local environment = getgenv and getgenv() or _G
local Action = assert(environment.__CLAW_MODULES["src/Combat/Action.lua"])

local DefenseEngine = {}
DefenseEngine.__index = DefenseEngine

function DefenseEngine.new(
	settings,
	state,
	timings,
	scheduler,
	executor,
	resolver,
	validator,
	probability,
	fallbacks,
	hitboxWaiter
)
	return setmetatable({
		Settings = settings,
		State = state,
		Timings = timings,
		Scheduler = scheduler,
		Executor = executor,
		Resolver = resolver,
		Validator = validator,
		Probability = probability,
		Fallbacks = fallbacks,
		HitboxWaiter = hitboxWaiter,
		Recent = {},
		Repeats = {},
		ModuleNotified = {},
		LastPrune = 0,
	}, DefenseEngine)
end

function DefenseEngine:_prune(now)
	if now - self.LastPrune < 5 then
		return
	end
	self.LastPrune = now
	for key, timestamp in pairs(self.Recent) do
		if now - timestamp > 2 then
			self.Recent[key] = nil
		end
	end
end

function DefenseEngine:_targetFor(entity, position)
	for _, target in ipairs(self.State.Targets) do
		if target.Character == entity then
			return target
		end
	end

	if typeof(position) ~= "Vector3" then
		return nil
	end

	local nearest
	local nearestDistance = math.huge
	for _, target in ipairs(self.State.Targets) do
		local distance = (target.Root.Position - position).Magnitude
		if distance < nearestDistance then
			nearest = target
			nearestDistance = distance
		end
	end
	return nearest
end

function DefenseEngine:_defaultAction()
	local preferred = self.Settings:get("Defense.Preferred")
	local allowPath = "Defense.Allow" .. preferred
	if self.Settings:get(allowPath) == false then
		preferred = self.Settings:get("Defense.Fallback")
	end
	return Action.new({ kind = preferred })
end

function DefenseEngine:_reject(reason)
	self.State:increment("Rejected")
	self.State:emit("action-rejected", reason)
	return false
end

function DefenseEngine:_waitForHitbox(key, event, profile, target, action)
	self.HitboxWaiter:wait(key, function()
		if event.track and not profile.ignoreAnimationEnd then
			local ok, playing = pcall(function()
				return event.track.IsPlaying
			end)
			if not ok or not playing then
				return false, "animation-ended"
			end
		end
		local inside = self.Validator:insideHitbox(event, profile, action)
		return inside
	end, function(ready, reason)
		if ready then
			self:_execute(key, event, profile, target, action, true)
		else
			self:_reject(reason)
		end
	end)
end

function DefenseEngine:_execute(key, event, profile, target, action, hitboxReady)
	local currentTarget = self:_targetFor(event.entity, event.position) or target
	if not currentTarget or not currentTarget.Root or not currentTarget.Root.Parent then
		return self:_reject("target-lost")
	end

	local valid, reason = self.Validator:validate(event, profile, currentTarget, action)
	local finalAction = action
	if not valid then
		if reason == "outside-hitbox" and profile.delayUntilHitbox and not hitboxReady then
			self:_waitForHitbox(key, event, profile, currentTarget, action)
			return true
		end
		finalAction = self.Fallbacks:resolve(action, reason, profile)
		if not finalAction then
			return self:_reject(reason)
		end
		local fallbackValid, fallbackReason = self.Validator:validate(event, profile, currentTarget, finalAction)
		if not fallbackValid then
			return self:_reject(fallbackReason)
		end
	end

	local ok, executeReason = self.Executor:execute(finalAction, {
		event = event,
		profile = profile,
		target = currentTarget,
	})
	if not ok then
		return self:_reject(executeReason)
	end
	return true
end

function DefenseEngine:_startRepeat(key, event, profile, target)
	if not profile.preferRepeat or profile.repeatDelay <= 0 then
		return
	end
	local token = {}
	local startedAt = os.clock()
	self.Repeats[key] = token

	local function queue(delay)
		self.Scheduler:schedule("repeat:" .. key, math.max(0.03, delay), {
			punishable = profile.punishableWindow,
			after = profile.afterWindow,
		}, function()
			if self.Repeats[key] ~= token then
				return
			end
			if os.clock() - startedAt >= 10 then
				self.Repeats[key] = nil
				return
			end
			if event.track then
				local ok, playing = pcall(function()
					return event.track.IsPlaying
				end)
				if not ok or not playing then
					self.Repeats[key] = nil
					return
				end
			end

			local action = Action.new({ kind = "Parry", name = profile.name .. " (repeat)" })
			local resolved, reason = self.Probability:resolve(action, profile)
			if resolved then
				self:_execute("repeat:" .. key, event, profile, target, resolved)
			else
				self:_reject(reason)
			end
			queue(profile.repeatDelay)
		end)
	end

	queue(profile.repeatStartDelay)
end

function DefenseEngine:reset()
	table.clear(self.Recent)
	table.clear(self.Repeats)
	table.clear(self.ModuleNotified)
	self.HitboxWaiter:cancelAll()
	self.LastPrune = 0
end

function DefenseEngine:handle(event)
	self.State:increment("Detected")
	self.State:emit("detected", event)

	if not self.Settings:get("Enabled") or not self.Settings:get("Defense.Enabled") then
		return false, "defense is disabled"
	end
	if event.entity == self.State.Character then
		return false, "ignored local character event"
	end

	local profile = self.Timings:get(event.detector, event.id)
	if not profile then
		return false, "no timing profile"
	end

	local target = self:_targetFor(event.entity, event.position)
	if not target then
		self.State:increment("Rejected")
		return false, "event entity is not a selected target"
	end

	local dedupeKey = string.format("%s:%s:%s", event.detector, event.id, tostring(event.entity or event.instance))
	local now = os.clock()
	self:_prune(now)
	if now - (self.Recent[dedupeKey] or 0) < 0.02 then
		return false, "duplicate event"
	end
	self.Recent[dedupeKey] = now
	self.State:emit("defense-profile", {
		event = event,
		profile = profile,
		target = target,
	})

	local actions = #profile.actions > 0 and profile.actions or { self:_defaultAction() }
	if profile.preferModule and #profile.actions == 0 and not self.ModuleNotified[profile.sourceModule] then
		self.ModuleNotified[profile.sourceModule] = true
		self.State:emit("module-fallback", {
			module = profile.sourceModule,
			profile = profile.name,
		})
	end
	for index, action in ipairs(actions) do
		local resolved, probabilityReason = self.Probability:resolve(action, profile)
		if not resolved then
			self.State:increment("Rejected")
			self.State:emit("action-rejected", probabilityReason)
			continue
		end

		local valid, validationReason = self.Validator:validate(event, profile, target, resolved, {
			skipHitbox = profile.delayUntilHitbox,
		})
		if not valid then
			resolved = self.Fallbacks:resolve(resolved, validationReason, profile)
			if not resolved then
				self.State:increment("Rejected")
				self.State:emit("action-rejected", validationReason)
				continue
			end
			local fallbackValid, fallbackReason = self.Validator:validate(event, profile, target, resolved)
			if not fallbackValid then
				self.State:increment("Rejected")
				self.State:emit("action-rejected", fallbackReason)
				continue
			end
		end

		local delay = self.Resolver:delay(resolved, event)
		local scheduledAction = resolved
		local stopConnection
		local scheduled = self.Scheduler:schedule(string.format("%s:%s:%d", event.detector, event.id, index), delay, {
			punishable = profile.punishableWindow,
			after = profile.afterWindow,
		}, function()
			if stopConnection then
				stopConnection:Disconnect()
				stopConnection = nil
			end
			self:_execute(scheduled.identifier, event, profile, target, scheduledAction)
		end)

		if event.track and not profile.ignoreAnimationEnd and not scheduledAction.metadata.ignoreAnimationEnd then
			stopConnection = event.track.Stopped:Connect(function()
				local elapsed = os.clock() - event.startedAt
				local ignoreEarly = profile.ignoreEarlyAnimationEnd
					and profile.maxAnimationTime > 0
					and elapsed < profile.maxAnimationTime
				if not ignoreEarly then
					self.Scheduler:cancel(scheduled, "animation ended")
				end
				if stopConnection then
					stopConnection:Disconnect()
					stopConnection = nil
				end
			end)
		end
	end

	self:_startRepeat(dedupeKey, event, profile, target)

	return true
end

return DefenseEngine

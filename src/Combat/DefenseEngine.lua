local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES
local Action = assert(modules["src/Combat/Action.lua"])
local TimingProfile = assert(modules["src/Combat/TimingProfile.lua"])
local DynamicWeaponResolver = assert(modules["src/Combat/DynamicWeaponResolver.lua"])

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
	hitboxWaiter,
	threats
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
		Threats = threats,
		Recent = {},
		GenericRecent = setmetatable({}, { __mode = "k" }),
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
	local function live(target)
		if not target or not target.Root or not target.Root.Parent then
			return nil
		end
		local localRoot = self.State.Root
		return {
			Character = target.Character,
			Player = target.Player,
			Humanoid = target.Humanoid,
			Root = target.Root,
			Distance = localRoot and (target.Root.Position - localRoot.Position).Magnitude or target.Distance,
			CrosshairDistance = target.CrosshairDistance,
			FacingDot = target.FacingDot,
			OnScreen = target.OnScreen,
			HealthRatio = target.HealthRatio,
		}
	end
	for _, target in ipairs(self.State.Targets) do
		if target.Character == entity then
			return live(target)
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
	return live(nearest)
end

function DefenseEngine:_defaultAction()
	local preferred = self.Settings:get("Defense.Preferred")
	local allowPath = "Defense.Allow" .. preferred
	if self.Settings:get(allowPath) == false then
		preferred = self.Settings:get("Defense.Fallback")
	end
	return Action.new({ kind = preferred })
end

function DefenseEngine:_unknownAnimationProfile(event)
	if event.detector ~= "animation" or not event.track or event.entity == self.State.Character then
		return nil, "not an enemy animation"
	end

	local ok, priority, looped, length = pcall(function()
		return event.track.Priority, event.track.Looped, event.track.Length
	end)
	if not ok then
		return nil, "animation properties unavailable"
	end
	local actionPriority = priority == Enum.AnimationPriority.Action
		or priority == Enum.AnimationPriority.Action2
		or priority == Enum.AnimationPriority.Action3
		or priority == Enum.AnimationPriority.Action4
	if not actionPriority then
		return nil, "non-combat animation priority"
	end
	if looped then
		return nil, "non-combat animation playback"
	end
	if length > 0 and length > self.Settings:get("Defense.UnknownAnimationMaxLength") then
		return nil, "animation is too long"
	end

	local default = self:_defaultAction()
	local weapon = DynamicWeaponResolver.weaponInfo(event)
	local speed = 1
	pcall(function()
		speed = math.max(0.05, math.abs(event.track.Speed))
	end)
	default.name = "Generic " .. default.kind .. ": " .. event.id
	default.delay = self.Settings:get("Defense.UnknownAnimationDelay") / speed
	default.ignoreHitbox = weapon == nil
	default.metadata.preserveDelay = weapon ~= nil
	local profile = TimingProfile.new({
		id = event.id,
		name = (weapon and "Unindexed weapon attack " or "Unindexed animation ") .. event.id,
		detector = "animation",
		tag = weapon and "M1" or "Undefined",
		maxDistance = math.min(
			self.Settings:get("Targeting.MaxDistance"),
			weapon and math.max(64, weapon.length * 4) or 100
		),
		delayUntilHitbox = weapon ~= nil,
		facingHitbox = weapon ~= nil,
		pastHitbox = weapon ~= nil,
		predictFacing = weapon ~= nil,
		historySeconds = weapon and self.Settings:get("Validation.PastHitboxSeconds") or 0,
		predictionSeconds = weapon and self.Settings:get("Validation.PredictionSeconds") or 0,
		sourceModule = weapon and "WeaponTest" or "",
		maxAnimationTime = 2,
		punishableWindow = self.Settings:get("Timing.DefaultPunishableWindow"),
		afterWindow = self.Settings:get("Timing.DefaultAfterWindow"),
		actions = { default },
	})
	profile.genericUnknown = true
	return profile, nil
end

function DefenseEngine:_dynamicAction(action, event)
	local metadata = action.metadata or {}
	if not metadata.actionFromTelegraph and not metadata.alternativeChild then
		return action
	end
	local resolved = action:clone()
	local attributes = event.metadata and event.metadata.attributes or {}
	if metadata.actionFromTelegraph then
		local telegraph = tostring(attributes.telegraph or attributes.Telegraph or "")
		resolved.kind = telegraph == "dodge_only" and "Dodge" or "Parry"
	end
	if metadata.alternativeChild and event.entity and event.entity:FindFirstChild(metadata.alternativeChild, true) then
		resolved.kind = metadata.alternativeKind or resolved.kind
		resolved.delay = tonumber(metadata.alternativeDelay) or resolved.delay
		local hitbox = metadata.alternativeHitbox
		if type(hitbox) == "table" then
			resolved.hitbox = Vector3.new(hitbox.X or 0, hitbox.Y or 0, hitbox.Z or 0)
		end
	end
	return resolved
end

function DefenseEngine:_reject(reason)
	local detail = tostring(reason)
	self.State:increment("Rejected")
	self.State.LastReject = {
		reason = detail,
		at = os.clock(),
	}
	self.State:emit("action-rejected", reason)
	return false, detail
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
	if not self.Settings:get("Enabled") or not self.Settings:get("Defense.Enabled") then
		return self:_reject("defense disabled before execution")
	end
	local currentTarget
	if event.entity == self.State.Character then
		currentTarget = {
			Character = self.State.Character,
			Root = self.State.Root,
			Humanoid = self.State.Humanoid,
			Distance = 0,
		}
	else
		currentTarget = self:_targetFor(event.entity, event.position)
	end
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
	local threatPlan
	if self.Threats then
		local admitted, claimed = self.Threats:claim(event, os.clock() + profile.repeatStartDelay)
		if not admitted then
			return
		end
		threatPlan = claimed
	end
	local token = {}
	local startedAt = os.clock()
	self.Repeats[key] = token

	local function queue(delay)
		local scheduled
		scheduled = self.Scheduler:schedule("repeat:" .. key, math.max(0.03, delay), {
			punishable = profile.punishableWindow,
			after = profile.afterWindow,
		}, function()
			if self.Repeats[key] ~= token then
				if self.Threats then
					self.Threats:settle(threatPlan, scheduled, "repeat replaced")
				end
				return
			end
			if os.clock() - startedAt >= 10 then
				self.Repeats[key] = nil
				if self.Threats then
					self.Threats:settle(threatPlan, scheduled, "repeat timeout")
				end
				return
			end
			if event.track then
				local ok, playing = pcall(function()
					return event.track.IsPlaying
				end)
				if not ok or not playing then
					self.Repeats[key] = nil
					if self.Threats then
						self.Threats:settle(threatPlan, scheduled, "repeat animation ended")
					end
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
			if self.Threats then
				self.Threats:settle(threatPlan, scheduled, "repeat advanced")
			end
		end)
		if self.Threats then
			self.Threats:register(threatPlan, scheduled)
		end
		scheduled.onCancel = function(reason)
			if self.Threats then
				self.Threats:settle(threatPlan, scheduled, reason or "repeat cancelled")
			end
		end
	end

	queue(profile.repeatStartDelay)
end

function DefenseEngine:reset()
	table.clear(self.Recent)
	table.clear(self.GenericRecent)
	table.clear(self.Repeats)
	table.clear(self.ModuleNotified)
	self.HitboxWaiter:cancelAll()
	if self.Threats then
		self.Threats:reset()
	end
	self.LastPrune = 0
end

function DefenseEngine:handle(event)
	self.State:increment("Detected")
	self.State.LastDetection = {
		detector = event.detector,
		id = event.id,
		entity = event.entity and event.entity.Name or "?",
		at = os.clock(),
	}
	self.State:emit("detected", event)

	if not self.Settings:get("Enabled") or not self.Settings:get("Defense.Enabled") then
		return false, "defense is disabled"
	end
	local profile = self.Timings:get(event.detector, event.id)
	if not profile then
		local reason
		profile, reason = self:_unknownAnimationProfile(event)
		if not profile then
			return self:_reject(reason or "no timing profile")
		end
		self.State:emit("generic-defense", {
			event = event,
			profile = profile,
		})
	end
	if self.Threats then
		local observed, observeReason = self.Threats:observe(event)
		if not observed then
			return false, observeReason
		end
	end
	if profile.genericUnknown then
		local now = os.clock()
		local lastGeneric = self.GenericRecent[event.entity]
		if lastGeneric and now - lastGeneric < 0.18 then
			return self:_reject("generic defense rearm")
		end
		local native = self.Executor.Input and self.Executor.Input.Native
		if native and native:isBusy() then
			return self:_reject("generic event while defense input active")
		end
		self.GenericRecent[event.entity] = now
	end
	profile = DynamicWeaponResolver.resolveProfile(profile, event)
	local localEvent = event.entity == self.State.Character
	if localEvent and profile.ignoreLocalPlayer then
		return self:_reject("ignored local character event")
	end
	if localEvent and not profile.allowLocalPlayer and not profile.forceLocalPlayer then
		return self:_reject("local character event is not allowed")
	end
	if profile.forceLocalPlayer and not localEvent then
		return self:_reject("effect is not on local character")
	end

	local target = localEvent
			and (self.State.PrimaryTarget or {
				Character = self.State.Character,
				Root = self.State.Root,
				Distance = 0,
			})
		or self:_targetFor(event.entity, event.position)
	if not target then
		return self:_reject("event entity is not a selected target")
	end

	local dedupeKey = string.format("%s:%s:%s", event.detector, event.id, tostring(event.entity or event.instance))
	local now = os.clock()
	self:_prune(now)
	if now - (self.Recent[dedupeKey] or 0) < 0.02 then
		return self:_reject("duplicate event")
	end
	self.Recent[dedupeKey] = now
	self.State:emit("defense-profile", {
		event = event,
		profile = profile,
		target = target,
	})

	local actions = #profile.actions > 0 and profile.actions
		or ((profile.preferRepeat or profile.suppressGeneric) and {} or { self:_defaultAction() })
	actions = DynamicWeaponResolver.resolve(profile, event, actions)
	if
		profile.preferModule
		and not profile.preferRepeat
		and not profile.suppressGeneric
		and #profile.actions == 0
		and not self.ModuleNotified[profile.sourceModule]
	then
		self.ModuleNotified[profile.sourceModule] = true
		self.State:emit("module-fallback", {
			module = profile.sourceModule,
			profile = profile.name,
		})
	end
	for index, action in ipairs(actions) do
		local resolved, probabilityReason = self.Probability:resolve(self:_dynamicAction(action, event), profile)
		if not resolved then
			self:_reject(probabilityReason)
			continue
		end

		local valid, validationReason = self.Validator:validate(event, profile, target, resolved, {
			-- Detection is an observation, not the impact frame.  Rushes, lunges,
			-- projectiles, and turning attacks routinely start outside their final
			-- hitbox/facing geometry.  Schedule them from the timing profile and
			-- perform the authoritative geometry checks at execution time.
			skipHitbox = true,
			skipFacing = true,
			skipTransient = true,
		})
		if not valid then
			resolved = self.Fallbacks:resolve(resolved, validationReason, profile)
			if not resolved then
				self:_reject(validationReason)
				continue
			end
			local fallbackValid, fallbackReason = self.Validator:validate(event, profile, target, resolved)
			if not fallbackValid then
				self:_reject(fallbackReason)
				continue
			end
		end

		local delay = self.Resolver:delay(resolved, event, target)
		local scheduledAction = resolved
		local threatPlan
		if self.Threats then
			local admitted, claimed = self.Threats:claim(event, os.clock() + delay)
			if not admitted then
				continue
			end
			threatPlan = claimed
		end
		self.State.LastPlan = {
			kind = scheduledAction.kind,
			name = scheduledAction.name,
			profile = profile.name,
			distance = target.Distance,
			delay = delay,
			at = os.clock(),
		}
		self.State:emit("incoming-action", {
			event = event,
			profile = profile,
			action = scheduledAction,
			delay = delay,
			target = target,
		})
		local stopConnection
		-- Predeclare the handle so the delayed closure captures this local. In
		-- Lua/Luau a local is not in scope inside its own initializer, which made
		-- `scheduled` resolve to nil when the callback eventually ran.
		local scheduled
		scheduled = self.Scheduler:schedule(string.format("%s:%s:%d", event.detector, event.id, index), delay, {
			punishable = profile.punishableWindow,
			after = profile.afterWindow,
		}, function()
			if stopConnection then
				stopConnection:Disconnect()
				stopConnection = nil
			end
			local executionKey = scheduled.identifier .. ":" .. tostring(scheduled.id)
			local called, ok, detail = pcall(
				self._execute,
				self,
				executionKey,
				event,
				profile,
				target,
				scheduledAction
			)
			if self.Threats then
				self.Threats:settle(threatPlan, scheduled, called and (detail or "executed") or "execution error")
			end
			if not called then
				error(ok, 0)
			end
			return ok, detail
		end)
		if self.Threats then
			self.Threats:register(threatPlan, scheduled)
		end
		scheduled.onCancel = function(reason)
			if stopConnection then
				stopConnection:Disconnect()
				stopConnection = nil
			end
			if self.Threats then
				self.Threats:settle(threatPlan, scheduled, reason or "plan cancelled")
			end
		end

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

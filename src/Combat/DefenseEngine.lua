local environment = getgenv and getgenv() or _G
local Action = assert(environment.__CLAW_MODULES["src/Combat/Action.lua"])

local DefenseEngine = {}
DefenseEngine.__index = DefenseEngine

function DefenseEngine.new(settings, state, timings, scheduler, executor, resolver)
	return setmetatable({
		Settings = settings,
		State = state,
		Timings = timings,
		Scheduler = scheduler,
		Executor = executor,
		Resolver = resolver,
	}, DefenseEngine)
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

	local actions = #profile.actions > 0 and profile.actions or { self:_defaultAction() }
	for index, action in ipairs(actions) do
		local delay = self.Resolver:delay(action, event)
		self.Scheduler:schedule(
			string.format("%s:%s:%d", event.detector, event.id, index),
			delay,
			{
				punishable = profile.punishableWindow,
				after = profile.afterWindow,
			},
			function()
				local ok, reason = self.Executor:execute(action, {
					event = event,
					profile = profile,
					target = target,
				})
				if not ok then
					self.State:increment("Rejected")
					self.State:emit("action-rejected", reason)
				end
			end
		)
	end

	return true
end

return DefenseEngine

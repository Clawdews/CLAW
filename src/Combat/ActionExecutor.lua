local ActionExecutor = {}
ActionExecutor.__index = ActionExecutor

local KEY_BINDINGS = {
	Parry = Enum.KeyCode.F,
	Block = Enum.KeyCode.F,
	Dodge = Enum.KeyCode.Q,
	FullDodge = Enum.KeyCode.Q,
	Jump = Enum.KeyCode.Space,
	Slide = Enum.KeyCode.LeftControl,
	Crouch = Enum.KeyCode.LeftControl,
}

local DEFAULT_COOLDOWNS = {
	Parry = 0.075,
	Block = 0.075,
	Dodge = 0.20,
	FullDodge = 0.25,
	Jump = 0.10,
	Slide = 0.10,
	Crouch = 0.10,
	Feint = 0.075,
	M1 = 0.075,
}

function ActionExecutor.new(settings, state, input)
	return setmetatable({
		Settings = settings,
		State = state,
		Input = input,
		Cooldowns = DEFAULT_COOLDOWNS,
	}, ActionExecutor)
end

function ActionExecutor:canExecute(action)
	local readyAt = self.State.Cooldowns[action.kind] or 0
	return os.clock() >= readyAt
end

function ActionExecutor:_markCooldown(action)
	local duration = tonumber(action.metadata.cooldown) or self.Cooldowns[action.kind] or 0
	self.State.Cooldowns[action.kind] = os.clock() + math.max(0, duration)
end

function ActionExecutor:execute(action, context)
	if not self:canExecute(action) then
		return false, "action is on cooldown"
	end
	if not action:shouldRun() then
		return false, "probability rejected action"
	end

	local kind = action.kind
	local duration = action.duration
	if duration <= 0 then
		duration = kind == "Block" and self.Settings:get("Defense.BlockFallbackHold")
			or kind == "FullDodge" and 0.18
			or 0.035
	end
	local success, result

	if (kind == "Dodge" or kind == "FullDodge") and self.Settings:get("Defense.DirectRoll") then
		success, result = self.Input:custom("DirectDodge", action, context)
		if not success then
			success, result = self.Input:tapKey(KEY_BINDINGS[kind], duration)
		end
	elseif KEY_BINDINGS[kind] then
		success, result = self.Input:tapKey(KEY_BINDINGS[kind], duration)
	elseif kind == "Feint" then
		success, result = self.Input:tapMouse(1, duration)
	elseif kind == "M1" then
		success, result = self.Input:tapMouse(0, duration)
	else
		local customName = action.metadata.customName or kind
		success, result = self.Input:custom(customName, action, context)
	end

	if not success then
		return false, result
	end

	self:_markCooldown(action)
	self.State:emit("action", {
		action = action,
		context = context,
	})

	if (kind == "Dodge" or kind == "FullDodge") and self.Settings:get("Defense.RollCancel") then
		task.delay(self.Settings:get("Defense.RollCancelDelay"), function()
			self.Input:tapMouse(1, 0.035)
		end)
	end

	return true
end

return ActionExecutor

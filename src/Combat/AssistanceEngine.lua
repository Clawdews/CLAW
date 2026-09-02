local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES
local Action = assert(modules["src/Combat/Action.lua"])

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local AssistanceEngine = {}
AssistanceEngine.__index = AssistanceEngine

local DELAYED_FEINT_ACTION = "CLAW_MARK_DELAYED_FEINT"

local function cleanID(value)
	return tostring(value or ""):match("(%d+)") or tostring(value or "")
end

local function includes(list, value)
	for _, item in ipairs(list or {}) do
		if item == value then
			return true
		end
	end
	return false
end

function AssistanceEngine.new(settings, state, timings, scheduler, input, executor)
	return setmetatable({
		Settings = settings,
		State = state,
		Timings = timings,
		Scheduler = scheduler,
		Input = input,
		Executor = executor,
		Connections = {},
		CharacterConnections = {},
		ActiveAttack = nil,
		Cooldowns = {},
		Running = false,
		Random = Random.new(),
		HoldingM1 = false,
	}, AssistanceEngine)
end

function AssistanceEngine:_bind(list, signal, callback)
	local connection = signal:Connect(callback)
	list[#list + 1] = connection
	return connection
end

function AssistanceEngine:_disconnect(list)
	for _, connection in ipairs(list) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(list)
end

function AssistanceEngine:_ready(name, cooldown)
	local now = os.clock()
	if now < (self.Cooldowns[name] or 0) then
		return false
	end
	self.Cooldowns[name] = now + (cooldown or self.Settings:get("CombatAssistance.AssistanceCooldown"))
	return true
end

function AssistanceEngine:_custom(name, delay)
	if not self:_ready(name) then
		return
	end
	self.Scheduler:schedule("assist:" .. name, delay or 0, {}, function()
		local ok, reason = self.Input:custom(name, self.State)
		self.State:emit(ok and "assistance" or "assistance-unavailable", {
			name = name,
			reason = reason,
		})
	end)
end

function AssistanceEngine:_roll(trigger)
	local attack = self.Settings:get("AttackAssistance")
	if not attack.ActionRolling or not includes(attack.ActionRollingActions, trigger) then
		return
	end
	if not self:_ready("ActionRoll", attack.ActionRollCooldown) then
		return
	end

	local action = Action.new({ kind = "Dodge", name = "Action Roll: " .. trigger })
	local ok, reason = self.Executor:execute(action, { trigger = trigger })
	if ok and attack.ActionRollCancelDelay >= 0 then
		task.delay(attack.ActionRollCancelDelay, function()
			self.Input:tapMouse(1, 0.035)
		end)
	elseif not ok then
		self.State:emit("assistance-unavailable", { name = "ActionRoll", reason = reason })
	end
end

function AssistanceEngine:_speed(track, profile)
	local options = self.Settings:get("AttackAssistance.AnimationSpeed")
	if not options.Enabled or (options.LimitToConfigured and not profile) then
		return
	end

	local minimum = math.min(options.Minimum, options.Maximum)
	local maximum = math.max(options.Minimum, options.Maximum)
	local speed
	if options.SwitchExtremes then
		speed = self.Random:NextInteger(0, 1) == 0 and minimum or maximum
	else
		speed = self.Random:NextNumber(minimum, maximum)
	end
	pcall(function()
		track:AdjustSpeed(speed)
	end)
end

function AssistanceEngine:_feint(profile, name)
	local attack = self.Settings:get("AttackAssistance")
	if not attack.AutoFeint then
		return
	end
	if attack.AutoFeintMode == "Passive" and #self.State.Targets == 0 then
		return
	end

	local delay = attack.FeintDelay
	if profile and profile.actions[1] then
		delay = math.max(0, profile.actions[1].delay - attack.FeintLead)
	end
	self.Scheduler:schedule("assist:auto-feint", delay, {}, function()
		self.Executor:execute(Action.new({ kind = "Feint", name = name or "Auto Feint" }), {
			profile = profile,
		})
	end)
end

function AssistanceEngine:_onAnimation(track)
	local animation = track.Animation
	local id = cleanID(animation and animation.AnimationId)
	local profile = self.Timings:get("animation", id)

	local clawMark = environment.__CLAW_MARK or environment.__ANIM_LAB_V6
	if clawMark and clawMark.OwnGhostTracks and clawMark.OwnGhostTracks[track] then
		return
	end

	self:_speed(track, profile)
	if not profile then
		return
	end

	local tag = string.lower(profile.tag or "")
	local name = string.lower(profile.name or "")
	local isAttack = tag == "m1" or tag == "critical" or tag == "mantra" or tag == "flourish"
	if not isAttack then
		return
	end

	self.ActiveAttack = { track = track, profile = profile }
	if self.Settings:get("AttackAssistance.HoldM1") and not self.HoldingM1 then
		self.HoldingM1 = self.Input:mouse(0, true) == true
	end
	self:_bind(self.CharacterConnections, track.Stopped, function()
		if self.ActiveAttack and self.ActiveAttack.track == track then
			self.ActiveAttack = nil
			if self.HoldingM1 then
				self.Input:mouse(0, false)
				self.HoldingM1 = false
			end
		end
	end)

	self:_feint(profile, "Auto Feint: " .. profile.name)
	if
		self.Settings:get("AttackAssistance.FlourishFeint")
		and (tag == "flourish" or string.find(name, "flourish", 1, true))
	then
		self.Scheduler:schedule("assist:flourish-feint", 0, {}, function()
			self.Executor:execute(Action.new({ kind = "Feint", name = "Flourish Feint" }))
		end)
	end

	if tag == "m1" then
		self:_roll("M1")
	elseif tag == "critical" then
		self:_roll("Critical")
	elseif tag == "mantra" then
		self:_roll("Cast")
	end

	if
		self.Settings:get("CombatAssistance.FlowState")
		and (string.find(tag, "silentheart", 1, true) or string.find(name, "silentheart", 1, true))
	then
		self:_custom("FlowState")
	end
end

function AssistanceEngine:_attach(character)
	self:_disconnect(self.CharacterConnections)
	self.ActiveAttack = nil
	if not character then
		return
	end

	local function hookAnimator(animator)
		self:_bind(self.CharacterConnections, animator.AnimationPlayed, function(track)
			self:_onAnimation(track)
		end)
	end

	local animator = character:FindFirstChildWhichIsA("Animator", true)
	if animator then
		hookAnimator(animator)
	end
	self:_bind(self.CharacterConnections, character.DescendantAdded, function(descendant)
		if descendant:IsA("Animator") and not animator then
			animator = descendant
			hookAnimator(descendant)
		end
	end)
end

function AssistanceEngine:_onFlag(payload)
	if payload.name == "Ragdolled" and payload.value and self.Settings:get("CombatAssistance.RagdollResponse") then
		self:_custom("RagdollRecover")
	elseif
		payload.name == "WispCooldown"
		and not payload.value
		and not self.State.Flags.WispActive
		and self.Settings:get("CombatAssistance.Wisp")
	then
		self:_custom("Wisp", self.Settings:get("CombatAssistance.WispDelay"))
	elseif
		payload.name == "GoldenTongueCooldown"
		and payload.value
		and self.Settings:get("CombatAssistance.GoldenTongue")
	then
		if not self.Settings:get("CombatAssistance.GoldenTongueCombatOnly") or self.State.Flags.InCombat then
			self:_custom("GoldenTongue")
		end
	elseif payload.name == "UsingMantra" and payload.value and self.Settings:get("CombatAssistance.MantraFollowUp") then
		if not self.Settings:get("CombatAssistance.MantraFollowUpRequireHit") or self.State.Flags.DamagedAnother then
			self:_custom("MantraFollowUp")
		end
	elseif
		(payload.name == "WeaponEquipped" or payload.name == "ArdourActive")
		and self.State.Flags.WeaponEquipped
		and not self.State.Flags.ArdourActive
		and self.Settings:get("CombatAssistance.Ardour")
	then
		self:_custom("Ardour")
	end
end

function AssistanceEngine:_delayedFeint(_, inputState)
	if
		inputState ~= Enum.UserInputState.Begin
		or not self.Settings:get("AttackAssistance.DelayedFeint")
		or not self.ActiveAttack
	then
		return Enum.ContextActionResult.Pass
	end

	local profile = self.ActiveAttack.profile
	local delay = self.Settings:get("AttackAssistance.FeintDelay")
	if profile.actions[1] then
		delay = math.max(0, profile.actions[1].delay - self.Settings:get("AttackAssistance.FeintLead"))
	end
	self.Scheduler:schedule("assist:delayed-feint", delay, {}, function()
		self.Executor:execute(Action.new({ kind = "Feint", name = "Delayed Feint" }))
	end)
	return Enum.ContextActionResult.Sink
end

function AssistanceEngine:_onSetting(payload)
	if payload.path == "CombatAssistance.Rhythm" and payload.value then
		self:_custom("Rhythm")
	elseif payload.path == "AttackAssistance.HoldM1" and not payload.value and self.HoldingM1 then
		self.Input:mouse(0, false)
		self.HoldingM1 = false
	elseif
		payload.path == "CombatAssistance.Wisp"
		and payload.value
		and not self.State.Flags.WispCooldown
		and not self.State.Flags.WispActive
	then
		self:_custom("Wisp", self.Settings:get("CombatAssistance.WispDelay"))
	elseif
		payload.path == "CombatAssistance.Ardour"
		and payload.value
		and self.State.Flags.WeaponEquipped
		and not self.State.Flags.ArdourActive
	then
		self:_custom("Ardour")
	end
end

function AssistanceEngine:start()
	if self.Running then
		return
	end
	self.Running = true
	self:_bind(self.Connections, Players.LocalPlayer.CharacterAdded, function(character)
		self:_attach(character)
	end)
	self:_bind(self.Connections, self.State.Event, function(event)
		if event.kind == "flag" then
			self:_onFlag(event.payload)
		elseif event.kind == "setting" then
			self:_onSetting(event.payload)
		elseif event.kind == "action" and event.payload.action.kind == "Parry" then
			self:_roll("Parry")
		end
	end)
	self:_bind(self.Connections, UserInputService.InputBegan, function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_roll("M1")
		end
	end)
	ContextActionService:BindActionAtPriority(DELAYED_FEINT_ACTION, function(...)
		return self:_delayedFeint(...)
	end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton2)
	self:_attach(Players.LocalPlayer.Character)
end

function AssistanceEngine:stop()
	if not self.Running then
		return
	end
	self.Running = false
	ContextActionService:UnbindAction(DELAYED_FEINT_ACTION)
	self:_disconnect(self.CharacterConnections)
	self:_disconnect(self.Connections)
	self.ActiveAttack = nil
	if self.HoldingM1 then
		self.Input:mouse(0, false)
		self.HoldingM1 = false
	end
	table.clear(self.Cooldowns)
end

function AssistanceEngine:Destroy()
	self:stop()
end

return AssistanceEngine

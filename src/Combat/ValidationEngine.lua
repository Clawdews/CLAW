local environment = getgenv and getgenv() or _G
local UserInputService = game:GetService("UserInputService")

local ValidationEngine = {}
ValidationEngine.__index = ValidationEngine

local ACTION_SETTING = {
	Parry = "Defense.AllowParry",
	Block = "Defense.AllowBlock",
	Dodge = "Defense.AllowDodge",
	FullDodge = "Defense.AllowFullDodge",
	Jump = "Defense.AllowJump",
	Slide = "Defense.AllowSlide",
	Crouch = "Defense.AllowCrouch",
	Teleport = "Defense.AllowTeleport",
}

local function hasState(character, names)
	if not character then
		return false
	end
	for _, name in ipairs(names) do
		if character:GetAttribute(name) == true or character:FindFirstChild(name) then
			return true
		end
	end
	return false
end

function ValidationEngine.new(settings, state, history, executor)
	return setmetatable({
		Settings = settings,
		State = state,
		History = history,
		Executor = executor,
	}, ValidationEngine)
end

function ValidationEngine:_sourceCFrame(event, profile)
	local source
	if event.root and event.root.Parent then
		source = event.root.CFrame
	elseif event.instance and event.instance:IsA("BasePart") then
		source = event.instance.CFrame
	end
	if not source or not profile or profile.disablePrediction or not self.Settings:get("Validation.Prediction") then
		return source
	end

	local seconds = profile.predictionSeconds > 0 and profile.predictionSeconds
		or self.Settings:get("Validation.PredictionSeconds")
	local movingPart = event.root or (event.instance and event.instance:IsA("BasePart") and event.instance)
	if movingPart then
		source = source + (movingPart.AssemblyLinearVelocity * seconds)
	end
	if profile.predictFacing and event.entity then
		source = source * CFrame.Angles(0, self.History:yawRate(event.entity) * seconds, 0)
	end
	return source
end

function ValidationEngine:_filtered(profile)
	local filters = self.Settings:get("Filters")
	local tag = string.lower(profile.tag or "")
	if filters.M1 and tag == "m1" then
		return true, "filtered-m1"
	end
	if filters.Mantra and tag == "mantra" then
		return true, "filtered-mantra"
	end
	if filters.Critical and tag == "critical" then
		return true, "filtered-critical"
	end
	if filters.Undefined and (tag == "" or tag == "undefined") then
		return true, "filtered-undefined"
	end
	if filters.TextboxFocused and UserInputService:GetFocusedTextBox() then
		return true, "textbox-focused"
	end
	if filters.HoldingBlock and UserInputService:IsKeyDown(Enum.KeyCode.F) then
		return true, "holding-block"
	end
	if filters.WindowInactive then
		local isActive = rawget(environment, "isrbxactive")
		if type(isActive) == "function" then
			local ok, active = pcall(isActive)
			if ok and not active then
				return true, "window-inactive"
			end
		end
	end
	if filters.ChimeCountdown and self.State.Flags.ChimeCountdown then
		return true, "chime-countdown"
	end
	return false
end

function ValidationEngine:_trackValid(event)
	if event.detector ~= "animation" or not event.track then
		return true
	end

	local ok, speed, length = pcall(function()
		return math.abs(event.track.Speed), event.track.Length
	end)
	if not ok then
		return false, "animation-unavailable"
	end

	local validation = self.Settings:get("Validation")
	if speed < validation.MinAnimationSpeed or speed > validation.MaxAnimationSpeed then
		return false, "animation-speed"
	end
	if length > 0 and (length < validation.MinAnimationLength or length > validation.MaxAnimationLength) then
		return false, "animation-length"
	end
	return true
end

function ValidationEngine:_insideHitbox(event, profile, action)
	local hitbox = action.hitbox.Magnitude > 0 and action.hitbox or profile.hitbox
	if action.ignoreHitbox or not self.Settings:get("Validation.Hitbox") or hitbox.Magnitude <= 0 then
		return true
	end

	local source = self:_sourceCFrame(event, profile)
	local localRoot = self.State.Root
	if not source or not localRoot then
		return false, "missing-hitbox-origin"
	end

	local localFrame = localRoot.CFrame
	if self.Settings:get("Validation.Prediction") and not profile.disablePrediction then
		local seconds = profile.predictionSeconds > 0 and profile.predictionSeconds
			or self.Settings:get("Validation.PredictionSeconds")
		localFrame = self.History:predict(self.State.Character, seconds) or localFrame
	end

	local half = hitbox * 0.5
	local function contains(frame)
		local relative = source:PointToObjectSpace(frame.Position)
		local shiftedZ = relative.Z + profile.hitboxOffset
		return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(shiftedZ) <= half.Z
	end

	local inside = contains(localFrame)
	if not inside and profile.pastHitbox then
		local seconds = profile.historySeconds > 0 and profile.historySeconds
			or self.Settings:get("Validation.PastHitboxSeconds")
		inside = self.History:anyRecent(self.State.Character, seconds, function(record)
			return contains(record.cframe)
		end)
	end
	return inside, inside and nil or "outside-hitbox"
end

function ValidationEngine:insideHitbox(event, profile, action)
	return self:_insideHitbox(event, profile, action)
end

function ValidationEngine:_facing(event, profile)
	if not self.Settings:get("Validation.Facing") or not profile.facingHitbox then
		return true
	end
	local source = self:_sourceCFrame(event, profile)
	if not source or not self.State.Root then
		return false, "missing-facing-origin"
	end
	local direction = self.State.Root.Position - source.Position
	if direction.Magnitude <= 0.001 then
		return true
	end
	local facing = source.LookVector:Dot(direction.Unit) > -0.15
	return facing, facing and nil or "not-facing"
end

function ValidationEngine:_visible(event, profile)
	if not self.Settings:get("Validation.Visibility") then
		return true
	end
	local source = self:_sourceCFrame(event, profile)
	if not source or not self.State.Root then
		return false, "missing-visibility-origin"
	end

	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { self.State.Character, event.entity }
	local direction = self.State.Root.Position - source.Position
	local visible = workspace:Raycast(source.Position, direction, parameters) == nil
	return visible, visible and nil or "occluded"
end

function ValidationEngine:validate(event, profile, target, action, options)
	options = options or {}
	local debugState = self.Settings:get("DebugState")
	if
		(action.kind == "Parry" and debugState.BlockParry)
		or ((action.kind == "Dodge" or action.kind == "FullDodge") and debugState.BlockDodge)
		or (action.name == "Vent" and debugState.BlockVent)
		or (action.kind == "Block" and debugState.NoBlocking)
	then
		return false, "debug-state-block"
	end

	local filtered, filterReason = self:_filtered(profile)
	if filtered then
		return false, filterReason
	end

	local settingPath = ACTION_SETTING[action.kind]
	if settingPath and not self.Settings:get(settingPath) then
		return false, "action-disabled"
	end
	if self.Settings:get("Validation.Cooldown") and not self.Executor:canExecute(action) then
		return false, "cooldown"
	end

	local character = self.State.Character
	if
		self.Settings:get("Validation.IFrames")
		and hasState(character, { "IFrame", "Invulnerable", "Dodging", "Immortal" })
	then
		return false, "iframes"
	end
	if
		action.kind == "Parry"
		and self.Settings:get("Validation.AutoParryFrames")
		and self.State.Flags.AutoParryFrames
	then
		return false, "auto-parry-frames"
	end
	if
		self.Settings:get("Validation.Stun")
		and hasState(character, { "Stun", "Stunned", "Knocked", "Unconscious", "Carried" })
	then
		return false, "stunned"
	end
	if self.State.Flags.Attacking and not profile.allowAttacking then
		return false, "already-attacking"
	end

	local trackValid, trackReason = self:_trackValid(event)
	if not trackValid then
		return false, trackReason
	end

	local maximumDistance = profile.maxDistance > 0 and profile.maxDistance
		or self.Settings:get("Targeting.MaxDistance")
	if target.Distance < profile.minDistance or target.Distance > maximumDistance then
		return false, "distance"
	end

	if not options.skipHitbox then
		local inside, hitboxReason = self:_insideHitbox(event, profile, action)
		if not inside then
			return false, hitboxReason
		end
	end
	local facing, facingReason = self:_facing(event, profile)
	if not facing then
		return false, facingReason
	end
	local visible, visibleReason = self:_visible(event, profile)
	if not visible then
		return false, visibleReason
	end

	return true
end

return ValidationEngine

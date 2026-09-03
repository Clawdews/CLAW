local environment = getgenv and getgenv() or _G
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

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
	if profile and profile.useHitboxCFrame and event.instance and event.instance:IsA("BasePart") then
		source = event.instance.CFrame
	elseif event.root and event.root.Parent then
		source = event.root.CFrame
	elseif event.instance and event.instance:IsA("BasePart") then
		source = profile and profile.useHitboxCFrame and event.instance.CFrame or CFrame.new(event.instance.Position)
	end
	if not source or not profile or profile.disablePrediction or not self.Settings:get("Validation.Prediction") then
		return source
	end

	local seconds = profile.predictionSeconds > 0 and profile.predictionSeconds
		or self.Settings:get("Validation.PredictionSeconds")
	local movingPart = profile.useHitboxCFrame
		and event.instance
		and event.instance:IsA("BasePart")
		and event.instance
		or event.root
		or (event.instance and event.instance:IsA("BasePart") and event.instance)
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
	if filters.SightlessBeam and self.State.Flags.SightlessBeam then
		return true, "sightless-beam"
	end
	return false
end

function ValidationEngine:_trackValid(event)
	if not self.Settings:get("Validation.AnimationSanity") or event.detector ~= "animation" or not event.track then
		return true
	end
	if event.metadata and event.metadata.playerMobAnimation then
		return false, "player-mob-animation"
	end

	local ok, speed, length = pcall(function()
		return math.abs(event.track.Speed), event.track.Length
	end)
	if not ok then
		return false, "animation-unavailable"
	end

	local validation = self.Settings:get("Validation")
	local okProperties, priority, weightTarget = pcall(function()
		return event.track.Priority, event.track.WeightTarget
	end)
	if not okProperties then
		return false, "animation-properties"
	end
	if priority == Enum.AnimationPriority.Core then
		return false, "core-priority-animation"
	end
	-- AnimationPlayed can fire at weight zero during the first blend frame. Let
	-- the scheduler accept that fresh event; execution revalidates after the
	-- configured delay and rejects tracks that never actually blended in.
	local eventAge = os.clock() - (event.startedAt or os.clock())
	if
		event.entity
		and Players:GetPlayerFromCharacter(event.entity)
		and (tonumber(weightTarget) or 0) <= 0.05
		and eventAge > 0.10
	then
		return false, "low-weight-animation"
	end
	if
		speed < validation.MinAnimationSpeed
		or (validation.MaxAnimationSpeed > 0 and speed >= validation.MaxAnimationSpeed)
	then
		return false, "animation-speed"
	end
	if
		length > 0
		and (
			length < validation.MinAnimationLength
			or (validation.MaxAnimationLength > 0 and length > validation.MaxAnimationLength)
		)
	then
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
	local function contains(sourceFrame, targetFrame)
		local relative = sourceFrame:PointToObjectSpace(targetFrame.Position)
		-- Lycoris's fhb is a hitbox-center offset, not a directional
		-- validation switch. hso is positive backwards and negative forwards.
		local shiftedZ = relative.Z + (profile.facingHitbox and half.Z or 0) - profile.hitboxOffset
		return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(shiftedZ) <= half.Z
	end

	local inside = contains(source, localFrame)
	if not inside and profile.forceFacingTarget and self.State.Root then
		local direction = self.State.Root.Position - source.Position
		if direction.Magnitude > 0.001 then
			inside = contains(CFrame.lookAt(source.Position, self.State.Root.Position), localFrame)
		end
	end
	if not inside and profile.pastHitbox then
		local seconds = profile.historySeconds > 0 and profile.historySeconds
			or self.Settings:get("Validation.PastHitboxSeconds")
		-- Past-hitbox detection replays the attacker's recent hitboxes against
		-- our current position. Replaying our own history against the current
		-- attacker position reverses the intended test.
		inside = self.History:anyRecent(event.entity, seconds, function(record)
			return contains(record.cframe, localFrame)
		end)
	end
	return inside, inside and nil or "outside-hitbox"
end

function ValidationEngine:insideHitbox(event, profile, action)
	return self:_insideHitbox(event, profile, action)
end

function ValidationEngine:_facing(event, profile)
	if not self.Settings:get("Validation.Facing") then
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
	if not options.skipTransient then
		if self.Settings:get("Validation.Cooldown") and not self.Executor:canExecute(action) then
			return false, "cooldown"
		end

		-- The local executor cooldown only tells us when CLAW last sent an input.
		-- Deepwoken's replicated effects are the authoritative answer at the
		-- scheduled execution moment. Planning deliberately skips this block so
		-- a future parry does not become an immediate dodge while ParryCool is
		-- still active at detection time.
		local native = self.Executor.Input and self.Executor.Input.Native
		if action.kind == "Parry" and native then
			local canParry, parryReason = native:canParry()
			if not canParry then
				return false, parryReason
			end
		elseif (action.kind == "Dodge" or action.kind == "FullDodge") and native then
			local canDodge, dodgeReason = native:canDodge()
			if not canDodge then
				return false, dodgeReason
			end
		end
	end

	local character = self.State.Character
	if
		not options.skipTransient
		and
		self.Settings:get("Validation.IFrames")
		and hasState(character, { "IFrame", "Invulnerable", "Dodging", "Immortal" })
	then
		return false, "iframes"
	end
	if
		not options.skipTransient
		and
		action.kind == "Parry"
		and self.Settings:get("Validation.AutoParryFrames")
		and self.State.Flags.AutoParryFrames
	then
		return false, "auto-parry-frames"
	end
	if
		not options.skipTransient
		and
		self.Settings:get("Validation.Stun")
		and hasState(character, { "Stun", "Stunned", "Knocked", "Unconscious", "Carried" })
	then
		return false, "stunned"
	end
	if
		not options.skipTransient
		and self.State.Flags.Attacking
		and not profile.allowAttacking
		and not self.Settings:get("Defense.DefendWhileAttacking")
	then
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
	if not options.skipFacing then
		local facing, facingReason = self:_facing(event, profile)
		if not facing then
			return false, facingReason
		end
	end
	local visible, visibleReason = self:_visible(event, profile)
	if not visible then
		return false, visibleReason
	end

	return true
end

return ValidationEngine

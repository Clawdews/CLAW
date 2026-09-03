local Settings = {}
Settings.__index = Settings

local DEFAULTS = {
	Enabled = false,
	Targeting = {
		Selection = "ClosestDistance",
		MaxTargets = 4,
		MaxDistance = 3000,
		FOVDegrees = 360,
		ScanInterval = 0.05,
		IgnorePlayers = false,
		IgnoreMobs = false,
		CheckMobTarget = false,
		IgnoreAllies = false,
		RequireOnScreen = false,
		Whitelist = {},
		WhitelistMode = "Exclude",
		Blacklist = {},
	},
	Detection = {
		Animations = true,
		Sounds = true,
		Parts = true,
		Effects = true,
		Projectiles = true,
		OnlyConfigured = true,
		UnknownAnimations = true,
	},
	Defense = {
		Enabled = false,
		Preferred = "Parry",
		Fallback = "Dodge",
		UnknownAnimationDelay = 0.16,
		UnknownAnimationMaxLength = 10,
		AllowParry = true,
		AllowBlock = true,
		AllowDodge = true,
		AllowFullDodge = true,
		AllowJump = true,
		AllowSlide = true,
		AllowCrouch = true,
		AllowTeleport = false,
		RollCancel = false,
		DirectRoll = false,
		RollCancelDelay = 0.08,
		BlockFallbackHold = 0.30,
		RollOnParryCooldown = false,
		DodgeFallback = false,
		VentFallback = false,
		BlockFallback = false,
		ParryOnly = false,
		UsePredictionMantra = false,
		UsePunishmentMantra = false,
	},
	ThreatGuard = {
		Enabled = true,
		BurstWindow = 0.35,
		BurstLimit = 8,
		QuarantineSeconds = 1.25,
		MaxPendingPerSource = 2,
		PlanSeparation = 0.08,
		SourceRearm = 0.16,
		SameAnimationRearm = 0.30,
		ChurnWindow = 2.00,
		ChurnLimit = 5,
		AbortWindow = 1.50,
		AbortLimit = 3,
	},
	Timing = {
		Profile = "Balanced",
		GlobalOffset = 0,
		PingCompensation = true,
		PingScale = 0.50,
		MinDelay = 0,
		MaxDelay = 3,
		DefaultPunishableWindow = 0.70,
		DefaultAfterWindow = 0.12,
		HitboxPollInterval = 0.03,
		MaxHitboxWait = 10,
	},
	Validation = {
		Hitbox = true,
		Facing = false,
		Visibility = false,
		Stun = true,
		Cooldown = true,
		IFrames = false,
		AutoParryFrames = false,
		Prediction = true,
		PredictionSeconds = 0.10,
		HistorySeconds = 3,
		PastHitboxSeconds = 0.20,
		MinAnimationSpeed = 0,
		AnimationSanity = true,
		MaxAnimationSpeed = 1000,
		MinAnimationLength = 0,
		MaxAnimationLength = 0,
	},
	Filters = {
		M1 = false,
		Mantra = false,
		Critical = false,
		Undefined = false,
		TextboxFocused = false,
		WindowInactive = false,
		HoldingBlock = false,
		ChimeCountdown = false,
		SightlessBeam = false,
	},
	Probability = {
		Enabled = false,
		AllowFailure = false,
		FailureRate = 0,
		DashInsteadOfParryRate = 0,
		IgnoreAnimationEndRate = 0,
		Parry = 100,
		Block = 100,
		Dodge = 100,
		Feint = 100,
	},
	AttackAssistance = {
		AutoFeint = false,
		AutoFeintMode = "Passive",
		DelayedFeint = false,
		FeintDelay = 0.12,
		FeintLead = 0.04,
		HoldM1 = false,
		FlourishFeint = false,
		ActionRolling = false,
		ActionRollingActions = {},
		ActionRollCancelDelay = 0.10,
		ActionRollCooldown = 2,
		AnimationSpeed = {
			Enabled = false,
			LimitToConfigured = true,
			SwitchExtremes = false,
			Minimum = 1,
			Maximum = 1.25,
		},
	},
	CombatAssistance = {
		Wisp = false,
		WispDelay = 0.40,
		GoldenTongue = false,
		GoldenTongueCombatOnly = false,
		MantraFollowUp = false,
		MantraFollowUpRequireHit = false,
		Ardour = false,
		FlowState = false,
		Rhythm = false,
		RagdollResponse = false,
		AssistanceCooldown = 0.35,
	},
	Diagnostics = {
		Enabled = false,
		Notifications = false,
		TraceDetectors = false,
		TraceScheduler = false,
		VisualizeHitboxes = false,
		MaxEvents = 200,
		PerformanceBudgetMs = 2,
		AdaptiveScan = true,
	},
	DebugState = {
		BlockParry = false,
		BlockDodge = false,
		BlockVent = false,
		NoBlocking = false,
	},
	Bindings = {
		ToggleDefense = "",
		DirectDodge = "",
		Prediction = "",
		Punishment = "",
		Vent = "",
		Wisp = "",
		GoldenTongue = "",
		MantraFollowUp = "",
		Ardour = "",
		FlowState = "",
		Rhythm = "",
		RagdollRecover = "",
		Teleport = "",
	},
}

-- Active switches never carry across executions. Numeric tuning, targeting,
-- bindings, filters, and selected roll targets remain saved, but CLAW MARK
-- always boots inert until the user explicitly enables a feature.
local SAFE_START_OFF = {
	"Enabled",
	"Defense.Enabled",
	"Defense.RollCancel",
	"Defense.DirectRoll",
	"Defense.RollOnParryCooldown",
	"Defense.DodgeFallback",
	"Defense.VentFallback",
	"Defense.BlockFallback",
	"Defense.ParryOnly",
	"Defense.UsePredictionMantra",
	"Defense.UsePunishmentMantra",
	"Probability.Enabled",
	"Probability.AllowFailure",
	"Filters.M1",
	"Filters.Mantra",
	"Filters.Critical",
	"Filters.Undefined",
	"Filters.TextboxFocused",
	"Filters.WindowInactive",
	"Filters.HoldingBlock",
	"Filters.ChimeCountdown",
	"Filters.SightlessBeam",
	"Validation.Facing",
	"Validation.IFrames",
	"Validation.AutoParryFrames",
	"AttackAssistance.AutoFeint",
	"AttackAssistance.DelayedFeint",
	"AttackAssistance.HoldM1",
	"AttackAssistance.FlourishFeint",
	"AttackAssistance.ActionRolling",
	"AttackAssistance.AnimationSpeed.Enabled",
	"CombatAssistance.Wisp",
	"CombatAssistance.GoldenTongue",
	"CombatAssistance.MantraFollowUp",
	"CombatAssistance.Ardour",
	"CombatAssistance.FlowState",
	"CombatAssistance.Rhythm",
	"CombatAssistance.RagdollResponse",
	"Diagnostics.Enabled",
	"Diagnostics.Notifications",
	"Diagnostics.TraceDetectors",
	"Diagnostics.TraceScheduler",
	"Diagnostics.VisualizeHitboxes",
	"DebugState.BlockParry",
	"DebugState.BlockDodge",
	"DebugState.BlockVent",
	"DebugState.NoBlocking",
}

local function clone(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy

	for key, child in pairs(value) do
		copy[clone(key, seen)] = clone(child, seen)
	end

	return copy
end

local function mergeKnown(target, source)
	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		if target[key] ~= nil then
			if type(target[key]) == "table" and type(value) == "table" then
				if next(target[key]) == nil then
					target[key] = clone(value)
				else
					mergeKnown(target[key], value)
				end
			elseif type(target[key]) == type(value) then
				target[key] = value
			end
		end
	end

	return target
end

local function splitPath(path)
	local parts = {}
	for part in string.gmatch(path, "[^.]+") do
		parts[#parts + 1] = part
	end
	return parts
end

function Settings.defaults()
	return clone(DEFAULTS)
end

function Settings.new(values)
	local self = setmetatable({}, Settings)
	self._data = mergeKnown(clone(DEFAULTS), values)
	return self
end

function Settings:get(path)
	if not path or path == "" then
		return self._data
	end

	local cursor = self._data
	for _, part in ipairs(splitPath(path)) do
		if type(cursor) ~= "table" then
			return nil
		end
		cursor = cursor[part]
	end

	return cursor
end

function Settings:set(path, value)
	local parts = splitPath(path)
	assert(#parts > 0, "setting path cannot be empty")

	local cursor = self._data
	for index = 1, #parts - 1 do
		cursor = cursor[parts[index]]
		assert(type(cursor) == "table", "unknown setting path: " .. path)
	end

	local key = parts[#parts]
	local current = cursor[key]
	assert(current ~= nil, "unknown setting path: " .. path)
	assert(type(current) == type(value), "invalid setting type for " .. path)
	cursor[key] = value
	return value
end

function Settings:load(values)
	self._data = mergeKnown(clone(DEFAULTS), values)
	return self
end

function Settings:safeStart()
	for _, path in ipairs(SAFE_START_OFF) do
		self:set(path, false)
	end
	return self
end

function Settings:serialize()
	return clone(self._data)
end

return Settings

local PresetManager = {}
PresetManager.__index = PresetManager

-- Every preset starts by clearing optional/risky switches. Numeric tuning,
-- bindings, and target lists are preserved, but stale toggles from a previous
-- experiment cannot silently leak into the next preset.
local PRESET_BASE = {
	Enabled = true,
	Detection = {
		Animations = true,
		Sounds = true,
		Parts = true,
		Effects = true,
		Projectiles = true,
		OnlyConfigured = true,
		UnknownAnimations = false,
	},
	Defense = {
		Enabled = true,
		Preferred = "Parry",
		DefendWhileAttacking = true,
		RollCancel = false,
		DirectRoll = false,
		RollOnParryCooldown = false,
		DodgeFallback = false,
		VentFallback = false,
		BlockFallback = false,
		ParryOnly = false,
		UsePredictionMantra = false,
		UsePunishmentMantra = false,
	},
	ThreatGuard = { Enabled = true },
	Validation = {
		Hitbox = true,
		Facing = false,
		Visibility = false,
		Stun = false,
		Cooldown = true,
		IFrames = false,
		AutoParryFrames = false,
		Prediction = false,
		AnimationSanity = true,
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
	Probability = { Enabled = false, AllowFailure = false, FailureRate = 0 },
	AttackAssistance = {
		AutoFeint = false,
		DelayedFeint = false,
		HoldM1 = false,
		FlourishFeint = false,
		ActionRolling = false,
		AnimationSpeed = { Enabled = false },
	},
	CombatAssistance = {
		Wisp = false,
		GoldenTongue = false,
		MantraFollowUp = false,
		Ardour = false,
		FlowState = false,
		Rhythm = false,
		RagdollResponse = false,
	},
	Diagnostics = {
		Enabled = false,
		Notifications = false,
		TraceDetectors = false,
		TraceScheduler = false,
		VisualizeHitboxes = false,
	},
	DebugState = { BlockParry = false, BlockDodge = false, BlockVent = false, NoBlocking = false },
}

local PRESETS = {
	Stable = {
		Targeting = {
			Selection = "ClosestDistance",
			MaxTargets = 4,
			MaxDistance = 3000,
			FOVDegrees = 360,
		},
		-- Facing is a useful per-attack geometry hint, but the global facing
		-- gate drops legitimate AoE, pull, aerial, and turning attacks.  Stable
		-- therefore leaves it off and relies on each profile's hitbox geometry.
		Validation = { Hitbox = true, Facing = false, Prediction = false },
		Diagnostics = { AdaptiveScan = true, PerformanceBudgetMs = 2 },
	},
	Legit = {
		Targeting = { ScanInterval = 0.05, MaxTargets = 2, MaxDistance = 65 },
		Validation = { Hitbox = true, Facing = false, Prediction = true, Visibility = false },
		Probability = { Enabled = true, AllowFailure = true, FailureRate = 3 },
		Diagnostics = { PerformanceBudgetMs = 2, AdaptiveScan = true },
	},
	Responsive = {
		Targeting = { ScanInterval = 0.025, MaxTargets = 4, MaxDistance = 90 },
		Validation = { Hitbox = true, Facing = false, Prediction = true },
		Diagnostics = { PerformanceBudgetMs = 3, AdaptiveScan = true },
	},
	Performance = {
		Targeting = { ScanInterval = 0.08, MaxTargets = 2, MaxDistance = 55 },
		Detection = { Sounds = false, Effects = false, OnlyConfigured = true },
		Validation = { Visibility = false, Prediction = false },
		Diagnostics = { PerformanceBudgetMs = 1.25, AdaptiveScan = true },
	},
	Lab = {
		Defense = { Enabled = false },
		Detection = { OnlyConfigured = false, UnknownAnimations = true },
		Diagnostics = { Enabled = true, TraceDetectors = true, TraceScheduler = true },
	},
}

local DESCRIPTIONS = {
	Stable = "Known-good indexed parry baseline from live trainer testing.",
	Legit = "Short range with prediction and a small intentional failure rate.",
	Responsive = "Faster scans and prediction for live combat testing.",
	Performance = "Reduced detector and scan load for weaker machines.",
	Lab = "Defense off; broad detection and traces on for animation research.",
}

local function merge(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and type(target[key]) == "table" then
			merge(target[key], value)
		else
			target[key] = value
		end
	end
end

function PresetManager.new(settings)
	return setmetatable({ Settings = settings }, PresetManager)
end

function PresetManager:names()
	local names = {}
	for name in pairs(PRESETS) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function PresetManager:describe(name)
	return DESCRIPTIONS[name] or ""
end

function PresetManager:apply(name)
	local preset = PRESETS[name]
	if not preset then
		return false, "unknown preset"
	end
	local current = self.Settings:serialize()
	merge(current, PRESET_BASE)
	merge(current, preset)
	self.Settings:load(current)
	return true
end

return PresetManager

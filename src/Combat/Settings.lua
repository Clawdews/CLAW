local Settings = {}
Settings.__index = Settings

local DEFAULTS = {
	Enabled = false,
	Targeting = {
		Selection = "ClosestDistance",
		MaxTargets = 1,
		MaxDistance = 65,
		FOVDegrees = 180,
		ScanInterval = 0.05,
		IgnorePlayers = false,
		IgnoreMobs = false,
		IgnoreAllies = true,
		RequireOnScreen = false,
		Whitelist = {},
		Blacklist = {},
	},
	Detection = {
		Animations = true,
		Sounds = true,
		Parts = true,
		Effects = true,
		Projectiles = true,
	},
	Defense = {
		Enabled = false,
		Preferred = "Parry",
		Fallback = "Dodge",
		AllowParry = true,
		AllowBlock = true,
		AllowDodge = true,
		AllowFullDodge = true,
		AllowJump = true,
		AllowSlide = true,
		AllowCrouch = true,
		AllowTeleport = false,
		RollCancel = false,
		RollCancelDelay = 0.08,
		BlockFallbackHold = 0.30,
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
	},
	Validation = {
		Hitbox = true,
		Facing = true,
		Visibility = false,
		Stun = true,
		Cooldown = true,
		IFrames = true,
		Prediction = true,
		PredictionSeconds = 0.10,
		HistorySeconds = 3,
		PastHitboxSeconds = 0.20,
	},
	Probability = {
		Enabled = false,
		Parry = 100,
		Block = 100,
		Dodge = 100,
		Feint = 100,
	},
	AttackAssistance = {
		AutoFeint = false,
		DelayedFeint = false,
		FeintDelay = 0.12,
		HoldM1 = false,
		FlourishFeint = false,
		ActionRolling = false,
		AnimationSpeed = 1,
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
		TraceDetectors = false,
		TraceScheduler = false,
		VisualizeHitboxes = false,
		MaxEvents = 200,
	},
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

function Settings:serialize()
	return clone(self._data)
end

return Settings

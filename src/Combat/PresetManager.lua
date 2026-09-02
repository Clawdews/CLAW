local PresetManager = {}
PresetManager.__index = PresetManager

local PRESETS = {
	Legit = {
		Enabled = true,
		Defense = { Enabled = true },
		Targeting = { ScanInterval = 0.05, MaxTargets = 2, MaxDistance = 65 },
		Validation = { Hitbox = true, Facing = true, Prediction = true, Visibility = false },
		Probability = { Enabled = true, AllowFailure = true, FailureRate = 3 },
		Diagnostics = { PerformanceBudgetMs = 2, AdaptiveScan = true },
	},
	Responsive = {
		Enabled = true,
		Defense = { Enabled = true },
		Targeting = { ScanInterval = 0.025, MaxTargets = 4, MaxDistance = 90 },
		Validation = { Hitbox = true, Facing = true, Prediction = true },
		Probability = { Enabled = false },
		Diagnostics = { PerformanceBudgetMs = 3, AdaptiveScan = true },
	},
	Performance = {
		Enabled = true,
		Defense = { Enabled = true },
		Targeting = { ScanInterval = 0.08, MaxTargets = 2, MaxDistance = 55 },
		Detection = { Sounds = false, Effects = false, OnlyConfigured = true },
		Validation = { Visibility = false, Prediction = false },
		Diagnostics = { PerformanceBudgetMs = 1.25, AdaptiveScan = true },
	},
	Lab = {
		Enabled = true,
		Defense = { Enabled = false },
		Detection = { OnlyConfigured = false },
		Diagnostics = { Enabled = true, TraceDetectors = true, TraceScheduler = true },
	},
}

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

function PresetManager:apply(name)
	local preset = PRESETS[name]
	if not preset then
		return false, "unknown preset"
	end
	local current = self.Settings:serialize()
	local function merge(target, source)
		for key, value in pairs(source) do
			if type(value) == "table" and type(target[key]) == "table" then
				merge(target[key], value)
			else
				target[key] = value
			end
		end
	end
	merge(current, preset)
	self.Settings:load(current)
	return true
end

return PresetManager

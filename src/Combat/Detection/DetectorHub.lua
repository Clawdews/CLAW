local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES
local Signal = assert(modules["src/Runtime/Signal.lua"])
local AnimationDetector = assert(modules["src/Combat/Detection/AnimationDetector.lua"])
local SoundDetector = assert(modules["src/Combat/Detection/SoundDetector.lua"])
local PartDetector = assert(modules["src/Combat/Detection/PartDetector.lua"])
local EffectDetector = assert(modules["src/Combat/Detection/EffectDetector.lua"])

local DetectorHub = {}
DetectorHub.__index = DetectorHub

function DetectorHub.new(settings, timings, options)
	options = options or {}
	local shared = options.shared or {}
	local function accept(category, id)
		return not settings:get("Detection.OnlyConfigured") or timings:has(category, id)
	end
	local function detectorOptions(specific)
		local combined = {}
		for key, value in pairs(shared) do
			combined[key] = value
		end
		for key, value in pairs(specific or {}) do
			combined[key] = value
		end
		combined.accept = combined.accept or accept
		return combined
	end
	local self = setmetatable({
		Settings = settings,
		Timings = timings,
		Detected = Signal.new(),
		Connections = {},
		Running = false,
		Detectors = {
			Animations = AnimationDetector.new(detectorOptions(options.animation)),
			Sounds = SoundDetector.new(detectorOptions(options.sound)),
			Parts = PartDetector.new(detectorOptions(options.part)),
			Effects = EffectDetector.new(detectorOptions(options.effect)),
		},
	}, DetectorHub)

	for settingName, detector in pairs(self.Detectors) do
		self.Connections[#self.Connections + 1] = detector.Detected:Connect(function(event)
			if self.Settings:get("Detection." .. settingName) then
				self.Detected:Fire(event)
			end
		end)
	end

	self.Connections[#self.Connections + 1] = timings.Changed:Connect(function()
		self.Detectors.Sounds:refresh()
	end)

	return self
end

function DetectorHub:start()
	if self.Running then
		return
	end
	self.Running = true
	for _, detector in pairs(self.Detectors) do
		detector:start()
	end
end

function DetectorHub:stop()
	if not self.Running then
		return
	end
	self.Running = false
	for _, detector in pairs(self.Detectors) do
		detector:stop()
	end
end

function DetectorHub:refresh()
	if self.Running then
		self.Detectors.Sounds:refresh()
	end
end

function DetectorHub:Destroy()
	self:stop()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for _, detector in pairs(self.Detectors) do
		detector:Destroy()
	end
	self.Detected:Destroy()
end

return DetectorHub

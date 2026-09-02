local environment = getgenv and getgenv() or _G
local modules = environment.__CLAW_MODULES
local Signal = assert(modules["src/Runtime/Signal.lua"])
local AnimationDetector = assert(modules["src/Combat/Detection/AnimationDetector.lua"])
local SoundDetector = assert(modules["src/Combat/Detection/SoundDetector.lua"])
local PartDetector = assert(modules["src/Combat/Detection/PartDetector.lua"])
local EffectDetector = assert(modules["src/Combat/Detection/EffectDetector.lua"])

local DetectorHub = {}
DetectorHub.__index = DetectorHub

function DetectorHub.new(settings, options)
	options = options or {}
	local shared = options.shared or {}
	local self = setmetatable({
		Settings = settings,
		Detected = Signal.new(),
		Connections = {},
		Running = false,
		Detectors = {
			Animations = AnimationDetector.new(options.animation or shared),
			Sounds = SoundDetector.new(options.sound or shared),
			Parts = PartDetector.new(options.part or shared),
			Effects = EffectDetector.new(options.effect or shared),
		},
	}, DetectorHub)

	for settingName, detector in pairs(self.Detectors) do
		self.Connections[#self.Connections + 1] = detector.Detected:Connect(function(event)
			if self.Settings:get("Detection." .. settingName) then
				self.Detected:Fire(event)
			end
		end)
	end

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

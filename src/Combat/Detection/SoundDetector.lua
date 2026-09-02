local environment = getgenv and getgenv() or _G
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])
local DetectorEvent = assert(environment.__CLAW_MODULES["src/Combat/Detection/DetectorEvent.lua"])

local SoundDetector = {}
SoundDetector.__index = SoundDetector

local function cleanID(value)
	return tostring(value or ""):match("(%d+)") or tostring(value or "")
end

function SoundDetector.new(options)
	options = options or {}
	return setmetatable({
		Detected = Signal.new(),
		_source = options.source,
		_accept = options.accept,
		_activeSource = nil,
		_connections = {},
		_sounds = setmetatable({}, { __mode = "k" }),
		_running = false,
	}, SoundDetector)
end

function SoundDetector:_emit(sound)
	local id = cleanID(sound.SoundId)
	if id == "" then
		return
	end
	if type(self._accept) == "function" and not self._accept("sound", id, sound) then
		return
	end

	self.Detected:Fire(DetectorEvent.new("sound", id, sound, {
		position = sound.Parent and sound.Parent:IsA("BasePart") and sound.Parent.Position or nil,
		metadata = {
			name = sound.Name,
			playbackSpeed = sound.PlaybackSpeed,
			timePosition = sound.TimePosition,
		},
	}))
end

function SoundDetector:_hook(sound)
	if self._sounds[sound] then
		return
	end
	local id = cleanID(sound.SoundId)
	if type(self._accept) == "function" and not self._accept("sound", id, sound) then
		return
	end

	local connection = sound.Played:Connect(function()
		self:_emit(sound)
	end)
	self._sounds[sound] = connection
	self._connections[#self._connections + 1] = connection

	if sound.Playing then
		self:_emit(sound)
	end
end

function SoundDetector:start()
	if self._running then
		return
	end
	self._running = true

	local source = type(self._source) == "function" and self._source()
		or self._source
		or workspace:FindFirstChild("Live")
		or workspace
	self._activeSource = source

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:_hook(descendant)
		end
	end

	local connection = source.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			self:_hook(descendant)
		end
	end)
	self._connections[#self._connections + 1] = connection
end

function SoundDetector:refresh()
	if not self._running or not self._activeSource then
		return
	end
	for _, descendant in ipairs(self._activeSource:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:_hook(descendant)
		end
	end
end

function SoundDetector:stop()
	if not self._running then
		return
	end
	self._running = false
	for _, connection in ipairs(self._connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)
	table.clear(self._sounds)
	self._activeSource = nil
end

function SoundDetector:Destroy()
	self:stop()
	self.Detected:Destroy()
end

return SoundDetector

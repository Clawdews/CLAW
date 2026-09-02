local environment = getgenv and getgenv() or _G
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])
local DetectorEvent = assert(environment.__CLAW_MODULES["src/Combat/Detection/DetectorEvent.lua"])

local AnimationDetector = {}
AnimationDetector.__index = AnimationDetector

local function cleanID(value)
	return tostring(value or ""):match("(%d+)") or tostring(value or "")
end

function AnimationDetector.new(options)
	options = options or {}
	return setmetatable({
		Detected = Signal.new(),
		_source = options.source,
		_ignoreTrack = options.ignoreTrack,
		_connections = {},
		_animators = setmetatable({}, { __mode = "k" }),
		_running = false,
	}, AnimationDetector)
end

function AnimationDetector:_bind(signal, callback)
	local connection = signal:Connect(callback)
	self._connections[#self._connections + 1] = connection
	return connection
end

function AnimationDetector:_emit(animator, track)
	if type(self._ignoreTrack) == "function" then
		local ok, ignored = pcall(self._ignoreTrack, track)
		if ok and ignored then
			return
		end
	end

	local animation = track.Animation
	local id = cleanID(animation and animation.AnimationId)
	if id == "" then
		return
	end

	self.Detected:Fire(DetectorEvent.new("animation", id, animator, {
		track = track,
		metadata = {
			priority = tostring(track.Priority),
			looped = track.Looped,
			length = track.Length,
		},
	}))
end

function AnimationDetector:_hook(animator)
	if self._animators[animator] then
		return
	end

	local connection = animator.AnimationPlayed:Connect(function(track)
		self:_emit(animator, track)
	end)
	self._animators[animator] = connection
	self._connections[#self._connections + 1] = connection

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		self:_emit(animator, track)
	end
end

function AnimationDetector:start()
	if self._running then
		return
	end
	self._running = true

	local source = type(self._source) == "function" and self._source()
		or self._source
		or workspace:FindFirstChild("Live")
		or workspace

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("Animator") then
			self:_hook(descendant)
		end
	end

	self:_bind(source.DescendantAdded, function(descendant)
		if descendant:IsA("Animator") then
			self:_hook(descendant)
		end
	end)
end

function AnimationDetector:stop()
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
	table.clear(self._animators)
end

function AnimationDetector:Destroy()
	self:stop()
	self.Detected:Destroy()
end

return AnimationDetector

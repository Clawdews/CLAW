local environment = getgenv and getgenv() or _G
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])
local DetectorEvent = assert(environment.__CLAW_MODULES["src/Combat/Detection/DetectorEvent.lua"])

local PartDetector = {}
PartDetector.__index = PartDetector

function PartDetector.new(options)
	options = options or {}
	return setmetatable({
		Detected = Signal.new(),
		_source = options.source,
		_connection = nil,
		_running = false,
	}, PartDetector)
end

function PartDetector:_emit(part)
	self.Detected:Fire(DetectorEvent.new("part", part.Name, part, {
		position = part.Position,
		metadata = {
			className = part.ClassName,
			size = part.Size,
			velocity = part.AssemblyLinearVelocity,
		},
	}))
end

function PartDetector:start()
	if self._running then
		return
	end
	self._running = true

	local source = type(self._source) == "function" and self._source()
		or self._source
		or workspace
	self._connection = source.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			self:_emit(descendant)
		end
	end)
end

function PartDetector:stop()
	self._running = false
	if self._connection then
		pcall(function()
			self._connection:Disconnect()
		end)
		self._connection = nil
	end
end

function PartDetector:Destroy()
	self:stop()
	self.Detected:Destroy()
end

return PartDetector

local environment = getgenv and getgenv() or _G
local CollectionService = game:GetService("CollectionService")
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])
local DetectorEvent = assert(environment.__CLAW_MODULES["src/Combat/Detection/DetectorEvent.lua"])

local EffectDetector = {}
EffectDetector.__index = EffectDetector

function EffectDetector.new(options)
	options = options or {}
	return setmetatable({
		Detected = Signal.new(),
		_source = options.source,
		_accept = options.accept,
		_connection = nil,
		_running = false,
	}, EffectDetector)
end

function EffectDetector:_emit(instance)
	if instance:IsA("Animator") or instance:IsA("Sound") or instance:IsA("BasePart") then
		return
	end

	local tags = CollectionService:GetTags(instance)
	local acceptName = type(self._accept) ~= "function" or self._accept("effect", instance.Name, instance)
	if acceptName then
		self.Detected:Fire(DetectorEvent.new("effect", instance.Name, instance, {
			metadata = {
				className = instance.ClassName,
				tags = tags,
				attributes = instance:GetAttributes(),
			},
		}))
	end

	for _, tag in ipairs(tags) do
		if type(self._accept) ~= "function" or self._accept("effect", tag, instance) then
			self.Detected:Fire(DetectorEvent.new("effect", tag, instance, {
				metadata = { source = "tag", name = instance.Name },
			}))
		end
	end
end

function EffectDetector:start()
	if self._running then
		return
	end
	self._running = true

	local source = type(self._source) == "function" and self._source()
		or self._source
		or workspace:FindFirstChild("Live")
		or workspace
	self._connection = source.DescendantAdded:Connect(function(descendant)
		self:_emit(descendant)
	end)
end

function EffectDetector:stop()
	self._running = false
	if self._connection then
		pcall(function()
			self._connection:Disconnect()
		end)
		self._connection = nil
	end
end

function EffectDetector:Destroy()
	self:stop()
	self.Detected:Destroy()
end

return EffectDetector

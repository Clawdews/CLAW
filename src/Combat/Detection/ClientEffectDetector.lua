local environment = getgenv and getgenv() or _G
local Signal = assert(environment.__CLAW_MODULES["src/Runtime/Signal.lua"])
local DetectorEvent = assert(environment.__CLAW_MODULES["src/Combat/Detection/DetectorEvent.lua"])

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientEffectDetector = {}
ClientEffectDetector.__index = ClientEffectDetector

local CHANNELS = {
	ClientEffect = true,
	ClientEffectLarge = true,
	ClientEffectDirect = true,
}

local OWNER_KEYS = {
	"owner",
	"Owner",
	"caster",
	"Caster",
	"character",
	"Character",
	"entity",
	"Entity",
	"source",
	"Source",
}

local POSITION_KEYS = {
	"position",
	"Position",
	"pos",
	"Pos",
	"cframe",
	"CFrame",
	"cf",
	"CF",
	"part",
	"Part",
}

local function humanoidModel(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end
	local model
	if instance:IsA("Model") then
		model = instance
	elseif instance:IsA("BasePart") or instance:IsA("Attachment") then
		model = instance:FindFirstAncestorWhichIsA("Model")
	end
	if not model or not model:FindFirstChildWhichIsA("Humanoid") then
		return nil
	end
	local live = workspace:FindFirstChild("Live")
	if live and model ~= live and not model:IsDescendantOf(live) then
		return nil
	end
	return model
end

local function explicitOwner(data)
	for _, key in ipairs(OWNER_KEYS) do
		local owner = humanoidModel(data[key])
		if owner then
			return owner, "explicit"
		end
	end
	return nil
end

local function boundedOwner(data)
	local explicit, confidence = explicitOwner(data)
	if explicit then
		return explicit, confidence
	end

	local seen = {}
	local inspected = 0
	local function visit(value, depth)
		if inspected >= 32 or depth > 2 then
			return nil
		end
		inspected = inspected + 1
		local owner = humanoidModel(value)
		if owner then
			return owner
		end
		if type(value) ~= "table" or seen[value] then
			return nil
		end
		seen[value] = true
		for _, child in pairs(value) do
			local found = visit(child, depth + 1)
			if found then
				return found
			end
			if inspected >= 32 then
				break
			end
		end
		return nil
	end
	local owner = visit(data, 0)
	return owner, owner and "inferred" or "none"
end

local function originFor(data, owner)
	local root = owner and owner:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root, root.Position
	end
	for _, key in ipairs(POSITION_KEYS) do
		local value = data[key]
		if typeof(value) == "Vector3" then
			return nil, value
		elseif typeof(value) == "CFrame" then
			return nil, value.Position
		elseif typeof(value) == "Instance" then
			if value:IsA("BasePart") then
				return value, value.Position
			elseif value:IsA("Attachment") then
				return value.Parent, value.WorldPosition
			end
		end
	end
	return owner, nil
end

local function shallowSnapshot(data)
	local snapshot = {}
	local count = 0
	for key, value in pairs(data) do
		if count >= 32 then
			break
		end
		local valueType = typeof(value)
		if
			type(key) == "string"
			and (
				valueType == "string"
				or valueType == "number"
				or valueType == "boolean"
				or valueType == "Vector3"
				or valueType == "CFrame"
				or valueType == "Instance"
			)
		then
			snapshot[key] = value
			count = count + 1
		end
	end
	return snapshot
end

local function rounded(value)
	return math.floor(value * 4 + 0.5) / 4
end

local function fingerprintFor(id, owner, position)
	local ownerKey = owner and owner:GetFullName() or "?"
	local positionKey = "?"
	if typeof(position) == "Vector3" then
		positionKey = string.format("%.2f,%.2f,%.2f", rounded(position.X), rounded(position.Y), rounded(position.Z))
	end
	return tostring(id) .. "|" .. ownerKey .. "|" .. positionKey
end

function ClientEffectDetector.new(options)
	options = options or {}
	return setmetatable({
		Detected = Signal.new(),
		_source = options.source,
		_accept = options.accept,
		_connections = {},
		_hooked = setmetatable({}, { __mode = "k" }),
		_recent = {},
		_running = false,
		Stats = {
			ClientEffect = 0,
			ClientEffectLarge = 0,
			ClientEffectDirect = 0,
			Deduplicated = 0,
		},
	}, ClientEffectDetector)
end

function ClientEffectDetector:_bind(signal, callback)
	local connection = signal:Connect(callback)
	self._connections[#self._connections + 1] = connection
	return connection
end

function ClientEffectDetector:_deduplicated(fingerprint, channel, now)
	local previous = self._recent[fingerprint]
	self._recent[fingerprint] = { channel = channel, at = now }
	if previous and previous.channel ~= channel and now - previous.at <= 0.03 then
		self.Stats.Deduplicated = self.Stats.Deduplicated + 1
		return true
	end
	if math.random(1, 32) == 1 then
		for key, value in pairs(self._recent) do
			if now - value.at > 0.25 then
				self._recent[key] = nil
			end
		end
	end
	return false
end

function ClientEffectDetector:_emit(channel, name, data)
	local id = tostring(name or "")
	if id == "" then
		return
	end
	if type(self._accept) == "function" and not self._accept("effect", id, nil) then
		return
	end
	if type(data) ~= "table" then
		data = {}
	end

	local owner, confidence = boundedOwner(data)
	local instance, position = originFor(data, owner)
	local fingerprint = fingerprintFor(id, owner, position)
	local now = os.clock()
	if self:_deduplicated(fingerprint, channel, now) then
		return
	end

	self.Stats[channel] = (self.Stats[channel] or 0) + 1
	local snapshot = shallowSnapshot(data)
	self.Detected:Fire(DetectorEvent.new("effect", id, instance, {
		entity = owner,
		position = position,
		startedAt = now,
		metadata = {
			channel = channel,
			attributes = snapshot,
			payload = snapshot,
			ownershipConfidence = confidence,
			fingerprint = fingerprint,
		},
	}))
end

function ClientEffectDetector:_hook(channel, remote)
	if self._hooked[remote] or not CHANNELS[channel] then
		return
	end
	local signal
	if remote:IsA("RemoteEvent") then
		signal = remote.OnClientEvent
	elseif remote:IsA("BindableEvent") then
		signal = remote.Event
	end
	if not signal then
		return
	end
	self._hooked[remote] = true
	self:_bind(signal, function(name, data)
		self:_emit(channel, name, data)
	end)
end

function ClientEffectDetector:start()
	if self._running then
		return
	end
	self._running = true
	local requests = type(self._source) == "function" and self._source()
		or self._source
		or ReplicatedStorage:FindFirstChild("Requests")
	if not requests then
		self:_bind(ReplicatedStorage.ChildAdded, function(child)
			if self._running and child.Name == "Requests" then
				for channel in pairs(CHANNELS) do
					local remote = child:FindFirstChild(channel)
					if remote then
						self:_hook(channel, remote)
					end
				end
				self:_bind(child.ChildAdded, function(remote)
					if CHANNELS[remote.Name] then
						self:_hook(remote.Name, remote)
					end
				end)
			end
		end)
		return
	end
	for channel in pairs(CHANNELS) do
		local remote = requests:FindFirstChild(channel)
		if remote then
			self:_hook(channel, remote)
		end
	end
	self:_bind(requests.ChildAdded, function(child)
		if CHANNELS[child.Name] then
			self:_hook(child.Name, child)
		end
	end)
end

function ClientEffectDetector:stop()
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
	table.clear(self._hooked)
	table.clear(self._recent)
end

function ClientEffectDetector:Destroy()
	self:stop()
	self.Detected:Destroy()
end

return ClientEffectDetector

local environment = getgenv and getgenv() or _G

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NativeInputBridge = {}
NativeInputBridge.__index = NativeInputBridge

local ALLOWED_INPUT_KEYS = {
	Left = true,
	Right = true,
	W = true,
	A = true,
	S = true,
	D = true,
	Thumbstick1 = true,
	C = true,
	f = true,
	H = true,
	Space = true,
	ctrl = true,
}

local function executorFunction(name)
	local callback = rawget(environment, name)
	return type(callback) == "function" and callback or nil
end

local function debugFunction(name)
	local debugLibrary = rawget(environment, "debug") or debug
	local callback = debugLibrary and debugLibrary[name]
	return type(callback) == "function" and callback or executorFunction(name)
end

local function rawMetatable(value)
	local callback = executorFunction("getrawmetatable")
	if callback then
		local ok, result = pcall(callback, value)
		return ok and result or nil
	end
	return getmetatable(value)
end

local function isExecutorFunction(value)
	for _, name in ipairs({ "iscclosure", "isexecutorclosure", "checkclosure" }) do
		local callback = executorFunction(name)
		if callback then
			local ok, result = pcall(callback, value)
			if ok and result then
				return true
			end
		end
	end
	return false
end

local function tableLength(value)
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count
end

local function validInputTable(value)
	if type(value) ~= "table" or rawMetatable(value) then
		return false
	end
	for key, child in pairs(value) do
		if not ALLOWED_INPUT_KEYS[key] or type(child) ~= "boolean" then
			return false
		end
	end
	return tableLength(value) <= 12
end

local function includes(values, expected)
	for _, value in pairs(values or {}) do
		if value == expected then
			return true
		end
	end
	return false
end

local function numberToString(number, iterations)
	local result = ""
	for _ = 1, iterations do
		local byte = number % 256
		result = string.char(byte) .. result
		number = (number - byte) / 256
	end
	return result
end

local function stringToNumber(value, offset)
	local number = 0
	for index = offset, offset + 3 do
		number = number * 256 + string.byte(value, index)
	end
	return number
end

local function shaPreprocess(message)
	return message
		.. string.char(128)
		.. string.rep(string.char(0), 64 - (#message + 9) % 64)
		.. numberToString(8 * #message, 8)
end

local function shaDigest(message, offset, hashes, randomTable)
	local chunks = {}
	for index = 1, 16 do
		chunks[index] = stringToNumber(message, offset + ((index - 1) * 4))
	end
	for index = 17, 64 do
		local first = chunks[index - 15]
		local second = chunks[index - 2]
		chunks[index] = chunks[index - 16]
			+ bit32.bxor(bit32.rrotate(first, 7), bit32.rrotate(first, 18), bit32.rshift(first, 3))
			+ chunks[index - 7]
			+ bit32.bxor(bit32.rrotate(second, 17), bit32.rrotate(second, 19), bit32.rshift(second, 10))
	end

	local a, b, c, d = hashes[1], hashes[2], hashes[3], hashes[4]
	local e, f, g, h = hashes[5], hashes[6], hashes[7], hashes[8]
	for index = 1, 64 do
		local first = bit32.bxor(bit32.rrotate(a, 2), bit32.rrotate(a, 13), bit32.rrotate(a, 22))
			+ bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
		local second = bit32.bxor(bit32.rrotate(e, 6), bit32.rrotate(e, 11), bit32.rrotate(e, 25))
		local choose = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
		local temporary = h + second + choose + randomTable[index] + chunks[index]
		h, g, f, e, d, c, b, a = g, f, e, d + temporary, c, b, a, temporary + first
	end

	hashes[1] = bit32.band(hashes[1] + a)
	hashes[2] = bit32.band(hashes[2] + b)
	hashes[3] = bit32.band(hashes[3] + c)
	hashes[4] = bit32.band(hashes[4] + d)
	hashes[5] = bit32.band(hashes[5] + e)
	hashes[6] = bit32.band(hashes[6] + f)
	hashes[7] = bit32.band(hashes[7] + g)
	hashes[8] = bit32.band(hashes[8] + h)
end

local function hashRemote(name, randomTable)
	local hashes = {
		1779033703,
		3144134277,
		1013904242,
		2773480762,
		1359893119,
		2600822924,
		528734635,
		1541459225,
	}
	local processed = shaPreprocess(name)
	for offset = 1, #name, 64 do
		shaDigest(processed, offset, hashes, randomTable)
	end
	local result = ""
	for _, value in ipairs(hashes) do
		result = result .. numberToString(value, 4)
	end
	return result
end

local function upvaluesOf(callback)
	local getter = debugFunction("getupvalues")
	if not getter then
		return {}
	end
	local ok, values = pcall(getter, callback)
	return ok and type(values) == "table" and values or {}
end

local function valueAtUpvalue(callback, index)
	local getter = debugFunction("getupvalue")
	if not getter then
		return nil
	end
	local results = table.pack(pcall(getter, callback, index))
	if not results[1] then
		return nil
	end
	if type(results[2]) == "table" then
		return results[2]
	end
	return type(results[3]) == "table" and results[3] or nil
end

local function remoteContainer(value)
	if type(value) ~= "table" then
		return nil
	end
	for _, candidate in pairs(value) do
		if type(candidate) == "table" and not rawMetatable(candidate) and #candidate == 0 and not candidate[10] then
			return candidate
		end
	end
	return nil
end

local function randomConstants(value)
	if type(value) ~= "table" or rawMetatable(value) or #value ~= 68 then
		return nil
	end
	local firstIndex, firstValue = next(value)
	if type(firstIndex) == "number" and type(firstValue) == "number" and firstValue >= 100000 and firstValue <= 100000000 then
		return value
	end
	return nil
end

function NativeInputBridge.new()
	local self = setmetatable({
		Initialized = false,
		Ready = false,
		Status = "not initialized",
		RemoteTable = nil,
		RandomTable = nil,
		InputData = nil,
		SprintFunction = nil,
		Remotes = {},
		Queue = {},
		NextQueueID = 0,
		NextRetry = 0,
		NextBlockRetry = 0,
		BlockRetryCount = 0,
		NextUnblockRetry = 0,
		UnblockAttemptCount = 0,
		ReleaseSent = true,
		LastTransition = "idle",
		Stats = {
			Blocks = 0,
			Unblocks = 0,
			Retries = 0,
			Coalesced = 0,
			ReleaseRetries = 0,
			SafetyReleases = 0,
			Dodges = 0,
			DodgeCancels = 0,
		},
		RenderConnection = nil,
		CharacterConnection = nil,
		EffectModule = nil,
	}, NativeInputBridge)
	self.CharacterConnection = Players.LocalPlayer.CharacterAdded:Connect(function()
		self:invalidate("character changed")
	end)
	return self
end

function NativeInputBridge:_effectModule()
	if self.EffectModule then
		return self.EffectModule
	end
	local source = ReplicatedStorage:FindFirstChild("EffectReplicator")
	if source then
		local ok, result = pcall(require, source)
		if ok then
			self.EffectModule = result
		end
	end
	return self.EffectModule
end

function NativeInputBridge:_hasEffect(name)
	local module = self:_effectModule()
	if not module then
		return false
	end
	local finder = module.FindEffect
	if type(finder) ~= "function" then
		return false
	end
	local ok, result = pcall(finder, module, name)
	return ok and result ~= nil and result ~= false
end

function NativeInputBridge:_removeEffect(name)
	local module = self:_effectModule()
	local finder = module and module.FindEffect
	if type(finder) ~= "function" then
		return
	end
	local ok, effect = pcall(finder, module, name)
	if ok and effect and type(effect.Remove) == "function" then
		pcall(effect.Remove, effect)
	end
end

function NativeInputBridge:_scanGC()
	local getGC = executorFunction("getgc")
	if not getGC then
		return false, "getgc unavailable"
	end
	local ok, values = pcall(getGC, true)
	if not ok or type(values) ~= "table" then
		ok, values = pcall(getGC)
	end
	if not ok or type(values) ~= "table" then
		return false, "getgc failed"
	end
	local getInfo = debugFunction("getinfo")

	for _, value in pairs(values) do
		if not self.RandomTable then
			self.RandomTable = randomConstants(value)
		end
		if type(value) == "function" and not isExecutorFunction(value) then
			if not self.RemoteTable and getInfo then
				local infoOK, info = pcall(getInfo, value)
				local source = infoOK
					and info
					and (tostring(info.source or "") .. " " .. tostring(info.short_src or ""))
					or ""
				if string.find(source, "KeyHandler", 1, true) then
					self.RemoteTable = remoteContainer(valueAtUpvalue(value, 10))
				end
			end
			if not self.SprintFunction and getInfo then
				local infoOK, info = pcall(getInfo, value)
				if infoOK and info and info.name == "Sprint" and next(upvaluesOf(value)) ~= nil then
					self.SprintFunction = value
				end
			end
		end
		if self.RemoteTable and self.RandomTable and self.SprintFunction then
			break
		end
	end
	return self.RemoteTable ~= nil and self.RandomTable ~= nil,
		self.RemoteTable and (self.RandomTable and nil or "hash constants unavailable") or "key-handler remotes unavailable"
end

function NativeInputBridge:_scanInputData()
	local getConnections = executorFunction("getconnections")
	local getConstants = debugFunction("getconstants")
	if not getConnections or not getConstants then
		return nil
	end
	local ok, connections = pcall(getConnections, RunService.RenderStepped)
	if not ok or type(connections) ~= "table" then
		return nil
	end
	for _, connection in pairs(connections) do
		local callback
		pcall(function()
			callback = connection.Function
		end)
		if type(callback) ~= "function" or isExecutorFunction(callback) then
			continue
		end
		local constantsOK, constants = pcall(getConstants, callback)
		if not constantsOK or not includes(constants, ".lastHBCheck") then
			continue
		end
		for _, value in pairs(upvaluesOf(callback)) do
			if validInputTable(value) then
				return value
			end
		end
	end
	return nil
end

function NativeInputBridge:_remote(name)
	local cached = self.Remotes[name]
	if cached and cached.Parent then
		return cached
	end
	if not self.RemoteTable or not self.RandomTable then
		return nil
	end
	local remote = self.RemoteTable[hashRemote(name, self.RandomTable)]
	if typeof(remote) == "Instance" then
		self.Remotes[name] = remote
		return remote
	end
	return nil
end

function NativeInputBridge:_fire(remote, ...)
	if not remote then
		return false, "remote unavailable"
	end
	local ok, result = pcall(remote.FireServer, remote, ...)
	return ok, ok and nil or tostring(result)
end

function NativeInputBridge:_sendBlock(retry)
	local fired, reason = self:_fire(self:_remote("Block"))
	if fired then
		self.Stats.Blocks = self.Stats.Blocks + 1
		if retry then
			self.Stats.Retries = self.Stats.Retries + 1
		end
		self.LastTransition = retry and "block retry" or "block sent"
	else
		self.LastTransition = "block failed: " .. tostring(reason)
	end
	return fired, reason
end

function NativeInputBridge:_sendUnblock(detail)
	local fired, reason = self:_fire(self:_remote("Unblock"))
	if fired then
		self.Stats.Unblocks = self.Stats.Unblocks + 1
		self.LastTransition = "unblock sent: " .. tostring(detail or "release")
	else
		self.LastTransition = "unblock failed: " .. tostring(reason)
	end
	return fired, reason
end

function NativeInputBridge:_attemptUnblock(detail, now)
	now = now or os.clock()
	if now < self.NextUnblockRetry then
		return false, "unblock retry pending"
	end

	local retry = self.UnblockAttemptCount > 0
	local fired, reason = self:_sendUnblock(detail)
	self.UnblockAttemptCount = self.UnblockAttemptCount + 1
	-- Lycoris intentionally repeats Unblock while the replicated Blocking
	-- effect remains. A fixed retry cap can leave the server-side state alive,
	-- which prevents weapon-slot input and attacks even after our queue is empty.
	-- Thirty hertz preserves that state-driven contract without per-frame spam.
	self.NextUnblockRetry = now + 0.033
	self.ReleaseSent = fired
	if retry then
		self.Stats.ReleaseRetries = self.Stats.ReleaseRetries + 1
	end
	return fired, reason
end

function NativeInputBridge:isBusy()
	return next(self.Queue) ~= nil or not self.ReleaseSent or self:_hasEffect("Blocking")
end

function NativeInputBridge:canParry()
	if self:_hasEffect("ParryCool") then
		return false, "parry-cooldown"
	end
	return true
end

function NativeInputBridge:canDodge()
	for _, effect in ipairs({ "NoRoll", "PreventRoll", "Dodged", "Dodge", "Stun" }) do
		if self:_hasEffect(effect) then
			return false, effect == "Stun" and "stunned" or "dodge-cooldown"
		end
	end
	return true
end

function NativeInputBridge:isDodging()
	return self:_hasEffect("ClientDodge")
		or self:_hasEffect("Dodge")
		or self:_hasEffect("DodgeFrame")
		or self:_hasEffect("DodgedFrame")
		or self:_hasEffect("Immortal")
		or self:_hasEffect("NoRoll")
end

function NativeInputBridge:directDodge()
	local ready, reason = self:initialize()
	if not ready then
		return false, reason
	end
	local canDodge, dodgeReason = self:canDodge()
	if not canDodge then
		return false, dodgeReason
	end
	if not self.InputData then
		return false, "native input state unavailable"
	end
	if self:_hasEffect("Blocking") or next(self.Queue) ~= nil then
		table.clear(self.Queue)
		self:_sendUnblock("dodge")
		self.ReleaseSent = true
	end
	local fired, fireReason = self:_fire(self:_remote("Dodge"), "roll", nil, nil, false)
	if fired then
		self.Stats.Dodges = self.Stats.Dodges + 1
		self.LastTransition = "direct dodge sent"
	else
		self.LastTransition = "direct dodge failed: " .. tostring(fireReason)
	end
	return fired, fired and "LycorisNativeDodge" or fireReason
end

function NativeInputBridge:stopDodge(direct)
	local ready, reason = self:initialize()
	if not ready then
		return false, reason
	end
	if not self.InputData then
		return false, "native input state unavailable"
	end
	local fired, fireReason
	if direct then
		fired, fireReason = self:_fire(
			self:_remote("StopDodge"),
			self.InputData,
			self:_hasEffect("LightAttack"),
			true
		)
	else
		fired, fireReason = self:_fire(
			self:_remote("StopDodge"),
			self.InputData,
			self:_hasEffect("LightAttack")
		)
	end
	if fired then
		self.Stats.DodgeCancels = self.Stats.DodgeCancels + 1
		self.LastTransition = "dodge cancel sent"
	else
		self.LastTransition = "dodge cancel failed: " .. tostring(fireReason)
	end
	return fired, fired and "LycorisNativeStopDodge" or fireReason
end

function NativeInputBridge:releaseAll(reason)
	local detail = reason or "safe reset"
	local blocking = self:_hasEffect("Blocking")
	local shouldUnblock = blocking or not self.ReleaseSent or next(self.Queue) ~= nil

	if self.InputData then
		self.InputData.f = false
	end
	table.clear(self.Queue)
	self.NextBlockRetry = 0
	self.BlockRetryCount = 0
	self.NextUnblockRetry = 0
	self.UnblockAttemptCount = 0

	local ok, releaseReason = true, nil
	if shouldUnblock and self.Ready then
		self.Stats.SafetyReleases = self.Stats.SafetyReleases + 1
		ok, releaseReason = self:_attemptUnblock(detail)
	elseif shouldUnblock then
		ok, releaseReason = false, "native bridge unavailable"
	end
	if not shouldUnblock then
		self.ReleaseSent = true
	end
	self.LastTransition = ok and ("released: " .. detail)
		or ("release failed: " .. tostring(releaseReason))
	return ok, releaseReason or detail
end

function NativeInputBridge:_updateQueue()
	local now = os.clock()
	local hadEntries = next(self.Queue) ~= nil
	local blocking = self:_hasEffect("Blocking")
	for id, item in pairs(self.Queue) do
		if now >= item.expires or (item.sent and item.deflect and blocking) then
			self.Queue[id] = nil
		end
	end
	local active = next(self.Queue) ~= nil
	local hasPending = false
	for _, item in pairs(self.Queue) do
		if not item.sent then
			hasPending = true
			break
		end
	end

	if active and hasPending then
		-- A new parry arrived before the previous Blocking effect cleared. Keep
		-- input released until the server acknowledges that release, then send one
		-- fresh Block edge for every coalesced pending request.
		if self.InputData then
			self.InputData.f = false
		end
		if blocking then
			self:_attemptUnblock("waiting for clear", now)
		elseif not self:_hasEffect("Action") and not self:_hasEffect("Knocked") then
			local fired = self:_sendBlock(false)
			if fired then
				for _, item in pairs(self.Queue) do
					item.sent = true
				end
				if self.InputData then
					self.InputData.f = true
				end
				self.ReleaseSent = false
				self.BlockRetryCount = 0
				self.NextBlockRetry = now + 0.12
				self.UnblockAttemptCount = 0
				self.NextUnblockRetry = 0
			end
		end
	elseif active then
		if self.InputData then
			self.InputData.f = true
		end
		if
			not blocking
			and now >= self.NextBlockRetry
			and self.BlockRetryCount < 1
			and not self:_hasEffect("Action")
			and not self:_hasEffect("Knocked")
		then
			self.BlockRetryCount = self.BlockRetryCount + 1
			self.NextBlockRetry = now + 0.12
			self:_sendBlock(true)
		end
	else
		if self.InputData then
			self.InputData.f = false
		end
		-- Release once when the queue drains. The old implementation sent this
		-- remote every rendered frame while the Blocking effect lingered.
		if hadEntries or blocking then
			self:_attemptUnblock("queue drained", now)
		else
			self.UnblockAttemptCount = 0
			self.NextUnblockRetry = 0
		end
	end
end

function NativeInputBridge:_startQueue()
	if self.RenderConnection then
		return
	end
	self.RenderConnection = RunService.RenderStepped:Connect(function()
		self:_updateQueue()
	end)
end

function NativeInputBridge:initialize(force)
	if self.Ready then
		return true, self.Status
	end
	if not force and os.clock() < self.NextRetry then
		return false, self.Status
	end
	self.Initialized = true
	self.NextRetry = os.clock() + 2
	local scanned, reason = self:_scanGC()
	if not scanned then
		self.Ready = false
		self.Status = reason or "native scan failed"
		return false, self.Status
	end
	-- Do not retain or mutate the game's private input-state upvalue. Native
	-- Block/Unblock remotes do not require it, and an executor returning the
	-- wrong RenderStepped closure here can corrupt BackpackClient/weapon input.
	-- Direct dodge/cancel will safely use the ordinary configured fallback when
	-- this optional private state is unavailable.
	self.InputData = nil
	local block = self:_remote("Block")
	local unblock = self:_remote("Unblock")
	if not block or not unblock then
		self.Ready = false
		self.Status = "Block/Unblock remotes unresolved"
		return false, self.Status
	end
	self.Ready = true
	self.Status = self.InputData and "native remotes + input state" or "native remotes"
	self:_startQueue()
	return true, self.Status
end

function NativeInputBridge:block(duration, deflect)
	local ready, reason = self:initialize()
	if not ready then
		return false, reason
	end
	if self:_hasEffect("CastingSpell") then
		return false, "casting spell"
	end
	self:_removeEffect("M1Buffering")
	if self.SprintFunction then
		pcall(self.SprintFunction, false)
	end

	local now = os.clock()
	local blocking = self:_hasEffect("Blocking")
	local hasSent = false
	for _, item in pairs(self.Queue) do
		if item.sent then
			hasSent = true
			break
		end
	end
	self.NextQueueID = self.NextQueueID + 1
	local item = {
		deflect = deflect == true,
		expires = now
			+ (deflect and math.max(0.20, tonumber(duration) or 0) or math.max(0.05, tonumber(duration) or 0.30)),
		sent = false,
	}
	self.Queue[self.NextQueueID] = item

	if blocking then
		self.LastTransition = "queued until block clears"
		if self.InputData then
			self.InputData.f = false
		end
		return true, "LycorisNativeQueued"
	end
	if hasSent then
		-- Multiple detections inside one unacknowledged parry window share the
		-- already-sent Block edge instead of multiplying remote traffic.
		item.sent = true
		self.Stats.Coalesced = self.Stats.Coalesced + 1
		self.LastTransition = "coalesced"
		return true, "LycorisNativeCoalesced"
	end

	local fired, fireReason = self:_sendBlock(false)
	if not fired then
		self.Queue[self.NextQueueID] = nil
		return false, fireReason
	end
	item.sent = true
	self.ReleaseSent = false
	self.BlockRetryCount = 0
	self.NextBlockRetry = now + 0.12
	self.UnblockAttemptCount = 0
	self.NextUnblockRetry = 0
	if self.InputData then
		self.InputData.f = true
	end
	return true, "LycorisNative"
end

function NativeInputBridge:invalidate(reason)
	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end
	if self.InputData then
		self.InputData.f = false
	end
	table.clear(self.Queue)
	self.NextBlockRetry = 0
	self.BlockRetryCount = 0
	self.NextUnblockRetry = 0
	self.UnblockAttemptCount = 0
	self.ReleaseSent = true
	self.LastTransition = "idle"
	self.InputData = nil
	self.SprintFunction = nil
	self.Initialized = false
	self.Ready = false
	self.NextRetry = 0
	self.Status = reason or "invalidated"
end

function NativeInputBridge:Destroy()
	if self.Ready then
		self:_sendUnblock("destroyed")
	end
	self:invalidate("destroyed")
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
		self.CharacterConnection = nil
	end
end

return NativeInputBridge

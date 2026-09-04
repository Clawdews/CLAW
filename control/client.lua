-- No GUI, input hooks or movement. Discord config + the tested exact-ID join route.
local BASE = "https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/"
local env = getgenv()
local config = env.CLAW_CONTROL_CONFIG
assert(type(config) == "table", "Set private CLAW_CONTROL_CONFIG before loading")
local endpoint = tostring(config.Endpoint or ""):gsub("/+$", "")
assert(endpoint:match("^https://[%w%.%-]+$"), "Endpoint must be your HTTPS relay origin, with no path or query")
local ownerId = config.OwnerId
assert(ownerId == nil or (type(ownerId) == "string" and ownerId:match("^%d+$") and #ownerId >= 17 and #ownerId <= 20), "Invalid Discord owner ID")
local ownerQuery = ownerId and ("?owner=" .. ownerId) or ""
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Replicated = game:GetService("ReplicatedStorage")
local Teleport = game:GetService("TeleportService")
local Run = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "CLAW CONTROL requires a client")
local accountId = tostring(player.UserId)
local key = config.Accounts and (config.Accounts[accountId] or config.Accounts[player.UserId]) or config.Key
assert(type(key) == "string" and #key == 64 and key:match("^[a-fA-F0-9]+$"), "This account has no valid private pairing key")
local http = request or http_request
local wsLibrary = WebSocket or websocket
assert(type(http) == "function" and wsLibrary and type(wsLibrary.connect) == "function", "Volt HTTP and WebSocket support required")
local function module(path)
	local source = game:HttpGet(BASE .. path .. "?cache=" .. Http:GenerateGUID(false))
	local chunk, failure = loadstring(source, "@CLAW/" .. path)
	assert(chunk, failure)
	return chunk()
end
local Core, Auto, Regions = module("join/core.lua"), module("control/auto.lua"), module("control/regions.lua")
assert(Core.VERSION == "0.1.0" and Auto.VERSION == "0.2.0-beta.1", "Module version mismatch")
if env.CLAW_CONTROL and type(env.CLAW_CONTROL.destroy) == "function" then env.CLAW_CONTROL:destroy() end

local file = "CLAW_CONTROL_BETA/" .. (ownerId or "single") .. "-" .. accountId .. ".json"
local setting = "CLAW_CONTROL_BETA_" .. (ownerId or "single") .. "_" .. accountId
local connections, socketConnections = {}, {}
local core, auto, coreSaved, selectedSlot, saved
local stopped, busy, socket, socketGeneration = false, false, nil, 0
local reconnectAt, backoff, presenceAt, packetAt = 0, 2, 0, 0
local networkProblem
local api = {}
local function decode(raw, maximum)
	if type(raw) ~= "string" or #raw > (maximum or 32768) then return nil end
	local ok, value = pcall(Http.JSONDecode, Http, raw)
	return ok and type(value) == "table" and value or nil
end
local function readSaved()
	local newest
	local function consider(raw)
		local value = decode(raw)
		if not value or value.version ~= 1 or value.accountId ~= accountId or value.endpoint ~= endpoint or value.ownerId ~= ownerId
			or type(value.revision) ~= "number" then return end
		if not newest or value.revision > newest.revision then newest = value end
	end
	local ok, raw = pcall(Teleport.GetTeleportSetting, Teleport, setting)
	if ok then consider(raw) end
	if type(readfile) == "function" then ok, raw = pcall(readfile, file); if ok then consider(raw) end end
	return newest
end
saved = readSaved()
coreSaved = saved and saved.core
local storageRevision = saved and saved.revision or 0
local function save()
	storageRevision += 1
	local raw = Http:JSONEncode({ version = 1, accountId = accountId, endpoint = endpoint, revision = storageRevision,
		ownerId = ownerId, updatedAt = os.time(), status = auto and auto.status, core = coreSaved, auto = auto and auto:serialize() or nil })
	local memoryOK = pcall(function()
		Teleport:SetTeleportSetting(setting, raw)
		assert(Teleport:GetTeleportSetting(setting) == raw)
	end)
	local fileOK = false
	if type(writefile) == "function" and type(readfile) == "function" and type(makefolder) == "function" and type(isfolder) == "function" then
		fileOK = pcall(function()
			if not isfolder("CLAW_CONTROL_BETA") then makefolder("CLAW_CONTROL_BETA") end
			writefile(file, raw); assert(readfile(file) == raw)
		end)
	end
	return memoryOK or fileOK
end
local function current()
	local slot = player:GetAttribute("DataSlot")
	if game.PlaceId == Core.LOBBY_PLACE_ID and selectedSlot then slot = selectedSlot end
	return { userId = player.UserId, gameId = game.GameId, placeId = game.PlaceId, jobId = game.JobId, slot = slot }
end
local function remote(name, menu)
	local parent = Replicated:FindFirstChild("Requests")
	if menu then parent = parent and parent:FindFirstChild("StartMenu") end
	local found = parent and parent:FindFirstChild(name)
	return found and found:IsA("RemoteEvent") and found or nil
end
local function fire(name, menu, ...)
	local request = remote(name, menu)
	if not request then return false end
	request:FireServer(...)
	return true
end
core = Core.new({ now = os.time, current = current, nonce = function() return Http:GenerateGUID(false) end,
	save = function(payload) coreSaved = payload; return save() end,
	canJoin = function() return remote("PickServer", true) ~= nil end,
	join = function(id) assert(fire("PickServer", true, id), "PickServer unavailable") end,
	hasPlayer = function(id) return Players:GetPlayerByUserId(id) ~= nil end,
})
auto = Auto.new({ now = os.time, current = current, save = save,
	requireRegionCheck = true,
	chooseSlot = function(profile, placeId) return Regions.choose(profile, placeId, profile.catalog, os.time()) end,
	regionMatches = function(placeId)
		local expected, actual = Regions.forPlace(placeId), Regions.normalize(core.realm)
		return expected ~= nil and actual == expected, "REGION_MISMATCH: selected " .. tostring(core.realm) .. "; main requires " .. tostring(expected)
	end,
	validTicket = function(ticket) return Core.validateTicket(ticket, os.time()) end,
	joinState = function() return core.state end,
	hasMain = function(id) return Players:GetPlayerByUserId(id) ~= nil end,
	allowMenuReturn = config.AllowMenuReturn == true,
	returnMenu = function() return fire("ReturnToMenu", false) end,
	confirmMenu = function()
		local gui = player:FindFirstChild("PlayerGui")
		local prompt = gui and gui:FindFirstChild("ChoicePrompt")
		if not prompt or prompt:GetAttribute("Title") ~= "Return to Main Menu" then return false end
		local choice = prompt:FindFirstChild("Choice")
		if not choice or not choice:IsA("RemoteEvent") then return false end
		choice:FireServer(true); return true
	end,
	pickSlot = function(slot)
		selectedSlot = slot; core.realm = nil
		return fire("PickSlot", true, slot)
	end,
	slotReady = function() return selectedSlot ~= nil and auto.attempt and selectedSlot == auto.attempt.slot and core.realm ~= nil end,
	beginJoin = function(ticket) return core:begin(ticket) end,
	changed = function(status) print("[CLAW CONTROL] " .. status); if auto then save() end end,
}, saved and saved.auto)
if saved and saved.core then core:resume(saved.core) end

local function connect(signal, callback)
	local connection = signal:Connect(callback); connections[#connections + 1] = connection; return connection
end
local showRemote, showConnection
local function bindSlot()
	local found = remote("ShowServers", false)
	if found == showRemote then return end
	if showConnection then showConnection:Disconnect() end
	showRemote, showConnection = found, nil
	if found then showConnection = found.OnClientEvent:Connect(function(realm) core:onServers(realm) end) end
end
bindSlot()
connect(player.OnTeleport, function(state)
	if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then core:teleportStarted() end
end)
connect(Teleport.TeleportInitFailed, function(who, result)
	if who == player then core:teleportFailed(tostring(result)) end
end)
local function disconnect()
	socketGeneration += 1
	for _, connection in ipairs(socketConnections) do connection:Disconnect() end
	table.clear(socketConnections)
	local old = socket; socket = nil
	if old then pcall(function() old:Close() end) end -- Stop Volt's own reconnect; obtain a fresh single-use ticket instead.
	auto:disconnected()
	reconnectAt = os.clock() + backoff + math.random()
	backoff = math.min(backoff * 2, 60)
end
local function send(value)
	if not socket then return false end
	local ok = pcall(function() socket:Send(Http:JSONEncode(value)) end)
	if not ok then disconnect() end
	return ok
end
local function connectRelay()
	if stopped or busy then return end
	busy = true
	local generation = socketGeneration
	local ok, response = pcall(http, { Url = endpoint .. "/session" .. ownerQuery, Method = "POST",
		Headers = { ["Content-Type"] = "application/json" }, Body = Http:JSONEncode({ accountId = accountId, key = key }) })
	if stopped or generation ~= socketGeneration then busy = false; return end
	if not ok or type(response) ~= "table" or response.StatusCode ~= 200 then
		busy = false; disconnect()
		if ok and type(response) == "table" and response.StatusCode == 401 then
			networkProblem = "AUTH_FAILED: check account pairing"
			reconnectAt = os.clock() + 300; auto:statusAs(networkProblem)
		end
		return
	end
	local payload = decode(response.Body, 2048)
	if not payload or type(payload.ticket) ~= "string" or not payload.ticket:match("^" .. accountId .. "%.[a-fA-F0-9%-]+$") then
		busy = false; disconnect(); return
	end
	local success, connected = pcall(wsLibrary.connect, endpoint:gsub("^https:", "wss:") .. "/socket" .. (ownerId and (ownerQuery .. "&") or "?") .. "ticket=" .. payload.ticket)
	busy = false
	if not success then disconnect(); return end
	if stopped or generation ~= socketGeneration then pcall(function() connected:Close() end); return end
	socket = connected; packetAt = os.clock(); presenceAt = os.clock() + 2.2
	socketConnections[#socketConnections + 1] = connected.OnMessage:Connect(function(raw)
		if stopped or socket ~= connected then return end
		local data = decode(raw, 32768) -- A full 30-character catalog plus approvals can exceed 8 KiB.
		if not data then disconnect(); return end
		packetAt = os.clock(); backoff = 2
		if data.type == "profile" then
			if (ownerId and data.ownerId ~= ownerId) or not auto:setProfile(data) then disconnect() else networkProblem = nil end
		elseif data.type == "target" then auto:setTarget(data)
		else disconnect() end
	end)
	socketConnections[#socketConnections + 1] = connected.OnClose:Connect(function()
		if socket == connected then disconnect() end
	end)
	send({ type = "hello" })
end
local elapsed, ticking = 0, false
connect(Run.Heartbeat, function(dt)
	if stopped then return end
	elapsed += dt; if elapsed < 1 then return end; elapsed = 0
	bindSlot()
	if not ticking then
		ticking = true
		local ok = pcall(function()
			core:tick()
			if networkProblem and not auto.profile then auto:statusAs(networkProblem) else auto:tick() end
		end)
		if not ok then auto:hold("local lifecycle error; inspect state before retrying") end
		ticking = false
	end
	if socket and os.clock() - packetAt > 40 then disconnect() end
	if socket and os.clock() >= presenceAt then
		presenceAt = os.clock() + 10
		local snapshot = current(); snapshot.state = auto.status
		send({ type = "presence", current = snapshot })
	elseif not socket and not busy and os.clock() >= reconnectAt then task.spawn(connectRelay) end
end)
function api:destroy()
	if stopped then return end
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	if showConnection then showConnection:Disconnect() end
	disconnect()
	if env.CLAW_CONTROL == self then env.CLAW_CONTROL = nil end
end
function api:report()
	return { version = Auto.VERSION, status = auto.status, accountId = accountId, current = current(),
		join = core:report(), attempt = auto.attempt, connected = socket ~= nil, connectionProblem = networkProblem }
end
env.CLAW_CONTROL = api
if env.CLAW_RELAY then warn("[CLAW CONTROL] Disable competing relay auto-start on this account during join testing; no other script was changed.") end
task.spawn(connectRelay)
return api

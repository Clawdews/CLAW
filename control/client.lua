-- One client for joining, account status, item scans and owner-approved movement.
local BASE = "https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/"
local BUILD_ID = "source"
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
local MenuScan, Catalog = module("control/menu-scan.lua"), module("control/catalog.lua")
local Movement = module("control/movement.lua")
assert(Core.VERSION == "0.1.0" and Auto.VERSION == "0.3.0-beta.2", "Module version mismatch")
if env.CLAW_CONTROL and type(env.CLAW_CONTROL.destroy) == "function" then env.CLAW_CONTROL:destroy() end

local file = "CLAW_CONTROL_BETA/" .. (ownerId or "single") .. "-" .. accountId .. ".json"
local setting = "CLAW_CONTROL_BETA_" .. (ownerId or "single") .. "_" .. accountId
local connections, socketConnections = {}, {}
local core, auto, coreSaved, selectedSlot, saved
local stopped, busy, socket, socketGeneration = false, false, nil, 0
local reconnectAt, backoff, presenceAt, packetAt = 0, 2, 0, 0
local networkProblem
local movement, movementState = nil, "idle"
local actionResults, inventoryAt, lastInventory = {}, 0, nil
local menuCatalog, scanBusy, scanAt, catalogSentAt, catalogPending = nil, false, 0, 0, false
local menuSignature, sentSignature
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
if saved and type(saved.actions) == "table" then
	local restored = 0
	for id, result in pairs(saved.actions) do
		if type(id) == "string" and #id <= 160 and id:match("^[%w%-]+$") and type(result) == "table"
			and type(result.ok) == "boolean" and type(result.message) == "string" and #result.message <= 160 then
			actionResults[id] = { ok = result.ok, message = result.message }
			restored += 1
			if restored >= 30 then break end
		end
	end
end
local function save()
	storageRevision += 1
	local encoded, raw = pcall(Http.JSONEncode, Http, { version = 1, accountId = accountId, endpoint = endpoint, revision = storageRevision,
		ownerId = ownerId, updatedAt = os.time(), status = auto and auto.status, core = coreSaved,
		auto = auto and auto:serialize() or nil, actions = actionResults })
	-- A failed encoder may include private state in its error. Never write or expose it.
	if not encoded or type(raw) ~= "string" or #raw == 0 or #raw > 32768 then return false end
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position
	return { userId = player.UserId, gameId = game.GameId, placeId = game.PlaceId, jobId = game.JobId, slot = slot,
		position = position and { x = position.X, y = position.Y, z = position.Z } or nil,
		movement = movementState }
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
movement = Movement.new(function(state) movementState = state end)
auto = Auto.new({ now = os.time, current = current, save = save,
	requireRegionCheck = true,
	chooseSlot = function(profile, placeId)
		if game.PlaceId == Core.LOBBY_PLACE_ID then
			if not menuCatalog or not menuCatalog.scanComplete or os.time() - menuCatalog.observedAt > 20 then
				return nil, "WAITING_SLOT_SCAN: reading current character cards"
			end
			-- A reused slot letter must not inherit permission before the cloud has
			-- seen this character and cleared any previous character's approval.
			local synced = {}
			for _, card in ipairs(profile.catalog or {}) do synced[card.slot] = card end
			for _, card in ipairs(menuCatalog.cards) do
				local known = synced[card.slot]
				if profile.approvedSlots and profile.approvedSlots[card.slot] and
					(not known or (known.source == "menu-card" and not known.complete)
						or known.characterName ~= card.characterName or known.level ~= card.level) then
					return nil, "WAITING_SLOT_SYNC: waiting for current character permissions"
				end
			end
			return Regions.choose(profile, placeId, menuCatalog.cards, os.time())
		end
		return Regions.choose(profile, placeId, profile.catalog, os.time())
	end,
	regionMatches = function(placeId)
		local expected, actual = Regions.forPlace(placeId), Regions.normalize(core.realm)
		return expected ~= nil and actual == expected, "REGION_MISMATCH: selected " .. tostring(core.realm) .. "; main requires " .. tostring(expected)
	end,
	validTicket = function(ticket) return Core.validateTicket(ticket, os.time()) end,
	joinState = function() return core.state end,
	hasMain = function(id) return Players:GetPlayerByUserId(id) ~= nil end,
	allowMenuReturn = function()
		local cloud = auto and auto.profile and auto.profile.allowMenuReturn
		if type(cloud) == "boolean" then return cloud end
		return config.AllowMenuReturn == true -- Older pairings retain their explicit local opt-in until overridden.
	end,
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
	changed = function(status)
		print("[CLAW CONTROL] " .. status)
		if auto and not save() then auto.storageBlocked = true end
	end,
}, saved and saved.auto)
if saved and saved.core and core:resume(saved.core) then
	local pending = { REQUESTED = true, TRAVELLING = true, WAITING_MAIN = true }
	if pending[saved.core.state] then
		-- Recover the validated in-flight join, not menu/slot work from an incomplete snapshot.
		local operation, ticket = core.operation, core.operation.ticket
		auto.attempt = { phase = "JOINING", slot = operation.slot, startedAt = operation.startedAt, deadline = operation.deadline,
			key = tostring(ticket.gameId) .. "." .. tostring(ticket.placeId) .. "." .. ticket.jobId }
		auto:save()
	end
end

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
local function itemName(value)
	if type(value) ~= "string" then return nil end
	value = value:match("^%s*(.-)%s*$")
	if value == "" or #value > 80 or value:find("[%c]") then return nil end
	return value
end
local function addItem(counts, name, amount)
	name = itemName(name)
	if not name then return end
	counts[name] = math.clamp((counts[name] or 0) + (amount or 1), 1, 9999)
end
local function sortedItems(counts)
	local items = {}
	for name, count in pairs(counts) do items[#items + 1] = { name = name, count = count } end
	table.sort(items, function(a, b) return a.name < b.name end)
	while #items > 200 do table.remove(items) end
	return items
end
local function scanItems()
	local inventory = {}
	for _, parent in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		for _, child in ipairs(parent and parent:GetChildren() or {}) do
			if child:IsA("Tool") then
				local name = child:GetAttribute("ItemName")
				if type(name) ~= "string" or name == "" then name = child.Name end
				if not name:match("^Talent:") and not name:match("^Mantra:") then addItem(inventory, name) end
			end
		end
	end
	local bank, gui = {}, player:FindFirstChildOfClass("PlayerGui")
	for _, object in ipairs(gui and gui:GetDescendants() or {}) do
		local parent, visibleBank = object, false
		for _ = 1, 8 do
			parent = parent and parent.Parent
			local label = parent and tostring(parent.Name):lower() or ""
			if label:find("bank", 1, true) or label:find("storage", 1, true) then visibleBank = true; break end
		end
		if visibleBank then
			local name = object:GetAttribute("ItemName") or object:GetAttribute("Item") or object:GetAttribute("ToolName")
			if type(name) == "string" then addItem(bank, name, tonumber(object:GetAttribute("Amount")) or 1) end
		end
	end
	local packet = { type = "inventory", version = 1, accountId = accountId,
		inventory = sortedItems(inventory), bank = sortedItems(bank) }
	if lastInventory then
		local gained = {}
		for name, count in pairs(inventory) do
			local difference = count - (lastInventory[name] or 0)
			if difference > 0 then gained[#gained + 1] = { name = name, count = difference } end
		end
		if #gained > 0 then send({ type = "loot", version = 1, accountId = accountId, items = gained }) end
	end
	lastInventory = inventory
	return send(packet)
end
local function actionReply(id, ok, message)
	message = tostring(message or (ok and "completed" or "failed")):gsub("[%c]", " "):sub(1, 160)
	actionResults[id] = { ok = ok == true, message = message }
	local count = 0
	for _ in pairs(actionResults) do count += 1 end
	if count > 30 then actionResults = { [id] = actionResults[id] } end
	save() -- Prevent an acknowledged command from running again after a teleport or restart.
	return send({ type = "action-result", accountId = accountId, id = id, ok = ok == true, message = message })
end
local function handleAction(data)
	if type(data.id) ~= "string" or #data.id > 160 or type(data.expiresAt) ~= "number" or data.expiresAt <= os.time()
		or data.expiresAt > os.time() + 300 or type(data.args) ~= "table" then return disconnect() end
	if data.action ~= "stop" and data.action ~= "scan-items" and data.action ~= "bring" and data.action ~= "park" then
		return disconnect()
	end
	local previous = actionResults[data.id]
	if previous then return actionReply(data.id, previous.ok, previous.message) end
	if data.action == "stop" then
		movement:stop("stopped by owner")
		return actionReply(data.id, true, "movement stopped")
	end
	if data.action == "scan-items" then
		local ok = scanItems()
		return actionReply(data.id, ok, ok and "item scan sent" or "item scan could not be sent")
	end
	if not auto.profile or auto.profile.role ~= "alt" or auto.profile.halted == true then
		return actionReply(data.id, false, "account is not available for movement")
	end
	if data.action == "bring" then
		if tostring(data.args.mainId) ~= tostring(auto.profile.mainId) then return actionReply(data.id, false, "main changed") end
		local ok, reason = movement:bring(data.args.mainId, data.args.offset)
		return actionReply(data.id, ok, reason)
	end
	if data.action == "park" then
		local ok, reason = movement:park(data.args.position, data.args.placeId, data.args.jobId)
		return actionReply(data.id, ok, reason)
	end
	return disconnect()
end
local function connectRelay()
	if stopped or busy then return end
	busy = true
	local generation = socketGeneration
	local ok, response = pcall(function()
		return http({ Url = endpoint .. "/session" .. ownerQuery, Method = "POST",
			Headers = { ["Content-Type"] = "application/json" }, Body = Http:JSONEncode({ accountId = accountId, key = key }) })
	end)
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
		local data = decode(raw, 65536) -- Bounded 60-card compact roster; never raw UI reports.
		if not data then disconnect(); return end
		packetAt = os.clock(); backoff = 2
		if data.type == "profile" then
			if (ownerId and data.ownerId ~= ownerId) or not auto:setProfile(data) then disconnect() else
				networkProblem = nil
				if data.halted == true or data.enabled == false then movement:stop(data.halted and "emergency stop" or "standby") end
			end
		elseif data.type == "target" then auto:setTarget(data)
		elseif data.type == "action" and data.version == 1 then handleAction(data)
		else disconnect() end
	end)
	socketConnections[#socketConnections + 1] = connected.OnClose:Connect(function()
		if socket == connected then disconnect() end
	end)
	send({ type = "hello", username = player.Name })
	catalogPending = menuCatalog ~= nil; catalogSentAt = 0; sentSignature = nil; inventoryAt = 0
end
local function refreshMenu()
	if stopped or scanBusy then return end
	scanBusy = true
	local ok, result = pcall(function()
		local report = MenuScan.collect(player:FindFirstChild("PlayerGui"), function() task.wait() end)
		return Catalog.fromScan(report, accountId, os.time())
	end)
	if not stopped and game.PlaceId == Core.LOBBY_PLACE_ID then
		menuCatalog = ok and result or nil
		menuSignature = menuCatalog and Catalog.signature(menuCatalog) or nil
		catalogPending = menuCatalog ~= nil and (menuSignature ~= sentSignature or os.clock() - catalogSentAt >= 300)
	end
	scanBusy = false
end
local elapsed, ticking = 0, false
connect(Run.Heartbeat, function(dt)
	if stopped then return end
	elapsed += dt; if elapsed < 1 then return end; elapsed = 0
	bindSlot()
	if game.PlaceId == Core.LOBBY_PLACE_ID and os.clock() >= scanAt and not scanBusy then
		scanAt = os.clock() + 10; task.spawn(refreshMenu)
	elseif game.PlaceId ~= Core.LOBBY_PLACE_ID then menuCatalog = nil; catalogPending = false; scanAt = 0 end
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
	if socket and auto.profile and catalogPending and os.clock() - catalogSentAt >= 10 then
		if send(menuCatalog) then catalogSentAt = os.clock(); sentSignature = menuSignature; catalogPending = false end
	end
	if socket and os.clock() >= presenceAt then
		presenceAt = os.clock() + 10
		local snapshot = current(); snapshot.state = auto.status
		send({ type = "presence", current = snapshot })
	elseif not socket and not busy and os.clock() >= reconnectAt then task.spawn(connectRelay) end
	if socket and game.PlaceId ~= Core.LOBBY_PLACE_ID and os.clock() >= inventoryAt then
		inventoryAt = os.clock() + 60
		task.spawn(scanItems)
	end
end)
function api:destroy()
	if stopped then return end
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	if showConnection then showConnection:Disconnect() end
	if movement then movement:destroy() end
	disconnect()
	if env.CLAW_CONTROL == self then env.CLAW_CONTROL = nil end
end
function api:report()
	return { version = Auto.VERSION, status = auto.status, accountId = accountId, current = current(),
		join = core:report(), attempt = auto.attempt, connected = socket ~= nil, connectionProblem = networkProblem,
		menu = menuCatalog and { status = menuCatalog.status, cards = #menuCatalog.cards,
			complete = menuCatalog.complete, scanComplete = menuCatalog.scanComplete } }
end
function api:supportReport()
	-- Share fixed states, never copy free-form errors, tickets or profile fields.
	local nextSteps = {
		CONNECTING = "Wait for the cloud connection.", RECONNECTING = "Check your connection and leave the loader running.",
		AUTH_FAILED = "Check the account's private pairing; see Recover pairing in the setup guide.",
		MAIN = "Keep the main online in the world.", PAUSED = "Enable follow in Discord when ready.",
		WAITING_MAIN = "Keep the main online in the world and check /claw status privately.",
		WAITING_MAIN_PRESENCE = "Wait for the main to appear; arrival is not confirmed.",
		WAITING_MENU = "Return this alt to character selection.",
		WAITING_SLOT_SCAN = "Leave character selection open until its cards can be read.",
		WAITING_SLOT_SYNC = "Wait for character cards to sync, then check slot approval in Discord.",
		NEEDS_SLOT = "Choose and approve a character in Discord.", NO_APPROVED_SLOT = "Approve a character in Discord.",
		NO_COMPATIBLE_SLOT = "Approve a character in the main's region.",
		CHOOSE_PREFERRED_SLOT = "Choose a preferred character in Discord.",
		UNSUPPORTED_REGION = "This location is not supported for following.",
		WAITING_TARGET_SETTLE = "Wait for the main destination to settle.",
		RETURN_MENU = "Wait for the normal return-to-menu flow.", WAIT_SLOT = "Wait for character selection to finish.",
		JOINING = "Wait for arrival verification; do not send another join.",
		REQUESTED = "Wait for arrival verification; do not send another join.",
		TRAVELLING = "Wait for arrival verification; do not send another join.",
		VERIFIED = "Arrival was checked by this client.", WITH_MAIN = "The client reports it is already with the main.",
		ATTENTION = "Read /claw status privately and fix its reason before retrying.",
		STOPPED = "Start the public loader again when ready.", UNKNOWN = "Read /claw status privately for more information.",
	}
	local code = stopped and "STOPPED" or (type(auto.status) == "string" and auto.status:match("^([A-Z_]+)"))
	if not nextSteps[code] then code = "UNKNOWN" end
	local joinStates = { IDLE = true, SLOT_READY = true, REQUESTED = true, TRAVELLING = true, WAITING_MAIN = true,
		VERIFIED = true, STALE = true, FAILED = true, TIMED_OUT = true, WRONG_DESTINATION = true, CANCELLED = true }
	local menu = "not-in-menu"
	if game.PlaceId == Core.LOBBY_PLACE_ID then
		menu = not menuCatalog and "not-read" or (os.time() - menuCatalog.observedAt > 20 and "stale"
			or (menuCatalog.complete and "complete" or (menuCatalog.scanComplete and "partial-details" or "incomplete")))
	end
	return table.concat({ "CLAW SUPPORT 1", "release=" .. Auto.VERSION, "build=" .. BUILD_ID,
		"client=" .. (stopped and "stopped" or "running"),
		"connection=" .. (socket and (auto.profile and "ready" or "waiting-profile") or "offline"),
		"status=" .. code, "join=" .. (joinStates[core.state] and core.state or "UNKNOWN"), "menu=" .. menu,
		"storage=" .. (auto.storageBlocked == nil and "not-tested" or (auto.storageBlocked and "unavailable" or "ready")),
		"next=" .. nextSteps[code] }, "\n")
end
env.CLAW_CONTROL = api
if env.CLAW_RELAY then warn("[CLAW CONTROL] Disable competing relay auto-start on this account during join testing; no other script was changed.") end
task.spawn(connectRelay)
return api

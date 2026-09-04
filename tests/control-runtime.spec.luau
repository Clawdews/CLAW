return function(clientSource, autoSource, coreSource, regionSource, menuSource, catalogSource, pairedLauncher)
	local function clone(value)
		if type(value) ~= "table" then return value end
		local copy = {}; for k, v in pairs(value) do copy[k] = clone(v) end; return copy
	end
	local function signal()
		local list, s = {}, {}
		function s:Connect(callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			list[#list + 1] = { connection, callback }; return connection
		end
		function s:Fire(...)
			for _, pair in ipairs(list) do if pair[1].Connected then pair[2](...) end end
		end
		return s
	end
	local function object(class)
		local o = { ClassName = class, children = {}, OnClientEvent = signal() }
		function o:IsA(name) return self.ClassName == name or (name == "GuiObject" and (class == "Frame" or class == "TextLabel" or class == "TextButton" or class == "ScrollingFrame")) end
		function o:GetChildren()
			local result = {}; for key, child in pairs(self.children) do child.Name = key; table.insert(result, child) end; return result
		end
		function o:FindFirstChild(name) return self.children[name] end
		function o:GetAttribute(name) return self[name] end
		return o
	end
	local function boot(options)
		options = options or {}
		if pairedLauncher then options.owner = options.owner or "123456789012345678" end
		local f = { now = 2000000000, clock = 0, files = {}, memory = {}, values = {}, encoded = 0,
			picks = 0, joins = 0, menus = 0, confirms = 0, sockets = {}, packets = {}, logs = {}, hasMain = false, authRequests = 0, encodeFailures = 0 }
		f.cloudMenu = options.cloudMenu
		f.env = { CLAW_CONTROL_CONFIG = { Endpoint = "https://claw-test.example", Key = string.rep("a", 64),
			AllowMenuReturn = options.menu == true, OwnerId = options.owner } }
		local http = {}
		function http:JSONEncode(value)
			if options.requestEncodeFail and value.key then f.encodeFailures += 1; error("encoder included " .. value.key) end
			f.encoded += 1; local key = "json-" .. f.encoded; f.values[key] = clone(value); return key
		end
		function http:JSONDecode(key) return clone(assert(f.values[key], "invalid JSON")) end
		function http:GenerateGUID() return "nonce-1" end
		f.http = http
		local player = object("Player"); player.UserId = options.main and 11 or 22; player.OnTeleport = signal()
		player.DataSlot = options.slot
		f.player = player
		if pairedLauncher then
			local pairing = clone(f.env.CLAW_CONTROL_CONFIG); pairing.Version = 1; pairing.AccountId = tostring(player.UserId)
			if options.firstPair then f.env.CLAW_PAIR = pairing
			else f.files["CLAW_PAIRINGS/" .. pairing.AccountId .. ".json"] = http:JSONEncode(pairing) end
		end
		local gui = object("PlayerGui"); player.children.PlayerGui = gui
		if not options.noMenu then
			local parent = gui
			for _, name in ipairs({ "LoadingGui", "Overlay", "Columns", "MainFrame", "Slots", "SlotScroll", "L" }) do
				local next = object("Frame"); parent.children[name] = next; parent = next
			end
			for name, value in pairs({ CharacterName = "Test Character", Race = "Khan", Level = "Lv. 1", Realm = "Etrean Luminant", Slot = "L" }) do
				local label = object("TextLabel"); label.Text = value; parent.children[name] = label
			end
		end
		f.prompt = object("Frame"); f.prompt.Title = "Some unrelated choice"; gui.children.ChoicePrompt = f.prompt
		local choice = object("RemoteEvent"); f.prompt.children.Choice = choice
		function choice:FireServer(value) assert(value == true); f.confirms += 1 end
		local players = { LocalPlayer = player }
		function players:GetPlayerByUserId(id) return id == 11 and f.hasMain and {} or nil end
		local rep, requests, menu = object("ReplicatedStorage"), object("Folder"), object("Folder")
		rep.children.Requests = requests; requests.children.StartMenu = menu
		local show, pick, join, ret = object("RemoteEvent"), object("RemoteEvent"), object("RemoteEvent"), object("RemoteEvent")
		requests.children.ShowServers = show; requests.children.ReturnToMenu = ret
		menu.children.PickSlot = pick; menu.children.PickServer = join
		function pick:FireServer(slot) assert(slot == "L"); f.picks += 1; show.OnClientEvent:Fire(options.wrongRegion and "EastLuminant" or "EtreanLuminant") end
		function join:FireServer(id) assert(id == "main-job"); f.joins += 1 end
		function ret:FireServer() f.menus += 1 end
		local teleport = { TeleportInitFailed = signal() }
		function teleport:GetTeleportSetting(key) return f.memory[key] end
		function teleport:SetTeleportSetting(key, raw) assert(not options.storageFail); f.memory[key] = raw end
		local run = { Heartbeat = signal() }; f.heartbeat = run.Heartbeat
		local services = { HttpService = http, Players = players, ReplicatedStorage = rep, TeleportService = teleport, RunService = run }
		f.game = { GameId = 99, PlaceId = options.world and 456 or 4111023553, JobId = "origin-job" }
		function f.game:GetService(name) return assert(services[name], name) end
		function f.game:HttpGet(url)
			if url:find("join/core.lua", 1, true) then return coreSource end
			if url:find("control/regions.lua", 1, true) then return regionSource end
			if url:find("control/menu-scan.lua", 1, true) then return menuSource end
			if url:find("control/catalog.lua", 1, true) then return catalogSource end
			return autoSource
		end
		local function target()
			return { type = "target", enabled = true, key = "99.6032399813.main-job", expiresAt = f.now + 35,
				ticket = { version = 1, controllerId = 11, gameId = 99, placeId = 6032399813, jobId = "main-job", joinId = "main-job",
					createdAt = f.now, nonce = "revision-1" } }
		end
		local wsLibrary = {}
		function wsLibrary.connect(url)
			assert(url:find("wss://claw-test.example/socket" .. (options.owner and ("?owner=" .. options.owner .. "&") or "?") .. "ticket=", 1, true) == 1)
			local ws = { OnMessage = signal(), OnClose = signal(), closed = false }
			function ws:Close() self.closed = true; self.OnClose:Fire() end
			function ws:Send(raw)
				assert(not self.closed)
				local value = http:JSONDecode(raw)
				f.packets[#f.packets + 1] = value
				if value.type == "hello" then self.OnMessage:Fire(http:JSONEncode({ type = "profile", accountId = tostring(player.UserId),
					mainId = "11", ownerId = options.wrongOwner and "999999999999999999" or options.owner,
					role = options.main and "main" or "alt", slot = "L", follow = true,
					allowMenuReturn = f.cloudMenu,
					approvedSlots = { ["L"] = true }, catalog = { { slot = "L", region = "EtreanLuminant", observedAt = f.now, confirmed = true,
						characterName = options.oldCharacter and "Previous Character" or "Test Character", level = 1 } } })) end
				self.OnMessage:Fire(http:JSONEncode(target()))
			end
			f.sockets[#f.sockets + 1] = ws
			return ws
		end
		local runtime = setmetatable({ game = f.game, getgenv = function() return f.env end,
			os = { time = function() return f.now end, clock = function() return f.clock end },
			task = { spawn = function(fn) fn() end, wait = function() end }, WebSocket = wsLibrary,
			Enum = { TeleportState = { Started = 1, InProgress = 2 } },
			request = function(request)
				assert(request.Url == "https://claw-test.example/session" .. (options.owner and ("?owner=" .. options.owner) or ""))
				local data = http:JSONDecode(request.Body); assert(data.accountId == tostring(player.UserId)); assert(#data.key == 64)
				f.authRequests += 1
				return { StatusCode = options.badAuth and 401 or 200,
					Body = http:JSONEncode({ ticket = data.accountId .. ".12345678-1234-1234-1234-123456789012" }) }
			end,
			isfolder = function() return true end, makefolder = function() end,
			isfile = function(path) return f.files[path] ~= nil end,
			writefile = function(path, raw) assert(not options.storageFail); f.files[path] = raw end,
			readfile = function(path) return assert(f.files[path]) end,
			warn = function() end,
			print = function(message) f.logs[#f.logs + 1] = message end,
		}, { __index = getfenv() })
		runtime.loadstring = function(source, name)
			local chunk, failure = loadstring(source, name)
			if chunk then setfenv(chunk, runtime) end
			return chunk, failure
		end
		function f:reload()
			local chunk = assert(loadstring(clientSource, "control-client")); setfenv(chunk, runtime); self.api = chunk()
		end
		function f:advance(seconds)
			for _ = 1, seconds do self.now += 1; self.clock += 1; self.heartbeat:Fire(1) end
		end
		f:reload(); return f
	end
	local passed = 0
	local function test(name, fn) fn(); passed += 1; print("PASS runtime " .. name) end
	test("support report omits identities and has no file, network or game side effects", function()
		local f = boot({ owner = "123456789012345678" }); f:advance(3)
		assert(type(f.api.supportReport) == "function", "Missing private-by-default support report")
		local files, memory = clone(f.files), clone(f.memory)
		local packets, requests, encoded, logs = #f.packets, f.authRequests, f.encoded, #f.logs
		local report = f.api:supportReport()
		assert(type(report) == "string" and #report < 1000 and report:find("CLAW SUPPORT 1", 1, true))
		assert(report:find("status=REQUESTED", 1, true) and report:find("connection=ready", 1, true))
		local build = report:match("build=([%w]+)"); assert(build == "source" or (#build == 12 and build:match("^[a-f0-9]+$")))
		for _, private in ipairs({ string.rep("a", 64), "123456789012345678", "claw-test.example", "main-job", "origin-job", "Test Character", "revision-1" }) do
			assert(not report:find(private, 1, true), "Support report included private data")
		end
		assert(f.api:supportReport() == report and packets == #f.packets and requests == f.authRequests and encoded == f.encoded and logs == #f.logs)
		for path, raw in pairs(f.files) do assert(files[path] == raw) end
		for path, raw in pairs(files) do assert(f.files[path] == raw) end
		for path, raw in pairs(f.memory) do assert(memory[path] == raw) end
		assert(f.picks == 1 and f.joins == 1 and f.menus == 0 and f.confirms == 0)
	end)
	test("support report never copies free-form failure details", function()
		local f = boot(); f:advance(3)
		local private = "PRIVATE_" .. string.rep("b", 64) .. "\nsecret-server"
		local attempt = f.api:report().attempt; attempt.phase = "HOLD"; attempt.reason = private
		f:advance(1); assert(f.api:report().status:find(private, 1, true))
		local report = f.api:supportReport()
		assert(report:find("status=ATTENTION", 1, true) and not report:find(private, 1, true) and not report:find("secret-server", 1, true))
		assert(not report:find(string.rep("b", 64), 1, true))
	end)
	test("support report explains pairing and menu waits without claiming arrival", function()
		for _, case in ipairs({ { options = { badAuth = true }, status = "AUTH_FAILED", next = "pairing" },
			{ options = { noMenu = true }, status = "WAITING_SLOT_SCAN", next = "character selection" },
			{ options = { world = true }, status = "WAITING_MENU", next = "character selection" } }) do
			local f = boot(case.options); f:advance(3); local report = f.api:supportReport()
			assert(report:find("status=" .. case.status, 1, true) and report:find("next=", 1, true) and report:find(case.next, 1, true))
			assert(not report:find("VERIFIED", 1, true))
			f.api:destroy(); report = f.api:supportReport()
			assert(report:find("client=stopped", 1, true) and report:find("connection=offline", 1, true))
		end
	end)
	test("session encode errors remain private and reconnect can recover", function()
		local options = { requestEncodeFail = true }
		local ok, f = pcall(boot, options)
		assert(ok, "Session setup leaked an unhandled encoder error")
		assert(f.authRequests == 0 and f.encodeFailures == 1 and not f.api:report().connected)
		f:advance(10); assert(f.encodeFailures > 1 and f.authRequests == 0)
		options.requestEncodeFail = false
		f:advance(60); assert(f.authRequests == 1 and f.api:report().connected)
		f.api:destroy()
	end)
	test("autoexec selects saved slot and joins without clipboard or GUI", function()
		local f = boot(); f:advance(2); assert(f.picks == 1 and f.joins == 1)
		f:advance(10); assert(f.joins == 1)
	end)
	test("post-teleport reload verifies and never resends", function()
		local f = boot(); f:advance(2); f.game.PlaceId = 6032399813; f.game.JobId = "main-job"; f.player.DataSlot = "L"; f.hasMain = true
		f:reload(); f:advance(2); assert(f.joins == 1 and f.api:report().status == "VERIFIED")
	end)
	test("reload while join is pending retains core persistence", function()
		local f = boot(); f:advance(2); f:reload(); f:advance(2); f:reload(); f:advance(2)
		assert(f.joins == 1 and f.api:report().join.state == "REQUESTED")
	end)
	test("main only publishes presence", function()
		local f = boot({ main = true }); f:advance(20); assert(f.picks == 0 and f.joins == 0 and f.menus == 0)
	end)
	test("bad pairing does not spam authentication or game requests", function()
		local f = boot({ badAuth = true }); f:advance(20); assert(f.authRequests == 1 and f.joins == 0 and f.picks == 0)
	end)
	test("failed persistence prevents automatic slot choice", function()
		local f = boot({ storageFail = true }); f:advance(5); assert(f.picks == 0 and f.joins == 0)
	end)
	test("unrelated menu prompt is untouched", function()
		local f = boot({ world = true, menu = true }); f:advance(3); assert(f.menus == 1 and f.confirms == 0)
		f.prompt.Title = "Return to Main Menu"; f:advance(3); assert(f.confirms == 1)
	end)
	test("stopping disconnects owned callbacks and the socket", function()
		local f = boot(); f.api:destroy(); f:advance(10)
		assert(f.sockets[1].closed and f.picks == 0 and f.env.CLAW_CONTROL == nil)
	end)
	test("wrong selected region never reaches PickServer", function()
		local f = boot({ wrongRegion = true }); f:advance(15)
		assert(f.picks == 1 and f.joins == 0 and f.api:report().status:find("ATTENTION"))
	end)
	test("owner-scoped client authenticates, joins and persists only in its namespace", function()
		local owner = "123456789012345678"
		local f = boot({ owner = owner }); f:advance(3)
		assert(f.picks == 1 and f.joins == 1)
		for path, raw in pairs(f.files) do
			if not path:find("CLAW_PAIRINGS/", 1, true) then
				assert(path == "CLAW_CONTROL_BETA/" .. owner .. "-22.json")
				local state = f.http:JSONDecode(raw); assert(state.ownerId == owner and state.key == nil)
			end
		end
	end)
	test("another owner's profile closes the connection without game actions", function()
		local f = boot({ owner = "123456789012345678", wrongOwner = true }); f:advance(3)
		assert(f.picks == 0 and f.joins == 0 and f.sockets[1].closed)
	end)
	test("menu sync sends compact cards without creating scan report files", function()
		local f = boot({ main = true }); f:advance(21)
		local packets = {}; for _, p in ipairs(f.packets) do if p.type == "catalog" then packets[#packets + 1] = p end end
		assert(#packets == 1) -- Unchanged scans are not repeatedly uploaded.
		assert(packets[1].cards[1].characterName == "Test Character" and packets[1].cards[1].labels == nil)
		for path in pairs(f.files) do assert(not path:find("menu-", 1, true)) end
	end)
	test("missing current menu cannot select from a stale cloud roster", function()
		local f = boot({ noMenu = true }); f:advance(20)
		assert(f.picks == 0 and f.joins == 0 and f.api:report().status:find("WAITING_SLOT_SCAN", 1, true))
	end)
	test("a different character reusing an approved letter waits for permission sync", function()
		local f = boot({ oldCharacter = true }); f:advance(20)
		assert(f.picks == 0 and f.joins == 0 and f.api:report().status:find("WAITING_SLOT_SYNC", 1, true))
	end)
	test("cloud menu opt-in works without local configuration edits", function()
		local f = boot({ world = true, cloudMenu = true }); f:advance(3)
		assert(f.menus == 1 and f.confirms == 0)
	end)
	test("cloud OFF overrides old local opt-in and suppresses a pending confirmation", function()
		local f = boot({ world = true, menu = true, cloudMenu = false }); f:advance(3); assert(f.menus == 0)
		f.cloudMenu = true; f.sockets[1]:Send(f.http:JSONEncode({ type = "hello" })); f:advance(1); assert(f.menus == 1)
		f.cloudMenu = false; f.sockets[1]:Send(f.http:JSONEncode({ type = "hello" })); f.prompt.Title = "Return to Main Menu"
		f:advance(3); assert(f.confirms == 0)
	end)
	if pairedLauncher then
		test("bundled first-run entry pairs then connects without module downloads", function()
			local f = boot({ firstPair = true }); f:advance(2)
			assert(f.authRequests == 2 and f.env.CLAW_PAIR == nil and f.picks == 1 and f.joins == 1)
			assert(f.files["CLAW_PAIRINGS/22.json"])
		end)
	end
	print(tostring(passed) .. " control-client smoke tests passed")
end

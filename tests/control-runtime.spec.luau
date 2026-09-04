return function(clientSource, autoSource, coreSource, regionSource, menuSource, catalogSource, movementSource, pairedLauncher)
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
		function o:GetDescendants()
			local result = {}
			local function visit(parent)
				for _, child in ipairs(parent:GetChildren()) do result[#result + 1] = child; visit(child) end
			end
			visit(self); return result
		end
		function o:FindFirstChild(name) return self.children[name] end
		function o:FindFirstChildOfClass(name)
			for _, child in pairs(self.children) do if child.ClassName == name then return child end end
		end
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
			if options.stateEncodeFail and value.version == 1 and value.revision then
				if options.stateEncodeFail == "invalid" then return {} end
				if options.stateEncodeFail == "oversized" then return string.rep("x", 32769) end
				error("private state " .. string.rep("c", 64))
			end
			f.encoded += 1; local key = "json-" .. f.encoded; f.values[key] = clone(value); return key
		end
		function http:JSONDecode(key) return clone(assert(f.values[key], "invalid JSON")) end
		function http:GenerateGUID() return "nonce-1" end
		f.http = http
		local player = object("Player"); player.UserId = options.main and 11 or 22; player.OnTeleport = signal()
		player.DataSlot = options.slot
		f.player = player
		if options.items then
			player.Character = object("Model")
			local humanoid = object("Humanoid"); humanoid.Health = 100; player.Character.children.Humanoid = humanoid
			player.children.Backpack = object("Backpack")
		end
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
				if name == "SlotScroll" then f.slotList = next end
			end
			for name, value in pairs({ CharacterName = "Test Character", Race = "Khan", Level = "Lv. 1", Realm = "Etrean Luminant", Slot = "L" }) do
				local label = object("TextLabel"); label.Text = value; parent.children[name] = label
			end
			if options.editMenu then options.editMenu(f.slotList, parent) end
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
			if url:find("control/movement.lua", 1, true) then return movementSource end
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
					retry = options.retry,
					allowMenuReturn = f.cloudMenu,
					approvedSlots = options.approvedSlots or { ["L"] = true }, catalog = { { slot = "L", region = "EtreanLuminant", observedAt = f.now, confirmed = true,
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
			if options.movement and name == "@CLAW/control/movement.lua" then
				return function() return { new = function()
					local mover = {}
					function mover:stop() f.moveStops = (f.moveStops or 0) + 1 end
					function mover:destroy() self:stop() end
					function mover:bring()
						f.moves = (f.moves or 0) + 1
						for _, raw in pairs(f.files) do
							local value = http:JSONDecode(raw)
							if value.actions then f.receiptsAtMove = value.actions end
						end
						return true, "movement started"
					end
					mover.park = mover.bring
					return mover
				end } end
			end
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
		function f:action(id, action, args)
			self.sockets[#self.sockets].OnMessage:Fire(http:JSONEncode({ type = "action", version = 1,
				id = id, action = action, args = args or {}, createdAt = self.now, expiresAt = self.now + 60 }))
		end
		function f:profile(extra)
			local profile = { type = "profile", accountId = tostring(player.UserId), ownerId = options.owner,
				mainId = "11", role = "alt", enabled = true, follow = false, approvedSlots = {} }
			for key, value in pairs(extra or {}) do profile[key] = value end
			self.sockets[#self.sockets].OnMessage:Fire(http:JSONEncode(profile))
		end
		f:reload(); return f
	end
	local passed = 0
	local function test(name, fn) fn(); passed += 1; print("PASS runtime " .. name) end
	local function damageAutoSnapshot(f, phase)
		f.api:destroy() -- Simulate a new process; no old client may rewrite the fixture before startup.
		for _, value in pairs(f.values) do
			if type(value) == "table" and value.version == 1 and value.core and value.core.operation then
				if phase then value.auto.attempt.phase = phase else value.auto = nil end
			end
		end
	end
	test("reload observes an existing join even when auto state is absent or stale", function()
		for _, phase in ipairs({ "missing", "HOLD", "WAIT_SLOT" }) do
			local f = boot(); f:advance(3); assert(f.picks == 1 and f.joins == 1)
			damageAutoSnapshot(f, phase ~= "missing" and phase or nil)
			f:reload(); f:advance(2)
			assert(f.picks == 1 and f.joins == 1, "Reload repeated character selection for a pending join")
			assert(f.api:report().attempt.phase == "JOINING" and f.api:report().status == "REQUESTED")
		end
	end)
	test("restored pending join verifies arrival without its old auto snapshot", function()
		local f = boot(); f:advance(3); damageAutoSnapshot(f)
		f.game.PlaceId = 6032399813; f.game.JobId = "main-job"; f.player.DataSlot = "L"; f.hasMain = true
		f:reload(); f:advance(2)
		assert(f.picks == 1 and f.joins == 1 and f.api:report().status == "VERIFIED")
	end)
	test("recovered join timeout holds until a new explicit retry", function()
		local options = { retry = "original-retry" }
		local f = boot(options); f:advance(3); damageAutoSnapshot(f); f:reload(); f:advance(140)
		assert(f.picks == 1 and f.joins == 1 and f.api:report().status:find("ATTENTION", 1, true))
		assert(f.api:report().join.state == "TIMED_OUT")
		options.retry = "next-retry"; f.sockets[#f.sockets]:Send(f.http:JSONEncode({ type = "hello" })); f:advance(3)
		assert(f.picks == 2 and f.joins == 2, "Explicit retry should still work after recovery")
	end)
	test("failed recovery persistence cannot start new menu or slot actions", function()
		local options = {}
		local f = boot(options); f:advance(3); damageAutoSnapshot(f); options.storageFail = true
		f:reload(); f:advance(20)
		assert(f.picks == 1 and f.joins == 1 and f.menus == 0)
		assert(f.api:report().status:find("storage unavailable", 1, true))
	end)
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
	test("invalid state encoding stops actions without exposing adapter errors", function()
		for _, failure in ipairs({ "throw", "invalid", "oversized" }) do
			local options = { stateEncodeFail = failure }
			local f = boot(options)
			local ok = pcall(function() f:advance(5) end)
			assert(ok, "State encoder failure escaped the client lifecycle")
			assert(f.picks == 0 and f.joins == 0 and f.menus == 0)
			assert(f.api:supportReport():find("storage=unavailable", 1, true))
			for _, line in ipairs(f.logs) do assert(not line:find(string.rep("c", 64), 1, true)) end
			assert(next(f.memory) == nil, "Invalid serialized state was saved")
			for path in pairs(f.files) do assert(not path:find("CLAW_CONTROL_BETA/", 1, true)) end
		end
	end)
	test("repaired state encoding waits for an explicit retry", function()
		for _, options in ipairs({ { stateEncodeFail = "throw" }, { storageFail = true } }) do
			local f = boot(options); f:advance(3)
			options.stateEncodeFail = nil; options.storageFail = nil; f:advance(15)
			assert(f.picks == 0 and f.joins == 0, "Repairing storage is not permission to retry")
			options.retry = "retry-after-storage-repair"
			f.sockets[#f.sockets]:Send(f.http:JSONEncode({ type = "hello" })); f:advance(3)
			assert(f.picks == 1 and f.joins == 1, "One retry must recover the stopped selection")
			assert(f.api:supportReport():find("storage=ready", 1, true))
		end
	end)
	test("storage recovery retry cannot replace an already pending join", function()
		local options = {}
		local f = boot(options); f:advance(3)
		options.stateEncodeFail = "throw"; f.sockets[#f.sockets]:Close()
		assert(f.api:supportReport():find("storage=unavailable", 1, true))
		options.stateEncodeFail = nil; f:advance(10)
		options.retry = "retry-while-join-pending"
		f.sockets[#f.sockets]:Send(f.http:JSONEncode({ type = "hello" })); f:advance(3)
		assert(f.picks == 1 and f.joins == 1 and f.api:report().attempt.phase == "JOINING")
	end)
	test("failed state encoding cannot interrupt client shutdown", function()
		local options = {}
		local f = boot(options); f:advance(3)
		options.stateEncodeFail = "throw"
		local ok = pcall(function() f.api:destroy() end)
		assert(ok, "Shutdown exposed a private state encoder error")
		assert(f.env.CLAW_CONTROL == nil and f.sockets[#f.sockets].closed)
		f:advance(20); assert(f.picks == 1 and f.joins == 1)
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

	local function addUnusedSlots(list)
		for _, slot in ipairs({ "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }) do
			local blank, label = object("Frame"), object("TextLabel")
			label.Text = slot; blank.children.Slot = label; list.children[slot] = blank
		end
	end
	test("one approved character still joins alongside ten unused slots", function()
		local f = boot({ editMenu = addUnusedSlots }); f:advance(20)
		assert(f.picks == 1 and f.joins == 1, "Unused slots blocked the finished character")
		assert(f.api:report().menu.cards == 11 and not f.api:report().menu.complete)
	end)
	test("unused slots never weaken selected-character or cloud identity checks", function()
		for _, field in ipairs({ "CharacterName", "Race", "Level", "Realm", "Slot" }) do
			local f = boot({ editMenu = function(list, selected)
				addUnusedSlots(list); selected.children[field] = nil
			end }); f:advance(20)
			assert(f.picks == 0 and f.joins == 0, "Selected a character missing " .. field)
		end
		local f = boot({ oldCharacter = true, editMenu = addUnusedSlots }); f:advance(20)
		assert(f.picks == 0 and f.joins == 0 and f.api:report().status:find("WAITING_SLOT_SYNC", 1, true))
		local unapproved = boot({ approvedSlots = {}, editMenu = addUnusedSlots }); unapproved:advance(20)
		assert(unapproved.picks == 0 and unapproved.joins == 0)
		local mismatch = boot({ wrongRegion = true, editMenu = addUnusedSlots }); mismatch:advance(20)
		assert(mismatch.picks == 1 and mismatch.joins == 0)
	end)
	test("an account with only unused slots never selects or joins", function()
		local f = boot({ editMenu = function(list) list.children = {}; addUnusedSlots(list) end }); f:advance(20)
		assert(f.picks == 0 and f.joins == 0 and f.menus == 0)
	end)
	test("truncated and duplicate roster scans still block selection", function()
		for _, duplicate in ipairs({ false, true }) do
			local f = boot({ editMenu = function(list, selected)
				if duplicate then
					selected.Name = "L"
					function list:GetChildren() return { selected, selected } end
				else
					for i = 1, 170 do selected.children["Decoration" .. i] = object("Frame") end
				end
			end }); f:advance(20)
			assert(f.picks == 0 and f.joins == 0 and f.api:report().status:find("WAITING_SLOT_SCAN", 1, true))
		end
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
	test("authenticated cloud actions are bounded and return results", function()
		local f = boot({ main = true, items = true }); f:advance(3)
		local socket = f.sockets[#f.sockets]
		socket.OnMessage:Fire(f.http:JSONEncode({ type = "action", version = 1, id = "action-stop", action = "stop",
			args = {}, createdAt = f.now, expiresAt = f.now + 60 }))
		local stopped
		for _, packet in ipairs(f.packets) do
			if packet.type == "action-result" and packet.id == "action-stop" then stopped = packet end
		end
		assert(stopped and stopped.ok == true and stopped.accountId == tostring(f.player.UserId))
		socket.OnMessage:Fire(f.http:JSONEncode({ type = "action", version = 1, id = "action-scan", action = "scan-items",
			args = {}, createdAt = f.now, expiresAt = f.now + 60 }))
		local inventory, scanned
		for _, packet in ipairs(f.packets) do
			if packet.type == "inventory" then inventory = packet end
			if packet.type == "action-result" and packet.id == "action-scan" then scanned = packet end
		end
		assert(inventory and #inventory.inventory == 0 and #inventory.bank == 0 and scanned and scanned.ok)
		assert(f.picks == 0 and f.joins == 0 and f.menus == 0)
	end)
	test("inactive teams cannot start movement and disconnect stops active movement", function()
		local f = boot({ movement = true }); f:advance(3)
		f:profile({ enabled = false })
		f:action("inactive-bring", "bring", { mainId = "11" })
		assert((f.moves or 0) == 0, "standby account moved")
		f:profile()
		f:action("active-bring", "bring", { mainId = "11" }); assert(f.moves == 1)
		local stops = f.moveStops or 0
		f.sockets[#f.sockets]:Close()
		assert(f.moveStops > stops, "movement outlived its connection")
	end)
	test("changing the main stops movement and failed storage cannot start it", function()
		local options = { movement = true }
		local f = boot(options); f:advance(3); f:profile()
		f:action("first-bring", "bring", { mainId = "11" }); assert(f.moves == 1)
		assert(f.receiptsAtMove["first-bring"].ok == false, "no receipt existed before starting movement")
		f:reload(); f:advance(3); f:profile()
		f:action("first-bring", "bring", { mainId = "11" }); assert(f.moves == 1, "duplicate command ran after reload")
		local stops = f.moveStops or 0
		f:profile({ mainId = "33" })
		assert(f.moveStops > stops, "old main still controlled movement")
		options.storageFail = true
		f:action("unsaved-bring", "bring", { mainId = "33" })
		assert(f.moves == 1, "movement started without a saved receipt")
		f:action("stop-without-storage", "stop")
		assert(f.moveStops > stops + 1, "storage failure blocked Stop")
	end)
	test("missing backpacks and new characters do not create fake item gains", function()
		local f = boot({ main = true, world = true, items = true }); f:advance(3)
		local backpack = f.player.children.Backpack
		local tool = object("Tool"); tool.Name = "Sword"; backpack.children.Sword = tool
		f:action("scan-one", "scan-items")
		local before = #f.packets
		f.player.children.Backpack = nil; f:action("scan-missing", "scan-items")
		f.player.children.Backpack = backpack; f:action("scan-returned", "scan-items")
		for i = before + 1, #f.packets do assert(f.packets[i].type ~= "loot", "reappearing inventory became loot") end
		f.player.Character = object("Model")
		local humanoid = object("Humanoid"); humanoid.Health = 100; f.player.Character.children.Humanoid = humanoid
		local extra = object("Tool"); backpack.children.Axe = extra
		before = #f.packets; f:action("scan-respawn", "scan-items")
		for i = before + 1, #f.packets do assert(f.packets[i].type ~= "loot", "respawn inventory became loot") end
	end)
	test("large item gains stay within the server packet limits", function()
		local f = boot({ main = true, world = true, items = true }); f:advance(3)
		for i = 1, 25 do f.player.children.Backpack.children["Item" .. i] = object("Tool") end
		f:action("scan-many", "scan-items"); f:advance(12)
		local count = 0
		for _, packet in ipairs(f.packets) do if packet.type == "loot" then
			assert(#packet.items <= 20, "client sent more items than its server accepts")
			for _, item in ipairs(packet.items) do assert(item.count <= 100); count += item.count end
		end end
		assert(count == 25, "gains were lost")
	end)
	test("hidden bank windows are not reported as current bank scans", function()
		local f = boot({ main = true, items = true }); f:advance(3)
		local gui = f.player.children.PlayerGui
		local bank = object("Frame"); bank.Name = "BankWindow"; bank.Parent = gui; gui.children.BankWindow = bank
		local row = object("Frame"); row.ItemName = "Crown"; row.Amount = 2; row.Parent = bank; bank.children.Row = row
		f:action("bank-open", "scan-items")
		local function latest()
			for i = #f.packets, 1, -1 do if f.packets[i].type == "inventory" then return f.packets[i] end end
		end
		assert(latest().bankObserved and latest().bank[1].count == 2)
		bank.Visible = false; f:action("bank-closed", "scan-items")
		assert(latest().bankObserved == false and #latest().bank == 0)
	end)
	test("unknown cloud actions close without touching the game", function()
		local f = boot({ main = true }); f:advance(3)
		local socket = f.sockets[#f.sockets]
		socket.OnMessage:Fire(f.http:JSONEncode({ type = "action", version = 1, id = "action-unknown", action = "execute-code",
			args = {}, createdAt = f.now, expiresAt = f.now + 60 }))
		assert(socket.closed and f.picks == 0 and f.joins == 0 and f.menus == 0,
			("closed=%s picks=%s joins=%s menus=%s"):format(tostring(socket.closed), tostring(f.picks), tostring(f.joins), tostring(f.menus)))
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

return function(clientSource, autoSource, coreSource)
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
		function o:IsA(name) return self.ClassName == name end
		function o:FindFirstChild(name) return self.children[name] end
		function o:GetAttribute(name) return self[name] end
		return o
	end
	local function boot(options)
		options = options or {}
		local f = { now = 2000000000, clock = 0, files = {}, memory = {}, values = {}, encoded = 0,
			picks = 0, joins = 0, menus = 0, confirms = 0, sockets = {}, hasMain = false, authRequests = 0 }
		f.env = { CLAW_CONTROL_CONFIG = { Endpoint = "https://claw-test.example", Key = string.rep("a", 64),
			AllowMenuReturn = options.menu == true } }
		local http = {}
		function http:JSONEncode(value) f.encoded += 1; local key = "json-" .. f.encoded; f.values[key] = clone(value); return key end
		function http:JSONDecode(key) return clone(assert(f.values[key], "invalid JSON")) end
		function http:GenerateGUID() return "nonce-1" end
		f.http = http
		local player = object("Player"); player.UserId = options.main and 11 or 22; player.OnTeleport = signal()
		player.DataSlot = options.slot
		f.player = player
		local gui = object("PlayerGui"); player.children.PlayerGui = gui
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
		function pick:FireServer(slot) assert(slot == "chosen-slot"); f.picks += 1; show.OnClientEvent:Fire("Etrean") end
		function join:FireServer(id) assert(id == "main-job"); f.joins += 1 end
		function ret:FireServer() f.menus += 1 end
		local teleport = { TeleportInitFailed = signal() }
		function teleport:GetTeleportSetting(key) return f.memory[key] end
		function teleport:SetTeleportSetting(key, raw) assert(not options.storageFail); f.memory[key] = raw end
		local run = { Heartbeat = signal() }; f.heartbeat = run.Heartbeat
		local services = { HttpService = http, Players = players, ReplicatedStorage = rep, TeleportService = teleport, RunService = run }
		f.game = { GameId = 99, PlaceId = options.world and 456 or 4111023553, JobId = "origin-job" }
		function f.game:GetService(name) return assert(services[name], name) end
		function f.game:HttpGet(url) return url:find("join/core.lua", 1, true) and coreSource or autoSource end
		local function target()
			return { type = "target", enabled = true, key = "99.123.main-job", expiresAt = f.now + 35,
				ticket = { version = 1, controllerId = 11, gameId = 99, placeId = 123, jobId = "main-job", joinId = "main-job",
					createdAt = f.now, nonce = "revision-1" } }
		end
		local wsLibrary = {}
		function wsLibrary.connect(url)
			assert(url:match("^wss://claw%-test%.example/socket%?ticket="))
			local ws = { OnMessage = signal(), OnClose = signal(), closed = false }
			function ws:Close() self.closed = true; self.OnClose:Fire() end
			function ws:Send(raw)
				assert(not self.closed)
				local value = http:JSONDecode(raw)
				if value.type == "hello" then self.OnMessage:Fire(http:JSONEncode({ type = "profile", accountId = tostring(player.UserId),
					mainId = "11", role = options.main and "main" or "alt", slot = "chosen-slot", follow = true })) end
				self.OnMessage:Fire(http:JSONEncode(target()))
			end
			f.sockets[#f.sockets + 1] = ws
			return ws
		end
		local runtime = setmetatable({ game = f.game, getgenv = function() return f.env end,
			os = { time = function() return f.now end, clock = function() return f.clock end },
			task = { spawn = function(fn) fn() end }, WebSocket = wsLibrary,
			Enum = { TeleportState = { Started = 1, InProgress = 2 } },
			request = function(request)
				assert(request.Url == "https://claw-test.example/session")
				local data = http:JSONDecode(request.Body); assert(data.accountId == tostring(player.UserId)); assert(#data.key == 64)
				f.authRequests += 1
				return { StatusCode = options.badAuth and 401 or 200,
					Body = http:JSONEncode({ ticket = data.accountId .. ".12345678-1234-1234-1234-123456789012" }) }
			end,
			isfolder = function() return true end, makefolder = function() end,
			writefile = function(path, raw) assert(not options.storageFail); f.files[path] = raw end,
			readfile = function(path) return assert(f.files[path]) end,
			warn = function() end,
		}, { __index = getfenv() })
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
	test("autoexec selects saved slot and joins without clipboard or GUI", function()
		local f = boot(); f:advance(2); assert(f.picks == 1 and f.joins == 1)
		f:advance(10); assert(f.joins == 1)
	end)
	test("post-teleport reload verifies and never resends", function()
		local f = boot(); f:advance(2); f.game.PlaceId = 123; f.game.JobId = "main-job"; f.player.DataSlot = "chosen-slot"; f.hasMain = true
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
	print(tostring(passed) .. " control-client smoke tests passed")
end

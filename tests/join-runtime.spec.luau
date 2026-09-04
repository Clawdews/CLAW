-- Lightweight Roblox adapter mocks. These test wiring, not network/game behavior.
return function(source, coreSource)
	local function clone(value)
		if type(value) ~= "table" then return value end
		local copy = {}; for key, item in pairs(value) do copy[key] = clone(item) end
		return copy
	end
	local function signal()
		local listeners = {}
		local s = {}
		function s:Connect(callback)
			local c = { Connected = true }
			function c:Disconnect() self.Connected = false end
			listeners[#listeners + 1] = { c, callback }
			return c
		end
		function s:Fire(...)
			for _, listener in ipairs(listeners) do if listener[1].Connected then listener[2](...) end end
		end
		return s
	end
	local function boot(options)
		options = options or {}
		local f = { objects = {}, now = 2000000000, sends = {}, files = {}, memory = {},
			values = {}, encoded = 0, env = {}, mainPresent = false }
		local function instance(class)
			local obj = { ClassName = class, children = {}, Activated = signal(), OnClientEvent = signal() }
			function obj:IsA(name) return self.ClassName == name end
			function obj:FindFirstChild(name) return self.children[name] end
			function obj:WaitForChild(name) return assert(self.children[name], name .. " not mocked") end
			function obj:Destroy() self.destroyed = true end
			f.objects[#f.objects + 1] = obj
			return obj
		end
		local player = instance("Player")
		player.UserId = options.main and 11 or 22
		player.OnTeleport = signal()
		player.children.PlayerGui = instance("PlayerGui")
		function player:GetAttribute() return "alt-slot" end
		f.player = player
		local players = { LocalPlayer = player }
		function players:GetPlayerByUserId(id) return id == 11 and f.mainPresent and {} or nil end
		local replicated = instance("ReplicatedStorage")
		local requests = instance("Folder"); replicated.children.Requests = requests
		local menu = instance("Folder"); requests.children.StartMenu = menu
		f.showServers = instance("RemoteEvent"); requests.children.ShowServers = f.showServers
		local pickServer = instance("RemoteEvent"); menu.children.PickServer = pickServer
		function pickServer:FireServer(id) f.sends[#f.sends + 1] = id end
		local http = {}
		function http:GenerateGUID() return "nonce-1" end
		function http:JSONEncode(value)
			f.encoded += 1
			local raw = "json-" .. tostring(f.encoded)
			f.values[raw] = clone(value)
			return raw
		end
		function http:JSONDecode(raw) return clone(assert(f.values[raw], "not JSON")) end
		f.http = http
		local teleport = { TeleportInitFailed = signal() }
		function teleport:GetTeleportSetting(key) return f.memory[key] end
		function teleport:SetTeleportSetting(key, raw)
			assert(not options.storageFail and not options.teleportStorageFail, "unavailable")
			f.memory[key] = raw
		end
		local run = { Heartbeat = signal() }; f.heartbeat = run.Heartbeat
		local services = { HttpService = http, Players = players, TeleportService = teleport,
			ReplicatedStorage = replicated, RunService = run }
		local game = { GameId = 99, PlaceId = options.main and 123 or 4111023553,
			JobId = options.main and "main-job" or "lobby-job" }
		function game:GetService(name) return assert(services[name], name) end
		function game:HttpGet() return coreSource end
		f.game = game
		local runtime = setmetatable({ game = game, workspace = { CurrentCamera = { ViewportSize = { X = 1920, Y = 1080 } } },
			Instance = { new = instance }, getgenv = function() return f.env end,
			os = { time = function() return f.now end },
			Color3 = { fromRGB = function(r, g, b) return { r, g, b } end },
			Vector2 = { new = function(x, y) return { X = x, Y = y } end },
			UDim = { new = function(...) return { ... } end },
			UDim2 = { new = function(...) return { ... } end, fromOffset = function(...) return { ... } end },
			Enum = { ZIndexBehavior = { Sibling = 1 }, Font = { Gotham = 1, Code = 2 },
				TextXAlignment = { Left = 1 }, TextYAlignment = { Top = 1, Center = 2 },
				TeleportState = { Started = 1, InProgress = 2 } },
			setclipboard = function(raw) f.clipboard = raw end,
			isfolder = function() return true end, makefolder = function() end,
			writefile = function(path, raw)
				assert(not options.storageFail and not options.fileStorageFail, "unavailable"); f.files[path] = raw
			end,
			readfile = function(path) return assert(f.files[path], "missing") end,
		}, { __index = getfenv() })
		function f:reload()
			local chunk = assert(loadstring(source, "join-test"))
			setfenv(chunk, runtime)
			self.api = chunk()
		end
		function f:object(class, text)
			for i = #self.objects, 1, -1 do
				local obj = self.objects[i]
				if obj.ClassName == class and (not text or obj.Text == text) then return obj end
			end
			error("object not found: " .. class .. " " .. tostring(text))
		end
		function f:click(text) self:object("TextButton", text).Activated:Fire() end
		function f:ticketBox()
			for i = #self.objects, 1, -1 do
				if self.objects[i].ClassName == "TextBox" and self.objects[i].MultiLine then return self.objects[i] end
			end
			error("ticket box missing")
		end
		function f:join()
			self:ticketBox().Text = self.http:JSONEncode({ version = 1, controllerId = 11, gameId = 99,
				placeId = 123, jobId = "main-job", joinId = "join-candidate", nonce = "nonce-1", createdAt = self.now })
			self.showServers.OnClientEvent:Fire("Etrean")
			self:click("JOIN EXACT SERVER")
		end
		function f:report() return self.http:JSONDecode(self.api:report()) end
		f:reload()
		return f
	end
	local passed = 0
	local function test(name, callback)
		callback(); passed += 1; print("PASS runtime: " .. name)
	end
	test("UI loads without a teleport or equipment/movement calls", function()
		local f = boot(); assert(#f.sends == 0); assert(f:report().state == "IDLE")
		f:click("-"); f:click("+"); f:click("COPY REPORT")
		assert(f.clipboard and f:ticketBox().Text == f.clipboard)
	end)
	test("main copy button captures actual destination", function()
		local f = boot({ main = true }); f:click("COPY MAIN TARGET")
		local ticket = f.http:JSONDecode(f.clipboard)
		assert(ticket.controllerId == 11 and ticket.jobId == "main-job" and #f.sends == 0)
	end)
	test("slot signal and join button send the exact candidate once", function()
		local f = boot(); f:join(); f:click("JOIN EXACT SERVER")
		assert(#f.sends == 1 and f.sends[1] == "join-candidate")
		assert(f:report().state == "REQUESTED")
	end)
	test("arrival reload restores storage and verifies, never resends", function()
		local f = boot(); f:join(); f.game.PlaceId = 123; f.game.JobId = "main-job"; f.mainPresent = true
		local oldGui = f:object("ScreenGui"); f:reload()
		assert(oldGui.destroyed); assert(f:report().state == "VERIFIED"); assert(#f.sends == 1)
		f.mainPresent = false; f.heartbeat:Fire(1); assert(f:report().state == "STALE")
	end)
	test("both storage methods failing prevents teleport", function()
		local f = boot({ storageFail = true }); f:join()
		assert(#f.sends == 0 and f:report().state == "FAILED")
	end)
	test("file mirror alone can restore arrival verification", function()
		local f = boot({ teleportStorageFail = true }); f:join()
		assert(f:report().storage.file and not f:report().storage.teleport)
		f.game.PlaceId = 123; f.game.JobId = "main-job"; f.mainPresent = true; f:reload()
		assert(f:report().state == "VERIFIED" and #f.sends == 1)
	end)
	test("teleport storage alone can restore arrival verification", function()
		local f = boot({ fileStorageFail = true }); f:join()
		assert(f:report().storage.teleport and not f:report().storage.file)
		f.game.PlaceId = 123; f.game.JobId = "main-job"; f.mainPresent = true; f:reload()
		assert(f:report().state == "VERIFIED" and #f.sends == 1)
	end)
	test("invalid textbox contents cannot execute", function()
		local f = boot(); f:ticketBox().Text = "error('must not run')"; f:click("JOIN EXACT SERVER")
		assert(#f.sends == 0 and f:report().state == "IDLE")
	end)
	test("close cancels tracking and disconnects callbacks", function()
		local f = boot(); f:join(); local api = f.api; f:click("X")
		assert(f.env.CLAW_JOIN_TEST == nil); assert(f:object("ScreenGui").destroyed)
		f.game.PlaceId = 123; f.game.JobId = "main-job"; f.mainPresent = true
		f.heartbeat:Fire(1); assert(f.http:JSONDecode(api:report()).state == "CANCELLED")
	end)
	print(tostring(passed) .. " runtime smoke tests passed")
end

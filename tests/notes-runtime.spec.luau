return function(source, newLoop, validRun, buttonSource)
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS notes runtime " .. name) end
    local function signal()
        local s = { handlers = {} }
        function s:Connect(fn)
            local c = { fn = fn, connected = true }; function c:Disconnect() self.connected = false end
            table.insert(self.handlers, c); return c
        end
        function s:Fire(...) for _, c in ipairs(self.handlers) do if c.connected then c.fn(...) end end end
        return s
    end
    local function node(name, class, parent)
        local n = { Name = name, ClassName = class, Parent = parent, children = {}, Text = "", hidden = false }
        if parent then table.insert(parent.children, n) end
        function n:IsA(c) return self.ClassName == c end
        function n:FindFirstChild(k) for _, c in ipairs(self.children) do if c.Name == k then return c end end end
        function n:GetAttribute(k) return self[k] end
        function n:GetDescendants()
            local out = {}; for _, c in ipairs(self.children) do table.insert(out, c); for _, d in ipairs(c:GetDescendants()) do table.insert(out, d) end end
            return out
        end
        return n
    end
    local function child(root, ...) for _, k in ipairs({...}) do root = root and root:FindFirstChild(k) end; return root end
    local function fixture()
        local f = { time = 1000, queued = {}, settings = {}, json = {}, calls = {}, delayed = {}, serial = 0 }
        f.env = { CLAW_NOTES_EXECUTION_KEY = string.rep("A", 32) }
        f.player = node("Player", "Player"); f.player.UserId = 12; f.player.DataSlot = "A"; f.player.Character = {}; f.player.OnTeleport = signal()
        f.gui = node("PlayerGui", "PlayerGui")
        f.notes = node("Notes", "TextButton", node("CurrencyFrame", "Frame", node("CurrencyGui", "ScreenGui", f.gui)))
        f.count = node("Amount", "TextLabel", f.notes); f.count.Text = "4,335"
        f.requests = node("Requests", "Folder", node("ReplicatedStorage", "Folder")); f.menu = node("StartMenu", "Folder", f.requests)
        local function remote(name, parent, fn)
            local r = node(name, "RemoteEvent", parent); r.OnClientEvent = signal()
            function r:FireServer(...) table.insert(f.calls, { name, ... }); if fn then fn(...) end end
            return r
        end
        remote("ReturnToMenu", f.requests, function() f.player.OnTeleport:Fire("Started") end)
        f.show = remote("ShowServers", f.requests)
        remote("PickSlot", f.menu, function() f.show.OnClientEvent:Fire("Etrean") end)
        remote("PickServer", f.menu, function() f.player.OnTeleport:Fire("Started") end)
        f.teleport = { TeleportInitFailed = signal(),
            SetTeleportSetting = function(_, k, v) if f.storageFailure then error("storage failed") end; f.settings[k] = v end,
            GetTeleportSetting = function(_, k) return f.settings[k] end }
        f.http = {
            GenerateGUID = function() f.serial += 1; return "unique-token-123456789-" .. f.serial end,
            JSONEncode = function(_, r) local id = "json-" .. r.token; f.json[id] = table.clone(r); return id end,
            JSONDecode = function(_, id) assert(f.json[id]); return table.clone(f.json[id]) end }
        f.game = { GameId = 34, PlaceId = 6473861193, JobId = "exact-server" }
        function f.game:GetService(name)
            return ({ HttpService = f.http, TeleportService = f.teleport, ReplicatedStorage = f.requests.Parent, Players = { LocalPlayer = f.player } })[name]
        end
        f.ui = { setAuto = function(_, active, message) f.active, f.message = active, message end,
            setNotice = function(_, code) assert(type(code) == "string"); f.notice = code end }
        f.core = { cancel = function() f.cancelled = true end, run = function(self, raw)
            assert(raw == "MAX"); self.lastAmount = 1000; f.count.Text = "3,335"; return true, "sent"
        end }
        f.scope = setmetatable({ game = f.game, newNotesLoop = newLoop, validNotesRun = validRun,
            os = { time = function() return f.time end, clock = function() return f.time end },
            task = { wait = function(s) f.time += s; if f.waitHook then f.waitHook() end end,
                delay = function(_, fn) table.insert(f.delayed, fn) end },
            queue_on_teleport = function(code) table.insert(f.queued, code) end,
            getgenv = function() return f.env end,
            Enum = { TeleportState = { Started = "Started", InProgress = "InProgress" } }, warn = function() f.warning = true end,
        }, { __index = getfenv() })
        local factory = assert(loadstring(source .. "\nreturn newNotesRuntime")); setfenv(factory, f.scope)
        f.runtime = factory()(f.env, f.core, f.ui, f.player, f.gui, child, function(n) return not n.hidden end)
        function f:bootstrap()
            local scope = setmetatable({ loadstring = function() return function() f.loaded = (f.loaded or 0) + 1 end end }, { __index = f.scope })
            function f.game:HttpGet(url) assert(url == "https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"); return "payload" end
            local fn = assert(loadstring(f.queued[#f.queued])); setfenv(fn, scope); fn()
        end
        return f
    end
    test("read only an unambiguous numeric Notes display", function()
        local f = fixture(); assert(f.runtime.balance() == 4335)
        f.count.Text = "553"; assert(f.runtime.balance() == 553)
        f.count.Text = "1,,234"; assert(f.runtime.balance() == nil)
        f.count.Text = "1,234,567"; assert(f.runtime.balance() == 1234567)
        local extra = node("Other", "TextLabel", f.notes); extra.Text = "2"; assert(f.runtime.balance() == nil)
    end)
    test("manual construction is idle; Start uses one normal menu request", function()
        local f = fixture(); assert(#f.calls == 0 and #f.queued == 0)
        f.runtime:start(); assert(#f.calls == 1 and f.calls[1][1] == "ReturnToMenu" and #f.queued == 1)
    end)
    test("queued bootstrap consumes its token once and restores only the same account", function()
        local f = fixture(); f.runtime:start(); f.game.PlaceId = 4111023553; f:bootstrap(); f:bootstrap()
        assert(f.loaded == 1 and f.env.CLAW_NOTES_RESUME.phase == "menu")
    end)
    test("Stop invalidates a queued bootstrap without clearing other scripts", function()
        local f = fixture(); f.runtime:start(); f.runtime:stop(); f.game.PlaceId = 4111023553; f:bootstrap()
        assert(not f.loaded and not f.active)
    end)
    test("wrong account, game, place and expiry never download a payload", function()
        for _, change in ipairs({ "account", "game", "place", "expiry" }) do
            local f = fixture(); f.runtime:start(); f.game.PlaceId = 4111023553
            if change == "account" then f.player.UserId = 99 elseif change == "game" then f.game.GameId = 99
            elseif change == "place" then f.game.PlaceId = 123 else f.time = 3000 end
            f:bootstrap(); assert(not f.loaded)
        end
    end)
    test("menu resume selects the same slot and exact server once", function()
        local f = fixture(); f.runtime:start(); f.game.PlaceId = 4111023553; f:bootstrap()
        f.runtime:resume(f.env.CLAW_NOTES_RESUME)
        assert(f.calls[2][1] == "PickSlot" and f.calls[2][2] == "A")
        assert(f.calls[3][1] == "PickServer" and f.calls[3][2] == "exact-server" and #f.calls == 3)
    end)
    test("storage failure prevents the leave request and reports it", function()
        local f = fixture(); f.storageFailure = true; f.runtime:start()
        assert(#f.calls == 0 and #f.queued == 0 and f.warning)
    end)
    test("teleport failure clears the pending resume", function()
        local f = fixture(); f.runtime:start(); f.teleport.TeleportInitFailed:Fire(f.player)
        f.game.PlaceId = 4111023553; f:bootstrap(); assert(not f.loaded and not f.active)
    end)
    test("missing key prevents the first drop", function()
        local f = fixture(); f.env.CLAW_NOTES_EXECUTION_KEY = nil
        -- Key is captured at construction, so create a fresh factory with the empty environment.
        local factory = assert(loadstring(source .. "\nreturn newNotesRuntime")); setfenv(factory, f.scope)
        f.runtime = factory()(f.env, f.core, f.ui, f.player, f.gui, child, function() return true end)
        f.runtime:start(); assert(f.count.Text == "4,335" and #f.calls == 0)
    end)
    test("ambiguous Notes events are not activated", function()
        local f = fixture(); f.notes.MouseButton1Click = {}; f.notes.Activated = {}
        local one = { Enabled = true, LuaConnection = true, ForeignState = false }
        local map = { [f.notes.MouseButton1Click] = { one }, [f.notes.Activated] = {} }
        local scope = setmetatable({ child = child, playerGui = f.gui, visible = function() return true end,
            getconnections = function(s) return map[s] end }, { __index = getfenv() })
        local factory = assert(loadstring(buttonSource .. "\nreturn notesConnection")); setfenv(factory, scope); local select = factory()
        assert(select() == one); map[f.notes.Activated] = { one }; assert(select() == nil)
    end)
    print(passed .. " notes runtime tests passed")
end

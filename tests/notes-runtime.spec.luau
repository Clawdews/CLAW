return function(source, newLoop, validRun, buttonSource, autoLoader, manualLoader, bootSource)
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
        local f = { time = 1000, queued = {}, settings = {}, json = {}, files = {}, calls = {}, delayed = {}, serial = 0, amounts = {} }
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
            JSONEncode = function(_, r) f.serial += 1; local id = "json-" .. f.serial; f.json[id] = table.clone(r); return id end,
            JSONDecode = function(_, id) assert(f.json[id]); return table.clone(f.json[id]) end }
        f.game = { GameId = 34, PlaceId = 6473861193, JobId = "exact-server" }
        function f.game:GetService(name)
            return ({ HttpService = f.http, TeleportService = f.teleport, ReplicatedStorage = f.requests.Parent, Players = { LocalPlayer = f.player } })[name]
        end
        f.ui = { setAuto = function(_, active, message) f.active, f.message = active, message end,
            setNotice = function(_, code) assert(type(code) == "string"); f.notice = code end }
        f.core = { used = {}, cancel = function() f.cancelled = true end, run = function(self, raw, cap)
            assert(raw == "MAX")
            if f.beforeRun then f.beforeRun() end
            if self.beforeSubmit then self.beforeSubmit() end
            if f.afterPrepare then f.afterPrepare() end
            if f.noSend then return false, "cancelled" end
            local amount = math.min(cap, tonumber((f.count.Text:gsub(",", ""))))
            self.lastAmount = amount; table.insert(f.amounts, amount)
            if not f.noChange then f.count.Text = tostring(tonumber((f.count.Text:gsub(",", ""))) - amount) end
            return true, "sent"
        end }
        f.scope = setmetatable({ game = f.game, newNotesLoop = newLoop, validNotesRun = validRun,
            os = { time = function() return f.time end, clock = function() return f.time end },
            task = { wait = function(s) f.time += s; if f.waitHook then f.waitHook() end end,
                delay = function(_, fn) table.insert(f.delayed, fn) end },
            queue_on_teleport = function(code) table.insert(f.queued, code) end,
            getgenv = function() return f.env end,
            isfile = function(p) return f.files[p] ~= nil end,
            readfile = function(p) if f.readFailure then error("read failed") end; return f.files[p] end,
            writefile = function(p, v) if f.writeFailure then error("write failed") end; f.files[p] = v end,
            isfolder = function() return true end, makefolder = function() end,
            Enum = { TeleportState = { Started = "Started", InProgress = "InProgress" } }, warn = function() f.warning = true end,
        }, { __index = getfenv() })
        local factory = assert(loadstring(source .. "\nreturn newNotesRuntime")); setfenv(factory, f.scope)
        function f:mount()
            self.runtime = factory()(self.env, self.core, self.ui, self.player, self.gui, child, function(n) return not n.hidden end)
        end
        f:mount()
        function f:saved() return self.http:JSONDecode(self.files[self.runtime.path]) end
        function f:seed(enabled, pending)
            self.files[self.runtime.path] = self.http:JSONEncode({ version = 2, token = "saved-token-123456789",
                accountId = 12, gameId = 34, enabled = enabled, pending = pending or false })
        end
        function f:bootstrap(code)
            local scope = setmetatable({ loadstring = function() return function() f.loaded = (f.loaded or 0) + 1 end end }, { __index = f.scope })
            function f.game:HttpGet(url) assert(url == "https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"); return "payload" end
            local fn = assert(loadstring(code or f.queued[#f.queued])); setfenv(fn, scope); fn()
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
    test("first load is OFF; manual MAX drains without any key or settings requirement", function()
        local f = fixture(); f.runtime:resume(); assert(not f.runtime.enabled and #f.amounts == 0)
        f.scope.writefile = false; f.runtime:drop("MAX")
        assert(table.concat(f.amounts, ",") == "1000,1000,1000,1000,335" and #f.calls == 0 and #f.queued == 0)
    end)
    test("manual total clips 5000 to 3500 and honors a smaller total", function()
        local f = fixture(); f.count.Text = "3500"; assert(f.runtime:drop("5000"))
        assert(table.concat(f.amounts, ",") == "1000,1000,1000,500")
        f = fixture(); assert(f.runtime:drop("1500")); assert(f.count.Text == "2835")
    end)
    test("ON drains and stays enabled at zero without any menu or server call", function()
        local f = fixture(); f.runtime:start()
        assert(f:saved().enabled and not f:saved().pending and f.runtime.enabled and not f.runtime.loop.active)
        assert(#f.amounts == 5 and #f.calls == 0 and #f.queued == 1 and f.active)
        assert(f.message:find("next join"))
    end)
    test("second click persists OFF and invalidates queued continuation", function()
        local f = fixture(); f.runtime:start(); f.runtime:start(); f:bootstrap()
        assert(not f.loaded and not f:saved().enabled and not f.runtime.enabled)
    end)
    test("new runtime reads saved ON and drains a different server and slot without a click", function()
        local f = fixture(); f:seed(true); f.game.JobId = "other-server"; f.player.DataSlot = "B"
        f.runtime:resume(); assert(f.runtime.enabled and f.count.Text == "0" and #f.calls == 0)
    end)
    test("saved OFF stays OFF after another load", function()
        local f = fixture(); f:seed(false); f.runtime:resume()
        assert(not f.runtime.enabled and #f.amounts == 0 and #f.queued == 0)
    end)
    test("saved ON at zero does not require a Notes opener", function()
        local f = fixture(); f:seed(true); f.count.Text = "0"
        f.runtime:resume(); assert(f.runtime.enabled and #f.amounts == 0)
    end)
    test("pending receipt after a crash cannot automatically replay", function()
        local f = fixture(); f:seed(true, true); f.runtime:resume()
        assert(not f.runtime.enabled and not f:saved().enabled and f:saved().pending and #f.amounts == 0)
    end)
    test("receipt is on disk before each send and cleared only after confirmation", function()
        local f = fixture(); local prepared = 0
        f.afterPrepare = function() assert(f:saved().pending); prepared += 1 end
        f.runtime:start(); assert(prepared == 5 and not f:saved().pending)
    end)
    test("unknown balance disables Auto and retains receipt across loads", function()
        local f = fixture(); f.noChange = true; f.runtime:start()
        assert(#f.amounts == 1 and f.core.uncertain and not f:saved().enabled and f:saved().pending)
        f.core.uncertain = false; f:mount(); f.runtime:resume(); assert(#f.amounts == 1)
    end)
    test("Stop between batches saves OFF without marking a confirmed drop uncertain", function()
        local f = fixture(); f.waitHook = function() f.runtime:stop() end; f.runtime:start()
        assert(#f.amounts == 1 and not f:saved().enabled and not f:saved().pending and not f.core.uncertain)
    end)
    test("Stop during confirmation never submits the next batch", function()
        local f = fixture(); f.noChange = true; f.waitHook = function() f.runtime:stop() end; f.runtime:start()
        assert(#f.amounts == 1 and not f:saved().enabled and f:saved().pending and f.core.uncertain)
    end)
    test("failed setting write prevents starting and warns if OFF also cannot save", function()
        local f = fixture(); f.writeFailure = true; f.runtime:start()
        assert(#f.amounts == 0 and #f.calls == 0 and f.warning and not f.runtime.enabled)
    end)
    test("failed durable receipt prevents InvokeServer", function()
        local f = fixture(); f.beforeRun = function() f.writeFailure = true end
        f.runtime:start(); assert(#f.amounts == 0 and not f.runtime.enabled)
    end)
    test("malformed or wrong-account setting never starts", function()
        for _, mode in ipairs({ "bad", "account", "game", "version", "read" }) do
            local f = fixture(); f:seed(true)
            if mode == "bad" then f.files[f.runtime.path] = "bad json"
            elseif mode == "read" then f.readFailure = true
            else
                local saved = f:saved()
                saved[({ account = "accountId", game = "gameId", version = "version" })[mode]] = 99
                f.files[f.runtime.path] = f.http:JSONEncode(saved)
            end
            f.runtime:resume(); assert(#f.amounts == 0 and not f.runtime.enabled)
        end
    end)
    test("menu resume remains idle and never selects a slot or server", function()
        local f = fixture(); f.game.PlaceId = 4111023553; f:seed(true); f.runtime:resume()
        assert(f.runtime.enabled and f.runtime.waiting and #f.amounts == 0 and #f.calls == 0 and #f.queued == 1)
        f.runtime:start(); assert(not f:saved().enabled)
    end)
    test("ON waits for character and unreadable display instead of guessing a balance", function()
        local f = fixture(); f.player.Character = nil; f:seed(true)
        f.waitHook = function() if not f.player.Character then f.player.Character = {} end end; f.runtime:resume(); assert(#f.amounts == 5)
        f = fixture(); f.count.Text = "?"; f:seed(true); f.runtime:resume()
        assert(#f.amounts == 0 and not f.runtime.enabled and not f:saved().enabled)
    end)
    test("user-initiated teleport preserves ON without sending any travel request", function()
        local f = fixture(); f.waitHook = function() f.player.OnTeleport:Fire("Started") end; f.runtime:start()
        assert(#f.amounts == 1 and f:saved().enabled and not f:saved().pending and #f.calls == 0)
    end)
    test("queued continuation consumes its ticket once", function()
        local f = fixture(); f.runtime:start(); f.game.PlaceId = 4111023553; f:bootstrap(); f:bootstrap()
        assert(f.loaded == 1 and #f.calls == 0)
    end)
    test("queued continuation rejects wrong account game and unsupported place", function()
        for _, mode in ipairs({ "account", "game", "place" }) do
            local f = fixture(); f.runtime:start()
            if mode == "account" then f.player.UserId = 99 elseif mode == "game" then f.game.GameId = 99 else f.game.PlaceId = 123 end
            f:bootstrap(); assert(not f.loaded)
        end
    end)
    test("autoexec and teleport continuation cannot double-load", function()
        for _, mode in ipairs({ "loading", "loaded" }) do
            local f = fixture(); f.runtime:start()
            if mode == "loading" then f.env.CLAW_NOTES_LOADING = true else f.env.CLAW_NOTES_DROPPER = { closed = false } end
            f:bootstrap(); assert(not f.loaded)
        end
    end)
    test("missing key blocks saved Auto but not manual batching", function()
        local f = fixture(); f.env.CLAW_NOTES_EXECUTION_KEY = nil; f:mount(); f.runtime:start()
        assert(#f.amounts == 0 and not f.runtime.enabled)
        assert(f.runtime:drop("553") and #f.amounts == 1)
    end)
    test("manager or bringer conflicts refuse both manual batches and Auto", function()
        for _, name in ipairs({ "CLAW_CONTROL", "CLAW_RELAY" }) do
            local f = fixture(); f.env[name] = {}; f.runtime:start(); f.runtime:drop("MAX")
            assert(#f.amounts == 0 and not f.runtime.enabled)
        end
    end)
    test("used prompt remains locked until it disappears", function()
        local f = fixture(); local prompt = node("ChoicePrompt", "ScreenGui", f.gui); f.core.used[prompt] = true
        f.runtime:drop("MAX"); assert(#f.amounts == 0)
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
    test("autoexec only loads for a saved ON account", function()
        local f = fixture(); f:bootstrap(autoLoader); assert(not f.loaded)
        f:seed(false); f:bootstrap(autoLoader); assert(not f.loaded)
        f:seed(true); f:bootstrap(autoLoader); assert(f.loaded == 1)
    end)
    test("autoexec is inert in other games and for other accounts", function()
        for _, mode in ipairs({ "place", "account", "game", "wrong-record" }) do
            local f = fixture(); f:seed(true)
            if mode == "place" then f.game.PlaceId = 123
            elseif mode == "account" then f.player.UserId = 99
            elseif mode == "game" then f.game.GameId = 99
            else local r = f:saved(); r.accountId = 99; f.files[f.runtime.path] = f.http:JSONEncode(r) end
            f:bootstrap(autoLoader); assert(not f.loaded)
        end
    end)
    test("autoexec rejects malformed data and never writes settings", function()
        local f = fixture(); f.files[f.runtime.path] = "bad data"; f.writeFailure = true
        f:bootstrap(autoLoader); assert(not f.loaded and f.warning)
    end)
    test("personal manual loader opens panel even with saved OFF", function()
        local f = fixture(); f:seed(false); f:bootstrap(manualLoader); assert(f.loaded == 1)
    end)
    test("loader guard handles simultaneous or duplicate executions", function()
        local f = fixture(); f:seed(true); f.env.CLAW_NOTES_LOADING = true
        f:bootstrap(autoLoader); f:bootstrap(manualLoader); assert(not f.loaded)
        f.env.CLAW_NOTES_LOADING = nil
        f.env.CLAW_NOTES_DROPPER = { uiVersion = 5, closed = false, show = function() f.shown = true end }
        f:bootstrap(autoLoader); assert(f.shown and not f.loaded)
    end)
    test("button can cancel a manual batch without enabling saved Auto", function()
        local f = fixture(); f.waitHook = function() f.runtime:start() end
        f.runtime:drop("MAX"); assert(#f.amounts == 1 and not f.runtime.enabled and not f.files[f.runtime.path])
    end)
    test("join waits for the initial Notes display to settle before draining", function()
        local f = fixture(); f:seed(true); f.count.Text = "0"
        f.waitHook = function() if f.time < 1001 then f.count.Text = "553" end end
        f.runtime:resume(); assert(#f.amounts == 1 and f.amounts[1] == 553 and f.time >= 1002)
    end)
    test("join waits for the Notes handler to connect without a manual click", function()
        local f = fixture(); f:seed(true); f.core.canOpen = function() return f.time > 1001 end
        f.runtime:resume(); assert(#f.amounts == 5 and f.runtime.enabled)
    end)
    test("true prefix enables and saves ON without clicking, including saved OFF", function()
        for _, existing in ipairs({ true, false }) do
            local f = fixture(); if existing then f:seed(false) end
            f.runtime:resume(true)
            assert(#f.amounts == 5 and f.runtime.enabled and f:saved().enabled and #f.calls == 0)
        end
    end)
    test("false prefix overrides saved ON without submitting anything", function()
        local f = fixture(); f:seed(true); f.runtime:resume(false)
        assert(#f.amounts == 0 and not f.runtime.enabled and not f:saved().enabled)
        f = fixture(); f.runtime:resume(false); assert(not f:saved().enabled and #f.amounts == 0)
    end)
    test("prefix ON is idempotent, not a toggle or another drain", function()
        local f = fixture(); f.runtime:resume(true); f.count.Text = "553"
        local queued = #f.queued; f.runtime:applyAuto(true)
        assert(f.runtime.enabled and #f.amounts == 5 and #f.queued == queued and f.count.Text == "553")
    end)
    test("false prefix on a running batch stops and saves OFF", function()
        local f = fixture(); f.waitHook = function() f.runtime:applyAuto(false) end
        f.runtime:start(); assert(#f.amounts == 1 and not f:saved().enabled)
    end)
    test("true prefix cannot bypass a saved pending receipt", function()
        local f = fixture(); f:seed(true, true); f.runtime:resume(true)
        assert(#f.amounts == 0 and f:saved().pending and not f:saved().enabled)
    end)
    test("false keeps a pending receipt and cannot reset uncertainty", function()
        local f = fixture(); f:seed(true, true); f.runtime:resume(false)
        assert(#f.amounts == 0 and f:saved().pending and not f:saved().enabled)
    end)
    test("quoted or invalid settings fail closed instead of using saved ON", function()
        for _, value in ipairs({ "true", "false", 1, 0, {} }) do
            local f = fixture(); f:seed(true); f.runtime:resume(value)
            assert(#f.amounts == 0 and not f.runtime.enabled and not f:saved().enabled)
        end
    end)
    test("false prefix can save OFF even when the old setting cannot be decoded", function()
        local f = fixture(); f.files[f.runtime.path] = "bad data"; f.runtime:resume(false)
        assert(#f.amounts == 0 and not f:saved().enabled and f:saved().pending)
    end)
    test("true prefix cannot ignore missing storage or an unreadable saved receipt", function()
        local f = fixture(); f.scope.writefile = false; f.runtime:resume(true)
        assert(#f.amounts == 0 and not f.runtime.enabled)
        f = fixture(); f.files[f.runtime.path] = "bad data"; f.runtime:resume(true)
        assert(#f.amounts == 0 and not f.runtime.enabled)
    end)
    test("explicit setting applied before startup is not overwritten by stale startup intent", function()
        local f = fixture(); f.runtime:applyAuto(false); f.runtime:resume(true)
        assert(#f.amounts == 0 and not f.runtime.enabled and not f:saved().enabled)
    end)
    test("generated autoexec allows an explicit prefix even when no saved ON exists", function()
        for _, value in ipairs({ true, false }) do
            local f = fixture(); f.env.CLAW_NOTES_AUTO = value; f:bootstrap(autoLoader)
            assert(f.loaded == 1 and f.env.CLAW_NOTES_AUTO == value)
        end
    end)
    test("both generated loaders apply and consume prefix on an existing UI, even while loading", function()
        for _, loader in ipairs({ autoLoader, manualLoader }) do
            for _, value in ipairs({ true, false }) do
                local f = fixture(); f.env.CLAW_NOTES_AUTO = value; f.env.CLAW_NOTES_LOADING = true
                f.env.CLAW_NOTES_DROPPER = { uiVersion = 5, closed = false, show = function() f.shown = true end,
                    setAuto = function(_, v) f.applied = v end }
                f:bootstrap(loader)
                assert(f.shown and f.applied == value and f.env.CLAW_NOTES_AUTO == nil and not f.loaded)
            end
        end
    end)
    test("raw-script startup consumes prefixes and applies them to an already loaded UI", function()
        for _, value in ipairs({ true, false, "true" }) do
            local f = fixture(); f.env.CLAW_NOTES_AUTO = value
            f.env.CLAW_NOTES_DROPPER = { uiVersion = 5, closed = false, show = function() end,
                setAuto = function(_, v) f.applied = v end }
            local run = assert(loadstring(bootSource)); setfenv(run, f.scope); run()
            assert(f.applied == value and f.env.CLAW_NOTES_AUTO == nil)
        end
    end)
    test("raw-script fresh startup retains false exactly rather than defaulting to saved state", function()
        local f = fixture(); f.env.CLAW_NOTES_AUTO = false
        local run = assert(loadstring(bootSource .. "\nreturn requestedAuto")); setfenv(run, f.scope)
        assert(run() == false and f.env.CLAW_NOTES_AUTO == nil)
    end)
    print(passed .. " notes runtime tests passed")
end

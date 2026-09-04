return function(source)
    local function fixture()
        local f = { env = {}, downloads = 0, starts = 0, waits = 0, elapsed = 0, warnings = {}, urls = {} }
        f.players = { LocalPlayer = { UserId = 22 } }
        f.game = { PlaceId = 4111023553 }
        local http = { GenerateGUID = function() return "nonce-" .. (f.downloads + 1) end }
        function f.game:GetService(name) return name == "Players" and f.players or http end
        function f.game:HttpGet(url)
            f.downloads += 1; table.insert(f.urls, url)
            if f.onDownload then f.onDownload() end
            if f.failures and f.downloads <= f.failures then error("private download error") end
            if f.badSource then return f.badSource end
            return "startClient()"
        end
        f.runtime = setmetatable({
            game = f.game, getgenv = function() return f.env end,
            warn = function(message) table.insert(f.warnings, message) end,
            task = { wait = function(seconds)
                f.waits += 1; f.elapsed += seconds
                if f.onWait then f.onWait() end
            end },
            startClient = function()
                f.starts += 1
                if f.startFailure then error("private startup error") end
                f.env.CLAW_CONTROL = { running = true }
            end,
        }, { __index = getfenv() })
        f.runtime.loadstring = function(body, name)
            local chunk, failure = loadstring(body, name)
            if chunk then setfenv(chunk, f.runtime) end
            return chunk, failure
        end
        function f:run()
            local chunk = assert(loadstring(source)); setfenv(chunk, self.runtime); chunk()
        end
        return f
    end
    local count = 0
    local function test(name, run) run(); count += 1; print("PASS autoexec " .. name) end
    test("the same file starts on every supported destination", function()
        for _, place in ipairs({ 4111023553, 6473861193, 6032399813 }) do
            local f = fixture(); f.game.PlaceId = place; f:run()
            assert(f.starts == 1 and f.downloads == 1 and not f.env.CLAW_AUTOEXEC_LOADING)
            assert(f.urls[1] == "https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua?cache=nonce-1")
        end
    end)
    test("unrelated games and unsupported layers perform no download", function()
        for _, place in ipairs({ 1, 2, 5735553160 }) do
            local f = fixture(); f.game.PlaceId = place; f:run()
            assert(f.starts == 0 and f.downloads == 0 and #f.warnings == 0 and not f.env.CLAW_AUTOEXEC_LOADING)
        end
    end)
    test("early autoexec waits for player and place", function()
        local f = fixture(); f.players.LocalPlayer = nil; f.game.PlaceId = 0
        f.onWait = function()
            if f.waits == 2 then f.players.LocalPlayer = { UserId = 22 } end
            if f.waits == 3 then f.game.PlaceId = 4111023553 end
        end
        f:run(); assert(f.waits == 3 and f.starts == 1)
    end)
    test("startup wait is bounded and retryable", function()
        local f = fixture(); f.players.LocalPlayer = nil; f:run()
        assert(f.elapsed == 60 and f.downloads == 0 and #f.warnings == 1 and not f.env.CLAW_AUTOEXEC_LOADING)
        f.players.LocalPlayer = { UserId = 22 }; f:run(); assert(f.starts == 1)
    end)
    test("existing controller is left alone", function()
        local f = fixture(); local existing = {}; f.env.CLAW_CONTROL = existing; f:run()
        assert(f.downloads == 0 and f.env.CLAW_CONTROL == existing)
    end)
    test("concurrent autoexec files do not double-start", function()
        local f = fixture(); f.onDownload = function() f:run() end
        f:run(); assert(f.downloads == 1 and f.starts == 1)
    end)
    test("manual startup during a download is not replaced", function()
        local f = fixture(); local existing = {}; f.onDownload = function() f.env.CLAW_CONTROL = existing end
        f:run(); assert(f.starts == 0 and f.env.CLAW_CONTROL == existing and not f.env.CLAW_AUTOEXEC_LOADING)
    end)
    test("download failure retries only three times with fresh URLs", function()
        local f = fixture(); f.failures = 2; f:run()
        assert(f.downloads == 3 and f.starts == 1 and f.elapsed == 6)
        assert(f.urls[1] ~= f.urls[2] and f.urls[2] ~= f.urls[3])
    end)
    test("failed downloads leave a retryable state and no private error text", function()
        local f = fixture(); f.failures = 3; f:run()
        assert(f.downloads == 3 and f.starts == 0 and #f.warnings == 1 and not f.env.CLAW_AUTOEXEC_LOADING)
        assert(not f.warnings[1]:find("private", 1, true)); f:run(); assert(f.starts == 1)
    end)
    test("empty and oversized responses are not executed", function()
        for _, value in ipairs({ "", string.rep("x", 1048577) }) do
            local f = fixture(); f.badSource = value; f:run()
            assert(f.downloads == 3 and f.starts == 0 and #f.warnings == 1)
        end
    end)
    test("compile errors do not echo source or execute anything", function()
        local f = fixture(); f.badSource = "private broken source !!!"; f:run()
        assert(f.downloads == 1 and f.starts == 0 and #f.warnings == 1 and not f.env.CLAW_AUTOEXEC_LOADING)
        assert(not f.warnings[1]:find("private", 1, true))
    end)
    test("startup errors never repeat game actions automatically", function()
        local f = fixture(); f.startFailure = true; f:run()
        assert(f.downloads == 1 and f.starts == 1 and #f.warnings == 1 and not f.env.CLAW_AUTOEXEC_LOADING)
        assert(not f.warnings[1]:find("private", 1, true))
    end)
    print(tostring(count) .. " autoexec tests passed")
end

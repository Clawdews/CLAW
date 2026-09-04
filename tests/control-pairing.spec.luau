return function(pairSource, launcherSource, bundledSource)
    local function copy(t)
        if type(t) ~= "table" then return t end
        local c = {}; for k, v in pairs(t) do c[k] = copy(v) end; return c
    end
    local function fixture()
        local f = { files = {}, json = {}, count = 0, requests = 0, downloads = 0, status = 200, logs = {}, writes = 0 }
        local http = {}
        function http:JSONEncode(value)
            f.count += 1; local raw = "json-" .. f.count; f.json[raw] = copy(value); return raw
        end
        function http:JSONDecode(raw) return copy(assert(f.json[raw], "invalid JSON")) end
        function http:GenerateGUID() return "cache" end
        f.http = http
        f.env = { CLAW_PAIR = { Endpoint = "https://claw.test", OwnerId = "123456789012345678", AccountId = "22", Key = string.rep("a", 64) } }
        f.input = copy(f.env.CLAW_PAIR)
        local game = {}
        function game:GetService(name)
            if name == "HttpService" then return http end
            assert(name == "Players"); return { LocalPlayer = { UserId = f.userId or 22 } }
        end
        function game:HttpGet(url)
            if url:find("/control/pair.lua", 1, true) then f.downloads += 1; return pairSource end
            assert(url:find("/control-client.lua", 1, true)); f.downloads += 1; return "return true"
        end
        f.runtime = setmetatable({
            game = game, getgenv = function() return f.env end,
            readfile = function(path) return assert(f.files[path], "missing file") end,
            isfile = function(path) return f.files[path] ~= nil end,
            writefile = function(path, raw) f.files[path] = raw; f.writes += 1 end,
            isfolder = function() return true end, makefolder = function() end,
            request = function(r)
                assert(r.Url == "https://claw.test/session?owner=123456789012345678" and r.Method == "POST")
                local b = http:JSONDecode(r.Body); assert(b.accountId == "22" and #b.key == 64)
                f.requests += 1; return { StatusCode = f.status }
            end,
            print = function(message) f.logs[#f.logs + 1] = message end,
        }, { __index = getfenv() })
        f.runtime.loadstring = function(source)
            local c, err = loadstring(source); if c then setfenv(c, f.runtime) end; return c, err
        end
        function f:run(source) local c = assert(loadstring(source)); setfenv(c, self.runtime); return pcall(c) end
        function f:existing(overrides)
            local value = copy(self.input); value.Version = 1; value.AllowMenuReturn = false
            for k, v in pairs(overrides or {}) do value[k] = v end
            self.files["CLAW_PAIRINGS/22.json"] = http:JSONEncode(value)
        end
        return f
    end
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS pairing " .. name) end
    local function privateFailure(f, source, expected)
        local ok, failure = f:run(source)
        assert(not ok and type(failure) == "string", "Expected a controlled setup failure")
        assert(not failure:find(f.input.Key, 1, true), "A private key escaped through a setup error")
        assert(failure:find(expected, 1, true), "Missing useful setup instruction")
        for _, message in ipairs(f.logs) do assert(not message:find(f.input.Key, 1, true), "A private key escaped through a log") end
    end
    test("an unreadable file cannot bypass the existing owner check", function()
        for _, owner in ipairs({ "123456789012345678", "234567890123456789" }) do
            local f = fixture(); f:existing({ OwnerId = owner }); local before = f.files["CLAW_PAIRINGS/22.json"]
            f.runtime.readfile = function() error("read failed " .. f.input.Key) end
            privateFailure(f, pairSource, "Cannot read saved pairing")
            assert(f.requests == 0 and f.writes == 0 and f.files["CLAW_PAIRINGS/22.json"] == before)
        end
    end)
    test("unknown file existence stops pairing without echoing an adapter error", function()
        for _, detector in ipairs({ function() error("private adapter failure") end, function() return nil end, function() return 1 end }) do
            local f = fixture(); f.runtime.isfile = detector
            privateFailure(f, pairSource, "Cannot check pairing file")
            assert(f.requests == 0 and f.writes == 0)
        end
    end)
    test("missing file support stops before authentication or writes", function()
        for _, name in ipairs({ "isfile", "readfile", "writefile", "isfolder", "makefolder" }) do
            local f = fixture(); f.runtime[name] = false
            privateFailure(f, pairSource, "Executor file support required")
            assert(f.requests == 0 and f.writes == 0)
        end
    end)
    test("a pairing changed while authentication yields is never overwritten", function()
        for _, wasPresent in ipairs({ true, false }) do
            local f = fixture(); if wasPresent then f:existing() end
            local request, changed = f.runtime.request, nil
            f.runtime.request = function(r)
                local result = request(r); f:existing({ OwnerId = "234567890123456789" })
                changed = f.files["CLAW_PAIRINGS/22.json"]; return result
            end
            privateFailure(f, pairSource, "Pairing file changed during setup")
            assert(f.requests == 1 and f.writes == 0 and f.files["CLAW_PAIRINGS/22.json"] == changed)
        end
    end)
    test("a file removed while authentication yields is not silently recreated", function()
        local f = fixture(); f:existing(); local request = f.runtime.request
        f.runtime.request = function(r) local result = request(r); f.files["CLAW_PAIRINGS/22.json"] = nil; return result end
        privateFailure(f, pairSource, "Pairing file changed during setup")
        assert(f.requests == 1 and f.writes == 0 and not f.files["CLAW_PAIRINGS/22.json"])
    end)
    test("unreadable saved files are not described as first setup by either launcher", function()
        for _, source in ipairs({ launcherSource, bundledSource }) do
            local f = fixture(); f.env.CLAW_PAIR = nil; f:existing()
            f.runtime.readfile = function() error("read failed " .. f.input.Key) end
            privateFailure(f, source, "Cannot read saved pairing")
            assert(f.downloads == 0 and #f.logs == 0 and not f.env.CLAW_CONTROL_CONFIG)
        end
    end)
    test("launcher cannot call an unknown file state unpaired", function()
        for _, source in ipairs({ launcherSource, bundledSource }) do
            local f = fixture(); f.env.CLAW_PAIR = nil
            f.runtime.isfile = function() error("file check failed " .. f.input.Key) end
            privateFailure(f, source, "Cannot check pairing file")
            assert(f.downloads == 0 and #f.logs == 0)
        end
    end)
    test("pairing decode errors cannot echo the saved key", function()
        local f = fixture(); f:existing()
        function f.http:JSONDecode() error("decoder included " .. f.input.Key) end
        privateFailure(f, pairSource, "Existing pairing file is invalid")
        assert(f.requests == 0 and f.writes == 0 and f.env.CLAW_PAIR == nil)
    end)
    test("launcher decode errors cannot echo the saved key", function()
        local f = fixture(); f.env.CLAW_PAIR = nil; f:existing()
        function f.http:JSONDecode() error("decoder included " .. f.input.Key) end
        privateFailure(f, launcherSource, "Invalid local pairing file")
        assert(f.downloads == 0 and not f.env.CLAW_CONTROL_CONFIG)
    end)
    test("published launcher hides pairing and startup decoder errors", function()
        for _, firstRun in ipairs({ true, false }) do
            local f = fixture(); f:existing(); if not firstRun then f.env.CLAW_PAIR = nil end
            function f.http:JSONDecode() error("decoder included " .. f.input.Key) end
            privateFailure(f, bundledSource, firstRun and "Existing pairing file is invalid" or "Invalid local pairing file")
            assert(f.requests == 0 and f.writes == 0 and f.downloads == 0)
        end
    end)
    test("pairing transport errors cannot echo a request body", function()
        local f = fixture(); f:existing(); local before = f.files["CLAW_PAIRINGS/22.json"]
        f.runtime.request = function() error("request body included " .. f.input.Key) end
        privateFailure(f, pairSource, "Pairing rejected or relay unavailable")
        assert(f.writes == 0 and f.files["CLAW_PAIRINGS/22.json"] == before)
    end)
    test("pairing encode errors cannot echo the supplied key", function()
        local f = fixture()
        function f.http:JSONEncode() error("encoder included " .. f.input.Key) end
        privateFailure(f, pairSource, "Could not prepare pairing")
        assert(f.requests == 0 and f.writes == 0)
    end)
    test("pairing write and verification errors never print file contents", function()
        for _, stage in ipairs({ "write", "verify" }) do
            local f = fixture()
            if stage == "write" then f.runtime.writefile = function() error("write included " .. f.input.Key) end
            else
                local read = f.runtime.readfile
                f.runtime.readfile = function(path)
                    if f.writes > 0 then error("verification included " .. f.input.Key) end
                    return read(path)
                end
            end
            privateFailure(f, pairSource, "Could not save and verify pairing")
        end
    end)
    test("pair authenticates and saves just the local account, with automatic exits off", function()
        local f = fixture(); assert(f:run(pairSource)); assert(f.env.CLAW_PAIR == nil and f.requests == 1 and f.downloads == 0)
        local saved = f.http:JSONDecode(f.files["CLAW_PAIRINGS/22.json"])
        assert(saved.OwnerId == f.input.OwnerId and saved.Key == f.input.Key and saved.AllowMenuReturn == false)
        for _, message in ipairs(f.logs) do assert(not message:find(f.input.Key, 1, true)) end
    end)
    test("wrong local account cannot authenticate or write", function()
        local f = fixture(); f.userId = 33; assert(not f:run(pairSource)); assert(f.requests == 0 and f.writes == 0)
    end)
    test("another local owner cannot be overwritten", function()
        local f = fixture(); f:existing({ OwnerId = "234567890123456789" })
        assert(not f:run(pairSource)); assert(f.requests == 0 and f.writes == 0)
    end)
    test("corrupt existing file is not silently replaced", function()
        local f = fixture(); f.files["CLAW_PAIRINGS/22.json"] = "corrupt"
        assert(not f:run(pairSource)); assert(f.requests == 0 and f.writes == 0)
    end)
    test("relay rejection leaves the old pairing intact", function()
        local f = fixture(); f:existing(); local before = f.files["CLAW_PAIRINGS/22.json"]; f.status = 401
        assert(not f:run(pairSource)); assert(f.requests == 1 and f.writes == 0 and f.files["CLAW_PAIRINGS/22.json"] == before)
    end)
    test("key replacement preserves local automatic-exit preference", function()
        local f = fixture(); f:existing({ AllowMenuReturn = true, Key = string.rep("b", 64) })
        assert(f:run(pairSource)); local saved = f.http:JSONDecode(f.files["CLAW_PAIRINGS/22.json"])
        assert(saved.AllowMenuReturn and saved.Key == f.input.Key)
    end)
    test("unpaired autoexec does not download or execute a client", function()
        local f = fixture(); f.env.CLAW_PAIR = nil
        assert(f:run(launcherSource)); assert(f.downloads == 0 and not f.env.CLAW_CONTROL_CONFIG)
    end)
    test("public launcher uses the local pairing without writing keys", function()
        local f = fixture(); f.env.CLAW_PAIR = nil; f:existing(); assert(f:run(launcherSource))
        assert(f.downloads == 1 and f.writes == 0 and f.env.CLAW_CONTROL_CONFIG.OwnerId == f.input.OwnerId)
    end)
    test("wrong account or malformed owner is rejected before download", function()
        for _, overrides in ipairs({ { AccountId = "33" }, { OwnerId = "bad" }, { Endpoint = "http://bad" }, { Key = "bad" } }) do
            local f = fixture(); f.env.CLAW_PAIR = nil; f:existing(overrides); assert(not f:run(launcherSource)); assert(f.downloads == 0)
        end
    end)
    test("first run pairs and launches through the same public entry", function()
        local f = fixture(); assert(f:run(launcherSource))
        assert(f.requests == 1 and f.writes == 1 and f.downloads == 2 and f.env.CLAW_PAIR == nil)
        assert(f.env.CLAW_CONTROL_CONFIG.OwnerId == f.input.OwnerId)
    end)
    test("failed first pairing cannot launch the client", function()
        local f = fixture(); f.status = 401; assert(not f:run(launcherSource))
        assert(f.requests == 1 and f.writes == 0 and f.downloads == 1 and not f.env.CLAW_CONTROL_CONFIG)
    end)
    print(tostring(passed) .. " pairing tests passed")
end

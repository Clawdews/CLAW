return function(pairSource, launcherSource)
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
            assert(url:find("/control-client.lua", 1, true)); f.downloads += 1; return "return true"
        end
        f.runtime = setmetatable({
            game = game, getgenv = function() return f.env end,
            readfile = function(path) return assert(f.files[path], "missing file") end,
            writefile = function(path, raw) f.files[path] = raw; f.writes += 1 end,
            isfolder = function() return true end, makefolder = function() end,
            request = function(r)
                assert(r.Url == "https://claw.test/session?owner=123456789012345678" and r.Method == "POST")
                local b = http:JSONDecode(r.Body); assert(b.accountId == "22" and #b.key == 64)
                f.requests += 1; return { StatusCode = f.status }
            end,
            print = function(message) f.logs[#f.logs + 1] = message end,
        }, { __index = getfenv() })
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
        local f = fixture(); assert(f:run(launcherSource)); assert(f.downloads == 0 and not f.env.CLAW_CONTROL_CONFIG)
    end)
    test("public launcher uses the local pairing without writing keys", function()
        local f = fixture(); f:existing(); assert(f:run(launcherSource))
        assert(f.downloads == 1 and f.writes == 0 and f.env.CLAW_CONTROL_CONFIG.OwnerId == f.input.OwnerId)
    end)
    test("wrong account or malformed owner is rejected before download", function()
        for _, overrides in ipairs({ { AccountId = "33" }, { OwnerId = "bad" }, { Endpoint = "http://bad" }, { Key = "bad" } }) do
            local f = fixture(); f:existing(overrides); assert(not f:run(launcherSource)); assert(f.downloads == 0)
        end
    end)
    print(tostring(passed) .. " pairing tests passed")
end

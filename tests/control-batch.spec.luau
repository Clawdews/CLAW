return function(batchSource, pairSource, launcherSource, bundleSource)
    local function copy(v)
        if type(v) ~= "table" then return v end
        local result = {}; for k, value in pairs(v) do result[k] = copy(value) end; return result
    end
    local function fixture()
        local f = { env = {}, files = {}, json = {}, sequence = 0, requests = 0, writes = 0, time = 1000, logs = {}, starts = 0, status = "pending" }
        f.config = { Version = 1, Endpoint = "https://claw.test", OwnerId = "123456789012345678", Code = string.rep("a", 64), Expires = 1600 }
        local http = {}
        function http:JSONEncode(value) f.sequence += 1; local raw = "json" .. f.sequence; f.json[raw] = copy(value); return raw end
        function http:JSONDecode(raw) return copy(assert(f.json[raw], "private decode error")) end
        function http:GenerateGUID() return "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" end
        f.http = http
        local player = { UserId = 22, Name = "Nova_Alt" }
        local game = {}
        function game:GetService(name) if name == "Players" then return { LocalPlayer = player } end; assert(name == "HttpService"); return http end
        function game:HttpGet(url)
            if url:find("control/batch.lua", 1, true) then return batchSource end
            if url:find("control/pair.lua", 1, true) then return pairSource end
            assert(url:find("control-client.lua", 1, true)); return "CLIENT_STUB"
        end
        f.runtime = setmetatable({ game = game, getgenv = function() return f.env end, os = { time = function() return f.time end },
            isfile = function(path) return f.files[path] ~= nil end, readfile = function(path) return assert(f.files[path], "private missing file") end,
            writefile = function(path, raw) f.files[path] = raw; f.writes += 1 end, isfolder = function() return true end, makefolder = function() end,
            delfile = function(path) f.files[path] = nil end,
            task = { wait = function(delay) assert(delay > 0 and delay <= 30); f.time += delay; if f.wait then f.wait() end end },
            print = function(message) f.logs[#f.logs + 1] = message end,
            request = function(r)
                f.requests += 1
                if f.request then return f.request(r) end
                if r.Url:find("/session?", 1, true) then return { StatusCode = 200 } end
                assert(r.Url == "https://claw.test/batch?owner=123456789012345678")
                local body = http:JSONDecode(r.Body); assert(body.accountId == "22" and #body.key == 64 and #body.code == 64)
                return { StatusCode = 200, Body = http:JSONEncode({ state = f.status, check = "1234ABCD" }) }
            end,
        }, { __index = getfenv() })
        f.runtime.loadstring = function(source)
            if source == "CLIENT_STUB" or source:find("local __CLAW_BUNDLE =", 1, true) then return function() f.starts += 1; return true end end
            local chunk, err = loadstring(source); if chunk then setfenv(chunk, f.runtime) end; return chunk, err
        end
        function f:run(source) local chunk = assert(loadstring(source)); setfenv(chunk, self.runtime); return pcall(chunk) end
        function f:shared() self.files["CLAW_PAIRINGS/batch.json"] = http:JSONEncode(self.config) end
        function f:paired() self.files["CLAW_PAIRINGS/22.json"] = http:JSONEncode({ Version = 1, AccountId = "22", OwnerId = self.config.OwnerId,
            Endpoint = self.config.Endpoint, Key = string.rep("c", 64), AllowMenuReturn = true }) end
        return f
    end
    local count = 0
    local function test(name, fn) fn(); count += 1; print("PASS batch " .. name) end
    test("existing pairings take precedence and do not request new keys", function()
        local f = fixture(); f:shared(); f:paired(); local before = f.files["CLAW_PAIRINGS/22.json"]
        assert(f:run(batchSource)); assert(f.requests == 0 and f.writes == 0 and f.files["CLAW_PAIRINGS/22.json"] == before)
    end)
    test("one explicit setup on a paired main saves only the shared setup file", function()
        local f = fixture(); f:paired(); f.env.CLAW_BATCH = copy(f.config); local before = f.files["CLAW_PAIRINGS/22.json"]
        assert(f:run(batchSource)); assert(f.files["CLAW_PAIRINGS/batch.json"] and f.files["CLAW_PAIRINGS/22.json"] == before)
        assert(f.requests == 0 and f.writes == 1)
    end)
    test("new accounts save their own pending key before requesting approval", function()
        local f = fixture(); f:shared()
        f.request = function(r)
            assert(f.files["CLAW_PAIRINGS/pending-22.json"], "key must survive a restart before request")
            assert(not f.files["CLAW_PAIRINGS/22.json"])
            return { StatusCode = 200, Body = f.http:JSONEncode({ state = "approved" }) }
        end
        assert(f:run(batchSource)); assert(f.env.CLAW_PAIR and #f.env.CLAW_PAIR.Key == 64)
        assert(not f.files["CLAW_PAIRINGS/22.json"], "approval still requires normal authenticated pairing")
    end)
    test("pending polls stop after the setup window instead of running forever", function()
        local f = fixture(); f:shared(); local ok, result = f:run(batchSource)
        assert(ok and result == false and f.time <= 1630 and f.requests <= 22 and f.starts == 0)
        assert(not f.files["CLAW_PAIRINGS/22.json"])
    end)
    test("no batch file or an expired window does not create pending keys", function()
        for _, expired in ipairs({ true, false }) do
            local f = fixture(); if expired then f.config.Expires = 999; f:shared() end
            local ok, result = f:run(batchSource); assert(ok and result == true and f.requests == 0 and f.writes == 0)
        end
    end)
    test("retries retain the saved private key and never print it", function()
        local f = fixture(); f:shared(); f.config.Expires = 1030; f:shared(); f:run(batchSource)
        local pending = f.http:JSONDecode(f.files["CLAW_PAIRINGS/pending-22.json"])
        f.config.Expires = 1100; f:shared(); f.status = "approved"; assert(f:run(batchSource))
        assert(f.env.CLAW_PAIR.Key == pending.Key)
        for _, message in ipairs(f.logs) do assert(not message:find(pending.Key, 1, true) and not message:find(f.config.Code, 1, true)) end
    end)
    test("another owner's active setup or pending file cannot be overwritten", function()
        for _, stage in ipairs({ "shared", "pending" }) do
            local f = fixture(); f:shared(); local raw
            if stage == "shared" then f.env.CLAW_BATCH = copy(f.config); f.env.CLAW_BATCH.OwnerId = "234567890123456789"; raw = f.files["CLAW_PAIRINGS/batch.json"]
            else
                local pending = copy(f.config); pending.AccountId = "22"; pending.Key = string.rep("b", 64); pending.OwnerId = "234567890123456789"
                f.files["CLAW_PAIRINGS/pending-22.json"] = f.http:JSONEncode(pending); raw = f.files["CLAW_PAIRINGS/pending-22.json"]
            end
            assert(not f:run(batchSource)); assert(f.requests == 0 and f.writes == 0)
            assert((stage == "shared" and f.files["CLAW_PAIRINGS/batch.json"] or f.files["CLAW_PAIRINGS/pending-22.json"]) == raw)
        end
    end)
    test("unreadable files and failed writes stop without leaking adapter contents", function()
        for _, method in ipairs({ "readfile", "writefile", "isfile" }) do
            local f = fixture(); f:shared(); f.runtime[method] = function() error("secret " .. f.config.Code) end
            local ok, err = f:run(batchSource); assert(not ok and not err:find(f.config.Code, 1, true) and f.requests == 0)
        end
    end)
    test("an existing duplicate run is superseded and never pairs after it is replaced", function()
        local f = fixture(); f:shared(); f.wait = function() f.env.CLAW_BATCH_ACTIVE = {} end
        local ok, result = f:run(batchSource); assert(ok and result == false and f.requests == 1 and f.env.CLAW_PAIR == nil)
    end)
    test("changing the shared setup window stops the previous poller", function()
        local f = fixture(); f:shared(); f.wait = function() f.config.Code = string.rep("d", 64); f:shared() end
        local ok, result = f:run(batchSource); assert(ok and result == false and f.requests == 1)
    end)
    test("untrusted network errors are not printed", function()
        local f = fixture(); f.config.Expires = 1001; f:shared(); f.request = function() error("private " .. f.config.Code) end
        local ok, result = f:run(batchSource); assert(ok and result == false)
        for _, message in ipairs(f.logs) do assert(not message:find(f.config.Code, 1, true)) end
    end)
    test("source and published loader complete batch approval and normal pairing in one execution", function()
        for _, source in ipairs({ launcherSource, bundleSource }) do
            local f = fixture(); f:shared(); f.status = "approved"
            assert(f:run(source)); assert(f.starts == 1 and f.requests == 2)
            local saved = f.http:JSONDecode(f.files["CLAW_PAIRINGS/22.json"])
            assert(saved.AccountId == "22" and saved.AllowMenuReturn == false and #saved.Key == 64)
            assert(not f.files["CLAW_PAIRINGS/pending-22.json"], "matching temporary key removed only after verified save")
        end
    end)
    print(count .. " batch setup tests passed")
end

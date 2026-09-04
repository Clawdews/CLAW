return function(source, moduleSource, bundled)
    local function object(name, class, text, children)
        local o = { Name = name, ClassName = class or "Frame", Text = text, children = children or {} }
        function o:IsA(c) return self.ClassName == c or (c == "GuiObject" and self.ClassName ~= "ScreenGui") end
        function o:GetChildren() return self.children end
        return o
    end
    local function fixture()
        local node = object("SlotScroll", "ScrollingFrame", nil, {
            object("L", "TextButton", "", {
                object("CharacterName", "TextLabel", "Example Character"), object("Level", "TextLabel", "Lv. 1"),
                object("Race", "TextLabel", "Khan"), object("Realm", "TextLabel", "Eastern Luminant"),
                object("Origin", "TextLabel", "Authority Ensign"), object("Playtime", "TextLabel", "0h 26m"),
                object("LastPlayed", "TextLabel", "0m ago"),
            }) })
        for _, name in ipairs({ "Slots", "MainFrame", "Columns", "Overlay", "LoadingGui", "PlayerGui" }) do
            node = object(name, "Frame", nil, { node })
        end
        local f = { files = {}, downloads = 0, logs = {}, env = {}, report = nil, writes = 0, playerGui = node }
        local player = { UserId = 22 }
        function player:FindFirstChild(name) assert(name == "PlayerGui"); return f.playerGui end
        local http = {}
        function http:GenerateGUID() return "test" end
        function http:JSONEncode(value) f.report = value; return f.oversize and string.rep("x", 400000) or "REPORT" end
        local game = { PlaceId = 4111023553 }
        function game:GetService(name)
            if name == "HttpService" then return http end
            assert(name == "Players"); return { LocalPlayer = player }
        end
        function game:HttpGet(url)
            assert(not bundled and url:find("/control/menu-scan.lua", 1, true)); f.downloads += 1; return moduleSource
        end
        local env = setmetatable({ game = game, task = { wait = function() end }, getgenv = function() return f.env end,
            isfolder = function(path) assert(path == "CLAW_CONTROL"); return true end,
            makefolder = function() error("Folder already exists") end,
            writefile = function(path, raw)
                if f.failSave then error("disk unavailable") end
                assert(path == "CLAW_CONTROL/menu-22.json"); f.files[path] = raw; f.writes += 1
            end,
            readfile = function(path) return f.corruptRead and "CORRUPTED" or f.files[path] end,
            print = function(message) f.logs[#f.logs + 1] = message end,
        }, { __index = getfenv() })
        function env.loadstring(text, name)
            local fn, err = loadstring(text, name); if fn then setfenv(fn, env) end; return fn, err
        end
        function f:run() local fn = assert(env.loadstring(source)); return pcall(fn) end
        f.game = game
        return f
    end
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS scanner runtime " .. name) end
    test("save contains separate card fields and readable console summary", function()
        local f = fixture(); local ok, result = f:run(); assert(ok, result)
        assert(f.files["CLAW_CONTROL/menu-22.json"] == "REPORT" and f.writes == 1)
        assert(result.accountId == "22" and result.version == "0.2.0" and result.completeCards == 1)
        assert(f.env.CLAW_SLOT_SCAN == result and result.cards[1].confirmed == false)
        assert(f.logs[2]:find("Example Character", 1, true) and f.logs[2]:find("Authority Ensign", 1, true))
        assert(f.downloads == (bundled and 0 or 1))
    end)
    test("wrong game place cannot scan or write", function()
        local f = fixture(); f.game.PlaceId = 6473861193
        assert(not f:run() and f.writes == 0 and f.downloads == 0)
    end)
    test("file failure keeps report in memory and reports the failure", function()
        local f = fixture(); f.failSave = true; assert(f:run())
        assert(f.env.CLAW_SLOT_SCAN and f.writes == 0 and f.logs[#f.logs]:find("File save unavailable", 1, true))
    end)
    test("failed readback is not reported as a successful save", function()
        local f = fixture(); f.corruptRead = true; assert(f:run())
        assert(f.logs[#f.logs]:find("File save unavailable", 1, true))
    end)
    test("absent cards yield an honest empty report", function()
        local f = fixture(); f.playerGui = nil; local ok, result = f:run(); assert(ok)
        assert(result.status == "NO_SLOT_LIST" and #result.cards == 0 and f.writes == 1)
    end)
    test("oversize report cannot overwrite the previous file", function()
        local f = fixture(); f.files["CLAW_CONTROL/menu-22.json"] = "OLD"; f.oversize = true
        assert(not f:run() and f.files["CLAW_CONTROL/menu-22.json"] == "OLD" and f.writes == 0)
    end)
    print(tostring(passed) .. " " .. (bundled and "bundled" or "source") .. " scanner runtime tests passed")
end

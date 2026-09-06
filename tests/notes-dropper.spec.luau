return function(newDropper, promptSource, learnSource)
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS dropper " .. name) end
    local function fixture()
        local f = { time = 0, opens = 0, sends = 0, actor = {}, learned = true, identity = {}, choice = {} }
        function f:prompt() return { kind = "notes", identity = self.identity, choice = self.choice, minimum = 1, maximum = 544 } end
        f.current = f:prompt()
        f.core = newDropper({ now = function() return f.time end, actor = function() return f.actor end,
            inspect = function() if f.onInspect then return f.onInspect() end; return f.current end,
            canOpen = function() return f.learned end,
            open = function() f.opens += 1; if f.openError then error("open failed") end; if not f.noPrompt then f.current = f:prompt() end end,
            sleep = function(dt) f.time += dt; if f.onSleep then f.onSleep() end end,
            submit = function(choice, amount)
                f.sends += 1; assert(choice == f.choice); f.amount = amount
                if f.onSend then f.onSend() end
                if f.sendError then error("unknown delivery") end
                return nil
            end,
        })
        return f
    end
    test("creating a dropper does not send anything", function() local f = fixture(); assert(f.sends == 0 and f.opens == 0) end)
    test("MAX follows live bounds for both large and uneven balances", function()
        for _, max in ipairs({ 4335, 1000, 553, 1 }) do
            local f = fixture(); f.current.maximum = max; assert(f.core:run("MAX"))
            assert(f.amount == math.min(1000, max) and f.sends == 1)
        end
    end)
    test("MAX with no remaining notes submits nothing", function()
        local f = fixture(); f.current.maximum = 0; local ok, code = f.core:run("MAX")
        assert(not ok and code == "empty" and f.sends == 0)
    end)
    test("chosen amount is submitted once to the exact active notes prompt", function()
        local f = fixture(); local ok, result = f.core:run("2")
        assert(ok and result == "sent" and f.sends == 1 and f.amount == 2 and f.opens == 0)
    end)
    test("the same prompt cannot be submitted twice", function()
        local f = fixture(); assert(f.core:run("2")); local ok, result = f.core:run("2")
        assert(not ok and result == "already-sent" and f.sends == 1)
    end)
    test("a new explicit operation can use a fresh prompt", function()
        local f = fixture(); assert(f.core:run("2")); f.identity = {}; f.current = f:prompt()
        assert(f.core:run("3")); assert(f.sends == 2 and f.amount == 3)
    end)
    test("invalid amounts and live out-of-range amounts never submit", function()
        for _, raw in ipairs({ "0", "-1", "1.5", "1e2", "nan", "", "545", "1000000001", "99999999999999" }) do
            local f = fixture(); assert(not f.core:run(raw)); assert(f.sends == 0 and f.opens == 0)
        end
    end)
    test("reads current bounds rather than using a cached limit", function()
        local f = fixture(); f.current.maximum = 1; local _, result = f.core:run("2")
        assert(result == "range" and f.sends == 0)
    end)
    test("other dialogs and incomplete UI cannot be submitted", function()
        for _, kind in ipairs({ "other", "loading" }) do
            local f = fixture(); f.current.kind = kind; local _, result = f.core:run("2")
            assert(result == "other-prompt" and f.sends == 0 and f.opens == 0)
        end
    end)
    test("unknown opener asks for manual learning, without guessing", function()
        local f = fixture(); f.current = nil; f.learned = false; local _, result = f.core:run("2")
        assert(result == "learn" and f.sends == 0 and f.opens == 0)
    end)
    test("a learned opener is called once, then the new prompt is used", function()
        local f = fixture(); f.current = nil; assert(f.core:run("2")); assert(f.opens == 1 and f.sends == 1)
    end)
    test("opening timeout never loops remote calls or submits", function()
        local f = fixture(); f.current = nil; f.noPrompt = true; local _, result = f.core:run("2")
        assert(result == "open-timeout" and f.opens == 1 and f.sends == 0 and not f.core.busy)
    end)
    test("stop and character changes during opening cancel the drop", function()
        for _, changeActor in ipairs({ false, true }) do
            local f = fixture(); f.current = nil; f.noPrompt = true
            f.onSleep = function() if changeActor then f.actor = {} else f.core:cancel() end end
            local _, result = f.core:run("2"); assert(result == "cancelled" and f.sends == 0)
        end
    end)
    test("a changed prompt identity or choice aborts submission", function()
        for _, field in ipairs({ "identity", "choice" }) do
            local f = fixture(); local count = 0
            f.onInspect = function() count += 1; if count == 2 then f.current[field] = {} end; local p = {}; for k,v in pairs(f.current) do p[k]=v end; return p end
            local _, result = f.core:run("2"); assert(result == "changed" and f.sends == 0)
        end
    end)
    test("malformed bounds fail closed", function()
        for _, value in ipairs({ 0, -1, 1.5, math.huge, 0/0 }) do
            local f = fixture(); f.current.maximum = value; local _, result = f.core:run("1")
            assert(result == "bounds" and f.sends == 0)
        end
    end)
    test("unknown submission outcome blocks further sends", function()
        local f = fixture(); f.sendError = true; local _, result = f.core:run("2")
        assert(result == "uncertain" and f.core.uncertain and f.sends == 1)
        f.identity = {}; f.current = f:prompt(); assert(not f.core:run("2")); assert(f.sends == 1)
    end)
    test("a concurrent press cannot duplicate a request", function()
        local f = fixture(); f.onSend = function() local _, result = f.core:run("2"); assert(result == "busy") end
        assert(f.core:run("2")); assert(f.sends == 1)
    end)
    test("an opener error does not submit or create an automatic retry", function()
        local f = fixture(); f.current = nil; f.openError = true; local _, result = f.core:run("2")
        assert(result == "failed" and f.opens == 1 and f.sends == 0)
    end)
    test("missing character blocks even an already-open dialog", function()
        local f = fixture(); f.actor = nil; local _, result = f.core:run("2")
        assert(result == "character" and f.sends == 0)
    end)

    local function node(name, class, parent, props)
        local n = { Name = name, ClassName = class, Parent = parent, children = {} }
        if parent then table.insert(parent.children, n) end
        for key, value in pairs(props or {}) do n[key] = value end
        function n:IsA(kind) return self.ClassName == kind end
        function n:FindFirstChild(key) for _, item in ipairs(self.children) do if item.Name == key then return item end end end
        function n:GetChildren() return self.children end
        return n
    end
    local function promptFixture()
        local f = {}; f.root = node("PlayerGui", "PlayerGui")
        f.prompt = node("ChoicePrompt", "ScreenGui", f.root)
        local frame = node("ChoiceFrame", "Frame", f.prompt)
        f.title = node("Title", "TextLabel", frame, { Text = "Drop Notes" })
        local desc = node("DescSheet", "Frame", frame); local sheet = node("SliderSheet", "Frame", desc)
        local slider = node("GenericSlider", "Frame", sheet); local bar = node("Slider", "Frame", slider)
        f.markers = node("Markers", "Frame", bar)
        f.min = node("SliderMarker", "TextLabel", f.markers, { Text = "1" })
        f.max = node("SliderMarker", "TextLabel", f.markers, { Text = "544" })
        f.number = node("Number", "TextBox", slider)
        f.submit = node("Submit", "TextButton", node("Buttons", "Frame", sheet))
        f.choice = node("Choice", "RemoteFunction", f.prompt)
        local runtime = setmetatable({ playerGui = f.root, visible = function() return not f.hidden end,
            child = function(root, ...) for _, name in ipairs({...}) do root = root and root:FindFirstChild(name) end; return root end,
        }, { __index = getfenv() })
        local chunk = assert(loadstring(promptSource .. "\nreturn inspect")); setfenv(chunk, runtime); f.inspect = chunk()
        return f
    end
    test("observed prompt tree supplies its current range and Choice object", function()
        local f = promptFixture(); local p = f.inspect()
        assert(p.kind == "notes" and p.minimum == 1 and p.maximum == 544 and p.choice == f.choice and p.identity == f.prompt)
    end)
    test("a different title, hidden button, or malformed marker is not accepted", function()
        local f = promptFixture(); f.title.Text = "Sell Item"; assert(f.inspect().kind == "other")
        f = promptFixture(); f.hidden = true; assert(f.inspect().kind == "loading")
        f = promptFixture(); f.max.Text = "unknown"; assert(f.inspect().kind == "loading")
    end)
    test("learning observer forwards unchanged and only captures zero-argument events in the armed folder", function()
        local requests, remote, other = {}, {}, {}; remote.ClassName = "RemoteEvent"; remote.Parent = requests
        other.ClassName = "RemoteEvent"; other.Parent = requests
        local calls, hook, method = 0, nil, "FireServer"
        local state = { api = { closed = false }, learning = { deadline = os.clock()+4, requests = requests }, core = { used = {} }, game = {},
            getnamecallmethod = function() return method end, typeof = function(v) return (v == remote or v == other) and "Instance" or typeof(v) end,
            newcclosure = function(fn) return fn end,
            hookmetamethod = function(_, _, fn) hook=fn; return function(_, ...) calls += 1; return nil, select("#", ...) end end,
        }
        setmetatable(state, { __index = getfenv() }); local chunk = assert(loadstring(learnSource)); setfenv(chunk, state); chunk()
        local a, b = hook(remote, 123); assert(a == nil and b == 1 and state.learning.candidate == nil)
        hook(remote); assert(state.learning.candidate == remote and not state.learning.ambiguous)
        hook(other); assert(state.learning.ambiguous and calls == 3)
    end)
    print(tostring(passed) .. " notes-dropper tests passed")
end

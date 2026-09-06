return function(geometry, panelState, uiSource)
    local passed = 0
    local function test(name, fn) fn(); passed += 1; print("PASS notes UI " .. name) end
    local function near(a, b) assert(math.abs(a - b) < 0.001, tostring(a) .. " != " .. tostring(b)) end
    local function contained(g, w, h)
        assert(g.x >= 8 and g.y >= 8)
        assert(g.x + g.width <= w - 8.0 + 0.001 and g.y + g.height <= h - 8.0 + 0.001)
    end
    local prompt = { kind = "notes", minimum = 1, maximum = 544 }
    test("compact panel sits ten pixels above and right-aligns with Notes", function()
        local g = geometry(1920, 1080, 1760, 1000, 120, false, false)
        near(g.width, 244); near(g.height, 154); near(g.x + g.width, 1880); near(g.y + g.height, 990)
        contained(g, 1920, 1080)
    end)
    test("details and collapsed modes preserve the bottom anchor", function()
        for _, mode in ipairs({ { true, false, 224 }, { false, true, 38 }, { true, true, 38 } }) do
            local g = geometry(1920, 1080, 1760, 1000, 120, mode[1], mode[2])
            near(g.height, mode[3]); near(g.y + g.height, 990); near(g.x + g.width, 1880)
        end
    end)
    test("moving the actual Notes widget moves the panel by the same amount", function()
        local a = geometry(1920, 1080, 1700, 900, 120, false, false)
        local b = geometry(1920, 1080, 1730, 945, 120, false, false)
        near(b.x - a.x, 30); near(b.y - a.y, 45)
    end)
    test("near screen edges the panel remains inside the viewport", function()
        for _, point in ipairs({ { 0, 0 }, { 0, 1000 }, { 1920, 1080 }, { -100, -100 }, { 2200, 1300 } }) do
            contained(geometry(1920, 1080, point[1], point[2], 100, true, false), 1920, 1080)
        end
    end)
    test("small viewports scale the whole panel without clipping its controls", function()
        for _, size in ipairs({ { 320, 240 }, { 240, 180 }, { 160, 120 }, { 64, 64 } }) do
            local g = geometry(size[1], size[2], size[1] - 60, size[2] - 20, 60, true, false)
            contained(g, size[1], size[2]); near(g.width / g.height, 244 / 224)
            assert(g.scale > 0 and g.scale <= 1)
        end
    end)
    test("initial setup does not invent a balance or a live limit", function()
        local s = panelState("1", false, false, nil, false, "learn")
        assert(s.badge == "SETUP" and s.range == "LIMIT CHECKED WHEN OPENED")
    end)
    test("live range and valid amount display ready", function()
        local s = panelState("2", false, false, prompt, false, "ready")
        assert(s.badge == "READY" and s.enabled and s.range == "1 - 544  /  LIVE LIMIT")
    end)
    test("invalid total numbers disable the drop control", function()
        for _, raw in ipairs({ "", "0", "-1", "1.1", "1e2", "1000000001", "9999999999999" }) do
            assert(not panelState(raw, false, false, prompt, true, "ready").enabled)
        end
    end)
    test("live limits are removed when the dialog closes", function()
        assert(panelState("2", false, false, nil, true, "ready").range == "LIMIT CHECKED WHEN OPENED")
    end)
    test("busy and unknown-outcome states override earlier notices", function()
        local s = panelState("2", true, false, prompt, true, "sent")
        assert(not s.enabled and s.button == "WAIT" and s.badge == "WORKING")
        s = panelState("2", false, true, prompt, true, "ready")
        assert(not s.enabled and s.button == "LOCKED" and s.badge == "CHECK")
    end)
    test("request sent is not represented as confirmed delivery", function()
        local s = panelState("2", false, false, nil, true, "sent")
        assert(s.badge == "SENT" and s.short == "Request sent. Check the ground.")
    end)

    -- Minimal native UI fixture: verifies construction, event wiring and layout, not Roblox rendering.
    local function fixture(reduced)
        local f = { instances = {}, tweens = 0, collapses = 0 }
        local function signal()
            local s = { handlers = {} }
            function s:Connect(fn)
                local c = { connected = true }
                function c:Disconnect() self.connected = false end
                self.handlers[#self.handlers + 1] = { fn, c }; return c
            end
            function s:Fire(...)
                for _, h in ipairs(self.handlers) do if h[2].connected then h[1](...) end end
            end
            return s
        end
        local vector
        local vmt = { __add = function(a, b) return vector(a.X + b.X, a.Y + b.Y) end,
            __sub = function(a, b) return vector(a.X - b.X, a.Y - b.Y) end }
        vector = function(x, y) return setmetatable({ X = x, Y = y }, vmt) end
        local function dim2(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end
        local methods = {}
        function methods:GetPropertyChangedSignal(key)
            local sig = self._changed[key]
            if not sig then sig = signal(); self._changed[key] = sig end
            return sig
        end
        function methods:Destroy() self.destroyed = true end
        local mt = {
            __index = function(o, key) return methods[key] or o._props[key] end,
            __newindex = function(o, key, value)
                local changed = o._props[key] ~= value
                o._props[key] = value
                if changed and o._changed[key] then o._changed[key]:Fire() end
            end,
        }
        local function new(class)
            local o = setmetatable({ _props = { ClassName = class, Visible = true, Enabled = true,
                AbsoluteSize = vector(1920, 1044), AbsolutePosition = vector(0, 36) }, _changed = {} }, mt)
            for _, event in ipairs({ "Activated", "MouseEnter", "MouseLeave", "Focused", "FocusLost" }) do o[event] = signal() end
            f.instances[#f.instances + 1] = o; return o
        end
        local rgb = function(r, g, b) return string.format("%.6f/%.6f/%.6f", r, g, b) end
        local env = {
            Instance = { new = new }, Vector2 = { new = vector },
            UDim = { new = function(s, o) return { Scale = s, Offset = o } end },
            UDim2 = { new = dim2, fromOffset = function(x, y) return dim2(0, x, 0, y) end,
                fromScale = function(x, y) return dim2(x, 0, y, 0) end },
            Color3 = { new = rgb, fromRGB = function(r, g, b) return rgb(r / 255, g / 255, b / 255) end },
            ColorSequence = { new = function(a, b) return { a, b } end },
            TweenInfo = { new = function(...) return { ... } end },
            Enum = setmetatable({}, { __index = function(_, group)
                return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
            end }),
            notesPanelGeometry = geometry, notesPanelState = panelState,
        }
        env.game = { GetService = function(_, service)
            if service == "GuiService" then return { ReducedMotionEnabled = reduced } end
            assert(service == "TweenService", "UI must not access gameplay services")
            return { Create = function(_, object, _, props)
                f.tweens += 1
                return { Cancel = function() end, Play = function() for k, v in pairs(props) do object[k] = v end end }
            end }
        end }
        setmetatable(env, { __index = getfenv() })
        local factory = assert(loadstring(uiSource .. "\nreturn createNotesPanel"))
        setfenv(factory, env)
        f.ui = factory()({}, function() f.collapses += 1 end)
        function f:find(name)
            for _, o in ipairs(self.instances) do if o.Name == name then return o end end
            error("Missing " .. name)
        end
        function f:step(text)
            for _, o in ipairs(self.instances) do
                if o.Parent == self:find("AmountField") and o.ClassName == "TextButton" and o.Text == text then o.Activated:Fire(); return end
            end
            error("Missing step button")
        end
        f.notes = { AbsoluteSize = vector(120, 26), AbsolutePosition = vector(1760, 1000) }
        f.ui:refresh(prompt, true, { busy = false, uncertain = false })
        f.ui:layout(f.notes)
        return f
    end
    test("native panel builds and accounts for the screen's safe-area origin", function()
        local f = fixture(false)
        local dock = f:find("NotesDock")
        assert(dock.Visible and f.ui.amount.Text == "MAX" and f.ui.dropButton.Active)
        near(dock.Position.X.Offset, 1880); near(dock.Position.Y.Offset, 954)
        near(dock.Size.X.Offset, 244); near(dock.Size.Y.Offset, 154)
        assert(#f.ui.dropButton.Activated.handlers == 0, "UI factory must not wire gameplay")
    end)
    test("details toggle grows upward without moving the Notes-side edge", function()
        local f = fixture(false); local dock = f:find("NotesDock")
        local bottom = dock.Position.Y.Offset
        f:find("Details").Activated:Fire()
        assert(f.ui.expanded and f:find("DetailsBox").Visible)
        near(dock.Size.Y.Offset, 224); near(dock.Position.Y.Offset, bottom)
        f:find("Details").Activated:Fire()
        assert(not f.ui.expanded); near(dock.Size.Y.Offset, 154)
    end)
    test("collapse hides the body and invokes only the cancellation callback", function()
        local f = fixture(false)
        f:find("Collapse").Activated:Fire()
        assert(f.ui.collapsed and not f:find("Body").Visible and f.collapses == 1)
        near(f:find("NotesDock").Size.Y.Offset, 38)
        f:find("Collapse").Activated:Fire()
        assert(not f.ui.collapsed and f:find("Body").Visible and f.collapses == 1)
    end)
    test("errors reveal details even from the collapsed strip", function()
        local f = fixture(false); f:find("Collapse").Activated:Fire()
        f.ui:setNotice("uncertain", "Check your notes before continuing.")
        assert(f.ui.expanded and not f.ui.collapsed and f:find("DetailsBox").Visible and f:find("Body").Visible)
    end)
    test("plus and minus edit the number without submitting and stop while busy", function()
        local f = fixture(false)
        f:step("+"); assert(f.ui.amount.Text == "1")
        f:step("+"); assert(f.ui.amount.Text == "2")
        f:step("-"); f:step("-"); assert(f.ui.amount.Text == "1")
        f.ui:refresh(prompt, true, { busy = true, uncertain = false })
        f:step("+"); assert(f.ui.amount.Text == "1" and not f.ui.amount.TextEditable and not f.ui.dropButton.Active)
    end)
    test("amount validation and long-number sizing update immediately", function()
        local f = fixture(false); f.ui.amount.Text = "5000"; assert(f.ui.dropButton.Active)
        f.ui.amount.Text = "4"; assert(f.ui.dropButton.Active)
        f.ui.amount.Text = "1000000000"; assert(f.ui.amount.TextSize == 14)
    end)
    test("missing anchor hides the panel and a restored anchor shows it", function()
        local f = fixture(false); f.ui:layout(nil); assert(not f:find("NotesDock").Visible)
        f.ui:layout(f.notes); assert(f:find("NotesDock").Visible)
    end)
    test("reduced-motion preference avoids all tweens", function()
        local f = fixture(true); f:find("Details").Activated:Fire()
        assert(f.tweens == 0 and f:find("NotesDock").Size.Y.Offset == 224)
    end)
    test("destroy disconnects controls and removes the old panel", function()
        local f = fixture(false); f.ui:destroy()
        f:find("Collapse").Activated:Fire(); f:step("+")
        assert(f.ui.gui.destroyed and f.collapses == 0 and f.ui.amount.Text == "MAX")
    end)
    test("MAX accepts an uneven balance and remains available from the amount label", function()
        assert(panelState("MAX", false, false, prompt, true, "ready").enabled)
        local f = fixture(false); f.ui.amount.Text = "12"; f:find("Maximum").Activated:Fire()
        assert(f.ui.amount.Text == "MAX")
    end)
    test("auto locks manual actions but keeps Stop and the menu fallback visible", function()
        local f = fixture(false); f.ui:setAuto(true, "Auto ON for next join.")
        assert(f:find("AutoLoop").Text == "AUTO ON / STOP" and not f.ui.amount.TextEditable and not f.ui.dropButton.Active)
        f:step("+"); assert(f.ui.amount.Text == "MAX")
        f.ui.keepVisible = true; f.ui:layout(nil); assert(f:find("NotesDock").Visible)
        f.ui:setAuto(false, "Stopped"); assert(f:find("AutoLoop").Text == "AUTO OFF")
    end)
    print(tostring(passed) .. " notes UI tests passed")
end

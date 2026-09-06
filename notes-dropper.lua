-- CLAW notes dropper. Starts idle; automatic mode requires an explicit Start.
-- Learns the opener from a manual Notes click in this session; no remote-name guessing.
-- Does not use KeyHandler internals, fixed screen coordinates, or automatic retries.

-- DROPPER_CORE_BEGIN
local function newDropper(adapter)
    local core = { busy = false, uncertain = false, generation = 0, phase = "idle", used = setmetatable({}, { __mode = "k" }) }
    local function integer(value)
        return type(value) == "number" and value == value and value >= 1 and value <= 1000000000 and value % 1 == 0
    end
    function core:cancel() self.generation += 1 end
    function core:run(raw)
        if self.busy then return false, "busy" end
        if self.uncertain then return false, "uncertain" end
        local maximumMode = raw == "MAX"
        if not maximumMode and (type(raw) ~= "string" or #raw > 12 or not raw:match("^%s*%d+%s*$")) then return false, "amount" end
        local amount = maximumMode and nil or tonumber(raw)
        if not maximumMode and not integer(amount) then return false, "amount" end
        local actor = adapter.actor()
        if actor == nil then return false, "character" end
        self.busy, self.phase = true, "checking"
        self.generation += 1
        local generation = self.generation
        local ok, result = pcall(function()
            local prompt = adapter.inspect()
            if prompt and prompt.kind ~= "notes" then return "other-prompt" end
            if not prompt then
                if not adapter.canOpen() then return "learn" end
                self.phase = "opening"
                adapter.open() -- Exactly one opener call; never loop or guess another remote.
                local untilTime = adapter.now() + 5
                repeat
                    if generation ~= self.generation or adapter.actor() ~= actor then return "cancelled" end
                    prompt = adapter.inspect()
                    if prompt and prompt.kind == "notes" then break end
                    if prompt and prompt.kind == "other" then return "other-prompt" end
                    if adapter.now() >= untilTime then return "open-timeout" end
                    adapter.sleep(0.05)
                until false
            end
            if generation ~= self.generation or adapter.actor() ~= actor then return "cancelled" end
            -- Re-read the exact active dialog immediately before the irreversible call.
            local fresh = adapter.inspect()
            if not fresh or fresh.kind ~= "notes" or fresh.identity ~= prompt.identity or fresh.choice ~= prompt.choice then return "changed" end
            if maximumMode and fresh.maximum == 0 then return "empty" end
            if not integer(fresh.minimum) or not integer(fresh.maximum) or fresh.minimum > fresh.maximum then return "bounds" end
            if maximumMode then amount = math.min(1000, fresh.maximum) end
            if amount < fresh.minimum or amount > fresh.maximum then return "range" end
            if self.used[fresh.identity] then return "already-sent" end
            self.used[fresh.identity] = true -- Mark before yielding; an error is not permission to resend.
            self.phase = "submitting"
            self.lastAmount = amount
            adapter.submit(fresh.choice, amount)
            return "sent" -- A returned request is not proof the notes landed on the ground.
        end)
        if not ok and self.phase == "submitting" then self.uncertain = true end
        self.busy, self.phase = false, "idle"
        if not ok then return false, self.uncertain and "uncertain" or "failed" end
        return result == "sent", result
    end
    return core
end
-- DROPPER_CORE_END

-- DROPPER_AUTO_BEGIN
local function validNotesRun(r, now, context, phase)
    return type(r) == "table" and r.version == 1 and r.phase == phase
        and type(r.token) == "string" and #r.token >= 16 and #r.token <= 80
        and type(r.jobId) == "string" and #r.jobId > 0 and #r.jobId <= 160
        and type(r.slot) == "string" and #r.slot > 0 and #r.slot <= 32 and r.slot:match("^[%w_-]+$") ~= nil
        and type(r.cycles) == "number" and r.cycles >= 0 and r.cycles < 100 and r.cycles % 1 == 0
        and type(r.expires) == "number" and r.expires > now and r.expires <= now + 1800
        and r.accountId == context.accountId and r.gameId == context.gameId
        and (r.worldPlaceId == 6473861193 or r.worldPlaceId == 6032399813)
        and (phase == "menu" and context.placeId == 4111023553
            or phase == "world" and context.placeId == r.worldPlaceId and context.jobId == r.jobId and context.slot == r.slot)
        and (r.expectedBalance == nil or type(r.expectedBalance) == "number" and r.expectedBalance >= 0
            and r.expectedBalance <= 1000000000 and r.expectedBalance % 1 == 0)
end
local function newNotesLoop(adapter)
    local loop = { active = false, generation = 0, state = "idle" }
    function loop:stop(reason)
        self.active = false; self.generation += 1; self.state = reason or "stopped"
        if self.unconfirmed then adapter.uncertain(); self.unconfirmed = false end
        adapter.cancel(); adapter.clear(); adapter.status(self.state)
    end
    function loop:run(record)
        if self.active then return false, "busy" end
        if not validNotesRun(record, adapter.now(), adapter.context(), "world") then return false, "wrong-session" end
        self.active = true; self.generation += 1
        local generation = self.generation
        local function live()
            return self.active and self.generation == generation
                and validNotesRun(record, adapter.now(), adapter.context(), "world")
        end
        local function hold(reason) self:stop(reason); return false, reason end
        local ok, success, reason = pcall(function()
            local ready, problem = adapter.preflight()
            if not ready then return hold(problem or "not-ready") end
            local before, identity = adapter.balance()
            if type(before) ~= "number" or before < 0 or before > 1000000000 or before % 1 ~= 0 or not identity then return hold("balance-unavailable") end
            if record.expectedBalance ~= nil and before ~= record.expectedBalance then return hold("balance-changed-on-rejoin") end
            if before == 0 then return hold("empty") end
            if not live() then return hold("cancelled") end
            self.state = "dropping"; adapter.status(self.state)
            local sent, result, amount = adapter.drop()
            if not sent then return hold(result or "drop-failed") end
            self.unconfirmed = true
            if type(amount) ~= "number" or amount < 1 or amount > math.min(1000, before) or amount % 1 ~= 0 then return hold("outcome-unknown") end
            self.state = "confirming"; adapter.status(self.state)
            local deadline, after = adapter.now() + 10, nil
            repeat
                if not live() then return hold("cancelled") end
                local count, source = adapter.balance()
                if source ~= nil and source ~= identity then return hold("balance-source-changed") end
                if count == before - amount then after = count; break end
                if count ~= nil and count ~= before then return hold("outcome-unknown") end
                if adapter.now() >= deadline then return hold("outcome-unknown") end
                adapter.sleep(0.1)
            until false
            self.unconfirmed = false
            record.cycles += 1
            if after == 0 then self:stop("empty"); return true, "empty" end
            if record.cycles >= 100 then self:stop("cycle-limit"); return true, "cycle-limit" end
            self.state = "countdown"; adapter.status(self.state)
            local rejoinAt = adapter.now() + 3
            while adapter.now() < rejoinAt do if not live() then return hold("cancelled") end; adapter.sleep(0.1) end
            if not live() then return hold("cancelled") end
            local currentBalance, source = adapter.balance()
            if source ~= identity or currentBalance ~= after then return hold("balance-changed") end
            local nextRun = table.clone(record); nextRun.expectedBalance, nextRun.phase = after, "menu"
            self.state = "rejoining"; adapter.status(self.state)
            if not adapter.depart(nextRun, live) then return hold("rejoin-failed") end
            return true, "rejoining"
        end)
        if not ok then return hold("automation-error") end
        return success, reason
    end
    return loop
end
-- DROPPER_AUTO_END

-- DROPPER_RUNTIME_BEGIN
local function newNotesRuntime(env, core, ui, player, playerGui, child, visible)
    local Http, Teleport = game:GetService("HttpService"), game:GetService("TeleportService")
    local Replicated = game:GetService("ReplicatedStorage")
    local setting = "CLAW_NOTES_AUTO_" .. tostring(player.UserId)
    local loader = "https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"
    local queue = queue_on_teleport or queueonteleport or queueteleport
    local key = env.CLAW_NOTES_EXECUTION_KEY or env.script_key or script_key
    local runtime = { loop = nil, menuActive = false, message = nil, closed = false }
    local texts = {
        dropping = "Dropping the allowed maximum...", confirming = "Checking the balance change...",
        countdown = "Rejoining in 3s. STOP cancels.", rejoining = "Returning through the game menu...",
        empty = "No notes left. Auto stopped.", ["cycle-limit"] = "100 drops reached. Auto stopped.",
        ["balance-unavailable"] = "Cannot read your notes balance. Auto stopped.",
        ["outcome-unknown"] = "Balance did not confirm the drop. Auto stopped.",
        ["balance-source-changed"] = "Notes display changed. Auto stopped.",
        ["balance-changed-on-rejoin"] = "Balance differs after rejoin. Auto stopped.",
        ["balance-changed"] = "Balance changed before leaving. Auto stopped.",
        ["rejoin-failed"] = "Rejoin failed. Auto stopped; no retry.",
        cancelled = "Auto stopped.", stopped = "Auto stopped.",
        ["automation-error"] = "Auto error. No automatic retry.",
    }
    local function context()
        local slot = player:GetAttribute("DataSlot")
        return { accountId = player.UserId, gameId = game.GameId, placeId = game.PlaceId,
            jobId = game.JobId, slot = slot ~= nil and tostring(slot) or nil }
    end
    local function clear()
        local ok = pcall(function()
            Teleport:SetTeleportSetting(setting, "")
            assert(Teleport:GetTeleportSetting(setting) == "")
        end)
        if not ok then warn("[CLAW] Could not verify clearing resume state. Close this game client to cancel any queued continuation.") end
    end
    local function status(code)
        runtime.message = texts[code] or code
        ui:setAuto(runtime.menuActive or runtime.loop and runtime.loop.active, runtime.message)
        if code ~= "dropping" and code ~= "confirming" and code ~= "countdown" and code ~= "rejoining" then
            ui:setNotice((code == "empty" or code == "stopped" or code == "cancelled") and "ready" or code, runtime.message)
        end
    end
    local function remote(name, menu)
        local root = Replicated:FindFirstChild("Requests")
        if menu then root = root and root:FindFirstChild("StartMenu") end
        local r = root and root:FindFirstChild(name)
        return r and r:IsA("RemoteEvent") and r or nil
    end
    local function balance()
        -- Read only the Notes button's own numeric display; never confuse Knowledge/other currencies.
        local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
        if not notes then return nil end
        local found, identity
        local objects = notes:GetDescendants(); table.insert(objects, 1, notes)
        for _, item in ipairs(objects) do
            if (item:IsA("TextLabel") or item:IsA("TextButton")) and visible(item) then
                local raw = item.Text:match("^%s*(.-)%s*$")
                local plain = raw:match("^%d+$") ~= nil
                local grouped = raw:match("^%d%d?%d?,%d%d%d") ~= nil
                if grouped then
                    local tail = raw:match("^%d+,(.*)$")
                    grouped = tail ~= nil and tail:gsub("%d%d%d,", ""):match("^%d%d%d$") ~= nil
                end
                if #raw <= 16 and (plain or grouped) then
                    local normalized = raw:gsub(",", "")
                    local n = tonumber(normalized)
                    if n and n >= 0 and n <= 1000000000 and n % 1 == 0 then
                        if identity and (found ~= n or identity ~= item) then return nil end
                        found, identity = n, item
                    end
                end
            end
        end
        return found, identity
    end
    local function arm(record)
        assert(type(queue) == "function", "Teleport queue unavailable")
        assert(type(key) == "string" and #key == 32 and key:match("^[%w]+$"), "Use the notes auto-ready loader")
        local nextRun = table.clone(record); nextRun.token = Http:GenerateGUID(false)
        local raw = Http:JSONEncode(nextRun)
        Teleport:SetTeleportSetting(setting, raw)
        assert(Teleport:GetTeleportSetting(setting) == raw, "Cannot verify resume state")
        -- A stale queued entry is harmless after Stop: it must match the current one-use token.
        local code = string.format([[
local ok = pcall(function()
    local t, h, p = game:GetService("TeleportService"), game:GetService("HttpService"), game:GetService("Players")
    local deadline = os.clock() + 120
    repeat task.wait(0.1) until p.LocalPlayer or os.clock() >= deadline
    if not p.LocalPlayer then return end
    local raw = t:GetTeleportSetting(%q)
    if type(raw) ~= "string" or #raw > 4096 then return end
    local r = h:JSONDecode(raw)
    if type(r) ~= "table" or r.version ~= 1 or r.token ~= %q or r.accountId ~= p.LocalPlayer.UserId or r.gameId ~= game.GameId then return end
    if type(r.expires) ~= "number" or not (r.expires > os.time() and r.expires <= os.time() + 1800) then return end
    if r.phase ~= "menu" and r.phase ~= "world" then return end
    t:SetTeleportSetting(%q, "")
    if r.phase == "menu" and game.PlaceId ~= 4111023553 then return end
    if r.phase == "world" and (game.PlaceId ~= r.worldPlaceId or game.JobId ~= r.jobId) then return end
    getgenv().CLAW_NOTES_RESUME = r
    getgenv().CLAW_NOTES_EXECUTION_KEY = %q
    script_key = getgenv().CLAW_NOTES_EXECUTION_KEY
    loadstring(game:HttpGet(%q))()
end)
if not ok then warn("[CLAW] Notes resume stopped; no automatic retry.") end
]], setting, nextRun.token, setting, key, loader)
        queue(code)
    end
    local travelling = false
    local teleportConnection = player.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then travelling = true end
    end)
    local failedConnection = Teleport.TeleportInitFailed:Connect(function(who)
        if who == player and (runtime.menuActive or runtime.loop and runtime.loop.active) then runtime:stop("rejoin-failed") end
    end)
    local function waitFor(check, seconds, live)
        local untilTime = os.clock() + seconds
        repeat
            if not live() then return nil end
            local value = check(); if value then return value end
            task.wait(0.1)
        until os.clock() >= untilTime
        return nil
    end
    runtime.loop = newNotesLoop({ now = os.time, context = context, sleep = task.wait, balance = balance,
        cancel = function() core:cancel() end, clear = clear, status = status,
        uncertain = function() core.uncertain = true end,
        preflight = function()
            if core.uncertain or core.busy then return false, "Check the pending drop before starting Auto. Rejoin if uncertain." end
            if env.CLAW_CONTROL or env.CLAW_RELAY then return false, "Stop the manager/bringer on this alt before standalone Auto." end
            if type(queue) ~= "function" then return false, "Your executor has no teleport queue." end
            if type(key) ~= "string" or #key ~= 32 or not key:match("^[%w]+$") then return false, "Use the auto-ready notes loadstring so rejoin can authenticate." end
            if not remote("ReturnToMenu") then return false, "The normal Return to Menu request is unavailable." end
            return true
        end,
        drop = function()
            local ok, result = core:run("MAX"); return ok, result, core.lastAmount
        end,
        depart = function(record, live)
            local request = remote("ReturnToMenu")
            if not request or not live() then return false end
            arm(record); travelling = false
            if not live() then clear(); return false end
            request:FireServer()
            local prompt = waitFor(function()
                if travelling then return "travelling" end
                local p = playerGui:FindFirstChild("ChoicePrompt")
                if not p then return nil end
                local title = child(p, "ChoiceFrame", "Title")
                if p:GetAttribute("Title") ~= "Return to Main Menu" and (not title or title.Text ~= "Return to Main Menu") then return nil end
                local choice = p:FindFirstChild("Choice")
                return choice and choice:IsA("RemoteEvent") and choice or nil
            end, 10, live)
            if not prompt then clear(); return false end
            if prompt ~= "travelling" then
                if not live() then clear(); return false end
                prompt:FireServer(true)
            end
            if not waitFor(function() return travelling end, 15, live) then clear(); return false end
            -- If the old client is still here after a minute, the trip did not finish.
            task.delay(60, function() if not runtime.closed and runtime.loop.active then runtime:stop("rejoin-failed") end end)
            return true
        end,
    })
    function runtime:stop(reason)
        self.menuActive = false; self.loop:stop(reason or "stopped"); clear()
    end
    function runtime:destroy()
        self:stop(); self.closed = true; teleportConnection:Disconnect(); failedConnection:Disconnect()
    end
    function runtime:start()
        if self.loop.active or self.menuActive then self:stop(); return end
        ui.keepVisible = true
        local c = context()
        local record = { version = 1, phase = "world", token = Http:GenerateGUID(false), accountId = c.accountId,
            gameId = c.gameId, worldPlaceId = c.placeId, jobId = c.jobId, slot = c.slot, expires = os.time() + 1800, cycles = 0 }
        local ok, problem = self.loop:run(record)
        if not ok and problem == "wrong-session" then status("Join the world and load your character before Auto.") end
    end
    function runtime:resume(record)
        if type(record) ~= "table" then self:stop("rejoin-failed"); return end
        ui.keepVisible = true
        if record.phase == "menu" then
            if not validNotesRun(record, os.time(), context(), "menu") then status("Expired or wrong-account resume. Auto stopped."); return end
            self.menuActive = true; status("Returning to the same slot and server...")
            local function live() return self.menuActive and not self.closed and validNotesRun(record, os.time(), context(), "menu") end
            local shown = false
            local show = waitFor(function() return remote("ShowServers") end, 45, live)
            local pick = remote("PickSlot", true)
            if not show or not pick then self:stop("rejoin-failed"); return end
            local observed = show.OnClientEvent:Connect(function(realm) if type(realm) == "string" and realm ~= "" then shown = true end end)
            pick:FireServer(record.slot)
            local ready = waitFor(function() return shown end, 30, live); observed:Disconnect()
            local join = remote("PickServer", true)
            if not ready or not join or not live() then self:stop("rejoin-failed"); return end
            local nextRun = table.clone(record); nextRun.phase = "world"; arm(nextRun)
            if not live() then clear(); return end
            travelling = false; join:FireServer(record.jobId)
            if not waitFor(function() return travelling end, 30, live) then self:stop("rejoin-failed"); return end
            task.delay(60, function() if self.menuActive and not self.closed then self:stop("rejoin-failed") end end)
        elseif record.phase == "world" then
            self.menuActive = true; status("Waiting for the same character to load...")
            local ready = waitFor(function()
                return player.Character and validNotesRun(record, os.time(), context(), "world") and child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
            end, 90, function() return self.menuActive and not self.closed and os.time() < record.expires end)
            if not ready then self:stop("rejoin-failed"); return end
            self.menuActive = false; self.loop:run(record)
        else self:stop("rejoin-failed")
        end
    end
    runtime.balance = balance
    return runtime
end
-- DROPPER_RUNTIME_END

-- DROPPER_VIEW_BEGIN
local function notesPanelGeometry(viewWidth, viewHeight, noteX, noteY, noteWidth, expanded, collapsed)
    local width, height, margin, gap = 244, collapsed and 38 or expanded and 224 or 154, 8, 10
    local scale = math.min(1, math.max(1, viewWidth - margin * 2) / width, math.max(1, viewHeight - margin * 2) / height)
    local w, h = width * scale, height * scale
    local x = math.clamp(noteX + noteWidth - w, margin, math.max(margin, viewWidth - margin - w))
    local y = math.clamp(noteY - gap - h, margin, math.max(margin, viewHeight - margin - h))
    return { x = x, y = y, width = w, height = h, scale = scale, baseHeight = height }
end
local function notesPanelState(raw, busy, uncertain, prompt, canOpen, notice)
    local maximumMode = raw == "MAX"
    local number = type(raw) == "string" and #raw <= 12 and raw:match("^%s*%d+%s*$") and tonumber(raw) or nil
    local valid = maximumMode or number ~= nil and number >= 1 and number <= 1000000000 and number % 1 == 0
    local live = prompt and prompt.kind == "notes" and type(prompt.minimum) == "number" and type(prompt.maximum) == "number"
    local inRange = not live or maximumMode and prompt.maximum >= prompt.minimum and prompt.maximum > 0
        or (not maximumMode and valid and number >= prompt.minimum and number <= prompt.maximum)
    local state = { badge = canOpen and "READY" or "SETUP", tone = canOpen and "ready" or "warm",
        button = "DROP", sub = "once", enabled = valid and inRange and not busy and not uncertain,
        range = live and (tostring(prompt.minimum) .. " - " .. tostring(prompt.maximum) .. "  /  LIVE LIMIT") or "LIMIT CHECKED WHEN OPENED",
        short = canOpen and "One drop. Only when you choose." or "Click Notes once to connect." }
    if live then state.badge, state.tone = "READY", "ready" end
    if notice == "sent" then state.badge, state.tone, state.short = "SENT", "warm", "Request sent. Check the ground."
    elseif notice and notice ~= "learn" and notice ~= "ready" and notice ~= "working" then
        state.badge, state.tone, state.short = "CHECK", "error", "Action stopped. See details."
    end
    if not valid then state.short = "Enter a positive whole number."
    elseif not inRange then state.short = "Amount exceeds the live limits." end
    if busy then state.badge, state.tone, state.button, state.sub, state.short = "WORKING", "warm", "WAIT", "one request", "Waiting on the game. No retry."
    elseif uncertain then state.badge, state.tone, state.button, state.sub, state.short = "CHECK", "error", "LOCKED", "check notes", "Outcome unknown. See details." end
    return state
end
-- DROPPER_VIEW_END

-- DROPPER_UI_BEGIN
local function createNotesPanel(playerGui, onCollapse)
    local Tween = game:GetService("TweenService")
    local GuiService = game:GetService("GuiService")
    local palette = {
        panel = Color3.fromRGB(19, 22, 28), line = Color3.fromRGB(65, 62, 57),
        ink = Color3.fromRGB(240, 233, 220), muted = Color3.fromRGB(143, 147, 155),
        gold = Color3.fromRGB(222, 189, 131), bright = Color3.fromRGB(241, 213, 164),
        ready = Color3.fromRGB(143, 198, 169), warm = Color3.fromRGB(222, 189, 131), error = Color3.fromRGB(232, 150, 143),
    }
    local ui = { expanded = false, collapsed = false, hovered = false, notice = "learn", connections = {}, tweens = {} }
    local reducedOK, reduced = pcall(function() return GuiService.ReducedMotionEnabled end)
    local function make(class, parent, props)
        local object = Instance.new(class)
        for key, value in pairs(props or {}) do object[key] = value end
        object.Parent = parent
        return object
    end
    local function round(parent, radius) return make("UICorner", parent, { CornerRadius = UDim.new(0, radius) }) end
    local function stroke(parent, color, transparency)
        return make("UIStroke", parent, { Color = color, Transparency = transparency or 0, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    end
    local function label(parent, text, x, y, w, h, size, color, font)
        return make("TextLabel", parent, { BackgroundTransparency = 1, Text = text, Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(w, h), TextSize = size, TextColor3 = color or palette.ink,
            Font = font or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0 })
    end
    local function animate(object, props)
        if ui.tweens[object] then ui.tweens[object]:Cancel() end
        if reducedOK and reduced then for key, value in pairs(props) do object[key] = value end; return end
        local tween = Tween:Create(object, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
        ui.tweens[object] = tween; tween:Play()
    end
    local function listen(signal, fn) ui.connections[#ui.connections + 1] = signal:Connect(fn) end
    ui.gui = make("ScreenGui", playerGui, { Name = "CLAWNotesDropper", ResetOnSpawn = false, DisplayOrder = 10001, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
    local canvas = make("Frame", ui.gui, { Name = "Canvas", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 })
    local dock = make("Frame", canvas, { Name = "NotesDock", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(244, 154), BackgroundTransparency = 1, Visible = false })
    local scale = make("UIScale", dock, { Scale = 1 })
    for _, shadow in ipairs({ { 7, 7, 0.94 }, { 3, 4, 0.8 } }) do
        local s = make("Frame", dock, { Name = "Shadow", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = shadow[3], BorderSizePixel = 0,
            Position = UDim2.fromOffset(-shadow[1], shadow[2] - shadow[1]), Size = UDim2.new(1, shadow[1] * 2, 1, shadow[1] * 2), ZIndex = 1 })
        round(s, 16)
    end
    local surface = make("Frame", dock, { Name = "Surface", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 })
    round(surface, 12); stroke(surface, palette.line, 0.12)
    make("UIGradient", surface, { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(30, 32, 39), palette.panel) })
    local mark = make("Frame", surface, { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromRGB(61, 53, 39), BorderSizePixel = 0 })
    round(mark, 5); stroke(mark, palette.gold, 0.6)
    local markText = label(mark, "N", 0, 0, 18, 18, 10, palette.gold, Enum.Font.GothamBold); markText.TextXAlignment = Enum.TextXAlignment.Center
    label(surface, "CLAW", 37, 11, 43, 16, 11, palette.ink, Enum.Font.GothamBold)
    label(surface, "notes", 82, 11, 36, 16, 10, palette.muted)
    local badge = make("Frame", surface, { Position = UDim2.fromOffset(121, 11), Size = UDim2.fromOffset(62, 16), BackgroundColor3 = Color3.fromRGB(38, 38, 35), BorderSizePixel = 0 })
    round(badge, 8)
    local dot = make("Frame", badge, { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = palette.gold, BorderSizePixel = 0 }); round(dot, 3)
    local badgeText = label(badge, "SETUP", 14, 0, 46, 16, 8, palette.gold, Enum.Font.GothamBold)
    local function icon(text, x)
        local b = make("TextButton", surface, { Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = palette.muted,
            BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(53, 53, 59), AutoButtonColor = false, BorderSizePixel = 0,
            Position = UDim2.fromOffset(x, 7), Size = UDim2.fromOffset(24, 24) })
        round(b, 6)
        listen(b.MouseEnter, function() animate(b, { BackgroundTransparency = 0.2, TextColor3 = palette.ink }) end)
        listen(b.MouseLeave, function() animate(b, { BackgroundTransparency = 1, TextColor3 = palette.muted }) end)
        return b
    end
    local infoButton, collapseButton = icon("i", 187), icon("-", 213)
    infoButton.Name, collapseButton.Name = "Details", "Collapse"
    local body = make("Frame", surface, { Name = "Body", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundTransparency = 1 })
    local field = make("Frame", body, { Name = "AmountField", Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(116, 56), BackgroundColor3 = Color3.fromRGB(12, 15, 20), BorderSizePixel = 0 })
    round(field, 8); local fieldStroke = stroke(field, Color3.fromRGB(52, 55, 64), 0.25)
    local maxButton = make("TextButton", field, { Name = "Maximum", Text = "AMOUNT / MAX", Font = Enum.Font.GothamMedium,
        TextSize = 8, TextColor3 = palette.muted, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 3), Size = UDim2.fromOffset(77, 17) })
    listen(maxButton.Activated, function()
        if not ui.autoActive and not (ui.model and ui.model.busy) then ui.amount.Text = "MAX" end
    end)
    ui.amount = make("TextBox", field, { Name = "Amount", Text = "1", PlaceholderText = "1", ClearTextOnFocus = false,
        Position = UDim2.fromOffset(10, 20), Size = UDim2.fromOffset(78, 29), BackgroundTransparency = 1,
        TextColor3 = palette.ink, PlaceholderColor3 = palette.muted, Font = Enum.Font.GothamBold, TextSize = 22,
        TextXAlignment = Enum.TextXAlignment.Left, MultiLine = false })
    local function step(text, y, delta)
        local b = make("TextButton", field, { Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = palette.muted,
            BackgroundTransparency = 1, AutoButtonColor = false, Position = UDim2.fromOffset(91, y), Size = UDim2.fromOffset(18, 21) })
        listen(b.Activated, function()
            if ui.autoActive or ui.model and ui.model.busy then return end
            local n = tonumber(ui.amount.Text)
            if ui.amount.Text == "MAX" then ui.amount.Text = "1"
            elseif n and n % 1 == 0 then ui.amount.Text = tostring(math.clamp(n + delta, 1, 1000000000)) end
        end)
        listen(b.MouseEnter, function() b.TextColor3 = palette.gold end)
        listen(b.MouseLeave, function() b.TextColor3 = palette.muted end)
        return b
    end
    step("+", 7, 1); step("-", 29, -1)
    ui.amount.Text = "MAX"
    ui.dropButton = make("TextButton", body, { Name = "DropOnce", Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        Position = UDim2.fromOffset(138, 4), Size = UDim2.fromOffset(94, 56), BackgroundColor3 = palette.gold })
    round(ui.dropButton, 8); stroke(ui.dropButton, palette.bright, 0.65)
    make("UIGradient", ui.dropButton, { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 183, 161)) })
    local actionTitle = label(ui.dropButton, "DROP", 0, 11, 94, 19, 14, Color3.fromRGB(30, 28, 25), Enum.Font.GothamBold)
    local actionSub = label(ui.dropButton, "once", 0, 31, 94, 12, 9, Color3.fromRGB(76, 65, 48))
    actionTitle.TextXAlignment, actionSub.TextXAlignment = Enum.TextXAlignment.Center, Enum.TextXAlignment.Center
    ui.autoButton = make("TextButton", body, { Name = "AutoLoop", Text = "START AUTO", Font = Enum.Font.GothamBold,
        TextSize = 9, TextColor3 = palette.gold, BackgroundTransparency = 1, AutoButtonColor = false,
        Position = UDim2.fromOffset(132, 65), Size = UDim2.fromOffset(100, 16) })
    local rangeText = label(body, "MAX 1000 / DROP", 12, 67, 118, 12, 7, palette.muted, Enum.Font.GothamMedium)
    make("Frame", body, { Position = UDim2.fromOffset(12, 85), Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = Color3.fromRGB(53, 54, 60), BackgroundTransparency = 0.5, BorderSizePixel = 0 })
    local status = label(body, "Click Notes once to connect.", 12, 93, 220, 14, 10, palette.muted)
    status.TextTruncate = Enum.TextTruncate.AtEnd
    local detailsBox = make("Frame", body, { Name = "DetailsBox", Position = UDim2.fromOffset(12, 114), Size = UDim2.fromOffset(220, 60), BackgroundColor3 = Color3.fromRGB(13, 16, 21), BorderSizePixel = 0, Visible = false })
    round(detailsBox, 7)
    local details = label(detailsBox, "", 8, 5, 204, 52, 11, Color3.fromRGB(181, 185, 193))
    details.TextWrapped, details.TextYAlignment = true, Enum.TextYAlignment.Top
    function ui:layout(notes)
        self.anchor = notes
        if not notes and self.keepVisible then
            notes = { AbsoluteSize = Vector2.new(1, 1), AbsolutePosition = canvas.AbsolutePosition + canvas.AbsoluteSize - Vector2.new(18, 18) }
        end
        if not notes or notes.AbsoluteSize.X <= 0 or canvas.AbsoluteSize.X <= 16 or canvas.AbsoluteSize.Y <= 16 then dock.Visible = false; return end
        local origin, size, location = canvas.AbsolutePosition, canvas.AbsoluteSize, notes.AbsolutePosition
        local geometry = notesPanelGeometry(size.X, size.Y, location.X - origin.X, location.Y - origin.Y, notes.AbsoluteSize.X, self.expanded, self.collapsed)
        scale.Scale = geometry.scale
        dock.Position = UDim2.fromOffset(geometry.x + geometry.width, geometry.y + geometry.height)
        if self.targetHeight ~= geometry.baseHeight then
            self.targetHeight = geometry.baseHeight
            animate(dock, { Size = UDim2.fromOffset(244, geometry.baseHeight) })
        end
        dock.Visible = true
    end
    function ui:render()
        if not self.model then return end
        local m = self.model
        local state = notesPanelState(self.amount.Text, m.busy, m.uncertain, m.prompt, m.canOpen, self.notice)
        badgeText.Text, badgeText.TextColor3, dot.BackgroundColor3 = state.badge, palette[state.tone], palette[state.tone]
        status.Text, status.TextColor3 = state.short, state.tone == "error" and palette.error or palette.muted
        actionTitle.Text, actionSub.Text = state.button, state.sub
        rangeText.Text = m.prompt and m.prompt.kind == "notes" and ("UP TO " .. tostring(math.min(1000, m.prompt.maximum)) .. " NOTES") or "MAX 1000 / DROP"
        self.dropButton.Active = state.enabled and not self.autoActive
        self.amount.TextEditable = not m.busy and not self.autoActive
        self.amount.TextSize = #self.amount.Text > 8 and 14 or #self.amount.Text > 6 and 17 or 22
        local color = self.dropButton.Active and (self.hovered and palette.bright or palette.gold) or Color3.fromRGB(68, 60, 49)
        if color ~= self.buttonColor then self.buttonColor = color; animate(self.dropButton, { BackgroundColor3 = color }) end
        actionTitle.TextColor3 = state.enabled and Color3.fromRGB(30, 28, 25) or Color3.fromRGB(182, 169, 147)
        actionSub.TextColor3 = state.enabled and Color3.fromRGB(76, 65, 48) or Color3.fromRGB(156, 145, 126)
    end
    function ui:refresh(prompt, canOpen, core)
        self.model = { prompt = prompt, canOpen = canOpen, busy = core.busy, uncertain = core.uncertain }
        self:render()
    end
    function ui:setAuto(active, text)
        self.autoActive = active
        self.autoButton.Text = active and "STOP AUTO" or "START AUTO"
        self.autoButton.TextColor3 = active and palette.error or palette.gold
        self:render()
        if text then status.Text, details.Text = text, text end
        if active then badgeText.Text, badgeText.TextColor3 = "AUTO", palette.warm end
    end
    function ui:setNotice(code, text)
        self.notice, details.Text = code, text
        if code ~= "learn" and code ~= "ready" and code ~= "working" and code ~= "sent" then
            self.expanded, self.collapsed = true, false
            body.Visible, collapseButton.Text = true, "-"
        end
        detailsBox.Visible = self.expanded and not self.collapsed
        self:render(); self:layout(self.anchor)
    end
    function ui:destroy()
        for _, c in ipairs(self.connections) do c:Disconnect() end
        for _, tween in pairs(self.tweens) do tween:Cancel() end
        self.gui:Destroy()
    end
    listen(infoButton.Activated, function()
        ui.expanded, ui.collapsed = not ui.expanded, false
        body.Visible, detailsBox.Visible, collapseButton.Text = true, ui.expanded, "-"
        ui:layout(ui.anchor)
    end)
    listen(collapseButton.Activated, function()
        ui.collapsed = not ui.collapsed
        if ui.collapsed then onCollapse() end
        body.Visible, collapseButton.Text = not ui.collapsed, ui.collapsed and "+" or "-"
        detailsBox.Visible = ui.expanded and not ui.collapsed
        ui:layout(ui.anchor)
    end)
    listen(ui.amount.Focused, function() animate(fieldStroke, { Color = palette.gold, Transparency = 0.15 }) end)
    listen(ui.amount.FocusLost, function() animate(fieldStroke, { Color = Color3.fromRGB(52, 55, 64), Transparency = 0.25 }) end)
    listen(ui.amount:GetPropertyChangedSignal("Text"), function() ui:render() end)
    listen(ui.dropButton.MouseEnter, function() ui.hovered = true; ui:render() end)
    listen(ui.dropButton.MouseLeave, function() ui.hovered = false; ui:render() end)
    return ui
end
-- DROPPER_UI_END

local env = getgenv()
local resume = env.CLAW_NOTES_RESUME; env.CLAW_NOTES_RESUME = nil
local inheritedUsed
if env.CLAW_NOTES_DROPPER then
    local old = env.CLAW_NOTES_DROPPER
    if old.uiVersion == 3 and not old.closed then old:show(); return end
    if old.core and (old.core.busy or old.core.uncertain) then
        old:show(); warn("[CLAW] Finish/check the pending drop before changing the UI. Rejoin if its outcome is unknown."); return
    end
    assert(type(old.destroy) == "function", "Rejoin before loading the new notes UI")
    inheritedUsed = old.core and old.core.used
    old:destroy()
end
local Players, Replicated = game:GetService("Players"), game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Join the game before opening the notes dropper")
local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
assert(playerGui, "Wait for the game UI")
local api = { uiVersion = 3, closed = false, hookReady = false }
local connections, observedButtons = {}, setmetatable({}, { __mode = "k" })
local learning, learned, currentChoice, currentPrompt
local function child(root, ...)
    for _, name in ipairs({ ... }) do root = root and root:FindFirstChild(name) end
    return root
end
local function visible(object)
    local current = object
    for _ = 1, 16 do
        if not current then return false end
        if current == playerGui then return true end
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return false
end
-- DROPPER_PROMPT_BEGIN
local function inspect()
    currentPrompt, currentChoice = nil, nil
    local prompt = playerGui:FindFirstChild("ChoicePrompt")
    if not prompt then currentPrompt, currentChoice = nil, nil; return nil end
    local frame = child(prompt, "ChoiceFrame")
    local title = child(frame, "Title")
    if not title or not title:IsA("TextLabel") then return { kind = "loading", identity = prompt } end
    if title.Text:match("^%s*(.-)%s*$") ~= "Drop Notes" then return { kind = "other", identity = prompt } end
    local slider = child(frame, "DescSheet", "SliderSheet", "GenericSlider")
    local markers = child(slider, "Slider", "Markers")
    local number = child(slider, "Number")
    local submit = child(frame, "DescSheet", "SliderSheet", "Buttons", "Submit")
    local choice = child(prompt, "Choice")
    if not slider or not markers or not number or not number:IsA("TextBox") or not submit or not submit:IsA("TextButton")
        or not choice or not choice:IsA("RemoteFunction") or not visible(submit) then return { kind = "loading", identity = prompt } end
    local minimum, maximum, count = nil, nil, 0
    for _, marker in ipairs(markers:GetChildren()) do
        if marker:IsA("TextLabel") and marker.Name == "SliderMarker" then
            local text = marker.Text
            if #text > 12 or not text:match("^%s*%d+%s*$") then return { kind = "loading", identity = prompt } end
            local value = tonumber(text)
            count += 1; minimum = minimum and math.min(minimum, value) or value; maximum = maximum and math.max(maximum, value) or value
        end
    end
    if count < 2 then return { kind = "loading", identity = prompt } end
    currentPrompt, currentChoice = prompt, choice
    return { kind = "notes", identity = prompt, choice = choice, minimum = minimum, maximum = maximum }
end
-- DROPPER_PROMPT_END

local function validOpener()
    return learned and learned.job == game.JobId and learned.character == player.Character
        and learned.remote.Parent == Replicated:FindFirstChild("Requests") and learned.remote.ClassName == "RemoteEvent"
end
-- DROPPER_BUTTON_BEGIN
local function notesConnection()
    if type(getconnections) ~= "function" then return nil end
    local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
    if not notes or not notes:IsA("TextButton") or not visible(notes) then return nil end
    local selected, activated
    -- Fire one connected UI handler, never both events and never a guessed remote.
    for _, event in ipairs({ { notes.MouseButton1Click, false }, { notes.Activated, true } }) do
        for _, connection in ipairs(getconnections(event[1])) do
            if connection.Enabled and connection.LuaConnection and not connection.ForeignState then
                if selected then return nil end
                selected, activated = connection, event[2]
            end
        end
    end
    return selected, activated
end
-- DROPPER_BUTTON_END
local function canOpen()
    if validOpener() then return true end
    local ok, connection = pcall(notesConnection)
    return ok and connection ~= nil
end
local core = newDropper({ inspect = inspect, now = os.clock, sleep = task.wait, actor = function() return player.Character end,
    canOpen = canOpen,
    open = function()
        if validOpener() then learned.remote:FireServer(); return end
        local connection, activated = notesConnection()
        assert(connection, "Open Notes manually; its UI handler is unavailable or ambiguous")
        if activated then connection:Fire(nil, 1) else connection:Fire() end
    end,
    submit = function(choice, amount) return choice:InvokeServer(amount) end,
})
api.core = core
if inheritedUsed then core.used = inheritedUsed end
local staleGui = playerGui:FindFirstChild("CLAWNotesDropper")
if staleGui and inheritedUsed and not staleGui.Enabled then staleGui:Destroy() end
local runtime
local ui = createNotesPanel(playerGui, function()
    if runtime then runtime:stop() else core:cancel() end
    learning = nil
end)
runtime = newNotesRuntime(env, core, ui, player, playerGui, child, visible)
local gui, amount, dropButton = ui.gui, ui.amount, ui.dropButton
local messages = {
    sent = "Request sent. Check that the chosen amount dropped. Nothing will repeat automatically.",
    learn = "Click the game's Notes button once to learn the opener. Leave that dialog open, then use Drop once here.",
    busy = "A request is already in progress. Don't press the game's Submit button at the same time.",
    amount = "Enter a positive whole number of notes.", range = "That amount is outside the current dialog's range. Nothing dropped.",
    character = "Wait for your character to load before dropping notes.",
    bounds = "Cannot read the allowed amount safely. Nothing dropped.",
    ["other-prompt"] = "Close the other dialog, or wait for the notes dialog to finish loading. Nothing dropped.",
    changed = "The dialog changed. Nothing was submitted.", ["already-sent"] = "This dialog was already submitted. No repeat was sent.",
    ["open-timeout"] = "No notes dialog appeared within 5 seconds. No drop was submitted.",
    cancelled = "Stopped before submitting the drop.", failed = "Setup failed. No automatic retry was made.",
    uncertain = "The submission errored; the outcome is unknown. Check your notes. Further sends are blocked until you rejoin.",
}
local function connect(signal, callback)
    connections[#connections + 1] = signal:Connect(function(...)
        local ok = pcall(callback, ...)
        if not ok then ui:setNotice("failed", "Observer/setup error. Stop and report what happened; no automatic retry.") end
    end)
end

-- DROPPER_LEARN_BEGIN
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local previous
    local wrapper = function(self, ...)
        local count = select("#", ...)
        pcall(function()
            if api.closed then return end
            local method = getnamecallmethod()
            if method == "InvokeServer" and self == currentChoice and currentPrompt then core.used[currentPrompt] = true end
            if not learning or os.clock() > learning.deadline or method ~= "FireServer" or count ~= 0 then return end
            if typeof(self) ~= "Instance" or self.ClassName ~= "RemoteEvent" or self.Parent ~= learning.requests then return end
            if learning.candidate and learning.candidate ~= self then learning.ambiguous = true end
            learning.candidate = self
        end)
        return previous(self, ...)
    end
    local ok = pcall(function()
        previous = hookmetamethod(game, "__namecall", type(newcclosure) == "function" and newcclosure(wrapper) or wrapper)
    end)
    api.hookReady = ok and type(previous) == "function"
end
-- DROPPER_LEARN_END
local function watchNotesButton()
    local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
    if not notes or not notes:IsA("TextButton") or observedButtons[notes] then return end
    observedButtons[notes] = true
    connect(notes.MouseButton1Down, function()
        if api.closed or core.busy or not api.hookReady or not visible(notes) then return end
        learning = { deadline = os.clock() + 4, before = playerGui:FindFirstChild("ChoicePrompt"),
            requests = Replicated:FindFirstChild("Requests"), character = player.Character, job = game.JobId }
    end)
end
function api:show() if not self.closed then gui.Enabled = true end end
function api:stopAuto() runtime:stop() end
function api:startAuto() if not self.closed then runtime:start() end end
function api:stop() runtime:stop(); learning = nil; gui.Enabled = false end
function api:destroy()
    self:stop(); self.closed = true
    runtime:destroy()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    ui:destroy()
    -- Leave an inactive forwarding hook; do not overwrite hooks installed by other scripts.
end
connect(dropButton.Activated, function()
    if api.closed then return end
    if core.busy or core.uncertain or runtime.loop.active or runtime.menuActive then return end
    runtime.message = nil
    ui:setNotice("working", "Working on one drop. Do not also press the game's Submit button. Collapsing stops pre-submit waiting, but cannot undo a sent drop.")
    task.delay(8, function()
        if core.busy and not api.closed then ui:setNotice("working", "Still waiting for the game. No repeat will be sent. Check the ground before doing anything else.") end
    end)
    local _, result = core:run(amount.Text)
    ui:refresh(inspect(), canOpen(), core)
    ui:setNotice(result, messages[result] or "Stopped.")
end)
connect(ui.autoButton.Activated, function()
    if api.closed then return end
    local ok = pcall(function() runtime:start() end)
    if not ok then runtime:stop("automation-error") end
end)
ui:refresh(nil, false, core)
ui:setNotice("learn", api.hookReady and messages.learn or "Automatic opener learning is unavailable. Open Notes manually, then use Drop once here.")
env.CLAW_NOTES_DROPPER = api
if resume then task.spawn(function()
    local ok = pcall(function() runtime:resume(resume) end)
    if not ok then runtime:stop("automation-error") end
end) end
task.spawn(function()
    while not api.closed do
        local ok = pcall(function()
            watchNotesButton()
            local prompt = inspect()
            if learning then
                if os.clock() > learning.deadline or learning.character ~= player.Character or learning.job ~= game.JobId then learning = nil
                elseif prompt and prompt.kind == "notes" and prompt.identity ~= learning.before and learning.candidate then
                    if not learning.ambiguous then
                        learned = { remote = learning.candidate, character = learning.character, job = learning.job }
                        ui:setNotice("ready", "Connected to this session's Notes button. Choose an amount and press DROP. One drop per press; no automatic retries.")
                    else ui:setNotice("failed", "More than one opening request was observed. Close Notes and click it again to relearn.") end
                    learning = nil
                end
            end
            local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
            ui:refresh(prompt, canOpen(), core)
            ui:setAuto(runtime.loop.active or runtime.menuActive, runtime.message)
            -- Keep the controls reachable if the game hides its currency HUD while the notes dialog is open.
            ui:layout(notes and (visible(notes) or (prompt and prompt.kind == "notes")) and notes or nil)
        end)
        if not ok then learning = nil end
        task.wait(0.15)
    end
end)
print("[CLAW] Notes v3 ready. DROP sends one maximum-size drop; START AUTO enables same-server rejoining. Idle unless explicitly started or resuming your active run.")

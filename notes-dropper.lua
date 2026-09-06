-- CLAW notes dropper. Auto is OFF until chosen; the saved choice survives joins.
-- Learns the opener from a manual Notes click in this session; no remote-name guessing.
-- Does not use KeyHandler internals, fixed screen coordinates, or automatic retries.

-- DROPPER_CORE_BEGIN
local function newDropper(adapter)
    local core = { busy = false, uncertain = false, generation = 0, phase = "idle", used = setmetatable({}, { __mode = "k" }) }
    local function integer(value)
        return type(value) == "number" and value == value and value >= 1 and value <= 1000000000 and value % 1 == 0
    end
    function core:cancel() self.generation += 1 end
    function core:run(raw, cap)
        if self.busy then return false, "busy" end
        if self.uncertain then return false, "uncertain" end
        local maximumMode = raw == "MAX"
        if cap ~= nil and not integer(cap) then return false, "amount" end
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
            if maximumMode then amount = math.min(1000, fresh.maximum, cap or 1000) end
            if amount < fresh.minimum or amount > fresh.maximum then return "range" end
            if self.used[fresh.identity] then return "already-sent" end
            if self.beforeSubmit then self.beforeSubmit() end
            if generation ~= self.generation or adapter.actor() ~= actor then return "cancelled" end
            local verified = adapter.inspect()
            if not verified or verified.kind ~= "notes" or verified.identity ~= fresh.identity or verified.choice ~= fresh.choice
                or verified.minimum ~= fresh.minimum or verified.maximum ~= fresh.maximum then return "changed" end
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
local function validNotesRun(r, context)
    return type(r) == "table" and r.version == 2
        and type(r.enabled) == "boolean" and type(r.pending) == "boolean"
        and type(r.token) == "string" and #r.token >= 16 and #r.token <= 80
        and r.accountId == context.accountId and r.gameId == context.gameId
end
local function newNotesLoop(adapter)
    local loop = { active = false, generation = 0, state = "idle", unconfirmed = false }
    function loop:stop(reason)
        self.active = false; self.generation += 1; self.state = reason or "stopped"
        if self.unconfirmed then adapter.uncertain() end
        adapter.cancel(); adapter.status(self.state)
    end
    function loop:run(target)
        if self.active then return false, "busy" end
        if target ~= nil and (type(target) ~= "number" or target < 1 or target > 1000000000 or target % 1 ~= 0) then return false, "amount" end
        local session = adapter.context()
        self.active = true; self.generation += 1; self.unconfirmed = false
        self.total, self.batches = 0, 0
        local generation = self.generation
        local function live()
            if not self.active or self.generation ~= generation then return false end
            local c = adapter.context()
            return session.actor ~= nil and c.actor == session.actor and c.accountId == session.accountId
                and c.gameId == session.gameId and c.placeId == session.placeId and c.jobId == session.jobId and c.slot == session.slot
        end
        self.live = live
        local function hold(reason) self:stop(reason); return false, reason end
        local function countOK(n) return type(n) == "number" and n >= 0 and n <= 1000000000 and n % 1 == 0 end
        local ok, success, reason = pcall(function()
            local ready, problem = adapter.preflight()
            if not ready then return hold(problem or "not-ready") end
            local before, identity = adapter.balance()
            if not countOK(before) or not identity then return hold("balance-unavailable") end
            local remaining = math.min(target or before, before)
            if not live() then return hold("cancelled") end
            while remaining > 0 do
                local deadline = adapter.now() + 5
                while not adapter.ready() do
                    if not live() then return hold("cancelled") end
                    if adapter.now() >= deadline then return hold("prompt-not-closed") end
                    adapter.sleep(0.1)
                end
                if not live() then return hold("cancelled") end
                local count, source = adapter.balance()
                if count ~= before or source ~= identity then return hold("balance-changed") end
                self.state = "dropping"; adapter.status(self.state)
                if not live() then return hold("cancelled") end
                local sent, result, amount = adapter.drop(math.min(1000, remaining))
                if not sent then return hold(result or "drop-failed") end
                self.unconfirmed = true
                if not countOK(amount) or amount < 1 or amount > math.min(1000, remaining) then return hold("outcome-unknown") end
                self.state = "confirming"; adapter.status(self.state)
                deadline = adapter.now() + 10
                repeat
                    if not live() then return hold("cancelled") end
                    count, source = adapter.balance()
                    if source ~= nil and source ~= identity then return hold("balance-source-changed") end
                    if count == before - amount and source == identity then break end
                    if count ~= nil and count ~= before then return hold("outcome-unknown") end
                    if adapter.now() >= deadline then return hold("outcome-unknown") end
                    adapter.sleep(0.1)
                until false
                self.unconfirmed = false
                adapter.confirmed()
                self.total += amount; self.batches += 1
                remaining -= amount; before = count
                if remaining > 0 then
                    self.state = "between-batches"; adapter.status(self.state)
                    local nextAt = adapter.now() + 1
                    while adapter.now() < nextAt do
                        if not live() then return hold("cancelled") end
                        adapter.sleep(0.1)
                    end
                end
            end
            self.active = false
            self.state = before == 0 and "empty" or "complete"
            adapter.status(self.state)
            return true, self.state
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
    local accountId, gameId = player.UserId, game.GameId
    local setting = "CLAW_NOTES_AUTO_" .. tostring(accountId)
    local path = "CLAW/notes-auto-v2-" .. tostring(gameId) .. "-" .. tostring(accountId) .. ".json"
    local loader = "https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"
    local queue = queue_on_teleport or queueonteleport or queueteleport
    local key = env.CLAW_NOTES_EXECUTION_KEY or env.script_key or script_key
    local runtime = { enabled = false, waiting = false, closed = false, generation = 0, pending = false, message = nil }
    local texts = {
        dropping = "Dropping the next batch...", confirming = "Checking the balance change...",
        ["between-batches"] = "Next batch in 1s. Click STOP to cancel.",
        ["balance-unavailable"] = "Cannot read your Notes balance. Nothing more sent.",
        ["outcome-unknown"] = "Drop unconfirmed. Check your notes; no repeat sent.",
        ["balance-source-changed"] = "Notes display changed. Nothing more sent.",
        ["balance-changed"] = "Balance changed unexpectedly. Nothing more sent.",
        ["prompt-not-closed"] = "Previous dialog did not close. Nothing more sent.",
        ["automation-error"] = "Dropper error. Nothing more sent.",
        ["other-prompt"] = "Close the other dialog before dropping.",
        ["open-timeout"] = "Notes dialog did not open. Nothing dropped.",
        learn = "Notes handler unavailable. Open Notes once, then start again.",
        travelling = "You are leaving. Auto will wait for your next join.",
        waiting = "Auto ON. Waiting for your character and Notes display.",
        stopped = "Auto OFF. Saved for future joins.", cancelled = "Dropping stopped.",
        uncertain = "Check the pending drop and rejoin before starting again.",
    }
    local function context()
        return { accountId = player.UserId, gameId = game.GameId, placeId = game.PlaceId,
            jobId = game.JobId, slot = player:GetAttribute("DataSlot"), actor = player.Character }
    end
    local function world() return game.PlaceId == 6473861193 or game.PlaceId == 6032399813 end
    local function status(code)
        if code == "empty" then
            runtime.message = runtime.enabled and "Empty. Auto ON for your next join." or "All notes dropped. Staying here."
        elseif code == "complete" then runtime.message = "Requested total dropped. Staying here."
        else runtime.message = texts[code] or code end
        ui:setAuto(runtime.enabled, runtime.message)
        if code ~= "dropping" and code ~= "confirming" and code ~= "between-batches" and code ~= "waiting" and code ~= "travelling" then
            local normal = code == "empty" or code == "complete" or code == "stopped" or code == "cancelled"
            ui:setNotice(normal and "ready" or code, runtime.message)
        end
    end
    local function storage()
        return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
    end
    local function read()
        assert(storage(), "Local settings unavailable")
        if not isfile(path) then return nil end
        local raw = readfile(path)
        assert(type(raw) == "string" and #raw <= 4096, "Invalid notes setting")
        local r = Http:JSONDecode(raw)
        assert(validNotesRun(r, { accountId = accountId, gameId = gameId }), "Wrong notes setting")
        return r
    end
    local function save()
        assert(storage(), "Cannot save Auto")
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder("CLAW") then makefolder("CLAW") end
        local r = { version = 2, accountId = accountId, gameId = gameId, token = runtime.token or Http:GenerateGUID(false),
            enabled = runtime.enabled, pending = runtime.pending }
        local raw = Http:JSONEncode(r)
        writefile(path, raw)
        assert(readfile(path) == raw, "Cannot verify Auto setting")
        runtime.token = r.token
    end
    local function clearQueueTicket()
        pcall(function() Teleport:SetTeleportSetting(setting, "") end)
    end
    local function arm()
        assert(type(queue) == "function", "Teleport continuation unavailable")
        assert(type(key) == "string" and #key == 32 and key:match("^[%w]+$"), "Use the notes loadstring")
        local ticket = Http:GenerateGUID(false)
        Teleport:SetTeleportSetting(setting, ticket)
        assert(Teleport:GetTeleportSetting(setting) == ticket, "Cannot verify continuation")
        -- This only reloads on a USER-initiated teleport. It never requests a teleport.
        -- Stop invalidates both the disk setting and this one-use ticket.
        local code = string.format([[
local ok = pcall(function()
    local t, h, p = game:GetService("TeleportService"), game:GetService("HttpService"), game:GetService("Players")
    local deadline = os.clock() + 120
    repeat task.wait(0.1) until p.LocalPlayer or os.clock() >= deadline
    if not p.LocalPlayer or p.LocalPlayer.UserId ~= %d or game.GameId ~= %d then return end
    if game.PlaceId ~= 4111023553 and game.PlaceId ~= 6473861193 and game.PlaceId ~= 6032399813 then return end
    if t:GetTeleportSetting(%q) ~= %q then return end
    t:SetTeleportSetting(%q, "")
    if type(isfile) ~= "function" or type(readfile) ~= "function" or not isfile(%q) then return end
    local raw = readfile(%q)
    if type(raw) ~= "string" or #raw > 4096 then return end
    local r = h:JSONDecode(raw)
    if type(r) ~= "table" or r.version ~= 2 or r.enabled ~= true or type(r.pending) ~= "boolean" or r.token ~= %q
        or r.accountId ~= p.LocalPlayer.UserId or r.gameId ~= game.GameId then return end
    local e = getgenv()
    if e.CLAW_NOTES_LOADING or e.CLAW_NOTES_DROPPER and not e.CLAW_NOTES_DROPPER.closed then return end
    e.CLAW_NOTES_LOADING = true
    e.CLAW_NOTES_EXECUTION_KEY = %q
    script_key = e.CLAW_NOTES_EXECUTION_KEY
    local loaded = pcall(function() loadstring(game:HttpGet(%q))() end)
    e.CLAW_NOTES_LOADING = nil
    if not loaded then warn("[CLAW] Notes continuation stopped; check your key and connection.") end
end)
if not ok then warn("[CLAW] Notes continuation stopped; no automatic retry.") end
]], accountId, gameId, setting, ticket, setting, path, path, runtime.token, key, loader)
        queue(code)
    end
    local function balance()
        -- Only the Notes button's own numeric display; never another currency/stat.
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
                    local n = tonumber((raw:gsub(",", "")))
                    if n and n >= 0 and n <= 1000000000 and n % 1 == 0 then
                        if identity then return nil end
                        found, identity = n, item
                    end
                end
            end
        end
        return found, identity
    end
    local function preflight()
        if core.uncertain or core.busy then return false, "uncertain" end
        if env.CLAW_CONTROL or env.CLAW_RELAY then return false, "Stop manager/bringer before standalone dropping." end
        if not world() or not player.Character then return false, "Wait for your character in the world." end
        return true
    end
    runtime.loop = newNotesLoop({ now = os.clock, context = context, sleep = task.wait, balance = balance,
        cancel = function() core:cancel() end, status = status, preflight = preflight,
        uncertain = function() core.uncertain = true end,
        ready = function()
            local prompt = playerGui:FindFirstChild("ChoicePrompt")
            return not prompt or not core.used[prompt]
        end,
        drop = function(limit)
            local ok, result = core:run("MAX", limit); return ok, result, core.lastAmount
        end,
        confirmed = function()
            runtime.pending = false
            if runtime.enabled or runtime.journaled then save() end
        end,
    })
    core.beforeSubmit = function()
        assert(runtime.loop.live and runtime.loop.live() and not runtime.closed, "Batch cancelled")
        assert(not env.CLAW_CONTROL and not env.CLAW_RELAY, "Another controller started")
        runtime.loop.unconfirmed = true
        if runtime.enabled or runtime.journaled then
            runtime.pending = true
            save() -- Durable before InvokeServer: a crash cannot silently replay an uncertain batch.
        end
        assert(runtime.loop.live() and not runtime.closed, "Batch cancelled")
    end
    function runtime:stop(reason)
        self.enabled, self.waiting = false, false; self.generation += 1
        self.loop:stop(reason or "stopped"); clearQueueTicket()
        if self.journaled then
            local ok = pcall(save)
            if not ok then
                status("STOPPED HERE, but Auto OFF could not save. Do not rejoin until saved; remove the notes autoexec loader if needed.")
                warn("[CLAW] Auto stopped locally but OFF could not be saved.")
            end
        end
    end
    function runtime:destroy()
        self:stop(); self.closed = true
        if self.teleportConnection then self.teleportConnection:Disconnect() end
    end
    function runtime:drain(target)
        local generation = self.generation
        local ok, reason = self.loop:run(target)
        if not ok and self.enabled and generation == self.generation then self:stop(reason) end
        return ok, reason
    end
    function runtime:drop(raw)
        if self.closed or self.enabled or self.waiting or self.loop.active then return false, "busy" end
        local target
        if raw ~= "MAX" then
            if type(raw) ~= "string" or #raw > 12 or not raw:match("^%s*%d+%s*$") then status("Enter MAX or a positive whole total."); return false, "amount" end
            target = tonumber(raw)
            if not target or target < 1 or target > 1000000000 then status("Enter MAX or a positive whole total."); return false, "amount" end
        end
        return self:drain(target)
    end
    function runtime:waitAndDrain(resuming)
        self.waiting = true; status("waiting")
        if not world() then return end -- Menu stays idle; user chooses the slot/server.
        local generation, untilTime = self.generation, os.clock() + 90
        local stableAt, stableCount, stableSource, stableActor
        while self.enabled and not self.closed and generation == self.generation do
            local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
            local count, source = balance()
            local openerReady = not core.canOpen or core.canOpen() or playerGui:FindFirstChild("ChoicePrompt") ~= nil
            if player.Character and notes and count ~= nil and (count == 0 or openerReady) then
                if not stableAt or count ~= stableCount or source ~= stableSource or player.Character ~= stableActor then
                    stableAt, stableCount, stableSource, stableActor = os.clock(), count, source, player.Character
                end
                if not resuming or os.clock() - stableAt >= 2 then
                    self.waiting = false; self:drain(nil); return
                end
            else
                stableAt = nil
            end
            if os.clock() >= untilTime then self:stop("Notes display did not become readable. Auto OFF."); return end
            task.wait(0.1)
        end
    end
    function runtime:start(resuming)
        if self.closed then return end
        if self.enabled then self:stop(); return end
        if self.loop.active then self:stop("cancelled"); return end
        if self.loop.active or core.busy or core.uncertain then status("uncertain"); return end
        if env.CLAW_CONTROL or env.CLAW_RELAY then status("Stop manager/bringer before standalone dropping."); return end
        ui.keepVisible = true
        local ok = pcall(function()
            assert(storage(), "Saving unavailable")
            self.token = Http:GenerateGUID(false)
            self.enabled, self.pending, self.journaled = true, false, true
            save(); arm()
        end)
        if not ok then self:stop("Cannot enable saved Auto. Check file access, teleport queue and your notes loadstring."); return end
        self:waitAndDrain(resuming == true)
    end
    function runtime:applyAuto(value, resuming)
        if self.closed then return end
        self.configured = true
        if type(value) ~= "boolean" then
            self.journaled = true
            self:stop("CLAW_NOTES_AUTO must be true or false, without quotes. Auto OFF."); return
        end
        if not value then
            self.journaled = true; self:stop(); return
        end
        if self.enabled then return end -- Setting ON is not the same as clicking a toggle.
        if self.pending or core.uncertain then
            self:stop("Last drop unconfirmed. Check notes before manually enabling Auto again."); return
        end
        if self.loop.active or core.busy then status("Finish or stop the current drop before enabling Auto."); return end
        self:start(resuming)
    end
    function runtime:resume(requestedAuto)
        if self.closed or self.configured then return end
        local ok, r = pcall(read)
        if not ok then
            if requestedAuto == false then
                self.pending, self.journaled = true, true -- Preserve uncertainty if the old file could not be read.
                self:stop()
            else status("Auto setting unreadable. Auto OFF; no automatic drops.") end
            return
        end
        if r then self.token, self.pending, self.journaled = r.token, r.pending, true end
        if requestedAuto ~= nil then self:applyAuto(requestedAuto, true); return end
        if not r then return end
        if r.pending then
            self:stop("Last drop unconfirmed. Check notes before manually enabling Auto again."); return
        end
        if not r.enabled then status("stopped"); return end
        self.enabled = true; ui.keepVisible = true
        if not pcall(arm) then self:stop("Cannot prepare the next join. Use the notes loadstring."); return end
        self:waitAndDrain(true)
    end
    runtime.teleportConnection = player.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
            runtime.generation += 1; runtime.waiting = false
            runtime.loop:stop("travelling")
            -- Leave the saved ON choice intact, but never clear a pending receipt.
        end
    end)
    runtime.balance, runtime.path = balance, path
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
    -- This field is a TOTAL, not the per-dialog limit. Runtime clips it to the balance.
    local inRange = not live or prompt.maximum >= 0
    local state = { badge = canOpen and "READY" or "SETUP", tone = canOpen and "ready" or "warm",
        button = "DROP", sub = "total", enabled = valid and inRange and not busy and not uncertain,
        range = live and (tostring(prompt.minimum) .. " - " .. tostring(prompt.maximum) .. "  /  LIVE LIMIT") or "LIMIT CHECKED WHEN OPENED",
        short = canOpen and "One click drops the chosen total." or "Click Notes once to connect." }
    if live then state.badge, state.tone = "READY", "ready" end
    if notice == "sent" then state.badge, state.tone, state.short = "SENT", "warm", "Request sent. Check the ground."
    elseif notice and notice ~= "learn" and notice ~= "ready" and notice ~= "working" then
        state.badge, state.tone, state.short = "CHECK", "error", "Action stopped. See details."
    end
    if not valid then state.short = "Enter a positive whole number."
    elseif not inRange then state.short = "Waiting for the notes dialog." end
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
    local maxButton = make("TextButton", field, { Name = "Maximum", Text = "TOTAL / MAX", Font = Enum.Font.GothamMedium,
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
    local actionSub = label(ui.dropButton, "total", 0, 31, 94, 12, 9, Color3.fromRGB(76, 65, 48))
    actionTitle.TextXAlignment, actionSub.TextXAlignment = Enum.TextXAlignment.Center, Enum.TextXAlignment.Center
    ui.autoButton = make("TextButton", body, { Name = "AutoLoop", Text = "AUTO OFF", Font = Enum.Font.GothamBold,
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
        self.autoButton.Text = self.autoActive and "AUTO ON / STOP" or m.busy and "STOP DROP" or "AUTO OFF"
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
        self.autoButton.Text = active and "AUTO ON / STOP" or "AUTO OFF"
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

-- DROPPER_BOOT_BEGIN
local env = getgenv()
local requestedAuto = env.CLAW_NOTES_AUTO
env.CLAW_NOTES_AUTO = nil -- One request per execution; the UI can still save OFF afterwards.
env.CLAW_NOTES_RESUME = nil -- Discard the old v3 rejoin plan; never travel automatically.
local inheritedUsed
if env.CLAW_NOTES_DROPPER then
    local old = env.CLAW_NOTES_DROPPER
    if old.uiVersion == 5 and not old.closed then
        old:show()
        if requestedAuto ~= nil then old:setAuto(requestedAuto) end
        return
    end
    if requestedAuto == false and type(old.stopAuto) == "function" then old:stopAuto() end
    if old.core and (old.core.busy or old.core.uncertain) then
        old:show(); warn("[CLAW] Finish/check the pending drop before changing the UI. Rejoin if its outcome is unknown."); return
    end
    assert(type(old.destroy) == "function", "Rejoin before loading the new notes UI")
    inheritedUsed = old.core and old.core.used
    old:destroy()
end
-- DROPPER_BOOT_END
local Players, Replicated = game:GetService("Players"), game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Join the game before opening the notes dropper")
local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
assert(playerGui, "Wait for the game UI")
local api = { uiVersion = 5, closed = false, hookReady = false }
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
core.canOpen = canOpen
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
function api:setAuto(enabled) if not self.closed then runtime:applyAuto(enabled) end end
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
    if core.busy or core.uncertain or runtime.loop.active or runtime.enabled then return end
    runtime.message = nil
    ui:setNotice("working", "Dropping the chosen total in batches. Do not also press the game's Submit button. Collapse cancels further batches, not notes already sent.")
    task.delay(8, function()
        if core.busy and not api.closed then ui:setNotice("working", "Still waiting for the game. No repeat will be sent. Check the ground before doing anything else.") end
    end)
    runtime:drop(amount.Text)
    ui:refresh(inspect(), canOpen(), core)
end)
connect(ui.autoButton.Activated, function()
    if api.closed then return end
    local ok = pcall(function() runtime:start() end)
    if not ok then runtime:stop("automation-error") end
end)
ui:refresh(nil, false, core)
ui:setNotice("learn", api.hookReady and messages.learn or "Automatic opener learning is unavailable. Open Notes manually, then use Drop once here.")
env.CLAW_NOTES_DROPPER = api
task.spawn(function()
    if env.CLAW_NOTES_AUTO ~= nil then
        requestedAuto, env.CLAW_NOTES_AUTO = env.CLAW_NOTES_AUTO, nil
    end
    local ok = pcall(function() runtime:resume(requestedAuto) end)
    if not ok then runtime:stop("automation-error") end
end)
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
                        ui:setNotice("ready", "Connected to this session's Notes button. DROP drains your chosen total in batches; Auto saves drop-on-join.")
                    else ui:setNotice("failed", "More than one opening request was observed. Close Notes and click it again to relearn.") end
                    learning = nil
                end
            end
            local notes = child(playerGui, "CurrencyGui", "CurrencyFrame", "Notes")
            ui:refresh(prompt, canOpen(), { busy = core.busy or runtime.loop.active, uncertain = core.uncertain })
            ui:setAuto(runtime.enabled, runtime.message)
            -- Keep the controls reachable if the game hides its currency HUD while the notes dialog is open.
            ui:layout(notes and (visible(notes) or (prompt and prompt.kind == "notes")) and notes or nil)
        end)
        if not ok then learning = nil end
        task.wait(0.15)
    end
end)
print("[CLAW] Notes v5 ready. CLAW_NOTES_AUTO = true/false sets Auto at launch; omit to use the saved choice. This script never rejoins or moves you.")

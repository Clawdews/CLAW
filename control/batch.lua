-- A temporary shared setup window. Permanent pairing keys remain per account.
local env, Http = getgenv(), game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local account = tostring(player.UserId)
local provided = env.CLAW_BATCH; env.CLAW_BATCH = nil
local folder, sharedPath = "CLAW_PAIRINGS", "CLAW_PAIRINGS/batch.json"
local pendingPath = folder .. "/pending-" .. account .. ".json"
local pairingPath = folder .. "/" .. account .. ".json"
local function valid(config)
    return type(config) == "table" and config.Version == 1
        and type(config.Endpoint) == "string" and config.Endpoint:match("^https://[%w%.%-]+$")
        and type(config.OwnerId) == "string" and config.OwnerId:match("^%d+$") and #config.OwnerId >= 17 and #config.OwnerId <= 20
        and type(config.Code) == "string" and #config.Code == 64 and config.Code:match("^[a-f0-9]+$")
        and type(config.Expires) == "number" and config.Expires == math.floor(config.Expires)
end
local function exists(path)
    local ok, value = pcall(isfile, path)
    assert(ok and type(value) == "boolean", "CLAW cannot check local setup files; nothing overwritten")
    return value
end
local function read(path)
    if not exists(path) then return nil end
    local ok, result = pcall(function()
        local raw = readfile(path)
        assert(type(raw) == "string" and #raw <= 4096)
        return Http:JSONDecode(raw)
    end)
    assert(ok and type(result) == "table", "CLAW cannot read a local setup file; nothing overwritten")
    return result
end
local function save(path, value)
    local ok = pcall(function()
        if not isfolder(folder) then makefolder(folder) end
        local raw = Http:JSONEncode(value)
        writefile(path, raw)
        assert(readfile(path) == raw)
    end)
    assert(ok, "CLAW could not save and verify local setup; check executor file access")
end
if type(isfile) ~= "function" or type(readfile) ~= "function" then
    assert(not provided, "Executor file support required for alt setup")
    return true
end
if provided ~= nil then
    assert(valid(provided) and provided.Expires > os.time() and provided.Expires <= os.time() + 660, "Alt setup expired or invalid; start again from /claw panel")
    assert(type(writefile) == "function" and type(isfolder) == "function" and type(makefolder) == "function", "Executor write support required for alt setup")
    local old = read(sharedPath)
    assert(not old or (valid(old) and (old.OwnerId == provided.OwnerId or old.Expires <= os.time())), "Another Discord owner's setup is active on this workspace; wait for it to expire")
    save(sharedPath, provided)
    print("[CLAW] Alt setup saved for this workspace for 10 minutes. Other accounts use the same public loader. Approve their requests in /claw panel.")
end
-- Explicit single-account setup and existing pairings always take precedence.
if env.CLAW_PAIR ~= nil or exists(pairingPath) then return true end
local config = read(sharedPath)
if not config or not valid(config) then return true end
local pending = read(pendingPath)
if config.Expires <= os.time() and not pending then return true end
assert(type(writefile) == "function" and type(isfolder) == "function" and type(makefolder) == "function", "Executor write support required for alt setup")
if pending then
    assert(valid(pending) and pending.AccountId == account and type(pending.Key) == "string"
        and #pending.Key == 64 and pending.Key:match("^[a-f0-9]+$"), "Invalid pending setup file; keep it private and inspect it before replacing it")
    -- Retain the same device key across setup windows and retries.
    if pending.OwnerId ~= config.OwnerId or pending.Endpoint ~= config.Endpoint then
        error("Pending setup belongs to another owner; nothing overwritten")
    end
    pending.Code, pending.Expires = config.Code, config.Expires
else
    pending = { Version = 1, Endpoint = config.Endpoint, OwnerId = config.OwnerId, Code = config.Code,
        Expires = config.Expires, AccountId = account, Key = (Http:GenerateGUID(false) .. Http:GenerateGUID(false)):gsub("%-", ""):lower() }
end
save(pendingPath, pending)
local request = request or http_request
assert(type(request) == "function", "Executor HTTP support required for alt setup")
local active = {}; env.CLAW_BATCH_ACTIVE = active
local announced = false
-- One request at startup, then every 30 seconds; bounded by the setup expiry.
for attempt = 1, 22 do
    if env.CLAW_BATCH_ACTIVE ~= active then return false end
    if exists(pairingPath) then return true end
    local current = read(sharedPath)
    if not current or current.Code ~= config.Code or current.OwnerId ~= config.OwnerId then break end
    local sent, response = pcall(function()
        return request({ Url = pending.Endpoint .. "/batch?owner=" .. pending.OwnerId, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" }, Body = Http:JSONEncode({ accountId = account,
                username = player.Name, code = pending.Code, key = pending.Key }) })
    end)
    if env.CLAW_BATCH_ACTIVE ~= active then return false end
    local decoded, body = false, nil
    if sent and type(response) == "table" and type(response.Body) == "string" and #response.Body <= 4096 then
        decoded, body = pcall(Http.JSONDecode, Http, response.Body)
    end
    if decoded and type(body) == "table" then
        if response.StatusCode == 200 and body.state == "approved" then
            env.CLAW_PAIR = { Endpoint = pending.Endpoint, OwnerId = pending.OwnerId, AccountId = account, Key = pending.Key }
            print("[CLAW] Pairing approved. Saving this account's own private key.")
            return true
        elseif response.StatusCode == 200 and body.state == "pending" and not announced
            and type(body.check) == "string" and body.check:match("^[A-F0-9]+$") and #body.check == 8 then
            print("[CLAW] @" .. player.Name .. " waiting for approval. Check code: " .. body.check .. ". Compare it in /claw panel, then approve this request.")
            announced = true
        elseif response.StatusCode == 401 or response.StatusCode == 409 then break end
    end
    if os.time() >= config.Expires then break end
    task.wait(math.min(30, math.max(1, config.Expires - os.time())))
end
print("[CLAW] Alt setup stopped or expired. Your paired accounts were not changed. Open /claw panel to review setup.")
return false

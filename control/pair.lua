-- One-time setup on one account. Never ships a shared key or a Discord bot token.
local env, Http = getgenv(), game:GetService("HttpService")
local input = env.CLAW_PAIR; env.CLAW_PAIR = nil
assert(type(input) == "table", "Use your private /claw enroll snippet")
local player = game:GetService("Players").LocalPlayer
assert(player and tostring(player.UserId) == input.AccountId, "Run this pairing snippet on its matching Roblox account")
assert(type(input.OwnerId) == "string" and input.OwnerId:match("^%d+$") and #input.OwnerId >= 17 and #input.OwnerId <= 20, "Invalid Discord owner")
assert(type(input.Key) == "string" and #input.Key == 64 and input.Key:match("^[a-f0-9]+$"), "Invalid pairing key")
assert(type(input.Endpoint) == "string" and input.Endpoint:match("^https://[%w%.%-]+$"), "Invalid relay origin")
local path = "CLAW_PAIRINGS/" .. input.AccountId .. ".json"
assert(type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
    and type(isfolder) == "function" and type(makefolder) == "function", "Executor file support required; nothing saved")
-- A failed read is not evidence that no pairing exists.
local function readSnapshot()
    local checked, present = pcall(isfile, path)
    assert(checked and type(present) == "boolean", "Cannot check pairing file; check executor file access. Nothing saved.")
    if not present then return false, nil end
    local readable, raw = pcall(readfile, path)
    assert(readable and type(raw) == "string", "Cannot read saved pairing; check executor file access. Nothing saved.")
    return true, raw
end
local exists, oldRaw = readSnapshot()
local previous
if exists then
    assert(type(oldRaw) == "string" and #oldRaw <= 4096, "Existing pairing file is invalid; inspect it before replacing it")
    local decoded, value = pcall(Http.JSONDecode, Http, oldRaw)
    previous = decoded and value or nil
    assert(type(previous) == "table" and previous.Version == 1 and previous.AccountId == input.AccountId,
        "Existing pairing file is invalid; inspect it before replacing it")
    assert(previous.OwnerId == input.OwnerId and previous.Endpoint == input.Endpoint,
        "This local account is paired to another owner or endpoint. Remove its CLAW_PAIRINGS file deliberately before changing owners.")
end
local request = request or http_request
assert(type(request) == "function", "Executor HTTP support required")
-- Never forward adapter errors: they may contain the private request or file.
local encoded, body, raw = pcall(function()
    return Http:JSONEncode({ accountId = input.AccountId, key = input.Key }),
        Http:JSONEncode({ Version = 1, Endpoint = input.Endpoint, OwnerId = input.OwnerId,
            AccountId = input.AccountId, Key = input.Key, AllowMenuReturn = previous and previous.AllowMenuReturn == true or false })
end)
assert(encoded and type(body) == "string" and type(raw) == "string" and #raw <= 4096,
    "Could not prepare pairing; nothing saved. Check executor JSON support.")
local sent, response = pcall(request, { Url = input.Endpoint .. "/session?owner=" .. input.OwnerId, Method = "POST",
    Headers = { ["Content-Type"] = "application/json" }, Body = body })
assert(sent and type(response) == "table" and response.StatusCode == 200, "Pairing rejected or relay unavailable; nothing saved")
local stillExists, latestRaw = readSnapshot()
assert(stillExists == exists and latestRaw == oldRaw,
    "Pairing file changed during setup; nothing overwritten. Stop the other setup and rerun this account's snippet.")
local stored = pcall(function()
    if not isfolder("CLAW_PAIRINGS") then makefolder("CLAW_PAIRINGS") end
    writefile(path, raw); assert(readfile(path) == raw)
end)
assert(stored, "Could not save and verify pairing. Check executor file access, then rerun this account's private snippet.")
-- Remove only this account's matching temporary setup file after the permanent save succeeds.
if type(delfile) == "function" then
    pcall(function()
        local pendingPath = "CLAW_PAIRINGS/pending-" .. input.AccountId .. ".json"
        if not isfile(pendingPath) then return end
        local pending = Http:JSONDecode(readfile(pendingPath))
        if pending.AccountId == input.AccountId and pending.OwnerId == input.OwnerId and pending.Key == input.Key then delfile(pendingPath) end
    end)
end
print("[CLAW] Paired this account privately. Put the public launcher-beta.lua loader in autoexec; /claw setup has it.")
return true

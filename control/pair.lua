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
local exists, oldRaw = pcall(readfile, path)
local previous
if exists then
    assert(type(oldRaw) == "string" and #oldRaw <= 4096, "Existing pairing file is invalid; inspect it before replacing it")
    previous = Http:JSONDecode(oldRaw)
    assert(type(previous) == "table" and previous.Version == 1 and previous.AccountId == input.AccountId,
        "Existing pairing file is invalid; inspect it before replacing it")
    assert(previous.OwnerId == input.OwnerId and previous.Endpoint == input.Endpoint,
        "This local account is paired to another owner or endpoint. Remove its CLAW_PAIRINGS file deliberately before changing owners.")
end
local request = request or http_request
assert(type(request) == "function", "Executor HTTP support required")
local response = request({ Url = input.Endpoint .. "/session?owner=" .. input.OwnerId, Method = "POST",
    Headers = { ["Content-Type"] = "application/json" }, Body = Http:JSONEncode({ accountId = input.AccountId, key = input.Key }) })
assert(type(response) == "table" and response.StatusCode == 200, "Pairing rejected or relay unavailable; nothing saved")
local raw = Http:JSONEncode({ Version = 1, Endpoint = input.Endpoint, OwnerId = input.OwnerId,
    AccountId = input.AccountId, Key = input.Key, AllowMenuReturn = previous and previous.AllowMenuReturn == true or false })
if not isfolder("CLAW_PAIRINGS") then makefolder("CLAW_PAIRINGS") end
writefile(path, raw); assert(readfile(path) == raw, "Pairing file verification failed")
print("[CLAW] Paired this account privately. Put the public launcher-beta.lua loader in autoexec; /claw setup has it.")
return true

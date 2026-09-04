-- Public autoexec entry point. Each local account reads only its own private pairing.
local Players = game:GetService("Players")
for _ = 1, 240 do
    if Players.LocalPlayer then break end
    task.wait(0.25)
end
assert(Players.LocalPlayer, "CLAW is waiting for Roblox to finish loading. Run the same public loader again when the menu appears.")
-- PAIR_MODULE_BEGIN
if getgenv().CLAW_PAIR ~= nil then
    local pairing = game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/control/pair.lua")
    assert(loadstring(pairing, "@CLAW/pair.lua"))()
end
-- PAIR_MODULE_END
local player = Players.LocalPlayer
local Http = game:GetService("HttpService")
local path = "CLAW_PAIRINGS/" .. tostring(player.UserId) .. ".json"
assert(type(isfile) == "function" and type(readfile) == "function", "Executor file support required; saved pairing was not changed")
local checked, exists = pcall(isfile, path)
assert(checked and type(exists) == "boolean", "Cannot check pairing file; check executor file access before trying again")
if not exists then
    print("[CLAW] First setup: in Discord use /claw enroll account:" .. (player.Name and ("@" .. player.Name) or tostring(player.UserId)))
    print("[CLAW] Run its private pairing reply once on this account. Afterward this same public loader reconnects automatically.")
    return
end
local ok, raw = pcall(readfile, path)
assert(ok, "Cannot read saved pairing; check executor file access. Do not enroll again just because a read failed.")
assert(type(raw) == "string" and #raw <= 4096, "Invalid local pairing file")
local decoded, config = pcall(Http.JSONDecode, Http, raw)
assert(decoded, "Invalid local pairing file; keep it private and follow Recover pairing in the setup guide")
assert(type(config) == "table" and config.Version == 1 and config.AccountId == tostring(player.UserId), "Pairing belongs to another account")
assert(type(config.OwnerId) == "string" and config.OwnerId:match("^%d+$") and #config.OwnerId >= 17 and #config.OwnerId <= 20, "Invalid pairing owner")
assert(type(config.Endpoint) == "string" and config.Endpoint:match("^https://[%w%.%-]+$"), "Invalid pairing endpoint")
assert(type(config.Key) == "string" and #config.Key == 64 and config.Key:match("^[a-f0-9]+$"), "Invalid pairing key")
getgenv().CLAW_CONTROL_CONFIG = { Endpoint = config.Endpoint, OwnerId = config.OwnerId, Key = config.Key,
    AllowMenuReturn = config.AllowMenuReturn == true }
local url = "https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/control-client.lua"
return assert(loadstring(game:HttpGet(url .. "?cache=" .. Http:GenerateGUID(false)), "@CLAW/control-client.lua"))()

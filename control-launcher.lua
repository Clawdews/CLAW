-- Public autoexec entry point. Each local account reads only its own private pairing.
-- PAIR_MODULE_BEGIN
if getgenv().CLAW_PAIR ~= nil then
    local pairing = game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/control/pair.lua")
    assert(loadstring(pairing, "@CLAW/pair.lua"))()
end
-- PAIR_MODULE_END
local player = game:GetService("Players").LocalPlayer
if not player then return end
local Http = game:GetService("HttpService")
local ok, raw = pcall(readfile, "CLAW_PAIRINGS/" .. tostring(player.UserId) .. ".json")
if not ok then
    print("[CLAW] First setup: in Discord use /claw enroll account:" .. tostring(player.UserId))
    print("[CLAW] Run its private pairing reply once on this account. Afterward this same public loader reconnects automatically.")
    return
end
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

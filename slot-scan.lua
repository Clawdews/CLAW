-- Standalone read-only diagnostic. Compatible with the current live control client.
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Run this in a Roblox client")
assert(game.PlaceId == 4111023553, "Run the slot scanner at the character-selection menu")
local source = game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/control/menu-scan.lua?cache=" .. Http:GenerateGUID(false))
local Scan = assert(loadstring(source, "@CLAW/menu-scan.lua"))()
local result = Scan.collect(player:FindFirstChild("PlayerGui"), function() task.wait() end)
result.accountId = tostring(player.UserId)
result.capturedAt = os.time()
result.placeId = game.PlaceId
local raw = Http:JSONEncode(result)
assert(#raw < 180000, "Menu report exceeded the safety limit")
getgenv().CLAW_SLOT_SCAN = result
local ok = pcall(function()
    if not isfolder("CLAW_CONTROL") then makefolder("CLAW_CONTROL") end
    local path = "CLAW_CONTROL/menu-" .. tostring(player.UserId) .. ".json"
    writefile(path, raw)
    assert(readfile(path) == raw)
end)
print("[CLAW SCAN] " .. result.status .. " | " .. #result.rows .. " rows | " .. #result.candidates .. " unconfirmed slot candidates")
print(ok and "[CLAW SCAN] Saved in Volt workspace/CLAW_CONTROL. No selection or teleport was sent."
    or "[CLAW SCAN] File save unavailable; report is in getgenv().CLAW_SLOT_SCAN")
return result

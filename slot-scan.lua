-- Standalone read-only diagnostic. Compatible with the current live control client.
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
assert(player, "Run this in a Roblox client")
assert(game.PlaceId == 4111023553, "Run the slot scanner at the character-selection menu")
-- SCANNER_MODULE_BEGIN
local source = game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/control/menu-scan.lua?cache=" .. Http:GenerateGUID(false))
local Scan = assert(loadstring(source, "@CLAW/menu-scan.lua"))()
-- SCANNER_MODULE_END
local result = Scan.collect(player:FindFirstChild("PlayerGui"), function() task.wait() end)
result.accountId = tostring(player.UserId)
result.capturedAt = os.time()
result.placeId = game.PlaceId
local raw = Http:JSONEncode(result)
assert(#raw < 400000, "Menu report exceeded the safety limit")
getgenv().CLAW_SLOT_SCAN = result
local ok = pcall(function()
    if not isfolder("CLAW_CONTROL") then makefolder("CLAW_CONTROL") end
    local path = "CLAW_CONTROL/menu-" .. tostring(player.UserId) .. ".json"
    writefile(path, raw)
    assert(readfile(path) == raw)
end)
print("[CLAW SCAN] v" .. Scan.VERSION .. " | " .. result.status .. " | " .. #result.cards .. " cards | "
    .. result.completeCards .. " with name/level/race/location | " .. result.labelCount .. " labels")
for _, card in ipairs(result.cards) do
    print("[CLAW SLOT " .. card.slot .. "] " .. (card.characterName or "name not read")
        .. " | Lv. " .. tostring(card.level or "?") .. " " .. (card.race or "race not read")
        .. " | " .. (card.oath or "") .. " | " .. (card.origin or "") .. " | " .. (card.location or "location not read")
        .. " | played " .. (card.playtime or "?") .. " | last " .. (card.lastPlayed or "?"))
end
print(ok and "[CLAW SCAN] Saved in Volt workspace/CLAW_CONTROL. No selection or teleport was sent."
    or "[CLAW SCAN] File save unavailable; report is in getgenv().CLAW_SLOT_SCAN")
return result

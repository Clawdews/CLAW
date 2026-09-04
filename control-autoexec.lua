-- One public startup file for every paired account. No keys belong here.
local env = getgenv()
if env.CLAW_AUTOEXEC_LOADING or env.CLAW_CONTROL then return end
env.CLAW_AUTOEXEC_LOADING = true

local ok = pcall(function()
    local Players = game:GetService("Players")
    for _ = 1, 240 do
        if Players.LocalPlayer and game.PlaceId > 0 then break end
        task.wait(0.25)
    end
    if not Players.LocalPlayer or game.PlaceId <= 0 then
        warn("[CLAW] Roblox is still loading. Run the public loader when the menu appears.")
        return
    end

    -- The character menu and the two supported Luminants only.
    local places = { [4111023553] = true, [6473861193] = true, [6032399813] = true }
    if not places[game.PlaceId] or env.CLAW_CONTROL then return end

    local Http = game:GetService("HttpService")
    local url = "https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"
    local source
    for attempt = 1, 3 do
        local downloaded, body = pcall(function()
            return game:HttpGet(url .. "?cache=" .. Http:GenerateGUID(false))
        end)
        if downloaded and type(body) == "string" and #body > 0 and #body <= 1048576 then
            source = body
            break
        end
        if attempt < 3 then task.wait(attempt * 2) end
    end
    if not source then
        warn("[CLAW] Could not download the loader after 3 attempts. Check your connection, then run the same public loader.")
        return
    end
    local chunk = loadstring(source, "@CLAW/launcher-beta.lua")
    if not chunk then
        warn("[CLAW] The downloaded loader could not compile. Run the public loader again after the release is corrected.")
        return
    end
    -- Do not repeat pairing or game actions if startup itself fails.
    if not env.CLAW_CONTROL then chunk() end
end)

env.CLAW_AUTOEXEC_LOADING = nil
if not ok then
    warn("[CLAW] Startup stopped. Saved pairings were not reset. Run the public loader manually to see the setup error.")
end

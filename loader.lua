-- CLAW's public distribution contains no GitHub token or private timing data.
local environment = getgenv and getgenv() or _G
local distributionURL = environment.CLAW_DIST_URL
	or "https://raw.githubusercontent.com/Clawdews/CLAW/main/dist/ClawMark.lua"

local source = game:HttpGet(distributionURL)
local chunk, compileError = loadstring(source, "@CLAW/ClawMark.lua")
assert(chunk, compileError)

return chunk()

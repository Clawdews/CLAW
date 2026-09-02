-- CLAW intentionally does not contain a GitHub token.
-- Set this to a secret-free URL that serves dist/AnimationLab.lua.
local environment = getgenv and getgenv() or _G
local distributionURL = environment.CLAW_DIST_URL

assert(
	type(distributionURL) == "string" and distributionURL ~= "",
	"Set getgenv().CLAW_DIST_URL to the published CLAW bundle URL first."
)

local source = game:HttpGet(distributionURL)
local chunk, compileError = loadstring(source, "@CLAW/AnimationLab.lua")
assert(chunk, compileError)

return chunk()

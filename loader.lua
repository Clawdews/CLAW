-- CLAW's public distribution contains no GitHub token or private timing data.
local environment = getgenv and getgenv() or _G
local distributionURL = environment.CLAW_DIST_URL
	or "https://raw.githubusercontent.com/Clawdews/CLAW/main/dist/ClawMark.lua"

local function traceback(message)
	local handler = debug and debug.traceback
	return type(handler) == "function" and handler(tostring(message), 2) or tostring(message)
end

local function notify(title, message)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = title,
			Text = string.sub(tostring(message), 1, 240),
			Duration = 10,
		})
	end)
end

local success, result = xpcall(function()
	local separator = string.find(distributionURL, "?", 1, true) and "&" or "?"
	local resolvedURL = distributionURL .. separator .. "claw_cache=" .. tostring(os.time())
	local source = game:HttpGet(resolvedURL)
	assert(type(source) == "string" and #source > 1024, "CLAW bundle download was empty or incomplete")

	local chunk, compileError = loadstring(source, "@CLAW/ClawMark.lua")
	assert(chunk, compileError)
	return chunk()
end, traceback)

environment.CLAW_BOOT_STATUS = {
	ok = success,
	timestamp = os.time(),
	detail = success and "loaded" or tostring(result),
}

if success then
	print("[CLAW] CLAW MARK loader completed")
	notify("CLAW MARK", "Newest public build loaded.")
	return result
end

warn("[CLAW] loader failed:\n" .. tostring(result))
notify("CLAW MARK FAILED", result)
error(result, 0)

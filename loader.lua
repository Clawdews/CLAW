-- CLAW's public distribution contains no GitHub token or private timing data.
local environment = getgenv and getgenv() or _G
local HttpService = game:GetService("HttpService")
local repository = "Clawdews/CLAW"
local fallbackRef = "43900510ddea3ae2d4280b500e53e473be8c13c3"

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

local function cacheBust(url)
	local separator = string.find(url, "?", 1, true) and "&" or "?"
	return url .. separator .. "claw_cache=" .. HttpService:GenerateGUID(false)
end

local function resolveDistribution()
	if type(environment.CLAW_DIST_URL) == "string" and environment.CLAW_DIST_URL ~= "" then
		return cacheBust(environment.CLAW_DIST_URL), "override"
	end

	local referenceURL = "https://api.github.com/repos/" .. repository .. "/git/ref/heads/main"
	local okReference, referenceBody = pcall(function()
		return game:HttpGet(cacheBust(referenceURL))
	end)
	if okReference and type(referenceBody) == "string" then
		local okDecode, reference = pcall(HttpService.JSONDecode, HttpService, referenceBody)
		local sha = okDecode and reference and reference.object and reference.object.sha
		if type(sha) == "string" and #sha == 40 and string.match(sha, "^%x+$") then
			return "https://raw.githubusercontent.com/" .. repository .. "/" .. sha .. "/dist/ClawMark.lua", sha
		end
	end

	-- This immutable fallback is the compiler-verified v0.3.8 baseline with
	-- state-aware dodge fallback, native roll cancellation, and clear failures.
	return "https://raw.githubusercontent.com/" .. repository .. "/" .. fallbackRef .. "/dist/ClawMark.lua", fallbackRef
end

local resolvedRef
local downloadedBytes = 0
local timingBytes = 0
local timingDetail = "not attempted"
local success, result = xpcall(function()
	local resolvedURL
	resolvedURL, resolvedRef = resolveDistribution()
	local source = game:HttpGet(resolvedURL)
	downloadedBytes = type(source) == "string" and #source or 0
	assert(type(source) == "string" and #source > 1024, "CLAW bundle download was empty or incomplete")

	environment.CLAW_DISTRIBUTION_REF = resolvedRef
	environment.CLAW_TIMINGS_JSON = nil
	local timingURL = "https://raw.githubusercontent.com/" .. repository .. "/" .. resolvedRef .. "/data/lycoris-timings.json"
	local timingOK, timingResult = pcall(function()
		return game:HttpGet(cacheBust(timingURL))
	end)
	if timingOK and type(timingResult) == "string" and #timingResult > 1024 then
		environment.CLAW_TIMINGS_JSON = timingResult
		timingBytes = #timingResult
		timingDetail = "loaded"
	else
		timingDetail = timingOK and "empty or incomplete" or tostring(timingResult)
		warn("[CLAW] timing database unavailable; generic animation defense remains active:", timingDetail)
	end

	local chunk, compileError = loadstring(source, "@CLAW/ClawMark.lua")
	assert(chunk, compileError)
	return chunk()
end, traceback)

environment.CLAW_BOOT_STATUS = {
	ok = success,
	timestamp = os.time(),
	detail = success and "loaded" or tostring(result),
	ref = resolvedRef,
	bytes = downloadedBytes,
	timingBytes = timingBytes,
	timingDetail = timingDetail,
	timingSource = environment.CLAW_TIMING_STATUS and environment.CLAW_TIMING_STATUS.source,
	timingCount = environment.CLAW_TIMING_STATUS and environment.CLAW_TIMING_STATUS.count or 0,
}

if success then
	print("[CLAW] CLAW MARK loader completed", resolvedRef, downloadedBytes, "timings", timingBytes)
	local timingMessage = environment.CLAW_BOOT_STATUS.timingCount > 0
		and (tostring(environment.CLAW_BOOT_STATUS.timingCount) .. " timings ready.")
		or "Generic defense fallback ready."
	notify("CLAW MARK", "Build " .. string.sub(resolvedRef or "unknown", 1, 7) .. " loaded; " .. timingMessage)
	return result
end

warn("[CLAW] loader failed:\n" .. tostring(result))
notify("CLAW MARK FAILED", result)
error(result, 0)

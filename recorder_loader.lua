local HttpService = game:GetService("HttpService")
local url = "https://raw.githubusercontent.com/Clawdews/CLAW/main/tools/ClawRecorder.lua"
url = url .. "?claw_cache=" .. HttpService:GenerateGUID(false)
local source = game:HttpGet(url)
assert(type(source) == "string" and #source > 1024, "CLAW Recorder download was empty or incomplete")
local chunk, compileError = loadstring(source, "@CLAW/ClawRecorder.lua")
assert(chunk, compileError)
return chunk()

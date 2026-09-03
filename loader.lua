local HttpService = game:GetService("HttpService")
local url = "https://raw.githubusercontent.com/Clawdews/CLAW/main/relay.lua"
url = url .. "?claw_cache=" .. HttpService:GenerateGUID(false)

local source = game:HttpGet(url)
assert(type(source) == "string" and #source > 1024, "CLAW RELAY download was empty or incomplete")
local chunk, compileError = loadstring(source, "@CLAW/relay.lua")
assert(chunk, compileError)
return chunk()

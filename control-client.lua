-- Put your private CLAW_CONTROL_CONFIG before this loader in Volt autoexec.
local url = "https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/dist/control-beta.lua"
local source = game:HttpGet(url .. "?cache=" .. game:GetService("HttpService"):GenerateGUID(false))
local chunk, failure = loadstring(source, "@CLAW/control/client.lua")
assert(chunk, failure)
return chunk()

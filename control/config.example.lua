-- PRIVATE SETUP: copy into your own Volt autoexec file; never commit real pairing keys.
-- Every account can use the same file. Keys are selected by the actual local UserId.
getgenv().CLAW_CONTROL_CONFIG = {
	Endpoint = "https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev",
	Accounts = {
		["MAIN_ROBLOX_USER_ID"] = "PAIRING_KEY_FROM_DISCORD",
		["ALT_ROBLOX_USER_ID"] = "PAIRING_KEY_FROM_DISCORD",
	},
	-- Opt in only after the menu-to-main test passes. Does not bypass combat/respawn restrictions.
	AllowMenuReturn = false,
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/discord-control/control-client.lua?t=" .. tostring(os.time())))()

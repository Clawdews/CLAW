# CLAW

Deepwoken alt control and loot notifications.

## Alt bringer

Run this on each alt. Replace the username with your main's Roblox username. Everyone must already be in the same server.

```lua
getgenv().CLAW_RELAY_CONFIG = {
    ControllerName = "YOUR_MAIN_USERNAME",
    TrustedUserIds = {},
    ProximitySafety = false,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loader.lua?t=" .. tostring(os.time())))()
```

Use `alts bring` from the main. Default speed is 200 horizontal and 24 vertical.

| Command | Action |
| --- | --- |
| `alts bring` | Bring the alts |
| `alts stop` | Stop movement |
| `alts speed 200` | Set horizontal speed |
| `alts yspeed 24` | Set vertical speed |
| `alts menu` | Return to the game menu |
| `alts safety on/off` | Toggle proximity exit |
| `alts status` | Show current settings |

Safety starts off. Add trusted alt IDs before enabling it. Travel is direct and can still be interrupted by the game.

## Loot notifier

Fill in your Discord webhook and run this before PR:

```lua
getgenv().CLAW_LOOT_CONFIG = {
    WEBHOOK_URL = "",
    USER_ID = "",
    PING_ITEMS = { ["ether core"] = true },
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loot.lua?t=" .. tostring(os.time())))()
```

It watches PR's `Looted:` messages and batches repeated items. Keep the filled configuration private. Do not load a second copy if PR already starts it.

## Discord control

[CLAW Control](https://github.com/Clawdews/CLAW/tree/control-beta/control) pairs alts, reads character cards and follows the main's exact server.

[Install](https://discord.com/oauth2/authorize?client_id=1545435882784559124&scope=applications.commands&integration_type=1) · [Setup](https://github.com/Clawdews/CLAW/blob/control-beta/docs/CONTROL-SETUP.md) · [Privacy](docs/PRIVACY.md)

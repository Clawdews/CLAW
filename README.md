# CLAW

Alt control and loot notifications for Deepwoken. Two separate scripts; use whichever you need.

## Alt manager

Run this on each alt. Replace the username with your main's exact username, not its display name. All accounts need to be in the same server.

```lua
getgenv().CLAW_RELAY_CONFIG = {
    ControllerName = "YOUR_MAIN_USERNAME",
    BringSpeed = 40, -- studs per second; lower this for slower travel
    BringVerticalSpeed = 16,
    TrustedUserIds = {},
    ProximitySafety = false,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loader.lua?t=" .. tostring(os.time())))()
```

Type commands in chat from your main:

| Command | What it does |
| --- | --- |
| `;alts bring` | Moves alts to positions around you |
| `;alts bring 5` | Requests a slower trip; speed limits still apply |
| `;alts speed 25` | Sets the travel speed limit, including during a trip |
| `;alts stop` | Stops movement |
| `;alts phase on` / `;alts phase off` | Toggles noclip |
| `;alts menu` | Requests a return to the main menu |
| `;alts safety on` / `;alts safety off` | Toggles proximity auto-log |
| `;alts status` / `;alts help` | Prints to each alt's console |

Proximity safety starts off. Before turning it on, add your other alts' numeric Roblox UserIds to `TrustedUserIds`. Your main is already trusted. By default, an untrusted player within 80 studs for two seconds triggers a menu request.

You can use `ControllerUserId` instead of `ControllerName`.

Bring uses velocity-based flight with acceleration and braking, not a fixed three-second teleport tween. Default limits are 40 studs/s overall and 16 studs/s vertically. `bring 5` requests a minimum travel time, not a deadline that overrides those limits. The destination is your position when you send the command; this is not continuous follow.

Flight temporarily changes the air controller, ground sensing, and collisions, then restores them on stop. It releases a `BodyPosition` pin under the character's head during flight; set `ReleaseHeadPin = false` to disable that behavior. Other options are `BringAcceleration` (80), `BringSeconds` (3), and `BringTimeout` (300). Stops include missing characters, a removed mover, no progress, repeated head pins, and large unexpected position changes. `status` prints the last movement result on each alt.

Test over a short distance first. This is direct travel, not obstacle-aware navigation, and isn't a guarantee against anti-air attacks or server corrections. No server joining or forced respawn yet.

[Alt manager source](relay.lua)

## Loot webhook

Watches PR's `Looted:` notifications and sends them to Discord. Repeated items are batched together, starred loot gets a gold embed, and chosen items can ping you.

Run this once before PR, with your webhook URL filled in. Keep that URL private.

```lua
getgenv().CLAW_LOOT_CONFIG = {
    WEBHOOK_URL = "", -- paste your Discord webhook URL here
    USER_ID = "",     -- your Discord user ID, if you want pings
    PING_ITEMS = {
        ["ether core"] = true, -- lowercase item names
    },
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loot.lua?t=" .. tostring(os.time())))()
```

Messages include your Roblox username, item names, a session item count, a timestamp, and a shortened server ID. Optional settings: `USERNAME`, `AVATAR`, `FLUSH_EVERY` (default 2 seconds), `BATCH_SIZE` (default 12), and `DEBUG_SCAN` (default false).

This is the standalone notifier from the working PR setup, with private config and the PR loader removed. It doesn't launch PR. If you're already running that notifier, don't load a second copy.

[Loot notifier source](loot.lua)

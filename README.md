# CLAW

Alt control and loot notifications for Deepwoken. Two separate scripts; use whichever you need.

## Discord control beta

This branch also contains [CLAW Control](control/README.md): a Discord app and paired client for exact-server following, with a separate account group for each Discord user. See the [setup guide](docs/CONTROL-SETUP.md) and [release checklist](docs/CONTROL-RELEASE.md). It is not a public hosted release yet; the existing live setup remains separate. The stable scripts below are unchanged.

## Alt manager

Run this on each alt. Replace the username with your main's exact username, not its display name. All accounts need to be in the same server.

```lua
getgenv().CLAW_RELAY_CONFIG = {
    ControllerName = "YOUR_MAIN_USERNAME",
    BringSpeed = 200, -- horizontal (XZ) studs/s; configurable 5–200
    BringVerticalSpeed = 24, -- independent vertical (Y) studs/s; configurable 2–60
    TrustedUserIds = {},
    ProximitySafety = false,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loader.lua?t=" .. tostring(os.time())))()
```

Once loaded, type **`alts bring`** in chat from your main. That applies 200 horizontal / 24 vertical with no timed pacing, even if your old config has different speeds. No setup commands needed. The older `;alts` prefix still works too.

| Command | What it does |
| --- | --- |
| `alts bring` | Applies the 200 / 24 preset and moves alts to positions around you |
| `alts bring 5` | Uses your current speeds with optional distance / 5 seconds pacing |
| `alts bring 0` | Uses your current speeds with no timed pacing |
| `alts speed 200` | Sets horizontal speed (5–200 studs/s), including during a trip |
| `alts yspeed 24` | Sets vertical speed independently (2–60 studs/s) |
| `alts stop` | Stops movement |
| `alts phase on` / `alts phase off` | Toggles noclip |
| `alts menu` | Requests a return to the main menu |
| `alts safety on` / `alts safety off` | Toggles proximity auto-log |
| `alts status` / `alts help` | Prints to each alt's console |

Proximity safety starts off. Before turning it on, add your other alts' numeric Roblox UserIds to `TrustedUserIds`. Your main is already trusted. By default, an untrusted player within 80 studs for two seconds triggers a menu request.

You can use `ControllerUserId` instead of `ControllerName`.

Bring uses velocity-based flight with acceleration and braking. Plain `bring` always selects 200 studs/s horizontally and 24 studs/s vertically, with pacing off; horizontal arrival doesn't slow the remaining vertical travel. For custom speeds, use the speed commands followed by `bring 0`. `bring 5` limits each axis to its starting distance / 5 seconds as well as your chosen speeds; acceleration, braking, and arrival tolerance affect the actual trip time. Repeating `bring` updates the destination without restarting the flight or zeroing velocity. The destination is your position when you send the command; this is not continuous follow. Other config settings are unchanged by the preset.

Flight temporarily changes the air controller, ground sensing, and collisions, then restores them on stop. It releases a `BodyPosition` pin under the character's head during flight; set `ReleaseHeadPin = false` to disable that behavior. Other options are `BringAcceleration` (80 studs/s² per axis, configurable 10–240), `BringSeconds` (0, pacing off), and `BringTimeout` (300). Stops include missing characters, a removed mover, no progress, repeated head pins, and large unexpected position changes. `status` prints configured speeds, current measured XZ/Y speeds, pacing, and the last movement result on each alt. High limits won't necessarily be reached on short trips because acceleration and braking still apply.

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

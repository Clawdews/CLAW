# CLAW

Alt control and loot notifications for Deepwoken.

## Alt manager

Run on each alt. Set your main's exact username, not its display name. All accounts must already be in the same server.

```lua
getgenv().CLAW_RELAY_CONFIG = {
    ControllerName = "YOUR_MAIN_USERNAME",
    TrustedUserIds = {},
    ProximitySafety = false,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loader.lua?t=" .. tostring(os.time())))()
```

Type `alts bring` from your main. It uses 200 studs/s horizontally and 24 vertically, with pacing off. Repeating it updates the destination without restarting the flight.

| Command | Action |
| --- | --- |
| `alts bring` | Bring alts using the 200 / 24 preset |
| `alts bring 0` | Bring using your current speeds |
| `alts bring 5` | Use current speeds with five-second pacing |
| `alts speed 200` | Set horizontal speed, 5–200 |
| `alts yspeed 24` | Set vertical speed, 2–60 |
| `alts stop` | Stop movement |
| `alts phase on/off` | Toggle noclip |
| `alts menu` | Request the main menu |
| `alts safety on/off` | Toggle proximity exit |
| `alts status` / `alts help` | Print status or commands |

The older `;alts` prefix still works. `ControllerUserId` can replace `ControllerName`.

Proximity exit starts off. Add your other alts' numeric IDs to `TrustedUserIds` before enabling it. Your main is trusted automatically. An untrusted player within 80 studs for two seconds triggers the normal menu request.

Travel is direct, not obstacle-aware. Acceleration and braking mean short trips may not reach the configured speed. Flight restores its movement/collision changes when stopped. Test a short trip first; server corrections and anti-air attacks can still interrupt it.

[Source](relay.lua)

## Loot notifications

Run once before PR. Fill in your webhook URL and keep it private.

```lua
getgenv().CLAW_LOOT_CONFIG = {
    WEBHOOK_URL = "",
    USER_ID = "",
    PING_ITEMS = {
        ["ether core"] = true,
    },
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loot.lua?t=" .. tostring(os.time())))()
```

Watches PR's `Looted:` notifications. Repeated items are batched; starred loot gets a gold embed. `USER_ID` and lowercase `PING_ITEMS` are optional.

Messages include your username, items, session count, time and shortened server ID. Options: `USERNAME`, `AVATAR`, `FLUSH_EVERY` (2 seconds), `BATCH_SIZE` (12), `DEBUG_SCAN` (false).

This does not launch PR. If your current PR setup already includes the notifier, don't load a second copy.

[Source](loot.lua)

## Discord controller

[CLAW Control](https://github.com/Clawdews/CLAW/tree/control-beta/control) pairs your accounts with Discord and follows your main's exact server. Character selection, private groups and recovery controls are in closed beta. Public onboarding is not open yet.

## Repository updates

[Connect a Discord channel](docs/DISCORD-UPDATES.md) for one-line push notifications.

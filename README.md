# CLAW RELAY

CLAW RELAY is a small, no-UI controller for moving and managing the user's own alternate accounts from one trusted Roblox account. It contains no combat automation, animation recorder, timing database, or Project Rain code.

The former CLAW MARK v0.4.7 source remains archived under the `legacy-combat-v0.4.7` tag. The existing local Project Rain loot notifier remains private, ignored, and untouched.

## Start each follower account

Set the controller to the exact username of the main account, then execute the loader on every alt:

```lua
getgenv().CLAW_RELAY_CONFIG = {
    ControllerName = "ExactMainUsername",

    -- Optional safety roster. Numeric UserIds are recommended.
    TrustedUserIds = {},
    ProximitySafety = false,
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/main/loader.lua?t=" .. tostring(os.time())))()
```

`ControllerUserId` may be used instead of `ControllerName` and takes priority when both are supplied. The configured controller account deliberately does not start the follower runtime.

## Controller commands

Type these in chat from the configured controller account while the alts share its server:

```text
;alts bring
;alts bring 5
;alts stop
;alts phase on
;alts phase off
;alts menu
;alts safety on
;alts safety off
;alts status
;alts help
```

`bring` assigns each alt a stable formation position instead of stacking every character on one point. Movement noclip is temporary and restores the character's collision state afterward.

Proximity safety is disabled by default. Before enabling it, list the UserIds of the main account and every alt in `TrustedUserIds`. An unlisted player who stays within `ProximityDistance` for `ProximityGraceSeconds` causes that alt to request the main menu.

CLAW RELAY does not currently force a respawn or select a Deepwoken server. Deepwoken's instant-respawn behavior and its lobby `StartMenu.PickServer` flow are game-specific; they must not be replaced with generic Roblox respawn or JobId assumptions.

# Animation transport experiment

The working chat relay is saved as [`relay-chat-v0.2.2`](https://github.com/Clawdews/CLAW/tree/relay-chat-v0.2.2). The normal loader still uses `main`. Nothing here changes its flight code or dispatches alt commands.

## What we're checking

Uni suggested animation playback with `httpid=0%s`. We don't yet have his full playback line. The probe's candidate URL, `http://www.roblox.com/asset/?id=0%s`, is an interpretation of that shorthand, not a confirmed implementation.

Roblox documents replication of animations started on the owning player's client when using the existing, server-created Animator. That does **not** establish that an invalid asset ID or extra text will survive loading and replication. [Animator documentation](https://create.roblox.com/docs/reference/engine/classes/Animator/LoadAnimation).

This probe sends one marked ping when you click a button. The receiver watches only the configured main's Animator. It never moves, logs out, changes collision, hooks input, plays attacks, or runs commands from animation text. The panel also counts ordinary animation events so we can distinguish a missing listener from a missing ping.

## One main + one alt test

Keep both characters nearby in the same server. Load the receiver on the alt first. If that alt already has `CLAW_RELAY_CONFIG` with your main's name or UserId, it is reused:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = { Role = "receiver" }
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/animation-transport/experiments/animation_probe.lua?t=" .. tostring(os.time())))()
```

Without an existing relay config, include `ControllerName = "YOUR_MAIN_USERNAME"` in that table.

On your main:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = { Role = "sender" }
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/animation-transport/experiments/animation_probe.lua?t=" .. tostring(os.time())))()
```

Click **SEND TEST PING** once on the main. Check the **alt's** panel, not just the main's console:

- `RECEIVED PING` on the alt with the same short token: evidence that this candidate reached that alt.
- `local echoes` on the main: only local playback was observed; not delivery confirmation.
- `seen` rises on the alt during normal movement but no ping arrives: animation observation works, but this candidate hasn't demonstrated transport.
- Load/play error or no remote ping: the proposed format is unproven. Record what both panels show; don't wire this into movement or substitute random combat animations.

The test allows at most five attempts per load, at least three seconds apart, and cleans up only its own temporary track. Close the panel to unload it. `AnimationIdTemplate` can override the candidate if further investigation establishes another format; it must contain exactly one `%s` placeholder. `ShowPanel = false` is available for local tests. This work does not depend on getting another reply from Uni.

## Before replacing chat

1. Confirm the exact format and remote delivery on two clients. Test repeat delivery, movement, distance/streaming, and respawn.
2. Add a bounded command format: version, session, sequence, allowlisted action and validated arguments. Bind identity to the observed player, not a claimed name in the payload.
3. Reject duplicates/stale messages and cap send/receive rates. Decide how acknowledgments and retry limits work from measured behavior.
4. Connect accepted commands to the existing relay methods, leaving the working flight implementation alone. Add main-account buttons/hotkeys so sending doesn't depend on chat.
5. Keep chat selectable until live testing shows the new transport is reliable.

Animation playback is not a private channel. Other observers may see it; no secrets belong in the payload. This is an experiment, not a claim that animation transport is more reliable yet.

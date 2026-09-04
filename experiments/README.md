# Animation transport probe

An unconfirmed transport experiment. It sends a marked ping through animation playback and watches for that ping on another client. It does not dispatch alt commands or change flight.

The proposed format is `httpid=0%s`. This probe interprets it as `http://www.roblox.com/asset/?id=0%s`; that interpretation has not been verified. Normal animation replication does not prove that an invalid asset ID or appended text will replicate.

The working chat relay remains on `main`, with the earlier version saved at [relay-chat-v0.2.2](https://github.com/Clawdews/CLAW/tree/relay-chat-v0.2.2).

## Test with one main and one alt

Keep both characters nearby in the same server. Load the receiver on the alt first:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = {
    Role = "receiver",
    ControllerName = "YOUR_MAIN_USERNAME",
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/animation-transport/experiments/animation_probe.lua"))()
```

On the main:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = { Role = "sender" }
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/animation-transport/experiments/animation_probe.lua"))()
```

Click **SEND TEST PING** once. Read the **alt's** panel:

| Result | Meaning |
| --- | --- |
| `RECEIVED PING` with the same token | This candidate reached the alt |
| Only a local echo on the main | No remote delivery confirmed |
| Ordinary animations counted, no ping | Listener works; candidate transport is unconfirmed |
| Load/play error | Candidate could not be played |

The receiver watches only the configured main's Animator. The probe permits five attempts per load, at least three seconds apart. Closing the panel disconnects it and cleans up its own temporary track.

An existing `CLAW_RELAY_CONFIG` can supply the controller identity. `AnimationIdTemplate` accepts a different candidate with exactly one `%s` placeholder; `ShowPanel = false` hides the panel.

Before using this for commands, delivery must be tested across distance, streaming, movement and respawn. Command framing also needs identity checks, sequence numbers, duplicate rejection and bounded retries.

Animation playback is observable by other clients. Never send keys or other secrets through it. [Roblox Animator reference](https://create.roblox.com/docs/reference/engine/classes/Animator/LoadAnimation).

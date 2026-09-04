# Animation transport probe

Small test for marked data sent through animation playback. It is not an alt-control transport.

Load the receiver on the alt:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = {
    Role = "receiver",
    ControllerName = "YOUR_MAIN_USERNAME",
}
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/animation-transport/experiments/animation_probe.lua"))()
```

Load the sender on the main:

```lua
getgenv().CLAW_ANIMATION_PROBE_CONFIG = { Role = "sender" }
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/animation-transport/experiments/animation_probe.lua"))()
```

Click **SEND TEST PING**. A matching `RECEIVED PING` on the alt confirms that attempt. A local echo or ordinary animation event does not.

Keep both accounts nearby. Do not send keys or private data through animation playback.

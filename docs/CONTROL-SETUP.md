# Set up your accounts

These instructions apply to the shared-service beta after its host enables your Discord user. The existing private live service has different commands; do not replace a working setup with this beta by accident.

## Once per account

1. Install the host's CLAW Discord app, then run `/claw setup`. In closed beta, the host must enable your Discord User ID first.
2. Run `/claw enroll account:<Roblox UserId>` for your main and each alt. Use the numeric profile ID, not a username or display name.
3. On each matching Roblox account, execute its private pairing snippet from Discord once. It checks the local account, verifies the key and saves it to that executor's workspace. Never share this snippet.
4. Put the following **public** loader in autoexec. It reads only the current account's pairing file. Unlike the enrollment snippet, this line is safe to share:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/dist/launcher-beta.lua"))()
```

Run the loader once after pairing, or restart the client. Do not run the beta and legacy control loaders together. Keep unrelated working scripts intact; disable competing automatic slot selection/server-hopping during the first test.

## Choose the characters

Load the intended character once with the client running, then use `/claw slots account:...`. The service learns its actual DataSlot and region. The slot ID can be a letter or another game-assigned string; do not guess a number.

```text
/claw allow-slot account:<alt UserId> slot:<observed slot> enabled:true
/claw prefer-slot account:<alt UserId> region:<region> slot:<observed slot>
```

The preference is only necessary when several approved characters share a region. Approvals persist. Observations expire after 24 hours; load a character again to refresh its location. The client checks the region returned by selection before requesting a join, even if its earlier observation matched.

Only Eastern and Etrean are mapped. Depths, layers and other places are not interchangeable and will not be guessed. Until the real menu parser is validated, loading a character once is required to discover it; the scanner alone does not approve or confirm anything.

## Follow your main

Keep the main in the world and return one alt to character selection:

```text
/claw main account:<main UserId>
/claw follow enabled:true
/claw status
```

Changing the main pauses following until you enable it again. A fresh main destination, an approved compatible character and a working save mechanism are required before an alt acts.

`VERIFIED` means the paired client checked the expected account, character, experience, place, exact server and main's presence after joining. `WITH_MAIN` means it was already there. Discord relays those client reports; it does not independently observe Roblox.

Automatic exits are off by default. To opt in after a successful menu test, change only `AllowMenuReturn` to `true` in that account's private `CLAW_PAIRINGS/<UserId>.json` and reload. Treat the rest of that file as a password. This requests the normal return-to-menu flow; it does not bypass combat restrictions or force a respawn.

## Everyday controls

| Command | What it does |
| --- | --- |
| `/claw status` | Show your accounts, main and follow state |
| `/claw follow enabled:false` | Stop new follow requests once received |
| `/claw retry account:...` | Allow one new attempt after a stopped attempt |
| `/claw allow-slot ... enabled:false` | Remove permission to use a character |
| `/claw rotate account:...` | Replace a lost key; disconnects the old client |
| `/claw revoke account:...` | Remove one account's stored enrollment and permission |

Pause/revocation cannot undo a teleport Roblox already accepted. If a key leaks, revoke or rotate it in Discord; deleting its local file alone does not revoke it.

## If an alt waits

| Status | Next step |
| --- | --- |
| `AUTH_FAILED` | Check the actual account and its private pairing; use rotate if the key is lost |
| `WAITING_MAIN` | Keep the main loaded and connected; destinations expire after 35 seconds |
| `WAITING_MENU` | Return the alt to character selection; no Discord retry is needed just for this |
| `NO_COMPATIBLE_SLOT` | Load and approve a character in the main's region |
| `CHOOSE_PREFERRED_SLOT` | Choose which of the matching approved characters to use |
| `REGION_MISMATCH` | The selection response disagreed; refresh the character's location before retrying |
| `ATTENTION` | Read the saved reason; fix it before `/claw retry` |
| `OFFLINE` | Check Roblox, executor, loader and network; Discord cannot launch a closed process |

Beta attempt reports are in `CLAW_CONTROL_BETA/<DiscordUserId>-<RobloxUserId>.json`, separate from pairing keys. Share a status report privately, not the contents of `CLAW_PAIRINGS`.

## Read-only menu capture

At the character menu, run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/control-beta/slot-scan.lua"))()
```

This reads bounded menu labels/attributes and saves `CLAW_CONTROL/menu-<UserId>.json`. It does not click, select a slot, teleport, send a webhook, or upload the report. Review it before sharing: it may contain character names and locations. `CAPTURED_UNCONFIRMED` is a diagnostic result, not a successful character selection.

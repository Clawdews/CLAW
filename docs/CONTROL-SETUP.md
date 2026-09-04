# Set up your accounts

**Closed beta:** use this guide only after the host gives you access. Do not replace a working older controller with this one yet.

You pair each account once, choose which characters it may use, then tell your alts to follow your main. You do not need your own website, Cloudflare account or bot token.

The **public loader** is safe to share. The **pairing snippet** contains your account's private key: treat it like a password. [What to keep private](PRIVACY.md).

## 1. Pair your accounts

1. Install the host's CLAW Discord app, then run `/claw setup`. In closed beta, the host must enable your Discord User ID first.
2. Run `/claw enroll account:<Roblox UserId>` for your main and each alt. `UserId` means the number in that account's Roblox profile URL, not its username. Replace the `<...>` text with that number; do not type the brackets.
3. On each matching Roblox account, execute its private pairing snippet from Discord once. It checks the local account, verifies the key and saves it to that executor's workspace. Never share this snippet.
4. Put the following **public** loader in autoexec. It reads only the current account's pairing file. Unlike the enrollment snippet, this line is safe to share:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"))()
```

The private pairing snippet already starts the client. Later, autoexec uses just the public line. Do not run the beta and legacy control loaders together. Keep unrelated working scripts intact; disable competing automatic slot selection/server-hopping during the first test.

## 2. Choose which characters the alts may use

Leave the paired alt at character selection for about 15 seconds, then use `/claw slots account:...`. Its character cards appear in Discord automatically. They show the slot letter, name, level, race, oath/origin, location, playtime and last played. Use `page:2` to see more.

Nothing is selected just because it appeared in the list. **Allow** means “this alt may use this character.” **Prefer** means “use this one when more than one allowed character fits.” Choose the region shown by the command's menu.

```text
/claw allow-slot account:<alt UserId> slot:<observed slot> enabled:true
/claw prefer-slot account:<alt UserId> region:<region> slot:<observed slot>
```

The preference is only necessary when several approved characters share a region. Approvals persist, but a changed character name, observed level reset or removed slot clears the old permission. Cloud observations expire after 24 hours; reopening the menu refreshes them. Selection requires a complete current local scan and matching cloud character details, then checks the region returned by the game before requesting a join.

Only Eastern and Etrean are mapped. Depths, layers and other places remain visible in the catalog but are not join destinations. A menu observation is labelled as such, not as an in-world verification. Syncing a card never approves it automatically.

## 3. Start following

Keep the main in the world and return one alt to character selection:

```text
/claw main account:<main UserId>
/claw follow enabled:true
/claw status
```

Changing the main pauses following until you enable it again. A fresh main destination, an approved compatible character and a working save mechanism are required before an alt acts.

For a normal later session, let autoexec start the paired clients and check `/claw status`. You do not need to enroll them again. To stop new follow requests, use `/claw follow enabled:false`.

`VERIFIED` means the paired client checked the expected account, character, experience, place, exact server and main's presence after joining. `WITH_MAIN` means it was already there. Discord relays those client reports; it does not independently observe Roblox.

Automatic exits are off by default. After a successful menu test, opt in from Discord with `/claw auto-return account:<alt UserId> enabled:true`. Use `enabled:false` to switch it off, including pending menu confirmations once the client receives the update. It requests the normal return-to-menu flow; it does not bypass combat restrictions or force a respawn. Older explicit local settings remain effective only until a cloud setting overrides them. You no longer need to edit the private pairing file for this option.

## Everyday controls

| Command | What it does |
| --- | --- |
| `/claw status` | Show your accounts, main and follow state |
| `/claw status page:2` | See additional accounts without a truncated report |
| `/claw nickname account:... label:...` | Give an account a readable label; its numeric identity stays visible |
| `/claw auto-return account:... enabled:true` | Opt an account into normal menu return; default off |
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
| `WAITING_SLOT_SCAN` | Leave character selection open until the complete list is readable |
| `WAITING_SLOT_SYNC` | Wait for the current cards to sync, then check approval in Discord |
| `NO_COMPATIBLE_SLOT` | Refresh the menu and approve a character in the main's region |
| `CHOOSE_PREFERRED_SLOT` | Choose which of the matching approved characters to use |
| `REGION_MISMATCH` | The selection response disagreed; refresh the character's location before retrying |
| `ATTENTION` | Read the saved reason; fix it before `/claw retry` |
| `OFFLINE` | Check Roblox, executor, loader and network; Discord cannot launch a closed process |

Beta attempt reports are in `CLAW_CONTROL_BETA/<DiscordUserId>-<RobloxUserId>.json`, separate from pairing keys. Share a status report privately, not the contents of `CLAW_PAIRINGS`.

There are two small persistent files per paired account: its pairing and current attempt state. They are overwritten in place. Normal cloud sync creates no menu-report files or recording history. The separate diagnostic scanner below creates one additional report per account only when you explicitly run it.

## Recover pairing

- **Cannot check/read pairing, or file support required:** fix executor file access first, then rerun the loader. A read failure is not the same as an unpaired account. Do not delete or rotate a working pairing for this error. Volt's [file functions](https://docs.voltbz.net/docs/filesystem) must be available.
- **Pairing file changed during setup:** another setup changed it while authentication was running. Let that setup finish, then rerun only the snippet for this account. The conflicting save is stopped.
- **Key rejected or lost:** use `/claw rotate account:...`, then run the new private snippet on that same Roblox account. A valid existing pairing file is updated for you.
- **Invalid local pairing file:** stop the loader on that account. Get a new private snippet with `/claw rotate`, move only its damaged `CLAW_PAIRINGS/<RobloxUserId>.json` file aside privately, then run the snippet. Leave other accounts' files alone. Never upload the damaged file; it may still contain a key.
- **Could not save and verify pairing:** check executor file access, then rerun the same private snippet. A write may have happened even though verification failed. If it now reports an invalid file, use the recovery step above.
- **Relay unavailable:** wait and retry. Do not rotate keys just because the network is down.

Setup errors intentionally hide raw file and request contents. Send the short error message when asking for help, not the pairing snippet.

## A report you can share

If the beta is running but an alt is stuck, execute this on that account:

```lua
local control = getgenv().CLAW_CONTROL
print(control and control.supportReport and control:supportReport() or "CLAW support report unavailable. Copy the short setup error, or reload the current beta.")
```

Copy only the `CLAW SUPPORT 1` block from the console. It includes the build ID, connection/slot-reading state and a next step. The build ID identifies the code, not your account. The report excludes keys, account IDs, character names, server IDs, endpoint URLs and raw failure details. It creates no file and sends nothing anywhere.

The older `report()` method and saved attempt files are detailed private diagnostics; do not paste those publicly. The short report is for troubleshooting, not proof that Roblox accepted a request.

## Optional menu report

Only use this for troubleshooting; normal cloud sync does not need it.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/slot-scan.lua"))()
```

Run at character selection. It prints each card and overwrites one local report at `CLAW_CONTROL/menu-<UserId>.json`. It reads the slot list only: no clicks, selections, teleports or uploads.

Reports include character names and locations, so review them before sharing. Missing or conflicting fields are flagged, not guessed. Loaded offscreen cards are included; the scanner does not scroll to load more. `CARDS_CAPTURED_UNCONFIRMED` describes the scan, not a verified join.

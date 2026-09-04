# Set up your accounts

**Closed beta:** use this guide only after the host gives you access. Do not replace a working older controller with this one yet.

You pair each account once, choose which characters it may use, then tell your alts to follow your main. You do not need your own website, Cloudflare account or bot token.

The **public loader** is safe to share. The **pairing snippet** contains your account's private key: treat it like a password. [What to keep private](PRIVACY.md).

## Already paired? Start here

Type **`/claw panel`** in Discord. Only you can see it.

1. Choose an account from the dropdown.
2. Click **Characters**. Filter by region or use **Next** to see more.
3. Choose a character to see its details. **Allow character** and **Prefer in this region** both ask you to confirm.
4. Back on **Accounts**, you can choose your main, enable following, or pause it.

You do not need to pair working accounts again. Keep the same public loader below. The panel shows a snapshot: click **Refresh** for an update. Controls expire after 15 minutes; open `/claw panel` again if needed.

### Adding several alts

1. In `/claw panel`, click **Setup → Start alt setup**.
2. Run the private snippet **once** on one account in your executor's shared workspace.
3. Start your other accounts with the same public loader (or run it on accounts already open).
4. In Discord, click **Refresh**. Choose each request and compare its eight-character check code with that account's Roblox console. Confirm only your own matching requests.
5. Pairing finishes on the next check, usually within 30 seconds. Then choose which characters each alt may use.

The setup window lasts 10 minutes. It does not change existing pairings, turn following on, or allow every character. Each account gets its own private key. A username alone is not proof that a request came from your device—check the code too. If an unfamiliar request appears, close setup and start a fresh window.

Accounts must use the same executor workspace for one setup snippet to reach them all. Another device or workspace needs the snippet there too. Roblox must be open and the executor running; Discord cannot launch them. If the window expires, open a new one and rerun the same public loader on unfinished accounts. Single-account enrollment below still works.

## 1. Pair your accounts

1. Install the host's CLAW Discord app, then run `/claw panel`. In closed beta, the host must enable your Discord User ID first.
2. Run `/claw enroll account:<username>` for your main and each alt. Enter the actual Roblox username, not the display name; do not type the brackets. Numeric UserIds still work. All `account` fields accept either.
3. On each matching Roblox account, execute its private pairing snippet from Discord once. It checks the local account, verifies the key and saves it to that executor's workspace. Never share this snippet.
4. Put the following **public** loader in autoexec. It reads only the current account's pairing file. Unlike the enrollment snippet, this line is safe to share:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"))()
```

Username lookup uses Roblox’s public API. Capitalization and a leading `@` are fine. Use the current username; former names and display names are not selected. If a username consists only of digits, prefix it with `@` so it is not treated as an ID. If lookup fails, nothing is changed; retry or use the numeric UserId. Replies show the resolved username and ID so you can check the account. Existing pairings do not need to be redone.

The private pairing snippet already starts the client. Later, autoexec uses just the public line. Do not run the beta and legacy control loaders together. Keep unrelated working scripts intact; disable competing automatic slot selection/server-hopping during the first test.

### One startup file in Volt

Save [control-autoexec.lua](../control-autoexec.lua) in Volt's `autoexec` folder as `CLAW Control.luau`. Use either this file or the public line above, not both. This file contains no private keys. It waits for the local player, retries a failed download up to three times, and starts only in the character menu, Eastern or Etrean. It does not restart an already-running controller.

Every instance using that same Volt installation and workspace uses this one file. You do **not** need one copy per alt. If you use another computer or a separate executor workspace, set it up there too; keys do not download from Discord automatically. Keep existing pairings private rather than posting them with the loader.

For **new** alts, use the setup window above or `/claw enroll account:<username>`. They then use the existing shared startup file on later joins. Choose the characters they may use in Discord; the loader never approves every character for you.

### What happens next time?

1. Open your main and alts with Volt attached. Autoexec starts CLAW; you paste nothing.
2. Enter the world on your selected main. Leave the alts at character selection.
3. If Follow is still on, the alts use their approved compatible characters to join the main.

The same process applies after a server change. Pairing files stay on your device; your selected main, Follow setting, approvals and preferences stay with your private Discord group. These are saved settings, not instructions you must repeat every session. The loader downloads the current beta at startup; it does not hot-reload an already-running client.

An alt already in another world waits for the menu unless you opted that account into `/claw auto-return`. This remains off by default. Closing Roblox still closes the client; this script does not start Roblox or attach Volt for you.

## 2. Choose which characters the alts may use

Leave the paired alt at character selection for about 15 seconds, then open **Characters** in `/claw panel`, or use `/claw slots account:...`. Cards show the slot letter, name, power, race, oath/origin, region and permission. Choose a card for playtime, last played and the last scan time. Use **Next** or the region filter to find another character.

Nothing is selected just because it appeared in the list. **Allow** means “this alt may use this character.” **Prefer** means “use this one when more than one allowed character fits.” Choose the region shown by the command's menu.

```text
/claw allow-slot account:<alt username> slot:<observed slot> enabled:true
/claw prefer-slot account:<alt username> region:<region> slot:<observed slot>
```

The preference is only necessary when several approved characters share a region. Approvals persist, but a changed character name, observed level reset or removed slot clears the old permission. Cloud observations expire after 24 hours; reopening the menu refreshes them. Selection requires a complete current local scan and matching cloud character details, then checks the region returned by the game before requesting a join.

Only Eastern and Etrean are mapped. Depths, layers and other places remain visible in the catalog but are not join destinations. A menu observation is labelled as such, not as an in-world verification. Syncing a card never approves it automatically.

## 3. Start following

Keep the main in the world and return one alt to character selection:

```text
/claw main account:<main username>
/claw follow enabled:true
/claw status
```

Changing the main pauses following until you enable it again. A fresh main destination, an approved compatible character and a working save mechanism are required before an alt acts.

For a normal later session, let autoexec start the paired clients and check `/claw status`. You do not need to enroll them again. To stop new follow requests, use `/claw follow enabled:false`.

`VERIFIED` means the paired client checked the expected account, character, experience, place, exact server and main's presence after joining. `WITH_MAIN` means it was already there. Discord relays those client reports; it does not independently observe Roblox.

Automatic exits are off by default. After a successful menu test, opt in from Discord with `/claw auto-return account:<alt username> enabled:true`. Use `enabled:false` to switch it off, including pending menu confirmations once the client receives the update. It requests the normal return-to-menu flow; it does not bypass combat restrictions or force a respawn. Older explicit local settings remain effective only until a cloud setting overrides them. You no longer need to edit the private pairing file for this option.

## Everyday controls

| Command | What it does |
| --- | --- |
| `/claw panel` | Private account selector, character cards, permissions and setup |
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

Batch setup adds one shared `CLAW_PAIRINGS/batch.json` file and, while waiting, one `pending-<RobloxUserId>.json` per account. Both are private. The pending file is removed after a verified pairing save if the executor supports deletion; otherwise it is reused, not multiplied. The shared setup code stops working after its 10-minute window even if the file remains on disk.

**Storage unavailable:** the client could not prepare or save its current attempt. New actions stop. Check executor JSON/file support and storage access, then use `/claw retry account:...` after fixing the problem. Do not delete your pairing or attempt files to force a retry. You can still stop the client while saving is unavailable.

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

If Roblox or the loader restarts during a join, the client resumes checking that existing request when a valid saved record is available. It does not select another character just because the separate follow state is incomplete. A timed-out request waits for `/claw retry`; repeated reloads are not a retry button.

## Optional menu report

Only use this for troubleshooting; normal cloud sync does not need it.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/slot-scan.lua"))()
```

Run at character selection. It prints each card and overwrites one local report at `CLAW_CONTROL/menu-<UserId>.json`. It reads the slot list only: no clicks, selections, teleports or uploads.

Reports include character names and locations, so review them before sharing. Missing or conflicting fields are flagged, not guessed. Loaded offscreen cards are included; the scanner does not scroll to load more. `CARDS_CAPTURED_UNCONFIRMED` describes the scan, not a verified join.

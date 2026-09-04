# Set up your accounts

CLAW is in closed beta. Ask the host for access first. You don't need your own bot or website.

Already paired? Open `/claw panel` in Discord. Your saved accounts are still there.

## 1. Pair once

### One account

1. In Discord, use `/claw enroll account:<username>`. Enter the Roblox username, not the display name or the brackets.
2. Run the private snippet from the reply on that Roblox account.
3. Do the same for your main and each alt.

That snippet contains a private key. **Don't share it.** The public loader below has no keys.

### Several alts on one device

1. Open `/claw panel` → **Setup → Start alt setup**.
2. Run its private snippet once on one account.
3. Run the public loader on your other accounts.
4. In Discord, click **Refresh**, then choose a pairing request.
5. Match its check code with the code in that account's Roblox console, then confirm.

Pairing finishes within about 30 seconds. Only approve matching requests from your own accounts. If a request looks unfamiliar, close setup and start again.

The window lasts 10 minutes. This works across accounts sharing the same executor workspace; another device or workspace needs the snippet there too. Existing pairings are left alone. New accounts still need character approval.

If time runs out, start a new setup window and rerun the public loader on the unfinished accounts.

## 2. Use one startup script

Put this public loader in autoexec:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"))()
```

For Volt, save [control-autoexec.lua](../control-autoexec.lua) in its `autoexec` folder as `CLAW Control.luau`. Use that file **or** the line above, not both. One copy serves every account using that Volt installation.

Don't run the older Discord controller alongside the beta. During your first test, turn off other scripts that automatically select characters or hop servers. Your loot notifier can stay as it is.

## 3. Choose the characters

1. Leave an alt at character selection for about 15 seconds.
2. Open `/claw panel`, choose the account, then click **Characters**.
3. Find a character in your main's region. Use the region filter or **Next** if needed.
4. Open its card, click **Allow character**, and confirm.
5. If you allow several characters in the same region, use **Prefer in this region** to choose one.

Only Eastern and Etrean are supported for joining. Characters elsewhere still appear in the list, but CLAW cannot join with them there.

Unused slots are fine. You only need a finished, allowed character in the right region; you don't need to fill every slot.

Approvals stay saved. Replacing a character, resetting its level or removing its slot clears that character's old permission. Reopening character selection refreshes old cards.

## 4. Follow your main

1. On **Accounts**, choose your main and click **Use as main**.
2. Enter the world on the main. Leave the alt at character selection.
3. Click **Enable following** and confirm.

The alt should select its allowed character and join the main's exact server. Changing your main pauses following until you enable it again.

**Joined the correct server** means the running script checked the account, character, server and main's presence. Discord displays that report; it isn't watching Roblox itself.

## Next time you play

Open Roblox with Volt attached. Autoexec runs the same loader; you don't pair again or paste another script.

Your keys stay in the executor workspace. Your main, Follow setting and character permissions stay saved with your Discord account. The latest script downloads at startup; it doesn't replace a copy that's already running.

An alt already in another world waits for character selection. To let it return to the menu automatically, use `/claw auto-return account:<username> enabled:true`. It starts off and uses the normal game menu flow, not a forced respawn. Older local overrides show as **local setting** until you choose ON or OFF in Discord.

Roblox and your executor must be running. Discord can't open them for you.

## Useful controls

| Control | What it does |
| --- | --- |
| `/claw panel` | Accounts, characters, following and setup |
| **Refresh** | Update the current card or list |
| `/claw status` | Show why an account is waiting |
| `/claw nickname account:... label:...` | Give an account a short label |
| `/claw follow enabled:false` | Pause following |
| `/claw auto-return account:... enabled:false` | Turn automatic menu return off |
| `/claw retry account:...` | Try once more after fixing a stopped attempt |
| `/claw rotate account:...` | Replace a lost or leaked pairing key |
| `/claw revoke account:...` | Remove an account from your group |

Buttons expire after 15 minutes. Open `/claw panel` again when that happens.

All account fields accept usernames or numeric IDs. Capitalization and a leading `@` are fine. For an all-number username, include `@`. Use current usernames, not display names or former names.

Pausing or revoking stops new requests once received. It can't undo a teleport Roblox has already accepted.

## If an alt waits

| Status | What to do |
| --- | --- |
| `OFFLINE` | Check Roblox, Volt and the loader are running |
| `WAITING_MAIN` | Keep your selected main in-world with CLAW running |
| `WAITING_MENU` | Return the alt to character selection |
| `WAITING_SLOT_SCAN` | Let the character cards finish loading |
| `WAITING_SLOT_SYNC` | Wait briefly, then refresh the Discord panel |
| `NO_APPROVED_SLOT` / `NO_COMPATIBLE_SLOT` | Allow a character in your main's region |
| `CHOOSE_PREFERRED_SLOT` | Pick a preferred character for that region |
| `REGION_MISMATCH` | Reopen character selection and check its location |
| `AUTH_FAILED` | Check the account pairing; replace a lost key with Rotate |
| `ATTENTION` | Read the reason, fix it, then use Retry |

Reloading during a join keeps checking that attempt. It doesn't force a new one. Use Retry after fixing the reported problem.

### Pairing or save errors

- **Can't check or read pairing:** fix executor file access, then rerun. Don't delete a working pairing or rotate its key for a read error.
- **Pairing changed during setup:** let the other setup finish, then rerun only this account's snippet.
- **Key lost or rejected:** use `/claw rotate`, then run its new private snippet on the matching account.
- **Invalid pairing file:** stop this account's loader. Use Rotate, move only its damaged `CLAW_PAIRINGS/<RobloxUserId>.json` file aside privately, then run the new snippet. Leave other accounts' files alone.
- **Can't save or verify pairing:** check file access and rerun the same snippet. If the file is now invalid, use the step above.
- **Storage unavailable:** fix executor file access, then use Retry. Don't delete pairing or attempt files to force it.
- **Relay unavailable:** wait and retry. A network outage doesn't mean your key needs replacing.

## A report you can share

If the loader is running but an account is stuck, execute this on that account:

```lua
local control = getgenv().CLAW_CONTROL
print(control and control.supportReport and control:supportReport() or "CLAW support report unavailable. Copy the short setup error, or reload the current beta.")
```

Copy only the `CLAW SUPPORT 1` block. It leaves out keys, account names/IDs, characters, server IDs, service addresses and raw errors. It creates no file and sends nothing.

If setup never finishes, send the short error message instead. Don't post your pairing snippet, full console log, old `report()` output or saved account files.

## Files on your device

CLAW keeps two small files per paired account: its key and current join state. It updates those files instead of making new recordings.

Group setup adds one shared `CLAW_PAIRINGS/batch.json` and a temporary `pending-<RobloxUserId>.json` per waiting account. The pending file is removed after pairing when the executor supports deletion; otherwise it's reused. The setup code expires even if the file stays there.

Keep these files private. Never upload the whole executor workspace. [More about privacy](PRIVACY.md).

### Optional menu report

Only run this when troubleshooting the character list:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/slot-scan.lua"))()
```

Run it at character selection. It prints the loaded cards and overwrites one report at `CLAW_CONTROL/menu-<UserId>.json`. It doesn't scroll, select a character or join a server. The report includes character names and locations, so check it before sharing. Normal setup doesn't need it.

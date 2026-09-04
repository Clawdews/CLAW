# CLAW Control setup

[Install the Discord app](https://discord.com/oauth2/authorize?client_id=1545435882784559124&scope=applications.commands&integration_type=1), then open `/claw panel`.

## 1. Add the loader

Put this in autoexec once:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"))()
```

Volt users can instead save [control-autoexec.lua](../control-autoexec.lua) as `autoexec/CLAW Control.luau`. Do not use both.

## 2. Pair accounts

For several accounts on one executor workspace:

1. Open **Setup → Start alt setup**.
2. Run the private snippet once in that workspace.
3. Open each unpaired account and let autoexec run.
4. Refresh the panel and approve each account after matching its 8-character console code.

The setup window lasts ten minutes. Repeat the snippet once on each separate device or workspace.

For one account, use `/claw enroll account:<username>` and run its private reply on that account.

## 3. Allow characters

1. Leave the alt at character selection for about 15 seconds.
2. Choose the account and open **Characters**.
3. Allow a finished character in the main's region.
4. If several are allowed in one region, choose a preferred character.

Unused slots are fine. Eastern and Etrean are supported.

## 4. Start following

1. Choose the main and click **Use as main**.
2. Keep the main in-world and the alts at character selection.
3. Enable following.

The same autoexec loader reconnects on later sessions. Pairings, character permissions and the chosen main stay saved.

An alt already in-world waits for the menu. Enable normal menu return with `/claw auto-return account:<username> enabled:true` if wanted.

## 5. Make a team

1. Use `/claw team create`.
2. Add the main and alts with `/claw team add`.
3. Choose the team main with `/claw team main`.
4. Turn on team recovery with `/claw settings recovery` if wanted.
5. Use `/claw deploy`, then `/claw ready`.

The public loader handles later sessions. Movement and alerts remain off until requested from Discord.

For Discord alerts, a server owner must [add the CLAW bot](https://discord.com/oauth2/authorize?client_id=1545435882784559124&permissions=2048&scope=bot%20applications.commands). Then use `/claw settings alerts` in the channel you want.

## If an alt waits

| Status | Fix |
| --- | --- |
| `OFFLINE` | Start Roblox, the executor and the loader |
| `WAITING_MAIN` | Keep the selected main in-world |
| `WAITING_MENU` | Return the alt to character selection |
| `WAITING_SLOT_SCAN` | Wait for the character cards to load |
| `NO_APPROVED_SLOT` | Allow a character in the main's region |
| `CHOOSE_PREFERRED_SLOT` | Pick a preferred character |
| `AUTH_FAILED` | Rotate the pairing key and run the new private reply |
| `ATTENTION` | Fix the shown problem, then use Retry |

Use current Roblox usernames, not display names. `/claw status` shows the next step. Open a new panel when old buttons expire.

Never share a pairing snippet or files from `CLAW_PAIRINGS`. See [Privacy](PRIVACY.md).

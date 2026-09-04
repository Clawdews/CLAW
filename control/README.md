# CLAW Control

Single-owner Discord controller. The main publishes its server; paired alts select their saved character, join that exact server and report their arrival.

For separate user groups and character-card sync, see the [shared beta](https://github.com/Clawdews/CLAW/tree/control-beta/control). Do not run both clients together.

## Hosting

Create a Discord application and install it in your server with `applications.commands`. No message-reading permission is needed. Commands are restricted to the configured Discord owner and server.

From `control/`:

```sh
npm ci
npx wrangler login
npm test
npm run check
npm run deploy
npx wrangler secret put DISCORD_PUBLIC_KEY
npx wrangler secret put DISCORD_OWNER_ID
npx wrangler secret put DISCORD_GUILD_ID
```

Set the app's Interactions Endpoint URL to `https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/discord`. Discord must accept its verification ping.

Copy `.env.example` to a private `.env`, fill in the registration values, then run:

```sh
node --env-file=.env register.mjs
```

This updates only `/claw`. Keep the bot token out of Lua and public files. A Discord `50001` error means the app lacks access to the configured server.

The Worker uses a SQLite-backed Durable Object and WebSockets. Cloudflare's Free plan is sufficient within its quotas; paid service is not required by this setup.

## Pair and follow

1. Run `/claw enroll account:<Roblox UserId>` for your main and each alt.
2. Put the returned private keys into your autoexec config using [config.example.lua](config.example.lua). Each instance uses its actual account ID.
3. Load the client inside each character you want to use. It learns that character's actual DataSlot. Check `/claw status`.
4. Set `/claw main account:<main UserId>`. Keep the main in-world and return one alt to character selection.
5. Enable `/claw follow enabled:true`. Keep the same private config and loader in autoexec after teleport.

Following starts off. Competing auto-start or server-hop scripts can interfere with selection. After a successful menu join, `AllowMenuReturn = true` in an alt's private config enables the normal menu-return request. It only confirms a prompt titled **Return to Main Menu**; it does not force a respawn.

## Commands

| Command | Action |
| --- | --- |
| `/claw status` | Main, follow state, accounts, slots and reported results |
| `/claw main account:...` | Select a main and pause following |
| `/claw follow enabled:true/false` | Start or pause following |
| `/claw enroll account:...` | Create or rotate one account's key |
| `/claw slot account:... value:...` | Set a known DataSlot string |
| `/claw retry account:...` | Permit one new attempt |
| `/claw revoke account:...` | Revoke that account and disconnect it |

`VERIFIED` means the paired client checked the requested account, character, experience, place, server and main's presence after joining. `WITH_MAIN` means it was already there. Discord relays these reports; it does not independently observe Roblox.

Changing the main pauses following. Failed attempts wait for a new destination or an explicit retry. Pause/revocation cannot undo a teleport Roblox already accepted.

## Storage and limits

- Separate keys per account; only hashes are stored remotely. Enrollment again rotates the previous key.
- Main destinations expire after 35 seconds. A lobby or offline main is not a destination.
- Attempt state uses `CLAW_CONTROL/<UserId>.json` and available teleport settings. At least one read/write method must work. Pairing keys are not stored in the status report.
- Maximum 30 accounts. Roblox and the executor must already be running; the service cannot launch a closed process.
- No movement commands, proximity exits or arbitrary remote code execution.

Optional first-room provisioning is supported through `INITIAL_PAIRING`: `version: 1`, owner/server IDs, `mainId`, `follow`, and `members: [{accountId, keyHash}]`. Use SHA-256 hashes of independently generated private keys. Existing persisted configuration always takes precedence, including an empty revoked roster. Remove this temporary binding after provisioning.

## Development

```sh
npm --prefix control test
npm --prefix control run check
node tests/run-control-tests.mjs /path/to/luau
node tests/run-join-tests.mjs /path/to/luau
```

Local tests cover permissions, tickets, persistence and join sequencing. In-game timing and executor behavior still need client testing.

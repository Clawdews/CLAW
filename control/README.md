# CLAW Control

Discord selects the main; the main publishes its current server; paired alts join and verify automatically. No clipboard, chat commands, in-game panel or local HTTP service.

**Status (2026-09-04):** deployed on the owner's Workers Free account. The installed Discord app has all seven `/claw` subcommands, and the owner has confirmed a live `/claw status` response. The main and first alt are paired, follow is enabled, and authenticated HTTPS/WebSocket profile delivery passed for both accounts. A separate private Volt autoexec file is installed; the existing PR/loot file was not changed. Character-slot learning and the first automatic in-game join are still pending. The underlying manual exact-server join passed the user's earlier live test; that does not yet validate automatic slot selection or returning to menu.

The working alt manager, loot notifier, and `main/loader.lua` are unchanged. This lives on `codex/discord-control`.

## One-time setup

The owner needs a Cloudflare account and a Discord server where they can install an application. Start with Cloudflare's **Workers Free** plan. Do not enable a paid plan just to follow these instructions.

1. Create a Discord application in the [Developer Portal](https://discord.com/developers/applications). Name it CLAW. Keep its bot token private. Note its application ID and public key, plus your own Discord User ID and the target Discord server ID.
2. Install the app in that server with `applications.commands`. This code does not need message-reading access or Administrator bot permissions. Commands default to administrators, and the Worker additionally accepts only the configured owner in the configured server.
3. Deploy the Worker using the commands below. Its `workers.dev` address is the client endpoint; no custom domain is required.
4. Set the Discord app's **Interactions Endpoint URL** to `https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/discord`. Discord's signed verification ping must succeed before saving it.
5. Register `/claw` using the private local environment. The registration script upserts only this command; it does not erase other app commands.

From this `control` directory:

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

Enter each value at the secret prompt. Only the public verification key and allowed owner/server IDs are needed by the running Worker. The **bot token never goes in Roblox Lua or public GitHub files**.

For command registration, privately copy `.env.example` to `.env` and fill it in, then run:

```sh
node --env-file=.env register.mjs
```

The Git ignore rules cover `.env`, `.dev.vars`, `*.local.lua`, dependency folders, and build state. Never add real values to an example file. Registration and login are real account operations; dry-run compilation is not deployment.

If registration reports Discord API code `50001` (Missing Access), install the app in the configured server with the `applications.commands` scope before retrying. The registration script supplies Discord's required client identification header and never prints API response bodies or credentials on failure.

## Pair the accounts

In your configured Discord server:

```text
/claw enroll account:<main's numeric Roblox UserId>
/claw enroll account:<alt's numeric Roblox UserId>
/claw main account:<main's numeric Roblox UserId>
```

Each enrollment privately replies with a pairing key. Re-enrolling rotates it and disconnects the previous client. Copy the keys into your private autoexec config based on [config.example.lua](config.example.lua). The same config can be used across your own instances: the client chooses its key by the actual local account ID. Do not share a file containing all your keys with someone else.

Load once on each alt **inside the character you intend to use**. This lets the relay learn the actual `DataSlot` string. Selecting the correct character once is still required; we never guess slot numbers. `/claw status` reports whether the slot was saved. If needed, `/claw slot` lets you supply an actual known DataSlot string explicitly.

Then return a test alt to the menu, keep its new loader in autoexec, keep your main in the world, and enable:

```text
/claw follow enabled:true
```

The alt should select its saved character, join the main and report `VERIFIED`. Autoexec must run the same **private config + loader** after teleport. The client does not modify Volt's autoexec settings or store your pairing key in its status file.

After that passes, set `AllowMenuReturn = true` in the alt's private config if you want it to leave another server and follow the main automatically. It sends one menu request and confirms only a prompt titled **Return to Main Menu**. It does not force respawn, bypass combat restrictions or click unrelated prompts. Keep this off during the first test.

Disable competing auto-start/server-hop scripts during testing. The existing relay's `AutoStart` can race character/server selection; this client warns but does not change any other script.

### Deployment-managed initial pairing

For a fresh room, the deployment owner can use an optional `INITIAL_PAIRING` secret instead of entering enroll commands. It is JSON with `version: 1`, the configured `ownerId` and `guildId`, `mainId`, a boolean `follow`, and `members: [{accountId, keyHash}]`. Each `keyHash` is the SHA-256 hex digest of a separately generated, private 64-hex-character client key. Never put the plaintext keys in this binding or public files.

Initialization validates the roster and saves it before handling requests. Any existing persisted config takes precedence, including an empty roster after revocation. This is not an HTTP administration endpoint and cannot be used to reset existing accounts. Remove the temporary secret after authenticating the paired clients, then verify them again. Character slots remain unset until learned from the game.

## Controls

| Command | Result |
| --- | --- |
| `/claw status` | Current main, follow mode, online accounts, saved-slot state and client-reported results |
| `/claw main account:...` | Choose an enrolled main; also pauses following |
| `/claw follow enabled:true/false` | Start or pause automatic following |
| `/claw enroll account:...` | Create or rotate one account's pairing key |
| `/claw slot account:... value:...` | Set an actual DataSlot string |
| `/claw retry account:...` | Authorize one new attempt for a stopped alt |
| `/claw revoke account:...` | Revoke its credential and disconnect it |

Pause prevents new requests once received. It cannot undo a teleport Roblox already accepted. A failed attempt stays stopped until the target changes or `/claw retry` is used; repeating the same server announcement does not spam requests. Connection retries are separate and back off to one per minute; rejected pairing waits five minutes.

`WITH_MAIN` means the client was already at the exact destination and found the main. `VERIFIED` follows an issued join and the original join verifier. Discord displays what the paired client reports; it cannot independently observe Roblox.

## Guardrails and limits

- Only the configured Discord owner/server may change settings. Signed requests have a five-minute acceptance window and mutating commands are replay-checked for the full window.
- Each Roblox account has its own credential. Only its hash is stored remotely. The selected main is chosen server-side, not claimed by an alt's message.
- Credentials are exchanged over HTTPS for a short-lived, single-use WebSocket ticket. Long-lived keys do not appear in socket URLs. New connections replace only that account's previous connection.
- Main presence expires after 35 seconds. An offline main or a main sitting in the lobby is not a destination. Existing server lists are not consulted.
- One action attempt per destination is saved before game requests. Menu waiting is bounded to 60 seconds, slot response to 30 seconds, and join verification to 120 seconds.
- Client state lives in `CLAW_CONTROL/<UserId>.json` in the executor workspace and, if available, client teleport settings. It contains IDs and attempt state, not pairing keys. At least one write/read-back storage method must work.
- Maximum 30 enrolled accounts. No arbitrary Lua execution, Roblox cookies, movement commands, proximity logout or forced process relaunch in this version.
- Roblox and Volt must already be running. A closed process cannot execute the client; relaunching one is a separate account-manager feature, not something this bot implements.

The Worker uses a SQLite-backed Durable Object and hibernatable WebSockets. These are available on Cloudflare's [free plan](https://developers.cloudflare.com/durable-objects/platform/pricing/), subject to quotas; this is not a promise of unlimited free usage. If a quota is exhausted, the clients must wait rather than treat a stale server as current. No upgrade or billing subscription is configured by this project.

## Tests and deployment checks

```sh
# In control:
npm test
npm run check

# From the repository root, with Luau installed:
node tests/run-control-tests.mjs /path/to/luau
node tests/run-join-tests.mjs /path/to/luau
luau-compile --null control/client.lua control/auto.lua control-client.lua
```

Tests exercise signed Discord requests, owner/guild restrictions, key isolation, single-use socket tickets, target delivery, pause/retry/revocation, persistence, slot/menu sequencing and client reload. Node's tests run the Worker in Cloudflare's local runtime; Luau tests use game-service mocks. Neither substitutes for a live Discord-to-Volt test.

Current development tools are pinned in `package-lock.json`. Wrangler's selected release depends on an alpha Miniflare test runtime; the tests use its supplied v4-options conversion API. No application runtime npm dependencies are shipped to clients.

## Next live checks

1. Main + one alt: learn slot, enable follow from the menu, get `VERIFIED` without copying a ticket.
2. Pause before selecting a slot; confirm no new join occurs. Change main server; confirm the new destination is used.
3. Disconnect the main's relay connection; confirm stale destinations stop being delivered. Reconnect the alt without resending a pending join.
4. Opt into menu return on one alt and test its exact prompt. Then add the remaining alts.

Movement and Enmity parking stay in the working relay until these checks pass. Discord movement buttons, proximity safety/rejoin and automatic process relaunch are later work, not implemented here.

# Host CLAW Control

The shared beta needs one Cloudflare Worker and one Discord application for all its users. Ordinary users only install the app and pair their own clients. Use a separate beta app and Worker while an existing live service is in use.

## Closed beta first

`control/wrangler.shared.jsonc` creates `claw-control-beta`, not the legacy `claw-control`. Its default empty allowlist admits nobody. Start on the Workers Free plan and monitor quotas; do not silently enable paid billing for users.

1. Copy the shared config to an ignored `control/wrangler.shared.local.jsonc`. Set `vars.BETA_USERS` to comma-separated tester Discord IDs. Keep `SHARED_MODE="true"` and `ACCESS_MODE="closed"`. Set `PUBLIC_ENDPOINT` to the Worker's HTTPS origin after its first deployment. Never use `INITIAL_PAIRING` in shared mode; legacy seed data is intentionally ignored.
2. Create a beta Discord app. Enable server and user installation, with `applications.commands`. No Administrator permission, privileged intents, message-reading bot or Roblox OAuth cookie is needed. Discord documents the [user-installable app configuration](https://docs.discord.com/developers/tutorials/developing-a-user-installable-app).
3. Install dependencies and test from `control`:

```sh
npm ci
npm test
npx wrangler deploy --config wrangler.shared.local.jsonc --dry-run
npx wrangler deploy --config wrangler.shared.local.jsonc
npx wrangler secret put DISCORD_PUBLIC_KEY --config wrangler.shared.local.jsonc
```

4. Enter that app's public verification key at the secret prompt. Update `PUBLIC_ENDPOINT`, redeploy, then set the app's Interactions Endpoint URL to `<origin>/discord`. Its signed verification ping must pass.
5. Copy `control/.env.shared.example` to ignored `.env` and fill it privately. Register first in a test guild. The script upserts only `/claw`, never bulk-deletes another application's commands:

```sh
node --env-file=.env register.mjs
```

6. Test with two real Discord users in the same server. Each should see and control only their own account group. Complete the [release gates](CONTROL-RELEASE.md) before opening enrollment.

For a public release, register global commands with `DISCORD_COMMAND_SCOPE=global` and `SHARED_MODE=true`; confirm the app's user-install support and remove any obsolete **beta-app-only** guild command that shadows the global command. Do not alter the separate legacy app's commands. Switch `ACCESS_MODE` to `public` only after quota and abuse monitoring are ready. The configured `ENTRY_LIMITER` is required in public mode; missing/failed limits deny requests. Cloudflare's limits are approximate per-location controls, not a complete global abuse budget: see [rate-limit bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).

The runtime needs only the Discord public key. The bot token is used privately for registration, not stored in Roblox or the Worker. Never publish `.env`, pairing files, session tickets, or raw HTTP headers/bodies.

## Data and trust

- Each signed invoking Discord user owns a separate Durable Object named `user:<DiscordUserId>`. A guild owner or another member is not its commander. Shared mode never reuses the legacy `claw` room.
- Persistent records contain the Discord owner ID, enrolled Roblox IDs, optional account nicknames, hashes of high-entropy random pairing keys, credential revisions, main/follow and automatic-menu-return settings, current character summaries (letter, name, level, race, oath/origin, location, playtime and last played), observation timestamps, approvals, preferences and retry/replay metadata. This is not Roblox account-ownership verification.
- Plaintext pairing keys are returned privately in Discord and stored in `CLAW_PAIRINGS` on the user's device. Anyone who can read those files or the enrollment message can impersonate that paired client. Other scripts running in the same executor are not a security boundary.
- Presence contains experience/place/server IDs, slot and status. It lives in socket attachments and expires as an actionable destination after 35 seconds; expiry is not a promise of immediate physical deletion from hosting storage.
- Socket tickets expire in 30 seconds and are single-use. Their URLs must not appear in request logs. Worker observability is deliberately off until a redacted logging path exists; this is an explicit exception to the usual logging recommendation. Use aggregate hosting metrics, not credential-bearing traces.
- `/claw revoke` removes the account's enrollment/catalog/settings, invalidates its key and closes its connection. Revoking every account clears the roster, but the owner ID and short replay metadata remain. Local pairing files are not remotely erased. Cloudflare may retain recovery data according to its platform retention; do not promise instant deletion from backups.
- The standalone diagnostic scanner is local-only. The integrated client sends only allowlisted compact card fields, not raw labels, hidden base metadata, friends, chat, text-entry contents or diagnostic report files. The pairing instructions disclose this sync. The host controls the service and can access its stored data; private groups isolate users, not the hosting operator.

## Limits and failure behavior

Maximum 30 accounts per group and 60 observed slots per account. Request bodies are capped at 8 KiB, catalog/profile messages at 64 KiB, other client socket messages at 4 KiB, and recent mutating command IDs at 1,000 per group. Card fields have byte limits. Public entry is limited to 60 requests per minute per client-IP key and per Discord-user command key. Large groups reconnecting together may temporarily wait.

While the menu is open the reader scans only its known card container every 10 seconds with bounded traversal. Changed summaries upload at most once per 10 seconds; unchanged cards refresh every five minutes, or after reconnecting. Full snapshots replace the current roster; partial snapshots cannot erase unseen entries. There is no growing match history or scan archive in cloud state.

Worker restarts preserve configuration. Revocation and preference changes are persisted before being reported as successful. A failed save blocks game actions. No arbitrary Lua commands, external webhook forwarding, Roblox cookies or process-launch permissions are accepted by the relay.

Normal network reconnects back off to one attempt per minute; rejected credentials wait five minutes. Game actions are different: one saved attempt per destination, bounded waits, and no repeated join spam. Main freshness is checked before acting. If the main changes location while an already accepted teleport is underway, the client verifies the original attempt rather than pretending it arrived at the new destination.

## Release and rollback

Build with `node tools/build-control.mjs` and verify with `--check`. The generated `dist/launcher-beta.lua` contains both local pairing lookup and the full client; it makes no secondary module downloads. Record the Git commit, artifact hashes and deployed Worker version in the release record.

The branch loadstrings are an opt-in moving beta. For stable distribution, link directly to `dist/launcher-beta.lua` at an immutable, reviewed commit or protected release tag, including in the hosted enrollment reply. Pairing is bundled in that same artifact. A manifest hash is an operator check, not an executor-enforced signature.

Before replacing a live deployment, save its version ID, app endpoint, command schema and client release reference privately. Roll back the Worker to that verified version and restore the matching pinned loader. Do not delete its Durable Object namespace or run a destructive migration to roll back code. Cloudflare's [deployment commands](https://developers.cloudflare.com/workers/wrangler/commands/) describe version management.

The beta's owner/account-scoped status files and pairing files do not replace the legacy `CLAW_CONTROL/<UserId>.json` state. Moving between services requires deliberate pairing to the intended endpoint, and only one control loader should run on an account.

# Hosting Control

One Cloudflare Worker and one Discord application serve all users. Users pair their clients; they do not need hosting accounts or bot tokens.

Use a separate app and Worker for beta testing.

## Setup

1. Copy `control/wrangler.shared.jsonc` to ignored `control/wrangler.shared.local.jsonc`. Keep `SHARED_MODE=true` and `ACCESS_MODE=closed`. Add tester Discord IDs to `BETA_USERS`.
2. Create a Discord app with server/user installation and the `applications.commands` scope. No Administrator permission or message-reading intent is required.
3. Test and deploy:

```sh
npm --prefix control ci
node tools/check-control.mjs --worker-build
cd control
npx wrangler deploy --config wrangler.shared.local.jsonc
npx wrangler secret put DISCORD_PUBLIC_KEY --config wrangler.shared.local.jsonc
```

4. Set `PUBLIC_ENDPOINT` to the Worker's HTTPS origin and redeploy. Set the app's Interactions Endpoint to `<origin>/discord`; its verification must pass.
5. Copy `.env.shared.example` to ignored `.env`, fill it privately, then register the commands:

```sh
node --env-file=.env register.mjs
```

Start with a test guild. For public release, register globally with `DISCORD_COMMAND_SCOPE=global`, test user installation, then switch `ACCESS_MODE=public`. Public mode requires the configured rate-limit binding. Stay on the free plan unless a billing change is deliberate.

Do not mix in the legacy service's `INITIAL_PAIRING`, endpoint or credentials.

## Data

Each signed Discord user owns a separate stored group. Records contain account IDs, hashed pairing keys, preferences, nicknames, compact character cards and bounded retry metadata. The host can access stored data; other users cannot access your group.

Raw menu reports, chat, friends and editable text are not uploaded. Current card summaries replace earlier snapshots. Unchanged cards refresh every five minutes; changed cards upload at most once per ten seconds.

Pairing keys stay in private Discord replies and `CLAW_PAIRINGS/<UserId>.json` on the device. Anyone with that key or access to the executor can impersonate the client. Pairing is not Roblox account-ownership verification.

`/claw revoke` removes an account's stored enrollment, cards and settings and invalidates its key. Local files are not erased remotely. Owner/replay metadata and hosting backups have separate retention.

## Limits and recovery

- 30 accounts per group; 60 cards per account.
- 8 KiB HTTP bodies; 64 KiB catalog/profile messages; 4 KiB other client messages.
- Main destinations expire after 35 seconds.
- Socket tickets expire after 30 seconds and are single-use.
- Network reconnects back off; game joins require a saved, bounded attempt.
- Rejected credentials wait five minutes before reconnecting.

No arbitrary Lua, Roblox cookies or process-launch commands are accepted. Automatic menu return starts off and uses normal game requests.

Worker request logging is disabled because socket URLs contain temporary credentials. Do not log full requests, pairing replies or webhook URLs.

## Releases

`node tools/build-control.mjs` builds the self-contained launcher. `node tools/check-control.mjs` checks versions, artifacts, credentials and tests. Nothing in that command deploys or registers the app.

Pin a reviewed commit for stable distribution. The moving beta loader receives updates; its manifest hashes are build checks, not an executor-enforced signature.

Before changing a live service, record its Worker version and matching loader. Roll back code to that pair if needed; do not delete its stored groups. Keep only one control loader active per account.

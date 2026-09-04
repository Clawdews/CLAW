# Hosting CLAW Control

One Discord app and one Cloudflare Worker serve all users. Users do not need bot tokens or Cloudflare accounts.

## Setup

1. Copy `control/wrangler.shared.jsonc` to ignored `control/wrangler.shared.local.jsonc`.
2. Create a Discord app with user/server installation and `applications.commands`. No Administrator permission or message-reading intent is needed.
3. Test and deploy:

```sh
npm --prefix control ci
node tools/check-control.mjs --worker-build
cd control
npx wrangler deploy --config wrangler.shared.local.jsonc
npx wrangler secret put DISCORD_PUBLIC_KEY --config wrangler.shared.local.jsonc
```

4. Set `PUBLIC_ENDPOINT` to the Worker origin and the Discord Interactions Endpoint to `<origin>/discord`.
5. Fill an ignored `.env`, then run `node --env-file=.env register.mjs`.

Test in a guild first. For public use, register globally and set `ACCESS_MODE=public`. Public mode requires the rate-limit binding.

## Stored data

Each Discord user has a separate group containing account IDs, hashed pairing keys, settings, character cards and current connection state. Pairing keys remain in private Discord replies and local `CLAW_PAIRINGS` files. The host can access stored data.

Limits: 30 accounts per group, 60 cards per account, 15-minute panels, 10-minute batch setup, 35-second main destinations and single-use 30-second socket tickets.

Worker request logging should stay off because socket URLs contain temporary credentials. Never log pairing replies, full requests or webhook URLs.

## Releases

`node tools/build-control.mjs` builds the launcher. `node tools/check-control.mjs --worker-build` checks the release without deploying it.

Keep one control loader active per account. Roll back code without deleting stored groups.

# CLAW Control (legacy)

Single-owner Discord controller. The current shared version is on [control-beta](https://github.com/Clawdews/CLAW/tree/control-beta/control). Do not run both clients together.

## Hosting

From `control/`:

```sh
npm ci
npm test
npm run check
npm run deploy
npx wrangler secret put DISCORD_PUBLIC_KEY
npx wrangler secret put DISCORD_OWNER_ID
npx wrangler secret put DISCORD_GUILD_ID
```

Set the Discord Interactions Endpoint to `https://YOUR-WORKER.YOUR-SUBDOMAIN.workers.dev/discord`, fill an ignored `.env`, then run `node --env-file=.env register.mjs`.

## Use

1. Enroll the main and alts with `/claw enroll`.
2. Put each private key in its local config.
3. Set the main, leave the alt at character selection and enable following.

Use `/claw status` for current state. Following and automatic menu return start off.

Run checks with `npm --prefix control run check`.

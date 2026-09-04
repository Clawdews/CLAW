# CLAW Control

Your main reports its server. Your alts join it. Setup and status live in Discord.

**Closed beta.** The shared backend is deployed; the separate Discord app and full in-game rollout are still pending. The [existing controller](https://github.com/Clawdews/CLAW/tree/discord-control/control) stays separate.

- One public loader after one-time pairing on each account.
- A private account group for each Discord user.
- Automatic character cards: slot, name, level, race, oath/origin, location and playtime.
- Approved slots and a preferred character per region.
- Exact-server joining with arrival checks.
- Pause, retry, revoke, nicknames and normal menu-return controls.
- No local web server or extra in-game panel.

Eastern and Etrean Luminant are supported. Unknown regions, incomplete cards, stale destinations and mismatched selections stop the join. Automatic menu return starts off. No forced respawn, process launching or combat automation.

## Guides

- [Setup](../docs/CONTROL-SETUP.md)
- [Hosting and data](../docs/CONTROL-HOSTING.md)
- [Changelog](../docs/CONTROL-RELEASE.md)

## Development

```sh
npm --prefix control ci
node tools/build-control.mjs
node tools/check-control.mjs
```

Pass `--luau /path/to/luau` if needed. Add `--worker-build` to compile the shared Worker without deploying it. Tests cover local Worker execution and mocked game services; they do not replace an in-game test.

GitHub runs the same checks on beta pushes and pull requests, including Luau compilation and bundle consistency. The test workflow has no deployment credentials and does not publish to Cloudflare.

Edit the source modules, then rebuild `dist`. Pairing keys, bot tokens and local account files must stay out of Git.

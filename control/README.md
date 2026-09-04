# CLAW Control

Your main announces its server. Your alts join it. Discord handles setup and shows the result; no chat commands, in-game panel, clipboard relay or local web server.

This branch is the **shared-service beta**, not the installed live service. The existing single-owner version passed two automatic in-game joins and stays on [`codex/discord-control`](https://github.com/Clawdews/CLAW/tree/codex/discord-control/control). Nothing here replaces its endpoint or autoexec automatically.

## How it ships

One Discord app plus one public autoexec loader. Each Discord user gets a separate private account group, with their own main, alts, approved characters and pairing keys. They do not need their own Cloudflare account or Discord bot token when using a hosted instance.

- [User setup](../docs/CONTROL-SETUP.md)
- [Hosting, privacy and rollback](../docs/CONTROL-HOSTING.md)
- [Release checklist and roadmap](../docs/CONTROL-RELEASE.md)

## What's in this beta

- Signed Discord commands, private replies and per-user storage/socket isolation.
- One-time pairing on each Roblox account; a key cannot authenticate another account or another Discord user's group.
- Separate enrollment and key replacement, plus account revocation.
- Approved character selection for Eastern and Etrean Luminant, with a preferred character per region.
- Unknown regions, conflicting choices, observations older than 24 hours and selection-response mismatches stop before joining.
- Explicit waiting for a manual menu return when automatic exits are off. No sticky failure just because the alt is still in the world.
- Persistent, bounded join attempts; pause, retry, reconnect and exact-destination verification.
- Read-only menu scanner for validating the actual game UI. Its output is not yet an automatic character catalog.
- Reproducible, self-contained client builds. One launcher download includes its matching client modules.

There is no combat automation, forced respawn, proximity logout, process relaunch or Discord movement control here. The working alt-movement relay and loot notifier remain separate.

## Development

Requires Node and Luau. From the repository root:

```sh
npm --prefix control ci
node tools/build-control.mjs
node tools/build-control.mjs --check
npm --prefix control test
node tests/run-control-tests.mjs /path/to/luau
node tests/run-join-tests.mjs /path/to/luau
```

From `control`, `npm run check:shared` compiles the separate beta Worker without deploying it. `npm run check` checks the legacy configuration. Local Worker tests run in Miniflare; client tests use mocked Roblox services. Passing either does not prove the in-game menu reader works.

Edit `control/client.lua`, `control/auto.lua`, `control/regions.lua` and `control-launcher.lua`, then rebuild. Do not edit `dist` by hand. Its manifest records artifact sizes and SHA-256 hashes for release checks, not a claim that the executor authenticates a download at runtime.

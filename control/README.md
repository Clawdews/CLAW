# CLAW Control

Discord control for pairing alts, following a main, teams, movement, character presets and account status. Each Discord user has a separate account group.

[Install CLAW Control](https://discord.com/oauth2/authorize?client_id=1545435882784559124&scope=applications.commands&integration_type=1)

## Setup

1. Open `/claw panel`.
2. Under **Setup**, start alt setup and run the private snippet once in the shared executor workspace.
3. Open each account and approve its matching check code.
4. Leave each alt at character selection and allow a character in the main's region.
5. Choose the main and enable following.

Eastern and Etrean are supported. Automatic menu return and Discord alerts start off. Roblox and the executor must be running.

## Teams

Create a team with `/claw team create`, add its accounts, then choose its main. `/claw deploy` starts following. `/claw ready` shows what still needs attention.

Movement, parking spots, formations, presets, inventory, loot history, notes and the Enmity flow are under their matching `/claw` command groups. `/claw emergency` stops movement and following.

Bring and Park need the accounts in the same server. A new movement command replaces the previous one; Stop clears it. Bank scans only read supported data in an open bank window. Item gains are observations, not a complete loot ledger.

The chat bringer is separate. Do not run chat movement and Discord movement at the same time.

Discord alerts need [the optional server install](https://discord.com/oauth2/authorize?client_id=1545435882784559124&permissions=2048&scope=bot%20applications.commands). The app tests the channel before saving alerts.

[Full setup](../docs/CONTROL-SETUP.md) · [Privacy](../docs/PRIVACY.md) · [Hosting](../docs/CONTROL-HOSTING.md) · [Changelog](../docs/CONTROL-RELEASE.md)

## Build

```sh
npm --prefix control ci
node tools/build-control.mjs
node tools/check-control.mjs
```

# CLAW Control

Discord control for pairing alts and following a main's exact Deepwoken server. Each Discord user has a separate account group.

[Install CLAW Control](https://discord.com/oauth2/authorize?client_id=1545435882784559124&scope=applications.commands&integration_type=1)

## Setup

1. Open `/claw panel`.
2. Under **Setup**, start alt setup and run the private snippet once in the shared executor workspace.
3. Open each account and approve its matching check code.
4. Leave each alt at character selection and allow a character in the main's region.
5. Choose the main and enable following.

Eastern and Etrean are supported. Automatic menu return starts off. Roblox and the executor must be running.

[Full setup](../docs/CONTROL-SETUP.md) · [Privacy](../docs/PRIVACY.md) · [Hosting](../docs/CONTROL-HOSTING.md) · [Changelog](../docs/CONTROL-RELEASE.md)

## Build

```sh
npm --prefix control ci
node tools/build-control.mjs
node tools/check-control.mjs
```

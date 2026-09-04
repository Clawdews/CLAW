# CLAW Control

Manage your alts from Discord and have them join your main's server.

Open to everyone. Each Discord user gets a separate account group automatically. Main-to-alt joining and server hopping have been tested in-game; batch pairing still needs a fresh-alt test.

[Add CLAW to your Discord account](https://discord.com/oauth2/authorize?client_id=1545435882784559124&scope=applications.commands&integration_type=1).

## Using it

Open `/claw panel` in Discord. Pick an account, then click **Characters** to see its slots and choose which ones it can use.

- Pair each account once. After that, they all use the same loader.
- Adding several alts? **Setup → Start alt setup** gives you one setup snippet for accounts sharing the same executor workspace.
- See character names, power, race and region without looking through each Roblox window.
- Choose your main, turn following on, or pause it from the panel.
- Your account list is private to your Discord user.

Supports Eastern and Etrean. Returning an alt to the menu automatically is off unless you enable it. Roblox and your executor still need to be running.

Using the [older controller](https://github.com/Clawdews/CLAW/tree/discord-control/control)? Keep that setup separate; don't run both loaders together.

## Guides

- [Setup](../docs/CONTROL-SETUP.md)
- [Hosting and data](../docs/CONTROL-HOSTING.md)
- [What to keep private](../docs/PRIVACY.md)
- [Changelog](../docs/CONTROL-RELEASE.md)

## Development

```sh
npm --prefix control ci
node tools/build-control.mjs
node tools/check-control.mjs
```

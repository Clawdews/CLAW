# Control changelog

## Client fixes

- Unreadable pairings stop setup instead of being replaced.
- Setup checks the saved pairing again before replacing it.
- Pairing errors hide private file and request contents.
- Reconnect recovers if preparing a request fails.
- Invalid pairing files stop with a readable next step.

## 0.2.0-beta.3

- Account nicknames and paginated status.
- Waiting states include a next step.
- Normal menu return can be toggled from Discord.
- Turning it off stops pending confirmations once received.

## 0.2.0-beta.2

- Automatic, compact character-card sync.
- One loader for first pairing and later launches.
- Replaced characters lose old slot approval.
- Unchanged cards avoid repeated cloud writes.

## Release status

The [shared backend](https://claw-control-beta.your-account.workers.dev/health) is deployed with enrollment closed. The existing controller remains on its own service.

Before public onboarding:

- Connect the separate Discord app.
- Test setup with two independent users.
- Verify menu sync, region mismatch, pause and reconnect in-game.

Tests: `node tools/check-control.mjs`.

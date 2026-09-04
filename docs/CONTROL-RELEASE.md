# Control changelog

## 0.2.0-beta.4

- Private `/claw panel` with account selection, main/alt labels and readable status.
- Character cards, region filters, next/previous controls and a separate details view.
- Confirm before changing main, following, or character permissions. Stale controls cannot change settings.
- Temporary alt setup: one snippet per workspace, then approve matching account requests in Discord.
- Same public loader and existing private keys. No changes to joining, auto-return defaults or loot notifications.

## Client fixes

- Failed state encoding stops new actions without exposing private error text or interrupting shutdown.
- One explicit retry can recover a selection stopped by storage failure; an already-issued join is not resent.
- Restarts keep watching an in-flight join even if its saved follow state is incomplete.
- Shareable support report with a build ID and no account/server details.
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

The shared backend is deployed with enrollment closed. Deployment addresses stay in private configuration. The existing controller remains on its own service.

Before public onboarding:

- Test setup with two independent users.
- Verify the new panel and batch setup with real executor instances.
- Verify menu sync, region mismatch, pause and reconnect in-game.

Tests: `node tools/check-control.mjs`.

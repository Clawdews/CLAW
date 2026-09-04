# Control changelog

## 0.2.0-beta.4

- Shorter setup guide and panel messages.
- Empty region filters now suggest another filter, not an unnecessary rescan.
- Refresh button on character details; unsupported locations marked on each card.
- Older local auto-return settings no longer appear as a confirmed OFF in Discord.
- Private `/claw panel` with account selection, main/alt labels and readable status.
- Character cards, region filters, next/previous controls and a separate details view.
- Confirm before changing main, following, or character permissions. Stale controls cannot change settings.
- Temporary alt setup: one snippet per workspace, then approve matching account requests in Discord.
- Same public loader and existing private keys. No changes to joining, auto-return defaults or loot notifications.

### Earlier client fixes

- Reloading during a join keeps checking that join instead of sending it again.
- Failed saves stop new actions. Fix storage, then use Retry.
- Damaged or unreadable pairing files aren't silently replaced.
- Setup errors hide private contents. The short support report leaves out account and server details.
- Reconnect recovers from failed request setup.

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

Closed beta. The older controller is still separate.

Before public onboarding:

- Test setup with two independent users.
- Test group setup on a fresh alt and confirm the panel buttons in-game.
- Verify menu sync, region mismatch, pause and reconnect in-game.

Tests: `node tools/check-control.mjs`.

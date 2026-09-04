# Control changelog

## 0.2.0-beta.5

- Open access: each Discord user gets their own group without host approval.
- Commands available for personal and server installations.
- Username commands show a private loading reply while Roblox responds.
- Longer lookup timeout and one retry for short rate limits or server errors.
- Existing pairings, following settings and character approvals stay unchanged.

## 0.2.0-beta.4

- Unused slots no longer block a finished, approved character from joining.
- Full main-to-alt server hopping tested in-game, including automatic menu return and startup.
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

Public beta. The older controller is still separate.

Still to test in-game:

- Test setup with two independent users.
- Test group setup on a fresh alt and confirm the panel buttons in-game.
- Verify menu sync, region mismatch, pause and reconnect in-game.

Tests: `node tools/check-control.mjs`.

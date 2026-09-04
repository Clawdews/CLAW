# CLAW Control beta

The live v0.1 exact-server flow has passed two user tests. It stays on `codex/discord-control`; this beta is isolated on `codex/control-beta`.

## Product shape

One installable Discord app, with a private control group for each Discord user. The script pairs that user's Roblox clients. No local web server and no shared Discord-server-wide commander. Self-hosting remains an option.

The Discord identity comes from the verified interaction, never a command argument. Roblox identity is a paired-client claim, not Roblox OAuth/account-ownership verification. A pairing key can authorize only its account in its owner's group. Never accept arbitrary script execution or Roblox login cookies.

## Character selection

Read menu metadata without clicking and sync compact current cards to the owner's cloud roster; keep menu candidates labelled as observations, not in-world confirmations. The user approves usable slots and can prefer one per region. Current local cards and cloud permissions must agree before selection. Reused slot letters cannot inherit a changed character's approval. Unknown regions, ambiguous choices, stale observations, or a selected-region mismatch stop the join. Only Eastern and Etrean have mappings in this beta; other layers must be explicitly verified before support is added.

## Release gates

- [x] Existing exact-server arrival verified in-game; repeat test passed.
- [x] Real menu structure captured; slot entries A–M located in the character list.
- [x] Focused v0.2.0 reader captured 13 cards / 115 labels, visiting 337 nodes without truncation.
- [x] v0.2.1 captured 13 complete cards / 115 labels / 325 nodes without truncation. Slot H's visible Celtor / Rogue Assassin fields match the screenshot; hidden base fields stay separate.
- [x] Compact cloud catalog, per-user privacy, permissions, replacement-character resets, pagination and first-pair launch tested locally.
- [ ] Approved multi-slot region picker tested against a real mismatch.
- [x] Separate-user authentication, commands, sockets, revocation and restart isolation tested in the local Cloudflare runtime.
- [x] Private pairing and public launcher covered by mocked-client tests, including wrong account/owner, bad keys and corrupt files.
- [ ] Self-service pairing tested by someone other than the owner.
- [ ] Pause, manual menu return, reconnect and stale-target behavior checked in-game.
- [x] Host limits, privacy, troubleshooting, release pin and rollback documented.
- [x] Reproducible self-contained client and launcher builds, with source/bundle smoke tests.
- [ ] Beta deployment and Discord installation reviewed before enabling public registration.

Public release is not the same as committing code. Do not change the existing live endpoint or autoexec as part of an unverified beta rollout.

## 0.2.0-beta.2 checkpoint — September 4

The separate [cloud beta health endpoint](https://claw-control-beta.your-account.workers.dev/health) returned HTTP 200 with version `0.2.0-beta.2` and `shared:true`. Cloudflare version: `f1748091-526b-4146-be8f-8cef047e9221`. Enrollment remains closed with an empty allowlist; a separate Discord application is not connected yet. This is a deployed backend, not a public-ready install.

Local checks: 56 Worker/Node tests, 117 Luau control/scanner/pairing checks, and 44 exact-join checks passed. Client and scanner bundles reproduce from source; the shared Worker dry run compiled. These are local tests, not integrated in-game cloud verification.

The live service still returned `0.1.0`. Its deployment, Discord endpoint, credentials, autoexec and PR/loot scripts were not changed.

## 0.2.0-beta.3 checkpoint — September 4

Added account nicknames, bounded/paginated account status with concrete next steps, and `/claw auto-return` so users do not edit pairing files to change that setting. Cloud OFF overrides an older local opt-in; a pending menu confirmation is suppressed after permission is withdrawn. This uses normal game menu requests, not forced respawn.

Checks passed: 62 Worker/Node tests and 127 control/scanner/pairing checks. Shared Worker dry run passed. Cloud version `285d89e9-03c4-4904-a4a1-211267c46159` returned beta.3 health, rejected unapproved enrollment with HTTP 401, and left live v0.1.0 unchanged. GitHub beta.2's immutable launcher was also verified against its Git blob.

Still waiting for the separate beta Discord application and real-client validation. Computer Use requires an action-time confirmation to create new persistent app access; this setup step is parked while the user is asleep. Do not reuse or reset the working bot's token to get around that dependency.

## Next milestones

1. Validate integrated menu-to-Discord sync and compare location observations with the game's selected-region response. Never present an observed menu card as a verified arrival.
2. Run closed beta with two independent Discord users: pairing, approval, correct-region join, mismatch refusal, pause, disconnect, revoke and reconnect. Record actual results, not just screenshots of the UI loading.
3. Pin a reviewed client release, deploy the shared service separately and publish the install link after the gates pass.
4. Bring the existing movement/parking controls to Discord only after joining is reliable. Proximity safety/rejoin and closed-process relaunch are separate projects, not promises in this release.

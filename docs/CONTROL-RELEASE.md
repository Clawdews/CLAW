# CLAW Control beta

The live v0.1 exact-server flow has passed two user tests. It stays on `codex/discord-control`; this beta is isolated on `codex/control-beta`.

## Product shape

One installable Discord app, with a private control group for each Discord user. The script pairs that user's Roblox clients. No local web server and no shared Discord-server-wide commander. Self-hosting remains an option.

The Discord identity comes from the verified interaction, never a command argument. Roblox identity is a paired-client claim, not Roblox OAuth/account-ownership verification. A pairing key can authorize only its account in its owner's group. Never accept arbitrary script execution or Roblox login cookies.

## Character selection

Read menu metadata without clicking; keep menu candidates unconfirmed. A running character's DataSlot and mapped place establish an observed slot/region pair. The user approves usable slots and can prefer one per region. Unknown regions, ambiguous choices, stale observations, or a selected-region mismatch stop the join. Only Eastern and Etrean have mappings in this beta; other layers must be explicitly verified before support is added.

## Release gates

- [x] Existing exact-server arrival verified in-game; repeat test passed.
- [x] Real menu structure captured; slot entries A–M located in the character list.
- [ ] Focused card reader validated in-game against names, races and location labels. Source/bundle tests pass; a real v0.2.0 report is still required.
- [ ] Approved multi-slot region picker tested against a real mismatch.
- [x] Separate-user authentication, commands, sockets, revocation and restart isolation tested in the local Cloudflare runtime.
- [x] Private pairing and public launcher covered by mocked-client tests, including wrong account/owner, bad keys and corrupt files.
- [ ] Self-service pairing tested by someone other than the owner.
- [ ] Pause, manual menu return, reconnect and stale-target behavior checked in-game.
- [x] Host limits, privacy, troubleshooting, release pin and rollback documented.
- [x] Reproducible self-contained client and launcher builds, with source/bundle smoke tests.
- [ ] Beta deployment and Discord installation reviewed before enabling public registration.

Public release is not the same as committing code. Do not change the existing live endpoint or autoexec as part of an unverified beta rollout.

## Next milestones

1. Test the focused v0.2.0 card reader, map any remaining label formats and compare the location observations with the game's selected-region response. Never promote labels to confirmed slot IDs without that check.
2. Run closed beta with two independent Discord users: pairing, approval, correct-region join, mismatch refusal, pause, disconnect, revoke and reconnect. Record actual results, not just screenshots of the UI loading.
3. Pin a reviewed client release, deploy the shared service separately and publish the install link after the gates pass.
4. Bring the existing movement/parking controls to Discord only after joining is reliable. Proximity safety/rejoin and closed-process relaunch are separate projects, not promises in this release.

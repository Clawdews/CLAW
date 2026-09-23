# CLAW — session handoff

Quick state dump so the next session starts with full context. Written 2026-09-23.

## What got done this session

### Shipped to `main` (live, pushed)
- **Loot ping fix** (`loot.lua`) — the `@`-ping used a single global `pingWanted` flag, so a
  ping-item past `BATCH_SIZE` pinged on the wrong batch. Ping now rides the queued item and
  flushes with the batch that actually contains it.
- **Relay noclip restored** (`relay.lua`) — plain `CanCollide=false` gets re-asserted by
  Deepwoken, causing wall stickiness. Reinstated the `EffectReplicator.HasAny` spoof for the
  teleport-phase classes (`PrepareTP`/`TPSafe`), gated to only when flying/phasing, restored on
  Destroy.
- **Relay persistent bring** (`relay.lua`) — random mid-air drops were `_stepFlight` guards
  cancelling with nothing to resume. Added a supervisor: `alts bring` keeps re-issuing toward the
  controller's *current* position on any non-arrival stop. Only arrival / `stop` / `menu` /
  proximity-safety end it. Also scaled the knockback tolerance with step speed to cut false stops.
- Branches `fix-loot-ping` and `fix-relay-noclip` were merged into `main` and deleted.

### On branch `smooth-controller` (NOT merged — waiting on in-game test)
Cloud Discord controller smoothness. Files: `control/client.lua`, `control/movement.lua`,
rebuilt `dist/*`, and specs `tests/control-movement.spec.luau`, `tests/control-runtime.spec.luau`.
- **Instant presence** — `client.lua` pushes a presence packet immediately on any movement/status
  change (rate-limited ~1.5s) instead of only on the 10s heartbeat. Panel reacts almost at once.
- **Cloud noclip + resumable movement** — ported the `EffectReplicator` spoof and a movement
  supervisor into `movement.lua` (the Discord path had neither). Owner Stop / settings-change now
  call `movement:cancel()`; transient stops keep the desire and auto-resume.
- **Reconnect backoff** capped 60s → 20s.
- All tests pass (`node tools/check-control.mjs` → "CLAW release checks passed").

## To do next (priority order)
1. **Merge `smooth-controller` → `control-beta`** once confirmed in-game. NOTE: `control-beta` is
   in the Discord-notify list, so that push WILL fire the webhook.
2. **Panel one-tap buttons + autocomplete** — not started, both buildable/testable against the
   worker suite. Add Bring all / Stop all / Park + a persistent Emergency-Stop button to the panel
   (`control/panel.js` + `control/panel-controller.js`, wiring into the existing `reconcileActions`
   action queue). Add Discord `autocomplete: true` to `account:`/`team:` options + a handler in the
   worker so it suggests the known roster.
3. **Auto seller — BLOCKED on info from user.** It does not exist anywhere in the repo/history.
   Design is ready: mirror `notes-dropper.lua`'s safety model (learn the sell remote from ONE manual
   sell — never guess a remote name — allow/keep-list, batch + verify inventory decrement, stop on
   ambiguity, report to Discord). **Need from user: the actual in-game sell flow** — NPC shop prompt?
   menu sell button? amount dialog like notes? Cannot build correctly without this.
4. **Notes coexistence** — `notes-dropper.lua` deliberately refuses to run beside the manager/bringer;
   docs call a combined flow "future work." Could expose a `drop` action in the manager queue.
5. **Loot rarity** — `loot.lua` only detects a star (→ legendary); everything else is grey/common.
   The `RARITY` table's other tiers are dead unless real rarity can be read from the UI.
6. **Stale branch** `cleanup-loot-readme` — looked like a dead leftover; offered to check/delete, not done.

## Technical context (important)
- **No Roblox runtime here.** Validation is: `luaparse` for syntax; the luau spec suites via
  `node tools/check-control.mjs` or `node tests/run-control-tests.mjs`; worker node tests
  (`node --test control/test/*.mjs`); `node --test tests/discord-push.test.mjs`. Real in-game
  behavior is the user's to confirm.
- **luau binary** was downloaded to `.tools/luau/bin/luau.exe` (gitignored) via
  `gh release download --repo luau-lang/luau --pattern 'luau-windows.zip'` then extracted. If it's
  gone next session, re-fetch it there.
- **Production load path for the manager:** autoexec → `dist/launcher-beta.lua` →
  `control-client.lua` → `dist/control-beta.lua` (the BUILT bundle). After editing any
  `control/*.lua` source you MUST rebuild: `npm --prefix control ci` then
  `node tools/build-control.mjs`, then `node tools/check-control.mjs`. The chat relay
  (`relay.lua`) and loot (`loot.lua`) load raw from `main`, no build step.
- **Discord-notify branches** (`.github/workflows/discord-updates.yml`): `main`, `control-beta`,
  `discord-control`, `server-join`, `animation-transport`. Pushing to any of these pings Discord.
  Feature branches (like `smooth-controller`) do not — use them for WIP.
- **Loadstrings** live in `README.md` (relay + loot, from `main`) and `docs/CONTROL-SETUP.md` /
  `docs/NOTES.md` (manager from `control-beta` dist; notes from a luarmor loader that needs a key).
- **Luarmor auto-publish for notes is broken** (HTTP 400 `Missing x-turnstile-token`), so the live
  notes script is whatever was last uploaded via the dashboard — local `notes-dropper.lua` edits are
  NOT live until that's resolved.
- GitHub auth: `gh` is signed in as **Clawdews**. Repo is `Clawdews/CLAW`.

## The four components (user's mental model)
1. **Alt bringer** — `relay.lua` (chat-controlled, `main`).
2. **Alt manager / Discord controller** — `control/` Cloudflare worker + client (`control-beta`).
3. **Notes dropper** — `notes-dropper.lua` (`control-beta`, luarmor-protected).
4. **Auto seller** — does not exist yet (see To-do #3).
Plus a 5th utility: the **loot notifier** (`loot.lua`).

# CLAW MARK Roadmap

This roadmap treats Lycoris as a behavioral reference and timing source while keeping CLAW's runtime modular, bounded, and safe by default. Every phase must preserve the proven native Block → bounded retry → Unblock path unless a regression harness proves a replacement.

## Threat Guard foundation — v0.4.0

- Per-attacker animation burst detection and quarantine; one noisy Animator does not disable other targets or detector channels.
- Bounded pending threat plans per source and coalescing for signals predicting the same contact window.
- Stronger part/effect evidence replaces an overlapping animation plan, while reserved non-animation capacity prevents animation spam from starving independent signals.
- Three real Lycoris client-effect channels with bounded owner/origin extraction, scalar payload snapshots, and cross-channel-only deduplication.
- Debug and copied diagnostics expose guard mode, active plans, noisy sources, admitted/coalesced/dropped/burst counts, and client-effect channel counts.
- Executable Luau regression scenarios cover burst quarantine, per-source budgets, trusted-evidence admission, overlap coalescing, settlement, and reset.
- Live target distance, hitbox-CFrame selection, ValueBase state changes, and character-removal cleanup corrected alongside the new pipeline.

This is intentionally `Threat Guard v1`, not a breaker-proof claim. Animation remains a sensor; the current milestone contains floods and establishes the evidence channels required for later genuine-vs-fake research.

## Shipped foundation — v0.3.9

- Safe/inert startup for every active feature.
- Attributed 854-profile timing database with animation, sound, part, and effect schemas.
- Native parry, dodge readiness, direct dodge, roll cancellation, fallback policy, scheduling, target selection, and validation.
- Known-good deterministic `Stable` preset.
- Searchable, type-filtered, paged timing browser.
- Targeted animation logger, live/recent track inspector, Burster controls, Ghost pool, lower-body pose guard, and Ghost experiment ledger.
- Panic reset, stale-job cancellation, unique simultaneous hitbox waits, shareable diagnostic report, remembered tab/window/selection, and truthful status feedback.

## Phase 1 — Combat truth and effect coverage (P0)

1. **Shipped v0.4.0:** three-channel client-effect detection for `ClientEffect`, `ClientEffectLarge`, and `ClientEffectDirect`.
2. **Shipped v0.4.0:** bounded payload ID, owner, origin, scalar attribute, and cross-channel duplicate normalization.
3. Add one replicated effect-state bridge for `ParryCool`, `NoRoll`, stun, equipped, attacking, and iframe state.
4. Replace the string-only feature catalog with capability records: backend, dependencies, availability, safe default, and self-test.
5. Show `NATIVE`, `KEYPRESS`, `BINDING REQUIRED`, or `UNAVAILABLE` beside every action/assistance feature.
6. Add a trace harness for detection → plan → due time → fallback → input → release.

Acceptance:

- All 16 converted effect profiles can receive their real event channel.
- `DisplayThorns` computes its delay from `Time - Window`.
- Turning Auto Defense off produces no later defensive input.
- Two identical attacks from different entities retain separate plans and hitbox waits.
- All active features still boot off.

## Phase 2 — Animation Lab workbench (P1)

1. Unified event inbox for unknown/missing animation, sound, part, and effect events.
2. Search, target/distance filter, missing-only mode, blacklist/undo, copy ID, and one-click “Create Timing”.
3. Playback inspector with a viewport clone, speed history, scrubber, pause, and frame stepping.
4. Interactive hitbox sandbox sharing the production validation geometry.
5. Timing provenance and source badges: bundled, local override, unsupported module, favorite, and recent.
6. Ghost experiment matrices with controlled single-variable runs and exported observations.
7. Burster visual research: normal anticipation, accelerated technical segment, and immediate normal visual layer—never a delayed animation from idle.

Acceptance:

- An unknown event becomes an editable timing in two clicks.
- A timing can be previewed and its hitbox inspected without entering live combat.
- Ghost tests retain exact parameters plus local/remote results.
- Hidden pages perform no high-frequency polling.

## Phase 3 — Native feature parity (P2)

1. Native adapters for Vent, jump, feint, mantra activation, and other actions currently dependent on generic bindings.
2. Exact Prediction/Punishment scheduling and Wisp, Golden Tongue, Ardour, Flow State, Rhythm, mantra follow-up, ragdoll recovery, and flourish-feint semantics.
3. One roll controller shared by defense fallback and Action Rolling.
4. Allowlisted declarative timing-formula registry with validated inputs, execution budgets, error isolation, and lifecycle cleanup.

Acceptance:

- Every visible control truthfully reports its backend and missing dependency.
- No feature silently succeeds when it only queued an unavailable binding.
- Re-execution leaves no connections, held inputs, or scheduled callbacks behind.

## Phase 4 — Data, UI architecture, and performance (P3)

1. Split the monolithic UI into page modules backed by a control metadata registry.
2. Named timing workspaces with bundled/user/session layers, explicit merge/replace, dirty state, undo/redo, recovery, and automatic backups.
3. Virtual row pools and debounced search for large timing/event lists.
4. One shared telemetry sampler; pause LIVE/inspector polling while hidden.
5. Motion Validation V2 in shadow mode using live synchronized attacker/local snapshots before activation.
6. Recent p95/peak timings, scheduler lateness, waiter/cancel counts, and active connection counts.

Acceptance:

- UI modules remain below Luau register limits.
- Normal runtime stays inside the configured scan budget without losing events.
- Saved work can be recovered after malformed or interrupted writes.

## Phase 5 — Optional packs (P4)

- Player/mob monitoring and configurable notifications.
- Minimal target/entity visualization.
- Lightweight visual and ambience QOL.

Full farms, movement cheats, spoofing, teleports, and broad exploit packs are not core Animation Lab work. They must remain separate so CLAW does not inherit Lycoris's initialization and performance problems.

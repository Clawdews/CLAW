# CLAW MARK Product Specification

## Product promise

CLAW MARK is a clean, inspectable Animation Lab and combat-timing workbench. A non-coder should be able to observe an event, understand how CLAW interpreted it, test a response, and share a useful report without reading Lua.

## Operating rules

- Startup is inert. No active combat, Burster, Ghost, logger, assistance, probability, fallback, or diagnostic trace silently resumes.
- A green control means active. Ordinary off controls are neutral; red is reserved for failure, danger, or fault injection.
- Every action is traceable from source event to final input result.
- User scripts, Project Rain, and the separate loot notifier remain outside CLAW's runtime.
- Lycoris code is a behavioral reference. CLAW keeps its own bounded modules and attributed converted timing data.

## Primary workflows

### Known-good defense

1. Open Combat.
2. Select `Stable` and Apply.
3. Confirm Master and Auto Defense are on.
4. Test against a controlled enemy.
5. Copy Debug if behavior differs from the expected result.

The Stable preset is deterministic: optional fallbacks, assistance, probability, hidden filters, experimental unknown-animation handling, and fault injection are reset before the known-good settings are applied.

### Animation research

1. Choose a local or remote target.
2. Enable Logger deliberately.
3. Search observed animation statistics or inspect LIVE/RECENT tracks.
4. Select an ID and move it into Burster, Ghost, or timing editing.
5. Change one experimental variable at a time.

### Ghost experiment

1. Select one animation and Fire Once.
2. Record whether the local pose was clean or twitched.
3. Record whether a second client's logger saw it.
4. Copy the JSON ledger after the test matrix.

Each entry records ID, speed, lifetime, fade, target weight, visible cap, maximum observed weight, time position, priority, visual-guard state, leg-guard state, largest joint displacement/rotation, and the two manual observations.

### Failure recovery

`PANIC / ALL OFF` must stop Ghost, Burster, Logger, combat master, defense, assistance, fallbacks, probability, traces, scheduled work, hitbox waits, roll-cancel jobs, held mouse input, and native block state. It must not unload the UI or delete timings.

## Runtime pipeline

```text
detector event
  → timing/profile resolution
  → stable planning validation
  → per-source threat admission / overlap coalescing
  → scheduled due time
  → live target/state validation
  → fallback selection if the requested input is unavailable
  → one input backend
  → release/cancel lifecycle
  → correlated diagnostics
```

Transient state such as `ParryCool`, dodge cooldown, stun, iframes, and current attack state belongs at scheduled execution time. Geometry/profile validity can be checked while planning. A fallback must not discard the original attack's due time.

Animation volume is never equivalent to danger. Threat Guard maintains a bounded plan budget per source, quarantines only the noisy source's animation channel, and reserves capacity for stronger part/effect/projectile evidence. It does not add a fixed validation sleep and does not present a heuristic distinction as proof that an attack is genuine.

## Capability states

Every feature will expose one of:

- `NATIVE`: game-specific state and input bridge is available.
- `KEYPRESS`: ordinary input emulation is being used.
- `BINDING REQUIRED`: the user must configure a key/callback.
- `UNAVAILABLE`: a required executor/game dependency is missing.

The UI must never label a queued callback as successfully executed input.

## Performance budgets

- No full descendant scan in the steady-state combat loop.
- Target scans obey the configured millisecond budget and adaptive backoff.
- Hidden pages do not poll at display refresh rates.
- Event buffers and experiment ledgers are bounded.
- Payload traversal is cycle-safe, depth-limited, and item-limited.
- Large lists use paging or pooled rows rather than thousands of persistent controls.

## Release gates

Every public release must pass:

1. Generated bundle freshness check.
2. Official Luau compilation.
3. Safe-start and secret/private-source verification.
4. Scenario checks for pending-action shutdown, repeated dodge cancellation, simultaneous identical attackers, and fallback timing.
5. Public loader, bundle, timing database, and immutable fallback HTTP verification.

# CLAW Recorder

CLAW Recorder is a standalone, observer-only combat session recorder. Its purpose is to collect evidence for timing profiles while another hub, such as APC, handles combat. It is deliberately not a CLAW MARK module.

## Safety boundary

The recorder does not:

- load or call CLAW MARK;
- simulate keyboard or mouse input;
- fire game remotes;
- play, stop, or change animation tracks;
- alter global mouse behavior;
- hook functions or scan another hub;
- record player names, the local user ID, or the server job ID.

Its only interactive surfaces are its own four HUD buttons and draggable title bar.

## What a session records

- Enemy animation ID, start time, start speed, length, priority, weight, distance, facing, relative position, both players' linear velocity, and a non-identifying player/mob label.
- Animation end time, possible early stop, speed changes, and named keyframe times.
- Observed weapon type, swing speed, original swing speed, weapon length, and network ping when available.
- Local health loss, posture/break-meter changes, combat-relevant replicated effect additions/removals, and selected effect outcomes including parry attempts, confirmed `ParrySuccess`, frames/signals, blocking, dodging, iframes, stun, and knockdown. Counts for other observed effect classes remain in the catalog without flooding the raw timeline.
- A separate read-only mirror of the local character's Action-priority animation starts and stops. `Parried` is correlated as the opponent parrying one of those local attacks, while `LandedLightAttack` is correlated as that local attack landing. These are never counted as incoming defense outcomes.
- Client effect name/channel plus a bounded scalar snapshot of its data.
- For every outcome, up to eight ranked recent animation candidates. The selected best candidate and current geometry are stored, but the alternatives remain in the raw event so later analysis can correct an uncertain automatic match.
- Anonymous source IDs, per-animation source counts, and a source-scoped cadence classifier. Sustained floods of at least five repeatedly playing Action IDs are labeled suspicious and demoted during correlation; they are never silently discarded.

## Files

The HUD displays the session directory. Relative paths are resolved inside the executor's workspace:

```text
CLAW_RECORDER/<timestamp_random-id>/
  catalog.json
  manifest.json
  events_0001.json
  events_live.json
  ...
```

`catalog.json` is the first file to send. It is bounded and aggregated by animation ID. Enemy attacks and incoming-defense outcomes are stored in `catalog`; local attacks and opponent responses are stored separately in `offenseCatalog`. The numbered chunks contain sampled detail and every outcome; `events_live.json` is an overwrite-safe checkpoint for the current unrotated events. Repetitive starts, keyframes, effect churn, and healing ticks are summarized rather than copied indefinitely. `manifest.json` lists all chunks and basic counts.

The recorder checkpoints every 15 seconds, rotates a numbered chunk when 2,000 retained events accumulate, and flushes when **SAVE NOW** is pressed or the HUD is closed. Re-executing its loader cleanly saves and closes the old recorder before starting a new session.

## HUD controls

- **PAUSE / RESUME** stops or resumes observation without touching the other hub.
- **SAVE NOW** flushes the current event buffer and refreshes the catalog.
- **COPY PATH** copies the relative session folder.
- **COPY CATALOG** copies the shareable catalog JSON, including on executors without `writefile`.
- **X** saves, disconnects the recorder's listeners, and removes only the recorder HUD.

## Collection workflow

1. Execute APC normally.
2. Execute `recorder_loader.lua` separately.
3. Confirm the HUD says `RECORDING`; `effects:connected` is ideal, while health and animation logging still work if the effect stream is unavailable.
4. Play normally. Several clean observations of the same move are more valuable than one observation.
5. Press **SAVE NOW** after the final match, then send `catalog.json`. Keep the numbered chunks until the catalog has been reviewed.

The automatic links are candidates, not ground truth. A health decrease is definite damage but may be a later burn/chip tick rather than a distinct weapon impact; a parry cooldown is evidence of a parry attempt rather than proof that the parry succeeded. Repeated samples, exact `ParrySuccess` effects, damage amounts, and the raw candidate list are what let the later builder distinguish those cases. The offensive mirror likewise reports effect correlation: it does not claim that every `Parried` or `LandedLightAttack` signal uniquely identifies one overlapping attack.

Health loss below two points is labeled `chip_or_dot`; larger loss is labeled `impact_candidate`. Both remain evidence rather than assumptions because elemental damage-over-time can arrive after the animation that originally caused it. The repository's `npm run analyze:recorder -- <session-folder>` command processes all chunks together, removes detected breaker clusters from candidate ranking, pairs the exact `ParrySuccess` effect with attempts, reports damage amounts separately from damage-tick counts, and prints opponent parry/land response timing from v0.3 sessions.

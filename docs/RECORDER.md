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
- Local health loss, posture/break-meter changes, all replicated local effect additions/removals, and selected effect outcomes including parry attempts/frames/signals, blocking, dodging, iframes, stun, and knockdown.
- Client effect name/channel plus a bounded scalar snapshot of its data.
- For every outcome, up to eight ranked recent animation candidates. The selected best candidate and current geometry are stored, but the alternatives remain in the raw event so later analysis can correct an uncertain automatic match.

## Files

The HUD displays the session directory. Relative paths are resolved inside the executor's workspace:

```text
CLAW_RECORDER/<timestamp_random-id>/
  catalog.json
  manifest.json
  events_0001.json
  events_0002.json
  ...
```

`catalog.json` is the first file to send. It is bounded and aggregated by animation ID. The event chunks contain the lossless timeline and are useful when a catalog sample appears misidentified. `manifest.json` lists all chunks and basic counts.

The recorder saves every 15 seconds, when 250 buffered events accumulate, when **SAVE NOW** is pressed, and when the HUD is closed. Re-executing its loader cleanly saves and closes the old recorder before starting a new session.

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

The automatic links are candidates, not ground truth. Health loss is a definite hit, but a parry cooldown is evidence of a parry attempt rather than proof that the parry succeeded. Repeated samples and the raw candidate list are what let the later builder distinguish those cases.

# CLAW Control changelog

## 0.3.0-beta.3

- Stop clears old movement commands. Disconnecting or changing the main stops cloud movement.
- Standby accounts stay put. Old commands cannot survive a pairing-key change.
- Ready checks compare the actual servers, not just the last status.
- Fixed false item gains after respawning and oversized loot messages.
- Closed bank windows keep the last scan. Movement restores an empty controller correctly.
- Emergency stop also blocks the follow buttons. Fixed active-team changes and overlapping disconnect alerts.

## 0.3.0-beta.2

- Disconnect alerts no longer wait behind a later disconnect.

## 0.3.0-beta.1

- Teams, deployment, ready checks and formations.
- Cloud bring, stop, parking spots and emergency stop.
- Recovery settings, presets and the Enmity team flow.
- Item scans, loot history, sessions and character notes.
- Optional Discord alerts.

Movement, recovery and alerts stay off until requested.

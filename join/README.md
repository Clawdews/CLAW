# Exact-server join test

A manual test for joining the main's exact server. The regular alt manager and loot notifier are unchanged.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/server-join/join-test.lua?t=" .. tostring(os.time())))()
```

1. On the main, inside the world, press **COPY MAIN TARGET**.
2. On an alt, load the test at the character menu before selecting a slot.
3. Select a character normally. Wait for `SLOT_READY`, paste the ticket and press **JOIN EXACT SERVER**.
4. After teleporting, run the same loader within two minutes. It checks arrival without sending another join.

Disable competing automatic slot-selection/server-hop scripts during the test. CLAW does not change them.

The default join ID is the main's `game.JobId`. The optional override accepts PR's copied server ID, not a script. It changes only the requested join ID; arrival must still match the main's captured place and server.

| Status | Meaning |
| --- | --- |
| `SLOT_READY` | A fresh slot/server-list response arrived |
| `REQUESTED` | One join request was sent |
| `TRAVELLING` | Teleport started |
| `WAITING_MAIN` | Correct server; waiting for the main to appear |
| `VERIFIED` | Account, destination and main presence matched |
| `WRONG_DESTINATION` | Arrival did not match |
| `FAILED` / `TIMED_OUT` | Stopped; copy the report |
| `STALE` | A previously checked destination or main presence changed |

Slot IDs are compared when available; missing slot data is not treated as verified. Tickets expire after ten minutes. Arrival checks time out after two. Closing the panel cannot undo an accepted teleport.

## Implementation

The join route follows [Lycoris's ServerHop module](https://git.blastbrean.com/lycoris/deepwoken-rewrite/src/branch/main/Game/ServerHop.lua): `Requests.ShowServers`, then `Requests.StartMenu.PickServer`.

[core.lua](core.lua) handles state; [join-test.lua](../join-test.lua) handles game services and the test panel. Pending checks use teleport settings and, when available, one overwritten file at `CLAW_JOIN_TEST/<UserId>.json`. Reports contain account/server IDs and a bounded event history. Nothing is uploaded.

```sh
node tests/run-join-tests.mjs /path/to/luau
```

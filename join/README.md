# Exact-server join test

Experimental branch: `codex/server-join`. The regular `main/loader.lua`, alt movement and loot notifier are unchanged.

This tests one thing: can an alt join the main's exact server through Deepwoken's own server-selection request, including when that server isn't listed to the alt?

The user has now confirmed a successful live join with `VERIFIED`. Automated delivery is being developed separately in [CLAW Control](../control/README.md); this manual test remains unchanged.

It is not a Discord bot, automatic rejoin system or proximity logger. No join happens on load. The small in-game panel is temporary test equipment, not the planned control panel.

## Try it with one alt

Use a test alt with no competing auto-start or server-hop scripts. CLAW RELAY's `AutoStart` and another hub's auto-start can leave the menu before you select a slot. This test does not disable or edit those scripts for you.

Run this on the main and the test alt:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/codex/server-join/join-test.lua?t=" .. tostring(os.time())))()
```

1. **Main, inside the world:** press **COPY MAIN TARGET**. Stay in that server.
2. **Alt, at the main menu:** load the test **before** selecting a character slot. Select the intended slot using the game's normal UI. Wait for `SLOT_READY`, paste the ticket into the large box, then press **JOIN EXACT SERVER**. Do not click a normal server as well.
3. **After teleport:** run the same test again within two minutes of the request, or use that same loadstring in the test alt's autoexec. It resumes the arrival check only. It does not send another join.
4. Look for **VERIFIED**. If it fails or times out, press **COPY REPORT** and send the report back.

If you loaded the test after selecting a slot, go back and select the slot again. The test deliberately waits for a fresh `ShowServers` event rather than guessing which character the game selected.

Tickets expire after ten minutes. The arrival check times out after two minutes. Copy a fresh ticket if the main changes servers. Closing the panel cancels tracking, but cannot undo a teleport Roblox already accepted.

### Which server ID?

The first candidate is the main's `game.JobId`. **Its equivalence to the ID accepted by Deepwoken's `PickServer` has not been verified in-game.**

If that candidate fails, paste PR's raw copied server ID into the main's optional override field, then copy a new ticket and repeat. Don't paste a loadstring there. The override changes only the ID sent to `PickServer`; the expected arrival stays the main's captured `PlaceId` and `JobId`.

This makes the comparison useful: a request with PR's ID can succeed without weakening the check that the alt actually arrived beside the main. A server absent from the alt's listing is not rejected locally. Server-side restrictions, a full server or a dead instance may still reject the request.

## What each result means

| Status | Meaning |
| --- | --- |
| `SLOT_READY` | The game sent its slot/server-list response after the test loaded. |
| `REQUESTED` | One `PickServer` call was issued. This is not success. |
| `TRAVELLING` | Roblox reported teleport start. This is still not arrival. |
| `WAITING_MAIN` | Exact experience/place/server matched, but the main's UserId is not present yet. |
| `VERIFIED` | Correct alt account, exact experience/place/server, and main's numeric UserId are present. If slot IDs were available at both ends, they matched too. |
| `WRONG_DESTINATION` | Client arrived somewhere other than the captured destination. No fallback is attempted. |
| `FAILED` / `TIMED_OUT` | The request or check failed. Details are in the report; no automatic retry. |
| `STALE` | A previously verified server/account/main-presence check changed. No automatic rejoin. |

The selected slot is recorded when the game exposes `DataSlot`; missing slot metadata is not claimed as verified. A ticket is manually supplied data, not a signed authorization token. Only paste tickets you created on your main.

## Implementation

The route was identified in Lycoris's [`Game/ServerHop.lua`](https://git.blastbrean.com/lycoris/deepwoken-rewrite/src/branch/main/Game/ServerHop.lua): slot selection produces `Requests.ShowServers`, then a server ID is sent to `Requests.StartMenu.PickServer`. The supplied PX source uses the same request shape. PR's internal implementation has **not** been inspected or reproduced.

This test selects no slot itself, sends the requested ID once, and never chooses another server on failure. The state machine is original code in [`core.lua`](core.lua); [`../join-test.lua`](../join-test.lua) handles Roblox services, persistence and the panel.

Pending checks are saved under `CLAW_JOIN_TEST_v1_<UserId>` in [TeleportService's client teleport settings](https://create.roblox.com/docs/reference/engine/classes/TeleportService/SetTeleportSetting). When executor file functions are available, a second copy is written to `CLAW_JOIN_TEST/<UserId>.json` in the executor workspace. At least one method must pass a write/read-back check before a join is sent. Reload only verifies; it never resends a saved request.

Files/reports contain account IDs, destination IDs, slot metadata and a bounded 40-event history. No cookies, Discord tokens or webhook credentials are requested. No report is uploaded. The only HTTP download is this test's core module from the public CLAW branch.

## Local checks

With Node and Luau installed:

```sh
node tests/run-join-tests.mjs /path/to/luau
luau-compile --null join/core.lua join-test.lua
```

If Luau is at `.tools/luau/bin/luau.exe`, omit the path argument on Windows. The runner generates an ignored smoke-test input from the current source, then runs 35 state-machine tests and 9 adapter/UI-wiring tests. The mocks cover controls, persistence, exact-ID dispatch and reload. They do **not** verify real game remotes, cross-client behavior, rendering or successful live teleports.

## Next, if this passes

1. Test a server visible to the main but absent from the alt's list; compare default JobId and PR's copied ID. Then test an expired ticket and the main leaving before arrival.
2. Make the confirmed route a reusable join module with explicit main/alt account configuration. Keep the working movement script separate until this passes live tests.
3. Build a hosted Discord control service: restricted commands, per-alt credentials, expiring commands, heartbeat status, and arrival acknowledgements. No localhost service; no Discord bot token or Roblox cookies in Lua.
4. Add proximity exit/rejoin as a separate opt-in state machine: recognize trusted accounts, wait until the destination is safe, cap retries, and avoid rejoin loops. Returning to menu, a teleport failure, and a closed Roblox process need different handling.

Hosting/deployment for the Discord service is still to be chosen. Nothing has been created in your Discord account, and automatic reconnect is not part of this test.

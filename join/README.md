# Exact-server join test

Manual test for the server-join route:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/server-join/join-test.lua?t=" .. tostring(os.time())))()
```

1. In-world on the main, press **COPY MAIN TARGET**.
2. At character selection on the alt, load the test and choose a slot.
3. After `SLOT_READY`, paste the ticket and press **JOIN EXACT SERVER**.
4. Run the loader again after teleporting to check arrival.

Disable other slot-selection and server-hop scripts during the test. Tickets expire after ten minutes; arrival checks stop after two minutes.

`VERIFIED` means the account, destination and main presence matched. `FAILED`, `TIMED_OUT` or `WRONG_DESTINATION` means the test stopped.

The route uses `Requests.ShowServers` followed by `Requests.StartMenu.PickServer`, based on [Lycoris ServerHop](https://git.blastbrean.com/lycoris/deepwoken-rewrite/src/branch/main/Game/ServerHop.lua).

Run tests with `node tests/run-join-tests.mjs /path/to/luau`.

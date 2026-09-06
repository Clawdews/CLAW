# CLAW Notes

The compact panel follows the game's Notes button. It starts idle.

- **DROP** sends one drop. The default **MAX** uses the smaller of 1,000 and the current prompt's allowed amount, including uneven amounts such as 553.
- **START AUTO** requests one maximum drop, checks the displayed balance decrease, waits three seconds, returns through the normal menu, selects the same character slot and rejoins the exact saved server. It repeats only while notes remain.
- **STOP AUTO** cancels further work. Collapsing or stopping the panel also cancels automation. A request already sent cannot be undone.
- The small **AMOUNT / MAX** label restores MAX after entering a custom amount. Auto always uses MAX regardless of that manual field.

Auto requires a notes-project execution key retained by the wrapper, a supported teleport queue, readable Notes balance UI and an unambiguous connected Notes-button handler. If automatic opening is unavailable, open Notes manually. The learned remote is scoped to the current character/server and is never guessed from a previous session's name.

It stops on zero notes, 100 drops, 30 minutes, ambiguous balance changes, wrong account/slot/server, expired state, another active manager/bringer, or a failed return/join. It does not choose a different server if the saved one is gone or full. Unknown drop results block further sending until rejoin. No combat restriction is bypassed.

The current standalone version deliberately does not run beside the manager/bringer. A coordinated combined flow is future work; unrelated movement code is unchanged.

## Protected loader

Keep the user's existing notes-only key above the permanent URL. The retained execution key lets a queued rejoin authenticate again; no dashboard API credential belongs here.

```lua
script_key = "YOUR_NOTES_EXECUTION_KEY";
getgenv().CLAW_NOTES_EXECUTION_KEY = script_key;
local ok = pcall(function()
    loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"))()
end)
if not ok then warn("[CLAW] Notes loader stopped. Check your key and connection.") end
```

`tools/build-notes-loader.mjs` refreshes the already-created friend's ignored wrapper without changing or creating the key. Do not run a friend's device-bound key on the owner's PC.

## Automatic publishing from a Windows PC

`tools/luarmor-publisher.mjs` reads only `notes-dropper.lua` from the private `control-beta` branch after **Notes release checks** pass for that exact revision. It repeats local compilation and tests, checks credential patterns, then updates only the existing CLAW Notes Luarmor script. It does not execute GitHub workflow commands on the PC, upload the dirty working tree, update its own tooling, or change other CLAW scripts.

The API key is stored in ignored `.tools/luarmor-publisher/api-key.dpapi`, protected by the current Windows user. Windows login protection does not protect against software already running as that user. GitHub uses the existing local Git sign-in. No API key is stored in GitHub Actions or the game script.

After authorizing the PC's public IP in Luarmor and saving the existing API key through the one-use `node tools/luarmor-publisher-setup.mjs` local form:

```powershell
./tools/install-luarmor-publisher.ps1 -Action Install
node tools/luarmor-publisher.mjs --once
./tools/install-luarmor-publisher.ps1 -Action Status
./tools/install-luarmor-publisher.ps1 -Action Disable
```

The task checks every two minutes while the PC is awake and this Windows user is signed in. It catches up after downtime and does not wake the PC. If the public IP changes, Luarmor may require it to be authorized again. Unchanged source is not reuploaded.

A persisted pending-upload record blocks automatic retries after an uncertain result. Inspect Luarmor and the exact candidate hash before resolving it; never delete the pending record simply to make an error go away. A leftover lock after a crash similarly needs inspection. API acceptance is not proof that obfuscation completed; verify the first release in the dashboard.

## Tests and live checks

```powershell
node tests/run-notes-dropper-tests.mjs
node --test tests/luarmor-publisher.test.mjs
node tools/check-public.mjs
```

The suites use mock game services; they do not establish real game compatibility or ban safety. Live checks still required: displayed Notes balance path, connected button activation after rejoin, protected loader continuation, same-slot/same-server return, Stop during countdown, and an uneven final balance. Observe the first run; do not assume unattended operation is proven.

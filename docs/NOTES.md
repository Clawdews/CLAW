# CLAW Notes

The compact panel follows the game's Notes button. A new account starts with Auto OFF.

- **DROP** drains the chosen total, using batches of at most 1,000 and waiting one second between confirmed batches. MAX means the entire starting balance. Entering more than the balance clips to what is actually available: MAX or 5,000 with 3,500 sends 1,000 + 1,000 + 1,000 + 500. Entering 2,500 with 3,500 leaves 1,000.
- **AUTO OFF** is a toggle. Click it once to save ON for this Roblox account on this executor/device and drain all notes now. At zero it stays ON, armed for the next join; it does not continuously drain newly earned notes in the current session.
- **AUTO ON / STOP** saves OFF and cancels further batches. During a manual batch the same control reads **STOP DROP**. Collapsing/stopping the panel also cancels and saves OFF. A submitted request cannot be undone.
- **TOTAL / MAX** restores MAX after entering a custom total. Auto always drains all notes, ignoring the manual total.
- **There is no automatic rejoin, leave, slot selection, server selection, or movement.** The user chooses when/where to join. An enabled account drops from the character loaded on that join, including a different slot/server.

Auto requires writable executor-local files, a notes-project execution key retained by the wrapper, a supported teleport queue, readable Notes balance UI and an unambiguous connected Notes-button handler. It waits up to 90 seconds for startup readiness, including two seconds of stable balance on resume. If automatic opening is unavailable, open Notes manually. The learned remote is scoped to the current character/server and is never guessed from a previous session's name.

Auto ON/OFF is saved in the executor workspace under `CLAW/notes-auto-v2-<gameId>-<userId>.json`. There is no expiry or rejoin-cycle limit. A pending receipt is written before each automatic submission and cleared only after an exact displayed balance decrement. Unknown results stop further sending; a pending receipt on a later load disables Auto and asks the user to check their notes before explicitly restarting. Invalid/unreadable settings never silently enable Auto. File-save failures are reported, including when OFF could not be persisted. No dashboard credential is stored here.

Each batch uses a fresh unsubmitted dialog and its current limits. The script stops on unreadable/ambiguous balances, unexpected balance changes, a stuck old dialog, character/session change during a batch, another active manager/bringer, or uncertain submission. Balance confirmation is not independent proof that a ground item spawned. No combat restriction is bypassed.

The current standalone version deliberately does not run beside the manager/bringer. A coordinated combined flow is future work; unrelated movement code is unchanged.

## Protected loader

Keep the user's existing notes-only key above the permanent URL. The retained execution key lets the script reload after a user-initiated teleport; no dashboard API credential belongs here.

```lua
script_key = "YOUR_NOTES_EXECUTION_KEY";
getgenv().CLAW_NOTES_EXECUTION_KEY = script_key;
local ok = pcall(function()
    loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"))()
end)
if not ok then warn("[CLAW] Notes loader stopped. Check your key and connection.") end
```

`tools/build-notes-loader.mjs` generates the personal ready loader in ignored
`.tools/CLAW Notes.lua` from the separately saved notes execution key. It never
creates or changes keys. Optional `--key-file` and `--out` arguments support other
keys; ready loader outputs must remain inside the ignored `.tools` folder.

`node tools/build-notes-loader.mjs --autoexec` creates the separate ignored
`.tools/CLAW Notes Autoexec.lua`. Put this personal loader in the executor's
autoexec folder **once** for fresh Roblox launches. It only downloads the protected
script for a saved-ON account in the supported game places. Without autoexec, the
saved choice resumes when the normal loader is run, or after a user-initiated
teleport with queue support; it cannot start itself in a fresh process. Volt must
still be running/injected and configured to execute its autoexec folder. This does
not inject Volt, launch accounts, or replace PR/manager autoexec files.

Both generated loaders and the teleport continuation guard against simultaneous
duplicate loading. Turn ON once in each intended account, observe its first run,
then use AUTO ON / STOP to save OFF when finished. Filesystem support follows
[Volt's writefile documentation](https://docs.voltbz.net/docs/filesystem/writefile);
continuation uses its [teleport queue](https://docs.voltbz.net/docs/miscellaneous/queueonteleport), not a travel request.

## Automatic publishing from a Windows PC

**Current live limitation (2026-09-05):** the API key and authorized PC IP were
verified, but Luarmor rejected script uploads with HTTP 400, `Missing
x-turnstile-token header`. The installed Windows task is **disabled**. The existing
notes release was uploaded through the dashboard and remains live. The tooling
below is prepared, but unattended publishing is **not operational** until Luarmor
provides a supported way to satisfy its upload verification. Do not treat an IP
allowlist or successful account-details request as proof that uploads are allowed.
No CAPTCHA service or new paid account has been added.

`tools/luarmor-publisher.mjs` reads only `notes-dropper.lua` from the private `control-beta` branch after **Notes release checks** pass for that exact revision. It repeats local compilation and tests, checks credential patterns, then updates only the existing CLAW Notes Luarmor script. It does not execute GitHub workflow commands on the PC, upload the dirty working tree, update its own tooling, or change other CLAW scripts.

The API key is stored in ignored `.tools/luarmor-publisher/api-key.dpapi`, protected by the current Windows user. Windows login protection does not protect against software already running as that user. GitHub uses the existing local Git sign-in. No API key is stored in GitHub Actions or the game script.

After resolving that upload-access requirement, authorizing the PC's public IP in Luarmor and saving the existing API key through the one-use `node tools/luarmor-publisher-setup.mjs` local form:

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

The suites use mock game services; they do not establish real game compatibility or ban safety. Live checks still required: the actual displayed Notes balance, several batches with a fresh prompt per batch, an uneven final amount, a smaller chosen total, STOP mid-batch, ON across a user-initiated join, OFF surviving another join, and the autoexec loader after a fresh client launch. The script must never issue a leave/menu/slot/server request; static tests reject those calls. Observe the first run; do not assume unattended operation is proven.

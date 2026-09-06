import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export function buildNotesLoader(key, { autoexec = false } = {}) {
    if (!/^[A-Za-z0-9]{32}$/.test(key)) throw new Error('Expected the existing notes-only execution key, not a dashboard API key.');
    const gate = autoexec ? `
    -- Autoexec is inert until THIS Roblox account has explicitly saved Auto ON.
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
    local path = "CLAW/notes-auto-v2-" .. tostring(game.GameId) .. "-" .. tostring(p.LocalPlayer.UserId) .. ".json"
    if not isfile(path) then return end
    local raw = readfile(path)
    if type(raw) ~= "string" or #raw > 4096 then return end
    local r = game:GetService("HttpService"):JSONDecode(raw)
    if type(r) ~= "table" or r.version ~= 2 or r.enabled ~= true or type(r.pending) ~= "boolean"
        or type(r.token) ~= "string" or #r.token < 16 or #r.token > 80
        or r.accountId ~= p.LocalPlayer.UserId or r.gameId ~= game.GameId then return end
` : '';
    return `-- CLAW Notes. Private execution key; never publish this ready loader.
-- No teleport, server selection, injection, or gameplay actions in this loader.
local ok = pcall(function()
    if game.PlaceId ~= 4111023553 and game.PlaceId ~= 6473861193 and game.PlaceId ~= 6032399813 then return end
    local p = game:GetService("Players")
    local deadline = os.clock() + 120
    repeat task.wait(0.1) until p.LocalPlayer or os.clock() >= deadline
    if not p.LocalPlayer then return end
${gate}
    local e = getgenv()
    if e.CLAW_NOTES_LOADING then return end
    if e.CLAW_NOTES_DROPPER and e.CLAW_NOTES_DROPPER.uiVersion == 4 and not e.CLAW_NOTES_DROPPER.closed then
        e.CLAW_NOTES_DROPPER:show(); return
    end
    e.CLAW_NOTES_LOADING = true
    script_key = "${key}"
    e.CLAW_NOTES_EXECUTION_KEY = script_key
    local loaded = pcall(function()
        loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"))()
    end)
    e.CLAW_NOTES_LOADING = nil
    if not loaded then warn("[CLAW] Notes loader stopped. Check your key and connection.") end
end)
if not ok then warn("[CLAW] Notes loader stopped. Check local settings; no automatic retry.") end
`;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const args = process.argv.slice(2), options = {};
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--autoexec' && !options.autoexec) { options.autoexec = true; continue; }
        if (!['--key-file', '--out'].includes(args[i]) || !args[i + 1] || options[args[i]]) throw new Error('Use --key-file <file>, --out <ignored Lua file>, or --autoexec.');
        options[args[i]] = args[++i];
    }
    const output = resolve(root, options['--out'] || (options.autoexec ? '.tools/CLAW Notes Autoexec.lua' : '.tools/CLAW Notes.lua'));
    const privateRelative = relative(resolve(root, '.tools'), output);
    if (!privateRelative || privateRelative.startsWith('..') || isAbsolute(privateRelative) || !output.endsWith('.lua')) throw new Error('Ready loaders must stay inside the ignored .tools folder.');
    const key = readFileSync(resolve(root, options['--key-file'] || '.tools/luarmor-notes-owner-key.txt'), 'utf8').trim();
    writeFileSync(output, buildNotesLoader(key, options));
    console.log('Ready notes loader saved under .tools; no key created or executed by this builder.');
}

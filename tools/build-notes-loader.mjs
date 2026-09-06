import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const key = readFileSync(resolve(root, '.tools/luarmor-notes-friend-key.txt'), 'utf8').trim();
if (!/^[A-Za-z0-9]{32}$/.test(key)) throw new Error('Expected the existing notes-only execution key, not a dashboard API key.');
const loader = `-- Existing notes-only key. Do not test a friend's device-bound key on your PC.
script_key = "${key}";
getgenv().CLAW_NOTES_EXECUTION_KEY = script_key;
local ok = pcall(function()
    loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"))()
end)
if not ok then warn("[CLAW] Notes loader stopped. No automatic retry; check your key and connection.") end
`;
writeFileSync(resolve(root, '.tools/CLAW Notes Friend.lua'), loader);
console.log('Updated the existing ignored friend loader; no new key created or executed.');

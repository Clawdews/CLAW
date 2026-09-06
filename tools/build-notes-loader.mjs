import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const options = {};
for (let i = 0; i < args.length; i += 2) {
    if (!['--key-file', '--out'].includes(args[i]) || !args[i + 1] || options[args[i]]) throw new Error('Use --key-file <file> and --out <ignored Lua file>.');
    options[args[i]] = args[i + 1];
}
const output = resolve(root, options['--out'] || '.tools/CLAW Notes.lua');
const privateRelative = relative(resolve(root, '.tools'), output);
if (!privateRelative || privateRelative.startsWith('..') || isAbsolute(privateRelative) || !output.endsWith('.lua')) throw new Error('Ready loaders must stay inside the ignored .tools folder.');
const key = readFileSync(resolve(root, options['--key-file'] || '.tools/luarmor-notes-owner-key.txt'), 'utf8').trim();
if (!/^[A-Za-z0-9]{32}$/.test(key)) throw new Error('Expected the existing notes-only execution key, not a dashboard API key.');
const loader = `-- CLAW Notes. Personal execution key; never publish this ready loader.
script_key = "${key}";
getgenv().CLAW_NOTES_EXECUTION_KEY = script_key;
local ok = pcall(function()
    loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua"))()
end)
if not ok then warn("[CLAW] Notes loader stopped. No automatic retry; check your key and connection.") end
`;
writeFileSync(output, loader);
console.log('Ready notes loadstring saved under .tools; no key created or executed by this builder.');

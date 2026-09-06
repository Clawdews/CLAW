import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { buildNotesLoader } from '../tools/build-notes-loader.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceIndex = process.argv.indexOf('--source');
const luauIndex = process.argv.indexOf('--luau');
const source = readFileSync(sourceIndex >= 0 ? resolve(process.argv[sourceIndex + 1]) : resolve(root, 'notes-dropper.lua'), 'utf8');
function part(name) { const found = source.match(new RegExp('-- DROPPER_' + name + '_BEGIN\\r?\\n([\\s\\S]*?)-- DROPPER_' + name + '_END')); assert.ok(found); return found[1]; }
function quote(text) { let eq = '='; while (text.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[' + text + ']' + eq + ']'; }
assert.doesNotMatch(source, /BinciancGaj|keypress\s*\(|fireclickdetector\s*\(|clearqueueonteleport/);
assert.doesNotMatch(source, /ReturnToMenu|PickSlot|PickServer|TeleportToPlaceInstance|TeleportAsync|:\s*Teleport\s*\(/);
assert.equal((source.match(/HttpGet\s*\(/g) || []).length, 1);
assert.equal((source.match(/https:\/\//g) || []).length, 1);
assert.ok(part('RUNTIME').includes('https://api.luarmor.net/files/v4/loaders/8c5cec745c34ac98ebbfca1ee3bad27f.lua'));
assert.doesNotMatch(part('VIEW') + part('UI'), /FireServer|InvokeServer|core\s*:\s*run|task\s*\./);
const file = resolve(root, '.tools/tests/notes-dropper.generated.luau'); mkdirSync(dirname(file), { recursive: true });
writeFileSync(file, part('CORE') + '\nlocal run = require("../../tests/notes-dropper.spec")\nrun(newDropper,' + quote(part('PROMPT')) + ',' + quote(part('LEARN')) + ')\n'
  + part('AUTO') + '\nlocal autoTests = require("../../tests/notes-auto.spec")\nautoTests(newNotesLoop, validNotesRun)\n'
  + '\nlocal runtimeTests = require("../../tests/notes-runtime.spec")\nruntimeTests(' + quote(part('RUNTIME')) + ', newNotesLoop, validNotesRun,' + quote(part('BUTTON')) + ',' + quote(buildNotesLoader('A'.repeat(32), { autoexec: true })) + ',' + quote(buildNotesLoader('A'.repeat(32))) + ')\n'
  + part('VIEW') + '\nlocal uiTests = require("../../tests/notes-ui.spec")\nuiTests(notesPanelGeometry, notesPanelState,' + quote(part('UI')) + ')\n');
const result = spawnSync(luauIndex >= 0 ? resolve(process.argv[luauIndex + 1]) : resolve(root, '.tools/luau/bin', process.platform === 'win32' ? 'luau.exe' : 'luau'), [file], { cwd: root, stdio: 'inherit', timeout: 30000 });
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;

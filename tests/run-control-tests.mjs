import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const luau = process.argv[2] || resolve(root, '.tools/luau/bin', process.platform === 'win32' ? 'luau.exe' : 'luau');
function quote(source) {
  let eq = '='; while (source.includes(`]${eq}]`)) eq += '=';
  return `[${eq}[${source}]${eq}]`;
}
mkdirSync(resolve(root, '.tools/tests'), { recursive: true });
const generated = '.tools/tests/control-runtime.generated.luau';
const bundled = '.tools/tests/control-bundle.generated.luau';
const pairing = '.tools/tests/control-pairing.generated.luau';
const batch = '.tools/tests/control-batch.generated.luau';
const autoexec = '.tools/tests/control-autoexec.generated.luau';
const launcher = '.tools/tests/control-launcher.generated.luau';
const scanner = '.tools/tests/slot-scan.generated.luau';
const scannerBundle = '.tools/tests/slot-scan-bundle.generated.luau';
const movement = '.tools/tests/control-movement.generated.luau';
for (const [target, entry, bundledScan] of [[scanner, 'slot-scan.lua', false], [scannerBundle, 'dist/slot-scan.lua', true]]) {
  writeFileSync(resolve(root, target), `local run = require("../../tests/slot-scan-runtime.spec")\nrun(${quote(readFileSync(resolve(root, entry), 'utf8'))},${quote(readFileSync(resolve(root, 'control/menu-scan.lua'), 'utf8'))},${bundledScan})\n`);
}
writeFileSync(resolve(root, pairing), `local run = require("../../tests/control-pairing.spec")\nrun(${['control/pair.lua', 'control-launcher.lua', 'dist/launcher-beta.lua'].map(file => quote(readFileSync(resolve(root, file), 'utf8'))).join(',')})\n`);
writeFileSync(resolve(root, batch), `local run = require("../../tests/control-batch.spec")\nrun(${['control/batch.lua', 'control/pair.lua', 'control-launcher.lua', 'dist/launcher-beta.lua'].map(file => quote(readFileSync(resolve(root, file), 'utf8'))).join(',')})\n`);
writeFileSync(resolve(root, autoexec), `local run = require("../../tests/control-autoexec.spec")\nrun(${quote(readFileSync(resolve(root, 'control-autoexec.lua'), 'utf8'))})\n`);
const sources = ['control/client.lua', 'control/auto.lua', 'join/core.lua', 'control/regions.lua', 'control/menu-scan.lua', 'control/catalog.lua', 'control/movement.lua'].map(file => quote(readFileSync(resolve(root, file), 'utf8')));
writeFileSync(resolve(root, generated), `local run = require("../../tests/control-runtime.spec")\nrun(${sources.join(',')})\n`);
writeFileSync(resolve(root, bundled), `local run = require("../../tests/control-runtime.spec")\nrun(${[quote(readFileSync(resolve(root, 'dist/control-beta.lua'), 'utf8')), ...sources.slice(1)].join(',')})\n`);
writeFileSync(resolve(root, launcher), `local run = require("../../tests/control-runtime.spec")\nrun(${[quote(readFileSync(resolve(root, 'dist/launcher-beta.lua'), 'utf8')), ...sources.slice(1), 'true'].join(',')})\n`);
writeFileSync(resolve(root, movement), `local run = require("../../tests/control-movement.spec")\nrun(${quote(readFileSync(resolve(root, 'control/movement.lua'), 'utf8'))})\n`);
for (const file of ['tests/control-auto.spec.luau', 'tests/control-slots.spec.luau', scanner, scannerBundle, movement, generated, bundled, launcher, pairing, batch, autoexec]) {
  const result = spawnSync(luau, [file], { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

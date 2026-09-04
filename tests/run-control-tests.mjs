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
const sources = ['control/client.lua', 'control/auto.lua', 'join/core.lua'].map(file => quote(readFileSync(resolve(root, file), 'utf8')));
writeFileSync(resolve(root, generated), `local run = require("../../tests/control-runtime.spec")\nrun(${sources.join(',')})\n`);
for (const file of ['tests/control-auto.spec.luau', generated]) {
  const result = spawnSync(luau, [file], { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

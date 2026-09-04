// Regenerate the smoke-test input from the actual entrypoint; no stale source snapshots.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const luau = process.argv[2] || resolve(root, '.tools/luau/bin', process.platform === 'win32' ? 'luau.exe' : 'luau');
const quote = (source) => {
  let equals = '=';
  while (source.includes(`]${equals}]`)) equals += '=';
  return `[${equals}[${source}]${equals}]`;
};
mkdirSync(resolve(root, '.tools/tests'), { recursive: true });
const generated = '.tools/tests/join-runtime.generated.luau';
writeFileSync(resolve(root, generated),
  `local run = require("../../tests/join-runtime.spec")\nrun(${quote(readFileSync(resolve(root, 'join-test.lua'), 'utf8'))}, ${quote(readFileSync(resolve(root, 'join/core.lua'), 'utf8'))})\n`);
for (const file of ['tests/join-core.spec.luau', generated]) {
  const result = spawnSync(luau, [file], { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

// Read-only release checks plus local test/build outputs; never deploys or registers Discord commands.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export function credentialIssue(path, text) {
  const normalized = path.replaceAll('\\', '/');
  if (/(^|\/)(\.tools|CLAW_PAIRINGS|CLAW_CONTROL_BETA)(\/|$)/.test(normalized)
      || /(^|\/)(?:\.env(?:\.|$)|\.dev\.vars)/.test(normalized) && !/\.example$/.test(normalized)
      || /\.local\.(?:lua|jsonc?)$/.test(normalized)) return 'private file must not be published';
  if (/https:\/\/(?:canary\.)?discord(?:app)?\.com\/api(?:\/v\d+)?\/webhooks\/\d+\/[A-Za-z0-9_-]+/.test(text)) return 'Discord webhook credential';
  if (/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b/.test(text)) return 'GitHub credential';
  if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text)) return 'private key';
  return null;
}
function gitFiles(args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error('Unable to inspect Git paths; release check did not pass.');
  return result.stdout.split('\0').filter(Boolean);
}
export function checkPublicFiles() {
  const files = [...new Set([
    ...gitFiles(['diff', '--name-only', '-z']),
    ...gitFiles(['diff', '--cached', '--name-only', '-z']),
    ...gitFiles(['ls-files', '--others', '--exclude-standard', '-z']),
  ])];
  for (const path of files) {
    const absolute = resolve(root, path);
    if (relative(root, absolute).startsWith('..')) throw new Error('A changed path escaped the repository.');
    if (!existsSync(absolute)) continue;
    const issue = credentialIssue(path, readFileSync(absolute, 'utf8'));
    if (issue) throw new Error(`${path}: ${issue}; value not printed.`);
  }
  return files.length;
}
export function checkVersions(read = path => readFileSync(resolve(root, path), 'utf8')) {
  const version = JSON.parse(read('control/package.json')).version;
  const locked = JSON.parse(read('control/package-lock.json'));
  if (locked.version !== version || locked.packages?.['']?.version !== version) throw new Error('Package lock release version mismatch.');
  const expected = {
    'control/auto.lua': `VERSION = "${version}"`,
    'control/client.lua': `Auto.VERSION == "${version}"`,
    'control/worker.js': `version: '${version}'`,
    'control/register.mjs': `CLAW, ${version})`,
  };
  for (const [path, text] of Object.entries(expected)) if (!read(path).includes(text)) throw new Error(`Release version mismatch in ${path}`);
  if (JSON.parse(read('dist/control-beta.json')).version !== version) throw new Error('Built manifest release version mismatch.');
  return version;
}
function run(command, args, label) {
  console.log(`Checking ${label}`);
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit',
    env: { ...process.env, WRANGLER_LOG_PATH: resolve(root, '.tools/wrangler-logs') } });
  if (result.error) throw new Error(`${label} could not start (${result.error.code || 'unknown error'}).`);
  if (result.status !== 0) throw new Error(`${label} failed with exit ${result.status ?? 'unknown'}; remaining steps were not run.`);
}
export function main(args) {
  const valid = new Set(['--security-only', '--worker-build', '--luau']);
  let luau = resolve(root, '.tools/luau/bin', process.platform === 'win32' ? 'luau.exe' : 'luau');
  for (let i = 0; i < args.length; i++) {
    if (!valid.has(args[i])) throw new Error('Use --security-only, --worker-build, or --luau <path>.');
    if (args[i] === '--luau') { if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error('--luau needs a path.'); luau = resolve(args[++i]); }
  }
  const count = checkPublicFiles(); console.log(`Checked ${count} changed/staged public files for private paths and credential patterns.`);
  if (args.includes('--security-only')) return;
  console.log(`Release ${checkVersions()}`);
  if (!existsSync(luau)) throw new Error('Luau is missing. Pass --luau <path>; no compiler is downloaded automatically.');
  run(process.execPath, ['tools/build-control.mjs', '--check'], 'control bundle consistency');
  run(process.execPath, ['tools/build-slot-scan.mjs', '--check'], 'standalone scanner consistency');
  run(process.execPath, ['--test', 'tests/discord-push.test.mjs'], 'push notification tests');
  const tests = readdirSync(resolve(root, 'control/test')).filter(name => name.endsWith('.test.mjs')).map(name => 'control/test/' + name);
  run(process.execPath, ['--test', ...tests], 'Worker and release tooling tests');
  run(process.execPath, ['tests/run-control-tests.mjs', luau], 'control client and pairing tests');
  run(process.execPath, ['tests/run-join-tests.mjs', luau], 'exact-join regressions');
  if (args.includes('--worker-build')) {
    const wrangler = resolve(root, 'control/node_modules/wrangler/bin/wrangler.js');
    if (!existsSync(wrangler)) throw new Error('Install the checked-in control dependencies before the Worker dry run.');
    run(process.execPath, [wrangler, 'deploy', '--config', 'control/wrangler.shared.jsonc', '--dry-run'], 'isolated shared Worker build (no deployment)');
  }
  console.log('CLAW release checks passed. This does not claim in-game or Discord installation verification.');
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; }
}

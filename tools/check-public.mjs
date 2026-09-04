import { readFileSync, existsSync, lstatSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const limit = 128 * 1024 * 1024;

export function credentialIssue(path, text) {
  const normalized = path.replaceAll('\\', '/');
  if (/(^|\/)(?:\.tools|CLAW_PAIRINGS|CLAW_CONTROL(?:_BETA)?|CLAW_RECORDER)(\/|$)/i.test(normalized)
      || /(^|\/)(?:\.env(?:\.|$)|\.dev\.vars(?:\.|$))/i.test(normalized) && !/\.example$/i.test(normalized)
      || /(?:\.local\.(?:lua|jsonc?)|project_rain_with_loot\.lua)$/i.test(normalized)
      || /(^|\/)(?:config\.local\.|secrets\.)/i.test(normalized)) return 'private file must not be published';
  if (/https:\/\/(?:(?:canary|ptb)\.)?discord(?:app)?\.com\/api(?:\/v\d+)?\/webhooks\/\d+\/[A-Za-z0-9_-]+/i.test(text)) return 'Discord webhook credential';
  if (/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b/.test(text)) return 'GitHub credential';
  if (/-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/.test(text)) return 'private key';
  if (/\b(?:[A-Za-z0-9_-]{23,30}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}|mfa\.[A-Za-z0-9_-]{60,})\b/.test(text)) return 'Discord token';
  if (/_\|WARNING:-DO-NOT-SHARE-THIS\.[^\s"']{30,}/.test(text)) return 'Roblox session cookie';
  if (/\b(?:CLIENT_KEY|ACCOUNT_KEY|BOT_TOKEN|API_TOKEN|API_KEY|TOKEN|Secret|ClientKey|AccountKey|Key)["']?\s*[=:]\s*["'][A-Za-z0-9_./+=-]{24,}["']/i.test(text)) return 'hardcoded credential';
  if (/[A-Za-z]:[\\/]+Users[\\/]+(?!PUBLIC\b|USERNAME\b|YOUR_)[A-Za-z0-9._-]+[\\/]/i.test(text)) return 'personal computer path';
  return null;
}

function git(cwd, args, input) {
  const result = spawnSync('git', args, { cwd, input, maxBuffer: limit });
  if (result.error || result.status !== 0) throw new Error('Cannot read Git data; privacy check did not pass.');
  return result.stdout;
}
function check(path, text, source) {
  const issue = credentialIssue(path, text);
  if (issue) throw new Error(`${JSON.stringify(path)} (${source}): ${issue}; value not printed.`);
}
function checkObjects(cwd, objects) {
  if (!objects.length) return;
  const output = git(cwd, ['cat-file', '--batch'], objects.map(item => item.oid).join('\n') + '\n');
  let offset = 0;
  for (const object of objects) {
    const end = output.indexOf(10, offset);
    if (end < 0) throw new Error('Incomplete Git object response.');
    const [oid, type, length] = output.subarray(offset, end).toString('utf8').split(' ');
    const size = Number(length);
    if (oid !== object.oid || !Number.isSafeInteger(size) || size < 0 || end + size + 1 >= output.length) throw new Error('Incomplete Git object response.');
    if (['blob', 'commit', 'tag'].includes(type)) check(object.path || type, output.subarray(end + 1, end + 1 + size).toString('utf8'), object.oid.slice(0, 12));
    offset = end + size + 2;
  }
}

export function checkPublicFiles({ cwd = root } = {}) {
  const staged = git(cwd, ['ls-files', '--stage', '-z']).toString('utf8').split('\0').filter(Boolean).map(line => {
    const tab = line.indexOf('\t');
    const [mode, oid, stage] = line.slice(0, tab).split(' ');
    const path = line.slice(tab + 1);
    if (stage !== '0' || !['100644', '100755'].includes(mode)) throw new Error('Resolve conflicts, symlinks or submodules before publishing.');
    return { oid, path };
  });
  // Read the index too: a clean working copy can hide an unsafe staged version.
  checkObjects(cwd, staged);
  const paths = [...new Set([...staged.map(item => item.path), ...git(cwd, ['ls-files', '--others', '--exclude-standard', '-z']).toString('utf8').split('\0').filter(Boolean)])];
  for (const path of paths) {
    const absolute = resolve(cwd, path);
    if (relative(cwd, absolute).startsWith('..')) throw new Error('A public path escaped the repository.');
    if (!existsSync(absolute)) continue;
    if (!lstatSync(absolute).isFile()) throw new Error('Only regular files may be scanned for publication.');
    check(path, readFileSync(absolute, 'utf8'), 'working copy');
  }
  return paths.length;
}

export function checkHistory({ cwd = root } = {}) {
  if (git(cwd, ['rev-parse', '--is-shallow-repository']).toString('utf8').trim() === 'true') throw new Error('History is incomplete. Fetch full history before using --history.');
  const objects = git(cwd, ['rev-list', '--objects', '--all']).toString('utf8').split(/\r?\n/).filter(Boolean).map(line => ({ oid: line.slice(0, 40), path: line.slice(41) }));
  checkObjects(cwd, objects);
  return objects.length;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    if (process.argv.slice(2).some(arg => arg !== '--history')) throw new Error('Use --history to include all fetched branches and tags.');
    console.log(`Checked ${checkPublicFiles()} public files, including staged contents.`);
    if (process.argv.includes('--history')) console.log(`Checked ${checkHistory()} historical Git objects.`);
    console.log('No configured credential patterns or private paths found. Review personal data before sharing; this is not a guarantee.');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

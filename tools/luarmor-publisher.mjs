import { readFileSync, writeFileSync, mkdirSync, openSync, closeSync, unlinkSync, existsSync, renameSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { credentialIssue } from './check-public.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const home = resolve(root, '.tools/luarmor-publisher');
export const target = Object.freeze({ repo: 'Clawdews/CLAW', branch: 'control-beta', source: 'notes-dropper.lua',
  project: '7ff29ee35ff02cb0c004cdae1b1605f7', script: '8c5cec745c34ac98ebbfca1ee3bad27f' });
export const digest = data => createHash('sha256').update(data).digest('hex');
const sha = value => typeof value === 'string' && /^[0-9a-f]{40}$/.test(value);
function requireThat(ok, message) { if (!ok) throw new Error(message); }
function windowsPowerShellEnv() {
  const env = { ...process.env };
  // A Node child inherits PowerShell 7's module path, which Windows PowerShell cannot load.
  for (const key of Object.keys(env)) if (key.toLowerCase() === 'psmodulepath') delete env[key];
  return env;
}
export function validateSource(source) {
  requireThat(typeof source === 'string' && Buffer.byteLength(source) >= 1000 && Buffer.byteLength(source) <= 500000, 'Invalid source size.');
  requireThat(source.startsWith('-- CLAW notes dropper.'), 'Not the CLAW notes source.');
  requireThat(!credentialIssue(target.source, source), 'Source failed the credential/privacy check.');
  requireThat(!/script_key\s*=\s*["'][A-Za-z0-9]{32}["']/.test(source), 'An execution key must not be uploaded.');
  return source;
}
export async function jsonRequest(url, options = {}, fetcher = fetch) {
  let response;
  try { response = await fetcher(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(90000) }); }
  catch { throw new Error('Network request failed. Response and credentials withheld.'); }
  requireThat(response.ok, `Service returned HTTP ${response.status}.`);
  requireThat((response.headers.get('content-type') || '').includes('application/json'), 'Service did not return JSON.');
  let text;
  try { text = await response.text(); requireThat(text.length <= 3000000, 'Response too large.'); return JSON.parse(text); }
  catch { throw new Error('Service returned invalid JSON.'); }
}
export async function githubSnapshot(credential, fetcher = fetch) {
  const base = `https://api.github.com/repos/${target.repo}`;
  const headers = { Authorization: `Bearer ${credential}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
  const get = path => jsonRequest(base + path, { headers }, fetcher);
  const repo = await get('');
  requireThat(repo.private === true && repo.full_name === target.repo, 'Publisher only accepts the private CLAW repository.');
  const commit = await get(`/commits/${target.branch}`);
  requireThat(sha(commit.sha), 'Invalid GitHub revision.');
  const checks = await get(`/commits/${commit.sha}/check-runs?per_page=100`);
  const relevant = checks.check_runs?.filter(c => c.name === 'Notes release checks' && c.app?.slug === 'github-actions' && c.head_sha === commit.sha) || [];
  relevant.sort((a, b) => b.id - a.id);
  if (relevant[0]?.status !== 'completed' || relevant[0]?.conclusion !== 'success') return { waiting: true, revision: commit.sha };
  const blob = await get(`/contents/${target.source}?ref=${commit.sha}`);
  requireThat(blob.type === 'file' && blob.path === target.source && blob.encoding === 'base64' && blob.size <= 500000 && typeof blob.content === 'string', 'Invalid GitHub source file.');
  const bytes = Buffer.from(blob.content, 'base64');
  requireThat(bytes.length === blob.size, 'Incomplete source download.');
  const source = validateSource(bytes.toString('utf8'));
  return { revision: commit.sha, hash: digest(source), source };
}
export async function uploadSource(source, credential, fetcher = fetch) {
  validateSource(source);
  requireThat(typeof credential === 'string' && /^[A-Za-z0-9_-]{32,160}$/.test(credential), 'Invalid Luarmor API credential.');
  // Only documented flags are sent. Do not reset users, rotate keys or touch other projects.
  const response = await jsonRequest(`https://api.luarmor.net/v3/projects/${target.project}/scripts/${target.script}`, {
    method: 'PUT', headers: { Authorization: credential, 'Content-Type': 'application/json' },
    body: JSON.stringify({ script: source, silent: false, ffa: false, heartbeat: true, lightning: false }),
  }, fetcher);
  requireThat(response.success === true, 'Luarmor did not confirm acceptance. Check the dashboard before retrying.');
  return { accepted: true }; // Acceptance is not proof of completed obfuscation or in-game execution.
}
function statePath(name) { return resolve(home, name); }
function readState() { return existsSync(statePath('state.json')) ? JSON.parse(readFileSync(statePath('state.json'), 'utf8')) : {}; }
function saveState(state) {
  const data = JSON.stringify(state, null, 2) + '\n';
  writeFileSync(statePath('state.pending.json'), data, { mode: 0o600 });
  renameSync(statePath('state.pending.json'), statePath('state.json'));
}
function status(message) {
  writeFileSync(statePath('status.json'), JSON.stringify({ time: new Date().toISOString(), message }, null, 2) + '\n');
  console.log(message);
}
function gitCredential() {
  const result = spawnSync('git', ['credential', 'fill'], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 20000,
    input: 'protocol=https\nhost=github.com\n\n', env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never' } });
  requireThat(result.status === 0, 'Saved GitHub sign-in is unavailable.');
  const value = result.stdout.split(/\r?\n/).find(line => line.startsWith('password='))?.slice(9); result.stdout = '';
  requireThat(value, 'Saved GitHub sign-in is unavailable.'); return value;
}
function apiCredential() {
  const encrypted = readFileSync(statePath('api-key.dpapi'), 'utf8');
  const command = '$s = ConvertTo-SecureString ([Console]::In.ReadToEnd()); $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { [Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }';
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { input: encrypted, encoding: 'utf8', windowsHide: true, timeout: 15000, env: windowsPowerShellEnv() });
  requireThat(result.status === 0, 'Cannot unlock the API key with this Windows account.');
  return result.stdout.trim();
}
function verifyLocally(source) {
  const file = statePath('candidate.lua'); writeFileSync(file, source);
  for (const [command, args] of [
    [resolve(root, '.tools/luau/bin/luau-compile.exe'), ['--null', file]],
    [process.execPath, [resolve(root, 'tests/run-notes-dropper-tests.mjs'), '--source', file]],
  ]) {
    const result = spawnSync(command, args, { cwd: root, timeout: 45000, windowsHide: true, encoding: 'utf8', maxBuffer: 2000000 });
    requireThat(result.status === 0, 'Downloaded release failed local compilation/tests. Nothing uploaded.');
  }
}
export async function publishOnce(deps) {
  const previous = deps.readState();
  if (previous.pending) return deps.status('Upload outcome needs dashboard review; automatic retries are paused.');
  const snapshot = await deps.snapshot();
  if (snapshot.waiting) return deps.status('Waiting for Notes release checks on GitHub.');
  if (previous.hash === snapshot.hash) return deps.status('Up to date. No upload needed.');
  await deps.verify(snapshot.source);
  const pending = { revision: snapshot.revision, hash: snapshot.hash, time: new Date().toISOString() };
  deps.saveState({ ...previous, pending }); // Durable gate before the external mutation.
  await deps.upload(snapshot.source);
  deps.saveState({ revision: snapshot.revision, hash: snapshot.hash, acceptedAt: new Date().toISOString() });
  deps.status('Luarmor accepted the notes update. The loader URL is unchanged.');
}
async function main() {
  mkdirSync(home, { recursive: true });
  const mode = process.argv[2] || '--once';
  if (mode === '--status') { console.log(existsSync(statePath('status.json')) ? readFileSync(statePath('status.json'), 'utf8') : 'Not configured.'); return; }
  if (mode === '--save-key') {
    requireThat(process.platform === 'win32', 'Windows DPAPI is required.');
    requireThat(!existsSync(statePath('api-key.dpapi')), 'A saved key already exists; do not overwrite it blindly.');
    let input = ''; for await (const chunk of process.stdin) input += chunk;
    input = input.trim(); requireThat(/^[A-Za-z0-9_-]{32,160}$/.test(input), 'Invalid API credential.');
    const command = '$s = ConvertTo-SecureString ([Console]::In.ReadToEnd()) -AsPlainText -Force; [Console]::Out.Write((ConvertFrom-SecureString $s))';
    const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { input, encoding: 'utf8', windowsHide: true, timeout: 15000, env: windowsPowerShellEnv() });
    input = ''; requireThat(result.status === 0 && result.stdout.length > 100, 'Windows key protection failed.');
    writeFileSync(statePath('api-key.dpapi'), result.stdout, { flag: 'wx', mode: 0o600 }); status('API key stored using Windows user protection.'); return;
  }
  requireThat(mode === '--once' || mode === '--check', 'Use --once, --check, --status or --save-key.');
  requireThat(process.platform === 'win32', 'This publisher is configured for Windows.');
  // Fail closed after a crash: do not steal a stale lock automatically while an upload may still be running.
  let lock;
  try { lock = openSync(statePath('upload.lock'), 'wx'); } catch { status('Uploader lock exists. Another run or an interrupted run needs checking.'); return; }
  try {
    if (mode === '--check') {
      const snapshot = await githubSnapshot(gitCredential());
      status(snapshot.waiting ? 'Waiting for Notes release checks on GitHub.' : `Ready revision ${snapshot.revision.slice(0, 12)}.`); return;
    }
    requireThat(existsSync(statePath('enabled')), 'Automatic publishing is not enabled.');
    await publishOnce({ readState, saveState, status, snapshot: () => githubSnapshot(gitCredential()), verify: verifyLocally,
      upload: source => uploadSource(source, apiCredential()) });
  } finally { closeSync(lock); unlinkSync(statePath('upload.lock')); }
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { status(error.message || 'Publisher stopped.'); process.exitCode = 1; });
}

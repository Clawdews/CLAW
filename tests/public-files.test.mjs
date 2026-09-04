import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync, readdirSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, relative, isAbsolute } from 'node:path';
import { credentialIssue, checkPublicFiles, checkHistory } from '../tools/check-public.mjs';

const fake = () => 'ghp_' + 'a'.repeat(40);
function repository(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'claw-privacy-'));
  function remove(path) { for (const entry of readdirSync(path, { withFileTypes: true })) { const child = join(path, entry.name); if (entry.isDirectory()) remove(child); else unlinkSync(child); } rmdirSync(path); }
  t.after(() => {
    const target = realpathSync(cwd), inside = relative(realpathSync(tmpdir()), target);
    if (!inside || inside.startsWith('..') || isAbsolute(inside) || !inside.startsWith('claw-privacy-')) throw new Error('Refusing cleanup outside the test directory.');
    remove(target);
  });
  const git = (...args) => execFileSync('git', args, { cwd, stdio: 'pipe', env: { ...process.env, GIT_AUTHOR_NAME: 'Test', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Test', GIT_COMMITTER_EMAIL: 'test@example.com' } });
  git('init', '--quiet');
  const write = (file, content) => writeFileSync(join(cwd, file), content);
  return { cwd, git, write };
}

test('private executor files and configuration cannot be published', () => {
  for (const path of ['.tools/private.json', 'CLAW_PAIRINGS/1.json', 'CLAW_CONTROL_BETA/1.json', 'CLAW_CONTROL/menu-1.json',
    'CLAW_RECORDER/events.json', 'control/.dev.vars.production', 'control/.env', 'control/wrangler.shared.local.jsonc', 'project_rain_with_loot.lua', 'secrets.json']) assert.ok(credentialIssue(path, '{}'));
  for (const path of ['control/.env.example', 'control/.env.shared.example', 'docs/PRIVACY.md']) assert.equal(credentialIssue(path, ''), null);
});
test('credential errors contain categories, never secret values', () => {
  const samples = [fake(), 'https://ptb.discord.com/api/v10/' + 'webhooks/123/' + 'test-value',
    '-----BEGIN ' + 'ENCRYPTED PRIVATE KEY-----', 'A'.repeat(24) + '.' + 'B'.repeat(6) + '.' + 'C'.repeat(30),
    '_|WARNING:' + '-DO-NOT-SHARE-THIS.' + 'x'.repeat(50), 'Key="' + 'a'.repeat(64) + '"',
    'BOT_TOKEN = "' + 'z'.repeat(35) + '"', ['C:', 'Users', 'ExamplePerson', 'Desktop'].join('\\')];
  for (const sample of samples) { const issue = credentialIssue('sample.txt', sample); assert.ok(issue); assert.ok(!issue.includes(sample)); }
  assert.equal(credentialIssue('manifest.json', '{"sha256":"' + 'a'.repeat(64) + '"}'), null);
});
test('clean checkouts are scanned, not only changed files', t => {
  const r = repository(t); r.write('sample.txt', fake()); r.git('add', '.'); r.git('commit', '-qm', 'fixture');
  assert.throws(() => checkPublicFiles(r), /GitHub credential/);
});
test('unsafe staged contents are caught even when the working file is clean', t => {
  const r = repository(t); r.write('sample.txt', fake()); r.git('add', '.'); r.write('sample.txt', 'safe');
  assert.throws(() => checkPublicFiles(r), /GitHub credential/);
});
test('working and untracked files are scanned; ignored private files are not published', t => {
  const r = repository(t); r.write('sample.txt', 'safe'); r.write('.gitignore', 'private.txt\n'); r.git('add', '.');
  r.write('private.txt', fake()); assert.equal(checkPublicFiles(r), 2);
  r.write('sample.txt', fake()); assert.throws(() => checkPublicFiles(r), /GitHub credential/);
  r.write('sample.txt', 'safe'); r.write('new.txt', fake()); assert.throws(() => checkPublicFiles(r), /GitHub credential/);
});
test('deleted secrets remain detectable in history', t => {
  const r = repository(t); r.write('sample.txt', fake()); r.git('add', '.'); r.git('commit', '-qm', 'fixture');
  r.write('sample.txt', 'safe'); r.git('add', '.'); r.git('commit', '-qm', 'replace');
  assert.equal(checkPublicFiles(r), 1); assert.throws(() => checkHistory(r), /GitHub credential/);
});
test('safe history passes and secret-bearing commit messages do not', t => {
  const r = repository(t); r.write('sample.txt', 'safe'); r.git('add', '.'); r.git('commit', '-qm', 'fixture');
  assert.ok(checkHistory(r) > 0);
  r.git('commit', '--allow-empty', '-qm', fake()); assert.throws(() => checkHistory(r), /GitHub credential/);
});

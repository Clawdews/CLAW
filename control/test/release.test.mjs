import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { credentialIssue, checkVersions } from '../../tools/check-control.mjs';

test('release gate catches private paths even after files have been staged', () => {
  for (const path of ['.tools/private.json', 'control/.env', 'control/.env.production', 'control/.dev.vars',
    'control/wrangler.shared.local.jsonc', 'CLAW_PAIRINGS/22.json', 'CLAW_CONTROL_BETA/user.json']) assert.ok(credentialIssue(path, '{}'));
  for (const path of ['control/.env.shared.example', 'control/.env.example', 'control/worker.js', 'docs/CONTROL-SETUP.md']) assert.equal(credentialIssue(path, ''), null);
});
test('release gate detects credential families without returning credential values', () => {
  const samples = ['https://discord.com/api/' + 'webhooks/123/' + 'temporary-test-value',
    'ghp_' + 'a'.repeat(40), '-----BEGIN ' + 'PRIVATE KEY-----'];
  for (const value of samples) { const result = credentialIssue('example.txt', value); assert.ok(result); assert.ok(!result.includes(value)); }
  assert.equal(credentialIssue('example.txt', 'sha256: ' + 'a'.repeat(64)), null);
});
test('release version consistency fails instead of shipping mismatched client, Worker or manifest', () => {
  const read = path => readFileSync(new URL('../../' + path, import.meta.url), 'utf8');
  const version = JSON.parse(read('control/package.json')).version;
  assert.equal(checkVersions(read), version);
  for (const changed of ['control/package-lock.json', 'control/auto.lua', 'control/client.lua', 'control/worker.js', 'control/register.mjs', 'dist/control-beta.json']) {
    assert.throws(() => checkVersions(path => path === changed ? read(path).replaceAll(version, '0.0.0-old') : read(path)), /version mismatch/);
  }
});
test('published clients carry the same source fingerprint as the manifest', () => {
  const read = path => readFileSync(new URL('../../' + path, import.meta.url), 'utf8');
  const manifest = JSON.parse(read('dist/control-beta.json'));
  assert.match(manifest.build, /^[a-f0-9]{12}$/);
  for (const file of ['dist/control-beta.lua', 'dist/launcher-beta.lua']) assert.ok(read(file).includes(`local BUILD_ID = "${manifest.build}"`));
});

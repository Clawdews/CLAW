import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { githubSnapshot, uploadSource, validateSource, publishOnce, digest, target, jsonRequest } from '../tools/luarmor-publisher.mjs';
const source = readFileSync(new URL('../notes-dropper.lua', import.meta.url), 'utf8');
const revision = 'a'.repeat(40);
const credential = 'test'.repeat(16);
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
function api(overrides = {}) {
  const requests = [];
  const fetcher = async (url, options) => {
    requests.push({ url, options }); assert.equal(new URL(url).hostname, 'api.github.com');
    if (url.endsWith('/CLAW')) return json({ private: true, full_name: target.repo, ...overrides.repo });
    if (url.endsWith('/commits/control-beta')) return json({ sha: revision });
    if (url.includes('/check-runs')) return json({ check_runs: overrides.checks || [{ id: 1, name: 'Notes release checks', app: { slug: 'github-actions' }, head_sha: revision, status: 'completed', conclusion: 'success' }] });
    assert.equal(new URL(url).searchParams.get('ref'), revision);
    return json({ type: 'file', path: target.source, encoding: 'base64', size: Buffer.byteLength(source), content: Buffer.from(source).toString('base64'), ...overrides.blob });
  };
  return { requests, fetcher };
}
test('fetches only the private approved repository and exact checked revision', async () => {
  const f = api(); const s = await githubSnapshot(credential, f.fetcher);
  assert.equal(s.revision, revision); assert.equal(s.hash, digest(source)); assert.equal(s.source, source);
  assert.equal(f.requests.length, 4); assert.ok(f.requests.every(r => r.options.redirect === 'error'));
});
test('public repository and missing/failed/spoofed checks never supply an upload', async () => {
  await assert.rejects(githubSnapshot(credential, api({ repo: { private: false } }).fetcher));
  for (const checks of [[], [{ name: 'Notes release checks', status: 'completed', conclusion: 'failure' }],
    [{ name: 'Notes release checks', status: 'completed', conclusion: 'success', head_sha: revision, app: { slug: 'untrusted' } }]]) {
    const f = api({ checks }); assert.equal((await githubSnapshot(credential, f.fetcher)).waiting, true); assert.equal(f.requests.length, 3);
  }
});
test('a later failed rerun supersedes an older success', async () => {
  const base = { name: 'Notes release checks', status: 'completed', head_sha: revision, app: { slug: 'github-actions' } };
  const f = api({ checks: [{ ...base, id: 1, conclusion: 'success' }, { ...base, id: 2, conclusion: 'failure' }] });
  assert.equal((await githubSnapshot(credential, f.fetcher)).waiting, true);
});
test('wrong file, incomplete content and credentials are rejected', async () => {
  for (const blob of [{ path: 'another.lua' }, { size: 42 }, { type: 'symlink' }]) await assert.rejects(githubSnapshot(credential, api({ blob }).fetcher));
  assert.throws(() => validateSource('short'));
  assert.throws(() => validateSource(source + '\nscript_key = "' + 'x'.repeat(32) + '"'));
});
test('uploads once to the existing notes script, preserving documented privacy flags', async () => {
  let calls = 0;
  await uploadSource(source, credential, async (url, options) => {
    calls++; assert.equal(url, `https://api.luarmor.net/v3/projects/${target.project}/scripts/${target.script}`);
    assert.equal(options.method, 'PUT'); assert.equal(options.headers.Authorization, credential);
    assert.deepEqual(JSON.parse(options.body), { script: source, silent: false, ffa: false, heartbeat: true, lightning: false });
    return json({ success: true });
  });
  assert.equal(calls, 1);
});
test('HTML, non-success JSON, server errors and unknown network results are not retried', async () => {
  for (const response of [new Response('<html/>'), json({ success: false }), json({}, 500)]) {
    let calls = 0; await assert.rejects(uploadSource(source, credential, async () => { calls++; return response; })); assert.equal(calls, 1);
  }
  await assert.rejects(jsonRequest('https://api.luarmor.net/status', {}, async () => { throw new Error(credential); }), e => !e.message.includes(credential));
});
test('rejected API requests retain a useful reason without leaking credentials or URLs', async () => {
  await assert.rejects(uploadSource(source, credential, async () => json({ success: false,
    message: 'Missing x-turnstile-token header. Secret ' + credential + ' https://example.com/' + credential }, 400)), error => {
    assert.match(error.message, /HTTP 400.*Missing x-turnstile-token header/);
    assert.ok(!error.message.includes(credential) && !error.message.includes('https://'));
    return true;
  });
});
function runFixture() {
  const f = { state: {}, uploads: 0, verifies: 0, saves: [], messages: [] };
  f.deps = { readState: () => f.state, saveState: s => { f.state = s; f.saves.push(s); }, status: m => f.messages.push(m),
    snapshot: async () => ({ source, hash: digest(source), revision }), verify: async () => { f.verifies++; },
    upload: async () => { assert.ok(f.state.pending); f.uploads++; } };
  return f;
}
test('durable pending gate precedes the upload, then acceptance is saved', async () => {
  const f = runFixture(); await publishOnce(f.deps); assert.equal(f.uploads, 1); assert.equal(f.verifies, 1);
  assert.ok(f.saves[0].pending); assert.equal(f.state.pending, undefined); assert.equal(f.state.hash, digest(source));
});
test('unchanged source is not uploaded again', async () => {
  const f = runFixture(); await publishOnce(f.deps); await publishOnce(f.deps); assert.equal(f.uploads, 1);
});
test('failed local test makes no external write', async () => {
  const f = runFixture(); f.deps.verify = async () => { throw new Error('test failed'); };
  await assert.rejects(publishOnce(f.deps)); assert.equal(f.uploads, 0); assert.equal(f.saves.length, 0);
});
test('uncertain upload survives restart and blocks a duplicate attempt', async () => {
  const f = runFixture(); f.deps.upload = async () => { f.uploads++; throw new Error('timeout'); };
  await assert.rejects(publishOnce(f.deps)); assert.ok(f.state.pending);
  await publishOnce(f.deps); assert.equal(f.uploads, 1);
});
test('failed state persistence prevents upload', async () => {
  const f = runFixture(); f.deps.saveState = () => { throw new Error('disk full'); };
  await assert.rejects(publishOnce(f.deps)); assert.equal(f.uploads, 0);
});

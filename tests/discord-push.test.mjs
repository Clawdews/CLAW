import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, unlinkSync, rmdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { shortTitle, pushPayload, webhookUrl, sendPush, branches } from '../tools/discord-push.mjs';

const sha = 'a'.repeat(40);
const event = (overrides = {}) => ({ repository: { full_name: 'Clawdews/CLAW' }, ref: 'refs/heads/main',
  after: sha, deleted: false, head_commit: { id: sha, message: 'Tidy setup instructions\n\nLong body' }, ...overrides });
const webhook = 'https://discord.com/api/' + 'webhooks/' + '1'.repeat(19) + '/' + 'example'.repeat(10);

function runCLI(args = [], data = event(), extraEnv = {}) {
  const folder = mkdtempSync(join(tmpdir(), 'claw-notifier-test-'));
  const eventPath = join(folder, 'push.json');
  try {
    writeFileSync(eventPath, JSON.stringify(data));
    return spawnSync(process.execPath, [fileURLToPath(new URL('../tools/discord-push.mjs', import.meta.url)), ...args], {
      encoding: 'utf8', env: { ...process.env, GITHUB_EVENT_NAME: 'push', GITHUB_REPOSITORY: 'Clawdews/CLAW',
        GITHUB_EVENT_PATH: eventPath, DISCORD_UPDATES_WEBHOOK: '', ...extraEnv },
    });
  } finally {
    if (existsSync(eventPath)) unlinkSync(eventPath);
    rmdirSync(folder);
  }
}

test('dry run needs no secret and previews only one public line', () => {
  const result = runCLI(['--dry-run']);
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
  assert.equal(result.stdout.trim(), pushPayload(event(), 'Clawdews/CLAW').content);
});
test('unconnected workflow warns instead of claiming delivery', () => {
  const result = runCLI();
  assert.equal(result.status, 0);
  assert.match(result.stdout, /::warning::Discord updates are not connected/);
  assert.ok(!result.stdout.includes('update sent'));
});
test('CLI rejects other events and arguments without exposing configuration', () => {
  for (const [args, extraEnv] of [[[], { GITHUB_EVENT_NAME: 'pull_request' }], [['--invalid'], {}]]) {
    const result = runCLI(args, event(), { DISCORD_UPDATES_WEBHOOK: webhook, ...extraEnv });
    assert.equal(result.status, 1);
    assert.ok(!result.stderr.includes(webhook));
  }
});

test('one short line, one commit link, no pings or embeds', () => {
  const payload = pushPayload(event(), 'Clawdews/CLAW');
  assert.equal(payload.content, `CLAW: Tidy setup instructions · [view](https://github.com/Clawdews/CLAW/commit/${sha})`);
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.equal(payload.flags, 4);
  assert.ok(!payload.content.includes('\n'));
});
test('titles cannot inject mentions, Markdown, links or extra lines', () => {
  assert.equal(shortTitle('@everyone [click](https://bad.invalid/a) **test**\nsecret'), 'everyone click test');
  assert.equal(shortTitle('a\u202Eb\u200Bc\u0000d'), 'abcd');
  assert.equal(shortTitle(''), 'Updated');
  assert.equal(Array.from(shortTitle('😀'.repeat(70))).length, 56);
  assert.equal(shortTitle('x'.repeat(70)), 'x'.repeat(55) + '…');
});
test('deletions, tags and compatibility refs are silent', () => {
  for (const overrides of [{ deleted: true }, { ref: 'refs/tags/v1' }, { ref: 'refs/heads/legacy' }])
    assert.equal(pushPayload(event(overrides), 'Clawdews/CLAW'), null);
  assert.match(pushPayload(event({ ref: 'refs/heads/control-beta' }), 'Clawdews/CLAW').content, /^CLAW control-beta:/);
});
test('repository and commit identity are checked', () => {
  assert.throws(() => pushPayload(event(), 'another/repo'), /mismatch/);
  assert.throws(() => pushPayload(event(), 'bad\n/path'), /mismatch/);
  for (const after of ['bad', '0'.repeat(40)]) assert.throws(() => pushPayload(event({ after }), 'Clawdews/CLAW'), /commit/);
  assert.match(pushPayload(event({ head_commit: null }), 'Clawdews/CLAW').content, /^CLAW: Updated/);
});
test('only a direct Discord webhook URL is accepted, without leaking it on error', () => {
  assert.equal(webhookUrl(webhook).search, '?wait=true');
  for (const input of ['invalid', webhook.replace('https:', 'http:'), webhook.replace('discord.com', 'discord.com.evil.test'),
    webhook.replace('discord.com', 'user:password@discord.com'), webhook + '?thread_id=1', webhook + '#test', webhook.replace('/api/', '/other/')]) {
    assert.throws(() => webhookUrl(input), error => error.message === 'Invalid Discord webhook configuration.');
  }
});
test('posting waits for a message ID and refuses redirects', async () => {
  let calls = 0;
  const payload = pushPayload(event(), 'Clawdews/CLAW');
  const id = await sendPush(payload, webhook, async (url, options) => {
    calls++;
    assert.equal(url.searchParams.get('wait'), 'true');
    assert.equal(options.redirect, 'error');
    assert.equal(options.method, 'POST');
    assert.deepEqual(JSON.parse(options.body), payload);
    return { ok: true, json: async () => ({ id: '2'.repeat(19) }) };
  });
  assert.equal(calls, 1); assert.equal(id, '2'.repeat(19));
});
test('failures and ambiguous delivery never leak credentials or duplicate a post', async () => {
  const responses = [() => { throw new Error(webhook); }, () => ({ ok: false, status: 429 }),
    () => ({ ok: true, json: async () => { throw new Error(webhook); } }), () => ({ ok: true, json: async () => ({}) })];
  for (const response of responses) {
    let calls = 0;
    await assert.rejects(sendPush({}, webhook, async () => { calls++; return response(); }), error => !error.message.includes(webhook));
    assert.equal(calls, 1);
  }
});
test('workflow pins checkout, keeps credentials out of commands and uses the same refs', () => {
  const source = readFileSync(new URL('../.github/workflows/discord-updates.yml', import.meta.url), 'utf8');
  assert.match(source, /actions\/checkout@[a-f0-9]{40}/);
  assert.match(source, /persist-credentials: false/);
  assert.ok(!source.includes('head_commit.message'));
  const names = source.match(/branches: \[([^\]]+)\]/)[1].split(',').map(value => value.trim());
  assert.deepEqual(new Set(names), branches);
});

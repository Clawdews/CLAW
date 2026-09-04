import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const moduleUrl = new URL('../register.mjs', import.meta.url).href;
function run(mock, overrides = {}) {
  return spawnSync(process.execPath, ['--input-type=module', '-e', `${mock}; await import(${JSON.stringify(moduleUrl)});`], {
    encoding: 'utf8', env: { ...process.env, DISCORD_BOT_TOKEN: 'private-test-token',
      DISCORD_APPLICATION_ID: '123456789012345678', DISCORD_GUILD_ID: '234567890123456789', ...overrides },
  });
}
test('registration upserts only CLAW and supplies Discord client identification', () => {
  const result = run(`globalThis.fetch = async (url, options) => {
    if (url !== 'https://discord.com/api/v10/applications/123456789012345678/guilds/234567890123456789/commands') throw Error('Unexpected route');
    if (options.method !== 'POST') throw Error('Not an upsert');
    if (!options.headers['User-Agent'].startsWith('DiscordBot (')) throw Error('Missing client identification');
    if (options.headers.Authorization !== 'Bot private-test-token') throw Error('Missing credential');
    if (!options.signal || JSON.parse(options.body).name !== 'claw') throw Error('Invalid request');
    return new Response('{}', { status: 200 });
  }`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Registered \/claw/);
  assert.doesNotMatch(result.stdout + result.stderr, /private-test-token/);
});
test('missing server access gives an installation instruction without echoing response content', () => {
  const result = run(`globalThis.fetch = async () => new Response(JSON.stringify({code:50001,message:'private-test-token'}),{status:403})`);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Install CLAW in the configured server/);
  assert.doesNotMatch(result.stdout + result.stderr, /private-test-token/);
});
test('non-JSON API errors do not disclose response content', () => {
  const result = run(`globalThis.fetch = async () => new Response('private-test-token',{status:403})`);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /HTTP 403/);
  assert.doesNotMatch(result.stdout + result.stderr, /private-test-token/);
});
test('missing configuration stops before any request', () => {
  const result = run(`globalThis.fetch = () => { throw Error('Unexpected network request'); }`, {DISCORD_BOT_TOKEN:''});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Set DISCORD_BOT_TOKEN/);
  assert.doesNotMatch(result.stderr, /Unexpected network request/);
});

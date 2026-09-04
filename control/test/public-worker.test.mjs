import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';

test('public users get separate groups and slow username replies stay private', async t => {
  const alice = '123456789012345678', bob = '234567890123456789', guild = '345678901234567890';
  const app = '456789012345678901';
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const delivered = new Map(); let lookups = 0;
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'public-test',
    modules: ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js', 'catalog.js', 'status.js', 'accounts.js', 'panel.js', 'panel-controller.js', 'batch.js']
      .map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    ratelimits: { ENTRY_LIMITER: { namespace_id: '153105', simple: { limit: 60, period: 60 } } },
    bindings: { SHARED_MODE: 'true', ACCESS_MODE: 'public', PUBLIC_ENDPOINT: 'https://claw.test', DISCORD_PUBLIC_KEY: publicKey },
    outboundService: async request => {
      assert.equal(request.headers.get('Authorization'), null); assert.equal(request.headers.get('Cookie'), null);
      if (request.url === 'https://users.roblox.com/v1/usernames/users') {
        lookups++; const body = await request.json();
        assert.deepEqual(Object.keys(body).sort(), ['excludeBannedUsers', 'usernames']);
        await new Promise(resolve => setTimeout(resolve, 1600));
        return Response.json({ data: [{ id: 11, name: 'Nova_One', requestedUsername: body.usernames[0] }] });
      }
      const url = new URL(request.url);
      assert.equal(url.origin, 'https://discord.com'); assert.equal(request.method, 'PATCH');
      assert.equal(url.pathname.split('/')[4], app); assert.ok(url.pathname.endsWith('/messages/@original'));
      const data = await request.json(); assert.equal(data.flags, undefined); assert.deepEqual(data.allowed_mentions, { parse: [] });
      delivered.set(url.pathname.split('/')[5], data);
      return new Response(null, { status: 204 });
    } }] }));
  t.after(() => mf.dispose());
  let sequence = 500000000000000000n;
  async function command(owner, name, values = {}, personal = false) {
    const token = 'test-interaction-' + String(sequence);
    const payload = { id: String(sequence++), type: 2, application_id: app, token,
      ...(personal ? { user: { id: owner }, authorizing_integration_owners: { 1: owner } }
        : { guild_id: guild, member: { user: { id: owner } }, authorizing_integration_owners: { 0: guild } }),
      data: { name: 'claw', options: [{ name, options: Object.entries(values).map(([name, value]) => ({ name, value })) }] } };
    const raw = JSON.stringify(payload), ts = String(Math.floor(Date.now() / 1000));
    const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + raw))).toString('hex');
    const response = await mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw,
      headers: { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sig } });
    const data = await response.json(); assert.equal(data.data.flags, 64);
    if (data.type !== 5) return data.data;
    assert.ok(!delivered.has(token), 'Discord is acknowledged before the slow lookup finishes');
    for (let i = 0; i < 500; i++) {
      if (delivered.has(token)) return delivered.get(token);
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.fail('Deferred response did not arrive');
  }
  await t.test('a new user can open a private panel without host approval', async () => {
    const panel = await command(alice, 'panel');
    assert.ok(panel.embeds.length); assert.ok(!JSON.stringify(panel).includes('restricted'));
  });
  const a = await command(alice, 'enroll', { account: 'nova_one' });
  const b = await command(bob, 'enroll', { account: 'nova_one' }, true);
  const keyA = a.content.match(/Key="([a-f0-9]{64})"/)?.[1], keyB = b.content.match(/Key="([a-f0-9]{64})"/)?.[1];
  assert.ok(keyA); assert.ok(keyB); assert.notEqual(keyA, keyB); assert.equal(lookups, 2);
  await t.test('credentials remain private to the invoking user for either install type', async () => {
    const session = (owner, key) => mf.dispatchFetch('https://claw.test/session?owner=' + owner,
      { method: 'POST', body: JSON.stringify({ accountId: '11', key }) });
    assert.equal((await session(alice, keyA)).status, 200);
    assert.equal((await session(bob, keyA)).status, 401);
    assert.equal((await session(alice, keyB)).status, 401);
    await command(alice, 'main', { account: '11' });
    await command(alice, 'follow', { enabled: true });
    assert.match((await command(bob, 'status', {}, true)).content, /Follow: OFF \| Main: not selected/);
  });
});

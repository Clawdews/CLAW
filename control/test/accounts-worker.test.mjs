import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';

test('signed username commands retain enrollment, replay and per-user isolation in Workers', async t => {
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const alice = '123456789012345678', bob = '234567890123456789', guild = '345678901234567890';
  let lookups = 0, failLookup = false;
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'username-test',
    modules: ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js', 'catalog.js', 'status.js', 'accounts.js']
      .map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    bindings: { SHARED_MODE: 'true', BETA_USERS: alice + ',' + bob, PUBLIC_ENDPOINT: 'https://claw.test', DISCORD_PUBLIC_KEY: publicKey },
    outboundService: async request => {
      lookups++;
      assert.equal(request.url, 'https://users.roblox.com/v1/usernames/users');
      assert.equal(request.headers.get('Authorization'), null); assert.equal(request.headers.get('Cookie'), null);
      const body = await request.json();
      assert.deepEqual(Object.keys(body).sort(), ['excludeBannedUsers', 'usernames']);
      if (failLookup) return new Response('private upstream error', { status: 503 });
      return Response.json({ data: body.usernames[0].toLowerCase() === 'nova_one'
        ? [{ id: 11, name: 'Nova_One', requestedUsername: body.usernames[0] }] : [] });
    },
  }] }));
  t.after(() => mf.dispose());
  let sequence = 500000000000000000n;
  async function command(owner, name, values = {}) {
    const payload = { id: String(sequence++), type: 2, guild_id: guild, member: { user: { id: owner } },
      authorizing_integration_owners: { 0: guild },
      data: { name: 'claw', options: [{ name, options: Object.entries(values).map(([name, value]) => ({ name, value })) }] } };
    const raw = JSON.stringify(payload), ts = String(Math.floor(Date.now() / 1000));
    const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + raw))).toString('hex');
    const send = () => mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw,
      headers: { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sig } });
    const result = await (await send()).json();
    assert.equal(result.data.flags, 64); assert.deepEqual(result.data.allowed_mentions.parse, []);
    assert.ok(result.data.content.length <= 2000);
    return { text: result.data.content, send };
  }
  await t.test('unauthorized and account-less commands never call Roblox', async () => {
    assert.equal((await mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: '{}' })).status, 401);
    assert.match((await command('999999999999999999', 'enroll', { account: 'nova_one' })).text, /restricted/);
    await command(alice, 'setup'); await command(alice, 'status');
    assert.equal(lookups, 0);
  });
  const enrolled = await command(alice, 'enroll', { account: '@nova_one' });
  assert.match(enrolled.text, /^Account: @Nova_One \(11\)/);
  const key = enrolled.text.match(/Key="([a-f0-9]{64})"/)?.[1]; assert.ok(key);
  const session = () => mf.dispatchFetch('https://claw.test/session?owner=' + alice,
    { method: 'POST', body: JSON.stringify({ accountId: '11', key }) });
  await t.test('name resolves to the same permanent account without replacing its pairing', async () => {
    assert.equal((await session()).status, 200);
    const previous = lookups;
    assert.match((await command(alice, 'enroll', { account: '11' })).text, /Already paired/);
    assert.equal(lookups, previous);
    assert.match((await command(alice, 'enroll', { account: 'NOVA_ONE' })).text, /Already paired/);
    assert.equal((await session()).status, 200);
  });
  await t.test('main, nickname and character listing accept usernames; replay stays blocked', async () => {
    const selected = await command(alice, 'main', { account: 'nova_one' });
    assert.match(selected.text, /Main set to 11/);
    assert.match((await (await selected.send()).json()).data.content, /already processed/);
    assert.match((await command(alice, 'nickname', { account: 'nova_one', label: 'Main account' })).text, /Saved/);
    assert.match((await command(alice, 'slots', { account: 'nova_one' })).text, /Characters for 11/);
  });
  await t.test('another user cannot select or revoke the first user’s account by username', async () => {
    assert.match((await command(bob, 'main', { account: 'nova_one' })).text, /Enroll/);
    assert.match((await command(bob, 'revoke', { account: 'nova_one' })).text, /not enrolled/);
    assert.equal((await session()).status, 200);
  });
  await t.test('lookup failure leaves main, following and pairing unchanged; numeric commands still work', async () => {
    await command(alice, 'follow', { enabled: true });
    const before = (await command(alice, 'status')).text;
    failLookup = true;
    for (const name of ['main', 'rotate', 'revoke', 'retry']) {
      const result = await command(alice, name, { account: 'nova_one' });
      assert.match(result.text, /unavailable.*No changes made/); assert.doesNotMatch(result.text, /private upstream/);
    }
    assert.equal((await command(alice, 'status')).text, before);
    assert.equal((await session()).status, 200);
    assert.match((await command(alice, 'retry', { account: '11' })).text, /One retry/);
    failLookup = false;
    assert.match((await command(alice, 'revoke', { account: 'nova_one' })).text, /Revoked 11/);
    assert.equal((await session()).status, 401);
  });
});

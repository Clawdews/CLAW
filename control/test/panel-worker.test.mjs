import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';

test('signed Discord panels and batch approval work through real Worker endpoints', async t => {
  const owner = '123456789012345678', other = '234567890123456789', guild = '345678901234567890';
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  let lookups = 0;
  const options = { workers: [{ name: 'panel-test',
    modules: ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js', 'catalog.js', 'status.js', 'accounts.js', 'panel.js', 'panel-controller.js', 'batch.js']
      .map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    ratelimits: { ENTRY_LIMITER: { namespace_id: '153104', simple: { limit: 60, period: 60 } } },
    bindings: { SHARED_MODE: 'true', ACCESS_MODE: 'closed', BETA_USERS: owner + ',' + other, PUBLIC_ENDPOINT: 'https://claw.test', DISCORD_PUBLIC_KEY: publicKey },
    outboundService: async request => {
      lookups++; assert.equal(request.url, 'https://users.roblox.com/v1/usernames/users');
      assert.equal(request.headers.get('Authorization'), null);
      const body = await request.json(); assert.deepEqual(Object.keys(body).sort(), ['excludeBannedUsers', 'usernames']);
      return Response.json({ data: [{ id: 22, name: 'Nova_Alt', requestedUsername: body.usernames[0] }] });
    } }] };
  const mf = new Miniflare(convertV4MiniflareOptions(options)); t.after(() => mf.dispose());
  let sequence = 500000000000000000n;
  async function send(partial, who = owner) {
    const payload = { id: String(sequence++), guild_id: guild, member: { user: { id: who } },
      authorizing_integration_owners: { 0: guild }, ...partial };
    const raw = JSON.stringify(payload), ts = String(Math.floor(Date.now() / 1000));
    const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + raw))).toString('hex');
    const request = () => mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw, headers: { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sig } });
    const response = await request(); assert.equal(response.status, 200); return { ...(await response.json()), resend: request };
  }
  const command = (name, values = {}) => send({ type: 2, data: { name: 'claw', options: [{ name,
    options: Object.entries(values).map(([name, value]) => ({ name, value })) }] } });
  const controls = p => p.data.components.flatMap(row => row.components);
  const click = (p, action, value, who = owner) => {
    const c = controls(p).find(c => c.custom_id.endsWith(':' + action)); assert.ok(c, action);
    return send({ type: 3, message: { ...p.data, flags: 64 }, data: { custom_id: c.custom_id, component_type: c.type,
      ...(value ? { values: [value] } : {}) } }, who);
  };
  const batch = input => mf.dispatchFetch('https://claw.test/batch?owner=' + owner, { method: 'POST', body: JSON.stringify(input) });
  const session = (accountId, key) => mf.dispatchFetch('https://claw.test/session?owner=' + owner, { method: 'POST', body: JSON.stringify({ accountId, key }) });
  const main = await command('enroll', { account: '11' }); const mainKey = main.data.content.match(/Key="([a-f0-9]{64})"/)[1];
  await command('main', { account: '11' }); await command('follow', { enabled: true });
  let panel = await command('panel'); assert.equal(panel.data.flags, 64); assert.ok(panel.data.embeds.length);
  await t.test('another user cannot operate a copied panel or learn its accounts', async () => {
    const denied = await click(panel, 'setup', null, other); assert.match(denied.data.content, /expired/);
    assert.ok(!JSON.stringify(denied.data).includes(mainKey));
  });
  panel = await click(panel, 'setup'); panel = await click(panel, 'batch-start');
  assert.equal(panel.type, 7); const code = panel.data.content.match(/Code="([a-f0-9]{64})"/)[1];
  const input = { accountId: '22', username: 'Nova_Alt', code, key: 'b'.repeat(64) };
  await t.test('invalid batch authority never reaches Roblox lookup', async () => {
    assert.equal((await batch({ ...input, code: 'f'.repeat(64) })).status, 401); assert.equal(lookups, 0);
    assert.equal((await session('22', input.key)).status, 401);
  });
  let response = await batch(input); assert.equal(response.status, 200); const pending = await response.json(); assert.equal(pending.state, 'pending');
  assert.equal(lookups, 1);
  assert.equal((await (await batch(input)).json()).check, pending.check); assert.equal(lookups, 1);
  panel = await click(panel, 'refresh'); const request = controls(panel).find(c => c.type === 3).options[0].value;
  panel = await click(panel, 'request', request); assert.ok(panel.data.embeds[0].description.includes(pending.check));
  assert.equal((await session('22', input.key)).status, 401);
  panel = await click(panel, 'confirm'); assert.equal(panel.type, 7);
  await t.test('approval saves only the requested key and leaves main, follow and old key intact', async () => {
    assert.equal((await session('22', input.key)).status, 200); assert.equal((await session('11', mainKey)).status, 200);
    assert.equal((await (await batch(input)).json()).state, 'approved');
    assert.equal((await batch({ ...input, key: 'c'.repeat(64) })).status, 409);
    assert.match((await command('status')).data.content, /Follow: ON \| Main: 11/);
    const replay = await (await panel.resend()).json(); assert.match(replay.data.content, /expired/);
  });
  await t.test('newly paired client receives no inferred slot approvals', async () => {
    const { ticket } = await (await session('22', input.key)).json();
    const upgrade = await mf.dispatchFetch('https://claw.test/socket?owner=' + owner + '&ticket=' + ticket, { headers: { Upgrade: 'websocket' } });
    assert.equal(upgrade.status, 101); const ws = upgrade.webSocket; ws.accept();
    const message = new Promise(resolve => ws.addEventListener('message', e => resolve(JSON.parse(e.data)), { once: true }));
    ws.send(JSON.stringify({ type: 'hello' })); const profile = await message;
    assert.equal(profile.mainId, '11'); assert.deepEqual(profile.approvedSlots, {}); assert.equal(profile.allowMenuReturn, null); ws.close();
  });
  await t.test('owner-signed component messages may contain full embeds without overflowing the body limit', async () => {
    const c = controls(panel).find(c => c.custom_id.endsWith(':refresh'));
    const result = await send({ type: 3, message: { flags: 64, content: 'x'.repeat(10000) }, data: { custom_id: c.custom_id, component_type: 2 } });
    assert.equal(result.type, 7);
  });
  await t.test('reload preserves pairings and shuts batch routes when the rate limiter is absent', async () => {
    const next = { workers: [{ ...options.workers[0], ratelimits: {}, bindings: { ...options.workers[0].bindings, TEST_REVISION: 'reload' } }] };
    await mf.setOptions(convertV4MiniflareOptions(next));
    assert.equal((await session('11', mainKey)).status, 200); assert.equal((await session('22', input.key)).status, 200);
    assert.equal((await batch(input)).status, 429);
  });
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';
import { hash } from '../protocol.js';

test('Cloudflare runtime: private enrollment, exact target delivery, pause, replay and revocation', async t => {
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const owner = '123456789012345678', guild = '234567890123456789';
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'claw-test', modules: [
    { type: 'ESModule', path: fileURLToPath(new URL('../worker.js', import.meta.url)) },
    { type: 'ESModule', path: fileURLToPath(new URL('../protocol.js', import.meta.url)) },
    { type: 'ESModule', path: fileURLToPath(new URL('../bootstrap.js', import.meta.url)) } ],
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    bindings: { DISCORD_PUBLIC_KEY: publicKey, DISCORD_OWNER_ID: owner, DISCORD_GUILD_ID: guild } }] }));
  t.after(() => mf.dispose());
  let counter = 300000000000000000n;
  const sockets = [];
  t.after(() => { for (const socket of sockets) { try { socket.close(); } catch {} } });
  async function interaction(command, values = {}, override = {}) {
    const payload = { id: String(counter++), type: 2, guild_id: guild, member: { user: { id: owner } },
      data: { name: 'claw', options: [{ name: command, options: Object.entries(values).map(([name, value]) => ({ name, value })) }] }, ...override };
    const raw = JSON.stringify(payload), ts = String(Math.floor(Date.now() / 1000));
    const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + raw))).toString('hex');
    const request = () => mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw,
      headers: { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sig } });
    const response = await request();
    assert.equal(response.status, 200);
    return { result: await response.json(), request };
  }
  async function pair(account) {
    const { result } = await interaction('enroll', { account });
    const key = result.data.content.match(/\|\|([a-f0-9]{64})\|\|/)?.[1];
    assert.ok(key); assert.equal(result.data.flags, 64);
    return key;
  }
  async function session(accountId, key) {
    return mf.dispatchFetch('https://claw.test/session', { method: 'POST', body: JSON.stringify({ accountId, key }) });
  }
  async function connect(account, key) {
    const response = await session(account, key); assert.equal(response.status, 200);
    const { ticket } = await response.json();
    const upgrade = await mf.dispatchFetch('https://claw.test/socket?ticket=' + ticket, { headers: { Upgrade: 'websocket' } });
    assert.equal(upgrade.status, 101);
    const socket = upgrade.webSocket; socket.accept(); sockets.push(socket);
    const messages = [];
    socket.addEventListener('message', event => messages.push(JSON.parse(event.data)));
    socket.send(JSON.stringify({ type: 'hello' }));
    return { socket, messages, ticket };
  }
  async function waitFor(fn) {
    for (let i = 0; i < 60; i++) { if (fn()) return; await new Promise(r => setTimeout(r, 25)); }
    assert.fail('Expected socket message not received');
  }
  await t.test('health works and unsigned commands fail', async () => {
    assert.equal((await mf.dispatchFetch('https://claw.test/health')).status, 200);
    assert.equal((await mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: '{}' })).status, 401);
  });
  await t.test('validly signed requests still require owner and guild', async () => {
    const { result } = await interaction('enroll', { account: '11' }, { member: { user: { id: '999999999999999999' } } });
    assert.match(result.data.content, /restricted/);
    const other = await interaction('enroll', { account: '11' }, { guild_id: '999999999999999999' });
    assert.match(other.result.data.content, /restricted/);
  });
  const mainKey = await pair('11'); let altKey = await pair('22');
  await t.test('key rotation invalidates the previous key', async () => {
    const old = altKey; altKey = await pair('22');
    assert.equal((await session('22', old)).status, 401);
  });
  await t.test('credentials cannot be reused for another account', async () => {
    assert.equal((await session('22', mainKey)).status, 401);
    assert.equal((await session('11', '0'.repeat(64))).status, 401);
  });
  const main = await connect('11', mainKey), alt = await connect('22', altKey);
  await waitFor(() => alt.messages.some(m => m.type === 'profile'));
  await t.test('socket tickets are single-use', async () => {
    const response = await mf.dispatchFetch('https://claw.test/socket?ticket=' + alt.ticket, { headers: { Upgrade: 'websocket' } });
    assert.equal(response.status, 401);
  });
  await interaction('main', { account: '11' });
  await interaction('follow', { enabled: true });
  await new Promise(r => setTimeout(r, 2100)); // Respect the production per-client message throttle.
  main.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 123, jobId: 'main-job', slot: 'main-slot', state: 'MAIN' } }));
  await waitFor(() => alt.messages.some(m => m.type === 'target' && m.enabled));
  await t.test('only the selected main supplies the exact destination', async () => {
    const target = alt.messages.find(m => m.type === 'target' && m.enabled);
    assert.equal(target.ticket.jobId, 'main-job'); assert.equal(target.ticket.controllerId, 11);
    alt.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 123, jobId: 'imposter-job', state: 'ONLINE' } }));
    await new Promise(r => setTimeout(r, 100));
    assert.ok(!main.messages.some(m => m.ticket?.jobId === 'imposter-job'));
  });
  await t.test('main disconnect withdraws its destination', async () => {
    main.socket.close();
    await waitFor(() => alt.messages.at(-1)?.reason === 'WAITING_MAIN');
  });
  await t.test('pause propagates and signed command replay cannot toggle it again', async () => {
    const paused = await interaction('follow', { enabled: false });
    await waitFor(() => alt.messages.at(-1)?.reason === 'PAUSED');
    const duplicate = await paused.request();
    assert.match((await duplicate.json()).data.content, /already processed/);
  });
  await t.test('retry is explicit and included in the account profile', async () => {
    await interaction('retry', { account: '22' });
    await waitFor(() => alt.messages.some(m => m.type === 'profile' && m.retry));
  });
  await t.test('status never exposes pairing credentials', async () => {
    const { result } = await interaction('status');
    assert.ok(!result.data.content.includes(mainKey) && !result.data.content.includes(altKey));
  });
  await t.test('revoke invalidates the account credential', async () => {
    await interaction('revoke', { account: '22' });
    assert.equal((await session('22', altKey)).status, 401);
  });
});

test('deployment pairing works through real session/socket auth, not an admin HTTP route', async t => {
  const mainKey = '1'.repeat(64), altKey = '2'.repeat(64);
  const seed = { version: 1, ownerId: '123456789012345678', guildId: '234567890123456789',
    mainId: '11', follow: true, members: [
      { accountId: '11', keyHash: await hash(mainKey) }, { accountId: '22', keyHash: await hash(altKey) }] };
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'seed-test',
    modules: ['worker.js', 'protocol.js', 'bootstrap.js'].map(name => ({ type: 'ESModule',
      path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    bindings: { DISCORD_OWNER_ID: seed.ownerId, DISCORD_GUILD_ID: seed.guildId, INITIAL_PAIRING: JSON.stringify(seed) } }] }));
  t.after(() => mf.dispose());
  assert.equal((await mf.dispatchFetch('https://claw.test/bootstrap', { method: 'POST', body: JSON.stringify(seed) })).status, 404);
  assert.equal((await mf.dispatchFetch('https://claw.test/session', { method: 'POST',
    body: JSON.stringify({ accountId: '22', key: mainKey }) })).status, 401);
  for (const [accountId, key, role] of [['11', mainKey, 'main'], ['22', altKey, 'alt']]) {
    const auth = await mf.dispatchFetch('https://claw.test/session', { method: 'POST', body: JSON.stringify({ accountId, key }) });
    assert.equal(auth.status, 200);
    const { ticket } = await auth.json();
    const upgrade = await mf.dispatchFetch('https://claw.test/socket?ticket=' + ticket, { headers: { Upgrade: 'websocket' } });
    assert.equal(upgrade.status, 101);
    const ws = upgrade.webSocket; ws.accept();
    const messages = [];
    ws.addEventListener('message', event => messages.push(JSON.parse(event.data)));
    ws.send(JSON.stringify({ type: 'hello' }));
    try {
      for (let i = 0; i < 60 && messages.length < 2; i++) await new Promise(r => setTimeout(r, 25));
      const profile = messages.find(m => m.type === 'profile');
      assert.ok(profile); assert.equal(profile.accountId, accountId); assert.equal(profile.role, role);
      assert.equal(profile.mainId, '11'); assert.equal(profile.follow, true); assert.equal(profile.slot, null);
      assert.ok(messages.some(m => m.type === 'target' && m.reason === 'WAITING_MAIN'));
    } finally { ws.close(); }
  }
});

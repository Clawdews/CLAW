import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';
import { interactionOwner, entryAllowed, safeSlot, regionForPlace } from '../tenancy.js';
import { sharedCommand } from '../commands.js';

const alice = '123456789012345678', bob = '234567890123456789', guild = '345678901234567890';
test('signed invoking user, not installation owner or guild, owns the account group', () => {
  const env = { SHARED_MODE: 'true', BETA_USERS: alice + ',' + bob };
  const i = { id: '456789012345678901', member: { user: { id: bob } }, guild_id: guild,
    authorizing_integration_owners: { 0: guild }, data: { options: [{ name: 'owner', value: alice }] } };
  assert.equal(interactionOwner(i, env), bob);
  assert.equal(interactionOwner({ ...i, authorizing_integration_owners: { 1: alice } }, env), null);
  assert.equal(interactionOwner({ ...i, guild_id: undefined, member: undefined, user: { id: alice },
    authorizing_integration_owners: { 1: alice } }, env), alice);
  assert.equal(interactionOwner(i, { SHARED_MODE: 'true' }), null);
});
test('public mode refuses entry without working host limits', async () => {
  assert.equal(await entryAllowed({ SHARED_MODE: 'true', ACCESS_MODE: 'public' }, 'test'), false);
  assert.equal(await entryAllowed({ SHARED_MODE: 'true', ACCESS_MODE: 'public', ENTRY_LIMITER: { limit: async () => ({ success: true }) } }, 'test'), true);
  assert.equal(await entryAllowed({ SHARED_MODE: 'true', ACCESS_MODE: 'public', ENTRY_LIMITER: { limit: async () => { throw Error('unavailable'); } } }, 'test'), false);
});
test('slot map keys and supported regions reject unsafe/unknown values', () => {
  for (const slot of ['__proto__', 'constructor', 'prototype', '', '@everyone', 'A\nB']) assert.equal(safeSlot(slot), false);
  assert.equal(safeSlot('L'), true); assert.equal(regionForPlace(6473861193), 'EastLuminant'); assert.equal(regionForPlace(99), null);
  assert.equal(sharedCommand.default_member_permissions, null);
  assert.deepEqual(sharedCommand.integration_types, [0, 1]);
});

test('two users in the same Discord server have isolated commands, credentials, sockets and character choices', async t => {
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const options = { workers: [{ name: 'shared-test',
    modules: ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js'].map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    bindings: { SHARED_MODE: 'true', BETA_USERS: alice + ',' + bob, PUBLIC_ENDPOINT: 'https://claw.test', DISCORD_PUBLIC_KEY: publicKey,
      // Even if mistakenly left in a shared deployment, legacy seed data cannot enter a user's room.
      INITIAL_PAIRING: 'invalid legacy seed' } }] };
  const mf = new Miniflare(convertV4MiniflareOptions(options));
  t.after(() => mf.dispose());
  let sequence = 500000000000000000n;
  const sockets = [];
  t.after(() => { for (const ws of sockets) try { ws.close(); } catch {} });
  async function command(owner, name, values = {}) {
    const payload = { id: String(sequence++), type: 2, guild_id: guild, member: { user: { id: owner } },
      authorizing_integration_owners: { 0: guild },
      data: { name: 'claw', options: [{ name, options: Object.entries(values).map(([name, value]) => ({ name, value })) }] } };
    const raw = JSON.stringify(payload), ts = String(Math.floor(Date.now() / 1000));
    const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + raw))).toString('hex');
    const response = await mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw,
      headers: { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sig } });
    assert.equal(response.status, 200); const data = await response.json(); assert.equal(data.data.flags, 64); return data.data.content;
  }
  async function enroll(owner, account) {
    const text = await command(owner, 'enroll', { account });
    const key = text.match(/Key="([a-f0-9]{64})"/)?.[1]; assert.ok(key, text);
    assert.ok(text.includes(`OwnerId="${owner}"`)); return key;
  }
  const session = (owner, accountId, key) => mf.dispatchFetch('https://claw.test/session?owner=' + owner,
    { method: 'POST', body: JSON.stringify({ accountId, key }) });
  async function connect(owner, accountId, key) {
    const auth = await session(owner, accountId, key); assert.equal(auth.status, 200);
    const { ticket } = await auth.json();
    const upgrade = await mf.dispatchFetch(`https://claw.test/socket?owner=${owner}&ticket=${ticket}`, { headers: { Upgrade: 'websocket' } });
    assert.equal(upgrade.status, 101);
    const socket = upgrade.webSocket; socket.accept(); sockets.push(socket);
    const messages = []; socket.addEventListener('message', e => messages.push(JSON.parse(e.data)));
    socket.send(JSON.stringify({ type: 'hello' })); return { socket, messages, ticket };
  }
  async function waitFor(fn) { for (let i = 0; i < 100; i++) { if (fn()) return; await new Promise(r => setTimeout(r, 20)); } assert.fail('Socket message timeout'); }
  assert.match(await command(alice, 'setup'), /private/);
  const a11 = await enroll(alice, '11'), a22 = await enroll(alice, '22'), b11 = await enroll(bob, '11');
  await command(alice, 'main', { account: '11' }); await command(alice, 'follow', { enabled: true });
  await t.test('same account ID may be paired separately but keys cannot cross users', async () => {
    assert.equal((await session(bob, '11', a11)).status, 401);
    assert.equal((await session(alice, '11', b11)).status, 401);
    assert.equal((await mf.dispatchFetch('https://claw.test/session', { method: 'POST', body: JSON.stringify({ accountId: '11', key: a11 }) })).status, 401);
  });
  await t.test('enroll never silently rotates an existing key in shared mode', async () => {
    assert.match(await command(alice, 'enroll', { account: '11' }), /Already paired/);
    assert.equal((await session(alice, '11', a11)).status, 200);
  });
  const main = await connect(alice, '11', a11), alt = await connect(alice, '22', a22), other = await connect(bob, '11', b11);
  await waitFor(() => other.messages.length >= 2 && alt.messages.length >= 2);
  await t.test('profiles and main configuration are isolated', async () => {
    assert.equal(alt.messages[0].ownerId, alice); assert.equal(alt.messages[0].mainId, '11');
    assert.equal(other.messages[0].ownerId, bob); assert.equal(other.messages[0].mainId, null);
    assert.equal(other.messages[0].follow, false);
    assert.match(await command(bob, 'main', { account: '22' }), /Enroll/);
    assert.match(await command(bob, 'status'), /Main: not selected/);
  });
  await t.test('socket tickets cannot be moved into another owner namespace', async () => {
    const auth = await session(alice, '22', a22), { ticket } = await auth.json();
    const result = await mf.dispatchFetch(`https://claw.test/socket?owner=${bob}&ticket=${ticket}`, { headers: { Upgrade: 'websocket' } });
    assert.equal(result.status, 401);
  });
  await new Promise(r => setTimeout(r, 2100));
  main.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 6473861193, jobId: 'alice-server', slot: 'M', state: 'MAIN' } }));
  alt.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 6473861193, jobId: 'alt-server', slot: 'L', state: 'ONLINE' } }));
  await waitFor(() => alt.messages.some(m => m.type === 'profile' && m.catalog?.some(s => s.slot === 'L')));
  await t.test('targets only reach sockets belonging to the same user', async () => {
    assert.ok(alt.messages.some(m => m.ticket?.jobId === 'alice-server'));
    assert.ok(!other.messages.some(m => m.ticket?.jobId === 'alice-server'));
  });
  await t.test('observed characters are not automatically approved; owner can approve and prefer', async () => {
    const p = alt.messages.find(m => m.type === 'profile' && m.catalog?.some(s => s.slot === 'L'));
    assert.deepEqual(p.approvedSlots, {}); assert.equal(p.catalog[0].region, 'EastLuminant');
    assert.match(await command(alice, 'allow-slot', { account: '22', slot: 'X', enabled: true }), /Load that character/);
    assert.match(await command(alice, 'allow-slot', { account: '22', slot: 'L', enabled: true }), /approved/);
    assert.match(await command(alice, 'prefer-slot', { account: '22', slot: 'L', region: 'EastLuminant' }), /Preferred/);
    assert.match(await command(alice, 'slots', { account: '22' }), /L: EastLuminant \| approved/);
    assert.match(await command(bob, 'slots', { account: '22' }), /Enroll/);
    await command(alice, 'allow-slot', { account: '22', slot: 'L', enabled: false });
    await waitFor(() => alt.messages.at(-2)?.type === 'profile' && !alt.messages.at(-2).approvedSlots.L);
    assert.deepEqual(alt.messages.at(-2).preferredSlots, {});
  });
  await t.test('revoking another users same-numbered account does not affect this user', async () => {
    await command(bob, 'revoke', { account: '11' });
    assert.equal((await session(bob, '11', b11)).status, 401);
    assert.equal((await session(alice, '11', a11)).status, 200);
  });
  await t.test('status and slots never echo pairing keys', async () => {
    const text = await command(alice, 'status') + await command(alice, 'slots', { account: '22' });
    for (const key of [a11, a22, b11]) assert.ok(!text.includes(key));
  });
  await t.test('worker reload preserves isolation, revocation and character permissions', async () => {
    const reloaded = structuredClone(options);
    reloaded.workers[0].bindings.TEST_REVISION = 'reload';
    await mf.setOptions(convertV4MiniflareOptions(reloaded));
    assert.equal((await session(alice, '11', a11)).status, 200);
    assert.equal((await session(bob, '11', a11)).status, 401);
    assert.equal((await session(bob, '11', b11)).status, 401);
    assert.match(await command(alice, 'status'), /Follow: ON \| Main: 11/);
    assert.match(await command(bob, 'status'), /Follow: OFF \| Main: not selected/);
    assert.match(await command(alice, 'slots', { account: '22' }), /L: EastLuminant \| not approved/);
  });
});

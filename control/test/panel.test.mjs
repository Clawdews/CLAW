import test from 'node:test';
import assert from 'node:assert/strict';
import { renderPanel, confirmation, confirmationFresh, accountStatus, regionName } from '../panel.js';
import { panelCommand } from '../panel-controller.js';
import { batchRequest } from '../batch.js';
import { hash, now, nonce } from '../protocol.js';

const owner = '123456789012345678';
function room() {
  const storage = new Map();
  const r = { config: { ownerId: owner, members: { '11': { username: 'Nova_Main', credential: 'epoch', keyHash: 'a'.repeat(64),
    slots: { L: { slot: 'L', characterName: 'Rook Janus', race: 'Khan', origin: 'Authority Ensign', region: 'EastLuminant', level: 1, confirmed: true, observedAt: now() } },
    approvedSlots: {} } }, mainId: '11', follow: true, revision: 'initial' },
    env: { PUBLIC_ENDPOINT: 'https://claw.test' }, sockets: () => [], live: () => null, broadcasts: 0,
    broadcast() { this.broadcasts++; },
    ctx: { storage: { get: async key => structuredClone(storage.get(key)), put: async (key, value) => {
      if (typeof key === 'object') for (const [k, v] of Object.entries(key)) storage.set(k, structuredClone(v));
      else storage.set(key, structuredClone(value));
    } } }, storage };
  storage.set('config', structuredClone(r.config)); return r;
}
const controls = panel => panel.data.components.flatMap(row => row.components);
function clicked(panel, action, value) {
  const c = controls(panel).find(c => c.custom_id.endsWith(':' + action)); assert.ok(c, action);
  return { type: 3, message: { flags: 64 }, data: { custom_id: c.custom_id, component_type: c.type, ...(value ? { values: [value] } : {}) } };
}
const open = (r, initial = {}) => panelCommand(r, {}, owner, { screen: 'home', account: '11', ...initial });
const click = (r, p, action, value, who = owner) => panelCommand(r, clicked(p, action, value), who);
function limits(data) {
  assert.ok(data.content.length <= 2000); assert.ok(data.embeds.length <= 10); assert.ok(data.components.length <= 5);
  let text = 0;
  for (const e of data.embeds) {
    assert.ok(e.title.length <= 256); assert.ok(e.description.length <= 4096);
    text += e.title.length + e.description.length + (e.footer?.text.length || 0);
    for (const f of e.fields || []) { assert.ok(f.name.length <= 256 && f.value.length <= 1024); text += f.name.length + f.value.length; }
  }
  assert.ok(text <= 6000, 'embed text limit'); const ids = new Set();
  for (const row of data.components) {
    assert.ok(row.components.length <= 5);
    for (const c of row.components) {
      assert.ok(c.custom_id.length <= 100 && !ids.has(c.custom_id)); ids.add(c.custom_id);
      assert.ok(!c.options || c.options.length <= 25);
      for (const o of c.options || []) assert.ok(o.label.length <= 100 && o.value.length <= 100 && (!o.description || o.description.length <= 100));
    }
  }
  assert.deepEqual(data.allowed_mentions, { parse: [] });
}
test('all panel views stay within Discord limits with maximum escaped card metadata and 30 accounts', () => {
  const r = room();
  for (let n = 12; n <= 40; n++) r.config.members[String(n)] = { ...structuredClone(r.config.members['11']), nickname: '*'.repeat(32) };
  const member = r.config.members['11']; member.slots = {};
  for (let n = 0; n < 60; n++) {
    const slot = String.fromCharCode(65 + Math.floor(n / 26)) + String.fromCharCode(65 + n % 26);
    member.slots[slot] = { slot, characterName: '@'.repeat(80), race: '*'.repeat(40), oath: '`'.repeat(60), origin: '|'.repeat(60),
      location: '*'.repeat(100), playtime: '*'.repeat(32), lastPlayed: '@'.repeat(32), confirmed: true, observedAt: now(), level: 20 };
  }
  for (const screen of ['home', 'slots', 'detail', 'setup', 'requests']) for (let page = 0; page < 12; page++) {
    const result = renderPanel(r.config, {}, { token: nonce(), screen, account: '11', page, slot: 'AA' }, now()); limits(result.data);
    assert.ok(!JSON.stringify(result).includes('a'.repeat(64)));
  }
});
test('main and character views use readable regions and never call disconnected clients verified', () => {
  assert.equal(regionName('EastLuminant'), 'Eastern Luminant');
  assert.equal(accountStatus({ seen: now() - 36, presence: { state: 'VERIFIED' } }, now()).text, 'Not connected');
  assert.equal(accountStatus({ seen: now() + 1 }, now()).state, 'OFFLINE');
});
test('offline cards give one instruction and do not guess the local auto-return setting', () => {
  const r = room();
  const card = () => renderPanel(r.config, {}, { token: nonce(), screen: 'home', account: '11' }, now()).data.embeds[1];
  assert.match(card().description, /Auto-return: local setting/);
  assert.equal((card().description.match(/loader/g) || []).length, 1);
  for (const enabled of [false, true]) {
    r.config.members['11'].allowMenuReturn = enabled;
    assert.ok(card().description.includes('Auto-return: ' + (enabled ? 'ON' : 'OFF')));
  }
});
test('empty region filters do not tell users to rescan an existing roster', () => {
  const r = room(), view = { token: nonce(), screen: 'slots', account: '11', filter: 'EtreanLuminant' };
  const filtered = renderPanel(r.config, {}, view, now()).data.embeds[0].description;
  assert.match(filtered, /No characters in this region.*All regions/);
  assert.ok(!filtered.includes('Leave this account'));
  r.config.members['11'].slots = {};
  assert.match(renderPanel(r.config, {}, view, now()).data.embeds[0].description, /character selection/);
});
test('character details can refresh and unsupported regions are labelled on the card', () => {
  const r = room(), member = r.config.members['11'];
  member.slots.L.region = null; member.slots.L.location = 'The Depths';
  const panel = renderPanel(r.config, {}, { token: nonce(), screen: 'detail', account: '11', slot: 'L' }, now());
  assert.match(panel.data.embeds[1].description, /Joining not supported here/);
  assert.equal(panel.offers.refresh.kind, 'refresh'); limits(panel.data);
  assert.equal(accountStatus({ seen: now(), presence: { state: 'WITH_MAIN' } }, now()).text, 'Already with your main');
});
test('cross-owner, public-message, forged selection, changed and expired controls fail without mutation', async () => {
  const r = room(), p = await open(r), before = JSON.stringify(r.config);
  assert.match((await click(r, p, 'follow', null, '234567890123456789')).data.content, /expired/);
  const bad = clicked(p, 'follow'); bad.message.flags = 0;
  assert.match((await panelCommand(r, bad, owner)).data.content, /expired/);
  assert.match((await click(r, p, 'account', '999')).data.content, /expired/);
  for (const view of r.storage.get('panels') && Object.values(r.storage.get('panels'))) view.expires = now() - 1;
  assert.match((await click(r, p, 'follow')).data.content, /expired/);
  assert.equal(JSON.stringify(r.config), before); assert.equal(r.broadcasts, 0);
});
test('follow requires confirmation and an old control cannot be replayed', async () => {
  const r = room(), p = await open(r); let next = await click(r, p, 'follow');
  assert.equal(r.config.follow, true); assert.equal(next.type, 7);
  const confirmInteraction = clicked(next, 'confirm'); next = await panelCommand(r, confirmInteraction, owner);
  assert.equal(r.config.follow, false); assert.equal(r.broadcasts, 1); limits(next.data);
  assert.match((await panelCommand(r, confirmInteraction, owner)).data.content, /expired/);
  assert.equal(r.broadcasts, 1);
});
test('the panel cannot re-enable follow while emergency stop is locked', async () => {
  const r = room(); r.config.follow = false; r.config.halted = true;
  let panel = await open(r); panel = await click(r, panel, 'follow'); panel = await click(r, panel, 'confirm');
  assert.equal(r.config.follow, false); assert.equal(r.broadcasts, 0);
  assert.match(panel.data.content, /Emergency stop is locked/);
});
test('stale confirmations reject config, credential, and character changes', async () => {
  for (const mutate of [r => r.config.revision = 'other', r => r.config.members['11'].credential = 'rotated',
    r => r.config.members['11'].slots.L.characterName = 'Replaced']) {
    const r = room(); let p = await open(r, { screen: 'detail', slot: 'L' }); p = await click(r, p, 'allow');
    mutate(r); p = await click(r, p, 'confirm');
    assert.match(p.data.content, /changed/); assert.deepEqual(r.config.members['11'].approvedSlots, {});
  }
});
test('allow, prefer and disable preserve other accounts and clear disabled preferences', async () => {
  const r = room(), key = r.config.members['11'].keyHash;
  let p = await open(r, { screen: 'detail', slot: 'L' }); p = await click(r, p, 'allow'); p = await click(r, p, 'confirm');
  assert.equal(r.config.members['11'].approvedSlots.L, true);
  p = await click(r, p, 'prefer'); p = await click(r, p, 'confirm'); assert.equal(r.config.members['11'].preferredSlots.EastLuminant, 'L');
  p = await click(r, p, 'allow'); await click(r, p, 'confirm');
  assert.deepEqual(r.config.members['11'].approvedSlots, {}); assert.deepEqual(r.config.members['11'].preferredSlots, {});
  assert.equal(r.config.members['11'].keyHash, key); assert.equal(r.config.follow, true);
});
test('fresh timestamp-only scans do not stale a confirmation, but expired evidence cannot be approved', async () => {
  const r = room(), v = { account: '11', slot: 'L' }, c = confirmation(r.config, v, {}, 'test');
  r.config.members['11'].slots.L.observedAt--;
  assert.equal(confirmationFresh(r.config, c), true);
  let p = await open(r, { screen: 'detail', slot: 'L' }); p = await click(r, p, 'allow');
  r.config.members['11'].slots.L.observedAt = now() - 86401;
  assert.match((await click(r, p, 'confirm')).data.content, /expired/);
  assert.deepEqual(r.config.members['11'].approvedSlots, {});
});
test('a failed storage commit never updates in-memory permissions or broadcasts success', async () => {
  const r = room(); let p = await open(r); p = await click(r, p, 'follow');
  r.ctx.storage.put = async () => { throw Error('storage failed'); };
  await assert.rejects(click(r, p, 'confirm')); assert.equal(r.config.follow, true); assert.equal(r.broadcasts, 0);
});
test('panels are bounded and older views expire without touching pairing or follow state', async () => {
  const r = room(), before = JSON.stringify(r.config), old = await open(r);
  for (let i = 0; i < 45; i++) await open(r);
  assert.equal(Object.keys(r.storage.get('panels')).length, 40);
  assert.match((await click(r, old, 'refresh')).data.content, /expired/); assert.equal(JSON.stringify(r.config), before);
});
test('batch setup has independent keys, checked approvals, expiry, and no implicit character permissions', async () => {
  const r = room(), saved = structuredClone(r.config.members['11']);
  let p = await open(r, { screen: 'setup' }); p = await click(r, p, 'batch-start');
  const code = p.data.content.match(/Code="([a-f0-9]{64})"/)[1];
  assert.ok(!JSON.stringify([...r.storage.values()]).includes(code));
  const input = { accountId: '22', username: 'Nova_Alt', code, key: 'b'.repeat(64) };
  assert.equal((await batchRequest(r, input, owner)).state, 'new');
  assert.equal((await batchRequest(r, input, owner, true)).state, 'pending');
  assert.equal((await batchRequest(r, input, '234567890123456789', true)).state, 'unauthorized');
  assert.equal((await batchRequest(r, { ...input, key: 'c'.repeat(64) }, owner, true)).state, 'request-exists');
  p = await click(r, p, 'refresh'); const request = controls(p).find(c => c.type === 3).options[0].value;
  p = await click(r, p, 'request', request); assert.equal(r.config.members['22'], undefined);
  p = await click(r, p, 'confirm'); assert.equal(r.config.members['22'].keyHash, await hash(input.key));
  assert.equal(r.config.members['22'].approvedSlots, undefined); assert.deepEqual(r.config.members['11'], saved); assert.equal(r.config.follow, true);
  assert.equal((await batchRequest(r, input, owner)).state, 'approved');
  assert.equal((await batchRequest(r, { ...input, key: 'c'.repeat(64) }, owner)).state, 'already-paired');
  p = await click(r, p, 'close'); await click(r, p, 'confirm');
  assert.equal((await batchRequest(r, input, owner)).state, 'approved');
  assert.equal((await batchRequest(r, { ...input, accountId: '33' }, owner, true)).state, 'expired');
  assert.equal((await batchRequest(r, { ...input, key: 'c'.repeat(64) }, owner)).state, 'expired', 'no membership disclosure without setup authority');
});
test('expired batch, full group, mismatched code and invalid input never enroll', async () => {
  const r = room(), input = { accountId: '22', username: 'Nova_Alt', code: 'b'.repeat(64), key: 'c'.repeat(64) };
  r.storage.set('batch', { id: nonce(), codeHash: await hash(input.code), expires: now() - 1, pending: {} });
  assert.equal((await batchRequest(r, input, owner, true)).state, 'expired');
  r.storage.get('batch').expires = now() + 100;
  assert.equal((await batchRequest(r, { ...input, code: 'd'.repeat(64) }, owner, true)).state, 'expired');
  assert.equal((await batchRequest(r, { ...input, accountId: '__proto__' }, owner, true)).state, 'unauthorized');
  for (let i = 100; i < 129; i++) r.config.members[String(i)] = {};
  assert.equal((await batchRequest(r, input, owner, true)).state, 'full');
  assert.equal(Object.keys(r.storage.get('batch').pending).length, 0);
});

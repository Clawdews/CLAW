import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanCatalog, menuRegion, selectable, catalogPage } from '../catalog.js';

const at = 2000000000;
const card = () => ({ slot: 'L', slotLabel: 'L', characterName: 'Rook Janus', level: 1,
  race: 'Khan', origin: 'Authority Ensign', location: 'Eastern Luminant', complete: true,
  playtime: '0h 26m', lastPlayed: '0m ago' });
const packet = () => ({ type: 'catalog', version: 1, accountId: '22', placeId: 4111023553, complete: true, cards: [card()] });

test('menu projection stores only bounded display metadata, with server observation time and no verification claim', () => {
  const input = packet(); Object.assign(input.cards[0], { confirmed: true, observedAt: at + 99, labels: ['private'], rawText: 'private', baseRace: 'hidden' });
  const output = cleanCatalog(input, '22', at), c = output.entries.L;
  assert.equal(output.complete, true); assert.equal(c.confirmed, false); assert.equal(c.observedAt, at);
  assert.equal(c.source, 'menu-card'); assert.equal(c.region, 'EastLuminant'); assert.equal(c.characterName, 'Rook Janus');
  for (const name of ['labels', 'rawText', 'baseRace', 'slotLabel']) assert.equal(c[name], undefined);
});
test('another account, wrong context, duplicate slots and prototype keys are rejected', () => {
  const variants = [ { accountId: '33' }, { placeId: 6473861193 }, { cards: [card(), card()] },
    { cards: [{ ...card(), slot: '__proto__' }] }, { cards: Array(61).fill(card()) }, { complete: 'yes' } ];
  for (const change of variants) assert.equal(cleanCatalog({ ...packet(), ...change }, '22', at), null);
});
test('oversized UTF-8, controls and invalid levels are rejected', () => {
  for (const change of [{ characterName: 'é'.repeat(41) }, { race: 'x\nsecret' }, { level: 1.5 }, { level: -1 }, { level: 1001 }]) {
    assert.equal(cleanCatalog({ ...packet(), cards: [{ ...card(), ...change }] }, '22', at), null);
  }
});
test('missing core fields and mismatched slot labels cannot be approved as complete cards', () => {
  for (const change of [{ slotLabel: 'X' }, { race: undefined }, { level: undefined }, { characterName: '' }, { complete: false }]) {
    const output = cleanCatalog({ ...packet(), cards: [{ ...card(), ...change }] }, '22', at);
    assert.equal(output.complete, false); assert.equal(selectable(output.entries.L, at), false);
  }
  assert.equal(cleanCatalog({ ...packet(), cards: [] }, '22', at).complete, false);
});
test('observed location aliases stay exact; unsupported layers are not guessed', () => {
  assert.equal(menuRegion('The Etrean Luminant'), 'EtreanLuminant');
  assert.equal(menuRegion('The Eastern Luminant'), 'EastLuminant');
  for (const name of ['The Depths (Scyphozia)', 'Fragments of Else', 'not Eastern Luminant']) assert.equal(menuRegion(name), null);
});
test('menu evidence expires, cannot be future dated, and does not require a false in-world confirmation', () => {
  const c = cleanCatalog(packet(), '22', at).entries.L;
  assert.ok(selectable(c, at)); assert.ok(!selectable(c, at - 1)); assert.ok(!selectable(c, at + 86401));
  assert.ok(!selectable({ ...c, complete: false }, at));
});
test('normal cards paginate five per page and include visible details and permission status', () => {
  const entries = {};
  for (let i = 0; i < 13; i++) { const slot = String.fromCharCode(65 + i); entries[slot] = { ...card(), slot, source: 'menu-card', observedAt: at }; }
  const member = { slots: entries, approvedSlots: { A: true } };
  const first = catalogPage(member, at), last = catalogPage(member, at, 3);
  assert.match(first, /Page 1\/3/); assert.match(first, /A: Eastern Luminant \| approved/);
  assert.match(first, /Rook Janus · Lv. 1 Khan · Authority Ensign/); assert.match(first, /Played 0h 26m · Last 0m ago/);
  assert.ok(!first.includes('F:')); assert.match(last, /M:/); assert.match(catalogPage(member, at, 4), /Choose page/);
});
test('worst-case metadata is escaped and paginated without cutting off cards or exceeding Discord content limits', () => {
  const slots = {};
  for (let i = 0; i < 60; i++) {
    const slot = String.fromCharCode(65 + Math.floor(i / 26)) + String.fromCharCode(65 + i % 26);
    slots[slot] = { ...card(), slot, characterName: '@'.repeat(80), race: '*'.repeat(40), oath: '`'.repeat(60), origin: '|'.repeat(60),
      location: '@'.repeat(100), playtime: '*'.repeat(32), lastPlayed: '*'.repeat(32), observedAt: at };
  }
  const member = { slots }, first = catalogPage(member, at), pages = Number(first.match(/Page 1\/(\d+)/)[1]);
  let output = '';
  for (let page = 1; page <= pages; page++) { const body = catalogPage(member, at, page); assert.ok(body.length < 1850); output += body; }
  for (const slot of Object.keys(slots)) assert.equal(output.split(`${slot}:`).length - 1, 1);
  assert.ok(output.includes('\\@')); assert.ok(!output.includes('@everyone'));
});

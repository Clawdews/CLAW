import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanNickname, nextStep, statusPage } from '../status.js';

const at = 2000000000;
test('nicknames are display-only bounded text, not control characters or a route to other accounts', () => {
  assert.equal(cleanNickname('  Farming alt  '), 'Farming alt');
  for (const input of ['', '   ', null, {}, 'bad\nlabel', 'a'.repeat(33), 'é'.repeat(17)]) assert.equal(cleanNickname(input), null);
});
test('status includes the actual observed character, approval count, menu setting and concrete next step', () => {
  const config = { mainId: '11', follow: true, members: {
    '11': { nickname: 'Main' }, '22': { nickname: 'Farming alt', allowMenuReturn: false, approvedSlots: { L: true },
      slots: { L: { characterName: 'Rook Janus' } } } } };
  const connections = { '22': { seen: at, presence: { state: 'WAITING_MENU', slot: 'L', placeId: 6473861193 } } };
  const text = statusPage(config, connections, at);
  assert.match(text, /Main: Main \(11\)/); assert.match(text, /Farming alt \(22\): WAITING\\_MENU/);
  assert.match(text, /Slot L · Rook Janus · cards 1 \/ approved 1 · auto-return OFF/);
  assert.match(text, /opt in with \/claw auto-return/); assert.match(text, /not independently observed/);
});
test('expired or future presence cannot display a live verified state', () => {
  const config = { members: { '22': {} } };
  for (const seen of [at - 36, at + 1]) {
    const text = statusPage(config, { '22': { seen, presence: { state: 'VERIFIED' } } }, at);
    assert.match(text, /22: OFFLINE/); assert.ok(!text.includes('VERIFIED'));
  }
});
test('large rosters and markdown-heavy names stay within message limits without losing accounts', () => {
  const config = { mainId: '11', members: {} }, connections = {};
  for (let i = 11; i < 41; i++) {
    config.members[i] = { nickname: '@'.repeat(32), slots: { L: { characterName: '*'.repeat(80) } } };
    connections[i] = { seen: at, presence: { state: 'ATTENTION: '.padEnd(60, '*'), slot: 'L' } };
  }
  const first = statusPage(config, connections, at), count = Number(first.match(/Page 1\/(\d+)/)[1]);
  let all = '';
  for (let p = 1; p <= count; p++) { const text = statusPage(config, connections, at, p); assert.ok(text.length < 2000); all += text; }
  for (let i = 11; i < 41; i++) assert.ok(all.includes(`(${i}):`));
  assert.match(statusPage(config, connections, at, count + 1), /Choose status page/);
  assert.match(all, /\\@/);
});
test('known waiting states get actionable advice without pretending to operate Roblox remotely', () => {
  for (const state of ['WAITING_SLOT_SCAN', 'WAITING_SLOT_SYNC', 'NO_COMPATIBLE_SLOT', 'CHOOSE_PREFERRED_SLOT',
    'ATTENTION: REGION_MISMATCH', 'AUTH_FAILED', 'WAITING_MAIN', 'OFFLINE', 'RECONNECTING']) assert.ok(nextStep(state));
  assert.equal(nextStep('VERIFIED'), ''); assert.equal(nextStep('MAIN'), '');
  assert.match(nextStep('OFFLINE'), /cannot launch/);
});

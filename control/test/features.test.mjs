import test from 'node:test';
import assert from 'node:assert/strict';
import { sharedCommand } from '../commands.js';
import { commandInput, featureCommand } from '../feature-commands.js';
import { ensureFeatures, formationOffset, readyReport, keyFor, named } from '../features.js';
import { cleanActionResult, cleanInventory, cleanLoot, cleanPosition, actionPacket, cleanQueuedAction } from '../actions.js';
import { shouldAlert, postAlert } from '../alerts.js';

test('public command stays inside Discord limits and exposes the complete control surface', () => {
  assert.ok(sharedCommand.options.length <= 25);
  const check = option => {
    assert.ok(option.name.length <= 32 && option.description.length <= 100);
    assert.ok(!option.options || option.options.length <= 25);
    if (option.type === 1) {
      let optional = false;
      for (const child of option.options || []) {
        if (child.required !== true) optional = true;
        else assert.equal(optional, false, option.name + ' has a required option after an optional one');
      }
    }
    for (const child of option.options || []) check(child);
  };
  for (const option of sharedCommand.options) {
    check(option);
  }
  for (const name of ['team', 'deploy', 'ready', 'move', 'spot', 'preset', 'data', 'settings', 'emergency', 'enmity']) {
    assert.ok(sharedCommand.options.some(option => option.name === name), name);
  }
});

test('saved names cannot collide with object internals', () => {
  for (const value of ['__proto__', 'constructor']) assert.equal(keyFor(value), null);
  assert.deepEqual(named({ normal: { name: 'Normal' } }, 'normal'), ['normal', { name: 'Normal' }]);
});

test('nested Discord commands are parsed without trusting display text', () => {
  const interaction = { data: { options: [{ type: 2, name: 'team', options: [{ type: 1, name: 'add',
    options: [{ name: 'team', value: 'Enmity' }, { name: 'account', value: '11' }] }] }] } };
  assert.deepEqual(commandInput(interaction), { name: 'team:add', values: { team: 'Enmity', account: '11' } });
});

test('formations are deterministic and ready checks explain every account', () => {
  const circle = [0, 1, 2, 3].map(index => formationOffset('circle', index, 4, 10));
  assert.deepEqual(circle[0], { x: 10, y: 0, z: 0 });
  assert.ok(Math.abs(circle[2].x + 10) < 0.001);
  assert.deepEqual(formationOffset('stack', 2, 4, 6), { x: 0, y: 3, z: 0 });
  const config = ensureFeatures({ mainId: '11', follow: true, members: { '11': { username: 'Main' }, '22': { username: 'Alt' } } });
  const report = readyReport(config, { '11': { seen: 100, presence: { state: 'MAIN', placeId: 6032399813 } },
    '22': { seen: 100, presence: { state: 'VERIFIED', placeId: 6032399813 } } }, null, 110);
  assert.match(report, /2 ready/); assert.match(report, /@Main/); assert.match(report, /@Alt/);
});

test('action, item, loot and position packets are bounded', () => {
  const packet = actionPacket('stop', {}, 90);
  assert.equal(cleanQueuedAction(packet)?.id, packet.id);
  assert.equal(cleanQueuedAction({ ...packet, action: 'execute-code' }), null);
  assert.ok(cleanActionResult({ type: 'action-result', accountId: '11', id: packet.id, ok: true, message: 'done' }, '11'));
  assert.equal(cleanActionResult({ type: 'action-result', accountId: '22', id: packet.id, ok: true }, '11'), null);
  assert.ok(cleanInventory({ type: 'inventory', version: 1, accountId: '11',
    inventory: [{ name: 'Sword', count: 1 }], bank: [] }, '11'));
  assert.equal(cleanInventory({ type: 'inventory', version: 1, accountId: '11',
    inventory: [{ name: '@everyone\n', count: 1 }], bank: [] }, '11'), null);
  assert.ok(cleanLoot({ type: 'loot', version: 1, accountId: '11', items: [{ name: 'Crown', count: 2 }] }, '11'));
  assert.deepEqual(cleanPosition({ x: 1, y: 2, z: 3 }), { x: 1, y: 2, z: 3 });
  assert.equal(cleanPosition({ x: Infinity, y: 2, z: 3 }), null);
});

test('alerts are opt-in, bounded and never echo credentials', async () => {
  assert.equal(shouldAlert('important', 'VERIFIED'), true);
  assert.equal(shouldAlert('important', 'WAIT_SLOT'), false);
  assert.equal(shouldAlert('all', 'WAIT_SLOT'), true);
  assert.equal(await postAlert({}, { mode: 'important', channelId: '123456789012345678' }, 'test', () => assert.fail()), false);
  const secret = ['private', 'bot', 'token', 'value'].join('-');
  let sent;
  assert.equal(await postAlert({ DISCORD_BOT_TOKEN: secret }, { mode: 'important', channelId: '123456789012345678' }, '@everyone ready',
    async (_url, options) => { sent = options; return new Response(null, { status: 204 }); }), true);
  assert.doesNotMatch(sent.body, /@everyone/);
  assert.doesNotMatch(sent.body, new RegExp(secret));
});

test('alert settings are saved only after Discord accepts a test message', async () => {
  const secret = ['private', 'bot', 'token', 'value'].join('-');
  const config = ensureFeatures({ members: {} }), interaction = { channel_id: '123456789012345678' };
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response(null, { status: 403 });
    let result = await featureCommand({ env: { DISCORD_BOT_TOKEN: secret } }, 'settings:alerts',
      { mode: 'important' }, interaction, config, {});
    assert.equal(result.changed, false); assert.equal(config.alerts.mode, 'off');
    globalThis.fetch = async () => new Response(null, { status: 204 });
    result = await featureCommand({ env: { DISCORD_BOT_TOKEN: secret } }, 'settings:alerts',
      { mode: 'important' }, interaction, config, {});
    assert.equal(result.changed, true); assert.equal(config.alerts.mode, 'important');
  } finally { globalThis.fetch = original; }
});

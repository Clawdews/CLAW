import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';

test('room timers, saved commands and fresh destinations survive overlapping events', async t => {
  const files = ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js', 'catalog.js', 'status.js',
    'accounts.js', 'panel.js', 'panel-controller.js', 'batch.js', 'features.js', 'actions.js', 'alerts.js', 'feature-commands.js'];
  const contents = `
    import { ControlRoom } from './worker.js';
    import { ensureFeatures } from './features.js';
    import { now } from './protocol.js';
    export class TestRoom extends ControlRoom {
      async probe() {
        this.config = ensureFeatures({ mainId: '11', follow: true, members: {
          '11': { credential: 'first' }, '22': { credential: 'second' } }, alerts: { mode: 'important' } });
        await this.ctx.storage.put('config', this.config);
        await this.ctx.storage.put('offline', { '11': { credential: 'first', due: now() - 1 } });
        let notification;
        this.notify = () => notification = this.markOffline('22');
        await this.alarm();
        await notification;
        const pending = await this.ctx.storage.get('offline');

        const attachment = { userId: '11', credential: 'first', seen: now(), presenceSeen: now() - 60,
          presence: { gameId: 99, placeId: 6032399813, jobId: 'old-job' } };
        const socket = { readyState: 1, deserializeAttachment: () => attachment };
        this.sockets = () => [socket];
        const staleTarget = this.target();
        attachment.presenceSeen = now();
        const sent = [], storedAtSend = [];
        this.send = (_socket, packet) => {
          sent.push(packet.type);
          if (packet.type === 'action') storedAtSend.push(this.ctx.storage.get('actions'));
        };
        await this.command({ id: '123456789012345678', data: { options: [{ type: 1, name: 'emergency',
          options: [{ name: 'action', value: 'stop' }] }] } }, now());
        const snapshots = await Promise.all(storedAtSend);
        this.config.members['22'].inventory = { bank: [{ name: 'Crown', count: 3 }], bankObservedAt: 100, observedAt: 100 };
        const inventorySocket = { readyState: 1, deserializeAttachment: () => ({ userId: '22', credential: 'second' }),
          serializeAttachment() {}, close() { throw Error('Inventory connection closed'); } };
        await this.webSocketMessage(inventorySocket, JSON.stringify({ type: 'inventory', version: 1, accountId: '22',
          inventory: [{ name: 'Sword', count: 1 }], bank: [], bankObserved: false }));
        return { pending: Object.keys(pending), staleTarget, sent,
          inventory: this.config.members['22'].inventory,
          storedBeforeSend: snapshots.every(queue => queue?.['11']?.some(packet => packet.action === 'stop')) };
      }
    }
    export default { async fetch(request, env) { return Response.json(await env.ROOM.getByName('review').probe()); } };
  `;
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'room-lifecycle-test',
    modules: [{ type: 'ESModule', path: fileURLToPath(new URL('../review-test-entry.js', import.meta.url)), contents },
      ...files.map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) }))],
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'TestRoom', useSQLite: true } },
  }] }));
  t.after(() => mf.dispose());
  const response = await mf.dispatchFetch('https://claw.test/');
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.deepEqual(result.pending, ['22'], 'a later disconnect was overwritten by the first alarm');
  assert.equal(result.staleTarget.enabled, false, 'other packets extended an old destination');
  assert.equal(result.storedBeforeSend, true, 'movement was sent before its queue was saved');
  assert.ok(result.sent.indexOf('profile') < result.sent.indexOf('action'), 'action arrived before updated permissions');
  assert.deepEqual(result.inventory.bank, [{ name: 'Crown', count: 3 }]);
  assert.equal(result.inventory.bankObservedAt, 100, 'closed bank changed its scan timestamp');
});

import { identifier, now } from './protocol.js';
import { activeFor } from './features.js';

const finite = value => typeof value === 'number' && Number.isFinite(value);
const text = (value, size) => typeof value === 'string' && !/[\x00-\x1f\x7f]/.test(value) && value.length <= size ? value : null;
export function cleanActionResult(input, accountId) {
  if (!input || input.type !== 'action-result' || input.accountId !== accountId
      || !identifier(input.id) || typeof input.ok !== 'boolean') return null;
  return { id: input.id, ok: input.ok, message: text(input.message, 160) || (input.ok ? 'completed' : 'failed'), at: now() };
}
export function cleanInventory(input, accountId) {
  if (!input || input.type !== 'inventory' || input.version !== 1 || input.accountId !== accountId
      || !Array.isArray(input.inventory) || !Array.isArray(input.bank)
      || input.inventory.length > 200 || input.bank.length > 200) return null;
  const clean = list => {
    const out = [], seen = new Set();
    for (const item of list) {
      if (!item || !text(item.name, 80) || !Number.isSafeInteger(item.count) || item.count < 1 || item.count > 9999
          || seen.has(item.name)) return null;
      seen.add(item.name); out.push({ name: item.name, count: item.count });
    }
    return out.sort((a, b) => a.name.localeCompare(b.name));
  };
  const inventory = clean(input.inventory), bank = clean(input.bank);
  return inventory && bank ? { inventory, bank, observedAt: now(), bankObserved: input.bankObserved !== false,
    bankObservedAt: input.bankObserved === false ? null : now() } : null;
}
export function cleanLoot(input, accountId) {
  if (!input || input.type !== 'loot' || input.version !== 1 || input.accountId !== accountId
      || !Array.isArray(input.items) || input.items.length < 1 || input.items.length > 20) return null;
  const items = [];
  for (const item of input.items) {
    if (!item || !text(item.name, 80) || !Number.isSafeInteger(item.count) || item.count < 1 || item.count > 100) return null;
    items.push({ name: item.name, count: item.count });
  }
  return items;
}
export function cleanPosition(value) {
  if (!value || !finite(value.x) || !finite(value.y) || !finite(value.z)
      || Math.abs(value.x) > 1e7 || Math.abs(value.y) > 1e7 || Math.abs(value.z) > 1e7) return null;
  return { x: value.x, y: value.y, z: value.z };
}
export function actionPacket(action, args, ttl = 90) {
  return { type: 'action', version: 1, id: crypto.randomUUID(), action, args, createdAt: now(), expiresAt: now() + ttl };
}
export function cleanQueuedAction(value, at = now()) {
  if (!value || value.type !== 'action' || value.version !== 1 || !identifier(value.id)
      || !['bring', 'park', 'stop', 'scan-items'].includes(value.action)
      || !Number.isSafeInteger(value.createdAt) || !Number.isSafeInteger(value.expiresAt)
      || value.expiresAt <= at || value.expiresAt > value.createdAt + 300) return null;
  return value;
}

const moves = packet => packet.action === 'bring' || packet.action === 'park';
export function reconcileActions(config, previous = {}, requests = [], at = now()) {
  const queue = {};
  const allowed = (account, packet) => {
    const member = config.members[account], scope = packet.scope;
    if (!member || !cleanQueuedAction(packet, at) || scope?.credential !== member.credential) return false;
    return !moves(packet) || (!config.halted && account !== config.mainId && activeFor(config, account)
      && scope.mainId === config.mainId && scope.team === config.activeTeam);
  };
  for (const [account, pending] of Object.entries(previous)) {
    const kept = pending.filter(packet => allowed(account, packet)).slice(-10);
    if (kept.length) queue[account] = kept;
  }
  for (const request of requests) for (const account of request.accounts || []) {
    if (!config.members[account]) continue;
    const packet = { ...request.packet, scope: { credential: config.members[account].credential,
      mainId: config.mainId, team: config.activeTeam } };
    if (!allowed(account, packet)) continue;
    const pending = (queue[account] || []).filter(old => {
      if (packet.action === 'stop' || moves(packet)) return !moves(old) && old.action !== 'stop';
      return old.action !== packet.action;
    });
    queue[account] = [...pending, packet].slice(-10);
  }
  return queue;
}
export function clientAction(packet) {
  const { scope, ...wire } = packet;
  return wire;
}

import { id, now, nonce, hash, sameHash, MAX_MEMBERS } from './protocol.js';

export function batchInput(input) {
  return input && id(input.accountId) && typeof input.username === 'string' && /^[A-Za-z0-9_]{1,20}$/.test(input.username)
    && typeof input.code === 'string' && /^[a-f0-9]{64}$/.test(input.code)
    && typeof input.key === 'string' && /^[a-f0-9]{64}$/.test(input.key);
}
// Called only inside the owning room's serialization boundary. No network I/O here.
export async function batchRequest(room, input, ownerId, register = false) {
  if (!batchInput(input) || room.config.ownerId !== ownerId) return { status: 401, state: 'unauthorized' };
  const keyHash = await hash(input.key), member = room.config.members[input.accountId];
  if (member && sameHash(member.keyHash, keyHash)) return { status: 200, state: 'approved' };
  const batch = await room.ctx.storage.get('batch');
  if (!batch || batch.expires <= now() || !sameHash(batch.codeHash, await hash(input.code))) return { status: 401, state: 'expired' };
  if (member) return { status: 409, state: 'already-paired' };
  const pending = Object.values(batch.pending).find(p => p.accountId === input.accountId);
  if (pending) return sameHash(pending.keyHash, keyHash) ? { status: 200, state: 'pending', check: pending.check, expires: batch.expires }
    : { status: 409, state: 'request-exists' };
  if (Object.keys(room.config.members).length + Object.keys(batch.pending).length >= MAX_MEMBERS) return { status: 429, state: 'full' };
  if (!register) return { status: 200, state: 'new' };
  const request = { id: nonce(), accountId: input.accountId, username: input.username, keyHash,
    check: nonce().replaceAll('-', '').slice(0, 8).toUpperCase() };
  batch.pending[request.id] = request;
  await room.ctx.storage.put('batch', batch);
  return { status: 200, state: 'pending', check: request.check, expires: batch.expires };
}

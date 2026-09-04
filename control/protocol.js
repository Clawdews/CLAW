export const LOBBY = 4111023553;
export const FRESH_SECONDS = 35;
export const MAX_MEMBERS = 30;
export const id = value => typeof value === 'string' && /^[1-9][0-9]{0,15}$/.test(value) && Number.isSafeInteger(Number(value));
export const snowflake = value => typeof value === 'string' && /^[1-9][0-9]{16,19}$/.test(value);
export const identifier = value => typeof value === 'string' && /^[\w:.\-]{1,160}$/.test(value);
export const slotId = value => typeof value === 'string' && value.length > 0 && value.length <= 160 && !/[\x00-\x1f]/.test(value);
const positive = value => Number.isSafeInteger(value) && value > 0;
export const now = () => Math.floor(Date.now() / 1000);
export const nonce = () => crypto.randomUUID();
export async function hash(value) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
}
export function sameHash(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== 64 || b.length !== 64) return false;
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
export function cleanPresence(value) {
  if (!value || !positive(value.gameId) || !positive(value.placeId) || !identifier(value.jobId)) return null;
  const position = value.position && [value.position.x, value.position.y, value.position.z].every(Number.isFinite)
    && [value.position.x, value.position.y, value.position.z].every(number => Math.abs(number) <= 1e7)
    ? { x: value.position.x, y: value.position.y, z: value.position.z } : null;
  const result = { gameId: value.gameId, placeId: value.placeId, jobId: value.jobId,
    slot: slotId(value.slot) ? value.slot : null,
    state: typeof value.state === 'string' ? value.state.replace(/[\x00-\x1f]/g, '').slice(0, 60) : 'ONLINE' };
  if (position) result.position = position;
  if (typeof value.movement === 'string') result.movement = value.movement.replace(/[\x00-\x1f]/g, '').slice(0, 80);
  return result;
}
export function ticketFor(mainId, presence, revision, at = now()) {
  return { version: 1, controllerId: Number(mainId), gameId: presence.gameId,
    placeId: presence.placeId, jobId: presence.jobId, joinId: presence.jobId,
    createdAt: at, nonce: revision };
}
export function targetKey(presence) { return `${presence.gameId}.${presence.placeId}.${presence.jobId}`; }
export async function discordSignature(body, timestamp, signature, publicKey, at = now()) {
  if (!/^\d{10}$/.test(timestamp || '') || Math.abs(at - Number(timestamp)) > 300
      || !/^[a-f0-9]{128}$/i.test(signature || '') || !/^[a-f0-9]{64}$/i.test(publicKey || '')) return false;
  try {
    const bytes = hex => Uint8Array.from(hex.match(/../g), b => parseInt(b, 16));
    const key = await crypto.subtle.importKey('raw', bytes(publicKey), 'Ed25519', false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, bytes(signature), new TextEncoder().encode(timestamp + body));
  } catch { return false; }
}
export const reply = content => ({ type: 4, data: { content, flags: 64, allowed_mentions: { parse: [] } } });

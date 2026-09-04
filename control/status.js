import { FRESH_SECONDS, LOBBY } from './protocol.js';
import { regionForPlace } from './tenancy.js';

const escape = value => String(value).replace(/[\\`*_~|<>@\[\]()]/g, '\\$&');
const short = (value, size) => Array.from(String(value || '')).slice(0, size).join('');
export function cleanNickname(value) {
  if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) return null;
  const label = value.trim();
  return label && new TextEncoder().encode(label).length <= 32 ? label : null;
}
export function nextStep(state) {
  if (/WAITING_SLOT_SCAN/.test(state)) return 'Keep character selection open until the cards finish loading.';
  if (/WAITING_SLOT_SYNC/.test(state)) return 'Waiting for cloud permissions to match the current cards.';
  if (/NO_APPROVED_SLOT|NO_COMPATIBLE_SLOT|NEEDS_SLOT/.test(state)) return 'Use /claw slots, then approve a character in the main’s region.';
  if (/CHOOSE_PREFERRED_SLOT/.test(state)) return 'Use /claw prefer-slot to choose between approved characters.';
  if (/REGION_MISMATCH|UNSUPPORTED_REGION/.test(state)) return 'No join sent for this mismatch. Refresh the slot’s region before retrying.';
  if (/WAITING_MENU/.test(state)) return 'Return this alt to the menu, or opt in with /claw auto-return.';
  if (/WAITING_MAIN/.test(state)) return 'Keep the chosen main loaded and connected.';
  if (/AUTH_FAILED/.test(state)) return 'Check the account pairing; use /claw rotate for a replacement key.';
  if (/ATTENTION/.test(state)) return 'Fix the reported cause, then /claw retry for one new attempt.';
  if (/OFFLINE/.test(state)) return 'Start Roblox and the paired loader; Discord cannot launch a closed client.';
  if (/RECONNECTING|CONNECTING/.test(state)) return 'The client is reconnecting; it will not act without a fresh target.';
  return '';
}
export function statusPage(config, connections, at, page = 1) {
  const members = Object.entries(config.members || {}).sort(([a], [b]) => a.localeCompare(b));
  const pages = [[]]; let length = 0;
  for (const [account, member] of members) {
    const connection = connections[account];
    const live = connection && connection.seen <= at && at - connection.seen <= FRESH_SECONDS ? connection : null;
    const presence = live?.presence, state = presence?.state || (live ? 'CONNECTING' : 'OFFLINE');
    const slot = presence?.slot, character = slot && member.slots?.[slot];
    const heading = `${member.nickname ? escape(member.nickname) + ' (' + account + ')' : account}: ${escape(short(state, 60))}`;
    const where = presence?.placeId === LOBBY ? 'character menu' : (regionForPlace(presence?.placeId) || (presence ? 'unmapped region' : 'offline'));
    const details = slot ? `Slot ${escape(short(slot, 12))}${character?.characterName ? ' · ' + escape(short(character.characterName, 80)) : ''}` : where;
    const cards = Object.keys(member.slots || {}).length;
    const approved = Object.values(member.approvedSlots || {}).filter(v => v === true).length;
    const automatic = typeof member.allowMenuReturn === 'boolean' ? (member.allowMenuReturn ? 'ON' : 'OFF') : 'local/default OFF';
    const advice = nextStep(state);
    const line = `${heading}\n${details} · cards ${cards} / approved ${approved} · auto-return ${automatic}` + (advice ? '\n' + advice : '');
    if (pages.at(-1).length >= 4 || length + line.length + 2 > 1600) { pages.push([]); length = 0; }
    pages.at(-1).push(line); length += line.length + 2;
  }
  if (!Number.isInteger(page) || page < 1 || page > pages.length) return `Choose status page 1–${pages.length}.`;
  const main = config.mainId ? (config.members?.[config.mainId]?.nickname
    ? `${escape(config.members[config.mainId].nickname)} (${config.mainId})` : config.mainId) : 'not selected';
  return `Follow: ${config.follow ? 'ON' : 'OFF'} | Main: ${main}\nPage ${page}/${pages.length}\n\n`
    + (pages[page - 1].join('\n\n') || 'No accounts paired yet. Use /claw setup.')
    + '\n\nStatuses are reported by your paired clients, not independently observed by Discord.';
}

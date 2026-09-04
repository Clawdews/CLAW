import { LOBBY } from './protocol.js';
import { safeSlot } from './tenancy.js';

export const MAX_SLOTS = 60;
const limits = { characterName: 80, race: 40, oath: 60, origin: 60, location: 100, playtime: 32, lastPlayed: 32 };
const regions = { eastluminant: 'EastLuminant', easternluminant: 'EastLuminant', theeasternluminant: 'EastLuminant',
  etreanluminant: 'EtreanLuminant', theetreanluminant: 'EtreanLuminant' };
export function menuRegion(value) { return typeof value === 'string' ? regions[value.toLowerCase().replace(/[\s_-]/g, '')] || null : null; }
const encoder = new TextEncoder();
export function cleanCatalog(input, accountId, at) {
  if (!input || input.type !== 'catalog' || input.version !== 1 || input.accountId !== accountId
      || input.placeId !== LOBBY || typeof input.complete !== 'boolean' || !Array.isArray(input.cards)
      || input.cards.length > MAX_SLOTS) return null;
  const entries = {}, seen = new Set();
  for (const item of input.cards) {
    if (!item || !safeSlot(item.slot) || !/^[A-Z]{1,3}$/.test(item.slot) || seen.has(item.slot)
        || typeof item.complete !== 'boolean') return null;
    seen.add(item.slot);
    const card = { slot: item.slot, source: 'menu-card', confirmed: false, observedAt: at };
    for (const [field, limit] of Object.entries(limits)) {
      const value = item[field];
      if (value == null) continue;
      if (typeof value !== 'string' || /[\x00-\x1f]/.test(value) || encoder.encode(value).length > limit) return null;
      card[field] = value;
    }
    if (item.level != null && (!Number.isInteger(item.level) || item.level < 0 || item.level > 1000)) return null;
    card.level = item.level ?? null;
    card.region = menuRegion(card.location);
    card.complete = item.complete && item.slotLabel === item.slot && !!card.characterName && !!card.race
      && !!card.location && card.level !== null;
    entries[card.slot] = card;
  }
  return { entries, complete: input.complete && seen.size > 0 && Object.values(entries).every(c => c.complete), observedAt: at };
}
export function selectable(entry, at) {
  return entry && (entry.confirmed === true || (entry.source === 'menu-card' && entry.complete === true))
    && Number.isInteger(entry.observedAt) && entry.observedAt <= at && at - entry.observedAt <= 86400;
}
const escape = value => String(value).replace(/[\\`*_~|<>@\[\]()]/g, '\\$&');
export function catalogPage(member, at, page = 1) {
  const entries = Object.values(member.slots || {}).sort((a, b) => a.slot.length - b.slot.length || a.slot.localeCompare(b.slot));
  const lines = entries.map(s => {
    const permission = member.approvedSlots?.[s.slot] ? 'approved' : 'not approved';
    const age = selectable(s, at) ? (s.confirmed ? 'verified in-world' : 'menu observed') : 'stale/incomplete';
    return `${escape(s.slot)}: ${escape(s.region || s.location || 'unsupported region')} | ${permission} | ${age}`
      + (s.characterName ? `\n${escape(s.characterName)} · Lv. ${s.level ?? '?'} ${escape(s.race || '?')}` : '')
      + ([s.oath, s.origin].filter(Boolean).length ? ` · ${[s.oath, s.origin].filter(Boolean).map(escape).join(' · ')}` : '')
      + (s.playtime || s.lastPlayed ? `\nPlayed ${escape(s.playtime || '?')} · Last ${escape(s.lastPlayed || '?')}` : '');
  });
  const groups = [[]]; let length = 0;
  for (const line of lines) {
    if (groups.at(-1).length >= 5 || length + line.length + 2 > 1750) { groups.push([]); length = 0; }
    groups.at(-1).push(line); length += line.length + 2;
  }
  if (!Number.isInteger(page) || page < 1 || page > groups.length) return `Choose page 1–${groups.length}.`;
  return `Page ${page}/${groups.length}\n${groups[page - 1].join('\n\n') || 'No characters yet. Run the paired loader at character selection.'}`;
}

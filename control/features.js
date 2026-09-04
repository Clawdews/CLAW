import { FRESH_SECONDS, LOBBY, id, now, nonce } from './protocol.js';
import { regionForPlace } from './tenancy.js';

export const MAX_TEAMS = 20, MAX_PRESETS = 20, MAX_SPOTS = 20, MAX_HISTORY = 100, MAX_LOOT = 100;
const encoder = new TextEncoder();
const escape = value => String(value ?? '').replace(/[\\`*_~|<>@\[\]()]/g, '\\$&');
const safeText = (value, bytes) => {
  if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) return null;
  const text = value.trim();
  return text && encoder.encode(text).length <= bytes ? text : null;
};
export const cleanName = value => safeText(value, 32);
export const cleanNote = value => safeText(value, 200);
export const cleanEventText = value => safeText(value, 160);
export const keyFor = value => {
  const key = cleanName(value)?.toLocaleLowerCase('en-US') || null;
  return key && !Object.prototype.hasOwnProperty.call(Object.prototype, key) ? key : null;
};

export function ensureFeatures(config) {
  config.teams ||= {};
  config.presets ||= {};
  config.spots ||= {};
  config.activeTeam ||= null;
  config.halted = config.halted === true;
  config.alerts ||= { mode: 'off', channelId: null };
  config.session ||= null;
  return config;
}
export function named(collection, name) {
  const key = keyFor(name);
  return key && collection && Object.prototype.hasOwnProperty.call(collection, key) ? [key, collection[key]] : [key, null];
}
export function teamMembers(config, team) {
  return [...new Set((team?.members || []).filter(account => id(account) && config.members?.[account]))];
}
export function teamLabel(team) { return cleanName(team?.name) || 'Unnamed team'; }
export function formationOffset(shape, index, total, spacing = 6) {
  const count = Math.max(1, total), place = Math.max(0, index);
  const gap = Math.max(2, Math.min(30, Number(spacing) || 6));
  if (shape === 'stack') return { x: 0, y: place * 1.5, z: 0 };
  if (shape === 'line') return { x: (place - (count - 1) / 2) * gap, y: 0, z: -gap };
  if (shape === 'spread') {
    const columns = Math.ceil(Math.sqrt(count)), row = Math.floor(place / columns), column = place % columns;
    return { x: (column - (columns - 1) / 2) * gap, y: 0, z: -(row + 1) * gap };
  }
  const angle = (place / count) * Math.PI * 2;
  return { x: Math.cos(angle) * gap, y: 0, z: Math.sin(angle) * gap };
}
export function activeFor(config, account) {
  if (!config.activeTeam) return true;
  const team = config.teams?.[config.activeTeam];
  return account === config.mainId || teamMembers(config, team).includes(account);
}

const display = (account, member) => member?.nickname || (member?.username ? '@' + member.username : 'Account ' + account);
const stateName = connection => connection?.presence?.state || (connection ? 'CONNECTING' : 'OFFLINE');
export function readyReport(config, connections, requestedTeam, at = now()) {
  ensureFeatures(config);
  let team = null;
  if (requestedTeam) [, team] = named(config.teams, requestedTeam);
  else if (config.activeTeam) team = config.teams[config.activeTeam];
  const ids = team ? teamMembers(config, team) : Object.keys(config.members || {});
  if (!ids.length) return team ? 'That team has no paired accounts.' : 'No accounts are paired.';
  const lines = [], totals = { ready: 0, waiting: 0, offline: 0 };
  for (const account of ids) {
    const member = config.members[account], connection = connections[account];
    const live = connection && at - connection.seen <= FRESH_SECONDS;
    const state = live ? stateName(connection) : 'OFFLINE';
    const withMain = account === config.mainId ? state === 'MAIN' : ['VERIFIED', 'WITH_MAIN'].includes(state);
    const ready = live && (withMain || (!config.follow && state === 'PAUSED'));
    if (!live) totals.offline++; else if (ready) totals.ready++; else totals.waiting++;
    const where = !live ? 'not connected' : !connection.presence ? 'connecting' : connection.presence.placeId === LOBBY ? 'character selection'
      : regionForPlace(connection.presence?.placeId) || 'another region';
    lines.push((ready ? 'READY' : !live ? 'OFFLINE' : 'WAIT') + ' · ' + escape(display(account, member)) + ' · ' + escape(where) + ' · ' + escape(state));
  }
  const label = team ? teamLabel(team) : 'All accounts';
  return (escape(label) + ': ' + totals.ready + ' ready · ' + totals.waiting + ' waiting · ' + totals.offline + ' offline\n' + lines.join('\n')).slice(0, 1950);
}
export function teamsReport(config) {
  ensureFeatures(config);
  const teams = Object.entries(config.teams);
  if (!teams.length) return 'No teams saved.';
  return teams.map(([key, team]) => (key === config.activeTeam ? 'ACTIVE · ' : '') + escape(teamLabel(team)) + ' · '
    + teamMembers(config, team).length + ' accounts' + (team.mainId ? ' · main ' + escape(display(team.mainId, config.members[team.mainId])) : '')
    + ' · recovery ' + (team.recovery ? 'ON' : 'OFF')).join('\n').slice(0, 1950);
}
export function presetsReport(config) {
  ensureFeatures(config);
  const presets = Object.values(config.presets);
  if (!presets.length) return 'No presets saved.';
  return presets.map(preset => escape(preset.name) + ' · ' + escape(preset.teamName) + ' · ' + Object.keys(preset.members || {}).length + ' accounts').join('\n').slice(0, 1950);
}
export function spotsReport(config) {
  ensureFeatures(config);
  const spots = Object.values(config.spots);
  if (!spots.length) return 'No parking spots saved.';
  return spots.map(spot => escape(spot.name) + ' · ' + escape(regionForPlace(spot.placeId) || 'unmapped place') + ' · saved <t:' + spot.savedAt + ':R>').join('\n').slice(0, 1950);
}
export async function addHistory(room, type, text, account = null) {
  const message = cleanEventText(text);
  if (!message) return;
  const history = await room.ctx.storage.get('history') || [];
  history.push({ id: nonce(), at: now(), type: String(type).slice(0, 24), text: message, account: id(account) ? account : null,
    sessionId: room.config.session?.id || null });
  await room.ctx.storage.put('history', history.slice(-MAX_HISTORY));
}
export async function historyReport(room) {
  const history = await room.ctx.storage.get('history') || [];
  if (!history.length) return 'No CLAW activity recorded yet.';
  return history.slice(-20).reverse().map(item => '<t:' + item.at + ':t> · ' + escape(item.text)).join('\n').slice(0, 1950);
}
export async function addLoot(room, account, items) {
  const history = await room.ctx.storage.get('loot') || [];
  for (const item of items) history.push({ at: now(), account, name: item.name, count: item.count });
  await room.ctx.storage.put('loot', history.slice(-MAX_LOOT));
}
export async function lootReport(room) {
  const loot = await room.ctx.storage.get('loot') || [];
  if (!loot.length) return 'No item gains recorded yet.';
  return loot.slice(-25).reverse().map(item => '<t:' + item.at + ':t> · ' + escape(display(item.account, room.config.members[item.account]))
    + ' · +' + item.count + ' ' + escape(item.name)).join('\n').slice(0, 1950);
}
export function inventoryReport(config, account) {
  const member = config.members?.[account];
  if (!member) return 'That account is not paired.';
  const inventory = member.inventory;
  if (!inventory) return 'No item scan yet. Leave the public loader running in-game.';
  const section = source => {
    const items = inventory[source] || [];
    return '**' + (source === 'bank' ? 'Bank' : 'Inventory') + '**\n'
      + (items.length ? items.map(item => item.count + '× ' + escape(item.name)).join('\n') : 'Nothing recorded');
  };
  return (escape(display(account, member)) + ' · scanned <t:' + inventory.observedAt + ':R>\n' + section('inventory') + '\n\n' + section('bank')).slice(0, 1950);
}
export function sessionReport(config) {
  if (!config.session) return 'No session is running.';
  return 'Session ' + (config.session.name || 'active') + ' started <t:' + config.session.startedAt + ':R>.';
}

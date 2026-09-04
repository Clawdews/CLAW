import { FRESH_SECONDS, LOBBY } from './protocol.js';
import { selectable } from './catalog.js';
import { nextStep } from './status.js';
import { regionForPlace } from './tenancy.js';

export const PANEL_TTL = 900;
export const regionName = value => ({ EastLuminant: 'Eastern Luminant', EtreanLuminant: 'Etrean Luminant' })[value] || value || 'Unknown region';
const cut = (value, n) => String(value || '').slice(0, n);
const escape = value => String(value ?? '').replace(/[\\`*_~|<>@\[\]()]/g, '\\$&');
export const accountName = (account, member) => member?.nickname || (member?.username ? '@' + member.username : 'Account ' + account);
const states = { OFFLINE: 'Not connected', CONNECTING: 'Connecting', RECONNECTING: 'Reconnecting', MAIN: 'Main connected',
  PAUSED: 'Following paused', VERIFIED: 'Joined the correct server', WAITING_MAIN: 'Waiting for your main',
  WAITING_MENU: 'Waiting at the game menu', WAITING_SLOT_SCAN: 'Reading character cards', WAITING_SLOT_SYNC: 'Syncing character permissions',
  NO_APPROVED_SLOT: 'Choose an allowed character', NO_COMPATIBLE_SLOT: 'No allowed character in this region',
  CHOOSE_PREFERRED_SLOT: 'Choose a preferred character', JOINING: 'Joining your main', TELEPORTING: 'Joining your main' };
export function accountStatus(connection, at) {
  const live = connection && connection.seen <= at && at - connection.seen <= FRESH_SECONDS;
  const state = live ? connection.presence?.state || 'CONNECTING' : 'OFFLINE';
  return { state, text: states[state] || cut(state.replaceAll('_', ' ').toLowerCase(), 60),
    where: live ? (connection.presence?.placeId === LOBBY ? 'Character selection' : regionName(regionForPlace(connection.presence?.placeId))) : 'Open Roblox and run the public loader.',
    advice: nextStep(state) };
}
export const cardStamp = card => JSON.stringify(card ? [card.slot, card.characterName, card.level, card.race, card.region, card.location, card.complete, card.confirmed] : null);
export function slotChoices(member, filter) {
  return Object.values(member?.slots || {}).filter(card => !filter || filter === 'all' || (filter === 'other'
    ? !['EastLuminant', 'EtreanLuminant'].includes(card.region) : card.region === filter))
    .sort((a, b) => a.slot.length - b.slot.length || a.slot.localeCompare(b.slot));
}

// The offered actions are stored with a short-lived, owner-bound view. Custom IDs contain no account keys.
export function renderPanel(config, connections, view, at, batch = null) {
  const offers = {}, components = [], embeds = [];
  const cid = action => `claw:${view.token}:${action}`;
  const button = (action, label, spec, disabled = false, style = 2) => {
    if (!disabled) offers[action] = { type: 2, ...spec };
    return { type: 2, custom_id: cid(action), label, style, disabled };
  };
  const row = (...items) => components.push({ type: 1, components: items });
  const select = (action, placeholder, options, spec) => {
    if (!options.length) return;
    offers[action] = { type: 3, values: options.map(o => o.value), ...spec };
    row({ type: 3, custom_id: cid(action), placeholder, min_values: 1, max_values: 1, options });
  };
  const title = (name, description) => embeds.push({ title: name, description, color: 0x8272db });
  const members = Object.entries(config.members || {}).sort(([a], [b]) => a === config.mainId ? -1 : b === config.mainId ? 1 : a.localeCompare(b));
  const member = config.members[view.account];
  if (view.confirm) {
    title('Confirm this change', view.confirm.description);
    row(button('confirm', 'Confirm', { kind: 'confirm' }, false, 3), button('cancel', 'Go back', { kind: 'cancel' }));
  } else if (view.screen === 'setup') {
    title('Pair your accounts', 'One public loader for every account. Existing pairings are saved; you do not need to pair them again.');
    embeds[0].fields = [
      { name: 'One account', value: 'Use `/claw enroll account:username`, then run its private reply once on that Roblox account.' },
      { name: 'Several alts on one device', value: 'Start a 10-minute setup window. Run its private setup snippet once in your shared executor workspace. New accounts using the public loader will appear here for approval.' },
      { name: 'Keep it private', value: 'Only approve requests whose check code matches your own Roblox console. Pairing does not approve characters or turn following on.' },
    ];
    row(button('batch-start', 'Start alt setup', { kind: 'batch-start' }, false, 1), button('requests', 'Pairing requests', { kind: 'screen', screen: 'requests' }), button('home', 'Accounts', { kind: 'home' }));
  } else if (view.screen === 'requests') {
    const pending = batch && batch.expires > at ? Object.values(batch.pending || {}) : [];
    const pages = Math.max(1, Math.ceil(pending.length / 5)); view.page = Math.min(view.page || 0, pages - 1);
    const shown = pending.slice(view.page * 5, view.page * 5 + 5);
    title('Pairing requests', batch && batch.expires > at
      ? `Setup closes <t:${batch.expires}:R>. Approve only your own accounts after matching the check code in Roblox.\n${pending.length} waiting · Page ${view.page + 1}/${pages}`
      : 'No active setup window. Start one from Setup when you are ready.');
    for (const request of shown) embeds.push({ title: '@' + request.username, color: 0x8272db,
      description: `Check code: **${request.check}**\nCompare this with the console on that account. A username alone is not proof of ownership.` });
    select('request', 'Choose a request to review', shown.map(r => ({ label: '@' + r.username, value: r.id, description: 'Check ' + r.check })), { kind: 'request', batchId: batch?.id });
    row(button('prev', 'Previous', { kind: 'page', page: view.page - 1 }, view.page === 0), button('next', 'Next', { kind: 'page', page: view.page + 1 }, view.page + 1 >= pages),
      button('refresh', 'Refresh', { kind: 'refresh' }), button('close', 'Close setup', { kind: 'batch-close', batchId: batch?.id }, !batch || batch.expires <= at, 4), button('home', 'Accounts', { kind: 'home' }));
  } else if ((view.screen === 'slots' || view.screen === 'detail') && member) {
    const entries = slotChoices(member, view.filter), pages = Math.max(1, Math.ceil(entries.length / 5));
    view.page = Math.min(view.page || 0, pages - 1);
    const shown = entries.slice(view.page * 5, view.page * 5 + 5);
    const card = view.screen === 'detail' && member.slots?.[view.slot];
    title(escape(accountName(view.account, member)) + ' · Characters', `Page ${view.page + 1}/${pages} · ${entries.length} characters\nApprovals allow automatic selection; they do not make an unsupported region joinable.`);
    const cardEmbed = s => {
      const approved = member.approvedSlots?.[s.slot] === true;
      const preferred = member.preferredSlots?.[s.region] === s.slot;
      const ready = selectable(s, at);
      return { title: `Slot ${escape(s.slot)} · ${escape(s.characterName || 'Unnamed character')}`, color: approved ? 0x48a879 : 0x747780,
        description: `**Power ${s.level ?? '?'} · ${escape(s.race || 'Race unknown')}**\n${[s.oath, s.origin].filter(Boolean).map(escape).join(' · ') || 'Origin not recorded'}\n${escape(regionName(s.region || s.location))}\n`
          + `${approved ? 'Allowed' : 'Not allowed'}${preferred ? ' · Preferred' : ''} · ${ready ? 'Recently observed' : 'Needs a fresh menu scan'}` };
    };
    if (card) {
      const item = cardEmbed(card);
      item.fields = [{ name: 'Details', value: `Playtime: ${escape(card.playtime || 'Not recorded')}\nLast played: ${escape(card.lastPlayed || 'Not recorded')}\nLast scan: ${Number.isInteger(card.observedAt) ? `<t:${card.observedAt}:R>` : 'Not recorded'}` }];
      embeds.push(item);
      const approved = member.approvedSlots?.[card.slot] === true;
      const supported = ['EastLuminant', 'EtreanLuminant'].includes(card.region);
      row(button('allow', approved ? 'Disable character' : 'Allow character', { kind: 'policy', operation: 'allow', enabled: !approved }, !approved && !selectable(card, at), approved ? 4 : 3),
        button('prefer', 'Prefer in this region', { kind: 'policy', operation: 'prefer' }, !approved || !supported || !selectable(card, at) || member.preferredSlots?.[card.region] === card.slot),
        button('back', 'Back to characters', { kind: 'screen', screen: 'slots' }), button('home', 'Accounts', { kind: 'home' }));
    } else {
      embeds.push(...shown.map(cardEmbed));
      if (!shown.length) embeds[0].description += '\nNo cards here yet. Leave this account at character selection with the public loader running.';
      select('filter', 'Filter by region', [{ label: 'All regions', value: 'all' }, { label: 'Eastern Luminant', value: 'EastLuminant' },
        { label: 'Etrean Luminant', value: 'EtreanLuminant' }, { label: 'Other regions', value: 'other' }].map(o => ({ ...o, default: o.value === (view.filter || 'all') })), { kind: 'filter' });
      select('slot', 'Choose a character for details and permissions', shown.map(s => ({ label: cut(`${s.slot} · ${s.characterName || 'Unnamed character'}`, 100), value: s.slot,
        description: cut(`Power ${s.level ?? '?'} · ${s.race || '?'} · ${regionName(s.region || s.location)}`, 100) })), { kind: 'slot' });
      row(button('prev', 'Previous', { kind: 'page', page: view.page - 1 }, view.page === 0), button('next', 'Next', { kind: 'page', page: view.page + 1 }, view.page + 1 >= pages),
        button('refresh', 'Refresh', { kind: 'refresh' }), button('home', 'Accounts', { kind: 'home' }));
    }
  } else {
    view.screen = 'home';
    const pages = Math.max(1, Math.ceil(members.length / 5)); view.page = Math.min(view.page || 0, pages - 1);
    const shown = members.slice(view.page * 5, view.page * 5 + 5);
    const main = config.mainId ? accountName(config.mainId, config.members[config.mainId]) : 'Not selected';
    title('CLAW · Your accounts', `**Following ${config.follow ? 'ON' : 'OFF'}** · Main: ${escape(main)}\nPage ${view.page + 1}/${pages} · Choose an account below to see its characters.${member ? '\nSelected: **' + escape(accountName(view.account, member)) + '**' : ''}`);
    for (const [account, m] of shown) {
      const status = accountStatus(connections[account], at);
      embeds.push({ title: `${account === config.mainId ? 'MAIN' : 'ALT'} · ${escape(accountName(account, m))}`, color: status.state === 'OFFLINE' ? 0x747780 : 0x48a879,
        description: `**${escape(status.text)}**\n${escape(status.where)}\n${Object.values(m.approvedSlots || {}).filter(Boolean).length} allowed / ${Object.keys(m.slots || {}).length} characters · Auto-return ${m.allowMenuReturn === true ? 'ON' : 'OFF'}${status.advice ? '\n' + status.advice : ''}` });
    }
    select('account', 'Choose an account', shown.map(([account, m]) => ({ label: cut(accountName(account, m), 100), value: account, default: account === view.account,
      description: account === config.mainId ? 'Main account' : 'Alt account' })), { kind: 'account' });
    row(button('prev', 'Previous', { kind: 'page', page: view.page - 1 }, view.page === 0), button('next', 'Next', { kind: 'page', page: view.page + 1 }, view.page + 1 >= pages),
      button('refresh', 'Refresh', { kind: 'refresh' }), button('follow', config.follow ? 'Pause following' : 'Enable following', { kind: 'follow', enabled: !config.follow }, !config.mainId, config.follow ? 4 : 3),
      button('setup', 'Setup', { kind: 'screen', screen: 'setup' }));
    if (member) row(button('characters', 'Characters', { kind: 'screen', screen: 'slots' }), button('main', 'Use as main', { kind: 'main' }, view.account === config.mainId));
  }
  embeds[0].footer = { text: 'Private to you · Status reported by paired clients · Refresh to update' };
  return { data: { content: view.notice || '', embeds, components, allowed_mentions: { parse: [] } }, offers };
}

export function confirmation(config, view, operation, description) {
  const member = config.members[view.account];
  return { ...operation, account: view.account || null, slot: view.slot || null, revision: config.revision,
    credential: member?.credential || null, stamp: cardStamp(member?.slots?.[view.slot]), description };
}
export function confirmationFresh(config, change) {
  return config.revision === change.revision && (config.members[change.account]?.credential || null) === change.credential
    && cardStamp(config.members[change.account]?.slots?.[change.slot]) === change.stamp;
}

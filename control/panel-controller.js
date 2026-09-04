import { now, nonce, hash, MAX_MEMBERS, reply } from './protocol.js';
import { selectable } from './catalog.js';
import { PANEL_TTL, renderPanel, confirmation, confirmationFresh, accountName } from './panel.js';

const expired = () => reply('That panel has expired or changed. Open /claw panel again; no settings were changed.');
export async function panelCommand(room, interaction, ownerId, initial) {
  const at = now();
  const views = Object.fromEntries(Object.entries(await room.ctx.storage.get('panels') || {}).filter(([, v]) => v.expires > at));
  let view, offer, oldToken;
  let config = structuredClone(room.config), changed = false;
  let batch = await room.ctx.storage.get('batch'), batchChanged = false, privateSnippet;
  if (initial) {
    view = { ...initial, ownerId, expires: at + PANEL_TTL };
  } else {
    if (interaction.type !== 3 || !(interaction.message?.flags & 64)) return expired();
    const match = /^claw:([a-f0-9-]{36}):([a-z-]+)$/.exec(interaction.data?.custom_id || '');
    if (!match) return expired();
    oldToken = match[1]; view = views[oldToken];
    if (!view || view.ownerId !== ownerId || view.expires <= at) return expired();
    view = structuredClone(view); offer = view.offers[match[2]];
    if (!offer || offer.type !== interaction.data.component_type) return expired();
    if (offer.type === 3 && (!Array.isArray(interaction.data.values) || interaction.data.values.length !== 1
        || !offer.values.includes(interaction.data.values[0]))) return expired();
    const value = interaction.data.values?.[0];
    view.notice = '';
    if (offer.kind === 'confirm') {
      const change = view.confirm;
      delete view.confirm;
      if (!change || !confirmationFresh(config, change)) view.notice = 'Settings or this character changed. Review the latest information before confirming again.';
      else if (change.kind === 'follow') {
        if (change.enabled && !config.mainId) return expired();
        config.follow = change.enabled; changed = true;
      } else if (change.kind === 'main') {
        if (!config.members[change.account]) return expired();
        config.mainId = change.account; config.follow = false; changed = true;
        view.notice = 'Main selected. Following is paused until you enable it.';
      } else if (change.kind === 'allow' || change.kind === 'prefer') {
        const member = config.members[change.account], card = member?.slots?.[change.slot];
        if (!member || ((change.kind === 'prefer' || change.enabled) && !selectable(card, at))) return expired();
        member.approvedSlots ||= {}; member.preferredSlots ||= {};
        if (change.kind === 'prefer') {
          if (!member.approvedSlots[change.slot] || !['EastLuminant', 'EtreanLuminant'].includes(card.region)) return expired();
          member.preferredSlots[card.region] = change.slot;
        } else if (change.enabled) member.approvedSlots[change.slot] = true;
        else {
          delete member.approvedSlots[change.slot];
          for (const [region, slot] of Object.entries(member.preferredSlots)) if (slot === change.slot) delete member.preferredSlots[region];
        }
        changed = true;
      } else if (change.kind === 'batch-approve') {
        const request = batch?.pending?.[change.requestId];
        if (!batch || batch.id !== change.batchId || batch.expires <= at || !request
            || config.members[request.accountId] || Object.keys(config.members).length >= MAX_MEMBERS) return expired();
        config.members[request.accountId] = { username: request.username, keyHash: request.keyHash, credential: nonce(), slot: null };
        delete batch.pending[request.id]; batchChanged = true; changed = true;
        view.notice = `@${request.username} approved. Its public loader will finish pairing. Characters still need your approval.`;
      } else if (change.kind === 'batch-close') {
        if (!batch || batch.id !== change.batchId) return expired();
        batch = null; batchChanged = true; view.notice = 'Setup closed. Existing paired accounts are unchanged.';
      } else return expired();
      if (changed && !view.notice) view.notice = 'Saved.';
    } else if (offer.kind === 'cancel') delete view.confirm;
    else if (offer.kind === 'refresh') { /* Rendering below reads current state. */ }
    else if (offer.kind === 'page') view.page = offer.page;
    else if (offer.kind === 'home') { view.screen = 'home'; view.page = 0; }
    else if (offer.kind === 'screen') { view.screen = offer.screen; view.page = 0; }
    else if (offer.kind === 'account') {
      if (!config.members[value]) return expired();
      view.account = value; view.screen = 'home';
      view.notice = 'Selected ' + accountName(value, config.members[value]) + '. Use Characters below, or choose Use as main.';
    } else if (offer.kind === 'filter') { view.filter = value; view.page = 0; }
    else if (offer.kind === 'slot') { view.slot = value; view.screen = 'detail'; }
    else if (offer.kind === 'follow') view.confirm = confirmation(config, view, { kind: 'follow', enabled: offer.enabled }, offer.enabled
      ? 'Enable following? Paired alts may immediately join the main using their approved characters.'
      : 'Pause following? A teleport already accepted by Roblox cannot be undone.');
    else if (offer.kind === 'main') view.confirm = confirmation(config, view, { kind: 'main' },
      'Use ' + accountName(view.account, config.members[view.account]) + ' as your main? This pauses following.');
    else if (offer.kind === 'policy') {
      if (!config.members[view.account]?.slots?.[view.slot]) return expired();
      view.confirm = confirmation(config, view, { kind: offer.operation, enabled: offer.enabled }, offer.operation === 'prefer'
        ? `Prefer slot ${view.slot} in its region? This affects the next automatic character selection.`
        : `${offer.enabled ? 'Allow' : 'Disable'} slot ${view.slot}? ${offer.enabled ? 'If following is on, this alt may join immediately.' : 'An already accepted teleport cannot be undone.'}`);
    } else if (offer.kind === 'batch-start') {
      if (batch?.expires > at) { view.screen = 'requests'; view.notice = 'A setup window is already open. Close it first if you need a replacement snippet.'; }
      else {
        if (!/^https:\/\/[a-z0-9.-]+$/i.test(room.env.PUBLIC_ENDPOINT || '')) return reply('The private service address is not configured.');
        const code = nonce().replaceAll('-', '') + nonce().replaceAll('-', '');
        batch = { id: nonce(), codeHash: await hash(code), expires: at + 600, pending: {} }; batchChanged = true;
        config.ownerId = ownerId;
        privateSnippet = `Private alt setup — expires in 10 minutes. Run this ONCE in your shared executor workspace, then run the public loader on your other accounts. Never share this message.\n\n\`\`\`lua\ngetgenv().CLAW_BATCH = {Version=1, Endpoint="${room.env.PUBLIC_ENDPOINT}", OwnerId="${ownerId}", Code="${code}", Expires=${batch.expires}}\nloadstring(game:HttpGet("https://raw.githubusercontent.com/Clawdews/CLAW/control-beta/dist/launcher-beta.lua"))()\n\`\`\`\nClick Refresh below to see requests. Compare each check code with its Roblox console before approving. Existing pairings are left alone.`;
        view.screen = 'requests'; view.page = 0;
      }
    } else if (offer.kind === 'request') {
      const request = batch?.pending?.[value];
      if (!batch || batch.expires <= at || batch.id !== offer.batchId || !request) return expired();
      view.confirm = confirmation(config, view, { kind: 'batch-approve', batchId: batch.id, requestId: request.id },
        `Pair @${request.username}? Check that **${request.check}** is displayed in that account’s Roblox console. Only approve accounts you control. This will not approve any characters.`);
    } else if (offer.kind === 'batch-close') view.confirm = confirmation(config, view, { kind: 'batch-close', batchId: offer.batchId }, 'Close this setup window and discard its pending requests? Existing pairings remain connected.');
    else return expired();
  }
  if (changed) config.revision = nonce();
  const connections = {};
  for (const ws of room.sockets()) { const live = room.live(ws); if (live) connections[live.userId] = live; }
  view.token = nonce();
  const rendered = renderPanel(config, connections, view, at, batch);
  view.offers = rendered.offers;
  if (oldToken) delete views[oldToken];
  while (Object.keys(views).length >= 40) delete views[Object.keys(views)[0]];
  views[view.token] = view;
  // Permission changes, consumed controls and pending requests commit together.
  await room.ctx.storage.put({ panels: views, ...(changed || privateSnippet ? { config } : {}), ...(batchChanged ? { batch } : {}) });
  if (changed || privateSnippet) room.config = config;
  if (changed) room.broadcast(true);
  if (privateSnippet) rendered.data.content = privateSnippet;
  return { type: initial ? 4 : 7, data: { ...rendered.data, ...(initial ? { flags: 64 } : {}) } };
}

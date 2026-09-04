import { LOBBY, FRESH_SECONDS, MAX_MEMBERS, id, snowflake, slotId, now, nonce, hash, sameHash,
  cleanPresence, ticketFor, targetKey, discordSignature, reply } from './protocol.js';
import { DurableObject } from 'cloudflare:workers';
import { loadConfig } from './bootstrap.js';
import { shared, allowedOwner, interactionOwner, roomName, regionForPlace, safeSlot, entryAllowed } from './tenancy.js';
import { pairingReply, setupReply } from './onboarding.js';
import { cleanCatalog, selectable, catalogPage, MAX_SLOTS } from './catalog.js';
import { cleanNickname, statusPage } from './status.js';
import { resolveCommandAccount, resolveAccount, canDeferAccount, finishAccountReply } from './accounts.js';
import { panelCommand } from './panel-controller.js';
import { batchInput, batchRequest } from './batch.js';
import { commandInput, featureCommand } from './feature-commands.js';
import { ensureFeatures, activeFor, addHistory, addLoot } from './features.js';
import { cleanActionResult, cleanInventory, cleanLoot, cleanQueuedAction } from './actions.js';
import { shouldAlert, postAlert } from './alerts.js';

const json = (value, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
async function bodyText(request, limit = 8192) {
  if (Number(request.headers.get('Content-Length')) > limit) throw new Error('body too large');
  const reader = request.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder(); let bytes = 0, text = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > limit) { await reader.cancel(); throw new Error('body too large'); }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}
export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    if (path === '/health' && request.method === 'GET') return json({ service: 'CLAW control', version: '0.3.0-beta.1', shared: shared(env) });
    if (path === '/discord' && request.method === 'POST') {
      let raw;
      try { raw = await bodyText(request, 32768); } catch { return json({ error: 'Invalid body' }, 413); }
      if (!await discordSignature(raw, request.headers.get('X-Signature-Timestamp'),
        request.headers.get('X-Signature-Ed25519'), env.DISCORD_PUBLIC_KEY)) return json({ error: 'Invalid signature' }, 401);
      let interaction;
      try { interaction = JSON.parse(raw); } catch { return json({ error: 'Invalid JSON' }, 400); }
      if (!interaction || typeof interaction !== 'object') return json({ error: 'Invalid interaction' }, 400);
      if (interaction.type === 1) return json({ type: 1 });
      const user = interactionOwner(interaction, env);
      if (!user) {
        return json(reply('This control is restricted. Install the app for yourself or ask the beta host for access.'));
      }
      if (!(interaction.type === 2 && interaction.data?.name === 'claw') && !(shared(env) && interaction.type === 3)) return json(reply('Unsupported command.'));
      if (!await entryAllowed(env, 'command:' + user)) return json(reply('Control is temporarily rate-limited or unavailable. Try again later.'));
      const run = async () => {
        try {
          // Resolve outside the account room so a slow lookup cannot block its sockets.
          const resolved = shared(env) && interaction.type === 2 ? await resolveCommandAccount(interaction) : { interaction };
          if (resolved.error) return reply(resolved.error);
          const result = await env.ROOM.getByName(roomName(env, user)).command(resolved.interaction, Number(request.headers.get('X-Signature-Timestamp')), user);
          if (resolved.username && result.type === 4 && !result.data.embeds) result.data.content = `Account: @${resolved.username} (${resolved.accountId})\n` + result.data.content;
          return result;
        } catch { return reply('Control service unavailable. No success was confirmed; try status before retrying.'); }
      };
      if (shared(env) && canDeferAccount(interaction) && ctx?.waitUntil) {
        ctx.waitUntil(finishAccountReply(interaction, run));
        return json({ type: 5, data: { flags: 64 } });
      }
      return json(await run());
    }
    if (shared(env) && path === '/batch' && request.method === 'POST') {
      const owner = new URL(request.url).searchParams.get('owner');
      if (!allowedOwner(env, owner)) return json({ state: 'unauthorized' }, 401);
      // Batch onboarding is rate limited even in the closed beta.
      try {
        if (!env.ENTRY_LIMITER || !(await env.ENTRY_LIMITER.limit({ key: 'batch:' + owner })).success) return json({ state: 'try-later' }, 429);
        const input = JSON.parse(await bodyText(request));
        if (!batchInput(input)) return json({ state: 'invalid' }, 400);
        const room = env.ROOM.getByName(roomName(env, owner));
        let result = await room.batch(input, owner);
        if (result.state === 'new') {
          const resolved = await resolveAccount('@' + input.username);
          if (resolved.error || resolved.accountId !== input.accountId) return json({ state: 'lookup-failed' }, 400);
          result = await room.batch({ ...input, username: resolved.username }, owner, true);
        }
        const { status, ...body } = result;
        return json(body, status);
      } catch { return json({ state: 'try-later' }, 503); }
    }
    if ((path === '/session' && request.method === 'POST') || (path === '/socket' && request.method === 'GET')) {
      const owner = new URL(request.url).searchParams.get('owner');
      if (shared(env) && !allowedOwner(env, owner)) return json({ error: 'Unauthorized' }, 401);
      if (!await entryAllowed(env, 'client:' + await hash(request.headers.get('CF-Connecting-IP') || 'unknown'))) {
        return json({ error: 'Try later' }, 429);
      }
      return env.ROOM.getByName(roomName(env, owner)).fetch(request);
    }
    return json({ error: 'Not found' }, 404);
  },
};

// Shared mode uses one room per Discord user; legacy mode keeps its existing room.
export class ControlRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.config = ensureFeatures(await loadConfig(this.ctx.storage, shared(this.env) ? {} : this.env));
    });
  }
  sockets() { return this.ctx.getWebSockets(); }
  attachment(ws) { try { return ws.deserializeAttachment(); } catch { return null; } }
  live(ws, at = now()) {
    const a = this.attachment(ws), member = a && this.config.members[a.userId];
    return member && member.credential === a.credential && ws.readyState === 1
      && at - a.seen <= FRESH_SECONDS ? a : null;
  }
  send(ws, value) { try { ws.send(JSON.stringify(value)); } catch { /* Next liveness check expires it. */ } }
  accountName(userId) {
    const member = this.config.members[userId];
    return member?.nickname || (member?.username ? '@' + member.username : 'Account ' + userId);
  }
  notify(text) { return postAlert(this.env, this.config.alerts, text); }
  async markOffline(userId) {
    if (!this.config.members[userId]) return;
    const pending = await this.ctx.storage.get('offline') || {};
    pending[userId] = { due: now() + 15, credential: this.config.members[userId].credential };
    await this.ctx.storage.put('offline', pending);
    await this.ctx.storage.setAlarm(Date.now() + 16000);
  }
  async clearOffline(userId) {
    const pending = await this.ctx.storage.get('offline') || {};
    if (!pending[userId]) return;
    delete pending[userId]; await this.ctx.storage.put('offline', pending);
  }
  async alarm() {
    const at = now(), pending = await this.ctx.storage.get('offline') || {};
    let next = null;
    for (const [account, item] of Object.entries(pending)) {
      const live = Object.values(this.connections()).some(connection => connection.userId === account);
      if (live || this.config.members[account]?.credential !== item.credential) delete pending[account];
      else if (item.due <= at) {
        delete pending[account];
        await addHistory(this, 'offline', this.accountName(account) + ' disconnected', account);
        if (this.config.alerts?.mode !== 'off') await this.notify(this.accountName(account) + ' disconnected.');
      } else next = next === null ? item.due : Math.min(next, item.due);
    }
    await this.ctx.storage.put('offline', pending);
    if (next !== null) await this.ctx.storage.setAlarm(next * 1000 + 1000);
  }
  profile(userId) {
    const member = this.config.members[userId];
    const team = this.config.activeTeam && this.config.teams?.[this.config.activeTeam];
    const teamRecovery = userId !== this.config.mainId && team?.recovery === true && activeFor(this.config, userId);
    return { type: 'profile', accountId: userId, mainId: this.config.mainId,
      role: userId === this.config.mainId ? 'main' : 'alt', slot: member?.slot || null,
      ownerId: this.config.ownerId || null, approvedSlots: member?.approvedSlots || {},
      allowMenuReturn: teamRecovery || member?.allowMenuReturn === true ? true
        : typeof member?.allowMenuReturn === 'boolean' ? false : null,
      preferredSlots: member?.preferredSlots || {}, catalog: Object.values(member?.slots || {}),
      follow: this.config.follow, revision: this.config.revision, retry: member?.retry || null,
      enabled: activeFor(this.config, userId), activeTeam: this.config.activeTeam,
      halted: this.config.halted === true, capabilities: { movement: true, inventory: true, queue: true } };
  }

  connections() {
    const connections = {};
    for (const ws of this.sockets()) { const live = this.live(ws); if (live) connections[live.userId] = live; }
    return connections;
  }
  async queueActions(actions) {
    if (!actions?.length) return;
    const at = now(), queue = await this.ctx.storage.get('actions') || {};
    for (const request of actions) for (const account of request.accounts || []) {
      if (!this.config.members[account]) continue;
      const packet = cleanQueuedAction(request.packet, at);
      if (!packet) continue;
      queue[account] = [...(queue[account] || []).filter(item => cleanQueuedAction(item, at)), packet].slice(-10);
      for (const ws of this.sockets()) if (this.live(ws)?.userId === account) this.send(ws, packet);
    }
    await this.ctx.storage.put('actions', queue);
  }
  async sendPending(ws, userId) {
    const at = now(), queue = await this.ctx.storage.get('actions') || {};
    const pending = (queue[userId] || []).filter(item => cleanQueuedAction(item, at));
    if (pending.length !== (queue[userId] || []).length) {
      queue[userId] = pending; await this.ctx.storage.put('actions', queue);
    }
    for (const packet of pending) this.send(ws, packet);
  }
  target() {
    if (!this.config.follow || !this.config.mainId) return { type: 'target', enabled: false, reason: 'PAUSED' };
    for (const ws of this.sockets()) {
      const a = this.live(ws);
      if (a?.userId !== this.config.mainId || !a.presence || a.presence.placeId === LOBBY) continue;
      return { type: 'target', enabled: true, key: targetKey(a.presence), revision: this.config.revision,
        expiresAt: a.seen + FRESH_SECONDS,
        ticket: ticketFor(this.config.mainId, a.presence, this.config.revision) };
    }
    return { type: 'target', enabled: false, reason: 'WAITING_MAIN' };
  }
  broadcast(profiles = false) {
    const target = this.target();
    for (const ws of this.sockets()) {
      const a = this.live(ws);
      if (!a) continue;
      if (profiles) this.send(ws, this.profile(a.userId));
      this.send(ws, target);
    }
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/session' && request.method === 'POST') {
      if (shared(this.env) && url.searchParams.get('owner') !== this.config.ownerId) return json({ error: 'Unauthorized' }, 401);
      let input;
      try { input = JSON.parse(await bodyText(request)); } catch { return json({ error: 'Invalid input' }, 400); }
      if (!input || !id(input.accountId) || typeof input.key !== 'string' || input.key.length !== 64) return json({ error: 'Unauthorized' }, 401);
      const member = this.config.members[input.accountId];
      if (!member || !sameHash(await hash(input.key), member.keyHash)) return json({ error: 'Unauthorized' }, 401);
      // At most one outstanding, single-use socket ticket per enrolled account.
      const token = nonce();
      await this.ctx.storage.put('ticket:' + input.accountId,
        { hash: await hash(token), expires: now() + 30, credential: member.credential });
      return json({ ticket: input.accountId + '.' + token, expiresIn: 30 });
    }
    if (url.pathname !== '/socket' || request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return json({ error: 'Upgrade required' }, 426);
    if (shared(this.env) && url.searchParams.get('owner') !== this.config.ownerId) return json({ error: 'Unauthorized' }, 401);
    const [userId, token, extra] = (url.searchParams.get('ticket') || '').split('.');
    if (!id(userId) || typeof token !== 'string' || token.length !== 36 || extra) return json({ error: 'Unauthorized' }, 401);
    return this.ctx.blockConcurrencyWhile(async () => {
      const pending = await this.ctx.storage.get('ticket:' + userId), member = this.config.members[userId];
      if (!member || !pending || pending.expires < now() || pending.credential !== member.credential
          || !sameHash(await hash(token), pending.hash)) return json({ error: 'Unauthorized' }, 401);
      await this.ctx.storage.delete('ticket:' + userId);
      // A new connection displaces the old one for that account, not another account.
      for (const ws of this.sockets()) {
        if (this.attachment(ws)?.userId === userId) { try { ws.close(4001, 'Replaced by a new connection'); } catch {} }
      }
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server, [userId]);
      server.serializeAttachment({ userId, credential: member.credential, seen: now(), presence: null, lastMessage: 0,
        lastInventory: 0, lootWindowAt: 0, lootPackets: 0 });
      // The client requests a profile after binding its listeners; do not race that setup.
      return new Response(null, { status: 101, webSocket: client });
    });
  }
  async webSocketMessage(ws, raw) {
    if (ws.readyState !== 1) return;
    const a = this.attachment(ws), member = a && this.config.members[a.userId];
    if (!member || member.credential !== a.credential) return ws.close(4003, 'Enrollment revoked');
    if (typeof raw !== 'string' || raw.length > 65536) return ws.close(1009, 'Message too large');
    let data;
    try { data = JSON.parse(raw); } catch { return ws.close(1008, 'Invalid JSON'); }
    if (!data || typeof data !== 'object') return ws.close(1008, 'Invalid message');
    if (data.type === 'catalog') {
      if (now() - (a.lastCatalog || 0) < 8) return;
      const catalog = cleanCatalog(data, a.userId, now());
      if (!catalog) return ws.close(1008, 'Invalid character catalog');
      if (a.presence && a.presence.placeId !== LOBBY) return ws.close(1008, 'Catalog requires character menu');
      a.lastCatalog = now(); a.seen = now(); ws.serializeAttachment(a);
      let next;
      await this.ctx.storage.transaction(async storage => {
        const current = await storage.get('config');
        if (!current?.members[a.userId] || current.members[a.userId].credential !== a.credential) return;
        next = structuredClone(current);
        const updated = next.members[a.userId];
        updated.catalogState = { complete: catalog.complete, observedAt: catalog.observedAt };
        for (const [slot, card] of Object.entries(catalog.entries)) {
          const previous = updated.slots?.[slot];
          if (previous?.characterName && (previous.characterName !== card.characterName
              || (Number.isInteger(previous.level) && Number.isInteger(card.level) && card.level < previous.level))) {
            if (updated.approvedSlots) delete updated.approvedSlots[slot];
            for (const [region, preferred] of Object.entries(updated.preferredSlots || {})) {
              if (preferred === slot) delete updated.preferredSlots[region];
            }
          }
        }
        // A complete menu snapshot replaces the roster. A partial one may update
        // displayed entries but cannot invent missing characters or approvals.
        updated.slots = catalog.complete ? catalog.entries : { ...updated.slots, ...catalog.entries };
        if (catalog.complete) {
          for (const slot of Object.keys(updated.approvedSlots || {})) {
            if (!updated.slots[slot]) delete updated.approvedSlots[slot];
          }
          for (const [region, slot] of Object.entries(updated.preferredSlots || {})) {
            if (!updated.slots[slot]) delete updated.preferredSlots[region];
          }
        }
        const entries = Object.entries(updated.slots).slice(0, MAX_SLOTS);
        updated.slots = Object.fromEntries(entries);
        await storage.put('config', next);
      });
      if (next) { this.config = next; this.send(ws, this.profile(a.userId)); }
      this.send(ws, this.target()); return;
    }
    if (data.type === 'action-result') {
      const result = cleanActionResult(data, a.userId);
      if (!result) return ws.close(1008, 'Invalid action result');
      const queue = await this.ctx.storage.get('actions') || {};
      const pending = queue[a.userId] || [];
      if (!pending.some(item => item.id === result.id)) return;
      queue[a.userId] = pending.filter(item => item.id !== result.id);
      const next = structuredClone(this.config), updated = next.members[a.userId];
      if (!updated || updated.credential !== a.credential) return;
      updated.lastAction = result;
      await this.ctx.storage.put({ actions: queue, config: next });
      this.config = next;
      await addHistory(this, 'action', (result.ok ? 'Completed: ' : 'Failed: ') + result.message, a.userId);
      return;
    }
    if (data.type === 'inventory') {
      if (now() - (a.lastInventory || 0) < 5) return;
      const inventory = cleanInventory(data, a.userId);
      if (!inventory) return ws.close(1008, 'Invalid inventory');
      a.lastInventory = now(); a.seen = now(); ws.serializeAttachment(a);
      const next = structuredClone(this.config), updated = next.members[a.userId];
      if (!updated || updated.credential !== a.credential) return;
      updated.inventory = inventory;
      await this.ctx.storage.put('config', next); this.config = next;
      return;
    }
    if (data.type === 'loot') {
      const at = now();
      if (at - (a.lootWindowAt || 0) >= 10) { a.lootWindowAt = at; a.lootPackets = 0; }
      a.lootPackets = (a.lootPackets || 0) + 1;
      if (a.lootPackets > 10) return ws.close(1008, 'Loot rate exceeded');
      const items = cleanLoot(data, a.userId);
      if (!items) return ws.close(1008, 'Invalid loot');
      a.seen = at; ws.serializeAttachment(a);
      await addLoot(this, a.userId, items);
      await addHistory(this, 'loot', 'Recorded ' + items.reduce((sum, item) => sum + item.count, 0) + ' new item(s)', a.userId);
      return;
    }
    if (raw.length > 4096) return ws.close(1009, 'Message too large');
    if (data.type === 'hello') {
      if (now() - a.lastMessage < 1) return;
      a.seen = now(); a.lastMessage = now(); ws.serializeAttachment(a);
      // Display-only label from an authenticated client; never used for ownership or routing.
      if (!member.username && typeof data.username === 'string' && /^[A-Za-z0-9_]{1,20}$/.test(data.username)) {
        await this.ctx.blockConcurrencyWhile(async () => {
          const latest = this.config.members[a.userId];
          if (!latest || latest.credential !== a.credential || latest.username) return;
          const next = structuredClone(this.config); next.members[a.userId].username = data.username;
          await this.ctx.storage.put('config', next); this.config = next;
        });
      }
      await this.clearOffline(a.userId);
      this.send(ws, this.profile(a.userId)); this.send(ws, this.target()); await this.sendPending(ws, a.userId); return;
    }
    if (data.type !== 'presence') return ws.close(1008, 'Unsupported message');
    if (now() - a.lastMessage < 2) return;
    const presence = cleanPresence(data.current);
    if (!presence) return ws.close(1008, 'Invalid presence');
    const previousState = a.presence?.state;
    a.presence = presence; a.seen = now(); a.lastMessage = now(); ws.serializeAttachment(a);
    if (previousState && previousState !== presence.state) {
      await addHistory(this, 'state', this.accountName(a.userId) + ': ' + presence.state, a.userId);
      if (shouldAlert(this.config.alerts?.mode, presence.state)) {
        this.ctx.waitUntil(this.notify(this.accountName(a.userId) + ': ' + presence.state));
      }
    }
    // Observations are not permission: newly learned characters stay unapproved.
    const observedRegion = regionForPlace(presence.placeId);
    const previousSlot = safeSlot(presence.slot) && member.slots?.[presence.slot];
    if (presence.placeId !== LOBBY && safeSlot(presence.slot) && (!member.slot || !previousSlot
        || previousSlot.region !== observedRegion || now() - previousSlot.observedAt >= 300)) {
      await this.ctx.blockConcurrencyWhile(async () => {
        const latest = this.config.members[a.userId];
        if (latest && latest.credential === a.credential) {
          const next = structuredClone(this.config), updated = next.members[a.userId];
          if (!updated.slot) updated.slot = presence.slot;
          updated.slots ||= {};
          if (Object.hasOwn(updated.slots, presence.slot) || Object.keys(updated.slots).length < MAX_SLOTS) {
            updated.slots[presence.slot] = { ...updated.slots[presence.slot], slot: presence.slot, region: observedRegion,
              observedAt: now(), confirmed: true, source: 'character-place' };
          }
          await this.ctx.storage.put('config', next); this.config = next;
        }
      });
      this.send(ws, this.profile(a.userId));
    }
    if (a.userId === this.config.mainId) this.broadcast();
    else this.send(ws, this.target());
  }
  async webSocketClose(ws, code) {
    const userId = this.attachment(ws)?.userId;
    try { ws.close(code === 1006 ? 1000 : code, 'Closed'); } catch {}
    if (userId && code !== 4001 && code !== 4003) await this.markOffline(userId);
    this.broadcast();
  }
  async webSocketError(ws) {
    const userId = this.attachment(ws)?.userId;
    try { ws.close(1011, 'Connection error'); } catch {}
    if (userId) await this.markOffline(userId);
    this.broadcast();
  }
  async batch(input, ownerId, register = false) {
    return this.ctx.blockConcurrencyWhile(() => batchRequest(this, input, ownerId, register));
  }
  async command(interaction, signedAt, ownerId) {
    return this.ctx.blockConcurrencyWhile(async () => {
      if (shared(this.env) && (!snowflake(ownerId) || interactionOwner(interaction, this.env) !== ownerId
          || (this.config.ownerId && this.config.ownerId !== ownerId))) return reply('Not authorized for this account group.');
      if (shared(this.env) && interaction.type === 3) return panelCommand(this, interaction, ownerId);
      const config = structuredClone(this.config);
      if (shared(this.env)) config.ownerId = ownerId;
      const parsed = commandInput(interaction);
      const option = { name: parsed.name };
      const values = parsed.values;
      const account = values.account;
      if (shared(this.env) && ['panel', 'setup', 'slots'].includes(option?.name)) {
        if (option.name === 'slots' && !config.members[account]) return reply('Enroll that account first.');
        return panelCommand(this, interaction, ownerId, { screen: option.name === 'slots' ? 'slots' : option.name === 'setup' ? 'setup' : 'home',
          account: account || config.mainId, page: Math.max(0, (values.page || 1) - 1) });
      }
      if (['enroll', 'rotate', 'main', 'slot', 'slots', 'allow-slot', 'prefer-slot', 'auto-return', 'nickname', 'retry', 'revoke'].includes(option?.name) && !id(account)) {
        return reply('Account must be a numeric Roblox UserId.');
      }
      const replay = (await this.ctx.storage.get('replay') || []).filter(item => item.expires >= now());
      if (replay.some(item => item.id === interaction.id)) return reply('This command was already processed. Use /claw status to check the current state.');
      if (option?.name === 'setup') return reply(setupReply);
      if (option?.name === 'slots') {
        const member = config.members[account];
        if (!member) return reply('Enroll that account first.');
        return reply((`Characters for ${account}\n` + catalogPage(member, now(), values.page ?? 1)).slice(0, 1950));
      }
      if (option?.name === 'status') {
        const connections = this.connections();
        return reply(statusPage(this.config, connections, now(), values.page ?? 1));
      }
      let content, disconnectAccount;
      if (replay.length >= 1000) return reply('Too many recent commands. Wait a few minutes.');
      const feature = await featureCommand(this, option.name, values, interaction, config, this.connections());
      if (feature.handled) {
        if (!feature.changed && !feature.actions?.length) return reply(feature.content);
        if (feature.changed) config.revision = nonce();
        replay.push({ id: interaction.id, expires: signedAt + 301 });
        await this.ctx.storage.put({ config, replay });
        this.config = config;
        if (feature.actions?.length) await this.queueActions(feature.actions);
        if (feature.event) await addHistory(this, 'command', feature.event);
        if (feature.changed) this.broadcast(true);
        return reply(feature.content);
      }
      if (option?.name === 'enroll' || option?.name === 'rotate') {
        if (shared(this.env) && option.name === 'enroll' && config.members[account]) return reply('Already paired. Use /claw rotate only if you need a replacement key.');
        if (option.name === 'rotate' && !config.members[account]) return reply('Enroll that account first.');
        if (!id(account)) return reply('Account must be a numeric Roblox UserId, not a display name.');
        if (!config.members[account] && Object.keys(config.members).length >= MAX_MEMBERS) return reply('Member limit reached.');
        const key = nonce().replaceAll('-', '') + nonce().replaceAll('-', '');
        config.members[account] = { ...config.members[account], keyHash: await hash(key), credential: nonce(), slot: config.members[account]?.slot || null };
        if (interaction.accountUsername) config.members[account].username = interaction.accountUsername;
        content = shared(this.env) ? pairingReply(this.env.PUBLIC_ENDPOINT, ownerId, account, key)
          : `Paired Roblox account ${account}. Save this privately in its autoexec config. Re-enrolling rotates the key.\n\nKey: ||${key}||\nNever put it in GitHub or a public message.`;
        disconnectAccount = account;
      } else if (option?.name === 'main') {
        if (!config.members[account]) return reply('Enroll that numeric Roblox UserId first.');
        config.mainId = account; config.follow = false; config.activeTeam = null;
        content = `Main set to ${account}. Follow is paused; enable it when the accounts are ready.`;
      } else if (option?.name === 'follow') {
        if (typeof values.enabled !== 'boolean') return reply('Specify enabled true or false.');
        if (values.enabled && !config.mainId) return reply('Choose an enrolled main first.');
        config.follow = values.enabled;
        content = values.enabled ? 'Auto-follow enabled. Fresh main destinations will be delivered to paired alts.'
          : 'Auto-follow paused. A teleport already accepted by Roblox cannot be undone.';
      } else if (option?.name === 'slot') {
        if (shared(this.env)) return reply('Use /claw slots and /claw allow-slot to approve observed characters.');
        if (!config.members[account] || !slotId(values.value)) return reply('Provide an enrolled account and its actual DataSlot string.');
        config.members[account].slot = values.value;
        content = `Saved the character slot for ${account}.`;
      } else if (option?.name === 'allow-slot') {
        const member = config.members[account], slot = values.slot;
        if (!member || !safeSlot(slot) || typeof values.enabled !== 'boolean') return reply('Provide an enrolled account, actual slot and enabled true/false.');
        if (values.enabled && !selectable(member.slots?.[slot], now())) return reply('Refresh that character in the menu with the paired loader, or load it once, before approving it.');
        member.approvedSlots ||= {};
        if (values.enabled) member.approvedSlots[slot] = true;
        else {
          delete member.approvedSlots[slot];
          for (const [region, preferred] of Object.entries(member.preferredSlots || {})) if (preferred === slot) delete member.preferredSlots[region];
        }
        content = `Slot ${slot} ${values.enabled ? 'approved' : 'disabled'} for ${account}.`;
      } else if (option?.name === 'prefer-slot') {
        const member = config.members[account], slot = values.slot, region = values.region;
        if (!member || !safeSlot(slot) || !['EastLuminant', 'EtreanLuminant'].includes(region)
            || member.approvedSlots?.[slot] !== true || member.slots?.[slot]?.region !== region
            || !selectable(member.slots?.[slot], now())) return reply('Choose an approved, observed slot in that region.');
        member.preferredSlots ||= {}; member.preferredSlots[region] = slot;
        content = `Preferred ${region} character for ${account}: ${slot}.`;
      } else if (option?.name === 'auto-return') {
        if (!config.members[account] || typeof values.enabled !== 'boolean') return reply('Choose an enrolled account and enabled true/false.');
        config.members[account].allowMenuReturn = values.enabled;
        content = values.enabled ? `Automatic menu return enabled for ${account}. It uses the normal game menu flow, not forced respawn or combat bypass. A valid main and approved character are still required.`
          : `Automatic menu return disabled for ${account}. Pending menu confirmations stop when the client receives this update. A teleport already accepted by Roblox cannot be undone.`;
      } else if (option?.name === 'nickname') {
        const nickname = cleanNickname(values.label);
        if (!config.members[account] || !nickname) return reply('Choose an enrolled account and a nickname of 1–32 UTF-8 bytes, without control characters.');
        config.members[account].nickname = nickname;
        content = `Saved the display nickname for ${account}. Account identity and permissions are unchanged.`;
      } else if (option?.name === 'revoke') {
        if (!config.members[account]) return reply('Account is not enrolled.');
        delete config.members[account]; await this.ctx.storage.delete('ticket:' + account);
        for (const team of Object.values(config.teams || {})) {
          team.members = (team.members || []).filter(value => value !== account);
          if (team.mainId === account) team.mainId = null;
        }
        if (config.mainId === account) { config.mainId = null; config.follow = false; }
        disconnectAccount = account;
        content = `Revoked ${account}.`;
      } else if (option?.name === 'retry') {
        if (!config.members[account]) return reply('Specify one enrolled account to retry.');
        const retry = nonce();
        config.members[account].retry = retry;
        content = `One retry authorized for ${account}; it still needs a fresh main destination.`;
      } else return reply('Unknown command.');
      config.revision = nonce();
      // Keep the complete accepted-signature replay window, capped by a command limit.
      replay.push({ id: interaction.id, expires: signedAt + 301 });
      await this.ctx.storage.put({ config, replay });
      this.config = config;
      if (disconnectAccount) for (const ws of this.sockets()) if (this.attachment(ws)?.userId === disconnectAccount) { try { ws.close(4003, 'Pairing changed'); } catch {} }
      this.broadcast(true);
      return reply(content);
    });
  }
}

import { LOBBY, FRESH_SECONDS, MAX_MEMBERS, id, snowflake, slotId, now, nonce, hash, sameHash,
  cleanPresence, ticketFor, targetKey, discordSignature, reply } from './protocol.js';
import { DurableObject } from 'cloudflare:workers';

const json = (value, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
async function bodyText(request) {
  if (Number(request.headers.get('Content-Length')) > 8192) throw new Error('body too large');
  const reader = request.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder(); let bytes = 0, text = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > 8192) { await reader.cancel(); throw new Error('body too large'); }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}
export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/health' && request.method === 'GET') return json({ service: 'CLAW control', version: '0.1.0' });
    if (path === '/discord' && request.method === 'POST') {
      let raw;
      try { raw = await bodyText(request); } catch { return json({ error: 'Invalid body' }, 413); }
      if (!await discordSignature(raw, request.headers.get('X-Signature-Timestamp'),
        request.headers.get('X-Signature-Ed25519'), env.DISCORD_PUBLIC_KEY)) return json({ error: 'Invalid signature' }, 401);
      let interaction;
      try { interaction = JSON.parse(raw); } catch { return json({ error: 'Invalid JSON' }, 400); }
      if (!interaction || typeof interaction !== 'object') return json({ error: 'Invalid interaction' }, 400);
      if (interaction.type === 1) return json({ type: 1 });
      const user = interaction.member?.user?.id || interaction.user?.id;
      if (!snowflake(env.DISCORD_OWNER_ID) || !snowflake(env.DISCORD_GUILD_ID) || !snowflake(interaction.id)
          || user !== env.DISCORD_OWNER_ID || interaction.guild_id !== env.DISCORD_GUILD_ID) {
        return json(reply('This control is restricted to its owner in the configured server.'));
      }
      if (interaction.type !== 2 || interaction.data?.name !== 'claw') return json(reply('Unsupported command.'));
      try { return json(await env.ROOM.getByName('claw').command(interaction, Number(request.headers.get('X-Signature-Timestamp')))); }
      catch { return json(reply('Control service unavailable. No success was confirmed; try status before retrying.')); }
    }
    if ((path === '/session' && request.method === 'POST') || (path === '/socket' && request.method === 'GET')) {
      return env.ROOM.getByName('claw').fetch(request);
    }
    return json({ error: 'Not found' }, 404);
  },
};

// One room per deployment. Hibernatable sockets avoid an always-running process.
export class ControlRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.config = await ctx.storage.get('config') || { mainId: null, follow: false, revision: nonce(), members: {} };
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
  profile(userId) {
    const member = this.config.members[userId];
    return { type: 'profile', accountId: userId, mainId: this.config.mainId,
      role: userId === this.config.mainId ? 'main' : 'alt', slot: member?.slot || null,
      follow: this.config.follow, revision: this.config.revision, retry: member?.retry || null };
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
      server.serializeAttachment({ userId, credential: member.credential, seen: now(), presence: null, lastMessage: 0 });
      // The client requests a profile after binding its listeners; do not race that setup.
      return new Response(null, { status: 101, webSocket: client });
    });
  }
  async webSocketMessage(ws, raw) {
    if (ws.readyState !== 1) return;
    const a = this.attachment(ws), member = a && this.config.members[a.userId];
    if (!member || member.credential !== a.credential) return ws.close(4003, 'Enrollment revoked');
    if (typeof raw !== 'string' || raw.length > 4096) return ws.close(1009, 'Message too large');
    let data;
    try { data = JSON.parse(raw); } catch { return ws.close(1008, 'Invalid JSON'); }
    if (!data || typeof data !== 'object') return ws.close(1008, 'Invalid message');
    if (data.type === 'hello') {
      if (now() - a.lastMessage < 1) return;
      a.seen = now(); a.lastMessage = now(); ws.serializeAttachment(a);
      this.send(ws, this.profile(a.userId)); this.send(ws, this.target()); return;
    }
    if (data.type !== 'presence') return ws.close(1008, 'Unsupported message');
    if (now() - a.lastMessage < 2) return;
    const presence = cleanPresence(data.current);
    if (!presence) return ws.close(1008, 'Invalid presence');
    a.presence = presence; a.seen = now(); a.lastMessage = now(); ws.serializeAttachment(a);
    // Learn a real DataSlot once from a running character. Never guess a slot number.
    if (!member.slot && presence.slot && presence.placeId !== LOBBY) {
      await this.ctx.blockConcurrencyWhile(async () => {
        const latest = this.config.members[a.userId];
        if (latest && latest.credential === a.credential && !latest.slot) {
          latest.slot = presence.slot; await this.ctx.storage.put('config', this.config);
        }
      });
      this.send(ws, this.profile(a.userId));
    }
    if (a.userId === this.config.mainId) this.broadcast();
    else this.send(ws, this.target());
  }
  webSocketClose(ws, code) { try { ws.close(code === 1006 ? 1000 : code, 'Closed'); } catch {} this.broadcast(); }
  webSocketError(ws) { try { ws.close(1011, 'Connection error'); } catch {} this.broadcast(); }
  async command(interaction, signedAt) {
    return this.ctx.blockConcurrencyWhile(async () => {
      const option = interaction.data.options?.[0];
      const values = Object.fromEntries((option?.options || []).map(o => [o.name, o.value]));
      const account = values.account;
      if (['enroll', 'main', 'slot', 'retry', 'revoke'].includes(option?.name) && !id(account)) {
        return reply('Account must be a numeric Roblox UserId.');
      }
      const replay = (await this.ctx.storage.get('replay') || []).filter(item => item.expires >= now());
      if (replay.some(item => item.id === interaction.id)) return reply('This command was already processed. Use /claw status to check the current state.');
      if (option?.name === 'status') {
        const lines = [`Follow: ${this.config.follow ? 'ON' : 'OFF'} | Main: ${this.config.mainId || 'not selected'}`];
        for (const [userId, member] of Object.entries(this.config.members)) {
          const live = this.sockets().map(ws => this.live(ws)).find(a => a?.userId === userId);
          lines.push(`${userId}: ${live?.presence?.state || (live ? 'CONNECTING' : 'OFFLINE')} | slot ${member.slot ? 'saved' : 'not learned'}`);
        }
        lines.push('Verified statuses are reported by your paired client, not independently observed by Discord.');
        return reply(lines.join('\n').slice(0, 1900));
      }
      let content;
      if (replay.length >= 1000) return reply('Too many recent commands. Wait a few minutes.');
      if (option?.name === 'enroll') {
        if (!id(account)) return reply('Account must be a numeric Roblox UserId, not a display name.');
        if (!this.config.members[account] && Object.keys(this.config.members).length >= MAX_MEMBERS) return reply('Member limit reached.');
        const key = nonce().replaceAll('-', '') + nonce().replaceAll('-', '');
        this.config.members[account] = { keyHash: await hash(key), credential: nonce(), slot: this.config.members[account]?.slot || null };
        content = `Paired Roblox account ${account}. Save this privately in its autoexec config. Re-enrolling rotates the key.\n\nKey: ||${key}||\nNever put it in GitHub or a public message.`;
        for (const ws of this.sockets()) if (this.attachment(ws)?.userId === account) { try { ws.close(4003, 'Key rotated'); } catch {} }
      } else if (option?.name === 'main') {
        if (!this.config.members[account]) return reply('Enroll that numeric Roblox UserId first.');
        this.config.mainId = account; this.config.follow = false;
        content = `Main set to ${account}. Follow is paused; enable it when the accounts are ready.`;
      } else if (option?.name === 'follow') {
        if (typeof values.enabled !== 'boolean') return reply('Specify enabled true or false.');
        if (values.enabled && !this.config.mainId) return reply('Choose an enrolled main first.');
        this.config.follow = values.enabled;
        content = values.enabled ? 'Auto-follow enabled. Fresh main destinations will be delivered to paired alts.'
          : 'Auto-follow paused. A teleport already accepted by Roblox cannot be undone.';
      } else if (option?.name === 'slot') {
        if (!this.config.members[account] || !slotId(values.value)) return reply('Provide an enrolled account and its actual DataSlot string.');
        this.config.members[account].slot = values.value;
        content = `Saved the character slot for ${account}.`;
      } else if (option?.name === 'revoke') {
        if (!this.config.members[account]) return reply('Account is not enrolled.');
        delete this.config.members[account]; await this.ctx.storage.delete('ticket:' + account);
        if (this.config.mainId === account) { this.config.mainId = null; this.config.follow = false; }
        for (const ws of this.sockets()) if (this.attachment(ws)?.userId === account) { try { ws.close(4003, 'Revoked'); } catch {} }
        content = `Revoked ${account}.`;
      } else if (option?.name === 'retry') {
        if (!this.config.members[account]) return reply('Specify one enrolled account to retry.');
        const retry = nonce();
        this.config.members[account].retry = retry;
        content = `One retry authorized for ${account}; it still needs a fresh main destination.`;
      } else return reply('Unknown command.');
      this.config.revision = nonce();
      // Keep the complete accepted-signature replay window, capped by a command limit.
      replay.push({ id: interaction.id, expires: signedAt + 301 });
      await this.ctx.storage.put({ config: this.config, replay });
      this.broadcast(true);
      return reply(content);
    });
  }
}

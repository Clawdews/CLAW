import { id, snowflake, reply } from './protocol.js';

const accountCommands = new Set(['enroll', 'rotate', 'main', 'slot', 'slots', 'allow-slot', 'prefer-slot', 'auto-return', 'nickname', 'retry', 'revoke']);
const usernamePattern = /^[A-Za-z0-9_]{1,20}$/;
const unavailable = 'Roblox username lookup is unavailable. No changes made. Please try again in a moment.';
const invalid = 'Enter the Roblox username, not its display name. Numeric UserIds also work.';
export const LOOKUP_TIMEOUT_MS = 8000;

export async function resolveAccount(value, fetcher = fetch) {
  if (typeof value !== 'string' || value.length > 64) return { error: invalid };
  const input = value.trim();
  if (id(input)) return { accountId: input };
  const username = input.startsWith('@') ? input.slice(1) : input;
  if (!usernamePattern.test(username) || (!input.startsWith('@') && /^\d+$/.test(input))) return { error: invalid };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LOOKUP_TIMEOUT_MS);
  let reader;
  try {
    // Only the name goes to Roblox; no Discord identifiers, cookies or pairing keys.
    let response;
    for (let attempt = 0; attempt < 2; attempt++) {
      response = await fetcher('https://users.roblox.com/v1/usernames/users', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, redirect: 'manual',
        body: JSON.stringify({ usernames: [username], excludeBannedUsers: false }), signal: controller.signal,
      });
      if (attempt || (response.status !== 429 && response.status < 500)) break;
      const retryAfter = response.headers.get('Retry-After');
      const pause = retryAfter === null ? 250 : Number(retryAfter) * 1000;
      if (!Number.isFinite(pause) || pause < 0 || pause > 1000) break;
      await response.body?.cancel();
      await new Promise(resolve => setTimeout(resolve, Math.max(250, pause)));
      if (controller.signal.aborted) return { error: unavailable };
    }
    if (!response.ok || Number(response.headers.get('Content-Length')) > 8192) return { error: unavailable };
    reader = response.body?.getReader();
    if (!reader) return { error: unavailable };
    const decoder = new TextDecoder(); let bytes = 0, text = '';
    while (true) {
      const { value: chunk, done } = await reader.read();
      if (done) break;
      bytes += chunk.byteLength;
      if (bytes > 8192) return { error: unavailable };
      text += decoder.decode(chunk, { stream: true });
    }
    if (controller.signal.aborted) return { error: unavailable };
    const data = JSON.parse(text + decoder.decode())?.data;
    if (!Array.isArray(data)) return { error: unavailable };
    if (!data.length) return { error: 'No account found with that username. Check the spelling and use its current Roblox username, not its display name.' };
    if (data.length !== 1) return { error: unavailable };
    const user = data[0];
    if (!user || !Number.isSafeInteger(user.id) || !id(String(user.id)) || typeof user.name !== 'string'
        || !usernamePattern.test(user.name) || typeof user.requestedUsername !== 'string'
        || user.requestedUsername.toLowerCase() !== username.toLowerCase()) return { error: unavailable };
    // Roblox also searches former names. Never silently select a renamed account.
    if (user.name.toLowerCase() !== username.toLowerCase()) return { error: 'That is a former username. Use the account’s current Roblox username. No changes made.' };
    return { accountId: String(user.id), username: user.name };
  } catch { return { error: unavailable }; }
  finally {
    clearTimeout(timer); controller.abort();
    if (reader) { try { await reader.cancel(); } catch { /* The fetch may already be aborted. */ } }
  }
}

export function canDeferAccount(interaction) {
  const options = interaction.data?.options;
  if (!Array.isArray(options) || options.length !== 1) return false;
  const option = options[0];
  const accounts = Array.isArray(option?.options) ? option.options.filter(value => value?.name === 'account') : [];
  if (accounts.length !== 1) return false;
  const account = accounts[0].value;
  return interaction.type === 2 && accountCommands.has(option?.name)
    && typeof account === 'string' && !id(account.trim())
    && snowflake(interaction.application_id) && typeof interaction.token === 'string'
    && /^[A-Za-z0-9._-]{20,2048}$/.test(interaction.token);
}

export async function finishAccountReply(interaction, work, fetcher = fetch) {
  if (!canDeferAccount(interaction)) return false;
  let result;
  try { result = await work(); }
  catch { result = reply('Control service unavailable. Check /claw status before trying again.'); }
  if (result?.type !== 4 || !result.data) return false;
  const { flags, ...data } = result.data;
  // Edit only the private response already acknowledged for this signed interaction.
  const url = `https://discord.com/api/v10/webhooks/${interaction.application_id}/${encodeURIComponent(interaction.token)}/messages/@original`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await fetcher(url, { method: 'PATCH', redirect: 'manual',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data), signal: AbortSignal.timeout(4000) });
      const status = response.status;
      const retryAfter = response.headers.get('Retry-After');
      await response.body?.cancel();
      if (response.ok) return true;
      if (status !== 404 && status !== 429 && status < 500) return false;
      if (retryAfter !== null && (!Number.isFinite(Number(retryAfter)) || Number(retryAfter) > 1)) return false;
    } catch { /* No tokens, pairing replies or upstream error bodies go to logs. */ }
    if (!attempt) await new Promise(resolve => setTimeout(resolve, 1000));
  }
  return false;
}

export async function resolveCommandAccount(interaction, fetcher = fetch) {
  const options = interaction.data?.options;
  if (!Array.isArray(options) || options.length !== 1 || !accountCommands.has(options[0]?.name)) return { interaction };
  const values = options[0].options;
  const accounts = Array.isArray(values) ? values.filter(o => o?.name === 'account') : [];
  if (accounts.length !== 1) return { error: invalid };
  const resolved = await resolveAccount(accounts[0].value, fetcher);
  if (resolved.error) return resolved;
  const normalized = structuredClone(interaction);
  normalized.data.options[0].options.find(o => o.name === 'account').value = resolved.accountId;
  if (resolved.username) normalized.accountUsername = resolved.username;
  return { ...resolved, interaction: normalized };
}

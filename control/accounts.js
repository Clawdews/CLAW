import { id } from './protocol.js';

const accountCommands = new Set(['enroll', 'rotate', 'main', 'slot', 'slots', 'allow-slot', 'prefer-slot', 'auto-return', 'nickname', 'retry', 'revoke']);
const usernamePattern = /^[A-Za-z0-9_]{1,20}$/;
const unavailable = 'Roblox username lookup is unavailable. No changes made. Try again, or use the numeric UserId.';
const invalid = 'Enter the Roblox username, not its display name. Numeric UserIds also work.';
export const LOOKUP_TIMEOUT_MS = 1200;

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
    const response = await fetcher('https://users.roblox.com/v1/usernames/users', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, redirect: 'manual',
      body: JSON.stringify({ usernames: [username], excludeBannedUsers: false }), signal: controller.signal,
    });
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

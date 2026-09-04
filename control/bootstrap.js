import { id, snowflake, MAX_MEMBERS, nonce } from './protocol.js';

// Deployment-only setup. No HTTP request can supply this binding.
function initialConfig(raw, owner, guild) {
  const invalid = () => { throw new Error('Invalid INITIAL_PAIRING configuration'); };
  if (typeof raw !== 'string' || raw.length > 12000) return invalid();
  let seed;
  try { seed = JSON.parse(raw); } catch { return invalid(); }
  if (!seed || seed.version !== 1 || !snowflake(owner) || !snowflake(guild)
      || seed.ownerId !== owner || seed.guildId !== guild || !id(seed.mainId)
      || typeof seed.follow !== 'boolean' || !Array.isArray(seed.members)
      || seed.members.length < 1 || seed.members.length > MAX_MEMBERS) return invalid();
  const members = {}, hashes = new Set();
  for (const member of seed.members) {
    if (!member || !id(member.accountId) || typeof member.keyHash !== 'string'
        || !/^[a-f0-9]{64}$/.test(member.keyHash) || members[member.accountId]
        || hashes.has(member.keyHash)) return invalid();
    members[member.accountId] = { keyHash: member.keyHash, credential: nonce(), slot: null };
    hashes.add(member.keyHash);
  }
  if (!members[seed.mainId]) return invalid();
  return { mainId: seed.mainId, follow: seed.follow, revision: nonce(), members };
}

export async function loadConfig(storage, env) {
  const saved = await storage.get('config');
  // Even an empty roster is deliberate persisted state; never resurrect revoked keys.
  if (saved !== undefined) return saved;
  if (env.INITIAL_PAIRING === undefined) return { mainId: null, follow: false, revision: nonce(), members: {} };
  const config = initialConfig(env.INITIAL_PAIRING, env.DISCORD_OWNER_ID, env.DISCORD_GUILD_ID);
  await storage.put('config', config);
  return config;
}

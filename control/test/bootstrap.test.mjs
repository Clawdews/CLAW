import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../bootstrap.js';

const owner = '123456789012345678', guild = '234567890123456789';
const seed = () => ({ version: 1, ownerId: owner, guildId: guild, mainId: '11', follow: true,
  members: [{ accountId: '11', keyHash: 'a'.repeat(64) }, { accountId: '22', keyHash: 'b'.repeat(64) }] });
const env = value => ({ DISCORD_OWNER_ID: owner, DISCORD_GUILD_ID: guild, INITIAL_PAIRING: JSON.stringify(value) });
function storage(initial) {
  let saved = initial;
  return { writes: 0, async get(key) { assert.equal(key, 'config'); return structuredClone(saved); },
    async put(key, value) { assert.equal(key, 'config'); saved = structuredClone(value); this.writes++; } };
}

test('without a seed normal Discord enrollment still starts empty', async () => {
  const db = storage(), config = await loadConfig(db, {});
  assert.equal(config.follow, false); assert.equal(config.mainId, null);
  assert.deepEqual(config.members, {}); assert.equal(db.writes, 0);
});
test('seed persists hashes and roles, but never guesses character slots', async () => {
  const db = storage(), config = await loadConfig(db, env(seed()));
  assert.equal(db.writes, 1); assert.deepEqual(await db.get('config'), config);
  assert.equal(config.mainId, '11'); assert.equal(config.follow, true);
  assert.equal(config.members['22'].slot, null);
  assert.notEqual(config.members['11'].credential, config.members['22'].credential);
});
test('restart survives removing the deployment binding and cannot overwrite keys', async () => {
  const db = storage(), first = await loadConfig(db, env(seed()));
  assert.deepEqual(await loadConfig(db, {}), first);
  assert.deepEqual(await loadConfig(db, { INITIAL_PAIRING: 'invalid replacement' }), first);
  assert.equal(db.writes, 1);
});
test('empty persisted roster cannot resurrect revoked accounts', async () => {
  const revoked = { mainId: null, follow: false, revision: 'revoked', members: {} };
  const db = storage(revoked);
  assert.deepEqual(await loadConfig(db, env(seed())), revoked); assert.equal(db.writes, 0);
});
test('invalid seed fails closed without writing or echoing its contents', async () => {
  const cases = [null, {}, { ...seed(), version: 2 }, { ...seed(), ownerId: guild },
    { ...seed(), guildId: owner }, { ...seed(), mainId: '33' }, { ...seed(), follow: 'true' },
    { ...seed(), members: [] }, { ...seed(), members: Array(31).fill(seed().members[0]) },
    { ...seed(), members: [seed().members[0], seed().members[0]] },
    { ...seed(), members: [seed().members[0], { accountId: '22', keyHash: 'a'.repeat(64) }] },
    { ...seed(), members: [{ accountId: '__proto__', keyHash: 'a'.repeat(64) }] },
    { ...seed(), members: [{ accountId: '11', keyHash: 'secret-key-do-not-echo' }] }];
  for (const value of cases) {
    const db = storage();
    await assert.rejects(loadConfig(db, env(value)), { message: 'Invalid INITIAL_PAIRING configuration' });
    assert.equal(db.writes, 0);
  }
  await assert.rejects(loadConfig(storage(), { ...env(seed()), INITIAL_PAIRING: '{secret' }), /Invalid INITIAL_PAIRING/);
  await assert.rejects(loadConfig(storage(), { ...env(seed()), INITIAL_PAIRING: 'x'.repeat(12001) }), /Invalid INITIAL_PAIRING/);
});
test('storage failure does not return an unpersisted successful pairing', async () => {
  await assert.rejects(loadConfig({ get: async () => undefined, put: async () => { throw new Error('write failed'); } },
    env(seed())), /write failed/);
});

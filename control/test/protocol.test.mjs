import test from 'node:test';
import assert from 'node:assert/strict';
import { id, snowflake, cleanPresence, discordSignature, hash, sameHash, ticketFor } from '../protocol.js';
test('Roblox IDs and Discord snowflakes are not confused', () => {
  assert.ok(id('12345678')); assert.ok(!id('claw')); assert.ok(!id('9007199254740992'));
  assert.ok(snowflake('123456789012345678')); assert.ok(!snowflake('12345678'));
});
test('presence strips unsupported fields and rejects invalid destinations', () => {
  assert.equal(cleanPresence({ placeId: 1 }), null);
  assert.deepEqual(cleanPresence({ gameId: 9, placeId: 8, jobId: 'job-1', cookie: 'do-not-store' }),
    { gameId: 9, placeId: 8, jobId: 'job-1', slot: null, state: 'ONLINE' });
});
test('pairing hashes are stable and compared without accepting malformed values', async () => {
  const a = await hash('a'), b = await hash('b');
  assert.ok(sameHash(a, a)); assert.ok(!sameHash(a, b)); assert.ok(!sameHash('', ''));
});
test('Discord signatures reject forgery and expired signed requests', async () => {
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const at = 2000000000, body = '{"type":1}', timestamp = String(at);
  const signature = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey,
    new TextEncoder().encode(timestamp + body))).toString('hex');
  assert.ok(await discordSignature(body, timestamp, signature, publicKey, at));
  assert.ok(!await discordSignature(body + ' ', timestamp, signature, publicKey, at));
  assert.ok(!await discordSignature(body, timestamp, signature, publicKey, at + 301));
});
test('join tickets retain the main identity and exact destination', () => {
  const ticket = ticketFor('11', { gameId: 9, placeId: 8, jobId: 'job-1' }, 'revision-1', 2000000000);
  assert.equal(ticket.controllerId, 11); assert.equal(ticket.jobId, ticket.joinId);
  assert.equal(ticket.nonce, 'revision-1');
});

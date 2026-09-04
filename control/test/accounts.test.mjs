import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveAccount, resolveCommandAccount, LOOKUP_TIMEOUT_MS } from '../accounts.js';
import { command, sharedCommand } from '../commands.js';

const user = { id: 11, name: 'Nova_One', requestedUsername: 'nova_one', displayName: 'NotTheUsername' };
const lookup = data => async () => Response.json({ data });
const forbiddenFetch = async () => { assert.fail('Unexpected username lookup'); };

test('numeric IDs work without Roblox lookup; username settings do not alter legacy commands', async () => {
  assert.deepEqual(await resolveAccount(' 11 ', forbiddenFetch), { accountId: '11' });
  for (const option of sharedCommand.options) for (const field of option.options || []) {
    if (field.name === 'account') { assert.match(field.description, /username/); assert.equal(field.max_length, 64); }
  }
  assert.equal(command.options.find(o => o.name === 'main').options[0].description, 'Numeric Roblox UserId');
});
test('exact case-insensitive usernames and optional @ resolve without sending credentials', async () => {
  for (const input of ['nova_one', ' @NoVa_OnE ']) {
    const result = await resolveAccount(input, async (url, options) => {
      assert.equal(url, 'https://users.roblox.com/v1/usernames/users');
      assert.equal(options.method, 'POST'); assert.equal(options.redirect, 'manual');
      assert.deepEqual(options.headers, { 'Content-Type': 'application/json' });
      assert.deepEqual(JSON.parse(options.body), { usernames: [input.trim().replace(/^@/, '')], excludeBannedUsers: false });
      assert.ok(options.signal);
      return Response.json({ data: [user] });
    });
    assert.deepEqual(result, { accountId: '11', username: 'Nova_One' });
  }
  assert.equal((await resolveAccount('@123', lookup([{ id: 44, name: '123', requestedUsername: '123' }]))).accountId, '44');
});
test('invalid inputs never trigger a lookup', async () => {
  for (const input of [null, 11, {}, '', ' ', '@', '@@name', 'a b', 'a\nb', 'a'.repeat(21), '<@123>', 'https://example.com', '9007199254740992', '0', '0011']) {
    assert.ok((await resolveAccount(input, forbiddenFetch)).error);
  }
});
test('missing, former, mismatched and ambiguous names never select an account', async () => {
  assert.match((await resolveAccount('nova_one', lookup([]))).error, /No account found/);
  assert.match((await resolveAccount('nova_one', lookup([{ ...user, name: 'Renamed' }]))).error, /former username/);
  for (const data of [[user, user], [{ ...user, requestedUsername: 'different' }], [{ ...user, id: -1 }],
    [{ ...user, id: 9007199254740992 }], [{ ...user, id: '11' }], [{ ...user, name: '@everyone' }], [null], null]) {
    assert.ok((await resolveAccount('nova_one', lookup(data))).error);
  }
});
test('upstream errors and invalid JSON use fixed private-safe errors', async () => {
  const secret = 'private-error-marker';
  for (const fetcher of [async () => { throw Error(secret); }, async () => new Response(secret, { status: 429 }),
    async () => new Response(secret), async () => Response.json({ error: secret }),
    async () => new Response('', { status: 302, headers: { Location: 'https://example.com' } })]) {
    const result = await resolveAccount('nova_one', fetcher);
    assert.match(result.error, /unavailable/); assert.doesNotMatch(result.error, /private-error-marker/);
  }
});
test('lookup bodies are bounded by both declared and actual bytes', async () => {
  for (const fetcher of [async () => new Response('{}', { headers: { 'Content-Length': '9000' } }),
    async () => new Response(' '.repeat(8193)), async () => new Response('é'.repeat(4200))]) {
    assert.match((await resolveAccount('nova_one', fetcher)).error, /unavailable/);
  }
});
test('slow headers and slow response bodies abort within the lookup budget', async () => {
  for (const body of [false, true]) {
    let aborted = false;
    const start = performance.now();
    const result = await resolveAccount('nova_one', async (_url, { signal }) => {
      if (!body) return new Promise((_resolve, reject) => signal.addEventListener('abort', () => { aborted = true; reject(Error('private timeout')); }, { once: true }));
      return new Response(new ReadableStream({ start(controller) {
        signal.addEventListener('abort', () => { aborted = true; controller.error(Error('private timeout')); }, { once: true });
      } }));
    });
    assert.ok(aborted); assert.match(result.error, /unavailable/);
    assert.ok(performance.now() - start < LOOKUP_TIMEOUT_MS + 1000);
  }
});
test('every account command resolves its account only and preserves the signed input object', async () => {
  for (const option of sharedCommand.options.filter(o => o.options?.some(v => v.name === 'account'))) {
    const interaction = { id: '123456789012345678', data: { name: 'claw', options: [{ name: option.name,
      options: [{ name: 'account', value: 'nova_one' }, { name: 'slot', value: 'L' }] }] } };
    const before = structuredClone(interaction);
    const resolved = await resolveCommandAccount(interaction, lookup([user]));
    assert.equal(resolved.interaction.data.options[0].options[0].value, '11');
    assert.equal(resolved.interaction.data.options[0].options[1].value, 'L');
    assert.deepEqual(interaction, before);
  }
});
test('account-less commands skip Roblox and duplicate/missing account values fail closed', async () => {
  for (const name of ['setup', 'status', 'follow']) {
    const interaction = { data: { options: [{ name }] } };
    assert.equal((await resolveCommandAccount(interaction, forbiddenFetch)).interaction, interaction);
  }
  for (const options of [[], null, [{ name: 'account', value: '11' }, { name: 'account', value: '22' }]]) {
    assert.ok((await resolveCommandAccount({ data: { options: [{ name: 'enroll', options }] } }, forbiddenFetch)).error);
  }
});

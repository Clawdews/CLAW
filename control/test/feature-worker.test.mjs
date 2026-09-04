import test from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';

test('teams, deployment, movement queue, spots, inventory, loot and emergency stop work together', async t => {
  const owner = '123456789012345678', guild = '234567890123456789';
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
  const files = ['worker.js', 'protocol.js', 'bootstrap.js', 'tenancy.js', 'onboarding.js', 'catalog.js', 'status.js',
    'accounts.js', 'panel.js', 'panel-controller.js', 'batch.js', 'features.js', 'actions.js', 'alerts.js', 'feature-commands.js'];
  const mf = new Miniflare(convertV4MiniflareOptions({ workers: [{ name: 'features-test',
    modules: files.map(name => ({ type: 'ESModule', path: fileURLToPath(new URL('../' + name, import.meta.url)) })),
    compatibilityDate: '2026-09-04', durableObjects: { ROOM: { className: 'ControlRoom', useSQLite: true } },
    ratelimits: { ENTRY_LIMITER: { namespace_id: '153106', simple: { limit: 60, period: 60 } } },
    bindings: { SHARED_MODE: 'true', ACCESS_MODE: 'public', PUBLIC_ENDPOINT: 'https://claw.test', DISCORD_PUBLIC_KEY: publicKey } }] }));
  t.after(() => mf.dispose());
  let counter = 500000000000000000n;
  async function command(name, values = {}, group = null) {
    const leaf = { type: 1, name, options: Object.entries(values).map(([key, value]) => ({ name: key, value })) };
    const options = group ? [{ type: 2, name: group, options: [leaf] }] : [leaf];
    const payload = { id: String(counter++), application_id: '345678901234567890', token: ['test', 'feature', 'interaction', 'token'].join('-'),
      type: 2, guild_id: guild, channel_id: '456789012345678901', member: { user: { id: owner } },
      authorizing_integration_owners: { '0': guild },
      data: { name: 'claw', options } };
    const raw = JSON.stringify(payload), timestamp = String(Math.floor(Date.now() / 1000));
    const signature = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey,
      new TextEncoder().encode(timestamp + raw))).toString('hex');
    const response = await mf.dispatchFetch('https://claw.test/discord', { method: 'POST', body: raw,
      headers: { 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature } });
    assert.equal(response.status, 200);
    return response.json();
  }
  async function enroll(account) {
    const response = await command('enroll', { account });
    const key = response.data.content.match(/[a-f0-9]{64}/)?.[0];
    assert.ok(key, JSON.stringify(response)); return key;
  }
  async function connect(account, key) {
    const auth = await mf.dispatchFetch('https://claw.test/session?owner=' + owner, { method: 'POST',
      body: JSON.stringify({ accountId: account, key }) });
    const ticket = (await auth.json()).ticket;
    const response = await mf.dispatchFetch('https://claw.test/socket?owner=' + owner + '&ticket=' + ticket,
      { headers: { Upgrade: 'websocket' } });
    const socket = response.webSocket; socket.accept();
    const messages = [];
    socket.addEventListener('message', event => messages.push(JSON.parse(event.data)));
    socket.send(JSON.stringify({ type: 'hello', username: account === '11' ? 'Main' : 'Alt' }));
    return { socket, messages };
  }
  async function waitFor(fn) {
    for (let index = 0; index < 100; index++) { const value = fn(); if (value) return value; await new Promise(resolve => setTimeout(resolve, 20)); }
    assert.fail('message timeout');
  }

  const mainKey = await enroll('11'), altKey = await enroll('22');
  const main = await connect('11', mainKey); let alt = await connect('22', altKey);
  t.after(() => { main.socket.close(); alt.socket.close(); });
  await command('create', { team: 'Enmity' }, 'team');
  await command('add', { team: 'Enmity', account: '11' }, 'team');
  await command('add', { team: 'Enmity', account: '22' }, 'team');
  await command('main', { team: 'Enmity', account: '11' }, 'team');
  await new Promise(resolve => setTimeout(resolve, 2100));
  main.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 6032399813, jobId: 'same-server',
    state: 'MAIN', slot: 'L', position: { x: 10, y: 20, z: 30 } } }));
  alt.socket.send(JSON.stringify({ type: 'presence', current: { gameId: 99, placeId: 6032399813, jobId: 'same-server',
    state: 'WITH_MAIN', slot: 'L', position: { x: 0, y: 20, z: 0 } } }));
  await new Promise(resolve => setTimeout(resolve, 50));
  await command('recovery', { team: 'Enmity', enabled: true }, 'settings');
  const deployed = await command('deploy', { team: 'Enmity' });
  assert.match(deployed.data.content, /Deploying Enmity/);
  const profile = await waitFor(() => alt.messages.find(message => message.type === 'profile' && message.activeTeam));
  assert.equal(profile.enabled, true); assert.equal(profile.mainId, '11'); assert.equal(profile.allowMenuReturn, true);
  const ready = await command('ready', { team: 'Enmity' });
  assert.match(ready.data.content, /2 ready/);

  await command('formation', { team: 'Enmity', shape: 'line', spacing: 8 }, 'settings');
  const brought = await command('bring', { team: 'Enmity' }, 'move');
  assert.match(brought.data.content, /1 accounts/);
  const bring = await waitFor(() => alt.messages.find(message => message.type === 'action' && message.action === 'bring'));
  assert.equal(bring.args.mainId, '11'); assert.equal(bring.args.offset.z, -8);
  alt.socket.send(JSON.stringify({ type: 'action-result', accountId: '22', id: bring.id, ok: true, message: 'movement started' }));

  const saved = await command('save', { spot: 'Corner', account: '11' }, 'spot');
  assert.match(saved.data.content, /Saved parking spot/);
  await command('park', { team: 'Enmity', spot: 'Corner' }, 'move');
  const park = await waitFor(() => alt.messages.find(message => message.type === 'action' && message.action === 'park'));
  assert.equal(park.args.placeId, 6032399813); assert.equal(park.args.position.z, 22);

  alt.socket.close();
  alt = await connect('22', altKey);
  const recoveredPark = await waitFor(() => alt.messages.find(message => message.type === 'action' && message.id === park.id));
  assert.equal(recoveredPark.action, 'park');
  alt.socket.send(JSON.stringify({ type: 'action-result', accountId: '22', id: park.id, ok: true, message: 'movement started' }));

  alt.socket.send(JSON.stringify({ type: 'inventory', version: 1, accountId: '22',
    inventory: [{ name: 'Sword', count: 1 }], bank: [{ name: 'Crown', count: 2 }] }));
  alt.socket.send(JSON.stringify({ type: 'loot', version: 1, accountId: '22', items: [{ name: 'Crown', count: 1 }] }));
  await new Promise(resolve => setTimeout(resolve, 50));
  const inventory = await command('inventory', { account: '22' }, 'data');
  assert.match(inventory.data.content, /Sword/); assert.match(inventory.data.content, /Crown/);
  const loot = await command('loot', {}, 'data');
  assert.match(loot.data.content, /\+1 Crown/);

  const noted = await command('note', { account: '22', slot: 'L', text: 'Crown runner' }, 'data');
  assert.match(noted.data.content, /note saved/);
  assert.match((await command('save', { preset: 'Safe run', team: 'Enmity' }, 'preset')).data.content, /Saved preset/);
  assert.match((await command('list', {}, 'preset')).data.content, /Safe run/);
  await command('formation', { team: 'Enmity', shape: 'spread', spacing: 12 }, 'settings');
  assert.match((await command('apply', { preset: 'Safe run' }, 'preset')).data.content, /Review ready status/);
  assert.match((await command('list', {}, 'spot')).data.content, /Corner/);

  assert.match((await command('session', { action: 'start' }, 'data')).data.content, /Session started/);
  assert.match((await command('session', { action: 'show' }, 'data')).data.content, /Session CLAW session/);
  assert.match((await command('session', { action: 'end' }, 'data')).data.content, /Session ended/);

  const stopped = await command('emergency', { action: 'stop' });
  assert.match(stopped.data.content, /Emergency stop locked/);
  const stop = await waitFor(() => alt.messages.find(message => message.type === 'action' && message.action === 'stop'));
  assert.ok(stop);
  const blocked = await command('bring', { team: 'Enmity' }, 'move');
  assert.match(blocked.data.content, /Emergency stop is locked/);
  assert.match((await command('emergency', { action: 'resume' })).data.content, /Controls unlocked/);
  assert.match((await command('enmity', { team: 'Enmity', action: 'prepare' })).data.content, /prepared/);
  const oldBringIds = new Set(alt.messages.filter(message => message.action === 'bring').map(message => message.id));
  assert.match((await command('enmity', { team: 'Enmity', action: 'recall' })).data.content, /Recalling/);
  const recall = await waitFor(() => alt.messages.find(message => message.action === 'bring' && !oldBringIds.has(message.id)));
  assert.ok(recall);
  assert.match((await command('enmity', { team: 'Enmity', action: 'park', spot: 'Corner' })).data.content, /Parking/);
  assert.match((await command('enmity', { team: 'Enmity', action: 'finish' })).data.content, /finished/);
  const history = await command('history', {}, 'data');
  assert.match(history.data.content, /Emergency stop/);
});

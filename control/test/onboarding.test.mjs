import test from 'node:test';
import assert from 'node:assert/strict';
import { setupReply } from '../onboarding.js';

test('setup starts with one-workspace pairing and stays inside Discord limits', () => {
  assert.ok(setupReply.length <= 2000);
  assert.match(setupReply, /Start alt setup/);
  assert.match(setupReply, /Do not paste it into every account/);
  assert.match(setupReply, /8-character console code/);
  assert.match(setupReply, /launcher-beta\.lua/);
  assert.ok(setupReply.indexOf('Several accounts') < setupReply.indexOf('One account only'));
});

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { credentialIssue } from './check-public.mjs';

export const branches = new Set(['main', 'control-beta', 'discord-control', 'server-join', 'animation-transport']);

export function shortTitle(value) {
  const line = String(value || '').split(/[\r\n]/, 1)[0]
    .replace(/[\p{Cc}\p{Cf}]/gu, '')
    .replace(/https?:\/\/\S+/gi, '')
    .replace(/[@#*_`~<>\[\]()\\|]/g, '')
    .replace(/\s+/g, ' ').trim();
  const chars = Array.from(line || 'Updated');
  return chars.length > 56 ? chars.slice(0, 55).join('').trimEnd() + '…' : chars.join('');
}

export function pushPayload(event, repository) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository || '')
      || event?.repository?.full_name !== repository) throw new Error('Push repository mismatch.');
  if (event.deleted || typeof event.ref !== 'string' || !event.ref.startsWith('refs/heads/')) return null;
  const branch = event.ref.slice('refs/heads/'.length);
  if (!branches.has(branch)) return null;
  if (!/^[a-f0-9]{40}$/.test(event.after || '') || /^0+$/.test(event.after)) throw new Error('Missing push commit.');
  const message = String(event.head_commit?.id === event.after ? event.head_commit.message || '' : 'Updated');
  // Check before shortening or removing punctuation; neither makes private text safe.
  for (const text of [message, message.replace(/[\p{Cc}\p{Cf}]/gu, '')]) {
    if (credentialIssue('commit-message', text) || /\b[a-f0-9]{64}\b/i.test(text)
        || /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.test(text)) {
      throw new Error('Update withheld: review the commit message for private data.');
    }
  }
  const title = shortTitle(message);
  const label = branch === 'main' ? 'CLAW' : `CLAW ${branch}`;
  return {
    content: `${label}: ${title} · [view](https://github.com/${repository}/commit/${event.after})`,
    allowed_mentions: { parse: [] },
    flags: 4,
  };
}

export function webhookUrl(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Invalid Discord webhook configuration.'); }
  if (url.protocol !== 'https:' || url.hostname !== 'discord.com' || url.port || url.username || url.password
      || !/^\/api(?:\/v\d+)?\/webhooks\/\d{17,22}\/[A-Za-z0-9_-]{30,}$/.test(url.pathname)
      || url.search || url.hash) throw new Error('Invalid Discord webhook configuration.');
  url.searchParams.set('wait', 'true');
  return url;
}

export async function sendPush(payload, webhook, fetcher = fetch) {
  const url = webhookUrl(webhook);
  let response;
  try {
    response = await fetcher(url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    });
  } catch {
    throw new Error('Discord delivery was not confirmed; no automatic retry was sent.');
  }
  if (!response.ok) throw new Error(`Discord rejected the update (HTTP ${response.status}); no retry was sent.`);
  let message;
  try { message = await response.json(); } catch { /* A successful status alone does not confirm delivery. */ }
  if (!/^\d{17,22}$/.test(message?.id || '')) throw new Error('Discord returned no message confirmation; no retry was sent.');
  return message.id;
}

export async function main(env = process.env, args = process.argv.slice(2)) {
  if (args.some(arg => arg !== '--dry-run')) throw new Error('Use --dry-run to preview an update.');
  if (env.GITHUB_EVENT_NAME !== 'push') throw new Error('Only push events are supported.');
  let event;
  try { event = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, 'utf8')); }
  catch { throw new Error('Unable to read the push event.'); }
  const payload = pushPayload(event, env.GITHUB_REPOSITORY);
  if (!payload) { console.log('No update for this ref.'); return; }
  if (args.includes('--dry-run')) { console.log(payload.content); return payload; }
  if (!env.DISCORD_UPDATES_WEBHOOK) {
    console.log('::warning::Discord updates are not connected. Add the DISCORD_UPDATES_WEBHOOK repository secret.');
    return;
  }
  await sendPush(payload, env.DISCORD_UPDATES_WEBHOOK);
  console.log('Discord update sent.');
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}

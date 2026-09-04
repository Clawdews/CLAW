import { snowflake } from './protocol.js';

const important = new Set(['VERIFIED', 'WITH_MAIN', 'ATTENTION', 'AUTH_FAILED', 'EMERGENCY_STOP']);
const safe = value => String(value || '').replace(/[\x00-\x1f\x7f@]/g, ' ').slice(0, 100);
export function shouldAlert(mode, state) {
  if (mode === 'all') return true;
  const code = safe(state).match(/^([A-Z_]+)/)?.[1];
  return mode === 'important' && important.has(code);
}
export async function postAlert(env, alerts, content, fetcher = fetch) {
  if (!alerts || alerts.mode === 'off' || !snowflake(alerts.channelId)
      || typeof env.DISCORD_BOT_TOKEN !== 'string' || env.DISCORD_BOT_TOKEN.length < 20) return false;
  try {
    const response = await fetcher('https://discord.com/api/v10/channels/' + alerts.channelId + '/messages', {
      method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(2000),
      headers: { Authorization: 'Bot ' + env.DISCORD_BOT_TOKEN, 'Content-Type': 'application/json',
        'User-Agent': 'DiscordBot (https://github.com/Clawdews/CLAW, 0.3.0-beta.3)' },
      body: JSON.stringify({ content: 'CLAW · ' + safe(content), allowed_mentions: { parse: [] } }),
    });
    await response.body?.cancel();
    return response.ok;
  } catch { return false; }
}

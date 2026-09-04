// Read secrets from the environment or: node --env-file=.env register.mjs
import { command } from './commands.js';
import { snowflake } from './protocol.js';
const { DISCORD_BOT_TOKEN: token, DISCORD_APPLICATION_ID: app, DISCORD_GUILD_ID: guild } = process.env;
if (!token || !snowflake(app) || !snowflake(guild)) {
  throw new Error('Set DISCORD_BOT_TOKEN, DISCORD_APPLICATION_ID and DISCORD_GUILD_ID in the private environment.');
}
// Upsert only CLAW. Do not bulk-overwrite other commands in an existing application.
const response = await fetch(`https://discord.com/api/v10/applications/${app}/guilds/${guild}/commands`, {
  method: 'POST', headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json',
    'User-Agent': 'DiscordBot (https://github.com/Clawdews/CLAW, 0.1.0)' },
  signal: AbortSignal.timeout(15000),
  body: JSON.stringify(command),
});
if (!response.ok) {
  let code;
  try { code = (await response.json()).code; } catch { /* Do not print an HTML error page. */ }
  const reason = code === 50001 ? ' Install CLAW in the configured server before registering commands.' : '';
  const apiCode = Number.isSafeInteger(code) ? `, API ${code}` : '';
  throw new Error(`Discord registration failed (HTTP ${response.status}${apiCode}).${reason} No credentials printed.`);
}
console.log('Registered /claw in the configured Discord server.');

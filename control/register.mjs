// Read secrets from the environment or: node --env-file=.env register.mjs
import { command, sharedCommand } from './commands.js';
import { snowflake } from './protocol.js';
const { DISCORD_BOT_TOKEN: token, DISCORD_APPLICATION_ID: app, DISCORD_GUILD_ID: guild } = process.env;
const globalScope = process.env.DISCORD_COMMAND_SCOPE === 'global';
if (process.env.DISCORD_COMMAND_SCOPE && !['global', 'guild'].includes(process.env.DISCORD_COMMAND_SCOPE)) throw new Error('Invalid DISCORD_COMMAND_SCOPE');
if (globalScope && process.env.SHARED_MODE !== 'true') throw new Error('Global registration requires SHARED_MODE=true');
if (!token || !snowflake(app) || (!globalScope && !snowflake(guild))) {
  throw new Error('Set DISCORD_BOT_TOKEN, DISCORD_APPLICATION_ID and DISCORD_GUILD_ID in the private environment.');
}
// Upsert only CLAW. Do not bulk-overwrite other commands in an existing application.
const selectedCommand = structuredClone(process.env.SHARED_MODE === 'true' ? sharedCommand : command);
if (!globalScope) { delete selectedCommand.integration_types; delete selectedCommand.contexts; }
const response = await fetch(`https://discord.com/api/v10/applications/${app}${globalScope ? '' : '/guilds/' + guild}/commands`, {
  method: 'POST', headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json',
    'User-Agent': 'DiscordBot (https://github.com/Clawdews/CLAW, 0.2.0-beta.5)' },
  signal: AbortSignal.timeout(15000),
  body: JSON.stringify(selectedCommand),
});
if (!response.ok) {
  let code;
  try { code = (await response.json()).code; } catch { /* Do not print an HTML error page. */ }
  const reason = code === 50001 ? ' Install CLAW in the configured server before registering commands.' : '';
  const apiCode = Number.isSafeInteger(code) ? `, API ${code}` : '';
  throw new Error(`Discord registration failed (HTTP ${response.status}${apiCode}).${reason} No credentials printed.`);
}
console.log(globalScope ? 'Registered /claw for user and server installations.' : 'Registered /claw in the configured Discord server.');

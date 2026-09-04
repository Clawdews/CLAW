// Read secrets from the environment or: node --env-file=.env register.mjs
import { command } from './commands.js';
import { snowflake } from './protocol.js';
const { DISCORD_BOT_TOKEN: token, DISCORD_APPLICATION_ID: app, DISCORD_GUILD_ID: guild } = process.env;
if (!token || !snowflake(app) || !snowflake(guild)) {
  throw new Error('Set DISCORD_BOT_TOKEN, DISCORD_APPLICATION_ID and DISCORD_GUILD_ID in the private environment.');
}
// Upsert only CLAW. Do not bulk-overwrite other commands in an existing application.
const response = await fetch(`https://discord.com/api/v10/applications/${app}/guilds/${guild}/commands`, {
  method: 'POST', headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(command),
});
if (!response.ok) throw new Error(`Discord registration failed (HTTP ${response.status}); no credentials printed.`);
console.log('Registered /claw in the configured Discord server.');

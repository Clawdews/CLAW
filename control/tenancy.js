import { snowflake } from './protocol.js';

export const shared = env => env.SHARED_MODE === 'true';
export function allowedOwner(env, owner) {
  if (!snowflake(owner)) return false;
  if (env.ACCESS_MODE === 'public') return true;
  return (env.BETA_USERS || '').split(',').map(s => s.trim()).includes(owner);
}
export function interactionOwner(interaction, env) {
  const owner = interaction.member?.user?.id || interaction.user?.id;
  if (!snowflake(interaction.id) || !snowflake(owner)) return null;
  if (!shared(env)) return owner === env.DISCORD_OWNER_ID && interaction.guild_id === env.DISCORD_GUILD_ID ? owner : null;
  if (!allowedOwner(env, owner)) return null;
  // The installation owner is not necessarily the person invoking a guild command.
  // Always isolate by the authenticated invoking user, never by guild or an option.
  const installations = interaction.authorizing_integration_owners;
  const userInstall = installations?.['1'] === owner;
  const guildInstall = snowflake(interaction.guild_id) && installations?.['0'] === interaction.guild_id;
  return userInstall || guildInstall ? owner : null;
}
export const roomName = (env, owner) => shared(env) ? 'user:' + owner : 'claw';
export const regionForPlace = place => ({ 6473861193: 'EastLuminant', 6032399813: 'EtreanLuminant' })[place] || null;
export const safeSlot = slot => typeof slot === 'string' && /^[A-Za-z0-9_.:-]{1,80}$/.test(slot)
  && !['__proto__', 'constructor', 'prototype'].includes(slot);
export async function entryAllowed(env, key) {
  if (!shared(env) || env.ACCESS_MODE !== 'public') return true;
  // Public onboarding is disabled if the hosting rate-limit binding is missing.
  if (!env.ENTRY_LIMITER) return false;
  try { return (await env.ENTRY_LIMITER.limit({ key })).success === true; } catch { return false; }
}

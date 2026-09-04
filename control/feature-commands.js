import { id, now, nonce, snowflake } from './protocol.js';
import { safeSlot } from './tenancy.js';
import { actionPacket } from './actions.js';
import { postAlert } from './alerts.js';
import { ensureFeatures, cleanName, cleanNote, keyFor, named, teamMembers, formationOffset,
  MAX_TEAMS, MAX_PRESETS, MAX_SPOTS, readyReport, teamsReport, presetsReport, spotsReport,
  historyReport, lootReport, inventoryReport, sessionReport, activeFor } from './features.js';

export function commandInput(interaction) {
  const root = interaction.data?.options?.[0];
  if (!root) return { name: '', values: {} };
  const leaf = root.type === 2 ? root.options?.[0] : root;
  if (!leaf) return { name: root.name + ':', values: {} };
  return { name: root.type === 2 ? root.name + ':' + leaf.name : root.name,
    values: Object.fromEntries((leaf.options || []).map(option => [option.name, option.value])) };
}

const failed = content => ({ handled: true, content, changed: false, actions: [] });
const saved = (content, event, actions = []) => ({ handled: true, content, changed: true, event, actions });
const acted = (content, event, actions) => ({ handled: true, content, changed: false, event, actions });
const display = (account, member) => member?.nickname || (member?.username ? '@' + member.username : 'Account ' + account);
function getTeam(config, name) {
  const [key, team] = named(config.teams, name);
  return { key, team };
}
function movementTargets(config, team) {
  return teamMembers(config, team).filter(account => account !== (team.mainId || config.mainId));
}

export async function featureCommand(room, name, values, interaction, config, connections) {
  ensureFeatures(config);
  if (!['team:', 'move:', 'spot:', 'preset:', 'data:', 'settings:'].some(prefix => name.startsWith(prefix))
      && !['deploy', 'ready', 'emergency', 'enmity'].includes(name)) return { handled: false };

  if (name === 'team:create') {
    const label = cleanName(values.team), key = keyFor(values.team);
    if (!label || !key) return failed('Choose another team name between 1 and 32 bytes.');
    if (config.teams[key]) return failed('That team already exists.');
    if (Object.keys(config.teams).length >= MAX_TEAMS) return failed('Team limit reached.');
    config.teams[key] = { name: label, members: [], mainId: null, formation: { shape: 'circle', spacing: 6 }, recovery: false };
    return saved('Created team ' + label + '.', 'Created team ' + label);
  }
  if (name.startsWith('team:')) {
    if (name === 'team:list') return failed(teamsReport(config));
    const { key, team } = getTeam(config, values.team);
    if (!key || !team) return failed('That team does not exist.');
    if (name === 'team:delete') {
      delete config.teams[key];
      if (config.activeTeam === key) { config.activeTeam = null; config.follow = false; }
      return saved('Deleted team ' + team.name + '.', 'Deleted team ' + team.name);
    }
    const account = values.account;
    if (!id(account) || !config.members[account]) return failed('Pair that account first.');
    team.members ||= [];
    if (name === 'team:add') {
      if (!team.members.includes(account)) team.members.push(account);
      return saved('Added ' + display(account, config.members[account]) + ' to ' + team.name + '.',
        'Added an account to ' + team.name);
    }
    if (name === 'team:remove') {
      team.members = team.members.filter(value => value !== account);
      if (team.mainId === account) {
        team.mainId = null;
        if (config.activeTeam === key) { config.mainId = null; config.follow = false; }
      }
      return saved('Removed ' + display(account, config.members[account]) + ' from ' + team.name + '.',
        'Removed an account from ' + team.name);
    }
    if (name === 'team:main') {
      if (!team.members.includes(account)) team.members.push(account);
      team.mainId = account;
      if (config.activeTeam === key) { config.mainId = account; config.follow = false; }
      return saved('Team main set to ' + display(account, config.members[account]) + '.', 'Changed the main for ' + team.name);
    }
  }
  if (name === 'deploy') {
    if (config.halted) return failed('Emergency stop is locked. Use /claw emergency action:Unlock controls first.');
    const { key, team } = getTeam(config, values.team);
    if (!key || !team) return failed('That team does not exist.');
    const members = teamMembers(config, team), mainId = team.mainId || config.mainId;
    if (!members.length || !mainId || !members.includes(mainId)) return failed('Add the team accounts and choose its main first.');
    config.activeTeam = key; config.mainId = mainId; config.follow = true;
    return saved('Deploying ' + team.name + '. ' + members.length + ' accounts selected; following is on.',
      'Deployed ' + team.name);
  }
  if (name === 'ready') {
    if (values.team && !getTeam(config, values.team).team) return failed('That team does not exist.');
    return failed(readyReport(config, connections, values.team));
  }
  if (name === 'move:bring') {
    if (config.halted) return failed('Emergency stop is locked.');
    const { team } = getTeam(config, values.team);
    if (!team) return failed('That team does not exist.');
    const ids = movementTargets(config, team), mainId = team.mainId || config.mainId;
    if (!mainId || !config.members[mainId]) return failed('Choose a team main first.');
    if (mainId !== config.mainId || ids.some(account => !activeFor(config, account))) return failed('Deploy this team before bringing it.');
    const formation = team.formation || { shape: 'circle', spacing: 6 };
    const actions = ids.map((account, index) => ({ accounts: [account], packet: actionPacket('bring',
      { mainId, offset: formationOffset(formation.shape, index, ids.length, formation.spacing) }) }));
    return acted('Bring sent to ' + ids.length + ' accounts in ' + team.name + '.', 'Sent bring to ' + team.name, actions);
  }
  if (name === 'move:stop') {
    let ids = Object.keys(config.members);
    if (values.team) {
      const { team } = getTeam(config, values.team);
      if (!team) return failed('That team does not exist.');
      ids = teamMembers(config, team);
    }
    return acted('Stop sent to ' + ids.length + ' accounts.', 'Stopped account movement',
      [{ accounts: ids, packet: actionPacket('stop', {}, 300) }]);
  }
  if (name === 'move:park') {
    if (config.halted) return failed('Emergency stop is locked.');
    const { team } = getTeam(config, values.team), [, spot] = named(config.spots, values.spot);
    if (!team) return failed('That team does not exist.');
    if (!spot) return failed('That parking spot does not exist.');
    const ids = movementTargets(config, team), formation = team.formation || { shape: 'circle', spacing: 6 };
    if ((team.mainId || config.mainId) !== config.mainId || ids.some(account => !activeFor(config, account))) return failed('Deploy this team before parking it.');
    const actions = ids.map((account, index) => {
      const offset = formationOffset(formation.shape, index, ids.length, formation.spacing);
      return { accounts: [account], packet: actionPacket('park', { placeId: spot.placeId, jobId: spot.jobId,
        position: { x: spot.position.x + offset.x, y: spot.position.y + offset.y, z: spot.position.z + offset.z } }) };
    });
    return acted('Park sent to ' + ids.length + ' accounts.', 'Sent team to ' + spot.name, actions);
  }
  if (name.startsWith('spot:')) {
    if (name === 'spot:list') return failed(spotsReport(config));
    const key = keyFor(values.spot);
    if (!key) return failed('Use a spot name between 1 and 32 bytes.');
    if (name === 'spot:delete') {
      if (!config.spots[key]) return failed('That parking spot does not exist.');
      const label = config.spots[key].name; delete config.spots[key];
      return saved('Deleted parking spot ' + label + '.', 'Deleted parking spot ' + label);
    }
    if (name === 'spot:save') {
      const label = cleanName(values.spot), connection = connections[values.account], presence = connection?.presence;
      if (!label || !presence?.position || presence.placeId === 4111023553) return failed('That account must be connected and in-world to save its position.');
      if (!config.spots[key] && Object.keys(config.spots).length >= MAX_SPOTS) return failed('Parking spot limit reached.');
      config.spots[key] = { name: label, placeId: presence.placeId, jobId: presence.jobId,
        position: presence.position, savedAt: now(), savedBy: values.account };
      return saved('Saved parking spot ' + label + '.', 'Saved parking spot ' + label);
    }
  }
  if (name.startsWith('preset:')) {
    if (name === 'preset:list') return failed(presetsReport(config));
    const key = keyFor(values.preset);
    if (!key) return failed('Use a preset name between 1 and 32 bytes.');
    if (name === 'preset:delete') {
      if (!config.presets[key]) return failed('That preset does not exist.');
      const label = config.presets[key].name; delete config.presets[key];
      return saved('Deleted preset ' + label + '.', 'Deleted preset ' + label);
    }
    if (name === 'preset:save') {
      const { key: teamKey, team } = getTeam(config, values.team), label = cleanName(values.preset);
      if (!team) return failed('That team does not exist.');
      if (!config.presets[key] && Object.keys(config.presets).length >= MAX_PRESETS) return failed('Preset limit reached.');
      const members = {};
      for (const account of teamMembers(config, team)) {
        const member = config.members[account];
        members[account] = { preferredSlots: structuredClone(member.preferredSlots || {}),
          allowMenuReturn: member.allowMenuReturn === true };
      }
      config.presets[key] = { name: label, teamKey, teamName: team.name, members, mainId: team.mainId || config.mainId,
        formation: structuredClone(team.formation || { shape: 'circle', spacing: 6 }), recovery: team.recovery === true, savedAt: now() };
      return saved('Saved preset ' + label + '.', 'Saved preset ' + label);
    }
    if (name === 'preset:apply') {
      const preset = config.presets[key];
      if (!preset) return failed('That preset does not exist.');
      if (!config.teams[preset.teamKey] && Object.keys(config.teams).length >= MAX_TEAMS) return failed('Team limit reached. Delete a team before applying this preset.');
      const members = Object.keys(preset.members).filter(account => config.members[account]);
      if (!members.length || !preset.mainId || !members.includes(preset.mainId)) return failed('The preset no longer has a valid paired main.');
      config.teams[preset.teamKey] = { name: preset.teamName, members, mainId: preset.mainId,
        formation: structuredClone(preset.formation || { shape: 'circle', spacing: 6 }), recovery: preset.recovery === true };
      for (const account of members) {
        config.members[account].preferredSlots = structuredClone(preset.members[account].preferredSlots || {});
        config.members[account].allowMenuReturn = preset.members[account].allowMenuReturn === true;
      }
      config.activeTeam = preset.teamKey; config.mainId = preset.mainId; config.follow = false;
      return saved('Applied ' + preset.name + '. Review ready status, then deploy the team.', 'Applied preset ' + preset.name);
    }
  }
  if (name === 'data:note') {
    const member = config.members[values.account], slot = values.slot, note = values.text === '-' ? null : cleanNote(values.text);
    if (!member || !safeSlot(slot) || !member.slots?.[slot] || (values.text !== '-' && !note)) return failed('Choose an observed character and a note up to 200 bytes. Use - to clear it.');
    member.notes ||= {};
    if (note) member.notes[slot] = note; else delete member.notes[slot];
    return saved(note ? 'Character note saved.' : 'Character note cleared.', note ? 'Updated a character note' : 'Cleared a character note');
  }
  if (name === 'data:inventory') {
    if (!config.members[values.account]) return failed('That account is not paired.');
    return { handled: true, changed: false, content: inventoryReport(config, values.account),
      actions: [{ accounts: [values.account], packet: actionPacket('scan-items', {}, 90) }] };
  }
  if (name === 'data:loot') return failed(await lootReport(room));
  if (name === 'data:history') return failed(await historyReport(room));
  if (name === 'data:session') {
    if (values.action === 'show') return failed(sessionReport(config));
    if (values.action === 'start') {
      if (config.session) return failed(sessionReport(config));
      config.session = { id: nonce(), startedAt: now(), name: 'CLAW session' };
      return saved('Session started.', 'Started a session');
    }
    if (values.action === 'end') {
      if (!config.session) return failed('No session is running.');
      config.session = null;
      return saved('Session ended. History and loot remain available.', 'Ended the session');
    }
  }
  if (name === 'settings:formation') {
    const { team } = getTeam(config, values.team);
    if (!team || !['circle', 'line', 'stack', 'spread'].includes(values.shape)) return failed('Choose a saved team and formation.');
    const spacing = values.spacing === undefined ? 6 : values.spacing;
    if (!Number.isInteger(spacing) || spacing < 2 || spacing > 30) return failed('Spacing must be 2–30 studs.');
    team.formation = { shape: values.shape, spacing };
    return saved('Formation saved for ' + team.name + '.', 'Changed formation for ' + team.name);
  }
  if (name === 'settings:alerts') {
    if (!['off', 'important', 'all'].includes(values.mode)) return failed('Choose an alert mode.');
    if (values.mode !== 'off' && !snowflake(interaction.channel_id)) return failed('Run this command in the Discord channel where alerts should appear.');
    const alerts = { mode: values.mode, channelId: values.mode === 'off' ? null : interaction.channel_id };
    if (values.mode !== 'off' && !await postAlert(room.env, alerts, 'Alerts connected: ' + values.mode + '.')) {
      return failed('CLAW could not post in this channel. Add the bot with Send Messages permission, then try again.');
    }
    config.alerts = alerts;
    return saved(values.mode === 'off' ? 'Alerts are off.' : 'Alerts will post in this channel: ' + values.mode + '.',
      'Changed alert settings');
  }
  if (name === 'settings:recovery') {
    const { team } = getTeam(config, values.team);
    if (!team || typeof values.enabled !== 'boolean') return failed('Choose a saved team and enabled true or false.');
    team.recovery = values.enabled;
    return saved('Automatic server recovery ' + (values.enabled ? 'enabled' : 'disabled') + ' for ' + team.name + '.',
      'Changed recovery for ' + team.name);
  }
  if (name === 'emergency') {
    if (values.action === 'stop') {
      config.halted = true; config.follow = false; config.activeTeam = null;
      return saved('Emergency stop locked. Following is off; Stop was sent to all accounts.', 'Emergency stop',
        [{ accounts: Object.keys(config.members), packet: actionPacket('stop', {}, 300) }]);
    }
    if (values.action === 'resume') {
      config.halted = false; config.follow = false;
      return saved('Controls unlocked. Following stays off until you deploy a team or enable it.', 'Unlocked controls');
    }
  }
  if (name === 'enmity') {
    const { key, team } = getTeam(config, values.team);
    if (!team) return failed('That team does not exist.');
    const members = teamMembers(config, team), mainId = team.mainId || config.mainId;
    if (!members.length || !mainId || !members.includes(mainId)) return failed('Add the Enmity accounts and choose the team main first.');
    if (values.action === 'prepare') {
      if (config.halted) return failed('Emergency stop is locked.');
      config.activeTeam = key; config.mainId = mainId; config.follow = true;
      return saved('Enmity team prepared. Following is on; use Recall when everyone arrives.', 'Prepared Enmity team');
    }
    if (values.action === 'finish') {
      config.follow = false;
      return saved('Enmity flow finished. Following and movement are stopped.', 'Finished Enmity flow',
        [{ accounts: members, packet: actionPacket('stop', {}, 300) }]);
    }
    if (config.halted) return failed('Emergency stop is locked.');
    const ids = movementTargets(config, team), formation = team.formation || { shape: 'circle', spacing: 6 };
    if (mainId !== config.mainId || ids.some(account => !activeFor(config, account))) return failed('Prepare this Enmity team first.');
    if (values.action === 'recall') {
      const actions = ids.map((account, index) => ({ accounts: [account], packet: actionPacket('bring',
        { mainId, offset: formationOffset(formation.shape, index, ids.length, formation.spacing) }) }));
      return acted('Recalling ' + ids.length + ' Enmity accounts to the main.', 'Recalled Enmity team', actions);
    }
    if (values.action === 'park') {
      const [, spot] = named(config.spots, values.spot);
      if (!spot) return failed('Choose a saved parking spot.');
      const actions = ids.map((account, index) => {
        const offset = formationOffset(formation.shape, index, ids.length, formation.spacing);
        return { accounts: [account], packet: actionPacket('park', { placeId: spot.placeId, jobId: spot.jobId,
          position: { x: spot.position.x + offset.x, y: spot.position.y + offset.y, z: spot.position.z + offset.z } }) };
      });
      return acted('Parking ' + ids.length + ' Enmity accounts at ' + spot.name + '.', 'Parked Enmity team', actions);
    }
  }
  return failed('Unknown CLAW feature command.');
}

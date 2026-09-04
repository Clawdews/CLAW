const account = { type: 3, name: 'account', description: 'Numeric Roblox UserId', required: true };
const usernameAccount = { ...account, description: 'Roblox username (not display name), or numeric UserId', max_length: 64 };
const teamName = { type: 3, name: 'team', description: 'Team name', required: true, min_length: 1, max_length: 32 };
const presetName = { type: 3, name: 'preset', description: 'Preset name', required: true, min_length: 1, max_length: 32 };
const spotName = { type: 3, name: 'spot', description: 'Saved spot name', required: true, min_length: 1, max_length: 32 };

export const command = {
  name: 'claw', description: 'Control your paired CLAW accounts', type: 1,
  default_member_permissions: '0',
  options: [
    { type: 1, name: 'status', description: 'Show paired accounts and their current status' },
    { type: 1, name: 'enroll', description: 'Create or rotate an account pairing key', options: [account] },
    { type: 1, name: 'main', description: 'Choose the main account; pauses following until enabled', options: [account] },
    { type: 1, name: 'follow', description: 'Enable or pause automatic joining', options: [
      { type: 5, name: 'enabled', description: 'Enable auto-follow', required: true } ] },
    { type: 1, name: 'slot', description: 'Set an actual DataSlot string if it cannot be learned automatically', options: [account,
      { type: 3, name: 'value', description: 'Actual game DataSlot string, not a guessed slot number', required: true } ] },
    { type: 1, name: 'retry', description: 'Authorize one new attempt for a stuck alt', options: [account] },
    { type: 1, name: 'revoke', description: 'Disconnect an account and invalidate its key', options: [account] },
  ],
};

export const sharedCommand = {
  ...command, default_member_permissions: null, integration_types: [0, 1], contexts: [0, 1, 2],
  options: [
    { type: 1, name: 'panel', description: 'Open your private account controls' },
    { type: 1, name: 'setup', description: 'Pair your accounts' },
    { type: 1, name: 'status', description: 'Show account status', options: [
      { type: 4, name: 'page', description: 'Status page', min_value: 1, max_value: 30 }] },
    { type: 1, name: 'enroll', description: 'Pair one account', options: [usernameAccount] },
    { type: 1, name: 'main', description: 'Choose the main account', options: [usernameAccount] },
    { type: 1, name: 'follow', description: 'Enable or pause automatic joining', options: [
      { type: 5, name: 'enabled', description: 'Enable following', required: true }] },
    { type: 1, name: 'retry', description: 'Retry one stuck account', options: [usernameAccount] },
    { type: 1, name: 'revoke', description: 'Remove one paired account', options: [usernameAccount] },
    { type: 1, name: 'nickname', description: 'Give an account a short label', options: [usernameAccount,
      { type: 3, name: 'label', description: 'Label', required: true, max_length: 32 }] },
    { type: 1, name: 'auto-return', description: 'Let an account return to the menu when the main moves', options: [usernameAccount,
      { type: 5, name: 'enabled', description: 'Enable normal menu return', required: true }] },
    { type: 1, name: 'rotate', description: 'Replace a lost pairing key', options: [usernameAccount] },
    { type: 1, name: 'slots', description: 'Show characters and permissions', options: [usernameAccount,
      { type: 4, name: 'page', description: 'Character page', min_value: 1, max_value: 60 }] },
    { type: 1, name: 'allow-slot', description: 'Allow or disable one character', options: [usernameAccount,
      { type: 3, name: 'slot', description: 'Observed slot letter', required: true },
      { type: 5, name: 'enabled', description: 'Allow this character', required: true }] },
    { type: 1, name: 'prefer-slot', description: 'Choose a character for a region', options: [usernameAccount,
      { type: 3, name: 'region', description: 'Region', required: true, choices: [
        { name: 'Eastern Luminant', value: 'EastLuminant' }, { name: 'Etrean Luminant', value: 'EtreanLuminant' }] },
      { type: 3, name: 'slot', description: 'Allowed slot in that region', required: true }] },
    { type: 2, name: 'team', description: 'Create and edit account teams', options: [
      { type: 1, name: 'create', description: 'Create a team', options: [teamName] },
      { type: 1, name: 'add', description: 'Add an account to a team', options: [teamName, usernameAccount] },
      { type: 1, name: 'remove', description: 'Remove an account from a team', options: [teamName, usernameAccount] },
      { type: 1, name: 'main', description: 'Choose the team main', options: [teamName, usernameAccount] },
      { type: 1, name: 'list', description: 'Show saved teams' },
      { type: 1, name: 'delete', description: 'Delete a team', options: [teamName] }] },
    { type: 1, name: 'deploy', description: 'Prepare and follow with one saved team', options: [teamName] },
    { type: 1, name: 'ready', description: 'Check who is ready', options: [
      { ...teamName, required: false }] },
    { type: 2, name: 'move', description: 'Move connected team members', options: [
      { type: 1, name: 'bring', description: 'Bring a team to its main', options: [teamName] },
      { type: 1, name: 'stop', description: 'Stop a team immediately', options: [{ ...teamName, required: false }] },
      { type: 1, name: 'park', description: 'Move a team to a saved spot', options: [teamName, spotName] }] },
    { type: 2, name: 'spot', description: 'Save parking spots', options: [
      { type: 1, name: 'save', description: 'Save an account’s current position', options: [spotName, usernameAccount] },
      { type: 1, name: 'list', description: 'Show saved spots' },
      { type: 1, name: 'delete', description: 'Delete a saved spot', options: [spotName] }] },
    { type: 2, name: 'preset', description: 'Save and apply team setups', options: [
      { type: 1, name: 'save', description: 'Save the current team setup', options: [presetName, teamName] },
      { type: 1, name: 'apply', description: 'Apply a saved setup', options: [presetName] },
      { type: 1, name: 'list', description: 'Show saved presets' },
      { type: 1, name: 'delete', description: 'Delete a preset', options: [presetName] }] },
    { type: 2, name: 'data', description: 'Notes, items, loot and sessions', options: [
      { type: 1, name: 'note', description: 'Save a character note', options: [usernameAccount,
        { type: 3, name: 'slot', description: 'Character slot', required: true },
        { type: 3, name: 'text', description: 'Note, or - to clear', required: true, max_length: 200 }] },
      { type: 1, name: 'inventory', description: 'Show the latest item scan', options: [usernameAccount] },
      { type: 1, name: 'loot', description: 'Show recent item gains' },
      { type: 1, name: 'history', description: 'Show recent CLAW activity' },
      { type: 1, name: 'session', description: 'Start, end or show a session', options: [
        { type: 3, name: 'action', description: 'Session action', required: true, choices: [
          { name: 'Start', value: 'start' }, { name: 'End', value: 'end' }, { name: 'Show', value: 'show' }] }] }] },
    { type: 2, name: 'settings', description: 'Team formations and alerts', options: [
      { type: 1, name: 'formation', description: 'Choose a team formation', options: [teamName,
        { type: 3, name: 'shape', description: 'Formation', required: true, choices: [
          { name: 'Circle', value: 'circle' }, { name: 'Line', value: 'line' },
          { name: 'Stack', value: 'stack' }, { name: 'Spread', value: 'spread' }] },
        { type: 4, name: 'spacing', description: 'Spacing in studs', min_value: 2, max_value: 30 }] },
      { type: 1, name: 'alerts', description: 'Post account alerts in this channel', options: [
        { type: 3, name: 'mode', description: 'Alert level', required: true, choices: [
          { name: 'Off', value: 'off' }, { name: 'Important only', value: 'important' }, { name: 'All changes', value: 'all' }] }] },
      { type: 1, name: 'recovery', description: 'Let a team recover after its main changes servers', options: [teamName,
        { type: 5, name: 'enabled', description: 'Enable normal menu return for this team', required: true }] }] },
    { type: 1, name: 'emergency', description: 'Stop everything or unlock controls', options: [
      { type: 3, name: 'action', description: 'Emergency action', required: true, choices: [
        { name: 'Stop everything', value: 'stop' }, { name: 'Unlock controls', value: 'resume' }] }] },
    { type: 1, name: 'enmity', description: 'Run the saved Enmity team flow', options: [teamName,
      { type: 3, name: 'action', description: 'Flow step', required: true, choices: [
        { name: 'Prepare and follow', value: 'prepare' }, { name: 'Park safely', value: 'park' },
        { name: 'Recall to main', value: 'recall' }, { name: 'Finish and stop', value: 'finish' }] },
      { ...spotName, required: false }] },
  ],
};

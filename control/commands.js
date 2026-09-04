const account = { type: 3, name: 'account', description: 'Numeric Roblox UserId', required: true };
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
const usernameAccount = { ...account, description: 'Roblox username (not display name), or numeric UserId', max_length: 64 };
export const sharedCommand = {
  ...command, default_member_permissions: null, integration_types: [0, 1], contexts: [0, 1, 2],
  options: [
    { type: 1, name: 'panel', description: 'Open your private account and character controls' },
    { type: 1, name: 'setup', description: 'Start your own private account group' },
    ...command.options.filter(option => option.name !== 'slot').map(option => option.name === 'enroll'
      ? { ...option, description: 'Pair a new account and receive private setup instructions' }
      : option.name === 'status' ? { ...option, options: [{ type: 4, name: 'page', description: 'Account status page', min_value: 1, max_value: 30 }] } : option),
    { type: 1, name: 'nickname', description: 'Give one account an easy-to-read label in Discord', options: [account,
      { type: 3, name: 'label', description: 'Short account label (up to 32 UTF-8 bytes)', required: true, max_length: 32 }] },
    { type: 1, name: 'auto-return', description: 'Opt an account in or out of normal automatic menu return', options: [account,
      { type: 5, name: 'enabled', description: 'Permit normal menu return; does not bypass combat restrictions', required: true }] },
    { type: 1, name: 'rotate', description: 'Replace a lost pairing key; disconnects the previous client', options: [account] },
    { type: 1, name: 'slots', description: 'List your character cards, regions and approvals', options: [account,
      { type: 4, name: 'page', description: 'Character-list page', min_value: 1, max_value: 60 }] },
    { type: 1, name: 'allow-slot', description: 'Approve or disable one character for automatic selection', options: [account,
      { type: 3, name: 'slot', description: 'Actual observed DataSlot', required: true },
      { type: 5, name: 'enabled', description: 'Allow this character', required: true }] },
    { type: 1, name: 'prefer-slot', description: 'Choose your preferred approved character for a region', options: [account,
      { type: 3, name: 'region', description: 'Destination region', required: true, choices: [
        { name: 'Eastern Luminant', value: 'EastLuminant' }, { name: 'Etrean Luminant', value: 'EtreanLuminant' }] },
      { type: 3, name: 'slot', description: 'Approved DataSlot in that region', required: true }] },
  ],
};
sharedCommand.options = sharedCommand.options.map(option => ({ ...option,
  ...(option.options ? { options: option.options.map(value => value.name === 'account' ? { ...usernameAccount } : value) } : {}),
}));

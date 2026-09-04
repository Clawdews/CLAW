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

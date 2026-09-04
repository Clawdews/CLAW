# Privacy

Public source and blank examples are safe to share. Filled configurations are not.

Keep these private:

- Discord pairing and batch-setup snippets
- `CLAW_PAIRINGS` and account reports
- Webhook URLs, bot tokens, cookies and passwords
- Character lists and exact server details

CLAW Control stores account IDs, usernames, hashed pairing keys, character cards, settings, notes, item summaries and recent activity in the shared service. Each Discord user has a separate group, but the service host can access stored data. Pairing keys also stay in the executor workspace.

Username commands send the entered name to Roblox's public users API. They do not send cookies, pairing keys or server details with that lookup.

CLAW Control alerts send the selected channel an account label and status. Item history stays inside private command replies.

Before sharing screenshots, cover keys, account details and server IDs. Use `/claw rotate` for a leaked pairing key and replace leaked webhooks or bot tokens at their source.

Before publishing:

```sh
node tools/check-public.mjs --history
```

Automated checks catch known patterns, not every possible private detail.

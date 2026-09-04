# What to keep private

The source code and public loader are safe to share. Your filled-in setup is not.

| Safe to share | Keep private |
| --- | --- |
| The public GitHub loader | Your Discord pairing snippet |
| Source code and blank examples | Files inside `CLAW_PAIRINGS` |
| A command name or the short support report | Webhook URLs, bot tokens, cookies and passwords |
| A screenshot with personal details covered | Account lists, character reports and exact server details |

## Where your information goes

- **GitHub:** code, blank examples and documentation. The push-notification webhook lives in an encrypted repository secret, not in the source.
- **Your device:** cloud pairing and attempt files stay in the executor workspace. Keep that folder private; do not upload it as a whole.
- **Shared controller (beta):** the host stores account IDs, hashed pairing keys, character cards, settings and connection/attempt information. Groups are separated by Discord user, but the service owner can access stored data. This is not end-to-end encryption.
- **Roblox username lookup:** when you use a username in a beta command, only that name is sent to Roblox’s public users API. No Discord identity, server destination, pairing key or cookie is sent with the lookup. Numeric IDs skip this request.
- **Discord:** private pairing/status replies and the notifications you configure. Private replies are not permission to share their contents.
- **Loot notifications:** your chosen channel receives the username, items and session/server details described in the loot guide. Everyone who can view that channel can read them.

The controller does not need your Roblox password or session cookie. The host needs a bot token for its own Discord app; ordinary users do not.

Private does not mean stored nowhere: pairing needs a saved key, and cloud following needs account and server details. Keep those in the locations above, not in public posts. Never upload your whole executor workspace to get help.

## Before sharing a screenshot or report

For the shared beta, prefer the [short support report](CONTROL-SETUP.md#a-report-you-can-share). It leaves out identities, keys and raw errors without uploading anything.

1. Hide keys, webhook URLs and pairing snippets completely.
2. Remove account IDs, character names and server details you do not want others to see.
3. Share the short support report and what you were doing, not full console logs or configuration. Other scripts' errors may contain private details.

If a pairing key leaks, use `/claw rotate` or `/claw revoke`. Replace a leaked webhook or bot token in Discord. Deleting a post or file alone does not make the old credential safe.

## Before publishing code

```sh
node --test tests/public-files.test.mjs
node tools/check-public.mjs --history
```

The check scans checked-in, staged and untracked public files, plus all fetched history. Ignored local files stay local. GitHub also runs the check on pushes and pull requests. Pattern checks can miss private information, so still review what you publish. Old clones, screenshots and backups cannot be recalled by deleting a current file.

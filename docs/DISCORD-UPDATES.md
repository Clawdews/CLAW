# Push updates

One short line per push to an active branch. No pings, embeds or commit lists.

> CLAW: Tidy setup instructions · view

To connect a channel:

1. In that Discord channel, open **Edit Channel → Integrations → Webhooks**. Create a webhook and copy its URL. This needs Manage Webhooks permission.
2. In this GitHub repository, open **Settings → Secrets and variables → Actions**. Add a repository secret named `DISCORD_UPDATES_WEBHOOK` containing the URL.
3. The next push sends an update. Check **Actions → Discord updates** for the result.

The workflow runs on `main`, `control-beta`, `discord-control`, `server-join` and `animation-transport`. Compatibility refs stay silent. The webhook is used only by the posting step; it does not belong in Lua or a tracked file.

If the secret is missing, the job reports that updates are not connected. A send counts as confirmed only when Discord returns a message ID. Ambiguous failures are not automatically retried, to avoid duplicate posts. Rerunning a successful workflow will post again.

Keep commit titles brief. Notifications use only the final commit's first line, shortened to 56 characters, plus a link to that commit. Remove the repository secret to disconnect updates.

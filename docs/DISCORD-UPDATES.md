# Discord push updates

The workflow posts one short commit title and link per push. No pings or embeds.

1. Create a Discord channel webhook.
2. Add it to GitHub Actions secrets as `DISCORD_UPDATES_WEBHOOK`.
3. Push to an active branch.

Remove the secret to disconnect it. Keep commit titles short and private information out of commits.

# EPU Guild Sync Helper

This Windows helper uses your guild's existing Discord bot. You do not need its token, a second bot or an officer rank.

1. Install the current EPU Guild Tools addon.
2. Accept your organiser's invitation to **your individual shared folder**, using OneDrive or Google Drive for desktop. Make sure it appears as a real folder in File Explorer, not just a web link. Keep it available offline. Both ends must access the same shared files; Google Drive and OneDrive do not automatically sync to each other.
3. Open **EPU-Sync-Helper.exe**. Browse to that shared folder, which contains `connection.json`, then to WoW's `_forever_` folder.
4. Select **Start syncing**. Optionally enable starting when you sign into Windows. Keep the helper open or minimized while playing.
5. Your organiser must whitelist each of your characters in game. Log into an allowed character and `/reload` to save the first game snapshot. Incoming actions load at login or `/reload`; they are not instant.

The helper stages guild invite requests, new bank requests awaiting approval and verified-character event signups. It exports a filtered copy of public guild bank/request/crafter/event/signup data to the central bot, including officer status changes already confirmed through guild sync. It does not export officer notes/logs, your guide bookmarks, notification preferences, map coordinates, Discord credentials or unrelated account data. It cannot approve/reject bank requests, change event organisers' plans or post officer announcements. Those incoming officer actions remain on the officer's existing bridge. Update both the helper and addon for Discord event signups; older helpers retain invite/bank sync.

Whitelisting does not change your guild rank. Receiving invite alerts/sending invitations still requires the game's guild-invite permission. The bot PC and both cloud sync apps must be running to exchange fresh files. Do not run the full Discord bot on the helper PC or point multiple helpers at the same WoW installation.

Each helper folder contains an individual connection secret. Share only your assigned folder with approved people. Never share the organiser's bot config, Discord token or the parent folder containing everybody's connections. The organiser can disable your connection separately. Signed files are validated and replay-protected; incomplete cloud copies are retried. Data older than 24 hours is not newly staged.

For source users, `python helper.py` needs Python with Tkinter but no extra Python packages. The Windows release executable includes its runtime.

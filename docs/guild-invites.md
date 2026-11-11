# Discord guild invite requests

In **#guild-invite-requests**, type `/guildinvite` and select the command Discord suggests. Fill in both required fields: `first_name` and `last_name`. These are the character's names, not the player's real name or Discord display name.

Alternatively post an unquoted, standalone line such as:

```text
Character: Donaga Gaelige
```

No Discord tag needs to be created. `Character:` is a label the companion recognizes. It does not supply Discord's typing dropdown; the slash command does. Both fields must contain a single name part, using letters and optional internal apostrophes. The game still decides whether the character name is valid and eligible for a guild invitation.

Ordinary conversation, names without the label, quotes, fenced code examples, bot/webhook posts, missing surnames and multiple Character lines are ignored. The companion accepts at most five new requests per Discord user per hour, suppresses duplicate active character names, and expires requests after seven days. Only new messages are watched; old channel history is not backfilled.

Editing an accepted message updates its name. Removing the Character line, deleting the message or bulk-deleting it withdraws that request. A duplicate message that was not accepted cannot withdraw another person's original request. Changes require another game import. Slash-command requests remain until they expire or the character joins.

## In game

After the companion-running officer or a whitelisted shared-folder helper logs in or `/reload`s, the addon imports requests and shares them through normal guild sync. This is not an instant internet connection: WoW does not read changed Inbox.lua files during a session.

Only characters for whom the game reports `CanGuildInvite()` receive invite notifications. This is independent of EPU's officer-rank setting, so a non-officer with invite permission can receive them. Notifications follow quiet hours, sound and Instant/Digest/Off preferences. A request is not proof of character ownership.

Use `/epu invites` or click **Guild invites** below **Roster** in the sidebar. The sidebar entry appears on characters with guild invite permission. Select a request to review the complete character name and Discord requester. Click **Open invite in chat**, review the prepared `/ginvite First Last` command, and press **Enter**. You can also copy the command into WoW chat yourself. Check the game's response. Already-joined characters stop appearing as pending. **Dismiss for me** hides a request on this character only.

The list shows **Online**, **Offline**, **Online (reported)** or **Unknown**. Friends-list results match the complete first and last name. **Add to Friends** is an explicit manual action; EPU never adds or removes friends in the background. A connected target or positive result from a player's manual `/who` search can also establish recent online presence. Missing `/who` results never mean offline, and EPU does not issue automatic `/who` queries or change the Who window's routing.

Invite-capable addon users share brief positive sightings for active requests through paced guild messages. Reports identify their source, expire after two minutes, are advisory and never create invite confirmations or Discord checkmarks. Presence stays in memory and is not exported through the companion. Members with actual game invite permission receive an actionable online alert, respecting their notification settings, quiet hours and personal dismissals. Continuous online status stays quiet; observed reconnects have a ten-minute alert cooldown. Universal live status for non-guild characters is unavailable: use Friends for reliable login/offline updates and treat **Unknown** honestly.

Native success messages and roster joins create a synced outcome. The bot reacts ✅ on the original request only after that outcome reaches its game snapshot (directly or through a helper). The addon distinguishes **Invite sent** from **Joined**. No checkmark is created from clicking Invite alone; unsupported/protected client messages wait for a roster-confirmed join. Editing a request to a different character invalidates its old outcome. Slash commands create a visible bot response that can receive the same checkmark. The bot needs View Channel, Read Message History and Add Reactions permissions.

## Companion setup

Set `invite_requests_channel_id` in `epu-discord/config.json` to the text channel's ID. Leave it blank to disable this feature. Enable the bot's **Message Content Intent** in the Discord Developer Portal for labelled-message imports, and allow the bot to View Channel and Read Message History there. The command is registered in the configured server and accepts submissions only in the configured channel. No channel permissions are changed automatically.

Update the addon before importing. The companion holds invite entries out of Inbox.lua until the installed addon lists `InviteRequests.lua`, so an older addon cannot consume them as unknown actions. Normal bank/announcement entries continue using the existing bridge. Keep the existing bot token private.

## Shared-folder helper setup

Each `sync_helpers` entry in the bot's private config has a helper ID, a random `secret`, an `enabled` flag, an exact `characters` list and one or more local `folders`. Those folders can be under OneDrive or Google Drive for desktop. The bot mirrors its feed to each location and reads the newest authenticated return packet. Providers do not sync to each other on their own; the central bot mirrors the protocol files.

The organiser creates `connection.json` inside each volunteer's individual folder with `helper`, `guild`, `secret` and `characters` matching that private config. Share only that individual folder with its intended recipient, with access to sync/read/write the files. Never share the bot config or parent folder. See the [helper instructions](../sync-helper/README.md).

Configuring the private helper character list queues whitelist grants in the local **officer** inbox. Install/update EPU and log into the officer character, wait for import, then `/reload` once more to save and publish the grants. Alternatively officers can use `/epu synchelper add First Last` or `/epu synchelper remove First Last` for each character. Existing guild ranks are unchanged; unverified alts do not inherit access.

An officer can also run `/epu synchelper rank Chron & Lib` to approve in-game sync for characters with that exact roster rank. Use `rank off` to turn off the rule. Explicit character approvals and removals take precedence. Each volunteer still needs their own connection folder, and the bot must list the characters allowed to use that folder. Guild invite and officer permissions come from their existing settings.

The helper stages only invite requests and new bank requests awaiting approval. Approvals/status changes, officer news and whitelist grants stay on the officer's bridge. Public game bank/request/crafter data and invite outcomes can return through a helper. Officer notes, logs, identity proofs, account preferences and location history are excluded. Confirmed-record revisions win over older snapshots; helper data does not grant in-game approval rights.

Disable an individual helper in the private config and restart the bot to stop accepting its uploads and publish a disabled feed. Remove its in-game character grants as well. Fresh feeds expire after 24 hours; protocol signatures and saved sequence numbers reject modified, wrong-guild or older cloud copies. Both desktop sync clients and the central bot must be running. Cloud sharing cannot be completed until the recipient's provider/account is known.

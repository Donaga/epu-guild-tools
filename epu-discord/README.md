# EPU Discord companion

## Linking and class/rank roles (0.23)

- **Linking by code.** `/link` gives each member a private code. They type `/epu link CODE` in game on any character. Every character on that WoW account links itself when it logs in with EPU 0.23+, and confirmed EPU alts (`/epu main` groups) come along. No officer step. The game only sends a scrambled form of code + character name, so guildmates can't tell from addon data which characters share an account. `/link character:` still asks an officer to approve by hand (`/approve_link`) for anyone who can't use the addon.
- **Roles.** Linked members get a **class role** for each linked character's class and a **rank role** from their main's guild rank, but only for the ranks in `rank_roles` (default Veteran, Member, Initiate). Officer and GM ranks, and your `officer_role`, are never touched. The bot creates any role that doesn't exist yet. If your server already has a **rank** role with the same name (say *Member*), the bot uses it instead of making a duplicate (`"adopt_existing_roles": "rank"`, the default; `"all"` adopts class roles too, `"none"` never adopts). It won't adopt your officer role, a role with moderator permissions (Administrator, Manage Server/Roles/Channels/Messages/Webhooks, Kick, Ban, Timeout, Mention Everyone), another bot's role, or a role above its own; those are reported in the officer log instead. Adopted roles change only for linked members: people who never linked, or unlink, keep what they have. Roles update after each officer save. If a refresh would take roles from more than 5 people (or 20% of linked members) at once, nothing is removed until an officer runs `/roles confirm`.
  - Setup: give the bot **Manage Roles**, then in Server Settings → Roles drag the bot's role **above** the class and rank roles. Turn roles off with `"discord_roles": false` or `"class_roles": false`, or `"rank_roles": []`.
- **Officer log.** Set `officer_log_channel_id` to an officers-only channel for joins, leaves, returns, promotions and demotions, level milestones (`level_milestones`, default 60), new links and link conflicts. A save that suddenly loses over a third of the roster is ignored as a bad read.
- **Commands.** `/whois character` (who plays it, and their other characters), `/chars [member]`, `/main` (pick your main for the rank role; otherwise the in-game `/epu main` is used), `/roles` (officers: status, refresh now, confirm held removals), `/link_suggestions` (officers: link everyone whose Discord name matches an unlinked guild character with one button; needs **Server Members Intent** in the Developer Portal and `"members_intent": true`).

## Shared-folder volunteers and guild invitations (0.18)

See [guild invite setup](../docs/guild-invites.md) and [helper instructions](../sync-helper/README.md). Set `invite_requests_channel_id` and keep `sync_helpers` credentials in the private config. Each helper can have OneDrive and/or Google Drive folder locations; volunteers run the standalone Windows helper, not another copy of this bot. Privileged actions remain on the officer bridge.

## 0.10 identity and recovery changes

Upgrade this companion together with the addon. Old, unverified Discord links are preserved under `legacy_links` in state.json for reference, but no longer authorize requests. Each member uses `/link character:` and an officer verifies the person in game, then runs `/approve_link user: character:`. Verify each character separately. One character cannot belong to multiple Discord accounts; an officer can resolve mistakes with `/revoke_link user: character:`. `/unlink` still removes your own links.

Approval also queues the Discord onboarding checklist step for the next officer login/reload. Existing guild role checks still protect approvals. The companion records link approvals in its local audit and writes a previous-state recovery copy at `state.json.bak` before replacing state. Back up state.json and config.json with the companion stopped; the recovery copy can contain guild information and should stay on the officer PC.

The bot periodically restores Inbox.lua if an addon manager replaced it, and defers writes during an EPU updater install. Discord changes remain queued until the game imports them on login/reload. Partial-delivery counts are shown on request messages and reduce the outstanding shopping quantity.

Connects the **EPU Guild Tools** addon to a Discord channel.

- **Game → Discord:** new guild bank requests are posted to a channel, and each post updates as the request is approved, rejected or filled. Donations get a thank-you post (you can turn this off).
- **Discord → game:** members can `/request` items from Discord. Officers can **Approve** or **Reject** from the request post.
- **Pinned status post:** one "Guild Bank Status" message that the bot edits in place on every refresh. It shows each need's stock (red under half, yellow below target, green stocked), the shopping list, the guild focus professions officers have set (with progress toward each skill goal), gold on hand, open request counts and who holds the stock.
- **Pinned how-to post:** a "How to use the Guild Bank bot" guide, pinned in the request channel and refreshed each time the bot starts. `/help` shows it privately. Turn it off with `"help_post": false`. `addon_url` sets its download link.
- **Bank catalog and quantities:** `/request` offers only items the guild bank currently holds or has stocked before. Choices show banked and available quantities. Sold-out items remain requestable and are marked **Out of stock**; requests needing more stock show **Awaiting restock**. Direct links and IDs must belong to this catalog too. Open requests, including Discord requests not yet imported into WoW, reduce available stock. These are estimates from the latest officer save, not live reservations. Craft requests remain separate. The bot no longer downloads the complete game item list at startup; old `item_db` settings are ignored there.
- **Release announcements:** checks GitHub every 30 minutes and posts when you publish a new release, with download links. `/download` shows the links any time (the updater, the addon zip, and WowUp instructions). Turn announcements off with `"announce_releases": false`.
- **Lookups:** `/needs` shows what the bank is short on. `/bank <search>` shows what it holds. `/requests` lists open requests. `/craft` shows who can make an item, guild crafters first.

## How it works (and the one catch)
WoW addons can't use the internet, so this program runs on **your PC**, next to WoW, and passes messages through two files:

| Direction | File | When it updates |
|---|---|---|
| Game → Discord | `WTF\Account\<you>\SavedVariables\EPUGuild.lua` | WoW only writes this on **/reload** or logout. `/epu save` does a reload. |
| Discord → game | `Interface\AddOns\EPUGuild\Inbox.lua` | WoW only reads this at **login** or **/reload**. |

So it isn't instant. A Discord request shows up in game the next time you /reload or log in. A request made in game shows up in Discord the next time you /reload or log out. Typing `/epu save` before you log off for the night pushes everything at once.

It must run on an **officer's** PC. Members' addons ignore the inbox file, so nobody can forge approvals through it.

## Setup (about 10 minutes, once)

### 1. Create the Discord bot
1. Go to https://discord.com/developers/applications and click **New Application**. Name it, e.g. *EPU Guild Bank*.
2. Open **Bot** → **Reset Token** → copy the token. Keep it secret; it's the bot's password.
3. Open **OAuth2 → URL Generator**:
   - Scopes: `bot` and `applications.commands`
   - Bot permissions: View Channels, Send Messages, Embed Links, Read Message History, Manage Messages (only used to pin the status post), Manage Roles (class and rank roles)
   - Open the generated URL and add the bot to your server.

This needs its own bot. Don't reuse your One Ring bot's token, because two programs can't log in as the same bot.

### 2. Get the IDs
In Discord: **User Settings → Advanced → Developer Mode** on. Then:
- right-click your server icon → **Copy Server ID**
- right-click the channel for requests (e.g. `#guild-bank`) → **Copy Channel ID**

### 3. Configure
Copy `config.example.json` to `config.json` and fill it in:

```json
{
  "token": "your bot token",
  "server_id": "your server ID",
  "channel_id": "your #guild-bank channel ID",
  "officer_role": "Officer",
  "wow_path": "C:\\Program Files (x86)\\World of Warcraft\\_forever_",
  "guild_key": "E Pluribus Unum",
  "account": "",
  "post_donations": true,
  "poll_seconds": 15,
  "status_post": true,
  "status_channel_id": ""
}
```
- `officer_role`: the Discord role allowed to Approve or Reject. Server admins can always do it.
- `feed_channel_id`: where guild milestones go (level-ups every 10 levels, first mounts, profession ranks, big donations, new members). Blank means the request channel. Set `post_milestones` to `false` to turn them off.
- `announce_channel_id`: where announcements go, both ones posted in game and ones posted with `/announce`. Blank means the request channel. A `#announcements` channel works well.
- `import_channel_id`: an existing Discord announcements channel to copy into the game. New posts there (and ones from the last `import_days` days when the bot starts) show up in the addon's News page and pop up in game for everyone; edits and deletions follow. The first line of a post becomes the title. Set `import_officers_only` to `true` if people other than officers can post in that channel. **This needs the Message Content Intent:** Developer Portal > your application > Bot > Privileged Gateway Intents > turn on *Message Content Intent* > Save. The bot also needs *View Channel* and *Read Message History* in that channel. Leave it blank to turn copying off.
- `post_motd`: when the in-game guild message of the day changes, post it to the announcements channel (default on).
- `status_channel_id`: where the pinned status post lives. Leave it blank to use the request channel, or point it at a read-only `#bank-status` channel. Set `status_post` to `false` to turn it off. If you delete the post, the bot makes and pins a new one at the next refresh.
  When Discord updates wait two minutes for game sync, this post shows **WoW reload would help**. A companion user or eligible helper can log in or reload when convenient. EPU reminds the importer to reload again or log out to save the results back.
- `account`: leave blank unless you have several WoW accounts. Otherwise set it to the folder name under `WTF\Account`.

### 4. Run it
Double-click **start.bat**. The first run creates a private Python environment and installs `discord.py`. You need Python 3.10+ from python.org; you probably have it already for your One Ring bot.

Leave the window open while you play. It should say `Logged in as ... Watching ...EPUGuild.lua`.

If it says it can't write **Inbox.lua**, Windows is blocking writes to `Program Files`. Right-click `...\_forever_\Interface\AddOns\EPUGuild` → **Properties → Security → Edit**, select **Users**, and tick **Modify**. Or run start.bat once as administrator.

## Using it
Sold-out weapons and armor are excluded from `/bank` and `/request`; other
classified supplies can remain available for restock requests. Their history is
kept, so gear returns automatically when stocked again. If historical item
categories are missing, update the addon and `/reload` on the officer character
to export metadata. Existing requests are preserved.

**Members (in Discord)**
- `/link` with your character's full name, e.g. `/link character:Tyler Stonefist`. The list autocompletes from the guild roster, and a first name works if only one member has it. Your first link is your main.
  - If the addon already knows your alts (they've logged in with it), linking one character links all of them.
  - Otherwise `/link` each alt yourself. `/unlink` removes one.
- `/request item:<start typing> qty:5 note:for bags character:<alt>`. `character` is optional and picks which of your characters gets the mail (default: your main).
- The item list comes from items the guild has seen. You can also paste a Wowhead link or item ID.
- `/needs`, `/bank search:cloth`, `/requests`

**Officers**
- Click **Approve** or **Reject** (with an optional reason) on any pending request post.
- In game, Discord requests appear on the Requests tab marked "(via Discord)". Approve, Reject or Fill them as usual.
- Mailing the item still marks it filled automatically. The Discord post updates after your next `/epu save` or logout.

## Trying it without WoW
`testkit.py` builds a fake WoW folder with you and a few made-up guildmates, so you can test the whole Discord side before you can log in:

```
.venv\Scripts\python testkit.py setup "Donlock Gaeilge"
.venv\Scripts\python testkit.py use        (then restart the bot)
.venv\Scripts\python testkit.py show       (and request / approve / fill / donate / stock / need / gold / reload)
.venv\Scripts\python testkit.py unuse      (back to real WoW; restart the bot)
```
`reload` plays the part of an officer typing /reload: it applies anything done in Discord. Run `testkit.py` with no arguments for the full list.

## Files
- `bot.py`: the Discord bot
- `epu_core.py`: reads and writes the addon's files (no Discord code)
- `state.json`: created automatically; holds linked characters, which Discord message belongs to which request, and queued Discord actions. Back it up if you move PCs.

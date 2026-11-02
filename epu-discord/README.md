# EPU Discord companion

Connects the **EPU Guild Tools** addon to a Discord channel.

- **Game → Discord:** new guild bank requests are posted to a channel, and each post updates as the request is approved, rejected or filled. Donations get a thank-you post (you can turn this off).
- **Discord → game:** members can `/request` items from Discord. Officers can **Approve** or **Reject** from the request post.
- **Lookups:** `/needs` shows what the bank is short on. `/bank <search>` shows what it holds. `/requests` lists open requests.

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
   - Bot permissions: View Channels, Send Messages, Embed Links, Read Message History
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
  "poll_seconds": 15
}
```
- `officer_role`: the Discord role allowed to Approve or Reject. Server admins can always do it.
- `account`: leave blank unless you have several WoW accounts. Otherwise set it to the folder name under `WTF\Account`.

### 4. Run it
Double-click **start.bat**. The first run creates a private Python environment and installs `discord.py`. You need Python 3.10+ from python.org; you probably have it already for your One Ring bot.

Leave the window open while you play. It should say `Logged in as ... Watching ...EPUGuild.lua`.

If it says it can't write **Inbox.lua**, Windows is blocking writes to `Program Files`. Right-click `...\_forever_\Interface\AddOns\EPUGuild` → **Properties → Security → Edit**, select **Users**, and tick **Modify**. Or run start.bat once as administrator.

## Using it
**Members (in Discord)**
- `/link character:Tyler` once, so requests are filed under your character.
- `/request item:<start typing> qty:5 note:for bags`. The item list comes from items the guild has seen. You can also paste a Wowhead link or item ID.
- `/needs`, `/bank search:cloth`, `/requests`

**Officers**
- Click **Approve** or **Reject** (with an optional reason) on any pending request post.
- In game, Discord requests appear on the Requests tab marked "(via Discord)". Approve, Reject or Fill them as usual.
- Mailing the item still marks it filled automatically. The Discord post updates after your next `/epu save` or logout.

## Files
- `bot.py`: the Discord bot
- `epu_core.py`: reads and writes the addon's files (no Discord code)
- `state.json`: created automatically; holds linked characters, which Discord message belongs to which request, and queued Discord actions. Back it up if you move PCs.

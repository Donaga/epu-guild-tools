# EPU Guild Tools

Guild bank and guild helper tools for **E Pluribus Unum** on WoW: Forever.

| Folder | What it is |
|---|---|
| [`EPUGuild/`](EPUGuild/) | The WoW addon. Everyone in the guild installs it. See its [README](EPUGuild/README.md). |
| [`epu-discord/`](epu-discord/) | Discord companion bot. One officer runs it. See its [README](epu-discord/README.md). |
| [`updater/`](updater/) | One-click updater for guildmates (Windows). Ships as `EPU-Updater-x.y.z.zip` on each release. |
| [`tests/`](tests/) | Simulators that run the addon outside WoW, with stubbed game functions, plus the Discord file round trip. |

## Getting the addon (guildmates)
- **Easiest:** download `EPU-Updater-x.y.z.zip` from the latest [Release](../../releases/latest), unzip it somewhere you'll keep it, and double-click **Update EPU Guild Tools**. It finds WoW: Forever, installs the addon, and updates it whenever you run it. Double-click **Update automatically at startup** once and it keeps itself current.
- **WowUp:** Get Addons, then Install from URL, and paste this repo's link.
- **By hand:** unzip `EPUGuild-x.y.z.zip` into `World of Warcraft\_forever_\Interface\AddOns\`, then `/reload`.

In game, the addon tells you when a guildmate has a newer version. On Discord, the bot announces each release and `/download` gives the links.

## Making a release
1. Commit changes to `main`. The **Tests** workflow runs on every push.
2. Add a line to `CHANGELOG.md`.
3. On GitHub: **Releases → Draft a new release**. Type a new tag such as `v0.4.0` (target `main`), paste the changelog lines, then **Publish release**.

The **Release** workflow then runs the tests, stamps the version into the `.toc`, and attaches `EPUGuild-0.4.0.zip`, `EPU-Updater-0.4.0.zip`, `epu-discord-0.4.0.zip` and WowUp's `release.json` to the release. It takes about a minute. Within 30 minutes the Discord bot announces it, and guildmates' updaters pick it up the next time they run.

The repo must be **public** for the updater and WowUp to download releases.

## Running the tests locally
```
pip install lupa "discord.py>=2.3"
python tests/test_sync.py
python tests/test_discord.py
python tests/test_itemdb.py
python tests/test_ui.py
```

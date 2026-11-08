# EPU Guild Tools

Guild bank and guild helper tools for **E Pluribus Unum** on WoW: Forever.

| Folder | What it is |
|---|---|
| [`EPUGuild/`](EPUGuild/) | The WoW addon. Everyone in the guild installs it. See its [README](EPUGuild/README.md). |
| [`epu-discord/`](epu-discord/) | Discord companion bot. One officer runs it. See its [README](epu-discord/README.md). |
| [`updater/`](updater/) | One-click updater for guildmates (Windows). Ships as `EPU-Updater-x.y.z.zip` on each release. |
| [`tests/`](tests/) | Simulators that run the addon outside WoW, with stubbed game functions, plus the Discord file round trip. |

Guild activities include quest help, dungeon groups, voluntary helpers and starter-kit templates. Officers can combine a member’s approved bank requests into one mail draft.

The event calendar, selected-quest matching, returning-player catch-up and private notification controls are available under Guild activities.

Use `/epu guides` for **Your guides**: Forever class, leveling, talent and profession
sources filtered to this character's class, level and learned profession skills.
Choose a talent focus in Options if the game cannot identify one. Save sources,
keep private notes and mark the current bracket reviewed. Best-fit sources show
by default; optional alternatives retain beta/pre-launch labels. Short original
summaries are available in game; **Read full guide** lets you copy a source URL
to your browser. Notes and reading progress are never synced to the guild.
See [guide maintenance](docs/guide-sources.md) for the source selection, review
dates and weekly external review process. Updates reach players through normal
addon releases; the game does not download guides in the background.

## Getting the addon (guildmates)
- **Recommended: CurseForge.** Install the free [CurseForge app](https://www.curseforge.com/download/app), open **https://www.curseforge.com/wow/addons/epu-guild-tools** and click **Install**, then pick your *Forever* install. The app keeps it updated (turn on auto-update in its World of Warcraft settings). The project is unlisted, so use the link rather than searching.
- **Updater:** download `EPU-Updater-x.y.z.zip` from the latest [Release](../../releases/latest), unzip it somewhere you'll keep it, and double-click **Update EPU Guild Tools**. It finds WoW: Forever, installs the addon, and updates it whenever you run it. Double-click **Update automatically at startup** once and it keeps itself current.
- **WowUp:** pick your *Forever* install from the dropdown at the top, then Get Addons > Install from URL, paste `https://github.com/Donaga/epu-guild-tools` and click Install. WowUp updates it like any other addon.
- **By hand:** unzip `EPUGuild-x.y.z.zip` into `World of Warcraft\_forever_\Interface\AddOns\`, then `/reload`.

Use just one of these; each would try to update the same folder. In game, the addon tells you when a guildmate has a newer version. On Discord, the bot announces each release and `/download` gives the links.

Every GitHub release also uploads to CurseForge automatically (see *Making a release*); CurseForge reviews each file before the app offers it, usually within a day.

## Making a release
1. Commit changes to `main`. The **Tests** workflow runs on every push.
2. Add a line to `CHANGELOG.md`.
3. On GitHub: **Releases → Draft a new release**. Type a new tag such as `v0.4.0` (target `main`), paste the changelog lines, then **Publish release**.

The **Release** workflow then runs the tests, stamps the version into the `.toc`, and attaches `EPUGuild-0.4.0.zip`, `EPU-Updater-0.4.0.zip`, `epu-discord-0.4.0.zip` and WowUp's `release.json` to the release. It takes about a minute. Within 30 minutes the Discord bot announces it, and guildmates' updaters pick it up the next time they run.

The repo must be **public** for the updater and WowUp to download releases.

**CurseForge (optional):** each release can also upload to CurseForge. Create the project once on CurseForge, then in GitHub go to Settings > Secrets and variables > Actions and add a **secret** `CF_API_KEY` (an API token from your CurseForge author account) and a **variable** `CURSEFORGE_PROJECT_ID` (the numeric Project ID from the project page). Until both are set, the upload step just skips. The text in `media/curseforge-description.md` and the logo in `media/epu-logo.png` are ready for the project page.

## Running the tests locally
```
pip install lupa "discord.py>=2.3"
python tests/test_sync.py
python tests/test_discord.py
python tests/test_itemdb.py
python tests/test_ui.py
python tests/test_casual.py
python tests/test_community.py
python tests/test_quest_matching.py
python tests/test_member_mail.py
python tests/test_guild.py
python tests/test_autosync.py
python tests/test_bankalt.py
python tests/test_reliability.py
```

On Windows, run `./tests/test_updater.ps1 -ScratchRoot <existing temporary folder>` to verify staged installs and inbox preservation.

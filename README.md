# EPU Guild Tools

Guild bank and guild helper tools for **E Pluribus Unum** on WoW: Forever.

| Folder | What it is |
|---|---|
| [`EPUGuild/`](EPUGuild/) | The WoW addon. Everyone in the guild installs it. See its [README](EPUGuild/README.md). |
| [`epu-discord/`](epu-discord/) | Discord companion bot. One officer runs it. See its [README](epu-discord/README.md). |
| [`updater/`](updater/) | One-click updater for guildmates (Windows). Ships as `EPU-Updater-x.y.z.zip` on each release. |
| [`tests/`](tests/) | Simulators that run the addon outside WoW, with stubbed game functions, plus the Discord file round trip. |

Guild activities include scheduled dungeons, leveling, quest help, fishing, professions, farming and other group plans, with a month picker and volunteer signups. Quick-help boards, voluntary helpers and starter kits remain available. Officers can combine a member’s approved bank requests into one mail draft.

Discord guild invite requests use `/guildinvite` with required first/last-name fields, or a standalone `Character: First Last` line in the configured channel. Eligible inviters get an in-game alert and manual Invite button. Game-confirmed invitations return a ✅ to the original Discord request. See [guild invite requests](docs/guild-invites.md).

The [Windows sync helper](sync-helper/README.md) lets whitelisted characters relay invite/new pending bank requests and return filtered public game snapshots to the existing bot through shared OneDrive or Google Drive folders. No Discord token or rank change is needed. Officer approvals remain separate; login or `/reload` is still required. Each volunteer has an individual connection folder, and the bot can mirror it to both providers.

Use `/epu activities` or `/epu calendar` for the activity agenda. Optional WoW guild-calendar copies let members without EPU see an event. Open the linked native event to refresh its attendees into a combined signup view, or explicitly send your own response to both. Native snapshots expire after three minutes; event edits/cancellations remain separate. See [Activities and calendar](docs/activities-calendar.md) for publishing, linking and limitations.

Bank requests are limited to items currently or previously stocked by the guild
bank. The Bank page and request pickers show quantities; sold-out items remain
available for waiting requests. Open bank requests and approved bank-paid craft
materials reduce the displayed available count. Requests needing more stock say
**Awaiting restock**. Counts are estimates from the latest shared bank snapshots,
not live reservations; approval and delivery remain manual. Craft requests are
separate. New stock-history metadata retains item IDs after depletion/retirement;
existing snapshots and recorded bank donations seed history, but previously lost
history cannot be reconstructed. Upgrade the Discord companion too for matching
request rules, then sync and `/reload` on the bank/officer character.

Sold-out weapons and armor are hidden from the bank catalog and request pickers;
they reappear when restocked. Other classified supplies remain available for
restock requests. Historical items without category metadata wait for item data
instead of appearing as unknown equipment. Bank filters combine item category,
**In stock**, **Available now**, **Awaiting restock** and quality; **Reset** clears
the filters and search. Available now subtracts open requests; In stock shows
physically recorded quantities even when already requested.

The event calendar, selected-quest matching, returning-player catch-up and private notification controls are available under Guild activities.

Guild map markers now use circular class icons. `/epu map` also offers round dots.
For the addon button, `/epu button` offers position presets, spacing, lock and
visibility controls. `/epu minimap reset` recovers it if hidden or misplaced.
The button follows the actual minimap edge and has a larger drag target.
The 0.16 rollout enables outdoor location sharing, both map displays and class icons
once for everyone who updates, including installations with previous off settings.
Subsequent player choices are preserved. Members need the update and `/reload`;
this cannot reset installations that have not updated. Use `/epu sharelocation off`
or the map controls to stop sharing. Location history is not saved.

Open **Member tools → Your guides** or type `/epu guides` for Forever class, leveling, talent and profession
sources filtered to this character's class, level and learned profession skills.
Choose a talent focus in Settings if the game cannot identify one. The home screen
shows one task per topic, such as **Level my Paladin** or **Level Blacksmithing**.
Open a task for its recommended guide; **Other sources** holds alternatives and
**Source details / notes** holds review metadata and private progress. Save sources,
keep private notes and mark the current bracket reviewed. Best-fit sources show
by default; alternatives retain beta/pre-launch labels. Short original
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

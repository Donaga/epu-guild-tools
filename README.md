# EPU Guild Tools

Guild bank and guild helper tools for **E Pluribus Unum** on WoW: Forever.

| Folder | What it is |
|---|---|
| [`EPUGuild/`](EPUGuild/) | The WoW addon. Everyone in the guild installs it. See its [README](EPUGuild/README.md). |
| [`epu-discord/`](epu-discord/) | Discord companion bot. One officer runs it. See its [README](epu-discord/README.md). |
| [`tests/`](tests/) | Simulators that run the addon outside WoW, with stubbed game functions, plus the Discord file round trip. |

## Getting the addon
Download `EPUGuild-x.y.z.zip` from the latest [Release](../../releases/latest). Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, then `/reload`.

## Making a release
1. Commit changes to `main`. The **Tests** workflow runs on every push.
2. Add a line to `CHANGELOG.md`.
3. On GitHub: **Releases → Draft a new release**. Type a new tag such as `v0.4.0` (target `main`), paste the changelog lines, then **Publish release**.

The **Release** workflow then runs the tests, stamps the version into the `.toc`, and attaches `EPUGuild-0.4.0.zip` and `epu-discord-0.4.0.zip` to the release. It takes about a minute.

## Running the tests locally
```
pip install lupa "discord.py>=2.3"
python tests/test_sync.py
python tests/test_discord.py
```

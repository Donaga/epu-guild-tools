"""Release announcements wait until CurseForge has approved the new file, so the
CurseForge app already offers the update when guildmates read the post. The
version only counts as announced once it's posted."""
import asyncio
import importlib
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
import epu_core as core

failed = 0


def check(name, ok):
    global failed
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok


# --- Reading CurseForge -------------------------------------------------------------------
check("the slug comes from curseforge_url", core.curseforge_slug("https://www.curseforge.com/wow/addons/epu-guild-tools") == "epu-guild-tools")
check("a non-CurseForge URL has no slug", core.curseforge_slug("https://example.com/x") is None)
check("a display name names its version", core.mentions_version("EPU Guild Tools 0.32.0", "0.32.0"))
check("a zip name names its version", core.mentions_version("EPUGuild-0.32.0.zip", "0.32.0"))
check("0.32.01, 10.32.0 and 0.32.0.1 are other versions",
      not any(core.mentions_version(s, "0.32.0") for s in ("EPU Guild Tools 0.32.01", "10.32.0", "EPUGuild-0.32.0.1.zip")))

api = {"data": [
    {"displayName": "EPU Guild Tools 0.32.0", "fileName": "EPUGuild-0.32.0.zip", "fileStatus": 3, "isAvailable": False},
    {"displayName": "EPU Guild Tools 0.31.1", "fileName": "EPUGuild-0.31.1.zip", "fileStatus": 4, "isAvailable": True},
]}
files = core.curseforge_files_from_api(api)
check("CurseForge's API: a file still under review doesn't count", not core.curseforge_has_version(files, "0.32.0"))
check("CurseForge's API: an approved file counts", core.curseforge_has_version(files, "0.31.1"))
api["data"][0].update(fileStatus=4, isAvailable=True)
check("CurseForge's API: once approved, the new version counts",
      core.curseforge_has_version(core.curseforge_files_from_api(api), "0.32.0"))
widget = {"id": 1, "files": [{"id": 9, "display": "EPU Guild Tools 0.31.1", "name": "EPUGuild-0.31.1.zip", "type": "release"}]}
check("CFWidget: only what's listed counts",
      core.curseforge_has_version(core.curseforge_files_from_widget(widget), "0.31.1")
      and not core.curseforge_has_version(core.curseforge_files_from_widget(widget), "0.32.0"))
check("odd responses read as no files", core.curseforge_files_from_api({"data": None}) == []
      and core.curseforge_files_from_widget({"files": [5, None]}) == [] and core.curseforge_files_from_widget(None) == [])

base = {"curseforge_url": "https://www.curseforge.com/wow/addons/epu-guild-tools"}
check("with no key, the public mirror is used", core.curseforge_source(base) == "widget")
check("key + project ID: CurseForge's own API",
      core.curseforge_source({**base, "curseforge_api_key": "k", "curseforge_project_id": "123"}) == "api")
check("a key without a project ID falls back to the mirror", core.curseforge_source({**base, "curseforge_api_key": "k"}) == "widget")
check("announce_after_curseforge false: no waiting", core.curseforge_source({**base, "announce_after_curseforge": False}) is None)
check("no CurseForge page: no waiting", core.curseforge_source({"curseforge_url": ""}) is None)

check("already announced: nothing", core.release_step("v0.32.0", "v0.32.0", True, True, True) == "none")
check("first run: remembered, not posted", core.release_step(None, "v0.32.0", True, True, False) == "remember")
check("announcements off: remembered", core.release_step("v0.31.1", "v0.32.0", False, True, True) == "remember")
check("not approved yet: wait", core.release_step("v0.31.1", "v0.32.0", True, True, False) == "wait")
check("CurseForge unreachable: wait", core.release_step("v0.31.1", "v0.32.0", True, True, None) == "wait")
check("approved: announce", core.release_step("v0.31.1", "v0.32.0", True, True, True) == "announce")
check("not gated: announce at once", core.release_step("v0.31.1", "v0.32.0", True, False, None) == "announce")

# --- The companion's release check -----------------------------------------------------
cfgdir = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "wow_path": tempfile.mkdtemp()},
          open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py"):
    shutil.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check("announcements default on, waiting for CurseForge", bot.cfg["announce_releases"] is True
      and bot.cfg["announce_after_curseforge"] is True and bot.core.curseforge_source(bot.cfg) == "widget")

sent = []
class FakeChannel:
    async def send(self, **kw):
        sent.append(kw["embed"])
bot.client.get_channel = lambda cid: FakeChannel()
gh = {"tag": "v0.32.0", "version": "0.32.0", "page": "https://github.com/x/releases/v0.32.0", "addon": "a", "updater": "u",
      "notes": "Notes", "draft": False, "prerelease": False}
cf = {"files": [{"display": "EPU Guild Tools 0.31.1", "name": "EPUGuild-0.31.1.zip"}], "fail": False, "calls": 0}
bot.core.fetch_latest_release = lambda repo, timeout=30: dict(gh)
def fake_cf(cfg, timeout=30):
    cf["calls"] += 1
    if cf["fail"]:
        raise OSError("unreachable")
    return cf["files"]
bot.core.fetch_curseforge_files = fake_cf
bot.state.data["last_release"] = "v0.31.1"
bot.state.data.pop("release_waiting", None)

asyncio.run(bot.check_release())
check("a new GitHub release under review isn't posted", sent == [] and bot.state.data["last_release"] == "v0.31.1")
check("it's noted as waiting", bot.state.data.get("release_waiting") == "v0.32.0")
cf["fail"] = True
asyncio.run(bot.check_release())
check("CurseForge unreachable: still not posted or marked", sent == [] and bot.state.data["last_release"] == "v0.31.1")
cf["fail"] = False
cf["files"].insert(0, {"display": "EPU Guild Tools 0.32.0", "name": "EPUGuild-0.32.0.zip"})
asyncio.run(bot.check_release())
check("once approved, it's posted once", len(sent) == 1 and sent[0].title == "EPU Guild Tools 0.32.0 is out")
check("the footer says it's live on CurseForge", "live on CurseForge" in sent[0].footer.text)
check("and marked announced", bot.state.data["last_release"] == "v0.32.0" and "release_waiting" not in bot.state.data)
check("saved in state.json", json.load(open(os.path.join(cfgdir, "state.json")))["last_release"] == "v0.32.0")
calls = cf["calls"]
asyncio.run(bot.check_release())
check("not posted again, and CurseForge isn't asked again", len(sent) == 1 and cf["calls"] == calls)

gh.update(tag="v0.32.1", version="0.32.1")
bot.cfg["announce_after_curseforge"] = False
asyncio.run(bot.check_release())
check("announce_after_curseforge false posts at once", len(sent) == 2 and "approves it" in sent[1].footer.text)
gh.update(tag="v0.32.2", version="0.32.2")
bot.cfg["announce_after_curseforge"] = True
bot.cfg["announce_releases"] = False
asyncio.run(bot.check_release())
check("announcements off: remembered without a post or a CurseForge check",
      len(sent) == 2 and bot.state.data["last_release"] == "v0.32.2" and cf["calls"] == calls)
bot.cfg["announce_releases"] = True
bot.state.data.pop("last_release")
gh.update(tag="v0.32.3", version="0.32.3")
asyncio.run(bot.check_release())
check("first run remembers the current release without a post", len(sent) == 2 and bot.state.data["last_release"] == "v0.32.3")

print("Release announcement checks:", failed, "failed")
sys.exit(bool(failed))

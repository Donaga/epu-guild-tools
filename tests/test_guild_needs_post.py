"""Daily "guild needs" post: the Discord companion lists guildmates' needed mats."""
import asyncio
import importlib
import json
import os
import shutil
import sys
import tempfile
import types
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
import epu_core as core

WOW = tempfile.mkdtemp().replace(os.sep, "/")
SV = WOW + "/WTF/Account/ACCT/SavedVariables/EPUGuild.lua"
os.makedirs(os.path.dirname(SV), exist_ok=True)
os.makedirs(WOW + "/Interface/AddOns/EPUGuild", exist_ok=True)

for n in ["Chris Baker", "Tyler Baker", "Pip Baker", "Chris Stone"]:
    clients[n] = Client(n)
tick(20)
A = clients["Chris Baker"]   # the officer whose PC runs the companion
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in clients.values()), timeout=90)

# --- Members add materials in game; the officer's copy reaches SavedVariables -------------
clients["Tyler Baker"].ex("""
local g = __ns.G()
g.recipes["Tyler Baker"] = {t = __now, profs = {Tailoring = {rank = 75, items = {2996}}}}
g.mats["item:2996"] = {t = __now, r = {2589, 2}}
""")
clients["Tyler Baker"].ex('SlashCmdList.EPUGUILD("mats add " .. __link(2589) .. " 20")')
clients["Tyler Baker"].ex('SlashCmdList.EPUGUILD("mats add " .. __link(4306) .. " 5 Tailoring")')
clients["Pip Baker"].ex('SlashCmdList.EPUGUILD("mats add " .. __link(2589) .. " 10 Tailoring")')
clients["Chris Stone"].ex('SlashCmdList.EPUGUILD("mats add " .. __link(14047))')
tick(5)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"] ~= nil and __ns.G().neededMats["Pip Baker"] ~= nil '
                        'and __ns.G().neededMats["Chris Stone"] ~= nil'), timeout=60)
# A list nobody has refreshed for a month, and one from someone who left the guild: neither is posted.
A.ex("""
local s = __ns.G().neededMats
s["Newbie Stone"] = {who = "Newbie Stone", t = __now - 31 * 86400, i = {[2996] = {n = 3}}}
s["Gone Away"] = {who = "Gone Away", t = __now, i = {[2996] = {n = 7}}}
""")
A.ex("__ns.CacheItemNames()")
A.ex(f'__dumpSV("{SV}")')
NOW = A.ev("__now")

gd = core.load_guild_data(SV, "E Pluribus Unum")
check("item names include needed mats (Silk Cloth only appears there)", gd.item_name(4306) == "Silk Cloth")
rows = gd.needed_mats(NOW)
by_id = {r["id"]: r for r in rows}
check("one row per material (%s)" % sorted(by_id), sorted(by_id) == [2589, 4306, 14047])
linen = by_id.get(2589) or {}
check("amounts add up and the bigger ask is first",
      linen.get("total") == 30 and [(w["who"], w["n"]) for w in linen.get("who", [])] == [("Tyler Baker", 20), ("Pip Baker", 10)])
check("profession comes from the entries", linen.get("prof") == "Tailoring" and by_id[14047]["prof"] is None)
check("the material most people need is first", rows[0]["id"] == 2589)
check("stale lists and ex-members are left out", 2996 not in by_id)
check("an entry with no amount counts as one person, no total", by_id[14047]["total"] == 0 and by_id[14047]["who"][0]["n"] == 0)

groups, left = core.needed_mats_groups(rows)
check("grouped by profession, Other last (%s)" % groups, [p for p, _ in groups] == ["Tailoring", "Other"] and left == 0)
check("lines are short: name, total, who (%s)" % groups[0][1],
      groups[0][1][0] == "**Linen Cloth** x30: Tyler Baker (20), Pip Baker (10)" and groups[1][1] == ["**Runecloth**: Chris Stone"])
many = [{"id": i, "name": f"Mat {i}", "total": 0, "prof": None, "who": [{"who": f"P{j}", "n": 0, "p": None} for j in range(5)]}
        for i in range(1, 21)]
g2, left2 = core.needed_mats_groups(many, max_items=15)
check("long lists stop at the cap and say how many more", sum(len(l) for _, l in g2) == 15 and left2 == 5)
check("long name lists end with +N more", g2[0][1][0].endswith("P0, P1, P2, +2 more"))
check("odd records don't break the read", core.GuildData({"guilds": {"E": {"members": {1: "A B"}, "neededMats": {
    "A B": {"who": "A B", "t": "x", "i": {}}, "C D": 5, 7: {}}}}}).needed_mats(NOW) == [])

# --- The companion: config, schedule and the post ---------------------------------------
cfgdir = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "feed_channel_id": "3", "wow_path": WOW,
           "guild_needs_post": True, "guild_needs_time": "18:30"}, open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py"):
    shutil.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check("channel falls back to the milestones channel", bot.cfg["guild_needs_channel_id"] == "3")
check("clock times parse", bot.parse_clock("18:30") == (18, 30) and bot.parse_clock("6:05") == (6, 5)
      and bot.parse_clock("25:00") is None and bot.parse_clock("6pm") is None and bot.parse_clock("18:5") is None)

sent, fail = [], []
class FakeChannel:
    async def send(self, **kw):
        if fail:
            raise RuntimeError("Discord is down")
        sent.append(kw["embed"])
seen_ids = []
bot.client.get_channel = lambda cid: (seen_ids.append(cid), FakeChannel())[1]
bot.read_latest = lambda force=False: core.load_guild_data(SV, "E Pluribus Unum")
bot.state.data.pop("guild_needs_day", None)

def at(hh, mm, day=24):
    # The game clock in the test is fixed, so give "now" a matching timestamp for the 30-day check.
    d = datetime(2026, 11, day, hh, mm)
    return types.SimpleNamespace(date=d.date, hour=hh, minute=mm, timestamp=lambda: NOW)

check("nothing before the set time", asyncio.run(bot.post_guild_needs(at(18, 29))) is False and sent == [])
fail.append(1)
check("a failed send is retried", asyncio.run(bot.post_guild_needs(at(18, 30))) is False and "guild_needs_day" not in bot.state.data)
fail.clear()
check("posts at the set time", asyncio.run(bot.post_guild_needs(at(18, 31))) is True and len(sent) == 1 and seen_ids[-1] == 3)
e = sent[0]
check("embed has the groups (%s)" % [f.name for f in e.fields], e.title == "Guild needs" and [f.name for f in e.fields] == ["Tailoring", "Other"]
      and "Tyler Baker (20)" in e.fields[0].value)
check("only once a day", asyncio.run(bot.post_guild_needs(at(21, 0))) is False and len(sent) == 1)
check("again the next day", asyncio.run(bot.post_guild_needs(at(18, 30, day=25))) is True and len(sent) == 2)
check("the day is remembered in state.json", json.load(open(os.path.join(cfgdir, "state.json")))["guild_needs_day"] == "2026-11-25")

A.ex("__ns.G().neededMats = {}")
A.ex(f'__dumpSV("{SV}")')
check("no post when nobody needs anything, and the day counts as done",
      asyncio.run(bot.post_guild_needs(at(18, 30, day=26))) is False and len(sent) == 2 and bot.state.data["guild_needs_day"] == "2026-11-26")
check("the lookup command's embed is empty too", bot.guild_needs_embed(bot.read_latest(), NOW) is None)
bot.cfg["guild_needs_post"] = False
check("off means off", asyncio.run(bot.post_guild_needs(at(18, 30, day=27))) is False and bot.state.data["guild_needs_day"] == "2026-11-26")
check("help mentions /neededmats", any("/neededmats" in f.value for f in bot.help_embed().fields))

check("no addon runtime errors", all((c.ev("__errors") or 0) == 0 for c in clients.values()))
print(f"{check.failed} failed" if check.failed else "all passed")
sys.exit(1 if check.failed else 0)

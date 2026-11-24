"""Weekly leveling board: levels each guildmate gained this week and last week.

The addon reads it from the level history every PC keeps as it reads the guild
roster (g.lvlLog), shows it in a window opened from Member tools or with
/epu levelboard, and the Discord companion posts last week's board once a week
from the officer PC's save.
"""
import asyncio
import importlib
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
import epu_core as core

WOW = tempfile.mkdtemp().replace(os.sep, "/")
SV = WOW + "/WTF/Account/ACCT/SavedVariables/EPUGuild.lua"
os.makedirs(os.path.dirname(SV), exist_ok=True)
os.makedirs(WOW + "/Interface/AddOns/EPUGuild", exist_ok=True)

A = Client("Chris Baker")
clients[A.name] = A
tick(20)
DAY = 86400

# --- Weeks start on Monday at midnight on this PC's clock -------------------------------
NOW = A.ev("__now")
WS = A.ev("__ns.WeekStart(__now)")
LW = WS - 7 * DAY
check("the week starts on a Monday at 00:00", A.ev(f'date("*t", {WS}).wday') == 2 and A.ev(f'date("*t", {WS}).hour') == 0
      and A.ev(f'date("*t", {WS}).min') == 0)
check("now is inside that week", WS <= NOW < WS + 7 * DAY)
check("a Monday's week starts that day", A.ev(f"__ns.WeekStart({WS} + 3600)") == WS
      and A.ev(f"__ns.WeekStart({WS} - 1)") == LW)
check("Python agrees on when the week starts", datetime.fromtimestamp(WS).weekday() == 0
      and datetime.fromtimestamp(WS).hour == 0)

# --- Level spans ----------------------------------------------------------------------------
span = lambda log, a, b: tuple(A.ev(f"{{__ns.LevelSpan({log}, {a}, {b})}}").values())
check("start is the last level before the week, end the last level in it",
      span("{100, 10, 120, 11, 200, 12, 300, 15}", 150, 400) == (11, 15))
check("someone first seen during the week starts where they were first seen",
      span("{200, 3, 300, 7}", 150, 400) == (3, 7))
check("levels after the week don't count", span("{100, 10, 500, 20}", 150, 400) == (10, 10))
check("a history that starts after the week has nothing", A.ev("__ns.LevelSpan({500, 5}, 150, 400) == nil"))
check("Python reads spans the same way", core.level_span({1: 100, 2: 10, 3: 120, 4: 11, 5: 200, 6: 12, 7: 300, 8: 15}, 150, 400) == (11, 15)
      and core.level_span([200, 3, 300, 7], 150, 400) == (3, 7) and core.level_span([500, 5], 150, 400) == (None, None)
      and core.level_span("junk", 0, 1) == (None, None) and core.level_span([1, "x", 2, 4], 0, 3) == (4, 4))

# --- The board ------------------------------------------------------------------------------
# Roster levels match each history's latest, so roster updates during the test add nothing.
A.ex('__rosterExtra["Tyler Baker"] = {16}; __rosterExtra["Pip Baker"] = {31}; __rosterExtra["Newbie Stone"] = {8}; __rosterExtra["Chris Stone"] = {60}')
A.ex(f"""
local g = __ns.GuildStore()
g.lvlLog = {{
  ["Tyler Baker"]  = {{ {LW} - 3 * 86400, 10, {LW} + 86400, 12, {WS} + 3600, 15, {WS} + 7200, 16 }},
  ["Pip Baker"]    = {{ {LW} - 10 * 86400, 30, {WS} + 3 * 3600, 31 }},
  ["Newbie Stone"] = {{ {WS} + 3600, 1, {WS} + 5 * 3600, 8 }},
  ["Chris Stone"]  = {{ {LW} - 86400, 60 }},
  ["Gone Away"]    = {{ {WS} + 3600, 5, {WS} + 7200, 9 }},
}}
""")
def board(which):
    A.ex(f'__b = __ns.LevelingBoard("{which}")')
    n = A.ev("#__b.rows")
    return [(A.ev(f"__b.rows[{i}].name"), A.ev(f"__b.rows[{i}].from"), A.ev(f"__b.rows[{i}].to"), A.ev(f"__b.rows[{i}].gained"))
            for i in range(1, n + 1)]
this = board("this")
check("this week: most levels first, ex-members and no-gainers left out (%s)" % this,
      this == [("Newbie Stone", 1, 8, 7), ("Tyler Baker", 12, 16, 4), ("Pip Baker", 30, 31, 1)])
check("this week's total", A.ev("__b.total") == 12 and A.ev("__b.from") == WS)
last = board("last")
check("last week runs Monday to Monday (%s)" % last, last == [("Tyler Baker", 10, 12, 2)]
      and A.ev("__b.from") == LW and A.ev("__b.to") == WS)

# --- Level history keeps three weeks ------------------------------------------------------
def track(at, name, level):
    A.ex(f"""local real = __ns.Now; __ns.Now = function() return {at} end
    __ns.TrackRoster({{ ["{name}"] = {{ level = {level} }} }}); __ns.Now = real""")
for i in range(20):
    track(NOW - 6 * DAY + i * 3600, "Fast Leveler", 10 + i)
check("twenty level-ups in a week are all kept (the old cap kept eight)",
      A.ev('#__ns.GuildStore().lvlLog["Fast Leveler"]') == 40)
A.ex(f'__ns.GuildStore().lvlLog["Old Timer"] = {{ {NOW} - 40 * 86400, 10, {NOW} - 30 * 86400, 11, {NOW} - 25 * 86400, 12 }}')
track(NOW, "Old Timer", 13)
check("changes older than three weeks drop, but the last one before that stays",
      list(A.ev('__ns.GuildStore().lvlLog["Old Timer"]').values()) == [NOW - 25 * DAY, 12, NOW, 13])
for i in range(70):
    track(NOW + i, "Flapper", 1 + i % 2)
check("a history never grows past 60 changes", A.ev('#__ns.GuildStore().lvlLog["Flapper"]') == 120)
A.ex('local l = __ns.GuildStore().lvlLog; l["Fast Leveler"], l["Old Timer"], l["Flapper"] = nil, nil, nil')

# --- The window: from Member tools, reused widgets ----------------------------------------
A.ex('''function __clickRow(key) for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key==key then r:GetScript("OnClick")(r); return true end end error("Missing row "..key) end
function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end
function __boardTexts()
  local t = {}
  for _, w in ipairs(EPUGuildLevelingBoard.pool.used) do
    if w.GetText and w:IsShown() and w:GetText() then t[#t + 1] = w:GetText() end
  end
  return table.concat(t, "\\n")
end
function __boardClick(label)
  for _, w in ipairs(EPUGuildLevelingBoard.pool.used) do
    if w.GetText and w:GetText() == label and w:GetScript("OnClick") then w:GetScript("OnClick")(w); return true end
  end
  error("Missing button " .. label)
end''')
A.ex('__ns.UI:Show(); __ns.UI.nav.membertools:Click()')
check("Member tools has a Leveling board tile", "levelboard" in (A.ev("__rowKeys()") or "").split(","))
A.ex('__ns.UI.search:SetText("most levels")')
check("searching member tools finds it", A.ev("__rowKeys()") == "levelboard")
A.ex('__ns.UI.search:SetText(""); __clickRow("levelboard")')
check("the tile opens the board", A.ev("EPUGuildLevelingBoard ~= nil and EPUGuildLevelingBoard:IsShown()"))
text = A.ev("__boardTexts()") or ""
check("this week lists each character with levels and gain (%s)" % text.replace("\n", " | "),
      "Newbie Stone" in text and "1 to 8" in text and "+7" in text and "3 guildmates gained 12 levels." in text
      and "Gone Away" not in text and "(so far)" in text)
A.ex('__boardClick("Last week")')
text = A.ev("__boardTexts()") or ""
check("Last week shows the week before", "Tyler Baker" in text and "10 to 12" in text and "Newbie Stone" not in text
      and "1 guildmate gained 2 levels." in text)
made = A.ev("EPUGuildLevelingBoard.pool:Made()")
for _ in range(30):
    A.ex('__boardClick("This week"); __boardClick("Last week")')
check("redraws reuse the same widgets", A.ev("EPUGuildLevelingBoard.pool:Made()") <= made + 8)
A.ex('EPUGuildLevelingBoard:Hide(); SlashCmdList.EPUGUILD("levelboard")')
check("/epu levelboard opens this week", A.ev("EPUGuildLevelingBoard:IsShown()") and "Newbie Stone" in (A.ev("__boardTexts()") or ""))
A.ex('SlashCmdList.EPUGUILD("levelboard last")')
check("/epu levelboard last opens last week", "Newbie Stone" not in (A.ev("__boardTexts()") or ""))
A.ex('__ns.G().lvlLog = {}')
A.ex('__boardClick("This week")')
check("an empty week says so", "Nobody has gained a level yet this week." in (A.ev("__boardTexts()") or ""))

# --- The Discord companion ----------------------------------------------------------------
A.ex(f"""
local g = __ns.GuildStore()
g.lvlLog = {{
  ["Tyler Baker"]  = {{ {LW} - 3 * 86400, 10, {LW} + 86400, 12, {WS} + 3600, 15, {WS} + 7200, 16 }},
  ["Pip Baker"]    = {{ {LW} - 10 * 86400, 30, {WS} + 3 * 3600, 31 }},
  ["Newbie Stone"] = {{ {WS} + 3600, 1, {WS} + 5 * 3600, 8 }},
  ["Gone Away"]    = {{ {WS} + 3600, 5, {WS} + 7200, 9 }},
}}
""")
A.ex(f'__dumpSV("{SV}")')
gd = core.load_guild_data(SV, "E Pluribus Unum")
rows = gd.leveling_board(WS, WS + 7 * DAY)
check("the bot reads the same board as the game (%s)" % rows,
      [(r["name"], r["from"], r["to"], r["gained"]) for r in rows] == [("Newbie Stone", 1, 8, 7), ("Tyler Baker", 12, 16, 4), ("Pip Baker", 30, 31, 1)])
check("odd records don't break the read", core.GuildData({"guilds": {"E": {"members": {1: "A B"}, "lvlLog": {
    "A B": "x", "C D": [1, 2], 7: [1, 2, 3, 4]}}}}).leveling_board(0, 10) == [])

check("weekday names parse", core.parse_weekday("Monday") == 0 and core.parse_weekday("sun") == 6
      and core.parse_weekday("mo") is None and core.parse_weekday("funday") is None)
mon = datetime.fromtimestamp(WS)
at, start, end = core.leveling_board_period(mon + timedelta(hours=19), 0, 19, 0)
check("on Monday at the set time it covers Monday to Sunday before it", at == mon + timedelta(hours=19)
      and start == mon - timedelta(days=7) and end == mon)
at, start, end = core.leveling_board_period(mon + timedelta(hours=18, minutes=59), 0, 19, 0)
check("a minute early, the latest post time is last week's", at == mon - timedelta(days=7) + timedelta(hours=19))
at, start, end = core.leveling_board_period(mon + timedelta(days=2), 6, 12, 0)
check("another post day covers the seven days before it", at == mon - timedelta(days=1) + timedelta(hours=12)
      and end == mon - timedelta(days=1) and start == mon - timedelta(days=8))

cfgdir = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "feed_channel_id": "3", "guild_needs_channel_id": "4",
           "wow_path": WOW}, open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py"):
    shutil.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check("on by default, Monday at 19:00", bot.cfg["leveling_board_post"] is True and bot.cfg["leveling_board_day"] == "monday"
      and bot.cfg["leveling_board_time"] == "19:00")
check("channel falls back to the guild needs channel", bot.cfg["leveling_board_channel_id"] == "4")

sent, fail, seen_ids = [], [], []
class FakeChannel:
    async def send(self, **kw):
        if fail:
            raise RuntimeError("Discord is down")
        sent.append(kw["embed"])
bot.client.get_channel = lambda cid: (seen_ids.append(cid), FakeChannel())[1]
bot.read_latest = lambda force=False: core.load_guild_data(SV, "E Pluribus Unum")
bot.state.data.pop("leveling_board_week", None)
post = lambda when: asyncio.run(bot.post_leveling_board(when))

check("nothing before the set time", post(mon + timedelta(hours=18, minutes=59)) is False and sent == [])
check("posts on Monday at the set time", post(mon + timedelta(hours=19)) is True and len(sent) == 1 and seen_ids[-1] == 4)
e = sent[0]
check("last week's board: title has the dates, Monday to Sunday (%s)" % e.title,
      e.title == f"Leveling board: {bot._day_label(mon - timedelta(days=7))} to {bot._day_label(mon - timedelta(days=1))}")
check("it lists who gained what (%s)" % e.description, e.description == "\U0001f947 **Tyler Baker** 10 → 12 (+2)"
      and "1 guildmate gained 2 levels" in e.footer.text and "/epu levelboard" in e.footer.text)
check("only once a week", post(mon + timedelta(days=2, hours=20)) is False and len(sent) == 1)
fail.append(1)
nxt = mon + timedelta(days=7, hours=19)
check("a failed send is retried", post(nxt) is False and bot.state.data["leveling_board_week"] == (mon - timedelta(days=7)).date().isoformat())
fail.clear()
check("the next week posts the next board", post(nxt + timedelta(minutes=1)) is True and len(sent) == 2)
lines = sent[1].description.split("\n")
check("most levels first, top three marked (%s)" % lines, lines == [
    "\U0001f947 **Newbie Stone** 1 → 8 (+7)", "\U0001f948 **Tyler Baker** 12 → 16 (+4)", "\U0001f949 **Pip Baker** 30 → 31 (+1)"])
check("the week is remembered in state.json", json.load(open(os.path.join(cfgdir, "state.json")))["leveling_board_week"] == mon.date().isoformat())
check("up to two days late is still posted, but nobody levelled that week, so it's skipped and marked done",
      post(mon + timedelta(days=15, hours=12)) is False and len(sent) == 2
      and bot.state.data["leveling_board_week"] == (mon + timedelta(days=7)).date().isoformat())
check("more than two days late waits for next week", post(mon + timedelta(days=24, hours=20)) is False
      and bot.state.data["leveling_board_week"] == (mon + timedelta(days=7)).date().isoformat())
bot.cfg["leveling_board_max"] = 2
e = bot.leveling_board_embed(bot.read_latest(), mon, mon + timedelta(days=7))
check("long boards stop at the cap and say how many more", e.description.endswith("...and 1 more.") and e.description.count("\n") == 2)
bot.cfg["leveling_board_post"] = False
check("off means off", post(mon + timedelta(days=28, hours=19)) is False and len(sent) == 2)
check("help mentions /levelboard", any("/levelboard" in f.value for f in bot.help_embed().fields))

check("no addon runtime errors", all((c.ev("__errors") or 0) == 0 for c in clients.values()))
print(f"{check.failed} failed" if check.failed else "all passed")
sys.exit(1 if check.failed else 0)

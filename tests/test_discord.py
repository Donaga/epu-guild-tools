import sys, os, json, shutil, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
WOW = tempfile.mkdtemp().replace(os.sep, "/")
STATE = os.path.join(WOW, "state.json")
import epu_core as core

for n in ["Chris Baker","Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]

# --- guild bank scanning ---
A.ex('__gb[1] = {{2589, 20}, {2589, 15}, {14047, 3}}; __gb[2] = {{4306, 8}}')
A.ex('SlashCmdList.EPUGUILD("need 2589 50")')
A.ex('__fire("GUILDBANKFRAME_OPENED")'); tick(8)
check("guild bank counted for officer", A.ev("__ns.BankCount(2589)") == 35)
check("guild bank synced to member", B.ev("__ns.BankCount(4306)") == 8)
check("bank alt names mention guild bank", "guild bank" in A.ev("__ns.BankAltNames()"))
# member opens guild bank: counted locally but not trusted to publish
B.ex('__gb[1] = {{2589, 99}}; __gb[2] = {}')
B.ex('__fire("GUILDBANKFRAME_OPENED")'); tick(8)
check("member's scan not accepted by officer", A.ev("__ns.BankCount(2589)") == 35)
A.ex('__fire("GUILDBANKFRAME_CLOSED")'); B.ex('__fire("GUILDBANKFRAME_CLOSED")')

# --- deposit log -> donations, no duplicates on rescan ---
A.ex('__gblog[1] = {{"Tyler Baker", 2589, 20, 2}, {"Tyler Baker", 2589, 20, 2}, {"Newbie Stone", 14047, 3, 0}}; __gbmoneylog = {{"Tyler Baker", 50000, 1}}')
A.ex('__fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); tick(4)
cnt = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.to == 'Guild Bank' then n=n+1 end end return n end)()"
check("4 guild bank deposits logged", A.ev(cnt) == 4)
A.ex('__now = __now + 1800; __fire("GUILDBANKLOG_UPDATE")'); tick(4)
check("rescan adds no duplicates", A.ev(cnt) == 4)
A.ex('__gblog[1][4] = {"Tyler Baker", 2589, 20, 0}; __fire("GUILDBANKLOG_UPDATE")'); tick(4)
check("a genuinely new identical deposit is logged", A.ev(cnt) == 5)
check("member received guild bank donations", B.ev(cnt) == 5)
A.ex('__fire("GUILDBANKFRAME_CLOSED")')

# --- in-game request that Discord should see ---
B.ex('SlashCmdList.EPUGUILD("request 4306 4 for bags")'); tick(3)

# --- game -> companion: write SavedVariables like WoW does, parse it ---
os.makedirs(WOW + "/WTF/Account/ACCT/SavedVariables", exist_ok=True)
os.makedirs(WOW + "/Interface/AddOns/EPUGuild", exist_ok=True)
A.ex('__ns.CacheItemNames()')
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
paths = core.find_saved_variables(WOW)
check("companion finds SavedVariables", len(paths) == 1)
gd = core.load_guild_data(paths[0], "E Pluribus Unum")
check("parsed guild key", gd.key == "E Pluribus Unum - Forever")
check("parsed item names", gd.item_name(2589) == "Linen Cloth")
check("parsed bank counts", gd.bank_count(2589) == 35)
needs = gd.needs()
check("parsed needs", needs and needs[0]["name"] == "Linen Cloth" and needs[0]["missing"] == 15)

if os.path.exists(STATE): os.remove(STATE)
st = core.State(STATE)
ch = core.diff(gd, st)
check("first run posts the open request, not old donations", len(ch["new_requests"]) == 1 and ch["new_donations"] == [])
rid_game = ch["new_requests"][0][0]
st.set_posted(rid_game, 111, "pending")

# --- companion -> game: Discord request + approval of the in-game request ---
item_id, name = core.resolve_item("id:2996", gd.known_items() | {2996: "Bolt of Linen Cloth"})
e = st.queue_request("tyler", item_id, name, 2, 'needs "quotes" \\ and\nnewline', "tyler")
st.queue_status(rid_game, "approved", "Chris (Discord)")
wl = core.resolve_item("https://www.wowhead.com/forever/item=14047/runecloth", gd.known_items())
check("wowhead link resolves", wl[0] == 14047)
core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(4)
rid_d = "d-" + e["id"]
check("Discord request created in game", A.ev(f'__ns.G().requests["{rid_d}"].who') == "Tyler Baker")
check("tricky note survived Lua round trip", A.ev(f'__ns.G().requests["{rid_d}"].note') == 'needs "quotes" \\ and\nnewline')
check("Discord request synced to member", B.ev(f'__ns.G().requests["{rid_d}"] ~= nil'))
check("Discord approval applied", B.ev(f'__ns.G().requests["{rid_game}"].status') == "approved")
check("approval credited to Discord user", B.ev(f'__ns.G().requests["{rid_game}"].by') == "Chris (Discord)")
A.ex('__ns.ProcessInbox()'); tick(2)
n = A.ev("(function() local n=0 for _ in pairs(__ns.G().requests) do n=n+1 end return n end)()")
check("re-processing the inbox doesn't duplicate", n == 2)

# --- next save: companion prunes inbox and sees status change ---
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd = core.load_guild_data(paths[0], "E Pluribus Unum")
check("inbox pruned after game applied it", st.prune_inbox(gd.inbox_done) and st.data["inbox"] == [])
ch = core.diff(gd, st)
check("status change detected for Discord edit", [r for r, _ in ch["changed_requests"]] == [rid_game])
check("Discord-made request shows as new for posting", [r for r, _ in ch["new_requests"]] == [rid_d])

# --- /link name matching against the saved roster ---
check("roster saved for companion", "Tyler Baker" in gd.members and "Chris Stone" in gd.members)
check("/link full name any case", gd.resolve_member("tyler baker") == ("Tyler Baker", []))
check("/link unique first name", gd.resolve_member("Newbie")[0] == "Newbie Stone")
check("/link shared first name asks for full", gd.resolve_member("chris") == (None, ["Chris Baker", "Chris Stone"]))

# --- multiple linked characters and deliver-to from Discord ---
B.ex('local key = __ns.GuildKey(); __ns.db.accountChars[key]["Pip Baker"] = __now + 100; __ns.PublishAlts()'); tick(3)
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd = core.load_guild_data(paths[0], "E Pluribus Unum")
grp = gd.group_of("Pip Baker")
check("companion sees alt group", grp and grp["main"] == "Tyler Baker" and grp["chars"] == ["Tyler Baker", "Pip Baker"])
check("companion labels alts", gd.label("Pip Baker") == "Pip Baker (Tyler Baker)")
st.data["links"]["42"] = "Tyler Baker"                     # a link saved by the older version
check("old single link still read", st.characters_for(42) == ["Tyler Baker"])
chars = st.link(42, *grp["chars"], main=grp["main"])
check("linking pulls in the alt group, main first", chars == ["Tyler Baker", "Pip Baker"])
e2 = st.queue_request(chars[0], 2589, "Linen Cloth", 5, "", "tyler", to="Pip Baker")
core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
check("Discord deliver-to reaches the game", B.ev(f'__ns.G().requests["d-{e2['id']}"].to') == "Pip Baker")
check("unlink", st.unlink(42, "pip baker") == ["Tyler Baker"])

# --- /craft lookup from shared recipes ---
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(6)
A.ex('__ns.SetDesignated("Tailoring", "Tyler Baker", true)'); tick(3)
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd2 = core.load_guild_data(paths[0], "E Pluribus Unum")
cr = gd2.crafters_for(item_id=2996)
check("companion finds who can craft (%s)" % cr, cr and cr[0]["who"] == "Tyler Baker" and cr[0]["designated"] is True)
check("craftable items for autocomplete", 2996 in gd2.craftable_items())

# --- status post summary ---
sm = gd.status_summary()
check("status: needs listed", [n["name"] for n in sm["needs"]] == ["Linen Cloth"])
check("status: gold from guild bank", sm["gold"] == 5000000)
addon_shop = A.ev('(function() local t = {} for _, r in ipairs(__ns.ShoppingList()) do t[#t+1] = r.id .. "=" .. r.buy end return table.concat(t, ",") end)()')
check("status: shopping matches the addon's Shopping tab (%s)" % addon_shop, ",".join(f"{r['id']}={r['buy']}" for r in sm["shopping"]) == addon_shop)
check("status: request counts", sm["requests"] == {"pending": 1, "approved": 1, "crafts": 0} or print(sm["requests"]))
import importlib, json as _j
cfgdir = tempfile.mkdtemp()
_j.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "wow_path": WOW}, open(os.path.join(cfgdir, "config.json"), "w"))
import shutil as _s
for f in ("bot.py", "epu_core.py"):
    _s.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
emb = bot.status_embed(gd)
check("status embed builds", emb.title == "Guild Bank Status" and [f.name for f in emb.fields][:4] == ["Needs", "Shopping list", "Gold", "Requests"])
check("status channel falls back to request channel", bot.cfg["status_channel_id"] == "2")
print("   ", emb.fields[0].value, "|", emb.fields[2].value)

# --- milestones and announcements, both ways ---
B.ex('__fire("PLAYER_LEVEL_UP", 20)'); tick(3)
A.ex('__ns.PostNews("Welcome", "Mail donations to the bank")'); tick(3)
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd3 = core.load_guild_data(paths[0], "E Pluribus Unum")
ch3 = core.diff(gd3, st)
check("bot sees the new milestone", [e["text"] for e in ch3["new_feed"]] == ["reached level 20"])
check("milestone line", bot.milestone_line(gd3, ch3["new_feed"][0]).endswith("**Tyler Baker** reached level 20!"))
check("bot sees the new announcement", len(ch3["news"]) == 1 and ch3["news"][0][1]["title"] == "Welcome")
nid3 = ch3["news"][0][0]
st.data.setdefault("news_posted", {})[nid3] = {"message_id": 5, "u": ch3["news"][0][1]["u"]}
check("posted milestones and announcements aren't repeated", core.diff(gd3, st)["new_feed"] == [] and core.diff(gd3, st)["news"] == [])
A.ex('__ns.RemoveNews("%s")' % nid3); tick(2)
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd4 = core.load_guild_data(paths[0], "E Pluribus Unum")
rm = core.diff(gd4, st)["news"]
check("removed announcement comes back so the post can be deleted", len(rm) == 1 and rm[0][1].get("removed") is True)
ne = st.queue_news("Raid night", "Deadmines Friday 8pm", "Donaga")
core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
check("/announce reaches the game and members", B.ev('(function() for _, e in ipairs(__ns.NewsEntries()) do if e.title == "Raid night" then return e.by end end end)()') == "Donaga (Discord)")
check("announcement embed", bot.news_embed({"title": "Raid night", "text": "x", "by": "Donaga"}).title == "Raid night")

# --- copying the Discord announcements channel into the game ---
import asyncio, types
from datetime import datetime as _dt, timezone as _tz
bot.client._connection.user = types.SimpleNamespace(id=1)
bot.flush_inbox = lambda: core.write_inbox(core.inbox_path(WOW), bot.state.data["inbox"])
bot.state = st
def fake_msg(mid, content, author="Donaga", aid=2):
    return types.SimpleNamespace(id=mid, clean_content=content, embeds=[], type=bot.discord.MessageType.default, guild=None,
                                 author=types.SimpleNamespace(id=aid, display_name=author), created_at=_dt.now(_tz.utc))
check("copies a post from the announcements channel", asyncio.run(bot.import_message(fake_msg(777, "**Patch night**\nServers restart at 6"))) is True)
n_in = len(st.data["inbox"])
asyncio.run(bot.import_message(fake_msg(777, "**Patch night**\nServers restart at 6")))
check("the same post isn't copied twice", len(st.data["inbox"]) == n_in)
check("the bot's own posts are skipped", asyncio.run(bot.import_message(fake_msg(778, "hello", aid=1))) is False)
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
title_of = '(function() local e = __ns.GuildStore().news["m777"] return e and not e.removed and (e.title .. "|" .. e.text) or nil end)()'
check("copied post becomes an in-game announcement", B.ev(title_of) == "Patch night|Servers restart at 6")
check("copied posts aren't posted back to Discord", st.data["news_posted"]["m777"]["external"] is True)
asyncio.run(bot.import_message(fake_msg(777, "**Patch night**\nServers restart at 7"), edit=True))
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
check("edits in Discord update the game", B.ev(title_of) == "Patch night|Servers restart at 7")
st.queue_news_remove("m777"); core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
check("deleting in Discord removes it in game", B.ev(title_of) is None)

# pings stripped; older posts copied quietly (no pop-up); a pending copy is rewritten, not duplicated
asyncio.run(bot.import_message(fake_msg(901, "@everyone\n**Launch night**\nGoldshire at 6"), quiet=True))
n_before = len(st.data["inbox"])
asyncio.run(bot.import_message(fake_msg(901, "@everyone\n**Launch night!**\nGoldshire at 6"), quiet=True))
check("re-copying a post that hasn't reached the game rewrites it", len(st.data["inbox"]) == n_before
      and [e for e in st.data["inbox"] if e.get("nid") == "m901"][0]["title"] == "Launch night!")
core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
B.ex('__popups = {}')
A.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(3)
check("old announcements show in News", B.ev('__ns.GuildStore().news["m901"].title') == "Launch night!")
check("but don't pop up or count as unread", B.ev('#__popups') == 0
      and B.ev('(function() for _, e in ipairs(__ns.UnreadNews()) do if e.id == "m901" then return true end end return false end)()') == False)

# --- in-game message of the day ---
for c in (A, B):
    c.ex('__motd = "Welcome! Bank alt is Epu Bank."; __ginfo = "Casual leveling guild. Be nice."; __fire("GUILD_MOTD", __motd)')
check("MOTD shows as unread news", B.ev('__ns.UnreadNews()[1].id') == "motd")
B.ex('__ns.UI:Show(); __ns.UI:SetView("news")')
check("News page shows MOTD and guild info", B.ev('(function() local t = {} for _, r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data then t[#t+1] = r.data.key end end return table.concat(t, ",") end)()').startswith("news:motd,news:info"))
B.ex('__ns.MarkNewsRead("motd")')
check("reading it clears it until it changes", B.ev('(function() for _, e in ipairs(__ns.UnreadNews()) do if e.id == "motd" then return true end end return false end)()') == False)
B.ex('__motd = "New: raid Friday"; __fire("GUILD_MOTD", __motd)')
check("a new MOTD is unread again", B.ev('__ns.UnreadNews()[1].id') == "motd")
A.ex(f'__dumpSV("{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua")')
gd5 = core.load_guild_data(paths[0], "E Pluribus Unum")
check("bot mirrors the MOTD to Discord", core.diff(gd5, st).get("motd") == "Welcome! Bank alt is Epu Bank.")
check("and only once", core.diff(gd5, st).get("motd") is None)

# --- a member's client doesn't apply the inbox ---
st.queue_status(rid_d, "approved", "x"); core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
B.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(2)
check("member client ignores inbox", B.ev(f'__ns.G().requests["{rid_d}"].status') == "pending")

# --- craft requests, reagents and skill-ups on the bot side ---
cg = core.GuildData({"guilds": {"G - R": {
    "bank": {"Epu Bank": {"v": 1, "items": {2996: 1}}},
    "recipes": {"Tyler Baker": {"t": 1, "profs": {"Tailoring": {"rank": 150, "items": [30001], "diff": {"item:30001": "o"}}}}},
    "mats": {"item:30001": {"t": 1, "r": [2996, 3, 2589, 1]}},
    "requests": {
        "c1": {"who": "Pip Baker", "crafter": "Tyler Baker", "key": "item:30001", "item": 30001, "qty": 2, "mats": "bank", "status": "approved", "t": 5, "u": 5},
        "c2": {"who": "Pip Baker", "crafter": "Tyler Baker", "key": "spell:Enchant Bracer", "spell": "Enchant Bracer", "qty": 1, "mats": "me", "status": "pending", "t": 6, "u": 6},
        "b1": {"who": "Pip Baker", "item": 2589, "qty": 4, "status": "approved", "t": 7, "u": 7},
    }}}, "itemNames": {2996: "Bolt of Linen Cloth", 2589: "Linen Cloth", 30001: "Linen Bag"}})
shop = {r["id"]: r["buy"] for r in cg.shopping_list()}
check("bank-paid craft mats on the bot's shopping list (%s)" % shop, shop.get(2996) == 5 and shop.get(2589) == 2 + 4 and 30001 not in shop)
sm = cg.status_summary()["requests"]
check("status post counts crafts separately", sm == {"pending": 0, "approved": 1, "crafts": 2})
check("craft labels", core.status_label(cg.requests["c1"]) == "accepted" and core.status_label(cg.requests["c2"]) == "asked"
      and cg.request_name(cg.requests["c2"]) == "Enchant Bracer")
cr = cg.crafters_for(item_id=30001)
check("/craft shows skill-ups and materials", cr[0]["skillup"] is True and cg.mats_for(cr[0]["key"]) == [(2996, 3), (2589, 1)])
emb = bot.request_embed("c1", cg.requests["c1"], cg)
check("craft request embed", emb.title.startswith("Craft: Linen Bag") and any(f.name == "Crafter" for f in emb.fields))
he = bot.help_embed()
check("help post fits Discord's limits (%d chars)" % len(he), len(he) < 6000 and all(len(f.value) <= 1024 for f in he.fields))

for c in (A, B):
    c.ex('__ns.UI:Show()')
    for tab in ["Needs","Shopping","Bank","Requests","Donations","Crafters"]:
        c.ex(f'__ns.UI:SetTab("{tab}")')
errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

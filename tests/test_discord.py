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

# --- status post summary ---
sm = gd.status_summary()
check("status: needs listed", [n["name"] for n in sm["needs"]] == ["Linen Cloth"])
check("status: gold from guild bank", sm["gold"] == 5000000)
addon_shop = A.ev('(function() local t = {} for _, r in ipairs(__ns.ShoppingList()) do t[#t+1] = r.id .. "=" .. r.buy end return table.concat(t, ",") end)()')
check("status: shopping matches the addon's Shopping tab (%s)" % addon_shop, ",".join(f"{r['id']}={r['buy']}" for r in sm["shopping"]) == addon_shop)
check("status: request counts", sm["requests"] == {"pending": 1, "approved": 1})
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

# --- a member's client doesn't apply the inbox ---
st.queue_status(rid_d, "approved", "x"); core.write_inbox(core.inbox_path(WOW), st.data["inbox"])
B.ex(f'dofile("{WOW}/Interface/AddOns/EPUGuild/Inbox.lua"); __ns.ProcessInbox()'); tick(2)
check("member client ignores inbox", B.ev(f'__ns.G().requests["{rid_d}"].status') == "pending")

for c in (A, B):
    c.ex('__ns.UI:Show()')
    for tab in ["Needs","Shopping","Bank","Requests","Donations","Crafters"]:
        c.ex(f'__ns.UI:SetTab("{tab}")')
errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

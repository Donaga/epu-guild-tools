"""0.9.3 automatic sync: login retry, officer-online hellos, prioritised bundles,
member relay (unconfirmed), officer check-ins, held data until the roster loads,
and the Needs page on clients without the old GetItemCount."""
import sys, re
import simcore
from simcore import *

for n in ["Late Member", "Mid Member", "Roster Late", "Part Member", "Check Member", "Modern Client"]:
    simcore.ROSTER.append((n, "Initiate", 4))

def join(name, pre=""):
    """A client logging in; `pre` runs before the addon loads."""
    c = Client.__new__(Client)
    c.rt = simcore.L.LuaRuntime(unpack_returned_tuples=True)
    c.name = name
    c.rt.execute(open(simcore.os.path.join(simcore.HERE, "stubs.lua")).read())
    rank = [r for r in simcore.ROSTER if r[0] == name][0]
    c.rt.execute('__name, __rankName, __rankIndex = "%s", "%s", %d' % (name, rank[1], rank[2]))
    c.rt.execute("__roster = {" + ",".join('{"%s","%s",%d}' % r for r in simcore.ROSTER) + "}")
    c.rt.execute(pre)
    c.rt.execute(f'__load("{simcore.ADDON}")')
    clients[name] = c
    return c

def needs(c): return c.ev('(function() local n = 0 for _ in pairs(__ns.G().needs.list) do n = n + 1 end return n end)()')
def status(c): return c.ev('(__ns.SyncStatus())')
def unconf(c): return c.ev('__ns.HasUnconfirmed()')
def popups(c, title="Guild announcement"):
    return sum(1 for i in range(1, c.ev('#__dialogs') + 1) if c.ev('__dialogs[%d][1]' % i) == title)

A = join("Chris Baker"); B = join("Tyler Baker"); CS = join("Chris Stone")
tick(25)
for i in range(6): A.ex('__ns.SetNeed(%d, 20)' % (30000 + i))
A.ex('__ns.PostNews("Raid night", "Friday at 8")')
tick(40)
check("member synced from the officer (%s)" % status(B), status(B).startswith("Synced") and needs(B) == 6)

# --- bundles: needs and bank first, recipes chunked ---
parts = A.ev('(function() local b = __ns.Delta({ since = 0 }); local p = __ns.SplitDelta(b); return p[1].needs ~= nil and "needs" or "other" end)()')
check("first bundle carries the needs list", parts == "needs")
A.ex('for i = 1, 8 do __ns.G().recipes["R" .. i] = { t = __ns.Now(), profs = {} } end')
n = A.ev('(function() local p = __ns.SplitDelta(__ns.Delta({ since = 0 })); local n = 0 for _, x in ipairs(p) do if x.recipes then n = n + 1 end end return n end)()')
check("recipes go out a few at a time (%d bundles)" % n, n == 3)
A.ex('for i = 1, 8 do __ns.G().recipes["R" .. i] = nil end')

# --- no officer online: a guildmate relays, marked unconfirmed ---
del clients["Chris Baker"]
L = join("Late Member"); tick(60)
check("new member got data with no officer online (%d needs)" % needs(L), needs(L) == 6)
check("it's marked unconfirmed (%s)" % status(L), unconf(L) == True and status(L) == "Unconfirmed data")
check("relayed news shows in News", L.ev('#__ns.NewsEntries()') == 1)
check("but never pops up", popups(L) == 0)
check("relay doesn't count as a sync", L.ev('__ns.G().syncedAt') is None)
check("footer says unconfirmed", "Unconfirmed" in (L.ex('__ns.UI:Show(); __ns.UI:SetView("needs")') or L.ev('__ns.UI.footerText:GetText()')))

M = join("Mid Member"); tick(60)
check("relayed data is never passed on (from %s)" % M.ev('__ns.sync.relayFrom'),
      M.ev('__ns.sync.relayFrom') in ("Tyler Baker", "Chris Stone") and needs(M) == 6)

# a hand-edited client tries to slip in fake data
B.ex('__ns.Send("D", { sync = "Late Member", relay = true, hs = 1, part = 1, parts = 1,'
     ' bank = { ["Fake Alt"] = { v = 5, items = { [30001] = 999 } } },'
     ' don = { fake1 = { t = __ns.Now(), who = "Tyler Baker", item = 30001, n = 500 } } })')
tick(2)
check("fake relay lands only as unconfirmed", L.ev('__ns.Unconf(__ns.G(), "bank", "Fake Alt")') == True)
real_v = CS.ev('(function() for k, s in pairs(__ns.G().bank) do return k end end)()')
B.ex('__ns.Send("D", { sync = "Chris Stone", relay = true, hs = 1, part = 1, parts = 1,'
     ' needs = { v = 9999999999, list = { [30099] = 1 } } })')
tick(2)
check("relay can't override confirmed data (%d, v%d)" % (needs(CS), CS.ev('__ns.G().needs.v')), needs(CS) == 6 and CS.ev('__ns.G().needs.v') < 9999999999)
B.ex('__ns.Send("D", { sync = "Mid Member", relay = true, hs = 1, part = 1, parts = 1,'
     ' req = { r1 = { u = __ns.Now(), who = "Mid Member", item = 30001, qty = 1, status = "approved" } } })')
tick(2)
check("relay can't touch your own records", M.ev('__ns.G().requests.r1') is None)
B.ex('__ns.Send("D", { relay = true, sync = "Late Member", hs = 1, part = 1, parts = 1, needs = { v = 1, list = {} } })')

# --- the officer logs in: everyone unconfirmed asks by itself, fakes are dropped ---
# (same officer, same saved data, logging back in)
clients["Chris Baker"] = A; A2 = A
A.ex('__ns.SendHello()'); tick(90)
for c, nm in ((L, "Late"), (M, "Mid")):
    check("%s member synced automatically when the officer came on (%s)" % (nm, status(c)),
          status(c).startswith("Synced") and unconf(c) == False and needs(c) == 6)
check("fake bank alt removed", L.ev('__ns.G().bank["Fake Alt"]') is None)
check("fake donation removed", L.ev('__ns.G().donations.fake1') is None)

# --- an officer seen coming online in the roster prompts a hello ---
L.ex('__ns.sync.officerAt = nil; __ns.sync.helloAt = nil')
L.ex('__ns.WatchOfficers({ ["Chris Baker"] = { online = false, rank = 1 } })')
L.ex('__ns.WatchOfficers({ ["Chris Baker"] = { online = true, rank = 1 } })')
check("officer coming online in the roster triggers a hello", L.ev('__ns.sync.helloQueued') == True)
tick(40)
check("and it syncs", status(L).startswith("Synced"))

# --- the guild roster loads late: retry, and hold the officer's data until it does ---
R = join("Roster Late", 'local real = GetNumGuildMembers; function GetNumGuildMembers() if __now < 40 + __bornAt then return 0 end return real() end; __bornAt = __now')
tick(5)
check("roster not loaded yet", R.ev('next(__ns.roster)') is None)
tick(80)
check("synced once the roster loaded (%s, %d needs)" % (status(R), needs(R)), status(R).startswith("Synced") and needs(R) == 6)
# officer data arriving before the roster: held, not thrown away
R.ex('__ns.roster = {}; GetNumGuildMembers = function() return 0 end')
A2.ex('__ns.SetNeed(30010, 5)'); tick(3)
check("officer data held while roster is missing", needs(R) == 6)
R.ex('GetNumGuildMembers = function() return #__roster end; __fire("GUILD_ROSTER_UPDATE")'); tick(2)
check("and applied once the roster loads (%d)" % needs(R), needs(R) == 7)

# --- a lost bundle only costs that bundle; the rest sticks and it's retried ---
seen, state = [], {"drop": None}
real_route = simcore.route
def lossy():
    for c in list(clients.values()):
        if c.name != "Chris Baker": continue
        out = c.ev("__out"); keep = []
        for i in range(1, len(out) + 1):
            m = out[i]; msg = m[2]
            mm = re.match(r"^P(\d+):", msg)
            if state["drop"] == "armed" and mm:
                bid = mm.group(1)
                if bid not in seen: seen.append(bid)
                if len(seen) == 2: state["dropid"] = bid
            if state.get("dropid") and mm and mm.group(1) == state["dropid"]: continue
            keep.append(m)
        c.ex("__out = {}")
        for m in keep: c.rt.globals()["table"].insert(c.ev("__out"), m)
    real_route()
for i in range(30): A2.ex('__ns.PostNews("Long %d", string.rep("words ", 60))' % i)
tick(60)
simcore.route = lossy; state["drop"] = "armed"
P = join("Part Member"); tick(30)
state["drop"] = None; state["dropid"] = None
check("needs arrived even though a later bundle was lost (%d)" % needs(P), needs(P) == 7)
check("an incomplete answer isn't counted as synced", P.ev('__ns.sync.officerAt') is None)
simcore.route = real_route
tick(120)
check("retried and completed (%s, %d news)" % (status(P), P.ev('#__ns.NewsEntries()')),
      status(P).startswith("Synced") and P.ev('#__ns.NewsEntries()') == A2.ev('#__ns.NewsEntries()'))

# --- officer check-in catches a member up on something they missed ---
K = join("Check Member"); tick(60)
K.ex('__ns.comm.D = (function(real) return function(s, b, ch) if not b.sync and b.needs then return end return real(s, b, ch) end end)(__ns.comm.D)')
A2.ex('__ns.SetNeed(30011, 5)'); tick(3)
check("member missed a live update", needs(K) == 7)
K.ex('__ns.comm.D = nil'); K.ex('__load_sync = nil')
# restore the handler by reloading the module's D from a fresh reference
K.ex('local f = assert(loadfile("%s/Sync.lua")); f("EPUGuild", __ns)' % simcore.ADDON)
tick(17 * 60, step=1.0)
check("officer check-in caught them up (%d)" % needs(K), needs(K) == 8)


# --- Sync tab: everyone's last sync, what came across, and their version ---
A.ex('__ns.UI:Show(); __ns.UI.state.sync.filter = "guild"; __ns.UI:SetView("sync")')
rows = A.ev('(function() local t = {} for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then t[#t+1] = r.title:GetText() .. " | " .. (r.sub:GetText() or "") end end return table.concat(t, "\\n") end)()')
check("Sync tab lists members who synced", "Late Member" in rows and "Synced from Chris Baker" in rows)
check("and what came across", "needs" in rows)
L.ex('__ns.UI:Show(); __ns.UI.state.sync.filter = "mine"; __ns.UI:SetView("sync")')
mine = L.ev('(function() local t = {} for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then t[#t+1] = r.title:GetText() end end return table.concat(t, "\\n") end)()')
check("This PC shows the local history", "Unconfirmed data from" in mine and "Synced from Chris Baker" in mine and "Dropped" in mine)
B.ex('__ns.SeenSync("Pip Baker", { t = __ns.Now(), from = "Chris Baker", what = "1 needs", ver = "0.9.0" }); __ns.newestVersion = nil')
A.ex('__ns.SeenSync("Pip Baker", { t = __ns.Now(), from = "Chris Baker", what = "1 needs", ver = "0.0.1" }); __ns.UI.state.sync.filter = "all"; __ns.UI:Refresh()')
check("older versions are flagged", "older version" in A.ev('__ns.UI.footerText:GetText()'))
A.ex('__ns.UI:SetView("needs")')


# --- a client without the old global item functions (only C_Item) ---
MC = join("Modern Client", 'C_Item = { GetItemInfo = GetItemInfo, GetItemInfoInstant = GetItemInfoInstant, GetItemCount = GetItemCount or function() return 0 end }'
          '; GetItemInfo = nil; GetItemInfoInstant = nil; GetItemCount = nil')
tick(60)
MC.ex('__ns.UI:Show()')
bad = []
for view in ["news", "needs", "shopping", "bank", "requests", "donations", "roster", "crafters", "recipes", "sync"]:
    MC.ex('__ns.UI:SetView("%s")' % view)
    t = MC.ev('__ns.UI.empty:IsShown() and __ns.UI.empty:GetText() or ""') or ""
    if "couldn't load" in t: bad.append(view + ": " + t.split("What went wrong:|r ")[-1][:80])
check("every page loads with only C_Item (%s)" % ("; ".join(bad) or "ok"), not bad)
check("and item pages have rows", MC.ev("(function() __ns.UI:SetView('needs') local n=0 for _,r in ipairs(__ns.UI.rows) do if r:IsShown() then n=n+1 end end return n end)()") > 0)

# --- Needs page without the old GetItemCount (WoW: Forever) ---
B.ex('GetItemCount = nil; C_Item = C_Item or {}; C_Item.GetItemCount = function() return 2 end')
B.ex('__ns.UI:Show(); __ns.UI:SetView("roster"); __ns.UI:SetView("needs")')
shown = B.ev("(function() local n = 0 for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then n = n + 1 end end return n end)()")
check("Needs page draws without GetItemCount (%d rows)" % shown, shown == needs(B))
check("carried count comes from C_Item", "you carry 2" in B.ev('__ns.UI.rows[1].title:GetText()'))
B.ex('C_Item.GetItemCount = nil')
B.ex('__ns.UI:SetView("needs")')
check("still draws with no count function at all", "Loading" in B.ev('__ns.UI.rows[1].title:GetText()') or B.ev('__ns.UI.rows[1]:IsShown()') == True)
# a page that errors shows a message, not the previous page's rows
B.ex('__ns.UI:SetView("roster"); local real = __ns.OpenNeeds; __ns.OpenNeeds = function() error("boom") end; __ns.UI:SetView("needs"); __ns.OpenNeeds = real')
shown = B.ev("(function() local n = 0 for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then n = n + 1 end end return n end)()")
txt = B.ev('__ns.UI.empty:GetText()')
check("a broken page doesn't show stale rows", shown == 0 and "couldn't load" in txt)
check("and says which page, why and where (%s)" % txt.replace("\n", " / "), "Needs page" in txt and "What went wrong" in txt and "line" in txt)
B.ex('__ns.UI:SetView("roster"); local real = __ns.OpenNeeds; __ns.OpenNeeds = function() return GetMissingThing() end; __ns.UI:SetView("needs"); __ns.OpenNeeds = real')
txt = B.ev('__ns.UI.empty:GetText()')
check("missing game functions are named in plain words", "doesn't have \"GetMissingThing\"" in txt)
B.ex('__ns.G().bank["Odd Alt"] = { v = 1, items = { [30001] = "x", foo = 3, [30002] = 4 } }; __ns.UI:SetView("bank")')
check("odd bank data doesn't break the Bank page", B.ev("(function() for _, r in ipairs(__ns.UI.rows) do if r:IsShown() and (r.title:GetText() or ''):find('30002') then return true end end return false end)()") == True)

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

"""0.8.0 guild management: roster, profiles, milestones, member review, officer log, announcements."""
import sys
import simcore
from simcore import *

# a second officer so officer-only data has somewhere to go
simcore.ROSTER.append(("Gm Baker", "Guild Master", 0))
for n in ["Chris Baker", "Tyler Baker", "Newbie Stone", "Gm Baker"]:
    clients[n] = Client(n)
A, B, N, GM = clients["Chris Baker"], clients["Tyler Baker"], clients["Newbie Stone"], clients["Gm Baker"]
for c in clients.values():
    c.ex('__toasts = {}; __ns.Notify = function(t, m) table.insert(__toasts, t .. ": " .. (m or "")) end')
tick(25)
shown = "(function() local n = 0 for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then n = n + 1 end end return n end)()"
def toasts(c):
    n = c.ev('#__toasts')
    return [c.ev('__toasts[%d]' % i) for i in range(1, n + 1)]

# --- roster details ---
for c in clients.values():
    c.ex('__rosterExtra = { ["Tyler Baker"] = {22, "Warrior", "WARRIOR", "Westfall"}, ["Pip Baker"] = {14, "Mage", "MAGE", nil, false, 40},'
         ' ["Chris Stone"] = {35, "Priest", "PRIEST", nil, false, 2} }; __fire("GUILD_ROSTER_UPDATE")')
tick(2)
check("roster keeps class, zone, last seen", A.ev('__ns.roster["Tyler Baker"].zone') == "Westfall"
      and A.ev('__ns.roster["Pip Baker"].away') == 40 and A.ev('__ns.roster["Pip Baker"].online') == False)
A.ex('__ns.UI:Show(); __ns.UI:SetView("roster")')
check("Roster lists everyone (%d)" % A.ev(shown), A.ev(shown) == 7)
A.ex('__ns.UI.state.roster.filter = "online"; __ns.UI:Refresh()')
check("online filter", A.ev(shown) == 5)
A.ex('__ns.UI.state.roster.filter = "near"; __ns.UI:Refresh()')
check("near my level: online, within 3 levels, not me (%d)" % A.ev(shown), A.ev(shown) == 4)
A.ex('__ns.UI.state.roster.filter = "all"; __ns.UI:Refresh()')

# --- profiles ---
B.ex('__ns.SetProfile("ht", "LF Deadmines")'); tick(3)
check("profile shared", A.ev('__ns.ProfileOf("Tyler Baker").roles') == "th" and A.ev('__ns.ProfileOf("Tyler Baker").lf') == "LF Deadmines")
N.ex('__ns.Send("D", { profiles = { ["Tyler Baker"] = { t = 9999999999, roles = "d", lf = "spoof" } } })'); tick(3)
check("can't set someone else's profile", A.ev('__ns.ProfileOf("Tyler Baker").lf') == "LF Deadmines")
A.ex('__ns.UI.state.roster.role = "h"; __ns.UI:Refresh()')
check("role filter", A.ev(shown) == 1)
A.ex('__ns.UI.state.roster.role = nil; __ns.UI:Refresh(); __ns.UI:OpenDetails("member", "Tyler Baker")')
check("member details", A.ev('__ns.UI.details.kind') == "member")
N.ex('__ns.UI:Show(); __ns.UI:OpenDetails("profile", "Newbie Stone")')
N.ex('(function() for _, b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText():find("Healer") then b:GetScript("OnClick")(b) end end end)()')
N.ex('__ns.UI.details.pools.box[1]:SetText("leveling buddy")')
N.ex('(function() for _, b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText() == "Save" then b:GetScript("OnClick")(b) end end end)()'); tick(3)
check("profile editor saves", A.ev('__ns.ProfileOf("Newbie Stone").roles') == "h" and A.ev('__ns.ProfileOf("Newbie Stone").lf') == "leveling buddy")

# --- milestones ---
B.ex('__fire("PLAYER_LEVEL_UP", 30)'); tick(3)
feed = "(function() local t = {} for _, e in ipairs(__ns.FeedEntries()) do t[#t+1] = e.who .. ' ' .. e.text end return table.concat(t, ' | ') end)()"
check("level 30 shared (%s)" % A.ev(feed), "Tyler Baker reached level 30" in A.ev(feed))
check("guildmates get a pop-up", any("reached level 30" in t for t in toasts(A)))
B.ex('__fire("PLAYER_LEVEL_UP", 31)'); tick(3)
check("level 31 isn't a milestone", "level 31" not in A.ev(feed))
B.ex('__ns.ProfessionMilestones({ Tailoring = 140 }, { Tailoring = 152 })'); tick(3)
check("profession rank milestone", "Tyler Baker reached Tailoring 150" in A.ev(feed))
B.ex('__ns.ProfessionMilestones(nil, { Tailoring = 152 })'); tick(3)
check("no backlog of milestones on the first scan", A.ev(feed).count("Tailoring 150") == 1)
B.ex('__ns.RidingMilestone(false, true)'); tick(3)
check("first mount", "learned to ride" in A.ev(feed))
N.ex('__ns.Send("D", { feed = { x1 = { t = %d, who = "Tyler Baker", kind = "level", text = "reached level 99" } } })' % A.ev('__ns.Now()')); tick(3)
check("can't post milestones for someone else", "level 99" not in A.ev(feed))
A.ex('__ns.SetBankAlt(true); __ns.AddDonation("Newbie Stone", nil, 0, 120000)'); tick(4)
check("big gold donation is a milestone", "Newbie Stone donated 12g" in B.ev(feed))
for c in clients.values():
    c.ex('table.insert(__roster, {"Fresh Face", "Initiate", 4}); __fire("GUILD_ROSTER_UPDATE")')
tick(4)
check("new member: welcome milestone and join date", "Fresh Face joined the guild" in B.ev(feed) and B.ev('__ns.GuildStore().joined["Fresh Face"] ~= nil') == True
      and B.ev('__ns.GuildStore().joined["Fresh Face"].seed') is None and B.ev('__ns.GuildStore().joined["Tyler Baker"].seed') == True)
A.ex('__ns.UI:SetView("news")')
check("News lists milestones", A.ev(shown) >= 5)

# --- announcements ---
A.ex('__ns.PostNews("Deadmines night", "Friday 8pm server time. Bring a healer!")'); tick(3)
nid = A.ev('__ns.NewsEntries()[1].id')
check("announcement reaches members", B.ev('__ns.NewsEntries()[1].title') == "Deadmines night")
check("members get the announcement pop-up", B.ev('(function() for _, d in ipairs(__dialogs) do if d[1] == "Guild announcement" and d[2]:find("Deadmines night", 1, true) then return true end end end)()') == True
      and B.ev('EPUGuildDialog:IsShown()') == True)
check("unread badge", B.ev('#__ns.UnreadNews()') == 1 and A.ev('#__ns.UnreadNews()') == 0)
B.ex('__ns.MarkNewsRead("%s")' % nid)
check("read clears it", B.ev('#__ns.UnreadNews()') == 0)
B.ex('__ns.PostNews("fake", "fake")'); tick(3)
check("members can't post announcements", A.ev('#__ns.NewsEntries()') == 1)
N.ex('__ns.Send("D", { news = { fake = { t = 1, u = 9999999999, by = "Newbie Stone", title = "fake" } } })'); tick(3)
check("forged announcements ignored", B.ev('#__ns.NewsEntries()') == 1)
A.ex('__ns.UI:OpenDetails("newnews", "new")')
A.ex('__ns.UI.details.pools.box[1]:SetText("Bank open"); __ns.UI.details.pools.box[2]:SetText("Mail Epu Bank anytime")')
A.ex('(function() for _, b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText() == "Post" then b:GetScript("OnClick")(b) end end end)()'); tick(3)
check("posting from the window", B.ev('#__ns.NewsEntries()') == 2 and A.ev('__ns.UI.details.kind') == "news")
A.ex('__ns.RemoveNews("%s")' % nid); tick(3)
check("removing an announcement", B.ev('#__ns.NewsEntries()') == 1)

# --- officer review, notes, log ---
A.ex('__ns.SetPolicy("promoDays", 0); __ns.SetPolicy("promoLevel", 20)'); tick(3)
check("promotion check: lowest rank, meets level, not the bank", A.ev('__ns.Review("Newbie Stone").promote') == True
      and A.ev('__ns.Review("Epu Bank").promote') is None and A.ev('__ns.Review("Tyler Baker").promote') is None)
A.ex('__ns.UI:SetView("officer")')
check("promotion rule spelled out (%s)" % A.ev('__ns.UI.promoRule:GetText()'), "level 20+" in A.ev('__ns.UI.promoRule:GetText()'))
A.ex('__ns.UI:SetView("roster")')
check("inactive flag", A.ev('__ns.Review("Pip Baker").inactive') == True and A.ev('__ns.Review("Chris Stone").inactive') == False)
A.ex('__ns.UI:SetView("roster"); __ns.UI.state.roster.review = "inactive"; __ns.UI:Refresh()')
check("review filter", A.ev(shown) == 1)
A.ex('__ns.UI.state.roster.review = nil; __ns.UI:Refresh()')
A.ex('__ns.SetNote("Newbie Stone", "Great healer, promote soon")'); tick(3)
check("officer notes reach other officers", GM.ev('__ns.GuildStore().notes["Newbie Stone"].text') == "Great healer, promote soon")
check("members never receive officer notes", B.ev('__ns.GuildStore().notes["Newbie Stone"]') is None and N.ev('__ns.GuildStore().notes["Newbie Stone"]') is None)
B.ex('__ns.comm.O("Chris Baker", { notes = { ["Pip Baker"] = { t = 1, text = "x" } } }, "GUILD")')
check("officer data on the guild channel is ignored", B.ev('__ns.GuildStore().notes["Pip Baker"]') is None)
logtxt = "(function() local t = {} for _, e in ipairs(__ns.LogEntries()) do t[#t+1] = e.by .. ': ' .. e.text end return table.concat(t, ' | ') end)()"
check("officer log records actions (%s)" % A.ev(logtxt)[:160], "officer note for Newbie Stone" in A.ev(logtxt)
      and "Posted announcement: Deadmines night" in A.ev(logtxt) and "promoLevel" in A.ev(logtxt))
check("log shared with officers only", "officer note" in GM.ev(logtxt) and B.ev('#__ns.LogEntries()') == 0)
B.ex('__ns.NewRequest(2589, 5)'); tick(3)
rid = A.ev('(function() for id, r in pairs(__ns.G().requests) do if r.who == "Tyler Baker" then return id end end end)()')
A.ex('__ns.EditRequest("%s", { status = "rejected", reason = "we are out" })' % rid); tick(3)
check("request decisions are logged", "Rejected Tyler Baker's request for Linen Cloth x5: we are out" in GM.ev(logtxt))
A.ex('__ns.UI:SetView("officer"); __ns.UI:OpenDetails("log", "all")')
check("officer log details", A.ev('__ns.UI.details.kind') == "log")

# a late officer catches up on notes and log
del clients["Gm Baker"]
GM2 = Client("Gm Baker"); clients["Gm Baker"] = GM2; tick(30)
tick_until(lambda: GM2.ev('__ns.GuildStore().notes["Newbie Stone"] ~= nil') and GM2.ev('#__ns.LogEntries()') > 3, timeout=90)
check("officer catching up gets notes and log", GM2.ev('__ns.GuildStore().notes["Newbie Stone"] ~= nil') == True and GM2.ev('#__ns.LogEntries()') > 3)

# toolbars still fit at the smallest size
fits = A.ev('(function() local bad = {} for _, k in ipairs({"news","roster"}) do __ns.UI:SetView(k) local b = __ns.UI.bars[k] if b.leftX + b.rightX > 480 then bad[#bad+1] = k .. "=" .. (b.leftX + b.rightX) end end return table.concat(bad, ",") end)()')
check("news and roster toolbars fit (%s)" % (fits or "ok"), fits == "")

# --- WoW: Forever lists professions with GetProfessions(), not the old skill list ---
B.ex('GetNumSkillLines = nil; local P = { [5] = {"Blacksmithing", 39}, [7] = {"Mining", 67}, [9] = {"Cooking", 10} }'
     '; function GetProfessions() return 5, 7, nil, nil, 9 end'
     '; function GetProfessionInfo(i) return P[i][1], "icon", P[i][2], 75 end'
     '; __ns.ScanProfessions()'); tick(3)
check("modern profession list read and shared (%s)" % A.ev('(function() local c = __ns.G().crafters["Tyler Baker"] return c and (tostring(c.profs.Blacksmithing) .. "," .. tostring(c.profs.Mining) .. "," .. tostring(c.profs.Cooking)) end)()'),
      A.ev('(function() local c = __ns.G().crafters["Tyler Baker"] return c and c.profs.Blacksmithing == 39 and c.profs.Mining == 67 and c.profs.Cooking == 10 end)()') == True)

# --- a member logging in fresh gets everything, even past the game's message limit ---
for i in range(12):
    A.ex('__ns.PostNews("Notice %d", string.rep("Long announcement text for testing the sync. ", 8))' % i)
for i in range(40):
    A.ex('__ns.SetNeed(%d, 20)' % (50000 + i))
tick(90)
simcore.ROSTER.append(("Late Member", "Initiate", 4))
for c in clients.values():
    c.ex('table.insert(__roster, {"Late Member", "Initiate", 4})')
LM = Client("Late Member"); clients["Late Member"] = LM
tick(180)
check("fresh member got every announcement (%s)" % LM.ev('#__ns.NewsEntries()'), LM.ev('#__ns.NewsEntries()') == A.ev('#__ns.NewsEntries()'))
check("and every need (%s)" % LM.ev('(function() local n = 0 for _ in pairs(__ns.G().needs.list) do n = n + 1 end return n end)()'),
      LM.ev('(function() local n = 0 for _ in pairs(__ns.G().needs.list) do n = n + 1 end return n end)()')
      == A.ev('(function() local n = 0 for _ in pairs(__ns.G().needs.list) do n = n + 1 end return n end)()'))
check("pacing keeps us under the game's limit (%d refused)" % sum((c.ev("__dropped") or 0) for c in clients.values()),
      sum((c.ev("__dropped") or 0) for c in clients.values()) == 0)
# force the game to refuse: the message must still arrive once the limit refills
A.ex('__sendTokens = 0; __sendRefill = __now; __ns.PostNews("After throttle", "still arrives")'); tick(20)
check("a refused message is resent and arrives", A.ev('__dropped') > 0
      and LM.ev('(function() for _, e in ipairs(__ns.NewsEntries()) do if e.title == "After throttle" then return true end end return false end)()') == True)


# --- officers make requests for other members ---
B.ex('__btoasts = {}; __ns.Notify = function(t, x) table.insert(__btoasts, t) end')
A.ex('__ns.UI:Show(); __ns.UI:SetView("requests")')
check("officers get a name box on the request form", A.ev('__ns.UI.forBox:IsShown()') == True and A.ev('__ns.UI.forBtn:IsShown()') != True)
A.ex('__ns.UI.itemBox:SetText(__link(2589)); __ns.UI.qtyBox:SetText("10"); __ns.UI.forBox:SetText("tyl")')
A.ex('__ns.UI.action:GetScript("OnClick")()'); tick(5)
rid = B.ev('(function() for id, r in pairs(__ns.G().requests) do if r.made == "Chris Baker" then return id end end end)()')
check("typing part of a name files it under that member", rid is not None and B.ev('__ns.G().requests["%s"].who' % rid) == "Tyler Baker")
check("approved, and marked who added it", B.ev('__ns.G().requests["%s"].status' % rid) == "approved" and "Chris" in B.ev('__ns.G().requests["%s"].note' % rid))
check("the member is told", "Request added for you" in [B.ev('__btoasts[%d]' % i) for i in range(1, B.ev('#__btoasts') + 1)])
check("it shows as theirs on their PC", B.ev('__ns.G().requests["%s"].who == __ns.me' % rid) == True)
A.ex('__log = {}; __ns.UI.itemBox:SetText(__link(2589)); __ns.UI.forBox:SetText("Nobody Here"); __ns.UI.action:GetScript("OnClick")()')
check("an unknown name is refused with a message", any("No guild member" in (A.ev('__log[%d]' % i) or "") for i in range(1, A.ev('#__log') + 1)))
A.ex('__log = {}; __ns.UI.itemBox:SetText(__link(2589)); __ns.UI.forBox:SetText("Chris"); __ns.UI.action:GetScript("OnClick")()')
check("an ambiguous name lists the matches", any("More than one member" in (A.ev('__log[%d]' % i) or "") for i in range(1, A.ev('#__log') + 1)))
B.ex('__ns.UI:Show(); __ns.UI:SetView("requests")')
check("members don't get the name box", B.ev('__ns.UI.forBox:IsShown()') != True)
n0 = B.ev('(function() local n = 0 for _ in pairs(__ns.G().requests) do n = n + 1 end return n end)()')
B.ex('__ns.NewRequest(2589, 1, "", nil, "Newbie Stone")'); tick(3)
check("members can't file requests for others", B.ev('(function() local n = 0 for _ in pairs(__ns.G().requests) do n = n + 1 end return n end)()') == n0)
# from the roster
A.ex('__ns.UI:SetView("roster"); __ns.UI:OpenDetails("member", "Newbie Stone")')
A.ex('(function() for _, b in ipairs(__ns.UI.details.pools.btn or {}) do if b:IsShown() and (b.text:GetText() or ""):find("Request for") then b:GetScript("OnClick")() end end end)()')
check("Request for… on the roster opens the form with their name", A.ev('__ns.UI.view') == "requests" and A.ev('__ns.UI.forBox:GetText()') == "Newbie Stone")


# --- name suggestions while typing ---
A.ex('__ns.UI:SetView("requests"); __ns.UI.forBox.HasFocus = function() return true end')
A.ex('__ns.UI.forBox:SetText("tyl")')
check("typing suggests matching members", A.ev('__ns.UI.suggest:IsShown()') == True and A.ev('__ns.UI.suggest.names[1]') == "Tyler Baker")
A.ex('__ns.UI.forBox:GetScript("OnTabPressed")(__ns.UI.forBox)')
check("Tab fills in the name", A.ev('__ns.UI.forBox:GetText()') == "Tyler Baker" and A.ev('__ns.UI.suggest:IsShown()') != True)
A.ex('__ns.UI.forBox:SetText("bak")')
check("last names match too", "Tyler Baker" in [A.ev('__ns.UI.suggest.names[%d]' % i) for i in range(1, 9)])
A.ex('__ns.UI.forBox:SetText("Chris")')
check("several matches are all listed", A.ev('#__ns.UI.suggest.names') >= 2)
A.ex('__ns.UI.itemBox:SetText(""); __log = {}; __ns.UI.forBox.onEnter(__ns.UI.forBox)')
check("Enter doesn't guess between several", A.ev('__ns.UI.forBox:GetText()') == "Chris")
A.ex('__ns.UI.forBox:SetText("Chris"); __ns.UI.forBox:GetScript("OnArrowPressed")(__ns.UI.forBox, "UP")')
pick = A.ev('__ns.UI.suggest.names[__ns.UI.suggest.sel]')
A.ex('__ns.UI.forBox.onEnter(__ns.UI.forBox)')
check("arrow keys then Enter picks one (%s)" % pick, A.ev('__ns.UI.forBox:GetText()') == pick and pick.startswith("Chris "))
A.ex('__ns.UI.suggest.rows[1]:GetScript("OnClick")(__ns.UI.suggest.rows[1])') if A.ev('__ns.UI.suggest:IsShown()') else None
A.ex('__ns.UI.forBox:SetText("")')
check("an empty box shows no suggestions", A.ev('__ns.UI.suggest:IsShown()') != True)
# the item hint fits its box
check("item hint is shortened when the box is narrow", A.ev('__ns.UI.itemBox:GetWidth()') >= 200 or A.ev('__ns.UI.itemBox.ph:GetText()') != "Item: shift-click or drag it here")
check("officers see 'Officer copy', not 'Waiting for guild data' (%s)" % A.ev('(__ns.SyncStatus())'),
      A.ev('(__ns.SyncStatus())') in ("Officer copy",) or A.ev('(__ns.SyncStatus())').startswith("Synced"))


# --- item suggestions while typing ---
A.ex('__ns.UI:SetView("requests"); __ns.UI.itemBox.HasFocus = function() return true end; __bags[0] = {{4306, 5}}')
A.ex('__ns.UI.itemBox:SetText("lin")')
names = [A.ev('__ns.UI.suggest.names[%d]' % i) for i in range(1, 9)]
check("typing part of an item name suggests items (%s)" % names, A.ev('__ns.UI.suggest:IsShown()') == True and 2589 in names)
A.ex('__ns.UI.itemBox:SetText("cloth")')
names = [A.ev('__ns.UI.suggest.names[%d]' % i) for i in range(1, 9)]
check("words inside the name match too (Linen Cloth, Silk Cloth)", 2589 in names and 4306 in names)
A.ex('__ns.UI.itemBox:SetText("silk")')
A.ex('__ns.UI.itemBox:GetScript("OnTabPressed")(__ns.UI.itemBox)')
check("Tab puts the item in the box", A.ev('__ns.ItemID(__ns.UI.itemBox:GetText())') == 4306)
check("and the list closes (it's a real item now)", A.ev('__ns.UI.suggest:IsShown()') != True)
A.ex('__ns.UI.itemBox:SetText("l")')
check("one letter isn't enough to search", A.ev('__ns.UI.suggest:IsShown()') != True)
A.ex('__ns.UI.forBox.HasFocus = nil; __ns.UI.qtyBox:SetText("2"); __ns.UI.forBox:SetText(""); __ns.UI.itemBox:SetText("silk")')
n0 = A.ev('(function() local n = 0 for _ in pairs(__ns.G().requests) do n = n + 1 end return n end)()')
A.ex('__ns.UI.itemBox.onEnter(__ns.UI.itemBox)')
check("Enter with a single match picks it (doesn't submit yet)", A.ev('__ns.ItemID(__ns.UI.itemBox:GetText())') == 4306
      and A.ev('(function() local n = 0 for _ in pairs(__ns.G().requests) do n = n + 1 end return n end)()') == n0)
A.ex('__ns.UI.itemBox.onEnter(__ns.UI.itemBox)'); tick(2)
check("a second Enter makes the request", A.ev('(function() local n = 0 for _ in pairs(__ns.G().requests) do n = n + 1 end return n end)()') == n0 + 1)
A.ex('__ns.UI.itemBox.HasFocus = nil; __ns.UI.forBox.HasFocus = nil; __bags[0] = {}')


# --- login pop-up: only the newest, with a count ---
A.ex('for i = 1, 4 do __ns.PostNews("Old " .. i, "text " .. i) end'); tick(5)
A.ex('__ns.PostNews("Newest one", "latest")'); tick(10)
N.ex('__dialogs = {}; __ns.ShowUnreadNews()')
check("one pop-up at login", N.ev('#__dialogs') == 1)
check("it's the newest announcement", "Newest one" in N.ev('__dialogs[1][2]'))
check("and says how many others are unread (%s)" % N.ev('__dialogs[1][2]').split("\n")[-1], "more unread announcement" in N.ev('__dialogs[1][2]'))
N.ex('__dialogs[1][3][1][2]()'); tick(1)
check("Got it doesn't open the next one", N.ev('#__dialogs') == 1)
N.ex('__log = {}; __dialogs = {}; __ns.ShowUnreadNews()')
check("next login: no pop-up for older ones, just a chat line", N.ev('#__dialogs') == 0 and any("unread guild announcement" in (N.ev('__log[%d]' % i) or "") for i in range(1, N.ev('#__log') + 1)))

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

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
check("members get the announcement pop-up", B.ev('(function() for _, p in ipairs(__popups) do if p[1] == "EPUGUILD_NEWS" then return p[4] end end end)()') == nid)
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

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

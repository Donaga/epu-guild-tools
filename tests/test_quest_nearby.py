"""Same quest nearby: quest lists shared by default, heads-ups for guildmates in your zone."""
from simcore import *
for name in ['Chris Baker','Tyler Baker','Pip Baker']: clients[name]=Client(name)
tick(60)
A,B,P=(clients[n] for n in ['Chris Baker','Tyler Baker','Pip Baker'])
def fixture(ids, zone):
    return '''__quests={}; for _,id in ipairs({%s}) do __quests[#__quests+1]={questID=id,title='Quest '..id,isHeader=false,suggestedGroup=(id==1003 and 3 or 0)} end
__zone=%r; GetZoneText=function() return __zone end
C_QuestLog={GetNumQuestLogEntries=function() return #__quests end, GetInfo=function(i) return __quests[i] end,
 IsComplete=function() return false end, IsOnQuest=function(id) for _,q in ipairs(__quests) do if q.questID==id then return true end end return false end,
 GetQuestObjectives=function() return {{numFulfilled=1,numRequired=8}} end}
__toasts={}; local n=__ns.Notify; __ns.Notify=function(t,x,i,c) table.insert(__toasts,{t=t,x=x,c=c}); return n(t,x,i,c) end''' % (','.join(map(str,ids)), zone)
A.ex(fixture([1001,1002,1003],'Westfall'))
B.ex(fixture([1001,1003,1009],'Westfall'))
P.ex(fixture([1002],'Duskwood'))
check('quest sharing is on by default', A.ev('__ns.QuestListSharing()') is True)
for c in (A,B,P): c.ex('__ns.SendQuestList(true)')
check('guildmates receive your quest list', tick_until(lambda: A.ev('__ns.questLists["Tyler Baker"] ~= nil') and A.ev('__ns.questLists["Pip Baker"] ~= nil'), 30))
check('shared quests are worked out', A.ev('#__ns.SharedQuestIDs("Tyler Baker")') == 2 and A.ev('#__ns.SharedQuestIDs("Pip Baker")') == 1)
A.ex('__ns.CheckNearbyQuests()')
toasts = A.ev('(function() local t={} for _,x in ipairs(__toasts) do t[#t+1]=x.t.." | "..x.x end return table.concat(t,"\\n") end)()')
check('a guildmate in your zone on the same quest gets a heads-up', 'Same quest nearby' in toasts and 'Tyler' in toasts and '1 more' in toasts)
check('guildmates in other zones do not', 'Pip' not in toasts)
n = A.ev('#__toasts'); A.ex('__ns.CheckNearbyQuests()')
check('the heads-up comes once per guildmate and quest', A.ev('#__toasts') == n)
A.ex('__combat=true; InCombatLockdown=function() return __combat end; __quests[#__quests+1]={questID=1009,title="Quest 1009",isHeader=false}; __ns.CheckNearbyQuests()')
check('no heads-up in combat', A.ev('#__toasts') == n)
A.ex('__combat=false; __fire("PLAYER_REGEN_ENABLED")'); tick(5)
check('it arrives after combat', A.ev('#__toasts') == n + 1)
# the Quests page
A.ex('__ns.UI:Show(); __ns.UI:SetView("quests")')
rows = A.ev('(function() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data then t[#t+1]=(r.data.key or "").." | "..(r.data.title or "").." | "..(r.data.sub or "").." | "..(r.data.right or "") end end return table.concat(t,"\\n") end)()')
check('Quests is a top-level page', A.ev('__ns.UI.nav.quests ~= nil'))
check('Questing near you lists guildmates in your zone', 'questnear:Tyler Baker' in rows and 'questnear:Pip Baker' not in rows)
check('your quests show how many guildmates are on them', 'quest:1001' in rows and '1 guildmate, 1 nearby' in rows)
check('group quests are flagged', 'group quest (3)' in rows)
A.ex('__ns.UI:OpenDetails("questmatch","1003")')
lb = A.ev('(function() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end)()')
check('a quest offers Ask for help, Whisper and Invite', 'Ask for help with this' in lb and 'Whisper' in lb and 'Invite' in lb)
A.ex('(function() for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()=="Ask for help with this" then b:GetScript("OnClick")(b) end end end)()')
check('Ask for help prefills the quest', A.ev('__ns.UI.details.kind') == 'activityform' and A.ev('(function() for _,e in ipairs(__ns.UI.details.pools.box or {}) do if e:IsShown() and e:GetText()=="Quest 1003" then return true end end return false end)()'))
# Home and Guildmates
A.ex('__ns.UI:SetView("home")')
home = A.ev('(function() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data then t[#t+1]=(r.data.key or "").." | "..(r.data.title or "").." | "..(r.data.sub or "") end end return table.concat(t,"\\n") end)()')
check('Home shows Same quests as you', 'section:Same quests as you' in home and 'questmate:Tyler Baker' in home and 'nearby' in home)
A.ex('__ns.UI.state.roster.filter="online"; __ns.UI:SetView("roster")')
check('Guildmates shows quests in common', 'quests in common' in A.ev('(function() for _,r in ipairs(__ns.UI.rows) do if r.data and r.data.key=="member:Tyler Baker" then return r.data.sub end end end)()'))
# turning it off
B.ex('__ns.SetQuestListSharing(false)')
check('turning sharing off withdraws your list', tick_until(lambda: A.ev('__ns.questLists["Tyler Baker"] == nil'), 30))
print('Quest nearby tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

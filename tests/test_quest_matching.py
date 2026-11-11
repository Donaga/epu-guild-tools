"""Explicit quest consent, paced transient updates and graceful API fallbacks."""
from simcore import *
for name in ['Chris Baker','Tyler Baker']: clients[name]=Client(name)
tick(120)
A,B=(clients[n] for n in ['Chris Baker','Tyler Baker'])
fixture='''__quests={}; for i=1,10 do __quests[i]={questID=1000+i,title='Quest '..i,isHeader=false} end
__progress=2; __complete=false; __wire={}
C_QuestLog={GetNumQuestLogEntries=function() return #__quests end,
 GetInfo=function(i) return __quests[i] end,
 IsComplete=function() return __complete end,
 IsOnQuest=function(id) for _,q in ipairs(__quests) do if q.questID==id then return true end end return false end,
 GetQuestObjectives=function() return {{numFulfilled=__progress,numRequired=8}} end}
local send=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(prefix,msg,channel,target)
 if msg:sub(1,2)=='SQ' then table.insert(__wire,msg) end
 return send(prefix,msg,channel,target)
end
'''
for c in [A,B]:c.ex(fixture)
check('modern quest log returns active quests and progress',A.ev('__ns.CurrentQuests()[1001].progress')=='2/8')
A.ex('__ns.SelectSharedQuest(1001,true); __advance(3)')
check('selecting a quest does not silently enable sharing',not A.ev('__ns.CommunityState().shareQuests') and A.ev('#__wire')==0)
A.ex('__ns.SetQuestSharing(true)')
check('explicit sharing sends selected quest to guild peer',tick_until(lambda:B.ev('__ns.sharedQuests["Chris Baker"] and __ns.sharedQuests["Chris Baker"][1001]') is not None,30))
check('unselected quests are never sent',B.ev('__ns.sharedQuests["Chris Baker"][1002]') is None)
check('matching is based on exact quest IDs in own log',B.ev('#__ns.QuestMatches(1001)')==1 and B.ev('#__ns.QuestMatches(1002)')==0)
check('quest packets fit the disposable single-packet limit',A.ev('(function() for _,msg in ipairs(__wire) do if #msg>250 then return false end end return true end)()'))
A.ex('__progress=5; __fire("QUEST_LOG_UPDATE")')
check('progress updates are coalesced and delivered',tick_until(lambda:B.ev('__ns.sharedQuests["Chris Baker"][1001].progress')=='5/8',60))
tick(190)
check('stationary selected quests heartbeat instead of disappearing',B.ev('#__ns.QuestMatches(1001)')==1)
A.ex('__complete=true; __fire("QUEST_LOG_UPDATE")')
check('completed quest indicates ready to turn in',tick_until(lambda:B.ev('__ns.sharedQuests["Chris Baker"][1001].done'),60))
A.ex('__ns.SelectSharedQuest(1001,false)')
check('unselecting withdraws that quest immediately',tick_until(lambda:B.ev('__ns.sharedQuests["Chris Baker"][1001]') is None,30))
A.ex('for id=1001,1008 do __ns.SelectSharedQuest(id,true) end')
check('selection is capped at eight quests',A.ev('__ns.SelectSharedQuest(1009,true)') is None)
A.ex('__ns.UpdateQuestSharing()')
check('several selected quests keep separate queued packet identities',tick_until(lambda:B.ev('(function() local n=0 for _ in pairs(__ns.sharedQuests["Chris Baker"] or {}) do n=n+1 end return n end)()')==8,60))
A.ex('__ns.SetQuestSharing(false)')
check('opt-out withdraws every shared quest',tick_until(lambda:B.ev('next(__ns.sharedQuests["Chris Baker"] or {})==nil'),30))
A.ex('__wire={}; __advance(180)')
check('opt-out stops future heartbeats',A.ev('#__wire')==0)
B.ex("__ns.comm.Q('Stranger',{id=1001,title='Fake',p='8/8',done=true,u=__now},'GUILD'); __ns.comm.Q('Chris Baker',{id=1001,title='Whisper',p='8/8',done=true,u=__now},'WHISPER')")
check('unknown senders and whisper relays are ignored',B.ev('#__ns.QuestMatches(1001)')==0)
B.ex("__ns.comm.Q('Chris Baker',{id=1001,title='Valid',p='2/8',done=false,u=__now},'GUILD'); __ns.comm.Q('Chris Baker',{id=1001,title='Too fast',p='8/8',done=true,u=__now},'GUILD')")
check('duplicate revisions cannot rewrite progress',B.ev('__ns.sharedQuests["Chris Baker"][1001].title')=='Valid')
B.ex("__ns.comm.Q('Chris Baker',{id=-1,title='Invalid',p='2/8',done=false,u=__now},'GUILD')")
check('invalid quest IDs are rejected',B.ev('__ns.sharedQuests["Chris Baker"][-1]') is None)
check('remote quest progress does not enter SavedVariables', 'Valid' not in B.ev('__ns.Serialize(EPUGuildDB)') and 'sharedQuests' not in B.ev('__ns.Serialize(EPUGuildCharDB)'))
B.ex("__ns.roster['Chris Baker'].online=false; __ns.ExpireQuestMatches()")
check('offline guildmates disappear from quest matches',B.ev('#__ns.QuestMatches(1001)')==0)
B.ex("__ns.roster['Chris Baker'].online=true; __ns.comm.Q('Chris Baker',{id=1001,title='Valid',p='2/8',done=false,u=__now},'GUILD'); __advance(181); __ns.ExpireQuestMatches()")
check('old progress expires after three minutes',B.ev('#__ns.QuestMatches(1001)')==0)
A.ex('__quests={}; __fire("QUEST_LOG_UPDATE"); __ns.SetQuestSharing(true); __ns.UpdateQuestSharing()')
check('confirmed abandoned quests are removed from selection',A.ev('next(__ns.CommunityState().selectedQuests)==nil'))
A.ex("C_QuestLog.GetNumQuestLogEntries=function() error('restricted') end")
check('restricted quest API degrades without runtime error',A.ev('select(2,__ns.CurrentQuests())') is not None)
A.ex("C_QuestLog=nil; GetNumQuestLogEntries=function() return 1 end; GetQuestLogTitle=function() return 'Legacy quest',12,nil,false,nil,1,nil,2001 end; GetNumQuestLeaderBoards=function() return 1 end; GetQuestLogLeaderBoard=function() return 'Done','monster',true end")
check('legacy quest APIs still provide IDs and completion',A.ev('__ns.CurrentQuests()[2001].done') is True)
A.ex('GetNumQuestLogEntries=nil; GetQuestLogTitle=nil')
check('missing quest APIs produce a helpful unavailable state',A.ev('select(2,__ns.CurrentQuests())') is not None)
B.ex("SlashCmdList.EPUGUILD('quests'); __ns.UI:OpenDetails('questmatch',1001)")
check('quest match detail renders without errors',(B.ev('__errors') or 0)==0 and B.ev('__ns.UI.details.title:GetText()')=='Quest 1')
B.ex("__ns.UI:OpenDetails('questsettings','settings')")
check('quest sharing settings render without errors',(B.ev('__errors') or 0)==0)
print('Quest matching tests:',check.failed,'failed')
sys.exit(1 if check.failed else 0)

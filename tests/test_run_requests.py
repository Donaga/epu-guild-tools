"""Run requests: ask for a dungeon run, mark the times that suit you, find the best overlap, schedule it."""
from simcore import *

names = ['Chris Baker', 'Tyler Baker', 'Pip Baker', 'Chris Stone']
for n in names:
    clients[n] = Client(n)
A, B, P, S = (clients[n] for n in names)
tick(120)
for c in clients.values():
    c.ex('function __slot(h) return __ns.RunSlot(__now,true)+h*1800 end')

check('nothing extra is synced while nobody uses run requests', A.ev('__ns.Digest().fields.runRequests') is None)
check('times must be on the 30-minute grid',
      B.ev("__ns.ValidRunRequest('Tyler Baker\\031x',{who='Tyler Baker',t=__now,created=__now,dungeon='The Deadmines',purpose='q',note='',role='t',status='open',windows={{s=__slot(2)+60,e=__slot(6)}}})") is False)
check('a request needs at least one time that has not passed',
      B.ev("__ns.SaveRunRequest({dungeon='The Deadmines',purpose='q',role='t',windows={{s=__slot(-8),e=__slot(-4)}}})") is None)
run = B.ev("""__ns.SaveRunRequest({dungeon='The Deadmines',purpose='q',role='t',note='Need the Defias quests',
  windows={{s=__slot(2),e=__slot(8)},{s=__slot(50),e=__slot(54)},{s=__slot(60),e=__slot(62)},{s=__slot(70),e=__slot(72)}}})""")
check('a member can request a run', run is not None)
for c in clients.values():
    c.rt.globals()['run'] = run
check('at most three time ranges are kept', B.ev('#__ns.CasualStore().runRequests[run].windows') == 3)
check('the request reaches guildmates', tick_until(lambda: A.ev('(__ns.CasualStore().runRequests[run] or {}).dungeon') == 'The Deadmines', 60)
      and tick_until(lambda: P.ev('__ns.CasualStore().runRequests[run]~=nil') and S.ev('__ns.CasualStore().runRequests[run]~=nil'), 60))

seen = lambda c: c.ev('(function() for k in pairs(__ns.CommunityState().seen) do if k:find("run\\031"..run,1,true) then return true end end return false end)()')
check('guildmates get a notice about the new run request', seen(P))
A.ex("__ns.RespondRunRequest(run,'in','h',{{s=__slot(3),e=__slot(6)}},'After dinner')")
P.ex("__ns.RespondRunRequest(run,'in','d',{{s=__slot(2),e=__slot(8)}},'')")
S.ex("__ns.RespondRunRequest(run,'in','d',{{s=__slot(50),e=__slot(54)}},'')")
check('interest syncs back to the requester', tick_until(lambda: len(B.ev('__ns.RunInterested(run)') or {}) == 3, 60))
check('the requester gets a notice when someone is in', seen(B))
check("you can't mark interest in your own request", B.ev("__ns.RespondRunRequest(run,'in','t',{{s=__slot(2),e=__slot(8)}},'')") is None)
best = lambda c: c.ev('(function() local b=__ns.RunBestTimes(run,3)[1] return b.s..","..b.e..","..#b.who..","..b.roles.t..b.roles.h..b.roles.d end)()')
check('the best time is where most people overlap, with role counts',
      best(B) == B.ev('__slot(3)..","..__slot(6)..",3,111"'))
check('the second best time is the other evening', B.ev('(function() local b=__ns.RunBestTimes(run,3) return #b[2].who end)()') == 2)
B.ex("__ns.Send('D',{runInterest={[run..'\\030Chris Stone']={who='Chris Stone',request=run,state='out',role='d',note='',t=__now+5}}})")
tick(4)
check("a member can't change someone else's interest", A.ev("__ns.CasualStore().runInterest[run..'\\030Chris Stone'].state") == 'in')

# UI
B.ex("__ns.UI:Show(); __ns.UI.state.activities.kind='runs'; __ns.UI:SetView('activities'); __ns.UI:Refresh()")
rows = B.ev('(function() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.title then t[#t+1]=r.data.title.." | "..(r.data.right or "") end end return table.concat(t,"\\n") end)()')
check('the Run requests board lists it with interest and the best time', 'The Deadmines · Quests' in rows and '4 in' in rows and 'best' in rows)
labels = lambda c: c.ev('(function() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end for _,f in ipairs(__ns.UI.details.pools.text) do if f:IsShown() then t[#t+1]=f:GetText() end end return table.concat(t,"|") end)()')
B.ex("__ns.UI:OpenDetails('run',run)")
lb = labels(B)
check('the requester sees best times with Schedule buttons', 'Best times' in lb and 'Schedule ' in lb and '3 people' in lb)
P.ex("__ns.UI:Show(); __ns.UI:OpenDetails('run',run)")
lp = labels(P)
check('guildmates can tick times and update their interest', '[x] ' in lp and 'Update' in lp and 'Not anymore' in lp)
B.ex("__ns.UI:OpenDetails('runform','new')")
lf = labels(B)
check('the request form has a dungeon list, purpose, role and time pickers',
      all(s in lf for s in ('Choose dungeon', 'Quests', 'Loot farming', 'Quests or loot', 'Tank', 'From ', 'To ', 'Add another day', 'Post request')))
check('the form shows no errors', B.ev('__errors') in (None, 0))

# scheduling
ev = B.ev("__ns.ScheduleRunRequest(run,__slot(3),90,nil)")
for c in clients.values():
    c.rt.globals()['ev'] = ev
check('scheduling makes a dungeon event and marks the request', ev is not None and B.ev('__ns.CasualStore().runRequests[run].status') == 'scheduled'
      and B.ev('__ns.CasualStore().guildEvents[ev].kind') == 'dungeon')
check('people who picked that time are signed up with their role',
      tick_until(lambda: (A.ev("(__ns.CasualStore().eventResponses[ev..'\\030Chris Baker'] or {}).role") == 'h'
                          and P.ev("(__ns.CasualStore().eventResponses[ev..'\\030Pip Baker'] or {}).state") == 'going'), 90))
check("someone who picked other times isn't signed up",
      tick_until(lambda: S.ev("__ns.CommunityState().runJoined and __ns.CommunityState().runJoined[run]") is True, 60)
      and S.ev("__ns.CasualStore().eventResponses[ev..'\\030Chris Stone']") is None)
check('it only signs you up once', A.ev("__ns.RespondGuildEvent(ev,'declined','h','')") and (A.ex('__ns.CheckScheduledRuns()') or True)
      and A.ev("__ns.CasualStore().eventResponses[ev..'\\030Chris Baker'].state") == 'declined')

# closing and expiry
run2 = P.ev("__ns.SaveRunRequest({dungeon='Wailing Caverns',purpose='l',role='d',windows={{s=__slot(4),e=__slot(6)}}})")
P.rt.globals()['run2'] = run2
check('the requester can close a request', P.ev('__ns.CloseRunRequest(run2)') and not P.ev('__ns.RunActive(__ns.CasualStore().runRequests[run2])'))
P.ex("__ns.CasualStore().runRequests[run].status='open'; __advance(40*3600)")
check('requests end when their last time passes', not P.ev("__ns.RunActive(__ns.CasualStore().runRequests[run])"))
check('no runtime errors', all(c.ev('__errors') in (None, 0) for c in clients.values()))

print('Run request tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

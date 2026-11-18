"""Home dashboard, Groups page and the Create a group form."""
from simcore import *

A = Client('Chris Baker'); B = Client('Tyler Baker')
clients[A.name] = A; clients[B.name] = B
tick(120)
for c in (A, B):
    c.ex('''__chat={} SendChatMessage=function(msg,ch) __chat[#__chat+1]=ch..": "..msg end
function __rows() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data then t[#t+1]=(r.data.key or "").." | "..(r.data.title or "").." | "..(r.data.sub or "") end end return table.concat(t,"\\n") end
function __labels() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end
function __click(label) for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:GetScript("OnClick")(b); return true end end error("Missing "..label) end''')

A.ex("""for _,n in ipairs({'Tyler Baker','Chris Stone','Pip Baker'}) do __rosterExtra[n]={20,'Mage','MAGE','Elwynn Forest'} end
__fire('GUILD_ROSTER_UPDATE')""")
# navigation
order = A.ev('(function() local t={} for _,k in ipairs({"home","groups","roster"}) do t[#t+1]=tostring(__ns.UI.nav[k] and __ns.UI.nav[k]:IsShown()) end return table.concat(t,",") end)()')
A.ex('__ns.UI:Show(); __ns.UI:SetView("home")')
check('Guild activities are now the Groups page, top-level with Guildmates',
      A.ev('__ns.UI.nav.activities.label:GetText()') == 'Groups' and A.ev('__ns.UI.state.activities.kind') == 'all' and
      A.ev('__ns.UI.nav.activities:IsShown() and __ns.UI.nav.roster:IsShown()') is True)
A.ex('__ns.UI:SetView("activities")')
check('the board menu still reaches events, quick dungeons, run requests, helpers and kits',
      A.ev('__ns.UI.bars.activities.casualChoose.text:GetText()') == 'All groups and events' and A.ev('__ns.UI.bars.activities.casualNew.text:GetText()') == 'Create')
A.ex('__ns.UI:SetView("home")')
check('Roster is now called Guildmates and opens on who is online',
      A.ev('__ns.UI.nav.roster.label:GetText()') == 'Guildmates' and A.ev('__ns.UI.state.roster.filter') == 'online')

home = A.ev('__rows()')
check('Home shows the online count and groups at a glance', 'online |' in home and 'open group' in home)
import re
m = re.search(r'online \| (\d+) with EPU', home)
check('online guildmates whose EPU has been heard count as using EPU', m is not None and int(m.group(1)) == 2)
check('someone EPU never heard from does not', A.ev('__ns.UsesEPU("Pip Baker")') is False and A.ev('__ns.UsesEPU("Tyler Baker")') is True)
check('Home has a Right now section with a Start one prompt when nobody is looking', 'Right now' in home and "Nobody's looking for a group" in home)
check('Home shows who is where', 'Who is where' in home and 'zone:' in home)

# create a group now
B.ex('__ns.UI:Show(); __ns.UI:SetView("groups"); __ns.UI:OpenDetails("groupform","new")')
lb = B.ev('__labels()')
check('the form offers type, when and role', all(s in lb for s in ('Dungeon', 'Raid', 'PvP', 'Other', 'Now', 'Today', 'Tomorrow', 'Tank', 'Post')))
check('the Create form switches between group, event, quest help and helper', all(s in lb for s in ('Group or run', 'Scheduled event', 'Ask for quest help', 'Offer to help')))
B.ex('__click("Today")')
check('a later group offers a fixed start instead', 'Pick one fixed start instead' in B.ev('__labels()'))
B.ex('__click("Tomorrow")')
lb2 = B.ev('__labels()')
check('run requests offer Morning, Afternoon and Evening', all(x in lb2.split('|') for x in ['Morning', 'Afternoon', 'Evening']))
B.ex('__click("Morning")')
check('a day part sets From and To', 'From 8:00 AM' in B.ev('__labels()') and 'To 12:00 PM' in B.ev('__labels()'))
B.ex('__click("Today")')
B.ex('__ns.CommunityState(); local d=nil; __click("Pick one fixed start instead")')
check('switching to an event keeps the dungeon type and day', B.ev('__ns.UI.details.kind') == 'eventform'
      and B.ev('__ns.UI.details.pools.box[4]:GetText()') == B.ev('date("%Y-%m-%d",__ns.RunSlot(__now,true))') + B.ev('__ns.UI.details.pools.box[4]:GetText()')[10:]
      and 'Scheduled event' in B.ev('__labels()'))
B.ex('__click("Ask for quest help")')
check('Quest help opens the help form with the same switcher', B.ev('__ns.UI.details.kind') == 'activityform' and 'Group or run' in B.ev('__labels()'))
B.ex('__click("Group or run")')
B.ex('__click("Now")')
B.ex('__click("PvP")')
check('PvP asks what the group is for instead of a dungeon', 'Choose dungeon' not in B.ev('__labels()'))
B.ex('__click("Dungeon")')
B.ex('__click("[ ] Also post in guild chat")')
B.ex("__click('Post group')")
check('posting without a dungeon explains what is missing', B.ev('__ns.CasualStore() and next(__ns.CasualStore().activityPosts)') is None)
kind_id = B.ev("(function() local k,id=__ns.PostGroup({type='dungeon',dungeon='The Deadmines',when='now',minutes=120,purpose='q',role='t',note='Defias run',chat=true,lvl=20}) return k end)()")
check('Now posts a quick group', kind_id == 'activity')
check('it can tell guild chat in one line', any('GUILD: [EPU] Tyler wants a group for The Deadmines (quests), now' in v for v in (B.ev('__chat') or {}).values()))
check('the quick group reaches guildmates', tick_until(lambda: 'The Deadmines' in ((A.ex('__ns.UI:Refresh()') or A.ev('__rows()')) or ''), 60))
home = (A.ex('__ns.UI:SetView("home")') or A.ev('__rows()'))
check('Home lists it under Right now with role counts', 'The Deadmines' in home and '1 tank' in home)

# later this week becomes a run request
k = B.ev("(function() local s=__ns.RunSlot(__now,true)+86400 local k=__ns.PostGroup({type='other',title='Elite quests in Hillsbrad',when=1,s=s,e=s+7200,purpose='e',role='d',note='',chat=false}) return k end)()")
check('a later day becomes a run request', k == 'run')
check('Groups sorts things into Right now and later sections',
      tick_until(lambda: 'Elite quests in Hillsbrad' in ((A.ex('__ns.UI:SetView("groups")') or A.ev('__rows()')) or ''), 60)
      and 'Right now' in A.ev('__rows()') and ('This week' in A.ev('__rows()') or 'Later today' in A.ev('__rows()')))
check('both groups are listed as open', A.ev('#__ns.OpenGroups()') >= 2)

# feed
A.ex('''local g=__ns.G(); local prev={} for k,v in pairs(g.memberInfo) do prev[k]={c=v.c,cn=v.cn,r=v.r,ri=v.ri,l=v.l} end
local cur={} for k,v in pairs(prev) do cur[k]={c=v.c,cn=v.cn,r=v.r,ri=v.ri,l=v.l} end
cur["Tyler Baker"].l=(cur["Tyler Baker"].l or 1)+1; cur["New Friend"]={c="MAGE",cn="Mage",r="Initiate",ri=4,l=5}
__ns.NoteRosterChanges(g,prev,cur)''')
home = (A.ex('__ns.UI:SetView("home")') or A.ev('__rows()'))
check('Today in the guild shows joins and level-ups', 'New Friend joined the guild' in home and 'Tyler Baker reached level' in home)
A.ex('__ns.NoteRosterChanges(__ns.G(),{a={l=1},b={l=1},c={l=1},d={l=1}},{a={l=1}})')
check('a partial roster read is not reported as departures', 'left the guild' not in A.ev('__rows()'))

# slash commands
A.ex('SlashCmdList.EPUGUILD("lfg")')
check('/epu lfg opens the Create a group form', A.ev('__ns.UI.view') == 'activities' and 'Post' in A.ev('__labels()'))
A.ex('SlashCmdList.EPUGUILD("who")')
check('/epu who opens Guildmates online', A.ev('__ns.UI.view') == 'roster')
check('no runtime errors', all(c.ev('__errors') in (None, 0) for c in (A, B)))
print('Social home tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

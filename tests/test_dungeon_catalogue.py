"""0.27.0 dungeon catalogue, raid picker and the clearer run-request wording."""
from simcore import *

A = Client('Chris Baker'); B = Client('Tyler Baker')
clients[A.name] = A; clients[B.name] = B
tick(120)
for c in (A, B):
    c.ex('''function __rows() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data then t[#t+1]=(r.data.key or "").." | "..(r.data.title or "").." | "..(r.data.sub or "") end end return table.concat(t,"\\n") end
function __labels() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end
function __texts() local t={} for _,f in ipairs(__ns.UI.details.pools.text or {}) do if f:IsShown() then t[#t+1]=f:GetText() end end return table.concat(t,"|") end
function __click(label) for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:GetScript("OnClick")(b); return true end end error("Missing "..label) end''')
A.ex("""__rosterExtra['Chris Baker']={20,'Warrior','WARRIOR','Westfall'}
__rosterExtra['Tyler Baker']={21,'Mage','MAGE','Westfall'}
__rosterExtra['Pip Baker']={58,'Priest','PRIEST','Felwood'}
__fire('GUILD_ROSTER_UPDATE')""")
tick(2)
A.ex('__ns.UI:Show(); __ns.UI.state.activities.kind="dungeons"; __ns.UI:SetView("activities")')
rows = A.ev('__rows()')
check('the catalogue lists classic and Forever dungeons and raids',
      'dungeon:The Deadmines' in rows and 'dungeon:Hall of Thanes' in rows and 'dungeon:Molten Core' in rows and 'cat:raids' in rows)
check('dungeons show their level range', 'levels 17–26' in rows)
check('dungeons in your level range are marked', A.ev('(function() for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key=="dungeon:The Deadmines" then return r.data.right end end end)()') is not None)
check('the catalogue counts guildmates online in range', 'online in range' in A.ev('(function() for _,r in ipairs(__ns.UI.rows) do if r.data and r.data.key=="dungeon:The Deadmines" then return r.data.sub end end end)()'))
A.ex('__ns.UI.state.activities.near=true; __ns.UI:Refresh()')
rows = A.ev('__rows()')
check('Near my level keeps only dungeons in range', 'dungeon:The Deadmines' in rows and 'dungeon:Molten Core' not in rows)
A.ex('__ns.UI.state.activities.near=false')
# details
A.ex('__ns.UI:OpenDetails("dungeoninfo","The Deadmines")')
lb = A.ev('__labels()')
check('details offer Start a group now and Request a run', 'Start a group now' in lb and 'Request a run' in lb)
check('details list guildmates online in range', 'Tyler Baker' in lb and 'Pip Baker' not in lb)
A.ex('__click("Request a run")')
check('Request a run opens Create prefilled with the dungeon and a day',
      A.ev('__ns.UI.details.kind') == 'groupform' and 'The Deadmines' in A.ev('__labels()') and 'Post run request' in A.ev('__labels()'))
A.ex('__click("Post run request")'); tick(3)
A.ex('__ns.UI:OpenDetails("dungeoninfo","The Deadmines")')
check('the run request shows on the dungeon', any(s.startswith('The Deadmines ·') for s in A.ev('__labels()').split('|')))
A.ex('__ns.UI.state.activities.kind="dungeons"; __ns.UI:SetView("activities")')
check('the catalogue counts the open run request', '1 open' in A.ev('__rows()'))
# raid picker
A.ex('__ns.OpenCreate("group"); __click("Raid")')
check('Raid offers a raid picker', 'Choose raid' in A.ev('__labels()'))
A.ex('__ns.UI:OpenDetails("dungeoninfo","Molten Core")')
A.ex('__click("Start a group now")')
check('a raid from the catalogue prefills the raid', 'Molten Core' in A.ev('__labels()') and 'Post group' in A.ev('__labels()'))
# the sidebar opens Groups on Everything again
A.ex('__ns.UI.state.activities.kind="events"; __ns.UI:SetView("home"); __ns.UI.nav.activities:Click()')
check('the sidebar opens Groups on Everything', A.ev('__ns.UI.state.activities.kind') == 'all')
A.ex('__ns.UI:SetView("home"); __ns.EventBubbleLFG:GetScript("OnClick")(__ns.EventBubbleLFG,"LeftButton")')
check('the Events bubble has a Groups button', A.ev('__ns.UI.view') == 'activities')
A.ex('__ns.EventBubbleLFG:GetScript("OnClick")(__ns.EventBubbleLFG,"RightButton")')
check('right-clicking it starts a group', A.ev('__ns.UI.details.kind') == 'groupform')
A.ex('__ns.UI:SetView("home"); EPUGuild_Binding("groups")')
check('the Groups key binding opens Groups', A.ev('__ns.UI.view') == 'activities' and A.ev('BINDING_NAME_EPUGUILD_GROUPS') is not None)
print('Dungeon catalogue tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

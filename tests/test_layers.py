"""Layer detection from NPC GUIDs, sharing it with the location, and the Roster tags."""
from simcore import *

A=Client('Chris Baker')
A.ex('''__advance(120); __sent={}
__maps={[42]={name='Elwynn',mapType=3,parentMapID=13},[4242]={name='Fargodeep Mine',mapType=5,parentMapID=42},
 [40]={name='Westfall',mapType=3,parentMapID=13},[13]={name='Eastern Kingdoms',mapType=2,parentMapID=947}}
__map=42
C_Map={GetMapInfo=function(id) return __maps[id] end,
GetBestMapForUnit=function() return __map end,
GetPlayerMapPosition=function() return {GetXY=function() return 0.4,0.5 end} end}
IsInInstance=function() return __instance end
__guids={}
UnitGUID=function(unit) return __guids[unit] end
strsplit=strsplit or function(sep,s)
  local out={} for part in (s..sep):gmatch('(.-)'..sep:gsub('%p','%%%0')) do out[#out+1]=part end
  return unpack(out)
end
local send=__ns.SendEphemeral
__ns.SendEphemeral=function(kind,p,ttl,guard) if kind=='L' then __sent[#__sent+1]=p end return send(kind,p,ttl,guard) end
function __see(unit,guid,event,...) __guids[unit]=guid; __fire(event or 'PLAYER_TARGET_CHANGED',...) end
function __receive(who,d) __ns.comm.L(who,d,'GUILD') end
__opened={}
ChatFrame_OpenChat=function(text) __opened[#__opened+1]=text end
for _,n in ipairs({'Tyler Baker','Chris Stone','Pip Baker'}) do __rosterExtra[n]={20,'Mage','MAGE','Elwynn Forest'} end
__fire('GUILD_ROSTER_UPDATE')
''')

check('nothing is known before any NPC is seen',A.ev('__ns.MyLayer()') is None)
A.ex("__see('target','Player-4372-0ABCDEF0')")
check('player GUIDs carry no layer and are ignored',A.ev('__ns.MyLayer()') is None)
A.ex("issecretvalue=function(v) return v=='secret' end; __see('target','secret'); issecretvalue=nil")
check('secret GUIDs are ignored without errors',A.ev('__ns.MyLayer()') is None)
A.ex("__see('target','Creature-0-4372-0-1234-299-0000ABCDEF')")
check('targeting an NPC reads the layer from its GUID',A.ev('__ns.MyLayer().id')==1234 and A.ev('__ns.MyLayer().zone')==42)
A.ex("__see('nameplate3','Vehicle-0-4372-0-1234-300-0000ABCDEF','NAME_PLATE_UNIT_ADDED','nameplate3')")
check('nameplates and vehicles also count',A.ev('__ns.MyLayer().id')==1234)

A.ex('__ns.UpdateGuildLocation()')
check('your location message carries your layer',A.ev('__sent[#__sent].l')==1234 and A.ev('__sent[#__sent].map')==42)

A.ex('''__receive('Tyler Baker',{map=42,x=0.3,y=0.4,l=1234})
__receive('Chris Stone',{map=42,x=0.5,y=0.4,l=5678})
__receive('Pip Baker',{map=4242,x=0.5,y=0.5,l=1234})
__receive('Newbie Stone',{map=42,x=0.5,y=0.5})''')
check('same layer is recognised',A.ev("__ns.LayerOf('Tyler Baker')")=='same')
check('another layer of your zone is recognised',A.ev("__ns.LayerOf('Chris Stone')")=='other')
check('caves and sub-maps compare against their zone',A.ev("__ns.LayerOf('Pip Baker')")=='same')
check('guildmates on an older EPU show no layer instead of a guess',A.ev("__ns.LayerOf('Newbie Stone')") is None)
A.ex("__advance(6); __receive('Tyler Baker',{map=42,x=0.3,y=0.4,l=-3}); __advance(6); __receive('Chris Stone',{map=42,x=0.5,y=0.4,l='5678'})")
check('malformed layer ids are dropped',A.ev("__ns.LayerOf('Tyler Baker')") is None and A.ev("__ns.LayerOf('Chris Stone')") is None)
A.ex("__advance(6); __receive('Tyler Baker',{map=42,x=0.3,y=0.4,l=1234}); __receive('Chris Stone',{map=42,x=0.5,y=0.4,l=5678})")

A.ex("__ns.UI:Show(); __ns.UI.state.roster.filter='all'; __ns.UI:SetView('roster')")
def sub(name):
    return A.ev(f"""(function()
  for _,row in ipairs(__ns.UI.rows) do
    if row:IsShown() and row.data and row.data.key=='member:{name}' then return row.data.sub or '' end
  end
end)()""")
check('Roster tags a guildmate on your layer',(sub('Tyler Baker') or '').find('same layer')>=0)
check('Roster tags a guildmate on another layer',(sub('Chris Stone') or '').find('other layer')>=0)
check('Roster shows no tag when the layer is unknown','layer' not in (sub('Newbie Stone') or 'x'))
check('your own row has no layer tag','layer' not in (sub('Chris Baker') or ''))
A.ex("__ns.UI.state.roster.filter='layer'; __ns.UI:Refresh()")
shown=A.ev("""(function() local t={}
  for _,row in ipairs(__ns.UI.rows) do if row:IsShown() and row.data and row.data.key then t[#t+1]=row.data.key end end
  table.sort(t); return table.concat(t,',') end)()""")
check('Same layer filter keeps only guildmates on your layer',shown=='member:Pip Baker,member:Tyler Baker')

def labels():
    return A.ev("""(function() local t={}
  for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end
  for _,f in ipairs(__ns.UI.details.pools.text) do if f:IsShown() then t[#t+1]=f:GetText() end end
  return table.concat(t,'|') end)()""")
A.ex("__ns.UI:OpenDetails('member','Chris Stone')")
l=labels()
check('member details say they are on another layer','another layer of Elwynn Forest' in l)
check('member details offer Ask to join their layer','Ask to join their layer' in l)
A.ex("""for _,b in ipairs(__ns.UI.details.pools.btn) do
  if b:IsShown() and b.text:GetText()=='Ask to join their layer' then b:GetScript('OnClick')(b) end end""")
check('the button opens a prefilled whisper asking for an invite',A.ev("__opened[#__opened]:find('^/w Chris Stone Could you invite me',1)~=nil"))
A.ex("__ns.UI:OpenDetails('member','Tyler Baker')")
l=labels()
check('same-layer members get no join button','Same layer as you' in l and 'Ask to join their layer' not in l)

A.ex("__sent={}; __advance(31); __ns.UpdateGuildLocation(); __see('mouseover','Creature-0-4372-0-9999-299-0000ABCDEF','UPDATE_MOUSEOVER_UNIT'); __advance(5); __ns.UpdateGuildLocation()")
A.ex("__see('mouseover','Creature-0-4372-0-1234-299-0000ABCDEF','UPDATE_MOUSEOVER_UNIT'); __advance(1); __see('mouseover','Creature-0-4372-0-9999-299-0000ABCDEF','UPDATE_MOUSEOVER_UNIT'); __advance(9)")
check('flipping between layers sends at most one update per 20 seconds',A.ev('#__sent')<=2)
A.ex("__advance(6); __ns.UpdateGuildLocation()")
check('a layer change reaches guildmates within about ten seconds',A.ev('__sent[#__sent].l')==9999)
check('switching layers flips the tags',A.ev("__ns.LayerOf('Tyler Baker')")=='other')

A.ex("__map=40")
check('changing zone hides a layer from the old zone',A.ev('__ns.MyLayer()') is None and A.ev("__ns.LayerOf('Tyler Baker')") is None)
A.ex("__map=42; __fire('ZONE_CHANGED_NEW_AREA')")
check('a new area clears the old reading',A.ev('__ns.MyLayer()') is None)
A.ex("__instance=true; __see('target','Creature-0-4372-0-777-299-0000ABCDEF')")
check('dungeon NPCs never count as a world layer',A.ev('__ns.MyLayer()') is None)
A.ex("__instance=false; __see('target','Creature-0-4372-0-1234-299-0000ABCDEF'); __advance(301)")
check('readings go stale after five minutes',A.ev('__ns.MyLayer()') is None)
check('layer data is never saved',"5678" not in A.ev('__ns.Serialize(EPUGuildDB)'))

print('Layer tests:',check.failed,'failed')
sys.exit(1 if check.failed else 0)

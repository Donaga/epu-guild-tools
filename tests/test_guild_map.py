"""Location privacy, disposable paced traffic and the mapping-library boundary."""
from simcore import *

A=Client('Chris Baker')
A.ex('''__advance(120); __positions={}; __world={}; __mini={}; __pins={}
C_Map={GetMapInfo=function(id) if id==42 then return {name='Elwynn'} end end,
GetBestMapForUnit=function() return 42 end,
GetPlayerMapPosition=function() return {GetXY=function() return __x or 0.4,0.5 end} end}
IsInInstance=function() return __instance end
function __pins:AddWorldMapIconMap(ref,f,map,x,y,flag) __world[f]={map,x,y,flag}; f:Show() end
function __pins:AddMinimapIconMap(ref,f,map,x,y,parent,edge) __mini[f]={map,x,y,parent,edge}; f:Show() end
function __pins:RemoveWorldMapIcon(ref,f) __world[f]=nil; f:Hide() end
function __pins:RemoveMinimapIcon(ref,f) __mini[f]=nil; f:Hide() end
LibStub=function() return __pins end
local send=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(prefix,msg,channel,target)
 if msg:sub(1,2)=='SL' then table.insert(__positions,msg) end
 return send(prefix,msg,channel,target)
end
function __count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function __receive(d,ch,who) __ns.comm.L(who or 'Tyler Baker',d,ch or 'GUILD') end
''')
A.ex('__ns.UpdateGuildLocation()')
check('sharing starts off',A.ev('#__positions')==0)
A.ex('__ns.SetLocationSharing(true); __ns.UpdateGuildLocation(); __advance(2)')
check('explicit opt-in sends one compact position',A.ev('#__positions')==1 and len(A.ev('__positions[1]'))<=250)
A.ex('__ns.UpdateGuildLocation(); __advance(30); __ns.UpdateGuildLocation()')
check('stationary client does not broadcast every timer tick',A.ev('#__positions')==1)
A.ex('__advance(35); __ns.UpdateGuildLocation()')
check('stationary heartbeat reaches new listeners',A.ev('#__positions')==2)
A.ex('__x=0.7; __advance(30); __ns.UpdateGuildLocation(); __advance(2)')
check('movement broadcasts after the minimum interval',A.ev('#__positions')==3)
A.ex('__instance=true; __fire("PLAYER_ENTERING_WORLD"); __advance(2)')
check('instance entry withdraws the outdoor position', 'off' in A.ev('__positions[4]'))
A.ex('__advance(80)')
check('no coordinates broadcast inside instances',A.ev('#__positions')==4)
A.ex('__instance=false; __ns.SetLocationSharing(false); __advance(2); __positions={}; __advance(120)')
check('opt-out stops all future position heartbeats',A.ev('#__positions')==0)
A.ex('__receive({map=42,x=0.3,y=0.4})')
check('guild member position creates world and minimap pins',A.ev('__count(__world)')==1 and A.ev('__count(__mini)')==1)
check('pins use parent/world conversion and do not float at minimap edges',A.ev('(function() for _,p in pairs(__world) do return p[4] end end)()')==3 and A.ev('(function() for _,p in pairs(__mini) do return p[4]==true and p[5]==false end end)()'))
A.ex('''__receive({map=42,x=0.9,y=0.9},'WHISPER'); __receive({map=42,x=0.9,y=0.9},'GUILD','Stranger')
__receive({map=42,x=0.9,y=0.9})''')
check('unknown members, whispers and rapid repeats cannot move a marker',A.ev('__ns.guildLocations["Tyler Baker"].x')==0.3)
A.ex('''__advance(5); __receive({map=42,x=0/0,y=0.5}); __receive({map=42,x=2,y=0.5});
__receive({map=999,x=0.5,y=0.5}); __receive({map=42,x='0.2',y=0.5})''')
check('malformed coordinates and unknown maps rejected',A.ev('__ns.guildLocations["Tyler Baker"].x')==0.3)
A.ex('__receive({map=42,x=0.6,y=0.4,who="Chris Stone"})')
check('payload cannot impersonate another guild member',A.ev('__ns.guildLocations["Chris Stone"]') is None and A.ev('__ns.guildLocations["Tyler Baker"].x')==0.6)
A.ex('__ns.db.settings.guildWorldMap=false; __ns.RefreshGuildMap()')
check('world map can be hidden without hiding minimap',A.ev('__count(__world)')==0 and A.ev('__count(__mini)')==1)
A.ex('__ns.db.settings.guildMinimap=false; __ns.RefreshGuildMap(); __ns.db.settings.guildWorldMap=true; __ns.RefreshGuildMap()')
check('pooled markers re-register when display is enabled again',A.ev('__count(__world)')==1 and A.ev('__count(__mini)')==0)
A.ex('__receive({off=true})')
check('withdrawal immediately removes markers',A.ev('__count(__world)')==0 and A.ev('__count(__ns.guildLocations)')==0)
A.ex('__receive({map=42,x=0.3,y=0.4}); __ns.roster["Tyler Baker"].online=false; __ns.RefreshGuildMap()')
check('offline members are removed',A.ev('__count(__ns.guildLocations)')==0)
A.ex('__ns.roster["Tyler Baker"].online=true; __receive({map=42,x=0.3,y=0.4}); __advance(121); __ns.RefreshGuildMap()')
check('stale markers expire without a roster update',A.ev('__count(__ns.guildLocations)')==0)
A.ex('''__receive({map=42,x=0.3,y=0.4}); __saved=__ns.Serialize(EPUGuildDB)''')
check('locations are not stored in SavedVariables', 'guildLocations' not in A.ev('__saved') and 'Elwynn' not in A.ev('__saved'))
A.ex('''__ns.SetLocationSharing(true); __positions={}; local old=__ns.NetworkStatus
__ns.NetworkStatus=function() return {queued=10,pause=0} end
__ns.UpdateGuildLocation(); __ns.NetworkStatus=old''')
check('sync backlog takes priority over locations',A.ev('#__positions')==0)
A.ex('''local old=C_Map.GetPlayerMapPosition; C_Map.GetPlayerMapPosition=function() error('restricted') end
__ns.UpdateGuildLocation(); C_Map.GetPlayerMapPosition=old''')
check('restricted coordinates do not raise or send',A.ev('#__positions')==0)
A.ex('''__ns.SetLocationSharing(false); __advance(3); __positions={}
__refuse=true; local old=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(...) if __refuse then return false end return old(...) end
__ns.SendEphemeral('L',{map=42,x=0.1,y=0.1},15,function() return true end)
__advance(20); __refuse=false; __advance(60)''')
check('queued position expires during throttling instead of arriving late',A.ev('#__positions')==0)
A.ex('''__ns.SendEphemeral('L',{map=42,x=0.1,y=0.1},15,function() return false end); __advance(3)''')
check('send-time consent guard discards revoked positions',A.ev('#__positions')==0)
A.ex('''LibStub=nil; __ns.RefreshGuildMap(); SlashCmdList.EPUGUILD('map')''')
check('missing map library degrades to a usable settings panel',A.ev('EPUGuildMapSettings:IsShown()'))
A.ex('''local old=__ns.GuildKey; __ns.GuildKey=function() return 'another guild' end
__fire('PLAYER_GUILD_UPDATE','player'); __ns.GuildKey=old''')
check('guild changes clear session locations',A.ev('__count(__ns.guildLocations)')==0)

# The simulator deliberately has no map canvas. Compile all packaged library
# scripts and verify that the XML loader refers to shipped files.
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path(ADDON)/'Libs'
for script in ET.parse(root/'Libraries.xml').getroot():
    path=root/script.attrib['file']
    A.rt.globals()['__libraryPath']=str(path).replace('\\','/')
    A.ex('assert(loadfile(__libraryPath))')
check('all bundled mapping scripts compile and XML paths resolve',True)
B=Client('Chris Baker')
B.ex((Path(HERE)/'map_canvas.lua').read_text())
for script in ET.parse(root/'Libraries.xml').getroot():
    B.rt.globals()['__libraryPath']=str(root/script.attrib['file']).replace('\\','/')
    B.ex('assert(loadfile(__libraryPath))()')
B.ex("""__fire('PLAYER_ENTERING_WORLD',true,false)
__ns.comm.L('Tyler Baker',{map=42,x=0.41,y=0.5},'GUILD')
__hbd=LibStub('HereBeDragons-Pins-2.0')
__hbd.updateFrame:GetScript('OnUpdate')(__hbd.updateFrame,2)
""")
check('shipped library renders a real registered world pin',B.ev('next(WorldMapFrame.pins)~=nil'))
check('shipped library renders a nearby minimap pin',B.ev('(function() for f in pairs(__hbd.minimapPins) do return f:IsShown() end end)()'))
B.ex("__viewMap=13; WorldMapFrame.provider:RefreshAllData()")
check('shipped library projects markers onto parent continent',B.ev('next(WorldMapFrame.pins)~=nil'))
B.ex("__viewMap=947; WorldMapFrame.provider:RefreshAllData()")
check('shipped library projects markers onto Azeroth map',B.ev('next(WorldMapFrame.pins)~=nil'))
B.ex("""__rotate=true; __facing=1.2; __zoom=4; __fire('CVAR_UPDATE','rotateMinimap','1')
__fire('MINIMAP_UPDATE_ZOOM'); __hbd.updateFrame:GetScript('OnUpdate')(__hbd.updateFrame,2)""")
check('shipped library handles rotated and zoomed minimap',B.ev('(function() for f in pairs(__hbd.minimapPins) do return f:IsShown() end end)()'))
B.ex("""__advance(6); __ns.comm.L('Tyler Baker',{map=42,x=0.9,y=0.9},'GUILD')
__hbd.updateFrame:GetScript('OnUpdate')(__hbd.updateFrame,2)""")
check('distant minimap marker is hidden instead of stuck on the edge',B.ev('(function() for f in pairs(__hbd.minimapPins) do return not f:IsShown() end end)()'))
print('Guild map tests:',check.failed,'failed')
sys.exit(1 if check.failed else 0)

"""Public event cards and actual helper-mediated Discord RSVP round trip."""
from simcore import *
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'epu-discord'))
import tempfile,asyncio,types,json,shutil
import epu_core as core,shared_bridge as bridge,event_sync
check('timezone picker finds familiar names and cities',
      event_sync.time_zone_choices('eastern')[0].value=='America/New_York'
      and any(choice.value=='America/Indiana/Indianapolis' for choice in event_sync.time_zone_choices('indianapolis')))
for month, offset in [('01','-05:00'),('07','-04:00')]:
    wall=f'2026-{month}-15 19:00'
    check('Eastern date selects the offset in effect for '+wall,
          event_sync.event_start(wall,'America/New_York')==event_sync.event_start(wall+' '+offset))
for wall, expected in [('2026-03-08 02:30','skipped'),('2026-11-01 01:30','twice')]:
    try:
        event_sync.event_start(wall,'America/New_York')
    except ValueError as error:
        check('picker detects '+expected+' local time',expected in str(error))
    else:
        check('picker detects '+expected+' local time',False)
A=Client('Chris Baker');B=Client('Tyler Baker');P=Client('Pip Baker')
clients.update({c.name:c for c in (A,B,P)});tick(120)
now=int(A.ev('__now'));event_sync.time.time=lambda:now
A.ex("__ns.SetSyncHelper('Tyler Baker',true)");tick(30)
event=A.ev("__ns.SaveGuildEvent({kind='fishing',title='Learn fishing',zone='Stormwind',note='Beginners welcome',starts=__now+3600,minutes=60,slots=10})")
for c in (A,B,P):c.rt.globals()['event']=event
tick(30)
root=Path(tempfile.mkdtemp());state=core.State(str(root/'state.json'))
sv=root/'EPUGuild.lua'
def snapshot():
    B.ex('__dumpSV("'+str(sv).replace('\\','/')+'")')
    return core.load_guild_data(str(sv),'E Pluribus Unum')
gd=snapshot()
class Message:
    id=101
    def __init__(self):self.edits=[]
    async def edit(self,**kw):self.edits.append(kw)
class Channel:
    guild=types.SimpleNamespace(id=1)
    def __init__(self):self.sent=[];self.message=Message()
    async def send(self,**kw):self.sent.append(kw);return self.message
    async def fetch_message(self,id):return self.message
channel=Channel();cfg={'server_id':'1','events_channel_id':'2','guild_key':'E Pluribus Unum'}
sync=event_sync.EventSync(cfg,state,types.SimpleNamespace(get_channel=lambda id:channel),lambda:gd,lambda:None)
asyncio.run(sync.refresh(gd));asyncio.run(sync.refresh(gd))
check('event posts once and retains signup buttons',len(channel.sent)==1 and len(channel.sent[0]['view'].children)==4)
check('card contains event time and current signup names','<t:' in channel.sent[0]['embed'].fields[0].value and 'Chris Baker' in str(channel.sent[0]['embed'].to_dict()))
class Response:
    def __init__(self):self.messages=[]
    async def send_message(self,text,**kw):self.messages.append(text)
response=Response();interaction=types.SimpleNamespace(data={'custom_id':'epuevent:going:'+event_sync.token(event)},guild_id=1,channel_id=2,user=types.SimpleNamespace(id=42),response=response)
asyncio.run(sync.handle(interaction))
check('unverified Discord account cannot claim a signup',not state.data['inbox'] and 'verify' in response.messages[-1])
# Existing verification API, not a self-asserted character name.
state.data['links']['42']=['Pip Baker']
interaction.data={'custom_id':'epuevent:role:'+event_sync.token(event),'values':['m']};asyncio.run(sync.handle(interaction))
interaction.data={'custom_id':'epuevent:going:'+event_sync.token(event)};asyncio.run(sync.handle(interaction));asyncio.run(sync.handle(interaction))
check('repeated signup leaves one pending action',len(state.data['inbox'])==1 and state.data['inbox'][0]['role']=='m')
entry=state.data['inbox'][0]
check('card clearly separates pending from confirmed','Awaiting game sync' in str(event_sync.card(gd,state,event,gd.g['guildEvents'][event]).to_dict()) and len(event_sync.responses(gd,event))==1)
wow=root/'wow';addon=wow/'Interface'/'AddOns'/'EPUGuild';addon.mkdir(parents=True)
(addon/'EPUGuild.toc').write_text('InviteRequests.lua\nEventBridge.lua\n')
target=wow/'WTF'/'Account'/'ACCOUNT'/'SavedVariables'/'EPUGuild.lua';target.parent.mkdir(parents=True);shutil.copy(sv,target)
folder=root/'cloud';secret='s'*48
cfg['sync_helpers']={'helper':{'enabled':True,'secret':secret,'characters':['Tyler Baker'],'folders':[str(folder)]}}
hc={'helper':'helper','guild':cfg['guild_key'],'secret':secret,'characters':['Tyler Baker'],'folder':str(folder),'wow_path':str(wow)}
bridge.publish(cfg,state)
feed=bridge.verify(folder/'to-game.json','helper',cfg['guild_key'],'feed',secret)
check('old helpers do not receive unsupported event actions',feed['payload']['entries']==[])
local={};bridge.helper_cycle(hc,local);bridge.publish(cfg,state);bridge.helper_cycle(hc,local)
B.ex((addon/'Inbox.lua').read_text());B.ex('__ns.ProcessInbox()')
check('whitelisted helper imports verified member RSVP',B.ev("__ns.CasualStore().eventResponses[event..'\\030Pip Baker'].state")=='going')
check('delegated response reaches organiser without granting officer rank',tick_until(lambda:A.ev("(__ns.CasualStore().eventResponses[event..'\\030Pip Baker'] or {}).role")=='m',60) and not B.ev('__ns.IsTrusted(__ns.me)'))
B.ex('__dumpSV("'+str(target).replace('\\','/')+'")');bridge.helper_cycle(hc,local)
merged,_=bridge.merge_public(gd,cfg);bridge.reconcile_helper_acks(cfg,state)
check('confirmed game response returns to Discord and clears pending',not state.data['inbox'] and len(event_sync.responses(merged,event))==2)
asyncio.run(sync.refresh(merged));check('existing Discord card is updated with signups',len(channel.sent)==1 and len(channel.message.edits)==1)
P.rt.globals()['entry']=P.rt.table_from(entry)
check('ordinary member cannot import delegated bridge action',not P.ev('__ns.ImportEventResponse(entry)'))
# A more recent in-game choice wins over an old queued Discord response.
A.rt.globals()['entry']=A.rt.table_from(entry)
A.ex("__ns.CasualStore().eventResponses[event..'\\030Pip Baker'].state='declined';__ns.CasualStore().eventResponses[event..'\\030Pip Baker'].t=__now+10;entry.revision=entry.revision+1;__ns.ImportEventResponse(entry)")
check('late cloud data does not overwrite a newer game response',A.ev("__ns.CasualStore().eventResponses[event..'\\030Pip Baker'].state")=='declined')
merged.g['guildEvents'][event]['status']='cancelled';asyncio.run(sync.refresh(merged))
check('cancellation updates the same card and disables signup controls',len(channel.sent)==1 and all(c.disabled for c in channel.message.edits[-1]['view'].children))
gd=merged;asyncio.run(sync.handle(interaction));check('cancelled event rejects new signups',not state.data['inbox'])

# Discord creation through the real shared-folder path.
interaction.id=123456
start=event_sync.datetime.fromtimestamp(now+7200, event_sync.datetime.fromisoformat('2000-01-01T00:00:00-05:00').tzinfo)
start=start.strftime('%Y-%m-%d %H:%M -05:00')
def create(**kwargs):
    asyncio.run(sync.create(interaction,'Discord fishing night',kwargs.pop('start',start),**kwargs))
interaction.channel_id=99
create()
check('event creation is limited to #events',not state.data['inbox'] and '#events' in response.messages[-1])
interaction.channel_id=2
interaction.user.id=43
create()
check('event creation requires a verified guild member',not state.data['inbox'] and 'verify' in response.messages[-1])
interaction.user.id=42
create(organiser='Chris Baker')
check('Discord users cannot create events as someone else',not state.data['inbox'])
create(start='2027-01-15 08:00 -05:80')
check('invalid UTC offsets are rejected',not state.data['inbox'] and 'Enter a start' in response.messages[-1])
create(start=start.rsplit(' ',1)[0], time_zone='America/New_York', activity='fishing', meet_at='Stormwind',
       details='Bring a fishing pole', minutes=45, players=8)
create()
check('retry of the same command queues one event',len(state.data['inbox'])==1)
creation=state.data['inbox'][0]
key=event_sync.event_id(creation)
check('start offset converts to the correct instant',abs(creation['starts']-(now+7200))<60)
for c in (A,B,P):
    c.rt.globals()['creation']=c.rt.table_from(creation)
    c.rt.globals()['createdEvent']=key
check('an ordinary member cannot import delegated creation',not P.ev('__ns.ImportEventCreate(creation)'))
bridge.publish(cfg,state)
check('helpers with older addons are not sent creation entries',bridge.verify(folder/'to-game.json','helper',cfg['guild_key'],'feed',secret)['payload']['entries']==[])
(addon/'EPUGuild.toc').write_text('InviteRequests.lua\nEventBridge.lua\nEventCreateBridge.lua\n')
bridge.helper_cycle(hc,local);bridge.publish(cfg,state);bridge.helper_cycle(hc,local)
B.ex((addon/'Inbox.lua').read_text());B.ex('__ns.ProcessInbox()')
check('updated helper imports an event owned by the verified organiser',B.ev('__ns.CasualStore().guildEvents[createdEvent].who')=='Pip Baker')
check('delegated creation reaches the organiser',tick_until(lambda:P.ev('(__ns.CasualStore().guildEvents[createdEvent] or {}).title')=='Discord fishing night',60))
P.ex("""__ns.UI:Show(); __ns.UI:SetView('activities'); __ns.UI:OpenDetails('eventcalendar',createdEvent)
function __canPrepare() for _, b in ipairs(__ns.UI.details.pools.btn) do
  if b:IsShown() and b.text:GetText()=='Prepare WoW draft' then return true end
end end""")
check('organiser can prepare a WoW calendar draft for a Discord event',P.ev('__canPrepare()'))
check('helper cannot publish the organiser’s native draft',not B.ev('__ns.PrepareWoWCalendar(createdEvent)'))
P.ex("__ns.SaveGuildEvent({title='Edited in WoW',starts=creation.starts,minutes=45,slots=8,kind='fishing'},createdEvent)")
check('only the organiser’s edit takes effect on the event',tick_until(lambda:B.ev('__ns.CasualStore().guildEvents[createdEvent].title')=='Edited in WoW',60))
check('a repeated import leaves the newer organiser edit in place',B.ev("__ns.ImportEventCreate(creation) and __ns.CasualStore().guildEvents[createdEvent].title=='Edited in WoW'"))
B.ex("__forged={}; for k,v in pairs(__ns.CasualStore().guildEvents[createdEvent]) do __forged[k]=v end; __forged.title='Forged'; __forged.t=__now+10")
A.rt.globals()['forged']=A.rt.table_from(dict(B.ev('__forged').items()))
check('helper cannot use delegated creation to edit an existing event',not A.ev("__ns.MergeCommunity('Tyler Baker',{guildEvents={[createdEvent]=forged}},false)"))
B.ex('__dumpSV("'+str(target).replace('\\','/')+'")');bridge.helper_cycle(hc,local)
merged,_=bridge.merge_public(gd,cfg);bridge.reconcile_helper_acks(cfg,state)
check('helper receipt clears the queued creation once the event is saved',not state.data['inbox'] and merged.g['guildEvents'][key]['who']=='Pip Baker')
asyncio.run(sync.refresh(merged));asyncio.run(sync.refresh(merged))
check('imported event gets a single Discord signup card',len(channel.sent)==2 and channel.sent[-1]['embed'].title=='Edited in WoW')
check('no addon runtime errors',sum(c.ev('__errors') or 0 for c in (A,B,P))==0)
print('Event sync:',check.failed,'failed');sys.exit(bool(check.failed))

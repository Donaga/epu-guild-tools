"""Public event cards and actual helper-mediated Discord RSVP round trip."""
from simcore import *
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'epu-discord'))
import tempfile,asyncio,types,json,shutil
import epu_core as core,shared_bridge as bridge,event_sync
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
check('no addon runtime errors',sum(c.ev('__errors') or 0 for c in (A,B,P))==0)
print('Event sync:',check.failed,'failed');sys.exit(bool(check.failed))

"""Two PCs and two cloud folder locations, using actual Lua inbox imports."""
from simcore import *
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'epu-discord'))
import tempfile,shutil,json
import epu_core as core
import shared_bridge as bridge
A=Client('Chris Baker'); B=Client('Tyler Baker'); clients.update({c.name:c for c in (A,B)});tick(120)
now=int(A.ev('__now'));bridge.time.time=lambda:now
A.ex("__ns.SetSyncHelper('Tyler Baker',true)")
check('member helper receives scoped whitelist',tick_until(lambda:B.ev("__ns.IsSyncHelper('Tyler Baker')"),60))
root=Path(tempfile.mkdtemp());od=root/'owner-onedrive';gdroot=root/'owner-googledrive';remote=root/'helper-google';remote.mkdir()
wow=root/'wow';addon=wow/'Interface'/'AddOns'/'EPUGuild';addon.mkdir(parents=True)
(addon/'EPUGuild.toc').write_text('InviteRequests.lua\n')
sv=wow/'WTF'/'Account'/'ACCOUNT'/'SavedVariables'/'EPUGuild.lua';sv.parent.mkdir(parents=True)
secret='s'*48
cfg={'guild_key':'E Pluribus Unum','sync_helpers':{'helper1':{'enabled':True,'secret':secret,'characters':['Tyler Baker'],'folders':[str(od),str(gdroot)]}}}
helper={'helper':'helper1','guild':'E Pluribus Unum','secret':secret,'characters':['Tyler Baker'],'folder':str(remote),'wow_path':str(wow)}
state=core.State(str(root/'state.json'));state.queue_guild_invite('m100','Fresh Applicant','Applicant','42',now)
bank=state.queue_request('Pip Baker',2589,'Linen Cloth',3,'Thanks','Pip')
state.queue_status('protected','approved','Officer')
bridge.publish(cfg,state)
check('both provider folders receive identical signed feeds',(od/'to-game.json').read_bytes()==(gdroot/'to-game.json').read_bytes())
packet=bridge.verify(gdroot/'to-game.json','helper1',cfg['guild_key'],'feed',secret)
check('helper feed excludes officer approval actions',{e['kind'] for e in packet['payload']['entries']}=={'guild_invite','request'})
shutil.copy(gdroot/'to-game.json',remote/'to-game.json')
local={};status=bridge.helper_cycle(helper,local)
check('helper stages incoming actions without a Discord token','ready' in status and 'token' not in helper)
B.ex("__ns.G().bank.Bank={v=__now,money=0,items={[2589]=20},seen={[2589]=true}}; CanGuildInvite=function() return true end")
A.ex("__ns.G().bank.Bank={v=__now,money=0,items={[2589]=20},seen={[2589]=true}}")
B.ex((addon/'Inbox.lua').read_text());B.ex('__ns.ProcessInbox()')
check('member imports the named invite request',B.ev('__ns.CasualStore().inviteRequests.m100.who')=='Fresh Applicant')
B.rt.globals()['bankId']='d-'+bank['id']
check('bank relay creates a pending request without granting approval',B.ev('__ns.G().requests[bankId].status')=='pending' and not B.ev('__ns.IsTrusted(__ns.me)'))
A.rt.globals()['bankId']='d-'+bank['id']
check('pending bank request syncs to officer through helper whitelist',tick_until(lambda:A.ev('__ns.G().requests[bankId]~=nil'),60))
B.ex("local r={} for k,v in pairs(__ns.G().requests[bankId]) do r[k]=v end; r.status='approved'; r.u=__now+1; __ns.Send('D',{req={[bankId]=r}})");tick(10)
check('helper cannot turn a pending request into an approval',A.ev('__ns.G().requests[bankId].status')=='pending')
B.ex("__ns.G().notes={secret={text='PRIVATE OFFICER NOTE'}}; __ns.db.secretPreference='PRIVATE PREF'; __ns.G().mats['item:1']={t=__now,r={1,2,3,4,5,6,7,8,9,10,11,12}}")
B.ex('__dumpSV("'+str(sv).replace('\\','/')+'")')
status=bridge.helper_cycle(helper,local)
check('snapshot export reports pending bot receipt','waiting for cloud transfer' in status)
uploaded=(remote/'to-bot.json').read_text()
check('snapshot excludes private notes, preferences and unrelated data','PRIVATE OFFICER NOTE' not in uploaded and 'PRIVATE PREF' not in uploaded and 'inboxDone' not in uploaded)
shutil.copy(remote/'to-bot.json',gdroot/'to-bot.json')
base=core.GuildData({'guilds':{'E Pluribus Unum - Forever':{'bank':{},'requests':{},'needs':{'v':0,'list':{}}}}},'E Pluribus Unum')
merged,fingerprint=bridge.merge_public(base,cfg)
check('helper sends game requests back to central Discord view',merged.requests['d-'+bank['id']]['status']=='pending')
check('numeric item keys and long reagent arrays survive JSON',merged.bank['Bank']['items'][2589]==20 and merged.mats_for('item:1')==[(1,2),(3,4),(5,6),(7,8),(9,10),(11,12)])
bridge.reconcile_helper_acks(cfg,state)
check('verified game receipts clear only imported helper actions',[e['kind'] for e in state.data['inbox']]==['status'])
bridge.publish(cfg,state);shutil.copy(gdroot/'to-game.json',remote/'to-game.json')
check('bot receipt is shown after return transfer','Bot received' in bridge.helper_cycle(helper,local))
A.ex("__ns.SetRequestStatus(bankId,'approved')")
check('actual officer approval reaches helper',tick_until(lambda:B.ev('__ns.G().requests[bankId].status')=='approved',60))
B.ex('__dumpSV("'+str(sv).replace('\\','/')+'")');bridge.helper_cycle(helper,local)
shutil.copy(remote/'to-bot.json',gdroot/'to-bot.json');approved,_=bridge.merge_public(base,cfg)
check('helper exports officer status back to Discord without approval rights',approved.requests['d-'+bank['id']]['status']=='approved' and not B.ev('__ns.IsTrusted(__ns.me)'))
base.g['requests']['d-'+bank['id']]={**approved.requests['d-'+bank['id']],'status':'filled','u':approved.requests['d-'+bank['id']]['u']+1}
newer,_=bridge.merge_public(base,cfg)
check('older helper snapshot cannot roll back newer officer action',newer.requests['d-'+bank['id']]['status']=='filled')
before=(addon/'Inbox.lua').read_bytes();raw=json.loads((remote/'to-game.json').read_text());raw['payload']['entries']=[{'kind':'status','id':'forged'}];bridge.atomic(remote/'to-game.json',raw)
try:bridge.helper_cycle(helper,local);tamper=False
except ValueError:tamper=True
check('modified cloud files cannot stage actions',tamper and before==(addon/'Inbox.lua').read_bytes())
old=bridge.envelope('helper1',cfg['guild_key'],'feed',{'enabled':True,'entries':[]},secret,sequence=1);bridge.atomic(remote/'to-game.json',old)
try:bridge.helper_cycle(helper,local);replay=False
except ValueError:replay=True
check('older conflicting cloud copy cannot roll back queue',replay)
cfg['sync_helpers']['helper1']['enabled']=False;bridge.publish(cfg,state);shutil.copy(gdroot/'to-game.json',remote/'to-game.json')
check('connection can be individually disabled','disabled' in bridge.helper_cycle(helper,local))
check('disabled connection cannot supplement central snapshots',bridge.read_helper_uploads(cfg)==[])
check('helper raised no game runtime errors',(B.ev('__errors') or 0)==0)
print('Shared bridge:',check.failed,'failed');sys.exit(bool(check.failed))

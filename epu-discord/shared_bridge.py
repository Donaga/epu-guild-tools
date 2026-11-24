"""Provider-neutral shared-folder bridge. Never transfers executable Lua or bot credentials."""
from __future__ import annotations
import copy,hashlib,hmac,json,math,os,time
from pathlib import Path
import epu_core as core

MAX_BYTES=8*1024*1024
EVENT_MODULES={'event_response':'EventBridge.lua','event_create':'EventCreateBridge.lua'}
# Officer actions from Discord (approvals, announcements, onboarding steps,
# helper whitelist). Only a helper the organiser marks "officer": true in the
# bot config is sent these, and the addon applies them only on an officer's
# character, so any officer's PC running the helper can carry Discord while
# the organiser is away. Every action has a fixed id, so several officers
# carrying the same one change the same record once.
OFFICER_KINDS={'status','news','news_remove','checklist','sync_helper'}
KINDS={'guild_invite','request'} | set(EVENT_MODULES) | OFFICER_KINDS
FIELDS={'needs','bank','requests','donations','crafters','recipes','mats','members','memberInfo','inviteRequests','inviteOutcomes','guildEvents','eventResponses','activityPosts','activityReplies','runRequests','runInterest'}
# Announcements, milestones and the guild MOTD, which the bot posts as the
# guild's own: exported only by officer helpers and taken only from them.
OFFICER_FIELDS={'news','feed','motd'}
OFFICER_CAPABILITY='officer'
WIRE={'requests':'req','donations':'don','crafters':'craft'}
def safe(value,depth=0):
    if depth>24: raise ValueError('Bridge data is too deeply nested')
    if isinstance(value,dict): return {str(k):safe(v,depth+1) for k,v in value.items()}
    if isinstance(value,(list,tuple)): return [safe(v,depth+1) for v in value]
    if value is None or isinstance(value,(str,bool,int)): return value
    if isinstance(value,float) and math.isfinite(value): return value
    raise ValueError('Invalid bridge value')
def canonical(value):return json.dumps(safe(value),ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode('utf-8')
def atomic(path,value):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    data=canonical(value)
    if len(data)>MAX_BYTES:raise ValueError('Bridge packet is too large')
    tmp=path.with_name(path.name+'.tmp'); tmp.write_bytes(data); os.replace(tmp,path)
def envelope(helper,guild,direction,payload,secret,sequence=None):
    body={'schema':1,'helper':helper,'guild':guild,'direction':direction,'issued':int(time.time()),'sequence':sequence or time.time_ns()//1000000,'payload':safe(payload)}
    body['mac']=hmac.new(secret.encode(),canonical(body),hashlib.sha256).hexdigest(); return body
def verify(path,helper,guild,direction,secret,minimum=0):
    path=Path(path)
    if path.stat().st_size>MAX_BYTES:raise ValueError('Bridge packet is too large')
    packet=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(packet,dict):raise ValueError('Invalid bridge packet')
    mac=packet.pop('mac',None)
    if not isinstance(mac,str) or not hmac.compare_digest(mac,hmac.new(secret.encode(),canonical(packet),hashlib.sha256).hexdigest()):raise ValueError('Bridge signature does not match')
    if packet.get('schema')!=1 or packet.get('helper')!=helper or packet.get('guild')!=guild or packet.get('direction')!=direction:raise ValueError('Wrong bridge account, guild or direction')
    issued=packet.get('issued'); seq=packet.get('sequence')
    if type(issued) is not int or issued>time.time()+300 or time.time()-issued>86400:raise ValueError('Shared sync data is stale; wait for the central bot')
    if type(seq) is not int or seq<minimum:raise ValueError('An older cloud copy was ignored')
    return packet
def public_snapshot(gd,character,officer=False):
    g={}
    unconf=gd.g.get('unconf') or {}
    for field in FIELDS|(OFFICER_FIELDS if officer else set()):
        value=copy.deepcopy(gd.g.get(field) or {})
        wire=WIRE.get(field,field); blocked=unconf.get(wire) or {}
        if field=='needs':
            if blocked:continue
        elif field=='motd':
            if not isinstance(value,dict) or not isinstance(value.get('text'),str):continue
        elif isinstance(value,dict):
            value={k:v for k,v in value.items() if not blocked.get(k) and not blocked.get(str(k))}
        if field=='mats':
            for record in value.values():
                if isinstance(record,dict) and isinstance(record.get('r'),dict):record['r']=[v for _,v in sorted(record['r'].items(),key=lambda kv:int(kv[0]))]
        g[field]=value
    return safe({'character':character,'guild_key':gd.key,'saved':gd.db.get('syncHelperExported',0),'game':g,'itemNames':gd.db.get('itemNames') or {},'itemClass':gd.db.get('itemClass') or {}})
def restore_keys(snapshot):
    """JSON object keys are strings; the existing guild reader expects item IDs as ints."""
    s=copy.deepcopy(snapshot)
    def numeric(m):return {int(k) if str(k).isdigit() else k:v for k,v in (m or {}).items()}
    s['itemNames']=numeric(s.get('itemNames'));s['itemClass']=numeric(s.get('itemClass'))
    g=s.get('game') or {}; g['needs']=g.get('needs') or {}
    g['needs']['list']=numeric(g['needs'].get('list'))
    for bank in (g.get('bank') or {}).values():
        if isinstance(bank,dict):
            bank['items']=numeric(bank.get('items'));bank['seen']=numeric(bank.get('seen'))
    return s
def guild_matches(key,wanted):return key==wanted or (isinstance(key,str) and key.startswith(wanted+' - '))
def read_helper_uploads(cfg):
    out=[]
    for helper,entry in cfg.get('sync_helpers',{}).items():
        if not entry.get('enabled',True):continue
        newest=None
        for folder in entry.get('folders',[]):
            try:
                packet=verify(Path(folder)/'to-bot.json',helper,cfg['guild_key'],'upload',entry['secret'])
                payload=packet['payload']; snapshot=payload['snapshot']
                if not isinstance(snapshot,dict) or not isinstance(snapshot.get('game'),dict):continue
                if not isinstance(snapshot.get('itemNames'),dict) or not isinstance(snapshot.get('itemClass'),dict):continue
                if snapshot.get('character') not in entry.get('characters',[]) or not guild_matches(snapshot.get('guild_key'),cfg['guild_key']):continue
                if newest is None or packet['sequence']>newest['sequence']:newest=packet
            except (OSError,ValueError,KeyError,TypeError):continue
        if newest:out.append((helper,newest))
    return out
def _stamp_ok(value):return isinstance(value,(int,float)) and not isinstance(value,bool) and 0<=value<=time.time()+300
def merge_officer_fields(g,src):
    """Announcements, milestones and the MOTD from an officer's helper; newer wins."""
    news=src.get('news')
    if isinstance(news,dict):
        target=g.setdefault('news',{})
        for key,r in news.items():
            if not isinstance(r,dict) or not isinstance(r.get('title',''),str) or not isinstance(r.get('text',''),str):continue
            rev=r.get('u',r.get('t',0)); old=target.get(key) or {}
            if _stamp_ok(rev) and rev>float(old.get('u',old.get('t',0)) or 0):target[key]=r
    feed=src.get('feed')
    if isinstance(feed,dict):
        target=g.setdefault('feed',{})
        for key,r in feed.items():
            if isinstance(r,dict) and isinstance(r.get('text'),str) and _stamp_ok(r.get('t')) and key not in target:target[key]=r
    motd=src.get('motd')
    if isinstance(motd,dict) and isinstance(motd.get('text'),str) and _stamp_ok(motd.get('t')):
        old=g.get('motd') or {}
        if motd['t']>float(old.get('t') or 0):g['motd']=motd
def merge_public(base,cfg):
    uploads=read_helper_uploads(cfg)
    if not base:return base,''
    db=copy.deepcopy(base.db); gd=core.GuildData(db,base.key); g=gd.g
    for helper,packet in uploads:
        s=restore_keys(packet['payload']['snapshot'])
        if s['guild_key']!=base.key:continue
        saved=s.get('saved',0)
        if type(saved) in (int,float) and saved<=time.time()+300 and saved>max(float(db.get('syncHelperExported') or 0),float(g.get('bridgeRosterAt') or 0)):
            members=(s.get('game') or {}).get('members')
            if isinstance(members,(dict,list)) and members:g['members']=members;g['bridgeRosterAt']=saved
            info=(s.get('game') or {}).get('memberInfo')
            if isinstance(info,dict) and info:g['memberInfo']=info;g['memberInfoAt']=saved
        for field in FIELDS-{'members','memberInfo'}:
            src=(s.get('game') or {}).get(field) or {}
            if not isinstance(src,dict):continue
            if field=='needs':
                if float(src.get('v') or 0)>float((g.get('needs') or {}).get('v') or 0):g[field]=src
                continue
            target=g.setdefault(field,{})
            for key,r in src.items():
                if not isinstance(r,dict):continue
                stamp='v' if field=='bank' else ('u' if field=='requests' else 't')
                rev=r.get(stamp,0); old=target.get(key) or {}
                if isinstance(rev,(int,float)) and 0<=rev<=time.time()+300 and rev>float(old.get(stamp) or 0):target[key]=r
        if (cfg.get('sync_helpers',{}).get(helper) or {}).get('officer'):
            merge_officer_fields(g,(s.get('game') or {}))
        # Only public item metadata is supplemented. Identity/alt proofs,
        # policies, notes, private preferences and inboxDone are never imported.
        db.setdefault('itemNames',{}).update(s.get('itemNames') or {})
        db.setdefault('itemClass',{}).update(s.get('itemClass') or {})
    fingerprint=hashlib.sha256(canonical([(h,p['sequence']) for h,p in uploads])).hexdigest()
    return core.GuildData(db,base.key),fingerprint
def officer_helper(cfg,helper,payload=None):
    """An organiser-marked officer helper whose helper app can carry officer actions."""
    entry=cfg.get('sync_helpers',{}).get(helper) or {}
    if not entry.get('officer') or not entry.get('enabled',True):return False
    return payload is None or OFFICER_CAPABILITY in (payload.get('capabilities') or [])
def reconcile_helper_acks(cfg,state):
    remove=set()
    for helper,packet in read_helper_uploads(cfg):
        payload=packet['payload']; snapshot=payload['snapshot']; g=snapshot.get('game') or {}
        acks=set(payload.get('acked') or [])
        officer=officer_helper(cfg,helper,payload)
        for e in state.data['inbox']:
            if e['id'] not in acks:continue
            if e.get('kind') in OFFICER_KINDS:
                # Applied (or dropped as stale) by an officer's client. Only an
                # officer helper is ever sent these, so its receipt is enough.
                if officer:remove.add(e['id'])
            elif e.get('kind')=='guild_invite':
                r=(g.get('inviteRequests') or {}).get(e.get('source')) or {}
                if r.get('who')==e.get('who') and r.get('revision',0)>=e.get('revision',1) and r.get('cancelled')==e.get('cancelled'):remove.add(e['id'])
            elif e.get('kind')=='request':
                r=(g.get('requests') or {}).get('d-'+e['id']) or {}
                if r.get('who')==e.get('who') and r.get('item')==e.get('item') and r.get('qty')==e.get('qty') and e.get('item'):remove.add(e['id'])
            elif e.get('kind')=='event_response':
                r=(g.get('eventResponses') or {}).get(e.get('event','')+'\x1e'+e.get('who','')) or {}
                if r.get('sourceID')==e['id'] or r.get('t',0)>e.get('t',0):remove.add(e['id'])
            elif e.get('kind')=='event_create':
                key=e['who']+'\x1f'+e['id']
                r=(g.get('guildEvents') or {}).get(key) or {}
                if r.get('who')==e['who'] and r.get('created')==e['t']:remove.add(e['id'])
    if remove:
        state.data['inbox']=[e for e in state.data['inbox'] if e['id'] not in remove];state.save()
def publish(cfg,state):
    uploads=dict(read_helper_uploads(cfg))
    received={h:p['sequence'] for h,p in uploads.items()}
    for helper,entry in cfg.get('sync_helpers',{}).items():
        folders=entry.get('folders') or []
        if not folders:continue
        enabled=entry.get('enabled',True)
        capabilities=(uploads.get(helper,{}).get('payload') or {}).get('capabilities') or []
        kinds={'guild_invite','request'} | (set(EVENT_MODULES) & set(capabilities))
        # Officer actions only go to an officer helper whose app understands
        # them (an older helper app would reject the whole feed).
        officer=bool(enabled and entry.get('officer'))
        if officer and OFFICER_CAPABILITY in capabilities:kinds|=OFFICER_KINDS
        entries=[dict(e,guild=cfg['guild_key']) for e in state.data['inbox'] if e.get('kind') in kinds] if enabled else []
        payload={'enabled':enabled,'characters':entry.get('characters',[]),'entries':entries,'received_sequence':received.get(helper,0),'officer':officer}
        digest=hashlib.sha256(canonical(payload)).hexdigest()
        last=state.data.setdefault('bridge_feeds',{}).get(helper) or {}
        if last.get('digest')==digest and time.time()-last.get('issued',0)<60:continue
        sequence=max(time.time_ns()//1000000,last.get('sequence',0)+1)
        packet=envelope(helper,cfg['guild_key'],'feed',payload,entry['secret'],sequence)
        wrote=False
        for folder in folders:
            try:atomic(Path(folder)/'to-game.json',packet);wrote=True
            except OSError:continue
        if not wrote:continue
        state.data['bridge_feeds'][helper]={'digest':digest,'sequence':sequence,'issued':packet['issued']};state.save()
def helper_cycle(config,local):
    folder=Path(config['folder']); helper=config['helper']; guild=config['guild']; secret=config['secret']
    feed=verify(folder/'to-game.json',helper,guild,'feed',secret,local.get('feed_sequence',0))
    payload=feed['payload']
    if not isinstance(payload,dict):raise ValueError('Invalid helper feed')
    entries=payload.get('entries') or []
    if not isinstance(entries,list) or len(entries)>2000:raise ValueError('Invalid helper queue')
    if any(not isinstance(e,dict) or e.get('kind') not in KINDS or not isinstance(e.get('id'),str) for e in entries):raise ValueError('Unsupported helper action')
    addon=Path(config['wow_path'])/'Interface'/'AddOns'/'EPUGuild'
    toc=addon/'EPUGuild.toc'
    modules=toc.read_text(encoding='utf-8').splitlines() if toc.exists() else []
    if 'InviteRequests.lua' not in modules:raise ValueError('Update EPU Guild Tools before starting the helper')
    capabilities=[kind for kind,module in EVENT_MODULES.items() if module in modules]+[OFFICER_CAPABILITY]
    officer=payload.get('officer') is True
    # The inbox lives in EPUGuild_Inbox, beside the addon, so addon updates
    # can't replace it; anything still in the old EPUGuild\\Inbox.lua moves there.
    if core.addon_reads_inbox_addon(config['wow_path']) and Path(core.inbox_drop_path(config['wow_path'])).exists():
        existing=core.read_inbox_drop(config['wow_path'])
    else:
        existing=core.read_legacy_inbox(config['wow_path'])
    owned=set(local.get('owned_ids') or [])
    other=[e for e in existing if isinstance(e,dict) and e.get('id') not in owned]
    stage=[dict(e,bridge=True,bridgeIssued=feed['issued']) for e in entries
           if (e['kind'] not in EVENT_MODULES or e['kind'] in capabilities) and (officer or e['kind'] not in OFFICER_KINDS)] if payload.get('enabled') else []
    core.write_inbox_files(config['wow_path'],other+stage,seen_at=local.get('drop_seen',0))
    local['owned_ids']=[e['id'] for e in stage];local['feed_sequence']=feed['sequence']
    if not payload.get('enabled'):return 'Helper access disabled by the organiser.'
    paths=core.find_saved_variables(config['wow_path'])
    if config.get('account'):paths=[p for p in paths if Path(p).parts[-3]==config['account']]
    allowed=set(config.get('characters') or []) & set(payload.get('characters') or [])
    for path in paths:
        try:
            gd=core.load_guild_data(path,guild)
            seen=gd.db.get('inboxDropSeen')
            if isinstance(seen,(int,float)) and seen>local.get('drop_seen',0):local['drop_seen']=seen
            character=gd.db.get('syncHelperCharacter')
            if character not in allowed or not guild_matches(gd.key,guild) or gd.db.get('syncHelperGuild')!=gd.key:continue
            signature=hashlib.sha256(Path(path).read_bytes()).hexdigest()
            if signature!=local.get('uploaded') or capabilities!=local.get('capabilities') or officer!=local.get('officer',False) or time.time()-local.get('uploaded_at',0)>300:
                snap=public_snapshot(gd,character,officer)
                acked=[e['id'] for e in entries if e['id'] in gd.inbox_done]
                packet=envelope(helper,guild,'upload',{'snapshot':snap,'acked':acked,'capabilities':capabilities},secret,max(time.time_ns()//1000000,local.get('upload_sequence',0)+1))
                atomic(folder/'to-bot.json',packet)
                local.update(uploaded=signature,uploaded_at=time.time(),upload_sequence=packet['sequence'],capabilities=capabilities,officer=officer)
            receipt='Bot received your game snapshot.' if payload.get('received_sequence',0)>=local.get('upload_sequence',1) else 'Game snapshot exported; waiting for cloud transfer and bot receipt.'
            role=' Carrying officer actions for Discord (they apply on an officer character).' if officer else ''
            return str(len(stage))+' queued update(s) ready. '+receipt+role+' /reload to import incoming updates.'
        except (OSError,ValueError,KeyError,TypeError):continue
    return str(len(stage))+' queued update(s) ready. Log into a whitelisted character, then /reload to export your game snapshot.'

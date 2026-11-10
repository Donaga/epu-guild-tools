"""Public EPU event cards. Discord responses remain pending until game receipt."""
from __future__ import annotations
import hashlib,json,time,uuid
import discord

ROLES={'t':'Tank','h':'Healer','d':'DPS','g':'Helper','c':'Crafter','m':'Mentor'}
KINDS={'dungeon':'Dungeon','leveling':'Leveling','quest':'Quest help','fishing':'Fishing','profession':'Profession','farming':'Farming','other':'Other'}
def token(event):return hashlib.sha256(event.encode()).hexdigest()[:24]
def active(r):return r.get('status')=='scheduled' and r.get('ends',0)>time.time()

def responses(gd,event):
    return sorted((r for r in (gd.g.get('eventResponses') or {}).values()
        if r.get('event')==event and r.get('who') in gd.members),key=lambda r:(r.get('state',''),r.get('who','')))

def pending(state,gd,event):
    result=[]
    for e in state.data['inbox']:
        if e.get('kind')!='event_response' or e.get('event')!=event:continue
        r=(gd.g.get('eventResponses') or {}).get(event+'\x1e'+e['who']) or {}
        if r.get('sourceID')!=e['id'] and r.get('t',0)<=e['t']:result.append(e)
    return result

def view(event,enabled):
    v=discord.ui.View(timeout=None);key=token(event)
    for action,label in [('going','Going'),('tentative','Maybe'),('declined','Can’t make it')]:
        v.add_item(discord.ui.Button(label=label,style=discord.ButtonStyle.primary if action=='going' else discord.ButtonStyle.secondary,
            custom_id=f'epuevent:{action}:{key}',disabled=not enabled))
    v.add_item(discord.ui.Select(placeholder='Choose your role, then select Going or Maybe',
        options=[discord.SelectOption(label=name,value=role) for role,name in ROLES.items()],custom_id=f'epuevent:role:{key}',disabled=not enabled))
    return v

def card(gd,state,event,r):
    status='Cancelled' if r.get('status')=='cancelled' else ('Upcoming' if active(r) else 'Ended')
    embed=discord.Embed(title=(r.get('title') or 'Guild event')[:256],description=(r.get('note') or '')[:500],color=discord.Color.gold() if active(r) else discord.Color.dark_grey())
    embed.add_field(name=KINDS.get(r.get('kind'),'Other')+' · '+status,
        value=f"<t:{int(r['starts'])}:F> (<t:{int(r['starts'])}:R>)\n{int((r['ends']-r['starts'])/60)} minutes · {r.get('slots',5)} planned players",inline=False)
    embed.add_field(name='Meet / levels',value=f"{r.get('zone') or 'Ask the organiser'} · levels {r.get('minLevel',1)}–{r.get('maxLevel',60)}\nOrganiser: {r.get('who','?')}",inline=False)
    rows=responses(gd,event)
    for state_name,label in [('going','Going'),('tentative','Maybe'),('declined','Can’t make it')]:
        members=[f"{r['who']} · {ROLES.get(r.get('role'),'Helper')}" for r in rows if r.get('state')==state_name]
        # Discord's field limit: retain the total and a clearly labelled preview.
        text='\n'.join(members) or 'None yet'
        if len(text)>1000:text=text[:950]+'\n…more signups in EPU'
        embed.add_field(name=f'{label} ({len(members)})',value=text,inline=False)
    waiting=pending(state,gd,event)
    if waiting:
        text='\n'.join(f"{e['who']} · {e['state']} · {ROLES[e['role']]}" for e in waiting)
        embed.add_field(name='Awaiting game sync',value=text[:950]+('…' if len(text)>950 else ''),inline=False)
    embed.set_footer(text='EPU signups • Verified character link required • Sync needs a helper/officer login or /reload. WoW calendar attendees are not included.')
    return embed

class EventSync:
    def __init__(self,cfg,state,client,read,flush):self.cfg,self.state,self.client,self.read,self.flush=cfg,state,client,read,flush

    async def handle(self,interaction):
        data=interaction.data or {};cid=data.get('custom_id','')
        if not cid.startswith('epuevent:'):return False
        async def reply(text):await interaction.response.send_message(text,ephemeral=True,allowed_mentions=discord.AllowedMentions.none())
        if str(interaction.guild_id)!=str(self.cfg['server_id']) or str(interaction.channel_id)!=str(self.cfg.get('events_channel_id')):
            await reply('Use the event card in the guild’s events channel.');return True
        parts=cid.split(':');gd=self.read()
        if len(parts)!=3 or gd is None:await reply('The game snapshot is unavailable. Please try later.');return True
        action,key=parts[1:];event=next((i for i in (gd.g.get('guildEvents') or {}) if token(i)==key),None)
        r=(gd.g.get('guildEvents') or {}).get(event)
        who=self.state.character_for(interaction.user.id)
        if not who or who not in gd.members:await reply('Link a current guild character with /link and have an officer verify it first.');return True
        if not r or not active(r):await reply('This event has ended or was cancelled.');return True
        roles=self.state.data.setdefault('event_roles',{})
        if action=='role':
            values=data.get('values') or []
            if len(values)!=1 or values[0] not in ROLES:await reply('Choose a valid role.');return True
            roles[str(interaction.user.id)]=values[0];self.state.save()
            await reply(f'Role set to {ROLES[values[0]]}. Select Going or Maybe to submit your signup.');return True
        if action not in {'going','tentative','declined'}:await reply('Unknown event action.');return True
        previous=(gd.g.get('eventResponses') or {}).get(event+'\x1e'+who) or {}
        now=int(time.time());role=roles.get(str(interaction.user.id),previous.get('role','g'))
        if role not in ROLES:role='g'
        # One pending action per linked character/event, even across repeated clicks.
        self.state.data['inbox']=[e for e in self.state.data['inbox'] if not (e.get('kind')=='event_response' and e.get('event')==event and e.get('who')==who)]
        self.state.data['inbox'].append({'id':uuid.uuid4().hex[:16],'kind':'event_response','event':event,'who':who,
            'state':action,'role':role,'note':previous.get('note','')[:160],'t':now,'revision':time.time_ns()//1000000,'guild':self.cfg['guild_key']})
        self.state.save();self.flush()
        await reply(f'Saved for {who}: {action} ({ROLES[role]}). Awaiting game sync; the card confirms it after a helper/officer logs in or /reloads.')
        return True

    async def refresh(self,gd):
        channel_id=self.cfg.get('events_channel_id')
        if not channel_id:return
        posts=self.state.data.setdefault('event_posts',{})
        channel=self.client.get_channel(int(channel_id)) or await self.client.fetch_channel(int(channel_id))
        if str(getattr(getattr(channel,'guild',None),'id',''))!=str(self.cfg['server_id']):raise ValueError('Events channel belongs to another server')
        # Superseded/expired pending responses must not linger forever.
        before=len(self.state.data['inbox'])
        for e in list(self.state.data['inbox']):
            if e.get('kind')!='event_response':continue
            r=(gd.g.get('eventResponses') or {}).get(e.get('event','')+'\x1e'+e.get('who','')) or {}
            event=(gd.g.get('guildEvents') or {}).get(e.get('event'))
            if (event and not active(event)) or time.time()-e.get('t',0)>7*86400 or r.get('sourceID')==e['id'] or r.get('t',0)>e.get('t',0):self.state.data['inbox'].remove(e)
        if before!=len(self.state.data['inbox']):self.state.save()
        for event,r in (gd.g.get('guildEvents') or {}).items():
            old=posts.get(event)
            if not old and not active(r):continue
            embed=card(gd,self.state,event,r)
            signature=hashlib.sha256(json.dumps(embed.to_dict(),sort_keys=True).encode()).hexdigest()
            if old and old.get('signature')==signature and str(old.get('channel'))==str(channel_id):continue
            message=None
            if old and str(old.get('channel'))==str(channel_id):
                try:message=await channel.fetch_message(int(old['message']))
                except discord.NotFound:pass
            if message:await message.edit(embed=embed,view=view(event,active(r)),allowed_mentions=discord.AllowedMentions.none())
            elif active(r):message=await channel.send(embed=embed,view=view(event,True),allowed_mentions=discord.AllowedMentions.none())
            if message:
                posts[event]={'message':message.id,'channel':str(channel_id),'signature':signature};self.state.save()

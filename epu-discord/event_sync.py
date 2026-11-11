"""Public EPU event cards. Discord responses remain pending until game receipt."""
from __future__ import annotations
from datetime import datetime
from functools import lru_cache
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones
import hashlib,json,re,time,uuid
import discord

ROLES={'t':'Tank','h':'Healer','d':'DPS','g':'Helper','c':'Crafter','m':'Mentor'}
KINDS={'dungeon':'Dungeon','leveling':'Leveling','quest':'Quest help','fishing':'Fishing','profession':'Profession','farming':'Farming','other':'Other'}
def token(event):return hashlib.sha256(event.encode()).hexdigest()[:24]
def active(r):return r.get('status')=='scheduled' and r.get('ends',0)>time.time()

COMMON_TIME_ZONES = {
    'America/New_York': 'Eastern (US) · New York',
    'America/Chicago': 'Central (US) · Chicago',
    'America/Denver': 'Mountain (US) · Denver',
    'America/Los_Angeles': 'Pacific (US) · Los Angeles',
    'America/Phoenix': 'Arizona · Phoenix',
    'America/Anchorage': 'Alaska · Anchorage',
    'Pacific/Honolulu': 'Hawaii · Honolulu',
    'UTC': 'UTC',
    'Europe/London': 'United Kingdom · London',
    'Europe/Paris': 'Central Europe · Paris',
    'Asia/Kolkata': 'India · Kolkata',
    'Asia/Manila': 'Philippines · Manila',
    'Australia/Sydney': 'Australia · Sydney',
    'Pacific/Auckland': 'New Zealand · Auckland',
}


@lru_cache(maxsize=1)
def known_time_zones():
    return sorted(available_timezones())


def time_zone_choices(query):
    words = query.casefold().replace('_', ' ').split()
    matches = []
    zones = dict(COMMON_TIME_ZONES)
    if words:
        for zone in known_time_zones():
            zones.setdefault(zone, zone.replace('_', ' ').replace('/', ' / '))
    for zone, label in zones.items():
        searchable = (label + ' ' + zone).casefold().replace('_', ' ')
        if all(word in searchable for word in words):
            matches.append(discord.app_commands.Choice(name=label, value=zone))
            if len(matches) == 25:
                break
    return matches


def event_start(value, time_zone=''):
    """Convert an event's wall time using a named zone or an explicit offset."""
    match = re.fullmatch(
        r'(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})(?: (UTC|[+-](?:0\d|1[0-3]):[0-5]\d|[+-]14:00))?',
        value.strip(), re.ASCII,
    )
    if not match:
        raise ValueError('Enter a start like 2026-11-20 19:00 and choose a time zone.')
    day, clock, offset = match.groups()
    try:
        wall = datetime.fromisoformat(day + 'T' + clock)
    except ValueError:
        raise ValueError('Enter a valid date and 24-hour start time.') from None
    if offset:
        if time_zone:
            raise ValueError('Choose a time zone or put a UTC offset in the start field. Use only one.')
        return int(datetime.fromisoformat(wall.isoformat() + ('+00:00' if offset == 'UTC' else offset)).timestamp())
    if not time_zone:
        raise ValueError('Select a time zone, such as Eastern (US) or UTC.')
    try:
        zone = ZoneInfo(time_zone)
    except (ValueError, ZoneInfoNotFoundError):
        raise ValueError('Choose a time zone from the suggestions. Search by city or region.') from None
    candidates = set()
    for fold in (0, 1):
        instant = int(wall.replace(tzinfo=zone, fold=fold).timestamp())
        try:
            matches_wall_time = datetime.fromtimestamp(instant, zone).replace(tzinfo=None) == wall
        except (OverflowError, OSError, ValueError):
            raise ValueError('Choose a start within the next 28 days.') from None
        if matches_wall_time:
            candidates.add(instant)
    if not candidates:
        raise ValueError('That local time is skipped by a clock change. Pick another start time.')
    if len(candidates) > 1:
        raise ValueError('That local time happens twice because the clocks change. Pick another time or enter the UTC offset with the start.')
    return candidates.pop()

def event_text(value, limit, label, required=False):
    value = ' '.join(value.split())
    if (required and not value) or len(value.encode('utf-8')) > limit or re.search(r'[\x00-\x1f\x7f|]', value):
        raise ValueError(f'Use plain text for {label}, up to {limit} bytes.')
    return value

def event_id(entry):
    return entry['who'] + '\x1f' + entry['id']

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

    async def create(self, interaction, title, start, details='', meet_at='', activity='other', minutes=60, players=5, organiser='', time_zone=''):
        async def reply(message):
            await interaction.response.send_message(message, ephemeral=True, allowed_mentions=discord.AllowedMentions.none())

        channel = self.cfg.get('events_channel_id')
        if not channel or str(interaction.guild_id) != str(self.cfg['server_id']) or str(interaction.channel_id) != str(channel):
            await reply('Use /guildevent in #events.')
            return
        gd = self.read()
        if gd is None:
            await reply('The game snapshot is unavailable. Try again after a guild sync.')
            return
        linked = [name for name in self.state.characters_for(interaction.user.id) if name in gd.members]
        if not linked:
            await reply('Link a current guild character with /link and have an officer verify it first.')
            return
        name = ' '.join(organiser.split()).casefold()
        who = next((character for character in linked if character.casefold() == name), None) if name else linked[0]
        if not who:
            await reply('Choose one of your verified guild characters: ' + ', '.join(linked))
            return
        now = int(time.time())
        try:
            starts = event_start(start, time_zone)
            if not now + 60 <= starts <= now + 28 * 86400:
                raise ValueError('Choose a start at least one minute from now and within the next 28 days.')
            title = event_text(title, 80, 'the title', required=True)
            details = event_text(details, 500, 'the details')
            meet_at = event_text(meet_at, 80, 'the meeting place')
            if activity not in KINDS or not 15 <= minutes <= 480 or not 2 <= players <= 40:
                raise ValueError('Choose an activity type, 15–480 minutes, and 2–40 players.')
        except ValueError as error:
            await reply(str(error))
            return
        entry = {
            'id': 'D:' + str(interaction.id), 'kind': 'event_create', 'guild': self.cfg['guild_key'],
            'who': who, 'title': title, 'note': details, 'zone': meet_at, 'activity': activity,
            'starts': starts, 'minutes': minutes, 'slots': players, 't': now,
        }
        records = gd.g.get('guildEvents') or {}
        inbox = self.state.data['inbox']
        if event_id(entry) in records or any(e['id'] == entry['id'] for e in inbox):
            await reply('This event was already queued or imported.')
            return
        count = sum(active(r) and r.get('who') == who for r in records.values())
        count += sum(e.get('kind') == 'event_create' and e.get('who') == who and e['starts'] > now
                     and event_id(e) not in records for e in inbox)
        if count >= 10 or len(inbox) >= 2000:
            await reply('The event queue is full. Wait for guild sync or close an existing event.')
            return
        inbox.append(entry)
        self.state.save()
        self.flush()
        await reply(f'Event queued for {who} at <t:{starts}:F>. It will appear in EPU and get a signup card here after a bridge user imports it and saves the game data. Open it as {who} to prepare the WoW calendar draft.')

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
        records = gd.g.get('guildEvents') or {}
        for e in list(self.state.data['inbox']):
            if e.get('kind') == 'event_create':
                if event_id(e) in records or e['starts'] <= time.time():
                    self.state.data['inbox'].remove(e)
                continue
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

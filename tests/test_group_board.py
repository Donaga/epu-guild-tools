"""Dungeon board: quick groups ping guildmates near the level, and board posts reach Discord."""
import asyncio
import os
import sys
import tempfile
import types
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
import epu_core as core
import shared_bridge as bridge
import group_board

names = ['Chris Baker', 'Tyler Baker', 'Pip Baker', 'Chris Stone']
for n in names:
    clients[n] = Client(n)
A, B, P, S = (clients[n] for n in names)
LEVELS = {'Chris Baker': 20, 'Tyler Baker': 21, 'Pip Baker': 58, 'Chris Stone': 24}
roster = ",".join("['%s']={%d,'Mage','MAGE','Westfall'}" % kv for kv in LEVELS.items())
for c in clients.values():
    c.ex("__rosterExtra={" + roster + "}; __fire('GUILD_ROSTER_UPDATE')")
tick(120)

def notices(c, kind, key):
    return c.ev('(function() local n=0 for k in pairs(__ns.CommunityState().seen) do if k:find("%s\\031"..%s,1,true) then n=n+1 end end return n end)()'
                % (kind, key))

# --- In game: a quick group pings guildmates near its level ----------------------------
kind, post = B.ev("(function() return __ns.PostGroup({type='dungeon',dungeon='The Deadmines',when='now',minutes=60,purpose='q',role='t',note='Defias run',chat=false,lvl=21}) end)()")
check('a quick group posts as a group activity', kind == 'activity' and post is not None)
for c in clients.values():
    c.rt.globals()['post'] = post
check('the quick group reaches guildmates',
      tick_until(lambda: all(c.ev('__ns.CasualStore().activityPosts[post]~=nil') for c in (A, P, S)), 60))
tick(5)
check('a guildmate in the level range gets a notice', notices(A, 'activity', 'post') == 1 and notices(S, 'activity', 'post') == 1)
check('a guildmate far above the range gets none', notices(P, 'activity', 'post') == 0)
check('the poster gets no notice about their own group', notices(B, 'activity', 'post') == 0)
B.ex("__ns.RespondActivity(post,'t','ready','')")
B.ex("__ns.SaveActivity('dungeon',{title='The Deadmines',note='Defias run, now with a healer',minLevel=17,maxLevel=26,slots=5},post)")
tick(10)
check('an edit to the group doesn\'t ping again', notices(A, 'activity', 'post') == 1)
help_id = B.ev("__ns.SaveActivity('help',{title='Elite quest',zone='Westfall',note='',minLevel=10,maxLevel=30,slots=3,minutes=30})")
for c in clients.values():
    c.rt.globals()['help'] = help_id
tick_until(lambda: A.ev('__ns.CasualStore().activityPosts[help]~=nil'), 60)
tick(5)
check('help posts keep their old behaviour (no level ping)', notices(A, 'activity', 'help') == 0)
P.ex("__rosterExtra['Pip Baker'][1]=22; __fire('GUILD_ROSTER_UPDATE')")
A.ex("__rosterExtra['Pip Baker'][1]=22")
tick(2)
kind2, post2 = A.ev("(function() return __ns.PostGroup({type='dungeon',dungeon='Wailing Caverns',when='now',minutes=30,purpose='e',role='d',note='',chat=false,lvl=20}) end)()")
for c in clients.values():
    c.rt.globals()['post2'] = post2
tick_until(lambda: P.ev('__ns.CasualStore().activityPosts[post2]~=nil'), 60)
tick(5)
check('levelling into range means the next group pings you', notices(P, 'activity', 'post2') == 1)
run = S.ev("__ns.SaveRunRequest({dungeon='The Deadmines',purpose='l',role='h',note='Cruel Barb',windows={{s=__ns.RunSlot(__now,true)+3600,e=__ns.RunSlot(__now,true)+3*3600}}})")
for c in clients.values():
    c.rt.globals()['run'] = run
tick_until(lambda: B.ev('__ns.CasualStore().runRequests[run]~=nil'), 60)
tick(5)
check('run requests still ping guildmates near the level', notices(B, 'run', 'run') == 1)
B.ex("__ns.RespondRunRequest(run,'in','t',{{s=__ns.RunSlot(__now,true)+3600,e=__ns.RunSlot(__now,true)+2*3600}},'')")
tick(10)

# --- On Discord: the companion posts and updates board cards ----------------------------
root = Path(tempfile.mkdtemp())
sv = root / 'EPUGuild.lua'
def snapshot():
    A.ex('__dumpSV("' + str(sv).replace('\\', '/') + '")')
    return core.load_guild_data(str(sv), 'E Pluribus Unum')
gd = snapshot()
NOW = int(A.ev('__now'))
board = {e['key']: e for e in group_board.entries(gd, NOW)}
g1 = board.get('activity:' + post) or {}
check('the quick group is an open board entry with its sign-ups',
      g1.get('kind') == 'group' and g1.get('status') == 'open' and g1.get('ready') == 1 and g1.get('roles', {}).get('t') == 1)
check('help posts and run requests are on the board too',
      (board.get('activity:' + help_id) or {}).get('kind') == 'help' and (board.get('run:' + run) or {}).get('interested') == 2)
check('guild events are left to their own cards', all(not k.startswith('event') for k in board))

class Message:
    def __init__(self, i):
        self.id, self.edits = i, []
    async def edit(self, **kw):
        self.edits.append(kw)
class Channel:
    guild = types.SimpleNamespace(id=1)
    def __init__(self):
        self.sent, self.messages, self.gone = [], {}, set()
    async def send(self, **kw):
        m = Message(100 + len(self.sent)); self.sent.append(kw); self.messages[m.id] = m
        return m
    async def fetch_message(self, i):
        if i in self.gone:
            raise group_board.discord.NotFound(types.SimpleNamespace(status=404, reason='gone'), 'gone')
        return self.messages[i]
channel = Channel()
state = core.State(str(root / 'state.json'))
cfg = {'server_id': '1', 'group_board_post': True, 'group_board_channel_id': '5'}
gb = group_board.GroupBoard(cfg, state, types.SimpleNamespace(get_channel=lambda i: channel))
asyncio.run(gb.refresh(gd, NOW)); asyncio.run(gb.refresh(gd, NOW))
titles = [kw['embed'].title for kw in channel.sent]
check('each open board entry is posted once (%s)' % titles, len(channel.sent) == 4
      and 'Quick group: The Deadmines' in titles and 'Help wanted: Elite quest' in titles and 'Run request: The Deadmines' in titles)
card = next(kw['embed'] for kw in channel.sent if kw['embed'].title == 'Quick group: The Deadmines')
text = str(card.to_dict())
check('the card shows levels, sign-ups, the end time and how to join',
      '17–26' in text and '1/5 ready' in text and '1 Tank' in text and '<t:' in text and '/epu groups' in text)
check('cards never ping anyone', all(kw['allowed_mentions'].everyone is False and kw['allowed_mentions'].users is False for kw in channel.sent))
run_card = str(next(kw['embed'] for kw in channel.sent if kw['embed'].title.startswith('Run request')).to_dict())
check('the run request card shows its times and interest', '<t:' in run_card and '2 so far' in run_card and 'Loot farming' in run_card)

S.ex("__ns.RespondActivity(post,'h','ready','')")
tick_until(lambda: A.ev('#__ns.ActivityReplies(post)') == 2, 60)
gd = snapshot()
asyncio.run(gb.refresh(gd, NOW))
qmsg = channel.messages[state.data['group_board']['activity:' + post]['message']]
check('a new sign-up edits the card instead of posting again', len(channel.sent) == 4 and '2/5 ready' in str(qmsg.edits[-1]['embed'].to_dict()))
B.ex('__ns.CloseActivity(post)')
tick_until(lambda: A.ev('__ns.CasualStore().activityPosts[post].status') == 'closed', 60)
gd = snapshot()
asyncio.run(gb.refresh(gd, NOW))
check('a closed group greys out and stops being tracked',
      '(closed)' in qmsg.edits[-1]['embed'].title and 'activity:' + post not in state.data['group_board'])
asyncio.run(gb.refresh(gd, NOW))
check('and is never posted again', len(channel.sent) == 4)
asyncio.run(gb.refresh(gd, NOW + 2 * 3600))
hmsg = channel.messages[100 + titles.index('Help wanted: Elite quest')]
check('an expired post greys out even without a new save', hmsg.edits and '(expired)' in hmsg.edits[-1]['embed'].title)
check('only the run request is still tracked', list(state.data['group_board']) == ['run:' + run])
channel.gone.add(state.data['group_board']['run:' + run]['message'])
state.data['group_board']['run:' + run]['signature'] = 'changed since'
asyncio.run(gb.refresh(gd, NOW + 2 * 3600 + 1))
check('a card deleted on Discord is posted again at its next change while the request is open', len(channel.sent) == 5)
missing = core.GuildData({'guilds': {'E Pluribus Unum': {'members': gd.g['members']}}}, 'E Pluribus Unum')
asyncio.run(gb.refresh(missing, NOW + 2 * 3600 + 2))
check('a card whose record is missing from one read waits', 'run:' + run in state.data['group_board'])
asyncio.run(gb.refresh(missing, NOW + 9 * 86400))
check('and greys out once it would have ended', not state.data['group_board']
      and 'no longer on the board' in channel.messages[104].edits[-1]['embed'].title)
check('state.json keeps the cards between restarts', 'group_board' in core.State(str(root / 'state.json')).data)
cfg['group_board_post'] = False
before = len(channel.sent)
P.ex("__ns.PostGroup({type='dungeon',dungeon='Shadowfang Keep',when='now',minutes=60,purpose='e',role='d',note='',chat=false,lvl=22})")
tick(10)
asyncio.run(gb.refresh(snapshot(), NOW))
check('off means off', len(channel.sent) == before)

# --- Odd records and the sync helper --------------------------------------------------
odd = core.GuildData({'guilds': {'E': {'members': {1: 'A B'}, 'activityPosts': {'x': 5, 7: {}, 'y': {'who': 'Gone Away', 'kind': 'dungeon', 'title': 'X'}},
                                      'runRequests': {'z': {'who': 'A B', 'dungeon': 'Y', 'windows': 'nope'}}}}})
check("odd records don't break the read", [e['status'] for e in group_board.entries(odd, NOW)] == ['expired'])
snap = bridge.public_snapshot(gd, 'Chris Baker')
check('sync helpers carry the board to the bot', post2 in snap['game']['activityPosts'] and run in snap['game']['runRequests']
      and snap['game']['runInterest'] and snap['game']['activityReplies'])

# --- The companion's config --------------------------------------------------------------
import json, shutil, importlib
cfgdir = tempfile.mkdtemp()
WOW = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "feed_channel_id": "3", "wow_path": WOW}, open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py", "group_board.py", "event_sync.py", "links_roles.py"):
    shutil.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check('the board is on by default and falls back to the milestones channel',
      bot.cfg['group_board_post'] is True and bot.cfg['group_board_channel_id'] == '3')
check('no addon runtime errors', all((c.ev('__errors') or 0) == 0 for c in clients.values()))
print(f"{check.failed} failed" if check.failed else "all passed")
sys.exit(1 if check.failed else 0)

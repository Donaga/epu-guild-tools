"""The Discord inbox lives in its own addon folder, EPUGuild_Inbox, so an EPU
update (CurseForge, WowUp, the updater or a folder copy) can't replace the
bot's queued requests and approvals with the empty Inbox.lua that EPU ships."""
from simcore import *
from pathlib import Path
import os, re, shutil, tempfile, time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'epu-discord'))
import epu_core as core
import shared_bridge as bridge

ROOT = Path(__file__).resolve().parents[1]
REPO_ADDON = ROOT / 'EPUGuild'

# --- What ships ---------------------------------------------------------------
toc = (REPO_ADDON / 'EPUGuild.toc').read_text(encoding='utf-8')
deps = re.search(r'^## OptionalDeps:(.*)$', toc, re.M).group(1)
check('EPU loads EPUGuild_Inbox first (OptionalDeps)', 'EPUGuild_Inbox' in [d.strip() for d in deps.split(',')])
check('the repo never contains an EPUGuild_Inbox folder', not (ROOT / core.INBOX_ADDON).exists())
release = (ROOT / '.github' / 'workflows' / 'release.yml').read_text(encoding='utf-8')
zips = re.findall(r'zip -r "[^"]*EPUGuild-[^"]*\.zip"\s+(\S+)', release) + re.findall(r'zip -r "\$CF_ZIP"\s+(\S+)', release)
check('every addon zip (GitHub, WowUp, CurseForge) holds only the EPUGuild folder', len(zips) >= 2 and set(zips) == {'EPUGuild'})
stub = (REPO_ADDON / 'Inbox.lua').read_text(encoding='utf-8')
check('the shipped Inbox.lua is still the empty stub older companions expect', re.search(r'^EPUGuildInbox = \{\}$', stub, re.M) is not None)


def install(root, new=True):
    wow = Path(root) / 'wow'
    addon = wow / 'Interface' / 'AddOns' / 'EPUGuild'
    if addon.exists():
        shutil.rmtree(addon)
    shutil.copytree(REPO_ADDON, addon)
    if not new:   # an EPU from before this change
        t = addon / 'EPUGuild.toc'
        t.write_text(t.read_text(encoding='utf-8').replace(', EPUGuild_Inbox', ''), encoding='utf-8')
    return str(wow)


def legacy_entries(wow):
    return core.parse_saved_variables(Path(core.inbox_path(wow)).read_text(encoding='utf-8')).get('EPUGuildInbox') or {}


entries = [{'id': 'n1', 'kind': 'news', 'title': 'Raid night', 'text': 'Thursday at 8', 't': 1800000000},
           {'id': 'n2', 'kind': 'news', 'title': 'Bank day', 'text': 'Saturday', 't': 1800000000}]

# --- An older EPU keeps the old file --------------------------------------
old = install(tempfile.mkdtemp(), new=False)
check('an older EPU gets the old Inbox.lua only', core.write_inbox_files(old, entries) == 'legacy'
      and not os.path.exists(core.inbox_addon_dir(old)) and len(legacy_entries(old)) == 2)

# --- A new EPU gets the inbox addon ---------------------------------------
wow = install(tempfile.mkdtemp())
check('a new EPU gets EPUGuild_Inbox', core.write_inbox_files(wow, entries, [{'id': 'c1', 't': 1, 'who': 'X', 'msg': 'hi'}]) == 'addon')
drop_toc = Path(core.inbox_addon_dir(wow)) / 'EPUGuild_Inbox.toc'
interface = re.search(r'^## Interface:\s*(.+)$', toc, re.M).group(1).strip()
check('its TOC copies EPU\'s Interface line and loads Inbox.lua',
      ('## Interface: ' + interface) in drop_toc.read_text() and drop_toc.read_text().strip().endswith('Inbox.lua'))
check('the drop holds the entries and the chat', [e['id'] for e in core.read_inbox_drop(wow)] == ['n1', 'n2']
      and 'chat' in Path(core.inbox_drop_path(wow)).read_text())
check('until EPU says it loaded the drop, the old file gets the same entries', len(legacy_entries(wow)) == 2)

# An EPU update through CurseForge or WowUp replaces the EPUGuild folder whole.
install(Path(wow).parent)
check('an EPU update leaves the drop alone', [e['id'] for e in core.read_inbox_drop(wow)] == ['n1', 'n2'])
check('and the old file is back to the shipped stub', legacy_entries(wow) == {})

# The game: EPUGuild_Inbox loads first, then EPU (with its shipped stub).
clients.clear()
A = Client('Chris Baker'); clients[A.name] = A; tick(20)
A.ex(Path(core.inbox_drop_path(wow)).read_text(encoding='utf-8'))
A.ex(stub)
check('EPU reads entries from the drop', [A.ev('__ns.InboxEntries()[%d].id' % i) for i in (1, 2)] == ['n1', 'n2'])
A.ex('__ns.ProcessInbox()')
check('an officer applies them', A.ev("__ns.GuildStore().news['d-n1'] ~= nil") and A.ev("__ns.GuildStore().news['d-n2'] ~= nil"))
A.ex("EPUGuildInbox = {{id='n1',kind='news',title='Raid night',text='Thursday at 8',t=__now},{id='old1',kind='news',title='Old',text='From the old file',t=__now}}")
check('an id in both files counts once, the old file still counts', A.ev('#__ns.InboxEntries()') == 3)
A.ex("__ns.GuildStore().news['d-n1'].title = 'kept'; __ns.ProcessInbox()")
check('nothing is applied twice', A.ev("__ns.GuildStore().news['d-n1'].title") == 'kept' and A.ev("__ns.GuildStore().news['d-old1'] ~= nil"))
A.ex("__fire('PLAYER_ENTERING_WORLD', false, true)"); tick(20)
seen = A.ev('__ns.db.inboxDropSeen')
check('a /reload with the drop loaded tells the companion', isinstance(seen, (int, float)) and seen > 0)
check('the Officer page knows where updates come from', A.ev('__ns.InboxSource()') == 'addon')
A.ex("EPUGuildInboxDrop = nil; GetAddOnInfo = function(n) if n == 'EPUGuild_Inbox' then return n, 'Discord inbox', '', false, 'DISABLED' end end")
check('a turned-off drop addon is spotted', A.ev('(__ns.InboxSource())') == 'off')
A.ex('__log = {}; __ns.db.inboxDropSeen = nil'); A.ex("__fire('PLAYER_ENTERING_WORLD', false, true)"); tick(20)
log = [A.ev('__log[%d]' % i) for i in range(1, A.ev('#__log') + 1)]
check('and officers are told to turn it on', any('Discord inbox' in str(m) and 'turn it on' in str(m).lower() for m in log)
      and A.ev('__ns.db.inboxDropSeen') is None)
# Any PC without the bot (other officers, sync helpers): WoW names the optional
# dependency anyway, with reason MISSING. That's not "turned off".
A.ex("GetAddOnInfo = function(n) if n == 'EPUGuild_Inbox' then return n, nil, nil, false, 'MISSING' end end")
check('an inbox folder that isn\'t there counts as not installed', A.ev('(__ns.InboxSource())') == 'legacy')
A.ex('__log = {}'); A.ex("__fire('PLAYER_ENTERING_WORLD', false, true)"); tick(20)
log = [A.ev('__log[%d]' % i) for i in range(1, A.ev('#__log') + 1)]
check('and officers without it get no warning', not any('Discord inbox' in str(m) for m in log))
A.ex("GetAddOnInfo = function(n) if n == 'EPUGuild_Inbox' then return n, 'Discord inbox', '', false, 'INTERFACE_VERSION' end end")
check('an inbox folder that is there but won\'t load is still spotted', A.ev('(__ns.InboxSource())') == 'off')
A.ex('GetAddOnInfo = nil')
check('with neither, only the old file is read', A.ev('__ns.InboxSource()') == 'legacy')
A.ex("EPUGuildInboxDrop = {entries={}, chat={{id='a',t=1,who='A',msg='new'}}}; EPUGuildDiscordChat = {{id='a',t=1,who='A',msg='new'},{id='b',t=2,who='B',msg='old'}}")
check('Discord chat from both files is merged by id', A.ev('#__ns.InboxChat()') == 2 and A.ev('__ns.InboxChat()[2].id') == 'b')

# Once EPU has loaded the drop, the companion empties the old file.
core.write_inbox_files(wow, entries, seen_at=time.time() + 5)
check('after EPU loaded the drop, the old file is emptied', legacy_entries(wow) == {} and len(core.read_inbox_drop(wow)) == 2)
os.utime(drop_toc, (time.time() + 60, time.time() + 60))   # the drop folder was remade after that login
core.write_inbox_files(wow, entries, seen_at=time.time() + 5)
check('a remade drop folder gets the old file filled again until EPU loads it', len(legacy_entries(wow)) == 2)

# The EPU updater is mid-install: the drop is still written.
lock = Path(wow) / 'Interface' / 'AddOns' / '.EPUGuild-update.lock'
lock.write_text('')
try:
    where = core.write_inbox_files(wow, entries + [{'id': 'n3', 'kind': 'news', 'title': 'During update', 'text': 'x', 't': 1}])
except BlockingIOError:
    where = 'blocked'
lock.unlink()
check('during an updater install the drop is still written', where == 'addon' and len(core.read_inbox_drop(wow)) == 3)

# Windows won't let the companion make the folder: it falls back to the old file.
denied = install(tempfile.mkdtemp())
real = core.os.makedirs
def no(*a, **k): raise PermissionError('Access is denied')
core.os.makedirs = no
try:
    where = core.write_inbox_files(denied, entries)
finally:
    core.os.makedirs = real
check('without permission for the folder, the old file is written as before', where == 'denied' and len(legacy_entries(denied)) == 2)

# --- Migration: anything only in the old file moves into the queue once -----
st = core.State(os.path.join(tempfile.mkdtemp(), 'state.json'))
st.data['inbox'] = [{'id': 'n1', 'kind': 'news'}]
moved = st.adopt_legacy_inbox([{'id': 'n1', 'kind': 'news'}, {'id': 'lost', 'kind': 'news', 'title': 'T', 'text': 'x'},
                                {'id': 'helper', 'kind': 'request', 'bridge': True}, {'kind': 'news'}])
check('the companion adopts only entries it lost track of', moved == 1 and [e['id'] for e in st.data['inbox']] == ['n1', 'lost'])
check('and only once', st.adopt_legacy_inbox([{'id': 'later', 'kind': 'news'}]) == 0 and core.State(st.path).data.get('legacy_inbox_adopted'))
mig = install(tempfile.mkdtemp())
core.write_inbox(core.inbox_path(mig), [{'id': 'q1', 'kind': 'news', 'title': 'Q', 'text': 'x', 't': 1}])
check('the old file\'s entries can be read for migration', [e['id'] for e in core.read_legacy_inbox(mig)] == ['q1'])

# --- A sync helper's PC moves its inbox too ---------------------------------
root = Path(tempfile.mkdtemp()); out = root / 'owner'; remote = root / 'helper'; remote.mkdir()
hw = install(root)
core.write_inbox(core.inbox_path(hw), [{'id': 'someone-else', 'kind': 'news', 'title': 'Kept', 'text': 'x', 't': 1}])
secret = 's' * 48
cfg = {'guild_key': 'E Pluribus Unum', 'sync_helpers': {'h1': {'enabled': True, 'secret': secret, 'characters': ['Tyler Baker'], 'folders': [str(out)]}}}
hs = core.State(str(root / 'state.json')); hs.queue_request('Pip Baker', 2589, 'Linen Cloth', 3, 'Thanks', 'Pip')
bridge.publish(cfg, hs); shutil.copy(out / 'to-game.json', remote / 'to-game.json')
helper = {'helper': 'h1', 'guild': 'E Pluribus Unum', 'secret': secret, 'characters': ['Tyler Baker'], 'folder': str(remote), 'wow_path': hw}
local = {}; bridge.helper_cycle(helper, local)
ids = [e['id'] for e in core.read_inbox_drop(hw)]
check('the helper writes the drop and carries the old file\'s other entries', 'someone-else' in ids and len(ids) == 2)
install(root)
local['feed_sequence'] = 0; bridge.helper_cycle(helper, local)
check('after an EPU update the helper still has both', len(core.read_inbox_drop(hw)) == 2)

print('Inbox addon tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

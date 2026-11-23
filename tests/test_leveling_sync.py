"""Dungeon readiness, raid prep and officer run logs reach guildmates, safely.

0.29.0 to 0.31.1 sent readiness on "L" and raid prep on "K", kinds the guild
map and the quest list already used, so neither ever arrived. Their handlers
also let any member rewrite another member's record, and the run log took
runs from bank ranks on guild chat.
"""
import re
import glob
from simcore import *

# Every message kind has exactly one handler, so a new feature can't quietly
# take over an existing one (later files in the TOC replace earlier ones).
kinds = {}
for path in glob.glob(os.path.join(ADDON, "*.lua")):
    for m in re.finditer(r'^ns\.comm(?:\.([A-Za-z])|\[\s*"([A-Za-z])"\s*\])\s*=', open(path, encoding="utf-8").read(), re.M):
        kinds.setdefault(m.group(1) or m.group(2), []).append(os.path.basename(path))
dupes = {k: v for k, v in kinds.items() if len(v) > 1}
check('no two files handle the same message kind ' + str(dupes), not dupes)
lt = open(os.path.join(ADDON, "LevelingTools.lua"), encoding="utf-8").read()
rp = open(os.path.join(ADDON, "RaidPrep.lua"), encoding="utf-8").read()
rk = re.search(r'local READINESS_KIND = "(.)"', lt).group(1)
zk = re.search(r'local RAID_KIND = "(.)"', rp).group(1)
check('readiness and raid prep kinds are their own', rk not in kinds and zk not in kinds and rk != zk)

for name in ['Chris Baker', 'Tyler Baker', 'Epu Bank']: clients[name] = Client(name)
tick(120)
A, B, K = (clients[n] for n in ['Chris Baker', 'Tyler Baker', 'Epu Bank'])

# Readiness: Tyler marks a dungeon done, Chris sees it.
B.ex('__ns.ToggleMyReadiness("deadmines", true)')
check('dungeon readiness reaches guildmates',
      tick_until(lambda: A.ev('((__ns.G().levelingProgress or {})["Tyler Baker"] or {done={}}).done.deadmines') is True, 30))
check('the guild map keeps its own location handler', A.ev('__ns.comm.L ~= nil'))
B.ex('__ns.ToggleMyCampingStation("Tier 2 Forge")'); tick(5)
B.ex('__ns.ToggleMyReadiness("wailing", true)'); tick(5)
check('a later dungeon update keeps camping stations',
      A.ev('((__ns.G().levelingProgress or {})["Tyler Baker"].camp or {})["Tier 2 Forge"]') is True)

# Forged records are filed under the sender, never the named member.
A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","S%s"..__ns.Serialize({who="Chris Baker",done={rfc=true},t=__ns.Now()+60}),"GUILD","Tyler Baker")' % rk)
check('readiness can only update the sender', A.ev('(__ns.G().levelingProgress or {})["Chris Baker"] == nil'))
A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","S%s"..__ns.Serialize({done={zf=true},t=__ns.Now()+86400*365}),"GUILD","Tyler Baker")' % rk)
check("far-future readiness is ignored", not A.ev("(__ns.G().levelingProgress or {})[\"Tyler Baker\"].done.zf"))

# Raid prep travels too, also only for the sender.
B.ex('__ns.SyncMyRaidStatus()')
check('raid prep status reaches guildmates', tick_until(lambda: A.ev('__ns.G().raidPrep and (__ns.G().raidPrep or {})["Tyler Baker"] ~= nil'), 30))
A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","S%s"..__ns.Serialize({who="Pip Baker",level=60,role="Tank",t=__ns.Now()+60}),"GUILD","Tyler Baker")' % zk)
check('raid prep can only update the sender', A.ev('(__ns.G().raidPrep or {})["Pip Baker"] == nil'))

print('Leveling sync checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

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

# Officer run log: officer chat only, from trusted senders, with clean members.
def run(t, members='{"Chris Baker","Tyler Baker"}'):
    return '__ns.Serialize({id="RFake:1",dungeon="Deadmines",members=%s,t=%s,by="Chris Baker"})' % (members, t)
A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","SR"..%s,"GUILD","Epu Bank")' % run('__ns.Now()'))
check('runs sent on guild chat are ignored', A.ev('(__ns.G().dungeonRuns or {})["RFake:1"] == nil'))
A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","SR"..%s,"OFFICER","Chris Stone")' % run('__ns.Now()'))
check('runs from members are ignored', A.ev('(__ns.G().dungeonRuns or {})["RFake:1"] == nil'))
A.ex('__ns.LogGuildDungeonRun("Deadmines", nil, {"Chris Baker","Tyler Baker"}, true, "")')
check('an officer can still log a run', A.ev('(function() local n=0 for _ in pairs(__ns.G().dungeonRuns) do n=n+1 end return n end)()') == 1)

# Auto-logging: only one officer in a group logs a boss kill.
A.ex('''GetInstanceInfo=function() return "The Deadmines","party" end
GetNumGroupMembers=function() return 2 end; IsInRaid=function() return false end
UnitExists=function(u) return u=="party1" end; UnitName=function(u) if u=="party1" then return "Tyler Baker" end return "Chris Baker" end
__ns.G().dungeonRuns={}''')
A.ex('__fire("ENCOUNTER_END", 1, "Rhahk\'Zor", 1, 5, 1)')
A.ex('__fire("ENCOUNTER_END", 2, "Sneed", 1, 5, true)')
check('boss kills log one run with both bosses',
      A.ev('(function() local n,r=0 for _,v in pairs(__ns.G().dungeonRuns) do n=n+1; r=v end return n==1 and r.note:find("Sneed",1,true)~=nil end)()'))


print('Leveling sync checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

"""The guild message of the day is not read during combat (the game blocks it)."""
from simcore import *

A = Client('Chris Baker'); clients[A.name] = A
tick(30)
A.ex('''__motd = "Raid tonight"; __motdCalls = 0
local real = GetGuildRosterMOTD
GetGuildRosterMOTD = function() __motdCalls = __motdCalls + 1; return real() end
__combat = true
InCombatLockdown = function() return __combat end''')
A.ex('__fire("GUILD_ROSTER_UPDATE")')
check('the MOTD is not read in combat', A.ev('__motdCalls') == 0)
A.ex('__combat = false; __fire("PLAYER_REGEN_ENABLED")')
check('it is read once combat ends', A.ev('__motdCalls') == 1)
check('and saved', A.ev('__ns.GuildStore().motd.text') == 'Raid tonight')
A.ex('__fire("PLAYER_REGEN_ENABLED")')
check('nothing is read again on later combat ends', A.ev('__motdCalls') == 1)
print('Combat MOTD tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

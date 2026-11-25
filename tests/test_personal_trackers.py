"""Personal trackers (/epu trackers): lockouts, cooldowns, farming session.

The first version (PR #65) read class colors and item sell prices through
`local a, b = f and f()`, which keeps only the first value, so names never
had their class color and the farming session's loot value stayed at 0. Its
window made new widgets on every refresh, it scanned profession cooldowns on
every cooldown update (several a second in combat), and it counted kills from
a combat chat message the game no longer sends.
"""
import os
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(5)

A.ex('''
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" } }
RequestRaidInfo = function() end
GetNumSavedInstances = function() return 1 end
GetSavedInstanceInfo = function(i)
  -- name, id, reset, difficulty, locked, extended, mostsig, isRaid, maxPlayers, diffName, numEncounters, progress
  return "Molten Core", 409, 3 * 86400, 9, true, false, 0, true, 40, "40 Player", 10, 4
end
__arcaniteChecks = 0
IsSpellKnown = function(id)
  if id == 17187 then __arcaniteChecks = __arcaniteChecks + 1; return true end
  return false
end
GetSpellCooldown = function(id) if id == 17187 then return GetTime() - 600, 172800, 1 end return 0, 0, 1 end
__combat = false
InCombatLockdown = function() return __combat end
function __texts()
  local t = {}
  for _, w in ipairs(EPUGuildPersonalTrackers.pool.used) do
    if w.GetText and w:IsShown() then t[#t + 1] = w:GetText() end
  end
  return table.concat(t, "\\n")
end
''')

# --- Class colors ---
A.ex('__ns.OpenPersonalTrackers("lockouts")')
text = A.ev('__texts()') or ''
check('lockouts list the raid with its boss progress', 'Molten Core [40 Player] (4/10)' in text)
check("lockouts show the character's name in their class color", '|cff3fc7eb' in text)
check('the saved lockout keeps the class', A.ev('(function() for _, r in pairs(__ns.db.personalTrackers.lockouts[GetRealmName() or "Realm"] or {}) do return r.classFile end end)()') == 'MAGE')

A.ex('__ns.OpenPersonalTrackers("cooldowns")')
text = A.ev('__texts()') or ''
check('cooldowns list Arcanite with time left', 'Transmute: Arcanite:  |cffffd100' in text)
check("cooldowns show the character's name in their class color", '|cff3fc7eb' in text)

# --- Cooldown scan is folded and waits out combat ---
before = A.ev('__arcaniteChecks')
for _ in range(60):
    A.ex('__fire("SPELL_UPDATE_COOLDOWN"); __fire("BAG_UPDATE_COOLDOWN")')
check('a burst of cooldown updates does not scan at once', A.ev('__arcaniteChecks') == before)
tick(4)
check('a burst of cooldown updates scans once, a moment later', A.ev('__arcaniteChecks') == before + 1)

A.ex('__combat = true')
before = A.ev('__arcaniteChecks')
for _ in range(30):
    A.ex('__fire("SPELL_UPDATE_COOLDOWN")')
    tick(0.5)
tick(5)
check('no cooldown scan happens in combat', A.ev('__arcaniteChecks') == before)
A.ex('__combat = false; __fire("PLAYER_REGEN_ENABLED")')
tick(4)
check('the scan skipped in combat runs once combat ends', A.ev('__arcaniteChecks') == before + 1)
A.ex('__fire("PLAYER_REGEN_ENABLED")')
tick(4)
check('leaving combat again with nothing new does not scan', A.ev('__arcaniteChecks') == before + 1)

# --- Farming session loot value and drops ---
A.ex('''__qual = { [30001] = 2 }
__fire("CHAT_MSG_LOOT", "You receive loot: " .. __link(30001) .. "x3.")
__fire("CHAT_MSG_LOOT", "You receive loot: " .. __link(30002) .. ".")
__ns.OpenPersonalTrackers("session")''')
text = A.ev('__texts()') or ''
check('looted items add their vendor value to the session', 'Item Vendor Value: |cffffd1004c|r' in text)
check('an uncommon drop is listed with its count', '[Test Item 30001]|h|r x3' in text)
check('a common drop is not listed as notable', 'Test Item 30002' not in text)
check('the session counts only kills that gave XP', 'Kills that gave XP:' in text)
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'EPUGuild', 'PersonalTrackers.lua'), encoding='utf-8').read()
check('the trackers no longer listen for the removed combat death message', 'CHAT_MSG_COMBAT_HOSTILE_DEATH' not in src)

# --- Redraws reuse their widgets ---
A.ex('''local db = __ns.db.personalTrackers
db.consumables = { { id = 30001, name = "Test Item 30001", target = 10 }, { id = 30002, name = "Test Item 30002", target = 5 } }
__made = 0
local M = getmetatable(UIParent)
local fs, tex = M.CreateFontString, M.CreateTexture
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end
M.CreateTexture = function(...) __made = __made + 1; return tex(...) end
local cf = CreateFrame
CreateFrame = function(...) __made = __made + 1; return cf(...) end''')
tabs = ['lockouts', 'cooldowns', 'session', 'consumables', 'reppvp', 'rested']
cycle = '; '.join(f'__ns.OpenPersonalTrackers("{t}")' for t in tabs)
A.ex(cycle)
A.ex(cycle)
before = A.ev('__made')
for _ in range(10):
    A.ex(cycle)
check('switching tracker tabs over and over makes nothing new', A.ev('__made') == before)
A.ex('__ns.OpenPersonalTrackers("consumables")')
before = A.ev('__made')
for _ in range(10):
    A.ex('EPUGuildPersonalTrackers:Refresh()')
check('redrawing the consumables list makes nothing new', A.ev('__made') == before)
check('the consumables list still shows its items', 'Test Item 30001' in (A.ev('__texts()') or '') or
      A.ev('(function() for _, w in ipairs(EPUGuildPersonalTrackers.pool.used) do if w.GetText and (w:GetText() or ""):find("Test Item 30001", 1, true) then return true end end end)()') is True)
check('nothing went wrong drawing the trackers', not A.ev('__errors'))

print('Personal tracker checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

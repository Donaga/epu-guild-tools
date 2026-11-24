"""Rested XP across alts (Personal trackers, Rested XP tab; /epu rested).

Each character saves its level, XP, rested XP, whether it is resting and when
it logged out. For alts the window estimates what they have built up since:
5% of a level every 8 hours resting, a quarter of that elsewhere, up to 1.5
levels.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(5)

A.ex('''
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" }, ROGUE = { colorStr = "fffff569" } }
__level, __xp, __xpMax, __rested, __resting = 20, 4000, 10000, 2500, true
UnitLevel = function() return __level end
UnitXP = function() return __xp end
UnitXPMax = function() return __xpMax end
GetXPExhaustion = function() return __rested end
IsResting = function() return __resting end
GetMaxPlayerLevel = function() return 60 end
function __texts()
  local t = {}
  for _, w in ipairs(EPUGuildPersonalTrackers.pool.used) do
    if w.GetText and w:IsShown() then t[#t + 1] = w:GetText() end
  end
  return table.concat(t, "\\n")
end
function __est(rec, ago, live) local r, cap, full = __ns.EstimateRested(rec, os.time(), live); return r .. "/" .. cap .. "/" .. full end
''')

# --- Recording ---
A.ex('__ns.RecordRested(false)')
me = A.ev('__ns.me')
rec = lambda: A.ev(f'__ns.RestedDB()["{me}"]')
check('this character records level, XP and rested XP', rec().level == 20 and rec().xp == 4000 and rec().rested == 2500)
check('this character records that it is resting', rec().resting is True)
check('this character records its class', rec().classFile == 'MAGE')
check('a character still logged in has no logout time', rec().logout is None)
A.ex('__resting = false; __rested = 3000; __fire("PLAYER_LOGOUT")')
check('logging out stamps the logout time', rec().logout is not None)
check('logging out saves the latest rested XP and resting state', rec().rested == 3000 and rec().resting is False)
A.ex('__resting = true; __fire("PLAYER_UPDATE_RESTING")')
tick(2)
check('entering an inn updates the saved state a moment later', rec().resting is True)
check('a fresh update clears the logout time', rec().logout is None)

# --- Estimates ---
hour = 3600
def est(rested, resting, ago, xpmax=10000, live='false', logout=True):
    field = 'logout' if logout else 'seen'
    return A.ev(f'__est({{ xpMax = {xpmax}, rested = {rested}, resting = {str(resting).lower()}, {field} = os.time() - {ago} }}, {ago}, {live})')

check('8 hours resting adds 5% of a level', est(0, True, 8 * hour) == '500/15000/' + str(232 * hour))
check('32 hours outside an inn adds 5% of a level', est(0, False, 32 * hour).startswith('500/15000/'))
check('rested XP stops at 1.5 levels', est(14000, True, 7 * 24 * hour) == '15000/15000/0')
check('a character that crashed out counts from when it was last seen', est(0, True, 16 * hour, logout=False).startswith('1000/'))
check('rested XP already saved is kept', est(2000, True, 0).startswith('2000/'))
check('the character you are on shows its real rested XP, no estimate', est(2000, True, 48 * hour, live='true').startswith('2000/'))
check('time to full counts down at the resting rate', est(14500, True, 0) == '14500/15000/28800')
check('a record with no XP bar estimates nothing', A.ev('__est({ xpMax = 0, rested = 0, resting = true, logout = os.time() - 99999 })') == '0/0/0')

# --- Window ---
A.ex(f'''local list = __ns.RestedDB()
list["Pip Quickfoot"] = {{ level = 34, xp = 0, xpMax = 20000, rested = 1000, resting = true, classFile = "ROGUE", seen = os.time() - 80 * 3600, logout = os.time() - 80 * 3600 }}
list["Brenna Ashford"] = {{ level = 12, xp = 0, xpMax = 8000, rested = 0, resting = false, classFile = "MAGE", seen = os.time() - 10 * 3600, logout = os.time() - 10 * 3600 }}
list["Old Main"] = {{ level = 60, xp = 0, xpMax = 0, rested = 0, maxed = true, classFile = "MAGE", seen = os.time() - 3600, logout = os.time() - 3600 }}''')
A.ex('__ns.OpenPersonalTrackers("rested")')
text = A.ev('__texts()') or ''
check('the Rested XP tab lists every character', all(n in text for n in ['Pip Quickfoot', 'Brenna Ashford', 'Old Main', me.split('-')[0]]))
# Pip: 1000 + 80h * 20000*0.05/8h = 1000 + 10000 = 11000 -> 55%
check('an alt resting in an inn shows its estimated share of a level', '55% of a level|r (11 bubbles, 11000 XP)' in text)
# Brenna: 10h outside = 10 * 8000*0.05/32 = 125 -> 2%
check('an alt logged out in the open builds rested XP slowly', '2% of a level|r (0 bubbles, 125 XP)' in text)
check('an estimate says when the alt logged out', 'Logged out resting, 3d 8h ago (estimate)' in text)
check('a max-level character says rested XP does not matter', 'Max level' in text)
check('the character you are on is marked and shown live', 'this character' in text and 'Resting now' in text)
check('names are in class colors', '|cfffff569' in text)
check('alts logged out in the open get the inn tip', 'four times faster' in text)
pos = [text.find(n) for n in ['Pip Quickfoot', 'Brenna Ashford', 'Old Main']]
check('most rested first, max level last', pos[0] < pos[1] < pos[2])

A.ex('local r = __ns.RestedDB()["Pip Quickfoot"]; r.rested = 29000; r.logout = os.time() - 100 * 3600; r.seen = r.logout')
A.ex('EPUGuildPersonalTrackers:Refresh()')
text = A.ev('__texts()') or ''
check('an alt at the cap shows Full', '150% of a level|r (30 bubbles, 30000 XP)  -  |cff4ade80Full|r' in text)

# --- Redraws reuse widgets ---
A.ex('''__made = 0
local M = getmetatable(UIParent)
local fs = M.CreateFontString
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end
local cf = CreateFrame
CreateFrame = function(...) __made = __made + 1; return cf(...) end''')
A.ex('EPUGuildPersonalTrackers:Refresh(); EPUGuildPersonalTrackers:Refresh()')
before = A.ev('__made')
for _ in range(10):
    A.ex('EPUGuildPersonalTrackers:Refresh()')
check('redrawing the Rested XP tab makes nothing new', A.ev('__made') == before)

# --- Reachable from the main window and by slash command ---
A.ex('EPUGuildPersonalTrackers:Hide(); SlashCmdList["EPUGUILD"]("rested")')
check('/epu rested opens the trackers on the Rested XP tab',
      A.ev('EPUGuildPersonalTrackers:IsShown()') and 'Rested XP Across Alts' in (A.ev('__texts()') or ''))
A.ex('''EPUGuildPersonalTrackers:Hide()
function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end
__ns.UI:Show(); __ns.UI.nav.membertools:Click(); __ns.UI.search:SetText("rested")''')
check('searching member tools for rested finds the Personal trackers tile', 'trackers' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__ns.UI.search:SetText("")')
check('nothing went wrong', not A.ev('__errors'))

print('Rested XP checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

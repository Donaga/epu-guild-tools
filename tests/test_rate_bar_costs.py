"""Rate bar: deaths and repairs, quest XP vs kill XP, profession skill-ups.

Chris asked for three more stats on the rate bar (/epu bar): what a session
costs in deaths and repairs, whether questing or killing gives the XP, and
profession skill-ups per hour. All three are off until picked in the bar's
settings, and they follow the Session tab's Pause and Reset like the rest.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(2)

A.ex('''
__xp, __xpMax, __level = 1000, 50000, 20
UnitXP = function() return __xp end
UnitXPMax = function() return __xpMax end
UnitLevel = function() return __level end
GetMaxPlayerLevel = function() return 60 end
GetXPExhaustion = function() return 0 end
time = function() return math.floor(__now) end
__repairCursor = false
InRepairMode = function() return __repairCursor end
__feign = false
UnitIsFeignDeath = function() return __feign end
__money = 1000000
function __bar() return _G.EPUGuildRateBar end
function __barText()
  local b, t = __bar(), {}
  if not b then return "" end
  for _, fs in ipairs(b.cells) do if fs:IsShown() then t[#t + 1] = fs:GetText() end end
  return table.concat(t, " | ")
end
function __tip(id)
  for _, e in ipairs(__ns.RateBar.Visible()) do if e[1].id == id then return e[3] end end
  return ""
end
function __cfgButton(action)
  for _, w in ipairs(EPUGuildRateBarConfig.pool.used) do
    if w.epuAction == action and w:IsShown() then return w end
  end
end
function __cfgClick(action) local b = __cfgButton(action); b:GetScript("OnClick")(b) end
function __gainXP(n) __xp = __xp + n; __fire("PLAYER_XP_UPDATE", "player") end
function __spend(n) __money = __money - n; __fire("PLAYER_MONEY") end
function __sessionText()
  __ns.OpenPersonalTrackers("session")
  local t = {}
  for _, w in ipairs(EPUGuildPersonalTrackers.pool.used) do
    if w:IsShown() and w.GetText and w:GetText() then t[#t + 1] = w:GetText() end
  end
  return table.concat(t, "\\n")
end
''')

def bar():
    A.ex('__ns.RateBar.Layout()')
    return A.ev('__barText()') or ''

def tip(stat):
    return A.ev('__tip("%s")' % stat) or ''

A.ex('__fire("PLAYER_MONEY"); SlashCmdList.EPUGUILD("bar reset"); SlashCmdList.EPUGUILD("bar show")')
t = bar()
check('the three new stats are off by default',
      'Deaths' not in t and 'Quest/Kill' not in t and 'Skill-ups' not in t)

# --- Picking them ---
A.ex('SlashCmdList.EPUGUILD("bar settings")')
for action, name in [('stat:deaths', 'Deaths and repairs'), ('stat:xpsplit', 'Quest XP vs kill XP'),
                     ('stat:skillhr', 'Profession skill-ups/hr')]:
    check(f'the settings list "{name}"', A.ev(f'__cfgButton("{action}") ~= nil')
          and name in A.ev(f'__cfgButton("{action}"):GetText()'))
check('the settings window grows to fit the longer stat list', A.ev('EPUGuildRateBarConfig:GetHeight()') > 440)
A.ex('__cfgClick("stat:deaths"); __cfgClick("stat:xpsplit"); __cfgClick("stat:skillhr"); __cfgClick("stat:nethr")')
t = bar()
check('a ticked stat shows on the bar', 'Deaths' in t and 'Quest/Kill XP' in t and 'Skill-ups/hr' in t)
check('the picks are saved', all(A.ev(f'__ns.db.rateBar.stats.{k}') is True for k in ['deaths', 'xpsplit', 'skillhr']))

# --- Deaths ---
A.ex('__fire("PLAYER_DEAD"); __fire("PLAYER_DEAD")')
check('each death counts', 'Deaths|r 2 ' in bar())
A.ex('__feign = true; __fire("PLAYER_DEAD"); __feign = false')
check('feigning death is not a death', 'Deaths|r 2 ' in bar())

# --- Repairs ---
A.ex('__repairCost = 5000; RepairAllItems(false); __spend(5000); __repairCost = 0')
check('repairing everything counts what it cost', 'Repairs|r 50s 0c' in bar())
check('net gold per hour already includes the repair', 'repairs of 50s 0c included' in tip('nethr'))
A.ex('__spend(1200)')
check('buying something at a vendor is not a repair', 'Repairs|r 50s 0c' in bar())
A.ex('__repairCursor = true; __spend(37); __repairCursor = false')
check('a single item repaired with the repair cursor counts', 'Repairs|r 50s 37c' in bar())
A.ex('__repairCost = 3000; RepairAllItems(false); __repairCost = 0; __advance(10); __spend(3000)')
check('gold spent long after a repair is not counted as one', 'Repairs|r 50s 37c' in bar())
A.ex('__repairCost = 20000; RepairAllItems(true); __repairCost = 0')
check('a repair the guild bank pays is not your cost', 'Repairs|r 50s 37c' in bar())
check('but the tooltip says the guild bank paid it', 'guild bank paid 2g 0s' in tip('deaths'))
check('the tooltip counts deaths', tip('deaths').startswith('2 deaths this session'))
A.ex('__fire("CHAT_MSG_MONEY", "You loot 3 Gold")')
check('gold per hour from loot also says what it comes to after repairs', 'after repairs' in tip('goldhr'))

# --- Quest XP vs kill XP ---
A.ex('''__gainXP(250); __fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 250 experience.")
__gainXP(1000); __fire("QUEST_TURNED_IN", 101, 1000, 0); __fire("CHAT_MSG_SYSTEM", "Experience gained: 1000.")
__gainXP(250); __fire("CHAT_MSG_SYSTEM", "Discovered Goldshire: 250 experience gained")''')
check('quest and kill XP show as shares of the session XP', 'Quest/Kill XP|r 67% / 17%' in bar())
check('the tooltip gives the XP from each and what is left over',
      'From kills: 250 (17%)' in tip('xpsplit') and 'XP from quests: 1,000 (67%)' in tip('xpsplit')
      and 'Other, such as exploring: 250' in tip('xpsplit'))
A.ex('''__gainXP(600); __fire("CHAT_MSG_SYSTEM", "Experience gained: 600.")
__advance(1)
__gainXP(400); __fire("QUEST_TURNED_IN", 102, 400, 0); __fire("CHAT_MSG_SYSTEM", "Experience gained: 400.")
__gainXP(400); __fire("CHAT_MSG_SYSTEM", "Experience gained: 400."); __fire("QUEST_TURNED_IN", 103, 400, 0)''')
check('quest XP counts once whether the event or the chat line comes first, or only one of them',
      'XP from quests: 2,400' in tip('xpsplit'))

# --- Profession skill-ups ---
A.ex('''__fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 74.")
__fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 75.")
__fire("CHAT_MSG_SKILL", "Your skill in First Aid has increased to 101.")
__fire("CHAT_MSG_SKILL", "Your skill in Swords has increased to 40.")
__fire("CHAT_MSG_SKILL", "Your skill in Defense has increased to 99.")''')
check('profession skill-ups count, weapon skills and Defense do not', '3 this session' in tip('skillhr'))
check('the tooltip lists each profession with its new skill', 'Mining +2 (now 75)' in tip('skillhr') and 'First Aid +1 (now 101)' in tip('skillhr'))
A.ex('''local orig = GetSkillLineInfo
local lines = { { "Professions", true }, { "Woodcarving", false }, { "Weapon Skills", true }, { "Staves", false } }
GetNumSkillLines = function() return #lines end
GetSkillLineInfo = function(i) return unpack(lines[i]) end
__fire("CHAT_MSG_SKILL", "Your skill in Woodcarving has increased to 5.")
__fire("CHAT_MSG_SKILL", "Your skill in Staves has increased to 5.")''')
check('a profession the list does not know counts when it sits under Professions', 'Woodcarving +1' in tip('skillhr') and 'Staves' not in tip('skillhr'))
A.ex('__fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 78.")')
check('a jump of several points counts them all', 'Mining +5 (now 78)' in tip('skillhr'))
A.ex('__now = __now + 1800')
check('skill-ups per hour use the session time', 'Skill-ups/hr|r 14' in bar())

# --- Session tab ---
s = A.ev('__sessionText()') or ''
check('the Session tab shows deaths and repairs', 'Deaths: |cffff6b6b2|r' in s and 'Repairs you paid: |cffffd10050s 37c|r' in s
      and 'Guild bank paid: |cffffd1002g 0s|r' in s)
check('the Session tab shows the quest and kill XP split', 'XP from quests: |cff4fc3f72400|r' in s and 'from kills: |cff4fc3f7250|r' in s)
check('the Session tab shows skill-ups by profession', 'Profession skill-ups: |cff4ade807|r' in s and 'Mining +5 (now 78)' in s)
check('the Session tab shows loot after repairs', 'After repairs:' in s)

# --- Pause and reset ---
A.ex('''SlashCmdList.EPUGUILD("bar pause")
__fire("PLAYER_DEAD")
__repairCost = 4000; RepairAllItems(false); __spend(4000); __repairCost = 0
__gainXP(300); __fire("QUEST_TURNED_IN", 104, 300, 0)
__fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 79.")''')
check('a paused session counts no deaths or repairs', 'Deaths|r 2 |cffa3b0c2Repairs|r 50s 37c' in bar())
check('or quest XP', 'XP from quests: 2,400' in tip('xpsplit'))
check('or skill-ups', '7 this session' in tip('skillhr'))
A.ex('SlashCmdList.EPUGUILD("bar resume"); __fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 80.")')
check('after resuming, a skill-up counts one point, not the paused one too', 'Mining +6 (now 80)' in tip('skillhr'))
A.ex('SlashCmdList.EPUGUILD("bar reset")')
t = bar()
check('reset clears deaths and repairs', 'Deaths|r 0 |cffa3b0c2Repairs|r 0c' in t)
check('reset clears the XP split', 'Quest/Kill XP|r --' in t)
check('reset clears skill-ups', 'Skill-ups/hr|r 0' in t and '0 this session' in tip('skillhr'))

# --- Max level ---
A.ex('__level = 60')
t = bar()
check('the XP split hides on a max-level character', 'Quest/Kill' not in t)
check('deaths and skill-ups still show at max level', 'Deaths' in t and 'Skill-ups/hr' in t)
A.ex('__level = 20')

# --- Saved settings from 0.36/0.37 ---
A.ex('__ns.db.rateBar.stats = { xphr = false, kills = true }; __ns.RateBar.Layout()')
check('older saved stat picks keep working', A.ev('__ns.db.rateBar.stats.kills') is True and A.ev('__ns.db.rateBar.stats.xphr') is False)
check('and the new stats start off for them', all(A.ev(f'__ns.db.rateBar.stats.{k}') is False for k in ['deaths', 'xpsplit', 'skillhr']))

# --- Entry point ---
A.ex('''function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end
__ns.UI:Show(); __ns.UI.nav.membertools:Click(); __ns.UI.search:SetText("skill-ups")''')
check('searching member tools for skill-ups finds the rate bar', 'ratebar' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__ns.UI.search:SetText("repairs")')
check('and so does repairs', 'ratebar' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__ns.UI.search:SetText("")')

check('nothing went wrong', not A.ev('__errors'))
print('Rate bar cost checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

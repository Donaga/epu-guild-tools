"""Rate bar (/epu bar): a small movable strip with the session's live rates.

Chris wanted the trackers as a small toolbar instead of a pop-up, to watch
XP per hour and the like while playing, with the stats he picks and a size he
sets. The bar reads the farming session from Personal trackers, so Pause and
Reset there act on the bar too.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(2)

A.ex('''
__xp, __xpMax, __level, __rested = 1000, 5000, 20, 0
UnitXP = function() return __xp end
UnitXPMax = function() return __xpMax end
UnitLevel = function() return __level end
GetMaxPlayerLevel = function() return 60 end
GetXPExhaustion = function() return __rested end
-- the session clock follows the test clock
time = function() return math.floor(__now) end
function __bar() return _G.EPUGuildRateBar end
function __barText()
  local b, t = __bar(), {}
  if not b then return "" end
  for _, fs in ipairs(b.cells) do if fs:IsShown() then t[#t + 1] = fs:GetText() end end
  return table.concat(t, " | ")
end
function __cfgButton(action)
  for _, w in ipairs(EPUGuildRateBarConfig.pool.used) do
    if w.epuAction == action and w:IsShown() then return w end
  end
  error("Missing rate bar button " .. action)
end
function __cfgClick(action) local b = __cfgButton(action); b:GetScript("OnClick")(b) end
function __gainXP(n)
  __xp = __xp + n
  if __xp >= __xpMax then __xp = __xp - __xpMax; __xpMax = __xpMax + 1000; __level = __level + 1 end
  __fire("PLAYER_XP_UPDATE", "player")
end
''')

def bar_text():
    return A.ev('__barText()') or ''

check('the bar is not shown until you turn it on', A.ev('__bar() == nil or not __bar():IsShown()'))

# --- Turning it on ---
A.ex('SlashCmdList.EPUGUILD("bar reset"); SlashCmdList.EPUGUILD("bar")')
check('/epu bar shows the bar', A.ev('__bar():IsShown()'))
check('the bar remembers it is shown on this character', A.ev('__ns.cdb.rateBar.shown') is True)
t = bar_text()
check('by default the bar shows XP per hour, time to level, gold per hour and session time',
      all(x in t for x in ['XP/hr', 'Level in', 'Gold/hr', 'Session']))
check('stats you did not pick stay off by default', 'Kills/hr' not in t and 'Honor/hr' not in t)
check('time to level waits for some XP before guessing', 'Level in|r --' in t)

# --- Rates ---
A.ex('__gainXP(2000); __gainXP(3000)')   # 1000 + 5000 crosses into level 21
XP_TIP = '(function() for _, e in ipairs(__ns.RateBar.Visible()) do if e[1].id == "xphr" then return e[3] end end return "" end)()'
check('a level up counts what was left of the old level plus the new XP', '(5,000 this session)' in (A.ev(XP_TIP) or ''))
A.ex('__now = __now + 1800; __ns.RateBar.Layout()')
t = bar_text()
check('5,000 XP in half an hour shows as 10.0k XP an hour', 'XP/hr|r 10.0k' in t)
# level 21: 1000 of 6000, 5000 to go at 10,000 an hour = 30 minutes
check('time to level uses the XP left and the current rate', 'Level in|r 30m' in t)
check('session time shows on the bar', 'Session|r 30m' in t)

A.ex('''__fire("CHAT_MSG_MONEY", "You loot 2 Gold 50 Silver")
__fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 250 experience.")
__fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 250 experience.")
__fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 400 experience.")
__ns.RateBar.Layout()''')
check('looted gold counts toward gold per hour', 'Gold/hr|r 5g 0s' in bar_text())

# --- Picking stats in the settings ---
A.ex('SlashCmdList.EPUGUILD("bar settings")')
check('/epu bar settings opens the rate bar settings', A.ev('EPUGuildRateBarConfig:IsShown()'))
A.ex('__cfgClick("stat:kills"); __cfgClick("stat:killsleft"); __cfgClick("stat:xphr")')
t = bar_text()
check('a stat you tick appears on the bar', 'Kills/hr|r 4' in t)
check('kills to level uses the XP each kill gave', 'Kills to lvl|r 20' in t)
check('a stat you untick leaves the bar', 'XP/hr' not in t)
check('quest XP ("You gain 400 experience") is not a kill', A.ev('(function() for _, e in ipairs(__ns.RateBar.Visible()) do if e[1].id == "kills" then return e[3] end end return "" end)()').find('(2 this session') >= 0)
check('the settings button shows the tick', A.ev('__cfgButton("stat:kills"):GetText()').startswith('[x]'))
check('the stat choice is saved', A.ev('__ns.db.rateBar.stats.kills') is True and A.ev('__ns.db.rateBar.stats.xphr') is False)
A.ex('__cfgClick("stat:xphr")')

# --- Size ---
A.ex('__cfgClick("bigger"); __cfgClick("bigger")')
check('Bigger makes the bar bigger in steps', abs(A.ev('__ns.db.rateBar.scale') - 1.2) < 1e-9)
check('the settings show the size', A.ev('__cfgButton("size"):GetText()') == 'Size: 120%')
A.ex('__cfgClick("smaller")')
check('Smaller makes it smaller', abs(A.ev('__ns.db.rateBar.scale') - 1.1) < 1e-9)
A.ex('SlashCmdList.EPUGUILD("bar scale 1.5")')
check('/epu bar scale sets the size', abs(A.ev('__ns.db.rateBar.scale') - 1.5) < 1e-9)
A.ex('SlashCmdList.EPUGUILD("bar scale 9")')
check('the size stops at twice normal', abs(A.ev('__ns.db.rateBar.scale') - 2.0) < 1e-9)
A.ex('SlashCmdList.EPUGUILD("bar scale 0.1")')
check('and at 60% the other way', abs(A.ev('__ns.db.rateBar.scale') - 0.6) < 1e-9)
A.ex('__log = {}; SlashCmdList.EPUGUILD("bar scale big")')
check('a size that is not a number explains the command', any('Usage: /epu bar scale' in str(m) for m in A.ev('__log').values()))
A.ex('SlashCmdList.EPUGUILD("bar scale 1")')

# --- Layout ---
A.ex('__cfgClick("layout")')
check('the bar can stack its stats', A.ev('__ns.db.rateBar.layout') == 'stacked' and 'Gold/hr' in bar_text())
check('a stacked bar is taller than one row', A.ev('__bar():GetHeight()') > 30)
A.ex('__cfgClick("layout")')
check('and go back to one row', A.ev('__ns.db.rateBar.layout') == 'across' and A.ev('__bar():GetHeight()') == 22)
A.ex('__cfgClick("background")')
check('the background can be made see-through', A.ev('__ns.db.rateBar.bgAlpha') < 0.85)

# --- Moving, locking and clicking ---
A.ex('''local b = __bar()
b.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 140, -60 end
b:GetScript("OnMouseDown")(b, "LeftButton")
b:GetScript("OnDragStart")(b)
b:GetScript("OnDragStop")(b)
EPUGuildPersonalTrackers = EPUGuildPersonalTrackers
if EPUGuildPersonalTrackers then EPUGuildPersonalTrackers:Hide() end
b:GetScript("OnMouseUp")(b, "LeftButton")''')
check('dragging the bar saves where it sits for this character',
      A.ev('__ns.cdb.rateBar.point') == 'TOPLEFT' and A.ev('__ns.cdb.rateBar.x') == 140 and A.ev('__ns.cdb.rateBar.y') == -60)
check('letting go after a drag does not open the details', A.ev('EPUGuildPersonalTrackers == nil or not EPUGuildPersonalTrackers:IsShown()'))
A.ex('local b = __bar(); b:GetScript("OnMouseDown")(b, "LeftButton"); b:GetScript("OnMouseUp")(b, "LeftButton")')
check('a left-click opens the session details', A.ev('EPUGuildPersonalTrackers:IsShown()'))
A.ex('EPUGuildRateBarConfig:Hide(); local b = __bar(); b:GetScript("OnMouseDown")(b, "RightButton"); b:GetScript("OnMouseUp")(b, "RightButton")')
check('a right-click opens the rate bar settings', A.ev('EPUGuildRateBarConfig:IsShown()'))

A.ex('SlashCmdList.EPUGUILD("bar lock"); __moved = false; local b = __bar(); b.StartMoving = function() __moved = true end; b:GetScript("OnDragStart")(b)')
check('a locked bar does not move', A.ev('__moved') is False and A.ev('__ns.db.rateBar.locked') is True)
A.ex('SlashCmdList.EPUGUILD("bar unlock"); local b = __bar(); b:GetScript("OnDragStart")(b); b:GetScript("OnDragStop")(b)')
check('an unlocked bar moves again', A.ev('__moved') is True)

A.ex('__cfgClick("resetpos")')
check('Put it back forgets the saved spot', A.ev('__ns.cdb.rateBar.point') is None)

# --- Shown again after logging in ---
A.ex('__bar():Hide(); __fire("PLAYER_LOGIN")')
check('the bar comes back at login on a character that had it shown', A.ev('__bar():IsShown()'))
A.ex('SlashCmdList.EPUGUILD("bar hide"); __fire("PLAYER_LOGIN")')
check('and stays hidden on one that turned it off', A.ev('__bar():IsShown()') is False)
A.ex('SlashCmdList.EPUGUILD("bar show")')

# --- Session pause and reset ---
A.ex('SlashCmdList.EPUGUILD("bar pause"); __ns.RateBar.Layout()')
check('a paused session says so on the bar', '(paused)' in bar_text())
A.ex('__gainXP(500); __now = __now + 600; __ns.RateBar.Layout()')
check('XP while paused is not counted', '(5,000 this session)' in (A.ev(XP_TIP) or ''))
A.ex('SlashCmdList.EPUGUILD("bar resume"); __gainXP(100)')
check('resuming counts only XP gained after it', '(5,100 this session)' in (A.ev(XP_TIP) or ''))
A.ex('SlashCmdList.EPUGUILD("bar reset"); __ns.RateBar.Layout()')
check('reset starts the session over', 'XP/hr|r 0' in bar_text() and 'Gold/hr|r 0c' in bar_text())

# --- Max level ---
A.ex('__level = 60; __ns.RateBar.Layout()')
t = bar_text()
check('XP stats hide on a max-level character', 'XP/hr' not in t and 'Level in' not in t and 'Kills to lvl' not in t)
check('gold and kills still show at max level', 'Gold/hr' in t and 'Kills/hr' in t)
A.ex('for k in pairs(__ns.db.rateBar.stats) do __ns.db.rateBar.stats[k] = false end; __ns.RateBar.Layout()')
check('with nothing picked the bar says how to pick stats', 'right-click' in bar_text())
A.ex('__level = 20; __ns.db.rateBar.stats = {}; __ns.RateBar.Layout()')

# --- Redraws reuse their font strings ---
A.ex('''__made = 0
local M = getmetatable(UIParent)
local fs = M.CreateFontString
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end''')
for _ in range(30):
    A.ex('__ns.RateBar.Layout()')
check('redrawing the bar every second makes nothing new', A.ev('__made') == 0)

# --- Entry points ---
A.ex('''function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end
function __clickRow(key) for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key==key then r:GetScript("OnClick")(r); return true end end error("Missing row "..key) end''')
A.ex('SlashCmdList.EPUGUILD("bar hide"); EPUGuildRateBarConfig:Hide(); __ns.UI:Show(); __ns.UI.nav.membertools:Click()')
check('Member tools has a Rate bar tile', 'ratebar' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__clickRow("ratebar")')
check('the Rate bar tile shows the bar', A.ev('__bar():IsShown()'))
check('the Rate bar tile opens its settings', A.ev('EPUGuildRateBarConfig:IsShown()'))
A.ex('__ns.UI.search:SetText("xp per hour")')
check('searching member tools for XP per hour finds the rate bar', 'ratebar' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__ns.UI.search:SetText("")')

A.ex('''__ns.OpenPersonalTrackers("session")
function __trackerButton(label)
  for _, w in ipairs(EPUGuildPersonalTrackers.pool.used) do
    if w.GetText and w:IsShown() and w:GetText() == label then return w end
  end
end''')
check('the Session tab offers to hide the rate bar while it shows', A.ev('__trackerButton("Hide rate bar") ~= nil'))
A.ex('local b = __trackerButton("Hide rate bar"); b:GetScript("OnClick")(b)')
check('and hides it', A.ev('__bar():IsShown()') is False and A.ev('__trackerButton("Show rate bar") ~= nil'))
check('the Session tab links to the rate bar settings', A.ev('__trackerButton("Rate bar settings") ~= nil'))
check('/epu help lists the rate bar', A.ev('(function() __log = {}; SlashCmdList.EPUGUILD("help"); for _, m in ipairs(__log) do if m:find("/epu bar", 1, true) then return true end end return false end)()'))

check('nothing went wrong', not A.ev('__errors'))
print('Rate bar checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

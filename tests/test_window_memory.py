"""Windows that redraw themselves don't grow over a long session.

The game never frees a frame, font string or texture. In 0.29.0 to 0.31.1 the gold
tracker, info bar and travel settings, the chat settings pop-up, the zone
guide, the leveling tools and the needed mats window made new ones on every
refresh (the gold tracker up to 90 textures for its pie each time gold
changed), so memory grew for as long as you played. They now reuse what the
last refresh made. Each window here is redrawn many times; after the first
draw, nothing new may be made.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(60)

# Count every frame, font string and texture the addon makes from now on.
A.ex('''
__made = 0
local M = getmetatable(UIParent)
local fs, tex = M.CreateFontString, M.CreateTexture
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end
M.CreateTexture = function(...) __made = __made + 1; return tex(...) end
local cf = CreateFrame
CreateFrame = function(...) __made = __made + 1; return cf(...) end
''')


def growth(open_code, redraw_code, times=25):
    """Widgets made by redraws after the first two (first draw, then one to settle)."""
    A.ex(open_code)
    A.ex(redraw_code)
    before = A.ev('__made')
    for _ in range(times):
        A.ex(redraw_code)
    return A.ev('__made') - before


# Gold tracker with spending in several categories, so the pie, bars and
# trend chart all draw. Gold changing while it's open redraws it.
A.ex('''__ns.db.goldTracker = nil; __fire("PLAYER_LOGIN")
local db = __ns.db.goldTracker or {}
__money = 1000000; __fire("PLAYER_LOGIN")''')
A.ex('__ns.OpenGoldTracker()')
A.ex('''local e = __ns.db.goldTracker.entries
for i = 1, 40 do
  local cats = {"vendor","repair","auction","mail","training","flight","trade","loot"}
  e[#e+1] = {t = time() - i * 60, who = __ns.me, realm = "Forever", delta = (i % 3 == 0) and 5000 or -2500 * i, cat = cats[i % #cats + 1]}
end''')
check('the gold tracker redraws without making new widgets',
      growth('__ns.OpenGoldTracker()', 'EPUGuildGoldTracker:Refresh()') == 0)
check('gold changing while the tracker is open makes nothing new',
      growth('', '__money = __money - 1234; __fire("PLAYER_MONEY")') == 0)
check('the tracker still shows its pie chart',
      A.ev('(function() for _,w in ipairs(EPUGuildGoldTracker.pool.used) do if w.epuPoolKind=="frame:pie" then return true end end end)()') is True)
A.ex('EPUGuildGoldTracker:Hide()')

check('info bar settings redraw without making new widgets',
      growth('__ns.OpenInfoBarsSettings()', 'EPUGuildInfoBarsConfig:Refresh()') == 0)
A.ex('EPUGuildInfoBarsConfig:Hide()')

check('travel and vendor settings redraw without making new widgets',
      growth('__ns.OpenWorldQoLSettings()', 'EPUGuildWorldQoLConfig:Refresh()') == 0)
A.ex('EPUGuildWorldQoLConfig:Hide()')

check('the chat settings pop-up redraws without making new widgets',
      growth('__ns.OpenPopoutChatSettings()', 'EPUGuildChatOptsPopup:Refresh()') == 0)
A.ex('EPUGuildChatOptsPopup:Hide()')

check('the zone guide redraws without making new widgets',
      growth('__ns.OpenZoneGuide()', '__ns.RefreshZoneGuideContent()') == 0)
A.ex('EPUGuildZoneGuideWindow:Hide()')

tabs = ['advisor', 'dungeons', 'writs', 'camping', 'gear', 'runs', 'raid']
cycle = '; '.join(f'__ns.OpenLevelingTools("{t}")' for t in tabs)
check('switching leveling tool tabs over and over makes nothing new', growth(cycle, cycle, times=8) == 0)
A.ex('EPUGuildLevelingWindow:Hide()')

check('the needed mats window redraws without making new widgets',
      growth('__ns.ShowNeededMats()', 'EPUGuildNeededMats:Refresh()') == 0)

# A pool hands back what it made, in the state a fresh widget would be in.
A.ex('''
__p = __ns.NewWidgetPool(UIParent)
local b = __p:Button("First", 80, 22, "accent")
b.tip = "old tip"; b:SetScript("OnClick", function() end); b:SetEnabled(false)
local f = __p:Font(12, {1, 0, 0})
f:SetText("old")
__p:ReleaseAll()
__b2 = __p:Button("Second", 60, 20)
__f2 = __p:Font(12, {0, 1, 0})
__same = (__b2 == b) and (__f2 == f)
''')
check('a released button and font string are handed out again', A.ev('__same') is True)
check('a reused button starts clean', A.ev('__b2:GetText() == "Second" and __b2.tip == nil and __b2:GetScript("OnClick") == nil and __b2:IsEnabled() and __b2.style == nil'))
check('a reused font string starts empty', A.ev('__f2:GetText() == ""'))
check('released widgets are hidden until handed out', A.ev('(function() __p:ReleaseAll(); return not __b2:IsShown() end)()'))
check('nothing went wrong drawing the windows', not A.ev('__errors'))

print('Window memory checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

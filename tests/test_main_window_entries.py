"""Every pop-up tool opens from the main window, not only by slash command.

Member tools has tiles for the Zone guide, Leveling and dungeons, and Gold and
budget. Settings has rows for pop-out chat and log windows, Info bars, and
Travel, vendor and tooltips. Each one opens the same window as its /epu command.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(60)
A.ex('''function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end
function __clickRow(key) for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key==key then r:GetScript("OnClick")(r); return true end end error("Missing row "..key) end
function __shown(name) local f=_G[name]; return f~=nil and f:IsShown() end
function __hide(name) local f=_G[name]; if f then f:Hide() end end''')


def keys():
    return (A.ev('__rowKeys()') or '').split(',')


# --- Member tools tiles ---
A.ex('__ns.UI:Show(); __ns.UI.nav.membertools:Click()')
k = keys()
check('member tools keeps its first four tiles in order', k[:4] == ['guides', 'quests', 'catchup', 'notifications'])
check('member tools lists the zone guide, leveling tools and gold tracker',
      all(x in k for x in ['zoneguide', 'leveling', 'gold']))

for key, window, label in [('zoneguide', 'EPUGuildZoneGuideWindow', 'Zone guide'),
                           ('leveling', 'EPUGuildLevelingWindow', 'Leveling and dungeons'),
                           ('gold', 'EPUGuildGoldTracker', 'Gold and budget')]:
    A.ex(f'__hide("{window}"); __ns.UI.nav.membertools:Click(); __clickRow("{key}")')
    check(f'{label} tile opens its window', A.ev(f'__shown("{window}")'))
    check(f'{label} tile leaves the main window open', A.ev('__ns.UI:IsShown()'))
    A.ex(f'__hide("{window}")')

A.ex('__ns.UI.nav.membertools:Click(); __ns.UI.search:SetText("camping")')
check('searching member tools for a leveling tab finds the leveling tile', keys() == ['leveling'])
A.ex('__ns.UI.search:SetText("budget")')
check('searching member tools for budget finds the gold tile', keys() == ['gold'])
A.ex('__ns.UI.search:SetText("")')

A.ex('__saved=__ns.OpenGoldTracker; __ns.OpenGoldTracker=nil; __ns.UI.nav.membertools:Click()')
check('a tile hides itself when its tool is not loaded', 'gold' not in keys())
A.ex('__ns.OpenGoldTracker=__saved; __ns.UI.nav.membertools:Click()')
check('the tile comes back when the tool is loaded', 'gold' in keys())

if A.ev('__ns.OpenPersonalTrackers ~= nil'):
    # Personal Trackers (/epu trackers) is in the addon: the real window opens
    A.ex('__hide("EPUGuildPersonalTrackers"); __ns.UI.nav.membertools:Click(); __clickRow("trackers")')
    check('Personal trackers tile opens the trackers window', A.ev('__shown("EPUGuildPersonalTrackers")'))
    A.ex('__hide("EPUGuildPersonalTrackers")')
else:
    check('Personal trackers tile stays hidden while that tool is not in the addon', 'trackers' not in keys())
    A.ex('__opened=nil; __ns.OpenPersonalTrackers=function(tab) __opened=tab or "default" end; __ns.UI.nav.membertools:Click()')
    check('Personal trackers tile appears once the tool is loaded', 'trackers' in keys())
    A.ex('__clickRow("trackers")')
    check('Personal trackers tile opens the trackers window', A.ev('__opened') == 'default')
    A.ex('__ns.OpenPersonalTrackers=nil')

# --- Settings rows ---
A.ex('__ns.UI:SetView("settings")')
k = keys()
check('settings lists log windows, info bars and travel helpers',
      all(x in k for x in ['logs', 'infobars', 'qol']))
check('settings keeps notifications first and the minimap button last', k[0] == 'notifications' and k[-1] == 'minimap')

for key, window, label in [('logs', 'EPUGuildChatOptsPopup', 'Pop-out chat and log windows'),
                           ('infobars', 'EPUGuildInfoBarsConfig', 'Info bars'),
                           ('qol', 'EPUGuildWorldQoLConfig', 'Travel, vendor and tooltips')]:
    A.ex(f'__hide("{window}"); __ns.UI:SetView("settings"); __clickRow("{key}")')
    check(f'{label} row opens its window', A.ev(f'__shown("{window}")'))
    A.ex(f'__hide("{window}")')

A.ex('__ns.UI:SetView("settings"); __ns.UI.search:SetText("waypoint")')
check('searching settings for waypoints finds the travel row', keys() == ['qol'])
A.ex('__ns.UI.search:SetText("")')

# --- the slash commands still open the same windows ---
for cmd, window in [('zone', 'EPUGuildZoneGuideWindow'), ('leveling', 'EPUGuildLevelingWindow'),
                    ('gold', 'EPUGuildGoldTracker'), ('logs', 'EPUGuildChatOptsPopup'),
                    ('bars', 'EPUGuildInfoBarsConfig'), ('qol', 'EPUGuildWorldQoLConfig')]:
    A.ex(f'__hide("{window}"); SlashCmdList.EPUGUILD("{cmd}")')
    check(f'/epu {cmd} still opens the same window', A.ev(f'__shown("{window}")'))
    A.ex(f'__hide("{window}")')

check('no runtime errors', A.ev('__errors') in (None, 0))
print('Main window entry tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

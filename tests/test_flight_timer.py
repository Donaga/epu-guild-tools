"""Flight timer: route times keyed by flight master, learned from every
flight, filled in from other flight timer addons, and a restyled bar.

0.38.0 keyed routes by the subzone you took off from, which can split one
route into several, only learned while the bar was on, and had it on for
everyone. The bar is now off for new installs, learning runs either way,
and times from InFlight-style addons fill in routes you haven't flown.
"""
from simcore import *
clients['Tyler Baker'] = Client('Tyler Baker')
tick(5)
T = clients['Tyler Baker']

# A flight master in Ironforge with three places to go, like the game's taxi API.
T.ex('''
__nodes = {
  { "Ironforge, Dun Morogh", "CURRENT", 0.51, 0.62 },
  { "Thelsamar, Loch Modan", "REACHABLE", 0.58, 0.60 },
  { "Menethil Harbor, Wetlands", "REACHABLE", 0.47, 0.50 },
  { "Stormwind, Elwynn", "REACHABLE", 0.43, 0.80 },
  { "Lakeshire, Redridge", "REACHABLE", 0.50, 0.82 },
}
function NumTaxiNodes() return #__nodes end
function TaxiNodeName(i) return __nodes[i] and __nodes[i][1] end
function TaxiNodeGetType(i) return __nodes[i] and __nodes[i][2] end
function TaxiNodePosition(i) return __nodes[i][3], __nodes[i][4] end
-- Lakeshire goes by way of Stormwind.
function GetNumRoutes(i) if i == 5 then return 2 end return 1 end
function TaxiGetNodeSlot(i, hop, src) if i == 5 then return hop == 1 and 4 or 5 end return i end
function UnitFactionGroup() return "Alliance" end
function GetMinimapZoneText() return "The Commons" end
__zone = "The Commons"
function __fly(slot, secs)
  TakeTaxiNode(slot); __advance(0.5)
  local tick = __trackTick()
  tick(); __onTaxi = true; tick(); __advance(secs); __onTaxi = false; tick()
end
''')
T.ex('''function __trackTick()
  -- the tracker frame is the last one created before the hook ran; find the one with an OnUpdate
  for i = #__frames, 1, -1 do
    local f = __frames[i]
    if f._scripts.OnUpdate and f ~= EPUGuildFlightTimer then return function() f._scripts.OnUpdate(f, 0.25) end end
  end
end''')

db = '__ns.db.worldQoL'
check('the bar is off for a new install', T.ev(db + '.flightTimer') is False)
T.ex('__fly(2, 42)')
check('with the bar off, no bar appears', T.ev('EPUGuildFlightTimer == nil or not EPUGuildFlightTimer:IsShown()'))
check('with the bar off, the route time is still learned, keyed by flight master',
      T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Thelsamar, Loch Modan"].t') == 42)

T.ex('__fly(2, 46)')
check('a second flight averages in', T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Thelsamar, Loch Modan"].t') == 44)
T.ex('__fly(2, 12)')
check('a flight far off the average is set aside', T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Thelsamar, Loch Modan"].t') == 44)
T.ex('__fly(2, 44)')
check('and the average carries on after it', T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Thelsamar, Loch Modan"].n') == 3)

# 0.38.0's saved time for this flight master (subzone key) is taken over.
T.ex(db + '.flightTimes["The Commons->Menethil Harbor, Wetlands"] = 120')
r = T.ev('(function() local r = __ns.FlightRouteTime({name="Ironforge, Dun Morogh"}, {name="Menethil Harbor, Wetlands"}) return r and r.t end)()')
check('a time saved by 0.38.0 carries over', r == 120)

# Other flight timer addons: names, node ids and the Classic position hash.
T.ex('''
InFlightDB = { global = { Alliance = { ["Ironforge, Dun Morogh"] = { ["Stormwind, Elwynn"] = 213 } },
  Horde = { ["Ironforge, Dun Morogh"] = { ["Lakeshire, Redridge"] = 999 } } },
  profiles = { Default = { barWidth = 300, fontSize = 12 } } }
-- Unrelated saved data keyed by small numbers must not be read as routes.
SomeOtherAddonDB = { [1] = { [4] = 77 } }
__ns.db.worldQoL.flightRoutes["Ironforge, Dun Morogh->Stormwind, Elwynn"] = nil
''')
T.ex('__fire("TAXIMAP_OPENED")')
r = T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Stormwind, Elwynn"]')
check('opening the flight map fills a route from InFlight', r is not None and r.t == 213 and r.src == 'InFlight')
check("the other faction's times are skipped", T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Lakeshire, Redridge"]') is None)

T.ex('''FTCData = { Alliance = { ["51000000"] = { ["50000000"] = 260 } } }''')
T.ex('__ns.FlightTimeSources()')  # cached for two minutes; force a fresh look
T.ex('__advance(130); __fire("TAXIMAP_OPENED")')
r = T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Lakeshire, Redridge"]')
check('a route from a position-hash timer is filled in', r is not None and r.t == 260)

T.ex('''EllesmereUIDB = { profiles = { Default = { travel = { flightTimes = { [11] = { [12] = 150 } } } } } }
function C_TaxiMap_GetAll() end
C_TaxiMap = { GetAllTaxiNodes = function() return { {slotIndex=1,nodeID=11}, {slotIndex=3,nodeID=12} } end }
function GetTaxiMapID() return 1415 end
__ns.db.worldQoL.flightRoutes["Ironforge, Dun Morogh->Menethil Harbor, Wetlands"] = nil
__ns.db.worldQoL.flightTimes = {}''')
T.ex('__advance(130); __fire("TAXIMAP_OPENED")')
r = T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Menethil Harbor, Wetlands"]')
check('EllesmereUI travel times keyed by node id are read', r is not None and r.t == 150 and r.src == 'EllesmereUI')
srcs = T.ev('table.concat(__ns.FlightTimeSources(), ",")')
check('the settings list which addons gave times: ' + srcs, 'InFlight' in srcs and 'EllesmereUI' in srcs and 'Flight Timer Classic' in srcs)

T.ex('__fly(4, 200)')
r = T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Stormwind, Elwynn"]')
check('your own flight replaces an imported time', r.t == 200 and r.src == 'flown')

# The bar, once turned on: time left over total, stops, fade out after landing.
T.ex(db + '.flightTimer = true')
T.ex('TakeTaxiNode(5); __advance(0.5); __trackTick()(); __onTaxi = true; __trackTick()()')
check('turning the bar on shows it on the next flight', T.ev('EPUGuildFlightTimer:IsShown()'))
T.ex('__advance(20); EPUGuildFlightTimer:GetScript("OnUpdate")(EPUGuildFlightTimer, 0.5)')
txt = T.ev('EPUGuildFlightTimer.time:GetText()')
check('it shows time left over the total: ' + txt, txt == '4:00 / 4:20')
check('it names the destination', T.ev('EPUGuildFlightTimer.dest:GetText()') == 'Lakeshire')
note = T.ev('EPUGuildFlightTimer.note:GetText()')
check('it names the next stop on the way: ' + note, note.startswith('Next: Stormwind'))
T.ex('__advance(240); __onTaxi = false; __trackTick()()')
check('landing records the multi-stop route', T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Lakeshire, Redridge"].t') == 260)
T.ex('for i = 1, 10 do EPUGuildFlightTimer:GetScript("OnUpdate")(EPUGuildFlightTimer, 0.2) end')
check('the bar fades out and hides after landing', not T.ev('EPUGuildFlightTimer:IsShown()'))

# Early landing: not counted as the route's time.
T.ex('TaxiRequestEarlyLanding = function() end')
T.ex('TakeTaxiNode(2); __advance(0.5); __trackTick()(); __onTaxi = true; __trackTick()(); __advance(5)')
T.ex('EPUGuildFlightTimer:GetScript("OnUpdate")(EPUGuildFlightTimer, 0.5); EPUGuildFlightTimer.land:Click(); __advance(10); __onTaxi = false; __trackTick()()')
check('a flight cut short with Land is not counted', T.ev(db + '.flightRoutes["Ironforge, Dun Morogh->Thelsamar, Loch Modan"].n') == 3)

# Settings: look options, a preview to place it, and the bar's place is kept.
T.ex('__ns.OpenWorldQoLSettings()')
labels = T.ev('(function() local o = {} for _, w in ipairs(EPUGuildWorldQoLConfig.pool.used) do if w.text then o[#o+1] = w.text:GetText() end end return table.concat(o, "|") end)()')
check('the settings have bar height, end caps and a preview', 'Bar: Medium' in labels and 'End caps: On' in labels and 'Preview & move' in labels)
T.ex('''for _, w in ipairs(EPUGuildWorldQoLConfig.pool.used) do if w.text and w.text:GetText() == "Bar: Medium" then w:Click() break end end''')
check('the height button steps to thick', T.ev(db + '.flightBarHeight') == 'thick')
T.ex('''for _, w in ipairs(EPUGuildWorldQoLConfig.pool.used) do if w.text and w.text:GetText() == "Preview & move" then w:Click() break end end''')
check('the preview shows the bar', T.ev('__ns.FlightPreviewShown()') and T.ev('EPUGuildFlightTimer:IsShown()'))
T.ex('EPUGuildFlightTimer:GetScript("OnUpdate")(EPUGuildFlightTimer, 0.5)')
check('the preview shows a sample route', T.ev('EPUGuildFlightTimer.dest:GetText()') == 'Lakeshire')
T.ex('EPUGuildFlightTimer.GetPoint = function() return "CENTER", UIParent, "CENTER", 120, -40 end; EPUGuildFlightTimer:GetScript("OnDragStop")(EPUGuildFlightTimer)')
check('dragging saves where the bar goes', T.ev(db + '.flightPos[3]') == 120)

# A saved "on" from before stays on.
T.ex(db + '.flightTimer = true; __ns.db.worldQoL.mapCoords = nil')
T.ex('__ns.OpenWorldQoLSettings()')
check('a setting already saved as on stays on', T.ev(db + '.flightTimer') is True)

print('Flight timer checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

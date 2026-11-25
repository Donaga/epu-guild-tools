-- EPU Guild Tools: World travel, waypoints, flight timer, vendor QoL, and item tooltip extras.
local _, ns = ...
-- Newer clients keep this under C_Item; the old global only exists when the
-- game's "deprecated API" fallback is on (see Core.lua).
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function DB()
  if not ns.db then return {} end
  ns.db.worldQoL = ns.db.worldQoL or {}
  local db = ns.db.worldQoL
  if db.mapCoords == nil then db.mapCoords = true end
  if db.waypoints == nil then db.waypoints = true end
  -- Off for new installs (0.39.0); a setting already saved stays as it is.
  if db.flightTimer == nil then db.flightTimer = false end
  if db.autoSellGrey == nil then db.autoSellGrey = true end
  if db.autoRepair == nil then db.autoRepair = true end
  -- Paying repairs from the guild bank is the player's choice, not a default.
  -- 0.30.x saved it as on for everyone, so reset it once; the toggle below
  -- marks it chosen.
  if not db.guildRepairChosen then db.guildRepair = false end
  if db.tooltipExtras == nil then db.tooltipExtras = true end
  if db.neededMatsWarn == nil then db.neededMatsWarn = true end
  db.flightTimes = db.flightTimes or {}
  db.altItems = db.altItems or {}
  return db
end

local function FormatMoneyText(copper)
  copper = math.floor(math.abs(copper or 0))
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

local function ClassHex(cf)
  local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if c then
    if c.colorStr then return "|c" .. c.colorStr end
    return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
  end
  return "|cffffffff"
end

---------------------------------------------------------------------------
-- 1. World Map Player & Cursor Coordinates (parented to UIParent to avoid taint)
---------------------------------------------------------------------------
local coordFrame, coordText
local function SetupMapCoords()
  if coordFrame or not WorldMapFrame then return end
  local C = ns.InterfaceColors
  coordFrame = CreateFrame("Frame", "EPUGuildMapCoords", UIParent)
  coordFrame:SetSize(250, 22)
  coordFrame:SetFrameStrata("HIGH")
  coordFrame:Hide()
  local bg = coordFrame:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.82)
  bg:SetAllPoints()
  coordText = ns.InterfaceFont(coordFrame, 11, C.white)
  coordText:SetPoint("CENTER")

  local function SyncShown()
    if DB().mapCoords and WorldMapFrame:IsShown() then
      coordFrame:ClearAllPoints()
      coordFrame:SetPoint("BOTTOM", WorldMapFrame, "BOTTOM", 0, 10)
      coordFrame:Show()
    else
      coordFrame:Hide()
    end
  end
  WorldMapFrame:HookScript("OnShow", SyncShown)
  WorldMapFrame:HookScript("OnHide", SyncShown)

  local elapsed = 0
  coordFrame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if not DB().mapCoords or not WorldMapFrame:IsShown() then coordFrame:Hide(); return end

    local pStr = "Player: --"
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
      local mapID = C_Map.GetBestMapForUnit("player")
      local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
      if pos and pos.GetXY then
        local px, py = pos:GetXY()
        if px and py and (px > 0 or py > 0) then
          pStr = string.format("Player: %.1f, %.1f", px * 100, py * 100)
        end
      end
    end

    local cStr = "Cursor: --"
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.GetNormalizedCursorPosition then
      local ok, cx, cy = pcall(sc.GetNormalizedCursorPosition, sc)
      if ok and cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        cStr = string.format("Cursor: %.1f, %.1f", cx * 100, cy * 100)
      end
    end
    coordText:SetText(pStr .. "   |cff888888||r   " .. cStr)
  end)
end

---------------------------------------------------------------------------
-- 2. Simple /way x y Waypoint HUD
---------------------------------------------------------------------------
local wayFrame, wayText, wayArrow
local activeWay

local function EnsureWayFrame()
  if wayFrame then return wayFrame end
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", "EPUGuildWaypointFrame", UIParent)
  f:SetSize(210, 44)
  f:SetPoint("TOP", UIParent, "TOP", 0, -110)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.88)
  bg:SetAllPoints()
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4] or 1)
    t:SetPoint(side[1]); t:SetPoint(side[2])
    if side[3] then t:SetHeight(1) else t:SetWidth(1) end
  end

  wayArrow = f:CreateTexture(nil, "ARTWORK")
  wayArrow:SetSize(22, 22)
  wayArrow:SetPoint("LEFT", 10, 0)
  wayArrow:SetTexture("Interface\\Minimap\\MinimapArrow")

  wayText = ns.InterfaceFont(f, 11, C.white)
  wayText:SetPoint("LEFT", wayArrow, "RIGHT", 8, 0)
  wayText:SetPoint("RIGHT", -24, 0)
  wayText:SetJustifyH("LEFT")

  local close = ns.InterfaceButton(f, "×", 18, 18)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() activeWay = nil; f:Hide() end)

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.08 then return end
    acc = 0
    if not activeWay or not DB().waypoints then f:Hide(); return end
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID ~= activeWay.mapID then
      wayText:SetText((activeWay.label or "Waypoint") .. "\n|cff888888Different zone|r")
      return
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or not pos.GetXY then return end
    local px, py = pos:GetXY()
    if not px or not py then return end
    local dx = (activeWay.x - px)
    local dy = (activeWay.y - py)
    local distPct = math.sqrt(dx * dx + dy * dy) * 100
    if distPct < 0.8 then
      ns.Print("Arrived at waypoint" .. (activeWay.label and (": " .. activeWay.label) or "."))
      activeWay = nil
      f:Hide()
      return
    end
    local facing = GetPlayerFacing and SafeNum(GetPlayerFacing()) or 0
    local targetAngle = math.atan2(-dx, -dy)
    if wayArrow.SetRotation then
      wayArrow:SetRotation(targetAngle - facing)
    end
    wayText:SetText(string.format("%s\n|cff4fc3f7%.1f, %.1f|r  |cff888888(%.1f)|r", activeWay.label or "Waypoint", activeWay.x * 100, activeWay.y * 100, distPct))
  end)

  wayFrame = f
  return f
end

function ns.SetWaypoint(x, y, label)
  if not DB().waypoints then return ns.Print("Waypoints are disabled in /epu qol.") end
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if not mapID then return ns.Print("Could not determine current map.") end
  activeWay = { mapID = mapID, x = x / 100, y = y / 100, label = label and label ~= "" and label or nil }
  EnsureWayFrame():Show()
end

function ns.HandleWayCommand(msg)
  msg = tostring(msg or ""):match("^%s*(.-)%s*$")
  if msg == "" or msg:lower() == "clear" or msg:lower() == "reset" then
    activeWay = nil
    if wayFrame then wayFrame:Hide() end
    return ns.Print("Waypoint cleared.")
  end
  local xStr, yStr, rest = msg:match("^(%d+%.?%d*)%s*[,%s]+(%d+%.?%d*)%s*(.*)$")
  local x, y = tonumber(xStr), tonumber(yStr)
  if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
    return ns.Print("Usage: /epu way <x> <y> [label]  or  /epu way clear")
  end
  ns.SetWaypoint(x, y, rest)
end

---------------------------------------------------------------------------
-- 3. Flight Path Timer
--
-- Routes are keyed by the flight master names the taxi map shows, such as
-- "Ironforge, Dun Morogh->Thelsamar, Loch Modan". Each route keeps
-- { t = seconds, n = flights you timed, src = "flown" or the addon the time
-- came from }. Times from other flight timer addons fill the gaps, and every
-- flight you take corrects them. Learning runs even with the bar turned off,
-- so the times are ready when someone turns it on.
---------------------------------------------------------------------------
local FLIGHT_MIN, FLIGHT_MAX = 5, 1800
local flightFrame
local curFlight = nil
local flightPreview = false

local function Routes()
  local db = DB()
  db.flightRoutes = db.flightRoutes or {}
  return db.flightRoutes
end

local function FlightClock(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
ns.FlightClock = FlightClock

-- A flight's time joins the route's average. Times far from it, like a
-- flight cut short by a disconnect, are set aside, unless two in a row agree
-- (the route really changed). A time from another addon gives way to the
-- first one you fly.
local function RecordFlight(key, secs)
  if not key or not secs or secs < FLIGHT_MIN or secs > FLIGHT_MAX then return end
  local routes = Routes()
  local r = routes[key]
  local now = GetServerTime and GetServerTime() or 0
  if not r or r.src ~= "flown" or not r.t then
    routes[key] = { t = secs, n = 1, src = "flown", at = now }
    return routes[key]
  end
  if (r.n or 1) >= 2 and (secs < r.t * 0.7 or secs > r.t * 1.4) then
    if r.odd and math.abs(r.odd - secs) <= math.max(5, secs * 0.15) then
      routes[key] = { t = (r.odd + secs) / 2, n = 2, src = "flown", at = now }
    else
      r.odd = secs
    end
    return routes[key]
  end
  local w = math.min(r.n or 1, 4)
  r.t = math.floor(((r.t * w + secs) / (w + 1)) * 10 + 0.5) / 10
  r.n = (r.n or 1) + 1
  r.odd = nil
  r.at = now
  return r
end
ns.RecordFlight = RecordFlight

---------------------------------------------------------------------------
-- Flight times from other flight timer addons
--
-- Each addon keeps its times its own way, so EPU doesn't assume one layout.
-- It looks through their saved data for tables shaped like
-- [from][to] = seconds (or a small table with the seconds in it) and reads
-- a route only when both ends match the flight masters you're flying
-- between: by full name, by short name, by the game's node id, or by the map
-- position hash older Classic timers use. Nothing is copied from those
-- addons' files; this only reads what they have loaded in your game.
---------------------------------------------------------------------------
local KNOWN_FLIGHT_GLOBALS = {
  { "InFlightDB", "InFlight" }, { "InFlight", "InFlight" },
  { "FlightTimerDB", "Flight Timer" }, { "FTCData", "Flight Timer Classic" },
  { "FlightTimerClassic", "Flight Timer Classic" }, { "FlightTimerClassicDB", "Flight Timer Classic" },
  { "FlyTravelTimesDB", "FlyTravelTimes" }, { "FlyTravelTimes", "FlyTravelTimes" },
  { "FlightMapTimes", "FlightMap" }, { "FlightMap", "FlightMap" },
  { "ForeverFlightPathDB", "ForeverFlightPath" }, { "ForeverFlightTimerDB", "Forever Flight Timer" },
  { "EllesmereUIDB", "EllesmereUI" },
}
local FLIGHT_WORDS = { "flight", "taxi", "fly", "travel", "route" }
local routeTables, routeTablesAt, flightSourcesFound

local function HasFlightWord(s)
  if type(s) ~= "string" then return false end
  s = s:lower()
  for _, w in ipairs(FLIGHT_WORDS) do if s:find(w, 1, true) then return true end end
  return false
end

local function ValueSeconds(v)
  if type(v) == "table" then
    v = rawget(v, "time") or rawget(v, "t") or rawget(v, "duration") or rawget(v, "seconds")
      or rawget(v, "secs") or rawget(v, "avg") or rawget(v, "average")
  end
  v = SafeNum(v)
  if v and v >= FLIGHT_MIN and v <= FLIGHT_MAX then return v end
end

-- Loaded addons that look like flight timers (or EllesmereUI), with the
-- globals named after them.
local function FlightAddonGlobals()
  local found, names = {}, {}
  local num = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
  for i = 1, SafeNum(num) or 0 do
    local name, title
    if C_AddOns and C_AddOns.GetAddOnInfo then name, title = C_AddOns.GetAddOnInfo(i)
    elseif GetAddOnInfo then name, title = GetAddOnInfo(i) end
    name = SafeStr(name)
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(i))
      or (IsAddOnLoaded and IsAddOnLoaded(i))
    if name and loaded and name ~= "EPUGuild" and (HasFlightWord(name) or name:lower():find("ellesmere", 1, true)) then
      names[#names + 1] = { name:lower():gsub("[^%w]", ""), SafeStr(title) and SafeStr(title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or name }
    end
  end
  if #names > 0 then
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "table" then
        local lk = k:lower():gsub("[^%w]", "")
        for _, n in ipairs(names) do
          if #n[1] >= 4 and lk:sub(1, #n[1]) == n[1] then found[#found + 1] = { k, n[2] } end
        end
      end
    end
  end
  return found
end

local function CollectRouteTables()
  local out, seen, budget = {}, {}, 40000
  local faction = UnitFactionGroup and SafeStr(UnitFactionGroup("player"))
  local other = faction == "Alliance" and "Horde" or faction == "Horde" and "Alliance" or nil
  local sources, labels = {}, {}
  for _, g in ipairs(KNOWN_FLIGHT_GLOBALS) do sources[#sources + 1] = g end
  for _, g in ipairs(FlightAddonGlobals()) do sources[#sources + 1] = g end
  for _, src in ipairs(sources) do
    local root = rawget(_G, src[1])
    if type(root) == "table" and not seen[root] then
      local specific = HasFlightWord(src[1]) or HasFlightWord(src[2]) or src[1] == "FTCData"
      local stack = { { root, 0, specific } }
      local before = #out
      while #stack > 0 and budget > 0 do
        local item = table.remove(stack)
        local t, depth, ok = item[1], item[2], item[3]
        if not seen[t] then
          seen[t] = true
          budget = budget - 1
          local isRoutes = false
          for k, v in pairs(t) do
            if type(v) == "table" then
              if not isRoutes then
                local looked = 0
                for _, x in pairs(v) do
                  if ValueSeconds(x) then isRoutes = true; break end
                  looked = looked + 1
                  if looked >= 6 then break end
                end
              end
              if depth < 6 and k ~= other then
                stack[#stack + 1] = { v, depth + 1, ok or HasFlightWord(k) }
              end
            end
          end
          if isRoutes then out[#out + 1] = { t = t, label = src[2], ok = ok } end
        end
      end
      if #out > before then labels[src[2]] = true end
    end
  end
  flightSourcesFound = {}
  for label in pairs(labels) do flightSourcesFound[#flightSourcesFound + 1] = label end
  table.sort(flightSourcesFound)
  return out
end

local function RouteTables()
  local now = GetTime and GetTime() or 0
  if not routeTables or now - (routeTablesAt or 0) > 120 then
    local ok, list = pcall(CollectRouteTables)
    routeTables = ok and list or {}
    routeTablesAt = now
  end
  return routeTables
end

-- Ways other addons may name a flight master. Only the full "Name, Zone"
-- form is matched outside tables that are clearly about flights.
local function NodeKeys(node)
  local keys = {}
  if node.name then
    keys[#keys + 1] = { k = node.name, named = true }
    local short = node.name:match("^(.-),")
    if short and short ~= "" then keys[#keys + 1] = { k = short } end
  end
  if node.id then keys[#keys + 1] = { k = node.id }; keys[#keys + 1] = { k = tostring(node.id) } end
  if node.x then
    local h = math.floor(node.x * 100000000)
    keys[#keys + 1] = { k = tostring(h) }; keys[#keys + 1] = { k = h }
    local r = math.floor(node.x * 100000000 + 0.5)
    if r ~= h then keys[#keys + 1] = { k = tostring(r) } end
  end
  return keys
end

local function LookUpElsewhere(from, to)
  local srcKeys, dstKeys = NodeKeys(from), NodeKeys(to)
  for _, rt in ipairs(RouteTables()) do
    for _, s in ipairs(srcKeys) do
      if rt.ok or s.named then
        local okA, inner = pcall(function() return rt.t[s.k] end)
        if okA and type(inner) == "table" then
          for _, d in ipairs(dstKeys) do
            if rt.ok or d.named then
              local okB, v = pcall(function() return inner[d.k] end)
              local secs = okB and ValueSeconds(v)
              if secs then return secs, rt.label end
            end
          end
        end
      end
    end
  end
end

function ns.FlightTimeSources()
  RouteTables()
  return flightSourcesFound or {}
end

---------------------------------------------------------------------------
-- The taxi map: where you are, where each flight goes and where it stops
---------------------------------------------------------------------------
local function NodeAt(slot, ids)
  if not slot then return nil end
  local name = TaxiNodeName and SafeStr(TaxiNodeName(slot))
  local x, y
  if TaxiNodePosition then x, y = TaxiNodePosition(slot) end
  return { slot = slot, name = name, id = ids and ids[slot], x = SafeNum(x), y = SafeNum(y) }
end

local function TaxiNodeIDs()
  local ids = {}
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
    local ok, list = pcall(function() return C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) end)
    if ok and type(list) == "table" then
      for _, n in ipairs(list) do
        if type(n) == "table" and SafeNum(n.slotIndex) and SafeNum(n.nodeID) then ids[n.slotIndex] = n.nodeID end
      end
    end
  end
  return ids
end

local function CurrentNode(ids)
  local n = NumTaxiNodes and SafeNum(NumTaxiNodes()) or 0
  for i = 1, n do
    if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then return NodeAt(i, ids) end
  end
end

-- The flight masters a flight passes, ending with the destination, each with
-- how far along the bar it sits (by distance on the flight map).
local function FlightStops(slot, from, ids)
  local stops = {}
  local hops = GetNumRoutes and SafeNum(GetNumRoutes(slot)) or 0
  if hops > 1 and TaxiGetNodeSlot then
    for i = 1, hops do
      local ok, s = pcall(TaxiGetNodeSlot, slot, i, false)
      s = ok and SafeNum(s)
      if s then stops[#stops + 1] = NodeAt(s, ids) end
    end
  end
  if #stops == 0 or stops[#stops].slot ~= slot then stops[#stops + 1] = NodeAt(slot, ids) end
  local total, dist, px, py = 0, {}, from and from.x, from and from.y
  for i, s in ipairs(stops) do
    if px and s.x and s.y and py then total = total + math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2) end
    dist[i] = total
    px, py = s.x, s.y
  end
  for i, s in ipairs(stops) do
    s.at = (total > 0 and dist[i] / total) or (i / #stops)
  end
  stops[#stops].at = 1
  return stops
end

local function LegacyKey(destName)
  local from = GetMinimapZoneText and SafeStr(GetMinimapZoneText())
  return from and destName and (from .. "->" .. destName)
end

-- What EPU knows about a route, filling it from 0.38.0's saved times or
-- another addon when it has none of its own.
local function RouteTime(from, to)
  if not (from and from.name and to and to.name) then return nil end
  local key = from.name .. "->" .. to.name
  local routes = Routes()
  local r = routes[key]
  if r and r.t then return r, key end
  local legacy = DB().flightTimes[LegacyKey(to.name) or ""]
  if SafeNum(legacy) and legacy >= FLIGHT_MIN then
    routes[key] = { t = legacy, n = 1, src = "flown", at = GetServerTime and GetServerTime() or 0 }
    return routes[key], key
  end
  local secs, label = LookUpElsewhere(from, to)
  if secs then
    routes[key] = { t = secs, n = 0, src = label, at = GetServerTime and GetServerTime() or 0 }
    return routes[key], key, true
  end
  return nil, key
end
ns.FlightRouteTime = RouteTime

-- On the flight map, fill in every reachable route EPU doesn't know yet.
local function OnTaxiMapOpened()
  local ids = TaxiNodeIDs()
  local from = CurrentNode(ids)
  if not from then return end
  local n = NumTaxiNodes and SafeNum(NumTaxiNodes()) or 0
  local added, labels = 0, {}
  for i = 1, n do
    local kind = TaxiNodeGetType and TaxiNodeGetType(i)
    if kind == "REACHABLE" then
      local r, _, imported = RouteTime(from, NodeAt(i, ids))
      if imported then added = added + 1; labels[r.src] = true end
    end
  end
  if added > 0 and DB().flightTimer then
    local names = {}
    for l in pairs(labels) do names[#names + 1] = l end
    table.sort(names)
    ns.Print(string.format("Flight timer: added %d flight time%s from %s.", added, added == 1 and "" or "s", table.concat(names, ", ")))
  end
end

---------------------------------------------------------------------------
-- The bar: destination and time left over a route track, with each stop
-- passing by as you reach it, end caps, and an early landing button where
-- the game has one. Drag it to move it; the place is saved.
---------------------------------------------------------------------------
local BAR_HEIGHTS = { thin = 6, medium = 10, thick = 14 }
local NODE_DONE = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
local NODE_NEXT = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow"
local NODE_AHEAD = "Interface\\TaxiFrame\\UI-Taxi-Icon-White"

local function FlightLook()
  local db = DB()
  if not BAR_HEIGHTS[db.flightBarHeight or ""] then db.flightBarHeight = "medium" end
  if db.flightEndCaps == nil then db.flightEndCaps = true end
  return BAR_HEIGHTS[db.flightBarHeight], db.flightEndCaps
end

local function SaveFlightPosition(f)
  local point, _, rel, x, y = f:GetPoint()
  if point then DB().flightPos = { point, rel or point, x or 0, y or 0 } end
end

local function PlaceFlightFrame(f)
  f:ClearAllPoints()
  local p = DB().flightPos
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -165)
  end
end

local function Layout(f)
  local h, caps = FlightLook()
  f.track:SetHeight(h)
  f:SetHeight(h + 52)
  local cap = h + 8
  for _, c in ipairs({ f.capFrom, f.capTo }) do c:SetSize(cap, cap); c:SetShown(caps) end
  f.track:ClearAllPoints()
  local inset = caps and math.floor(cap / 2) + 10 or 10
  f.track:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -26)
  f.track:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -26)
  f.spark:SetSize(math.max(12, h * 2), h * 2.6)
end

local function FlightStopIcon(f, i)
  f.stopIcons = f.stopIcons or {}
  local t = f.stopIcons[i]
  if not t then
    t = f.trackOverlay:CreateTexture(nil, "OVERLAY")
    f.stopIcons[i] = t
  end
  return t
end

local function ShowFlight(f, fl, elapsed)
  local h = FlightLook()
  local width = f.track:GetWidth()
  if not width or width <= 0 then width = 250 end
  local expected = fl.expected and fl.expected > 0 and fl.expected or nil
  local frac = expected and math.min(1, elapsed / expected) or nil
  f.dest:SetText(fl.dest or "In flight")
  f.from:SetText(fl.from and ("From " .. fl.from) or "")
  if expected then
    f.time:SetText(FlightClock(expected - elapsed) .. " / " .. FlightClock(expected))
    f.track:SetValue(frac)
    f.track:SetAlpha(1)
    f.spark:SetShown(frac > 0 and frac < 1)
    f.spark:SetPoint("CENTER", f.track, "LEFT", width * frac, 0)
  else
    f.time:SetText(FlightClock(elapsed))
    f.track:SetValue(1)
    f.track:SetAlpha(0.35 + 0.2 * math.sin((GetTime() or 0) * 3))
    f.spark:Hide()
  end
  -- Stops along the way: passed ones turn green, the next one is yellow.
  local stops = fl.stops or {}
  local nextStop, left = nil, 0
  local size = math.max(8, h + 2)
  for i, s in ipairs(stops) do
    local passed = frac and frac >= s.at - 0.002
    if not passed then left = left + 1; nextStop = nextStop or s end
    if i < #stops then
      local t = FlightStopIcon(f, i)
      t:SetSize(size, size)
      t:ClearAllPoints()
      t:SetPoint("CENTER", f.track, "LEFT", width * s.at, 0)
      t:SetTexture(passed and NODE_DONE or (nextStop == s and NODE_NEXT or NODE_AHEAD))
      t:Show()
    end
  end
  for i = math.max(1, #stops), #(f.stopIcons or {}) do f.stopIcons[i]:Hide() end
  f.capTo:SetTexture(frac and frac >= 1 and NODE_DONE or NODE_NEXT)
  if not expected then
    f.note:SetText(#stops > 1 and string.format("Timing this route · %d stops", #stops - 1) or "Timing this route")
  elseif nextStop and nextStop.name and left > 1 then
    local short = nextStop.name:match("^(.-),") or nextStop.name
    f.note:SetText(string.format("Next: %s · %d stop%s left", short, left - 1, left - 1 == 1 and "" or "s"))
  elseif fl.src and fl.src ~= "flown" then
    f.note:SetText("Time from " .. fl.src .. " · EPU checks it this flight")
  else
    f.note:SetText(fl.n and fl.n > 1 and string.format("Average of %d flights", fl.n) or "")
  end
  f.land:SetShown(not fl.preview and TaxiRequestEarlyLanding ~= nil and not fl.early)
end

local function EnsureFlightFrame()
  if flightFrame then return flightFrame end
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", "EPUGuildFlightTimer", UIParent)
  f:SetSize(300, 62)
  PlaceFlightFrame(f)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveFlightPosition(self) end)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.92)
  bg:SetAllPoints()
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local e = f:CreateTexture(nil, "BORDER")
    e:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    if side == "TOP" or side == "BOTTOM" then
      e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT"); e:SetHeight(1)
    else
      e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side); e:SetWidth(1)
    end
  end
  local accent = f:CreateTexture(nil, "ARTWORK")
  accent:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.9)
  accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("TOPRIGHT", -1, -1); accent:SetHeight(2)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
  f.icon:SetSize(14, 14)
  f.icon:SetPoint("TOPLEFT", 9, -7)
  f.dest = ns.InterfaceFont(f, 12, C.white, "OVERLAY", true)
  f.dest:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
  f.time = ns.InterfaceFont(f, 12, C.gold, "OVERLAY", true)
  f.time:SetPoint("TOPRIGHT", -10, -7)
  f.time:SetJustifyH("RIGHT")
  f.dest:SetPoint("RIGHT", f.time, "LEFT", -8, 0)

  f.track = CreateFrame("StatusBar", nil, f)
  f.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  f.track:SetStatusBarColor(C.blue[1], C.blue[2], C.blue[3], 0.95)
  f.track:SetMinMaxValues(0, 1)
  local tbg = f.track:CreateTexture(nil, "BACKGROUND")
  tbg:SetColorTexture(C.input[1], C.input[2], C.input[3], 1)
  tbg:SetAllPoints()
  f.trackOverlay = CreateFrame("Frame", nil, f)
  f.trackOverlay:SetAllPoints(f.track)
  f.trackOverlay:SetFrameLevel((f.track:GetFrameLevel() or 1) + 2)
  f.spark = f.trackOverlay:CreateTexture(nil, "OVERLAY")
  f.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  f.spark:SetBlendMode("ADD")
  f.capFrom = f.trackOverlay:CreateTexture(nil, "OVERLAY")
  f.capFrom:SetTexture(NODE_DONE)
  f.capFrom:SetPoint("CENTER", f.track, "LEFT", -2, 0)
  f.capTo = f.trackOverlay:CreateTexture(nil, "OVERLAY")
  f.capTo:SetTexture(NODE_NEXT)
  f.capTo:SetPoint("CENTER", f.track, "RIGHT", 2, 0)

  f.from = ns.InterfaceFont(f, 10, C.muted)
  f.from:SetPoint("BOTTOMLEFT", 10, 7)
  f.note = ns.InterfaceFont(f, 10, C.muted)
  f.note:SetJustifyH("RIGHT")

  f.land = CreateFrame("Button", nil, f)
  f.land:SetSize(40, 15)
  f.land:SetPoint("BOTTOMRIGHT", -8, 5)
  local lbg = f.land:CreateTexture(nil, "BACKGROUND")
  lbg:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1)
  lbg:SetAllPoints()
  f.land.text = ns.InterfaceFont(f.land, 10, C.text)
  f.land.text:SetPoint("CENTER")
  f.land.text:SetText("Land")
  f.land:SetScript("OnClick", function()
    if curFlight and TaxiRequestEarlyLanding then
      curFlight.early = true
      pcall(TaxiRequestEarlyLanding)
    end
  end)
  f.land:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Land at the next flight master")
    GameTooltip:Show()
  end)
  f.land:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.land:HookScript("OnShow", function() f.note:SetPoint("BOTTOMRIGHT", f.land, "BOTTOMLEFT", -6, 2) end)
  f.land:HookScript("OnHide", function() f.note:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7) end)
  f.note:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
  f.note:SetPoint("LEFT", f.from, "RIGHT", 8, 0)
  f.land:Hide()

  -- Fade in when it appears, out after you land.
  f.fade = 0
  f:SetScript("OnUpdate", function(self, dt)
    dt = dt or 0
    local fl = flightPreview and self.previewFlight or curFlight
    local want = fl and (flightPreview or DB().flightTimer) and not self.leaving
    self.fade = math.max(0, math.min(1, self.fade + (want and dt / 0.25 or -dt / 0.6)))
    self:SetAlpha(self.fade)
    if self.fade <= 0 and not want then self.leaving = nil; self:Hide(); return end
    if fl then
      local elapsed = (GetTime() or 0) - (fl.startedAt or 0)
      if fl.preview and fl.expected and elapsed > fl.expected + 2 then fl.startedAt = GetTime(); elapsed = 0 end
      ShowFlight(self, fl, fl.boarded == false and 0 or elapsed)
    end
  end)
  Layout(f)
  flightFrame = f
  return f
end

local function ShowFlightFrame()
  local f = EnsureFlightFrame()
  f.leaving = nil
  Layout(f)
  if not f:IsShown() then f.fade = 0; f:SetAlpha(0); f:Show() end
end

-- Times the flight whether or not the bar is shown.
local flightTracker = CreateFrame("Frame")
local function TrackFlight()
  local fl = curFlight
  if not fl then flightTracker:SetScript("OnUpdate", nil); return end
  -- The server puts us on the taxi a moment after TakeTaxiNode, so wait
  -- for boarding (and time the flight from then) before treating "not on
  -- a taxi" as landed. No boarding within 10 seconds means no flight.
  local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
  if onTaxi and not fl.boarded then
    fl.boarded = true
    fl.startedAt = GetTime()
  elseif not onTaxi then
    if fl.boarded then
      local elapsed = math.floor((GetTime() - fl.startedAt) + 0.5)
      if not fl.early then RecordFlight(fl.key, elapsed) end
    end
    if fl.boarded or GetTime() - fl.startedAt > 10 then
      curFlight = nil
      flightTracker:SetScript("OnUpdate", nil)
      if flightFrame and not flightPreview then flightFrame.leaving = true end
      return
    end
  end
end

if hooksecurefunc and TakeTaxiNode then
  hooksecurefunc("TakeTaxiNode", function(slot)
    local ids = TaxiNodeIDs()
    local from = CurrentNode(ids) or { name = GetMinimapZoneText and SafeStr(GetMinimapZoneText()) }
    local to = NodeAt(slot, ids) or {}
    to.name = to.name or "Destination"
    local r, key = RouteTime(from, to)
    if not key then key = LegacyKey(to.name) end
    curFlight = {
      key = key,
      dest = (to.name:match("^(.-),") or to.name),
      from = from.name and (from.name:match("^(.-),") or from.name),
      startedAt = GetTime(),
      boarded = false,
      expected = r and r.t,
      src = r and r.src,
      n = r and r.n,
      stops = FlightStops(slot, from, ids),
    }
    flightTracker:SetScript("OnUpdate", TrackFlight)
    if DB().flightTimer then ShowFlightFrame() end
  end)
end

-- A sample flight to see the look and drag the bar into place.
function ns.ToggleFlightPreview(on)
  if on == nil then on = not flightPreview end
  flightPreview = on and true or false
  local f = EnsureFlightFrame()
  if flightPreview then
    f.previewFlight = {
      preview = true, dest = "Lakeshire", from = "Stormwind", startedAt = GetTime(), expected = 95, src = "flown", n = 3,
      stops = { { name = "Goldshire, Elwynn", at = 0.3 }, { name = "Sentinel Hill, Westfall", at = 0.62 }, { name = "Lakeshire, Redridge", at = 1 } },
    }
    ShowFlightFrame()
  else
    f.previewFlight = nil
    if not curFlight or not DB().flightTimer then f.leaving = true end
  end
  return flightPreview
end
function ns.FlightPreviewShown() return flightPreview end

function ns.RefreshFlightTimerLook()
  if flightFrame then Layout(flightFrame) end
end

if ns.On then ns.On("TAXIMAP_OPENED", function() pcall(OnTaxiMapOpened) end) end

---------------------------------------------------------------------------
-- Needed mats (NeededMats.lua): who in the guild still needs an item.
---------------------------------------------------------------------------
local function ItemIDOf(link)
  link = SafeStr(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- Everyone who needs it, you included: { {who, n, me}, ... } or nil
local function NeededList(id)
  id = tonumber(id)
  if not id or not ns.NeededBy then return nil end
  local list = ns.NeededBy(id)
  return (#list > 0) and list or nil
end

local function IsNeeded(id) return NeededList(id) ~= nil end

-- "Tyler (x20), Ana and you", or nil when nobody needs it.
local function WhoNeeds(id)
  local list = NeededList(id)
  if not list then return nil end
  local names = {}
  for i = 1, math.min(3, #list) do
    local c = list[i]
    local n = c.me and "you" or ((c.who and c.who:match("^(%S+)")) or c.who or "?")
    if (tonumber(c.n) or 0) > 0 then n = n .. " (x" .. c.n .. ")" end
    names[#names + 1] = n
  end
  if #list > 3 then names[#names + 1] = (#list - 3) .. " more" end
  -- the verb to follow: "Tyler needs", "you need", "Tyler and Ana need"
  local verb = (#list == 1 and not list[1].me) and "needs" or "need"
  if #names == 1 then return names[1], verb end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names], verb
end

---------------------------------------------------------------------------
-- 4. Auto-Sell Grey Junk & Auto-Repair at Merchants (hold Shift to skip)
---------------------------------------------------------------------------
local function OnMerchantShow()
  if IsShiftKeyDown and IsShiftKeyDown() then return end
  -- A bank alt's bags and gold are the guild's: leave them alone.
  if ns.IsBankAlt and ns.IsBankAlt() then return end
  local db = DB()

  if db.autoSellGrey then
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local getInfo = C_Container and C_Container.GetContainerItemInfo
    local useItem = C_Container and C_Container.UseContainerItem or UseContainerItem
    local soldCount, soldCopper, keptCount = 0, 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      local n = getSlots and SafeNum(getSlots(bag)) or 0
      for slot = 1, (n or 0) do
        local link, quality, count
        if getInfo then
          local info = getInfo(bag, slot)
          if info then link, quality, count = info.hyperlink, info.quality, info.stackCount end
        elseif GetContainerItemInfo then
          local _, c, _, q, _, _, l = GetContainerItemInfo(bag, slot)
          link, quality, count = l, q, c
        end
        if quality == 0 and SafeStr(link) and IsNeeded(ItemIDOf(link)) then
          keptCount = keptCount + 1
        elseif quality == 0 and SafeStr(link) then
          local sellPrice = GetItemInfo and select(11, GetItemInfo(link))
          sellPrice = SafeNum(sellPrice) or 0
          if sellPrice > 0 and useItem then
            soldCount = soldCount + (count or 1)
            soldCopper = soldCopper + sellPrice * (count or 1)
            useItem(bag, slot)
          end
        end
      end
    end
    if soldCount > 0 then
      ns.Print(string.format("Sold %d grey item%s for %s.", soldCount, soldCount == 1 and "" or "s", FormatMoneyText(soldCopper)))
    end
    if keptCount > 0 then
      ns.Print(string.format("Kept %d grey item%s a guildmate has on their needed mats list.", keptCount, keptCount == 1 and "" or "s"))
    end
  end

  if db.autoRepair and CanMerchantRepair and CanMerchantRepair() then
    local cost, canRepair = GetRepairAllCost()
    cost = SafeNum(cost) or 0
    if canRepair and cost > 0 then
      if db.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        -- What the guild can pay: today's withdrawal limit (-1 = no limit),
        -- but never more than the guild bank holds.
        local gLimit = GetGuildBankWithdrawMoney and SafeNum(GetGuildBankWithdrawMoney()) or 0
        local inBank = GetGuildBankMoney and SafeNum(GetGuildBankMoney()) or 0
        local canPay = gLimit == -1 and inBank or math.min(gLimit, inBank)
        if canPay >= cost then
          RepairAllItems(true)
          ns.Print("Repaired using guild bank funds: " .. FormatMoneyText(cost))
          return
        end
      end
      if GetMoney and (SafeNum(GetMoney()) or 0) >= cost then
        RepairAllItems(false)
        ns.Print("Repaired for " .. FormatMoneyText(cost))
      end
    end
  end
end

---------------------------------------------------------------------------
-- 4b. Needed mats at vendors and the auction house
-- Auto-sell never sells a material on anyone's needed mats list (above).
-- With the warning on (/epu qol), EPU also says in chat which needed mats are
-- in your bags when a vendor opens, when you sell one by hand, and when you
-- put one up for auction, naming who needs it. These are post-hooks only:
-- replacing the game's sell or post functions would taint the bag buttons.
---------------------------------------------------------------------------
local function Warn(msg) ns.Print("|cffffb347" .. msg .. "|r") end

local function WarnOn() return DB().neededMatsWarn ~= false end

local function ItemAt(bag, slot)
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  if getInfo then
    local info = getInfo(bag, slot)
    if info then return SafeNum(info.itemID) or ItemIDOf(info.hyperlink), SafeNum(info.stackCount) or 1 end
  elseif GetContainerItemInfo then
    local _, c, _, _, _, _, l, _, _, id = GetContainerItemInfo(bag, slot)
    return SafeNum(id) or ItemIDOf(l), SafeNum(c) or 1
  end
end

local function MerchantOpen() return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() end

-- When a vendor opens: one line listing the needed mats in your bags.
local function NoticeBags()
  if not WarnOn() then return end
  local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local seen, parts = {}, {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = getSlots and SafeNum(getSlots(bag)) or 0
    for slot = 1, (n or 0) do
      local id = ItemAt(bag, slot)
      if id and not seen[id] then
        seen[id] = true
        local who = WhoNeeds(id)
        if who then parts[#parts + 1] = ns.ItemLink(id) .. " (" .. who .. ")" end
      end
    end
  end
  if #parts == 0 then return end
  table.sort(parts)
  local more = #parts > 3 and (" and " .. (#parts - 3) .. " more") or ""
  Warn("Needed mats in your bags, so don't sell: " .. table.concat(parts, ", ", 1, math.min(3, #parts)) .. more .. ".")
end

-- Selling by hand is a right-click on a bag item while a vendor is open. The
-- item is still in its slot (locked) until the server takes it.
local lastSale = {}
local function OnUseContainerItem(bag, slot)
  if not WarnOn() or not MerchantOpen() then return end
  local id, count = ItemAt(bag, slot)
  if not id then return end
  local who, verb = WhoNeeds(id)
  if not who then return end
  local price = GetItemInfo and SafeNum(select(11, GetItemInfo(id))) or 0
  if price <= 0 then return end                 -- vendors won't buy it, so nothing sold
  local key = bag .. ":" .. slot .. ":" .. id
  local now = GetTime and GetTime() or 0
  if lastSale[key] and now - lastSale[key] < 0.5 then return end   -- one right-click, two hooked names
  lastSale[key] = now
  Warn("You sold " .. ns.ItemLink(id) .. ((count or 1) > 1 and (" x" .. count) or "") .. ", which " .. who
    .. " " .. verb .. ". Buy it back on the vendor's Buyback tab if that was a mistake.")
end

-- Auction house (classic): warn when a needed mat goes into the sell slot,
-- before it's posted. Once per item placed.
local auctionWarned
local function OnNewAuction()
  if not GetAuctionSellItemInfo then return end
  local name, _, count, _, _, _, _, _, _, id = GetAuctionSellItemInfo()
  name, id = SafeStr(name), SafeNum(id)
  if not name then auctionWarned = nil; return end
  if not id and GetItemInfo then id = ItemIDOf(select(2, GetItemInfo(name))) end
  if not id or auctionWarned == id then return end
  auctionWarned = id
  if not WarnOn() then return end
  local who = WhoNeeds(id)
  if who then
    Warn(ns.ItemLink(id) .. " is on the needed mats list of " .. who .. ". Consider offering it in guild instead of posting it.")
  end
end

-- Auction house (newer clients): warn after posting, since the post is one call.
local function OnPostItemLocation(loc, _, quantity)
  if not WarnOn() or type(loc) ~= "table" then return end
  local id = C_Item and C_Item.GetItemID and SafeNum(C_Item.GetItemID(loc))
  if not id then return end
  local who, verb = WhoNeeds(id)
  if who then
    Warn("You listed " .. ns.ItemLink(id) .. ((tonumber(quantity) or 1) > 1 and (" x" .. quantity) or "") .. ", which "
      .. who .. " " .. verb .. ". You can cancel it on the Auctions tab.")
  end
end

-- Hook when the vendor or auction house opens, so the functions exist. Each
-- function is hooked once.
local hooked = {}
local function Hook(tbl, key, name, fn)
  if hooked[key] or not hooksecurefunc then return end
  if tbl then
    if type(tbl[name]) ~= "function" then return end
    hooksecurefunc(tbl, name, fn)
  else
    if type(_G[name]) ~= "function" then return end
    hooksecurefunc(name, fn)
  end
  hooked[key] = true
end
local function HookVendor()
  Hook(C_Container, "C_Container.UseContainerItem", "UseContainerItem", OnUseContainerItem)
  Hook(nil, "UseContainerItem", "UseContainerItem", OnUseContainerItem)
end
local function HookAuctionHouse()
  Hook(C_AuctionHouse, "C_AuctionHouse.PostItem", "PostItem", OnPostItemLocation)
  Hook(C_AuctionHouse, "C_AuctionHouse.PostCommodity", "PostCommodity", OnPostItemLocation)
end

---------------------------------------------------------------------------
-- 5. Item Tooltip Extras (Alt/Bank item counts, vendor sell price, stack)
---------------------------------------------------------------------------
local function ScanCharacterItems(includeBank)
  if not ns.me then return end
  local db = DB()
  if not db.altItems then return end
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  db.altItems[realm] = db.altItems[realm] or {}
  local cf
  if UnitClass then cf = select(2, UnitClass("player")) end
  local rec = db.altItems[realm][ns.me] or { bags = {}, bank = {} }
  rec.classFile = cf
  rec.bags = {}

  local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local function ScanBag(bagID, dest)
    local n = getSlots and SafeNum(getSlots(bagID)) or 0
    for slot = 1, (n or 0) do
      local itemID, count
      if getInfo then
        local info = getInfo(bagID, slot)
        if info then itemID, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, _, _, _, id = GetContainerItemInfo(bagID, slot)
        itemID, count = id, c
      end
      if SafeNum(itemID) and SafeNum(count) then
        dest[itemID] = (dest[itemID] or 0) + count
      end
    end
  end

  for bag = 0, (NUM_BAG_SLOTS or 4) do ScanBag(bag, rec.bags) end
  if includeBank then
    rec.bank = {}
    if BANK_CONTAINER then ScanBag(BANK_CONTAINER, rec.bank) end
    if NUM_BAG_SLOTS and NUM_BANKBAGSLOTS then
      for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do ScanBag(bag, rec.bank) end
    end
  end
  db.altItems[realm][ns.me] = rec
end

local function AppendItemTooltip(tt, itemLinkOrID)
  if not tt or not DB().tooltipExtras then return end
  local itemID = type(itemLinkOrID) == "number" and itemLinkOrID or (SafeStr(itemLinkOrID) and tonumber(itemLinkOrID:match("item:(%d+)")))
  if not itemID then return end

  local maxStack, sellPrice
  if GetItemInfo then
    local info = { GetItemInfo(itemID) }
    maxStack, sellPrice = info[8], info[11]
  end
  maxStack = SafeNum(maxStack)
  sellPrice = SafeNum(sellPrice)

  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  local realmAlts = DB().altItems and DB().altItems[realm] or {}
  local altLines = {}
  local total = 0
  for who, rec in pairs(realmAlts) do
    local b = rec.bags and rec.bags[itemID] or 0
    local bk = rec.bank and rec.bank[itemID] or 0
    if b + bk > 0 then
      total = total + b + bk
      local detail = (b > 0 and bk > 0) and (b .. " bag, " .. bk .. " bank") or (bk > 0 and (bk .. " bank") or (b .. " bag"))
      altLines[#altLines + 1] = { name = ClassHex(rec.classFile) .. (ns.Short and ns.Short(who) or who) .. "|r", text = detail }
    end
  end

  if #altLines > 0 then
    table.sort(altLines, function(a, b) return a.name < b.name end)
    tt:AddLine(" ")
    tt:AddDoubleLine("Owned on Realm:", "|cffffffff" .. total .. "|r", 0.4, 0.8, 1, 1, 1, 1)
    for _, line in ipairs(altLines) do
      tt:AddDoubleLine("  " .. line.name, line.text, 1, 1, 1, 0.85, 0.85, 0.85)
    end
  end

  if (sellPrice and sellPrice > 0) or (maxStack and maxStack > 1) then
    local parts = {}
    if sellPrice and sellPrice > 0 then parts[#parts + 1] = "Sell: " .. FormatMoneyText(sellPrice) end
    if maxStack and maxStack > 1 then parts[#parts + 1] = "Stack: " .. maxStack end
    tt:AddLine(table.concat(parts, "  ·  "), 0.72, 0.78, 0.85)
  end
  tt:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt == GameTooltip and data and data.id then
      AppendItemTooltip(tt, data.id)
    end
  end)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", function(tt)
    local _, link = tt:GetItem()
    if link then AppendItemTooltip(tt, link) end
  end)
end

---------------------------------------------------------------------------
-- 6. Settings UI (/epu qol)
---------------------------------------------------------------------------
local qolWin
function ns.OpenWorldQoLSettings()
  local K = ns.UIKit
  if not qolWin then
    local C = ns.InterfaceColors
    qolWin = ns.InterfaceWindow("EPUGuildWorldQoLConfig", UIParent, "EPU Travel, Vendor & Tooltips", 410, 456)
    qolWin:SetFrameStrata("DIALOG")
    qolWin.pool = ns.NewWidgetPool(qolWin)

    function qolWin:Refresh()
      local pool = self.pool
      pool:ReleaseAll()
      local db = DB()
      local y = -44
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function AddToggle(label, key, onChange)
        local b = pool:Button(Check(db[key], label), 370, 22)
        b:SetPoint("TOPLEFT", 18, y)
        b:SetScript("OnClick", function()
          db[key] = not db[key]
          if onChange then onChange(db[key]) end
          qolWin:Refresh()
        end)
        y = y - 28
      end

      AddToggle("World Map Player & Cursor Coordinates", "mapCoords", function()
        if coordFrame and WorldMapFrame then coordFrame:SetShown(db.mapCoords and WorldMapFrame:IsShown()) end
      end)
      AddToggle("Waypoints (/epu way x y [label] and /epu way clear)", "waypoints", function(on)
        if not on and wayFrame then wayFrame:Hide() end
      end)
      AddToggle("Flight Path Timer Bar (learns route times)", "flightTimer", function(on)
        if not on and flightFrame and not flightPreview then flightFrame.leaving = true end
        if on and curFlight then ShowFlightFrame() end
      end)
      -- Flight bar look, a preview to drag it into place, and where its times come from.
      local function AddButton(label, w, x, fn)
        local b = pool:Button(label, w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() fn(); qolWin:Refresh() end)
        return b
      end
      local barH = FlightLook()
      local heightName = ({ [6] = "Thin", [10] = "Medium", [14] = "Thick" })[barH] or "Medium"
      AddButton("Bar: " .. heightName, 116, 34, function()
        db.flightBarHeight = ({ thin = "medium", medium = "thick", thick = "thin" })[db.flightBarHeight] or "medium"
        ns.RefreshFlightTimerLook()
      end)
      AddButton(db.flightEndCaps ~= false and "End caps: On" or "End caps: Off", 116, 154, function()
        db.flightEndCaps = db.flightEndCaps == false
        ns.RefreshFlightTimerLook()
      end)
      AddButton(flightPreview and "Hide preview" or "Preview & move", 116, 274, function() ns.ToggleFlightPreview() end)
      y = y - 26
      local known, imported = 0, 0
      for _, r in pairs(db.flightRoutes or {}) do
        known = known + 1
        if r.src ~= "flown" then imported = imported + 1 end
      end
      local sources = ns.FlightTimeSources()
      local info = pool:Font(10, C.muted, "flightInfo")
      info:SetPoint("TOPLEFT", 36, y)
      info:SetWidth(352)
      info:SetJustifyH("LEFT")
      info:SetText(string.format("%d route%s known, %d from other addons. Times from: %s.", known, known == 1 and "" or "s",
        imported, #sources > 0 and table.concat(sources, ", ") or "your own flights (no other flight timer found)"))
      y = y - 24
      AddToggle("Auto-Sell Grey Junk at Vendors (hold Shift to skip)", "autoSellGrey")
      AddToggle("Auto-Repair Gear at Vendors (hold Shift to skip)", "autoRepair")
      AddToggle("Use Guild Bank Funds for Auto-Repair when allowed", "guildRepair", function() db.guildRepairChosen = true end)
      AddToggle("Warn Before Selling or Auctioning a Mat a Guildmate Needs", "neededMatsWarn")
      AddToggle("Item Tooltip Extras (Alt/Bank counts, Sell price, Stack)", "tooltipExtras")

      local note = pool:Font(11, C.muted, "note")
      note:SetPoint("TOPLEFT", 18, y - 6)
      note:SetWidth(370)
      note:SetJustifyH("LEFT")
      note:SetText("Tip: Open your Bank once on each alt so EPU records their bank items for tooltip counts.")
    end
  end
  qolWin:Refresh()
  qolWin:Show()
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    SetupMapCoords()
    ScanCharacterItems(false)
  end)
  ns.On("BAG_UPDATE", function() ScanCharacterItems(false) end)
  ns.On("BANKFRAME_OPENED", function() ScanCharacterItems(true) end)
  ns.On("PLAYERBANKSLOTS_CHANGED", function() ScanCharacterItems(true) end)
  ns.On("MERCHANT_SHOW", OnMerchantShow)
  ns.On("MERCHANT_SHOW", function() HookVendor(); NoticeBags() end)
  ns.On("AUCTION_HOUSE_SHOW", function() auctionWarned = nil; HookAuctionHouse() end)
  ns.On("NEW_AUCTION_UPDATE", OnNewAuction)
end

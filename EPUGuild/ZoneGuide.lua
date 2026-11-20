-- EPU Guild Tools: Zone Visitor's Guide logic, quest difficulty colors,
-- live guildmate & gathering enrichment, and map waypoints.
local _, ns = ...
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local byId, byMap, byLowerName = {}, {}, {}

local function EnsureIndex()
  if next(byId) then return end
  for _, z in ipairs(ns.ZONE_GUIDE_DATA or {}) do
    byId[z.id] = z
    if z.mapID then byMap[z.mapID] = z end
    byLowerName[z.name:lower()] = z
  end
end

function ns.GetZoneById(id)
  EnsureIndex()
  return id and byId[id] or nil
end

function ns.FindZone(query)
  EnsureIndex()
  if not query or query == "" then return nil end
  local q = query:lower():match("^%s*(.-)%s*$")
  if q == "" then return nil end
  if byId[q] then return byId[q] end
  if byLowerName[q] then return byLowerName[q] end
  for _, z in ipairs(ns.ZONE_GUIDE_DATA or {}) do
    if z.name:lower():find(q, 1, true) then return z end
  end
  return nil
end

function ns.GetCurrentPlayerZone()
  EnsureIndex()
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID and byMap[mapID] then return byMap[mapID] end
  end
  if GetRealZoneText then
    local ok, name = pcall(GetRealZoneText)
    if ok and ns.IsReadableString(name) and byLowerName[name:lower()] then
      return byLowerName[name:lower()]
    end
  end
  if GetZoneText then
    local ok, name = pcall(GetZoneText)
    if ok and ns.IsReadableString(name) and byLowerName[name:lower()] then
      return byLowerName[name:lower()]
    end
  end
  return nil
end

function ns.GetPlayerLevel()
  if UnitLevel then
    local ok, lv = pcall(UnitLevel, "player")
    if ok and type(lv) == "number" and lv >= 1 then return lv end
  end
  return 1
end

function ns.GetPlayerFaction()
  if UnitFactionGroup then
    local ok, f = pcall(UnitFactionGroup, "player")
    if ok and (f == "Alliance" or f == "Horde") then return f end
  end
  return nil
end

function ns.GetZoneList(continent, search, nearLevelOnly)
  EnsureIndex()
  local out = {}
  local q = (search or ""):lower():match("^%s*(.-)%s*$")
  local pLevel = ns.GetPlayerLevel()
  for _, z in ipairs(ns.ZONE_GUIDE_DATA or {}) do
    local okCont = not continent or continent == "All" or z.continent == continent
    local okLevel = not nearLevelOnly or (z.levelRange and pLevel >= (z.levelRange[1] - 4) and pLevel <= (z.levelRange[2] + 4))
    local okSearch = q == "" or z.name:lower():find(q, 1, true) or (z.tagline and z.tagline:lower():find(q, 1, true))
    if okCont and okLevel and okSearch then
      out[#out + 1] = z
    end
  end
  table.sort(out, function(a, b)
    local al, bl = (a.levelRange and a.levelRange[1]) or 99, (b.levelRange and b.levelRange[1]) or 99
    if al ~= bl then return al < bl end
    return a.name < b.name
  end)
  return out
end

-- Classic WoW quest difficulty color schema relative to player level.
local function ClassicGreenDelta(playerLevel)
  if playerLevel <= 5 then return 4
  elseif playerLevel <= 39 then return 4 + math.floor(playerLevel / 10)
  elseif playerLevel <= 59 then return 5 + math.floor(playerLevel / 10)
  else return 10 end
end

function ns.QuestDifficultyColor(questLevel, playerLevel)
  playerLevel = playerLevel or ns.GetPlayerLevel()
  questLevel = questLevel or playerLevel
  local diff = questLevel - playerLevel
  if diff >= 5 then
    return { 1.00, 0.25, 0.25 }, "ffff4040", "Very Hard"
  elseif diff >= 3 then
    return { 1.00, 0.50, 0.25 }, "ffff8040", "Challenging"
  elseif diff >= -2 then
    return { 1.00, 0.90, 0.25 }, "ffffe640", "On Level"
  elseif diff >= -ClassicGreenDelta(playerLevel) then
    return { 0.25, 0.85, 0.35 }, "ff40d959", "Easy"
  else
    return { 0.58, 0.62, 0.68 }, "ff949ead", "Trivial"
  end
end

function ns.GetPlayerQuestLogMap()
  local active = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok and type(n) == "number" then
      for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.title then
          active[info.title:lower()] = info.isComplete and "Ready" or "In Log"
        end
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    local ok, n = pcall(GetNumQuestLogEntries)
    if ok and type(n) == "number" then
      for i = 1, n do
        local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
          active[title:lower()] = (isComplete and isComplete ~= 0) and "Ready" or "In Log"
        end
      end
    end
  end
  return active
end

function ns.GetZoneLiveInfo(zone)
  local guildmates, herbs, ores = {}, {}, {}
  if not zone then return { guildmates = guildmates, herbs = herbs, ores = ores } end

  local zLower = zone.name:lower()
  for name, r in pairs(ns.roster or {}) do
    if r.online and r.zone and r.zone:lower() == zLower then
      guildmates[#guildmates + 1] = {
        name = name,
        level = r.level or 0,
        class = r.class or "",
        classFile = r.classFile,
      }
    end
  end
  table.sort(guildmates, function(a, b) return a.name < b.name end)

  if zone.mapID then
    local function CollectSpots(tbl, dest)
      local mapSpots = tbl and tbl[zone.mapID]
      if not mapSpots then return end
      for itemID, pts in pairs(mapSpots) do
        local itemName = GetItemInfo and GetItemInfo(itemID)
        dest[#dest + 1] = {
          id = itemID,
          name = itemName or ("Item #" .. tostring(itemID)),
          count = #pts,
        }
      end
      table.sort(dest, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
      end)
    end
    CollectSpots(ns.HERB_SPOTS, herbs)
    CollectSpots(ns.ORE_SPOTS, ores)
  end

  return { guildmates = guildmates, herbs = herbs, ores = ores }
end

function ns.SetZoneWaypoint(mapID, x, y, label)
  if not x or not y then return end
  local nx, ny = x / 100, y / 100
  if mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, nx, ny))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
      ns.Print(string.format("Waypoint set: %s (%.1f, %.1f)", label or "Location", x, y))
      return
    end
  end
  if mapID and TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(mapID, nx, ny, { title = label or "EPU Zone Guide" })
    ns.Print(string.format("TomTom waypoint set: %s (%.1f, %.1f)", label or "Location", x, y))
    return
  end
  ns.Print(string.format("%s is at %.1f, %.1f.", label or "Location", x, y))
end

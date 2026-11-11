local _, ns = ...
-- Routable gathering professions: bundled spot table, GatherMate2 database, wording.
local TYPES = {
  [182] = {catalog = "HERB_SPOTS", gatherMate = "Herb Gathering", name = "Herb route", matchNames = true},
  [186] = {catalog = "ORE_SPOTS", gatherMate = "Mining", name = "Ore route"},
}
local ARRIVAL = 12
local route, hud

function ns.GatheringRouteProfession(id)
  return TYPES[id] ~= nil
end

local function Coordinate(value)
  return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value >= 0 and value <= 1
end

local function Position()
  local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
  if not hbd then return end
  -- Position reads can fail in instances and other restricted places: treat that as "unknown".
  local ok, x, y, map = pcall(hbd.GetPlayerZonePosition, hbd)
  if not ok or not (Coordinate(x) and Coordinate(y) and ns.PositiveInt(map)) then return end
  local sized, width, height = pcall(hbd.GetZoneSize, hbd, map)
  if not sized or type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
  return x, y, map, width, height
end

local function Points(map, item, profession)
  local points, seen = {}, {}
  profession = profession or (item and ns.GatherItemProfession(item)) or 182
  local kind = TYPES[profession]
  if not kind then return points end
  local function Add(x, y)
    if not Coordinate(x) or not Coordinate(y) then return end
    local key = math.floor(x * 2000 + .5) * 2001 + math.floor(y * 2000 + .5)
    if seen[key] then return end
    seen[key] = true
    points[#points + 1] = {x = x, y = y}
  end
  local function AddCatalog(catalog)
    for id, spots in pairs((catalog and catalog[map]) or {}) do
      if (item and id == item) or (not item and ns.GatherItemProfession(id) == profession) then
        for _, point in ipairs(spots) do Add(point[1], point[2]) end
      end
    end
  end
  AddCatalog(ns[kind.catalog])
  AddCatalog(ns.cdb and ns.cdb.herbSpots)   -- the member's own recorded spots, herbs and ores alike
  -- GatherMate2 is optional and its API is not ours: a failure there must never break a route.
  local gather = GatherMate2
  if gather and gather.GetNodesForZone and gather.DecodeLoc and (not item or kind.matchNames) then
    pcall(function()
      local name = item and ns.ItemName(item, true)
      for key, node in gather:GetNodesForZone(map, kind.gatherMate, true) do
        if not item or (gather.GetNameForNode and gather:GetNameForNode(kind.gatherMate, node) == name) then
          Add(gather:DecodeLoc(key))
        end
      end
    end)
  end
  return points
end

function ns.GatheringRoutePreview(item, profession)
  local _, _, map = Position()
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return map and Points(map, item, profession) or {}, info and info.name or "this area", map
end

function ns.RecordGatheringSpot(item)
  local x, y, map = Position()
  if not map then return ns.Print("Record gathering spots while outdoors in a zone with map coordinates.") end
  local catalog = ns.cdb.herbSpots or {}
  ns.cdb.herbSpots = catalog
  catalog[map] = catalog[map] or {}
  local spots = catalog[map][item] or {}
  catalog[map][item] = spots
  for _, point in ipairs(spots) do
    if math.abs(point[1] - x) < .002 and math.abs(point[2] - y) < .002 then
      return ns.Print("You already recorded this spot.")
    end
  end
  if #spots >= 1000 then return ns.Print("This material already has 1,000 recorded spots in this zone.") end
  spots[#spots + 1] = {x, y}
  ns.Print("Recorded " .. ns.ItemName(item, true) .. " at your current location.")
end

local function Offset(current, point, x, y)
  return (point.x - x) * current.width, (point.y - y) * current.height
end

local function Stop(message)
  route = nil
  if hud then hud:Hide() end
  if message then ns.Print(message) end
end

local function Next(current, x, y)
  local nearest, distance
  for _, point in ipairs(current.points) do
    if not point.visited then
      local dx, dy = Offset(current, point, x, y)
      local candidate = dx * dx + dy * dy
      if not nearest or candidate < distance then nearest, distance = point, candidate end
    end
  end
  current.target = nearest
  if not nearest then Stop("Route complete.") end
end

local function Advance(current, x, y)
  current.target.visited = true
  current.visited = current.visited + 1
  Next(current, x, y)
end

local function Update()
  local current = route
  if not current then return end
  local x, y, map = Position()
  if map and map ~= current.map then return Stop("Route ended when you left the zone.") end
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not x or (issecretvalue and issecretvalue(facing)) or type(facing) ~= "number" then
    hud.arrow:Hide()
    hud.title:SetText("Waiting for player position")
    return
  end
  local dx, dy = Offset(current, current.target, x, y)
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance <= ARRIVAL then
    Advance(current, x, y)
    if not route then return end
    dx, dy = Offset(current, current.target, x, y)
    distance = math.sqrt(dx * dx + dy * dy)
  end
  local atan2 = math.atan2 or math.atan
  local angle = atan2(-dx, -dy) - facing
  local sin, cos = math.sin(angle), math.cos(angle)
  for _, stroke in ipairs(hud.strokes) do
    stroke.line:SetStartPoint("CENTER", hud.arrow, -12 * sin, 12 * cos)
    stroke.line:SetEndPoint("CENTER", hud.arrow,
      stroke.x * cos - stroke.y * sin, stroke.x * sin + stroke.y * cos)
  end
  hud.arrow:Show()
  hud.title:SetText(string.format("%s · %d yd", current.name, math.floor(distance + .5)))
  hud.progress:SetText(string.format("Recorded spot %d of %d", current.visited + 1, #current.points))
end

local function MakeHUD()
  hud = CreateFrame("Frame", "EPUGuildRouteArrow", UIParent, "BackdropTemplate")
  hud:SetSize(390, 53)
  hud:SetClampedToScreen(true)
  hud:SetMovable(true)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
  hud:SetBackdropColor(.05, .06, .08, .92)
  hud:SetBackdropBorderColor(.65, .48, .22, 1)
  hud:SetScript("OnDragStart", function(self) self:StartMoving() end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    local x, y = self:GetCenter()
    if x and y then ns.cdb.herbArrow = {x / UIParent:GetWidth(), y / UIParent:GetHeight()} end
  end)
  local saved = ns.cdb.herbArrow
  if saved then
    hud:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved[1] * UIParent:GetWidth(), saved[2] * UIParent:GetHeight())
  else
    hud:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
  hud.arrow = CreateFrame("Frame", nil, hud)
  hud.arrow:SetSize(34, 34)
  hud.arrow:SetPoint("LEFT", 8, 0)
  hud.strokes = {}
  for _, endpoint in ipairs({{0, -11}, {-8, 4}, {8, 4}}) do
    local line = hud.arrow:CreateLine(nil, "ARTWORK")
    line:SetColorTexture(1, .78, .24, 1)
    line:SetThickness(4)
    hud.strokes[#hud.strokes + 1] = {line = line, x = endpoint[1], y = endpoint[2]}
  end
  hud.title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hud.title:SetPoint("TOPLEFT", 49, -9)
  hud.progress = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hud.progress:SetPoint("TOPLEFT", 49, -29)
  local function Button(label, width, offset, command)
    local button = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
    button:SetSize(width, 23)
    button:SetPoint("RIGHT", offset, 0)
    button:SetText(label)
    button:SetScript("OnClick", function() ns.GatheringRouteCommand(command) end)
  end
  Button("Next spot", 74, -61, "next")
  Button("Stop", 51, -7, "stop")
  local elapsed = 0
  hud:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < .12 then return end
    elapsed = 0
    Update()
  end)
end

function ns.GatheringRouteCommand(action, item, profession)
  action = (action or ""):lower():match("^%s*(.-)%s*$")
  if action == "stop" then return Stop(route and "Route stopped.") end
  if action == "ore" or action == "ores" or action == "mining" then action, profession = "start", 186 end
  if action == "herb" or action == "herbs" then action, profession = "start", 182 end
  if action == "next" then
    if not route then return ns.Print("Start a route first.") end
    local x, y, map = Position()
    if map == route.map then
      Advance(route, x, y)
      Update()
    end
    return
  end
  if action ~= "" and action ~= "start" then
    return ns.Print("Use /epu route, /epu route ore, /epu route next, or /epu route stop.")
  end
  profession = profession or (item and ns.GatherItemProfession(item)) or 182
  local kind = TYPES[profession]
  if not kind then return ns.Print("Routes cover Herbalism and Mining.") end
  local x, y, map, width, height = Position()
  if not map then return ns.Print("Start a route outdoors in a zone with map coordinates.") end
  local points = Points(map, item, profession)
  if #points == 0 then
    return ns.Print("No recorded spots for this route in your current zone yet. When you find a node, open Market, choose Gather, select the material and press Record spot.")
  end
  if not hud then MakeHUD() end
  route = {map = map, width = width, height = height, points = points, visited = 0,
    name = item and ns.ItemName(item, true) or kind.name}
  Next(route, x, y)
  hud:Show()
  Update()
  return true
end

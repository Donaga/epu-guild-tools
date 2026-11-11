local _, ns = ...
local OWNER = "EPUGuildHerbRoute"
local HERBS = "Herb Gathering"
local ARRIVAL = 22
local route

local function Coordinate(value)
  return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value >= 0 and value <= 1
end

local function Position(hbd)
  local x, y, map = hbd:GetPlayerZonePosition()
  if Coordinate(x) and Coordinate(y) and ns.PositiveInt(map) then return x, y, map end
end

local function DistanceSquared(current, point, x, y)
  local dx, dy = (point.x - x) * current.width, (point.y - y) * current.height
  return dx * dx + dy * dy
end

local function Stop(message)
  if route then
    local previous = route
    route = nil
    previous.nav.Cancel(OWNER)
  end
  if message then ns.Print(message) end
end

local function Next(current, x, y)
  local nearest, distance
  for _, point in ipairs(current.points) do
    if not point.visited then
      local candidate = DistanceSquared(current, point, x, y)
      if not nearest or candidate < distance then nearest, distance = point, candidate end
    end
  end
  if not nearest then
    Stop("Herb route complete. Start another pass when you want to check the spots again.")
    return
  end
  local title = "Recorded herb spot " .. (current.visited + 1) .. "/" .. #current.points
  if current.nav.Navigate(OWNER, current.map, nearest.x, nearest.y, title) then
    current.target = nearest
  else
    Stop("Polestar couldn't open this waypoint. Try starting the herb route again in the zone.")
  end
end

local function Tick(current)
  if route ~= current then return end
  local x, y, map = Position(current.hbd)
  if map and map ~= current.map then
    Stop("Herb route ended when you left the zone. Start a new route in this zone.")
    return
  end
  if x then
    local active, owner = current.nav.Active()
    if active and owner ~= OWNER then
      Stop()
      return
    end
    if DistanceSquared(current, current.target, x, y) <= ARRIVAL * ARRIVAL then
      current.target.visited = true
      current.visited = current.visited + 1
      Next(current, x, y)
    else
      if owner ~= OWNER then
        Stop()
        return
      end
    end
  end
  if route == current then C_Timer.After(1, function() Tick(current) end) end
end

function ns.GatheringRouteCommand(action)
  if action == "stop" then
    Stop(route and "Herb route stopped.")
    return
  end
  if action == "next" then
    if not route then return ns.Print("Start an herb route first.") end
    local x, y, map = Position(route.hbd)
    if map == route.map then
      local active, owner = route.nav.Active()
      if active and owner ~= OWNER then Stop(); return end
      route.target.visited = true
      route.visited = route.visited + 1
      Next(route, x, y)
    end
    return
  end
  if action ~= "" and action ~= "start" then return ns.Print("Use /epu route, /epu route next, or /epu route stop.") end
  local nav = Polestar and Polestar.Nav and Polestar.Nav.API
  if not nav or type(nav.Navigate) ~= "function" or type(nav.Active) ~= "function" or type(nav.Cancel) ~= "function" then
    return ns.Print("Enable Polestar with its navigation module to use the herb route arrow.")
  end
  local ace = LibStub and LibStub("AceAddon-3.0", true)
  local gather = ace and ace:GetAddon("GatherMate2", true)
  if not gather or type(gather.GetNodesForZone) ~= "function" or type(gather.DecodeLoc) ~= "function" then
    return ns.Print("Enable GatherMate2 to route through recorded herb spots.")
  end
  local hbd = LibStub("HereBeDragons-2.0", true)
  if not hbd then return end
  local x, y, map = Position(hbd)
  local width, height
  if map then width, height = hbd:GetZoneSize(map) end
  if not x or not width or not height or width <= 0 or height <= 0 then
    return ns.Print("Start an herb route while outdoors in a zone with map coordinates.")
  end
  local points = {}
  for key in gather:GetNodesForZone(map, HERBS) do
    local px, py = gather:DecodeLoc(key)
    if Coordinate(px) and Coordinate(py) then points[#points + 1] = {x = px, y = py} end
  end
  if #points == 0 then
    return ns.Print("GatherMate2 has no visible recorded herb spots in this zone yet.")
  end
  Stop()
  route = {nav = nav, hbd = hbd, map = map, width = width, height = height, points = points, visited = 0}
  local current = route
  Next(current, x, y)
  if route then
    C_Timer.After(1, function() Tick(current) end)
    ns.Print("Herb route started. Use /epu route next to skip a spot or /epu route stop to end.")
  end
end

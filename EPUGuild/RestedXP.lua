-- EPU Guild Tools: rested XP across your alts.
--
-- The game only tells you rested XP for the character you are logged in on.
-- Each character records its level, XP, rested XP, whether it is resting and
-- when it logged out, so the Personal trackers window (Rested XP tab) can
-- estimate how much every alt has built up since.
--
-- Classic rates: 5% of a level every 8 hours while resting (an inn or a
-- city), a quarter of that anywhere else, up to 1.5 levels' worth.
local _, ns = ...

local REST_RATE = 0.05 / (8 * 3600)   -- share of a level per second, resting
local AWAY_FACTOR = 0.25              -- logged out outside an inn or city
local CAP_LEVELS = 1.5

ns.RESTED_RATE, ns.RESTED_AWAY_FACTOR, ns.RESTED_CAP_LEVELS = REST_RATE, AWAY_FACTOR, CAP_LEVELS

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function RealmName()
  return (GetRealmName and SafeStr(GetRealmName())) or "Realm"
end

-- [realm][character] = { level, xp, xpMax, rested, resting, maxed,
--   classFile, seen, logout }
function ns.RestedDB()
  if not ns.db then return {} end
  ns.db.personalTrackers = ns.db.personalTrackers or {}
  local db = ns.db.personalTrackers
  db.rested = db.rested or {}
  local realm = RealmName()
  db.rested[realm] = db.rested[realm] or {}
  return db.rested[realm], realm
end

-- Save this character's rested state. `loggingOut` stamps the logout time,
-- which is where the estimate for an alt starts counting from.
function ns.RecordRested(loggingOut)
  if not ns.me or not ns.db then return end
  local level = UnitLevel and SafeNum(UnitLevel("player"))
  if not level or level < 1 then return end
  local list = ns.RestedDB()
  local rec = list[ns.me] or {}
  local maxLevel = GetMaxPlayerLevel and SafeNum(GetMaxPlayerLevel()) or 60
  local xpDisabled = IsXPUserDisabled and IsXPUserDisabled() and true or false
  rec.level = level
  rec.xp = UnitXP and SafeNum(UnitXP("player")) or 0
  rec.xpMax = UnitXPMax and SafeNum(UnitXPMax("player")) or 0
  rec.rested = GetXPExhaustion and SafeNum(GetXPExhaustion()) or 0
  rec.resting = IsResting and IsResting() and true or false
  rec.maxed = level >= maxLevel or nil
  rec.xpOff = xpDisabled or nil
  if UnitClass then
    local _, cf = UnitClass("player")
    rec.classFile = SafeStr(cf) or rec.classFile
  end
  local now = time()
  rec.seen = now
  if loggingOut then rec.logout = now else rec.logout = nil end
  list[ns.me] = rec
  return rec
end

-- Estimated rested XP for a saved record at `now`.
-- Returns rested XP, the cap, and seconds until the cap (0 when full).
function ns.EstimateRested(rec, now, live)
  local xpMax = rec and rec.xpMax or 0
  if xpMax <= 0 then return 0, 0, 0 end
  local cap = math.floor(xpMax * CAP_LEVELS)
  local rested = math.min(cap, math.max(0, rec.rested or 0))
  local perSec = xpMax * REST_RATE * (rec.resting and 1 or AWAY_FACTOR)
  if not live then
    local since = rec.logout or rec.seen
    local elapsed = since and math.max(0, (now or time()) - since) or 0
    rested = math.min(cap, rested + math.floor(elapsed * perSec))
  end
  local toFull = rested >= cap and 0 or math.ceil((cap - rested) / perSec)
  return rested, cap, toFull
end

-- This realm's characters, most rested (as a share of a level) first, with
-- max-level characters last.
function ns.RestedAlts(now)
  now = now or time()
  local list = ns.RestedDB()
  local out = {}
  for who, rec in pairs(list) do
    local live = who == ns.me
    local rested, cap, toFull = ns.EstimateRested(rec, now, live)
    out[#out + 1] = {
      name = who, rec = rec, live = live, rested = rested, cap = cap, toFull = toFull,
      pct = (rec.xpMax or 0) > 0 and rested / rec.xpMax or 0,
      done = rec.maxed or rec.xpOff,
    }
  end
  table.sort(out, function(a, b)
    if (a.done and true or false) ~= (b.done and true or false) then return not a.done end
    if a.pct ~= b.pct then return a.pct > b.pct end
    return a.name < b.name
  end)
  return out
end

if ns.On then
  local function Snap() ns.Debounce("restedxp:record", 1, function() ns.RecordRested(false) end) end
  ns.On("PLAYER_LOGIN", function() ns.RecordRested(false) end)
  ns.On("PLAYER_ENTERING_WORLD", Snap)
  ns.On("PLAYER_UPDATE_RESTING", Snap)
  ns.On("UPDATE_EXHAUSTION", Snap)
  ns.On("PLAYER_XP_UPDATE", Snap)
  ns.On("PLAYER_LEVEL_UP", Snap)
  ns.On("PLAYER_LOGOUT", function() ns.RecordRested(true) end)
end

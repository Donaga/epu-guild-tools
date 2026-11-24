-- EPU Guild Tools: guild progress.
-- Each member's dungeon keys, raid attunements, raid status (level, role,
-- Drakefire Amulet, Fire Resistance) and reputation with a few guild-relevant
-- factions, as one guild record per character:
--
--   levelingProgress[who] = { who, t, done = { [id] = true }, camp = { [blueprint] = true },
--                             raid = { level, role, amulet, fireRes },
--                             rep = { [factionID] = { s = standing 1-8, v = into rank, m = rank size } } }
--
-- The record syncs like needed mats: members publish only their own, officers
-- keep everyone's and hand them to whoever logs in later, so a guildmate who
-- was offline (or installed EPU today) still sees who is keyed and attuned.
-- The live "E" (readiness) and "Z" (raid status) messages still go out for
-- guildmates on older versions.
--
-- Keys and raid attunements the game can confirm (an item in your bags or a
-- completed quest) are ticked by themselves, and each new one is a guild
-- milestone (News, and the Discord companion's milestones channel). Custom
-- Forever chains the game can't confirm stay a tick-box.
local ADDON, ns = ...

ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS + 1] = "levelingProgress"
local DAY = 86400
local REFRESH = 7 * DAY      -- owners re-stamp their record at login after this long (lists age out after 30 days)
local MAX_MEMBERS = 1000
local REP_STEP = 500         -- reputation gains smaller than this don't republish on their own

-- Raid attunements. Quest IDs are the classic ones; if Forever changed a
-- chain, ticking it by hand on the Readiness page still works.
ns.RAID_ATTUNEMENTS = {
  { id = "attune_onyxia", name = "Onyxia's Lair", itemID = 16309, quests = { 6502, 6602 },
    note = "Drakefire Amulet: the Alliance chain ends with Drakefire Amulet, the Horde chain with Blood of the Black Dragon Champion. Keep the amulet in your bags." },
  { id = "attune_mc", name = "Molten Core", quests = { 7848 },
    note = "Attunement to the Core: Lothos Riftwaker in Blackrock Mountain, with a Core Fragment from Blackrock Depths." },
  { id = "attune_bwl", name = "Blackwing Lair", quests = { 7761 },
    note = "Blackhand's Command: from Overlord Wyrmthalak in Lower Blackrock Spire, then touch the orb behind General Drakkisath." },
}

-- Factions shown in the guild reputation view (classic faction IDs).
ns.GUILD_REP_FACTIONS = {
  { id = 529, name = "Argent Dawn" },
  { id = 576, name = "Timbermaw Hold" },
  { id = 609, name = "Cenarion Circle" },
  { id = 59, name = "Thorium Brotherhood" },
  { id = 749, name = "Hydraxian Waterlords" },
  { id = 270, name = "Zandalar Tribe" },
  { id = 910, name = "Brood of Nozdormu" },
  { id = 589, name = "Wintersaber Trainers" },
}
local REP_IDS = {}
for _, f in ipairs(ns.GUILD_REP_FACTIONS) do REP_IDS[f.id] = f end
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
function ns.StandingName(s)
  return (s and (_G["FACTION_STANDING_LABEL" .. s] or STANDINGS[s])) or "?"
end
local ROLES = { Tank = true, Healer = true, DPS = true, Melee = true, Caster = true }

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function Int(n, lo, hi) return type(n) == "number" and n == n and n % 1 == 0 and n >= lo and n <= hi end

-- The guild store. Records from before 0.34 have no "who": add it.
local function Store()
  local g = ns.CasualStore and ns.CasualStore()
  local s = g and g.levelingProgress
  if not s then return end
  for who, r in pairs(s) do
    if type(r) == "table" and r.who == nil and type(who) == "string" then r.who = who end
  end
  return s
end
ns.ProgressStore = Store

---------------------------------------------------------------------------
-- Reading this character
---------------------------------------------------------------------------
local function HasItem(id)
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not id or not count then return false end
  local ok, n = pcall(count, id, false)
  return ok and type(n) == "number" and n > 0
end

local function QuestDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    if ok then return done == true end
  end
  if IsQuestFlaggedCompleted then
    local ok, done = pcall(IsQuestFlaggedCompleted, id)
    return ok and done == true
  end
  return false
end

local function ReadFaction(id)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(d) == "table" and d.reaction then
      return d.reaction, d.currentStanding, d.currentReactionThreshold, d.nextReactionThreshold
    end
  end
  if GetFactionInfoByID then
    local ok, name, _, standing, barMin, barMax, barValue = pcall(GetFactionInfoByID, id)
    if ok and name then return standing, barValue, barMin, barMax end
  end
end

function ns.ShareRep()
  return not (ns.cdb and ns.cdb.progressShareRep == false)
end
function ns.SetShareRep(on)
  if not ns.cdb then return end
  ns.cdb.progressShareRep = on and true or false
  ns.MarkProgressChanged()
  ns.PublishProgress()
end

local function RepSnapshot()
  local out = {}
  if not ns.ShareRep() then return out end
  for _, f in ipairs(ns.GUILD_REP_FACTIONS) do
    local s, value, lo, hi = ReadFaction(f.id)
    s, value, lo, hi = tonumber(s), tonumber(value), tonumber(lo), tonumber(hi)
    if s and value and lo and hi and Int(s, 1, 8) then
      local v, m = math.floor(value - lo), math.floor(hi - lo)
      if m < 0 then m = 0 end
      if v < 0 then v = 0 elseif v > m then v = m end
      -- Neutral with nothing earned is what the game reports for a faction you never met.
      if not (s == 4 and v == 0) then out[f.id] = { s = s, v = v, m = m } end
    end
  end
  return out
end

local function RaidSnapshot()
  local st = ns.GetMyRaidStatus and ns.GetMyRaidStatus()
  if type(st) ~= "table" then return nil end
  local role = ROLES[st.role] and st.role or "DPS"
  return { level = math.floor(tonumber(st.level) or 1), role = role, amulet = st.amulet and true or false,
    fireRes = math.max(0, math.min(2000, math.floor(tonumber(st.fireRes) or 0))) }
end

local function RaidChanged(a, b)
  if not a or not b then return a ~= b end
  return a.level ~= b.level or a.role ~= b.role or a.amulet ~= b.amulet or a.fireRes ~= b.fireRes
end

local function RepChanged(old, new)
  old, new = old or {}, new or {}
  for id, e in pairs(new) do
    local o = old[id]
    if not o or o.s ~= e.s or math.abs((o.v or 0) - e.v) >= REP_STEP then return true end
  end
  for id in pairs(old) do if not new[id] then return true end end
  return false
end

---------------------------------------------------------------------------
-- Publishing this character's record
---------------------------------------------------------------------------
local dirty = false
function ns.MarkProgressChanged() dirty = true end

local function Own()
  local store = Store()
  if not store or not ns.me then return end
  local cur = store[ns.me]
  if type(cur) ~= "table" then cur = { who = ns.me, done = {}, camp = {}, t = 0 }; store[ns.me] = cur end
  cur.who, cur.done, cur.camp = ns.me, cur.done or {}, cur.camp or {}
  return cur
end
ns.OwnProgress = Own

local function Copy(r)
  local done, camp, rep = {}, {}, {}
  for k, v in pairs(r.done or {}) do done[k] = v end
  for k, v in pairs(r.camp or {}) do camp[k] = v end
  for k, v in pairs(r.rep or {}) do rep[k] = { s = v.s, v = v.v, m = v.m } end
  local raid = r.raid and { level = r.raid.level, role = r.raid.role, amulet = r.raid.amulet, fireRes = r.raid.fireRes }
  return { who = r.who, t = r.t, done = done, camp = camp, raid = raid, rep = rep }
end

-- announce: resend an unchanged record (at login, for guildmates who missed it)
-- noLive: skip the live messages for older versions (login and first-scan
-- publishes, so a login adds one message, not three)
function ns.PublishProgress(announce, noLive)
  local cur = Own()
  if not cur then return end
  local raid, rep = RaidSnapshot(), RepSnapshot()
  local raidChanged = RaidChanged(cur.raid, raid)
  local changed = dirty or raidChanged or RepChanged(cur.rep, rep) or ns.Now() - (tonumber(cur.t) or 0) >= REFRESH
  if not changed then
    if announce and (tonumber(cur.t) or 0) > 0 then ns.Send("D", { levelingProgress = { [ns.me] = Copy(cur) } }) end
    return
  end
  dirty = false
  cur.raid, cur.rep = raid, rep
  cur.t = ns.NextVersion(cur.t)
  ns.Send("D", { levelingProgress = { [ns.me] = Copy(cur) } })
  -- Guildmates on 0.33 and older only hear the live messages.
  if not noLive then
    ns.Send("E", { who = ns.me, done = cur.done, camp = cur.camp, t = cur.t })
    if raidChanged and ns.SyncMyRaidStatus then ns.SyncMyRaidStatus(true) end
  end
  ns.Changed()
end

---------------------------------------------------------------------------
-- Merging records from guildmates
---------------------------------------------------------------------------
local function CleanSet(t, maxLen, maxN)
  if t == nil then return {} end
  if type(t) ~= "table" then return end
  local out, n = {}, 0
  for k, v in pairs(t) do
    n = n + 1
    if n > maxN or type(k) ~= "string" or #k > maxLen or k:find("[%c|]") or v ~= true then return end
    out[k] = true
  end
  return out
end

local function CleanRaid(r)
  if r == nil then return nil, true end
  if type(r) ~= "table" or not Int(r.level, 1, 100) or not ROLES[r.role] or type(r.amulet) ~= "boolean"
    or not Int(r.fireRes, 0, 2000) then return nil, false end
  return { level = r.level, role = r.role, amulet = r.amulet, fireRes = r.fireRes }, true
end

local function CleanRep(r)
  if r == nil then return {} end
  if type(r) ~= "table" then return end
  local out, n = {}, 0
  for id, e in pairs(r) do
    n = n + 1
    if n > 20 or not REP_IDS[id] or type(e) ~= "table" or not Int(e.s, 1, 8) or not Int(e.m, 0, 100000)
      or not Int(e.v, 0, math.max(e.m, 0)) then return end
    out[id] = { s = e.s, v = e.v, m = e.m }
  end
  return out
end

local function Clean(who, r)
  local done, camp, rep = CleanSet(r.done, 60, 200), CleanSet(r.camp, 80, 200), CleanRep(r.rep)
  local raid, raidOk = CleanRaid(r.raid)
  if not done or not camp or not rep or not raidOk then return end
  return { who = who, t = r.t, done = done, camp = camp, raid = raid, rep = rep }
end

function ns.MergeLevelingProgress(sender, b, trusted)
  if type(b) ~= "table" or type(b.levelingProgress) ~= "table" then return false end
  local store = Store()
  if not store then return false end
  sender = ns.Short(sender)
  local size, changed = Count(store), false
  for who, r in pairs(b.levelingProgress) do
    if type(who) == "string" and #who <= 80 and type(r) == "table" and r.who == who
      and (trusted or who == sender) and ns.StampOK(r.t) and r.t <= ns.Now() + 300 then
      local clean = Clean(who, r)
      local cur = store[who]
      if clean and (cur or size < MAX_MEMBERS) and ns.Newer(clean, cur, "t") then
        store[who] = clean
        if not cur then size = size + 1 end
        changed = true
      end
    end
  end
  if changed then ns.Changed() end
  return changed
end

---------------------------------------------------------------------------
-- Keys and attunements the game can confirm
---------------------------------------------------------------------------
local function Plain(name) return (tostring(name or ""):gsub("%s*%(Forever%)", "")) end

-- quiet: tick what's found without a milestone (the first scan after install,
-- so nobody's existing keys flood News and Discord).
-- noLive: see ns.PublishProgress.
function ns.DetectProgress(quiet, noLive)
  local cur = Own()
  if not cur then return 0 end
  if not ns.cdb or not ns.cdb.progressScanned then quiet, noLive = true, true end
  local found = {}
  for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
    if d.keyItemID and not cur.done[d.id] and HasItem(d.keyItemID) then
      found[#found + 1] = { id = d.id, text = "picked up the key for " .. Plain(d.name) }
    end
  end
  for _, a in ipairs(ns.RAID_ATTUNEMENTS) do
    if not cur.done[a.id] then
      local ok = a.itemID and HasItem(a.itemID)
      for _, q in ipairs(a.quests or {}) do if not ok and QuestDone(q) then ok = true end end
      if ok then found[#found + 1] = { id = a.id, text = "is attuned to " .. a.name } end
    end
  end
  for _, f in ipairs(found) do
    cur.done[f.id] = true
    if not quiet and ns.AddFeed then ns.AddFeed("attune", f.text, ns.me, "att:" .. ns.me .. ":" .. f.id) end
  end
  if ns.cdb then ns.cdb.progressScanned = true end
  if #found > 0 then dirty = true; ns.PublishProgress(nil, noLive) end
  return #found
end

function ns.IsAttuned(id, who)
  local store = Store() or {}
  local r = store[who or ns.me]
  return r and r.done and r.done[id] == true or false
end

-- Guildmates with a raid attunement, and level 55+ guildmates without it.
function ns.GetGuildAttunement(id)
  local store = Store() or {}
  local done, missing = {}, {}
  for who, r in pairs(ns.roster or {}) do
    local rec = store[who]
    if rec and rec.done and rec.done[id] then
      done[#done + 1] = { name = who, level = r.level or 0, online = r.online }
    elseif (r.level or 0) >= 55 then
      missing[#missing + 1] = { name = who, level = r.level or 0, online = r.online }
    end
  end
  local function order(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online end
    return a.name < b.name
  end
  table.sort(done, order); table.sort(missing, order)
  return done, missing
end

-- Guildmates' standing with one faction, best first.
function ns.GetGuildRep(factionID)
  local store, out = Store() or {}, {}
  for who, rec in pairs(store) do
    local e = type(rec) == "table" and type(rec.rep) == "table" and rec.rep[factionID]
    if e and ns.InGuild and ns.InGuild(who) then
      local r = ns.roster and ns.roster[who]
      out[#out + 1] = { name = who, s = e.s, v = e.v, m = e.m, online = r and r.online, at = rec.t }
    end
  end
  table.sort(out, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    if a.v ~= b.v then return a.v > b.v end
    return a.name < b.name
  end)
  return out
end

---------------------------------------------------------------------------
-- When to look
---------------------------------------------------------------------------
ns.On("PLAYER_LOGIN", function()
  local tries = 0
  local function start()
    tries = tries + 1
    if not ns.G() or (not (ns.IsSynced and ns.IsSynced()) and tries < 6) then
      if tries < 12 then C_Timer.After(30, start) end
      return
    end
    if ns.DetectProgress(false, true) == 0 then ns.PublishProgress(true, true) end
  end
  C_Timer.After(40, start)
end)
ns.On("QUEST_TURNED_IN", function() C_Timer.After(2, function() ns.DetectProgress() end) end)
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("progressDetect", 5, function() ns.DetectProgress() end) end)
ns.On("PLAYER_LEVEL_UP", function() ns.Debounce("progressPublish", 10, function() ns.PublishProgress() end) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Debounce("progressGear", 30, function() ns.PublishProgress() end) end)
ns.On("UPDATE_FACTION", function() ns.Debounce("progressRep", 300, function() ns.PublishProgress() end) end)

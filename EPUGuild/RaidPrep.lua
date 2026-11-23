-- EPU Guild Tools: WoW: Forever Dec 9 Raid Readiness, 10/20/40 Squad Builder,
-- Drakefire Amulet / Fire Resistance Tracker, and Consumable Bank Prep.
local _, ns = ...
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

ns.FOREVER_RAIDS = {
  {
    id = "barrow_deeps", name = "Barrow Deeps", size = 10, bosses = 8,
    attunement = "None required (Level 60)",
    location = "Mount Hyjal / Winterspring / Blackmaw Hold entrances",
    notes = "First-stop 10-player raid. No classic world buffs inside Forever raids; bring Protection Potions & Flasks.",
  },
  {
    id = "hyjal_summit", name = "Hyjal Summit", size = 20, bosses = 13,
    attunement = "None required (Level 60)",
    location = "Nordrassil, Mount Hyjal",
    notes = "20-player raid with branching paths. Coordinate raid-wide buffs and Nature/Shadow protection.",
  },
  {
    id = "onyxias_lair", name = "Onyxia's Lair", size = 40, bosses = 1,
    attunement = "Drakefire Amulet (mandatory in bags per character)",
    attuneItemID = 16309,
    location = "Dustwallow Marsh (52.6, 76.2)",
    notes = "Stack Fire Resistance gear & Greater Fire Protection Potions for Phase 2/3.",
  },
}

ns.RAID_CONSUMABLES = {
  { name = "Greater Fire Protection Potion", itemID = 13457, use = "Onyxia's Lair / Fire bosses" },
  { name = "Greater Nature Protection Potion", itemID = 13458, use = "Barrow Deeps / Hyjal Summit" },
  { name = "Greater Shadow Protection Potion", itemID = 13459, use = "Hyjal Summit / Shadow bosses" },
  { name = "Flask of the Titans", itemID = 13510, use = "Tanks (+1200 HP, persists through death)" },
  { name = "Flask of Distilled Wisdom", itemID = 13511, use = "Healers (+2000 Mana)" },
  { name = "Flask of Supreme Power", itemID = 13512, use = "Casters (+150 Spell Power)" },
  { name = "Elixir of the Mongoose", itemID = 13452, use = "Physical DPS (+25 Agi, +2% Crit)" },
  { name = "Greater Arcane Elixir", itemID = 13454, use = "Caster DPS (+35 Spell Power)" },
}

-- "K" is the quest list kind (QuestMatching.lua), so raid prep uses its own.
local RAID_KIND = "Z"
local function RaidStore()
  local g = ns.G and ns.G()
  if not g then return end
  g.raidPrep = g.raidPrep or {}
  return g.raidPrep
end

function ns.GetMyRaidStatus()
  local hasAmulet = false
  if GetItemCount then
    local ok, cnt = pcall(GetItemCount, 16309, false)
    hasAmulet = ok and type(cnt) == "number" and cnt > 0
  end
  local fireRes = 0
  if UnitResistance then
    local ok, _, total = pcall(UnitResistance, "player", 2)
    if ok and type(total) == "number" then fireRes = total end
  end
  local role = (ns.PlayerGearRole and ns.PlayerGearRole()) or "DPS"
  local lv = (ns.GetPlayerLevel and ns.GetPlayerLevel()) or 1
  return {
    who = ns.me,
    level = lv,
    role = role,
    amulet = hasAmulet,
    fireRes = fireRes,
    t = ns.Now and ns.Now() or time(),
  }
end

function ns.SyncMyRaidStatus()
  local store = RaidStore()
  if not store or not ns.me then return end
  local st = ns.GetMyRaidStatus()
  store[ns.me] = st
  if ns.Send then ns.Send(RAID_KIND, st) end
  return st
end

ns.comm[RAID_KIND] = function(sender, st, channel)
  if channel ~= "GUILD" or type(st) ~= "table" then return end
  -- Only the sender's own record: a member can't rewrite someone else's.
  local who = ns.Member and ns.Member(sender)
  if not who then return end
  local now = ns.Now and ns.Now() or time()
  if tonumber(st.t) and tonumber(st.t) > now + 300 then return end
  local store = RaidStore()
  if not store then return end
  local cur = store[who]
  if cur and (cur.t or 0) >= (st.t or 0) then return end
  store[who] = {
    who = who,
    level = tonumber(st.level) or 0,
    role = type(st.role) == "string" and st.role or "DPS",
    amulet = st.amulet and true or false,
    fireRes = tonumber(st.fireRes) or 0,
    t = tonumber(st.t) or (ns.Now and ns.Now() or time()),
  }
end

function ns.GetRaidRosterReport()
  local store = RaidStore() or {}
  local ready, attuneMissing = {}, {}
  for who, r in pairs(ns.roster or {}) do
    local lv = r.level or 1
    if lv >= 55 then
      local rs = store[who]
      local role = (rs and rs.role) or "DPS"
      local g = ns.G and ns.G()
      local prof = g and g.profiles and g.profiles[who]
      -- Profiles keep roles as letters: "t", "h", "d" (see ns.SetProfile).
      local pr = prof and type(prof.roles) == "string" and prof.roles or ""
      if pr:find("t", 1, true) then role = "Tank"
      elseif pr:find("h", 1, true) then role = "Healer"
      elseif pr:find("d", 1, true) then role = "DPS" end
      local entry = {
        name = who,
        level = lv,
        online = r.online and true or false,
        role = role,
        amulet = rs and rs.amulet or false,
        fireRes = rs and rs.fireRes or 0,
      }
      ready[#ready + 1] = entry
      if not entry.amulet then
        attuneMissing[#attuneMissing + 1] = entry
      end
    end
  end
  table.sort(ready, function(a, b)
    if a.online ~= b.online then return a.online end
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
  end)
  return ready, attuneMissing
end

-- Auto-split raid-ready members (Lv 58+) into balanced 10, 20, or 40-man squads
function ns.BuildRaidSquads(squadSize)
  squadSize = squadSize or 10
  local all = ns.GetRaidRosterReport()
  local pool = {}
  for _, m in ipairs(all) do
    if m.level >= 58 then pool[#pool + 1] = m end
  end
  local numSquads = math.max(1, math.ceil(#pool / squadSize))
  local squads = {}
  for i = 1, numSquads do
    squads[i] = { index = i, tanks = {}, healers = {}, dps = {}, members = {} }
  end

  local tanks, healers, dps = {}, {}, {}
  for _, m in ipairs(pool) do
    if m.role == "Tank" then tanks[#tanks + 1] = m
    elseif m.role == "Healer" then healers[#healers + 1] = m
    else dps[#dps + 1] = m end
  end

  local function Distribute(list, bucket)
    local idx = 1
    for _, m in ipairs(list) do
      local placed = false
      for _ = 1, numSquads do
        local sq = squads[idx]
        idx = (idx % numSquads) + 1
        if #sq.members < squadSize then
          sq[bucket][#sq[bucket] + 1] = m
          sq.members[#sq.members + 1] = m
          placed = true
          break
        end
      end
      if not placed then
        local sq = squads[#squads]
        sq[bucket][#sq[bucket] + 1] = m
        sq.members[#sq.members + 1] = m
      end
    end
  end

  Distribute(tanks, "tanks")
  Distribute(healers, "healers")
  Distribute(dps, "dps")
  return squads, #pool
end

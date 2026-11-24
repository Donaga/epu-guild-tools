-- EPU Guild Tools: WoW: Forever Leveling Advisor, Dungeon Readiness & Keys,
-- 12-Level Trivial-XP Guard, and Waylaid Crates / Craftsman's Writs Helper.
local _, ns = ...
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

ns.SUPPLY_HUBS = {
  Alliance = {
    name = "Three Corners (Azeroth Commerce Authority)",
    zone = "Redridge / Elwynn / Duskwood border",
    mapID = 1433, x = 14.5, y = 76.0,
    note = "Turn in filled Waylaid Crates & Craftsman's Writs for Merchant's Favor.",
  },
  Horde = {
    name = "Crossroads Supply Camp (Durotar Supply and Logistics)",
    zone = "The Barrens (west of Crossroads)",
    mapID = 1413, x = 50.2, y = 30.8,
    note = "Turn in filled Waylaid Crates & Craftsman's Writs for Merchant's Favor.",
  },
}

-- Common leveling/quest bottleneck items crafted by guildmates
ns.QUEST_BOTTLENECKS = {
  { name = "Elixir of Water Breathing", itemID = 5996, prof = "Alchemy", usedIn = "Shimmering Flats / Deep Ocean / Underwater quests" },
  { name = "Frost Oil", itemID = 3829, prof = "Alchemy", usedIn = "Badlands (Coolant Heads Prevail) & Frost quests" },
  { name = "Bronze Tube", itemID = 4371, prof = "Engineering", usedIn = "Duskwood (Look To The Stars) & Gnomeregan" },
  { name = "Deadly Blunderbuss", itemID = 4369, prof = "Engineering", usedIn = "Ashenvale / Stonetalon quests" },
  { name = "Patterned Bronze Bracers", itemID = 2868, prof = "Blacksmithing", usedIn = "Badlands (The Absent Minded Prospector / Barbecued Buzzard)" },
  { name = "Gyrochronatom", itemID = 4389, prof = "Engineering", usedIn = "Badlands (Study of the Elements) & high-level quests" },
  { name = "Mithril Casing", itemID = 10561, prof = "Engineering", usedIn = "Un'Goro / Tanaris / Gadgetzan quests" },
  { name = "Healing Potion", itemID = 929, prof = "Alchemy", usedIn = "General leveling & Waylaid Crates" },
}

-- Dungeon Readiness: Forever custom dungeons + Classic key/attunement dungeons
ns.DUNGEON_READINESS = {
  { id = "hall_of_thanes", name = "Hall of Thanes (Forever)", levelRange = {13, 18}, zone = "Ironforge", mapID = 1455, x = 43.5, y = 52.0, faction = "Alliance",
    key = "None", quests = {
      { name = "Check Ironforge / Dun Morogh hubs before entering", level = 15, faction = "Alliance", giver = "Ironforge", x = 55.5, y = 47.8 },
    }},
  { id = "ruins_of_lordaeron", name = "Ruins of Lordaeron (Forever)", levelRange = {15, 20}, zone = "Tirisfal Glades", mapID = 1420, x = 61.8, y = 65.0, faction = "Horde",
    key = "None", quests = {
      { name = "Check Brill / Undercity hubs before entering", level = 17, faction = "Horde", giver = "Tirisfal Glades", x = 61.8, y = 65.0 },
    }},
  { id = "deadmines", name = "The Deadmines", levelRange = {17, 26}, zone = "Westfall", mapID = 1436, x = 42.5, y = 71.7, faction = "Alliance",
    key = "None", quests = {
      { name = "The Defias Brotherhood", level = 22, faction = "Alliance", giver = "Gryan Stoutmantle", x = 56.3, y = 47.5 },
      { name = "Red Silk Bandanas", level = 17, faction = "Alliance", giver = "Scout Riell", x = 56.7, y = 47.4 },
      { name = "Collecting Memories / Oh Brother...", level = 18, faction = "Alliance", mapID = 1453, giver = "Stormwind (Dwarven District)", x = 54.0, y = 18.0 },
    }},
  { id = "wailing_caverns", name = "Wailing Caverns", levelRange = {17, 24}, zone = "The Barrens", mapID = 1413, x = 46.0, y = 36.4, faction = "Neutral",
    key = "None", quests = {
      { name = "Leaders of the Fang", level = 22, faction = "Horde", mapID = 1456, giver = "Nara Wildmane (Thunder Bluff)", x = 75.6, y = 31.2 },
      { name = "Deviate Eradication", level = 21, faction = "Neutral", giver = "Ebru (Above WC cave)", x = 46.0, y = 35.8 },
      { name = "Smart Drinks", level = 18, faction = "Neutral", giver = "Mebok Mizzyrix (Ratchet)", x = 62.4, y = 37.6 },
    }},
  { id = "excavation_site", name = "Excavation Site (Forever)", levelRange = {24, 29}, zone = "Wetlands", mapID = 1437, x = 38.0, y = 49.0, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Menethil Harbor / Whelgar's Excavation Site", level = 26, faction = "Alliance", giver = "Menethil Harbor", x = 10.0, y = 59.0 },
    }},
  { id = "city_of_dalaran", name = "City of Dalaran (Forever)", levelRange = {28, 33}, zone = "Alterac Mountains", mapID = 1416, x = 20.0, y = 84.0, faction = "Neutral",
    key = "Dalaran Attunement Chain (Unstable Arcane Barrier)", quests = {
      { name = "Complete the Dalaran Arcane Barrier attunement chain first", level = 28, faction = "Neutral", giver = "Alterac / Hillsbrad hub", x = 20.0, y = 84.0 },
    }},
  { id = "gnomeregan", name = "Gnomeregan", levelRange = {29, 38}, zone = "Dun Morogh", mapID = 1426, x = 24.3, y = 39.8, faction = "Neutral",
    key = "Workshop Key (back door shortcut)", keyItemID = 6893, quests = {
      { name = "Save Techbot's Brain!", level = 26, faction = "Alliance", mapID = 1455, giver = "Tinkmaster Overspark (Ironforge)", x = 69.8, y = 50.2 },
      { name = "Rig Wars", level = 35, faction = "Horde", mapID = 1454, giver = "Nogg (Orgrimmar)", x = 75.8, y = 25.2 },
    }},
  { id = "scarlet_monastery", name = "Scarlet Monastery", levelRange = {29, 44}, zone = "Tirisfal Glades", mapID = 1420, x = 84.9, y = 32.8, faction = "Neutral",
    key = "The Scarlet Key (Armory & Cathedral)", keyItemID = 7146, quests = {
      { name = "In the Name of the Light", level = 40, faction = "Alliance", mapID = 1424, giver = "Raleigh the Devout (Southshore)", x = 51.4, y = 58.6 },
      { name = "Into The Scarlet Monastery", level = 38, faction = "Horde", mapID = 1458, giver = "Varimathras (Undercity)", x = 56.2, y = 92.2 },
    }},
  { id = "drowned_city", name = "The Drowned City (Forever)", levelRange = {35, 40}, zone = "Stranglethorn Vale", mapID = 1434, x = 21.4, y = 27.9, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Booty Bay / Grom'gol / Rebel Camp for Naga ruin quests", level = 37, faction = "Neutral", giver = "Booty Bay", x = 27.5, y = 77.5 },
    }},
  { id = "kroldok_stronghold", name = "Krol'dok Stronghold (Forever)", levelRange = {40, 45}, zone = "Riverglades", mapID = 2548, x = 37.5, y = 37.5, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Riverglades outposts before entering", level = 42, faction = "Neutral", giver = "Riverglades", x = 58.0, y = 45.8 },
    }},
  { id = "zulfarrak", name = "Zul'Farrak", levelRange = {44, 54}, zone = "Tanaris", mapID = 1446, x = 38.7, y = 20.0, faction = "Neutral",
    key = "Mallet of Zul'Farrak (summons Gahz'rilla)", keyItemID = 9240, quests = {
      { name = "Gahz'rilla (Carrot on a Stick!)", level = 50, faction = "Neutral", mapID = 1441, giver = "Wizzle Brassbolts (Shimmering Flats)", x = 78.0, y = 77.1 },
      { name = "Scarab Shells", level = 45, faction = "Neutral", giver = "Tran'rek (Gadgetzan)", x = 51.6, y = 26.8 },
      { name = "Divino-matic Rod", level = 47, faction = "Neutral", giver = "Chief Engineer Bilgewhizzle", x = 52.5, y = 28.5 },
    }},
  { id = "alcaz_prison", name = "Alcaz Prison (Forever)", levelRange = {48, 53}, zone = "Dustwallow Marsh", mapID = 1445, x = 77.0, y = 17.5, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Theramore / Brackenwall Village before sailing to Alcaz", level = 50, faction = "Neutral", giver = "Dustwallow Marsh", x = 67.5, y = 51.3 },
    }},
  { id = "blackrock_depths", name = "Blackrock Depths", levelRange = {52, 60}, zone = "Searing Gorge", mapID = 1427, x = 34.8, y = 85.4, faction = "Neutral",
    key = "Shadowforge Key (inner shortcuts)", keyItemID = 11000, quests = {
      { name = "Attunement to the Core (MC attune)", level = 60, faction = "Neutral", giver = "Lothos Riftwaker (BRM)", x = 34.8, y = 85.4 },
      { name = "The Princess Saved? / Marshal Windsor", level = 58, faction = "Alliance", mapID = 1428, giver = "Morgan's Vigil", x = 84.3, y = 68.3 },
    }},
  { id = "blackmaw_hold", name = "Blackmaw Hold (Forever)", levelRange = {55, 60}, zone = "Azshara", mapID = 1447, x = 38.4, y = 32.6, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Azshara hubs / Timbermaw quests before entering", level = 57, faction = "Neutral", giver = "Azshara", x = 22.0, y = 49.6 },
    }},
  { id = "shapers_terrace", name = "Shaper's Terrace (Forever)", levelRange = {58, 60}, zone = "Un'Goro Crater", mapID = 1449, x = 48.1, y = 6.1, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Marshal's Refuge before entering Shaper's Terrace", level = 59, faction = "Neutral", giver = "Marshal's Refuge", x = 45.2, y = 5.8 },
    }},
  { id = "dire_maul", name = "Dire Maul", levelRange = {55, 60}, zone = "Feralas", mapID = 1444, x = 59.0, y = 41.8, faction = "Neutral",
    key = "Crescent Key (West & North wings)", keyItemID = 18249, quests = {
      { name = "Elven Legends", level = 58, faction = "Neutral", giver = "Scholar Runethorn", x = 31.2, y = 43.9 },
    }},
  { id = "scholomance", name = "Scholomance", levelRange = {58, 60}, zone = "Western Plaguelands", mapID = 1422, x = 69.0, y = 73.0, faction = "Neutral",
    key = "Skeleton Key (front gate)", keyItemID = 13704, quests = {
      { name = "Scholomance (Key Chain)", level = 58, faction = "Neutral", giver = "Chillwind Camp / The Bulwark", x = 42.7, y = 84.0 },
    }},
  { id = "stratholme", name = "Stratholme", levelRange = {58, 60}, zone = "Eastern Plaguelands", mapID = 1423, x = 31.2, y = 13.8, faction = "Neutral",
    key = "Key to the City (Service Gate)", keyItemID = 12382, quests = {
      { name = "The Active Agent", level = 60, faction = "Neutral", giver = "Betina Bigglezink (Light's Hope)", x = 81.4, y = 59.8 },
    }},
  { id = "ubrs", name = "Upper Blackrock Spire (UBRS)", levelRange = {58, 60}, zone = "Burning Steppes", mapID = 1428, x = 29.0, y = 37.5, faction = "Neutral",
    key = "Seal of Ascension (opens UBRS door)", keyItemID = 12344, quests = {
      { name = "Blackhand's Command (BWL attunement)", level = 60, faction = "Neutral", giver = "Scarshield Quartermaster", x = 29.0, y = 37.5 },
    }},
}

function ns.HasKeyItem(itemID)
  if not itemID or not GetItemCount then return false end
  local ok, count = pcall(GetItemCount, itemID, false)
  return ok and type(count) == "number" and count > 0
end

-- 12-level Trivial-XP Guard (WoW: Forever Nov 13 rule:
-- a kill gives the party zero XP if trivial — 12+ levels below a party member).
function ns.CheckTrivialXP(targetMinLevel, targetMaxLevel)
  local members = {}
  local myName = ns.me or (UnitName and UnitName("player")) or "You"
  local myLevel = ns.GetPlayerLevel and ns.GetPlayerLevel() or 1
  members[#members + 1] = { name = myName, level = myLevel }

  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n > 0 then
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    local limit = prefix == "raid" and n or (n - 1)
    for i = 1, limit do
      local unit = prefix .. i
      if UnitExists and UnitExists(unit) then
        local lv = UnitLevel and UnitLevel(unit) or 0
        local nm = (ns.UnitFullName and ns.UnitFullName(unit)) or (UnitName and UnitName(unit)) or unit
        if lv and lv > 0 and nm ~= myName then
          members[#members + 1] = { name = nm, level = lv }
        end
      end
    end
  end

  local hi, lo = members[1], members[1]
  for _, m in ipairs(members) do
    if m.level > hi.level then hi = m end
    if m.level < lo.level then lo = m end
  end

  local gap = ns.FOREVER_PARTY_TRIVIAL_GAP or 12
  local warnings = {}
  if targetMaxLevel and (hi.level - targetMaxLevel) >= gap then
    warnings[#warnings + 1] = string.format(
      "%s (Lv %d) is %d+ levels above this dungeon's max level (%d) — kills may grant ZERO XP to the party!",
      hi.name, hi.level, hi.level - targetMaxLevel, targetMaxLevel
    )
  end
  if #members > 1 and (hi.level - lo.level) >= gap then
    warnings[#warnings + 1] = string.format(
      "Party spread is %d levels (%s Lv %d vs %s Lv %d) — mobs on-level for %s will be trivial (0 XP)!",
      hi.level - lo.level, hi.name, hi.level, lo.name, lo.level, lo.name
    )
  end
  return {
    members = members,
    highest = hi,
    lowest = lo,
    warnings = warnings,
    ok = #warnings == 0,
  }
end

-- Check guild bank stock & guild crafters for an item
function ns.CheckGuildStockAndCrafters(itemName, itemID)
  local bankQty, crafters = 0, {}
  local g = ns.G and ns.G()
  -- Bank snapshots keep a plain count per item: g.bank[alt].items[id] = n.
  if g and g.bank and itemID then
    for _, b in pairs(g.bank) do
      if type(b) == "table" and type(b.items) == "table" then
        bankQty = bankQty + (tonumber(b.items[itemID]) or 0)
      end
    end
  end
  -- Crafters come from the shared recipe index (Data.lua), by item, then by name.
  local entry = itemID and ns.RecipeFor and ns.RecipeFor("item:" .. itemID)
  if not entry and itemName and itemName ~= "" and ns.RecipeByName then entry = ns.RecipeByName(itemName) end
  local seen = {}
  for _, c in ipairs(entry and entry.crafters or {}) do
    if not seen[c.who] then
      seen[c.who] = true
      local online = ns.roster and ns.roster[c.who] and ns.roster[c.who].online
      crafters[#crafters + 1] = { name = c.who, online = online and true or false }
    end
  end
  table.sort(crafters, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  return bankQty, crafters
end

-- Scan bags for Waylaid Crates, Craftsman's Writs, Shipping Labels
function ns.ScanBagCratesAndWrits()
  local found = {}
  local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local getLink = GetContainerItemLink
  if not getSlots then return found end

  for bag = 0, 4 do
    local ok, slots = pcall(getSlots, bag)
    if ok and type(slots) == "number" and slots > 0 then
      for slot = 1, slots do
        local link, count
        if getInfo then
          local info = getInfo(bag, slot)
          if info then link, count = info.hyperlink, info.stackCount end
        elseif getLink then
          link = getLink(bag, slot)
          count = 1
        end
        if link then
          local itemName = link:match("%[(.-)%]") or ""
          local low = itemName:lower()
          local kind
          if low:find("waylaid", 1, true) then kind = "Waylaid Crate"
          elseif low:find("craftsman's writ", 1, true) or low:find("sealed writ", 1, true) then kind = "Craftsman's Writ"
          elseif low:find("shipping label", 1, true) then kind = "Shipping Label (+2,000 Rep!)"
          end
          if kind then
            local target = itemName:match(":%s*(.+)$")
            found[#found + 1] = {
              name = itemName,
              link = link,
              kind = kind,
              target = target,
              count = count or 1,
              bag = bag,
              slot = slot,
            }
          end
        end
      end
    end
  end
  return found
end

function ns.GetWritCooldowns()
  if not ns.cdb then return {} end
  ns.cdb.writCooldowns = ns.cdb.writCooldowns or {}
  return ns.cdb.writCooldowns
end

function ns.RecordWritCooldown(name)
  if not name or name == "" then return end
  local cd = ns.GetWritCooldowns()
  cd[name] = time() + 20 * 3600
end

function ns.GetLevelingAdvice()
  local pLevel = ns.GetPlayerLevel and ns.GetPlayerLevel() or 1
  local pFaction = ns.GetPlayerFaction and ns.GetPlayerFaction()
  local zones, dungeons, milestones = {}, {}, {}

  for _, z in ipairs(ns.ZONE_GUIDE_DATA or {}) do
    local lr = z.levelRange
    if lr and pLevel >= (lr[1] - 2) and pLevel <= (lr[2] + 2) and not (lr[1] == 1 and lr[2] == 60) then
      if not pFaction or z.faction == "Neutral" or z.faction == "Contested" or z.faction == pFaction then
        zones[#zones + 1] = z
      end
    end
  end

  for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
    local lr = d.levelRange
    if lr and pLevel >= (lr[1] - 2) and pLevel <= (lr[2] + 3) then
      if not pFaction or d.faction == "Neutral" or d.faction == pFaction then
        dungeons[#dungeons + 1] = d
      end
    end
  end

  local allMilestones = {
    { minLv = 1, maxLv = 19, title = "Bag & Spell Reminder (Forever)", note = "New bags must be equipped manually and new spell ranks put on your action bars after training (/epu ranks finds and updates them)." },
    { minLv = 10, maxLv = 60, title = "Waylaid Crates & Craftsman's Writs", note = "Turn in filled crates & writs at your faction's supply hub for Merchant's Favor & supply rep." },
    { minLv = 25, maxLv = 45, title = "Artisan First Aid (225–300) — Triage", note = pFaction == "Horde" and "Doctor Gregory Victor in Hammerfall (Arathi, 73.4, 36.9)" or "Doctor Gustaf VanHowzen in Theramore (Dustwallow, 67.8, 49.0)" },
    { minLv = 35, maxLv = 55, title = "Artisan Fishing (225–300) — Nat Pagle", note = "Nat Pagle on Pagle's Pointe island, Dustwallow Marsh (58.6, 60.1)." },
    { minLv = 35, maxLv = 55, title = "Artisan Cooking (225–300) — Clamlette Magnifique", note = "Dirge Quikcleave in Gadgetzan Inn, Tanaris (52.6, 28.1)." },
    { minLv = 38, maxLv = 44, title = "Lv 40 Mount & Riding Training", note = "Save ~90-100g for Apprentice Riding and your level 40 mount." },
    { minLv = 38, maxLv = 55, title = "Master Enchanting (225–300) — Annora", note = "Annora inside Uldaman (Badlands, 42.5, 13.5) — clear scorpids before speaking." },
    { minLv = 56, maxLv = 60, title = "Lv 60 Epic Mount & Raid Attunements", note = "Check Dungeon Readiness for UBRS Seal of Ascension, Scholo/Strat keys, and MC/Onyxia attunements." },
  }
  for _, m in ipairs(allMilestones) do
    if pLevel >= m.minLv and pLevel <= m.maxLv then
      milestones[#milestones + 1] = m
    end
  end

  return {
    level = pLevel,
    faction = pFaction,
    zones = zones,
    dungeons = dungeons,
    milestones = milestones,
  }
end

-- =========================================================================
-- Guild-wide Key / Attunement / Milestone Tracker + Projects & Needs Links
-- =========================================================================
-- "L" is the guild map's location kind (GuildMap.lua), so readiness uses its own.
local READINESS_KIND = "E"
local function ReadinessStore()
  local g = ns.G and ns.G()
  if not g then return end
  g.levelingProgress = g.levelingProgress or {}
  return g.levelingProgress
end

local function Mine()
  local store = ReadinessStore()
  if not store or not ns.me then return end
  if ns.OwnProgress then return ns.OwnProgress() end
  store[ns.me] = store[ns.me] or { who = ns.me, done = {}, camp = {}, t = 0 }
  store[ns.me].done, store[ns.me].camp = store[ns.me].done or {}, store[ns.me].camp or {}
  return store[ns.me]
end

-- Your record changed: the synced guild copy (GuildProgress.lua) goes out,
-- along with the live message older versions listen for.
local function Publish(mine)
  if ns.PublishProgress then
    ns.MarkProgressChanged()
    ns.PublishProgress()
  else
    mine.t = ns.Now and ns.Now() or time()
    if ns.Send then ns.Send(READINESS_KIND, { who = ns.me, done = mine.done, camp = mine.camp, t = mine.t }) end
  end
  if ns.Changed then ns.Changed() end
end

function ns.GetMyReadiness()
  local mine = Mine()
  return mine and mine.done or {}
end

function ns.ToggleMyReadiness(keyId, val)
  local mine = keyId and Mine()
  if not mine then return end
  if val == nil then val = not mine.done[keyId] end
  mine.done[keyId] = val and true or nil
  Publish(mine)
end

-- Keys in your bags and attunement quests you've finished tick themselves.
function ns.SyncMyKeys()
  if ns.DetectProgress then return ns.DetectProgress() end
  local mine = Mine()
  if not mine then return end
  local changed = false
  for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
    if d.keyItemID and ns.HasKeyItem(d.keyItemID) and not mine.done[d.id] then
      mine.done[d.id] = true
      changed = true
    end
  end
  if changed then Publish(mine) end
end

function ns.GetGuildReadiness(dungeon)
  local store = ReadinessStore() or {}
  local completed, needed = {}, {}
  local minLv = dungeon.levelRange and dungeon.levelRange[1] or 1
  local maxLv = dungeon.levelRange and dungeon.levelRange[2] or 60

  for who, entry in pairs(store) do
    if entry.done and entry.done[dungeon.id] then
      local r = ns.roster and ns.roster[who]
      completed[#completed + 1] = { name = who, level = r and r.level or 0, online = r and r.online }
    end
  end
  for who, r in pairs(ns.roster or {}) do
    local isDone = store[who] and store[who].done and store[who].done[dungeon.id]
    if not isDone and r.level and r.level >= (minLv - 3) and r.level <= (maxLv + 10) then
      if not dungeon.faction or dungeon.faction == "Neutral" or r.faction == dungeon.faction or not r.faction then
        needed[#needed + 1] = { name = who, level = r.level, online = r.online }
      end
    end
  end
  table.sort(completed, function(a, b) return a.name < b.name end)
  table.sort(needed, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online end
    return a.name < b.name
  end)
  return completed, needed
end

function ns.ToggleMyCampingStation(bpName)
  local mine = bpName and Mine()
  if not mine then return end
  mine.camp[bpName] = not mine.camp[bpName] and true or nil
  Publish(mine)
end

function ns.GetGuildCampingCoverage(bpName)
  local store = ReadinessStore() or {}
  local owners = {}
  for who, entry in pairs(store) do
    if entry.camp and entry.camp[bpName] then
      local r = ns.roster and ns.roster[who]
      owners[#owners + 1] = { name = who, online = r and r.online }
    end
  end
  table.sort(owners, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online end
    return a.name < b.name
  end)
  return owners
end

ns.comm[READINESS_KIND] = function(sender, payload, channel)
  if channel ~= "GUILD" or type(payload) ~= "table" or type(payload.done) ~= "table" then return end
  -- Only the sender's own record: a member can't rewrite someone else's.
  local who = ns.Member and ns.Member(sender)
  if not who then return end
  local now = ns.Now and ns.Now() or time()
  if tonumber(payload.t) and tonumber(payload.t) > now + 300 then return end
  local store = ReadinessStore()
  if not store then return end
  local cur = store[who]
  if cur and (cur.t or 0) >= (payload.t or 0) then return end
  local clean, cleanCamp, n = {}, {}, 0
  for k, v in pairs(payload.done) do
    n = n + 1
    if n > 200 then return end
    if type(k) == "string" and #k <= 60 and v == true then clean[k] = true end
  end
  -- A dungeon update without camp keeps the camping stations we already had.
  local camp = payload.camp
  if type(camp) ~= "table" then camp = cur and cur.camp or {} end
  for k, v in pairs(camp) do
    n = n + 1
    if n > 400 then return end
    if type(k) == "string" and #k <= 80 and v == true then cleanCamp[k] = true end
  end
  -- Keep what the synced record carries beyond dungeons (raid status, reputation).
  store[who] = { who = who, done = clean, camp = cleanCamp, raid = cur and cur.raid, rep = cur and cur.rep,
    t = tonumber(payload.t) or (ns.Now and ns.Now() or time()) }
  if ns.Changed then ns.Changed() end
end

function ns.AddLevelingNeed(itemID, qty, itemName)
  if not ns.IsTrusted or not ns.IsTrusted(ns.me) then
    return ns.Print("Only officers or bank managers can add guild bank needs.")
  end
  if not ns.SetNeed then return end
  local g = ns.G and ns.G()
  local cur = (g and g.needs and g.needs.list and g.needs.list[itemID] and ns.NeedEntry) and ns.NeedEntry(g.needs.list[itemID]) or 0
  ns.SetNeed(itemID, cur + (qty or 5), "restock")
  ns.Print(string.format("Updated guild bank need for %s to %d.", itemName or ("Item #" .. itemID), cur + (qty or 5)))
end

function ns.CreateLevelingProject(title, note)
  if not ns.IsTrusted or not ns.IsTrusted(ns.me) then
    return ns.Print("Only officers or bank managers can create guild crafting projects.")
  end
  if not ns.CreateProject then return end
  local pid = ns.CreateProject(title, note)
  if pid then
    ns.Print("Created guild project: " .. title .. " (open Guild -> Projects to assign crafters).")
  end
  return pid
end

-- =========================================================================
-- WoW: Forever Camping Blueprints (Tier 2 & Tier 3 Drop Reference)
-- =========================================================================
ns.CAMPING_BLUEPRINTS = {
  -- Tier 3 (Skill 300)
  { tier = 3, profession = "Alchemy", skill = 300, name = "Blueprint: Alchemy Laboratory",
    source = "Ras Frostwhisper (Scholomance)", dungeonId = "scholomance",
    effect = "Portable Alchemy Lab for flasks & high-end potions + Mana Well buff." },
  { tier = 3, profession = "Blacksmithing", skill = 300, name = "Blueprint: Master Forge",
    source = "Golem Lord Argelmach (Blackrock Depths)", dungeonId = "blackrock_depths",
    effect = "Advanced portable Forge/Anvil for endgame recipes + Strength buff." },
  { tier = 3, profession = "Cooking", skill = 300, name = "Blueprint: Expert Campfire",
    source = "High-level dungeon bosses (e.g. Slavecrusher Grox)", dungeonId = "blackrock_depths",
    effect = "Upgrades campfire capacity to 10 simultaneous profession features." },
  { tier = 3, profession = "Cooking", skill = 300, name = "Blueprint: Iron Oven / Advanced Feast",
    source = "Endgame dungeon drops", dungeonId = "stratholme",
    effect = "Superior camping feasts with strong food buffs & XP support." },
  { tier = 3, profession = "Engineering", skill = 300, name = "Blueprint: Advanced Repair / Workshop Bot",
    source = "Endgame dungeon bosses (BRD / Dire Maul / UBRS)", dungeonId = "blackrock_depths",
    effect = "Full field Repair Bot, vendor & engineering workbench." },
  { tier = 3, profession = "Enchanting", skill = 300, name = "Blueprint: Arcane Salvager / Crystal Prism",
    source = "High-level dungeon bosses (Scholo / Strat / Dire Maul)", dungeonId = "scholomance",
    effect = "Shard transmutation & field enchanting station + All-Stats/Resist buff." },
  { tier = 3, profession = "Leatherworking", skill = 300, name = "Blueprint: Sewing Machine",
    source = "Endgame dungeon bosses (BRD / Dire Maul / LBRS)", dungeonId = "dire_maul",
    effect = "Portable workstation for epic & core-leather patterns + Rested XP tent." },
  { tier = 3, profession = "Tailoring", skill = 300, name = "Blueprint: Tailoring Workstation",
    source = "Endgame dungeon bosses (Scholo / Strat / Dalaran)", dungeonId = "stratholme",
    effect = "Field tailoring loom + Spirit banner buff." },
  { tier = 3, profession = "Herbalism", skill = 300, name = "Blueprint: Master Greenhouse",
    source = "Endgame dungeon bosses / Rare drops", dungeonId = "dire_maul",
    effect = "Upgraded herbalism soil node + Intellect buff." },
  { tier = 3, profession = "Mining", skill = 300, name = "Blueprint: Master Rock Garden / Smelter",
    source = "Endgame dungeon bosses (BRD / UBRS)", dungeonId = "blackrock_depths",
    effect = "Periodic ore/smelting utility + Attack Power buff." },
  { tier = 3, profession = "Skinning", skill = 300, name = "Blueprint: Master Hide Frame",
    source = "Endgame dungeon bosses (UBRS / Dire Maul)", dungeonId = "ubrs",
    effect = "Hide treatment frame + 2% Crit Camp Chair aura." },
  { tier = 3, profession = "First Aid", skill = 300, name = "Blueprint: Field Emergency Station",
    source = "Endgame dungeon bosses / Supply Quartermaster", dungeonId = "stratholme",
    effect = "Dispenses high-level bandages & anti-venom + Stamina buff." },
  { tier = 3, profession = "Fishing", skill = 300, name = "Blueprint: Master Tackle Box",
    source = "Endgame dungeon bosses / Fishing drops", dungeonId = "zulfarrak",
    effect = "Fishing lures & uncommon catch node + 8% All-Stats Fish Bowl." },

  -- Tier 2 (Skill ~140)
  { tier = 2, profession = "Alchemy", skill = 140, name = "Blueprint: Fermenter",
    source = "Rath'mael (Ruins of Lordaeron)", dungeonId = "ruins_of_lordaeron",
    effect = "Tier 2 Alchemy camp station." },
  { tier = 2, profession = "Blacksmithing", skill = 140, name = "Blueprint: Anvil",
    source = "Gilnid (The Deadmines)", dungeonId = "deadmines",
    effect = "Portable Anvil at campfires." },
  { tier = 2, profession = "Engineering", skill = 140, name = "Blueprint: Repair Bot",
    source = "Sneed (The Deadmines)", dungeonId = "deadmines",
    effect = "Field Repair Bot at campfires." },
  { tier = 2, profession = "Cooking", skill = 140, name = "Blueprint: Journeyman Campfire",
    source = "Lord Serpentis (Wailing Caverns)", dungeonId = "wailing_caverns",
    effect = "Upgrades campfire capacity to 5 simultaneous features." },
  { tier = 2, profession = "Leatherworking", skill = 140, name = "Blueprint: Tanning Rack",
    source = "Razorclaw the Butcher (Shadowfang Keep)",
    effect = "Tier 2 Leatherworking camp station." },
  { tier = 2, profession = "Herbalism", skill = 140, name = "Blueprint: Greenhouse",
    source = "Raptor bosses (Excavation Site: Wetlands)", dungeonId = "excavation_site",
    effect = "Tier 2 Herbalism camp node." },
  { tier = 2, profession = "Mining", skill = 140, name = "Blueprint: Rock Garden",
    source = "Relic Guardian (Excavation Site: Wetlands)", dungeonId = "excavation_site",
    effect = "Tier 2 Mining camp node." },
}

-- =========================================================================
-- Dungeon Gear Guide by Level, Class & Spec/Role
-- =========================================================================
local SPEC_TO_ROLE = {
  Protection = "Tank",
  Feral = "Melee",
  Restoration = "Healer",
  Holy = "Healer",
  Discipline = "Healer",
  Shadow = "Caster",
  Balance = "Caster",
  Elemental = "Caster",
  Enhancement = "Melee",
  Retribution = "Melee",
  Arms = "Melee",
  Fury = "Melee",
  Combat = "Melee",
  Assassination = "Melee",
  Subtlety = "Melee",
  ["Beast Mastery"] = "Melee",
  Marksmanship = "Melee",
  Survival = "Melee",
  Arcane = "Caster",
  Fire = "Caster",
  Frost = "Caster",
  Affliction = "Caster",
  Demonology = "Caster",
  Destruction = "Caster",
}

local CLASS_DEFAULT_ROLE = {
  WARRIOR = "Melee",
  ROGUE = "Melee",
  HUNTER = "Melee",
  MAGE = "Caster",
  WARLOCK = "Caster",
  PRIEST = "Healer",
  PALADIN = "Healer",
  SHAMAN = "Healer",
  DRUID = "Melee",
}

function ns.PlayerGearRole()
  local p = ns.GuidePlayer and ns.GuidePlayer() or {}
  local role = (p.focus and SPEC_TO_ROLE[p.focus]) or (p.class and CLASS_DEFAULT_ROLE[p.class]) or "Melee"
  return role, p.className or p.class or "Adventurer", p.focus
end

ns.DUNGEON_GEAR = {
  { id = "hall_of_thanes", name = "Hall of Thanes (Forever)", levelRange = {13, 18}, faction = "Alliance",
    items = {
      { name = "Early Alliance dungeon blues & greens", role = "All", slot = "Weapons / Armor", source = "Ironforge Vault Bosses" },
    }},
  { id = "ruins_of_lordaeron", name = "Ruins of Lordaeron (Forever)", levelRange = {15, 20}, faction = "Horde",
    items = {
      { name = "Early Horde dungeon blues & greens", role = "All", slot = "Weapons / Armor", source = "Ruins Bosses" },
    }},
  { id = "deadmines", name = "The Deadmines", levelRange = {17, 26}, faction = "Alliance",
    items = {
      { name = "Cruel Barb", role = "Melee", slot = "1H Sword (+12 AP)", source = "Edwin VanCleef" },
      { name = "Smite's Mighty Hammer", role = "Melee", slot = "2H Mace (11 Str)", source = "Mr. Smite" },
      { name = "Thief's Blade", role = "Melee", slot = "1H Sword", source = "Sneed's Shredder" },
      { name = "Blackened Defias Armor", role = "Melee", slot = "Leather Chest", source = "Edwin VanCleef" },
      { name = "Emberstone Staff", role = "Caster", slot = "Staff (Int/Spi)", source = "Captain Greenskin" },
      { name = "Cookie's Stirring Rod", role = "Caster", slot = "Wand", source = "Cookie" },
      { name = "Corsair's Overshirt", role = "Healer", slot = "Cloth Chest", source = "Captain Greenskin" },
      { name = "Gold-flecked Gloves", role = "Tank", slot = "Mail Hands", source = "Rhahk'Zor" },
    }},
  { id = "wailing_caverns", name = "Wailing Caverns", levelRange = {17, 24}, faction = "Neutral",
    items = {
      { name = "Wingblade / Crescent Staff", role = "Melee", slot = "Quest Rewards (Leaders of the Fang)", source = "Wailing Caverns Quest" },
      { name = "Armor of the Fang (Set)", role = "Melee", slot = "Leather Set", source = "Druids of the Fang" },
      { name = "Cobrahn's Grasp", role = "Tank", slot = "Mail Belt", source = "Lord Cobrahn" },
      { name = "Living Root", role = "Healer", slot = "Staff (Spi/Sta)", source = "Verdan the Everliving" },
      { name = "Robe of the Moccasin", role = "Caster", slot = "Cloth Chest", source = "Skum" },
    }},
  { id = "shadowfang_keep", name = "Shadowfang Keep", levelRange = {22, 30}, faction = "Neutral",
    items = {
      { name = "Meteor Shard", role = "Melee", slot = "1H Dagger", source = "Archmage Arugal" },
      { name = "Butcher's Cleaver", role = "Melee", slot = "1H Axe", source = "Razorclaw the Butcher" },
      { name = "Robes of Arugal", role = "Caster", slot = "Cloth Chest (9 Int/10 Spi)", source = "Archmage Arugal" },
      { name = "Belt of Arugal", role = "Healer", slot = "Cloth Waist", source = "Archmage Arugal" },
      { name = "Baron's Scepter", role = "Tank", slot = "1H Mace", source = "Baron Silverlaine" },
    }},
  { id = "excavation_site", name = "Excavation Site (Forever)", levelRange = {24, 29}, faction = "Neutral",
    items = {
      { name = "Mid-20s Forever dungeon drops", role = "All", slot = "Weapons / Armor", source = "Excavation Bosses" },
    }},
  { id = "city_of_dalaran", name = "City of Dalaran (Forever)", levelRange = {28, 33}, faction = "Neutral",
    items = {
      { name = "Arcane-themed 28-33 Forever drops", role = "All", slot = "Weapons / Armor", source = "Dalaran Bosses (requires attunement)" },
    }},
  { id = "gnomeregan", name = "Gnomeregan", levelRange = {29, 38}, faction = "Neutral",
    items = {
      { name = "Triprunner Dungarees", role = "Melee", slot = "Leather Legs (18 Agi!)", source = "Quest: Rig Wars / Save Techbot" },
      { name = "Manual Crowd Pummeler", role = "Melee", slot = "2H Mace (Feral BiS!)", source = "Crowd Pummeler 9-60" },
      { name = "Thermaplugg's Left Arm", role = "Tank", slot = "1H Axe", source = "Mekgineer Thermaplugg" },
      { name = "Electromagnetic Gigaflux Reactivator", role = "Caster", slot = "Cloth Helm", source = "Mekgineer Thermaplugg" },
      { name = "Civinad Robes", role = "Healer", slot = "Cloth Chest", source = "Viscous Fallout" },
    }},
  { id = "scarlet_monastery", name = "Scarlet Monastery", levelRange = {29, 44}, faction = "Neutral",
    items = {
      { name = "Ravager / Whirlwind-tier 2H", role = "Melee", slot = "2H Axe (AoE proc)", source = "Herod (Armory)" },
      { name = "Herod's Shoulder & Scarlet Leggings", role = "Melee", slot = "Mail", source = "Herod (Armory)" },
      { name = "Illusionary Rod", role = "Caster", slot = "Staff (15 Int/10 Spi)", source = "Arcanist Doan (Library)" },
      { name = "Hypnotic Blade", role = "Caster", slot = "1H Dagger (8 Int/9 SP)", source = "Arcanist Doan (Library)" },
      { name = "Whitemane's Chapeau", role = "Healer", slot = "Cloth Helm (14 Int/14 Spi/33 Heal)", source = "High Inquisitor Whitemane" },
      { name = "Aegis of the Scarlet Commander", role = "Tank", slot = "Shield", source = "Scarlet Commander Mograine" },
    }},
  { id = "drowned_city", name = "The Drowned City (Forever)", levelRange = {35, 40}, faction = "Neutral",
    items = {
      { name = "Naga & Pirate 35-40 Forever drops", role = "All", slot = "Weapons / Armor", source = "Drowned City Bosses" },
    }},
  { id = "kroldok_stronghold", name = "Krol'dok Stronghold (Forever)", levelRange = {40, 45}, faction = "Neutral",
    items = {
      { name = "Level 40-45 Forever dungeon drops", role = "All", slot = "Weapons / Armor", source = "Krol'dok Bosses" },
    }},
  { id = "zulfarrak", name = "Zul'Farrak", levelRange = {44, 54}, faction = "Neutral",
    items = {
      { name = "Sul'thraze the Lasher", role = "Melee", slot = "Epic 2H Sword (Jang'thraze + Sang'thraze)", source = "Chief Ukorz / Antu'sul" },
      { name = "Big Bad Pauldrons", role = "Tank", slot = "Plate Shoulders", source = "Chief Ukorz Sandscalp" },
      { name = "Bad Mojo Mask", role = "Caster", slot = "Cloth Helm (22 Int/14 SP)", source = "Shadowpriest Sezz'ziz" },
      { name = "Gahz'rilla Scale Armor", role = "Melee", slot = "Mail Chest", source = "Gahz'rilla" },
      { name = "Mason's Fraternity Ring", role = "Healer", slot = "Ring", source = "Quest: Gahz'rilla / Divino-matic" },
    }},
  { id = "alcaz_prison", name = "Alcaz Prison (Forever)", levelRange = {48, 53}, faction = "Neutral",
    items = {
      { name = "Level 48-53 Forever dungeon drops", role = "All", slot = "Weapons / Armor", source = "Alcaz Prison Bosses" },
    }},
  { id = "blackrock_depths", name = "Blackrock Depths", levelRange = {52, 60}, faction = "Neutral",
    items = {
      { name = "Hand of Justice", role = "Melee", slot = "Trinket (2% Extra Attack)", source = "General Angerforge" },
      { name = "Savage Gladiator Chain", role = "Melee", slot = "Mail Chest (2% Crit)", source = "Gorosh the Dervish (Arena)" },
      { name = "Ironfoe", role = "Tank", slot = "Epic 1H Mace", source = "Emperor Dagran Thaurissan" },
      { name = "Force of Will", role = "Tank", slot = "Trinket", source = "Emperor Dagran Thaurissan" },
      { name = "Ban'thok Sash", role = "Caster", slot = "Cloth Waist (1% Hit + SP)", source = "Ok'thor the Breaker (Arena)" },
      { name = "Second Wind", role = "Healer", slot = "Trinket (+22 Healing)", source = "Golem Lord Argelmach" },
    }},
  { id = "blackmaw_hold", name = "Blackmaw Hold (Forever)", levelRange = {55, 60}, faction = "Neutral",
    items = {
      { name = "Endgame 55-60 Forever Furbolg drops", role = "All", slot = "Weapons / Armor", source = "Blackmaw Hold Bosses" },
    }},
  { id = "shapers_terrace", name = "Shaper's Terrace (Forever)", levelRange = {58, 60}, faction = "Neutral",
    items = {
      { name = "Endgame 58-60 Forever Titan drops", role = "All", slot = "Weapons / Armor", source = "Shaper's Terrace Bosses" },
    }},
}

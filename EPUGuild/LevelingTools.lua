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
  { id = "hall_of_thanes", name = "Hall of Thanes (Forever)", levelRange = {13, 18}, zone = "Ironforge", mapID = 1455, x = 50.0, y = 50.0, faction = "Alliance",
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
      { name = "Collecting Memories / Oh Brother...", level = 18, faction = "Alliance", giver = "Stormwind (Dwarven District)", x = 54.0, y = 18.0 },
    }},
  { id = "wailing_caverns", name = "Wailing Caverns", levelRange = {17, 24}, zone = "The Barrens", mapID = 1413, x = 46.0, y = 36.4, faction = "Neutral",
    key = "None", quests = {
      { name = "Leaders of the Fang", level = 22, faction = "Horde", giver = "Nara Wildmane (Thunder Bluff)", x = 75.6, y = 31.2 },
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
      { name = "Save Techbot's Brain!", level = 26, faction = "Alliance", giver = "Tinkmaster Overspark (Ironforge)", x = 69.8, y = 50.2 },
      { name = "Rig Wars", level = 35, faction = "Horde", giver = "Nogg (Orgrimmar)", x = 75.8, y = 25.2 },
    }},
  { id = "scarlet_monastery", name = "Scarlet Monastery", levelRange = {29, 44}, zone = "Tirisfal Glades", mapID = 1420, x = 84.9, y = 32.8, faction = "Neutral",
    key = "The Scarlet Key (Armory & Cathedral)", keyItemID = 7146, quests = {
      { name = "In the Name of the Light", level = 40, faction = "Alliance", giver = "Raleigh the Devout (Southshore)", x = 51.4, y = 58.6 },
      { name = "Into The Scarlet Monastery", level = 38, faction = "Horde", giver = "Varimathras (Undercity)", x = 56.2, y = 92.2 },
    }},
  { id = "drowned_city", name = "The Drowned City (Forever)", levelRange = {35, 40}, zone = "Stranglethorn Vale", mapID = 1434, x = 40.0, y = 50.0, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Booty Bay / Grom'gol / Rebel Camp for Naga ruin quests", level = 37, faction = "Neutral", giver = "Booty Bay", x = 27.5, y = 77.5 },
    }},
  { id = "kroldok_stronghold", name = "Krol'dok Stronghold (Forever)", levelRange = {40, 45}, zone = "Riverglades", mapID = 2548, x = 50.0, y = 50.0, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Riverglades outposts before entering", level = 42, faction = "Neutral", giver = "Riverglades", x = 58.0, y = 45.8 },
    }},
  { id = "zulfarrak", name = "Zul'Farrak", levelRange = {44, 54}, zone = "Tanaris", mapID = 1446, x = 38.7, y = 20.0, faction = "Neutral",
    key = "Mallet of Zul'Farrak (summons Gahz'rilla)", keyItemID = 9240, quests = {
      { name = "Gahz'rilla (Carrot on a Stick!)", level = 50, faction = "Neutral", giver = "Wizzle Brassbolts (Shimmering Flats)", x = 78.0, y = 77.1 },
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
      { name = "The Princess Saved? / Marshal Windsor", level = 58, faction = "Alliance", giver = "Morgan's Vigil", x = 84.3, y = 68.3 },
    }},
  { id = "blackmaw_hold", name = "Blackmaw Hold (Forever)", levelRange = {55, 60}, zone = "Azshara", mapID = 1447, x = 55.0, y = 50.0, faction = "Neutral",
    key = "None", quests = {
      { name = "Check Azshara hubs / Timbermaw quests before entering", level = 57, faction = "Neutral", giver = "Azshara", x = 22.0, y = 49.6 },
    }},
  { id = "shapers_terrace", name = "Shaper's Terrace (Forever)", levelRange = {58, 60}, zone = "Un'Goro Crater", mapID = 1449, x = 50.0, y = 50.0, faction = "Neutral",
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

  local warnings = {}
  if targetMaxLevel and (hi.level - targetMaxLevel) >= 12 then
    warnings[#warnings + 1] = string.format(
      "%s (Lv %d) is %d+ levels above this dungeon's max level (%d) — kills may grant ZERO XP to the party!",
      hi.name, hi.level, hi.level - targetMaxLevel, targetMaxLevel
    )
  end
  if #members > 1 and (hi.level - lo.level) >= 12 then
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
  if g and g.bank then
    for _, b in pairs(g.bank) do
      if b.items and itemID and b.items[itemID] then
        bankQty = bankQty + (b.items[itemID].qty or 0)
      end
    end
  end
  if g and g.guildBank and g.guildBank.items and itemID and g.guildBank.items[itemID] then
    bankQty = bankQty + (g.guildBank.items[itemID].qty or 0)
  end
  local needle = (itemName or ""):lower()
  if g and g.recipes and needle ~= "" then
    for who, rlist in pairs(g.recipes) do
      for _, rec in ipairs(rlist) do
        local rname = type(rec) == "table" and rec.name or tostring(rec)
        if rname:lower():find(needle, 1, true) then
          local online = ns.roster and ns.roster[who] and ns.roster[who].online
          crafters[#crafters + 1] = { name = who, online = online and true or false }
          break
        end
      end
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
    { minLv = 1, maxLv = 19, title = "Bag & Spell Reminder (Forever)", note = "New bags must be equipped manually and new spell ranks dragged onto your action bars after training." },
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
local function ReadinessStore()
  local g = ns.G and ns.G()
  if not g then return end
  g.levelingProgress = g.levelingProgress or {}
  return g.levelingProgress
end

function ns.GetMyReadiness()
  local store = ReadinessStore()
  if not store or not ns.me then return {} end
  store[ns.me] = store[ns.me] or { done = {}, t = 0 }
  return store[ns.me].done
end

function ns.ToggleMyReadiness(keyId, val)
  local store = ReadinessStore()
  if not store or not ns.me or not keyId then return end
  store[ns.me] = store[ns.me] or { done = {}, t = 0 }
  if val == nil then val = not store[ns.me].done[keyId] end
  store[ns.me].done[keyId] = val and true or nil
  store[ns.me].t = ns.Now and ns.Now() or time()
  if ns.Send then
    ns.Send("L", { who = ns.me, done = store[ns.me].done, t = store[ns.me].t })
  end
  if ns.Changed then ns.Changed() end
end

function ns.SyncMyKeys()
  local store = ReadinessStore()
  if not store or not ns.me then return end
  store[ns.me] = store[ns.me] or { done = {}, t = 0 }
  local changed = false
  for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
    if d.keyItemID and ns.HasKeyItem(d.keyItemID) and not store[ns.me].done[d.id] then
      store[ns.me].done[d.id] = true
      changed = true
    end
  end
  if changed then
    store[ns.me].t = ns.Now and ns.Now() or time()
    if ns.Send then ns.Send("L", { who = ns.me, done = store[ns.me].done, t = store[ns.me].t }) end
  end
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

ns.comm.L = function(sender, payload)
  if type(payload) ~= "table" or type(payload.done) ~= "table" then return end
  local who = ns.Member and ns.Member(payload.who or sender) or sender
  if not who then return end
  local store = ReadinessStore()
  if not store then return end
  local cur = store[who]
  if cur and (cur.t or 0) >= (payload.t or 0) then return end
  local clean = {}
  for k, v in pairs(payload.done) do
    if type(k) == "string" and v == true then clean[k] = true end
  end
  store[who] = { done = clean, t = tonumber(payload.t) or (ns.Now and ns.Now() or time()) }
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

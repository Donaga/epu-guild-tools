-- EPU Guild Tools: Configurable screen-edge Info Bars (Top, Bottom, Left, Right).
local _, ns = ...

local BAR_ORDER = { "top", "bottom", "left", "right" }
local BAR_LABELS = { top = "Top Bar", bottom = "Bottom Bar", left = "Left Bar", right = "Right Bar" }
local DEFAULT_WIDGETS = {
  top = { "zone", "fps", "ms", "durability", "bags", "gold", "clock" },
  bottom = { "xp", "reputation", "currency", "guild", "friends", "mail" },
  left = { "epuchat", "epuevents", "volume" },
  right = { "gold", "durability", "bags" },
}

local MODULE_ORDER = {
  "fps", "ms", "gold", "durability", "bags", "currency", "reputation",
  "xp", "clock", "zone", "speed", "hearth", "guild", "friends", "mail", "epuchat", "epuevents", "volume",
}
local MODULE_LABELS = {
  fps = "FPS",
  ms = "Latency (MS)",
  gold = "Gold",
  durability = "Durability",
  bags = "Bag Space",
  currency = "Currencies",
  reputation = "Reputation",
  xp = "XP / iLvl",
  clock = "Clock",
  zone = "Zone & Coords",
  speed = "Move Speed",
  hearth = "Hearthstone",
  guild = "Guild Online",
  friends = "Friends Online",
  mail = "Mail",
  epuchat = "EPU Chat",
  epuevents = "EPU Events",
  volume = "Volume",
}

local sessionStart = time()
local startMoney
local sessionXP = 0
local startXP
local sessionRep = {}
local barFrames = {}
local cfgWin
local selectedBar = "top"

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function FormatMoney(copper)
  copper = math.floor(math.abs(copper or 0))
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local gStr = tostring(g):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  if g > 0 then
    return string.format("|cffffffff%s|r|cffffd100g|r |cffffffff%d|r|cffc7c7cfs|r", gStr, s)
  elseif s > 0 then
    return string.format("|cffffffff%d|r|cffc7c7cfs|r |cffffffff%d|r|cffeda55fc|r", s, c)
  end
  return string.format("|cffffffff%d|r|cffeda55fc|r", c)
end

local function DB()
  if not ns.db then return {} end
  ns.db.infoBars = ns.db.infoBars or {}
  local db = ns.db.infoBars
  if db.excludeSpecBags == nil then db.excludeSpecBags = true end
  if db.useRealmTime == nil then db.useRealmTime = false end
  db.bars = db.bars or {}
  for _, id in ipairs(BAR_ORDER) do
    db.bars[id] = db.bars[id] or {}
    local b = db.bars[id]
    local isVert = (id == "left" or id == "right")
    if b.enabled == nil then b.enabled = false end
    if b.thickness == nil then b.thickness = isVert and 136 or 24 end
    if b.fontSize == nil then b.fontSize = 11 end
    if b.bgAlpha == nil then b.bgAlpha = 0.88 end
    if b.border == nil then b.border = true end
    if b.hideInCombat == nil then b.hideInCombat = false end
    if b.mouseover == nil then b.mouseover = false end
    if b.align == nil then b.align = isVert and "top" or "center" end
    if type(b.widgets) ~= "table" then
      b.widgets = {}
      for _, w in ipairs(DEFAULT_WIDGETS[id] or {}) do b.widgets[#b.widgets + 1] = w end
    end
  end
  db.altGold = db.altGold or {}
  return db
end

local function RecordAltGold()
  if not GetMoney or not ns.me then return end
  local m = SafeNum(GetMoney())
  if not m then return end
  if startMoney == nil then startMoney = m end
  local db = DB()
  if not db.altGold then return end
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  db.altGold[realm] = db.altGold[realm] or {}
  local _, cf = UnitClass and UnitClass("player")
  db.altGold[realm][ns.me] = { money = m, classFile = cf }
end

local function ClassHex(cf)
  local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if c then
    if c.colorStr then return "|c" .. c.colorStr end
    return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
  end
  return "|cffffffff"
end

local function StandingColor(standing)
  local cols = {
    [1] = "|cffcc2222", [2] = "|cffff4422", [3] = "|cffee6622", [4] = "|cffffff00",
    [5] = "|cff00ff00", [6] = "|cff00ff88", [7] = "|cff00ffcc", [8] = "|cff4fc3f7",
  }
  return cols[standing] or "|cffffffff"
end

local STANDING_NAMES = {
  [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral",
  [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted",
}

local function GetWatchedRep()
  if C_Reputation and C_Reputation.GetWatchedFactionData then
    local ok, d = pcall(C_Reputation.GetWatchedFactionData)
    if ok and type(d) == "table" and SafeStr(d.name) and d.name ~= "" then
      local minV = SafeNum(d.currentReactionThreshold) or 0
      local maxV = SafeNum(d.nextReactionThreshold) or 1
      local curV = SafeNum(d.currentStanding) or 0
      return d.name, d.reaction or 4, minV, maxV, curV
    end
  end
  if GetWatchedFactionInfo then
    local ok, name, standing, minV, maxV, curV = pcall(GetWatchedFactionInfo)
    if ok and SafeStr(name) and name ~= "" then
      return name, standing or 4, SafeNum(minV) or 0, SafeNum(maxV) or 1, SafeNum(curV) or 0
    end
  end
  return nil
end

local function GetAllFactions()
  local out = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    local n = C_Reputation.GetNumFactions() or 0
    for i = 1, n do
      local ok, d = pcall(C_Reputation.GetFactionDataByIndex, i)
      if ok and type(d) == "table" and not d.isHeader and SafeStr(d.name) then
        out[#out + 1] = {
          name = d.name,
          standing = d.reaction or 4,
          minV = SafeNum(d.currentReactionThreshold) or 0,
          maxV = SafeNum(d.nextReactionThreshold) or 1,
          curV = SafeNum(d.currentStanding) or 0,
        }
      end
    end
    return out
  end
  if GetNumFactions and GetFactionInfo then
    local n = GetNumFactions() or 0
    for i = 1, n do
      local ok, name, _, standing, minV, maxV, curV, _, _, isHeader = pcall(GetFactionInfo, i)
      if ok and not isHeader and SafeStr(name) then
        out[#out + 1] = {
          name = name,
          standing = standing or 4,
          minV = SafeNum(minV) or 0,
          maxV = SafeNum(maxV) or 1,
          curV = SafeNum(curV) or 0,
        }
      end
    end
  end
  return out
end

local function GetCurrencies()
  local list = {}
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
    local n = C_CurrencyInfo.GetCurrencyListSize() or 0
    for i = 1, n do
      local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
      if ok and type(info) == "table" and not info.isHeader and SafeStr(info.name) then
        list[#list + 1] = {
          name = info.name,
          qty = SafeNum(info.quantity) or 0,
          max = SafeNum(info.maxQuantity) or 0,
          icon = info.iconFileID,
          watched = info.isShowInBackpack,
        }
      end
    end
  elseif GetCurrencyListSize and GetCurrencyListInfo then
    local n = GetCurrencyListSize() or 0
    for i = 1, n do
      local ok, name, isHeader, _, _, isWatched, count, icon, maximum = pcall(GetCurrencyListInfo, i)
      if ok and not isHeader and SafeStr(name) then
        list[#list + 1] = {
          name = name,
          qty = SafeNum(count) or 0,
          max = SafeNum(maximum) or 0,
          icon = icon,
          watched = isWatched,
        }
      end
    end
  end
  return list
end

local function GetBagSummary()
  local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local getFree = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  local getBagName = C_Container and C_Container.GetBagName or GetBagName
  local excl = DB().excludeSpecBags
  local normalFree, normalTotal = 0, 0
  local specFree, specTotal = 0, 0
  local perBag = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local total = getSlots and SafeNum(getSlots(bag)) or 0
    if total and total > 0 then
      local free, bagType = 0, 0
      if getFree then
        local f, bt = getFree(bag)
        free = SafeNum(f) or 0
        bagType = SafeNum(bt) or 0
      end
      local isSpec = (bag > 0 and bagType ~= 0)
      if isSpec then
        specFree = specFree + free
        specTotal = specTotal + total
      else
        normalFree = normalFree + free
        normalTotal = normalTotal + total
      end
      local name = bag == 0 and "Backpack" or (getBagName and SafeStr(getBagName(bag))) or ("Bag " .. bag)
      perBag[#perBag + 1] = { name = name, free = free, total = total, spec = isSpec }
    end
  end
  if excl then
    return normalFree, normalTotal, specFree, specTotal, perBag
  end
  return normalFree + specFree, normalTotal + specTotal, 0, 0, perBag
end

local function GetDurabilityInfo()
  local curSum, maxSum = 0, 0
  local slots = {}
  local SLOT_NAMES = {
    [1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
  }
  if GetInventoryItemDurability then
    for id, label in pairs(SLOT_NAMES) do
      local c, m = GetInventoryItemDurability(id)
      c, m = SafeNum(c), SafeNum(m)
      if c and m and m > 0 then
        curSum = curSum + c
        maxSum = maxSum + m
        local pct = math.floor((c / m) * 100 + 0.5)
        if pct < 100 then slots[#slots + 1] = { label = label, pct = pct } end
      end
    end
  end
  table.sort(slots, function(a, b) return a.pct < b.pct end)
  local overall = maxSum > 0 and math.floor((curSum / maxSum) * 100 + 0.5) or 100
  return overall, slots
end

local MODULES = {}

MODULES.fps = {
  text = function()
    local fps = math.floor((GetFramerate and SafeNum(GetFramerate()) or 0) + 0.5)
    local col = fps >= 55 and "|cff4ade80" or (fps >= 30 and "|cffffd100" or "|cffff6b6b")
    return col .. fps .. "|r |cff9fb4c8FPS|r"
  end,
  tooltip = function(tt)
    local fps = math.floor((GetFramerate and SafeNum(GetFramerate()) or 0) + 0.5)
    local down, up, home, world = 0, 0, 0, 0
    if GetNetStats then down, up, home, world = GetNetStats() end
    tt:AddLine("Performance", 1, 0.84, 0.35)
    tt:AddDoubleLine("Framerate:", fps .. " FPS", 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddDoubleLine("Latency (Home / World):", string.format("%d / %d ms", home or 0, world or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddDoubleLine("Bandwidth (In / Out):", string.format("%.1f / %.1f KB/s", down or 0, up or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
      UpdateAddOnMemoryUsage()
      local n = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or (GetNumAddOns and GetNumAddOns() or 0)
      local list, totalMem = {}, 0
      for i = 1, n do
        local mem = GetAddOnMemoryUsage(i) or 0
        if mem > 0 then
          totalMem = totalMem + mem
          local name = (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i)) or (GetAddOnInfo and GetAddOnInfo(i)) or ("Addon " .. i)
          list[#list + 1] = { name = name, mem = mem }
        end
      end
      table.sort(list, function(a, b) return a.mem > b.mem end)
      tt:AddLine(" ")
      tt:AddDoubleLine("Top Addon Memory", string.format("%.1f MB total", totalMem / 1024), 1, 0.84, 0.35, 0.8, 0.8, 0.8)
      for i = 1, math.min(8, #list) do
        local m = list[i].mem
        local val = m >= 1024 and string.format("%.2f MB", m / 1024) or string.format("%d KB", math.floor(m + 0.5))
        tt:AddDoubleLine(list[i].name, val, 0.85, 0.85, 0.85, 1, 1, 1)
      end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Run garbage collection", 0.5, 0.8, 1)
  end,
  onClick = function()
    collectgarbage("collect")
    ns.Print("Memory cleanup complete.")
    if ns.RefreshInfoBars then ns.RefreshInfoBars() end
  end,
}

MODULES.ms = {
  text = function()
    local _, _, home, world = 0, 0, 0, 0
    if GetNetStats then _, _, home, world = GetNetStats() end
    local ms = math.max(home or 0, world or 0)
    local col = ms <= 80 and "|cff4ade80" or (ms <= 160 and "|cffffd100" or "|cffff6b6b")
    return col .. (home or 0) .. "/" .. (world or 0) .. "|r |cff9fb4c8ms|r"
  end,
  tooltip = MODULES.fps.tooltip,
  onClick = MODULES.fps.onClick,
}

MODULES.gold = {
  text = function()
    local m = GetMoney and SafeNum(GetMoney()) or 0
    return FormatMoney(m)
  end,
  tooltip = function(tt)
    local m = GetMoney and SafeNum(GetMoney()) or 0
    RecordAltGold()
    tt:AddLine("Gold & Realm Characters", 1, 0.84, 0.35)
    local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
    local alts = DB().altGold and DB().altGold[realm] or {}
    local rows, total = {}, 0
    for who, info in pairs(alts) do
      total = total + (info.money or 0)
      rows[#rows + 1] = { who = who, money = info.money or 0, cf = info.classFile }
    end
    table.sort(rows, function(a, b) return a.money > b.money end)
    for _, r in ipairs(rows) do
      local label = ClassHex(r.cf) .. (ns.Short and ns.Short(r.who) or r.who) .. "|r"
      tt:AddDoubleLine(label, FormatMoney(r.money), 1, 1, 1, 1, 1, 1)
    end
    if #rows > 1 then
      tt:AddLine(" ")
      tt:AddDoubleLine("Realm Total:", FormatMoney(total), 1, 0.84, 0.35, 1, 1, 1)
    end
    if startMoney ~= nil then
      local diff = m - startMoney
      local sign = diff > 0 and "|cff4ade80+" or (diff < 0 and "|cffff6b6b-" or "|cff888888")
      tt:AddDoubleLine("Session Net:", sign .. FormatMoney(diff) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Toggle Bags", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleAllBags then ToggleAllBags() end end,
}

MODULES.durability = {
  text = function()
    local pct = GetDurabilityInfo()
    local col = pct >= 80 and "|cff4ade80" or (pct >= 45 and "|cffffd100" or "|cffff6b6b")
    return "|cff9fb4c8Dur:|r " .. col .. pct .. "%|r"
  end,
  tooltip = function(tt)
    local overall, slots = GetDurabilityInfo()
    tt:AddDoubleLine("Durability", overall .. "%", 1, 0.84, 0.35, 1, 1, 1)
    if #slots == 0 then
      tt:AddLine("All equipped items are at 100%.", 0.4, 0.9, 0.5)
    else
      for _, s in ipairs(slots) do
        local col = s.pct >= 80 and "|cff4ade80" or (s.pct >= 45 and "|cffffd100" or "|cffff6b6b")
        tt:AddDoubleLine(s.label, col .. s.pct .. "%|r", 0.85, 0.85, 0.85, 1, 1, 1)
      end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Open Character Sheet", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end,
}

MODULES.bags = {
  text = function()
    local free, total = GetBagSummary()
    local col = free > 6 and "|cff4ade80" or (free > 0 and "|cffffd100" or "|cffff6b6b")
    return "|cff9fb4c8Bags:|r " .. col .. free .. "|r/" .. total
  end,
  tooltip = function(tt)
    local free, total, sFree, sTotal, perBag = GetBagSummary()
    tt:AddDoubleLine("Bag Space", free .. " / " .. total .. " free", 1, 0.84, 0.35, 1, 1, 1)
    for _, b in ipairs(perBag) do
      local tag = b.spec and " |cff888888(Spec)|r" or ""
      tt:AddDoubleLine(b.name .. tag, b.free .. " / " .. b.total .. " free", 0.85, 0.85, 0.85, 1, 1, 1)
    end
    if sTotal > 0 then
      tt:AddLine(" ")
      tt:AddDoubleLine("Specialized Bags:", sFree .. " / " .. sTotal .. " free", 0.7, 0.8, 0.95, 1, 1, 1)
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Toggle Bags", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleAllBags then ToggleAllBags() end end,
}

MODULES.currency = {
  text = function()
    local list = GetCurrencies()
    local parts = {}
    for _, c in ipairs(list) do
      if c.watched then
        parts[#parts + 1] = string.format("|cff9fb4c8%s:|r |cffffffff%d|r", c.name:sub(1, 10), c.qty)
        if #parts >= 2 then break end
      end
    end
    if #parts > 0 then return table.concat(parts, "  ") end
    if list[1] then return string.format("|cff9fb4c8%s:|r |cffffffff%d|r", list[1].name:sub(1, 12), list[1].qty) end
    return "|cff9fb4c8Currencies:|r |cff888888None|r"
  end,
  tooltip = function(tt)
    tt:AddLine("Currencies", 1, 0.84, 0.35)
    local list = GetCurrencies()
    if #list == 0 then
      tt:AddLine("No currencies tracked on this character.", 0.7, 0.7, 0.7)
    else
      for _, c in ipairs(list) do
        local qty = c.max and c.max > 0 and (c.qty .. " / " .. c.max) or tostring(c.qty)
        tt:AddDoubleLine(c.name, qty, 0.88, 0.88, 0.88, 1, 1, 1)
      end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Open Currency Tab", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleCharacter then ToggleCharacter("TokenFrame") end end,
}

MODULES.reputation = {
  text = function()
    local name, standing, minV, maxV, curV = GetWatchedRep()
    if not name then return "|cff9fb4c8Rep:|r |cff888888None watched|r" end
    local span = math.max(1, maxV - minV)
    local cur = math.max(0, curV - minV)
    local pct = math.floor((cur / span) * 100 + 0.5)
    return string.format("%s%s:|r |cffffffff%d%%|r", StandingColor(standing), name:sub(1, 14), pct)
  end,
  tooltip = function(tt)
    tt:AddLine("Reputation", 1, 0.84, 0.35)
    local name, standing, minV, maxV, curV = GetWatchedRep()
    if name then
      local span = math.max(1, maxV - minV)
      local cur = math.max(0, curV - minV)
      tt:AddDoubleLine("Watched: " .. name, StandingColor(standing) .. (STANDING_NAMES[standing] or "") .. "|r (" .. cur .. "/" .. span .. ")", 1, 1, 1, 1, 1, 1)
    end
    local factions = GetAllFactions()
    if #factions > 0 then
      tt:AddLine(" ")
      for i = 1, math.min(12, #factions) do
        local f = factions[i]
        local span = math.max(1, f.maxV - f.minV)
        local cur = math.max(0, f.curV - f.minV)
        local pct = math.floor((cur / span) * 100 + 0.5)
        local gained = sessionRep[f.name] and (" |cff4ade80(+" .. sessionRep[f.name] .. ")|r") or ""
        tt:AddDoubleLine(f.name .. gained, StandingColor(f.standing) .. (STANDING_NAMES[f.standing] or "") .. " " .. pct .. "%|r", 0.85, 0.85, 0.85, 1, 1, 1)
      end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Open Reputation Tab", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleCharacter then ToggleCharacter("ReputationFrame") end end,
}

MODULES.xp = {
  text = function()
    local lvl = UnitLevel and UnitLevel("player") or 1
    local maxLvl = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    if lvl >= maxLvl then
      local avg = GetAverageItemLevel and select(2, GetAverageItemLevel())
      if avg and avg > 0 then
        return string.format("|cff9fb4c8iLvl:|r |cffffffff%.1f|r", avg)
      end
      return "|cff9fb4c8Lvl|r |cffffffff" .. lvl .. "|r"
    end
    local cur = UnitXP and SafeNum(UnitXP("player")) or 0
    local mx = UnitXPMax and SafeNum(UnitXPMax("player")) or 1
    if mx <= 0 then mx = 1 end
    local pct = math.floor((cur / mx) * 100 + 0.5)
    local rested = GetXPExhaustion and SafeNum(GetXPExhaustion()) or 0
    local rPct = math.floor((rested / mx) * 100 + 0.5)
    if rPct > 0 then
      return string.format("|cff9fb4c8XP:|r |cffffffff%d%%|r |cff4fc3f7(+%d%%)|r", pct, rPct)
    end
    return string.format("|cff9fb4c8XP:|r |cffffffff%d%%|r", pct)
  end,
  tooltip = function(tt)
    local lvl = UnitLevel and UnitLevel("player") or 1
    local cur = UnitXP and SafeNum(UnitXP("player")) or 0
    local mx = UnitXPMax and SafeNum(UnitXPMax("player")) or 1
    local rested = GetXPExhaustion and SafeNum(GetXPExhaustion()) or 0
    tt:AddDoubleLine("Experience & Level", "Level " .. lvl, 1, 0.84, 0.35, 1, 1, 1)
    if mx > 0 then
      tt:AddDoubleLine("Current XP:", string.format("%d / %d (%.1f%%)", cur, mx, (cur / mx) * 100), 0.85, 0.85, 0.85, 1, 1, 1)
      tt:AddDoubleLine("Rested XP:", string.format("%d (%.1f%%)", rested, (rested / mx) * 100), 0.4, 0.8, 1, 1, 1, 1)
    end
    local elapsed = math.max(1, time() - sessionStart)
    local xph = math.floor((sessionXP / elapsed) * 3600)
    tt:AddDoubleLine("Session XP:", string.format("%d (%d/hr)", sessionXP, xph), 0.85, 0.85, 0.85, 1, 1, 1)
    if xph > 0 and mx > cur then
      local mins = math.ceil(((mx - cur) / xph) * 60)
      tt:AddDoubleLine("Time to Level:", mins >= 60 and string.format("%dh %dm", math.floor(mins / 60), mins % 60) or (mins .. "m"), 0.85, 0.85, 0.85, 1, 1, 1)
    end
    if GetAverageItemLevel then
      local _, eq = GetAverageItemLevel()
      if eq and eq > 0 then tt:AddDoubleLine("Equipped iLvl:", string.format("%.1f", eq), 0.85, 0.85, 0.85, 1, 1, 1) end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Toggle XP & Rep Log", 0.5, 0.8, 1)
  end,
  onClick = function() if ns.ToggleLogWindow then ns.ToggleLogWindow("xp") end end,
}

MODULES.clock = {
  text = function()
    if DB().useRealmTime and GetGameTime then
      local h, m = GetGameTime()
      return string.format("|cffffffff%02d:%02d|r |cff888888ST|r", h or 0, m or 0)
    end
    return "|cffffffff" .. date("%H:%M") .. "|r"
  end,
  tooltip = function(tt)
    tt:AddLine("Clock", 1, 0.84, 0.35)
    tt:AddDoubleLine("Local Time:", date("%H:%M:%S"), 0.85, 0.85, 0.85, 1, 1, 1)
    if GetGameTime then
      local h, m = GetGameTime()
      tt:AddDoubleLine("Realm Time:", string.format("%02d:%02d", h or 0, m or 0), 0.85, 0.85, 0.85, 1, 1, 1)
    end
    local s = time() - sessionStart
    tt:AddDoubleLine("Session Time:", string.format("%dh %dm", math.floor(s / 3600), math.floor((s % 3600) / 60)), 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Click: Open EPU Events", 0.5, 0.8, 1)
  end,
  onClick = function() if SlashCmdList and SlashCmdList.EPUGUILD then SlashCmdList.EPUGUILD("calendar") end end,
}

MODULES.zone = {
  text = function()
    local z = (GetMinimapZoneText and SafeStr(GetMinimapZoneText())) or (GetZoneText and SafeStr(GetZoneText())) or "Unknown"
    local coords = ""
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
      local mapID = C_Map.GetBestMapForUnit("player")
      local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
      if pos and pos.GetXY then
        local x, y = pos:GetXY()
        if x and y and (x > 0 or y > 0) then
          coords = string.format(" |cff9fb4c8(%.0f, %.0f)|r", x * 100, y * 100)
        end
      end
    end
    return "|cffffffff" .. z:sub(1, 20) .. "|r" .. coords
  end,
  tooltip = function(tt)
    local z = (GetZoneText and SafeStr(GetZoneText())) or "Unknown"
    local sub = (GetSubZoneText and SafeStr(GetSubZoneText())) or ""
    tt:AddLine(z, 1, 0.84, 0.35)
    if sub ~= "" and sub ~= z then tt:AddLine(sub, 0.85, 0.85, 0.85) end
    local pvp = GetZonePVPInfo and SafeStr(GetZonePVPInfo())
    if pvp then tt:AddDoubleLine("Territory:", pvp, 0.8, 0.8, 0.8, 1, 1, 1) end
    local inZone = {}
    for name, r in pairs(ns.roster or {}) do
      if r.online and r.zone == z then inZone[#inZone + 1] = ClassHex(r.classFile) .. name .. "|r" end
    end
    if #inZone > 0 then
      table.sort(inZone)
      tt:AddLine(" ")
      tt:AddLine("Guildmates in zone: " .. table.concat(inZone, ", "), 0.8, 0.95, 0.8, true)
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Toggle World Map", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleWorldMap then ToggleWorldMap() end end,
}

MODULES.guild = {
  text = function()
    local n = 0
    for _, r in pairs(ns.roster or {}) do if r.online then n = n + 1 end end
    return "|cff4ade80Guild:|r |cffffffff" .. n .. "|r"
  end,
  tooltip = function(tt)
    local online = {}
    for name, r in pairs(ns.roster or {}) do
      if r.online then online[#online + 1] = { name = name, r = r } end
    end
    table.sort(online, function(a, b) return a.name < b.name end)
    tt:AddDoubleLine("Guild Online", tostring(#online), 1, 0.84, 0.35, 0.4, 0.9, 0.5)
    for i = 1, math.min(20, #online) do
      local x = online[i]
      tt:AddDoubleLine(ClassHex(x.r.classFile) .. x.name .. "|r", (x.r.level or "?") .. " · " .. (x.r.zone or ""), 1, 1, 1, 0.75, 0.75, 0.75)
    end
    if #online > 20 then tt:AddLine("... and " .. (#online - 20) .. " more", 0.6, 0.6, 0.6) end
    tt:AddLine(" ")
    tt:AddLine("Click: Open EPU Roster", 0.5, 0.8, 1)
  end,
  onClick = function() if SlashCmdList and SlashCmdList.EPUGUILD then SlashCmdList.EPUGUILD("roster") end end,
}

MODULES.friends = {
  text = function()
    local online = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
      online = C_FriendList.GetNumOnlineFriends() or 0
    elseif GetNumFriends then
      local _, on = GetNumFriends()
      online = on or 0
    end
    if BNGetNumFriends then
      local _, bnOn = BNGetNumFriends()
      online = online + (bnOn or 0)
    end
    return "|cff4fc3f7Friends:|r |cffffffff" .. online .. "|r"
  end,
  tooltip = function(tt)
    tt:AddLine("Friends Online", 1, 0.84, 0.35)
    local shown = 0
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
      for i = 1, (C_FriendList.GetNumFriends() or 0) do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
          shown = shown + 1
          tt:AddDoubleLine(info.name or "?", info.area or "", 0.4, 0.85, 1, 0.8, 0.8, 0.8)
        end
      end
    end
    if shown == 0 then tt:AddLine("Click to open Friends window.", 0.75, 0.75, 0.75) end
    tt:AddLine(" ")
    tt:AddLine("Click: Open Friends List", 0.5, 0.8, 1)
  end,
  onClick = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end,
}

MODULES.mail = {
  text = function()
    local has = HasNewMail and HasNewMail()
    return has and "|cff4ade80New Mail!|r" or "|cff888888No Mail|r"
  end,
  tooltip = function(tt)
    tt:AddLine("Mailbox", 1, 0.84, 0.35)
    if HasNewMail and HasNewMail() then
      local s1, s2, s3 = GetLatestThreeSenders and GetLatestThreeSenders()
      tt:AddLine("You have unread mail" .. (s1 and " from:" or "."), 0.4, 0.9, 0.5)
      for _, s in ipairs({ s1, s2, s3 }) do if SafeStr(s) then tt:AddLine("  " .. s, 1, 1, 1) end end
    else
      tt:AddLine("No unread mail.", 0.75, 0.75, 0.75)
    end
  end,
}

MODULES.epuchat = {
  text = function()
    local n = ns.ChatUnread and ns.ChatUnread() or 0
    if n > 0 then return "|cff4ade80Chat (" .. n .. ")|r" end
    return "|cff9fb4c8Chat|r"
  end,
  tooltip = function(tt)
    tt:AddLine("EPU Chat", 1, 0.84, 0.35)
    local n = ns.ChatUnread and ns.ChatUnread() or 0
    tt:AddDoubleLine("Unread messages:", tostring(n), 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Click: Toggle Pop-out Chat", 0.5, 0.8, 1)
  end,
  onClick = function() if ns.ToggleMessenger then ns.ToggleMessenger() end end,
}

MODULES.epuevents = {
  text = function()
    local g = ns.CasualStore and ns.CasualStore()
    local n, now = 0, ns.Now and ns.Now() or time()
    for _, ev in pairs(g and g.guildEvents or {}) do
      if ev.status == "scheduled" and ev.starts and ev.starts > now then n = n + 1 end
    end
    if n > 0 then return "|cffffd100Events (" .. n .. ")|r" end
    return "|cff9fb4c8Events|r"
  end,
  tooltip = function(tt)
    tt:AddLine("EPU Guild Events", 1, 0.84, 0.35)
    local g = ns.CasualStore and ns.CasualStore()
    local list, now = {}, ns.Now and ns.Now() or time()
    for _, ev in pairs(g and g.guildEvents or {}) do
      if ev.status == "scheduled" and ev.starts and ev.starts > now then list[#list + 1] = ev end
    end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    if #list == 0 then
      tt:AddLine("No upcoming guild events.", 0.75, 0.75, 0.75)
    else
      for i = 1, math.min(6, #list) do
        local ev = list[i]
        tt:AddDoubleLine(ev.title or "Event", date("%m/%d %H:%M", ev.starts), 1, 1, 1, 0.8, 0.8, 0.8)
      end
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Open EPU Calendar", 0.5, 0.8, 1)
  end,
  onClick = function() if SlashCmdList and SlashCmdList.EPUGUILD then SlashCmdList.EPUGUILD("calendar") end end,
}

MODULES.volume = {
  text = function()
    local enabled = not GetCVar or GetCVar("Sound_EnableAllSound") ~= "0"
    local vol = GetCVar and tonumber(GetCVar("Sound_MasterVolume")) or 1
    if not enabled then return "|cffff6b6bVol: Muted|r" end
    return "|cff9fb4c8Vol:|r |cffffffff" .. math.floor(vol * 100 + 0.5) .. "%|r"
  end,
  tooltip = function(tt)
    tt:AddLine("Master Volume", 1, 0.84, 0.35)
    tt:AddLine("Scroll wheel: Adjust volume", 0.85, 0.85, 0.85)
    tt:AddLine("Click: Mute / Unmute", 0.5, 0.8, 1)
  end,
  onClick = function()
    if not GetCVar or not SetCVar or (InCombatLockdown and InCombatLockdown()) then return end
    local on = GetCVar("Sound_EnableAllSound") ~= "0"
    pcall(SetCVar, "Sound_EnableAllSound", on and "0" or "1")
    if ns.RefreshInfoBars then ns.RefreshInfoBars() end
  end,
  onWheel = function(delta)
    if not GetCVar or not SetCVar or (InCombatLockdown and InCombatLockdown()) then return end
    local cur = tonumber(GetCVar("Sound_MasterVolume")) or 0.5
    local nextV = math.max(0, math.min(1, cur + delta * 0.05))
    pcall(SetCVar, "Sound_MasterVolume", string.format("%.2f", nextV))
    if ns.RefreshInfoBars then ns.RefreshInfoBars() end
  end,
}

MODULES.speed = {
  text = function()
    local cur = GetUnitSpeed and SafeNum(GetUnitSpeed("player")) or 0
    local pct = math.floor((cur / 7) * 100 + 0.5)
    local col = pct > 100 and "|cff4ade80" or (pct > 0 and "|cffffffff" or "|cff888888")
    return "|cff9fb4c8Spd:|r " .. col .. pct .. "%|r"
  end,
  tooltip = function(tt)
    local cur, run, flight, swim = 0, 7, 7, 4.7
    if GetUnitSpeed then cur, run, flight, swim = GetUnitSpeed("player") end
    tt:AddLine("Movement Speed", 1, 0.84, 0.35)
    tt:AddDoubleLine("Current:", math.floor(((cur or 0) / 7) * 100 + 0.5) .. "%", 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddDoubleLine("Ground:", math.floor(((run or 7) / 7) * 100 + 0.5) .. "%", 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddDoubleLine("Flight:", math.floor(((flight or 7) / 7) * 100 + 0.5) .. "%", 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddDoubleLine("Swim:", math.floor(((swim or 4.7) / 7) * 100 + 0.5) .. "%", 0.85, 0.85, 0.85, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Click: Open Travel & QoL Settings", 0.5, 0.8, 1)
  end,
  onClick = function() if ns.OpenWorldQoLSettings then ns.OpenWorldQoLSettings() end end,
}

MODULES.hearth = {
  text = function()
    local loc = GetBindLocation and SafeStr(GetBindLocation()) or "Hearth"
    local getCD = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    local start, dur = getCD and getCD(6948)
    start, dur = SafeNum(start) or 0, SafeNum(dur) or 0
    if start > 0 and dur > 1.5 then
      local rem = math.max(0, math.ceil((start + dur) - GetTime()))
      local cdStr = rem >= 60 and (math.ceil(rem / 60) .. "m") or (rem .. "s")
      return "|cffffd100HS:|r |cff9fb4c8" .. loc:sub(1, 10) .. "|r |cffff6b6b(" .. cdStr .. ")|r"
    end
    return "|cff4ade80HS:|r |cffffffff" .. loc:sub(1, 12) .. "|r"
  end,
  tooltip = function(tt)
    local loc = GetBindLocation and SafeStr(GetBindLocation()) or "Unknown"
    tt:AddLine("Hearthstone", 1, 0.84, 0.35)
    tt:AddDoubleLine("Bind Location:", loc, 0.85, 0.85, 0.85, 1, 1, 1)
    local getCD = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    local start, dur = getCD and getCD(6948)
    start, dur = SafeNum(start) or 0, SafeNum(dur) or 0
    if start > 0 and dur > 1.5 then
      local rem = math.max(0, math.ceil((start + dur) - GetTime()))
      tt:AddDoubleLine("Cooldown:", string.format("%dm %ds", math.floor(rem / 60), rem % 60), 0.85, 0.85, 0.85, 1, 0.4, 0.4)
    else
      tt:AddDoubleLine("Status:", "Ready", 0.85, 0.85, 0.85, 0.4, 0.9, 0.5)
    end
    tt:AddLine(" ")
    tt:AddLine("Click: Open Travel & QoL Settings", 0.5, 0.8, 1)
  end,
  onClick = function() if ns.OpenWorldQoLSettings then ns.OpenWorldQoLSettings() end end,
}

local function LayoutBar(id)
  local cfg = DB().bars[id]
  local f = barFrames[id]
  if not f then return end
  local C = ns.InterfaceColors
  local isVert = (id == "left" or id == "right")

  f:ClearAllPoints()
  if id == "top" then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    f:SetHeight(cfg.thickness)
  elseif id == "bottom" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    f:SetHeight(cfg.thickness)
  elseif id == "left" then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    f:SetWidth(cfg.thickness)
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    f:SetWidth(cfg.thickness)
  end

  f.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], cfg.bgAlpha or 0.88)
  f.edgeLine:SetShown(cfg.border ~= false)

  for _, b in ipairs(f.slots) do b:Hide() end
  local widgets = cfg.widgets or {}
  local activeSlots = {}
  for i, modId in ipairs(widgets) do
    local mod = MODULES[modId]
    if mod then
      local btn = f.slots[i]
      if not btn then
        btn = CreateFrame("Button", nil, f)
        btn.label = ns.InterfaceFont(btn, cfg.fontSize or 11, C.white)
        btn.label:SetPoint("CENTER")
        btn:EnableMouse(true)
        btn:EnableMouseWheel(true)
        btn:SetScript("OnEnter", function(self)
          local m = self.mod
          if m and m.tooltip and GameTooltip then
            GameTooltip:SetOwner(self, id == "bottom" and "ANCHOR_TOP" or (id == "top" and "ANCHOR_BOTTOM" or "ANCHOR_CURSOR"))
            GameTooltip:ClearLines()
            m.tooltip(GameTooltip)
            GameTooltip:Show()
          end
        end)
        btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        btn:SetScript("OnClick", function(self)
          if self.mod and self.mod.onClick then self.mod.onClick() end
        end)
        btn:SetScript("OnMouseWheel", function(self, delta)
          if self.mod and self.mod.onWheel then self.mod.onWheel(delta) end
        end)
        f.slots[i] = btn
      end
      btn.mod = mod
      local fnt = btn.label.GetFont and btn.label:GetFont()
      if fnt then btn.label:SetFont(fnt, cfg.fontSize or 11, "") end
      btn.label:SetText(mod.text())
      local tw = math.max(36, (btn.label:GetStringWidth() or 40) + 14)
      btn:SetSize(isVert and math.max(60, cfg.thickness - 8) or tw, isVert and 22 or math.max(18, cfg.thickness - 2))
      btn:Show()
      activeSlots[#activeSlots + 1] = btn
    end
  end

  if #activeSlots == 0 then return end
  if isVert then
    local totalH = #activeSlots * 24
    local startY = -12
    if cfg.align == "center" then startY = -math.max(12, ((f:GetHeight() or 600) - totalH) / 2)
    elseif cfg.align == "bottom" then startY = -math.max(12, (f:GetHeight() or 600) - totalH - 12) end
    for i, btn in ipairs(activeSlots) do
      btn:ClearAllPoints()
      btn:SetPoint("TOP", f, "TOP", 0, startY - (i - 1) * 24)
    end
  else
    local totalW = 0
    for _, btn in ipairs(activeSlots) do totalW = totalW + btn:GetWidth() + 6 end
    totalW = math.max(0, totalW - 6)
    local startX = 12
    if cfg.align == "center" then startX = math.max(12, ((f:GetWidth() or 1000) - totalW) / 2)
    elseif cfg.align == "right" then startX = math.max(12, (f:GetWidth() or 1000) - totalW - 12) end
    local curX = startX
    for _, btn in ipairs(activeSlots) do
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", f, "LEFT", curX, 0)
      curX = curX + btn:GetWidth() + 6
    end
  end
end

local function EnsureBar(id)
  if barFrames[id] then return barFrames[id] end
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", "EPUGuildInfoBar_" .. id, UIParent)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.edgeLine = f:CreateTexture(nil, "BORDER")
  f.edgeLine:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4] or 1)
  if id == "top" then f.edgeLine:SetPoint("BOTTOMLEFT"); f.edgeLine:SetPoint("BOTTOMRIGHT"); f.edgeLine:SetHeight(1)
  elseif id == "bottom" then f.edgeLine:SetPoint("TOPLEFT"); f.edgeLine:SetPoint("TOPRIGHT"); f.edgeLine:SetHeight(1)
  elseif id == "left" then f.edgeLine:SetPoint("TOPRIGHT"); f.edgeLine:SetPoint("BOTTOMRIGHT"); f.edgeLine:SetWidth(1)
  else f.edgeLine:SetPoint("TOPLEFT"); f.edgeLine:SetPoint("BOTTOMLEFT"); f.edgeLine:SetWidth(1) end
  f.slots = {}

  f:SetScript("OnUpdate", function(self)
    local cfg = DB().bars[id]
    if cfg and cfg.mouseover then
      self:SetAlpha(MouseIsOver(self) and 1 or 0)
    else
      self:SetAlpha(1)
    end
  end)
  barFrames[id] = f
  return f
end

function ns.RefreshInfoBars()
  local db = DB()
  local inCombat = InCombatLockdown and InCombatLockdown()
  for _, id in ipairs(BAR_ORDER) do
    local cfg = db.bars[id]
    if cfg.enabled and not (inCombat and cfg.hideInCombat) then
      local f = EnsureBar(id)
      f:Show()
      LayoutBar(id)
    elseif barFrames[id] then
      barFrames[id]:Hide()
    end
  end
end

function ns.OpenInfoBarsSettings()
  local K = ns.UIKit
  if not cfgWin then
    local C = ns.InterfaceColors
    cfgWin = ns.InterfaceWindow("EPUGuildInfoBarsConfig", UIParent, "EPU Info Bars", 440, 500)
    cfgWin:SetFrameStrata("DIALOG")
    cfgWin.widgets = {}

    local scroll = CreateFrame("ScrollFrame", nil, cfgWin)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(410); child:SetHeight(400)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    cfgWin.scroll, cfgWin.child = scroll, child

    function cfgWin:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local db = DB()
      local cfg = db.bars[selectedBar]
      local y = -4
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local b = Track(K.Btn(child, it[1], it[2], 22, it[4]))
          b:SetPoint("TOPLEFT", x, y)
          b:SetScript("OnClick", function() it[3](); ns.RefreshInfoBars(); cfgWin:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = Track(K.Font(child, 12, C.gold or C.white))
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 24
      end

      local tabs = {}
      for _, id in ipairs(BAR_ORDER) do
        local on = db.bars[id].enabled and "*" or ""
        tabs[#tabs + 1] = { BAR_LABELS[id] .. on, 96, function() selectedBar = id end, selectedBar == id and "accent" or nil }
      end
      Row(tabs)

      Heading(BAR_LABELS[selectedBar] .. " Settings")
      Row({
        { Check(cfg.enabled, "Enable " .. BAR_LABELS[selectedBar]), 190, function() cfg.enabled = not cfg.enabled end },
        { Check(cfg.hideInCombat, "Hide in combat"), 140, function() cfg.hideInCombat = not cfg.hideInCombat end },
      })
      Row({
        { Check(cfg.mouseover, "Mouseover only"), 145, function() cfg.mouseover = not cfg.mouseover end },
        { Check(cfg.border, "Show border"), 115, function() cfg.border = not cfg.border end },
        { "Align: " .. cfg.align, 110, function()
          local opts = (selectedBar == "left" or selectedBar == "right") and { "top", "center", "bottom" } or { "left", "center", "right" }
          local idx = 1
          for i, v in ipairs(opts) do if v == cfg.align then idx = i; break end end
          cfg.align = opts[(idx % #opts) + 1]
        end },
      })
      Row({
        { "Size -", 62, function() cfg.thickness = math.max(18, (cfg.thickness or 24) - ((selectedBar == "left" or selectedBar == "right") and 10 or 2)) end },
        { "Size +", 62, function() cfg.thickness = math.min(260, (cfg.thickness or 24) + ((selectedBar == "left" or selectedBar == "right") and 10 or 2)) end },
        { "Font -", 62, function() cfg.fontSize = math.max(9, (cfg.fontSize or 11) - 1) end },
        { "Font +", 62, function() cfg.fontSize = math.min(18, (cfg.fontSize or 11) + 1) end },
        { "Alpha: " .. math.floor((cfg.bgAlpha or 0.88) * 100) .. "%", 96, function()
          cfg.bgAlpha = cfg.bgAlpha <= 0.25 and 0.95 or (cfg.bgAlpha - 0.2)
        end },
      })
      Row({
        { Check(db.excludeSpecBags, "Exclude specialized bags (Ammo/Soul/Herb)"), 270, function() db.excludeSpecBags = not db.excludeSpecBags end },
        { Check(db.useRealmTime, "Realm time"), 110, function() db.useRealmTime = not db.useRealmTime end },
      })

      Heading("Active Widgets on " .. BAR_LABELS[selectedBar])
      if #cfg.widgets == 0 then
        local t = Track(K.Font(child, 11, C.muted))
        t:SetPoint("TOPLEFT", 0, y)
        t:SetText("No widgets on this bar. Add some below.")
        y = y - 22
      else
        for idx, modId in ipairs(cfg.widgets) do
          Row({
            { MODULE_LABELS[modId] or modId, 160, function() end },
            { "Up", 44, function() if idx > 1 then cfg.widgets[idx], cfg.widgets[idx - 1] = cfg.widgets[idx - 1], cfg.widgets[idx] end end },
            { "Down", 52, function() if idx < #cfg.widgets then cfg.widgets[idx], cfg.widgets[idx + 1] = cfg.widgets[idx + 1], cfg.widgets[idx] end end },
            { "Remove", 70, function() table.remove(cfg.widgets, idx) end },
          })
        end
      end

      Heading("Add Widget")
      local rowItems = {}
      for _, modId in ipairs(MODULE_ORDER) do
        rowItems[#rowItems + 1] = { "+ " .. (MODULE_LABELS[modId] or modId), 124, function() cfg.widgets[#cfg.widgets + 1] = modId end }
        if #rowItems == 3 then Row(rowItems); rowItems = {} end
      end
      if #rowItems > 0 then Row(rowItems) end
      child:SetHeight(math.max(400, -y + 20))
    end
  end
  cfgWin:Refresh()
  cfgWin:Show()
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    RecordAltGold()
    startXP = UnitXP and SafeNum(UnitXP("player")) or 0
    ns.RefreshInfoBars()
  end)
  ns.On("PLAYER_MONEY", function() RecordAltGold(); ns.RefreshInfoBars() end)
  ns.On("BAG_UPDATE", ns.RefreshInfoBars)
  ns.On("UPDATE_INVENTORY_DURABILITY", ns.RefreshInfoBars)
  ns.On("PLAYER_XP_UPDATE", function()
    local cur = UnitXP and SafeNum(UnitXP("player")) or 0
    if startXP and cur > startXP then sessionXP = sessionXP + (cur - startXP) end
    startXP = cur
    ns.RefreshInfoBars()
  end)
  ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
    if SafeStr(msg) then
      local fac, amt = msg:match("Your reputation with (.+) has increased by (%d+)")
      if fac and amt then sessionRep[fac] = (sessionRep[fac] or 0) + (tonumber(amt) or 0) end
    end
    ns.RefreshInfoBars()
  end)
  ns.On("PLAYER_REGEN_DISABLED", ns.RefreshInfoBars)
  ns.On("PLAYER_REGEN_ENABLED", ns.RefreshInfoBars)
  ns.On("ZONE_CHANGED_NEW_AREA", ns.RefreshInfoBars)
  ns.On("UPDATE_PENDING_MAIL", ns.RefreshInfoBars)
  ns.On("GUILD_ROSTER_UPDATE", ns.RefreshInfoBars)
  ns.On("FRIENDLIST_UPDATE", ns.RefreshInfoBars)
  ns.On("CURRENCY_DISPLAY_UPDATE", ns.RefreshInfoBars)
end

if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(1, function()
    local db = ns.db and ns.db.infoBars and ns.db.infoBars.bars
    if not db then return end
    for _, id in ipairs(BAR_ORDER) do
      if db[id] and db[id].enabled then
        ns.RefreshInfoBars()
        break
      end
    end
  end)
end

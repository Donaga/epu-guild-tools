-- EPU Guild Tools: Personal Trackers (Lockouts, Profession Cooldowns, Farming Session, Consumables, Rep & PvP, Rested XP),
-- and the rate bar: a small movable strip with the farming session's live rates (/epu bar).
local _, ns = ...

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

-- `local _, cf = UnitClass and UnitClass("player")` keeps only the first
-- return value, so the class file was always nil and names showed in white.
local function PlayerClassFile()
  if not UnitClass then return nil end
  local _, cf = UnitClass("player")
  return SafeStr(cf)
end

local function ClassHex(cf)
  local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if c then
    if c.colorStr then return "|c" .. c.colorStr end
    return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
  end
  return "|cffffffff"
end

local function FormatDuration(secs)
  secs = math.max(0, math.floor(secs or 0))
  local d = math.floor(secs / 86400)
  local h = math.floor((secs % 86400) / 3600)
  local m = math.floor((secs % 3600) / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm %ds", m, secs % 60)
end

local function FormatMoney(copper)
  copper = math.floor(math.abs(copper or 0))
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

local function DB()
  if not ns.db then return {} end
  ns.db.personalTrackers = ns.db.personalTrackers or {}
  local db = ns.db.personalTrackers
  db.lockouts = db.lockouts or {}
  db.cooldowns = db.cooldowns or {}
  db.consumables = db.consumables or {}
  return db
end

---------------------------------------------------------------------------
-- 1. Alt Lockouts & Reset Tracker
---------------------------------------------------------------------------
local function ScanLockouts()
  if not GetNumSavedInstances or not GetSavedInstanceInfo or not ns.me then return end
  local db = DB()
  local realm = RealmName()
  db.lockouts[realm] = db.lockouts[realm] or {}
  local cf = PlayerClassFile()
  local list = {}
  local now = time()
  local n = SafeNum(GetNumSavedInstances()) or 0
  for i = 1, n do
    local name, id, reset, _, locked, extended, _, isRaid, maxPlayers, diffName, numEnc, progress = GetSavedInstanceInfo(i)
    reset = SafeNum(reset) or 0
    if SafeStr(name) and (locked or extended) and reset > 0 then
      list[#list + 1] = {
        name = name,
        id = SafeNum(id) or 0,
        expires = now + reset,
        diff = SafeStr(diffName) or (isRaid and "Raid" or "Dungeon"),
        maxPlayers = SafeNum(maxPlayers) or 0,
        progress = SafeNum(progress) or 0,
        numEnc = SafeNum(numEnc) or 0,
      }
    end
  end
  db.lockouts[realm][ns.me] = { classFile = cf, items = list, updated = now }
end

---------------------------------------------------------------------------
-- 2. Profession Cooldown Tracker across Alts
---------------------------------------------------------------------------
local TRACKED_SPELL_CDS = {
  { id = 17187, label = "Transmute: Arcanite" },
  { id = 17559, label = "Transmute: Air to Fire" },
  { id = 17560, label = "Transmute: Fire to Earth" },
  { id = 17561, label = "Transmute: Earth to Water" },
  { id = 17562, label = "Transmute: Water to Air" },
  { id = 17563, label = "Transmute: Undeath to Water" },
  { id = 17564, label = "Transmute: Water to Undeath" },
  { id = 17565, label = "Transmute: Life to Earth" },
  { id = 17566, label = "Transmute: Earth to Life" },
  { id = 18560, label = "Mooncloth" },
  { id = 28566, label = "Transmute: Primal Air to Fire" },
  { id = 28567, label = "Transmute: Primal Earth to Water" },
  { id = 28568, label = "Transmute: Primal Fire to Earth" },
  { id = 28569, label = "Transmute: Primal Water to Air" },
  { id = 28580, label = "Transmute: Primal Shadow to Water" },
  { id = 28581, label = "Transmute: Primal Water to Shadow" },
  { id = 28582, label = "Transmute: Primal Mana to Fire" },
  { id = 28583, label = "Transmute: Primal Fire to Mana" },
  { id = 28584, label = "Transmute: Primal Life to Earth" },
  { id = 28585, label = "Transmute: Primal Earth to Life" },
  { id = 29688, label = "Transmute: Primal Might" },
}
local TRACKED_ITEM_CDS = {
  { id = 15846, label = "Salt Shaker" },
}

local function ScanCooldowns()
  if not ns.me then return end
  local db = DB()
  local realm = RealmName()
  db.cooldowns[realm] = db.cooldowns[realm] or {}
  local cf = PlayerClassFile()
  local rec = db.cooldowns[realm][ns.me] or { classFile = cf, cds = {} }
  rec.classFile = cf
  rec.cds = rec.cds or {}
  local now = time()
  local gt = GetTime and GetTime() or 0

  for _, sp in ipairs(TRACKED_SPELL_CDS) do
    local known = (IsSpellKnown and IsSpellKnown(sp.id)) or (IsPlayerSpell and IsPlayerSpell(sp.id))
    if known then
      local start, dur
      if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(sp.id)
        if info then start, dur = info.startTime, info.duration end
      elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(sp.id)
      end
      start, dur = SafeNum(start) or 0, SafeNum(dur) or 0
      if start > 0 and dur > 60 then
        local rem = math.max(0, (start + dur) - gt)
        rec.cds[sp.label] = now + rem
      else
        rec.cds[sp.label] = 0
      end
    end
  end

  local getItemCD = C_Container and C_Container.GetItemCooldown or GetItemCooldown
  if getItemCD then
    for _, it in ipairs(TRACKED_ITEM_CDS) do
      local count = GetItemCount and SafeNum(GetItemCount(it.id)) or 0
      if count > 0 then
        local start, dur = getItemCD(it.id)
        start, dur = SafeNum(start) or 0, SafeNum(dur) or 0
        if start > 0 and dur > 60 then
          local rem = math.max(0, (start + dur) - gt)
          rec.cds[it.label] = now + rem
        else
          rec.cds[it.label] = 0
        end
      end
    end
  end
  db.cooldowns[realm][ns.me] = rec
end

-- SPELL_UPDATE_COOLDOWN and BAG_UPDATE_COOLDOWN fire on every global
-- cooldown, so in combat they come several times a second. Profession
-- cooldowns only change when you craft, so fold a burst of updates into one
-- scan a few seconds later, and wait for the end of combat to do it.
local CD_SCAN_DELAY = 3
local cdScanWaiting = false

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function QueueCooldownScan()
  if InCombat() then cdScanWaiting = true; return end
  ns.Debounce("personalTrackers:cooldowns", CD_SCAN_DELAY, function()
    if InCombat() then cdScanWaiting = true; return end
    ScanCooldowns()
  end)
end

---------------------------------------------------------------------------
-- 3. Farming / Grinding Session Tracker
---------------------------------------------------------------------------
local farm = {
  running = true,
  startedAt = time(),
  pausedElapsed = 0,
  xp = 0,
  lastXP = nil,
  lastXPMax = nil,
  cash = 0,
  lootValue = 0,
  net = 0,         -- change in the gold you carry while the session runs
  kills = 0,       -- kills that gave XP ("X dies, you gain N experience")
  killXP = 0,
  rep = 0,
  repLast = nil,   -- the faction you last gained reputation with
  honor = 0,
  drops = {},
  deaths = 0,
  repairs = 0,      -- gold you paid for repairs this session
  guildRepairs = 0, -- repairs the guild bank paid for
  questXP = 0,      -- XP from turning in quests
  skillups = 0,     -- profession skill points gained
  skills = {},      -- [profession] = { gained = n, rank = n }
}

local function ReadXP()
  local cur = UnitXP and SafeNum(UnitXP("player")) or 0
  local max = UnitXPMax and SafeNum(UnitXPMax("player")) or 0
  return cur, max
end

-- XP gained since the last update. A level up resets the bar, so the gain is
-- what was left of the old level plus what's on the new one.
local function TakeXPGain()
  local cur, max = ReadXP()
  local gained = 0
  if farm.lastXP then
    if cur > farm.lastXP then
      gained = cur - farm.lastXP
    elseif cur < farm.lastXP and (farm.lastXPMax or 0) > farm.lastXP then
      gained = (farm.lastXPMax - farm.lastXP) + cur
    end
  end
  farm.lastXP, farm.lastXPMax = cur, max
  return gained
end

local function FarmElapsed()
  if farm.running then
    return farm.pausedElapsed + math.max(1, time() - farm.startedAt)
  end
  return math.max(1, farm.pausedElapsed)
end

local function ResetFarmSession()
  farm.startedAt = time()
  farm.pausedElapsed = 0
  farm.xp = 0
  farm.lastXP, farm.lastXPMax = ReadXP()
  farm.cash = 0
  farm.lootValue = 0
  farm.net = 0
  farm.kills, farm.killXP = 0, 0
  farm.rep, farm.repLast = 0, nil
  farm.honor = 0
  farm.drops = {}
  farm.deaths, farm.repairs, farm.guildRepairs = 0, 0, 0
  farm.questXP = 0
  farm.skillups, farm.skills = 0, {}
  farm.lastMoney = GetMoney and SafeNum(GetMoney()) or nil
end

local function ToggleFarmPause()
  if farm.running then
    farm.pausedElapsed = farm.pausedElapsed + math.max(0, time() - farm.startedAt)
    farm.running = false
  else
    farm.startedAt = time()
    farm.running = true
  end
end

-- Repairs. Repair all (yours or the guild bank's, by hand or EPU's auto
-- repair) goes through RepairAllItems; the gold leaves a moment later, so the
-- next drop in your gold within a few seconds is the repair. A single item
-- repaired with the repair cursor is a drop in gold while the cursor is up.
local REPAIR_WINDOW = 4
local pendingRepair

local function OnRepairAll(guild)
  local cost = GetRepairAllCost and SafeNum((GetRepairAllCost())) or 0
  if guild then
    if farm.running and cost > 0 then farm.guildRepairs = farm.guildRepairs + cost end
    return
  end
  pendingRepair = { cost = cost > 0 and cost or nil, t = GetTime and GetTime() or 0 }
end

-- Called with each drop in the gold you carry; counts what was a repair.
local function TakeRepairSpend(spent)
  if spent <= 0 then return end
  local now = GetTime and GetTime() or 0
  if pendingRepair and now - pendingRepair.t <= REPAIR_WINDOW then
    local amt = pendingRepair.cost and math.min(spent, pendingRepair.cost) or spent
    pendingRepair = nil
    if farm.running then farm.repairs = farm.repairs + amt end
  elseif InRepairMode and InRepairMode() then
    if farm.running then farm.repairs = farm.repairs + spent end
  end
end

-- Quest XP arrives twice in most clients: QUEST_TURNED_IN carries the XP
-- reward and the "Experience gained: N." system line says it again. Count a
-- reward once, from whichever comes first.
local lastQuestXP

local function AddQuestXP(amount, source)
  amount = SafeNum(amount) or 0
  if amount <= 0 or not farm.running then return end
  local now = GetTime and GetTime() or 0
  local l = lastQuestXP
  if l and l.source ~= source and l.amount == amount and now - l.t <= 3 then
    lastQuestXP = nil
    return
  end
  lastQuestXP = { amount = amount, source = source, t = now }
  farm.questXP = farm.questXP + amount
end

-- Turn a game message format ("Experience gained: %d.") into a pattern.
local function FormatToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]])", "%%%1")
  p = p:gsub("%%%d?%$?d", "(%%d+)"):gsub("%%%d?%$?s", "(.+)")
  return p
end
local QUEST_XP_PATTERN = FormatToPattern(ERR_QUEST_REWARD_EXP_I) or "Experience gained: (%d+)%."
local SKILL_UP_PATTERN = FormatToPattern(SKILL_RANK_UP) or "Your skill in (.+) has increased to (%d+)%."

-- Professions, so weapon skills and Defense going up don't count.
local PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
  Leatherworking = true, Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true,
  Inscription = true, Cooking = true, ["First Aid"] = true, Fishing = true,
}
local PROFESSION_HEADERS = { Professions = true, ["Secondary Skills"] = true }
if TRADE_SKILLS then PROFESSION_HEADERS[TRADE_SKILLS] = true end
if SECONDARY_SKILLS then PROFESSION_HEADERS[SECONDARY_SKILLS] = true end

local function IsProfession(name)
  if PROFESSIONS[name] then return true end
  -- Other languages or custom professions: look where the skill sits in the
  -- skill list.
  if not GetNumSkillLines or not GetSkillLineInfo then return false end
  local header
  for i = 1, (SafeNum(GetNumSkillLines()) or 0) do
    local n, isHeader = GetSkillLineInfo(i)
    if isHeader then header = n elseif n == name then return PROFESSION_HEADERS[header] == true end
  end
  return false
end

local function OnSkillUp(msg)
  local name, rank = msg:match(SKILL_UP_PATTERN)
  rank = tonumber(rank)
  if not name or not rank or not IsProfession(name) then return end
  local rec = farm.skills[name]
  -- One message per point, but count a jump of more than one if it comes.
  local gained = (rec and rec.rank and rank > rec.rank) and (rank - rec.rank) or 1
  if not farm.running then
    if rec then rec.rank = rank end
    return
  end
  rec = rec or { gained = 0 }
  rec.gained, rec.rank = rec.gained + gained, rank
  farm.skills[name] = rec
  farm.skillups = farm.skillups + gained
end

-- Kill and quest XP as shares of the session's XP. Anything else
-- (exploration, gathering, and the like) is what's left.
local function XPSplit()
  local total = math.max(farm.xp, farm.questXP + farm.killXP)
  local other = math.max(0, total - farm.questXP - farm.killXP)
  local function Pct(n) return total > 0 and math.floor(n / total * 100 + 0.5) or 0 end
  return { total = total, quest = farm.questXP, kill = farm.killXP, other = other,
    questPct = Pct(farm.questXP), killPct = Pct(farm.killXP), otherPct = Pct(other) }
end

local function SkillList()
  local names = {}
  for n in pairs(farm.skills) do names[#names + 1] = n end
  table.sort(names, function(a, b)
    local ga, gb = farm.skills[a].gained, farm.skills[b].gained
    if ga ~= gb then return ga > gb end
    return a < b
  end)
  local out = {}
  for _, n in ipairs(names) do
    out[#out + 1] = string.format("%s +%d (now %d)", n, farm.skills[n].gained, farm.skills[n].rank or 0)
  end
  return out
end

---------------------------------------------------------------------------
-- 4. Personal Consumable Checklist
---------------------------------------------------------------------------
local PRESET_CONSUMABLES = {
  { id = 13446, name = "Major Healing Potion", target = 10 },
  { id = 13444, name = "Major Mana Potion", target = 10 },
  { id = 14530, name = "Heavy Runecloth Bandage", target = 20 },
  { id = 13510, name = "Flask of the Titans", target = 2 },
  { id = 13512, name = "Flask of Supreme Power", target = 2 },
  { id = 13457, name = "Greater Fire Protection Potion", target = 5 },
}

local function CountOwnedItem(itemID)
  local localCount = GetItemCount and SafeNum(GetItemCount(itemID, true)) or 0
  local altTotal = 0
  local altItems = ns.db and ns.db.worldQoL and ns.db.worldQoL.altItems
  local realm = RealmName()
  if altItems and altItems[realm] then
    for who, rec in pairs(altItems[realm]) do
      if who ~= ns.me then
        altTotal = altTotal + (rec.bags and rec.bags[itemID] or 0) + (rec.bank and rec.bank[itemID] or 0)
      end
    end
  end
  return localCount, altTotal
end

---------------------------------------------------------------------------
-- 5. Rep & PvP Grind Estimator
---------------------------------------------------------------------------
local repSession = {}
local pvpSession = { honor = 0, hks = 0, startHKs = nil }

local function GetAllFactions()
  local out = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    for i = 1, (C_Reputation.GetNumFactions() or 0) do
      local ok, d = pcall(C_Reputation.GetFactionDataByIndex, i)
      if ok and type(d) == "table" and not d.isHeader and SafeStr(d.name) then
        out[d.name] = {
          standing = d.reaction or 4,
          minV = SafeNum(d.currentReactionThreshold) or 0,
          maxV = SafeNum(d.nextReactionThreshold) or 1,
          curV = SafeNum(d.currentStanding) or 0,
        }
      end
    end
  elseif GetNumFactions and GetFactionInfo then
    for i = 1, (GetNumFactions() or 0) do
      local ok, name, _, standing, minV, maxV, curV, _, _, isHeader = pcall(GetFactionInfo, i)
      if ok and not isHeader and SafeStr(name) then
        out[name] = {
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

---------------------------------------------------------------------------
-- UI (/epu trackers)
---------------------------------------------------------------------------
local win
local activeTab = "lockouts"

function ns.OpenPersonalTrackers(tab)
  if tab then activeTab = tab end
  if not win then
    local C = ns.InterfaceColors
    win = ns.InterfaceWindow("EPUGuildPersonalTrackers", UIParent, "EPU Personal Trackers", 620, 500)
    win:SetFrameStrata("DIALOG")

    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(590); child:SetHeight(420)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    win.scroll, win.child = scroll, child
    -- The game never frees a widget, so each refresh reuses the last one's.
    win.pool = ns.NewWidgetPool(child)

    function win:Refresh()
      local pool = self.pool
      pool:ReleaseAll()
      local db = DB()
      local C = ns.InterfaceColors
      local y = -4
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local btn = pool:Button(it[1], it[2], 22, it[4])
          btn:SetPoint("TOPLEFT", x, y)
          btn:SetScript("OnClick", function() it[3](); win:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = pool:Font(12, C.gold or C.white, "heading")
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 22
      end
      local function Line(txt, col)
        local f = pool:Font(11, col or C.text, "line")
        f:SetPoint("TOPLEFT", 4, y)
        f:SetWidth(580)
        f:SetJustifyH("LEFT")
        f:SetText(txt)
        y = y - 18
      end

      Row({
        { "Lockouts", 84, function() activeTab = "lockouts" end, activeTab == "lockouts" and "accent" or nil },
        { "Cooldowns", 90, function() activeTab = "cooldowns" end, activeTab == "cooldowns" and "accent" or nil },
        { "Session", 76, function() activeTab = "session" end, activeTab == "session" and "accent" or nil },
        { "Consumables", 104, function() activeTab = "consumables" end, activeTab == "consumables" and "accent" or nil },
        { "Rep & PvP", 92, function() activeTab = "reppvp" end, activeTab == "reppvp" and "accent" or nil },
        { "Rested XP", 84, function() activeTab = "rested" end, activeTab == "rested" and "accent" or nil },
      })

      local realm = RealmName()
      local now = time()

      if activeTab == "lockouts" then
        ScanLockouts()
        Heading("Active Raid & Dungeon Lockouts (" .. realm .. ")")
        Row({ { "Refresh Raid Info", 140, function() if RequestRaidInfo then RequestRaidInfo() end; ScanLockouts() end } })
        local any = false
        for who, rec in pairs(db.lockouts[realm] or {}) do
          local active = {}
          for _, it in ipairs(rec.items or {}) do
            if (it.expires or 0) > now then active[#active + 1] = it end
          end
          if #active > 0 then
            any = true
            Line(ClassHex(rec.classFile) .. (ns.Short and ns.Short(who) or who) .. "|r")
            for _, it in ipairs(active) do
              local prog = it.numEnc > 0 and string.format(" (%d/%d)", it.progress, it.numEnc) or ""
              Line(string.format("   %s [%s]%s  -  |cff4fc3f7Resets in %s|r", it.name, it.diff, prog, FormatDuration(it.expires - now)))
            end
          end
        end
        if not any then Line("No active lockouts recorded on this realm.", C.muted) end

      elseif activeTab == "cooldowns" then
        ScanCooldowns()
        Heading("Profession Cooldowns Across Alts (" .. realm .. ")")
        local any = false
        for who, rec in pairs(db.cooldowns[realm] or {}) do
          if rec.cds and next(rec.cds) then
            any = true
            Line(ClassHex(rec.classFile) .. (ns.Short and ns.Short(who) or who) .. "|r")
            for label, readyAt in pairs(rec.cds) do
              if readyAt == 0 or readyAt <= now then
                Line("   " .. label .. ":  |cff4ade80READY|r")
              else
                Line("   " .. label .. ":  |cffffd100" .. FormatDuration(readyAt - now) .. "|r")
              end
            end
          end
        end
        if not any then Line("No tracked profession cooldowns detected yet. Open your profession/bags on each alt.", C.muted) end

      elseif activeTab == "session" then
        local elapsed = FarmElapsed()
        local xph = math.floor((farm.xp / elapsed) * 3600)
        local totalGold = farm.cash + farm.lootValue
        local gph = math.floor((totalGold / elapsed) * 3600)
        Heading("Farming / Grinding Session")
        Row({
          { farm.running and "Pause" or "Resume", 84, function() ToggleFarmPause() end },
          { "Reset Session", 110, function() ResetFarmSession() end },
          { ns.RateBarShown and ns.RateBarShown() and "Hide rate bar" or "Show rate bar", 110, function() ns.ToggleRateBar() end, "accent" },
          { "Rate bar settings", 128, function() ns.OpenRateBarSettings() end },
        })
        Line(string.format("Elapsed: |cffffffff%s|r", FormatDuration(elapsed)))
        Line(string.format("XP Gained: |cff4fc3f7%d|r (%d/hr)", farm.xp, xph))
        Line(string.format("Kills that gave XP: |cff4fc3f7%d|r (%d/hr)", farm.kills, math.floor((farm.kills / elapsed) * 3600)))
        local split = XPSplit()
        if split.total > 0 then
          Line(string.format("XP from quests: |cff4fc3f7%d|r (%d%%)    from kills: |cff4fc3f7%d|r (%d%%)    other: |cff4fc3f7%d|r (%d%%)",
            split.quest, split.questPct, split.kill, split.killPct, split.other, split.otherPct))
        end
        local repairs = string.format("Deaths: |cffff6b6b%d|r    Repairs you paid: |cffffd100%s|r", farm.deaths, FormatMoney(farm.repairs))
        if farm.guildRepairs > 0 then repairs = repairs .. string.format("    Guild bank paid: |cffffd100%s|r", FormatMoney(farm.guildRepairs)) end
        Line(repairs)
        Line(string.format("Profession skill-ups: |cff4ade80%d|r (%d/hr)", farm.skillups, math.floor((farm.skillups / elapsed) * 3600)))
        for _, sk in ipairs(SkillList()) do Line("   " .. sk) end
        Line(string.format("Cash Looted: |cffffd100%s|r    Item Vendor Value: |cffffd100%s|r", FormatMoney(farm.cash), FormatMoney(farm.lootValue)))
        Line(string.format("Total Value: |cff4ade80%s|r (%s/hr)", FormatMoney(totalGold), FormatMoney(gph)))
        if farm.repairs > 0 then
          local after = totalGold - farm.repairs
          Line(string.format("After repairs: |cff4ade80%s%s|r (%s%s/hr)", after < 0 and "-" or "", FormatMoney(after),
            after < 0 and "-" or "", FormatMoney(math.floor((after / elapsed) * 3600))))
        end
        Heading("Notable Drops (" .. #farm.drops .. ")")
        if #farm.drops == 0 then
          Line("No uncommon+ drops looted in this session yet.", C.muted)
        else
          for i = #farm.drops, math.max(1, #farm.drops - 14), -1 do
            Line("   " .. farm.drops[i])
          end
        end

      elseif activeTab == "consumables" then
        Heading("Personal Consumables Checklist")
        local box = pool:Input(200, "Item ID or Preset below...", "consumable")
        box:SetPoint("TOPLEFT", 0, y)
        local addBtn = pool:Button("+ Add (x10)", 96, 22, "accent")
        addBtn:SetPoint("LEFT", box, "RIGHT", 6, 0)
        addBtn:SetScript("OnClick", function()
          local id = tonumber(box:GetText())
          if id then
            local name = (GetItemInfo and SafeStr(GetItemInfo(id))) or ("Item " .. id)
            db.consumables[#db.consumables + 1] = { id = id, name = name, target = 10 }
            win:Refresh()
          else
            ns.Print("Enter a numeric Item ID or use a quick preset below.")
          end
        end)
        y = y - 30

        if #db.consumables == 0 then
          Line("No consumables tracked yet. Add presets below:", C.muted)
        else
          for idx, item in ipairs(db.consumables) do
            local have, alts = CountOwnedItem(item.id)
            local tgt = item.target or 10
            local col = have >= tgt and "|cff4ade80" or (have > 0 and "|cffffd100" or "|cffff6b6b")
            local altNote = alts > 0 and (" |cff888888(+" .. alts .. " on alts)|r") or ""
            Row({
              { string.format("%s: %s%d/%d|r%s", (item.name or ("#" .. item.id)):sub(1, 22), col, have, tgt, altNote), 280, function() end },
              { "-5", 38, function() item.target = math.max(1, (item.target or 10) - 5) end },
              { "+5", 38, function() item.target = (item.target or 10) + 5 end },
              { "x", 28, function() table.remove(db.consumables, idx) end },
            })
          end
        end

        Heading("Quick Add Presets")
        local pRow = {}
        for _, p in ipairs(PRESET_CONSUMABLES) do
          pRow[#pRow + 1] = { "+ " .. p.name:sub(1, 18), 160, function()
            db.consumables[#db.consumables + 1] = { id = p.id, name = p.name, target = p.target }
          end }
          if #pRow == 3 then Row(pRow); pRow = {} end
        end
        if #pRow > 0 then Row(pRow) end

      elseif activeTab == "reppvp" then
        Heading("Session PvP")
        Line(string.format("Session Honor: |cffffd100%d|r    Session HKs: |cff4ade80%d|r", pvpSession.honor, pvpSession.hks))

        Heading("Reputation Grind Estimator (This Session)")
        local factions = GetAllFactions()
        local anyRep = false
        for fac, st in pairs(repSession) do
          anyRep = true
          local elapsed = math.max(1, now - (st.startedAt or farm.startedAt))
          local rph = math.floor((st.gained / elapsed) * 3600)
          local fData = factions[fac]
          local eta = ""
          if fData and st.lastGain and st.lastGain > 0 and fData.maxV > fData.curV then
            local rem = fData.maxV - fData.curV
            local gains = math.ceil(rem / st.lastGain)
            eta = string.format("  ·  |cff4fc3f7%d to next rank (~%d gains)|r", rem, gains)
          end
          Line(string.format("%s: |cff4ade80+%d|r (%d/hr)%s", fac, st.gained, rph, eta))
        end
        if not anyRep then Line("Earn reputation with any faction this session to see Rep/hr & ETA.", C.muted) end

      elseif activeTab == "rested" and ns.RestedAlts then
        if ns.RecordRested then ns.RecordRested(false) end
        Heading("Rested XP Across Alts (" .. realm .. ")")
        local alts = ns.RestedAlts(now)
        local anyAway = false
        for _, a in ipairs(alts) do
          local rec = a.rec
          local who = ClassHex(rec.classFile) .. (ns.Short and ns.Short(a.name) or a.name) .. "|r"
          local lvl = "Level " .. (rec.level or "?")
          if a.live then lvl = lvl .. ", this character" end
          Line(who .. "  |cff888888" .. lvl .. "|r")
          if rec.xpOff then
            Line("   XP gain is turned off on this character.", C.muted)
          elseif rec.maxed then
            Line("   Max level, so rested XP doesn't matter.", C.muted)
          else
            local pct = math.floor(a.pct * 100 + 0.5)
            local col = a.toFull == 0 and "|cff4ade80" or (pct >= 50 and "|cff4fc3f7" or "|cffffd100")
            local txt = string.format("   %s%d%% of a level|r (%d bubbles, %d XP)", col, pct, math.floor(pct / 5), a.rested)
            if a.toFull == 0 then
              txt = txt .. "  -  |cff4ade80Full|r"
            else
              txt = txt .. "  -  full in " .. FormatDuration(a.toFull)
            end
            Line(txt)
            local where
            if a.live then
              where = rec.resting and "Resting now" or "Not resting now"
            else
              where = (rec.resting and "Logged out resting, " or "Logged out outside an inn or city, ")
                .. FormatDuration(now - (rec.logout or rec.seen or now)) .. " ago (estimate)"
              if not rec.resting and a.toFull > 0 then anyAway = true end
            end
            Line("   |cff888888" .. where .. "|r")
          end
        end
        if #alts == 0 then Line("Log in on each character once to start tracking its rested XP.", C.muted) end
        if anyAway then
          Line("Characters logged out in an inn or city build rested XP four times faster.", C.muted)
        end
      end

      child:SetHeight(math.max(420, -y + 20))
    end
  end
  win:Refresh()
  win:Show()
end

if hooksecurefunc and RepairAllItems then
  hooksecurefunc("RepairAllItems", function(guild) pcall(OnRepairAll, guild) end)
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    farm.lastXP, farm.lastXPMax = ReadXP()
    farm.lastMoney = GetMoney and SafeNum(GetMoney()) or nil
    if RequestRaidInfo then RequestRaidInfo() end
    ScanLockouts()
    ScanCooldowns()
    if GetPVPSessionStats then
      local hk = GetPVPSessionStats()
      pvpSession.startHKs = SafeNum(hk) or 0
    end
    local db = DB()
    local realm = RealmName()
    local now = time()
    for who, rec in pairs(db.cooldowns[realm] or {}) do
      for label, readyAt in pairs(rec.cds or {}) do
        if readyAt > 0 and readyAt <= now then
          ns.Print(string.format("|cff4ade80Cooldown Ready:|r %s — %s", ns.Short and ns.Short(who) or who, label))
        end
      end
    end
  end)
  ns.On("UPDATE_INSTANCE_INFO", ScanLockouts)
  ns.On("SPELL_UPDATE_COOLDOWN", QueueCooldownScan)
  ns.On("BAG_UPDATE_COOLDOWN", QueueCooldownScan)
  ns.On("PLAYER_REGEN_ENABLED", function()
    if cdScanWaiting then cdScanWaiting = false; QueueCooldownScan() end
  end)
  ns.On("PLAYER_XP_UPDATE", function()
    -- Read it even while paused, so resuming doesn't count XP from the pause.
    local gained = TakeXPGain()
    if farm.running then farm.xp = farm.xp + gained end
  end)
  ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    if not farm.running or not SafeStr(msg) then return end
    local amt = tonumber(msg:match(" dies, you gain (%d+) experience"))
    if amt then farm.kills = farm.kills + 1; farm.killXP = farm.killXP + amt end
  end)
  ns.On("PLAYER_MONEY", function()
    local cur = GetMoney and SafeNum(GetMoney())
    if not cur then return end
    if farm.lastMoney then
      if farm.running then farm.net = farm.net + (cur - farm.lastMoney) end
      TakeRepairSpend(farm.lastMoney - cur)
    end
    farm.lastMoney = cur
  end)
  ns.On("PLAYER_DEAD", function()
    if not farm.running then return end
    if UnitIsFeignDeath and UnitIsFeignDeath("player") then return end
    farm.deaths = farm.deaths + 1
  end)
  ns.On("QUEST_TURNED_IN", function(_, xp) AddQuestXP(xp, "event") end)
  ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not SafeStr(msg) then return end
    local amt = msg:match(QUEST_XP_PATTERN)
    if amt then AddQuestXP(tonumber(amt), "chat") end
  end)
  ns.On("CHAT_MSG_SKILL", function(msg)
    if SafeStr(msg) then OnSkillUp(msg) end
  end)
  ns.On("CHAT_MSG_MONEY", function(msg)
    if not farm.running or not SafeStr(msg) then return end
    local g = tonumber(msg:match("(%d+) Gold")) or 0
    local s = tonumber(msg:match("(%d+) Silver")) or 0
    local c = tonumber(msg:match("(%d+) Copper")) or 0
    farm.cash = farm.cash + g * 10000 + s * 100 + c
  end)
  ns.On("CHAT_MSG_LOOT", function(msg)
    if not farm.running or not SafeStr(msg) then return end
    if msg:find("You receive loot:", 1, true) then
      local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
      if link and GetItemInfo then
        -- Called directly: `GetItemInfo and GetItemInfo(link)` kept only the
        -- name, so quality and sell price were nil and loot value stayed 0.
        local _, _, q, _, _, _, _, _, _, _, sell = GetItemInfo(link)
        sell = SafeNum(sell) or 0
        local qty = tonumber(msg:match("|h|r%s*x(%d+)")) or 1
        farm.lootValue = farm.lootValue + sell * qty
        if SafeNum(q) and q >= 2 then
          farm.drops[#farm.drops + 1] = link .. (qty > 1 and (" x" .. qty) or "")
          if #farm.drops > 40 then table.remove(farm.drops, 1) end
        end
      end
    end
  end)
  ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
    if not SafeStr(msg) then return end
    local fac, amt = msg:match("Your reputation with (.+) has increased by (%d+)")
    amt = tonumber(amt)
    if fac and amt then
      repSession[fac] = repSession[fac] or { startedAt = time(), gained = 0, lastGain = 0 }
      repSession[fac].gained = repSession[fac].gained + amt
      repSession[fac].lastGain = amt
      if farm.running then farm.rep = farm.rep + amt; farm.repLast = fac end
    end
  end)
  ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
    if not SafeStr(msg) then return end
    local amt = tonumber(msg:match("(%d+) honor"))
    if amt then
      pvpSession.honor = pvpSession.honor + amt
      if farm.running then farm.honor = farm.honor + amt end
    end
    if GetPVPSessionStats then
      local hk = SafeNum(GetPVPSessionStats()) or 0
      if pvpSession.startHKs then pvpSession.hks = math.max(0, hk - pvpSession.startHKs) end
    end
  end)
end

---------------------------------------------------------------------------
-- Rate bar (/epu bar): a small strip with the session's live rates
---------------------------------------------------------------------------
-- It reads the same farming session as the Session tab, so Pause and Reset
-- there pause and reset the bar too. Which rates show, the size, the layout
-- and the lock are account-wide (ns.db.rateBar); whether the bar is shown and
-- where it sits are saved per character (ns.cdb.rateBar).

local function Commas(n)
  n = math.floor((n or 0) + 0.5)
  local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. s
end

-- 12,345 -> 12.3k; 1,234,567 -> 1.23m; small numbers keep their commas.
local function Short(n)
  n = n or 0
  local a = math.abs(n)
  if a >= 1000000 then return string.format("%.2fm", n / 1000000) end
  if a >= 10000 then return string.format("%.1fk", n / 1000) end
  return Commas(n)
end

local function SignedMoney(copper)
  copper = math.floor(copper or 0)
  return (copper < 0 and "-" or "") .. FormatMoney(copper)
end

-- Short durations for the bar: "1h 12m", "12m", "45s".
local function BarDuration(secs)
  secs = math.max(0, math.floor(secs or 0))
  if secs >= 86400 then return FormatDuration(secs) end
  local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
  if h > 0 then return string.format("%dh %dm", h, m) end
  if m > 0 then return string.format("%dm", m) end
  return string.format("%ds", secs)
end

local function PerHour(amount, elapsed) return (amount or 0) / math.max(1, elapsed) * 3600 end

-- True when this character can't gain XP (max level, or XP turned off).
local function NoXP()
  local level = UnitLevel and SafeNum(UnitLevel("player")) or 0
  local maxLevel = GetMaxPlayerLevel and SafeNum(GetMaxPlayerLevel()) or 60
  if level >= maxLevel then return true end
  return IsXPUserDisabled and IsXPUserDisabled() and true or false
end

-- What the bar can show, in the order it shows them. `xp` stats hide
-- themselves on a character that can't gain XP. Each value() returns the
-- bar text and the longer tooltip text.
local RATE_STATS = {
  { id = "xphr", label = "XP/hr", name = "XP per hour", on = true, xp = true, value = function(s)
      local v = PerHour(farm.xp, s.elapsed)
      return Short(v), Commas(v) .. " XP per hour (" .. Commas(farm.xp) .. " this session)"
    end },
  { id = "ttl", label = "Level in", name = "Time to level", on = true, xp = true, value = function(s)
      local rate = PerHour(farm.xp, s.elapsed)
      local left = math.max(0, s.xpMax - s.xp)
      if rate <= 0 or s.xpMax <= 0 then return "--", "Gain some XP to see how long the level takes" end
      local secs = left / rate * 3600
      return BarDuration(secs), BarDuration(secs) .. " to level " .. (s.level + 1) .. " at this rate (" .. Commas(left) .. " XP to go)"
    end },
  { id = "xp", label = "XP", name = "XP this session", xp = true, value = function()
      return Short(farm.xp), Commas(farm.xp) .. " XP this session"
    end },
  { id = "level", label = "Lvl", name = "Level progress", xp = true, value = function(s)
      local pct = s.xpMax > 0 and math.floor(s.xp / s.xpMax * 100) or 0
      return s.level .. " " .. pct .. "%", "Level " .. s.level .. ", " .. pct .. "% of the way to " .. (s.level + 1)
    end },
  { id = "rested", label = "Rested", name = "Rested XP", xp = true, value = function(s)
      local r = GetXPExhaustion and SafeNum(GetXPExhaustion()) or 0
      local pct = s.xpMax > 0 and math.floor(r / s.xpMax * 100 + 0.5) or 0
      return pct .. "%", Commas(r) .. " rested XP (" .. pct .. "% of a level)"
    end },
  { id = "kills", label = "Kills/hr", name = "Kills per hour", value = function(s)
      local v = PerHour(farm.kills, s.elapsed)
      return Commas(v), Commas(v) .. " kills per hour (" .. farm.kills .. " this session that gave XP)"
    end },
  { id = "killsleft", label = "Kills to lvl", name = "Kills to level", xp = true, value = function(s)
      if farm.kills == 0 or farm.killXP <= 0 then return "--", "Kill something that gives XP to see how many kills the level takes" end
      local per = farm.killXP / farm.kills
      local n = math.ceil(math.max(0, s.xpMax - s.xp) / per)
      return Commas(n), "About " .. Commas(n) .. " kills to level, at " .. Commas(per) .. " XP a kill"
    end },
  { id = "goldhr", label = "Gold/hr", name = "Gold per hour (loot)", on = true, value = function(s)
      local total = farm.cash + farm.lootValue
      local v = PerHour(total, s.elapsed)
      local long = FormatMoney(v) .. " per hour from looted coin and the vendor value of looted items ("
        .. FormatMoney(total) .. " this session)"
      if farm.repairs > 0 then
        long = long .. "; " .. SignedMoney(PerHour(total - farm.repairs, s.elapsed)) .. " per hour after repairs"
      end
      return FormatMoney(v), long
    end },
  { id = "nethr", label = "Net/hr", name = "Net gold per hour", value = function(s)
      local v = PerHour(farm.net, s.elapsed)
      return SignedMoney(v), SignedMoney(v) .. " per hour: the change in the gold you carry, after spending ("
        .. SignedMoney(farm.net) .. " this session" .. (farm.repairs > 0 and (", repairs of " .. FormatMoney(farm.repairs) .. " included") or "") .. ")"
    end },
  { id = "deaths", label = "Deaths", name = "Deaths and repairs", value = function(s)
      local short = farm.deaths .. " |cffa3b0c2Repairs|r " .. FormatMoney(farm.repairs)
      local long = farm.deaths .. (farm.deaths == 1 and " death" or " deaths") .. " this session. Repairs cost you "
        .. FormatMoney(farm.repairs) .. " (" .. FormatMoney(PerHour(farm.repairs, s.elapsed)) .. " per hour)"
      if farm.guildRepairs > 0 then long = long .. "; the guild bank paid " .. FormatMoney(farm.guildRepairs) .. " more" end
      return short, long .. ". Net gold per hour already counts repairs you paid."
    end },
  { id = "xpsplit", label = "Quest/Kill XP", name = "Quest XP vs kill XP", xp = true, value = function()
      local x = XPSplit()
      if x.total <= 0 then return "--", "Gain some XP to see how much comes from quests and how much from kills" end
      return x.questPct .. "% / " .. x.killPct .. "%", string.format(
        "XP from quests: %s (%d%%). From kills: %s (%d%%). Other, such as exploring: %s (%d%%).",
        Commas(x.quest), x.questPct, Commas(x.kill), x.killPct, Commas(x.other), x.otherPct)
    end },
  { id = "skillhr", label = "Skill-ups/hr", name = "Profession skill-ups/hr", value = function(s)
      local v = PerHour(farm.skillups, s.elapsed)
      local long = Commas(v) .. " profession skill-ups per hour (" .. farm.skillups .. " this session)"
      local list = SkillList()
      if #list > 0 then long = long .. ": " .. table.concat(list, ", ") end
      return Commas(v), long
    end },
  { id = "rephr", label = "Rep/hr", name = "Reputation per hour", value = function(s)
      local v = PerHour(farm.rep, s.elapsed)
      return Short(v), Commas(v) .. " reputation per hour (" .. Commas(farm.rep) .. " this session"
        .. (farm.repLast and (", last with " .. farm.repLast) or "") .. ")"
    end },
  { id = "honorhr", label = "Honor/hr", name = "Honor per hour", value = function(s)
      local v = PerHour(farm.honor, s.elapsed)
      return Short(v), Commas(v) .. " honor per hour (" .. Commas(farm.honor) .. " this session)"
    end },
  { id = "time", label = "Session", name = "Session time", on = true, value = function(s)
      local t = BarDuration(s.elapsed)
      if not farm.running then return t .. " (paused)", "Session paused at " .. t end
      return t, "Session running for " .. t
    end },
}
local RATE_STAT_BY_ID = {}
for _, st in ipairs(RATE_STATS) do RATE_STAT_BY_ID[st.id] = st end

local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2.0, 0.1
local BG_STEPS = { 0.85, 0.6, 0.35, 0 }

local function BarDB()
  if not ns.db then return { stats = {} } end
  ns.db.rateBar = ns.db.rateBar or {}
  local db = ns.db.rateBar
  db.stats = db.stats or {}
  for _, st in ipairs(RATE_STATS) do
    if db.stats[st.id] == nil then db.stats[st.id] = st.on and true or false end
  end
  db.scale = db.scale or 1
  if db.locked == nil then db.locked = false end
  db.layout = db.layout or "across"
  db.bgAlpha = db.bgAlpha or BG_STEPS[1]
  return db
end

local function CharBarDB()
  if not ns.cdb then return {} end
  ns.cdb.rateBar = ns.cdb.rateBar or {}
  return ns.cdb.rateBar
end

local function Snapshot()
  local xp, xpMax = ReadXP()
  return { elapsed = FarmElapsed(), xp = xp, xpMax = xpMax,
    level = UnitLevel and SafeNum(UnitLevel("player")) or 0, noXP = NoXP() }
end

-- The stats the bar shows now: the ones picked, minus XP stats on a
-- character that can't gain XP. Each entry is { stat, barText, tipText }.
local function VisibleStats()
  local db, s, out = BarDB(), Snapshot(), {}
  for _, st in ipairs(RATE_STATS) do
    if db.stats[st.id] and not (st.xp and s.noXP) then
      local short, long = st.value(s)
      out[#out + 1] = { st, short, long }
    end
  end
  return out, s
end

local bar, barCfg

-- The offsets are saved in screen units (offset x scale), so making the bar
-- bigger or smaller keeps it where it is instead of sliding it across.
local function SaveBarPosition()
  if not bar then return end
  local point, _, rel, x, y = bar:GetPoint()
  local scale = (bar.GetScale and bar:GetScale()) or 1
  local c = CharBarDB()
  c.point, c.rel = point or "CENTER", rel or point or "CENTER"
  c.x, c.y = math.floor((x or 0) * scale + 0.5), math.floor((y or 0) * scale + 0.5)
end

local function PlaceBar()
  local c = CharBarDB()
  local scale = BarDB().scale or 1
  bar:SetScale(scale)
  bar:ClearAllPoints()
  if c.point then
    bar:SetPoint(c.point, UIParent, c.rel or c.point, (c.x or 0) / scale, (c.y or 0) / scale)
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -120 / scale)
  end
end

local function LayoutRateBar()
  if not bar then return end
  local db = BarDB()
  local C = ns.InterfaceColors or {}
  local bg = C.bg or { 0.05, 0.06, 0.08 }
  if bar.epuScale ~= db.scale then
    bar.epuScale = db.scale
    if not bar.dragging then PlaceBar() end
  end
  bar.bg:SetColorTexture(bg[1], bg[2], bg[3], db.bgAlpha)
  for _, e in ipairs(bar.edges) do e:SetShown(db.bgAlpha > 0) end
  bar:EnableMouse(true)
  local stats = VisibleStats()
  if #stats == 0 then
    stats = { { { id = "none" }, "Pick some stats: right-click", "" } }
  end
  -- Across: one row, each stat after the last. Stacked: one stat a line.
  local across = db.layout ~= "stacked"
  local x, y, w, h = 8, -5, 0, 22
  for i, entry in ipairs(stats) do
    local fs = bar.cells[i]
    if not fs then
      fs = ns.InterfaceFont(bar, 12, C.text)
      bar.cells[i] = fs
    end
    local label = entry[1].label
    fs:SetText(label and ("|cffa3b0c2" .. label .. "|r " .. entry[2]) or entry[2])
    fs:ClearAllPoints()
    fs:Show()
    local sw = fs:GetStringWidth() or 40
    if across then
      fs:SetPoint("LEFT", bar, "LEFT", x, 0)
      x = x + sw + 14
      w = x - 6
    else
      fs:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, y)
      y = y - 16
      w, h = math.max(w, sw + 16), -y + 4
    end
  end
  for i = #stats + 1, #bar.cells do bar.cells[i]:Hide() end
  bar:SetSize(math.max(60, w), math.max(22, h))
end

local function RateBarTooltip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("EPU rate bar", 1, 1, 1)
  local stats = VisibleStats()
  for _, entry in ipairs(stats) do
    if entry[3] ~= "" then GameTooltip:AddLine(entry[3], 0.85, 0.85, 0.85, true) end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: session details", 0.5, 0.8, 1)
  GameTooltip:AddLine("Right-click: pick stats, size and lock", 0.5, 0.8, 1)
  if not BarDB().locked then GameTooltip:AddLine("Drag to move", 0.5, 0.8, 1) end
  GameTooltip:Show()
end

local function EnsureRateBar()
  if bar then return bar end
  local C = ns.InterfaceColors or {}
  bar = CreateFrame("Frame", "EPUGuildRateBar", UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  local line = C.line or { 0.2, 0.22, 0.26, 1 }
  bar.edges = {}
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                          { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = bar:CreateTexture(nil, "BORDER")
    e:SetColorTexture(line[1], line[2], line[3], line[4] or 1)
    e:SetPoint(side[1]); e:SetPoint(side[2])
    if side[3] then e:SetHeight(1) else e:SetWidth(1) end
    bar.edges[#bar.edges + 1] = e
  end
  bar.cells = {}
  bar:SetScript("OnMouseDown", function(self) self.dragged = false end)
  bar:SetScript("OnDragStart", function(self)
    if BarDB().locked then return end
    self.dragging = true
    self:StartMoving()
  end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveBarPosition()
    self.dragged = true
    self.dragging = false
  end)
  bar:SetScript("OnMouseUp", function(self, button)
    if self.dragged then self.dragged = false; return end
    if button == "RightButton" then
      ns.OpenRateBarSettings()
    else
      ns.OpenPersonalTrackers("session")
    end
  end)
  bar:SetScript("OnEnter", RateBarTooltip)
  bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- Redraw once a second while shown; the game only runs OnUpdate for a
  -- visible frame, so a hidden bar costs nothing.
  bar.since = 0
  bar:SetScript("OnUpdate", function(self, dt)
    self.since = self.since + (dt or 0)
    if self.since < 1 or self.dragging then return end
    self.since = 0
    LayoutRateBar()
  end)
  PlaceBar()
  return bar
end

function ns.RateBarShown() return bar ~= nil and bar:IsShown() end

function ns.RefreshRateBar()
  if bar and bar:IsShown() then LayoutRateBar() end
  if barCfg and barCfg:IsShown() then barCfg:Refresh() end
end

function ns.ShowRateBar(show)
  CharBarDB().shown = show and true or false
  if show then
    EnsureRateBar()
    bar:Show()
    LayoutRateBar()
  elseif bar then
    bar:Hide()
  end
  if barCfg and barCfg:IsShown() then barCfg:Refresh() end
  if win and win:IsShown() then win:Refresh() end
end

function ns.ToggleRateBar() ns.ShowRateBar(not ns.RateBarShown()) end

function ns.SetRateBarScale(s)
  s = tonumber(s)
  if not s then return false end
  s = math.floor(math.max(SCALE_MIN, math.min(SCALE_MAX, s)) * 10 + 0.5) / 10
  BarDB().scale = s
  ns.RefreshRateBar()
  return true, s
end

function ns.ResetRateBarPosition()
  local c = CharBarDB()
  c.point, c.rel, c.x, c.y = nil, nil, nil, nil
  if bar then PlaceBar() end
end

function ns.OpenRateBarSettings()
  if not barCfg then
    barCfg = ns.InterfaceWindow("EPUGuildRateBarConfig", UIParent, "EPU Rate Bar", 430, 440)
    barCfg:SetFrameStrata("DIALOG")
    local body = CreateFrame("Frame", nil, barCfg)
    body:SetPoint("TOPLEFT", 12, -44)
    body:SetPoint("BOTTOMRIGHT", -12, 12)
    barCfg.pool = ns.NewWidgetPool(body)

    function barCfg:Refresh()
      local pool = self.pool
      pool:ReleaseAll()
      local C = ns.InterfaceColors
      local db = BarDB()
      local y = 0
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local b = pool:Button(it[1], it[2], 22, it[4])
          b:SetPoint("TOPLEFT", x, y)
          b.epuAction = it[5]
          b:SetScript("OnClick", function() it[3](); ns.RefreshRateBar(); barCfg:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = pool:Font(12, C.gold or C.white, "heading")
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 22
      end
      local function Note(t)
        local f = pool:Font(11, C.muted, "note")
        f:SetPoint("TOPLEFT", 0, y)
        f:SetWidth(400)
        f:SetWordWrap(true)
        f:SetText(t)
        y = y - 30
      end

      Row({
        { Check(ns.RateBarShown(), "Show the rate bar"), 160, function() ns.ToggleRateBar() end, nil, "show" },
        { Check(db.locked, "Lock in place"), 120, function() db.locked = not db.locked end, nil, "lock" },
      })
      Heading("Size and look")
      Row({
        { "Smaller", 72, function() ns.SetRateBarScale(db.scale - SCALE_STEP) end, nil, "smaller" },
        { "Size: " .. math.floor(db.scale * 100 + 0.5) .. "%", 90, function() ns.SetRateBarScale(1) end, nil, "size" },
        { "Bigger", 72, function() ns.SetRateBarScale(db.scale + SCALE_STEP) end, nil, "bigger" },
        { db.layout == "stacked" and "Layout: stacked" or "Layout: across", 120, function()
            db.layout = db.layout == "stacked" and "across" or "stacked"
          end, nil, "layout" },
      })
      Row({
        { "Background: " .. math.floor(db.bgAlpha * 100 + 0.5) .. "%", 140, function()
            local nextA = BG_STEPS[1]
            for i, a in ipairs(BG_STEPS) do
              if math.abs(a - db.bgAlpha) < 0.01 then nextA = BG_STEPS[(i % #BG_STEPS) + 1] end
            end
            db.bgAlpha = nextA
          end, nil, "background" },
        { "Put it back at the top", 160, function() ns.ResetRateBarPosition() end, nil, "resetpos" },
      })

      Heading("Stats to show")
      local pair = {}
      for _, st in ipairs(RATE_STATS) do
        pair[#pair + 1] = { Check(db.stats[st.id], st.name), 196, function() db.stats[st.id] = not db.stats[st.id] end, nil, "stat:" .. st.id }
        if #pair == 2 then Row(pair); pair = {} end
      end
      if #pair > 0 then Row(pair) end
      Note("XP stats hide themselves on a max-level character. Size, stats and lock are the same on all your characters; whether the bar shows and where it sits is saved for each one.")

      Heading("Session")
      Row({
        { farm.running and "Pause" or "Resume", 80, function() ToggleFarmPause() end, nil, "pause" },
        { "Reset session", 110, function() ResetFarmSession() end, nil, "reset" },
        { "Session details", 120, function() ns.OpenPersonalTrackers("session") end, nil, "details" },
      })
      -- Grow the window to fit the stat list.
      self:SetHeight(math.max(440, -y + 56))
    end
  end
  barCfg:Refresh()
  barCfg:Show()
end

-- /epu bar [show | hide | lock | unlock | scale <n> | reset | resetpos | settings]
function ns.RateBarCommand(args)
  local sub, rest = (args or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if sub == "" then
    ns.ToggleRateBar()
  elseif sub == "show" or sub == "on" then
    ns.ShowRateBar(true)
  elseif sub == "hide" or sub == "off" then
    ns.ShowRateBar(false)
  elseif sub == "lock" or sub == "unlock" then
    BarDB().locked = sub == "lock"
    ns.Print("Rate bar " .. (sub == "lock" and "locked." or "unlocked: drag it to move it."))
    ns.RefreshRateBar()
  elseif sub == "scale" or sub == "size" then
    local ok, s = ns.SetRateBarScale(rest)
    if not ok then return ns.Print("Usage: /epu bar scale 1.2  (between 0.6 and 2)") end
    ns.Print("Rate bar size: " .. math.floor(s * 100 + 0.5) .. "%")
  elseif sub == "reset" then
    ResetFarmSession()
    ns.Print("Session reset: the rate bar starts counting again.")
    ns.RefreshRateBar()
  elseif sub == "resetpos" then
    ns.ResetRateBarPosition()
  elseif sub == "pause" or sub == "resume" then
    if (sub == "pause") == farm.running then ToggleFarmPause() end
    ns.RefreshRateBar()
  else
    ns.OpenRateBarSettings()
  end
end

ns.RateBar = { STATS = RATE_STATS, Visible = VisibleStats, Layout = function() LayoutRateBar() end }

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    if CharBarDB().shown then ns.ShowRateBar(true) end
  end)
end

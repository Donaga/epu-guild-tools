-- EPU Guild Tools: Personal Trackers (Lockouts, Profession Cooldowns, Farming Session, Consumables, Rep & PvP).
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
  local _, cf = UnitClass and UnitClass("player")
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
  local _, cf = UnitClass and UnitClass("player")
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

---------------------------------------------------------------------------
-- 3. Farming / Grinding Session Tracker
---------------------------------------------------------------------------
local farm = {
  running = true,
  startedAt = time(),
  pausedElapsed = 0,
  xp = 0,
  lastXP = nil,
  cash = 0,
  lootValue = 0,
  kills = 0,
  drops = {},
}

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
  farm.lastXP = UnitXP and SafeNum(UnitXP("player")) or 0
  farm.cash = 0
  farm.lootValue = 0
  farm.kills = 0
  farm.drops = {}
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
  local K = ns.UIKit
  if not win then
    local C = ns.InterfaceColors
    win = ns.InterfaceWindow("EPUGuildPersonalTrackers", UIParent, "EPU Personal Trackers", 540, 500)
    win:SetFrameStrata("DIALOG")
    win.widgets = {}

    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(510); child:SetHeight(420)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    win.scroll, win.child = scroll, child

    function win:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local db = DB()
      local C = ns.InterfaceColors
      local y = -4
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local btn = Track(K.Btn(child, it[1], it[2], 22, it[4]))
          btn:SetPoint("TOPLEFT", x, y)
          btn:SetScript("OnClick", function() it[3](); win:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = Track(K.Font(child, 12, C.gold or C.white))
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 22
      end
      local function Line(txt, col)
        local f = Track(K.Font(child, 11, col or C.text))
        f:SetPoint("TOPLEFT", 4, y)
        f:SetWidth(500)
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
        })
        Line(string.format("Elapsed: |cffffffff%s|r    Kills: |cffffffff%d|r", FormatDuration(elapsed), farm.kills))
        Line(string.format("XP Gained: |cff4fc3f7%d|r (%d/hr)", farm.xp, xph))
        Line(string.format("Cash Looted: |cffffd100%s|r    Item Vendor Value: |cffffd100%s|r", FormatMoney(farm.cash), FormatMoney(farm.lootValue)))
        Line(string.format("Total Value: |cff4ade80%s|r (%s/hr)", FormatMoney(totalGold), FormatMoney(gph)))
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
        local box = Track(K.Box(child, 200, "Item ID or Preset below..."))
        box:SetPoint("TOPLEFT", 0, y)
        local addBtn = Track(K.Btn(child, "+ Add (x10)", 96, 22, "accent"))
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
            local kills = math.ceil(rem / st.lastGain)
            eta = string.format("  ·  |cff4fc3f7%d to next rank (~%d gains)|r", rem, kills)
          end
          Line(string.format("%s: |cff4ade80+%d|r (%d/hr)%s", fac, st.gained, rph, eta))
        end
        if not anyRep then Line("Earn reputation with any faction this session to see Rep/hr & ETA.", C.muted) end
      end

      child:SetHeight(math.max(420, -y + 20))
    end
  end
  win:Refresh()
  win:Show()
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    farm.lastXP = UnitXP and SafeNum(UnitXP("player")) or 0
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
  ns.On("SPELL_UPDATE_COOLDOWN", ScanCooldowns)
  ns.On("BAG_UPDATE_COOLDOWN", ScanCooldowns)
  ns.On("PLAYER_XP_UPDATE", function()
    if not farm.running then return end
    local cur = UnitXP and SafeNum(UnitXP("player")) or 0
    if farm.lastXP and cur > farm.lastXP then farm.xp = farm.xp + (cur - farm.lastXP) end
    farm.lastXP = cur
  end)
  ns.On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function()
    if farm.running then farm.kills = farm.kills + 1 end
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
      if link then
        local _, _, q, _, _, _, _, _, _, _, sell = GetItemInfo and GetItemInfo(link)
        sell = SafeNum(sell) or 0
        local qty = tonumber(msg:match("x(%d+)")) or 1
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
    end
  end)
  ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
    if not SafeStr(msg) then return end
    local amt = tonumber(msg:match("(%d+) honor"))
    if amt then pvpSession.honor = pvpSession.honor + amt end
    if GetPVPSessionStats then
      local hk = SafeNum(GetPVPSessionStats()) or 0
      if pvpSession.startHKs then pvpSession.hks = math.max(0, hk - pvpSession.startHKs) end
    end
  end)
end

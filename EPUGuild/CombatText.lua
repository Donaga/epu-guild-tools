-- EPU Guild Tools: Personal Scrolling Combat Text (strictly player/pet only).
local _, ns = ...

local pool, active = {}, {}
local animFrame = CreateFrame("Frame")
local playerGUID

local SCHOOL_COLORS = {
  [1]  = { 1.00, 1.00, 0.90 }, -- Physical
  [2]  = { 1.00, 0.90, 0.45 }, -- Holy
  [4]  = { 1.00, 0.45, 0.20 }, -- Fire
  [8]  = { 0.35, 0.90, 0.35 }, -- Nature
  [16] = { 0.40, 0.80, 1.00 }, -- Frost
  [32] = { 0.72, 0.45, 1.00 }, -- Shadow
  [64] = { 0.45, 0.95, 0.95 }, -- Arcane
}

local function DB()
  if not ns.db then return {} end
  ns.db.sct = ns.db.sct or {}
  local s = ns.db.sct
  if s.enabled == nil then s.enabled = false end
  if s.outDamage == nil then s.outDamage = true end
  if s.outHeal == nil then s.outHeal = true end
  if s.inDamage == nil then s.inDamage = false end
  if s.inHeal == nil then s.inHeal = true end
  if s.pet == nil then s.pet = true end
  if s.nameplate == nil then s.nameplate = true end
  if s.size == nil then s.size = 18 end
  return s
end

local function Acquire()
  local fs = table.remove(pool)
  if not fs then
    fs = animFrame:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
  end
  return fs
end

local function Release(item)
  item.fs:Hide()
  item.fs:ClearAllPoints()
  pool[#pool + 1] = item.fs
end

local function AnchorForGUID(destGUID, usePlate)
  if usePlate and destGUID and C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if u and UnitGUID and UnitGUID(u) == destGUID then
          return plate, 0, 18
        end
      end
    end
  end
  return UIParent, 0, 60
end

local function Spawn(text, color, isCrit, destGUID, driftX)
  local s = DB()
  local fs = Acquire()
  local fontPath = (ns.UIKit and ns.UIKit.FONT) or STANDARD_TEXT_FONT
  local sz = (s.size or 18) + (isCrit and 6 or 0)
  if fs:SetFont(fontPath, sz, "OUTLINE") == false then
    fs:SetFont(STANDARD_TEXT_FONT, sz, "OUTLINE")
  end
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetText(text)

  local anchor, baseX, baseY = AnchorForGUID(destGUID, s.nameplate)
  local jitterX = (driftX or math.random(-36, 36))
  local jitterY = math.random(-8, 14)
  fs:SetPoint("CENTER", anchor, "CENTER", baseX + jitterX, baseY + jitterY)
  fs:SetAlpha(1)
  fs:Show()

  active[#active + 1] = {
    fs = fs,
    anchor = anchor,
    startX = baseX + jitterX,
    startY = baseY + jitterY,
    vx = jitterX * 0.25,
    vy = isCrit and 68 or 52,
    elapsed = 0,
    duration = isCrit and 1.25 or 1.0,
  }
end

animFrame:SetScript("OnUpdate", function(_, dt)
  if #active == 0 then return end
  for i = #active, 1, -1 do
    local it = active[i]
    it.elapsed = it.elapsed + dt
    local p = it.elapsed / it.duration
    if p >= 1 then
      Release(it)
      table.remove(active, i)
    else
      local y = it.startY + it.vy * it.elapsed
      local x = it.startX + it.vx * it.elapsed
      it.fs:ClearAllPoints()
      it.fs:SetPoint("CENTER", it.anchor, "CENTER", x, y)
      it.fs:SetAlpha(p > 0.65 and (1 - (p - 0.65) / 0.35) or 1)
    end
  end
end)

local function OnCombatLog()
  local s = DB()
  if not s.enabled or not CombatLogGetCurrentEventInfo then return end
  playerGUID = playerGUID or (UnitGUID and UnitGUID("player"))
  if not playerGUID then return end
  local petGUID = s.pet and UnitGUID and UnitGUID("pet") or nil

  local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, p12, p13, p14, p15, _, _, p18, _, _, p21 = CombatLogGetCurrentEventInfo()
  local isMine = (srcGUID == playerGUID) or (petGUID and srcGUID == petGUID)
  local isToMe = (dstGUID == playerGUID)
  if not isMine and not isToMe then return end

  if sub == "SWING_DAMAGE" then
    local amount, crit = p12, p18
    if isMine and s.outDamage and type(amount) == "number" and amount > 0 then
      Spawn(crit and (amount .. "!") or tostring(amount), crit and { 1, 0.85, 0.2 } or SCHOOL_COLORS[1], crit, dstGUID)
    elseif isToMe and s.inDamage and type(amount) == "number" and amount > 0 then
      Spawn("-" .. amount, { 1.0, 0.28, 0.28 }, crit, nil, math.random(-40, 40))
    end
  elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then
    local school, amount, crit = p14, p15, p21
    local col = SCHOOL_COLORS[school] or SCHOOL_COLORS[1]
    if isMine and s.outDamage and type(amount) == "number" and amount > 0 then
      Spawn(crit and (amount .. "!") or tostring(amount), col, crit, dstGUID)
    elseif isToMe and s.inDamage and type(amount) == "number" and amount > 0 then
      Spawn("-" .. amount, { 1.0, 0.28, 0.28 }, crit, nil, math.random(-40, 40))
    end
  elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
    local amount, crit = p15, p18
    if (isMine and s.outHeal) or (isToMe and s.inHeal) then
      if type(amount) == "number" and amount > 0 then
        Spawn("+" .. amount .. (crit and "!" or ""), { 0.28, 0.95, 0.45 }, crit, isMine and dstGUID or nil)
      end
    end
  end
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    playerGUID = UnitGUID and UnitGUID("player") or nil
  end)
  ns.On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
end

local sctWin
function ns.OpenSCTSettings()
  if not sctWin then
    sctWin = ns.InterfaceWindow("EPUGuildSCTWindow", UIParent, "EPU Scrolling Combat Text (Yours Only)", 420, 320)
    sctWin:SetMovable(true)
    sctWin:RegisterForDrag("LeftButton")
    sctWin:SetScript("OnDragStart", sctWin.StartMoving)
    sctWin:SetScript("OnDragStop", sctWin.StopMovingOrSizing)
    sctWin.widgets = {}

    function sctWin:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local s = DB()
      local y = -44
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function Row(btns)
        local x = 16
        for _, spec in ipairs(btns) do
          local b = Track(ns.InterfaceButton(self, spec[1], spec[2] or 184, 24))
          b:SetPoint("TOPLEFT", x, y)
          b:SetScript("OnClick", spec[3])
          x = x + (spec[2] or 184) + 8
        end
        y = y - 30
      end

      Row({
        { Check(s.enabled, "Enable Personal SCT"), 220, function() s.enabled = not s.enabled; self:Refresh() end },
        { "Test Numbers", 140, function()
          Spawn("482", SCHOOL_COLORS[4], false, nil, -24)
          Spawn("1,240!", { 1, 0.85, 0.2 }, true, nil, 18)
          Spawn("+365", { 0.28, 0.95, 0.45 }, false, nil, 0)
        end },
      })
      Row({
        { Check(s.outDamage, "Outgoing Damage"), 184, function() s.outDamage = not s.outDamage; self:Refresh() end },
        { Check(s.outHeal, "Outgoing Healing"), 184, function() s.outHeal = not s.outHeal; self:Refresh() end },
      })
      Row({
        { Check(s.inHeal, "Incoming Healing"), 184, function() s.inHeal = not s.inHeal; self:Refresh() end },
        { Check(s.inDamage, "Incoming Damage"), 184, function() s.inDamage = not s.inDamage; self:Refresh() end },
      })
      Row({
        { Check(s.pet, "Include My Pet"), 184, function() s.pet = not s.pet; self:Refresh() end },
        { Check(s.nameplate, "On Target Nameplate"), 184, function() s.nameplate = not s.nameplate; self:Refresh() end },
      })
      Row({
        { "Size -", 86, function() s.size = math.max(12, (s.size or 18) - 2); self:Refresh() end },
        { "Size: " .. (s.size or 18), 100, function() s.size = 18; self:Refresh() end },
        { "Size +", 86, function() s.size = math.min(30, (s.size or 18) + 2); self:Refresh() end },
      })
    end
  end
  sctWin:Refresh()
  sctWin:Show()
end

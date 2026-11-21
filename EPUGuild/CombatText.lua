-- EPU Guild Tools: Personal Scrolling Combat Text (strictly player/pet only).
-- Supports Nameplates (Modern / Classic / Impact styles with per-style offsets),
-- custom movable/resizable Screen Areas, rapid-hit combining, thresholds,
-- number formatting, spell icons, crit sounds, and Blizzard FCT toggle.
local _, ns = ...

local pool, active = {}, {}
local areaFrames = {}
local mergeBuf = {}
local animFrame = CreateFrame("Frame")
local playerGUID

local DEFAULT_SCHOOL_COLORS = {
  [1]  = { 1.00, 1.00, 0.90 }, -- Physical
  [2]  = { 1.00, 0.90, 0.45 }, -- Holy
  [4]  = { 1.00, 0.45, 0.20 }, -- Fire
  [8]  = { 0.35, 0.90, 0.35 }, -- Nature
  [16] = { 0.40, 0.80, 1.00 }, -- Frost
  [32] = { 0.72, 0.45, 1.00 }, -- Shadow
  [64] = { 0.45, 0.95, 0.95 }, -- Arcane
  heal = { 0.28, 0.95, 0.45 },
  miss = { 0.78, 0.82, 0.88 },
  inc  = { 1.00, 0.28, 0.28 },
}

local SOUND_CHOICES = {
  { label = "Off", id = false },
  { label = "Level Up", id = 888 },
  { label = "Ready Check", id = 8960 },
  { label = "PvP Flag", id = 8174 },
  { label = "Map Ping", id = 3175 },
  { label = "Tell", id = 3081 },
}

local function DB()
  if not ns.db then return {} end
  ns.db.sct = ns.db.sct or {}
  local s = ns.db.sct
  if s.enabled == nil then s.enabled = false end
  if s.outDamage == nil then s.outDamage = true end
  if s.outHeal == nil then s.outHeal = true end
  if s.inDamage == nil then s.inDamage = true end
  if s.inHeal == nil then s.inHeal = true end
  if s.pet == nil then s.pet = true end
  if s.misses == nil then s.misses = true end
  if s.critsOnly == nil then s.critsOnly = false end
  if s.minThreshold == nil then s.minThreshold = 0 end
  if s.hideBlizz == nil then s.hideBlizz = false end

  -- Routing: "nameplate" or area id
  if s.routeOutDmg == nil then s.routeOutDmg = "nameplate" end
  if s.routeOutHeal == nil then s.routeOutHeal = "nameplate" end
  if s.routeIn == nil then s.routeIn = "incoming" end

  -- Nameplate styles: "modern", "classic", "impact"
  if s.style == nil then s.style = "modern" end
  s.styleOffsets = s.styleOffsets or {
    modern  = { x = 0, y = 20 },
    classic = { x = 0, y = 14 },
    impact  = { x = 18, y = 22 },
  }
  s.modernMotions = s.modernMotions or { normal = "up", crit = "arc", miss = "up" }
  if s.npDistance == nil then s.npDistance = 64 end
  if s.npSpeed == nil then s.npSpeed = 1.0 end
  if s.npDuration == nil then s.npDuration = 1.1 end

  -- Rapid-hit combining
  if s.mergeWindow == nil then s.mergeWindow = 0.6 end
  if s.mergeSeparateSpells == nil then s.mergeSeparateSpells = true end
  if s.mergeShowCount == nil then s.mergeShowCount = true end
  if s.mergePop == nil then s.mergePop = true end

  -- Formatting & appearance
  if s.font == nil then s.font = "epu" end
  if s.size == nil then s.size = 18 end
  if s.inFont == nil then s.inFont = "epu" end
  if s.inSize == nil then s.inSize = 16 end
  if s.numFormat == nil then s.numFormat = "thousands" end -- "full", "thousands", "compact"
  if s.iconPos == nil then s.iconPos = "left" end         -- "off", "left", "right", "above", "below"
  s.schoolColors = s.schoolColors or {}

  -- Crit sounds
  if s.critSound == nil then s.critSound = false end
  if s.critSoundChan == nil then s.critSoundChan = "Master" end
  if s.hugeCritThreshold == nil then s.hugeCritThreshold = 1000 end
  if s.hugeCritSound == nil then s.hugeCritSound = false end
  if s.hugeCritSoundChan == nil then s.hugeCritSoundChan = "Master" end

  -- Screen areas
  if not s.areas or #s.areas == 0 then
    s.areas = {
      { id = "outgoing", name = "Outgoing", x = 220, y = 40, w = 220, h = 180, anim = "up", align = "CENTER", spacing = 22, duration = 1.2 },
      { id = "incoming", name = "Incoming", x = -220, y = 40, w = 220, h = 180, anim = "down", align = "CENTER", spacing = 22, duration = 1.2 },
    }
  end
  return s
end

local function ParseThreshold(str)
  if type(str) == "number" then return math.max(0, str) end
  local s = tostring(str or ""):lower():gsub(",", ""):match("^%s*(.-)%s*$")
  local num, suf = s:match("^([%d%.]+)([km]?)$")
  num = tonumber(num)
  if not num then return 0 end
  if suf == "k" then num = num * 1000
  elseif suf == "m" then num = num * 1000000 end
  return math.max(0, math.floor(num))
end

local function FormatNumber(n, fmt)
  n = math.floor(n or 0)
  if fmt == "compact" then
    if n >= 1000000 then return string.format("%.1fm", n / 1000000):gsub("%.0m$", "m") end
    if n >= 1000 then return string.format("%.1fk", n / 1000):gsub("%.0k$", "k") end
    return tostring(n)
  elseif fmt == "thousands" then
    local s = tostring(n)
    local left, num, right = s:match("^([^%d]*%d)(%d*)(.-)$")
    return left .. num:reverse():gsub("(%d%d%d)", "%1,"):reverse() .. right
  end
  return tostring(n)
end

local function FontPathFor(key)
  for _, f in ipairs(ns.CHAT_FONTS or {}) do
    if f.value == key and f.path then return f.path end
  end
  return (ns.UIKit and ns.UIKit.FONT) or STANDARD_TEXT_FONT
end

local function SchoolColor(key)
  local s = DB()
  local c = (s.schoolColors and s.schoolColors[key]) or DEFAULT_SCHOOL_COLORS[key] or DEFAULT_SCHOOL_COLORS[1]
  return c[1], c[2], c[3]
end

local function ApplyBlizzardFCT(hide)
  if not SetCVar then return end
  local v = hide and "0" or "1"
  pcall(SetCVar, "floatingCombatTextCombatDamage", v)
  pcall(SetCVar, "floatingCombatTextCombatHealing", v)
end

local function Acquire()
  local obj = table.remove(pool)
  if not obj then
    local f = CreateFrame("Frame", nil, animFrame)
    f:SetSize(220, 32)
    f.fs = f:CreateFontString(nil, "OVERLAY")
    f.icon = f:CreateTexture(nil, "OVERLAY")
    obj = f
  end
  return obj
end

local function Release(item)
  item.frame:Hide()
  item.frame:ClearAllPoints()
  item.frame.icon:Hide()
  pool[#pool + 1] = item.frame
end

local function AnchorForGUID(destGUID)
  if destGUID and C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if u and UnitGUID and UnitGUID(u) == destGUID then
          return plate
        end
      end
    end
  end
  return nil
end

local function FindArea(id)
  local s = DB()
  for _, a in ipairs(s.areas) do if a.id == id then return a end end
  return s.areas[1]
end

local function LayoutIconAndText(frame, text, fontPath, size, r, g, b, iconTex, iconPos, align)
  local fs, ic = frame.fs, frame.icon
  if fs:SetFont(fontPath, size, "OUTLINE") == false then
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
  end
  fs:SetTextColor(r, g, b, 1)
  fs:SetText(text)
  fs:SetJustifyH(align or "CENTER")
  fs:ClearAllPoints()
  ic:ClearAllPoints()

  if iconTex and iconPos and iconPos ~= "off" then
    local isz = math.max(12, math.floor(size * 0.95))
    ic:SetSize(isz, isz)
    ic:SetTexture(iconTex)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:Show()
    if iconPos == "left" then
      fs:SetPoint("CENTER", frame, "CENTER", isz * 0.5 + 2, 0)
      ic:SetPoint("RIGHT", fs, "LEFT", -4, 0)
    elseif iconPos == "right" then
      fs:SetPoint("CENTER", frame, "CENTER", -(isz * 0.5 + 2), 0)
      ic:SetPoint("LEFT", fs, "RIGHT", 4, 0)
    elseif iconPos == "above" then
      fs:SetPoint("CENTER", frame, "CENTER", 0, -isz * 0.35)
      ic:SetPoint("BOTTOM", fs, "TOP", 0, 2)
    else
      fs:SetPoint("CENTER", frame, "CENTER", 0, isz * 0.35)
      ic:SetPoint("TOP", fs, "BOTTOM", 0, -2)
    end
  else
    ic:Hide()
    fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
  end
end

local function SpawnDisplay(opts)
  local s = DB()
  local f = Acquire()
  local isIncoming = opts.incoming
  local fontPath = FontPathFor(isIncoming and s.inFont or s.font)
  local baseSize = isIncoming and (s.inSize or 16) or (s.size or 18)
  local sz = baseSize + (opts.isCrit and 6 or 0) + (opts.isPop and 3 or 0)
  local r, g, b = SchoolColor(opts.colorKey or 1)
  local iconTex = opts.spellID and GetSpellTexture and select(1, pcall(GetSpellTexture, opts.spellID)) and GetSpellTexture(opts.spellID) or nil

  local anchor = UIParent
  local startX, startY, vx, vy, dur, style, motion, align = 0, 60, 0, 56, 1.1, s.style, "up", "CENTER"

  local area
  if not isIncoming and opts.route == "nameplate" then
    local plate = AnchorForGUID(opts.destGUID)
    anchor = plate or UIParent
    local off = (s.styleOffsets and s.styleOffsets[style]) or { x = 0, y = 20 }
    local spread = (style == "classic") and 12 or 26
    startX = off.x + math.random(-spread, spread)
    startY = (plate and 0 or 60) + off.y + math.random(-6, 8)
    dur = (s.npDuration or 1.1) / math.max(0.4, s.npSpeed or 1.0)
    local dist = s.npDistance or 64
    vy = dist / dur
    if style == "modern" then
      motion = (s.modernMotions and s.modernMotions[opts.kind or "normal"]) or "up"
      if motion == "arc" then vx = (math.random(0, 1) == 0 and -1 or 1) * 34 end
    elseif style == "impact" then
      vx = (startX >= off.x and 1 or -1) * 16
    end
  else
    area = FindArea(opts.route)
    anchor = UIParent
    align = area.align or "CENTER"
    startX = (area.x or 0) + math.random(-14, 14)
    startY = (area.y or 0)
    dur = area.duration or 1.2
    motion = area.anim or "up"
    if motion == "down" then
      startY = startY + (area.h or 180) * 0.35
      vy = -((area.h or 180) * 0.7) / dur
    elseif motion == "static" then
      vy = 0
    elseif motion == "arc" then
      vx = (math.random(0, 1) == 0 and -1 or 1) * 36
      vy = ((area.h or 180) * 0.65) / dur
    else
      startY = startY - (area.h or 180) * 0.35
      vy = ((area.h or 180) * 0.7) / dur
    end
  end

  LayoutIconAndText(f, opts.text, fontPath, sz, r, g, b, iconTex, s.iconPos, align)
  f:SetPoint("CENTER", anchor, "CENTER", startX, startY)
  f:SetAlpha(1)
  f:Show()

  active[#active + 1] = {
    frame = f,
    anchor = anchor,
    startX = startX,
    startY = startY,
    vx = vx,
    vy = vy,
    style = style,
    motion = motion,
    isCrit = opts.isCrit,
    isPop = opts.isPop,
    elapsed = 0,
    duration = dur,
  }
  return active[#active]
end

local function FlushMerged(key)
  local m = mergeBuf[key]
  if not m then return end
  mergeBuf[key] = nil
  local s = DB()
  if m.isCrit then
    if s.hugeCritSound and m.amount >= (s.hugeCritThreshold or 1000) and PlaySound then
      pcall(PlaySound, s.hugeCritSound, s.hugeCritSoundChan or "Master")
    elseif s.critSound and PlaySound then
      pcall(PlaySound, s.critSound, s.critSoundChan or "Master")
    end
  end
  local numStr = FormatNumber(m.amount, s.numFormat)
  if m.prefix then numStr = m.prefix .. numStr end
  if m.isCrit then numStr = numStr .. "!" end
  if m.count > 1 and s.mergeShowCount then
    numStr = numStr .. " (x" .. m.count .. ")"
  end
  SpawnDisplay({
    text = numStr,
    colorKey = m.colorKey,
    isCrit = m.isCrit,
    isPop = (m.count > 1 and s.mergePop) or false,
    spellID = m.spellID,
    destGUID = m.destGUID,
    route = m.route,
    incoming = m.incoming,
    kind = m.isCrit and "crit" or "normal",
  })
end

local function QueueHit(opts)
  local s = DB()
  if not opts.incoming and not opts.isHeal and not opts.isMiss then
    if s.critsOnly and not opts.isCrit then return end
    if (opts.amount or 0) < (s.minThreshold or 0) then return end
  end

  local win = s.mergeWindow or 0
  if win <= 0 or opts.isMiss then
    local numStr = opts.isMiss and opts.text or FormatNumber(opts.amount, s.numFormat)
    if not opts.isMiss then
      if opts.prefix then numStr = opts.prefix .. numStr end
      if opts.isCrit then numStr = numStr .. "!" end
    end
    if opts.isCrit then
      if s.hugeCritSound and (opts.amount or 0) >= (s.hugeCritThreshold or 1000) and PlaySound then
        pcall(PlaySound, s.hugeCritSound, s.hugeCritSoundChan or "Master")
      elseif s.critSound and PlaySound then
        pcall(PlaySound, s.critSound, s.critSoundChan or "Master")
      end
    end
    SpawnDisplay({
      text = numStr,
      colorKey = opts.colorKey,
      isCrit = opts.isCrit,
      spellID = opts.spellID,
      destGUID = opts.destGUID,
      route = opts.route,
      incoming = opts.incoming,
      kind = opts.isMiss and "miss" or (opts.isCrit and "crit" or "normal"),
    })
    return
  end

  local bucket = opts.isHeal and "H" or (opts.isCrit and "C" or "N")
  local spKey = s.mergeSeparateSpells and tostring(opts.spellID or 0) or "all"
  local mKey = string.format("%s:%s:%s:%s", opts.incoming and "I" or "O", tostring(opts.destGUID or "me"), bucket, spKey)
  local cur = mergeBuf[mKey]
  if cur then
    cur.amount = cur.amount + (opts.amount or 0)
    cur.count = cur.count + 1
  else
    mergeBuf[mKey] = {
      amount = opts.amount or 0,
      count = 1,
      prefix = opts.prefix,
      colorKey = opts.colorKey,
      isCrit = opts.isCrit,
      spellID = opts.spellID,
      destGUID = opts.destGUID,
      route = opts.route,
      incoming = opts.incoming,
      expires = GetTime() + win,
    }
  end
end

animFrame:SetScript("OnUpdate", function(_, dt)
  local now = GetTime()
  for k, m in pairs(mergeBuf) do
    if now >= m.expires then FlushMerged(k) end
  end

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
      if it.style == "impact" and it.elapsed < 0.14 then
        local sc = 1.35 - (it.elapsed / 0.14) * 0.35
        it.frame:SetScale(sc)
      elseif (it.isCrit or it.isPop) and it.elapsed < 0.18 then
        local sc = 1.25 - (it.elapsed / 0.18) * 0.25
        it.frame:SetScale(sc)
      else
        it.frame:SetScale(1)
      end
      it.frame:ClearAllPoints()
      it.frame:SetPoint("CENTER", it.anchor, "CENTER", x, y)
      it.frame:SetAlpha(p > 0.65 and (1 - (p - 0.65) / 0.35) or 1)
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
      QueueHit({ amount = amount, isCrit = crit, colorKey = 1, destGUID = dstGUID, route = s.routeOutDmg })
    elseif isToMe and s.inDamage and type(amount) == "number" and amount > 0 then
      QueueHit({ amount = amount, isCrit = crit, prefix = "-", colorKey = "inc", incoming = true, route = s.routeIn })
    end
  elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "DAMAGE_SHIELD" then
    local spellID, school, amount, crit = p12, p14, p15, p21
    if isMine and s.outDamage and type(amount) == "number" and amount > 0 then
      QueueHit({ amount = amount, isCrit = crit, spellID = spellID, colorKey = school or 1, destGUID = dstGUID, route = s.routeOutDmg })
    elseif isToMe and s.inDamage and type(amount) == "number" and amount > 0 then
      QueueHit({ amount = amount, isCrit = crit, spellID = spellID, prefix = "-", colorKey = "inc", incoming = true, route = s.routeIn })
    end
  elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
    local spellID, amount, crit = p12, p15, p18
    if type(amount) == "number" and amount > 0 then
      if isMine and s.outHeal then
        QueueHit({ amount = amount, isCrit = crit, isHeal = true, spellID = spellID, prefix = "+", colorKey = "heal", destGUID = dstGUID, route = s.routeOutHeal })
      elseif isToMe and s.inHeal then
        QueueHit({ amount = amount, isCrit = crit, isHeal = true, spellID = spellID, prefix = "+", colorKey = "heal", incoming = true, route = s.routeIn })
      end
    end
  elseif (sub == "SWING_MISSED" or sub == "SPELL_MISSED" or sub == "RANGE_MISSED") and s.misses then
    local missType = (sub == "SWING_MISSED") and p12 or p15
    local spellID = (sub ~= "SWING_MISSED") and p12 or nil
    if isMine and s.outDamage and type(missType) == "string" then
      QueueHit({ isMiss = true, text = missType, spellID = spellID, colorKey = "miss", destGUID = dstGUID, route = s.routeOutDmg })
    elseif isToMe and s.inDamage and type(missType) == "string" then
      QueueHit({ isMiss = true, text = missType, spellID = spellID, colorKey = "miss", incoming = true, route = s.routeIn })
    end
  end
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    playerGUID = UnitGUID and UnitGUID("player") or nil
    if DB().hideBlizz then ApplyBlizzardFCT(true) end
  end)
  ns.On("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)
end

-- Show/Hide movable/resizable scroll area overlays with sample numbers
local showingAreas = false
local sampleTicker
function ns.ToggleSCTScrollAreas(force)
  if force == nil then showingAreas = not showingAreas else showingAreas = force and true or false end
  local s = DB()
  local C = ns.InterfaceColors
  for _, af in pairs(areaFrames) do af:Hide() end
  if sampleTicker and sampleTicker.Cancel then sampleTicker:Cancel(); sampleTicker = nil end
  if not showingAreas then return end

  for _, a in ipairs(s.areas) do
    local f = areaFrames[a.id]
    if not f then
      f = CreateFrame("Frame", nil, UIParent)
      f:SetFrameStrata("DIALOG")
      f:SetMovable(true)
      f:SetResizable(true)
      f:EnableMouse(true)
      f:RegisterForDrag("LeftButton")
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 0.55)
      bg:SetAllPoints()
      f.lbl = ns.InterfaceFont(f, 12, C.gold)
      f.lbl:SetPoint("CENTER")
      local grip = CreateFrame("Button", nil, f)
      grip:SetSize(14, 14)
      grip:SetPoint("BOTTOMRIGHT", -2, 2)
      grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
      grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
      grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.areaRef.w, f.areaRef.h = math.floor(f:GetWidth()), math.floor(f:GetHeight())
      end)
      f:SetScript("OnDragStart", f.StartMoving)
      f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        self.areaRef.x, self.areaRef.y = math.floor(x or 0), math.floor(y or 0)
      end)
      areaFrames[a.id] = f
    end
    f.areaRef = a
    f:SetSize(a.w or 220, a.h or 180)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", a.x or 0, a.y or 0)
    f.lbl:SetText(a.name .. " Area\n(Drag to move)")
    f:Show()
  end

  if C_Timer and C_Timer.NewTicker then
    sampleTicker = C_Timer.NewTicker(1.0, function()
      if not showingAreas then return end
      for _, a in ipairs(DB().areas) do
        SpawnDisplay({ text = FormatNumber(math.random(350, 2400), DB().numFormat) .. "!", colorKey = 4, isCrit = true, route = a.id })
      end
    end)
  end
end

local sctWin
local sctTab = "general"
function ns.OpenSCTSettings()
  if not sctWin then
    sctWin = ns.InterfaceWindow("EPUGuildSCTWindow", UIParent, "EPU Scrolling Combat Text (Yours Only)", 580, 500)
    sctWin:SetMovable(true)
    sctWin:RegisterForDrag("LeftButton")
    sctWin:SetScript("OnDragStart", sctWin.StartMoving)
    sctWin:SetScript("OnDragStop", sctWin.StopMovingOrSizing)
    sctWin:HookScript("OnHide", function() ns.ToggleSCTScrollAreas(false) end)

    local scroll = CreateFrame("ScrollFrame", nil, sctWin)
    scroll:SetPoint("TOPLEFT", 12, -74)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(548); child:SetHeight(200)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    sctWin.scroll = scroll
    sctWin.child = child
    sctWin.widgets = {}

    local tabDefs = {
      { "general", "Styles & Routing", 126 },
      { "areas", "Screen Areas", 112 },
      { "filters", "Clutter & Merge", 120 },
      { "look", "Fonts & Sounds", 124 },
    }
    sctWin.tabs = {}
    local tx = 14
    for _, td in ipairs(tabDefs) do
      local tb = ns.InterfaceButton(sctWin, td[2], td[3], 24)
      tb:SetPoint("TOPLEFT", tx, -42)
      tb:SetScript("OnClick", function() sctTab = td[1]; sctWin.scroll:SetVerticalScroll(0); sctWin:Refresh() end)
      tx = tx + td[3] + 6
    end

    function sctWin:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local s = DB()
      local C = ns.InterfaceColors
      local y = -4
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function Heading(text)
        y = y - 6
        local h = Track(ns.InterfaceFont(self.child, 12, C.gold))
        h:SetPoint("TOPLEFT", 4, y); h:SetText(text)
        y = y - 20
      end
      local function Row(btns)
        local x = 4
        for _, spec in ipairs(btns) do
          local b = Track(ns.InterfaceButton(self.child, spec[1], spec[2] or 170, 22))
          b:SetPoint("TOPLEFT", x, y)
          b:SetScript("OnClick", spec[3])
          x = x + (spec[2] or 170) + 6
        end
        y = y - 26
      end

      if sctTab == "general" then
        Row({
          { Check(s.enabled, "Enable Personal SCT"), 190, function() s.enabled = not s.enabled; self:Refresh() end },
          { Check(s.hideBlizz, "Hide Blizzard Numbers"), 190, function() s.hideBlizz = not s.hideBlizz; ApplyBlizzardFCT(s.hideBlizz); self:Refresh() end },
          { "Test", 80, function()
            QueueHit({ amount = 482, colorKey = 4, route = s.routeOutDmg })
            QueueHit({ amount = 1240, isCrit = true, colorKey = 1, route = s.routeOutDmg })
            QueueHit({ amount = 365, isHeal = true, prefix = "+", colorKey = "heal", route = s.routeOutHeal })
          end },
        })
        Row({
          { Check(s.outDamage, "Outgoing Damage"), 130, function() s.outDamage = not s.outDamage; self:Refresh() end },
          { Check(s.outHeal, "Outgoing Healing"), 130, function() s.outHeal = not s.outHeal; self:Refresh() end },
          { Check(s.inDamage, "Incoming Damage"), 130, function() s.inDamage = not s.inDamage; self:Refresh() end },
          { Check(s.inHeal, "Incoming Healing"), 130, function() s.inHeal = not s.inHeal; self:Refresh() end },
        })
        Row({
          { Check(s.pet, "Include My Pet"), 160, function() s.pet = not s.pet; self:Refresh() end },
        })

        Heading("Nameplate Style & Per-Style Offsets")
        Row({
          { (s.style == "modern" and "* " or "") .. "Modern", 110, function() s.style = "modern"; self:Refresh() end },
          { (s.style == "classic" and "* " or "") .. "Classic", 110, function() s.style = "classic"; self:Refresh() end },
          { (s.style == "impact" and "* " or "") .. "Impact", 110, function() s.style = "impact"; self:Refresh() end },
        })
        local off = s.styleOffsets[s.style]
        Row({
          { "Offset X: " .. off.x, 100, function() off.x = 0; self:Refresh() end },
          { "X -4", 54, function() off.x = off.x - 4; self:Refresh() end },
          { "X +4", 54, function() off.x = off.x + 4; self:Refresh() end },
          { "Offset Y: " .. off.y, 100, function() off.y = 20; self:Refresh() end },
          { "Y -4", 54, function() off.y = off.y - 4; self:Refresh() end },
          { "Y +4", 54, function() off.y = off.y + 4; self:Refresh() end },
        })
        Row({
          { "Dist: " .. s.npDistance, 90, function() s.npDistance = s.npDistance >= 100 and 40 or (s.npDistance + 16); self:Refresh() end },
          { string.format("Speed: %.1fx", s.npSpeed), 100, function() s.npSpeed = s.npSpeed >= 1.8 and 0.6 or (s.npSpeed + 0.2); self:Refresh() end },
          { string.format("Dur: %.1fs", s.npDuration), 90, function() s.npDuration = s.npDuration >= 2.0 and 0.7 or (s.npDuration + 0.2); self:Refresh() end },
        })
        if s.style == "modern" then
          local nxt = { up = "arc", arc = "bounce", bounce = "up" }
          Row({
            { "Normal: " .. s.modernMotions.normal, 140, function() s.modernMotions.normal = nxt[s.modernMotions.normal] or "up"; self:Refresh() end },
            { "Crit: " .. s.modernMotions.crit, 140, function() s.modernMotions.crit = nxt[s.modernMotions.crit] or "arc"; self:Refresh() end },
            { "Miss: " .. s.modernMotions.miss, 140, function() s.modernMotions.miss = nxt[s.modernMotions.miss] or "up"; self:Refresh() end },
          })
        end

        Heading("Destination Routing")
        local function NextRoute(cur, allowPlate)
          local opts = allowPlate and { "nameplate" } or {}
          for _, a in ipairs(s.areas) do opts[#opts + 1] = a.id end
          for i, v in ipairs(opts) do if v == cur then return opts[(i % #opts) + 1] end end
          return opts[1]
        end
        Row({
          { "Out Dmg -> " .. s.routeOutDmg, 174, function() s.routeOutDmg = NextRoute(s.routeOutDmg, true); self:Refresh() end },
          { "Out Heal -> " .. s.routeOutHeal, 174, function() s.routeOutHeal = NextRoute(s.routeOutHeal, true); self:Refresh() end },
          { "Incoming -> " .. s.routeIn, 174, function() s.routeIn = NextRoute(s.routeIn, false); self:Refresh() end },
        })

      elseif sctTab == "areas" then
        Row({
          { showingAreas and "Hide Scroll Areas" or "Show Scroll Areas", 170, function() ns.ToggleSCTScrollAreas(); self:Refresh() end },
        })
        local nameBox = Track(ns.InterfaceInput(self.child, 200, "New area name..."))
        nameBox:SetPoint("TOPLEFT", 4, y)
        local addBtn = Track(ns.InterfaceButton(self.child, "+ Add Area", 110, 22))
        addBtn:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
        addBtn:SetScript("OnClick", function()
          local nm = (nameBox:GetText() or ""):match("^%s*(.-)%s*$")
          if nm == "" then return end
          s.areas[#s.areas + 1] = { id = "area" .. time(), name = nm:sub(1, 16), x = 0, y = 0, w = 220, h = 180, anim = "up", align = "CENTER", spacing = 22, duration = 1.2 }
          self:Refresh()
        end)
        y = y - 28

        local nxtAnim = { up = "down", down = "arc", arc = "static", static = "up" }
        local nxtAlign = { LEFT = "CENTER", CENTER = "RIGHT", RIGHT = "LEFT" }
        for idx, a in ipairs(s.areas) do
          local iCopy, area = idx, a
          Heading(area.name .. " (" .. area.id .. ")")
          Row({
            { "Anim: " .. area.anim, 110, function() area.anim = nxtAnim[area.anim] or "up"; self:Refresh() end },
            { "Align: " .. area.align, 110, function() area.align = nxtAlign[area.align] or "CENTER"; self:Refresh() end },
            { string.format("Dur: %.1fs", area.duration), 96, function() area.duration = area.duration >= 2.4 and 0.8 or (area.duration + 0.2); self:Refresh() end },
            { "Spacing: " .. area.spacing, 100, function() area.spacing = area.spacing >= 32 and 14 or (area.spacing + 4); self:Refresh() end },
            #s.areas > 1 and { "Delete", 74, function() table.remove(s.areas, iCopy); self:Refresh() end } or { "Default", 74, function() end },
          })
        end

      elseif sctTab == "filters" then
        Heading("Minimum Damage Threshold (e.g. 500, 20k, 2m)")
        local thBox = Track(ns.InterfaceInput(self.child, 180, tostring(s.minThreshold or 0)))
        thBox:SetPoint("TOPLEFT", 4, y)
        local setTh = Track(ns.InterfaceButton(self.child, "Apply Threshold", 130, 22))
        setTh:SetPoint("LEFT", thBox, "RIGHT", 6, 0)
        setTh:SetScript("OnClick", function()
          s.minThreshold = ParseThreshold(thBox:GetText())
          ns.Print("SCT minimum damage threshold: " .. FormatNumber(s.minThreshold, "thousands"))
          self:Refresh()
        end)
        y = y - 28

        Row({
          { Check(s.critsOnly, "Critical Damage Only"), 200, function() s.critsOnly = not s.critsOnly; self:Refresh() end },
          { Check(s.misses, "Show Misses & Avoidance"), 220, function() s.misses = not s.misses; self:Refresh() end },
        })

        Heading("Combine Rapid Hits")
        Row({
          { s.mergeWindow > 0 and string.format("Merge Window: %.1fs", s.mergeWindow) or "Merge: Off", 170, function()
            s.mergeWindow = s.mergeWindow >= 1.5 and 0 or (s.mergeWindow + 0.3); self:Refresh()
          end },
          { Check(s.mergeSeparateSpells, "Keep Spells Separate"), 186, function() s.mergeSeparateSpells = not s.mergeSeparateSpells; self:Refresh() end },
        })
        Row({
          { Check(s.mergeShowCount, "Show Hit Counts (x3)"), 186, function() s.mergeShowCount = not s.mergeShowCount; self:Refresh() end },
          { Check(s.mergePop, "Pop on Each Merge"), 186, function() s.mergePop = not s.mergePop; self:Refresh() end },
        })

      elseif sctTab == "look" then
        Heading("Outgoing Font & Number Format")
        Row({
          { "Font: " .. s.font, 150, function(btn)
            if ns.UIKit and ns.UIKit.OpenMenu then
              local items = {}
              for _, f in ipairs(ns.CHAT_FONTS or {}) do items[#items + 1] = { label = f.label, value = f.value } end
              ns.UIKit.OpenMenu(btn, items, s.font, function(v) s.font = v or "epu"; self:Refresh() end)
            end
          end },
          { "Size: " .. s.size, 84, function() s.size = s.size >= 28 and 12 or (s.size + 2); self:Refresh() end },
          { "Format: " .. s.numFormat, 136, function()
            s.numFormat = ({ full = "thousands", thousands = "compact", compact = "full" })[s.numFormat] or "thousands"; self:Refresh()
          end },
          { "Icons: " .. s.iconPos, 114, function()
            s.iconPos = ({ off = "left", left = "right", right = "above", above = "below", below = "off" })[s.iconPos] or "left"; self:Refresh()
          end },
        })

        Heading("Incoming Hits Font")
        Row({
          { "In Font: " .. s.inFont, 150, function(btn)
            if ns.UIKit and ns.UIKit.OpenMenu then
              local items = {}
              for _, f in ipairs(ns.CHAT_FONTS or {}) do items[#items + 1] = { label = f.label, value = f.value } end
              ns.UIKit.OpenMenu(btn, items, s.inFont, function(v) s.inFont = v or "epu"; self:Refresh() end)
            end
          end },
          { "In Size: " .. s.inSize, 100, function() s.inSize = s.inSize >= 26 and 12 or (s.inSize + 2); self:Refresh() end },
        })

        Heading("School Colors (Click to Customize)")
        local function PickSchoolColor(key)
          if not ColorPickerFrame then return end
          local r, g, b = SchoolColor(key)
          local function Apply(nr, ng, nb)
            s.schoolColors[key] = { nr, ng, nb }
            self:Refresh()
          end
          if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
              r = r, g = g, b = b,
              swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
              cancelFunc = function(prev) if prev then Apply(prev.r, prev.g, prev.b) end end,
            })
          end
        end
        Row({
          { "Physical", 82, function() PickSchoolColor(1) end },
          { "Fire", 64, function() PickSchoolColor(4) end },
          { "Frost", 68, function() PickSchoolColor(16) end },
          { "Nature", 76, function() PickSchoolColor(8) end },
          { "Shadow", 80, function() PickSchoolColor(32) end },
          { "Arcane", 76, function() PickSchoolColor(64) end },
          { "Holy", 64, function() PickSchoolColor(2) end },
        })

        Heading("Crit Sounds")
        local function NextSound(cur)
          for i, sc in ipairs(SOUND_CHOICES) do if sc.id == cur then return SOUND_CHOICES[(i % #SOUND_CHOICES) + 1].id end end
          return SOUND_CHOICES[2].id
        end
        local function SoundLabel(id)
          for _, sc in ipairs(SOUND_CHOICES) do if sc.id == id then return sc.label end end
          return "Off"
        end
        local nxtChan = { Master = "SFX", SFX = "Dialog", Dialog = "Ambience", Ambience = "Master" }
        Row({
          { "Crit Sound: " .. SoundLabel(s.critSound), 170, function() s.critSound = NextSound(s.critSound); self:Refresh() end },
          { "Chan: " .. s.critSoundChan, 110, function() s.critSoundChan = nxtChan[s.critSoundChan] or "Master"; self:Refresh() end },
        })
        Row({
          { "Huge Crit (" .. s.hugeCritThreshold .. "+): " .. SoundLabel(s.hugeCritSound), 220, function() s.hugeCritSound = NextSound(s.hugeCritSound); self:Refresh() end },
          { "Threshold: " .. s.hugeCritThreshold, 120, function() s.hugeCritThreshold = s.hugeCritThreshold >= 5000 and 500 or (s.hugeCritThreshold + 500); self:Refresh() end },
          { "Chan: " .. s.hugeCritSoundChan, 110, function() s.hugeCritSoundChan = nxtChan[s.hugeCritSoundChan] or "Master"; self:Refresh() end },
        })
      end

      self.child:SetHeight(math.max(200, -y + 16))
    end
  end
  sctWin:Refresh()
  sctWin:Show()
end

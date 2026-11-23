-- EPU Guild Tools: Customizable floating windows for XP & Rep and Server/Loot.
-- (0.29.x also had a Combat Log window. It listened for chat events the game
-- dropped in 2.4, so it never showed anything; DB() clears what it saved.)
local _, ns = ...

local ORDER = { "xp", "system" }
local DEFAULTS = {
  xp = { title = "EPU XP & Reputation", tab = "XP & Rep", enabled = false, maxLines = 120, fontSize = 11, x = 0, y = 120, w = 340, h = 260 },
  system = { title = "EPU Server & Loot", tab = "Server & Loot", enabled = false, maxLines = 150, fontSize = 11, x = 260, y = 120, w = 340, h = 260 },
}

local frames = {}
local combinedFrame
local logs = { xp = {}, system = {} }
local rawLogs = { xp = {}, system = {} }
local paused = {}
local sessionStart = time()
local sessionXP = 0

local function DB()
  if not ns.db then return {} end
  ns.db.logWindows = ns.db.logWindows or {}
  -- The Combat Log window is gone: drop its saved settings and its tab.
  ns.db.logWindows.combat = nil
  for k, def in pairs(DEFAULTS) do
    ns.db.logWindows[k] = ns.db.logWindows[k] or {}
    local s = ns.db.logWindows[k]
    if s.enabled == nil then s.enabled = def.enabled end
    if s.fontSize == nil then s.fontSize = def.fontSize end
  end
  if type(ns.db.logWindows.combinedCfg) ~= "table" then
    ns.db.logWindows.combinedCfg = { x = 0, y = 120, w = 380, h = 280, active = "system", fontSize = 11 }
  end
  if not DEFAULTS[ns.db.logWindows.combinedCfg.active or "system"] then ns.db.logWindows.combinedCfg.active = "system" end
  return ns.db.logWindows
end

function ns.IsLogWindowsCombined()
  return DB().combined == true
end

local function SyncSettingsUI()
  if ns.RefreshPopoutChatSettings then ns.RefreshPopoutChatSettings() end
end

local function BuildLogText(kind)
  local header = ""
  if kind == "xp" then
    local elapsed = math.max(1, time() - sessionStart)
    local xph = math.floor((sessionXP / elapsed) * 3600)
    header = string.format("|cff4fc3f7Session XP: %d  (%d/hr)|r\n\n", sessionXP, xph)
  end
  return header .. (#logs[kind] > 0 and table.concat(logs[kind], "\n") or "|cff888888Waiting for messages...|r")
end

local function LayoutScrollText(f)
  if not f or not f.scroll or not f.child or not f.text then return end
  local w = math.max(140, (f:GetWidth() or 340) - 24)
  f.child:SetWidth(w)
  f.text:SetWidth(w - 4)
  f.child:SetHeight(math.max(100, (f.text:GetStringHeight() or 40) + 16))
end

-- Follow new lines only when the reader is already at the newest one, so
-- scrolling up to read back isn't undone by every loot or system message.
local function AtNewest(f)
  if not (f.scroll and f.scroll.GetVerticalScroll and f.child) then return true end
  local maxV = math.max(0, (f.child:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
  return (f.scroll:GetVerticalScroll() or 0) >= maxV - 20
end

local function RefreshWindow(kind)
  local db = DB()
  if ns.IsLogWindowsCombined() then
    local f = combinedFrame
    if not f or not f:IsShown() then return end
    local cfg = db.combinedCfg or {}
    local active = cfg.active
    if not DEFAULTS[active] then active = "system"; cfg.active = active end
    local follow = AtNewest(f) or f.lastActive ~= active
    f.lastActive = active
    local fnt = f.text.SetFont and f.text:GetFont()
    if fnt then f.text:SetFont(fnt, cfg.fontSize or 11, "") end
    f.text:SetText(BuildLogText(active))
    LayoutScrollText(f)
    if f.UpdateTabs then f:UpdateTabs() end
    if f.pauseBtn then f.pauseBtn:SetText(paused[active] and "Resume" or "Pause") end
    if follow and f.scroll and f.scroll.SetVerticalScroll then
      local maxV = math.max(0, (f.child:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
      f.scroll:SetVerticalScroll(maxV)
    end
    return
  end

  local f = frames[kind]
  if not f or not f:IsShown() then return end
  local cfg = db[kind] or DEFAULTS[kind]
  local follow = AtNewest(f)
  local fnt = f.text.SetFont and f.text:GetFont()
  if fnt then f.text:SetFont(fnt, cfg.fontSize or 11, "") end
  f.text:SetText(BuildLogText(kind))
  LayoutScrollText(f)
  if f.pauseBtn then f.pauseBtn:SetText(paused[kind] and "Resume" or "Pause") end
  if follow and f.scroll and f.scroll.SetVerticalScroll then
    local maxV = math.max(0, (f.child:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
    f.scroll:SetVerticalScroll(maxV)
  end
end

local function Append(kind, msg, colorHex)
  -- Check for a secret value before comparing: comparing one is an error.
  if paused[kind] or type(msg) ~= "string" then return end
  if issecretvalue and issecretvalue(msg) then return end
  if msg == "" then return end
  local list = logs[kind]
  local raw = rawLogs[kind]
  local maxL = DEFAULTS[kind].maxLines
  local now = time()
  local line = string.format("|cff888888%s|r %s%s|r", date("%H:%M:%S", now), colorHex or "|cffffffff", msg)
  list[#list + 1] = line
  raw[#raw + 1] = { t = now, msg = msg, color = colorHex or "|cffffffff", kind = kind }
  while #list > maxL do table.remove(list, 1) end
  while #raw > maxL do table.remove(raw, 1) end
  RefreshWindow(kind)
  if ns.RefreshChatBubble then ns.RefreshChatBubble() end
  if ns.ChatWindows then
    for _, w in pairs(ns.ChatWindows) do
      if w and w.IsShown and w:IsShown() and w.Key and type(w:Key()) == "string" and w:Key():sub(1, 7) == "custom:" then
        if w.Update then w:Update() end
      end
    end
  end
end

function ns.GetLogStreamLines(kind)
  return rawLogs[kind] or {}
end

local function AddResizeGrip(f, saveFn)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:EnableMouse(true)
  local C = ns.InterfaceColors
  for i = 1, 3 do
    local d = grip:CreateTexture(nil, "OVERLAY")
    d:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.65)
    d:SetSize(2, 2)
    d:SetPoint("BOTTOMRIGHT", -3 - (i - 1) * 4, 3)
    if i > 1 then
      local d2 = grip:CreateTexture(nil, "OVERLAY")
      d2:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.65)
      d2:SetSize(2, 2)
      d2:SetPoint("BOTTOMRIGHT", -3, 3 + (i - 1) * 4)
    end
  end
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    if f.SetUserPlaced then f:SetUserPlaced(false) end
    if saveFn then saveFn(f) end
  end)
  return grip
end

-- Build a MEDIUM-strata, non-UISpecialFrames window so Esc won't close it and bags/panels stay on top.
local function CreateFloatingLogFrame(name, title, w, h, x, y, onClose, onSave, point, relPoint)
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:ClearAllPoints()
  f:SetPoint(point or "CENTER", UIParent, relPoint or "CENTER", x, y)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(240, 140, 900, 760)
  elseif f.SetMinResize then f:SetMinResize(240, 140) end

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.96)
  bg:SetAllPoints()
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4] or 1)
    t:SetPoint(side[1]); t:SetPoint(side[2])
    if side[3] then t:SetHeight(1) else t:SetWidth(1) end
  end

  f.TitleText = ns.InterfaceFont(f, 13, C.white)
  f.TitleText:SetPoint("TOPLEFT", 10, -9)
  f.TitleText:SetText(title)

  local rule = f:CreateTexture(nil, "BORDER")
  rule:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4] or 1)
  rule:SetPoint("TOPLEFT", 1, -30); rule:SetPoint("TOPRIGHT", -1, -30); rule:SetHeight(1)

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    if onSave then onSave(self) end
  end)

  local close = ns.InterfaceButton(f, "×", 22, 20)
  close:SetPoint("TOPRIGHT", -6, -5)
  close:SetScript("OnClick", function()
    f:Hide()
    if onClose then onClose() end
  end)
  f.closeBtn = close

  AddResizeGrip(f, onSave)
  return f
end

local function SaveFrameGeom(f, tbl)
  if not f or not tbl then return end
  local p, _, rp, x, y = f:GetPoint()
  tbl.point = p or "CENTER"
  tbl.relPoint = rp or "CENTER"
  tbl.x = math.floor((x or 0) + 0.5)
  tbl.y = math.floor((y or 0) + 0.5)
  tbl.w = math.floor((f:GetWidth() or 340) + 0.5)
  tbl.h = math.floor((f:GetHeight() or 260) + 0.5)
end

local function EnsureWindow(kind)
  if frames[kind] then return frames[kind] end
  local def = DEFAULTS[kind]
  local cfg = DB()[kind] or def
  local C = ns.InterfaceColors

  local f = CreateFloatingLogFrame(
    "EPUGuildLog_" .. kind,
    def.title,
    cfg.w or def.w,
    cfg.h or def.h,
    -- 0.29.x saved x/y without the anchor point; those don't place right.
    cfg.point and cfg.x or def.x,
    cfg.point and cfg.y or def.y,
    function()
      local s = DB()[kind]
      if s then s.enabled = false end
      SyncSettingsUI()
    end,
    function(self)
      SaveFrameGeom(self, DB()[kind])
    end,
    cfg.point,
    cfg.relPoint
  )

  local clr = ns.InterfaceButton(f, "Clear", 44, 20)
  clr:SetPoint("RIGHT", f.closeBtn, "LEFT", -4, 0)
  clr:SetScript("OnClick", function() logs[kind] = {}; RefreshWindow(kind) end)

  local pauseBtn = ns.InterfaceButton(f, "Pause", 46, 20)
  pauseBtn:SetPoint("RIGHT", clr, "LEFT", -4, 0)
  pauseBtn:SetScript("OnClick", function(self)
    paused[kind] = not paused[kind]
    self:SetText(paused[kind] and "Resume" or "Pause")
  end)
  f.pauseBtn = pauseBtn

  local smaller = ns.InterfaceButton(f, "A-", 24, 20)
  smaller:SetPoint("RIGHT", pauseBtn, "LEFT", -4, 0)
  smaller:SetScript("OnClick", function()
    local s = DB()[kind]; s.fontSize = math.max(9, (s.fontSize or 11) - 1); RefreshWindow(kind)
  end)

  local bigger = ns.InterfaceButton(f, "A+", 24, 20)
  bigger:SetPoint("RIGHT", smaller, "LEFT", -2, 0)
  bigger:SetScript("OnClick", function()
    local s = DB()[kind]; s.fontSize = math.min(20, (s.fontSize or 11) + 1); RefreshWindow(kind)
  end)

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 10, -36)
  scroll:SetPoint("BOTTOMRIGHT", -10, 14)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(math.max(140, (cfg.w or def.w) - 24)); child:SetHeight(160)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 32)))
  end)

  local text = ns.InterfaceFont(child, cfg.fontSize or 11, C.text)
  text:SetPoint("TOPLEFT", 2, -2)
  text:SetWidth(math.max(136, (cfg.w or def.w) - 28))
  text:SetJustifyH("LEFT")
  text:SetWordWrap(true)

  f.scroll, f.child, f.text = scroll, child, text
  f:SetScript("OnSizeChanged", function() RefreshWindow(kind) end)
  frames[kind] = f
  return f
end

local function EnsureCombinedWindow()
  if combinedFrame then return combinedFrame end
  local db = DB()
  local cfg = db.combinedCfg
  local C = ns.InterfaceColors

  local f = CreateFloatingLogFrame(
    "EPUGuildLog_Combined",
    "EPU Logs",
    cfg.w or 380,
    cfg.h or 280,
    cfg.point and cfg.x or 0,
    cfg.point and cfg.y or 120,
    function()
      local d = DB()
      for _, k in ipairs(ORDER) do
        if d[k] then d[k].enabled = false end
      end
      SyncSettingsUI()
    end,
    function(self)
      SaveFrameGeom(self, DB().combinedCfg)
    end,
    cfg.point,
    cfg.relPoint
  )

  local clr = ns.InterfaceButton(f, "Clear", 44, 20)
  clr:SetPoint("RIGHT", f.closeBtn, "LEFT", -4, 0)
  clr:SetScript("OnClick", function()
    local active = DB().combinedCfg.active or "system"
    logs[active] = {}
    RefreshWindow(active)
  end)

  local pauseBtn = ns.InterfaceButton(f, "Pause", 46, 20)
  pauseBtn:SetPoint("RIGHT", clr, "LEFT", -4, 0)
  pauseBtn:SetScript("OnClick", function(self)
    local active = DB().combinedCfg.active or "system"
    paused[active] = not paused[active]
    self:SetText(paused[active] and "Resume" or "Pause")
  end)
  f.pauseBtn = pauseBtn

  local smaller = ns.InterfaceButton(f, "A-", 24, 20)
  smaller:SetPoint("RIGHT", pauseBtn, "LEFT", -4, 0)
  smaller:SetScript("OnClick", function()
    local c = DB().combinedCfg
    c.fontSize = math.max(9, (c.fontSize or 11) - 1)
    RefreshWindow(c.active or "system")
  end)

  local bigger = ns.InterfaceButton(f, "A+", 24, 20)
  bigger:SetPoint("RIGHT", smaller, "LEFT", -2, 0)
  bigger:SetScript("OnClick", function()
    local c = DB().combinedCfg
    c.fontSize = math.min(20, (c.fontSize or 11) + 1)
    RefreshWindow(c.active or "system")
  end)

  f.tabBtns = {}
  for _, k in ipairs(ORDER) do
    local b = ns.InterfaceButton(f, DEFAULTS[k].tab, 90, 20)
    b:SetScript("OnClick", function()
      DB().combinedCfg.active = k
      RefreshWindow(k)
    end)
    f.tabBtns[k] = b
  end

  function f:UpdateTabs()
    local d = DB()
    local active = d.combinedCfg.active or "system"
    local shown = {}
    for _, k in ipairs(ORDER) do
      if d[k] and d[k].enabled then shown[#shown + 1] = k end
    end
    if #shown == 0 then shown = { "xp", "system" } end
    local activeVisible = false
    for _, k in ipairs(shown) do if k == active then activeVisible = true; break end end
    if not activeVisible then active = shown[1]; d.combinedCfg.active = active end

    local width = math.max(200, (f:GetWidth() or 380) - 20)
    local tw = math.floor((width - (#shown - 1) * 4) / #shown)
    for _, k in ipairs(ORDER) do f.tabBtns[k]:Hide() end
    for i, k in ipairs(shown) do
      local b = f.tabBtns[k]
      b:ClearAllPoints()
      b:SetSize(tw, 20)
      b:SetPoint("TOPLEFT", 10 + (i - 1) * (tw + 4), -36)
      if b.SetOn then b:SetOn(k == active)
      elseif b.text then b.text:SetTextColor(k == active and 1 or 0.72, k == active and 0.84 or 0.72, k == active and 0.35 or 0.72) end
      b:Show()
    end
  end

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 10, -62)
  scroll:SetPoint("BOTTOMRIGHT", -10, 14)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(math.max(140, (cfg.w or 380) - 24)); child:SetHeight(160)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 32)))
  end)

  local text = ns.InterfaceFont(child, cfg.fontSize or 11, C.text)
  text:SetPoint("TOPLEFT", 2, -2)
  text:SetWidth(math.max(136, (cfg.w or 380) - 28))
  text:SetJustifyH("LEFT")
  text:SetWordWrap(true)

  f.scroll, f.child, f.text = scroll, child, text
  f:SetScript("OnSizeChanged", function() RefreshWindow(DB().combinedCfg.active or "system") end)
  combinedFrame = f
  return f
end

local function SyncVisibility()
  local db = DB()
  local anyEnabled = false
  for _, k in ipairs(ORDER) do
    if db[k] and db[k].enabled then anyEnabled = true; break end
  end

  if ns.IsLogWindowsCombined() then
    for _, f in pairs(frames) do f:Hide() end
    if anyEnabled then
      local cf = EnsureCombinedWindow()
      cf:Show()
      RefreshWindow(db.combinedCfg.active or "system")
    elseif combinedFrame then
      combinedFrame:Hide()
    end
  else
    if combinedFrame then combinedFrame:Hide() end
    for _, k in ipairs(ORDER) do
      if db[k] and db[k].enabled then
        local f = EnsureWindow(k)
        f:Show()
        RefreshWindow(k)
      elseif frames[k] then
        frames[k]:Hide()
      end
    end
  end
end

function ns.IsLogWindowEnabled(kind)
  local s = DB()[kind]
  return s and s.enabled == true
end

function ns.ToggleLogWindow(kind, force)
  if not DEFAULTS[kind] then return end
  local db = DB()
  local s = db[kind]
  if force == nil then s.enabled = not s.enabled else s.enabled = force and true or false end
  if s.enabled and ns.IsLogWindowsCombined() then
    db.combinedCfg.active = kind
  end
  SyncVisibility()
end

function ns.SetLogWindowsCombined(on)
  DB().combined = on and true or false
  SyncVisibility()
end

function ns.OpenLogWindowsMenu()
  ns.ToggleLogWindow("xp", true)
  ns.ToggleLogWindow("system", true)
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    SyncVisibility()
  end)

  ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    if type(msg) == "string" and not (issecretvalue and issecretvalue(msg)) then
      local gained = tonumber(msg:match("(%d+)%s+experience"))
      if gained then sessionXP = sessionXP + gained end
    end
    Append("xp", msg, "|cffc77dff")
  end)
  ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg) Append("xp", msg, "|cff70b8ff") end)
  ns.On("CHAT_MSG_SKILL", function(msg) Append("xp", msg, "|cff4ade80") end)

  ns.On("CHAT_MSG_SYSTEM", function(msg) Append("system", msg, "|cffffff00") end)
  ns.On("CHAT_MSG_LOOT", function(msg) Append("system", msg, "|cff1eff00") end)
  ns.On("CHAT_MSG_MONEY", function(msg) Append("system", msg, "|cffffd100") end)
end

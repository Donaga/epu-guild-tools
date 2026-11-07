-- EPU Guild Tools: main window (flat dark style), details panel, officer
-- settings, and the minimap button.
local ADDON, ns = ...
-- Newer clients keep these under C_Item; the old global names only exist when
-- the game's "deprecated API" fallback is on, which varies from PC to PC.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local C = {
  bg     = { 0.082, 0.090, 0.106 },
  panel  = { 0.106, 0.118, 0.137 },
  panel2 = { 0.165, 0.184, 0.216 },
  hover  = { 0.137, 0.153, 0.180 },
  line   = { 0.176, 0.192, 0.224 },
  input  = { 0.071, 0.078, 0.094 },
  text   = { 0.85, 0.86, 0.88 },
  muted  = { 0.49, 0.52, 0.56 },
  white  = { 1, 1, 1 },
  gold   = { 0.95, 0.76, 0.31 },
  goldBg = { 0.17, 0.14, 0.07 },
  green  = { 0.29, 0.87, 0.50 },
  greenBg= { 0.07, 0.19, 0.11 },
  red    = { 1.00, 0.42, 0.42 },
  redBg  = { 0.23, 0.09, 0.09 },
  blue   = { 0.43, 0.66, 1.00 },
}
local PILL = {
  pending  = { "Pending",  C.goldBg,  C.gold },
  sync_wait   = { "Waiting",     C.goldBg, C.gold },
  sync_unconf = { "Unconfirmed", C.goldBg, C.gold },
  open     = { "Pending",  C.goldBg,  C.gold },
  approved = { "Approved", C.greenBg, C.green },
  filled   = { "Filled",   C.panel2,  C.muted },
  rejected = { "Rejected", C.redBg,   C.red },
  cancelled= { "Cancelled",C.panel2,  C.muted },
  -- craft requests (asked of a crafter, not the bank)
  craft_pending  = { "Asked",    C.goldBg,  C.gold },
  craft_open     = { "Asked",    C.goldBg,  C.gold },
  craft_approved = { "Accepted", C.greenBg, C.green },
  craft_filled   = { "Made",     C.panel2,  C.muted },
  craft_rejected = { "Declined", C.redBg,   C.red },
  craft_cancelled= { "Cancelled",C.panel2,  C.muted },
}
PILL.news_new = { "New", C.goldBg, C.gold }
PILL.roster_inactive = { "Inactive", C.redBg, C.red }
PILL.roster_promote = { "Promote?", C.goldBg, C.gold }
local function PillKey(r) return (r.crafter and "craft_" or "") .. (r.status or "pending") end

-- Skill-up colors: orange always gives a point, yellow usually, green sometimes.
local DIFF = { o = { "ff8040", "orange" }, y = { "ffff00", "yellow" }, g = { "40c040", "green" } }
local function SkillMark(d) return DIFF[d] and ("|cff" .. DIFF[d][1] .. "+|r") or "" end
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local SIDEBAR_W, HEADER_H, TOOLBAR_H, COMPOSER_H, FOOTER_H, ROW_H, DETAILS_W = 140, 36, 34, 36, 24, 38, 280

local function Tex(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function Edges(f, c)
  local e = {}
  for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = Tex(f, "BORDER", c)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
    else
      t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
    end
    e[i] = t
  end
  f.edges = e
  return e
end

local function EdgeColor(f, c)
  for _, t in ipairs(f.edges or {}) do t:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function Font(parent, size, c, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(FONT, size or 12, "")
  fs:SetTextColor((c or C.text)[1], (c or C.text)[2], (c or C.text)[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- style: nil (plain), "accent" (gold), "chip" (rounded-ish filter chip)
local function Btn(parent, label, w, h, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 80, h or 22)
  b.style = style
  b.base = (style == "accent") and C.goldBg or C.panel
  b.bg = Tex(b, "BACKGROUND", b.base)
  b.bg:SetAllPoints()
  Edges(b, (style == "accent") and C.gold or C.line)
  b.text = Font(b, 11, (style == "accent") and C.gold or C.text)
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  b.text:SetText(label or "")
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(self.base[1], self.base[2], self.base[3], 1)
    GameTooltip_Hide()
  end)
  function b:SetLabel(t) self.text:SetText(t) end
  function b:SetOn(on)
    self.on = on
    self.base = on and C.panel2 or ((self.style == "accent") and C.goldBg or C.panel)
    self.bg:SetColorTexture(self.base[1], self.base[2], self.base[3], 1)
    EdgeColor(self, on and C.gold or ((self.style == "accent") and C.gold or C.line))
    SetColor(self.text, on and C.white or ((self.style == "accent") and C.gold or C.text))
  end
  return b
end

local function IconBtn(parent, texture, tip, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 22, size or 22)
  b.bg = Tex(b, "BACKGROUND", C.panel)
  b.bg:SetAllPoints()
  Edges(b, C.line)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("CENTER")
  b.icon:SetSize((size or 22) - 6, (size or 22) - 6)
  b.icon:SetTexture(texture)
  b.tip = tip
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
    GameTooltip_Hide()
  end)
  return b
end

local UI   -- forward
local function Box(parent, w, placeholder, numeric)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w or 120, 22)
  e:SetAutoFocus(false)
  e:SetFont(FONT, 12, "")
  e:SetTextColor(C.white[1], C.white[2], C.white[3])
  e:SetTextInsets(6, 6, 0, 0)
  if numeric then e:SetNumeric(true) end
  e.bg = Tex(e, "BACKGROUND", C.input)
  e.bg:SetAllPoints()
  Edges(e, C.line)
  e.ph = Font(e, 11, C.muted)
  e.ph:SetPoint("LEFT", 6, 0)
  e.ph:SetPoint("RIGHT", -6, 0)
  e.ph:SetJustifyH("LEFT")
  e.ph:SetWordWrap(false)
  e.ph:SetText(placeholder or "")
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEditFocusGained", function(self) EdgeColor(self, C.gold); UI.focusBox = self end)
  e:SetScript("OnEditFocusLost", function(self) EdgeColor(self, C.line); if UI.focusBox == self then UI.focusBox = nil end end)
  e:SetScript("OnTextChanged", function(self)
    self.ph:SetShown(self:GetText() == "")
    if self.onChange then self.onChange(self) end
  end)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if self.onEnter then self.onEnter(self) end
  end)
  -- drop an item onto the box (released from a drag, or clicked with it on the cursor)
  local function TakeCursorItem(self)
    local kind, id, link = GetCursorInfo()
    if kind == "item" and id then
      self:SetText(link or select(2, GetItemInfo(id)) or ("item:" .. id))
      ClearCursor()
      return true
    end
  end
  e.TakeCursorItem = TakeCursorItem
  e:SetScript("OnReceiveDrag", TakeCursorItem)
  e:HookScript("OnMouseDown", function(self) TakeCursorItem(self) end)
  return e
end

local function Money(c)
  c = math.floor(tonumber(c) or 0)
  if GetCoinTextureString then return GetCoinTextureString(c) end
  local gold, silver, copper = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = "|cffffd700" .. gold .. "g|r" end
  if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "s|r" end
  if copper > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. copper .. "c|r" end
  return table.concat(parts, " ")
end

local function Ago(t)
  if not t then return "never" end
  local s = ns.Now() - t
  if s < 120 then return "just now" end
  if s < 7200 then return math.floor(s / 60) .. "m ago" end
  if s < 172800 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

local function Quality(id)
  if not id then return 1 end
  local _, _, q = GetItemInfo(id)
  return q or 1
end

local function QColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.r then return { c.r, c.g, c.b } end
  return C.white
end

local function Online(name)
  return ns.roster[name] ~= nil and ns.roster[name].online == true
end

-- Dropdown menu: a flat list that opens under a button.
-- items = { { label =, value =, right = } ... }; onPick(value) runs on click.
local Menu
local function OpenMenu(anchor, items, current, onPick)
  if not Menu then
    Menu = CreateFrame("Frame", "EPUGuildMenu", UIParent)
    Menu:SetFrameStrata("DIALOG")
    Menu:SetClampedToScreen(true)
    Menu:EnableMouse(true)
    Menu.bg = Tex(Menu, "BACKGROUND", C.panel); Menu.bg:SetAllPoints()
    Edges(Menu, C.line)
    Menu.rows = {}
    -- a clear frame behind the menu: clicking anywhere else closes it
    Menu.catch = CreateFrame("Button", nil, UIParent)
    Menu.catch:SetFrameStrata("DIALOG")
    Menu.catch:SetAllPoints(UIParent)
    Menu.catch:RegisterForClicks("AnyUp")
    Menu.catch:SetScript("OnClick", function() Menu:Hide() end)
    Menu.catch:Hide()
    Menu:SetScript("OnShow", function(self)
      self.catch:Show()
      self:SetFrameLevel(self.catch:GetFrameLevel() + 10)   -- rows must sit above the click-anywhere-to-close layer
    end)
    Menu:SetScript("OnHide", function(self) self.catch:Hide() end)
    tinsert(UISpecialFrames, "EPUGuildMenu")   -- Escape closes it
  end
  if Menu:IsShown() and Menu.anchor == anchor then Menu:Hide(); return end
  Menu.anchor = anchor
  local w = math.max(anchor:GetWidth(), 170)
  for i, it in ipairs(items) do
    local r = Menu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, Menu)
      r:SetHeight(22)
      r.hl = Tex(r, "BACKGROUND", C.hover); r.hl:SetAllPoints(); r.hl:Hide()
      r.mark = Tex(r, "ARTWORK", C.gold); r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
      r.text = Font(r, 11); r.text:SetPoint("LEFT", 10, 0)
      r.right = Font(r, 11, C.muted); r.right:SetPoint("RIGHT", -8, 0); r.right:SetJustifyH("RIGHT")
      r:SetScript("OnEnter", function(self) self.hl:Show() end)
      r:SetScript("OnLeave", function(self) self.hl:Hide() end)
      r:SetScript("OnClick", function(self) Menu:Hide(); if Menu.onPick then Menu.onPick(self.value) end end)
      Menu.rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22); r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
    r.value = it.value
    local on = it.value == current
    r.text:SetText(it.label); SetColor(r.text, on and C.white or C.text)
    r.right:SetText(it.right or "")
    r.mark:SetShown(on)
    r:Show()
  end
  for i = #items + 1, #Menu.rows do Menu.rows[i]:Hide() end
  Menu.onPick = onPick
  Menu:SetScale(UI and UI:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1)
  Menu:SetSize(w, #items * 22 + 2)
  Menu:ClearAllPoints()
  Menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  Menu:Show()
end
ns.OpenMenu = OpenMenu

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
UI = CreateFrame("Frame", "EPUGuildFrame", UIParent)
ns.UI = UI
UI:SetSize(700, 470)
UI:SetPoint("CENTER")
UI:SetFrameStrata("HIGH")
UI:SetToplevel(true)
UI:SetClampedToScreen(true)
UI:SetMovable(true)
UI:SetResizable(true)
if UI.SetResizeBounds then UI:SetResizeBounds(620, 420, 1400, 1000)
elseif UI.SetMinResize then UI:SetMinResize(620, 420); UI:SetMaxResize(1400, 1000) end
UI:EnableMouse(true)
UI:Hide()
tinsert(UISpecialFrames, "EPUGuildFrame")
UI.bg = Tex(UI, "BACKGROUND", C.bg, 0.97)
UI.bg:SetAllPoints()
Edges(UI, C.line)

function UI:Toggle()
  if self:IsShown() then self:Hide() else self:Show() end
end

-- Header ------------------------------------------------------------------
local header = CreateFrame("Frame", nil, UI)
header:SetPoint("TOPLEFT", 1, -1)
header:SetPoint("TOPRIGHT", -1, -1)
header:SetHeight(HEADER_H)
Tex(header, "BACKGROUND", C.panel):SetAllPoints()
local hline = Tex(header, "BORDER", C.line)
hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function() UI:StartMoving() end)
header:SetScript("OnDragStop", function() UI:StopMovingOrSizing(); UI:SaveLayout() end)

local logo = header:CreateTexture(nil, "ARTWORK")
logo:SetSize(28, 28)
logo:SetPoint("LEFT", 8, 0)
logo:SetTexture(ns.LOGO)
local title = Font(header, 13, C.white)
title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
title:SetText("EPU Guild Bank")

local closeBtn = IconBtn(header, "Interface\\Buttons\\UI-StopButton", "Close")
closeBtn:SetPoint("RIGHT", -8, 0)
closeBtn:SetScript("OnClick", function() UI:Hide() end)
local syncBtn = IconBtn(header, "Interface\\Buttons\\UI-RefreshButton", "Sync with online officers")
syncBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
syncBtn:SetScript("OnClick", function() ns.FullSync() end)

UI.search = Box(header, 260, "Search items, members...")
UI.search:SetPoint("LEFT", title, "RIGHT", 18, 0)
UI.search:SetPoint("RIGHT", syncBtn, "LEFT", -10, 0)
UI.search:SetTextInsets(22, 6, 0, 0)
UI.search.ph:SetPoint("LEFT", 22, 0)
local mag = UI.search:CreateTexture(nil, "OVERLAY")
mag:SetSize(14, 14)
mag:SetPoint("LEFT", 5, 0)
mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
UI.search.onChange = function() UI:Refresh() end

-- Sidebar -------------------------------------------------------------------
local side = CreateFrame("Frame", nil, UI)
side:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
side:SetPoint("BOTTOMLEFT", 1, 1)
side:SetWidth(SIDEBAR_W)
Tex(side, "BACKGROUND", C.panel):SetAllPoints()
local sline = Tex(side, "BORDER", C.line)
sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)

local goldText = Font(side, 13, C.gold)
goldText:SetPoint("BOTTOMLEFT", 10, 30)
local syncText = Font(side, 10, C.muted)
syncText:SetPoint("BOTTOMLEFT", 10, 12)
syncText:SetWidth(SIDEBAR_W - 16)
-- hover the status line for the details
local syncHover = CreateFrame("Frame", nil, side)
syncHover:SetPoint("BOTTOMLEFT", 4, 6); syncHover:SetPoint("BOTTOMRIGHT", -4, 6); syncHover:SetHeight(20)
syncHover:EnableMouse(true)
syncHover:SetScript("OnEnter", function(self)
  if not ns.SyncStatus then return end
  local label, _, long = ns.SyncStatus()
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(label, 1, 1, 1)
  if long and long ~= "" then GameTooltip:AddLine(long, 0.8, 0.8, 0.8, true) end
  GameTooltip:AddLine("Addon version " .. ns.VERSION, 0.5, 0.5, 0.5)
  GameTooltip:Show()
end)
syncHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
syncHover:SetScript("OnMouseUp", function() ns.FullSync() end)
local sfline = Tex(side, "BORDER", C.line)
sfline:SetPoint("BOTTOMLEFT", 6, 52); sfline:SetPoint("BOTTOMRIGHT", -6, 52); sfline:SetHeight(1)

-- Content area ----------------------------------------------------------------
local content = CreateFrame("Frame", nil, UI)
content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
content:SetPoint("BOTTOMRIGHT", -1, 1)

local toolbar = CreateFrame("Frame", nil, content)
toolbar:SetPoint("TOPLEFT"); toolbar:SetPoint("TOPRIGHT")
toolbar:SetHeight(TOOLBAR_H)
local tline = Tex(toolbar, "BORDER", C.line, 0.6)
tline:SetPoint("BOTTOMLEFT"); tline:SetPoint("BOTTOMRIGHT"); tline:SetHeight(1)

local footer = CreateFrame("Frame", nil, content)
footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER_H)
local fline = Tex(footer, "BORDER", C.line, 0.6)
fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
UI.footerText = Font(footer, 11, C.muted)
UI.footerText:SetPoint("LEFT", 10, 0)
UI.footerText:SetPoint("RIGHT", -22, 0)

local composer = CreateFrame("Frame", nil, content)
composer:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
composer:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
composer:SetHeight(COMPOSER_H)
local cline = Tex(composer, "BORDER", C.line, 0.6)
cline:SetPoint("TOPLEFT"); cline:SetPoint("TOPRIGHT"); cline:SetHeight(1)

local listArea = CreateFrame("Frame", nil, content)
listArea:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT")
listArea:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT")

local scroll = CreateFrame("ScrollFrame", nil, listArea)
scroll:SetPoint("TOPLEFT")
scroll:SetPoint("BOTTOMRIGHT", -6, 0)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(400, 1)
scroll:SetScrollChild(child)
scroll:EnableMouseWheel(true)
local thumb = Tex(listArea, "ARTWORK", C.line)
thumb:SetWidth(3)

local function UpdateThumb()
  local viewH, total = scroll:GetHeight() or 0, child:GetHeight() or 0
  if total <= viewH + 1 or viewH <= 0 then thumb:Hide() return end
  local h = math.max(20, viewH * viewH / total)
  local off = (scroll:GetVerticalScroll() or 0) / (total - viewH) * (viewH - h)
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -1, -off)
  thumb:SetHeight(h)
  thumb:Show()
end

scroll:SetScript("OnMouseWheel", function(self, delta)
  local maxV = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
  local v = math.min(maxV, math.max(0, (self:GetVerticalScroll() or 0) - delta * ROW_H * 2))
  self:SetVerticalScroll(v)
  UpdateThumb()
end)

UI.empty = Font(listArea, 12, C.muted)
UI.empty:SetPoint("TOP", 0, -40)
UI.empty:SetJustifyH("CENTER")
UI.empty:SetWordWrap(true)

-- Resize grip
local grip = CreateFrame("Button", nil, UI)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() UI:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() UI:StopMovingOrSizing(); UI:SaveLayout(); UI:Refresh() end)

UI:SetScript("OnSizeChanged", function() if UI:IsShown() then ns.Debounce("uiresize", 0.05, function() UI:Refresh() end) end end)

function UI:SaveLayout()
  if not ns.db then return end
  local point, _, rel, x, y = self:GetPoint()
  ns.db.settings.window = { w = self:GetWidth(), h = self:GetHeight(), point = point, rel = rel, x = x, y = y }
end

function UI:RestoreLayout()
  local w = ns.db and ns.db.settings.window
  if w and w.w then
    self:SetSize(w.w, w.h)
    self:ClearAllPoints()
    self:SetPoint(w.point or "CENTER", UIParent, w.rel or w.point or "CENTER", w.x or 0, w.y or 0)
  end
  if ns.db and ns.db.settings.scale then self:SetScale(ns.db.settings.scale) end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
UI.rows = {}

local function RowEnter(self)
  self.hl:Show()
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if d.item then
    GameTooltip:SetHyperlink("item:" .. d.item)
  else
    GameTooltip:SetText(d.title or "", 1, 1, 1)
  end
  if d.tip then
    for i = 1, table.maxn(d.tip) do
      if d.tip[i] then GameTooltip:AddLine(d.tip[i], 0.85, 0.86, 0.88, true) end
    end
  end
  if d.onClick then GameTooltip:AddLine("Click for details", C.gold[1], C.gold[2], C.gold[3]) end
  GameTooltip:Show()
end

local function RowLeave(self)
  if UI.selected ~= self.data or not self.data then self.hl:Hide() end
  GameTooltip_Hide()
end

local function RowClick(self)
  local d = self.data
  if not d then return end
  if d.item and IsModifiedClick("CHATLINK") then
    local _, link = GetItemInfo(d.item)
    if link then ChatEdit_InsertLink(link) end
    return
  end
  if d.onClick then
    UI.selected = d
    d.onClick(d)
    UI:Refresh()
  end
end

local function GetRow(i)
  local r = UI.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, child)
  r:SetHeight(ROW_H)
  r.hl = Tex(r, "BACKGROUND", C.hover)
  r.hl:SetAllPoints()
  r.hl:Hide()
  local sep = Tex(r, "BORDER", C.line, 0.45)
  sep:SetPoint("BOTTOMLEFT", 8, 0); sep:SetPoint("BOTTOMRIGHT", -8, 0); sep:SetHeight(1)

  r.qb = Tex(r, "BORDER", C.white)
  r.qb:SetSize(30, 30)
  r.qb:SetPoint("LEFT", 10, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("CENTER", r.qb, "CENTER")
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.dot = Tex(r, "ARTWORK", C.green)
  r.dot:SetSize(8, 8)
  r.dot:SetPoint("LEFT", 21, 0)

  r.title = Font(r, 12, C.text)
  r.title:SetPoint("TOPLEFT", 48, -5)
  r.sub = Font(r, 11, C.muted)
  r.sub:SetPoint("TOPLEFT", 48, -21)

  r.barBg = Tex(r, "ARTWORK", C.panel2)
  r.barBg:SetHeight(5)
  r.barBg:SetPoint("TOPLEFT", 48, -24)
  r.bar = Tex(r, "OVERLAY", C.green)
  r.bar:SetHeight(5)
  r.bar:SetPoint("TOPLEFT", r.barBg, "TOPLEFT")

  r.b2 = IconBtn(r, nil, nil, 22)
  r.b2:SetPoint("RIGHT", -10, 0)
  r.b1 = IconBtn(r, nil, nil, 22)
  r.b1:SetPoint("RIGHT", r.b2, "LEFT", -4, 0)

  r.pill = CreateFrame("Frame", nil, r)
  r.pill:SetHeight(16)
  r.pill.bg = Tex(r.pill, "BACKGROUND", C.panel2)
  r.pill.bg:SetAllPoints()
  r.pill.text = Font(r.pill, 10, C.text)
  r.pill.text:SetPoint("CENTER")
  r.pill.text:SetJustifyH("CENTER")

  r.right = Font(r, 12, C.text)
  r.right:SetJustifyH("RIGHT")

  r:SetScript("OnEnter", RowEnter)
  r:SetScript("OnLeave", RowLeave)
  r:SetScript("OnClick", RowClick)
  UI.rows[i] = r
  return r
end

local function ShowRows(data, width)
  local inner = width - 20
  for i, d in ipairs(data) do
    local r = GetRow(i)
    r.data = d
    r:SetWidth(width)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    -- icon / quality border / online dot
    if d.icon then
      r.icon:SetTexture(d.icon); r.icon:Show()
      local q = d.qcolor or C.line
      r.qb:SetColorTexture(q[1], q[2], q[3], 1); r.qb:Show()
    else
      r.icon:Hide(); r.qb:Hide()
    end
    if d.dot ~= nil then
      local c = d.dot and C.green or C.panel2
      r.dot:SetColorTexture(c[1], c[2], c[3], 1); r.dot:Show()
    else
      r.dot:Hide()
    end

    -- action buttons
    local rightEdge = 10
    for _, key in ipairs({ "b2", "b1" }) do
      local spec = d.buttons and d.buttons[(key == "b2") and 1 or 2]
      local b = r[key]
      if spec then
        b.icon:SetTexture(spec[1]); b.tip = spec[2]
        b:SetScript("OnClick", spec[3]); b:Show()
        rightEdge = rightEdge + 26
      else
        b:Hide()
      end
    end
    -- reposition b1 if b2 hidden
    r.b1:ClearAllPoints()
    if r.b2:IsShown() then r.b1:SetPoint("RIGHT", r.b2, "LEFT", -4, 0) else r.b1:SetPoint("RIGHT", -10, 0) end

    -- pill
    if d.pill then
      local p = PILL[d.pill] or { d.pill, C.panel2, C.text }
      r.pill.text:SetText(p[1])
      SetColor(r.pill.text, p[3])
      r.pill.bg:SetColorTexture(p[2][1], p[2][2], p[2][3], 1)
      r.pill:SetWidth((r.pill.text:GetStringWidth() or 40) + 14)
      r.pill:ClearAllPoints()
      r.pill:SetPoint("RIGHT", r, "RIGHT", -rightEdge - 4, 0)
      r.pill:Show()
      rightEdge = rightEdge + r.pill:GetWidth() + 10
    else
      r.pill:Hide()
    end

    -- right-hand value
    r.right:ClearAllPoints()
    if d.right then
      r.right:SetText(d.right)
      SetColor(r.right, d.rightColor or C.text)
      r.right:SetPoint("RIGHT", r, "RIGHT", -rightEdge - 4, d.frac and 4 or 0)
      r.right:Show()
      rightEdge = rightEdge + (r.right:GetStringWidth() or 40) + 12
    else
      r.right:Hide()
    end

    local textW = math.max(60, width - 48 - rightEdge - 6)
    r.title:SetWidth(textW)
    r.title:SetText(d.title or "")
    SetColor(r.title, d.titleColor or C.text)
    r.title:ClearAllPoints()
    if d.sub or d.frac then r.title:SetPoint("TOPLEFT", 48, -5) else r.title:SetPoint("LEFT", 48, 0) end

    if d.frac then
      r.sub:Hide()
      local w = math.max(40, width - 48 - rightEdge + (d.right and 0 or 0) - 6)
      r.barBg:SetWidth(w); r.barBg:Show()
      local c = d.barColor or C.green
      r.bar:SetColorTexture(c[1], c[2], c[3], 1)
      r.bar:SetWidth(math.max(1, w * math.min(1, d.frac)))
      r.bar:SetShown(d.frac > 0)
    else
      r.barBg:Hide(); r.bar:Hide()
      if d.sub then r.sub:SetWidth(textW); r.sub:SetText(d.sub); r.sub:Show() else r.sub:Hide() end
    end

    r.hl:SetShown(UI.selected ~= nil and UI.selected.key ~= nil and UI.selected.key == d.key)
    r:Show()
  end
  for i = #data + 1, #UI.rows do UI.rows[i]:Hide(); UI.rows[i].data = nil end
  child:SetHeight(math.max(1, #data * ROW_H))
end

---------------------------------------------------------------------------
-- Details panel (opens on row click)
---------------------------------------------------------------------------
local det = CreateFrame("Frame", nil, content)
det:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, 0)
det:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
det:SetWidth(DETAILS_W)
det:SetFrameLevel(content:GetFrameLevel() + 20)
det:EnableMouse(true)
Tex(det, "BACKGROUND", C.panel):SetAllPoints()
local dline = Tex(det, "BORDER", C.line)
dline:SetPoint("TOPLEFT"); dline:SetPoint("BOTTOMLEFT"); dline:SetWidth(1)
det:Hide()
UI.details = det

det.close = IconBtn(det, "Interface\\Buttons\\UI-StopButton", "Close details", 20)
det.close:SetPoint("TOPRIGHT", -8, -8)
det.close:SetFrameLevel(det:GetFrameLevel() + 5)
det.close:SetScript("OnClick", function() UI:CloseDetails() end)

-- Everything below the close button scrolls, so nothing is cut off on small windows.
det.scroll = CreateFrame("ScrollFrame", nil, det)
det.scroll:SetPoint("TOPLEFT", 1, 0)
det.scroll:SetPoint("BOTTOMRIGHT", -4, 0)
det.body = CreateFrame("Frame", nil, det.scroll)
det.body:SetSize(DETAILS_W - 6, 1)
det.scroll:SetScrollChild(det.body)
det.scroll:EnableMouseWheel(true)
det.thumb = Tex(det, "ARTWORK", C.line)
det.thumb:SetWidth(3)
function det:UpdateScroll()
  local viewH, total = self.scroll:GetHeight() or 0, self.body:GetHeight() or 0
  local maxV = math.max(0, total - viewH)
  if (self.scroll:GetVerticalScroll() or 0) > maxV then self.scroll:SetVerticalScroll(maxV) end
  if maxV <= 1 or viewH <= 0 then self.thumb:Hide() return end
  local h = math.max(20, viewH * viewH / total)
  local off = (self.scroll:GetVerticalScroll() or 0) / maxV * (viewH - h)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -off)
  self.thumb:SetHeight(h)
  self.thumb:Show()
end
det.scroll:SetScript("OnMouseWheel", function(self, delta)
  local maxV = math.max(0, (det.body:GetHeight() or 0) - (self:GetHeight() or 0))
  self:SetVerticalScroll(math.min(maxV, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
  det:UpdateScroll()
end)

det.icon = det.body:CreateTexture(nil, "ARTWORK")
det.icon:SetSize(32, 32)
det.icon:SetPoint("TOPLEFT", 12, -10)
det.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
det.title = Font(det.body, 13, C.white)
det.title:SetPoint("TOPLEFT", 52, -12)
det.title:SetWidth(DETAILS_W - 52 - 36)
det.subtitle = Font(det.body, 11, C.muted)
det.subtitle:SetPoint("TOPLEFT", 52, -30)
det.subtitle:SetWidth(DETAILS_W - 62)

det.pools = { text = {}, box = {}, btn = {}, label = {} }
det.used = { text = 0, box = 0, btn = 0, label = 0 }

function det:Reset(icon, quality, titleText, subtitle)
  for k in pairs(self.used) do
    for i = 1, #self.pools[k] do self.pools[k][i]:Hide() end
    self.used[k] = 0
  end
  self.y = -52
  self.scroll:SetVerticalScroll(0)
  if icon then self.icon:SetTexture(icon); self.icon:Show() else self.icon:Hide() end
  local q = quality and QColor(quality) or C.white
  self.title:SetText(titleText or "")
  SetColor(self.title, q)
  self.subtitle:SetText(subtitle or "")
end

function det:Take(kind, make)
  self.used[kind] = self.used[kind] + 1
  local w = self.pools[kind][self.used[kind]]
  if not w then w = make(); self.pools[kind][self.used[kind]] = w end
  w:ClearAllPoints()
  w:Show()
  return w
end

function det:Text(str, color)
  local fs = self:Take("text", function() local f = Font(self.body, 11, C.text); f:SetWordWrap(true); return f end)
  fs:SetPoint("TOPLEFT", 12, self.y)
  fs:SetWidth(DETAILS_W - 24)
  fs:SetText(str)
  SetColor(fs, color or C.text)
  self.y = self.y - math.max(14, (fs:GetStringHeight() or 14)) - 6
  return fs
end

function det:Field(label, value, width, numeric)
  local l = self:Take("label", function() return Font(self.body, 11, C.muted) end)
  l:SetPoint("TOPLEFT", 12, self.y - 4)
  l:SetText(label)
  local b = self:Take("box", function() return Box(self.body, 100, "") end)
  b:SetNumeric(numeric == true)
  b:SetWidth(math.min(width or 150, DETAILS_W - 90 - 14))
  b:SetPoint("TOPLEFT", 90, self.y)
  b:SetText(value or "")
  b.onChange, b.onEnter = nil, nil
  self.y = self.y - 28
  return b
end

function det:Buttons(specs)
  local x = 12
  for _, s in ipairs(specs) do
    local b = self:Take("btn", function() return Btn(self.body, "", 80, 22) end)
    b.style = s.accent and "accent" or nil
    b:SetOn(false)
    b:SetLabel(s[1])
    local w = math.max(56, (b.text:GetStringWidth() or 40) + 18)
    b:SetWidth(w)
    if x + w > DETAILS_W - 16 then x = 12; self.y = self.y - 28 end
    b:SetPoint("TOPLEFT", x, self.y)
    b.tip = s.tip
    b:SetScript("OnClick", s[2])
    x = x + w + 6
  end
  self.y = self.y - 30
end

function det:Gap(n) self.y = self.y - (n or 6) end

-- Call after filling: sizes the scrolling body to what was added.
function det:Finish()
  self.body:SetHeight(math.max(1, -self.y + 8))
  self:UpdateScroll()
end

function UI:CloseDetails()
  det:Hide()
  det.kind, det.key = nil, nil
  self.selected = nil
  self:Layout()
  self:Refresh()
end

function UI:OpenDetails(kind, key)
  det.kind, det.key = kind, key
  det:Show()
  self:Layout()
  self:FillDetails()
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
UI.state = {
  requests = { filter = "open", mine = false, sort = "new" },
  needs = { filter = "all" },
  bank = { cat = nil },
  crafters = { filter = "all", prof = nil },
  recipes = { prof = nil, online = false, designated = false, crafter = nil, skillup = false },
  roster = { filter = "all", role = nil, review = nil },
  sync = { filter = "guild" },
}
local SORTS = { { "new", "Newest" }, { "old", "Oldest" }, { "item", "Item" }, { "who", "Requester" } }
local REQ_FILTERS = { { "open", "Open" }, { "pending", "Pending" }, { "approved", "Approved / accepted" }, { "filled", "Filled / made" },
  { "rejected", "Rejected / declined" }, { "all", "All, including tidied" } }

local function Q() return (UI.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
local function Match(q, ...)
  if q == "" then return true end
  for i = 1, select("#", ...) do
    local s = select(i, ...)
    if s and tostring(s):lower():find(q, 1, true) then return true end
  end
  return false
end

local Views = {}
local ORDER = { "news", "needs", "shopping", "bank", "requests", "donations", "roster", "crafters", "recipes", "projects", "onboarding", "sync", "officer" }
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"   -- marks designated guild crafters

-- A toolbar button that opens a dropdown menu.
--   items() -> { {label, value, right} }, current() -> value, set(value)
local function DropChip(bar, w, tip, items, current, set, side)
  local b
  b = bar:Add(Btn(bar, "", w, 22), side or "left", function()
    OpenMenu(b, items(), current(), function(v) set(v); UI:Refresh() end)
  end, tip)
  b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -20, 0); b.text:SetJustifyH("LEFT")
  b.arrow = b:CreateTexture(nil, "ARTWORK")
  b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  b.arrow:SetSize(12, 12); b.arrow:SetPoint("RIGHT", -5, -2)
  b.arrow:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
  return b
end

-- Needs ---------------------------------------------------------------------
Views.needs = {
  label = "Needs", icon = "Interface\\Icons\\INV_Misc_Note_01",
  chips = { { "all", "All" }, { "low", "Low" }, { "goal", "Goals" } },
  composer = "need",
  count = function()
    local n = 0
    for _, x in ipairs(ns.OpenNeeds()) do if x.critical then n = n + 1 end end
    return n, C.redBg, C.red
  end,
  rows = function(g, q)
    local st, out = UI.state.needs, {}
    for _, n in ipairs(ns.OpenNeeds()) do
      local name = ns.ItemName(n.id, true)
      if (st.filter == "all" or (st.filter == "low" and n.critical) or (st.filter == "goal" and n.kind == "goal")) and Match(q, name) then
        local color = n.frac < 0.5 and C.red or (n.frac < 1 and C.gold or C.green)
        local carry = ns.ItemCount(n.id)
        local id = n.id
        out[#out + 1] = {
          key = "need:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)),
          title = name .. "  |cff7e8590" .. ((n.kind == "goal") and "goal" or "restock") .. "|r"
            .. (carry > 0 and ("  |cff4ade80you carry " .. carry .. "|r") or ""),
          titleColor = QColor(Quality(id)),
          right = n.have .. " / " .. n.target, rightColor = color, frac = n.frac, barColor = color,
          tip = { " ", "Still needed: " .. n.rem, "Mail to: " .. ns.BankAltNames() },
          onClick = function() UI:OpenDetails("need", id) end,
        }
      end
    end
    return out
  end,
  footer = function() return "Mail donations to " .. ns.BankAltNames() .. ". Red means under half stocked." end,
  empty = "No needs yet. Officers add them below.",
}

-- Shopping ------------------------------------------------------------------
Views.shopping = {
  label = "Shopping", icon = "Interface\\Icons\\INV_Misc_Coin_02",
  count = function() return #ns.ShoppingList(), C.panel2, C.muted end,
  tools = function(bar)
    bar:Add(Btn(bar, "Send to Auctionator", 140, 22, "accent"), "right", function() ns.ExportAuctionator() end,
      "Save this list as the \"" .. ns.SHOPPING_LIST_NAME .. "\" shopping list in Auctionator, with quantities.")
  end,
  rows = function(g, q)
    local out = {}
    for _, r in ipairs(ns.ShoppingList()) do
      local name = ns.ItemName(r.id, true)
      if Match(q, name) then
        local id = r.id
        out[#out + 1] = {
          key = "item:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)), titleColor = QColor(Quality(id)),
          title = name, sub = "need " .. r.need .. "  ·  approved requests " .. r.req .. "  ·  have " .. r.have,
          right = "buy " .. r.buy, rightColor = C.gold,
          onClick = function() UI:OpenDetails("item", id) end,
        }
      end
    end
    return out
  end,
  footer = function() return ns.HasAuctionator() and "Shortfalls plus approved requests the bank can't cover." or "Install Auctionator to send this list to the auction house." end,
  empty = "Nothing to buy. Every need is stocked and every approved request is covered.",
}

-- Bank ----------------------------------------------------------------------
Views.bank = {
  label = "Bank", icon = "Interface\\Icons\\INV_Misc_Bag_10",
  tools = function(bar)
    UI.bankCatChip = DropChip(bar, 150, "Show one kind of item", function()
      local counts = {}
      for _, s in pairs((ns.G() or {}).bank or {}) do
        if not s.retired then
          for id in pairs(s.items or {}) do local c = ns.ItemCategory(id); counts[c] = (counts[c] or 0) + 1 end
        end
      end
      local items = { { label = "All categories", value = false } }
      for _, c in ipairs(ns.CATEGORIES) do
        if counts[c] then items[#items + 1] = { label = c, value = c, right = tostring(counts[c]) } end
      end
      return items
    end, function() return UI.state.bank.cat or false end, function(v) UI.state.bank.cat = v or nil end)
  end,
  rows = function(g, q)
    local totals, holders = {}, {}
    for alt, s in pairs(g.bank) do
      if not s.retired then
        for id, c in pairs(type(s.items) == "table" and s.items or {}) do
          id, c = tonumber(id), tonumber(c)
          if id and c then
            totals[id] = (totals[id] or 0) + c
            holders[id] = holders[id] and (holders[id] .. ", " .. tostring(alt)) or tostring(alt)
          end
        end
      end
    end
    -- grouped by category, each under a header, most plentiful first
    local groups, order = {}, {}
    for i, c in ipairs(ns.CATEGORIES) do order[c] = i end
    local only = UI.state.bank.cat
    for id, c in pairs(totals) do
      -- one odd item mustn't take the whole page down
      local ok, err = ns.SafeCall(function()
        local name = tostring(ns.ItemName(id, true))
        local okc, cat = pcall(ns.ItemCategory, id)
        cat = (okc and type(cat) == "string") and cat or "Other"
        if (not only or cat == only) and Match(q, name, holders[id], cat) then
          groups[cat] = groups[cat] or {}
          table.insert(groups[cat], {
            key = "item:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)), titleColor = QColor(Quality(id)),
            title = name, sub = holders[id], right = tostring(c), count = c, sort = name,
            onClick = function() UI:OpenDetails("item", id) end,
          })
        end
      end)
      if not ok and not UI.bankItemErr then
        UI.bankItemErr = true
        ns.Print("Skipped bank item " .. tostring(id) .. " (" .. tostring(err.where) .. "): " .. err.plain .. "  |cff9aa1ab" .. err.raw .. "|r")
      end
    end
    local cats = {}
    for cat in pairs(groups) do cats[#cats + 1] = cat end
    table.sort(cats, function(a, b) return (order[a] or 99) < (order[b] or 99) end)
    local out = {}
    for _, cat in ipairs(cats) do
      local list = groups[cat]
      table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.sort < b.sort end)
      local total = 0
      for _, r in ipairs(list) do total = total + r.count end
      out[#out + 1] = { key = "cat:" .. cat, title = "|cfff2c14e" .. cat .. "|r",
        sub = #list .. (#list == 1 and " kind of item" or " kinds of items"), right = tostring(total) }
      for _, r in ipairs(list) do out[#out + 1] = r end
    end
    return out
  end,
  footer = function(g)
    local parts = {}
    for alt, s in pairs(g.bank) do
      if not s.retired then parts[#parts + 1] = alt .. " " .. Money(s.money) .. " (" .. Ago(s.bankTime or s.v) .. ")" end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "   ") or "No bank yet. On the bank character: /epu bankalt on"
  end,
  empty = "Nothing recorded yet. The bank character needs the addon and should open its bank once.",
}

-- Requests --------------------------------------------------------------------
local function RequestMatchesFilter(r, f)
  if f == "all" then return true end
  if r.archived then return false end
  if f == "open" then return ns.IsActiveRequest(r) end
  if f == "pending" then return r.status == "pending" or r.status == "open" end
  return r.status == f
end

Views.requests = {
  label = "Requests", icon = "Interface\\Icons\\INV_Letter_15",
  composer = "request",
  count = function(g)
    local n = 0
    local officer = ns.IsTrusted(ns.me)
    for _, r in pairs(g.requests) do
      local pending = (r.status == "pending" or r.status == "open")
      if r.crafter and ns.IAmCrafter(r) and (pending or r.status == "approved") then n = n + 1     -- work for me to do
      elseif officer and pending and not r.crafter then n = n + 1
      elseif not officer and ns.IsActiveRequest(r) and ns.MainOf(r.who) == ns.MainOf(ns.me) then n = n + 1 end
    end
    return n, C.goldBg, C.gold
  end,
  tools = function(bar)
    UI.statusChip = DropChip(bar, 120, "Which requests to show", function()
      local g, counts = ns.G(), {}
      for _, r in pairs((g and g.requests) or {}) do
        for _, f in ipairs(REQ_FILTERS) do
          if RequestMatchesFilter(r, f[1]) then counts[f[1]] = (counts[f[1]] or 0) + 1 end
        end
      end
      local items = {}
      for _, f in ipairs(REQ_FILTERS) do items[#items + 1] = { label = f[2], value = f[1], right = tostring(counts[f[1]] or 0) } end
      return items
    end, function() return UI.state.requests.filter end, function(v) UI.state.requests.filter = v end)
    UI.mineChip = bar:Add(Btn(bar, "Mine", 50, 22), "left", function()
      UI.state.requests.mine = not UI.state.requests.mine
      UI:Refresh()
    end, "Only your requests (and your alts'), plus crafts people asked you to make")
    UI.craftsChip = bar:Add(Btn(bar, "Crafts", 54, 22), "left", function()
      UI.state.requests.crafts = not UI.state.requests.crafts
      UI:Refresh()
    end, "Only craft requests (asked of a crafter, not the bank). Ask for one from the Recipes page.")
    UI.sortChip = DropChip(bar, 112, "Change the order", function()
      local items = {}
      for _, s in ipairs(SORTS) do items[#items + 1] = { label = s[2], value = s[1] } end
      return items
    end, function() return UI.state.requests.sort end, function(v) UI.state.requests.sort = v end, "right")
  end,
  rows = function(g, q)
    local st, officer, out = UI.state.requests, ns.IsTrusted(ns.me), {}
    local myMain = ns.MainOf(ns.me)
    for rid, r in pairs(g.requests) do
      local name = ns.RequestName(r, true)
      local mineHere = ns.MainOf(r.who) == myMain or ns.IAmCrafter(r)
      if RequestMatchesFilter(r, st.filter) and (not st.mine or mineHere) and (not st.crafts or r.crafter)
        and Match(q, name, r.who, r.to, ns.MainOf(r.who), r.note, r.crafter) then
        local pending = (r.status == "pending" or r.status == "open")
        local parts = { ns.WhoLabel(r.who) }
        if r.crafter then
          parts[#parts + 1] = "|cff6ea8ffcraft by " .. (ns.IAmCrafter(r) and "you" or r.crafter) .. "|r"
          parts[#parts + 1] = ({ me = "they send mats", bank = "bank sends mats", crafter = "crafter's mats" })[r.mats or "me"]
        end
        if r.to and r.to ~= r.who then parts[#parts + 1] = "|cfff2c14e-> " .. r.to .. "|r" end
        parts[#parts + 1] = Ago(r.t)
        if r.via == "discord" then parts[#parts + 1] = "|cff8b9cffDiscord|r" end
        if r.status == "rejected" and r.reason and r.reason ~= "" then parts[#parts + 1] = "|cffff6b6b" .. r.reason .. "|r"
        elseif r.note and r.note ~= "" then parts[#parts + 1] = "\"" .. r.note .. "\"" end
        local buttons
        local crafterHere = r.crafter and r.crafter == ns.me
        if crafterHere and pending then
          buttons = {
            { "Interface\\RaidFrame\\ReadyCheck-NotReady", "Decline (open details to add a reason)", function() ns.EditRequest(rid, { status = "rejected" }) end },
            { "Interface\\RaidFrame\\ReadyCheck-Ready", "Accept: you'll make it", function() ns.EditRequest(rid, { status = "approved" }) end },
          }
        elseif crafterHere and r.status == "approved" then
          buttons = { { "Interface\\RaidFrame\\ReadyCheck-Ready", "Made it (mailing it to them marks this automatically)", function() ns.EditRequest(rid, { status = "filled" }) end } }
          if r.item then table.insert(buttons, 1, { "Interface\\Icons\\INV_Letter_15", "Mail it (open a mailbox first)", function() ns.MailRequest(rid) end }) end
        elseif r.crafter then
          buttons = nil   -- officers and the requester use the details panel
        elseif officer and pending then
          buttons = {
            { "Interface\\RaidFrame\\ReadyCheck-NotReady", "Reject (open details to add a reason)", function() ns.EditRequest(rid, { status = "rejected" }) end },
            { "Interface\\RaidFrame\\ReadyCheck-Ready", "Approve", function() ns.EditRequest(rid, { status = "approved" }) end },
          }
        elseif officer and r.status == "approved" then
          buttons = { { "Interface\\Icons\\INV_Letter_15", "Mail it (open a mailbox first)", function() ns.MailRequest(rid) end } }
        end
        out[#out + 1] = {
          key = "req:" .. rid, item = r.item,
          icon = r.item and ns.ItemIcon(r.item) or "Interface\\Icons\\Trade_Engraving", qcolor = QColor(Quality(r.item)),
          title = name .. " |cff9aa1abx" .. r.qty .. "|r", titleColor = QColor(Quality(r.item)),
          sub = table.concat(parts, "  ·  "), pill = PillKey(r), buttons = buttons,
          t = r.t, who = r.who, name = name,
          onClick = function() UI:OpenDetails("request", rid) end,
        }
      end
    end
    local s = st.sort
    table.sort(out, function(a, b)
      if s == "old" then return a.t < b.t end
      if s == "item" then if a.name ~= b.name then return a.name < b.name end return a.t > b.t end
      if s == "who" then if a.who ~= b.who then return a.who < b.who end return a.t > b.t end
      return a.t > b.t
    end)
    return out
  end,
  footer = function()
    if ns.IsTrusted(ns.me) then return "Mailing an approved item to the requester marks it filled automatically." end
    return "Ask for something below. An officer approves it and mails it to you."
  end,
  empty = "No requests match. Try another filter, or ask for something below.",
}

-- Donations -----------------------------------------------------------------
Views.donations = {
  label = "Donations", icon = "Interface\\Icons\\INV_Misc_Gift_01",
  rows = function(g, q)
    local list = {}
    for id, d in pairs(g.donations) do list[#list + 1] = { id = id, d = d } end
    table.sort(list, function(a, b) return (a.d.t or 0) > (b.d.t or 0) end)
    local out = {}
    for _, e in ipairs(list) do
      local d, id = e.d, e.id
      local name = d.item and ns.ItemName(d.item, true) or nil
      if Match(q, name, d.who, ns.MainOf(d.who or "")) then
        local void = d.void and "  |cffff6b6b(voided)|r" or ""
        out[#out + 1] = {
          key = "don:" .. id, item = d.item,
          icon = d.item and ns.ItemIcon(d.item) or "Interface\\Icons\\INV_Misc_Coin_01",
          qcolor = d.item and QColor(Quality(d.item)) or C.gold,
          title = (d.item and (name .. " |cff9aa1abx" .. (d.n or 1) .. "|r") or Money(d.money)) .. void,
          titleColor = d.void and C.muted or (d.item and QColor(Quality(d.item)) or C.white),
          sub = ns.WhoLabel(d.who or "?") .. "  ·  to " .. tostring(d.to) .. "  ·  " .. Ago(d.t),
          onClick = function() UI:OpenDetails("donation", id) end,
        }
      end
    end
    return out
  end,
  footer = function(g)
    local cutoff, counts = ns.Now() - 30 * 86400, {}
    for _, d in pairs(g.donations) do
      if not d.void and (d.t or 0) > cutoff and d.who then
        local p = ns.MainOf(d.who)
        counts[p] = (counts[p] or 0) + 1
      end
    end
    local top = {}
    for who, n in pairs(counts) do top[#top + 1] = { who, n } end
    table.sort(top, function(a, b) return a[2] > b[2] end)
    local names = {}
    for i = 1, math.min(4, #top) do names[#names + 1] = top[i][1] .. " (" .. top[i][2] .. ")" end
    return #names > 0 and ("Top donors, 30 days: " .. table.concat(names, ", ")) or "Mail or trades to a bank character are logged automatically."
  end,
  empty = "No donations logged yet.",
}

-- Sync ------------------------------------------------------------------------
local SYNC_KIND = { asked = "Asked", sent = "Answered", relayed = "Passed on", officer = "Synced", relay = "Unconfirmed",
  dropped = "Cleaned up", checkin = "Check-in", behind = "Behind" }
Views.sync = {
  label = "Sync", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", stateKey = "sync",
  chips = { { "guild", "Members" }, { "all", "Whole roster" }, { "mine", "This PC" } },
  tools = function(bar)
    bar:Add(Btn(bar, "Sync now", 80, 22, "accent"), "right", function() ns.FullSync() end,
      "Ask online officers for everything again (it also happens by itself)")
  end,
  rows = function(g, q)
    local st, out = UI.state.sync, {}
    if st.filter == "mine" then
      for i, e in ipairs(g.syncLog or {}) do
        if Match(q, e.text, e.who) then
          out[#out + 1] = {
            key = "synclog:" .. i, title = e.text or "?", titleColor = (e.kind == "relay" or e.kind == "behind") and C.gold or C.text,
            sub = (SYNC_KIND[e.kind] or e.kind or "") .. "  ·  " .. Ago(e.t),
          }
        end
      end
      return out
    end
    local reports = {}
    for _, r in ipairs(ns.SyncReports()) do reports[r.name] = r end
    if st.filter == "all" then
      for name in pairs(ns.roster) do reports[name] = reports[name] or { name = name, none = true } end
    end
    local list = {}
    for _, r in pairs(reports) do list[#list + 1] = r end
    table.sort(list, function(a, b)
      if (a.none or false) ~= (b.none or false) then return not a.none end
      return math.max(a.t or 0, a.asked or 0) > math.max(b.t or 0, b.asked or 0)
    end)
    local newest = ns.newestVersion or ns.VERSION
    for _, r in ipairs(list) do
      if Match(q, r.name, r.from, r.what, r.ver) then
        local sub, pill
        if r.none then
          sub = "No addon seen yet"
        elseif r.t then
          sub = ((r.kind == "relay") and "Unconfirmed copy from " or "Synced from ") .. tostring(r.from or "?") .. " " .. Ago(r.t)
            .. "  ·  " .. tostring(r.what or "")
          if r.kind == "relay" then pill = "sync_unconf" end
          if r.asked and r.asked > r.t + 60 then sub = "Asked " .. Ago(r.asked) .. ", no answer yet  ·  last: " .. sub; pill = "sync_wait" end
        elseif r.asked then
          sub = "Asked " .. Ago(r.asked) .. ", hasn't synced yet"
          pill = "sync_wait"
        else
          sub = r.from or "Waiting for guild data"
        end
        local old = r.ver and ns.VersionNumber(r.ver) < ns.VersionNumber(newest)
        out[#out + 1] = {
          key = "sync:" .. r.name, dot = ns.roster[r.name] ~= nil and ns.roster[r.name].online == true,
          title = ns.WhoLabel and ns.WhoLabel(r.name) or r.name, titleColor = r.none and C.muted or C.text,
          sub = sub, pill = pill,
          right = r.ver and ("v" .. r.ver) or nil, rightColor = old and C.red or C.muted,
          tip = old and { " ", "Older addon version: they should update in the CurseForge app." } or nil,
        }
      end
    end
    return out
  end,
  footer = function(g)
    if UI.state.sync.filter == "mine" then return "What this PC's addon sent and received. Kept on this PC only." end
    local n, day, old = 0, 0, 0
    local newest = ns.newestVersion or ns.VERSION
    for _, r in ipairs(ns.SyncReports()) do
      n = n + 1
      if r.t and ns.Now() - r.t < 86400 then day = day + 1 end
      if r.ver and ns.VersionNumber(r.ver) < ns.VersionNumber(newest) then old = old + 1 end
    end
    return n .. " with the addon  ·  " .. day .. " synced today" .. (old > 0 and ("  ·  |cffff6b6b" .. old .. " on an older version|r") or "")
  end,
  empty = "Nothing yet. Members show up here as their addon syncs.",
}

-- Crafters ------------------------------------------------------------------
Views.crafters = {
  label = "Crafters", icon = "Interface\\Icons\\Trade_BlackSmithing",
  chips = { { "all", "All" }, { "online", "Online" }, { "designated", "Guild crafters" } },
  tools = function(bar)
    UI.crafterProfChip = DropChip(bar, 120, "Pick a profession", function()
      local counts = {}
      for _, c in pairs((ns.G() or {}).crafters or {}) do
        for p in pairs(c.profs or {}) do counts[p] = (counts[p] or 0) + 1 end
      end
      local list = {}
      for p in pairs(counts) do list[#list + 1] = p end
      table.sort(list)
      local items = { { label = "All professions", value = false } }
      for _, p in ipairs(list) do items[#items + 1] = { label = p, value = p, right = tostring(counts[p]) } end
      return items
    end, function() return UI.state.crafters.prof or false end, function(v) UI.state.crafters.prof = v or nil end)
    bar:Add(Btn(bar, "Who can craft...?", 120, 22), "right", function()
      local text = UI.search:GetText()
      if text == "" then return ns.Print("Type an item name in the search box (or shift-click an item into it), then click Who can craft.") end
      ns.AskWhoCrafts(text)
    end, "Asks online guild members who knows the recipe for what's in the search box.")
  end,
  rows = function(g, q)
    local out = {}
    local res = ns.whoResults
    if res and res.label then
      out[#out + 1] = { key = "who", title = "|cfff2c14eCan craft|r " .. res.label, sub = (#res.list == 0) and "Waiting for answers..." or nil }
      for _, h in ipairs(res.list) do
        out[#out + 1] = { key = "who:" .. h.who .. h.prof, dot = Online(h.who), title = ns.WhoLabel(h.who),
          sub = h.prof, right = tostring(h.rank or "?") }
      end
    end
    local list = {}
    for who, c in pairs(g.crafters) do
      for prof, skill in pairs(c.profs or {}) do
        local f, pf = UI.state.crafters.filter, UI.state.crafters.prof
        local des = ns.IsDesignated(who, prof)
        if (f == "all" or (f == "online" and Online(who)) or (f == "designated" and des))
          and (not pf or pf == prof) and Match(q, who, prof, ns.MainOf(who)) then
          list[#list + 1] = { who = who, prof = prof, skill = skill, lvl = c.lvl, des = des }
        end
      end
    end
    table.sort(list, function(a, b)
      if a.prof ~= b.prof then return a.prof < b.prof end
      if a.des ~= b.des then return a.des end
      if a.skill ~= b.skill then return a.skill > b.skill end
      return a.who < b.who
    end)
    for _, e in ipairs(list) do
      local who = e.who
      local nrec = 0
      local rec = g.recipes[who] and g.recipes[who].profs and g.recipes[who].profs[e.prof]
      if rec then nrec = #(rec.items or {}) + #(rec.spells or {}) end
      local age = rec and (rec.at or g.recipes[who].t)
      out[#out + 1] = {
        key = "craft:" .. who .. e.prof, dot = Online(who),
        title = (e.des and (STAR .. " ") or "") .. ns.WhoLabel(who) .. (e.des and ("  |cfff2c14eguild " .. e.prof:lower() .. "|r") or ""),
        sub = e.prof .. "  ·  level " .. tostring(e.lvl or "?")
          .. (nrec > 0 and ("  ·  " .. nrec .. " recipes, updated " .. Ago(age)) or ""),
        right = tostring(e.skill),
        frac = nil, onClick = function() UI:OpenDetails("crafter", who) end,
      }
    end
    return out
  end,
  footer = function(g)
    local n = 0
    for _ in pairs(g.crafters) do n = n + 1 end
    return n .. " members reporting. Green dot = online now. " .. STAR .. " = guild crafter (officers set these in a crafter's details)."
  end,
  empty = "No profession data yet. It fills in as members with the addon log in.",
}

-- Recipes ---------------------------------------------------------------------
local function RecipeProfs()
  local set, list = {}, {}
  for _, e in ipairs(ns.RecipeIndex()) do
    for _, c in ipairs(e.crafters) do
      if not set[c.prof] then set[c.prof] = true; list[#list + 1] = c.prof end
    end
  end
  table.sort(list)
  return list
end

local MAX_LIST = 250   -- long lists: show the first 250 and ask people to search

Views.recipes = {
  label = "Recipes", icon = "Interface\\Icons\\INV_Misc_Book_09",
  tools = function(bar)
    UI.profChip = DropChip(bar, 116, "Pick a profession", function()
      local counts = {}
      for _, e in ipairs(ns.RecipeIndex()) do
        local seen = {}
        for _, c in ipairs(e.crafters) do
          if not seen[c.prof] then seen[c.prof] = true; counts[c.prof] = (counts[c.prof] or 0) + 1 end
        end
      end
      local items = { { label = "All professions", value = false } }
      for _, p in ipairs(RecipeProfs()) do items[#items + 1] = { label = p, value = p, right = tostring(counts[p] or 0) } end
      return items
    end, function() return UI.state.recipes.prof or false end, function(v) UI.state.recipes.prof = v or nil end)
    UI.onlineChip = bar:Add(Btn(bar, "Online", 56, 22), "left", function()
      UI.state.recipes.online = not UI.state.recipes.online; UI:Refresh()
    end, "Only recipes someone online right now can make")
    UI.desChip = bar:Add(Btn(bar, "Guild crafters", 96, 22), "left", function()
      UI.state.recipes.designated = not UI.state.recipes.designated; UI:Refresh()
    end, "Only recipes a designated guild crafter can make")
    UI.skillChip = bar:Add(Btn(bar, "Skill-ups", 68, 22), "left", function()
      UI.state.recipes.skillup = not UI.state.recipes.skillup; UI:Refresh()
    end, "Only recipes that still give someone a skill point. Send these to them so they level up!")
    UI.crafterChip = bar:Add(Btn(bar, "", 84, 22), "right", function()
      UI.state.recipes.crafter = nil; UI:Refresh()
    end, "Click to show everyone's recipes again")
  end,
  rows = function(g, q)
    local st, out = UI.state.recipes, {}
    for _, e in ipairs(ns.RecipeIndex()) do
      local name = e.item and ns.ItemName(e.item, true) or e.name
      if (not st.prof or e.prof == st.prof) and ns.IsBoP(e.item or 0) ~= true then
        local crafters, anyOnline, anyDes, anySkill, hasCrafter = {}, false, false, false, st.crafter == nil
        for _, c in ipairs(e.crafters) do
          local des = ns.IsDesignated(c.who, c.prof)
          local on = Online(c.who)
          anyOnline = anyOnline or on
          anyDes = anyDes or des
          anySkill = anySkill or (c.diff ~= nil)
          if c.who == st.crafter then hasCrafter = true end
          crafters[#crafters + 1] = { who = c.who, des = des, on = on, diff = c.diff }
        end
        local names = {}
        for _, c in ipairs(crafters) do names[#names + 1] = c.who end
        if hasCrafter and (not st.online or anyOnline) and (not st.designated or anyDes) and (not st.skillup or anySkill)
          and Match(q, name, e.prof, table.concat(names, " ")) then
          table.sort(crafters, function(a, b)
            if a.des ~= b.des then return a.des end
            if a.on ~= b.on then return a.on end
            return a.who < b.who
          end)
          local shown = {}
          for i = 1, math.min(4, #crafters) do
            local c = crafters[i]
            shown[#shown + 1] = (c.des and STAR or "") .. (c.on and ("|cff4ade80" .. c.who .. "|r") or c.who) .. SkillMark(c.diff)
          end
          if #crafters > 4 then shown[#shown + 1] = "+" .. (#crafters - 4) .. " more" end
          local key = e.key
          out[#out + 1] = {
            key = "rec:" .. key, item = e.item,
            icon = e.item and ns.ItemIcon(e.item) or "Interface\\Icons\\Trade_Engraving",
            qcolor = e.item and QColor(Quality(e.item)) or C.line,
            titleColor = e.item and QColor(Quality(e.item)) or C.white,
            title = name, sub = e.prof .. "  ·  " .. table.concat(shown, ", "),
            right = #crafters .. (#crafters == 1 and " crafter" or " crafters"), sort = name,
            onClick = function() UI:OpenDetails("recipe", key) end,
          }
        end
      end
    end
    table.sort(out, function(a, b) return a.sort < b.sort end)
    UI.recipeTotal = #out
    if #out > MAX_LIST then
      for i = #out, MAX_LIST + 1, -1 do out[i] = nil end
    end
    return out
  end,
  footer = function()
    local n = UI.recipeTotal or 0
    if n > MAX_LIST then return "Showing " .. MAX_LIST .. " of " .. n .. " recipes. Search or pick a profession to narrow it down." end
    return n .. " recipes. Green = online, " .. SkillMark("o") .. " = they'd get a skill point making it. BoP items are left out."
  end,
  empty = "No recipes match. Crafters share theirs by opening their profession window once.",
}

-- News: announcements and milestones -------------------------------------
local FEED_ICON = {
  level = "Interface\\Icons\\Spell_Holy_SurgeOfLight", prof = "Interface\\Icons\\INV_Misc_Note_01",
  mount = "Interface\\Icons\\Ability_Mount_RidingHorse", donation = "Interface\\Icons\\INV_Misc_Coin_01",
  join = "Interface\\Icons\\INV_Misc_Head_Human_01",
}
Views.news = {
  label = "News", icon = "Interface\\Icons\\INV_Scroll_03",
  count = function() return #ns.UnreadNews(), C.goldBg, C.gold end,
  tools = function(bar)
    UI.newsBtn = bar:Add(Btn(bar, "New announcement", 130, 22, "accent"), "right", function() UI:OpenDetails("newnews", "new") end,
      "Pops up for everyone the next time they log in, and posts to Discord.")
  end,
  rows = function(g, q)
    local out, read = {}, (ns.cdb and ns.cdb.newsRead) or {}
    local motd = ns.MotdEntry()
    if motd and Match(q, motd.text) then
      out[#out + 1] = {
        key = "news:motd", icon = "Interface\\Icons\\INV_Misc_Note_01", qcolor = C.gold,
        title = "Message of the day", titleColor = C.gold, sub = motd.text:gsub("\n", " "),
        pill = (ns.cdb and ns.cdb.motdRead ~= motd.text) and "news_new" or nil,
        onClick = function() ns.MarkNewsRead("motd"); UI:OpenDetails("motd", "motd") end,
      }
    end
    local info = ns.GuildInfoText()
    if info and Match(q, info) then
      out[#out + 1] = {
        key = "news:info", icon = "Interface\\Icons\\INV_Misc_Book_09", qcolor = C.line,
        title = "Guild info", sub = info:gsub("\n", " "),
        onClick = function() UI:OpenDetails("motd", "info") end,
      }
    end
    for _, e in ipairs(ns.NewsEntries()) do
      if Match(q, e.title, e.text, e.by) then
        out[#out + 1] = {
          key = "news:" .. e.id, icon = "Interface\\Icons\\INV_Letter_15", qcolor = C.gold,
          title = (e.title and e.title ~= "") and e.title or (e.text or ""):sub(1, 60), titleColor = C.gold,
          sub = (e.text or ""):gsub("\n", " ") .. "  ·  " .. tostring(e.by) .. ", " .. Ago(e.t),
          pill = (not read[e.id]) and "news_new" or nil,
          onClick = function() ns.MarkNewsRead(e.id); UI:OpenDetails("news", e.id) end,
        }
      end
    end
    for _, e in ipairs(ns.FeedEntries(30)) do
      if Match(q, e.who, e.text) then
        out[#out + 1] = {
          key = "feed:" .. e.id, icon = FEED_ICON[e.kind] or "Interface\\Icons\\INV_Misc_Note_01", qcolor = C.line,
          title = ns.WhoLabel(e.who or "?") .. " " .. (e.text or ""), sub = Ago(e.t), dot = Online(e.who or ""),
          onClick = function() if e.who and ns.roster[e.who] then UI:OpenDetails("member", e.who) end end,
        }
      end
    end
    return out
  end,
  footer = function() return "Message of the day, announcements (in game and from Discord), then the last 30 days of milestones." end,
  empty = "Nothing yet. Level-ups, first mounts, profession ranks and big donations show up here.",
}

-- Roster --------------------------------------------------------------------
local function ClassColor(file)
  local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
  if c and c.r then return { c.r, c.g, c.b } end
  return C.white
end

Views.roster = {
  label = "Roster", icon = "Interface\\Icons\\INV_Misc_Head_Human_01", stateKey = "roster",
  chips = { { "all", "All" }, { "online", "Online" }, { "near", "Near my level" } },
  tools = function(bar)
    UI.roleChip = DropChip(bar, 84, "Show one role", function()
      local items = { { label = "Any role", value = false } }
      for _, r in ipairs({ "t", "h", "d" }) do items[#items + 1] = { label = ns.ROLES[r], value = r } end
      return items
    end, function() return UI.state.roster.role or false end, function(v) UI.state.roster.role = v or nil end)
    UI.reviewChip = DropChip(bar, 84, "Officers: members worth a look", function()
      return { { label = "Everyone", value = false }, { label = "Inactive " .. ns.INACTIVE_DAYS .. "+ days", value = "inactive" },
        { label = "Ready for promotion", value = "promote" }, { label = "Has an officer note", value = "note" } }
    end, function() return UI.state.roster.review or false end, function(v) UI.state.roster.review = v or nil end)
    bar:Add(Btn(bar, "My profile", 80, 22), "right", function() UI:OpenDetails("profile", ns.me) end,
      "Your role and what you're looking for, shown to the guild")
  end,
  rows = function(g, q)
    local st, out, officer = UI.state.roster, {}, ns.IsTrusted(ns.me)
    local myLevel = UnitLevel("player") or 1
    for name, r in pairs(ns.roster) do
      local prof = ns.ProfileOf(name)
      local roles = prof and prof.roles or ""
      local ok = (st.filter == "all") or (st.filter == "online" and r.online)
        or (st.filter == "near" and r.online and name ~= ns.me and math.abs((r.level or 0) - myLevel) <= 3)
      if ok and st.role then ok = roles:find(st.role, 1, true) ~= nil end
      local rv = (officer and st.review) and ns.Review(name) or nil
      if ok and rv then
        ok = (st.review == "inactive" and rv.inactive) or (st.review == "promote" and rv.promote)
          or (st.review == "note" and rv.note and rv.note.text ~= "")
      end
      if ok and Match(q, name, r.zone, r.class, ns.MainOf(name), prof and prof.lf, ns.RoleText(roles)) then
        local parts = { "Level " .. tostring(r.level or "?") .. (r.class and (" " .. r.class) or "") }
        if r.online then
          if r.zone and r.zone ~= "" then parts[#parts + 1] = r.zone end
        else
          parts[#parts + 1] = r.away and (r.away < 1 and "seen today" or ("seen " .. math.floor(r.away) .. "d ago")) or "offline"
        end
        if prof and prof.lf then parts[#parts + 1] = "|cfff2c14e" .. prof.lf .. "|r" end
        local pill
        if officer then
          local rev = rv or ns.Review(name)
          if rev.inactive then pill = "roster_inactive" elseif rev.promote then pill = "roster_promote" end
        end
        out[#out + 1] = {
          key = "member:" .. name, dot = r.online,
          title = ns.WhoLabel(name), titleColor = ClassColor(r.classFile),
          sub = table.concat(parts, "  ·  "), right = ns.RoleText(roles), pill = pill,
          sortOnline = r.online and 1 or 0, sortLevel = r.level or 0, sortName = name,
          onClick = function() UI:OpenDetails("member", name) end,
        }
      end
    end
    table.sort(out, function(a, b)
      if a.sortOnline ~= b.sortOnline then return a.sortOnline > b.sortOnline end
      if a.sortLevel ~= b.sortLevel then return a.sortLevel > b.sortLevel end
      return a.sortName < b.sortName
    end)
    return out
  end,
  footer = function()
    local n, on = 0, 0
    for _, r in pairs(ns.roster) do n = n + 1; if r.online then on = on + 1 end end
    return n .. " members, " .. on .. " online. Set your role and what you're looking for under My profile."
  end,
  empty = "Nobody matches. Try another filter.",
}

-- Officer -------------------------------------------------------------------
local function InboxWaiting()
  local n = 0
  local done = (ns.db and ns.db.inboxDone) or {}
  for _, e in ipairs(EPUGuildInbox or {}) do
    if type(e) == "table" and e.id and not done[e.id] then n = n + 1 end
  end
  return n
end


-- Crafting projects and onboarding ---------------------------------------
Views.projects = {
  label="Projects", icon="Interface\Icons\Trade_BlackSmithing",
  tools=function(bar)
    bar:Add(Btn(bar,"New project",100,22),"right",function()
      if ns.IsTrusted(ns.me) then UI:OpenDetails("newproject","new") else ns.Print("Ask an officer to create a project.") end
    end)
  end,
  rows=function(g,q)
    ns.PlanningStore(); local out={}
    for id,p in pairs(g.projects) do
      if p.status~="archived" and Match(q,p.title,p.note) then
        local done,total=ns.ProjectProgress(p)
        out[#out+1]={key="project:"..id,title=p.title,sub=p.note,right=done.." / "..total,
          frac=total>0 and done/total or 0,onClick=function() UI:OpenDetails("project",id) end}
      end
    end
    table.sort(out,function(a,b) return a.title<b.title end); return out
  end,
  empty="No active crafting projects. Officers can add one and assign craft tasks.",
  footer=function() return "Projects connect shared recipes, assigned crafters, materials and delivery progress." end,
}
Views.onboarding = {
  label="Getting started", icon="Interface\Icons\INV_Misc_Book_09",
  tools=function(bar)
    bar:Add(Btn(bar,"My checklist",100,22),"left",function() UI:OpenDetails("checklist",ns.me) end)
  end,
  rows=function(g,q)
    local out={}
    for name in pairs(ns.roster) do
      if (name==ns.me or ns.IsTrusted(ns.me)) and Match(q,name) then
        local done,total=0,0
        for _,s in ipairs(ns.Checklist(name)) do total=total+1; if s.done then done=done+1 end end
        out[#out+1]={key="checklist:"..name,title=ns.WhoLabel(name),sub="Guild setup and welcome checklist",
          right=done.." / "..total,frac=total>0 and done/total or 0,onClick=function() UI:OpenDetails("checklist",name) end}
      end
    end
    table.sort(out,function(a,b) return a.title<b.title end); return out
  end,
  empty="No checklist matches.",footer=function() return "Members complete their own steps; officers confirm Discord, mentors and starter supplies." end,
}

Views.officer = {
  label = "Officer", icon = "Interface\\Icons\\INV_Misc_Key_03", officer = true,
  count = function() return InboxWaiting(), C.goldBg, C.gold end,
  custom = true,
}

---------------------------------------------------------------------------
-- Toolbar (per view, built once)
---------------------------------------------------------------------------
local function NewBar(view)
  local bar = CreateFrame("Frame", nil, toolbar)
  bar:SetAllPoints()
  bar.leftX, bar.rightX = 10, 10
  function bar:Add(w, side, onClick, tip)
    w:SetParent(self)
    if w.text and not w.arrow and (w.text:GetText() or "") ~= "" then   -- fit plain buttons to their label
      w:SetWidth(math.max(36, (w.text:GetStringWidth() or 40) + 18))
    end
    w:ClearAllPoints()
    if side == "right" then
      w:SetPoint("RIGHT", self, "RIGHT", -self.rightX, 0)
      self.rightX = self.rightX + w:GetWidth() + 6
    else
      w:SetPoint("LEFT", self, "LEFT", self.leftX, 0)
      self.leftX = self.leftX + w:GetWidth() + 4
    end
    if onClick then w:SetScript("OnClick", onClick) end
    w.tip = tip
    return w
  end
  bar.chips = {}
  for _, ch in ipairs(view.chips or {}) do
    local key = ch[1]
    local stateKey = view.stateKey or (view == Views.requests and "requests") or (view == Views.needs and "needs") or "crafters"
    local probe = Btn(bar, ch[2], 60, 22)
    probe:SetWidth(math.max(36, (probe.text:GetStringWidth() or 40) + 18))
    local b = bar:Add(probe, "left", function()
      UI.state[stateKey].filter = key
      UI:Refresh()
    end)
    b.key, b.label = key, ch[2]
    bar.chips[#bar.chips + 1] = b
  end
  if view.tools then view.tools(bar) end
  bar:Hide()
  return bar
end

---------------------------------------------------------------------------
-- Composer (bottom bar for adding needs / making requests)
---------------------------------------------------------------------------
UI.itemBox = Box(composer, 200, "Item: shift-click or drag it here")
UI.itemBox:SetPoint("LEFT", 10, 0)
UI.qtyBox = Box(composer, 46, "Qty", true)
UI.qtyBox:SetPoint("LEFT", UI.itemBox, "RIGHT", 6, 0)
UI.noteBox = Box(composer, 120, "Note (optional)")
UI.noteBox:SetPoint("LEFT", UI.qtyBox, "RIGHT", 6, 0)
UI.noteBox:SetMaxLetters(80)
UI.kind = "restock"
UI.kindBtn = Btn(composer, "Restock", 96, 22)
UI.kindBtn:SetPoint("LEFT", UI.qtyBox, "RIGHT", 6, 0)
UI.kindBtn.tip = "Restock: always keep this many. One-time goal: closes itself when reached."
UI.kindBtn:SetScript("OnClick", function(self)
  UI.kind = (UI.kind == "restock") and "goal" or "restock"
  self:SetLabel(UI.kind == "goal" and "One-time goal" or "Restock")
end)
UI.forIndex = 1
UI.forBtn = Btn(composer, "For: me", 104, 22)
UI.forBtn:SetPoint("LEFT", UI.noteBox, "RIGHT", 6, 0)
UI.forBtn.tip = "Which of your characters it should be mailed to. Click to cycle."
function UI:ForTarget()
  local chars = ns.MyChars()
  if self.forIndex > #chars then self.forIndex = 1 end
  return chars[self.forIndex]
end
function UI:UpdateForButton()
  local t = self:ForTarget() or ns.me or "me"
  self.forBtn:SetLabel("For: " .. (t:match("^(%S+)") or t))
end
UI.forBtn:SetScript("OnClick", function() UI.forIndex = UI.forIndex + 1; UI:UpdateForButton() end)
-- officers: type any guild member's name (partial is fine if it's unique)
UI.forBox = Box(composer, 110, "For: me")
UI.forBox:SetPoint("LEFT", UI.noteBox, "RIGHT", 6, 0)
UI.forBox:Hide()
UI.forBox.tip = "Officers: type a guild member's name to request it for them."
UI.action = Btn(composer, "Request", 90, 22, "accent")
UI.action:SetPoint("RIGHT", -10, 0)

local function ClearComposer()
  UI.itemBox:SetText(""); UI.qtyBox:SetText(""); UI.noteBox:SetText(""); UI.forBox:SetText("")
end

local function SubmitComposer()
  local id = ns.ItemID(UI.itemBox:GetText())
  if UI.composerMode == "need" then
    local qty = tonumber(UI.qtyBox:GetText())
    if not id or not qty then return ns.Print("Pick an item and a target quantity (0 removes it).") end
    ns.SetNeed(id, qty, UI.kind)
  else
    if not id then return ns.Print("Shift-click or drag the item you need into the item box first.") end
    local typed = UI.forBox:IsShown() and (UI.forBox:GetText() or ""):match("^%s*(.-)%s*$") or ""
    if typed ~= "" and typed:lower() ~= "me" then
      local who, hits = ns.FindMember(typed)
      if not who then
        if hits and #hits > 1 then
          local names = {}
          for i = 1, math.min(6, #hits) do names[i] = hits[i] end
          return ns.Print("More than one member matches \"" .. typed .. "\": " .. table.concat(names, ", ") .. ". Type more of the name.")
        end
        return ns.Print("No guild member named \"" .. typed .. "\".")
      end
      ns.NewRequest(id, tonumber(UI.qtyBox:GetText()) or 1, UI.noteBox:GetText(), nil, who)
    else
      ns.NewRequest(id, tonumber(UI.qtyBox:GetText()) or 1, UI.noteBox:GetText(), UI:ForTarget())
    end
  end
  ClearComposer()
end
UI.action:SetScript("OnClick", SubmitComposer)
UI.itemBox.onEnter = SubmitComposer
UI.qtyBox.onEnter = SubmitComposer
UI.noteBox.onEnter = SubmitComposer
UI.forBox.onEnter = function(self)
  if UI:AcceptSuggestion(true) then return end
  SubmitComposer()
end

---------------------------------------------------------------------------
-- Name suggestions for the For box: guild members matching what you've
-- typed (start of first or last name), online first. Tab or a click fills it
-- in; Up/Down pick; Enter takes the picked one.
---------------------------------------------------------------------------
local sug = CreateFrame("Frame", nil, UI)
sug:SetFrameStrata("DIALOG")
sug:SetClampedToScreen(true)
sug.bg = Tex(sug, "BACKGROUND", C.panel); sug.bg:SetAllPoints()
Edges(sug, C.line)
sug.rows, sug.names, sug.sel, sug.moved = {}, {}, 1, false
sug:Hide()
UI.suggest = sug

function ns.MatchMembers(text, max)
  text = (text or ""):lower():match("^%s*(.-)%s*$")
  local out = {}
  if text == "" then return out end
  for name, r in pairs(ns.roster or {}) do
    local l = name:lower()
    local last = l:match("%s(.+)$") or ""
    if l:sub(1, #text) == text or last:sub(1, #text) == text then
      out[#out + 1] = { name = name, online = r.online and true or false, level = r.level }
    end
  end
  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  while #out > (max or 8) do out[#out] = nil end
  return out
end

-- Items the addon knows by name: everything the guild deals with, your bags,
-- and names cached earlier. (The game can't search items it hasn't seen.)
function ns.ItemCandidates()
  local ids = {}
  local g = ns.G()
  if g then
    for id in pairs(g.needs.list) do ids[id] = true end
    for _, b in pairs(g.bank) do for id in pairs(b.items or {}) do ids[tonumber(id) or 0] = true end end
    for _, r in pairs(g.requests) do if r.item then ids[r.item] = true end end
    for _, d in pairs(g.donations) do if d.item then ids[d.item] = true end end
    for _, rec in pairs(g.recipes or {}) do
      for _, p in pairs(rec.profs or {}) do for _, id in ipairs(p.items or {}) do ids[id] = true end end
    end
    for _, m in pairs(g.mats or {}) do for i = 1, #(m.r or {}), 2 do ids[m.r[i]] = true end end
  end
  for id in pairs((ns.db and ns.db.itemNames) or {}) do ids[id] = true end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
    for slot = 1, n do
      local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then ids[info.itemID] = true end
    end
  end
  ids[0] = nil
  return ids
end

function ns.MatchItems(text, max)
  text = (text or ""):lower():match("^%s*(.-)%s*$")
  local out = {}
  if #text < 2 then return out end
  local names = (ns.db and ns.db.itemNames) or {}
  for id in pairs(ns.ItemCandidates()) do
    local name = GetItemInfo(id) or names[id]
    if name then
      local l = name:lower()
      local at = l:find(text, 1, true)
      -- match at the start of the name or of any word in it
      if at and (at == 1 or l:sub(at - 1, at - 1):find("[%s%-:%(]")) then
        out[#out + 1] = { id = id, name = name, first = at == 1 }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.first ~= b.first then return a.first end
    return a.name < b.name
  end)
  while #out > (max or 8) do out[#out] = nil end
  return out
end

local function DrawSuggestions()
  for i, r in ipairs(sug.rows) do r.hl:SetShown(i == sug.sel) end
end

-- list: { { text, right, value, icon }, ... }; pick(box, value) fills the box
function UI:ShowSuggestions(box, list, pick)
  if #list == 0 then sug:Hide(); return end
  sug.box, sug.pick, sug.names, sug.sel, sug.moved = box, pick, {}, 1, false
  local w = math.max(box:GetWidth(), 220)
  for i, m in ipairs(list) do
    local r = sug.rows[i]
    if not r then
      r = CreateFrame("Button", nil, sug)
      r:SetHeight(20)
      r.hl = Tex(r, "BACKGROUND", C.hover); r.hl:SetAllPoints(); r.hl:Hide()
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.text = Font(r, 11)
      r.right = Font(r, 10, C.muted); r.right:SetPoint("RIGHT", -8, 0)
      r:SetScript("OnEnter", function(self) sug.sel = self.i; DrawSuggestions() end)
      r:SetScript("OnClick", function(self) sug.sel = self.i; UI:AcceptSuggestion() end)
      sug.rows[i] = r
    end
    r.i = i
    r:ClearAllPoints()
    r:SetPoint("BOTTOMLEFT", 1, 1 + (#list - i) * 20)
    r:SetPoint("BOTTOMRIGHT", -1, 1 + (#list - i) * 20)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", m.icon and 24 or 8, 0)
    r.icon:SetShown(m.icon ~= nil)
    if m.icon then r.icon:SetTexture(m.icon) end
    r.text:SetText(m.text)
    r.right:SetText(m.right or "")
    r:Show()
    sug.names[i] = m.value
  end
  for i = #list + 1, #sug.rows do sug.rows[i]:Hide() end
  sug:SetSize(w, #list * 20 + 2)
  sug:ClearAllPoints()
  sug:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)     -- the form sits at the bottom, so open upwards
  sug:Show()
  DrawSuggestions()
end

function UI:Suggest(box)
  local text = box:GetText() or ""
  local found = ns.MatchMembers(text, 8)
  if #found == 1 and found[1].name:lower() == text:lower() then sug:Hide(); return end
  local list = {}
  for i, m in ipairs(found) do
    list[i] = { text = m.name, value = m.name,
      right = (m.online and "|cff4ade80online|r  " or "") .. (m.level and ("lvl " .. m.level) or "") }
  end
  self:ShowSuggestions(box, list, function(b, v) b:SetText(v) end)
end

function UI:SuggestItems(box)
  local text = box:GetText() or ""
  if text:find("|H", 1, true) or text:find("^item:") then sug:Hide(); return end   -- already a real item
  local found = ns.MatchItems(text, 8)
  local list = {}
  for i, m in ipairs(found) do
    local have = ns.BankCount and ns.BankCount(m.id) or 0
    local q = select(3, GetItemInfo(m.id))
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    list[i] = { text = (c and c.hex or "") .. m.name .. (c and c.hex and "|r" or ""), value = m.id, icon = ns.ItemIcon(m.id),
      right = have > 0 and ("bank has " .. have) or nil }
  end
  self:ShowSuggestions(box, list, function(b, id) b:SetText(select(2, GetItemInfo(id)) or ("item:" .. id)) end)
end

-- Fill in the picked suggestion. With onlyIfChosen (Enter), only when the
-- choice is clear: a single match, or one picked with the arrow keys.
function UI:AcceptSuggestion(onlyIfChosen)
  if not sug:IsShown() or not sug.box then return false end
  if onlyIfChosen and not sug.moved and #sug.names ~= 1 then sug:Hide(); return false end
  local v = sug.names[sug.sel]
  if v == nil then return false end
  local box = sug.box
  sug:Hide()
  sug.pick(box, v)
  return true
end

local function WireSuggestions(box, suggest)
  box.onChange = function(self) if self:HasFocus() then suggest(UI, self) end end
  box:SetScript("OnTabPressed", function() UI:AcceptSuggestion() end)
  box:SetScript("OnArrowPressed", function(self, key)
    if not sug:IsShown() or sug.box ~= self then return end
    -- the list grows upwards: Up goes to the next entry
    if key == "UP" then sug.sel = math.min(#sug.names, sug.sel + 1); sug.moved = true
    elseif key == "DOWN" then sug.sel = math.max(1, sug.sel - 1); sug.moved = true end
    DrawSuggestions()
  end)
  box:HookScript("OnEditFocusLost", function(self) C_Timer.After(0.2, function() if sug.box == self and not self:HasFocus() then sug:Hide() end end) end)
  box:HookScript("OnHide", function(self) if sug.box == self then sug:Hide() end end)
end
WireSuggestions(UI.forBox, UI.Suggest)
WireSuggestions(UI.itemBox, UI.SuggestItems)
UI.itemBox.onEnter = function(self)
  if UI:AcceptSuggestion(true) then return end
  SubmitComposer()
end

-- open the request form already addressed to someone (from the roster)
function UI:RequestFor(name)
  self:SetView("requests")
  self.forBox:SetText(name or "")
  self.itemBox:SetFocus()
  ns.Print("Shift-click or drag the item for " .. tostring(name) .. ", set the amount, then press Request.")
end

-- Shift-click an item: it goes into the box you're typing in, or the item box
-- at the bottom if the window is open. Modern clients send shift-clicks through
-- ChatFrameUtil.InsertLink, older ones through ChatEdit_InsertLink; hook both.
local lastLink, lastAt = nil, 0
local function OnInsertLink(link)
  if not UI:IsShown() or type(link) ~= "string" or not link:find("|Hitem:") then return end
  if link == lastLink and GetTime() - lastAt < 0.2 then return end      -- same click seen by two hooks
  lastLink, lastAt = link, GetTime()
  local box = UI.focusBox
  if not (box and box:IsVisible()) then
    box = UI.itemBox:IsVisible() and UI.itemBox or nil
  end
  if box then box:SetText(link) end
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
if HandleModifiedItemClick then
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then OnInsertLink(link) end
  end)
end

-- The whole bottom bar takes a dropped item too, not just the small box.
composer:EnableMouse(true)
composer:SetScript("OnReceiveDrag", function() UI.itemBox:TakeCursorItem() end)
composer:SetScript("OnMouseDown", function() UI.itemBox:TakeCursorItem() end)

---------------------------------------------------------------------------
-- Officer page (custom content, built once)
---------------------------------------------------------------------------
-- The officer page scrolls, so it fits even the smallest window.
local officerScroll = CreateFrame("ScrollFrame", nil, listArea)
officerScroll:SetAllPoints()
officerScroll:Hide()
local officerPage = CreateFrame("Frame", nil, officerScroll)
officerPage:SetSize(480, 400)
officerScroll:SetScrollChild(officerPage)
officerScroll:EnableMouseWheel(true)
officerScroll:SetScript("OnMouseWheel", function(self, delta)
  local maxV = math.max(0, (officerPage:GetHeight() or 0) - (self:GetHeight() or 0))
  self:SetVerticalScroll(math.min(maxV, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
end)
officerScroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then officerPage:SetWidth(w) end end)
UI.officerPage = officerPage
do
  local y = -12
  local function Row(labelText, height)
    local l = Font(officerPage, 12, C.text)
    l:SetPoint("TOPLEFT", 14, y - 4)
    l:SetText(labelText)
    local hint = Font(officerPage, 10, C.muted)
    hint:SetPoint("TOPLEFT", 14, y - 20)
    y = y - (height or 44)
    return l, hint
  end

  local _, h1 = Row("Trusted ranks")
  UI.rankBtn = Btn(officerPage, "", 230, 22)
  UI.rankBtn:SetPoint("TOPRIGHT", -14, -12)
  UI.rankBtn.tip = "Members at these ranks (and any rank with \"Bank\" in its name) can change needs, approve requests and publish bank contents. Each officer's addon uses its own setting, so keep them the same."
  h1:SetText("Who can manage the bank")
  UI.rankBtn:SetScript("OnClick", function()
    local g = ns.G()
    if not g then return end
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 10
    g.officerRank = ((g.officerRank or 1) + 1) % math.max(1, n - 1)
    UI:Refresh()
  end)

  local _, h2 = Row("This character is a bank")
  h2:SetText("Track its bags and bank as guild stock")
  UI.bankToggle = Btn(officerPage, "", 80, 22)
  UI.bankToggle:SetPoint("TOPRIGHT", -14, -56)
  UI.bankToggle:SetScript("OnClick", function() ns.SetBankAlt(not ns.IsBankAlt()); UI:Refresh() end)

  local _, h3 = Row("Open requests per player")
  h3:SetText("Counting alts. 0 means no limit. Shared with the guild.")
  UI.limitBox = Box(officerPage, 50, "0", true)
  UI.limitBox:SetPoint("TOPRIGHT", -84, -100)
  local limitSave = Btn(officerPage, "Save", 62, 22)
  limitSave:SetPoint("TOPRIGHT", -14, -100)
  limitSave:SetScript("OnClick", function()
    ns.SetPolicy("maxOpen", tonumber(UI.limitBox:GetText()) or 0)
    UI.limitBox:ClearFocus()
  end)

  local _, h4 = Row("Discord")
  UI.inboxHint = h4
  local applyInbox = Btn(officerPage, "Apply inbox now", 120, 22)
  applyInbox:SetPoint("TOPRIGHT", -146, -144)
  applyInbox.tip = "Apply requests and approvals made in Discord that have arrived in Inbox.lua."
  applyInbox:SetScript("OnClick", function() ns.ProcessInbox(); UI:Refresh() end)
  local saveDiscord = Btn(officerPage, "Save for Discord", 126, 22)
  saveDiscord:SetPoint("TOPRIGHT", -14, -144)
  saveDiscord.tip = "Reloads your UI so WoW saves everything and the Discord bot picks it up."
  saveDiscord:SetScript("OnClick", function() pcall(ns.CacheItemNames); ReloadUI() end)

  local rowY = y
  local _, h6 = Row("Promotion reminder", 62)
  h6:SetText("Tags members at the lowest rank who are ready, so you remember to promote them")
  -- [Days in guild: __]  [Min level: __]  [Save], with their own labels
  local promoSave = Btn(officerPage, "Save", 62, 22)
  promoSave:SetPoint("TOPRIGHT", -14, rowY)
  UI.promoLevel = Box(officerPage, 36, "0", true)
  UI.promoLevel:SetPoint("TOPRIGHT", promoSave, "TOPLEFT", -8, 0)
  local lvlLabel = Font(officerPage, 11, C.muted)
  lvlLabel:SetPoint("RIGHT", UI.promoLevel, "LEFT", -4, 0)
  lvlLabel:SetText("Min level")
  UI.promoDays = Box(officerPage, 36, "0", true)
  UI.promoDays:SetPoint("RIGHT", lvlLabel, "LEFT", -12, 0)
  local daysLabel = Font(officerPage, 11, C.muted)
  daysLabel:SetPoint("RIGHT", UI.promoDays, "LEFT", -4, 0)
  daysLabel:SetText("Days in guild")
  h6:ClearAllPoints()
  h6:SetPoint("TOPLEFT", 14, rowY - 20)
  UI.promoRule = Font(officerPage, 11, C.gold)       -- the rule in plain words
  UI.promoRule:SetPoint("TOPLEFT", 14, rowY - 38)
  promoSave.tip = "Members at the lowest rank who meet both get a \"Promote?\" tag on the Roster page (officers only)."
  promoSave:SetScript("OnClick", function()
    ns.SetPolicy("promoDays", tonumber(UI.promoDays:GetText()) or 0)
    ns.SetPolicy("promoLevel", tonumber(UI.promoLevel:GetText()) or 0)
    UI.promoDays:ClearFocus(); UI.promoLevel:ClearFocus()
  end)

  local _, h5 = Row("Tools", 40)
  h5:SetText("")
  local tools = {
    { "Post needs to guild", function() ns.PostNeeds() end, "Posts the top open needs in guild chat." },
    { "Full sync", function() ns.FullSync() end, "Asks other online officers to resend everything." },
    { "Tidy finished requests", function()
        local n = ns.ArchiveFinished()
        ns.Print("Tidied " .. n .. " finished request" .. (n == 1 and "" or "s") .. ". They're still under the All filter.")
      end, "Hides filled, rejected and cancelled requests from the default views, for everyone." },
    { "Profession coverage", function() UI:OpenDetails("coverage", "all") end, "Which professions the guild has, who's best, and the gaps." },
    { "Officer log", function() UI:OpenDetails("log", "all") end, "Who approved, rejected, voided or changed what, and when." },
  }
  local x = 14
  for _, t in ipairs(tools) do
    local b = Btn(officerPage, t[1], 10, 22)
    b:SetWidth((b.text:GetStringWidth() or 80) + 20)
    if x + b:GetWidth() > 460 then x = 14; y = y - 28 end     -- wrap onto a second line
    b:SetPoint("TOPLEFT", x, y + 8)
    b:SetScript("OnClick", t[2])
    b.tip = t[3]
    x = x + b:GetWidth() + 6
  end
  y = y - 30
  UI.officerStats = Font(officerPage, 11, C.muted)
  UI.officerStats:SetPoint("TOPLEFT", 14, y)
  UI.officerStats:SetPoint("RIGHT", -14, 0)
  UI.officerStats:SetWordWrap(true)
  officerPage:SetHeight(-y + 90)
end

local function RefreshOfficerPage(g)
  local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
  local names = {}
  for i = 0, (g.officerRank or 1) do
    local nm = GuildControlGetRankName and GuildControlGetRankName(i + 1)
    names[#names + 1] = nm or ("rank " .. i)
  end
  UI.rankBtn:SetLabel("Ranks 0-" .. (g.officerRank or 1) .. ": " .. table.concat(names, ", "))
  UI.bankToggle:SetLabel(ns.IsBankAlt() and "On" or "Off")
  UI.bankToggle:SetOn(ns.IsBankAlt())
  if not UI.limitBox:HasFocus() then UI.limitBox:SetText(tostring(g.policy.maxOpen or 0)) end
  if not UI.promoDays:HasFocus() then UI.promoDays:SetText(tostring(g.policy.promoDays or 0)) end
  if not UI.promoLevel:HasFocus() then UI.promoLevel:SetText(tostring(g.policy.promoLevel or 0)) end
  local pd, pl = tonumber(g.policy.promoDays) or 0, tonumber(g.policy.promoLevel) or 0
  local nRanks = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
  local lowName = (nRanks > 0 and GuildControlGetRankName and GuildControlGetRankName(nRanks)) or "lowest-rank"
  if pd == 0 and pl == 0 then
    UI.promoRule:SetText("Off. Set either number above 0 to turn it on.")
    SetColor(UI.promoRule, C.muted)
  else
    local parts = {}
    if pd > 0 then parts[#parts + 1] = "in the guild " .. pd .. "+ days" end
    if pl > 0 then parts[#parts + 1] = "level " .. pl .. "+" end
    UI.promoRule:SetText("Now: " .. lowName .. " members " .. table.concat(parts, " and ") .. " get a \"Promote?\" tag on the Roster.")
    SetColor(UI.promoRule, C.gold)
  end
  local inactive, promote = 0, 0
  for name in pairs(ns.roster) do
    local rv = ns.Review(name)
    if rv.inactive then inactive = inactive + 1 end
    if rv.promote then promote = promote + 1 end
  end
  local waiting = InboxWaiting()
  UI.inboxHint:SetText(waiting > 0 and ("|cfff2c14e" .. waiting .. " update(s) from Discord waiting|r") or "Nothing waiting from Discord")
  local open, pending, members = 0, 0, 0
  for _, r in pairs(g.requests) do
    if ns.IsActiveRequest(r) then open = open + 1 end
    if r.status == "pending" or r.status == "open" then pending = pending + 1 end
  end
  for _ in pairs(g.crafters) do members = members + 1 end
  local gaps, noGuild = {}, {}
  for _, row in ipairs(ns.Coverage()) do
    if row.count == 0 then gaps[#gaps + 1] = row.prof
    elseif #row.guild == 0 then noGuild[#noGuild + 1] = row.prof end
  end
  UI.officerStats:SetText(open .. " open requests (" .. pending .. " pending)  ·  " .. members
    .. " members using the addon  ·  addon version " .. ns.VERSION
    .. ((inactive + promote > 0) and ("\n" .. inactive .. " inactive " .. ns.INACTIVE_DAYS .. "+ days, " .. promote .. " ready for promotion (Roster > Review)") or "")
    .. ((members > 0 and #gaps > 0) and ("\n|cffff6b6bNobody has:|r " .. table.concat(gaps, ", ")) or "")
    .. ((members > 0 and #noGuild > 0) and ("\n|cfff2c14eNo guild crafter yet:|r " .. table.concat(noGuild, ", ")) or ""))
end

---------------------------------------------------------------------------
-- Details content
---------------------------------------------------------------------------
-- Reagent lines for a recipe: icon, name x count, how many the bank has.
local function MatsLines(key, times)
  local mats = ns.MatsFor(key)
  if #mats == 0 then
    det:Text("Materials: not shared yet (the crafter's addon sends them when they open their profession window).", C.muted)
    return mats
  end
  det:Text(times and times > 1 and ("Materials for " .. times .. ":") or "Materials:", C.muted)
  for _, m in ipairs(mats) do
    local need = m.n * (times or 1)
    local bank = ns.BankCount(m.id)
    local col = (bank >= need) and "|cff4ade80" or "|cff7e8590"
    det:Text("|T" .. (ns.ItemIcon(m.id) or "") .. ":14:14|t " .. ns.ItemName(m.id, true) .. " x" .. need
      .. "   " .. col .. "bank " .. bank .. "|r")
    det.y = det.y + 4
  end
  return mats
end

local MATS_LABEL = { me = "I'll send the materials", bank = "Guild bank sends materials", crafter = "Crafter uses their own" }
local MATS_ORDER = { "me", "bank", "crafter" }

function UI:FillDetails()
  local g = ns.G()
  if not det:IsShown() or not g then return end
  local kind, key = det.kind, det.key
  local officer = ns.IsTrusted(ns.me)


  if kind=="newproject" then
    det:Reset(nil,1,"New crafting project","Officers coordinate shared crafting goals")
    local title=det:Field("Title","",160)
    local note=det:Field("Goal","",160)
    det:Buttons({{"Create",function() local id=ns.CreateProject(title:GetText(),note:GetText()); if id then UI:OpenDetails("project",id) end end,accent=true}})
  elseif kind=="project" then
    local p=ns.PlanningStore().projects[key]; if not p then return UI:CloseDetails() end
    local done,total=ns.ProjectProgress(p)
    det:Reset(nil,1,p.title,done.." of "..total.." items delivered")
    det:Text(p.note)
    for _,task in ipairs(p.tasks) do
      local r=g.requests[task.rid]; local rid=task.rid
      det:Text((r and ns.RequestName(r,true) or task.key).." x"..task.qty.." - "..task.crafter)
      det:Text(r and ((r.status or "pending")..", "..ns.Remaining(r).." remaining; deliver to "..task.to) or "Request history unavailable; awaiting sync.",C.muted)
      if r then det:Buttons({{"View request",function() UI:OpenDetails("request",rid) end}}) end
    end
    det:Text("Materials still required",C.gold)
    for item,n in pairs(ns.ProjectMaterials(p)) do det:Text(ns.ItemName(item,true).." x"..n.." (bank: "..ns.BankCount(item)..")") end
    if officer then
      det:Buttons({{"Add craft task",function() UI:OpenDetails("projecttask",key) end},
        {"Stock materials",function() ns.StockProject(key) end}, {"Archive",function() ns.ArchiveProject(key); UI:CloseDetails() end}})
    end
  elseif kind=="projecttask" then
    det:Reset(nil,1,"Add craft task","Pick a shared recipe and a crafter who knows it")
    local item=det:Field("Item / spell","",160)
    local qty=det:Field("Quantity","1",60,true)
    local crafter=det:Field("Crafter","",160)
    local recipient=det:Field("Send to",ns.me,160)
    det:Text("Shift-click an item into the first field, enter an item ID, or use spell:Enchant Name. Materials come from the guild bank. The crafter must accept the request.",C.muted)
    det:Buttons({{"Assign",function()
      local id=ns.ItemID(item:GetText()); local recipe=id and ("item:"..id) or item:GetText()
      local rid=ns.AddProjectTask(key,recipe,crafter:GetText(),qty:GetText(),recipient:GetText())
      if rid then UI:OpenDetails("project",key) end
    end,accent=true}})
  elseif kind=="checklist" then
    det:Reset(nil,1,"Getting started",key)
    for _,s in ipairs(ns.Checklist(key)) do
      local step=s.id; local value=s.done
      det:Text((value and "[Done] " or "[ ] ")..s.title,value and C.green or C.white)
      det:Text(s.text,C.muted)
      if s.note~="" then det:Text(s.note) end
      if officer or (key==ns.me and not s.officer) then
        det:Buttons({{value and "Mark incomplete" or "Mark done",function() ns.SetChecklist(key,step,not value,s.note); UI:FillDetails() end}})
      end
      if officer then
        det:Buttons({{"Edit instructions",function() UI:OpenDetails("editstep",step) end}})
      end
    end
    if officer then
      local note=det:Field("Mentor / kit","",160)
      det:Buttons({{"Save welcome note",function() ns.SetChecklist(key,"mentor",true,note:GetText()); UI:FillDetails() end}})
    end
  elseif kind=="editstep" then
    det:Reset(nil,1,"Checklist instructions","Officers can update or add steps")
    local step=det:Field("Step ID",key,160)
    local found
    for _,s in ipairs(ns.OnboardingSteps()) do if s.id==key then found=s end end
    local title=det:Field("Title",found and found.title or "",160)
    local text=det:Field("Instructions",found and found.text or "",160)
    local restricted=found and found.officer or false
    det:Buttons({{restricted and "Officer confirms" or "Member confirms",function(self) restricted=not restricted; self:SetLabel(restricted and "Officer confirms" or "Member confirms") end}})
    det:Buttons({{"Save",function() ns.SetOnboardingStep(step:GetText(),title:GetText(),text:GetText(),restricted); UI:SetView("onboarding") end,accent=true}})
  elseif kind == "request" and g.requests[key] and g.requests[key].crafter then

    local r = g.requests[key]
    local p = PILL[PillKey(r)] or { r.status }
    local name = ns.RequestName(r, true)
    det:Reset(r.item and ns.ItemIcon(r.item) or "Interface\\Icons\\Trade_Engraving", Quality(r.item),
      name .. "  x" .. r.qty, "Craft request  ·  " .. p[1] .. "  ·  " .. Ago(r.t))
    local e = ns.RecipeFor(r.key)
    local prof = e and e.prof
    det:Text("Asked by " .. ns.WhoLabel(r.who) .. ((r.to and r.to ~= r.who) and (", for " .. r.to) or ""))
    det:Text("Delivered: " .. (r.delivered or 0) .. " / " .. r.qty .. "   Remaining: " .. ns.Remaining(r))
    det:Text("Crafter: " .. ((prof and ns.IsDesignated(r.crafter, prof)) and (STAR .. " ") or "") .. r.crafter
      .. (Online(r.crafter) and "  |cff4ade80online|r" or ""))
    det:Text(MATS_LABEL[r.mats or "me"] or "", C.muted)
    if r.note and r.note ~= "" then det:Text("Note: " .. r.note) end
    if r.status == "rejected" and r.reason and r.reason ~= "" then det:Text("Reason: " .. r.reason, C.red) end
    det:Gap()
    MatsLines(r.key, r.qty)
    det:Gap()
    local iCraft, own = r.crafter == ns.me, r.who == ns.me
    local pending = (r.status == "pending" or r.status == "open")
    if iCraft or officer then
      local reason = det:Field("Reason", r.reason or "", 160)
      local function Set(st) return function() ns.EditRequest(key, { status = st, reason = reason:GetText() }) end end
      if pending then
        det:Buttons({ { "Accept", Set("approved"), accent = true, tip = "You'll make it. They're told right away." },
          { "Decline", Set("rejected"), tip = "Type a reason above first if you like" } })
      elseif r.status == "approved" then
        local specs = { { "Made it", Set("filled"), accent = true, tip = "Mailing or trading it to them marks this automatically." },
          { "Decline", Set("rejected") } }
        if r.item then table.insert(specs, 2, { "Mail it", function() ns.MailRequest(key) end,
          tip = "With a mailbox open: fills in " .. (r.to or r.who) .. " and attaches what you made." }) end
        det:Buttons(specs)
      end
    end
    if ns.IsActiveRequest(r) and ((own and r.mats == "me") or (officer and r.mats == "bank")) then
      det:Buttons({ { "Mail materials to " .. (r.crafter:match("^(%S+)") or r.crafter), function() ns.MailCraftMats(key) end,
        tip = "With a mailbox open: attaches the materials for " .. r.qty .. " from your bags." } })
    end
    if own and ns.IsActiveRequest(r) then
      det:Buttons({ { "Cancel request", function() ns.EditRequest(key, { status = "cancelled" }) end } })
    end
    local other = iCraft and r.who or r.crafter
    det:Buttons({ { "Whisper " .. (other:match("^(%S+)") or other), function()
      if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. other .. " ") end
    end } })

  elseif kind == "member" then
    local r = ns.roster[key]
    if not r then return UI:CloseDetails() end
    det:Reset(nil, nil, ns.WhoLabel(key), "Level " .. tostring(r.level or "?") .. (r.class and (" " .. r.class) or "")
      .. "  ·  " .. tostring(r.rankName or ""))
    SetColor(det.title, ClassColor(r.classFile))
    if r.online then
      det:Text("|cff4ade80Online|r" .. ((r.zone and r.zone ~= "") and ("  ·  " .. r.zone) or ""))
    else
      det:Text("Offline" .. (r.away and ("  ·  last seen " .. (r.away < 1 and "today" or (math.floor(r.away) .. " days ago"))) or ""), C.muted)
    end
    local prof = ns.ProfileOf(key)
    if prof and prof.roles then det:Text("Plays: " .. ns.RoleText(prof.roles)) end
    if prof and prof.lf then det:Text("Looking for: |cfff2c14e" .. prof.lf .. "|r") end
    local main, alts = ns.MainOf(key), ns.AltsOf(ns.MainOf(key))
    if #alts > 0 then det:Text("Characters: " .. main .. ", " .. table.concat(alts, ", "), C.muted) end
    local c = g.crafters[key]
    if c and c.profs and next(c.profs) then
      local parts = {}
      for p2, v in pairs(c.profs) do parts[#parts + 1] = p2 .. " " .. v end
      table.sort(parts)
      det:Text("Professions: " .. table.concat(parts, ", "), C.muted)
    end
    det:Gap()
    local specs = { { "Whisper", function() if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. key .. " ") end end, accent = true } }
    if key ~= ns.me then
      specs[#specs + 1] = { "Invite to group", function()
        local inv = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if inv then inv(key) end
      end }
    end
    det:Buttons(specs)
    if officer and key ~= ns.me then
      det:Buttons({ { "Request for " .. (key:match("^(%S+)") or key), function() UI:RequestFor(key) end } })
    end
    if officer then
      local rv = ns.Review(key)
      det:Gap()
      det:Text("|cfff2c14eOfficer review|r")
      if rv.joined then
        det:Text((rv.joinedSeed and "In the guild since before " or "Joined ") .. date("%b %d", rv.joined)
          .. " (" .. rv.daysIn .. (rv.daysIn == 1 and " day" or " days") .. ")")
      end
      if rv.gained ~= nil then det:Text("Levels gained, last 14 days: " .. rv.gained) end
      det:Text("Last 30 days: " .. rv.donations .. " donations, " .. rv.requests .. " requests (all characters)")
      if rv.inactive then det:Text("Inactive for " .. math.floor(rv.away) .. " days", C.red) end
      if rv.promote then det:Text("Meets the promotion check", C.gold) end
      local note = det:Field("Note", rv.note and rv.note.text or "", 160)
      if rv.note and rv.note.text ~= "" then det:Text("Last edited by " .. tostring(rv.note.by) .. " " .. Ago(rv.note.t), C.muted) end
      det:Buttons({ { "Save note", function() ns.SetNote(key, note:GetText()) end,
        tip = "Officer notes are shared with other officers only, never shown to members." } })
    end

  elseif kind == "profile" then
    det:Reset(nil, nil, "My profile", "Shown to the guild on the Roster page")
    local prof = (ns.GuildStore() or {}).profiles and ns.GuildStore().profiles[ns.me]
    det.prof = det.prof or {}
    if det.prof.loaded ~= ns.me then
      det.prof = { loaded = ns.me, roles = prof and prof.roles or "", lf = prof and prof.lf or "" }
    end
    local P = det.prof
    det:Text("What do you play? (pick any)", C.muted)
    local specs = {}
    for _, r in ipairs({ "t", "h", "d" }) do
      local on = P.roles:find(r, 1, true) ~= nil
      specs[#specs + 1] = { (on and "|cff4ade80[x]|r " or "[ ] ") .. ns.ROLES[r], function()
        if P.roles:find(r, 1, true) then P.roles = P.roles:gsub(r, "") else P.roles = P.roles .. r end
        UI:FillDetails()
      end }
    end
    det:Buttons(specs)
    local lf = det:Field("Looking for", P.lf, 160)
    lf.onChange = function(b) P.lf = b:GetText() end
    det:Text("e.g. \"LF Deadmines\", \"leveling buddy\", \"selling Linen Bags\"", C.muted)
    det:Buttons({ { "Save", function() ns.SetProfile(P.roles, P.lf); ns.Print("Profile saved.") end, accent = true } })
    det:Text("Applies to this character. Alts without their own profile show your main's.", C.muted)

  elseif kind == "news" then
    local e = (ns.GuildStore() or {}).news and ns.GuildStore().news[key]
    if not e or e.removed then return UI:CloseDetails() end
    det:Reset("Interface\\Icons\\INV_Letter_15", 1, (e.title and e.title ~= "") and e.title or "Announcement",
      tostring(e.by) .. "  ·  " .. Ago(e.t) .. (e.via == "discord" and "  ·  from Discord" or ""))
    det:Text(e.text or "")
    det:Gap()
    if officer then
      det:Buttons({ { "Edit", function() UI:OpenDetails("newnews", key) end },
        { "Remove", function() ns.RemoveNews(key); UI:CloseDetails() end } })
    end

  elseif kind == "motd" then
    local m, info = ns.MotdEntry(), ns.GuildInfoText()
    det:Reset("Interface\\Icons\\INV_Misc_Note_01", 1, key == "info" and "Guild info" or "Message of the day",
      "From the in-game guild window" .. ((key ~= "info" and m and m.t) and ("  ·  changed " .. Ago(m.t)) or ""))
    if key ~= "info" then
      det:Text(m and m.text or "No message of the day set.")
      if info then det:Gap(); det:Text("Guild info", C.muted); det:Text(info) end
    else
      det:Text(info or "No guild info set.")
    end
    det:Gap()
    det:Text("Officers change these in the guild window (Guild & Communities). The addon shows the message of the day here, pops it up when it changes, and mirrors it to Discord.", C.muted)

  elseif kind == "newnews" then
    local e = key ~= "new" and (ns.GuildStore() or {}).news[key] or nil
    det:Reset("Interface\\Icons\\INV_Letter_15", 1, e and "Edit announcement" or "New announcement",
      "Pops up for everyone at their next login, and goes to Discord")
    if not officer then det:Text("Only officers can post announcements.", C.muted) det:Finish() return end
    local title = det:Field("Title", e and e.title or "", 160)
    title:SetMaxLetters(60)
    local text = det:Field("Message", e and e.text or "", 160)
    text:SetMaxLetters(400)
    det:Text("Up to 400 characters. Keep it short: it appears as a pop-up.", C.muted)
    det:Buttons({ { e and "Save" or "Post", function()
      local id = ns.PostNews(title:GetText(), text:GetText(), e and key or nil)
      if id then UI:OpenDetails("news", id) end
    end, accent = true }, { "Cancel", function() UI:CloseDetails() end } })

  elseif kind == "log" then
    det:Reset("Interface\\Icons\\INV_Misc_Note_01", 1, "Officer log", "What officers changed, newest first (90 days)")
    local list = ns.LogEntries()
    for i = 1, math.min(100, #list) do
      local e = list[i]
      det:Text("|cff7e8590" .. date("%b %d %H:%M", e.t) .. "  " .. tostring(e.by) .. "|r\n" .. tostring(e.text))
      det.y = det.y + 2
    end
    if #list == 0 then det:Text("Nothing logged yet.", C.muted) end
    if #list > 100 then det:Text("Showing the newest 100 of " .. #list .. ".", C.muted) end

  elseif kind == "craftask" then
    -- key = recipeKey .. "\n" .. crafter
    local rkey, crafter = key:match("^(.-)\n(.+)$")
    local e = rkey and ns.RecipeFor(rkey)
    if not e then return UI:CloseDetails() end
    local name = e.item and ns.ItemName(e.item, true) or e.name
    det:Reset(e.item and ns.ItemIcon(e.item) or "Interface\\Icons\\Trade_Engraving", Quality(e.item), name,
      "Ask " .. crafter .. " to craft this")
    det.ask = det.ask or {}
    local ask = det.ask
    if ask.key ~= key then ask.key, ask.qty, ask.mats, ask.forIndex = key, 1, "me", 1 end
    local qty = det:Field("Quantity", tostring(ask.qty), 60, true)
    qty.onChange = function(b) ask.qty = math.max(1, tonumber(b:GetText()) or 1) end
    qty.onEnter = function() UI:FillDetails() end
    local note = det:Field("Note", ask.note or "", 160)
    note.onChange = function(b) ask.note = b:GetText() end
    local function MatsIndex() for i, m in ipairs(MATS_ORDER) do if m == ask.mats then return i end end return 1 end
    det:Buttons({ { MATS_LABEL[ask.mats], function()
      ask.mats = MATS_ORDER[MatsIndex() % #MATS_ORDER + 1]
      UI:FillDetails()
    end, tip = "Who provides the materials. Click to change." } })
    local chars = ns.MyChars()
    if #chars > 1 then
      if ask.forIndex > #chars then ask.forIndex = 1 end
      det:Buttons({ { "Send it to: " .. chars[ask.forIndex], function()
        ask.forIndex = ask.forIndex % #chars + 1
        UI:FillDetails()
      end, tip = "Which of your characters gets it" } })
    end
    det:Gap()
    MatsLines(rkey, ask.qty)
    det:Gap()
    det:Buttons({ { "Send request", function()
      local rid = ns.NewCraftRequest(rkey, crafter, ask.qty, ask.mats, ask.note, chars[ask.forIndex])
      ask.key = nil
      if rid then UI:OpenDetails("request", rid) end
    end, accent = true }, { "Back", function() UI:OpenDetails("recipe", rkey) end } })
    det:Text(crafter .. " gets a pop-up and can accept or decline. You'll be told either way.", C.muted)

  elseif kind == "coverage" then
    det:Reset("Interface\\Icons\\INV_Misc_Note_01", 1, "Profession coverage", "Who the guild has for each profession")
    local gaps = {}
    for _, row in ipairs(ns.Coverage()) do
      if row.count == 0 then
        det:Text("|cffff6b6b" .. row.prof .. ": nobody yet|r")
        gaps[#gaps + 1] = row.prof
      else
        local guild = #row.guild > 0 and ("  " .. STAR .. " " .. table.concat(row.guild, ", ")) or "  |cfff2c14eno guild crafter|r"
        det:Text(row.prof .. ": " .. row.count .. (row.count == 1 and " player" or " players")
          .. ", best " .. row.best .. ((row.online > 0) and ("  ·  |cff4ade80" .. row.online .. " online|r") or "")
          .. (row.recipes > 0 and ("  ·  " .. row.recipes .. " recipes") or "") .. "\n" .. guild)
      end
      det.y = det.y + 2
    end
    det:Gap()
    det:Text(#gaps > 0 and ("Worth recruiting or leveling: " .. table.concat(gaps, ", ") .. ".") or "Every profession has someone.", C.muted)
    det:Text("Players are counted once across their alts. Pick guild crafters from a crafter's details.", C.muted)

  elseif kind == "request" then
    local r = g.requests[key]
    if not r then return UI:CloseDetails() end
    local p = PILL[r.status] or { r.status }
    det:Reset(ns.ItemIcon(r.item), Quality(r.item), ns.ItemName(r.item, true), p[1] .. "  ·  requested " .. Ago(r.t))
    det:Text("Delivered: " .. (r.delivered or 0) .. " / " .. r.qty .. "   Remaining: " .. ns.Remaining(r))
    det:Text("Requested by " .. ns.WhoLabel(r.who) .. ((r.via == "discord") and " via Discord" or ""))
    if r.by and r.status ~= "pending" then det:Text("Last changed by " .. r.by .. " " .. Ago(r.u), C.muted) end
    det:Text("In bank: " .. ns.BankCount(r.item) .. "   You carry: " .. ns.ItemCount(r.item), C.muted)
    det:Gap()
    local own, pending = (r.who == ns.me), (r.status == "pending" or r.status == "open")
    local canEdit = officer or (own and pending)
    if canEdit then
      local qty = det:Field("Quantity", tostring(r.qty), 60, true)
      local note = det:Field("Note", r.note or "", 160)
      -- deliver-to: cycle through the requester's characters
      local chars = { r.who }
      for _, a in ipairs(ns.AltsOf(r.who)) do chars[#chars + 1] = a end
      local main = ns.MainOf(r.who)
      if main ~= r.who then table.insert(chars, 1, main) end
      local seen, uniq = {}, {}
      for _, c in ipairs(chars) do if not seen[c] then seen[c] = true; uniq[#uniq + 1] = c end end
      local idx = 1
      for i, c in ipairs(uniq) do if c == (r.to or r.who) then idx = i end end
      det.toChoice = uniq[idx]
      det:Buttons({ { "Mail to: " .. uniq[idx], function(self)
        idx = idx % #uniq + 1
        det.toChoice = uniq[idx]
        self:SetLabel("Mail to: " .. uniq[idx])
      end, tip = (#uniq > 1) and ("Click to pick another of " .. ns.MainOf(r.who) .. "'s characters") or "No other characters known for this player" } })
      local reason = officer and det:Field("Reason", r.reason or "", 160) or nil
      det:Buttons({ { "Save changes", function()
        ns.EditRequest(key, { qty = qty:GetText(), note = note:GetText(), to = det.toChoice,
          reason = reason and reason:GetText() or nil })
        ns.Print("Request updated.")
      end, accent = true } })
      if officer then
        det:Text("Set status", C.muted)
        local function Set(s) return function()
          ns.EditRequest(key, { status = s, reason = reason and reason:GetText() or nil })
        end end
        det:Buttons({ { "Pending", Set("pending") }, { "Approve", Set("approved") }, { "Fill", Set("filled") }, { "Reject", Set("rejected"), tip = "Type a reason above first if you like" } })
        if r.status == "approved" then
          det:Buttons({ { "Mail it", function() ns.MailRequest(key) end, accent = true,
            tip = "With a mailbox open: fills in " .. (r.to or r.who) .. " and attaches " .. r.qty .. " from your bags. You click Send." } })
        end
      end
      if own and ns.IsActiveRequest(r) then
        det:Buttons({ { "Cancel request", function() ns.EditRequest(key, { status = "cancelled" }) end } })
      end
    else
      if r.note and r.note ~= "" then det:Text("Note: " .. r.note) end
      if r.to and r.to ~= r.who then det:Text("Mail to: " .. r.to) end
      if r.status == "rejected" and r.reason then det:Text("Reason: " .. r.reason, C.red) end
      det:Text(own and "An officer is handling this. Ask them in game or on Discord to change it." or "Only officers and the requester can change this.", C.muted)
    end

  elseif kind == "need" then
    local v = g.needs.list[key]
    if not v then return UI:CloseDetails() end
    local target, nkind = ns.NeedEntry(v)
    det:Reset(ns.ItemIcon(key), Quality(key), ns.ItemName(key, true), (nkind == "goal" and "One-time goal" or "Restock") .. "  ·  target " .. target)
    det:Text("In bank: " .. ns.BankCount(key) .. "   You carry: " .. ns.ItemCount(key))
    det:Text("Mail donations to " .. ns.BankAltNames(), C.muted)
    det:Gap()
    if officer then
      local t = det:Field("Target", tostring(target), 60, true)
      local choice = nkind
      det:Buttons({ { (choice == "goal") and "One-time goal" or "Restock", function(self)
        choice = (choice == "goal") and "restock" or "goal"
        self:SetLabel((choice == "goal") and "One-time goal" or "Restock")
      end, tip = "Restock: always keep this many. One-time goal: closes itself when reached." } })
      det:Buttons({ { "Save", function() ns.SetNeed(key, tonumber(t:GetText()) or target, choice) end, accent = true },
        { "Remove", function() ns.SetNeed(key, 0); UI:CloseDetails() end } })
    end
    det:Buttons({ { "Request this", function()
      UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus()
    end } })

  elseif kind == "item" then
    local holders = {}
    for alt, s in pairs(g.bank) do
      if not s.retired and s.items and s.items[key] then holders[#holders + 1] = alt .. ": " .. s.items[key] end
    end
    det:Reset(ns.ItemIcon(key), Quality(key), ns.ItemName(key, true), "In bank: " .. ns.BankCount(key))
    for _, h in ipairs(holders) do det:Text(h) end
    if #holders == 0 then det:Text("None in the bank right now.", C.muted) end
    det:Gap()
    det:Buttons({ { "Request this", function()
      UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus()
    end, accent = true } })
    if officer then
      det:Buttons({ { "Add as a need", function()
        UI:SetView("needs"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus()
      end } })
    end

  elseif kind == "donation" then
    local d = g.donations[key]
    if not d then return UI:CloseDetails() end
    local name = d.item and ns.ItemName(d.item, true) or Money(d.money)
    det:Reset(d.item and ns.ItemIcon(d.item) or "Interface\\Icons\\INV_Misc_Coin_01", d.item and Quality(d.item) or 1,
      name, Ago(d.t) .. (d.void and "  ·  voided" or ""))
    det:Text("From " .. ns.WhoLabel(d.who or "?"))
    det:Text("Received by " .. tostring(d.to) .. " on " .. date("%b %d %H:%M", d.t), C.muted)
    if d.item then det:Text("Quantity: " .. (d.n or 1), C.muted) end
    det:Gap()
    if officer then
      if d.void then
        det:Buttons({ { "Restore", function() ns.VoidDonation(key, false) end } })
      else
        det:Buttons({ { "Void (logged by mistake)", function() ns.VoidDonation(key, true) end,
          tip = "Keeps the record but stops it counting toward donor totals." } })
      end
    end

  elseif kind == "crafter" then
    local c = g.crafters[key]
    if not c then return UI:CloseDetails() end
    det:Reset(nil, nil, ns.WhoLabel(key), "Level " .. tostring(c.lvl or "?") .. (Online(key) and "  ·  |cff4ade80online|r" or ""))
    local profs = {}
    for p in pairs(c.profs or {}) do profs[#profs + 1] = p end
    table.sort(profs)
    local rec = g.recipes[key] and g.recipes[key].profs or {}
    for _, p in ipairs(profs) do
      local n = rec[p] and (#(rec[p].items or {}) + #(rec[p].spells or {})) or 0
      det:Text((ns.IsDesignated(key, p) and (STAR .. " ") or "") .. p .. ": " .. c.profs[p]
        .. (n > 0 and ("  |cff7e8590(" .. n .. " recipes, updated " .. Ago(rec[p].at or g.recipes[key].t) .. ")|r") or "  |cff7e8590(recipes not shared yet)|r"))
      if officer then
        local des = ns.IsDesignated(key, p)
        det:Buttons({ { des and ("Remove as guild " .. p:lower()) or ("Make guild " .. p:lower()), function()
          ns.SetDesignated(p, key, not des)
        end, tip = "Guild crafters get a star and are listed first for everyone." } })
      end
    end
    local alts = ns.AltsOf(ns.MainOf(key))
    if #alts > 0 then det:Text("Characters: " .. ns.MainOf(key) .. ", " .. table.concat(alts, ", "), C.muted) end
    det:Gap()
    det:Buttons({ { "Whisper", function()
      if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. key .. " ") end
    end, accent = true }, { "Show recipes", function()
      UI.state.recipes.crafter = key
      UI:SetView("recipes")
    end } })

  elseif kind == "recipe" then
    local e
    for _, x in ipairs(ns.RecipeIndex()) do if x.key == key then e = x end end
    if not e then return UI:CloseDetails() end
    local name = e.item and ns.ItemName(e.item, true) or e.name
    det:Reset(e.item and ns.ItemIcon(e.item) or "Interface\\Icons\\Trade_Engraving", e.item and Quality(e.item) or 1,
      name, e.prof .. "  ·  " .. #e.crafters .. (#e.crafters == 1 and " crafter" or " crafters"))
    if e.item then det:Text("In bank: " .. ns.BankCount(e.item), C.muted) end
    local mats = MatsLines(key)
    if #mats > 0 then
      local n = ns.CraftsCovered(key) or 0
      det:Text(n > 0 and ("|cff4ade80Bank materials cover " .. n .. (n == 1 and " craft" or " crafts") .. "|r")
        or "The bank doesn't have the materials for one yet.", n > 0 and C.text or C.muted)
      if officer then
        det:Buttons({ { "Stock mats for 5 crafts", function() ns.StockMatsFor(key, 5) end,
          tip = "Raises the bank's needs so it keeps enough of each material for 5 crafts." } })
      end
    end
    det:Gap()
    local list = {}
    for _, cr in ipairs(e.crafters) do list[#list + 1] = cr end
    table.sort(list, function(a, b)
      local da, db = ns.IsDesignated(a.who, a.prof), ns.IsDesignated(b.who, b.prof)
      if da ~= db then return da end
      local oa, ob = Online(a.who), Online(b.who)
      if oa ~= ob then return oa end
      return a.who < b.who
    end)
    for _, cr in ipairs(list) do
      local who = cr.who
      local skill = cr.diff and ("  |cff" .. DIFF[cr.diff][1] .. "skill-up (" .. DIFF[cr.diff][2] .. ")|r") or ""
      det:Text((ns.IsDesignated(who, cr.prof) and (STAR .. " ") or "") .. ns.WhoLabel(who)
        .. "  |cff7e8590" .. cr.prof .. " " .. tostring(cr.rank or "?") .. "|r" .. (Online(who) and "  |cff4ade80online|r" or "")
        .. skill .. "\n|cff7e8590updated " .. Ago(cr.at) .. "|r")
      det.y = det.y + 2
      local short = who:match("^(%S+)") or who
      local specs = { { "Whisper " .. short, function()
        if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. who .. " ") end
      end } }
      if who ~= ns.me then
        table.insert(specs, 1, { "Ask " .. short .. " to craft", function() UI:OpenDetails("craftask", key .. "\n" .. who) end,
          accent = true, tip = "Send " .. short .. " a craft request. They get a pop-up and can accept it." })
      end
      det:Buttons(specs)
    end
    if #list > 0 then det:Text(SkillMark("o") .. " Orange always gives the crafter a skill point, yellow usually, green sometimes.", C.muted) end
    if e.item then
      det:Gap()
      det:Buttons({ { "Request one from the bank", function()
        UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(e.item)); UI.qtyBox:SetFocus()
      end } })
    end
  end
  det:Finish()
end

---------------------------------------------------------------------------
-- Sidebar navigation
---------------------------------------------------------------------------
UI.nav = {}
do
  local y = -8
  for _, key in ipairs(ORDER) do
    local v = Views[key]
    local b = CreateFrame("Button", nil, side)
    b:SetSize(SIDEBAR_W - 12, 28)
    b:SetPoint("TOPLEFT", 6, y)
    b.bg = Tex(b, "BACKGROUND", C.panel2)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.strip = Tex(b, "BORDER", C.gold)
    b.strip:SetPoint("TOPLEFT"); b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetWidth(2)
    b.strip:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 8, 0)
    b.icon:SetTexture(v.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = Font(b, 12, C.muted)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:SetText(v.label)
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(22, 14)
    b.badge:SetPoint("RIGHT", -6, 0)
    b.badge.bg = Tex(b.badge, "BACKGROUND", C.goldBg)
    b.badge.bg:SetAllPoints()
    b.badge.text = Font(b.badge, 10, C.gold)
    b.badge.text:SetPoint("CENTER")
    b.badge.text:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self) if UI.view ~= self.key then self.bg:Show() end end)
    b:SetScript("OnLeave", function(self) if UI.view ~= self.key then self.bg:Hide() end end)
    b:SetScript("OnClick", function(self) UI:SetView(self.key) end)
    b.key = key
    b.baseY = y
    UI.nav[key] = b
    y = y - 30
  end
end

---------------------------------------------------------------------------
-- Layout / view switching / refresh
---------------------------------------------------------------------------
function UI:Layout()
  local v = Views[self.view]
  local showComposer = v and not v.custom and v.composer ~= nil and (v.composer ~= "need" or ns.IsTrusted(ns.me))
  composer:SetShown(showComposer)
  composer:SetHeight(showComposer and COMPOSER_H or 0.01)
  listArea:ClearAllPoints()
  listArea:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT")
  if det:IsShown() then
    listArea:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT", -DETAILS_W, 0)
  else
    listArea:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT")
  end
  -- composer contents
  if showComposer then
    local need = (v.composer == "need")
    self.composerMode = v.composer
    local officerFor = (not need) and ns.IsTrusted(ns.me)
    local wantFor = (not need) and (officerFor or #ns.MyChars() > 1)
    local width = (composer:GetWidth() or 500)
    self.noteBox:SetShown(not need)
    self.kindBtn:SetShown(need)
    self.forBtn:SetShown(wantFor and not officerFor)
    self.forBox:SetShown(officerFor)
    local tight = width < 560
    local noteW = officerFor and (tight and 80 or 100) or 120
    local forW = officerFor and (tight and 92 or 110) or 104
    self.noteBox:SetWidth(noteW)
    self.forBox:SetWidth(forW)
    local itemW = width - 10 - 46 - 6 - 6 - 90 - 20
    if need then itemW = itemW - 96 - 6 else itemW = itemW - noteW - 6 - (wantFor and (forW + 6) or 0) end
    itemW = math.max(110, itemW)
    self.itemBox:SetWidth(itemW)
    self.itemBox.ph:SetText(itemW >= 200 and "Item: shift-click or drag it here" or (itemW >= 150 and "Item: shift-click or drag" or "Item (shift-click)"))
    self.action:SetLabel(need and "Set need" or "Request")
    if wantFor and not officerFor then self:UpdateForButton() end
  end
end

function UI:SetView(key)
  if Views[key] and Views[key].officer and not ns.IsTrusted(ns.me) then key = "needs" end
  if not Views[key] then key = "needs" end
  if self.view ~= key then
    if det:IsShown() then det:Hide(); det.kind, det.key = nil, nil; self.selected = nil end
    self.forIndex = 1
  end
  self.view = key
  for k, b in pairs(self.nav) do
    local on = (k == key)
    b.bg:SetShown(on); b.strip:SetShown(on)
    SetColor(b.label, on and C.white or C.muted)
  end
  for _, v in pairs(Views) do if v.bar then v.bar:Hide() end end
  local v = Views[key]
  if not v.bar then v.bar = NewBar(v); UI.bars = UI.bars or {}; UI.bars[key] = v.bar end
  v.bar:Show()
  officerScroll:SetShown(v.custom == true)
  officerPage:Show()
  scroll:SetShown(not v.custom)
  scroll:SetVerticalScroll(0)
  self:Layout()
  self:Refresh()
end

-- Old tab names (used by tests and older habits)
local TAB_ALIASES = { Needs = "needs", Shopping = "shopping", Bank = "bank", Requests = "requests",
  Donations = "donations", Crafters = "crafters", Officer = "officer" }
function UI:SetTab(name) self:SetView(TAB_ALIASES[name] or name) end

function UI:Refresh()
  if not self:IsShown() or not self.view then return end
  local g = ns.G()
  local officer = ns.IsTrusted(ns.me)

  -- sidebar: officer page visibility, badges
  local y = -8
  local nVisible = 0
  for _, key in ipairs(ORDER) do if not Views[key].officer or officer then nVisible = nVisible + 1 end end
  local step = math.max(22, math.min(30, math.floor(((side:GetHeight() or 400) - 64) / nVisible)))
  for _, key in ipairs(ORDER) do
    local b, v = self.nav[key], Views[key]
    local visible = not v.officer or officer
    b:SetShown(visible)
    if visible then
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6, y); y = y - step
      local n, bg, fg = 0, C.goldBg, C.gold
      if g and v.count then
        local ok, a, b2, c2 = pcall(v.count, g)
        if ok then n, bg, fg = a, b2 or bg, c2 or fg else n = 0 end
      end
      if n and n > 0 then
        b.badge.text:SetText(n > 99 and "99+" or tostring(n))
        b.badge.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
        SetColor(b.badge.text, fg)
        b.badge:SetWidth(math.max(20, (b.badge.text:GetStringWidth() or 10) + 10))
        b.badge:Show()
      else
        b.badge:Hide()
      end
    end
  end
  if Views[self.view].officer and not officer then return self:SetView("needs") end

  if not g then
    ShowRows({}, 400)
    self.empty:SetText("Join a guild to use EPU Guild Tools.")
    self.empty:Show()
    self.footerText:SetText("")
    goldText:SetText("")
    syncText:SetText("")
    return
  end

  local gold = 0
  for _, s in pairs(g.bank) do if not s.retired then gold = gold + (s.money or 0) end end
  goldText:SetText(Money(gold) .. "  |cff7e8590on hand|r")
  if ns.newestVersion then
    syncText:SetText("|cfff2c14eUpdate available: v" .. ns.newestVersion .. "|r")
  elseif ns.SyncStatus then
    local label, tone = ns.SyncStatus()
    local hex = (tone == "green" and "6fcf73") or (tone == "gold" and "f2c14e") or "7e8590"
    syncText:SetText("|cff" .. hex .. label .. "|r")
  else
    syncText:SetText("v" .. ns.VERSION)
  end

  local v = Views[self.view]
  -- toolbar chip states
  local bar = v.bar
  if bar then
    local stKey = v.stateKey or (v == Views.requests and "requests") or (v == Views.needs and "needs") or (v == Views.crafters and "crafters") or nil
    for _, chip in ipairs(bar.chips) do chip:SetOn(stKey and self.state[stKey].filter == chip.key) end
    if v == Views.requests then self.craftsChip:SetOn(self.state.requests.crafts == true) end
    if v == Views.bank then
      self.bankCatChip:SetLabel(self.state.bank.cat or "All categories")
      self.bankCatChip:SetOn(self.state.bank.cat ~= nil)
    end
    if v == Views.roster then
      local st = self.state.roster
      self.roleChip:SetLabel(st.role and ns.ROLES[st.role] or "Any role")
      self.roleChip:SetOn(st.role ~= nil)
      local labels = { inactive = "Inactive", promote = "Promote?", note = "Has note" }
      self.reviewChip:SetLabel(st.review and labels[st.review] or "Review")
      self.reviewChip:SetOn(st.review ~= nil)
      self.reviewChip:SetShown(ns.IsTrusted(ns.me))
    end
    if v == Views.news then self.newsBtn:SetShown(ns.IsTrusted(ns.me)) end
    if v == Views.crafters then
      local pf = self.state.crafters.prof
      self.crafterProfChip:SetLabel(pf or "All professions")
      self.crafterProfChip:SetOn(pf ~= nil)
    end
    if v == Views.recipes then
      local st = self.state.recipes
      self.skillChip:SetOn(st.skillup)
      self.profChip:SetLabel(st.prof or "All professions")
      self.profChip:SetOn(st.prof ~= nil)
      self.onlineChip:SetOn(st.online)
      self.desChip:SetOn(st.designated)
      self.crafterChip:SetShown(st.crafter ~= nil)
      if st.crafter then self.crafterChip:SetLabel((st.crafter:match("^(%S+)") or st.crafter) .. "  x") self.crafterChip:SetOn(true) end
    end
    if v == Views.requests then
      self.mineChip:SetOn(self.state.requests.mine)
      for _, s in ipairs(SORTS) do if s[1] == self.state.requests.sort then self.sortChip:SetLabel("Sort: " .. s[2]) end end
      for _, f in ipairs(REQ_FILTERS) do
        if f[1] == self.state.requests.filter then self.statusChip:SetLabel((f[2]:match("^([^/,]+)") or f[2]):gsub("%s+$", "")) end
      end
      self.statusChip:SetOn(self.state.requests.filter ~= "open")
    end
  end

  if v.custom then
    RefreshOfficerPage(g)
    self.empty:Hide()
    self.footerText:SetText("Only officers see this page. Changes here are checked by everyone's addon.")
    return
  end

  local width = (scroll:GetWidth() or 400)
  child:SetWidth(width)
  local okRows, rows = ns.SafeCall(v.rows, g, Q())
  if not okRows then
    -- never leave the last page's rows on screen under this page's name
    local e = rows
    local where = e.where and (" in " .. e.where) or ""
    local key = (v.label or "?") .. where .. e.raw
    if self.rowErr ~= key then
      self.rowErr = key
      ns.Print("|cffff6060The " .. (v.label or "") .. " page couldn't load|r (v" .. ns.VERSION .. where .. "): " .. e.plain)
      ns.Print("|cff9aa1abDetails: " .. e.raw .. "|r")
    end
    ShowRows({}, width)
    self.empty:SetText("|cffff6060The " .. (v.label or "") .. " page couldn't load.|r\n\n"
      .. "|cffffffffWhat went wrong:|r " .. e.plain .. "\n"
      .. "|cffffffffWhere:|r " .. (e.where or "unknown") .. ", addon v" .. ns.VERSION .. "\n\n"
      .. "|cff9aa1ab" .. e.raw:sub(1, 240) .. "|r\n\n"
      .. "Try /reload. If it keeps happening, send a screenshot of this to an officer.")
    self.empty:Show()
    self.footerText:SetText("")
    return
  end
  ShowRows(rows, width)
  self.empty:SetWidth(math.max(200, width - 60))
  local emptyText = v.empty
  local g0 = ns.G()
  if Q() == "" and g0 and not g0.syncedAt and not ns.IsTrusted(ns.me) then
    -- a member who hasn't received the guild's data yet
    emptyText = (emptyText and (emptyText .. "\n\n") or "")
      .. "|cfff2c14eWaiting for guild data.|r It arrives by itself as soon as an officer\n"
      .. "(or a guildmate with the addon) is online. Nothing to do on your end."
  end
  self.empty:SetText(Q() ~= "" and ("Nothing matches \"" .. Q() .. "\".") or emptyText)
  self.empty:SetShown(#rows == 0)
  local foot = v.footer and v.footer(g) or ""
  if ns.HasUnconfirmed and ns.HasUnconfirmed() then
    foot = "|cfff2c14eUnconfirmed:|r passed on by a guildmate; an officer's addon will check it." .. ((foot ~= "") and ("  " .. foot) or "")
  end
  self.footerText:SetText(foot)
  UpdateThumb()
  -- don't wipe what an officer is typing in the details panel
  if det:IsShown() and not (self.focusBox and self.focusBox:GetParent() == det.body) then self:FillDetails() end
end

UI:SetScript("OnShow", function(self)
  ns.RequestRoster()
  if not self.view then self:SetView("needs") else self:Layout(); self:Refresh() end
end)

ns.On("PLAYER_LOGIN", function() UI:RestoreLayout() end)
ns.On("MAIL_SHOW", function() if UI:IsShown() then UI:Refresh() end end)

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mb = CreateFrame("Button", "EPUGuildMinimapButton", Minimap)
mb:SetSize(31, 31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mbIcon = mb:CreateTexture(nil, "BACKGROUND")
mbIcon:SetTexture(ns.LOGO_SMALL)
mbIcon:SetSize(21, 21)
mbIcon:SetPoint("TOPLEFT", 6, -5)
local mbBorder = mb:CreateTexture(nil, "OVERLAY")
mbBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mbBorder:SetSize(53, 53)
mbBorder:SetPoint("TOPLEFT")

local function PlaceButton()
  local a = math.rad(ns.db.settings.minimapAngle or 200)
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

function ns.UpdateMinimapButton()
  if ns.db.settings.hideMinimap then mb:Hide() else mb:Show(); PlaceButton() end
end

mb:SetScript("OnClick", function(_, button)
  if button == "RightButton" then ns.FullSync() else UI:Toggle() end
end)
mb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    ns.db.settings.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
    PlaceButton()
  end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("EPU Guild Tools")
  GameTooltip:AddLine("Left-click: open window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: resync with officers", 1, 1, 1)
  GameTooltip:AddLine("Drag: move button", 1, 1, 1)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", GameTooltip_Hide)

ns.On("PLAYER_LOGIN", ns.UpdateMinimapButton)

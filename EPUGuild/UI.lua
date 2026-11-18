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
  bg     = { 0.056, 0.066, 0.086 },
  panel  = { 0.078, 0.089, 0.113 },
  panel2 = { 0.109, 0.142, 0.196 },
  hover  = { 0.137, 0.153, 0.180 },
  line   = { 0.176, 0.192, 0.224 },
  input  = { 0.071, 0.078, 0.094 },
  text   = { 0.85, 0.86, 0.88 },
  muted  = { 0.64, 0.69, 0.76 },
  white  = { 1, 1, 1 },
  gold   = { 0.95, 0.76, 0.31 },
  goldBg = { 0.17, 0.14, 0.07 },
  selected = { 0.26, 0.21, 0.12 },
  selectedHover = { 0.33, 0.27, 0.15 },
  disabled = { 0.09, 0.10, 0.12 },
  disabledText = { 0.49, 0.52, 0.57 },
  green  = { 0.29, 0.87, 0.50 },
  greenBg= { 0.07, 0.19, 0.11 },
  red    = { 1.00, 0.42, 0.42 },
  redBg  = { 0.23, 0.09, 0.09 },
  blue   = { 0.43, 0.66, 1.00 },
}
ns.InterfaceColors=C
local PILL = {
  pending  = { "Pending",  C.goldBg,  C.gold },
  sync_wait   = { "Requested",   C.goldBg, C.gold },
  sync_ok     = { "Reported",    C.greenBg, C.green },
  sync_none   = { "No report",   C.panel2, C.muted },
  sync_noseen = { "No addon seen", C.panel2, C.muted },
  sync_host   = { "Officer copy", C.panel2, C.text },
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
local locale=GetLocale and GetLocale()
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local fallbackFont = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local localizedFont = locale=="koKR" or locale=="zhCN" or locale=="zhTW"
local FONT = localizedFont and fallbackFont or MEDIA .. "Fonts\\Inter-Regular.ttf"
local HEADING = localizedFont and fallbackFont or MEDIA .. "Fonts\\Inter-SemiBold.ttf"
local SIDEBAR_W, SUBNAV_W = 88, 158
local HEADER_H, TOOLBAR_H, COMPOSER_H, FOOTER_H, ROW_H, DETAILS_W = 36, 34, 36, 24, 40, 300

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

local function Font(parent, size, c, layer, heading)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  if fs:SetFont(heading and HEADING or FONT, size or 12, "") == false then
    fs:SetFont(fallbackFont, size or 12, "")
  end
  fs:SetTextColor((c or C.text)[1], (c or C.text)[2], (c or C.text)[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end
ns.InterfaceFont = Font

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function TextWidth(fs)
  return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

-- style: nil (plain), "accent" (gold), "chip" (rounded-ish filter chip)
local function Btn(parent, label, w, h, style)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 80, h or 22)
  b.style = style
  b.bg = Tex(b, "BACKGROUND", C.panel)
  b.bg:SetAllPoints()
  Edges(b, C.line)
  b.mark = Tex(b, "BORDER", C.gold)
  b.mark:SetPoint("BOTTOMLEFT",1,1); b.mark:SetPoint("BOTTOMRIGHT",-1,1); b.mark:SetHeight(2)
  b.text = Font(b, 12, C.text)
  b.text:SetPoint("LEFT",5,0); b.text:SetPoint("RIGHT",-5,0)
  b.text:SetJustifyH("CENTER")
  b.text:SetText(label or "")
  local function Paint(self)
    local off, on, accent = self.disabled, self.on == true, self.style == "accent"
    local bg = off and C.disabled or on and (self.hovered and C.selectedHover or C.selected)
      or accent and C.gold or self.hovered and C.hover or C.panel
    self.bg:SetColorTexture(bg[1],bg[2],bg[3],1)
    EdgeColor(self, not off and (on or accent) and C.gold or C.line)
    SetColor(self.text,off and C.disabledText or on and C.gold or accent and C.bg or C.text)
    self.mark:SetShown(on and not off)
    if self.icon then self.icon:SetAlpha(off and 0.42 or 1) end
    if self.arrow then self.arrow:SetAlpha(off and 0.42 or 1) end
  end
  if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
  b:SetScript("OnEnter", function(self)
    self.hovered = true
    Paint(self)
    local reason = self.disabled and self.disabledTip or self.tip
    local truncated = TextWidth(self.text)>(self.text:GetWidth() or 0)+1
    if not reason and not truncated then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(self.fullLabel or self:GetText(), 1, 1, 1, 1, true)
    if reason then GameTooltip:AddLine(reason,C.muted[1],C.muted[2],C.muted[3],true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.hovered = false
    Paint(self)
    GameTooltip_Hide()
  end)
  b:SetScript("OnHide",function(self)
    self.hovered = false
    Paint(self)
  end)
  function b:SetLabel(t) self.text:SetText(t) end
  b.SetText = b.SetLabel
  function b:GetText() return self.text:GetText() end
  function b:SetIcon(texture)
    if not self.icon then
      self.icon = self:CreateTexture(nil, "ARTWORK")
      self.icon:SetSize(14, 14)
      self.icon:SetPoint("LEFT", 7, 0)
      self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      self.text:ClearAllPoints()
      self.text:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
      self.text:SetPoint("RIGHT", -5, 0)
      self.text:SetJustifyH("LEFT")
    end
    self.icon:SetTexture(texture)
    Paint(self)
  end
  function b:SetOn(on)
    self.on = on == true
    Paint(self)
  end
  b:SetScript("OnDisable", function(self)
    self.disabled = true
    self.hovered = false
    Paint(self)
  end)
  b:SetScript("OnEnable", function(self) self.disabled=false; Paint(self) end)
  Paint(b)
  return b
end
ns.InterfaceButton = Btn

function ns.InterfaceWindow(name, parent, heading, width, height)
  local frame=CreateFrame("Frame",name,parent)
  frame:SetSize(width,height)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  Tex(frame,"BACKGROUND",C.bg):SetAllPoints()
  Edges(frame,C.line)
  frame.TitleText=Font(frame,16,C.white)
  frame.TitleText:SetPoint("TOPLEFT",14,-10)
  frame.TitleText:SetText(heading)
  local close=Btn(frame,"×",24,22)
  close:SetPoint("TOPRIGHT",-7,-6)
  close:SetScript("OnClick",function() frame:Hide() end)
  local rule=Tex(frame,"BORDER",C.line)
  rule:SetPoint("TOPLEFT",1,-34); rule:SetPoint("TOPRIGHT",-1,-34); rule:SetHeight(1)
  tinsert(UISpecialFrames,name)
  return frame
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
  if e:SetFont(FONT, 12, "") == false then e:SetFont(fallbackFont, 12, "") end
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
ns.InterfaceInput = Box

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
local bankCategoryItems = {
  Cloth=2589, Leather=2318, ["Metal & Stone"]=2770, Herbs=765, Cooking=2672, Enchanting=10940,
  Elemental=7067, ["Parts & Engineering"]=4357, ["Other Trade Goods"]=2320, Consumables=118,
  Reagents=17020, Bags=4496, ["Weapons & Armor"]=25, Recipes=2881,
}
local function BankCategoryIcon(category)
  local item = bankCategoryItems[category]
  return item and ns.ItemIcon(item) or "Interface\\Icons\\INV_Misc_Bag_10"
end

-- Dropdown menu: a flat list that opens under a button.
-- items = { { label =, value =, right =, icon = } ... }
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
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(15, 15); r.icon:SetPoint("LEFT", 9, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.text = Font(r, 11); r.text:SetPoint("LEFT", 31, 0)
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
    r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_Note_01")
    r.text:SetText(it.label); SetColor(r.text, on and C.gold or C.text)
    r.right:SetText(it.right or "")
    w = math.max(w, 46 + r.text:GetStringWidth() + r.right:GetStringWidth())
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
UI.bg = Tex(UI, "BACKGROUND", C.bg)
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
Tex(header, "BACKGROUND", C.panel2):SetAllPoints()
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
local title = Font(header, 16, C.white)
title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
title:SetText("EPU Guild Tools")

local closeBtn = IconBtn(header, "Interface\\Buttons\\UI-StopButton", "Close")
closeBtn:SetPoint("RIGHT", -8, 0)
closeBtn:SetScript("OnClick", function() UI:Hide() end)
local syncBtn = IconBtn(header, "Interface\\Buttons\\UI-RefreshButton", "Sync with online officers")
syncBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
syncBtn:SetScript("OnClick", function() ns.FullSync() end)

UI.search = Box(header, 260, "Search items, members...")
UI.search:SetPoint("LEFT", title, "RIGHT", 18, 0)
UI.search:SetPoint("RIGHT", syncBtn, "LEFT", -10, 0)
UI.search:SetTextInsets(22, 28, 0, 0)
UI.search.ph:SetPoint("LEFT", 22, 0)
local mag = UI.search:CreateTexture(nil, "OVERLAY")
mag:SetSize(14, 14)
mag:SetPoint("LEFT", 5, 0)
mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
UI.clearSearch = IconBtn(UI.search, "Interface\\Buttons\\UI-StopButton", "Clear search", 18)
UI.clearSearch:SetPoint("RIGHT", -3, 0)
UI.clearSearch:SetFrameLevel(UI.search:GetFrameLevel()+2)
UI.clearSearch:Hide()
UI.clearSearch:SetScript("OnClick", function() UI.search:SetText(""); UI.search:ClearFocus() end)
UI.search.onChange = function()
  UI.clearSearch:SetShown((UI.search:GetText() or "")~="")
  UI:Refresh()
end
UI.search.onEnter = function()
  if UI.view=="market" or UI.view=="officer" or UI.search:GetText()=="" then return end
  for _, row in ipairs(UI.rows or {}) do
    if row:IsShown() and row.data and row.data.onClick then row:Click(); return end
  end
end

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

local sectionTabs=CreateFrame("Frame",nil,UI)
sectionTabs:SetPoint("TOPLEFT"); sectionTabs:SetPoint("TOPRIGHT")
sectionTabs:SetHeight(30)
local sectionBg=Tex(sectionTabs,"BACKGROUND",C.panel)
sectionBg:SetAllPoints()
local sectionLine=Tex(sectionTabs,"BORDER",C.line)

local page=CreateFrame("Frame",nil,content)
page:SetPoint("TOPLEFT",sectionTabs,"BOTTOMLEFT")
page:SetPoint("TOPRIGHT",sectionTabs,"BOTTOMRIGHT")
page:SetHeight(48)
local pageArt=page:CreateTexture(nil,"BACKGROUND")
pageArt:SetAllPoints()
pageArt:SetTexture(MEDIA .. "midnight.tga")
UI.pageTitle=Font(page,23,C.white,nil,true)
UI.pageTitle:SetPoint("LEFT",12,0)
UI.pageStatus=Font(page,11,C.muted)
UI.pageStatus:SetPoint("RIGHT",-12,0)
UI.pageStatus:SetJustifyH("RIGHT")
UI.clearFilters=Btn(page,"Clear filters",104,23)
UI.clearFilters:SetPoint("RIGHT",-12,0)
UI.clearFilters:Hide()
UI.filterCount=Font(page,11,C.muted)
UI.filterCount:SetPoint("RIGHT",UI.clearFilters,"LEFT",-10,0)
UI.filterCount:Hide()
function UI:SetFilterSummary(shown,total,clear)
  local active=clear~=nil
  self.clearFilters:SetShown(active)
  self.filterCount:SetShown(active)
  self.pageStatus:SetShown(not active)
  if not active then return end
  self.filterCount:SetText(shown.." of "..total.." shown")
  self.clearFilters:SetScript("OnClick",clear)
end

local toolbar = CreateFrame("Frame", nil, content)
toolbar:SetPoint("TOPLEFT",page,"BOTTOMLEFT"); toolbar:SetPoint("TOPRIGHT",page,"BOTTOMRIGHT")
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
footer:EnableMouse(true)
footer:SetScript("OnEnter",function(self)
  if TextWidth(UI.footerText)<=UI.footerText:GetWidth()+1 then return end
  GameTooltip:SetOwner(self,"ANCHOR_TOP")
  GameTooltip:SetText(UI.footerText:GetText(),1,1,1,1,true)
  GameTooltip:Show()
end)
footer:SetScript("OnLeave",GameTooltip_Hide)

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
UI.empty:SetNonSpaceWrap(true)
UI.emptyAction=Btn(listArea,"",138,26)
UI.emptyAction:SetPoint("TOP",UI.empty,"BOTTOM",0,-12)
UI.emptyAction:Hide()

-- Resize grip
local grip = CreateFrame("Button", nil, UI)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() UI:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() UI:StopMovingOrSizing(); UI:SaveLayout(); UI:Refresh() end)

UI:SetScript("OnSizeChanged", function()
  if UI:IsShown() then ns.Debounce("uiresize", 0.05, function() UI:Layout(); UI:Refresh() end) end
end)

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
    GameTooltip:SetText(d.title or "", 1, 1, 1, 1, true)
  end
  if d.sub and self.sub:IsShown() and TextWidth(self.sub)>self.sub:GetWidth()+1 then
    GameTooltip:AddLine(d.sub,C.muted[1],C.muted[2],C.muted[3],true)
  end
  if d.right and self.right:IsShown() and TextWidth(self.right)>self.right:GetWidth()+1 then
    GameTooltip:AddLine(d.right,1,1,1,true)
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
  if not UI.selected or not self.data or UI.selected.key~=self.data.key then self.hl:Hide() end
  GameTooltip_Hide()
end

local function RowClick(self, button)
  local d = self.data
  if not d then return end
  if button == "RightButton" then
    if d.onRightClick then d.onRightClick(self) end
    return
  end
  if d.item and IsModifiedClick("CHATLINK") then
    local _, link = GetItemInfo(d.item)
    if link then ChatEdit_InsertLink(link) end
    return
  end
  if d.onClick then
    UI.detailHistory=nil
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
  r.card = Tex(r, "BACKGROUND", C.panel)
  r.card:SetAllPoints()
  r.hl = Tex(r, "BORDER", C.hover)
  r.hl:SetAllPoints()
  r.selectedMark = Tex(r,"BORDER",C.gold)
  r.selectedMark:SetPoint("TOPLEFT"); r.selectedMark:SetPoint("BOTTOMLEFT")
  r.selectedMark:SetWidth(2)
  r.hl:Hide()
  r.sep = Tex(r, "BORDER", C.line, 0.45)
  r.sep:SetPoint("BOTTOMLEFT", 8, 0); r.sep:SetPoint("BOTTOMRIGHT", -8, 0); r.sep:SetHeight(1)

  r.qb = Tex(r, "BORDER", C.white)
  r.qb:SetSize(30, 30)
  r.qb:SetPoint("LEFT", 10, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("CENTER", r.qb, "CENTER")
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.dot = Tex(r, "OVERLAY", C.green)
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
  r.stock = Font(r, 12, C.muted)
  r.stock:SetJustifyH("RIGHT")

  r:SetScript("OnEnter", RowEnter)
  r:SetScript("OnLeave", RowLeave)
  r:SetScript("OnClick", RowClick)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  UI.rows[i] = r
  return r
end

-- Home is laid out as a dashboard: full-width cards (message of the day,
-- needs attention), a row of stat tiles, then two panes of sections side by
-- side (d.pane = 1 or 2), then a grid of shortcut cards.  Other views are a
-- plain list.
local function HomePlacer(width)
  local gap = 10
  local twoPane = width >= 600
  local paneW = math.floor((width - gap * 3) / 2)
  local y, gridCols, gridCol, gridH = 12, 0, 0, 0
  local paneY
  local function CloseGrid()
    if gridCol > 0 then y = y + gridH + gap end
    gridCol, gridH = 0, 0
  end
  local function ClosePanes()
    if paneY then y = math.max(paneY[1], paneY[2]) + 4; paneY = nil end
  end
  local place = {}
  function place.Height(d)
    return d.section and 28 or d.tile and 52 or d.compact and 44 or 58
  end
  function place.Next(d)
    local h = place.Height(d)
    if d.pane and twoPane then
      CloseGrid()
      if not paneY then paneY = { y, y } end
      local p = d.pane == 2 and 2 or 1
      local x, top = gap + (p - 1) * (paneW + gap), paneY[p]
      paneY[p] = top + h + (d.section and 2 or 6)
      return x, top, paneW, h
    elseif d.featured or d.section or d.pane then
      CloseGrid(); ClosePanes()
      local top = y
      y = y + h + (d.section and 2 or (d.pane and 6 or gap))
      return gap, top, width - gap * 2, h
    end
    ClosePanes()
    local n = d.tile and (width >= 600 and 4 or 2) or (width >= 460 and 2 or 1)
    if gridCols ~= n then CloseGrid(); gridCols = n end
    local w = math.floor((width - gap * (n + 1)) / n)
    local x = gap + gridCol * (w + gap)
    gridH = math.max(gridH, h)
    gridCol = gridCol + 1
    local top = y
    if gridCol == n then y = y + gridH + gap; gridCol, gridH = 0, 0 end
    return x, top, w, h
  end
  function place.Total() CloseGrid(); ClosePanes(); return y end
  return place
end

local function ShowRows(data, width, viewIcon)
  local home = UI.view == "home"
  local place = home and HomePlacer(width)
  local y = 0
  for i, d in ipairs(data) do
    local r = GetRow(i)
    r.data = d
    local x, top, rowWidth, height = 0, y, width, ROW_H
    if home then x, top, rowWidth, height = place.Next(d) else y = y + ROW_H end
    r:SetSize(rowWidth, height)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", x, -top)
    r.card:SetShown(home and not d.section)
    local cardColor = d.featured and C.goldBg or C.panel
    r.card:SetColorTexture(cardColor[1], cardColor[2], cardColor[3], 1)
    r.sep:SetShown(not home)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", 48, home and (d.compact and -24 or -30) or -22)

    -- icon / quality border / online dot
    local icon = d.icon or ((d.onClick or d.dot ~= nil) and viewIcon)
    if icon then
      r.icon:SetTexture(icon); r.icon:Show()
      r.icon:SetTexCoord(unpack(d.iconCoords or {0.08, 0.92, 0.08, 0.92}))
      local q = d.qcolor or C.line
      r.qb:SetColorTexture(q[1], q[2], q[3], 1); r.qb:Show()
    else
      r.icon:Hide(); r.qb:Hide()
    end
    if d.dot ~= nil then
      local c = d.dot and C.green or C.panel2
      r.dot:ClearAllPoints()
      if icon then r.dot:SetPoint("BOTTOMRIGHT", r.qb, "BOTTOMRIGHT", 1, -1)
      else r.dot:SetPoint("LEFT", 21, 0) end
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
      r.right:SetWidth(math.max(1,math.min(TextWidth(r.right)+1,rowWidth*0.26)))
      SetColor(r.right, d.rightColor or C.text)
      r.right:SetPoint("RIGHT", r, "RIGHT", -rightEdge - 4, d.frac and 4 or 0)
      r.right:Show()
      rightEdge = rightEdge + r.right:GetWidth() + 12
    else
      r.right:Hide()
    end

    r.stock:ClearAllPoints()
    r.stock:SetShown(d.stock ~= nil)
    if d.stock ~= nil then
      r.stock:SetPoint("RIGHT",r,"RIGHT",-92,0)
      r.stock:SetText(d.stock)
      r.right:ClearAllPoints()
      r.right:SetPoint("RIGHT",r,"RIGHT",-14,0)
      r.right:SetWidth(76)
      r.stock:SetWidth(48)
      rightEdge=140
    end
    local textW = math.max(60, rowWidth - 48 - rightEdge - 6)
    r.title:SetWidth(textW)
    r.title:SetText(d.title or "")
    SetColor(r.title, d.titleColor or C.text)
    r.title:ClearAllPoints()
    if d.sub or d.frac then r.title:SetPoint("TOPLEFT", 48, home and (d.compact and -8 or -11) or -5) else r.title:SetPoint("LEFT", 48, 0) end

    if d.frac then
      r.sub:Hide()
      local w = math.max(40, rowWidth - 48 - rightEdge - 6)
      r.barBg:SetWidth(w); r.barBg:Show()
      local c = d.barColor or C.green
      r.bar:SetColorTexture(c[1], c[2], c[3], 1)
      r.bar:SetWidth(math.max(1, w * math.min(1, d.frac)))
      r.bar:SetShown(d.frac > 0)
    else
      r.barBg:Hide(); r.bar:Hide()
      if d.sub then r.sub:SetWidth(textW); r.sub:SetText(d.sub); r.sub:Show() else r.sub:Hide() end
    end

    -- table-style columns: name, then fixed or "flex" width cells on one line
    r.cols = r.cols or {}
    local used = 0
    if d.columns and not home and rowWidth >= 480 then
      local titleW = d.titleWidth or 160
      local fixed, flexCount = 0, 0
      for _, c in ipairs(d.columns) do if c.w == "flex" then flexCount = flexCount + 1 else fixed = fixed + c.w end end
      local flexW = math.max(50, math.floor((rowWidth - 48 - titleW - fixed - rightEdge - 8) / math.max(1, flexCount)))
      r.title:SetWidth(titleW - 6); r.title:ClearAllPoints(); r.title:SetPoint("LEFT", 48, 0)
      r.sub:Hide()
      local x = 48 + titleW
      for ci, c in ipairs(d.columns) do
        local fs = r.cols[ci]
        if not fs then fs = Font(r, 11, C.text); fs:SetWordWrap(false); r.cols[ci] = fs end
        local w = c.w == "flex" and flexW or c.w
        fs:ClearAllPoints(); fs:SetPoint("LEFT", x, 0); fs:SetWidth(w - 6)
        fs:SetJustifyH(c.align or "LEFT")
        fs:SetText(c.text or "")
        SetColor(fs, c.color or (d.header and C.muted or C.text))
        fs:Show()
        x = x + w
        used = ci
      end
      if d.header then SetColor(r.title, C.muted) end
    end
    for ci = used + 1, #r.cols do r.cols[ci]:Hide() end

    -- home section headings: gold title with a thin rule running to the right
    if not r.rule then r.rule = Tex(r, "ARTWORK", C.line); r.rule:SetHeight(1) end
    r.rule:Hide()
    if home and d.section then
      r.sub:Hide()
      r.title:ClearAllPoints(); r.title:SetPoint("BOTTOMLEFT", 2, 6)
      local tw = math.min(TextWidth(r.title) + 1, rowWidth - 40)
      r.title:SetWidth(tw)
      r.rule:ClearAllPoints()
      r.rule:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
      r.rule:SetPoint("RIGHT", r, "RIGHT", -2, 0)
      r.rule:Show()
    end
    -- home stat tiles: a big number, its label beside it, a small line under
    if not r.big then r.big = Font(r, 18, C.gold, nil, true) end
    r.big:Hide()
    if home and d.tile then
      r.big:SetText(d.big or "")
      r.big:SetWidth(math.max(1, math.min(TextWidth(r.big) + 1, rowWidth - 60)))
      r.big:ClearAllPoints(); r.big:SetPoint("TOPLEFT", 48, -7)
      r.big:Show()
      r.title:ClearAllPoints(); r.title:SetPoint("BOTTOMLEFT", r.big, "BOTTOMRIGHT", 5, 1)
      r.title:SetWidth(math.max(20, rowWidth - 48 - r.big:GetWidth() - 12))
      SetColor(r.title, d.titleColor or C.text)
      r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", 48, -31)
      r.sub:SetWidth(math.max(20, rowWidth - 54))
    end

    local selected = UI.selected ~= nil and UI.selected.key ~= nil and UI.selected.key == d.key
    r.hl:SetShown(selected)
    r.selectedMark:SetShown(selected)
    r:Show()
  end
  for i = #data + 1, #UI.rows do UI.rows[i]:Hide(); UI.rows[i].data = nil end
  if home then y = place.Total() end
  child:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- Details panel (opens on row click)
---------------------------------------------------------------------------
local det = CreateFrame("Frame", nil, content)
det.panelWidth = DETAILS_W
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

det.close = Btn(det, "Back", 45, 22)
det.close:SetPoint("TOPRIGHT", -8, -8)
det.close:SetFrameLevel(det:GetFrameLevel() + 5)
det.close:SetScript("OnClick", function() UI:BackDetails() end)

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
det.title = Font(det.body, 15, C.white, nil, true)
det.title:SetPoint("TOPLEFT", 52, -12)
det.title:SetWidth(DETAILS_W - 52 - 36)
det.title:SetWordWrap(true)
det.title:SetNonSpaceWrap(true)
det.subtitle = Font(det.body, 11, C.muted)
det.subtitle:SetPoint("TOPLEFT",det.title,"BOTTOMLEFT",0,-4)
det.subtitle:SetWidth(DETAILS_W - 62)
det.subtitle:SetWordWrap(true)
det.subtitle:SetNonSpaceWrap(true)

det.art = det.body:CreateTexture(nil, "BACKGROUND")
det.art:SetPoint("TOPRIGHT", -4, 0)
det.art:SetSize(104, 52)
det.art:SetTexCoord(0.08, 0.92, 0.30, 0.72)
det.art:SetAlpha(0.13)
det.stats = CreateFrame("Frame", nil, det.body)
det.stats:SetHeight(58)
Tex(det.stats, "BACKGROUND", C.panel2):SetAllPoints()
for i, label in ipairs({"Available", "In bank", "Reserved"}) do
  local value = Font(det.stats, 19, C.white, nil, true)
  local caption = Font(det.stats, 11, C.muted)
  caption:SetText(label)
  det.stats[i] = {value=value, caption=caption}
end

det.actionBar = CreateFrame("Frame", nil, det)
det.actionBar:SetPoint("BOTTOMLEFT", 1, 0)
det.actionBar:SetPoint("BOTTOMRIGHT")
det.actionBar:SetHeight(46)
Tex(det.actionBar, "BACKGROUND", C.panel2):SetAllPoints()
det.actionBar.request = Btn(det.actionBar, "Request item", 105, 28, "accent")
det.actionBar.request:SetPoint("LEFT", 10, 0)
det.actionBar.mail = Btn(det.actionBar, "Mail by profession", 132, 28)
det.actionBar.mail:SetPoint("RIGHT", -10, 0)

det.pools = { text = {}, box = {}, btn = {}, label = {}, rule = {}, progress = {} }
det.used = { text = 0, box = 0, btn = 0, label = 0, rule = 0, progress = 0 }

function det:Reset(icon, quality, titleText, subtitle, iconCoords)
  self.casualDraft=nil
  for k in pairs(self.used) do
    for i = 1, #self.pools[k] do self.pools[k][i]:Hide() end
    self.used[k] = 0
  end
  self.scroll:SetVerticalScroll(0)
  self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -4, 0)
  self.art:Hide()
  self.stats:Hide()
  self.actionBar:Hide()
  local nav = UI.nav and UI.nav[UI.view]
  self.icon:SetTexture(icon or (nav and nav.icon:GetTexture()) or ns.LOGO_SMALL)
  self.icon:SetTexCoord(unpack(iconCoords or {0.08, 0.92, 0.08, 0.92}))
  self.icon:Show()
  local q = quality and QColor(quality) or C.white
  self.title:SetText(titleText or "")
  SetColor(self.title, q)
  self.subtitle:SetText(subtitle or "")
  self.y = -math.max(52, 27 + self.title:GetStringHeight()
    + (subtitle and subtitle~="" and self.subtitle:GetStringHeight() or 0))
end

function det:ShowItemSummary(icon, free, held, reserved)
  if icon then self.art:SetTexture(icon); self.art:Show() end
  local width = (self.panelWidth - 26) / 3
  self.stats:SetPoint("TOPLEFT", 10, self.y)
  self.stats:SetWidth(width * 3)
  local counts = {free, held, reserved}
  for i, stat in ipairs(self.stats) do
    stat.value:SetPoint("TOPLEFT", 12 + (i - 1) * width, -7)
    stat.value:SetText(counts[i])
    stat.caption:SetPoint("TOPLEFT", 12 + (i - 1) * width, -34)
  end
  SetColor(self.stats[1].value, free > 0 and C.green or C.muted)
  self.stats:Show()
  self.y = self.y - 70
end

function det:ShowItemActions(request, mail)
  if not request and not mail then return end
  local bar = self.actionBar
  bar.request:SetShown(request ~= nil)
  bar.request:SetScript("OnClick", request)
  bar.mail:SetShown(mail ~= nil)
  bar.mail:SetScript("OnClick", mail)
  bar:Show()
  self.scroll:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -4, 0)
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
  -- Pooled rows may previously have been a fixed-height live preview. Restore
  -- automatic measurement before laying out the next paragraph or heading.
  fs:SetHeight(0)
  fs:SetWordWrap(true); fs:SetNonSpaceWrap(true); fs:SetJustifyV("TOP")
  fs:SetWidth(self.panelWidth - 24)
  fs:SetText(str)
  SetColor(fs, color or C.text)
  local height=math.max(14,math.ceil(fs:GetStringHeight() or 14))
  fs:SetHeight(height)
  self.y = self.y - height - 8
  return fs
end

function det:Field(label, value, width, numeric)
  local l = self:Take("label", function() return Font(self.body, 11, C.muted) end)
  l:SetPoint("TOPLEFT", 12, self.y - 4)
  l:SetText(label)
  local b = self:Take("box", function() return Box(self.body, 100, "") end)
  b:SetNumeric(numeric == true)
  b:SetWidth(math.min(width or 150, self.panelWidth - 90 - 14))
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
    b:SetOn(s.on == true)
    b:SetLabel(s[1])
    local w = math.max(56, (b.text:GetStringWidth() or 40) + 18)
    b:SetWidth(w)
    if x + w > self.panelWidth - 16 then x = 12; self.y = self.y - 28 end
    b:SetPoint("TOPLEFT", x, self.y)
    b.tip = s.tip
    b:SetScript("OnClick", s[2])
    x = x + w + 6
  end
  self.y = self.y - 30
end

function det:Gap(n) self.y = self.y - (n or 6) end

function det:Section(title)
  self:Gap(5)
  local rule=self:Take("rule",function() return Tex(self.body,"BORDER",C.line) end)
  rule:SetPoint("TOPLEFT",12,self.y)
  rule:SetPoint("TOPRIGHT",-12,self.y)
  rule:SetHeight(1)
  self:Gap(9)
  self:Text(title,C.gold)
end

function det:Progress(done,total)
  done,total=tonumber(done) or 0,tonumber(total) or 0
  if total<=0 then return end
  local line=self:Take("progress",function()
    local bar=CreateFrame("Frame",nil,self.body)
    Tex(bar,"BACKGROUND",C.panel2):SetAllPoints()
    bar.fill=Tex(bar,"ARTWORK",C.green)
    bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    return bar
  end)
  local width=self.panelWidth-24
  line:SetPoint("TOPLEFT",12,self.y)
  line:SetSize(width,5)
  line.fill:SetWidth(math.max(1,width*math.max(0,math.min(done/total,1))))
  line.fill:SetShown(done>0)
  self:Gap(14)
end

-- Call after filling: sizes the scrolling body to what was added.
function det:Finish()
  self.body:SetHeight(math.max(1, -self.y + 8))
  self:UpdateScroll()
end

function UI:CloseDetails()
  det:Hide()
  det.kind, det.key = nil, nil
  self.selected = nil
  self.detailHistory=nil
  self:Layout()
  self:Refresh()
end

function UI:OpenDetails(kind, key, back)
  if not back and det:IsShown() and det.kind and (det.kind~=kind or det.key~=key) then
    local history=self.detailHistory or {}
    self.detailHistory=history
    history[#history+1]={kind=det.kind,key=det.key}
    if #history>12 then table.remove(history,1) end
  end
  if (kind == "banksort" or kind == "professionmail") and (det.kind ~= kind or det.key ~= key) then
    det.mailProfession, det.mailQuantity = nil, nil
  end
  det.kind, det.key = kind, key
  det:Show()
  self:Layout()
  self:FillDetails()
end

function UI:BackDetails()
  local previous=self.detailHistory and table.remove(self.detailHistory)
  if not previous then return self:CloseDetails() end
  self:OpenDetails(previous.kind,previous.key,true)
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
UI.state = {
  requests = { filter = "open", mine = false, sort = "new" },
  needs = { filter = "all" },
  bank = { cat = nil, stock = 'all', quality = nil, mode = nil },
  crafters = { filter = "all", prof = nil },
  recipes = { prof = nil, online = false, designated = false, crafter = nil, skillup = false },
  roster = { filter = "online", role = nil, review = nil },
  sync = { filter = "guild", status = "all", sort = "recent" },
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
local ORDER = { "home", "activities", "roster", "quests", "bank", "requests", "needs", "shopping", "donations", "market", "crafters", "recipes", "projects", "invites", "news", "membertools", "onboarding", "settings", "sync", "officer" }
local GROUPS = {
  {label="Bank", first="bank", iconView="bank", "bank", "requests", "needs", "shopping", "donations"},
  {label="Professions", first="market", iconView="crafters", "market", "crafters", "recipes"},
  {label="Guild", first="news", iconView="news", "news", "projects", "invites"},
  {label="Member tools", first="membertools", iconView="membertools", "membertools", "onboarding"},
}
local groupFor = {}
for _, group in ipairs(GROUPS) do
  for _, key in ipairs(group) do groupFor[key] = group end
end
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"   -- marks designated guild crafters

local function AddDropdownArrow(b)
  b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -20, 0); b.text:SetJustifyH("LEFT")
  b.arrow = b:CreateTexture(nil, "ARTWORK")
  b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  b.arrow:SetSize(12, 12); b.arrow:SetPoint("RIGHT", -5, -2)
  b.arrow:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
end

-- A toolbar button that opens a dropdown menu.
--   items() -> { {label, value, right} }, current() -> value, set(value)
local function DropChip(bar, w, tip, items, current, set, side)
  local b
  b = bar:Add(Btn(bar, "", w, 22), side or "left", function()
    OpenMenu(b, items(), current(), function(v) set(v); UI:Refresh() end)
  end, tip)
  AddDropdownArrow(b)
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
        local makers = ns.CraftersOf("item:" .. id)
        local made = ""
        if #makers > 0 then
          local first = makers[1]
          made = "Craftable by " .. (Online(first.who) and ("|cff4ade80" .. first.who .. "|r") or first.who)
            .. (#makers > 1 and (" +" .. (#makers - 1)) or "")
        end
        out[#out + 1] = {
          key = "need:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)),
          sub = made ~= "" and made or nil,
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
    bar.export = bar:Add(Btn(bar, "Send to Auctionator", 140, 22, "accent"), "right", function() ns.ExportAuctionator() end,
      "Save this list as the \"" .. ns.SHOPPING_LIST_NAME .. "\" shopping list in Auctionator, with quantities.")
    bar.export.disabledTip = "Load Auctionator to send your shopping list to it."
  end,
  rows = function(g, q)
    local out = {}
    for _, r in ipairs(ns.ShoppingList()) do
      local name = ns.ItemName(r.id, true)
      if Match(q, name) then
        local id = r.id
        out[#out + 1] = {
          key = "item:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)), titleColor = QColor(Quality(id)),
          title = name, sub = "need " .. r.need .. "  ·  approved requests " .. r.req,
          stock=tostring(r.have), right=tostring(r.buy), rightColor=C.gold,
          onClick = function() UI:OpenDetails("item", id) end,
        }
      end
    end
    if #out>0 then table.insert(out,1,{key="shopping-columns",title="Item",stock="On hand",right="To buy",titleColor=C.muted,rightColor=C.muted}) end
    return out
  end,
  footer = function() return ns.HasAuctionator() and "Shortfalls plus approved requests the bank can't cover." or "Install Auctionator to send this list to the auction house." end,
  empty = "Nothing to buy. Every need is stocked and every approved request is covered.",
}

-- Bank ----------------------------------------------------------------------
Views.bank = {
  label = "Bank", icon = "Interface\\Icons\\INV_Misc_Bag_10",
  clearFilters = function()
    local st=UI.state.bank
    if not st.mode then st.cat, st.stock, st.quality=nil,"all",nil end
  end,
  filtered = function()
    local st=UI.state.bank
    return not st.mode and (st.cat or st.stock~="all" or st.quality~=nil)
  end,
  tools = function(bar)
    UI.bankCatChip = DropChip(bar, 116, "Show one kind of item", function()
      local counts = {}
      for id in pairs(ns.BankCatalog()) do local c=ns.ItemCategory(id); counts[c]=(counts[c] or 0)+1 end
      local items = { { label = "All categories", value = false, icon = Views.bank.icon } }
      for _, c in ipairs(ns.CATEGORIES) do
        if counts[c] then items[#items + 1] = { label = c, value = c, right = tostring(counts[c]), icon = BankCategoryIcon(c) } end
      end
      return items
    end, function() return UI.state.bank.cat or false end, function(v) UI.state.bank.cat = v or nil end)
    UI.bankStockChip=DropChip(bar,118,'Filter by recorded stock and open requests',function()
      return {{label='All stock',value='all'},{label='In stock',value='stocked'},{label='Available now',value='available'},{label='Awaiting restock',value='restock'}}
    end,function() return UI.state.bank.stock end,function(v) UI.state.bank.stock=v end)
    UI.bankQualityChip=DropChip(bar,96,'Filter by item quality',function()
      return {{label='Any quality',value=false},{label='Poor',value=0},{label='Common',value=1},{label='Uncommon',value=2},{label='Rare',value=3},{label='Epic+',value=4}}
    end,function() if UI.state.bank.quality==nil then return false end; return UI.state.bank.quality end,function(v) UI.state.bank.quality=v~=false and v or nil end)
  end,
  rows = function(g, q)
    if UI.state.bank.mode == 'sort' then return UI.BankSortRows(q) end
    if UI.state.bank.mode == 'stv' then return UI.StvRows(q) end
    local totals, holders = {}, {}
    for id in pairs(ns.BankCatalog()) do totals[id]=0 end
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
    local shown,total = 0,0
    for id, c in pairs(totals) do
      -- one odd item mustn't take the whole page down
      local ok, err = ns.SafeCall(function()
        local name = tostring(ns.ItemName(id, true))
        local okc, cat = pcall(ns.ItemCategory, id)
        cat = (okc and type(cat) == "string") and cat or "Other"
        local stock=UI.state.bank.stock or 'all'
        local held,asked,free=ns.BankRequestStock(id)
        local stockMatch=stock=='all' or (stock=='stocked' and held>0) or (stock=='available' and free>0) or (stock=='restock' and (held==0 or asked>held))
        local quality=select(3,GetItemInfo(id)); local wanted=UI.state.bank.quality
        local qualityMatch=wanted==nil or (quality and (wanted==4 and quality>=4 or quality==wanted))
        total=total+1
        if stockMatch and qualityMatch and (not only or cat == only) and Match(q, name, holders[id], cat) then
          shown=shown+1
          groups[cat] = groups[cat] or {}
          table.insert(groups[cat], {
            key = "item:" .. id, item = id, icon = ns.ItemIcon(id), qcolor = QColor(Quality(id)), titleColor = QColor(Quality(id)),
            title = name, sub = c==0 and "Out of stock · requests wait for restock" or asked>0 and (asked.." requested") or nil,
            stock=tostring(c), right=tostring(free), rightColor=free>0 and C.green or C.muted, count=c, sort=name,
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
    if #cats>0 then out[1]={key="bank-columns",title="Item",stock="In bank",right="Available",titleColor=C.muted,rightColor=C.muted} end
    for _, cat in ipairs(cats) do
      local list = groups[cat]
      table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.sort < b.sort end)
      local total = 0
      for _, r in ipairs(list) do total = total + r.count end
      out[#out + 1] = { key = "cat:" .. cat, title = "|cfff2c14e" .. cat .. "|r", icon = BankCategoryIcon(cat),
        sub = #list .. (#list == 1 and " kind of item" or " kinds of items"), right = tostring(total) }
      for _, r in ipairs(list) do out[#out + 1] = r end
    end
    return out,total,shown
  end,
  footer = function(g)
    if UI.state.bank.mode == 'stv' then
      return "Pages for the Green Hills of Stranglethorn quests. Click a chapter to request pages. Duplicates you loot are welcome at the mailbox."
    end
    if UI.state.bank.mode == 'sort' then
      local src = UI.bankPlan and UI.bankPlan.source
      return (src and ("Prices: " .. (({ledger="AHledger",tsm="TSM",auctionator="Auctionator"})[src] or src) .. ", less the 5% AH cut. ")
        or "No price addon loaded; values use vendor prices. ") .. "Click an item for details and Mail buttons."
    end
    local latest = 0
    for _, snapshot in pairs(g.bank) do
      if not snapshot.retired then latest=math.max(latest,tonumber(snapshot.bankTime or snapshot.v) or 0) end
    end
    return latest>0 and ("Newest bank snapshot · "..Ago(latest)) or "No bank yet. On the bank character: /epu bankalt on"
  end,
  empty = "No items in the bank catalog yet. Stock appears after a bank character shares it.",
}

-- Sort the bank ------------------------------------------------------------
local function Holders(r)
  local parts = {}
  for who, n in pairs(r.holders or {}) do parts[#parts + 1] = tostring(who) .. (n > 1 and (" " .. n) or "") end
  table.sort(parts)
  return table.concat(parts, ", ")
end
local function First(name) return (name or "?"):match("^(%S+)") or name end
function UI.BankSortPlan()
  if not UI.bankPlan or GetTime() - (UI.bankPlanAt or 0) > 30 then
    local ok, plan = pcall(ns.BankSortPlan)
    UI.bankPlan, UI.bankPlanAt = ok and plan or { recipes = {}, mats = {}, sell = {} }, GetTime()
    if not ok and not UI.bankSortErr then UI.bankSortErr = true; ns.Print("Sort the bank failed: " .. tostring(plan)) end
  end
  return UI.bankPlan
end
function UI.BankSortRows(q)
  local plan, out = UI.BankSortPlan(), {}
  local function row(r, sub, right)
    return { key = "sort:" .. r.item, item = r.item, icon = ns.ItemIcon(r.item), qcolor = QColor(r.quality or 1), titleColor = QColor(r.quality or 1),
      title = r.name or ns.ItemName(r.item, true), sub = sub, right = right, onClick = function() UI:OpenDetails("banksort", r.item) end }
  end
  local function section(title, list, hint, build)
    local shown = {}
    for _, r in ipairs(list) do if Match(q, r.name, Holders(r)) then shown[#shown + 1] = build(r) end end
    if #shown == 0 then return end
    out[#out + 1] = { key = "cat:" .. title, title = "|cfff2c14e" .. title .. "|r", sub = hint, right = tostring(#shown) }
    for _, x in ipairs(shown) do out[#out + 1] = x end
  end
  section("Recipes to hand out", plan.recipes, "Best guildmate for each pattern in the bank or mail", function(r)
    local who = r.give
    local sub = (r.best and "|cff4ade80Give to " or r.maybe and "|cfff2c14eMaybe " or r.unverified and "|cfff2c14eCheck with " or "|cff9aa1abClosest: ") .. First(who.who) .. "|r"
      .. " (" .. tostring(r.prof) .. " " .. who.skill .. ", " .. r.why .. ")" .. (r.need and ("  ·  needs " .. r.need) or "")
    return row(r, sub, r.count > 1 and tostring(r.count) or nil)
  end)
  section("Materials guildmates can use", plan.mats, "Skill-ups first, then profitable crafts", function(r)
    local parts = {}
    if #r.users > 0 then
      local names, seen = {}, {}
      for _, u in ipairs(r.users) do if not seen[u.who] and #names < 3 then seen[u.who] = true; names[#names + 1] = First(u.who) end end
      parts[#parts + 1] = "Skill-ups: " .. table.concat(names, ", ") .. (#r.users > #names and " +" or "")
    end
    if r.use then parts[#parts + 1] = "Craft " .. tostring(r.use.name) .. ": +" .. Money(r.use.profit) end
    if r.unit > 0 then parts[#parts + 1] = "sells " .. Money(r.unit) end
    return row(r, table.concat(parts, "  ·  "), tostring(r.count))
  end)
  section("Sell", plan.sell, "Nobody needs these; stock kept for needs and requests is left out", function(r)
    local sub = (r.reason and (r.reason .. "  ·  ") or "") .. r.surplus .. " × " .. Money(r.unit)
      .. ((r.ah and r.unit > (r.vendor or 0)) and " on the AH" or " to a vendor")
    return row(r, sub, Money(r.value))
  end)
  return out,#plan.recipes+#plan.mats+#plan.sell
end
local function FindPlanRow(id)
  local plan = UI.BankSortPlan()
  for _, list in ipairs({ plan.recipes, plan.mats, plan.sell }) do
    for _, r in ipairs(list) do if r.item == id then return r end end
  end
end

-- Green Hills of Stranglethorn pages ----------------------------------------
local stvPick = {}
function UI.StvRows(q)
  local plan, out = ns.StvPlan(), {}
  for i, c in ipairs(plan.chapters) do
    local nums = {}
    for _, p in ipairs(c.pages) do nums[#nums + 1] = p.page end
    local status = c.done and "|cff4ade80you've finished this chapter|r"
      or ((c.sets > 0 and (c.sets .. " full set" .. (c.sets == 1 and "" or "s") .. " in the bank") or "no full set in the bank")
      .. (#c.short > 0 and ("  ·  short on page" .. (#c.short > 1 and "s " or " ") .. table.concat(c.short, ", ")) or ""))
    out[#out + 1] = { key = "cat:stv" .. i, title = "|cfff2c14e" .. c.name .. "|r  ·  pages " .. table.concat(nums, ", "), sub = status,
      right = c.done and "Done" or nil, onClick = function() UI:OpenDetails("stvchapter", i) end }
    for _, p in ipairs(c.pages) do
      local name = "Page " .. p.page
      if Match(q, name, c.name, table.concat(p.holders, ", ")) then
        local parts = {}
        parts[#parts + 1] = p.held > 0 and ("Bank: " .. table.concat(p.holders, ", ")) or "None in the bank"
        if p.asked > 0 then parts[#parts + 1] = p.asked .. " requested" end
        if p.mine > 0 then parts[#parts + 1] = "|cff4ade80you have " .. p.mine .. "|r"
        elseif p.missing then parts[#parts + 1] = "|cffffb347you need this|r" end
        out[#out + 1] = { key = "stv:" .. p.page, item = p.item, icon = ns.ItemIcon(p.item),
          titleColor = p.held > 0 and QColor(1) or C.muted, title = name, sub = table.concat(parts, "  ·  "),
          right = tostring(p.free), onClick = function() UI:OpenDetails("stvchapter", i) end }
      end
    end
  end
  return out
end

-- Requests --------------------------------------------------------------------
local function RequestMatchesFilter(r, f)
  if f == "all" then return true end
  if r.archived then return false end
  if f == "open" then return ns.IsActiveRequest(r) end
  if f == "pending" then return r.status == "pending" or r.status == "open" end
  return r.status == f
end

local function RequestMatchesScope(r,q)
  local st=UI.state.requests
  local mine=ns.MainOf(r.who)==ns.MainOf(ns.me) or ns.IAmCrafter(r)
  return (not st.mine or mine) and (not st.crafts or r.crafter)
    and Match(q,ns.RequestName(r,true),r.who,r.to,ns.MainOf(r.who),r.note,r.crafter)
end

Views.requests = {
  label = "Requests", icon = "Interface\\Icons\\INV_Letter_15",
  composer = "request",
  count = function(g)
    local n = 0
    local officer = ns.IsBankTrusted(ns.me)
    for _, r in pairs(g.requests) do
      local pending = (r.status == "pending" or r.status == "open")
      if r.crafter and ns.IAmCrafter(r) and (pending or r.status == "approved") then n = n + 1     -- work for me to do
      elseif officer and pending and not r.crafter then n = n + 1
      elseif not officer and ns.IsActiveRequest(r) and ns.MainOf(r.who) == ns.MainOf(ns.me) then n = n + 1 end
    end
    return n, C.goldBg, C.gold
  end,
  tools = function(bar)
    UI.statusChip = DropChip(bar, 120, "Which requests to show; counts include the current search, Mine and Crafts filters", function()
      local g, counts = ns.G(), {}
      for _, r in pairs((g and g.requests) or {}) do
        if RequestMatchesScope(r,Q()) then
        for _, f in ipairs(REQ_FILTERS) do
          if RequestMatchesFilter(r, f[1]) then counts[f[1]] = (counts[f[1]] or 0) + 1 end
        end
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
    local st, officer, out = UI.state.requests, ns.IsBankTrusted(ns.me), {}
    for rid, r in pairs(g.requests) do
      local name = ns.RequestName(r, true)
      if RequestMatchesFilter(r, st.filter) and RequestMatchesScope(r,q) then
        local pending = (r.status == "pending" or r.status == "open")
        local parts = { ns.WhoLabel(r.who) }
        if r.crafter then
          parts[#parts + 1] = "|cff6ea8ffcraft by " .. (ns.IAmCrafter(r) and "you" or r.crafter) .. "|r"
          parts[#parts + 1] = ({ me = "they send mats", bank = "bank sends mats", crafter = "crafter's mats" })[r.mats or "me"]
        end
        if r.to and r.to ~= r.who then table.insert(parts, 1, "|cfff2c14eMail to " .. r.to .. "|r") end
        parts[#parts + 1] = Ago(r.t)
        if not r.crafter then
          local waiting=ns.RequestRestock(rid)
          if waiting>0 then parts[#parts+1]='|cfff2c14eAwaiting restock: '..waiting..'|r' end
        end
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
  footer = function(g)
    local shown,total=0,0
    for _,r in pairs(g.requests) do
      if RequestMatchesFilter(r,UI.state.requests.filter) then
        total=total+1; if RequestMatchesScope(r,Q()) then shown=shown+1 end
      end
    end
    local summary="Showing "..shown.." of "..total.." requests"
    if Q()~="" then summary=summary..' | Search: "'..Q()..'" (X clears)' end
    if UI.state.requests.mine then summary=summary.." | Mine" end
    if UI.state.requests.crafts then summary=summary.." | Crafts" end
    local item=UI.itemBox and ns.ItemID(UI.itemBox:GetText())
    if item then return ns.CanBankRequest(item) and ns.BankRequestAvailability(item) or 'This item is not requestable. Sold-out equipment stays hidden; choose an item from Bank.' end
    return summary
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
local function OlderSyncVersion(report)
  local release = ns.newestVersion or ns.RELEASE_VERSION
  return release and report.ver and ns.VersionNumber(report.ver) < ns.VersionNumber(release)
end
local function SyncMemberStatus(r)
  if r.none then return "No sync activity recorded", "sync_noseen" end
  if r.asked and ns.Now()-r.asked < 120 and (not r.t or r.asked > r.t+60) then
    return "Requested data "..Ago(r.asked), "sync_wait"
  end
  if r.t then
    local source = r.from and (" from "..r.from) or ""
    return "Last report "..Ago(r.t)..source, r.kind=="relay" and "sync_unconf" or "sync_ok"
  end
  if r.asked then return "Last requested "..Ago(r.asked), "sync_none" end
  if r.name==ns.me and ns.IsBankTrusted(ns.me) then return "Holds this guild's copy", "sync_host" end
  return "Waiting for guild data", "sync_none"
end
local syncFilters = {
  {value="all", label="All statuses"},
  {value="sync_ok", label="Reported"},
  {value="sync_wait", label="Requested"},
  {value="sync_unconf", label="Unconfirmed"},
  {value="sync_host", label="Officer copy"},
  {value="sync_none", label="No report"},
  {value="sync_noseen", label="No addon seen"},
  {value="online", label="Online"},
  {value="outdated", label="Older version"},
}
local syncSorts = {
  {value="recent", label="Latest activity"},
  {value="name", label="Name A–Z"},
  {value="online", label="Online first"},
  {value="version", label="Newest version"},
}
Views.sync = {
  label = "Sync", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", stateKey = "sync",
  filtered = function() return UI.state.sync.filter~="mine" and UI.state.sync.status~="all" end,
  clearFilters = function() UI.state.sync.status="all" end,
  chips = {
    { "guild", "Members", "Members whose addon has checked in.", "Interface\\Icons\\INV_Misc_Head_Human_01" },
    { "all", "Whole roster", "Include members whose addon hasn't been seen.", "Interface\\Icons\\INV_Misc_GroupLooking" },
    { "mine", "This PC", "Local sync activity log.", "Interface\\Icons\\INV_Misc_Book_09" },
  },
  tools = function(bar)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(TOOLBAR_H)
    bar:Add(Btn(bar, "Sync now", 80, 22, "accent"), "right", function() ns.FullSync() end,
      "Ask online officers for everything again (it also happens by itself)")
    local function Choice(field, options, width, x)
      local b = Btn(bar,"",width,22)
      b:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",x,-1)
      AddDropdownArrow(b)
      b:SetScript("OnClick",function()
        local st = UI.state.sync
        local choices = options
        if field=="status" and not (ns.newestVersion or ns.RELEASE_VERSION) then
          choices = {}
          for _, option in ipairs(options) do
            if option.value~="outdated" then choices[#choices+1]=option end
          end
        end
        OpenMenu(b,choices,st[field],function(value)
          st[field]=value; scroll:SetVerticalScroll(0); UI:Refresh()
        end)
      end)
      return b
    end
    bar.status = Choice("status",syncFilters,132,10)
    bar.sort = Choice("sort",syncSorts,160,148)
  end,
  rows = function(g, q)
    local st, out = UI.state.sync, {}
    if st.filter == "mine" then
      for i, e in ipairs(g.syncLog or {}) do
        if Match(q, e.text, e.who) then
          out[#out + 1] = {
            key = "synclog:" .. i, title = e.text or "?", titleColor = (e.kind == "relay" or e.kind == "behind") and C.gold or C.text,
            sub = (SYNC_KIND[e.kind] or e.kind or "") .. "  ·  " .. Ago(e.t),
            icon = Views.sync.icon, onClick = function() UI:OpenDetails("synclog", e) end,
          }
        end
      end
      return out,#(g.syncLog or {})
    end
    local reports = {}
    for _, r in ipairs(ns.SyncReports()) do reports[r.name] = r end
    if st.filter == "all" then
      for name in pairs(ns.roster) do reports[name] = reports[name] or { name = name, none = true } end
    end
    local total=0
    for _, r in pairs(reports) do
      total=total+1
      if Match(q, r.name, r.from, r.what, r.ver) then
        local sub,pill = SyncMemberStatus(r)
        local old = OlderSyncVersion(r)
        local online = Online(r.name)
        if st.status=="all" or st.status==pill or (st.status=="online" and online) or (st.status=="outdated" and old) then
          local icon, coords = ns.ClassIcon((ns.roster[r.name] or {}).classFile)
          out[#out + 1] = {
            key = "sync:" .. r.name, name = r.name, dot = online,
            icon = icon, iconCoords = coords,
            title = ns.WhoLabel(r.name)..(r.name==ns.me and " (you)" or ""), titleColor = r.none and C.muted or C.text,
            sub = sub, pill = pill, activity = math.max(r.t or 0, r.asked or 0),
            version = r.ver and ns.VersionNumber(r.ver) or 0,
            right = r.ver and ("v" .. r.ver) or nil, rightColor = old and C.red or C.muted,
            onClick = function() UI:OpenDetails("syncmember", r.name) end,
          }
        end
      end
    end
    table.sort(out,function(a,b)
      if st.sort=="recent" then
        if a.activity~=b.activity then return a.activity>b.activity end
      elseif st.sort=="online" and a.dot~=b.dot then
        return a.dot
      elseif st.sort=="version" and a.version~=b.version then
        return a.version>b.version
      end
      return a.name:lower()<b.name:lower()
    end)
    return out,total
  end,
  footer = function(g)
    if UI.state.sync.filter == "mine" then return "What this PC's addon sent and received. Kept on this PC only." end
    local n, day, old = 0, 0, 0
    for _, r in ipairs(ns.SyncReports()) do
      n = n + 1
      if r.t and ns.Now() - r.t < 86400 then day = day + 1 end
      if OlderSyncVersion(r) then old = old + 1 end
    end
    return n .. " addons seen  ·  " .. day .. " reported in the last 24h" .. (old > 0 and ("  ·  |cffff6b6b" .. old .. " on an older version|r") or "")
  end,
  empty = "No matching sync activity. Try another status or clear the search.",
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
      for prof, skill in pairs(ns.InGuild(who) and c.profs or {}) do
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
    for who in pairs(g.crafters) do if ns.InGuild(who) then n = n + 1 end end
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
  filtered = function()
    local st=UI.state.recipes
    return st.prof or st.online or st.designated or st.crafter or st.skillup
  end,
  clearFilters = function()
    local st=UI.state.recipes
    st.prof,st.crafter,st.online,st.designated,st.skillup=nil,nil,false,false,false
  end,
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
    local total=0
    for _, e in ipairs(ns.RecipeIndex()) do
      local name = e.item and ns.ItemName(e.item, true) or e.name
      local shareable=ns.IsBoP(e.item or 0)~=true
      if shareable then total=total+1 end
      if shareable and (not st.prof or e.prof == st.prof) then
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
    return out,total
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
  label = "Guildmates", icon = "Interface\\Icons\\INV_Misc_Head_Human_01", stateKey = "roster",
  tools = function(bar)
    local SHOW = { { label = "Online", value = "online" }, { label = "Everyone", value = "all" },
      { label = "Near my level (±5)", value = "near" }, { label = "Looking for a partner", value = "looking" },
      { label = "On my layer", value = "layer" } }
    UI.showChip = DropChip(bar, 112, "Who to show. On my layer: target or mouse over any NPC to detect yours.", function() return SHOW end,
      function() return UI.state.roster.filter end, function(v) UI.state.roster.filter = v or "online" end)
    UI.roleChip = DropChip(bar, 64, "Show one role", function()
      local items = { { label = "Any role", value = false } }
      for _, r in ipairs({ "t", "h", "d" }) do items[#items + 1] = { label = ns.ROLES[r], value = r } end
      return items
    end, function() return UI.state.roster.role or false end, function(v) UI.state.roster.role = v or nil end)
    UI.reviewChip = DropChip(bar, 68, "Officers: members worth a look", function()
      return { { label = "Everyone", value = false }, { label = "Inactive " .. ns.INACTIVE_DAYS .. "+ days", value = "inactive" },
        { label = "Ready for promotion", value = "promote" }, { label = "Has an officer note", value = "note" } }
    end, function() return UI.state.roster.review or false end, function(v) UI.state.roster.review = v or nil end)
    UI.lookingBtn = bar:Add(Btn(bar, "I want a partner", 76, 22), "right", function(self)
      if ns.SetLookingForPartner then ns.SetLookingForPartner(not ns.LookingForPartner()) end
      self:SetOn(ns.LookingForPartner and ns.LookingForPartner() or false)
      UI:Refresh()
    end, "Looking for a partner: guildmates see it in their Guildmates list and on your tooltip until you log off or untick it")
    bar:Add(Btn(bar, "My profile", 52, 22), "right", function() UI:OpenDetails("profile", ns.me) end,
      "Your role and what you're looking for, shown to the guild")
  end,
  rows = function(g, q)
    local st, out, officer = UI.state.roster, {}, ns.IsTrusted(ns.me)
    local myLevel = UnitLevel("player") or 1
    local myQuests = ns.CurrentQuests and ns.CurrentQuests() or {}
    for name, r in pairs(ns.roster) do
      local prof = ns.ProfileOf(name)
      local roles = prof and prof.roles or ""
      local status = ns.GuildmateStatus and ns.GuildmateStatus(name)
      local looking = r.online and status and status.lf
      local ok = (st.filter == "all") or (st.filter == "online" and r.online)
        or (st.filter == "near" and r.online and name ~= ns.me and math.abs((r.level or 0) - myLevel) <= 5)
        or (st.filter == "layer" and r.online and name ~= ns.me and ns.LayerOf and ns.LayerOf(name) == "same")
        or (st.filter == "looking" and looking)
      if ok and st.role then ok = roles:find(st.role, 1, true) ~= nil end
      local rv = (officer and st.review) and ns.Review(name) or nil
      if ok and rv then
        ok = (st.review == "inactive" and rv.inactive) or (st.review == "promote" and rv.promote)
          or (st.review == "note" and rv.note and rv.note.text ~= "")
      end
      if ok and Match(q, name, r.zone, r.class, ns.MainOf(name), prof and prof.lf, ns.RoleText(roles)) then
        local where = r.online and name ~= ns.me and ns.LayerOf and ns.LayerOf(name)
        local seen = g.syncSeen and g.syncSeen[name]
        local epu = name == ns.me or (seen and ns.Now() - (seen.t or 0) < 30 * 86400)
        local zoneText = r.online and (r.zone or "")
          or (r.away and (r.away < 1 and "seen today" or ("seen " .. math.floor(r.away) .. "d ago")) or "offline")
        local groupText = ""
        if looking then groupText = "|cfff2c14eLooking|r"
        elseif r.online and UnitInParty and name ~= ns.me and (UnitInParty(name) or (UnitInRaid and UnitInRaid(name))) then groupText = "|cff4ade80With you|r"
        elseif status and (status.g or 0) > 1 then groupText = "In group (" .. status.g .. ")"
        elseif status and r.online then groupText = "Solo" end
        local layerText = where == "same" and "|cff4ade80same|r" or where == "other" and "|cffffb347other|r" or ""
        local parts = { "Level " .. tostring(r.level or "?") .. (r.class and (" " .. r.class) or ""), zoneText }
        if where == "same" then parts[#parts + 1] = "|cff4ade80same layer|r"
        elseif where == "other" then parts[#parts + 1] = "|cffffb347other layer|r" end
        if groupText ~= "" then parts[#parts + 1] = groupText end
        if prof and prof.lf then parts[#parts + 1] = "|cfff2c14e" .. prof.lf .. "|r" end
        local pill
        if officer then
          local rev = rv or ns.Review(name)
          if rev.inactive then pill = "roster_inactive" elseif rev.promote then pill = "roster_promote" end
        end
        local icon, coords = ns.ClassIcon(r.classFile)
        local sharedQuests = (r.online and name ~= ns.me and ns.SharedQuestIDs) and #ns.SharedQuestIDs(name, myQuests) or 0
        if sharedQuests > 0 then parts[#parts + 1] = "|cff4ade80" .. sharedQuests .. (sharedQuests == 1 and " quest" or " quests") .. " in common|r" end
        if epu then parts[#parts + 1] = "uses EPU" end
        local lvlColor = (r.level and math.abs(r.level - myLevel) <= 5) and C.green or C.text
        out[#out + 1] = {
          key = "member:" .. name, dot = r.online, iconCoords = coords,
          icon = icon,
          title = ns.WhoLabel(name) .. (name == ns.me and " (you)" or ""), titleColor = ClassColor(r.classFile),
          sub = table.concat(parts, "  ·  "),
          columns = {
            { text = tostring(r.level or "?"), w = 34, align = "CENTER", color = lvlColor },
            { text = zoneText, w = "flex", color = r.online and C.text or C.muted },
            { text = layerText, w = 52 },
            { text = groupText, w = 92 },
            { text = sharedQuests > 0 and tostring(sharedQuests) or "", w = 48, align = "CENTER", color = C.green },
          },
          titleWidth = 170,
          right = ns.RoleText(roles), pill = pill,
          sortOnline = r.online and 1 or 0, sortLooking = looking and 1 or 0, sortLevel = r.level or 0, sortName = name,
          onClick = function() UI:OpenDetails("member", name) end,
          onRightClick = function(self) if ns.GuildmateMenu then ns.GuildmateMenu(self, name) end end,
        }
      end
    end
    table.sort(out, function(a, b)
      if a.sortOnline ~= b.sortOnline then return a.sortOnline > b.sortOnline end
      if a.sortLooking ~= b.sortLooking then return a.sortLooking > b.sortLooking end
      if a.sortLevel ~= b.sortLevel then return a.sortLevel > b.sortLevel end
      return a.sortName < b.sortName
    end)
    if #out > 0 then
      table.insert(out, 1, { key = "cat:rosterheader", header = true, title = "Name", titleWidth = 170,
        columns = { { text = "Lv", w = 34, align = "CENTER" }, { text = "Zone", w = "flex" }, { text = "Layer", w = 52 },
          { text = "Group", w = 92 }, { text = "Quests", w = 48, align = "CENTER" } }, right = "Role", rightColor = C.muted })
    end
    return out
  end,
  footer = function()
    local n, on = 0, 0
    for _, r in pairs(ns.roster) do n = n + 1; if r.online then on = on + 1 end end
    return n .. " members, " .. on .. " online. Set your role and what you're looking for under Profile."
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
  label="Projects", icon="Interface\\Icons\\Trade_BlackSmithing",
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
  label="Getting started", icon="Interface\\Icons\\INV_Misc_Book_09",
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

if ns.InstallCasualViews then ns.InstallCasualViews(Views,{Btn=Btn,Match=Match,C=C,OpenMenu=OpenMenu,UI=UI}) end

Views.market = { label = "Market", icon = "Interface\\Icons\\INV_Misc_Coin_02" }
Views.home = {
  label = "Home", icon = "Interface\\Icons\\INV_Misc_Map_01",
  rows = function(g, query)
    local rows = {}
    local pane
    local function Add(row)
      if not (row.featured or row.tile) then row.pane = pane end
      if row.section or Match(query, row.title, row.sub) then rows[#rows + 1] = row end
    end
    -- side: 1 = left pane, 2 = right pane, nil = full width below the panes
    local function Section(title, side)
      -- drop an empty section header left by the previous section
      if rows[#rows] and rows[#rows].section then rows[#rows] = nil end
      pane = side
      rows[#rows + 1] = { key = "section:" .. title, section = true, pane = side, title = "|cfff2c14e" .. title .. "|r" }
    end
    local function Go(fn) return function() UI.search:SetText(""); fn() end end
    local c = ns.CasualStore and ns.CasualStore() or {}
    -- message of the day
    local motd = g.motd and g.motd.text
    if motd and motd ~= "" then
      Add({ key = "motd", title = "Message of the day", sub = motd, icon = Views.news.icon, featured = true, compact = true,
        onClick = Go(function() UI:SetView("news") end) })
    end
    local state = ns.CommunityState()
    if state and ns.GetBubbleActions then
      local total = 0
      for _, items in pairs(ns.GetBubbleActions(g, state)) do total = total + #items end
      if total > 0 then Add({ key = "attention", title = "Needs your attention", sub = total .. (total == 1 and " action" or " actions"),
        icon = "Interface\\Icons\\INV_Misc_Note_01", featured = true, onClick = Go(function() UI:OpenDetails("bubbleactions", "all") end) }) end
    end
    -- at a glance
    local online, withEPU, zones = 0, 0, {}
    for name, r in pairs(ns.roster) do
      if r.online then
        online = online + 1
        local seen = g.syncSeen and g.syncSeen[name]
        if name == ns.me or (seen and ns.Now() - (seen.t or 0) < 6 * 3600) then withEPU = withEPU + 1 end
        if name ~= ns.me and r.zone and r.zone ~= "" then
          zones[r.zone] = zones[r.zone] or {}
          table.insert(zones[r.zone], name)
        end
      end
    end
    local groups = ns.OpenGroups and ns.OpenGroups() or {}
    local now, soon = {}, {}
    for _, x in ipairs(groups) do if x.when == "now" then now[#now + 1] = x else soon[#soon + 1] = x end end
    local myRequests = 0
    for _, r in pairs(g.requests) do
      if ns.IsActiveRequest(r) and (ns.MainOf(r.who) == ns.MainOf(ns.me) or ns.IAmCrafter(r)) then myRequests = myRequests + 1 end
    end
    Add({ key = "online", tile = true, big = tostring(online), title = "online", sub = withEPU .. " with EPU", icon = Views.roster.icon,
      onClick = Go(function() UI.state.roster.filter = "online"; UI:SetView("roster") end) })
    Add({ key = "groups", tile = true, big = tostring(#groups), title = #groups == 1 and "open group" or "open groups",
      sub = #now .. " now · " .. #soon .. " later", icon = Views.activities.icon, onClick = Go(function() ns.ShowGroups() end) })
    Add({ key = "myrequests", tile = true, big = tostring(myRequests), title = myRequests == 1 and "request" or "requests",
      sub = "yours, still open", icon = Views.requests.icon,
      onClick = Go(function()
        local filters = UI.state.requests
        filters.mine, filters.crafts, filters.filter = true, false, "open"
        UI:SetView("requests")
      end) })
    local nextEvent
    for _, event in pairs(c.guildEvents or {}) do
      if event.status == "scheduled" and event.starts > ns.Now() then
        if not nextEvent or event.starts < nextEvent.starts then nextEvent = event end
      end
    end
    Add({ key = "nextevent", tile = true, big = nextEvent and date("%a", nextEvent.starts) or "—",
      title = nextEvent and date("%H:%M", nextEvent.starts) or "no events",
      sub = nextEvent and nextEvent.title or "Next event: nothing planned",
      icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", onClick = Go(function() SlashCmdList.EPUGUILD("calendar") end) })
    -- right now
    Section("Right now", 1)
    for i, x in ipairs(now) do
      if i > 4 then break end
      Add({ key = "now:" .. x.key, title = x.title, sub = x.sub, icon = x.icon, compact = true, onClick = Go(x.open) })
    end
    if #now == 0 then
      Add({ key = "nobody", title = "Nobody's looking for a group", sub = "Start one: pick a dungeon and when", icon = Views.activities.icon, compact = true,
        onClick = Go(function() ns.ShowGroups(); UI:OpenDetails("groupform", "new") end) })
    end
    if #soon > 0 then
      Section("Coming up", 1)
      for i, x in ipairs(soon) do
        if i > 4 then Add({ key = "more", title = "See all groups", sub = (#soon - 4) .. " more", icon = Views.activities.icon, compact = true,
          onClick = Go(function() ns.ShowGroups() end) }); break end
        Add({ key = "soon:" .. x.key, title = x.title, sub = x.sub, icon = x.icon, compact = true, onClick = Go(x.open) })
      end
    end
    -- who is where
    local zoneList = {}
    for zone, names in pairs(zones) do zoneList[#zoneList + 1] = { zone = zone, names = names } end
    table.sort(zoneList, function(a, b) if #a.names ~= #b.names then return #a.names > #b.names end return a.zone < b.zone end)
    if #zoneList > 0 then
      Section("Who is where", 2)
      for i, z in ipairs(zoneList) do
        if i > 6 then break end
        table.sort(z.names)
        local first = {}
        for j, name in ipairs(z.names) do
          if j > 4 then first[#first + 1] = "+" .. (#z.names - 4); break end
          local lvl = (ns.roster[name] or {}).level
          first[#first + 1] = (name:match("^(%S+)") or name) .. (lvl and (" " .. lvl) or "")
        end
        Add({ key = "zone:" .. z.zone, title = z.zone .. " (" .. #z.names .. ")", sub = table.concat(first, ", "), compact = true,
          icon = "Interface\\Icons\\INV_Misc_Map02",
          onClick = Go(function() UI.state.roster.filter = "online"; UI:SetView("roster"); UI.search:SetText(z.zone) end) })
      end
    end
    -- same quests as you
    if ns.SharedQuestIDs then
      local own, mates = ns.CurrentQuests(), {}
      for name, r in pairs(ns.roster) do
        if r.online and name ~= ns.me then
          local ids = ns.SharedQuestIDs(name, own)
          if #ids > 0 then mates[#mates + 1] = { name = name, r = r, ids = ids, near = ns.QuestNearby(name) } end
        end
      end
      table.sort(mates, function(a, b)
        if a.near ~= b.near then return a.near end
        if #a.ids ~= #b.ids then return #a.ids > #b.ids end
        return a.name < b.name
      end)
      if #mates > 0 then
        Section("Same quests as you", 2)
        for i, m in ipairs(mates) do
          if i > 4 then
            Add({ key = "questmore", title = "See all on Quests", sub = (#mates - 4) .. " more guildmates", compact = true,
              icon = Views.quests and Views.quests.icon, onClick = Go(function() UI:SetView("quests") end) })
            break
          end
          local first = own[m.ids[1]] and own[m.ids[1]].title or "a quest"
          Add({ key = "questmate:" .. m.name, compact = true, icon = ns.ClassIcon(m.r.classFile),
            title = (m.name:match("^(%S+)") or m.name) .. " · " .. #m.ids .. (#m.ids == 1 and " quest" or " quests"),
            sub = (m.near and "|cff4ade80nearby|r · " or ((m.r.zone or "") .. " · ")) .. first .. (#m.ids > 1 and (" +" .. (#m.ids - 1)) or ""),
            onClick = Go(function() UI:SetView("quests") end),
            onRightClick = function(self) if ns.GuildmateMenu then ns.GuildmateMenu(self, m.name) end end })
        end
      end
    end
    -- today in the guild
    local feed, shared = {}, {}
    for _, e in ipairs(ns.FeedEntries and ns.FeedEntries(1) or {}) do
      feed[#feed + 1] = { t = e.t, kind = "shared", sharedKind = e.kind, who = e.who, title = e.text }
      shared[tostring(e.who)] = true
    end
    for _, e in ipairs(g.rosterFeed or {}) do
      if ns.Now() - e.t < 86400 and not (e.kind == "level" and shared[e.who]) then feed[#feed + 1] = e end
    end
    for _, n in ipairs(ns.UnreadNews and ns.UnreadNews() or {}) do
      if n.t and ns.Now() - n.t < 86400 then feed[#feed + 1] = { t = n.t, kind = "news", who = n.by, title = n.title } end
    end
    table.sort(feed, function(a, b) return a.t > b.t end)
    if #feed > 0 then
      Section("Today in the guild", 2)
      for i, e in ipairs(feed) do
        if i > 6 then break end
        local ago = math.floor((ns.Now() - e.t) / 60)
        local agoText = ago < 1 and "just now" or ago < 60 and (ago .. " min ago") or (math.floor(ago / 60) .. " h ago")
        local text = e.kind == "joined" and (e.who .. " joined the guild") or e.kind == "left" and (e.who .. " left the guild")
          or e.kind == "level" and (e.who .. " reached level " .. tostring(e.v))
          or e.kind == "shared" and (tostring(e.who) .. " " .. tostring(e.title)) or ("News: " .. tostring(e.title))
        local icon = e.kind == "joined" and "Interface\\Icons\\INV_Letter_15" or (e.kind == "level" or e.sharedKind == "level") and "Interface\\Icons\\Spell_Holy_Renew"
          or e.kind == "shared" and "Interface\\Icons\\Achievement_Level_10"
          or e.kind == "left" and "Interface\\Icons\\Ability_Rogue_Sprint" or Views.news.icon
        Add({ key = "feed:" .. i, title = text, sub = agoText, icon = icon, compact = true,
          onClick = e.kind == "news" and Go(function() UI:SetView("news") end) or nil })
      end
    end
    -- shortcuts
    Section("Shortcuts")
    Add({ key = "bank", title = "Guild bank", sub = "Browse stock and request an item.", icon = Views.bank.icon, compact = true, onClick = Go(function() UI:SetView("bank") end) })
    Add({ key = "news", title = "Guild news", sub = #ns.UnreadNews() .. " unread announcements", icon = Views.news.icon, compact = true, onClick = Go(function() UI:SetView("news") end) })
    Add({ key = "start", title = "Getting started", sub = "See your guild checklist.", icon = Views.onboarding.icon, compact = true, onClick = Go(function() UI:SetView("onboarding") end) })
    if ns.IsBankTrusted(ns.me) then
      Add({ key = "fulfil", title = "Bank fulfillment", sub = "Review approved requests and preview mail.", icon = "Interface\\Icons\\INV_Misc_Bag_08",
        compact = true, onClick = Go(function() UI:OpenDetails("fulfillment", "all") end) })
    end
    if rows[#rows] and rows[#rows].section then rows[#rows] = nil end
    return rows
  end,
  empty = "Nothing matches your search.",
}
Views.settings = {
  label = "Settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
  rows = function(_,query)
    local options = {
      {key="notifications", title="Notifications", sub="Alerts, quiet hours and the floating Events button.",
        icon="Interface\\Icons\\INV_Misc_PocketWatch_01",
        onClick=function() SlashCmdList.EPUGUILD("notifications"); UI:OpenDetails("noticeform","all") end},
      {key="map", title="Map and sharing", sub="Guild location markers and sharing preferences.",
        icon=Views.home.icon,
        onClick=function() SlashCmdList.EPUGUILD("map") end},
      {key="chat", title="Chat history", sub="Keep whispers, guild chat and officer chat after a reload.",
        icon="Interface\\Icons\\INV_Letter_15", onClick=function() ns.ShowChatHistory() end},
      {key="minimap", title="Minimap button", sub="Position, spacing and visibility.", icon=ns.LOGO_SMALL,
        onClick=function() ns.ShowMinimapButtonSettings() end},
    }
    local rows={}
    for _, row in ipairs(options) do if Match(query,row.title,row.sub) then rows[#rows+1]=row end end
    return rows
  end,
  empty="No settings match your search.",
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
  bar.controls = {}
  function bar:Fit(width)
    local left, right, lower = 10, 10, 10
    for _, entry in ipairs(self.controls) do
      local b=entry.button
      if b:IsShown() then
        local padding = b.arrow and 31 or b.icon and 34 or 16
        local size = math.min(math.max(104,width*0.43), math.max(entry.width,TextWidth(b.text)+padding))
        b:SetWidth(size)
        b:ClearAllPoints()
        if entry.right then
          b:SetPoint("TOPRIGHT",self,"TOPRIGHT",-right,-6)
          right=right+size+6
        end
      end
    end
    for _, entry in ipairs(self.controls) do
      local b=entry.button
      if b:IsShown() and not entry.right then
        local size=b:GetWidth()
        if lower>10 or left+size+right>width then
          b:SetPoint("TOPLEFT",self,"TOPLEFT",lower,-34)
          lower=lower+size+4
        else
          b:SetPoint("TOPLEFT",self,"TOPLEFT",left,-6)
          left=left+size+4
        end
      end
    end
    return lower>10
  end
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
    self.controls[#self.controls+1]={button=w,width=w:GetWidth(),right=side=="right"}
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
      if view == Views.sync then scroll:SetVerticalScroll(0); UI:Layout() end
      UI:Refresh()
    end, ch[3])
    if ch[4] then
      local width = b:GetWidth()+20
      b:SetWidth(width); bar.leftX = bar.leftX+20
      b:SetIcon(ch[4])
    end
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
UI.forBtn = Btn(composer, "Mail to: me", 104, 22)
UI.forBtn:SetPoint("LEFT", UI.noteBox, "RIGHT", 6, 0)
AddDropdownArrow(UI.forBtn)
local function RequestRecipients()
  local chars = { ns.me }
  for _, name in ipairs(ns.MyChars()) do
    if name ~= ns.me then chars[#chars + 1] = name end
  end
  return chars
end
function UI:ForTarget()
  for _, name in ipairs(RequestRecipients()) do
    if name == self.requestTo then return name end
  end
  return ns.me
end
function UI:UpdateForButton()
  local t = self:ForTarget() or ns.me or "me"
  self.forBtn:SetLabel("Mail to: " .. (t:match("^(%S+)") or t))
  self.forBtn.tip = "Mail to: " .. t .. ". Click to choose another character."
end
UI.forBtn:SetScript("OnClick", function(self)
  local choices = {}
  for _, name in ipairs(RequestRecipients()) do
    choices[#choices + 1] = { label = name, value = name, right = name == ns.me and "Current toon" or nil }
  end
  OpenMenu(self, choices, UI:ForTarget(), function(name)
    UI.requestTo = name
    UI:UpdateForButton()
  end)
end)
-- officers: type any guild member's name (partial is fine if it's unique)
UI.forBox = Box(composer, 110, "Request for…")
UI.forBox:SetPoint("LEFT", UI.noteBox, "RIGHT", 6, 0)
UI.forBox:Hide()
UI.forBox.tip = "Enter a guild character's name to request for them. Leave blank to request for your current character."
UI.action = Btn(composer, "Request", 90, 22, "accent")
UI.action:SetPoint("RIGHT", -10, 0)

local function ClearComposer()
  UI.itemBox:SetText(""); UI.qtyBox:SetText(""); UI.noteBox:SetText(""); UI.forBox:SetText("")
  UI.requestTo = nil
  UI:UpdateForButton()
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
      if not ns.NewRequest(id, tonumber(UI.qtyBox:GetText()) or 1, UI.noteBox:GetText(), nil, who) then return end
    else
      if not ns.NewRequest(id, tonumber(UI.qtyBox:GetText()) or 1, UI.noteBox:GetText(), UI:ForTarget()) then return end
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

function ns.MatchItems(text, max, bankOnly)
  text = (text or ""):lower():match("^%s*(.-)%s*$")
  local out = {}
  if #text < 2 then return out end
  local names = (ns.db and ns.db.itemNames) or {}
  for id in pairs(bankOnly and ns.BankCatalog() or ns.ItemCandidates()) do
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
  local bankOnly=self.composerMode~='need'
  local found = ns.MatchItems(text, 8,bankOnly)
  local list = {}
  for i, m in ipairs(found) do
    local have = ns.BankCount and ns.BankCount(m.id) or 0
    local q = select(3, GetItemInfo(m.id))
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    list[i] = { text = (c and c.hex or "") .. m.name .. (c and c.hex and "|r" or ""), value = m.id, icon = ns.ItemIcon(m.id),
      right = bankOnly and (have>0 and (have..' in bank') or 'Out of stock') or (have > 0 and ("bank has " .. have) or nil) }
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
UI.itemBox:HookScript('OnTextChanged',function()
  if UI.view=='requests' then ns.Debounce('requestStockHint',0.1,function() UI.footerText:SetText(Views.requests.footer(ns.G())) end) end
end)
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
  local function Row(labelText, height, icon)
    local badge = officerPage:CreateTexture(nil, "ARTWORK")
    badge:SetTexture(icon)
    badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge:SetSize(22, 22)
    badge:SetPoint("TOPLEFT", 14, y - 4)
    local l = Font(officerPage, 12, C.text)
    l:SetPoint("TOPLEFT", 45, y - 4)
    l:SetText(labelText)
    local hint = Font(officerPage, 11, C.muted)
    hint:SetPoint("TOPLEFT", 45, y - 21)
    local line=Tex(officerPage,"BORDER",C.line)
    line:SetPoint("TOPLEFT",14,y-(height or 48)+6)
    line:SetPoint("TOPRIGHT",-14,y-(height or 48)+6)
    line:SetHeight(1)
    y = y - (height or 48)
    return l, hint
  end

  local lineY=y
  local _, queueHint=Row("Bank fulfillment",54,Views.bank.icon)
  UI.queueHint=queueHint
  local queueButton=Btn(officerPage,"Review fulfillment",132,24,"accent")
  queueButton:SetPoint("TOPRIGHT",-14,lineY)
  queueButton:SetScript("OnClick",function() UI:OpenDetails("fulfillment","all") end)

  lineY=y
  local _, h1 = Row("Trusted ranks",nil,Views.officer.icon)
  UI.rankBtn = Btn(officerPage, "", 230, 22)
  UI.rankBtn:SetPoint("TOPRIGHT", -14, lineY)
  UI.rankBtn.tip = "Officers: members at these ranks (and any rank with \"Bank\" in its name) have every officer tool. Each officer's addon uses its own setting, so keep them the same."
  h1:SetText("Officer ranks (all officer tools)")
  UI.rankBtn:SetScript("OnClick", function()
    local g = ns.G()
    if not g then return end
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 10
    g.officerRank = ((g.officerRank or 1) + 1) % math.max(1, n - 1)
    UI:Refresh()
  end)

  lineY=y
  local _, hb = Row("Bank managers",nil,Views.bank.icon)
  UI.bankMgrHint = hb
  UI.bankMgrBtn = Btn(officerPage, "Choose", 80, 22)
  UI.bankMgrBtn:SetPoint("TOPRIGHT", -14, lineY)
  UI.bankMgrBtn.tip = "Ranks or characters that may run the bank side for the whole guild: bank contents, needs, requests, donations and verified sync. No announcements, notes or Officer tab."
  UI.bankMgrBtn:SetScript("OnClick", function() UI:OpenDetails("bankmanagers", "guild") end)

  lineY=y
  local _, h2 = Row("This character is a bank",nil,Views.bank.icon)
  h2:SetText("Track its bags and bank as guild stock")
  UI.bankToggle = Btn(officerPage, "", 80, 22)
  UI.bankToggle:SetPoint("TOPRIGHT", -14, lineY)
  UI.bankToggle:SetScript("OnClick", function() ns.SetBankAlt(not ns.IsBankAlt()); UI:Refresh() end)

  lineY=y
  local _, h3 = Row("Open requests per player",nil,Views.requests.icon)
  h3:SetText("Counting alts. 0 means no limit. Shared with the guild.")
  UI.limitBox = Box(officerPage, 50, "0", true)
  UI.limitBox:SetPoint("TOPRIGHT", -84, lineY)
  local limitSave = Btn(officerPage, "Save", 62, 22)
  limitSave:SetPoint("TOPRIGHT", -14, lineY)
  limitSave:SetScript("OnClick", function()
    ns.SetPolicy("maxOpen", tonumber(UI.limitBox:GetText()) or 0)
    UI.limitBox:ClearFocus()
  end)

  lineY=y
  local _, h4 = Row("Discord",nil,Views.sync.icon)
  UI.inboxHint = h4
  local applyInbox = Btn(officerPage, "Apply inbox now", 120, 22)
  applyInbox:SetPoint("TOPRIGHT", -146, lineY)
  applyInbox.tip = "Apply requests and approvals made in Discord that have arrived in Inbox.lua."
  applyInbox:SetScript("OnClick", function() ns.ProcessInbox(); UI:Refresh() end)
  local saveDiscord = Btn(officerPage, "Save for Discord", 126, 22)
  saveDiscord:SetPoint("TOPRIGHT", -14, lineY)
  saveDiscord.tip = "Reloads your UI so WoW saves everything and the Discord bot picks it up."
  saveDiscord:SetScript("OnClick", function() pcall(ns.CacheItemNames); ReloadUI() end)

  local rowY = y
  local _, h6 = Row("Promotion reminder", 62, Views.roster.icon)
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
  h6:SetPoint("TOPLEFT", 45, rowY - 20)
  UI.promoRule = Font(officerPage, 11, C.gold)       -- the rule in plain words
  UI.promoRule:SetPoint("TOPLEFT", 14, rowY - 38)
  promoSave.tip = "Members at the lowest rank who meet both get a \"Promote?\" tag on the Roster page (officers only)."
  promoSave:SetScript("OnClick", function()
    ns.SetPolicy("promoDays", tonumber(UI.promoDays:GetText()) or 0)
    ns.SetPolicy("promoLevel", tonumber(UI.promoLevel:GetText()) or 0)
    UI.promoDays:ClearFocus(); UI.promoLevel:ClearFocus()
  end)

  local _, h5 = Row("Tools", 40, Views.settings.icon)
  h5:SetText("")
  local tools = {
    { "Post needs to guild", function() ns.PostNeeds() end, "Posts the top open needs in guild chat." },
    { "Full sync", function() ns.FullSync() end, "Asks other online officers to resend everything." },
    { "Tidy finished requests", function()
        local n = ns.ArchiveFinished()
        ns.Print("Tidied " .. n .. " finished request" .. (n == 1 and "" or "s") .. ". They're still under the All filter.")
      end, "Hides filled, rejected and cancelled requests from the default views, for everyone." },
    { "Profession coverage", function() UI:OpenDetails("coverage", "all") end, "Which professions the guild has, who's best, the gaps, and the guild focus." },
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
  do
    local bits = {}
    for r in pairs(g.policy.bankRanks or {}) do bits[#bits + 1] = r end
    local nChars = 0
    for _ in pairs(g.policy.bankChars or {}) do nChars = nChars + 1 end
    table.sort(bits)
    if nChars > 0 then bits[#bits + 1] = nChars .. (nChars == 1 and " character" or " characters") end
    UI.bankMgrHint:SetText(#bits > 0 and ("Bank side only, guild-wide: " .. table.concat(bits, ", ")) or "Bank side only, guild-wide. None chosen yet.")
  end
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
  local open, pending, members, fulfillment = 0, 0, 0, 0
  for _, r in pairs(g.requests) do
    if ns.IsActiveRequest(r) then open = open + 1 end
    if r.status == "pending" or r.status == "open" then pending = pending + 1 end
    if not r.crafter and r.status=="approved" and ns.Remaining(r)>0 then fulfillment=fulfillment+1 end
  end
  UI.queueHint:SetText(fulfillment==0 and "No approved bank requests to fill." or (fulfillment.." approved bank requests to fill"))
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
  local bankOfficer = ns.IsBankTrusted(ns.me)


  if ns.FillCasualDetails and ns.FillCasualDetails(kind,key,det) then
    -- Activity forms and details are supplied by CasualUI.
  elseif kind=="syncmember" then
    local report
    for _, r in ipairs(ns.SyncReports()) do if r.name==key then report=r; break end end
    report = report or {name=key, none=true}
    local summary = SyncMemberStatus(report)
    local icon, coords = ns.ClassIcon((ns.roster[key] or {}).classFile)
    det:Reset(icon or Views.sync.icon,nil,ns.WhoLabel(key),summary,coords)
    det:Text(report.ver and ("Addon version: v"..report.ver) or "Addon version unknown",C.muted)
    if OlderSyncVersion(report) then det:Text("An updated version is available on CurseForge.",C.gold) end
    if report.asked then det:Text("Last request: "..date("%b %d, %H:%M",report.asked),C.muted) end
    if report.t then
      det:Section("Latest reported sync")
      det:Text((report.kind=="relay" and "Unconfirmed copy" or "Officer copy")..
        (report.from and (" from "..report.from) or "").." · "..date("%b %d, %H:%M",report.t))
      if report.what and report.what~="" then det:Text(report.what,C.muted) end
    end
  elseif kind=="synclog" then
    local label = SYNC_KIND[key.kind] or "Sync activity"
    det:Reset(Views.sync.icon,nil,label,Ago(key.t))
    det:Text(key.text or label)
  elseif kind=="bubbleactions" then
    ns.FillBubbleActions(det)
  elseif kind=="fulfillment" and bankOfficer then
    det:Reset(nil,nil,"Bank fulfillment","Stock estimates use the latest bank snapshots")
    local queue = ns.BankFulfillmentQueue()
    for _, section in ipairs({{"Ready to fill",queue.ready},{"Pull from bank",queue.pull},{"Waiting for stock",queue.restock}}) do
      det:Text(section[1].." ("..#section[2]..")",C.gold)
      for _, group in ipairs(section[2]) do
        local who = group.who
        det:Text(who.." · "..#group.rows.." approved"
          ..(group.short>0 and (" · "..group.short.." short in recorded stock") or ""))
        det:Buttons({{"Preview mail",function() UI:OpenDetails("membermail",who) end}})
      end
    end
    det:Text("Needs review ("..#queue.review..")",C.gold)
    for _, id in ipairs(queue.review) do
      local request = g.requests[id]
      det:Text(ns.RequestName(request,true).." · "..(request.to or request.who).." · "..request.status)
      det:Buttons({{"Open request",function() UI:OpenDetails("request",id) end}})
    end
  elseif kind=="membermail" then
    det:Reset(nil,nil,"Fill mail for member",key)
    local rows=ns.MemberMailPlan(key)
    local shortage={}
    for _,row in ipairs(rows) do shortage[row.r.item]=(shortage[row.r.item] or 0)+ns.RequestRestock(row.id) end
    for _,line in ipairs(ns.MemberMailPreview(rows)) do
      det:Text(ns.ItemName(line.item,true).." · "..line.ready.." of "..line.remaining.." in next mail"
        ..((shortage[line.item] or 0)>0 and (" · "..shortage[line.item].." short in recorded stock") or ""))
    end
    det:Text("Combines approved bank requests for this exact recipient. Uses items in your bags, up to the game's attachment limit. Missing quantities stay open. Sending is manual.",C.muted)
    if bankOfficer then det:Buttons({{"Fill mail",function() ns.MailMemberRequests(key) end,accent=true}}) end
  elseif kind=="newproject" then
    det:Reset(nil,1,"New crafting project","Officers coordinate shared crafting goals")
    local title=det:Field("Title","",160)
    local note=det:Field("Goal","",160)
    det:Buttons({{"Create",function() local id=ns.CreateProject(title:GetText(),note:GetText()); if id then UI:OpenDetails("project",id) end end,accent=true}})
  elseif kind=="project" then
    local p=ns.PlanningStore().projects[key]; if not p then return UI:CloseDetails() end
    local done,total=ns.ProjectProgress(p)
    det:Reset(nil,1,p.title,done.." of "..total.." items delivered")
    det:Progress(done,total)
    det:Text(p.note)
    if officer then
      det:Buttons({{"Add craft task",function() UI:OpenDetails("projecttask",key) end,accent=true},
        {"Stock materials",function() ns.StockProject(key) end}})
    end
    det:Section("Assigned work")
    if #p.tasks==0 then det:Text("No tasks assigned yet.",C.muted) end
    for _,task in ipairs(p.tasks) do
      local r=g.requests[task.rid]; local rid=task.rid
      det:Text((r and ns.RequestName(r,true) or task.key).." x"..task.qty.." - "..task.crafter)
      det:Text(r and ((r.status or "pending")..", "..ns.Remaining(r).." remaining; deliver to "..task.to) or "Request history unavailable; awaiting sync.",C.muted)
      if r then det:Buttons({{"View request",function() UI:OpenDetails("request",rid) end}}) end
    end
    if p.recipient then det:Text("Starter kit for "..p.recipient,C.gold) end
    det:Section("Materials and bank supplies")
    for item,n in pairs(ns.ProjectMaterials(p)) do det:Text(ns.ItemName(item,true).." x"..n.." (bank: "..ns.BankCount(item)..")") end
    if officer then
      det:Buttons({{"Archive project",function() ns.ArchiveProject(key); UI:CloseDetails() end}})
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
    local steps=ns.Checklist(key)
    local done=0
    for _,s in ipairs(steps) do if s.done then done=done+1 end end
    det:Text(done.." of "..#steps.." steps complete",C.muted)
    det:Progress(done,#steps)
    for _,s in ipairs(steps) do
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
      det:Buttons({{"Starter kits",function() UI.state.activities.kind="kits"; UI:SetView("activities") end}})
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
    det:Progress(r.delivered or 0,r.qty)
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
    if ns.IsActiveRequest(r) and ((own and r.mats == "me") or (bankOfficer and r.mats == "bank")) then
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
    local where = key ~= ns.me and r.online and ns.LayerOf and ns.LayerOf(key)
    if r.online then
      det:Text("|cff4ade80Online|r" .. ((r.zone and r.zone ~= "") and ("  ·  " .. r.zone) or ""))
      if where == "same" then
        det:Text("|cff4ade80Same layer as you|r")
      elseif where == "other" then
        det:Text("|cffffb347On another layer of " .. (r.zone or "this zone") .. "|r")
      elseif key ~= ns.me and ns.guildLocations and ns.guildLocations[key] and ns.guildLocations[key].l and not ns.MyLayer() then
        det:Text("Target or mouse over any NPC to compare layers with them.", C.muted)
      end
    else
      det:Text("Offline" .. (r.away and ("  ·  last seen " .. (r.away < 1 and "today" or (math.floor(r.away) .. " days ago"))) or ""), C.muted)
    end
    local specs = {}
    if key==ns.me then
      specs[1]={"Edit my profile",function() UI:OpenDetails("profile",key) end,accent=true}
    else
      specs[1]={"Whisper",function() if ChatFrame_OpenChat then ChatFrame_OpenChat("/w "..key.." ") end end,accent=true}
    end
    if where == "other" then
      specs[#specs + 1] = { "Ask to join their layer", function()
        if ChatFrame_OpenChat then
          ChatFrame_OpenChat("/w " .. key .. " Could you invite me to a group so I can join your layer in "
            .. (r.zone or "this zone") .. "? I'll accept the world refresh and leave the group after.")
        end
      end, tip = "Opens a whisper asking for a group invite. Once you're grouped, accept the game's world refresh prompt to move to their layer." }
    end
    if key ~= ns.me then
      specs[#specs + 1] = { "Invite to group", function()
        local inv = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if inv then inv(key) end
      end }
    end
    det:Buttons(specs)
    if bankOfficer and #ns.MemberMailPlan(key)>0 then
      det:Buttons({{"Fill member mail",function() UI:OpenDetails("membermail",key) end}})
    end
    if officer and key ~= ns.me then
      det:Buttons({ { "Request for " .. (key:match("^(%S+)") or key), function() UI:RequestFor(key) end } })
    end
    local prof = ns.ProfileOf(key)
    local main, alts = ns.MainOf(key), ns.AltsOf(ns.MainOf(key))
    local c = g.crafters[key]
    if prof or #alts>0 or (c and next(c.profs or {})) then
      det:Section("Character profile")
      if prof and prof.roles then det:Text("Plays: "..ns.RoleText(prof.roles)) end
      if prof and prof.lf then det:Text("Looking for: "..prof.lf,C.gold) end
      if #alts>0 then det:Text("Characters: "..main..", "..table.concat(alts,", "),C.muted) end
      local parts={}
      for profession,skill in pairs(c and c.profs or {}) do parts[#parts+1]=profession.." "..skill end
      table.sort(parts)
      if #parts>0 then det:Text("Professions: "..table.concat(parts,", "),C.muted) end
    end
    if officer then
      local rv = ns.Review(key)
      det:Section("Officer review")
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

  elseif kind == "bankmanagers" then
    local pol = g.policy
    local ranks, chars = {}, {}
    for k in pairs(pol.bankRanks or {}) do ranks[k] = true end
    for k in pairs(pol.bankChars or {}) do chars[k] = true end
    det:Reset(Views.bank.icon, nil, "Bank managers", "Run the bank side for the whole guild")
    det:Text("Bank managers can publish bank contents, edit needs, approve and mail requests, record donations, and other members sync from them as verified. They can't post announcements, write member notes, manage events or use the Officer tab.")
    local canEdit = officer
    if not canEdit then det:Text("Only officers can change this.", C.muted) end
    det:Section("By rank")
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    local row = {}
    for i = (g.officerRank or 1) + 2, n do
      local nm = GuildControlGetRankName and GuildControlGetRankName(i)
      if type(nm) == "string" and nm ~= "" then
        local key = nm:lower()
        row[#row + 1] = { (ranks[key] and "[x] " or "[ ] ") .. nm, function()
          if not canEdit then return end
          ranks[key] = not ranks[key] or nil
          ns.SetBankManagers(ranks, chars); UI:FillDetails()
        end, on = ranks[key] == true }
        if #row == 2 then det:Buttons(row); row = {} end
      end
    end
    if #row > 0 then det:Buttons(row) end
    det:Section("By character")
    local list = {}
    for name in pairs(chars) do list[#list + 1] = name end
    table.sort(list)
    if #list == 0 then det:Text("No characters added.", C.muted) end
    for _, name in ipairs(list) do
      det:Buttons({ { name, function() end, tip = "Bank manager" },
        canEdit and { "Remove", function() chars[name] = nil; ns.SetBankManagers(ranks, chars); UI:FillDetails() end } or nil })
    end
    if canEdit then
      local box = det:Field("Character", "", 150)
      det:Buttons({ { "Add", function()
        local name = ns.Member(box:GetText()) or ns.Short(box:GetText())
        if not name or name == "" then return ns.Print("Type a guild member's character name.") end
        chars[name] = true
        for _, alt in ipairs(ns.AltsOf and ns.AltsOf(name) or {}) do chars[alt] = true end
        ns.SetBankManagers(ranks, chars); UI:FillDetails()
      end, accent = true, tip = "Adds the character (and its linked alts)." } })
    end
    det:Text("Ranks with \"Bank\" in their name are full officers, as before.", C.muted)
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
    local chars = RequestRecipients()
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
    local focusList = ns.GuildFocus and ns.GuildFocus() or {}
    local focus = {}
    for _, f in ipairs(focusList) do focus[f.prof] = f end
    if #focusList > 0 then
      local parts = {}
      for _, f in ipairs(focusList) do
        parts[#parts + 1] = f.prof .. (f.goal > 0
          and string.format(" (goal %d: %d of %d player%s there)", f.goal, f.atGoal, f.players, f.players == 1 and "" or "s")
          or string.format(" (%d player%s)", f.players, f.players == 1 and "" or "s"))
      end
      det:Text("|cfff2c14eGuild focus:|r " .. table.concat(parts, ", "))
      det:Text("Members see the focus in Market, with their own progress.", C.muted)
      det:Gap()
    elseif officer then
      det:Text("Mark the professions the guild wants more of with Set as focus. Members see the guild focus in Market.", C.muted)
      det:Gap()
    end
    local gaps = {}
    for _, row in ipairs(ns.Coverage()) do
      local f = focus[row.prof]
      local tag = f and ("  |cfff2c14e· focus" .. (f.goal > 0 and (" " .. f.goal) or "") .. "|r") or ""
      if row.count == 0 then
        det:Text("|cffff6b6b" .. row.prof .. ": nobody yet|r" .. tag)
        gaps[#gaps + 1] = row.prof
      else
        local guild = #row.guild > 0 and ("  " .. STAR .. " " .. table.concat(row.guild, ", ")) or "  |cfff2c14eno guild crafter|r"
        det:Text(row.prof .. ": " .. row.count .. (row.count == 1 and " player" or " players")
          .. ", best " .. row.best .. ((row.online > 0) and ("  ·  |cff4ade80" .. row.online .. " online|r") or "")
          .. (row.recipes > 0 and ("  ·  " .. row.recipes .. " recipes") or "") .. tag .. "\n" .. guild)
      end
      if officer and ns.SetGuildFocus then
        local prof = row.prof
        det:Buttons({ { f and "Change focus" or "Set as focus", function(self)
          OpenMenu(self, ns.GuildFocusChoices(), f and f.goal or false, function(goal)
            ns.SetGuildFocus(prof, goal ~= false and goal or nil)
            UI:FillDetails()
          end)
        end, tip = "Focus professions are shown to every member in Market, with an optional skill goal." } })
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
    det:Text("Requested by " .. r.who .. ((r.via == "discord") and " via Discord" or ""))
    local savedRecipient = r.to or r.who
    local recipientLine = det:Text("Mail to: " .. savedRecipient, C.gold)
    if r.by and r.status ~= "pending" then det:Text("Last changed by " .. r.by .. " " .. Ago(r.u), C.muted) end
    det:Text("In bank: " .. ns.BankCount(r.item) .. "   You carry: " .. ns.ItemCount(r.item), C.muted)
    local waiting=ns.RequestRestock(key)
    if waiting>0 then det:Text('Awaiting restock: '..waiting..' of the remaining '..ns.Remaining(r)..'. Stock is based on the latest shared bank snapshot.',C.gold) end
    det:Gap()
    local own, pending = (r.who == ns.me), (r.status == "pending" or r.status == "open")
    local canEdit = bankOfficer or (own and pending)
    if canEdit then
      local qty = det:Field("Quantity", tostring(r.qty), 60, true)
      local note = det:Field("Note", r.note or "", 160)
      -- deliver-to: cycle through the requester's characters
      local chars = { r.who }
      for _, a in ipairs(ns.AltsOf(r.who)) do chars[#chars + 1] = a end
      local main = ns.MainOf(r.who)
      if main ~= r.who then table.insert(chars, 1, main) end
      local seen, choices = {}, {}
      for _, name in ipairs(chars) do
        if not seen[name] then
          seen[name] = true
          choices[#choices + 1] = { label = name, value = name, right = name == r.who and "Requester" or nil }
        end
      end
      if not seen[savedRecipient] then
        choices[#choices + 1] = { label = savedRecipient, value = savedRecipient }
      end
      det.toChoice = savedRecipient
      if #choices > 1 then
        det:Buttons({ { "Change recipient", function(self)
          OpenMenu(self, choices, det.toChoice, function(name)
            det.toChoice = name
            det.casualDraft = name ~= savedRecipient
            recipientLine:SetText("Mail to: " .. name .. (name ~= savedRecipient and " (unsaved)" or ""))
          end)
        end, tip = "Choose the delivery character, then click Save changes." } })
      end
      local reason = bankOfficer and det:Field("Reason", r.reason or "", 160) or nil
      det:Buttons({ { "Save changes", function()
        if ns.EditRequest(key, { qty = qty:GetText(), note = note:GetText(), to = det.toChoice,
          reason = reason and reason:GetText() or nil }) then
          UI:FillDetails()
          ns.Print("Request updated.")
        end
      end, accent = true } })
      if bankOfficer then
        det:Text("Set status", C.muted)
        local function Set(s) return function()
          ns.EditRequest(key, { status = s, reason = reason and reason:GetText() or nil })
        end end
        det:Buttons({ { "Pending", Set("pending") }, { "Approve", Set("approved") }, { "Fill", Set("filled") }, { "Reject", Set("rejected"), tip = "Type a reason above first if you like" } })
        if r.status == "approved" then
          local function RecipientSaved()
            local current = g.requests[key]
            if current and det.toChoice == (current.to or current.who) then return true end
            ns.Print("Save changes to the recipient before preparing mail.")
            return false
          end
          if #ns.MemberMailPlan(r.to or r.who)>1 then
            det:Buttons({{"Fill mail for this member",function()
              if RecipientSaved() then UI:OpenDetails("membermail", det.toChoice) end
            end}})
          end
          det:Buttons({ { "Mail it", function() if RecipientSaved() then ns.MailRequest(key) end end, accent = true,
            tip = "With a mailbox open: fills in " .. (r.to or r.who) .. " and attaches " .. r.qty .. " from your bags. You click Send." } })
        end
      end
      if own and ns.IsActiveRequest(r) then
        det:Buttons({ { "Cancel request", function() ns.EditRequest(key, { status = "cancelled" }) end } })
      end
    else
      if r.note and r.note ~= "" then det:Text("Note: " .. r.note) end
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
    local makers = ns.CraftersOf("item:" .. key)
    if #makers > 0 then
      local names = {}
      for i = 1, math.min(6, #makers) do
        local c = makers[i]
        names[#names + 1] = (ns.IsDesignated(c.who, c.prof) and (STAR .. " ") or "")
          .. (Online(c.who) and ("|cff4ade80" .. c.who .. "|r") or c.who)
      end
      det:Text("Guildmates who can craft this: " .. table.concat(names, ", ") .. (#makers > 6 and (" +" .. (#makers - 6)) or ""))
      det:Buttons({ { "Ask a crafter", function() UI:OpenDetails("recipe", "item:" .. key) end,
        tip = "Opens the recipe so you can send a craft request." } })
    end
    det:Gap()
    if bankOfficer then
      local t = det:Field("Target", tostring(target), 60, true)
      local choice = nkind
      det:Buttons({ { (choice == "goal") and "One-time goal" or "Restock", function(self)
        choice = (choice == "goal") and "restock" or "goal"
        self:SetLabel((choice == "goal") and "One-time goal" or "Restock")
      end, tip = "Restock: always keep this many. One-time goal: closes itself when reached." } })
      det:Buttons({ { "Save", function() ns.SetNeed(key, tonumber(t:GetText()) or target, choice) end, accent = true },
        { "Remove", function() ns.SetNeed(key, 0); UI:CloseDetails() end } })
    end
    if ns.CanBankRequest(key) then det:Buttons({ { "Request this", function()
      UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus()
    end } }) end

  elseif kind == "stvchapter" then
    local plan = ns.StvPlan()
    local c = plan.chapters[key]
    if not c then return UI:CloseDetails() end
    det:Reset("Interface\\Icons\\INV_Misc_Book_09", 1, "Green Hills: " .. c.name,
      c.done and "You've finished this chapter" or "Turn in to Barnil Stonepot at Nesingwary's camp")
    local pick = stvPick[key]
    if not pick then
      pick = {}
      for _, p in ipairs(c.pages) do pick[p.page] = p.missing and p.free > 0 end
      stvPick[key] = pick
    end
    det:Section("Pages")
    for _, p in ipairs(c.pages) do
      det:Text("Page " .. p.page .. "  ·  bank " .. p.held .. (p.asked > 0 and (" (" .. p.asked .. " requested)") or "")
        .. (p.mine > 0 and ("  ·  you have " .. p.mine) or (p.missing and "  ·  |cffffb347you need it|r" or ""))
        .. (#p.holders > 0 and ("\n" .. table.concat(p.holders, ", ")) or ""), p.held > 0 and C.text or C.muted)
    end
    if not c.done then
      det:Section("Request from the bank")
      local toggles = {}
      for _, p in ipairs(c.pages) do
        if p.free > 0 then
          toggles[#toggles + 1] = { "Page " .. p.page, function() pick[p.page] = not pick[p.page]; UI:FillDetails() end, on = pick[p.page] == true }
        end
      end
      if #toggles == 0 then
        det:Text("The bank has no free copies of these pages yet.", C.muted)
      else
        det:Buttons(toggles)
        local chosen = {}
        for _, p in ipairs(c.pages) do if pick[p.page] and p.free > 0 then chosen[#chosen + 1] = p.page end end
        det:Buttons({ { #chosen > 0 and ("Request page" .. (#chosen > 1 and "s " or " ") .. table.concat(chosen, ", ")) or "Pick pages above",
          function()
            if #chosen == 0 then return end
            if ns.RequestStvPages(chosen, c.name) > 0 then stvPick[key] = nil; UI:FillDetails() end
          end, accent = #chosen > 0,
          tip = "One request per page. Pages you already carry start unticked." } })
      end
    end
    if ns.IsBankTrusted(ns.me) then
      det:Section("Officers")
      if plan.targetsSet then
        det:Text("The bank keeps " .. plan.target .. " of each page. Short pages show on Needs and in the donate panel.", C.muted)
        det:Buttons({ { "Remove page targets", function() ns.SetStvTargets(0); UI:FillDetails() end } })
      else
        det:Buttons({ { "Keep " .. ns.STV_TARGET .. " of each page", function() ns.SetStvTargets(ns.STV_TARGET); UI:FillDetails() end, accent = true,
          tip = "Sets a restock minimum for all 15 pages in one go." } })
      end
    end
  elseif kind == "banksort" or (kind == "professionmail" and bankOfficer) then
    local r = FindPlanRow(key)
    if kind == "professionmail" and not r then
      r = {count = ns.BankCount(key), quality = Quality(key)}
    end
    if not r then return UI:CloseDetails() end
    local subtitle = r.holders and ("Held by " .. Holders(r)) or ("In bank: " .. r.count)
    det:Reset(ns.ItemIcon(key), r.quality or 1, r.name or ns.ItemName(key, true), subtitle)
    local specs = {}
    local offered = {}
    local quantity
    local profession = det.mailProfession
    local recipients, choices = {}, {}
    if not r.isRecipe then
      for who, crafter in pairs(g.crafters or {}) do
        if who ~= ns.me and ns.InGuild(who) then
          for prof, skill in pairs(crafter.profs or {}) do
            skill = tonumber(skill)
            if skill and skill > 0 then
              if not recipients[prof] then
                recipients[prof] = {}
                choices[#choices + 1] = {label = prof, value = prof}
              end
              recipients[prof][#recipients[prof] + 1] = {who = who, skill = skill}
            end
          end
        end
      end
      table.sort(choices, function(a, b) return a.label < b.label end)
      table.insert(choices, 1, {label = "All recommendations", value = false})
      if not recipients[profession] then profession = nil end
    end
    if r.users or #choices > 1 then
      quantity = det:Field("Quantity", det.mailQuantity or "1", 70, true)
      quantity.onChange = function()
        if det.kind == kind and det.key == key then det.mailQuantity = quantity:GetText() end
      end
      det:Text("Available from your bags: " .. ns.BankSortMailLimit(key) ..
        ". Needs and open requests stay on this character.", C.muted)
      if #choices > 1 then
        det:Buttons({{"Profession: " .. (profession or "All"), function(button)
          OpenMenu(button, choices, profession or false, function(value)
            det.mailProfession, det.mailQuantity = value or nil, quantity:GetText()
            UI:FillDetails()
          end)
        end}})
      end
    end
    local function mail(who, n)
      if #specs < 3 and who ~= ns.me and not offered[who] then
        offered[who] = true
        specs[#specs + 1] = { "Mail to " .. First(who), function() ns.MailBankItem(who, key, n or (quantity and tonumber(quantity:GetText()))) end, accent = #specs == 0,
          tip = "Open a mailbox on the character holding it. The item goes into a mail for you to check and send." }
      end
    end
    if r.candidates then
      det:Text((r.prof or "?") .. (r.need and (" " .. r.need .. " required") or ", required skill unknown"), C.muted)
      if r.reason then det:Text(r.reason .. ". Worth " .. Money(r.unit) .. " each.") end
      for i, c in ipairs(r.candidates) do
        if i > 8 then det:Text("…and " .. (#r.candidates - 8) .. " more", C.muted); break end
        local status = c.knows and "|cff9aa1abknows it|r" or not r.need and "|cfff2c14erequired skill unknown|r" or not c.scanned and "|cfff2c14ehasn't shared recipes|r"
          or c.canLearn and "|cff4ade80can learn it|r" or "|cffff6b6bskill too low|r"
        det:Text((c.designated and STAR or "") .. c.who .. "  " .. c.skill .. "  ·  " .. status .. (c.online and "  ·  |cff4ade80online|r" or ""))
        if not c.knows and c.canLearn then mail(c.who, 1) end
      end
      if #specs == 0 and r.closest then mail(r.closest.who, 1) end
    end
    if profession then
      local skillUps = {}
      for _, u in ipairs(r.users or {}) do
        if u.prof == profession then
          local prev = skillUps[u.who]
          if not prev or (prev.color ~= "o" and u.color == "o") then skillUps[u.who] = u end
        end
      end
      local list = recipients[profession]
      table.sort(list, function(a, b)
        local function priority(candidate)
          local u = skillUps[candidate.who]
          return u and (u.color == "o" and 2 or 1) or 0
        end
        if priority(a) ~= priority(b) then return priority(a) > priority(b) end
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.who < b.who
      end)
      for _, candidate in ipairs(list) do
        local who = candidate.who
        local use = skillUps[who]
        det:Text(who .. " · " .. profession .. " " .. candidate.skill
          .. (use and (" · " .. use.name .. (use.color == "o" and " (orange)" or " (yellow)")) or ""))
        det:Buttons({{"Mail to " .. First(who), function()
          ns.MailBankItem(who, key, tonumber(quantity:GetText()))
        end}})
      end
    elseif r.users then
      if #r.users > 0 then det:Text("|cfff2c14eSkill-ups|r (orange first)") end
      for i, u in ipairs(r.users) do
        if i > 8 then det:Text("…and " .. (#r.users - 8) .. " more", C.muted); break end
        det:Text(u.who .. "  ·  " .. u.prof .. ": " .. tostring(u.name) .. "  " .. (u.color == "o" and "|cffff8040orange|r" or "|cffffff00yellow|r"))
        mail(u.who)
      end
      if r.use then
        det:Text("|cfff2c14eMost profitable craft|r: " .. tostring(r.use.name) .. ", +" .. Money(r.use.profit) .. " each")
        for _, c in ipairs(r.use.crafters or {}) do mail(c.who) end
      end
    end
    if r.holders then
      det:Text("Sells for " .. (r.ah and (Money(r.ah) .. " on the AH (" .. Money(math.floor(r.ah * 0.95)) .. " after the cut)") or "nothing listed on the AH")
        .. (r.vendor and r.vendor > 0 and (", " .. Money(r.vendor) .. " to a vendor") or "") .. ".", C.muted)
    end
    if kind == "professionmail" and #choices <= 1 then det:Text("No guildmates have shared their professions yet.", C.muted) end
    if r.surplus and r.surplus < r.count then det:Text((r.count - r.surplus) .. " kept for needs and open requests.", C.muted) end
    det:Gap()
    if #specs > 0 then det:Buttons(specs) end
  elseif kind == "item" then
    local holders = {}
    for alt, s in pairs(g.bank) do
      if not s.retired and s.items and s.items[key] then holders[#holders + 1] = alt .. ": " .. s.items[key] end
    end
    local held, asked, free=ns.BankRequestStock(key)
    local icon=ns.ItemIcon(key)
    det:Reset(icon, Quality(key), ns.ItemName(key, true), ns.ItemCategory(key))
    local reserved=held-free
    det:ShowItemSummary(icon, free, held, reserved)
    if asked>reserved then det:Text((asked-reserved).." requested beyond current stock", C.muted) end
    if #holders>0 then det:Section("Bank holders") end
    table.sort(holders)
    for _, h in ipairs(holders) do det:Text(h) end
    if #holders == 0 then det:Text("None in the bank right now.", C.muted) end
    if held==0 then det:Text('Previously stocked. You can request this item and wait for a restock.',C.muted) end
    det:Gap()
    local request, mail
    if ns.CanBankRequest(key) then
      request = function() UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus() end
    end
    if officer then
      local classID = select(6, GetItemInfoInstant(key)) or select(12, GetItemInfo(key))
      if held > 0 and classID == (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7) then
        mail = function() UI:OpenDetails("professionmail", key) end
      end
      det:Section("Officer actions")
      det:Buttons({ { "Add as a need", function()
        UI:SetView("needs"); UI.itemBox:SetText(ns.ItemLink(key)); UI.qtyBox:SetFocus()
      end } })
    end
    det:ShowItemActions(request, mail)

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
    det:Section("Find a crafter")
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
    det:Section("Materials")
    local mats=MatsLines(key)
    if #mats>0 then
      local covered=ns.CraftsCovered(key) or 0
      det:Text(covered>0 and ("Bank stock covers "..covered..(covered==1 and " craft" or " crafts"))
        or "The bank does not have enough materials for one craft.",covered>0 and C.green or C.muted)
      if officer then
        det:Buttons({{"Stock mats for 5 crafts",function() ns.StockMatsFor(key,5) end,
          tip="Raises the bank's needs to cover five crafts."}})
      end
    end
    if e.item then
      det:Gap()
      det:Buttons({ { "Request one from the bank", function()
        UI:SetView("requests"); UI.itemBox:SetText(ns.ItemLink(e.item)); UI.qtyBox:SetFocus()
      end } })
    end
  end
  if ns.AddPersonalActions then ns.AddPersonalActions(kind,key,det) end
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
    local isTab = groupFor[key] ~= nil
    local b = CreateFrame("Button", nil, isTab and sectionTabs or side)
    b:SetSize(SIDEBAR_W - 12, 28)
    b:SetPoint("TOPLEFT", 6, y)
    b.bg = Tex(b, "BACKGROUND", C.panel2)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.strip = Tex(b, "BORDER", C.gold)
    if isTab then
      b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetPoint("BOTTOMRIGHT"); b.strip:SetHeight(2)
    else
      b.strip:SetPoint("TOPLEFT"); b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetWidth(2)
    end
    b.strip:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 8, 0)
    b.icon:SetTexture(v.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = Font(b, isTab and 11 or 10, C.muted)
    if isTab then
      b.icon:Hide()
      b.label:SetPoint("LEFT", 8, 0)
    else
      b.icon:ClearAllPoints()
      b.icon:SetPoint("TOP", 0, -3)
      b.label:SetPoint("TOP", b.icon, "BOTTOM", 0, -2)
    end
    b.label:SetText(({bank="Bank stock", requests="Item requests", needs="Bank needs", shopping="To buy",
      donations="Donations", invites="Invites", onboarding="Start here"})[key] or v.label)
    -- one line on what each page is for, shown on hover
    b.desc = ({
      home="Your guild at a glance: who's on, open groups, today's news.",
      activities="Find or start a group, request a dungeon run, see events.",
      roster="Who's online, where they are, their level and layer.",
      quests="Your quests and which guildmates are on them, plus who is questing near you.",
      bank="Everything the guild bank holds. Click an item to request it.",
      requests="Item requests from guildmates and where each one stands.",
      needs="Items the bank is collecting, with how many are still wanted.",
      shopping="What still has to be bought or farmed to cover needs and requests.",
      donations="Who has given what to the guild bank.",
      market="Prices guildmates ask for gathered materials and crafts.",
      crafters="Who can craft what, and their profession skill.",
      recipes="Every recipe guildmates know. Ask someone to craft one.",
      news="Guild announcements and milestones.",
      projects="Guild crafting projects and who is working on which part.",
      invites="Invite requests for new members.",
      membertools="Quest guides, catch-up help and your notifications.",
      onboarding="Your guild checklist for getting started.",
      settings="Notifications, map sharing and the minimap button.",
      sync="How up to date your guild data is and who has shared it.",
      officer="Officer tools: Discord updates, member review and the officer log.",
    })[key]
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(22, 14)
    b.badge:SetPoint("RIGHT", -6, 0)
    b.badge.bg = Tex(b.badge, "BACKGROUND", C.goldBg)
    b.badge.bg:SetAllPoints()
    b.badge.text = Font(b.badge, 10, C.gold)
    b.badge.text:SetPoint("CENTER")
    b.badge.text:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self)
      if UI.view~=self.key then self.bg:Show() end
      if not self.desc and self.label:GetText()==v.label and TextWidth(self.label)<=self.label:GetWidth()+1 then return end
      GameTooltip:SetOwner(self,"ANCHOR_BOTTOM")
      GameTooltip:SetText(self.label:GetText() or v.label,1,1,1,1,true)
      if self.desc then GameTooltip:AddLine(self.desc,0.85,0.85,0.85,true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
      if UI.view~=self.key then self.bg:Hide() end
      GameTooltip_Hide()
    end)
    b:SetScript("OnClick", function(self)
      if self.key=="bank" and UI.state.bank.mode then UI.state.bank.mode=nil; UI:CloseDetails() end
      -- the sidebar always opens Groups on Everything, so a board picked earlier
      -- (Events from the calendar, say) doesn't hide run requests and groups
      if self.key=="activities" and UI.view~="activities" then UI.state.activities.kind="all" end
      if v.onSelect then v.onSelect() else UI:SetView(self.key) end
    end)
    b.key = key
    b.baseY = y
    UI.nav[key] = b
    y = y - 30
  end
end
UI.bankSort=Btn(sectionTabs,"Sort",70,25)
UI.bankSort:SetIcon("Interface\\Icons\\INV_Misc_Gem_Variety_02")
UI.bankSort.tip="Recommend recipe recipients, distribute materials, or review items to sell."
UI.bankSort:SetScript("OnClick",function()
  UI.state.bank.mode="sort"
  UI.bankPlan=nil
  UI:CloseDetails()
  UI:SetView("bank")
end)
UI.bankStv=Btn(sectionTabs,"STV pages",70,25)
UI.bankStv:SetIcon("Interface\\Icons\\INV_Misc_Book_09")
UI.bankStv.tip="Green Hills of Stranglethorn pages: what the bank has for each chapter, and requests."
UI.bankStv:SetScript("OnClick",function()
  UI.state.bank.mode="stv"
  UI:CloseDetails()
  UI:SetView("bank")
end)
-- Section buttons look exactly like the other sidebar entries (flat, icon over label,
-- gold strip when selected) so the sidebar reads as one list.
for _, group in ipairs(GROUPS) do
  local button = CreateFrame("Button", nil, side)
  button:SetSize(SIDEBAR_W - 12, 28)
  button.bg = Tex(button, "BACKGROUND", C.panel2)
  button.bg:SetAllPoints()
  button.bg:Hide()
  button.strip = Tex(button, "BORDER", C.gold)
  button.strip:SetPoint("TOPLEFT"); button.strip:SetPoint("BOTTOMLEFT"); button.strip:SetWidth(2)
  button.strip:Hide()
  local icon = button:CreateTexture(nil,"ARTWORK")
  icon:SetSize(18,18)
  icon:SetPoint("TOP",0,-3)
  icon:SetTexture(Views[group.iconView].icon)
  icon:SetTexCoord(0.08,0.92,0.08,0.92)
  button.icon = icon
  button.text = Font(button, 10, C.muted)
  button.text:SetPoint("TOP",icon,"BOTTOM",0,-2)
  button.text:SetText(group.label)
  function button:SetOn(on)
    self.on = on and true or false
    self.bg:SetShown(self.on or self.hovered)
    self.strip:SetShown(self.on)
    SetColor(self.text, self.on and C.gold or C.muted)
  end
  local groupDesc = ({Bank="Bank stock, item requests, needs, what to buy and donations.",
    Professions="Market prices, crafters and recipes.", Guild="News, crafting projects and invites.",
    ["Member tools"]="Quest guides, catch-up help and your getting-started checklist."})[group.label]
  button:SetScript("OnEnter", function(self)
    self.hovered=true; self:SetOn(self.on)
    if groupDesc then
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText(group.label,1,1,1,1,true)
      GameTooltip:AddLine(groupDesc,0.85,0.85,0.85,true)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function(self) self.hovered=false; self:SetOn(self.on); GameTooltip_Hide() end)
  button:SetScript("OnClick", function()
    UI.search:SetText("")
    local v=Views[group.first]
    if v.onSelect then v.onSelect() else UI:SetView(group.first) end
  end)
  button:SetOn(false)
  group.button=button
end
-- Thin rules split the sidebar into Together (Home, Groups, Guildmates),
-- Guild (Bank, Professions, Guild) and You (Member tools, Settings, Sync).
UI.navRules = {}
for i = 1, 2 do
  local rule = Tex(side, "ARTWORK", C.line)
  rule:SetHeight(1)
  UI.navRules[i] = rule
end
local NAV_BREAK = { bank = 1, membertools = 2 }

---------------------------------------------------------------------------
-- Layout / view switching / refresh
---------------------------------------------------------------------------
function UI:Layout()
  local v = Views[self.view]
  local group = groupFor[self.view]
  self.wideNav = group ~= nil and self:GetWidth() >= 930 and not (ns.MailboxOpen and ns.MailboxOpen())
  local subnavWidth = self.wideNav and SUBNAV_W or 0
  local mainWidth = self:GetWidth() - SIDEBAR_W - subnavWidth - 2
  self.mainWidth = mainWidth
  UI.pageStatus:SetWidth(math.floor(mainWidth*0.41))
  UI.pageTitle:SetWidth(math.floor(mainWidth*0.55)-18)
  content:SetPoint("TOPLEFT", side, "TOPRIGHT", subnavWidth, 0)
  sectionTabs:ClearAllPoints()
  page:ClearAllPoints()
  sectionLine:ClearAllPoints()
  if self.wideNav then
    sectionTabs:SetPoint("TOPLEFT", side, "TOPRIGHT")
    sectionTabs:SetPoint("BOTTOMRIGHT", content, "BOTTOMLEFT")
    sectionLine:SetPoint("TOPRIGHT"); sectionLine:SetPoint("BOTTOMRIGHT"); sectionLine:SetWidth(1)
    page:SetPoint("TOPLEFT", content, "TOPLEFT")
    page:SetPoint("TOPRIGHT", content, "TOPRIGHT")
  else
    sectionTabs:SetPoint("TOPLEFT", content, "TOPLEFT")
    sectionTabs:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    sectionTabs:SetHeight(group and 30 or 0.01)
    sectionLine:SetPoint("BOTTOMLEFT"); sectionLine:SetPoint("BOTTOMRIGHT"); sectionLine:SetHeight(1)
    page:SetPoint("TOPLEFT", sectionTabs, "BOTTOMLEFT")
    page:SetPoint("TOPRIGHT", sectionTabs, "BOTTOMRIGHT")
  end
  sectionTabs:SetShown(group ~= nil)
  local showTools = v and (v.tools ~= nil or v.chips ~= nil)
    and not (self.view == "bank" and self.state.bank.mode == "sort")
  toolbar:SetShown(showTools == true)
  local filterHeight = self.view=="sync" and self.state.sync.filter~="mine" and 28 or 0
  toolbar:SetHeight(showTools and TOOLBAR_H+filterHeight or 0.01)
  local showComposer = v and not v.custom and v.composer ~= nil and (v.composer ~= "need" or ns.IsBankTrusted(ns.me))
  composer:SetShown(showComposer)
  composer:SetHeight(showComposer and COMPOSER_H or 0.01)
  listArea:ClearAllPoints()
  listArea:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT")
  local compact = det:IsShown() and mainWidth < 650
  det.panelWidth = compact and mainWidth or DETAILS_W
  det:SetWidth(det.panelWidth)
  det.body:SetWidth(det.panelWidth-6)
  det.title:SetWidth(det.panelWidth-105)
  det.subtitle:SetWidth(det.panelWidth-105)
  local showList = v and not v.custom and self.view ~= "market" and not compact
  scroll:SetShown(showList == true)
  if det:IsShown() and not compact then
    listArea:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT", -DETAILS_W, 0)
  else
    listArea:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT")
  end
  -- composer contents
  if showComposer then
    local need = (v.composer == "need")
    self.composerMode = v.composer
    local officerFor = (not need) and ns.IsBankTrusted(ns.me)
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
  if key == "groups" then key = "activities"; self.state.activities.kind = "all" end
  if Views[key] and Views[key].officer and not ns.IsTrusted(ns.me) then key = "needs" end
  if not Views[key] then key = "needs" end
  if self.view ~= key then
    if det:IsShown() then det:Hide(); det.kind, det.key = nil, nil; self.selected = nil end
    self.requestTo = nil
    self.detailHistory=nil
    if key == "invites" or key == "market" then self.search:SetText("") end
  end
  self.view = key
  local searchHint=({bank="Search items or bank holders",roster="Search guildmates or roles",recipes="Search recipes or crafters",
    activities="Search groups and events",market="Search materials and crafts",settings="Search settings"})[key]
  self.search.ph:SetText(searchHint or ("Search "..Views[key].label:lower()))
  for k, b in pairs(self.nav) do
    local on = (k == key)
    b.bg:SetShown(on); b.strip:SetShown(on)
    SetColor(b.label, on and C.gold or C.muted)
  end
  for _, v in pairs(Views) do if v.bar then v.bar:Hide() end end
  local v = Views[key]
  if not v.bar then v.bar = NewBar(v); UI.bars = UI.bars or {}; UI.bars[key] = v.bar end
  v.bar:Show()
  ns.SetGatheringMarketVisible(key == "market", content, footer, page)
  officerScroll:SetShown(v.custom == true)
  officerPage:Show()
  scroll:SetShown(not v.custom and key ~= "market")
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
  self.emptyAction:Hide()
  self:SetFilterSummary()
  local g = ns.G()
  local officer = ns.IsTrusted(ns.me)
  local pageNames={bank="Guild bank",officer="Officer tools"}
  self.pageTitle:SetText(self.view=="bank" and self.state.bank.mode=="sort" and "Sort the bank"
    or pageNames[self.view] or Views[self.view].label)
  self.pageStatus:SetText("")
  SetColor(self.pageStatus,C.muted)
  if g and self.view=="roster" then
    local online=0
    for _, member in pairs(ns.roster) do if member.online then online=online+1 end end
    self.pageStatus:SetText(online.." online")
  elseif g and self.view=="officer" then
    local waiting=InboxWaiting()
    self.pageStatus:SetText(waiting>0 and (waiting.." Discord updates waiting") or "")
  elseif g and self.view=="sync" then
    local label, tone = ns.SyncStatus()
    self.pageStatus:SetText(label)
    SetColor(self.pageStatus,tone=="green" and C.green or tone=="gold" and C.gold or C.muted)
  end

  -- Sidebar permissions and badges.
  local y = -8
  local nVisible = #GROUPS
  local visibility = {}
  for _, key in ipairs(ORDER) do
    local v = Views[key]
    visibility[key] = (not v.officer or officer) and (not v.visible or v.visible())
    if visibility[key] and not groupFor[key] then nVisible = nVisible + 1 end
  end
  local active = groupFor[self.view]
  local tabs = 0
  for _, key in ipairs(active or {}) do if visibility[key] then tabs = tabs+1 end end
  local inBank=active==groupFor.bank
  if inBank then tabs=tabs+2 end
  local tabWidth = math.min(108, math.floor((self:GetWidth()-SIDEBAR_W-16)/math.max(1,tabs)))
  local tabX, subY = 7, -12
  local step = math.min(51, math.floor((self:GetHeight() - HEADER_H - 76) / nVisible))
  for _, key in ipairs(ORDER) do
    local b, v = self.nav[key], Views[key]
    local group = groupFor[key]
    local rule = NAV_BREAK[key] and self.navRules[NAV_BREAK[key]]
    if rule then
      rule:ClearAllPoints()
      rule:SetPoint("TOPLEFT", side, "TOPLEFT", 12, y - 3)
      rule:SetPoint("TOPRIGHT", side, "TOPLEFT", SIDEBAR_W - 12, y - 3)
      y = y - 8
    end
    if group and group[1] == key then
      local button = group.button
      button:SetHeight(step - 2)
      button:ClearAllPoints(); button:SetPoint("TOPLEFT", 6, y); y = y - step
      button:SetOn(active == group)
    end
    local visible = visibility[key] and (not group or group == active)
    b:SetShown(visible)
    if visible then
      b:ClearAllPoints()
      if group then
        b.strip:ClearAllPoints()
        b.label:ClearAllPoints()
        b.badge:ClearAllPoints()
        b.icon:SetSize(self.wideNav and 18 or 14,self.wideNav and 18 or 14)
        b.icon:Show()
        if self.wideNav then
          b:SetSize(SUBNAV_W-16,34)
          b:SetPoint("TOPLEFT",8,subY)
          subY=subY-37
          b.strip:SetPoint("TOPLEFT"); b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetWidth(2)
          b.label:SetPoint("LEFT",b.icon,"RIGHT",7,0)
          b.badge:SetHeight(14)
          b.badge:SetPoint("RIGHT",-6,0)
        else
          b:SetSize(tabWidth,28)
          b:SetPoint("TOPLEFT",tabX,-1)
          tabX=tabX+tabWidth
          b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetPoint("BOTTOMRIGHT"); b.strip:SetHeight(2)
          b.label:SetPoint("LEFT",b.icon,"RIGHT",4,-2)
          b.badge:SetHeight(12)
          b.badge:SetPoint("TOPRIGHT",-2,1)
        end
        local selected=self.view==key and (key~="bank" or not self.state.bank.mode)
        b.bg:SetShown(selected); b.strip:SetShown(selected)
        SetColor(b.label,selected and C.gold or C.muted)
      else
        b:SetHeight(step-2)
        b:SetPoint("TOPLEFT",6,y)
        y=y-step
      end
    end
    if visibility[key] then
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
      if visible and group then
        local labelLeft = self.wideNav and 33 or 26
        local badgeWidth = self.wideNav and b.badge:IsShown() and b.badge:GetWidth()+4 or 0
        b.label:SetWidth(b:GetWidth()-labelLeft-badgeWidth-6)
      end
    end
  end
  self.bankSort:SetShown(inBank)
  if inBank then
    self.bankSort:ClearAllPoints()
    if self.wideNav then
      self.bankSort:SetPoint("TOPLEFT",8,subY)
      self.bankSort:SetSize(SUBNAV_W-16,32)
    else
      self.bankSort:SetPoint("TOPLEFT",tabX,-2)
      self.bankSort:SetSize(tabWidth-4,25)
    end
    self.bankSort:SetOn(self.view=="bank" and self.state.bank.mode=="sort")
    self.bankStv:ClearAllPoints()
    if self.wideNav then
      self.bankStv:SetPoint("TOPLEFT",8,subY-37)
      self.bankStv:SetSize(SUBNAV_W-16,32)
    else
      self.bankStv:SetPoint("TOPLEFT",tabX+tabWidth,-2)
      self.bankStv:SetSize(tabWidth-4,25)
    end
    self.bankStv:SetOn(self.view=="bank" and self.state.bank.mode=="stv")
  end
  self.bankStv:SetShown(inBank)
  if Views[self.view].officer and not officer then return self:SetView("needs") end

  if not g and self.view ~= "market" then
    ShowRows({}, 400)
    self.empty:SetText("Join a guild to use EPU Guild Tools.")
    self.empty:Show()
    self.footerText:SetText("")
    goldText:SetText("")
    syncText:SetText("")
    return
  end

  local gold = 0
  for _, s in pairs(g and g.bank or {}) do if not s.retired then gold = gold + (s.money or 0) end end
  goldText:SetText(g and Money(gold) or "")
  if ns.newestVersion then
    syncText:SetText("|cfff2c14ev" .. ns.newestVersion .. " out|r")
  elseif ns.SyncStatus then
    local label, tone = ns.SyncStatus()
    label = ({["Sync cooling down"]="Sync paused",["Unconfirmed data"]="Unconfirmed",
      ["Waiting for an officer"]="Awaiting officer",["Waiting for guild data"]="Awaiting sync"})[label] or label
    local hex = (tone == "green" and "6fcf73") or (tone == "gold" and "f2c14e") or "7e8590"
    syncText:SetText("|cff" .. hex .. label .. "|r")
  else
    syncText:SetText("v" .. ns.VERSION)
  end

  if self.view == "market" then
    self.empty:Hide()
    thumb:Hide()
    ns.RefreshGatheringMarket()
    return
  end

  local v = Views[self.view]
  -- toolbar chip states
  local bar = v.bar
  if bar then
    local stKey = v.stateKey or (v == Views.requests and "requests") or (v == Views.needs and "needs") or (v == Views.crafters and "crafters") or nil
    for _, chip in ipairs(bar.chips) do chip:SetOn(stKey and self.state[stKey].filter == chip.key) end
    if v == Views.requests then self.craftsChip:SetOn(self.state.requests.crafts == true) end
    if v == Views.shopping then bar.export:SetEnabled(ns.HasAuctionator()) end
    if v == Views.bank then
      local sorting = self.state.bank.mode ~= nil
      self.bankCatChip:SetShown(not sorting); self.bankStockChip:SetShown(not sorting); self.bankQualityChip:SetShown(not sorting)
      self.bankCatChip:SetLabel(self.state.bank.cat or "All categories")
      self.bankCatChip:SetOn(self.state.bank.cat ~= nil)
      self.bankStockChip:SetLabel(({all='All stock',stocked='In stock',available='Available now',restock='Awaiting restock'})[self.state.bank.stock] or 'All stock')
      self.bankStockChip:SetOn(self.state.bank.stock~='all')
      self.bankQualityChip:SetLabel(({[0]='Poor',[1]='Common',[2]='Uncommon',[3]='Rare',[4]='Epic+'})[self.state.bank.quality] or 'Any quality')
      self.bankQualityChip:SetOn(self.state.bank.quality~=nil)
    end
    if v == Views.roster then
      local st = self.state.roster
      local shows = { online = "Online", all = "Everyone", near = "Near my level", looking = "Looking for partner", layer = "On my layer" }
      self.showChip:SetLabel("Show: " .. (shows[st.filter] or "Online"))
      self.showChip:SetOn(st.filter ~= "online")
      if self.lookingBtn then self.lookingBtn:SetOn(ns.LookingForPartner and ns.LookingForPartner() or false) end
      self.roleChip:SetLabel(st.role and ns.ROLES[st.role] or "Any role")
      self.roleChip:SetOn(st.role ~= nil)
      local labels = { inactive = "Inactive", promote = "Promote?", note = "Has note" }
      self.reviewChip:SetLabel(st.review and labels[st.review] or "Officer review")
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
    if v == Views.sync then
      local st = self.state.sync
      local showFilters = st.filter~="mine"
      bar.status:SetShown(showFilters); bar.sort:SetShown(showFilters)
      for _, option in ipairs(syncFilters) do
        if option.value==st.status then bar.status:SetLabel(option.label); break end
      end
      for _, option in ipairs(syncSorts) do
        if option.value==st.sort then bar.sort:SetLabel("Sort: "..option.label); break end
      end
      bar.status:SetOn(st.status~="all")
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
  local query=Q()
  local okRows, rows, total, shown = ns.SafeCall(v.rows, g, query)
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
    self.empty:SetWidth(math.max(200,width-40))
    self.empty:SetText("|cffff6060The " .. (v.label or "") .. " page couldn't load.|r\n\n"
      .. "|cffffffffWhat went wrong:|r " .. e.plain .. "\n"
      .. "|cffffffffWhere:|r " .. (e.where or "unknown") .. ", addon v" .. ns.VERSION .. "\n\n"
      .. "|cff9aa1ab" .. e.raw:sub(1, 240) .. "|r\n\n"
      .. "Try /reload. If it keeps happening, send a screenshot of this to an officer.")
    self.empty:Show()
    self.footerText:SetText("")
    return
  end
  if bar and toolbar:IsShown() then
    local wrap=bar:Fit(self.mainWidth or width)
    local syncFiltersVisible=v==Views.sync and self.state.sync.filter~="mine"
    toolbar:SetHeight(TOOLBAR_H+((wrap or syncFiltersVisible) and 28 or 0))
  end
  ShowRows(rows, width, v.icon)
  local filtersOn=v.filtered and v.filtered()
  local function ClearFilters()
    v.clearFilters()
    scroll:SetVerticalScroll(0)
    if self.search:GetText()~="" then self.clearSearch:Click() else self:Refresh() end
  end
  if total and v.clearFilters and (query~="" or filtersOn) then
    self:SetFilterSummary(shown or #rows,total,ClearFilters)
  end
  self.empty:SetWidth(math.max(200, width - 60))
  local emptyText = v.empty
  if #rows==0 then
    local label, action
    if query~="" then
      emptyText = "|cffffffffNo search results|r\nTry a shorter search or clear it to see this page again."
      label,action="Clear search",function() self.clearSearch:Click() end
    elseif filtersOn then
      emptyText = "|cffffffffNothing matches these filters|r\nClear the filters to see more results."
      label,action="Clear filters",ClearFilters
    elseif not g.syncedAt and not ns.IsBankTrusted(ns.me) then
      emptyText = "|cffffffffWaiting for guild data|r\nThis page will fill in after a guildmate shares data."
      label,action="Sync now",function() ns.FullSync() end
    end
    if label then
      self.emptyAction:SetLabel(label)
      self.emptyAction:SetScript("OnClick",action)
      self.emptyAction:Show()
    end
  end
  self.empty:SetText(emptyText or "Nothing to show here yet.")
  self.empty:SetShown(#rows == 0)
  local foot = v.footer and v.footer(g) or ""
  if ns.HasUnconfirmed and ns.HasUnconfirmed() then
    foot = "|cfff2c14eUnconfirmed:|r passed on by a guildmate; an officer's addon will check it." .. ((foot ~= "") and ("  " .. foot) or "")
  end
  self.footerText:SetText(foot)
  UpdateThumb()
  -- don't wipe what an officer is typing in the details panel
  if det:IsShown() and not (det.casualDraft or (ns.CasualFormKind and ns.CasualFormKind(det.kind))) and not (self.focusBox and self.focusBox:GetParent() == det.body) then
    local offset=det.scroll:GetVerticalScroll()
    self:FillDetails()
    if det:IsShown() then
      det.scroll:SetVerticalScroll(math.max(0,math.min(offset,det.body:GetHeight()-det.scroll:GetHeight())))
      det:UpdateScroll()
    end
  end
end

UI:SetScript("OnShow", function(self)
  ns.RequestRoster()
  if not self.view then self:SetView("home") else self:Layout(); self:Refresh() end
end)

ns.On("PLAYER_LOGIN", function() UI:RestoreLayout() end)
local function RefreshMailboxLayout()
  if UI:IsShown() then UI:Layout(); UI:Refresh() end
end
ns.On("MAIL_SHOW", RefreshMailboxLayout)
ns.On("MAIL_CLOSED", RefreshMailboxLayout)

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mb = CreateFrame("Button", "EPUGuildMinimapButton", Minimap)
local buttonSize = 28
mb:SetSize(buttonSize, buttonSize)
mb:SetClampedToScreen(true)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mb:RegisterForDrag("LeftButton")
local mbIcon = mb:CreateTexture(nil, "ARTWORK")
mbIcon:SetTexture(ns.LOGO_SMALL)
mbIcon:SetAllPoints()
local mbGlow = mb:CreateTexture(nil, "HIGHLIGHT")
mbGlow:SetTexture(ns.LOGO_SMALL)
mbGlow:SetAllPoints()
mbGlow:SetBlendMode("ADD")
mbGlow:SetAlpha(0.35)

local buttonPanel
local buttonShapes={
  SQUARE={false,false,false,false},
  ["CORNER-TOPLEFT"]={true,false,false,false},["CORNER-TOPRIGHT"]={false,false,true,false},
  ["CORNER-BOTTOMLEFT"]={false,true,false,false},["CORNER-BOTTOMRIGHT"]={false,false,false,true},
  ["SIDE-LEFT"]={true,true,false,false},["SIDE-RIGHT"]={false,false,true,true},
  ["SIDE-TOP"]={true,false,true,false},["SIDE-BOTTOM"]={false,true,false,true},
  ["TRICORNER-TOPLEFT"]={true,true,true,false},["TRICORNER-TOPRIGHT"]={true,false,true,true},
  ["TRICORNER-BOTTOMLEFT"]={true,true,false,true},["TRICORNER-BOTTOMRIGHT"]={false,true,true,true},
}
local function ButtonGap()
  local n=tonumber(ns.db.settings.minimapGap)
  return n and n==n and math.max(16,math.min(80,n)) or 20
end
function ns.MinimapButtonOffset(angle,width,height,shape,gap)
  angle=tonumber(angle) or 200
  if angle~=angle or angle==math.huge or angle==-math.huge then angle=200 end
  local a=math.rad(angle%360); local x,y=math.cos(a),math.sin(a)
  local corners=buttonShapes[shape]; local quadrant=(x<0 and 1 or 3)+(y<0 and 1 or 0)
  if corners and not corners[quadrant] then
    local edge=math.max(math.abs(x),math.abs(y)); x,y=x/edge,y/edge
  end
  return x*(width/2+gap),y*(height/2+gap)
end

local function NearbyMinimapButtons(scale)
  local bounds = {}
  local function Add(button)
    if not button or button == mb or not button:IsObjectType("Button") or not button:IsVisible() then return end
    local left,bottom,width,height = button:GetRect()
    local buttonScale = button:GetEffectiveScale()
    if not left or not bottom or not width or not height or not buttonScale or buttonScale <= 0 then return end
    local ratio = buttonScale/scale
    if width*ratio > 70 or height*ratio > 70 then return end
    local margin = buttonSize/2 + 3
    bounds[#bounds+1] = {left*ratio-margin, bottom*ratio-margin,
      (left+width)*ratio+margin, (bottom+height)*ratio+margin}
  end
  local function AddChildren(parent)
    if not parent then return end
    for _, child in ipairs({parent:GetChildren()}) do Add(child) end
  end
  AddChildren(Minimap)
  AddChildren(MinimapCluster)
  AddChildren(MinimapBackdrop)
  Add(EPUGuildEventBubble)
  return bounds
end

local function PlaceButton(dragging)
  if not ns.db then return end
  local w,h=Minimap:GetWidth(),Minimap:GetHeight()
  if not w or not h or w<=0 or h<=0 then return end
  local shape=GetMinimapShape and GetMinimapShape() or "ROUND"
  local gap=ButtonGap()
  local angle=tonumber(ns.db.settings.minimapAngle) or 200
  if angle~=angle or angle==math.huge or angle==-math.huge then angle=200 end
  local x,y=ns.MinimapButtonOffset(angle,w,h,shape,gap)
  -- Screen clamping alone can push a button back over a map at the screen
  -- edge. Prefer the nearest perimeter position with room for the grab area.
  local mx,my=Minimap:GetCenter(); local scale=Minimap:GetEffectiveScale()
  if mx and my and scale and scale>0 then
    local sw=UIParent:GetWidth()*UIParent:GetEffectiveScale()/scale
    local sh=UIParent:GetHeight()*UIParent:GetEffectiveScale()/scale
    local bounds=dragging and {} or NearbyMinimapButtons(scale)
    local function OnScreen(px,py) return px>=22 and px<=sw-22 and py>=22 and py<=sh-22 end
    local function Open(px,py)
      for _, box in ipairs(bounds) do
        if px>box[1] and py>box[2] and px<box[3] and py<box[4] then return false end
      end
      return true
    end
    local fallbackX,fallbackY
    for attempt=0,72 do
      local delta=math.ceil(attempt/2)*5*(attempt%2==1 and 1 or -1)
      local dx,dy=ns.MinimapButtonOffset(angle+delta,w,h,shape,gap)
      local px,py=mx+dx,my+dy
      if OnScreen(px,py) then
        if not fallbackX then fallbackX,fallbackY=dx,dy end
        if Open(px,py) then fallbackX,fallbackY=dx,dy; break end
      end
    end
    if fallbackX then x,y=fallbackX,fallbackY end
  end
  mb:SetFrameLevel(math.max(8,Minimap:GetFrameLevel()+10))
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", x,y)
end

function ns.UpdateMinimapButton()
  if not ns.db then return end
  if ns.db.settings.hideMinimap then mb:Hide() else mb:Show(); PlaceButton() end
  if buttonPanel then
    buttonPanel.lock:SetLabel(ns.db.settings.minimapLocked and "Unlock dragging" or "Lock dragging")
    buttonPanel.visible:SetLabel(ns.db.settings.hideMinimap and "Show button" or "Hide button")
    buttonPanel.status:SetText("Distance from edge: "..ButtonGap().." · "..(ns.db.settings.minimapLocked and "Dragging locked" or "Drag around the minimap edge"))
  end
end
function ns.ResetMinimapButton()
  ns.db.settings.minimapAngle=200; ns.db.settings.minimapGap=20
  ns.db.settings.hideMinimap=false; ns.db.settings.minimapLocked=false
  ns.UpdateMinimapButton()
end
function ns.ShowMinimapButtonSettings()
  if not buttonPanel then
    local p=ns.InterfaceWindow("EPUGuildButtonSettings",UIParent,"Minimap button",400,330)
    buttonPanel=p
    local hint=Font(p,12,C.text); hint:SetPoint("TOPLEFT",20,-38); hint:SetWidth(360); hint:SetWordWrap(true)
    hint:SetText("Choose a position or drag the button around the edge. Add space to avoid other minimap buttons.")
    local presets={{"Top left",135},{"Top",90},{"Top right",45},{"Left",180},{"Reset",false},{"Right",0},{"Bottom left",225},{"Bottom",270},{"Bottom right",315}}
    p.presets={}
    for i,spec in ipairs(presets) do
      local angle=spec[2]; local b=Btn(p,spec[1],112,26)
      b:SetPoint("TOPLEFT",20+((i-1)%3)*124,-82-math.floor((i-1)/3)*32)
      b:SetScript("OnClick",function()
        if angle==false then ns.ResetMinimapButton() else ns.db.settings.minimapAngle=angle; ns.db.settings.hideMinimap=false; ns.UpdateMinimapButton() end
      end)
      p.presets[i]=b
    end
    p.closer=Btn(p,"Closer",112,24); p.closer:SetPoint("TOPLEFT",20,-190)
    p.closer:SetScript("OnClick",function() ns.db.settings.minimapGap=math.max(16,ButtonGap()-8); ns.UpdateMinimapButton() end)
    p.further=Btn(p,"Further out",112,24); p.further:SetPoint("TOPLEFT",144,-190)
    p.further:SetScript("OnClick",function() ns.db.settings.minimapGap=math.min(80,ButtonGap()+8); ns.UpdateMinimapButton() end)
    p.status=Font(p,11,C.muted); p.status:SetPoint("TOPLEFT",20,-228); p.status:SetWidth(360); p.status:SetWordWrap(true)
    p.lock=Btn(p,"Lock dragging",170,24); p.lock:SetPoint("BOTTOMLEFT",20,22)
    p.lock:SetScript("OnClick",function() ns.db.settings.minimapLocked=not ns.db.settings.minimapLocked; mb:SetScript("OnUpdate",nil); ns.UpdateMinimapButton() end)
    p.visible=Btn(p,"Hide button",170,24); p.visible:SetPoint("BOTTOMRIGHT",-20,22)
    p.visible:SetScript("OnClick",function() ns.db.settings.hideMinimap=not ns.db.settings.hideMinimap; ns.UpdateMinimapButton() end)
  end
  ns.UpdateMinimapButton(); buttonPanel:Show()
end

mb:SetScript("OnClick", function(self, button)
  if self.suppressClickUntil and GetTime()<=self.suppressClickUntil then return end
  if IsShiftKeyDown() and ns.ShowGuildMapSettings then ns.ShowGuildMapSettings()
  elseif button == "RightButton" then ns.FullSync() else UI:Toggle() end
end)
mb:SetScript("OnDragStart", function(self)
  if ns.db.settings.minimapLocked then return end
  GameTooltip_Hide()
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    if not mx or not my or not s or s<=0 then return end
    local x=(px/s-mx)/(Minimap:GetWidth()/2+ButtonGap())
    local y=(py/s-my)/(Minimap:GetHeight()/2+ButtonGap())
    if x==0 and y==0 then return end
    ns.db.settings.minimapAngle = math.deg(math.atan2(y,x))%360
    PlaceButton(true)
  end)
end)
mb:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
  self.suppressClickUntil=GetTime()+0.25
  PlaceButton()
end)
mb:SetScript("OnHide",function(self) self:SetScript("OnUpdate",nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("EPU Guild Tools")
  GameTooltip:AddLine("Left-click: open window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: resync with officers", 1, 1, 1)
  GameTooltip:AddLine("Shift-click: guild map settings", 1, 1, 1)
  GameTooltip:AddLine(ns.db.settings.minimapLocked and "Dragging locked" or "Drag: move around the edge", 1, 1, 1)
  GameTooltip:AddLine("/epu button: position, spacing and reset", 1, 1, 1)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", GameTooltip_Hide)

ns.On("PLAYER_LOGIN", ns.UpdateMinimapButton)
ns.On("PLAYER_ENTERING_WORLD",ns.UpdateMinimapButton)
ns.On("UI_SCALE_CHANGED",ns.UpdateMinimapButton)
ns.On("DISPLAY_SIZE_CHANGED",ns.UpdateMinimapButton)
Minimap:HookScript("OnSizeChanged",function() PlaceButton() end)

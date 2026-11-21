-- EPU Guild Tools: Customizable floating windows for Combat Log, XP & Rep, and Server/Loot.
local _, ns = ...

local DEFAULTS = {
  combat = { title = "EPU Combat Log", enabled = false, maxLines = 150, fontSize = 11, x = -260, y = 120 },
  xp = { title = "EPU XP & Reputation", enabled = false, maxLines = 120, fontSize = 11, x = 0, y = 120 },
  system = { title = "EPU Server & Loot", enabled = false, maxLines = 150, fontSize = 11, x = 260, y = 120 },
}

local frames = {}
local logs = { combat = {}, xp = {}, system = {} }
local rawLogs = { combat = {}, xp = {}, system = {} }
local paused = {}
local sessionStart = time()
local sessionXP = 0

local function DB()
  if not ns.db then return {} end
  ns.db.logWindows = ns.db.logWindows or {}
  for k, def in pairs(DEFAULTS) do
    ns.db.logWindows[k] = ns.db.logWindows[k] or {}
    local s = ns.db.logWindows[k]
    if s.enabled == nil then s.enabled = def.enabled end
    if s.fontSize == nil then s.fontSize = def.fontSize end
  end
  return ns.db.logWindows
end

local function RefreshWindow(kind)
  local f = frames[kind]
  if not f or not f:IsShown() then return end
  local cfg = DB()[kind] or DEFAULTS[kind]
  local C = ns.InterfaceColors
  local fnt = f.text.SetFont and f.text:GetFont()
  if fnt then f.text:SetFont(fnt, cfg.fontSize or 11, "") end

  local header = ""
  if kind == "xp" then
    local elapsed = math.max(1, time() - sessionStart)
    local xph = math.floor((sessionXP / elapsed) * 3600)
    header = string.format("|cff4fc3f7Session XP: %d  (%d/hr)|r\n\n", sessionXP, xph)
  end
  f.text:SetText(header .. (#logs[kind] > 0 and table.concat(logs[kind], "\n") or "|cff888888Waiting for messages...|r"))
  f.child:SetHeight(math.max(100, (f.text:GetStringHeight() or 40) + 16))
  if f.scroll and f.scroll.SetVerticalScroll then
    local maxV = math.max(0, (f.child:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
    f.scroll:SetVerticalScroll(maxV)
  end
end

local function Append(kind, msg, colorHex)
  if paused[kind] or type(msg) ~= "string" or msg == "" then return end
  if issecretvalue and issecretvalue(msg) then return end
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

local function EnsureWindow(kind)
  if frames[kind] then return frames[kind] end
  local def = DEFAULTS[kind]
  local cfg = DB()[kind] or def
  local C = ns.InterfaceColors
  local f = ns.InterfaceWindow("EPUGuildLog_" .. kind, UIParent, def.title, 340, 260)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or def.x, cfg.y or def.y)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(220, 140, 800, 700) end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    local s = DB()[kind]
    if s then s.x, s.y = math.floor(x or 0), math.floor(y or 0) end
  end)

  local clr = ns.InterfaceButton(f, "Clear", 48, 20)
  clr:SetPoint("TOPRIGHT", -36, -7)
  clr:SetScript("OnClick", function() logs[kind] = {}; RefreshWindow(kind) end)

  local pauseBtn = ns.InterfaceButton(f, "Pause", 48, 20)
  pauseBtn:SetPoint("RIGHT", clr, "LEFT", -4, 0)
  pauseBtn:SetScript("OnClick", function(self)
    paused[kind] = not paused[kind]
    self:SetText(paused[kind] and "Resume" or "Pause")
  end)

  local smaller = ns.InterfaceButton(f, "A-", 26, 20)
  smaller:SetPoint("RIGHT", pauseBtn, "LEFT", -4, 0)
  smaller:SetScript("OnClick", function()
    local s = DB()[kind]; s.fontSize = math.max(9, (s.fontSize or 11) - 1); RefreshWindow(kind)
  end)

  local bigger = ns.InterfaceButton(f, "A+", 26, 20)
  bigger:SetPoint("RIGHT", smaller, "LEFT", -2, 0)
  bigger:SetScript("OnClick", function()
    local s = DB()[kind]; s.fontSize = math.min(20, (s.fontSize or 11) + 1); RefreshWindow(kind)
  end)

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 10, -40)
  scroll:SetPoint("BOTTOMRIGHT", -10, 12)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(310); child:SetHeight(160)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 32)))
  end)

  local text = ns.InterfaceFont(child, cfg.fontSize or 11, C.text)
  text:SetPoint("TOPLEFT", 2, -2)
  text:SetWidth(306)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(true)

  f.scroll, f.child, f.text = scroll, child, text
  frames[kind] = f
  return f
end

function ns.IsLogWindowEnabled(kind)
  local s = DB()[kind]
  return s and s.enabled == true
end

function ns.ToggleLogWindow(kind, force)
  if not DEFAULTS[kind] then return end
  local s = DB()[kind]
  if force == nil then s.enabled = not s.enabled else s.enabled = force and true or false end
  local f = EnsureWindow(kind)
  if s.enabled then
    RefreshWindow(kind)
    f:Show()
  else
    f:Hide()
  end
end

function ns.OpenLogWindowsMenu()
  ns.ToggleLogWindow("combat", true)
  ns.ToggleLogWindow("xp", true)
  ns.ToggleLogWindow("system", true)
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    for kind in pairs(DEFAULTS) do
      if ns.IsLogWindowEnabled(kind) then
        local f = EnsureWindow(kind)
        RefreshWindow(kind)
        f:Show()
      end
    end
  end)

  ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
    if type(msg) == "string" then
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

  for _, ev in ipairs({
    "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
    "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
    "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
  }) do
    ns.On(ev, function(msg) Append("combat", msg, "|cffff9e64") end)
  end
end

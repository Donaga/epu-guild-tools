-- EPU Guild Tools: reusable widgets for windows that redraw their contents.
--
-- The game never frees a frame, font string or texture once it is made:
-- hiding it or calling SetParent(nil) only takes it off the screen. A window
-- that makes new ones every time it refreshes therefore grows for the whole
-- session. A pool keeps what one refresh made and hands the same widgets out
-- again on the next refresh, so a window only ever holds as many widgets as
-- its busiest refresh needed.
--
--   local pool = ns.NewWidgetPool(parentFrame)
--   pool:ReleaseAll()                      -- start of every refresh
--   local fs = pool:Font(12, C.text)       -- font strings on parentFrame
--   local b = pool:Button("OK", 80, 22)    -- EPU buttons
--   local t = pool:Texture("ARTWORK")      -- textures
--   local box, inner = pool:Frame("card")  -- child frame with its own pool
--
-- Widgets are pooled by kind. Pass the same tag from the same place in the
-- code, so a widget that one caller sized or wrapped is only handed back to
-- a caller that sets those things up the same way.
local _, ns = ...

local Pool = {}
Pool.__index = Pool

function ns.NewWidgetPool(owner)
  return setmetatable({ owner = owner, free = {}, used = {}, made = 0 }, Pool)
end

-- A widget of this kind: one the last refresh used, or a new one from make().
function Pool:Get(kind, make)
  local free = self.free[kind]
  local w = free and table.remove(free)
  if not w then
    w = make(self.owner)
    w.epuPoolKind = kind
    self.made = self.made + 1
  end
  self.used[#self.used + 1] = w
  if w.ClearAllPoints then w:ClearAllPoints() end
  w:Show()
  return w
end

-- Hide everything handed out since the last call, ready to hand out again.
function Pool:ReleaseAll()
  for _, w in ipairs(self.used) do
    w:Hide()
    if w.epuPool then w.epuPool:ReleaseAll() end
    local list = self.free[w.epuPoolKind]
    if not list then list = {}; self.free[w.epuPoolKind] = list end
    list[#list + 1] = w
  end
  self.used = {}
end

-- How many widgets this pool (and the frames it handed out) has ever made.
function Pool:Made()
  local n = self.made
  for _, list in pairs(self.free) do
    for _, w in ipairs(list) do if w.epuPool then n = n + w.epuPool:Made() end end
  end
  for _, w in ipairs(self.used) do if w.epuPool then n = n + w.epuPool:Made() end end
  return n
end

function Pool:InUse() return #self.used end

local function Color(c, fallback)
  c = c or fallback or { 1, 1, 1 }
  return c[1], c[2], c[3]
end

function Pool:Font(size, color, tag)
  size = size or 12
  local fs = self:Get("font:" .. size .. ":" .. (tag or ""), function(owner)
    return ns.InterfaceFont(owner, size, color)
  end)
  fs:SetTextColor(Color(color, ns.InterfaceColors and ns.InterfaceColors.text))
  fs:SetJustifyH("LEFT")
  fs:SetText("")
  return fs
end

function Pool:Button(text, w, h, style, tag)
  local b = self:Get("button:" .. (tag or ""), function(owner)
    return ns.InterfaceButton(owner, text, w, h, style)
  end)
  b:SetSize(w or 80, h or 22)
  b.style = style
  b.tip, b.disabledTip, b.fullLabel = nil, nil, nil
  b:SetScript("OnClick", nil)
  if b.SetEnabled then b:SetEnabled(true) end
  b:SetText(text or "")
  if b.SetOn then b:SetOn(false) end   -- also repaints for the new style
  return b
end

function Pool:Texture(layer, tag)
  layer = layer or "BACKGROUND"
  local t = self:Get("texture:" .. layer .. ":" .. (tag or ""), function(owner)
    return owner:CreateTexture(nil, layer)
  end)
  t:SetVertexColor(1, 1, 1, 1)
  if t.SetRotation then t:SetRotation(0) end
  return t
end

function Pool:Input(w, placeholder, tag)
  local e = self:Get("input:" .. (tag or ""), function(owner)
    return ns.InterfaceInput(owner, w, placeholder)
  end)
  e:SetWidth(w or 120)
  if e.ClearFocus then e:ClearFocus() end
  e:SetText("")
  if e.ph then e.ph:SetText(placeholder or "") end
  return e
end

-- A child frame with a pool of its own for what goes inside it. setup(f)
-- runs once, when the frame is first made, for parts every use shares.
function Pool:Frame(tag, setup)
  local f = self:Get("frame:" .. (tag or ""), function(owner)
    local nf = CreateFrame("Frame", nil, owner)
    nf.epuPool = ns.NewWidgetPool(nf)
    if setup then setup(nf) end
    return nf
  end)
  return f, f.epuPool
end

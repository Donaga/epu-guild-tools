-- EPU Guild Tools: the guild bank by category.
-- A window that shows everything in the guild bank grouped by kind of item
-- (Herbs, Cloth, Consumables...), like Baganator's category view of your
-- bags. Baganator's own guild bank window only shows tabs, so this is EPU's.
-- Nothing is moved for you; at the bank you can still take and add items:
--   right-click   take a stack into your bags
--   drag / click  pick a stack up on the cursor
--   drop an item  put it in the tab its category lives in (a stack of the
--                 same item there first, then an empty slot)
--   shift-click   link it in chat
-- Away from the bank it shows the guild bank as it was last seen.
--
-- At the guild bank it can open by itself (/epu vault, or the With the bank
-- menu in the window): Off (the default), Beside the guild bank window, or
-- Instead of it. Instead moves the game's guild bank window, and Baganator's
-- if it's loaded, off the screen while this one is open, and puts them back
-- when the bank closes or you press Other window. The game window still runs
-- the bank itself, so closing this window closes the bank.
-- Open it from the Guild bank view button on the main window's Bank page.
local ADDON, ns = ...

local SIZE, GAP = 36, 4
local MODES = { { "off", "Off" }, { "beside", "Beside the bank window" }, { "instead", "Instead of the bank window" } }
local MODE_SHORT = { off = "Off", beside = "Beside", instead = "Instead" }
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

local function Opt()
  if not ns.db then return {} end
  ns.db.guildVault = ns.db.guildVault or {}
  return ns.db.guildVault
end

function ns.GuildVaultMode()
  local m = Opt().mode
  if m == "beside" or m == "instead" then return m end
  return "off"
end

function ns.GuildVaultGroupBy() return Opt().group == "tab" and "tab" or "category" end

---------------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------------
-- Every stack the window can show: { tab, slot (nil when away), id, n }.
-- At the bank these are the live slots; tabs still loading, and every tab
-- when you're away, come from the last scan (counts per item, no slots).
-- info = { live, tabs (live tab details), pending, seen (newest scan time) }
function ns.GuildVaultStacks(g)
  g = g or ns.G()
  local stacks, info = {}, { live = false, tabs = {}, pending = 0, seen = nil }
  local fromLive = {}
  if ns.GuildBankIsOpen and ns.GuildBankIsOpen() and ns.GuildBankLiveStacks then
    local live, tabs, pending = ns.GuildBankLiveStacks()
    info.live, info.tabs, info.pending = true, tabs, pending
    for _, s in ipairs(live) do stacks[#stacks + 1] = s end
    for tab, t in pairs(tabs) do if t.loaded then fromLive[tab] = true end end
  end
  if g and type(g.gbTabs) == "table" then
    for tab, t in pairs(g.gbTabs) do
      if type(tab) == "number" and type(t) == "table" and not fromLive[tab] then
        if not info.seen or (tonumber(t.t) or 0) > info.seen then info.seen = tonumber(t.t) end
        for id, n in pairs(type(t.items) == "table" and t.items or {}) do
          id, n = tonumber(id), tonumber(n)
          if id and n and n > 0 then stacks[#stacks + 1] = { tab = tab, id = id, n = n } end
        end
      end
    end
  end
  return stacks, info
end

-- Group stacks for the window. Pure: everything it needs about an item comes
-- through opts, so the tests can drive it without the game.
--   opts.group     "category" (default) or "tab"
--   opts.query     lower-case search text (name or category)
--   opts.tab       show only this tab
--   opts.catOf(id), opts.nameOf(id), opts.qualityOf(id), opts.tabLabel(tab)
-- Returns sections in order: { key, title, items, kinds, total }, and each
-- item { id, n, cat, name, quality, stacks (biggest first), tabs = {tab = n}, tabOrder }.
-- One item fills one button, however many stacks and tabs it's spread over.
function ns.GuildVaultGroups(stacks, opts)
  opts = opts or {}
  local byTab = opts.group == "tab"
  local catOf = opts.catOf or function(id) local ok, c = pcall(ns.ItemCategory, id); return ok and c or "Other" end
  local nameOf = opts.nameOf or function(id) return tostring(ns.ItemName(id, true)) end
  local qualityOf = opts.qualityOf or function(id) local _, _, q = GetItemInfo(id); return q end
  local tabLabel = opts.tabLabel or function(tab) return "Tab " .. tab end
  local query = opts.query and opts.query ~= "" and opts.query:lower() or nil
  local entries, sections, secList = {}, {}, {}
  for _, s in ipairs(stacks or {}) do
    if s.id and (tonumber(s.n) or 0) > 0 and (not opts.tab or s.tab == opts.tab) then
      local key = byTab and (s.tab .. ":" .. s.id) or tostring(s.id)
      local e = entries[key]
      if not e then
        local cat = catOf(s.id)
        if type(cat) ~= "string" then cat = "Other" end
        e = { id = s.id, n = 0, cat = cat, name = tostring(nameOf(s.id) or ""), quality = tonumber(qualityOf(s.id)) or 1,
          stacks = {}, tabs = {}, tabOrder = {} }
        entries[key] = e
        local skey = byTab and ("tab:" .. s.tab) or ("cat:" .. cat)
        if not query or e.name:lower():find(query, 1, true) or cat:lower():find(query, 1, true) then
          local sec = sections[skey]
          if not sec then
            sec = { key = skey, title = byTab and tabLabel(s.tab) or cat, tab = byTab and s.tab or nil, cat = not byTab and cat or nil,
              items = {}, kinds = 0, total = 0 }
            sections[skey] = sec
            secList[#secList + 1] = sec
          end
          sec.items[#sec.items + 1] = e
          sec.kinds = sec.kinds + 1
          e.section = sec
        end
      end
      e.n = e.n + s.n
      e.stacks[#e.stacks + 1] = s
      if not e.tabs[s.tab] then e.tabOrder[#e.tabOrder + 1] = s.tab end
      e.tabs[s.tab] = (e.tabs[s.tab] or 0) + s.n
      if e.section then e.section.total = e.section.total + s.n end
    end
  end
  local catOrder = {}
  for i, c in ipairs(ns.CATEGORIES or {}) do catOrder[c] = i end
  table.sort(secList, function(a, b)
    if byTab then return a.tab < b.tab end
    local x, y = catOrder[a.cat] or 99, catOrder[b.cat] or 99
    if x ~= y then return x < y end
    return a.cat < b.cat
  end)
  for _, sec in ipairs(secList) do
    table.sort(sec.items, function(a, b)
      if a.quality ~= b.quality then return a.quality > b.quality end
      if a.name ~= b.name then return a.name < b.name end
      return a.id < b.id
    end)
    for _, e in ipairs(sec.items) do
      table.sort(e.stacks, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        if a.tab ~= b.tab then return a.tab < b.tab end
        return (a.slot or 0) < (b.slot or 0)
      end)
      table.sort(e.tabOrder)
      e.section = nil
    end
  end
  return secList
end

-- Where an item dropped on the window goes: (tab, slot, how) or nil.
--   tabs[tab] = { canDeposit, empty = {slots} }; stacks = live stacks
--   home = the tab its category lives in; current = the tab the bank shows
--   maxStack = how many of the item fit in one stack (nil: don't top up)
-- Tabs are tried in order: its home tab, tabs that already hold the item,
-- the current tab, then the rest. In each, a stack of the same item with
-- room for all of them comes first, then an empty slot.
function ns.GuildVaultDepositSpot(id, n, tabs, stacks, home, current, maxStack)
  local order, seen = {}, {}
  local function Add(tab) if tab and tabs[tab] and not seen[tab] then seen[tab] = true; order[#order + 1] = tab end end
  Add(home)
  local holding = {}
  for _, s in ipairs(stacks or {}) do if s.id == id and s.slot then holding[#holding + 1] = s.tab end end
  table.sort(holding)
  for _, tab in ipairs(holding) do Add(tab) end
  Add(current)
  local rest = {}
  for tab in pairs(tabs) do rest[#rest + 1] = tab end
  table.sort(rest)
  for _, tab in ipairs(rest) do Add(tab) end
  n = tonumber(n) or 1
  for _, tab in ipairs(order) do
    local t = tabs[tab]
    if t.canDeposit ~= false then
      if maxStack and maxStack > 1 then
        for _, s in ipairs(stacks or {}) do
          if s.tab == tab and s.slot and s.id == id and not s.locked and s.n + n <= maxStack then return tab, s.slot, "stack" end
        end
      end
      if t.empty and t.empty[1] then return tab, t.empty[1], "empty" end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- The other guild bank windows: the game's, and Baganator's
---------------------------------------------------------------------------
local stashed, hookedOthers, baganatorFrames = {}, {}, nil
local moving = false
local win
local Rehide

local function FindBaganator()
  if baganatorFrames then return baganatorFrames end
  if not Baganator or not EnumerateFrames then return {} end
  local found, f = {}, EnumerateFrames()
  while f do
    local ok, name = pcall(f.GetName, f)
    if ok and type(name) == "string" and name:find("^Baganator") and name:find("Guild") and f:GetParent() == UIParent then
      found[#found + 1] = f
    end
    f = EnumerateFrames(f)
  end
  if #found > 0 then baganatorFrames = found end
  return found
end

local function Others()
  local list = {}
  if GuildBankFrame then list[#list + 1] = GuildBankFrame end
  for _, f in ipairs(FindBaganator()) do list[#list + 1] = f end
  return list
end

local function Away(f)
  moving = true
  pcall(function()
    if f.SetClampedToScreen then f:SetClampedToScreen(false) end
    f:SetAlpha(0)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -6000, 6000)
  end)
  moving = false
end

local function Hiding()
  return win and win:IsShown() and win.instead and not win.showOthers and ns.GuildBankIsOpen and ns.GuildBankIsOpen()
end

local function Stash(f)
  if not f or stashed[f] or not f:IsVisible() then return end
  local saved = { alpha = f.GetAlpha and f:GetAlpha() or 1, clamped = f.IsClampedToScreen and f:IsClampedToScreen(), points = {} }
  for i = 1, (f.GetNumPoints and f:GetNumPoints() or 0) do saved.points[i] = { f:GetPoint(i) } end
  stashed[f] = saved
  Away(f)
  if not hookedOthers[f] then
    hookedOthers[f] = true
    -- The game (or Baganator) may put its window back in place; move it away again.
    hooksecurefunc(f, "SetPoint", function(self)
      if not moving and stashed[self] then C_Timer.After(0, function() if stashed[self] and Hiding() then Away(self) end end) end
    end)
    if f.HookScript then f:HookScript("OnShow", function(self) if Hiding() then C_Timer.After(0, Rehide) end end) end
  end
end

local function RestoreOthers()
  for f, saved in pairs(stashed) do
    moving = true
    pcall(function()
      f:SetAlpha(saved.alpha or 1)
      if f.SetClampedToScreen and saved.clamped ~= nil then f:SetClampedToScreen(saved.clamped) end
      f:ClearAllPoints()
      if #saved.points == 0 then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
      for _, p in ipairs(saved.points) do f:SetPoint(unpack(p)) end
    end)
    moving = false
    stashed[f] = nil
  end
end
ns.GuildVaultRestoreOthers = RestoreOthers

Rehide = function()
  if not Hiding() then return end
  for _, f in ipairs(Others()) do Stash(f) end
end

-- The donate panel sits beside this window while it's open at the bank.
function ns.GuildVaultDonateAnchor()
  if win and win:IsShown() and ns.GuildBankIsOpen and ns.GuildBankIsOpen() then return win end
end

local function CloseBank()
  if CloseGuildBankFrame then
    CloseGuildBankFrame()
  elseif C_PlayerInteractionManager and C_PlayerInteractionManager.ClearInteraction and Enum and Enum.PlayerInteractionType
    and Enum.PlayerInteractionType.GuildBanker then
    C_PlayerInteractionManager.ClearInteraction(Enum.PlayerInteractionType.GuildBanker)
  end
end

---------------------------------------------------------------------------
-- Taking and adding items (only at the bank)
---------------------------------------------------------------------------
local function SetTab(tab)
  if SetCurrentGuildBankTab and GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= tab then SetCurrentGuildBankTab(tab) end
end

-- The stack a click takes: the biggest one in a tab you still have withdrawals on.
local function TakeStack(e, tabs)
  for _, s in ipairs(e.stacks) do
    local t = tabs and tabs[s.tab]
    if s.slot and not s.locked and not (t and t.withdrawalsLeft == 0) then return s end
  end
end

function ns.GuildVaultDeposit()
  if not (ns.GuildBankIsOpen and ns.GuildBankIsOpen()) then return false end
  local kind, id = GetCursorInfo()
  if kind ~= "item" or not id then return false end
  local stacks, tabs = ns.GuildBankLiveStacks()
  local okc, cat = pcall(ns.ItemCategory, id)
  local plan = ns.GuildBankTabPlan and ns.GuildBankTabPlan() or { home = {} }
  local home = okc and plan.home and plan.home[cat] or nil
  local maxStack = select(8, GetItemInfo(id))
  -- GetCursorInfo doesn't say how many are on the cursor: top up any stack
  -- with room, and the game leaves what doesn't fit on the cursor
  local count = 1
  local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or nil
  local tab, slot = ns.GuildVaultDepositSpot(id, count, tabs, stacks, home, current, tonumber(maxStack))
  if not tab then
    ns.Print("No guild bank tab you can deposit in has room for " .. ns.ItemLink(id) .. ".")
    return false
  end
  SetTab(tab)
  PickupGuildBankItem(tab, slot)
  ns.Debounce("guildVaultRefresh", 0.3, function() if ns.RefreshGuildVault then ns.RefreshGuildVault() end end)
  return true, tab, slot
end

local function Withdraw(e, info)
  local s = TakeStack(e, info.tabs)
  if not s then
    ns.Print("You have no withdrawals left today on the tabs that hold " .. ns.ItemLink(e.id) .. ".")
    return
  end
  SetTab(s.tab)
  if AutoStoreGuildBankItem then AutoStoreGuildBankItem(s.tab, s.slot) else PickupGuildBankItem(s.tab, s.slot) end
end

local function PickUp(e, info)
  local s = TakeStack(e, info.tabs)
  if not s then return end
  SetTab(s.tab)
  PickupGuildBankItem(s.tab, s.slot)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local state = { tab = nil, query = "" }

local function Ago(t)
  local d = math.max(0, ns.Now() - (tonumber(t) or 0))
  if d < 120 then return "just now" end
  if d < 7200 then return math.floor(d / 60) .. " minutes ago" end
  if d < 172800 then return math.floor(d / 3600) .. " hours ago" end
  return math.floor(d / 86400) .. " days ago"
end

local function CountText(n)
  if n >= 10000 then return math.floor(n / 1000) .. "k" end
  if n <= 1 then return "" end
  return tostring(n)
end

local function TabLabel(tab)
  local g = ns.G()
  local t = g and g.gbTabs and g.gbTabs[tab]
  return ns.GuildBankTabLabel(tab, t)
end

local function ItemButton(owner)
  local C = ns.InterfaceColors
  local b = CreateFrame("Button", nil, owner)
  b:SetSize(SIZE, SIZE)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetSize(SIZE * 1.75, SIZE * 1.75)
  b.glow:SetPoint("CENTER")
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetSize(7, 7); b.mark:SetPoint("TOPRIGHT", -2, -2)
  b.mark:SetColorTexture(1, 0.7, 0.28, 1)
  b.count = ns.InterfaceFont(b, 11, C.white)
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.count:SetJustifyH("RIGHT")
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.16)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnEnter", function(self)
    local e, info = self.entry, win and win.info or {}
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local s = e.stacks[1]
    if info.live and s and s.slot and GameTooltip.SetGuildBankItem then GameTooltip:SetGuildBankItem(s.tab, s.slot)
    else GameTooltip:SetHyperlink("item:" .. e.id) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("In the guild bank: " .. e.n, C.gold[1], C.gold[2], C.gold[3])
    for _, tab in ipairs(e.tabOrder) do
      local t = info.tabs and info.tabs[tab]
      local left = t and t.withdrawalsLeft
      GameTooltip:AddLine(TabLabel(tab) .. ": " .. e.tabs[tab] .. ((left == 0) and "  (no withdrawals left today)" or ""),
        C.muted[1], C.muted[2], C.muted[3])
    end
    for _, m in ipairs(self.misplaced or {}) do GameTooltip:AddLine(TabLabel(m.tab) .. ": " .. m.why, 1, 0.7, 0.28, true) end
    if info.live then
      GameTooltip:AddLine("Right-click takes a stack. Drag to pick it up. Shift-click links it.", C.muted[1], C.muted[2], C.muted[3], true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip_Hide() end)
  b:SetScript("OnClick", function(self, button)
    local e, info = self.entry, win and win.info or {}
    if not e then return end
    if IsModifiedClick and IsModifiedClick("CHATLINK") or (IsShiftKeyDown and IsShiftKeyDown()) then
      local link = ns.ItemLink(e.id)
      if ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) elseif ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
      return
    end
    if not info.live then return end
    if GetCursorInfo() then ns.GuildVaultDeposit(); return end
    if button == "RightButton" then Withdraw(e, info) else PickUp(e, info) end
  end)
  b:SetScript("OnDragStart", function(self) if self.entry and win and win.info.live then PickUp(self.entry, win.info) end end)
  b:SetScript("OnReceiveDrag", function() ns.GuildVaultDeposit() end)
  return b
end

local function HeadButton(owner)
  local C = ns.InterfaceColors
  local h = CreateFrame("Button", nil, owner)
  h:SetHeight(22)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetAllPoints()
  h.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
  h.text = ns.InterfaceFont(h, 12, C.gold)
  h.text:SetPoint("LEFT", 6, 0)
  h.sub = ns.InterfaceFont(h, 11, C.muted)
  h.sub:SetPoint("RIGHT", -6, 0)
  h.sub:SetJustifyH("RIGHT")
  h:SetScript("OnClick", function(self)
    local col = Opt()
    col.collapsed = col.collapsed or {}
    col.collapsed[self.key] = not col.collapsed[self.key] or nil
    if win then win:Refresh() end
  end)
  h:SetScript("OnReceiveDrag", function() ns.GuildVaultDeposit() end)
  return h
end

local function Place(mode)
  local pos = Opt().pos
  win:ClearAllPoints()
  if type(pos) == "table" and pos[1] then
    win:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    return
  end
  local beside
  if mode == "beside" then
    for _, f in ipairs(Others()) do if f:IsVisible() and (f.GetAlpha and f:GetAlpha() or 1) > 0 then beside = f; break end end
  end
  if beside then win:SetPoint("TOPLEFT", beside, "TOPRIGHT", 8, 0)
  elseif mode == "instead" then win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
  else win:SetPoint("CENTER") end
end

local function Build()
  local K, C = ns.UIKit, ns.InterfaceColors
  win = ns.InterfaceWindow("EPUGuildVault", UIParent, "Guild bank by category", 600, 540)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    Opt().pos = { p, rp, x, y }
  end)

  local search = ns.InterfaceInput(win, 170, "Search the guild bank")
  search:SetPoint("TOPLEFT", 14, -44)
  search.onChange = function(self) state.query = self:GetText() or ""; if win:IsShown() then win:Refresh() end end
  win.search = search

  local group = K.Btn(win, "", 104, 22)
  group:SetPoint("LEFT", search, "RIGHT", 8, 0)
  group:SetScript("OnClick", function()
    if ns.GuildVaultGroupBy() == "tab" then Opt().group = nil else Opt().group = "tab" end
    win:Refresh()
  end)
  group.tip = "Group the items by category, or by guild bank tab."
  win.group = group

  local tabs = K.Btn(win, "", 112, 22)
  tabs:SetPoint("LEFT", group, "RIGHT", 6, 0)
  K.AddDropdownArrow(tabs)
  tabs:SetScript("OnClick", function(self)
    local g = ns.G()
    local items = { { label = "All tabs", value = false } }
    local order = {}
    for tab in pairs(g and g.gbTabs or {}) do if type(tab) == "number" then order[#order + 1] = tab end end
    table.sort(order)
    for _, tab in ipairs(order) do items[#items + 1] = { label = TabLabel(tab), value = tab } end
    K.OpenMenu(self, items, state.tab or false, function(v) state.tab = v or nil; win:Refresh() end)
  end)
  tabs.tip = "Show one guild bank tab."
  win.tabs = tabs

  local mode = K.Btn(win, "", 150, 22)
  mode:SetPoint("TOPRIGHT", -14, -44)
  K.AddDropdownArrow(mode)
  mode:SetScript("OnClick", function(self)
    local items = {}
    for _, m in ipairs(MODES) do items[#items + 1] = { label = m[2], value = m[1] } end
    K.OpenMenu(self, items, ns.GuildVaultMode(), function(v) ns.SetGuildVaultMode(v) end)
  end)
  mode.tip = "Open this window by itself at the guild bank: beside the bank window, or instead of it "
    .. "(the game's window, or Baganator's, moves off the screen until the bank closes)."
  win.mode = mode

  local scroll = CreateFrame("ScrollFrame", nil, win)
  scroll:SetPoint("TOPLEFT", 14, -76)
  scroll:SetPoint("BOTTOMRIGHT", -14, 50)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(572); child:SetHeight(400)
  child:EnableMouse(true)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * (SIZE + GAP) * 2)))
  end)
  -- drop an item anywhere in the list to deposit it
  child:SetScript("OnReceiveDrag", function() ns.GuildVaultDeposit() end)
  child:SetScript("OnMouseUp", function() if GetCursorInfo() then ns.GuildVaultDeposit() end end)
  win.scroll, win.child = scroll, child
  win.pool = ns.NewWidgetPool(child)

  win.status = ns.InterfaceFont(win, 11, C.muted)
  win.status:SetPoint("BOTTOMLEFT", 14, 30)
  win.status:SetPoint("RIGHT", win, "RIGHT", -150, 0)
  win.hint = ns.InterfaceFont(win, 11, C.muted)
  win.hint:SetPoint("BOTTOMLEFT", 14, 13)
  win.hint:SetPoint("RIGHT", win, "RIGHT", -130, 0)
  win.money = ns.InterfaceFont(win, 12, C.text)
  win.money:SetPoint("BOTTOMRIGHT", -14, 30)
  win.money:SetJustifyH("RIGHT")

  local other = K.Btn(win, "Other window", 104, 22)
  other:SetPoint("BOTTOMRIGHT", -14, 6)
  other:SetScript("OnClick", function()
    win.showOthers = true
    RestoreOthers()
    win:Refresh()
  end)
  other.tip = "Bring back the regular guild bank window (or Baganator's) for this visit, for gold and the bank log."
  win.other = other

  function win:Refresh()
    local pool = self.pool
    pool:ReleaseAll()
    self.shown = {}
    local g = ns.G()
    local stacks, info = ns.GuildVaultStacks(g)
    self.info = info
    local by = ns.GuildVaultGroupBy()
    self.group:SetText(by == "tab" and "By tab" or "By category")
    self.tabs:SetText(state.tab and ("Tab " .. state.tab) or "All tabs")
    self.mode:SetText("With the bank: " .. MODE_SHORT[ns.GuildVaultMode()])
    self.other:SetShown((info.live and self.instead and not self.showOthers and next(stashed) ~= nil) and true or false)
    local plan = ns.GuildBankTabPlan(g)
    local sections = ns.GuildVaultGroups(stacks, { group = by, query = state.query, tab = state.tab, tabLabel = TabLabel })
    self.sections = sections
    local collapsed = Opt().collapsed or {}
    local width = child:GetWidth()
    local cols = math.max(1, math.floor((width + GAP) / (SIZE + GAP)))
    local y = 0
    for _, sec in ipairs(sections) do
      local h = pool:Get("vaultHead", HeadButton)
      h:SetPoint("TOPLEFT", 0, y); h:SetPoint("TOPRIGHT", 0, y)
      h.key = sec.key
      local closed = collapsed[sec.key]
      h.text:SetText((closed and "+ " or "- ") .. sec.title)
      local sub = sec.kinds .. (sec.kinds == 1 and " kind" or " kinds") .. "  ·  " .. sec.total
      local home = sec.cat and plan.home[sec.cat]
      if home and not state.tab then sub = "kept in " .. TabLabel(home) .. "  ·  " .. sub end
      local holds = sec.tab and plan.tabs[sec.tab] and plan.tabs[sec.tab].holdsText
      if holds then sub = holds .. "  ·  " .. sub end
      h.sub:SetText(sub)
      y = y - 26
      if not closed then
        for i, e in ipairs(sec.items) do
          local b = pool:Get("vaultItem", ItemButton)
          local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
          b:SetPoint("TOPLEFT", col * (SIZE + GAP), y - row * (SIZE + GAP))
          b.entry = e
          b.icon:SetTexture(ns.ItemIcon(e.id))
          b.count:SetText(CountText(e.n))
          local q = QUALITY[e.quality]
          b.glow:SetShown(e.quality >= 2 and q ~= nil)
          if q then b.glow:SetVertexColor(q[1], q[2], q[3], 0.9) end
          local mis = {}
          for _, m in ipairs(plan.misplaced[e.id] or {}) do
            if not sec.tab or m.tab == sec.tab then mis[#mis + 1] = m end
          end
          b.misplaced = mis
          b.mark:SetShown(#mis > 0)
          -- nothing you can take today: dim it
          local takeable = not info.live or TakeStack(e, info.tabs) ~= nil
          b.icon:SetDesaturated(info.live and not takeable)
          b.icon:SetAlpha((info.live and not takeable) and 0.55 or 1)
          self.shown[#self.shown + 1] = e
        end
        y = y - math.ceil(#sec.items / cols) * (SIZE + GAP) - 6
      end
    end
    if #sections == 0 then
      local fs = pool:Font(12, C.muted, "empty")
      fs:SetPoint("TOPLEFT", 4, -8)
      fs:SetWidth(width - 8)
      fs:SetWordWrap(true)
      if state.query ~= "" or state.tab then fs:SetText("Nothing in the guild bank matches.")
      elseif info.live then fs:SetText("The guild bank is still loading, or it's empty.")
      else fs:SetText("EPU hasn't seen the guild bank yet. Open it once at a guild vault and it shows up here, by category.") end
      self.emptyText = fs:GetText()
      y = y - 40
    else
      self.emptyText = nil
    end
    child:SetHeight(math.max(scroll:GetHeight(), -y + 6))
    -- footer
    local money
    if info.live then
      money = GetGuildBankMoney and GetGuildBankMoney() or 0
      local loading = info.pending > 0 and ("  ·  " .. info.pending .. (info.pending == 1 and " tab is" or " tabs are") .. " still loading") or ""
      self.status:SetText("Live from the guild bank" .. loading)
      self.hint:SetText("Right-click takes a stack. Drop an item here to put it in the tab for its kind.")
    else
      local snap = g and g.bank and g.bank[ns.GB_KEY]
      money = snap and snap.money or nil
      self.status:SetText(info.seen and ("As last seen " .. Ago(info.seen)) or "")
      self.hint:SetText("Open the guild bank to take or add items from here.")
    end
    self.money:SetText(money and ns.MoneyText(money) or "")
  end

  win:SetScript("OnShow", function(self)
    self:Refresh()
    if ns.ReanchorDonate then ns.ReanchorDonate() end
  end)
  win:SetScript("OnHide", function(self)
    local closeBank = self.instead and not self.closing and ns.GuildBankIsOpen and ns.GuildBankIsOpen()
    RestoreOthers()
    self.instead, self.showOthers, self.auto = nil, nil, nil
    if ns.ReanchorDonate then ns.ReanchorDonate() end
    -- this window stood in for the bank window, so closing it closes the bank
    if closeBank then CloseBank() end
  end)
end

function ns.RefreshGuildVault()
  if win and win:IsShown() then ns.Debounce("guildVaultWindow", 0.2, function() if win:IsShown() then win:Refresh() end end) end
end

-- Open the window (from the Bank page, /epu vault, or by itself at the bank).
function ns.OpenGuildVault()
  if not ns.G() then return ns.Print("You are not in a guild.") end
  if not win then Build() end
  local atBank = ns.GuildBankIsOpen and ns.GuildBankIsOpen()
  if not win:IsShown() then Place(atBank and ns.GuildVaultMode() or "off") end
  win:Show()
  win:Raise()
  win:Refresh()
  return win
end

local function ShowAtBank()
  if not (ns.GuildBankIsOpen and ns.GuildBankIsOpen()) then return end
  local mode = ns.GuildVaultMode()
  if mode == "off" or not ns.G() then return end
  if not win then Build() end
  local was = win:IsShown()
  win.instead = mode == "instead"
  win.auto = win.auto or not was
  win.showOthers = nil
  if not was then Place(mode) end
  win:Show()
  if win.instead then
    Rehide()
    -- Baganator shows its guild bank window a moment after the bank opens
    C_Timer.After(0.5, Rehide)
    C_Timer.After(1.5, Rehide)
  end
  win:Refresh()
end

function ns.SetGuildVaultMode(m)
  Opt().mode = (m == "beside" or m == "instead") and m or nil
  if win and win:IsShown() and ns.GuildBankIsOpen and ns.GuildBankIsOpen() then
    win.instead = ns.GuildVaultMode() == "instead"
    win.showOthers = nil
    if win.instead then Rehide() else RestoreOthers() end
    win:Refresh()
  elseif ns.GuildVaultMode() ~= "off" then
    ShowAtBank()
  end
  if win and win:IsShown() then win:Refresh() end
  ns.Print("The guild bank category window now opens "
    .. ({ off = "only when you open it (Guild bank view on the Bank page, or /epu vault).",
          beside = "beside the guild bank window at a guild vault.",
          instead = "instead of the guild bank window at a guild vault." })[ns.GuildVaultMode()])
end

-- /epu vault [beside|instead|off]
function ns.GuildVaultCommand(args)
  local a = tostring(args or ""):lower():match("^%s*(%S*)")
  if a == "beside" or a == "instead" or a == "off" then return ns.SetGuildVaultMode(a) end
  return ns.OpenGuildVault()
end

local wasOpen = false
local function BankChanged()
  local open = ns.GuildBankIsOpen and ns.GuildBankIsOpen() or false
  if open == wasOpen then return end
  wasOpen = open
  if open then
    C_Timer.After(0.1, ShowAtBank)
  else
    RestoreOthers()
    if win and win:IsShown() then
      if win.auto then
        win.closing = true
        win:Hide()
        win.closing = nil
      else
        win.instead, win.showOthers = nil, nil
        ns.RefreshGuildVault()
      end
    end
  end
end

for _, ev in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                      "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
  ns.On(ev, BankChanged)
end
for _, ev in ipairs({ "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS", "GUILDBANK_UPDATE_MONEY", "GUILDBANK_ITEM_LOCK_CHANGED",
                      "GET_ITEM_INFO_RECEIVED" }) do
  ns.On(ev, function() ns.RefreshGuildVault() end)
end

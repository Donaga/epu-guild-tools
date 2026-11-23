-- EPU Guild Tools: needed mats the guild bank already holds.
-- Matches everyone's needed mats lists (NeededMats.lua) against the bank
-- contents the addon already keeps: the in-game guild bank (with its tabs,
-- when this client has scanned it) and the bank alts. Each match gets one
-- button for whoever needs it:
--   Pull      take it straight out of the open guild bank (your own needs,
--             where your rank may withdraw from that tab), or, for officers
--             and bank managers, pull it for the member's request
--   Request   file a bank request the bank managers see, when it can't be
--             pulled right now (bank closed, no withdrawals, only on a bank alt)
--   Requested an open request for it already exists
local ADDON, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local MAX_QTY = 1000   -- the largest bank request

local function SamePlayer(a, b)
  return a == b or (a ~= nil and b ~= nil and ns.MainOf(a) == ns.MainOf(b))
end

local function StackSize(id)
  local n = GetItemInfo and select(8, GetItemInfo(id))
  n = tonumber(n)
  return (n and n > 0) and n or 20
end

-- Where the bank holds an item: { {holder, tab, tabName, n}, ... }, total.
-- The guild bank is broken down by tab when this client's own tab scan agrees
-- with the guild's count; otherwise it shows as one "Guild Bank" line.
function ns.BankHoldings(id)
  local g = ns.G()
  local out, total = {}, 0
  if not g or not id then return out, 0 end
  for holder, s in pairs(g.bank or {}) do
    local n = (not s.retired and type(s.items) == "table" and tonumber(s.items[id])) or 0
    if n > 0 then
      total = total + n
      local tabs, counted = {}, 0
      if holder == ns.GB_KEY then
        for tab, t in pairs(g.gbTabs or {}) do
          local c = type(t) == "table" and type(t.items) == "table" and tonumber(t.items[id]) or 0
          if c > 0 then tabs[#tabs + 1] = { holder = holder, tab = tab, tabName = t.name, n = c }; counted = counted + c end
        end
      end
      if #tabs > 0 and counted == n then
        table.sort(tabs, function(a, b) return a.tab < b.tab end)
        for _, t in ipairs(tabs) do out[#out + 1] = t end
      else
        out[#out + 1] = { holder = holder, n = n }
      end
    end
  end
  table.sort(out, function(a, b)
    local ag, bg = a.holder == ns.GB_KEY, b.holder == ns.GB_KEY
    if ag ~= bg then return ag end
    if a.holder ~= b.holder then return a.holder < b.holder end
    return (a.tab or 0) < (b.tab or 0)
  end)
  return out, total
end

-- "Guild Bank (Mats) 30, Donlock 10"
function ns.BankHoldingsText(where)
  local parts = {}
  for _, w in ipairs(where or {}) do
    local name = w.holder
    if w.tab then name = name .. " (" .. ((w.tabName and w.tabName ~= "") and w.tabName or ("tab " .. w.tab)) .. ")" end
    parts[#parts + 1] = name .. " " .. w.n
  end
  return table.concat(parts, ", ")
end

-- An open bank request for this item, mailed to this player (any of their characters).
local function OpenRequest(who, id)
  local g = ns.G()
  local best, bestR
  for rid, r in pairs((g and g.requests) or {}) do
    if not r.crafter and r.item == id and ns.IsActiveRequest(r) and SamePlayer(r.to or r.who, who) and ns.Remaining(r) > 0 then
      -- an approved one first (it can be pulled), then the oldest
      local better = not bestR
      if bestR then
        local a, b = r.status == "approved", bestR.status == "approved"
        if a ~= b then better = a else better = (r.t or 0) < (bestR.t or 0) end
      end
      if better then best, bestR = rid, r end
    end
  end
  return best, bestR
end

-- How much one click asks for: what's still needed (one stack when no
-- amount was given), never more than the bank holds.
local function PullQty(e)
  local want = (e.n and e.n > 0) and e.n or StackSize(e.id)
  return math.max(0, math.min(want, e.held or 0, MAX_QTY))
end

-- What the button does for this entry: "pull", "request", "requested" or nil (no button).
function ns.NeededMatAction(e)
  local bank = ns.IsBankTrusted(ns.me)
  if not e.me and not bank then return nil end
  local qty = PullQty(e)
  if qty <= 0 then return nil end
  local open = ns.GuildBankIsOpen and ns.GuildBankIsOpen()
  local canPull = open and ns.PlanGuildBankPull and #(ns.PlanGuildBankPull(e.id, qty)) > 0
  if e.request then
    -- officers and bank managers can pull for it (approving it if it waits)
    if bank and canPull then return "pull" end
    return "requested"
  end
  if canPull then return "pull" end
  return "request"
end

-- Every needed mat (yours first, then the guild's) that the bank holds some of:
--   { id, who, n, p, online, me, held, where, request, requestStatus, action }
function ns.NeededMatsInBank()
  local list = {}
  if not ns.G() then return list end
  local function Add(e)
    local where, held = ns.BankHoldings(e.id)
    if held <= 0 then return end
    e.where, e.held = where, held
    local rid, r = OpenRequest(e.who, e.id)
    e.request, e.requestStatus = rid, r and r.status
    e.action = ns.NeededMatAction(e)
    list[#list + 1] = e
  end
  for _, m in ipairs(ns.MyNeededMats and ns.MyNeededMats() or {}) do
    Add({ id = m.id, who = ns.me, n = m.need, p = m.p, online = true, me = true })
  end
  for _, m in ipairs(ns.GuildNeededMats and ns.GuildNeededMats() or {}) do
    Add({ id = m.id, who = m.who, n = m.n, p = m.p, online = m.online })
  end
  return list
end

local function Find(who, id)
  for _, e in ipairs(ns.NeededMatsInBank()) do
    if e.who == who and e.id == id then return e end
  end
end

-- The one-click button.
function ns.PullNeededMat(who, id)
  id = tonumber(id)
  local e = id and Find(who, id)
  if not e then return ns.Print("The bank doesn't hold that needed material, or it's no longer needed.") end
  local action = e.action
  if not action then return ns.Print("Only officers and bank managers can send a guildmate's needed mats.") end
  local qty = PullQty(e)
  local link = ns.ItemLink(id)
  local Refresh = function() if ns.RefreshNeededMatsBank then ns.RefreshNeededMatsBank() end end

  if action == "requested" and not e.me and ns.IsBankTrusted(ns.me) then
    return ns.Print(who .. " already has a request for " .. link .. ". Open the guild bank and press Pull, or Mail it from the request.")
  elseif action == "requested" then
    return ns.Print("You already asked the bank for " .. link .. ". A bank manager will send it.")
  end

  if e.me then
    if action == "pull" then
      return ns.PullFromGuildBank(id, qty, function(moved)
        if moved > 0 then ns.Print("Took " .. link .. " x" .. moved .. " from the guild bank for your needed mats.")
        else ns.Print("Nothing moved from the guild bank. Check your withdrawal limit for today, then try again.") end
        Refresh()
      end)
    end
    local rid = ns.NewRequest(id, qty, "Needed mats")
    if rid then
      ns.Print("Or take it yourself: open the guild bank and press Pull, if your rank can withdraw from that tab.")
      Refresh()
    end
    return rid
  end

  -- an officer or bank manager, for a guildmate: through a bank request, so
  -- the usual Pull for request and Mail it deliver it and credit it
  local rid = e.request
  if not rid then
    rid = ns.NewRequest(id, qty, "Needed mats", nil, who)
    if not rid then return end
  elseif e.requestStatus ~= "approved" then
    ns.SetRequestStatus(rid, "approved")
  end
  Refresh()
  if ns.GuildBankIsOpen and ns.GuildBankIsOpen() and #(ns.PlanGuildBankPull(id, qty)) > 0 then
    return ns.PullForRequest(rid)
  end
  ns.Print("It's on " .. who .. "'s request. Open the guild bank and press Pull, or send it from a bank alt with Mail it.")
  return rid
end

---------------------------------------------------------------------------
-- Window: /epu mats bank, or "In the guild bank" on the Needed mats page
---------------------------------------------------------------------------
local LABEL = { pull = "Pull", request = "Request", requested = "Requested" }
local win

local function First(name)
  return (name and name:match("^(%S+)")) or name or "?"
end

local function Build_Window()
  local K, C = ns.UIKit, ns.InterfaceColors
  win = ns.InterfaceWindow("EPUGuildNeededMatsBank", UIParent, "Needed mats in the bank", 520, 460)

  local hint = K.Font(win, 11, C.muted)
  hint:SetPoint("TOPLEFT", 14, -46)
  hint:SetWidth(490)
  hint:SetWordWrap(true)
  win.hint = hint

  local scroll = CreateFrame("ScrollFrame", nil, win)
  scroll:SetPoint("TOPLEFT", 14, -84)
  scroll:SetPoint("BOTTOMRIGHT", -14, 12)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(492); child:SetHeight(360)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
  end)
  win.child = child
  win.pool = ns.NewWidgetPool(child)

  function win:Refresh()
    local pool = self.pool
    pool:ReleaseAll()
    self.texts, self.buttons = {}, {}
    local bank = ns.IsBankTrusted(ns.me)
    local open = ns.GuildBankIsOpen and ns.GuildBankIsOpen()
    self.hint:SetText(open
      and "The guild bank is open: Pull takes what's needed straight into your bags, within your rank's withdrawal limits."
      or ("Open the guild bank to Pull. Until then, Request asks the bank managers to send it." .. (bank and " Officers and bank managers can do this for anyone." or "")))
    local y = -2
    local list = ns.NeededMatsInBank()
    if #list == 0 then
      local fs = pool:Font(12, C.muted)
      fs:SetPoint("TOPLEFT", 4, y - 4)
      fs:SetWidth(484)
      fs:SetWordWrap(true)
      fs:SetText("The bank doesn't hold any material on a needed mats list right now. Open the guild bank so EPU can see its tabs.")
      self.texts[#self.texts + 1] = fs:GetText()
      y = y - 40
    end
    for i = 1, math.min(80, #list) do
      local e = list[i]
      local who = e.me and "you" or (e.online and ("|cff4ade80" .. First(e.who) .. "|r") or First(e.who))
      local text = ns.ItemLink(e.id) .. (e.n > 0 and ("  x" .. e.n) or "") .. "  for " .. who
        .. (e.p and ("  |cffa3afc2" .. e.p .. "|r") or "")
      local sub = "In the bank: " .. ns.BankHoldingsText(e.where)
        .. (e.request and ("  |cfff2c14e" .. (e.requestStatus == "approved" and "approved request" or "request waiting") .. "|r") or "")
      local fs = pool:Font(12, C.text, "row")
      fs:SetPoint("TOPLEFT", 4, y - 2)
      fs:SetWidth(390)
      fs:SetText(text)
      local s = pool:Font(11, C.muted, "sub")
      s:SetPoint("TOPLEFT", 4, y - 18)
      s:SetWidth(390)
      s:SetText(sub)
      self.texts[#self.texts + 1] = text
      self.texts[#self.texts + 1] = sub
      if e.action then
        local b = pool:Button(LABEL[e.action], 84, 20)
        b:SetPoint("TOPRIGHT", 0, y - 4)
        b:SetScript("OnClick", function() ns.PullNeededMat(e.who, e.id) end)
        b.action, b.who, b.item = e.action, e.who, e.id
        self.buttons[#self.buttons + 1] = b
      end
      y = y - 40
    end
    if #list > 80 then
      local fs = pool:Font(11, C.muted)
      fs:SetPoint("TOPLEFT", 4, y - 2)
      fs:SetText("+" .. (#list - 80) .. " more")
      y = y - 22
    end
    child:SetHeight(math.max(360, -y + 10))
  end
  win:SetScript("OnShow", function(self) self:Refresh() end)
end

function ns.RefreshNeededMatsBank()
  if win and win:IsShown() then ns.Debounce("neededMatsBankWindow", 0.3, function() win:Refresh() end) end
end

function ns.ShowNeededMatsBank()
  if not ns.G() then return ns.Print("You are not in a guild.") end
  if not win then Build_Window() end
  win:Show()
  win:Refresh()
  return win
end

for _, ev in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
  ns.On(ev, function() ns.RefreshNeededMatsBank() end)
end

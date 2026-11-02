-- EPU Guild Tools: main window and minimap button
local ADDON, ns = ...

local W, H, ROW_H, LIST_W = 600, 470, 20, 552
local COLS = { { 26, 214 }, { 246, 80 }, { 330, 118 }, { 452, 46 } }
local TABS = { "Needs", "Shopping", "Bank", "Requests", "Donations", "Crafters" }

local UI = CreateFrame("Frame", "EPUGuildFrame", UIParent, "BasicFrameTemplateWithInset")
ns.UI = UI
UI:SetSize(W, H)
UI:SetPoint("CENTER")
UI:SetFrameStrata("HIGH")
UI:SetMovable(true)
UI:SetClampedToScreen(true)
UI:EnableMouse(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", UI.StartMoving)
UI:SetScript("OnDragStop", UI.StopMovingOrSizing)
UI:Hide()
tinsert(UISpecialFrames, "EPUGuildFrame")

UI.title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
UI.title:SetPoint("TOP", 0, -6)
UI.title:SetText("E Pluribus Unum - Guild Tools")

function UI:Toggle()
  if self:IsShown() then self:Hide() else self:Show() end
end

---------------------------------------------------------------------------
-- Tabs and header
---------------------------------------------------------------------------
UI.tabButtons = {}
for i, name in ipairs(TABS) do
  local b = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
  b:SetSize(80, 22)
  b:SetPoint("TOPLEFT", 12 + (i - 1) * 84, -30)
  b:SetText(name)
  b:SetScript("OnClick", function() UI:SetTab(name) end)
  UI.tabButtons[name] = b
end

local syncBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
syncBtn:SetSize(64, 22)
syncBtn:SetPoint("TOPRIGHT", -12, -30)
syncBtn:SetText("Sync")
syncBtn:SetScript("OnClick", function() ns.FullSync() end)

UI.headers = {}
for c, def in ipairs(COLS) do
  local fs = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 12 + def[1], -62)
  fs:SetWidth(def[2])
  fs:SetJustifyH("LEFT")
  UI.headers[c] = fs
end

---------------------------------------------------------------------------
-- Scrolling list
---------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", "EPUGuildScroll", UI, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -78)
scroll:SetPoint("BOTTOMRIGHT", -34, 68)
local child = CreateFrame("Frame", nil, scroll)
child:SetSize(LIST_W, 1)
scroll:SetScrollChild(child)

UI.empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
UI.empty:SetPoint("TOP", 0, -30)
UI.empty:SetWidth(LIST_W - 40)

local function RowEnter(self)
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if d.item then
    GameTooltip:SetHyperlink("item:" .. d.item)
  else
    GameTooltip:SetText(d.title or d.cols[1] or "")
  end
  if d.tip then
    for _, line in ipairs(d.tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
  end
  GameTooltip:Show()
end

local function RowClick(self)
  local d = self.data
  if d and d.item and IsModifiedClick("CHATLINK") then
    local _, link = GetItemInfo(d.item)
    if link then ChatEdit_InsertLink(link) end
  end
end

UI.rows = {}
local function GetRow(i)
  local r = UI.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, child)
  r:SetSize(LIST_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
  r.bar = r:CreateTexture(nil, "BORDER")
  r.bar:SetPoint("TOPLEFT")
  r.bar:SetPoint("BOTTOMLEFT")
  r.bar:SetColorTexture(0.2, 0.75, 0.3, 0.22)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 4, 0)
  r.cols = {}
  for c, def in ipairs(COLS) do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", def[1], 0)
    fs:SetWidth(def[2])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    r.cols[c] = fs
  end
  r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.btn:SetSize(52, 18)
  r.btn:SetPoint("RIGHT", -2, 0)
  r.btn2 = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.btn2:SetSize(52, 18)
  r.btn2:SetPoint("RIGHT", r.btn, "LEFT", -2, 0)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r:SetScript("OnEnter", RowEnter)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:SetScript("OnClick", RowClick)
  UI.rows[i] = r
  return r
end

local function ShowRows(data)
  for i, d in ipairs(data) do
    local r = GetRow(i)
    r.data = d
    if d.icon then r.icon:SetTexture(d.icon); r.icon:Show() else r.icon:Hide() end
    for c = 1, #COLS do r.cols[c]:SetText(d.cols[c] ~= nil and tostring(d.cols[c]) or "") end
    if d.frac and d.frac > 0 then
      local c = d.barColor or { 0.2, 0.75, 0.3 }
      r.bar:SetColorTexture(c[1], c[2], c[3], 0.22)
      r.bar:SetWidth(math.max(1, LIST_W * d.frac))
      r.bar:Show()
    else
      r.bar:Hide()
    end
    if d.btnText then
      r.btn:SetText(d.btnText)
      r.btn:SetScript("OnClick", d.btnFn)
      r.btn:Show()
    else
      r.btn:Hide()
    end
    if d.btn2Text then
      r.btn2:SetText(d.btn2Text)
      r.btn2:SetScript("OnClick", d.btn2Fn)
      r.btn2:Show()
    else
      r.btn2:Hide()
    end
    r:Show()
  end
  for i = #data + 1, #UI.rows do UI.rows[i]:Hide(); UI.rows[i].data = nil end
  child:SetHeight(math.max(1, #data * ROW_H))
end

---------------------------------------------------------------------------
-- Bottom inputs
---------------------------------------------------------------------------
UI.status = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
UI.status:SetPoint("BOTTOMLEFT", 16, 46)
UI.status:SetWidth(W - 32)
UI.status:SetJustifyH("LEFT")
UI.status:SetWordWrap(true)

local function MakeBox(width)
  local e = CreateFrame("EditBox", nil, UI, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if UI.action:IsShown() then UI.action:Click() end end)
  e.ph = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.ph:SetPoint("LEFT", 2, 0)
  e:SetScript("OnTextChanged", function(self)
    self.ph:SetShown(self:GetText() == "")
    if self.onChange then self.onChange() end
  end)
  return e
end

UI.itemBox = MakeBox(220)
UI.itemBox:SetPoint("BOTTOMLEFT", 22, 16)
UI.qtyBox = MakeBox(50)
UI.qtyBox:SetPoint("LEFT", UI.itemBox, "RIGHT", 10, 0)
UI.qtyBox:SetNumeric(true)
UI.qtyBox.ph:SetText("Qty")
UI.noteBox = MakeBox(170)
UI.noteBox:SetPoint("LEFT", UI.qtyBox, "RIGHT", 10, 0)
UI.noteBox:SetMaxLetters(80)
UI.noteBox.ph:SetText("Note (optional)")

-- Needs tab: restock minimum vs one-time goal
UI.kind = "restock"
UI.kindBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
UI.kindBtn:SetSize(90, 22)
UI.kindBtn:SetPoint("LEFT", UI.qtyBox, "RIGHT", 10, 0)
UI.kindBtn:SetText("Restock")
UI.kindBtn:SetScript("OnClick", function(self)
  UI.kind = (UI.kind == "restock") and "goal" or "restock"
  self:SetText(UI.kind == "goal" and "One-time goal" or "Restock")
end)
UI.kindBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText("Restock or goal?")
  GameTooltip:AddLine("Restock: a standing minimum the bank should always hold, e.g. 20 healing potions.", 1, 1, 1, true)
  GameTooltip:AddLine("One-time goal: removed automatically once the bank reaches it, e.g. 100 Runecloth for a raid push.", 1, 1, 1, true)
  GameTooltip:Show()
end)
UI.kindBtn:SetScript("OnLeave", GameTooltip_Hide)

UI.action = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
UI.action:SetSize(92, 22)
UI.action:SetPoint("BOTTOMRIGHT", -14, 14)

-- Drag an item onto the item box, or shift-click an item while it has focus.
UI.itemBox:SetScript("OnReceiveDrag", function(self)
  local kind, id, link = GetCursorInfo()
  if kind == "item" then
    self:SetText(link or ("item:" .. id))
    ClearCursor()
  end
end)
hooksecurefunc("ChatEdit_InsertLink", function(link)
  if UI:IsShown() and UI.itemBox:IsShown() and UI.itemBox:HasFocus() and link and link:find("|Hitem:") then
    UI.itemBox:SetText(link)
  end
end)

local function ClearInputs()
  UI.itemBox:SetText("")
  UI.qtyBox:SetText("")
  UI.noteBox:SetText("")
end

---------------------------------------------------------------------------
-- Tab contents
---------------------------------------------------------------------------
local function Ago(t)
  if not t then return "never" end
  local s = ns.Now() - t
  if s < 120 then return "just now" end
  if s < 7200 then return math.floor(s / 60) .. " min ago" end
  if s < 172800 then return math.floor(s / 3600) .. " hr ago" end
  return math.floor(s / 86400) .. " days ago"
end

local function Money(c)
  if GetCoinTextureString then return GetCoinTextureString(c or 0) end
  return tostring(math.floor((c or 0) / 10000)) .. "g"
end

local function SearchText()
  local s = UI.itemBox:GetText() or ""
  local id = ns.ItemID(s:find("|Hitem:") and s or nil)
  if id then s = ns.ItemName(id, true) end
  return s:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local Tabs = {}

Tabs.Needs = {
  headers = { "Item", "Bank / target", "Type", "You carry" },
  inputs = { item = "Shift-click or drag an item", qty = true, kind = true },
  action = "Set Need",
  onAction = function()
    local id = ns.ItemID(UI.itemBox:GetText())
    local qty = tonumber(UI.qtyBox:GetText())
    if not id or not qty then return ns.Print("Pick an item and enter a target quantity (0 removes it).") end
    ns.SetNeed(id, qty, UI.kind)
    ClearInputs()
  end,
  rows = function(g)
    local rows = {}
    local officer = ns.IsTrusted(ns.me)
    for _, n in ipairs(ns.OpenNeeds()) do
      local carry = GetItemCount(n.id) or 0
      local id = n.id
      local kind = (n.kind == "goal") and "Goal" or "Restock"
      if n.critical then kind = "|cffff4040" .. kind .. " (low)|r" end
      rows[#rows + 1] = {
        item = id, icon = ns.ItemIcon(id), frac = n.frac,
        barColor = n.critical and { 0.9, 0.2, 0.2 } or nil,
        cols = { ns.ItemName(id), n.have .. " / " .. n.target, kind, carry > 0 and ("|cff00ff00" .. carry .. "|r") or "0" },
        tip = { " ", "Still needed: " .. n.rem,
          (n.kind == "goal") and "One-time goal: removed once the bank reaches it." or "Restock: a standing minimum.",
          "Mail donations to: " .. ns.BankAltNames() },
        btnText = officer and "Clear" or nil,
        btnFn = function() ns.SetNeed(id, 0) end,
      }
    end
    return rows
  end,
  status = function(g)
    local s = "Mail donations to " .. ns.BankAltNames() .. ". Anything you carry that's on the list shows in green; red means under half stocked."
    if ns.IsTrusted(ns.me) then s = s .. "\nOfficers: pick Restock (always keep this many) or One-time goal (closes when reached). 0 removes." end
    return s
  end,
  empty = "No needs set yet. Officers can add targets below or with /epu need <item> <qty> [goal].",
}

Tabs.Shopping = {
  headers = { "Item", "Need", "Requests", "To buy" },
  action = "To Auctionator",
  onAction = function() ns.ExportAuctionator() end,
  rows = function(g)
    local rows = {}
    for _, r in ipairs(ns.ShoppingList()) do
      rows[#rows + 1] = {
        item = r.id, icon = ns.ItemIcon(r.id),
        cols = { ns.ItemName(r.id), r.need, r.req, "|cffffd100" .. r.buy .. "|r" },
        tip = { " ", "In bank: " .. r.have, "Needs target: " .. r.need, "Approved requests: " .. r.req, "To buy: " .. r.buy },
      }
    end
    return rows
  end,
  status = function(g)
    if ns.HasAuctionator() then
      return "Everything below its target, plus approved requests the bank can't cover. Click To Auctionator (or /epu shop), then open the \"" .. ns.SHOPPING_LIST_NAME .. "\" list on the Auctionator Shopping tab."
    end
    return "Everything below its target, plus approved requests the bank can't cover. Install Auctionator to export this as a shopping list."
  end,
  empty = "Nothing to buy. Every need is stocked and every approved request is covered.",
}

Tabs.Bank = {
  headers = { "Item", "Count", "Held by", "" },
  inputs = { item = "Search..." },
  rows = function(g)
    local totals, holders = {}, {}
    for alt, s in pairs(g.bank) do
      if not s.retired then
        for id, c in pairs(s.items or {}) do
          totals[id] = (totals[id] or 0) + c
          holders[id] = holders[id] and (holders[id] .. ", " .. alt) or alt
        end
      end
    end
    local q = SearchText()
    local rows = {}
    for id, c in pairs(totals) do
      local plain = ns.ItemName(id, true)
      if q == "" or plain:lower():find(q, 1, true) then
        rows[#rows + 1] = { item = id, icon = ns.ItemIcon(id), cols = { ns.ItemName(id), c, holders[id] }, sort = plain }
      end
    end
    table.sort(rows, function(a, b) return a.sort < b.sort end)
    return rows
  end,
  status = function(g)
    local parts = {}
    local gb = g.bank[ns.GB_KEY]
    if gb and not gb.retired then
      parts[#parts + 1] = "Guild bank: " .. Money(gb.money) .. " (read " .. Ago(gb.bankTime) .. ")"
    end
    for _, alt in ipairs(ns.BankAlts()) do
      local s = g.bank[alt]
      parts[#parts + 1] = alt .. ": " .. Money(s.money) .. " (updated " .. Ago(s.v) .. ", bank seen " .. Ago(s.bankTime) .. ")"
    end
    if #parts == 0 then return "No bank yet. Log onto the bank character and type /epu bankalt on, or open the guild bank." end
    return table.concat(parts, "\n")
  end,
  empty = "Nothing recorded yet. The bank alt needs the addon, and should open its bank once.",
}

local STATUS_TEXT = {
  pending = "|cffffd100pending|r", open = "|cffffd100pending|r", approved = "|cff40ff40approved|r",
  filled = "|cff888888filled|r", rejected = "|cffff4040rejected|r",
}
local STATUS_ORDER = { pending = 1, open = 1, approved = 2, filled = 3, rejected = 4 }

Tabs.Requests = {
  headers = { "Item", "Qty (bank)", "Requested by", "Status" },
  inputs = { item = "Item you need", qty = true, note = true },
  action = "Request",
  onAction = function()
    local id = ns.ItemID(UI.itemBox:GetText())
    if not id then return ns.Print("Shift-click or drag the item you need into the box first.") end
    ns.NewRequest(id, tonumber(UI.qtyBox:GetText()) or 1, UI.noteBox:GetText())
    ClearInputs()
  end,
  rows = function(g)
    local officer = ns.IsTrusted(ns.me)
    local list = {}
    for rid, r in pairs(g.requests) do
      if r.status ~= "cancelled" then list[#list + 1] = { rid = rid, r = r } end
    end
    table.sort(list, function(a, b)
      local oa, ob = STATUS_ORDER[a.r.status] or 9, STATUS_ORDER[b.r.status] or 9
      if oa ~= ob then return oa < ob end
      return a.r.t > b.r.t
    end)
    local rows = {}
    for _, e in ipairs(list) do
      local r, rid = e.r, e.rid
      local st = r.status
      local pending = (st == "pending" or st == "open")
      local who = r.who
      if ns.roster[who] and ns.roster[who].online then who = "|cff00ff00" .. who .. "|r" end
      local row = {
        item = r.item, icon = ns.ItemIcon(r.item),
        cols = { ns.ItemName(r.item), r.qty .. " (" .. ns.BankCount(r.item) .. ")", who, STATUS_TEXT[st] or st },
        tip = { " ", "Requested " .. Ago(r.t) .. " by " .. r.who .. ((r.via == "discord") and " (via Discord)" or ""),
          (r.note and r.note ~= "") and ("Note: " .. r.note) or nil,
          (r.by and not pending) and (st .. " by " .. r.by .. " " .. Ago(r.u)) or nil,
          (st == "rejected" and r.reason and r.reason ~= "") and ("Reason: " .. r.reason) or nil },
      }
      if officer and pending then
        row.btnText, row.btnFn = "Approve", function() ns.SetRequestStatus(rid, "approved") end
        row.btn2Text, row.btn2Fn = "Reject", function()
          ns.SetRequestStatus(rid, "rejected", UI.noteBox:GetText())
          UI.noteBox:SetText("")
        end
        row.cols[4] = ""
      elseif officer and st == "approved" then
        row.btnText, row.btnFn = "Fill", function() ns.SetRequestStatus(rid, "filled") end
      elseif r.who == ns.me and ns.IsActiveRequest(r) then
        row.btnText, row.btnFn = "Cancel", function() ns.SetRequestStatus(rid, "cancelled") end
      end
      rows[#rows + 1] = row
    end
    return rows
  end,
  status = function(g)
    if ns.IsTrusted(ns.me) then
      return "Approve or Reject pending requests (type a reason in the Note box before Reject). Mailing or trading an approved item to the requester marks it filled automatically."
    end
    return "Ask the guild bank for something. An officer approves it and mails it to you."
  end,
  empty = "No requests. Put an item in the box below to ask the guild bank for it.",
}

Tabs.Donations = {
  headers = { "Item / gold", "Qty", "From", "When" },
  rows = function(g)
    local list = {}
    for _, d in pairs(g.donations) do list[#list + 1] = d end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    local rows = {}
    for _, d in ipairs(list) do
      if d.item then
        rows[#rows + 1] = { item = d.item, icon = ns.ItemIcon(d.item), cols = { ns.ItemName(d.item), d.n, d.who, Ago(d.t) },
          tip = { " ", "Received by " .. tostring(d.to) .. " on " .. date("%b %d %H:%M", d.t) } }
      else
        rows[#rows + 1] = { icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Gold donation",
          cols = { Money(d.money), "", d.who, Ago(d.t) }, tip = { "Received by " .. tostring(d.to) .. " on " .. date("%b %d %H:%M", d.t) } }
      end
    end
    return rows
  end,
  status = function(g)
    local cutoff, counts = ns.Now() - 30 * 86400, {}
    for _, d in pairs(g.donations) do
      if (d.t or 0) > cutoff then counts[d.who] = (counts[d.who] or 0) + 1 end
    end
    local top = {}
    for who, n in pairs(counts) do top[#top + 1] = { who = who, n = n } end
    table.sort(top, function(a, b) return a.n > b.n end)
    local names = {}
    for i = 1, math.min(5, #top) do names[#names + 1] = top[i].who .. " (" .. top[i].n .. ")" end
    if #names == 0 then return "Mail or trade to a bank alt is logged automatically." end
    return "Top donors, last 30 days: " .. table.concat(names, ", ") .. ". Thank you!"
  end,
  empty = "No donations logged yet. Mail or trades from guild members to a bank alt show up here.",
}

Tabs.Crafters = {
  headers = { "Member", "Profession", "Skill", "Level" },
  inputs = { item = "Search, or an item to look up" },
  action = "Who crafts?",
  onAction = function()
    local text = UI.itemBox:GetText()
    if text == "" then return ns.Print("Put an item (or recipe name) in the box first.") end
    ns.AskWhoCrafts(text)
  end,
  rows = function(g)
    local rows = {}
    local res = ns.whoResults
    if res and res.label then
      rows[#rows + 1] = { title = "Recipe lookup", cols = { "|cffffd100Can craft|r " .. res.label .. ":", "", "", "" } }
      if #res.list == 0 then
        rows[#rows + 1] = { cols = { "  |cff888888(waiting for answers...)|r", "", "", "" } }
      end
      for _, h in ipairs(res.list) do
        rows[#rows + 1] = { cols = { "  " .. h.who, h.prof, h.rank or "?", "" } }
      end
    end
    local q = SearchText()
    local list = {}
    for who, c in pairs(g.crafters) do
      for prof, skill in pairs(c.profs or {}) do
        if q == "" or prof:lower():find(q, 1, true) or who:lower():find(q, 1, true) then
          list[#list + 1] = { who = who, prof = prof, skill = skill, lvl = c.lvl, t = c.t }
        end
      end
    end
    table.sort(list, function(a, b)
      if a.prof ~= b.prof then return a.prof < b.prof end
      if a.skill ~= b.skill then return a.skill > b.skill end
      return a.who < b.who
    end)
    for _, e in ipairs(list) do
      local name = e.who
      if ns.roster[e.who] and ns.roster[e.who].online then name = "|cff00ff00" .. name .. "|r" end
      rows[#rows + 1] = { title = e.who, cols = { name, e.prof, e.skill, e.lvl }, tip = { "Updated " .. Ago(e.t) } }
    end
    return rows
  end,
  status = function(g)
    local n = 0
    for _ in pairs(g.crafters) do n = n + 1 end
    return n .. " members reporting. Online members show in green. To look up a recipe, put an item in the box and click Who crafts? (Recipes are learned when a crafter opens their profession window.)"
  end,
  empty = "No profession data yet. It fills in as members with the addon log in.",
}

function UI:SetTab(name)
  self.tab = name
  local t = Tabs[name]
  for n, b in pairs(self.tabButtons) do
    if n == name then b:LockHighlight() else b:UnlockHighlight() end
  end
  for c = 1, #COLS do self.headers[c]:SetText(t.headers[c] or "") end
  local inp = t.inputs or {}
  self.itemBox:SetShown(inp.item ~= nil)
  self.itemBox.ph:SetText(inp.item or "")
  self.itemBox.onChange = (name == "Bank" or name == "Crafters") and function() UI:Refresh() end or nil
  self.qtyBox:SetShown(inp.qty == true)
  self.noteBox:SetShown(inp.note == true)
  self.kindBtn:SetShown(inp.kind == true)
  self.action:SetShown(t.action ~= nil)
  self.action:SetText(t.action or "")
  self.action:SetScript("OnClick", t.onAction)
  ClearInputs()
  scroll:SetVerticalScroll(0)
  self:Refresh()
end

function UI:Refresh()
  if not self:IsShown() or not self.tab then return end
  local g = ns.G()
  if not g then
    ShowRows({})
    self.empty:SetText("Join a guild to use EPU Guild Tools.")
    self.empty:Show()
    self.status:SetText("")
    return
  end
  local t = Tabs[self.tab]
  local rows = t.rows(g)
  ShowRows(rows)
  self.empty:SetText(t.empty or "")
  self.empty:SetShown(#rows == 0)
  self.status:SetText(t.status(g))
end

UI:SetScript("OnShow", function(self)
  ns.RequestRoster()
  if not self.tab then self:SetTab("Needs") else self:Refresh() end
end)

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
mbIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
mbIcon:SetSize(20, 20)
mbIcon:SetPoint("TOPLEFT", 7, -5)
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

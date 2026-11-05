-- EPU Guild Tools: help outside the main window.
--   * item tooltips show what the guild bank needs / holds
--   * a gold marker on items in your bags that the bank needs
--   * a "Donate" panel at the mailbox: pick items and amounts, then Fill mail
--   * pop-up notices when your request changes (and new requests for officers)
--   * a welcome card the first time the window opens
local ADDON, ns = ...
-- Newer clients keep these under C_Item; the old global names only exist when
-- the game's "deprecated API" fallback is on, which varies from PC to PC.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local GOLD = { 0.95, 0.76, 0.31 }
local MUTED = { 0.55, 0.58, 0.62 }

local function Setting(key, default)
  if not ns.db then return default end
  local v = ns.db.settings[key]
  if v == nil then return default end
  return v
end

local function MyChars()
  local set = {}
  for _, c in ipairs(ns.MyChars()) do set[c] = true end
  if ns.me then set[ns.me] = true end
  return set
end

---------------------------------------------------------------------------
-- 1. Tooltips
---------------------------------------------------------------------------
local CraftLines
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9

local function NameList(list, max)
  local names = {}
  for i = 1, math.min(max, #list) do
    local c = list[i]
    local n = c.who:match("^(%S+)") or c.who
    if ns.IsDesignated(c.who, c.prof) then n = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t" .. n end
    if ns.roster[c.who] and ns.roster[c.who].online then n = "|cff4ade80" .. n .. "|r" end
    names[#names + 1] = n
  end
  if #list > max then names[#names + 1] = "+" .. (#list - max) .. " more" end
  return table.concat(names, ", ")
end

-- Who in the guild crafts this item; for recipes/patterns, whether anyone knows it.
CraftLines = function(tt, id)
  local crafters = ns.CraftersOf("item:" .. id)
  local added = false
  if #crafters > 0 then
    tt:AddLine("Guild crafters: " .. NameList(crafters, 3), 0.85, 0.86, 0.88)
    added = true
  end
  local name, _, _, _, _, _, subType, _, _, _, _, classID = GetItemInfo(id)
  if classID == RECIPE_CLASS and name then
    local made = name:match("^[^:]+:%s*(.+)$") or name    -- "Pattern: Woolen Bag" -> "Woolen Bag"
    local e = ns.RecipeByName(made)
    if e then
      tt:AddLine("Known in the guild by " .. NameList(ns.CraftersOf(e.key), 3), MUTED[1], MUTED[2], MUTED[3])
      added = true
    elseif #ns.RecipeIndex() > 0 then
      tt:AddLine("Nobody in the guild knows this recipe yet", GOLD[1], GOLD[2], GOLD[3])
      local g, who = ns.G(), {}
      for n, c in pairs((g and g.crafters) or {}) do
        local skill = c.profs and subType and c.profs[subType]
        if skill then who[#who + 1] = { n = n, s = skill } end
      end
      table.sort(who, function(a, b) return a.s > b.s end)
      local parts = {}
      for i = 1, math.min(3, #who) do parts[#parts + 1] = (who[i].n:match("^(%S+)") or who[i].n) .. " " .. who[i].s end
      if #parts > 0 then tt:AddLine(subType .. " in the guild: " .. table.concat(parts, ", "), MUTED[1], MUTED[2], MUTED[3]) end
      added = true
    end
  end
  return added
end
local function TooltipLines(tt, id)
  if not id or not Setting("tooltips", true) then return end
  local g = ns.G()
  if not g then return end
  local added = false
  local v = g.needs.list[id]
  local have = ns.BankCount(id)
  if v then
    local target, kind = ns.NeedEntry(v)
    local rem = math.max(0, target - have)
    if rem > 0 then
      tt:AddLine("Guild bank needs " .. rem .. " more (" .. have .. "/" .. target .. ")", GOLD[1], GOLD[2], GOLD[3])
    else
      tt:AddLine("Guild bank: stocked (" .. have .. "/" .. target .. ")", MUTED[1], MUTED[2], MUTED[3])
    end
    added = true
  elseif have > 0 then
    tt:AddLine("In guild bank: " .. have, MUTED[1], MUTED[2], MUTED[3])
    added = true
  end
  local mine = MyChars()
  for _, r in pairs(g.requests) do
    if r.item == id and mine[r.who] and ns.IsActiveRequest(r) then
      local st = (r.status == "open") and "pending" or r.status
      if r.crafter then
        st = (r.status == "approved") and "accepted" or st
        tt:AddLine("Your craft request to " .. r.crafter .. ": " .. st .. " (x" .. r.qty .. ")", GOLD[1], GOLD[2], GOLD[3])
      else
        tt:AddLine("Your guild bank request: " .. st .. " (x" .. r.qty .. ")", GOLD[1], GOLD[2], GOLD[3])
      end
      added = true
    end
  end
  if CraftLines(tt, id) then added = true end
  if added then tt:Show() end
end
ns.TooltipLines = TooltipLines

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id and tt.GetItem then id = ns.ItemID(select(2, tt:GetItem())) end
    pcall(TooltipLines, tt, id)
  end)
else
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
      tt:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        pcall(TooltipLines, self, ns.ItemID(link))
      end)
    end
  end
end

---------------------------------------------------------------------------
-- 2. Bag markers (Blizzard bags and Baganator)
---------------------------------------------------------------------------
local function Needed(id)
  if not id or not Setting("bagMarkers", true) then return false end
  local g = ns.G()
  local v = g and g.needs.list[id]
  if not v then return false end
  local target = ns.NeedEntry(v)
  return ns.BankCount(id) < target
end
ns.ItemIsNeeded = Needed

local function Marker(parent)
  local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
  t:SetSize(12, 12)
  t:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
  return t
end

-- Blizzard container frames
local function MarkButton(button, id)
  if not button then return end
  if Needed(id) then
    if not button.epuMarker then
      button.epuMarker = Marker(button)
      button.epuMarker:SetPoint("TOPLEFT", 2, -2)
    end
    button.epuMarker:Show()
  elseif button.epuMarker then
    button.epuMarker:Hide()
  end
end

local function ItemIDAt(bag, slot)
  if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
  if GetContainerItemID then return GetContainerItemID(bag, slot) end
end

local function UpdateContainerFrame(frame)
  if not frame or not frame.IsShown or not frame:IsShown() then return end
  if frame.EnumerateValidItems then
    for _, button in frame:EnumerateValidItems() do
      local bag = button.GetBagID and button:GetBagID()
      local slot = button.GetID and button:GetID()
      if bag and slot then MarkButton(button, ItemIDAt(bag, slot)) end
    end
  else
    local bag = frame.GetID and frame:GetID()
    local name = frame.GetName and frame:GetName()
    for i = 1, (frame.size or 0) do
      local button = name and _G[name .. "Item" .. i]
      if button and bag then MarkButton(button, ItemIDAt(bag, button:GetID())) end
    end
  end
end

function ns.RefreshBagMarkers()
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do pcall(UpdateContainerFrame, _G["ContainerFrame" .. i]) end
  pcall(UpdateContainerFrame, _G.ContainerFrameCombinedBags)
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    pcall(Baganator.API.RequestItemButtonsRefresh, { Baganator.Constants and Baganator.Constants.RefreshReason and Baganator.Constants.RefreshReason.ItemWidgets })
  end
end

ns.On("PLAYER_LOGIN", function()
  -- Blizzard bags: re-mark whenever a bag frame redraws
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = _G["ContainerFrame" .. i]
    if f and f.UpdateItems then hooksecurefunc(f, "UpdateItems", function(self) pcall(UpdateContainerFrame, self) end) end
  end
  local combined = _G.ContainerFrameCombinedBags
  if combined and combined.UpdateItems then hooksecurefunc(combined, "UpdateItems", function(self) pcall(UpdateContainerFrame, self) end) end
  if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", function(self) pcall(UpdateContainerFrame, self) end) end

  -- Baganator: a corner widget users can move in Baganator's settings
  if Baganator and Baganator.API and Baganator.API.RegisterCornerWidget then
    pcall(Baganator.API.RegisterCornerWidget, "EPU: guild bank needs this", "epu_guild_needs",
      function(corner, details)
        local id = details and (details.itemID or ns.ItemID(details.itemLink))
        if id == nil then return nil end
        return Needed(id)
      end,
      function(itemButton) return Marker(itemButton) end,
      { corner = "top_left", priority = 1 })
  end
end)
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("bagmarkers", 0.2, ns.RefreshBagMarkers) end)

---------------------------------------------------------------------------
-- 4. Notices (toasts)
---------------------------------------------------------------------------
local toast = CreateFrame("Frame", "EPUGuildToast", UIParent)
toast:SetSize(330, 54)
toast:SetPoint("TOP", 0, -140)
toast:SetFrameStrata("DIALOG")
toast:Hide()
do
  local bg = toast:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.082, 0.090, 0.106, 0.95)
  local edge = toast:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(3)
  edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(34, 34)
  toast.icon:SetPoint("LEFT", 12, 0)
  toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  toast.title = toast:CreateFontString(nil, "OVERLAY")
  toast.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
  toast.title:SetTextColor(1, 1, 1)
  toast.title:SetPoint("TOPLEFT", 54, -10)
  toast.title:SetWidth(260)
  toast.title:SetJustifyH("LEFT")
  toast.text = toast:CreateFontString(nil, "OVERLAY")
  toast.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
  toast.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
  toast.text:SetPoint("TOPLEFT", 54, -28)
  toast.text:SetWidth(260)
  toast.text:SetJustifyH("LEFT")
  toast:EnableMouse(true)
  toast:SetScript("OnMouseUp", function()
    toast:Hide()
    ns.UI:Show()
    ns.UI:SetView("requests")
  end)
end

local toastQueue, toastBusy = {}, false
local function NextToast()
  local t = table.remove(toastQueue, 1)
  if not t then toastBusy = false; toast:Hide() return end
  toastBusy = true
  toast.icon:SetTexture(t.icon or ns.LOGO)
  if t.icon then toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else toast.icon:SetTexCoord(0, 1, 0, 1) end   -- the crest is round; don't crop it
  toast.title:SetText(t.title)
  toast.text:SetText(t.text or "")
  toast:SetAlpha(1)
  toast:Show()
  if t.sound ~= false then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
  C_Timer.After(6, NextToast)
end

function ns.Notify(title, text, icon)
  if not Setting("notices", true) then return end
  ns.Print(title .. (text and text ~= "" and (" - " .. text) or ""))
  table.insert(toastQueue, { title = title, text = text, icon = icon })
  if not toastBusy then NextToast() end
end

-- Called by Merge when a request changes because of someone else.
function ns.OnRequestChanged(rid, r, oldStatus)
  if not r or not ns.me then return end
  local mine = MyChars()
  local name = ns.RequestName(r, true)
  local icon = r.item and ns.ItemIcon(r.item) or "Interface\\Icons\\Trade_Engraving"
  if r.crafter then
    local short = r.crafter:match("^(%S+)") or r.crafter
    if mine[r.who] and oldStatus and oldStatus ~= r.status then
      if r.status == "approved" then
        ns.Notify("Craft accepted", short .. " will make " .. name .. " x" .. r.qty .. "."
          .. (r.mats == "me" and " Mail them the materials." or ""), icon)
      elseif r.status == "filled" then
        ns.Notify("Craft done", short .. " made " .. name .. " x" .. r.qty .. ".", icon)
      elseif r.status == "rejected" then
        ns.Notify("Craft declined", short .. " can't make " .. name .. ((r.reason and r.reason ~= "") and (": " .. r.reason) or ""), icon)
      end
    elseif not oldStatus and mine[r.crafter] and not mine[r.who] and (r.status == "pending" or r.status == "open") then
      ns.Notify("Craft request", ns.WhoLabel(r.who) .. " asks you to make " .. name .. " x" .. r.qty .. ".", icon)
    elseif ns.IsTrusted(ns.me) and r.mats == "bank" and r.status == "approved" and oldStatus ~= "approved"
      and Setting("officerNotices", true) and not mine[r.crafter] then
      ns.Notify("Bank materials needed", short .. " accepted " .. name .. " x" .. r.qty .. " for " .. r.who .. ". The bank sends the materials.", icon)
    end
    return
  end
  if mine[r.who] and oldStatus and oldStatus ~= r.status then
    if r.status == "approved" then
      ns.Notify("Request approved", name .. " x" .. r.qty .. ". It'll be mailed to " .. (r.to or r.who) .. ".", icon)
    elseif r.status == "filled" then
      ns.Notify("Request filled", name .. " x" .. r.qty .. " is on its way to " .. (r.to or r.who) .. "'s mailbox.", icon)
    elseif r.status == "rejected" then
      ns.Notify("Request declined", name .. ((r.reason and r.reason ~= "") and (": " .. r.reason) or ""), icon)
    end
  elseif not oldStatus and not mine[r.who] and ns.IsTrusted(ns.me) and (r.status == "pending" or r.status == "open")
    and Setting("officerNotices", true) then
    ns.Notify("New guild bank request", ns.WhoLabel(r.who) .. " wants " .. name .. " x" .. r.qty .. ".", icon)
  end
end

---------------------------------------------------------------------------
-- 3. Donate at the mailbox: choose items and amounts, then Fill mail
---------------------------------------------------------------------------
local don = CreateFrame("Frame", "EPUGuildDonate", UIParent)
don:SetSize(300, 360)
don:SetFrameStrata("HIGH")
don:Hide()
don:EnableMouse(true)
ns.DonatePanel = don
don.rows, don.pick = {}, {}

local function DText(parent, size, c)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetJustifyH("LEFT")
  return fs
end

local function DBtn(parent, label, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 20)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.165, 0.184, 0.216, 1)
  b.text = DText(b, 11, { 0.85, 0.86, 0.88 })
  b.text:SetPoint("CENTER")
  b.text:SetText(label)
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.22, 0.24, 0.28, 1) end)
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.165, 0.184, 0.216, 1) end)
  return b
end

do
  local bg = don:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.082, 0.090, 0.106, 0.97)
  local top = don:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
  top:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  don.crest = don:CreateTexture(nil, "ARTWORK")
  don.crest:SetTexture(ns.LOGO_SMALL)
  don.crest:SetSize(20, 20)
  don.crest:SetPoint("TOPLEFT", 10, -7)
  don.title = DText(don, 13, { 1, 1, 1 })
  don.title:SetPoint("TOPLEFT", 36, -10)
  don.title:SetText("Donate to the guild bank")
  don.sub = DText(don, 11, MUTED)
  don.sub:SetPoint("TOPLEFT", 12, -28)
  don.sub:SetWidth(276)
  local close = DBtn(don, "x", 20)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() don:Hide(); don.dismissed = true end)
  don.toBtn = DBtn(don, "", 276)
  don.toBtn:SetPoint("TOPLEFT", 12, -48)
  don.toBtn:SetScript("OnClick", function()
    local alts = ns.BankAlts()
    if #alts == 0 then return end
    don.toIndex = (don.toIndex or 1) % #alts + 1
    don:Update()
  end)
  don.list = CreateFrame("Frame", nil, don)
  don.list:SetPoint("TOPLEFT", 8, -74)
  don.list:SetPoint("BOTTOMRIGHT", -8, 66)
  don.empty = DText(don.list, 11, MUTED)
  don.empty:SetPoint("TOP", 0, -20)
  don.empty:SetWidth(260)
  don.empty:SetJustifyH("CENTER")
  don.allBtn = DBtn(don, "Show everything I carry", 160)
  don.allBtn:SetPoint("BOTTOMLEFT", 12, 40)
  don.allBtn:SetScript("OnClick", function() don.showAll = not don.showAll; don:Update() end)
  don.total = DText(don, 11, MUTED)
  don.total:SetPoint("BOTTOMRIGHT", -12, 44)
  don.fill = DBtn(don, "Fill mail", 276)
  don.fill.bg:SetColorTexture(0.17, 0.14, 0.07, 1)
  don.fill.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  don.fill:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.17, 0.14, 0.07, 1) end)
  don.fill:SetPoint("BOTTOMLEFT", 12, 12)
  don.fill:SetScript("OnClick", function() ns.FillDonation() end)
end

-- Items in your bags: { id, count } sorted needed-first
local function Carried()
  local counts = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
    for slot = 1, n do
      local id, count
      if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then id, count = info.itemID, info.stackCount end
      else
        local _, c, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        if link then id, count = ns.ItemID(link), c end
      end
      if id then counts[id] = (counts[id] or 0) + (count or 1) end
    end
  end
  return counts
end

local function DonateRow(i)
  local r = don.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, don.list)
  r:SetSize(284, 30)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
  r:EnableMouseWheel(true)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(24, 24)
  r.icon:SetPoint("LEFT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = DText(r, 11, { 1, 1, 1 })
  r.name:SetPoint("TOPLEFT", 34, -2)
  r.name:SetWidth(120)
  r.info = DText(r, 10, MUTED)
  r.info:SetPoint("TOPLEFT", 34, -16)
  r.info:SetWidth(120)
  r.minus = DBtn(r, "-", 20)
  r.minus:SetPoint("LEFT", 160, 0)
  r.qty = DText(r, 12, GOLD)
  r.qty:SetPoint("LEFT", r.minus, "RIGHT", 2, 0)
  r.qty:SetWidth(30)
  r.qty:SetJustifyH("CENTER")
  r.plus = DBtn(r, "+", 20)
  r.plus:SetPoint("LEFT", r.qty, "RIGHT", 2, 0)
  r.max = DBtn(r, "Max", 34)
  r.max:SetPoint("LEFT", r.plus, "RIGHT", 4, 0)
  local function Change(delta, absolute)
    local id = r.id
    if not id then return end
    local cur = don.pick[id] or 0
    local new = absolute or (cur + delta)
    don.pick[id] = math.max(0, math.min(r.carry or 0, new))
    don:Update()
  end
  -- shift-click +/- moves a whole stack's worth (or 10)
  r.minus:SetScript("OnClick", function() Change(IsShiftKeyDown() and -10 or -1) end)
  r.plus:SetScript("OnClick", function() Change(IsShiftKeyDown() and 10 or 1) end)
  r.max:SetScript("OnClick", function()
    if (don.pick[r.id] or 0) >= (r.suggest or 0) and (r.suggest or 0) > 0 and r.suggest < r.carry then
      Change(0, r.carry)     -- second click: everything you carry
    else
      Change(0, r.suggest and r.suggest > 0 and r.suggest or r.carry)
    end
  end)
  r:SetScript("OnMouseWheel", function(_, delta) Change(delta * (IsShiftKeyDown() and 10 or 1)) end)
  r:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.id)
    GameTooltip:AddLine("Use - / + (shift for 10), the mouse wheel, or Max. Max first picks what the bank still needs; click again for all you carry.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  don.rows[i] = r
  return r
end

function don:Update()
  local alts = ns.BankAlts()
  if #alts == 0 then self:Hide() return end
  self.toIndex = math.min(self.toIndex or 1, #alts)
  self.to = alts[self.toIndex]
  self.toBtn.text:SetText("Send to: " .. self.to .. ((#alts > 1) and "  (click to change)" or ""))
  self.sub:SetText("Pick what to give and how many. Nothing is added unless you choose it.")
  local g = ns.G()
  local carry = Carried()
  local list = {}
  for id, n in pairs(carry) do
    local v = g and g.needs.list[id]
    local target = v and ns.NeedEntry(v) or 0
    local still = math.max(0, target - ns.BankCount(id))
    if still > 0 or self.showAll or (self.pick[id] or 0) > 0 then
      list[#list + 1] = { id = id, carry = n, still = still, name = ns.ItemName(id, true) }
    end
  end
  table.sort(list, function(a, b)
    if (a.still > 0) ~= (b.still > 0) then return a.still > 0 end
    return a.name < b.name
  end)
  local maxRows = math.floor(((self.list:GetHeight() or 220)) / 32)
  local items, stacks = 0, 0
  for i, e in ipairs(list) do
    local r = DonateRow(i)
    if i <= maxRows then
      r.id, r.carry, r.suggest = e.id, e.carry, math.min(e.carry, e.still)
      r.icon:SetTexture(ns.ItemIcon(e.id))
      r.name:SetText(e.name)
      r.info:SetText((e.still > 0) and ("bank needs " .. e.still .. "  ·  you have " .. e.carry) or ("you have " .. e.carry))
      r.qty:SetText(tostring(self.pick[e.id] or 0))
      r:Show()
    else
      r:Hide()
    end
  end
  for i = #list + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].id = nil end
  for id, n in pairs(self.pick) do
    if n > 0 then
      items = items + n
      local _, _, _, _, _, _, _, stackSize = GetItemInfo(id)
      stacks = stacks + math.ceil(n / math.max(1, tonumber(stackSize) or 20))
    end
  end
  self.empty:SetText(self.showAll and "Your bags are empty." or "You're not carrying anything the bank needs right now. Use \"Show everything I carry\" to give something else.")
  self.empty:SetShown(#list == 0)
  self.allBtn.text:SetText(self.showAll and "Show only what's needed" or "Show everything I carry")
  self.total:SetText(items > 0 and (items .. " item" .. (items == 1 and "" or "s")) or "")
  self.fill.text:SetText(items > 0 and "Fill mail" or "Pick something to give")
  self.stacks = stacks
end

function ns.FillDonation()
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first.") end
  local picks = {}
  for id, n in pairs(don.pick) do if n > 0 then picks[#picks + 1] = { id, n } end end
  if #picks == 0 then return ns.Print("Pick something to give first (use + or Max).") end
  if MailFrameTab2 and SendMailFrame and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(don.to) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Donation for the guild bank") end
  if ClearCursor then ClearCursor() end
  local slotIndex, maxSlots = 1, ATTACHMENTS_MAX_SEND or 12
  local left = {}
  for _, p in ipairs(picks) do
    local id, need = p[1], p[2]
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
      for slot = 1, n do
        if need <= 0 or slotIndex > maxSlots then break end
        local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        local sid, count = info and info.itemID, info and info.stackCount
        if not info and GetContainerItemInfo then
          local _, c, _, _, _, _, link = GetContainerItemInfo(bag, slot)
          sid, count = ns.ItemID(link), c
        end
        if sid == id then
          if count <= need then
            if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(bag, slot) else PickupContainerItem(bag, slot) end
            need = need - count
          else
            if C_Container and C_Container.SplitContainerItem then C_Container.SplitContainerItem(bag, slot, need) else SplitContainerItem(bag, slot, need) end
            need = 0
          end
          ClickSendMailItemButton(slotIndex)
          slotIndex = slotIndex + 1
        end
      end
    end
    if need > 0 then left[#left + 1] = ns.ItemLink(id) .. " x" .. need end
  end
  wipe(don.pick)
  don:Update()
  if #left > 0 then
    ns.Print("A mail holds " .. maxSlots .. " stacks, so these didn't fit: " .. table.concat(left, ", ") .. ". Send this one, then pick them again.")
  else
    ns.Print("Mail ready for " .. don.to .. ". Check it, then click Send. Thank you!")
  end
end

local function ShowDonate()
  if not Setting("donatePanel", true) or not MailFrame or not ns.G() then return end
  if ns.IsBankAlt() or #ns.BankAlts() == 0 then return end
  for _, a in ipairs(ns.BankAlts()) do if a == ns.me then return end end
  don:ClearAllPoints()
  don:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
  wipe(don.pick)
  don.showAll, don.dismissed = false, false
  don:Show()
  don:Update()
end
ns.ShowDonate = ShowDonate

ns.On("MAIL_SHOW", function() C_Timer.After(0.1, ShowDonate) end)
ns.On("MAIL_CLOSED", function() don:Hide() end)
ns.On("BAG_UPDATE_DELAYED", function() if don:IsShown() then don:Update() end end)

---------------------------------------------------------------------------
-- 6. Welcome card (first time the window opens; /epu welcome to see it again)
---------------------------------------------------------------------------
local welcome
local function BuildWelcome()
  local UI = ns.UI
  welcome = CreateFrame("Frame", nil, UI)
  welcome:SetAllPoints()
  welcome:SetFrameLevel(UI:GetFrameLevel() + 40)
  welcome:EnableMouse(true)
  local shade = welcome:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.6)
  local card = CreateFrame("Frame", nil, welcome)
  card:SetSize(440, 340)
  card:SetPoint("CENTER")
  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.106, 0.118, 0.137, 1)
  local top = card:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
  top:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  local crest = card:CreateTexture(nil, "ARTWORK")
  crest:SetTexture(ns.LOGO)
  crest:SetSize(44, 44)
  crest:SetPoint("TOPRIGHT", -14, -10)
  local title = DText(card, 15, { 1, 1, 1 })
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("Welcome to the EPU guild bank")
  local tips = {
    { "Interface\\Icons\\INV_Letter_15", "Need something?", "Requests: pick an item, set a number, click Request. You'll get a pop-up when it's approved and mailed." },
    { "Interface\\Icons\\INV_Misc_Coin_01", "Want to help?", "Items the bank needs get a gold coin in your bags and a line on their tooltip. At a mailbox, the Donate panel fills the mail for you." },
    { "Interface\\Icons\\INV_Misc_Note_01", "Colors", "Red bars are badly needed, yellow below target, green stocked. Gold numbers in the sidebar mean something's waiting." },
    { "Interface\\Icons\\INV_Misc_Spyglass_02", "Find anything", "Use the search box at the top, and click any row for details." },
  }
  local y = -48
  for _, t in ipairs(tips) do
    local ic = card:CreateTexture(nil, "ARTWORK")
    ic:SetSize(28, 28)
    ic:SetPoint("TOPLEFT", 18, y)
    ic:SetTexture(t[1])
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local h = DText(card, 12, GOLD)
    h:SetPoint("TOPLEFT", 56, y)
    h:SetText(t[2])
    local b = DText(card, 11, { 0.85, 0.86, 0.88 })
    b:SetPoint("TOPLEFT", 56, y - 16)
    b:SetWidth(366)
    b:SetWordWrap(true)
    b:SetText(t[3])
    y = y - 58
  end
  welcome.mainLine = DText(card, 11, MUTED)
  welcome.mainLine:SetPoint("BOTTOMLEFT", 18, 52)
  welcome.mainBtn = DBtn(card, "Change main", 100)
  welcome.mainBtn:SetPoint("BOTTOMRIGHT", -18, 48)
  welcome.mainBtn:SetScript("OnClick", function()
    local chars, cur = ns.MyChars(), ns.MyMain()
    local idx = 1
    for i, c in ipairs(chars) do if c == cur then idx = i end end
    ns.SetMain(chars[idx % #chars + 1])
    welcome:Refresh()
  end)
  local ok = DBtn(card, "Got it", 120)
  ok:SetPoint("BOTTOMRIGHT", -18, 14)
  ok.bg:SetColorTexture(0.17, 0.14, 0.07, 1)
  ok.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  ok:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.17, 0.14, 0.07, 1) end)
  ok:SetScript("OnClick", function()
    ns.db.settings.welcomed = true
    welcome:Hide()
  end)
  function welcome:Refresh()
    local chars = ns.MyChars()
    if #chars > 1 then
      self.mainLine:SetText("Your main: |cffffffff" .. tostring(ns.MyMain()) .. "|r  (your alts count toward it)")
      self.mainLine:Show(); self.mainBtn:Show()
    else
      self.mainLine:Hide(); self.mainBtn:Hide()
    end
  end
end

function ns.ShowWelcome()
  if not ns.UI then return end
  if not welcome then BuildWelcome() end
  welcome:Refresh()
  welcome:Show()
end

ns.On("PLAYER_LOGIN", function()
  ns.UI:HookScript("OnShow", function()
    if ns.db and not ns.db.settings.welcomed then ns.ShowWelcome() end
  end)
end)


---------------------------------------------------------------------------
-- Our own pop-up. Blizzard's shared StaticPopup boxes get "tainted" when an
-- addon shows one, which can block Blizzard's own dialogs later (Release
-- Spirit, delete item...). So notices use this frame instead.
--   ns.Dialog(title, body, { {label, fn}, {label, fn} })
---------------------------------------------------------------------------
local dialog
local function BuildDialog()
  dialog = CreateFrame("Frame", "EPUGuildDialog", UIParent)
  dialog:SetSize(360, 160)
  dialog:SetPoint("TOP", 0, -140)
  dialog:SetFrameStrata("DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
  dialog:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "EPUGuildDialog")
  local bg = dialog:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.106, 0.118, 0.137, 0.97)
  local top = dialog:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
  top:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  local crest = dialog:CreateTexture(nil, "ARTWORK")
  crest:SetTexture(ns.LOGO)
  crest:SetSize(30, 30)
  crest:SetPoint("TOPLEFT", 12, -10)
  dialog.title = DText(dialog, 14, GOLD)
  dialog.title:SetPoint("TOPLEFT", 50, -12)
  dialog.title:SetPoint("RIGHT", -14, 0)
  dialog.body = DText(dialog, 12, { 0.85, 0.86, 0.88 })
  dialog.body:SetPoint("TOPLEFT", 50, -34)
  dialog.body:SetPoint("RIGHT", -16, 0)
  dialog.body:SetWordWrap(true)
  dialog.buttons = {}
  for i = 1, 2 do
    local b = DBtn(dialog, "", 110)
    b:SetHeight(22)
    dialog.buttons[i] = b
  end
  dialog.buttons[1]:SetPoint("BOTTOMRIGHT", -14, 12)
  dialog.buttons[2]:SetPoint("RIGHT", dialog.buttons[1], "LEFT", -8, 0)
end

function ns.Dialog(title, body, buttons)
  if not dialog then BuildDialog() end
  dialog.title:SetText(title or "")
  dialog.body:SetText(body or "")
  buttons = buttons or { { "Okay" } }
  for i, b in ipairs(dialog.buttons) do
    local spec = buttons[i]
    if spec then
      b.text:SetText(spec[1])
      b:SetWidth(math.max(80, (b.text:GetStringWidth() or 60) + 24))
      b:SetScript("OnClick", function()
        dialog:Hide()
        if spec[2] then spec[2]() end
      end)
      b:Show()
    else
      b:Hide()
    end
  end
  dialog:SetHeight(math.max(120, (dialog.body:GetStringHeight() or 40) + 86))
  dialog:Show()
  return dialog
end

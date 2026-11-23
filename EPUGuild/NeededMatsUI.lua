-- EPU Guild Tools: the Needed mats window (/epu mats). Data and sync: NeededMats.lua.
local ADDON, ns = ...

local function First(name)
  return (name and name:match("^(%S+)")) or name or "?"
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local win
local function Build_Window()
  local K, C = ns.UIKit, ns.InterfaceColors
  win = ns.InterfaceWindow("EPUGuildNeededMats", UIParent, "Needed mats", 460, 480)
  win.widgets = {}

  local item = K.Box(win, 250, "Shift-click or drag a material")
  item:SetPoint("TOPLEFT", 14, -46)
  local qty = K.Box(win, 64, "Amount", true)
  qty:SetPoint("LEFT", item, "RIGHT", 6, 0)
  local add = K.Btn(win, "Add", 90, 22, "accent")
  add:SetPoint("LEFT", qty, "RIGHT", 6, 0)
  local function Add()
    local id = ns.ParseItemArgs(item:GetText())
    if not id then return ns.Print("Shift-click or drag the material into the box first.") end
    if ns.AddNeededMat(id, tonumber(qty:GetText()) or 0) then item:SetText(""); qty:SetText("") end
  end
  add:SetScript("OnClick", Add)
  item.onEnter, qty.onEnter = Add, Add
  win.itemBox, win.qtyBox, win.addButton = item, qty, add

  local hint = K.Font(win, 11, C.muted)
  hint:SetPoint("TOPLEFT", 14, -74)
  hint:SetWidth(430)
  hint:SetWordWrap(true)
  hint:SetText("Guildmates see who needs a material on its tooltip. The amount is optional; when you've gained that many, it comes off your list.")

  local scroll = CreateFrame("ScrollFrame", nil, win)
  scroll:SetPoint("TOPLEFT", 14, -104)
  scroll:SetPoint("BOTTOMRIGHT", -14, 12)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(432); child:SetHeight(360)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxV = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
  end)
  win.child = child

  function win:Refresh()
    for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
    self.widgets = {}
    self.texts = {}
    local y = -2
    local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
    local function Heading(t)
      local h = Track(K.Font(child, 13, C.gold))
      h:SetPoint("TOPLEFT", 0, y)
      h:SetText(t)
      self.texts[#self.texts + 1] = t
      y = y - 22
    end
    local function Row(text, label, fn)
      local fs = Track(K.Font(child, 12, C.text))
      fs:SetPoint("TOPLEFT", 4, y - 4)
      fs:SetWidth(label and 340 or 428)
      fs:SetText(text)
      self.texts[#self.texts + 1] = text
      if label then
        local b = Track(K.Btn(child, label, 80, 20))
        b:SetPoint("TOPRIGHT", 0, y)
        b:SetScript("OnClick", fn)
        self.buttons = self.buttons or {}
        self.buttons[#self.buttons + 1] = b
      end
      y = y - 24
    end
    local function Note(text)
      local fs = Track(K.Font(child, 11, C.muted))
      fs:SetPoint("TOPLEFT", 4, y - 2)
      fs:SetText(text)
      self.texts[#self.texts + 1] = text
      y = y - 22
    end
    self.buttons = {}

    local mine = ns.MyNeededMats()
    Heading("Your needed mats (" .. First(ns.me) .. ")")
    if #mine == 0 then Note("Nothing yet. Add a material above, or type /epu mats add [item] 20.") end
    for _, e in ipairs(mine) do
      local text = ns.ItemLink(e.id)
      if e.q > 0 then text = text .. "  x" .. e.need .. (e.got > 0 and (" (" .. e.got .. " of " .. e.q .. " in)") or "") end
      if e.p then text = text .. "  |cffa3afc2" .. e.p .. "|r" end
      Row(text, "Remove", function() ns.RemoveNeededMat(e.id) end)
    end

    y = y - 8
    local guild = ns.GuildNeededMats()
    Heading("Guild needed mats")
    if #guild == 0 then Note("No guildmate has listed a material yet.") end
    local officer = ns.IsTrusted(ns.me)
    for i = 1, math.min(80, #guild) do
      local e = guild[i]
      local who = e.online and ("|cff4ade80" .. e.who .. "|r") or e.who
      local text = ns.ItemLink(e.id) .. (e.n > 0 and ("  x" .. e.n) or "") .. "  " .. who .. (e.p and ("  |cffa3afc2" .. e.p .. "|r") or "")
      if officer then Row(text, "Clear", function() ns.ClearNeededMat(e.who, e.id) end) else Row(text) end
    end
    if #guild > 80 then Note("+" .. (#guild - 80) .. " more") end
    child:SetHeight(math.max(360, -y + 10))
  end
  win:SetScript("OnShow", function(self) self:Refresh() end)
end

function ns.RefreshNeededMatsWindow()
  if win and win:IsShown() then ns.Debounce("neededMatsWindow", 0.2, function() win:Refresh() end) end
end

function ns.ShowNeededMats()
  if not ns.G() then return ns.Print("You are not in a guild.") end
  if not win then Build_Window() end
  win:Show()
  win:Refresh()
  return win
end

-- Shift-clicking an item while the window is open puts it in the box.
local lastLink, lastAt = nil, 0
local function OnInsertLink(link)
  if not (win and win:IsShown()) or type(link) ~= "string" or not link:find("|Hitem:") then return end
  if link == lastLink and GetTime() - lastAt < 0.2 then return end
  lastLink, lastAt = link, GetTime()
  -- When the main window is open too, it fills only the box being typed in.
  if ns.UI and ns.UI:IsShown() and ns.UI.focusBox and ns.UI.focusBox ~= win.itemBox and ns.UI.focusBox ~= win.qtyBox then return end
  win.itemBox:SetText(link)
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
if HandleModifiedItemClick then
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then OnInsertLink(link) end
  end)
end

-- EPU Guild Tools: guild bank gear that fits you.
-- Looks through what the guild bank and the bank alts hold for weapons and
-- armor this character can use: the required level is yours or a few levels
-- ahead, the armor type is the one your class wears (plate and mail once
-- your class learns them at 40), and the weapon type is one your class can
-- train. Each item says whether it beats what you wear in that slot, by item
-- level, and gets the same one button as needed mats in the bank:
--   Pull      take it straight out of the open guild bank, where your rank
--             may withdraw from that tab
--   Request   file a bank request the bank managers see
--   Requested you already have an open request for it
-- Open it from the Gear for you button on the main window's Bank page, the
-- Bank gear for you tile in Member tools, or /epu bankgear.
local ADDON, ns = ...

-- looked up on each call, so a client that swaps in its item API later still works
local function GetItemInfo(x) return ((C_Item and C_Item.GetItemInfo) or _G.GetItemInfo)(x) end

ns.BANK_GEAR_AHEAD = 5    -- gear you can wear within this many levels
ns.BANK_GEAR_BEHIND = 10  -- gear further below your level shows only when it's an upgrade

-- Armor types by class, best first, with the level the class learns each.
-- Subclasses: 1 cloth, 2 leather, 3 mail, 4 plate.
local ARMOR = {
  WARRIOR = { { 4, 40 }, { 3, 1 } }, PALADIN = { { 4, 40 }, { 3, 1 } },
  HUNTER = { { 3, 40 }, { 2, 1 } }, SHAMAN = { { 3, 40 }, { 2, 1 } },
  ROGUE = { { 2, 1 } }, DRUID = { { 2, 1 } },
  PRIEST = { { 1, 1 } }, MAGE = { { 1, 1 } }, WARLOCK = { { 1, 1 } },
}
-- Shields (6) and relics: librams (7), idols (8), totems (9).
local ARMOR_EXTRA = {
  [6] = { WARRIOR = true, PALADIN = true, SHAMAN = true },
  [7] = { PALADIN = true }, [8] = { DRUID = true }, [9] = { SHAMAN = true },
}
-- Weapon types each class can train. 0/1 axes, 2 bows, 3 guns, 4/5 maces,
-- 6 polearms, 7/8 swords, 10 staves, 13 fist, 14 miscellaneous, 15 daggers,
-- 16 thrown, 18 crossbows, 19 wands.
local function Set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
local WEAPONS = {
  WARRIOR = Set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18 }),
  PALADIN = Set({ 0, 1, 4, 5, 6, 7, 8, 14 }),
  HUNTER = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 14, 15, 16, 18 }),
  ROGUE = Set({ 2, 3, 4, 7, 13, 14, 15, 16, 18 }),
  PRIEST = Set({ 4, 10, 14, 15, 19 }),
  SHAMAN = Set({ 0, 1, 4, 5, 10, 13, 14, 15 }),
  MAGE = Set({ 7, 10, 14, 15, 19 }),
  WARLOCK = Set({ 7, 10, 14, 15, 19 }),
  DRUID = Set({ 4, 5, 10, 13, 14, 15 }),
}
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- Equipment slots each kind of item goes in, and what to call it.
local SLOTS = {
  INVTYPE_HEAD = { { 1 }, "Head" }, INVTYPE_NECK = { { 2 }, "Neck" }, INVTYPE_SHOULDER = { { 3 }, "Shoulder" },
  INVTYPE_CHEST = { { 5 }, "Chest" }, INVTYPE_ROBE = { { 5 }, "Chest" }, INVTYPE_WAIST = { { 6 }, "Waist" },
  INVTYPE_LEGS = { { 7 }, "Legs" }, INVTYPE_FEET = { { 8 }, "Feet" }, INVTYPE_WRIST = { { 9 }, "Wrist" },
  INVTYPE_HAND = { { 10 }, "Hands" }, INVTYPE_FINGER = { { 11, 12 }, "Finger" }, INVTYPE_TRINKET = { { 13, 14 }, "Trinket" },
  INVTYPE_CLOAK = { { 15 }, "Back" }, INVTYPE_WEAPON = { { 16 }, "One-hand" }, INVTYPE_2HWEAPON = { { 16 }, "Two-hand" },
  INVTYPE_WEAPONMAINHAND = { { 16 }, "Main hand" }, INVTYPE_WEAPONOFFHAND = { { 17 }, "Off hand" },
  INVTYPE_SHIELD = { { 17 }, "Shield" }, INVTYPE_HOLDABLE = { { 17 }, "Held in off hand" },
  INVTYPE_RANGED = { { 18 }, "Ranged" }, INVTYPE_RANGEDRIGHT = { { 18 }, "Ranged" }, INVTYPE_THROWN = { { 18 }, "Thrown" },
  INVTYPE_RELIC = { { 18 }, "Relic" },
}

-- The armor type a class wears at a level: 1 cloth .. 4 plate.
function ns.BankGearArmorType(class, level)
  for _, a in ipairs(ARMOR[class] or {}) do
    if level >= a[2] then return a[1] end
  end
  return 1
end

-- Can a character of `class` at `level` use this item, now or within
-- BANK_GEAR_AHEAD levels? info = { classID, subclassID, equipLoc, reqLevel }.
-- Returns false, or "now" / "soon".
function ns.BankGearFits(info, class, level)
  if not info or not class or not level or not SLOTS[info.equipLoc] then return false end
  local req = tonumber(info.reqLevel) or 0
  if req > level + ns.BANK_GEAR_AHEAD then return false end
  local at = math.max(level, req)   -- the level you'd wear it at
  local sub = info.subclassID
  if info.classID == 4 then
    if sub == 0 or info.equipLoc == "INVTYPE_CLOAK" then
      -- rings, necks, trinkets, off-hand frills and cloaks: anyone
    elseif sub >= 1 and sub <= 4 then
      if sub ~= ns.BankGearArmorType(class, at) then return false end
    elseif not (ARMOR_EXTRA[sub] and ARMOR_EXTRA[sub][class]) then
      return false
    end
  elseif info.classID == 2 then
    if not (WEAPONS[class] and WEAPONS[class][sub]) then return false end
  else
    return false
  end
  return req <= level and "now" or "soon"
end

local function ItemLevelOf(link)
  if not link then return nil end
  local name, _, _, ilvl = GetItemInfo(link)
  if not name then return nil end   -- not loaded yet
  return tonumber(ilvl) or 0, name
end

-- What you wear where this item would go: the weakest of the slots it can
-- take, by item level (0 for an empty slot), and that item's name.
function ns.BankGearEquipped(equipLoc, class)
  local s = SLOTS[equipLoc]
  if not s or not GetInventoryItemLink then return nil end
  local slots = s[1]
  if equipLoc == "INVTYPE_WEAPON" and DUAL_WIELD[class] then slots = { 16, 17 } end
  local best, bestName
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    -- an off hand next to a two-hander is measured against the two-hander
    if not link and slot == 17 then
      local main = GetInventoryItemLink("player", 16)
      if main and select(9, GetItemInfo(main)) == "INVTYPE_2HWEAPON" then link = main end
    end
    local ilvl, name = ItemLevelOf(link)
    if link and not ilvl then return nil end   -- can't compare until it loads
    ilvl = ilvl or 0
    if not best or ilvl < best then best, bestName = ilvl, name end
  end
  return best, bestName
end

local function MyClass()
  if not UnitClass then return nil end
  local _, class = UnitClass("player")
  return class
end

-- Every bank item id held right now (guild bank and bank alts).
local function HeldIDs()
  local ids, g = {}, ns.G()
  for _, s in pairs((g and g.bank) or {}) do
    if not s.retired and type(s.items) == "table" then
      for id, n in pairs(s.items) do
        id = tonumber(id)
        if id and (tonumber(n) or 0) > 0 then ids[id] = true end
      end
    end
  end
  return ids
end

-- What the button does: "pull", "request", "requested" or nil.
local function Action(e)
  if e.request then return "requested" end
  local open = ns.GuildBankIsOpen and ns.GuildBankIsOpen()
  if open and ns.PlanGuildBankPull and #(ns.PlanGuildBankPull(e.id, 1)) > 0 then return "pull" end
  if ns.CanBankRequest and not ns.CanBankRequest(e.id) then return nil end
  return "request"
end

local function Opt()
  if not ns.cdb then return {} end
  ns.cdb.bankGear = ns.cdb.bankGear or {}
  return ns.cdb.bankGear
end
function ns.BankGearUpgradesOnly() return Opt().upgradesOnly == true end
function ns.SetBankGearUpgradesOnly(on)
  Opt().upgradesOnly = on and true or nil
  if ns.RefreshBankGear then ns.RefreshBankGear() end
end

-- Bank gear for this character, upgrades first, then what you can wear now:
--   { id, name, quality, ilvl, reqLevel, equipLoc, slot, fit ("now"/"soon"),
--     yours (item level you wear there, 0 = empty), yoursName, upgrade,
--     held, where, request, requestStatus, action }
-- Also returns how many bank items are still loading their item info.
function ns.BankGearForMe()
  local list, loading = {}, 0
  if not ns.G() then return list, 0 end
  local class, level = MyClass(), tonumber(UnitLevel and UnitLevel("player")) or 1
  if not class then return list, 0 end
  local upgradesOnly = ns.BankGearUpgradesOnly()
  for id in pairs(HeldIDs()) do
    local name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID = GetItemInfo(id)
    if not name then
      local c
      if GetItemInfoInstant then c = select(6, GetItemInfoInstant(id)) end
      if c == nil or c == 2 or c == 4 then
        loading = loading + 1
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
    elseif classID == 2 or classID == 4 then
      local info = { classID = classID, subclassID = subclassID, equipLoc = equipLoc, reqLevel = reqLevel }
      local fit = ns.BankGearFits(info, class, level)
      if fit then
        ilvl = tonumber(ilvl) or 0
        local yours, yoursName = ns.BankGearEquipped(equipLoc, class)
        local upgrade = yours ~= nil and ilvl > yours
        local tooLow = (tonumber(reqLevel) or 0) < level - ns.BANK_GEAR_BEHIND
        if (upgrade or not (tooLow or upgradesOnly)) then
          local where, held = ns.BankHoldings(id)
          if held > 0 then
            local e = { id = id, name = name, quality = quality, ilvl = ilvl, reqLevel = tonumber(reqLevel) or 0,
              equipLoc = equipLoc, slot = SLOTS[equipLoc][2], fit = fit, yours = yours, yoursName = yoursName,
              upgrade = upgrade, held = held, where = where }
            local rid, r
            if ns.OpenBankRequest then rid, r = ns.OpenBankRequest(ns.me, id) end
            e.request, e.requestStatus = rid, r and r.status
            e.action = Action(e)
            list[#list + 1] = e
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.upgrade ~= b.upgrade then return a.upgrade end
    if (a.fit == "now") ~= (b.fit == "now") then return a.fit == "now" end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    return a.name < b.name
  end)
  return list, loading
end

-- "Upgrade over your Ring of Foo (item level 18)"
function ns.BankGearCompareText(e)
  if not e.yours then return nil end
  if e.yours == 0 then return "Upgrade: your " .. e.slot:lower() .. " slot is empty" end
  local yours = (e.yoursName and ("your " .. e.yoursName) or "yours") .. " (item level " .. e.yours .. ")"
  if e.upgrade then return "Upgrade over " .. yours end
  return "Not an upgrade over " .. yours
end

local function Find(id)
  for _, e in ipairs((ns.BankGearForMe())) do
    if e.id == id then return e end
  end
end

-- The one-click button: pull it at the open guild bank, or ask for it.
function ns.TakeBankGear(id)
  id = tonumber(id)
  local e = id and Find(id)
  if not e then return ns.Print("The bank doesn't hold that item, or it doesn't fit this character.") end
  local link = ns.ItemLink(id)
  local Refresh = function() if ns.RefreshBankGear then ns.RefreshBankGear() end end
  if e.action == "requested" then
    return ns.Print("You already asked the bank for " .. link .. ". A bank manager will send it.")
  elseif e.action == "pull" then
    return ns.PullFromGuildBank(id, 1, function(moved)
      if moved > 0 then ns.Print("Took " .. link .. " from the guild bank.")
      else ns.Print("Nothing moved from the guild bank. Check your withdrawal limit for today, then try again.") end
      Refresh()
    end)
  elseif e.action == "request" then
    local rid = ns.NewRequest(id, 1, "Bank gear")
    if rid then Refresh() end
    return rid
  end
  ns.Print("That item can't be requested right now.")
end

---------------------------------------------------------------------------
-- Window: /epu bankgear, Gear for you on the Bank page, or the Member tools tile
---------------------------------------------------------------------------
local LABEL = { pull = "Pull", request = "Request", requested = "Requested" }
local win

local function Build_Window()
  local K, C = ns.UIKit, ns.InterfaceColors
  win = ns.InterfaceWindow("EPUGuildBankGear", UIParent, "Bank gear for you", 540, 480)

  local hint = K.Font(win, 11, C.muted)
  hint:SetPoint("TOPLEFT", 14, -46)
  hint:SetWidth(380)
  hint:SetWordWrap(true)
  win.hint = hint

  local toggle = K.Btn(win, "Upgrades only", 112, 22)
  toggle:SetPoint("TOPRIGHT", -14, -44)
  toggle:SetScript("OnClick", function() ns.SetBankGearUpgradesOnly(not ns.BankGearUpgradesOnly()); win:Refresh() end)
  toggle.tip = "Show only items with a higher item level than what you wear in that slot."
  win.toggle = toggle

  local scroll = CreateFrame("ScrollFrame", nil, win)
  scroll:SetPoint("TOPLEFT", 14, -84)
  scroll:SetPoint("BOTTOMRIGHT", -14, 12)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(512); child:SetHeight(380)
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
    local upgradesOnly = ns.BankGearUpgradesOnly()
    self.toggle.text:SetText(upgradesOnly and "Show all" or "Upgrades only")
    local level = tonumber(UnitLevel and UnitLevel("player")) or 1
    local open = ns.GuildBankIsOpen and ns.GuildBankIsOpen()
    self.hint:SetText("Weapons and armor in the bank you can use at level " .. level .. " or within "
      .. ns.BANK_GEAR_AHEAD .. " levels. Upgrades compare item level with what you wear. "
      .. (open and "Pull takes it into your bags." or "Open the guild bank to Pull, or Request it from the bank managers."))
    local y = -2
    local list, loading = ns.BankGearForMe()
    if #list == 0 then
      local fs = pool:Font(12, C.muted)
      fs:SetPoint("TOPLEFT", 4, y - 4)
      fs:SetWidth(500)
      fs:SetWordWrap(true)
      fs:SetText(upgradesOnly and "No upgrades for you in the bank right now. Press Show all to see everything that fits."
        or "The bank holds no weapons or armor that fit you right now.")
      self.texts[#self.texts + 1] = fs:GetText()
      y = y - 40
    end
    for i = 1, math.min(80, #list) do
      local e = list[i]
      local text = ns.ItemLink(e.id) .. "  |cffa3afc2" .. e.slot .. " · item level " .. e.ilvl .. "|r"
      local when = e.fit == "now" and "Wear it now" or ("|cfff2c14eWear it at level " .. e.reqLevel .. "|r")
      local cmp = ns.BankGearCompareText(e)
      if cmp then cmp = (e.upgrade and "|cff4ade80" or "|cffa3afc2") .. cmp .. "|r" end
      local sub = when .. (cmp and ("  ·  " .. cmp) or "")
      local sub2 = "In the bank: " .. ns.BankHoldingsText(e.where)
        .. (e.request and ("  |cfff2c14e" .. (e.requestStatus == "approved" and "approved request" or "request waiting") .. "|r") or "")
      local fs = pool:Font(12, C.text, "row")
      fs:SetPoint("TOPLEFT", 4, y - 2)
      fs:SetWidth(410)
      fs:SetText(text)
      local s = pool:Font(11, C.muted, "sub")
      s:SetPoint("TOPLEFT", 4, y - 18)
      s:SetWidth(410)
      s:SetText(sub)
      local s2 = pool:Font(11, C.muted, "sub2")
      s2:SetPoint("TOPLEFT", 4, y - 32)
      s2:SetWidth(410)
      s2:SetText(sub2)
      self.texts[#self.texts + 1] = text
      self.texts[#self.texts + 1] = sub
      self.texts[#self.texts + 1] = sub2
      if e.action then
        local b = pool:Button(LABEL[e.action], 84, 20)
        b:SetPoint("TOPRIGHT", 0, y - 6)
        b:SetScript("OnClick", function() ns.TakeBankGear(e.id) end)
        b.action, b.item = e.action, e.id
        self.buttons[#self.buttons + 1] = b
      end
      y = y - 52
    end
    if #list > 80 or loading > 0 then
      local fs = pool:Font(11, C.muted)
      fs:SetPoint("TOPLEFT", 4, y - 2)
      fs:SetText((#list > 80 and ("+" .. (#list - 80) .. " more. ") or "")
        .. (loading > 0 and (loading .. " bank item" .. (loading == 1 and " is" or "s are") .. " still loading.") or ""))
      self.texts[#self.texts + 1] = fs:GetText()
      y = y - 22
    end
    child:SetHeight(math.max(380, -y + 10))
  end
  win:SetScript("OnShow", function(self) self:Refresh() end)
end

function ns.RefreshBankGear()
  if win and win:IsShown() then ns.Debounce("bankGearWindow", 0.3, function() win:Refresh() end) end
end

function ns.ShowBankGear()
  if not ns.G() then return ns.Print("You are not in a guild.") end
  if not win then Build_Window() end
  win:Show()
  win:Refresh()
  return win
end

for _, ev in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "BAG_UPDATE_DELAYED",
                      "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }) do
  ns.On(ev, function() ns.RefreshBankGear() end)
end

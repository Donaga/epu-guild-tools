-- EPU Guild Tools: World travel, waypoints, flight timer, vendor QoL, and item tooltip extras.
local _, ns = ...

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function DB()
  if not ns.db then return {} end
  ns.db.worldQoL = ns.db.worldQoL or {}
  local db = ns.db.worldQoL
  if db.mapCoords == nil then db.mapCoords = true end
  if db.waypoints == nil then db.waypoints = true end
  if db.flightTimer == nil then db.flightTimer = true end
  if db.autoSellGrey == nil then db.autoSellGrey = true end
  if db.autoRepair == nil then db.autoRepair = true end
  -- Paying repairs from the guild bank is the player's choice, not a default.
  -- 0.30.x saved it as on for everyone, so reset it once; the toggle below
  -- marks it chosen.
  if not db.guildRepairChosen then db.guildRepair = false end
  if db.tooltipExtras == nil then db.tooltipExtras = true end
  db.flightTimes = db.flightTimes or {}
  db.altItems = db.altItems or {}
  return db
end

local function FormatMoneyText(copper)
  copper = math.floor(math.abs(copper or 0))
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

local function ClassHex(cf)
  local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if c then
    if c.colorStr then return "|c" .. c.colorStr end
    return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5), math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
  end
  return "|cffffffff"
end

---------------------------------------------------------------------------
-- 1. World Map Player & Cursor Coordinates (parented to UIParent to avoid taint)
---------------------------------------------------------------------------
local coordFrame, coordText
local function SetupMapCoords()
  if coordFrame or not WorldMapFrame then return end
  local C = ns.InterfaceColors
  coordFrame = CreateFrame("Frame", "EPUGuildMapCoords", UIParent)
  coordFrame:SetSize(250, 22)
  coordFrame:SetFrameStrata("HIGH")
  coordFrame:Hide()
  local bg = coordFrame:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.82)
  bg:SetAllPoints()
  coordText = ns.InterfaceFont(coordFrame, 11, C.white)
  coordText:SetPoint("CENTER")

  local function SyncShown()
    if DB().mapCoords and WorldMapFrame:IsShown() then
      coordFrame:ClearAllPoints()
      coordFrame:SetPoint("BOTTOM", WorldMapFrame, "BOTTOM", 0, 10)
      coordFrame:Show()
    else
      coordFrame:Hide()
    end
  end
  WorldMapFrame:HookScript("OnShow", SyncShown)
  WorldMapFrame:HookScript("OnHide", SyncShown)

  local elapsed = 0
  coordFrame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if not DB().mapCoords or not WorldMapFrame:IsShown() then coordFrame:Hide(); return end

    local pStr = "Player: --"
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
      local mapID = C_Map.GetBestMapForUnit("player")
      local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
      if pos and pos.GetXY then
        local px, py = pos:GetXY()
        if px and py and (px > 0 or py > 0) then
          pStr = string.format("Player: %.1f, %.1f", px * 100, py * 100)
        end
      end
    end

    local cStr = "Cursor: --"
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.GetNormalizedCursorPosition then
      local ok, cx, cy = pcall(sc.GetNormalizedCursorPosition, sc)
      if ok and cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        cStr = string.format("Cursor: %.1f, %.1f", cx * 100, cy * 100)
      end
    end
    coordText:SetText(pStr .. "   |cff888888||r   " .. cStr)
  end)
end

---------------------------------------------------------------------------
-- 2. Simple /way x y Waypoint HUD
---------------------------------------------------------------------------
local wayFrame, wayText, wayArrow
local activeWay

local function EnsureWayFrame()
  if wayFrame then return wayFrame end
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", "EPUGuildWaypointFrame", UIParent)
  f:SetSize(210, 44)
  f:SetPoint("TOP", UIParent, "TOP", 0, -110)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.88)
  bg:SetAllPoints()
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4] or 1)
    t:SetPoint(side[1]); t:SetPoint(side[2])
    if side[3] then t:SetHeight(1) else t:SetWidth(1) end
  end

  wayArrow = f:CreateTexture(nil, "ARTWORK")
  wayArrow:SetSize(22, 22)
  wayArrow:SetPoint("LEFT", 10, 0)
  wayArrow:SetTexture("Interface\\Minimap\\MinimapArrow")

  wayText = ns.InterfaceFont(f, 11, C.white)
  wayText:SetPoint("LEFT", wayArrow, "RIGHT", 8, 0)
  wayText:SetPoint("RIGHT", -24, 0)
  wayText:SetJustifyH("LEFT")

  local close = ns.InterfaceButton(f, "×", 18, 18)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() activeWay = nil; f:Hide() end)

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.08 then return end
    acc = 0
    if not activeWay or not DB().waypoints then f:Hide(); return end
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID ~= activeWay.mapID then
      wayText:SetText((activeWay.label or "Waypoint") .. "\n|cff888888Different zone|r")
      return
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or not pos.GetXY then return end
    local px, py = pos:GetXY()
    if not px or not py then return end
    local dx = (activeWay.x - px)
    local dy = (activeWay.y - py)
    local distPct = math.sqrt(dx * dx + dy * dy) * 100
    if distPct < 0.8 then
      ns.Print("Arrived at waypoint" .. (activeWay.label and (": " .. activeWay.label) or "."))
      activeWay = nil
      f:Hide()
      return
    end
    local facing = GetPlayerFacing and SafeNum(GetPlayerFacing()) or 0
    local targetAngle = math.atan2(-dx, -dy)
    if wayArrow.SetRotation then
      wayArrow:SetRotation(targetAngle - facing)
    end
    wayText:SetText(string.format("%s\n|cff4fc3f7%.1f, %.1f|r  |cff888888(%.1f)|r", activeWay.label or "Waypoint", activeWay.x * 100, activeWay.y * 100, distPct))
  end)

  wayFrame = f
  return f
end

function ns.SetWaypoint(x, y, label)
  if not DB().waypoints then return ns.Print("Waypoints are disabled in /epu qol.") end
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if not mapID then return ns.Print("Could not determine current map.") end
  activeWay = { mapID = mapID, x = x / 100, y = y / 100, label = label and label ~= "" and label or nil }
  EnsureWayFrame():Show()
end

function ns.HandleWayCommand(msg)
  msg = tostring(msg or ""):match("^%s*(.-)%s*$")
  if msg == "" or msg:lower() == "clear" or msg:lower() == "reset" then
    activeWay = nil
    if wayFrame then wayFrame:Hide() end
    return ns.Print("Waypoint cleared.")
  end
  local xStr, yStr, rest = msg:match("^(%d+%.?%d*)%s*[,%s]+(%d+%.?%d*)%s*(.*)$")
  local x, y = tonumber(xStr), tonumber(yStr)
  if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
    return ns.Print("Usage: /epu way <x> <y> [label]  or  /epu way clear")
  end
  ns.SetWaypoint(x, y, rest)
end

---------------------------------------------------------------------------
-- 3. Flight Path Timer (learns route durations automatically)
---------------------------------------------------------------------------
local flightFrame, flightBar, flightText
local curFlight = nil

local function EnsureFlightFrame()
  if flightFrame then return flightFrame end
  local C = ns.InterfaceColors
  local f = CreateFrame("Frame", "EPUGuildFlightTimer", UIParent)
  f:SetSize(240, 26)
  f:SetPoint("TOP", UIParent, "TOP", 0, -165)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.9)
  bg:SetAllPoints()

  flightBar = CreateFrame("StatusBar", nil, f)
  flightBar:SetPoint("TOPLEFT", 2, -2)
  flightBar:SetPoint("BOTTOMRIGHT", -2, 2)
  flightBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  flightBar:SetStatusBarColor(0.24, 0.62, 0.92, 0.85)
  flightBar:SetMinMaxValues(0, 1)

  flightText = ns.InterfaceFont(flightBar, 11, C.white)
  flightText:SetPoint("CENTER")

  f:SetScript("OnUpdate", function()
    if not curFlight or not DB().flightTimer then f:Hide(); return end
    if UnitOnTaxi and not UnitOnTaxi("player") then
      local elapsed = math.floor((GetTime() - curFlight.startedAt) + 0.5)
      if elapsed >= 3 and curFlight.key then
        DB().flightTimes[curFlight.key] = elapsed
      end
      curFlight = nil
      f:Hide()
      return
    end
    local elapsed = GetTime() - curFlight.startedAt
    if curFlight.expected and curFlight.expected > 0 then
      local rem = math.max(0, math.ceil(curFlight.expected - elapsed))
      flightBar:SetValue(math.min(1, elapsed / curFlight.expected))
      flightText:SetText(string.format("%s  (%ds)", curFlight.dest or "In Flight", rem))
    else
      flightBar:SetValue(1)
      flightText:SetText(string.format("%s  (%ds)", curFlight.dest or "In Flight", math.floor(elapsed)))
    end
  end)

  flightFrame = f
  return f
end

if hooksecurefunc and TakeTaxiNode then
  hooksecurefunc("TakeTaxiNode", function(slot)
    if not DB().flightTimer then return end
    local dest = TaxiNodeName and SafeStr(TaxiNodeName(slot)) or "Destination"
    local from = (GetMinimapZoneText and SafeStr(GetMinimapZoneText())) or "Origin"
    local key = from .. "->" .. dest
    curFlight = {
      key = key,
      dest = dest,
      startedAt = GetTime(),
      expected = DB().flightTimes[key],
    }
    EnsureFlightFrame():Show()
  end)
end

---------------------------------------------------------------------------
-- 4. Auto-Sell Grey Junk & Auto-Repair at Merchants (hold Shift to skip)
---------------------------------------------------------------------------
local function OnMerchantShow()
  if IsShiftKeyDown and IsShiftKeyDown() then return end
  -- A bank alt's bags and gold are the guild's: leave them alone.
  if ns.IsBankAlt and ns.IsBankAlt() then return end
  local db = DB()

  if db.autoSellGrey then
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local getInfo = C_Container and C_Container.GetContainerItemInfo
    local useItem = C_Container and C_Container.UseContainerItem or UseContainerItem
    local soldCount, soldCopper = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      local n = getSlots and SafeNum(getSlots(bag)) or 0
      for slot = 1, (n or 0) do
        local link, quality, count
        if getInfo then
          local info = getInfo(bag, slot)
          if info then link, quality, count = info.hyperlink, info.quality, info.stackCount end
        elseif GetContainerItemInfo then
          local _, c, _, q, _, _, l = GetContainerItemInfo(bag, slot)
          link, quality, count = l, q, c
        end
        if quality == 0 and SafeStr(link) then
          local sellPrice = GetItemInfo and select(11, GetItemInfo(link))
          sellPrice = SafeNum(sellPrice) or 0
          if sellPrice > 0 and useItem then
            soldCount = soldCount + (count or 1)
            soldCopper = soldCopper + sellPrice * (count or 1)
            useItem(bag, slot)
          end
        end
      end
    end
    if soldCount > 0 then
      ns.Print(string.format("Sold %d grey item%s for %s.", soldCount, soldCount == 1 and "" or "s", FormatMoneyText(soldCopper)))
    end
  end

  if db.autoRepair and CanMerchantRepair and CanMerchantRepair() then
    local cost, canRepair = GetRepairAllCost()
    cost = SafeNum(cost) or 0
    if canRepair and cost > 0 then
      if db.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        -- What the guild can pay: today's withdrawal limit (-1 = no limit),
        -- but never more than the guild bank holds.
        local gLimit = GetGuildBankWithdrawMoney and SafeNum(GetGuildBankWithdrawMoney()) or 0
        local inBank = GetGuildBankMoney and SafeNum(GetGuildBankMoney()) or 0
        local canPay = gLimit == -1 and inBank or math.min(gLimit, inBank)
        if canPay >= cost then
          RepairAllItems(true)
          ns.Print("Repaired using guild bank funds: " .. FormatMoneyText(cost))
          return
        end
      end
      if GetMoney and (SafeNum(GetMoney()) or 0) >= cost then
        RepairAllItems(false)
        ns.Print("Repaired for " .. FormatMoneyText(cost))
      end
    end
  end
end

---------------------------------------------------------------------------
-- 5. Item Tooltip Extras (Alt/Bank item counts, vendor sell price, stack)
---------------------------------------------------------------------------
local function ScanCharacterItems(includeBank)
  if not ns.me then return end
  local db = DB()
  if not db.altItems then return end
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  db.altItems[realm] = db.altItems[realm] or {}
  local _, cf = UnitClass and UnitClass("player")
  local rec = db.altItems[realm][ns.me] or { bags = {}, bank = {} }
  rec.classFile = cf
  rec.bags = {}

  local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local getInfo = C_Container and C_Container.GetContainerItemInfo
  local function ScanBag(bagID, dest)
    local n = getSlots and SafeNum(getSlots(bagID)) or 0
    for slot = 1, (n or 0) do
      local itemID, count
      if getInfo then
        local info = getInfo(bagID, slot)
        if info then itemID, count = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, _, _, _, id = GetContainerItemInfo(bagID, slot)
        itemID, count = id, c
      end
      if SafeNum(itemID) and SafeNum(count) then
        dest[itemID] = (dest[itemID] or 0) + count
      end
    end
  end

  for bag = 0, (NUM_BAG_SLOTS or 4) do ScanBag(bag, rec.bags) end
  if includeBank then
    rec.bank = {}
    if BANK_CONTAINER then ScanBag(BANK_CONTAINER, rec.bank) end
    if NUM_BAG_SLOTS and NUM_BANKBAGSLOTS then
      for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do ScanBag(bag, rec.bank) end
    end
  end
  db.altItems[realm][ns.me] = rec
end

local function AppendItemTooltip(tt, itemLinkOrID)
  if not tt or not DB().tooltipExtras then return end
  local itemID = type(itemLinkOrID) == "number" and itemLinkOrID or (SafeStr(itemLinkOrID) and tonumber(itemLinkOrID:match("item:(%d+)")))
  if not itemID then return end

  local _, _, _, _, _, _, _, maxStack, _, _, sellPrice = GetItemInfo and GetItemInfo(itemID)
  maxStack = SafeNum(maxStack)
  sellPrice = SafeNum(sellPrice)

  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  local realmAlts = DB().altItems and DB().altItems[realm] or {}
  local altLines = {}
  local total = 0
  for who, rec in pairs(realmAlts) do
    local b = rec.bags and rec.bags[itemID] or 0
    local bk = rec.bank and rec.bank[itemID] or 0
    if b + bk > 0 then
      total = total + b + bk
      local detail = (b > 0 and bk > 0) and (b .. " bag, " .. bk .. " bank") or (bk > 0 and (bk .. " bank") or (b .. " bag"))
      altLines[#altLines + 1] = { name = ClassHex(rec.classFile) .. (ns.Short and ns.Short(who) or who) .. "|r", text = detail }
    end
  end

  if #altLines > 0 then
    table.sort(altLines, function(a, b) return a.name < b.name end)
    tt:AddLine(" ")
    tt:AddDoubleLine("Owned on Realm:", "|cffffffff" .. total .. "|r", 0.4, 0.8, 1, 1, 1, 1)
    for _, line in ipairs(altLines) do
      tt:AddDoubleLine("  " .. line.name, line.text, 1, 1, 1, 0.85, 0.85, 0.85)
    end
  end

  if (sellPrice and sellPrice > 0) or (maxStack and maxStack > 1) then
    local parts = {}
    if sellPrice and sellPrice > 0 then parts[#parts + 1] = "Sell: " .. FormatMoneyText(sellPrice) end
    if maxStack and maxStack > 1 then parts[#parts + 1] = "Stack: " .. maxStack end
    tt:AddLine(table.concat(parts, "  ·  "), 0.72, 0.78, 0.85)
  end
  tt:Show()
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt == GameTooltip and data and data.id then
      AppendItemTooltip(tt, data.id)
    end
  end)
elseif GameTooltip and GameTooltip.HookScript then
  GameTooltip:HookScript("OnTooltipSetItem", function(tt)
    local _, link = tt:GetItem()
    if link then AppendItemTooltip(tt, link) end
  end)
end

---------------------------------------------------------------------------
-- 6. Settings UI (/epu qol)
---------------------------------------------------------------------------
local qolWin
function ns.OpenWorldQoLSettings()
  local K = ns.UIKit
  if not qolWin then
    local C = ns.InterfaceColors
    qolWin = ns.InterfaceWindow("EPUGuildWorldQoLConfig", UIParent, "EPU Travel, Vendor & Tooltips", 410, 360)
    qolWin:SetFrameStrata("DIALOG")
    qolWin.widgets = {}

    function qolWin:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local db = DB()
      local y = -44
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
      local function AddToggle(label, key, onChange)
        local b = Track(K.Btn(qolWin, Check(db[key], label), 370, 22))
        b:SetPoint("TOPLEFT", 18, y)
        b:SetScript("OnClick", function()
          db[key] = not db[key]
          if onChange then onChange(db[key]) end
          qolWin:Refresh()
        end)
        y = y - 28
      end

      AddToggle("World Map Player & Cursor Coordinates", "mapCoords", function()
        if coordFrame and WorldMapFrame then coordFrame:SetShown(db.mapCoords and WorldMapFrame:IsShown()) end
      end)
      AddToggle("Waypoints (/epu way x y [label] and /epu way clear)", "waypoints", function(on)
        if not on and wayFrame then wayFrame:Hide() end
      end)
      AddToggle("Flight Path Timer Bar (learns route times)", "flightTimer", function(on)
        if not on and flightFrame then flightFrame:Hide() end
      end)
      AddToggle("Auto-Sell Grey Junk at Vendors (hold Shift to skip)", "autoSellGrey")
      AddToggle("Auto-Repair Gear at Vendors (hold Shift to skip)", "autoRepair")
      AddToggle("Use Guild Bank Funds for Auto-Repair when allowed", "guildRepair", function() db.guildRepairChosen = true end)
      AddToggle("Item Tooltip Extras (Alt/Bank counts, Sell price, Stack)", "tooltipExtras")

      local note = Track(K.Font(qolWin, 11, C.muted))
      note:SetPoint("TOPLEFT", 18, y - 6)
      note:SetWidth(370)
      note:SetJustifyH("LEFT")
      note:SetText("Tip: Open your Bank once on each alt so EPU records their bank items for tooltip counts.")
    end
  end
  qolWin:Refresh()
  qolWin:Show()
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    SetupMapCoords()
    ScanCharacterItems(false)
  end)
  ns.On("BAG_UPDATE", function() ScanCharacterItems(false) end)
  ns.On("BANKFRAME_OPENED", function() ScanCharacterItems(true) end)
  ns.On("PLAYERBANKSLOTS_CHANGED", function() ScanCharacterItems(true) end)
  ns.On("MERCHANT_SHOW", OnMerchantShow)
end

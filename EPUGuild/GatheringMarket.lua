local ADDON, ns = ...

-- Herbalism skill thresholds for standard herbs. Unknown acquisition
-- requirements stay visible in the full catalog and out of the skill filter.
local herbs = {
  {2447,1}, {765,1}, {2449,15}, {785,50}, {2450,70}, {2452,50},
  {3820,85}, {2453,100}, {3355,115}, {3369,120}, {3356,125}, {3357,150},
  {3818,160}, {3821,170}, {3819,195}, {3358,185}, {4625,205},
  {8831,210}, {8153,210}, {8836,220}, {8838,230}, {8839,235}, {8845,245},
  {8846,250}, {13463,270}, {13464,260}, {13465,280}, {13466,285},
  {13467,290}, {13468,300}, {19726}, {248821}, {248822}, {248823},
}
local circle = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local sources = {
  { key = "ledger", title = "AHledger", hint = "Forever market · estimated units sold per day · hollow circles have no sell-through data" },
  { key = "tsm", title = "TSM", hint = "TSM regional averages · bubble area shows sell-through from 1% to 100%" },
  { key = "auctionator", title = "Auctionator", hint = "Last scanned listing prices · volume and sell-through unavailable" },
}

local function Readable(value)
  return not (issecretvalue and issecretvalue(value))
end

local function Number(value, minimum, maximum)
  if Readable(value) and type(value) == "number" and value >= minimum and value <= maximum then return value end
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, value = pcall(fn, ...)
  if ok and Readable(value) then return value end
end

local function AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function Available(source)
  if source == "ledger" then return AHledgerAPI and type(AHledgerAPI.GetPrice) == "function" end
  if source == "tsm" then return TSM_API and type(TSM_API.GetCustomPriceValue) == "function" end
  local api = AuctionatorAPI()
  return api and type(api.GetAuctionPriceByItemID) == "function"
end

local function Market(source, item, reagent)
  local price, volume, rate, market
  if source == "ledger" then
    local row = Call(AHledgerAPI and AHledgerAPI.GetPrice, item)
    if type(row) == "table" then
      if reagent then price = row.minBuyout else price = row.median end
      volume = row.soldPerDay
      if ns.IsReadableString(row.market) then market = row.market end
    end
  elseif source == "tsm" then
    local read = TSM_API and TSM_API.GetCustomPriceValue
    local key = "i:" .. item
    price = Call(read, reagent and "dbregionmarketavg" or "dbregionsaleavg", key)
    if not reagent then
      volume = Call(read, "dbregionsoldperday", key)
      rate = Call(read, "dbregionsalerate", key)
    end
  else
    local api = AuctionatorAPI()
    price = Call(api and api.GetAuctionPriceByItemID, ADDON, item)
  end
  return Number(price, 1, 1e12), Number(volume, 0, 1e9), Number(rate, 0, 1), market
end

local function Sort(rows)
  table.sort(rows, function(a,b)
    if a.score ~= b.score then return (a.score or -math.huge) > (b.score or -math.huge) end
    if a.price ~= b.price then return (a.price or 0) > (b.price or 0) end
    return a.name < b.name
  end)
  return rows
end

function ns.GatheringMarketRows(source, skill)
  local rows = {}
  for _, herb in ipairs(herbs) do
    local item, required = herb[1], herb[2]
    if skill == nil or (required and required <= skill) then
      local price, volume, rate, market = Market(source, item)
      local score
      if price and source == "tsm" and rate then score = price * rate end
      if price and source == "ledger" and volume then score = price * volume end
      rows[#rows + 1] = {
        item = item, name = ns.ItemName(item, true), skill = required, price = price,
        volume = volume, rate = rate, market = market, score = score,
      }
    end
  end
  return Sort(rows)
end

function ns.CraftingMarketRows(source, professions)
  local rows, costs = {}, {}
  for name, scan in pairs((ns.cdb and ns.cdb.recipes) or {}) do
    local skill = professions[name]
    if skill then
      for item, recipe in pairs(scan.market or {}) do
        if ns.IsBoP(item) == false then
          local price, volume, rate, market = Market(source, item)
          local cost = 0
          for i = 1, #recipe.reagents, 2 do
            local reagent, quantity = recipe.reagents[i], recipe.reagents[i + 1]
            if costs[reagent] == nil then costs[reagent] = Market(source, reagent, true) or false end
            local unit = costs[reagent]
            if not unit then cost = nil; break end
            cost = cost + unit * quantity
          end
          local revenue = price and price * recipe.quantity
          rows[#rows + 1] = {
            item = item, name = ns.ItemName(item, true), price = price, volume = volume, rate = rate, market = market,
            profession = name, skill = skill, quantity = recipe.quantity, cost = cost, revenue = revenue,
            score = revenue and cost and revenue - cost,
          }
        end
      end
    end
  end
  return Sort(rows)
end

local frame, activeSource, craftMode, skillOnly
local points, listRows = {}, {}
local WIDTH, HEIGHT = 431, 264

local function Gold(copper)
  if not copper then return "—" end
  return string.format("%.3g g", copper / 10000)
end

local function Label(parent, text, font)
  local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  label:SetText(text)
  return label
end

local function Tooltip(button)
  local row = button.row
  if not row then return end
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.name)
  GameTooltip:AddLine("Price per item: " .. Gold(row.price), 1, 1, 1)
  GameTooltip:AddLine("Units sold/day: " .. (row.volume and string.format("%.3g", row.volume) or "Unavailable"), 1, 1, 1)
  GameTooltip:AddLine("Sell-through: " .. (row.rate and string.format("%.1f%%", row.rate * 100) or "Unavailable"), 1, 1, 1)
  if row.market then GameTooltip:AddLine(row.market) end
  if row.profession then
    GameTooltip:AddLine(row.profession .. " " .. row.skill .. " · makes " .. row.quantity)
    GameTooltip:AddLine("Reagents: " .. Gold(row.cost) .. " · output: " .. Gold(row.revenue))
    GameTooltip:AddLine("Margin before AH fees: " .. Gold(row.score))
  else
    GameTooltip:AddLine(row.skill and ("Herbalism required: " .. row.skill) or "Gathering requirements unverified")
  end
  GameTooltip:Show()
end

local function HoverButton(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetScript("OnEnter", Tooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return button
end

local function Plot(rows)
  local maxVolume, maxPrice, shown = 1, 1, 0
  for _, row in ipairs(rows) do
    if row.volume and row.price then
      maxVolume = math.max(maxVolume, row.volume)
      maxPrice = math.max(maxPrice, row.price)
    end
  end
  for _, row in ipairs(rows) do
    if row.volume and row.price then
      shown = shown + 1
      local point = points[shown]
      if not point then
        point = HoverButton(frame.chart)
        point.dot = point:CreateTexture(nil, "ARTWORK")
        point.dot:SetAllPoints()
        point.dot:SetTexture(circle)
        point.hole = point:CreateTexture(nil, "OVERLAY")
        point.hole:SetPoint("CENTER")
        point.hole:SetTexture(circle)
        point.hole:SetVertexColor(0.08, 0.09, 0.12)
        points[shown] = point
      end
      local size = row.rate and math.max(5, 30 * math.sqrt(row.rate)) or 10
      point.row = row
      point:SetSize(size, size)
      point.hole:SetSize(size - 4, size - 4)
      point.hole:SetShown(not row.rate)
      point.dot:SetVertexColor(0.26, 0.86, 0.65, 0.85)
      point:ClearAllPoints()
      point:SetPoint("CENTER", frame.chart, "BOTTOMLEFT", 16 + row.volume / maxVolume * (WIDTH - 32), 16 + row.price / maxPrice * (HEIGHT - 32))
      point:Show()
    end
  end
  for i = shown + 1, #points do points[i]:Hide() end
  for i = 0, 4 do
    frame.xLabels[i]:SetText(shown > 0 and string.format("%.3g", maxVolume * i / 4) or "")
    frame.yLabels[i]:SetText(shown > 0 and Gold(maxPrice * i / 4) or "")
  end
  frame.chartEmpty:SetShown(shown == 0)
  return shown
end

local function Refresh()
  local player = ns.GuidePlayer()
  local herb = player.professions[182]
  local skill = herb and herb.rank or 0
  local professions = {}
  for _, prof in pairs(player.professions) do professions[prof.name] = prof.rank end
  frame.skill:SetText("My skill: " .. (skillOnly and "On" or "Off"))
  frame.skill:SetShown(not craftMode)
  frame.herbGuide:SetShown(not craftMode)
  frame.routeButton:SetShown(not craftMode)
  frame.chart:SetShown(not craftMode)
  local rows = craftMode and ns.CraftingMarketRows(activeSource.key, professions)
    or ns.GatheringMarketRows(activeSource.key, skillOnly and skill or nil)
  local shown = not craftMode and Plot(rows)
  local label = craftMode and "Margin per craft before fees"
    or (activeSource.key == "tsm" and "Price × sell-through per item")
    or (activeSource.key == "ledger" and "Estimated market gold/day") or "Listing price per item"
  frame.context:SetText(craftMode and "Margin per craft before fees · Open a profession window to refresh its learned recipes."
    or string.format("Level %s · Herbalism %d · %d/%d plotted · %s", player.level or "?", skill, shown, #rows, label))
  frame.sourceText:SetText(Available(activeSource.key) and activeSource.hint
    or ("Load " .. activeSource.title .. " with current market data, then press Refresh."))
  frame.credit:SetShown(activeSource.key == "ledger")
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", craftMode and 20 or 537, -104)
  frame.scroll:SetPoint("BOTTOMRIGHT", -32, 46)
  frame.list:SetSize(craftMode and 722 or 207, math.max(28, #rows * 30))
  frame.scroll:SetVerticalScroll(0)
  for i, row in ipairs(rows) do
    local button = listRows[i]
    if not button then
      button = HoverButton(frame.list)
      button:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
      button:SetPoint("TOPRIGHT", 0, -(i - 1) * 30)
      button:SetHeight(29)
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button.name = Label(button, "")
      button.name:SetPoint("TOPLEFT", 3, -1)
      button.summary = Label(button, "", "GameFontDisableSmall")
      button.summary:SetPoint("TOPLEFT", 3, -15)
      listRows[i] = button
    end
    button.row = row
    button.name:SetText(row.name)
    local summary = craftMode and (row.profession .. " " .. row.skill .. " · margin " .. Gold(row.score))
      or (Gold(row.price) .. " · " .. (row.volume and string.format("%.3g/day", row.volume) or "—/day"))
    button.summary:SetText(summary)
    button:Show()
  end
  for i = #rows + 1, #listRows do listRows[i]:Hide() end
  frame.empty:SetShown(#rows == 0)
  frame.empty:SetText(craftMode and "No eligible recipes yet. Open a learned profession to scan its recipes." or "No catalog herbs match your Herbalism skill.")
end

local function Create()
  frame = CreateFrame("Frame", "EPUGuildGatheringMarket", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(780, 500)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame.TitleText:SetText("Gathering market · Herbalism pilot")
  tinsert(UISpecialFrames, "EPUGuildGatheringMarket")
  local function Button(text, width, x, y, callback)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, 23)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
  end
  Button("Herbs", 69, 17, -29, function() craftMode = false; Refresh() end)
  Button("My crafts", 88, 90, -29, function() craftMode = true; Refresh() end)
  frame.skill = Button("My skill: Off", 103, 183, -29, function() skillOnly = not skillOnly; Refresh() end)
  for i, source in ipairs(sources) do
    Button(source.title, 91, 300 + (i - 1) * 94, -29, function() activeSource = source; Refresh() end)
  end
  Button("Refresh", 79, 594, -29, Refresh)
  frame.herbGuide = Button("Herb guides", 86, 676, -29, function()
    frame:Hide()
    ns.OpenMemberTools("guides")
    if ns.GuideChoice("profession:182") then ns.UI:OpenDetails("guidechoice", "profession:182") end
  end)
  frame.routeButton = Button("Start herb route", 120, 78, -439, function()
    ns.GatheringRouteCommand("start")
  end)
  frame.context = Label(frame, "")
  frame.context:SetPoint("TOPLEFT", 19, -60)
  frame.sourceText = Label(frame, "", "GameFontDisableSmall")
  frame.sourceText:SetPoint("TOPLEFT", 19, -78)
  frame.chart = CreateFrame("Frame", nil, frame)
  frame.chart:SetSize(WIDTH, HEIGHT)
  frame.chart:SetPoint("TOPLEFT", 78, -132)
  local bg = frame.chart:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.09, 0.12, 1)
  frame.xLabels, frame.yLabels = {}, {}
  for i = 0, 4 do
    local x, y = 16 + i * (WIDTH - 32) / 4, 16 + i * (HEIGHT - 32) / 4
    local vertical, horizontal = frame.chart:CreateTexture(nil, "BORDER"), frame.chart:CreateTexture(nil, "BORDER")
    vertical:SetColorTexture(0.3, 0.34, 0.4, 0.6)
    horizontal:SetColorTexture(0.3, 0.34, 0.4, 0.6)
    vertical:SetPoint("BOTTOMLEFT", x, 16); vertical:SetSize(1, HEIGHT - 32)
    horizontal:SetPoint("BOTTOMLEFT", 16, y); horizontal:SetSize(WIDTH - 32, 1)
    frame.xLabels[i] = Label(frame.chart, "")
    frame.xLabels[i]:SetPoint("TOP", frame.chart, "BOTTOMLEFT", x, -4)
    frame.yLabels[i] = Label(frame.chart, "")
    frame.yLabels[i]:SetPoint("RIGHT", frame.chart, "BOTTOMLEFT", -6, y)
  end
  Label(frame.chart, "Gold per item"):SetPoint("BOTTOMLEFT", frame.chart, "TOPLEFT", 0, 6)
  Label(frame.chart, "Units sold per day"):SetPoint("TOP", frame.chart, "BOTTOM", 0, -20)
  frame.chartEmpty = Label(frame.chart, "A chart needs both price and daily sales data.")
  frame.chartEmpty:SetPoint("CENTER")
  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.list = CreateFrame("Frame", nil, frame.scroll)
  frame.scroll:SetScrollChild(frame.list)
  frame.empty = Label(frame, "")
  frame.empty:SetPoint("TOPLEFT", 20, -111)
  frame.credit = Label(frame, "AHledger data · ahledger.com", "GameFontDisableSmall")
  frame.credit:SetPoint("BOTTOMLEFT", 20, 15)
  Label(frame, "Market estimates. Gathering speed, route difficulty and auction fees affect your actual gold/hour.", "GameFontDisableSmall"):SetPoint("BOTTOMRIGHT", -20, 15)
end

function ns.ShowGatheringMarket()
  if not frame then Create() end
  if not activeSource then
    for _, source in ipairs(sources) do
      if Available(source.key) then activeSource = source; break end
    end
    activeSource = activeSource or sources[1]
  end
  frame:Show()
  Refresh()
end

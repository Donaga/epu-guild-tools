-- EPU Guild Tools: Personal gold tracking, spending categories, and budgeting.
local _, ns = ...

local CATEGORIES = {
  { id = "loot", label = "Loot & Quests", color = "|cff4ade80" },
  { id = "vendor", label = "Vendor / Junk", color = "|cffffd100" },
  { id = "repair", label = "Repairs", color = "|cffff6b6b" },
  { id = "auction", label = "Auction House", color = "|cff4fc3f7" },
  { id = "mail", label = "Mail / COD", color = "|cffc77dff" },
  { id = "training", label = "Training & Riding", color = "|cffff9e64" },
  { id = "flight", label = "Flight Paths", color = "|cff70b8ff" },
  { id = "trade", label = "Player Trade", color = "|cfff2c14e" },
  { id = "guildbank", label = "Guild Bank", color = "|cff8a9cff" },
  { id = "other", label = "Other", color = "|cffaaaaaa" },
}
local CAT_MAP = {}
for _, c in ipairs(CATEGORIES) do CAT_MAP[c.id] = c end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function FormatMoney(copper, colored)
  local neg = (copper or 0) < 0
  copper = math.floor(math.abs(copper or 0))
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local gStr = tostring(g):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  local prefix = neg and "-" or ""
  if colored then
    if g > 0 then return string.format("%s|cffffffff%s|r|cffffd100g|r |cffffffff%d|r|cffc7c7cfs|r", prefix, gStr, s) end
    if s > 0 then return string.format("%s|cffffffff%d|r|cffc7c7cfs|r |cffffffff%d|r|cffeda55fc|r", prefix, s, c) end
    return string.format("%s|cffffffff%d|r|cffeda55fc|r", prefix, c)
  end
  if g > 0 then return string.format("%s%sg %ds", prefix, gStr, s) end
  if s > 0 then return string.format("%s%ds %dc", prefix, s, c) end
  return string.format("%s%dc", prefix, c)
end

local function DB()
  if not ns.db then return {} end
  ns.db.goldTracker = ns.db.goldTracker or {}
  local db = ns.db.goldTracker
  db.entries = db.entries or {}
  db.budgets = db.budgets or {}
  if db.budgets.enabled == nil then db.budgets.enabled = false end
  if db.budgets.dailyGold == nil then db.budgets.dailyGold = 50 end
  if db.budgets.weeklyGold == nil then db.budgets.weeklyGold = 250 end
  if db.budgets.warnChat == nil then db.budgets.warnChat = true end
  return db
end

local sessionStart = time()
local lastMoney = nil
local openState = {}
local pendingCat = nil
local pendingUntil = 0
local warnedDay, warnedWeek

local function SetPending(cat, secs)
  pendingCat = cat
  pendingUntil = GetTime() + (secs or 2)
end

local function DetectCategory()
  if pendingCat and GetTime() <= pendingUntil then
    local c = pendingCat
    pendingCat = nil
    return c
  end
  if openState.auction then return "auction" end
  if openState.mail then return "mail" end
  if openState.trainer then return "training" end
  if openState.merchant then return "vendor" end
  if openState.trade then return "trade" end
  if openState.guildbank then return "guildbank" end
  if UnitOnTaxi and UnitOnTaxi("player") then return "flight" end
  return "other"
end

local function TodayStart()
  local d = date("*t")
  d.hour, d.min, d.sec = 0, 0, 0
  return time(d)
end

function ns.GetGoldSummary(sinceTime, charOnly)
  local db = DB()
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  local byCat = {}
  local income, expense = 0, 0
  local list = {}
  for _, c in ipairs(CATEGORIES) do byCat[c.id] = { inc = 0, exp = 0 } end
  for i = #db.entries, 1, -1 do
    local e = db.entries[i]
    if (e.t or 0) < (sinceTime or 0) then break end
    if (not e.realm or e.realm == realm) and (not charOnly or e.who == ns.me) then
      local bucket = byCat[e.cat] or byCat.other
      if (e.delta or 0) >= 0 then
        income = income + e.delta
        bucket.inc = bucket.inc + e.delta
      else
        local absD = -e.delta
        expense = expense + absD
        bucket.exp = bucket.exp + absD
      end
      list[#list + 1] = e
    end
  end
  return {
    income = income,
    expense = expense,
    net = income - expense,
    byCat = byCat,
    entries = list,
  }
end

function ns.GetGoldBudgetStatus()
  local b = DB().budgets
  if not b or not b.enabled then return nil end
  local daySum = ns.GetGoldSummary(TodayStart(), false)
  local weekSum = ns.GetGoldSummary(time() - 7 * 86400, false)
  return {
    dailySpent = daySum.expense,
    dailyLimit = (b.dailyGold or 50) * 10000,
    weeklySpent = weekSum.expense,
    weeklyLimit = (b.weeklyGold or 250) * 10000,
  }
end

local win
local timeframe = "today"
local scopeAll = true

local function CheckBudgetAlerts()
  local b = DB().budgets
  if not b or not b.enabled or not b.warnChat then return end
  local st = ns.GetGoldBudgetStatus()
  if not st then return end
  local dayKey = date("%Y-%m-%d")
  if st.dailyLimit > 0 and st.dailySpent >= st.dailyLimit and warnedDay ~= dayKey then
    warnedDay = dayKey
    ns.Print(string.format("|cffff6b6bDaily budget reached:|r spent %s of %s today.", FormatMoney(st.dailySpent), FormatMoney(st.dailyLimit)))
  end
  local weekKey = date("%Y-W%W")
  if st.weeklyLimit > 0 and st.weeklySpent >= st.weeklyLimit and warnedWeek ~= weekKey then
    warnedWeek = weekKey
    ns.Print(string.format("|cffff6b6bWeekly budget reached:|r spent %s of %s this week.", FormatMoney(st.weeklySpent), FormatMoney(st.weeklyLimit)))
  end
end

local function RecordDelta(delta, cat)
  if not delta or delta == 0 then return end
  local db = DB()
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  local _, cf = UnitClass and UnitClass("player")
  db.entries[#db.entries + 1] = {
    t = time(),
    who = ns.me or "Player",
    cf = cf,
    realm = realm,
    delta = delta,
    cat = CAT_MAP[cat] and cat or "other",
  }
  while #db.entries > 2000 do table.remove(db.entries, 1) end
  CheckBudgetAlerts()
  if win and win:IsShown() and win.Refresh then win:Refresh() end
end

function ns.OpenGoldTracker()
  local K = ns.UIKit
  if not win then
    local C = ns.InterfaceColors
    win = ns.InterfaceWindow("EPUGuildGoldTracker", UIParent, "EPU Gold & Budget Tracker", 520, 520)
    win:SetFrameStrata("DIALOG")
    win.widgets = {}

    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(490); child:SetHeight(440)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    win.scroll, win.child = scroll, child

    function win:Refresh()
      for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
      self.widgets = {}
      local db = DB()
      local b = db.budgets
      local y = -4
      local function Track(w) self.widgets[#self.widgets + 1] = w; return w end
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local btn = Track(K.Btn(child, it[1], it[2], 22, it[4]))
          btn:SetPoint("TOPLEFT", x, y)
          btn:SetScript("OnClick", function() it[3](); win:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = Track(K.Font(child, 12, C.gold or C.white))
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 22
      end

      Row({
        { "Session", 72, function() timeframe = "session" end, timeframe == "session" and "accent" or nil },
        { "Today", 68, function() timeframe = "today" end, timeframe == "today" and "accent" or nil },
        { "7 Days", 72, function() timeframe = "week" end, timeframe == "week" and "accent" or nil },
        { "30 Days", 76, function() timeframe = "month" end, timeframe == "month" and "accent" or nil },
        { "All", 54, function() timeframe = "all" end, timeframe == "all" and "accent" or nil },
        { scopeAll and "All Alts" or "This Char", 92, function() scopeAll = not scopeAll end },
      })

      local since = 0
      if timeframe == "session" then since = sessionStart
      elseif timeframe == "today" then since = TodayStart()
      elseif timeframe == "week" then since = time() - 7 * 86400
      elseif timeframe == "month" then since = time() - 30 * 86400 end

      local sum = ns.GetGoldSummary(since, not scopeAll)
      local netCol = sum.net >= 0 and "|cff4ade80+" or "|cffff6b6b"
      local sumText = Track(K.Font(child, 12, C.white))
      sumText:SetPoint("TOPLEFT", 0, y)
      sumText:SetText(string.format("Income: |cff4ade80%s|r    Spent: |cffff6b6b%s|r    Net: %s%s|r",
        FormatMoney(sum.income), FormatMoney(sum.expense), netCol, FormatMoney(sum.net)))
      y = y - 24

      Heading("Spending Budget")
      Row({
        { (b.enabled and "[x] " or "[ ] ") .. "Enable Budget", 130, function() b.enabled = not b.enabled end },
        { (b.warnChat and "[x] " or "[ ] ") .. "Chat Alert", 110, function() b.warnChat = not b.warnChat end },
        { "Clear History", 104, function() db.entries = {} end },
      })
      if b.enabled then
        Row({
          { "Daily: " .. (b.dailyGold or 50) .. "g", 96, function() end },
          { "-10g", 48, function() b.dailyGold = math.max(10, (b.dailyGold or 50) - 10) end },
          { "+10g", 48, function() b.dailyGold = (b.dailyGold or 50) + 10 end },
          { "Weekly: " .. (b.weeklyGold or 250) .. "g", 110, function() end },
          { "-50g", 48, function() b.weeklyGold = math.max(25, (b.weeklyGold or 250) - 50) end },
          { "+50g", 48, function() b.weeklyGold = (b.weeklyGold or 250) + 50 end },
        })
        local st = ns.GetGoldBudgetStatus()
        if st then
          local dPct = st.dailyLimit > 0 and math.floor((st.dailySpent / st.dailyLimit) * 100 + 0.5) or 0
          local wPct = st.weeklyLimit > 0 and math.floor((st.weeklySpent / st.weeklyLimit) * 100 + 0.5) or 0
          local dCol = dPct >= 100 and "|cffff6b6b" or (dPct >= 80 and "|cffffd100" or "|cff4ade80")
          local wCol = wPct >= 100 and "|cffff6b6b" or (wPct >= 80 and "|cffffd100" or "|cff4ade80")
          local bLine = Track(K.Font(child, 11, C.text))
          bLine:SetPoint("TOPLEFT", 0, y)
          bLine:SetText(string.format("Today: %s%s|r / %s (%d%%)    7-Day: %s%s|r / %s (%d%%)",
            dCol, FormatMoney(st.dailySpent), FormatMoney(st.dailyLimit), dPct,
            wCol, FormatMoney(st.weeklySpent), FormatMoney(st.weeklyLimit), wPct))
          y = y - 22
        end
      end

      Heading("Breakdown by Category")
      for _, cat in ipairs(CATEGORIES) do
        local bucket = sum.byCat[cat.id]
        if bucket and (bucket.inc > 0 or bucket.exp > 0) then
          local line = Track(K.Font(child, 11, C.text))
          line:SetPoint("TOPLEFT", 4, y)
          local parts = {}
          if bucket.inc > 0 then parts[#parts + 1] = "|cff4ade80+" .. FormatMoney(bucket.inc) .. "|r" end
          if bucket.exp > 0 then parts[#parts + 1] = "|cffff6b6b-" .. FormatMoney(bucket.exp) .. "|r" end
          line:SetText(string.format("%s%s|r:  %s", cat.color, cat.label, table.concat(parts, "   ")))
          y = y - 18
        end
      end

      Heading("Recent Transactions (" .. math.min(25, #sum.entries) .. " of " .. #sum.entries .. ")")
      if #sum.entries == 0 then
        local empty = Track(K.Font(child, 11, C.muted))
        empty:SetPoint("TOPLEFT", 4, y)
        empty:SetText("No gold transactions recorded in this timeframe yet.")
        y = y - 20
      else
        for i = 1, math.min(25, #sum.entries) do
          local e = sum.entries[i]
          local cat = CAT_MAP[e.cat] or CAT_MAP.other
          local dCol = e.delta >= 0 and "|cff4ade80+" or "|cffff6b6b"
          local short = ns.Short and ns.Short(e.who or "?") or (e.who or "?")
          local rowText = Track(K.Font(child, 11, C.text))
          rowText:SetPoint("TOPLEFT", 4, y)
          rowText:SetText(string.format("|cff888888%s|r  %s  %s%s|r  %s%s|r",
            date("%m/%d %H:%M", e.t or 0), short, cat.color, cat.label, dCol, FormatMoney(e.delta)))
          y = y - 18
        end
      end
      child:SetHeight(math.max(440, -y + 20))
    end
  end
  win:Refresh()
  win:Show()
end

if hooksecurefunc then
  if RepairAllItems then hooksecurefunc("RepairAllItems", function() SetPending("repair", 3) end) end
  if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function() SetPending("flight", 4) end) end
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    lastMoney = GetMoney and SafeNum(GetMoney()) or 0
  end)
  ns.On("PLAYER_MONEY", function()
    local cur = GetMoney and SafeNum(GetMoney())
    if not cur then return end
    if lastMoney ~= nil and cur ~= lastMoney then
      RecordDelta(cur - lastMoney, DetectCategory())
    end
    lastMoney = cur
  end)
  ns.On("MERCHANT_SHOW", function() openState.merchant = true end)
  ns.On("MERCHANT_CLOSED", function() openState.merchant = false end)
  ns.On("AUCTION_HOUSE_SHOW", function() openState.auction = true end)
  ns.On("AUCTION_HOUSE_CLOSED", function() openState.auction = false end)
  ns.On("MAIL_SHOW", function() openState.mail = true end)
  ns.On("MAIL_CLOSED", function() openState.mail = false end)
  ns.On("TRAINER_SHOW", function() openState.trainer = true end)
  ns.On("TRAINER_CLOSED", function() openState.trainer = false end)
  ns.On("TRADE_SHOW", function() openState.trade = true end)
  ns.On("TRADE_CLOSED", function() openState.trade = false end)
  ns.On("GUILDBANKFRAME_OPENED", function() openState.guildbank = true end)
  ns.On("GUILDBANKFRAME_CLOSED", function() openState.guildbank = false end)
  ns.On("QUEST_TURNED_IN", function() SetPending("loot", 3) end)
  ns.On("CHAT_MSG_MONEY", function() SetPending("loot", 2) end)
end

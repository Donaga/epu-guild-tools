-- EPU Guild Tools: Personal gold tracking, spending categories, and budgeting.
local _, ns = ...

local CATEGORIES = {
  { id = "loot", label = "Loot & Quests", color = "|cff4ade80", rgb = { 0.29, 0.87, 0.50 } },
  { id = "vendor", label = "Vendor / Junk", color = "|cffffd100", rgb = { 1.00, 0.82, 0.00 } },
  { id = "repair", label = "Repairs", color = "|cffff6b6b", rgb = { 1.00, 0.42, 0.42 } },
  { id = "auction", label = "Auction House", color = "|cff4fc3f7", rgb = { 0.31, 0.76, 0.97 } },
  { id = "mail", label = "Mail / COD", color = "|cffc77dff", rgb = { 0.78, 0.49, 1.00 } },
  { id = "training", label = "Training & Riding", color = "|cffff9e64", rgb = { 1.00, 0.62, 0.39 } },
  { id = "flight", label = "Flight Paths", color = "|cff70b8ff", rgb = { 0.44, 0.72, 1.00 } },
  { id = "trade", label = "Player Trade", color = "|cfff2c14e", rgb = { 0.95, 0.76, 0.31 } },
  -- Transfers: gold moved between your own characters, or into and out of the
  -- guild bank. It isn't earned or spent, so it stays out of income, spending
  -- and the budget, and is shown on its own line instead.
  { id = "guildbank", label = "Guild Bank", color = "|cff8a9cff", rgb = { 0.54, 0.61, 1.00 }, transfer = true },
  { id = "alts", label = "Your Other Characters", color = "|cff7fd4c1", rgb = { 0.50, 0.83, 0.76 }, transfer = true },
  { id = "other", label = "Other", color = "|cffaaaaaa", rgb = { 0.67, 0.67, 0.67 } },
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

local pendingSign, pendingAmount
local function SetPending(cat, secs, sign, amount)
  pendingCat = cat
  pendingUntil = GetTime() + (secs or 2)
  pendingSign, pendingAmount = sign, amount
end

function ns.IsGoldTransfer(cat)
  local c = CAT_MAP[cat]
  return c ~= nil and c.transfer == true
end

-- Is this one of your own characters? SavedVariables are shared by the whole
-- account, so EPU knows every character that has logged in with it. Mail
-- may name just the first name; that counts if only one of yours has it.
local function MyCharacters()
  local mine = {}
  local function Add(n) n = ns.Short and ns.Short(n) or n; if type(n) == "string" and n ~= "" then mine[n:lower()] = n end end
  Add(ns.me)
  local adb = ns.db or {}
  for _, chars in pairs(adb.accountChars or {}) do
    if type(chars) == "table" then for n in pairs(chars) do Add(n) end end
  end
  for _, chars in pairs((adb.infoBars and adb.infoBars.altGold) or {}) do
    if type(chars) == "table" then for n in pairs(chars) do Add(n) end end
  end
  for _, e in ipairs((adb.goldTracker and adb.goldTracker.entries) or {}) do Add(e.who) end
  return mine
end

function ns.IsMyCharacter(name)
  name = SafeStr(name)
  if not name then return false end
  name = (ns.Short and ns.Short(name)) or name
  if not name then return false end
  local mine, lower = MyCharacters(), name:lower()
  if mine[lower] then return true end
  if lower:find(" ", 1, true) then return false end
  local hits = 0
  for l in pairs(mine) do if l:match("^(%S+)") == lower then hits = hits + 1 end end
  return hits == 1
end

-- Repairs and flights only cost gold; loot only brings it in. A pending label
-- waits for a change of its own sign, so grey items sold at the same vendor
-- visit as a repair stay "vendor" and the repair still gets its label.
local SPEND_ONLY = { repair = true, flight = true }
local function DetectCategory(delta)
  if pendingCat and GetTime() <= pendingUntil then
    local spend = SPEND_ONLY[pendingCat]
    if pendingSign then spend = pendingSign < 0 end
    if (spend and delta < 0) or (not spend and delta > 0) then
      local c, amount = pendingCat, pendingAmount
      pendingCat, pendingSign, pendingAmount = nil, nil, nil
      return c, amount
    end
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
  local income, expense, moveIn, moveOut = 0, 0, 0, 0
  local list = {}
  for _, c in ipairs(CATEGORIES) do byCat[c.id] = { inc = 0, exp = 0 } end
  for i = #db.entries, 1, -1 do
    local e = db.entries[i]
    if (e.t or 0) < (sinceTime or 0) then break end
    if (not e.realm or e.realm == realm) and (not charOnly or e.who == ns.me) then
      local bucket = byCat[e.cat] or byCat.other
      local transfer = ns.IsGoldTransfer(e.cat)
      if (e.delta or 0) >= 0 then
        if transfer then moveIn = moveIn + e.delta else income = income + e.delta end
        bucket.inc = bucket.inc + e.delta
      else
        local absD = -e.delta
        if transfer then moveOut = moveOut + absD else expense = expense + absD end
        bucket.exp = bucket.exp + absD
      end
      list[#list + 1] = e
    end
  end
  return {
    income = income,
    expense = expense,
    net = income - expense,
    transferIn = moveIn,     -- from your other characters and the guild bank
    transferOut = moveOut,   -- to your other characters and the guild bank
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
local graphMode = "both"

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

local function AddEntry(db, delta, cat)
  local realm = (GetRealmName and SafeStr(GetRealmName())) or "Realm"
  local cf
  if UnitClass then cf = select(2, UnitClass("player")) end
  db.entries[#db.entries + 1] = {
    t = time(),
    who = ns.me or "Player",
    cf = cf,
    realm = realm,
    delta = delta,
    cat = CAT_MAP[cat] and cat or "other",
  }
end

-- amount: the part of a loss that was a transfer (gold mailed to an alt); the
-- rest of it (postage) is mail spending.
local function RecordDelta(delta, cat, amount)
  if not delta or delta == 0 then return end
  local db = DB()
  if amount and amount > 0 and delta < 0 and -delta > amount then
    AddEntry(db, -amount, cat)
    AddEntry(db, delta + amount, "mail")
  else
    AddEntry(db, delta, cat)
  end
  while #db.entries > 2000 do table.remove(db.entries, 1) end
  CheckBudgetAlerts()
  if win and win:IsShown() and win.Refresh then win:Refresh() end
end

function ns.OpenGoldTracker()
  if not win then
    local C = ns.InterfaceColors
    win = ns.InterfaceWindow("EPUGuildGoldTracker", UIParent, "EPU Gold & Budget Tracker", 520, 520)
    win:SetFrameStrata("DIALOG")

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
    win.pool = ns.NewWidgetPool(child)

    function win:Refresh()
      local pool = self.pool
      pool:ReleaseAll()
      local db = DB()
      local b = db.budgets
      local y = -4
      local function Row(items)
        local x = 0
        for _, it in ipairs(items) do
          local btn = pool:Button(it[1], it[2], 22, it[4])
          btn:SetPoint("TOPLEFT", x, y)
          btn:SetScript("OnClick", function() it[3](); win:Refresh() end)
          x = x + it[2] + 6
        end
        y = y - 28
      end
      local function Heading(t)
        local h = pool:Font(12, C.gold or C.white)
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 22
      end

      Row({
        { "Session", 64, function() timeframe = "session" end, timeframe == "session" and "accent" or nil },
        { "Today", 58, function() timeframe = "today" end, timeframe == "today" and "accent" or nil },
        { "7 Days", 62, function() timeframe = "week" end, timeframe == "week" and "accent" or nil },
        { "30 Days", 66, function() timeframe = "month" end, timeframe == "month" and "accent" or nil },
        { "All", 44, function() timeframe = "all" end, timeframe == "all" and "accent" or nil },
        { scopeAll and "All Alts" or "This Char", 82, function() scopeAll = not scopeAll end },
        { "Graph: " .. graphMode, 84, function()
          local modes = { "both", "bar", "pie", "off" }
          local idx = 1
          for i, m in ipairs(modes) do if m == graphMode then idx = i; break end end
          graphMode = modes[(idx % #modes) + 1]
        end },
      })

      local since = 0
      if timeframe == "session" then since = sessionStart
      elseif timeframe == "today" then since = TodayStart()
      elseif timeframe == "week" then since = time() - 7 * 86400
      elseif timeframe == "month" then since = time() - 30 * 86400 end

      local sum = ns.GetGoldSummary(since, not scopeAll)
      local netCol = sum.net >= 0 and "|cff4ade80+" or "|cffff6b6b"
      local sumText = pool:Font(12, C.white)
      sumText:SetPoint("TOPLEFT", 0, y)
      sumText:SetText(string.format("Income: |cff4ade80%s|r    Spent: |cffff6b6b%s|r    Net: %s%s|r",
        FormatMoney(sum.income), FormatMoney(sum.expense), netCol, FormatMoney(sum.net)))
      y = y - 24
      if sum.transferIn > 0 or sum.transferOut > 0 then
        local moved = pool:Font(11, C.muted, "moved")
        moved:SetPoint("TOPLEFT", 0, y + 4)
        moved:SetText(string.format("Moved, not earned or spent: |cff4ade80+%s|r in, |cffff6b6b-%s|r out (your alts and the guild bank)",
          FormatMoney(sum.transferIn), FormatMoney(sum.transferOut)))
        y = y - 18
      end

      -- Pie / Donut Chart (Spending by Category)
      if (graphMode == "both" or graphMode == "pie") and sum.expense > 0 then
        local slices = {}
        for _, cat in ipairs(CATEGORIES) do
          local bucket = sum.byCat[cat.id]
          if bucket and bucket.exp > 0 and not cat.transfer then
            slices[#slices + 1] = { cat = cat, val = bucket.exp, pct = (bucket.exp / sum.expense) }
          end
        end
        table.sort(slices, function(a, b) return a.val > b.val end)
        if #slices > 0 then
          Heading("Spending Pie Chart")
          local pieBox, piePool = pool:Frame("pie")
          local pieH = math.max(126, #slices * 18 + 12)
          pieBox:SetSize(480, pieH)
          pieBox:SetPoint("TOPLEFT", 0, y)

          local cx, cy, radius = 64, -math.floor(pieH / 2), 42
          local SEGS = 90
          local segIdx = 1
          for _, sl in ipairs(slices) do
            local count = math.max(1, math.floor(sl.pct * SEGS + 0.5))
            local rgb = sl.cat.rgb or { 0.7, 0.7, 0.7 }
            for _ = 1, count do
              if segIdx <= SEGS then
                local angle = ((segIdx - 1) / SEGS) * math.pi * 2
                local tex = piePool:Texture("ARTWORK", "segment")
                tex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
                tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 0.95)
                tex:SetSize(5, 18)
                local px = cx + math.cos(angle) * radius
                local py = cy + math.sin(angle) * radius
                tex:SetPoint("CENTER", pieBox, "TOPLEFT", px, py)
                if tex.SetRotation then tex:SetRotation(angle + math.pi / 2) end
                segIdx = segIdx + 1
              end
            end
          end

          local centerLbl = piePool:Font(11, C.white, "center")
          centerLbl:SetPoint("CENTER", pieBox, "TOPLEFT", cx, cy)
          centerLbl:SetText(FormatMoney(sum.expense))

          local ly = -6
          for _, sl in ipairs(slices) do
            local swatch = piePool:Texture("ARTWORK", "swatch")
            swatch:SetColorTexture(sl.cat.rgb[1], sl.cat.rgb[2], sl.cat.rgb[3], 1)
            swatch:SetSize(10, 10)
            swatch:SetPoint("TOPLEFT", 142, ly - 2)
            local lbl = piePool:Font(11, C.text)
            lbl:SetPoint("TOPLEFT", 158, ly)
            lbl:SetText(string.format("%s%s|r: %s (%.0f%%)", sl.cat.color, sl.cat.label, FormatMoney(sl.val), sl.pct * 100))
            ly = ly - 18
          end
          y = y - pieH - 6
        end
      end

      -- Bar Graph (Category Spending + 7-Day Income vs Expense)
      if graphMode == "both" or graphMode == "bar" then
        local bars = {}
        local maxBar = 1
        for _, cat in ipairs(CATEGORIES) do
          local bucket = sum.byCat[cat.id]
          if bucket and bucket.exp > 0 and not cat.transfer then
            bars[#bars + 1] = { cat = cat, val = bucket.exp }
            if bucket.exp > maxBar then maxBar = bucket.exp end
          end
        end
        table.sort(bars, function(a, b) return a.val > b.val end)
        if #bars > 0 then
          Heading("Spending Bar Graph")
          local barBox, barPool = pool:Frame("bars")
          local bh = #bars * 20 + 6
          barBox:SetSize(480, bh)
          barBox:SetPoint("TOPLEFT", 0, y)
          local by = -2
          for _, br in ipairs(bars) do
            local lbl = barPool:Font(11, C.text)
            lbl:SetPoint("TOPLEFT", 0, by)
            lbl:SetText(br.cat.color .. br.cat.label .. "|r")

            local bgBar = barPool:Texture("BACKGROUND")
            bgBar:SetColorTexture(0.14, 0.16, 0.20, 0.9)
            bgBar:SetSize(220, 12)
            bgBar:SetPoint("TOPLEFT", 130, by - 1)

            local fillW = math.max(3, math.floor((br.val / maxBar) * 220))
            local fill = barPool:Texture("ARTWORK")
            fill:SetColorTexture(br.cat.rgb[1], br.cat.rgb[2], br.cat.rgb[3], 0.95)
            fill:SetSize(fillW, 12)
            fill:SetPoint("TOPLEFT", 130, by - 1)

            local valLbl = barPool:Font(11, C.white)
            valLbl:SetPoint("TOPLEFT", 358, by)
            valLbl:SetText(FormatMoney(br.val))
            by = by - 20
          end
          y = y - bh - 6
        end

        -- 7-Day Income vs Expense Trend Bars
        local dayTotals = {}
        local maxDay = 1
        local now = time()
        for dOff = 6, 0, -1 do
          local d = date("*t", now - dOff * 86400)
          d.hour, d.min, d.sec = 0, 0, 0
          local ds = time(d)
          local de = ds + 86400
          local inc, exp = 0, 0
          for _, e in ipairs(db.entries) do
            if (e.t or 0) >= ds and (e.t or 0) < de and (scopeAll or e.who == ns.me) and not ns.IsGoldTransfer(e.cat) then
              if (e.delta or 0) >= 0 then inc = inc + e.delta else exp = exp + (-e.delta) end
            end
          end
          maxDay = math.max(maxDay, inc, exp)
          dayTotals[#dayTotals + 1] = { label = date("%a", ds), inc = inc, exp = exp }
        end
        Heading("7-Day Trend (Green = In, Red = Out)")
        local trendBox, trendPool = pool:Frame("trend")
        trendBox:SetSize(480, 96)
        trendBox:SetPoint("TOPLEFT", 0, y)
        local tBg = trendPool:Texture("BACKGROUND")
        tBg:SetColorTexture(0.10, 0.12, 0.16, 0.85)
        tBg:SetAllPoints()
        for i, dt in ipairs(dayTotals) do
          local gx = 18 + (i - 1) * 66
          local incH = dt.inc > 0 and math.max(3, math.floor((dt.inc / maxDay) * 64)) or 2
          local expH = dt.exp > 0 and math.max(3, math.floor((dt.exp / maxDay) * 64)) or 2
          local incBar = trendPool:Texture("ARTWORK", "in")
          incBar:SetColorTexture(0.29, 0.87, 0.50, dt.inc > 0 and 0.95 or 0.2)
          incBar:SetSize(16, incH)
          incBar:SetPoint("BOTTOMLEFT", trendBox, "BOTTOMLEFT", gx, 22)
          local expBar = trendPool:Texture("ARTWORK", "out")
          expBar:SetColorTexture(1.00, 0.42, 0.42, dt.exp > 0 and 0.95 or 0.2)
          expBar:SetSize(16, expH)
          expBar:SetPoint("BOTTOMLEFT", trendBox, "BOTTOMLEFT", gx + 19, 22)
          local dLbl = trendPool:Font(10, C.muted)
          dLbl:SetPoint("BOTTOM", trendBox, "BOTTOMLEFT", gx + 17, 5)
          dLbl:SetText(dt.label)
        end
        y = y - 104
      end

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
          local bLine = pool:Font(11, C.text)
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
          local line = pool:Font(11, C.text)
          line:SetPoint("TOPLEFT", 4, y)
          local parts = {}
          if bucket.inc > 0 then parts[#parts + 1] = "|cff4ade80+" .. FormatMoney(bucket.inc) .. "|r" end
          if bucket.exp > 0 then parts[#parts + 1] = "|cffff6b6b-" .. FormatMoney(bucket.exp) .. "|r" end
          line:SetText(string.format("%s%s|r%s:  %s", cat.color, cat.label, cat.transfer and " |cff888888(moved, not spent)|r" or "", table.concat(parts, "   ")))
          y = y - 18
        end
      end

      Heading("Recent Transactions (" .. math.min(25, #sum.entries) .. " of " .. #sum.entries .. ")")
      if #sum.entries == 0 then
        local empty = pool:Font(11, C.muted)
        empty:SetPoint("TOPLEFT", 4, y)
        empty:SetText("No gold transactions recorded in this timeframe yet.")
        y = y - 20
      else
        for i = 1, math.min(25, #sum.entries) do
          local e = sum.entries[i]
          local cat = CAT_MAP[e.cat] or CAT_MAP.other
          local dCol = e.delta >= 0 and "|cff4ade80+" or "|cffff6b6b"
          if cat.transfer then dCol = e.delta >= 0 and "|cffa3afc2+" or "|cffa3afc2" end
          local short = ns.Short and ns.Short(e.who or "?") or (e.who or "?")
          local rowText = pool:Font(11, C.text)
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
  -- A guild-funded repair (RepairAllItems(true)) doesn't touch the player's gold.
  if RepairAllItems then hooksecurefunc("RepairAllItems", function(guild) if not guild then SetPending("repair", 3) end end) end
  if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function() SetPending("flight", 4) end) end
  -- Gold mailed to, or taken from mail sent by, one of your own characters.
  if SendMail then
    hooksecurefunc("SendMail", function(to)
      local money = GetSendMailMoney and SafeNum(GetSendMailMoney()) or 0
      if money > 0 and ns.IsMyCharacter(to) then SetPending("alts", 6, -1, money) end
    end)
  end
  local function FromMyCharacter(i)
    if not GetInboxHeaderInfo then return end
    local _, _, sender, _, money, cod = GetInboxHeaderInfo(i)
    if (SafeNum(money) or 0) > 0 and (SafeNum(cod) or 0) == 0 and ns.IsMyCharacter(sender) then
      SetPending("alts", 4, 1)
    end
  end
  if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", FromMyCharacter) end
  if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", FromMyCharacter) end
end

if ns.On then
  ns.On("PLAYER_LOGIN", function()
    lastMoney = GetMoney and SafeNum(GetMoney()) or 0
  end)
  ns.On("PLAYER_MONEY", function()
    local cur = GetMoney and SafeNum(GetMoney())
    if not cur then return end
    if lastMoney ~= nil and cur ~= lastMoney then
      local cat, amount = DetectCategory(cur - lastMoney)
      RecordDelta(cur - lastMoney, cat, amount)
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

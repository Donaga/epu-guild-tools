-- EPU Guild Tools: the in-game guild bank, counted alongside the bank alts.
-- Contents are read whenever someone opens the guild bank; officers publish
-- them to the guild and turn deposit-log entries into donation records.
local ADDON, ns = ...

local GB_KEY = "Guild Bank"
ns.GB_KEY = GB_KEY

local isOpen = false
local movedNoted = 0   -- bank-character deposits already mentioned since login
local loaded, pendingTab, queryQueue = {}, nil, {}
local QueryNext
local SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98

local function NumTabs()
  return (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
end

local function Viewable(tab)
  local _, _, viewable = GetGuildBankTabInfo(tab)
  return viewable
end

function ns.ScanGuildBank()
  if not isOpen then return end
  local g = ns.G()
  if not g then return end
  g.gbTabs = g.gbTabs or {}
  local n = NumTabs()
  for tab = 1, n do
    local name, _, viewable = GetGuildBankTabInfo(tab)
    if viewable and loaded[tab] then
      local items = {}
      for slot = 1, SLOTS do
        local id = ns.ItemID(GetGuildBankItemLink(tab, slot))
        if id then
          local _, count = GetGuildBankItemInfo(tab, slot)
          items[id] = (items[id] or 0) + (tonumber(count) or 1)
        end
      end
      g.gbTabs[tab] = { name = name, items = items, t = ns.Now() }
    end
  end
  for tab in pairs(g.gbTabs) do
    if tab > n then g.gbTabs[tab] = nil end
  end

  local complete = true
  for tab = 1, n do if not Viewable(tab) or not loaded[tab] then complete = false end end
  if not complete then return end
  local items = {}
  for _, t in pairs(g.gbTabs) do
    for id, c in pairs(t.items or {}) do items[id] = (items[id] or 0) + c end
  end
  local money = (GetGuildBankMoney and GetGuildBankMoney()) or 0
  local cur = g.bank[GB_KEY]
  -- No tabs bought and no gold yet: there's no guild bank to show. Clear any
  -- empty entry recorded earlier instead of listing an empty "Guild Bank".
  if n == 0 and money == 0 then
    if cur and not cur.retired and ns.IsBankTrusted(ns.me) then
      g.bank[GB_KEY] = { v = ns.NextVersion(cur.v), money = 0, items = {}, seen=ns.BankHistory(cur,nil,GB_KEY), retired = true, guild = true }
      ns.Send("D", { bank = { [GB_KEY] = g.bank[GB_KEY] } })
      ns.Changed()
    end
    return
  end
  local seen=ns.BankHistory(cur,items,GB_KEY)
  if cur and cur.money == money and ns.SameCounts(cur.items, items) and ns.Fingerprint(cur.seen)==ns.Fingerprint(seen) then
    if ns.Now()-(cur.bankTime or 0)<60 then return end
  end
  g.bank[GB_KEY] = { v = ns.NextVersion(cur and cur.v), money = money, items = items, seen=seen, bankTime = ns.Now(), guild = true }
  ns.Changed()
  if ns.IsBankTrusted(ns.me) then
    ns.Debounce("gbBroadcast", 5, function()
      local s = g.bank[GB_KEY]
      if s then ns.Send("D", { bank = { [GB_KEY] = s } }) end
    end)
  end
end

---------------------------------------------------------------------------
-- Deposit log -> donations. Log times are relative ("3 hours ago"), so a
-- deposit matches an existing record if who/what/how much agree and the
-- times are within 3 hours of each other.
-- Deposits by bank characters (Donlock moving the guild's stock in, say) are
-- the guild's own items changing places, so they are never donations.
---------------------------------------------------------------------------
local function LogTime(y, mo, d, h)
  return ns.Now() - ((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 86400 - (h or 0) * 3600
end

-- When the donation list is full: a log time at or before which a deposit
-- can't be new (the oldest donation kept, plus the log-time slack).
function ns.DonationsAgedOutBefore(g)
  local n, oldest = 0, nil
  for _, d in pairs(g.donations) do
    n = n + 1
    local t = d.t or 0
    if not oldest or t < oldest then oldest = t end
  end
  if n < ns.DONATION_CAP or not oldest then return nil end
  return oldest + 3 * 3600
end

function ns.ParseGuildBankLogs()
  if not isOpen or not ns.IsBankTrusted(ns.me) then return end
  local g = ns.G()
  if not g then return end

  local entries, moved, withdrawals = {}, 0, {}
  for tab = 1, NumTabs() do
    if Viewable(tab) and GetNumGuildBankTransactions then
      for i = 1, (GetNumGuildBankTransactions(tab) or 0) do
        local kind, who, link, count, _, _, y, mo, d, h = GetGuildBankTransaction(tab, i)
        local id = ns.ItemID(link)
        who = ns.Member(who) or ns.Short(who)
        if kind == "deposit" and id and who and ns.IsBankCharacter(who) then
          moved = moved + 1
        elseif kind == "deposit" and id and who then
          entries[#entries + 1] = { who = who, item = id, n = tonumber(count) or 1, money = 0, t = LogTime(y, mo, d, h) }
        elseif kind == "withdraw" and id and who and not ns.IsBankCharacter(who) then
          withdrawals[#withdrawals + 1] = { who = who, item = id, n = tonumber(count) or 1, t = LogTime(y, mo, d, h) }
        end
      end
    end
  end
  if GetNumGuildBankMoneyTransactions then
    for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
      local kind, who, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
      who = ns.Member(who) or ns.Short(who)
      if kind == "deposit" and who and (tonumber(amount) or 0) > 0 and ns.IsBankCharacter(who) then
        moved = moved + 1
      elseif kind == "deposit" and who and (tonumber(amount) or 0) > 0 then
        entries[#entries + 1] = { who = who, n = 0, money = tonumber(amount), t = LogTime(y, mo, d, h) }
      end
    end
  end

  -- Match only against records that existed before this scan, so two
  -- identical deposits in the same log both count.
  local before = {}
  for id, d in pairs(g.donations) do
    if d.to == GB_KEY then before[id] = d end
  end
  local used = {}
  local function Known(e)
    for id, d in pairs(before) do
      if not used[id] and d.to == GB_KEY and d.who == e.who and d.item == e.item
        and (d.n or 0) == e.n and (d.money or 0) == e.money and math.abs((d.t or 0) - e.t) <= 3 * 3600 then
        used[id] = true
        return true
      end
    end
    return false
  end
  -- Once the donation list is full, a deposit older than the oldest one kept
  -- is one that was already logged and has since been pruned (a quiet tab's
  -- log still shows it). Logging it again would thank the donor a second
  -- time, and Prune would drop it straight away, so leave it.
  local agedOut = ns.DonationsAgedOutBefore(g)
  for _, e in ipairs(entries) do
    if not Known(e) and not (agedOut and e.t <= agedOut) then ns.AddDonation(e.who, e.item, e.n, e.money, GB_KEY, e.t) end
  end
  ns.CreditWithdrawals(withdrawals)
  if moved > movedNoted then
    movedNoted = moved
    ns.Print(moved .. (moved == 1 and " deposit" or " deposits") .. " by bank characters in the guild bank log " .. (moved == 1 and "is" or "are")
      .. " the guild's own stock, so " .. (moved == 1 and "it isn't" or "they aren't") .. " counted as donations.")
  end
end

---------------------------------------------------------------------------
-- Withdrawal log -> request deliveries. A member who takes an item they asked
-- for straight out of the guild bank has received it, so the oldest approved
-- request of theirs (any of their characters) for that item is credited, as
-- if it had been mailed. Withdrawals by bank characters are stock moving, and
-- an officer taking something out for someone else is credited when they mail
-- or trade it, so neither counts here.
-- Each credited withdrawal is remembered on the delivery it made (from, wn,
-- wt), which travels with the request, so no client credits it twice. Only
-- withdrawals made after the request was created (or reopened) count, so an
-- old one still in the log can't fill a new request.
---------------------------------------------------------------------------
local WINDOW = 3 * 3600

local function SamePlayer(a, b)
  return a == b or (a ~= nil and b ~= nil and ns.MainOf(a) == ns.MainOf(b))
end

function ns.CreditWithdrawals(list)
  local g = ns.G()
  if not g or not list or #list == 0 or not ns.IsBankTrusted(ns.me) then return end
  -- withdrawals already credited, by anyone (one withdrawal may have made
  -- deliveries on several requests; it counts once)
  local credited, seen = {}, {}
  for _, r in pairs(g.requests) do
    for _, d in ipairs(r.deliveries or {}) do
      if d.from and d.wt and r.item then
        local key = d.from .. ":" .. r.item .. ":" .. tostring(d.wn) .. ":" .. d.wt
        if not seen[key] then
          seen[key] = true
          credited[#credited + 1] = { who = d.from, item = r.item, n = d.wn, t = d.wt }
        end
      end
    end
  end
  local used = {}
  local function Known(e)
    for i, c in ipairs(credited) do
      if not used[i] and c.who == e.who and c.item == e.item and c.n == e.n and math.abs(c.t - e.t) <= WINDOW then
        used[i] = true
        return true
      end
    end
    return false
  end
  table.sort(list, function(a, b) return a.t < b.t end)
  local batch, any = {}, false
  for _, e in ipairs(list) do
    if not Known(e) then
      local rows = {}
      for rid, r in pairs(g.requests) do
        if r.status == "approved" and not r.crafter and r.item == e.item and SamePlayer(r.to or r.who, e.who)
          and ns.Remaining(r) > 0 and e.t >= math.max(r.t or 0, r.reopenedAt or 0) - 3600 then
          rows[#rows + 1] = { id = rid, r = r }
        end
      end
      table.sort(rows, function(a, b) if (a.r.t or 0) ~= (b.r.t or 0) then return (a.r.t or 0) < (b.r.t or 0) end return a.id < b.id end)
      local left = e.n
      for _, row in ipairs(rows) do
        if left <= 0 then break end
        local r = row.r
        local n = math.min(left, ns.Remaining(r))
        left = left - n
        r.delivered = (r.delivered or 0) + n
        r.deliveries = r.deliveries or {}
        r.deliveries[#r.deliveries + 1] = { t = ns.Now(), by = ns.me, n = n, from = e.who, wn = e.n, wt = e.t }
        if #r.deliveries > 50 then table.remove(r.deliveries, 1) end
        if ns.Remaining(r) == 0 then r.status = "filled" end
        r.by = ns.me
        r.u = ns.NextVersion(r.u)
        batch[row.id] = r
        any = true
        ns.Print(e.who .. " took " .. ns.ItemLink(r.item) .. " x" .. n .. " from the guild bank for their request; "
          .. ns.Remaining(r) .. " remaining.")
      end
    end
  end
  if any then
    ns.Send("D", { req = batch })
    ns.Changed()
  end
end

---------------------------------------------------------------------------
-- Pull for request: with the guild bank open, move exactly what an approved
-- request still needs from the guild bank into your bags, one stack at a
-- time (the server handles guild bank moves one by one), ready for Mail it.
-- Whole stacks are taken where they fit, and one stack is split for the rest.
---------------------------------------------------------------------------
function ns.GuildBankIsOpen() return isOpen end

local pulling = false

-- withdrawals left today on a tab; nil means no limit
local function WithdrawalsLeft(tab)
  local _, _, _, _, _, left = GetGuildBankTabInfo(tab)
  left = tonumber(left)
  if left and left >= 0 then return left end
  return nil
end

-- Steps that take `qty` of `item` from the viewable tabs: { tab, slot, take, whole }.
-- Returns the steps, how many they take, how many the bank holds, and
-- whether withdrawal limits left some out.
function ns.PlanGuildBankPull(item, qty)
  local stacks, have = {}, 0
  for tab = 1, NumTabs() do
    if Viewable(tab) then
      for slot = 1, SLOTS do
        if ns.ItemID(GetGuildBankItemLink(tab, slot)) == item then
          local _, count, locked = GetGuildBankItemInfo(tab, slot)
          count = tonumber(count) or 1
          have = have + count
          if not locked then stacks[#stacks + 1] = { tab = tab, slot = slot, n = count } end
        end
      end
    end
  end
  table.sort(stacks, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.tab ~= b.tab then return a.tab < b.tab end
    return a.slot < b.slot
  end)
  local left, limited = {}, false
  local function Allowed(tab)
    if left[tab] == nil then left[tab] = WithdrawalsLeft(tab) or math.huge end
    if left[tab] <= 0 then limited = true return false end
    return true
  end
  local steps, need = {}, qty
  for _, st in ipairs(stacks) do
    if need <= 0 then break end
    if st.n <= need and Allowed(st.tab) then
      steps[#steps + 1] = { tab = st.tab, slot = st.slot, take = st.n, whole = true }
      need, st.used = need - st.n, true
      left[st.tab] = left[st.tab] - 1
    end
  end
  if need > 0 then
    local best
    for _, st in ipairs(stacks) do
      if not st.used and st.n > need and (not best or st.n < best.n) and Allowed(st.tab) then best = st end
    end
    if best then
      steps[#steps + 1] = { tab = best.tab, slot = best.slot, take = need, whole = false }
      need = 0
    end
  end
  return steps, qty - need, have, limited
end

local function EmptyBagSlots()
  local free = {}
  for _, bag in ipairs(ns.BagList()) do
    local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
    for slot = 1, n do
      local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
      if not info then free[#free + 1] = { bag, slot } end
    end
  end
  return free
end

local function InBags(item)
  local total = 0
  for _, bag in ipairs(ns.BagList()) do
    local n = (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
    for slot = 1, n do
      local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == item then total = total + (info.stackCount or 1) end
    end
  end
  return total
end

function ns.PullForRequest(rid)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return end
  if not ns.IsBankTrusted(ns.me) then return ns.Print("Only officers and bank managers pull requests from the guild bank.") end
  if r.crafter or not r.item then return ns.Print("Only item requests to the bank can be pulled from the guild bank.") end
  if r.status ~= "approved" then return ns.Print("Approve the request before pulling it from the guild bank.") end
  if not isOpen then return ns.Print("Open the guild bank first, then click Pull for request again.") end
  if pulling then return ns.Print("Still pulling the last request. Wait a moment.") end
  local want = ns.Remaining(r)
  if want <= 0 then return ns.Print("This request has nothing left to send.") end
  local steps, got, have, limited = ns.PlanGuildBankPull(r.item, want)
  if #steps == 0 then
    if limited then return ns.Print("You have no guild bank withdrawals left today on the tabs that hold " .. ns.ItemLink(r.item) .. ".") end
    return ns.Print("The guild bank has no " .. ns.ItemLink(r.item) .. " you can take right now.")
  end
  local free = EmptyBagSlots()
  if #free < #steps then
    return ns.Print("That needs " .. #steps .. " empty bag slot" .. (#steps == 1 and "" or "s") .. " and you have " .. #free .. ". Make room, then try again.")
  end
  local to, start = r.to or r.who, InBags(r.item)
  pulling = true
  local i = 0
  local function Finish()
    pulling = false
    C_Timer.After(0.5, function()
      local moved = InBags(r.item) - start
      if moved >= want then
        ns.Print("Pulled " .. ns.ItemLink(r.item) .. " x" .. want .. " for " .. to .. ". Take it to a mailbox and click Mail it on the request.")
      elseif moved > 0 then
        ns.Print("Pulled " .. moved .. " of " .. want .. " " .. ns.ItemLink(r.item) .. " for " .. to .. "."
          .. ((got < want) and (limited and " Your withdrawal limit stopped the rest." or (" The guild bank only had " .. have .. ".")) or " Check your bags; the rest didn't move.")
          .. " Mail it sends what you have; the rest stays open.")
      else
        ns.Print("Nothing moved from the guild bank. Check your withdrawal limit for today, then try again.")
      end
    end)
  end
  local function Step()
    i = i + 1
    local st = steps[i]
    if not st or not isOpen then return Finish() end
    if ClearCursor then ClearCursor() end
    if SetCurrentGuildBankTab and GetCurrentGuildBankTab and GetCurrentGuildBankTab() ~= st.tab then SetCurrentGuildBankTab(st.tab) end
    if st.whole then PickupGuildBankItem(st.tab, st.slot) else SplitGuildBankItem(st.tab, st.slot, st.take) end
    local spot = free[i]
    if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(spot[1], spot[2]) else PickupContainerItem(spot[1], spot[2]) end
    if ClearCursor then ClearCursor() end
    C_Timer.After(0.5, Step)
  end
  if got < want then
    ns.Print("The guild bank can give " .. got .. " of " .. want .. " " .. ns.ItemLink(r.item) .. " right now.")
  end
  Step()
end

-- Query one tab at a time: GUILDBANKBAGSLOTS_CHANGED has no tab argument.
QueryNext = function()
  if not isOpen or pendingTab then return end
  local tab = table.remove(queryQueue, 1)
  if not tab then ns.ScanGuildBank(); return end
  pendingTab = tab
  if QueryGuildBankTab then QueryGuildBankTab(tab) end
  if QueryGuildBankLog then QueryGuildBankLog(tab) end
end

local function SlotsChanged()
  if not isOpen then return end
  local tab = pendingTab or (GetCurrentGuildBankTab and GetCurrentGuildBankTab())
  if not tab then return end
  loaded[tab] = true
  pendingTab = nil
  ns.ScanGuildBank()
  -- Let duplicate events from this reply drain before requesting another tab.
  ns.Debounce("gbnext", 0.5, QueryNext)
end

local function OnOpen()
  if isOpen then return end
  isOpen = true
  loaded, queryQueue, pendingTab = {}, {}, nil
  for tab = 1, NumTabs() do
    if Viewable(tab) then queryQueue[#queryQueue + 1] = tab end
  end
  QueryNext()
  if QueryGuildBankLog then
    C_Timer.After(0.2, function() if isOpen then QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1) end end)
  end
  ns.Debounce("gbscan", 1.5, ns.ScanGuildBank)
  ns.Changed()
  -- the donate panel, beside the guild bank
  C_Timer.After(0.3, function() if isOpen and ns.ShowDonate then ns.ShowDonate("vault") end end)
end

local function OnClose()
  isOpen = false
  loaded, pendingTab, queryQueue = {}, nil, {}
  if ns.HideDonate then ns.HideDonate("vault") end
  ns.Changed()
end

local function IsGuildBanker(kind)
  local e = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
  return e ~= nil and kind == e
end

ns.On("GUILDBANKFRAME_OPENED", OnOpen)
ns.On("GUILDBANKFRAME_CLOSED", OnClose)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if IsGuildBanker(kind) then OnOpen() end end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if IsGuildBanker(kind) then OnClose() end end)
ns.On("GUILDBANKBAGSLOTS_CHANGED", SlotsChanged)
ns.On("GUILDBANK_UPDATE_TABS", function() ns.Debounce("gbscan", 1, ns.ScanGuildBank) end)
ns.On("GUILDBANK_UPDATE_MONEY", function() ns.Debounce("gbscan", 1, ns.ScanGuildBank) end)
ns.On("GUILDBANKLOG_UPDATE", function() ns.Debounce("gblog", 1, ns.ParseGuildBankLogs) end)

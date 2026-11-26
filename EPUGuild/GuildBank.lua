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
  ns.MarkDuplicateDonations(g)
  ns.CreditWithdrawals(withdrawals)
  if moved > movedNoted then
    movedNoted = moved
    ns.Print(moved .. (moved == 1 and " deposit" or " deposits") .. " by bank characters in the guild bank log " .. (moved == 1 and "is" or "are")
      .. " the guild's own stock, so " .. (moved == 1 and "it isn't" or "they aren't") .. " counted as donations.")
  end
end

---------------------------------------------------------------------------
-- Two officers (or bank managers) who open the guild bank close together
-- each read the same deposit before the other's record reaches them, so it's
-- logged twice, under two ids. Every client works out the same duplicates
-- from the records it holds and marks them (d.dup): they stay in the data,
-- so the deposit is never logged a third time, but they aren't listed,
-- counted or thanked.
-- Records match when who/what/how much agree and they sit within the same
-- 3-hour log slack as above. In each run of matching records, the logger
-- that recorded the most of them is kept (ties: the lowest name), so two
-- real identical deposits logged by one officer both stay.
---------------------------------------------------------------------------
local DUP_WINDOW = 3 * 3600

-- "Chris Baker:1700000000:3" -> "Chris Baker"
local function Logger(id)
  id = tostring(id)
  return id:match("^(.-):%d+:%d+$") or id
end
ns.DonationLogger = Logger

function ns.MarkDuplicateDonations(g)
  g = g or ns.G()
  if not g or type(g.donations) ~= "table" then return 0 end
  local groups = {}
  for id, d in pairs(g.donations) do
    if type(d) == "table" then
      d.dup = nil
      if d.to == GB_KEY and not d.void then
        local sig = tostring(d.who) .. "|" .. tostring(d.item or "") .. "|" .. tostring(tonumber(d.n) or 0) .. "|" .. tostring(tonumber(d.money) or 0)
        local list = groups[sig]
        if not list then list = {}; groups[sig] = list end
        list[#list + 1] = { id = tostring(id), d = d, by = Logger(id), t = tonumber(d.t) or 0 }
      end
    end
  end
  local marked = 0
  for _, list in pairs(groups) do
    if #list > 1 then
      table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
      local i = 1
      while i <= #list do
        local j = i
        while j < #list and list[j + 1].t - list[j].t <= DUP_WINDOW do j = j + 1 end
        if j > i then
          local count, keep = {}, nil
          for k = i, j do count[list[k].by] = (count[list[k].by] or 0) + 1 end
          for by, c in pairs(count) do
            if not keep or c > count[keep] or (c == count[keep] and by < keep) then keep = by end
          end
          for k = i, j do
            if list[k].by ~= keep then list[k].d.dup = true; marked = marked + 1 end
          end
        end
        i = j + 1
      end
    end
  end
  return marked
end

-- A donation that counts: not voided by an officer and not a second copy.
function ns.DonationCounts(d)
  return type(d) == "table" and not d.void and not d.dup
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

-- What the open guild bank holds, slot by slot, for the category window:
-- stacks = { {tab, slot, id, n, locked} } from tabs that have loaded; tabs[tab]
-- = { name, loaded, canDeposit, withdrawalsLeft (nil = no limit), empty = {slots} }.
-- Also returns how many viewable tabs are still loading.
function ns.GuildBankLiveStacks()
  local stacks, tabs, pending = {}, {}, 0
  if not isOpen then return stacks, tabs, 0 end
  for tab = 1, NumTabs() do
    local name, _, viewable, canDeposit = GetGuildBankTabInfo(tab)
    if viewable then
      local t = { name = name, loaded = loaded[tab] == true, canDeposit = canDeposit ~= false,
        withdrawalsLeft = WithdrawalsLeft(tab), empty = {} }
      tabs[tab] = t
      if t.loaded then
        for slot = 1, SLOTS do
          local id = ns.ItemID(GetGuildBankItemLink(tab, slot))
          if id then
            local _, count, locked = GetGuildBankItemInfo(tab, slot)
            stacks[#stacks + 1] = { tab = tab, slot = slot, id = id, n = tonumber(count) or 1, locked = locked and true or nil }
          else
            t.empty[#t.empty + 1] = slot
          end
        end
      else
        pending = pending + 1
      end
    end
  end
  return stacks, tabs, pending
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

-- Take `want` of `item` out of the open guild bank into your bags, one stack
-- at a time. The game only lets you do this at a guild vault, from tabs your
-- rank may withdraw from, within the tab's daily withdrawal limit; the plan
-- skips tabs that are out of withdrawals. finish(moved, got, have, limited)
-- runs once the moves have settled. Returns true when the moves started.
function ns.PullFromGuildBank(item, want, finish)
  if not isOpen then return false end
  if pulling then ns.Print("Still pulling from the guild bank. Wait a moment.") return false end
  local steps, got, have, limited = ns.PlanGuildBankPull(item, want)
  if #steps == 0 then
    if limited then ns.Print("You have no guild bank withdrawals left today on the tabs that hold " .. ns.ItemLink(item) .. ".") return false end
    ns.Print("The guild bank has no " .. ns.ItemLink(item) .. " you can take right now.")
    return false
  end
  local free = EmptyBagSlots()
  if #free < #steps then
    ns.Print("That needs " .. #steps .. " empty bag slot" .. (#steps == 1 and "" or "s") .. " and you have " .. #free .. ". Make room, then try again.")
    return false
  end
  local start = InBags(item)
  pulling = true
  local i = 0
  local function Finish()
    pulling = false
    C_Timer.After(0.5, function()
      if finish then finish(InBags(item) - start, got, have, limited) end
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
    ns.Print("The guild bank can give " .. got .. " of " .. want .. " " .. ns.ItemLink(item) .. " right now.")
  end
  Step()
  return true
end

function ns.PullForRequest(rid)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return end
  if not ns.IsBankTrusted(ns.me) then return ns.Print("Only officers and bank managers pull requests from the guild bank.") end
  if r.crafter or not r.item then return ns.Print("Only item requests to the bank can be pulled from the guild bank.") end
  if r.status ~= "approved" then return ns.Print("Approve the request before pulling it from the guild bank.") end
  if not isOpen then return ns.Print("Open the guild bank first, then click Pull for request again.") end
  local want = ns.Remaining(r)
  if want <= 0 then return ns.Print("This request has nothing left to send.") end
  local to = r.to or r.who
  return ns.PullFromGuildBank(r.item, want, function(moved, got, have, limited)
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

---------------------------------------------------------------------------
-- Which tab each kind of item belongs in, for the Bank page's tab tools.
-- A tab holds the categories its name names ("Herbs", "Recipes", "Gear"),
-- or, with no such word, the one category that fills at least half of it.
-- Items of another category are out of place when some other tab holds that
-- category, or when the tab's name says it's for something else. Nothing is
-- ever moved; the Bank page only points these out.
---------------------------------------------------------------------------
local TRADE_CATS = { "Cloth", "Leather", "Metal & Stone", "Herbs", "Cooking", "Enchanting", "Elemental",
  "Parts & Engineering", "Other Trade Goods" }
local TAB_WORDS = {
  { "Cloth", { "cloth", "linen", "silk", "wool" } },
  { "Leather", { "leather", "hide", "skin" } },
  { "Metal & Stone", { "metal", "ore", "stone", "mining" } },
  { "Herbs", { "herb" } },
  { "Cooking", { "cook", "food", "meat", "fish" } },
  { "Enchanting", { "enchant", "dust", "essence", "shard" } },
  { "Elemental", { "elemental" } },
  { "Parts & Engineering", { "engineer", "parts" } },
  { "Consumables", { "consum", "potion", "flask", "elixir", "scroll" } },
  { "Reagents", { "reagent" } },
  { "Bags", { "bag" } },
  { "Weapons & Armor", { "gear", "weapon", "armor", "armour", "equip", "twink" } },
  { "Recipes", { "recipe", "pattern", "plans", "formula", "schematic", "book" } },
}
local GENERIC_MATS = { "mats", "material", "trade" }   -- a general materials tab

local function NameClaims(name)
  local low, claims, any = tostring(name or ""):lower(), {}, false
  for _, entry in ipairs(TAB_WORDS) do
    for _, w in ipairs(entry[2]) do
      if low:find(w, 1, true) then claims[entry[1]] = true; any = true; break end
    end
  end
  local generic = false
  for _, w in ipairs(GENERIC_MATS) do if low:find(w, 1, true) then generic = true end end
  return any and claims or nil, generic
end
ns.GuildBankTabNameClaims = NameClaims

function ns.GuildBankTabLabel(tab, t)
  local name = type(t) == "table" and t.name
  return "Tab " .. tab .. ((name and name ~= "") and (": " .. name) or "")
end

-- plan.order: tab numbers in order; plan.tabs[tab] = { name, label, kinds,
-- byCat = {cat = kinds}, holds = {cat = true}, holdsText, named, misplaced };
-- plan.home[cat] = tab; plan.misplaced[id] = { {tab, n, cat, suggest, why} };
-- plan.count = misplaced item stacks across all tabs.
function ns.GuildBankTabPlan(g)
  g = g or ns.G()
  local plan = { order = {}, tabs = {}, home = {}, misplaced = {}, count = 0 }
  if not g or type(g.gbTabs) ~= "table" then return plan end
  local catOf = {}
  local function Cat(id)
    if catOf[id] == nil then
      local ok, c = pcall(ns.ItemCategory, id)
      catOf[id] = (ok and type(c) == "string") and c or "Other"
    end
    return catOf[id]
  end
  for tab, t in pairs(g.gbTabs) do
    if type(tab) == "number" and type(t) == "table" then plan.order[#plan.order + 1] = tab end
  end
  table.sort(plan.order)
  local generics = {}
  for _, tab in ipairs(plan.order) do
    local t = g.gbTabs[tab]
    local info = { name = t.name, label = ns.GuildBankTabLabel(tab, t), kinds = 0, byCat = {}, holds = {}, misplaced = 0 }
    for id, n in pairs(type(t.items) == "table" and t.items or {}) do
      id, n = tonumber(id), tonumber(n) or 0
      if id and n > 0 then
        local c = Cat(id)
        info.kinds = info.kinds + 1
        info.byCat[c] = (info.byCat[c] or 0) + 1
      end
    end
    local claims, generic = NameClaims(t.name)
    if claims then
      info.holds, info.named = claims, true
    elseif generic then
      generics[#generics + 1] = tab
    else
      local best, bestN = nil, 0
      for c, n in pairs(info.byCat) do
        if n > bestN or (n == bestN and best and c < best) then best, bestN = c, n end
      end
      if best and bestN >= 2 and bestN * 2 >= info.kinds then info.holds[best] = true end
    end
    plan.tabs[tab] = info
  end
  -- Home tab per category: a tab named for it first, then the tab mostly made of it.
  for _, tab in ipairs(plan.order) do
    local info = plan.tabs[tab]
    if info.named then for c in pairs(info.holds) do plan.home[c] = plan.home[c] or tab end end
  end
  for _, tab in ipairs(plan.order) do
    local info = plan.tabs[tab]
    if not info.named then
      for c in pairs(info.holds) do
        local cur = plan.home[c]
        if not cur or (not plan.tabs[cur].named and (info.byCat[c] or 0) > (plan.tabs[cur].byCat[c] or 0)) then plan.home[c] = tab end
      end
    end
  end
  -- A general materials tab takes every trade good no other tab is named for.
  for _, tab in ipairs(generics) do
    local info = plan.tabs[tab]
    info.named, info.generic = true, true
    for _, c in ipairs(TRADE_CATS) do
      if not plan.home[c] or not plan.tabs[plan.home[c]].named then info.holds[c] = true; plan.home[c] = tab end
    end
  end
  for _, tab in ipairs(plan.order) do
    local info = plan.tabs[tab]
    local list = {}
    for _, c in ipairs(ns.CATEGORIES) do if info.holds[c] then list[#list + 1] = c end end
    info.holdsText = #list > 0 and table.concat(list, ", ") or nil
    if info.generic then   -- "trade goods", or "trade goods except Herbs"
      local other = {}
      for _, c in ipairs(TRADE_CATS) do if not info.holds[c] then other[#other + 1] = c end end
      info.holdsText = "trade goods" .. (#other > 0 and (" except " .. table.concat(other, ", ")) or "")
    end
    for id, n in pairs(type(g.gbTabs[tab].items) == "table" and g.gbTabs[tab].items or {}) do
      id, n = tonumber(id), tonumber(n) or 0
      if id and n > 0 then
        local c = Cat(id)
        local home = plan.home[c]
        local why
        if not info.holds[c] then
          if home and home ~= tab then
            why = "Belongs in " .. plan.tabs[home].label
          elseif info.named then
            why = "Not what " .. info.label .. " is for"
          end
        end
        if why then
          plan.misplaced[id] = plan.misplaced[id] or {}
          table.insert(plan.misplaced[id], { tab = tab, n = n, cat = c, suggest = home ~= tab and home or nil, why = why })
          info.misplaced = info.misplaced + 1
          plan.count = plan.count + 1
        end
      end
    end
  end
  return plan
end

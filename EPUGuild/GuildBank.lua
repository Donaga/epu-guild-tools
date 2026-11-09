-- EPU Guild Tools: the in-game guild bank, counted alongside the bank alts.
-- Contents are read whenever someone opens the guild bank; officers publish
-- them to the guild and turn deposit-log entries into donation records.
local ADDON, ns = ...

local GB_KEY = "Guild Bank"
ns.GB_KEY = GB_KEY

local isOpen = false
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
    if cur and not cur.retired and ns.IsTrusted(ns.me) then
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
  if ns.IsTrusted(ns.me) then
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
---------------------------------------------------------------------------
local function LogTime(y, mo, d, h)
  return ns.Now() - ((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 86400 - (h or 0) * 3600
end

function ns.ParseGuildBankLogs()
  if not isOpen or not ns.IsTrusted(ns.me) then return end
  local g = ns.G()
  if not g then return end

  local entries = {}
  for tab = 1, NumTabs() do
    if Viewable(tab) and GetNumGuildBankTransactions then
      for i = 1, (GetNumGuildBankTransactions(tab) or 0) do
        local kind, who, link, count, _, _, y, mo, d, h = GetGuildBankTransaction(tab, i)
        local id = ns.ItemID(link)
        who = ns.Member(who) or ns.Short(who)
        if kind == "deposit" and id and who then
          entries[#entries + 1] = { who = who, item = id, n = tonumber(count) or 1, money = 0, t = LogTime(y, mo, d, h) }
        end
      end
    end
  end
  if GetNumGuildBankMoneyTransactions then
    for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
      local kind, who, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
      who = ns.Member(who) or ns.Short(who)
      if kind == "deposit" and who and (tonumber(amount) or 0) > 0 then
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
  for _, e in ipairs(entries) do
    if not Known(e) then ns.AddDonation(e.who, e.item, e.n, e.money, GB_KEY, e.t) end
  end
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
  -- the donate panel, beside the guild bank
  C_Timer.After(0.3, function() if isOpen and ns.ShowDonate then ns.ShowDonate("vault") end end)
end

local function OnClose()
  isOpen = false
  loaded, pendingTab, queryQueue = {}, nil, {}
  if ns.HideDonate then ns.HideDonate("vault") end
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

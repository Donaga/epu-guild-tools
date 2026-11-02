-- EPU Guild Tools: bank alt inventory snapshots and automatic donation logging
local ADDON, ns = ...

function ns.IsBankAlt()
  return ns.cdb and ns.cdb.bankAlt == true
end

---------------------------------------------------------------------------
-- Container helpers (support both C_Container and the older globals)
---------------------------------------------------------------------------
local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  return GetContainerNumSlots(bag)
end

local function SlotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID or ns.ItemID(info.hyperlink), info.stackCount or 1 end
    return nil
  end
  local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
  if link then return id or ns.ItemID(link), count or 1 end
end

local function FreeSlots(bag)
  if C_Container and C_Container.GetContainerNumFreeSlots then return (C_Container.GetContainerNumFreeSlots(bag)) end
  return (GetContainerNumFreeSlots(bag))
end

local function BagList()
  local t = {}
  for b = 0, (NUM_BAG_SLOTS or 4) do t[#t + 1] = b end
  return t
end

local function BankList()
  local t = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do t[#t + 1] = b end
  return t
end

local function Scan(list)
  local items = {}
  for _, bag in ipairs(list) do
    for slot = 1, (NumSlots(bag) or 0) do
      local id, count = SlotItem(bag, slot)
      if id then items[id] = (items[id] or 0) + count end
    end
  end
  return items
end

local function TotalFreeBagSlots()
  local n = 0
  for _, b in ipairs(BagList()) do n = n + (FreeSlots(b) or 0) end
  return n
end

---------------------------------------------------------------------------
-- Snapshots
---------------------------------------------------------------------------
local bankOpen = false
local warnedTrust = false

function ns.SnapshotBank()
  if not ns.IsBankAlt() then return end
  local g = ns.G()
  if not g then return end
  local cdb = ns.cdb
  cdb.bagItems = Scan(BagList())
  if bankOpen then
    cdb.bankItems = Scan(BankList())
    cdb.bankTime = ns.Now()
  end
  local items = {}
  for id, c in pairs(cdb.bagItems or {}) do items[id] = (items[id] or 0) + c end
  for id, c in pairs(cdb.bankItems or {}) do items[id] = (items[id] or 0) + c end
  local money = GetMoney()

  local cur = g.bank[ns.me]
  if cur and not cur.retired and cur.money == money and ns.SameCounts(cur.items, items) then return end
  g.bank[ns.me] = { v = ns.NextVersion(cur and cur.v), money = money, items = items, bankTime = cdb.bankTime }
  ns.Changed()

  if not ns.IsTrusted(ns.me) and not warnedTrust then
    warnedTrust = true
    ns.Print("This bank alt isn't an officer or a rank with 'Bank' in its name, so other members will ignore its updates. Ask the GM to promote it, or use /epu officerrank.")
  end
  ns.Debounce("bankBroadcast", 5, function()
    local s = g.bank[ns.me]
    if s then ns.Send("D", { bank = { [ns.me] = s } }) end
  end)
end

local function Rescan(delay)
  if ns.IsBankAlt() then ns.Debounce("bankscan", delay or 1.5, ns.SnapshotBank) end
end

function ns.SetBankAlt(on)
  local g = ns.G()
  if not g then return ns.Print("Join the guild on this character first.") end
  if on then
    ns.cdb.bankAlt = true
    ns.Print(ns.me .. " is now a guild bank alt. Open the bank once so its contents are recorded.")
    ns.SnapshotBank()
  else
    ns.cdb.bankAlt = false
    local cur = g.bank[ns.me]
    g.bank[ns.me] = { v = ns.NextVersion(cur and cur.v), retired = true, items = {}, money = 0 }
    ns.Send("D", { bank = { [ns.me] = g.bank[ns.me] } })
    ns.Changed()
    ns.Print(ns.me .. " is no longer a bank alt.")
  end
end

ns.On("BAG_UPDATE", function() Rescan(1.5) end)
ns.On("PLAYER_MONEY", function() Rescan(1.5) end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() Rescan(1) end)
ns.On("BANKFRAME_OPENED", function() bankOpen = true; Rescan(0.5) end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false end)
ns.On("PLAYER_ENTERING_WORLD", function() Rescan(6) end)

---------------------------------------------------------------------------
-- Donations: anything a guild member mails or trades to a bank alt
---------------------------------------------------------------------------
local recent = {}
local donCounter = 0
ns.pendingDon = {}

local function Fresh(key)
  local now = GetTime()
  if recent[key] and now - recent[key] < 3 then return false end
  recent[key] = now
  return true
end

-- to: who received it (a bank alt, or ns.GB_KEY for the guild bank); t: when
function ns.AddDonation(who, item, n, money, to, t)
  local g = ns.G()
  if not g then return end
  donCounter = donCounter + 1
  t = t or ns.Now()
  local id = ns.me .. ":" .. ns.Now() .. ":" .. donCounter
  local d = { t = t, who = who, item = item, n = n or 0, money = money or 0, to = to or ns.me }
  g.donations[id] = d
  ns.pendingDon[id] = d
  ns.Changed()
  ns.Debounce("donBroadcast", 3, function()
    local p = ns.pendingDon
    ns.pendingDon = {}
    if next(p) then ns.Send("D", { don = p }) end
  end)
end

local function MailSender(i)
  local _, _, sender, _, money, cod = GetInboxHeaderInfo(i)
  sender = ns.Member(sender)
  if not sender then return nil end                             -- AH, NPCs, non-guild mail
  if cod and cod > 0 then return nil end                        -- COD is a purchase, not a gift
  return sender, money or 0
end

-- GetInboxItem returns (name, itemID, texture, count, ...) on current
-- clients and (name, texture, count, ...) on older ones; handle both.
function ns.InboxCount(i, a, id)
  local _, x, y, z = GetInboxItem(i, a)
  if x == id and tonumber(z) then return tonumber(z) end
  return tonumber(y) or 1
end

local function RecordMailItem(i, a)
  if not ns.IsBankAlt() then return end
  local sender = MailSender(i)
  if not sender or TotalFreeBagSlots() == 0 then return end
  local link = GetInboxItemLink and GetInboxItemLink(i, a)
  local id = ns.ItemID(link)
  if not id then return end
  count = ns.InboxCount(i, a, id)
  if Fresh("i" .. sender .. id .. count .. i .. a) then ns.AddDonation(sender, id, count, 0) end
end

local function RecordMailMoney(i)
  if not ns.IsBankAlt() then return end
  local sender, money = MailSender(i)
  if sender and money > 0 and Fresh("m" .. sender .. money .. i) then ns.AddDonation(sender, nil, 0, money) end
end

local function RecordMailAll(i)
  for a = 1, (ATTACHMENTS_MAX_RECEIVE or 12) do RecordMailItem(i, a) end
  RecordMailMoney(i)
end

-- Pre-hooks: the attachment is gone once the original function runs.
local function PreHook(name, fn)
  local orig = _G[name]
  if type(orig) ~= "function" then return end
  _G[name] = function(...)
    pcall(fn, ...)
    return orig(...)
  end
end
PreHook("TakeInboxItem", RecordMailItem)
PreHook("TakeInboxMoney", RecordMailMoney)
PreHook("AutoLootMailItem", RecordMailAll)

---------------------------------------------------------------------------
-- Auto-fill requests: when a trusted character mails or trades an item to
-- a member with an approved request for it, the request is marked filled.
---------------------------------------------------------------------------
local outgoing
PreHook("SendMail", function(to)
  outgoing = nil
  if not ns.IsTrusted(ns.me) or not GetSendMailItemLink then return end
  local items = {}
  for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local id = ns.ItemID(GetSendMailItemLink(i))
    if id then items[#items + 1] = { id, 1 } end
  end
  if #items > 0 then outgoing = { to = to, items = items } end
end)
ns.On("MAIL_SEND_SUCCESS", function()
  local o = outgoing
  outgoing = nil
  if o then ns.AutoFillFor(o.to, o.items) end
end)
ns.On("MAIL_FAILED", function() outgoing = nil end)

local tradeSnap
ns.On("TRADE_ACCEPT_UPDATE", function()
  local bankAlt, officer = ns.IsBankAlt(), ns.IsTrusted(ns.me)
  if not bankAlt and not officer then return end
  local who = ns.Member(ns.UnitFullName("NPC"))
  if not who then tradeSnap = nil return end
  local snap = { who = who, money = GetTargetTradeMoney() or 0, items = {}, mine = {}, bankAlt = bankAlt }
  for slot = 1, 6 do
    local id = ns.ItemID(GetTradeTargetItemLink(slot))
    if id then
      local _, _, count = GetTradeTargetItemInfo(slot)
      snap.items[#snap.items + 1] = { id, tonumber(count) or 1 }
    end
    local mineID = GetTradePlayerItemLink and ns.ItemID(GetTradePlayerItemLink(slot))
    if mineID then snap.mine[#snap.mine + 1] = { mineID, 1 } end
  end
  tradeSnap = snap
end)

ns.On("UI_INFO_MESSAGE", function(a, b)
  local msg = (type(b) == "string" and b) or a
  if not tradeSnap or msg ~= ERR_TRADE_COMPLETE then return end
  local s = tradeSnap
  tradeSnap = nil
  if s.bankAlt then
    for _, it in ipairs(s.items) do ns.AddDonation(s.who, it[1], it[2], 0) end
    if s.money > 0 then ns.AddDonation(s.who, nil, 0, s.money) end
  end
  if #s.mine > 0 then ns.AutoFillFor(s.who, s.mine) end
end)

ns.On("TRADE_CLOSED", function()
  C_Timer.After(2, function() tradeSnap = nil end)
end)

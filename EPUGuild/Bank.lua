-- EPU Guild Tools: bank alt inventory snapshots and automatic donation logging
local ADDON, ns = ...
-- Newer clients keep these under C_Item; the old global names only exist when
-- the game's "deprecated API" fallback is on, which varies from PC to PC.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

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

-- itemID, count, bound (soulbound: can't be traded or mailed)
local function SlotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID or ns.ItemID(info.hyperlink), info.stackCount or 1, info.isBound == true end
    return nil
  end
  local _, count, _, _, _, _, link, _, _, id, bound = GetContainerItemInfo(bag, slot)
  if link then return id or ns.ItemID(link), count or 1, bound == true end
end

local HEARTHSTONE = 6948
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

local function FreeSlots(bag)
  if C_Container and C_Container.GetContainerNumFreeSlots then return (C_Container.GetContainerNumFreeSlots(bag)) end
  return (GetContainerNumFreeSlots(bag))
end

-- Which container numbers are bags and which are the bank differs between
-- game versions (newer clients add a reagent bag and renumber bank bags, and
-- some use bank "tabs"), so ask the game when it can tell us.
local function BagList()
  local t, seen = {}, {}
  local function add(b) if b and not seen[b] then seen[b] = true; t[#t + 1] = b end end
  for b = 0, (NUM_BAG_SLOTS or 4) do add(b) end
  local E = Enum and Enum.BagIndex
  if E then add(E.ReagentBag) end
  return t, seen
end

local function BankList()
  local _, inBags = BagList()
  local t, seen = {}, {}
  local function add(b) if type(b) == "number" and not seen[b] and not inBags[b] then seen[b] = true; t[#t + 1] = b end end
  local E = Enum and Enum.BagIndex
  if E then
    for name, b in pairs(E) do
      -- the character's own bank, bank bags/tabs and reagent bank; not the account-wide one
      if type(name) == "string" and name:find("Bank") and not name:find("Account") and not name:find("Warband") then add(b) end
    end
  end
  add(BANK_CONTAINER or -1)
  add(REAGENTBANK_CONTAINER)
  if not E then
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
  end
  table.sort(t)
  return t
end
ns.BagList, ns.BankList = BagList, BankList

local function Scan(list)
  local items = {}
  for _, bag in ipairs(list) do
    for slot = 1, (NumSlots(bag) or 0) do
      local id, count, bound = SlotItem(bag, slot)
      -- guild stock is what the bank can give away: skip soulbound items
      -- (Hearthstone, bind-on-pickup gear) and quest items
      if id and not bound and id ~= HEARTHSTONE and select(12, GetItemInfo(id)) ~= QUEST_CLASS then
        items[id] = (items[id] or 0) + count
      end
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
-- newer clients report the banker through the interaction manager instead
local BANKER = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker) or 8
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if kind == BANKER then bankOpen = true; Rescan(0.5) end end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if kind == BANKER then Rescan(0); C_Timer.After(0.2, function() bankOpen = false end) end end)
ns.On("BAG_UPDATE_DELAYED", function() if bankOpen then Rescan(0.5) end end)
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
  if ns.DonationMilestone then pcall(ns.DonationMilestone, id, d) end
  ns.Changed()
  ns.Debounce("donBroadcast", 3, function()
    local p = ns.pendingDon
    ns.pendingDon = {}
    if next(p) then ns.Send("D", { don = p }) end
  end)
end

-- What's in the mailbox, read just before you act on it. We hook Blizzard's mail
-- functions safely (after they run), so we work from this copy instead of
-- assuming the mail is still there.
local inbox = {}   -- [index] = { sender, money, cod, items = { [slot] = { id, count } } }

local function ReadMail(i)
  local _, _, sender, _, money, cod = GetInboxHeaderInfo(i)
  local m = { sender = sender, money = money or 0, cod = cod or 0, items = {} }
  for a = 1, (ATTACHMENTS_MAX_RECEIVE or 12) do
    local id = ns.ItemID(GetInboxItemLink and GetInboxItemLink(i, a))
    if id then m.items[a] = { id, ns.InboxCount(i, a, id) } end
  end
  return m
end

local function SnapInbox()
  wipe(inbox)
  for i = 1, ((GetInboxNumItems and GetInboxNumItems()) or 0) do inbox[i] = ReadMail(i) end
end
ns.SnapInbox = SnapInbox
ns.On("MAIL_SHOW", SnapInbox)
ns.On("MAIL_INBOX_UPDATE", SnapInbox)

local function MailAt(i)
  return inbox[i] or ReadMail(i)
end

local function GuildSender(m)
  local sender = ns.Member(m.sender)
  if not sender then return nil end                             -- AH, NPCs, non-guild mail
  if m.cod and m.cod > 0 then return nil end                    -- COD is a purchase, not a gift
  return sender
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
  local m = MailAt(i)
  local sender = GuildSender(m)
  local it = m.items[a]
  if not sender or not it then return end
  m.items[a] = nil                                              -- taken; don't count it twice
  local id, count = it[1], it[2]
  if Fresh("i" .. sender .. id .. count .. i .. a) then ns.AddDonation(sender, id, count, 0) end
end

local function RecordMailMoney(i)
  if not ns.IsBankAlt() then return end
  local m = MailAt(i)
  local sender, money = GuildSender(m), m.money
  if sender and money > 0 then
    m.money = 0
    if Fresh("m" .. sender .. money .. i) then ns.AddDonation(sender, nil, 0, money) end
  end
end

local function RecordMailAll(i)
  for a = 1, (ATTACHMENTS_MAX_RECEIVE or 12) do RecordMailItem(i, a) end
  RecordMailMoney(i)
end

-- Run fn right after Blizzard's function, without replacing it: replacing a
-- Blizzard function "taints" the default UI and gets the addon blocked.
local function AfterCall(name, fn)
  if type(_G[name]) ~= "function" then return end
  hooksecurefunc(name, function(...) pcall(fn, ...) end)
end
AfterCall("TakeInboxItem", RecordMailItem)
AfterCall("TakeInboxMoney", RecordMailMoney)
AfterCall("AutoLootMailItem", RecordMailAll)

---------------------------------------------------------------------------
-- Auto-fill requests: when a trusted character mails or trades an item to
-- a member with an approved request for it, the request is marked filled.
---------------------------------------------------------------------------
local outgoing, attached = nil, {}

local function ReadAttachments()
  local items = {}
  if not GetSendMailItemLink then return items end
  for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local id = ns.ItemID(GetSendMailItemLink(i))
    if id and GetSendMailItem then
      local _, _, _, count = GetSendMailItem(i)
      if ns.PositiveInt(count) then items[#items + 1] = { id, count } end
    end
  end
  return items
end
-- keep a copy as items are attached, in case Send clears them before we look
ns.On("MAIL_SEND_INFO_UPDATE", function() attached = ReadAttachments() end)

AfterCall("SendMail", function(to)
  local items = ReadAttachments()
  if #items == 0 then items = attached end
  outgoing = (#items > 0) and { to = to, items = items, requestID=ns.mailRequestID, requestIDs=ns.mailRequestIDs } or nil
end)
ns.On("MAIL_SEND_SUCCESS", function()
  local o = outgoing
  outgoing, attached = nil, {}
  if o then ns.AutoFillFor(o.to, o.items, o.requestIDs or o.requestID) end
  ns.mailRequestID,ns.mailRequestIDs = nil,nil
end)
ns.On("MAIL_FAILED", function() outgoing = nil end)
ns.On("MAIL_CLOSED", function() outgoing, attached, ns.mailRequestID, ns.mailRequestIDs = nil, {}, nil,nil end)

local tradeSnap
ns.On("TRADE_ACCEPT_UPDATE", function()
  local bankAlt, officer = ns.IsBankAlt(), ns.IsTrusted(ns.me)
  local crafting = false   -- handing over something we were asked to craft?
  local g = ns.G()
  for _, r in pairs((g and g.requests) or {}) do
    if r.crafter == ns.me and r.status == "approved" then crafting = true break end
  end
  if not bankAlt and not officer and not crafting then return end
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
    if mineID and GetTradePlayerItemInfo then
      local _, _, count = GetTradePlayerItemInfo(slot)
      if ns.PositiveInt(count) then snap.mine[#snap.mine + 1] = { mineID, count } end
    end
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

---------------------------------------------------------------------------
-- Mail helper: with the mailbox open, fill in a request's mail (recipient,
-- subject, the right number of the item from your bags). You press Send;
-- the send itself marks the request filled (see AutoFillFor above).
---------------------------------------------------------------------------
function ns.MailboxOpen()
  return SendMailFrame ~= nil and MailFrame ~= nil and MailFrame:IsShown()
end

local function StartMail(to, subject)
  if not ns.MailIsEmpty() then return false end
  ns.mailRequestID,ns.mailRequestIDs=nil,nil
  if MailFrameTab2 and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject) end
  if ClearCursor then ClearCursor() end
  return true
end

-- Officers mail approved bank requests; a crafter mails what they made.
function ns.MailRequest(rid)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return end
  local crafter = r.crafter and r.crafter == ns.me
  if not crafter and not ns.IsTrusted(ns.me) then return ns.Print("Only officers and the bank character send requested items.") end
  if not r.item then return ns.Print("That's an enchant, so there's nothing to mail. Meet up and use the trade window, then mark it made.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first, then click Mail it again.") end
  if r.status ~= "approved" then return ns.Print(r.crafter and "Accept the request before mailing it." or "Approve the request before mailing it.") end

  local to = r.to or r.who
  local name = ns.ItemName(r.item, true)
  local remaining = ns.Remaining(r)
  if remaining<=0 then return ns.Print("This request has no remaining quantity to mail.") end
  if not StartMail(to, (r.crafter and "Crafted: " or "Guild bank: ") .. name .. " x" .. remaining) then return end
  ns.mailRequestID = rid
  local attached = ns.AttachExactMailItem(r.item, remaining, 1)
  local need = remaining - attached
  if attached == 0 then
    return ns.Print("No items attached. Check that the item is available and unlocked in your bags, and review any preparation message above.")
  end
  if need > 0 then
    ns.Print("Attached " .. attached .. " of " .. remaining .. " " .. ns.ItemLink(r.item) .. ". Check quantities before sending; the remainder stays open.")
  else
    ns.Print("Prepared for " .. to .. ": " .. ns.ItemLink(r.item) .. " x" .. remaining .. ". Check attachment quantities, then click Send.")
  end
end

-- Send a craft request's materials to the crafter: officers when the bank
-- pays, or the requester when they said they'd send them.
function ns.MailCraftMats(rid)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r or not r.crafter then return end
  local mine = r.who == ns.me
  if not mine and not ns.IsTrusted(ns.me) then return ns.Print("Only the requester or an officer sends the materials.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first, then click Mail materials again.") end
  local mats = ns.MatsFor(r.key)
  if #mats == 0 then return ns.Print("The materials for this recipe haven't been shared yet. Ask " .. r.crafter .. " what they need.") end
  local remaining=ns.Remaining(r)
  if remaining<=0 then return ns.Print("This craft request has no remaining quantity.") end
  if not StartMail(r.crafter, "Mats for " .. ns.RequestName(r, true) .. " x" .. remaining) then return end
  local slotIndex, short = 1, {}
  for _, m in ipairs(mats) do
    local want = m.n * remaining
    local got
    got, slotIndex = ns.AttachExactMailItem(m.id, want, slotIndex)
    if got < want then short[#short + 1] = ns.ItemLink(m.id) .. " x" .. (want - got) end
  end
  if #short > 0 then
    ns.Print("Mail ready for " .. r.crafter .. ", but you're short: " .. table.concat(short, ", ") .. ". Check it, then click Send.")
  else
    ns.Print("Materials ready to mail to " .. r.crafter .. ". Check it, then click Send.")
  end
end

-- EPU Guild Tools: mail tools (/epu mailtools, or Member tools -> Mail tools).
--
-- Two buttons on the mailbox:
--   * Take all, on an open mail: takes that mail's gold and every attachment,
--     one at a time, and leaves the rest of the inbox alone.
--   * AH gold, on the inbox: takes only the gold from auction house mail
--     (sales and outbid refunds) and leaves item mail (expired, cancelled and
--     won auctions) where it is.
--
-- Taking mail is a request to the server: the mailbox changes a moment later.
-- So each step takes one thing, then waits until the mailbox shows it gone
-- before taking the next. Nothing here ever pays cash on delivery, and a
-- mail is always found again by who sent it and its subject before anything
-- is taken from it, because the inbox renumbers when a mail is deleted.
local _, ns = ...

local MailTools = {}
ns.MailTools = MailTools

local STEP = 0.4   -- seconds between steps
local WAIT = 3     -- seconds to wait for the server before taking again
local TRIES = 2    -- takes of one thing before giving up on it

local function Slots() return ATTACHMENTS_MAX_RECEIVE or 12 end

local function Settings()
  if not ns.db then return {} end
  ns.db.settings = ns.db.settings or {}
  return ns.db.settings
end

-- "mailTakeAll" (Take all on an open mail) and "mailAHGold" (AH gold on the
-- inbox) are on unless you turn them off.
function MailTools.Enabled(key) return Settings()[key] ~= false end
function MailTools.SetEnabled(key, on)
  Settings()[key] = on and true or false
  MailTools.Refresh()
end

local function Str(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function Num(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return 0 end
  return v
end

local function Count()
  local n, total = 0, 0
  if GetInboxNumItems then n, total = GetInboxNumItems() end
  n = Num(n)
  return n, math.max(n, Num(total))
end

-- One mail's header, or nil if there's no mail at that index.
function MailTools.Header(i)
  if not GetInboxHeaderInfo or not i then return nil end
  local _, _, sender, subject, money, cod, daysLeft, _, _, _, _, canReply = GetInboxHeaderInfo(i)
  sender, subject = Str(sender), Str(subject)
  if not sender and not subject then return nil end
  return { sender = sender or "", subject = subject or "", money = Num(money), cod = Num(cod),
    daysLeft = Num(daysLeft), canReply = canReply }
end
local Header = MailTools.Header

local function Same(h, key)
  return h ~= nil and h.sender == key.sender and h.subject == key.subject
    and math.abs(h.daysLeft - key.daysLeft) < 0.01
end

-- Where the mail is now: at the index it had if it's still there, else the
-- matching mail nearest to it (a new mail at the top moves everything down).
local function Find(key, hint)
  if hint and Same(Header(hint), key) then return hint end
  local best
  for i = 1, (Count()) do
    if Same(Header(i), key) and (not best or math.abs(i - (hint or 1)) < math.abs(best - (hint or 1))) then best = i end
  end
  return best
end

local function FirstAttachment(i)
  for a = 1, Slots() do
    local link = GetInboxItemLink and GetInboxItemLink(i, a)
    if link then return a, link end
  end
end

local function Attachments(i)
  local n = 0
  for a = 1, Slots() do
    if GetInboxItemLink and GetInboxItemLink(i, a) then n = n + 1 end
  end
  return n
end

local function FreeBagSlots()
  local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if not get then return 1 end
  local free = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local n, kind = get(bag)
    -- quivers, soul bags and other special bags only take their own kind
    if (kind == nil or kind == 0) then free = free + Num(n) end
  end
  return free
end

---------------------------------------------------------------------------
-- Telling auction house mail from everyone else's
---------------------------------------------------------------------------
-- The game's own subject lines for auction mail, in the client's language.
local AH_SUBJECTS = { "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
  "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" }

local function Escape(s) return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end

-- "Auction successful: %s" -> "^Auction successful: .+$"
function MailTools.SubjectPattern(template)
  local out, pos = {}, 1
  while true do
    local s, e = template:find("%%%d*%$?s", pos)
    if not s then break end
    out[#out + 1] = Escape(template:sub(pos, s - 1))
    out[#out + 1] = ".+"
    pos = e + 1
  end
  out[#out + 1] = Escape(template:sub(pos))
  return "^" .. table.concat(out) .. "$"
end

local patterns
local function SubjectPatterns()
  if not patterns then
    patterns = {}
    for _, key in ipairs(AH_SUBJECTS) do
      local t = Str(_G[key])
      if t and t ~= "" then patterns[#patterns + 1] = MailTools.SubjectPattern(t) end
    end
  end
  return patterns
end

function MailTools.IsAuctionMail(i, h)
  h = h or Header(i)
  if not h then return false end
  if h.canReply == true then return false end          -- players' mail can be answered; the AH's can't
  if GetInboxInvoiceInfo then
    local kind = Str(GetInboxInvoiceInfo(i))
    if kind and kind ~= "" then return true end        -- sales and wins carry an invoice
  end
  for _, p in ipairs(SubjectPatterns()) do
    if h.subject:match(p) then return true end         -- outbid refunds have no invoice
  end
  return h.sender:find("Auction House", 1, true) ~= nil
end

---------------------------------------------------------------------------
-- The job that's running (one at a time)
---------------------------------------------------------------------------
local job

function MailTools.Busy(kind) return job ~= nil and (kind == nil or job.kind == kind) end

local function Who(sender)
  sender = sender ~= "" and sender or "this"
  return sender:sub(-1) == "s" and (sender .. "'") or (sender .. "'s")
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function Finish(msg)
  job = nil
  MailTools.status = msg
  if msg then ns.Print(msg) end
  MailTools.Refresh()
end

local Step
local function Schedule(j)
  C_Timer.After(STEP, function() if job == j then Step(j) end end)
end

-- Bags full or a unique item: the server says so with an error message.
local BLOCKING = { ERR_INV_FULL = true, ERR_ITEM_MAX_COUNT = true, ERR_INVENTORY_FULL = true }
local function OnError(...)
  if not job then return end
  for n = 1, select("#", ...) do
    local v = Str((select(n, ...)))
    if v then
      for key in pairs(BLOCKING) do
        if _G[key] and v == _G[key] then job.blocked = v; return end
      end
    end
  end
end

-- What one mail still holds, for the summary when Take all stops early.
local function Left(i)
  if not i then return "" end
  local h, n = Header(i), Attachments(i)
  local parts = {}
  if h and h.money > 0 then parts[#parts + 1] = ns.MoneyText(h.money) end
  if n > 0 then parts[#parts + 1] = Plural(n, "item") end
  return #parts > 0 and (" " .. table.concat(parts, " and ") .. " still in it.") or ""
end

local function OneSummary(j)
  local got = {}
  if j.money > 0 then got[#got + 1] = ns.MoneyText(j.money) end
  if j.items > 0 then got[#got + 1] = Plural(j.items, "item") end
  if #got == 0 then return "Nothing left to take from " .. Who(j.key.sender) .. " mail." end
  return "Took " .. table.concat(got, " and ") .. " from " .. Who(j.key.sender) .. " mail."
end

-- A take is done once the mailbox shows it gone. A mail that's emptied is
-- often deleted, so a mailbox one mail shorter counts as done too.
local function Settled(j)
  local p = j.pending
  local n = Count()
  if n < p.count then return true, nil end
  local i = Find(j.key, p.index)
  if not i then return true, nil end
  local h = Header(i)
  if p.slot then return not (GetInboxItemLink and GetInboxItemLink(i, p.slot)), i end
  return h.money == 0, i
end

-- Handle the take that's waiting on the server. Returns true if the job
-- should wait for the next step.
local function Waiting(j)
  local p = j.pending
  if not p then return false end
  local done, i = Settled(j)
  if done then
    if p.slot then j.items = j.items + 1 else j.money = j.money + p.money; j.mails = (j.mails or 0) + 1 end
    j.pending = nil
    if i then j.index = i end
    return false
  end
  if GetTime() < p.deadline then Schedule(j); return true end
  if p.tries >= TRIES then
    j.pending = nil
    return false, p
  end
  p.tries, p.deadline = p.tries + 1, GetTime() + WAIT
  if p.slot then TakeInboxItem(i, p.slot) else TakeInboxMoney(i) end
  Schedule(j)
  return true
end

local function TakeMoney(j, i, h)
  j.pending = { index = i, money = h.money, count = (Count()), tries = 1, deadline = GetTime() + WAIT }
  TakeInboxMoney(i)
  Schedule(j)
end

-- Take all: one mail's gold, then each attachment.
local function StepOne(j)
  if not ns.MailboxOpen() then return Finish("The mailbox closed, so Take all stopped. " .. OneSummary(j)) end
  if j.blocked then
    -- the server refused the last take (bags full, or a unique item you already carry)
    return Finish(j.blocked .. " Take all stopped. " .. OneSummary(j) .. Left(Find(j.key, j.index)))
  end
  local waiting, failed = Waiting(j)
  if waiting then return end
  if failed then
    return Finish("The server didn't hand over " .. (failed.slot and "an item" or "the gold")
      .. " from " .. Who(j.key.sender) .. " mail, so Take all stopped. " .. OneSummary(j) .. Left(Find(j.key, j.index)))
  end
  local n = Count()
  if j.count and n < j.count then return Finish(OneSummary(j)) end   -- emptied and deleted
  local i = Find(j.key, j.index)
  if not i then return Finish(OneSummary(j)) end
  j.index, j.count = i, n
  local h = Header(i)
  if h.cod > 0 then
    return Finish("That mail is cash on delivery (" .. ns.MoneyText(h.cod) .. "). EPU never pays COD: "
      .. "use the mail's Accept button if you want it.")
  end
  if h.money > 0 then return TakeMoney(j, i, h) end
  local slot = FirstAttachment(i)
  if not slot then return Finish(OneSummary(j)) end
  if FreeBagSlots() < 1 then
    return Finish("Your bags are full. Take all stopped. " .. OneSummary(j) .. Left(i))
  end
  j.pending = { index = i, slot = slot, count = n, tries = 1, deadline = GetTime() + WAIT }
  TakeInboxItem(i, slot)
  Schedule(j)
end

local function Skipped(j, h)
  for _, key in ipairs(j.skip) do if Same(h, key) then return true end end
  return false
end

local function AHSummary(j)
  local shown, total = Count()
  local itemMail = 0
  for i = 1, shown do
    local h = Header(i)
    if h and MailTools.IsAuctionMail(i, h) and Attachments(i) > 0 then itemMail = itemMail + 1 end
  end
  local msg
  if j.money > 0 then
    msg = "Collected " .. ns.MoneyText(j.money) .. " from " .. Plural(j.mails or 0, "auction house mail") .. "."
  else
    msg = "No auction house gold to collect."
  end
  if itemMail > 0 then msg = msg .. " " .. Plural(itemMail, "auction mail") .. " with items stayed in your inbox." end
  if #j.skip > 0 then msg = msg .. " " .. Plural(#j.skip, "mail") .. " didn't hand over gold; try again in a moment." end
  if total > shown then msg = msg .. " More mail is waiting on the server: close and reopen the mailbox, then collect again." end
  return msg
end

-- AH gold: from the bottom of the inbox up, so a deleted mail never moves
-- one we haven't looked at yet.
local function StepAH(j)
  if not ns.MailboxOpen() then return Finish("The mailbox closed. " .. AHSummary(j)) end
  local waiting, failed = Waiting(j)
  if waiting then return end
  if failed then j.skip[#j.skip + 1] = j.lastKey end
  for i = (Count()), 1, -1 do
    local h = Header(i)
    if h and h.money > 0 and h.cod == 0 and not Skipped(j, h) and MailTools.IsAuctionMail(i, h) then
      j.key, j.lastKey = h, h
      return TakeMoney(j, i, h)
    end
  end
  Finish(AHSummary(j))
end

Step = function(j)
  local ok, err = pcall(j.kind == "one" and StepOne or StepAH, j)
  if not ok then Finish("Mail tools stopped: " .. tostring(err)) end
end

local function Start(j)
  j.money, j.items, j.mails, j.skip = 0, 0, 0, {}
  job = j
  MailTools.status = nil
  MailTools.Refresh()
  Step(j)
end

function MailTools.Stop()
  if not job then return end
  local j = job
  Finish("Stopped. " .. (j.kind == "one" and OneSummary(j) or AHSummary(j)))
end

-- Take everything from the mail at this inbox index.
function MailTools.TakeAll(index)
  if job then return ns.Print("EPU is already taking mail. Wait for it to finish, or press Stop.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first.") end
  local h = Header(index)
  if not h then return ns.Print("That mail isn't there any more.") end
  Start({ kind = "one", key = h, index = index })
end

function MailTools.CollectAHGold()
  if job then return ns.Print("EPU is already taking mail. Wait for it to finish, or press Stop.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first, then collect AH gold.") end
  Start({ kind = "ah", key = { sender = "", subject = "", daysLeft = 0 } })
end

local function OpenIndex()
  local i = InboxFrame and InboxFrame.openMailID
  if type(i) == "number" and OpenMailFrame and OpenMailFrame:IsShown() then return i end
end

---------------------------------------------------------------------------
-- Buttons on the mailbox. They're made the first time the mailbox opens,
-- outside Blizzard's frames so they never cover its buttons.
---------------------------------------------------------------------------
local takeBtn, ahBtn

local function Make(parent, label, w)
  local b = ns.InterfaceButton(parent, label, w, 22)
  b:SetFrameStrata("HIGH")
  return b
end

local function EnsureButtons()
  if not takeBtn and OpenMailFrame and ns.InterfaceButton then
    takeBtn = Make(OpenMailFrame, "Take all", 96)
    takeBtn:SetPoint("BOTTOMRIGHT", OpenMailFrame, "TOPRIGHT", 0, 4)
    takeBtn:SetScript("OnClick", function()
      if MailTools.Busy("one") then return MailTools.Stop() end
      local i = OpenIndex()
      if i then MailTools.TakeAll(i) end
    end)
    if OpenMailFrame.HookScript then OpenMailFrame:HookScript("OnShow", function() MailTools.Refresh() end) end
  end
  if not ahBtn and InboxFrame and MailFrame and ns.InterfaceButton then
    ahBtn = Make(InboxFrame, "Collect AH gold", 128)
    ahBtn:SetPoint("BOTTOMRIGHT", MailFrame, "TOPRIGHT", 0, 4)
    ahBtn.tip = "Takes the gold from auction house mail (sales and outbid refunds). Expired, cancelled and won auctions stay in your inbox."
    ahBtn:SetScript("OnClick", function()
      if MailTools.Busy("ah") then return MailTools.Stop() end
      MailTools.CollectAHGold()
    end)
  end
  MailTools.takeButton, MailTools.ahButton = takeBtn, ahBtn
end

local win

function MailTools.Refresh()
  if takeBtn then
    takeBtn:SetShown(MailTools.Enabled("mailTakeAll"))
    local i = OpenIndex()
    local h = i and Header(i)
    takeBtn.tip, takeBtn.disabledTip = "Takes this mail's gold and every item, one at a time. The rest of your inbox stays.", nil
    if MailTools.Busy("one") then
      takeBtn:SetLabel("Stop"); takeBtn:SetEnabled(true)
    else
      takeBtn:SetLabel("Take all")
      local why
      if job then why = "EPU is collecting auction house gold."
      elseif not h then why = "Open a mail first."
      elseif h.cod > 0 then why = "Cash on delivery: EPU never pays COD. Use the mail's Accept button."
      elseif h.money == 0 and Attachments(i) == 0 then why = "Nothing left to take." end
      takeBtn.disabledTip = why
      takeBtn:SetEnabled(why == nil)
    end
  end
  if ahBtn then
    ahBtn:SetShown(MailTools.Enabled("mailAHGold"))
    if MailTools.Busy("ah") then ahBtn:SetLabel("Stop"); ahBtn:SetEnabled(true)
    else
      ahBtn:SetLabel("Collect AH gold")
      ahBtn.disabledTip = job and "EPU is taking another mail." or nil
      ahBtn:SetEnabled(job == nil)
    end
  end
  if win and win:IsShown() then win:Refresh() end
end

---------------------------------------------------------------------------
-- Window (/epu mailtools, or Member tools -> Mail tools)
---------------------------------------------------------------------------
function ns.OpenMailTools()
  if not win then
    local C = ns.InterfaceColors
    win = ns.InterfaceWindow("EPUGuildMailTools", UIParent, "Mail tools", 460, 300)
    local function Text(y, col)
      local f = ns.InterfaceFont(win, 11, col or C.text)
      f:SetPoint("TOPLEFT", 14, y); f:SetWidth(432)
      f:SetJustifyH("LEFT")
      if f.SetWordWrap then f:SetWordWrap(true) end
      return f
    end
    local function Toggle(y, key, label, tip)
      local b = ns.InterfaceButton(win, label, 200, 22)
      b:SetPoint("TOPLEFT", 14, y)
      b.tip = tip
      b:SetScript("OnClick", function() MailTools.SetEnabled(key, not MailTools.Enabled(key)) end)
      return b
    end
    win.takeText = Text(-46)
    win.takeText:SetText("|cffffffffTake all|r on an open mail takes that mail's gold and every item, one at a time, "
      .. "and leaves the rest of your inbox alone. It stops when your bags are full and never pays cash on delivery.")
    win.takeToggle = Toggle(-94, "mailTakeAll", "Take all button", "Show Take all above a mail you open.")
    win.ahText = Text(-128)
    win.ahText:SetText("|cffffffffCollect AH gold|r on the inbox takes only the gold from auction house mail "
      .. "(sales and outbid refunds). Expired, cancelled and won auctions stay in your inbox.")
    win.ahToggle = Toggle(-164, "mailAHGold", "AH gold button", "Show Collect AH gold above the inbox.")
    win.collect = ns.InterfaceButton(win, "Collect AH gold now", 160, 22, "accent")
    win.collect:SetPoint("TOPLEFT", 14, -200)
    win.collect:SetScript("OnClick", function()
      if MailTools.Busy("ah") then MailTools.Stop() else MailTools.CollectAHGold() end
    end)
    win.status = Text(-232, C.gold)

    function win:Refresh()
      self.takeToggle:SetOn(MailTools.Enabled("mailTakeAll"))
      self.takeToggle:SetLabel("Take all button: " .. (MailTools.Enabled("mailTakeAll") and "on" or "off"))
      self.ahToggle:SetOn(MailTools.Enabled("mailAHGold"))
      self.ahToggle:SetLabel("AH gold button: " .. (MailTools.Enabled("mailAHGold") and "on" or "off"))
      if MailTools.Busy("ah") then
        self.collect:SetLabel("Stop"); self.collect:SetEnabled(true)
      else
        self.collect:SetLabel("Collect AH gold now")
        local why = job and "EPU is taking another mail." or (not ns.MailboxOpen() and "Open a mailbox first.") or nil
        self.collect.disabledTip = why
        self.collect:SetEnabled(why == nil)
      end
      self.status:SetText(MailTools.status or "")
    end
  end
  win:Refresh()
  win:Show()
end

if ns.On then
  ns.On("MAIL_SHOW", function() EnsureButtons(); MailTools.Refresh() end)
  ns.On("MAIL_INBOX_UPDATE", function() MailTools.Refresh() end)
  ns.On("MAIL_CLOSED", function()
    if job then MailTools.Stop() else MailTools.Refresh() end
  end)
  ns.On("UI_ERROR_MESSAGE", OnError)
end

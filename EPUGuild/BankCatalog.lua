-- Requestable items come from actual bank inventory/history, never wish lists
-- or the game's complete item database. History carries no stock quantity.
local ADDON,ns=...
local GetItemInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant=(C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local function HistoricalItemClass(id)
  local cached=ns.db and ns.db.itemClass and ns.db.itemClass[id]
  local class=cached and cached[1]
  if not class and GetItemInfoInstant then class=select(6,GetItemInfoInstant(id)) end
  if not class and GetItemInfo then class=select(12,GetItemInfo(id)) end
  return class
end
function ns.BankHistory(snapshot,items,holder)
  local seen={}
  for id,value in pairs((snapshot or {}).seen or {}) do if ns.PositiveInt(id) and value==true then seen[id]=true end end
  for id,n in pairs((snapshot or {}).items or {}) do if ns.PositiveInt(id) and type(n)=='number' and n>0 then seen[id]=true end end
  for id,n in pairs(items or {}) do if ns.PositiveInt(id) and type(n)=='number' and n>0 then seen[id]=true end end
  if holder then for _,d in pairs((ns.G() or {}).donations or {}) do
    if d.to==holder and ns.PositiveInt(d.item) and (tonumber(d.n) or 0)>0 then seen[d.item]=true end
  end end
  return seen
end
function ns.BankCatalog()
  local catalog={}; local g=ns.G(); if not g then return catalog end
  for holder,s in pairs(g.bank) do for id in pairs(ns.BankHistory(s,nil,holder)) do catalog[id]=true end end
  -- Donation records can predate the new persistent history field.
  for _,d in pairs(g.donations) do
    if (g.bank[d.to] or d.to==ns.GB_KEY) and ns.PositiveInt(d.item) and (tonumber(d.n) or 0)>0 then catalog[d.item]=true end
  end
  for id in pairs(catalog) do
    if ns.BankCount(id)<=0 then
      local class=HistoricalItemClass(id)
      -- Keep the history for future restocking, but do not advertise sold-out
      -- gear. Unknown historical items wait for item metadata to load.
      if not class or class==2 or class==4 then catalog[id]=nil end
    end
  end
  return catalog
end
function ns.CanBankRequest(id)
  return ns.PositiveInt(id) and ns.BankCatalog()[id]==true
end
function ns.BankRequestStock(id)
  local held,asked=ns.BankCount(id),0
  for _,r in pairs((ns.G() or {}).requests or {}) do
    if ns.IsActiveRequest(r) then
      if not r.crafter and r.item==id then asked=asked+ns.Remaining(r)
      elseif r.crafter and r.status=='approved' and r.mats=='bank' then
        for _,m in ipairs(ns.MatsFor(r.key)) do if m.id==id then asked=asked+m.n*ns.Remaining(r) end end
      end
    end
  end
  return held,asked,math.max(0,held-asked)
end
function ns.BankRequestAvailability(id)
  local held,asked,free=ns.BankRequestStock(id)
  return held..' in bank · '..free..' available'..(asked>0 and (' · '..asked..' already requested') or '')..(held==0 and ' · Out of stock; requests wait for restock' or '')
end
function ns.RequestRestock(rid)
  local g=ns.G(); local r=g and g.requests[rid]
  if not r or r.crafter or not ns.IsActiveRequest(r) then return 0 end
  local remaining=ns.Remaining(r); local pool=ns.BankCount(r.item); local queue={}
  for id,v in pairs(g.requests) do
    if ns.IsActiveRequest(v) and not v.crafter and v.item==r.item then queue[#queue+1]={id=id,r=v}
    elseif v.crafter and v.status=='approved' and v.mats=='bank' then
      for _,m in ipairs(ns.MatsFor(v.key)) do if m.id==r.item then pool=math.max(0,pool-m.n*ns.Remaining(v)) end end
    end
  end
  table.sort(queue,function(a,b)
    local x,y=a.r.status=='approved',b.r.status=='approved'
    if x~=y then return x end
    if (a.r.t or 0)~=(b.r.t or 0) then return (a.r.t or 0)<(b.r.t or 0) end
    return a.id<b.id
  end)
  for _,entry in ipairs(queue) do
    local need=ns.Remaining(entry.r)
    if entry.id==rid then return math.max(0,remaining-pool) end
    pool=math.max(0,pool-need)
  end
  return remaining
end

---------------------------------------------------------------------------
-- Sort the bank: who should get each recipe, which materials help a
-- guildmate skill up or make a profit, and what is only worth selling.
---------------------------------------------------------------------------
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local needCache = {}
local scanner

local function SkillPattern()
  local fmt = type(ITEM_MIN_SKILL) == "string" and ITEM_MIN_SKILL or "Requires %s (%d)"
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
  return "^" .. p .. "$"
end

local function TooltipLines(id)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        if type(line.leftText) == "string" and not (issecretvalue and issecretvalue(line.leftText)) then out[#out + 1] = line.leftText end
      end
      return out
    end
  end
  if not CreateFrame or not GameTooltip then return out end
  scanner = scanner or CreateFrame("GameTooltip", "EPUGuildScanTooltip", UIParent, "GameTooltipTemplate")
  if not scanner.SetItemByID then return out end
  scanner:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  pcall(scanner.SetItemByID, scanner, id)
  for i = 1, (scanner.NumLines and scanner:NumLines() or 0) do
    local fs = _G["EPUGuildScanTooltipTextLeft" .. i]
    local text = fs and fs:GetText()
    if type(text) == "string" then out[#out + 1] = text end
  end
  scanner:Hide()
  return out
end

-- "Requires Tailoring (75)" from a recipe's tooltip: profession, skill.
function ns.RecipeRequirement(id)
  local c = needCache[id]
  if c then return c.prof, c.skill end
  local pattern = SkillPattern()
  for _, text in ipairs(TooltipLines(id)) do
    local prof, skill = text:match(pattern)
    skill = tonumber(skill)
    if prof and skill then needCache[id] = {prof = prof, skill = skill}; return prof, skill end
  end
end

local function Short(name) return (name or "?"):match("^(%S+)") or name end

-- Guildmates with a profession, and whether each knows a recipe.
local function Candidates(prof, entry, need)
  local g = ns.G()
  local knows = {}
  for _, c in ipairs(entry and entry.crafters or {}) do if c.prof == prof then knows[c.who] = true end end
  local out = {}
  for who, c in pairs(g and g.crafters or {}) do
    local skill = c.profs and tonumber(c.profs[prof])
    if skill and ns.InGuild(who) then
      local rec = g.recipes and g.recipes[who]
      local scanned = rec and rec.profs and rec.profs[prof] ~= nil
      out[#out + 1] = {
        who = who, skill = skill, knows = knows[who] == true, scanned = scanned or knows[who] == true,
        canLearn = not need or skill >= need, designated = ns.IsDesignated(who, prof),
        online = ns.roster[who] ~= nil and ns.roster[who].online == true,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.skill ~= b.skill then return a.skill > b.skill end
    if a.designated ~= b.designated then return a.designated end
    if a.online ~= b.online then return a.online end
    return a.who < b.who
  end)
  return out
end

-- Orange/yellow recipes per reagent: [itemID] = { {who, prof, name, color} }.
local function SkillUpUsers()
  local g, users = ns.G(), {}
  if not g then return users end
  for _, e in ipairs(ns.RecipeIndex()) do
    local m = g.mats[e.key]
    if m and type(m.r) == "table" then
      for _, c in ipairs(e.crafters) do
        if (c.diff == "o" or c.diff == "y") and ns.InGuild(c.who) then
          local name = e.item and ns.ItemName(e.item, true) or e.name
          for i = 1, #m.r - 1, 2 do
            local id = tonumber(m.r[i])
            if id then
              users[id] = users[id] or {}
              local list, dup = users[id], false
              for _, u in ipairs(list) do if u.who == c.who and u.name == name then dup = true end end
              if not dup and #list < 30 then list[#list + 1] = {who = c.who, prof = c.prof, name = name, color = c.diff} end
            end
          end
        end
      end
    end
  end
  for _, list in pairs(users) do
    table.sort(list, function(a, b)
      if a.color ~= b.color then return a.color == "o" end
      return a.who < b.who
    end)
  end
  return users
end

local function Keep(g, id)
  local v = g.needs and g.needs.list and g.needs.list[id]
  return type(v) == "table" and (tonumber(v.q) or 0) or tonumber(v) or 0
end

-- { recipes = {...}, mats = {...}, sell = {...}, priced = bool, source = key }
function ns.BankSortPlan()
  local g = ns.G()
  local plan = {recipes = {}, mats = {}, sell = {}, source = ns.MarketSourceKey and ns.MarketSourceKey()}
  if not g then return plan end
  local totals, holders = {}, {}
  local function add(id, n, where)
    id, n = tonumber(id), tonumber(n)
    if not id or not n or n <= 0 then return end
    totals[id] = (totals[id] or 0) + n
    holders[id] = holders[id] or {}
    holders[id][where] = (holders[id][where] or 0) + n
  end
  for alt, s in pairs(g.bank) do
    if not s.retired then for id, n in pairs(type(s.items) == "table" and s.items or {}) do add(id, n, alt) end end
  end
  for id, n in pairs(ns.InboxItems and ns.InboxItems() or {}) do add(id, n, ns.me .. "'s mailbox") end
  local users = SkillUpUsers()
  local uses = ns.ProfitableUses and ns.ProfitableUses() or {}
  local payout = (ns.FACTION_PAYOUT or 95) / 100
  for id, count in pairs(totals) do
    ns.SliceCheck()
    local name, _, quality, _, _, _, subType, _, _, _, vendor, classID = ItemInfo(id)
    local ah, info = nil, {}
    if ns.ItemMarketValue then ah, info = ns.ItemMarketValue(id) end
    local unit = math.max(ah and math.floor(ah * payout) or 0, tonumber(vendor) or 0)
    local _, asked = ns.BankRequestStock(id)
    local surplus = math.max(0, count - Keep(g, id) - (asked or 0))
    local base = {item = id, name = name or ns.ItemName(id, true), count = count, holders = holders[id], quality = quality,
      ah = ah, basis = info and info.basis, vendor = tonumber(vendor) or 0, unit = unit, surplus = surplus}
    local placed = false
    if classID == RECIPE and name then
      local prof, need = ns.RecipeRequirement(id)
      prof = prof or subType
      local entry = ns.RecipeByName(name:match("^[^:]+:%s*(.+)$") or name)
      local list = Candidates(prof, entry, need)
      local best, maybe, closest, everyone = nil, nil, nil, #list > 0
      for _, c in ipairs(list) do
        if not c.knows then everyone = false end
        if c.canLearn and not c.knows and c.scanned and not best then best = c end
        if c.canLearn and not c.scanned and not maybe then maybe = c end
        if not c.canLearn and not c.knows and not closest then closest = c end
      end
      local r = setmetatable({prof = prof, need = need, candidates = list, best = best, maybe = maybe, closest = closest}, {__index = base})
      if best or maybe or closest then
        r.give = best or maybe or closest
        r.why = best and "doesn't know it" or maybe and "hasn't shared recipes yet" or ("needs " .. need .. ", has " .. closest.skill)
        plan.recipes[#plan.recipes + 1] = r
        placed = true
      elseif everyone then
        r.reason = "Everyone with " .. tostring(prof) .. " already knows it"
      else
        r.reason = "Nobody in the guild has " .. tostring(prof)
      end
      if not placed and unit > 0 then plan.sell[#plan.sell + 1] = r; placed = true end
    end
    if not placed and (users[id] or uses[id]) then
      local r = setmetatable({users = users[id] or {}, use = uses[id]}, {__index = base})
      plan.mats[#plan.mats + 1] = r
      placed = true
    end
    if not placed and surplus > 0 and unit > 0 then
      plan.sell[#plan.sell + 1] = setmetatable({value = surplus * unit}, {__index = base})
    end
  end
  for _, r in ipairs(plan.sell) do r.value = r.value or r.surplus * r.unit end
  table.sort(plan.recipes, function(a, b)
    local ga, gb = a.best and 2 or a.maybe and 1 or 0, b.best and 2 or b.maybe and 1 or 0
    if ga ~= gb then return ga > gb end
    return (a.name or "") < (b.name or "")
  end)
  table.sort(plan.mats, function(a, b)
    if #a.users ~= #b.users then return #a.users > #b.users end
    return (a.name or "") < (b.name or "")
  end)
  table.sort(plan.sell, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.name or "") < (b.name or "")
  end)
  return plan
end

-- Reserve on the sending character, not against possibly stale remote stock.
-- This is deliberately conservative when several characters hold the item.
function ns.BankSortMailLimit(item)
  local g = ns.G()
  if not g then return 0 end
  local have = ns.ItemCount(item)
  local _, asked = ns.BankRequestStock(item)
  return math.max(0, have - Keep(g, item) - (asked or 0))
end

-- Put a bank item into a mail to a guildmate, ready to check and send.
function ns.MailBankItem(target, item, qty)
  if not ns.PositiveInt(qty) then return ns.Print("Choose a positive whole-number quantity before preparing bank mail.") end
  target = ns.Member(target) or target
  local have = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item)) or (GetItemCount and GetItemCount(item)) or 0
  if have <= 0 then return ns.Print("This character isn't carrying " .. ns.ItemName(item, true) .. ". Log in on whoever holds it and take it out of the bank first.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first, then click Mail again.") end
  if not ns.MailIsEmpty() then return end
  local available = ns.BankSortMailLimit(item)
  if qty > available then
    return ns.Print("Only " .. available .. " available from your bags after keeping needs and open requests. Choose a smaller quantity; use the request's mail helper to fulfill a reserved request.")
  end
  if MailFrameTab2 and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(target) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("From the guild bank: " .. ns.ItemName(item, true)) end
  if ClearCursor then ClearCursor() end
  local n = ns.AttachExactMailItem(item, qty, 1)
  if n == 0 then return ns.Print("Couldn't attach it. Check it's unlocked and not soulbound.") end
  ns.Print("Attached " .. n .. "x " .. ns.ItemName(item, true) .. " for " .. Short(target) .. ". Check the mail, then click Send.")
  return n
end

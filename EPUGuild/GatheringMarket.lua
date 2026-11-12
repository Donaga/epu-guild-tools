local ADDON, ns = ...

-- Herbalism skill thresholds for standard herbs. Unknown acquisition
-- requirements stay visible in the full catalog and out of the skill filter.
local herbs = {
  {2447,1}, {765,1}, {2449,15}, {785,50}, {2450,70}, {2452,50},
  {3820,85}, {2453,100}, {3355,115}, {3369,120}, {3356,125}, {3357,150},
  {3818,160}, {3821,170}, {3819,195}, {3358,185}, {4625,205},
  {8831,210}, {8153,210}, {8836,220}, {8838,230}, {8839,235}, {8845,245},
  {8846,250}, {13463,270}, {13464,260}, {13465,280}, {13466,285},
  {13467,290}, {13468,300}, {19726,300}, {248821}, {248822}, {248823},
}
local gatherCatalogs = {
  [182] = {items = herbs, thresholds = true},
  [186] = {thresholds = true, items = {
    {2770,1}, {2835,1}, {2771,65}, {2836,65}, {2775,75}, {2772,125},
    {2838,125}, {2776,155}, {3858,175}, {7912,175}, {7911,230},
    {11370,230}, {10620,245}, {12365,245},
  }},
  [393] = {hint = "Skinning skill depends on the creature", items = {
    {2934}, {2318}, {2319}, {4234}, {4304}, {8170}, {783}, {4232},
    {4235}, {8169}, {8171}, {15417}, {15419}, {15422}, {15423}, {17012},
  }},
  [356] = {hint = "Fishing skill depends on the water or pool", items = {
    {6291}, {6289}, {6308}, {6303}, {6361}, {6362}, {6358}, {6359}, {6522},
    {13422}, {13753}, {13754}, {13755}, {13756}, {13757}, {13758}, {13759},
    {13760}, {13888}, {13889}, {13890}, {13891}, {13893}, {21071}, {21153},
  }},
}
local gatherOrder = {182, 186, 393, 356}
local circle = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FACTION_PAYOUT = 95
local buySorts = {
  {value = "opportunity", label = "Profit + demand"},
  {value = "volume", label = "Sold/day"},
  {value = "profit", label = "Profit/craft"},
  {value = "roi", label = "Profit %"},
  {value = "price", label = "Sale price"},
}
-- Gathering professions have no recipes to scan. Mining stays for Smelting.
local gatheringOnly = {[182] = true, [356] = true, [393] = true}
local THIN_PROFIT, THIN_ROI = 100, 10        -- under 1s or 10% per craft is a thin margin
local SLOW_DAYS = 3                          -- more than this many days of stock listed
local STALE_SECONDS = 6 * 3600
local SKILL_CHANCE = {o = 1, y = .75}        -- rough skill-up odds for orange and yellow recipes
local highlightLabels = {
  profit = "Top profit", roi = "Top %", volume = "Top seller", opportunity = "Top pick",
  price = "Top price", score = "Cheapest skill-up",
}
local tagColors = {
  ["Sells now"] = "6fdc8c", Slow = "ffb347", ["Thin margin"] = "ffb347",
  ["No listings"] = "ff8a65", Loss = "ff6b6b",
}
local sources = {
  { key = "ledger", title = "AHledger", hint = "Forever market · estimated sales/day", plotHint = " · hollow circles have no sell-through data" },
  { key = "tsm", title = "TSM", hint = "TSM regional averages", plotHint = " · bubble area shows sell-through" },
  { key = "auctionator", title = "Auctionator", hint = "Last scanned listing prices · volume and sell-through unavailable" },
}

---------------------------------------------------------------------------
-- Guild focus: professions officers want more of, with an optional skill goal.
-- One record per profession, synced like other guild records (officers only).
---------------------------------------------------------------------------
ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS + 1] = "guildFocus"
local PRIMARY = {Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
  Leatherworking = true, Mining = true, Skinning = true, Tailoring = true}
local FOCUS_GOALS = {75, 150, 225, 300}

local function KnownProfession(name)
  for _, p in ipairs(ns.ALL_PROFS or {}) do if p == name then return true end end
  return false
end

local function ValidFocus(id, r)
  return type(id) == "string" and KnownProfession(id) and type(r) == "table" and ns.StampOK(r.t)
    and r.t <= ns.Now() + 300 and type(r.on) == "boolean" and type(r.goal) == "number"
    and r.goal >= 0 and r.goal <= 300 and r.goal % 1 == 0
    and (r.by == nil or (ns.IsReadableString(r.by) and #r.by <= 80))
end

local function FocusStore()
  local g = ns.CasualStore and ns.CasualStore()
  return g and g.guildFocus
end

function ns.MergeGuildFocus(sender, b, trusted)
  if not trusted or type(b) ~= "table" or type(b.guildFocus) ~= "table" then return false end
  local store = FocusStore()
  if not store then return false end
  local changed = false
  for id, r in pairs(b.guildFocus) do
    if ValidFocus(id, r) and ns.Newer(r, store[id], "t") then
      store[id] = {on = r.on, goal = r.goal, t = r.t, by = r.by}
      changed = true
    end
  end
  if changed then ns.Changed() end
  return changed
end

-- goal: nil removes the profession from the focus, 0 is a focus without a skill goal.
function ns.SetGuildFocus(prof, goal)
  if not ns.IsTrusted(ns.me) then return ns.Print("Only officers can set the guild focus.") end
  local store = FocusStore()
  if not store or not KnownProfession(prof) then return end
  local cur = store[prof]
  local r = {on = goal ~= nil, goal = goal or 0, t = ns.NextVersion(cur and cur.t), by = ns.me}
  store[prof] = r
  ns.Send("D", {guildFocus = {[prof] = r}})
  ns.Changed()
  if ns.Log then
    ns.Log(goal and ("Set the guild focus: " .. prof .. (goal > 0 and (", skill goal " .. goal) or ""))
      or ("Removed " .. prof .. " from the guild focus"))
  end
end

function ns.GuildFocusOf(prof)
  local store = FocusStore()
  local r = store and store[prof]
  return r and r.on and r or nil
end

-- { {prof, goal, players, atGoal, primary} } for each focused profession. Players are
-- counted once across their alts, at their best character's skill.
function ns.GuildFocus()
  local g, out = ns.G(), {}
  for prof, r in pairs(FocusStore() or {}) do
    if r.on then
      local best = {}
      for who, c in pairs(g and g.crafters or {}) do
        local skill = ns.InGuild(who) and tonumber(c.profs and c.profs[prof])
        if skill then
          local main = ns.MainOf and ns.MainOf(who) or who
          if not best[main] or skill > best[main] then best[main] = skill end
        end
      end
      local players, atGoal = 0, 0
      for _, skill in pairs(best) do
        players = players + 1
        if r.goal > 0 and skill >= r.goal then atGoal = atGoal + 1 end
      end
      out[#out + 1] = {prof = prof, goal = r.goal, players = players, atGoal = atGoal, primary = PRIMARY[prof] == true}
    end
  end
  table.sort(out, function(a, b) return a.prof < b.prof end)
  return out
end

function ns.GuildFocusChoices()
  local items = {{value = false, label = "Not a focus"}, {value = 0, label = "Focus, no skill goal"}}
  for _, goal in ipairs(FOCUS_GOALS) do items[#items + 1] = {value = goal, label = "Focus, skill goal " .. goal} end
  return items
end

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

local function VendorPrice(item)
  local price = ns.VENDOR_PRICES and ns.VENDOR_PRICES[item]
  if type(price) == "number" and price > 0 then return price end
end

-- Returns the unit price and a table describing where it came from.
-- Selling uses the current lowest listing: the profit available right now.
-- Ingredients use the lowest listing (or the budget price), or a vendor when cheaper.
local function Market(source, item, reagent)
  local price, info = nil, {}
  if source == "ledger" then
    local row = Call(AHledgerAPI and AHledgerAPI.GetPrice, item)
    if type(row) == "table" then
      local low, median = Number(row.minBuyout, 1, 1e12), Number(row.median, 1, 1e12)
      if reagent then
        price = low
        if price and reagent == "budget" then price = math.max(price, median or price) end
      else
        -- A lone overpriced listing must not inflate profit, so never sell above the median.
        price = low and median and math.min(low, median) or low or median
        info.basis = low and (median and low > median and "median" or "low") or (median and "unlisted") or nil
      end
      info.volume = Number(row.soldPerDay, 0, 1e9)
      info.listed = Number(row.quantity, 0, 1e9)
      if ns.IsReadableString(row.market) then info.market = row.market end
      info.updated = Number(row.updated, 1, 5e9)
      if not info.updated and ns.IsReadableString(row.updated) then info.updated = row.updated end
      info.snapshot = Readable(row.snapshot) and row.snapshot == true
    end
  elseif source == "tsm" then
    local read = TSM_API and TSM_API.GetCustomPriceValue
    local key = "i:" .. item
    if reagent then
      price = Call(read, "dbregionmarketavg", key)
    else
      price = Number(Call(read, "dbminbuyout", key), 1, 1e12)
      info.basis = price and "low" or "average"
      price = price or Call(read, "dbregionsaleavg", key)
      info.volume = Number(Call(read, "dbregionsoldperday", key), 0, 1e9)
      info.rate = Number(Call(read, "dbregionsalerate", key), 0, 1)
    end
  else
    local api = AuctionatorAPI()
    price = Call(api and api.GetAuctionPriceByItemID, ADDON, item)
    if not reagent then info.basis = "low" end
    info.ageDays = Number(Call(api and api.GetAuctionAgeByItemID, ADDON, item), 0, 100000)
  end
  price = Number(price, 1, 1e12)
  if not price then info.basis = nil end
  if reagent then
    local vendor = VendorPrice(item)
    if vendor and (not price or vendor <= price) then price, info.vendor = vendor, true end
  end
  return price, info
end

-- One short verdict a member can act on without reading the numbers.
local function Verdict(row)
  if not row.price then return end
  if row.basis == "unlisted" then return "No listings" end
  if row.profit and row.profit <= 0 then return "Loss" end
  if (row.supplyDays and row.supplyDays > SLOW_DAYS) or (row.volume and row.volume < 1) then return "Slow" end
  if row.profit and (row.profit < THIN_PROFIT or (row.roi and row.roi < THIN_ROI)) then return "Thin margin" end
  if row.supplyDays and row.supplyDays <= 1 then return "Sells now" end
end

local function SupplyDays(info)
  if info.listed and info.volume and info.volume > 0 then return info.listed / info.volume end
end

local function Sort(rows)
  table.sort(rows, function(a,b)
    if a.score ~= b.score then return (a.score or -math.huge) > (b.score or -math.huge) end
    if a.price ~= b.price then return (a.price or 0) > (b.price or 0) end
    return a.name < b.name
  end)
  return rows
end

local gatherItemProfession = {}
for id, catalog in pairs(gatherCatalogs) do
  for _, entry in ipairs(catalog.items) do gatherItemProfession[entry[1]] = id end
end

function ns.GatherItemProfession(item)
  return gatherItemProfession[item]
end

function ns.GatheringMarketRows(source, skill, profession)
  profession = profession or 182
  local catalog = gatherCatalogs[profession]
  local rows = {}
  if not catalog then return rows end
  for _, entry in ipairs(catalog.items) do
    local item, required = entry[1], entry[2]
    -- Herbs whose requirement isn't known yet stay listed, marked unconfirmed.
    if not catalog.thresholds or skill == nil or required == nil or required <= skill then
      local price, info = Market(source, item)
      local score
      if price and source == "tsm" and info.rate then score = price * info.rate end
      if price and source == "ledger" and info.volume then score = price * info.volume end
      local row = {
        item = item, name = ns.ItemName(item, true), skill = required, price = price, gatherProfession = profession,
        volume = info.volume, rate = info.rate, market = info.market, updated = info.updated, snapshot = info.snapshot,
        basis = info.basis, listed = info.listed, ageDays = info.ageDays, supplyDays = SupplyDays(info), score = score,
        unconfirmed = catalog.thresholds and required == nil or nil,
      }
      row.tag = Verdict(row)
      rows[#rows + 1] = row
    end
  end
  return Sort(rows)
end

local function RecipeCost(source, recipe, reagentPrice, costs)
  local cost = 0
  for i = 1, #recipe.reagents, 2 do
    local reagent, quantity = recipe.reagents[i], recipe.reagents[i + 1]
    if costs[reagent] == nil then costs[reagent] = Market(source, reagent, reagentPrice) or false end
    local unit = costs[reagent]
    if not unit then return nil end
    cost = cost + unit * quantity
  end
  return cost
end

-- Several learned recipes can make the same item. Compare the cheapest per unit.
local function CheapestRecipe(source, recipe, reagentPrice, costs)
  local best, bestCost = recipe, RecipeCost(source, recipe, reagentPrice, costs)
  for _, alt in ipairs(recipe.alts or {}) do
    local cost = RecipeCost(source, alt, reagentPrice, costs)
    if cost and (not bestCost or cost / alt.quantity < bestCost / best.quantity) then best, bestCost = alt, cost end
  end
  return best, bestCost
end

-- buySort: only profitable recipes with daily sales, ingredients at the budget price.
-- skillUps: only orange and yellow recipes, cheapest expected skill-up first.
function ns.CraftingMarketRows(source, professions, buySort, pendingItems, skillUps)
  local rows, costs = {}, {}
  local reagentPrice = buySort and "budget" or true
  for name, scan in pairs((ns.cdb and ns.cdb.recipes) or {}) do
    local skill = professions[name]
    if skill then
      for item, entry in pairs(scan.market or {}) do
        local bound = ns.IsBoP(item)
        if bound == nil and pendingItems then pendingItems[item] = true end
        if bound == false then
          local price, info = Market(source, item)
          local recipe, cost = CheapestRecipe(source, entry, reagentPrice, costs)
          local volume = info.volume
          local revenue = price and price * recipe.quantity
          local payout = price and math.floor(price * FACTION_PAYOUT / 100) * recipe.quantity
          local profit = payout and cost and payout - cost
          local diff = scan.diff and scan.diff["item:" .. item]
          local keep = true
          if skillUps then keep = cost ~= nil and SKILL_CHANCE[diff] ~= nil
          elseif buySort then keep = profit and profit > 0 and volume and volume > 0 end
          if keep then
            local row = {
              item = item, name = ns.ItemName(item, true), price = price, volume = volume, rate = info.rate, market = info.market,
              updated = info.updated, snapshot = info.snapshot, basis = info.basis, listed = info.listed, ageDays = info.ageDays,
              supplyDays = SupplyDays(info), diff = diff,
              profession = name, skill = skill, quantity = recipe.quantity, cost = cost, revenue = revenue, recipe = recipe,
              score = profit, payout = payout, profit = profit, buySort = buySort,
              roi = profit and cost > 0 and profit / cost * 100 or nil,
            }
            if buySort then
              -- Stock already listed competes for the same buyers, so discount by days of supply.
              row.opportunity = profit / recipe.quantity * volume / math.max(1, row.supplyDays or 1)
              row.score = row[buySort]
            elseif skillUps then
              local net = (payout or 0) - cost
              row.skillNet = net
              row.score = net >= 0 and net or net / SKILL_CHANCE[diff]
            end
            row.tag = Verdict(row)
            rows[#rows + 1] = row
          end
        end
      end
    end
  end
  return Sort(rows)
end

-- Which of a crafter's shared recipes Market can price. Only crafters on 0.22.0 or
-- later share this, so older shares count as "waiting" instead of being guessed.
local marketShares = setmetatable({}, {__mode = "k"})
local function SharedMarket(rec, prof)
  local p = rec and rec.profs and rec.profs[prof]
  if type(p) ~= "table" or not p.m then return end
  local share = marketShares[p]
  if not share then
    share = {skip = {}, quantity = type(p.mq) == "table" and p.mq or {}}
    for _, id in ipairs(type(p.nm) == "table" and p.nm or {}) do share.skip[id] = true end
    marketShares[p] = share
  end
  return share
end

local function IsOnline(who)
  local r = ns.roster and ns.roster[who]
  return r and r.online == true or false
end

-- Every tradable item any guildmate can craft, priced like Craft.
function ns.GuildCraftingRows(source, buySort, pendingItems)
  local g = ns.G()
  local rows, costs, info, people = {}, {}, {waiting = 0, crafters = 0}, {}
  if not g then return rows, info end
  local reagentPrice = buySort and "budget" or true
  for _, e in ipairs(ns.RecipeIndex()) do
    local item = e.item
    local bound = item and ns.IsBoP(item)
    if item and bound == nil and pendingItems then pendingItems[item] = true end
    if item and bound == false then
      local ready, skipped, quantity, crafters, best = false, false, 1, {}, 0
      for _, c in ipairs(e.crafters) do
        local share = SharedMarket(g.recipes[c.who], c.prof)
        if share then
          ready = true
          if share.skip[item] then skipped = true end
          local n = tonumber(share.quantity[item])
          if n and n >= 1 and n <= 1000 and n % 1 == 0 then quantity = n end
        end
        crafters[#crafters + 1] = {who = c.who, online = IsOnline(c.who), designated = ns.IsDesignated(c.who, c.prof), rank = tonumber(c.rank)}
        best = math.max(best, tonumber(c.rank) or 0)
        people[c.who] = true
      end
      local mats = g.mats["item:" .. item]
      if not ready then
        info.waiting = info.waiting + 1
      elseif not skipped and mats and type(mats.r) == "table" and #mats.r >= 2 then
        local recipe = {quantity = quantity, reagents = mats.r}
        local price, market = Market(source, item)
        local cost = RecipeCost(source, recipe, reagentPrice, costs)
        local volume = market.volume
        local payout = price and math.floor(price * FACTION_PAYOUT / 100) * quantity
        local profit = payout and cost and payout - cost
        if not buySort or (profit and profit > 0 and volume and volume > 0) then
          table.sort(crafters, function(a, b)
            if a.designated ~= b.designated then return a.designated end
            if a.online ~= b.online then return a.online end
            return a.who < b.who
          end)
          local row = {
            item = item, name = ns.ItemName(item, true), price = price, volume = volume, rate = market.rate,
            market = market.market, updated = market.updated, snapshot = market.snapshot, basis = market.basis,
            listed = market.listed, ageDays = market.ageDays, supplyDays = SupplyDays(market),
            profession = e.prof, skill = best, quantity = quantity, cost = cost, revenue = price and price * quantity,
            recipe = recipe, payout = payout, profit = profit, score = profit, buySort = buySort, guild = true,
            crafters = crafters, roi = profit and cost > 0 and profit / cost * 100 or nil,
          }
          if buySort then
            row.opportunity = profit / quantity * volume / math.max(1, row.supplyDays or 1)
            row.score = row[buySort]
          end
          row.tag = Verdict(row)
          rows[#rows + 1] = row
        end
      end
    end
  end
  for _ in pairs(people) do info.crafters = info.crafters + 1 end
  return Sort(rows), info
end

local function CrafterNames(row, limit)
  local names = {}
  for i, c in ipairs(row.crafters or {}) do
    if i > limit then names[#names + 1] = "+" .. (#row.crafters - limit); break end
    names[#names + 1] = (c.designated and "*" or "") .. (c.online and ("|cff4ade80" .. c.who .. "|r") or c.who)
  end
  return table.concat(names, ", ")
end

-- Guildmates other than you whose shared gathering skill covers this material.
local function GuildGatherers(row)
  local g, prof, list = ns.G(), ns.GUIDE_PROFESSIONS[row.gatherProfession], {}
  for who, c in pairs(g and g.crafters or {}) do
    local skill = tonumber(c.profs and c.profs[prof])
    if skill and who ~= ns.me and ns.InGuild(who) and (not row.skill or skill >= row.skill) then
      list[#list + 1] = {who = who, skill = skill, online = IsOnline(who)}
    end
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    if a.skill ~= b.skill then return a.skill > b.skill end
    return a.who < b.who
  end)
  return list
end

-- One line for members: what the guild wants, your own progress, and a nudge
-- when you still have a free primary profession slot.
local function FocusLine(player)
  local focus = ns.GuildFocus()
  if #focus == 0 then return end
  local mine, primaries = {}, 0
  for id, prof in pairs(player.professions) do
    local name = ns.GUIDE_PROFESSIONS[id] or prof.name
    mine[name] = prof.rank
    if PRIMARY[name] then primaries = primaries + 1 end
  end
  local parts, suggest = {}, false
  for _, f in ipairs(focus) do
    local text = f.prof .. (f.goal > 0 and (" " .. f.goal) or "")
    if mine[f.prof] then text = text .. " (you " .. mine[f.prof] .. ")"
    elseif f.primary and primaries < 2 then suggest = true end
    parts[#parts + 1] = text
  end
  return "|cfff2c14eGuild focus:|r " .. table.concat(parts, ", ") .. (suggest and " · you have a free profession slot" or "")
end

local function FocusMark(id)
  local name = ns.GUIDE_PROFESSIONS[id]
  return name and ns.GuildFocusOf(name) and "Focus · " or ""
end

function ns.CraftingMaterialPlan(source, row, crafts, professions)
  local recipes, ambiguous, stock = {}, {}, {}
  local direct, base, steps = {}, {}, {}
  for profession, scan in pairs(ns.cdb.recipes or {}) do
    if professions[profession] then
      for item, recipe in pairs(scan.market or {}) do
        if recipes[item] then ambiguous[item] = true end
        recipes[item] = recipe
      end
    end
  end
  local function Require(item, needed, path)
    if stock[item] == nil then stock[item] = ns.ItemCount(item) end
    local used = math.min(needed, stock[item])
    stock[item] = stock[item] - used
    local missing = needed - used
    if missing == 0 then return end
    local recipe = recipes[item]
    if recipe and not ambiguous[item] and not path[item] then
      local batches = math.ceil(missing / recipe.quantity)
      path[item] = true
      for i = 1, #recipe.reagents, 2 do
        Require(recipe.reagents[i], recipe.reagents[i + 1] * batches, path)
      end
      path[item] = nil
      stock[item] = stock[item] + batches * recipe.quantity - missing
      steps[item] = (steps[item] or 0) + batches
    else
      base[item] = (base[item] or 0) + missing
    end
  end
  local needs = {}
  for i = 1, #row.recipe.reagents, 2 do
    local item, needed = row.recipe.reagents[i], row.recipe.reagents[i + 1] * crafts
    needs[item] = (needs[item] or 0) + needed
  end
  -- Reserve direct ingredients before expanding any subrecipe.
  for item, needed in pairs(needs) do
    local carried = ns.ItemCount(item)
    direct[item] = math.max(0, needed - carried)
    stock[item] = math.max(0, carried - needed)
  end
  local path = {[row.item] = true}
  if not row.buySort and not row.guild then
    for item, missing in pairs(direct) do Require(item, missing, path) end
  end
  local function Total(items)
    local cost = 0
    for item, quantity in pairs(items) do
      if quantity > 0 then
        local price = Market(source, item, row.buySort and "budget" or true)
        if not price then return end
        cost = cost + quantity * price
      end
    end
    return cost
  end
  return {direct = direct, base = base, steps = steps, buyCost = Total(direct), baseCost = Total(base)}
end

local frame, activeSource, craftMode, skillOnly, routeOrder, zoneOnly, buySort, professionFilter, gatherFilter, craftSort
local guildScope, guildProfession
local points, listRows, detailRows = {}, {}, {}
local Select
local RenderDetail

local function Gold(copper)
  if not copper then return "—" end
  local rounded = math.floor(math.abs(copper) + .5)
  return (copper < 0 and "−" or "") .. ns.MoneyText(rounded, true)
end

local function Sales(units)
  if not units then return "—" end
  if units > 0 and units < .1 then return "<0.1" end
  if units < 10 then return (string.format("%.1f", units):gsub("%.0$", "")) end
  local whole = tostring(math.floor(units + .5))
  return (whole:reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse())
end

local function ProfitPercent(roi)
  return roi and (string.format("%+.1f", roi):gsub("%.0$", "") .. "%") or "—"
end

local function HighlightTop(rows, field)
  local priced = {}
  for _, row in ipairs(rows) do
    if row[field] and row[field] > 0 then priced[#priced + 1] = row end
  end
  table.sort(priced, function(a, b)
    if a[field] ~= b[field] then return a[field] > b[field] end
    return a.name < b.name
  end)
  for i = 1, math.min(3, #priced) do priced[i].highlight = true end
end

local function CharacterCrafts(player)
  local learned, options, groups, ranks = {}, {}, {}, {}
  local scans = ns.cdb and ns.cdb.recipes or {}
  for id, prof in pairs(player.professions) do
    if not gatheringOnly[id] then
      learned[id] = prof
      groups[prof.name] = id
      local name = ns.GUIDE_PROFESSIONS[id]
      if name then groups[name] = id end
    end
  end
  if learned[186] then groups.Smelting = 186 end
  local scanned = {}
  for name, scan in pairs(scans) do
    local id = learned[scan.professionID] and scan.professionID or groups[name]
    if id then
      groups[name] = id
      ranks[name] = learned[id].rank
      if scan.market then scanned[id] = true end
    end
  end
  for id, prof in pairs(learned) do
    options[#options + 1] = {value = id, label = prof.name, right = FocusMark(id) .. (scanned[id] and tostring(prof.rank) or "Open to scan")}
  end
  table.sort(options, function(a, b) return a.label < b.label end)
  return learned, options, groups, ranks, scanned
end

local function GatherSelection(player)
  local options, firstLearned = {}, nil
  for _, id in ipairs(gatherOrder) do
    local prof = player.professions[id]
    if prof and not firstLearned then firstLearned = id end
    options[#options + 1] = {
      value = id, label = prof and prof.name or ns.GUIDE_PROFESSIONS[id],
      right = FocusMark(id) .. (prof and tostring(prof.rank) or "Unlearned"),
    }
  end
  return gatherFilter or firstLearned or gatherOrder[1], options
end

local function DataAge(row)
  local text = row.snapshot and "AHledger bundled snapshot" or nil
  if row.ageDays then
    text = "Last seen in your Auctionator scan "
      .. (row.ageDays < 1 and "today" or string.format("%d day%s ago", row.ageDays, row.ageDays < 2 and "" or "s"))
  end
  if not row.updated then return text end
  local stamp = type(row.updated) == "number" and date("%b %d %H:%M", row.updated) or row.updated
  return (text and text .. " · " or "") .. "Prices updated " .. stamp
end

local basisText = {
  low = "current low", median = "median (low is higher)",
  unlisted = "median (none listed)", average = "regional average",
}

-- One line for the header: how fresh the selected source is, and whether to warn.
local function SourceStatus(rows)
  local newest, snapshot, youngest
  for _, row in ipairs(rows) do
    if row.snapshot then snapshot = true end
    if row.updated and (newest == nil or (type(row.updated) == "number" and type(newest) == "number" and row.updated > newest)) then
      newest = row.updated
    end
    if row.ageDays and (not youngest or row.ageDays < youngest) then youngest = row.ageDays end
  end
  local text, warn
  if activeSource.key == "ledger" then
    if snapshot then text, warn = "bundled snapshot, not live prices", true end
    if newest then
      local stamp = type(newest) == "number" and date("%b %d %H:%M", newest) or newest
      text = (text and text .. " · " or "") .. "updated " .. stamp
      local age = type(newest) == "number" and ns.Now() - newest
      if age and age > STALE_SECONDS then
        text = text .. string.format(" (%d hours old)", math.floor(age / 3600))
        warn = true
      end
    end
  elseif activeSource.key == "auctionator" then
    if youngest then
      text = youngest < 1 and "your last scan was today"
        or string.format("your last scan was %d day%s ago", youngest, youngest < 2 and "" or "s")
      warn = youngest >= 1
    end
  end
  return text, warn
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
  if row.basis then
    local now = row.basis == "low"
    GameTooltip:AddLine("Price used: " .. basisText[row.basis], now and .6 or 1, now and .9 or .6, now and .6 or .3)
  end
  GameTooltip:AddLine("Units sold/day: " .. (row.volume and Sales(row.volume) or "Unavailable"), 1, 1, 1)
  if row.listed then
    GameTooltip:AddLine("Listed now: " .. Sales(row.listed)
      .. (row.supplyDays and (" · about " .. Sales(row.supplyDays) .. " days of supply") or ""), 1, 1, 1)
  end
  GameTooltip:AddLine("Sell-through: " .. (row.rate and string.format("%.1f%%", row.rate * 100) or "Unavailable"), 1, 1, 1)
  if row.market then GameTooltip:AddLine(row.market) end
  if row.gph then GameTooltip:AddLine("Gross at your route yield: " .. Gold(row.gph) .. "/hr") end
  local age = DataAge(row)
  if age then GameTooltip:AddLine(age) end
  if row.profession then
    GameTooltip:AddLine(row.profession .. " " .. row.skill .. " · makes " .. row.quantity)
    GameTooltip:AddLine("Reagents: " .. Gold(row.cost) .. " · output: " .. Gold(row.revenue))
    GameTooltip:AddLine("Profit per craft after 5% AH cut: " .. Gold(row.profit))
    GameTooltip:AddLine("The listing deposit comes back when it sells; an unsold listing loses it.", .7, .7, .7, true)
    GameTooltip:AddLine("Return on ingredient cost: " .. ProfitPercent(row.roi))
    if row.guild then GameTooltip:AddLine("Crafters: " .. CrafterNames(row, 6), 1, 1, 1, true) end
    if SKILL_CHANCE[row.diff] then
      GameTooltip:AddLine("Skill-up: " .. (row.diff == "o" and "orange, every craft" or "yellow, most crafts"))
    end
  else
    local profession = ns.GUIDE_PROFESSIONS[row.gatherProfession]
    GameTooltip:AddLine(row.skill and (profession .. " required: " .. row.skill)
      or gatherCatalogs[row.gatherProfession].hint
      or (row.unconfirmed and "Skill requirement not confirmed yet for this new Forever material")
      or "Gathering requirements unverified")
    local mates = GuildGatherers(row)
    if #mates > 0 then
      local names = {}
      for i = 1, math.min(5, #mates) do
        names[#names + 1] = (mates[i].online and ("|cff4ade80" .. mates[i].who .. "|r") or mates[i].who) .. " " .. mates[i].skill
      end
      GameTooltip:AddLine("Guildmates who can gather this: " .. table.concat(names, ", ")
        .. (#mates > 5 and (" +" .. (#mates - 5)) or ""), 1, 1, 1, true)
    end
  end
  if row.tag then GameTooltip:AddLine(row.tag, 1, .7, .3) end
  if row.highlight and frame.highlightLabel then GameTooltip:AddLine(frame.highlightLabel .. " in these results", 1, .8, .3) end
  GameTooltip:Show()
end

local function HoverButton(parent)
  local button = CreateFrame("Button", nil, parent)
  button:SetScript("OnEnter", Tooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnClick", function(self)
    if self.row then Select(self.row) end
  end)
  return button
end

local function Plot(rows)
  local width, height = frame.chart:GetWidth(), frame.chart:GetHeight()
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
      if row.highlight then point.dot:SetVertexColor(.95, .75, .31, .92)
      else point.dot:SetVertexColor(.26, .86, .65, .85) end
      point:ClearAllPoints()
      point:SetPoint("CENTER", frame.chart, "BOTTOMLEFT", 16 + row.volume / maxVolume * (width - 32), 16 + row.price / maxPrice * (height - 32))
      point:Show()
    end
  end
  for i = shown + 1, #points do points[i]:Hide() end
  for i = 0, 4 do
    local x, y = 16 + i * (width - 32) / 4, 16 + i * (height - 32) / 4
    local vertical, horizontal = frame.xGrid[i], frame.yGrid[i]
    vertical:ClearAllPoints()
    vertical:SetPoint("BOTTOMLEFT", x, 16)
    vertical:SetSize(1, height - 32)
    horizontal:ClearAllPoints()
    horizontal:SetPoint("BOTTOMLEFT", 16, y)
    horizontal:SetSize(width - 32, 1)
    frame.xLabels[i]:ClearAllPoints()
    frame.xLabels[i]:SetPoint("TOP", frame.chart, "BOTTOMLEFT", x, -4)
    frame.yLabels[i]:ClearAllPoints()
    frame.yLabels[i]:SetPoint("RIGHT", frame.chart, "BOTTOMLEFT", -6, y)
    frame.xLabels[i]:SetText(shown > 0 and Sales(maxVolume * i / 4) or "")
    frame.yLabels[i]:SetText(shown > 0 and Gold(maxPrice * i / 4) or "")
  end
  frame.chartEmpty:SetShown(shown == 0)
  return shown
end

local function Refresh()
  local width = math.max(478, frame:GetWidth())
  local height = math.max(358, frame:GetHeight())
  local sidebar = math.floor(width * .31)
  local detailWidth = width - sidebar - 35
  frame.chart:SetSize(width - sidebar - 76, height - 234)
  local offset = 27
  frame.detail:ClearAllPoints()
  frame.detail:SetPoint("TOPLEFT", sidebar + 20, -107 - offset)
  frame.detail:SetPoint("BOTTOMRIGHT", -12, 8)
  frame.detailText:SetWidth(detailWidth)
  frame.zonePreview:SetSize(detailWidth, 59)
  frame.detailList:SetWidth(detailWidth - 18)
  local player = ns.GuidePlayer()
  local gatherID, gatherChoices = GatherSelection(player)
  local gatherProf = player.professions[gatherID]
  local gatherName = gatherProf and gatherProf.name or ns.GUIDE_PROFESSIONS[gatherID]
  local skill = gatherProf and gatherProf.rank
  local routable = ns.GatheringRouteProfession(gatherID)
  local guild = craftMode and guildScope == true
  local skillUps = craftMode and not guild and not buySort and craftSort == "skill"
  frame.gatherSkill = skill
  frame.gatherID, frame.gatherChoices = gatherID, gatherChoices
  frame.gatherProfession:SetText(gatherName)
  frame.gatherProfession:SetShown(not craftMode)
  local learned, options, groups, professions, scanned = CharacterCrafts(player)
  frame.professions = professions
  frame.professionChoices = options
  if not learned[professionFilter] then professionFilter = nil end
  frame.professionFilter:SetShown(craftMode)
  frame.professionFilter:SetText(guild and (guildProfession or "All guild professions")
    or professionFilter and learned[professionFilter].name or "All my professions")
  frame.openProfession:SetShown(craftMode and not guild and #options > 0)
  frame.scope:SetShown(craftMode)
  frame.scope:SetText(guild and "Scope: Guild" or "Scope: Mine")
  frame.scope:ClearAllPoints()
  frame.scope:SetPoint("TOPLEFT", guild and 173 or 299, -61)
  frame.craftTab:SetButtonState(craftMode and not buySort and "PUSHED" or "NORMAL", craftMode and not buySort)
  frame.gatherTab:SetButtonState(not craftMode and "PUSHED" or "NORMAL", not craftMode)
  frame.buyTab:SetButtonState(buySort and "PUSHED" or "NORMAL", buySort ~= nil)
  frame.craftSort:SetShown(craftMode and not buySort and not guild)
  frame.craftSort:SetText(skillUps and "Sort: Skill-ups" or "Sort: Profit")
  for key, button in pairs(frame.sourceButtons) do
    local active = key == activeSource.key
    button:SetButtonState(active and "PUSHED" or "NORMAL", active)
  end
  frame.pendingItems = {}
  frame.skill:SetText("My skill: " .. (skillOnly and "On" or "Off"))
  frame.skill:SetShown(not craftMode and skill ~= nil and gatherCatalogs[gatherID].thresholds == true)
  frame.yieldSort:SetText(routeOrder and "Sort: My gold/hr" or "Sort: Market")
  -- Until the member chooses, show this zone's materials whenever it has recorded spots.
  local zoneActive = zoneOnly
  if zoneActive == nil then zoneActive = routable and #ns.GatheringRoutePreview(nil, gatherID) > 0 end
  frame.zoneActive = zoneActive
  frame.zoneFilter:SetText(zoneActive and "This zone: On" or "This zone: Off")
  frame.routeButton:SetText(gatherID == 186 and "Start ore route" or "Start herb route")
  local rows, guildInfo
  if guild then
    rows, guildInfo = ns.GuildCraftingRows(activeSource.key, buySort, frame.pendingItems)
    local counts = {}
    for _, row in ipairs(rows) do counts[row.profession] = (counts[row.profession] or 0) + 1 end
    local choices = {}
    for name, n in pairs(counts) do choices[#choices + 1] = {value = name, label = name, right = (ns.GuildFocusOf(name) and "Focus · " or "") .. n} end
    table.sort(choices, function(a, b) return a.label < b.label end)
    frame.guildChoices = choices
    if guildProfession and not counts[guildProfession] then guildProfession = nil end
    frame.professionFilter:SetText(guildProfession or "All guild professions")
    if guildProfession then
      for i = #rows, 1, -1 do if rows[i].profession ~= guildProfession then table.remove(rows, i) end end
    end
  else
    rows = craftMode and ns.CraftingMarketRows(activeSource.key, professions, buySort, frame.pendingItems, skillUps)
      or ns.GatheringMarketRows(activeSource.key, skillOnly and skill or nil, gatherID)
  end
  local status, stale = SourceStatus(rows)
  if craftMode and not guild and professionFilter then
    for i = #rows, 1, -1 do
      if groups[rows[i].profession] ~= professionFilter then table.remove(rows, i) end
    end
  end
  local query = ns.UI.search:GetText():lower():match("^%s*(.-)%s*$")
  if query ~= "" then
    for i = #rows, 1, -1 do
      if not rows[i].name:lower():find(query, 1, true) then table.remove(rows, i) end
    end
  end
  if frame.selected then
    local selected
    for _, row in ipairs(rows) do
      if row.item == frame.selected.item then selected = row; break end
    end
    frame.selected = selected
  end
  frame.buySort:SetShown(buySort ~= nil)
  for _, option in ipairs(buySorts) do
    if buySort == option.value then frame.buySort:SetText(option.label) end
  end
  local gatheringOverview = not craftMode and not frame.selected
  frame.yieldSort:SetShown(gatheringOverview)
  frame.zoneFilter:SetShown(gatheringOverview and routable)
  frame.routeButton:SetShown(gatheringOverview and routable)
  frame.yieldSort:ClearAllPoints()
  if routable then frame.yieldSort:SetPoint("LEFT", frame.routeButton, "RIGHT", 6, 0)
  else frame.yieldSort:SetPoint("BOTTOMLEFT", 12, 16) end
  if not craftMode then
    local _, _, map = ns.GatheringRoutePreview()
    local yields = ns.cdb.herbYield and ns.cdb.herbYield[map]
    for i = #rows, 1, -1 do
      local row = rows[i]
      local perHour = yields and yields[row.item]
      row.gph = row.price and perHour and row.price * perHour
      if routable and zoneActive and #ns.GatheringRoutePreview(row.item, gatherID) == 0 then table.remove(rows, i) end
    end
    if routeOrder then
      table.sort(rows, function(a, b)
        if a.gph ~= b.gph then return (a.gph or -1) > (b.gph or -1) end
        return a.name < b.name
      end)
    end
  end
  -- The gold highlight follows whatever the list is sorted by.
  local highlightField = not craftMode and "price" or skillUps and "score" or buySort or "profit"
  frame.highlightLabel = highlightLabels[highlightField]
  HighlightTop(rows, highlightField)
  frame.chart:SetShown(gatheringOverview and #rows > 0)
  local shown = not craftMode and Plot(rows)
  local label = (activeSource.key == "tsm" and "Price × sell-through per item")
    or (activeSource.key == "ledger" and "Estimated market gold/day") or "Listing price per item"
  frame.context:ClearAllPoints()
  frame.context:SetPoint("TOPLEFT", 12, -64 - offset)
  frame.context:SetPoint("RIGHT", -12, 0)
  frame.sourceText:ClearAllPoints()
  frame.sourceText:SetPoint("TOPLEFT", 12, -81 - offset)
  frame.sourceText:SetPoint("RIGHT", -12, 0)
  local unscanned = 0
  for id in pairs(learned) do if not scanned[id] then unscanned = unscanned + 1 end end
  local compared, learnedRecipes = 0, 0
  for name, scan in pairs(ns.cdb.recipes or {}) do
    if professions[name] and scan.stats then
      compared = compared + (scan.stats.priced or 0)
      learnedRecipes = learnedRecipes + (scan.stats.total or 0)
    end
  end
  frame.context:SetText(guild and ((buySort and "Profitable guild recipes with daily sales" or "Recipes your guildmates can craft")
      .. string.format(" · %d crafter%s · %d compared", guildInfo.crafters, guildInfo.crafters == 1 and "" or "s", #rows)
      .. (guildInfo.waiting > 0 and string.format(" · %d waiting for crafters to update EPU", guildInfo.waiting) or ""))
    or buySort and "Profitable recipes with daily sales · 5% faction AH cut"
    or skillUps and "Orange and yellow recipes · cheapest skill-ups first"
    or craftMode and (string.format("%d learned crafting professions · %d to scan", #options, unscanned)
      .. (learnedRecipes > 0 and string.format(" · %d of %d recipes compared", compared, learnedRecipes) or ""))
    or string.format("%s %s · %d/%d plotted · %s", gatherName, skill or "unlearned", shown, #rows, label))
  local sourceLine
  if not (Available("ledger") or Available("tsm") or Available("auctionator")) then
    sourceLine = "|cffffb347No price addon found. Install AHledger or Auctionator: EPU reads their prices and never scans the auction house itself.|r"
  elseif not Available(activeSource.key) then
    sourceLine = "Load " .. activeSource.title .. " with current market data, then press Refresh."
  else
    sourceLine = activeSource.title .. " · " .. (status and status .. " · " or "") .. activeSource.hint
      .. (not craftMode and activeSource.plotHint or "")
    if stale then sourceLine = "|cffffb347" .. sourceLine .. "|r" end
  end
  frame.sourceText:SetText(sourceLine)
  ns.UI.footerText:SetText(not craftMode and "Prices are the current lowest listing when the source has one. Gold per hour is gross, before the 5% AH cut."
    or buySort and "Sale at the current lowest listing, after the 5% AH cut. Ingredients at the higher of lowest listing and median, or the vendor price."
    or "Sale at the current lowest listing, after the 5% AH cut. Ingredients at the lowest listing or the vendor price.")
  frame.credit:SetShown(activeSource.key == "ledger")
  local focusLine = not frame.selected and FocusLine(player)
  frame.focusText:SetText(focusLine or "")
  frame.focusText:SetShown(focusLine ~= nil and focusLine ~= false)
  frame.focusText:ClearAllPoints()
  frame.focusText:SetPoint("BOTTOMLEFT", 12, craftMode and 22 or 44)
  frame.focusText:SetPoint("RIGHT", -12, 0)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", (craftMode or frame.selected) and 12 or width - sidebar - 10, -107 - offset)
  if frame.selected then
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", sidebar - 4, 8)
  else
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, (focusLine and not craftMode) and 60 or 42)
  end
  local listWidth = craftMode and not frame.selected and width - 38 or sidebar - 16
  frame.list:SetSize(listWidth, math.max(28, #rows * 30))
  -- Only jump back to the top when the member changed what the list shows.
  local viewKey = table.concat({tostring(craftMode), tostring(buySort), tostring(craftSort), tostring(professionFilter),
    tostring(guild), tostring(guildProfession),
    tostring(gatherID), tostring(skillOnly), tostring(zoneActive), tostring(routeOrder), activeSource.key, query,
    tostring(frame.selected and frame.selected.item)}, "|")
  local furthest = math.max(0, #rows * 30 - frame.scroll:GetHeight())
  if viewKey ~= frame.viewKey then
    frame.viewKey = viewKey
    frame.scroll:SetVerticalScroll(0)
  elseif frame.scroll:GetVerticalScroll() > furthest then
    frame.scroll:SetVerticalScroll(furthest)
  end
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
      for _, label in ipairs({button.name, button.summary}) do
        label:SetPoint("RIGHT", -3, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
      end
      listRows[i] = button
    end
    button.row = row
    local title = row.highlight and ("|cfff2c14e" .. row.name .. " · " .. frame.highlightLabel .. "|r") or row.name
    if row.tag then title = title .. "  |cff" .. tagColors[row.tag] .. row.tag .. "|r" end
    button.name:SetText(title)
    local summary
    if skillUps then
      summary = (row.skillNet >= 0 and ("earns " .. Gold(row.skillNet)) or ("costs " .. Gold(-row.skillNet))) .. "/craft · "
        .. (row.diff == "o" and "orange" or "yellow") .. " skill-up · " .. row.profession
    elseif row.guild then
      summary = Gold(row.profit) .. "/craft · " .. ProfitPercent(row.roi)
        .. (row.volume and (" · " .. Sales(row.volume) .. " sold/day") or "") .. " · " .. CrafterNames(row, 2)
    elseif craftMode then
      summary = Gold(row.profit) .. "/craft · " .. ProfitPercent(row.roi)
        .. (row.volume and (" · " .. Sales(row.volume) .. " sold/day") or "") .. " · " .. row.profession
    else
      summary = Gold(row.price) .. " · " .. Sales(row.volume) .. "/day"
        .. (routeOrder and row.gph and (" · " .. Gold(row.gph) .. "/hr") or "")
    end
    button.summary:SetText(summary)
    button:Show()
  end
  for i = #rows + 1, #listRows do listRows[i]:Hide() end
  frame.empty:ClearAllPoints()
  frame.empty:SetPoint("TOPLEFT", 12, -105 - offset)
  frame.empty:SetShown(#rows == 0)
  local needsScan = craftMode and not guild and (professionFilter and not scanned[professionFilter] or not next(scanned))
  frame.empty:SetText(query ~= "" and "No market items match your search."
    or guild and (guildInfo.waiting > 0 and "Guild recipes appear once crafters update EPU and open their professions."
      or buySort and "No guild recipes with positive profit and daily sales data."
      or "No guild recipes to compare yet. Crafters share them by opening their professions.")
    or craftMode and #options == 0 and "Learn a crafting profession to see recipes here."
    or needsScan and "Open a profession to scan your learned recipes."
    or skillUps and "No orange or yellow recipes with complete ingredient prices."
    or buySort and (activeSource.key == "auctionator" and "Choose AHledger or TSM for daily sales."
      or "No learned recipes with positive profit and daily sales data.")
    or craftMode and "No auctionable crafts with complete recipe data."
    or routable and zoneActive and "No recorded spots match your filters in this zone. Turn off This zone to see every material."
    or ("No " .. gatherName .. " materials match your skill filter."))
  RenderDetail()
end

Select = function(row)
  frame.selected = row
  frame.crafts:SetText("1")
  Refresh()
end

RenderDetail = function()
  local row = frame.selected
  frame.detail:SetShown(row ~= nil)
  if not row then return end
  frame.detailTitle:SetText(row.name)
  frame.crafts:SetShown(craftMode)
  frame.craftsLabel:SetShown(craftMode)
  frame.detailScroll:SetShown(craftMode)
  local routable = ns.GatheringRouteProfession(row.gatherProfession)
  frame.startTarget:SetShown(routable)
  frame.markTarget:SetShown(routable)
  frame.yieldLabel:SetShown(not craftMode)
  frame.yieldInput:SetShown(not craftMode)
  frame.zonePreview:SetShown(routable)
  frame.age:SetText(DataAge(row) or "")
  if not craftMode then
    frame.askCrafter:Hide()
    local spots, zone, map = ns.GatheringRoutePreview(row.item, row.gatherProfession)
    local count = routable and #spots or 0
    local profession = ns.GUIDE_PROFESSIONS[row.gatherProfession]
    local requirement = row.skill and ("Requires " .. profession .. " " .. row.skill)
      or gatherCatalogs[row.gatherProfession].hint
      or (row.unconfirmed and "Skill requirement not confirmed yet") or "Gathering requirement unverified"
    local location = routable and string.format("%d recorded spots in %s", count, zone)
      or "See Profession guides for gathering locations."
    local mates = #GuildGatherers(row)
    if mates > 0 then location = location .. string.format(" · %d guildmate%s can gather this", mates, mates == 1 and "" or "s") end
    frame.detailText:SetText(string.format("%s\n%s · %s sold/day\n%s\nYour gross estimate %s",
      requirement, Gold(row.price), Sales(row.volume), location,
      row.gph and Gold(row.gph) .. "/hr" or "—"))
    local yields = ns.cdb.herbYield and ns.cdb.herbYield[map]
    frame.yieldLabel:SetShown(map ~= nil)
    frame.yieldInput:SetShown(map ~= nil)
    if not frame.yieldInput:HasFocus() then frame.yieldInput:SetText(tostring(yields and yields[row.item] or "")) end
    -- A spot is worth recording whenever you see the node, whatever your skill.
    local canGather = row.skill == nil or row.skill <= (frame.gatherSkill or 0)
    frame.startTarget:SetEnabled(count > 0 and canGather)
    frame.markTarget:SetEnabled(true)
    for i = 1, count do
      local point = spots[i]
      local pin = frame.zonePins[i]
      if not pin then
        pin = frame.zonePreview:CreateTexture(nil, "ARTWORK")
        pin:SetTexture(circle)
        pin:SetVertexColor(1, .78, .24)
        pin:SetSize(6, 6)
        frame.zonePins[i] = pin
      end
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", frame.zonePreview, "TOPLEFT", 6 + point.x * (frame.zonePreview:GetWidth() - 12), -6 - point.y * 47)
      pin:Show()
    end
    for i = count + 1, #frame.zonePins do frame.zonePins[i]:Hide() end
    frame.zonePreview:SetShown(count > 0)
    return
  end
  local crafts = math.min(999, math.max(1, math.floor(tonumber(frame.crafts:GetText()) or 1)))
  local plan = ns.CraftingMaterialPlan(activeSource.key, row, crafts, frame.professions)
  local _, _, map = ns.GatheringRoutePreview()
  local yields = ns.cdb.herbYield and ns.cdb.herbYield[map]
  local sale = row.price and (Gold(row.price) .. " each, " .. (basisText[row.basis] or "listed price")) or "no price"
  frame.askCrafter:SetShown(row.guild == true)
  if row.guild then
    frame.detailText:SetText(string.format("Makes %d · sale %s\nProfit after AH cut %s (%s)\nBuy the ingredients %s\nCrafters: %s",
      crafts * row.quantity, sale, Gold(row.profit and row.profit * crafts), ProfitPercent(row.roi), Gold(plan.buyCost), CrafterNames(row, 4)))
  elseif buySort then
    frame.detailText:SetText(string.format("Makes %d · %s sold/day%s\nSale %s\nProfit after AH cut %s (%s)\nBuy missing ingredients %s",
      crafts * row.quantity, Sales(row.volume), row.listed and (" · " .. Sales(row.listed) .. " listed") or "", sale,
      Gold(row.profit * crafts), ProfitPercent(row.roi), Gold(plan.buyCost)))
  else
    frame.detailText:SetText(string.format("Makes %d · sale %s\nProfit after AH cut %s (%s)\nBuy missing ingredients %s\nBuy base materials and craft the rest %s",
      crafts * row.quantity, sale, Gold(row.profit and row.profit * crafts), ProfitPercent(row.roi), Gold(plan.buyCost), Gold(plan.baseCost)))
  end
  local entries = {}
  local function Add(title, values, showPrice, linkGathering)
    entries[#entries + 1] = {label = title}
    local items = {}
    for item, quantity in pairs(values) do
      if quantity > 0 then items[#items + 1] = item end
    end
    table.sort(items, function(a, b) return ns.ItemName(a, true) < ns.ItemName(b, true) end)
    for _, item in ipairs(items) do
      local label = "   " .. values[item] .. " × " .. ns.ItemName(item, true)
      if showPrice then
        local price, info = Market(activeSource.key, item, buySort and "budget" or true)
        if price then label = label .. " · " .. Gold(price * values[item]) .. (info.vendor and " (vendor)" or "") end
        if linkGathering and yields and yields[item] then
          label = label .. " · ~" .. math.ceil(60 * values[item] / yields[item]) .. " min"
        end
      end
      entries[#entries + 1] = {label = label, item = linkGathering and gatherItemProfession[item] ~= nil and item}
    end
    if #items == 0 then entries[#entries + 1] = {label = "   None"} end
  end
  Add((buySort or row.guild) and "Buy these materials" or "Missing ingredients", plan.direct, buySort ~= nil or row.guild == true, false)
  if not buySort and not row.guild then
    Add("Make these first (crafts)", plan.steps, false, false)
    Add("Still needed for that plan", plan.base, true, true)
  end
  for i, entry in ipairs(entries) do
    local button = detailRows[i]
    if not button then
      button = CreateFrame("Button", nil, frame.detailList)
      button:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
      button:SetHeight(21)
      button:SetPoint("TOPRIGHT", 0, -(i - 1) * 21)
      button.label = Label(button, "")
      button.label:SetPoint("LEFT", 0, 0)
      button:SetScript("OnClick", function(self)
        if not self.item then return end
        local id = gatherItemProfession[self.item]
        for _, material in ipairs(ns.GatheringMarketRows(activeSource.key, nil, id)) do
          if material.item == self.item then
            craftMode, zoneOnly, buySort = false, false, nil
            gatherFilter = id
            local prof = ns.GuidePlayer().professions[id]
            if not material.skill or not prof or material.skill > prof.rank then skillOnly = false end
            Select(material)
            return
          end
        end
      end)
      detailRows[i] = button
    end
    button.item = entry.item
    button.label:SetText(entry.label .. (entry.item and "  ›" or ""))
    button:Show()
  end
  for i = #entries + 1, #detailRows do detailRows[i]:Hide() end
  frame.detailList:SetHeight(math.max(21, #entries * 21))
end

local function Create(parent, footer)
  frame = CreateFrame("Frame", "EPUGuildGatheringMarket", parent)
  craftMode = true
  frame:SetPoint("TOPLEFT", parent)
  frame:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
  local function Button(text, width, x, y, callback)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(width, 23)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
  end
  local function SetMode(craft, sort)
    craftMode, buySort, frame.selected = craft, sort, nil
    Refresh()
  end
  frame.craftTab = Button("Craft", 69, 12, -7, function() SetMode(true) end)
  frame.gatherTab = Button("Gather", 69, 85, -7, function() SetMode(false) end)
  frame.buyTab = Button("Buy & Craft", 106, 159, -7, function() SetMode(true, buySorts[1].value) end)
  frame.buySort = Button("Profit + demand", 102, 12, -34, function(self)
    ns.OpenMenu(self, buySorts, buySort, function(key) buySort = key; Refresh() end)
  end)
  frame.craftSort = Button("Sort: Profit", 102, 12, -34, function()
    craftSort = craftSort == "skill" and "profit" or "skill"
    frame.selected = nil
    Refresh()
  end)
  frame.professionFilter = Button("All my professions", 155, 12, -61, function(self)
    if guildScope then
      local menu = {{value = false, label = "All guild professions"}}
      for _, option in ipairs(frame.guildChoices or {}) do menu[#menu + 1] = option end
      return ns.OpenMenu(self, menu, guildProfession or false, function(name)
        guildProfession = name or nil
        frame.selected = nil
        Refresh()
      end)
    end
    local menu = {{value = false, label = "All my professions"}}
    for _, option in ipairs(frame.professionChoices) do menu[#menu + 1] = option end
    ns.OpenMenu(self, menu, professionFilter or false, function(id)
      professionFilter = id or nil
      frame.selected = nil
      Refresh()
    end)
  end)
  frame.scope = Button("Scope: Mine", 110, 299, -61, function()
    guildScope = not guildScope
    frame.selected = nil
    Refresh()
  end)
  frame.gatherProfession = Button("Gathering profession", 155, 12, -61, function(self)
    ns.OpenMenu(self, frame.gatherChoices, frame.gatherID, function(id)
      gatherFilter = id
      frame.selected = nil
      Refresh()
    end)
  end)
  frame.openProfession = Button("Open to scan", 120, 173, -61, function(self)
    ns.OpenMenu(self, frame.professionChoices, nil, function(id)
      if not Call(C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill, id) then
        ns.Print("Open this profession from your spellbook to scan its learned recipes.")
      end
    end)
  end)
  skillOnly = true
  frame.skill = Button("My skill: On", 96, 12, -34, function()
    skillOnly = not skillOnly
    frame.selected = nil
    Refresh()
  end)
  frame.sourceButtons = {}
  for i, source in ipairs(sources) do
    frame.sourceButtons[source.key] = Button(source.title, 82, 116 + (i - 1) * 86, -34, function() activeSource = source; Refresh() end)
  end
  Button("Refresh", 73, 374, -34, Refresh)
  frame.professionGuides = Button("Profession guides", 135, 271, -7, function()
    ns.GuideState().savedOnly = false
    ns.OpenMemberTools("guides", "profession")
  end)
  frame.routeButton = Button("Start herb route", 120, 0, 0, function()
    if ns.GatheringRouteCommand("start", nil, frame.gatherID) then ns.UI:Hide() end
  end)
  frame.routeButton:ClearAllPoints()
  frame.routeButton:SetPoint("BOTTOMLEFT", 12, 16)
  frame.yieldSort = Button("Sort: Market", 124, 0, 0, function()
    routeOrder = not routeOrder
    Refresh()
  end)
  frame.yieldSort:ClearAllPoints()
  frame.yieldSort:SetPoint("LEFT", frame.routeButton, "RIGHT", 6, 0)
  frame.zoneFilter = Button("This zone: Off", 116, 0, 0, function()
    zoneOnly = not frame.zoneActive
    frame.selected = nil
    Refresh()
  end)
  frame.zoneFilter:ClearAllPoints()
  frame.zoneFilter:SetPoint("LEFT", frame.yieldSort, "RIGHT", 6, 0)
  frame.context = Label(frame, "")
  frame.context:SetPoint("TOPLEFT", 12, -64)
  frame.context:SetPoint("RIGHT", -12, 0)
  frame.context:SetJustifyH("LEFT")
  frame.context:SetWordWrap(false)
  frame.sourceText = Label(frame, "", "GameFontDisableSmall")
  frame.sourceText:SetPoint("TOPLEFT", 12, -81)
  frame.sourceText:SetPoint("RIGHT", -12, 0)
  frame.sourceText:SetJustifyH("LEFT")
  frame.sourceText:SetWordWrap(false)
  frame.chart = CreateFrame("Frame", nil, frame)
  frame.chart:SetPoint("TOPLEFT", 56, -145)
  local bg = frame.chart:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.09, 0.12, 1)
  frame.xLabels, frame.yLabels = {}, {}
  frame.xGrid, frame.yGrid = {}, {}
  for i = 0, 4 do
    local vertical, horizontal = frame.chart:CreateTexture(nil, "BORDER"), frame.chart:CreateTexture(nil, "BORDER")
    vertical:SetColorTexture(0.3, 0.34, 0.4, 0.6)
    horizontal:SetColorTexture(0.3, 0.34, 0.4, 0.6)
    frame.xGrid[i], frame.yGrid[i] = vertical, horizontal
    frame.xLabels[i] = Label(frame.chart, "")
    frame.yLabels[i] = Label(frame.chart, "")
  end
  Label(frame.chart, "Gold per item"):SetPoint("BOTTOMLEFT", frame.chart, "TOPLEFT", 0, 6)
  Label(frame.chart, "Units sold per day"):SetPoint("TOP", frame.chart, "BOTTOM", 0, -20)
  frame.chartEmpty = Label(frame.chart, "Waiting for price and sales data.")
  frame.chartEmpty:SetPoint("CENTER")
  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.list = CreateFrame("Frame", nil, frame.scroll)
  frame.scroll:SetScrollChild(frame.list)
  frame.empty = Label(frame, "")
  frame.empty:SetPoint("TOPLEFT", 12, -105)
  frame.detail = CreateFrame("Frame", nil, frame)
  frame.detailTitle = Label(frame.detail, "", "GameFontNormalLarge")
  frame.detailTitle:SetPoint("TOPLEFT")
  frame.age = Label(frame.detail, "", "GameFontDisableSmall")
  frame.age:SetPoint("TOPLEFT", 0, -19)
  frame.craftsLabel = Label(frame.detail, "Crafts")
  frame.craftsLabel:SetPoint("TOPLEFT", 0, -33)
  frame.crafts = CreateFrame("EditBox", nil, frame.detail, "InputBoxTemplate")
  frame.crafts:SetSize(60, 24)
  frame.crafts:SetPoint("TOPLEFT", 48, -27)
  frame.crafts:SetAutoFocus(false)
  frame.crafts:SetNumeric(true)
  frame.crafts:SetMaxLetters(3)
  frame.crafts:SetScript("OnTextChanged", function() if frame.selected and craftMode then RenderDetail() end end)
  frame.crafts:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  frame.detailText = Label(frame.detail, "")
  frame.detailText:SetPoint("TOPLEFT", 0, -62)
  frame.detailText:SetJustifyH("LEFT")
  frame.zonePreview = CreateFrame("Frame", nil, frame.detail)
  frame.zonePreview:SetPoint("TOPLEFT", 0, -116)
  local previewBg = frame.zonePreview:CreateTexture(nil, "BACKGROUND")
  previewBg:SetAllPoints()
  previewBg:SetColorTexture(.09, .12, .09, 1)
  frame.zonePins = {}
  frame.yieldLabel = Label(frame.detail, "Your units/hour (Enter to save)")
  frame.yieldLabel:SetPoint("TOPLEFT", 0, -35)
  frame.yieldInput = CreateFrame("EditBox", nil, frame.detail, "InputBoxTemplate")
  frame.yieldInput:SetSize(55, 22)
  frame.yieldInput:SetPoint("TOPLEFT", 183, -31)
  frame.yieldInput:SetAutoFocus(false)
  frame.yieldInput:SetNumeric(true)
  frame.yieldInput:SetMaxLetters(5)
  frame.yieldInput:SetScript("OnEnterPressed", function(self)
    local _, _, map = ns.GatheringRoutePreview(frame.selected.item)
    if map then
      ns.cdb.herbYield = ns.cdb.herbYield or {}
      ns.cdb.herbYield[map] = ns.cdb.herbYield[map] or {}
      ns.cdb.herbYield[map][frame.selected.item] = Number(tonumber(self:GetText()), 1, 99999)
    end
    self:ClearFocus()
    Refresh()
  end)
  frame.detailScroll = CreateFrame("ScrollFrame", nil, frame.detail, "UIPanelScrollFrameTemplate")
  frame.detailScroll:SetPoint("TOPLEFT", 0, -128)
  frame.detailScroll:SetPoint("BOTTOMRIGHT", -20, 29)
  frame.detailList = CreateFrame("Frame", nil, frame.detailScroll)
  frame.detailScroll:SetScrollChild(frame.detailList)
  local function DetailButton(text, width, anchor, x, y, click)
    local button = CreateFrame("Button", nil, frame.detail, "UIPanelButtonTemplate")
    button:SetPoint(anchor, x, y)
    button:SetSize(width, 23)
    button:SetText(text)
    button:SetScript("OnClick", click)
    return button
  end
  frame.startTarget = DetailButton("Start route", 128, "TOPLEFT", 0, -181, function()
    if ns.GatheringRouteCommand("start", frame.selected.item, frame.selected.gatherProfession) then ns.UI:Hide() end
  end)
  frame.markTarget = DetailButton("Record spot", 101, "TOPRIGHT", 0, -181, function()
    ns.RecordGatheringSpot(frame.selected.item)
    RenderDetail()
  end)
  DetailButton("Back to results", 125, "BOTTOMRIGHT", 0, 0, function() frame.selected = nil; Refresh() end)
  local credit = type(AHledgerAPI) == "table" and ns.IsReadableString(AHledgerAPI.CREDIT) and AHledgerAPI.CREDIT
  frame.credit = Label(frame, credit or "Prices from AHledger (ahledger.com)", "GameFontDisableSmall")
  frame.focusText = Label(frame, "")
  frame.focusText:SetPoint("BOTTOMLEFT", 12, 22)
  frame.focusText:SetPoint("RIGHT", -12, 0)
  frame.focusText:SetJustifyH("LEFT")
  frame.focusText:SetWordWrap(false)
  frame.askCrafter = DetailButton("Ask a crafter", 110, "BOTTOMLEFT", 0, 0, function()
    local item = frame.selected and frame.selected.item
    if not item then return end
    ns.UI:SetView("recipes")
    ns.UI:OpenDetails("recipe", "item:" .. item)
  end)
  frame.askCrafter:Hide()
  frame.credit:SetPoint("BOTTOMLEFT", 12, 3)
  ns.On("BAG_UPDATE_DELAYED", function()
    if frame:IsShown() and frame.selected and craftMode then RenderDetail() end
  end)
  ns.On("SKILL_LINES_CHANGED", ns.RefreshGatheringMarket)
  ns.On("GET_ITEM_INFO_RECEIVED", function(item, success)
    if success and frame.pendingItems and frame.pendingItems[item] then
      ns.Debounce("marketItems", .2, ns.RefreshGatheringMarket)
    end
  end)
end

function ns.SetGatheringMarketVisible(visible, parent, footer)
  if not visible then
    if frame then frame:Hide() end
    return
  end
  if not frame then Create(parent, footer) end
  if not activeSource then
    for _, source in ipairs(sources) do
      if Available(source.key) then activeSource = source; break end
    end
    activeSource = activeSource or sources[1]
  end
  frame:Show()
end

function ns.RefreshGatheringMarket()
  if frame and frame:IsShown() and ns.UI:IsShown() then Refresh() end
end

function ns.ShowGatheringMarket()
  ns.UI:Show()
  ns.UI:SetView("market")
end

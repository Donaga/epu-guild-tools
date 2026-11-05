-- EPU Guild Tools: guild data, trust rules, sync, needs, requests, crafters
local ADDON, ns = ...
-- Newer clients keep these under C_Item; the old global names only exist when
-- the game's "deprecated API" fallback is on, which varies from PC to PC.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local DAY = 86400

---------------------------------------------------------------------------
-- Per-guild storage
---------------------------------------------------------------------------
function ns.GuildKey()
  local name = GetGuildInfo("player")
  if not name then return nil end
  return name .. " - " .. (GetRealmName() or "?")
end

function ns.G()
  if not ns.db then return nil end
  local key = ns.GuildKey()
  if not key then return nil end
  local g = ns.db.guilds[key]
  if not g then
    g = {}
    ns.db.guilds[key] = g
  end
  g.officerRank = g.officerRank or 1
  g.needs = g.needs or { v = 0, list = {} }
  g.bank = g.bank or {}          -- [bankAltName] = { v, money, items = {[itemID] = count}, retired }
  g.requests = g.requests or {}  -- [id] = { who, item, qty, note, status, t, u, by }
  g.donations = g.donations or {}-- [id] = { t, who, item, n, money, to }
  g.crafters = g.crafters or {}  -- [member] = { t, lvl, profs = {[name] = skill} }
  g.alts = g.alts or {}          -- [accountId] = { t, main, chars = { names } }
  g.policy = g.policy or { v = 0, maxOpen = 0 }   -- officer settings shared with the guild
  g.policy.designated = g.policy.designated or {}  -- [profession] = { names } (guild crafters)
  g.recipes = g.recipes or {}    -- [member] = { t, profs = {[prof] = { rank, at, items = {ids}, spells = {names}, diff = {[key] = "o"|"y"|"g"} }} }
  g.mats = g.mats or {}          -- [recipeKey] = { t, r = { itemID, count, itemID, count, ... } } (reagents)
  return g
end

function ns.Changed()
  if ns.UI and ns.UI:IsShown() then
    ns.Debounce("ui", 0.3, function() ns.UI:Refresh() end)
  end
  if ns.CloseMetGoals and ns.db and ns.IsTrusted(ns.me) then
    ns.Debounce("goals", 3, ns.CloseMetGoals)
  end
  if ns.RefreshBagMarkers then ns.Debounce("bagmarkers", 1, ns.RefreshBagMarkers) end
end

-- Request states: pending -> approved | rejected -> filled; or cancelled.
-- ("open" is the 0.1.0 name for pending.)
local ACTIVE = { pending = true, approved = true, open = true }
function ns.IsActiveRequest(r) return r and ACTIVE[r.status] == true end
local MEMBER_STATES = { pending = true, open = true, cancelled = true }
local CRAFTER_STATES = { approved = true, filled = true, rejected = true }

-- A craft request goes to one crafter, who may accept (approved), mark it
-- made (filled) or decline (rejected) it, but change nothing else.
function ns.CrafterMayUpdate(sender, cur, r)
  return type(cur) == "table" and cur.crafter ~= nil and cur.crafter == sender
    and r.crafter == cur.crafter and r.who == cur.who and r.item == cur.item and r.spell == cur.spell
    and r.qty == cur.qty and r.mats == cur.mats and r.to == cur.to
    and CRAFTER_STATES[r.status] == true
end

function ns.IsCraftRequest(r) return r ~= nil and r.crafter ~= nil end

-- Display name for what a request is for (an item, or an enchant by name)
function ns.RequestName(r, plain)
  if r.item then return ns.ItemName(r.item, plain) end
  return r.spell or "?"
end

---------------------------------------------------------------------------
-- Roster and trust
---------------------------------------------------------------------------
ns.roster = {}

function ns.RequestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

ns.On("GUILD_ROSTER_UPDATE", function()
  local n = GetNumGuildMembers()
  if not n or n == 0 then return end
  -- Modern clients list offline members whatever the guild window's "Show
  -- offline" box says, so we leave that setting alone (changing it from an
  -- addon can taint the guild window).
  wipe(ns.roster)
  local names = {}
  for i = 1, n do
    local name, rankName, rankIndex, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
    name = ns.Short(name)
    if name then
      local away
      if not online and GetGuildRosterLastOnline then
        local y, m, d, h = GetGuildRosterLastOnline(i)
        if y or m or d or h then away = (y or 0) * 365 + (m or 0) * 30 + (d or 0) + (h or 0) / 24 end
      end
      ns.roster[name] = { rank = rankIndex, rankName = rankName, level = level, online = online,
        class = class, classFile = classFile, zone = zone, away = away }
      names[#names + 1] = name
    end
  end
  -- Saved so the Discord companion can match /link names to real characters.
  local g = ns.G()
  if g then g.members = names end
  if ns.TrackRoster then pcall(ns.TrackRoster, ns.roster) end
  if ns.WatchOfficers then pcall(ns.WatchOfficers, ns.roster) end
  if ns.ReplayHeld then ns.ReplayHeld() end
  ns.Changed()
end)

-- Officers (rank index <= officerRank) and any rank with "bank" in its name
-- are trusted to publish needs, bank contents and donation records.
function ns.IsTrusted(name)
  name = ns.Short(name)
  local g = ns.G()
  local limit = (g and g.officerRank) or 1
  local rank, rankName
  if name == ns.me then
    local _, rn, ri = GetGuildInfo("player")
    rank, rankName = ri, rn
  else
    local r = ns.roster[name]
    if r then rank, rankName = r.rank, r.rankName end
  end
  if rank == nil then return false end
  if rank <= limit then return true end
  if rankName and rankName:lower():find("bank") then return true end
  return false
end

---------------------------------------------------------------------------
-- Unconfirmed records: data a fellow member relayed to us before any officer
-- was online. It fills empty pages, but it never overrides real data, is
-- never passed on, and is replaced (or dropped) by the next officer sync.
---------------------------------------------------------------------------
function ns.Unconf(g, f, k)
  local u = g and g.unconf and g.unconf[f]
  return u ~= nil and u[k] == true
end

function ns.Confirm(g, f, k)
  local u = g and g.unconf and g.unconf[f]
  if u and u[k] then
    u[k] = nil
    if next(u) == nil then g.unconf[f] = nil end
  end
end

function ns.MarkUnconf(g, f, k)
  g.unconf = g.unconf or {}
  g.unconf[f] = g.unconf[f] or {}
  g.unconf[f][k] = true
end

function ns.HasUnconfirmed()
  local g = ns.G()
  return g ~= nil and g.unconf ~= nil and next(g.unconf) ~= nil
end

-- the current record, unless it's only an unconfirmed relay (then real data replaces it)
local function Real(g, f, k, v)
  if ns.Unconf(g, f, k) then return nil end
  return v
end
ns.Real = Real
local Confirm = ns.Confirm

---------------------------------------------------------------------------
-- Merge incoming data. Every record carries a version stamp; newer wins.
---------------------------------------------------------------------------
function ns.Prune(g)
  local now = ns.Now()
  for id, r in pairs(g.requests) do
    if not ns.IsActiveRequest(r) and now - (r.u or 0) > 14 * DAY then g.requests[id] = nil end
  end
  for who, c in pairs(g.crafters) do
    if now - (c.t or 0) > 90 * DAY then g.crafters[who] = nil end
  end
  for id, a in pairs(g.alts) do
    if now - (a.t or 0) > 90 * DAY then g.alts[id] = nil end
  end
  for who, rec in pairs(g.recipes) do
    if now - (rec.t or 0) > 90 * DAY then g.recipes[who] = nil; ns.recipeIndex = nil end
  end
  if ns.PruneGuild then ns.PruneGuild(g) end
  local ids = {}
  for id in pairs(g.donations) do ids[#ids + 1] = id end
  if #ids > 500 then
    table.sort(ids, function(a, b) return (g.donations[a].t or 0) > (g.donations[b].t or 0) end)
    for i = 501, #ids do g.donations[ids[i]] = nil end
  end
end

-- catchingUp: this bundle answers our login sync, so don't announce old news
function ns.Merge(sender, b, catchingUp)
  local g = ns.G()
  if not g or type(b) ~= "table" then return false end
  local trusted = ns.IsTrusted(sender)
  local changed = false

  local nd = b.needs
  if trusted and type(nd) == "table" and type(nd.v) == "number" and type(nd.list) == "table" and (nd.v > g.needs.v or ns.Unconf(g, "needs", "list")) then
    g.needs = { v = nd.v, list = nd.list }
    Confirm(g, "needs", "list")
    changed = true
  end

  if trusted and type(b.bank) == "table" then
    for alt, snap in pairs(b.bank) do
      if type(snap) == "table" and type(snap.v) == "number" then
        local cur = Real(g, "bank", alt, g.bank[alt])
        if not cur or snap.v > cur.v then
          snap.items = snap.items or {}
          g.bank[alt] = snap
          Confirm(g, "bank", alt)
          changed = true
        end
      end
    end
  end

  if type(b.req) == "table" then
    for id, r in pairs(b.req) do
      -- Members may only create or cancel their own requests; approving,
      -- rejecting and filling come from officers.
      if type(r) == "table" and type(r.u) == "number" and (r.item or r.spell)
        and (trusted or (r.who == sender and MEMBER_STATES[r.status]) or ns.CrafterMayUpdate(sender, Real(g, "req", id, g.requests[id]), r)) then
        local cur = Real(g, "req", id, g.requests[id])
        if not cur or r.u > cur.u then
          local oldStatus = cur and cur.status
          g.requests[id] = r
          Confirm(g, "req", id)
          changed = true
          if ns.OnRequestChanged and (oldStatus or not catchingUp) then pcall(ns.OnRequestChanged, id, r, oldStatus) end
        end
      end
    end
  end

  if trusted and type(b.don) == "table" then
    for id, d in pairs(b.don) do
      local cur = Real(g, "don", id, g.donations[id])
      if type(d) == "table" and (not cur or (tonumber(d.u) or 0) > (tonumber(cur.u) or 0)) then
        g.donations[id] = d          -- new, or corrected/voided by an officer
        Confirm(g, "don", id)
        changed = true
      end
    end
  end

  local pol = b.policy
  if trusted and type(pol) == "table" and type(pol.v) == "number" and pol.v > (g.policy.v or 0) then
    local designated = {}
    if type(pol.designated) == "table" then
      for prof, names in pairs(pol.designated) do
        if type(prof) == "string" and type(names) == "table" then
          local list = {}
          for _, n in ipairs(names) do if type(n) == "string" then list[#list + 1] = n end end
          designated[prof] = list
        end
      end
    end
    g.policy = { v = pol.v, maxOpen = tonumber(pol.maxOpen) or 0, designated = designated,
      promoDays = tonumber(pol.promoDays) or 0, promoLevel = tonumber(pol.promoLevel) or 0 }
    changed = true
  end

  if type(b.recipes) == "table" then
    for who, rec in pairs(b.recipes) do
      if type(rec) == "table" and type(rec.t) == "number" and type(rec.profs) == "table" and (trusted or who == sender) then
        local cur = Real(g, "recipes", who, g.recipes[who])
        if not cur or rec.t > cur.t then
          g.recipes[who] = rec
          Confirm(g, "recipes", who)
          changed = true
          ns.recipeIndex = nil
        end
      end
    end
  end

  if type(b.mats) == "table" then
    for key, m in pairs(b.mats) do
      local cur = Real(g, "mats", key, g.mats[key])
      if type(key) == "string" and type(m) == "table" and type(m.t) == "number" and type(m.r) == "table"
        and (not cur or (m.t > (cur.t or 0) and (trusted or sender == m.by))) then
        g.mats[key] = m
        Confirm(g, "mats", key)
        changed = true
      end
    end
  end

  if type(b.craft) == "table" then
    for who, c in pairs(b.craft) do
      if type(c) == "table" and type(c.t) == "number" and (trusted or who == sender) then
        local cur = Real(g, "craft", who, g.crafters[who])
        if not cur or c.t > cur.t then
          g.crafters[who] = c
          Confirm(g, "craft", who)
          changed = true
        end
      end
    end
  end

  -- Alt groups: a player can only publish a group that includes themselves.
  local altsChanged = false
  if type(b.alts) == "table" then
    for id, a in pairs(b.alts) do
      if type(a) == "table" and type(a.t) == "number" and type(a.chars) == "table" and type(a.main) == "string" then
        local mine = trusted
        for _, n in pairs(a.chars) do if n == sender then mine = true end end
        local cur = Real(g, "alts", id, g.alts[id])
        if mine and (not cur or a.t > cur.t) then
          local list = {}
          for _, n in ipairs(a.chars) do if type(n) == "string" then list[#list + 1] = n end end
          g.alts[id] = { t = a.t, main = a.main, chars = list }
          Confirm(g, "alts", id)
          altsChanged = true
        end
      end
    end
  end
  if altsChanged then ns.RebuildAlts() end
  if ns.MergeGuild and ns.MergeGuild(sender, b, trusted, catchingUp) then changed = true end

  if changed or altsChanged then
    ns.Prune(g)
    ns.Changed()
  end
  return changed or altsChanged
end

---------------------------------------------------------------------------
-- Bank helpers
---------------------------------------------------------------------------
function ns.BankAlts()
  local g = ns.G()
  local list = {}
  if not g then return list end
  for alt, s in pairs(g.bank) do
    if not s.retired and not s.guild then list[#list + 1] = alt end
  end
  table.sort(list)
  return list
end

function ns.HasGuildBank()
  local g = ns.G()
  local s = g and g.bank[ns.GB_KEY]
  return s ~= nil and not s.retired
end

-- Where members should send things, e.g. "Epubank (or deposit in the guild bank)"
function ns.BankAltNames()
  local list = ns.BankAlts()
  local alts = (#list > 0) and table.concat(list, ", ") or nil
  if ns.HasGuildBank() then
    return alts and (alts .. " (or deposit in the guild bank)") or "the guild bank"
  end
  return alts or "the bank alt"
end

function ns.BankCount(id)
  local g = ns.G()
  if not g then return 0 end
  local n = 0
  for _, s in pairs(g.bank) do
    if not s.retired and s.items then n = n + (s.items[id] or 0) end
  end
  return n
end

---------------------------------------------------------------------------
-- Needs (officer wish list)
--   restock: a standing minimum the bank should always hold
--   goal:    a one-time target that closes itself once the bank reaches it
-- Stored as list[itemID] = qty (restock) or { q = qty, k = "g" } (goal).
---------------------------------------------------------------------------
function ns.NeedEntry(v)
  if type(v) == "table" then
    return tonumber(v.q) or 0, (v.k == "g") and "goal" or "restock"
  end
  return tonumber(v) or 0, "restock"
end

function ns.SetNeed(id, qty, kind)
  local g = ns.G()
  if not g then return ns.Print("You are not in a guild.") end
  if not ns.IsTrusted(ns.me) then return ns.Print("Only officers can change the needs list.") end
  if qty and qty > 0 then
    g.needs.list[id] = (kind == "goal") and { q = qty, k = "g" } or qty
  else
    g.needs.list[id] = nil
  end
  g.needs.v = ns.NextVersion(g.needs.v)
  ns.Send("D", { needs = g.needs })
  ns.Changed()
  if ns.Log then ns.Log((qty and qty > 0) and ("Set need: " .. ns.ItemName(id, true) .. " x" .. qty .. ((kind == "goal") and " (goal)" or ""))
    or ("Removed need: " .. ns.ItemName(id, true))) end
  if qty and qty > 0 then
    ns.Print(((kind == "goal") and "Goal set: " or "Restock minimum set: ") .. ns.ItemLink(id) .. " x" .. qty)
  else
    ns.Print("Need removed: " .. ns.ItemLink(id))
  end
end

function ns.OpenNeeds()
  local g = ns.G()
  local list = {}
  if not g then return list end
  for id, v in pairs(g.needs.list) do
    local target, kind = ns.NeedEntry(v)
    if target > 0 then
      local have = ns.BankCount(id)
      local frac = math.min(1, have / target)
      list[#list + 1] = { id = id, target = target, kind = kind, have = have,
        rem = math.max(0, target - have), frac = frac, critical = frac < 0.5 }
    end
  end
  table.sort(list, function(a, b)
    if a.frac ~= b.frac then return a.frac < b.frac end
    return a.id < b.id
  end)
  return list
end

-- Officers' clients retire goals once the bank holds enough.
function ns.CloseMetGoals()
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return end
  local done = {}
  for id, v in pairs(g.needs.list) do
    local q, kind = ns.NeedEntry(v)
    if kind == "goal" and q > 0 and ns.BankCount(id) >= q then done[#done + 1] = { id, q } end
  end
  if #done == 0 then return end
  for _, d in ipairs(done) do
    g.needs.list[d[1]] = nil
    ns.Print("Goal reached: " .. ns.ItemLink(d[1]) .. " x" .. d[2] .. ". Removed from the needs list.")
  end
  g.needs.v = ns.NextVersion(g.needs.v)
  ns.Send("D", { needs = g.needs })
  if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end
end

function ns.PostNeeds()
  if not IsInGuild() then return ns.Print("You are not in a guild.") end
  local open = {}
  for _, n in ipairs(ns.OpenNeeds()) do if n.rem > 0 then open[#open + 1] = n end end
  if #open == 0 then return ns.Print("No open needs right now.") end
  SendChatMessage("Guild bank wish list - please mail to " .. ns.BankAltNames() .. ":", "GUILD")
  for i = 1, math.min(5, #open) do
    SendChatMessage("  " .. ns.ItemLink(open[i].id) .. " x" .. open[i].rem, "GUILD")
  end
end

---------------------------------------------------------------------------
-- Shopping list: need shortages plus approved requests, minus what's banked
---------------------------------------------------------------------------
function ns.ShoppingList()
  local g = ns.G()
  local rows = {}
  if not g then return rows end
  local demand = {}
  local function slot(id)
    demand[id] = demand[id] or { need = 0, req = 0 }
    return demand[id]
  end
  for id, v in pairs(g.needs.list) do slot(id).need = (ns.NeedEntry(v)) end
  for _, r in pairs(g.requests) do
    if r.status == "approved" and ns.IsCraftRequest(r) then
      if r.mats == "bank" then      -- the bank supplies the materials
        for _, m in ipairs(ns.MatsFor(r.key)) do
          local d = slot(m.id)
          d.req = d.req + m.n * (tonumber(r.qty) or 1)
        end
      end
    elseif r.status == "approved" and r.item then
      local d = slot(r.item)
      d.req = d.req + (tonumber(r.qty) or 0)
    end
  end
  for id, d in pairs(demand) do
    local have = ns.BankCount(id)
    local buy = math.max(0, d.need + d.req - have)
    if buy > 0 then rows[#rows + 1] = { id = id, need = d.need, req = d.req, have = have, buy = buy } end
  end
  table.sort(rows, function(a, b)
    if a.buy ~= b.buy then return a.buy > b.buy end
    return a.id < b.id
  end)
  return rows
end

ns.SHOPPING_LIST_NAME = "EPU Guild Bank"

function ns.HasAuctionator()
  return type(Auctionator) == "table" and type(Auctionator.API) == "table"
    and type(Auctionator.API.v1) == "table" and type(Auctionator.API.v1.CreateShoppingList) == "function"
end

function ns.ExportAuctionator()
  if not ns.HasAuctionator() then return ns.Print("Auctionator isn't loaded, so there's nothing to export to.") end
  local api = Auctionator.API.v1
  local terms, missing = {}, 0
  for _, r in ipairs(ns.ShoppingList()) do
    local name = GetItemInfo(r.id)
    if name then
      local ok, term = pcall(api.ConvertToSearchString, ADDON, { searchString = name, isExact = true, quantity = r.buy })
      terms[#terms + 1] = (ok and type(term) == "string") and term or name
    else
      missing = missing + 1
    end
  end
  if #terms == 0 then
    return ns.Print(missing > 0 and "Item info is still loading. Try again in a moment." or "Nothing to buy right now.")
  end
  local ok, err = pcall(api.CreateShoppingList, ADDON, ns.SHOPPING_LIST_NAME, terms)
  if not ok then return ns.Print("Auctionator export failed: " .. tostring(err)) end
  ns.Print("Saved " .. #terms .. " items to the Auctionator shopping list \"" .. ns.SHOPPING_LIST_NAME .. "\"."
    .. (missing > 0 and (" " .. missing .. " still loading; export again to include them.") or ""))
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------
-- to: which of my characters to mail it to (defaults to the one asking)
function ns.NewRequest(id, qty, note, to)
  local g = ns.G()
  if not g then return ns.Print("You are not in a guild.") end
  local officer = ns.IsTrusted(ns.me)
  local limit = tonumber(g.policy.maxOpen) or 0
  if not officer and limit > 0 and ns.OpenCountFor(ns.me) >= limit then
    return ns.Print("You already have " .. limit .. " open request" .. (limit == 1 and "" or "s")
      .. " (the guild's limit, counting alts). Cancel one or wait for it to be filled.")
  end
  local now = ns.Now()
  local rid = ns.me .. "-" .. now .. "-" .. math.random(100, 999)
  local r = { who = ns.me, item = id, qty = qty or 1, note = (note or ""):sub(1, 80),
    status = officer and "approved" or "pending", t = now, u = now }
  if officer then r.by = ns.me end
  to = ns.Short(to)
  if to and to ~= ns.me then r.to = to end
  g.requests[rid] = r
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
  if officer then
    ns.Print("Requested " .. ns.ItemLink(id) .. " x" .. r.qty .. (r.to and (" for " .. r.to) or "") .. " (auto-approved, since you're an officer).")
  else
    ns.Print("Requested " .. ns.ItemLink(id) .. " x" .. r.qty .. (r.to and (" for " .. r.to) or "") .. ". An officer will review it.")
  end
end

-- Ask a guildmate to craft something.
--   key:   recipe key ("item:ID" or "spell:Name") from RecipeIndex
--   mats:  "me" (I'll send them), "bank" (the guild bank sends them), "crafter" (crafter's own)
function ns.NewCraftRequest(key, crafter, qty, mats, note, to)
  local g = ns.G()
  if not g then return ns.Print("You are not in a guild.") end
  local e = ns.RecipeFor(key)
  if not e or not crafter then return ns.Print("That recipe isn't in the guild's list.") end
  if mats ~= "bank" and mats ~= "crafter" then mats = "me" end
  local now = ns.Now()
  local rid = ns.me .. "-" .. now .. "-" .. math.random(100, 999)
  local r = { who = ns.me, crafter = crafter, key = key, item = e.item, spell = (not e.item) and e.name or nil,
    qty = math.max(1, math.floor(tonumber(qty) or 1)), mats = mats, note = (note or ""):sub(1, 80),
    status = "pending", t = now, u = now }
  to = ns.Short(to)
  if to and to ~= ns.me then r.to = to end
  g.requests[rid] = r
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
  ns.Print("Asked " .. crafter .. " to craft " .. (e.item and ns.ItemLink(e.item) or e.name) .. " x" .. r.qty
    .. ". " .. ((mats == "me") and "Mail them the materials." or (mats == "bank") and "An officer will send the materials." or "They'll use their own materials."))
  return rid
end

-- Can I act as the crafter on this request? (it's addressed to one of my characters)
function ns.IAmCrafter(r)
  if not r or not r.crafter then return false end
  if r.crafter == ns.me then return true end
  for _, c in ipairs(ns.MyChars()) do if c == r.crafter then return true end end
  return false
end

-- status: "approved", "rejected", "filled" (officers) or "cancelled" (requester or officers)
function ns.SetRequestStatus(rid, status, reason, by)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return end
  local officer = ns.IsTrusted(ns.me)
  local crafter = r.crafter == ns.me and CRAFTER_STATES[status]
  if not officer and not crafter and not (r.who == ns.me and status == "cancelled") then
    return ns.Print("Only officers can approve, reject or fill requests.")
  end
  r.status = status
  r.by = by or ns.me
  if status == "rejected" then r.reason = (reason or ""):sub(1, 80) end
  r.u = ns.NextVersion(r.u)
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
  if officer and r.who ~= ns.me and ns.Log then
    ns.Log(status:gsub("^%l", string.upper) .. " " .. r.who .. "'s request for " .. ns.RequestName(r, true) .. " x" .. tostring(r.qty)
      .. ((by and by ~= ns.me) and (" (from Discord, by " .. by .. ")") or ""))
  end
end

-- Fix a request. Officers can change anything, including moving it back to
-- pending or approved. The requester can change quantity, note and
-- deliver-to while it's still pending, or cancel it.
--   changes: { qty, note, to, status, reason }
function ns.EditRequest(rid, changes)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return false end
  local officer = ns.IsTrusted(ns.me)
  local own = (r.who == ns.me)
  local pending = (r.status == "pending" or r.status == "open")
  if not officer and r.crafter == ns.me and not own then
    -- the crafter: accept, mark made, or decline (with a reason); nothing else
    if not changes.status or not CRAFTER_STATES[changes.status] then ns.Print("As the crafter you can accept, mark made or decline this.") return false end
    changes = { status = changes.status, reason = changes.reason }
  elseif not officer then
    if not own then ns.Print("Only officers can change other members' requests.") return false end
    if changes.status and changes.status ~= "cancelled" then ns.Print("Only officers can approve, reject or fill requests.") return false end
    if not pending and (changes.qty or changes.note or changes.to) then ns.Print("This request is already being handled; ask an officer to change it.") return false end
  end
  if changes.qty then r.qty = math.max(1, math.floor(tonumber(changes.qty) or r.qty)) end
  if changes.note then r.note = changes.note:sub(1, 80) end
  if changes.to then
    local to = ns.Short(changes.to)
    r.to = (to and to ~= r.who) and to or nil
  end
  if changes.status and changes.status ~= r.status then
    if officer and not own and ns.Log then
      ns.Log(changes.status:gsub("^%l", string.upper) .. " " .. r.who .. "'s " .. (r.crafter and "craft " or "") .. "request for "
        .. ns.RequestName(r, true) .. " x" .. tostring(r.qty) .. ((changes.reason and changes.reason ~= "") and (": " .. changes.reason) or ""))
    end
    r.status = changes.status
    r.by = ns.me
    if changes.status == "rejected" then r.reason = (changes.reason or ""):sub(1, 80) else r.reason = nil end
    r.archived = nil
  elseif changes.reason and r.status == "rejected" then
    r.reason = changes.reason:sub(1, 80)
  end
  r.u = ns.NextVersion(r.u)
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
  return true
end

-- Officers: hide finished (filled, rejected, cancelled) requests from the default views.
function ns.ArchiveFinished()
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return 0 end
  local batch, n = {}, 0
  for rid, r in pairs(g.requests) do
    if not ns.IsActiveRequest(r) and not r.archived then
      r.archived = true
      r.u = ns.NextVersion(r.u)
      batch[rid] = r
      n = n + 1
    end
  end
  if n > 0 then ns.Send("D", { req = batch }); ns.Changed(); if ns.Log then ns.Log("Tidied " .. n .. " finished requests") end end
  return n
end

-- Officers: mark a donation record as a mistake (kept, but no longer counted).
function ns.VoidDonation(id, void)
  local g = ns.G()
  local d = g and g.donations[id]
  if not d or not ns.IsTrusted(ns.me) then return end
  d.void = (void ~= false) or nil
  d.u = ns.NextVersion(math.max(d.u or 0, d.t or 0))
  ns.Send("D", { don = { [id] = d } })
  ns.Changed()
  if ns.Log then ns.Log((d.void and "Voided" or "Restored") .. " a donation from " .. tostring(d.who) .. ": "
    .. (d.item and (ns.ItemName(d.item, true) .. " x" .. (d.n or 1)) or (math.floor((d.money or 0) / 10000) .. "g"))) end
end

-- Officer settings shared with the guild.
function ns.SetPolicy(key, value)
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can change guild bank settings.") end
  g.policy[key] = value
  g.policy.v = ns.NextVersion(g.policy.v)
  ns.Send("D", { policy = g.policy })
  ns.Changed()
  if ns.Log then ns.Log("Changed setting " .. tostring(key) .. " to " .. tostring(value)) end
end

-- Open (pending or approved) requests for a player, counting all their alts.
function ns.OpenCountFor(name)
  local g = ns.G()
  if not g then return 0 end
  local player, n = ns.MainOf(name), 0
  for _, r in pairs(g.requests) do
    if ns.IsActiveRequest(r) and not r.crafter and ns.MainOf(r.who) == player then n = n + 1 end
  end
  return n
end

-- Called when a trusted character mails or trades items to someone:
-- any approved request of theirs for one of those items is marked filled.
-- A crafter sending what they made fills their craft request the same way.
function ns.AutoFillFor(recipient, items)
  local g = ns.G()
  if not g then return end
  local officer = ns.IsTrusted(ns.me)
  recipient = ns.Member(recipient) or ns.Short(recipient)
  if not recipient then return end
  local sent = {}
  for _, it in ipairs(items) do sent[it[1]] = true end
  for rid, r in pairs(g.requests) do
    local mine = (r.crafter and r.crafter == ns.me) or (not r.crafter and officer)
    if mine and (r.to or r.who) == recipient and r.status == "approved" and r.item and sent[r.item] then
      ns.SetRequestStatus(rid, "filled")
      ns.Print("Marked " .. recipient .. "'s request for " .. ns.ItemLink(r.item) .. " as filled.")
    end
  end
end

---------------------------------------------------------------------------
-- Crafters: professions and skill levels, shared guild-wide
---------------------------------------------------------------------------
local KNOWN_PROFS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
  Herbalism = true, Leatherworking = true, Mining = true, Skinning = true,
  Tailoring = true, Jewelcrafting = true, Inscription = true,
  Cooking = true, ["First Aid"] = true, Fishing = true,
}

-- Modern clients (WoW: Forever included) list professions through GetProfessions().
local function ModernProfessions()
  local profs = {}
  if not GetProfessions or not GetProfessionInfo then return nil end
  for _, index in pairs({ GetProfessions() }) do
    if index then
      local name, _, skill = GetProfessionInfo(index)
      if name and skill then profs[name] = skill end
    end
  end
  return profs
end

function ns.ScanProfessions()
  local g = ns.G()
  if not g then return end
  local profs = {}
  local inProf, riding = false, nil
  local modern = (not GetNumSkillLines or GetNumSkillLines() == 0) and ModernProfessions() or nil
  if modern then
    profs = modern
  elseif not GetNumSkillLines then
    return
  else
  riding = false
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if isHeader then
      inProf = (name == "Professions" or name == "Secondary Skills"
        or (TRADE_SKILLS ~= nil and name == TRADE_SKILLS)
        or (SECONDARY_SKILLS ~= nil and name == SECONDARY_SKILLS))
    elseif name == "Riding" or (RIDING ~= nil and name == RIDING) then
      riding = true
    elseif name and (inProf or KNOWN_PROFS[name]) then
      profs[name] = rank
    end
  end
  end
  local cur = g.crafters[ns.me]
  if ns.ProfessionMilestones and cur then pcall(ns.ProfessionMilestones, cur.profs, profs) end
  if ns.RidingMilestone and ns.cdb and riding ~= nil then
    if ns.cdb.riding ~= nil then pcall(ns.RidingMilestone, ns.cdb.riding, riding) end
    ns.cdb.riding = riding
  end
  local lvl = UnitLevel("player")
  if not cur and not next(profs) then return end
  if cur and ns.SameCounts(cur.profs, profs) and cur.lvl == lvl then return end
  g.crafters[ns.me] = { t = ns.NextVersion(cur and cur.t), lvl = lvl, profs = profs }
  ns.Send("D", { craft = { [ns.me] = g.crafters[ns.me] } })
  ns.Changed()
end

ns.On("SKILL_LINES_CHANGED", function()
  ns.Debounce("profs", 10, ns.ScanProfessions)
end)
ns.On("PLAYER_LEVEL_UP", function()
  ns.Debounce("profs", 10, ns.ScanProfessions)
end)
-- learning, unlearning or skilling up a profession (modern clients)
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CHAT_MSG_SKILL", "LEARNED_SPELL_IN_TAB" }) do
  ns.On(ev, function() ns.Debounce("profs", 3, ns.ScanProfessions) end)
end

---------------------------------------------------------------------------
-- Recipes: each character remembers its own recipes (scanned when the
-- profession window opens). "Who can craft X?" is asked live, and anyone
-- who knows it answers by whisper, so no big recipe lists are synced.
---------------------------------------------------------------------------
-- One scanned profession window:
--   ids[itemID] = true, names[lowercase] = true, spells = { enchant names },
--   diff[key] = "o" | "y" | "g" (orange/yellow/green: still gives skill points),
--   mats[key] = { itemID, count, itemID, count, ... }
local function SaveRecipes(prof, rank, ids, names, spells, diff, mats)
  if not prof or not ns.cdb then return end
  ns.cdb.recipes[prof] = { rank = rank, ids = ids, names = names, spells = spells, diff = diff, mats = mats, t = ns.Now() }
  ns.Debounce("publishRecipes", 2, function() ns.PublishRecipes() end)
end
ns.SaveRecipes = SaveRecipes

-- Is this item bind-on-pickup? (nil while the client hasn't loaded the item)
function ns.IsBoP(id)
  local bind = select(14, GetItemInfo(id))
  if bind == nil then return nil end
  return bind == 1
end

local REFRESH_AGE = DAY   -- re-share unchanged recipes at most daily so "updated" stays honest

-- Share this character's craftable (non-BoP) recipes with the guild.
function ns.PublishRecipes(force)
  local g = ns.G()
  if not g or not ns.cdb then return end
  local profs, sig, mats = {}, {}, {}
  local now = ns.Now()
  for prof, r in pairs(ns.cdb.recipes or {}) do
    local items, spells, diff = {}, {}, {}
    for id in pairs(r.ids or {}) do
      if ns.IsBoP(id) ~= true then items[#items + 1] = id end
    end
    for _, name in ipairs(r.spells or {}) do spells[#spells + 1] = name end
    table.sort(items)
    table.sort(spells)
    local dsig = {}
    for _, id in ipairs(items) do
      local k = "item:" .. id
      if r.diff and r.diff[k] then diff[k] = r.diff[k]; dsig[#dsig + 1] = id .. r.diff[k] end
      if r.mats and r.mats[k] then mats[k] = r.mats[k] end
    end
    for _, sp in ipairs(spells) do
      local k = "spell:" .. sp
      if r.diff and r.diff[k] then diff[k] = r.diff[k]; dsig[#dsig + 1] = sp .. r.diff[k] end
      if r.mats and r.mats[k] then mats[k] = r.mats[k] end
    end
    profs[prof] = { rank = r.rank, at = r.t, items = items, spells = spells, diff = next(diff) and diff or nil }
    sig[#sig + 1] = prof .. ":" .. tostring(r.rank) .. ":" .. table.concat(items, ",") .. ":" .. table.concat(spells, ",") .. ":" .. table.concat(dsig, ",")
  end
  table.sort(sig)
  local signature = table.concat(sig, "|")
  local cur = g.recipes[ns.me]
  if not force and cur and ns.cdb.recipeSig == signature and now - (cur.t or 0) < REFRESH_AGE then return end
  local changedRecipes = ns.cdb.recipeSig ~= signature
  ns.cdb.recipeSig = signature
  g.recipes[ns.me] = { t = ns.NextVersion(cur and cur.t), profs = profs }
  -- Reagents are the same for everyone: only send ones the guild doesn't have yet (or that changed).
  local newMats
  for k, list in pairs(mats) do
    local have = g.mats[k]
    if not have or table.concat(have.r, ",") ~= table.concat(list, ",") then
      g.mats[k] = { t = ns.NextVersion(have and have.t), r = list, by = ns.me }
      newMats = newMats or {}
      newMats[k] = g.mats[k]
    end
  end
  ns.recipeIndex = nil
  ns.Send("D", { recipes = { [ns.me] = g.recipes[ns.me] }, mats = newMats })
  if changedRecipes or newMats then ns.Changed() end
end

-- Officers: mark (or unmark) a member as a guild crafter for a profession.
function ns.SetDesignated(prof, name, on)
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can choose guild crafters.") end
  local list = g.policy.designated[prof] or {}
  local out = {}
  for _, n in ipairs(list) do if n ~= name then out[#out + 1] = n end end
  if on then out[#out + 1] = name end
  g.policy.designated[prof] = (#out > 0) and out or nil
  g.policy.v = ns.NextVersion(g.policy.v)
  ns.Send("D", { policy = g.policy })
  ns.Changed()
  if ns.Log then ns.Log((on and "Made " or "Removed ") .. name .. (on and " guild " or " as guild ") .. prof:lower()) end
end

function ns.IsDesignated(name, prof)
  local g = ns.G()
  local list = g and g.policy.designated and g.policy.designated[prof]
  for _, n in ipairs(list or {}) do if n == name then return true end end
  return false
end

-- Every craftable recipe in the guild:
--   { key, item, name, prof, crafters = { {who, prof, rank, diff, at} } }
function ns.RecipeIndex()
  if ns.recipeIndex then return ns.recipeIndex end
  local g = ns.G()
  local byKey, list = {}, {}
  for who, rec in pairs((g and g.recipes) or {}) do
    for prof, p in pairs(rec.profs or {}) do
      local function add(key, item, name)
        local e = byKey[key]
        if not e then
          e = { key = key, item = item, name = name, prof = prof, crafters = {} }
          byKey[key] = e
          list[#list + 1] = e
        end
        e.crafters[#e.crafters + 1] = { who = who, prof = prof, rank = p.rank,
          diff = p.diff and p.diff[key] or nil, at = p.at or rec.t }
      end
      for _, id in ipairs(p.items or {}) do add("item:" .. id, id, nil) end
      for _, sp in ipairs(p.spells or {}) do add("spell:" .. sp, nil, sp) end
    end
  end
  ns.recipeIndex, ns.recipeByKey = list, byKey
  return list
end

function ns.RecipeFor(key)
  ns.RecipeIndex()
  return ns.recipeByKey and ns.recipeByKey[key]
end

-- The guild crafters' list for an item, for tooltips: guild crafters first, then online, then by skill.
function ns.CraftersOf(key)
  local e = ns.RecipeFor(key)
  if not e then return {} end
  local list = {}
  for _, c in ipairs(e.crafters) do list[#list + 1] = c end
  local function on(n) return ns.roster[n] ~= nil and ns.roster[n].online == true end
  table.sort(list, function(a, b)
    local da, db = ns.IsDesignated(a.who, a.prof), ns.IsDesignated(b.who, b.prof)
    if da ~= db then return da end
    if on(a.who) ~= on(b.who) then return on(a.who) end
    if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
    return a.who < b.who
  end)
  return list
end

-- Find a recipe by the name it makes ("Woolen Bag"), for recipe/pattern tooltips.
function ns.RecipeByName(name)
  if not name or name == "" then return nil end
  name = name:lower()
  for _, e in ipairs(ns.RecipeIndex()) do
    local n = e.item and GetItemInfo(e.item) or e.name
    if n and n:lower() == name then return e end
  end
  return nil
end

-- Reagents for a recipe: { {id, n}, ... } (empty until a crafter has shared them)
function ns.MatsFor(key)
  local g = ns.G()
  local m = g and key and g.mats[key]
  local out = {}
  if not m or type(m.r) ~= "table" then return out end
  for i = 1, #m.r - 1, 2 do
    local id, n = tonumber(m.r[i]), tonumber(m.r[i + 1])
    if id and n and n > 0 then out[#out + 1] = { id = id, n = n } end
  end
  return out
end

-- How many times the guild bank's stock could make this recipe (nil if reagents unknown)
function ns.CraftsCovered(key)
  local mats = ns.MatsFor(key)
  if #mats == 0 then return nil end
  local best = math.huge
  for _, m in ipairs(mats) do best = math.min(best, math.floor(ns.BankCount(m.id) / m.n)) end
  return best
end

-- Officers: make sure the bank keeps enough materials for `crafts` crafts.
function ns.StockMatsFor(key, crafts)
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can change the needs list.") end
  local mats = ns.MatsFor(key)
  if #mats == 0 then return ns.Print("The materials for that recipe haven't been shared yet.") end
  crafts = math.max(1, tonumber(crafts) or 5)
  local added = {}
  for _, m in ipairs(mats) do
    local target, kind = ns.NeedEntry(g.needs.list[m.id])
    local want = m.n * crafts
    if want > target then
      g.needs.list[m.id] = (kind == "goal") and { q = want, k = "g" } or want
      added[#added + 1] = ns.ItemLink(m.id) .. " x" .. want
    end
  end
  if #added == 0 then return ns.Print("The needs list already covers " .. crafts .. " crafts.") end
  g.needs.v = ns.NextVersion(g.needs.v)
  ns.Send("D", { needs = g.needs })
  ns.Changed()
  if ns.Log then ns.Log("Stocked materials for " .. crafts .. " crafts: " .. table.concat(added, ", "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|r", "")) end
  ns.Print("Bank needs updated: " .. table.concat(added, ", "))
end

-- Profession coverage for officers: one row per profession.
ns.ALL_PROFS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring",
  "Herbalism", "Mining", "Skinning", "Cooking", "First Aid", "Fishing" }
function ns.Coverage()
  local g = ns.G()
  local rows, byProf = {}, {}
  local function row(p)
    if not byProf[p] then
      byProf[p] = { prof = p, count = 0, online = 0, best = 0, bestWho = nil, guild = {}, recipes = 0 }
      rows[#rows + 1] = byProf[p]
    end
    return byProf[p]
  end
  for _, p in ipairs(ns.ALL_PROFS) do row(p) end
  if not g then return rows end
  local counted = {}
  for who, c in pairs(g.crafters) do
    local main = ns.MainOf(who)
    for p, skill in pairs(c.profs or {}) do
      local r = row(p)
      local k = p .. "\0" .. main
      if not counted[k] then counted[k] = true; r.count = r.count + 1 end   -- players, not characters
      if ns.roster[who] and ns.roster[who].online then r.online = r.online + 1 end
      if (tonumber(skill) or 0) > r.best then r.best, r.bestWho = tonumber(skill), who end
      if ns.IsDesignated(who, p) then r.guild[#r.guild + 1] = who end
    end
  end
  for _, e in ipairs(ns.RecipeIndex()) do if byProf[e.prof] then byProf[e.prof].recipes = byProf[e.prof].recipes + 1 end end
  return rows
end

-- Scanning ---------------------------------------------------------------
local CLASSIC_DIFF = { optimal = "o", medium = "y", easy = "g" }   -- trivial (gray) gives nothing

local function ScanTradeSkill()
  if not GetTradeSkillLine or not GetNumTradeSkills then return end
  local prof, rank = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end
  local ids, names, spells, diff, mats = {}, {}, {}, {}, {}
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      names[name:lower()] = true
      local id = ns.ItemID(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
      local key
      if id then ids[id] = true; key = "item:" .. id else spells[#spells + 1] = name; key = "spell:" .. name end
      diff[key] = CLASSIC_DIFF[kind]
      if GetTradeSkillNumReagents then
        local r = {}
        for j = 1, (GetTradeSkillNumReagents(i) or 0) do
          local _, _, count = GetTradeSkillReagentInfo(i, j)
          local rid = ns.ItemID(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j))
          if rid and count then r[#r + 1] = rid; r[#r + 1] = count end
        end
        if #r > 0 then mats[key] = r end
      end
    end
  end
  SaveRecipes(prof, rank, ids, names, spells, diff, mats)
end

-- Enchanting (and Beast Training) use the separate Craft window in vanilla.
local function ScanCraft()
  if not GetNumCrafts or not GetCraftDisplaySkillLine then return end
  local prof, rank = GetCraftDisplaySkillLine()
  if not prof then return end
  local ids, names, spells, diff, mats = {}, {}, {}, {}, {}
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      names[name:lower()] = true
      local id = ns.ItemID(GetCraftItemLink and GetCraftItemLink(i))
      local key
      if id then ids[id] = true; key = "item:" .. id else spells[#spells + 1] = name; key = "spell:" .. name end   -- enchants are services, not items
      diff[key] = CLASSIC_DIFF[kind]
      if GetCraftNumReagents then
        local r = {}
        for j = 1, (GetCraftNumReagents(i) or 0) do
          local _, _, count = GetCraftReagentInfo(i, j)
          local rid = ns.ItemID(GetCraftReagentItemLink and GetCraftReagentItemLink(i, j))
          if rid and count then r[#r + 1] = rid; r[#r + 1] = count end
        end
        if #r > 0 then mats[key] = r end
      end
    end
  end
  SaveRecipes(prof, rank, ids, names, spells, diff, mats)
end

-- Modern clients (C_TradeSkillUI) in case Forever's profession window uses them.
local MODERN_DIFF = { [0] = "o", [1] = "y", [2] = "g" }
local function ScanModern()
  local T = C_TradeSkillUI
  if not T or not T.GetAllRecipeIDs or not T.GetRecipeInfo then return end
  local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  local prof = (info and info.professionName) or (child and child.professionName)
  local rank = (child and child.skillLevel and child.skillLevel > 0 and child.skillLevel) or (info and info.skillLevel)
  if not prof or prof == "" then return end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end      -- someone else's window
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
  local ids, names, spells, diff, mats = {}, {}, {}, {}, {}
  for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(recipeID)
    if r and r.learned and r.name then
      names[r.name:lower()] = true
      local sch = T.GetRecipeSchematic and T.GetRecipeSchematic(recipeID, false)
      local id = sch and sch.outputItemID
      if (not id) and T.GetRecipeItemLink then id = ns.ItemID(T.GetRecipeItemLink(recipeID)) end
      local key
      if id then ids[id] = true; key = "item:" .. id else spells[#spells + 1] = r.name; key = "spell:" .. r.name end
      diff[key] = MODERN_DIFF[r.relativeDifficulty]
      local list = {}
      for _, slot in ipairs((sch and sch.reagentSlotSchematics) or {}) do
        local basic = (slot.reagentType == nil) or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
        local rg = slot.reagents and slot.reagents[1]
        if basic and rg and rg.itemID and slot.quantityRequired then list[#list + 1] = rg.itemID; list[#list + 1] = slot.quantityRequired end
      end
      if #list > 0 then mats[key] = list end
    end
  end
  if next(names) then SaveRecipes(prof, rank, ids, names, spells, diff, mats) end
end

local function ScanAny()
  if GetNumTradeSkills and (GetNumTradeSkills() or 0) > 0 then ScanTradeSkill() else pcall(ScanModern) end
end

ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.5, ScanAny) end)
ns.On("TRADE_SKILL_UPDATE", function() ns.Debounce("tradescan", 1, ScanAny) end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() ns.Debounce("tradescan", 1, ScanAny) end)
ns.On("CRAFT_SHOW", function() C_Timer.After(0.5, ScanCraft) end)
ns.On("CRAFT_UPDATE", function() ns.Debounce("craftscan", 1, ScanCraft) end)

local function MyMatches(q)
  local hits = {}
  for prof, r in pairs((ns.cdb and ns.cdb.recipes) or {}) do
    local hit = (q.id and r.ids and r.ids[q.id]) or (q.name and r.names and r.names[q.name])
    if not hit and q.name and r.names then
      for n in pairs(r.names) do
        if n:find(q.name, 1, true) then hit = true break end
      end
    end
    if hit then hits[#hits + 1] = { prof = prof, rank = r.rank } end
  end
  return hits
end

ns.whoResults = { label = nil, list = {} }

function ns.AskWhoCrafts(text)
  text = text or ""
  local id = ns.ItemID(text)
  local name
  if id then
    name = GetItemInfo(id)
  else
    name = text:match("^%s*%[?(.-)%]?%s*$")
  end
  if (not id) and (not name or name == "") then
    return ns.Print("Usage: /epu who <item link or name>")
  end
  local q = { id = id, name = name and name:lower() or nil }
  ns.whoResults = { label = id and ns.ItemLink(id) or name, list = {} }
  for _, h in ipairs(MyMatches(q)) do
    table.insert(ns.whoResults.list, { who = ns.me, prof = h.prof, rank = h.rank })
  end
  if IsInGuild() then ns.Send("W", q) end
  ns.Print("Asking the guild who can craft " .. ns.whoResults.label .. "...")
  ns.Changed()
end

ns.comm.W = function(sender, q)
  if type(q) ~= "table" then return end
  local hits = MyMatches(q)
  if #hits > 0 then ns.Send("A", { q = q, hits = hits }, "WHISPER", sender) end
end

ns.comm.A = function(sender, a)
  if type(a) ~= "table" or type(a.hits) ~= "table" then return end
  for _, h in ipairs(a.hits) do
    table.insert(ns.whoResults.list, { who = sender, prof = h.prof, rank = h.rank })
    ns.Print(sender .. " can craft " .. tostring(ns.whoResults.label) .. " (" .. tostring(h.prof) .. " " .. tostring(h.rank or "?") .. ")")
  end
  ns.Changed()
end

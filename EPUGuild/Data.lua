-- EPU Guild Tools: guild data, trust rules, sync, needs, requests, crafters
local ADDON, ns = ...

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
  return g
end

function ns.Changed()
  if ns.UI and ns.UI:IsShown() then
    ns.Debounce("ui", 0.3, function() ns.UI:Refresh() end)
  end
  if ns.CloseMetGoals and ns.db and ns.IsTrusted(ns.me) then
    ns.Debounce("goals", 3, ns.CloseMetGoals)
  end
end

-- Request states: pending -> approved | rejected -> filled; or cancelled.
-- ("open" is the 0.1.0 name for pending.)
local ACTIVE = { pending = true, approved = true, open = true }
function ns.IsActiveRequest(r) return r and ACTIVE[r.status] == true end
local MEMBER_STATES = { pending = true, open = true, cancelled = true }

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
  wipe(ns.roster)
  local names = {}
  for i = 1, n do
    local name, rankName, rankIndex, level, _, _, _, _, online = GetGuildRosterInfo(i)
    name = ns.Short(name)
    if name then
      ns.roster[name] = { rank = rankIndex, rankName = rankName, level = level, online = online }
      names[#names + 1] = name
    end
  end
  -- Saved so the Discord companion can match /link names to real characters.
  local g = ns.G()
  if g then g.members = names end
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
  local ids = {}
  for id in pairs(g.donations) do ids[#ids + 1] = id end
  if #ids > 500 then
    table.sort(ids, function(a, b) return (g.donations[a].t or 0) > (g.donations[b].t or 0) end)
    for i = 501, #ids do g.donations[ids[i]] = nil end
  end
end

function ns.Merge(sender, b)
  local g = ns.G()
  if not g or type(b) ~= "table" then return false end
  local trusted = ns.IsTrusted(sender)
  local changed = false

  local nd = b.needs
  if trusted and type(nd) == "table" and type(nd.v) == "number" and type(nd.list) == "table" and nd.v > g.needs.v then
    g.needs = { v = nd.v, list = nd.list }
    changed = true
  end

  if trusted and type(b.bank) == "table" then
    for alt, snap in pairs(b.bank) do
      if type(snap) == "table" and type(snap.v) == "number" then
        local cur = g.bank[alt]
        if not cur or snap.v > cur.v then
          snap.items = snap.items or {}
          g.bank[alt] = snap
          changed = true
        end
      end
    end
  end

  if type(b.req) == "table" then
    for id, r in pairs(b.req) do
      -- Members may only create or cancel their own requests; approving,
      -- rejecting and filling come from officers.
      if type(r) == "table" and type(r.u) == "number" and r.item
        and (trusted or (r.who == sender and MEMBER_STATES[r.status])) then
        local cur = g.requests[id]
        if not cur or r.u > cur.u then
          g.requests[id] = r
          changed = true
        end
      end
    end
  end

  if trusted and type(b.don) == "table" then
    for id, d in pairs(b.don) do
      local cur = g.donations[id]
      if type(d) == "table" and (not cur or (tonumber(d.u) or 0) > (tonumber(cur.u) or 0)) then
        g.donations[id] = d          -- new, or corrected/voided by an officer
        changed = true
      end
    end
  end

  local pol = b.policy
  if trusted and type(pol) == "table" and type(pol.v) == "number" and pol.v > (g.policy.v or 0) then
    g.policy = { v = pol.v, maxOpen = tonumber(pol.maxOpen) or 0 }
    changed = true
  end

  if type(b.craft) == "table" then
    for who, c in pairs(b.craft) do
      if type(c) == "table" and type(c.t) == "number" and (trusted or who == sender) then
        local cur = g.crafters[who]
        if not cur or c.t > cur.t then
          g.crafters[who] = c
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
        local cur = g.alts[id]
        if mine and (not cur or a.t > cur.t) then
          local list = {}
          for _, n in ipairs(a.chars) do if type(n) == "string" then list[#list + 1] = n end end
          g.alts[id] = { t = a.t, main = a.main, chars = list }
          altsChanged = true
        end
      end
    end
  end
  if altsChanged then ns.RebuildAlts() end

  if changed or altsChanged then
    ns.Prune(g)
    ns.Changed()
  end
  return changed or altsChanged
end

---------------------------------------------------------------------------
-- Sync: a client that logs in sends "H" with its needs/bank versions and the
-- time of its last completed sync. One online officer answers with
-- everything newer ("D", tagged sync = requester). Other officers see that
-- answer go by on the guild channel and stand down, so there's no pile-on.
---------------------------------------------------------------------------
function ns.EmptyDigest()
  return { needs = 0, bank = {}, since = 0, ver = ns.VERSION }
end

function ns.Digest()
  local g = ns.G()
  local d = ns.EmptyDigest()
  if not g then return d end
  d.needs = g.needs.v
  d.policy = g.policy.v
  for alt, s in pairs(g.bank) do d.bank[alt] = s.v end
  d.since = g.syncedAt or 0
  return d
end

function ns.Delta(d)
  local g = ns.G()
  if not g then return nil end
  local b = {}
  local since = tonumber(d.since) or 0
  if g.needs.v > (tonumber(d.needs) or 0) then b.needs = g.needs end
  if (g.policy.v or 0) > (tonumber(d.policy) or 0) then b.policy = g.policy end
  for alt, s in pairs(g.bank) do
    if s.v > ((type(d.bank) == "table" and tonumber(d.bank[alt])) or 0) then
      b.bank = b.bank or {}
      b.bank[alt] = s
    end
  end
  for id, r in pairs(g.requests) do
    if r.u > since then b.req = b.req or {}; b.req[id] = r end
  end
  for id, x in pairs(g.donations) do
    if math.max(x.t or 0, tonumber(x.u) or 0) > since then b.don = b.don or {}; b.don[id] = x end
  end
  for who, c in pairs(g.crafters) do
    if c.t > since then b.craft = b.craft or {}; b.craft[who] = c end
  end
  for id, a in pairs(g.alts) do
    if (a.t or 0) > since then b.alts = b.alts or {}; b.alts[id] = a end
  end
  return b
end

ns.pendingHello = {}

-- A guildmate's addon is newer than ours: tell the player once per session.
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["EPUGUILD_UPDATE"] = {
  text = "EPU Guild Tools %s is out (you have %s).\n\nDouble-click \"Update EPU Guild Tools\" from the updater, or get it with /download in the guild Discord. Then type /reload.",
  button1 = OKAY or "Okay",
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.NoteVersion(sender, ver)
  if type(ver) ~= "string" or ns.VersionNumber(ver) <= ns.VersionNumber(ns.VERSION) then return end
  if ns.newestVersion and ns.VersionNumber(ns.newestVersion) >= ns.VersionNumber(ver) then return end
  ns.newestVersion = ver
  ns.Print("|cfff2c14eUpdate available:|r version " .. ver .. " (you have " .. ns.VERSION .. "). Run the EPU updater or use /download in the guild Discord.")
  if StaticPopup_Show then StaticPopup_Show("EPUGUILD_UPDATE", ver, ns.VERSION) end
  ns.Changed()
end

ns.comm.H = function(sender, d)
  if type(d) ~= "table" then return end
  ns.NoteVersion(sender, d.ver)
  if not ns.IsTrusted(ns.me) then return end
  ns.pendingHello[sender] = d
  C_Timer.After(1 + math.random() * 5, function()
    local dd = ns.pendingHello[sender]
    ns.pendingHello[sender] = nil
    if not dd then return end          -- another officer already answered
    local b = ns.Delta(dd)
    if not b then return end
    b.sync = sender
    b.ver = ns.VERSION
    ns.Send("D", b)
  end)
end

ns.comm.D = function(sender, b, channel)
  if type(b) ~= "table" then return end
  if b.ver then ns.NoteVersion(sender, b.ver) end
  ns.Merge(sender, b)
  if b.sync and channel == "GUILD" and ns.IsTrusted(sender) then
    if b.sync == ns.me then
      local g = ns.G()
      -- Small overlap margin so records stamped around the hello aren't missed.
      if g and ns.helloAt then g.syncedAt = math.max(g.syncedAt or 0, ns.helloAt - 300) end
    else
      ns.pendingHello[b.sync] = nil
    end
  end
end

function ns.SendHello()
  if not IsInGuild() then return end
  ns.helloAt = ns.Now()
  ns.Send("H", ns.Digest())
end

function ns.FullSync()
  if not IsInGuild() then return ns.Print("You are not in a guild.") end
  ns.helloAt = ns.Now()
  ns.Send("H", ns.EmptyDigest())
  ns.Print("Asked online officers for a full sync.")
end

-- Re-announce our own records so officers who were offline catch up.
function ns.BroadcastMine()
  local g = ns.G()
  if not g then return end
  local b, any = {}, false
  if g.crafters[ns.me] then b.craft = { [ns.me] = g.crafters[ns.me] }; any = true end
  local id = ns.db and ns.db.accountId
  if id and g.alts[id] then b.alts = { [id] = g.alts[id] }; any = true end
  for id, r in pairs(g.requests) do
    if r.who == ns.me and ns.IsActiveRequest(r) then
      b.req = b.req or {}
      b.req[id] = r
      any = true
    end
  end
  if any then ns.Send("D", b) end
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin == false and isReload == false then return end
  ns.RequestRoster()
  C_Timer.After(8, function()
    if not IsInGuild() then return end
    ns.RequestRoster()
    ns.ScanProfessions()
    ns.PublishAlts()
    ns.SendHello()
    C_Timer.After(4, ns.BroadcastMine)
  end)
end)

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
    if r.status == "approved" and r.item then
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

-- status: "approved", "rejected", "filled" (officers) or "cancelled" (requester or officers)
function ns.SetRequestStatus(rid, status, reason, by)
  local g = ns.G()
  local r = g and g.requests[rid]
  if not r then return end
  local officer = ns.IsTrusted(ns.me)
  if not officer and not (r.who == ns.me and status == "cancelled") then
    return ns.Print("Only officers can approve, reject or fill requests.")
  end
  r.status = status
  r.by = by or ns.me
  if status == "rejected" then r.reason = (reason or ""):sub(1, 80) end
  r.u = ns.NextVersion(r.u)
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
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
  if not officer then
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
  if n > 0 then ns.Send("D", { req = batch }); ns.Changed() end
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
end

-- Officer settings shared with the guild.
function ns.SetPolicy(key, value)
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can change guild bank settings.") end
  g.policy[key] = value
  g.policy.v = ns.NextVersion(g.policy.v)
  ns.Send("D", { policy = g.policy })
  ns.Changed()
end

-- Open (pending or approved) requests for a player, counting all their alts.
function ns.OpenCountFor(name)
  local g = ns.G()
  if not g then return 0 end
  local player, n = ns.MainOf(name), 0
  for _, r in pairs(g.requests) do
    if ns.IsActiveRequest(r) and ns.MainOf(r.who) == player then n = n + 1 end
  end
  return n
end

-- Called when a trusted character mails or trades items to someone:
-- any approved request of theirs for one of those items is marked filled.
function ns.AutoFillFor(recipient, items)
  local g = ns.G()
  if not g or not ns.IsTrusted(ns.me) then return end
  recipient = ns.Member(recipient) or ns.Short(recipient)
  if not recipient then return end
  local sent = {}
  for _, it in ipairs(items) do sent[it[1]] = true end
  for rid, r in pairs(g.requests) do
    if (r.to or r.who) == recipient and r.status == "approved" and sent[r.item] then
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

function ns.ScanProfessions()
  local g = ns.G()
  if not g or not GetNumSkillLines then return end
  local profs = {}
  local inProf = false
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if isHeader then
      inProf = (name == "Professions" or name == "Secondary Skills"
        or (TRADE_SKILLS ~= nil and name == TRADE_SKILLS)
        or (SECONDARY_SKILLS ~= nil and name == SECONDARY_SKILLS))
    elseif name and (inProf or KNOWN_PROFS[name]) then
      profs[name] = rank
    end
  end
  local cur = g.crafters[ns.me]
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

---------------------------------------------------------------------------
-- Recipes: each character remembers its own recipes (scanned when the
-- profession window opens). "Who can craft X?" is asked live, and anyone
-- who knows it answers by whisper, so no big recipe lists are synced.
---------------------------------------------------------------------------
local function SaveRecipes(prof, rank, ids, names)
  if not prof or not ns.cdb then return end
  ns.cdb.recipes[prof] = { rank = rank, ids = ids, names = names, t = ns.Now() }
end

local function ScanTradeSkill()
  if not GetTradeSkillLine or not GetNumTradeSkills then return end
  local prof, rank = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end
  local ids, names = {}, {}
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" then
      names[name:lower()] = true
      local id = ns.ItemID(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
      if id then ids[id] = true end
    end
  end
  SaveRecipes(prof, rank, ids, names)
end

-- Enchanting (and Beast Training) use the separate Craft window in vanilla.
local function ScanCraft()
  if not GetNumCrafts or not GetCraftDisplaySkillLine then return end
  local prof, rank = GetCraftDisplaySkillLine()
  if not prof then return end
  local ids, names = {}, {}
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      names[name:lower()] = true
      local id = ns.ItemID(GetCraftItemLink and GetCraftItemLink(i))
      if id then ids[id] = true end
    end
  end
  SaveRecipes(prof, rank, ids, names)
end

ns.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.5, ScanTradeSkill) end)
ns.On("TRADE_SKILL_UPDATE", function() ns.Debounce("tradescan", 1, ScanTradeSkill) end)
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

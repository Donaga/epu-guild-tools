-- EPU Guild Tools: needed mats.
-- Crafters list the materials they still need (for leveling a profession or a
-- big craft). Everyone with the addon sees "Needed by: Name (x20)" on that
-- item's tooltip, so it can go to a guildmate before it goes to a vendor or the
-- auction house.
--
-- Each character keeps its own list (per-character saved variables) and
-- publishes it as one guild record, synced like the shared gathering spots:
-- members can only publish their own list, officers can clear entries, and a
-- list nobody has refreshed for 30 days ages out.
local ADDON, ns = ...

ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS + 1] = "neededMats"
local DAY = 86400
local MAX_ITEMS, MAX_MEMBERS, MAX_QTY = 40, 1000, 10000
local REFRESH = 7 * DAY    -- owners re-stamp their list at login after this long
local STALE = 30 * DAY     -- lists older than this are hidden (and pruned by PruneCasual)
local LINE = { 0.45, 0.82, 0.95 }

local function Store()
  local g = ns.CasualStore and ns.CasualStore()
  return g and g.neededMats
end

-- This character's own list:
--   items[itemID] = { q = amount wanted (0 = no amount), got = gained since added,
--                     last = bag count last seen, p = profession, a = added }
--   pubT = revision of the record we last published
local function Mine()
  if not ns.cdb then return nil end
  local m = ns.cdb.neededMats
  if type(m) ~= "table" then m = {}; ns.cdb.neededMats = m end
  if type(m.items) ~= "table" then m.items = {} end
  return m
end

local function BagCount(id)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not fn then return 0 end
  local ok, n = pcall(fn, id)
  return (ok and tonumber(n)) or 0
end

local function Remaining(e)
  local q = tonumber(e.q) or 0
  if q <= 0 then return 0 end
  return math.max(0, q - (tonumber(e.got) or 0))
end

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function First(name)
  return (name and name:match("^(%S+)")) or name or "?"
end

local function Refresh()
  if ns.RefreshNeededMatsWindow then ns.RefreshNeededMatsWindow() end
end

---------------------------------------------------------------------------
-- Which profession a material is for: what the player typed, else the first
-- of their shared recipes that uses it.
---------------------------------------------------------------------------
local function Profession(id, typed)
  if type(typed) == "string" and typed:find("%S") then
    local want = typed:lower():match("^%s*(.-)%s*$")
    for _, p in ipairs(ns.ALL_PROFS or {}) do
      if p:lower() == want or p:lower():sub(1, #want) == want then return p end
    end
  end
  local g = ns.G()
  local rec = g and g.recipes and g.recipes[ns.me]
  local profs = {}
  for prof in pairs((rec and rec.profs) or {}) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    for _, item in pairs(rec.profs[prof].items or {}) do
      for _, m in ipairs(ns.MatsFor("item:" .. item)) do
        if m.id == id then return prof end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Publishing and merging the guild record
--   neededMats[who] = { who, t, i = { [itemID] = { n = still needed (0 = any), p = profession } }, by }
--   by: the officer who last cleared something from it, if anyone did
---------------------------------------------------------------------------
local function Build()
  local out = {}
  for id, e in pairs(Mine().items) do out[id] = { n = Remaining(e), p = e.p } end
  return out
end

-- An officer may have cleared entries since we last published: drop those
-- here too, so our next publish doesn't put them back.
local function Adopt()
  local store, m = Store(), Mine()
  local cur = store and m and store[ns.me]
  if not cur or (tonumber(cur.t) or 0) <= (tonumber(m.pubT) or 0) or type(cur.i) ~= "table" then return false end
  local removed = {}
  for id in pairs(m.items) do
    if not cur.i[id] then m.items[id] = nil; removed[#removed + 1] = ns.ItemLink(id) end
  end
  m.pubT = cur.t
  if #removed > 0 and cur.by and cur.by ~= ns.me then
    ns.Print(cur.by .. " cleared " .. table.concat(removed, ", ") .. " from your needed mats.")
  end
  return #removed > 0
end

-- announce: also resend an unchanged list (at login, for guildmates who missed it)
function ns.PublishNeededMats(announce)
  local store, m = Store(), Mine()
  if not store or not m or not ns.me then return end
  Adopt()
  local items = Build()
  local cur = store[ns.me]
  if not cur and next(items) == nil then return end   -- never had a list: nothing to say
  if cur and ns.Fingerprint(cur.i) == ns.Fingerprint(items) and ns.Now() - (tonumber(cur.t) or 0) < REFRESH then
    if announce and next(items) ~= nil then ns.Send("D", { neededMats = { [ns.me] = cur } }) end
    return
  end
  local r = { who = ns.me, t = ns.NextVersion(cur and cur.t), i = items }
  store[ns.me] = r
  m.pubT = r.t
  ns.Send("D", { neededMats = { [ns.me] = r } })
  ns.Changed()
end

-- Returns a clean copy of a record's items, or nil if anything is out of shape.
local function CleanItems(i)
  if type(i) ~= "table" then return end
  local out, n = {}, 0
  for id, e in pairs(i) do
    n = n + 1
    if n > MAX_ITEMS or not ns.PositiveInt(id, 10000000) or type(e) ~= "table" then return end
    local qty = e.n
    if type(qty) ~= "number" or qty ~= qty or qty < 0 or qty > MAX_QTY or qty % 1 ~= 0 then return end
    local p = e.p
    if p ~= nil and not (ns.IsReadableString(p) and #p > 0 and #p <= 24 and not p:find("[%c|]")) then return end
    out[id] = { n = qty, p = p }
  end
  return out
end

function ns.MergeNeededMats(sender, b, trusted)
  if type(b) ~= "table" or type(b.neededMats) ~= "table" then return false end
  local store = Store()
  if not store then return false end
  sender = ns.Short(sender)
  local size, changed, mine = Count(store), false, false
  for who, r in pairs(b.neededMats) do
    if type(who) == "string" and #who <= 80 and type(r) == "table" and r.who == who
      and (trusted or who == sender) and ns.StampOK(r.t) and r.t <= ns.Now() + 300 then
      local items = CleanItems(r.i)
      local cur = store[who]
      if items and (cur or size < MAX_MEMBERS) and ns.Newer(r, cur, "t") then
        local by = trusted and ns.IsReadableString(r.by) and #r.by <= 80 and r.by or nil
        store[who] = { who = who, t = r.t, i = items, by = by }
        if not cur then size = size + 1 end
        changed = true
        if who == ns.me then mine = true end
      end
    end
  end
  if mine and Adopt() then ns.Debounce("neededMatsPublish", 3, ns.PublishNeededMats) end
  if changed then ns.Changed(); Refresh() end
  return changed
end

---------------------------------------------------------------------------
-- Your own list
---------------------------------------------------------------------------
function ns.AddNeededMat(id, qty, prof)
  if not ns.G() then return ns.Print("You are not in a guild.") end
  local m = Mine()
  id = tonumber(id)
  if not m or not ns.PositiveInt(id, 10000000) then
    return ns.Print("Shift-click or drag the material, for example: /epu mats add [Linen Cloth] 20")
  end
  qty = tonumber(qty) or 0
  if qty < 0 or qty > MAX_QTY or qty % 1 ~= 0 then return ns.Print("The amount must be a whole number up to 10000.") end
  local e = m.items[id]
  if not e then
    if Count(m.items) >= MAX_ITEMS then
      return ns.Print("Your needed mats list is full (" .. MAX_ITEMS .. " items). Remove one first.")
    end
    e = { a = ns.Now() }
    m.items[id] = e
  end
  e.q, e.got, e.last = qty, 0, BagCount(id)
  e.p = Profession(id, prof) or e.p
  ns.Debounce("neededMatsPublish", 2, ns.PublishNeededMats)
  ns.Print("Added " .. ns.ItemLink(id) .. (qty > 0 and (" x" .. qty) or "") .. " to your needed mats"
    .. (e.p and (" (" .. e.p .. ")") or "") .. ". Guildmates see it on the item's tooltip.")
  Refresh()
  return true
end

function ns.RemoveNeededMat(id)
  local m = Mine()
  id = tonumber(id)
  if not m or not id or not m.items[id] then return ns.Print("That item isn't on your needed mats list.") end
  m.items[id] = nil
  ns.Debounce("neededMatsPublish", 2, ns.PublishNeededMats)
  ns.Print("Removed " .. ns.ItemLink(id) .. " from your needed mats.")
  Refresh()
  return true
end

function ns.ClearMyNeededMats()
  local m = Mine()
  if not m or next(m.items) == nil then return ns.Print("Your needed mats list is already empty.") end
  wipe(m.items)
  ns.Debounce("neededMatsPublish", 2, ns.PublishNeededMats)
  ns.Print("Cleared your needed mats list.")
  Refresh()
end

-- { {id, q, need, got, p, a}, ... } sorted by item name
function ns.MyNeededMats()
  local list = {}
  local m = Mine()
  if not m then return list end
  for id, e in pairs(m.items) do
    list[#list + 1] = { id = id, q = tonumber(e.q) or 0, need = Remaining(e), got = tonumber(e.got) or 0, p = e.p, a = e.a }
  end
  table.sort(list, function(a, b)
    local an, bn = ns.ItemName(a.id, true) or "", ns.ItemName(b.id, true) or ""
    if an ~= bn then return an < bn end
    return a.id < b.id
  end)
  return list
end

-- Count what arrives in your bags after you add a material (loot, mail, trade,
-- the auction house). Using some for crafting doesn't undo that progress.
-- Moving stacks to and from your own bank doesn't count.
local tracking = false
local function Track()
  local m = Mine()
  if not m or not tracking then return end
  local banking = BankFrame and BankFrame.IsShown and BankFrame:IsShown()
  local changed, done = false, {}
  for id, e in pairs(m.items) do
    local count = BagCount(id)
    local last = tonumber(e.last) or count
    if count > last and not banking and (tonumber(e.q) or 0) > 0 then
      e.got = (tonumber(e.got) or 0) + (count - last)
      changed = true
    end
    e.last = count
    if (tonumber(e.q) or 0) > 0 and Remaining(e) == 0 then done[#done + 1] = id end
  end
  for _, id in ipairs(done) do
    local q = m.items[id].q
    m.items[id] = nil
    ns.Print("You have the " .. q .. " " .. ns.ItemLink(id) .. " you needed, so it's off your needed mats.")
  end
  if changed or #done > 0 then
    ns.Debounce("neededMatsPublish", #done > 0 and 2 or 15, ns.PublishNeededMats)
    Refresh()
  end
end
ns.TrackNeededMats = Track
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("neededMatsTrack", 1, Track) end)

ns.On("PLAYER_LOGIN", function()
  -- Bags can still be loading at login: take fresh counts before counting gains.
  C_Timer.After(10, function()
    local m = Mine()
    if m then for id, e in pairs(m.items) do e.last = BagCount(id) end end
    tracking = true
  end)
  -- Publish once the officer sync has had a chance to bring in any clears.
  local tries = 0
  local function publish()
    tries = tries + 1
    if not ns.G() or (not (ns.IsSynced and ns.IsSynced()) and tries < 6) then
      if tries < 12 then C_Timer.After(30, publish) end
      return
    end
    ns.PublishNeededMats(true)
  end
  C_Timer.After(30, publish)
end)

---------------------------------------------------------------------------
-- The guild's lists
---------------------------------------------------------------------------
local function Visible(who, r, now)
  return type(r) == "table" and type(r.i) == "table" and ns.InGuild(who) and now - (tonumber(r.t) or 0) <= STALE
end

-- Who needs this item: { {who, n, p, online, me}, ... }, your own characters first, then online.
function ns.NeededBy(id)
  local list = {}
  id = tonumber(id)
  local store = Store()
  if not store or not id then return list end
  local now = ns.Now()
  for who, r in pairs(store) do
    local e = who ~= ns.me and Visible(who, r, now) and r.i[id]
    if e then
      local ro = ns.roster[who]
      list[#list + 1] = { who = who, n = e.n or 0, p = e.p, online = ro and ro.online or false }
    end
  end
  local own = Mine() and Mine().items[id]
  if own then list[#list + 1] = { who = ns.me, n = Remaining(own), p = own.p, online = true, me = true } end
  table.sort(list, function(a, b)
    if (a.me or false) ~= (b.me or false) then return a.me == true end
    if a.online ~= b.online then return a.online end
    return a.who < b.who
  end)
  return list
end

-- Everyone else's entries: { {id, who, n, p, online}, ... } sorted by item, then name.
function ns.GuildNeededMats()
  local list = {}
  local store = Store()
  if not store then return list end
  local now = ns.Now()
  for who, r in pairs(store) do
    if who ~= ns.me and Visible(who, r, now) then
      local ro = ns.roster[who]
      for id, e in pairs(r.i) do
        list[#list + 1] = { id = id, who = who, n = e.n or 0, p = e.p, online = ro and ro.online or false }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.id ~= b.id then
      local an, bn = ns.ItemName(a.id, true) or "", ns.ItemName(b.id, true) or ""
      if an ~= bn then return an < bn end
      return a.id < b.id
    end
    return a.who < b.who
  end)
  return list
end

-- Officers: take one item (or, with id nil, everything) off a member's list.
function ns.ClearNeededMat(who, id)
  if who == ns.me then
    if id then return ns.RemoveNeededMat(id) end
    return ns.ClearMyNeededMats()
  end
  if not ns.IsTrusted(ns.me) then return ns.Print("Only officers can clear a guildmate's needed mats.") end
  local store = Store()
  local cur = store and store[who]
  if not cur or type(cur.i) ~= "table" then return end
  id = tonumber(id)
  local items = {}
  for k, e in pairs(cur.i) do
    if id and k ~= id then items[k] = { n = e.n, p = e.p } end
  end
  local r = { who = who, t = ns.NextVersion(cur.t), i = items, by = ns.me }
  store[who] = r
  ns.Send("D", { neededMats = { [who] = r } })
  ns.Changed()
  Refresh()
  local what = id and ns.ItemName(id, true) or "everything"
  if ns.Log then ns.Log("Cleared " .. what .. " from " .. who .. "'s needed mats") end
  ns.Print("Cleared " .. (id and ns.ItemLink(id) or "everything") .. " from " .. who .. "'s needed mats.")
  return true
end

---------------------------------------------------------------------------
-- Tooltip: "Needed by: you (x5), Ana (x20), Bo"
---------------------------------------------------------------------------
function ns.NeededMatsTooltip(tt, id)
  local list = ns.NeededBy(id)
  if #list == 0 then return false end
  local names = {}
  for i = 1, math.min(3, #list) do
    local c = list[i]
    local n = c.me and "you" or First(c.who)
    if not c.me and c.online then n = "|cff4ade80" .. n .. "|r" end
    if c.n > 0 then n = n .. " (x" .. c.n .. ")" end
    names[#names + 1] = n
  end
  if #list > 3 then names[#names + 1] = "+" .. (#list - 3) .. " more" end
  tt:AddLine("Needed by: " .. table.concat(names, ", "), LINE[1], LINE[2], LINE[3])
  return true
end

---------------------------------------------------------------------------
-- /epu mats
---------------------------------------------------------------------------
function ns.NeededMatsCommand(args)
  args = args or ""
  local verb, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
  verb = (verb or ""):lower()
  if verb == "" and ns.ShowNeededMats then return ns.ShowNeededMats() end
  if verb == "clear" then return ns.ClearMyNeededMats() end
  if verb == "list" or verb == "" then
    local mine = ns.MyNeededMats()
    if #mine == 0 then return ns.Print("Your needed mats list is empty. Add one with /epu mats add [item] [amount].") end
    for _, e in ipairs(mine) do
      ns.Print("  " .. ns.ItemLink(e.id) .. (e.q > 0 and (" x" .. e.need .. " of " .. e.q) or "") .. (e.p and (" (" .. e.p .. ")") or ""))
    end
    return
  end
  if verb == "remove" or verb == "del" or verb == "delete" then
    local id = ns.ParseItemArgs(rest)
    if not id then return ns.Print("Usage: /epu mats remove <item link>") end
    return ns.RemoveNeededMat(id)
  end
  if verb ~= "add" then rest = args end     -- "/epu mats [Linen Cloth] 20" adds too
  local id, qty, prof = ns.ParseItemArgs(rest)
  if not id then
    return ns.Print("Usage: /epu mats add <item link> [amount] [profession], /epu mats remove <item>, /epu mats list, /epu mats clear")
  end
  return ns.AddNeededMat(id, qty, prof)
end


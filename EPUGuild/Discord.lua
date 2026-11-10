-- EPU Guild Tools: the in-game half of the Discord link.
--
-- WoW addons can't reach the internet. The EPU Discord companion (a small
-- program on an officer's PC) bridges the gap through two files:
--   * game -> Discord: it reads this addon's SavedVariables, which WoW writes
--     on /reload and logout (/epu save does a /reload).
--   * Discord -> game: it writes requests and approvals made in Discord into
--     Inbox.lua in this folder, which WoW loads at login and /reload.
-- Only officers' clients apply inbox entries, so the companion should run
-- on an officer's PC.
local ADDON, ns = ...
-- Newer clients keep these under C_Item; the old global names only exist when
-- the game's "deprecated API" fallback is on, which varies from PC to PC.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local DAY = 86400

---------------------------------------------------------------------------
-- Item names, so the companion can show and autocomplete items by name
---------------------------------------------------------------------------
function ns.CacheItemNames()
  local g = ns.G()
  if not g or not ns.db then return end
  ns.db.itemNames = ns.db.itemNames or {}
  ns.db.itemClass = ns.db.itemClass or {}        -- [itemID] = { classID, subclassID }, so Discord can group by type
  local names, classes = ns.db.itemNames, ns.db.itemClass
  local function add(id)
    if type(id) ~= "number" or (names[id] and classes[id]) then return end
    local name, _, _, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(id)
    if not classID and GetItemInfoInstant then
      local _,_,_,_,_,c,sc=GetItemInfoInstant(id); classID,subclassID=c,sc
    end
    if name then names[id] = name end
    if classID then classes[id] = { classID, subclassID or 0 } end
  end
  for id in pairs(g.needs.list) do add(id) end
  for _, s in pairs(g.bank) do
    for id in pairs(s.items or {}) do add(id) end
    for id in pairs(s.seen or {}) do add(id) end
  end
  for id in pairs(ns.BankCatalog()) do add(id) end
  for _, r in pairs(g.requests) do add(r.item) end
  for _, d in pairs(g.donations) do add(d.item) end
  for _, rec in pairs(g.recipes or {}) do
    for _, p in pairs(rec.profs or {}) do for _, id in ipairs(p.items or {}) do add(id) end end
  end
  for _, m in pairs(g.mats or {}) do
    for i = 1, #(m.r or {}), 2 do add(m.r[i]) end
  end
end

ns.On("PLAYER_LOGOUT", function()
  pcall(ns.CacheItemNames)
end)

---------------------------------------------------------------------------
-- Inbox
---------------------------------------------------------------------------
local function ResolveItem(e)
  if tonumber(e.item) then return tonumber(e.item) end
  if type(e.itemName) == "string" and e.itemName ~= "" then
    local id = ns.ItemID(e.itemName)
    if id then return id end
    local want = e.itemName:lower()
    for cid, name in pairs((ns.db and ns.db.itemNames) or {}) do
      if name:lower() == want then return cid end
    end
  end
  return nil
end

-- A request made on someone's behalf (from Discord). rid is fixed by the
-- companion ("d-<entry id>") so it can tie its Discord message to it.
function ns.CreateRequestFor(who, item, qty, note, discord, rid, to)
  local g = ns.G()
  if not g then return end
  if g.requests[rid] then return rid end
  if not ns.CanBankRequest(item) or not ns.PositiveInt(tonumber(qty) or 1,1000) then return end
  local now = ns.Now()
  local r = { who = ns.Member(who) or ns.Short(who), item = item, qty = tonumber(qty) or 1, note = (note or ""):sub(1, 80),
    status = "pending", t = now, u = now, via = "discord", discord = discord }
  to = to and (ns.Member(to) or ns.Short(to))
  if to and to ~= r.who then r.to = to end
  g.requests[rid] = r
  ns.Send("D", { req = { [rid] = r } })
  ns.Changed()
  return rid
end

function ns.ProcessInbox()
  local inbox = EPUGuildInbox
  local g = ns.G()
  if type(inbox) ~= "table" or not g or not ns.db then return end
  ns.db.inboxDone = ns.db.inboxDone or {}
  local done = ns.db.inboxDone
  local now = ns.Now()
  for id, t in pairs(done) do
    if now - t > 30 * DAY then done[id] = nil end
  end

  local pending = 0
  for _, e in ipairs(inbox) do
    if type(e) == "table" and e.id and not done[e.id] then pending = pending + 1 end
  end
  if pending == 0 then return end
  local officer=ns.IsTrusted(ns.me)
  if not officer and not (ns.IsSyncHelper and ns.IsSyncHelper(ns.me)) then return end

  local applied, waiting = 0, 0
  for _, e in ipairs(inbox) do
    if type(e) == "table" and e.id and not done[e.id] then
      local ok = false
      local key=ns.GuildKey()
      local wrongGuild=e.bridge and (type(e.guild)~='string' or (key~=e.guild and key:sub(1,#e.guild+3)~=e.guild..' - '))
      if e.bridge and (wrongGuild or type(e.bridgeIssued)~='number' or now-e.bridgeIssued>86400 or e.bridgeIssued>now+300) then
        ok=true -- stale/cross-guild helper actions are discarded, never applied
      elseif e.kind == "guild_invite" then
        ok=ns.ImportGuildInvite(e)
      elseif not officer and e.kind=='request' then
        local item=ResolveItem(e)
        if item and e.who then ok=ns.CreateRequestFor(e.who,item,e.qty,e.note,e.discord,'d-'..e.id,e.to)~=nil end
      elseif not officer then
        ok=false -- whitelisted helpers cannot import officer-only actions
      elseif e.kind=='sync_helper' then
        ok=ns.SetSyncHelper(e.who,e.enabled==true)
      elseif e.kind == "request" then
        local item = ResolveItem(e)
        if item and e.who then
          ok = ns.CreateRequestFor(e.who, item, e.qty, e.note, e.discord, "d-" .. e.id, e.to)~=nil
          if not ok and now-(tonumber(e.t) or now)>7*DAY then
            ok=true; ns.Print('Dropped a Discord request outside the bank catalog: '..tostring(e.itemName or item))
          end
        elseif now - (tonumber(e.t) or now) > 7 * DAY then
          ok = true    -- item never resolved; give up
          ns.Print("Dropped a Discord request for an unknown item: " .. tostring(e.itemName or e.item))
        end
      elseif e.kind == "checklist" then
        ok = ns.SetChecklist(e.who, e.step, e.done, e.note)
      elseif e.kind == "status" then
        local r = e.rid and g.requests[e.rid]
        if r then
          if ns.IsActiveRequest(r) then ns.SetRequestStatus(e.rid, e.status, e.reason, e.by) end
          ok = true
        elseif now - (tonumber(e.t) or now) > 7 * DAY then
          ok = true
        end
      elseif e.kind == "news" then
        -- /announce, or a post copied from the Discord announcements channel.
        -- e.nid is the post's own id, so edits update the same announcement.
        local g2 = ns.GuildStore()
        local nid = e.nid or ("d-" .. e.id)
        local cur = g2 and g2.news[nid]
        if g2 and (not cur or (e.edit and not cur.removed)) then
          ns.PostNews(e.title, e.text, nid, e.by and (e.by .. " (Discord)") or nil,
            { quiet = e.quiet, t = tonumber(e.posted) })
          if g2.news[nid] then g2.news[nid].via = "discord" end
        end
        ok = true
      elseif e.kind == "news_remove" then
        local g2 = ns.GuildStore()
        if g2 and e.nid and g2.news[e.nid] and not g2.news[e.nid].removed then ns.RemoveNews(e.nid) end
        ok = true
      else
        ok = true      -- unknown kind from a newer companion
      end
      if ok then
        done[e.id] = now
        applied = applied + 1
      else
        waiting = waiting + 1
      end
    end
  end
  if applied > 0 then
    ns.Print("Applied " .. applied .. " request update" .. (applied == 1 and "" or "s") .. " from Discord.")
  end
  if waiting > 0 then
    ns.Print(waiting .. " Discord update(s) are waiting on item info, bank catalog or sync; they'll retry on the next /reload.")
  end
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin == false and isReload == false then return end
  C_Timer.After(15, function() pcall(ns.ProcessInbox) end)
end)

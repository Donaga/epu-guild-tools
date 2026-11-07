-- EPU Guild Tools: guild management
--   * roster details (level, class, zone, last seen) and member profiles (role, "looking for")
--   * milestones feed (levels, first mount, profession ranks, big donations, new members)
--   * officer member review (join date, activity, promotion check, officer notes)
--   * officer log (who did what)
--   * announcements (pop up for everyone at login, mirrored to Discord)
local ADDON, ns = ...

local DAY = 86400
local ROLES = { t = "Tank", h = "Healer", d = "DPS" }
ns.ROLES = ROLES

local function G() return ns.G() end

local function Store(g)
  g.profiles = g.profiles or {}   -- [name] = { t, roles = "th", lf = "LF Deadmines" }   (members publish their own)
  g.feed     = g.feed or {}       -- [id] = { t, who, kind, text }                         (milestones)
  g.news     = g.news or {}       -- [id] = { t, u, by, title, text, removed }             (officers)
  g.log      = g.log or {}        -- [id] = { t, by, text }                                (officers)
  g.notes    = g.notes or {}      -- [name] = { t, by, text }                              (officers)
  g.joined   = g.joined or {}     -- [name] = { t = first seen, r = recorded, seed = true if already here at install }
  g.lvlLog   = g.lvlLog or {}     -- [name] = { t1, lvl1, t2, lvl2, ... }  (local to this PC; not synced)
  return g
end

function ns.GuildStore()
  local g = G()
  return g and Store(g)
end

local function NewID(prefix)
  return (prefix or "") .. ns.me .. "-" .. ns.Now() .. "-" .. math.random(1000, 9999)
end

---------------------------------------------------------------------------
-- Officer log
---------------------------------------------------------------------------
function ns.Log(text)
  local g = ns.GuildStore()
  if not g or not ns.me or not ns.IsTrusted(ns.me) or not text then return end
  local id = NewID("L")
  local e = { t = ns.Now(), by = ns.me, text = tostring(text):sub(1, 160) }
  g.log[id] = e
  ns.pendingLog = ns.pendingLog or {}
  ns.pendingLog[id] = e
  ns.Debounce("logSend", 2, function()
    local p = ns.pendingLog
    ns.pendingLog = {}
    if p and next(p) then ns.Send("O", { log = p }, "OFFICER") end
  end)
end

function ns.LogEntries()
  local g = ns.GuildStore()
  local list = {}
  for id, e in pairs((g and g.log) or {}) do list[#list + 1] = { id = id, t = e.t, by = e.by, text = e.text } end
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return list
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
function ns.SetProfile(roles, lf)
  local g = ns.GuildStore()
  if not g then return end
  local cur = g.profiles[ns.me]
  local set = {}
  for r in (roles or ""):gmatch("[thd]") do set[r] = true end
  local norm = (set.t and "t" or "") .. (set.h and "h" or "") .. (set.d and "d" or "")
  g.profiles[ns.me] = { t = ns.NextVersion(cur and cur.t), roles = norm ~= "" and norm or nil,
    lf = (lf and lf ~= "") and lf:sub(1, 60) or nil }
  ns.Send("D", { profiles = { [ns.me] = g.profiles[ns.me] } })
  ns.Changed()
end

-- A player's profile: their own character's, else their main's or any alt's.
function ns.ProfileOf(name)
  local g = ns.GuildStore()
  if not g then return nil end
  if g.profiles[name] then return g.profiles[name] end
  local main = ns.MainOf(name)
  if g.profiles[main] then return g.profiles[main] end
  for _, a in ipairs(ns.AltsOf(main)) do if g.profiles[a] then return g.profiles[a] end end
  return nil
end

function ns.RoleText(roles)
  local out = {}
  for r in (roles or ""):gmatch(".") do if ROLES[r] then out[#out + 1] = ROLES[r] end end
  return table.concat(out, "/")
end

---------------------------------------------------------------------------
-- Milestones feed
---------------------------------------------------------------------------
function ns.AddFeed(kind, text, who, id)
  local g = ns.GuildStore()
  if not g or not text then return end
  who = who or ns.me
  id = id or NewID("F")
  if g.feed[id] then return end
  local e = { t = ns.Now(), who = who, kind = kind, text = text:sub(1, 120) }
  g.feed[id] = e
  ns.Send("D", { feed = { [id] = e } })
  ns.Changed()
  if who == ns.me and ns.db and ns.db.settings.milestoneChat and IsInGuild() then
    SendChatMessage("[EPU] " .. who .. " " .. e.text .. "!", "GUILD")
  end
end

function ns.FeedEntries(days)
  local g = ns.GuildStore()
  local list, cutoff = {}, ns.Now() - (days or 30) * DAY
  for id, e in pairs((g and g.feed) or {}) do
    if (e.t or 0) >= cutoff then list[#list + 1] = { id = id, t = e.t, who = e.who, kind = e.kind, text = e.text } end
  end
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return list
end

local function LevelMilestone(level)
  level = tonumber(level)
  if not level then return false end
  local max = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  return level % 10 == 0 or level == max
end

ns.On("PLAYER_LEVEL_UP", function(level)
  if LevelMilestone(level) then ns.AddFeed("level", "reached level " .. level) end
end)

-- Called by ScanProfessions with the old and new skill tables.
local PROF_STEPS = { 75, 150, 225, 300 }
function ns.ProfessionMilestones(old, new)
  if not old then return end            -- first scan after install: no backlog of shout-outs
  for name, skill in pairs(new or {}) do
    local before = tonumber(old[name]) or 0
    for _, step in ipairs(PROF_STEPS) do
      if before < step and (tonumber(skill) or 0) >= step then
        ns.AddFeed("prof", "reached " .. name .. " " .. step)
      end
    end
  end
end

function ns.RidingMilestone(hadRiding, hasRiding)
  if hadRiding == false and hasRiding then ns.AddFeed("mount", "learned to ride (first mount!)") end
end

-- Officer/bank client logging a donation: shout out the generous ones.
function ns.DonationMilestone(id, d)
  if not d or not d.who or not ns.IsTrusted(ns.me) then return end
  local g = G()
  if (d.money or 0) >= 50000 then
    ns.AddFeed("donation", "donated " .. math.floor(d.money / 10000) .. "g to the guild bank", d.who, "don:" .. id)
  elseif d.item and (d.n or 0) >= 20 and g and g.needs.list[d.item] then
    ns.AddFeed("donation", "donated " .. d.n .. " " .. ns.ItemName(d.item, true) .. " to the guild bank", d.who, "don:" .. id)
  end
end

---------------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------------
-- opts: { quiet = true (listed in News, no pop-up), t = original post time }
function ns.PostNews(title, text, id, by, opts)
  local g = ns.GuildStore()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can post announcements.") end
  title = (title or ""):sub(1, 60)
  text = (text or ""):sub(1, 400)
  if title == "" and text == "" then return ns.Print("Write a title or a message first.") end
  id = id or NewID("N")
  local cur = g.news[id]
  opts = opts or {}
  local e = { t = (cur and cur.t) or opts.t or ns.Now(), u = ns.NextVersion(cur and cur.u), by = by or (cur and cur.by) or ns.me,
    title = title, text = text, via = cur and cur.via, quiet = opts.quiet or (cur and cur.quiet) or nil }
  g.news[id] = e
  if ns.cdb then ns.cdb.newsRead = ns.cdb.newsRead or {}; ns.cdb.newsRead[id] = true end
  ns.Send("D", { news = { [id] = e } })
  ns.Log((cur and "Edited" or "Posted") .. " announcement: " .. (title ~= "" and title or text:sub(1, 40)))
  ns.Changed()
  return id
end

function ns.RemoveNews(id)
  local g = ns.GuildStore()
  local e = g and g.news[id]
  if not e or not ns.IsTrusted(ns.me) then return end
  e.removed = true
  e.u = ns.NextVersion(e.u)
  ns.Send("D", { news = { [id] = e } })
  ns.Log("Removed announcement: " .. (e.title or ""))
  ns.Changed()
end

function ns.NewsEntries()
  local g = ns.GuildStore()
  local list = {}
  for id, e in pairs((g and g.news) or {}) do
    if not e.removed then list[#list + 1] = { id = id, t = e.t, by = e.by, title = e.title, text = e.text, quiet = e.quiet } end
  end
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return list
end

-- The in-game guild Message of the Day, as a News entry (each client reads it itself; nothing to sync).
function ns.MotdEntry()
  local g = ns.GuildStore()
  local m = g and g.motd
  if not m or not m.text or m.text == "" then return nil end
  return { id = "motd", title = "Guild message of the day", text = m.text, by = "Guild", t = m.t, motd = true }
end

function ns.GuildInfoText()
  local t = GetGuildInfoText and GetGuildInfoText()
  if type(t) == "string" and t:gsub("%s", "") ~= "" then return t end
  return nil
end

function ns.UpdateMotd(text)
  local g = ns.GuildStore()
  if not g then return end
  if text == nil and GetGuildRosterMOTD then text = GetGuildRosterMOTD() end
  if type(text) ~= "string" then return end
  g.motd = g.motd or {}
  if g.motd.text ~= text then
    g.motd = { text = text, t = ns.Now() }
    ns.Changed()
  end
end
ns.On("GUILD_MOTD", function(text) ns.UpdateMotd(text) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.UpdateMotd() end)
ns.On("GUILD_ROSTER_UPDATE", function() ns.UpdateMotd() end)

function ns.UnreadNews()
  local read = (ns.cdb and ns.cdb.newsRead) or {}
  local out = {}
  local motd = ns.MotdEntry()
  if motd and ns.cdb and ns.cdb.motdRead ~= motd.text then out[#out + 1] = motd end
  for _, e in ipairs(ns.NewsEntries()) do if not read[e.id] and not e.quiet then out[#out + 1] = e end end
  return out
end

function ns.MarkNewsRead(id)
  if not ns.cdb then return end
  if id == "motd" then
    local m = ns.MotdEntry()
    ns.cdb.motdRead = m and m.text or nil
  else
    ns.cdb.newsRead = ns.cdb.newsRead or {}
    ns.cdb.newsRead[id] = true
  end
  ns.Changed()
end

-- At login: one pop-up at most. It shows the newest announcement if you
-- haven't read it, and says how many others are unread. (The game already
-- prints the message of the day in chat, so that never pops up.)
function ns.ShowUnreadNews()
  if not ns.Dialog then return end
  local unread = {}
  for _, e in ipairs(ns.UnreadNews()) do if not e.motd then unread[#unread + 1] = e end end
  if #unread == 0 then return end
  local newest
  for _, e in ipairs(ns.NewsEntries()) do if not e.quiet then newest = e break end end
  if not newest or newest.id ~= unread[1].id then
    ns.Print("You have " .. #unread .. " unread guild announcement" .. (#unread == 1 and "" or "s") .. ". Type |cffffffff/epu news|r to read them.")
    return
  end
  local e = newest
  local more = #unread - 1
  local body = ((e.title and e.title ~= "") and ("|cffffffff" .. e.title .. "|r\n\n") or "") .. (e.text or "")
    .. "\n\n|cff7e8590- " .. tostring(e.by) .. "|r"
    .. (more > 0 and ("\n\n|cfff2c14e" .. more .. " more unread announcement" .. (more == 1 and "" or "s") .. " in News.|r") or "")
  ns.Dialog("Guild announcement", body, {
    { "Got it", function() ns.MarkNewsRead(e.id) end },
    { more > 0 and "Open News (" .. more .. ")" or "Open News", function()
      ns.MarkNewsRead(e.id)
      if ns.UI then ns.UI:Show(); ns.UI:SetView("news") end
    end },
  })
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin == false and isReload == false then return end
  C_Timer.After(20, function() if ns.db and ns.db.settings.newsPopups ~= false then ns.ShowUnreadNews() end end)
end)

---------------------------------------------------------------------------
-- Officer notes, join dates, member review
---------------------------------------------------------------------------
function ns.SetNote(name, text)
  local g = ns.GuildStore()
  if not g or not ns.IsTrusted(ns.me) then return ns.Print("Only officers can write member notes.") end
  local cur = g.notes[name]
  text = (text or ""):sub(1, 200)
  g.notes[name] = { t = ns.NextVersion(cur and cur.t), by = ns.me, text = text }
  ns.Send("O", { notes = { [name] = g.notes[name] } }, "OFFICER")
  ns.Log((text == "" and "Cleared" or "Updated") .. " the officer note for " .. name)
  ns.Changed()
end

-- Roster updates call this with every member's current info.
function ns.TrackRoster(entries)
  local g = ns.GuildStore()
  if not g then return end
  local now = ns.Now()
  local seeding = not g.joinedSeeded
  local newJoins = {}
  for name, r in pairs(entries) do
    -- level history (local)
    local log = g.lvlLog[name]
    if not log then
      g.lvlLog[name] = { now, r.level }
    elseif log[#log] ~= r.level and r.level then
      log[#log + 1] = now; log[#log + 1] = r.level
      while #log > 16 do table.remove(log, 1); table.remove(log, 1) end
    end
    -- join date (officers record and share it)
    if not g.joined[name] and ns.IsTrusted(ns.me) then
      g.joined[name] = { t = now, r = now, seed = seeding or nil }
      newJoins[name] = g.joined[name]
    end
  end
  if ns.IsTrusted(ns.me) then
    if seeding then g.joinedSeeded = now end
    if next(newJoins) then
      ns.Send("D", { joined = newJoins })
      if not seeding then
        for name in pairs(newJoins) do ns.AddFeed("join", "joined the guild. Say hi!", name, "join:" .. name) end
      end
    end
  end
end

-- Levels gained in the last `days` (from this PC's level history)
function ns.LevelsGained(name, days)
  local g = ns.GuildStore()
  local log = g and g.lvlLog[name]
  if not log or #log < 2 then return nil end
  local cutoff = ns.Now() - (days or 14) * DAY
  local start = log[2]
  for i = 1, #log - 1, 2 do
    if log[i] <= cutoff then start = log[i + 1] else break end
  end
  return (log[#log] or start) - start, log[1] <= cutoff
end

-- Days since a member was online (0 if online now; nil if unknown)
function ns.DaysAway(name)
  local r = ns.roster[name]
  if not r then return nil end
  if r.online then return 0 end
  return r.away
end

local function LowestRank()
  local n = GuildControlGetNumRanks and GuildControlGetNumRanks()
  if n and n > 0 then return n - 1 end
  local lo = 0
  for _, r in pairs(ns.roster) do lo = math.max(lo, r.rank or 0) end
  return lo
end

-- Review facts for one member, for officers.
--   { joined, joinedSeed, daysIn, away, inactive, gained, donations, requests, promote, note }
ns.INACTIVE_DAYS = 30
function ns.Review(name)
  local g = ns.GuildStore()
  if not g then return {} end
  local now = ns.Now()
  local main = ns.MainOf(name)
  local chars = { [name] = true, [main] = true }
  for _, a in ipairs(ns.AltsOf(main)) do chars[a] = true end
  local out = {}
  local j = g.joined[name]
  if j then out.joined, out.joinedSeed, out.daysIn = j.t, j.seed, math.floor((now - j.t) / DAY) end
  out.away = ns.DaysAway(name)
  out.inactive = out.away ~= nil and out.away >= ns.INACTIVE_DAYS
  out.gained = ns.LevelsGained(name, 14)
  local cutoff, dons, reqs = now - 30 * DAY, 0, 0
  for _, d in pairs(g.donations) do
    if chars[d.who or ""] and not d.void and (d.t or 0) >= cutoff then dons = dons + 1 end
  end
  for _, r in pairs(g.requests) do
    if chars[r.who or ""] and (r.t or 0) >= cutoff then reqs = reqs + 1 end
  end
  out.donations, out.requests = dons, reqs
  local pol = g.policy
  local days, level = tonumber(pol.promoDays) or 0, tonumber(pol.promoLevel) or 0
  local r = ns.roster[name]
  if r and (days > 0 or level > 0) and r.rank == LowestRank() and r.rank > 0 and not ns.IsTrusted(name) then
    out.promote = (not out.daysIn or out.daysIn >= days) and (out.daysIn ~= nil or days == 0) and (r.level or 0) >= level
  end
  out.note = g.notes[name]
  return out
end

---------------------------------------------------------------------------
-- Sync: merge and delta for everything above (called from Data.lua)
---------------------------------------------------------------------------
function ns.MergeGuild(sender, b, trusted, catchingUp)
  local g = ns.GuildStore()
  if not g then return false end
  local changed = false

  if type(b.profiles) == "table" then
    for who, p in pairs(b.profiles) do
      if type(p) == "table" and type(p.t) == "number" and (trusted or who == sender) then
        local cur = ns.Real(g, "profiles", who, g.profiles[who])
        if not cur or ns.Newer(p, cur, "t") then
          ns.Confirm(g, "profiles", who)
          g.profiles[who] = { t = p.t, roles = type(p.roles) == "string" and p.roles:sub(1, 3) or nil,
            lf = type(p.lf) == "string" and p.lf:sub(1, 60) or nil }
          changed = true
        end
      end
    end
  end

  if type(b.feed) == "table" then
    for id, e in pairs(b.feed) do
      if type(e) == "table" and type(e.t) == "number" and type(e.text) == "string" and not ns.Real(g, "feed", id, g.feed[id])
        and (trusted or e.who == sender) then
        ns.Confirm(g, "feed", id)
        g.feed[id] = { t = e.t, who = e.who, kind = e.kind, text = e.text:sub(1, 120) }
        changed = true
        if not catchingUp and e.who ~= ns.me and ns.Notify and ns.db and ns.db.settings.milestones ~= false
          and ns.Now() - e.t < 600 then
          pcall(ns.Notify, "Guild milestone", ns.WhoLabel(e.who) .. " " .. e.text .. "!", "Interface\\Icons\\Achievement_Level_10")
        end
      end
    end
  end

  if trusted and type(b.news) == "table" then
    for id, e in pairs(b.news) do
      local cur = ns.Real(g, "news", id, g.news[id])
      if type(e) == "table" and type(e.u) == "number" and (not cur or ns.Newer(e, cur, "u")) then
        ns.Confirm(g, "news", id)
        g.news[id] = { t = e.t, u = e.u, by = e.by, title = e.title, text = e.text, removed = e.removed, via = e.via,
          quiet = e.quiet and true or nil }
        changed = true
        if not catchingUp and not cur and not e.removed and not e.quiet then C_Timer.After(1, ns.ShowUnreadNews) end
      end
    end
  end

  if trusted and type(b.joined) == "table" then
    for who, j in pairs(b.joined) do
      local cur = ns.Real(g, "joined", who, g.joined[who])
      if type(j) == "table" and type(j.t) == "number" and (not cur or j.t < cur.t) then
        ns.Confirm(g, "joined", who)
        g.joined[who] = { t = j.t, r = math.max(j.r or 0, cur and cur.r or 0), seed = j.seed }
        changed = true
      end
    end
  end
  return changed
end

function ns.DeltaGuild(b, since)
  local g = ns.GuildStore()
  if not g then return end
  local U = ns.Unconf
  for who, p in pairs(g.profiles) do if (p.t or 0) > since and not U(g, "profiles", who) then b.profiles = b.profiles or {}; b.profiles[who] = p end end
  for id, e in pairs(g.feed) do if (e.t or 0) > since and not U(g, "feed", id) then b.feed = b.feed or {}; b.feed[id] = e end end
  for id, e in pairs(g.news) do if (e.u or 0) > since and not U(g, "news", id) then b.news = b.news or {}; b.news[id] = e end end
  for who, j in pairs(g.joined) do if (j.r or j.t or 0) > since and not U(g, "joined", who) then b.joined = b.joined or {}; b.joined[who] = j end end
end

---------------------------------------------------------------------------
-- Officer-only data (notes, log) travels on the OFFICER addon channel, which
-- only ranks that can read officer chat receive. It never goes out guild-wide.
---------------------------------------------------------------------------
local function MergeOfficer(b)
  local g = ns.GuildStore()
  if not g then return false end
  local trusted, changed = true, false
  if trusted and type(b.log) == "table" then
    for id, e in pairs(b.log) do
      if type(e) == "table" and type(e.t) == "number" and not g.log[id] then
        g.log[id] = { t = e.t, by = e.by, text = e.text }
        changed = true
      end
    end
  end

  if trusted and type(b.notes) == "table" then
    for who, n in pairs(b.notes) do
      local cur = g.notes[who]
      if type(n) == "table" and type(n.t) == "number" and (not cur or ns.Newer(n, cur, "t")) then
        g.notes[who] = { t = n.t, by = n.by, text = n.text }
        changed = true
      end
    end
  end

  return changed
end

ns.comm.O = function(sender, b, channel)
  if channel ~= "OFFICER" or type(b) ~= "table" then return end
  if not ns.IsTrusted(sender) or not ns.IsTrusted(ns.me) then return end
  if MergeOfficer(b) then ns.Changed() end
end

-- Answering an officer's login sync: their notes and log catch-up.
function ns.SendOfficerDelta(since)
  local g = ns.GuildStore()
  if not g then return end
  local b, any = {}, false
  for id, e in pairs(g.log) do if (e.t or 0) > since then b.log = b.log or {}; b.log[id] = e; any = true end end
  for who, n in pairs(g.notes) do if (n.t or 0) > since then b.notes = b.notes or {}; b.notes[who] = n; any = true end end
  if any then ns.Send("O", b, "OFFICER") end
end

function ns.PruneGuild(g)
  Store(g)
  local now = ns.Now()
  for id, e in pairs(g.feed) do if now - (e.t or 0) > 60 * DAY then g.feed[id] = nil end end
  for id, e in pairs(g.log) do if now - (e.t or 0) > 90 * DAY then g.log[id] = nil end end
  for id, e in pairs(g.news) do if e.removed and now - (e.u or 0) > 30 * DAY then g.news[id] = nil end end
  for who, p in pairs(g.profiles) do if now - (p.t or 0) > 180 * DAY then g.profiles[who] = nil end end
end

-- EPU Guild Tools: keeping everyone's copy of the guild data in step
local ADDON, ns = ...

local DAY = 86400

---------------------------------------------------------------------------
-- How it works
--
-- A client that logs in sends "H" (hello) with the versions it has and the
-- time of its last completed officer sync. One online officer answers with
-- everything newer ("D", tagged sync = requester), split into a few bundles
-- sent most important first: needs and bank, then requests and donations,
-- then news, then crafters, then recipes. Each bundle is kept as it arrives,
-- so a lost message only costs that one bundle. Other officers see the
-- answer go by and stand down.
--
-- No officer online? A guildmate who has officer-confirmed data answers
-- instead (relay = true). Relayed data only fills gaps, is shown as
-- unconfirmed, is never passed on, and the next officer sync replaces it.
--
-- It all runs by itself: at login (retrying until the guild has loaded), when
-- an officer comes online, when an officer's check-in ("C", every 15 minutes)
-- shows we're behind, and every 15 minutes while we're still unconfirmed.
---------------------------------------------------------------------------
ns.sync = ns.sync or { parts = {} }
local S = ns.sync
local U = ns.Unconf

ns.pendingHello = {}     -- officers: hellos waiting to be answered
ns.pendingRelay = {}     -- members: hellos we'll relay to if no officer does
function ns.ExpireSync()
  for key,p in pairs(S.parts) do if GetTime()-(p.at or 0)>1800 then S.parts[key]=nil end end
end

local FIELDS={req="requests",don="donations",craft="crafters",alts="alts",altVerified="altVerified",
  recipes="recipes",mats="mats",projects="projects",onboarding="onboarding",onboardingSteps="onboardingSteps"}
for _,f in ipairs(ns.CASUAL_FIELDS or {}) do FIELDS[f]=f end
local function FieldDigests(g)
  local out={}
  for wire,field in pairs(FIELDS) do
    local confirmed={}
    for k,v in pairs(g[field] or {}) do if not U(g,wire,k) then confirmed[k]=v end end
    -- The optional invite bridge adds no hello traffic when it has no records.
    if (wire~='inviteRequests' and wire~='syncHelpers' and wire~='inviteOutcomes') or next(confirmed) then out[wire]=ns.Fingerprint(confirmed) end
  end
  return out
end

function ns.EmptyDigest()
  return { needs = 0, bank = {}, since = 0, ver = ns.VERSION, at = ns.Now() }
end

function ns.Digest()
  local g = ns.G()
  local d = ns.EmptyDigest()
  if not g then return d end
  -- unconfirmed copies count as missing, so an officer sends the real thing
  d.needs = U(g, "needs", "list") and 0 or g.needs.v
  d.needsSig = ns.NeedsSignature()
  d.fields = FieldDigests(g)
  d.policySig=ns.Fingerprint(g.policy)
  d.bankSig={}
  for alt,s in pairs(g.bank) do d.bankSig[alt]=ns.Fingerprint(s) end
  d.policy = g.policy.v
  for alt, s in pairs(g.bank) do if not U(g, "bank", alt) then d.bank[alt] = s.v end end
  d.since = g.syncedAt or 0
  return d
end

-- Everything newer than the digest. Unconfirmed (relayed) records are never
-- included, so nobody can launder made-up data through a third client.
function ns.Delta(d)
  local g = ns.G()
  if not g then return nil end
  local b = {}
  local since = tonumber(d.since) or 0
  if (g.needs.v > (tonumber(d.needs) or 0) or d.needsSig ~= ns.NeedsSignature()) and not U(g, "needs", "list") then b.needs = g.needs end
  if (g.policy.v or 0) > (tonumber(d.policy) or 0) or (d.policySig and d.policySig~=ns.Fingerprint(g.policy)) then b.policy = g.policy end
  for alt, s in pairs(g.bank) do
    if (s.v > ((type(d.bank) == "table" and tonumber(d.bank[alt])) or 0) or (type(d.bankSig)=="table" and d.bankSig[alt]~=ns.Fingerprint(s))) and not U(g, "bank", alt) then
      b.bank = b.bank or {}
      b.bank[alt] = s
    end
  end
  local function add(field, src, stamp)
    local mismatch=type(d.fields)=="table" and d.fields[field]~=ns.Fingerprint(src)
    for k, x in pairs(src) do
      if (mismatch or stamp(x) > since) and not U(g, field, k) then
        b[field] = b[field] or {}
        b[field][k] = x
      end
    end
  end
  add("req", g.requests, function(r) return r.u or 0 end)
  add("don", g.donations, function(x) return math.max(x.t or 0, tonumber(x.u) or 0) end)
  add("craft", g.crafters, function(c) return c.t or 0 end)
  add("alts", g.alts, function(a) return a.t or 0 end)
  add("altVerified", g.altVerified, function(a) return a.t or 0 end)
  if ns.DeltaPlanning then
    for _,f in ipairs({"projects","onboarding","onboardingSteps"}) do
      add(f,g[f] or {},function(r) return r.t or 0 end)
    end
  end
  for _,f in ipairs(ns.CASUAL_FIELDS or {}) do add(f,g[f] or {},function(r) return r.t or 0 end) end
  add("recipes", g.recipes, function(r) return r.t or 0 end)
  add("mats", g.mats, function(m) return m.t or 0 end)
  if ns.DeltaGuild then ns.DeltaGuild(b, since) end
  return b
end

---------------------------------------------------------------------------
-- Splitting an answer into bundles, most important first
---------------------------------------------------------------------------
local GROUPS = {
  { "needs", "policy", "bank" },
  { "req", "don" },
  { "news", "feed" },
  { "craft", "alts", "altVerified", "profiles", "joined", "projects", "onboarding", "onboardingSteps" },
  { "activityPosts", "activityReplies", "helpers", "kitTemplates", "guildEvents", "eventResponses", "syncHelpers" },
}
local CHUNKED = { recipes = 3, mats = 40 }   -- big tables go out a few entries at a time

function ns.SplitDelta(b)
  local parts = {}
  for _, group in ipairs(GROUPS) do
    local p, any = {}, false
    for _, f in ipairs(group) do if b[f] ~= nil then p[f] = b[f]; any = true end end
    if any then parts[#parts + 1] = p end
  end
  for _, f in ipairs({ "recipes", "mats" }) do
    if type(b[f]) == "table" then
      local keys = {}
      for k in pairs(b[f]) do keys[#keys + 1] = k end
      table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
      for i = 1, #keys, CHUNKED[f] do
        local p = { [f] = {} }
        for j = i, math.min(#keys, i + CHUNKED[f] - 1) do p[f][keys[j]] = b[f][keys[j]] end
        parts[#parts + 1] = p
      end
    end
  end
  if #parts == 0 then parts[1] = {} end   -- still answer, so the requester knows it's up to date
  -- Keep whole bundles below the transport cap, including large request histories.
  local bounded={}
  for _,part in ipairs(parts) do
    if #ns.Serialize(part)<=60000 then bounded[#bounded+1]=part
    else
      for field,records in pairs(part) do
        if field=="policy" then
          if #ns.Serialize(records)>240000 then ns.Print("Guild settings are too large to sync."); return end
          bounded[#bounded+1]={[field]=records}
        else
          local src=field=="needs" and records.entries or records
          if field=="needs" and not records.entries then
            src={}; for id,value in pairs(records.list) do src[id]={v=records.v,by="",value=value} end
          end
          local batch={}
          local function bundle(map)
            if field=="needs" then
              local list={}; for id,e in pairs(map) do list[id]=e.value end
              return {needs={v=records.v,list=list,entries=map}}
            end
            return {[field]=map}
          end
          for id,r in pairs(src) do
            batch[id]=r
            if #ns.Serialize(bundle(batch))>60000 then
              batch[id]=nil
              if next(batch) then bounded[#bounded+1]=bundle(batch) end
              batch={[id]=r}
              if #ns.Serialize(bundle(batch))>240000 then ns.Print("A guild record is too large to sync; please report it to an officer."); return end
            end
          end
          if next(batch) then bounded[#bounded+1]=bundle(batch) end
        end
      end
    end
  end
  return bounded
end

local function SendAnswer(to, d, relay)
  local b = ns.Delta(d)
  if not b then return end
  if relay then b.policy = nil end         -- settings only ever come from officers
  local parts = ns.SplitDelta(b)
  if not parts then return end
  ns.LogSync(relay and "relayed" or "sent", to, (relay and "Passed on to " or "Answered ") .. to .. ": " .. ns.SyncWhat(ns.SyncCount(b)))
  for i, p in ipairs(parts) do
    p.sync, p.part, p.parts, p.hs = to, i, #parts, tonumber(d.at) or 0
    p.ver = ns.VERSION
    if relay then p.relay = true end
    ns.Send("D", p)
  end
  return #parts
end

---------------------------------------------------------------------------
-- Relayed (unconfirmed) data: fills gaps only
---------------------------------------------------------------------------
local function Owner(f, k, x)
  if f=="guildEvents" or f=="eventResponses" then return x.who end
  if f=="activityPosts" or f=="activityReplies" or f=="helpers" then return x.who end
  if f=="kitTemplates" then return x.by end
  if f == "req" then return x.who end
  if f == "craft" or f == "recipes" or f == "profiles" or f == "joined" then return k end
  if f == "mats" then return x.by end
  if f == "feed" then return x.who end
end

local function Stamp(f, x)
  if f == "bank" then return tonumber(x.v) end
  if f == "req" or f == "news" then return tonumber(x.u) end
  if f == "don" then return tonumber(x.t) end
  return tonumber(x.t)
end

local VALID = {
  bank = function(x) return type(x.items) == "table" end,
  req = function(x) return (x.item or x.spell) ~= nil and type(x.who) == "string" and type(x.status) == "string" end,
  don = function(x) return type(x.who) == "string" end,
  craft = function(x) return type(x.profs) == "table" end,
  recipes = function(x) return type(x.profs) == "table" end,
  mats = function(x) return type(x.r) == "table" end,
  alts = function(x) return type(x.chars) == "table" and type(x.main) == "string" end,
  profiles = function() return true end,
  feed = function(x) return type(x.text) == "string" end,
  news = function(x) return type(x.title) == "string" or type(x.text) == "string" end,
  joined = function() return true end,
}

local function Tables(g)
  return { guildEvents=g.guildEvents or {}, eventResponses=g.eventResponses or {}, activityPosts=g.activityPosts or {}, activityReplies=g.activityReplies or {}, helpers=g.helpers or {}, kitTemplates=g.kitTemplates or {}, projects=g.projects or {}, onboarding=g.onboarding or {}, onboardingSteps=g.onboardingSteps or {}, altVerified=g.altVerified or {}, bank = g.bank, req = g.requests, don = g.donations, craft = g.crafters, recipes = g.recipes,
    mats = g.mats, alts = g.alts, profiles = g.profiles, feed = g.feed, news = g.news, joined = g.joined }
end

function ns.MergeRelay(sender, b)
  local g = ns.GuildStore and ns.GuildStore() or ns.G()
  if not g or type(b) ~= "table" then return false end
  local changed, altsChanged = false, false

  local nd = b.needs
  if type(nd) == "table" and type(nd.v) == "number" and type(nd.list) == "table" then
    local unconf = U(g, "needs", "list")
    if (g.needs.v == 0 and not next(g.needs.list)) or (unconf and nd.v > g.needs.v) then
      g.needs = { v = nd.v, list = nd.list }
      ns.MarkUnconf(g, "needs", "list")
      changed = true
    end
  end

  local T = Tables(g)
  for f, dst in pairs(T) do
    local src = b[f]
    if type(src) == "table" then
      for k, x in pairs(src) do
        local stamp = type(x) == "table" and Stamp(f, x)
        local ok = stamp and VALID[f] and VALID[f](x) and Owner(f, k, x) ~= ns.me
        if ok and f == "alts" then
          for _, n in pairs(x.chars) do if n == ns.me then ok = false end end
        end
        local cur = dst[k]
        if ok and (cur == nil or (U(g, f, k) and stamp > (Stamp(f, cur) or 0))) then
          if f == "news" then
            -- shown in News, but never as a pop-up
            x = { t = x.t, u = x.u, by = x.by, title = x.title, text = x.text, removed = x.removed, via = x.via, quiet = true }
          end
          dst[k] = x
          ns.MarkUnconf(g, f, k)
          changed = true
          if f == "alts" then altsChanged = true end
          if f == "recipes" then ns.recipeIndex = nil end
        end
      end
    end
  end
  if altsChanged then ns.RebuildAlts() end
  if changed then
    S.relayFrom, S.relayAt = sender, ns.Now()
    ns.Changed()
  end
  return changed
end

-- After a complete officer sync, whatever is still unconfirmed wasn't real.
function ns.PurgeUnconfirmed()
  local g = ns.GuildStore and ns.GuildStore() or ns.G()
  if not g or not g.unconf then return 0 end
  local n = 0
  local T = Tables(g)
  for f, keys in pairs(g.unconf) do
    for k in pairs(keys) do
      if f == "needs" then
        g.needs = { v = 0, list = {} }
      elseif T[f] then
        T[f][k] = nil
      end
      n = n + 1
    end
  end
  g.unconf = nil
  ns.recipeIndex = nil
  if n > 0 then
    ns.RebuildAlts()
    ns.Changed()
  end
  return n
end

---------------------------------------------------------------------------
-- Sync history. Each PC keeps its own log (not shared), and everyone's addon
-- reports a one-line summary after it syncs ("Y"), which the Sync tab lists.
---------------------------------------------------------------------------
local LABELS = {
  { "guildEvents", "events" }, { "eventResponses", "event signups" },
  { "activityPosts", "activities" }, { "activityReplies", "responses" }, { "helpers", "helpers" }, { "kitTemplates", "kit templates" },
  { "projects", "projects" }, { "onboarding", "checklist updates" }, { "onboardingSteps", "checklist instructions" },
  { "altVerified", "character confirmations" },
  { "needs", "needs" }, { "bank", "bank snapshots" }, { "req", "requests" }, { "don", "donations" },
  { "news", "announcements" }, { "feed", "milestones" }, { "craft", "crafters" }, { "recipes", "recipe lists" },
  { "profiles", "profiles" }, { "alts", "alt groups" }, { "joined", "join dates" }, { "policy", "settings" },
}

local function Count(b, into)
  into = into or {}
  for _, l in ipairs(LABELS) do
    local f, x = l[1], b[l[1]]
    if type(x) == "table" then
      local n = 0
      if f == "needs" then for _ in pairs(x.list or {}) do n = n + 1 end
      elseif f == "policy" then n = 1
      else for _ in pairs(x) do n = n + 1 end end
      if n > 0 then into[f] = (into[f] or 0) + n end
    end
  end
  return into
end

ns.SyncCount = Count

function ns.SyncWhat(counts)
  local parts = {}
  for _, l in ipairs(LABELS) do
    local n = counts and counts[l[1]]
    if n and n > 0 then
      local word = (n == 1 and l[1] ~= "policy") and l[2]:gsub("s$", "") or l[2]
      parts[#parts + 1] = n .. " " .. word
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or "already up to date"
end

local function Store()
  local g = ns.G()
  if not g then return nil end
  g.syncLog = g.syncLog or {}     -- this PC only: { t, kind, who, text }, newest first
  g.syncSeen = g.syncSeen or {}   -- [name] = { t, from, kind, what, ver, asked }
  return g
end

function ns.LogSync(kind, who, text)
  local g = Store()
  if not g then return end
  table.insert(g.syncLog, 1, { t = ns.Now(), kind = kind, who = who, text = text })
  for i = #g.syncLog, 61, -1 do g.syncLog[i] = nil end
  ns.Changed()
end

function ns.SeenSync(name, fields)
  local g = Store()
  if not g or type(name) ~= "string" then return end
  local e = g.syncSeen[name] or {}
  for k, v in pairs(fields) do e[k] = v end
  g.syncSeen[name] = e
end

-- everyone's latest report, plus our own state
function ns.SyncReports()
  local g = Store()
  local list = {}
  if not g then return list end
  local now = ns.Now()
  for name, e in pairs(g.syncSeen) do
    if now - math.max(e.t or 0, e.asked or 0) > 60 * DAY then g.syncSeen[name] = nil
    elseif name ~= ns.me then list[#list + 1] = { name = name, t = e.t, from = e.from, kind = e.kind, what = e.what, ver = e.ver, asked = e.asked } end
  end
  local me = { name = ns.me, ver = ns.VERSION, asked = S.helloAt and ns.Now() - math.floor(GetTime() - S.helloAt) or nil }
  if S.officerAt then me.t, me.from, me.kind, me.what = S.officerAt, S.officer, "officer", S.lastWhat
  elseif S.relayAt then me.t, me.from, me.kind, me.what = S.relayAt, S.relayFrom, "relay", S.lastWhat end
  if ns.IsTrusted(ns.me) and not me.t then me.from = "Officer: holds the guild's copy"; me.asked = nil end
  list[#list + 1] = me
  return list
end

local function Report(kind, from, counts)
  local what = ns.SyncWhat(counts)
  S.lastWhat = what
  ns.SeenSync(ns.me, { t = ns.Now(), from = from, kind = kind, what = what, ver = ns.VERSION })
  ns.LogSync(kind, from, (kind == "relay" and "Unconfirmed data from " or "Synced from ") .. tostring(from) .. ": " .. what)
  ns.Send("Y", { kind = kind, from = from, what = what, ver = ns.VERSION, at = ns.Now() })
end

ns.comm.Y = function(sender, y)
  if type(y) ~= "table" then return end
  ns.SeenSync(sender, { t = ns.Now(), from = type(y.from) == "string" and y.from or nil,
    kind = y.kind == "relay" and "relay" or "officer", what = type(y.what) == "string" and y.what:sub(1, 160) or nil,
    ver = type(y.ver) == "string" and y.ver or nil })
  if y.ver then ns.NoteVersion(sender, y.ver) end
  ns.Changed()
end

---------------------------------------------------------------------------
-- Hello and answers
---------------------------------------------------------------------------
function ns.NoteVersion(sender, ver)
  if type(ver) ~= "string" or ns.VersionNumber(ver) <= ns.VersionNumber(ns.VERSION) then return end
  if ns.newestVersion and ns.VersionNumber(ns.newestVersion) >= ns.VersionNumber(ver) then return end
  ns.newestVersion = ver
  ns.Print("|cfff2c14eUpdate available:|r version " .. ver .. " (you have " .. ns.VERSION .. "). Update it in the CurseForge app (or WowUp / the EPU updater), then /reload.")
  if ns.Dialog then
    ns.Dialog("EPU Guild Tools " .. ver .. " is out", "You have " .. ns.VERSION .. ".\n\nUpdate it in the CurseForge app (or WowUp, or the EPU updater), then type /reload.\n\nNot installed through an app yet? Type /download in the guild Discord.")
  end
  ns.Changed()
end

-- Officer-synced this session, with nothing left unconfirmed?
function ns.IsSynced()
  return S.officerAt ~= nil and not ns.HasUnconfirmed()
end

function ns.SendHello(full)
  if not IsInGuild() or not ns.G() then return end
  local d = full and ns.EmptyDigest() or ns.Digest()
  ns.helloAt = d.at
  S.helloAt = GetTime()
  ns.Send("H", d)
  local hello = S.helloAt
  local function retry()
    if S.helloAt ~= hello or (S.officerHs or 0) >= d.at then return end
    if ns.QueueLength and ns.QueueLength()>0 then C_Timer.After(30,retry); return end
    if S.lastPart and GetTime()-S.lastPart<90 then C_Timer.After(90,retry); return end
    -- A missing bundle must not advance the watermark; ask for a full replay.
    ns.MaybeHello(true, 1)
  end
  C_Timer.After(120, retry)
  ns.LogSync("asked", nil, full and "Asked for a full sync" or "Asked for updates")
end

function ns.FullSync()
  if not IsInGuild() then return ns.Print("You are not in a guild.") end
  ns.SendHello(true)
  ns.Print("Asked online officers for a full sync.")
end

-- Ask again soon, unless we're already in step (or asked very recently).
function ns.MaybeHello(force, delay)
  if not force and ns.IsSynced() then return end
  if S.helloQueued then return end
  if S.helloAt and GetTime() - S.helloAt < 45 then return end
  S.helloQueued = true
  C_Timer.After(delay or (2 + math.random() * 10), function()
    S.helloQueued = nil
    if not force and ns.IsSynced() then return end
    if S.helloAt and GetTime() - S.helloAt < 45 then return end
    ns.SendHello()
  end)
end

ns.comm.H = function(sender, d)
  if type(d) ~= "table" then return end
  ns.NoteVersion(sender, d.ver)
  ns.SeenSync(sender, { asked = ns.Now(), ver = type(d.ver) == "string" and d.ver or nil })
  local g = ns.G()
  -- an officer just logged in: if we're missing anything, now's the time to ask
  if ns.IsTrusted(sender) then ns.MaybeHello(false) end
  if ns.IsTrusted(ns.me) then
    ns.pendingHello[sender] = d
    C_Timer.After(1 + math.random() * 5, function()
      local dd = ns.pendingHello[sender]
      ns.pendingHello[sender] = nil
      if not dd then return end          -- another officer already answered
      SendAnswer(sender, dd)
      if ns.IsTrusted(sender) and ns.SendOfficerDelta then ns.SendOfficerDelta(tonumber(dd.since) or 0) end
    end)
  elseif g and g.syncedAt and not ns.IsTrusted(sender) and (tonumber(d.since) or 0) < g.syncedAt - 60 then
    -- We have officer-confirmed data they lack. Give officers first go.
    ns.pendingRelay[sender] = d
    C_Timer.After(9 + math.random() * 9, function()
      local dd = ns.pendingRelay[sender]
      ns.pendingRelay[sender] = nil
      if dd then SendAnswer(sender, dd, true) end
    end)
  end
end

local function Complete(sender, b)
  local count, index = tonumber(b.parts) or 1, tonumber(b.part) or 1
  if count < 1 or count > 4096 or count ~= math.floor(count) or index < 1 or index > count or index ~= math.floor(index) then return false end
  local now = GetTime()
  local total=0
  for k,p in pairs(S.parts) do if now-(p.at or 0)>1800 then S.parts[k]=nil else total=total+1 end end
  local key = sender .. ":" .. tostring(b.hs)
  if total>=32 and not S.parts[key] then return false end
  local p = S.parts[key]
  if not p then p = { n = count, have = {}, got = 0, counts = {}, at=now }; S.parts[key] = p end
  if p.n ~= count then return false end
  p.at = now
  S.lastPart = now
  local i = index
  if not p.have[i] then p.have[i] = true; p.got = p.got + 1; Count(b, p.counts) end
  if p.got < p.n then return false end
  S.parts[key] = nil
  return true, p.counts
end

-- Data from someone our guild roster doesn't list yet (it loads a little
-- after login): hold it until the roster arrives, otherwise an officer's
-- data would be judged as a member's and mostly thrown away.
local held = {}
local function Unknown(sender)
  return ns.roster[sender] == nil and ns.Short(sender) ~= ns.me
end
function ns.ReplayHeld()
  if #held == 0 then return end
  local list = held
  held = {}
  for _, m in ipairs(list) do
    if Unknown(m[1]) and GetTime() - m[5] < 120 then held[#held + 1] = m
    else ns.comm[m[4]](m[1], m[2], m[3]) end
  end
end
local function Hold(kind, sender, b, channel)
  if not Unknown(sender) or #held > 200 then return false end
  held[#held + 1] = { sender, b, channel, kind, GetTime() }
  ns.Debounce("rosterAsk", 1, ns.RequestRoster)
  return true
end

ns.comm.D = function(sender, b, channel)
  if type(b) ~= "table" then return end
  if Hold("D", sender, b, channel) then return end
  if b.ver then ns.NoteVersion(sender, b.ver) end
  local trusted = ns.IsTrusted(sender)

  if b.sync then
    -- someone answered this hello: relayers always stand down, officers only for another officer
    ns.pendingRelay[b.sync] = nil
    if trusted then ns.pendingHello[b.sync] = nil end
  end

  if b.relay then
    -- relayed data is only for the member who asked, and only until an officer answers
    -- (officers hold the master copy, so they never take relayed data)
    if b.sync ~= ns.me or channel ~= "GUILD" or ns.IsTrusted(ns.me) then return end
    if S.officerAt and S.officerHs and S.officerHs >= (tonumber(b.hs) or 0) then return end
    ns.MergeRelay(sender, b)
    local done, counts = Complete("relay:" .. sender, b)
    if done then Report("relay", sender, counts) end
    return
  end

  ns.Merge(sender, b, b.sync ~= nil)
  local done, counts
  if b.sync == ns.me and channel == "GUILD" and trusted then done, counts = Complete(sender, b) end
  if done then
    local g = ns.G()
    local hs = tonumber(b.hs) or ns.helloAt
    -- small overlap margin so records stamped around the hello aren't missed
    if g and hs and hs > 0 then g.syncedAt = math.max(g.syncedAt or 0, hs - 300) end
    S.officerAt, S.officerHs, S.officer = ns.Now(), hs or 0, sender
    S.relayFrom = nil
    local dropped = ns.PurgeUnconfirmed()
    Report("officer", sender, counts)
    if dropped > 0 then ns.LogSync("dropped", sender, "Dropped " .. dropped .. " unconfirmed record(s) the officer didn't have") end
    ns.Changed()
  end
end

---------------------------------------------------------------------------
-- Officer check-ins: a small summary every 15 minutes, so anyone who missed
-- something notices and asks. One officer sends it; others stand down.
---------------------------------------------------------------------------
function ns.TopStamp(excludeMine)
  local g = ns.GuildStore and ns.GuildStore() or ns.G()
  if not g then return 0 end
  local top, owner = 0, nil
  local T = Tables(g)
  for f, src in pairs(T) do
    if f ~= "bank" then
      for k, x in pairs(src) do
        if type(x) == "table" and not U(g, f, k) and not (excludeMine and Owner(f, k, x) == ns.me) then
          local s = (f == "don") and math.max(x.t or 0, tonumber(x.u) or 0) or Stamp(f, x) or 0
          if s > top then top, owner = s, Owner(f, k, x) end
        end
      end
    end
  end
  return top, owner
end

function ns.CheckInDigest()
  local g = ns.G()
  if not g then return nil end
  local top, owner = ns.TopStamp()
  local d = { needsSig=ns.NeedsSignature(), needs = g.needs.v, policy = g.policy.v or 0, bank = {}, top = top, topBy = owner }
  d.fields=FieldDigests(g)
  d.policySig=ns.Fingerprint(g.policy)
  d.bankSig={}
  for alt,s in pairs(g.bank) do d.bankSig[alt]=ns.Fingerprint(s) end
  for alt, s in pairs(g.bank) do d.bank[alt] = s.v end
  return d
end

-- Does an officer's check-in show something we don't have?
function ns.Behind(c)
  local g = ns.G()
  if not g or type(c) ~= "table" then return false end
  if type(c.fields)=="table" then
    local mine=FieldDigests(g)
    for f,signature in pairs(c.fields) do if mine[f] and mine[f]~=signature then return true end end
  end
  if c.policySig and c.policySig~=ns.Fingerprint(g.policy) then return true end
  if c.needsSig and c.needsSig ~= ns.NeedsSignature() then return true end
  if U(g, "needs", "list") or (tonumber(c.needs) or 0) > g.needs.v then return true end
  if (tonumber(c.policy) or 0) > (g.policy.v or 0) then return true end
  if type(c.bank) == "table" then
    for alt, v in pairs(c.bank) do
      local s = g.bank[alt]
      if s and type(c.bankSig)=="table" and c.bankSig[alt]~=ns.Fingerprint(s) then return true end
      if not s or U(g, "bank", alt) or (tonumber(v) or 0) > s.v then return true end
    end
  end
  -- if the officer's newest record is one of ours, compare with ours included
  local mine = c.topBy == ns.me
  return (tonumber(c.top) or 0) > (ns.TopStamp(not mine))
end

ns.comm.C = function(sender, c)
  if type(c) ~= "table" then return end
  if Hold("C", sender, c) then return end
  if not ns.IsTrusted(sender) then return end
  S.lastCheckIn = GetTime()
  if ns.Behind(c) then
    ns.LogSync("behind", sender, sender .. "'s check-in showed newer data; asking for it")
    ns.MaybeHello(true, 3 + math.random() * 27)    -- spread out so a guild full of members doesn't ask at once
  end
end

local CHECKIN = 15 * 60
local function CheckInLoop()
  C_Timer.After(CHECKIN + math.random() * 120, function()
    if IsInGuild() and ns.G() then
      if ns.IsTrusted(ns.me) then
        if not S.lastCheckIn or GetTime() - S.lastCheckIn > 10 * 60 then
          S.lastCheckIn = GetTime()
          local d = ns.CheckInDigest()
          if d then ns.Send("C", d); ns.LogSync("checkin", nil, "Sent the 15-minute check-in") end
        end
      end
      -- still unconfirmed? ask again (and refresh the roster to spot officers)
      if not ns.IsSynced() then
        ns.RequestRoster()
        ns.MaybeHello(false, 1)
      end
    end
    CheckInLoop()
  end)
end

---------------------------------------------------------------------------
-- An officer coming online (seen in the guild roster)
---------------------------------------------------------------------------
local wasOnline = {}
function ns.WatchOfficers(roster)
  local first = next(wasOnline) == nil
  local cameOnline = false
  for name, r in pairs(roster) do
    if name ~= ns.me then
      local on = r.online and true or false
      if not first and on and wasOnline[name] == false and ns.IsTrusted(name) then cameOnline = true end
      wasOnline[name] = on
    end
  end
  if cameOnline then ns.MaybeHello(false, 15 + math.random() * 15) end   -- give their addon time to load
end

---------------------------------------------------------------------------
-- Status, for the sidebar and /epu sync
---------------------------------------------------------------------------
local function Ago(t)
  local s = math.max(0, ns.Now() - (t or 0))
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 2 * DAY then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / DAY) .. "d ago"
end
ns.Ago = Ago

-- short label, colour key, and a longer explanation
function ns.SyncStatus()
  local g = ns.G()
  if not g then return "Not in a guild", "muted", "" end
  local network=ns.NetworkStatus and ns.NetworkStatus()
  if network and network.queued>0 and network.pause>0 then
    return "Sync cooling down", "gold", "WoW reported message throttling. EPU will retry in "..network.pause.." seconds."
  end
  if ns.QueueLength and ns.QueueLength() > 0 and S.helloAt and GetTime() - S.helloAt < 120 then
    return "Syncing...", "gold", "Guild data is coming in."
  end
  if ns.HasUnconfirmed() then
    return "Unconfirmed data", "gold", "Some of what you see was passed on by " .. tostring(S.relayFrom or "a guildmate")
      .. " because no officer was online. It will be checked automatically when an officer logs in."
  end
  if S.officerAt then
    return "Synced " .. Ago(S.officerAt), "green", "Up to date with " .. tostring(S.officer or "an officer") .. ". Checks again automatically."
  end
  if ns.IsTrusted(ns.me) then
    return "Officer copy", "green", "You hold the guild's copy, so members sync from you. No other officer has synced with you since you logged in"
      .. (g.syncedAt and (" (last time: " .. Ago(g.syncedAt) .. ").") or ".")
  end
  if g.syncedAt then
    return "Waiting for an officer", "muted", "Last synced " .. Ago(g.syncedAt) .. ". Updates arrive automatically when an officer is online."
  end
  return "Waiting for guild data", "gold", "It arrives automatically when an officer (or a guildmate with the addon) is online."
end

---------------------------------------------------------------------------
-- Re-announce our own records so officers who were offline catch up.
---------------------------------------------------------------------------
function ns.BroadcastMine()
  local g = ns.G()
  if not g then return end
  local b, any = {}, false
  ns.VerifyCharacter(ns.db.accountId)
  if g.altVerified[ns.me] then b.altVerified = {[ns.me]=g.altVerified[ns.me]}; any=true end
  if g.crafters[ns.me] then b.craft = { [ns.me] = g.crafters[ns.me] }; any = true end
  local id = ns.db and ns.db.accountId
  if id and g.alts[id] then b.alts = { [id] = g.alts[id] }; any = true end
  if g.recipes[ns.me] then b.recipes = { [ns.me] = g.recipes[ns.me] }; any = true end
  if g.profiles and g.profiles[ns.me] then b.profiles = { [ns.me] = g.profiles[ns.me] }; any = true end
  for rid, r in pairs(g.requests) do
    if r.who == ns.me and ns.IsActiveRequest(r) then
      b.req = b.req or {}
      b.req[rid] = r
      any = true
    end
  end
  if any then ns.Send("D", b) end
end

---------------------------------------------------------------------------
-- Login: wait for the guild to load (it can take a while), then say hello.
-- If nobody answers, ask once more a minute later.
---------------------------------------------------------------------------
local started, loopStarted = false, false
local function Ready()
  return IsInGuild() and GetGuildInfo("player") ~= nil and ns.G() ~= nil and next(ns.roster) ~= nil
end

function ns.StartSync()
  local tries = 0
  local function try()
    tries = tries + 1
    if not Ready() then
      if tries < 36 then ns.RequestRoster(); C_Timer.After(5, try) end   -- up to 3 minutes
      return
    end
    ns.ScanProfessions()
    ns.PublishAlts()
    ns.SendHello()
    C_Timer.After(4, ns.BroadcastMine)
    C_Timer.After(60, function() if not S.officerAt and not ns.HasUnconfirmed() then ns.MaybeHello(false, 1) end end)
  end
  C_Timer.After(8, try)
  if not loopStarted then loopStarted = true; CheckInLoop() end
end

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  if isLogin == false and isReload == false then return end
  if started then return end
  started = true
  ns.RequestRoster()
  ns.StartSync()
end)

-- EPU Guild Tools: Officer-only Full-Guild Dungeon Run Tracker,
-- Attendance Stats, and Guild Health Overview.
local _, ns = ...

local function Store()
  local g = ns.G and ns.G()
  if not g then return end
  g.dungeonRuns = g.dungeonRuns or {}
  return g.dungeonRuns
end

function ns.GetCurrentPartyGuildStatus()
  local members, nonGuild = {}, {}
  local myName = ns.me or (UnitName and UnitName("player")) or "You"
  members[#members + 1] = myName

  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n > 0 then
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    local limit = prefix == "raid" and n or (n - 1)
    for i = 1, limit do
      local unit = prefix .. i
      if UnitExists and UnitExists(unit) then
        local nm = (ns.UnitFullName and ns.UnitFullName(unit)) or (UnitName and UnitName(unit))
        if nm and nm ~= myName then
          if (ns.InGuild and ns.InGuild(nm)) or (ns.roster and ns.roster[nm]) then
            members[#members + 1] = nm
          else
            nonGuild[#nonGuild + 1] = nm
          end
        end
      end
    end
  end

  local instName, instType
  if GetInstanceInfo then
    local ok, name, itype = pcall(GetInstanceInfo)
    if ok and (itype == "party" or itype == "raid") then
      instName, instType = name, itype
    end
  end

  return {
    members = members,
    nonGuild = nonGuild,
    fullGuild = (#members >= 2 and #nonGuild == 0),
    instance = instName,
    instanceType = instType,
  }
end

function ns.LogGuildDungeonRun(dungeonName, dungeonId, members, fullGuild, note)
  if not ns.IsTrusted or not ns.IsTrusted(ns.me) then
    return ns.Print("Only officers can log guild dungeon runs.")
  end
  local store = Store()
  if not store then return end
  if not dungeonName or dungeonName == "" then
    return ns.Print("Choose a dungeon name first.")
  end
  local now = ns.Now and ns.Now() or time()
  local id = "R" .. (ns.me or "Officer") .. ":" .. now .. ":" .. math.random(1000, 9999)
  local run = {
    id = id,
    dungeon = dungeonName,
    dungeonId = dungeonId,
    members = members or { ns.me },
    fullGuild = fullGuild and true or false,
    note = (note or ""):sub(1, 160),
    t = now,
    by = ns.me,
    voided = false,
  }
  store[id] = run
  if ns.Send then ns.Send("R", run, "OFFICER") end
  if ns.Changed then ns.Changed() end
  ns.Print(string.format("Logged %s run: %s (%d guildmates)", fullGuild and "full guild" or "guild", dungeonName, #run.members))
  return id
end

function ns.VoidGuildDungeonRun(id)
  if not ns.IsTrusted or not ns.IsTrusted(ns.me) then return end
  local store = Store()
  local run = store and store[id]
  if not run then return end
  run.voided = not run.voided
  run.t = ns.NextVersion and ns.NextVersion(run.t) or (time() + 1)
  if ns.Send then ns.Send("R", run, "OFFICER") end
  if ns.Changed then ns.Changed() end
end

ns.comm.R = function(sender, run, channel)
  -- Officer chat only: the server decides who can read and write it, unlike
  -- a rank name, so a bank-rank character can't add or rewrite runs.
  if channel ~= "OFFICER" then return end
  if not ns.IsTrusted or not ns.IsTrusted(ns.me) then return end
  if not ns.IsTrusted(sender) then return end
  if type(run) ~= "table" or type(run.id) ~= "string" or #run.id > 80
    or type(run.dungeon) ~= "string" or run.dungeon == "" or #run.dungeon > 60 then return end
  local now = ns.Now and ns.Now() or time()
  local t = tonumber(run.t)
  if not t or t > now + 300 then return end
  local members = {}
  if type(run.members) == "table" then
    for i, who in ipairs(run.members) do
      if i > 40 then break end
      if type(who) == "string" and who ~= "" and #who <= 48 then members[#members + 1] = who end
    end
  end
  local store = Store()
  if not store then return end
  local cur = store[run.id]
  if cur and (cur.t or 0) >= t then return end
  store[run.id] = {
    id = run.id,
    dungeon = run.dungeon,
    dungeonId = (type(run.dungeonId) == "number" or type(run.dungeonId) == "string") and run.dungeonId or nil,
    members = members,
    fullGuild = run.fullGuild and true or false,
    note = type(run.note) == "string" and run.note:sub(1, 160) or "",
    t = t,
    by = (cur and cur.by) or (type(run.by) == "string" and #run.by <= 48 and run.by) or sender,
    voided = run.voided and true or false,
  }
  if ns.Changed then ns.Changed() end
end

function ns.GetGuildDungeonStats()
  local store = Store() or {}
  local now = ns.Now and ns.Now() or time()
  local cutoff30 = now - 30 * 86400
  local cutoff7 = now - 7 * 86400

  local runs = {}
  local byDungeon = {}
  local byMember = {}

  for _, run in pairs(store) do
    if type(run) == "table" and not run.voided then
      runs[#runs + 1] = run
      local dKey = run.dungeonId or run.dungeon
      local d = byDungeon[dKey] or { name = run.dungeon, total = 0, full = 0, lastT = 0 }
      d.total = d.total + 1
      if run.fullGuild then d.full = d.full + 1 end
      if (run.t or 0) > d.lastT then d.lastT = run.t or 0 end
      byDungeon[dKey] = d

      for _, who in ipairs(run.members or {}) do
        local m = byMember[who] or { name = who, total = 0, full = 0, recent30 = 0, lastT = 0, dungeons = {} }
        m.total = m.total + 1
        if run.fullGuild then m.full = m.full + 1 end
        if (run.t or 0) >= cutoff30 then m.recent30 = m.recent30 + 1 end
        if (run.t or 0) > m.lastT then m.lastT = run.t or 0 end
        m.dungeons[run.dungeon] = true
        byMember[who] = m
      end
    end
  end
  table.sort(runs, function(a, b) return (a.t or 0) > (b.t or 0) end)

  local attendance = {}
  for _, m in pairs(byMember) do
    local uniq = 0
    for _ in pairs(m.dungeons) do uniq = uniq + 1 end
    m.uniqueDungeons = uniq
    attendance[#attendance + 1] = m
  end
  table.sort(attendance, function(a, b)
    if a.recent30 ~= b.recent30 then return a.recent30 > b.recent30 end
    if a.full ~= b.full then return a.full > b.full end
    return a.name < b.name
  end)

  -- Guild Health & Roster Breakdown
  local totalMembers, onlineCount, epuUsers = 0, 0, 0
  local brackets = { low = 0, mid = 0, high = 0, cap = 0 }
  local roles = { tank = 0, healer = 0, dps = 0 }
  local zeroRunMembers = {}
  local g = ns.G and ns.G()
  local profiles = (g and g.profiles) or {}

  for who, r in pairs(ns.roster or {}) do
    totalMembers = totalMembers + 1
    if r.online then onlineCount = onlineCount + 1 end
    if ns.UsesEPU and ns.UsesEPU(who) then epuUsers = epuUsers + 1 end
    local lv = r.level or 1
    if lv >= 60 then brackets.cap = brackets.cap + 1
    elseif lv >= 40 then brackets.high = brackets.high + 1
    elseif lv >= 20 then brackets.mid = brackets.mid + 1
    else brackets.low = brackets.low + 1 end

    local prof = profiles[who]
    -- Profiles keep roles as letters: "t", "h", "d" (see ns.SetProfile).
    local pr = prof and type(prof.roles) == "string" and prof.roles or ""
    if pr:find("t", 1, true) then roles.tank = roles.tank + 1 end
    if pr:find("h", 1, true) then roles.healer = roles.healer + 1 end
    if pr:find("d", 1, true) then roles.dps = roles.dps + 1 end

    local mStat = byMember[who]
    if (not mStat or mStat.recent30 == 0) and lv >= 13 and (r.online or (type(r.away) == "number" and r.away <= 7)) then
      zeroRunMembers[#zeroRunMembers + 1] = { name = who, level = lv, online = r.online }
    end
  end
  table.sort(zeroRunMembers, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online end
    return a.level > b.level
  end)

  return {
    runs = runs,
    byDungeon = byDungeon,
    attendance = attendance,
    zeroRunMembers = zeroRunMembers,
    guildHealth = {
      totalMembers = totalMembers,
      onlineCount = onlineCount,
      epuUsers = epuUsers,
      brackets = brackets,
      roles = roles,
    },
  }
end

-- Auto-log guild dungeon/raid runs on boss kill (ENCOUNTER_END) for officers.
-- Only one officer in the group logs, so a group with three officers makes
-- one run, not three: the first EPU-using officer in the group by name.
local sessionRunIds, lastInstance = {}, nil
local function IsRunLogger(members)
  local first
  for _, who in ipairs(members) do
    if ns.IsTrusted(who) and (who == ns.me or (ns.UsesEPU and ns.UsesEPU(who, 7))) then
      if not first or who < first then first = who end
    end
  end
  return first == ns.me
end
if ns.On then
  -- A new instance (or leaving one) starts a new run on the next kill.
  ns.On("PLAYER_ENTERING_WORLD", function()
    local name
    if GetInstanceInfo then
      local ok, n, itype = pcall(GetInstanceInfo)
      if ok and (itype == "party" or itype == "raid") then name = n end
    end
    if name ~= lastInstance then sessionRunIds = {} end
    lastInstance = name
  end)
  ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 and success ~= true then return end
    if not (ns.IsTrusted and ns.IsTrusted(ns.me)) then return end
    local party = ns.GetCurrentPartyGuildStatus()
    if not party.instance or #party.members < 2 then return end
    if not IsRunLogger(party.members) then return end

    local store = Store()
    if not store then return end
    local existingId = sessionRunIds[party.instance]
    local existing = existingId and store[existingId]
    local boss = encounterName or ("Boss #" .. tostring(encounterID or "?"))

    if existing and not existing.voided then
      if existing.note == "" then existing.note = "Bosses: " .. boss
      elseif not existing.note:find(boss, 1, true) then existing.note = (existing.note .. ", " .. boss):sub(1, 160) end
      existing.t = ns.Now and ns.Now() or time()
      if ns.Send then ns.Send("R", existing, "OFFICER") end
      if ns.Changed then ns.Changed() end
    else
      local id = ns.LogGuildDungeonRun(party.instance, nil, party.members, party.fullGuild, "Auto-logged (" .. boss .. ")")
      if id then sessionRunIds[party.instance] = id end
    end
  end)
end

local ADDON, ns = ...
local DAY = 86400

function ns.ValidBridgeEventCreate(sender, id, event)
  local suffix = id:sub(#event.who + 2)
  return suffix:match("^D:%d+$") and #suffix <= 22
    and event.by == event.who and event.status == "scheduled" and event.t == event.created
    and ns.Member(event.who) == event.who and ns.IsSyncHelper(sender)
end

function ns.ImportEventCreate(entry)
  local officer = ns.IsTrusted(ns.me)
  if not officer and not ns.IsSyncHelper(ns.me) then return false end
  local guild = ns.GuildKey()
  if not guild or type(entry.guild) ~= "string" or entry.guild == ""
    or (guild ~= entry.guild and guild:sub(1, #entry.guild + 3) ~= entry.guild .. " - ") then return false end
  local now = ns.Now()
  if type(entry.id) ~= "string" or not entry.id:match("^D:%d+$") or #entry.id > 22
    or type(entry.who) ~= "string" or entry.who == "" or ns.Member(entry.who) ~= entry.who
    or not ns.PositiveInt(entry.t, now + 300) or not ns.PositiveInt(entry.starts, entry.t + 28 * DAY)
    or entry.starts < entry.t + 60 or not ns.PositiveInt(entry.minutes, 480) or entry.minutes < 15
    or not ns.PositiveInt(entry.slots, 40) or entry.slots < 2 or not ns.EVENT_TYPES[entry.activity] then return false end
  if entry.starts <= now then return true end
  local g = ns.CasualStore()
  if not g then return false end
  local id = entry.who .. "\031" .. entry.id
  if g.guildEvents[id] then return true end
  local count = 0
  for _, event in pairs(g.guildEvents) do
    if event.who == entry.who and event.status == "scheduled" and event.ends > now then count = count + 1 end
  end
  if count >= 10 then return false end
  local event = {
    who = entry.who, by = entry.who, title = entry.title, note = entry.note, zone = entry.zone,
    starts = entry.starts, ends = entry.starts + entry.minutes * 60, slots = entry.slots,
    status = "scheduled", created = entry.t, t = entry.t, kind = entry.activity, minLevel = 1, maxLevel = 60,
  }
  local update = { guildEvents = { [id] = event } }
  if not ns.MergeCommunity(ns.me, update, officer) then return false end
  ns.Send("D", update)
  return true
end

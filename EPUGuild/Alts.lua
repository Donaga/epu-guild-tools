-- EPU Guild Tools: mains and alts.
--
-- SavedVariables are shared by every character on a WoW account, so the
-- addon knows which characters belong to one player. Each player publishes
-- a group record { main, chars } under a random per-account ID; the guild
-- uses it to label alts ("Pip Quickfoot (Brenna Ashford)") and to count a
-- player's donations together.
local ADDON, ns = ...

ns.altIndex = {}   -- [character] = group record

local function RosterReady()
  return ns.roster ~= nil and next(ns.roster) ~= nil
end

local function InGuild(name)
  return not RosterReady() or ns.roster[name] ~= nil
end

function ns.RegisterMe()
  local key = ns.GuildKey()
  if not key or not ns.me or not ns.db then return end
  ns.db.accountChars = ns.db.accountChars or {}
  local seen = ns.db.accountChars[key] or {}
  ns.db.accountChars[key] = seen
  if not seen[ns.me] then seen[ns.me] = ns.Now() end
end

-- This player's main in the current guild: their choice (/epu main), else
-- the first character that ran the addon in this guild.
function ns.MyMain()
  local key = ns.GuildKey()
  if not key or not ns.db then return ns.me end
  local seen = (ns.db.accountChars and ns.db.accountChars[key]) or {}
  local chosen = ns.db.mains and ns.db.mains[key]
  if chosen and seen[chosen] and InGuild(chosen) then return chosen end
  local best, bestT
  for name, t in pairs(seen) do
    if InGuild(name) and (not bestT or t < bestT or (t == bestT and name < best)) then best, bestT = name, t end
  end
  return best or ns.me
end

-- This account's characters in the current guild, main first.
function ns.MyChars()
  local key = ns.GuildKey()
  local list = {}
  if not key or not ns.db then return { ns.me } end
  for name in pairs((ns.db.accountChars and ns.db.accountChars[key]) or {}) do
    if InGuild(name) then list[#list + 1] = name end
  end
  local main = ns.MyMain()
  table.sort(list, function(a, b)
    if a == main then return true end
    if b == main then return false end
    return a < b
  end)
  if #list == 0 then list[1] = ns.me end
  return list
end

function ns.RebuildAlts()
  wipe(ns.altIndex)
  local g = ns.G()
  if not g then return end
  for _, rec in pairs(g.alts) do
    for _, name in ipairs(rec.chars or {}) do
      local cur = ns.altIndex[name]
      if not cur or (rec.t or 0) > (cur.t or 0) then ns.altIndex[name] = rec end   -- newest claim wins
    end
  end
end

function ns.MainOf(name)
  local rec = name and ns.altIndex[name]
  return (rec and rec.main) or name
end

function ns.AltsOf(name)
  local rec = name and ns.altIndex[name]
  local out = {}
  for _, n in ipairs((rec and rec.chars) or {}) do
    if n ~= rec.main then out[#out + 1] = n end
  end
  return out
end

-- "Pip Quickfoot (Brenna Ashford)" for an alt, just the name for a main.
function ns.WhoLabel(name)
  local main = ns.MainOf(name)
  if main and main ~= name then return name .. " (" .. main .. ")" end
  return name
end

function ns.PublishAlts()
  local g = ns.G()
  if not g or not ns.db or not ns.db.accountId then return end
  ns.RegisterMe()
  local chars, main = ns.MyChars(), ns.MyMain()
  local id = ns.db.accountId
  local cur = g.alts[id]
  if cur and cur.main == main and table.concat(cur.chars or {}, ",") == table.concat(chars, ",") then
    ns.RebuildAlts()
    return
  end
  g.alts[id] = { t = ns.NextVersion(cur and cur.t), main = main, chars = chars }
  ns.RebuildAlts()
  ns.Send("D", { alts = { [id] = g.alts[id] } })
  ns.Changed()
end

function ns.SetMain(name)
  local key = ns.GuildKey()
  if not key then return ns.Print("You are not in a guild.") end
  local want = ns.Short(name)
  for _, c in ipairs(ns.MyChars()) do
    if want and c:lower() == want:lower() then
      ns.db.mains = ns.db.mains or {}
      ns.db.mains[key] = c
      ns.PublishAlts()
      return ns.Print("Your main is now " .. c .. ".")
    end
  end
  ns.Print("That isn't one of your characters in this guild. Yours: " .. table.concat(ns.MyChars(), ", ")
    .. ". (Log in once on a character with the addon to add it.)")
end

ns.On("GUILD_ROSTER_UPDATE", function()
  ns.Debounce("alts", 5, ns.PublishAlts)
end)

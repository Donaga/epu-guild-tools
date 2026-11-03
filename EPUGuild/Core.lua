-- EPU Guild Tools: core helpers, saved variables, slash commands
local ADDON, ns = ...

ns.PREFIX = "EPUGuild"            -- addon message prefix (max 16 chars)
ns.comm = {}                      -- message handlers, keyed by one-letter kind

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "0.0.0"

---------------------------------------------------------------------------
-- Event dispatch
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.handlers = {}

function ns.On(event, fn)
  local list = ns.handlers[event]
  if not list then
    list = {}
    ns.handlers[event] = list
    frame:RegisterEvent(event)
  end
  list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = ns.handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end)

---------------------------------------------------------------------------
-- Small utilities
---------------------------------------------------------------------------
function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7EPU|r " .. tostring(msg))
end

function ns.Now()
  return (GetServerTime and GetServerTime()) or time()
end

-- Version stamps must always increase, even for two edits in the same second.
function ns.NextVersion(prev)
  local now = ns.Now()
  prev = prev or 0
  if now > prev then return now end
  return prev + 1
end

---------------------------------------------------------------------------
-- Character names
--   WoW: Forever: "First Surname". The pair is unique per region and there
--     are no realms. Roster entries and addon-message senders already use it.
--   Other clients: "Name" (realm stripped; a guild lives on one realm).
-- On Forever, UnitName() returns (first, surname), not (name, realm), and
-- names can be "secret" values, so every read goes through these helpers.
---------------------------------------------------------------------------
local function Plain(s)
  return type(s) == "string" and s ~= "" and not (issecretvalue and issecretvalue(s))
end

function ns.RegionalNames()
  return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

-- Normalise a name from any API: "First Surname", "Name-Realm", extra spaces.
function ns.Short(name)
  if not Plain(name) then return nil end
  if Ambiguate then
    local ok, a = pcall(Ambiguate, name, "none")
    if ok and Plain(a) then name = a end
  end
  name = name:gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if name == "" then return nil end
  return name
end

-- Full name of a unit ("player", "NPC" for the trade partner, ...).
function ns.UnitFullName(unit)
  if GetUnitName then
    local ok, n = pcall(GetUnitName, unit, true)
    if ok and Plain(n) then return ns.Short(n) end
  end
  local n, second = UnitName(unit)
  if not Plain(n) then return nil end
  if ns.RegionalNames() and Plain(second) then return ns.Short(n .. " " .. second) end
  return ns.Short(n)
end

-- Match a name to a guild member. Some places may only give a first name,
-- so a first name counts if exactly one member has it. Returns nil if the
-- name is ambiguous or not in the guild.
function ns.Member(name)
  name = ns.Short(name)
  if not name or not ns.roster then return nil end
  if ns.roster[name] then return name end
  local lower, hit = name:lower(), nil
  for full in pairs(ns.roster) do
    if full:lower() == lower then return full end
    local first = full:match("^(%S+)")
    if first and first:lower() == lower then
      if hit then return nil end
      hit = full
    end
  end
  return hit
end

ns.me = ns.UnitFullName("player")
ns.On("PLAYER_LOGIN", function() ns.me = ns.UnitFullName("player") or ns.me end)

local pending = {}
-- Run fn once, `delay` seconds after the first call; extra calls meanwhile are folded in.
function ns.Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    fn()
  end)
end

-- Shallow compare of two {key = number} tables.
function ns.SameCounts(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

function ns.VersionNumber(v)
  local a, b, c = tostring(v or ""):match("(%d+)%.(%d+)%.?(%d*)")
  return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- Accepts an item link, "item:1234", a bare item ID, or a cached item name.
function ns.ItemID(text)
  if type(text) == "number" then return text end
  if type(text) ~= "string" then return nil end
  local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
  if id then return tonumber(id) end
  local name = text:match("^%s*%[?(.-)%]?%s*$")
  if name and name ~= "" then
    local _, link = GetItemInfo(name)
    if link then return tonumber(link:match("item:(%d+)")) end
  end
  return nil
end

function ns.ItemIcon(id)
  if not id then return nil end
  if GetItemInfoInstant then
    local _, _, _, _, icon = GetItemInfoInstant(id)
    if icon then return icon end
  end
  return (select(10, GetItemInfo(id)))
end

-- Coloured item name, or a placeholder while the client fetches item data.
function ns.ItemName(id, plain)
  local name, _, quality = GetItemInfo(id)
  if not name then return "Loading item " .. tostring(id) .. "..." end
  if plain then return name end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  return ((c and c.hex) or "|cffffffff") .. name .. "|r"
end

function ns.ItemLink(id)
  local _, link = GetItemInfo(id)
  return link or ("item #" .. tostring(id))
end

-- Split "<item> <qty> <note>" where <item> is a link, an ID, or [Name].
function ns.ParseItemArgs(msg)
  msg = msg or ""
  local id, rest
  if msg:find("|Hitem:") then
    id = tonumber(msg:match("|Hitem:(%d+)"))
    rest = msg:match("|h|r(.*)$") or ""
  elseif msg:match("^%s*%d+") then
    local first, r = msg:match("^%s*(%d+)%s*(.*)$")
    id, rest = tonumber(first), r
  else
    local name, r = msg:match("^%s*%[(.-)%]%s*(.*)$")
    if name then id, rest = ns.ItemID(name), r end
  end
  rest = rest or ""
  local qty, note = rest:match("^%s*(%d+)%s*(.*)$")
  if not qty then note = rest:match("^%s*(.-)%s*$") end
  return id, tonumber(qty), note or ""
end

ns.On("GET_ITEM_INFO_RECEIVED", function()
  if ns.Changed then ns.Changed() end
end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  EPUGuildDB = EPUGuildDB or {}
  EPUGuildDB.guilds = EPUGuildDB.guilds or {}
  EPUGuildDB.settings = EPUGuildDB.settings or {}
  if EPUGuildDB.settings.minimapAngle == nil then EPUGuildDB.settings.minimapAngle = 200 end
  -- Random per-account ID for publishing this player's main/alt group.
  if not EPUGuildDB.accountId then
    EPUGuildDB.accountId = string.format("%x%05x", time(), math.random(0, 0xFFFFF))
  end
  EPUGuildCharDB = EPUGuildCharDB or {}
  EPUGuildCharDB.recipes = EPUGuildCharDB.recipes or {}
  ns.db = EPUGuildDB
  ns.cdb = EPUGuildCharDB
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "|cffffd100/epu|r - open or close the window",
  "|cffffd100/epu need <item> <qty> [goal]|r - (officers) set a restock minimum, or a one-time goal; qty 0 removes it",
  "|cffffd100/epu request <item> <qty> [note]|r - ask the guild bank for an item",
  "|cffffd100/epu who <item>|r - ask the guild who can craft an item",
  "|cffffd100/epu post|r - post the top open needs to guild chat",
  "|cffffd100/epu shop|r - save the shopping list to Auctionator",
  "|cffffd100/epu bankalt on|off|r - mark this character as a guild bank alt",
  "|cffffd100/epu main <name>|r - choose which of your characters is your main",
  "|cffffd100/epu alts|r - list your characters the addon knows about",
  "|cffffd100/epu officerrank <n>|r - ranks 0..n are trusted (default 1: GM + officers)",
  "|cffffd100/epu sync|r - ask online officers for a full resync",
  "|cffffd100/epu save|r - save now (a /reload) so the Discord companion sees the latest",
  "|cffffd100/epu minimap|r - show or hide the minimap button",
  "|cffffd100/epu scale <0.6-1.5>|r - make the window smaller or bigger",
  "|cffffd100/epu tooltips|r, |cffffd100markers|r, |cffffd100notices|r, |cffffd100donate|r - turn tooltip lines, bag coins, pop-ups or the mailbox panel on/off",
  "|cffffd100/epu welcome|r - show the welcome tips again",
  "|cffffd100/epu resetwindow|r - put the window back in the middle at its normal size",
}

SLASH_EPUGUILD1 = "/epu"
SLASH_EPUGUILD2 = "/epuguild"
SlashCmdList.EPUGUILD = function(msg)
  msg = msg or ""
  local cmd, args = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    ns.UI:Toggle()
  elseif cmd == "help" or cmd == "?" then
    for _, line in ipairs(HELP) do ns.Print(line) end
  elseif cmd == "need" then
    local id, qty, extra = ns.ParseItemArgs(args)
    if not id or not qty then return ns.Print("Usage: /epu need <item link> <qty> [goal]") end
    ns.SetNeed(id, qty, (extra or ""):lower():find("goal") and "goal" or "restock")
  elseif cmd == "request" or cmd == "req" then
    local id, qty, note = ns.ParseItemArgs(args)
    if not id then return ns.Print("Usage: /epu request <item link> <qty> [note]") end
    ns.NewRequest(id, qty or 1, note)
  elseif cmd == "who" then
    ns.AskWhoCrafts(args)
  elseif cmd == "shop" then
    ns.ExportAuctionator()
  elseif cmd == "post" then
    ns.PostNeeds()
  elseif cmd == "main" then
    if args == "" then return ns.Print("Your main is " .. tostring(ns.MyMain()) .. ". Change it with /epu main <name>.") end
    ns.SetMain(args)
  elseif cmd == "alts" then
    ns.Print("Your characters here: " .. table.concat(ns.MyChars(), ", ") .. " (main: " .. tostring(ns.MyMain()) .. ")")
  elseif cmd == "bankalt" then
    ns.SetBankAlt(args:lower() ~= "off")
  elseif cmd == "officerrank" then
    local n = tonumber(args)
    local g = ns.G()
    if not n or not g then return ns.Print("Usage: /epu officerrank <number> (you must be in a guild)") end
    g.officerRank = n
    ns.Print("Ranks 0 to " .. n .. " are now trusted for bank, needs and donation data.")
  elseif cmd == "save" then
    if ns.CacheItemNames then pcall(ns.CacheItemNames) end
    ReloadUI()
  elseif cmd == "sync" then
    ns.FullSync()
  elseif cmd == "tooltips" or cmd == "markers" or cmd == "notices" or cmd == "donate" or cmd == "officernotices" then
    local key = ({ tooltips = "tooltips", markers = "bagMarkers", notices = "notices", donate = "donatePanel", officernotices = "officerNotices" })[cmd]
    local on = ns.db.settings[key] == false
    ns.db.settings[key] = on
    ns.Print(({ tooltips = "Tooltip lines", markers = "Bag coins for needed items", notices = "Pop-up notices",
      donate = "Mailbox donate panel", officernotices = "New-request pop-ups for officers" })[cmd] .. (on and " on." or " off."))
    if ns.RefreshBagMarkers then ns.RefreshBagMarkers() end
  elseif cmd == "welcome" then
    ns.UI:Show()
    ns.ShowWelcome()
  elseif cmd == "scale" then
    local s = tonumber(args)
    if not s or s < 0.6 or s > 1.5 then return ns.Print("Usage: /epu scale 0.9  (between 0.6 and 1.5)") end
    ns.db.settings.scale = s
    ns.UI:SetScale(s)
  elseif cmd == "resetwindow" then
    ns.db.settings.window, ns.db.settings.scale = nil, nil
    ns.UI:SetScale(1)
    ns.UI:SetSize(700, 470)
    ns.UI:ClearAllPoints()
    ns.UI:SetPoint("CENTER")
  elseif cmd == "minimap" then
    ns.db.settings.hideMinimap = not ns.db.settings.hideMinimap
    ns.UpdateMinimapButton()
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end

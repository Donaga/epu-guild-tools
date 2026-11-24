-- EPU Guild Tools: weekly leveling board (/epu levelboard).
--
-- Who in the guild gained the most levels this week (or last week), from the
-- level history each PC keeps when it reads the guild roster (g.lvlLog, see
-- TrackRoster in Guild.lua). Every client reads the same roster, so nothing
-- extra is synced. The Discord companion reads the officer PC's copy and
-- posts last week's board once a week (epu-discord/README.md).
--
-- A week runs Monday 00:00 to Sunday 24:00 on this PC's clock. A level shows
-- up when this PC sees it on the roster, so levels gained while this PC was
-- offline count in the week it next saw that guildmate.
local _, ns = ...

local DAY = 86400

-- Monday 00:00 (this PC's clock) of the week that holds time t.
function ns.WeekStart(t)
  local d = date("*t", t or ns.Now())
  local back = (d.wday + 5) % 7            -- wday: 1 = Sunday, 2 = Monday ... 7 = Saturday
  return time({ year = d.year, month = d.month, day = d.day - back, hour = 0, min = 0, sec = 0 })
end

-- The level a character had at the start of [from, to) and at its end, from
-- a level history { t1, lvl1, t2, lvl2, ... } (oldest first). A character
-- first seen during the window starts at the level it was first seen at.
-- nil when the history has nothing before `to`.
function ns.LevelSpan(log, from, to)
  if type(log) ~= "table" then return nil end
  local startLv, endLv
  for i = 1, #log - 1, 2 do
    local at, lv = tonumber(log[i]), tonumber(log[i + 1])
    if at and lv and at < to then
      endLv = lv
      if at <= from or startLv == nil then startLv = lv end
    end
  end
  return startLv, endLv
end

-- The board for "this" week (so far) or "last" week:
--   { from, to, rows = { { name, from, to, gained, classFile } }, total }
-- Only characters still in the guild who gained at least one level, most
-- levels first.
function ns.LevelingBoard(which)
  local now = ns.Now()
  local from, to = ns.WeekStart(now), now + 1
  if which == "last" then from, to = ns.WeekStart(from - DAY), from end
  local out = { from = from, to = to, rows = {}, total = 0 }
  local g = ns.GuildStore and ns.GuildStore()
  if not g then return out end
  local info = g.memberInfo or {}
  for name, log in pairs(g.lvlLog or {}) do
    if type(name) == "string" and ns.InGuild(name) then
      local a, b = ns.LevelSpan(log, from, to)
      if a and b and b > a then
        local r = ns.roster[name]
        out.rows[#out.rows + 1] = { name = name, from = a, to = b, gained = b - a,
          classFile = (r and r.classFile) or (info[name] and info[name].c) }
        out.total = out.total + (b - a)
      end
    end
  end
  table.sort(out.rows, function(x, y)
    if x.gained ~= y.gained then return x.gained > y.gained end
    if x.to ~= y.to then return x.to > y.to end
    return x.name < y.name
  end)
  return out
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function ClassHex(cf)
  local c = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
  if not c then return "|cffffffff" end
  if c.colorStr then return "|c" .. c.colorStr end
  return string.format("|cff%02x%02x%02x", math.floor((c.r or 1) * 255 + 0.5),
    math.floor((c.g or 1) * 255 + 0.5), math.floor((c.b or 1) * 255 + 0.5))
end

local function DayLabel(t) return (date("%b %d", t):gsub(" 0", " ")) end

local win
local which = "this"

function ns.OpenLevelingBoard(view)
  if view == "this" or view == "last" then which = view end
  if not win then
    win = ns.InterfaceWindow("EPUGuildLevelingBoard", UIParent, "Leveling board", 460, 460)
    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(430); child:SetHeight(400)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local maxV = math.max(0, child:GetHeight() - self:GetHeight())
      self:SetVerticalScroll(math.min(maxV, math.max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    win.child = child
    -- The game never frees a widget, so each refresh reuses the last one's.
    win.pool = ns.NewWidgetPool(child)
    function win:Refresh()
      local pool, C = self.pool, ns.InterfaceColors
      pool:ReleaseAll()
      local y = -4
      local x = 0
      for _, tab in ipairs({ { "this", "This week", 96 }, { "last", "Last week", 96 } }) do
        local b = pool:Button(tab[2], tab[3], 22, which == tab[1] and "accent" or nil, "tab")
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() which = tab[1]; win:Refresh() end)
        x = x + tab[3] + 6
      end
      y = y - 32
      local board = ns.LevelingBoard(which)
      local head = pool:Font(12, C.gold, "heading")
      head:SetPoint("TOPLEFT", 0, y)
      head:SetText(DayLabel(board.from) .. " to " .. DayLabel(board.to - DAY)
        .. (which == "this" and " (so far)" or ""))
      y = y - 20
      local sum = pool:Font(11, C.muted, "line")
      sum:SetPoint("TOPLEFT", 0, y); sum:SetWidth(430)
      if #board.rows == 0 then
        sum:SetText(which == "this" and "Nobody has gained a level yet this week." or "Nobody gained a level last week.")
      else
        sum:SetText(#board.rows .. (#board.rows == 1 and " guildmate" or " guildmates") .. " gained "
          .. board.total .. (board.total == 1 and " level." or " levels."))
      end
      y = y - 24
      for i, r in ipairs(board.rows) do
        local place = pool:Font(12, i <= 3 and C.gold or C.muted, "place")
        place:SetPoint("TOPLEFT", 0, y); place:SetWidth(24); place:SetJustifyH("RIGHT")
        place:SetText(i .. ".")
        local who = pool:Font(12, C.text, "who")
        who:SetPoint("TOPLEFT", 32, y); who:SetWidth(260)
        who:SetText(ClassHex(r.classFile) .. ns.WhoLabel(r.name) .. "|r")
        local lv = pool:Font(12, C.text, "levels")
        lv:SetPoint("TOPLEFT", 296, y); lv:SetWidth(130); lv:SetJustifyH("RIGHT")
        lv:SetText(r.from .. " to " .. r.to .. "  |cff4ade80+" .. r.gained .. "|r")
        y = y - 20
      end
      y = y - 10
      local note = pool:Font(10, C.muted, "note")
      note:SetPoint("TOPLEFT", 0, y); note:SetWidth(430)
      note:SetText("Weeks run Monday to Sunday. A level counts when your game sees it on the guild roster, "
        .. "so levels gained while you were offline count in the week you next logged in. "
        .. "The guild's Discord gets last week's board once a week.")
      y = y - 44
      self.child:SetHeight(math.max(400, -y))
    end
  end
  win:Show()
  win:Refresh()
  return win
end

-- Keep an open board current as the roster updates.
ns.On("GUILD_ROSTER_UPDATE", function()
  if win and win:IsShown() then ns.Debounce("levelBoard", 1, function() if win:IsShown() then win:Refresh() end end) end
end)

-- Minimal WoW API stubs for exercising EPU Guild Tools outside the game
__now = 1800000000
__out = {}
__timers = {}
__frames = {}
__log = {}
__bags = {}
__money = 0
__inbox = {}

local function noop() end
local M = {}
M.__index = function(t, k)
  local v = rawget(M, k)
  if v then return v end
  if k:sub(1,1):match("%u") then return function(self) return nil end end
  return nil
end
function M:SetText(s) self._text = s; local f = self._scripts and self._scripts.OnTextChanged; if f then f(self, false) end end
function M:GetText() return self._text or "" end
function M:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function M:Hide() self._shown = false end
function M:IsShown() return self._shown == true end
function M:IsVisible() return self._shown == true end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:HasFocus() return false end
function M:SetScript(k, fn) self._scripts[k] = fn end
function M:GetScript(k) return self._scripts[k] end
function M:RegisterEvent(e) self._events[e] = true end
function M:Click() if self._scripts.OnClick then self._scripts.OnClick(self) end end
function M:GetCenter() return 0, 0 end
function M:GetEffectiveScale() return 1 end
function M:SetSize(w, h) self._w, self._h = w, h end
function M:SetWidth(w) self._w = w end
function M:SetHeight(h) self._h = h end
function M:GetWidth() return self._w or 400 end
function M:GetHeight() return self._h or 300 end
function M:GetStringWidth() return #(self._text or "") * 6 end
function M:GetStringHeight() return 14 end
function M:GetVerticalScroll() return self._vs or 0 end
function M:SetVerticalScroll(v) self._vs = v end
function M:GetFrameLevel() return 1 end
function M:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function M:GetParent() return self._parent end
function M:SetParent(p) self._parent = p end
function M:CreateFontString() local f = NewMock(); f._parent = self; return f end
function M:CreateTexture() local t = NewMock(); t._parent = self; return t end
function NewMock() local o = setmetatable({ _scripts = {}, _events = {} }, M); return o end

function CreateFrame(kind, name, parent, template)
  local f = NewMock()
  f._parent = parent
  if kind == "Frame" or kind == "Button" or kind == "EditBox" or kind == "ScrollFrame" then f._shown = (name ~= "EPUGuildFrame") end
  table.insert(__frames, f)
  if name then _G[name] = f end
  return f
end
function __fire(event, ...)
  for _, f in ipairs(__frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
C_Timer = { After = function(d, fn) table.insert(__timers, { at = __now + d, fn = fn }) end }
function __advance(sec)
  local target = __now + sec
  while true do
    table.sort(__timers, function(a, b) return a.at < b.at end)
    local t = __timers[1]
    if not t or t.at > target then break end
    table.remove(__timers, 1)
    if t.at > __now then __now = t.at end
    t.fn()
  end
  __now = target
end
C_ChatInfo = {
  SendAddonMessage = function(p, m, c, t)
    assert(#m <= 255, "addon message too long: " .. #m)
    table.insert(__out, { p, m, c, t })
  end,
  RegisterAddonMessagePrefix = noop,
}
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
function GetServerTime() return math.floor(__now) end
function GetTime() return __now end
-- Forever-style names: UnitName returns (first, surname); roster and addon
-- message senders use "First Surname" with no realm.
local function split(full) if not full then return nil end local f, s = full:match("^(%S+)%s+(.+)$"); if f then return f, s end return full end
function UnitName(u) if u == "player" then return split(__name) end if u == "NPC" then return split(__npc) end end
UnitFullName = UnitName
function GetUnitName(u) if u == "player" then return __name end if u == "NPC" then return __npc end end
function RegionalUniqueNamesEnabled() return true end
function UnitLevel() return 20 end
function GetGuildInfo() return "E Pluribus Unum", __rankName, __rankIndex end
function GetRealmName() return "Forever" end
function IsInGuild() return true end
__roster = {}
function GetNumGuildMembers() return #__roster end
function GetGuildRosterInfo(i) local r = __roster[i]; return r[1], r[2], r[3], 20, nil, nil, nil, nil, true end
C_GuildInfo = { GuildRoster = function() __fire("GUILD_ROSTER_UPDATE") end }
function Ambiguate(n) return n end
local ITEMS = { [2589] = "Linen Cloth", [2996] = "Bolt of Linen Cloth", [14047] = "Runecloth", [4306] = "Silk Cloth" }
for i = 30000, 30200 do ITEMS[i] = "Test Item " .. i end
function __link(id) return "|cffffffff|Hitem:" .. id .. "::::::::20:::::|h[" .. ITEMS[id] .. "]|h|r" end
function GetItemInfo(x)
  local id = tonumber(x)
  if not id then for k, v in pairs(ITEMS) do if v == x then id = k end end end
  if not id or not ITEMS[id] then return nil end
  local cls = __cls and __cls[id]   -- { classID, subType } for recipe items in tests
  return ITEMS[id], __link(id), 1, 1, 1, cls and "Recipe" or "Trade Goods", cls and cls[2] or "Cloth", 20, "", "icon" .. id, 1,
    cls and cls[1] or 7, 0, (__bop and __bop[id]) and 1 or 0
end
__ITEMS = ITEMS
function GetItemInfoInstant(id) return id, nil, nil, nil, "icon" .. id end
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
function GetItemCount() return 3 end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(__log, m) end }
function geterrorhandler() return function(e) print("ERROR: " .. tostring(e)) __errors = (__errors or 0) + 1 end end
UIParent = NewMock(); Minimap = NewMock(); GameTooltip = NewMock()
UISpecialFrames = {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc() end
function GameTooltip_Hide() end
function IsModifiedClick() return false end
function ChatEdit_InsertLink() end
function SendChatMessage(m, c) table.insert(__log, "[" .. c .. "] " .. m) end
SlashCmdList = {}
function GetNumSkillLines() return 4 end
local SK = { { "Professions", true }, { "Tailoring", false, nil, 150 }, { "Secondary Skills", true }, { "First Aid", false, nil, 100 } }
function GetSkillLineInfo(i) return unpack(SK[i]) end
C_Container = {
  GetContainerNumSlots = function(b) return 16 end,
  GetContainerItemInfo = function(b, s) local x = __bags[b] and __bags[b][s]; if x then return { itemID = x[1], stackCount = x[2], hyperlink = __link(x[1]) } end end,
  GetContainerNumFreeSlots = function() return 5 end,
}
function GetMoney() return __money end
function GetInboxHeaderInfo(i) local m = __inbox[i]; if m then return nil, nil, m.sender, "subj", m.money or 0, 0 end end
function GetInboxItemLink(i, a) local m = __inbox[i]; if m and m.items[a] then return __link(m.items[a][1]) end end
function GetInboxItem(i, a) local m = __inbox[i]; if m and m.items[a] then return "x", m.items[a][1], "tex", m.items[a][2] end end
function TakeInboxItem(i, a) __inbox[i].items[a] = nil end
function TakeInboxMoney(i) __inbox[i].money = 0 end
function AutoLootMailItem(i) end
ATTACHMENTS_MAX_RECEIVE = 12
function GetTargetTradeMoney() return 0 end
function GetTradeTargetItemLink() end
function GetTradeTargetItemInfo() end
function GetCoinTextureString(c) return c .. "c" end
function GetCursorInfo() end
function ClearCursor() end
function GetTradeSkillLine() return "Tailoring", 150, 300 end
__TS = { { "Cloth", "header" }, { "Bolt of Linen Cloth", "easy", 2996 } }
function GetNumTradeSkills() return #__TS end
function GetTradeSkillInfo(i) return __TS[i][1], __TS[i][2] end
function GetTradeSkillItemLink(i) if __TS[i][3] then return __link(__TS[i][3]) end end
__TSR = {}   -- [index] = { {itemID, count}, ... } reagents
function GetTradeSkillNumReagents(i) return #(__TSR[i] or {}) end
function GetTradeSkillReagentInfo(i, j) local r = __TSR[i][j]; return ITEMS[r[1]], "icon", r[2], 0 end
function GetTradeSkillReagentItemLink(i, j) return __link(__TSR[i][j][1]) end
ERR_TRADE_COMPLETE = "Trade complete."

function __load(dir)
  __ns = {}
  local files = {}
  for line in io.lines(dir .. "/EPUGuild.toc") do
    if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
  end
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(dir .. "/" .. f))
    chunk("EPUGuild", __ns)
  end
  __fire("ADDON_LOADED", "EPUGuild")
  __fire("PLAYER_LOGIN")
  __fire("PLAYER_ENTERING_WORLD", true, false)
end
date = os.date; time = os.time
__sendItems = {}
function GetSendMailItemLink(i) local id = __sendItems[i]; if id then return __link(id) end end
function SendMail(to) __lastMailTo = to; __fire("MAIL_SEND_SUCCESS") end
function GetTradePlayerItemLink() end
__shopping = nil
Auctionator = { API = { v1 = {
  ConvertToSearchString = function(caller, term) return '"' .. term.searchString .. '";;;;;;;;;;;;;' .. tostring(term.quantity) end,
  CreateShoppingList = function(caller, name, terms) __shopping = { name = name, terms = terms } end,
} } }
-- guild bank
__gb = { {}, {} }
__gblog = { {}, {} }
__gbmoneylog = {}
function GetNumGuildBankTabs() return 2 end
function GetGuildBankTabInfo(tab) return "Tab" .. tab, "icon", true end
function GetCurrentGuildBankTab() return 1 end
function GetGuildBankItemLink(tab, slot) local x = __gb[tab][slot]; if x then return __link(x[1]) end end
function GetGuildBankItemInfo(tab, slot) local x = __gb[tab][slot]; if x then return "icon", x[2] end end
function GetGuildBankMoney() return 5000000 end
function QueryGuildBankTab() end
function QueryGuildBankLog() end
function GetNumGuildBankTransactions(tab) return #__gblog[tab] end
function GetGuildBankTransaction(tab, i) local e = __gblog[tab][i]; return "deposit", e[1], __link(e[2]), e[3], nil, nil, 0, 0, 0, e[4] end
function GetNumGuildBankMoneyTransactions() return #__gbmoneylog end
function GetGuildBankMoneyTransaction(i) local e = __gbmoneylog[i]; return "deposit", e[1], e[2], 0, 0, 0, e[3] end
function ReloadUI() end
-- WoW-style SavedVariables writer
local function q(s) return string.format("%q", s) end
local function dump(v, ind, out)
  if type(v) == "table" then
    out[#out+1] = "{\n"
    for k, x in pairs(v) do
      out[#out+1] = string.rep("\t", ind + 1) .. (type(k) == "string" and ("[" .. q(k) .. "]") or ("[" .. tostring(k) .. "]")) .. " = "
      dump(x, ind + 1, out)
      out[#out+1] = ",\n"
    end
    out[#out+1] = string.rep("\t", ind) .. "}"
  elseif type(v) == "string" then out[#out+1] = q(v)
  else out[#out+1] = tostring(v) end
end
function __dumpSV(path)
  local out = {"\nEPUGuildDB = "}
  dump(EPUGuildDB, 0, out)
  out[#out+1] = "\nEPUGuildCharDB = nil\n"
  local f = io.open(path, "w"); f:write(table.concat(out)); f:close()
end

-- mailbox
__mailSlots = {}
MailFrame = NewMock(); MailFrame._shown = false
SendMailFrame = NewMock(); SendMailFrame._shown = true
SendMailNameEditBox = NewMock(); SendMailSubjectEditBox = NewMock()
__cursor = nil
C_Container.PickupContainerItem = function(b, s) local x = __bags[b][s]; __cursor = {x[1], x[2]}; __bags[b][s] = nil end
C_Container.SplitContainerItem = function(b, s, n) local x = __bags[b][s]; x[2] = x[2] - n; __cursor = {x[1], n} end
function ClickSendMailItemButton(i) __mailSlots[i] = __cursor; __cursor = nil end
function GuildControlGetNumRanks() return 5 end
function GuildControlGetRankName(i) return ({"Guild Master", "Officer", "Veteran", "Member", "Initiate"})[i] end

__popups = {}
function StaticPopup_Show(name, a, b) table.insert(__popups, {name, a, b}) end
OKAY = "Okay"

-- tooltips, sounds, Baganator
GameTooltip = NewMock(); GameTooltip._lines = {}
function GameTooltip:AddLine(t) table.insert(self._lines, t) end
ItemRefTooltip = NewMock()
Enum = Enum or {}; Enum.TooltipDataType = { Item = 0 }
__tooltipHook = nil
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) __tooltipHook = fn end }
function PlaySound() end
function IsShiftKeyDown() return false end
C_Container.GetContainerItemID = function(b, s) local x = __bags[b] and __bags[b][s]; return x and x[1] end
MailFrameTab2 = NewMock()
__corner = nil
Baganator = { API = { RegisterCornerWidget = function(label, id, onUpdate, onInit) __corner = { onUpdate = onUpdate, onInit = onInit } end,
  RequestItemButtonsRefresh = function() end } }

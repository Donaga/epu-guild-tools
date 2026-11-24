-- EPU Guild Tools: spell rank checker (/epu ranks).
--
-- WoW: Forever doesn't put a new spell rank on your action bars when you
-- train it, so bars keep casting the old rank. This reads each action slot,
-- compares the spell on it with the highest rank of that spell in your
-- spellbook, and lists the slots that are behind. Out of combat it can put
-- the highest rank on a slot for you (pick up the spell, place it on the
-- slot), and you can mark a rank you keep on purpose (downranking) so it
-- isn't flagged again.
local _, ns = ...

local SpellRanks = {}
ns.SpellRanks = SpellRanks

local MAX_SLOT = 180     -- 12 bars of 12; most clients use 1-120
local SCAN_DELAY = 2     -- SPELLS_CHANGED and slot changes come in bursts
local LOGIN_DELAY = 5    -- the spellbook and bars finish loading after login

local function SafeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function SafeNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function Settings()
  if not ns.db then return {} end
  ns.db.settings = ns.db.settings or {}
  return ns.db.settings
end

-- Ranks you keep on bars on purpose, by spell ID, for this character.
local function Kept()
  if not ns.cdb then return {} end
  ns.cdb.spellRanksKept = ns.cdb.spellRanksKept or {}
  return ns.cdb.spellRanksKept
end

---------------------------------------------------------------------------
-- Spell facts, through whichever API this client has
---------------------------------------------------------------------------
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = SafeStr(C_Spell.GetSpellName(id))
    if n then return n end
  end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" and SafeStr(info.name) then return info.name end
  end
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    return SafeStr(n)
  end
end

local function SpellSubtext(id)
  if C_Spell and C_Spell.GetSpellSubtext then
    local s = SafeStr(C_Spell.GetSpellSubtext(id))
    if s then return s end
  end
  if GetSpellSubtext then return SafeStr(GetSpellSubtext(id)) end
end

-- "Rank 3" (or "Rang 3", "Rango 3"...) -> 3. Spells without a number in their
-- subtext (Racial, Passive, Apprentice) have no rank to compare.
function SpellRanks.ParseRank(subtext)
  subtext = SafeStr(subtext)
  if not subtext then return nil end
  return tonumber(subtext:match("(%d+)%s*$") or subtext:match("(%d+)"))
end

local function SpellRank(id, subtext)
  return SpellRanks.ParseRank(subtext or SpellSubtext(id))
end

-- Every ranked player spell in the spellbook: best[name] = { id, rank }.
local function HighestKnownRanks()
  local best = {}
  local function Consider(id, name, subtext)
    id = SafeNum(id)
    if not id then return end
    name = SafeStr(name) or SpellName(id)
    local rank = SpellRank(id, SafeStr(subtext))
    if not name or not rank then return end
    local cur = best[name]
    if not cur or rank > cur.rank then best[name] = { id = id, rank = rank } end
  end

  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
    and C_SpellBook.GetSpellBookItemInfo then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, SafeNum(C_SpellBook.GetNumSpellBookSkillLines()) or 0 do
      local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
      if type(li) == "table" then
        local offset, n = SafeNum(li.itemIndexOffset) or 0, SafeNum(li.numSpellBookItems) or 0
        for i = offset + 1, offset + n do
          local it = C_SpellBook.GetSpellBookItemInfo(i, bank)
          if type(it) == "table" and (spellType == nil or it.itemType == spellType) and not it.isPassive
            and not it.isOffSpec then
            Consider(it.spellID or it.actionID, it.name, it.subName)
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    local book = BOOKTYPE_SPELL or "spell"
    for tab = 1, SafeNum(GetNumSpellTabs()) or 0 do
      local _, _, offset, n = GetSpellTabInfo(tab)
      offset, n = SafeNum(offset) or 0, SafeNum(n) or 0
      for i = offset + 1, offset + n do
        local kind, id = GetSpellBookItemInfo(i, book)
        if kind == "SPELL" then
          local name, subtext
          if GetSpellBookItemName then name, subtext = GetSpellBookItemName(i, book) end
          Consider(id, name, subtext)
        end
      end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Action slots
---------------------------------------------------------------------------
local BAR_NAMES = {
  "Main bar", "Main bar, page 2", "Right bar", "Right bar 2", "Bottom right bar", "Bottom left bar",
  "Stance or form bar 1", "Stance or form bar 2", "Stance or form bar 3", "Stance or form bar 4",
}

function SpellRanks.SlotLabel(slot)
  local bar = math.floor((slot - 1) / 12) + 1
  local button = (slot - 1) % 12 + 1
  return string.format("%s, button %d", BAR_NAMES[bar] or ("Bar " .. bar), button)
end

local function SpellOnSlot(slot)
  if not GetActionInfo then return nil end
  local kind, id = GetActionInfo(slot)
  if SafeStr(kind) ~= "spell" then return nil end
  return SafeNum(id)
end

-- The slots that hold a lower rank than the spellbook's highest:
-- { slot, label, name, oldID, oldRank, newID, newRank, kept }, by slot.
function SpellRanks.Scan()
  local best = HighestKnownRanks()
  local kept = Kept()
  local out = {}
  if not next(best) then return out end
  for slot = 1, MAX_SLOT do
    local id = SpellOnSlot(slot)
    if id then
      local name = SpellName(id)
      local top = name and best[name]
      local rank = top and SpellRank(id)
      if top and rank and rank < top.rank and top.id ~= id then
        out[#out + 1] = {
          slot = slot, label = SpellRanks.SlotLabel(slot), name = name,
          oldID = id, oldRank = rank, newID = top.id, newRank = top.rank,
          kept = kept[id] == true,
        }
      end
    end
  end
  return out
end

local function Outdated(list)
  local t = {}
  for _, r in ipairs(list) do if not r.kept then t[#t + 1] = r end end
  return t
end

-- Put the highest rank on one slot. Only out of combat, with nothing on the
-- cursor, and only if the slot still holds the old rank. Returns true when
-- the slot reads back as the new spell.
function SpellRanks.Update(row)
  if InCombat() then return false, "combat" end
  local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
  if not pickup or not PlaceAction or not GetActionInfo then return false, "api" end
  if GetCursorInfo and GetCursorInfo() then return false, "cursor" end
  if SpellOnSlot(row.slot) ~= row.oldID then return false, "changed" end
  local ok = pcall(pickup, row.newID)
  local onCursor = ok and GetCursorInfo and SafeStr((GetCursorInfo())) == "spell"
  if not onCursor then
    if ClearCursor then ClearCursor() end
    return false, "api"
  end
  ok = pcall(PlaceAction, row.slot)
  -- PlaceAction swaps: the old rank is on the cursor now. Drop it.
  if ClearCursor then ClearCursor() end
  if ok and SpellOnSlot(row.slot) == row.newID then return true end
  return false, "api"
end

local FAIL_TEXT = {
  combat = "Can't change action bars in combat. Try again once combat ends.",
  cursor = "Put down what's on your cursor first, then try again.",
  changed = "That button changed since the list was made. The list is up to date now.",
  api = "This client didn't let EPU change that button. Drag the spell from your spellbook instead.",
}

function SpellRanks.UpdateAll()
  local done, failed, why = 0, 0, nil
  for _, row in ipairs(Outdated(SpellRanks.Scan())) do
    local ok, reason = SpellRanks.Update(row)
    if ok then done = done + 1 else failed = failed + 1; why = why or reason end
    if reason == "combat" or reason == "cursor" then break end
  end
  return done, failed, why
end

---------------------------------------------------------------------------
-- Chat reminder after login and after training
---------------------------------------------------------------------------
local told = {}   -- "slot:oldID:newID" already mentioned this session

local function Remind()
  if Settings().spellRankReminder == false then return end
  local fresh, names, seen = 0, {}, {}
  for _, r in ipairs(Outdated(SpellRanks.Scan())) do
    local key = r.slot .. ":" .. r.oldID .. ":" .. r.newID
    if not told[key] then
      told[key] = true
      fresh = fresh + 1
      if not seen[r.name] then seen[r.name] = true; names[#names + 1] = r.name end
    end
  end
  if fresh == 0 then return end
  local shown = {}
  for i = 1, math.min(3, #names) do shown[i] = names[i] end
  local list = table.concat(shown, ", ") .. (#names > 3 and string.format(" and %d more", #names - 3) or "")
  ns.Print(string.format("%d action bar button%s still use%s an old spell rank (%s). Type |cffffd100/epu ranks|r to update them.",
    fresh, fresh == 1 and "" or "s", fresh == 1 and "s" or "", list))
end

local remindWaiting = false
local function QueueRemind(delay)
  if InCombat() then remindWaiting = true; return end
  ns.Debounce("spellRanks:remind", delay or SCAN_DELAY, function()
    if InCombat() then remindWaiting = true; return end
    Remind()
  end)
end

---------------------------------------------------------------------------
-- Window (/epu ranks, or Member tools -> Spell ranks)
---------------------------------------------------------------------------
local win
local status   -- one line of feedback after a button press

function ns.OpenSpellRanks()
  if not win then
    win = ns.InterfaceWindow("EPUGuildSpellRanks", UIParent, "Spell ranks on your bars", 520, 440)
    win:SetFrameStrata("DIALOG")
    local scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(490); child:SetHeight(380)
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
      local function Line(txt, col, x, w, dy)
        local f = pool:Font(11, col or C.text, "line")
        f:SetPoint("TOPLEFT", x or 4, y - (dy or 0))
        f:SetWidth(w or 480)
        f:SetJustifyH("LEFT")
        f:SetText(txt)
        return f
      end
      local function Heading(t)
        local h = pool:Font(12, C.gold or C.white, "heading")
        h:SetPoint("TOPLEFT", 0, y - 4)
        h:SetText(t)
        y = y - 24
      end
      local function Button(text, w, x, style, onClick, disabledTip)
        local b = pool:Button(text, w, 20, style)
        b:SetPoint("TOPLEFT", x, y + 2)
        b:SetScript("OnClick", function() onClick(); win:Refresh() end)
        if disabledTip then b.disabledTip = disabledTip; b:SetEnabled(false) end
        return b
      end

      local rows = SpellRanks.Scan()
      local outdated, kept = {}, {}
      for _, r in ipairs(rows) do
        if r.kept then kept[#kept + 1] = r else outdated[#outdated + 1] = r end
      end
      local combatTip = InCombat() and "Action bars can't change in combat." or nil

      Line("Forever doesn't swap in a new spell rank when you train it. These buttons still cast a lower rank than your spellbook has.", C.muted)
      y = y - 34
      local all = Button(string.format("Update all (%d)", #outdated), 130, 0, "accent", function()
        local done, failed, why = SpellRanks.UpdateAll()
        if failed == 0 then status = string.format("Updated %d button%s.", done, done == 1 and "" or "s")
        else status = string.format("Updated %d, %d left. %s", done, failed, FAIL_TEXT[why] or "") end
      end, combatTip)
      if #outdated == 0 then all.disabledTip = "Nothing to update."; all:SetEnabled(false) end
      Button("Check again", 100, 136, nil, function() status = nil end)
      local remindOn = Settings().spellRankReminder ~= false
      local remind = Button("Remind me in chat", 140, 242, nil, function()
        Settings().spellRankReminder = not remindOn
      end)
      remind:SetOn(remindOn)
      remind.tip = "After login and after training, say in chat when a button is behind."
      y = y - 28
      if status then Line(status, C.gold); y = y - 20 end

      Heading("Old ranks on your bars")
      if #outdated == 0 then
        Line("Every ranked spell on your bars is the highest rank you know.", C.green)
        y = y - 20
      end
      for _, r in ipairs(outdated) do
        Line(string.format("|cffffffff%s|r  Rank %d  ->  |cff4ade80Rank %d|r", r.name, r.oldRank, r.newRank), C.text, 4, 270)
        Line(r.label, C.muted, 4, 270, 14)
        local row = r
        Button("Update", 70, 284, "accent", function()
          local ok, why = SpellRanks.Update(row)
          status = ok and string.format("%s on %s is now rank %d.", row.name, row.label, row.newRank) or FAIL_TEXT[why]
        end, combatTip)
        local keep = Button("Keep this rank", 120, 360, nil, function()
          Kept()[row.oldID] = true
          status = string.format("Keeping %s rank %d. It won't be flagged again on this character.", row.name, row.oldRank)
        end)
        keep.tip = "For a lower rank you use on purpose. It stops being flagged on any button."
        y = y - 36
      end

      if #kept > 0 then
        Heading("Lower ranks you keep on purpose")
        for _, r in ipairs(kept) do
          Line(string.format("%s  Rank %d  (%s)", r.name, r.oldRank, r.label), C.muted, 4, 380)
          local row = r
          Button("Stop keeping", 100, 384, nil, function()
            Kept()[row.oldID] = nil
            status = nil
          end)
          y = y - 26
        end
      end
      child:SetHeight(math.max(380, -y + 20))
    end
  end
  status = nil
  win:Refresh()
  win:Show()
end

local function RefreshIfShown()
  if win and win:IsShown() then win:Refresh() end
end

if ns.On then
  ns.On("PLAYER_LOGIN", function() QueueRemind(LOGIN_DELAY) end)
  -- Training a rank: remind about the buttons it left behind.
  ns.On("LEARNED_SPELL_IN_TAB", function() QueueRemind(SCAN_DELAY) end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    if remindWaiting then remindWaiting = false; QueueRemind(SCAN_DELAY) end
    RefreshIfShown()
  end)
  ns.On("PLAYER_REGEN_DISABLED", RefreshIfShown)
  for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "SPELLS_CHANGED" }) do
    ns.On(ev, function()
      if win and win:IsShown() then ns.Debounce("spellRanks:window", 0.5, RefreshIfShown) end
    end)
  end
end

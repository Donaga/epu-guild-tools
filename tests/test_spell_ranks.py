"""Spell rank checker (/epu ranks).

WoW: Forever doesn't put a newly trained spell rank on the action bars, so
buttons keep casting the old rank. The checker compares every spell on the
bars with the highest rank of that spell in the spellbook, lists the buttons
that are behind, reminds in chat after login and training, and out of combat
puts the highest rank on a button for you. A lower rank kept on purpose can
be marked so it isn't flagged again.
"""
from simcore import *

SPELLBOOK_CLASSIC = r'''
-- id = { name, subtext }
__spells = {
  [116] = { "Frostbolt", "Rank 1" }, [205] = { "Frostbolt", "Rank 2" }, [837] = { "Frostbolt", "Rank 3" },
  [133] = { "Fireball", "Rank 1" }, [143] = { "Fireball", "Rank 2" },
  [1459] = { "Arcane Intellect", "Rank 1" },
  [20549] = { "War Stomp", "Racial" },
  [2136] = { "Fire Blast", "Rank 1" }, [2137] = { "Fire Blast", "Rank 2" },
}
__book = { 116, 205, 837, 133, 143, 1459, 20549, 2136 }
__actions = { [1] = { "spell", 143 }, [2] = { "spell", 116 }, [3] = { "spell", 1459 }, [4] = { "spell", 20549 },
  [5] = { "item", 6948 }, [6] = { "macro", 1 }, [14] = { "spell", 205 }, [15] = { "spell", 2136 } }
__combat = false
__placed = 0
InCombatLockdown = function() return __combat end
GetSpellInfo = function(id) local s = __spells[id]; if s then return s[1], nil, "icon", 0, 0, 0, id end end
GetSpellSubtext = function(id) local s = __spells[id]; return s and s[2] end
GetNumSpellTabs = function() return 2 end
GetSpellTabInfo = function(tab) if tab == 1 then return "General", "icon", 0, 1 end return "Frost", "icon", 1, #__book - 1 end
GetSpellBookItemInfo = function(i, book) local id = __book[i]; if id then return "SPELL", id end end
GetSpellBookItemName = function(i, book) local id = __book[i]; if id then return __spells[id][1], __spells[id][2] end end
GetActionInfo = function(slot) local a = __actions[slot]; if a then return a[1], a[2] end end
PickupSpell = function(id) if __spells[id] then __cursorSpell = id end end
PlaceAction = function(slot)
  if __combat then error("blocked in combat") end
  __placed = __placed + 1
  local old = __actions[slot]
  __actions[slot] = { "spell", __cursorSpell }
  __cursorSpell = old and old[1] == "spell" and old[2] or nil
  __fire("ACTIONBAR_SLOT_CHANGED", slot)
end
local baseCursor = GetCursorInfo
GetCursorInfo = function()
  if __cursorSpell then return "spell", 1, "spell", __cursorSpell end
  return baseCursor()
end
local baseClear = ClearCursor
ClearCursor = function() __cursorSpell = nil; return baseClear() end
'''

A = Client('Chris Baker')
clients[A.name] = A
A.ex(SPELLBOOK_CLASSIC)
A.ex('''function __texts()
  local t = {}
  for _, w in ipairs(EPUGuildSpellRanks.pool.used) do
    if w.GetText and w:IsShown() then t[#t + 1] = w:GetText() end
  end
  return table.concat(t, "\\n")
end
function __button(label)
  for _, w in ipairs(EPUGuildSpellRanks.pool.used) do
    if w.GetText and w:IsShown() and w:GetText() == label and w.GetScript and w:GetScript("OnClick") then return w end
  end
end
function __buttons(label)
  local n = 0
  for _, w in ipairs(EPUGuildSpellRanks.pool.used) do
    if w.GetText and w:IsShown() and w:GetText() == label and w.GetScript and w:GetScript("OnClick") then n = n + 1 end
  end
  return n
end
function __logText() return table.concat(__log, "\\n") end
function __reminders()
  local n = 0
  for _, m in ipairs(__log) do if tostring(m):find("old spell rank", 1, true) then n = n + 1 end end
  return n
end''')
# The suite's login fired before the spellbook existed: log in again with it.
A.ex('__log = {}; __fire("PLAYER_LOGIN")')
tick(8)

# --- Finding old ranks ---
rows = A.ev('''(function()
  local t = {}
  for _, r in ipairs(__ns.SpellRanks.Scan()) do
    t[#t + 1] = r.slot .. "=" .. r.name .. ":" .. r.oldRank .. ">" .. r.newRank .. ":" .. r.newID
  end
  return table.concat(t, ",")
end)()''')
check('an old Frostbolt on the main bar and on page 2 are found, with the highest rank known',
      rows == '2=Frostbolt:1>3:837,14=Frostbolt:2>3:837')
check('a rank the spellbook does not have yet is not offered', 'Fire Blast' not in rows)
check('a spell already on its highest rank, a one-rank spell, a racial, an item and a macro are not flagged',
      {r.split('=')[0] for r in rows.split(',')} == {'2', '14'})
check('slots are named by bar and button', A.ev('__ns.SpellRanks.SlotLabel(14)') == 'Main bar, page 2, button 2')
check('ranks are read from the number in the subtext', A.ev('__ns.SpellRanks.ParseRank("Rang 4")') == 4)
check('a subtext without a number has no rank', A.ev('__ns.SpellRanks.ParseRank("Racial")') is None)

# --- Chat reminder ---
check('login says in chat that two buttons use an old rank', A.ev('__reminders()') == 1 and
      '2 action bar buttons still use an old spell rank (Frostbolt)' in (A.ev('__logText()') or ''))
check('the reminder names the command to fix it', '/epu ranks' in (A.ev('__logText()') or ''))
A.ex('__fire("LEARNED_SPELL_IN_TAB", 1)')
tick(4)
check('training something else does not repeat the same reminder', A.ev('__reminders()') == 1)

A.ex('table.insert(__book, 2137); __fire("LEARNED_SPELL_IN_TAB", 2137)')
tick(4)
check('training a new rank reminds about the button it left behind', A.ev('__reminders()') == 2 and
      '1 action bar button still uses an old spell rank (Fire Blast)' in (A.ev('__logText()') or ''))

A.ex('__combat = true; table.insert(__book, 2138); __spells[2138] = { "Fireball", "Rank 3" }; __fire("LEARNED_SPELL_IN_TAB", 2138)')
tick(5)
check('no reminder in combat', A.ev('__reminders()') == 2)
A.ex('__combat = false; __fire("PLAYER_REGEN_ENABLED")')
tick(4)
check('the reminder held back in combat comes once combat ends', A.ev('__reminders()') == 3)

# --- Window opens from the main window and by command ---
A.ex('''function __clickRow(key) for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key==key then r:GetScript("OnClick")(r); return true end end error("Missing row "..key) end
__ns.UI:Show(); __ns.UI.nav.membertools:Click(); __clickRow("spellranks")''')
check('the Spell ranks tile in Member tools opens the checker', A.ev('EPUGuildSpellRanks ~= nil and EPUGuildSpellRanks:IsShown()'))
A.ex('EPUGuildSpellRanks:Hide(); SlashCmdList.EPUGUILD("ranks")')
check('/epu ranks opens the checker', A.ev('EPUGuildSpellRanks:IsShown()'))
text = A.ev('__texts()') or ''
check('the window lists each old rank with the rank it can go to', 'Frostbolt|r  Rank 1  ->  |cff4ade80Rank 3' in text)
check('the window says which button it is on', 'Main bar, button 2' in text and 'Main bar, page 2, button 2' in text)
check('each old rank has an Update button', A.ev('__buttons("Update")') == 4)

# --- Updating one button, and refusing in combat ---
A.ex('__combat = true; EPUGuildSpellRanks:Refresh()')
check('Update is turned off in combat', A.ev('__button("Update"):IsEnabled()') is False)
ok, why = A.ev('__ns.SpellRanks.Update(__ns.SpellRanks.Scan()[1])')
check('an update asked for in combat does nothing and says why', ok is False and why == 'combat' and A.ev('__placed') == 0)
A.ex('__combat = false; EPUGuildSpellRanks:Refresh()')
A.ex('__button("Update"):Click()')
check('Update puts the highest rank on that button', A.ev('__actions[1][2]') == 2138)
check('the old rank is not left on the cursor', A.ev('__cursorSpell') is None)
check('the window says what changed', 'is now rank' in (A.ev('__texts()') or ''))

A.ex('__cursor_item = 6948')
ok, why = A.ev('__ns.SpellRanks.Update(__ns.SpellRanks.Scan()[1])')
check('an update waits while something else is on the cursor', ok is False and why == 'cursor')
A.ex('__cursor_item = nil')

# --- Keeping a lower rank on purpose ---
A.ex('__actions[2] = { "spell", 116 }; EPUGuildSpellRanks:Refresh()')
check('the button put back on rank 1 is listed again', A.ev('__ns.SpellRanks.Scan()[1].oldID') == 116)
A.ex('__button("Keep this rank"):Click()')   # the first row: Frostbolt rank 1 on the main bar
check('Keep this rank marks Frostbolt rank 1 as kept', A.ev('__ns.cdb.spellRanksKept[116]') is True)
text = A.ev('__texts()') or ''
check('a kept rank moves to its own list', 'Lower ranks you keep on purpose' in text and 'Frostbolt  Rank 1  (Main bar, button 2)' in text)
A.ex('__log = {}; __fire("LEARNED_SPELL_IN_TAB", 1)')
tick(4)
check('a kept rank is never in a reminder', 'Frostbolt' not in (A.ev('__logText()') or ''))
left = A.ev('(function() local n = 0 for _, r in ipairs(__ns.SpellRanks.Scan()) do if not r.kept then n = n + 1 end end return n end)()')
check('other old ranks are still listed', left >= 1)
A.ex(f'__button("Update all ({left})"):Click()')
check('Update all leaves the kept rank alone', A.ev('__actions[2][2]') == 116)
check('Update all fixes the rest', A.ev('(function() for _, r in ipairs(__ns.SpellRanks.Scan()) do if not r.kept then return false end end return true end)()') is True)
check('the window says how many it updated', f'Updated {left} button' in (A.ev('__texts()') or ''))
A.ex('__button("Stop keeping"):Click()')
check('Stop keeping puts the rank back on the list', A.ev('__ns.cdb.spellRanksKept[116]') is None and
      A.ev('__buttons("Update")') == 1)

# --- Reminder switch ---
A.ex('__ns.cdb.spellRanksKept = {}; EPUGuildSpellRanks:Refresh(); __button("Remind me in chat"):Click()')
check('the reminder can be turned off', A.ev('__ns.db.settings.spellRankReminder') is False)
A.ex('__log = {}; __actions[20] = { "spell", 133 }; __fire("LEARNED_SPELL_IN_TAB", 1)')
tick(4)
check('with the reminder off nothing is said in chat', A.ev('__reminders()') == 0)
A.ex('__button("Remind me in chat"):Click()')
check('the reminder can be turned back on', A.ev('__ns.db.settings.spellRankReminder') is True)

# --- Redraws reuse their widgets ---
A.ex('''__made = 0
local M = getmetatable(UIParent)
local fs, tex = M.CreateFontString, M.CreateTexture
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end
M.CreateTexture = function(...) __made = __made + 1; return tex(...) end
local cf = CreateFrame
CreateFrame = function(...) __made = __made + 1; return cf(...) end
EPUGuildSpellRanks:Refresh(); EPUGuildSpellRanks:Refresh()''')
before = A.ev('__made')
for _ in range(10):
    A.ex('EPUGuildSpellRanks:Refresh(); __ns.OpenSpellRanks()')
check('redrawing the checker makes nothing new', A.ev('__made') == before)

# --- A client with the newer spellbook API ---
B = Client('Tyler Baker')
clients[B.name] = B
B.ex(SPELLBOOK_CLASSIC)
B.ex('''GetNumSpellTabs, GetSpellTabInfo, GetSpellBookItemInfo, GetSpellBookItemName, GetSpellInfo, GetSpellSubtext, PickupSpell = nil
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
Enum.SpellBookItemType = { Spell = 1, None = 0, Flyout = 2, FutureSpell = 3, PetAction = 4 }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #__book } end,
  GetSpellBookItemInfo = function(i, bank)
    local id = __book[i]
    if id then return { itemType = 1, spellID = id, name = __spells[id][1], subName = __spells[id][2] } end
  end,
}
C_Spell = C_Spell or {}
C_Spell.GetSpellName = function(id) return __spells[id] and __spells[id][1] end
C_Spell.GetSpellSubtext = function(id) return __spells[id] and __spells[id][2] end
C_Spell.PickupSpell = function(id) if __spells[id] then __cursorSpell = id end end''')
rows = B.ev('#__ns.SpellRanks.Scan()')
check('the newer spellbook API finds the same old ranks', rows == 2)
B.ex('__ns.SpellRanks.Update(__ns.SpellRanks.Scan()[1])')
check('the newer API can update a button too', B.ev('__actions[2][2]') == 837)

check('nothing went wrong', not A.ev('__errors') and not B.ev('__errors'))
print('Spell rank checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

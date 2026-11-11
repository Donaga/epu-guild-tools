"""Guild focus professions and the guild-wide Market view, across two synced clients."""
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)

# --- Guild focus ----------------------------------------------------------------
A.ex('__ns.SetGuildFocus("Alchemy", 225); __ns.SetGuildFocus("Herbalism", 0)')
tick(3)
tick_until(lambda: B.ev('__ns.GuildFocusOf("Alchemy") ~= nil and __ns.GuildFocusOf("Herbalism") ~= nil'))
check('an officer focus reaches members with its skill goal',
      B.ev('__ns.GuildFocusOf("Alchemy").goal') == 225 and B.ev('__ns.GuildFocusOf("Herbalism").goal') == 0)

B.ex('__ns.SetGuildFocus("Mining", 100)')
B.ex('__ns.Send("D", {guildFocus = {Alchemy = {on = false, goal = 0, t = __now + 50, by = "Tyler Baker"}}})')
tick(3)
check('members cannot set or clear the guild focus',
      A.ev('__ns.GuildFocusOf("Mining")') is None and A.ev('__ns.GuildFocusOf("Alchemy") ~= nil')
      and B.ev('__ns.GuildFocusOf("Mining")') is None)

A.ex('__ns.Send("D", {guildFocus = {Archaeology = {on = true, goal = 0, t = __now + 60}, Tailoring = {on = true, goal = 999, t = __now + 60}}})')
tick(3)
check('unknown professions and impossible goals are rejected',
      B.ev('__ns.GuildFocusOf("Archaeology")') is None and B.ev('__ns.GuildFocusOf("Tailoring")') is None)

A.ex("""
local g = __ns.G()
g.crafters["Tyler Baker"] = {t = __now, lvl = 30, profs = {Alchemy = 230, Herbalism = 150}}
g.crafters["Chris Stone"] = {t = __now, lvl = 20, profs = {Alchemy = 120}}
""")
check('focus progress counts players at the skill goal', A.ev("""
(function()
  for _, f in ipairs(__ns.GuildFocus()) do
    if f.prof == 'Alchemy' then return f.players == 2 and f.atGoal == 1 end
  end
end)()
"""))
A.ex("""
__texts = {}
local mock = getmetatable(NewMock())
local setText = mock.SetText
mock.SetText = function(self, text) __texts[#__texts + 1] = tostring(text); return setText(self, text) end
__ns.UI:Show(); __ns.UI:OpenDetails("coverage", "all")
mock.SetText = setText
""")
check('the coverage page shows focus progress and gives officers a button per profession', A.ev("""
(function()
  local focusLine, change, set = false, 0, 0
  for _, text in ipairs(__texts) do
    if text:find('Guild focus:', 1, true) and text:find('goal 225: 1 of 2 players there', 1, true) then focusLine = true end
    if text == 'Change focus' then change = change + 1 end
    if text == 'Set as focus' then set = set + 1 end
  end
  return focusLine and change == 2 and set == 10
end)()
"""))

A.ex('__ns.SetGuildFocus("Herbalism", nil)')
tick(3)
tick_until(lambda: B.ev('__ns.GuildFocusOf("Herbalism")') is None)
check('removing a focus reaches members', B.ev('__ns.GuildFocusOf("Herbalism")') is None)

B.ex("""
C_SkillInfo = {GetSkillLineInfoByID = function(id)
  if id == 197 then return {skillID = id, name = 'Tailoring', rank = 90} end
end}
GetNumSkillLines = nil; GetSkillLineInfo = nil
SlashCmdList.EPUGUILD('market')
""")
check('members see the guild focus in Market with a free-slot nudge', B.ev("""
(function()
  local text = EPUGuildGatheringMarket.focusText:GetText()
  return EPUGuildGatheringMarket.focusText:IsShown() and text:find('Alchemy 225', 1, true) ~= nil
    and text:find('free profession slot', 1, true) ~= nil
end)()
"""))
B.ex("""
C_SkillInfo = {GetSkillLineInfoByID = function(id)
  if id == 197 then return {skillID = id, name = 'Tailoring', rank = 90} end
  if id == 171 then return {skillID = id, name = 'Alchemy', rank = 140} end
end}
__ns.RefreshGatheringMarket()
""")
check('a member with the focus profession sees their own progress', B.ev("""
(function()
  local text = EPUGuildGatheringMarket.focusText:GetText()
  return text:find('Alchemy 225 (you 140)', 1, true) ~= nil and text:find('free profession slot', 1, true) == nil
end)()
"""))
check('the profession menu marks the focus', B.ev("""
(function()
  for _, option in ipairs(EPUGuildGatheringMarket.professionChoices) do
    if option.label == 'Alchemy' then return option.right:find('Focus', 1, true) == 1 end
  end
end)()
"""))

# --- Shared market data and the guild scope ----------------------------------------
B.ex("""
__ns.IsBoP = function() return false end
GetNumTradeSkills = nil
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return {professionID = 197, professionName = 'Tailoring', skillLevel = 90} end,
  GetAllRecipeIDs = function() return {1, 2, 3} end,
  GetRecipeInfo = function(id) return {learned = true, name = 'Recipe ' .. id} end,
  GetRecipeSchematic = function(id)
    if id == 1 then return {outputItemID = 2996, quantityMin = 1, quantityMax = 1,
      reagentSlotSchematics = {{quantityRequired = 2, reagents = {{itemID = 2589}}}}} end
    if id == 2 then return {outputItemID = 4343, quantityMin = 3, quantityMax = 3,
      reagentSlotSchematics = {{quantityRequired = 1, reagents = {{itemID = 2996}}}}} end
    return {outputItemID = 2570, quantityMin = 1, quantityMax = 1,
      reagentSlotSchematics = {{quantityRequired = 1, reagents = {{itemID = 2996}, {itemID = 2997}}}}}
  end,
}
__fire('TRADE_SKILL_SHOW'); __advance(3)
""")
tick(4)
tick_until(lambda: A.ev('__ns.G().recipes["Tyler Baker"] ~= nil and __ns.G().recipes["Tyler Baker"].profs.Tailoring ~= nil'))
check('shared recipes carry which items Market can price and multi-unit outputs', A.ev("""
(function()
  local p = __ns.G().recipes["Tyler Baker"].profs.Tailoring
  return p.m == 1 and p.mq[4343] == 3 and #p.nm == 1 and p.nm[1] == 2570
end)()
"""))

A.ex("""
__ns.IsBoP = function() return false end
AHledgerAPI = {GetPrice = function(id)
  return ({
    [2589] = {median = 20, minBuyout = 20},
    [2996] = {median = 200, minBuyout = 150, soldPerDay = 40, quantity = 20},
    [4343] = {median = 100, minBuyout = 90, soldPerDay = 10, quantity = 5},
    [2570] = {median = 900, minBuyout = 800, soldPerDay = 5},
    [7076] = {median = 1000, minBuyout = 1000, soldPerDay = 5},
  })[id]
end}
-- An older crafter shared recipes before Market data existed.
__ns.G().recipes["Chris Stone"] = {t = __now, profs = {Alchemy = {rank = 120, items = {7076}, spells = {}}}}
__ns.G().mats["item:7076"] = {t = __now, r = {2589, 1}, by = "Chris Stone"}
__ns.recipeIndex = nil
function __guild(sort)
  local rows, info = __ns.GuildCraftingRows('ledger', sort)
  local byItem = {}
  for _, r in ipairs(rows) do byItem[r.item] = r end
  return byItem, info
end
""")
check('guild rows price shared recipes at the current low and use the output quantity', A.ev("""
(function()
  local rows = __guild()
  local bolt, shirt = rows[2996], rows[4343]
  return bolt.cost == 40 and bolt.price == 150 and bolt.profit == 142 - 40
    and shirt.quantity == 3 and shirt.cost == 150 and shirt.profit == 85 * 3 - 150
    and bolt.crafters[1].who == 'Tyler Baker'
end)()
"""))
check('recipes with optional reagents stay out and older shares wait for an update', A.ev("""
(function()
  local rows, info = __guild()
  return rows[2570] == nil and rows[7076] == nil and info.waiting == 1 and info.crafters == 2
end)()
"""))
check('guild Buy & Craft keeps only profitable recipes with daily sales', A.ev("""
(function() local rows = __guild('profit'); return rows[2996] ~= nil and rows[4343] ~= nil end)()
"""))

A.ex("""
C_SkillInfo = {GetSkillLineInfoByID = function(id)
  if id == 164 then return {skillID = id, name = 'Blacksmithing', rank = 50} end
end}
GetNumSkillLines = nil; GetSkillLineInfo = nil
SlashCmdList.EPUGUILD('market')
EPUGuildGatheringMarket.craftTab:Click()
EPUGuildGatheringMarket.scope:Click()
""")
check("Scope: Guild lists guildmates' crafts with their crafters", A.ev("""
(function()
  local frame = EPUGuildGatheringMarket
  if frame.scope:GetText() ~= 'Scope: Guild' or frame.openProfession:IsShown() or frame.craftSort:IsShown() then return false end
  if not frame.context:GetText():find('1 waiting for crafters to update EPU', 1, true) then return false end
  for _, control in ipairs(__frames) do
    if control.row and control.row.item == 4343 and control.summary and control:IsShown() then
      return control.summary:GetText():find('Tyler Baker', 1, true) ~= nil
    end
  end
end)()
"""))
A.ex("EPUGuildGatheringMarket.professionFilter:Click()")
check('the guild profession menu lists guild professions', A.ev("""
(function()
  local labels = {}
  for _, row in ipairs(EPUGuildMenu.rows) do if row:IsShown() then labels[#labels + 1] = row.text:GetText() end end
  return labels[1] == 'All guild professions' and labels[2] == 'Tailoring' and #labels == 2
end)()
"""))
A.ex("EPUGuildMenu.rows[2]:Click()")
A.ex("""
for _, control in ipairs(__frames) do
  if control.row and control.row.item == 4343 and control.summary and control:IsShown() then control:Click(); break end
end
""")
check('a guild recipe shows its ingredients, crafters and an Ask a crafter button', A.ev("""
(function()
  local frame = EPUGuildGatheringMarket
  local text = frame.detailText:GetText()
  return frame.selected and frame.selected.item == 4343 and frame.askCrafter:IsShown()
    and text:find('Makes 3', 1, true) ~= nil and text:find('Crafters: ', 1, true) ~= nil
end)()
"""))
A.ex("EPUGuildGatheringMarket.askCrafter:Click()")
check('Ask a crafter opens the recipe in Recipes', A.ev('__ns.UI.view == "recipes"'))

A.ex("""
SlashCmdList.EPUGUILD('market')
EPUGuildGatheringMarket.scope:Click()
""")
check('Scope: Mine returns to your own professions', A.ev("""
EPUGuildGatheringMarket.scope:GetText() == 'Scope: Mine' and EPUGuildGatheringMarket.professionFilter:GetText() == 'All my professions'
"""))

# --- Guildmates who can gather a material ------------------------------------------
A.ex("""
C_SkillInfo = {GetSkillLineInfoByID = function(id)
  if id == 182 then return {skillID = id, name = 'Herbalism', rank = 50} end
end}
EPUGuildGatheringMarket.gatherTab:Click()
for _, control in ipairs(__frames) do
  if control.row and control.row.item == 785 and control.summary and control:IsShown() then control:Click(); break end
end
""")
check('Gather shows how many guildmates can gather a material', A.ev("""
(function()
  local frame = EPUGuildGatheringMarket
  return frame.selected and frame.selected.item == 785
    and frame.detailText:GetText():find('1 guildmate can gather this', 1, true) ~= nil
end)()
"""))
check('no addon runtime errors', (A.ev('__errors') or 0) == 0 and (B.ev('__errors') or 0) == 0)
sys.exit(bool(check.failed))

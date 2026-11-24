"""Bank gear for you: weapons and armor in the guild bank that fit this character.

/epu bankgear (or Gear for you on the main window's Bank page, or the Bank
gear for you tile in Member tools) lists bank gear whose required level is
yours or up to five levels ahead, in the armor type your class wears and a
weapon type it can train, with an upgrade hint by item level against what you
wear in that slot. Each item gets Pull (at the open guild bank) or Request.
"""
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]   # A is an officer, B a member
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)
LOG = 'table.concat(__log, "\\n")'
BAG = "(function() local n = 0 for _, s in pairs(__bags[0]) do if s[1] == %d then n = n + s[2] end end return n end)()"

# Gear the stub item database doesn't know: { quality, item level, required level, classID, subclassID, equip slot }
GEAR = '''
__gear = {
  [30010] = {2, 22, 18, 4, 3, "INVTYPE_CHEST"},      -- mail chest: an upgrade over Tyler's
  [30011] = {2, 45, 40, 4, 4, "INVTYPE_LEGS"},       -- plate legs, level 40
  [30012] = {2, 21, 20, 4, 2, "INVTYPE_FEET"},       -- leather boots: not for a warrior
  [30013] = {2, 24, 22, 4, 1, "INVTYPE_CLOAK"},      -- cloth cloak: anyone, two levels ahead
  [30014] = {2, 18, 15, 2, 19, "INVTYPE_RANGEDRIGHT"},-- wand: not for a warrior
  [30015] = {2, 20, 19, 2, 7, "INVTYPE_WEAPON"},     -- one-hand sword
  [30016] = {2, 8, 5, 4, 0, "INVTYPE_FINGER"},       -- low ring, but the finger slots are empty
  [30017] = {2, 8, 5, 4, 3, "INVTYPE_HEAD"},         -- low mail helm, worse than what Tyler wears
  [30018] = {2, 14, 20, 4, 6, "INVTYPE_SHIELD"},     -- shield, weaker than the off hand
  [30019] = {2, 30, 26, 4, 3, "INVTYPE_WRIST"},      -- mail bracers, six levels ahead: too far
  -- worn
  [30020] = {2, 18, 15, 4, 3, "INVTYPE_CHEST"},
  [30022] = {2, 24, 20, 2, 7, "INVTYPE_WEAPON"},
  [30023] = {2, 15, 12, 2, 0, "INVTYPE_WEAPON"},
  [30024] = {2, 20, 18, 4, 3, "INVTYPE_HEAD"},
}
local base = GetItemInfo
GetItemInfo = function(x)
  local id = tonumber(x) or (type(x) == "string" and tonumber(x:match("item:(%d+)")))
  if id == 30030 then return nil end   -- still loading
  local g = id and __gear[id]
  if not g then return base(x) end
  return __ITEMS[id], __link(id), g[1], g[2], g[3], "Armor", "Mail", 1, g[6], "icon" .. id, 1, g[4], g[5], 2
end
GetItemInfoInstant = function(id)
  local g = __gear[id]
  if id == 30030 then return id, "Armor", "Mail", "INVTYPE_HEAD", "icon", 4, 3 end
  return id, nil, nil, g and g[6], "icon" .. id, g and g[4], g and g[5]
end
__class = "WARRIOR"
UnitClass = function() return "Warrior", __class end
__level = 20
UnitLevel = function() return __level end
__equip = { [5] = 30020, [16] = 30022, [17] = 30023, [1] = 30024 }
GetInventoryItemLink = function(_, slot) local id = __equip[slot]; return id and __link(id) end
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end; __bags[0] = {}
'''
for c in (A, B):
    c.ex(GEAR)
    c.ex('__ns.G().bank["Epu Bank"] = { v = 1, money = 0, items = { [30010] = 1, [30011] = 1, [30012] = 1, [30013] = 2,'
         ' [30014] = 1, [30015] = 1, [30016] = 1, [30017] = 1, [30018] = 1, [30019] = 1, [30030] = 1, [2589] = 40 } }')


def fits(cls, level, classID, sub, loc, req):
    return B.ev('__ns.BankGearFits({classID=%d, subclassID=%d, equipLoc="%s", reqLevel=%d}, "%s", %d)'
                % (classID, sub, loc, req, cls, level))


# --- Who can use what ---------------------------------------------------------------------
check("a level 20 warrior wears mail now", fits("WARRIOR", 20, 4, 3, "INVTYPE_CHEST", 18) == "now")
check("plate waits for level 40", fits("WARRIOR", 20, 4, 4, "INVTYPE_LEGS", 40) is False)
check("a level 38 warrior sees level 40 plate as coming soon", fits("WARRIOR", 38, 4, 4, "INVTYPE_LEGS", 40) == "soon")
check("but not level 40 mail, since they'll wear plate by then", fits("WARRIOR", 38, 4, 3, "INVTYPE_LEGS", 40) is False)
check("a level 40 hunter wears mail", fits("HUNTER", 40, 4, 3, "INVTYPE_CHEST", 40) == "now")
check("a level 30 hunter wears leather, not mail",
      fits("HUNTER", 30, 4, 2, "INVTYPE_CHEST", 30) == "now" and fits("HUNTER", 30, 4, 3, "INVTYPE_CHEST", 30) is False)
check("priests wear cloth and use wands", fits("PRIEST", 20, 4, 1, "INVTYPE_ROBE", 20) == "now"
      and fits("PRIEST", 20, 2, 19, "INVTYPE_RANGEDRIGHT", 20) == "now")
check("priests can't use swords or leather", fits("PRIEST", 20, 2, 7, "INVTYPE_WEAPON", 20) is False
      and fits("PRIEST", 20, 4, 2, "INVTYPE_CHEST", 20) is False)
check("druids use staves but not swords", fits("DRUID", 20, 2, 10, "INVTYPE_2HWEAPON", 20) == "now"
      and fits("DRUID", 20, 2, 7, "INVTYPE_WEAPON", 20) is False)
check("anyone wears cloaks and rings", fits("WARRIOR", 20, 4, 1, "INVTYPE_CLOAK", 20) == "now"
      and fits("MAGE", 20, 4, 0, "INVTYPE_FINGER", 20) == "now")
check("shields: warriors and shamans, not rogues", fits("SHAMAN", 20, 4, 6, "INVTYPE_SHIELD", 20) == "now"
      and fits("ROGUE", 20, 4, 6, "INVTYPE_SHIELD", 20) is False)
check("relics go to their own class", fits("PALADIN", 20, 4, 7, "INVTYPE_RELIC", 20) == "now"
      and fits("DRUID", 20, 4, 7, "INVTYPE_RELIC", 20) is False and fits("DRUID", 20, 4, 8, "INVTYPE_RELIC", 20) == "now")
check("five levels ahead is the limit", fits("MAGE", 20, 4, 1, "INVTYPE_HEAD", 25) == "soon"
      and fits("MAGE", 20, 4, 1, "INVTYPE_HEAD", 26) is False)
check("bags and shirts aren't gear", fits("MAGE", 20, 4, 1, "INVTYPE_BODY", 1) is False)


# --- What the bank has for Tyler, a level 20 warrior -------------------------------------
def gear(c):
    return c.ev('''(function()
      local t = {}
      for _, e in ipairs((__ns.BankGearForMe())) do t[#t + 1] = e.id end
      return table.concat(t, ",")
    end)()''')


def entry(c, item):
    return c.ev('''(function()
      for _, e in ipairs((__ns.BankGearForMe())) do if e.id == %d then return e end end
    end)()''' % item)


ids = [int(x) for x in gear(B).split(",") if x]
check("Tyler sees the chest, cloak, sword, ring and shield (got %s)" % ids,
      sorted(ids) == [30010, 30013, 30015, 30016, 30018])
check("upgrades come first", set(ids[:4]) == {30010, 30013, 30015, 30016} and ids[4] == 30018)
check("leather, wands, plate, far-ahead bracers and trade goods stay out",
      not any(i in ids for i in (30011, 30012, 30014, 30019, 2589)))
check("a low item that's no upgrade stays out", 30017 not in ids)
check("an item still loading is counted", B.ev('select(2, __ns.BankGearForMe())') == 1)

chest = entry(B, 30010)
check("the chest is an upgrade over what Tyler wears", chest.upgrade and chest.yours == 18 and chest.fit == "now")
check("and says so (got %s)" % B.ev('__ns.BankGearCompareText(%s)' % 'select(1, __ns.BankGearForMe())[1]'),
      "Upgrade over your Test Item 30020 (item level 18)" == B.ev('''(function()
        for _, e in ipairs((__ns.BankGearForMe())) do if e.id == 30010 then return __ns.BankGearCompareText(e) end end end)()'''))
cloak = entry(B, 30013)
check("the cloak is for level 22, against an empty back slot", cloak.fit == "soon" and cloak.yours == 0 and cloak.upgrade)
check("an empty slot reads as an upgrade", B.ev('''(function()
  for _, e in ipairs((__ns.BankGearForMe())) do if e.id == 30013 then return __ns.BankGearCompareText(e) end end end)()''')
      == "Upgrade: your back slot is empty")
sword = entry(B, 30015)
check("a warrior's one-hander is measured against the weaker of the two hands", sword.yours == 15 and sword.upgrade)
shield = entry(B, 30018)
check("the shield is measured against the off hand and isn't an upgrade", shield.yours == 15 and not shield.upgrade)
B.ex('__class = "PALADIN"')
check("a paladin (no dual wield) measures a one-hander against the main hand", entry(B, 30015).yours == 24
      and not entry(B, 30015).upgrade)
B.ex('__class = "WARRIOR"')
check("where it sits", entry(B, 30010).where[1].holder == "Epu Bank")

B.ex('__ns.SetBankGearUpgradesOnly(true)')
check("Upgrades only drops the shield", sorted(int(x) for x in gear(B).split(",")) == [30010, 30013, 30015, 30016])
B.ex('__ns.SetBankGearUpgradesOnly(false)')

# --- Request when it can't be pulled -----------------------------------------------------
check("with the guild bank closed, the button is Request", entry(B, 30010).action == "request")
B.ex('__log = {}; __ns.TakeBankGear(30010)')
rid = B.ev('(function() for id, r in pairs(__ns.G().requests) do if r.item == 30010 then return id end end end)()')
check("Request files a bank request for one",
      rid is not None and B.ev('__ns.G().requests["%s"].qty' % rid) == 1
      and B.ev('__ns.G().requests["%s"].status' % rid) == "pending"
      and B.ev('__ns.G().requests["%s"].note' % rid) == "Bank gear")
check("and the button turns to Requested", entry(B, 30010).action == "requested")
B.ex('__log = {}; __ns.TakeBankGear(30010)')
check("pressing Requested makes no second request", "already asked" in B.ev(LOG)
      and B.ev('(function() local n = 0 for _, r in pairs(__ns.G().requests) do if r.item == 30010 then n = n + 1 end end return n end)()') == 1)
tick(3)
tick_until(lambda: A.ev('__ns.G().requests["%s"] ~= nil' % rid))
check("the bank managers get the request", A.ev('__ns.G().requests["%s"].who' % rid) == "Tyler Baker")

# --- Pull at the open guild bank ---------------------------------------------------------
B.ex('''__gb = { {{30018, 1}}, {} }
GetGuildBankTabInfo = function(tab) return "Gear" .. tab, "icon", true, true, 5, 5 end''')
B.ex('__fire("GUILDBANKFRAME_OPENED")')
tick(4)
check("at the open guild bank, with withdrawals left, the shield gets Pull", entry(B, 30018).action == "pull")
B.ex('__log = {}; __ns.TakeBankGear(30018)')
for _ in range(10):
    B.ex('__advance(0.5)')
check("Pull takes it into Tyler's bags (got %s)" % B.ev(BAG % 30018), B.ev(BAG % 30018) == 1)
check("and says so", "Took" in B.ev(LOG))
B.ex('__fire("GUILDBANKFRAME_CLOSED")')

B.ex('__log = {}; __ns.TakeBankGear(30012)')
check("an item that doesn't fit can't be taken", "doesn't fit" in B.ev(LOG))

# --- Window and entry points -------------------------------------------------------------
B.ex('SlashCmdList.EPUGUILD("bankgear")')
check("/epu bankgear opens the window", B.ev('EPUGuildBankGear ~= nil and EPUGuildBankGear:IsShown()') == True)
check("the window lists the chest with its upgrade hint", B.ev('''(function()
  for _, t in ipairs(EPUGuildBankGear.texts) do if t:find("Upgrade over your Test Item 30020", 1, true) then return true end end
  return false
end)()''') == True)
check("and says what's still loading", B.ev('''(function()
  for _, t in ipairs(EPUGuildBankGear.texts) do if t:find("still loading", 1, true) then return true end end
  return false
end)()''') == True)
check("each item has its button", B.ev('#EPUGuildBankGear.buttons') == len(gear(B).split(",")))
made = B.ev('EPUGuildBankGear.pool:Made()')
for _ in range(3):
    B.ex('EPUGuildBankGear:Refresh()')
check("redrawing reuses its widgets", B.ev('EPUGuildBankGear.pool:Made()') == made)
B.ex('EPUGuildBankGear.toggle:GetScript("OnClick")(EPUGuildBankGear.toggle)')
check("the Upgrades only button filters the window", B.ev('__ns.BankGearUpgradesOnly()') == True
      and B.ev('#EPUGuildBankGear.buttons') == 4 and B.ev('EPUGuildBankGear.toggle.text:GetText()') == "Show all")
B.ex('EPUGuildBankGear.toggle:GetScript("OnClick")(EPUGuildBankGear.toggle)')
B.ex('EPUGuildBankGear:Hide()')

B.ex('__ns.UI:Show(); __ns.UI:SetView("bank"); __ns.UI:Refresh()')
check("the main window's Bank page has a Gear for you button", B.ev('__ns.UI.bankGearBtn ~= nil and __ns.UI.bankGearBtn:IsShown()') == True)
B.ex('__ns.UI.bankGearBtn:GetScript("OnClick")(__ns.UI.bankGearBtn)')
check("which opens the window", B.ev('EPUGuildBankGear:IsShown()') == True)
fits_bar = B.ev('(function() local b = __ns.UI.bars.bank return b.leftX + b.rightX end)()')
check("the Bank toolbar still fits the smallest window (%s)" % fits_bar, fits_bar <= 480)
B.ex('EPUGuildBankGear:Hide()')

B.ex('''__ns.UI.nav.membertools:Click()
for _, r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key == "bankgear" then r:GetScript("OnClick")(r) end end''')
check("the Bank gear for you tile in Member tools opens it too", B.ev('EPUGuildBankGear:IsShown()') == True)

check('no addon runtime errors', all((c.ev('__errors') or 0) == 0 for c in clients.values()))
sys.exit(1 if check.failed else 0)

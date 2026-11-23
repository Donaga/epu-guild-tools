"""Needed mats: a crafter's list of materials, synced to the guild and shown on item tooltips."""
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]   # A is an officer, B a member
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)


def tooltip(c, item):
    c.ex('GameTooltip._lines = {}; __tooltipHook(GameTooltip, {id = %d})' % item)
    lines = c.ev('GameTooltip._lines')
    return [lines[i] for i in range(1, len(lines) + 1)]


def needed_line(c, item):
    hits = [l for l in tooltip(c, item) if l.startswith("Needed by: ")]
    return hits[0] if hits else None


# --- Adding: the profession comes from the crafter's shared recipes ------------------
B.ex("""
local g = __ns.G()
g.recipes["Tyler Baker"] = {t = __now, profs = {Tailoring = {rank = 75, items = {2996}}}}
g.mats["item:2996"] = {t = __now, r = {2589, 2}}
__count = {[2589] = 4, [4306] = 0}
GetItemCount = function(id) return __count[id] or 0 end
""")
B.ex('SlashCmdList.EPUGUILD("mats add " .. __link(2589) .. " 20")')
tick(3)
check('adding a material keeps it on this character with its profession', B.ev("""
(function()
  local e = __ns.cdb.neededMats.items[2589]
  return e and e.q == 20 and e.got == 0 and e.p == "Tailoring" and e.last == 4
end)()
"""))
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"] ~= nil'))
check('the list reaches guildmates', A.ev("""
(function()
  local r = __ns.G().neededMats["Tyler Baker"]
  return r and r.i[2589] and r.i[2589].n == 20 and r.i[2589].p == "Tailoring"
end)()
"""))
check('guildmates see who needs it on the tooltip', needed_line(A, 2589) == "Needed by: |cff4ade80Tyler|r (x20)")
check('the crafter sees their own entry as "you"', needed_line(B, 2589) == "Needed by: you (x20)")
check('items nobody needs get no line', needed_line(A, 4306) is None)

B.ex('SlashCmdList.EPUGUILD("mats [Silk Cloth]")')
tick(3)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[4306] ~= nil'))
check('an amount is optional ("/epu mats [item]" adds too)', needed_line(A, 4306) == "Needed by: |cff4ade80Tyler|r")

A.ex('SlashCmdList.EPUGUILD("tooltips")')
check('the tooltip setting hides the line', needed_line(A, 2589) is None)
A.ex('SlashCmdList.EPUGUILD("tooltips")')

# --- Progress: what arrives in the bags counts, crafting with it doesn't undo it -----
tick(12)   # bag counting starts 10 seconds after login
B.ex('__count[2589] = 9; __fire("BAG_UPDATE_DELAYED")')
tick(2)
check('gaining 5 leaves 15 to go', B.ev('__ns.MyNeededMats()[1].need') == 15 and B.ev('__ns.MyNeededMats()[1].got') == 5)
B.ex('__count[2589] = 1; __fire("BAG_UPDATE_DELAYED")')
tick(2)
check('using some for crafting does not undo the progress', B.ev('__ns.MyNeededMats()[1].need') == 15)
B.ex('BankFrame = NewMock(); BankFrame:Show(); __count[2589] = 40; __fire("BAG_UPDATE_DELAYED")')
tick(2)
check('taking your own stock out of the bank does not count', B.ev('__ns.MyNeededMats()[1].need') == 15)
B.ex('BankFrame:Hide()')
tick(20)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[2589].n') == 15)
check('guildmates see the new amount', needed_line(A, 2589) == "Needed by: |cff4ade80Tyler|r (x15)")
B.ex('__count[2589] = 55; __fire("BAG_UPDATE_DELAYED")')
tick(6)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[2589] == nil'))
check('getting the full amount takes it off the list everywhere',
      B.ev('__ns.cdb.neededMats.items[2589]') is None and needed_line(A, 2589) is None)

# --- Who may change a list ----------------------------------------------------------
B.ex('__ns.AddNeededMat(2589, 10)')
tick(3)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[2589] ~= nil'))
B.ex("""
__ns.Send("D", {neededMats = {["Chris Stone"] = {who = "Chris Stone", t = __now + 10, i = {[2996] = {n = 5}}}}})
__ns.Send("D", {neededMats = {["Tyler Baker"] = {who = "Tyler Baker", t = __now + 20, i = {[2996] = {n = -1}}}}})
local many = {}
for id = 30000, 30041 do many[id] = {n = 1} end
__ns.Send("D", {neededMats = {["Tyler Baker"] = {who = "Tyler Baker", t = __now + 30, i = many}}})
__ns.Send("D", {neededMats = {["Tyler Baker"] = {who = "Tyler Baker", t = __now + 40, i = {[2996] = {n = 1, p = "|cffff0000Bad"}}}}})
""")
tick(4)
check('members cannot publish a list for someone else', A.ev('__ns.G().neededMats["Chris Stone"]') is None)
check('bad amounts, oversize lists and odd text are rejected',
      A.ev('__ns.G().neededMats["Tyler Baker"].i[2589] ~= nil and __ns.G().neededMats["Tyler Baker"].i[2996] == nil'))

B.ex('for id = 30000, 30039 do __ns.AddNeededMat(id) end')
check('your own list stops at 40 items', B.ev('#__ns.MyNeededMats()') == 40)
B.ex('SlashCmdList.EPUGUILD("mats clear")')
B.ex('__ns.AddNeededMat(2589, 10); __ns.AddNeededMat(4306)')
tick(4)

# --- Officers can clear entries, and the owner's next publish doesn't bring them back --
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[4306] ~= nil'))
A.ex('__ns.ClearNeededMat("Tyler Baker", 4306)')
tick(4)
tick_until(lambda: B.ev('__ns.cdb.neededMats.items[4306] == nil'))
check("an officer's clear reaches the owner's own list", B.ev('__ns.cdb.neededMats.items[4306]') is None
      and B.ev('__ns.cdb.neededMats.items[2589] ~= nil'))
check('the owner is told who cleared it',
      B.ev('(function() for _, l in ipairs(__log) do if l:find("Chris Baker cleared", 1, true) then return true end end end)()') is True)
B.ex('__ns.AddNeededMat(2996, 3)')
tick(4)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[2996] ~= nil'))
check("the owner's next change keeps the officer's clear",
      A.ev('__ns.G().neededMats["Tyler Baker"].i[4306]') is None and needed_line(A, 4306) is None)
B.ex('__ns.ClearNeededMat("Chris Baker", 2589)')
check('members cannot clear a guildmate', B.ev(
    '(function() for _, l in ipairs(__log) do if l:find("Only officers can clear", 1, true) then return true end end end)()') is True)

# --- A guildmate who logs in later gets the list from the officer -------------------
P = Client("Pip Baker"); clients[P.name] = P
P.ex('__now = ' + str(A.ev('__now')))
tick(40)
tick_until(lambda: P.ev('__ns.G().neededMats ~= nil and __ns.G().neededMats["Tyler Baker"] ~= nil'), timeout=120)
check('a guildmate who logs in later sees it after syncing', needed_line(P, 2589) == "Needed by: |cff4ade80Tyler|r (x10)")

# --- Several crafters: online first, your own entry first, "+N more" after three ------
A.ex("""
local s = __ns.G().neededMats
for _, who in ipairs({"Chris Stone", "Newbie Stone", "Epu Bank"}) do
  s[who] = {who = who, t = __now, i = {[2589] = {n = 2}}}
end
__rosterExtra["Newbie Stone"] = {20, nil, nil, nil, false}
__fire("GUILD_ROSTER_UPDATE")
""")
line = needed_line(A, 2589)
check('a long list stays one short line', line is not None and line.endswith(", +1 more") and line.count(",") == 3)
check('offline crafters are not shown in green', "|cff4ade80Newbie" not in (line or ""))

# --- Stale lists and people who left ---------------------------------------------------
A.ex('__ns.G().neededMats["Chris Stone"].t = __now - 31 * 86400')
check('a list nobody has refreshed for 30 days is hidden',
      not any(e for e in A.ev('(function() local o = {} for _, e in ipairs(__ns.NeededBy(2589)) do o[#o+1] = e.who end return table.concat(o, ",") end)()').split(",") if e == "Chris Stone"))
A.ex('__ns.G().neededMats["Epu Bank"].t = __now; __ns.roster["Epu Bank"] = nil')
check('members who left the guild are not listed',
      "Epu Bank" not in A.ev('(function() local o = {} for _, e in ipairs(__ns.NeededBy(2589)) do o[#o+1] = e.who end return table.concat(o, ",") end)()'))

# --- The window ------------------------------------------------------------------------
B.ex('SlashCmdList.EPUGUILD("mats")')
check('/epu mats opens the window with your list', B.ev("""
(function()
  local w = EPUGuildNeededMats
  if not w or not w:IsShown() then return false end
  local mine, guild = false, false
  for _, t in ipairs(w.texts) do
    if t:find("Your needed mats (Tyler)", 1, true) then mine = true end
    if t == "Guild needed mats" then guild = true end
  end
  return mine and guild and #w.buttons == 2
end)()
"""))
B.ex('EPUGuildNeededMats.itemBox:SetText(__link(14047)); EPUGuildNeededMats.qtyBox:SetText("8"); EPUGuildNeededMats.addButton:Click()')
check('the Add button adds the item in the box', B.ev('__ns.cdb.neededMats.items[14047] and __ns.cdb.neededMats.items[14047].q') == 8
      and B.ev('EPUGuildNeededMats.itemBox:GetText()') == "")
B.ex('ChatFrameUtil.InsertLink(__link(2996))')
check('shift-clicking an item fills the box', B.ev('EPUGuildNeededMats.itemBox:GetText()') == B.ev('__link(2996)'))
B.ex('EPUGuildNeededMats.buttons[1]:Click()')
check('Remove takes it off your list', B.ev('#__ns.MyNeededMats()') == 2)
tick(4)

A.ex('__ns.ShowNeededMats()')
check("officers get a Clear button on guildmates' entries", A.ev('#EPUGuildNeededMats.buttons') == A.ev('#__ns.GuildNeededMats()'))
A.ex("""
for i, e in ipairs(__ns.GuildNeededMats()) do
  if e.who == "Tyler Baker" and e.id == 14047 then EPUGuildNeededMats.buttons[i]:Click() end
end
""")
tick(4)
tick_until(lambda: B.ev('__ns.cdb.neededMats.items[14047] == nil'))
check("an officer's Clear button takes it off the member's list", B.ev('__ns.cdb.neededMats.items[14047]') is None)
P.ex('__ns.ShowNeededMats()')
check("members don't get Clear buttons on others' entries", P.ev('#EPUGuildNeededMats.buttons') == 0)

A.ex('__ns.UI:Show(); __ns.UI:SetView("neededmats"); __ns.UI:Refresh()')
check('the main window has a Needed mats page listing who needs what', A.ev("""
(function()
  if __ns.UI.view ~= "neededmats" then return false end
  for _, row in ipairs(__ns.UI.rows) do
    local d = row.data
    if d and d.key == "neededmat:2589" then return d.sub:find("Needed by", 1, true) ~= nil and d.sub:find("Tyler Baker|r x10", 1, true) ~= nil end
  end
  return false
end)()
"""))
check('no addon runtime errors', all((c.ev('__errors') or 0) == 0 for c in clients.values()))
sys.exit(1 if check.failed else 0)

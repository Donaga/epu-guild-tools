"""Needed mats already in the guild bank: who needs what the bank holds, with one button.

/epu mats bank (or "In the guild bank" on the main window's Needed mats page)
lists each needed material the guild bank or a bank alt holds, how many, on
which tab, and who needs it. The button pulls it out of the open guild bank
(your own needs, within your rank's withdrawal limits; officers and bank
managers pull for a member's request), or files a bank request when it can't
be pulled right now.
"""
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]   # A is an officer, B a member
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)
LOG = 'table.concat(__log, "\\n")'
BAG = "(function() local n = 0 for _, s in pairs(__bags[0]) do if s[1] == %d then n = n + s[2] end end return n end)()"
GB = "(function() local n = 0 for _, t in pairs(__gb) do for _, s in pairs(t) do if s[1] == %d then n = n + s[2] end end end return n end)()"

for c in (A, B):
    c.ex('C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end; __bags[0] = {}')

# Tyler needs 30 Linen and some Silk; Runecloth too, which the bank doesn't hold.
B.ex('__ns.AddNeededMat(2589, 30); __ns.AddNeededMat(4306); __ns.AddNeededMat(14047, 5)')
tick(5)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"] ~= nil and __ns.G().neededMats["Tyler Baker"].i[14047] ~= nil'))

# The officer opens the guild bank: two tabs of Linen, a bank alt holds Silk.
A.ex('''__gb = { {{2589, 20}, {2589, 7}}, {{2589, 20}} }
GetGuildBankTabInfo = function(tab) return ({"Mats", "Spare"})[tab], "icon", true end''')
A.ex('__fire("GUILDBANKFRAME_OPENED")')
tick(4)
for c in (A, B):
    c.ex('__ns.G().bank["Epu Bank"] = { v = 1, money = 0, items = { [4306] = 12 } }')
tick_until(lambda: B.ev('__ns.G().bank["Guild Bank"] ~= nil and __ns.G().bank["Guild Bank"].items[2589] == 47'), timeout=60)


def entry(c, who, item):
    return c.ev('''(function()
      for _, e in ipairs(__ns.NeededMatsInBank()) do
        if e.who == "%s" and e.id == %d then return e end
      end
    end)()''' % (who, item))


e = entry(A, "Tyler Baker", 2589)
check("the officer sees Tyler's Linen is in the guild bank", e is not None and e.held == 47 and e.n == 30)
check("with its tabs, from the officer's own scan (got %s)" % A.ev('__ns.BankHoldingsText(%s)' % 'select(1, __ns.BankHoldings(2589))'),
      A.ev('__ns.BankHoldingsText((__ns.BankHoldings(2589)))') == "Guild Bank (Mats) 27, Guild Bank (Spare) 20")
check("bank alts count too", A.ev('__ns.BankHoldingsText((__ns.BankHoldings(4306)))') == "Epu Bank 12")
check("a needed mat the bank doesn't hold isn't listed", entry(A, "Tyler Baker", 14047) is None)
check("the member's client, which never saw the tabs, shows the guild bank total",
      B.ev('__ns.BankHoldingsText((__ns.BankHoldings(2589)))') == "Guild Bank 47")

# --- Members: Request when it can't be pulled -----------------------------------------
check("with the guild bank closed, the member's button is Request", entry(B, "Tyler Baker", 2589).action == "request")
B.ex('__log = {}; __ns.PullNeededMat("Tyler Baker", 2589)')
rid = B.ev('(function() for id, r in pairs(__ns.G().requests) do if r.item == 2589 and r.who == "Tyler Baker" then return id end end end)()')
check("Request files a bank request for what's still needed",
      rid is not None and B.ev('__ns.G().requests["%s"].qty' % rid) == 30 and B.ev('__ns.G().requests["%s"].status' % rid) == "pending")
check("and the button turns to Requested", entry(B, "Tyler Baker", 2589).action == "requested")
B.ex('__log = {}; __ns.PullNeededMat("Tyler Baker", 2589)')
check("pressing Requested makes no second request", "already asked" in B.ev(LOG)
      and B.ev('(function() local n = 0 for _, r in pairs(__ns.G().requests) do if r.item == 2589 then n = n + 1 end end return n end)()') == 1)
check("Silk with no amount asks for one stack, capped at what the bank holds",
      B.ev('(function() __ns.PullNeededMat("Tyler Baker", 4306) for _, r in pairs(__ns.G().requests) do if r.item == 4306 then return r.qty end end end)()') == 12)
tick(3)
tick_until(lambda: A.ev('__ns.G().requests["%s"] ~= nil' % rid))

# --- Officers: Pull for the member's request -------------------------------------------
check("the bank manager's button is Pull, with the guild bank open", entry(A, "Tyler Baker", 2589).action == "pull")
A.ex('__log = {}; __ns.PullNeededMat("Tyler Baker", 2589)')
for _ in range(10):
    A.ex('__advance(0.5)')
check("Pull approves the waiting request", A.ev('__ns.G().requests["%s"].status' % rid) == "approved")
check("and moves exactly the 30 into the officer's bags (got %s)" % A.ev(BAG % 2589), A.ev(BAG % 2589) == 30)
check("the guild bank keeps the rest", A.ev(GB % 2589) == 17)
check("the officer is pointed to Mail it", "Mail it" in A.ev(LOG) and "Tyler Baker" in A.ev(LOG))
check("no second request was made", A.ev('(function() local n = 0 for _, r in pairs(__ns.G().requests) do if r.item == 2589 then n = n + 1 end end return n end)()') == 1)

# An officer with the bank closed files an approved request in the member's name.
A.ex('__fire("GUILDBANKFRAME_CLOSED")')
B.ex('__ns.AddNeededMat(2996, 4)')
A.ex('__ns.G().bank["Epu Bank"].items[2996] = 6')
B.ex('__ns.G().bank["Epu Bank"].items[2996] = 6')
tick(5)
tick_until(lambda: A.ev('__ns.G().neededMats["Tyler Baker"].i[2996] ~= nil'))
check("with the bank closed the officer's button is Request", entry(A, "Tyler Baker", 2996).action == "request")
A.ex('__log = {}; __ns.PullNeededMat("Tyler Baker", 2996)')
check("which makes an approved request for the member, ready to mail",
      A.ev('(function() for _, r in pairs(__ns.G().requests) do if r.item == 2996 and r.who == "Tyler Baker" then return r.status == "approved" and r.qty == 4 end end return false end)()') == True
      and "Mail it" in A.ev(LOG))

# --- Members: Pull their own needs straight out of the guild bank ----------------------
B.ex('__ns.AddNeededMat(30001, 15)')
B.ex('''__gb = { {{30001, 10}, {30001, 10}}, {} }
GetGuildBankTabInfo = function(tab) return "Tab" .. tab, "icon", true, true, 5, 5 end''')
B.ex('__fire("GUILDBANKFRAME_OPENED")')
tick(4)
check("a member at the open guild bank, with withdrawals left, gets Pull", entry(B, "Tyler Baker", 30001).action == "pull")
B.ex('__log = {}; __ns.PullNeededMat("Tyler Baker", 30001)')
for _ in range(10):
    B.ex('__advance(0.5)')
check("Pull takes what's needed into their bags (got %s)" % B.ev(BAG % 30001), B.ev(BAG % 30001) == 15 and B.ev(GB % 30001) == 5)
check("and says so", "Took" in B.ev(LOG) and "x15" in B.ev(LOG))
check("taking it from the guild bank counts toward the needed mats list",
      (B.ex('__count = {[30001] = 15}; GetItemCount = function(id) return (__count and __count[id]) or 0 end') or True)
      and B.ev('(function() __ns.cdb.neededMats.items[30001].last = 0; __ns.TrackNeededMats(); return __ns.cdb.neededMats.items[30001] == nil end)()') == True)

B.ex('__ns.AddNeededMat(30002, 5); __gb[1][3] = {30002, 8}; __ns.ScanGuildBank()')
B.ex('GetGuildBankTabInfo = function(tab) return "Tab" .. tab, "icon", true, true, 0, 0 end')
check("a rank with no withdrawals on that tab gets Request instead", entry(B, "Tyler Baker", 30002).action == "request")

# --- Who gets a button ------------------------------------------------------------------
A.ex('__ns.AddNeededMat(4306, 3)')
tick(5)
tick_until(lambda: B.ev('__ns.G().neededMats["Chris Baker"] ~= nil'))
check("members get no button on a guildmate's needs", entry(B, "Chris Baker", 4306) is not None and entry(B, "Chris Baker", 4306).action is None)
B.ex('__log = {}; __ns.PullNeededMat("Chris Baker", 4306)')
check("and can't pull or request for them", "Only officers and bank managers" in B.ev(LOG))

# --- Window and entry points -------------------------------------------------------------
B.ex('SlashCmdList.EPUGUILD("mats bank")')
check("/epu mats bank opens the window", B.ev('EPUGuildNeededMatsBank ~= nil and EPUGuildNeededMatsBank:IsShown()') == True)
check("the window lists each match with where it sits", B.ev('''(function()
  for _, t in ipairs(EPUGuildNeededMatsBank.texts) do if t:find("In the bank: Epu Bank 12", 1, true) then return true end end
  return false
end)()''') == True)
check("own needs get a button, guildmates' don't (member)", B.ev('''(function()
  for _, b in ipairs(EPUGuildNeededMatsBank.buttons) do if b.who ~= "Tyler Baker" then return false end end
  return #EPUGuildNeededMatsBank.buttons > 0
end)()''') == True)
check('"/epu mats" still opens your own list', (B.ex('SlashCmdList.EPUGUILD("mats")') or True) and B.ev('EPUGuildNeededMats:IsShown()') == True)

A.ex('__ns.UI:Show(); __ns.UI:SetView("neededmats"); __ns.UI:Refresh()')
check("the main window's Needed mats page has an In the guild bank button", A.ev('__ns.UI.neededBankBtn ~= nil and __ns.UI.neededBankBtn:IsShown()') == True)
A.ex('if EPUGuildNeededMatsBank then EPUGuildNeededMatsBank:Hide() end')
A.ex('__ns.UI.neededBankBtn:GetScript("OnClick")(__ns.UI.neededBankBtn)')
check("which opens the window", A.ev('EPUGuildNeededMatsBank:IsShown()') == True)
fits = A.ev('(function() local b = __ns.UI.bars and __ns.UI.bars.neededmats if b then return b.leftX + b.rightX end return 0 end)()')
check("the Needed mats toolbar still fits the smallest window (%s)" % fits, fits <= 480)

check('no addon runtime errors', all((c.ev('__errors') or 0) == 0 for c in clients.values()))
sys.exit(1 if check.failed else 0)

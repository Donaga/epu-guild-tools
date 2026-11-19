"""Pull for request: take exactly what an approved request needs out of the guild bank.

With the guild bank open, an officer clicks Pull for request and EPU moves
the remaining quantity into their bags (whole stacks where they fit, one
split for the rest), one move at a time, then Mail it sends it.
"""
import sys
from simcore import *

A = Client("Chris Baker")
A.ex('__advance(60)')
A.ex('''C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
__bags[0] = {}
__gb = { {{2589, 20}, {2589, 7}, {4306, 20}}, {{2589, 20}} }
__ns.G().requests.r1 = {who = "Tyler Baker", item = 2589, qty = 30, delivered = 3, status = "approved", t = __now, u = __now}
__ns.G().requests.r2 = {who = "Tyler Baker", item = 4306, qty = 5, status = "pending", t = __now, u = __now}
__ns.G().requests.r3 = {who = "Tyler Baker", item = 14047, qty = 5, status = "approved", t = __now, u = __now}''')
BAG = "(function() local n = 0 for _, s in pairs(__bags[0]) do if s[1] == %d then n = n + s[2] end end return n end)()"
GB = "(function() local n = 0 for _, t in pairs(__gb) do for _, s in pairs(t) do if s[1] == %d then n = n + s[2] end end end return n end)()"
LOG = 'table.concat(__log, "\\n")'

A.ex('__log = {}; __ns.PullForRequest("r1")')
check("needs the guild bank open", "Open the guild bank first" in A.ev(LOG))

A.ex('__fire("GUILDBANKFRAME_OPENED")'); A.ex('__advance(3)')
check("guild bank is open", A.ev('__ns.GuildBankIsOpen()') == True)
steps = A.ev('(function() local s, got, have = __ns.PlanGuildBankPull(2589, 27); return #s .. ":" .. got .. ":" .. have end)()')
check("27 Linen plans as one whole stack and one split (got %s)" % steps, steps == "2:27:47")

A.ex('__log = {}; __ns.PullForRequest("r1")')
for _ in range(10): A.ex('__advance(0.5)')
check("exactly the 27 still owed are in the bags (got %s)" % A.ev(BAG % 2589), A.ev(BAG % 2589) == 27)
check("the guild bank keeps the rest", A.ev(GB % 2589) == 20)
check("the officer is pointed to Mail it", "Mail it" in A.ev(LOG) and "x27" in A.ev(LOG))
check("pulling doesn't mark the request filled", A.ev('__ns.G().requests.r1.status') == "approved")

A.ex('__log = {}; __ns.PullForRequest("r2")')
check("a pending request can't be pulled", "Approve the request" in A.ev(LOG))
A.ex('__log = {}; __ns.PullForRequest("r3")')
check("an item the bank doesn't have is reported", "has no" in A.ev(LOG) and A.ev(BAG % 14047) == 0)

# Only part of it is in the guild bank: take what there is and say so.
A.ex('__ns.G().requests.r4 = {who = "Tyler Baker", item = 4306, qty = 25, status = "approved", t = __now, u = __now}')
A.ex('__log = {}; __ns.PullForRequest("r4")')
for _ in range(10): A.ex('__advance(0.5)')
check("a short guild bank gives what it has", A.ev(BAG % 4306) == 20 and "20 of 25" in A.ev(LOG))

# Withdrawal limits: a tab with none left isn't used.
A.ex('__gb[1][4] = {14047, 10}; GetGuildBankTabInfo = function(tab) return "Tab" .. tab, "icon", true, true, 1, 0 end')
A.ex('__log = {}; __ns.PullForRequest("r3")')
check("no withdrawals left is explained", "no guild bank withdrawals left" in A.ev(LOG) and A.ev(BAG % 14047) == 0)

# Not enough bag space: nothing moves.
A.ex('GetGuildBankTabInfo = function(tab) return "Tab" .. tab, "icon", true end')
A.ex('for i = 1, 16 do __bags[0][i] = __bags[0][i] or {6948, 1} end')
A.ex('__ns.G().requests.r5 = {who = "Tyler Baker", item = 2589, qty = 5, status = "approved", t = __now, u = __now}')
A.ex('__log = {}; __ns.PullForRequest("r5")')
check("full bags stop it before anything moves", "empty bag slot" in A.ev(LOG) and A.ev(GB % 2589) == 20)

# Members can't pull.
M = Client("Tyler Baker")
M.ex('__advance(60); __ns.G().requests.r1 = {who = "Tyler Baker", item = 2589, qty = 5, status = "approved", t = __now, u = __now}')
M.ex('__fire("GUILDBANKFRAME_OPENED"); __log = {}; __ns.PullForRequest("r1")')
check("members can't pull for requests", "Only officers and bank managers" in M.ev(LOG))

check("no runtime errors", (A.ev("__errors") or 0) == 0 and (M.ev("__errors") or 0) == 0)
sys.exit(1 if check.failed else 0)

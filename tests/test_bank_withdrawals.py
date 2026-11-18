"""Taking a requested item out of the real guild bank fills the request.

When a member with an approved request withdraws that item from the guild
bank, the officer's addon reads the withdrawal log and credits the request,
the same way mailing it would. Each withdrawal is credited once, only after
the request was made, and never for bank characters or officers taking stock
out for someone else.
"""
import sys
from simcore import *

for n in ["Chris Baker", "Tyler Baker", "Epu Bank"]:
    clients[n] = Client(n)
tick(20)
A, B, C = clients["Chris Baker"], clients["Tyler Baker"], clients["Epu Bank"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B, C)), timeout=90)

C.ex('__bags[0] = {{2589, 20}, {4306, 20}}; __money = 1000')
C.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(8)
tick_until(lambda: A.ev('__ns.G().bank["Epu Bank"] ~= nil') and B.ev('__ns.G().bank["Epu Bank"] ~= nil'), timeout=30)

# An old withdrawal of Linen is already in the log before Tyler asks for any.
A.ex('__gblog[1] = {{"Tyler Baker", 2589, 4, 6, "withdraw"}}')
A.ex('__gblog[2] = {}')

B.ex('SlashCmdList.EPUGUILD("request 2589 10")'); tick(4)
B.ex('SlashCmdList.EPUGUILD("request 4306 3")'); tick(4)
RID = "(function() for id, r in pairs(__ns.G().requests) do if r.who == 'Tyler Baker' and r.item == %d then return id end end end)()"
lin, silk = A.ev(RID % 2589), A.ev(RID % 4306)
check("officer has both requests", lin is not None and silk is not None)
A.ex('__ns.EditRequest("%s", {status = "approved"}); __ns.EditRequest("%s", {status = "approved"})' % (lin, silk)); tick(4)
FIELD = '__ns.G().requests["%s"].%s'
check("requests approved", A.ev(FIELD % (lin, "status")) == "approved" and B.ev(FIELD % (lin, "status")) == "approved")

def open_bank(client):
    client.ex('__log = {}; __fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); tick(4)
    client.ex('__fire("GUILDBANKFRAME_CLOSED")')

open_bank(A)
check("a withdrawal from before the request doesn't count", (A.ev(FIELD % (lin, "delivered")) or 0) == 0)

# Tyler takes 6 Linen now, Epu Bank moves stock out, and Chris takes Silk for someone else.
A.ex('table.insert(__gblog[1], {"Tyler Baker", 2589, 6, 0, "withdraw"})')
A.ex('table.insert(__gblog[1], {"Epu Bank", 2589, 20, 0, "withdraw"})')
A.ex('table.insert(__gblog[2], {"Chris Baker", 4306, 3, 0, "withdraw"})')
open_bank(A)
check("Tyler's withdrawal is credited to his request (got %s)" % A.ev(FIELD % (lin, "delivered")), A.ev(FIELD % (lin, "delivered")) == 6)
check("request stays approved with 4 remaining", A.ev(FIELD % (lin, "status")) == "approved"
      and A.ev('__ns.Remaining(__ns.G().requests["%s"])' % lin) == 4)
check("the officer is told", "Tyler Baker took" in A.ev('table.concat(__log, "\\n")'))
check("the officer's own withdrawal doesn't fill Tyler's Silk", (A.ev(FIELD % (silk, "delivered")) or 0) == 0)
tick(4)
check("Tyler sees the delivery", B.ev(FIELD % (lin, "delivered")) == 6)

open_bank(A)
check("reopening the bank doesn't credit it again", A.ev(FIELD % (lin, "delivered")) == 6)

# A second, identical withdrawal later still counts, and completes the request.
A.ex('__now = __now + 7200; table.insert(__gblog[1], {"Tyler Baker", 2589, 6, 0, "withdraw"})')
open_bank(A)
check("the rest fills the request", A.ev(FIELD % (lin, "status")) == "filled" and A.ev(FIELD % (lin, "delivered")) == 10)
tick(4)
check("Tyler sees it filled", B.ev(FIELD % (lin, "status")) == "filled")

# Another bank-trusted client reading the same log after the officer's sync adds nothing.
check("the other client has the officer's credits", C.ev(FIELD % (lin, "delivered")) == 10)
C.ex('__gblog = { {{"Tyler Baker", 2589, 4, 8, "withdraw"}, {"Tyler Baker", 2589, 6, 2, "withdraw"}, {"Tyler Baker", 2589, 6, 0, "withdraw"}}, {} }')
open_bank(C)
check("another reader of the same log credits nothing new", C.ev(FIELD % (lin, "delivered")) == 10 and (C.ev(FIELD % (silk, "delivered")) or 0) == 0)

# An alt of Tyler's taking it counts for him; a stranger's doesn't.
A.ex('__ns.altIndex["Pip Baker"] = {main = "Tyler Baker", chars = {"Tyler Baker", "Pip Baker"}, t = 1}; __ns.altIndex["Tyler Baker"] = __ns.altIndex["Pip Baker"]')
A.ex('table.insert(__gblog[2], {"Pip Baker", 4306, 2, 0, "withdraw"}); table.insert(__gblog[2], {"Chris Stone", 4306, 1, 0, "withdraw"})')
open_bank(A)
check("an alt's withdrawal counts for its main (got %s)" % A.ev(FIELD % (silk, "delivered")), A.ev(FIELD % (silk, "delivered")) == 2)

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

"""Guild bank deposits that aged out of the donation list aren't logged again.

EPU keeps the newest 500 donations. A quiet guild bank tab's log still shows
its last deposits, so once one of them was pruned it would match nothing and
be logged (and thanked on Discord) a second time. It mustn't be.
"""
import sys
from simcore import *

A = Client("Chris Baker")
A.ex('__advance(60)')
GB_FROM = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.to == 'Guild Bank' and d.who == '%s' then n=n+1 end end return n end)()"
COUNT = "(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()"

def open_bank():
    A.ex('__fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); A.ex('__advance(3)'); A.ex('__fire("GUILDBANKFRAME_CLOSED")')

# Tyler deposits Linen 10 days ago; the officer logs it.
A.ex('__gblog[1] = {{"Tyler Baker", 2589, 20, 240}}')
open_bank()
check("the deposit is logged once", A.ev(GB_FROM % "Tyler Baker") == 1)

# 500 newer mail donations push it out of the list.
A.ex('for i = 1, 500 do __ns.G().donations["m" .. i] = {t = __now - 86400 * 5 + i, who = "Chris Stone", item = 4306, n = 1, money = 0, to = "Epu Bank"} end')
A.ex('__ns.Prune(__ns.G())')
check("pruning keeps 500 and drops the old deposit", A.ev(COUNT) == 500 and A.ev(GB_FROM % "Tyler Baker") == 0)
check("the list is full, so there's a cutoff", A.ev('__ns.DonationsAgedOutBefore(__ns.G()) ~= nil'))

# The tab is quiet, so its log still shows that deposit.
open_bank()
check("the aged-out deposit isn't logged again", A.ev(GB_FROM % "Tyler Baker") == 0)
check("nothing new is sent for it", A.ev(COUNT) == 500)

# A real new deposit still counts.
A.ex('table.insert(__gblog[1], {"Pip Baker", 2589, 5, 0})')
open_bank()
check("a new deposit is still logged", A.ev(GB_FROM % "Pip Baker") == 1)
open_bank()
check("and only once", A.ev(GB_FROM % "Pip Baker") == 1)

# Below the cap nothing is skipped: an old deposit nobody logged yet still counts.
B = Client("Chris Baker")
B.ex('__advance(60); __gblog[1] = {{"Tyler Baker", 2589, 20, 240}}')
B.ex('__ns.G().donations.x = {t = __now, who = "Chris Stone", item = 4306, n = 1, money = 0, to = "Epu Bank"}')
B.ex('__fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); B.ex('__advance(3)')
check("below the cap an old, unlogged deposit still counts", B.ev(GB_FROM % "Tyler Baker") == 1)

check("no runtime errors", (A.ev("__errors") or 0) == 0 and (B.ev("__errors") or 0) == 0)
sys.exit(1 if check.failed else 0)

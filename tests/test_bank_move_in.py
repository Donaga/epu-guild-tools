"""Moving the guild's own stock (from a bank alt) into the guild bank isn't a donation.

When the guild gets a real guild bank, the bank alt deposits everything it
holds. Those deposits must not become donation records (and so no News
pop-ups or Discord thank-yous), while members' deposits still count.
"""
import sys
from simcore import *

for n in ["Chris Baker", "Tyler Baker", "Epu Bank"]:
    clients[n] = Client(n)
tick(20)
A, B, C = clients["Chris Baker"], clients["Tyler Baker"], clients["Epu Bank"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B, C)), timeout=90)

GB_DONS = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.to == 'Guild Bank' then n=n+1 end end return n end)()"
FROM = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.who == '%s' then n=n+1 end end return n end)()"
FEED = "(function() local n=0 for _, e in pairs(__ns.G().feed) do if e.kind == 'donation' and e.who == '%s' then n=n+1 end end return n end)()"

# Epu Bank is the guild's bank alt, and its snapshot reaches the officer.
C.ex('__bags[0] = {{2589, 20}, {14047, 20}}; __money = 900000')
C.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(8)
tick_until(lambda: A.ev('__ns.G().bank["Epu Bank"] ~= nil'), timeout=30)
check("officer knows Epu Bank is a bank character", A.ev('__ns.IsBankCharacter("Epu Bank")') == True)
check("a first name alone is matched too", A.ev('__ns.IsBankCharacter(__ns.Member("Epu"))') == True)
check("members are not bank characters", A.ev('__ns.IsBankCharacter("Tyler Baker")') == False)
check("the guild bank itself is not a bank character", A.ev('__ns.IsBankCharacter("Guild Bank")') == False)
check("the bank alt counts itself", C.ev('__ns.IsBankCharacter(__ns.me)') == True)

# Guild bank opens with the bank alt's whole stock moved in, plus a real gift.
# 2589 and 14047 are on the needs list in stacks of 20, so as donations each
# would have made a News pop-up.
A.ex('SlashCmdList.EPUGUILD("need 2589 200")'); A.ex('SlashCmdList.EPUGUILD("need 14047 200")'); tick(3)
A.ex('__gblog[1] = {{"Epu Bank", 2589, 20, 0}, {"Epu Bank", 14047, 20, 0}, {"Epu", 2589, 20, 0}, {"Tyler Baker", 2589, 20, 1}}')
A.ex('__gblog[2] = {{"Epu Bank", 4306, 8, 0}}')
A.ex('__gbmoneylog = {{"Epu Bank", 900000, 0}, {"Tyler Baker", 60000, 1}}')
A.ex('__log = {}; __fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); tick(6)
check("only the member's 2 deposits are donations (got %s)" % A.ev(GB_DONS), A.ev(GB_DONS) == 2)
check("nothing recorded for the bank alt", A.ev(FROM % "Epu Bank") == 0 and A.ev(FROM % "Epu") == 0)
check("member's item and gold deposits still count", A.ev(FROM % "Tyler Baker") == 2)
check("no News pop-up for the bank alt's move-in", A.ev(FEED % "Epu Bank") == 0)
check("the member still gets a News shout-out", A.ev(FEED % "Tyler Baker") >= 1)
log = A.ev('table.concat(__log, "\\n")')
check("officer is told 5 deposits were the guild's own stock", "5 deposits by bank characters" in log)
A.ex('__log = {}; __now = __now + 600; __fire("GUILDBANKLOG_UPDATE")'); tick(4)
check("rescan adds nothing and doesn't repeat the note", A.ev(GB_DONS) == 2 and "bank characters" not in A.ev('table.concat(__log, "\\n")'))
check("members see the same records", B.ev(GB_DONS) == 2 and B.ev(FROM % "Epu Bank") == 0)
A.ex('__fire("GUILDBANKFRAME_CLOSED")')

# Once emptied, the bank alt is retired; its old log lines still aren't donations.
C.ex('SlashCmdList.EPUGUILD("bankalt off")'); tick(6)
tick_until(lambda: A.ev('__ns.G().bank["Epu Bank"].retired') == True, timeout=30)
check("a retired bank alt is still a bank character", A.ev('__ns.IsBankCharacter("Epu Bank")') == True)
A.ex('__gblog[1][5] = {"Epu Bank", 2589, 20, 0}; __fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")'); tick(4)
check("retired bank alt's deposit isn't a donation", A.ev(FROM % "Epu Bank") == 0 and A.ev(GB_DONS) == 2)
A.ex('__fire("GUILDBANKFRAME_CLOSED")')
C.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(6)

# Mail between bank characters is the guild's stock moving, not a gift.
C.ex('__ns.G().bank["Pip Baker"] = {v = 1, items = {}, money = 0, retired = true}')
C.ex('__inbox = {}; __inbox[1] = {sender = "Pip Baker", money = 7000, items = {{2589, 20}}}; TakeInboxItem(1, 1); TakeInboxMoney(1)')
C.ex('__inbox[2] = {sender = "Tyler Baker", money = 0, items = {{4306, 3}}}; TakeInboxItem(2, 1)')
tick(6)
check("mail from another bank character isn't a donation", C.ev(FROM % "Pip Baker") == 0)
check("mail from a member still is", C.ev(FROM % "Tyler Baker") >= 3)

# Trades work the same way.
def trade(who, item, count):
    C.ex('__npc = "%s"; GetTradeTargetItemLink = function(s) if s == 1 then return __link(%d) end end;'
         ' GetTradeTargetItemInfo = function(s) if s == 1 then return "x", "tex", %d end end' % (who, item, count))
    C.ex('__fire("TRADE_ACCEPT_UPDATE"); __fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)'); tick(4)
before = C.ev(FROM % "Tyler Baker")
trade("Pip Baker", 14047, 20)
check("trade from a bank character isn't a donation", C.ev(FROM % "Pip Baker") == 0)
trade("Tyler Baker", 14047, 5)
check("trade from a member still is", C.ev(FROM % "Tyler Baker") == before + 1)

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

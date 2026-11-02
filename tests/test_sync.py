from simcore import *

for n in ["Chrisb","Tyler","Epubank"]:
    clients[n] = Client(n)
tick(20)
A, B, C = clients["Chrisb"], clients["Tyler"], clients["Epubank"]

# Officer sets needs (with real link syntax)
A.ex('SlashCmdList.EPUGUILD("need " .. __link(2589) .. " 200")')
A.ex('SlashCmdList.EPUGUILD("need 14047 100")')
tick(3)
check("member sees needs", B.ev("__ns.G().needs.list[2589]") == 200 and B.ev("__ns.G().needs.list[14047]") == 100)

# Untrusted member tries to overwrite needs
B.ex('__ns.Send("D", {needs = {v = 9999999999, list = {}}})')
tick(2)
check("untrusted needs rejected", A.ev("__ns.G().needs.list[2589]") == 200)
B.ex('SlashCmdList.EPUGUILD("need 2589 5")')
check("member blocked locally", B.ev("__ns.G().needs.list[2589]") == 200)

# Bank alt with a big inventory (forces chunked messages)
C.ex('__bags[0] = {{2589, 20}, {2589, 20}, {14047, 7}}; __money = 123456')
C.ex('for i = 1, 60 do local bag = 1 + math.floor((i-1)/16); __bags[bag] = __bags[bag] or {}; __bags[bag][((i-1)%16)+1] = {30000+i, i} end')
C.ex('local banks = {-1,5,6,7,8,9,10}; for i = 61, 150 do local bag = banks[1 + math.floor((i-61)/16)]; __bags[bag] = __bags[bag] or {}; __bags[bag][((i-61)%16)+1] = {30000+i, i} end')
C.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(8); C.ex('__fire("BANKFRAME_OPENED")')
tick(10)
check("bank count synced to member", B.ev("__ns.BankCount(2589)") == 40)
check("big snapshot synced", B.ev("__ns.BankCount(30150)") == 150)
check("bank money synced", A.ev("__ns.G().bank.Epubank.money") == 123456)

# Request flow with approval
B.ex('SlashCmdList.EPUGUILD("request " .. __link(4306) .. " 10 for tailoring; thanks|pipe")')
tick(3)
rid = A.ev("(next(__ns.G().requests))")
check("officer sees pending request", rid is not None and A.ev(f'__ns.G().requests["{rid}"].status') == "pending")
check("note escaped round trip", A.ev(f'__ns.G().requests["{rid}"].note') == "for tailoring; thanks|pipe")
# member forges self-approval
B.ex(f'local r = __ns.G().requests["{rid}"]; r.status = "approved"; r.u = r.u + 1; __ns.Send("D", {{req = {{["{rid}"] = r}}}})')
tick(3)
check("forged self-approval rejected", A.ev(f'__ns.G().requests["{rid}"].status') == "pending")
A.ex(f'__ns.SetRequestStatus("{rid}", "approved")')
tick(3)
check("member sees approved", B.ev(f'__ns.G().requests["{rid}"].status') == "approved")
check("approved request on shopping list", A.ev('(function() for _, r in ipairs(__ns.ShoppingList()) do if r.id == 4306 then return r.buy end end end)()') == 10)
A.ex('SlashCmdList.EPUGUILD("shop")')
check("Auctionator list exported", A.ev('__shopping and __shopping.name') == "EPU Guild Bank" and A.ev('#__shopping.terms') == 3)
print("   shopping terms:", [A.ev(f'__shopping.terms[{i}]') for i in range(1,4)])
# officer mails the silk to Tyler -> auto-filled
A.ex('__sendItems = {4306}; SendMail("Tyler")'); tick(3)
check("mailing approved item auto-fills", B.ev(f'__ns.G().requests["{rid}"].status') == "filled")
# reject flow
B.ex('SlashCmdList.EPUGUILD("request 2589 5")'); tick(3)
rid2 = [k for k in [A.ev("(function() for k, r in pairs(__ns.G().requests) do if r.item == 2589 then return k end end end)()")]][0]
A.ex(f'__ns.SetRequestStatus("{rid2}", "rejected", "ask in guild chat first")'); tick(3)
check("reject with reason syncs", B.ev(f'__ns.G().requests["{rid2}"].reason') == "ask in guild chat first")
# one-time goal closes itself (bank holds 7 Runecloth)
A.ex('SlashCmdList.EPUGUILD("need 14047 5 goal")'); tick(6)
check("met goal auto-closed everywhere", B.ev("__ns.G().needs.list[14047]") is None)
A.ex('SlashCmdList.EPUGUILD("need 14047 50 goal")'); tick(6)
check("unmet goal stays, critical", B.ev("__ns.G().needs.list[14047].k") == "g" and B.ev('(function() for _, n in ipairs(__ns.OpenNeeds()) do if n.id == 14047 then return n.critical end end end)()') == True)

# Mail donation from Tyler to the bank alt
C.ex('__inbox[1] = {sender = "Tyler-Forever", money = 5000, items = {{2589, 20}}}')
C.ex('TakeInboxItem(1, 1); TakeInboxMoney(1)')
C.ex('__inbox[2] = {sender = "Auction House", money = 9999, items = {{2589, 1}}}')
C.ex('TakeInboxItem(2, 1); TakeInboxMoney(2)')
tick(6)
n = A.ev("(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()")
check("2 donations logged, AH mail ignored (got %s)" % n, n == 2)

# Crafters
check("officer sees Tyler's tailoring", A.ev('__ns.G().crafters.Tyler and __ns.G().crafters.Tyler.profs.Tailoring') == 150)

# Recipe lookup: Tyler opens tailoring window, officer asks
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(2)
A.ex('SlashCmdList.EPUGUILD("who " .. __link(2996))'); tick(3)
check("who-crafts answered", A.ev("#__ns.whoResults.list") == 1 and A.ev("__ns.whoResults.list[1].who") == "Tyler")
A.ex('SlashCmdList.EPUGUILD("who bolt of linen")'); tick(3)
check("who-crafts by name", A.ev("#__ns.whoResults.list") == 1)

# Late joiner with empty data gets everything
clients["Newbie"] = D = Client("Newbie")
tick(30)
check("late joiner got needs", D.ev("__ns.G().needs.list[2589]") == 200)
check("late joiner got big bank", D.ev("__ns.BankCount(30150)") == 150)
check("late joiner got donations", D.ev("(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()") == 2)
check("late joiner got crafters", D.ev("__ns.G().crafters.Tyler ~= nil"))

# Post needs + UI smoke test on every tab
A.ex('SlashCmdList.EPUGUILD("post")')
for c in (A, D):
    c.ex('__ns.UI:Show()')
    for tab in ["Needs","Shopping","Bank","Requests","Donations","Crafters"]:
        c.ex(f'__ns.UI:SetTab("{tab}")')
    c.ex('__ns.UI.itemBox:SetText("linen"); __ns.UI:SetTab("Bank"); __ns.UI.itemBox:SetText("linen"); __ns.UI:Refresh()')
check("UI rendered bank rows", A.ev("#__ns.UI.rows") >= 1)
errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
log = A.ev("__log"); print("--- officer chat log ---")
for i in range(1, len(log)+1): print("  ", log[i])
sys.exit(1 if check.failed else 0)

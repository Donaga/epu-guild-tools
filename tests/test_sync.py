from simcore import *

for n in ["Chris Baker","Tyler Baker","Epu Bank"]:
    clients[n] = Client(n)
tick(20)
A, B, C = clients["Chris Baker"], clients["Tyler Baker"], clients["Epu Bank"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B, C)), timeout=90)

# Officer sets needs (with real link syntax)
A.ex('SlashCmdList.EPUGUILD("need " .. __link(2589) .. " 200")')
A.ex('SlashCmdList.EPUGUILD("need 14047 100")')
tick(3)
tick_until(lambda: B.ev('__ns.G().needs.list[2589]') == 200 and B.ev('__ns.G().needs.list[14047]') == 100)
check("member sees needs", B.ev("__ns.G().needs.list[2589]") == 200 and B.ev("__ns.G().needs.list[14047]") == 100)

# Untrusted member tries to overwrite needs
B.ex('__ns.Send("D", {needs = {v = 9999999999, list = {}}})')
tick(2)
check("untrusted needs rejected", A.ev("__ns.G().needs.list[2589]") == 200)
B.ex('SlashCmdList.EPUGUILD("need 2589 5")')
check("member blocked locally", B.ev("__ns.G().needs.list[2589]") == 200)

# Bank alt with a big inventory (forces chunked messages)
C.ex('__ns.G().bank["Epu Bank"]={v=0,items={},seen={[4306]=true,[2996]=true}}') # Previously stocked, currently sold out.
C.ex('__bags[0] = {{2589, 20}, {2589, 20}, {14047, 7}}; __money = 123456')
C.ex('for i = 1, 60 do local bag = 1 + math.floor((i-1)/16); __bags[bag] = __bags[bag] or {}; __bags[bag][((i-1)%16)+1] = {30000+i, i} end')
C.ex('local banks = {-1,5,6,7,8,9,10}; for i = 61, 150 do local bag = banks[1 + math.floor((i-61)/16)]; __bags[bag] = __bags[bag] or {}; __bags[bag][((i-61)%16)+1] = {30000+i, i} end')
C.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(8); C.ex('__fire("BANKFRAME_OPENED")')
tick(10)
tick_until(lambda: B.ev('__ns.BankCount(30150)') == 150, timeout=60)
check("bank count synced to member", B.ev("__ns.BankCount(2589)") == 40)
check("big snapshot synced", B.ev("__ns.BankCount(30150)") == 150)
check("bank money synced", A.ev('__ns.G().bank["Epu Bank"].money') == 123456)

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
A.ex('__sendCounts = {10}; __sendItems = {4306}; SendMail("Tyler")'); tick(3)
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
C.ex('__inbox[1] = {sender = "Tyler Baker", money = 5000, items = {{2589, 20}}}')
C.ex('TakeInboxItem(1, 1); TakeInboxMoney(1)')
C.ex('__inbox[2] = {sender = "Auction House", money = 9999, items = {{2589, 1}}}')
C.ex('TakeInboxItem(2, 1); TakeInboxMoney(2)')
tick(6)
n = A.ev("(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()")
check("2 donations logged, AH mail ignored (got %s)" % n, n == 2)

# Forever two-part names
check("own name is First Surname", A.ev("__ns.me") == "Chris Baker" and B.ev("__ns.me") == "Tyler Baker")
check("same first name, different trust", A.ev('__ns.IsTrusted("Chris Baker")') == True and A.ev('__ns.IsTrusted("Chris Stone")') == False)
check("unique first name resolves", A.ev('__ns.Member("tyler")') == "Tyler Baker")
check("shared first name is ambiguous", A.ev('__ns.Member("Chris")') is None)
check("realm suffix still stripped", A.ev('__ns.Short("Tyler Baker-Forever")') == "Tyler Baker")
C.ex('__inbox[3] = {sender = "Chris Stone", money = 0, items = {{4306, 2}}}; TakeInboxItem(3, 1)')
C.ex('__inbox[4] = {sender = "Chris", money = 0, items = {{4306, 9}}}; TakeInboxItem(4, 1)')
tick(6)
check("mail from Chris Stone credited to him, ambiguous 'Chris' skipped",
      A.ev("(function() local w = {} for _, d in pairs(__ns.G().donations) do if d.item == 4306 then w[#w+1] = d.who .. ':' .. d.n end end return table.concat(w, ',') end)()") == "Chris Stone:2")

# Alts: Tyler also plays Pip Baker on the same account
B.ex('local key = __ns.GuildKey(); __ns.db.accountChars[key]["Pip Baker"] = __now + 100; __ns.PublishAlts()'); tick(3)
check("a claimed alt is unverified until that character confirms", A.ev('__ns.MainOf("Pip Baker")') == "Pip Baker")
P = Client("Pip Baker"); clients[P.name] = P
P.ex('__now = ' + str(B.ev('__now')))
P.ex('__ns.RegisterMe(); __ns.db.accountId = "' + B.ev('__ns.db.accountId') + '"; __ns.db.accountChars[__ns.GuildKey()]["Tyler Baker"] = __now - 100; __ns.PublishAlts()'); tick(4)
del clients[P.name]
check("alt group synced", A.ev('__ns.MainOf("Pip Baker")') == "Tyler Baker" and A.ev('__ns.WhoLabel("Pip Baker")') == "Pip Baker (Tyler Baker)")
check("my chars main first", B.ev('table.concat(__ns.MyChars(), ",")') == "Tyler Baker,Pip Baker")
B.ex('SlashCmdList.EPUGUILD("main pip baker")'); tick(3)
check("/epu main switches main guild-wide", A.ev('__ns.MainOf("Tyler Baker")') == "Pip Baker")
B.ex('SlashCmdList.EPUGUILD("main Tyler Baker")'); tick(3)
B.ex('__ns.Send("D", {alts = {fake = {t = 9e9, main = "Chris Baker", chars = {"Chris Baker", "Chris Stone"}}}})'); tick(2)
check("can't publish a group you're not in", A.ev('__ns.MainOf("Chris Stone")') == "Chris Stone")
# Deliver-to: Tyler requests from his main, for his alt
B.ex('__ns.NewRequest(2996, 3, "for Pip", "Pip Baker")'); tick(3)
ridp = A.ev("(function() for k, r in pairs(__ns.G().requests) do if r.item == 2996 then return k end end end)()")
check("deliver-to synced", A.ev(f'__ns.G().requests["{ridp}"].to') == "Pip Baker")
A.ex(f'__ns.SetRequestStatus("{ridp}", "approved")'); tick(2)
tick_until(lambda: B.ev(f'__ns.G().requests["{ridp}"].status') == 'approved')
A.ex('__sendCounts = {3}; __sendItems = {2996}; SendMail("Tyler Baker")'); tick(3)
check("mailing the requester's main doesn't fill an alt delivery", B.ev(f'__ns.G().requests["{ridp}"].status') == "approved")
A.ex('__sendCounts = {3}; __sendItems = {2996}; SendMail("Pip Baker")'); tick(3)
tick_until(lambda: B.ev(f'__ns.G().requests["{ridp}"].status') == 'filled')
check("mailing the deliver-to character fills it", B.ev(f'__ns.G().requests["{ridp}"].status') == "filled")

# Crafters
check("officer sees Tyler's tailoring", A.ev('__ns.G().crafters["Tyler Baker"] and __ns.G().crafters["Tyler Baker"].profs.Tailoring') == 150)

# Recipe lookup: Tyler opens tailoring window, officer asks
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(2)
A.ex('SlashCmdList.EPUGUILD("who " .. __link(2996))'); tick(3)
tick_until(lambda: A.ev('#__ns.whoResults.list') == 1)
check("who-crafts answered", A.ev("#__ns.whoResults.list") == 1 and A.ev("__ns.whoResults.list[1].who") == "Tyler Baker")
A.ex('SlashCmdList.EPUGUILD("who bolt of linen")'); tick(3)
tick_until(lambda: A.ev('#__ns.whoResults.list') == 1)
check("who-crafts by name", A.ev("#__ns.whoResults.list") == 1)

# Late joiner with empty data gets everything
clients["Newbie Stone"] = D = Client("Newbie Stone")
tick(30)
tick_until(lambda: D.ev('__ns.G().crafters["Tyler Baker"] ~= nil'), timeout=90)
check("late joiner got needs", D.ev("__ns.G().needs.list[2589]") == 200)
check("late joiner got big bank", D.ev("__ns.BankCount(30150)") == 150)
check("late joiner got all donations", D.ev("(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()") == A.ev("(function() local n=0 for _ in pairs(__ns.G().donations) do n=n+1 end return n end)()") == 3)
check("late joiner got crafters", D.ev('__ns.G().crafters["Tyler Baker"] ~= nil'))

# Post needs + UI smoke test on every tab
A.ex('SlashCmdList.EPUGUILD("post")')
for c in (A, D):
    c.ex('__ns.UI:Show()')
    for tab in ["Needs","Shopping","Bank","Requests","Donations","Crafters"]:
        c.ex(f'__ns.UI:SetTab("{tab}")')
    c.ex('__ns.UI.itemBox:SetText("linen"); __ns.UI:SetTab("Bank"); __ns.UI.itemBox:SetText("linen"); __ns.UI:Refresh()')
check("UI rendered bank rows", A.ev("#__ns.UI.rows") >= 1)

# --- taint guard: never assign to Blizzard's globals or replace their functions ---
import re, glob as _glob
ours = re.compile(r"^(EPUGuild\w*|SLASH_EPUGUILD\d+|BINDING_\w*EPU\w*)$")
bad = []
for path in sorted(_glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "EPUGuild", "*.lua"))):
    src = open(path, encoding="utf-8").read()
    locals_ = set(re.findall(r"^\s*local\s+(?:function\s+)?([A-Za-z_]\w*)", src, re.M))
    for ln, line in enumerate(src.splitlines(), 1):
        m = re.match(r"^([A-Za-z_]\w*)\s*=[^=]", line)        # a top-level assignment
        if m and m.group(1) not in locals_ and not ours.match(m.group(1)):
            bad.append(f"{os.path.basename(path)}:{ln} {line.strip()[:60]}")
        if re.search(r"_G\[[^\]]+\]\s*=[^=]", line):
            bad.append(f"{os.path.basename(path)}:{ln} {line.strip()[:60]}")
check("addon never overwrites Blizzard globals (taint) %s" % (bad or ""), not bad)

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
log = A.ev("__log"); print("--- officer chat log ---")
for i in range(1, len(log)+1): print("  ", log[i])
sys.exit(1 if check.failed else 0)

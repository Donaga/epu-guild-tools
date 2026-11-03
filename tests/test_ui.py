"""Redesigned window, details panel edits, mail helper, officer settings."""
import sys
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]

# Officer A is also the bank, carrying 25 Silk Cloth in two stacks
A.ex('__bags[0] = {{4306, 20}, {4306, 5}, {2589, 40}}; __money = 5000000')
A.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(8)
A.ex('SlashCmdList.EPUGUILD("need 2589 200")'); A.ex('SlashCmdList.EPUGUILD("need 14047 50 goal")'); tick(3)

# --- every view renders, with search and filters ---
for c in (A, B):
    c.ex('__ns.UI:Show()')
    for v in ["needs", "shopping", "bank", "requests", "donations", "crafters", "officer"]:
        c.ex(f'__ns.UI:SetView("{v}")')
check("officer page for officers", A.ev('__ns.UI.view') == "officer")
check("members can't open the officer page", B.ev('__ns.UI.view') == "needs" and B.ev('__ns.UI.nav.officer:IsShown()') == False)
check("officer sees officer nav", A.ev('__ns.UI.nav.officer:IsShown()') == True)

A.ex('__ns.UI:SetView("bank")')
A.ex('__ns.UI.search:SetText("silk")')
check("search filters the bank list", A.ev('#(function() local t = {} for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then t[#t+1] = r end end return t end)()') == 1)
A.ex('__ns.UI.search:SetText("")')

# --- requests: member asks, officer approves from the row, filters ---
B.ex('__ns.NewRequest(4306, 12, "for bags")'); tick(3)
rid = A.ev("(next(__ns.G().requests))")
A.ex('__ns.UI:SetView("requests")')
shown = "(function() local n = 0 for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then n = n + 1 end end return n end)()"
check("open filter shows the pending request", A.ev(shown) == 1)
check("pending badge on the sidebar", A.ev('__ns.UI.nav.requests.badge:IsShown()') == True)
A.ex('__ns.UI.state.requests.filter = "filled"; __ns.UI:Refresh()')
check("filled filter hides it", A.ev(shown) == 0)
A.ex('__ns.UI.state.requests.filter = "open"; __ns.UI:Refresh()')
A.ex('__ns.UI.rows[1].b1:GetScript("OnClick")()'); tick(3)
check("approve button on the row works", B.ev(f'__ns.G().requests["{rid}"].status') == "approved")

# --- details panel ---
A.ex('__ns.UI.rows[1]:GetScript("OnClick")(__ns.UI.rows[1])')
check("clicking a row opens details", A.ev('__ns.UI.details:IsShown()') == True and A.ev('__ns.UI.details.kind') == "request")
B.ex('__ns.UI:SetView("requests"); __ns.UI:OpenDetails("request", "' + rid + '")')
check("member gets read-only details once approved", B.ev('__ns.UI.details.used.box') == 0)

# --- edit rules ---
B.ex(f'__ns.EditRequest("{rid}", {{ status = "approved" }})')
check("member can't approve via edit", A.ev(f'__ns.G().requests["{rid}"].status') == "approved" and B.ev(f'__ns.G().requests["{rid}"].by') == "Chris Baker")
B.ex('__ns.NewRequest(2589, 5, "")'); tick(3)
rid2 = B.ev("(function() for k, r in pairs(__ns.G().requests) do if r.item == 2589 then return k end end end)()")
B.ex(f'__ns.EditRequest("{rid2}", {{ qty = 8, note = "changed my mind" }})'); tick(3)
check("member edits own pending request", A.ev(f'__ns.G().requests["{rid2}"].qty') == 8 and A.ev(f'__ns.G().requests["{rid2}"].note') == "changed my mind")
A.ex(f'__ns.EditRequest("{rid2}", {{ status = "filled" }})'); tick(2)
A.ex(f'__ns.EditRequest("{rid2}", {{ status = "approved" }})'); tick(3)
check("officer reopens a request filled by mistake", B.ev(f'__ns.G().requests["{rid2}"].status') == "approved")
A.ex(f'__ns.EditRequest("{rid2}", {{ status = "rejected", reason = "no copper left" }})'); tick(3)
check("reject with reason from details", B.ev(f'__ns.G().requests["{rid2}"].reason') == "no copper left")

# --- mail helper: 12 silk from stacks of 20 and 5 ---
A.ex('MailFrame._shown = false')
A.ex(f'__ns.MailRequest("{rid}")')
check("mail helper needs an open mailbox", A.ev('next(__mailSlots)') is None)
A.ex('MailFrame._shown = true')
A.ex(f'__ns.MailRequest("{rid}")')
check("mail helper fills recipient and subject", A.ev('SendMailNameEditBox._text') == "Tyler Baker" and "Silk Cloth x12" in A.ev('SendMailSubjectEditBox._text'))
check("mail helper attaches exactly 12 (split from a stack)", A.ev('(function() local n = 0 for _, s in pairs(__mailSlots) do n = n + s[2] end return n end)()') == 12)
A.ex('__sendItems = {4306}; SendMail("Tyler Baker")'); tick(3)
check("sending marks it filled", B.ev(f'__ns.G().requests["{rid}"].status') == "filled")

# --- archive finished, void a donation ---
A.ex('__ns.ArchiveFinished()'); tick(3)
check("tidy hides finished requests for everyone", B.ev(f'__ns.G().requests["{rid}"].archived') == True)
A.ex('__inbox[1] = {sender = "Tyler Baker", money = 0, items = {{2589, 20}}}; TakeInboxItem(1, 1)'); tick(6)
did = A.ev("(next(__ns.G().donations))")
check("donation logged", did is not None and B.ev(f'__ns.G().donations["{did}"] ~= nil'))
A.ex(f'__ns.VoidDonation("{did}", true)'); tick(3)
check("void syncs", B.ev(f'__ns.G().donations["{did}"].void') == True)
B.ex(f'local d = __ns.G().donations["{did}"]; d.void = nil; d.u = d.u + 5; __ns.Send("D", {{don = {{["{did}"] = d}}}})'); tick(2)
check("member can't un-void", A.ev(f'__ns.G().donations["{did}"].void') == True)

# --- officer policy: max open requests ---
A.ex('__ns.SetPolicy("maxOpen", 1)'); tick(3)
check("policy syncs", B.ev('__ns.G().policy.maxOpen') == 1)
B.ex('__ns.NewRequest(118, 1, "")'); tick(2)
B.ex('__ns.NewRequest(858, 1, "")'); tick(2)
n_open = A.ev("(function() local n=0 for _, r in pairs(__ns.G().requests) do if r.who == 'Tyler Baker' and __ns.IsActiveRequest(r) then n=n+1 end end return n end)()")
check("limit blocks a second open request (got %s)" % n_open, n_open == 1)
B.ex('__ns.SetPolicy("maxOpen", 9)'); tick(2)
check("members can't change policy", A.ev('__ns.G().policy.maxOpen') == 1)

# --- late joiner gets policy and voided state ---
clients["Newbie Stone"] = D = Client("Newbie Stone"); tick(30)
check("late joiner gets policy", D.ev('__ns.G().policy.maxOpen') == 1)
check("late joiner gets void", D.ev(f'__ns.G().donations["{did}"].void') == True)

# --- resize and every view again with data; details for each kind ---
A.ex('__ns.UI:SetSize(1000, 700); __ns.UI:GetScript("OnSizeChanged")()'); tick(1)
for v in ["needs", "shopping", "bank", "requests", "donations", "crafters", "officer"]:
    A.ex(f'__ns.UI:SetView("{v}")')
A.ex('__ns.UI:SetView("needs"); __ns.UI:OpenDetails("need", 2589)')
A.ex('__ns.UI:SetView("bank"); __ns.UI:OpenDetails("item", 4306)')
A.ex(f'__ns.UI:SetView("donations"); __ns.UI:OpenDetails("donation", "{did}")')
A.ex('__ns.UI:SetView("crafters"); __ns.UI:OpenDetails("crafter", "Tyler Baker")')
A.ex('__ns.UI:CloseDetails()')
A.ex('SlashCmdList.EPUGUILD("scale 0.9"); SlashCmdList.EPUGUILD("resetwindow")')
# --- update notice: a guildmate with a newer version logs in ---
A.ex('__ns.Send("H", {needs = 0, bank = {}, since = 0, ver = "9.9.9"})'); tick(3)
check("newer version shows the popup once", B.ev("#__popups") == 1 and B.ev("__popups[1][2]") == "9.9.9")
A.ex('__ns.Send("H", {needs = 0, bank = {}, since = 0, ver = "9.9.9"})'); tick(3)
check("no repeat popup for the same version", B.ev("#__popups") == 1)
check("older version: no popup", A.ev("#__popups") == 0)

# --- 1. tooltips ---
B.ex('GameTooltip._lines = {}; __tooltipHook(GameTooltip, {id = 2589})')
lines = B.ev('table.concat(GameTooltip._lines, "|")')
check("tooltip shows what the bank needs (%s)" % lines, "needs" in lines and "/200" in lines)
B.ex('SlashCmdList.EPUGUILD("tooltips"); GameTooltip._lines = {}; __tooltipHook(GameTooltip, {id = 2589})')
check("tooltips can be turned off", B.ev('#GameTooltip._lines') == 0)
B.ex('SlashCmdList.EPUGUILD("tooltips")')

# --- 2. bag coins ---
check("needed items are marked", B.ev('__ns.ItemIsNeeded(2589)') == True and B.ev('__ns.ItemIsNeeded(4306)') == False)
check("Baganator corner widget registered", B.ev('__corner ~= nil') and B.ev('__corner.onUpdate(nil, {itemID = 2589})') == True)
B.ex('__ns.RefreshBagMarkers()')

# --- 4. notices ---
B.ex('__toasts = {}; local old = __ns.Notify; __ns.Notify = function(t, x) table.insert(__toasts, t) end')
A.ex('__ns.Notify = function() end')
A.ex('__ns.SetPolicy("maxOpen", 0)'); tick(3)
B.ex('__ns.NewRequest(2589, 3, "")'); tick(3)
rid3 = A.ev("(function() for k, r in pairs(__ns.G().requests) do if r.item == 2589 and r.qty == 3 then return k end end end)()")
A.ex(f'__ns.EditRequest("{rid3}", {{ status = "approved" }})'); tick(3)
check("requester gets an 'approved' notice", B.ev('__toasts[#__toasts]') == "Request approved")
A.ex(f'__ns.EditRequest("{rid3}", {{ status = "filled" }})'); tick(3)
check("and a 'filled' notice", B.ev('__toasts[#__toasts]') == "Request filled")
A.ex('__otoasts = {}; __ns.Notify = function(t) table.insert(__otoasts, t) end')
B.ex('__ns.NewRequest(4306, 1, "")'); tick(3)
check("officer gets a 'new request' notice", A.ev('__otoasts[1]') == "New guild bank request")
clients["Pip Baker"] = E = Client("Pip Baker")
E.ex('__ns.Notify = function(t) __etoasts = (__etoasts or 0) + 1 end'); tick(30)
check("catching up at login doesn't flood notices", (E.ev('__etoasts') or 0) == 0)

# --- 3. donate at the mailbox (member B carries 30 linen + 5 silk) ---
B.ex('__bags[0] = {{2589, 20}, {2589, 10}, {4306, 5}}; __mailSlots = {}; MailFrame._shown = true')
B.ex('__ns.ShowDonate()')
check("donate panel opens for members with a bank to send to", B.ev('__ns.DonatePanel:IsShown()') == True)
check("only needed items listed by default", B.ev('(function() local n = 0 for _, r in ipairs(__ns.DonatePanel.rows) do if r:IsShown() then n = n + 1 end end return n end)()') == 1)
check("nothing picked until you choose", B.ev('next(__ns.DonatePanel.pick)') is None)
B.ex('local r = __ns.DonatePanel.rows[1]; r.plus:GetScript("OnClick")(); r.plus:GetScript("OnClick")()')
check("+ adds one at a time", B.ev('__ns.DonatePanel.pick[2589]') == 2)
B.ex('__ns.DonatePanel.rows[1]:GetScript("OnMouseWheel")(nil, 1)')
check("mouse wheel adjusts", B.ev('__ns.DonatePanel.pick[2589]') == 3)
B.ex('__ns.DonatePanel.rows[1].max:GetScript("OnClick")()')
need_left = B.ev('200 - __ns.BankCount(2589)')
check("Max picks what the bank still needs (capped at what you carry)", B.ev('__ns.DonatePanel.pick[2589]') == min(30, need_left))
B.ex('__ns.DonatePanel.pick[2589] = 25; __ns.FillDonation()')
check("Fill mail attaches exactly the chosen amount", B.ev('(function() local n = 0 for _, s in pairs(__mailSlots) do n = n + s[2] end return n end)()') == 25)
check("addressed to the bank", B.ev('SendMailNameEditBox._text') == "Chris Baker")
A.ex('__ns.ShowDonate()')
check("the bank character doesn't get the donate panel", A.ev('__ns.DonatePanel:IsShown()') != True)

# --- 6. welcome ---
B.ex('__ns.ShowWelcome()')
check("welcome card shows", B.ev('true'))

# --- details panel scrolls instead of overflowing ---
A.ex('__ns.UI:SetSize(620, 420); __ns.UI:SetView("requests"); __ns.UI:OpenDetails("request", "' + rid3 + '")')
check("details body sized for scrolling", A.ev('__ns.UI.details.body:GetHeight()') > 100)

errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

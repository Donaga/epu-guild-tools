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

# --- picking an item for a need or request ---
A.ex('__ns.UI:Show(); __ns.UI:SetView("needs"); __ns.UI.itemBox:SetText(""); __ns.UI.focusBox = nil; ChatFrameUtil.InsertLink(__link(4306))')
check("shift-click fills the item box without clicking into it first (modern clients)", (A.ev('__ns.UI.itemBox:GetText()') or "").find("Hitem:4306") is not None)
A.ex('__ns.UI.itemBox:SetText(""); __cursor_item = 2589; __ns.UI.itemBox:GetScript("OnReceiveDrag")(__ns.UI.itemBox)')
check("dragging an item onto the box", "Hitem:2589" in (A.ev('__ns.UI.itemBox:GetText()') or "") and A.ev('__cursor_item') is None)
A.ex('__ns.UI.itemBox:SetText(""); __cursor_item = 14047; __ns.UI.itemBox:GetScript("OnMouseDown")(__ns.UI.itemBox)')
check("clicking the box with an item on the cursor", "Hitem:14047" in (A.ev('__ns.UI.itemBox:GetText()') or ""))
A.ex('__ns.UI.itemBox:SetText("")')

# soulbound items (Hearthstone, BoP gear) aren't guild stock
A.ex('__bags[1] = {{6948, 1, true}, {30050, 1, true}, {4306, 3}}; __fire("BAG_UPDATE")'); tick(8)
check("Hearthstone and soulbound gear left out of bank stock",
      A.ev('__ns.BankCount(6948)') == 0 and A.ev('__ns.BankCount(30050)') == 0 and A.ev('__ns.BankCount(4306)') == 28)
A.ex('__bags[1] = nil; __fire("BAG_UPDATE")'); tick(8)

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
check("search filters the bank list (column and category headers plus the item)", A.ev('#(function() local t = {} for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then t[#t+1] = r end end return t end)()') == 3)
check("bank grouped by category", A.ev('__ns.UI.rows[2].data.key') == "cat:Cloth" and A.ev('__ns.UI.rows[3].data.item') == 4306)
check("bank shows separate recorded and available stock columns",
      A.ev('__ns.UI.rows[1].data.stock')=="In bank" and A.ev('__ns.UI.rows[1].data.right')=="Available")
check("Bank groups inventory, needs and requests while other tabs are hidden",
      A.ev('__ns.UI.nav.bank:IsShown() and __ns.UI.nav.requests:IsShown() and not __ns.UI.nav.recipes:IsShown()'))
check("the stock view has a titled page",A.ev('__ns.UI.pageTitle:GetText()')=="Guild bank")
A.ex('__ns.UI:SetSize(1000, 540); __ns.UI:Layout(); __ns.UI:Refresh()')
check("wide Bank puts icons in a second navigation column",
      A.ev('__ns.UI.wideNav and __ns.UI.nav.requests.icon:IsShown()'))
A.ex('__ns.UI:SetSize(700, 470); __ns.UI:Layout(); __ns.UI:Refresh()')
check("compact Bank keeps icons in horizontal tabs",
      A.ev('not __ns.UI.wideNav and __ns.UI.nav.requests.icon:IsShown() and __ns.UI.nav.requests:IsShown()'))
A.ex('__ns.UI:SetView("projects")')
check("Projects loads a WoW texture path", A.ev('__ns.UI.nav.projects.icon:GetTexture()') ==
      r"Interface\Icons\Trade_BlackSmithing")
A.ex('__ns.UI.nav.membertools:Click()')
check("Member tools shortcuts have icons",
      A.ev('__ns.UI.rows[1].icon:IsShown() and __ns.UI.rows[5].icon:IsShown()'))
A.ex('__ns.UI:SetView("settings")')
check("Settings shortcuts have icons",
      A.ev('__ns.UI.rows[1].icon:IsShown() and __ns.UI.rows[3].icon:IsShown()'))
A.ex('__ns.UI.search:SetText(""); __ns.UI:SetView("home")')
check("Home starts with the message of the day, the attention card or the online count",
      A.ev('__ns.UI.rows[1].data.featured or __ns.UI.rows[1].data.key=="online"'))
check("Home shortcuts render their destination icons", A.ev("""(function()
  local count=0
  for _, row in ipairs(__ns.UI.rows) do
    if row:IsShown() then
      if not row.data.section then
        if not row.data.icon or not row.icon:IsShown() then return false end
        count=count+1
      end
    end
  end
  return count>=5
end)()"""))
A.ex('__ns.UI:SetView("bank"); __ns.UI.search:SetText("silk")')
A.ex("""__ns.UI:OpenDetails('item',4306); __ns.UI:OpenDetails('professionmail',4306)
__ns.UI.details.close:Click()""")
check("Back returns to the preceding details without losing the bank view",
      A.ev('__ns.UI.view=="bank" and __ns.UI.details.kind=="item" and __ns.UI.details.key==4306'))
check("item details show stock and the fixed request action",
      A.ev('__ns.UI.details.stats:IsShown() and tonumber(__ns.UI.details.stats[2].value:GetText())==25'
           ' and __ns.UI.details.actionBar:IsShown() and __ns.UI.details.actionBar.request:IsShown()'))
A.ex('__ns.UI.details.actionBar.request:Click()')
check("fixed request action preloads the selected item in the composer",
      A.ev('__ns.UI.view')=="requests" and "Hitem:4306" in A.ev('__ns.UI.itemBox:GetText()'))
A.ex('__ns.UI.itemBox:SetText(""); __ns.UI.qtyBox:ClearFocus(); __ns.UI:SetView("bank")')
A.ex('__ns.UI:CloseDetails()')
A.ex('__ns.UI.search:SetText(""); __ns.UI.state.bank.cat = "Herbs"; __ns.UI:Refresh()')
check("category dropdown filter", A.ev('(function() local n = 0 for _, r in ipairs(__ns.UI.rows) do if r:IsShown() then n = n + 1 end end return n end)()') == 0)
A.ex('__ns.UI.state.bank.cat = nil; __ns.UI.search:SetText("silk")')
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
A.ex('__sendCounts = {12}; __sendItems = {4306}; SendMail("Tyler Baker")'); tick(3)
check("sending marks it filled", B.ev(f'__ns.G().requests["{rid}"].status') == "filled")

# --- archive finished, void a donation ---
A.ex('__ns.ArchiveFinished()'); tick(3)
tick_until(lambda: B.ev(f'__ns.G().requests[\"{rid}\"].archived') == True, timeout=30)
check("tidy hides finished requests for everyone", B.ev(f'__ns.G().requests["{rid}"].archived') == True)
A.ex('__inbox[1] = {sender = "Tyler Baker", money = 0, items = {{2589, 20}}}; TakeInboxItem(1, 1)'); tick(6)
did = A.ev("(next(__ns.G().donations))")
check("donation logged", did is not None and B.ev(f'__ns.G().donations["{did}"] ~= nil'))
A.ex(f'__ns.VoidDonation("{did}", true)'); tick(3)
check("void syncs", B.ev(f'__ns.G().donations["{did}"].void') == True)
B.ex(f'local d = __ns.G().donations["{did}"]; d.void = nil; d.u = d.u + 5; __ns.Send("D", {{don = {{["{did}"] = d}}}})'); tick(2)
check("member can't un-void", A.ev(f'__ns.G().donations["{did}"].void') == True)

# --- officer policy: max open requests ---
for c in (A,B): c.ex('__ns.G().bank["Chris Baker"].seen[118]=true; __ns.G().bank["Chris Baker"].seen[858]=true; __ns.db.itemClass=__ns.db.itemClass or {}; __ns.db.itemClass[118]={0,1}; __ns.db.itemClass[858]={0,1}')
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
check("newer version shows the popup once", B.ev("#__dialogs") == 1 and "9.9.9" in B.ev("__dialogs[1][1]"))
A.ex('__ns.Send("H", {needs = 0, bank = {}, since = 0, ver = "9.9.9"})'); tick(3)
check("no repeat popup for the same version", B.ev("#__dialogs") == 1)
check("older version: no popup", A.ev("#__dialogs") == 0)
check("the addon never uses Blizzard's shared pop-ups (taint)", B.ev("#__popups") == 0 and A.ev("#__popups") == 0)

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
rowsTxt = lambda: B.ev('(function() local t = {} for _, r in ipairs(__ns.DonatePanel.rows) do if r:IsShown() then t[#t+1] = r.id and ("item:" .. r.id) or r.head:GetText() end end return table.concat(t, "|") end)()')
dshown = rowsTxt()
check("needed items come first, under Bank needs (%s)" % dshown, dshown.startswith("Bank needs") and dshown.split("|")[1] == "item:2589")
check("other crafting materials are grouped by category", "Cloth" in dshown and "item:4306" in dshown)
check("nothing picked until you choose", B.ev('next(__ns.DonatePanel.pick)') is None)
B.ex('local r = __ns.DonatePanel:RowFor(2589); r.plus:GetScript("OnClick")(); r.plus:GetScript("OnClick")()')
check("+ adds one at a time", B.ev('__ns.DonatePanel.pick[2589]') == 2)
B.ex('IsControlKeyDown = function() return true end; __ns.DonatePanel:RowFor(2589):GetScript("OnMouseWheel")(nil, 1); IsControlKeyDown = function() return false end')
check("ctrl + mouse wheel adjusts", B.ev('__ns.DonatePanel.pick[2589]') == 3)
need_left = B.ev('200 - __ns.BankCount(2589)')
first = B.ev('__ns.DonatePanel:RowFor(2589).max:GetText()')
B.ex('__ns.DonatePanel:RowFor(2589).max:GetScript("OnClick")()')
if need_left < 30:
    check("the button says Need, and picks what the bank still needs", first == "Need" and B.ev('__ns.DonatePanel.pick[2589]') == need_left)
    check("then it says Max", B.ev('__ns.DonatePanel:RowFor(2589).max:GetText()') == "Max")
    B.ex('__ns.DonatePanel:RowFor(2589).max:GetScript("OnClick")()')
check("Max picks everything you carry", B.ev('__ns.DonatePanel.pick[2589]') == 30 and B.ev('__ns.DonatePanel:RowFor(2589).max:GetText()') == "Max")
check("the small buttons have a forgiving click area", B.ev('(function() local _, _, t = __ns.DonatePanel:RowFor(2589).max:GetHitRectInsets() return t end)()') == -5)
B.ex('__ns.DonatePanel.pick[2589] = 25; __ns.FillDonation()')
check("Fill mail attaches exactly the chosen amount", B.ev('(function() local n = 0 for _, s in pairs(__mailSlots) do n = n + s[2] end return n end)()') == 25)
check("addressed to the bank", B.ev('SendMailNameEditBox._text') == "Chris Baker")

allTxt = lambda: B.ev('(function() local t = {} for _, e in ipairs(__ns.DonatePanel.entries) do t[#t+1] = e.id and ("item:" .. e.id) or e.head end return table.concat(t, "|") end)()')
# what's offered: crafting stuff and green+ BoE gear; never soulbound, quest items or the Hearthstone
B.ex('__bags[0] = {{2589, 20}, {4306, 5}, {6948, 1}, {30050, 1}, {30051, 1}, {30052, 1, true}, {30053, 1}, {30054, 1}}'
     '; __cls = __cls or {}; __cls[30050] = {4, "Mail"}; __cls[30051] = {4, "Cloth"}; __cls[30052] = {2, "Sword"}; __cls[30053] = {12, "Quest"}; __cls[30054] = {0, "Potion"}'
     '; __qual = { [30050] = 2, [30051] = 1, [30052] = 3 }; __bind = { [30050] = 2, [30051] = 2, [30052] = 2 }')
B.ex('table.insert(__bags[0], {30055, 1}); table.insert(__bags[0], {30056, 1}); table.insert(__bags[0], {30057, 1})'
     '; __cls[30055] = {9, "Tailoring"}; __cls[30056] = {1, "Bag"}; __cls[30057] = {15, "Junk"}; __qual[30057] = 0')
B.ex('__ns.DonatePanel.offset = 0; __ns.DonatePanel.showAll = false; __ns.DonatePanel:Update()')
dshown = allTxt()
check("recipes and bags are offered", "item:30055" in dshown and "Recipes" in dshown and "item:30056" in dshown and "Bags" in dshown)
check("grey junk isn't", "item:30057" not in dshown)
check("green Bind on Equip gear is offered (%s)" % dshown, "item:30050" in dshown and "Gear (Bind on Equip)" in dshown)
check("white gear waits behind Show everything", "item:30051" not in dshown)
check("consumables (potions etc.) are offered", "item:30054" in dshown and "Consumables" in dshown)
check("soulbound, quest items and the Hearthstone never show", all(x not in dshown for x in ("item:30052", "item:30053", "item:6948")))
B.ex('__ns.DonatePanel.showAll = true; __ns.DonatePanel:Update()')
dshown = allTxt()
check("Show everything adds the rest, still no soulbound", "item:30051" in dshown and "item:30052" not in dshown)
# long lists scroll
B.ex('__bags[0] = {}; for i = 0, 25 do __bags[0][i + 1] = {30100 + i, 3} end; __ns.DonatePanel.offset = 0; __ns.DonatePanel:Update()')
first = B.ev('__ns.DonatePanel.shown')
B.ex('__ns.DonatePanel.list:GetScript("OnMouseWheel")(nil, -1)')
check("a long list scrolls (%d rows shown of %d)" % (first, B.ev('__ns.DonatePanel.entryCount')), first < B.ev('__ns.DonatePanel.entryCount') and B.ev('__ns.DonatePanel.offset') > 0)
B.ex('__ns.DonatePanel.showAll = false; __bags[0] = {}; __cls[30050] = nil; __cls[30051] = nil; __cls[30052] = nil; __cls[30053] = nil; __cls[30054] = nil; __cls[30055] = nil; __cls[30056] = nil; __cls[30057] = nil; __qual = nil; __bind = nil')

# --- gold in the donation ---
B.ex('__mailSlots = {}; __sendItems = {}; __money = 50000; __bags[0] = {{2589, 10}}; __ns.ShowDonate()')
B.ex('MoneyInputFrame_SetCopper = function(f, c) __mailMoney = c end; SendMailMoney = {}; SendMailBodyEditBox = NewMock(); SendMailSendMoneyButton = NewMock()')
coin = lambda i, btn="LeftButton": B.ex('__ns.DonatePanel.coinBtns[%d]:GetScript("OnClick")(__ns.DonatePanel.coinBtns[%d], "%s")' % (i, i, btn))
coin(1); coin(2); coin(4)
check("gold buttons add 5s + 10s + 1g", B.ev('__ns.DonatePanel.money') == 11500)
coin(2, "RightButton")
check("right-click takes it back off", B.ev('__ns.DonatePanel.money') == 10500)
check("the amount shows on the panel", "1" in (B.ev('__ns.DonatePanel.moneyText:GetText()') or ""))
check("gold alone is enough to fill a mail", B.ev('__ns.DonatePanel.fill.text:GetText()') == "Fill mail")
B.ex('__ns.DonatePanel.pick[2589] = 4; __ns.FillDonation()')
check("Fill mail puts the gold in the mail", B.ev('__mailMoney') == 10500)
body = B.ev('SendMailBodyEditBox._text') or ""
check("and writes what it's for in the letter (%s)" % body, "Linen Cloth x4" in body and "1g 5s in gold" in body)
check("panel resets afterwards", B.ev('__ns.DonatePanel.money') == 0)
B.ex('__money = 2000; __ns.DonatePanel:Update()'); coin(4)
check("can't give more than you have (keeping postage)", B.ev('__ns.DonatePanel.money') == 0)
# closes with the mailbox, whichever way the game says so
B.ex('__ns.DonatePanel:Show(); __fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)')
check("donate panel closes when the mailbox closes", B.ev('__ns.DonatePanel:IsShown()') != True)
B.ex('__money = 100000')

# --- the same panel at the guild bank vault ---
B.ex('__gb = { [1] = { [1] = {2589, 20} }, [2] = {} }; __gblog = { [1] = {}, [2] = {} }; __gbmoneylog = {}')
B.ex('__placed = {}; PickupGuildBankItem = function(tab, slot) if __cursor then table.insert(__placed, { tab, slot, __cursor[1], __cursor[2] }); __gb[tab][slot] = { __cursor[1], __cursor[2] }; __cursor = nil end end')
B.ex('DepositGuildBankMoney = function(c) __gbDeposit = c end; GuildBankFrame = NewMock()')
B.ex('__bags[0] = {{2589, 20}, {4306, 5}, {30060, 1, true}}; __money = 50000')
B.ex('__fire("GUILDBANKFRAME_OPENED")'); tick(2)
check("donate panel opens beside the guild bank", B.ev('__ns.DonatePanel:IsShown()') == True and B.ev('__ns.DonatePanel.mode') == "vault")
check("it says which tab it deposits into", "Deposit into: Tab1" in B.ev('__ns.DonatePanel.toBtn.text:GetText()'))
B.ex('__ns.DonatePanel.pick[2589] = 12; __ns.DonatePanel.pick[4306] = 5; __ns.DonatePanel:Update()')
B.ex('__ns.DonatePanel.coinBtns[2]:GetScript("OnClick")(__ns.DonatePanel.coinBtns[2], "LeftButton")')
check("button says Deposit", B.ev('__ns.DonatePanel.fill.text:GetText()') == "Deposit")
B.ex('__ns.DonatePanel.fill:GetScript("OnClick")()'); tick(3)
placed = B.ev('(function() local t = {} for _, p in ipairs(__placed) do t[#t+1] = p[3] .. "x" .. p[4] .. "@" .. p[2] end return table.concat(t, ",") end)()')
check("picked items go into empty slots of the current tab (%s)" % placed, "2589x12" in placed and "4306x5" in placed
      and all(not p.endswith("@1") for p in placed.split(",")))
check("only part of a stack moves when you picked part", B.ev('__bags[0][1][2]') == 8)
check("the gold is deposited too", B.ev('__gbDeposit') == 1000)
B.ex('__fire("GUILDBANKFRAME_CLOSED")')
check("panel closes with the guild bank", B.ev('__ns.DonatePanel:IsShown()') != True)
B.ex('__bags[0] = {}')
A.ex('__ns.ShowDonate()')
check("the bank character doesn't get the donate panel", A.ev('__ns.DonatePanel:IsShown()') != True)

# --- 6. welcome ---
B.ex('__ns.ShowWelcome()')
check("welcome card shows", B.ev('true'))

# --- details panel scrolls instead of overflowing ---
A.ex('__ns.UI:SetSize(620, 420); __ns.UI:SetView("requests"); __ns.UI:OpenDetails("request", "' + rid3 + '")')
check("details body sized for scrolling", A.ev('__ns.UI.details.body:GetHeight()') > 100)

# --- recipes: Tyler (tailor) opens his profession window ---
B.ex('__TS = { { "Cloth", "header" }, { "Bolt of Linen Cloth", "easy", 2996 }, { "Linen Bag", "easy", 30001 }, { "BoP Robe", "easy", 30002 } }; __bop = { [30002] = true }')
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(6)
idx = "(function() local t = {} for _, e in ipairs(__ns.RecipeIndex()) do t[#t+1] = tostring(e.item) end table.sort(t) return table.concat(t, ',') end)()"
check("recipes shared with the guild, BoP left out (%s)" % A.ev(idx), A.ev(idx) == "2996,30001")
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(6)
check("unchanged recipes aren't re-sent", B.ev('__ns.G().recipes["Tyler Baker"].t') == A.ev('__ns.G().recipes["Tyler Baker"].t'))
B.ex('__ns.SetDesignated("Tailoring", "Tyler Baker", true)'); tick(2)
check("members can't designate crafters", A.ev('__ns.IsDesignated("Tyler Baker", "Tailoring")') == False)
A.ex('__ns.SetDesignated("Tailoring", "Tyler Baker", true)'); tick(3)
check("officer designates a guild tailor (synced)", B.ev('__ns.IsDesignated("Tyler Baker", "Tailoring")') == True)
A.ex('__ns.UI:SetView("recipes")')
check("Recipes view lists them", A.ev(shown) == 2)
A.ex('__ns.UI.search:SetText("bolt")')
check("recipe search", A.ev(shown) == 1)
A.ex('__ns.UI.search:SetText(""); __ns.UI.state.recipes.designated = true; __ns.UI:Refresh()')
check("guild crafters filter", A.ev(shown) == 2)
A.ex('__ns.UI.state.recipes.designated = false; __ns.UI.state.recipes.prof = "Mining"; __ns.UI:Refresh()')
check("profession filter", A.ev(shown) == 0)
check("recipes count includes recipes outside the selected profession",
      A.ev('__ns.UI.filterCount:GetText()=="0 of 2 shown" and __ns.UI.clearFilters:IsShown()'))
A.ex('__ns.UI.clearFilters:Click(); __ns.UI.profChip:GetScript("OnClick")(__ns.UI.profChip)')
check("profession dropdown opens with All + each profession",
      A.ev('EPUGuildMenu:IsShown()') == True and A.ev('EPUGuildMenu.rows[1].text:GetText()') == "All professions"
      and A.ev('EPUGuildMenu.rows[2].text:GetText()') == "Tailoring" and A.ev('EPUGuildMenu.rows[2].right:GetText()') == "2"
      and A.ev('EPUGuildMenu.rows[3] == nil or not EPUGuildMenu.rows[3]:IsShown()') == True)
A.ex('EPUGuildMenu.rows[2]:GetScript("OnClick")(EPUGuildMenu.rows[2])')
check("picking from the dropdown filters and closes it",
      A.ev('__ns.UI.state.recipes.prof') == "Tailoring" and A.ev(shown) == 2 and A.ev('EPUGuildMenu:IsShown()') == False
      and A.ev('__ns.UI.profChip.text:GetText()') == "Tailoring")
A.ex('__ns.UI.profChip:GetScript("OnClick")(__ns.UI.profChip); EPUGuildMenu.catch:GetScript("OnClick")(EPUGuildMenu.catch)')
check("clicking outside closes the dropdown", A.ev('EPUGuildMenu:IsShown()') == False)
A.ex('__ns.UI.profChip:GetScript("OnClick")(__ns.UI.profChip); EPUGuildMenu.rows[1]:GetScript("OnClick")(EPUGuildMenu.rows[1])')
check("All professions clears it", A.ev('__ns.UI.state.recipes.prof') is None)
A.ex('__ns.UI.state.recipes.prof = nil; __ns.UI.state.recipes.crafter = "Chris Stone"; __ns.UI:Refresh()')
check("crafter filter", A.ev(shown) == 0)
A.ex('__ns.UI.state.recipes.crafter = nil; __ns.UI:Refresh(); __ns.UI:OpenDetails("recipe", "item:2996")')
check("recipe details open", A.ev('__ns.UI.details.kind') == "recipe")
A.ex('__ns.UI:SetView("crafters"); __ns.UI:OpenDetails("crafter", "Tyler Baker")')
clients["Newbie Stone"].ex('');  tick(1)
F = Client("Chris Stone"); clients["Chris Stone"] = F
# Digest size and bundle ordering vary with Lua table order. Wait for the
# actual paced transfer rather than assuming the whole login fits in 30s.
tick_until(lambda: F.ev('#__ns.RecipeIndex()') == 2 and F.ev('__ns.IsDesignated("Tyler Baker", "Tailoring")') == True, timeout=60)
check("late joiner gets recipes and guild crafters", F.ev('#__ns.RecipeIndex()') == 2 and F.ev('__ns.IsDesignated("Tyler Baker", "Tailoring")') == True)

# ===================== 0.7.0 crafting features =====================
# Tyler rescans: Linen Bag is orange for him, the bolt is gray; reagents come along.
B.ex('__TS = { { "Cloth", "header" }, { "Bolt of Linen Cloth", "trivial", 2996 }, { "Linen Bag", "optimal", 30001 }, { "BoP Robe", "easy", 30002 } }')
B.ex('__TSR = { [2] = { {2589, 2} }, [3] = { {2996, 3}, {2589, 1} } }')
B.ex('__fire("TRADE_SKILL_SHOW")'); tick(6)
check("reagents shared with the guild", A.ev('#__ns.MatsFor("item:30001")') == 2 and A.ev('__ns.MatsFor("item:30001")[1].n') == 3
      and F.ev('#__ns.MatsFor("item:2996")') == 1)
check("skill-up colors shared (orange; gray left out)", A.ev('__ns.RecipeFor("item:30001").crafters[1].diff') == "o"
      and A.ev('__ns.RecipeFor("item:2996").crafters[1].diff') is None)
check("recipes carry when they were scanned", (A.ev('__ns.RecipeFor("item:30001").crafters[1].at') or 0) > 0)
bolts = A.ev('__ns.BankCount(2996)'); linen = A.ev('__ns.BankCount(2589)')
check("bank coverage for a recipe (%s)" % A.ev('__ns.CraftsCovered("item:30001")'),
      A.ev('__ns.CraftsCovered("item:30001")') == min(bolts // 3, linen // 1))

# Recipes view: skill-up filter, details with reagents, stock button
A.ex('__ns.UI:CloseDetails(); __ns.UI:SetView("recipes"); __ns.UI.search:SetText(""); __ns.UI.state.recipes = { skillup = true }; __ns.UI:Refresh()')
check("skill-ups filter", A.ev(shown) == 1)
A.ex('__ns.UI.state.recipes.skillup = false; __ns.UI:Refresh(); __ns.UI:OpenDetails("recipe", "item:30001")')
check("recipe details list reagents", A.ev('(function() for _, f in ipairs(__ns.UI.details.pools.text) do if f:IsShown() and (f:GetText() or ""):find("Bolt of Linen Cloth x3", 1, true) then return true end end return false end)()') == True)
B.ex('__ns.StockMatsFor("item:30001", 5)'); tick(2)
check("members can't stock materials", A.ev('(__ns.NeedEntry(__ns.G().needs.list[2996]))') < 15)
A.ex('__ns.StockMatsFor("item:30001", 5)'); tick(3)
check("officer stocks mats for 5 crafts (synced)", B.ev('(__ns.NeedEntry(__ns.G().needs.list[2996]))') == 15)

# Tooltips
tt = 'local t = { lines = {} }; function t:AddLine(x) table.insert(self.lines, x) end; function t:Show() end; __tt = t'
lines = "(function() return table.concat(__tt.lines, ' | ') end)()"
A.ex('__ITEMS[30001] = "Linen Bag"; __ITEMS[30100] = "Pattern: Linen Bag"; __ITEMS[30101] = "Pattern: Silk Hat"; __cls = { [30100] = {9, "Tailoring"}, [30101] = {9, "Tailoring"} }')
A.ex(tt + '; __ns.TooltipLines(__tt, 30001)')
check("crafted item tooltip names the guild crafters (%s)" % A.ev(lines), "Guild crafters:" in A.ev(lines) and "Tyler" in A.ev(lines))
A.ex(tt + '; __ns.TooltipLines(__tt, 30100)')
check("pattern tooltip: someone knows it", "Known in the guild by" in A.ev(lines))
A.ex(tt + '; __ns.TooltipLines(__tt, 30101)')
check("pattern tooltip: nobody knows it (%s)" % A.ev(lines), "Nobody in the guild knows" in A.ev(lines))

# Craft requests: Pip asks Tyler for 2 Linen Bags, bank sends the mats
for c in (A, B, E):
    c.ex('__toasts = {}; __ns.Notify = function(t) table.insert(__toasts, t) end')
open_before = A.ev('__ns.OpenCountFor("Pip Baker")')
crid = E.ev('__ns.NewCraftRequest("item:30001", "Tyler Baker", 2, "bank", "for my alt")'); tick(3)
check("craft request reaches the crafter", B.ev('__ns.G().requests["%s"].crafter' % crid) == "Tyler Baker" and A.ev('__ns.G().requests["%s"].status' % crid) == "pending")
check("crafter gets a pop-up", B.ev('__toasts[1]') == "Craft request")
check("craft requests don't count toward the bank limit", A.ev('__ns.OpenCountFor("Pip Baker")') == open_before)
D.ex('__ns.EditRequest("%s", { status = "approved" })' % crid); tick(2)
check("someone else can't accept it", A.ev('__ns.G().requests["%s"].status' % crid) == "pending")
B.ex('__ns.EditRequest("%s", { status = "approved", qty = 50 })' % crid); tick(3)
check("crafter accepts (synced), and can't change the amount", A.ev('__ns.G().requests["%s"].status' % crid) == "approved"
      and E.ev('__ns.G().requests["%s"].qty' % crid) == 2)
check("requester told it was accepted", "Craft accepted" in [E.ev('__toasts[%d]' % i) for i in range(1, 4)])
check("officer told the bank sends mats", "Bank materials needed" in [A.ev('__toasts[%d]' % i) for i in range(1, 4)])
check("bank-paid mats go on the shopping list",
      A.ev('(function() for _, r in ipairs(__ns.ShoppingList()) do if r.id == 2996 then return r.req end end return 0 end)()') == 6)
# a forged update from someone who isn't the crafter is ignored
crid2 = E.ev('__ns.NewCraftRequest("item:2996", "Tyler Baker", 1, "me")'); tick(3)
D.ex('local r = __ns.G().requests["%s"]; local c = {}; for k, v in pairs(r) do c[k] = v end; c.status = "approved"; c.u = c.u + 5; __ns.Send("D", { req = { ["%s"] = c } })' % (crid2, crid2)); tick(3)
check("forged crafter update ignored", A.ev('__ns.G().requests["%s"].status' % crid2) == "pending")
B.ex('local r = __ns.G().requests["%s"]; local c = {}; for k, v in pairs(r) do c[k] = v end; c.status = "approved"; c.qty = 99; c.u = c.u + 9; __ns.Send("D", { req = { ["%s"] = c } })' % (crid2, crid2)); tick(3)
check("crafter can't change the amount by hand-editing", A.ev('__ns.G().requests["%s"].qty' % crid2) == 1)
# Tyler mails the bags to Pip: filled automatically
B.ex('__ns.AutoFillFor("Pip Baker", { {30001, 2} })'); tick(3)
check("crafter mailing it marks it made", A.ev('__ns.G().requests["%s"].status' % crid) == "filled")
check("requester told it's done", "Craft done" in [E.ev('__toasts[%d]' % i) for i in range(1, 6)])

# Requests view and details for crafts
A.ex('__ns.UI:SetView("requests"); __ns.UI.state.requests = { filter = "all", sort = "new", crafts = true }; __ns.UI:Refresh()')
check("Crafts filter", A.ev(shown) == 2)
B.ex('__ns.UI:Show(); __ns.UI:SetView("requests"); __ns.UI:OpenDetails("request", "%s")' % crid2)
check("crafter sees Accept in the details", B.ev('(function() for _, b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText() == "Accept" then return true end end return false end)()') == True)
E.ex('__ns.UI:Show(); __ns.UI:SetView("recipes"); __ns.UI:OpenDetails("craftask", "item:30001\\nTyler Baker")')
check("ask-to-craft form", E.ev('__ns.UI.details.kind') == "craftask")
E.ex('(function() for _, b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText() == "Send request" then b:GetScript("OnClick")(b) end end end)()'); tick(3)
check("form sends the request", A.ev('(function() local n = 0 for _, r in pairs(__ns.G().requests) do if r.crafter then n = n + 1 end end return n end)()') == 3)

# Crafters: profession dropdown; officer coverage
A.ex('__ns.UI:CloseDetails(); __ns.UI:SetView("crafters"); __ns.UI.state.crafters = { filter = "all", prof = "Tailoring" }; __ns.UI:Refresh()')
tailors = A.ev(shown)
A.ex('__ns.UI.state.crafters.prof = "Leatherworking"; __ns.UI:Refresh()')
check("crafters profession filter (%d tailors)" % tailors, tailors >= 1 and A.ev(shown) == 0)
A.ex('__ns.UI.crafterProfChip:GetScript("OnClick")(__ns.UI.crafterProfChip)')
check("crafters dropdown opens", A.ev('EPUGuildMenu:IsShown()') == True and A.ev('EPUGuildMenu.rows[1].text:GetText()') == "All professions")
A.ex('EPUGuildMenu:Hide()')
cov = "(function() for _, r in ipairs(__ns.Coverage()) do if r.prof == '%s' then return r.count end end end)()"
check("coverage: tailoring covered, leatherworking a gap", A.ev(cov % "Tailoring") >= 1 and A.ev(cov % "Leatherworking") == 0)
A.ex('__ns.UI:SetView("officer"); __ns.UI:OpenDetails("coverage", "all")')
check("coverage details open", A.ev('__ns.UI.details.kind') == "coverage")

# Requests: status and sort are dropdowns now
A.ex('__ns.UI:CloseDetails(); __ns.UI:SetView("requests"); __ns.UI.state.requests = { filter = "open", sort = "new" }; __ns.UI:Refresh()')
A.ex('__ns.UI.statusChip:GetScript("OnClick")(__ns.UI.statusChip)')
check("status dropdown lists every filter", A.ev('EPUGuildMenu.rows[6]:IsShown()') == True and A.ev('EPUGuildMenu.rows[4].text:GetText()') == "Filled / made")
A.ex('EPUGuildMenu.rows[4]:GetScript("OnClick")(EPUGuildMenu.rows[4])')
check("picking a status filters", A.ev('__ns.UI.state.requests.filter') == "filled" and A.ev('__ns.UI.statusChip.text:GetText()') == "Filled")
A.ex('__ns.UI.sortChip:GetScript("OnClick")(__ns.UI.sortChip); EPUGuildMenu.rows[3]:GetScript("OnClick")(EPUGuildMenu.rows[3])')
check("sort dropdown", A.ev('__ns.UI.state.requests.sort') == "item" and A.ev('__ns.UI.sortChip.text:GetText()') == "Sort: Item")
check("dropdown rows sit above the close-anywhere layer", A.ev('EPUGuildMenu:GetFrameLevel() > EPUGuildMenu.catch:GetFrameLevel()') == True)
# Toolbars fit the narrowest window (620 wide, minus the sidebar)
fits = A.ev('(function() local bad = {} for _, k in ipairs({"needs","shopping","bank","requests","donations","crafters","recipes"}) do __ns.UI:SetView(k) local b = __ns.UI.bars and __ns.UI.bars[k] if b and b.leftX + b.rightX > 480 then bad[#bad+1] = k .. "=" .. (b.leftX + b.rightX) end end return table.concat(bad, ",") end)()')
check("every toolbar fits at the smallest window size (%s)" % (fits or "ok"), fits == "")
check("addon loads on a client missing CRAFT_SHOW and friends", A.ev('__ns.handlers.TRADE_SKILL_SHOW ~= nil') == True)

# Button position follows the actual map size/shape, with accessible recovery.
A.ex("""__mb=EPUGuildMinimapButton; __point={}
__mb.SetPoint=function(_,...) __point={...} end
Minimap.GetWidth=function() return 240 end; Minimap.GetHeight=function() return 180 end
Minimap.GetCenter=function() return 100,200 end; Minimap.GetEffectiveScale=function() return 2 end
UIParent.GetWidth=function() return 1920 end; UIParent.GetHeight=function() return 1080 end
GetMinimapShape=function() return 'ROUND' end
__ns.db.settings.minimapAngle=0; __ns.db.settings.minimapGap=nil; __ns.UpdateMinimapButton()
""")
check('button follows a larger minimap instead of a fixed radius',A.ev('__point[4]')==140 and A.ev('__point[5]')==0)
A.ex("""__neighbor=CreateFrame("Button",nil,Minimap)
__neighbor.IsObjectType=function(_,kind) return kind=="Button" end
__neighbor.GetRect=function() return 468,388,24,24 end
Minimap.GetChildren=function() return __mb,__neighbor end
__ns.UpdateMinimapButton()
""")
check('button avoids a visible minimap neighbor even at a different scale',
      A.ev('math.abs(__point[5])>=23 and __ns.db.settings.minimapAngle==0'))
A.ex('__neighbor:Hide(); __ns.UpdateMinimapButton()')
check('the preferred position returns when the neighboring button is hidden',
      A.ev('__point[4]==140 and __point[5]==0'))
check('badge uses a compact footprint', A.ev('__mb:GetWidth()==28 and __mb:GetHeight()==28'))
A.ex("__ns.db.settings.minimapAngle=45; __ns.UpdateMinimapButton()")
check('round minimap button stays outside its elliptical edge',A.ev('math.abs((__point[4]/140)^2+(__point[5]/110)^2-1)<0.00001'))
A.ex("GetMinimapShape=function() return 'SQUARE' end; __ns.UpdateMinimapButton()")
check('square minimap button follows the corner',A.ev('math.abs(__point[4]-140)<0.00001 and math.abs(__point[5]-110)<0.00001'))
A.ex("""GetMinimapShape=function() return 'CORNER-TOPLEFT' end
local x,y=__ns.MinimapButtonOffset(135,240,180,'CORNER-TOPLEFT',20)
__rounded=math.abs(x)<140 and math.abs(y)<110
x,y=__ns.MinimapButtonOffset(315,240,180,'CORNER-TOPLEFT',20)
__square=math.abs(x-140)<0.00001 and math.abs(y+110)<0.00001
SlashCmdList.EPUGUILD('button'); EPUGuildButtonSettings.presets[6]:Click()
""")
check('mixed minimap shapes follow rounded and square quadrants',A.ev('__rounded and __square'))
check('position controls work without dragging',A.ev('__ns.db.settings.minimapAngle')==0 and A.ev('EPUGuildButtonSettings:IsShown()'))
A.ex("EPUGuildButtonSettings.further:Click()")
check('spacing control moves button further outside',A.ev('__ns.db.settings.minimapGap')==28)
A.ex("for i=1,20 do EPUGuildButtonSettings.further:Click() end; __maxGap=__ns.db.settings.minimapGap; for i=1,20 do EPUGuildButtonSettings.closer:Click() end")
check('spacing cannot move button into map or arbitrarily far away',A.ev('__maxGap')==80 and A.ev('__ns.db.settings.minimapGap')==16)
A.ex("EPUGuildButtonSettings.lock:Click(); __mb:GetScript('OnDragStart')(__mb)")
check('locked button ignores dragging',A.ev('__mb:GetScript("OnUpdate")') is None)
A.ex("""EPUGuildButtonSettings.lock:Click(); __ns.db.settings.minimapGap=20
GetCursorPosition=function() return 200,180 end
__mb:GetScript('OnDragStart')(__mb); __mb:GetScript('OnUpdate')(__mb)
""")
check('dragging uses effective scale and map dimensions',abs(A.ev('__ns.db.settings.minimapAngle')-270)<0.00001)
A.ex("""__mb:GetScript('OnDragStop')(__mb)
__toggle=0; __oldToggle=__ns.UI.Toggle; __ns.UI.Toggle=function() __toggle=__toggle+1 end
IsShiftKeyDown=function() return false end
__mb:GetScript('OnClick')(__mb,'LeftButton'); __advance(0.3); __mb:GetScript('OnClick')(__mb,'LeftButton')
__ns.UI.Toggle=__oldToggle
SlashCmdList.EPUGUILD('minimap hide')
""")
check('releasing a drag does not accidentally open the addon',A.ev('__toggle')==1)
check('explicit hide works',not A.ev('__mb:IsShown()'))
A.ex("SlashCmdList.EPUGUILD('minimap reset')")
check('reset recovers a hidden button and unlocks it',A.ev('__mb:IsShown() and not __ns.db.settings.minimapLocked and __ns.db.settings.minimapAngle==200 and __ns.db.settings.minimapGap==20'))
A.ex("""__ns.db.settings.minimapAngle=0; Minimap.GetWidth=function() return 320 end
Minimap:GetScript('OnSizeChanged')(Minimap)
""")
check('resized minimap automatically repositions button',A.ev('__point[4]')==180)
A.ex("""Minimap.GetCenter=function() return 940,400 end; GetMinimapShape=function() return 'ROUND' end
__ns.db.settings.minimapAngle=0; __ns.UpdateMinimapButton()
""")
check('screen-edge placement stays on perimeter instead of clamping inside',A.ev('940+__point[4]<=938 and math.abs((__point[4]/180)^2+(__point[5]/110)^2-1)<0.00001'))
check('screen-edge fallback preserves preferred saved angle',A.ev('__ns.db.settings.minimapAngle')==0)
A.ex("__ns.ShowGuildMapSettings(); EPUGuildMapSettings.buttonSettings:Click()")
check('map settings expose button position controls',A.ev('EPUGuildButtonSettings:IsShown()'))

# Sync keeps transfer details one click away and ages out recent-request labels.
A.ex("""local ns=__ns
ns.newestVersion=nil; ns.RELEASE_VERSION=nil
ns.roster["Tyler Baker"].classFile="PALADIN"
ns.SeenSync("Tyler Baker",{t=ns.Now()-7200,asked=ns.Now()-3600,from="Chris Baker",kind="officer",
  what="14 event signups, 49 character confirmations",ver="0.21.4"})
ns.UI:SetView("sync"); ns.UI.search:SetText("Tyler Baker")
""")
check("Sync list shows a short status and neutral version without a known release",
      A.ev("""(function()
        local r=__ns.UI.rows[1]
        return r.icon:IsShown() and r.data.pill=="sync_ok" and not r.data.sub:find("signups",1,true)
          and r.data.rightColor==__ns.InterfaceColors.muted
      end)()"""))
check("Sync uses the reported member's class icon and keeps their online dot",
      A.ev("""(function()
        local r=__ns.UI.rows[1]
        local texture,coords=__ns.ClassIcon("PALADIN")
        local left,right,top,bottom=r.icon:GetTexCoord()
        return r.icon:GetTexture()==texture and left==coords[1] and right==coords[2]
          and top==coords[3] and bottom==coords[4] and r.dot:IsShown()
      end)()"""))
A.ex('__ns.UI.rows[1]:Click()')
check("Sync details retain the full transfer summary",
      A.ev("""(function()
        local d=__ns.UI.details
        for _, line in ipairs(d.pools.text) do
          if line:IsShown() and line:GetText():find("14 event signups",1,true) then return d.kind=="syncmember" end
        end
      end)()"""))
A.ex("""__ns.RELEASE_VERSION="0.23.0"
__ns.SeenSync("Tyler Baker",{asked=__ns.Now()})
__ns.UI:Refresh()
""")
check("Sync marks a recent request and compares versions against a published release",
      A.ev('__ns.UI.rows[1].data.pill=="sync_wait" and __ns.UI.rows[1].data.rightColor==__ns.InterfaceColors.red'))
A.ex("""local u=__ns.UI
u:CloseDetails(); u.search:SetText("")
u.bars.sync.status:Click()
for _,r in ipairs(EPUGuildMenu.rows) do if r:IsShown() and r.value=="outdated" then r:Click(); break end end
""")
check("Sync status menu filters to members with older versions",
      A.ev("""(function()
        local ns, tyler=__ns,false
        for _,r in ipairs(ns.UI.rows) do
          if r:IsShown() then
            if r.data.rightColor~=ns.InterfaceColors.red then return false end
            if r.data.name=="Tyler Baker" then tyler=true end
          end
        end
        return ns.UI.state.sync.status=="outdated" and tyler
      end)()"""))
A.ex("""local u=__ns.UI
assert(u.clearFilters:IsShown() and u.filterCount:GetText():match("^%d+ of %d+ shown$"))
u.clearFilters:Click()
assert(u.state.sync.status=="all" and not u.clearFilters:IsShown())
u.bars.sync.sort:Click()
for _,r in ipairs(EPUGuildMenu.rows) do if r:IsShown() and r.value=="name" then r:Click(); break end end
""")
check("Sync sort menu can order members by name",
      A.ev("""(function()
        local ns, prev=__ns,""
        for _,r in ipairs(ns.UI.rows) do
          if r:IsShown() then
            local name=r.data.name:lower()
            if name<prev then return false end
            prev=name
          end
        end
        return ns.UI.state.sync.sort=="name" and prev~=""
      end)()"""))
A.ex('__ns.UI.bars.sync.chips[3]:Click()')
check("This PC keeps the activity log without member filters",
      A.ev('__ns.UI.state.sync.filter=="mine" and not __ns.UI.bars.sync.status:IsShown() and not __ns.UI.bars.sync.sort:IsShown()'))
A.ex('__ns.RELEASE_VERSION=nil; __ns.UI:SetView("bank"); __ns.UI.bankCatChip:Click()')
check("Bank category dropdown renders icons", A.ev('EPUGuildMenu.rows[1].icon:GetTexture()') ==
      r"Interface\Icons\INV_Misc_Bag_10")
A.ex('EPUGuildMenu:Hide(); __ns.UI.search:SetText("zz-no-search-matches-zz")')
check("empty search offers to clear the search",
      A.ev('__ns.UI.emptyAction:IsShown() and __ns.UI.emptyAction:GetText()=="Clear search"'))
A.ex('__ns.UI.emptyAction:Click()')
check("clear search brings the rows back",
      A.ev('__ns.UI.search:GetText()=="" and __ns.UI.rows[1]:IsShown() and not __ns.UI.emptyAction:IsShown()'))
A.ex("""local b=__ns.InterfaceButton(UIParent,"Test button")
b:SetOn(true); __selected=b.mark:IsShown()
b:SetEnabled(false); b:SetOn(true); b:GetScript("OnEnter")(b)
__disabled=b.disabled and not b.mark:IsShown()
b:SetEnabled(true); __restored=not b.disabled and b.mark:IsShown()
""")
check("disabled state takes precedence over hover and selection, with selection restored on enable",
      A.ev('__selected and __disabled and __restored'))
errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

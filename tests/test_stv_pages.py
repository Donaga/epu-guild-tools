"""Bank > STV pages: Green Hills of Stranglethorn pages by chapter, requests and officer targets."""
from simcore import *

A = Client('Chris Baker'); B = Client('Tyler Baker')
clients[A.name] = A; clients[B.name] = B
tick(60)
for c in (A, B):
    c.ex('''for _,n in ipairs({1,4,6,8,10,11,14,16,18,20,21,24,25,26,27}) do __ITEMS[2724+n]="Green Hills of Stranglethorn - Page "..n end
__done={}
C_QuestLog=C_QuestLog or {}; C_QuestLog.IsQuestFlaggedCompleted=function(q) return __done[q]==true end
__bags={}
GetItemCount=function(id) return __bags[id] or 0 end
if C_Item then C_Item.GetItemCount=GetItemCount end''')
A.ex('''local g=__ns.G()
g.bank["Epu Bank"]={v=__now,money=0,items={[2725]=2,[2728]=1,[2730]=3,[2732]=1,[2734]=1,[2735]=2,[2740]=1,[2749]=1}}
g.bankStock=g.bankStock or {}
__ns.Send("D",{bank={["Epu Bank"]=g.bank["Epu Bank"]}})''')
tick(10)
B.ex('__bags[2728]=1')
plan = lambda c, expr: c.ev('(function() local p=__ns.StvPlan() return %s end)()' % expr)
check('four chapters with 15 pages', plan(B, '#p.chapters') == 4 and plan(B, '#p.chapters[1].pages+#p.chapters[2].pages+#p.chapters[3].pages+#p.chapters[4].pages') == 15)
check('full sets in the bank are counted per chapter', plan(A, 'p.chapters[1].sets') == 1 and plan(A, 'p.chapters[2].sets') == 0)
check('the pages a chapter is short on are listed', plan(A, 'table.concat(p.chapters[2].short,",")') == '14')
check('pages you carry are not marked as needed', plan(B, 'p.chapters[1].pages[2].mine') == 1 and plan(B, 'p.chapters[1].pages[2].missing') is False)
B.ex('__done[340]=true')
check('a chapter you turned in is marked done', plan(B, 'p.chapters[2].done') is True and plan(B, 'p.chapters[2].pages[1].missing') is False)

B.ex("__ns.UI:Show(); __ns.UI:SetView('bank'); __ns.UI.bankStv:Click()")
rows = B.ev('(function() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.title then t[#t+1]=r.data.title.." | "..(r.data.sub or "") end end return table.concat(t,"\\n") end)()')
check('the STV pages tab lists chapters and pages', 'Chapter I' in rows and 'Page 27' in rows and 'None in the bank' in rows)
check('your missing pages are highlighted', 'you need this' in rows and 'you have 1' in rows)
check('the tab is on and the Bank filters are hidden', B.ev('__ns.UI.bankStv:GetChecked() or __ns.UI.bankStv.on') and not B.ev('__ns.UI.bankCatChip:IsShown()'))
B.ex("__ns.UI:OpenDetails('stvchapter',1)")
labels = lambda c: c.ev('(function() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end)()')
lb = labels(B)
check('chapter details offer the pages you need, preselected', 'Request pages 1, 6, 8' in lb and 'Page 4' in lb)
check('members see no officer buttons', 'Keep 3' not in lb)
n = B.ev("__ns.RequestStvPages({1,6,8},'Chapter I')")
check('requesting makes one request per page', n == 3)
check('requests reach the officer', tick_until(lambda: A.ev('(function() local n=0 for _,r in pairs(__ns.G().requests) do if r.who=="Tyler Baker" and r.note:find("Green Hills",1,true) then n=n+1 end end return n end)()') == 3, 60))
check('a page with no free copy is not requested', B.ev("__ns.RequestStvPages({18},'Chapter III')") == 0)

A.ex("__ns.UI:Show(); __ns.UI:SetView('bank'); __ns.UI.bankStv:Click(); __ns.UI:OpenDetails('stvchapter',1)")
check('officers can set page targets', 'Keep 3 of each page' in labels(A))
A.ex('__ns.SetStvTargets(3)')
check('every page gets a target of 3 in one change', A.ev('(function() local n=0 for id,v in pairs(__ns.G().needs.list) do if id>=2725 and id<=2751 and v==3 then n=n+1 end end return n end)()') == 15)
check('targets sync to members', tick_until(lambda: B.ev('__ns.G().needs.list[2751]') == 3, 60) and plan(B, 'p.targetsSet') is True)
check('Back to the normal bank list clears the tab', (A.ex("__ns.UI.nav.bank:Click()") or True) and A.ev('__ns.UI.state.bank.mode') is None)
check('no runtime errors', all(c.ev('__errors') in (None, 0) for c in (A, B)))
print('STV page tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

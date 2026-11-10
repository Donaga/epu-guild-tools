"""Request menu counts and visible rows must use the same search/ownership scope."""
from simcore import *
A=Client('Chris Baker')
A.ex('''__ns.G().requests={}
for i=1,8 do
  __ns.G().requests['filter-'..i]={who=i<=2 and 'Tyler Baker' or 'Chris Baker',item=2589,qty=1,
    status=i==8 and 'cancelled' or 'filled',t=__now,u=__now,crafter=i==1 and 'Chris Baker' or nil}
end
__ns.UI:Show(); __ns.UI.state.requests.filter='all'; __ns.UI:SetView('requests'); __ns.UI.search:SetText('tyler')
''')
shown='(function() local n=0 for _,r in ipairs(__ns.UI.rows) do if r:IsShown() then n=n+1 end end return n end)()'
def count(value):
    A.ex('__ns.UI.statusChip:GetScript("OnClick")(__ns.UI.statusChip)')
    result=A.ev('(function() for _,r in ipairs(EPUGuildMenu.rows) do if r.value=="'+value+'" then return r.right:GetText() end end end)()')
    A.ex('EPUGuildMenu:Hide()')
    return result
check('search shows two matching requests',A.ev(shown)==2)
check('All menu count matches search results',count('all')=='2')
check('Filled menu count matches search results',count('filled')=='2')
check('footer explains the eight-request total', 'Showing 2 of 8 requests' in A.ev('__ns.UI.footerText:GetText()'))
check('footer names the active search','tyler' in A.ev('__ns.UI.footerText:GetText()'))
check('clear-search control appears with text', A.ev('__ns.UI.clearSearch:IsShown()') is True)
A.ex('__ns.UI.clearSearch:GetScript("OnClick")(__ns.UI.clearSearch)')
check('clearing search restores all eight rows',A.ev(shown)==8)
check('clearing search restores total dropdown count',count('all')=='8')
check('status counts remain correct after clearing',count('filled')=='7')
check('clear control hides when search is empty', A.ev('__ns.UI.clearSearch:IsShown()') is False)
A.ex('__ns.UI.mineChip:GetScript("OnClick")(__ns.UI.mineChip)')
check('Mine scope includes own requests and assigned crafts',A.ev(shown)==7 and count('all')=='7')
A.ex('__ns.UI.craftsChip:GetScript("OnClick")(__ns.UI.craftsChip)')
check('combined Mine and Crafts scopes agree with menu',A.ev(shown)==1 and count('all')=='1')
A.ex('__ns.UI.search:SetText("no such name")')
check('no matching search has zero menu results',A.ev(shown)==0 and count('all')=='0')
check('filtering causes no runtime errors',(A.ev('__errors') or 0)==0)

B=Client('Tyler Baker')
B.ex('''__ns.RegisterMe()
__ns.db.accountChars[__ns.GuildKey()]={['Tyler Baker']=__now,['Pip Baker']=__now-10}
__ns.G().bank.Bank={v=__now,money=0,items={[2589]=20},seen={[2589]=true}}
__ns.UI:Show(); __ns.UI:SetView('requests')
function __submit()
  local ui=__ns.UI;ui.itemBox:SetText('2589');ui.action:Click()
end
''')
check('request composer defaults to the logged-in alt', B.ev('__ns.MyMain()')=='Pip Baker' and B.ev('__ns.UI:ForTarget()')=='Tyler Baker')
B.ex('__submit()')
check('default delivery stays with the requesting character', B.ev('(function() for _,r in pairs(__ns.G().requests) do return r.who=="Tyler Baker" and r.to==nil end end)()'))
B.ex('__ns.UI.forBtn:Click(); EPUGuildMenu.rows[2]:Click(); __submit()')
check('choosing another character sends that recipient on the new request', B.ev('(function() for _,r in pairs(__ns.G().requests) do if r.to=="Pip Baker" then return true end end end)()'))
check('next request defaults back to the logged-in character', B.ev('__ns.UI:ForTarget()')=='Tyler Baker')

A.ex('''__ns.G().requests.delivery={who='Tyler Baker',to='Pip Baker',item=2589,qty=1,status='approved',t=__now,u=__now}
__ns.MailRequest=function(id) local r=__ns.G().requests[id]; __mailed=r.to or r.who end
__ns.UI:OpenDetails('request','delivery')
function __click(label)
  for _, button in ipairs(__ns.UI.details.pools.btn) do
    if button:IsShown() and button.text:GetText()==label then button:Click(); return end
  end
  error('Missing button '..label)
end
__click('Change recipient'); EPUGuildMenu.rows[1]:Click(); __ns.UI:Refresh(); __click('Mail it')
''')
check('an unsaved recipient survives refresh and blocks mail preparation',
      A.ev('__ns.UI.details.toChoice')=='Tyler Baker' and A.ev('__mailed') is None)
A.ex("__click('Save changes'); __click('Mail it')")
check('saving the new recipient enables mail to that character', A.ev('__mailed')=='Tyler Baker')
sys.exit(1 if check.failed else 0)

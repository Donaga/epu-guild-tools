"""Sort the bank: recipe hand-outs, skill-up materials, sell list and Mail to."""
from simcore import *

A = Client('Chris Baker')
tick(10)
A.ex('''
__ITEMS[30010]="Pattern: Red Linen Robe"; __ITEMS[30011]="Red Linen Robe"
__ITEMS[30012]="Pattern: Mooncloth Robe"; __ITEMS[30013]="Mooncloth Robe"
__ITEMS[30014]="Pattern: Linen Belt"; __ITEMS[30015]="Linen Belt"
__cls={[30010]={9,"Tailoring"},[30012]={9,"Tailoring"},[30014]={9,"Tailoring"}}
ITEM_MIN_SKILL="Requires %s (%d)"
local need={[30010]=80,[30012]=250,[30014]=1}
C_TooltipInfo={GetItemByID=function(id) return {lines={{leftText=__ITEMS[id]},{leftText="Requires Level 20"},{leftText="Requires Tailoring ("..need[id]..")"}}} end}
local g=__ns.G()
g.crafters["Tyler Baker"]={t=__now,profs={Tailoring=120}}
g.crafters["Pip Baker"]={t=__now,profs={Tailoring=90}}
g.crafters["Chris Stone"]={t=__now,profs={Tailoring=150}}
g.recipes["Tyler Baker"]={t=__now,profs={Tailoring={rank=120,items={30011,30015}}}}
g.recipes["Pip Baker"]={t=__now,profs={Tailoring={rank=90,items={2996,30015},diff={["item:2996"]="o"}}}}
g.recipes["Chris Stone"]={t=__now,profs={Tailoring={rank=150,items={30015}}}}
g.mats["item:2996"]={t=__now,by="Pip Baker",r={2589,2}}
g.needs.list[4306]=10; g.needs.list[14047]=2
g.bank["Epu Bank"]={v=__now,money=0,items={[30010]=1,[30012]=1,[30014]=2,[2589]=40,[14047]=5,[4306]=5}}
__ns.recipeIndex=nil
__plan=__ns.BankSortPlan()
function __find(list,id) for _,r in ipairs(__plan[list]) do if r.item==id then return r end end end
''')
check('the required skill is read from the recipe tooltip', A.ev('__ns.RecipeRequirement(30010)') == ('Tailoring', 80))
check('a recipe goes to the highest-skill guildmate who lacks it',
      A.ev('__find("recipes",30010).give.who') == 'Chris Stone' and A.ev('__find("recipes",30010).best~=nil'))
check('someone who already knows it is never suggested',
      A.ev('(function() for _,c in ipairs(__find("recipes",30010).candidates) do if c.who=="Tyler Baker" then return c.knows end end end)()'))
check('when nobody can learn it yet, the closest guildmate is named',
      A.ev('__find("recipes",30012).give.who') == 'Chris Stone' and 'needs 250' in A.ev('__find("recipes",30012).why'))
check('a recipe the whole guild knows goes to the sell list',
      A.ev('__find("sell",30014)~=nil') and 'already knows it' in A.ev('__find("sell",30014).reason'))
check('materials show who can skill up with them', A.ev('__find("mats",2589).users[1].who') == 'Pip Baker'
      and A.ev('__find("mats",2589).users[1].color') == 'o')
check('only surplus over the needs target is sold', A.ev('__find("sell",14047).surplus') == 3 and A.ev('__find("sell",4306)') is None)

A.ex("""__keep=__ns.G().recipes["Chris Stone"]; __ns.G().recipes["Chris Stone"]=nil; __ns.recipeIndex=nil; __plan=__ns.BankSortPlan()""")
check("someone who hasn't shared recipes ranks after a confirmed candidate",
      A.ev('__find("recipes",30010).give.who') == 'Pip Baker'
      and A.ev('(function() for _,c in ipairs(__find("recipes",30010).candidates) do if c.who=="Chris Stone" then return not c.scanned end end end)()'))
A.ex("__ns.UI:Show(); __ns.UI.bankPlan=nil; __ns.UI:OpenDetails('banksort',30010)")
check("details put a confirmed learner ahead of an unscanned higher-skill guildmate",
      A.ev("(function() for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then return b.text:GetText() end end end)()") == "Mail to Pip")
A.ex("""__ns.G().recipes["Chris Stone"]=__keep; __ns.recipeIndex=nil""")
A.ex("__ns.UI:Show(); __ns.UI:SetView('bank'); __ns.UI.state.bank.mode='sort'; __ns.UI.bankPlan=nil; __ns.UI:Refresh()")
rows = A.ev('''(function() local t={}
  for _,row in ipairs(__ns.UI.rows) do if row:IsShown() and row.data then t[#t+1]=(row.data.title or "").."|"..(row.data.sub or "") end end
  return table.concat(t,"\\n") end)()''')
check('the sort view has the three sections', all(s in rows for s in ('Recipes to hand out', 'Materials guildmates can use', 'Sell')))
check('recipe rows say who to give them to', 'Give to Chris' in rows)
A.ex("__ns.UI:OpenDetails('banksort',30010)")
labels = A.ev('''(function() local t={}
  for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end
  return table.concat(t,"|") end)()''')
check('details offer Mail to the best guildmate first', labels.startswith('Mail to Chris') and 'Mail to Pip' in labels)
A.ex("__log={}; __ns.MailBankItem('Pip Baker',30010,1)")
check('mailing without a mailbox open explains what to do', any('Open a mailbox' in str(m) for m in A.ev('__log').values()))
A.ex("__ns.UI.state.bank.mode=nil; __ns.UI:Refresh()")
check('Back returns to the normal bank list', A.ev('__ns.UI.bankCatChip:IsShown()'))
fits = A.ev('(function() __ns.UI:SetView("bank") local b=__ns.UI.bars.bank return b.leftX+b.rightX end)()')
check('the bank toolbar still fits the smallest window (%s)' % fits, fits <= 480)


# Material hand-outs require an explicit quantity and protect current reserves.
A.ex("""
__bags[0]={{2589,40}}; MailFrame._shown=true
GetItemCount=function(id) local n=0 for _,bag in pairs(__bags) do for _,slot in pairs(bag) do if slot[1]==id then n=n+slot[2] end end end return n end
local g=__ns.G()
g.needs.list[2589]=10
g.requests.reserved={who='Tyler Baker',item=2589,qty=5,status='approved',t=__now,u=__now}
__ns.UI.bankPlan=nil
__ns.UI:OpenDetails('banksort',2589)
function __mailAmount() local n=0 for _,s in pairs(__mailSlots) do n=n+s[2] end return n end
function __clickMaterialMail()
  for _,b in ipairs(__ns.UI.details.pools.btn) do
    if b:IsShown() and b.text:GetText():find('Mail to',1,true) then b:GetScript('OnClick')(b); return end
  end
end
""")
check('material details default to a deliberate single-item quantity',
      A.ev('__ns.UI.details.pools.box[1]:GetText()')=='1')
check('bank mail limit preserves needs and open requests',A.ev('__ns.BankSortMailLimit(2589)')==25)
A.ex("__ns.UI.details.pools.box[1]:SetText('3'); __clickMaterialMail()")
check('material button attaches the entered quantity, not all carried stock',
      A.ev('__mailAmount()')==3 and A.ev('GetItemCount(2589)')==37)
A.ex("__clickMaterialMail()")
check('repeated material preparation preserves the existing draft',A.ev('__mailAmount()')==3)
A.ex("__mailSlots={}; SendMailNameEditBox:SetText(''); SendMailSubjectEditBox:SetText(''); __ns.UI.details.pools.box[1]:SetText('100'); __clickMaterialMail()")
check('over-limit quantity leaves an empty draft untouched',
      A.ev('__mailAmount()')==0 and A.ev('SendMailNameEditBox:GetText()')=='')
for value in ('nil','0','-1','1.5','0/0'):
    A.ex("__ns.MailBankItem('Pip Baker',2589,"+value+")")
    check('invalid or omitted quantity cannot attach all stock: '+value,A.ev('__mailAmount()')==0)
A.ex("__ns.G().requests.reserved.qty=30; __ns.G().bank['Epu Bank'].items[2589]=999; __ns.UI.details.pools.box[1]:SetText('1'); __clickMaterialMail()")
check('stale detail controls recheck new reservations and ignore stale remote quantities',
      A.ev('__mailAmount()')==0 and A.ev('GetItemCount(2589)')==37)
A.ex("__ns.G().requests.reserved.qty=5; __ns.MailBankItem('Pip Baker',2589,22)")
check('explicit surplus can be mailed without taking reserved stock',
      A.ev('__mailAmount()')==22 and A.ev('GetItemCount(2589)')==15)
A.ex("__mailSlots={}; SendMailNameEditBox:SetText(''); __ns.MailBankItem('Pip Baker',2589,1)")
check('a later mail cannot spend the protected remainder',A.ev('__mailAmount()')==0)
check('mail preparation does not fulfill the reserved request',
      A.ev('__ns.G().requests.reserved.status')=='approved')


# Missing requirement metadata is uncertainty, not permission to learn.
A.ex("""
__ITEMS[30016]='Pattern: Unverified Robe'; __cls[30016]={9,'Tailoring'}
__ns.G().bank['Epu Bank'].items[30016]=1
__oldTooltip=C_TooltipInfo.GetItemByID
C_TooltipInfo.GetItemByID=function(id)
  if id==30016 then return {lines={{leftText='Pattern: Unverified Robe'}}} end
  return __oldTooltip(id)
end
__ns.recipeIndex=nil; __plan=__ns.BankSortPlan()
""")
check('unknown required skill produces an unverified recommendation',
      A.ev('__find("recipes",30016).unverified') and A.ev('__find("recipes",30016).best') is None)
check('unknown requirement never marks a candidate as able to learn',
      A.ev('(function() for _,c in ipairs(__find("recipes",30016).candidates) do if c.canLearn then return false end end return true end)()'))
check('unverified recipe is retained rather than treated as an unwanted sell item',
      A.ev('__find("sell",30016)') is None)
A.ex("__ns.UI.bankPlan=nil; __ns.UI:OpenDetails('banksort',30016)")
check('unverified recipe details offer no automatic mail recommendation',
      A.ev('(function() for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText():find("Mail to",1,true) then return false end end return true end)()'))
check('unverified recipe row asks for a check rather than claiming learnability',
      A.ev('(function() for _,r in ipairs(__ns.UI.BankSortRows("")) do if r.item==30016 then return r.sub:find("Check with",1,true)~=nil and r.sub:find("required skill unknown",1,true)~=nil end end return false end)()'))
A.ex("""
C_TooltipInfo.GetItemByID=function(id)
  if id==30016 then return {lines={{leftText='Requires Tailoring (80)'}}} end
  return __oldTooltip(id)
end
__plan=__ns.BankSortPlan()
""")
check('newly available requirement metadata restores a verified recommendation',
      A.ev('__find("recipes",30016).best.who')=='Chris Stone' and not A.ev('__find("recipes",30016).unverified'))
check('recipe recommendation changes produce no runtime errors',(A.ev('__errors') or 0)==0)

print('Bank sort tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

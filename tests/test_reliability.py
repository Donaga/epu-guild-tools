"""Regressions for the review findings, projects and onboarding."""
from simcore import *

A=clients['Chris Baker']=Client('Chris Baker')
B=clients['Tyler Baker']=Client('Tyler Baker')
tick(20)
A.ex('''local g=__ns.G(); for _,id in ipairs({'delivery-a','delivery-b'}) do
g.requests[id]={who='Tyler Baker',item=2589,qty=20,status='approved',t=__now,u=__now} end
__ns.AutoFillFor('Tyler Baker',{{2589,1}})''')
check('partial delivery leaves both requests open', A.ev('__ns.G().requests["delivery-a"].status')=='approved' and A.ev('__ns.G().requests["delivery-b"].status')=='approved')
check('one delivered item is allocated once', A.ev('(__ns.G().requests["delivery-a"].delivered or 0)+(__ns.G().requests["delivery-b"].delivered or 0)')==1)
A.ex('__ns.AutoFillFor("Tyler Baker",{{2589,19}},"delivery-a")')
check('exact completion closes only the selected request', A.ev('__ns.G().requests["delivery-a"].status')=='filled' and A.ev('__ns.G().requests["delivery-b"].delivered') is None)
A.ex('__ns.EditRequest("delivery-a",{status="approved"})')
check('reopening resets credit and preserves delivery history', A.ev('__ns.Remaining(__ns.G().requests["delivery-a"])')==20 and A.ev('#__ns.G().requests["delivery-a"].deliveries')==2)
A.ex('''local g=__ns.G(); g.requests.victim={who='Pip Baker',item=2589,qty=20,status='approved',t=__now,u=__now}
__ns.Merge('Tyler Baker',{req={victim={who='Tyler Baker',item=14047,qty=9,status='pending',t=__now,u=__now+1}}})''')
check('member cannot overwrite another request ID', A.ev('__ns.G().requests.victim.who')=='Pip Baker')
A.ex('''__ns.Merge('Tyler Baker',{req={invalid={who='Tyler Baker',item=2589,qty=-9,status='pending',u=__now}}})''')
check('negative quantities rejected at receive boundary', A.ev('__ns.G().requests.invalid') is None)
A.ex('''__ns.Merge('Tyler Baker',{req={future={who='Tyler Baker',item=2589,qty=9,status='pending',u=__now+999999}}})''')
check('future revision poisoning rejected', A.ev('__ns.G().requests.future') is None)
A.ex('''local g=__ns.G(); g.requests.locked={who='Tyler Baker',item=2589,qty=20,status='approved',t=__now,u=__now}
__ns.Merge('Tyler Baker',{req={locked={who='Tyler Baker',item=2589,qty=200,status='pending',t=__now,u=__now+1}}})''')
check('member cannot turn an approved request back into a pending edit', A.ev('__ns.G().requests.locked.qty')==20)

# Two officers editing unrelated items merge, including equal-second revisions.
for c in [A,B]:
    c.ex('''__ns.G().needs={v=0,list={}}
__ns.Merge('Chris Baker',{needs={v=__now,list={[2589]=20},entries={[2589]={v=__now,by='Chris Baker',value=20}}}})
__ns.Merge('Epu Bank',{needs={v=__now,list={[4306]=10},entries={[4306]={v=__now,by='Epu Bank',value=10}}}})''')
check('independent needs edits survive', A.ev('__ns.G().needs.list[2589]')==20 and A.ev('__ns.G().needs.list[4306]')==10)
A.ex('''__ns.Merge('Epu Bank',{needs={v=__now,list={},entries={[2589]={v=__now+1,by='Epu Bank'}}}})
__ns.Merge('Chris Baker',{needs={v=__now,list={[2589]=20},entries={[2589]={v=__now,by='Chris Baker',value=20}}}})''')
check('deletion tombstone blocks stale resurrection', A.ev('__ns.G().needs.list[2589]') is None)
same1="{v=__now+2,list={},entries={[4306]={v=__now+2,by='Chris Baker',value=40}}}"
same2="{v=__now+2,list={},entries={[4306]={v=__now+2,by='Epu Bank',value=50}}}"
A.ex(f"__ns.Merge('Chris Baker',{{needs={same1}}}); __ns.Merge('Epu Bank',{{needs={same2}}})")
B.ex(f"__ns.Merge('Epu Bank',{{needs={same2}}}); __ns.Merge('Chris Baker',{{needs={same1}}})")
check('opposite-order equal-stamp edits converge', A.ev('__ns.G().needs.list[4306]')==B.ev('__ns.G().needs.list[4306]'))

A.ex('''local id=__ns.G().altVerified['Chris Baker'].id
__ns.Merge('Tyler Baker',{altVerified={['Tyler Baker']={id=id,t=__now+5,chars={'Tyler Baker','Chris Baker'}}}})
__ns.Merge('Tyler Baker',{alts={[id]={main='Tyler Baker',chars={'Tyler Baker','Chris Baker'},t=__now+6}}})''')
check('knowing an account ID cannot claim another character', A.ev('__ns.MainOf("Chris Baker")')=='Chris Baker')
A.ex("__ns.Merge('Tyler Baker',{altVerified={['Chris Baker']={id='fake',t=__now+7}}})")
check('member cannot publish another character proof', A.ev('__ns.G().altVerified["Chris Baker"].id')!='fake')

# Bank replies may be delayed; an unloaded tab is not a completed empty scan.
A.ex('__delayGuildBank=true; __gb[1]={{2589,20}}; __gb[2]={{4306,8}}; __fire("GUILDBANKFRAME_OPENED")')
check('pending bank query is not published', A.ev('__ns.G().bank["Guild Bank"]') is None)
A.ex('__fire("GUILDBANKBAGSLOTS_CHANGED"); __advance(0.6)')
check('one loaded tab is not a complete inventory', A.ev('__ns.G().bank["Guild Bank"]') is None)
A.ex('__fire("GUILDBANKBAGSLOTS_CHANGED")')
check('all replies produce the full inventory', A.ev('__ns.BankCount(4306)')==8)
A.ex('__gb[2]={}; __fire("GUILDBANKBAGSLOTS_CHANGED")')
check('empty offscreen loaded tab clears old stock', A.ev('__ns.BankCount(4306)')==0)
A.ex('__fire("GUILDBANKFRAME_CLOSED")')

# Reassembly: out-of-order and duplicate parts are safe; invalid/unbounded input isn't retained.
A.ex('''__probe=0; __ns.comm.Z=function(_,data) if data.ok then __probe=__probe+1 end end
local s='Z'..__ns.Serialize({ok=true}); local a=s:sub(1,4); local b=s:sub(5)
__ns.HandleAddonMessage(__ns.PREFIX,'P900:2:2:'..b,'GUILD','Tyler Baker')
__ns.HandleAddonMessage(__ns.PREFIX,'P900:2:2:'..b,'GUILD','Tyler Baker')
__ns.HandleAddonMessage(__ns.PREFIX,'P900:1:2:'..a,'GUILD','Tyler Baker')''')
check('out-of-order fragments assemble once', A.ev('__probe')==1)
A.ex("__ns.HandleAddonMessage(__ns.PREFIX,'P901:0:999999:x','GUILD','Tyler Baker')")
check('invalid fragment counts do not allocate', A.ev('__ns.PartialCount()')==0)
A.ex("for i=1,20 do __ns.HandleAddonMessage(__ns.PREFIX,'P'..i..':1:2:x','GUILD','Tyler Baker') end")
check('partial buffers are bounded per sender', A.ev('__ns.PartialCount()')==4)
A.ex('__advance(1840)')
check('incomplete transfers expire', A.ev('__ns.PartialCount()')==0)
check('deeply nested data rejected safely', A.ev('(function() return pcall(__ns.Deserialize,string.rep("{$a;",30).."T"..string.rep("}",30)) end)()')[0] is False)

# New features use the same authenticated, persistent sync as existing records.
A.ex("__ns.G().recipes['Tyler Baker']={t=__now,profs={Tailoring={items={30001},rank=150}}}; __ns.recipeIndex=nil; __ns.G().mats['item:30001']={t=__now,r={2589,6}}")
pid=A.ev('__ns.CreateProject("Bags for recruits","Two bags for new members")')
check('officer creates a crafting project', pid is not None)
check('member cannot create a project', B.ev('__ns.CreateProject("Fake","")') is None)
rid=A.ev(f'__ns.AddProjectTask("{pid}","item:30001","Tyler Baker",2,"Newbie Stone")')
check('project task creates a real craft request', rid is not None and A.ev(f'__ns.G().requests["{rid}"].project')==pid)
check('project calculates recipe materials', A.ev(f'__ns.ProjectMaterials(__ns.G().projects["{pid}"])[2589]')==12)
A.ex(f'__ns.StockProject("{pid}")')
check('project can raise existing bank needs', A.ev('__ns.NeedEntry(__ns.G().needs.list[2589])')==(12,'restock'))
A.ex(f'__ns.EditRequest("{rid}",{{status="filled"}})')
check('project progress follows completed requests', A.ev(f'__ns.ProjectProgress(__ns.G().projects["{pid}"])')==(2,2))
A.ex(f'__ns.Prune(__ns.G())')
check('project request history is retained', A.ev(f'__ns.G().requests["{rid}"]') is not None)
A.ex('__ns.SetOnboardingStep("rules","Read our rules","Ask Donaga for the rules",false)')
check('checklist instructions configurable', A.ev('__ns.OnboardingSteps()[6].title') is not None)
check('member can complete their own step', B.ev('__ns.SetChecklist("Tyler Baker","rules",true,"Read")') is True)
check('member cannot verify their own Discord identity', B.ev('__ns.SetChecklist("Tyler Baker","discord",true,"claimed")') is False)
check('member cannot complete another person checklist', B.ev('__ns.SetChecklist("Chris Baker","rules",true,"")') is False)
A.ex('__ns.SetChecklist("Tyler Baker","mentor",true,"Mentor: Chris Baker; starter bags supplied")')
tick(50)
check('project sync reaches members', B.ev(f'__ns.PlanningStore().projects["{pid}"].title')=='Bags for recruits')
check('member checklist progress reaches officers', A.ev('__ns.PlanningStore().onboarding["Tyler Baker\\031rules"].done') is True)
check('mentor assignment reaches the member', B.ev('__ns.PlanningStore().onboarding["Tyler Baker\\031mentor"].note')=='Mentor: Chris Baker; starter bags supplied')
for c in [A,B]:
    c.ex('__ns.UI:Show(); __ns.UI:SetView("projects")')
    c.ex(f'__ns.UI:OpenDetails("project","{pid}")')
    c.ex('__ns.UI:SetView("onboarding"); __ns.UI:OpenDetails("checklist","Tyler Baker")')
    c.ex('__ns.UI:OpenDetails("editstep","rules")')
check('new feature screens render without runtime errors', sum(c.ev('__errors') or 0 for c in [A,B])==0)
sys.exit(1 if check.failed else 0)

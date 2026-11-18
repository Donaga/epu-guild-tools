"""Bank managers: a guild-wide, officer-chosen trust level for the bank side only."""
from simcore import *
for name in ['Chris Baker','Tyler Baker','Pip Baker']: clients[name]=Client(name)
tick(120)
A,B,C=(clients[n] for n in ['Chris Baker','Tyler Baker','Pip Baker'])
check('a member is not a bank manager by default', not C.ev('__ns.IsBankTrusted("Tyler Baker")') and not B.ev('__ns.IsBankTrusted(__ns.me)'))
B.ex('__ns.SetNeed(2589, 40)'); tick(10)
check("a member's needs change is refused", C.ev('__ns.G().needs.list[2589] == nil'))
# a member cannot make himself a bank manager
B.ex('__ns.SetBankManagers({member=true},{})')
B.ex('local g=__ns.G(); g.policy.bankChars={["Tyler Baker"]=true}; g.policy.v=__ns.NextVersion(g.policy.v); __ns.Send("D",{policy=g.policy}); g.policy.bankChars={}'); tick(10)
check('members cannot grant themselves bank manager', not C.ev('__ns.IsBankTrusted("Tyler Baker")'))
# an officer adds Tyler by name
A.ex('__ns.SetBankManagers({},{["Tyler Baker"]=true})'); tick(10)
check('an officer choice reaches everyone', C.ev('__ns.IsBankTrusted("Tyler Baker")') and B.ev('__ns.IsBankTrusted(__ns.me)'))
check('a bank manager is not a full officer', not C.ev('__ns.IsTrusted("Tyler Baker")'))
B.ex('__ns.SetNeed(2589, 40)'); tick(10)
check("a bank manager's needs change is accepted as verified", C.ev('__ns.G().needs.list[2589] ~= nil'))
B.ex('__ns.PostNews("Hello","from a bank manager")'); tick(10)
check('a bank manager cannot post announcements', C.ev('(function() for _,e in pairs(__ns.G().news or {}) do if e.title=="Hello" then return true end end return false end)()') is False)
B.ex('__ns.SetBankManagers({},{["Pip Baker"]=true})'); tick(10)
check('a bank manager cannot add other bank managers', not C.ev('__ns.IsBankTrusted("Pip Baker")'))
# by rank
A.ex('__ns.SetBankManagers({member=true},{})'); tick(10)
check('a whole rank can be bank managers', C.ev('__ns.IsBankTrusted("Pip Baker")') and C.ev('__ns.IsBankTrusted("Tyler Baker")') and not C.ev('__ns.IsBankTrusted("Newbie Stone")'))
# officer panel
A.ex('__ns.UI:Show(); __ns.UI:OpenDetails("bankmanagers","guild")')
lb = A.ev('(function() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end)()')
check('officers choose ranks and characters in the panel', '[x] Member' in lb and '[ ] Veteran' in lb and 'Add' in lb)
check('officer ranks are not offered as bank ranks', 'Officer' not in lb.replace('Officer tab',''))
print('Bank manager tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

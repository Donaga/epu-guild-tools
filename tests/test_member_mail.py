"""Multiple approved bank requests share a draft and actual delivery accounting."""
from simcore import *
def setup(name='Chris Baker'):
    c=Client(name)
    c.ex('''__advance(120); MailFrame._shown=true; __ns.cdb.bankAlt=true
local g=__ns.G(); g.requests={
 a={who='Tyler Baker',item=2589,qty=5,delivered=2,status='approved',t=__now-4,u=__now},
 b={who='Tyler Baker',item=4306,qty=4,status='approved',t=__now-3,u=__now},
 c={who='Tyler Baker',item=2589,qty=2,status='approved',t=__now-2,u=__now},
 other={who='Pip Baker',item=2589,qty=10,status='approved',t=__now,u=__now},
 pending={who='Tyler Baker',item=2589,qty=10,status='pending',t=__now,u=__now},
 craft={who='Tyler Baker',item=2589,qty=10,crafter='Pip Baker',status='approved',t=__now,u=__now}}
__bags[0]={{2589,20},{4306,20}}
function __attached(id) local n=0 for _,v in pairs(__mailSlots) do if not id or id==v[1] then n=n+v[2] end end return n end
''')
    return c
A=setup()
check('plan includes only approved bank requests for exact recipient',A.ev("#__ns.MemberMailPlan('Tyler Baker')")==3)
A.ex("__ns.MailMemberRequests('Tyler Baker')")
check('one draft contains both different requested items',A.ev('__attached(2589)')==5 and A.ev('__attached(4306)')==4)
check('same-item requests share one attachment when stack allows',A.ev('#__mailSlots')==2)
check('whole inventory stacks are not sent',A.ev('__bags[0][1][2]')==15 and A.ev('__bags[0][2][2]')==16)
check('mail preparation does not mark requests delivered',A.ev('__ns.G().requests.a.delivered')==2 and A.ev('__ns.G().requests.b.delivered') is None)
A.ex("__ns.MailMemberRequests('Tyler Baker')")
check('repeated fill preserves draft instead of doubling attachments',A.ev('__attached()')==9)
A.ex("SendMail('Tyler Baker'); __advance(1)")
check('one successful mail fulfils all selected requests',A.ev("__ns.G().requests.a.status=='filled' and __ns.G().requests.b.status=='filled' and __ns.G().requests.c.status=='filled'"))
check('unrelated recipient pending and craft requests stay unchanged',A.ev("__ns.G().requests.other.delivered==nil and __ns.G().requests.pending.status=='pending' and __ns.G().requests.craft.delivered==nil"))
check('successful send clears both mail tracking modes',A.ev('__ns.mailRequestID==nil and __ns.mailRequestIDs==nil'))
B=setup(); B.ex("__bags[0]={{2589,4}}; __ns.MailMemberRequests('Tyler Baker'); SendMail('Tyler Baker'); __advance(1)")
check('partial stock fulfils oldest same-item request first',B.ev('__ns.G().requests.a.delivered')==5 and B.ev('__ns.G().requests.c.delivered')==1)
check('missing items and remainders stay open',B.ev("__ns.G().requests.b.status=='approved' and __ns.G().requests.c.status=='approved'"))
C=setup();C.ex("__ns.MailMemberRequests('Tyler Baker'); __mailSlots[1][2]=2; __fire('MAIL_SEND_INFO_UPDATE')")
check('changed attachment quantities are rejected by shared safeguards',C.ev('__attached(2589)')==0)
D=setup();D.ex("__ns.MailMemberRequests('Tyler Baker'); SendMail('Pip Baker'); __advance(1)")
check('changing recipient cannot fulfil somebody else requests',D.ev('__ns.G().requests.other.delivered') is None and D.ev('__ns.G().requests.a.delivered')==2)
E=setup();E.ex("__ns.MailMemberRequests('Tyler Baker'); __ns.G().requests.later={who='Tyler Baker',item=4306,qty=10,status='approved',t=__now-10,u=__now}; SendMail('Tyler Baker'); __advance(1)")
check('requests arriving after preparation cannot consume the draft',E.ev('__ns.G().requests.later.delivered') is None and E.ev('__ns.G().requests.b.status')=='filled')
F=setup();F.ex("__mailSlots[1]={14047,8}; SendMailNameEditBox:SetText('Pip Baker'); __ns.MailMemberRequests('Tyler Baker')")
check('existing attachments and recipient are preserved',F.ev('__attached(14047)')==8 and F.ev('SendMailNameEditBox:GetText()')=='Pip Baker')
G=setup('Tyler Baker');G.ex("__ns.MailMemberRequests('Tyler Baker')")
check('ordinary guild member cannot prepare officer bank fulfilment',G.ev('__attached()')==0)
H=setup();H.ex("ATTACHMENTS_MAX_SEND=1; __ns.MailMemberRequests('Tyler Baker'); SendMail('Tyler Baker'); __advance(1)")
check('attachment limit leaves additional item requests open',H.ev('__ns.G().requests.b.status')=='approved' and H.ev('__ns.G().requests.a.status')=='filled')
I=setup();I.ex("""__ns.MailMemberRequests('Tyler Baker'); local after=C_Timer.After
C_Timer.After=function(d,fn) if d~=0.1 then after(d,fn) end end
SendMail('Tyler Baker'); C_Timer.After=after; __fire('MAIL_FAILED'); __advance(1)""")
check('failed mail does not mark requests delivered',I.ev('__ns.G().requests.a.delivered')==2 and I.ev('__ns.G().requests.b.delivered') is None)
I.ex("SendMail('Tyler Baker'); __advance(1)")
check('retrying a failed draft retains its selected requests',I.ev('__ns.G().requests.b.status')=='filled')
J=setup();J.ex("MailFrame._shown=false; __ns.MailMemberRequests('Tyler Baker')")
check('combined mail requires the mailbox',J.ev('__attached()')==0)
K=setup();K.ex("__ns.UI:Show(); __ns.UI:OpenDetails('membermail','Tyler Baker')")
check('combined draft preview renders without errors',(K.ev('__errors') or 0)==0 and K.ev('__ns.UI.details.title:GetText()')=='Fill mail for member')
print('Combined member mail tests:',check.failed,'failed')
sys.exit(1 if check.failed else 0)

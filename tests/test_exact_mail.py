"""Bank request mail must reflect the requested remainder, never an unchecked stack."""
from simcore import *
def prepare(qty=3,stack=20,delivered=0):
    c=Client('Chris Baker')
    c.ex('__advance(60); MailFrame._shown=true; __ns.cdb.bankAlt=true')
    c.ex(f'''__bags[0]={{{{2589,{stack}}}}}; __ns.G().requests.mailtest={{who='Tyler Baker',item=2589,qty={qty},delivered={delivered},status='approved',t=__now,u=__now}}''')
    return c
def amount(c):return c.ev('(function() local n=0 for _,s in pairs(__mailSlots) do n=n+s[2] end return n end)()')
A=prepare();A.ex('__ns.MailRequest("mailtest")')
check('bank alt prepares three from a stack of twenty',amount(A)==3 and A.ev('__bags[0][1][2]')==17)
check('preparing a mail does not mark the request filled',A.ev('__ns.G().requests.mailtest.status')=='approved')
A.ex('__ns.MailRequest("mailtest")')
check('repeating preparation does not accumulate or swap stacks',amount(A)==3 and A.ev('__bags[0][1][2]')==17)
B=prepare(5,20,2);B.ex('__ns.MailRequest("mailtest")')
check('partial fulfillment attaches only the remainder',amount(B)==3 and 'x3' in B.ev('SendMailSubjectEditBox:GetText()'))
C=prepare();C.ex('__mailSlots[1]={4306,8}; SendMailNameEditBox:SetText("Newbie Stone"); __ns.MailRequest("mailtest")')
check('existing draft attachments are preserved',C.ev('__mailSlots[1][1]')==4306 and amount(C)==8)
check('existing draft recipient is not silently changed',C.ev('SendMailNameEditBox:GetText()')=='Newbie Stone')
D=prepare();D.ex('''local read=C_Container.GetContainerItemInfo; C_Container.GetContainerItemInfo=function(...) local i=read(...); if i then i.stackCount=nil end; return i end
__ns.MailRequest('mailtest')''')
check('unknown quantities never fall back to picking up the whole stack',amount(D)==0 and D.ev('__bags[0][1][2]')==20)
E=prepare();E.ex('''local read=C_Container.GetContainerItemInfo; C_Container.GetContainerItemInfo=function(...) local i=read(...); if i then i.isLocked=true end; return i end
__ns.MailRequest('mailtest')''')
check('locked stacks are not picked up',amount(E)==0 and E.ev('__bags[0][1][2]')==20)
F=prepare();F.ex('C_Container.SplitContainerItem=function() end; __ns.MailRequest("mailtest")')
check('failed split stops without attaching a stack',amount(F)==0 and F.ev('__bags[0][1][2]')==20)
G=prepare();G.ex('C_Container.SplitContainerItem=function(b,s,n) C_Container.PickupContainerItem(b,s) end; __ns.MailRequest("mailtest")')
check('whole-stack result from a bad split is removed',amount(G)==0 and G.ev('__bags[0][1][2]')==20)
H=prepare();H.ex('''__ns.MailRequest('mailtest'); __mailSlots[1][2]=20; __bags[0][1]=nil; __cursor_origin={0,1}; __fire('MAIL_SEND_INFO_UPDATE')''')
check('later mail-addon restacking is caught and detached',amount(H)==0 and H.ev('__bags[0][1][2]')==20)
check('guard rejection leaves the request open',H.ev('__ns.G().requests.mailtest.status')=='approved')
I=prepare(10,0);I.ex('__bags[0]={{2589,4},{2589,12}}; __ns.MailRequest("mailtest")')
check('exact quantity can span two inventory stacks',amount(I)==10 and I.ev('__bags[0][2][2]')==6)
J=prepare(5,20,2);J.ex('''local r=__ns.G().requests.mailtest; r.crafter='Tyler Baker'; r.key='item:30001'
__ns.G().mats[r.key]={t=__now,r={2589,2}}; __ns.MailCraftMats('mailtest')''')
check('craft materials use the undelivered remainder',amount(J)==6 and 'x3' in J.ev('SendMailSubjectEditBox:GetText()'))
check('no runtime errors',sum(c.ev('__errors') or 0 for c in [A,B,C,D,E,F,G,H,I,J])==0)
sys.exit(1 if check.failed else 0)

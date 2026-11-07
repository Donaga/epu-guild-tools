"""Donations scan and move eligible items from every carried container."""
from simcore import *
B=Client('Tyler Baker')
B.ex('''__advance(30); Enum.BagIndex={Backpack=0,Bag_1=1,Bag_2=2,Bag_3=3,Bag_4=4,ReagentBag=5,CharacterBankTab_1=6}
__ns.G().bank['Epu Bank']={v=__now,items={},money=0}
__ns.G().needs.list[2589]=100
MailFrame._shown=true
__bags[0]={}; __bags[5]={{2589,17},{4306,3,true}}; __bags[6]={{2589,99}}
__ns.ShowDonate('mail')''')
def carry():return B.ev('(function() for _,e in ipairs(__ns.DonatePanel.entries) do if e.id==2589 then return e.carry end end return 0 end)()')
check('reagent-bag-only items appear in the Donate panel',carry()==17)
check('stored bank items are not offered as carried donations',carry()!=116)
check('soulbound reagent-bag items remain excluded',B.ev('(function() for _,e in ipairs(__ns.DonatePanel.entries) do if e.id==4306 then return false end end return true end)()') is True)
B.ex('__ns.DonatePanel.pick[2589]=9; __ns.FillDonation()')
check('mail donation attaches from the reagent bag',B.ev('__mailSlots[1][1]')==2589 and B.ev('__mailSlots[1][2]')==9)
check('partial reagent stack is split accurately',B.ev('__bags[5][1][2]')==8)
B.ex('''__mailSlots={}; __bags[0]={{2589,4}}; __bags[5]={{2589,7}}; NUM_BAG_SLOTS=5
__ns.DonatePanel:Update()''')
check('regular and reagent stacks are combined without double-counting',carry()==11)
B.ex('__ns.DonatePanel.pick[2589]=10; __ns.FillDonation()')
check('mail donation can span regular and reagent bags',B.ev('__mailSlots[1][2]+__mailSlots[2][2]')==10 and B.ev('__bags[5][1][2]')==1)
B.ex('''NUM_BAG_SLOTS=4; __bags[0]={}; __bags[5]={{2589,7}}; __gb={{},{}}; __placed={}
PickupGuildBankItem=function(tab,slot) if __cursor then __placed[#__placed+1]={__cursor[1],__cursor[2]}; __gb[tab][slot]={__cursor[1],__cursor[2]}; __cursor=nil end end
__ns.ShowDonate('vault'); __ns.DonatePanel.pick[2589]=5; __ns.DepositDonation(); __advance(2)''')
check('vault donation moves items from the reagent bag',B.ev('__placed[1][1]')==2589 and B.ev('__placed[1][2]')==5)
check('vault donation leaves the unselected reagent quantity',B.ev('__bags[5][1][2]')==2)
B.ex('''Enum.BagIndex=nil; NUM_BAG_SLOTS=4; __bags[0]={{2589,4}}; __bags[5]={{2589,99}}
__ns.ShowDonate('mail')''')
check('old bag layout does not mistake bank bag five for a reagent bag',carry()==4)
check('no runtime errors',(B.ev('__errors') or 0)==0)
sys.exit(1 if check.failed else 0)

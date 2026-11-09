"""Hide historical equipment and exercise actual stock/quality bank filters."""
from simcore import *
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'epu-discord'))
import epu_core as core
A=Client('Chris Baker'); A.ex("""__advance(120)
__ITEMS[118]='Healing Potion'; __ITEMS[2447]='Peacebloom'; __ITEMS[4496]='Small Brown Pouch'
__cls={[30001]={2,'Sword'},[30002]={4,'Cloth'},[118]={0,'Potion'},[2447]={7,'Herb'},[4496]={1,'Bag'}}
__qual={[30001]=2,[30002]=3,[2589]=1,[118]=1,[2447]=2,[4496]=1}
local g=__ns.G(); g.bank={Bank={v=__now,money=0,items={[30001]=1,[2589]=10,[118]=5},seen={[30001]=true,[30002]=true,[2589]=true,[118]=true,[2447]=true,[4496]=true}}}
g.requests={cloth={who='Tyler Baker',item=2589,qty=10,status='approved',t=__now,u=__now},potion={who='Tyler Baker',item=118,qty=2,status='pending',t=__now,u=__now},oldgear={who='Tyler Baker',item=30002,qty=1,status='pending',t=__now,u=__now}}
__ns.UI:Show(); __ns.UI:SetView('bank')
function __shown() local out={} for _,row in ipairs(__ns.UI.rows) do if row:IsShown() and row.data.item then out[row.data.item]=true end end return out end
function __count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function __pick(chip,index) chip:GetScript('OnClick')(chip); EPUGuildMenu.rows[index]:GetScript('OnClick')(EPUGuildMenu.rows[index]) end
""")
check('sold-out armor is hidden while stocked weapons remain',not A.ev('__shown()[30002]') and A.ev('__shown()[30001]') is True)
check('sold-out materials and bags remain',A.ev('__shown()[2447]') is True and A.ev('__shown()[4496]') is True)
check('existing equipment request and history are preserved',A.ev('__ns.G().requests.oldgear~=nil and __ns.G().bank.Bank.seen[30002]'))
check('direct requests cannot bypass the sold-out equipment rule',A.ev("__ns.NewRequest(30002,1,'')") is None)
A.ex("__pick(__ns.UI.bankStockChip,2)")
check('In stock filter shows held items even if reserved',A.ev('__count(__shown())')==3 and A.ev('__shown()[2589]') is True)
A.ex("__pick(__ns.UI.bankStockChip,3)")
check('Available now excludes fully requested stock',A.ev('__count(__shown())')==2 and not A.ev('__shown()[2589]') and A.ev('__shown()[118]') is True)
A.ex("__pick(__ns.UI.bankStockChip,4)")
check('Awaiting restock shows depleted materials and bags',A.ev('__count(__shown())')==2 and A.ev('__shown()[2447]') is True and not A.ev('__shown()[30002]'))
A.ex("__pick(__ns.UI.bankStockChip,1); __pick(__ns.UI.bankQualityChip,4)")
check('Uncommon quality filter combines with the catalog',A.ev('__count(__shown())')==2 and A.ev('__shown()[30001]') is True and A.ev('__shown()[2447]') is True)
A.ex("__pick(__ns.UI.bankStockChip,2)")
check('stock and quality filters combine',A.ev('__count(__shown())')==1 and A.ev('__shown()[30001]') is True)
A.ex("__pick(__ns.UI.bankQualityChip,5)")
check('Rare does not resurrect historical rare gear',A.ev('__count(__shown())')==0)
A.ex("__ns.UI.search:SetText('unmatched'); __ns.UI.bankReset:Click()")
check('Reset clears all bank filters and search',A.ev('__ns.UI.state.bank.stock')=='all' and A.ev('__ns.UI.state.bank.quality') is None and A.ev('__ns.UI.state.bank.cat') is None and A.ev('__ns.UI.search:GetText()')=='')
check('Reset keeps unavailable equipment hidden',A.ev('__count(__shown())')==5 and not A.ev('__shown()[30002]'))
A.ex("__ns.G().bank.Bank.items[30002]=1; __ns.UI:Refresh()")
check('restocked armor automatically returns',A.ev('__shown()[30002]') is True and A.ev('__ns.CanBankRequest(30002)') is True)
A.ex("__ns.G().bank.Bank.items[30001]=nil; __ns.UI:Refresh(); __ns.UI:SetView('requests'); __ns.UI.itemBox:SetText('Test Item 30001'); __ns.UI:SuggestItems(__ns.UI.itemBox)")
check('request autocomplete also hides sold-out weapons',not A.ev('__ns.UI.suggest:IsShown()'))
A.ex('__ns.CacheItemNames()')
check('hidden equipment metadata is still exported for Discord',A.ev('__ns.db.itemClass[30001][1]')==2)
A.ex("__ns.G().bank.Bank.seen[999999]=true; __ns.db.itemNames=__ns.db.itemNames or {}; __ns.db.itemNames[999999]='Unclassified history'")
check('unclassified historical items wait for metadata',not A.ev('__ns.CanBankRequest(999999)'))
A.ex("__ns.UI:SetView('bank'); __toolbarFits=__ns.UI.bars.bank.leftX+__ns.UI.bars.bank.rightX<=480")
check('all bank filters fit the narrowest window',A.ev('__toolbarFits'))
check('new filters produce no runtime errors',(A.ev('__errors') or 0)==0)

gd=core.GuildData({'itemNames':{30001:'Sword',30002:'Armor',2589:'Linen Cloth',4496:'Bag'},'itemClass':{30001:[2,7],30002:[4,1],2589:[7,5],4496:[1,0]},'guilds':{'G - R':{'bank':{'Bank':{'items':{30001:1},'seen':{30001:True,30002:True,2589:True,4496:True,999999:True}}}}}})
check('Discord uses the same gear and metadata rules',set(gd.bank_catalog())=={30001,2589,4496})
gd.bank['Bank']['items'][30002]=2
check('Discord catalog restores gear when stocked',30002 in gd.bank_catalog())
gd.bank['Bank']['items'].pop(30001)
check('Discord picker removes depleted weapons',30001 not in {r['id'] for r in gd.requestable_items()})
check('Discord retains hidden gear history',gd.bank['Bank']['seen'][30001] is True)
print('Bank filter checks:',check.failed,'failed')
sys.exit(bool(check.failed))

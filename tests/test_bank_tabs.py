"""Bank page: sort the list, filter by guild bank tab or bank character, and
point out items that look out of place for their tab. Choices are saved."""
from simcore import *

A = Client('Chris Baker')
A.ex("""__advance(120)
__ITEMS[2447]='Peacebloom'; __ITEMS[785]='Mageroyal'; __ITEMS[118]='Healing Potion'
__cls={[30001]={2,'Sword'},[30002]={4,'Cloth'},[118]={0,'Potion'},[2447]={7,'Herb'},[785]={7,'Herb'}}
__sub[2447]=9; __sub[785]=9
__qual={[30001]=3,[30002]=2,[2589]=1,[14047]=1,[4306]=1,[118]=1,[2447]=1,[785]=1}
__ilvl={[30001]=30,[30002]=25,[2589]=5,[14047]=55,[4306]=25,[118]=12,[2447]=5,[785]=15}
local g=__ns.G()
g.bank={
  ['Guild Bank']={v=__now,money=0,items={[2589]=40,[14047]=20,[2447]=10,[785]=5,[30001]=1,[4306]=12}},
  Donlock={v=__now,money=0,items={[118]=8,[2589]=3}},
}
g.gbTabs={
  [1]={name='Mats',items={[2589]=20,[14047]=20,[30001]=1}},
  [2]={name='Herbs',items={[2447]=10,[785]=5,[2589]=20}},
  [3]={name='',items={[4306]=12}},
}
__ns.UI:Show(); __ns.UI:SetView('bank')
function __rows() local out={} for _,row in ipairs(__ns.UI.rows) do if row:IsShown() and row.data then out[#out+1]=row.data end end return out end
function __items() local out={} for _,d in ipairs(__rows()) do if d.item then out[#out+1]=d.item end end return out end
function __has(id) for _,i in ipairs(__items()) do if i==id then return true end end return false end
function __row(id) for _,d in ipairs(__rows()) do if d.item==id then return d end end end
function __heads() local out={} for _,d in ipairs(__rows()) do if not d.item and d.key~='bank-columns' then out[#out+1]=d.title:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','') end end return table.concat(out,'/') end
function __pick(chip,index) chip:GetScript('OnClick')(chip); EPUGuildMenu.rows[index]:GetScript('OnClick')(EPUGuildMenu.rows[index]) end
function __menu(chip) chip:GetScript('OnClick')(chip); local out={} for i,r in ipairs(EPUGuildMenu.rows) do if r:IsShown() then out[#out+1]=r.text:GetText() end end EPUGuildMenu:Hide(); return table.concat(out,'/') end
""")

# The plan: which tab holds what, and what sits in the wrong one.
A.ex("__plan=__ns.GuildBankTabPlan()")
check('a tab named Herbs holds herbs', A.ev("__plan.home.Herbs")==2)
check('a general Mats tab takes the other trade goods', A.ev("__plan.home.Cloth")==1 and A.ev("__plan.tabs[1].holds.Cloth==true"))
check('an unnamed tab holds what fills it (one kind is not enough)', A.ev("__plan.tabs[3].holdsText") is None)
check('cloth in the Herbs tab belongs in Mats', A.ev("__plan.misplaced[2589][1].tab")==2 and A.ev("__plan.misplaced[2589][1].suggest")==1
      and A.ev("__plan.misplaced[2589][1].why")=='Belongs in Tab 1: Mats')
check('a sword in Mats is out of place, with no gear tab to suggest', A.ev("__plan.misplaced[30001][1].suggest") is None
      and 'Not what Tab 1: Mats is for' in A.ev("__plan.misplaced[30001][1].why"))
check('silk alone in an unnamed tab is pointed to the Mats tab',
      A.ev("__plan.misplaced[4306]") is not None and A.ev("__plan.misplaced[4306][1].suggest")==1)
check('herbs in their own tab are fine', A.ev("__plan.misplaced[2447]") is None)
check('three stacks look out of place', A.ev("__plan.count")==3)

# A tab named for gear claims weapons, and then the sword's hint names it.
A.ex("__ns.G().gbTabs[4]={name='Gear & Twinks',items={}}; __plan=__ns.GuildBankTabPlan()")
check('a newly bought gear tab becomes home for weapons and armor', A.ev("__plan.home['Weapons & Armor']")==4
      and A.ev("__plan.misplaced[30001][1].why")=='Belongs in Tab 4: Gear & Twinks')
A.ex("__ns.G().gbTabs[4]=nil")

# Rows show where each item sits.
A.ex("__ns.UI:Refresh()")
check('rows say which tab and bank character hold an item', 'Tab 1: Mats 20' in (A.ev("__row(2589).sub") or '')
      and 'Tab 2: Herbs 20' in A.ev("__row(2589).sub") and 'Donlock 3' in A.ev("__row(2589).sub"))
check('out-of-place stacks are marked on the row', 'Tab 2: belongs in Tab 1: Mats' in A.ev("__row(2589).sub"))
check('category headers say which tab keeps them', 'kept in Tab 2: Herbs' in (A.ev("(function() for _,d in ipairs(__rows()) do if d.key=='cat:Herbs' then return d.sub end end end)()") or ''))

# Where: every tab, every bank character, and out of place.
menu = A.ev("__menu(__ns.UI.bankWhereChip)")
check('the Where menu lists each tab, the bank character and Out of place (%s)' % menu,
      menu.startswith('Anywhere/Tab 1: Mats') and 'Tab 2: Herbs' in menu and 'Tab 3' in menu and 'Donlock' in menu and menu.endswith('Out of place in its tab'))
A.ex("__pick(__ns.UI.bankWhereChip,3)")
check('picking Tab 2 shows only what is in it', sorted(A.ev("__items()").values())==[785,2447,2589])
check('the count column shows the stack in that tab', A.ev("__row(2589).stock")=='20' and A.ev("(function() for _,d in ipairs(__rows()) do if d.key=='bank-columns' then return d.stock end end end)()")=='Here')
check('in one tab, the hint drops the tab name', 'Belongs in Tab 1: Mats' in A.ev("__row(2589).sub"))
check('the Where chip names the tab', A.ev("__ns.UI.bankWhereChip.text:GetText()")=='Tab 2: Herbs' and A.ev("__ns.UI.filterCount:IsShown()"))
A.ex("__pick(__ns.UI.bankWhereChip,6)")
check('Out of place lists the three flagged items', sorted(A.ev("__items()").values())==[2589,4306,30001])
A.ex("__pick(__ns.UI.bankWhereChip,5)")
check('a bank character shows its own items', sorted(A.ev("__items()").values())==[118,2589] and A.ev("__row(2589).stock")=='3')
A.ex("__pick(__ns.UI.bankWhereChip,1)")

# Sorting.
A.ex("__pick(__ns.UI.bankSortChip,2)")
names = A.ev("(function() local out={} for _,d in ipairs(__rows()) do if d.item then out[#out+1]=d.title end end return table.concat(out,'/') end)()")
check('By name is one A to Z list with no category headers (%s)' % names, names.split('/')==sorted(names.split('/')) and A.ev("__heads()")=='')
A.ex("__pick(__ns.UI.bankSortChip,3)")
check('Most in bank puts the biggest stack first', A.ev("__items()[1]")==2589 and A.ev("__items()[2]")==14047)
A.ex("__pick(__ns.UI.bankSortChip,4)")
check('Best quality puts the rare sword first', A.ev("__items()[1]")==30001)
A.ex("__pick(__ns.UI.bankSortChip,5)")
check('Item level puts Runecloth (55) first', A.ev("__items()[1]")==14047 and A.ev("__items()[2]")==30001)
A.ex("__pick(__ns.UI.bankSortChip,6)")
heads = A.ev("__heads()")
check('By bank tab groups under each tab, then the bank character (%s)' % heads,
      heads.startswith('Tab 1: Mats/Tab 2: Herbs/Tab 3/Donlock'))
check('an item in two tabs is listed under both with that tab\'s count',
      A.ev("(function() local n=0 for _,d in ipairs(__rows()) do if d.item==2589 then n=n+1 end end return n end)()")==3)
check('tab headers say what the tab holds and how much is out of place',
      'holds Herbs' in A.ev("(function() for _,d in ipairs(__rows()) do if d.key=='place:gb:2' then return d.sub end end end)()")
      and '1 out of place' in A.ev("(function() for _,d in ipairs(__rows()) do if d.key=='place:gb:2' then return d.sub end end end)()"))
check('the Sort chip shows the choice', A.ev("__ns.UI.bankSortChip.text:GetText()")=='By bank tab')
A.ex("__pick(__ns.UI.bankCatChip,2)")
check('sort and category filter combine', A.ev("__ns.UI.state.bank.cat") is not None and A.ev("#__items()")>0)

# Choices are saved for the character and come back after a reload.
saved = A.ev("__ns.cdb.bankView.sort")
check('choices are saved for this character', saved=='tab' and A.ev("__ns.cdb.bankView.cat")==A.ev("__ns.UI.state.bank.cat"))
A.ex("__pick(__ns.UI.bankWhereChip,3); local st=__ns.UI.state.bank; st.sort,st.cat,st.where='category',nil,nil; __ns.UI.LoadBankView()")
check('loading restores sort, category and tab', A.ev("__ns.UI.state.bank.sort")=='tab' and A.ev("__ns.UI.state.bank.where")=='gb:2' and A.ev("__ns.UI.state.bank.cat") is not None)
A.ex("__ns.cdb.bankView={sort='bogus',stock='nope',quality=9,cat='Nonsense',where='gb:99'}; local st=__ns.UI.state.bank; st.sort,st.cat,st.where,st.stock,st.quality='category',nil,nil,'all',nil; __ns.UI.LoadBankView(); __ns.UI:Refresh()")
check('bad saved values are ignored and a missing tab falls back to Anywhere', A.ev("__ns.UI.state.bank.sort")=='category'
      and A.ev("__ns.UI.state.bank.stock")=='all' and A.ev("__ns.UI.state.bank.quality") is None and A.ev("__ns.UI.state.bank.where") is None)

# Reset clears filters, keeps the sort.
A.ex("__pick(__ns.UI.bankSortChip,2); __pick(__ns.UI.bankWhereChip,2); __ns.UI.clearFilters:Click()")
check('Reset clears the tab filter but keeps the sort', A.ev("__ns.UI.state.bank.where") is None and A.ev("__ns.UI.state.bank.sort")=='name'
      and A.ev("__ns.cdb.bankView.where") is None)

# Searching finds items by tab name.
A.ex("__ns.UI.search:SetText('herbs'); __ns.UI:Refresh()")
check('search matches the tab an item is in', A.ev("__has(2589)") and not A.ev("__has(118)"))
A.ex("__ns.UI.clearSearch:Click()")

# Item details show the tabs and the hint.
A.ex("__ns.UI:OpenDetails('item',2589)")
check('item details open without errors', (A.ev('__errors') or 0)==0)

# /epu banktabs opens the Bank page grouped by tab; "tidy" adds Out of place.
A.ex("__ns.UI:SetView('needs'); SlashCmdList.EPUGUILD('banktabs tidy')")
check('/epu banktabs tidy opens the out-of-place list grouped by tab', A.ev("__ns.UI.view")=='bank' and A.ev("__ns.UI.state.bank.sort")=='tab'
      and A.ev("__ns.UI.state.bank.where")=='misplaced' and A.ev("__has(30001)") and not A.ev("__has(2447)"))
A.ex("__ns.UI.clearFilters:Click()")

# No guild bank tabs known yet: nothing breaks and Out of place isn't offered.
A.ex("__ns.G().gbTabs=nil; __ns.UI:Refresh()")
menu = A.ev("__menu(__ns.UI.bankWhereChip)")
check('without tab data the Where menu lists the guild bank and characters only (%s)' % menu, 'Out of place' not in menu and 'Guild bank' in menu)

A.ex("__ns.UI:SetView('bank')")
fit = A.ev('(function() local b=__ns.UI.bars.bank; b:Fit(480) return math.max(b.row1W,b.row2W) end)()')
check('the bank toolbar fits the narrowest window on two rows (%s)' % fit, fit<=480)
check('no runtime errors', (A.ev('__errors') or 0)==0)
print('Bank tab checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

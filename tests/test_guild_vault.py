"""Guild bank by category: a window that groups the guild bank like
Baganator's category view of your bags, without moving anything by itself.

It opens from the Bank page's Guild bank view button or /epu vault. At the
guild bank it can open by itself, beside the bank window or instead of it
(the game's window and Baganator's move off the screen, then come back when
the bank closes). Right-click takes a stack; an item dropped on it goes to
the tab its category lives in.
"""
from simcore import *

A = Client('Chris Baker')
A.ex("""__advance(120)
__ITEMS[2447]='Peacebloom'; __ITEMS[785]='Mageroyal'; __ITEMS[118]='Healing Potion'
__cls={[30001]={2,'Sword'},[118]={0,'Potion'},[2447]={7,'Herb'},[785]={7,'Herb'}}
__sub[2447]=9; __sub[785]=9
__qual={[30001]=3,[2589]=1,[14047]=1,[4306]=1,[2447]=1,[785]=2}
local g=__ns.G()
g.bank={['Guild Bank']={v=__now,money=1234567,items={[2589]=40,[14047]=20,[2447]=10,[785]=5,[30001]=1,[4306]=12}}}
g.gbTabs={
  [1]={name='Mats',items={[2589]=20,[14047]=20,[30001]=1},t=__now-7200},
  [2]={name='Herbs',items={[2447]=10,[785]=5,[2589]=20},t=__now-7200},
  [3]={name='',items={[4306]=12},t=__now-7200},
}
function __titles(secs) local t={} for _,s in ipairs(secs) do t[#t+1]=s.title end return table.concat(t,'/') end
function __find(secs, id) for _,s in ipairs(secs) do for _,e in ipairs(s.items) do if e.id==id then return e, s end end end end
""")

# --- grouping (pure) ---
A.ex("__secs=__ns.GuildVaultGroups((__ns.GuildVaultStacks()))")
check('sections follow the category order', A.ev("__titles(__secs)") == 'Cloth/Herbs/Weapons & Armor')
check('one item spread over two tabs fills one button with the total', A.ev("__find(__secs,2589).n") == 40
      and A.ev("__find(__secs,2589).tabs[1]") == 20 and A.ev("__find(__secs,2589).tabs[2]") == 20)
check('a section counts kinds and items', A.ev("__secs[1].kinds") == 3 and A.ev("__secs[1].total") == 72)
check('better quality comes first in a section', A.ev("__secs[2].items[1].id") == 785)
A.ex("__secs=__ns.GuildVaultGroups((__ns.GuildVaultStacks()), {group='tab'})")
check('grouped by tab, each tab is a section', A.ev("__titles(__secs)") == 'Tab 1/Tab 2/Tab 3')
check('grouped by tab, an item shows in each tab that holds it', A.ev("#__secs[1].items") == 3 and A.ev("#__secs[2].items") == 3)
A.ex("__secs=__ns.GuildVaultGroups((__ns.GuildVaultStacks()), {query='herb'})")
check('searching a category name finds that section', A.ev("__titles(__secs)") == 'Herbs')
A.ex("__secs=__ns.GuildVaultGroups((__ns.GuildVaultStacks()), {query='linen'})")
check('searching an item name finds the item', A.ev("#__secs") == 1 and A.ev("__secs[1].items[1].id") == 2589)
A.ex("__secs=__ns.GuildVaultGroups((__ns.GuildVaultStacks()), {tab=3})")
check('one tab only', A.ev("__titles(__secs)") == 'Cloth' and A.ev("__secs[1].items[1].id") == 4306)

# --- where a dropped item goes (pure) ---
A.ex("""__tabs={[1]={empty={5,6}},[2]={empty={3}},[3]={empty={}}}
__st={{tab=2,slot=1,id=2447,n=10},{tab=1,slot=1,id=2447,n=4}}""")
check('a stack of the same item in its home tab is topped up first',
      A.ev("table.concat({__ns.GuildVaultDepositSpot(2447,5,__tabs,__st,2,1,20)},',')") == '2,1,stack')
check('a full stack is skipped for an empty slot in the home tab',
      A.ev("table.concat({__ns.GuildVaultDepositSpot(2447,15,__tabs,__st,2,1,20)},',')") == '2,3,empty')
A.ex("__tabs[2].canDeposit=false")
check('a tab you can\'t deposit in is skipped for one that already holds the item',
      A.ev("table.concat({__ns.GuildVaultDepositSpot(2447,1,__tabs,__st,2,3,20)},',')") == '1,1,stack')
A.ex("__tabs[1].empty={}; __st={}")
check('nothing fits: no spot', A.ev("__ns.GuildVaultDepositSpot(2447,1,__tabs,__st,2,1,20)") is None)

# --- the window, away from the bank ---
A.ex("function __hideVault() EPUGuildVault:Hide(); EPUGuildVault:GetScript('OnHide')(EPUGuildVault) end")
A.ex("__ns.UI:Show(); __ns.UI:SetView('bank')")
check('the Bank page has a Guild bank view button', A.ev("__ns.UI.bankVaultBtn ~= nil"))
A.ex("__ns.UI.bankVaultBtn:Click()")
check('the button opens the window', A.ev("EPUGuildVault:IsShown()"))
check('away from the bank it shows the last scan, by category', A.ev("__titles(EPUGuildVault.sections)") == 'Cloth/Herbs/Weapons & Armor'
      and not A.ev("EPUGuildVault.info.live"))
check('it says when the bank was last seen', 'As last seen 2 hours ago' in A.ev("EPUGuildVault.status:GetText()"))
check('it shows the guild bank gold', A.ev("EPUGuildVault.money:GetText()") != '')
A.ex("""function __button(id) for _,w in ipairs(EPUGuildVault.pool.used) do if w.entry and w.entry.id==id then return w end end end
function __head(key) for _,w in ipairs(EPUGuildVault.pool.used) do if w.key==key then return w.sub:GetText() end end end""")
check('headers say which tab keeps a category', 'kept in Tab 2: Herbs' in (A.ev("__head('cat:Herbs')") or ''))
check('an item out of place in its tab is marked', A.ev("#__button(2589).misplaced") == 1 and A.ev("#__button(2447).misplaced") == 0)
A.ex("EPUGuildVault.group:Click()")
check('the group button switches to tabs and is remembered', A.ev("__titles(EPUGuildVault.sections)") == 'Tab 1: Mats/Tab 2: Herbs/Tab 3'
      and A.ev("__ns.db.guildVault.group") == 'tab')
A.ex("EPUGuildVault.group:Click()")
check('and back to categories', A.ev("__titles(EPUGuildVault.sections)") == 'Cloth/Herbs/Weapons & Armor')
A.ex("EPUGuildVault.search:SetText('mage')")
check('the search box filters the window', A.ev("#EPUGuildVault.shown") == 1 and A.ev("EPUGuildVault.shown[1].id") == 785)
A.ex("EPUGuildVault.search:SetText('nothing like this')")
check('no match says so', A.ev("EPUGuildVault.emptyText") == 'Nothing in the guild bank matches.')
A.ex("EPUGuildVault.search:SetText('')")
A.ex("__ns.db.guildVault.collapsed={['cat:Cloth']=true}; EPUGuildVault:Refresh()")
check('a collapsed section hides its items', A.ev("#EPUGuildVault.shown") == 3)
A.ex("__ns.db.guildVault.collapsed=nil; EPUGuildVault:Refresh()")

# The window doesn't grow when redrawn.
A.ex('''__made = 0
local M = getmetatable(UIParent)
local fs, tex = M.CreateFontString, M.CreateTexture
M.CreateFontString = function(...) __made = __made + 1; return fs(...) end
M.CreateTexture = function(...) __made = __made + 1; return tex(...) end
local cf = CreateFrame
CreateFrame = function(...) __made = __made + 1; return cf(...) end
EPUGuildVault:Refresh(); EPUGuildVault:Refresh()
__before = __made
for i = 1, 20 do EPUGuildVault:Refresh() end''')
check('redrawing makes no new widgets', A.ev("__made") == A.ev("__before"))
A.ex("__hideVault()")

A.ex('SlashCmdList.EPUGUILD("vault")')
check('/epu vault opens it', A.ev("EPUGuildVault:IsShown()"))
A.ex("__hideVault()")
check('it opens only when asked by default', A.ev("__ns.GuildVaultMode()") == 'off')

# --- at the bank: instead of the bank window ---
A.ex("""__closed=0; function CloseGuildBankFrame() __closed=__closed+1 end
__stored={}; function AutoStoreGuildBankItem(tab, slot) __stored[#__stored+1]=tab..':'..slot; __gb[tab][slot]=nil end
local function alpha(f) f.SetAlpha=function(self,a) self._alpha=a end; f.GetAlpha=function(self) return self._alpha or 1 end end
GuildBankFrame=CreateFrame('Frame','GuildBankFrame',UIParent); alpha(GuildBankFrame)
__bag=CreateFrame('Frame','Baganator_SingleViewGuildViewFrameblizzard',UIParent); alpha(__bag)
__bag.GetName=function() return 'Baganator_SingleViewGuildViewFrameblizzard' end
function EnumerateFrames(f) local i=0 if f then for k,x in ipairs(__frames) do if x==f then i=k end end end return __frames[i+1] end
GetGuildBankTabInfo=function(tab) return ({'Mats','Herbs'})[tab], 'icon', true, true, 5, (tab==2 and 0 or 3) end
__gb={ {{2589,20},{2589,7},{30001,1}}, {{2447,10},{785,5},{2589,20}} }""")
A.ex('SlashCmdList.EPUGUILD("vault instead")')
check('/epu vault instead is saved', A.ev("__ns.db.guildVault.mode") == 'instead')
A.ex('__fire("GUILDBANKFRAME_OPENED")'); A.ex('__advance(2)')
check('the window opens by itself at the bank', A.ev("EPUGuildVault:IsShown()"))
check('it shows the live bank', A.ev("EPUGuildVault.info.live") and A.ev("__find(EPUGuildVault.sections,2589).n") == 47)
check("the game's guild bank window moves out of sight", A.ev("GuildBankFrame:GetAlpha()") == 0)
check("Baganator's guild bank window moves out of sight too", A.ev("__bag:GetAlpha()") == 0)
check('the Other window button is offered', A.ev("EPUGuildVault.other:IsShown()"))
check('the donate panel sits beside this window', A.ev("__ns.GuildVaultDonateAnchor() == EPUGuildVault"))
check('items with no withdrawals left today are dimmed in the tooltip data',
      A.ev("EPUGuildVault.info.tabs[2].withdrawalsLeft") == 0)

# Right-click takes the biggest stack you can still withdraw from.
A.ex("__button(2589):GetScript('OnClick')(__button(2589),'RightButton')")
check('right-click takes the biggest stack from a tab with withdrawals left', A.ev("__stored[1]") == '1:1')
A.ex("__advance(1); EPUGuildVault:Refresh(); __button(2447):GetScript('OnClick')(__button(2447),'RightButton')")
check('a tab with no withdrawals left today is not used', A.ev("#__stored") == 1)

# Dropping an item puts it in the tab its category lives in.
A.ex("__cursor={785,3}")
A.ex("__ok,__tab,__slot=__ns.GuildVaultDeposit()")
check('a dropped herb goes to the Herbs tab, onto the stack of the same herb',
      A.ev("__ok") and A.ev("__tab") == 2 and A.ev("__slot") == 2)

# Other window brings the bank window back for this visit.
A.ex("EPUGuildVault.other:Click()")
check('Other window brings the bank window back', A.ev("GuildBankFrame:GetAlpha()") == 1 and not A.ev("EPUGuildVault.other:IsShown()"))

# The bank closes: everything goes back.
A.ex('__fire("GUILDBANKFRAME_CLOSED")'); A.ex('__advance(1)')
check('the window closes with the bank', not A.ev("EPUGuildVault:IsShown()"))
check('the bank windows are back in place', A.ev("GuildBankFrame:GetAlpha()") == 1 and A.ev("__bag:GetAlpha()") == 1)
check('closing with the bank does not close it again', A.ev("__closed") == 0)

# Closing this window while it stands in for the bank closes the bank.
A.ex('__fire("GUILDBANKFRAME_OPENED")'); A.ex('__advance(2)')
check('it opens again next time', A.ev("EPUGuildVault:IsShown()") and A.ev("GuildBankFrame:GetAlpha()") == 0)
A.ex("__hideVault()")
check('closing it closes the guild bank', A.ev("__closed") == 1 and A.ev("GuildBankFrame:GetAlpha()") == 1)
A.ex('__fire("GUILDBANKFRAME_CLOSED")'); A.ex('__advance(1)')

# Beside: nothing is hidden.
A.ex('SlashCmdList.EPUGUILD("vault beside")')
A.ex('__fire("GUILDBANKFRAME_OPENED")'); A.ex('__advance(2)')
check('beside opens it next to the bank window', A.ev("EPUGuildVault:IsShown()") and A.ev("GuildBankFrame:GetAlpha()") == 1)
A.ex("__hideVault()")
check('closing it beside the bank leaves the bank open', A.ev("__closed") == 1)
A.ex('__fire("GUILDBANKFRAME_CLOSED")'); A.ex('__advance(1)')

# Off: it stays shut at the bank.
A.ex('SlashCmdList.EPUGUILD("vault off")')
A.ex('__fire("GUILDBANKFRAME_OPENED")'); A.ex('__advance(2)')
check('off leaves it shut at the bank', not A.ev("EPUGuildVault:IsShown()") and A.ev("GuildBankFrame:GetAlpha()") == 1)
A.ex('__fire("GUILDBANKFRAME_CLOSED")'); A.ex('__advance(1)')

check('no errors', (A.ev('__errors') or 0) == 0)
sys.exit(1 if check.failed else 0)

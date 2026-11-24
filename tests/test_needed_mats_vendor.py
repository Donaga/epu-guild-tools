"""Needed mats at vendors and the auction house.

Auto-sell never sells a material on a guildmate's needed mats list. With the
warning on (Travel, vendor and tooltips, /epu qol), EPU names who needs it when
a vendor opens, when you sell one by hand, and when you put one up for auction.
"""
from simcore import *

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)

# Tyler needs Linen Cloth and a grey item (30001).
B.ex('SlashCmdList.EPUGUILD("mats add " .. __link(2589) .. " 20")')
B.ex('SlashCmdList.EPUGUILD("mats add " .. __link(30001))')
tick(3)
tick_until(lambda: A.ev('(function() local r = __ns.G().neededMats["Tyler Baker"]; return r and r.i[30001] ~= nil end)()'))
check('the list reaches Chris', A.ev('__ns.G().neededMats["Tyler Baker"].i[2589] ~= nil'))

# Chris's bags and a vendor, like the game: a sale is a request, the slot empties a moment later.
A.ex('''
__qual = {[30001] = 0, [30002] = 0}
__bags = {[0] = {{2589, 5}, {30001, 1}, {30002, 1}, {4306, 3}}}
__sold = {}
C_Container.UseContainerItem = function(b, s)
  local x = __bags[b] and __bags[b][s]
  if not x then return end
  __sold[#__sold + 1] = x[1]
  C_Timer.After(0.1, function() __bags[b][s] = nil end)
end
UseContainerItem = function(b, s) return C_Container.UseContainerItem(b, s) end
local info = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function(b, s)
  local t = info(b, s)
  if t then t.quality = __qual[t.itemID] or 1 end
  return t
end
MerchantFrame = NewMock()
function __printed(text) for _, l in ipairs(__log) do if l:find(text, 1, true) then return l end end end
function __visit() __log = {}; __sold = {}; MerchantFrame:Show(); __fire("MERCHANT_SHOW") end
function __leave() MerchantFrame:Hide(); __fire("MERCHANT_CLOSED"); __advance(1) end
''')


def sold():
    s = A.ev('__sold')
    return [s[i] for i in range(1, len(s) + 1)]


def printed(text):
    return A.ev('__printed(%r)' % text)


# --- auto-sell keeps needed greys ------------------------------------------------
A.ex('__visit()')
check('auto-sell sells a grey nobody needs, and keeps the one Tyler needs ' + str(sold()), sold() == [30002])
check('auto-sell says it kept one', printed('Kept 1 grey item a guildmate has on their needed mats list') is not None)
line = printed("Needed mats in your bags, so don't sell:")
check('opening a vendor lists the needed mats in your bags, naming who needs them', line is not None
      and 'Linen Cloth' in line and 'Tyler (x20)' in line and 'Test Item 30001' in line and 'Silk Cloth' not in line)
A.ex('__leave()')

# --- selling by hand -------------------------------------------------------------
A.ex('__visit(); __log = {}; C_Container.UseContainerItem(0, 1)')
line = printed('You sold')
check('selling a needed mat by hand names who needs it', line is not None
      and 'Linen Cloth' in line and 'x5' in line and 'Tyler (x20) needs' in line and 'Buyback' in line)
A.ex('__leave()')
A.ex('__bags[0][1] = {2589, 5}; __visit(); __log = {}; UseContainerItem(0, 1)')
count = A.ev('(function() local n = 0 for _, l in ipairs(__log) do if l:find("You sold", 1, true) then n = n + 1 end end return n end)()')
check('a sale through both the old and the new function name warns once', count == 1)
A.ex('__log = {}; C_Container.UseContainerItem(0, 4)')
check('selling something nobody needs says nothing', printed('You sold') is None)
A.ex('__leave(); __bags[0][1] = {2589, 5}; __log = {}; C_Container.UseContainerItem(0, 1); __advance(0.2)')
check('using an item with no vendor open says nothing', printed('You sold') is None)

# --- your own list counts too ----------------------------------------------------
A.ex('SlashCmdList.EPUGUILD("mats add " .. __link(4306))')
A.ex('__bags[0][4] = {4306, 3}; __visit(); __log = {}; C_Container.UseContainerItem(0, 4)')
line = printed('You sold')
check('selling a mat on your own list says so ' + str(line), line is not None and 'which you need.' in line)
A.ex('__leave(); SlashCmdList.EPUGUILD("mats remove " .. __link(4306))')

# --- the auction house -----------------------------------------------------------
A.ex('''
__sellSlot = nil
function GetAuctionSellItemInfo()
  if not __sellSlot then return nil end
  return __ITEMS[__sellSlot[1]], "icon", __sellSlot[2], 1, true, 10, 10, 20, __sellSlot[2], __sellSlot[1]
end
__fire("AUCTION_HOUSE_SHOW")
''')
A.ex('__log = {}; __sellSlot = {2589, 5}; __fire("NEW_AUCTION_UPDATE")')
line = printed('is on the needed mats list of')
check('putting a needed mat in the auction sell slot warns before posting', line is not None and 'Tyler (x20)' in line)
A.ex('__log = {}; __fire("NEW_AUCTION_UPDATE")')
check('changing the price does not repeat the warning', printed('is on the needed mats list of') is None)
A.ex('__sellSlot = nil; __fire("NEW_AUCTION_UPDATE"); __sellSlot = {2589, 5}; __fire("NEW_AUCTION_UPDATE")')
check('putting it back in after taking it out warns again', printed('is on the needed mats list of') is not None)
A.ex('__log = {}; __sellSlot = {14047, 5}; __fire("NEW_AUCTION_UPDATE")')
check('an unneeded item in the sell slot says nothing', printed('is on the needed mats list of') is None)
A.ex('__fire("AUCTION_HOUSE_CLOSED")')

# Newer auction house: posting is one call with an item location.
A.ex('''
C_AuctionHouse = { PostItem = function() end, PostCommodity = function() end }
C_Item = C_Item or {}
C_Item.GetItemID = function(loc) return loc.id end
__fire("AUCTION_HOUSE_SHOW"); __log = {}
C_AuctionHouse.PostCommodity({id = 2589}, 1, 5, 100)
''')
line = printed('You listed')
check('posting a needed commodity names who needs it', line is not None and 'x5' in line and 'Tyler (x20) needs' in line)

# --- the setting -----------------------------------------------------------------
A.ex('__ns.OpenWorldQoLSettings()')
toggle = '[x] Warn Before Selling or Auctioning a Mat a Guildmate Needs'
check('the warning starts on', A.ev('__ns.db.worldQoL.neededMatsWarn') is True)
A.ex('''for _,w in ipairs(EPUGuildWorldQoLConfig.pool.used) do
  if w.text and w.text:GetText()==%r then w:Click() end end''' % toggle)
check('the travel, vendor and tooltips window turns it off', A.ev('__ns.db.worldQoL.neededMatsWarn') is False)
A.ex('__bags = {[0] = {{2589, 5}, {30001, 1}}}; __visit()')
check('with it off, opening a vendor says nothing', printed("Needed mats in your bags") is None)
check('with it off, auto-sell still keeps the needed grey', sold() == [] and printed('Kept 1 grey item') is not None)
A.ex('__log = {}; C_Container.UseContainerItem(0, 1)')
check('with it off, selling by hand says nothing', printed('You sold') is None)
A.ex('__leave(); __log = {}; __sellSlot = {2589, 5}; __fire("AUCTION_HOUSE_SHOW"); __fire("NEW_AUCTION_UPDATE")')
check('with it off, the auction house says nothing', printed('is on the needed mats list of') is None)

# --- reachable from the main window ----------------------------------------------
A.ex('''function __rowKeys() local t={} for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key then t[#t+1]=r.data.key end end return table.concat(t,",") end''')
A.ex('__ns.UI:Show(); __ns.UI:SetView("settings"); __ns.UI.search:SetText("needed mats")')
check('searching settings for needed mats finds the travel, vendor and tooltips row', 'qol' in (A.ev('__rowKeys()') or '').split(','))
A.ex('__ns.UI.search:SetText("")')

check('no Lua errors', A.ev('__errors or 0') == 0 and B.ev('__errors or 0') == 0)
print('Needed mats vendor checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

"""Mail tools: Take all on one mail, and AH gold only.

Take all takes one mail's gold and attachments one at a time, waiting for the
server between takes, and never touches another mail. It stops on full bags
and never pays cash on delivery. Collect AH gold takes only the gold from
auction house mail and leaves item mail and players' mail alone. Both open
from Member tools -> Mail tools.
"""
from simcore import *

SETUP = r'''
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
ERR_INV_FULL = "Inventory is full."
OpenMailFrame = CreateFrame("Frame", "OpenMailFrame"); OpenMailFrame._shown = false
InboxFrame = CreateFrame("Frame", "InboxFrame")
function __open(i) InboxFrame.openMailID = i; OpenMailFrame:Show(); __ns.MailTools.Refresh() end
function __text(f) return f and f:GetText() or "" end
function __lastLog() return __log[#__log] or "" end
'''


def client():
    c = Client('Chris Baker')
    c.ex(SETUP)
    c.ex('MailFrame._shown = true; __fire("MAIL_SHOW")')
    return c


def run(c, sec=10):
    c.ex(f'for i = 1, {int(sec * 10)} do __advance(0.1) end')


def inbox(c, lua):
    c.ex('__inbox = ' + lua + '; __takes = {}; __fire("MAIL_INBOX_UPDATE")')


ONE_MAIL = '''{
  { sender = "Pip Baker", subject = "Mats for you", money = 50000, items = {} },
  { sender = "Tyler Baker", subject = "Linen and gold", money = 12000, deleteWhenEmpty = true,
    items = { [1] = { 2589, 20 }, [3] = { 2589, 7 }, [5] = { 4306, 4 } } },
  { sender = "Newbie Stone", subject = "Thanks", money = 300, items = { [1] = { 2589, 1 } } },
}'''

# --- Take all on one mail ---
A = client()
inbox(A, ONE_MAIL)
check('the Take all button is made when the mailbox opens', A.ev('__ns.MailTools.takeButton ~= nil'))
A.ex('__open(2)')
check('Take all is ready on an open mail with gold and items', A.ev('__ns.MailTools.takeButton:IsEnabled()'))
A.ex('__ns.MailTools.takeButton:Click()')
check('the first take is only the gold', A.ev('#__takes') == 1 and A.ev('__takes[1][1]') == 'money')
check('the button turns into Stop while it runs', A.ev('__text(__ns.MailTools.takeButton)') == 'Stop')
run(A)
check('Take all took the gold and all three attachments, one at a time',
      A.ev('#__takes') == 4 and A.ev('__takes[2][1]=="item" and __takes[3][1]=="item" and __takes[4][1]=="item"'))
check('every take was from that mail', A.ev('(function() for _,t in ipairs(__takes) do if t[2] ~= 2 then return false end end return true end)()'))
check('the emptied mail is gone and the others are untouched',
      A.ev('#__inbox') == 2 and A.ev('__inbox[1].money') == 50000 and A.ev('__inbox[2].money') == 300
      and A.ev('__inbox[2].items[1] ~= nil'))
check('Take all says what it took', 'Took' in A.ev('__lastLog()') and '3 items' in A.ev('__lastLog()')
      and "Tyler Baker's mail" in A.ev('__lastLog()'))
check('the button is Take all again', A.ev('__text(__ns.MailTools.takeButton)') == 'Take all')

# a mail that stays (has text) is emptied but not deleted, and the next mail is left alone
B = client()
inbox(B, '''{
  { sender = "Pip Baker", subject = "Hi", money = 100, items = { [2] = { 2589, 3 } } },
  { sender = "Pip Baker", subject = "Hi", money = 100, items = { [2] = { 2589, 3 } } },
}''')
B.ex('__open(1); __ns.MailTools.TakeAll(1)')
run(B)
check('a mail that stays after emptying is finished, and an identical mail after it is left alone',
      B.ev('#__takes') == 2 and B.ev('__inbox[1].money') == 0 and B.ev('__inbox[2].money') == 100
      and B.ev('__inbox[2].items[2] ~= nil'))

# --- COD is never paid ---
C = client()
inbox(C, '{ { sender = "Chris Stone", subject = "Pick it up", money = 0, cod = 25000, items = { [1] = { 2589, 20 } } } }')
C.ex('__open(1)')
check('Take all is off on a cash-on-delivery mail', not C.ev('__ns.MailTools.takeButton:IsEnabled()')
      and 'COD' in C.ev('__ns.MailTools.takeButton.disabledTip'))
C.ex('__ns.MailTools.TakeAll(1)')
run(C)
check('a COD mail is never taken from', C.ev('#__takes') == 0 and C.ev('__codPaid') == 0)
check('and it says why', 'cash on delivery' in C.ev('__lastLog()'))

# --- full bags stop it ---
D = client()
inbox(D, '{ { sender = "Tyler Baker", subject = "Stuff", money = 0, items = { [1] = { 2589, 20 }, [2] = { 4306, 5 } } } }')
D.ex('__bagsFull = true; __ns.MailTools.TakeAll(1)')
run(D)
check('full bags stop Take all after the server refuses', D.ev('#__takes') == 1 and not D.ev('__ns.MailTools.Busy()'))
check('it says the bags are full and what is left', 'Inventory is full.' in D.ev('__lastLog()')
      and '2 items still in it' in D.ev('__lastLog()'))
D.ex('__bagsFull = nil; C_Container.GetContainerNumFreeSlots = function() return 0, 0 end; __ns.MailTools.TakeAll(1)')
run(D)
check('with no free bag slot it stops before taking', D.ev('#__takes') == 1 and 'bags are full' in D.ev('__lastLog()'))

# --- closing the mailbox stops it ---
E = client()
inbox(E, '{ { sender = "Tyler Baker", subject = "Stuff", money = 0, items = { [1] = { 2589, 1 }, [2] = { 2589, 1 }, [3] = { 2589, 1 } } } }')
E.ex('__ns.MailTools.TakeAll(1); __advance(0.2); MailFrame._shown = false; __fire("MAIL_CLOSED")')
run(E)
check('closing the mailbox stops Take all', E.ev('#__takes') == 1 and not E.ev('__ns.MailTools.Busy()'))

# --- a server that never answers ---
F = client()
inbox(F, '{ { sender = "Tyler Baker", subject = "Stuff", money = 500, items = {} } }')
F.ex('TakeInboxMoney = function(i) table.insert(__takes, { "money", i }) end; __ns.MailTools.TakeAll(1)')
run(F, 15)
check('a take the server ignores is tried twice, then Take all stops', F.ev('#__takes') == 2
      and not F.ev('__ns.MailTools.Busy()') and "didn't hand over" in F.ev('__lastLog()'))

# --- AH gold only ---
AH = '''{
  { sender = "Stormwind Auction House", subject = "Auction successful: Linen Cloth", money = 4000, invoice = "seller", deleteWhenEmpty = true, items = {} },
  { sender = "Stormwind Auction House", subject = "Auction expired: Copper Ore", money = 0, deleteWhenEmpty = true, items = { [1] = { 14047, 20 } } },
  { sender = "Pip Baker", subject = "Gold for you", money = 90000, canReply = true, items = {} },
  { sender = "Stormwind Auction House", subject = "Outbid on Silver Bar", money = 1500, deleteWhenEmpty = true, items = {} },
  { sender = "Stormwind Auction House", subject = "Auction won: Wool Cloth", money = 0, invoice = "buyer", deleteWhenEmpty = true, items = { [1] = { 4306, 10 } } },
  { sender = "Chris Stone", subject = "Auction successful: totally real", money = 777, canReply = true, items = {} },
  { sender = "Stormwind Auction House", subject = "Auction successful: Silk Cloth", money = 6000, invoice = "seller", deleteWhenEmpty = true, items = {} },
}'''
G = client()
inbox(G, AH)
check('the AH gold button is made with the inbox', G.ev('__ns.MailTools.ahButton ~= nil'))
check('sale and outbid mail count as auction mail, players\' mail does not',
      G.ev('__ns.MailTools.IsAuctionMail(1)') and G.ev('__ns.MailTools.IsAuctionMail(4)')
      and not G.ev('__ns.MailTools.IsAuctionMail(3)') and not G.ev('__ns.MailTools.IsAuctionMail(6)'))
G.ex('__ns.MailTools.ahButton:Click()')
run(G)
check('AH gold took only gold, from the three auction gold mails',
      G.ev('#__takes') == 3 and G.ev('(function() for _,t in ipairs(__takes) do if t[1] ~= "money" then return false end end return true end)()'))
check('expired and won auctions stay with their items, and players\' gold stays',
      G.ev('#__inbox') == 4
      and G.ev('__inbox[1].subject') == 'Auction expired: Copper Ore' and G.ev('__inbox[1].items[1] ~= nil')
      and G.ev('__inbox[2].money') == 90000
      and G.ev('__inbox[3].subject') == 'Auction won: Wool Cloth' and G.ev('__inbox[3].items[1] ~= nil')
      and G.ev('__inbox[4].money') == 777)
log = G.ev('__lastLog()')
check('it says how much it collected and that item mail stayed',
      'Collected' in log and '3 auction house mails' in log and '2 auction mails with items stayed' in log)
G.ex('__ns.MailTools.CollectAHGold()')
run(G)
check('a second run finds nothing to collect', G.ev('#__takes') == 3 and 'No auction house gold' in G.ev('__lastLog()'))

H = client()
inbox(H, AH)
H.ex('__inboxTotal = 60; __ns.MailTools.CollectAHGold()')
run(H)
check('it says when more mail waits on the server', 'More mail is waiting' in H.ev('__lastLog()'))
check('a subject pattern copes with a reordered placeholder',
      H.ev('("Vendu : Linen"):match(__ns.MailTools.SubjectPattern("Vendu : %1$s")) ~= nil'))

# --- turning the buttons off ---
H.ex('__ns.MailTools.SetEnabled("mailAHGold", false); __ns.MailTools.SetEnabled("mailTakeAll", false)')
check('each button can be turned off', not H.ev('__ns.MailTools.ahButton:IsShown()') and not H.ev('__ns.MailTools.takeButton:IsShown()'))
H.ex('__ns.MailTools.SetEnabled("mailAHGold", true)')
check('and back on', H.ev('__ns.MailTools.ahButton:IsShown()'))

# --- entry point from the main window ---
M = client()
M.ex('''__ns.UI:Show(); __ns.UI.nav.membertools:Click()
for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key=="mailtools" then __tile=r end end''')
check('Member tools has a Mail tools tile', M.ev('__tile ~= nil'))
M.ex('__tile:GetScript("OnClick")(__tile)')
check('the tile opens the Mail tools window', M.ev('EPUGuildMailTools ~= nil and EPUGuildMailTools:IsShown()'))
M.ex('EPUGuildMailTools.ahToggle:Click()')
check('the window turns the AH gold button off', M.ev('__ns.db.settings.mailAHGold') is False
      and 'off' in M.ev('__text(EPUGuildMailTools.ahToggle)'))
M.ex('EPUGuildMailTools:Hide(); SlashCmdList.EPUGUILD("mailtools")')
check('/epu mailtools opens the same window', M.ev('EPUGuildMailTools:IsShown()'))
M.ex('MailFrame._shown = false; __fire("MAIL_CLOSED"); EPUGuildMailTools.collect:Click()')
check('Collect AH gold now waits for an open mailbox', not M.ev('EPUGuildMailTools.collect:IsEnabled()'))

for c in (A, B, C, D, E, F, G, H, M):
    if c.ev('__errors') not in (None, 0):
        check('no runtime errors', False)
        break
else:
    check('no runtime errors', True)
print('Mail tools checks:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)

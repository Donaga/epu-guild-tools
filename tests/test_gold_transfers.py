"""Gold moved to your own characters or the guild bank isn't spending.

In 0.29.0 to 0.31.1 the gold tracker counted gold mailed to an alt, or put in
the guild bank, as money spent (and gold taken back out as income), so the
daily and weekly budgets filled up with your own gold. Those are now
transfers: kept out of income, spending, the charts and the budget, listed on
their own line, and still in the breakdown and the transaction list.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(60)
# Pip Baker is another character on this account (the account list is shared).
A.ex('''local key = __ns.GuildKey()
__ns.db.accountChars = __ns.db.accountChars or {}
__ns.db.accountChars[key] = __ns.db.accountChars[key] or {}
__ns.db.accountChars[key]["Pip Baker"] = __now
__sendMoney = 0
function GetSendMailMoney() return __sendMoney end
__ns.db.goldTracker = nil
__money = 1000000; __fire("PLAYER_LOGIN")''')

def cats():
    return A.ev('(function() local o={} for _,e in ipairs(__ns.db.goldTracker.entries) do o[#o+1]=e.cat..":"..e.delta end return table.concat(o,",") end)()')

def money(delta):
    A.ex(f'__money = __money + ({delta}); __fire("PLAYER_MONEY")')

check('your other characters are recognised', A.ev('__ns.IsMyCharacter("Pip Baker") and __ns.IsMyCharacter("pip") and __ns.IsMyCharacter("Pip Baker-Forever")'))
check('a guildmate is not one of your characters', not A.ev('__ns.IsMyCharacter("Tyler Baker")') and not A.ev('__ns.IsMyCharacter("Chris Stone")'))

# Mail 50g to Pip: the 50g is a transfer, the 30c postage is mail spending.
A.ex('__fire("MAIL_SHOW"); __sendMoney = 500000; SendMail("Pip Baker", "gold", "")')
money(-500030)
check('gold mailed to your alt is a transfer, postage is spending: ' + cats(), cats() == 'alts:-500000,mail:-30')

# Mail 10g to a guildmate: that is spending, as before.
A.ex('__sendMoney = 100000; SendMail("Tyler Baker", "gift", "")')
money(-100030)
check('gold mailed to a guildmate is still mail spending', cats().endswith('mail:-100030'))

# Take gold from mail Pip sent: a transfer in, not income.
A.ex('__inbox = {{sender = "Pip Baker", money = 200000}}; TakeInboxMoney(1)')
money(200000)
check('gold taken from your alt\'s mail is a transfer in', cats().endswith('alts:200000'))
# An auction sale arriving by mail is still income.
A.ex('__inbox = {{sender = "Stormwind Auction House", money = 70000}}; TakeInboxMoney(1)')
money(70000)
check('auction gold in the mail is still income', cats().endswith('mail:70000'))
A.ex('__fire("MAIL_CLOSED")')

# Deposit and withdraw at the guild bank.
A.ex('__fire("GUILDBANKFRAME_OPENED")')
money(-300000)
money(40000)
A.ex('__fire("GUILDBANKFRAME_CLOSED")')
check('guild bank deposits and withdrawals are recorded', cats().endswith('guildbank:-300000,guildbank:40000'))

s = 'local s = __ns.GetGoldSummary(0, false)'
check('income leaves transfers out', A.ev(f'(function() {s}; return s.income end)()') == 70000)
check('spending leaves transfers out', A.ev(f'(function() {s}; return s.expense end)()') == 30 + 100030)
check('transfers in are added up on their own', A.ev(f'(function() {s}; return s.transferIn end)()') == 240000)
check('transfers out are added up on their own', A.ev(f'(function() {s}; return s.transferOut end)()') == 800000)
check('the breakdown still lists them', A.ev(f'(function() {s}; return s.byCat.alts.exp end)()') == 500000)

A.ex('__ns.db.goldTracker.budgets.enabled = true; __ns.db.goldTracker.budgets.dailyGold = 60')
check('moving gold to an alt doesn\'t use up the daily budget', A.ev('__ns.GetGoldBudgetStatus().dailySpent') == 100060)

A.ex('__ns.OpenGoldTracker()')
texts = A.ev('(function() local o={} for _,w in ipairs(EPUGuildGoldTracker.pool.used) do if w.GetText and w:GetText() then o[#o+1]=w:GetText() end end return table.concat(o,"\\n") end)()')
check('the tracker shows moved gold on its own line', 'Moved, not earned or spent' in texts)
check('the transfer category is marked as moved, not spent', 'Your Other Characters|r |cff888888(moved, not spent)' in texts)
pie = A.ev('''(function() for _,w in ipairs(EPUGuildGoldTracker.pool.used) do if w.epuPoolKind=="frame:pie" then
  local o={} for _,r in ipairs(w.epuPool.used) do if r.GetText and r:GetText() then o[#o+1]=r:GetText() end end return table.concat(o,"\\n") end end return "" end)()''')
check('the spending pie leaves transfers out', 'Guild Bank' not in pie and 'Your Other' not in pie and 'Mail' in pie)
check('nothing went wrong', not A.ev('__errors'))

print('Gold transfer checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

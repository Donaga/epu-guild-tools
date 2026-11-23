"""Vendor visits: who pays for repairs, and how the gold tracker labels them.

0.30.0 turned guild-funded repairs on for everyone without asking, judged
the guild's money by the withdrawal limit alone, and auto-sold and repaired
on bank alts. The gold tracker filed grey-item sales as repairs.
"""
from simcore import *
for name in ['Tyler Baker', 'Epu Bank']: clients[name] = Client(name)
tick(60)
T, K = clients['Tyler Baker'], clients['Epu Bank']

T.ex('__ns.OpenWorldQoLSettings()')
check('guild-funded repair starts off', T.ev('__ns.db.worldQoL.guildRepair') is False)
T.ex('__ns.db.worldQoL.guildRepair = true')
T.ex('__ns.db.worldQoL.guildRepairChosen = nil; __ns.OpenWorldQoLSettings()')
check('an unchosen setting saved by 0.30.x is switched off once', T.ev('__ns.db.worldQoL.guildRepair') is False)
T.ex("""for _,w in ipairs(EPUGuildWorldQoLConfig.widgets) do
  if w.text and w.text:GetText()=="[ ] Use Guild Bank Funds for Auto-Repair when allowed" then w:Click() end end""")
check('turning it on is remembered', T.ev('__ns.db.worldQoL.guildRepair') is True and T.ev('__ns.db.worldQoL.guildRepairChosen') is True)
T.ex('__ns.OpenWorldQoLSettings()')
check('a chosen setting survives a reload', T.ev('__ns.db.worldQoL.guildRepair') is True)

def visit(c):
    c.ex('__repaired = nil; __fire("MERCHANT_SHOW"); __fire("MERCHANT_CLOSED")')
    return c.ev('__repaired')

T.ex('__money = 500000; __repairCost = 30000; __canGuildRepair = true; __gbWithdraw = -1; __gbMoneyOverride = 10000')
check('the guild pays only what its bank holds, else the player pays', visit(T) == 'own')
T.ex('__gbMoneyOverride = 5000000; __gbWithdraw = 20000')
check('the daily withdrawal limit still applies', visit(T) == 'own')
T.ex('__gbWithdraw = 50000')
check('within the limit and the bank, the guild pays', visit(T) == 'guild')
T.ex('__ns.db.worldQoL.guildRepair = false')
check('with guild repair off, the player pays', visit(T) == 'own')

K.ex('__ns.cdb.bankAlt = true; __money = 500000; __repairCost = 30000; __canGuildRepair = true; __gbWithdraw = -1')
check('bank alts never auto-repair', visit(K) is None)

# Gold tracker: a repair is a cost; a sale at the same visit stays "vendor".
T.ex('''__ns.db.goldTracker = nil; __fire("PLAYER_LOGIN")
__fire("MERCHANT_SHOW"); RepairAllItems(false)
__money = __money + 120; __fire("PLAYER_MONEY")
__money = __money - 30000; __fire("PLAYER_MONEY")
__fire("MERCHANT_CLOSED")''')
cats = T.ev('(function() local o={} for _,e in ipairs(__ns.db.goldTracker.entries) do o[#o+1]=e.cat..":"..e.delta end return table.concat(o,",") end)()')
check('sales stay vendor and the repair is labelled repair ' + cats, cats == 'vendor:120,repair:-30000')
print('Vendor checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

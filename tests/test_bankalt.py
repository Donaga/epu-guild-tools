"""Bank alt snapshots include the character's bank on old and new bag layouts."""
import sys
from simcore import *

def total(c, who, id):
    return c.ev('(function() local s = __ns.G().bank["%s"]; return s and s.items[%d] or 0 end)()' % (who, id))

# --- newer client: reagent bag, bank tabs, and an account-wide bank that isn't his ---
A = Client("Chris Baker"); clients["Chris Baker"] = A
A.ex('Enum = Enum or {}; Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,'
     ' CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8, CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,'
     ' AccountBankTab_1 = 12, AccountBankTab_2 = 13 }')
tick(10)
A.ex('__bags[0] = {{2589, 20}}; __bags[5] = {{4306, 7}}; __bags[7] = {{2589, 40}, {14047, 3}}; __bags[12] = {{30001, 99}}')
A.ex('SlashCmdList.EPUGUILD("bankalt on")'); tick(3)
check("bags and the reagent bag are counted before the bank opens", total(A, "Chris Baker", 2589) == 20 and total(A, "Chris Baker", 4306) == 7)
check("bank list follows the game's numbering (%s)" % A.ev('table.concat(__ns.BankList(), ",")'),
      A.ev('table.concat(__ns.BankList(), ",")') .endswith("6,7,8,9,10,11") and "12" not in A.ev('table.concat(__ns.BankList(), ",")').split(","))
A.ex('__fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)'); tick(3)
check("opening the bank adds what's stored there (%d linen)" % total(A, "Chris Baker", 2589), total(A, "Chris Baker", 2589) == 60 and total(A, "Chris Baker", 14047) == 3)
check("the account-wide bank isn't counted", total(A, "Chris Baker", 30001) == 0)
A.ex('__fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)'); tick(3)
A.ex('__bags[0] = {{2589, 25}}; __fire("BAG_UPDATE")'); tick(3)
check("after closing, the remembered bank stays in the total", total(A, "Chris Baker", 2589) == 65)
A.ex('__fire("BANKFRAME_OPENED"); __bags[7] = {{14047, 3}}; __fire("PLAYERBANKSLOTS_CHANGED")'); tick(3)
check("taking items out of the bank updates it", total(A, "Chris Baker", 2589) == 25)

# --- older client: no Enum.BagIndex, bank is -1 plus bags 5-11 ---
B = Client("Tyler Baker"); clients["Tyler Baker"] = B
B.ex('Enum = Enum or {}; Enum.BagIndex = nil'); tick(10)
check("old layout bank list", B.ev('table.concat(__ns.BankList(), ",")') == "-1,5,6,7,8,9,10,11")
errs = sum((c.ev("__errors") or 0) for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
sys.exit(1 if check.failed else 0)

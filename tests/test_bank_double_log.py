"""Two officers opening the guild bank close together log each deposit once.

Each officer's addon turns the guild bank log into donation records under its
own ids. When two of them read the same log before the other's records reach
them, every deposit was logged twice: two lines in Donations, double counts
for top donors, two News shout-outs and two Discord thank-yous. Every client
now works out the same duplicates and leaves them out, without losing a gift
when only one officer is on, and without merging two real identical gifts.
"""
import sys
from pathlib import Path
from simcore import *

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "epu-discord"))
import epu_core as core

for n in ["Chris Baker", "Tyler Baker", "Pip Baker"]:
    clients[n] = Client(n)
tick(20)
A, B, P = clients["Chris Baker"], clients["Tyler Baker"], clients["Pip Baker"]
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B, P)), timeout=90)

# Tyler is a bank manager, so both Chris and Tyler log the guild bank.
A.ex('__ns.SetBankManagers({}, {["Tyler Baker"] = true})')
check("Tyler logs the guild bank too", tick_until(lambda: B.ev('__ns.IsBankTrusted(__ns.me)') == True, 30))
A.ex('SlashCmdList.EPUGUILD("need 2589 200")'); tick(3)

GB = ("(function() local n=0 for _, d in pairs(__ns.G().donations) do "
      "if d.to == 'Guild Bank' and __ns.DonationCounts(d) then n=n+1 end end return n end)()")
RAW = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.to == 'Guild Bank' then n=n+1 end end return n end)()"
FEED = ("(function() local n=0 for _, e in ipairs(__ns.FeedEntries(30)) do "
        "if e.kind == 'donation' and e.who == '%s' then n=n+1 end end return n end)()")


def open_bank(c):
    c.ex('__fire("GUILDBANKFRAME_OPENED"); __fire("GUILDBANKLOG_UPDATE")')


def close_bank(c):
    c.ex('__fire("GUILDBANKFRAME_CLOSED")')


# Pip deposits a stack of linen (a needed item, so it earns a shout-out) and
# 6 gold. Both officers open the bank in the same moment, before either one's
# records can reach the other.
log = '__gblog[1] = {{"Pip Baker", 2589, 20, 1}}; __gbmoneylog = {{"Pip Baker", 60000, 1}}'
A.ex(log); B.ex(log)
open_bank(A); open_bank(B)
tick(1.5)
check("both officers logged both deposits before syncing", A.ev(RAW) == 2 and B.ev(RAW) == 2)
tick(10)
close_bank(A); close_bank(B)
tick_until(lambda: all(c.ev(RAW) == 4 for c in (A, B, P)), 60)
check("everyone holds both officers' copies (%s, %s, %s)" % (A.ev(RAW), B.ev(RAW), P.ev(RAW)),
      all(c.ev(RAW) == 4 for c in (A, B, P)))
check("each deposit counts once for everyone (%s, %s, %s)" % (A.ev(GB), B.ev(GB), P.ev(GB)),
      all(c.ev(GB) == 2 for c in (A, B, P)))
check("everyone keeps the same copies",
      A.ev("(function() local k={} for id, d in pairs(__ns.G().donations) do if not d.dup then k[#k+1]=id end end table.sort(k) return table.concat(k, ',') end)()")
      == P.ev("(function() local k={} for id, d in pairs(__ns.G().donations) do if not d.dup then k[#k+1]=id end end table.sort(k) return table.concat(k, ',') end)()"))
check("Chris's shout-outs (linen, 6g) reach everyone once", P.ev(FEED % "Pip Baker") == 2 and A.ev(FEED % "Pip Baker") == 2)
# Had Tyler been an officer too, his copy would have made a second shout-out.
P.ex("""for id, d in pairs(__ns.G().donations) do if d.dup and d.item == 2589 then
  __ns.G().feed['don:' .. id] = { t = __now, who = 'Pip Baker', kind = 'donation', text = 'donated 20 Linen Cloth to the guild bank' } end end""")
check("a second officer's shout-out for the same deposit isn't shown", P.ev(FEED % "Pip Baker") == 2)

# Reading the log again (either officer) adds nothing.
open_bank(A); tick(4); close_bank(A); tick(6)
check("a later scan adds nothing", A.ev(RAW) == 4 and A.ev(GB) == 2)

# Two real identical gifts logged by one officer both stay, even when another
# officer only caught one of them.
log2 = '__gblog[2] = {{"Pip Baker", 4306, 5, 2}, {"Pip Baker", 4306, 5, 1}}'
A.ex(log2); open_bank(A); tick(1.5)
B.ex('__gblog[2] = {{"Pip Baker", 4306, 5, 1}}'); open_bank(B)
tick(10); close_bank(A); close_bank(B)
SILK = ("(function() local n=0 for _, d in pairs(__ns.G().donations) do "
        "if d.item == 4306 and __ns.DonationCounts(d) then n=n+1 end end return n end)()")
tick_until(lambda: P.ev(SILK) == 2 and A.ev(SILK) == 2, 60)
check("two real identical gifts both count (%s)" % P.ev(SILK), P.ev(SILK) == 2 and A.ev(SILK) == 2 and B.ev(SILK) == 2)

# With only one officer on, every deposit is still logged.
B.ex('__now = __now + 86400'); A.ex('__now = __now + 86400'); P.ex('__now = __now + 86400')
A.ex('__gblog[1] = {{"Tyler Baker", 14047, 10, 0}}; __gblog[2] = {}; __gbmoneylog = {}')
open_bank(A); tick(6); close_bank(A)
WOOL = "(function() local n=0 for _, d in pairs(__ns.G().donations) do if d.item == 14047 and __ns.DonationCounts(d) then n=n+1 end end return n end)()"
check("one officer alone still logs a deposit", tick_until(lambda: P.ev(WOOL) == 1, 30))

# Voiding still works on the copy that counts.
vid = A.ev("(function() for id, d in pairs(__ns.G().donations) do if d.item == 14047 then return id end end end)()")
A.rt.globals()["vid"] = vid
A.ex("__ns.VoidDonation(vid, true)")
check("voiding the kept copy stops it counting", tick_until(lambda: P.ev(WOOL) == 0, 30))

# The Discord bot reads the same records and thanks each gift once.
records = {}
lua_dons = A.ev("__ns.G().donations")
for k, v in lua_dons.items():
    records[str(k)] = {kk: v[kk] for kk in v.keys()}
check("the bot finds the same copies as the game",
      core.duplicate_donations(records) == {k for k, d in records.items() if d.get("dup")})

state = core.State(str(Path(__file__).resolve().parent / "_double_log_state.json"))
try:
    state.data["primed"] = True
    first = {k: v for k, v in records.items() if core.donation_logger(k) == "Tyler Baker"}
    gd = core.GuildData({"guilds": {"E Pluribus Unum": {"donations": first}}}, "E Pluribus Unum")
    thanked = core.diff(gd, state)["new_donations"]
    gd2 = core.GuildData({"guilds": {"E Pluribus Unum": {"donations": records}}}, "E Pluribus Unum")
    later = core.diff(gd2, state)["new_donations"]
    gb_real = sum(1 for d in gd2.donations.values() if d.get("to") == "Guild Bank")
    check("Tyler's copies first, then Chris's: each real gift is thanked once (%d + %d of %d)"
          % (len(thanked), len(later), gb_real), len(thanked) + len(later) == gb_real)
    check("the bot's donation list leaves out second copies", len(gd2.donations) == gb_real)
    dup_feed = [e for e in gd2.feed() if str(e["id"]).startswith("don:")]
    check("the bot's milestone feed has no duplicate shout-out", len(dup_feed) == 0)
    feed = {"don:" + k: {"t": 1, "who": "Pip Baker", "kind": "donation", "text": "donated"} for k in records}
    gd3 = core.GuildData({"guilds": {"E Pluribus Unum": {"donations": records, "feed": feed}}}, "E Pluribus Unum")
    check("the bot posts one shout-out per real gift",
          len(gd3.feed()) == len(records) - len(core.duplicate_donations(records)))
finally:
    (Path(__file__).resolve().parent / "_double_log_state.json").unlink(missing_ok=True)

errs = sum(c.ev("__errors") or 0 for c in (A, B, P))
check("no runtime errors (%d)" % errs, errs == 0)
print("Bank double log:", check.failed, "failed")
sys.exit(bool(check.failed))

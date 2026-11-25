"""The gold tracker keeps 30 days and more, not just the last 2,000 changes.

Every coin you loot is its own gold change, so a long play day can be 800 or
more and the 2,000-change list only reached back two or three days: 7 Days
and 30 Days lost everything older. Changes that roll off the list are now
added into hourly totals, kept for 90 days, and every figure (Today, 7 Days,
30 Days, All, the 7-day graph, the budget, This Char) counts them, so it
comes out the same as if every change had been kept.

Entries saved with a blank realm (WoW: Forever can report the realm name as
"") count for the realm you're on, instead of being hidden when the name
comes back filled in.
"""
import random
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(60)
A.ex('__ns.db.goldTracker = nil; __money = 1000000; __fire("PLAYER_LOGIN")')
check('the entry limit is still 2,000 and totals are kept 90 days',
      A.ev('__ns.GoldTrackerLimits.entries') == 2000 and A.ev('__ns.GoldTrackerLimits.hourlyDays') == 90)

now = A.ev('time()')
today = A.ev('(function() local d = date("*t"); d.hour, d.min, d.sec = 0, 0, 0; return time(d) end)()')

# Twelve days of play, about 700 changes a day, from this character and an
# alt, with some saved under a blank realm, a few transfers, and a handful
# from another realm that must never count here.
rnd = random.Random(7)
cats = ['loot', 'loot', 'loot', 'vendor', 'repair', 'auction', 'flight', 'training', 'guildbank', 'alts', 'other']
entries = []
for day in range(11, -1, -1):
    start = today - day * 86400
    for i in range(700 if day else 150):
        t = start + 8 * 3600 + i * 50 + rnd.randint(0, 40)
        if t >= now:
            t = now - rnd.randint(1, 3000)
        cat = rnd.choice(cats)
        delta = rnd.randint(1, 5000) * (-1 if cat in ('repair', 'flight', 'training') or rnd.random() < 0.3 else 1)
        who = 'Chris Baker' if rnd.random() < 0.8 else 'Pip Baker'
        realm = rnd.choice(['Forever', 'Forever', ''])
        if rnd.random() < 0.01:
            realm = 'Elsewhere'
        entries.append((t, who, realm, delta, cat))
entries.sort()
check('the test history is longer than the old limit (%d changes)' % len(entries), len(entries) > 6000)

lua = ',\n'.join('{t=%d,who="%s",realm="%s",delta=%d,cat="%s"}' % e for e in entries)
A.ex('__ns.db.goldTracker.entries = {' + lua + '}')

TRANSFER = {'guildbank', 'alts'}


def expected(since, until=None, char_only=False):
    inc = exp = tin = tout = 0
    for t, who, realm, delta, cat in entries:
        if t < since or (until is not None and t >= until):
            continue
        if realm == 'Elsewhere' or (char_only and who != 'Chris Baker'):
            continue
        if delta >= 0:
            if cat in TRANSFER: tin += delta
            else: inc += delta
        else:
            if cat in TRANSFER: tout -= delta
            else: exp -= delta
    return inc, exp, tin, tout


def summary(since, until=None, char_only=False):
    u = 'nil' if until is None else str(until)
    return tuple(A.ev(f'(function() local s = __ns.GetGoldSummary({since}, {str(char_only).lower()}, {u}); '
                      'return s.income, s.expense, s.transferIn, s.transferOut end)()'))


# Before the trim (all changes still in the list) the figures are already
# right, blank realm included.
check('blank-realm entries count for the realm you are on', summary(today - 30 * 86400) == expected(today - 30 * 86400))

# The next gold change trims the list to 2,000 and folds the rest into hourly totals.
A.ex('__money = __money + 1; __fire("PLAYER_MONEY")')
entries.append((A.ev('__ns.db.goldTracker.entries[#__ns.db.goldTracker.entries].t'), 'Chris Baker', 'Forever', 1, 'other'))
check('the list is back to 2,000 changes', A.ev('#__ns.db.goldTracker.entries') == 2000)
oldest_kept = A.ev('__ns.db.goldTracker.entries[1].t')
check('the list alone now starts days ago, not a week or more', oldest_kept > today - 5 * 86400)
hours = A.ev('(function() local n = 0 for _ in pairs(__ns.db.goldTracker.hourly) do n = n + 1 end return n end)()')
check('older changes became a modest number of hourly totals (%d hours)' % hours, 0 < hours <= 12 * 24)

# Whole days, Today, 7 and 30 days from midnight: exact.
for label, since in [('Today', today), ('last 7 days from midnight', today - 6 * 86400),
                     ('last 30 days from midnight', today - 29 * 86400), ('All', 0)]:
    check(f'{label} matches full history', summary(since) == expected(since))
    check(f'{label}, this character only, matches full history', summary(since, None, True) == expected(since, None, True))
for d in range(11, -1, -1):
    ds = today - d * 86400
    if summary(ds, ds + 86400) != expected(ds, ds + 86400):
        check(f'day {d} days ago matches full history', False)
        break
else:
    check('every single day matches full history', True)

# The window's 7 Days and 30 Days start mid-hour (now - 7 days): an hour of
# totals counts when it overlaps, so the figure matches from that hour's start.
for days in (7, 30):
    since = now - days * 86400
    check(f'{days} Days counts the old days (from the start of its first hour)',
          summary(since) == expected(since - since % 3600))

A.ex('__ns.db.goldTracker.budgets.enabled = true')
wk = now - 7 * 86400
check('the weekly budget counts spending that rolled off the list',
      A.ev('__ns.GetGoldBudgetStatus().weeklySpent') == expected(wk - wk % 3600)[1])
check('the daily budget is unchanged', A.ev('__ns.GetGoldBudgetStatus().dailySpent') == expected(today)[1])

# With the realm read back blank, every entry here counts (nothing is hidden).
A.ex('__realGRN = GetRealmName; GetRealmName = function() return "" end')
check('a blank realm name hides nothing', summary(0)[0] >= expected(0)[0])
A.ex('__money = __money + 2; __fire("PLAYER_MONEY")')
entries.append((A.ev('__ns.db.goldTracker.entries[#__ns.db.goldTracker.entries].t'), 'Chris Baker', '', 2, 'other'))
check('a change made while the realm reads blank is saved without one',
      A.ev('__ns.db.goldTracker.entries[#__ns.db.goldTracker.entries].realm') is None)
A.ex('GetRealmName = __realGRN')
check('and still counts once the realm name is back', A.ev('__ns.GetGoldSummary(%d, false).entries[1].delta' % (now - 60)) == 2)

# The window says older changes are kept as totals and not listed one by one.
A.ex('__ns.OpenGoldTracker()')
A.ex('''for _, w in ipairs(EPUGuildGoldTracker.pool.used) do
  if w.GetText and w:GetText() == "30 Days" and w:GetScript("OnClick") then w:GetScript("OnClick")(w) end end''')
texts = A.ev('(function() local o={} for _,w in ipairs(EPUGuildGoldTracker.pool.used) do if w.GetText and w:GetText() then o[#o+1]=w:GetText() end end return table.concat(o,"\\n") end)()')
check('30 Days explains that older changes are kept as totals', 'kept\nas hourly totals for 90 days' in texts)
inc30 = expected(now - 30 * 86400 - (now - 30 * 86400) % 3600)[0]
check('30 Days shows the full income', A.ev('(function() local s = __ns.GetGoldSummary(%d, false) return s.income end)()' % (now - 30 * 86400)) == inc30)

# Totals older than 90 days are dropped at login; nothing newer is touched.
A.ex('__ns.db.goldTracker.hourly[%d] = {[""] = {["Chris Baker"] = {loot = {500, 0}}}}' % (today - 100 * 86400 - 3600))
before = A.ev('__ns.GetGoldSummary(%d, false).income' % (today - 95 * 86400))
A.ex('__fire("PLAYER_LOGIN")')
check('totals older than 90 days are dropped', A.ev('__ns.db.goldTracker.hourly[%d]' % (today - 100 * 86400 - 3600)) is None)
check('newer totals are kept', A.ev('__ns.GetGoldSummary(%d, false).income' % (today - 95 * 86400)) == before)

# Clear History clears the totals too.
A.ex('''for _, w in ipairs(EPUGuildGoldTracker.pool.used) do
  if w.GetText and w:GetText() == "Clear History" and w:GetScript("OnClick") then w:GetScript("OnClick")(w) end end''')
check('Clear History clears the hourly totals too',
      A.ev('next(__ns.db.goldTracker.hourly) == nil and #__ns.db.goldTracker.entries == 0'))
check('and every figure is back to nothing', summary(0) == (0, 0, 0, 0))
check('nothing went wrong', not A.ev('__errors'))

print('Gold history checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

"""Guild progress: keys, raid attunements, raid status and reputation reach every guildmate.

Before 0.34 readiness and raid status went out only live, so a guildmate who
was offline when someone ticked a key never saw it. Now each member's record
syncs like needed mats: the officer keeps everyone's and hands them out at login.
"""
import re
from simcore import *

clients["Chris Baker"] = Client("Chris Baker")   # officer
clients["Tyler Baker"] = Client("Tyler Baker")   # member
A, B = clients["Chris Baker"], clients["Tyler Baker"]

# Tyler has the Scarlet Key, is Honored with the Argent Dawn and hasn't done
# any attunement quest yet.
B.ex("""
__bag = {[7146] = 1}
GetItemCount = function(id) return __bag[id] or 0 end
__quests = {}
C_QuestLog = C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted = function(q) return __quests[q] == true end
__rep = {[529] = {reaction = 6, currentStanding = 3000, currentReactionThreshold = 0, nextReactionThreshold = 12000},
         [576] = {reaction = 4, currentStanding = 0, currentReactionThreshold = 0, nextReactionThreshold = 3000}}
C_Reputation = C_Reputation or {}
C_Reputation.GetFactionDataByID = function(id) return __rep[id] end
""")
tick(20)
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)

rec = '((__ns.G().levelingProgress or {})["Tyler Baker"] or {})'
check("a member's record reaches the officer after login",
      tick_until(lambda: A.ev(rec + '.who') == "Tyler Baker", timeout=200))
check('keys in the bags tick themselves', A.ev(rec + '.done.scarlet_monastery') is True)
check('keys not in the bags stay unticked', not A.ev(rec + '.done.gnomeregan'))
check('reputation travels with the record', A.ev(rec + '.rep[529].s') == 6 and A.ev(rec + '.rep[529].v') == 3000
      and A.ev(rec + '.rep[529].m') == 12000)
check("a faction you never met isn't shared", A.ev(rec + '.rep[576]') is None)
check('raid status travels with the record', A.ev(rec + '.raid ~= nil and ' + rec + '.raid.level ~= nil'))
feed = '(function() for id, e in pairs(__ns.GuildStore().feed) do if id:find("^att:Tyler Baker") then return id end end end)()'
check("the first scan after install makes no milestones", A.ev(feed) is None and B.ev(feed) is None)

# Tyler finishes Attunement to the Core: ticked, shared and a guild milestone.
B.ex('__quests[7848] = true; __fire("QUEST_TURNED_IN", 7848)')
check('a finished attunement quest ticks itself and reaches the guild',
      tick_until(lambda: A.ev(rec + '.done.attune_mc') is True, timeout=60))
check('a new attunement is a guild milestone', A.ev(
    '(function() local e = __ns.GuildStore().feed["att:Tyler Baker:attune_mc"] return e and e.kind == "attune" and e.text == "is attuned to Molten Core" end)()'))
B.ex('__bag[12382] = 1; __fire("BAG_UPDATE_DELAYED")')
check('a new key in the bags is a milestone too', tick_until(lambda: A.ev(
    '__ns.GuildStore().feed["att:Tyler Baker:stratholme"] ~= nil'), timeout=60))
check('the Discord companion has an icon for it',
      '"attune"' in open(os.path.join(HERE, "..", "epu-discord", "bot.py"), encoding="utf-8").read())

# A tick-box still works, and an old client's live message keeps the rest.
B.ex('__ns.ToggleMyReadiness("hall_of_thanes", true)')
check('a hand-ticked dungeon reaches the guild', tick_until(lambda: A.ev(rec + '.done.hall_of_thanes') is True, timeout=30))
A.ex('local d = {rfc = true} for k in pairs(%s.done) do d[k] = true end __fire("CHAT_MSG_ADDON","EPUGuild","SE"..__ns.Serialize({who="Tyler Baker",done=d,t=%s.t+5}),"GUILD","Tyler Baker")' % (rec, rec))
check("an older version's readiness message keeps reputation and raid status",
      A.ev(rec + '.done.rfc') is True and A.ev(rec + '.rep[529].s') == 6 and A.ev(rec + '.raid ~= nil'))

# Guild views read the records.
check('the guild reputation view lists Tyler', A.ev(
    '(function() for _, e in ipairs(__ns.GetGuildRep(529)) do if e.name == "Tyler Baker" then return e.s end end end)()') == 6)
A.ex('__ns.roster["Tyler Baker"].level = 60')
check('the raid attunement list shows Tyler', A.ev(
    '(function() local done = __ns.GetGuildAttunement("attune_mc") for _, m in ipairs(done) do if m.name == "Tyler Baker" then return true end end end)()') is True)

# Forged and broken records are refused.
def forge(who, body, sender="Tyler Baker"):
    A.ex('__fire("CHAT_MSG_ADDON","EPUGuild","SD"..__ns.Serialize({levelingProgress={["%s"]=%s}}),"GUILD","%s")' % (who, body, sender))
forge("Chris Stone", '{who="Chris Stone",t=__ns.Now(),done={attune_bwl=true}}')
check("a member can't write a guildmate's record", A.ev('(__ns.G().levelingProgress or {})["Chris Stone"]') is None)
forge("Tyler Baker", '{who="Tyler Baker",t=__ns.Now()+60,done={},rep={[529]={s=9,v=1,m=10}}}')
check('a record with an impossible standing is refused', A.ev(rec + '.rep[529].s') == 6)
forge("Tyler Baker", '{who="Tyler Baker",t=__ns.Now()+60,done={},rep={[12345]={s=5,v=1,m=10}}}')
check('a record with an unknown faction is refused', A.ev(rec + '.rep[12345]') is None and A.ev(rec + '.done.attune_mc') is True)
forge("Tyler Baker", '{who="Tyler Baker",t=__ns.Now()+86400*30,done={zf=true}}')
check('a far-future record is refused', not A.ev(rec + '.done.zf'))

# Sharing reputation is optional.
tick(10)   # past the stamp of the older version's message above
B.ex('__ns.SetShareRep(false)')
check('turning sharing off clears your reputation for the guild',
      tick_until(lambda: A.ev(rec + '.rep[529]') is None, timeout=30) and A.ev(rec + '.done.attune_mc') is True)
B.ex('__ns.SetShareRep(true)')
tick_until(lambda: A.ev(rec + '.rep[529] ~= nil'), timeout=30)

# A guildmate who was offline gets everything from the officer at login.
# (an officer with no other officer online waits a few minutes for a sync first)
tick_until(lambda: A.ev('(__ns.G().levelingProgress or {})["Chris Baker"] ~= nil'), timeout=300)
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in (A, B)), timeout=90)
P = Client("Pip Baker"); clients[P.name] = P
P.ex('__now = ' + str(A.ev('__now')))
check('a guildmate who logs in later sees keys, attunements and reputation', tick_until(lambda: P.ev(
    '(function() local r = (__ns.G() and __ns.G().levelingProgress or {})["Tyler Baker"] return r and r.done.attune_mc and r.done.scarlet_monastery and r.rep[529] and r.rep[529].s == 6 end)()') is True,
    timeout=300))
check("the officer's own record reaches them too", P.ev(
    '((__ns.G().levelingProgress or {})["Chris Baker"] or {}).who') == "Chris Baker")

# Your own ticks survive a long break.
A.ex('local r = __ns.G().levelingProgress["Chris Baker"]; r.t = __ns.Now() - 86400 * 40; r.done.mytick = true; __ns.PruneCasual()')
check('your own record is kept through a long break', A.ev('__ns.G().levelingProgress["Chris Baker"].done.mytick') is True)

# The Readiness page draws with all of this.
ok = A.ev('(function() return pcall(function() __ns.OpenLevelingTools("dungeons") end) end)()')
check('the Readiness page draws with attunements and reputation', ok is True)

# Waypoints: no placeholder entrances, and givers in other zones carry their map.
lt = open(os.path.join(ADDON, "LevelingTools.lua"), encoding="utf-8").read()
zd = open(os.path.join(ADDON, "ZoneData.lua"), encoding="utf-8").read()
check('no dungeon entrance sits on a 50, 50 placeholder',
      not re.search(r'x = 50\.0, y = 50\.0', lt) and not re.search(r'\(Forever\)", levelRange = \{\d+, \d+\}, x = 50\.0, y = 50\.0', zd))
for giver, m in [("Tinkmaster Overspark (Ironforge)", 1455), ("Nogg (Orgrimmar)", 1454), ("Varimathras (Undercity)", 1458),
                 ("Nara Wildmane (Thunder Bluff)", 1456), ("Raleigh the Devout (Southshore)", 1424)]:
    got = A.ev('(function() for _, d in ipairs(__ns.DUNGEON_READINESS) do for _, q in ipairs(d.quests) do if q.giver == "%s" then return q.mapID end end end end)()' % giver)
    check('%s has its own map' % giver, got == m)

print('Guild progress checks:', check.failed, 'failed')
sys.exit(bool(check.failed))

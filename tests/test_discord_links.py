"""Discord linking by code, alt families, class/rank roles and the officer log."""
import sys, os, tempfile, json, asyncio, importlib, shutil
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
import epu_core as core
import links_roles as lr

for n in ["Chris Baker", "Tyler Baker"]:
    clients[n] = Client(n)
tick(20)
A, B = clients["Chris Baker"], clients["Tyler Baker"]

# --- in game: /epu link ---
check("hash matches between Lua and Python",
      B.ev('__ns.LinkClaimHash("ABCDEF23","Tyler Baker")') == lr.claim_hash("ABCDEF23", "Tyler Baker"))
check("codes are normalised like the bot shows them",
      B.ev('__ns.NormalizeLinkCode(" abcd-ef23 ")') == "ABCDEF23" and lr.normalize_code("abcd ef23") == "ABCDEF23")
B.ex('SlashCmdList.EPUGUILD("link nonsense")'); tick(3)
check("a bad code publishes nothing", A.ev('next(__ns.CasualStore().discordClaims)') is None)
B.ex('SlashCmdList.EPUGUILD("link abcd-ef23")'); tick(5)
check("the claim reaches the officer", A.ev('__ns.CasualStore().discordClaims["Tyler Baker"].h') == lr.claim_hash("ABCDEF23", "Tyler Baker"))
check("the claim holds no code in the clear", "ABCDEF23" not in A.ev('__ns.Serialize(__ns.CasualStore().discordClaims)'))
check("the code is kept account-wide", B.ev('__ns.db.discordCode') == "ABCDEF23")
B.ex('__ns.Send("D",{discordClaims={["Chris Stone"]={who="Chris Stone",t=__ns.Now(),h="1-2"}}})'); tick(4)
check("a member can't claim someone else's character", A.ev('__ns.CasualStore().discordClaims["Chris Stone"]') is None)
B.ex('__ns.PublishDiscordClaim()'); tick(3)
check("republishing an unchanged claim sends nothing new",
      A.ev('__ns.CasualStore().discordClaims["Tyler Baker"].off') is None)
check("roster details are saved for roles",
      A.ev('__ns.G().memberInfo["Tyler Baker"].r') == "Member" and A.ev('__ns.G().memberInfo["Chris Baker"].r') == "Officer")

# --- companion side ---
WOW = tempfile.mkdtemp().replace(os.sep, "/")
os.makedirs(WOW + "/WTF/Account/ACCT/SavedVariables", exist_ok=True)
os.makedirs(WOW + "/Interface/AddOns/EPUGuild", exist_ok=True)
SV = f"{WOW}/WTF/Account/ACCT/SavedVariables/EPUGuild.lua"
A.ex(f'__dumpSV("{SV}")')
gd = core.load_guild_data(SV, "E Pluribus Unum")
check("companion reads claims and roster details",
      "Tyler Baker" in (gd.g.get("discordClaims") or {}) and lr.member_info(gd)["Tyler Baker"]["r"] == "Member")

st = core.State(os.path.join(WOW, "state.json"))
st.data["link_codes"] = {"ABCDEF23": {"user": "500", "t": 0}, "ZZZZZZZZ": {"user": "600", "t": 0}}
out = lr.process_links(gd, st)
check("a matching claim links the character to the code's owner",
      st.characters_for(500) == ["Tyler Baker"] and [e["kind"] for e in out] == ["linked"])
check("processing again changes nothing", lr.process_links(gd, st) == [])
check("code_for reuses a user's code", lr.code_for(st, 500) == "ABCDEF23" and len(lr.code_for(st, 777)) == 8)

# confirmed alt groups follow a linked main
gd.g["alts"] = {"grp": {"main": "Tyler Baker", "chars": {1: "Tyler Baker", 2: "Pip Baker"}, "t": 1}}
gd.g["altVerified"] = {"Tyler Baker": {"id": "grp", "t": 1}, "Pip Baker": {"id": "grp", "t": 1}}
out = lr.process_links(gd, st)
check("a confirmed alt links automatically", "Pip Baker" in st.characters_for(500) and out[0]["how"] == "alt")
gd.g["altVerified"]["Chris Stone"] = {"id": "other", "t": 1}
check("an unconfirmed alt claim does not link", "Chris Stone" not in st.characters_for(500))

st.link(600, "Chris Stone")
gd.g["discordClaims"]["Chris Stone"] = {"who": "Chris Stone", "t": 5, "h": lr.claim_hash("ABCDEF23", "Chris Stone")}
out = lr.process_links(gd, st)
check("a character already linked elsewhere is reported, not moved",
      st.characters_for(600) == ["Chris Stone"] and out and out[0]["kind"] == "conflict")

# roles
info = lr.member_info(gd)
info["Pip Baker"]["c"], info["Pip Baker"]["cn"] = "PRIEST", "Priest"
info["Tyler Baker"]["c"], info["Tyler Baker"]["cn"] = "MAGE", "Mage"
gd.g["memberInfo"] = info
st.link(700, "Chris Baker")
want = lr.desired_roles(gd, st, ["Veteran", "Member", "Initiate"])
check("class roles come from every linked character", {"class:MAGE", "class:PRIEST"} <= want["500"])
check("rank role comes from the main", "rank:Member" in want["500"])
check("officer ranks never get an automated role", not any(k.startswith("rank:") for k in want["700"]))
st.data.setdefault("mains", {})["500"] = "Pip Baker"
info["Pip Baker"]["r"] = "Initiate"
want = lr.desired_roles(gd, st, ["Veteran", "Member", "Initiate"])
check("a /main picked in Discord sets the rank role", "rank:Initiate" in want["500"] and "rank:Member" not in want["500"])
st.data["mains"].pop("500")
want = lr.desired_roles(gd, st, ["Veteran", "Initiate"], member_role="Member")
check("every linked guild member gets the member role, officers included",
      "member:Member" in want["500"] and "member:Member" in want["700"] and not any(k.startswith("rank:") for k in want["700"]))
check("a Member-rank main gets no duplicate rank role", not any(k.startswith("rank:") for k in want["500"]))
info["Pip Baker"]["r"] = "Initiate"; st.data["mains"]["500"] = "Pip Baker"
want = lr.desired_roles(gd, st, ["Veteran", "Initiate"], member_role="Member")
check("an Initiate gets both Member and Initiate", {"member:Member", "rank:Initiate"} <= want["500"])
st.data["mains"].pop("500"); info["Pip Baker"]["r"] = "Member"
check("role names use the class's display name", lr.role_name("class:PRIEST", gd) == "Priest" and lr.role_name("rank:Member") == "Member")
adds, removes = lr.plan_changes({"1": {"a", "b"}, "2": set()}, {"1": {"b", "c"}, "2": {"a"}})
check("plan adds and removes only the difference", adds == {"1": {"a"}} and removes == {"1": {"c"}, "2": {"a"}})
check("a big sweep needs confirmation", lr.needs_confirmation({str(i): {"x"} for i in range(9)}, 20)
      and not lr.needs_confirmation({str(i): {"x"} for i in range(3)}, 20))

# officer log
prev = {"A": {"r": "Member", "ri": 3, "l": 59}, "B": {"r": "Initiate", "ri": 4, "l": 10}, "C": {"r": "Member", "ri": 3, "l": 5}}
cur = {"A": {"r": "Veteran", "ri": 2, "l": 60}, "C": {"r": "Member", "ri": 3, "l": 5}, "D": {"r": "Initiate", "ri": 4, "l": 1}}
left = {}
ev, ok = lr.roster_events(prev, cur, (60,), left)
kinds = sorted((e["kind"], e["who"]) for e in ev)
check("roster changes are found", ok and kinds == [("joined", "D"), ("left", "B"), ("level", "A"), ("promoted", "A")])
ev, ok = lr.roster_events(cur, {**cur, "B": {"r": "Initiate", "ri": 4, "l": 10}}, (60,), left)
check("a member who comes back is a return, not a join", [e["kind"] for e in ev] == ["returned"])
ev, ok = lr.roster_events(cur, {"A": cur["A"]}, (60,), {})
check("a roster that suddenly loses most members is ignored", not ok and ev == [])
check("log lines read well", "promoted: Member → Veteran" in lr.event_line({"kind": "promoted", "who": "A", "from": "Member", "to": "Veteran"}))

# nickname suggestions
people = [("900", "Tyler Baker"), ("901", "Newbie Stone"), ("902", "Pip | Newbie"), ("903", "Random Name")]
sug = lr.nickname_matches(gd, st, people)
check("nickname matches skip linked users and ambiguous names", sug == [("901", "Newbie Stone")])

# --- bot glue: roles on a fake server ---
class Role:
    def __init__(self, i, name): self.id, self.name = i, name
class Member:
    def __init__(self, i): self.id, self.roles, self.bot = i, [], False
    async def add_roles(self, *rs, reason=None): self.roles += [r for r in rs if r not in self.roles]
    async def remove_roles(self, *rs, reason=None): self.roles = [r for r in self.roles if r not in rs]
class Guild:
    def __init__(self):
        self.roles, self.members_by = [Role(1, "Officer"), Role(2, "Member")], {}
    def get_role(self, i): return next((r for r in self.roles if r.id == i), None)
    def get_member(self, i): return self.members_by.get(i)
    async def fetch_member(self, i):
        import discord
        if i not in self.members_by: raise discord.NotFound(type("R", (), {"status": 404, "reason": "x"})(), "gone")
        return self.members_by[i]
    async def create_role(self, name, mentionable=False, reason=None):
        r = Role(100 + len(self.roles), name); self.roles.append(r); return r

cfgdir = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "wow_path": WOW}, open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py"):
    shutil.copy(os.path.join(os.path.dirname(core.__file__), f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check("everyone linked gets Member; Veteran and Initiate are extra rank roles",
      bot.cfg["member_role"] == "Member" and bot.cfg["rank_roles"] == ["Veteran", "Initiate"])
G = Guild()
for i in (500, 600, 700): G.members_by[i] = Member(i)
bot.client.get_guild = lambda i: G
bot.state = st
res = asyncio.run(bot.sync_roles(gd))
names = lambda m: sorted(r.name for r in m.roles)
check("linked members get class roles", "Mage" in names(G.members_by[500]) and "Priest" in names(G.members_by[500]))
check("your existing rank role is used instead of a duplicate",
      G.get_role(2) in G.members_by[500].roles and len([r for r in G.roles if r.name == "Member"]) == 1
      and any("existing **Member**" in l for l in res["lines"]))
check("the officer gets Member but never the Officer role", G.get_role(2) in G.members_by[700].roles
      and G.get_role(1) not in G.members_by[700].roles)
G.members_by[700].roles.append(G.get_role(1))
st.data["links"]["500"] = []
st.data.pop("roles_sig", None)
asyncio.run(bot.sync_roles(gd))
check("unlinking takes the bot's own roles away but leaves your adopted role",
      [r.name for r in G.members_by[500].roles] == ["Member"] and G.get_role(1) in G.members_by[700].roles)

class Perms:
    def __init__(self, **kw): self.__dict__.update(kw)
G2 = Guild()
G2.roles.append(Role(3, "Veteran")); G2.roles[-1].permissions = Perms(kick_members=True)
G2.roles[0].name = "Initiate"   # officer-looking roles: here a plain role named like a rank
G2.me = type("Me", (), {"top_role": type("Top", (), {"position": 5})()})()
for r in G2.roles: r.position = 1
G2.get_role(2).position = 9    # above the bot
st2 = core.State(os.path.join(WOW, "state2.json"))
st2.link(800, "Tyler Baker"); st2.link(801, "Pip Baker")
info["Pip Baker"]["r"] = "Veteran"
gd.g["memberInfo"] = info
gd.g["altVerified"] = {}
bot.state = st2
bot.client.get_guild = lambda i: G2
for i in (800, 801): G2.members_by[i] = Member(i)
res = asyncio.run(bot.sync_roles(gd))
check("a role with moderator permissions is never taken over",
      G2.get_role(3) not in G2.members_by[801].roles and any("moderator permissions" in l for l in res["lines"]))
check("a role above the bot is never taken over",
      G2.get_role(2) not in G2.members_by[800].roles and any("above the bot" in l for l in res["lines"]))
bot.cfg["adopt_existing_roles"] = "none"
G3 = Guild(); G3.members_by[900] = Member(900)
st3 = core.State(os.path.join(WOW, "state3.json")); st3.link(900, "Tyler Baker")
bot.state = st3; bot.client.get_guild = lambda i: G3
res = asyncio.run(bot.sync_roles(gd))
check("adopting can be turned off", G3.get_role(2) not in G3.members_by[900].roles and any("already exists" in l for l in res["lines"]))


# Cached role IDs must not bypass the adoption safety gate on later syncs.
for case in ("administrator", "officer config", "officer rename", "hierarchy", "integration"):
    bot.cfg.update(adopt_existing_roles="rank", officer_role="Officer", member_role="Member")
    server = Guild()
    server.me = type("Me", (), {"top_role": type("Top", (), {"position": 5})()})()
    role = server.get_role(2)
    role.position, role.permissions, role.managed = 1, Perms(), False
    server.members_by[950] = Member(950)
    saved = core.State(os.path.join(WOW, "safety-" + case + ".json"))
    saved.link(950, "Tyler Baker")
    bot.state = saved
    bot.client.get_guild = lambda i: server
    asyncio.run(bot.sync_roles(gd))
    check(case + ": safe role initially adopted", role in server.members_by[950].roles)
    if case == "administrator": role.permissions.administrator = True
    elif case == "officer config": bot.cfg["officer_role"] = "Member"
    elif case == "officer rename": role.name = "Officer"
    elif case == "hierarchy": server.me.top_role.position = 1
    else: role.managed = True
    result = asyncio.run(bot.sync_roles(gd))
    check(case + ": safety change invalidates unchanged-roster cache",
          bool(result.get("lines")) and role in server.members_by[950].roles)
    server.members_by[951] = Member(951)
    saved.link(951, "Chris Stone")
    asyncio.run(bot.sync_roles(gd, confirm=True))
    check(case + ": confirmation cannot assign unsafe cached role",
          role not in server.members_by[951].roles)
    bot.cfg["member_role"] = ""
    asyncio.run(bot.sync_roles(gd, confirm=True))
    check(case + ": unsafe role no longer desired is not removed",
          role in server.members_by[950].roles
          and "member:Member" in saved.data["role_holders"]["950"])
    role.name, role.position, role.permissions, role.managed = "Member", 1, Perms(), False
    server.me.top_role.position = 5
    bot.cfg.update(officer_role="Officer", member_role="Member")
    asyncio.run(bot.sync_roles(gd))
    check(case + ": sync resumes once role is safe",
          role in server.members_by[951].roles)


# Permissions can change while member fetches or earlier writes are awaited.
for phase in ("fetch", "add", "remove"):
    bot.cfg.update(adopt_existing_roles="rank", officer_role="Officer", member_role="Member", class_roles=False)
    server = Guild()
    role = server.get_role(2)
    role.permissions = Perms()
    saved = core.State(os.path.join(WOW, "race-" + phase + ".json"))
    saved.data["managed_roles"] = {"member:Member": "2"}
    for uid, char in ((960, "Tyler Baker"), (961, "Chris Stone")):
        saved.link(uid, char)
        server.members_by[uid] = Member(uid)
    bot.state = saved
    bot.client.get_guild = lambda i: server
    if phase == "fetch":
        server.get_member = lambda i: None
        async def fetch_and_elevate(i):
            role.permissions.administrator = True
            return server.members_by[i]
        server.fetch_member = fetch_and_elevate
    else:
        method = "add_roles" if phase == "add" else "remove_roles"
        async def mutate_and_elevate(self, *rs, reason=None):
            await getattr(Member, method)(self, *rs, reason=reason)
            role.permissions.administrator = True
        import types
        for member in server.members_by.values():
            setattr(member, method, types.MethodType(mutate_and_elevate, member))
        if phase == "remove":
            for uid, member in server.members_by.items():
                member.roles = [role]
                saved.data.setdefault("role_holders", {})[str(uid)] = ["member:Member"]
            bot.cfg["member_role"] = ""
    result = asyncio.run(bot.sync_roles(gd, confirm=True))
    present = sum(role in member.roles for member in server.members_by.values())
    check(phase + ": an awaited permission change blocks subsequent unsafe writes",
          present == (0 if phase == "fetch" else 1))
    check(phase + ": counts reflect only executed writes",
          result["added"] == (1 if phase == "add" else 0)
          and result["removed"] == (1 if phase == "remove" else 0))
    check(phase + ": unsafe skipped writes are not cached", "roles_sig" not in saved.data)
    check(phase + ": holder bookkeeping reflects actual writes",
          all(("member:Member" in saved.data["role_holders"].get(str(uid), []))
              == (role in member.roles) for uid, member in server.members_by.items()))

print("Discord link tests:", check.failed, "failed")
sys.exit(1 if check.failed else 0)

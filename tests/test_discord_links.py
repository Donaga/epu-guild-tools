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
check("rank roles default to Veteran, Member and Initiate", bot.cfg["rank_roles"] == ["Veteran", "Member", "Initiate"])
G = Guild()
for i in (500, 600, 700): G.members_by[i] = Member(i)
bot.client.get_guild = lambda i: G
bot.state = st
res = asyncio.run(bot.sync_roles(gd))
names = lambda m: sorted(r.name for r in m.roles)
check("linked members get class roles", "Mage" in names(G.members_by[500]) and "Priest" in names(G.members_by[500]))
check("an existing role a person made is never taken over",
      "Member" not in [r.name for r in G.members_by[500].roles if r.id >= 100] and any("already exists" in l for l in res["lines"]))
check("the officer gets no rank role", all(not r.name.startswith("Officer") or r.id == 1 for r in G.members_by[700].roles)
      and G.get_role(1) not in G.members_by[700].roles)
G.members_by[700].roles.append(G.get_role(1))
st.data["links"]["500"] = []
st.data.pop("roles_sig", None)
asyncio.run(bot.sync_roles(gd))
check("unlinking takes only the bot's roles away", G.members_by[500].roles == [] and G.get_role(1) in G.members_by[700].roles)

print("Discord link tests:", check.failed, "failed")
sys.exit(1 if check.failed else 0)

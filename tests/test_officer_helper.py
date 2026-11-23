"""Any officer's PC running the sync helper can carry Discord.

Before, Discord approvals, announcements, onboarding steps and helper
whitelist grants reached the game only through the organiser's own PC (the
one running the bot), and announcements, milestones and the guild MOTD only
reached Discord from that PC's game. With the organiser away, they all
waited. Now a helper the organiser marks "officer": true carries them too,
the addon applies them only on an officer's character, and several officers
carrying the same action change one record, so nothing is posted twice.
"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

import simcore
from simcore import *

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "epu-discord"))
import epu_core as core
import shared_bridge as bridge

# Two more officers. Chris (the organiser, whose PC runs the bot) is away.
simcore.ROSTER += [("Ana Stone", "Officer", 1), ("Ben Stone", "Officer", 1)]
for n in ["Ana Stone", "Ben Stone", "Tyler Baker", "Pip Baker"]:
    clients[n] = Client(n)
tick(20)
ANA, BEN, TY, PIP = (clients[n] for n in ["Ana Stone", "Ben Stone", "Tyler Baker", "Pip Baker"])
tick_until(lambda: all(c.ev('__ns.QueueLength()') == 0 for c in clients.values()), timeout=90)
now = int(ANA.ev('__now'))
bridge.time.time = lambda: now
for c in clients.values():
    c.ex("__ns.G().bank.Bank={v=__now,money=0,items={[2589]=20},seen={[2589]=true}}")

GUILD = "E Pluribus Unum"
root = Path(tempfile.mkdtemp())


def pc(name, drop=False):
    """One PC: its WoW folder and its shared helper folder (both ends of the cloud copy).
    drop: an EPU that reads the inbox from the EPUGuild_Inbox addon."""
    wow = root / name / "wow"
    addon = wow / "Interface" / "AddOns" / "EPUGuild"
    addon.mkdir(parents=True)
    (addon / "EPUGuild.toc").write_text(("## OptionalDeps: EPUGuild_Inbox\n" if drop else "") + "InviteRequests.lua\n")
    if drop:
        Path(core.inbox_drop_path(str(wow))).parent.mkdir(parents=True, exist_ok=True)
        Path(core.inbox_drop_path(str(wow))).write_text("EPUGuildInboxDrop = {}\n")
    sv = wow / "WTF" / "Account" / "ACCOUNT" / "SavedVariables" / "EPUGuild.lua"
    sv.parent.mkdir(parents=True)
    bot_side, helper_side = root / name / "bot-folder", root / name / "helper-folder"
    bot_side.mkdir(); helper_side.mkdir()
    return {"wow": wow, "addon": addon, "sv": sv, "bot": bot_side, "helper": helper_side}


PCS = {"ana": pc("ana", drop=True), "ben": pc("ben"), "tyler": pc("tyler")}
CHARS = {"ana": "Ana Stone", "ben": "Ben Stone", "tyler": "Tyler Baker"}
LUA = {"ana": ANA, "ben": BEN, "tyler": TY}
SECRETS = {k: (k[0] * 48) for k in PCS}
cfg = {"guild_key": GUILD, "sync_helpers": {
    k: {"enabled": True, "secret": SECRETS[k], "characters": [CHARS[k]], "folders": [str(PCS[k]["bot"])],
        "officer": k != "tyler"} for k in PCS}}
helpers = {k: {"helper": k, "guild": GUILD, "secret": SECRETS[k], "characters": [CHARS[k]],
               "folder": str(PCS[k]["helper"]), "wow_path": str(PCS[k]["wow"])} for k in PCS}
local = {k: {} for k in PCS}
state = core.State(str(root / "state.json"))


def to_helpers():
    bridge.publish(cfg, state)
    for k, p in PCS.items():
        if (p["bot"] / "to-game.json").exists():
            shutil.copy(p["bot"] / "to-game.json", p["helper"] / "to-game.json")


def cycle(k):
    """The helper app's 15-second check, then its upload copied to the bot's side."""
    out = bridge.helper_cycle(helpers[k], local[k])
    if (PCS[k]["helper"] / "to-bot.json").exists():
        shutil.copy(PCS[k]["helper"] / "to-bot.json", PCS[k]["bot"] / "to-bot.json")
    return out


def reload(k):
    """/reload: save SavedVariables, load Inbox.lua, apply it."""
    c = LUA[k]
    c.ex('__dumpSV("' + str(PCS[k]["sv"]).replace("\\", "/") + '")')
    for f in (PCS[k]["addon"] / "Inbox.lua", Path(core.inbox_drop_path(str(PCS[k]["wow"])))):
        if f.exists():
            c.ex(f.read_text())
    c.ex("__ns.ProcessInbox()")


def kinds(k):
    packet = bridge.verify(PCS[k]["helper"] / "to-game.json", k, GUILD, "feed", SECRETS[k])
    return {e["kind"] for e in packet["payload"]["entries"]}


# Discord: Pip asks for linen, an officer approves it, posts an announcement,
# ticks an onboarding step; the organiser's config whitelists a helper.
req = state.queue_request("Pip Baker", 2589, "Linen Cloth", 3, "for bags", "Pip")
rid = "d-" + req["id"]
state.queue_status(rid, "approved", "Dana (Discord)")
news = state.queue_news("Raid night", "Molten Core Friday 8pm", "Dana")
state.data["inbox"].append({"id": "link-1", "kind": "checklist", "who": "Pip Baker", "step": "discord", "done": True,
                            "note": "Linked Pip", "t": now})
state.save()

# A helper app from before this change says nothing about officer actions, so
# it must not be sent them (it would reject the whole feed).
to_helpers()
check("a helper that hasn't said it understands officer actions isn't sent them",
      all("status" not in kinds(k) for k in PCS))
for k in PCS:
    LUA[k].ex('__dumpSV("' + str(PCS[k]["sv"]).replace("\\", "/") + '")')
    cycle(k)
to_helpers()
check("officer helpers are sent approvals, announcements and onboarding steps",
      {"status", "news", "checklist", "request"} <= kinds("ana") and {"status", "news"} <= kinds("ben"))
check("a member's helper still gets only member actions", kinds("tyler") == {"request"})

# The organiser is away. Ana's helper (on an EPU that reads the inbox addon)
# and Ben's (on the old Inbox.lua) stage everything; at her /reload her
# officer client applies it and shares it through guild sync.
for k in PCS:
    cycle(k)
check("Ana's helper writes officer actions to the inbox addon",
      '"status"' in Path(core.inbox_drop_path(str(PCS["ana"]["wow"]))).read_text())
reload("ana")
ANA.rt.globals()["rid"] = rid
for c in clients.values():
    c.rt.globals()["rid"] = rid
check("Ana's client creates and approves the Discord request",
      ANA.ev("__ns.G().requests[rid] and __ns.G().requests[rid].status") == "approved")
NID = "d-" + news["id"]
for c in clients.values():
    c.rt.globals()["nid"] = NID
check("Ana's client posts the Discord announcement in game",
      ANA.ev("__ns.GuildStore().news[nid] ~= nil and __ns.GuildStore().news[nid].title") == "Raid night")
check("the approval reaches members by guild sync",
      tick_until(lambda: PIP.ev("__ns.G().requests[rid] and __ns.G().requests[rid].status") == "approved", 60))
check("the announcement reaches members by guild sync",
      tick_until(lambda: PIP.ev("__ns.GuildStore().news[nid] ~= nil"), 60))

# Ben's helper carried the same actions. His client changes the same records.
reload("ben")
tick(15)
check("a second officer carrying them makes no second request or announcement",
      sum(1 for k in PIP.ev("__ns.G().requests").keys() if str(k).startswith("d-")) == 1
      and PIP.ev("(function() local n=0 for k in pairs(__ns.GuildStore().news) do if k == nid then n=n+1 end end return n end)()") == 1)
check("the request is still approved", PIP.ev("__ns.G().requests[rid].status") == "approved")

# Tyler's member client was handed nothing officer-only.
reload("tyler")
check("a member's helper never applies an approval",
      TY.ev("__ns.IsTrusted(__ns.me)") == False and "status" not in kinds("tyler"))

# Back to Discord: each officer's helper exports its game, receipts included.
ANA.ex("__ns.G().motd = {text='Raid Friday, bring flasks', t=__now}")
ANA.ex("__ns.AddFeed('level', 'reached level 60', 'Pip Baker', 'F-pip60')")
TY.ex("__ns.GuildStore().news['forged'] = {t=__now, u=__now, by='Tyler', title='Free gold', text='Whisper me'}")
for k in PCS:
    LUA[k].ex('__dumpSV("' + str(PCS[k]["sv"]).replace("\\", "/") + '")')
    local[k].pop("uploaded", None)
    out = cycle(k)
    if k != "tyler":
        check(k + "'s helper says it carries officer actions", "officer actions" in out)
uploaded = json.loads((PCS["tyler"]["bot"] / "to-bot.json").read_text())
check("a member's helper doesn't export announcements", "news" not in uploaded["payload"]["snapshot"]["game"])

bridge.reconcile_helper_acks(cfg, state)
check("officer receipts clear the carried actions from the bot's queue",
      [e["kind"] for e in state.data["inbox"]] == [], )

# The organiser's own game data is days old: no news, no MOTD.
base = core.GuildData({"guilds": {ANA.ev("__ns.GuildKey()"): {"bank": {}, "requests": {}, "needs": {"v": 0, "list": {}}}}}, GUILD)
merged, _ = bridge.merge_public(base, cfg)
check("the approval reaches Discord through an officer helper", merged.requests[rid]["status"] == "approved")
check("in-game announcements reach Discord through an officer helper", NID in merged.news())
check("the guild MOTD reaches Discord through an officer helper", (merged.motd() or {}).get("text") == "Raid Friday, bring flasks")
check("milestones reach Discord through an officer helper", any(e["id"] == "F-pip60" for e in merged.feed()))
check("a member's helper can't put an announcement in Discord", "forged" not in merged.news())

# Several officer helpers, one post each.
state.data["primed"] = True
state.data.setdefault("news_posted", {})
changes = core.diff(merged, state)
check("the announcement is posted once", [n for n, _ in changes["news"]].count(NID) == 1)
check("the milestone is posted once", [e["id"] for e in changes["new_feed"]].count("F-pip60") == 1)
for nid, e in changes["news"]:
    state.data["news_posted"][nid] = {"message_id": 1, "u": e.get("u") or 0}
again = core.diff(bridge.merge_public(base, cfg)[0], state)
check("a later read posts nothing again", again["news"] == [] and again["new_feed"] == [] and "motd" not in again)

# The organiser can switch a helper back to member only.
cfg["sync_helpers"]["ben"]["officer"] = False
state.queue_status(rid, "filled", "Dana (Discord)")
to_helpers()
check("a helper switched off officer duty gets no officer actions", "status" not in kinds("ben"))
packet = bridge.verify(PCS["ben"]["helper"] / "to-game.json", "ben", GUILD, "feed", SECRETS["ben"])
check("its feed says so", packet["payload"]["officer"] is False)
cycle("ben")
uploaded = json.loads((PCS["ben"]["bot"] / "to-bot.json").read_text())
check("and it stops exporting announcements", "news" not in uploaded["payload"]["snapshot"]["game"])
bridge.reconcile_helper_acks(cfg, state)
check("its receipts no longer clear officer actions", any(e["kind"] == "status" for e in state.data["inbox"]))

shutil.rmtree(root, ignore_errors=True)
errs = sum(c.ev("__errors") or 0 for c in clients.values())
check("no runtime errors (%d)" % errs, errs == 0)
print("Officer helper:", check.failed, "failed")
sys.exit(bool(check.failed))

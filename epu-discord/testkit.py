"""Try the EPU Discord bot without WoW.

Builds a fake WoW folder (testwow/) holding the same SavedVariables file the
addon writes, and lets you play the game's side from the command line while
the bot runs. The bot can't tell the difference.

  python testkit.py setup "Donlock Gaeilge"   build fake data with you as officer + bank
  python testkit.py use                       point the bot at the fake folder
  python testkit.py unuse                     point it back at real WoW

Then, with the bot running, act out the game side:
  python testkit.py show                      what the fake game has right now
  python testkit.py reload                    an officer /reload: applies Discord requests/approvals
  python testkit.py request "Brenna Ashford" "Linen Cloth" 20 [note]   (add  --to "Pip Quickfoot"  to mail an alt)
  python testkit.py approve 1   |  reject 1 [reason]  |  fill 1
  python testkit.py need "Silk Cloth" 60 [goal]
  python testkit.py stock "Linen Cloth" 120   [--guild]   set a count (your bank, or the guild bank)
  python testkit.py donate "Brenna Ashford" "Wool Cloth" 40 [--guild]
  python testkit.py gold 250 [--guild]        set gold on hand (in gold)

Each change saves the file, just like a /reload in game, and the bot picks it up
within about 15 seconds. Restart the bot after `use` or `unuse`.
"""
from __future__ import annotations

import json
import os
import sys
import time

import epu_core as core

HERE = os.path.dirname(os.path.abspath(__file__))
TEST_DIR = os.path.join(HERE, "testwow")
SV_PATH = os.path.join(TEST_DIR, "WTF", "Account", "TESTACCOUNT", "SavedVariables", "EPUGuild.lua")
GUILD = "E Pluribus Unum - Forever"
CONFIG = os.path.join(HERE, "config.json")

# Vanilla item IDs, good enough for testing (Forever's may differ).
CATALOG = {
    2589: "Linen Cloth", 2592: "Wool Cloth", 4306: "Silk Cloth", 4338: "Mageweave Cloth", 14047: "Runecloth",
    2996: "Bolt of Linen Cloth", 4238: "Linen Bag", 1251: "Linen Bandage", 2581: "Heavy Linen Bandage",
    118: "Minor Healing Potion", 858: "Lesser Healing Potion", 929: "Healing Potion",
    2770: "Copper Ore", 2840: "Copper Bar", 2318: "Light Leather", 2447: "Peacebloom", 765: "Silverleaf",
}
FAKE_MEMBERS = ["Brenna Ashford", "Torvik Emberforge", "Lysa Moonbrook", "Donlock Stone", "Pip Quickfoot"]


def now() -> int:
    return int(time.time())


# ---------------------------------------------------------------------------
def load() -> dict:
    if not os.path.exists(SV_PATH):
        sys.exit("No test data yet. Run:  python testkit.py setup \"Your Name\"")
    with open(SV_PATH, encoding="utf-8") as f:
        return core.parse_saved_variables(f.read())["EPUGuildDB"]


def save(db: dict):
    os.makedirs(os.path.dirname(SV_PATH), exist_ok=True)
    with open(SV_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\nEPUGuildDB = " + core.lua_value(db) + "\nEPUGuildCharDB = nil\n")


def guild(db: dict) -> dict:
    return db["guilds"][GUILD]


def me(db: dict) -> str:
    return db["testkit"]["me"]


def item_id(db: dict, text: str) -> int:
    if text.isdigit():
        return int(text)
    want = text.lower().strip("[]")
    names = {**CATALOG, **{int(k): v for k, v in db.get("itemNames", {}).items()}}
    for i, n in names.items():
        if n.lower() == want:
            return i
    sys.exit(f"Unknown item '{text}'. Try one of: " + ", ".join(sorted(CATALOG.values())))


def member(db: dict, text: str) -> str:
    gd = core.GuildData(db, GUILD)
    name, candidates = gd.resolve_member(text)
    if name:
        return name
    if candidates:
        sys.exit("Which one? " + ", ".join(candidates))
    sys.exit(f"'{text}' isn't in the fake roster: " + ", ".join(gd.members))


GB_KEY = "Guild Bank"


def holder(db: dict, use_guild: bool) -> str:
    """Your bank character, or the in-game guild bank (created on first use)."""
    if not use_guild:
        return me(db)
    guild(db)["bank"].setdefault(GB_KEY, {"v": now(), "money": 0, "items": {}, "bankTime": now(), "guild": True})
    return GB_KEY


def take_flag(args: list, flag: str) -> tuple[list, bool]:
    return [a for a in args if a != flag], flag in args


def bank_items(db: dict, who: str | None = None) -> dict:
    return guild(db)["bank"][who or me(db)]["items"]


def touch_bank(db: dict, who: str | None = None):
    snap = guild(db)["bank"][who or me(db)]
    snap["v"] = max(now(), int(snap.get("v", 0)) + 1)
    snap["bankTime"] = now()


def numbered_requests(db: dict) -> list[tuple[str, dict]]:
    reqs = guild(db)["requests"]
    return sorted(reqs.items(), key=lambda kv: kv[1].get("t", 0))


def pick(db: dict, n: str) -> tuple[str, dict]:
    rows = numbered_requests(db)
    try:
        return rows[int(n) - 1]
    except (ValueError, IndexError):
        sys.exit("Request number not found. Run:  python testkit.py show")


def set_status(db: dict, rid: str, status: str, reason: str = ""):
    r = guild(db)["requests"][rid]
    r["status"] = status
    r["by"] = me(db)
    r["u"] = max(now(), int(r.get("u", 0)) + 1)
    if reason:
        r["reason"] = reason


# ---------------------------------------------------------------------------
def cmd_setup(args):
    name = " ".join(args) or "Donlock Gaeilge"
    if len(name.split()) < 2:
        sys.exit("Use your full Forever name, first and last, e.g.  python testkit.py setup \"Donlock Gaeilge\"")
    t = now()
    members = [name] + [m for m in FAKE_MEMBERS if m != name]
    db = {
        "testkit": {"me": name},
        "settings": {"minimapAngle": 200},
        "itemNames": dict(CATALOG),
        "inboxDone": {},
        "guilds": {GUILD: {
            "officerRank": 1,
            "members": members,
            "needs": {"v": t, "list": {2589: 200, 2592: 100, 4306: {"q": 60, "k": "g"}, 929: 20, 1251: 40}},
            "bank": {name: {"v": t, "money": 1234567, "bankTime": t,
                            "items": {2589: 140, 2592: 30, 4306: 10, 1251: 25, 118: 12, 2840: 18, 2447: 22}}},
            "requests": {
                f"{FAKE_MEMBERS[0]}-{t - 600}-101": {"who": FAKE_MEMBERS[0], "item": 4238, "qty": 2, "note": "bags for my alt",
                                                     "status": "pending", "t": t - 600, "u": t - 600},
            },
            "donations": {},
            "crafters": {FAKE_MEMBERS[1]: {"t": t, "lvl": 34, "profs": {"Blacksmithing": 165, "Mining": 170}}},
            # Brenna plays Pip as an alt (the addon learns this from their account)
            "alts": {"acct-brenna": {"t": t, "main": "Brenna Ashford", "chars": ["Brenna Ashford", "Pip Quickfoot"]},
                     "acct-me": {"t": t, "main": name, "chars": [name]}},
        }},
    }
    save(db)
    inbox = core.inbox_path(TEST_DIR)
    os.makedirs(os.path.dirname(inbox), exist_ok=True)
    core.write_inbox(inbox, [])
    print(f"Fake guild ready with you as {name} (officer, holding the bank).")
    print("Fake guildmates: " + ", ".join(members[1:]))
    print("Next:  python testkit.py use   then restart the bot.")


def cmd_use(_args):
    with open(CONFIG, encoding="utf-8") as f:
        cfg = json.load(f)
    if os.path.abspath(cfg.get("wow_path", "")) != os.path.abspath(TEST_DIR):
        cfg["real_wow_path"] = cfg.get("wow_path")
    cfg["wow_path"] = TEST_DIR
    cfg["account"] = ""
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    print("The bot now reads the fake folder. Restart it (close the window, run start.bat).")


def cmd_unuse(_args):
    with open(CONFIG, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["wow_path"] = cfg.pop("real_wow_path", None) or r"C:\Program Files (x86)\World of Warcraft\_forever_"
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    print("The bot is pointed back at real WoW. Restart it.")
    print("Before going live: delete state.json if you tested on a different Discord server than the real one.")


def cmd_show(_args):
    db = load()
    gd = core.GuildData(db, GUILD)
    st = gd.status_summary()
    print(f"You: {me(db)}    Gold (all banks): {core.money_text(st['gold'])}")
    for name, snap in guild(db)["bank"].items():
        stock = ", ".join(f"{gd.item_name(i)} {c}" for i, c in sorted(snap.get("items", {}).items(), key=lambda kv: gd.item_name(kv[0])))
        print(f"  {name}: {core.money_text(snap.get('money'))} | {stock or 'empty'}")
    print("\nNeeds:")
    for n in st["needs"]:
        print(f"  {n['name']}: {n['have']}/{n['target']}{' (goal)' if n['kind'] == 'goal' else ''}")
    print("\nRequests:")
    for i, (rid, r) in enumerate(numbered_requests(db), 1):
        via = " (via Discord)" if r.get("via") == "discord" else ""
        to = f", mail to {r['to']}" if r.get("to") else ""
        print(f"  {i}. {gd.item_name(r['item'])} x{r['qty']} for {gd.label(r['who'])}{to}{via}: {core.status_of(r)}")
    pending = [e for e in core.State(os.path.join(HERE, "state.json")).data.get("inbox", [])
               if e["id"] not in db.get("inboxDone", {})]
    if pending:
        print(f"\n{len(pending)} Discord action(s) waiting. Run:  python testkit.py reload")


def cmd_reload(_args):
    """What an officer's addon does at /reload: apply Inbox.lua, then save."""
    db = load()
    g = guild(db)
    done = db.setdefault("inboxDone", {})
    entries = core.State(os.path.join(HERE, "state.json")).data.get("inbox", [])
    applied = 0
    gd = core.GuildData(db, GUILD)
    for e in entries:
        if e["id"] in done:
            continue
        if e["kind"] == "request":
            who = gd.resolve_member(e["who"])[0] or e["who"]
            rid = "d-" + e["id"]
            g["requests"].setdefault(rid, {"who": who, "item": e["item"], "qty": e["qty"], "note": e.get("note", ""),
                                           "status": "pending", "t": now(), "u": now(), "via": "discord",
                                           "discord": e.get("discord", ""), **({"to": e["to"]} if e.get("to") else {})})
        elif e["kind"] == "status" and e["rid"] in g["requests"]:
            r = g["requests"][e["rid"]]
            if core.status_of(r) in ("pending", "approved"):
                set_status(db, e["rid"], e["status"], e.get("reason", ""))
                r["by"] = e.get("by") or me(db)
        else:
            continue
        done[e["id"]] = now()
        applied += 1
    save(db)
    print(f"Reloaded: applied {applied} Discord action(s). The bot updates within ~15 seconds.")


def cmd_request(args):
    if len(args) < 2:
        sys.exit('Usage: python testkit.py request "Member Name" "Item" [qty] [note]')
    to = None
    if "--to" in args:
        i = args.index("--to")
        to, args = args[i + 1], args[:i] + args[i + 2:]
    db = load()
    who, item = member(db, args[0]), item_id(db, args[1])
    to = member(db, to) if to else None
    qty = int(args[2]) if len(args) > 2 else 1
    t = now()
    rid = f"{who}-{t}-{t % 900 + 100}"
    officer = who == me(db)
    guild(db)["requests"][rid] = {"who": who, "item": item, "qty": qty, "note": " ".join(args[3:]),
                                  "status": "approved" if officer else "pending", "t": t, "u": t,
                                  **({"by": who} if officer else {}), **({"to": to} if to and to != who else {})}
    save(db)
    print(f"{who} requested {CATALOG.get(item, item)} x{qty} in game.")


def _status_cmd(status):
    def run(args):
        if not args:
            sys.exit(f"Usage: python testkit.py {status} <request number>   (see: python testkit.py show)")
        db = load()
        rid, r = pick(db, args[0])
        set_status(db, rid, {"approve": "approved", "reject": "rejected", "fill": "filled"}[status], " ".join(args[1:]))
        if status == "fill":
            items = bank_items(db)
            items[r["item"]] = max(0, int(items.get(r["item"], 0)) - int(r["qty"]))
            touch_bank(db)
        save(db)
        print(f"Request {args[0]} {status}{'d' if status.endswith('e') else 'ed'} in game.")
    return run


def cmd_need(args):
    if len(args) < 2:
        sys.exit('Usage: python testkit.py need "Item" <qty> [goal]   (qty 0 removes)')
    db = load()
    g = guild(db)
    i, q = item_id(db, args[0]), int(args[1])
    if q <= 0:
        g["needs"]["list"].pop(i, None)
    else:
        g["needs"]["list"][i] = {"q": q, "k": "g"} if "goal" in args[2:] else q
    g["needs"]["v"] = max(now(), int(g["needs"]["v"]) + 1)
    save(db)
    print("Needs updated.")


def cmd_stock(args):
    args, use_guild = take_flag(args, "--guild")
    if len(args) < 2:
        sys.exit('Usage: python testkit.py stock "Item" <count> [--guild]')
    db = load()
    who = holder(db, use_guild)
    i, n = item_id(db, args[0]), int(args[1])
    if n > 0:
        bank_items(db, who)[i] = n
    else:
        bank_items(db, who).pop(i, None)
    touch_bank(db, who)
    save(db)
    print(f"{who} now holds {n}x {CATALOG.get(i, i)}.")


def cmd_donate(args):
    args, use_guild = take_flag(args, "--guild")
    if len(args) < 2:
        sys.exit('Usage: python testkit.py donate "Member Name" "Item" [qty] [--guild]')
    db = load()
    who, item = member(db, args[0]), item_id(db, args[1])
    n = int(args[2]) if len(args) > 2 else 1
    to = holder(db, use_guild)
    items = bank_items(db, to)
    items[item] = int(items.get(item, 0)) + n
    touch_bank(db, to)
    t = now()
    guild(db)["donations"][f"{me(db)}:{t}:{len(guild(db)['donations']) + 1}"] = {
        "t": t, "who": who, "item": item, "n": n, "money": 0, "to": to}
    save(db)
    print(f"{who} {'deposited' if use_guild else 'mailed you'} {n}x {CATALOG.get(item, item)}"
          f"{' in the guild bank' if use_guild else ''}.")


def cmd_gold(args):
    args, use_guild = take_flag(args, "--guild")
    if not args:
        sys.exit("Usage: python testkit.py gold <amount in gold> [--guild]")
    db = load()
    who = holder(db, use_guild)
    guild(db)["bank"][who]["money"] = int(float(args[0]) * 10000)
    touch_bank(db, who)
    save(db)
    print(f"{who} now has {args[0]}g.")


COMMANDS = {
    "setup": cmd_setup, "use": cmd_use, "unuse": cmd_unuse, "show": cmd_show, "reload": cmd_reload,
    "request": cmd_request, "approve": _status_cmd("approve"), "reject": _status_cmd("reject"),
    "fill": _status_cmd("fill"), "need": cmd_need, "stock": cmd_stock, "donate": cmd_donate, "gold": cmd_gold,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0)
    COMMANDS[sys.argv[1]](sys.argv[2:])

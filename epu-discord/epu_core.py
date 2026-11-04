"""EPU Discord companion: the parts that don't need Discord.

* Reads the EPUGuild SavedVariables file that WoW writes on /reload and logout.
* Writes Inbox.lua, which the addon loads at the next login or /reload.
* Works out what changed since the last read (new requests, status changes,
  donations) so the bot can post or edit Discord messages.
"""
from __future__ import annotations

import csv
import glob
import io
import json
import os
import re
import time
import urllib.request
import uuid

# ---------------------------------------------------------------------------
# Lua SavedVariables parser (the subset WoW writes: tables, strings, numbers,
# booleans, nil, and "-- [n]" comments).
# ---------------------------------------------------------------------------
_TOKEN = re.compile(r"""
    (?P<ws>\s+|--[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

_ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def _unescape(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        c = body[i]
        if c.isdigit():
            j = i
            while j < len(body) and j < i + 3 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i:j])))
            i = j
        elif c == "\n":
            out.append("\n")
            i += 1
        else:
            out.append(_ESC.get(c, c))
            i += 1
    return "".join(out)


def _tokens(text: str):
    pos = 0
    for m in _TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError(f"unexpected text at {pos}: {text[pos:pos + 20]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        val = m.group()
        if kind == "str":
            yield ("str", _unescape(val[1:-1]))
        elif kind == "num":
            yield ("num", int(val, 16) if val.lower().startswith(("0x", "-0x")) else (float(val) if any(c in val for c in ".eE") else int(val)))
        elif kind == "name":
            yield ("name", val)
        else:
            yield ("op", val)
    if pos != len(text):
        raise ValueError(f"unexpected text at {pos}")


class _Parser:
    def __init__(self, text: str):
        self.toks = list(_tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, kind=None, val=None):
        t = self.peek()
        if t[0] is None or (kind and t[0] != kind) or (val is not None and t[1] != val):
            raise ValueError(f"expected {kind} {val!r}, got {t!r}")
        self.i += 1
        return t

    def value(self):
        kind, val = self.peek()
        if kind == "op" and val == "{":
            return self.table()
        self.i += 1
        if kind in ("str", "num"):
            return val
        if kind == "name":
            return {"true": True, "false": False, "nil": None}.get(val, val)
        raise ValueError(f"bad value {val!r}")

    def table(self):
        self.take("op", "{")
        out, n = {}, 1
        while True:
            kind, val = self.peek()
            if kind == "op" and val == "}":
                self.i += 1
                return out
            if kind == "op" and val == "[":
                self.i += 1
                key = self.value()
                self.take("op", "]")
                self.take("op", "=")
                out[key] = self.value()
            elif kind == "name" and self.toks[self.i + 1] == ("op", "="):
                self.i += 2
                out[val] = self.value()
            else:
                out[n] = self.value()
                n += 1
            kind, val = self.peek()
            if kind == "op" and val in (",", ";"):
                self.i += 1

    def chunk(self):
        out = {}
        while self.peek()[0] is not None:
            _, name = self.take("name")
            self.take("op", "=")
            out[name] = self.value()
        return out


def parse_saved_variables(text: str) -> dict:
    return _Parser(text).chunk()


# ---------------------------------------------------------------------------
# Lua writer (for Inbox.lua)
# ---------------------------------------------------------------------------
def lua_value(v, indent=0) -> str:
    pad = "  " * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        out = ['"']
        for ch in v:
            if ch in '"\\':
                out.append("\\" + ch)
            elif ch == "\n":
                out.append("\\n")
            elif ord(ch) < 32:
                out.append("\\%03d" % ord(ch))
            else:
                out.append(ch)
        out.append('"')
        return "".join(out)
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        inner = ",\n".join(pad + "  " + lua_value(x, indent + 1) for x in v)
        return "{\n" + inner + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = []
        for k, x in v.items():
            key = k if isinstance(k, str) and re.fullmatch(r"[A-Za-z_]\w*", k) else "[" + lua_value(k) + "]"
            items.append(pad + "  " + key + " = " + lua_value(x, indent + 1))
        return "{\n" + ",\n".join(items) + ",\n" + pad + "}"
    raise TypeError(f"can't write {type(v)} to Lua")


INBOX_HEADER = (
    "-- Written by the EPU Discord companion. Leave this file in place; it is\n"
    "-- replaced automatically. Entries here are applied by an officer's client\n"
    "-- at login or /reload.\n"
)


def safe_replace(tmp: str, path: str) -> None:
    """Move tmp over path. On Windows a sync app (OneDrive, Dropbox), an antivirus scan
    or WoW itself can hold the file for a moment, so retry, then fall back to a plain copy."""
    last = None
    for attempt in range(15):
        try:
            os.replace(tmp, path)
            return
        except PermissionError as e:
            last = e
            time.sleep(0.2 * (attempt + 1) if attempt < 5 else 1.0)
    try:
        with open(tmp, encoding="utf-8") as src, open(path, "w", encoding="utf-8") as dst:
            dst.write(src.read())
        os.remove(tmp)
    except OSError:
        raise last


def write_inbox(path: str, entries: list) -> None:
    text = INBOX_HEADER + "EPUGuildInbox = " + lua_value(entries) + "\n"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    safe_replace(tmp, path)


# ---------------------------------------------------------------------------
# Locating files
# ---------------------------------------------------------------------------
def find_saved_variables(wow_path: str) -> list[str]:
    pattern = os.path.join(wow_path, "WTF", "Account", "*", "SavedVariables", "EPUGuild.lua")
    return sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)


def inbox_path(wow_path: str) -> str:
    return os.path.join(wow_path, "Interface", "AddOns", "EPUGuild", "Inbox.lua")


# ---------------------------------------------------------------------------
# Guild data access
# ---------------------------------------------------------------------------
ACTIVE = {"pending", "approved", "open"}
STATUS_LABEL = {"open": "pending"}


def status_of(r: dict) -> str:
    s = r.get("status", "pending")
    return STATUS_LABEL.get(s, s)


def is_craft(r: dict) -> bool:
    """A craft request goes to a crafter, not the bank."""
    return isinstance(r, dict) and bool(r.get("crafter"))


CRAFT_LABEL = {"pending": "asked", "approved": "accepted", "filled": "made", "rejected": "declined", "cancelled": "cancelled"}


def status_label(r: dict) -> str:
    st = status_of(r)
    return CRAFT_LABEL.get(st, st) if is_craft(r) else st


class GuildData:
    """A read of one guild's data out of EPUGuildDB."""

    def __init__(self, db: dict, guild_key: str | None = None):
        self.db = db or {}
        guilds = self.db.get("guilds") or {}
        if guild_key and guild_key in guilds:
            self.key = guild_key
        elif guild_key:
            matches = [k for k in guilds if k.lower().startswith(guild_key.lower())]
            self.key = matches[0] if matches else None
        else:
            self.key = next(iter(guilds), None)
        self.g = guilds.get(self.key) or {}
        self.item_names = {int(k): v for k, v in (self.db.get("itemNames") or {}).items() if isinstance(k, (int, float))}
        self.inbox_done = self.db.get("inboxDone") or {}

    @property
    def members(self) -> list[str]:
        """Guild roster names as the addon saw them ("First Surname" on Forever)."""
        m = self.g.get("members") or {}
        names = list(m.values()) if isinstance(m, dict) else list(m)
        return sorted(n for n in names if isinstance(n, str))

    def resolve_member(self, text: str) -> tuple[str | None, list[str]]:
        """Match typed text to a member: full name (any case), or a first name
        only one member has. Returns (name or None, candidates if ambiguous)."""
        want = " ".join((text or "").split()).lower()
        if not want:
            return None, []
        exact = [n for n in self.members if n.lower() == want]
        if exact:
            return exact[0], []
        firsts = [n for n in self.members if n.split(" ")[0].lower() == want]
        if len(firsts) == 1:
            return firsts[0], []
        return None, firsts

    def group_of(self, name: str) -> dict | None:
        """The main/alt group a character belongs to (newest claim wins)."""
        best = None
        for rec in (self.g.get("alts") or {}).values():
            if not isinstance(rec, dict):
                continue
            chars = rec.get("chars") or {}
            chars = list(chars.values()) if isinstance(chars, dict) else list(chars)
            if name in chars and (best is None or rec.get("t", 0) > best["t"]):
                best = {"t": rec.get("t", 0), "main": rec.get("main") or name,
                        "chars": [rec.get("main")] + sorted(c for c in chars if c != rec.get("main"))}
        return best

    def main_of(self, name: str) -> str:
        g = self.group_of(name)
        return g["main"] if g else name

    def label(self, name: str) -> str:
        main = self.main_of(name)
        return f"{name} ({main})" if main and main != name else name

    @property
    def requests(self) -> dict:
        return self.g.get("requests") or {}

    @property
    def donations(self) -> dict:
        """Donation records, minus ones an officer voided as mistakes."""
        return {k: d for k, d in (self.g.get("donations") or {}).items() if not (isinstance(d, dict) and d.get("void"))}

    @property
    def bank(self) -> dict:
        return self.g.get("bank") or {}

    def item_name(self, item_id) -> str:
        try:
            return self.item_names.get(int(item_id)) or EXTRA_NAMES.get(int(item_id)) or f"item {item_id}"
        except (TypeError, ValueError):
            return str(item_id)

    def bank_count(self, item_id) -> int:
        n = 0
        for s in self.bank.values():
            if isinstance(s, dict) and not s.get("retired"):
                n += int((s.get("items") or {}).get(item_id, 0) or 0)
        return n

    def needs(self) -> list[dict]:
        rows = []
        for item_id, v in ((self.g.get("needs") or {}).get("list") or {}).items():
            if isinstance(v, dict):
                target, kind = int(v.get("q") or 0), ("goal" if v.get("k") == "g" else "restock")
            else:
                target, kind = int(v or 0), "restock"
            if target <= 0:
                continue
            have = self.bank_count(item_id)
            rows.append({"id": item_id, "name": self.item_name(item_id), "target": target, "kind": kind,
                         "have": have, "missing": max(0, target - have)})
        rows.sort(key=lambda r: (r["have"] / r["target"], r["name"]))
        return rows

    def bank_items(self) -> list[dict]:
        totals: dict = {}
        for s in self.bank.values():
            if isinstance(s, dict) and not s.get("retired"):
                for item_id, c in (s.get("items") or {}).items():
                    totals[item_id] = totals.get(item_id, 0) + int(c or 0)
        return sorted(({"id": i, "name": self.item_name(i), "count": c} for i, c in totals.items()), key=lambda r: r["name"])

    def is_designated(self, who: str, prof: str) -> bool:
        des = ((self.g.get("policy") or {}).get("designated") or {}).get(prof) or {}
        names = des.values() if isinstance(des, dict) else des
        return who in names

    def crafters_for(self, item_id: int | None = None, spell: str | None = None) -> list[dict]:
        """Who can craft an item (or an enchant by name): guild crafters first, then by skill."""
        out = []
        for who, rec in (self.g.get("recipes") or {}).items():
            for prof, p in ((rec or {}).get("profs") or {}).items():
                items = p.get("items") or {}
                items = list(items.values()) if isinstance(items, dict) else list(items)
                spells = p.get("spells") or {}
                spells = list(spells.values()) if isinstance(spells, dict) else list(spells)
                key = None
                if item_id is not None and item_id in items:
                    key = f"item:{item_id}"
                elif spell:
                    key = next((f"spell:{s}" for s in spells if s.lower() == spell.lower()), None)
                if key:
                    diff = (p.get("diff") or {}).get(key)
                    out.append({"who": who, "prof": prof, "rank": p.get("rank"), "designated": self.is_designated(who, prof),
                                "skillup": diff in ("o", "y"), "key": key})
        out.sort(key=lambda c: (not c["designated"], -(c["rank"] or 0), c["who"]))
        return out

    def feed(self) -> list[dict]:
        """Guild milestones, oldest first."""
        rows = [{"id": k, **v} for k, v in (self.g.get("feed") or {}).items() if isinstance(v, dict)]
        rows.sort(key=lambda e: e.get("t", 0))
        return rows

    def motd(self) -> dict | None:
        m = self.g.get("motd")
        return m if isinstance(m, dict) and m.get("text") else None

    def news(self) -> dict:
        """Announcements by id (including removed ones, so their posts can be taken down)."""
        return {k: v for k, v in (self.g.get("news") or {}).items() if isinstance(v, dict)}

    def mats_for(self, key) -> list[tuple[int, int]]:
        """Reagents for a recipe key ("item:123" or "spell:Name") as (item id, count)."""
        m = (self.g.get("mats") or {}).get(key) if key else None
        r = (m or {}).get("r") or []
        r = list(r.values()) if isinstance(r, dict) else list(r)
        return [(int(r[i]), int(r[i + 1])) for i in range(0, len(r) - 1, 2)]

    def request_name(self, r: dict) -> str:
        if r.get("itemName"):
            return r["itemName"]
        if r.get("item"):
            return self.item_name(r["item"])
        return r.get("spell") or "?"

    def craftable_items(self) -> dict[int, str]:
        names = {}
        for rec in (self.g.get("recipes") or {}).values():
            for p in ((rec or {}).get("profs") or {}).values():
                items = p.get("items") or {}
                for i in (items.values() if isinstance(items, dict) else items):
                    names[int(i)] = self.item_name(i)
        return names

    def known_items(self) -> dict[int, str]:
        names = dict(self.item_names)
        for row in self.needs():
            names.setdefault(row["id"], row["name"])
        return names

    def shopping_list(self) -> list[dict]:
        """Same rule as the addon's Shopping tab: need target plus approved
        requests, minus what's banked."""
        demand: dict = {}
        for row in self.needs():
            demand.setdefault(row["id"], {"need": 0, "req": 0})["need"] = row["target"]
        for r in self.requests.values():
            if not isinstance(r, dict) or r.get("status") != "approved":
                continue
            if is_craft(r):
                if r.get("mats") == "bank":       # the bank supplies the materials
                    for item_id, n in self.mats_for(r.get("key")):
                        demand.setdefault(item_id, {"need": 0, "req": 0})["req"] += n * int(r.get("qty") or 1)
            elif r.get("item"):
                demand.setdefault(r["item"], {"need": 0, "req": 0})["req"] += int(r.get("qty") or 0)
        rows = []
        for item_id, d in demand.items():
            have = self.bank_count(item_id)
            buy = max(0, d["need"] + d["req"] - have)
            if buy > 0:
                rows.append({"id": item_id, "name": self.item_name(item_id), "buy": buy, "have": have, **d})
        rows.sort(key=lambda r: (-r["buy"], r["name"]))
        return rows

    def status_summary(self) -> dict:
        """Everything the pinned status post shows."""
        banks = [(name, s) for name, s in self.bank.items() if isinstance(s, dict) and not s.get("retired")]
        counts = {"pending": 0, "approved": 0, "crafts": 0}
        for r in self.requests.values():
            if isinstance(r, dict):
                st = status_of(r)
                if is_craft(r):
                    if st in ("pending", "approved"):
                        counts["crafts"] += 1
                elif st in counts:
                    counts[st] += 1
        return {
            "needs": self.needs(),
            "shopping": self.shopping_list(),
            "gold": sum(int(s.get("money") or 0) for _, s in banks),
            "banks": [name for name, _ in banks],
            "requests": counts,
            "updated": max([int(s.get("v") or 0) for _, s in banks] + [int((self.g.get("needs") or {}).get("v") or 0)]),
        }


def load_guild_data(sv_path: str, guild_key: str | None = None) -> GuildData:
    with open(sv_path, encoding="utf-8", errors="replace") as f:
        chunk = parse_saved_variables(f.read())
    return GuildData(chunk.get("EPUGuildDB") or {}, guild_key)


# ---------------------------------------------------------------------------
# Companion state (links, posted messages, queued inbox entries)
# ---------------------------------------------------------------------------
class State:
    def __init__(self, path: str):
        self.path = path
        self.data = {"links": {}, "posted": {}, "donations_seen": [], "inbox": [], "primed": False}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                self.data.update(json.load(f))

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=2)
        safe_replace(tmp, self.path)

    # Discord user -> WoW characters (first one is their main)
    def characters_for(self, discord_id: int) -> list[str]:
        v = self.data["links"].get(str(discord_id))
        if isinstance(v, str):          # links saved by an older version
            return [v]
        return list(v or [])

    def link(self, discord_id: int, *characters: str, main: str | None = None) -> list[str]:
        chars = self.characters_for(discord_id)
        for c in characters:
            if c and c not in chars:
                chars.append(c)
        if main and main in chars:
            chars.remove(main)
            chars.insert(0, main)
        self.data["links"][str(discord_id)] = chars
        self.save()
        return chars

    def unlink(self, discord_id: int, character: str) -> list[str]:
        chars = [c for c in self.characters_for(discord_id) if c.lower() != character.lower()]
        self.data["links"][str(discord_id)] = chars
        self.save()
        return chars

    def character_for(self, discord_id: int) -> str | None:
        chars = self.characters_for(discord_id)
        return chars[0] if chars else None

    # Inbox
    def queue_request(self, who: str, item_id: int | None, item_name: str, qty: int, note: str, discord_name: str,
                      to: str | None = None) -> dict:
        e = {"id": uuid.uuid4().hex[:10], "kind": "request", "who": who, "item": item_id, "itemName": item_name,
             "qty": qty, "note": note[:80], "discord": discord_name, "t": int(time.time())}
        if to and to != who:
            e["to"] = to
        self.data["inbox"].append(e)
        self.save()
        return e

    def queue_news(self, title: str, text: str, by: str, nid: str | None = None, edit: bool = False,
                   posted_at: int | None = None, quiet: bool = False) -> dict:
        """An officer's /announce, or a post copied from the announcements channel
        (nid = "m<message id>" so edits and deletes find it again).
        quiet: show it in News but don't pop it up (older posts copied at startup)."""
        if nid and not edit:
            # still waiting for the game? replace that entry instead of adding another
            for old in self.data["inbox"]:
                if old.get("kind") == "news" and old.get("nid") == nid:
                    old.update(title=title[:60], text=text[:400], by=by, posted=posted_at or old.get("posted"))
                    old.pop("quiet", None)
                    if quiet:
                        old["quiet"] = True
                    self.save()
                    return old
        e = {"id": uuid.uuid4().hex[:10], "kind": "news", "title": title[:60], "text": text[:400], "by": by, "t": int(time.time())}
        if posted_at:
            e["posted"] = int(posted_at)
        if quiet:
            e["quiet"] = True
        if nid:
            e["nid"] = nid
        if edit:
            e["edit"] = True
        self.data["inbox"].append(e)
        self.save()
        return e

    def queue_news_remove(self, nid: str) -> dict:
        e = {"id": uuid.uuid4().hex[:10], "kind": "news_remove", "nid": nid, "t": int(time.time())}
        self.data["inbox"].append(e)
        self.save()
        return e

    def queue_status(self, rid: str, status: str, by: str, reason: str = "") -> dict:
        e = {"id": uuid.uuid4().hex[:10], "kind": "status", "rid": rid, "status": status,
             "by": by, "reason": reason[:80], "t": int(time.time())}
        self.data["inbox"].append(e)
        self.save()
        return e

    def prune_inbox(self, inbox_done: dict) -> bool:
        before = len(self.data["inbox"])
        self.data["inbox"] = [e for e in self.data["inbox"] if e["id"] not in inbox_done]
        if len(self.data["inbox"]) != before:
            self.save()
            return True
        return False

    # Posted Discord messages, keyed by request id
    def posted(self, rid: str) -> dict | None:
        return self.data["posted"].get(rid)

    def set_posted(self, rid: str, message_id: int, status: str):
        self.data["posted"][rid] = {"message_id": message_id, "status": status}
        self.save()


# ---------------------------------------------------------------------------
# Change detection
# ---------------------------------------------------------------------------
def diff(gd: GuildData, state: State) -> dict:
    """What to post or edit in Discord since the last read.

    The first run only records what already exists (plus any still-open
    requests), so connecting the bot doesn't flood the channel with history.
    """
    out = {"new_requests": [], "changed_requests": [], "new_donations": [], "new_feed": [], "news": []}
    primed = state.data.get("primed", False)
    for rid, r in gd.requests.items():
        if not isinstance(r, dict):
            continue
        st = status_of(r)
        posted = state.posted(rid)
        if posted is None:
            if st in ("pending", "approved") or (primed and st != "cancelled"):
                out["new_requests"].append((rid, r))
        elif posted.get("status") != st:
            out["changed_requests"].append((rid, r))
    seen = set(state.data.get("donations_seen", []))
    new_seen = []
    for did, d in gd.donations.items():
        if did in seen:
            continue
        new_seen.append(did)
        if primed and isinstance(d, dict):
            out["new_donations"].append(d)
    if new_seen:
        state.data["donations_seen"] = (state.data.get("donations_seen", []) + new_seen)[-2000:]
    # milestones: post each once; skip old ones (first run, or the bot was off for a while)
    feed_seen = set(state.data.get("feed_seen", []))
    fresh = []
    now = time.time()
    for e in gd.feed():
        if e["id"] in feed_seen:
            continue
        fresh.append(e["id"])
        if primed and now - (e.get("t") or 0) < 2 * 86400:
            out["new_feed"].append(e)
    if fresh:
        state.data["feed_seen"] = (state.data.get("feed_seen", []) + fresh)[-2000:]
    # in-game guild message of the day
    m = gd.motd()
    if m and state.data.get("motd_posted") != m["text"]:
        if primed:
            out["motd"] = m["text"]
        state.data["motd_posted"] = m["text"]
    # announcements: new, edited or removed
    posted = state.data.setdefault("news_posted", {})
    for nid, e in gd.news().items():
        p = posted.get(nid)
        if p is None:
            if not e.get("removed") and (primed or now - (e.get("t") or 0) < 7 * 86400):
                out["news"].append((nid, e))
        elif (e.get("u") or 0) > (p.get("u") or 0):
            out["news"].append((nid, e))
    if not primed:
        state.data["primed"] = True
    out["new_donations"].sort(key=lambda d: d.get("t", 0))
    return out


ITEM_ID_RE = re.compile(r"item[=:](\d+)(?:/([A-Za-z0-9\-]+))?")


def message_to_news(content: str, embeds: list | None = None) -> tuple[str, str]:
    """Turn a Discord post into (title, text) for the game's announcement pop-up.
    The first line becomes the title if there's more than one line."""
    text = (content or "").strip()
    title = ""
    for em in embeds or []:
        et, ed = (em.get("title") or "").strip(), (em.get("description") or "").strip()
        if not text and ed:
            text = ed
        if not title and et:
            title = et
    # WoW's fonts have no emoji: drop them (and the joiners/variation marks that glue them together)
    text = re.sub("[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0E\uFE0F\u200D\u20E3]", "", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    # pings mean nothing in game: drop @everyone/@here, and lines that are only pings
    text = re.sub(r"@(everyone|here)\b", "", text)
    text = "\n".join(ln for ln in text.splitlines() if not re.fullmatch(r"\s*(@\S+\s*)+", ln))
    # markdown the game can't show: **bold**, __underline__, headers, >quotes
    text = re.sub(r"(\*\*|__|~~|`)", "", text)
    lines = [re.sub(r"^(#+\s*|>\s*)", "", ln).strip() for ln in text.splitlines()]
    lines = [ln for ln in lines if ln]
    if title:
        title = re.sub("[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0E\uFE0F\u200D\u20E3]", "", title).strip()
    if not title and len(lines) > 1 and len(lines[0]) <= 60:
        title, lines = lines[0], lines[1:]
    body = "\n".join(lines)
    if len(body) > 400:
        body = body[:370].rstrip() + "... (more on Discord)"
    return (title or "Announcement")[:60], body
    """'pattern-woolen-reagent-bag' -> 'Pattern Woolen Reagent Bag' (Wowhead URL text)."""
    if not slug:
        return None
    words = [w for w in slug.split("-") if w]
    small = {"of", "the", "and", "a", "an", "to", "in", "on"}
    return " ".join(w if (i and w in small) else w[:1].upper() + w[1:] for i, w in enumerate(words)) or None


def resolve_item(text: str, known: dict[int, str]) -> tuple[int | None, str | None]:
    """Item ID and name from autocomplete value, an ID, a Wowhead link, or a known name."""
    text = (text or "").strip()
    if text.startswith("id:") and text[3:].isdigit():
        i = int(text[3:])
        return i, known.get(i) or EXTRA_NAMES.get(i)
    if text.isdigit():
        i = int(text)
        return i, known.get(i) or EXTRA_NAMES.get(i)
    m = ITEM_ID_RE.search(text)
    if m:
        i = int(m.group(1))
        return i, known.get(i) or EXTRA_NAMES.get(i) or name_from_slug(m.group(2))
    want = text.strip("[]").lower()
    for i, name in known.items():
        if name.lower() == want:
            return i, name
    for i, name in EXTRA_NAMES.items():          # the full game item list, if loaded
        if name.lower() == want:
            return i, name
    return None, None


def money_text(copper) -> str:
    copper = int(copper or 0)
    g, s, c = copper // 10000, (copper // 100) % 100, copper % 100
    parts = [f"{g}g" if g else "", f"{s}s" if s else "", f"{c}c" if c and not g else ""]
    return " ".join(p for p in parts if p) or "0c"


# ---------------------------------------------------------------------------
# Full item list from the game's own data (ItemSparse table, via wago.tools)
# ---------------------------------------------------------------------------

EXTRA_NAMES: dict[int, str] = {}      # filled by ItemDB.load(); used when the guild hasn't seen an item
_JUNK = ("deprecated", "[ph]", "test ", " test", "qa ", "monster -", "(old)", "old ", "unused", "zzold", "[dnt]", "dnd ")


def parse_itemsparse_csv(text: str) -> dict[int, str]:
    """ID -> English name from an ItemSparse CSV export."""
    reader = csv.reader(io.StringIO(text))
    header = next(reader)
    cols = {h.strip(): i for i, h in enumerate(header)}
    id_col = cols.get("ID")
    name_col = next((cols[c] for c in ("Display_lang", "Display_lang_enUS", "Display") if c in cols), None)
    if id_col is None or name_col is None:
        raise ValueError(f"unexpected ItemSparse columns: {header[:12]}")
    out = {}
    for row in reader:
        try:
            i, name = int(row[id_col]), row[name_col].strip()
        except (ValueError, IndexError):
            continue
        if name and not any(j in name.lower() for j in _JUNK):
            out[i] = name
    return out


def _vtuple(v: str):
    return tuple(int(x) for x in re.findall(r"\d+", v or ""))


def newest_version(builds: dict | list, prefix: str = "1.60.") -> str | None:
    """Newest build version starting with prefix (1.60. = WoW Forever) in wago.tools' build list."""
    found = []
    groups = builds.values() if isinstance(builds, dict) else [builds]
    for group in groups:
        for b in group if isinstance(group, list) else []:
            v = b.get("version") if isinstance(b, dict) else None
            if isinstance(v, str) and v.startswith(prefix):
                found.append(v)
    return max(found, key=_vtuple) if found else None


class ItemDB:
    """Every item in the game, cached as items.json next to the bot."""
    BUILDS_URL = "https://wago.tools/api/builds"
    CSV_URL = "https://wago.tools/db2/ItemSparse/csv?build={version}"
    UA = "EPU-Guild-Tools Discord companion (guild bank bot)"

    def __init__(self, folder: str):
        self.folder = folder
        self.cache = os.path.join(folder, "items.json")
        self.manual = os.path.join(folder, "items.csv")
        self.items: dict[int, str] = {}
        self.version = None
        self._lower: list[tuple[str, int, str]] = []

    def _set(self, items: dict[int, str], version):
        self.items, self.version = items, version
        self._lower = sorted((n.lower(), i, n) for i, n in items.items())
        EXTRA_NAMES.clear()
        EXTRA_NAMES.update(items)

    def _get(self, url: str, timeout=60) -> bytes:
        req = urllib.request.Request(url, headers={"User-Agent": self.UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()

    def load(self, prefix: str = "1.60.", url_override: str = "", max_age_days: float = 7) -> str:
        """Load items; returns a one-line description of where they came from."""
        if os.path.exists(self.manual):                       # a CSV you downloaded yourself wins
            with open(self.manual, encoding="utf-8-sig", errors="replace") as f:
                self._set(parse_itemsparse_csv(f.read()), "items.csv")
            return f"{len(self.items)} items from items.csv"
        cached = None
        if os.path.exists(self.cache):
            with open(self.cache, encoding="utf-8") as f:
                cached = json.load(f)
            self._set({int(k): v for k, v in cached["items"].items()}, cached.get("version"))
            if time.time() - cached.get("fetched", 0) < max_age_days * 86400:
                return f"{len(self.items)} items (cached, build {self.version})"
        try:
            if url_override:
                version, url = "custom", url_override
            else:
                version = newest_version(json.loads(self._get(self.BUILDS_URL)), prefix)
                if not version:
                    raise ValueError(f"no build starting with {prefix} in wago.tools' build list")
                if cached and cached.get("version") == version:
                    cached["fetched"] = time.time()
                    self._save(cached)
                    return f"{len(self.items)} items (build {version}, still current)"
                url = self.CSV_URL.format(version=version)
            items = parse_itemsparse_csv(self._get(url, timeout=180).decode("utf-8-sig", errors="replace"))
            if len(items) < 1000:
                raise ValueError(f"only {len(items)} items came back; keeping what I had")
            self._set(items, version)
            self._save({"version": version, "fetched": time.time(), "items": {str(k): v for k, v in items.items()}})
            return f"{len(items)} items downloaded (build {version})"
        except Exception as e:
            if self.items:
                return f"{len(self.items)} items (cached; refresh failed: {e})"
            raise

    def _save(self, data: dict):
        tmp = self.cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        safe_replace(tmp, self.cache)

    def search(self, text: str, limit: int = 25) -> list[tuple[int, str]]:
        q = " ".join((text or "").lower().split())
        if len(q) < 2:
            return []
        starts, contains = [], []
        for low, i, name in self._lower:
            if low.startswith(q):
                starts.append((i, name))
            elif q in low:
                contains.append((i, name))
            if len(starts) >= limit:
                break
        return (starts + contains)[:limit]

    def find(self, name: str) -> int | None:
        want = name.strip().strip("[]").lower()
        for low, i, _ in self._lower:
            if low == want:
                return i
        return None


# ---------------------------------------------------------------------------
# GitHub releases (announcements and /download)
# ---------------------------------------------------------------------------
def release_info(rel: dict) -> dict:
    """The parts of a GitHub 'latest release' response the bot uses."""
    assets = {a.get("name", ""): a.get("browser_download_url") for a in rel.get("assets") or []}
    def find(prefix):
        for name, url in assets.items():
            if name.lower().startswith(prefix.lower()) and name.lower().endswith(".zip"):
                return url
        return None
    tag = rel.get("tag_name") or ""
    return {
        "tag": tag,
        "version": tag[1:] if tag.lower().startswith("v") else tag,
        "page": rel.get("html_url"),
        "addon": find("EPUGuild-"),
        "updater": find("EPU-Updater"),
        "notes": (rel.get("body") or "").strip(),
        "draft": bool(rel.get("draft")),
        "prerelease": bool(rel.get("prerelease")),
    }


def fetch_latest_release(repo: str, timeout: int = 30) -> dict:
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest",
                                 headers={"User-Agent": "EPU-Guild-Tools-bot", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return release_info(json.loads(r.read()))

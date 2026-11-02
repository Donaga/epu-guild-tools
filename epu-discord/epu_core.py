"""EPU Discord companion: the parts that don't need Discord.

* Reads the EPUGuild SavedVariables file that WoW writes on /reload and logout.
* Writes Inbox.lua, which the addon loads at the next login or /reload.
* Works out what changed since the last read (new requests, status changes,
  donations) so the bot can post or edit Discord messages.
"""
from __future__ import annotations

import glob
import json
import os
import re
import time
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


def write_inbox(path: str, entries: list) -> None:
    text = INBOX_HEADER + "EPUGuildInbox = " + lua_value(entries) + "\n"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


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
    def requests(self) -> dict:
        return self.g.get("requests") or {}

    @property
    def donations(self) -> dict:
        return self.g.get("donations") or {}

    @property
    def bank(self) -> dict:
        return self.g.get("bank") or {}

    def item_name(self, item_id) -> str:
        try:
            return self.item_names.get(int(item_id)) or f"item {item_id}"
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
            if isinstance(r, dict) and r.get("status") == "approved" and r.get("item"):
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
        counts = {"pending": 0, "approved": 0}
        for r in self.requests.values():
            if isinstance(r, dict):
                st = status_of(r)
                if st in counts:
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
        os.replace(tmp, self.path)

    # Discord user -> WoW character
    def link(self, discord_id: int, character: str):
        self.data["links"][str(discord_id)] = character
        self.save()

    def character_for(self, discord_id: int) -> str | None:
        return self.data["links"].get(str(discord_id))

    # Inbox
    def queue_request(self, who: str, item_id: int | None, item_name: str, qty: int, note: str, discord_name: str) -> dict:
        e = {"id": uuid.uuid4().hex[:10], "kind": "request", "who": who, "item": item_id, "itemName": item_name,
             "qty": qty, "note": note[:80], "discord": discord_name, "t": int(time.time())}
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
    out = {"new_requests": [], "changed_requests": [], "new_donations": []}
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
    if not primed:
        state.data["primed"] = True
    out["new_donations"].sort(key=lambda d: d.get("t", 0))
    return out


ITEM_ID_RE = re.compile(r"item[=:](\d+)")


def resolve_item(text: str, known: dict[int, str]) -> tuple[int | None, str | None]:
    """Item ID and name from autocomplete value, an ID, a Wowhead link, or a known name."""
    text = (text or "").strip()
    if text.startswith("id:") and text[3:].isdigit():
        i = int(text[3:])
        return i, known.get(i)
    if text.isdigit():
        i = int(text)
        return i, known.get(i)
    m = ITEM_ID_RE.search(text)
    if m:
        i = int(m.group(1))
        return i, known.get(i)
    want = text.strip("[]").lower()
    for i, name in known.items():
        if name.lower() == want:
            return i, name
    return None, None


def money_text(copper) -> str:
    copper = int(copper or 0)
    g, s, c = copper // 10000, (copper // 100) % 100, copper % 100
    parts = [f"{g}g" if g else "", f"{s}s" if s else "", f"{c}c" if c and not g else ""]
    return " ".join(p for p in parts if p) or "0c"

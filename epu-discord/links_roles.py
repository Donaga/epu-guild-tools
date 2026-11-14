"""Discord linking by code, alt families, class/rank roles and the officer log.

Pure logic with no Discord calls, so it can be tested without a bot. bot.py
does the Discord side (giving and taking roles, posting the log).
"""
from __future__ import annotations

import secrets
import time

CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


# ---------------------------------------------------------------------------
# Codes and claims
# ---------------------------------------------------------------------------
def new_code() -> str:
    return "".join(secrets.choice(CODE_CHARS) for _ in range(8))


def show_code(code: str) -> str:
    return code[:4] + "-" + code[4:]


def normalize_code(text) -> str | None:
    s = "".join(str(text or "").upper().split()).replace("-", "")
    return s if len(s) == 8 and all(c in CODE_CHARS for c in s) else None


def claim_hash(code: str, who: str) -> str:
    """Same as the addon's ns.LinkClaimHash."""
    a = b = 0
    for c in (code + "\0" + who).encode("utf-8"):
        a = (a * 131 + c) % 4294967296
        b = (b * 257 + c) % 4294967296
    return f"{a}-{b}"


def code_for(state, discord_id) -> str:
    codes = state.data.setdefault("link_codes", {})
    uid = str(discord_id)
    for code, owner in codes.items():
        if owner.get("user") == uid:
            return code
    code = new_code()
    while code in codes:
        code = new_code()
    codes[code] = {"user": uid, "t": int(time.time())}
    state.save()
    return code


def owner_of(state, character: str) -> str | None:
    for uid, chars in state.data["links"].items():
        chars = [chars] if isinstance(chars, str) else chars
        if any(c.lower() == character.lower() for c in chars or []):
            return str(uid)
    return None


def _link(state, uid: str, character: str, how: str, out: list):
    owner = owner_of(state, character)
    if owner == uid:
        return
    if owner is not None:
        out.append({"kind": "conflict", "user": uid, "owner": owner, "who": character, "how": how})
        return
    state.link(int(uid), character)
    state.data.setdefault("link_audit", []).append({"user": uid, "character": character, "by": how, "t": int(time.time())})
    state.data["link_audit"] = state.data["link_audit"][-200:]
    out.append({"kind": "linked", "user": uid, "who": character, "how": how})


def process_links(gd, state) -> list[dict]:
    """Link characters whose in-game claim matches a code we handed out, then
    their confirmed EPU alts. Returns what happened, for the officer log."""
    out: list[dict] = []
    members = set(gd.members)
    codes = state.data.get("link_codes") or {}
    seen = state.data.setdefault("claims_seen", {})
    claims = gd.g.get("discordClaims") or {}
    for who, r in claims.items():
        if not isinstance(r, dict) or r.get("off") or not isinstance(r.get("h"), str):
            continue
        stamp = f"{r.get('t')}:{r['h']}"
        if seen.get(who) == stamp or who not in members:
            continue
        for code, owner in codes.items():
            if claim_hash(code, who) == r["h"]:
                _link(state, str(owner.get("user")), who, "code", out)
                break
        seen[who] = stamp
    # Confirmed EPU alt groups: both characters agreed in game, so a linked
    # main brings its alts along (and the other way round).
    for uid, chars in list(state.data["links"].items()):
        chars = [chars] if isinstance(chars, str) else list(chars or [])
        for c in chars:
            group = gd.group_of(c)
            for alt in (group or {}).get("chars", []):
                if alt in members and alt not in chars:
                    _link(state, str(uid), alt, "alt", out)
    if out:
        state.save()
    return out


# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
def member_info(gd) -> dict:
    info = gd.g.get("memberInfo") or {}
    return {k: v for k, v in info.items() if isinstance(k, str) and isinstance(v, dict)}


def desired_roles(gd, state, rank_roles: list[str], class_roles: bool = True, member_role: str | None = None) -> dict[str, set[str]]:
    """{discord user id: {"member:Member", "class:MAGE", "rank:Initiate", ...}} for every linked user.
    member_role goes to everyone linked who is still in the guild, whatever
    their rank. Rank roles come from the user's main, and only for ranks listed
    in rank_roles (a rank named like member_role adds nothing extra)."""
    info = member_info(gd)
    allowed = {r.lower(): r for r in rank_roles}
    out: dict[str, set[str]] = {}
    for uid, chars in state.data["links"].items():
        chars = [chars] if isinstance(chars, str) else list(chars or [])
        want: set[str] = set()
        here = [c for c in chars if c in info]
        if class_roles:
            for c in here:
                if info[c].get("c"):
                    want.add("class:" + str(info[c]["c"]))
        if here and member_role:
            want.add("member:" + member_role)
        if here:
            main = main_for(gd, state, uid)
            rank = (info.get(main) or info[here[0]]).get("r")  # main may have left; fall back
            if isinstance(rank, str) and rank.lower() in allowed and rank.lower() != str(member_role or "").lower():
                want.add("rank:" + allowed[rank.lower()])
        out[str(uid)] = want
    return out


def migrate_member_role(state, member_role: str | None) -> str | None:
    """Move the pre-0.23.1 rank key without changing the Discord role ID.

    Conflicting IDs require an explicit configuration decision; do not remove
    either role or choose one based on dictionary iteration order.
    """
    if not member_role:
        return None
    managed = state.data.setdefault("managed_roles", {})
    new_key = "member:" + member_role
    old_keys = {key for key in managed
                if key.startswith("rank:") and key.split(":", 1)[1].lower() == member_role.lower()}
    if not old_keys:
        return None
    ids = {str(managed[key]) for key in old_keys | ({new_key} if new_key in managed else set())}
    if len(ids) != 1:
        return "The old rank role and the member role refer to different Discord roles. Resolve their managed role IDs before syncing."
    managed[new_key] = ids.pop()
    for key in old_keys:
        managed.pop(key)
    for uid, keys in state.data.setdefault("role_holders", {}).items():
        state.data["role_holders"][uid] = sorted({new_key if key in old_keys else key for key in keys})
    for field in ("adopted_roles", "role_name_warned"):
        if field in state.data:
            state.data[field] = sorted({new_key if key in old_keys else key for key in state.data[field]})
    state.data.pop("roles_sig", None)
    return None


def main_for(gd, state, uid) -> str | None:
    """A main picked with /main in Discord wins; otherwise the main set in game
    (/epu main), else the first linked character."""
    chars = state.characters_for(int(uid))
    picked = (state.data.get("mains") or {}).get(str(uid))
    if picked in chars:
        return picked
    info = member_info(gd)
    here = [c for c in chars if c in info] or chars
    if not here:
        return None
    main = gd.main_of(here[0])
    return main if main in chars else here[0]


def role_name(key: str, gd=None) -> str:
    kind, value = key.split(":", 1)
    if kind == "class":
        names = {"DEATHKNIGHT": "Death Knight", "DEMONHUNTER": "Demon Hunter"}
        if gd is not None:
            for v in member_info(gd).values():
                if v.get("c") == value and isinstance(v.get("cn"), str):
                    return v["cn"]
        return names.get(value, value.title())
    return value


def plan_changes(desired: dict[str, set[str]], current: dict[str, set[str]]) -> tuple[dict, dict]:
    """current: managed role keys each user has now. Returns (adds, removes)."""
    adds, removes = {}, {}
    for uid in set(desired) | set(current):
        want, have = desired.get(uid, set()), current.get(uid, set())
        if want - have:
            adds[uid] = want - have
        if have - want:
            removes[uid] = have - want
    return adds, removes


def needs_confirmation(removes: dict, linked_users: int, limit: int = 5, share: float = 0.2) -> bool:
    """Hold back a sweep that would strip roles from many people at once (a
    partial roster read, a rank rename) until an officer confirms."""
    n = len(removes)
    return n > max(limit, int(linked_users * share))


# ---------------------------------------------------------------------------
# Officer log: roster changes between two saves
# ---------------------------------------------------------------------------
def roster_trusted(prev: dict | None, cur: dict) -> bool:
    """Reject snapshots losing over a third of the last accepted roster."""
    return not prev or len(cur) >= len(prev) * 2 / 3


def roster_events(prev: dict | None, cur: dict, milestones=(60,), left: dict | None = None) -> tuple[list[dict], bool]:
    """Compare memberInfo snapshots. Returns (events, trusted). A snapshot that
    loses over a third of the roster at once is treated as a bad read: no
    events, and the caller keeps the old baseline."""
    if not prev:
        return [], True
    if not roster_trusted(prev, cur):
        return [], False
    left = left if left is not None else {}
    out = []
    for name, v in cur.items():
        p = prev.get(name)
        if p is None:
            out.append({"kind": "returned" if name in left else "joined", "who": name, "rank": v.get("r")})
            left.pop(name, None)
            continue
        if p.get("r") != v.get("r"):
            up = (v.get("ri") or 0) < (p.get("ri") or 0)
            out.append({"kind": "promoted" if up else "demoted", "who": name, "from": p.get("r"), "to": v.get("r")})
        for m in milestones:
            if (p.get("l") or 0) < m <= (v.get("l") or 0):
                out.append({"kind": "level", "who": name, "level": m})
    for name, p in prev.items():
        if name not in cur:
            out.append({"kind": "left", "who": name, "rank": p.get("r")})
            left[name] = int(time.time())
    return out, True


def event_line(e: dict, mention=lambda uid: f"<@{uid}>") -> str:
    k = e["kind"]
    if k == "joined":
        return f"\U0001F44B **{e['who']}** joined the guild" + (f" as {e['rank']}" if e.get("rank") else "")
    if k == "returned":
        return f"\U0001F501 **{e['who']}** is back in the guild" + (f" as {e['rank']}" if e.get("rank") else "")
    if k == "left":
        return f"\U0001F6AA **{e['who']}** left the guild" + (f" (was {e['rank']})" if e.get("rank") else "")
    if k in ("promoted", "demoted"):
        return f"{'⬆️' if k == 'promoted' else '⬇️'} **{e['who']}** {k}: {e['from']} → {e['to']}"
    if k == "level":
        return f"\U0001F389 **{e['who']}** reached level {e['level']}"
    if k == "linked":
        via = {"code": "with their code", "alt": "as a confirmed alt", "officer": "by an officer", "nickname": "by nickname match"}
        return f"\U0001F517 Linked **{e['who']}** to {mention(e['user'])} {via.get(e['how'], '')}".rstrip()
    if k == "conflict":
        return (f"⚠️ **{e['who']}** is already linked to {mention(e['owner'])}, but {mention(e['user'])} "
                f"also claimed it ({e['how']}). Use `/revoke_link` if the first link is wrong.")
    if k == "roles_held":
        return (f"⏸️ Role sync would take roles from **{e['n']}** people at once, so nothing was removed. "
                "If that's expected, run `/roles confirm`.")
    return str(e)


# ---------------------------------------------------------------------------
# Nickname suggestions
# ---------------------------------------------------------------------------
def nickname_matches(gd, state, people: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """people: (discord id, display name). Suggest (id, character) where the
    display name names exactly one unlinked guild member."""
    linked_users = {str(u) for u, c in state.data["links"].items() if c}
    out = []
    for uid, display in people:
        if str(uid) in linked_users:
            continue
        name, _ = gd.resolve_member(display or "")
        if not name:
            words = (display or "").replace("|", " ").replace("/", " ").replace("(", " ").replace(")", " ").split()
            hits = {gd.resolve_member(w)[0] for w in words} - {None}
            for i in range(len(words) - 1):
                hits |= {gd.resolve_member(words[i] + " " + words[i + 1])[0]} - {None}
            name = hits.pop() if len(hits) == 1 else None
        if name and owner_of(state, name) is None:
            out.append((str(uid), name))
    return out

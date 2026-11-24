"""The dungeon board on Discord: quick groups, help posts and run requests.

Each open board entry from the addon's Groups page (/epu groups) gets one card
in the board channel. The card is edited as people sign up, and greyed out
once the group closes, expires or is scheduled as a guild event. Guild events
have their own cards (event_sync.py), so they aren't repeated here.

The bot sees a board entry when the game data on this PC is saved (logout or
/reload), or when a sync helper uploads a snapshot that holds it.
"""
from __future__ import annotations

import hashlib
import json
import time

import discord

ROLES = {"t": "Tank", "h": "Healer", "d": "DPS"}
PURPOSES = {"q": "Quests", "l": "Loot farming", "e": "Quests or loot"}
FOOTER = "Join in game: /epu groups, or Groups in the EPU window"
ENDED = {"closed": "Closed", "expired": "Expired", "scheduled": "Scheduled as a guild event", "gone": "No longer on the board"}


def _list(value) -> list:
    if isinstance(value, dict):
        return [value[k] for k in sorted(value, key=lambda k: (not isinstance(k, (int, float)), k))]
    return list(value) if isinstance(value, (list, tuple)) else []


def _int(value, default=0) -> int:
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def _text(value, limit) -> str:
    return " ".join(value.split())[:limit] if isinstance(value, str) else ""


def entries(gd, now: float | None = None) -> list[dict]:
    """Board entries, open or ended, from current guild members. Each has a
    key, a kind ('group', 'help' or 'run'), a status and what the card shows."""
    now = time.time() if now is None else now
    members = set(gd.members)
    g = gd.g
    out = []
    replies: dict[str, list[dict]] = {}
    for r in (g.get("activityReplies") or {}).values():
        if isinstance(r, dict) and r.get("who") in members and r.get("state") in ("ready", "tentative") and isinstance(r.get("post"), str):
            replies.setdefault(r["post"], []).append(r)
    for pid, r in (g.get("activityPosts") or {}).items():
        if not isinstance(pid, str) or not isinstance(r, dict) or r.get("who") not in members:
            continue
        if r.get("kind") not in ("dungeon", "help") or not _text(r.get("title"), 80):
            continue
        expires = _int(r.get("expires"))
        status = "closed" if r.get("status") == "closed" else ("open" if r.get("status") == "open" and expires > now else "expired")
        ready = [x for x in replies.get(pid, []) if x["state"] == "ready"]
        out.append({
            "key": "activity:" + pid, "kind": "group" if r["kind"] == "dungeon" else "help", "status": status,
            "who": r["who"], "title": _text(r.get("title"), 80), "note": _text(r.get("note"), 320), "zone": _text(r.get("zone"), 80),
            "min": _int(r.get("minLevel"), 1), "max": _int(r.get("maxLevel"), 60), "slots": _int(r.get("slots"), 5),
            "expires": expires, "ready": len(ready), "maybe": len(replies.get(pid, [])) - len(ready),
            "roles": {k: sum(1 for x in ready if x.get("role") == k) for k in ROLES},
        })
    interest: dict[str, set] = {}
    for x in (g.get("runInterest") or {}).values():
        if isinstance(x, dict) and x.get("state") == "in" and x.get("who") in members and isinstance(x.get("request"), str):
            interest.setdefault(x["request"], set()).add(x["who"])
    for rid, r in (g.get("runRequests") or {}).items():
        if not isinstance(rid, str) or not isinstance(r, dict) or r.get("who") not in members or not _text(r.get("dungeon"), 80):
            continue
        windows = sorted(((_int(w.get("s")), _int(w.get("e"))) for w in _list(r.get("windows")) if isinstance(w, dict)), key=lambda w: w[0])
        windows = [w for w in windows if w[1] > w[0] > 0][:3]
        last = max((e for _, e in windows), default=0)
        if r.get("status") == "closed":
            status = "closed"
        elif r.get("status") == "scheduled":
            status = "scheduled"
        else:
            status = "open" if r.get("status") == "open" and last > now else "expired"
        out.append({
            "key": "run:" + rid, "kind": "run", "status": status, "who": r["who"], "title": _text(r.get("dungeon"), 80),
            "note": _text(r.get("note"), 200), "purpose": PURPOSES.get(r.get("purpose"), "Quests or loot"),
            "role": ROLES.get(r.get("role"), "DPS"), "windows": [w for w in windows if w[1] > now] or windows[-1:],
            "interested": len(interest.get(rid, set()) - {r["who"]}) + 1,
        })
    out.sort(key=lambda e: e["key"])
    return out


def card(gd, e: dict) -> discord.Embed:
    is_open = e["status"] == "open"
    label = gd.label(e["who"]) if hasattr(gd, "label") else e["who"]
    if e["kind"] == "run":
        title = "Run request: " + e["title"]
        description = e["purpose"] + (" · " + e["note"] if e["note"] else "")
        color = discord.Color.blue()
    else:
        title = ("Quick group: " if e["kind"] == "group" else "Help wanted: ") + e["title"]
        description = e["note"]
        color = discord.Color.green() if e["kind"] == "group" else discord.Color.orange()
    if not is_open:
        title += " (" + ENDED.get(e["status"], "Ended").lower() + ")"
        color = discord.Color.dark_grey()
    embed = discord.Embed(title=title[:256], description=description[:500] or None, color=color)
    if e["kind"] == "run":
        times = "\n".join(f"<t:{s}:f> to <t:{end}:t>" for s, end in e["windows"]) or "No times left"
        embed.add_field(name="Times that suit " + e["who"], value=times, inline=False)
        embed.add_field(name="Interested", value=f"{e['interested']} so far · {label} plays {e['role']}", inline=False)
    else:
        when = f"Now, ends <t:{e['expires']}:R>" if is_open else ENDED.get(e["status"], "Ended")
        embed.add_field(name="When", value=when, inline=True)
        embed.add_field(name="Levels", value=f"{e['min']}–{e['max']}", inline=True)
        if e["zone"]:
            embed.add_field(name="Where", value=e["zone"], inline=True)
        roles = " · ".join(f"{e['roles'][k]} {name}" for k, name in ROLES.items())
        group = f"{e['ready']}/{e['slots']} ready · {roles}" + (f" · {e['maybe']} maybe" if e["maybe"] else "")
        embed.add_field(name="Group", value=group, inline=False)
        embed.add_field(name="Organiser", value=label, inline=False)
    if not is_open and e["kind"] == "run":
        embed.add_field(name="Status", value=ENDED.get(e["status"], "Ended"), inline=False)
    embed.set_footer(text=FOOTER if is_open else "EPU dungeon board")
    return embed


def gone_card(title: str) -> discord.Embed:
    return discord.Embed(title=(title + " (" + ENDED["gone"].lower() + ")")[:256], color=discord.Color.dark_grey()).set_footer(text="EPU dungeon board")


def signature(embed: discord.Embed) -> str:
    return hashlib.sha256(json.dumps(embed.to_dict(), sort_keys=True).encode()).hexdigest()


class GroupBoard:
    """Posts and updates the board cards. One state entry per card; an entry
    is dropped once its card shows that the group ended."""

    def __init__(self, cfg, state, client):
        self.cfg, self.state, self.client = cfg, state, client

    async def refresh(self, gd, now: float | None = None) -> None:
        if not self.cfg.get("group_board_post") or gd is None:
            return
        channel_id = self.cfg.get("group_board_channel_id")
        if not channel_id:
            return
        posts = self.state.data.setdefault("group_board", {})
        now = time.time() if now is None else now
        board = {e["key"]: e for e in entries(gd, now)}
        wanted = [k for k, e in board.items() if k in posts or e["status"] == "open"]
        # A card whose record is missing from this read (say a helper's
        # snapshot didn't arrive) waits until its group would have ended.
        gone = [k for k, old in posts.items() if k not in board and _int(old.get("ends")) <= now]
        if not wanted and not gone:
            return
        channel = self.client.get_channel(int(channel_id)) or await self.client.fetch_channel(int(channel_id))
        if str(getattr(getattr(channel, "guild", None), "id", "")) != str(self.cfg["server_id"]):
            raise ValueError("The group board channel belongs to another server")
        none = discord.AllowedMentions.none()
        for key in gone:
            old = posts.pop(key)
            try:
                if str(old.get("channel")) == str(channel_id):
                    message = await channel.fetch_message(int(old["message"]))
                    await message.edit(embed=gone_card(old.get("title") or "Group"), allowed_mentions=none)
            except discord.NotFound:
                pass
            self.state.save()
        for key in wanted:
            e = board[key]
            embed = card(gd, e)
            sig = signature(embed)
            old = posts.get(key)
            if old and old.get("signature") == sig and str(old.get("channel")) == str(channel_id):
                continue
            message = None
            if old and str(old.get("channel")) == str(channel_id):
                try:
                    message = await channel.fetch_message(int(old["message"]))
                except discord.NotFound:
                    message = None
                if message:
                    await message.edit(embed=embed, allowed_mentions=none)
            if message is None and e["status"] == "open":
                message = await channel.send(embed=embed, allowed_mentions=none)
            if message is None or e["status"] != "open":
                posts.pop(key, None)       # ended: the card says so, and nothing more will change
            else:
                ends = e["expires"] if e["kind"] != "run" else max((end for _, end in e["windows"]), default=0)
                posts[key] = {"message": message.id, "channel": str(channel_id), "signature": sig, "title": embed.title, "ends": ends}
            self.state.save()

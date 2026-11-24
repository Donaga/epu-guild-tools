"""EPU Discord companion bot.

Links the EPU Guild Tools addon and a Discord channel:
  * requests made in game are posted to the channel and kept up to date;
  * members can /request from Discord, and officers can Approve / Reject
    from the posted message. Those reach the game through Inbox.lua at the
    next /reload or login of an officer on this PC.
  * optional thank-you posts for donations; /needs and /bank lookups.

Run on the officer PC that plays WoW: python bot.py
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone
import os
import sys
import time
import uuid

import discord
from discord import app_commands
from discord.ext import tasks

import epu_core as core
import shared_bridge as bridge
import links_roles as lr
import self_update
from event_sync import EventSync, KINDS as EVENT_KINDS, time_zone_choices
from group_board import GroupBoard

HERE = os.path.dirname(os.path.abspath(__file__))
log = logging.getLogger("epu")

STATUS_COLOR = {
    "pending": discord.Color.gold(),
    "approved": discord.Color.green(),
    "filled": discord.Color.dark_grey(),
    "rejected": discord.Color.red(),
    "cancelled": discord.Color.dark_grey(),
}


CLASS_ROLE_COLORS = {
    "DEATHKNIGHT": 0xC41E3A, "DEMONHUNTER": 0xA330C9, "DRUID": 0xFF7C0A,
    "EVOKER": 0x33937F, "HUNTER": 0xAAD372, "MAGE": 0x3FC7EB, "MONK": 0x00FF98,
    "PALADIN": 0xF48CBA, "PRIEST": 0xFFFFFF, "ROGUE": 0xFFF468,
    "SHAMAN": 0x0070DD, "WARLOCK": 0x8788EE, "WARRIOR": 0xC69B6D,
}


def config_error(message: str):
    """Stop for something only an edit to config.json fixes, so start.bat doesn't keep retrying."""
    print(message, file=sys.stderr)
    sys.exit(self_update.CONFIG_ERROR_CODE)


def load_config() -> dict:
    path = os.path.join(HERE, "config.json")
    if not os.path.exists(path):
        config_error("config.json is missing. Copy config.example.json to config.json and fill it in.")
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    if not cfg.get("token") or "PASTE" in cfg.get("token", ""):
        config_error("Put your bot token in config.json first (see README.md).")
    cfg.setdefault("wow_path", r"C:\Program Files (x86)\World of Warcraft\_forever_")
    cfg.setdefault("officer_role", "Officer")
    cfg.setdefault("post_donations", True)
    cfg.setdefault("guild_key", "E Pluribus Unum")
    cfg.setdefault("poll_seconds", 15)
    cfg.setdefault("status_post", True)
    cfg.setdefault("help_post", True)
    cfg.setdefault("wowhead", "https://www.wowhead.com/forever")
    cfg.setdefault("github_repo", "Donaga/epu-guild-tools")
    cfg.setdefault("announce_releases", True)
    cfg.setdefault("announce_after_curseforge", True)  # wait until CurseForge approves the release's file
    cfg.setdefault("curseforge_wait_hours", 12)   # ...but announce anyway after this long if the bot can't see the approval
    cfg.setdefault("release_channel_id", "")      # where release announcements go (e.g. #updates); blank: the request channel
    cfg.setdefault("auto_update", True)           # move this clone to each new release and restart (start.bat only)
    cfg.setdefault("curseforge_project_id", "")   # optional: numeric project ID (else the slug in curseforge_url)
    cfg.setdefault("curseforge_api_key", "")      # optional: CurseForge API key; with the project ID, asks CurseForge itself
    cfg.setdefault("item_db", True)               # download the full Forever item list from wago.tools
    cfg.setdefault("item_build_prefix", "1.60.")  # WoW Forever client versions
    cfg.setdefault("item_csv_url", "")            # optional: a direct ItemSparse CSV URL
    cfg.setdefault("addon_url", "https://github.com/Donaga/epu-guild-tools/releases/latest")
    cfg.setdefault("curseforge_url", "https://www.curseforge.com/wow/addons/epu-guild-tools")   # the recommended way to install
    cfg.setdefault("post_milestones", True)       # level-ups, first mounts, new members... in Discord
    cfg.setdefault("import_channel_id", "")       # an existing #announcements channel to copy into the game
    cfg.setdefault("invite_requests_channel_id", "")
    cfg.setdefault('events_channel_id','')
    cfg.setdefault('sync_helpers',{})
    cfg.setdefault("ingame_chat_channel", "in-game-chat")  # the channel linked to guild chat in game; "" turns it off
    cfg.setdefault("ingame_chat_channel_id", "")  # or its ID, if the name differs
    cfg.setdefault("import_days", 30)             # on startup, copy posts from this many days back
    cfg.setdefault("import_officers_only", False) # only copy posts by the officer role (announcement channels are usually locked anyway)
    cfg.setdefault("post_motd", True)             # mirror the in-game guild message of the day to Discord
    cfg.setdefault("discord_roles", True)         # give linked members class and rank roles (needs Manage Roles)
    cfg.setdefault("class_roles", True)
    cfg.setdefault("member_role", "Member")       # every linked guild member gets this, whatever their rank ("" turns it off)
    cfg.setdefault("rank_roles", ["Veteran", "Initiate"])   # extra roles for these ranks only; officer ranks stay manual
    cfg.setdefault("adopt_existing_roles", "rank")  # use your own same-named roles: "rank", "all" (class too) or "none"
    cfg.setdefault("officer_log_channel_id", "")  # joins, leaves, rank changes, links (an officers-only channel)
    cfg.setdefault("level_milestones", [60])
    cfg.setdefault("members_intent", False)       # needed only for /link_suggestions (turn it on in the Developer Portal)
    cfg.setdefault("guild_needs_post", False)     # a short daily list of the mats guildmates need (from EPU's needed mats)
    cfg.setdefault("guild_needs_channel_id", "")  # blank: the milestones channel (feed_channel_id)
    cfg.setdefault("guild_needs_time", "18:00")   # 24-hour time on this PC's clock
    cfg.setdefault("guild_needs_max_items", 15)
    cfg.setdefault("group_board_post", True)      # quick groups, help posts and run requests from the Groups page
    cfg.setdefault("group_board_channel_id", "")  # blank: the events channel, else the milestones channel
    cfg.setdefault("leveling_board_post", True)    # weekly: levels each guildmate gained last week (EPU's leveling board)
    cfg.setdefault("leveling_board_channel_id", "")  # blank: the guild needs channel (guild_needs_channel_id)
    cfg.setdefault("leveling_board_day", "monday")   # posts this day about the seven days before it (Monday: Mon-Sun)
    cfg.setdefault("leveling_board_time", "19:00")   # 24-hour time on this PC's clock
    cfg.setdefault("leveling_board_max", 15)
    cfg.setdefault("logo_url", f"https://raw.githubusercontent.com/{cfg['github_repo']}/main/media/epu-logo.png")
    cfg["status_channel_id"] = cfg.get("status_channel_id") or cfg["channel_id"]
    cfg["feed_channel_id"] = cfg.get("feed_channel_id") or cfg["channel_id"]
    cfg["announce_channel_id"] = cfg.get("announce_channel_id") or cfg["channel_id"]
    cfg["release_channel_id"] = cfg.get("release_channel_id") or cfg["channel_id"]
    cfg["guild_needs_channel_id"] = cfg.get("guild_needs_channel_id") or cfg["feed_channel_id"]
    cfg["group_board_channel_id"] = cfg.get("group_board_channel_id") or cfg.get("events_channel_id") or cfg["feed_channel_id"]
    if parse_clock(cfg["guild_needs_time"]) is None:
        print(f"guild_needs_time {cfg['guild_needs_time']!r} isn't a 24-hour time like \"18:00\"; using 18:00.")
        cfg["guild_needs_time"] = "18:00"
    try:
        cfg["guild_needs_max_items"] = max(1, min(40, int(cfg["guild_needs_max_items"])))
    except (TypeError, ValueError):
        cfg["guild_needs_max_items"] = 15
    cfg["leveling_board_channel_id"] = cfg.get("leveling_board_channel_id") or cfg["guild_needs_channel_id"]
    if parse_clock(cfg["leveling_board_time"]) is None:
        print(f"leveling_board_time {cfg['leveling_board_time']!r} isn't a 24-hour time like \"19:00\"; using 19:00.")
        cfg["leveling_board_time"] = "19:00"
    if core.parse_weekday(cfg["leveling_board_day"]) is None:
        print(f"leveling_board_day {cfg['leveling_board_day']!r} isn't a day of the week; using Monday.")
        cfg["leveling_board_day"] = "monday"
    try:
        cfg["leveling_board_max"] = max(1, min(40, int(cfg["leveling_board_max"])))
    except (TypeError, ValueError):
        cfg["leveling_board_max"] = 15
    return cfg


def parse_clock(text) -> tuple[int, int] | None:
    """ "18:00" or "6:30" -> (18, 0) / (6, 30); anything else -> None."""
    try:
        hh, mm = str(text).strip().split(":")
        h, m = int(hh), int(mm)
    except (TypeError, ValueError):
        return None
    return (h, m) if 0 <= h <= 23 and 0 <= m <= 59 and len(mm.strip()) == 2 else None


cfg = load_config()
state = core.State(os.path.join(HERE, "state.json"))
intents = discord.Intents.default()
if cfg["import_channel_id"] or cfg["invite_requests_channel_id"] or cfg["ingame_chat_channel"] or cfg["ingame_chat_channel_id"]:
    intents.message_content = True   # needed to read the announcements channel (turn it on in the Developer Portal)
if cfg["members_intent"]:
    intents.members = True           # lets /link_suggestions read the server's member list
client = discord.Client(intents=intents)
tree = app_commands.CommandTree(client)
GUILD = discord.Object(id=int(cfg["server_id"]))

items_db = core.ItemDB(HERE)
latest: core.GuildData | None = None
latest_mtime = 0.0
latest_source_mtime = 0.0


# ---------------------------------------------------------------------------
# File plumbing
# ---------------------------------------------------------------------------
def sv_path() -> str | None:
    paths = core.find_saved_variables(cfg["wow_path"])
    if cfg.get("account"):
        paths = [p for p in paths if os.sep + cfg["account"] + os.sep in p] or paths
    return paths[0] if paths else None


def read_latest(force=False) -> core.GuildData | None:
    global latest, latest_mtime,latest_source_mtime
    path = sv_path()
    if not path:
        return latest
    m = os.path.getmtime(path)
    if force or m != latest_source_mtime or latest is None:
        try:
            latest = core.load_guild_data(path, cfg.get("guild_key"))
            latest_source_mtime = m
        except Exception:
            log.exception("Couldn't read %s (WoW may be mid-save); will retry", path)
    try:combined,fingerprint=bridge.merge_public(latest,cfg)
    except (OSError,ValueError,TypeError,KeyError):combined,fingerprint=latest,''
    latest_mtime=str(latest_source_mtime)+':'+fingerprint
    return combined


inbox_where=''


def adopt_legacy_inbox():
    """Once: carry anything left in the old EPUGuild\\Inbox.lua into the queue."""
    if not core.addon_reads_inbox_addon(cfg["wow_path"]) or state.data.get("legacy_inbox_adopted"):
        return
    try:
        n=state.adopt_legacy_inbox(core.read_legacy_inbox(cfg["wow_path"]))
    except (OSError,ValueError,KeyError,TypeError):
        log.exception("Couldn't read the old Inbox.lua; it's left in place and EPU still reads it.")
        return
    if n:
        log.info("Moved %d queued update(s) from the old Inbox.lua into EPUGuild_Inbox.",n)


def flush_inbox():
    global inbox_where
    try:
        bridge.reconcile_helper_acks(cfg,state)
        bridge.publish(cfg,state)
    except (OSError,ValueError,KeyError,TypeError):
        log.warning('Shared helper folder is unavailable or invalid; the local officer bridge will continue.')
    try:
        entries=state.data['inbox']
        toc=os.path.join(cfg['wow_path'],'Interface','AddOns','EPUGuild','EPUGuild.toc')
        try:
            with open(toc,encoding='utf-8') as f: modules=f.read().splitlines()
            invites_supported='InviteRequests.lua' in modules
        except OSError: invites_supported=False;modules=[]
        if not invites_supported: entries=[e for e in entries if e.get('kind') not in {'guild_invite','sync_helper'}]
        unsupported={kind for kind,module in bridge.EVENT_MODULES.items() if module not in modules}
        entries=[e for e in entries if e.get('kind') not in unsupported]
        entries=[dict(e,guild=cfg['guild_key']) if e.get('kind')=='guild_invite' else e for e in entries]
        chat=core.ingame_chat_list(ingame_chat) if ingame_chat_id else None
        # The old EPUGuild\Inbox.lua is emptied once EPU says it loaded EPUGuild_Inbox.
        seen=latest.db.get('inboxDropSeen') if latest else 0
        where=core.write_inbox_files(cfg["wow_path"], entries, chat, seen_at=seen if isinstance(seen,(int,float)) else 0)
        if where!=inbox_where:
            if where=='addon':
                log.info("Discord updates go to %s, which EPU updates never replace.",core.inbox_drop_path(cfg["wow_path"]))
            elif where=='denied':
                log.warning("Windows won't let me make %s, so Discord updates still go to Inbox.lua inside EPUGuild, "
                            "where an addon update can replace them until I rewrite it. See README (Folder permissions).",core.inbox_addon_dir(cfg["wow_path"]))
            elif where=='legacy':
                log.info("The installed EPU is older and reads Inbox.lua inside EPUGuild. Update EPU so Discord updates are kept where addon updates can't replace them.")
            inbox_where=where
    except (OSError,ValueError,KeyError,TypeError) as e:
        log.error("Couldn't write the Discord inbox (%s). Check folder permissions; see README.", e)


def is_officer(member) -> bool:
    if not isinstance(member, discord.Member):
        return False
    if member.guild_permissions.administrator:
        return True
    want = cfg["officer_role"].lower()
    return any(r.name.lower() == want for r in member.roles)


def channel() -> discord.abc.Messageable | None:
    return client.get_channel(int(cfg["channel_id"]))


# ---------------------------------------------------------------------------
# Request messages
# ---------------------------------------------------------------------------
def request_embed(rid: str, r: dict, gd: core.GuildData | None, note_extra: str = "") -> discord.Embed:
    st = core.status_of(r)
    craft = core.is_craft(r)
    name = gd.request_name(r) if gd else (r.get("itemName") or r.get("spell") or f"item {r.get('item')}")
    e = discord.Embed(title=("Craft: " if craft else "") + f"{name} x{r.get('qty', 1)}", color=STATUS_COLOR.get(st, discord.Color.blurple()))
    if r.get("item"):
        e.url = f"{cfg['wowhead'].rstrip('/')}/item={r['item']}"
    who = gd.label(r.get("who", "?")) if gd else r.get("who", "?")
    if r.get("discord"):
        who += f" via Discord ({r['discord']})"
    e.add_field(name="Requested by", value=who, inline=True)
    if r.get("to") and r.get("to") != r.get("who"):
        e.add_field(name="Mail to", value=r["to"], inline=True)
    if craft:
        e.add_field(name="Crafter", value=r["crafter"], inline=True)
        e.add_field(name="Materials", value={"me": "Requester sends", "bank": "Guild bank sends",
                                              "crafter": "Crafter's own"}.get(r.get("mats"), "Requester sends"), inline=True)
    e.add_field(name="Status", value=core.status_label(r).capitalize(), inline=True)
    if r.get("delivered"):
        e.add_field(name="Delivered", value=f"{r['delivered']} / {r.get('qty', 1)}", inline=True)
    if gd and r.get("item") and not craft:
        e.add_field(name="In bank", value=str(gd.bank_count(r["item"])), inline=True)
        waiting=gd.request_restock(rid,r,state.data['inbox'])
        if waiting:
            e.add_field(name='Awaiting restock',value=str(waiting)+' remaining items need restocking',inline=False)
    if r.get("note"):
        e.add_field(name="Note", value=r["note"], inline=False)
    if st == "rejected" and r.get("reason"):
        e.add_field(name="Reason", value=r["reason"], inline=False)
    if r.get("by") and st != "pending":
        e.add_field(name="By", value=r["by"], inline=True)
    if note_extra:
        e.add_field(name="\u200b", value=note_extra, inline=False)
    e.set_footer(text=f"EPU {'craft ' if craft else ''}request {rid}" + (" · the crafter accepts it in game" if craft and st == "pending" else ""))
    return e


def request_view(rid: str, st: str) -> discord.ui.View | None:
    if st != "pending":
        return None
    v = discord.ui.View(timeout=None)
    v.add_item(discord.ui.Button(label="Approve", style=discord.ButtonStyle.success, custom_id=f"epu:approve:{rid}"))
    v.add_item(discord.ui.Button(label="Reject", style=discord.ButtonStyle.danger, custom_id=f"epu:reject:{rid}"))
    return v


async def post_or_edit(rid: str, r: dict, gd: core.GuildData | None, note_extra: str = ""):
    ch = channel()
    if ch is None:
        log.error("Channel %s not found; check channel_id and the bot's access", cfg["channel_id"])
        return
    st = core.status_of(r)
    embed = request_embed(rid, r, gd, note_extra)
    view = None if core.is_craft(r) else request_view(rid, st)   # crafters answer in game
    posted = state.posted(rid)
    if posted:
        try:
            msg = await ch.fetch_message(posted["message_id"])
            await msg.edit(embed=embed, view=view)
            state.set_posted(rid, msg.id, st,core.request_signature(gd,rid,r,state.data['inbox']))
            return
        except discord.NotFound:
            pass
    msg = await ch.send(embed=embed, view=view)
    state.set_posted(rid, msg.id, st,core.request_signature(gd,rid,r,state.data['inbox']))


# ---------------------------------------------------------------------------
# Pinned status post: one message, edited in place on every refresh
# ---------------------------------------------------------------------------
def _clip(lines: list[str], limit: int = 1000) -> str:
    out, used = [], 0
    for i, line in enumerate(lines):
        if used + len(line) + 1 > limit:
            out.append(f"...and {len(lines) - i} more")
            break
        out.append(line)
        used += len(line) + 1
    return "\n".join(out) or "-"


CATEGORY_EMOJI = {"Cloth": "\U0001F9F5", "Leather": "\U0001F9E5", "Metal & Stone": "\u26CF\uFE0F", "Herbs": "\U0001F33F",
                  "Cooking": "\U0001F356", "Enchanting": "\u2728", "Elemental": "\U0001F525", "Parts & Engineering": "\u2699\uFE0F",
                  "Other Trade Goods": "\U0001F4E6", "Consumables": "\U0001F9EA", "Reagents": "\U0001F52E", "Bags": "\U0001F392",
                  "Weapons & Armor": "\u2694\uFE0F", "Recipes": "\U0001F4DC", "Other": "\U0001F4E6"}


def pending_bridge_updates(gd: core.GuildData, minimum_age=0) -> dict[str, int]:
    now = time.time()
    kinds = {'request', 'status', 'news', 'news_remove', 'checklist', 'guild_invite', 'event_create', 'event_response'}
    events_by_id = gd.g.get('guildEvents') or {}
    counts: dict[str, int] = {}
    for entry in state.data['inbox']:
        kind = entry.get('kind')
        if kind not in kinds or entry['id'] in gd.inbox_done or entry.get('t', now) > now - minimum_age:
            continue
        if kind == 'guild_invite' and now - entry['t'] >= 7 * 86400:
            continue
        if kind == 'event_create' and (entry['starts'] <= now or entry['who'] + '\x1f' + entry['id'] in events_by_id):
            continue
        if kind == 'event_response':
            event = events_by_id.get(entry.get('event'))
            if (event and (event.get('status') != 'scheduled' or event.get('ends', 0) <= now)) or now - entry['t'] >= 7 * 86400:
                continue
        counts[kind] = counts.get(kind, 0) + 1
    return counts


def waiting_for_reload(gd: core.GuildData) -> int:
    return sum(pending_bridge_updates(gd, minimum_age=120).values())


def status_embed(gd: core.GuildData, reload_count: int | None = None) -> discord.Embed:
    st = gd.status_summary()
    e = discord.Embed(title="Guild Bank Status", color=discord.Color.blurple())
    if cfg["logo_url"]:
        e.set_thumbnail(url=cfg["logo_url"])
    if reload_count is None:
        reload_count = waiting_for_reload(gd)
    if reload_count:
        updates = "update is" if reload_count == 1 else "updates are"
        e.add_field(name="WoW reload would help", inline=False, value=(
            f"{reload_count} Discord {updates} waiting for game sync. "
            "A companion user or eligible helper can log in or type `/reload` when convenient."
        ))
    need_lines = []
    for n in st["needs"]:
        frac = n["have"] / n["target"]
        mark = "\U0001F534" if frac < 0.5 else ("\U0001F7E1" if frac < 1 else "\u2705")
        goal = " *(goal)*" if n["kind"] == "goal" else ""
        need_lines.append(f"{mark} **{n['name']}** {n['have']}/{n['target']}{goal}")
    e.add_field(name="Needs", value=_clip(need_lines) if need_lines else "No targets set.", inline=False)
    shop_lines = [f"{r['name']}: {r['buy']}" for r in st["shopping"][:15]]
    e.add_field(name="Shopping list", value=_clip(shop_lines) if shop_lines else "Nothing to buy.", inline=False)
    focus_lines = []
    for f in gd.guild_focus():
        players = f"{f['players']} player" + ("" if f["players"] == 1 else "s")
        if f["goal"]:
            focus_lines.append(f"**{f['prof']}**: goal {f['goal']}, {f['at_goal']} of {players} there")
        else:
            focus_lines.append(f"**{f['prof']}**: {players}")
    if focus_lines:
        e.add_field(name="Guild focus", inline=False, value=_clip(focus_lines + [
            "Professions the officers want more of. Pick one up or level it, and open it in game so EPU shares your recipes."]))
    items = gd.bank_items()
    if items:
        groups: dict = {}
        for r in items:
            groups.setdefault(r["category"], []).append(r)
        cats = [c for c in core.CATEGORIES if c in groups]
        used = sum(len(f.value) + len(f.name) for f in e.fields) + 400      # room for the gold/requests fields and footer
        budget = max(300, (5800 - used) // max(1, len(cats)))
        for cat in cats:
            rows = sorted(groups[cat], key=lambda r: (-r["count"], r["name"]))
            value = _clip([f"{r['name']}: {r['count']}" for r in rows], min(1000, budget))
            e.add_field(name=f"{CATEGORY_EMOJI.get(cat, '')} {cat}".strip(), value=value, inline=True)
    else:
        e.add_field(name="In the bank", value="Nothing recorded yet. A bank character's bags count once it logs in with `/epu bankalt on`; "
                    "open its bank once to add the bank slots.", inline=False)
    e.add_field(name="Gold", value=core.money_text(st["gold"]), inline=True)
    req = f"{st['requests']['pending']} pending, {st['requests']['approved']} approved"
    if st["requests"].get("crafts"):
        req += f"\n{st['requests']['crafts']} open craft requests"
    e.add_field(name="Requests", value=req, inline=True)
    if st["banks"]:
        e.add_field(name="Held by", value=", ".join(st["banks"]), inline=True)
    e.set_footer(text="\U0001F534 under half  \U0001F7E1 below target  \u2705 stocked. Updates when an officer /reloads or logs out.")
    if st["updated"]:
        e.timestamp = datetime.fromtimestamp(st["updated"], tz=timezone.utc)
    return e


status_reload_count = None


async def update_status(gd: core.GuildData):
    global status_reload_count
    if not cfg["status_post"]:
        return
    ch = client.get_channel(int(cfg["status_channel_id"]))
    if ch is None:
        log.error("Status channel %s not found", cfg["status_channel_id"])
        return
    reload_count = waiting_for_reload(gd)
    embed = status_embed(gd, reload_count)
    mid = state.data.get("status_message_id")
    if mid:
        try:
            msg = await ch.fetch_message(mid)
            await msg.edit(embed=embed)
            status_reload_count = reload_count
            return
        except discord.NotFound:
            pass
    msg = await ch.send(embed=embed)
    state.data["status_message_id"] = msg.id
    state.save()
    status_reload_count = reload_count
    try:
        await msg.pin()
    except discord.Forbidden:
        log.warning("Posted the status message but couldn't pin it; give the bot Manage Messages (Pin Messages) or pin it by hand.")


# ---------------------------------------------------------------------------
# Pinned "how to use" post
# ---------------------------------------------------------------------------
def help_embed() -> discord.Embed:
    officer = cfg["officer_role"]
    e = discord.Embed(
        title="How to use the Guild Bank bot",
        description="Ask the guild bank for items, see what it needs, and check what it holds, all from Discord. "
                    "Everything here also works in game with the **EPU Guild Tools** addon (`/epu`).",
        color=discord.Color.blurple())
    e.add_field(name="1. Link your character (once)", inline=False, value=(
        "`/link` gives you a code. In game, type `/epu link CODE` on any character. Every character on that WoW account, "
        "plus your confirmed EPU alts, links itself, and you get class and rank roles. `/chars` lists yours, `/main` picks "
        "your main, `/unlink` removes one. Can't use the addon? `/link character:` asks an officer instead."))
    e.add_field(name="2. Ask for something", inline=False, value=(
        "`/request item:` choose an item the bank currently holds or has stocked before, then "
        "set `qty:`. The picker shows stock and available quantities. Sold-out supplies can wait for restock; weapons and armor must be in stock. Add a `note:` for the officers, "
        "and `character:` if it should be mailed to an alt.\n"
        "Your request is posted here. An officer approves it and mails it to you, and the post updates as it goes: "
        "**Pending, Approved, Filled** (or **Rejected** with a reason)."))
    e.add_field(name="3. See what the bank needs or has", inline=False, value=(
        "`/needs`: what the bank is short on. Donations of these are the most help.\n"
        "`/bank search:` look up an item, e.g. `/bank search:potion`.\n"
        "`/requests`: all open requests.\n"
        "`/craft item:` who in the guild can make something, and what it takes (\u2b50 = guild crafter).\n"
        "`/neededmats`: materials guildmates are collecting for their professions. Send them a stack before you vendor it.\n"
        "`/levelboard`: levels guildmates have gained this week. Last week's board is posted weekly.\n"
        "The pinned **Guild Bank Status** post shows stock levels, the shopping list and gold at a glance."))
    e.add_field(name="Getting something crafted", inline=False, value=(
        "In game, open the addon's **Recipes** page, pick the recipe and click **Ask ... to craft**. Choose who "
        "provides the materials (you, the guild bank, or the crafter). The crafter gets a pop-up and accepts it, "
        "and you're told when it's made. Craft requests show up here too. Hover any pattern or recipe in game "
        "to see whether someone in the guild already knows it."))
    e.add_field(name="Donating", inline=False, value=(
        "Items the bank needs show a gold coin in your bags and a line on their tooltip. At any mailbox the addon's "
        "Donate panel lets you pick what to give and fills the mail to the bank character for you. Deposits in the "
        "guild bank count too. Donations are logged automatically, and you'll get a thank-you here."))
    e.add_field(name="Guild news", inline=False, value=(
        "Level-ups every 10 levels, first mounts, profession ranks, big donations and new members are posted here "
        "automatically. In game, the addon's **Roster** page shows who's online, their level and role, and who's "
        "near your level or on your layer. Set your role and what you're looking for under **Profile**. "
        "`/whois` shows who plays a character."))
    e.add_field(name=f"Officers ({officer} role)", inline=False, value=(
        "`/announce` posts a guild announcement here and as a pop-up in game. Posts in the announcements channel "
        "are copied into the game too, and the in-game message of the day is mirrored here.\n"
        "Use the **Approve** and **Reject** buttons on request posts. Reject asks for an optional reason.\n"
        "Mailing or trading an approved item to the requester marks it filled automatically."))
    e.add_field(name="Why isn't it instant?", inline=False, value=(
        "WoW addons can't use the internet, so the bot and the game swap notes through files. Those are written when an "
        "officer types `/reload` or `/epu save`, or logs in or out. Requests made here reach the game, and changes made "
        "in game reach Discord, at the next one of those, usually within the same play session."))
    if cfg.get('invite_requests_channel_id'):
        e.add_field(name='Ask to join the guild',inline=False,value='In #guild-invite-requests, type `/guildinvite` and select the command, then fill in your character’s first and last name. Alternatively post a standalone `Character: First Last` line. Eligible guildmates receive an in-game request after the companion officer’s next login or `/reload`. Invitations are manual.')
    cf = cfg["curseforge_url"]
    e.add_field(name="Get the addon: CurseForge (recommended)", inline=False, value=(
        "1. Install the free **CurseForge app** from https://www.curseforge.com/download/app and sign in (a free "
        "CurseForge account keeps your addons with you).\n"
        f"2. Open {cf} and click **Install**. Pick **World of Warcraft**, then your **Forever** install.\n"
        "3. That's it: the app keeps it updated. Turn on auto-update in the app's World of Warcraft settings so new "
        "versions install on their own.\n"
        "Type `/epu` in game to open the addon. It's unlisted, so search won't find it; use the link."))
    e.add_field(name="Other ways", inline=False, value=(
        "**WowUp:** pick **World of Warcraft Forever** at the top, then Get Addons > Install from URL and paste "
        f"`https://github.com/{cfg['github_repo']}`.\n"
        "**Updater or by hand:** type `/download`.\n"
        "Use one of these, not several; they'd each try to update it."))
    if cfg["logo_url"]:
        e.set_thumbnail(url=cfg["logo_url"])
    e.set_footer(text="Type /help any time to see this again.")
    return e


async def ensure_help_post():
    if not cfg["help_post"]:
        return
    ch = client.get_channel(int(cfg["channel_id"]))
    if ch is None:
        return
    embed = help_embed()
    mid = state.data.get("help_message_id")
    try:
        if mid:
            try:
                msg = await ch.fetch_message(mid)
                await msg.edit(embed=embed)          # keep the text current after updates
                return
            except discord.NotFound:
                pass
        msg = await ch.send(embed=embed)
        state.data["help_message_id"] = msg.id
        state.save()
        try:
            await msg.pin()
        except discord.Forbidden:
            log.warning("Posted the how-to message but couldn't pin it; give the bot Manage Messages or pin it by hand.")
    except Exception as e:
        explain(e, "post the how-to message", cfg["channel_id"])


# ---------------------------------------------------------------------------
# Releases: announce new versions, /download
# ---------------------------------------------------------------------------
latest_release: dict | None = None
_cf_note: tuple | None = None   # the last CurseForge problem logged


def download_embed(rel: dict | None) -> discord.Embed:
    e = discord.Embed(title="Get EPU Guild Tools", color=discord.Color.gold())
    if cfg["logo_url"]:
        e.set_thumbnail(url=cfg["logo_url"])
    if not rel:
        e.description = (f"**Recommended:** [install it with CurseForge]({cfg['curseforge_url']}).\n"
                         f"Or get the [latest release]({cfg['addon_url']}).")
        return e
    e.description = f"Current version: **{rel['version']}**"
    e.add_field(name="Recommended: CurseForge", inline=False, value=(
        f"[Open EPU Guild Tools on CurseForge]({cfg['curseforge_url']}) and click **Install** (you need the free "
        "[CurseForge app](https://www.curseforge.com/download/app)). Pick your **Forever** install, and the app keeps "
        "it updated."))
    e.add_field(name="Use WowUp?", inline=False, value=(
        "Pick **World of Warcraft Forever** at the top, then Get Addons > Install from URL and paste "
        f"`https://github.com/{cfg['github_repo']}`. WowUp keeps it updated."))
    if rel.get("updater"):
        e.add_field(name="No addon app?", inline=False, value=(
            f"[Download the updater]({rel['updater']}), unzip it somewhere you'll keep, and double-click "
            "**Update EPU Guild Tools**."
            + (f" Or [download the addon]({rel['addon']}) and unzip it into "
               "`World of Warcraft\\_forever_\\Interface\\AddOns`." if rel.get("addon") else "")))
    if rel.get("page"):
        e.add_field(name="\u200b", value=f"[Release notes]({rel['page']})", inline=False)
    return e


async def check_release(announce: bool = True):
    """Announce a new GitHub release, once CurseForge has approved its file.

    The version only counts as announced once it's posted, so a release that
    waits for CurseForge is checked again on every run of the loop. If the bot
    can't see CurseForge approve it within curseforge_wait_hours, it's
    announced anyway, with a footer that doesn't promise the CurseForge app has it."""
    global latest_release, _cf_note
    try:
        rel = await asyncio.to_thread(core.fetch_latest_release, cfg["github_repo"])
    except Exception as e:
        log.debug("Release check failed: %s", e)
        return
    if rel["draft"] or not rel["tag"]:
        return
    latest_release = rel
    seen = state.data.get("last_release")
    gated = core.curseforge_source(cfg) is not None
    enabled = announce and cfg["announce_releases"]
    approved = None
    if gated and seen not in (None, rel["tag"]) and enabled:
        try:
            files = await asyncio.to_thread(core.fetch_curseforge_files, cfg)
            approved = core.curseforge_has_version(files, rel["version"])
        except Exception as e:
            note = (rel["tag"], str(e))
            if note != _cf_note:          # once per release and problem, not every 30 minutes
                _cf_note = note
                log.warning("Couldn't ask CurseForge whether %s is approved (%s). The announcement waits up to "
                            "%s hours from the release, then posts anyway.", rel["version"], e, cfg["curseforge_wait_hours"])
    overdue = core.release_overdue(rel.get("published"), cfg["curseforge_wait_hours"], time.time())
    step = core.release_step(seen, rel["tag"], enabled, gated, approved, overdue)
    if step == "none":
        return
    if step == "wait":
        if state.data.get("release_waiting") != rel["tag"]:
            state.data["release_waiting"] = rel["tag"]
            state.save()
            log.info("EPU Guild Tools %s is on GitHub; announcing it once CurseForge approves it "
                     "(or after %s hours).", rel["version"], cfg["curseforge_wait_hours"])
        return
    ch = client.get_channel(int(cfg["release_channel_id"])) if step == "announce" else None
    if step == "announce" and ch is None:
        note = (rel["tag"], "channel")
        if note != _cf_note:            # left unannounced, so it posts once the channel is fixed
            _cf_note = note
            log.warning("Can't see the release channel %s, so %s isn't announced yet. Check release_channel_id "
                        "and that the bot can view and post in that channel.", cfg["release_channel_id"], rel["version"])
        return
    state.data["last_release"] = rel["tag"]
    state.data.pop("release_waiting", None)
    state.save()
    if step == "remember":
        return                          # first run, or announcements off: remember the version without a post
    e = download_embed(rel)
    e.title = f"EPU Guild Tools {rel['version']} is out"
    notes = rel["notes"][:900] + ("..." if len(rel["notes"]) > 900 else "")
    if notes:
        e.description = notes
    if gated and approved:
        e.set_footer(text="It's live on CurseForge, so the CurseForge app offers it as an update. "
                          "WowUp and the updater have it too. Then /reload in game.")
    else:
        e.set_footer(text="CurseForge app: it shows up as an update once CurseForge approves it (usually within a day). "
                          "WowUp and the updater have it now. Then /reload in game.")
    try:
        await ch.send(embed=e)
        log.info("Announced EPU Guild Tools %s in channel %s.", rel["version"], cfg["release_channel_id"])
    except Exception as ex:
        explain(ex, "announce the new release", cfg["release_channel_id"])


# ---------------------------------------------------------------------------
# Updating itself to each new release
# ---------------------------------------------------------------------------
restart_requested = False
_update_note: tuple | None = None   # the last problem logged, so a skip isn't logged every 30 minutes


def update_wanted(rel: dict | None) -> bool:
    if not cfg["auto_update"] or not rel or rel.get("draft") or not rel.get("tag"):
        return False
    if os.environ.get("EPU_SUPERVISED") != "1":
        return False                    # run through start.bat, which starts it again after an update
    return state.data.get("update_failed") != rel["tag"]


async def maybe_update():
    """Fast-forward this clone to the latest release and restart, if it's safe (see self_update.py)."""
    global restart_requested, _update_note
    rel = latest_release
    if not update_wanted(rel):
        return
    result = await asyncio.to_thread(self_update.update_to, rel["tag"])
    if result.status == "current":
        _update_note = None
        return
    if result.status == "updated":
        log.info("Bot %s; restarting.", result.message)
        self_update.log_line(result.message)
        restart_requested = True
        await client.close()
        return
    if result.status == "failed":
        state.data["update_failed"] = rel["tag"]   # wait for the next release rather than retry this one
        state.save()
    note = (rel["tag"], result.message)
    if note != _update_note:
        _update_note = note
        log.warning("Not updating the bot to %s: %s", rel["tag"], result.message)
        self_update.log_line(f"not updated to {rel['tag']}: {result.message}")


@tasks.loop(minutes=30)
async def release_loop():
    await check_release()
    await maybe_update()


# ---------------------------------------------------------------------------
# Daily guild needs (from the addon's needed mats lists)
# ---------------------------------------------------------------------------
def guild_needs_embed(gd: core.GuildData, now: float | None = None, saved_at: float | None = None) -> discord.Embed | None:
    """The needed mats post, or None when nobody needs anything."""
    rows = gd.needed_mats(now)
    if not rows:
        return None
    groups, left_out = core.needed_mats_groups(rows, cfg["guild_needs_max_items"])
    e = discord.Embed(title="Guild needs", color=discord.Color.teal(),
                      description="Materials guildmates are collecting. Mail or trade them a stack before you vendor or auction it.")
    for prof, lines in groups[:24]:
        e.add_field(name=prof, value=_clip(lines, 1000), inline=False)
    if left_out:
        e.add_field(name="\u200b", value=f"...and {left_out} more. In game: **Professions > Needed mats**.", inline=False)
    e.set_footer(text="Add yours in game with /epu mats." + (" From the officer save" if saved_at else ""))
    if saved_at:
        e.timestamp = datetime.fromtimestamp(saved_at, timezone.utc)   # Discord shows it in each reader's time
    return e


def guild_needs_due(now: datetime, last_day: str | None) -> bool:
    """Once a day, at or after guild_needs_time on this PC's clock."""
    h, m = parse_clock(cfg["guild_needs_time"]) or (18, 0)
    return last_day != now.date().isoformat() and (now.hour, now.minute) >= (h, m)


async def post_guild_needs(now: datetime | None = None) -> bool:
    """Post today's list if it's due. Returns True if something was posted."""
    now = now or datetime.now()
    if not cfg["guild_needs_post"] or not guild_needs_due(now, state.data.get("guild_needs_day")):
        return False
    gd = read_latest()
    if gd is None:
        return False                      # no SavedVariables yet: try again next minute
    e = guild_needs_embed(gd, now.timestamp(), latest_source_mtime or None)
    if e is not None:
        ch = client.get_channel(int(cfg["guild_needs_channel_id"]))
        if ch is None:
            log.warning("guild_needs_channel_id %s isn't a channel the bot can see; skipping today's guild needs post.",
                        cfg["guild_needs_channel_id"])
        else:
            try:
                await ch.send(embed=e)
            except Exception as ex:
                explain(ex, "post the daily guild needs", cfg["guild_needs_channel_id"])
                return False              # try again next minute
    state.data["guild_needs_day"] = now.date().isoformat()   # an empty list counts as done for today
    state.save()
    return e is not None


@tasks.loop(minutes=1)
async def guild_needs_loop():
    try:
        await post_guild_needs()
    except Exception:
        log.exception("Couldn't build the daily guild needs post; will retry")


# ---------------------------------------------------------------------------
# Weekly leveling board (levels gained, from the addon's level history)
# ---------------------------------------------------------------------------
LEVEL_PLACES = ["\U0001f947", "\U0001f948", "\U0001f949"]   # gold, silver and bronze medals


def _day_label(d: datetime) -> str:
    return f"{d.strftime('%b')} {d.day}"


def leveling_board_embed(gd: core.GuildData, start: datetime, end: datetime, title: str | None = None) -> discord.Embed | None:
    """The leveling board for [start, end), or None when nobody gained a level."""
    rows = gd.leveling_board(start.timestamp(), end.timestamp())
    if not rows:
        return None
    shown = rows[:cfg["leveling_board_max"]]
    lines = []
    for i, r in enumerate(shown):
        place = LEVEL_PLACES[i] if i < len(LEVEL_PLACES) else f"{i + 1}."
        lines.append(f"{place} **{r['label']}** {r['from']} \u2192 {r['to']} (+{r['gained']})")
    if len(rows) > len(shown):
        lines.append(f"...and {len(rows) - len(shown)} more.")
    total = sum(r["gained"] for r in rows)
    last_day = end - timedelta(days=1)
    e = discord.Embed(title=title or f"Leveling board: {_day_label(start)} to {_day_label(last_day)}",
                      color=discord.Color.gold(), description=_clip(lines, 3900))
    people = f"{len(rows)} guildmate" + ("" if len(rows) == 1 else "s")
    e.set_footer(text=f"{people} gained {total} level{'' if total == 1 else 's'}. "
                      "See this week so far in game: /epu levelboard")
    return e


def leveling_board_schedule(now: datetime):
    h, m = parse_clock(cfg["leveling_board_time"]) or (19, 0)
    return core.leveling_board_period(now, core.parse_weekday(cfg["leveling_board_day"]) or 0, h, m)


async def post_leveling_board(now: datetime | None = None) -> bool:
    """Post last week's board if it's due. Returns True if something was posted.
    It posts once a week at leveling_board_day / leveling_board_time; if the bot
    was off then, it posts when it starts, up to two days late."""
    now = now or datetime.now()
    if not cfg["leveling_board_post"]:
        return False
    at, start, end = leveling_board_schedule(now)
    week = start.date().isoformat()
    if state.data.get("leveling_board_week") == week:
        return False
    if now - at > timedelta(days=2):
        return False                      # too late for this week's post: wait for next week's
    gd = read_latest()
    if gd is None:
        return False                      # no SavedVariables yet: try again next minute
    e = leveling_board_embed(gd, start, end)
    if e is not None:
        ch = client.get_channel(int(cfg["leveling_board_channel_id"]))
        if ch is None:
            log.warning("leveling_board_channel_id %s isn't a channel the bot can see; skipping this week's leveling board.",
                        cfg["leveling_board_channel_id"])
        else:
            try:
                await ch.send(embed=e)
            except Exception as ex:
                explain(ex, "post the weekly leveling board", cfg["leveling_board_channel_id"])
                return False              # try again next minute
    state.data["leveling_board_week"] = week   # a week with no level-ups counts as done
    state.save()
    return e is not None


@tasks.loop(minutes=1)
async def leveling_board_loop():
    try:
        await post_leveling_board()
    except Exception:
        log.exception("Couldn't build the weekly leveling board; will retry")


@tree.command(name="levelboard", description="Levels guildmates have gained this week (EPU's leveling board)", guild=GUILD)
async def levelboard_cmd(interaction: discord.Interaction):
    gd = read_latest()
    now = datetime.now()
    start = datetime(now.year, now.month, now.day) - timedelta(days=now.weekday())
    e = leveling_board_embed(gd, start, now + timedelta(seconds=1),
                             title=f"Leveling board: this week so far (since {_day_label(start)})") if gd else None
    if e is None:
        await interaction.response.send_message("Nobody has gained a level yet this week.", ephemeral=True)
        return
    await interaction.response.send_message(embed=e, ephemeral=True)


@tree.command(name="neededmats", description="Materials guildmates are collecting (from EPU's needed mats)", guild=GUILD)
async def neededmats_cmd(interaction: discord.Interaction):
    gd = read_latest()
    e = guild_needs_embed(gd, saved_at=latest_source_mtime or None) if gd else None
    if e is None:
        await interaction.response.send_message("Nobody in the guild has listed needed mats. Add yours in game with `/epu mats`.",
                                                ephemeral=True)
        return
    await interaction.response.send_message(embed=e, ephemeral=True)


@tree.command(name="download", description="How to install EPU Guild Tools (CurseForge, WowUp or the updater)", guild=GUILD)
async def download_cmd(interaction: discord.Interaction):
    await interaction.response.send_message(embed=download_embed(latest_release), ephemeral=True)


@tree.command(name="help", description="How to use the Guild Bank bot", guild=GUILD)
async def help_cmd(interaction: discord.Interaction):
    await interaction.response.send_message(embed=help_embed(), ephemeral=True)


# ---------------------------------------------------------------------------
# Polling the SavedVariables file
# ---------------------------------------------------------------------------
polled_mtime = 0.0


def explain(e: Exception, what: str, channel_id) -> None:
    if isinstance(e, discord.Forbidden):
        log.error("Discord refused to let me %s in channel %s (%s). If the channel is private, add the bot under "
                  "Edit Channel > Permissions with View Channel, Send Messages, Embed Links, Read Message History "
                  "and Manage Messages. Also check that channel_id is on the same server as server_id. "
                  "I'll retry on the next refresh.", what, channel_id, e.text or e)
    else:
        log.exception("Couldn't %s in channel %s; will retry on the next refresh", what, channel_id)


@tasks.loop(seconds=15)
async def poll():
    global polled_mtime
    flush_inbox()
    gd = read_latest()
    if gd is not None: await post_invite_results(gd)
    if gd is not None:
        try:await events.refresh(gd)
        except Exception as e:explain(e,'update guild events',cfg.get('events_channel_id'))
        try:await board.refresh(gd)
        except Exception as e:explain(e,'update the dungeon board',cfg['group_board_channel_id'])
    if gd is None:
        return
    if latest_mtime == polled_mtime:
        if cfg["status_post"] and waiting_for_reload(gd) != status_reload_count:
            try:
                await update_status(gd)
            except Exception as e:
                explain(e, "update the reload reminder", cfg["status_channel_id"])
        return
    try:
        await refresh(gd)
        polled_mtime = latest_mtime          # only once everything went through
    except Exception as e:                   # never let one failure stop the loop
        explain(e, "post", cfg["channel_id"])


async def refresh(gd: core.GuildData):
    if state.prune_inbox(gd.inbox_done):
        flush_inbox()
    changes = core.diff(gd, state)
    for rid, r in changes["new_requests"] + changes["changed_requests"]:
        await post_or_edit(rid, r, gd)
    try:
        await update_status(gd)
    except Exception as e:
        explain(e, "update the status post", cfg["status_channel_id"])
    await post_milestones(gd, changes["new_feed"])
    for nid, e in changes["news"]:
        await post_news(nid, e)
    if changes.get("motd"):
        await post_motd(changes["motd"])
    try:
        result = await sync_links_roles(gd)
        if summary := role_change_summary(result):
            state.data["last_automatic_role_changes"] = {"at": int(time.time()), "summary": summary}
    except Exception as e:
        explain(e, "update linked characters and roles", cfg.get("officer_log_channel_id") or cfg["channel_id"])
    if cfg["post_donations"] and changes["new_donations"]:
        ch = channel()
        for d in changes["new_donations"][:10]:
            what = f"{d.get('n', 1)}x {gd.item_name(d['item'])}" if d.get("item") else core.money_text(d.get("money"))
            if ch:
                await ch.send(f"Thanks **{d.get('who', '?')}** for donating {what} to the guild bank!")
    state.save()


# ---------------------------------------------------------------------------
# Milestones and announcements
# ---------------------------------------------------------------------------
FEED_EMOJI = {"level": "\U0001F389", "mount": "\U0001F40E", "prof": "\U0001F528", "donation": "\U0001F4B0", "join": "\U0001F44B", "attune": "\U0001F511"}


def milestone_line(gd: core.GuildData, e: dict) -> str:
    emoji = FEED_EMOJI.get(e.get("kind"), "\u2b50")
    return f"{emoji} **{gd.label(e.get('who', '?'))}** {e.get('text', '')}!"


async def post_milestones(gd: core.GuildData, entries: list[dict]):
    if not cfg["post_milestones"] or not entries:
        return
    ch = client.get_channel(int(cfg["feed_channel_id"]))
    if ch is None:
        return
    try:
        await ch.send("\n".join(milestone_line(gd, e) for e in entries[:15]))
    except Exception as ex:
        explain(ex, "post guild milestones", cfg["feed_channel_id"])


def news_embed(e: dict) -> discord.Embed:
    em = discord.Embed(title=e.get("title") or "Guild announcement", description=e.get("text") or "", color=discord.Color.gold())
    if cfg["logo_url"]:
        em.set_thumbnail(url=cfg["logo_url"])
    em.set_footer(text=f"Posted by {e.get('by', '?')}. Shows as a pop-up in game at everyone's next login.")
    return em


async def post_news(nid: str, e: dict):
    ch = client.get_channel(int(cfg["announce_channel_id"]))
    if ch is None:
        return
    posted = state.data.setdefault("news_posted", {})
    p = posted.get(nid)
    if p and p.get("external"):
        return          # it came from the announcements channel; the original post is already there
    try:
        if p:
            try:
                msg = await ch.fetch_message(p["message_id"])
                if e.get("removed"):
                    await msg.delete()
                else:
                    await msg.edit(embed=news_embed(e))
                posted[nid] = {"message_id": p["message_id"], "u": e.get("u") or 0}
                return
            except discord.NotFound:
                if e.get("removed"):
                    posted[nid] = {"message_id": p["message_id"], "u": e.get("u") or 0}
                    return
        msg = await ch.send(embed=news_embed(e))
        posted[nid] = {"message_id": msg.id, "u": e.get("u") or 0}
    except Exception as ex:
        explain(ex, "post an announcement", cfg["announce_channel_id"])


async def post_motd(text: str):
    if not cfg["post_motd"]:
        return
    ch = client.get_channel(int(cfg["announce_channel_id"]))
    if ch is None:
        return
    em = discord.Embed(title="Guild message of the day", description=text, color=discord.Color.gold())
    em.set_footer(text="Set in game in the guild window.")
    try:
        await ch.send(embed=em)
    except Exception as ex:
        explain(ex, "post the guild message of the day", cfg["announce_channel_id"])


# --- copying an existing announcements channel into the game ---------------
async def import_invite_message(message: discord.Message, edit: bool = False) -> bool:
    cid=cfg.get('invite_requests_channel_id')
    if not cid or str(message.channel.id)!=str(cid) or not message.guild or str(message.guild.id)!=str(cfg['server_id']): return False
    if getattr(message.author,'bot',False) or getattr(message,'webhook_id',None) or message.type not in (discord.MessageType.default,discord.MessageType.reply): return False
    who=core.invite_from_message(message.content)
    source='m'+str(message.id)
    if who is None and (not edit or source not in state.data.get('invite_sources',{})): return False
    try:
        changed=state.queue_guild_invite(source,who,message.author.display_name,str(message.author.id),int(message.created_at.timestamp()))
    except ValueError:
        return False
    if changed: flush_inbox()
    return changed

@tree.command(name='guildevent', description='Schedule a guild activity in EPU from #events', guild=GUILD)
@app_commands.describe(
    title='Event name',
    start='Local date and time, e.g. 2026-11-20 19:00',
    time_zone='Choose a time zone or search by city, such as Eastern or London',
    details='What guildmates should know',
    meet_at='Zone or meeting spot',
    activity='Kind of guild activity',
    minutes='Duration in minutes',
    players='Planned group size',
    organiser='Full name of one of your verified guild characters (defaults to your first link)',
)
@app_commands.choices(activity=[app_commands.Choice(name=label, value=key) for key, label in EVENT_KINDS.items()])
async def guildevent_cmd(
    interaction: discord.Interaction,
    title: app_commands.Range[str, 1, 80],
    start: app_commands.Range[str, 1, 32],
    time_zone: app_commands.Range[str, 1, 100] = '',
    details: app_commands.Range[str, 0, 500] = '',
    meet_at: app_commands.Range[str, 0, 80] = '',
    activity: str = 'other',
    minutes: app_commands.Range[int, 15, 480] = 60,
    players: app_commands.Range[int, 2, 40] = 5,
    organiser: app_commands.Range[str, 1, 80] = '',
):
    await events.create(interaction, title, start, details, meet_at, activity, minutes, players, organiser, time_zone)


@guildevent_cmd.autocomplete('time_zone')
async def guildevent_time_zone(_interaction: discord.Interaction, current: str):
    return time_zone_choices(current)


@tree.command(name='guildinvite',description='Ask to join the WoW guild using your character’s first and last name',guild=GUILD)
@app_commands.describe(first_name="Your character's first name",last_name="Your character's last name")
async def guildinvite_cmd(interaction: discord.Interaction, first_name: str, last_name: str):
    cid=cfg.get('invite_requests_channel_id')
    if not cid or str(interaction.guild_id)!=str(cfg['server_id']) or str(interaction.channel_id)!=str(cid):
        await interaction.response.send_message('Use this command in #guild-invite-requests. An officer must configure invite_requests_channel_id first.',ephemeral=True); return
    try:
        who=core.invite_character(first_name,last_name)
        changed=state.queue_guild_invite('c'+str(interaction.id),who,interaction.user.display_name,str(interaction.user.id),int(datetime.now(timezone.utc).timestamp()))
    except ValueError as error:
        await interaction.response.send_message(str(error),ephemeral=True); return
    if changed: flush_inbox()
    await interaction.response.send_message(('Guild invite requested\nCharacter: '+who+'\nQueued for an eligible guildmate’s next bridge import. ✅ will mean the game confirmed an invite was sent or the character joined.') if changed else ('An active request already exists for '+who+'. No duplicate alert was created.'),ephemeral=not changed,allowed_mentions=discord.AllowedMentions.none())
    if changed:
        reply=await interaction.original_response()
        state.data['invite_sources']['c'+str(interaction.id)]['message_id']=reply.id;state.save()

async def post_invite_results(gd):
    cid=cfg.get('invite_requests_channel_id')
    if not cid:return
    channel=client.get_channel(int(cid))
    if not channel:return
    reacted=state.data.setdefault('invite_reactions',{})
    for source,request in state.data.get('invite_sources',{}).items():
        outcomes=[r for r in (gd.g.get('inviteOutcomes') or {}).values() if isinstance(r,dict) and r.get('source')==source and r.get('who')==request['who'] and r.get('requestRevision')==request.get('revision') and r.get('phase') in ('sent','joined')]
        desired=bool(outcomes) and not request.get('cancelled')
        old=reacted.get(source)
        current=request.get('revision')
        if desired and old==current:continue
        if not desired and not old:continue
        mid=request.get('message_id') or (int(source[1:]) if source.startswith('m') else None)
        if not mid:continue
        try:
            message=await channel.fetch_message(mid)
            if desired:await message.add_reaction('✅');reacted[source]=current
            else:await message.remove_reaction('✅',client.user);reacted.pop(source,None)
            state.save()
        except discord.NotFound:
            reacted.pop(source,None)
        except discord.HTTPException as error:
            log.warning('Could not update an invite-request checkmark; check View Channel, Read Message History and Add Reactions permissions (%s).',error.status)

def queue_helper_whitelist():
    desired=sorted({name for helper in cfg.get('sync_helpers',{}).values() if helper.get('enabled',True) for name in helper.get('characters',[])})
    previous=state.data.get('helper_config_characters',[])
    if desired==previous:return
    for name in sorted(set(desired)|set(previous)):
        enabled=name in desired
        if enabled==(name in previous):continue
        state.data['inbox'].append({'id':'helper-'+uuid.uuid4().hex[:16],'kind':'sync_helper','who':name,'enabled':enabled,'t':int(time.time())})
    state.data['helper_config_characters']=desired;state.save()

async def may_import(message: discord.Message) -> bool:
    if message.author.id == client.user.id or message.type not in (discord.MessageType.default, discord.MessageType.reply):
        return False
    if not cfg["import_officers_only"]:
        return True
    member = message.author if isinstance(message.author, discord.Member) else None
    if member is None and message.guild is not None:
        try:
            member = await message.guild.fetch_member(message.author.id)
        except discord.HTTPException:
            return False
    return is_officer(member)


def embeds_of(message) -> list[dict]:
    return [{"title": em.title, "description": em.description} for em in getattr(message, "embeds", [])]


def _pending(nid: str) -> bool:
    return any(e.get("kind") == "news" and e.get("nid") == nid for e in state.data.get("inbox", []))


async def import_message(message: discord.Message, edit: bool = False, quiet: bool = False) -> bool:
    imported = state.data.setdefault("imported", {})
    key = str(message.id)
    if edit and key not in imported:
        return False
    if key in imported and not edit and not _pending("m" + key):
        return False          # already in the game
    if not edit and not await may_import(message):
        return False
    title, text = core.message_to_news(message.clean_content, embeds_of(message))
    if not text and title == "Announcement":
        return False      # an image-only post, nothing to show in game
    nid = "m" + key
    state.queue_news(title, text, message.author.display_name, nid=nid, edit=edit,
                     posted_at=int(message.created_at.timestamp()), quiet=quiet)
    imported[key] = int(message.created_at.timestamp())
    # the post already exists in Discord, so don't post it back when it shows up from the game
    state.data.setdefault("news_posted", {})[nid] = {"message_id": message.id, "u": 10 ** 12, "external": True}
    state.save()
    flush_inbox()
    log.info("Copied announcement %s into the game inbox (%s)", message.id, title)
    return True


async def backfill_announcements():
    cid = cfg["import_channel_id"]
    if not cid:
        return
    ch = client.get_channel(int(cid))
    if ch is None:
        log.error("import_channel_id %s not found; check the ID and that the bot can see that channel.", cid)
        return
    after = datetime.now(timezone.utc) - timedelta(days=float(cfg["import_days"]))
    n = 0
    recent = datetime.now(timezone.utc) - timedelta(days=3)
    try:
        async for m in ch.history(limit=50, after=after, oldest_first=True):
            # older posts go into News quietly; only the last few days pop up in game
            if await import_message(m, quiet=m.created_at < recent):
                n += 1
    except discord.Forbidden:
        log.error("The bot can't read the history of channel %s. Give it View Channel and Read Message History there.", cid)
        return
    if n:
        log.info("Copied %d existing announcement(s) into the game. They appear after an officer's next /reload.", n)


# Guild chat from the Discord channel the game links to guild chat. The last
# day goes into Inbox.lua; EPU fills gaps in its Guild chat from it at login.
ingame_chat: dict[str, dict] = {}
ingame_chat_id: str = ""


def find_ingame_chat_channel():
    cid = str(cfg.get("ingame_chat_channel_id") or "")
    if cid:
        return client.get_channel(int(cid))
    guild = client.get_guild(int(cfg["server_id"]))
    if not guild or not cfg.get("ingame_chat_channel"):
        return None
    for ch in guild.text_channels:
        if core.channel_matches(ch.name, cfg["ingame_chat_channel"]):
            return ch
    return None


def from_game(message: discord.Message) -> bool:
    """Lines typed in game reach Discord through the game's app (the controller icon)."""
    return getattr(message, "application_id", None) is not None or bool(message.webhook_id)


def add_ingame_chat(message: discord.Message) -> bool:
    # skip only this bot's own posts: the game's relay may come through an app or webhook
    if message.author == client.user or message.type not in (discord.MessageType.default, discord.MessageType.reply):
        return False
    uid = message.author.id
    chars = state.characters_for(uid)
    who = None
    if chars:
        try:
            who = lr.main_for(latest, state, uid) if latest else chars[0]
        except Exception:
            who = chars[0]
    line = core.ingame_chat_line(message.id, message.created_at.timestamp(), who or message.author.display_name,
                                 message.clean_content, chars, from_game(message),
                                 cfg["guild_key"])
    if not line:
        return False
    ingame_chat[line["id"]] = line
    return True


async def backfill_ingame_chat():
    global ingame_chat_id
    ch = find_ingame_chat_channel()
    if ch is None:
        if cfg.get("ingame_chat_channel") or cfg.get("ingame_chat_channel_id"):
            log.info("No #%s channel found, so Discord guild chat won't be added to EPU. Set ingame_chat_channel_id in config.json to use another channel.",
                     cfg.get("ingame_chat_channel") or cfg.get("ingame_chat_channel_id"))
        return
    after = datetime.now(timezone.utc) - timedelta(hours=core.INGAME_CHAT_HOURS)
    n = game_count = 0
    try:
        async for m in ch.history(limit=core.INGAME_CHAT_MAX, after=after, oldest_first=True):
            if add_ingame_chat(m):
                n += 1
                game_count += from_game(m)
    except discord.Forbidden:
        log.error("The bot can't read #%s. Give it View Channel and Read Message History there.", ch.name)
        return
    ingame_chat_id = str(ch.id)
    if ingame_chat:
        last = max(ingame_chat.values(), key=lambda v: v["t"])
        log.info("Newest #%s line: %s: %s (from the game: %s)", ch.name, last["who"], last["msg"][:60], "yes" if last.get("game") else "no")
    flush_inbox()
    log.info("Guild chat from #%s: %d message(s) in the last day (%d sent from the game). EPU adds any it missed at the next login or /reload.",
             ch.name, n, game_count)


@client.event
async def on_message(message: discord.Message):
    if ingame_chat_id and str(message.channel.id) == ingame_chat_id:
        if add_ingame_chat(message):
            flush_inbox()
        return
    if cfg.get('invite_requests_channel_id') and str(message.channel.id)==str(cfg['invite_requests_channel_id']):
        await import_invite_message(message); return
    if cfg["import_channel_id"] and str(message.channel.id) == str(cfg["import_channel_id"]):
        await import_message(message)


@client.event
async def on_raw_message_edit(payload: discord.RawMessageUpdateEvent):
    if cfg.get('invite_requests_channel_id') and str(payload.channel_id)==str(cfg['invite_requests_channel_id']):
        ch=client.get_channel(payload.channel_id)
        if ch:
            try: await import_invite_message(await ch.fetch_message(payload.message_id),edit=True)
            except discord.HTTPException: pass
        return
    if not cfg["import_channel_id"] or str(payload.channel_id) != str(cfg["import_channel_id"]):
        return
    if str(payload.message_id) not in state.data.get("imported", {}):
        return
    ch = client.get_channel(payload.channel_id)
    try:
        msg = await ch.fetch_message(payload.message_id)
    except discord.HTTPException:
        return
    await import_message(msg, edit=True)


@client.event
async def on_raw_message_delete(payload: discord.RawMessageDeleteEvent):
    if ingame_chat.pop(str(payload.message_id), None):
        flush_inbox()
    if cfg.get('invite_requests_channel_id') and str(payload.channel_id)==str(cfg['invite_requests_channel_id']):
        source='m'+str(payload.message_id)
        if source not in state.data.get('invite_sources',{}):source=next((k for k,v in state.data.get('invite_sources',{}).items() if v.get('message_id')==payload.message_id),source)
        old=state.data.get('invite_sources',{}).get(source)
        if old and state.queue_guild_invite(source,None,old['requester'],old['user'],old['posted']): flush_inbox()
        return
    if not cfg["import_channel_id"] or str(payload.channel_id) != str(cfg["import_channel_id"]):
        return
    imported = state.data.get("imported", {})
    if str(payload.message_id) in imported:
        state.queue_news_remove("m" + str(payload.message_id))
        imported.pop(str(payload.message_id), None)
        state.save()
        flush_inbox()

@client.event
async def on_raw_bulk_message_delete(payload: discord.RawBulkMessageDeleteEvent):
    if not cfg.get('invite_requests_channel_id') or str(payload.channel_id)!=str(cfg['invite_requests_channel_id']): return
    changed=False
    for mid in payload.message_ids:
        source='m'+str(mid); old=state.data.get('invite_sources',{}).get(source)
        if old: changed=state.queue_guild_invite(source,None,old['requester'],old['user'],old['posted']) or changed
    if changed: flush_inbox()


@tree.command(name="announce", description="Officers: post a guild announcement (also pops up in game)", guild=GUILD)
@app_commands.describe(title="Short title", message="The announcement (up to 400 characters)")
async def announce_cmd(interaction: discord.Interaction, title: app_commands.Range[str, 1, 60], message: app_commands.Range[str, 1, 400]):
    if not is_officer(interaction.user):
        await interaction.response.send_message(f"Only members with the **{cfg['officer_role']}** role can post announcements.", ephemeral=True)
        return
    e = state.queue_news(title, message, interaction.user.display_name)
    flush_inbox()
    shown = {"title": title, "text": message, "by": interaction.user.display_name}
    ch = client.get_channel(int(cfg["announce_channel_id"]))
    if ch is not None:
        msg = await ch.send(embed=news_embed(shown))
        state.data.setdefault("news_posted", {})["d-" + e["id"]] = {"message_id": msg.id, "u": 0}
        state.save()
    await interaction.response.send_message(
        "Posted. It pops up in game for everyone once an officer next logs in or types `/reload`.", ephemeral=True)


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------
class RejectModal(discord.ui.Modal, title="Reject request"):
    reason = discord.ui.TextInput(label="Reason (optional)", required=False, max_length=80)

    def __init__(self, rid: str):
        super().__init__()
        self.rid = rid

    async def on_submit(self, interaction: discord.Interaction):
        await apply_status(interaction, self.rid, "rejected", str(self.reason))


async def apply_status(interaction: discord.Interaction, rid: str, status: str, reason: str = ""):
    by = f"{interaction.user.display_name} (Discord)"
    state.queue_status(rid, status, by, reason)
    flush_inbox()
    gd = read_latest()
    r = dict((gd.requests.get(rid) if gd else None) or {})
    if not r:
        r = {"who": "?", "qty": "?", "item": None}
        for e in state.data["inbox"]:
            if e.get("kind") == "request" and "d-" + e["id"] == rid:
                r = {"who": e["who"], "qty": e["qty"], "item": e.get("item"), "itemName": e.get("itemName"),
                     "note": e.get("note"), "discord": e.get("discord")}
    r.update({"status": status, "by": by, "reason": reason})
    await interaction.response.edit_message(
        embed=request_embed(rid, r, gd, "Saved. It reaches the game at the next officer login or /reload."), view=None)
    state.set_posted(rid, interaction.message.id, status)


@client.event
async def on_interaction(interaction: discord.Interaction):
    if interaction.type != discord.InteractionType.component:
        return
    if await events.handle(interaction):return
    cid = (interaction.data or {}).get("custom_id", "")
    if not cid.startswith("epu:"):
        return
    _, action, rid = cid.split(":", 2)
    if not is_officer(interaction.user):
        await interaction.response.send_message(f"Only members with the **{cfg['officer_role']}** role can do that.", ephemeral=True)
        return
    if action == "approve":
        await apply_status(interaction, rid, "approved")
    elif action == "reject":
        await interaction.response.send_modal(RejectModal(rid))


# ---------------------------------------------------------------------------
# Linked characters, class/rank roles and the officer log
# ---------------------------------------------------------------------------
async def officer_log(lines: list[str]):
    if not lines:
        return
    for line in lines:
        log.info("Officer log: %s", line)
    cid = cfg.get("officer_log_channel_id")
    ch = client.get_channel(int(cid)) if cid else None
    if ch is None:
        return
    chunk = ""
    for line in lines[:60]:
        if len(chunk) + len(line) + 1 > 1900:
            await ch.send(chunk, allowed_mentions=discord.AllowedMentions.none())
            chunk = ""
        chunk += line + "\n"
    if chunk:
        await ch.send(chunk, allowed_mentions=discord.AllowedMentions.none())


def onboarding_done(name: str, note: str):
    state.data["inbox"].append({"id": "link-" + uuid.uuid4().hex, "kind": "checklist", "who": name,
                                "step": "discord", "done": True, "note": note, "t": int(time.time())})


def rejected_roster() -> dict:
    return {"lines": ["⚠️ Role sync paused: this snapshot lost over a third of the accepted guild roster. "
                      "Read a complete roster before retrying; confirmation cannot override this safety check."],
            "added": 0, "removed": 0, "held": True, "roster_held": True}


async def sync_links_roles(gd: core.GuildData, confirm: bool = False) -> dict:
    cur = lr.member_info(gd)
    if not lr.roster_trusted(state.data.get("roster_seen"), cur):
        result = rejected_roster()
        await officer_log(result["lines"])
        return result
    lines = []
    linked = lr.process_links(gd, state)
    for e in linked:
        if e["kind"] == "linked":
            onboarding_done(e["who"], "Discord linked with " + ("their code" if e["how"] == "code" else "a confirmed alt"))
    if any(e["kind"] == "linked" for e in linked):
        state.save(); flush_inbox()
    lines += [lr.event_line(e) for e in linked]
    # roster changes since the last save we read
    cur = lr.member_info(gd)
    stamp = gd.g.get("memberInfoAt")
    if cur and stamp != state.data.get("roster_seen_at"):
        events, ok = lr.roster_events(state.data.get("roster_seen"), cur, cfg["level_milestones"],
                                      state.data.setdefault("roster_left", {}))
        if ok:
            state.data["roster_seen"], state.data["roster_seen_at"] = cur, stamp
            lines += [lr.event_line(e) for e in events[:40]]
            if len(events) > 40:
                lines.append(f"…and {len(events) - 40} more roster changes.")
        state.save()
    result = await sync_roles(gd, confirm) if cfg["discord_roles"] and cur else {}
    lines += result.get("lines", [])
    await officer_log(lines)
    return result


DANGEROUS_PERMS = ("administrator", "manage_guild", "manage_roles", "manage_channels", "manage_webhooks",
                   "kick_members", "ban_members", "moderate_members", "manage_messages", "mention_everyone")


def adopt_problem(guild, role) -> str | None:
    """Why an existing role must not be taken over, or None if it's safe."""
    if role.name.lower() == str(cfg["officer_role"]).lower():
        return "it's your officer role"
    perms = getattr(role, "permissions", None)
    if perms is not None and any(getattr(perms, p, False) for p in DANGEROUS_PERMS):
        return "it has moderator permissions"
    if getattr(role, "managed", False):
        return "it belongs to another bot or integration"
    me = getattr(guild, "me", None)
    top = getattr(me, "top_role", None)
    if top is not None and getattr(role, "position", 0) >= getattr(top, "position", 0):
        return "it's above the bot's role (drag the bot's role higher in Server Settings > Roles)"
    return None


async def sync_roles(gd: core.GuildData, confirm: bool = False) -> dict:
    if not lr.roster_trusted(state.data.get("roster_seen"), lr.member_info(gd)):
        return rejected_roster()
    guild = client.get_guild(int(cfg["server_id"]))
    if guild is None:
        return {}
    migration_problem = lr.migrate_member_role(state, cfg["member_role"] or None)
    if migration_problem:
        return {"lines": ["⚠️ Role sync paused: " + migration_problem], "added": 0, "removed": 0, "held": True, "migration_held": True}
    desired = lr.desired_roles(gd, state, cfg["rank_roles"], cfg["class_roles"], cfg["member_role"] or None)
    managed = state.data.setdefault("managed_roles", {})
    holders = state.data.setdefault("role_holders", {})
    def role_safety():
        # Revalidate cached IDs too: a server admin may have changed permissions,
        # the officer role or role hierarchy since the last successful sync.
        return {key: adopt_problem(guild, role)
                for key, rid in managed.items()
                if (role := guild.get_role(int(rid))) is not None}

    requested_keys = set().union(*desired.values()) if desired else set()
    safety = role_safety()
    blocked = {key for key, problem in safety.items() if problem}
    sig = core.json.dumps([sorted((u, sorted(k)) for u, k in desired.items()), sorted(managed.items()),
                           sorted(holders.items()), sorted(safety.items())])
    if sig == state.data.get("roles_sig") and not confirm and requested_keys <= safety.keys():
        return {}
    out_lines, warned = [], set(state.data.setdefault("role_name_warned", []))
    created, reused = [], []
    for key in sorted(blocked):
        out_lines.append(f"⚠️ Left managed role **{guild.get_role(int(managed[key])).name}** alone because {safety[key]}. "
                         "No members were added to or removed from this role.")
    roles = {}
    for key in sorted(requested_keys):
        if key in blocked:
            continue
        role = guild.get_role(int(managed[key])) if key in managed else None
        if role is None:
            name = lr.role_name(key, gd)
            existing = discord.utils.get(guild.roles, name=name)
            if existing is not None:
                mode = str(cfg["adopt_existing_roles"]).lower()
                wanted = mode == "all" or (mode == "rank" and key.split(":", 1)[0] in ("rank", "member"))
                problem = adopt_problem(guild, existing) if wanted else None
                if wanted and not problem:
                    managed[key] = str(existing.id)
                    state.data["adopted_roles"] = sorted(set(state.data.get("adopted_roles", [])) | {key})
                    roles[key] = existing
                    reused.append(existing.name)
                    out_lines.append(f"\U0001F91D Using your existing **{name}** role. Linked members get or lose it as their rank changes; "
                                     "people who haven't linked keep whatever they have.")
                    continue
                if key not in warned:
                    why = f" because {problem}" if problem else ""
                    out_lines.append(f"⚠️ A role named **{name}** already exists and wasn't made by the bot, so I left it alone{why} "
                                     "and gave no one that role. Rename it, or remove the rank from `rank_roles`.")
                    warned.add(key)
                continue
            options = {}
            if key.startswith("class:") and (color := CLASS_ROLE_COLORS.get(key[6:])) is not None:
                options["color"] = discord.Color(color)
            role = await guild.create_role(name=name, mentionable=False, reason="EPU class/rank role", **options)
            managed[key] = str(role.id)
            created.append(role.name)
        roles[key] = role
    state.data["role_name_warned"] = sorted(warned)
    by_id = {str(r.id): k for k, r in roles.items()}
    for key, rid in managed.items():
        if rid not in by_id and guild.get_role(int(rid)) is not None:
            by_id[rid] = key
    current, people = {}, {}
    for uid in set(desired) | set(holders):
        try:
            m = guild.get_member(int(uid)) or await guild.fetch_member(int(uid))
        except discord.NotFound:
            holders.pop(uid, None)
            continue
        people[uid] = m
        current[uid] = {by_id[str(r.id)] for r in m.roles if str(r.id) in by_id}
    desired = {u: {k for k in ks if k in roles} for u, ks in desired.items() if u in people}
    adds, removes = lr.plan_changes(desired, current)
    # Keep unsafe roles and their holder bookkeeping untouched, even when a
    # key is no longer desired. Confirmation never bypasses this safety gate.
    removes = {uid: keys - blocked for uid, keys in removes.items() if keys - blocked}
    # Someone with no linked characters keeps roles that were yours to begin with.
    adopted = set(state.data.get("adopted_roles", []))
    for uid in list(removes):
        if not state.characters_for(int(uid)):
            removes[uid] = {k for k in removes[uid] if k not in adopted}
            if not removes[uid]:
                removes.pop(uid)
    held = bool(removes) and not confirm and lr.needs_confirmation(removes, len(desired))
    if held:
        if state.data.get("roles_held") != len(removes):
            out_lines.append(lr.event_line({"kind": "roles_held", "n": len(removes)}))
        state.data["roles_held"] = len(removes)
        removes = {}
    else:
        state.data.pop("roles_held", None)
    skipped_unsafe = False
    for changes, method in ((adds, "add_roles"), (removes, "remove_roles")):
        for uid, keys in changes.items():
            applied = set()
            for key in sorted(keys):
                # Member fetches and previous Discord writes yield to gateway
                # updates. Resolve the ID again immediately before EACH write.
                role = guild.get_role(int(managed[key])) if key in managed else None
                problem = adopt_problem(guild, role) if role is not None else "it no longer exists"
                if problem:
                    skipped_unsafe = True
                    if key not in blocked:
                        out_lines.append(f"⚠️ Stopped changing role **{getattr(role, 'name', key)}** because {problem}.")
                        blocked.add(key)
                    continue
                await getattr(people[uid], method)(role, reason="EPU linked characters")
                applied.add(key)
            changes[uid] = applied
    for uid in people:
        have = (current.get(uid, set()) | adds.get(uid, set())) - removes.get(uid, set())
        if have and state.characters_for(int(uid)):
            holders[uid] = sorted(have)
        else:
            holders.pop(uid, None)
    unresolved = requested_keys - roles.keys() - blocked
    if held or skipped_unsafe or unresolved or role_safety() != safety:
        # Never cache a safety state that was not used for this sync's plan.
        # Unmanaged same-name candidates can also change permissions/hierarchy;
        # retry them on the next sync instead of caching them out indefinitely.
        state.data.pop("roles_sig", None)
    else:
        state.data["roles_sig"] = core.json.dumps([sorted((u, sorted(k)) for u, k in lr.desired_roles(gd, state, cfg["rank_roles"], cfg["class_roles"], cfg["member_role"] or None).items()),
                                                   sorted(managed.items()), sorted(holders.items()), sorted(role_safety().items())])
    state.save()
    return {"lines": out_lines, "added": sum(map(len, adds.values())), "removed": sum(map(len, removes.values())),
            "held": held, "checked": len(people), "created": created, "adopted": reused,
            "skipped": bool(blocked or unresolved or skipped_unsafe)}


def role_change_summary(result: dict) -> str:
    parts = []
    if result.get("created"):
        parts.append("Created " + ", ".join(result["created"]) + ".")
    if result.get("adopted"):
        parts.append("Reused " + ", ".join(result["adopted"]) + ".")
    for key, verb in (("added", "Added"), ("removed", "Removed")):
        if count := result.get(key):
            noun = "assignment" if count == 1 else "assignments"
            parts.append(f"{verb} {count} role {noun}.")
    return " ".join(parts)


def describe_char(gd: core.GuildData | None, name: str) -> str:
    v = lr.member_info(gd).get(name) if gd else None
    if not v:
        return f"{name} (not in the guild roster)"
    return f"{name}: level {v.get('l', '?')} {v.get('cn') or v.get('c') or ''}, {v.get('r', '?')}".replace("  ", " ")


# ---------------------------------------------------------------------------
# Slash commands
# ---------------------------------------------------------------------------
async def member_autocomplete(interaction: discord.Interaction, current: str):
    gd = read_latest()
    cur = current.lower()
    names = [n for n in (gd.members if gd else []) if cur in n.lower()][:25]
    return [app_commands.Choice(name=n, value=n) for n in names]


async def my_chars_autocomplete(interaction: discord.Interaction, current: str):
    cur = current.lower()
    return [app_commands.Choice(name=c, value=c) for c in state.characters_for(interaction.user.id) if cur in c.lower()][:25]


@tree.command(name="unlink", description="Remove a character from your Discord account", guild=GUILD)
@app_commands.describe(character="One of your linked characters")
@app_commands.autocomplete(character=my_chars_autocomplete)
async def unlink_cmd(interaction: discord.Interaction, character: str):
    chars = state.unlink(interaction.user.id, character)
    left = ", ".join(chars) if chars else "none"
    await interaction.response.send_message(f"Unlinked {character}. Your characters now: {left}.", ephemeral=True)


@tree.command(name="link", description="Link your WoW characters to your Discord account", guild=GUILD)
@app_commands.describe(character="Optional: can't use the addon? Name a character and an officer approves it instead.")
@app_commands.autocomplete(character=member_autocomplete)
async def link_cmd(interaction: discord.Interaction, character: str | None = None):
    code = lr.show_code(lr.code_for(state, interaction.user.id))
    msg = (f"Your link code: **{code}**\n"
           f"In game, on any of your characters, type `/epu link {code}`. Every character on that WoW account then links "
           "itself when it logs in, and your confirmed EPU alts come along too. It shows up here after an officer's next "
           "save (usually within a day). Needs EPU 0.23 or newer. Keep the code to yourself.")
    if character:
        gd = read_latest()
        name, candidates = gd.resolve_member(character) if gd else (None, [])
        if name is None and candidates:
            await interaction.response.send_message(
                "More than one guild member has that first name: " + ", ".join(candidates) + ". Use your full name.", ephemeral=True)
            return
        if name is None:
            await interaction.response.send_message("No matching guild member. An officer must first save a current roster.", ephemeral=True)
            return
        try:
            state.request_link(interaction.user.id, name)
        except ValueError as e:
            await interaction.response.send_message(str(e), ephemeral=True)
            return
        msg += f"\n\nAlso asked an officer to approve **{name}** by hand (`/approve_link`), in case you can't use the code."
    await interaction.response.send_message(msg, ephemeral=True)


@tree.command(name="approve_link", description="Officers: verify and approve a pending character link", guild=GUILD)
@app_commands.autocomplete(character=member_autocomplete)
async def approve_link_cmd(interaction: discord.Interaction, user: discord.Member, character: str):
    if not is_officer(interaction.user):
        await interaction.response.send_message("Only officers can verify character links.", ephemeral=True)
        return
    gd = read_latest()
    name, _ = gd.resolve_member(character) if gd else (None, [])
    if not name:
        await interaction.response.send_message("Choose a character in the saved guild roster.", ephemeral=True)
        return
    try:
        state.approve_link(user.id, name, str(interaction.user.id))
    except ValueError as e:
        await interaction.response.send_message(str(e), ephemeral=True)
        return
    state.data["inbox"].append({"id": "link-" + core.uuid.uuid4().hex, "kind": "checklist", "who": name,
                                "step": "discord", "done": True, "note": "Discord identity verified by an officer", "t": int(core.time.time())})
    state.save()
    flush_inbox()
    await interaction.response.send_message(f"Verified **{name}** for {user.mention}. The onboarding step reaches the game after the next officer reload.", ephemeral=True)


@tree.command(name="revoke_link", description="Officers: revoke a character link", guild=GUILD)
async def revoke_link_cmd(interaction: discord.Interaction, user: discord.Member, character: str):
    if not is_officer(interaction.user):
        await interaction.response.send_message("Only officers can revoke someone else's link.", ephemeral=True)
        return
    state.unlink(user.id, character)
    await interaction.response.send_message("Character link revoked.", ephemeral=True)



async def item_autocomplete(interaction: discord.Interaction, current: str):
    gd = read_latest()
    cur = current.lower()
    rows=[r for r in (gd.requestable_items(state.data['inbox']) if gd else []) if cur in r['name'].lower()][:25]
    return [app_commands.Choice(name=(r['name']+f" — {r['count']} in bank, {r['available']} available"+(' · Out of stock' if r['count']==0 else ''))[:100],value=f"id:{r['id']}") for r in rows]


def load_items():
    try:
        log.info("Item list: %s", items_db.load(cfg["item_build_prefix"], cfg["item_csv_url"]))
    except Exception as e:
        log.warning("Couldn't load the full item list (%s). /request still works with items the guild has seen, "
                    "Wowhead links and item IDs. To fix it by hand, download ItemSparse as CSV for the newest "
                    "1.60.x build from https://wago.tools/db2/ItemSparse and save it here as items.csv.", e)


@tree.command(name="request", description="Ask the guild bank for an item", guild=GUILD)
@app_commands.describe(item="Choose a currently or previously stocked bank item", qty="How many; unavailable quantities wait for restock",
                       note="Anything the officers should know", character="Which of your characters to mail it to (default: your main)")
@app_commands.autocomplete(item=item_autocomplete, character=my_chars_autocomplete)
async def request_cmd(interaction: discord.Interaction, item: str, qty: app_commands.Range[int, 1, 1000] = 1,
                      note: str = "", character: str = ""):
    chars = state.characters_for(interaction.user.id)
    if not chars:
        await interaction.response.send_message("First tell me your character with `/link character:<name>`.", ephemeral=True)
        return
    who = chars[0]
    to = None
    if character:
        match = [c for c in chars if c.lower() == character.lower()]
        if not match:
            await interaction.response.send_message(
                f"{character} isn't linked to you. Your characters: {', '.join(chars)}. Add one with `/link`.", ephemeral=True)
            return
        to = match[0] if match[0] != who else None
    gd = read_latest()
    known = gd.bank_catalog() if gd else {}
    item_id, name = core.resolve_item(item, known)
    if item_id is None or item_id not in known:
        await interaction.response.send_message(
            "Choose an item the guild bank currently holds or a supply it has stocked before. Sold-out weapons and armor are hidden. If stock information is missing, ask an officer to sync and /reload.", ephemeral=True)
        return
    name = name or f"item {item_id}"
    held,asked,free=gd.bank_request_stock(item_id,state.data['inbox'])
    e = state.queue_request(who, item_id, name, int(qty), note, interaction.user.display_name, to)
    flush_inbox()
    rid = "d-" + e["id"]
    r = {"who": who, "item": item_id, "itemName": name, "qty": int(qty), "note": note,
         "discord": interaction.user.display_name, "status": "pending", "t":e['t'], **({"to": to} if to else {})}
    await interaction.response.send_message(
        f"Got it. Your request for {name} x{qty}{f' (mail to {to})' if to else ''} is queued and reaches the game at the next officer login or /reload. "
        +f"Latest snapshot: {held} in bank, {free} available after open requests. "
        +(f"Awaiting restock: {max(0,int(qty)-free)}." if int(qty)>free else ''),
        ephemeral=True)
    await post_or_edit(rid, r, gd, "Queued from Discord.")


async def craftable_autocomplete(interaction: discord.Interaction, current: str):
    gd = read_latest()
    cur = current.lower()
    hits = sorted((n, i) for i, n in (gd.craftable_items() if gd else {}).items() if cur in n.lower())[:25]
    return [app_commands.Choice(name=n[:100], value=f"id:{i}") for n, i in hits]


@tree.command(name="craft", description="Who in the guild can craft an item", guild=GUILD)
@app_commands.describe(item="Start typing a recipe or item name")
@app_commands.autocomplete(item=craftable_autocomplete)
async def craft_cmd(interaction: discord.Interaction, item: str):
    gd = read_latest()
    if gd is None:
        await interaction.response.send_message("I don't have the guild's data yet.", ephemeral=True)
        return
    item_id, name = core.resolve_item(item, gd.craftable_items() or gd.known_items())
    crafters = gd.crafters_for(item_id=item_id) if item_id else gd.crafters_for(spell=item)
    name = name or (gd.item_name(item_id) if item_id else item)
    if not crafters:
        await interaction.response.send_message(
            f"Nobody has shared a recipe for **{name}** yet. Crafters share theirs by opening their profession window in game.",
            ephemeral=True)
        return
    lines = [("\u2b50 " if c["designated"] else "") + f"**{c['who']}** ({c['prof']} {c['rank'] or '?'})"
             + (" \U0001F53C skill-up" if c.get("skillup") else "") for c in crafters[:15]]
    mats = gd.mats_for(crafters[0]["key"])
    if mats:
        lines.append("")
        lines.append("Materials: " + ", ".join(f"{gd.item_name(i)} x{n}" for i, n in mats))
    e = discord.Embed(title=f"Who can craft {name}", description="\n".join(lines), color=discord.Color.blurple())
    if item_id:
        e.url = f"{cfg['wowhead'].rstrip('/')}/item={item_id}"
    e.set_footer(text="\u2b50 = guild crafter. \U0001F53C = they'd get a skill point. Ask one in game from the Recipes page.")
    await interaction.response.send_message(embed=e)


@tree.command(name="needs", description="What the guild bank is short on", guild=GUILD)
async def needs_cmd(interaction: discord.Interaction):
    gd = read_latest()
    rows = [r for r in (gd.needs() if gd else []) if r["missing"] > 0]
    if not rows:
        await interaction.response.send_message("The guild bank isn't short on anything right now.", ephemeral=True)
        return
    lines = [f"**{r['name']}**: {r['have']}/{r['target']} ({r['missing']} needed){' (goal)' if r['kind'] == 'goal' else ''}" for r in rows[:20]]
    embed = discord.Embed(title="Guild bank needs", description="\n".join(lines), color=discord.Color.gold())
    embed.set_footer(text="Mail donations to the bank alt or deposit them in the guild bank. Thank you!")
    await interaction.response.send_message(embed=embed)


@tree.command(name="bank", description="Search what's in the guild bank and bank alts", guild=GUILD)
@app_commands.describe(search="Part of an item name")
async def bank_cmd(interaction: discord.Interaction, search: str):
    gd = read_latest()
    s = search.lower()
    rows = [r for r in (gd.requestable_items(state.data['inbox']) if gd else []) if s in r["name"].lower()]
    if not rows:
        await interaction.response.send_message(f"Nothing matching \"{search}\" in the bank.", ephemeral=True)
        return
    lines = [f"{r['name']}: {r['count']} in bank, {r['available']} available"+(' — Out of stock; requests wait for restock' if r['count']==0 else '') for r in rows[:25]]
    await interaction.response.send_message("\n".join(lines), ephemeral=True)


@tree.command(name="requests", description="Open guild bank requests", guild=GUILD)
async def requests_cmd(interaction: discord.Interaction):
    gd = read_latest()
    rows = [(rid, r) for rid, r in (gd.requests.items() if gd else []) if isinstance(r, dict) and core.status_of(r) in ("pending", "approved")]
    if not rows:
        await interaction.response.send_message("No open requests.", ephemeral=True)
        return
    rows.sort(key=lambda x: x[1].get("t", 0))
    lines = [f"{core.status_label(r).capitalize()}: **{gd.request_name(r)}** x{r.get('qty', 1)} for {gd.label(r.get('to') or r.get('who', '?'))}"
             + (f" (craft by {r['crafter']})" if core.is_craft(r) else "") for _, r in rows[:25]]
    await interaction.response.send_message("\n".join(lines), ephemeral=True)


# ---------------------------------------------------------------------------
def check_channel(cid) -> None:
    ch = client.get_channel(int(cid))
    if ch is None:
        log.error("I can't see channel %s. Either it's private and I haven't been added to it, or the ID is "
                  "from another server. (Right-click the channel > Copy Channel ID.)", cid)
        return
    perms = ch.permissions_for(ch.guild.me)
    needed = (("View Channel", perms.view_channel), ("Send Messages", perms.send_messages),
              ("Embed Links", perms.embed_links), ("Read Message History", perms.read_message_history),
              ("Manage Messages (to pin)", perms.manage_messages))
    missing = [name for name, ok in needed if not ok]
    if missing:
        log.warning("In #%s I'm missing: %s", ch.name, ", ".join(missing))
    else:
        log.info("Posting in #%s: permissions OK", ch.name)


@tree.command(name="whois", description="Who in Discord plays a WoW character, and their other characters", guild=GUILD)
@app_commands.autocomplete(character=member_autocomplete)
async def whois_cmd(interaction: discord.Interaction, character: str):
    gd = read_latest()
    name, _ = gd.resolve_member(character) if gd else (None, [])
    name = name or character
    uid = lr.owner_of(state, name)
    if not uid:
        main = gd.main_of(name) if gd else name
        extra = f" Their main is **{main}**." if main != name else ""
        await interaction.response.send_message(f"**{name}** isn't linked to a Discord account yet.{extra}", ephemeral=True)
        return
    chars = state.characters_for(int(uid))
    lines = [describe_char(gd, c) for c in chars]
    await interaction.response.send_message(f"**{name}** is <@{uid}>. Their characters:\n" + "\n".join("• " + l for l in lines),
                                            ephemeral=True, allowed_mentions=discord.AllowedMentions.none())


@tree.command(name="chars", description="List the WoW characters linked to a Discord member (you by default)", guild=GUILD)
async def chars_cmd(interaction: discord.Interaction, member: discord.Member | None = None):
    who = member or interaction.user
    chars = state.characters_for(who.id)
    if who.id == interaction.user.id:
        gd = read_latest()
        lines = [f"**Verified characters:** {', '.join(chars) or 'None yet.'}"]
        legacy = state.data.get("legacy_links", {}).get(str(who.id), [])
        legacy = [legacy] if isinstance(legacy, str) else legacy
        verified = {name.casefold() for name in chars}
        legacy = [name for name in legacy if name.casefold() not in verified]
        if legacy:
            lines.append("**Legacy characters awaiting verification:** " + ", ".join(legacy))
        if not chars or legacy:
            lines.append("Run `/link` here, enter `/epu link CODE` in WoW on the character, then `/reload`.")
        if not cfg["discord_roles"]:
            lines.append("Automatic Discord roles are turned off.")
        elif chars and (gd is None or not lr.member_info(gd)):
            lines.append("Waiting for a guild roster. Open it in WoW and `/reload`.")
        elif chars and gd:
            main = lr.main_for(gd, state, who.id)
            if main:
                lines.append(f"**Main:** {main}")
            if not lr.roster_trusted(state.data.get("roster_seen"), lr.member_info(gd)):
                lines.append("Role sync is paused until the bot sees a complete guild roster.")
            desired = lr.desired_roles(gd, state, cfg["rank_roles"], cfg["class_roles"], cfg["member_role"])
            managed = state.data.get("managed_roles", {})
            actual = {str(r.id) for r in getattr(who, "roles", [])}
            keys = sorted(desired.get(str(who.id), ()))
            assigned = [lr.role_name(k, gd) for k in keys if str(managed.get(k)) in actual]
            missing = [lr.role_name(k, gd) for k in keys if str(managed.get(k)) not in actual]
            if assigned:
                lines.append("**Assigned:** " + ", ".join(assigned))
            if missing:
                lines.append("**Expected but missing:** " + ", ".join(missing) + ". Ask an officer to check `/roles Status`.")
            if not keys:
                lines.append("No automatic roles expected from the current roster and role settings.")
        view = None
        if not chars or legacy:
            button = discord.ui.Button(label="Get a link code", style=discord.ButtonStyle.primary)
            async def get_code(click: discord.Interaction):
                await link_cmd.callback(click)
            button.callback = get_code
            view = discord.ui.View(timeout=180)
            view.add_item(button)
        await interaction.response.send_message("\n".join(lines)[:2000], ephemeral=True, view=view,
                                                allowed_mentions=discord.AllowedMentions.none())
        return
    if not chars:
        await interaction.response.send_message(f"No linked characters for {who.mention}.", ephemeral=True,
                                                allowed_mentions=discord.AllowedMentions.none())
        return
    gd = read_latest()
    main = lr.main_for(gd, state, who.id) if gd else chars[0]
    chars = [main] + [c for c in chars if c != main] if main in chars else chars
    lines = [("⭐ " if c == main else "• ") + describe_char(gd, c) for c in chars]
    await interaction.response.send_message(f"{who.mention}'s characters (⭐ main):\n" + "\n".join(lines), ephemeral=True,
                                            allowed_mentions=discord.AllowedMentions.none())


@tree.command(name="sync_health", description="Officers: check the WoW bridge, roster and bank snapshots", guild=GUILD)
async def sync_health_cmd(interaction: discord.Interaction):
    if not is_officer(interaction.user):
        await interaction.response.send_message("Only officers can view sync health.", ephemeral=True)
        return
    gd = read_latest()
    if gd is None:
        await interaction.response.send_message("Waiting for a WoW guild save. Log in and `/reload` on this PC.", ephemeral=True)
        return
    roster = lr.member_info(gd)
    stamp = gd.g.get("memberInfoAt")
    saved_at = int(latest_source_mtime or 0)
    lines = [f"**WoW save:** <t:{saved_at}:R>" if saved_at else "**WoW save:** waiting"]
    lines.append(f"**Guild roster:** {len(roster)} characters" + (f", captured <t:{int(stamp)}:R>" if stamp else ""))
    if not roster or not lr.roster_trusted(state.data.get("roster_seen"), roster):
        lines.append("Open the guild roster on a guild character and `/reload` to refresh it.")
    counts = pending_bridge_updates(gd)
    if counts:
        lines.append("**Waiting for WoW:** " + ", ".join(f"{k.replace('_', ' ')} × {n}" for k, n in sorted(counts.items())))
        lines.append("Log in or `/reload` on the bridge PC to import, then reload or log out to save the result.")
    else:
        lines.append("**Waiting for WoW:** none")
    lines.append("**Bank snapshots**")
    for name, snapshot in sorted(gd.bank.items()):
        if not isinstance(snapshot, dict) or snapshot.get("retired"):
            continue
        seen = snapshot.get("v")
        bank_at = snapshot.get("bankTime")
        line = f"• {name}: " + (f"snapshot <t:{int(seen)}:R>" if seen else "snapshot time unavailable")
        if bank_at:
            line += f", bank opened <t:{int(bank_at)}:R>"
        lines.append(line)
    lines.append("Open the guild bank or the bank alt's bank to refresh stock, then `/reload`.")
    await interaction.response.send_message("\n".join(lines)[:2000], ephemeral=True,
                                            allowed_mentions=discord.AllowedMentions.none())


@tree.command(name="main", description="Choose which of your linked characters is your main (sets your rank role)", guild=GUILD)
@app_commands.autocomplete(character=my_chars_autocomplete)
async def main_cmd(interaction: discord.Interaction, character: str):
    chars = state.characters_for(interaction.user.id)
    if character not in chars:
        await interaction.response.send_message("That isn't one of your linked characters. See `/chars`.", ephemeral=True)
        return
    state.data.setdefault("mains", {})[str(interaction.user.id)] = character
    state.save()
    await interaction.response.send_message(f"**{character}** is now your main in Discord (this overrides `/epu main` here). "
                                            "Roles update at the next refresh.", ephemeral=True)
    state.data.pop("roles_sig", None)


@tree.command(name="roles", description="Officers: class/rank role status, refresh now, or confirm a held removal", guild=GUILD)
@app_commands.choices(action=[app_commands.Choice(name="Status", value="status"), app_commands.Choice(name="Refresh now", value="sync"),
                              app_commands.Choice(name="Confirm held removals", value="confirm")])
async def roles_cmd(interaction: discord.Interaction, action: app_commands.Choice[str]):
    if not is_officer(interaction.user):
        await interaction.response.send_message("Only officers can manage roles.", ephemeral=True)
        return
    gd = read_latest()
    if action.value == "status":
        linked = sum(1 for c in state.data["links"].values() if c)
        held = state.data.get("roles_held")
        managed = ", ".join(f"<@&{r}>" for r in state.data.get("managed_roles", {}).values()) or "none yet"
        legacy_pending = sum(
            bool({c.casefold() for c in ([old] if isinstance(old, str) else old)}
                 - {c.casefold() for c in state.characters_for(uid)})
            for uid, old in state.data.get("legacy_links", {}).items()
        )
        extra = f"\nDiscord accounts with unverified legacy characters: **{legacy_pending}**."
        if cfg["discord_roles"] and interaction.guild and interaction.guild.me:
            if not interaction.guild.me.guild_permissions.manage_roles:
                extra += "\nThe bot needs Manage Roles to assign roles."
            else:
                blocked = []
                for role_id in state.data.get("managed_roles", {}).values():
                    role = interaction.guild.get_role(int(role_id))
                    if role and (problem := adopt_problem(interaction.guild, role)):
                        blocked.append(f"{role.name}: {problem}")
                if blocked:
                    extra += "\nBlocked roles: " + "; ".join(blocked)
        await interaction.response.send_message(
            (f"Linked members: **{linked}**. Roles I manage: {managed}.\nEveryone linked: {cfg['member_role'] or 'off'}; rank roles: {', '.join(cfg['rank_roles']) or 'off'}; "
             f"class roles: {'on' if cfg['class_roles'] else 'off'}." + extra
             + (f"\n⏸️ Holding back removals for **{held}** people; use Confirm if that's right." if held else ""))[:2000],
            ephemeral=True, allowed_mentions=discord.AllowedMentions.none())
        return
    if not cfg["discord_roles"]:
        await interaction.response.send_message("Automatic Discord roles are turned off.", ephemeral=True)
        return
    if gd is None:
        await interaction.response.send_message("No WoW guild save yet. Log into a guild character and /reload.", ephemeral=True)
        return
    if not lr.member_info(gd) and not state.data.get("roster_seen"):
        await interaction.response.send_message("No saved guild roster yet. Open the guild roster in WoW and /reload.", ephemeral=True)
        return
    await interaction.response.defer(ephemeral=True, thinking=True)
    state.data.pop("roles_sig", None)
    try:
        result = await sync_links_roles(gd, confirm=action.value == "confirm")
    except discord.Forbidden:
        await interaction.followup.send("Discord refused. Give the bot **Manage Roles** and drag its role above the class and rank roles "
                                        "(Server Settings > Roles).", ephemeral=True)
        return
    if result.get("roster_held") or result.get("migration_held"):
        await interaction.followup.send("\n".join(result["lines"]), ephemeral=True,
                                        allowed_mentions=discord.AllowedMentions.none())
        return
    message = role_change_summary(result)
    if result.get("held") or result.get("skipped"):
        message = message or "No role changes applied."
        if result.get("held"):
            message += " Removals are on hold. Review them before choosing Confirm held removals."
        if result.get("skipped"):
            message += " Some roles were skipped. Check the bot's role order and permissions."
    elif not message:
        checked = result.get("checked")
        if checked:
            noun = "member" if checked == 1 else "members"
            message = f"Roles are already up to date for {checked} linked {noun}."
        elif checked == 0:
            message = "No linked Discord members with roles to update."
        else:
            message = "Couldn't check Discord roles for this server."
        if last := state.data.get("last_automatic_role_changes"):
            message += f"\nLast automatic changes (<t:{last['at']}:R>): {last['summary']}"
    await interaction.followup.send(message[:2000], ephemeral=True, allowed_mentions=discord.AllowedMentions.none())


class SuggestView(discord.ui.View):
    def __init__(self, pairs):
        super().__init__(timeout=900)
        self.pairs = pairs

    @discord.ui.button(label="Link all of these", style=discord.ButtonStyle.success)
    async def link_all(self, interaction: discord.Interaction, button: discord.ui.Button):
        if not is_officer(interaction.user):
            await interaction.response.send_message("Only officers can approve links.", ephemeral=True)
            return
        out = []
        for uid, name in self.pairs:
            if lr.owner_of(state, name) is None:
                lr._link(state, uid, name, "nickname", out)
                onboarding_done(name, "Discord linked by nickname match, approved by an officer")
        state.save(); flush_inbox()
        button.disabled = True
        await interaction.response.edit_message(content=f"Linked {len(out)} member(s). Their alts and roles follow at the next refresh.", view=self)
        await officer_log([lr.event_line(e) for e in out])
        state.data.pop("roles_sig", None)


@tree.command(name="link_suggestions", description="Officers: link unlinked members whose Discord name matches a guild character", guild=GUILD)
async def link_suggestions_cmd(interaction: discord.Interaction):
    if not is_officer(interaction.user):
        await interaction.response.send_message("Only officers can approve links.", ephemeral=True)
        return
    if not cfg["members_intent"]:
        await interaction.response.send_message(
            "This needs the server member list. In the Discord Developer Portal > your bot > Bot, turn on **Server Members Intent**, "
            "then set `\"members_intent\": true` in config.json and restart the bot.", ephemeral=True)
        return
    gd = read_latest()
    guild = interaction.guild
    people = [(str(m.id), m.display_name) for m in guild.members if not m.bot] if guild else []
    pairs = lr.nickname_matches(gd, state, people) if gd else []
    if not pairs:
        await interaction.response.send_message("No unlinked members have a Discord name matching a guild character.", ephemeral=True)
        return
    shown = pairs[:40]
    text = "\n".join(f"• <@{u}> → **{n}**" for u, n in shown)
    more = f"\n…and {len(pairs) - 40} more after these." if len(pairs) > 40 else ""
    await interaction.response.send_message(f"Check these, then link them all at once:\n{text}{more}", view=SuggestView(shown),
                                            ephemeral=True, allowed_mentions=discord.AllowedMentions.none())


@client.event
async def on_ready():
    await tree.sync(guild=GUILD)
    path = sv_path()
    log.info("Logged in as %s. Watching %s", client.user, path or "(no EPUGuild SavedVariables yet - log in once with the addon)")
    adopt_legacy_inbox();queue_helper_whitelist();flush_inbox()
    for cid in dict.fromkeys([cfg["channel_id"], cfg["status_channel_id"]]):
        check_channel(cid)
    await ensure_help_post()
    await backfill_announcements()
    await backfill_ingame_chat()
    # Bank requests use actual stock history; a full-game download is no longer
    # needed for startup or autocomplete. Legacy item_db settings are harmless.
    if not release_loop.is_running():
        release_loop.start()
    if cfg["guild_needs_post"] and not guild_needs_loop.is_running():
        guild_needs_loop.start()
    if cfg["leveling_board_post"] and not leveling_board_loop.is_running():
        leveling_board_loop.start()
    poll.change_interval(seconds=cfg["poll_seconds"])
    if not poll.is_running():
        poll.start()


events=EventSync(cfg,state,client,read_latest,flush_inbox)
board=GroupBoard(cfg,state,client)

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    instance = self_update.InstanceLock(os.path.join(HERE, "bot.lock"))
    if not instance.acquire():
        print("The EPU bot is already running (another window, or the copy that starts at logon). "
              "Not starting a second one.", file=sys.stderr)
        sys.exit(self_update.ALREADY_RUNNING_CODE)
    try:
        client.run(cfg["token"], log_handler=None)
    except discord.errors.PrivilegedIntentsRequired:
        if cfg["members_intent"]:
            config_error("members_intent is on, but the bot's Server Members Intent is off. Developer Portal > your application > Bot > "
                         "Privileged Gateway Intents > turn on SERVER MEMBERS INTENT > Save. Or set members_intent to false.")
        config_error("To read announcement/invite-request messages the bot needs the Message Content Intent.\n"
                     "Discord Developer Portal > your application > Bot > Privileged Gateway Intents > turn on MESSAGE CONTENT INTENT > Save.\n"
                     "Or leave import_channel_id, invite_requests_channel_id and ingame_chat_channel blank to disable message imports.")
    finally:
        instance.release()
    if restart_requested:
        sys.exit(self_update.RESTART_CODE)

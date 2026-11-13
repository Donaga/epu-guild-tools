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
from event_sync import EventSync, KINDS as EVENT_KINDS, time_zone_choices

HERE = os.path.dirname(os.path.abspath(__file__))
log = logging.getLogger("epu")

STATUS_COLOR = {
    "pending": discord.Color.gold(),
    "approved": discord.Color.green(),
    "filled": discord.Color.dark_grey(),
    "rejected": discord.Color.red(),
    "cancelled": discord.Color.dark_grey(),
}


def load_config() -> dict:
    path = os.path.join(HERE, "config.json")
    if not os.path.exists(path):
        sys.exit("config.json is missing. Copy config.example.json to config.json and fill it in.")
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    if not cfg.get("token") or "PASTE" in cfg.get("token", ""):
        sys.exit("Put your bot token in config.json first (see README.md).")
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
    cfg.setdefault("import_days", 30)             # on startup, copy posts from this many days back
    cfg.setdefault("import_officers_only", False) # only copy posts by the officer role (announcement channels are usually locked anyway)
    cfg.setdefault("post_motd", True)             # mirror the in-game guild message of the day to Discord
    cfg.setdefault("discord_roles", True)         # give linked members class and rank roles (needs Manage Roles)
    cfg.setdefault("class_roles", True)
    cfg.setdefault("rank_roles", ["Veteran", "Member", "Initiate"])   # only these ranks; officer ranks stay manual
    cfg.setdefault("officer_log_channel_id", "")  # joins, leaves, rank changes, links (an officers-only channel)
    cfg.setdefault("level_milestones", [60])
    cfg.setdefault("members_intent", False)       # needed only for /link_suggestions (turn it on in the Developer Portal)
    cfg.setdefault("logo_url", f"https://raw.githubusercontent.com/{cfg['github_repo']}/main/media/epu-logo.png")
    cfg["status_channel_id"] = cfg.get("status_channel_id") or cfg["channel_id"]
    cfg["feed_channel_id"] = cfg.get("feed_channel_id") or cfg["channel_id"]
    cfg["announce_channel_id"] = cfg.get("announce_channel_id") or cfg["channel_id"]
    return cfg


cfg = load_config()
state = core.State(os.path.join(HERE, "state.json"))
intents = discord.Intents.default()
if cfg["import_channel_id"] or cfg["invite_requests_channel_id"]:
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


def flush_inbox():
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
        core.write_inbox(core.inbox_path(cfg["wow_path"]), entries)
    except (OSError,ValueError,KeyError,TypeError) as e:
        log.error("Couldn't write Inbox.lua (%s). Check folder permissions; see README.", e)


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


def waiting_for_reload(gd: core.GuildData) -> int:
    now = time.time()
    kinds = {'request', 'status', 'news', 'news_remove', 'checklist', 'guild_invite', 'event_create', 'event_response'}
    events_by_id = gd.g.get('guildEvents') or {}
    count = 0
    for entry in state.data['inbox']:
        kind = entry.get('kind')
        if kind not in kinds or entry['id'] in gd.inbox_done or entry.get('t', now) > now - 120:
            continue
        if kind == 'guild_invite' and now - entry['t'] >= 7 * 86400:
            continue
        if kind == 'event_create' and (entry['starts'] <= now or entry['who'] + '\x1f' + entry['id'] in events_by_id):
            continue
        if kind == 'event_response':
            event = events_by_id.get(entry.get('event'))
            if (event and (event.get('status') != 'scheduled' or event.get('ends', 0) <= now)) or now - entry['t'] >= 7 * 86400:
                continue
        count += 1
    return count


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
    global latest_release
    try:
        rel = await asyncio.to_thread(core.fetch_latest_release, cfg["github_repo"])
    except Exception as e:
        log.debug("Release check failed: %s", e)
        return
    if rel["draft"] or not rel["tag"]:
        return
    latest_release = rel
    seen = state.data.get("last_release")
    if seen == rel["tag"]:
        return
    state.data["last_release"] = rel["tag"]
    state.save()
    if seen is None or not announce or not cfg["announce_releases"]:
        return                          # first run: remember the current version without announcing it
    ch = channel()
    if ch is None:
        return
    e = download_embed(rel)
    e.title = f"EPU Guild Tools {rel['version']} is out"
    notes = rel["notes"][:900] + ("..." if len(rel["notes"]) > 900 else "")
    if notes:
        e.description = notes
    e.set_footer(text="CurseForge app: it shows up as an update once CurseForge approves it (usually within a day). "
                      "WowUp and the updater have it now. Then /reload in game.")
    try:
        await ch.send(embed=e)
    except Exception as ex:
        explain(ex, "announce the new release", cfg["channel_id"])


@tasks.loop(minutes=30)
async def release_loop():
    await check_release()


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
        await sync_links_roles(gd)
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
FEED_EMOJI = {"level": "\U0001F389", "mount": "\U0001F40E", "prof": "\U0001F528", "donation": "\U0001F4B0", "join": "\U0001F44B"}


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


@client.event
async def on_message(message: discord.Message):
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


async def sync_links_roles(gd: core.GuildData, confirm: bool = False) -> dict:
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


async def sync_roles(gd: core.GuildData, confirm: bool = False) -> dict:
    guild = client.get_guild(int(cfg["server_id"]))
    if guild is None:
        return {}
    desired = lr.desired_roles(gd, state, cfg["rank_roles"], cfg["class_roles"])
    managed = state.data.setdefault("managed_roles", {})
    holders = state.data.setdefault("role_holders", {})
    sig = core.json.dumps([sorted((u, sorted(k)) for u, k in desired.items()), sorted(managed.items()), sorted(holders.items())])
    if sig == state.data.get("roles_sig") and not confirm:
        return {}
    out_lines, warned = [], set(state.data.setdefault("role_name_warned", []))
    roles = {}
    for key in sorted(set().union(*desired.values()) if desired else set()):
        role = guild.get_role(int(managed[key])) if key in managed else None
        if role is None:
            name = lr.role_name(key, gd)
            if discord.utils.get(guild.roles, name=name) is not None:
                if key not in warned:      # never take over a role a person made
                    out_lines.append(f"⚠️ A role named **{name}** already exists and wasn't made by the bot, so I left it alone "
                                     "and gave no one that role. Rename it, or remove the rank from `rank_roles`.")
                    warned.add(key)
                continue
            role = await guild.create_role(name=name, mentionable=False, reason="EPU class/rank role")
            managed[key] = str(role.id)
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
    held = bool(removes) and not confirm and lr.needs_confirmation(removes, len(desired))
    if held:
        if state.data.get("roles_held") != len(removes):
            out_lines.append(lr.event_line({"kind": "roles_held", "n": len(removes)}))
        state.data["roles_held"] = len(removes)
        removes = {}
    else:
        state.data.pop("roles_held", None)
    for uid, keys in adds.items():
        await people[uid].add_roles(*[roles[k] for k in keys], reason="EPU linked characters")
    for uid, keys in removes.items():
        objs = [guild.get_role(int(managed[k])) for k in keys if k in managed]
        objs = [r for r in objs if r is not None]
        if objs:
            await people[uid].remove_roles(*objs, reason="EPU linked characters")
    for uid in people:
        have = (current.get(uid, set()) | adds.get(uid, set())) - removes.get(uid, set())
        if have:
            holders[uid] = sorted(have)
        else:
            holders.pop(uid, None)
    if not held:
        state.data["roles_sig"] = core.json.dumps([sorted((u, sorted(k)) for u, k in lr.desired_roles(gd, state, cfg["rank_roles"], cfg["class_roles"]).items()),
                                                   sorted(managed.items()), sorted(holders.items())])
    state.save()
    return {"lines": out_lines, "added": sum(map(len, adds.values())), "removed": sum(map(len, removes.values())), "held": held}


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
    if not chars:
        hint = " Use `/link` to get a code." if who == interaction.user else ""
        await interaction.response.send_message(f"No linked characters for {who.mention}.{hint}", ephemeral=True,
                                                allowed_mentions=discord.AllowedMentions.none())
        return
    gd = read_latest()
    main = lr.main_for(gd, state, who.id) if gd else chars[0]
    chars = [main] + [c for c in chars if c != main] if main in chars else chars
    lines = [("⭐ " if c == main else "• ") + describe_char(gd, c) for c in chars]
    await interaction.response.send_message(f"{who.mention}'s characters (⭐ main):\n" + "\n".join(lines), ephemeral=True,
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
    if action.value == "status" or gd is None:
        linked = sum(1 for c in state.data["links"].values() if c)
        held = state.data.get("roles_held")
        managed = ", ".join(f"<@&{r}>" for r in state.data.get("managed_roles", {}).values()) or "none yet"
        await interaction.response.send_message(
            f"Linked members: **{linked}**. Roles I manage: {managed}.\nRank roles: {', '.join(cfg['rank_roles']) or 'off'}; "
            f"class roles: {'on' if cfg['class_roles'] else 'off'}." + (f"\n⏸️ Holding back removals for **{held}** people; use Confirm if that's right." if held else ""),
            ephemeral=True, allowed_mentions=discord.AllowedMentions.none())
        return
    await interaction.response.defer(ephemeral=True, thinking=True)
    state.data.pop("roles_sig", None)
    try:
        result = await sync_links_roles(gd, confirm=action.value == "confirm")
    except discord.Forbidden:
        await interaction.followup.send("Discord refused. Give the bot **Manage Roles** and drag its role above the class and rank roles "
                                        "(Server Settings > Roles).", ephemeral=True)
        return
    await interaction.followup.send(f"Done: {result.get('added', 0)} role(s) given, {result.get('removed', 0)} removed."
                                    + (" Removals are still held; use Confirm." if result.get("held") else ""), ephemeral=True)


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
    queue_helper_whitelist();flush_inbox()
    for cid in dict.fromkeys([cfg["channel_id"], cfg["status_channel_id"]]):
        check_channel(cid)
    await ensure_help_post()
    await backfill_announcements()
    # Bank requests use actual stock history; a full-game download is no longer
    # needed for startup or autocomplete. Legacy item_db settings are harmless.
    if not release_loop.is_running():
        release_loop.start()
    poll.change_interval(seconds=cfg["poll_seconds"])
    if not poll.is_running():
        poll.start()


events=EventSync(cfg,state,client,read_latest,flush_inbox)

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        client.run(cfg["token"], log_handler=None)
    except discord.errors.PrivilegedIntentsRequired:
        if cfg["members_intent"]:
            sys.exit("members_intent is on, but the bot's Server Members Intent is off. Developer Portal > your application > Bot > "
                     "Privileged Gateway Intents > turn on SERVER MEMBERS INTENT > Save. Or set members_intent to false.")
        sys.exit("To read announcement/invite-request messages the bot needs the Message Content Intent.\n"
                 "Discord Developer Portal > your application > Bot > Privileged Gateway Intents > turn on MESSAGE CONTENT INTENT > Save.\n"
                 "Or leave import_channel_id and invite_requests_channel_id blank to disable message imports.")

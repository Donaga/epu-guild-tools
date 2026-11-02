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

import json
import logging
from datetime import datetime, timezone
import os
import sys

import discord
from discord import app_commands
from discord.ext import tasks

import epu_core as core

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
    cfg["status_channel_id"] = cfg.get("status_channel_id") or cfg["channel_id"]
    return cfg


cfg = load_config()
state = core.State(os.path.join(HERE, "state.json"))
intents = discord.Intents.default()
client = discord.Client(intents=intents)
tree = app_commands.CommandTree(client)
GUILD = discord.Object(id=int(cfg["server_id"]))

latest: core.GuildData | None = None
latest_mtime = 0.0


# ---------------------------------------------------------------------------
# File plumbing
# ---------------------------------------------------------------------------
def sv_path() -> str | None:
    paths = core.find_saved_variables(cfg["wow_path"])
    if cfg.get("account"):
        paths = [p for p in paths if os.sep + cfg["account"] + os.sep in p] or paths
    return paths[0] if paths else None


def read_latest(force=False) -> core.GuildData | None:
    global latest, latest_mtime
    path = sv_path()
    if not path:
        return latest
    m = os.path.getmtime(path)
    if force or m != latest_mtime or latest is None:
        try:
            latest = core.load_guild_data(path, cfg.get("guild_key"))
            latest_mtime = m
        except Exception:
            log.exception("Couldn't read %s (WoW may be mid-save); will retry", path)
    return latest


def flush_inbox():
    try:
        core.write_inbox(core.inbox_path(cfg["wow_path"]), state.data["inbox"])
    except OSError as e:
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
    name = r.get("itemName") or (gd.item_name(r.get("item")) if gd else f"item {r.get('item')}")
    e = discord.Embed(title=f"{name} x{r.get('qty', 1)}", color=STATUS_COLOR.get(st, discord.Color.blurple()))
    if r.get("item"):
        e.url = f"https://www.wowhead.com/item={r['item']}"
    who = r.get("who", "?")
    if r.get("discord"):
        who += f" ({r['discord']} on Discord)"
    e.add_field(name="Requested by", value=who, inline=True)
    e.add_field(name="Status", value=st.capitalize(), inline=True)
    if gd and r.get("item"):
        e.add_field(name="In bank", value=str(gd.bank_count(r["item"])), inline=True)
    if r.get("note"):
        e.add_field(name="Note", value=r["note"], inline=False)
    if st == "rejected" and r.get("reason"):
        e.add_field(name="Reason", value=r["reason"], inline=False)
    if r.get("by") and st != "pending":
        e.add_field(name="By", value=r["by"], inline=True)
    if note_extra:
        e.add_field(name="\u200b", value=note_extra, inline=False)
    e.set_footer(text=f"EPU request {rid}")
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
    view = request_view(rid, st)
    posted = state.posted(rid)
    if posted:
        try:
            msg = await ch.fetch_message(posted["message_id"])
            await msg.edit(embed=embed, view=view)
            state.set_posted(rid, msg.id, st)
            return
        except discord.NotFound:
            pass
    msg = await ch.send(embed=embed, view=view)
    state.set_posted(rid, msg.id, st)


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


def status_embed(gd: core.GuildData) -> discord.Embed:
    st = gd.status_summary()
    e = discord.Embed(title="Guild Bank Status", color=discord.Color.blurple())
    need_lines = []
    for n in st["needs"]:
        frac = n["have"] / n["target"]
        mark = "\U0001F534" if frac < 0.5 else ("\U0001F7E1" if frac < 1 else "\u2705")
        goal = " *(goal)*" if n["kind"] == "goal" else ""
        need_lines.append(f"{mark} **{n['name']}** {n['have']}/{n['target']}{goal}")
    e.add_field(name="Needs", value=_clip(need_lines) if need_lines else "No targets set.", inline=False)
    shop_lines = [f"{r['name']}: {r['buy']}" for r in st["shopping"][:15]]
    e.add_field(name="Shopping list", value=_clip(shop_lines) if shop_lines else "Nothing to buy.", inline=False)
    e.add_field(name="Gold", value=core.money_text(st["gold"]), inline=True)
    e.add_field(name="Requests", value=f"{st['requests']['pending']} pending, {st['requests']['approved']} approved", inline=True)
    if st["banks"]:
        e.add_field(name="Held by", value=", ".join(st["banks"]), inline=True)
    e.set_footer(text="\U0001F534 under half  \U0001F7E1 below target  \u2705 stocked. Updates when an officer /reloads or logs out.")
    if st["updated"]:
        e.timestamp = datetime.fromtimestamp(st["updated"], tz=timezone.utc)
    return e


async def update_status(gd: core.GuildData):
    if not cfg["status_post"]:
        return
    ch = client.get_channel(int(cfg["status_channel_id"]))
    if ch is None:
        log.error("Status channel %s not found", cfg["status_channel_id"])
        return
    embed = status_embed(gd)
    mid = state.data.get("status_message_id")
    if mid:
        try:
            msg = await ch.fetch_message(mid)
            await msg.edit(embed=embed)
            return
        except discord.NotFound:
            pass
    msg = await ch.send(embed=embed)
    state.data["status_message_id"] = msg.id
    state.save()
    try:
        await msg.pin()
    except discord.Forbidden:
        log.warning("Posted the status message but couldn't pin it; give the bot Manage Messages (Pin Messages) or pin it by hand.")


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
    gd = read_latest()
    if gd is None or latest_mtime == polled_mtime:
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
    if cfg["post_donations"] and changes["new_donations"]:
        ch = channel()
        for d in changes["new_donations"][:10]:
            what = f"{d.get('n', 1)}x {gd.item_name(d['item'])}" if d.get("item") else core.money_text(d.get("money"))
            if ch:
                await ch.send(f"Thanks **{d.get('who', '?')}** for donating {what} to the guild bank!")
    state.save()


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
# Slash commands
# ---------------------------------------------------------------------------
async def member_autocomplete(interaction: discord.Interaction, current: str):
    gd = read_latest()
    cur = current.lower()
    names = [n for n in (gd.members if gd else []) if cur in n.lower()][:25]
    return [app_commands.Choice(name=n, value=n) for n in names]


@tree.command(name="link", description="Link your Discord account to your WoW character", guild=GUILD)
@app_commands.describe(character="Your character's full name, e.g. Drie Stonefist")
@app_commands.autocomplete(character=member_autocomplete)
async def link_cmd(interaction: discord.Interaction, character: str):
    gd = read_latest()
    name, candidates = gd.resolve_member(character) if gd else (None, [])
    if name is None and candidates:
        await interaction.response.send_message(
            "More than one guild member has that first name: " + ", ".join(candidates) + ". Use your full name.", ephemeral=True)
        return
    if name is None:
        if gd and gd.members:
            await interaction.response.send_message(
                f"I can't find **{character}** in the guild roster. Pick your name from the list, or check the spelling.", ephemeral=True)
            return
        name = " ".join(w[:1].upper() + w[1:] for w in character.split())   # no roster saved yet
    state.link(interaction.user.id, name)
    await interaction.response.send_message(f"Linked you to **{name}**. Requests you make here will be under that name.", ephemeral=True)


async def item_autocomplete(interaction: discord.Interaction, current: str):
    gd = read_latest()
    known = gd.known_items() if gd else {}
    cur = current.lower()
    hits = sorted((name, i) for i, name in known.items() if cur in name.lower())[:25]
    return [app_commands.Choice(name=name[:100], value=f"id:{i}") for name, i in hits]


@tree.command(name="request", description="Ask the guild bank for an item", guild=GUILD)
@app_commands.describe(item="Start typing an item name, or paste a Wowhead link", qty="How many", note="Anything the officers should know")
@app_commands.autocomplete(item=item_autocomplete)
async def request_cmd(interaction: discord.Interaction, item: str, qty: app_commands.Range[int, 1, 1000] = 1, note: str = ""):
    who = state.character_for(interaction.user.id)
    if not who:
        await interaction.response.send_message("First tell me your character with `/link character:<name>`.", ephemeral=True)
        return
    gd = read_latest()
    known = gd.known_items() if gd else {}
    item_id, name = core.resolve_item(item, known)
    if item_id is None:
        await interaction.response.send_message(
            "I don't know that item yet. Pick one from the list, or paste its Wowhead link (or item ID).", ephemeral=True)
        return
    name = name or f"item {item_id}"
    e = state.queue_request(who, item_id, name, int(qty), note, interaction.user.display_name)
    flush_inbox()
    rid = "d-" + e["id"]
    r = {"who": who, "item": item_id, "itemName": name, "qty": int(qty), "note": note,
         "discord": interaction.user.display_name, "status": "pending"}
    await interaction.response.send_message(f"Got it. Your request for {name} x{qty} is queued and reaches the game at the next officer login or /reload.", ephemeral=True)
    await post_or_edit(rid, r, gd, "Queued from Discord.")


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
    rows = [r for r in (gd.bank_items() if gd else []) if s in r["name"].lower()]
    if not rows:
        await interaction.response.send_message(f"Nothing matching \"{search}\" in the bank.", ephemeral=True)
        return
    lines = [f"{r['name']}: {r['count']}" for r in rows[:25]]
    await interaction.response.send_message("\n".join(lines), ephemeral=True)


@tree.command(name="requests", description="Open guild bank requests", guild=GUILD)
async def requests_cmd(interaction: discord.Interaction):
    gd = read_latest()
    rows = [(rid, r) for rid, r in (gd.requests.items() if gd else []) if isinstance(r, dict) and core.status_of(r) in ("pending", "approved")]
    if not rows:
        await interaction.response.send_message("No open requests.", ephemeral=True)
        return
    rows.sort(key=lambda x: x[1].get("t", 0))
    lines = [f"{core.status_of(r).capitalize()}: **{gd.item_name(r.get('item'))}** x{r.get('qty', 1)} for {r.get('who', '?')}" for _, r in rows[:25]]
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


@client.event
async def on_ready():
    await tree.sync(guild=GUILD)
    path = sv_path()
    log.info("Logged in as %s. Watching %s", client.user, path or "(no EPUGuild SavedVariables yet - log in once with the addon)")
    flush_inbox()
    for cid in dict.fromkeys([cfg["channel_id"], cfg["status_channel_id"]]):
        check_channel(cid)
    poll.change_interval(seconds=cfg["poll_seconds"])
    if not poll.is_running():
        poll.start()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    client.run(cfg["token"], log_handler=None)

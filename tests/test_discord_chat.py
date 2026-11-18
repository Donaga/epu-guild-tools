"""Guild chat from the guild's linked Discord channel: the bot writes the last
day into Inbox.lua, and EPU adds what it missed at login."""
import sys, os, tempfile, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
from simcore import *
import epu_core as core

check("the channel is found by name despite its emoji", core.channel_matches("🖥️in-game-chat", "in-game-chat"))
check("other channels don't match", not core.channel_matches("guild-bank", "in-game-chat") and not core.channel_matches("x", ""))

now = time.time()
line = core.ingame_chat_line(123, now - 60, "Laurelin Feredis", "  Congrats!\nwell done ", ["Laurelin Feredis"], True, "E Pluribus Unum")
check("a message becomes one tidy chat line", line == {"id": "123", "t": int(now - 60), "who": "Laurelin Feredis", "msg": "Congrats! well done",
      "chars": ["Laurelin Feredis"], "game": True, "guild": "E Pluribus Unum"})
check("image-only messages are skipped", core.ingame_chat_line(1, now, "X", "   ") is None)
check("long messages are cut to what WoW allows", len(core.ingame_chat_line(1, now, "X", "a" * 900)["msg"]) == 255)

lines = {"1": core.ingame_chat_line(1, now - 90000, "Old", "too old", guild="E Pluribus Unum"), "2": line,
         "3": core.ingame_chat_line(3, now - 30, "Kothar", "woot", None, True, "E Pluribus Unum")}
out = core.ingame_chat_list(lines, now)
check("only the last day is kept, oldest first", [x["id"] for x in out] == ["123", "3"] and "1" not in lines)

d = tempfile.mkdtemp()
path = os.path.join(d, "Interface", "AddOns", "EPUGuild", "Inbox.lua")
os.makedirs(os.path.dirname(path))
core.write_inbox(path, [], out)
text = open(path, encoding="utf-8").read()
check("Inbox.lua carries the chat", "EPUGuildDiscordChat" in text and "EPUGuildInbox = {}" in text)
core.write_inbox(path, [])
check("without the channel, Inbox.lua is unchanged", "EPUGuildDiscordChat" not in open(path, encoding="utf-8").read())

clients["Chris Baker"] = Client("Chris Baker")
tick(20)
A = clients["Chris Baker"]
A.ex(text)
check("the game reads it", A.ev("#EPUGuildDiscordChat") == 2)
A.ex('__ns.ChatLog("guild")[1]={t=time()-60,who="Laurelin Feredis-Forever",msg="Congrats! well done"}')
A.ex('EPUGuildDiscordChat[1].t=time()-61; EPUGuildDiscordChat[2].t=time()-30')
check("EPU adds only the line it missed", A.ev("__ns.MergeDiscordChat()") == 1 and A.ev('#__ns.ChatLog("guild")') == 2)
A.ex('__fire("PLAYER_LOGIN")'); tick(40)
check("login runs the merge without adding twice", A.ev('#__ns.ChatLog("guild")') == 2)
print("Discord chat tests:", check.failed, "failed")
sys.exit(1 if check.failed else 0)

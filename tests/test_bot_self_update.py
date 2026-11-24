"""The Discord companion moves its git clone to each new release by itself, but
only by a fast-forward of a clean main, and goes back when the new version
won't install or load. start.bat's supervisor restarts it after an update or a
crash, and only one copy runs at a time."""
import asyncio
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

BOT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord")
sys.path.insert(0, BOT_DIR)
import self_update as su
import supervise

failed = 0


def check(name, ok):
    global failed
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok


def git(cwd, *args):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    assert p.returncode == 0, (args, p.stderr)
    return p.stdout.strip()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


root = tempfile.mkdtemp()
dev = os.path.join(root, "dev")            # where releases are made
origin = os.path.join(root, "origin.git")  # GitHub
clone = os.path.join(root, "clone")        # the PC that runs the bot
os.makedirs(dev)
git(dev, "init", "-q", "-b", "main")
git(dev, "config", "user.email", "t@example.com")
git(dev, "config", "user.name", "Test")
write(os.path.join(dev, ".gitignore"), "epu-discord/config.json\nepu-discord/state.json\n")
write(os.path.join(dev, "epu-discord", "bot.py"), "VERSION = '1'\n")
write(os.path.join(dev, "epu-discord", "requirements.txt"), "# none\n")
git(dev, "add", "-A")
git(dev, "commit", "-q", "-m", "one")
git(dev, "tag", "v1.0.0")
git(root, "clone", "-q", "--bare", dev, origin)
git(dev, "remote", "add", "origin", origin)
git(root, "clone", "-q", origin, clone)
git(clone, "config", "user.email", "t@example.com")
git(clone, "config", "user.name", "Test")
bot_dir = os.path.join(clone, "epu-discord")
write(os.path.join(bot_dir, "config.json"), '{"token": "secret"}\n')
write(os.path.join(bot_dir, "state.json"), '{"links": {}}\n')


def release(tag, files, message=None):
    for name, text in files.items():
        write(os.path.join(dev, "epu-discord", name), text)
    git(dev, "add", "-A")
    git(dev, "commit", "-q", "-m", message or tag)
    git(dev, "tag", tag)
    git(dev, "push", "-q", "origin", "main", tag)


def head():
    return git(clone, "rev-parse", "HEAD")


# --- Updating the clone ---------------------------------------------------------------------
r = su.update_to("v1.0.0", bot_dir)
check("a clone that has the release is current", r.status == "current")

release("v1.1.0", {"bot.py": "VERSION = '2'\n"})
r = su.update_to("v1.1.0", bot_dir)
check("a new release is fast-forwarded to", r.status == "updated" and read(os.path.join(bot_dir, "bot.py")) == "VERSION = '2'\n")
check("main is on the release commit", head() == git(dev, "rev-parse", "v1.1.0^{commit}")
      and git(clone, "symbolic-ref", "--short", "HEAD") == "main")
check("config.json and state.json are untouched", read(os.path.join(bot_dir, "config.json")) == '{"token": "secret"}\n'
      and read(os.path.join(bot_dir, "state.json")) == '{"links": {}}\n')
check("the requirements didn't change, so nothing was installed", "requirements" not in r.message)
check("updating again does nothing", su.update_to("v1.1.0", bot_dir).status == "current")

# Commits merged to main after a release don't count until they're released.
write(os.path.join(dev, "epu-discord", "bot.py"), "VERSION = 'unreleased'\n")
git(dev, "commit", "-q", "-am", "unreleased")
git(dev, "push", "-q", "origin", "main")
check("unreleased work on GitHub's main isn't pulled", su.update_to("v1.1.0", bot_dir).status == "current"
      and read(os.path.join(bot_dir, "bot.py")) == "VERSION = '2'\n")
release("v1.2.0", {"requirements.txt": "# still none\n"})
r = su.update_to("v1.2.0", bot_dir)
check("changed requirements are installed with the update", r.status == "updated" and "requirements" in r.message
      and read(os.path.join(bot_dir, "requirements.txt")) == "# still none\n")
check("the release brings what was merged before it", read(os.path.join(bot_dir, "bot.py")) == "VERSION = 'unreleased'\n")

# Local changes are never thrown away.
release("v1.3.0", {"bot.py": "VERSION = '3'\n"})
write(os.path.join(bot_dir, "bot.py"), "VERSION = 'my edit'\n")
before = head()
r = su.update_to("v1.3.0", bot_dir)
check("local changes: skipped, kept, retried later", r.status == "skipped" and r.retry and "local changes" in r.message
      and read(os.path.join(bot_dir, "bot.py")) == "VERSION = 'my edit'\n" and head() == before)
git(clone, "checkout", "-q", "--", "epu-discord/bot.py")
write(os.path.join(bot_dir, "notes.txt"), "an untracked file\n")
r = su.update_to("v1.3.0", bot_dir)
check("an untracked file doesn't block an update, and stays", r.status == "updated"
      and read(os.path.join(bot_dir, "notes.txt")) == "an untracked file\n")

# Local commits: no merge, no reset.
release("v1.4.0", {"bot.py": "VERSION = '4'\n"})
write(os.path.join(bot_dir, "mine.py"), "X = 1\n")
git(clone, "add", "-A")
git(clone, "commit", "-q", "-m", "my commit")
mine = head()
r = su.update_to("v1.4.0", bot_dir)
check("local commits the release lacks: skipped, left as they are", r.status == "skipped"
      and "fast-forward" in r.message and head() == mine)
git(clone, "reset", "-q", "--hard", "HEAD~1")

# Another branch, or a detached checkout.
git(clone, "checkout", "-q", "-b", "testing")
r = su.update_to("v1.4.0", bot_dir)
check("on another branch: skipped", r.status == "skipped" and "testing" in r.message)
git(clone, "checkout", "-q", "main")
check("bad tags aren't passed to git", su.update_to("main; rm -rf /", bot_dir).status == "skipped"
      and su.update_to("", bot_dir).status == "skipped")
r = su.update_to("v9.9.9", bot_dir)
check("a tag GitHub doesn't have: skipped", r.status == "skipped" and "fetch" in r.message)
zipdir = tempfile.mkdtemp()
check("a zip copy (not a clone) doesn't update itself", su.update_to("v1.4.0", zipdir).status == "skipped")

# A release that won't install or load goes back to the old version.
before = head()
release("v1.5.0", {"requirements.txt": "this is ===not a requirement\n"})
r = su.update_to("v1.5.0", bot_dir)
check("requirements that won't install: back to the old version", r.status == "failed" and not r.retry
      and head() == before and read(os.path.join(bot_dir, "requirements.txt")) == "# still none\n")
release("v1.6.0", {"requirements.txt": "# none again\n", "bot.py": "def broken(:\n"})
r = su.update_to("v1.6.0", bot_dir)
check("code that won't compile: back to the old version", r.status == "failed" and head() == before
      and read(os.path.join(bot_dir, "bot.py")) == "VERSION = '3'\n")
check("after a rollback the clone is clean and on main", git(clone, "status", "--porcelain", "--untracked-files=no") == ""
      and git(clone, "symbolic-ref", "--short", "HEAD") == "main")
release("v1.7.0", {"bot.py": "VERSION = '7'\n"})
check("the next good release goes in", su.update_to("v1.7.0", bot_dir).status == "updated"
      and read(os.path.join(bot_dir, "bot.py")) == "VERSION = '7'\n")

# --- The supervisor -------------------------------------------------------------------------
def run_codes(codes, durations=None):
    codes, said, waits, t = list(codes), [], [], [0.0]
    durations = list(durations or [1] * len(codes))

    def run(_cmd):
        t[0] += durations.pop(0)
        return codes.pop(0)
    out = supervise.supervise(["bot"], run=run, sleep=waits.append, clock=lambda: t[0], say=said.append)
    return out, waits, said, codes


out, waits, said, left = run_codes([su.RESTART_CODE, 0])
check("after an update it starts again at once", out == 0 and waits == [] and not left)
out, waits, said, left = run_codes([1, 1, 1, 1, 1, 1, 0])
check("crashes restart with growing waits, up to 5 minutes", out == 0 and waits == [10, 30, 60, 120, 300, 300])
out, waits, said, left = run_codes([1, 1, 1, 0], durations=[1, 1, 700, 1])
check("a bot that ran a while starts over at the short wait", waits == [10, 30, 10])
out, waits, said, left = run_codes([su.CONFIG_ERROR_CODE, 0])
check("config errors stop it rather than loop", out == su.CONFIG_ERROR_CODE and waits == [] and left == [0])
out, waits, said, left = run_codes([su.ALREADY_RUNNING_CODE, 0])
check("a second copy stops", out == su.ALREADY_RUNNING_CODE and left == [0] and "already running" in said[0])

# --- One copy at a time ---------------------------------------------------------------------
lock_path = os.path.join(tempfile.mkdtemp(), "bot.lock")
held = su.InstanceLock(lock_path)
check("the first copy gets the lock", held.acquire())
probe = ("import sys; sys.path.insert(0, sys.argv[1]); import self_update as su; "
         "sys.exit(0 if su.InstanceLock(sys.argv[2]).acquire() else 3)")
p = subprocess.run([sys.executable, "-c", probe, BOT_DIR, lock_path])
check("a second copy can't", p.returncode == 3)
held.release()
p = subprocess.run([sys.executable, "-c", probe, BOT_DIR, lock_path])
check("once the first stops, it can", p.returncode == 0)

# --- The bot's update check -----------------------------------------------------------------
cfgdir = tempfile.mkdtemp()
json.dump({"token": "x.y.z", "server_id": "1", "channel_id": "2", "wow_path": tempfile.mkdtemp()},
          open(os.path.join(cfgdir, "config.json"), "w"))
for f in ("bot.py", "epu_core.py", "shared_bridge.py"):
    shutil.copy(os.path.join(BOT_DIR, f), cfgdir)
sys.path.insert(0, cfgdir)
bot = importlib.import_module("bot")
check("auto_update defaults on", bot.cfg["auto_update"] is True)
calls, closed = [], []
rel = {"tag": "v2.0.0", "version": "2.0.0", "draft": False}


async def fake_close():
    closed.append(True)
bot.client.close = fake_close
bot.self_update.log_line = lambda text, bot_dir=None: None
outcome = {"status": "updated"}
bot.self_update.update_to = lambda tag: calls.append(tag) or su.Result(outcome["status"], "msg")

bot.latest_release = rel
os.environ.pop("EPU_SUPERVISED", None)
asyncio.run(bot.maybe_update())
check("not started by start.bat: no update", calls == [] and not bot.restart_requested)
os.environ["EPU_SUPERVISED"] = "1"
bot.cfg["auto_update"] = False
asyncio.run(bot.maybe_update())
check("auto_update false: no update", calls == [])
bot.cfg["auto_update"] = True
outcome["status"] = "skipped"
asyncio.run(bot.maybe_update())
asyncio.run(bot.maybe_update())
check("a skipped update is tried again and the bot keeps running", calls == ["v2.0.0", "v2.0.0"]
      and not bot.restart_requested and not closed)
outcome["status"] = "failed"
asyncio.run(bot.maybe_update())
asyncio.run(bot.maybe_update())
check("a failed release isn't tried again", calls == ["v2.0.0"] * 3 and bot.state.data.get("update_failed") == "v2.0.0")
bot.latest_release = {**rel, "tag": "v2.0.1"}
outcome["status"] = "updated"
asyncio.run(bot.maybe_update())
check("an update closes the bot to restart it", calls[-1] == "v2.0.1" and bot.restart_requested and closed == [True])

print("Bot self-update checks:", failed, "failed")
sys.exit(bool(failed))

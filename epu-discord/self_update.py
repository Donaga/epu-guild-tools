"""Keep the Discord companion on the newest release by itself.

When the bot runs from a git clone of the repo through start.bat, it looks at
GitHub's latest release on the same 30-minute check that announces releases.
If that release isn't in the clone yet, the clone is on main and has no local
changes, it:

  1. fetches the release tag and fast-forwards main to it (never a reset, a
     merge commit or a force; config.json, state.json and other ignored files
     are never touched),
  2. reinstalls requirements.txt into the bot's Python if it changed,
  3. checks that the new code compiles and that discord.py still imports,
  4. asks start.bat's supervisor to restart the bot (exit code RESTART_CODE).

If anything looks off (not a clone, another branch, local changes, local
commits the release doesn't have, git missing, no network, a failed install
or check), it changes nothing, or puts main back where it was, logs why, and
keeps running the current version. A release that failed once isn't tried
again; the next release is.

Nothing here posts to Discord. Each update and each problem is written to the
console and to updates.log next to bot.py.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass

RESTART_CODE = 75          # bot.py -> supervisor: new code is in place, start me again
ALREADY_RUNNING_CODE = 76  # another copy of the bot holds the lock; don't start a second one
CONFIG_ERROR_CODE = 78     # config.json needs fixing; restarting won't help

HERE = os.path.dirname(os.path.abspath(__file__))
TAG_RE = re.compile(r"^v?\d+(?:\.\d+){1,3}$")
GIT_TIMEOUT = 120
PIP_TIMEOUT = 900


@dataclass
class Result:
    status: str            # "current", "updated", "skipped" or "failed"
    message: str
    old: str = ""
    new: str = ""

    @property
    def retry(self) -> bool:
        """A skipped update is tried again next time; a failed one waits for a newer release."""
        return self.status == "skipped"


def _env() -> dict:
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"      # never wait for a password nobody will type
    env["GCM_INTERACTIVE"] = "never"      # nor for Git Credential Manager's window
    env.setdefault("GIT_SSH_COMMAND", "ssh -o BatchMode=yes")
    return env


class Git:
    def __init__(self, cwd: str):
        self.cwd = cwd

    def run(self, *args, timeout=GIT_TIMEOUT) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=self.cwd, env=_env(), capture_output=True,
                              text=True, timeout=timeout, stdin=subprocess.DEVNULL)

    def out(self, *args) -> str | None:
        """stdout of a git command, or None if it failed."""
        p = self.run(*args)
        return p.stdout.strip() if p.returncode == 0 else None

    def ok(self, *args) -> bool:
        return self.run(*args).returncode == 0


def _short(sha: str) -> str:
    return (sha or "")[:7]


def _err(p: subprocess.CompletedProcess) -> str:
    text = (p.stderr or p.stdout or "").strip().splitlines()
    return text[-1] if text else f"exit code {p.returncode}"


def check_code(bot_dir: str, python: str) -> str | None:
    """None if every .py next to bot.py compiles and discord.py imports; else what failed."""
    script = ("import os\n"
              "for name in sorted(os.listdir('.')):\n"
              "    if name.endswith('.py'):\n"
              "        with open(name, 'rb') as f:\n"
              "            compile(f.read(), name, 'exec')\n"
              "import discord\n")
    try:
        p = subprocess.run([python, "-c", script], cwd=bot_dir, capture_output=True, text=True,
                           timeout=GIT_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)
    return None if p.returncode == 0 else _err(p)


def install_requirements(bot_dir: str, python: str) -> str | None:
    """None once requirements.txt is installed into this Python; else what went wrong."""
    try:
        p = subprocess.run([python, "-m", "pip", "install", "--disable-pip-version-check", "-q",
                            "-r", "requirements.txt"], cwd=bot_dir, capture_output=True, text=True,
                           timeout=PIP_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)
    return None if p.returncode == 0 else _err(p)


def update_to(tag: str, bot_dir: str = HERE, python: str = sys.executable, branch: str = "main") -> Result:
    """Fast-forward the clone holding bot_dir to release `tag`, if that's safe."""
    if not tag or not TAG_RE.match(tag):
        return Result("skipped", f"the latest release's tag {tag!r} doesn't look like a version")
    git = Git(bot_dir)
    try:
        root = git.out("rev-parse", "--show-toplevel")
    except FileNotFoundError:
        return Result("skipped", "git isn't installed or isn't on PATH")
    except subprocess.TimeoutExpired:
        return Result("skipped", "git didn't answer")
    if not root:
        return Result("skipped", "the bot isn't running from a git clone (a zip copy can't update itself)")
    try:
        return _update(git, root, tag, bot_dir, python, branch)
    except subprocess.TimeoutExpired:
        return Result("skipped", "git took too long (no network?)")


def _update(git: Git, root: str, tag: str, bot_dir: str, python: str, branch: str) -> Result:
    on = git.out("symbolic-ref", "--short", "-q", "HEAD")
    if on != branch:
        return Result("skipped", f"the clone is on {on or 'a detached commit'}, not {branch}")
    head = git.out("rev-parse", "HEAD") or ""
    fetched = git.run("fetch", "--quiet", "--no-tags", "origin", f"+refs/tags/{tag}:refs/tags/{tag}")
    if fetched.returncode != 0:
        return Result("skipped", f"couldn't fetch {tag} from GitHub: {_err(fetched)}", head)
    target = git.out("rev-parse", "--verify", "-q", f"refs/tags/{tag}^{{commit}}")
    if not target:
        return Result("skipped", f"{tag} isn't a commit", head)
    if git.ok("merge-base", "--is-ancestor", target, "HEAD"):
        return Result("current", f"already has {tag}", head, head)
    if git.out("status", "--porcelain", "--untracked-files=no"):
        return Result("skipped", "the clone has local changes; commit or undo them and it updates next time", head)
    if not git.ok("merge-base", "--is-ancestor", "HEAD", target):
        return Result("skipped", f"{branch} has commits {tag} doesn't, so it can't fast-forward", head)

    rel = os.path.relpath(os.path.join(bot_dir, "requirements.txt"), root).replace(os.sep, "/")
    req_before = git.out("show", f"HEAD:{rel}")
    req_after = git.out("show", f"{target}:{rel}")
    reqs_changed = req_before != req_after
    merged = git.run("merge", "--ff-only", "--quiet", target)
    if merged.returncode != 0:
        return Result("skipped", f"git couldn't fast-forward to {tag}: {_err(merged)}", head)

    def roll_back(why: str) -> Result:
        undone = git.run("reset", "--keep", head)
        if reqs_changed:
            install_requirements(bot_dir, python)    # best effort: back to the old packages
        note = "" if undone.returncode == 0 else f" Putting {branch} back failed too: {_err(undone)}"
        return Result("failed", f"{why}; went back to {_short(head)} and kept running.{note}", head, target)

    if reqs_changed:
        problem = install_requirements(bot_dir, python)
        if problem:
            return roll_back(f"installing the new requirements failed ({problem})")
    problem = check_code(bot_dir, python)
    if problem:
        return roll_back(f"the new code didn't pass its check ({problem})")
    extra = " and its requirements" if reqs_changed else ""
    return Result("updated", f"updated to {tag}{extra} ({_short(head)} -> {_short(target)})", head, target)


def log_line(text: str, bot_dir: str = HERE) -> None:
    """Append one dated line to updates.log (ignored by git)."""
    try:
        with open(os.path.join(bot_dir, "updates.log"), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + text + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# One copy of the bot at a time
# ---------------------------------------------------------------------------
class InstanceLock:
    """An OS file lock on bot.lock. Two bots on one config would post everything twice,
    so a second copy (a double-clicked start.bat while the autostart one runs) stops."""

    def __init__(self, path: str):
        self.path = path
        self.handle = None

    def acquire(self) -> bool:
        handle = open(self.path, "a+")
        try:
            if os.name == "nt":
                import msvcrt
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return False
        self.handle = handle
        return True

    def release(self) -> None:
        if self.handle is None:
            return
        try:
            if os.name == "nt":
                import msvcrt
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        self.handle.close()
        self.handle = None

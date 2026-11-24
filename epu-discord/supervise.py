"""Keeps the Discord companion running. start.bat runs this instead of bot.py.

  * After the bot updates itself (exit code 75) it starts again straight away,
    on the new code.
  * If the bot crashes, it waits a little (10 seconds, growing to 5 minutes
    if it keeps crashing) and starts it again.
  * It stops when the bot exits normally, when config.json needs fixing
    (exit code 78) or when another copy of the bot is already running (76).

Close the window, or press Ctrl+C, to stop the bot.
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

from self_update import ALREADY_RUNNING_CODE, CONFIG_ERROR_CODE, RESTART_CODE

HERE = os.path.dirname(os.path.abspath(__file__))
CRASH_DELAYS = [10, 30, 60, 120, 300]
STEADY_SECONDS = 600       # a bot that ran this long before crashing starts over at the shortest wait


def supervise(cmd, run=None, sleep=time.sleep, clock=time.monotonic, say=print, max_starts=None) -> int:
    """Run cmd until it exits for good; return the code to exit with."""
    env = {**os.environ, "EPU_SUPERVISED": "1"}
    if run is None:
        def run(c):
            return subprocess.run(c, cwd=HERE, env=env).returncode
    crashes, starts = 0, 0
    while max_starts is None or starts < max_starts:
        starts += 1
        began = clock()
        code = run(cmd)
        if code == RESTART_CODE:
            say("EPU bot: starting the updated version.")
            crashes = 0
            continue
        if code == 0:
            say("EPU bot stopped.")
            return 0
        if code == ALREADY_RUNNING_CODE:
            say("EPU bot is already running in another window, so this one won't start a second copy.")
            return code
        if code == CONFIG_ERROR_CODE:
            say("EPU bot can't start until config.json is fixed (see the message above). Fix it, then run start.bat again.")
            return code
        if clock() - began >= STEADY_SECONDS:
            crashes = 0
        wait = CRASH_DELAYS[min(crashes, len(CRASH_DELAYS) - 1)]
        crashes += 1
        say(f"EPU bot stopped unexpectedly (exit code {code}). Starting it again in {wait} seconds; "
            "close this window to stop it.")
        sleep(wait)
    return 1


def main() -> int:
    try:
        return supervise([sys.executable, os.path.join(HERE, "bot.py")])
    except KeyboardInterrupt:
        print("EPU bot stopped.")
        return 0


if __name__ == "__main__":
    sys.exit(main())

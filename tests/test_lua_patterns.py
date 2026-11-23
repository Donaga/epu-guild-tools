"""Lua mistakes that look right and fail quietly in game.

`local a, b = f and f()` keeps only f's first return value, so b is always
nil. 0.30.x used it for the Hearthstone cooldown, item sell prices, class
colors and mail senders, and none of them ever showed.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "EPUGuild")
failed = 0
pat = re.compile(r'^\s*local\s+\w+\s*,[\w\s,]*=\s*[\w.]+\s+and\s+[\w.:]+\(.*\)\s*$')
hits = []
for path in sorted(glob.glob(os.path.join(ADDON, "*.lua"))):
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if pat.match(line):
            hits.append(f"{os.path.basename(path)}:{n}")
ok = not hits
print(("PASS " if ok else "FAIL ") + "no multi-value assignment from `f and f()` " + ", ".join(hits))
failed += not ok
# The release job adds one X-CurseForge-Version line to the zip's TOC, and
# Core.lua trusts it to mean "a published build". Copies of the line kept in
# the repo stack up in every release and can hide the real one.
toc = open(os.path.join(ADDON, "EPUGuild.toc"), encoding="utf-8").read()
ok = "X-CurseForge-Version" not in toc
print(("PASS " if ok else "FAIL ") + "the repo TOC carries no X-CurseForge-Version line")
failed += not ok
print("Lua pattern checks:", failed, "failed")
sys.exit(bool(failed))

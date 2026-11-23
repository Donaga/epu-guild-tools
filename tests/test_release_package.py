"""What a release ships. The Release workflow builds the addon zip from the repo,
stamps the version into its TOC, and runs tools/check_addon_zip.py on the zip
for GitHub and WowUp and on the one for CurseForge. This builds the same zip
the same way and checks it, plus the zips the checker must refuse: one with the
bot's live inbox data, one with the EPUGuild_Inbox folder, one missing a file
the TOC loads."""
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_addon_zip as checker

failed = 0


def check(name, ok, detail=""):
    global failed
    print(("PASS " if ok else "FAIL ") + name + (f" ({detail})" if detail and not ok else ""))
    failed += not ok


toc_text = (ROOT / "EPUGuild" / "EPUGuild.toc").read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc_text, re.M).group(1)


def build(path, stamp=True, extra=None, drop=None, inbox=None):
    """Zip the EPUGuild folder like `zip -r ... EPUGuild` after the workflow's sed lines."""
    toc = toc_text
    if stamp:
        toc = re.sub(r"^(## Version: .*)$", rf"\1\n## X-CurseForge-Version: {version}", toc, count=1, flags=re.M)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((ROOT / "EPUGuild").rglob("*")):
            if not f.is_file():
                continue
            rel = f.relative_to(ROOT).as_posix()
            if rel == drop:
                continue
            if rel == "EPUGuild/EPUGuild.toc":
                z.writestr(rel, toc)
            elif rel == "EPUGuild/Inbox.lua" and inbox is not None:
                z.writestr(rel, inbox)
            else:
                z.write(f, rel)
        for name, text in (extra or {}).items():
            z.writestr(name, text)


with tempfile.TemporaryDirectory() as tmp:
    good = os.path.join(tmp, f"EPUGuild-{version}.zip")
    build(good)
    errors, names = checker.problems(good, version)
    check("the release zip passes the package check", not errors, "; ".join(errors))
    for f in ("NeededMats.lua", "NeededMatsUI.lua", "NeededMatsBank.lua", "WidgetPool.lua", "Inbox.lua",
              "Libs/HereBeDragons-2.0.lua", "Media/logo.tga"):
        check(f"the release zip ships EPUGuild/{f}", f"EPUGuild/{f}" in names)
    check("nothing of EPUGuild_Inbox is in the release zip", not any("EPUGuild_Inbox" in n for n in names))
    proc = subprocess.run([sys.executable, str(ROOT / "tools" / "check_addon_zip.py"), good, "v" + version],
                          capture_output=True, text=True)
    check("the checker script exits 0 on the release zip (tag with a v works)", proc.returncode == 0, proc.stdout + proc.stderr)

    live = os.path.join(tmp, "live.zip")
    build(live, inbox='EPUGuildInbox = {\n  {id="d1", kind="approve"},\n}\n')
    check("a zip carrying queued Discord updates in Inbox.lua is refused",
          any("Inbox.lua" in e for e in checker.problems(live, version)[0]))
    withdrop = os.path.join(tmp, "drop.zip")
    build(withdrop, extra={"EPUGuild_Inbox/EPUGuild_Inbox.toc": "## Interface: 16001\nInbox.lua\n",
                           "EPUGuild_Inbox/Inbox.lua": "EPUGuildInboxDrop = {}\n"})
    check("a zip carrying the EPUGuild_Inbox addon is refused",
          any("Discord inbox addon" in e for e in checker.problems(withdrop, version)[0]))
    missing = os.path.join(tmp, "missing.zip")
    build(missing, drop="EPUGuild/NeededMatsBank.lua")
    check("a zip missing a file the TOC loads is refused",
          any("NeededMatsBank.lua" in e for e in checker.problems(missing, version)[0]))
    unstamped = os.path.join(tmp, "unstamped.zip")
    build(unstamped, stamp=False)
    check("a zip without the X-CurseForge-Version stamp is refused",
          any("X-CurseForge-Version" in e for e in checker.problems(unstamped, version)[0]))

check("an Inbox.lua stub with comments still counts as empty",
      checker.inbox_is_stub((ROOT / "EPUGuild" / "Inbox.lua").read_text(encoding="utf-8")))

release = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
check("the Release workflow checks the GitHub/WowUp zip before attaching it",
      'check_addon_zip.py "dist/EPUGuild-${VERSION}.zip"' in release
      and release.index('check_addon_zip.py "dist/EPUGuild-') < release.index("softprops/action-gh-release"))
check("the Release workflow checks the CurseForge zip before uploading it",
      'check_addon_zip.py "$CF_ZIP"' in release
      and release.index('check_addon_zip.py "$CF_ZIP"') < release.index("curseforge_upload.py"))

changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
check(f"CHANGELOG has a section for the TOC version {version}, so CurseForge gets its notes",
      re.search(rf"^## {re.escape(version)}\s*$", changelog, re.M) is not None)

print("Release package checks:", failed, "failed")
sys.exit(bool(failed))

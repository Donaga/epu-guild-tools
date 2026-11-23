"""Check a built EPU addon zip before it's published (called by the Release workflow).

    python tools/check_addon_zip.py dist/EPUGuild-1.2.3.zip 1.2.3

Fails (non-zero exit) unless the zip:
  - holds only the EPUGuild folder, and nothing of EPUGuild_Inbox, the Discord
    companion's own addon that keeps the bot's live inbox data
  - ships Inbox.lua as the empty stub, never anyone's queued Discord updates
  - contains every file the TOC and Libs/Libraries.xml load
  - carries Version and exactly one X-CurseForge-Version line, both = version
Prints what the zip holds, by folder.
"""
import collections
import posixpath
import re
import sys
import zipfile

ADDON = "EPUGuild"
INBOX_ADDON = "EPUGuild_Inbox"


def inbox_is_stub(text: str) -> bool:
    """Only comments, blank lines and `EPUGuildInbox = {}`."""
    code = [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.strip().startswith("--")]
    return code == ["EPUGuildInbox = {}"]


def problems(zip_path: str, version: str) -> tuple[list[str], list[str]]:
    errors = []
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        files = set(names)
        for n in names:
            top = n.split("/", 1)[0]
            if top == INBOX_ADDON or INBOX_ADDON + "/" in n or n.endswith(INBOX_ADDON + ".toc"):
                errors.append(f"{n}: the Discord inbox addon must never ship in an EPU zip")
            elif top != ADDON:
                errors.append(f"{n}: outside the {ADDON} folder")
            if "__pycache__" in n or n.endswith((".pyc", ".tmp")):
                errors.append(f"{n}: build leftover")
        toc_name = f"{ADDON}/{ADDON}.toc"
        if toc_name not in files:
            return [f"{toc_name} is missing"], names
        toc = z.read(toc_name).decode("utf-8")
        inbox = f"{ADDON}/Inbox.lua"
        if inbox not in files:
            errors.append(f"{inbox} is missing (older companions expect the empty stub)")
        elif not inbox_is_stub(z.read(inbox).decode("utf-8")):
            errors.append(f"{inbox} holds queued Discord updates; it must be the empty stub")
        versions = re.findall(r"^## Version:\s*(\S+)\s*$", toc, re.M)
        if versions != [version]:
            errors.append(f"TOC Version is {versions or 'missing'}, expected {version}")
        cf = re.findall(r"^## X-CurseForge-Version:\s*(\S+)\s*$", toc, re.M)
        if cf != [version]:
            errors.append(f"TOC X-CurseForge-Version lines are {cf}, expected exactly one {version}")
        loaded = []
        for line in toc.splitlines():
            entry = line.strip()
            if entry and not entry.startswith("#"):
                loaded.append(posixpath.normpath(f"{ADDON}/{entry.replace(chr(92), '/')}"))
        for xml in [e for e in loaded if e.endswith(".xml") and e in files]:
            base = posixpath.dirname(xml)
            for ref in re.findall(r'file="([^"]+)"', z.read(xml).decode("utf-8")):
                loaded.append(posixpath.normpath(f"{base}/{ref.replace(chr(92), '/')}"))
        for entry in loaded:
            if entry not in files:
                errors.append(f"{entry}: loaded by the addon but missing from the zip")
    return errors, names


def main():
    zip_path, version = sys.argv[1], sys.argv[2].lstrip("v")
    errors, names = problems(zip_path, version)
    by_dir = collections.Counter(posixpath.dirname(n) or "." for n in names)
    print(f"{zip_path}: {len(names)} files")
    for d in sorted(by_dir):
        print(f"  {d}/  {by_dir[d]} files")
    for e in errors:
        print("FAIL", e)
    if errors:
        sys.exit(f"{len(errors)} problem(s) in {zip_path}")
    print("OK: only EPUGuild, empty Inbox.lua stub, every loaded file present, version", version)


if __name__ == "__main__":
    main()

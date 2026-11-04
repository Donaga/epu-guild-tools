"""Upload a built addon zip to CurseForge (called by the Release workflow).

Needs:
  CF_API_KEY             - an API token from https://authors.curseforge.com (account > API tokens)
  CURSEFORGE_PROJECT_ID  - the numeric Project ID from the project's page sidebar
Usage: python tools/curseforge_upload.py dist/EPUGuild-1.2.3.zip 1.2.3 CHANGELOG.md
"""
import json, os, re, sys, urllib.request, uuid

API = "https://wow.curseforge.com/api"


def get(path, token):
    req = urllib.request.Request(API + path, headers={"X-Api-Token": token, "User-Agent": "epu-guild-tools-release"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def forever_versions(token):
    """CurseForge game-version ids for WoW: Forever (newest first)."""
    types = get("/game/version-types", token)
    ids = [t["id"] for t in types if "forever" in (t.get("slug", "") + " " + t.get("name", "")).lower()]
    if not ids:
        names = ", ".join(sorted(f"{t.get('name')} ({t.get('slug')})" for t in types))
        sys.exit(f"Couldn't find a WoW: Forever game version on CurseForge. Version types it offers: {names}")
    versions = [v for v in get("/game/versions", token) if v.get("gameVersionTypeID") in ids]
    versions.sort(key=lambda v: v["id"], reverse=True)
    return versions


def changelog_for(path, version):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return f"Version {version}"
    m = re.search(rf"^## {re.escape(version)}\s*$(.*?)(?=^## |\Z)", text, re.S | re.M)
    return (m.group(1).strip() if m else "") or f"Version {version}"


def main():
    zip_path, version = sys.argv[1], sys.argv[2]
    changelog_path = sys.argv[3] if len(sys.argv) > 3 else "CHANGELOG.md"
    token, project = os.environ.get("CF_API_KEY"), os.environ.get("CURSEFORGE_PROJECT_ID")
    if not token or not project:
        print("CurseForge upload skipped (set the CF_API_KEY secret and CURSEFORGE_PROJECT_ID variable to turn it on).")
        return
    versions = forever_versions(token)
    print("Uploading for CurseForge game version:", versions[0].get("name"), versions[0]["id"])
    meta = {"changelog": changelog_for(changelog_path, version), "changelogType": "markdown",
            "displayName": f"EPU Guild Tools {version}", "gameVersions": [versions[0]["id"]], "releaseType": "release"}
    boundary = uuid.uuid4().hex
    with open(zip_path, "rb") as f:
        data = f.read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n{json.dumps(meta)}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{os.path.basename(zip_path)}\"\r\n"
            f"Content-Type: application/zip\r\n\r\n").encode() + data + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{API}/projects/{project}/upload-file", data=body, method="POST",
                                 headers={"X-Api-Token": token, "Content-Type": f"multipart/form-data; boundary={boundary}",
                                          "User-Agent": "epu-guild-tools-release"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            print("Uploaded to CurseForge:", r.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"CurseForge upload failed ({e.code}): {e.read().decode()[:500]}")


if __name__ == "__main__":
    main()

"""Full item list (ItemSparse via wago.tools): parsing, build picking, caching, search, resolve."""
import json, os, sys, tempfile, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "epu-discord"))
import epu_core as core

failed = 0
def check(label, cond):
    global failed
    print(("PASS " if cond else "FAIL ") + label)
    failed += 0 if cond else 1

CSV = ('ID,AllowableRace,Description_lang,Display3_lang,Display2_lang,Display1_lang,Display_lang,OverallQualityID\n'
       '2589,-1,"",,,,Linen Cloth,1\n5762,-1,"",,,,Red Linen Bag,1\n'
       '253668,-1,"Teaches you how to sew a Woolen Reagent Bag.",,,,"Pattern: Woolen Reagent Bag",2\n'
       '4238,-1,,,,,Linen Bag,1\n12345,-1,,,,,Deprecated Linen Thing,0\n9999,-1,,,,,"Monster - Sword, Test",0\n')
items = core.parse_itemsparse_csv(CSV)
check("parses names incl. commas/colons", items.get(253668) == "Pattern: Woolen Reagent Bag" and items.get(5762) == "Red Linen Bag")
check("skips junk/test items", 12345 not in items and 9999 not in items)

builds = {"wow": [{"version": "12.1.5.66000"}], "wow_classic_era": [{"version": "1.15.8.67000"}],
          "wowf": [{"version": "1.60.1.70009"}, {"version": "1.60.1.70374"}], "wowf_beta": [{"version": "1.60.2.69000"}]}
check("picks newest 1.60.x build", core.newest_version(builds) == "1.60.2.69000")
check("no Forever build -> None", core.newest_version({"wow": [{"version": "12.0.0.1"}]}) is None)

d = tempfile.mkdtemp()
db = core.ItemDB(d)
big = CSV + "".join(f"{100000 + i},-1,,,,,Filler Item {i},1\n" for i in range(1200))
calls = []
def fake_get(url, timeout=60):
    calls.append(url)
    return json.dumps(builds).encode() if url == db.BUILDS_URL else big.encode()
db._get = fake_get
msg = db.load()
check("downloads newest build's ItemSparse", "downloaded" in msg and calls[-1].endswith("build=1.60.2.69000"))
check("search: prefix matches first", [n for _, n in db.search("linen")][:3] == ["Linen Bag", "Linen Cloth", "Red Linen Bag"][:3] or print(db.search("linen")))
check("search: substring", (253668, "Pattern: Woolen Reagent Bag") in db.search("reagent bag"))
check("resolve by exact name uses full list", core.resolve_item("red linen bag", {}) == (5762, "Red Linen Bag"))
check("autocomplete value resolves", core.resolve_item("id:253668", {}) == (253668, "Pattern: Woolen Reagent Bag"))
check("item names fall back to full list", core.GuildData({}).item_name(5762) == "Red Linen Bag")

db2 = core.ItemDB(d); calls.clear(); db2._get = fake_get
check("fresh cache: no network", "cached" in db2.load() and calls == [])
c = json.load(open(db2.cache)); c["fetched"] = time.time() - 8 * 86400; json.dump(c, open(db2.cache, "w"))
db3 = core.ItemDB(d); calls.clear(); db3._get = fake_get
check("stale cache, same build: only checks the build list", "still current" in db3.load() and calls == [db3.BUILDS_URL])
c = json.load(open(db3.cache)); c["fetched"] = 0; json.dump(c, open(db3.cache, "w"))
db4 = core.ItemDB(d)
def offline(url, timeout=60): raise OSError("no internet")
db4._get = offline
check("offline: keeps cached list", "refresh failed" in db4.load() and db4.find("Linen Cloth") == 2589)
open(os.path.join(d, "items.csv"), "w").write(CSV)
db5 = core.ItemDB(d); db5._get = offline
check("items.csv you saved yourself wins", "items.csv" in db5.load() and len(db5.items) == 4)
rel = core.release_info({"tag_name": "v0.4.0", "html_url": "https://github.com/x/y/releases/tag/v0.4.0", "body": "notes",
    "assets": [{"name": "EPUGuild-0.4.0.zip", "browser_download_url": "https://dl/addon"},
               {"name": "epu-discord-0.4.0.zip", "browser_download_url": "https://dl/bot"},
               {"name": "EPU-Updater-0.4.0.zip", "browser_download_url": "https://dl/updater"},
               {"name": "release.json", "browser_download_url": "https://dl/json"}]})
check("release info picks the right downloads", rel["version"] == "0.4.0" and rel["addon"] == "https://dl/addon" and rel["updater"] == "https://dl/updater")
sys.exit(1 if failed else 0)

"""Build EPUGuild/ZoneData.lua from Efficient Games WoW: Forever dataset (eg-link-output-wowf)
combined with WoW: Forever zone metadata (level ranges, fishing, overviews, Forever dungeons).
"""
import collections
import glob
import json
import os
import re

ROOT = r"C:\Users\Owner\.gemini\antigravity\brain\4b06908b-827d-492a-9191-11ad616f44ba\scratch\eg-link-output-wowf\data\wowf"
OUT = r"C:\Users\Owner\OneDrive\Documents\GitHub\epu-guild-tools\EPUGuild\ZoneData.lua"
OUT_LIVE = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\EPUGuild\ZoneData.lua"

ZONES = [
    # Kalimdor
    dict(id="durotar", name="Durotar", mapID=1411, continent="Kalimdor", faction="Horde", levelRange=(1, 12),
         tagline="Red-rock homeland of the Orcs and Darkspear Trolls",
         overview="Durotar stretches from the Valley of Trials to Orgrimmar. Razor Hill is the main quest and profession hub, with Sen'jin Village on the southern coast.",
         dungeons=[("Ragefire Chasm (via Orgrimmar)", (13, 18), 45.5, 10.0)],
         fishing=(1, "1+ (Coastal waters, Southfury River, Echo Isles)", ["Brilliant Smallfish", "Slitherskin Mackerel", "Longjaw Mud Snapper", "Oily Blackmouth"])),
    dict(id="mulgore", name="Mulgore", mapID=1412, continent="Kalimdor", faction="Horde", levelRange=(1, 12),
         tagline="Rolling green mesas of the Tauren",
         overview="Mulgore centers on Bloodhoof Village and Thunder Bluff. Rich in early Herbalism, Skinning, and Stonebull Lake fishing.",
         dungeons=[],
         fishing=(1, "1+ (Stonebull Lake in Bloodhoof Village)", ["Brilliant Smallfish", "Longjaw Mud Snapper", "Raw Loch Frenzy"])),
    dict(id="the_barrens", name="The Barrens", mapID=1413, continent="Kalimdor", faction="Horde", levelRange=(10, 25),
         tagline="Vast savanna crossroads, Ratchet port, and Wailing Caverns",
         overview="The Barrens is Kalimdor's central 10-25 leveling hub. Forever also adds a Merchant's Favor supply hub just west of The Crossroads.",
         dungeons=[("Wailing Caverns", (17, 24), 46.0, 36.4), ("Razorfen Kraul", (29, 38), 40.9, 94.0)],
         fishing=(1, "1-75+ (Oases for Deviate Fish; Ratchet coast for Oily Blackmouth & Firefin Snapper)", ["Deviate Fish", "Oily Blackmouth", "Firefin Snapper", "Raw Longjaw Mud Snapper", "Raw Bristle Whisker Catfish"])),
    dict(id="teldrassil", name="Teldrassil", mapID=1438, continent="Kalimdor", faction="Alliance", levelRange=(1, 12),
         tagline="The Great Tree home of the Night Elves",
         overview="Teldrassil rises above the northern sea, with Dolanaar as its central hub and Rut'theran Village connecting by boat to Darkshore.",
         dungeons=[],
         fishing=(1, "1+ (Lake Al'Ameth, Dolanaar ponds, Rut'theran docks)", ["Brilliant Smallfish", "Slitherskin Mackerel", "Longjaw Mud Snapper", "Raw Loch Frenzy"])),
    dict(id="darkshore", name="Darkshore", mapID=1439, continent="Kalimdor", faction="Alliance", levelRange=(10, 20),
         tagline="Misty Night Elf shoreline anchored by Auberdine",
         overview="Darkshore is a long coastal strip anchored by Auberdine, with boats to Teldrassil and Menethil Harbor.",
         dungeons=[],
         fishing=(1, "1-75+ (Auberdine docks & shoreline)", ["Slitherskin Mackerel", "Oily Blackmouth", "Raw Rainbow Fin Albacore"])),
    dict(id="ashenvale", name="Ashenvale", mapID=1440, continent="Kalimdor", faction="Contested", levelRange=(18, 30),
         tagline="Ancient Night Elf forest contested by Horde lumber camps",
         overview="Ashenvale spans from Zoram Strand in the west to Splintertree Post in the east, with Astranaar in the center and Blackfathom Deeps off the coast.",
         dungeons=[("Blackfathom Deeps", (24, 32), 14.5, 13.8)],
         fishing=(55, "55-130 (Falfarren River, Mystral Lake, Zoram Strand)", ["Raw Bristle Whisker Catfish", "Oily Blackmouth", "Firefin Snapper", "Raw Sagefish"])),
    dict(id="stonetalon_mountains", name="Stonetalon Mountains", mapID=1442, continent="Kalimdor", faction="Contested", levelRange=(15, 27),
         tagline="Canyon ridges, Venture Co. logging, and Stonetalon Peak",
         overview="Stonetalon Mountains bridges The Barrens and Desolace, with Sun Rock Retreat (Horde), Stonetalon Peak (Alliance), and goblin vendors near Windshear Crag.",
         dungeons=[],
         fishing=(55, "55+ (Mirkfallon Lake, Cragpool Lake)", ["Raw Bristle Whisker Catfish", "Raw Longjaw Mud Snapper", "Raw Sagefish"])),
    dict(id="thousand_needles", name="Thousand Needles", mapID=1441, continent="Kalimdor", faction="Contested", levelRange=(25, 35),
         tagline="Towering stone mesas and the Shimmering Flats raceway",
         overview="Thousand Needles is a canyon of mesas leading east to the Shimmering Flats neutral racing hub.",
         dungeons=[],
         fishing=(130, "130+ (Limited pools near Freewind & Darkcloud)", ["Raw Mithril Head Trout", "Raw Bristle Whisker Catfish"])),
    dict(id="desolace", name="Desolace", mapID=1443, continent="Kalimdor", faction="Contested", levelRange=(30, 40),
         tagline="Ash-swept centaur plains, Kodo Graveyard, and Maraudon",
         overview="Desolace features Shadowprey Village (Horde), Nijel's Point (Alliance), warring centaur clans, and traveling/off-road goblin vendors.",
         dungeons=[("Maraudon", (46, 55), 29.1, 62.5)],
         fishing=(130, "130-205 (Shadowprey Village docks & Ethel Rethor coast)", ["Raw Mithril Head Trout", "Raw Glossy Mightfish", "Firefin Snapper", "Stonescale Eel"])),
    dict(id="dustwallow_marsh", name="Dustwallow Marsh", mapID=1445, continent="Kalimdor", faction="Contested", levelRange=(35, 45),
         tagline="Misty swampland, Theramore Isle, and Alcaz Prison",
         overview="Dustwallow Marsh features Theramore Isle (Alliance), Brackenwall Village (Horde), Nat Pagle's island, and Forever's Alcaz Prison dungeon.",
         dungeons=[("Alcaz Prison (Forever)", (48, 53), 77.0, 17.5), ("Onyxia's Lair (Raid)", (60, 60), 52.6, 76.2)],
         fishing=(130, "130-205+ (Theramore Bay, Alcaz Island, Tidefury Cove)", ["Raw Redgill", "Raw Spotted Yellowtail", "Oily Blackmouth", "Firefin Snapper", "Stonescale Eel"])),
    dict(id="tanaris", name="Tanaris", mapID=1446, continent="Kalimdor", faction="Contested", levelRange=(40, 50),
         tagline="Desert crossroads of Gadgetzan, Steamwheedle Port, and Zul'Farrak",
         overview="Tanaris is a premier 40-50 hub anchored by neutral Gadgetzan and Steamwheedle Port, with high-demand Alchemy and Cooking recipe vendors.",
         dungeons=[("Zul'Farrak", (44, 54), 38.7, 20.0)],
         fishing=(205, "205+ (300 recommended for Steamwheedle Port & Land's End Beach)", ["Raw Redgill", "Raw Spotted Yellowtail", "Raw Nightfin Snapper", "Raw Sunscale Salmon", "Stonescale Eel", "Firefin Snapper"])),
    dict(id="feralas", name="Feralas", mapID=1444, continent="Kalimdor", faction="Contested", levelRange=(40, 50),
         tagline="Lush ancient rainforest, Feathermoon Stronghold, and Dire Maul",
         overview="Feralas is a dense 40-50 forest with Feathermoon Stronghold (Alliance), Camp Mojache (Horde), and Dire Maul.",
         dungeons=[("Dire Maul", (55, 60), 59.0, 41.8)],
         fishing=(205, "205-300 (Verdantis River, Feathermoon coast, Sardor Isle)", ["Raw Redgill", "Raw Nightfin Snapper", "Raw Sunscale Salmon", "Raw Whitescale Salmon", "Stonescale Eel"])),
    dict(id="azshara", name="Azshara", mapID=1447, continent="Kalimdor", faction="Contested", levelRange=(45, 55),
         tagline="Autumnal cliffs, Naga ruins, and Blackmaw Hold",
         overview="Azshara features dramatic cliffs, Bay of Storms fishing, Hydraxian Waterlords, and Forever's Blackmaw Hold dungeon.",
         dungeons=[("Blackmaw Hold (Forever)", (55, 60), 38.4, 32.6)],
         fishing=(205, "205-300+ (Bay of Storms — Elemental Water pools)", ["Stonescale Eel", "Raw Nightfin Snapper", "Raw Whitescale Salmon", "Essence of Water"])),
    dict(id="felwood", name="Felwood", mapID=1448, continent="Kalimdor", faction="Contested", levelRange=(48, 55),
         tagline="Blighted forest, Emerald Sanctuary, and Timbermaw Hold",
         overview="Felwood stretches from Emerald Sanctuary to Timbermaw Hold. Key spot for Timbermaw reputation, Whipper Root Tubers, and high-level herbs.",
         dungeons=[],
         fishing=(205, "205-300 (Bloodvenom Falls & Irontree Woods)", ["Raw Nightfin Snapper", "Raw Sunscale Salmon", "Raw Whitescale Salmon"])),
    dict(id="ungoro_crater", name="Un'Goro Crater", mapID=1449, continent="Kalimdor", faction="Contested", levelRange=(48, 55),
         tagline="Prehistoric jungle basin, Marshal's Refuge, and Shaper's Terrace",
         overview="Un'Goro Crater is a compact 48-55 basin anchored by Marshal's Refuge, Devilsaur Leather, and Forever's Shaper's Terrace dungeon.",
         dungeons=[("Shaper's Terrace (Forever)", (58, 60), 48.1, 6.1)],
         fishing=(205, "205+ (Lakkari Tar Pits & Golakka Hot Springs)", ["Raw Mithril Head Trout", "Raw Spotted Yellowtail"])),
    dict(id="moonglade", name="Moonglade", mapID=1450, continent="Kalimdor", faction="Neutral", levelRange=(1, 60),
         tagline="Sacred Druid sanctuary of Nighthaven and Lake Elune'ara",
         overview="Moonglade is a tranquil sanctuary for Druids and Cenarion Circle members, featuring unique recipes in Nighthaven.",
         dungeons=[],
         fishing=(205, "205-300 (Lake Elune'ara)", ["Raw Nightfin Snapper", "Raw Sunscale Salmon", "Oily Blackmouth"])),
    dict(id="silithus", name="Silithus", mapID=1451, continent="Kalimdor", faction="Contested", levelRange=(55, 60),
         tagline="Qiraji desert frontier, Cenarion Hold, and Ahn'Qiraj",
         overview="Silithus is the 55-60 endgame desert surrounding Ahn'Qiraj, anchored by Cenarion Hold.",
         dungeons=[("Ruins of Ahn'Qiraj (AQ20)", (60, 60), 28.8, 92.4), ("Temple of Ahn'Qiraj (AQ40)", (60, 60), 28.8, 92.4)],
         fishing=(1, "No open fishing waters in Silithus", [])),
    dict(id="winterspring", name="Winterspring", mapID=1452, continent="Kalimdor", faction="Contested", levelRange=(53, 60),
         tagline="Snowy high-level plateau, Everlook, and Frostsaber Rock",
         overview="Winterspring is a 53-60 endgame zone centered on neutral Everlook, home to rare vendor recipes and Black Lotus.",
         dungeons=[],
         fishing=(280, "280-300+ (Lake Kel'Theril & Frostwhisper Gorge)", ["Raw Whitescale Salmon", "Raw Nightfin Snapper", "Raw Sunscale Salmon"])),

    # Eastern Kingdoms
    dict(id="elwynn_forest", name="Elwynn Forest", mapID=1429, continent="Eastern Kingdoms", faction="Alliance", levelRange=(1, 12),
         tagline="Sunlit woods surrounding Stormwind City and Goldshire",
         overview="Elwynn Forest is the Human starting zone, with Northshire Abbey, Goldshire Inn, and Eastvale Logging Camp.",
         dungeons=[],
         fishing=(1, "1+ (Crystal Lake, Stonecairn Lake, southern rivers)", ["Brilliant Smallfish", "Longjaw Mud Snapper", "Raw Loch Frenzy"])),
    dict(id="westfall", name="Westfall", mapID=1436, continent="Eastern Kingdoms", faction="Alliance", levelRange=(10, 20),
         tagline="Golden farmlands overrun by the Defias Brotherhood",
         overview="Westfall is anchored by Sentinel Hill and Moonbrook, leading into The Deadmines.",
         dungeons=[("The Deadmines", (17, 26), 42.5, 71.7)],
         fishing=(1, "1-75+ (Longshore coast & Moonbrook pools)", ["Slitherskin Mackerel", "Oily Blackmouth", "Raw Rainbow Fin Albacore"])),
    dict(id="redridge_mountains", name="Redridge Mountains", mapID=1433, continent="Eastern Kingdoms", faction="Contested", levelRange=(15, 25),
         tagline="Lakeside town of Lakeshire under Blackrock Orc siege",
         overview="Redridge Mountains centers on Lakeshire and Lake Everstill, with Three Corners nearby on the Elwynn/Duskwood border.",
         dungeons=[],
         fishing=(55, "55+ (Lake Everstill)", ["Raw Bristle Whisker Catfish", "Raw Longjaw Mud Snapper", "Raw Loch Frenzy"])),
    dict(id="duskwood", name="Duskwood", mapID=1431, continent="Eastern Kingdoms", faction="Contested", levelRange=(18, 30),
         tagline="Haunted forest of Darkshire, Stitches, and Raven Hill",
         overview="Duskwood is an atmospheric 18-30 zone anchored by Darkshire on the east and Raven Hill Cemetery to the west.",
         dungeons=[],
         fishing=(55, "55+ (Brightwood streams)", ["Raw Bristle Whisker Catfish", "Raw Longjaw Mud Snapper"])),
    dict(id="dun_morogh", name="Dun Morogh", mapID=1426, continent="Eastern Kingdoms", faction="Alliance", levelRange=(1, 12),
         tagline="Snowy peaks of the Dwarves and Gnomes",
         overview="Dun Morogh surrounds Ironforge and Kharanos, with Coldridge Valley in the southwest and Gnomeregan in the west.",
         dungeons=[("Gnomeregan", (29, 38), 24.3, 39.8)],
         fishing=(1, "1+ (Iceflow Lake, Helm's Bed Lake)", ["Brilliant Smallfish", "Longjaw Mud Snapper", "Raw Loch Frenzy"])),
    dict(id="loch_modan", name="Loch Modan", mapID=1432, continent="Eastern Kingdoms", faction="Alliance", levelRange=(10, 20),
         tagline="The great dwarven Loch, Stonewrought Dam, and Thelsamar",
         overview="Loch Modan is an Alliance 10-20 zone centered on Thelsamar and Stonewrought Dam.",
         dungeons=[],
         fishing=(1, "1-75 (The Loch)", ["Raw Loch Frenzy", "Brilliant Smallfish", "Longjaw Mud Snapper", "Raw Bristle Whisker Catfish"])),
    dict(id="wetlands", name="Wetlands", mapID=1437, continent="Eastern Kingdoms", faction="Contested", levelRange=(20, 30),
         tagline="Rainy marshland, Menethil Harbor, and Excavation Site",
         overview="Wetlands connects Loch Modan, Arathi Highlands, boats to Darkshore & Theramore, and Forever's Excavation Site dungeon.",
         dungeons=[("Excavation Site (Forever)", (24, 29), 38.0, 49.0)],
         fishing=(55, "55-130+ (Menethil Bay & marshes)", ["Oily Blackmouth", "Firefin Snapper", "Raw Bristle Whisker Catfish", "Raw Mithril Head Trout"])),
    dict(id="tirisfal_glades", name="Tirisfal Glades", mapID=1420, continent="Eastern Kingdoms", faction="Horde", levelRange=(1, 12),
         tagline="Shadowy Forsaken homeland, Brill, and Scarlet Monastery",
         overview="Tirisfal Glades surrounds Undercity and Brill, with Scarlet Monastery in the northeast and Forever's Ruins of Lordaeron dungeon.",
         dungeons=[("Ruins of Lordaeron (Forever)", (15, 20), 61.8, 65.0), ("Scarlet Monastery", (29, 44), 84.9, 32.8)],
         fishing=(1, "1+ (Brightwater Lake & northern coast)", ["Brilliant Smallfish", "Slitherskin Mackerel", "Longjaw Mud Snapper"])),
    dict(id="silverpine_forest", name="Silverpine Forest", mapID=1421, continent="Eastern Kingdoms", faction="Horde", levelRange=(10, 20),
         tagline="Pine woods of The Sepulcher and Shadowfang Keep",
         overview="Silverpine Forest is a Horde 10-20 zone centered on The Sepulcher and Shadowfang Keep.",
         dungeons=[("Shadowfang Keep", (22, 30), 44.8, 67.8)],
         fishing=(1, "1-75+ (Lordamere Lake & western coast)", ["Slitherskin Mackerel", "Oily Blackmouth", "Raw Rainbow Fin Albacore"])),
    dict(id="hillsbrad_foothills", name="Hillsbrad Foothills", mapID=1424, continent="Eastern Kingdoms", faction="Contested", levelRange=(20, 30),
         tagline="Rolling hills between Southshore, Tarren Mill, and Ravenholdt",
         overview="Hillsbrad Foothills is the iconic 20-30 valley between Tarren Mill (Horde) and Southshore (Alliance).",
         dungeons=[],
         fishing=(55, "55-150+ (Southshore coast & Darrowmere river)", ["Oily Blackmouth", "Firefin Snapper", "Raw Bristle Whisker Catfish", "Raw Mithril Head Trout"])),
    dict(id="alterac_mountains", name="Alterac Mountains", mapID=1416, continent="Eastern Kingdoms", faction="Contested", levelRange=(28, 40),
         tagline="Snowy ruins, Syndicate strongholds, and City of Dalaran",
         overview="Alterac Mountains sits north of Hillsbrad and houses Forever's City of Dalaran dungeon.",
         dungeons=[("City of Dalaran (Forever)", (28, 33), 20.0, 84.0)],
         fishing=(130, "130+ (Lordamere Lake northern shore)", ["Raw Mithril Head Trout", "Raw Bristle Whisker Catfish"])),
    dict(id="arathi_highlands", name="Arathi Highlands", mapID=1417, continent="Eastern Kingdoms", faction="Contested", levelRange=(30, 40),
         tagline="Wind-swept highlands, Stromgarde Keep, and Hammerfall",
         overview="Arathi Highlands hosts Refuge Pointe (Alliance), Hammerfall (Horde), and hidden vendors in Faldir's Cove.",
         dungeons=[],
         fishing=(130, "130-205 (Faldir's Cove & Go'Shek Farm ponds)", ["Oily Blackmouth", "Firefin Snapper", "Raw Mithril Head Trout"])),
    dict(id="the_hinterlands", name="The Hinterlands", mapID=1425, continent="Eastern Kingdoms", faction="Contested", levelRange=(40, 50),
         tagline="Wildhammer Aerie Peak, Revantusk Village, and Jintha'Alor",
         overview="The Hinterlands is a lush 40-50 highland zone with Aerie Peak (Alliance) and Revantusk Village (Horde).",
         dungeons=[],
         fishing=(205, "205-300 (Revantusk coast & lakes)", ["Raw Redgill", "Raw Spotted Yellowtail", "Raw Nightfin Snapper", "Stonescale Eel"])),
    dict(id="stranglethorn_vale", name="Stranglethorn Vale", mapID=1434, continent="Eastern Kingdoms", faction="Contested", levelRange=(30, 45),
         tagline="Dense jungle of Nesingwary, Booty Bay, and The Drowned City",
         overview="Stranglethorn Vale (STV) is the 30-45 jungle hub with Booty Bay, Grom'gol, Forever's The Drowned City dungeon, and Zul'Gurub.",
         dungeons=[("The Drowned City (Forever)", (35, 40), 21.4, 27.9), ("Zul'Gurub (Raid)", (60, 60), 53.9, 17.6)],
         fishing=(130, "130-250+ (Booty Bay & Yojamba Isle)", ["Oily Blackmouth", "Firefin Snapper", "Stonescale Eel", "Raw Spotted Yellowtail", "Raw Redgill"])),
    dict(id="swamp_of_sorrows", name="Swamp of Sorrows", mapID=1435, continent="Eastern Kingdoms", faction="Contested", levelRange=(35, 45),
         tagline="Misty marshland, Stonard, and Sunken Temple",
         overview="Swamp of Sorrows is a 35-45 marshland anchored by Stonard (Horde) and the Temple of Atal'Hakkar.",
         dungeons=[("Sunken Temple", (50, 56), 70.0, 55.0)],
         fishing=(130, "130-205 (Misty Reed Strand & pools)", ["Oily Blackmouth", "Firefin Snapper", "Raw Redgill", "Stonescale Eel"])),
    dict(id="badlands", name="Badlands", mapID=1418, continent="Eastern Kingdoms", faction="Contested", levelRange=(35, 45),
         tagline="Arid canyons, Kargath, and Uldaman",
         overview="Badlands is a 35-45 zone famous for Uldaman (and Master Enchanting trainer Annora) and Kargath.",
         dungeons=[("Uldaman", (41, 51), 42.5, 13.5)],
         fishing=(1, "No open fishing waters in Badlands", [])),
    dict(id="riverglades", name="Riverglades", mapID=2548, continent="Eastern Kingdoms", faction="Contested", levelRange=(35, 45),
         tagline="WoW: Forever zone and Krol'dok Stronghold",
         overview="Riverglades is a new WoW: Forever zone featuring goblin and Horde/Alliance outposts and Krol'dok Stronghold.",
         dungeons=[("Krol'dok Stronghold (Forever)", (40, 45), 37.5, 37.5)],
         fishing=(130, "130-225+ (Riverglades waterways)", ["Raw Mithril Head Trout", "Raw Redgill"])),
    dict(id="zephras_isle", name="Zephras Isle", mapID=2653, continent="Kalimdor", faction="Neutral", levelRange=(1, 12),
         tagline="Skyborne starting island in WoW: Forever",
         overview="Zephras Isle is the new Skyborne starting zone in WoW: Forever. Watch for Skyborne quests, trainers, and early gathering.",
         dungeons=[],
         fishing=(1, "1+ (Zephras Isle coastal waters)", ["Brilliant Smallfish", "Slitherskin Mackerel"])),
    dict(id="quelthalas_outpost", name="Quel'Thalas / High Elf Enclave", mapID=2652, continent="Eastern Kingdoms", faction="Alliance", levelRange=(1, 20),
         tagline="WoW: Forever High Elf / Quel'Thalas area (Map 2652)",
         overview="Observed in WoW: Forever build data (NPCs include Mordent Evenshade and Nerlokh).",
         dungeons=[],
         fishing=(1, "1+ (Coastal waters)", ["Brilliant Smallfish", "Slitherskin Mackerel"])),

    # Capital Cities
    dict(id="stormwind", name="Stormwind City", mapID=1453, continent="Eastern Kingdoms", faction="Alliance", levelRange=(1, 60),
         tagline="Grand Alliance capital of Humans, canals, and every trainer",
         overview="Stormwind City houses Alliance class and profession trainers, Auction House, Bank, and The Stockade.",
         dungeons=[("The Stockade", (24, 32), 49.0, 66.0)],
         fishing=(1, "1+ (Canals & Stormwind Harbor)", ["Brilliant Smallfish", "Longjaw Mud Snapper", "Raw Bristle Whisker Catfish"])),
    dict(id="ironforge", name="Ironforge", mapID=1455, continent="Eastern Kingdoms", faction="Alliance", levelRange=(1, 60),
         tagline="Dwarven mountain capital, Great Forge, and Hall of Thanes",
         overview="Ironforge is the Alliance's central AH/bank hub around the Great Forge and home to Forever's Hall of Thanes dungeon.",
         dungeons=[("Hall of Thanes (Forever)", (13, 18), 43.5, 52.0)],
         fishing=(1, "1+ (Forlorn Cavern pool)", ["Brilliant Smallfish", "Longjaw Mud Snapper"])),
    dict(id="darnassus", name="Darnassus", mapID=1457, continent="Kalimdor", faction="Alliance", levelRange=(1, 60),
         tagline="Night Elf capital atop Teldrassil",
         overview="Darnassus is the Night Elf capital with class/profession trainers, AH, and Bank.",
         dungeons=[],
         fishing=(1, "1+ (Temple Gardens & Craftsmen's Terrace)", ["Brilliant Smallfish", "Longjaw Mud Snapper"])),
    dict(id="orgrimmar", name="Orgrimmar", mapID=1454, continent="Kalimdor", faction="Horde", levelRange=(1, 60),
         tagline="Fortress capital of the Horde and Ragefire Chasm",
         overview="Orgrimmar is the Horde's central AH/bank hub, Zeppelin port, and home to Ragefire Chasm.",
         dungeons=[("Ragefire Chasm", (13, 18), 52.8, 48.8)],
         fishing=(1, "1+ (Valley of Honor pond)", ["Brilliant Smallfish", "Longjaw Mud Snapper"])),
    dict(id="thunder_bluff", name="Thunder Bluff", mapID=1456, continent="Kalimdor", faction="Horde", levelRange=(1, 60),
         tagline="High-mesa capital of the Tauren",
         overview="Thunder Bluff spans four mesas connected by rope bridges, with all Horde trainers, AH, and Bank.",
         dungeons=[],
         fishing=(1, "1+ (Pools of Vision)", ["Brilliant Smallfish", "Longjaw Mud Snapper"])),
    dict(id="undercity", name="Undercity", mapID=1458, continent="Eastern Kingdoms", faction="Horde", levelRange=(1, 60),
         tagline="Subterranean Forsaken capital beneath Lordaeron",
         overview="Undercity is the Forsaken capital with circular quarters (Trade, Magic, War, Rogues, Apothecarium).",
         dungeons=[],
         fishing=(1, "1+ (Inner moat & canals)", ["Brilliant Smallfish", "Longjaw Mud Snapper"])),
]

RECIPE_PREFIXES = ("Recipe:", "Pattern:", "Plans:", "Schematic:", "Formula:", "Manual:")

def q(s):
    if s is None:
        return "nil"
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'

def main():
    builds = sorted(os.listdir(ROOT))
    # Aggregate across all WoW Forever builds
    npcs = {}  # npc_id -> {name, side, interactions, positions_by_map}
    vendors_items = collections.defaultdict(dict)  # npc_id -> {item_name: {limited, cost, itemId}}
    trainers_data = {}  # npc_id -> {name, services, positions}
    flight_masters = {}  # npc_id -> {name, node}
    quests_meta = {}  # qid -> {title, level, questType, zoneAreaId}
    quest_factions = {}  # qid -> faction
    quest_positions = collections.defaultdict(list)  # qid -> [(uiMap, x, y)]

    for b in builds:
        bdir = os.path.join(ROOT, b)
        np_file = os.path.join(bdir, "npcs.json")
        if os.path.exists(np_file):
            with open(np_file, encoding="utf-8") as f:
                data = json.load(f).get("npcs", {})
            for nid, info in data.items():
                entry = npcs.setdefault(nid, {"name": info.get("name"), "side": info.get("side"), "interactions": set(), "pos": {}})
                if info.get("name"): entry["name"] = info["name"]
                if info.get("side"): entry["side"] = info["side"]
                for inter in info.get("interactions") or []:
                    entry["interactions"].add(inter)
                for p in info.get("positions") or []:
                    if p.get("instance") in (0, 1) and p.get("uiMap") and p.get("mapX") is not None and p.get("mapY") is not None:
                        m = p["uiMap"]
                        if m not in entry["pos"]:
                            entry["pos"][m] = (round(p["mapX"] * 100, 1), round(p["mapY"] * 100, 1))

        vf = os.path.join(bdir, "vendors.json")
        if os.path.exists(vf):
            with open(vf, encoding="utf-8") as f:
                vdata = json.load(f).get("vendors", {})
            for nid, vinfo in vdata.items():
                for key, item in (vinfo.get("entries") or {}).items():
                    if not key.startswith("item:") or not item.get("name"):
                        continue
                    vendors_items[nid][item["name"]] = {
                        "limited": bool(item.get("limited") or item.get("stockMax")),
                        "itemId": item.get("itemId"),
                    }

        tf = os.path.join(bdir, "trainers.json")
        if os.path.exists(tf):
            with open(tf, encoding="utf-8") as f:
                tdata = json.load(f).get("trainers", {})
            for nid, tinfo in tdata.items():
                tentry = trainers_data.setdefault(nid, {"name": tinfo.get("name"), "services": set(), "pos": {}})
                if tinfo.get("name"): tentry["name"] = tinfo["name"]
                for svc in (tinfo.get("services") or {}).values():
                    if svc.get("name"):
                        tentry["services"].add((svc["name"], bool(svc.get("profession"))))
                for p in tinfo.get("positions") or []:
                    if p.get("instance") in (0, 1) and p.get("uiMap") and p.get("mapX") is not None and p.get("mapY") is not None:
                        m = p["uiMap"]
                        if m not in tentry["pos"]:
                            tentry["pos"][m] = (round(p["mapX"] * 100, 1), round(p["mapY"] * 100, 1))

        ff = os.path.join(bdir, "flights.json")
        if os.path.exists(ff):
            with open(ff, encoding="utf-8") as f:
                fdata = json.load(f).get("masters", {})
            for nid, finfo in fdata.items():
                flight_masters[nid] = finfo.get("name")

        qf = os.path.join(bdir, "quests.enUS.json")
        if os.path.exists(qf):
            with open(qf, encoding="utf-8") as f:
                qdata = json.load(f).get("quests", {})
            for qid, qinfo in qdata.items():
                if qinfo.get("title"):
                    qt = qinfo.get("questType")
                    qtype_label = "Group" if str(qt) == "1" else "Solo"
                    quests_meta[qid] = {
                        "title": qinfo["title"],
                        "level": qinfo.get("level") or qinfo.get("minLevel") or 1,
                        "questType": qtype_label,
                    }

        qsf = os.path.join(bdir, "quest_scan.json")
        if os.path.exists(qsf):
            with open(qsf, encoding="utf-8") as f:
                qsdata = json.load(f).get("described", {})
            for qid, qsinfo in qsdata.items():
                facs = list((qsinfo.get("factions") or {}).keys())
                if len(facs) == 1:
                    quest_factions[qid] = facs[0]
                elif len(facs) > 1:
                    quest_factions[qid] = "Neutral"

        obf = os.path.join(bdir, "objectives.json")
        if os.path.exists(obf):
            with open(obf, encoding="utf-8") as f:
                obq = json.load(f).get("quests", {})
            for qid, steps in obq.items():
                for step in steps.values():
                    for p in step.get("positions") or []:
                        if p.get("instance") in (0, 1) and p.get("uiMap") and p.get("mapX") is not None:
                            quest_positions[qid].append((p["uiMap"], round(p["mapX"] * 100, 1), round(p["mapY"] * 100, 1)))
                            break
                    if quest_positions[qid]:
                        break

    lines = [
        "-- EPU Guild Tools: WoW: Forever Zone Visitor's Guide database.",
        "-- Built from Efficient Games WoW: Forever dataset (https://efficient.games, CC BY 4.0)",
        "-- Source: eg-link-output-wowf builds %s to %s." % (builds[0], builds[-1]),
        "local _, ns = ...",
        "",
        "ns.ZONE_GUIDE_DATA = {",
    ]

    for z in ZONES:
        mid = z["mapID"]
        # Collect Flight Masters
        fps = []
        for nid, fname in flight_masters.items():
            npc = npcs.get(nid)
            if npc and mid in npc["pos"]:
                x, y = npc["pos"][mid]
                fps.append((npc["name"] or fname, npc.get("side") or "Neutral", x, y))
        fps.sort()

        # Collect Trainers
        trs = []
        for nid, tinfo in trainers_data.items():
            if mid in tinfo["pos"]:
                x, y = tinfo["pos"][mid]
                npc = npcs.get(nid, {})
                side = npc.get("side") or "Neutral"
                svcs = sorted(s[0] for s in tinfo["services"])
                is_prof = any(s[1] for s in tinfo["services"])
                ttype = "Profession Trainer" if is_prof else "Class Trainer"
                if svcs:
                    # Pick concise summary
                    sample = ", ".join(svcs[:3]) + ("..." if len(svcs) > 3 else "")
                    ttype = ttype + " (" + sample + ")"
                trs.append((tinfo["name"] or npc.get("name") or "Trainer", ttype, side, x, y))
        trs.sort()

        # Collect Vendors & Vendor Recipes
        vends = []
        recs = []
        for nid, npc in npcs.items():
            if mid in npc["pos"] and ("Merchant" in npc["interactions"] or nid in vendors_items):
                x, y = npc["pos"][mid]
                items = vendors_items.get(nid, {})
                rec_count = sum(1 for iname in items if iname.startswith(RECIPE_PREFIXES))
                vtype = "Merchant (%d items)" % len(items) if items else "Merchant"
                note = "Sells %d recipe/pattern(s)" % rec_count if rec_count else None
                vends.append((rec_count, npc["name"] or "Vendor", vtype, npc.get("side") or "Neutral", x, y, note))
                for iname, idata in sorted(items.items()):
                    if iname.startswith(RECIPE_PREFIXES):
                        prof = iname.split(":", 1)[0]
                        prof_map = {"Recipe": "Alchemy / Cooking", "Pattern": "Tailoring / Leatherworking", "Plans": "Blacksmithing", "Schematic": "Engineering", "Formula": "Enchanting", "Manual": "First Aid"}
                        recs.append((iname, prof_map.get(prof, "Profession"), npc["name"] or "Vendor", npc.get("side") or "Neutral", x, y, idata["limited"]))
        vends.sort(key=lambda r: (-r[0], r[1]))
        recs.sort()

        # Collect Quests observed in this map
        zquests = []
        seen_q = set()
        for qid, pts in quest_positions.items():
            for qm, qx, qy in pts:
                if qm == mid and qid in quests_meta and qid not in seen_q:
                    seen_q.add(qid)
                    qm_info = quests_meta[qid]
                    zquests.append((qm_info["level"], qm_info["title"], quest_factions.get(qid, "Neutral"), qm_info["questType"], qx, qy))
        zquests.sort(key=lambda r: (r[0], r[1]))

        lines.append("  {")
        lines.append("    id = %s, name = %s, mapID = %d, continent = %s," % (q(z["id"]), q(z["name"]), mid, q(z["continent"])))
        lines.append("    faction = %s, levelRange = {%d, %d}," % (q(z["faction"]), z["levelRange"][0], z["levelRange"][1]))
        lines.append("    tagline = %s," % q(z["tagline"]))
        lines.append("    overview = %s," % q(z["overview"]))

        lines.append("    dungeons = {")
        for dname, (dlo, dhi), dx, dy in z["dungeons"]:
            lines.append("      { name = %s, levelRange = {%d, %d}, x = %.1f, y = %.1f }," % (q(dname), dlo, dhi, dx, dy))
        lines.append("    },")

        lines.append("    flightPaths = {")
        for fname, fside, fx, fy in fps:
            lines.append("      { name = %s, faction = %s, x = %.1f, y = %.1f }," % (q(fname), q(fside), fx, fy))
        lines.append("    },")

        fmin, fnote, ffish = z["fishing"]
        fish_lua = ", ".join(q(x) for x in ffish)
        lines.append("    fishing = { minSkill = %d, levelNote = %s, fish = {%s} }," % (fmin, q(fnote), fish_lua))

        lines.append("    trainers = {")
        for tname, ttype, tside, tx, ty in trs:
            lines.append("      { name = %s, type = %s, faction = %s, x = %.1f, y = %.1f }," % (q(tname), q(ttype), q(tside), tx, ty))
        lines.append("    },")

        lines.append("    vendors = {")
        for _, vname, vtype, vside, vx, vy, vnote in vends[:80]:
            lines.append("      { name = %s, type = %s, faction = %s, x = %.1f, y = %.1f, note = %s }," % (q(vname), q(vtype), q(vside), vx, vy, q(vnote)))
        lines.append("    },")

        lines.append("    recipes = {")
        for rname, rprof, rsrc, rside, rx, ry, rlim in recs:
            lines.append("      { name = %s, profession = %s, source = \"Vendor\", sourceName = %s, faction = %s, x = %.1f, y = %.1f, limited = %s }," % (
                q(rname), q(rprof), q(rsrc), q(rside), rx, ry, "true" if rlim else "false"))
        lines.append("    },")

        lines.append("    quests = {")
        for qlvl, qtitle, qfac, qtype, qx, qy in zquests[:80]:
            lines.append("      { name = %s, level = %d, faction = %s, giver = \"Observed in zone\", type = %s, x = %.1f, y = %.1f }," % (
                q(qtitle), qlvl, q(qfac), q(qtype), qx, qy))
        lines.append("    },")
        lines.append("  },")

    lines.append("}")
    text = "\n".join(lines) + "\n"
    for target in (OUT_LIVE,):
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print("Wrote", OUT_LIVE, "zones:", len(ZONES), "bytes:", len(text))

if __name__ == "__main__":
    main()

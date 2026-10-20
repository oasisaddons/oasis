-- Oasis: Questgeber- und Abgabe-Orte der Dungeon-Quests (nur Fakten: NPC, Gebiet, Koordinaten, Voraussetzungen).
-- Zusammengestellt am 28.09.2026 aus foreverchanges.pro, wowforevertalents.com und wowhead.com/classic.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Dungeons", function()   -- Modul Dungeons (abschaltbar, siehe ModuleLoader.lua)
ns.QuestLocations = (function()
-- WoW Forever: dungeon quest start/finish locations (facts only). Generated 2026-09-28.
-- Coordinates: zone percent (0-100) on Classic UiMap "map"; start coords from foreverchanges.pro map pins
--   (Forever beta client build 1.60.1.70009 / cmangos classic-db positions), converted to zone percent.
-- NPC/item/object ids, finish NPC and prereq ids: wowhead.com/classic (IDs < 90000); Forever quests (>90000): foreverchanges.pro + wowforevertalents.com only.
-- inside = true: NPC stands in the dungeon; entrance = dungeon entrance from the Forever map. itemName/item: quest starts from an item.
return {
  [5723] = { start = { npc = "Rahauro", npcId = 11833, zone = "Thunder Bluff", map = 1456, x = 70.1, y = 29.5 } }, -- Testing an Enemy's Strength
  [5728] = { start = { npc = "Thrall", npcId = 4949, zone = "Orgrimmar", map = 1454, x = 31.7, y = 37.8 }, prereq = { 5727 } }, -- Hidden Enemies
  [5724] = { start = { npc = "Maur Grimtotem", inside = true, entrance = { zone = "Orgrimmar", map = 1454, x = 53.0, y = 48.9 } }, finish = { npc = "Rahauro", zone = "Thunder Bluff", map = 1456, x = 70.1, y = 29.5 } }, -- Returning the Lost Satchel
  [5761] = { start = { npc = "Neeru Fireblade", npcId = 3216, zone = "Orgrimmar", map = 1454, x = 49.5, y = 50.6 } }, -- Slaying the Beast
  [5725] = { start = { npc = "Varimathras", npcId = 2425, zone = "Undercity", map = 1458, x = 56.3, y = 92.2 } }, -- The Power to Destroy...
  [5722] = { start = { npc = "Magatha" }, finish = { object = "Maur Grimtotem's corpse" } }, -- Returning the Lost Satchel
  [96395] = { start = { npc = "Ghostly Attendant", inside = true, entrance = { zone = "Ironforge", map = 1455, x = 43.6, y = 51.7 } } }, -- An Ancient Grudge
  [96403] = { start = { npc = "Thom Filch", zone = "Ironforge", map = 1455, x = 32.4, y = 44.8 } }, -- Important Heirlooms
  [96393] = { start = { npc = "Earthseer Farsen", zone = "Dun Morogh", map = 1426, x = 64.8, y = 58.4 }, finish = { npc = "King Magni Bronzebeard", zone = "Dun Morogh", map = 1426, x = 57.4, y = 30.1 } }, -- Old Ironforge Incursion
  [96394] = { start = { npc = "Afadra Dunwall", zone = "Ironforge", map = 1455, x = 33.2, y = 47.8 } }, -- The Restless Dead
  [98423] = { start = { itemName = "Treaty of Understanding" } }, -- The Treaty of Understanding
  [95250] = { start = { npc = "Captain Truman", inside = true } }, -- Abominable Creatures
  [95195] = { start = { itemName = "Bloodied Insignia" }, finish = { npc = "General Marcus Jonathan" } }, -- Bloodied Insignia
  [92415] = { start = { itemName = "Blood-Stained Letter" }, finish = { npc = "Orphan Matron Nightingale" } }, -- Remember That I Love You
  [95189] = { start = { itemName = "Crest of Lordaeron" }, finish = { npc = "Lady Dena Kennedy" } }, -- Crest of Lordaeron
  [92422] = { start = { npc = "Deathguard Kristof", zone = "Tirisfal Glades", map = 1420, x = 65.2, y = 60.2 } }, -- The Wrath of Rath'mael
  [92421] = { start = { npc = "Morbin Lightbane", zone = "Undercity", map = 1458, x = 57.8, y = 89.8 } }, -- Light's Justice
  [92401] = { start = { npc = "Tabitha Heartweaver", zone = "Silverpine Forest", map = 1421, x = 44.4, y = 43.0 } }, -- A Frightened Request
  [95216] = { start = { npc = "Theodore Griffs", zone = "Undercity", map = 1458, x = 46.6, y = 71.4 } }, -- The New Plague
  [97288] = { start = { itemName = "Abominable Head" } }, -- Unending Torment
  [95204] = { start = { itemName = "Crest of Lordaeron" }, finish = { npc = "Oran Snakewrithe" } }, -- Crest of Lordaeron
  [1486] = { start = { npc = "Nalpak", npcId = 5767, zone = "The Barrens", map = 1413, x = 46.0, y = 35.7 } }, -- Deviate Hides
  [1491] = { start = { npc = "Mebok Mizzyrix", npcId = 3446, zone = "The Barrens", map = 1413, x = 62.4, y = 37.6 } }, -- Smart Drinks
  [959] = { start = { npc = "Crane Operator Bigglefuzz", npcId = 3665, zone = "The Barrens", map = 1413, x = 63.1, y = 37.6 } }, -- Trouble at the Docks
  [1487] = { start = { npc = "Ebru", npcId = 5768, zone = "The Barrens", map = 1413, x = 46.0, y = 35.7 } }, -- Deviate Eradication
  [6981] = { start = { item = 10441, itemName = "Glowing Shard" } }, -- The Glowing Shard
  [914] = { start = { npc = "Nara Wildmane", npcId = 5770, zone = "Thunder Bluff", map = 1456, x = 75.6, y = 31.6 }, prereq = { 1489 } }, -- Leaders of the Fang
  [962] = { start = { npc = "Apothecary Zamah", npcId = 3419, zone = "Thunder Bluff", map = 1456, x = 22.8, y = 20.9 } }, -- Serpentbloom
  [1490] = { start = { npc = "Nara Wildmane", npcId = 5770, zone = "Thunder Bluff", map = 1456, x = 75.6, y = 31.6 }, prereq = { 1489 } }, -- Hamuul Runetotem
  [1489] = { start = { npc = "Hamuul Runetotem" } }, -- Nara Wildmane
  [3366] = { start = { item = 10441, itemName = "Glowing Shard" } }, -- The Glowing Shard
  [214] = { start = { npc = "Scout Riell", npcId = 820, zone = "Westfall", map = 1436, x = 56.7, y = 47.3 }, prereq = { 166 } }, -- Red Silk Bandanas
  [168] = { start = { npc = "Wilder Thistlenettle", npcId = 656, zone = "Stormwind City", map = 1453, x = 70.3, y = 40.8 } }, -- Collecting Memories
  [166] = { start = { npc = "Gryan Stoutmantle", npcId = 234, zone = "Westfall", map = 1436, x = 56.3, y = 47.5 }, prereq = { 155 } }, -- The Defias Brotherhood
  [167] = { start = { npc = "Wilder Thistlenettle", npcId = 656, zone = "Stormwind City", map = 1453, x = 70.3, y = 40.8 } }, -- Oh Brother. . .
  [2040] = { start = { npc = "Shoni the Shilent", npcId = 6579, zone = "Stormwind City", map = 1453, x = 62.6, y = 34.1 }, prereq = { 2041 } }, -- Underground Assault
  [92753] = { finish = { npc = "Alba Fairmoon" } }, -- Destruction in Deadmines
  [373] = { start = { item = 2874, itemName = "An Unsent Letter" }, finish = { npc = "Baros Alexston", npcId = 1646 } }, -- The Unsent Letter
  [1013] = { start = { npc = "Keeper Bel'dugur", npcId = 2934, zone = "Undercity", map = 1458, x = 53.7, y = 54.4 } }, -- The Book of Ur
  [1098] = { start = { npc = "High Executor Hadrec", zone = "Silverpine Forest", map = 1421, x = 43.4, y = 40.9 } }, -- Deathstalkers in Shadowfang
  [1014] = { start = { npc = "Dalar Dawnweaver", npcId = 1938, zone = "Silverpine Forest", map = 1421, x = 44.2, y = 39.8 } }, -- Arugal Must Die
  [1740] = { start = { npc = "Doan Karhan", npcId = 6247 } }, -- The Orb of Soran'ruk
  [971] = { start = { npc = "Gerrig Bonegrip", npcId = 2786, zone = "Dun Morogh", map = 1426, x = 59.2, y = 22.0 } }, -- Knowledge in the Deeps
  [1275] = { start = { npc = "Gershala Nightwhisper", npcId = 8997, zone = "Darkshore", map = 1439, x = 38.3, y = 43.0 }, prereq = { 3765 } }, -- Researching the Corruption
  [1200] = { start = { npc = "Argent Guard Thaelrid", inside = true, entrance = { zone = "Ashenvale", map = 1440, x = 16.5, y = 11.0 } }, finish = { npc = "Dawnwatcher Selgorm" } }, -- Blackfathom Villainy
  [1199] = { start = { npc = "Argent Guard Manados", npcId = 4784, zone = "Darnassus", map = 1457, x = 55.2, y = 24.0 } }, -- Twilight Falls
  [6564] = { start = { item = 16790, itemName = "Damp Note" }, finish = { npc = "Je'neu Sancrea", npcId = 12736, zone = "Ashenvale", map = 1440, x = 11.6, y = 34.3 } }, -- Allegiance to the Old Gods
  [6563] = { start = { npc = "Je'neu Sancrea", npcId = 12736, zone = "Ashenvale", map = 1440, x = 11.6, y = 34.3 }, prereq = { 6562 } }, -- The Essence of Aku'Mai
  [6565] = { start = { npc = "Je'neu Sancrea", npcId = 12736, zone = "Ashenvale", map = 1440, x = 11.6, y = 34.3 }, prereq = { 6564 } }, -- Allegiance to the Old Gods
  [6561] = { start = { npc = "Argent Guard Thaelrid", inside = true, entrance = { zone = "Ashenvale", map = 1440, x = 16.5, y = 11.0 } }, finish = { npc = "Bashana Runetotem", zone = "Mulgore", map = 1412, x = 43.9, y = 33.0 } }, -- Blackfathom Villainy
  [6921] = { start = { npc = "Je'neu Sancrea", zone = "Ashenvale", map = 1440, x = 11.6, y = 34.3 } }, -- Amongst the Ruins
  [6562] = { start = { npc = "Je'neu Sancrea", npcId = 12736, zone = "Ashenvale", map = 1440, x = 11.6, y = 34.3 } }, -- The Essence of Aku'Mai
  [1198] = { start = { npc = "Dawnwatcher Shaedlass", npcId = 4786 }, finish = { npc = "Argent Guard Thaelrid", npcId = 4787, inside = true } }, -- Blackfathom Villainy
  [391] = { start = { npc = "Warden Thelwater", npcId = 1719, zone = "Stormwind City", map = 1453, x = 51.5, y = 69.4 }, prereq = { 389 } }, -- The Stockade Riots
  [386] = { start = { npc = "Guard Berton", npcId = 859, zone = "Redridge Mountains", map = 1433, x = 21.2, y = 46.6 } }, -- What Comes Around...
  [377] = { start = { npc = "Councilman Millstipe", npcId = 270, zone = "Duskwood", map = 1431, x = 71.9, y = 47.8 } }, -- Crime and Punishment
  [387] = { start = { npc = "Warden Thelwater", npcId = 1719, zone = "Stormwind City", map = 1453, x = 51.5, y = 69.4 } }, -- Quell The Uprising
  [388] = { start = { npc = "Nikova Raskol", npcId = 1721, zone = "Stormwind City", map = 1453, x = 76.5, y = 63.6 } }, -- The Color of Blood
  [378] = { start = { npc = "Motley Garmason", npcId = 1074, zone = "Wetlands", map = 1437, x = 49.7, y = 18.2 } }, -- The Fury Runs Deep
  [2904] = { start = { npc = "Kernobee", npcId = 7850, inside = true, entrance = { zone = "Dun Morogh", map = 1426, x = 17.7, y = 39.2 } }, finish = { npc = "Scooty", npcId = 7853, zone = "Stranglethorn Vale", map = 1434, x = 27.6, y = 77.5 } }, -- A Fine Mess
  [2951] = { start = { object = "The Sparklematic 5200", objectId = 142487, inside = true, entrance = { zone = "Dun Morogh", map = 1426, x = 17.7, y = 39.2 } } }, -- The Sparklematic 5200!
  [2952] = { start = { object = "The Sparklematic 5200", objectId = 142487, inside = true, entrance = { zone = "Dun Morogh", map = 1426, x = 17.7, y = 39.2 } } }, -- The Sparklematic 5200!
  [2945] = { start = { item = 9326, itemName = "Grime-Encrusted Ring" } }, -- Grime-Encrusted Ring
  [2922] = { start = { npc = "Tinkmaster Overspark", zone = "Dun Morogh", map = 1426, x = 62.2, y = 29.2 } }, -- Save Techbot's Brain!
  [2926] = { start = { npc = "Ozzie Togglevolt", zone = "Dun Morogh", map = 1426, x = 45.9, y = 49.4 }, prereq = { 2927 } }, -- Gnogaine
  [2928] = { start = { npc = "Shoni the Shilent", zone = "Stormwind City", map = 1453, x = 62.6, y = 34.1 } }, -- Gyrodrillmatic Excavationators
  [2962] = { start = { npc = "Ozzie Togglevolt", zone = "Dun Morogh", map = 1426, x = 45.9, y = 49.4 } }, -- The Only Cure is More Green Glow
  [2924] = { start = { npc = "Klockmort Spannerspan", npcId = 6169, zone = "Dun Morogh", map = 1426, x = 62.0, y = 28.5 }, prereq = { 2925 } }, -- Essential Artificials
  [2930] = { start = { npc = "Master Mechanic Castpipe", zone = "Dun Morogh", map = 1426, x = 62.3, y = 28.8 } }, -- Data Rescue
  [2929] = { start = { npc = "High Tinker Mekkatorque", npcId = 7937, zone = "Dun Morogh", map = 1426, x = 62.1, y = 28.9 } }, -- The Grand Betrayal
  [2947] = { start = { object = "The Sparklematic 5200", objectId = 142487, inside = true, entrance = { zone = "Dun Morogh", map = 1426, x = 17.7, y = 39.2 } }, finish = { npc = "Tinkertop" } }, -- Return of the Ring
  [2843] = { start = { npc = "Scooty", npcId = 7853, zone = "Stranglethorn Vale", map = 1434, x = 27.6, y = 77.5 }, prereq = { 2842 } }, -- Gnomer-gooooone!
  [2841] = { start = { npc = "Nogg", npcId = 3412, zone = "Orgrimmar", map = 1454, x = 76.0, y = 25.4 } }, -- Rig Wars
  [2949] = { start = { object = "The Sparklematic 5200", objectId = 142487, inside = true, entrance = { zone = "Dun Morogh", map = 1426, x = 17.7, y = 39.2 } } }, -- Return of the Ring
  [2923] = { start = { npc = "Tinkmaster Overspark", npcId = 7944, zone = "Dun Morogh", map = 1426, x = 62.2, y = 29.2 } }, -- Save Techbot's Brain!
  [2927] = { start = { npc = "Gnoarn", npcId = 6569 }, finish = { npc = "Ozzie Togglevolt", npcId = 1268, zone = "Dun Morogh", map = 1426, x = 45.9, y = 49.4 } }, -- The Day After
  [2842] = { start = { npc = "Scooty", npcId = 7853, zone = "Stranglethorn Vale", map = 1434, x = 27.6, y = 77.5 } }, -- Gnomer-gooooone!
  [1221] = { start = { npc = "Mebok Mizzyrix", npcId = 3446, zone = "The Barrens", map = 1413, x = 62.4, y = 37.6 } }, -- Blueleaf Tubers
  [1144] = { start = { npc = "Willix the Importer", npcId = 4508, inside = true, entrance = { zone = "The Barrens", map = 1413, x = 42.3, y = 89.9 } } }, -- Willix the Importer
  [1142] = { start = { npc = "Heralath Fallowbrook", inside = true, entrance = { zone = "The Barrens", map = 1413, x = 42.3, y = 89.9 } } }, -- Mortality Wanes
  [1101] = { start = { npc = "Falfindel Waywarder", npcId = 4048, zone = "Feralas", map = 1444, x = 89.6, y = 46.6 }, prereq = { 1100 } }, -- The Crone of the Kraul
  [1102] = { start = { npc = "Auld Stonespire", npcId = 4451, zone = "Thunder Bluff", map = 1456, x = 36.0, y = 59.9 } }, -- A Vengeful Fate
  [1109] = { start = { npc = "Master Apothecary Faranell", npcId = 2055, zone = "Undercity", map = 1458, x = 48.8, y = 69.3 } }, -- Going, Going, Guano!
  [1050] = { start = { npc = "Librarian Mae Paledust", zone = "Dun Morogh", map = 1426, x = 63.1, y = 23.1 } }, -- Mythology of the Titans
  [1051] = { start = { npc = "Vorrel Sengutz", npcId = 3981, inside = true, entrance = { zone = "Tirisfal Glades", map = 1420, x = 85.1, y = 31.4 } }, finish = { npc = "Monika Sengutz", npcId = 3982 } }, -- Vorrel's Revenge
  [1160] = { start = { npc = "Parqual Fintallas", npcId = 4488, zone = "Undercity", map = 1458, x = 57.8, y = 65.4 }, prereq = { 1159 } }, -- Test of Lore
  [1049] = { start = { npc = "Sage Truthseeker", npcId = 3978, zone = "Thunder Bluff", map = 1456, x = 34.4, y = 46.9 } }, -- Compendium of the Fallen
  [1113] = { start = { npc = "Master Apothecary Faranell", npcId = 2055, zone = "Undercity", map = 1458, x = 48.8, y = 69.3 }, prereq = { 1109 } }, -- Hearts of Zeal
  [1053] = { start = { npc = "Raleigh the Devout", npcId = 3980, zone = "Hillsbrad Foothills", map = 1424, x = 51.5, y = 58.4 } }, -- In the Name of the Light
  [1048] = { start = { npc = "Varimathras", npcId = 2425, zone = "Undercity", map = 1458, x = 56.3, y = 92.2 } }, -- Into The Scarlet Monastery
  [6626] = { start = { npc = "Myriam Moonsinger", npcId = 12866, zone = "The Barrens", map = 1413, x = 49.0, y = 94.9 } }, -- A Host of Evil
  [3525] = { start = { npc = "Belnistrasz", npcId = 8516, inside = true, entrance = { zone = "The Barrens", map = 1413, x = 50.9, y = 92.9 } }, finish = { object = "Quilboar's idol" }, prereq = { 3523 } }, -- Extinguishing the Idol
  [3523] = { start = { npc = "Belnistrasz", npcId = 8516, inside = true, entrance = { zone = "The Barrens", map = 1413, x = 50.9, y = 92.9 } } }, -- Scourge of the Downs
  [3636] = { start = { npc = "Archbishop Benedictus", zone = "Stormwind City", map = 1453, x = 50.3, y = 45.5 } }, -- Bring the Light
  [6521] = { start = { npc = "Varimathras", npcId = 2425, zone = "Undercity", map = 1458, x = 56.3, y = 92.2 }, prereq = { 6522 } }, -- An Unholy Alliance
  [6522] = { start = { item = 17008, itemName = "Small Scroll" }, finish = { npc = "Varimathras", npcId = 2425, zone = "Undercity", map = 1458, x = 56.3, y = 92.2 }, prereq = { 6521 } }, -- An Unholy Alliance
  [3341] = { start = { npc = "Andrew Brownell", npcId = 2308, zone = "Undercity", map = 1458, x = 74.1, y = 33.3 }, finish = { object = "Amnennar the Coldbringer" } }, -- Bring the End
  [2418] = { start = { npc = "Rigglefuzz", npcId = 2817, zone = "Badlands", map = 1418, x = 42.4, y = 52.9 } }, -- Power Stones
  [709] = { start = { npc = "Theldurin the Lost", npcId = 2785, zone = "Badlands", map = 1418, x = 51.4, y = 76.9 } }, -- Solution to Doom
  [704] = { start = { npc = "Prospector Ironband", npcId = 1344, zone = "Loch Modan", map = 1432, x = 65.9, y = 65.6 }, prereq = { 739 } }, -- Agmond's Fate
  [1360] = { start = { npc = "Krom Stoutarm", npcId = 6294, zone = "Dun Morogh", map = 1426, x = 63.0, y = 22.6 } }, -- Reclaimed Treasures
  [722] = { start = { npc = "Hammertoe Grez", zone = "Loch Modan", map = 1432, x = 37.3, y = 85.8 }, prereq = { 721 } }, -- Amulet of Secrets
  [2240] = { start = { npc = "Baelog", npcId = 6906, inside = true, entrance = { zone = "Badlands", map = 1418, x = 35.2, y = 10.3 } }, finish = { npc = "Prospector Stormpike", npcId = 1356 }, prereq = { 2398 } }, -- The Hidden Chamber
  [1139] = { start = { npc = "Advisor Belgrum", npcId = 2918, zone = "Dun Morogh", map = 1426, x = 63.5, y = 22.6 } }, -- The Lost Tablets of Will
  [17] = { start = { npc = "Ghak Healtouch", npcId = 1470, zone = "Loch Modan", map = 1432, x = 37.1, y = 49.4 } }, -- Uldaman Reagent Run
  [2199] = { start = { npc = "Talvash del Kissel", npcId = 6826, zone = "Dun Morogh", map = 1426, x = 56.9, y = 21.7 }, prereq = { 2198 } }, -- Lore for a Price
  [2198] = { start = { item = 7666, itemName = "Shattered Necklace" } }, -- The Shattered Necklace
  [2204] = { start = { npc = "Talvash's Scrying Bowl", inside = true, entrance = { zone = "Badlands", map = 1418, x = 35.2, y = 10.3 } } }, -- Restoring the Necklace
  [2361] = { start = { npc = "Talvash del Kissel", zone = "Dun Morogh", map = 1426, x = 56.9, y = 21.7 } }, -- Restoring the Necklace
  [2201] = { start = { npc = "Remains of a Paladin", inside = true, entrance = { zone = "Badlands", map = 1418, x = 35.2, y = 10.3 } } }, -- Find the Gems
  [2279] = { start = { object = "The Discs of Norgannon", objectId = 131474, inside = true, entrance = { zone = "Badlands", map = 1418, x = 35.2, y = 10.3 } }, finish = { npc = "Explorers' League" }, prereq = { 2280 } }, -- The Platinum Discs
  [2342] = { start = { npc = "Patrick Garrett", npcId = 5651, zone = "Undercity", map = 1458, x = 62.3, y = 48.6 } }, -- Reclaimed Treasures
  [2202] = { start = { npc = "Jarkal Mossmeld", npcId = 6868, zone = "Badlands", map = 1418, x = 2.4, y = 46.1 }, prereq = { 2258 } }, -- Uldaman Reagent Run
  [2283] = { start = { npc = "Dran Droffers", npcId = 6986, zone = "Orgrimmar", map = 1454, x = 59.6, y = 36.5 } }, -- Necklace Recovery
  [2338] = { start = { npc = "Jarkal Mossmeld", npcId = 6868, zone = "Badlands", map = 1418, x = 2.4, y = 46.1 }, prereq = { 2284 } }, -- Translating the Journal
  [2340] = { start = { npc = "Jarkal Mossmeld", zone = "Badlands", map = 1418, x = 2.4, y = 46.1 } }, -- Deliver the Gems
  [2339] = { start = { npc = "Jarkal Mossmeld", npcId = 6868, zone = "Badlands", map = 1418, x = 2.4, y = 46.1 } }, -- Find the Gems and Power Source
  [2341] = { start = { npc = "Dran Droffers", zone = "Orgrimmar", map = 1454, x = 59.6, y = 36.5 } }, -- Necklace Recovery, Take 3
  [2280] = { start = { object = "The Discs of Norgannon", objectId = 131474, inside = true, entrance = { zone = "Badlands", map = 1418, x = 35.2, y = 10.3 } }, finish = { npc = "Sage in Thunder Bluff" }, prereq = { 2279 } }, -- The Platinum Discs
  [2865] = { start = { npc = "Tran'rek", npcId = 7876, zone = "Tanaris", map = 1446, x = 51.6, y = 26.8 }, prereq = { 2864 } }, -- Scarab Shells
  [3042] = { start = { npc = "Trenton Lighthammer", npcId = 7804, zone = "Tanaris", map = 1446, x = 51.4, y = 28.8 } }, -- Troll Temper
  [2846] = { start = { npc = "Tabetha", npcId = 6546, zone = "Dustwallow Marsh", map = 1445, x = 46.1, y = 57.1 }, prereq = { 2861 } }, -- Tiara of the Deep
  [2768] = { start = { npc = "Chief Engineer Bilgewhizzle", npcId = 7407, zone = "Tanaris", map = 1446, x = 52.5, y = 28.5 } }, -- Divino-matic Rod
  [3527] = { start = { npc = "Yeh'kinya", npcId = 8579, zone = "Tanaris", map = 1446, x = 67.0, y = 22.4 }, prereq = { 3520 } }, -- The Prophecy of Mosh'aru
  [2770] = { start = { npc = "Wizzle Brassbolts", npcId = 4453, zone = "Thousand Needles", map = 1441, x = 78.1, y = 77.1 }, prereq = { 2769 } }, -- Gahz'rilla
  [2991] = { start = { npc = "Thadius Grimshade", zone = "Blasted Lands", map = 1419, x = 66.9, y = 19.5 } }, -- Nekrum's Medallion
  [7067] = { start = { npc = "Centaur Pariah", npcId = 13717, zone = "Desolace", map = 1443, x = 50.4, y = 86.7 } }, -- The Pariah's Instructions
  [7028] = { start = { npc = "Willow", npcId = 13656, zone = "Desolace", map = 1443, x = 62.2, y = 39.6 } }, -- Twisted Evils
  [7044] = { start = { npc = "Cavindra", zone = "Desolace", map = 1443, x = 32.1, y = 64.0 } }, -- Legends of Maraudon
  [7046] = { start = { npc = "Celebras the Redeemed", npcId = 13716, inside = true, entrance = { zone = "Desolace", map = 1443, x = 29.1, y = 62.9 } } }, -- The Scepter of Celebras
  [7066] = { start = { npc = "Zaetar's Spirit", inside = true, entrance = { zone = "Desolace", map = 1443, x = 29.1, y = 62.9 } } }, -- Seed of Life
  [7070] = { start = { npc = "Archmage Tervosh", npcId = 4967, zone = "Dustwallow Marsh", map = 1445, x = 66.4, y = 49.3 } }, -- Shadowshard Fragments
  [7041] = { start = { npc = "Talendria", npcId = 11715, zone = "Desolace", map = 1443, x = 68.5, y = 8.9 } }, -- Vyletongue Corruption
  [7065] = { start = { npc = "Keeper Marandis", npcId = 13698, zone = "Desolace", map = 1443, x = 63.8, y = 10.7 } }, -- Corruption of Earth and Seed
  [7068] = { start = { npc = "Uthel'nay", npcId = 7311, zone = "Orgrimmar", map = 1454, x = 39.2, y = 86.3 } }, -- Shadowshard Fragments
  [7029] = { start = { npc = "Vark Battlescar", npcId = 11823, zone = "Desolace", map = 1443, x = 23.2, y = 70.3 } }, -- Vyletongue Corruption
  [7064] = { start = { npc = "Selendra", npcId = 13699, zone = "Desolace", map = 1443, x = 26.9, y = 77.7 } }, -- Corruption of Earth and Seed
  [1446] = { start = { npc = "Atal'ai Exile", npcId = 5598, zone = "The Hinterlands", map = 1425, x = 33.8, y = 75.2 } }, -- Jammal'an the Prophet
  [3528] = { start = { npc = "Yeh'kinya", npcId = 8579, zone = "Tanaris", map = 1446, x = 67.0, y = 22.4 }, prereq = { 3527 } }, -- The God Hakkar
  [3446] = { start = { npc = "Marvon Rivetseeker", zone = "Tanaris", map = 1446, x = 52.7, y = 45.9 } }, -- Into the Depths
  [3447] = { start = { npc = "Marvon Rivetseeker", zone = "Tanaris", map = 1446, x = 52.7, y = 45.9 } }, -- Secret of the Circle
  [3373] = { start = { item = 10454, itemName = "Essence of Eranikus" }, finish = { object = "Essence Font", objectId = 148512 } }, -- The Essence of Eranikus
  [1475] = { start = { npc = "Brohann Caskbelly", npcId = 5384, zone = "Stormwind City", map = 1453, x = 69.5, y = 40.4 }, prereq = { 1469 } }, -- Into The Temple of Atal'Hakkar
  [1445] = { start = { npc = "Fel'zerul", npcId = 1443, zone = "Swamp of Sorrows", map = 1435, x = 47.9, y = 54.8 }, prereq = { 1444 } }, -- The Temple of Atal'Hakkar
  [4146] = { start = { npc = "Liv Rizzlefix", zone = "The Barrens", map = 1413, x = 62.4, y = 38.7 } }, -- Zapper Fuel
  [4083] = { start = { object = "Spectral Chalice", objectId = 164869, inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } } }, -- The Spectral Chalice
  [3802] = { start = { npc = "Franclorn Forgewright", zone = "Burning Steppes", map = 1428, x = 29.0, y = 28.9 } }, -- Dark Iron Legacy
  [4136] = { start = { npc = "Yuka Screwspigot", zone = "Burning Steppes", map = 1428, x = 66.1, y = 22.0 } }, -- Ribbly Screwspigot
  [4201] = { start = { npc = "Mistress Nagmara", npcId = 9500, inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } } }, -- The Love Potion
  [4123] = { start = { npc = "Maxwort Uberglint", npcId = 9536, zone = "Burning Steppes", map = 1428, x = 65.2, y = 23.9 } }, -- The Heart of the Mountain
  [4024] = { start = { npc = "Cyrus Therepentous", npcId = 9459, zone = "Burning Steppes", map = 1428, x = 95.1, y = 31.6 } }, -- A Taste of Flame
  [9015] = { start = { npc = "Falrin Treeshaper", inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } }, prereq = { 8950 } }, -- The Challenge
  [7604] = { start = { itemName = "Thorium Brotherhood Contract" } }, -- A Binding Contract
  [4242] = { start = { npc = "Marshal Windsor", inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } } }, -- Abandoned Hope
  [4263] = { start = { npc = "Jalinda Sprig", zone = "Burning Steppes", map = 1428, x = 85.4, y = 70.1 }, finish = { npc = "Lord Incendius", npcId = 9017 }, prereq = { 4262 } }, -- Incendius!
  [4126] = { start = { npc = "Ragnar Thunderbrew", npcId = 1267, zone = "Dun Morogh", map = 1426, x = 46.8, y = 52.4 }, prereq = { 4128 } }, -- Hurley Blackbreath
  [4286] = { start = { npc = "Oralius", npcId = 9177, zone = "Burning Steppes", map = 1428, x = 84.6, y = 68.7 } }, -- The Good Stuff
  [4264] = { start = { itemName = "A Crumpled Up Note" } }, -- A Crumpled Up Note
  [4282] = { start = { npc = "Marshal Windsor", npcId = 9023, inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } }, prereq = { 4264 } }, -- A Shred of Hope
  [4322] = { start = { npc = "Marshal Windsor", inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } } }, -- Jail Break!
  [4362] = { start = { npc = "King Magni Bronzebeard", zone = "Dun Morogh", map = 1426, x = 57.4, y = 30.1 }, finish = { npc = "Emperor Dagran Thaurissan", npcId = 9019 } }, -- The Fate of the Kingdom
  [4363] = { start = { npc = "Princess Moira Bronzebeard", inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } } }, -- The Princess's Surprise
  [4081] = { start = { npc = "WANTED", zone = "Badlands", map = 1418, x = 3.7, y = 47.4 } }, -- KILL ON SIGHT: Dark Iron Dwarves
  [7201] = { start = { npc = "Shadowmage Vivian Lagrave", zone = "Badlands", map = 1418, x = 2.9, y = 47.8 } }, -- The Last Element
  [3907] = { start = { npc = "Thunderheart", npcId = 9084, zone = "Badlands", map = 1418, x = 3.3, y = 48.3 }, prereq = { 3906 } }, -- Disharmony of Fire
  [4003] = { start = { npc = "Thrall", zone = "Orgrimmar", map = 1454, x = 31.7, y = 37.8 } }, -- The Royal Rescue
  [4004] = { start = { npc = "Princess Moira Bronzebeard", inside = true, entrance = { zone = "Searing Gorge", map = 1427, x = 27.1, y = 72.5 } }, finish = { npc = "Thrall", npcId = 4949, zone = "Orgrimmar", map = 1454, x = 31.7, y = 37.8 }, prereq = { 3981, 3982, 4001, 4002, 4003 } }, -- The Princess Saved?
  [4082] = { start = { npc = "KILL ON SIGHT", zone = "Badlands", map = 1418, x = 3.9, y = 46.7 } }, -- KILL ON SIGHT: High Ranking Dark Iron Officials
  [4134] = { start = { npc = "Shadowmage Vivian Lagrave", npcId = 4133, zone = "Badlands", map = 1418, x = 2.9, y = 47.8 } }, -- Lost Thunderbrew Recipe
  [4132] = { start = { npc = "Warlord Goretooth", npcId = 9077, zone = "Badlands", map = 1418, x = 5.8, y = 47.5 } }, -- Operation: Death to Angerforge
  [4121] = { start = { npc = "Grark Lorkrub", zone = "Burning Steppes", map = 1428, x = 40.2, y = 34.2 } }, -- Precarious Predicament
  [4063] = { start = { npc = "Lotwil Veriatus", zone = "Badlands", map = 1418, x = 25.9, y = 44.9 } }, -- The Rise of the Machines
  [7441] = { start = { npc = "Azj'Tordin", npcId = 14355, zone = "Feralas", map = 1444, x = 76.9, y = 37.3 } }, -- Pusillin and the Elder Azj'Tordin
  [7499] = { start = { itemName = "Codex of Defense" } }, -- Codex of Defense
  [7505] = { start = { item = 18363, itemName = "Frost Shock and You" } }, -- Frost Shock and You
  [7498] = { start = { itemName = "Garona: A Study on Stealth and Treachery" } }, -- Garona: A Study on Stealth and Treachery
  [7502] = { start = { itemName = "Harnessing Shadows" } }, -- Harnessing Shadows
  [7504] = { start = { itemName = "Holy Bologna: What the Light Won't Tell You" } }, -- Holy Bologna: What the Light Won't Tell You
  [7500] = { start = { item = 18358, itemName = "The Arcanist's Cookbook" } }, -- The Arcanist's Cookbook
  [7506] = { start = { itemName = "The Emerald Dream" } }, -- The Emerald Dream...
  [7503] = { start = { item = 18361, itemName = "The Greatest Race of Hunters" }, finish = { npc = "Shen'dralar" } }, -- The Greatest Race of Hunters
  [7501] = { start = { item = 18359, itemName = "The Light and How to Swing It" } }, -- The Light and How To Swing It
  [1318] = {  }, -- Unfinished Gordok Business
  [5528] = { start = { npc = "Stomper Kreeg", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } } }, -- The Gordok Taste Test
  [8948] = { start = { npc = "Anthion Harmon", zone = "Eastern Plaguelands", map = 1423, x = 26.1, y = 11.3 }, finish = { npc = "Falrin Treeshaper", npcId = 16032, inside = true }, prereq = { 8947 } }, -- Anthion's Old Friend
  [8949] = { start = { npc = "Falrin Treeshaper", npcId = 16032, inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } }, prereq = { 8948 } }, -- Falrin's Vendetta
  [8950] = { start = { npc = "Falrin Treeshaper", npcId = 16032, inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } }, prereq = { 8949 } }, -- The Instigator's Enchantment
  [8967] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Left Piece of Lord Valthalak's Amulet
  [8990] = { start = { npc = "Bodley", zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Right Piece of Lord Valthalak's Amulet
  [7463] = { start = { npc = "Lorekeeper Lydros", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } } }, -- Arcane Refreshment
  [7507] = { start = { itemName = "Foror's Compendium of Dragon Slaying" } }, -- Foror's Compendium
  [7508] = { start = { itemName = "A Dull and Flat Elven Blade" } }, -- The Forging of Quel'Serrar
  [7488] = { start = { npc = "Latronicus Moonspear", npcId = 7877, zone = "Feralas", map = 1444, x = 30.4, y = 46.2 }, prereq = { 7494 } }, -- Lethtendris's Web
  [7462] = { start = { npc = "Shen'dralar Ancient", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } }, prereq = { 7461 } }, -- The Treasure of the Shen'dralar
  [7489] = { start = { npc = "Talo Thornhoof", zone = "Feralas", map = 1444, x = 76.2, y = 43.8 } }, -- Lethtendris's Web
  [7877] = { start = { npc = "Shen'dralar Ancient", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } }, prereq = { 7461 } }, -- The Treasure of the Shen'dralar
  [4788] = { start = { npc = "Prospector Ironboot", zone = "Tanaris", map = 1446, x = 66.9, y = 24.0 } }, -- The Final Tablets
  [4862] = { start = { npc = "Kibler", npcId = 10260, zone = "Burning Steppes", map = 1428, x = 65.9, y = 21.9 } }, -- En-Ay-Es-Tee-Why
  [4729] = { start = { npc = "Kibler", npcId = 10260, zone = "Burning Steppes", map = 1428, x = 65.9, y = 21.9 } }, -- Kibler's Exotic Pets
  [5047] = { start = { npc = "Finkle Einhorn", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Finkle Einhorn, At Your Service!
  [4866] = { start = { npc = "Ragged John", zone = "Burning Steppes", map = 1428, x = 65.0, y = 23.8 } }, -- Mother's Milk
  [5127] = { start = { npc = "Lorax", zone = "Winterspring", map = 1452, x = 63.8, y = 73.8 } }, -- The Demon Forge
  [4867] = { start = { npc = "Warosh", npcId = 10799, inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Urok Doomhowl
  [4735] = { start = { npc = "Tinkee Steamboil", npcId = 10267, zone = "Burning Steppes", map = 1428, x = 65.2, y = 24.0 } }, -- Egg Collection
  [4734] = { start = { npc = "Tinkee Steamboil", npcId = 4907, zone = "Burning Steppes", map = 1428, x = 65.2, y = 24.0 } }, -- Egg Freezing
  [4742] = { start = { npc = "Vaelan", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Seal of Ascension
  [4743] = { start = { npc = "Vaelan", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } }, prereq = { 4742 } }, -- Seal of Ascension
  [5160] = { start = { npc = "Awbee", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- The Matron Protectorate
  [8995] = { start = { npc = "Bodley", zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- Mea Culpa, Lord Valthalak
  [8966] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Left Piece of Lord Valthalak's Amulet
  [8989] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Right Piece of Lord Valthalak's Amulet
  [5001] = { start = { npc = "Bijou", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Bijou's Belongings
  [5002] = { start = { npc = "Bijou", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Message to Maxwell
  [4701] = { start = { npc = "Helendis Riverhorn", zone = "Burning Steppes", map = 1428, x = 85.8, y = 68.9 } }, -- Put Her Down
  [5089] = { start = { item = 12780, itemName = "General Drakkisath's Command" }, finish = { npc = "Marshal Maxwell", npcId = 9560, zone = "Burning Steppes", map = 1428, x = 84.7, y = 69.0 } }, -- General Drakkisath's Command
  [5081] = { start = { npc = "Marshal Maxwell", npcId = 9560, zone = "Burning Steppes", map = 1428, x = 84.7, y = 69.0 }, prereq = { 5002 } }, -- Maxwell's Mission
  [4765] = { start = { npc = "Mayara Brightwing", zone = "Burning Steppes", map = 1428, x = 84.8, y = 69.1 } }, -- Delivery to Ridgewell
  [4764] = { start = { npc = "Mayara Brightwing", npcId = 9565, zone = "Burning Steppes", map = 1428, x = 84.8, y = 69.1 }, prereq = { 4766 } }, -- Doomrigger's Clasp
  [4982] = { start = { npc = "Bijou", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Bijou's Belongings
  [4983] = { start = { npc = "Bijou", inside = true, entrance = { zone = "Burning Steppes", map = 1428, x = 33.0, y = 25.2 } } }, -- Bijou's Reconnaissance Report
  [4724] = { start = { npc = "Galamav the Marksman", zone = "Badlands", map = 1418, x = 6.0, y = 47.7 } }, -- The Pack Mistress
  [6569] = { start = { npc = "Myranda the Hag", npcId = 11872, zone = "Western Plaguelands", map = 1422, x = 50.8, y = 77.8 }, prereq = { 6568 } }, -- Oculus Illusions
  [4903] = { start = { itemName = "Warlord Goretooth's Command" } }, -- Warlord's Command
  [5518] = { start = { npc = "Knot Thimblejack", npcId = 14338, inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } } }, -- The Gordok Ogre Suit
  [5525] = { start = { npc = "Knot Thimblejack", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } } }, -- Free Knot!
  [7461] = { start = { npc = "Shen'dralar Ancient", inside = true, entrance = { zone = "Feralas", map = 1444, x = 62.0, y = 33.3 } } }, -- The Madness Within
  [5529] = { start = { npc = "Betina Bigglezink", npcId = 11035, zone = "Eastern Plaguelands", map = 1423, x = 71.7, y = 49.9 } }, -- Plagued Hatchlings
  [5382] = { start = { npc = "Eva Sarkhoff", npcId = 11216, zone = "Western Plaguelands", map = 1422, x = 70.2, y = 73.7 } }, -- Doctor Theolen Krastinov, the Butcher
  [5384] = { start = { npc = "Eva Sarkhoff", npcId = 11216, zone = "Western Plaguelands", map = 1422, x = 70.2, y = 73.7 }, prereq = { 5515 } }, -- Kirtonos the Herald
  [5515] = { start = { npc = "Eva Sarkhoff", npcId = 11216, zone = "Western Plaguelands", map = 1422, x = 70.2, y = 73.7 }, prereq = { 5382 } }, -- Krastinov's Bag of Horrors
  [5531] = { start = { npc = "Leonid Barthalomew the Revered", zone = "Eastern Plaguelands", map = 1423, x = 71.9, y = 48.3 } }, -- Betina Bigglezink
  [4771] = { start = { npc = "Betina Bigglezink", zone = "Eastern Plaguelands", map = 1423, x = 71.7, y = 49.9 } }, -- Dawn's Gambit
  [5466] = { start = { npc = "Magistrate Marduke", npcId = 11286, zone = "Western Plaguelands", map = 1422, x = 70.6, y = 74.1 }, prereq = { 5465 } }, -- The Lich, Ras Frostwhisper
  [8969] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Left Piece of Lord Valthalak's Amulet
  [8992] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Right Piece of Lord Valthalak's Amulet
  [5343] = { start = { npc = "Weldon Barov", npcId = 11023, zone = "Western Plaguelands", map = 1422, x = 43.5, y = 83.7 } }, -- Barov Family Fortune
  [5341] = { start = { npc = "Alexi Barov", zone = "Tirisfal Glades", map = 1420, x = 83.1, y = 71.6 } }, -- Barov Family Fortune
  [5848] = { start = { npc = "Artist Renfray", zone = "Western Plaguelands", map = 1422, x = 65.8, y = 75.4 } }, -- Of Love and Family
  [5125] = { start = { npc = "Aurius", inside = true, entrance = { zone = "Eastern Plaguelands", map = 1423, x = 26.1, y = 10.4 } } }, -- Aurius' Reckoning
  [5243] = { start = { npc = "Leonid Barthalomew the Revered", npcId = 11036, zone = "Eastern Plaguelands", map = 1423, x = 71.9, y = 48.3 } }, -- Houses of the Holy
  [5213] = { start = { npc = "Betina Bigglezink", npcId = 11035, zone = "Eastern Plaguelands", map = 1423, x = 71.7, y = 49.9 }, prereq = { 5212 } }, -- The Active Agent
  [5251] = { start = { npc = "Duke Nicholas Zverenhoff", zone = "Eastern Plaguelands", map = 1423, x = 71.6, y = 50.1 } }, -- The Archivist
  [5214] = { start = { npc = "Smokey LaRue", zone = "Eastern Plaguelands", map = 1423, x = 70.9, y = 48.4 } }, -- The Great Fras Siabi
  [5282] = { start = { npc = "Egan", zone = "Eastern Plaguelands", map = 1423, x = 11.4, y = 26.6 } }, -- The Restless Souls
  [5262] = { start = { item = 13250, itemName = "Head of Balnazzar" }, finish = { npc = "Duke Nicholas Zverenhoff", npcId = 11039, zone = "Eastern Plaguelands", map = 1423, x = 71.6, y = 50.1 } }, -- The Truth Comes Crashing Down
  [5463] = { start = { npc = "Leonid Barthalomew the Revered", zone = "Eastern Plaguelands", map = 1423, x = 71.9, y = 48.3 } }, -- Menethil's Gift
  [8945] = { start = { npc = "Anthion Harmon", zone = "Eastern Plaguelands", map = 1423, x = 26.1, y = 11.3 }, finish = { npc = "Ysida Freed", npcId = 16031 }, prereq = { 8930 } }, -- Dead Man's Plea
  [8968] = { start = { npc = "Bodley", npcId = 16033, zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Left Piece of Lord Valthalak's Amulet
  [8991] = { start = { npc = "Bodley", zone = "Burning Steppes", map = 1428, x = 32.3, y = 25.8 } }, -- The Right Piece of Lord Valthalak's Amulet
  [5263] = { start = { npc = "Duke Nicholas Zverenhoff", zone = "Eastern Plaguelands", map = 1423, x = 71.6, y = 50.1 }, prereq = { 5262 } }, -- Above and Beyond
  [5212] = { start = { npc = "Betina Bigglezink", npcId = 11035, zone = "Eastern Plaguelands", map = 1423, x = 71.7, y = 49.9 } }, -- The Flesh Does Not Lie
  [6163] = { start = { npc = "Nathanos Blightcaller", zone = "Eastern Plaguelands", map = 1423, x = 22.2, y = 63.5 }, finish = { object = "Ramstein the Gorger" } }, -- Ramstein
  [6502] = { start = { npc = "Haleh", zone = "Winterspring", map = 1452, x = 54.5, y = 51.2 } }, -- Drakefire Amulet
  [5102] = { start = { npc = "Marshal Maxwell", npcId = 9560, zone = "Burning Steppes", map = 1428, x = 84.7, y = 69.0 }, finish = { npc = "General Drakkisath", npcId = 10363 }, prereq = { 5089 } }, -- General Drakkisath's Demise
  [6602] = { start = { npc = "Rexxar", zone = "Feralas", map = 1444, x = 46.4, y = 18.2 } }, -- Blood of the Black Dragon Champion
  [4974] = { start = { npc = "Thrall", zone = "Orgrimmar", map = 1454, x = 31.7, y = 37.8 } }, -- For The Horde!
  [4768] = { start = { npc = "Shadowmage Vivian Lagrave", zone = "Badlands", map = 1418, x = 2.9, y = 47.8 }, prereq = { 4769 } }, -- The Darkstone Tablet
}
end)()
end)

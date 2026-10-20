-- Oasis: Demo-Daten zum Ausprobieren (/oa demo, /oa demo aus)
-- Alles bleibt lokal: nur Store.merge, Datensaetze tragen demo=true und eine "demo-"-ID,
-- Comm schickt sie nie an die Gilde.
-- Live-Simulation: Mitglieder loggen ein/aus, laufen ueber die Karte, leveln, sterben,
-- finden Beute und suchen Gruppen - wie ein normaler Gildenabend.
local ADDON, ns = ...
local L = ns.L
local Store = ns.Store

local Demo = {}
ns.Demo = Demo

-- Name, Klasse, Level, Gebiet (UiMapID), online, Rollen, Berufe
local PEOPLE = {
    { "Grukthar", "WARRIOR", 34, 1413, true, "t", "Schmiedekunst/210/225/164+Bergbau/225/225/186" },
    { "Zul'mira", "PRIEST", 31, 1440, true, "h", "Schneiderei/180/225/197+Verzauberkunst/160/225/333" },
    { "Mokrash", "HUNTER", 28, 1442, true, "d", "Kuerschnerei/150/225/393+Lederverarbeitung/140/225/165" },
    { "Tavira", "MAGE", 37, 1441, true, "d", "Schneiderei/215/225/197+Verzauberkunst/200/225/333" },
    { "Hoknar", "SHAMAN", 22, 1454, true, "hd", "Alchemie/120/150/171+Kraeuterkunde/140/150/182" },
    { "Vex'ra", "ROGUE", 40, 1424, false, "d", "Ingenieurskunst/230/300/202+Bergbau/240/300/186" },
    { "Bramok", "DRUID", 26, 1421, false, "thd", "Kraeuterkunde/130/150/182+Alchemie/110/150/171" },
    { "Shazira", "WARLOCK", 19, 1411, false, "d", "Schneiderei/95/150/197" },
    { "Drogbar", "WARRIOR", 44, 1445, true, "td", "Bergbau/260/300/186+Schmiedekunst/245/300/164" },
    { "Ka'lesh", "SHAMAN", 41, 1434, true, "h", "Lederverarbeitung/230/300/165+Kuerschnerei/250/300/393" },
    { "Murgul", "PALADIN", 1, 1454, false, "", "" },
    { "Thrallia", "HUNTER", 33, 1443, true, "d", "Ingenieurskunst/190/225/202+Bergbau/200/225/186" },
    { "Grimzog", "ROGUE", 29, 1413, true, "d", "Alchemie/170/225/171+Kraeuterkunde/185/225/182" },
    { "Nakira", "PRIEST", 47, 1446, true, "h", "Schneiderei/270/300/197+Verzauberkunst/255/300/333" },
    { "Brokk", "WARRIOR", 16, 1411, true, "t", "Bergbau/90/150/186+Schmiedekunst/80/150/164" },
    { "Yenzi", "MAGE", 52, 1444, true, "d", "Schneiderei/290/300/197+Erste Hilfe/300/300/129" },
    { "Oggrim", "DRUID", 38, 1417, false, "th", "Kraeuterkunde/220/225/182+Alchemie/210/225/171" },
    { "Seraxa", "WARLOCK", 35, 1437, true, "d", "Schneiderei/200/225/197+Verzauberkunst/190/225/333" },
    { "Harnak", "SHAMAN", 12, 1412, true, "hd", "Kuerschnerei/60/75/393+Lederverarbeitung/55/75/165" },
    { "Vol'tar", "HUNTER", 60, 1418, false, "d", "Ingenieurskunst/300/300/202+Bergbau/300/300/186" },
    { "Ragna", "WARRIOR", 25, 1456, true, "t", "Bergbau/140/150/186+Kraeuterkunde/120/150/182" },
    { "Zzaja", "ROGUE", 43, 1434, false, "d", "Lederverarbeitung/240/300/165+Kuerschnerei/260/300/393" },
    { "Uktar", "PRIEST", 21, 1421, true, "h", "Schneiderei/110/150/197+Erste Hilfe/150/150/129" },
    { "Morgra", "MAGE", 30, 1458, false, "d", "Verzauberkunst/180/225/333+Schneiderei/170/225/197" },
}
local ONOTES = { [3] = "Twink: Morgra", [6] = "Raidlead Mi/Fr", [13] = "Probezeit bis 10.10.", [16] = "Bankverwaltung" }
local GROUPS = { [1] = "g4", [4] = "g4", [9] = "i5", [10] = "i5", [14] = "i5", [21] = "g2" }
local BIRTHDAYS = { [2] = "today", [12] = "03.11.", [16] = "24.12.", [9] = "17.02." }
local DEMO_BADGES = {
    [1] = "crafter:2+leader:2+pack:2+bosscrew:1", [2] = "angel:2+helper:1+punctual:2+hugs:3+welcome:1",
    [3] = "graveyard:2+unlucky:1+pack:1", [4] = "chat:3+cheer:2+voter:1+owl:1", [5] = "carry:1+hugs:1",
    [9] = "bosscrew:2+pack:3+loyal:2", [10] = "angel:1+trader:2+postman:1", [12] = "party:2+gambler:1+dice:1",
    [14] = "angel:3+carry:2+welcome:2+loyal:1", [16] = "lucky:2+dice:2+highroller:1+rooster:1",
    [18] = "chat:1+owl:2+unlucky:2", [21] = "party:1+hugs:2",
}
local R = {
    [2660] = "Rauer Wetzstein@2862", [2665] = "Grober Wetzstein@2863", [2674] = "Schwerer Wetzstein@2871",
    [3116] = "Grober Gewichtsstein@3240", [3491] = "Grosses Bronzemesser@3848", [9918] = "Fester Wetzstein@7964",
    [2963] = "Leinenstoffballen@2996", [3839] = "Seidenstoffballen@4305", [3813] = "Kleiner Seidenrucksack@4245",
    [18401] = "Runenstoffballen@14048", [7418] = "Armschiene - Schwache Gesundheit", [7457] = "Armschiene - Schwache Ausdauer",
    [13846] = "Armschiene - Geringe Willenskraft", [2152] = "Leichtes Ruestungsset@2304", [20648] = "Mittleres Leder@2319",
    [3780] = "Schweres Ruestungsset@4265", [10487] = "Dickes Ruestungsset@8173", [2330] = "Schwacher Heiltrank@118",
    [2337] = "Geringer Heiltrank@858", [3170] = "Schwaches Trollblut@3382", [3447] = "Heiltrank@929",
    [3922] = "Handvoll Kupferbolzen@4359", [3929] = "Grobes Sprengpulver@4364", [3946] = "Schweres Sprengpulver@4377",
    [12585] = "Festes Sprengpulver@10505", [3275] = "Leinenverband@1251", [3277] = "Schwerer Leinenverband@2581",
    [7928] = "Seidenverband@6450", [10840] = "Magiestoffverband@8544", [18629] = "Runenstoffverband@14529",
}
local DEMO_RECIPES = {
    [1] = { Schmiedekunst = { 2660, 2665, 2674, 3116, 3491, 9918 } },
    [2] = { Schneiderei = { 2963, 3839, 3813 }, Verzauberkunst = { 7418, 7457 } },
    [3] = { Lederverarbeitung = { 2152, 20648, 3780 } },
    [4] = { Schneiderei = { 2963, 3839, 3813 }, Verzauberkunst = { 7418, 13846 } },
    [5] = { Alchemie = { 2330, 2337, 3170 } },
    [6] = { Ingenieurskunst = { 3922, 3929, 3946, 12585 } },
    [9] = { Schmiedekunst = { 2674, 9918, 3491 } },
    [10] = { Lederverarbeitung = { 3780, 10487, 2152 } },
    [12] = { Ingenieurskunst = { 3922, 3929, 3946 } },
    [13] = { Alchemie = { 2337, 3447, 2330 } },
    [14] = { Schneiderei = { 3839, 18401, 3813 } },
    [16] = { Schneiderei = { 18401, 3839 }, ["Erste Hilfe"] = { 18629, 10840, 7928 } },
    [18] = { Schneiderei = { 3839, 3813 } },
    [23] = { ["Erste Hilfe"] = { 3275, 3277, 7928 } },
}
local function seedRecipes()
    for i, profs in pairs(DEMO_RECIPES) do
        local out = {}
        for prof, ids in pairs(profs) do
            out[prof] = {}
            for _, id in ipairs(ids) do out[prof][id] = R[id] end
        end
        ns.db.recipes[ns.fullName(PEOPLE[i][1])] = { hash = "demo", u = ns.now(), profs = out, demo = true }
    end
    if ns.Crafting then ns.Crafting.dirty = true end
end

-- Quests im (Demo-)Questlog - nur Anzeige, werden nie geteilt
local DEMO_QUESTS = {
    { id = 881, title = "Echeyakee", zone = "Brachland" },
    { id = 870, title = "Die vergessenen Teiche", zone = "Brachland" },
    { id = 887, title = "Südmeerfreibeuter", zone = "Brachland" },
    { id = 1062, title = "Ziegenwärter", zone = "Steinkrallengebirge" },
    { id = 6548, title = "Rache an meinem Dorf", zone = "Steinkrallengebirge", done = true },
    { id = 1489, title = "Hamuuls Befehl", zone = "Brachland" },
}
function Demo.Quests()
    local out = {}
    for _, q in ipairs(DEMO_QUESTS) do out[#out + 1] = { id = q.id, title = q.title, zone = q.zone, done = q.done, demo = true, lvl = q.lvl or math.max(1, (UnitLevel("player") or 10) + (q.id % 9) - 4) } end
    return out
end
local DEMO_QS = { [3] = "881,870", [13] = "881,887,1489", [15] = "870", [19] = "887,1062", [5] = "1062,6548", [21] = "1489", [7] = "881" }
local DEMO_ALLIES = {
    { "Kalthar-Everlook", "WARRIOR", 33, 3, "super Tank, sehr ruhig", true },
    { "Minzblatt-Venoxis", "DRUID", 29, 2, "Heilerin, will evtl. in eine Gilde", false },
    { "Grobbel-Everlook", "ROGUE", 31, 1, "", false },
    { "Sanjira-Lakeshire", "PRIEST", 35, 4, "hat uns im Kloster gerettet", true },
    { "Teldrin-Venoxis", "MAGE", 27, 1, "", false },
}
local RANKS = { [1] = "Offizier", [9] = "Offizier", [14] = "Offizier", [20] = "Veteran", [16] = "Veteran" }
local ITEMS = {
    shadowfang = "|cff0070dd|Hitem:1482::::::::|h[Shadowfang]|h|r",
    crescent = "|cff0070dd|Hitem:6505::::::::|h[Crescent Staff]|h|r",
    smite = "|cff0070dd|Hitem:7230::::::::|h[Smite's Mighty Hammer]|h|r",
    cape = "|cff1eff00|Hitem:6630::::::::|h[Seedcloud Buckler]|h|r",
}
-- Beute fuer die Live-Simulation (Stufe ab, Link)
local LIVE_LOOT = {
    { 18, "|cff0070dd|Hitem:6340::::::::|h[Fenrus' Hide]|h|r", "Burg Schattenfang" },
    { 25, "|cff0070dd|Hitem:6905::::::::|h[Reef Axe]|h|r", "Tiefschwarze Grotte" },
    { 30, "|cff0070dd|Hitem:7719::::::::|h[Raging Berserker's Helm]|h|r", "Scharlachrotes Kloster" },
    { 33, "|cff0070dd|Hitem:7720::::::::|h[Whitemane's Chapeau]|h|r", "Scharlachrotes Kloster" },
    { 38, "|cff0070dd|Hitem:10775::::::::|h[Carapace of Tuten'kash]|h|r", "Huegel der Klingenhauer" },
    { 43, "|cff0070dd|Hitem:9379::::::::|h[Sang'thraze the Deflector]|h|r", "Uldaman" },
    { 45, "|cffa335ee|Hitem:9372::::::::|h[Sul'thraze the Lasher]|h|r", "Zul'Farrak" },
    { 10, "|cff1eff00|Hitem:15405::::::::|h[Shucking Gloves]|h|r", "" },
}
local LIVE_BOSS = { { 18, "Arugal" }, { 24, "Aku'mai" }, { 32, "Hochinquisitor Weisstraene" }, { 36, "Amnennar der Kaeltebringer" }, { 44, "Archaedas" }, { 46, "Haeuptling Ukorz Sandskalp" } }
local LIVE_KILLER = { "Sturz", "Kolkar-Pirscher", "Allianz-Spieler", "Wildtatzenjaeger", "Ertrinken", "Oger-Zauberer", "Harpyien-Windhexe", "Skorpid-Schrecken", "Lava" }
local LIVE_LFG = { { 17, "Burg Schattenfang" }, { 22, "Tiefschwarze Grotte" }, { 30, "Kloster Bibliothek" }, { 36, "Kloster Waffenkammer + Kathedrale" }, { 40, "Uldaman" }, { 44, "Zul'Farrak" }, { 48, "Maraudon" } }

local function nm(i) return ns.fullName(PEOPLE[i][1]) end
-- Namen + Klassen der Demo-Gilde (fuer den Raid-Simulator, Core\Diagnostics\RaidSim.lua)
function Demo.People()
    local out = {}
    for i, p in ipairs(PEOPLE) do out[i] = { name = nm(i), class = p[2], level = p[3], roles = p[6] } end
    return out
end
-- Horde-Volk je Klasse (Orc 2, Untoter 5, Tauren 6, Troll 8)
local DEMO_RACE = { WARRIOR = 2, PRIEST = 5, HUNTER = 6, MAGE = 8, SHAMAN = 6, ROGUE = 5, DRUID = 6, WARLOCK = 2, PALADIN = 2 }
-- Beispieltexte in der Sprache des Nutzers: Deutsch steht im Code, jede andere Sprache nimmt die englische Fassung
-- (Modules/DemoSeeds/TextsEN.lua). Zusammengesetzte Felder ("Name@id", "Beruf/1/2/3+Beruf/..", "0{Item{5{..}")
-- werden abschnittsweise ersetzt. Kennungen und die Vorlagen der Chronik (tk, uebersetzt die Anzeige) bleiben.
local KEEP = { tk = true, id = true, who = true, by = true, kind = true, hash = true }
function Demo.Text(s)
    local t = ns.DemoEN
    if not t or ns.lang == "de" or type(s) ~= "string" then return s end
    local v = t[s]
    if v then return v end
    if s:find("[{}@/+]") then return (s:gsub("[^{}@/+]+", function(part) return t[part] end)) end
    return s
end
function Demo.Localize(rec, depth)
    if ns.lang == "de" or type(rec) ~= "table" or not ns.DemoEN then return rec end
    depth = depth or 0
    if depth > 6 then return rec end
    local rename
    for k, v in pairs(rec) do
        if type(v) == "table" then
            Demo.Localize(v, depth + 1)
        elseif type(v) == "string" and not KEEP[k] then
            local n = Demo.Text(v)
            if n ~= v then rec[k] = n end
        end
        -- Berufe stehen als Schluessel (Rezepte je Beruf)
        if type(k) == "string" and ns.DemoEN[k] and rec[ns.DemoEN[k]] == nil then
            rename = rename or {}
            rename[k] = ns.DemoEN[k]
        end
    end
    for k, n in pairs(rename or {}) do
        rec[n], rec[k] = rec[k], nil
    end
    return rec
end
-- alles ausserhalb des Stores, was die Demo angelegt hat (Mitglieder, Rezepte, Mitspieler ...): Tabellen mit demo = true
local function localizeTables(t, depth, seen)
    if type(t) ~= "table" or depth > 4 or seen[t] then return end
    seen[t] = true
    if rawget(t, "demo") == true then Demo.Localize(t) return end
    for _, v in pairs(t) do
        if type(v) == "table" then localizeTables(v, depth + 1, seen) end
    end
end
function Demo.LocalizeAll()
    if ns.lang == "de" or not ns.DemoEN then return end
    local seen = { [ns.db.store or {}] = true }   -- Store-Saetze uebersetzt put() schon
    localizeTables(ns.db, 0, seen)
    if ns.char then localizeTables(ns.char, 0, seen) end
end

local function put(name, rec)
    Demo.Localize(rec)
    rec.demo = true
    rec.u = rec.u or ns.now()
    rec.by = rec.by or rec.who or ns.me()
    Store.merge(name, rec)
end

-- 0.5.692: weitere Demo-Daten aus eigenen Dateien (Modules/DemoSeeds/*.lua) - je Bereich eine Datei.
-- seed(ctx) laeuft beim Laden der Demo, clean() beim Entfernen (nur fuer Daten ausserhalb des Stores noetig;
-- Store-Saetze mit demo=true bzw. "demo-"-ID raeumt Demo.Remove ohnehin weg).
Demo.SEEDS = {}
function Demo.AddSeed(name, seed, clean)
    Demo.SEEDS[#Demo.SEEDS + 1] = { name = name, seed = seed, clean = clean }
end
local function runSeeds()
    local ctx = { put = put, nm = nm, people = PEOPLE, race = DEMO_RACE, now = ns.now(), me = ns.me() }
    for _, d in ipairs(Demo.SEEDS) do
        local ok, e = pcall(d.seed, ctx)
        if not ok then ns.err("Demo " .. tostring(d.name), e) end
    end
end

function Demo.IsActive() return ns.db and ns.db.demo == true end

-- veraenderlicher Zustand je Person (bleibt ueber /reload erhalten)
local function state()
    local s = ns.db.demoPeople
    if type(s) ~= "table" or #s ~= #PEOPLE then
        s = {}
        for i, p in ipairs(PEOPLE) do
            s[i] = { lvl = p[3], map = p[4], on = p[5], x = 0.3 + math.random() * 0.4, y = 0.3 + math.random() * 0.4,
                dx = (math.random() - 0.5) * 0.006, dy = (math.random() - 0.5) * 0.006, off = p[5] and 0 or math.random(1, 9) }
        end
        s[8].off, s[11].off, s[24].off = 41, 0, 62
        ns.db.demoPeople = s
    end
    return s
end

local function zoneOf(mapID)
    return ns.zoneName and ns.zoneName(mapID, "") or ""
end

-- Gildenliste um Demo-Mitglieder ergaenzen (aus Radar.readRoster aufgerufen)
function Demo.InjectRoster(list, by)
    if not Demo.IsActive() then return 0, 0 end
    local st = state()
    local total, online = 0, 0
    for i, p in ipairs(PEOPLE) do
        local full, s = nm(i), st[i]
        if not by[full] then
            local m = {
                name = full, rank = L[RANKS[i] or "Mitglied"], rankIndex = RANKS[i] and 1 or 3,
                level = s.lvl, zone = (s.on and (i == 5 or i == 15 or i == 19) and ns.safe(GetRealZoneText())) or zoneOf(s.map), note = "", online = s.on, class = p[2], demo = true,
                offDays = (not s.on) and s.off or nil, onote = ONOTES[i] or "",
            }
            list[#list + 1] = m
            by[full] = m
            total = total + 1
            if s.on then online = online + 1 end
        end
    end
    return total, online
end

local function msString(lvl, now, i)
    -- Tempo je Person (Sekunden pro Level, steigt mit dem Level), dazu ein kleiner Versatz
    local pace = 9000 + ((i or 1) * 2741) % 14000
    local ms = {}
    for l = 10, lvl, 10 do
        local back = 0
        for x = l, lvl - 1 do back = back + pace * (1 + x / 30) end
        ms[#ms + 1] = l .. "@" .. math.floor(now - back - ((i or 1) * 977) % 3600)
    end
    return table.concat(ms, "+")
end

local function seedMembers()
    local now, st = ns.now(), state()
    for i, p in ipairs(PEOPLE) do
        ns.db.members[nm(i)] = {
            demo = true, v = ns.version, lvl = st[i].lvl, class = p[2], zone = zoneOf(st[i].map), profs = p[7],
            ilvl = 20 + st[i].lvl, ms = msString(st[i].lvl, now, i), rl = p[6], seen = now, map = true,
            bd = DEMO_BADGES[i] or "",
            st = ({ [4] = "chat=640,hugs=12", [2] = "rez=14,hugs=41,groupMin=380", [9] = "groupMin=910,zones=22",
                [16] = "fish=180,nightDays=2,jumps=5200", [18] = "nightDays=9,chat=210", [12] = "jumps=8800,zones=31" })[i] or "",
            nc = (i == 8 or i == 11) or nil, main = i == 7 and nm(3) or (i == 24 and nm(4) or nil),
            gs = st[i].on and GROUPS[i] or "", qs = DEMO_QS[i],
            gb = BIRTHDAYS[i] == "today" and date("%d.%m", now) or (BIRTHDAYS[i] and BIRTHDAYS[i]:sub(1, 5)) or nil,
            -- Aussehen + Oasis-Rang fuer Dashboard (Held der Woche, Rekorde)
            rc = DEMO_RACE[p[2]] or 2, sx = i % 2, orx = 600 + st[i].lvl * 140 + (i * 337) % 900,
        }
    end
    seedRecipes()
    -- Mitspieler von ausserhalb der Gilde
    ns.db.allies = ns.db.allies or {}
    for k, a in ipairs(DEMO_ALLIES) do
        local ex = ns.db.allies[a[1]]
        if ex and ex.demo then ex.demoOnline = (k == 1 or k == 2) or nil end
        if not ns.db.allies[a[1]] then
            ns.db.allies[a[1]] = { class = a[2], lvl = a[3], count = a[4], note = a[5], fav = a[6] or nil,
                last = now - k * 20000, zone = ({ "Brachland", "Steinkrallengebirge", "Eschental" })[(k % 3) + 1], demo = true,
                demoOnline = (k == 1 or k == 2) or nil }
        end
    end
    -- Spielzeit + Level-Verlauf der letzten Tage (fuer Tageszeit und Level-Tempo)
    if ns.Members then
        local play, hist = ns.Members.Store()
        for i, p in ipairs(PEOPLE) do
            local full, lvl = nm(i), st[i].lvl
            local peak = ({ 20, 19, 21, 12, 17, 22, 18, 20 })[(i % 8) + 1]
            local e = { d = {}, h = {}, demo = true }
            for d = 0, 6 do
                if (i + d) % 3 ~= 0 or st[i].on then
                    e.d[ns.Members.DayKey(now - d * 86400)] = (d == 0 and st[i].on) and math.random(1800, 12000) or math.random(1200, 14000)
                end
            end
            for k = -2, 2 do e.h[(peak + k) % 24] = math.random(4000, 20000) end
            e.h[(peak + 12) % 24] = math.random(0, 1500)
            play[full] = e
            local gain = (lvl < 60 and lvl > 1) and (i % 4) + ((i % 3 == 0) and 3 or 0) or 0
            local h = { demo = true }
            for d = 7, 0, -1 do h[ns.Members.DayKey(now - d * 86400)] = math.max(1, lvl - math.floor(gain * d / 7)) end
            h.demo = nil
            hist[full] = h
        end
    end
end

local function seedBank(now, me)
    put("bank", { id = "demo-tab-1", n = 1, name = "Allgemein", icon = "Interface\\Icons\\INV_Misc_Bag_10", items = "1:4245:1,2:4245:1,3:4245:1,4:4241:1,5:4241:1,6:4241:1,7:4241:1,8:804:1,9:804:1,10:4599:20,11:4599:20,12:4599:20,13:4599:20,14:4599:20,15:4599:20,16:1205:13,17:1205:20,18:1205:18,19:1205:20,20:2455:5,21:2455:5,22:2455:5,23:2455:5,24:2455:5,25:6948:1,26:5173:5,27:5173:5,28:6265:5,29:6265:5,30:6265:5,31:4306:12,32:4306:14,33:2589:10,34:2589:20,35:2589:20", who = nm(2), ts = now - 900 })
    put("bank", { id = "demo-tab-2", n = 2, name = "Stoffe & Leder", icon = "Interface\\Icons\\INV_Fabric_Silk_01", items = "1:2589:20,2:2589:20,3:2589:11,4:2589:14,5:2589:20,6:2589:18,7:2589:20,8:2589:17,9:2592:20,10:2592:20,11:2592:20,12:2592:10,13:2592:10,14:2592:20,15:2592:15,16:4306:20,17:4306:15,18:4306:15,19:4306:20,20:4306:20,21:4306:20,22:4306:20,23:4306:20,24:4306:20,25:4338:13,26:4338:20,27:4338:17,28:4338:20,29:4338:17,30:4338:20,31:14047:20,32:14047:20,33:14047:20,34:2996:10,35:2996:10,36:4305:9,37:4305:10,38:4305:10,39:2318:20,40:2318:20,41:2318:20,42:2318:20,43:2318:12,44:2319:13,45:2319:20,46:2319:12,47:2319:20,48:2319:20,49:2319:20,50:4234:20,51:4234:20,52:4234:20,53:4234:20,54:4304:20,55:4304:20,56:4304:20,57:783:5,58:783:10", who = nm(2), ts = now - 1800 })
    put("bank", { id = "demo-tab-3", n = 3, name = "Kräuter & Tränke", icon = "Interface\\Icons\\INV_Potion_51", items = "1:765:20,2:765:20,3:765:18,4:765:12,5:2447:20,6:2447:20,7:2447:20,8:2447:15,9:2447:20,10:785:20,11:785:20,12:785:20,13:785:20,14:2450:20,15:2450:20,16:2450:20,17:3820:20,18:3820:16,19:3820:20,20:3355:11,21:3355:20,22:3356:20,23:3356:20,24:3818:20,25:3818:20,26:3818:20,27:8831:10,28:8831:8,29:118:5,30:118:4,31:118:4,32:858:5,33:858:4,34:858:4,35:858:4,36:929:5,37:929:3,38:929:5,39:929:5,40:929:5,41:1710:4,42:1710:4,43:1710:5,44:3385:5,45:3385:5,46:3385:4,47:3827:5,48:3827:5", who = nm(2), ts = now - 2700 })
    put("bank", { id = "demo-tab-4", n = 4, name = "Erze & Steine", icon = "Interface\\Icons\\INV_Ore_Copper_01", items = "1:2770:20,2:2770:20,3:2770:20,4:2770:15,5:2770:20,6:2771:14,7:2771:10,8:2771:20,9:2771:20,10:2772:20,11:2772:20,12:2772:20,13:2772:20,14:2772:17,15:3858:20,16:3858:20,17:3858:14,18:2840:20,19:2840:20,20:2840:20,21:2840:18,22:2841:20,23:2841:18,24:2841:20,25:3575:15,26:3575:11,27:3575:20,28:3860:20,29:3860:20,30:2836:20,31:2836:20,32:2836:13,33:2838:20,34:2838:16,35:2838:20,36:2838:20,37:7912:20,38:7912:20,39:7912:17,40:818:5,41:818:3,42:1210:5,43:1210:4,44:1705:5", who = nm(2), ts = now - 3600 })
    put("bank", { id = "demo-tab-5", n = 5, name = "Offiziere", icon = "Interface\\Icons\\INV_Misc_Key_14", items = "1:1482:1,2:6505:1,3:7230:1,4:7719:1,5:10775:1,6:9379:1,7:14048:10,8:14048:10,9:12360:1,10:12360:1", who = nm(2), ts = now - 4500 })
    put("bank", { id = "demo-money", amount = 3127450, who = nm(2), ts = now - 900 })
    put("banklog", { id = "demo-log-2", tab = "2", e = "deposit/Nakira/4306/40/" .. (now - 3600) .. "/2/0#withdraw/Mokrash/2319/20/" .. (now - 18000) .. "/2/0#deposit/Zul'mira/4305/10/" .. (now - 43200) .. "/2/0#withdraw/Tavira/4338/20/" .. (now - 72000) .. "/2/0#deposit/Yenzi/14047/20/" .. (now - 122400) .. "/2/0#deposit/Ka'lesh/4234/20/" .. (now - 172800) .. "/2/0#deposit/Seraxa/4306/20/" .. (now - 198000) .. "/2/0#deposit/Mokrash/2318/20/" .. (now - 396000) .. "/2/0", who = nm(2), ts = now })
    put("banklog", { id = "demo-log-4", tab = "4", e = "deposit/Grukthar/2840/20/" .. (now - 10800) .. "/4/0#deposit/Drogbar/3575/20/" .. (now - 93600) .. "/4/0#withdraw/Grukthar/2838/20/" .. (now - 144000) .. "/4/0#deposit/Grukthar/7912/20/" .. (now - 324000) .. "/4/0#deposit/Drogbar/3860/20/" .. (now - 468000) .. "/4/0", who = nm(2), ts = now })
    put("banklog", { id = "demo-log-3", tab = "3", e = "deposit/Hoknar/858/10/" .. (now - 28800) .. "/3/0#move/Zul'mira/8831/10/" .. (now - 108000) .. "/3/3#withdraw/Hoknar/118/5/" .. (now - 216000) .. "/3/0#deposit/Nakira/1710/5/" .. (now - 252000) .. "/3/0", who = nm(2), ts = now })
    put("banklog", { id = "demo-log-5", tab = "5", e = "withdraw/Yenzi/1482/1/" .. (now - 360000) .. "/5/0", who = nm(2), ts = now })
    put("banklog", { id = "demo-log-money", tab = "money", e = "deposit/Nakira/0/250000/" .. (now - 7200) .. "#deposit/Grukthar/0/100000/" .. (now - 21600) .. "#withdraw/Zul'mira/0/50000/" .. (now - 32400) .. "#repair/Drogbar/0/18450/" .. (now - 54000) .. "#deposit/Yenzi/0/500000/" .. (now - 100800) .. "#deposit/Tavira/0/75000/" .. (now - 158400) .. "#withdraw/Grukthar/0/120000/" .. (now - 252000) .. "#deposit/Hoknar/0/30000/" .. (now - 345600) .. "", who = nm(2), ts = now })
end

local function seedStore()
    local now, me = ns.now(), ns.me()
    -- Chronik
    local chr = {
        { "level", 2, "hat Level %s erreicht", { 31 }, 900 },
        { "loot", 1, "hat erbeutet:", nil, 2400, { item = ITEMS.smite, zone = "Die Todesminen" } },
        { "boss", 4, "und Gruppe besiegen %s (%s)", { "Arugal", "3:12" }, 5400 },
        { "level", 4, "hat Level %s erreicht", { 37 }, 7200 },
        { "loot", 3, "hat erbeutet:", nil, 11000, { item = ITEMS.crescent, zone = "Die Hoehlen des Wehklagens" } },
        { "legacy", 6, "hat eine Legacy-Challenge geschafft:", { 0 }, 20000, { item = "Einsamer Wolf" } },
        { "level", 5, "hat Level %s erreicht", { 22 }, 30000 },
        { "badge", 1, "hat ein Abzeichen erhalten:", { "crafter", 2 }, 42000 },
        { "loot", 6, "hat erbeutet:", nil, 60000, { item = ITEMS.shadowfang, zone = "Burg Schattenfang" } },
        { "level", 1, "hat Level %s erreicht", { 34 }, 90000 },
        { "level", 8, "hat Level %s erreicht", { 19 }, 120000 },
        { "level", 16, "hat Level %s erreicht", { 50 }, 160000 },
        { "level", 14, "hat Level %s erreicht", { 47 }, 200000 },
        { "boss", 9, "und Gruppe besiegen %s (%s)", { "Gahz'rilla", "4:48" }, 230000 },
        { "level", 20, "hat Level %s erreicht", { 60 }, 300000 },
        { "loot", 20, "hat erbeutet:", nil, 330000, { item = ITEMS.shadowfang, zone = "Burg Schattenfang" } },
        -- Nakira: aktivste der Woche (Held der Woche im Dashboard)
        { "boss", 14, "und Gruppe besiegen %s (%s)", { "Archaedas", "6:41" }, 250000 },
        { "badge", 14, "hat ein Abzeichen erhalten:", { "angel", 3 }, 260000 },
        { "level", 14, "hat Level %s erreicht", { 46 }, 400000 },
        -- Raid-Abende (Barrow Deeps)
        { "boss", 1, "und Gruppe besiegen %s (%s)", { "Grabwächter Moradin", "5:02" }, 6 * 86400 + 3000 },
        { "boss", 1, "und Gruppe besiegen %s (%s)", { "Die Knochenhexe", "6:47" }, 6 * 86400 + 1200 },
        { "boss", 9, "und Gruppe besiegen %s (%s)", { "Varrok der Verschlinger", "8:15" }, 13 * 86400 },
        { "loot", 16, "hat erbeutet:", nil, 13 * 86400 - 600, { item = LIVE_LOOT[7][2], zone = "Barrow Deeps" } },
    }
    for i, c in ipairs(chr) do
        local rec = { id = "demo-chr-" .. i, kind = c[1], who = nm(c[2]), tk = c[3], ts = now - c[5] }
        for k, v in ipairs(c[4] or {}) do rec["a" .. k] = tostring(v) end
        for k, v in pairs(c[6] or {}) do rec[k] = v end
        put("chronicle", rec)
    end
    -- neue Mitglieder (Beitritt in den letzten Tagen -> "NEU" in der Liste)
    for k, j in ipairs({ { 19, 2 }, { 15, 5 }, { 11, 0.3 } }) do
        put("chronicle", { id = "demo-join-" .. k, kind = "guild", who = nm(j[1]), tk = "tritt der Gilde bei - willkommen!", ts = now - j[2] * 86400 })
    end
    -- Termine + Anmeldungen
    local ev = {
        { "demo-ev1", "Burg Schattenfang", "Burg Schattenfang", 2 * 3600, 5 },
        { "demo-ev2", "Scharlachrotes Kloster: Friedhof + Bibliothek", "Scharlachrotes Kloster", 26 * 3600, 5 },
        { "demo-ev3", "Gildenabend: Todeswuerfeln in Orgrimmar", "", 3 * 86400, 40 },
    }
    for _, e in ipairs(ev) do put("events", { id = e[1], title = e[2], inst = e[3], ts = now + e[4], max = e[5], who = nm(1) }) end
    -- Raid-Abende (20er): naechster Freitag fast voll, Folgewoche erst angelaufen
    put("events", { id = "demo-raid1", title = "Barrow Deeps - Wochenraid", inst = "Barrow Deeps", ts = now + 2 * 86400 + 5400, max = 20, kind = "raid",
        desc = "Flaschen + Reparatur mitbringen, Invite 19:45", who = nm(6) })
    put("events", { id = "demo-raid2", title = "Barrow Deeps - Wochenraid", inst = "Barrow Deeps", ts = now + 9 * 86400 + 5400, max = 20, kind = "raid",
        desc = "Flaschen + Reparatur mitbringen, Invite 19:45", who = nm(6) })
    put("events", { id = "demo-raid3", title = "Onyxias Hort - Gildenraid", inst = "Onyxias Hort", ts = now + 5 * 86400 + 5400, max = 40, kind = "raid",
        desc = "Feuerschutz + Feuerwiderstand mitbringen, Taktik-Karte vorher ansehen", who = nm(1) })
    for k, r in ipairs({ { 1, "tank" }, { 9, "tank" }, { 2, "heal" }, { 14, "heal" }, { 10, "heal" }, { 4, "dps" }, { 16, "dps" }, { 20, "dps" }, { 18, "dps", "maybe" } }) do
        local p = PEOPLE[r[1]]
        put("signups", { id = "demo-raid3@" .. nm(r[1]), ev = "demo-raid3", who = nm(r[1]), role = r[2], status = r[3] or "yes", class = p[2], lvl = p[3], ilvl = 20 + p[3], u = now - k * 2400 })
    end
    local rsu = {
        { 1, "tank" }, { 9, "tank" }, { 2, "heal" }, { 10, "heal" }, { 14, "heal" }, { 23, "heal", "maybe" }, { 4, "dps" }, { 6, "dps" },
        { 12, "dps" }, { 16, "dps" }, { 18, "dps" }, { 13, "dps" }, { 3, "dps" }, { 22, "dps", "maybe" }, { 20, "dps" }, { 17, "heal" },
        { 21, "tank", "no" },
    }
    for k, r in ipairs(rsu) do
        local p = PEOPLE[r[1]]
        put("signups", { id = "demo-raid1@" .. nm(r[1]), ev = "demo-raid1", who = nm(r[1]), role = r[2], status = r[3] or "yes", class = p[2], lvl = p[3], ilvl = 20 + p[3], u = now - k * 1700 })
        if k <= 6 then
            put("signups", { id = "demo-raid2@" .. nm(r[1]), ev = "demo-raid2", who = nm(r[1]), role = r[2], status = "yes", class = p[2], lvl = p[3], ilvl = 20 + p[3], u = now - k * 900 })
        end
    end
    -- Raid-Interesse (Rollen + Wunschtage)
    for k, r in ipairs({ { 5, "hd", "35" }, { 7, "thd", "157" }, { 8, "d", "5" }, { 15, "t", "356" }, { 19, "h", "35" }, { 24, "d", "57" }, { 11, "td", "6" } }) do
        put("raidint", { id = "ri-" .. nm(r[1]), roles = r[2], days = r[3], by = nm(r[1]), u = now - k * 5400 })
    end
    local su = { { "demo-ev1", 1, "tank" }, { "demo-ev1", 2, "heal" }, { "demo-ev1", 4, "dps" }, { "demo-ev2", 3, "dps" }, { "demo-ev2", 6, "dps" } }
    for _, s in ipairs(su) do
        local p = PEOPLE[s[2]]
        put("signups", { id = s[1] .. "@" .. nm(s[2]), ev = s[1], who = nm(s[2]), role = s[3], status = "yes", class = p[2], lvl = p[3] })
    end
    -- Handwerk
    put("orders", { id = "demo-ord1", recipe = "Schwerer Wetzstein", prof = "Schmiedekunst", to = nm(1), rid = 2674, item = 2871, qty = 5, note = "fuer den Raid am Freitag", from = me, status = "open", created = now - 3000, mats = true })
    put("orders", { id = "demo-ord2", recipe = "Kleiner Seidenrucksack", prof = "Schneiderei", to = "", rid = 3813, item = 4245, qty = 2, note = "", from = nm(8), status = "open", created = now - 8000, tip = 5 })
    put("orders", { id = "demo-ord3", recipe = "Heiltrank", prof = "Alchemie", to = nm(13), rid = 3447, item = 929, qty = 10, note = "", from = nm(3), status = "accepted", worker = nm(13), created = now - 20000, mats = true })
    put("orders", { id = "demo-ord4", recipe = "Schweres Ruestungsset", prof = "Lederverarbeitung", to = "", rid = 3780, item = 4265, qty = 3, note = "eilt nicht", from = nm(15), status = "open", created = now - 1500 })
    put("orders", { id = "demo-ord5", recipe = "Seidenverband", prof = "Erste Hilfe", to = nm(23), rid = 7928, item = 6450, qty = 20, note = "", from = me, status = "accepted", worker = nm(23), created = now - 5000, tip = 2 })
    put("orders", { id = "demo-ord6", recipe = "Grobes Sprengpulver", prof = "Ingenieurskunst", to = nm(6), rid = 3929, item = 4364, qty = 10, note = "", from = nm(12), status = "done", worker = nm(6), created = now - 90000 })
    put("orders", { id = "demo-ord7", recipe = "Seidenstoffballen", prof = "Schneiderei", to = nm(14), rid = 3839, item = 4305, qty = 8, note = "", from = nm(9), status = "done", worker = nm(14), created = now - 150000, tip = 3 })
    -- Gesucht
    put("wants", { id = "demo-want1", itemID = 4306, name = "Seidenstoff", qty = 40, note = "fuer Taschen", who = nm(2), created = now - 5000 })
    put("wants", { id = "demo-want2", itemID = 2589, name = "Leinenstoff", qty = 20, note = "", who = nm(8), created = now - 9000 })
    put("wants", { id = "demo-want5", itemID = 929, name = "Heiltrank", qty = 10, note = "fuer den Kloster-Run", who = nm(21), created = now - 2500, price = 1 })
    put("wants", { id = "demo-want6", itemID = 4265, name = "Schweres Ruestungsset", qty = 2, note = "", who = nm(23), created = now - 6000 })
    put("wants", { id = "demo-want7", itemID = 3575, name = "Eisenbarren", qty = 12, note = "fuer Schmiedekunst-Skill", who = nm(15), created = now - 12000, price = 2 })
    put("wants", { id = "demo-want4", itemID = 4245, name = "Kleiner Seidenrucksack", qty = 2, note = "Taschenplatz!", who = nm(19), created = now - 4000 })
    put("wants", { id = "demo-want3", itemID = 1482, name = "Shadowfang", qty = 1, note = "", who = nm(4), created = now - 40000 })
    -- Umfragen
    put("polls", { id = "demo-poll1", q = L["Which evening for the next guild run?"], o1 = L["Wednesday"], o2 = L["Friday"], o3 = L["Sunday"], multi = false, exp = now + 2 * 86400, created = now - 3600, who = nm(1) })
    for i, pick in ipairs({ "2", "2", "1", "3", "2" }) do
        put("votes", { id = "demo-poll1@" .. nm(i), poll = "demo-poll1", who = nm(i), pick = pick })
    end
    -- weitere Umfragen: Mehrfachauswahl (laeuft) + eine beendete mit Ergebnis
    put("polls", { id = "demo-poll2", q = L["What should the guild bank provide for the raid?"], o1 = L["Fire protection potions"], o2 = L["Flasks"],
        o3 = L["Buff food"], o4 = L["Repair money"], multi = true, exp = now + 4 * 86400, created = now - 7200, who = nm(6) })
    for i, pick in ipairs({ "1,2", "1", "1,3", "2,4", "1,4", "3", "1,2,3" }) do
        put("votes", { id = "demo-poll2@" .. nm(i + 1), poll = "demo-poll2", who = nm(i + 1), pick = pick })
    end
    put("polls", { id = "demo-poll3", q = L["First raid: Barrow Deeps or straight to Onyxia?"], o1 = L["Barrow Deeps"], o2 = L["Onyxia"],
        multi = false, exp = now - 2 * 86400, closed = true, created = now - 6 * 86400, who = nm(1) })
    for i, pick in ipairs({ "1", "1", "2", "1", "1", "2", "1", "1", "2", "1", "1" }) do
        put("votes", { id = "demo-poll3@" .. nm(i), poll = "demo-poll3", who = nm(i), pick = pick })
    end
    -- Beute
    put("loot", { id = "demo-loot1", item = ITEMS.smite, who = nm(1), src = "Die Todesminen", zone = "Die Todesminen", mapID = 0, ts = now - 2400, quality = 3 })
    put("loot", { id = "demo-loot2", item = ITEMS.crescent, who = nm(3), src = "Die Hoehlen des Wehklagens", zone = "Die Hoehlen des Wehklagens", mapID = 0, ts = now - 11000, quality = 3 })
    put("loot", { id = "demo-loot3", item = ITEMS.shadowfang, who = nm(6), src = "Burg Schattenfang", zone = "Burg Schattenfang", mapID = 0, ts = now - 60000, quality = 3 })
    -- Raid-Vergaben der letzten Abende (Beute-Log / Meine Beute)
    for k, d in ipairs({ { 16, 7, 13 }, { 4, 4, 13 }, { 12, 5, 6 }, { 14, 2, 6 }, { 9, 1, 6 }, { 10, 3, 20 } }) do
        local it = LIVE_LOOT[d[2]] and LIVE_LOOT[d[2]][2]
        if it then
            put("loot", { id = "demo-raidloot" .. k, item = it, who = nm(d[1]), src = "Vergabe", zone = "Barrow Deeps", mapID = 0, ts = now - d[3] * 86400 + k * 1200, quality = 4 })
        end
    end
    -- Tode
    local deaths = { { 1, 1413, 0.52, 0.31, "Brachland", "Kolkar-Pirscher", 3600 }, { 3, 1442, 0.47, 0.62, "Steinkrallengebirge", "Sturz", 7000 },
        { 3, 1413, 0.44, 0.58, "Brachland", "Rasiermaehne", 50000 }, { 8, 1411, 0.41, 0.18, "Durotar", "Brennende Klinge", 80000 },
        { 6, 1424, 0.63, 0.22, "Vorgebirge des Huegellands", "Allianz-Spieler", 120000 }, { 3, 1440, 0.26, 0.38, "Eschental", "Wildtatzenjaeger", 150000 } }
    for i, d in ipairs(deaths) do
        put("deaths", { id = "demo-death" .. i, who = nm(d[1]), mapID = d[2], x = math.floor(d[3] * 10000), y = math.floor(d[4] * 10000), zone = d[5], inst = false, killer = d[6], lvl = PEOPLE[d[1]][3], ts = now - d[7] })
    end
    seedBank(now, me)
    -- Punkte: drei Raid-Abende (Einsatz), vergebene Beute, woechentlicher Verfall
    local raiders = { 1, 2, 4, 6, 9, 10, 12, 14, 16, 18, 13, 3 }
    local nights = {
        { 20, "Barrow Deeps", { "Grabwächter Moradin", "Die Knochenhexe", "Varrok der Verschlinger" } },
        { 13, "Barrow Deeps", { "Grabwächter Moradin", "Die Knochenhexe", "Varrok der Verschlinger" } },
        { 6, "Barrow Deeps", { "Grabwächter Moradin", "Die Knochenhexe" } },
    }
    for n, night in ipairs(nights) do
        local t0 = now - night[1] * 86400
        local present = {}
        for _, i in ipairs(raiders) do if (i + n) % 5 ~= 0 then present[#present + 1] = nm(i) end end
        local who = table.concat(present, ",")
        put("points", { id = "demo-pts-start-" .. n, kind = "ep", who = who, amount = 10, reason = L["On time"], start = true, raid = night[2], ts = t0, by = nm(1) })
        for b, boss in ipairs(night[3]) do
            put("points", { id = "demo-pts-boss-" .. n .. "-" .. b, kind = "ep", who = who, amount = 10, reason = boss, raid = night[2], ts = t0 + b * 1800, by = nm(1) })
        end
        put("points", { id = "demo-pts-end-" .. n, kind = "ep", who = who, amount = 10, reason = L["Stayed until the end"], raid = night[2], ts = t0 + 3 * 3600, by = nm(1) })
        if n < 3 then put("points", { id = "demo-pts-decay-" .. n, kind = "decay", pct = 10, ts = t0 + 3 * 86400, by = nm(1) }) end
    end
    local drops = {
        { 6, ITEMS.shadowfang, 150, "need", 20 }, { 2, ITEMS.crescent, 150, "need", 20 }, { 9, ITEMS.smite, 150, "need", 13 },
        { 16, LIVE_LOOT[7][2], 100, "need", 13 }, { 4, LIVE_LOOT[4][2], 40, "need", 13 }, { 12, LIVE_LOOT[5][2], 10, "greed", 6 },
        { 14, LIVE_LOOT[2][2], 40, "need", 6 },
    }
    for k, d in ipairs(drops) do
        put("points", { id = "demo-pts-gp-" .. k, kind = "gp", who = nm(d[1]), amount = d[3], item = d[2], choice = d[4], ts = now - d[5] * 86400 + 5000, by = nm(1) })
    end
    put("points", { id = "demo-pts-adj-1", kind = "adj", who = nm(10), ep = 20, gp = 0, reason = L["Prepared flasks and buffs for everyone"], ts = now - 6 * 86400, by = nm(1) })
    -- Gruppensuche
    put("lfg", { id = "demo-lfg2", who = nm(9), title = "Zul'Farrak", note = "Treffpunkt Gadgetzan", layout = "thddd", m = nm(9) .. ":t," .. nm(12) .. ":d," .. nm(18) .. ":d," .. nm(16) .. ":d", tank = false, heal = true, dps = false, size = 5, count = 4, auto = true, open = true, lvl = 44, class = "WARRIOR", exp = now + 40 * 60 })
    put("lfg", { id = "demo-lfg3", who = nm(19), title = "Questen im Brachland", note = "", layout = "thddd", m = nm(19) .. ":h", tank = true, heal = false, dps = true, size = 5, count = 1, auto = true, open = true, lvl = 12, class = "SHAMAN", exp = now + 25 * 60 })
    put("lfg", { id = "demo-lfg1", who = nm(4), title = "Scharlachrotes Kloster Bibliothek", note = "", layout = "thddd", m = nm(4) .. ":d," .. nm(2) .. ":h," .. nm(13) .. ":d", tank = true, heal = false, dps = true, size = 5, count = 3, auto = false, open = true, lvl = 37, class = "MAGE", exp = now + 30 * 60 })
    -- Todeswuerfeln
    put("duels", { id = "demo-duel1", winner = nm(2), loser = nm(1), start = 100, stake = "10g", rolls = 7, ts = now - 20000 })
    put("duels", { id = "demo-duel2", winner = nm(2), loser = nm(3), start = 100, stake = "", rolls = 5, ts = now - 30000 })
    put("duels", { id = "demo-duel3", winner = nm(4), loser = nm(2), start = 1000, stake = "1g", rolls = 9, ts = now - 45000 })
    runSeeds()
end

------------------------------------------------------------------------
-- Live-Simulation
------------------------------------------------------------------------
local function refreshAll()
    if ns.Radar and ns.Radar.Reload then pcall(ns.Radar.Reload) end
    for _, key in ipairs({ "home", "radar", "chronicle", "raid", "crafting", "wants", "polls", "deaths", "groups", "deathroll", "map" }) do
        ns.RefreshPage(key)
    end
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
    if ns.UpdateDemoSwitch then ns.UpdateDemoSwitch() end
    -- ohne Gilde haengen die Gildenseiten an den Beispieldaten: Navigation neu aufbauen
    if ns.LayoutNav then pcall(ns.LayoutNav) end
end

-- Position des Spielers (damit ein paar Leute auch auf der Minimap neben dir stehen)
local function playerPos()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    if not x or x == 0 then return end
    return mapID, x, y
end
local NEAR = { [5] = { -0.012, 0.008 }, [15] = { 0.010, -0.006 }, [19] = { 0.004, 0.014 } }

-- alle 4 s: Leute laufen weiter, Kartenpunkte bleiben frisch
local function movePeople()
    if not (Demo.IsActive() and ns.Map and ns.Map.pos) then return end
    local st, t, now = state(), GetTime(), ns.now()
    local pm, px, py = playerPos()
    for i, s in ipairs(st) do
        local full = nm(i)
        if s.on then
            s.x, s.y = s.x + s.dx, s.y + s.dy
            if s.x < 0.15 or s.x > 0.85 then s.dx = -s.dx end
            if s.y < 0.15 or s.y > 0.85 then s.dy = -s.dy end
            if math.random() < 0.05 then s.dx, s.dy = (math.random() - 0.5) * 0.006, (math.random() - 0.5) * 0.006 end
            local mapID, x, y = s.map, s.x, s.y
            if NEAR[i] and pm then
                local o = NEAR[i]
                mapID, x, y = pm, px + o[1] + math.sin(t / 7 + i) * 0.003, py + o[2] + math.cos(t / 9 + i) * 0.003
            end
            ns.Map.pos[full] = { mapID = mapID, x = x, y = y, t = t, demo = true }
            local pr = ns.db.members[full]
            if pr then pr.seen = now end
        else
            ns.Map.pos[full] = nil
        end
    end
    ns.Map.dirty = true
end

local liveN = 0
local function liveId(kind) liveN = liveN + 1 return ("demo-live-%s-%d-%d"):format(kind, ns.now(), liveN) end
local function pick(filter)
    local st, c = state(), {}
    for i, s in ipairs(st) do if filter(i, s) then c[#c + 1] = i end end
    if #c > 0 then return c[math.random(#c)] end
end
local function countOnline()
    local n = 0
    for _, s in ipairs(state()) do if s.on then n = n + 1 end end
    return n
end
local function chronicle(i, kind, tk, args, extra)
    local rec = { id = liveId("chr"), kind = kind, who = nm(i), tk = tk, ts = ns.now() }
    for k, v in ipairs(args or {}) do rec["a" .. k] = tostring(v) end
    for k, v in pairs(extra or {}) do rec[k] = v end
    put("chronicle", rec)
end

-- ein zufaelliges Ereignis wie im echten Spiel
local EVENTS = {
    { 30, function() -- Level-Up
        local i = pick(function(_, s) return s.on and s.lvl < 60 end)
        if not i then return end
        local s = state()[i]
        s.lvl = s.lvl + 1
        local pr = ns.db.members[nm(i)]
        if pr then pr.lvl, pr.ilvl, pr.ms = s.lvl, 20 + s.lvl, msString(s.lvl, ns.now()) end
        chronicle(i, "level", "hat Level %s erreicht", { s.lvl }, { lvl = s.lvl })
    end },
    { 16, function() -- einloggen
        local i = pick(function(_, s) return not s.on and s.off < 30 end)
        if not i then return end
        local s = state()[i]
        s.on, s.off = true, 0
        pcall(ns.print, "|cffffff00" .. (L["%s is now online."]):format(ns.displayName(nm(i))) .. "|r")
    end },
    { 12, function() -- ausloggen (mindestens 10 bleiben da)
        if countOnline() <= 10 then return end
        local i = pick(function(i, s) return s.on and not NEAR[i] end)
        if not i then return end
        local s = state()[i]
        s.on, s.off = false, 0
        pcall(ns.print, "|cffffff00" .. (L["%s is now offline."]):format(ns.displayName(nm(i))) .. "|r")
    end },
    { 10, function() -- Gebietswechsel
        local i = pick(function(i, s) return s.on and not NEAR[i] end)
        if not i then return end
        local maps = { 1411, 1413, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1434, 1437, 1417, 1418, 1424, 1454, 1456 }
        state()[i].map = maps[math.random(#maps)]
        local pr = ns.db.members[nm(i)]
        if pr then pr.gs = ({ "", "", "g2", "g3" })[math.random(4)] end
    end },
    { 10, function() -- Beute
        local i = pick(function(_, s) return s.on end)
        if not i then return end
        local lvl, it = state()[i].lvl, nil
        for _, x in ipairs(LIVE_LOOT) do if lvl >= x[1] then it = x end end
        if not it then return end
        put("loot", { id = liveId("loot"), item = it[2], who = nm(i), src = it[3], zone = it[3], mapID = 0, ts = ns.now(), quality = it[2]:find("a335ee") and 4 or 3 })
        chronicle(i, "loot", "hat erbeutet:", nil, { item = it[2], zone = it[3] })
    end },
    { 7, function() -- Boss
        local i = pick(function(_, s) return s.on end)
        if not i then return end
        local lvl, b = state()[i].lvl, nil
        for _, x in ipairs(LIVE_BOSS) do if lvl >= x[1] then b = x end end
        if not b then return end
        chronicle(i, "boss", "und Gruppe besiegen %s (%s)", { b[2], ("%d:%02d"):format(math.random(1, 4), math.random(0, 59)) })
        local pr = ns.db.members[nm(i)]
        if pr then pr.gs = "i5" end
    end },
    { 8, function() -- Tod
        local i = pick(function(i, s) return s.on and not NEAR[i] end)
        if not i then return end
        local s = state()[i]
        put("deaths", { id = liveId("death"), who = nm(i), mapID = s.map, x = math.floor(s.x * 10000), y = math.floor(s.y * 10000),
            zone = zoneOf(s.map), inst = false, killer = LIVE_KILLER[math.random(#LIVE_KILLER)], lvl = s.lvl, ts = ns.now() })
    end },
    { 7, function() -- Gruppensuche
        local i = pick(function(_, s) return s.on and s.lvl >= 17 end)
        if not i then return end
        local lvl, g = state()[i].lvl, nil
        for _, x in ipairs(LIVE_LFG) do if lvl >= x[1] then g = x end end
        local need = math.random(3)
        local lead = ({ "t", "h", "d" })[need]
        local m, cnt = nm(i) .. ":" .. lead, 1
        local other = pick(function(j, s) return s.on and j ~= i end)
        if other and math.random() < 0.6 then m, cnt = m .. "," .. nm(other) .. ":d", 2 end
        put("lfg", { id = "demo-lfg-live", who = nm(i), title = g[2], note = "", layout = "thddd", m = m, tank = lead ~= "t", heal = lead ~= "h", dps = true,
            size = 5, count = cnt, auto = true, open = true, lvl = lvl, class = PEOPLE[i][2], exp = ns.now() + 20 * 60 })
    end },
}
local weightSum = 0
for _, e in ipairs(EVENTS) do weightSum = weightSum + e[1] end

local nextEvent = 0
local function tick()
    if not Demo.IsActive() then return end
    movePeople()
    if GetTime() < nextEvent then return end
    nextEvent = GetTime() + math.random(15, 35)
    local r, acc = math.random() * weightSum, 0
    for _, e in ipairs(EVENTS) do
        acc = acc + e[1]
        if r <= acc then
            local ok, err = pcall(e[2])
            if not ok then ns.err("Demo", err) end
            break
        end
    end
    refreshAll()
end

-- bei neuen Demo-Inhalten hochzaehlen: aeltere Demos werden nach /reload ergaenzt
local DEMO_VERSION = 14

function Demo.Load()
    -- 0.5.949: Beispieldaten gibt es wieder fuer alle (zum Ausprobieren und Einrichten). Sie starten nie von selbst,
    -- nur ueber /oa demo, den Schalter in den Einstellungen oder "Beispiel ansehen" - und bleiben auf diesem PC.
    ns.db.demo = true
    ns.db.demoVersion = DEMO_VERSION
    ns.db.demoPeople = nil
    ns.demoLoading = true
    local ok, err = pcall(function() seedMembers() seedStore() end)
    ns.demoLoading = false
    if not ok then ns.err("Demo", err) end
    pcall(Demo.LocalizeAll)
    movePeople()
    nextEvent = GetTime() + 8
    refreshAll()
    if ns.Admin and ns.Admin.ApplyBrand then pcall(ns.Admin.ApplyBrand, true) end   -- Logo: langer Demo-Gildenname
    if not Demo.quiet then ns.print(L["Demo data loaded (only on your client, never sent to the guild). Remove: /oa demo off"]) end
end

function Demo.Remove()
    ns.db.demo = nil
    ns.db.demoPeople = nil
    local n = 0
    for _, c in pairs(ns.db.store) do
        for id, r in pairs(c) do
            if r.demo or tostring(id):find("^demo%-") then c[id] = nil n = n + 1 end
        end
    end
    for name, p in pairs(ns.db.members) do if p.demo then ns.db.members[name] = nil end end
    for name, r in pairs(ns.db.recipes) do if r.demo then ns.db.recipes[name] = nil end end
    for name, a in pairs(ns.db.allies or {}) do if a.demo then ns.db.allies[name] = nil end end
    if ns.Crafting then ns.Crafting.dirty = true end
    if ns.db.play or ns.db.lvlHist then
        for i in ipairs(PEOPLE) do
            if ns.db.play then ns.db.play[nm(i)] = nil end
            if ns.db.lvlHist then ns.db.lvlHist[nm(i)] = nil end
        end
    end
    if ns.Map and ns.Map.pos then for name, p in pairs(ns.Map.pos) do if p.demo then ns.Map.pos[name] = nil end end end
    for _, d in ipairs(Demo.SEEDS) do if d.clean then pcall(d.clean) end end
    refreshAll()
    -- ohne Gilde: die offene Gildenseite gibt es jetzt nicht mehr
    if ns.MainShown and ns.MainShown() and ns.GuildOnly and ns.CurrentPage and ns.GuildOnly(ns.CurrentPage() or "") then
        pcall(ns.ShowPage, "home")
    end
    if ns.Admin and ns.Admin.ApplyBrand then pcall(ns.Admin.ApplyBrand, true) end   -- Logo wieder mit dem echten Namen
    if not Demo.quiet then ns.print((L["Demo data removed (%d entries)."]):format(n)) end
end

-- Sprache gewechselt, waehrend die Beispieldaten laufen: in der neuen Sprache neu anlegen
function Demo.Relang()
    if not Demo.IsActive() then return end
    Demo.quiet = true
    pcall(Demo.Remove)
    pcall(Demo.Load)
    Demo.quiet = nil
end

ns.slash.demo = function(arg)
    arg = (arg or ""):lower()
    if arg == "aus" or arg == "off" or arg == "weg" then Demo.Remove() else Demo.Load() end
end

ns.Every(4, tick)
-- nach /reload: Demo laeuft weiter, Leute stehen gleich wieder auf der Karte
ns.Listen("LOGIN", function()
    if not Demo.IsActive() then return end
    ns.After(2, function()
        pcall(seedMembers)
        -- Demo aus einer aelteren Oasis-Version: neue Bereiche (Bank, Rezepte ...) nachtragen
        if (ns.db.demoVersion or 0) < DEMO_VERSION then
            ns.demoLoading = true
            local ok, err = pcall(seedStore)
            ns.demoLoading = false
            if not ok then ns.err("Demo", err) end
            ns.db.demoVersion = DEMO_VERSION
            ns.print(L["Demo data updated to the latest version."])
        end
        pcall(Demo.LocalizeAll)
        movePeople()
        refreshAll()
    end)
end)

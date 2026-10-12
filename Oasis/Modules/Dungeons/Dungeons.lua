-- Oasis: Dungeons
-- Hauptquelle sind Blizzards eigene Client-Daten: Dungeonkompass (Dungeons, Bosse, Beute),
-- Dungeonfinder (Stufenbereiche) und die Questlogs der Gilde (Dungeon-Quests).
-- Ist "Forever Dungeon Journal" (Exehn) installiert, nutzt Oasis zusaetzlich dessen
-- gepflegte Quest- und Beutedaten (nur gelesen, nichts davon ist in Oasis enthalten).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Dungeons", function()   -- Modul Dungeons (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Dungeons = {}
ns.Dungeons = Dungeons

local function fdj()
    local t = _G.ForeverDungeonJournal_NS
    if type(t) == "table" and type(t.DB) == "table" then return t end
end
Dungeons.HasJournal = function() return fdj() ~= nil end

local function norm(s)
    return (tostring(s or ""):lower():gsub("^die ", ""):gsub("^der ", ""):gsub("^the ", ""):gsub("[%s%p]", ""))
end

------------------------------------------------------------------------
-- Blizzard: Stufenbereiche aus dem Dungeonfinder
------------------------------------------------------------------------
local lfgLevels
local function lfgLevelsByName()
    if lfgLevels then return lfgLevels end
    lfgLevels = {}
    local ids = {}
    if C_LFGInfo and C_LFGInfo.GetAllEntriesForCategory and LE_LFG_CATEGORY_LFD then
        local ok, list = pcall(C_LFGInfo.GetAllEntriesForCategory, LE_LFG_CATEGORY_LFD)
        if ok and type(list) == "table" then ids = list end
    end
    if #ids == 0 and GetLFDChoiceOrder then
        local ok, list = pcall(GetLFDChoiceOrder)
        if ok and type(list) == "table" then ids = list end
    end
    for _, id in ipairs(ids) do
        local ok, name, _, _, minL, maxL, recL = pcall(GetLFGDungeonInfo, id)
        if ok and name and minL then lfgLevels[norm(name)] = { lo = minL, hi = maxL or recL or minL } end
    end
    return lfgLevels
end

------------------------------------------------------------------------
-- Blizzard: Dungeons und Bosse aus dem Dungeonkompass
------------------------------------------------------------------------
local ejList, ejTried = nil, 0
local function scanEJ()
    -- leeres Ergebnis nicht fuer immer merken: Daten kommen im Client teils spaeter
    if ejList and (#ejList > 0 or GetTime() - ejTried < 60) then return ejList end
    ejTried = GetTime()
    lfgLevels = nil
    ejList = {}
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return ejList end
    local levels = lfgLevelsByName()
    local haveLFG = next(levels) ~= nil
    local okT, numTiers = pcall(EJ_GetNumTiers)
    numTiers = okT and numTiers or 0
    local seen = {}
    for tier = 1, numTiers do
        local tierName = EJ_GetTierInfo and select(1, EJ_GetTierInfo(tier)) or ""
        pcall(EJ_SelectTier, tier)
        for _, isRaid in ipairs({ false, true }) do
            for i = 1, 200 do
                local ok, id, name = pcall(EJ_GetInstanceByIndex, i, isRaid)
                if not ok or not id then break end
                local lv = levels[norm(name)]
                -- Nur Classic-/Forever-Inhalte: ueber den Dungeonfinder, sonst ueber den Tier-Namen
                local classicTier = tier == 1 or tostring(tierName):find("Forever") or tostring(tierName):find("Classic")
                local keep = lv ~= nil or classicTier or (not haveLFG and numTiers <= 2)
                if keep and not seen[id] then
                    seen[id] = true
                    local okI, _, desc, _, button, _, _, areaMapID = pcall(EJ_GetInstanceInfo, id)
                    ejList[#ejList + 1] = {
                        key = "ej:" .. id, ejID = id, name = name, raid = isRaid, tier = tierName,
                        lo = lv and lv.lo, hi = lv and lv.hi,
                        level = lv and ((lv.lo == lv.hi) and tostring(lv.lo) or (lv.lo .. "-" .. lv.hi)) or "",
                        location = isRaid and L["Schlachtzug"] or L["Dungeon"],
                        icon = okI and button or nil, mapID = okI and areaMapID or nil,
                        desc = okI and desc or "", source = "blizzard",
                    }
                end
            end
        end
    end
    table.sort(ejList, function(a, b)
        if (a.lo or 999) ~= (b.lo or 999) then return (a.lo or 999) < (b.lo or 999) end
        return a.name < b.name
    end)
    return ejList
end

-- Bosse eines Dungeons (lazy)
function Dungeons.Bosses(d)
    if d.bosses then return d.bosses end
    d.bosses = {}
    if d.source == "oasis" then
        for _, b in ipairs(d.data.bosses or {}) do
            local loot = {}
            for _, it in ipairs(b.loot or {}) do loot[#loot + 1] = { it[1], it[2], nil, it[3] } end
            d.bosses[#d.bosses + 1] = { name = b.name, loot = loot, rare = b.rare, trash = b.trash, object = b.object, level = b.level, npc = b.npc }
        end
        return d.bosses
    end
    if d.source == "journal" then
        local f = fdj()
        for _, b in ipairs(d.data.bosses or {}) do
            d.bosses[#d.bosses + 1] = { name = f.LocalizeBossName and select(2, pcall(f.LocalizeBossName, b.name)) or b.name, loot = b.loot }
        end
        return d.bosses
    end
    if not EJ_GetEncounterInfoByIndex then return d.bosses end
    pcall(EJ_SelectInstance, d.ejID)
    for i = 1, 30 do
        local ok, name, _, encounterID = pcall(EJ_GetEncounterInfoByIndex, i, d.ejID)
        if not ok or not name then break end
        d.bosses[#d.bosses + 1] = { name = name, encounterID = encounterID }
    end
    return d.bosses
end

-- Beute eines Blizzard-Dungeons einlesen (Item-Daten kommen teils verzoegert)
local lootIndex = {}
local function loadLoot(d)
    if d.source ~= "blizzard" or d.lootDone or not (EJ_SelectEncounter and EJ_GetNumLoot) then return end
    if EncounterJournal and EncounterJournal:IsShown() then return end   -- Blizzards Fenster nicht stoeren
    local getLoot = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
    if not getLoot then return end
    local missing = 0
    pcall(EJ_SelectInstance, d.ejID)
    for _, b in ipairs(Dungeons.Bosses(d)) do
        b.loot = {}
        if b.encounterID then
            pcall(EJ_SelectEncounter, b.encounterID)
            local okN, n = pcall(EJ_GetNumLoot)
            for i = 1, (okN and n or 0) do
                local ok, info = pcall(getLoot, i)
                if ok and type(info) == "table" and info.itemID then
                    b.loot[#b.loot + 1] = { info.itemID, info.name, info.slot, info.itemQuality }
                    lootIndex[info.itemID] = { boss = b.name, dungeon = d.name, key = d.key }
                    if not info.name then missing = missing + 1 end
                end
            end
        end
    end
    d.lootTries = (d.lootTries or 0) + 1
    d.lootDone = missing == 0 or d.lootTries >= 3
end
ns.On("EJ_LOOT_DATA_RECIEVED", function() ns.RefreshPage("dungeons") end)

------------------------------------------------------------------------
-- Journal von Exehn (optional)
------------------------------------------------------------------------
local function journalList()
    local f = fdj()
    if not f then return nil end
    local order = type(f.ORDER) == "table" and f.ORDER or {}
    local out = {}
    for _, key in ipairs(order) do
        local d = f.DB[key]
        if d then
            local lo, hi = tostring(d.level or ""):match("(%d+)%-?(%d*)")
            local okN, name = pcall(f.LocalizeDungeonName or function(x) return x end, key)
            local okL, locText = pcall(f.LocalizeDungeonField or function(_, _, x) return x end, key, "location", d.location or "")
            -- Journal-Schluessel mit Oasis-Karten und den deutschen/englischen Gebietsnamen verbinden.
            local own
            for _, e in ipairs(ns.DungeonData or {}) do
                if norm(key) == norm(e.name) or norm(key) == norm(e.key)
                    or (okN and (norm(name) == norm(e.name) or norm(name) == norm(e.de))) then
                    own = e
                    break
                end
            end
            out[#out + 1] = {
                key = key, name = okN and name or key, level = d.level or "", lo = tonumber(lo), hi = tonumber(hi) or tonumber(lo),
                dbKey = own and own.key, nameEN = own and own.name, nameDE = own and own.de,
                location = okL and locText or (d.location or ""), icon = d.icon, data = d, source = "journal",
            }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Oasis-eigene Dungeon-Datenbank (Modules\DungeonData.lua, aus oeffentlichen Quellen)
------------------------------------------------------------------------
local oasisList
local function dataList()
    if oasisList then return oasisList end
    oasisList = {}
    for _, e in ipairs(ns.DungeonData or {}) do
        local lo, hi = e.lo, e.hi or e.lo
        if e.status ~= "client" and lo then oasisList[#oasisList + 1] = {
            key = "db:" .. e.key, dbKey = e.key,
            name = (ns.lang == "de" and e.de) or e.name, nameEN = e.name, nameDE = e.de,
            lo = lo, hi = hi, level = lo and ((lo == hi) and tostring(lo) or (lo .. "-" .. hi)) or "",
            location = e.zone and L[e.zone] or "", faction = e.faction, icon = e.icon, data = e, source = "oasis",
            closed = e.status == "closed",
        } end
    end
    return oasisList
end

------------------------------------------------------------------------
-- Gemeinsame Abfragen
------------------------------------------------------------------------
function Dungeons.Available() return #Dungeons.List() > 0 end

-- Reihenfolge: Exehns Journal (falls da) > Oasis-Datenbank > uebrige Blizzard-Eintraege
function Dungeons.List()
    local out, have = {}, {}
    local function add(d, ...)
        for _, n in ipairs({ ... }) do if n and have[norm(n)] then return end end
        out[#out + 1] = d
        for _, n in ipairs({ ... }) do if n then have[norm(n)] = true end end
    end
    for _, d in ipairs(journalList() or {}) do add(d, d.name, d.key) end
    for _, d in ipairs(dataList()) do add(d, d.name, d.nameEN, d.nameDE) end
    for _, d in ipairs(scanEJ()) do add(d, d.name) end
    table.sort(out, function(a, b)
        if (a.lo or 999) ~= (b.lo or 999) then return (a.lo or 999) < (b.lo or 999) end
        return a.name < b.name
    end)
    return out
end
function Dungeons.Get(key)
    for _, d in ipairs(Dungeons.List()) do if d.key == key then return d end end
end

local SHORT = {
    ["Ragefire Chasm"] = "rfc", ["Hall of Thanes"] = "hot", ["The Deadmines"] = "dm",
    ["Ruins of Lordaeron"] = "rol", ["Wailing Caverns"] = "wc", ["Shadowfang Keep"] = "sfk",
    ["Blackfathom Deeps"] = "bfd",
}
local ALIAS = { dm = "deadmines", vc = "deadmines", wc = "wailing", sfk = "shadowfang", bfd = "blackfathom", rfc = "ragefire",
    hot = "thanes", rol = "lordaeron", stocks = "stockade", sm = "scarlet", rfk = "razorfen", gnomer = "gnomeregan" }

-- Dungeon aus freiem Text erkennen (Termin-Titel, Gruppensuche), deutsch oder englisch
function Dungeons.Match(text)
    if not text or text == "" then return nil end
    local t = norm(text)
    local raw = text:lower()
    local list = Dungeons.List()
    for _, d in ipairs(list) do
        for _, n in ipairs({ d.name, d.nameEN, d.nameDE }) do
            local nn = norm(n)
            if #nn > 3 and t:find(nn, 1, true) then return d end
        end
        if d.source == "journal" and t:find(norm(d.key), 1, true) then return d end
    end
    for short, word in pairs(ALIAS) do
        if raw:find("%f[%w]" .. short .. "%f[%W]") then
            for _, d in ipairs(list) do
                if norm(d.key):find(word) or norm(d.nameEN or d.name):find(word) then return d end
            end
        end
    end
end

local function journalShort(d)
    if not d then return nil end
    return SHORT[d.key] or SHORT[d.nameEN or ""]
end
function Dungeons.Open(key)
    local d = Dungeons.Get(key)
    local cmd = SlashCmdList and SlashCmdList.FOREVERDUNGEONJOURNAL
    local short = journalShort(d) or SHORT[key]
    if not cmd or not short then return false end
    return pcall(cmd, short)
end
function Dungeons.CanOpenJournal(d)
    return journalShort(d) ~= nil and SlashCmdList and SlashCmdList.FOREVERDUNGEONJOURNAL ~= nil or false
end

------------------------------------------------------------------------
-- Dungeon-Quests
-- Journal/Oasis-Datenbank: feste Liste. Zusaetzlich Quests, die im Questlog unter dem Dungeon-Namen
-- stehen, von allen Gildenmitgliedern mit Oasis gesammelt (Profilfeld dq = "schluessel:qid,qid;...").
------------------------------------------------------------------------
-- Dungeon-Schluessel zu einer Questlog-Ueberschrift (Gebiet), sonst nil
local zoneKeys
function Dungeons.KeyByZone(zone)
    if not zone or zone == "" then return nil end
    if not zoneKeys then
        zoneKeys = {}
        for _, d in ipairs(Dungeons.List()) do
            -- Forever nutzt abweichende deutsche Gebietsnamen.
            if (d.dbKey or d.key) == "blackfathomdeeps" then
                zoneKeys[norm("Blackfathom-Tiefe")] = d.key
                zoneKeys[norm("Blackfathom-Tiefen")] = d.key
            end
            for _, n in ipairs({ d.name, d.nameEN, d.nameDE }) do
                if n then
                    zoneKeys[norm(n)] = d.key
                    -- auch ohne Artikel ("Die Hoehlen des Wehklagens" = Unterzone "Hoehlen des Wehklagens")
                    local bare = n:gsub("^[Dd]ie ", ""):gsub("^[Dd]er ", ""):gsub("^[Dd]as ", ""):gsub("^[Tt]he ", "")
                    zoneKeys[norm(bare)] = zoneKeys[norm(bare)] or d.key
                end
            end
        end
    end
    local z = tostring(zone):gsub("^[Dd]ie ", ""):gsub("^[Dd]er ", ""):gsub("^[Dd]as ", ""):gsub("^[Tt]he ", "")
    return zoneKeys[norm(zone)] or zoneKeys[norm(z)]
end
function Dungeons.EncodeMyDungeonQuests()
    if not ns.Social then return "" end
    local byName = {}
    for _, d in ipairs(Dungeons.List()) do
        for _, n in ipairs({ d.name, d.nameEN, d.nameDE }) do if n then byName[norm(n)] = d.key end end
    end
    local groups = {}
    for _, q in ipairs(ns.Social.MyQuests()) do
        local key = byName[norm(q.zone)]
        if key then
            groups[key] = groups[key] or {}
            table.insert(groups[key], tostring(q.id))
        end
    end
    local parts = {}
    for key, ids in pairs(groups) do parts[#parts + 1] = key .. ":" .. table.concat(ids, ",") end
    return table.concat(parts, ";")
end

local function questTitle(id, fallback)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and ns.safe(t) and t ~= "" then return t end
        if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
    end
    return fallback or ("Quest #" .. id)
end

function Dungeons.Quests(d)
    local out, seen = {}, {}
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local function fits(q) return not q.faction or q.faction == "Both" or q.faction == faction end
    if d.source == "journal" then
        local f = fdj()
        for _, q in ipairs(d.data.quests or {}) do
            if fits(q) then
                local ok, name = pcall(f.LocalizeQuestField or function(_, _, x) return x end, q.id, "name", q.name)
                out[#out + 1] = { id = q.id, name = ok and name or q.name, level = q.level, giver = q.pickup }
                seen[q.id] = true
            end
        end
    elseif d.source == "oasis" then
        for _, q in ipairs(d.data.quests or {}) do
            if fits(q) then
                out[#out + 1] = { id = q.id, name = questTitle(q.id, q.name), level = q.level, min = q.min, giver = q.giver,
                    faction = q.faction, rewards = q.rewards }
                seen[q.id] = true
            end
        end
    end
    -- aus den Questlogs der Gilde
    local function add(s)
        for key, list in (s or ""):gmatch("([^;:]+):([%d,]+)") do
            local match = key == d.key or (d.ejID and tonumber(key) == d.ejID)
            if match then
                for id in list:gmatch("%d+") do
                    id = tonumber(id)
                    if not seen[id] then
                        seen[id] = true
                        out[#out + 1] = { id = id, name = questTitle(id) }
                    end
                end
            end
        end
    end
    add(Dungeons.EncodeMyDungeonQuests())
    for _, p in pairs(ns.db.members) do add(p.dq) end
    table.sort(out, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.name < b.name
    end)
    return out
end

------------------------------------------------------------------------
-- Quest-Status und Questgeber-Orte
------------------------------------------------------------------------
-- Classic-Gebiete (englischer Name -> UiMapID); der angezeigte Name kommt lokalisiert aus dem Client
local ZONES = {
    ["Elwynn Forest"] = 1429, ["Westfall"] = 1436, ["Silverpine Forest"] = 1421, ["Undercity"] = 1458,
    ["Orgrimmar"] = 1454, ["Stormwind City"] = 1453, ["Stormwind"] = 1453, ["Ironforge"] = 1455, ["Darnassus"] = 1457,
    ["Thunder Bluff"] = 1456, ["The Barrens"] = 1413, ["Barrens"] = 1413, ["Ashenvale"] = 1440, ["Durotar"] = 1411,
    ["Mulgore"] = 1412, ["Tirisfal Glades"] = 1420, ["Dun Morogh"] = 1426, ["Loch Modan"] = 1432,
    ["Redridge Mountains"] = 1433, ["Duskwood"] = 1431, ["Wetlands"] = 1437, ["Hillsbrad Foothills"] = 1424,
    ["Stonetalon Mountains"] = 1442, ["Darkshore"] = 1439, ["Teldrassil"] = 1438, ["Thousand Needles"] = 1441,
    ["Desolace"] = 1443, ["Stranglethorn Vale"] = 1434, ["Arathi Highlands"] = 1417, ["Badlands"] = 1418,
    ["Swamp of Sorrows"] = 1435, ["Alterac Mountains"] = 1416, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
    ["Feralas"] = 1444, ["The Hinterlands"] = 1425, ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428,
    ["Blasted Lands"] = 1419, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423, ["Felwood"] = 1448,
    ["Azshara"] = 1447, ["Un'Goro Crater"] = 1449, ["Winterspring"] = 1452, ["Silithus"] = 1451,
    ["Moonglade"] = 1450, ["Deadwind Pass"] = 1430,
}
Dungeons.ZONES = ZONES

local function zoneLabel(mapID, fallback)
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    return fallback or ""
end

-- "done" (erledigt) | "log" (im Questlog) | "open"
function Dungeons.QuestState(id, holders)
    local Q = C_QuestLog
    if Q and Q.IsQuestFlaggedCompleted then
        local ok, done = pcall(Q.IsQuestFlaggedCompleted, id)
        if ok and done then return "done" end
    end
    if Q and Q.GetLogIndexForQuestID then
        local ok, idx = pcall(Q.GetLogIndexForQuestID, id)
        if ok and idx then return "log" end
    end
    for _, n in ipairs(holders or {}) do if ns.isMe(n) then return "log" end end
    return "open"
end

-- Punkt (Questgeber/Abgabe) aufbereiten: kurzer Text, langer Text, Kartenziel
local function point(p, fallbackText)
    if not p then return nil end
    local out = {}
    if p.item or p.itemName then
        local name = p.item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(p.item) or p.itemName
        out.text = L["Startet durch ein Item"] .. (name and (": " .. name) or "")
        out.long = out.text .. "\n|cffa8a8a8" .. L["droppt meist im Dungeon"] .. "|r"
        return out
    end
    if p.object then
        out.text = p.object
        out.long = p.object .. "\n|cffa8a8a8" .. L["ein Objekt, meist im Dungeon"] .. "|r"
        return out
    end
    local npc = p.npc or ""
    if p.inside then
        out.text = npc .. "  ·  " .. L["im Dungeon"]
        out.long = npc .. "\n|cffa8a8a8" .. L["steht im Dungeon selbst"] .. "|r"
        -- Kartenziel: der Dungeon-Eingang
        local e = p.entrance
        if e and e.x and e.y then
            local emap = e.map or ZONES[e.zone or ""]
            if emap then
                local ez = zoneLabel(emap, e.zone)
                out.long = out.long .. "\n" .. L["Eingang:"] .. " |cffa8a8a8" .. ez .. "|r  |cff888888(" .. ("%.1f, %.1f"):format(e.x, e.y) .. ")|r"
                out.target = { mapID = emap, x = e.x / 100, y = e.y / 100, label = L["Dungeon-Eingang"], sub = ez }
                out.zoneMap = emap
            end
        end
        return out
    end
    local mapID = p.map or ZONES[p.zone or ""]
    local zone = zoneLabel(mapID, p.zone)
    out.text = npc .. (zone ~= "" and ("  ·  " .. zone) or "")
    local coords = p.x and p.y and ("%.1f, %.1f"):format(p.x, p.y) or nil
    out.long = npc .. "\n|cffa8a8a8" .. zone .. "|r" .. (coords and ("  |cff888888(" .. coords .. ")|r") or "")
    if mapID and p.x and p.y then
        out.target = { mapID = mapID, x = p.x / 100, y = p.y / 100, label = npc, sub = zone .. (coords and ("  " .. coords) or "") }
    end
    out.zoneMap = mapID
    return out
end

-- Ort einer Quest: Oasis-Ortsdaten (Koordinaten) oder Questgeber-Text aus der Dungeon-Datenbank
function Dungeons.QuestLocation(q)
    local data = ns.QuestLocations and ns.QuestLocations[q.id]
    local loc = {}
    if data and data.start then
        loc.start = point(data.start)
    elseif q.giver and q.giver ~= "" then
        local item = q.giver:match("^From the item")
        if item then
            loc.start = { text = L["Startet durch ein Item"], long = q.giver }
        else
            local npc, zone = q.giver:match("^(.-),%s*(.+)$")
            loc.start = point({ npc = npc or q.giver, zone = zone })
        end
    end
    if data and data.finish then loc.finish = point(data.finish) end
    if data and data.prereq then
        loc.prereq = {}
        for _, id in ipairs(data.prereq) do
            local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
            loc.prereq[#loc.prereq + 1] = { id = id, name = questTitle(id), done = done }
        end
    end
    return loc
end

-- Wer (Gilde, mit Oasis) hat welche Quest? -> { [questID] = { Namen } }
function Dungeons.QuestHolders(questIDs)
    local want = {}
    for _, id in ipairs(questIDs) do want[id] = {} end
    local function scan(name, qs)
        for id in (qs or ""):gmatch("%d+") do
            id = tonumber(id)
            if want[id] then table.insert(want[id], name) end
        end
    end
    scan(ns.me(), ns.Social and ns.Social.EncodeQuests() or "")
    for name, p in pairs(ns.db.members) do
        if not ns.isMe(name) then scan(name, p.qs) end
    end
    return want
end

------------------------------------------------------------------------
-- Beute-Herkunft (Tooltip) und gesuchte Beute
------------------------------------------------------------------------
local journalIndex
local function buildJournalIndex()
    if journalIndex then return journalIndex end
    journalIndex = {}
    for _, d in ipairs(dataList()) do
        for _, boss in ipairs(d.data.bosses or {}) do
            for _, it in ipairs(boss.loot or {}) do
                if type(it) == "table" and it[1] then journalIndex[it[1]] = { boss = boss.name, dungeon = d.name, key = d.key } end
            end
        end
        for _, q in ipairs(d.data.quests or {}) do
            for _, id in ipairs(q.rewards or {}) do
                if not journalIndex[id] then journalIndex[id] = { quest = questTitle(q.id, q.name), dungeon = d.name, key = d.key } end
            end
        end
    end
    local f = fdj()
    if not f then return journalIndex end
    for _, d in ipairs(journalList() or {}) do
        for _, boss in ipairs(d.data.bosses or {}) do
            local ok, bn = pcall(f.LocalizeBossName or function(x) return x end, boss.name)
            for _, it in ipairs(boss.loot or {}) do
                if type(it) == "table" and it[1] then journalIndex[it[1]] = { boss = ok and bn or boss.name, dungeon = d.name, key = d.key } end
            end
        end
        for _, q in ipairs(d.data.quests or {}) do
            for _, it in ipairs(q.rewardItems or {}) do
                if type(it) == "table" and it[1] and not journalIndex[it[1]] then
                    journalIndex[it[1]] = { quest = q.name, dungeon = d.name, key = d.key }
                end
            end
        end
    end
    return journalIndex
end
function Dungeons.Source(itemID)
    if not itemID then return nil end
    return buildJournalIndex()[itemID] or lootIndex[itemID]
end
function Dungeons.TooltipLine(itemID)
    local src = Dungeons.Source(itemID)
    if not src then return nil end
    if src.boss then return (L["Beute von %s (%s)"]):format(src.boss, src.dungeon) end
    return (L["Questbelohnung: %s (%s)"]):format(src.quest or "?", src.dungeon)
end

function Dungeons.InRange(d)
    local out = {}
    if not d.lo then return out end
    for _, m in ipairs(ns.Radar.roster) do
        if m.online and m.level >= d.lo - 2 and m.level <= (d.hi or d.lo) then out[#out + 1] = m end
    end
    return out
end
-- Wie viele Quests fuer diesen Dungeon hast du im Log? (Anzahl im Log, Anzahl bekannt)
function Dungeons.MyQuestCount(d)
    local ok, qs = pcall(Dungeons.Quests, d)
    if not ok or type(qs) ~= "table" then return 0, 0 end
    local n = 0
    for _, q in ipairs(qs) do
        local okS, s = pcall(Dungeons.QuestState, q.id)
        if okS and s == "log" then n = n + 1 end
    end
    return n, #qs
end
function Dungeons.WantedLoot(d)
    local out = {}
    for _, w in ipairs(Store.List("wants")) do
        local src = Dungeons.Source(w.itemID)
        if src and src.key == d.key then out[#out + 1] = w end
    end
    return out
end
-- Was die Gilde hier schon erbeutet hat (Beute-Log, ueber die Karten-ID des Dungeons)
function Dungeons.GuildLoot(d)
    local out = {}
    for _, x in ipairs(Store.List("loot")) do
        if (d.mapID and x.mapID == d.mapID) or (x.zone and norm(x.zone) == norm(d.name)) then out[#out + 1] = x end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- Die Seite (Karten, Boss-/Beute-/Quest-Ansicht) steht in DungeonUI.lua
Dungeons.LoadLoot = loadLoot

-- Beute aller Dungeons nach und nach im Hintergrund einlesen (fuer den Tooltip)
ns.Listen("LOGIN", function()
    if ns.db and ns.db.settings.dgPreload == false then return end
    ns.After(25, function()
        local list = scanEJ()
        local i = 0
        local ticker
        ticker = C_Timer.NewTicker(2, function()
            i = i + 1
            local d = list[i]
            if not d then ticker:Cancel() return end
            if not ns.inCombat() then pcall(loadLoot, d) end
        end)
    end)
end)

if _G.OasisAPI then
    -- Welche Gildenmitglieder (mit Oasis) haben diese Quest? -> { Namen }
    function _G.OasisAPI.GetQuestHolders(questID)
        local h = Dungeons.QuestHolders({ tonumber(questID) })
        return h[tonumber(questID)] or {}
    end
end
end)

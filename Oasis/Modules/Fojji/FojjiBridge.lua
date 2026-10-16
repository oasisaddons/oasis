-- Oasis - Zusammenarbeit mit FojjiCore (Dungeon-Journal, Karten, Routen, Wunschliste von Fojji).
-- Oasis will damit nicht konkurrieren: ist FojjiCore geladen, verweist Oasis fuer Journal/Karte/Routen dorthin und
-- bietet an, Fojjis Wunschliste in die gildenweite Oasis-Wunschliste zu uebernehmen.
-- Es werden nur oeffentliche Tabellen/Funktionen von FojjiCore AUFGERUFEN (FojjiCoreNS.DJ), nichts daraus kopiert oder veraendert.
-- Alles ist optional und nil-sicher: ohne FojjiCore (oder nach einer Aenderung dort) verhaelt sich Oasis wie bisher.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Fojji", function()   -- Modul FojjiCore (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L

local F = {}
ns.Fojji = F

local function DJ()
    if ns.db and ns.db.settings.fojjiBridge == false then return nil end
    local n = _G.FojjiCoreNS
    local d = type(n) == "table" and n.DJ
    if type(d) == "table" and type(d.ByKey) == "table" then return d end
    return nil
end
function F.Has() return DJ() ~= nil end
function F.Version() return type(_G.FojjiCore_Version) == "string" and _G.FojjiCore_Version or nil end

-- FojjiCore benennt die Dungeons teils anders als Oasis (z.B. "wailing" statt "wailingcaverns"): Oasis-Schluessel -> Fojji-Schluessel
local KEYMAP = {
    ruinsoflordaeron = "lordaeron", wailingcaverns = "wailing", shadowfangkeep = "shadowfang", blackfathomdeeps = "blackfathom",
    excavationsite = "excavation", cityofdalaran = "dalaran", razorfenkraul = "kraul", razorfendowns = "downs",
    smgraveyard = "sm_graveyard", smlibrary = "sm_library", smarmory = "sm_armory", smcathedral = "sm_cathedral",
    sunkentemple = "sunken", blackrockdepths = "brd", diremauleast = "dm_east", diremaulnorth = "dm_north", diremaulwest = "dm_west",
    stratmain = "stratholme", stratservice = "stratholme",
}
local function plain(s) return (tostring(s or ""):lower():gsub("[^a-z0-9]", "")) end
-- kennt FojjiCore diesen Dungeon? Erst der Schluessel (direkt oder ueber die Tabelle), sonst der englische Name
function F.Dungeon(key)
    local d = DJ()
    if not d or not key then return nil end
    local od = ns.Dungeons and ns.Dungeons.Get and ns.Dungeons.Get(key)
    for _, k in ipairs({ key, KEYMAP[key], od and od.dbKey, od and od.dbKey and KEYMAP[od.dbKey] }) do
        local dg = k and d.ByKey[k]
        if type(dg) == "table" then return dg end
    end
    local want = od and plain(od.nameEN or od.name) or ""
    if want ~= "" and type(d.Dungeons) == "table" then
        for _, dg in ipairs(d.Dungeons) do
            if type(dg) == "table" and plain(dg.name) == want then return dg end
        end
    end
    return nil
end

-- Fojjis Journal beim Dungeon (und, wenn bekannt, beim Boss) oeffnen. true = geoeffnet
function F.Open(key, bossName, tab)
    local d = DJ()
    local dg = F.Dungeon(key)
    local J = d and d.Journal
    if not (dg and type(J) == "table" and type(J.Open) == "function") then return false end
    if ns.inCombat and ns.inCombat() then return false end
    local boss
    if bossName and type(dg.bosses) == "table" then
        local want = tostring(bossName):lower()
        for _, b in ipairs(dg.bosses) do
            if type(b) == "table" and type(b.n) == "string" and b.n:lower() == want then boss = b break end
        end
    end
    local ok = pcall(J.Open, dg, tab or "overview", boss)
    return ok and true or false
end

-- Drop-Chance eines Teils (Prozent) aus FojjiCores Daten - nur gelesen, solange FojjiCore installiert ist; nichts wird uebernommen
local oddsIdx, oddsFor
function F.Odds(itemID)
    local d = DJ()
    if not d or not itemID or type(d.Dungeons) ~= "table" then return nil end
    if oddsFor ~= d.Dungeons then
        oddsIdx, oddsFor = {}, d.Dungeons
        for _, dg in ipairs(d.Dungeons) do
            for _, b in ipairs(type(dg) == "table" and type(dg.bosses) == "table" and dg.bosses or {}) do
                if type(b) == "table" and type(b.loot) == "table" and type(b.odds) == "table" then
                    for i, id in ipairs(b.loot) do
                        local o = tonumber(b.odds[i])
                        if type(id) == "number" and o and o > 0 and o <= 100 and not oddsIdx[id] then oddsIdx[id] = o end
                    end
                end
            end
        end
    end
    return oddsIdx[itemID]
end

-- Fojjis Wunschliste dieses Charakters (Item-IDs)
function F.Wishes()
    local d = DJ()
    local w = d and type(d.char) == "table" and d.char.wishes
    local out = {}
    if type(w) == "table" then
        for id in pairs(w) do
            id = tonumber(id)
            if id and id > 0 then out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end
-- davon noch nicht in meiner Oasis-Wunschliste
function F.NewWishes()
    local mine = {}
    if ns.Wants and ns.Wants.All then
        for _, w in ipairs(ns.Wants.All()) do
            if w.itemID and w.itemID ~= 0 and ns.isMe(w.who) then mine[w.itemID] = true end
        end
    end
    local out = {}
    for _, id in ipairs(F.Wishes()) do if not mine[id] then out[#out + 1] = id end end
    return out
end
-- nur auf Klick/Befehl: Fojji-Wuensche in die gildenweite Oasis-Wunschliste legen (die Gilde sieht sie dann)
function F.ImportWishes()
    if not (ns.Wants and ns.Wants.Add) then return 0 end
    local n = 0
    for _, id in ipairs(F.NewWishes()) do
        if n >= 40 then break end
        local ok = pcall(ns.Wants.Add, "item:" .. id, 1, "FojjiCore")
        if ok then n = n + 1 end
    end
    if n > 0 then ns.RefreshPage("wants") end
    return n
end

-- /oa fojji          -> Stand
-- /oa fojji wunsch   -> Fojjis Wunschliste in die Oasis-Wunschliste uebernehmen
ns.slash = ns.slash or {}
ns.slash.fojji = function(rest)
    rest = tostring(rest or ""):lower()
    if not F.Has() then
        ns.print(L["FojjiCore ist nicht geladen - Oasis laeuft eigenstaendig."])
        return
    end
    if rest:find("wunsch", 1, true) or rest:find("wish", 1, true) then
        local n = F.ImportWishes()
        ns.print(n > 0 and (L["%d Wuensche aus FojjiCore in die Oasis-Wunschliste uebernommen."]):format(n) or L["Keine neuen Wuensche in FojjiCore gefunden."])
        return
    end
    ns.print((L["FojjiCore %s erkannt - Journal, Karten und Routen oeffnet Oasis dort."]):format(F.Version() or ""))
    local nw = #F.NewWishes()
    if nw > 0 then ns.print((L["%d Wuensche in FojjiCore stehen noch nicht in der Oasis-Wunschliste: /oa fojji wunsch"]):format(nw)) end
end
end)

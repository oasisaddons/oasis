-- Oasis: Zusammenspiel mit verbreiteten Addons (0.6.525)
-- Leitlinie: Oasis ist das Gilden-/Gruppen-Addon und ergaenzt die grossen Addons, statt mit ihnen zu konkurrieren
-- (wie bei FojjiCore). Ist ein Addon geladen, das etwas schon gut kann, nimmt sich Oasis dort zurueck
-- (nur der STANDARD - wer selbst umschaltet, behaelt seine Wahl) und reicht Daten weiter, wo es passt.
--  * Naowh Forever: Gruppen-XP, Bedrohung, Glimmer aus; BiS-Liste -> Gilden-Gesucht; Journal/Gruppen-Betrachten oeffnen
--  * RareScanner: eigene Rare-Warnung aus (Meldung an die Gilde bleibt)
--  * Baganator/Syndicator/Bagnon/Altoholic: Twink-Zeile im Tooltip aus (Taschen-Seite und "Gilde braucht" bleiben)
--  * Pawn: Verbesserungs-Pfeile aus (Upgrade-Boerse der Gilde bleibt)
--  * ThreatClassic2: Oasis-Bedrohungsleiste aus
--  * TomTom: Oasis-Ziele zusaetzlich als TomTom-Wegpunkt
--  * Auctionator: Marktpreise, wenn Midas fehlt
--  * Chattynator/Prat: wie EllesmereUI-Chat - Oasis greift nicht in Blizzards Chatfenster ein (ns.ForeignChat)
-- Es werden nur oeffentliche Funktionen/Tabellen der anderen Addons AUFGERUFEN, nichts daraus kopiert.
local ADDON, ns = ...
local L = ns.L
local CP = {}
ns.Compat = CP

function CP.Has(name)
    local loadedFn = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not loadedFn then return false end
    local ok, r = pcall(loadedFn, name)
    return ok and r and true or false
end
local function any(list) for _, n in ipairs(list) do if CP.Has(n) then return n end end return nil end
CP.BAGS = { "Baganator", "Syndicator", "Bagnon", "BagBrother", "Altoholic", "AdiBags", "BetterBags", "ArkInventory" }
CP.CHAT = { "Chattynator", "Prat-3.0" }

-- Standardwerte, nur wenn der Spieler die Einstellung nie selbst gesetzt hat (nil). Merker compatSet, damit
-- Oasis seine eigene Vorgabe zuruecknimmt, wenn das andere Addon spaeter wieder fehlt.
local RULES = {
    { key = "partyXP", value = false, when = function() return CP.Has("NaowhForever_QoL") end },
    { key = "threatBar", value = false, when = function() return CP.Has("NaowhForever_Combat") or CP.Has("ThreatClassic2") end },
    { key = "glimmer", value = false, when = function() return CP.Has("NaowhForever_QoL") end },
    { key = "cpRare", value = false, when = function() return CP.Has("RareScanner") end },
    { key = "invTooltipOff", value = true, when = function() return any(CP.BAGS) ~= nil end },
    { key = "upgradeTipOff", value = true, when = function() return CP.Has("Pawn") end },
    { key = "upgradeIconOff", value = true, when = function() return CP.Has("Pawn") end },
}
function CP.Apply()
    local s = ns.db and ns.db.settings
    if not s then return end
    s.compatSet = s.compatSet or {}
    for _, r in ipairs(RULES) do
        local on = r.when()
        if on and s[r.key] == nil then
            s[r.key] = r.value
            s.compatSet[r.key] = r.value
        elseif not on and s.compatSet[r.key] ~= nil and s[r.key] == s.compatSet[r.key] then
            -- das andere Addon ist weg und der Wert stammt von uns -> wieder Oasis-Standard
            s[r.key] = nil
            s.compatSet[r.key] = nil
        end
    end
end
-- vor den LOGIN-Haken der Module (die setzen sonst ihre eigenen Standardwerte)
ns.Listen("DB_READY", function() pcall(CP.Apply) end)
-- Wenn der Spieler selbst schaltet, ist es seine Wahl (Merker loeschen)
function CP.UserSet(key) local s = ns.db and ns.db.settings if s and s.compatSet then s.compatSet[key] = nil end end

-- Liste fuer Einstellungen > Status: welche Addons erkannt wurden und was Oasis deshalb tut
CP.KNOWN = {
    { "NaowhForever", "Naowh Forever", "BiS list into the guild wishlist, opens journal and group inspect; Oasis XP bar, threat and glimmer off" },
    { "RareScanner", "RareScanner", "Rare alerts come from RareScanner; Oasis keeps sharing sightings with the guild" },
    { "Baganator", "Baganator", "Bags there; Oasis only shows what the guild needs" },
    { "Syndicator", "Syndicator", "Alt inventory in the tooltip there" },
    { "Bagnon", "Bagnon", "Bags there; Oasis only shows what the guild needs" },
    { "Altoholic", "Altoholic", "Alts there; Oasis only shows what the guild needs" },
    { "Pawn", "Pawn", "Upgrade arrows from Pawn; the Oasis upgrade exchange for tradeable guild gear stays" },
    { "TomTom", "TomTom", "Oasis targets (member, meeting point, node) also as TomTom waypoint" },
    { "Auctionator", "Auctionator", "Market values in the guild market when Midas is missing" },
    { "Midas", "Midas", "Market values in the guild market" },
    { "ThreatClassic2", "ThreatClassic2", "Threat there; the Oasis pull warning stays" },
    { "Details", "Details!", "Damage meter there; the Oasis guild combat ranking uses Blizzard's numbers" },
    { "DBM-Core", "Deadly Boss Mods", "Boss warnings there; the Oasis guild tactics board complements them" },
    { "BigWigs", "BigWigs", "Boss warnings there; the Oasis guild tactics board complements them" },
    { "Questie", "Questie", "Quests on the map there; Oasis marks group quests and shares quest items" },
    { "GatherMate2", "GatherMate2", "Your own nodes there; Oasis shares nodes with the guild" },
    { "HandyNotes", "HandyNotes", "Map notes there; Oasis markers are for the guild" },
    { "Chattynator", "Chattynator", "Chat window there; Oasis guild chat stays in the Oasis window" },
    { "Prat-3.0", "Prat", "Chat window there; Oasis guild chat stays in the Oasis window" },
    { "EllesmereUIChat", "EllesmereUI", "Chat window there; Oasis guild chat stays in the Oasis window" },
    { "Gargul", "Gargul", "Raid looting there; Oasis reservations and loot points as the guild record" },
    { "RCLootCouncil", "RCLootCouncil", "Raid looting there; Oasis loot points as the guild record" },
    { "Guild_Roster_Manager", "Guild Roster Manager", "Own history there; Oasis adds guild-wide shared data (attendance, thanks, mentors, votes)" },
    { "MRT", "Method Raid Tools", "Raid notes there; Oasis raid planning and sign-ups complement them" },
}
function CP.Detected()
    local out = {}
    for _, k in ipairs(CP.KNOWN) do if CP.Has(k[1]) then out[#out + 1] = k end end
    return out
end
ns.slash.addons = function()
    local d = CP.Detected()
    if #d == 0 then ns.print(L["No known addons found - Oasis does everything itself."]) return end
    for _, k in ipairs(d) do ns.print("|cffe8b44a" .. k[2] .. "|r: " .. L[k[3]]) end
end

------------------------------------------------------------------------
-- TomTom: Oasis-Ziel zusaetzlich als Wegpunkt
------------------------------------------------------------------------
local tomUid
function CP.TomTomTarget(t)
    if not t or ns.db.settings.tomtom == false then return end
    local T = rawget(_G, "TomTom")
    if type(T) ~= "table" or type(T.AddWaypoint) ~= "function" then return end
    if tomUid and type(T.RemoveWaypoint) == "function" then pcall(T.RemoveWaypoint, T, tomUid) end
    local ok, uid = pcall(T.AddWaypoint, T, t.mapID, t.x, t.y, { title = "Oasis: " .. tostring(t.label or ""), persistent = false, minimap = true, world = true })
    tomUid = ok and uid or nil
end
function CP.TomTomClear()
    local T = rawget(_G, "TomTom")
    if tomUid and type(T) == "table" and type(T.RemoveWaypoint) == "function" then pcall(T.RemoveWaypoint, T, tomUid) end
    tomUid = nil
end

------------------------------------------------------------------------
-- Auctionator: Preis, wenn Midas fehlt
------------------------------------------------------------------------
function CP.AuctionatorPrice(itemID)
    local A = rawget(_G, "Auctionator")
    local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1
    if type(v1) ~= "table" or type(v1.GetAuctionPriceByItemID) ~= "function" or not itemID then return nil end
    local ok, p = pcall(v1.GetAuctionPriceByItemID, "Oasis", itemID)
    return ok and type(p) == "number" and p > 0 and p or nil
end

------------------------------------------------------------------------
-- Naowh Forever: BiS-Liste -> Gilden-Wunschliste, Fenster oeffnen
------------------------------------------------------------------------
local N = {}
CP.Naowh = N
local function NS() local n = rawget(_G, "NaowhForever") return type(n) == "table" and n or nil end
function N.Has() return NS() ~= nil end
-- Spitzenwahl je Platz aus Naowhs BiS-Listen (Liste der aktuellen Spezialisierung, sonst alle)
function N.BisItems()
    local n = NS()
    local B = n and n.BiS
    local Lists = B and B.Lists
    if not (Lists and type(Lists.All) == "function") then return {} end
    local okA, all = pcall(Lists.All)
    if not okA or type(all) ~= "table" then return {} end
    local spec = type(Lists.CurrentSpec) == "function" and select(2, pcall(Lists.CurrentSpec)) or nil
    local pick
    for _, l in ipairs(all) do if type(l) == "table" and spec ~= nil and l.spec == spec then pick = l break end end
    local use = pick and { pick } or all
    local out, seen = {}, {}
    for _, l in ipairs(use) do
        for _, id in pairs(type(l) == "table" and type(l.slots) == "table" and l.slots or {}) do
            id = tonumber(id)
            if id and id > 0 and not seen[id] then seen[id] = true out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end
-- noch nicht im Besitz und noch nicht auf meiner Oasis-Wunschliste
function N.NewWishes()
    local mine = {}
    for _, w in ipairs(ns.Wants and ns.Wants.All and ns.Wants.All() or {}) do
        if w.itemID and w.itemID ~= 0 and ns.isMe(w.who) then mine[w.itemID] = true end
    end
    local out = {}
    for _, id in ipairs(N.BisItems()) do
        local have = (C_Item and C_Item.GetItemCount and ns.safe(C_Item.GetItemCount(id, true))) or 0
        local worn = C_Item and C_Item.IsEquippedItem and ns.safe(C_Item.IsEquippedItem(id))
        if not mine[id] and (have or 0) == 0 and not worn then out[#out + 1] = id end
    end
    return out
end
function N.ImportWishes()
    if not (ns.Wants and ns.Wants.Add) then return 0 end
    local n = 0
    for _, id in ipairs(N.NewWishes()) do
        if n >= 40 then break end
        if pcall(ns.Wants.Add, "item:" .. id, 1, "BiS (Naowh)") then n = n + 1 end
    end
    if n > 0 then ns.RefreshPage("wants") end
    return n
end
local function call(fn) if ns.inCombat and ns.inCombat() then return false end local f = rawget(_G, fn) if type(f) == "function" then return pcall(f) end return false end
function N.OpenJournal() return call("NaowhForever_ToggleJournal") end
function N.OpenGroupInspect() return call("NaowhForever_ToggleGroupInspect") end
function N.OpenBis() return call("NaowhForever_ToggleBis") end
function N.CanGroupInspect() return type(rawget(_G, "NaowhForever_ToggleGroupInspect")) == "function" end
function N.CanJournal() return type(rawget(_G, "NaowhForever_ToggleJournal")) == "function" end
ns.slash.naowh = function(rest)
    rest = tostring(rest or ""):lower()
    if not N.Has() then ns.print(L["Naowh Forever is not loaded - Oasis runs on its own."]) return end
    if rest:find("wunsch", 1, true) or rest:find("bis", 1, true) then
        local n = N.ImportWishes()
        ns.print(n > 0 and (L["%d BiS items from Naowh added to the Oasis wishlist."]):format(n) or L["No new BiS items found in Naowh."])
        return
    end
    ns.print(L["Naowh Forever found - Oasis handles guild and group, Naowh your character."])
    local nw = #N.NewWishes()
    if nw > 0 then ns.print((L["%d BiS items from Naowh are not on the Oasis wishlist yet: /oa naowh bis"]):format(nw)) end
end

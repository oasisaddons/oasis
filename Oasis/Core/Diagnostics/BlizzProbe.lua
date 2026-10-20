-- Oasis: what can the Forever client already do by itself? (0.5.521)
-- Once per Oasis version, silently reads all console settings (CVars) with help text and checks some
-- Blizzard windows. Result in OasisDB.blizzProbe (readable after /reload) - basis for finding duplicate
-- Oasis convenience features. Read only. Manually: /oa probe blizz
local ADDON, ns = ...

local KEYWORDS = { "coord", "loot", "duel", "camera", "zoom", "chat", "timestamp", "junk", "repair", "range", "tooltip",
    "sell", "quest", "error", "invite", "summon", "resurrect", "durab", "minimap", "clock", "xp", "experience", "fade",
    "class", "color", "colour", "fish", "rare", "vignette", "track", "flight", "taxi", "item", "level", "ilvl", "compare",
    "inspect", "nameplate", "map", "reveal", "fog", "arrow", "alt", "share", "mail", "vendor", "price", "auto" }
local FRAMES = { "MerchantSellAllJunkButton", "MerchantRepairAllButton", "DurabilityFrame", "TimeManagerClockButton",
    "MinimapCoordinatesFrame", "MinimapZoneText", "MiniMapTracking", "GameTimeFrame", "QuestTimerFrame", "ExpansionLandingPageMinimapButton",
    "WorldMapFrame", "PlayerSpellsFrame", "CharacterFrame", "InspectFrame", "ObjectiveTrackerFrame", "QuestWatchFrame",
    "LootFrame", "GroupLootContainer", "MainStatusTrackingBarContainer", "StatusTrackingBarManager", "TaxiFrame", "FlightMapFrame",
    "EditModeManagerFrame", "SettingsPanel", "InterfaceOptionsFrame", "ChatFrame1EditBox", "CompactRaidFrameManager" }

local function probe(manual)
    local out = { ts = ns.now(), v = ns.version, cvars = {}, frames = {}, n = 0 }
    local list
    if C_Console and C_Console.GetAllCommands then
        local ok, t = pcall(C_Console.GetAllCommands)
        if ok and type(t) == "table" then list = t end
    end
    if not list and ConsoleGetAllCommands then
        local ok, t = pcall(ConsoleGetAllCommands)
        if ok and type(t) == "table" then list = t end
    end
    for _, c in ipairs(list or {}) do
        local name = type(c) == "table" and (c.command or c.name) or tostring(c)
        if type(name) == "string" then
            out.n = out.n + 1
            local low = name:lower()
            local hit = false
            for _, k in ipairs(KEYWORDS) do if low:find(k, 1, true) then hit = true break end end
            if hit then
                local val
                if C_CVar and C_CVar.GetCVar then local ok, v = pcall(C_CVar.GetCVar, name) if ok then val = v end end
                local help = type(c) == "table" and c.help or nil
                out.cvars[#out.cvars + 1] = name .. " = " .. tostring(val) .. ((help and help ~= "") and ("  | " .. tostring(help):sub(1, 120)) or "")
            end
        end
    end
    table.sort(out.cvars)
    for _, n in ipairs(FRAMES) do
        local f = _G[n]
        out.frames[#out.frames + 1] = n .. " = " .. (type(f) == "table" and ("da" .. ((f.IsShown and f:IsShown()) and " (sichtbar)" or "")) or "fehlt")
    end
    -- Blizzard addons shipped with the client
    local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local GetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    out.addons = {}
    if GetNum and GetInfo then
        for i = 1, GetNum() do
            local ok, name, title = pcall(GetInfo, i)
            if ok and type(name) == "string" and name:find("^Blizzard_") then out.addons[#out.addons + 1] = name end
        end
    end
    ns.db.blizzProbe = out
    if manual then ns.print(("Blizzard-Pruefung: %d Einstellungen, %d passende gemerkt - nach /reload auswertbar."):format(out.n, #out.cvars)) end
end
ns.probes = ns.probes or {}
ns.probes.blizz = function() probe(true) end
ns.Listen("LOGIN", function()
    local p = ns.db.blizzProbe
    if p and p.v == ns.version then return end
    ns.After(25, function() if not ns.inCombat() then pcall(probe) end end)
end)

------------------------------------------------------------------------
-- 0.5.697: inventory of the Blizzard API (developers only)
-- Once per client build, remember all C_* namespaces (function names), all global functions written by Blizzard in C
-- (tostring = "builtin") and the enum names (OasisDB.apiSnap). If the build changes, it is compared with
-- the previous state: OasisDB.apiDiff = { from, to, added = {...}, removed = {...} }.
-- OasisDB.apiHits = names matching functions Oasis could use (Legacy, Cooldown Manager, Inspect ...).
-- Manually: /oa probe api   (evaluable in the Oasis file after /reload). Read only.
------------------------------------------------------------------------
local HITS = { "legacy", "cooldownviewer", "cooldown", "inspect", "voice", "questtype", "lfglist", "trait", "talent",
    "damagemeter", "gamepad", "challenge", "tooltipinfo", "spellbook", "barber" }
local function buildNo()
    local ok, ver, build = pcall(GetBuildInfo)
    return ok and tostring(build or ver or "?") or "?"
end
local function snapshot()
    local snap = { build = buildNo(), ts = ns.now(), v = ns.version, ns = {}, enum = "", glob = "", nns = 0, nfn = 0, nglob = 0 }
    local globs, enums = {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 1) ~= "_" and k:sub(1, 5) ~= "Oasis" then
            if k:sub(1, 2) == "C_" and type(v) == "table" then
                local names = {}
                local ok = pcall(function() for fk in pairs(v) do if type(fk) == "string" then names[#names + 1] = fk end end end)
                if ok then
                    table.sort(names)
                    snap.ns[k] = table.concat(names, ",")
                    snap.nns, snap.nfn = snap.nns + 1, snap.nfn + #names
                end
            elseif k == "Enum" and type(v) == "table" then
                pcall(function() for ek in pairs(v) do if type(ek) == "string" then enums[#enums + 1] = ek end end end)
            elseif type(v) == "function" then
                local okS, str = pcall(tostring, v)
                if okS and type(str) == "string" and str:find("builtin", 1, true) then globs[#globs + 1] = k end
            end
        end
    end
    table.sort(globs) table.sort(enums)
    snap.glob, snap.enum = table.concat(globs, ","), table.concat(enums, ",")
    snap.nglob = #globs
    return snap
end
local function setOf(str)
    local t = {}
    for n in tostring(str or ""):gmatch("[^,]+") do t[n] = true end
    return t
end
local function diff(old, new)
    local d = { from = old.build, to = new.build, ts = ns.now(), added = {}, removed = {} }
    local function cmp(label, a, b)
        local sa, sb = setOf(a), setOf(b)
        for n in pairs(sb) do if not sa[n] then d.added[#d.added + 1] = label .. n end end
        for n in pairs(sa) do if not sb[n] then d.removed[#d.removed + 1] = label .. n end end
    end
    for k, str in pairs(new.ns) do cmp(k .. ".", old.ns[k], str) end
    for k, str in pairs(old.ns) do if not new.ns[k] then cmp(k .. ".", str, nil) end end
    cmp("", old.glob, new.glob)
    cmp("Enum.", old.enum, new.enum)
    table.sort(d.added) table.sort(d.removed)
    while #d.added > 4000 do table.remove(d.added) end
    while #d.removed > 4000 do table.remove(d.removed) end
    return d
end
local function hitsOf(snap)
    local out = {}
    local function scan(label, str)
        for n in tostring(str or ""):gmatch("[^,]+") do
            local low = (label .. n):lower()
            for _, k in ipairs(HITS) do if low:find(k, 1, true) then out[#out + 1] = label .. n break end end
        end
    end
    for k, str in pairs(snap.ns) do
        if k:lower():find("legacy", 1, true) or k:lower():find("cooldown", 1, true) then
            out[#out + 1] = k .. " (Bereich)"
        end
        scan(k .. ".", str)
    end
    scan("", snap.glob)
    scan("Enum.", snap.enum)
    table.sort(out)
    while #out > 1500 do table.remove(out) end
    return out
end
local function apiProbe(manual)
    local old = ns.db.apiSnap
    local snap = snapshot()
    if old and old.build and old.build ~= snap.build then
        ns.db.apiDiff = diff(old, snap)
    end
    ns.db.apiSnap = snap
    ns.db.apiHits = hitsOf(snap)
    if manual then
        local d = ns.db.apiDiff
        ns.print(("Schnittstelle: Build %s - %d Bereiche, %d Funktionen, %d globale C-Funktionen, %d Treffer.%s"):format(
            snap.build, snap.nns, snap.nfn, snap.nglob, #ns.db.apiHits,
            d and (" Unterschied zu Build " .. tostring(d.from) .. ": +" .. #d.added .. " / -" .. #d.removed) or " (noch kein Vorgaenger zum Vergleichen)"))
    end
end
ns.probes.api = function() apiProbe(true) end
ns.Listen("LOGIN", function()
    if not (ns.IsDev and ns.IsDev()) then return end
    local old = ns.db.apiSnap
    if old and old.build == buildNo() then return end
    ns.After(40, function() if not ns.inCombat() then pcall(apiProbe) end end)
end)

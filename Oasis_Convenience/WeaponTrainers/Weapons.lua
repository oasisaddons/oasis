-- Oasis - Waffenlehrer: in welcher Hauptstadt lernt man welche Waffe? Passend zu Fraktion (Volk) und Klasse,
-- mit dem, was du schon kannst. Stand: Classic (WoW Forever kann abweichen).
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_WeaponTrainers", function()   -- Modul Waffenlehrer (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local W = {}
ns.Weapons = W

-- Waffen: Schluessel, deutscher Name (Fertigkeit im deDE-Client), englischer Name
local WEAPONS = {
    { "axe1", "One-Handed Axes", "One-Handed Axes" }, { "axe2", "Two-Handed Axes", "Two-Handed Axes" },
    { "mace1", "One-Handed Maces", "One-Handed Maces" }, { "mace2", "Two-Handed Maces", "Two-Handed Maces" },
    { "sword1", "One-Handed Swords", "One-Handed Swords" }, { "sword2", "Two-Handed Swords", "Two-Handed Swords" },
    { "dagger", "Daggers", "Daggers" }, { "fist", "Fist Weapons", "Fist Weapons" }, { "polearm", "Polearms", "Polearms" },
    { "staff", "Staves", "Staves" }, { "bow", "Bows", "Bows" }, { "xbow", "Crossbows", "Crossbows" },
    { "gun", "Guns", "Guns" }, { "thrown", "Thrown", "Thrown" },
}
-- was die Klasse lernen darf (Classic; WoW Forever: Schurken auch Einhandaexte - laut Gilde 07.10.)
local CLASS = {
    WARRIOR = { axe1 = 1, axe2 = 1, mace1 = 1, mace2 = 1, sword1 = 1, sword2 = 1, dagger = 1, fist = 1, polearm = 1, staff = 1, bow = 1, xbow = 1, gun = 1, thrown = 1 },
    PALADIN = { axe1 = 1, axe2 = 1, mace1 = 1, mace2 = 1, sword1 = 1, sword2 = 1, polearm = 1 },
    HUNTER = { axe1 = 1, axe2 = 1, sword1 = 1, sword2 = 1, dagger = 1, fist = 1, polearm = 1, staff = 1, bow = 1, xbow = 1, gun = 1, thrown = 1 },
    ROGUE = { axe1 = 1, mace1 = 1, sword1 = 1, dagger = 1, fist = 1, bow = 1, xbow = 1, gun = 1, thrown = 1 },
    PRIEST = { mace1 = 1, dagger = 1, staff = 1 },
    SHAMAN = { axe1 = 1, axe2 = 1, mace1 = 1, mace2 = 1, dagger = 1, fist = 1, staff = 1 },
    MAGE = { sword1 = 1, dagger = 1, staff = 1 },
    WARLOCK = { sword1 = 1, dagger = 1, staff = 1 },
    DRUID = { mace1 = 1, mace2 = 1, dagger = 1, fist = 1, staff = 1 },
}
-- Waffenmeister der Hauptstaedte (Classic)
local TRAINERS = {
    Horde = {
        { city = "Orgrimmar", npc = "Sayoc", where = "Tal der Ehre", x = 81.6, y = 19.4, w = { "axe1", "axe2", "bow", "dagger", "fist", "thrown" } },
        { city = "Orgrimmar", npc = "Hanashi", where = "Tal der Ehre", x = 81.2, y = 19.0, w = { "axe1", "axe2", "bow", "staff", "thrown" } },
        { city = "Donnerfels", npc = "Ansekhwa", where = "Anhoehe der Jaeger", x = 40.9, y = 62.7, w = { "mace1", "mace2", "gun", "staff" } },
        { city = "Unterstadt", npc = "Archibald", where = "Kriegsviertel", x = 57.3, y = 32.8, w = { "sword1", "sword2", "dagger", "xbow", "polearm" } },
    },
    Alliance = {
        { city = "Sturmwind", npc = "Woo Ping", where = "Altstadt", x = 57.1, y = 57.7, w = { "sword1", "sword2", "dagger", "xbow", "polearm", "staff" } },
        { city = "Eisenschmiede", npc = "Buliwyf Steinhand", where = "Halle der Waffen", x = 61.2, y = 89.5, w = { "axe1", "axe2", "mace1", "mace2", "fist", "gun" } },
        { city = "Eisenschmiede", npc = "Bixi Wobbelbonk", where = "Halle der Waffen", x = 62.2, y = 88.8, w = { "dagger", "thrown", "xbow" } },
        { city = "Darnassus", npc = "Ilyenia Mondfeuer", where = "Kriegerterrasse", x = 57.6, y = 46.6, w = { "bow", "dagger", "fist", "staff", "thrown" } },
    },
}

-- Karten der Hauptstaedte: Classic-ID zuerst, dann Retail-ID (Forever nutzt den Retail-Client)
local CITY_MAPS = {
    Orgrimmar = { 1454, 85 }, Donnerfels = { 1456, 88 }, Unterstadt = { 1458, 90 },
    Sturmwind = { 1453, 84 }, Eisenschmiede = { 1455, 87 }, Darnassus = { 1457, 89 },
}
local mapCache = {}
local function cityMap(city)
    if mapCache[city] ~= nil then return mapCache[city] or nil end
    for _, id in ipairs(CITY_MAPS[city] or {}) do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info and info.name then mapCache[city] = id return id end
    end
    mapCache[city] = false
    return nil
end
-- Waffenmeister auf der Weltkarte zeigen (Oasis-Ziel: Pfeil auf Karte + Minimap)
function W.ShowTrainer(t)
    if not t then return end
    local id = t.mapID or cityMap(t.city)
    if id and t.x and ns.Map and ns.Map.SetTarget then
        ns.Map.SetTarget({ mapID = id, x = t.x / 100, y = t.y / 100, label = t.npc, sub = L["Weapon masters"] .. " · " .. L[t.city] })
    elseif id and ns.Map and ns.Map.ShowOnWorldMap then
        ns.Map.ShowOnWorldMap(id)
    else
        ns.print(L["Weapon masters"] .. ": " .. t.npc .. ", " .. L[t.city] .. " (" .. L[t.where] .. ")")
    end
end

-- WoW Forever nennt die Einhand-Fertigkeiten kurz ("Äxte", "Streitkolben", "Schwerter")
local ALIAS = { ["Äxte"] = "axe1", ["Axes"] = "axe1", ["Streitkolben"] = "mace1", ["Maces"] = "mace1",
    ["Schwerter"] = "sword1", ["Swords"] = "sword1", ["Staves"] = "staff", ["Staves"] = "staff" }
-- schon gelernte Waffen (Fertigkeiten-Liste des Clients)
local function known()
    local out = {}
    local n = GetNumSkillLines and GetNumSkillLines() or 0
    for i = 1, n do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        name = ns.safe(name)
        if name and not isHeader then
            for _, wp in ipairs(WEAPONS) do
                if name == L[wp[2]] or name == wp[2] or name == wp[3] or ALIAS[name] == wp[1] then out[wp[1]] = { rank = rank, max = max } end
            end
        end
    end
    -- Forever-Client liefert die alte Fertigkeitenliste oft nicht: Waffen-Fertigkeiten sind auch Zauber
    local SPELL = { axe1 = 196, axe2 = 197, mace1 = 198, mace2 = 199, polearm = 200, sword1 = 201, sword2 = 202,
        staff = 227, bow = 264, gun = 266, dagger = 1180, thrown = 2567, xbow = 5011, fist = 15590 }
    for k, id in pairs(SPELL) do
        if not out[k] then
            local ok, has = pcall(function() return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) end)
            if ok and ns.safe(has) then out[k] = { rank = 0, max = 0 } end
        end
    end
    -- angelegte Waffen koennen nur gelernt sein (Waffen-Unterklasse -> Schluessel)
    local SUB = { [0] = "axe1", [1] = "axe2", [2] = "bow", [3] = "gun", [4] = "mace1", [5] = "mace2", [6] = "polearm",
        [7] = "sword1", [8] = "sword2", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown", [18] = "xbow" }
    for _, slot in ipairs({ 16, 17, 18 }) do
        local id = GetInventoryItemID and ns.safe(GetInventoryItemID("player", slot))
        if id and C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
            local k = classID == 2 and SUB[subID]
            if k and not out[k] then out[k] = { rank = 0, max = 0 } end
        end
    end
    return out
end

------------------------------------------------------------------------
-- WoW Forever statt Classic: was Waffenmeister WIRKLICH lehren, liest Oasis beim Besuch mit
-- (Trainerfenster) und teilt es mit der Gilde (Sammlung "wtrain"). Die Classic-Tabellen oben
-- gelten nur noch, solange niemand aus der Gilde den Lehrer besucht hat.
--   wt:<Lehrer>  = { npc, city, mapID, x, y, fac, w = "axe1,sword1,..." }   (was er lehrt, alle Klassen gesammelt)
--   wc:<KLASSE>  = { cls, w = "..." }                                      (was diese Klasse lernen kann)
------------------------------------------------------------------------
local Store = ns.Store
local KEYSET = {}
for _, wp in ipairs(WEAPONS) do KEYSET[wp[1]] = true end
-- Fertigkeitsname (Trainer, Fertigkeitenliste) -> Schluessel
local function keyOfName(name)
    if type(name) ~= "string" then return nil end
    for _, wp in ipairs(WEAPONS) do
        if name == L[wp[2]] or name == wp[2] or name == wp[3] or ALIAS[name] == wp[1] then return wp[1] end
    end
end
W.KeyOfName = keyOfName
local function splitKeys(str)
    local t = {}
    for k in tostring(str or ""):gmatch("[%w]+") do if KEYSET[k] then t[k] = true end end
    return t
end
local function joinKeys(t)
    local out = {}
    for _, wp in ipairs(WEAPONS) do if t[wp[1]] then out[#out + 1] = wp[1] end end
    return table.concat(out, ",")
end
local function clean(s, max)
    s = tostring(s or ""):gsub("[|%c]", "")
    return s:sub(1, max or 40)
end
-- Trainerfenster lesen
function W.ScanTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and Store) then return end
    local n = ns.safe(GetNumTrainerServices()) or 0
    local found = {}
    for i = 1, n do
        local ok, name = pcall(GetTrainerServiceInfo, i)
        local k = ok and keyOfName(ns.safe(name))
        if k then found[k] = true end
    end
    if not next(found) then return end   -- kein Waffenmeister
    local npc = clean(ns.safe(ns.UnitName("npc")), 40)
    if npc == "" then return end
    local _, cls = UnitClass("player")
    local fac = UnitFactionGroup("player") or ""
    local mapID = ns.safe(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local x, y
    if mapID and C_Map.GetPlayerMapPosition then
        local okp, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if okp and pos then x, y = pos.x, pos.y end
    end
    -- Lehrer: was er lehrt (alle Klassen zusammen)
    local id = "wt:" .. npc
    local old = Store.Get("wtrain", id)
    local w = splitKeys(old and old.w)
    local changed = not old
    for k in pairs(found) do if not w[k] then w[k] = true changed = true end end
    if changed or (old and not old.x and x) then
        Store.Put("wtrain", { id = id, npc = npc, city = clean(ns.safe(GetRealZoneText()) or "", 40), fac = fac, mapID = mapID,
            x = x and math.floor(x * 1000) / 10 or nil, y = y and math.floor(y * 1000) / 10 or nil, w = joinKeys(w) })
    end
    -- Klasse: was sie lernen kann
    if cls then
        local cid = "wc:" .. cls
        local oc = Store.Get("wtrain", cid)
        local cw = splitKeys(oc and oc.w)
        local ch = not oc
        for k in pairs(found) do if not cw[k] then cw[k] = true ch = true end end
        if ch then Store.Put("wtrain", { id = cid, cls = cls, w = joinKeys(cw) }) end
    end
    ns.RefreshPage("insta")
end
ns.On("TRAINER_SHOW", function() ns.After(0.3, function() pcall(W.ScanTrainer) end) end)
ns.On("TRAINER_UPDATE", function() pcall(W.ScanTrainer) end)

-- Lehrer einer Fraktion: gelesene (Forever) zuerst, Classic-Liste nur fuer noch unbesuchte
function W.Trainers(faction)
    local out, seen = {}, {}
    if Store then
        for _, r in ipairs(Store.List("wtrain", function(r) return type(r.id) == "string" and r.id:find("^wt:") and r.fac == faction end)) do
            local wl = {}
            for k in pairs(splitKeys(r.w)) do wl[#wl + 1] = k end
            table.sort(wl)
            out[#out + 1] = { city = r.city ~= "" and r.city or "?", npc = r.npc, where = r.city or "", x = r.x, y = r.y, mapID = r.mapID, w = wl, live = true }
            seen[r.npc] = true
        end
    end
    for _, t in ipairs(TRAINERS[faction] or {}) do if not seen[t.npc] then out[#out + 1] = t end end
    return out
end
-- was meine Klasse lernen kann: gelesen (Forever) falls vorhanden, sonst Classic
function W.ClassCan(cls)
    -- Classic-Liste PLUS was ein Forever-Waffenmeister dieser Klasse angeboten hat
    -- (ein einzelner Lehrer zeigt nur seine Waffen -> ergaenzen, nicht ersetzen)
    local t = {}
    for k in pairs(CLASS[cls or ""] or {}) do t[k] = true end
    local r = Store and Store.Get("wtrain", "wc:" .. tostring(cls))
    local seen = r and not r.del and r.w
    if seen then for k in pairs(splitKeys(r.w)) do t[k] = true end end
    return t, seen and true or false
end

function W.Build(h)
    local left = K.Panel(h, C.panel)
    left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(370)
    local hd = K.GameHead(left, L["Your weapons"], C.amber)
    hd:SetPoint("TOPLEFT", 12, -12) hd:SetPoint("RIGHT", -12, 0)
    h.rows = {}
    for i = 1, #WEAPONS do
        local r = CreateFrame("Button", nil, left)
        r:SetHeight(26)
        r:SetPoint("TOPLEFT", 12, -42 - (i - 1) * 28)
        r:SetPoint("RIGHT", -12, 0)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.025)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(6, 6)
        r.dot:SetPoint("LEFT", 8, 0)
        r.n = K.Text(r, 12, C.text)
        r.n:SetPoint("LEFT", 22, 0)
        r.pin = K.Glyph(r, 12, ns.MEDIA .. "icons\\map", C.dim)
        r.pin:SetPoint("RIGHT", -6, 0)
        r.v = K.Text(r, 11, C.muted, "RIGHT")
        r.v:SetPoint("RIGHT", r.pin, "LEFT", -6, 0)
        r:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0.07)
            if self.trainer then
                self.pin:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                K.ShowTip(self, { self.title or "", self.trainer.npc .. "  ·  " .. L[self.trainer.city] .. ", " .. L[self.trainer.where], "|cff66db9e" .. L["Click: show weapon master on the map"] .. "|r" })
            end
        end)
        r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.025) self.pin:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self) if self.trainer then W.ShowTrainer(self.trainer) end end)
        h.rows[i] = r
    end
    -- was die Klasse nicht kann: eine Zeile statt vieler grauer
    h.notMine = K.Text(left, 11, C.dim)
    h.notMine:SetPoint("RIGHT", -18, 0)
    h.notMine:SetJustifyH("LEFT")
    h.notMine:SetWordWrap(true)
    local right = K.Panel(h, C.panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0) right:SetPoint("BOTTOMRIGHT")
    local hr = K.GameHead(right, L["Weapon masters"], C.blue)
    hr:SetPoint("TOPLEFT", 12, -12) hr:SetPoint("RIGHT", -12, 0)
    h.cards = {}
    for i = 1, 4 do
        local c = CreateFrame("Button", nil, right)
        c:SetHeight(60)
        c:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 66)
        c:SetPoint("RIGHT", -12, 0)
        c.bg = K.Fill(c, C.raised)
        c.pin = K.Glyph(c, 14, ns.MEDIA .. "icons\\map", C.dim)
        c.pin:SetPoint("TOPRIGHT", -10, -10)
        c:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(C.raised[1] + 0.05, C.raised[2] + 0.05, C.raised[3] + 0.05, 1)
            self.pin:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            if self.trainer then K.ShowTip(self, { self.trainer.npc, L[self.trainer.city] .. ", " .. L[self.trainer.where], "|cff66db9e" .. L["Click: show weapon master on the map"] .. "|r" }) end
        end)
        c:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], C.raised[4] or 1)
            self.pin:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
            GameTooltip:Hide()
        end)
        c:SetScript("OnClick", function(self) if self.trainer then W.ShowTrainer(self.trainer) end end)
        c.top = c:CreateTexture(nil, "ARTWORK")
        c.top:SetPoint("TOPLEFT") c.top:SetPoint("BOTTOMLEFT") c.top:SetWidth(2)
        c.city = K.Title(c, 14, C.text)
        c.city:SetPoint("TOPLEFT", 12, -8)
        c.npc = K.Text(c, 11, C.muted)
        c.npc:SetPoint("LEFT", c.city, "RIGHT", 8, -1)   -- Lehrer neben der Stadt (spart eine Zeile)
        c.w = K.Text(c, 12, C.text)
        c.w:SetPoint("TOPLEFT", c.city, "BOTTOMLEFT", 0, -5)
        c.w:SetPoint("RIGHT", -28, 0)
        c.w:SetJustifyH("LEFT")
        c.w:SetWordWrap(true)
        c.w:SetSpacing(2)
        h.cards[i] = c
    end
    h.note = K.Text(right, 10, C.dim)
    h.note:SetPoint("BOTTOMLEFT", 12, 10)
    h.note:SetPoint("RIGHT", -12, 0)
    h.note:SetText(L["Red = not learned yet  ·  Green = already learned. Oasis reads what the weapon master actually teaches and shares it with the guild."])
end

function W.Show(h)
    if not h.built then h.built = true W.Build(h) end
    local _, cls = UnitClass("player")
    local faction = UnitFactionGroup("player") or "Horde"
    local can, fromGame = W.ClassCan(cls)
    local have = known()
    local trainers = W.Trainers(faction)
    -- was der Client schon als Fertigkeit kennt, darf die Klasse auf jeden Fall (WoW Forever weicht von Classic ab)
    for k in pairs(have) do can[k] = 1 end
    local byKey = {}
    for _, wp in ipairs(WEAPONS) do byKey[wp[1]] = wp end
    -- wo lerne ich was?
    local where = {}
    local firstT = {}
    for _, t in ipairs(trainers) do
        for _, k in ipairs(t.w) do
            where[k] = where[k] or {}
            local dup = false
            for _, c2 in ipairs(where[k]) do if c2 == t.city then dup = true end end
            if not dup then table.insert(where[k], t.city) end
            firstT[k] = firstT[k] or t
        end
    end
    -- zuerst, was die Klasse kann (gelernt + offen); der Rest kommt gesammelt in eine Zeile darunter
    local order, rest = {}, {}
    for _, wp in ipairs(WEAPONS) do
        if have[wp[1]] or can[wp[1]] then order[#order + 1] = wp else rest[#rest + 1] = L[wp[2]] end
    end
    for _, r in ipairs(h.rows) do r:Hide() end
    for i, wp in ipairs(order) do
        local r = h.rows[i]
        r:Show()
        local k = wp[1]
        local h2 = have[k]
        r.title = L[wp[2]]
        r.trainer = firstT[k]
        r.pin:SetShown(r.trainer ~= nil)
        if h2 then
            -- gelernt = gruen
            r.dot:SetColorTexture(0.40, 0.86, 0.62, 1)
            r.n:SetText("|cff66db9e" .. L[wp[2]] .. "|r")
            r.v:SetText((h2.max or 0) > 0 and ("|cff9a9aa2" .. (h2.rank or 0) .. " / " .. h2.max .. "|r") or ("|cff66db9e" .. L["learned"] .. "|r"))
        elseif can[k] then
            -- noch nicht gelernt = rot
            r.dot:SetColorTexture(0.95, 0.30, 0.30, 1)
            r.n:SetText("|cfff04d4d" .. L[wp[2]] .. "|r")
            local w = where[k]
            r.v:SetText(w and ("|cffe8b44a" .. table.concat(w, " · ") .. "|r") or ("|cff666666" .. L["no trainer of your faction"] .. "|r"))
        end
    end
    h.notMine:ClearAllPoints()
    h.notMine:SetPoint("TOPLEFT", 18, -42 - #order * 28 - 10)
    h.notMine:SetPoint("RIGHT", h.rows[1]:GetParent(), "RIGHT", -18, 0)
    h.notMine:SetText(#rest > 0 and ("|cff777777" .. L["Not for your class:"] .. "|r  |cff555555" .. table.concat(rest, ", ") .. "|r") or "")
    local col = faction == "Alliance" and C.blue or C.red
    for i, c in ipairs(h.cards) do
        local t = trainers[i]
        if t then
            c.trainer = t
            c.top:SetColorTexture(col[1], col[2], col[3], 1)
            c.city:SetText(L[t.city])
            c.npc:SetText(t.npc .. (t.live and "" or ("  ·  " .. L[t.where])))
            local list = {}
            for _, k in ipairs(t.w) do
                local wp = byKey[k]
                local txt = L[wp[2]]
                if have[k] then txt = "|cff66db9e" .. txt .. "|r"
                elseif can[k] then txt = "|cfff04d4d" .. txt .. "|r"
                else txt = "|cff444444" .. txt .. "|r" end
                list[#list + 1] = txt
            end
            c.w:SetText(table.concat(list, "  ·  "))
            c:Show()
        else
            c:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Fertigkeiten (Koennen > Fertigkeiten): Waffen-, Verteidigungs- und Ruestungsfertigkeiten mit Stufe.
-- Quelle: Fertigkeitenliste des Clients (GetSkillLineInfo, mit Kategorien); liefert der Client nichts,
-- zeigt die Seite wenigstens die gelernten Waffen (ohne Stufe).
------------------------------------------------------------------------
function W.Skills()
    local groups, cur = {}, nil
    local n = GetNumSkillLines and GetNumSkillLines() or 0
    for i = 1, n do
        local name, isHeader, _, rank, _, mod, max = GetSkillLineInfo(i)
        name = ns.safe(name)
        if name then
            if isHeader then
                cur = { head = name, list = {} }
                groups[#groups + 1] = cur
            elseif cur then
                cur.list[#cur.list + 1] = { name = name, rank = tonumber(rank) or 0, mod = tonumber(mod) or 0, max = tonumber(max) or 0 }
            end
        end
    end
    -- Berufe stehen schon unter "Berufe & Ruf"; Sprachen interessieren hier nicht
    local out = {}
    for _, g in ipairs(groups) do
        local h = g.head:lower()
        local skip = h:find("beruf") or h:find("profession") or h:find("sprache") or h:find("language")
        if not skip and #g.list > 0 then out[#out + 1] = g end
    end
    if #out == 0 then
        local have = known()
        local list = {}
        for _, wp in ipairs(WEAPONS) do
            local hk = have[wp[1]]
            if hk then list[#list + 1] = { name = L[wp[2]], rank = hk.rank or 0, mod = 0, max = hk.max or 0 } end
        end
        if #list > 0 then out[1] = { head = L["Weapons"], list = list, noRank = true } end
    end
    return out
end

function W.ShowSkills(h)
    if not h.built then
        h.built = true
        h.panel = K.Panel(h, C.panel)
        h.panel:SetAllPoints()
        h.head = K.GameHead(h.panel, L["Skills"], C.accent)
        h.head:SetPoint("TOPLEFT", 14, -12) h.head:SetPoint("RIGHT", -14, 0)
        h.note = K.Text(h.panel, 10, C.dim)
        h.note:SetPoint("BOTTOMLEFT", 14, 10) h.note:SetPoint("RIGHT", -14, 0)
        h.note:SetWordWrap(true)
        h.rows = {}
        h.heads = {}
    end
    local data = W.Skills()
    local W2 = (h:GetWidth() or 700)
    if W2 < 200 then W2 = 700 end
    local colW = math.floor((W2 - 28 - 20) / 2)
    -- zwei Spalten: Gruppen abwechselnd links/rechts auffuellen (kuerzere Spalte zuerst)
    local colY = { -44, -44 }
    local ri, hi = 0, 0
    local noRank = false
    for _, g in ipairs(data) do
        if g.noRank then noRank = true end
        local c = (colY[1] >= colY[2]) and 1 or 2
        local x = 14 + (c - 1) * (colW + 20)
        hi = hi + 1
        local hd = h.heads[hi]
        if not hd then hd = K.Text(h.panel, 11, C.muted) h.heads[hi] = hd end
        hd:ClearAllPoints()
        hd:SetPoint("TOPLEFT", x, colY[c])
        hd:SetText(g.head)
        hd:Show()
        colY[c] = colY[c] - 20
        for _, s in ipairs(g.list) do
            ri = ri + 1
            local r = h.rows[ri]
            if not r then
                r = CreateFrame("Frame", nil, h.panel)
                r:SetHeight(30)
                r.n = K.Text(r, 12, C.text)
                r.n:SetPoint("TOPLEFT", 0, 0)
                r.v = K.Text(r, 11, C.muted, "RIGHT")
                r.v:SetPoint("TOPRIGHT", 0, 0)
                r.track = r:CreateTexture(nil, "ARTWORK")
                r.track:SetHeight(4)
                r.track:SetPoint("TOPLEFT", 0, -18) r.track:SetPoint("TOPRIGHT", 0, -18)
                r.track:SetColorTexture(1, 1, 1, 0.08)
                r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
                r.fill:SetHeight(4)
                r.fill:SetPoint("LEFT", r.track, "LEFT")
                h.rows[ri] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", x, colY[c])
            r:SetWidth(colW)
            r.n:SetText(s.name)
            local hasMax = s.max > 0
            local full = hasMax and s.rank >= s.max
            local col = full and C.mint or (hasMax and C.amber or C.mint)
            r.v:SetText(hasMax and (s.rank .. (s.mod ~= 0 and (" |cff66db9e" .. (s.mod > 0 and "+" or "") .. s.mod .. "|r") or "") .. " |cff6b6b70/ " .. s.max .. "|r") or ("|cff66db9e" .. L["learned"] .. "|r"))
            r.track:SetShown(hasMax)
            r.fill:SetShown(hasMax)
            if hasMax then
                r.fill:SetColorTexture(col[1], col[2], col[3], 1)
                r.fill:SetWidth(math.max(1, colW * math.min(1, s.rank / s.max)))
            end
            r:Show()
            colY[c] = colY[c] - (hasMax and 32 or 22)
        end
        colY[c] = colY[c] - 10
    end
    for i = ri + 1, #h.rows do h.rows[i]:Hide() end
    for i = hi + 1, #h.heads do h.heads[i]:Hide() end
    h.note:SetText(#data == 0 and L["The client delivers no skills right now - wait a moment after logging in."]
        or (noRank and L["WoW Forever does not provide weapon skill levels - showing what you have learned."]
        or L["Green = maxed  ·  gold = can still improve (use the weapon or take hits)"]))
end
end)

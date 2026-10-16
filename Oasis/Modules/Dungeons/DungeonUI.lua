-- Oasis: Dungeon-Journal-Oberflaeche
-- Startseite mit Dungeon-Karten (Blizzards Ladebildschirme), Dungeon-Seite mit Banner und Reitern
-- Bosse (Liste + 3D-Modell + Beute), Beute, Quests, Gilde.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Dungeons", function()   -- Modul Dungeons (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
-- Sicherheit beim Empfang (Addon-Nachrichten anderer koennen manipuliert sein):
-- Texte entschaerfen, Zahlen begrenzen, Namen pruefen, Flut drosseln
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape-Sequenzen (|c |r |n |H |T |K |A ...) und Steuerzeichen unschaedlich; links: gueltige Item-/Zauberlinks bleiben
    function SEC.Text(s, max, links)
        if s == nil then return "" end
        s = tostring(s):gsub("[%z\1-\31\127]", " ")
        local keep
        if links then
            keep = {}
            s = s:gsub("(|c([^|]-)|H(%a+):([^|]*)|h(%[[^|%]]*%])|h|r)", function(all, col, kind, data)
                if #keep < 8 and (kind == "item" or kind == "spell") and data:match("^[%d:%-]+$")
                    and (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then
                    keep[#keep + 1] = all
                    return "\1" .. #keep .. "\2"
                end
            end)
        end
        s = cut((s:gsub("|", "/")), max)
        if keep then s = s:gsub("\1%d*$", ""):gsub("\1(%d+)\2", function(i) return keep[tonumber(i)] or "" end) end
        return s
    end
    function SEC.Link(s)
        if type(s) ~= "string" or #s > 300 then return nil end
        local col = s:match("^|c([^|]-)|Hitem:[%d:%-]+|h%[[^|%]]*%]|h|r$")
        if not col or not (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then return nil end
        return s
    end
    function SEC.Num(v, lo, hi, int)
        v = tonumber(v)
        if not v or v ~= v or v < lo or v > hi then return nil end
        if int then v = math.floor(v) end
        return v
    end
    function SEC.Name(s)
        if type(s) ~= "string" or s == "" or #s > 64 or s:find("[|%c]") then return nil end
        return s
    end
    local last, lastN = {}, 0
    function SEC.Rate(key, sec)
        local now = GetTime()
        local t = last[key]
        if t and now - t < sec then return false end
        if not t then lastN = lastN + 1 if lastN > 500 then last, lastN = {}, 0 end end
        last[key] = now
        return true
    end
end
local D = ns.Dungeons

local LS = "Interface\\Glues\\LoadingScreens\\"
-- Blizzards Ladebildschirme (englischer Dungeon-Name -> Datei); fehlt eine Datei, bleibt die Farbstimmung
local CAM = LS .. "camelot160\\main\\"
local ART = {
    ["Ragefire Chasm"] = LS .. "LoadScreenRagefireChasm",
    ["Hall of Thanes"] = CAM .. "loadscreen_camelot_oldironforge",
    ["Ruins of Lordaeron"] = CAM .. "loadscreen_camelot_ruinsoflordaeron",
    ["Wailing Caverns"] = LS .. "LoadScreenWailingCaverns",
    ["The Deadmines"] = LS .. "LoadScreenDeadmines",
    ["Shadowfang Keep"] = LS .. "LoadScreenShadowFangKeep",
    ["Blackfathom Deeps"] = LS .. "LoadScreenBlackFathomDeeps",
    ["The Stockade"] = LS .. "LoadScreenStormwindStockade",
    ["Excavation Site: Wetlands"] = CAM .. "loadscreen_camelot_excavation",
    ["City of Dalaran"] = CAM .. "loadscreen_camelot_dalaran",
    ["Gnomeregan"] = LS .. "LoadScreenGnomeregan",
    ["Razorfen Kraul"] = LS .. "LoadScreenRazorfenKraul",
    ["Razorfen Downs"] = LS .. "LoadScreenRazorfenDowns",
    ["Scarlet Monastery Graveyard"] = LS .. "LoadScreenScarletMonastery2",
    ["Scarlet Monastery Library"] = LS .. "LoadScreenScarletMonastery2",
    ["Scarlet Monastery Armory"] = LS .. "LoadScreenScarletMonastery2",
    ["Scarlet Monastery Cathedral"] = LS .. "LoadScreenScarletMonastery2",
    ["Uldaman"] = LS .. "LoadScreenUldaman",
    ["Zul'Farrak"] = LS .. "LoadScreenZulFarrak",
    ["Maraudon"] = LS .. "LoadScreenMaraudon",
    ["Sunken Temple"] = LS .. "LoadScreenSunkenTemple",
    ["Blackrock Depths"] = LS .. "LoadScreenBlackrockDepths",
    ["Lower Blackrock Spire"] = LS .. "LoadScreenBlackrockSpire",
    ["Upper Blackrock Spire"] = LS .. "LoadScreenUpperBlackrockSpire",
    ["Dire Maul East"] = LS .. "LoadScreenDireMaul",
    ["Dire Maul North"] = LS .. "LoadScreenDireMaul",
    ["Dire Maul West"] = LS .. "LoadScreenDireMaul",
    ["Scholomance"] = LS .. "LoadScreenScholomance",
    ["Stratholme Main Gate"] = LS .. "LoadScreenStrathome",
    ["Stratholme Service Gate"] = LS .. "LoadScreenStrathome",
    ["Karazhan Crypts"] = LS .. "loadscreen_classic_karazhancrypts",
    ["Demon Fall Canyon"] = LS .. "loadscreen_classic_demon_fall_canyon",
}
-- ohne eigenes Bild: WoW-Forever-Kontinentbild (Kalimdor / Oestliche Koenigreiche)
local KALIMDOR = { ["The Barrens"] = true, ["Feralas"] = true, ["Ashenvale"] = true, ["Un'Goro Crater"] = true, ["Tanaris"] = true,
    ["Orgrimmar"] = true, ["Dustwallow Marsh"] = true, ["Desolace"] = true, ["Azshara"] = true, ["Thousand Needles"] = true }
-- Farbstimmung je Dungeon (fuer Karten ohne Bild und als Akzent)
local TONE = {
    ragefire = { 0.55, 0.22, 0.08 }, hallofthanes = { 0.50, 0.36, 0.16 }, ruinsoflordaeron = { 0.38, 0.40, 0.30 },
    wailingcaverns = { 0.30, 0.42, 0.16 }, deadmines = { 0.45, 0.30, 0.16 }, shadowfangkeep = { 0.36, 0.26, 0.46 },
    blackfathomdeeps = { 0.18, 0.36, 0.42 }, stockade = { 0.36, 0.34, 0.32 }, gnomeregan = { 0.28, 0.38, 0.46 },
    razorfenkraul = { 0.42, 0.32, 0.18 }, razorfendowns = { 0.32, 0.30, 0.36 }, uldaman = { 0.46, 0.38, 0.22 },
    zulfarrak = { 0.52, 0.40, 0.20 }, maraudon = { 0.34, 0.26, 0.40 }, sunkentemple = { 0.18, 0.38, 0.30 },
    blackrockdepths = { 0.52, 0.18, 0.10 }, scholomance = { 0.30, 0.40, 0.34 },
}
local function tone(d)
    local k = d.dbKey or tostring(d.nameEN or d.name):lower():gsub("[^a-z]", "")
    if TONE[k] then return TONE[k] end
    if k:find("^sm") or k:find("scarlet") then return { 0.52, 0.14, 0.14 } end
    if k:find("diremaul") then return { 0.26, 0.38, 0.30 } end
    if k:find("strat") then return { 0.40, 0.26, 0.40 } end
    if k:find("brs") or k:find("blackrock") then return { 0.50, 0.20, 0.10 } end
    return { C.accent2[1], C.accent2[2], C.accent2[3] }
end
local function artOf(d)
    local a = ART[d.nameEN or ""] or ART[d.key or ""]
    if a then return a end
    local z = d.data and d.data.zone
    if z then return CAM .. (KALIMDOR[z] and "loadscreen_camelot_kalimdor" or "loadscreen_camelot_easternkingdom") end
end

-- Dungeon-Karten aus dem Client: Karten-IDs per Name finden (alle Ebenen), Kacheln der Kartengrafik
local mapCache = {}
-- Namen vergleichbar machen: Kleinschreibung, ohne Artikel (Die/Der/Das/The), ohne Satzzeichen
local function normName(n)
    n = tostring(n or ""):lower()
    n = n:gsub("^die ", ""):gsub("^der ", ""):gsub("^das ", ""):gsub("^the ", "")
    return (n:gsub("[%p%s]", ""))
end
-- im Dungeon stehend: die Karte, die WoW dort benutzt, merken (auch fuer spaeter)
local function learnMap()
    local inInst, kind = IsInInstance()
    if not (inInst and (kind == "party" or kind == "raid")) then return end
    local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local name = ns.safe(GetInstanceInfo())
    if id and name then
        ns.db.dungeonMapIds = ns.db.dungeonMapIds or {}
        ns.db.dungeonMapIds[normName(name)] = id
    end
end
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(3, function() pcall(learnMap) end) end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(5, function() pcall(learnMap) end) end)

local function dungeonMaps(d)
    local key = d.key or d.name
    if mapCache[key] and #mapCache[key] > 0 then return mapCache[key] end
    local out, seen = {}, {}
    local function add(id, name)
        if id and not seen[id] then seen[id] = true out[#out + 1] = { id = id, name = name } end
    end
    local want = {}
    for _, n in ipairs({ d.name, d.nameEN, d.nameDE, d.de }) do if n then want[normName(n)] = true end end
    -- bekannte Karten aus den Boss-Daten (Blizzard-Kartennummern)
    if ns.BossPos and ns.BossPos[d.dbKey or d.key] then
        for _, bp in ipairs(ns.BossPos[d.dbKey or d.key]) do
            if bp.map and not seen[bp.map] then
                local ok, info = pcall(C_Map.GetMapInfo, bp.map)
                if ok and info then add(bp.map, info.name) end
            end
        end
    end
    -- gemerkte Karte aus einem Besuch
    for n in pairs(want) do
        local id = ns.db.dungeonMapIds and ns.db.dungeonMapIds[n]
        if id then
            local ok, info = pcall(C_Map.GetMapInfo, id)
            add(id, ok and info and info.name or d.name)
        end
    end
    if C_Map and C_Map.GetMapInfo then
        for id = 1, 3000 do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and info and info.name and want[normName(info.name)] and (info.mapType == 3 or info.mapType == 4 or info.mapType == 5 or info.mapType == 6) then
                add(id, info.name)
            end
        end
        -- Ebenen: Kinder der gefundenen Karte dazunehmen
        if #out > 0 and C_Map.GetMapChildrenInfo then
            local ok, kids = pcall(C_Map.GetMapChildrenInfo, out[1].id)
            if ok and kids then
                for _, k in ipairs(kids) do add(k.mapID, k.name) end
            end
        end
    end
    mapCache[key] = out
    return out
end
local function drawMap(host, mapID, focus)
    host.tiles = host.tiles or {}
    for _, t in ipairs(host.tiles) do t:Hide() end
    if not (mapID and C_Map and C_Map.GetMapArtLayers) then return false end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if not ok or not layers or not layers[1] then return false end
    local L1 = layers[1]
    local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not ok2 or not files or #files == 0 then return false end
    local cols = math.ceil(L1.layerWidth / L1.tileWidth)
    local rows = math.ceil(L1.layerHeight / L1.tileHeight)
    local W, H = host:GetWidth(), host:GetHeight()
    if W < 50 then W, H = 600, 400 end
    local scale = math.min(W / L1.layerWidth, H / L1.layerHeight)
    if focus then scale = math.max(W / L1.layerWidth, H / L1.layerHeight) * (focus.zoom or 1) end
    local tw, th = L1.tileWidth * scale, L1.tileHeight * scale
    local ox = (W - L1.layerWidth * scale) / 2
    local oy = (H - L1.layerHeight * scale) / 2
    if focus and focus.x then
        local mw, mh = L1.layerWidth * scale, L1.layerHeight * scale
        ox = math.max(W - mw, math.min(0, W / 2 - focus.x * mw))
        oy = math.max(H - mh, math.min(0, H / 2 - focus.y * mh))
    end
    host.mapRect = { x = ox, y = oy, w = L1.layerWidth * scale, h = L1.layerHeight * scale }
    for i, file in ipairs(files) do
        local t = host.tiles[i]
        if not t then t = host:CreateTexture(nil, "ARTWORK") host.tiles[i] = t end
        local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
        if r < rows then
            t:SetTexture(file)
            t:SetSize(tw, th)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", host, "TOPLEFT", ox + c * tw, -(oy + r * th))
            t:Show()
        end
    end
    return true
end

-- Quests ordnen: fehlende zuerst, dann die im Log, erledigte ans Ende; dazu die Anzahl je Zustand
local QUEST_RANK = { open = 1, log = 2, done = 3 }
local function questOrder(quests)
    local n = { open = 0, log = 0, done = 0 }
    for i, q in ipairs(quests) do
        q.pos = i
        n[q.state] = (n[q.state] or 0) + 1
    end
    table.sort(quests, function(a, b)
        local ra, rb = QUEST_RANK[a.state] or 1, QUEST_RANK[b.state] or 1
        if ra ~= rb then return ra < rb end
        return a.pos < b.pos
    end)
    return n
end
-- Zustand einer Quest als kurzes Wort mit Farbe (Liste und Zaehlzeile)
local QUEST_STATE = {
    open = { "Fehlt", "ff7fa6", { 1, 0.42, 0.62 } },
    log = { "Aktiv", "ffd24a", { 1, 0.80, 0.25 } },
    done = { "Erledigt", "66db9e", { 0.35, 0.85, 0.60 } },
}

-- Forever Atlas installiert? (nur dann duerfen wir dessen eigene Kartenbilder verwenden)
local function hasForeverAtlas()
    local get = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not get then return false end
    local ok, name, _, _, loadable, reason = pcall(get, "AtlasLootClassic")
    return ok and type(name) == "string" and reason ~= "MISSING"
end
local S   -- Seitenzustand (wird weiter unten gefuellt)
-- Boss anklicken: in den Reiter "Bosse" springen und diesen Boss zeigen
local function openBoss(host, name)
    local d = host.curDungeon
    local raw = d and d.data and d.data.bosses
    if not raw or not name then return end
    local want = name:lower():gsub(" %(.-%)", "")
    for i, b in ipairs(raw) do
        local n = tostring(b.name or ""):lower()
        if n == want or n:find(want, 1, true) or want:find(n, 1, true) then
            S.view, S.dungeon, S.boss, S.tab = "dungeon", d.key, i, "bosses"
            if host.worldMapOverlay then
                if not ns.inCombat() and WorldMapFrame and WorldMapFrame:IsShown() then
                    if HideUIPanel then HideUIPanel(WorldMapFrame) end
                end
                ns.ShowPage("dungeons")
            else ns.RefreshPage("dungeons") end
            return
        end
    end
end
local function legacyPins(host, list, floor, toXY, hidden)
    host.lpins = host.lpins or {}
    for _, pn in ipairs(host.lpins) do pn:Hide() end
    local n = 0
    for idx, bp in ipairs(list or {}) do
        if (bp[4] or 1) == floor then
            n = n + 1
            local pin = host.lpins[n]
            if not pin then
                pin = CreateFrame("Frame", nil, host)
                pin:SetSize(22, 22)
                pin.ring = pin:CreateTexture(nil, "ARTWORK")
                pin.ring:SetTexture(ns.MEDIA .. "dot")
                pin.ring:SetAllPoints()
                pin.ring:SetVertexColor(0.05, 0.05, 0.06)
                pin.dot = pin:CreateTexture(nil, "OVERLAY")
                pin.dot:SetTexture(ns.MEDIA .. "dot")
                pin.dot:SetSize(16, 16)
                pin.dot:SetPoint("CENTER")
                pin.dot:SetVertexColor(C.red[1], C.red[2], C.red[3])
                pin.num = K.Title(pin, 10, C.text, "CENTER")
                K.CenterNum(pin.num, nil, "CENTER", 0, 0)
                pin.lbl = K.Text(pin, 10, C.text, "CENTER")
                pin.lbl:SetPoint("TOP", pin, "BOTTOM", 0, -1)
                pin.lbl:SetShadowOffset(1, -1)
                pin:EnableMouse(true)
                pin:SetScript("OnEnter", function(self)
                    if self.tip then K.ShowTip(self, self.tip) end
                    if not self.hidden then self.dot:SetVertexColor(1, 0.45, 0.4) end
                end)
                pin:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                    self.dot:SetVertexColor(C.red[1], C.red[2], C.red[3])
                end)
                pin:SetScript("OnMouseUp", function(self) openBoss(host, self.boss) end)
                host.lpins[n] = pin
            end
            local x, y = toXY(bp[2] / 100, bp[3] / 100)
            pin:SetFrameLevel(host:GetFrameLevel() + 10)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", host, "TOPLEFT", x, -y)
            pin.num:SetText(idx)
            pin.lbl:SetText(bp[1])
            pin.boss = bp[1]
            pin.hidden = hidden
            pin.tip = { bp[1] }
            -- 0.6.307: was der Boss fallen laesst (Qualitaetsfarbe, Upgrades gruen) direkt im Tooltip
            if D.BossTipLines then
                local ok, lines = pcall(D.BossTipLines, bp[1])
                for _, ln in ipairs(ok and lines or {}) do pin.tip[#pin.tip + 1] = ln end
            end
            if host.rough then pin.tip[#pin.tip + 1] = "|cffe8b44a" .. L["Position nur ungefaehr"] .. "|r" end
            pin.tip[#pin.tip + 1] = "|cff66db9e" .. L["Klick: Boss und Beute zeigen"] .. "|r"
            pin:SetAlpha(host.rough and 0.6 or 1)
            -- auf Bildern mit eingezeichneten Bossen: unsichtbare Klickflaeche
            pin.ring:SetShown(not hidden) pin.dot:SetShown(not hidden) pin.num:SetShown(not hidden) pin.lbl:SetShown(not hidden)
            pin:SetSize(hidden and 34 or 22, hidden and 34 or 22)
            pin:Show()
        end
    end
end
-- Karte des Clients zu einer Ebene: die Karten eines Dungeons nach Nummer geordnet; die Ebene zaehlt als Platz
-- in dieser Reihe (Fluegel teilen sich einen Ordner: Ebene 3 = dritte Karte), sonst der Platz in der Ebenenliste
local function clientMapFor(d, cfg, floor)
    if not d or not (C_Map and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, found = pcall(dungeonMaps, d)
    if not ok or type(found) ~= "table" or #found == 0 then return nil end
    local maps = {}
    for i, m in ipairs(found) do maps[i] = m end
    table.sort(maps, function(a, b) return a.id < b.id end)
    local idx = 1
    for i, fl in ipairs(cfg.floors or { 1 }) do if fl == floor then idx = i end end
    return maps[tonumber(floor) or 0] or maps[idx] or maps[1]
end
local function drawLegacyMap(host, cfg, floor)
    host.ltiles = host.ltiles or {}
    for _, t in ipairs(host.ltiles) do t:Hide() end
    if host.lpins then for _, pn in ipairs(host.lpins) do pn:Hide() end end
    if not cfg then return false end
    host.rough = cfg.rough
    local W, H = host:GetWidth(), host:GetHeight()
    if W < 50 then W, H = 600, 400 end
    if cfg.folder then
        -- Neuer Client (Forever): die alten Bildpfade gibt es dort nicht mehr - das Kartenbild kommt ueber die
        -- Kartennummer des Dungeons, die Boss-Positionen (in % des Bildes) passen unveraendert darauf.
        local m = clientMapFor(host.curDungeon, cfg, floor)
        if m and drawMap(host, m.id) and host.mapRect then
            local R = host.mapRect
            host.lrect = { R.x, R.y, R.w, R.h }
            legacyPins(host, cfg.pins, floor, function(x, y) return R.x + x * R.w, R.y + y * R.h end)
            return true
        end
        if host.tiles then for _, t in ipairs(host.tiles) do t:Hide() end end
        -- 4x3 Kacheln in einem 3:2-Rahmen (so wie die Boss-Positionen aus Forever Atlas gemessen sind)
        local asp = 1.5
        local dw = math.min(W, H * asp)
        local dh = dw / asp
        local tw, th = dw / 4, dh / 3
        local ox, oy = (W - dw) / 2, (H - dh) / 2
        host.lrect = { ox, oy, dw, dh }
        for i = 1, 12 do
            local t = host.ltiles[i]
            if not t then t = host:CreateTexture(nil, "ARTWORK") host.ltiles[i] = t end
            local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
            local path = cfg.special and ("Interface\\Worldmap\\" .. cfg.folder .. "\\" .. cfg.folder .. i)
                or ("Interface\\Worldmap\\" .. cfg.folder .. "\\" .. cfg.folder .. floor .. "_" .. i)
            t:SetTexture(path)
            t:SetSize(tw, th)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", host, "TOPLEFT", ox + c * tw, -(oy + r * th))
            t:Show()
        end
        legacyPins(host, cfg.pins, floor, function(x, y) return ox + x * dw, oy + y * dh end)
        return true
    elseif cfg.bundled then
        local asp = cfg.aspect or 1
        local dw = math.min(W, H * asp)
        local dh = dw / asp
        local ox, oy = (W - dw) / 2, (H - dh) / 2
        host.lrect = { ox, oy, dw, dh }
        local t = host.ltiles[1]
        if not t then t = host:CreateTexture(nil, "ARTWORK") host.ltiles[1] = t end
        t:SetTexture(cfg.bundled)
        t:SetSize(dw, dh)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", host, "TOPLEFT", ox, -oy)
        t:Show()
        -- Bosse sind im Bild schon eingezeichnet: nur unsichtbare Klickflaechen darueber
        legacyPins(host, cfg.pins, floor, function(x, y) return ox + x * dw, oy + y * dh end, true)
        return true
    end
    return false
end

local function gradient(tex, orient, a1, a2)
    local ok = CreateColor and pcall(function()
        tex:SetGradient(orient, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    end)
    if not ok then tex:SetColorTexture(0, 0, 0, (a1 + a2) / 2) end
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Gemeinsames fuer Optik und Animation
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local GREEN = { 0.35, 1, 0.5 }
local function st() return (ns.db and ns.db.settings) or {} end
local function animOn() return not st().noAnim end
local function grad(tex, dir, c, a1, a2)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2)
    end
end
local function hexRGB(h)
    return tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, tonumber(h:sub(7, 8), 16) / 255
end
local function pageShown()
    local def = ns.PageDef and ns.PageDef("dungeons")
    return def and def.frame and def.frame:IsVisible()
end

------------------------------------------------------------------------
-- Items: Name/Farbe/Icon aus dem Client, sonst aus der Datenbank
------------------------------------------------------------------------
local QCOL = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }
local function itemInfo(it)
    local id, fbName, _, fbQ = it[1], it[2], it[3], it[4]
    local name, link, q, _, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(id)
    if not name and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    q = q or fbQ or 2
    local slot = equipLoc and equipLoc ~= "" and _G[equipLoc] or ""
    return {
        id = id, name = name or fbName or ("#" .. id), link = link, quality = q,
        icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400,
        color = QCOL[q] or QCOL[2], slot = slot,
    }
end

-- Passt das Item zu mir? 2 = passt zu Klasse und Rolle, 1 = tragbar/allgemein, 0 = nicht fuer mich
local FIT_ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local FIT_WEAP = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 6, 10, 13, 15 },
}
local FIT_SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local FIT_STATS = {
    WARRIOR = { "STRENGTH", "STAMINA", "AGILITY" }, ROGUE = { "AGILITY", "STRENGTH", "ATTACK_POWER" },
    HUNTER = { "AGILITY", "ATTACK_POWER", "RANGED_ATTACK_POWER" }, MAGE = { "INTELLECT", "SPELL_POWER", "SPELL_DAMAGE_DONE" },
    WARLOCK = { "INTELLECT", "SPELL_POWER", "SPELL_DAMAGE_DONE", "STAMINA" }, PRIEST = { "INTELLECT", "SPIRIT", "SPELL_HEALING_DONE", "SPELL_POWER" },
    PALADIN = { "STRENGTH", "INTELLECT", "STAMINA" }, SHAMAN = { "INTELLECT", "STRENGTH", "AGILITY" }, DRUID = { "INTELLECT", "AGILITY", "STRENGTH", "SPIRIT" },
}
local fitCache = {}
local function fitFor(id)
    if fitCache[id] then return fitCache[id] end
    local _, cls = UnitClass("player")
    local lvl = ns.safe(UnitLevel("player")) or 60
    local ok, _, _, _, equipLoc, _, classID, sub = pcall(C_Item.GetItemInfoInstant, id)
    if not ok or not classID then return 1 end
    local use = true
    if classID == 4 then
        if sub == 6 then use = FIT_SHIELD[cls] or false
        elseif sub and sub >= 1 and sub <= 4 then
            local max = FIT_ARMOR[cls] or 1
            if lvl < 40 and (cls == "WARRIOR" or cls == "PALADIN") then max = 3 end
            if lvl < 40 and (cls == "HUNTER" or cls == "SHAMAN") then max = 2 end
            use = sub <= max
            if use and sub < max and equipLoc ~= "INVTYPE_CLOAK" then use = "low" end
        elseif sub and sub > 4 then use = false end
    elseif classID == 2 then
        use = tContains(FIT_WEAP[cls] or {}, sub)
    else
        fitCache[id] = 1
        return 1
    end
    if not use then fitCache[id] = 0 return 0 end
    local res = 1
    local link = select(2, C_Item.GetItemInfo(id))
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if link and getStats then
        local okS, sts = pcall(getStats, link)
        if okS and sts then
            local good, any = false, false
            for k in pairs(sts) do
                any = true
                for _, want in ipairs(FIT_STATS[cls] or {}) do if k:find(want, 1, true) then good = true end end
            end
            if good and use ~= "low" then res = 2 elseif any and not good then res = (use == "low") and 0 or 1 end
        end
        fitCache[id] = res
    end
    return res
end
D.FitFor = fitFor

-- Markierungen: gesucht / Gildenbank / habe ich
local function markers(id)
    local t = {}
    -- 0.6.308: alle Suchenden aus der Gilde, nicht nur der erste
    local seek = {}
    for _, w in ipairs(Store.List("wants")) do
        if w.itemID == id and w.who and not ns.isMe(w.who) then seek[#seek + 1] = w.who end
    end
    if #seek > 0 then
        t[#t + 1] = "|cffffc24d" .. (L["gesucht: %s"]):format(ns.displayName(seek[1])) .. (#seek > 1 and (" +" .. (#seek - 1)) or "") .. "|r"
    end
    -- wer aus der Gilde es schon erbeutet hat (neuester Eintrag im Beute-Log)
    local got
    for _, x in ipairs(Store.List("loot")) do
        if x.itemID == id and x.who and (not got or (x.ts or 0) > (got.ts or 0)) then got = x end
    end
    if got then t[#t + 1] = "|cffb48cff" .. (L["erbeutet: %s"]):format(ns.displayName(got.who)) .. "|r" end
    local bank = ns.GuildBank and ns.GuildBank.Count(id) or 0
    if bank > 0 then t[#t + 1] = "|cff9b8cff" .. L["Bank: "] .. bank .. "|r" end
    local ok, have = pcall(C_Item.GetItemCount, id, true)
    if ok and (ns.safe(have) or 0) > 0 then t[#t + 1] = "|cff66db9e" .. L["hast du"] .. "|r" end
    return table.concat(t, "  ")
end

------------------------------------------------------------------------
-- Verbesserungen (Vergleich mit angelegter Ausruestung ueber ns.Upgrade)
------------------------------------------------------------------------
local upCache, dgUpCache = {}, {}
local function upOn()
    return st().dgUpgradeGlow ~= false and ns.Upgrade ~= nil and ns.Upgrade.ForItem ~= nil
end
local function upPct(id)
    if not id or not upOn() then return nil end
    local c = upCache[id]
    if c ~= nil then return c or nil end
    local pct = ns.Upgrade.ForItem(id)
    local okI, name = pcall(C_Item.GetItemInfo, id)
    if okI and name then upCache[id] = pct or false end   -- erst merken, wenn der Client das Item kennt
    return pct
end
local function resetUp() wipe(upCache) wipe(dgUpCache) end
D.ResetUpgrades = resetUp
-- einheitliche Kennzeichnung: up = besser als angelegt, fit = passt zur Klasse
local function markOf(id)
    local pct = upPct(id)
    return { pct = pct, up = (pct and pct > 0) or false, fit = fitFor(id) }
end
local function rankOf(id)
    local m = markOf(id)
    if m.up then return 1000 + math.min(m.pct, 900) end
    return m.fit * 10
end
local function sortLoot(rows)
    for i, r in ipairs(rows) do r.n = r.n or i r.rk = rankOf(r.it[1]) end
    table.sort(rows, function(a, c) if a.rk ~= c.rk then return a.rk > c.rk end return a.n < c.n end)
end
-- Anzahl Verbesserungen in einem Dungeon (nur Daten ohne Blizzard-Journal-Zugriff)
local function dungeonUps(d)
    if not upOn() or not d or d.source == "blizzard" then return 0 end
    local c = dgUpCache[d.key]
    if c then return c end
    local n, all = 0, true
    local ok, bosses = pcall(D.Bosses, d)
    for _, b in ipairs(ok and bosses or {}) do
        for _, it in ipairs(b.loot or {}) do
            local p = upPct(it[1])
            if p and p > 0 then n = n + 1 end
            if upCache[it[1]] == nil then all = false end
        end
    end
    if all then dgUpCache[d.key] = n end
    return n
end
local qCache = {}
local function questCount(d)
    local c = qCache[d.key]
    local now = GetTime()
    if c and now - c.t < 5 then return c.n, c.all end
    local n, all = 0, 0
    if D.MyQuestCount then n, all = D.MyQuestCount(d) end
    qCache[d.key] = { n = n, all = all, t = now }
    return n, all
end
local function othersInRange(d)
    local out = {}
    local ok, list = pcall(D.InRange, d)
    for _, m in ipairs(ok and list or {}) do if not ns.isMe(m.name) then out[#out + 1] = m end end
    return out
end
local function refreshSoon()
    if pageShown() then ns.RefreshPage("dungeons") end
end
-- 0.6.307: Tooltip-Zeilen fuer einen Boss-Pin auf der Dungeonkarte: Beute (bis 8), Upgrades fuer mich gruen markiert
function D.BossTipLines(bossName)
    local d = D.Get(S.dungeon)
    if not d or not bossName then return {} end
    local ok, bosses = pcall(D.Bosses, d)
    local boss
    for _, bo in ipairs(ok and bosses or {}) do if bo.name == bossName then boss = bo break end end
    if not boss or not boss.loot or #boss.loot == 0 then return {} end
    local out = { " ", "|cff888888" .. L["Beute"] .. ":|r" }
    for i, it in ipairs(boss.loot) do
        if i > 8 then out[#out + 1] = "|cff777777+" .. (#boss.loot - 8) .. "|r" break end
        local info = itemInfo(it)
        local m = markOf(it[1])
        out[#out + 1] = "|c" .. (info.color or "ffffffff") .. (info.name or "?") .. "|r"
            .. ((m and m.up) and ("  |cff66db9e+" .. math.min(m.pct or 0, 999) .. "%|r") or "")
    end
    return out
end
ns.On("PLAYER_EQUIPMENT_CHANGED", function() resetUp() ns.After(0.3, refreshSoon) end)

------------------------------------------------------------------------
-- Beute-Karten (Boss- und Beute-Liste): Leuchten bei Verbesserung, Tooltip, Klick-Menue
------------------------------------------------------------------------
local function lootMenu(owner, id)
    local info = itemInfo({ id })
    local d = S and D.Get(S.dungeon)
    local dname = d and d.name or ""
    local label = info.link or info.name
    local items = {}
    items[#items + 1] = { text = L["Auf meine Wunschliste"], disabled = not (ns.Wants and ns.Wants.Add), fn = function()
        local rec = ns.Wants.Add(label, 1, dname)
        if rec then ns.print((L["Auf die Wunschliste gesetzt: %s"]):format(label)) end
        ns.RefreshPage("dungeons")
    end }
    items[#items + 1] = { text = L["Im Gildenchat fragen ..."], disabled = not (IsInGuild and IsInGuild()), fn = function()
        local txt = "/g " .. (L["Wer geht mit nach %s? Ich suche %s"]):format(dname, label)
        if ChatFrame_OpenChat then ChatFrame_OpenChat(txt) end
    end }
    items[#items + 1] = { text = L["Im Chat verlinken"], disabled = info.link == nil, fn = function()
        if info.link and ChatEdit_InsertLink and not ChatEdit_InsertLink(info.link) and ChatFrame_OpenChat then ChatFrame_OpenChat(info.link) end
    end }
    K.ShowMenu(owner, items, info.name, 210)
end

local function lootRow(l)
    local r = K.Row(l)
    r.upBg = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.upBg:SetAllPoints()
    grad(r.upBg, "HORIZONTAL", GREEN, 0.14, 0)
    r.upBg:Hide()
    r.iconHost = CreateFrame("Frame", nil, r)
    r.iconHost:SetSize(30, 30)
    r.iconHost:SetPoint("LEFT", 8, 0)
    r.iconBorder = r.iconHost:CreateTexture(nil, "ARTWORK")
    r.iconBorder:SetAllPoints()
    r.icon = r.iconHost:CreateTexture(nil, "OVERLAY")
    r.icon:SetPoint("TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.pct = K.Title(r, 12, GREEN, "RIGHT")
    r.pct:SetPoint("TOPRIGHT", -12, -7)
    -- Drop-Chance rechtsbuendig unten
    r.drop = K.Text(r, 11, { 0.79, 0.70, 0.48 }, "RIGHT")
    r.drop:SetPoint("BOTTOMRIGHT", -12, 7)
    r.cols.name = K.Text(r, 13, C.text)
    r.cols.name:SetPoint("TOPLEFT", 48, -6)
    r.cols.name:SetPoint("RIGHT", r, "RIGHT", -64, 0)
    r.cols.sub = K.Text(r, 11, C.muted)
    r.cols.sub:SetPoint("BOTTOMLEFT", 48, 6)
    r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -92, 0)
    r.cols.sub:SetWordWrap(false)
    r:RegisterForClicks("AnyUp")
    r:SetScript("OnEnter", function(self)
        local id = self.item and self.item.it and self.item.it[1]
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, id)
        local m = markOf(id)
        if m.up then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff66db9e" .. (L["Besser als dein angelegtes Teil (+%d%%)"]):format(math.min(m.pct, 999)) .. "|r")
            local against = ns.Upgrade.Against and ns.Upgrade.Against(id)
            GameTooltip:AddLine("|cff888888" .. L["Statt:"] .. "|r " .. (against or ("|cff888888" .. L["leerer Platz"] .. "|r")))
        elseif m.fit == 2 then
            GameTooltip:AddLine("|cff66db9e" .. L["fuer dich"] .. "|r")
        end
        GameTooltip:AddLine("|cff777777" .. L["Shift-Klick: verlinken  ·  Rechtsklick: Menue"] .. "|r")
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, btn)
        local id = self.item and self.item.it and self.item.it[1]
        if not id then return end
        if btn == "RightButton" then lootMenu(self, id) return end
        local info = itemInfo(self.item.it)
        if info.link and IsModifiedClick and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(info.link) end
    end)
    return r
end
local function lootUpdate(r, e)
    local info = itemInfo(e.it)
    r.icon:SetTexture(info.icon)
    local rr, gg, bb = hexRGB(info.color)
    r.iconBorder:SetColorTexture(rr, gg, bb, 0.9)
    r.cols.name:SetText("|c" .. info.color .. info.name .. "|r")
    local sub = {}
    if info.slot ~= "" then sub[#sub + 1] = info.slot end
    if e.boss then sub[#sub + 1] = "|cff888888" .. e.boss .. "|r" end
    local m = markOf(info.id)
    local s = st()
    if m.up then
        r.pct:SetText("+" .. math.min(m.pct, 999) .. "%")
    else
        r.pct:SetText("")
        if m.fit == 2 and s.dgForYou ~= false then table.insert(sub, 1, "|cff66db9e" .. L["fuer dich"] .. "|r") end
    end
    r.upBg:SetShown(m.up)
    if ns.Upgrade and ns.Upgrade.Glow then pcall(ns.Upgrade.Glow, r.iconHost, m.up and m.pct or nil) end
    r:SetAlpha((m.fit == 0 and not e.noDim and s.dgDimUnfit ~= false) and 0.45 or 1)
    local mk = s.dgMarkers ~= false and markers(info.id) or ""
    if mk ~= "" then sub[#sub + 1] = mk end
    -- Drop-Chance: FojjiCore (Forever-Werte, nur gelesen) wenn installiert, sonst die eigene Tabelle (Classic, aus AtlasLootClassic)
    local odds = (ns.Fojji and ns.Fojji.Odds and ns.Fojji.Odds(info.id)) or D.DropRate(info.id)
    r.drop:SetText(odds and (L["Drop %s %%"]):format(odds >= 10 and math.floor(odds + 0.5) or (math.floor(odds * 10 + 0.5) / 10)) or "")
    if e.versus and m.up and ns.Upgrade and ns.Upgrade.Against then
        local ok, against = pcall(ns.Upgrade.Against, info.id)
        sub[#sub + 1] = "|cff888888" .. L["Statt:"] .. "|r " .. ((ok and against) or ("|cff888888" .. L["leerer Platz"] .. "|r"))
    end
    r.cols.sub:SetText(table.concat(sub, "  ·  "))
end

------------------------------------------------------------------------
-- Reiter mit gleitendem Balken (wie Chronik)
------------------------------------------------------------------------
local function slideTabs(parent, items, onPick)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(30)
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT") f.base:SetPoint("BOTTOMRIGHT")
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.buttons = {}
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.key = it.key
        b.hov = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.hov:SetAllPoints()
        grad(b.hov, "VERTICAL", C.accent, 0.12, 0)
        b.hov:SetAlpha(0)
        b.label = K.Text(b, 13, C.muted, "CENTER")
        b.label:SetText(it.text)
        b.count = K.Text(b, 10, C.dim)
        b:SetScript("OnClick", function(self) f:Select(self.key, true) end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(f.value == self.key and 0.6 or 0)
            if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        end)
        f.buttons[i] = b
    end
    f.ind = f:CreateTexture(nil, "OVERLAY")
    f.ind:SetHeight(2)
    f.ind:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    f.indGlow = f:CreateTexture(nil, "ARTWORK")
    f.indGlow:SetHeight(10)
    f.indGlow:SetPoint("BOTTOMLEFT", f.ind, "TOPLEFT")
    f.indGlow:SetPoint("BOTTOMRIGHT", f.ind, "TOPRIGHT")
    grad(f.indGlow, "VERTICAL", C.accent, 0.25, 0)
    function f:Layout()
        local x = 0
        for _, b in ipairs(self.buttons) do
            local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
            local w = math.floor((b.label:GetStringWidth() or 40) + cw + 26)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", x, 1)
            b:SetSize(w, 28)
            b.label:ClearAllPoints()
            b.label:SetPoint("CENTER", -cw / 2, 1)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
            b.x, b.w = x, w
            x = x + w + 2
        end
        self:SetWidth(math.max(10, x))
        self:MoveInd(self.value, false)
    end
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb or not tb.x then return end
        local function place(x, w)
            self.indX, self.indW = x, w
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", x + 6, 0)
            self.ind:SetWidth(math.max(1, w - 12))
        end
        local fx, fw = self.indX, self.indW
        if animate and animOn() and fx then
            K.Tween(self.ind, 0.22, function(q)
                local e = 1 - (1 - q) ^ 3
                place(fx + (tb.x - fx) * e, fw + (tb.w - fw) * e)
            end, function() place(tb.x, tb.w) end)
        else
            place(tb.x, tb.w)
        end
    end
    function f:Select(key, user)
        local changed = self.value ~= key
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            b.hov:SetAlpha(on and 0.6 or 0)
        end
        self:MoveInd(key, user and changed)
        if user and onPick then onPick(key) end
    end
    function f:SetCounts(t)
        local changed = false
        for _, b in ipairs(self.buttons) do
            local n = t[b.key]
            local s = (n and n ~= 0) and tostring(n) or ""
            if b.count:GetText() ~= s then b.count:SetText(s) changed = true end
        end
        if changed then self:Layout() end
    end
    f:Layout()
    f:Select(items[1].key)
    return f
end

-- Leerzustand mit Aktionen
local function emptyState(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(360, 130)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(96, 96)
    f.halo:SetPoint("TOP", 0, 18)
    f.halo:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    f.halo:SetAlpha(0.3)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(44, 44)
    f.disc:SetPoint("TOP", 0, -5)
    f.disc:SetVertexColor(C.accent[1] * 0.25, C.accent[2] * 0.25, C.accent[3] * 0.25)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    f.icon:SetSize(22, 22)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 13, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(340)
    f.text:SetWordWrap(true)
    f.btn = K.Button(f, "", 150, 22, "primary")
    f.btn2 = K.Button(f, "", 130, 22, "ghost")
    function f:Set(msg, b1, fn1, b2, fn2)
        self.text:SetText(msg or "")
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        self.btn2:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetScript("OnClick", fn1)
            if b2 then self.btn:SetPoint("TOPRIGHT", self.text, "BOTTOM", -4, -12)
            else self.btn:SetPoint("TOP", self.text, "BOTTOM", 0, -12) end
        end
        if b2 then
            self.btn2:SetLabel(b2)
            self.btn2:SetScript("OnClick", fn2)
            self.btn2:SetPoint("TOPLEFT", self.text, "BOTTOM", 4, -12)
        end
    end
    return f
end

------------------------------------------------------------------------
-- Zustand
------------------------------------------------------------------------
S = { view = "home", filter = nil, dungeon = nil, tab = "bosses", boss = 1, homeOffset = 0, lootSearch = "",
    homeSearch = "", homeZone = nil, sort = "level", upOnly = false, lootUp = false, lootSlot = nil, lootKind = nil }
-- Dungeon-Seite: fuenf Ansichten in drei Reitern; je Reiter merkt sich S.sub die zuletzt gezeigte Ansicht
S.sub = { g1 = "bosses", g2 = "quests" }
S.group = { bosses = "g1", loot = "g1", quests = "g2", map = "map", guild = "guild" }   -- 0.6.307: Karte eigener Reiter
-- Start-Filter neu anwenden (nach Aenderung in den Einstellungen)
function D.ResetFilter() S.filter = nil S.homeOffset = 0 ns.RefreshPage("dungeons") end

local function fits(d)
    local lvl = ns.safe(UnitLevel("player")) or 0
    return d.lo and lvl >= d.lo - 2 and lvl <= (d.hi or d.lo) + 1
end
local SORTS = { { "level", "Stufe" }, { "name", "Name" }, { "ups", "Upgrades zuerst" }, { "online", "Online zuerst" } }
local function homeList()
    local out = {}
    local q = S.homeSearch or ""
    for _, d in ipairs(D.List()) do
        local ok = (S.filter == "all" and not (S.openOnly and d.closed)) or (S.filter == "mine" and not d.closed and fits(d))
        if ok and S.homeZone and (d.location or "") ~= S.homeZone then ok = false end
        if ok and q ~= "" then
            local hay = ((d.name or "") .. " " .. (d.nameEN or "") .. " " .. (d.location or "")):lower()
            ok = hay:find(q, 1, true) ~= nil
        end
        if ok and S.upOnly and dungeonUps(d) == 0 then ok = false end
        if ok then out[#out + 1] = d end
    end
    if S.sort == "name" then
        table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    elseif S.sort == "ups" then
        local u = {}
        for _, d in ipairs(out) do u[d] = dungeonUps(d) end
        table.sort(out, function(a, b) if u[a] ~= u[b] then return u[a] > u[b] end return (a.lo or 999) < (b.lo or 999) end)
    elseif S.sort == "online" then
        local o = {}
        for _, d in ipairs(out) do o[d] = #othersInRange(d) end
        table.sort(out, function(a, b) if o[a] ~= o[b] then return o[a] > o[b] end return (a.lo or 999) < (b.lo or 999) end)
    end
    return out
end
-- Stufenfarbe wie bei Quests: grau, gruen, gelb, orange, rot (nach deiner Stufe)
local function lvlColor(d)
    if not d.lo then return C.muted end
    local me = ns.safe(UnitLevel("player")) or 1
    local diff = math.floor((d.lo + (d.hi or d.lo)) / 2) - me
    if diff >= 5 then return { 1, 0.28, 0.22 } end
    if diff >= 3 then return { 1, 0.55, 0.25 } end
    if diff >= -2 then return { 1, 0.82, 0.25 } end
    if diff >= -9 then return { 0.35, 0.85, 0.4 } end
    return { 0.6, 0.6, 0.6 }
end

-- Drop-Chance eines Teils in Prozent aus ns.DungeonDropRate ([NPC] = { [Item] = % }); je Teil der hoechste Wert
local dropIdx
function D.DropRate(itemID)
    if not itemID or not ns.DungeonDropRate then return nil end
    if not dropIdx then
        dropIdx = {}
        for _, items in pairs(ns.DungeonDropRate) do
            for id, pct in pairs(items) do
                if not dropIdx[id] or pct > dropIdx[id] then dropIdx[id] = pct end
            end
        end
    end
    return dropIdx[itemID]
end
-- Reiter "Taktik" beim Boss: worum es geht, je ein Satz fuer Tank/Heiler/Schaden, Tipps fuer die gewaehlte Klasse
function D.FillTactic(bt, d, b)
    local tac, T = bt.tac, ns.BossTactics
    local raw = d and d.data and d.data.bosses and d.data.bosses[S.boss]
    local e = T and b and not b.trash and not b.object and (T.For(b.nameEN) or T.For(raw and raw.name) or T.For(b.name)) or nil
    for _, cb in ipairs(tac.btn) do cb:SetShown(e ~= nil) end
    tac.label:SetShown(e ~= nil)
    tac.cls:SetShown(e ~= nil)
    tac.note:SetShown(e ~= nil)
    if not e then
        tac.text:SetText("|cff888888" .. L["Fuer diesen Boss gibt es noch keine Taktik."] .. "|r")
        return
    end
    tac.text:SetText(table.concat({ e.s, " ",
        "|cff6aa8ff" .. L["Tank"] .. "|r   " .. (e.tank or ""), " ",
        "|cff66db9e" .. L["Heiler"] .. "|r   " .. (e.heal or ""), " ",
        "|cffff8a7a" .. L["Schaden"] .. "|r   " .. (e.dps or "") }, "\n"))
    tac.note:SetText(e.forever and L["Aus Guides zur Forever-Beta - kann sich noch aendern."] or L["Stand Classic - in WoW Forever kann ein Boss abweichen."])
    local cls = S.tacClass or ns.safe(select(2, UnitClass("player"))) or "WARRIOR"
    for i, cb in ipairs(tac.btn) do
        cb.cls = T.CLASSES[i]
        cb.disc:Set(cb.cls)
        cb:SetAlpha(cb.cls == cls and 1 or 0.4)
    end
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
    tac.label:SetText(K.Upper((L["Tipps fuer %s"]):format(name)))
    local lines, special = T.ClassLines(e, cls)
    for i, l in ipairs(lines) do
        lines[i] = (i <= special and "|cffffd24a•|r " or "|cff777777•|r |cffa3a3a8") .. l .. (i <= special and "" or "|r")
    end
    tac.cls:SetText(table.concat(lines, "\n"))
end
-- Boss mit wenig Beute: darunter die besten Upgrades der anderen Bosse (Klick springt hin)
function D.FillMoreUps(bt, bosses, cur, nRows)
    local more = bt.more
    local list, seen = {}, {}
    for bi, b in ipairs(bosses or {}) do
        if bi ~= cur then
            for _, it in ipairs(b.loot or {}) do
                local pc = it[1] and not seen[it[1]] and upPct(it[1])
                if pc and pc > 0 then
                    seen[it[1]] = true
                    list[#list + 1] = { it = it, boss = bi, bname = b.trash and L["Trash-Gegner"] or b.name, pct = pc, n = #list }
                end
            end
        end
    end
    table.sort(list, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.n < b.n end)
    -- nur so viele, wie unter der Beuteliste Platz ist
    local room = (bt.right:GetHeight() or 0) - 90 - (nRows or 0) * 52 - 44
    local n = math.max(0, math.min(#list, #more.row, math.floor(room / 30)))
    more.want = n > 0
    more:SetHeight(22 + n * 30)
    for i, r in ipairs(more.row) do
        local e = i <= n and list[i]
        r:SetShown(e and true or false)
        if e then
            local info = itemInfo(e.it)
            r.id, r.boss = info.id, e.boss
            r.icon:SetTexture(info.icon)
            r.name:SetText("|c" .. info.color .. info.name .. "|r  |cff777777" .. e.bname .. "|r")
            r.pct:SetText("+" .. math.min(e.pct, 999) .. "%")
        end
    end
end
function D.PickBoss(i)
    if not i or i == S.boss then return end
    S.boss, S.bossAnim = i, true
    ns.RefreshPage("dungeons")
end
local function openDungeon(key, boss)
    S.view, S.dungeon, S.tab, S.boss = "dungeon", key, boss and "bosses" or "guild", boss or 1   -- 0.6.303: ohne Boss: Gilde & Gruppe
    S.fadeIn = "dv"
    ns.RefreshPage("dungeons")
end

------------------------------------------------------------------------
-- Startseite: Karten (Hover: Bild zoomt, Glow, leichtes Anheben)
------------------------------------------------------------------------
local CH, GAP = 160, 12

local function cardArt(c, z)
    if not c.hasArt then return end
    local dz = 0.03 * z
    c.art:SetTexCoord(0.02 + dz, 0.98 - dz, 0.22 + dz * 0.75, 0.78 - dz * 0.75)
end
-- Stellung der Karte: z = 0 ruhig, 1 ueberfahren (Bild naeher, Name rueckt hoch und macht der Beute Platz)
local function cardPose(c, z)
    c.hz = z
    cardArt(c, z)
    c.hov:SetAlpha(z)
    c.glow:SetAlpha(0.4 * z)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", c.bx or 0, -(c.by or 0) + 2 * z)
    local lift = (c.nLoot or 0) > 0 and 32 * z or 0
    c.name:SetPoint("BOTTOMLEFT", 12, 30 + lift)
    c.meta:SetPoint("BOTTOMLEFT", 12, 12 + lift)
    c.loot:SetAlpha(z)
end
local function cardHover(c, on)
    local to = on and 1 or 0
    local from = c.hz or 0
    local apply = function(z) cardPose(c, z) end
    if animOn() then
        K.Tween(c, 0.16, function(q) apply(from + (to - from) * q) end, function() apply(to) end)
    else
        apply(to)
    end
end
local function pill(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.72)
    f.edge = f:CreateTexture(nil, "BORDER")
    f.edge:SetPoint("TOPLEFT") f.edge:SetPoint("BOTTOMLEFT")
    f.edge:SetWidth(2)
    f.edge:SetColorTexture(color[1], color[2], color[3], 1)
    f.ico = f:CreateTexture(nil, "ARTWORK")
    f.ico:SetSize(12, 12)
    f.ico:SetPoint("LEFT", 6, 0)
    f.text = K.Text(f, 11, color)
    f.text:SetPoint("LEFT", f.ico, "RIGHT", 3, 0)
    function f:Set(icon, txt)
        self.ico:SetTexture(icon)
        self.text:SetText(txt)
        self:SetWidth(math.floor((self.text:GetStringWidth() or 20) + 30))
    end
    return f
end

-- die besten Teile fuer mich aus der Beute (erst beim Ueberfahren berechnet): Upgrades, ohne Upgrade-Vergleich passende Teile
local LOOTN = 4
local function cardLoot(c)
    local d = c.d
    if not d or c.lootFor == d.key then return end
    local rows, seen = {}, {}
    local need = upOn() and 1000 or 20
    if d.source ~= "blizzard" then
        local ok, bosses = pcall(D.Bosses, d)
        for bi, b in ipairs(ok and bosses or {}) do
            for _, it in ipairs(b.loot or {}) do
                local rk = it[1] and not seen[it[1]] and rankOf(it[1]) or 0
                if rk >= need then
                    seen[it[1]] = true
                    rows[#rows + 1] = { it = it, boss = bi, rk = rk, n = #rows }
                end
            end
        end
    end
    table.sort(rows, function(a, b) if a.rk ~= b.rk then return a.rk > b.rk end return a.n < b.n end)
    c.nLoot = math.min(LOOTN, #rows)
    for i, b in ipairs(c.loot.btn) do
        local r = rows[i]
        b:SetShown(r ~= nil)
        if r then
            local info = itemInfo(r.it)
            b.id, b.boss = info.id, r.boss
            b.icon:SetTexture(info.icon)
            local er, eg, eb = hexRGB(info.color)
            b.edge:SetColorTexture(er or 1, eg or 1, eb or 1, 1)
        end
    end
    c.loot:SetShown(c.nLoot > 0)
    -- erst merken, wenn der Client alle Teile kennt (sonst fehlen Upgrades beim ersten Ueberfahren)
    if not upOn() or dgUpCache[d.key] then c.lootFor = d.key end
end
local function cardEnter(c, quiet)
    K.SetBorderColor(c, C.accent)
    cardLoot(c)
    if (c.hz or 0) < 1 then cardHover(c, true) end
    local d, i = c.d, c.info
    if quiet or not d or not i then return end
    local tip = { d.name, "|cff888888" .. ((d.level ~= "" and (L["Stufe %s"]):format(d.level) or "") .. ((d.location or "") ~= "" and ("  ·  " .. d.location) or "")) .. "|r" }
    if i.ups > 0 then tip[#tip + 1] = "|cff66db9e" .. (L["%d Verbesserungen fuer dich in der Beute"]):format(i.ups) .. "|r" end
    if i.q > 0 then tip[#tip + 1] = "|cffffd24a" .. (L["%d Quests fuer diesen Dungeon in deinem Log"]):format(i.q) .. "|r" end
    if #i.on > 0 then
        local names = {}
        for k = 1, math.min(6, #i.on) do names[#names + 1] = ns.Radar.Colored(i.on[k].name) end
        tip[#tip + 1] = (L["Online im Stufenbereich: %s"]):format(table.concat(names, ", ") .. (#i.on > 6 and " ..." or ""))
    end
    if d.closed then tip[#tip + 1] = "|cffd9786b" .. L["noch geschlossen"] .. "|r" end
    tip[#tip + 1] = "|cff777777" .. L["Klick: Dungeon oeffnen"] .. "|r"
    K.ShowTip(c, tip)
end
local function cardLeave(c)
    K.SetBorderColor(c, C.line)
    cardHover(c, false)
    GameTooltip:Hide()
end

local function buildCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(240, CH)
    c.hz = 0
    c.bg = K.Fill(c, C.raised)
    c.tone = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.tone:SetAllPoints()
    c.art = c:CreateTexture(nil, "ARTWORK")
    c.art:SetAllPoints()
    c.bigIcon = K.Icon(c, 54, nil)
    c.bigIcon:SetPoint("CENTER", 0, 16)
    c.bigIcon:SetAlpha(0.8)
    c.hov = c:CreateTexture(nil, "ARTWORK", nil, 3)
    c.hov:SetAllPoints()
    grad(c.hov, "VERTICAL", C.accent, 0.22, 0.02)
    c.hov:SetAlpha(0)
    c.shade = c:CreateTexture(nil, "ARTWORK", nil, 2)
    c.shade:SetPoint("BOTTOMLEFT") c.shade:SetPoint("BOTTOMRIGHT")
    c.shade:SetHeight(96)
    gradient(c.shade, "VERTICAL", 0.94, 0)
    c.topShade = c:CreateTexture(nil, "ARTWORK", nil, 2)
    c.topShade:SetPoint("TOPLEFT") c.topShade:SetPoint("TOPRIGHT")
    c.topShade:SetHeight(42)
    gradient(c.topShade, "VERTICAL", 0, 0.55)
    c.glow = c:CreateTexture(nil, "OVERLAY")
    c.glow:SetTexture(EMBER)
    c.glow:SetBlendMode("ADD")
    c.glow:SetPoint("BOTTOMLEFT", -20, -30)
    c.glow:SetPoint("BOTTOMRIGHT", 20, -30)
    c.glow:SetHeight(120)
    c.glow:SetAlpha(0)
    K.Border(c, C.line)
    -- 0.6.306: Oasis-Bildrahmen (rote Linie, abgeschraegte Ecken) wie bei allen Boxen; die alte Randlinie weicht
    if K.BoxFrame and K.BoxFrame(c) then for _, x in ipairs(c.borders or {}) do x:Hide() end end
    c.band = c:CreateTexture(nil, "OVERLAY", nil, 2)
    c.band:SetPoint("TOPLEFT", 10, -3) c.band:SetPoint("TOPRIGHT", -10, -3)
    c.band:SetHeight(2)
    c.name = K.Title(c, 15, C.text)
    c.name:SetPoint("BOTTOMLEFT", 12, 30)
    c.name:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    c.meta = K.Text(c, 11, C.muted)
    c.meta:SetPoint("BOTTOMLEFT", 12, 12)
    c.meta:SetPoint("RIGHT", c, "RIGHT", -86, 0)
    c.lvlBg = c:CreateTexture(nil, "OVERLAY")
    c.lvlBg:SetColorTexture(0, 0, 0, 0.75)
    c.lvlBg:SetPoint("TOPRIGHT", -8, -10)
    c.lvlBg:SetSize(56, 20)
    c.lvlEdge = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.lvlEdge:SetPoint("BOTTOMLEFT", c.lvlBg, "BOTTOMLEFT")
    c.lvlEdge:SetPoint("BOTTOMRIGHT", c.lvlBg, "BOTTOMRIGHT")
    c.lvlEdge:SetHeight(2)
    c.lvl = K.Title(c, 12, C.text, "CENTER")
    K.CenterNum(c.lvl, c.lvlBg, "CENTER", 0, 0)
    c.upPill = pill(c, GREEN)
    c.upPill:SetPoint("TOPLEFT", 8, -10)
    c.qPill = pill(c, { 1, 0.82, 0.3 })
    c.dots = {}
    for i = 1, 4 do
        local t = c:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetTexture(CIRCLE)
        t:SetSize(11, 11)
        t:SetPoint("BOTTOMRIGHT", -12 - (i - 1) * 8, 14)
        c.dots[i] = t
    end
    c.onl = K.Text(c, 11, C.mint, "RIGHT")
    c.onl:SetPoint("BOTTOMRIGHT", -12, 28)
    -- Beute-Leiste: bis zu vier Teile, die mir etwas bringen; Klick springt zum Boss, der sie fallen laesst
    c.loot = CreateFrame("Frame", nil, c)
    c.loot:SetSize(LOOTN * 32, 28)
    c.loot:SetPoint("BOTTOMLEFT", 12, 10)
    c.loot:SetAlpha(0)
    c.loot:Hide()
    c.loot.btn = {}
    for i = 1, LOOTN do
        local b = CreateFrame("Button", nil, c.loot)
        b:SetSize(28, 28)
        b:SetPoint("LEFT", (i - 1) * 32, 0)
        b.edge = b:CreateTexture(nil, "BACKGROUND")
        b.edge:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.18)
        b:SetScript("OnEnter", function(self)
            cardEnter(c, true)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
            local m = markOf(self.id)
            if m.up then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff66db9e" .. (L["Besser als dein angelegtes Teil (+%d%%)"]):format(math.min(m.pct, 999)) .. "|r")
            end
            GameTooltip:AddLine("|cff777777" .. L["Klick: zum Boss mit diesem Teil"] .. "|r")
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if not c:IsMouseOver() then cardLeave(c) end
        end)
        b:SetScript("OnClick", function(self)
            if not c.d then return end
            GameTooltip:Hide()
            openDungeon(c.d.key, self.boss)
        end)
        c.loot.btn[i] = b
    end
    c:SetScript("OnEnter", function(self) cardEnter(self) end)
    -- auf ein Beute-Symbol gewechselt: Karte bleibt offen
    c:SetScript("OnLeave", function(self)
        if self:IsMouseOver() and self.loot:IsShown() then return end
        cardLeave(self)
    end)
    c:SetScript("OnClick", function(self)
        if not self.d then return end
        GameTooltip:Hide()
        openDungeon(self.d.key)
    end)
    return c
end

local function fillCard(c, d)
    c.d = d
    local t = tone(d)
    c.tone:SetColorTexture(t[1], t[2], t[3], 1)
    local art = artOf(d)
    c.art:SetTexture(art)
    c.art:SetShown(art ~= nil)
    c.hasArt = art ~= nil
    -- anderer Dungeon auf dieser Karte (Mausrad): Beute-Leiste neu, unter der Maus gleich wieder fuellen
    if c.lootFor ~= d.key then
        c.lootFor, c.nLoot = nil, 0
        c.loot:Hide()
        if c:IsMouseOver() and (c.hz or 0) > 0 then cardLoot(c) end
    end
    cardPose(c, c.hz or 0)
    c.bigIcon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_Book_09")
    c.bigIcon:SetShown(art == nil)
    c.glow:SetVertexColor(t[1] * 0.6 + 0.4, t[2] * 0.6 + 0.4, t[3] * 0.6 + 0.4)
    c.name:SetText(d.name)
    c.lvl:SetText(d.level ~= "" and d.level or "?")
    local lc = lvlColor(d)
    c.lvl:SetTextColor(lc[1], lc[2], lc[3])
    c.lvlEdge:SetColorTexture(lc[1], lc[2], lc[3], 1)
    c.band:SetColorTexture(lc[1], lc[2], lc[3], fits(d) and 1 or 0.55)
    local info = { ups = dungeonUps(d), on = d.closed and {} or othersInRange(d), q = 0 }
    if not d.closed then info.q = questCount(d) end
    c.info = info
    -- Kennzeichen sagen, was die Zahl bedeutet; nur auf schmalen Karten bleibt die blosse Zahl
    local wide = (c:GetWidth() or 240) >= 250
    -- 0.6.303: keine Symbol-Pillen und Punkte mehr - eine Klartext-Zeile: wer aus der Gilde passt, Quests, Upgrades
    c.upPill:Hide() c.qPill:Hide()
    for _, dot in ipairs(c.dots) do dot:Hide() end
    c.onl:SetText("")
    local parts = {}
    if #info.on > 0 then parts[#parts + 1] = "|cff66db9e" .. (#info.on == 1 and L["1 aus der Gilde passt"] or (L["%d aus der Gilde passen"]):format(#info.on)) .. "|r" end
    if info.q > 0 then parts[#parts + 1] = "|cffffd24a" .. (info.q == 1 and L["1 Quest"] or (L["%d Quests"]):format(info.q)) .. "|r" end
    if info.ups > 0 then parts[#parts + 1] = "|cff7fe0a0" .. (info.ups == 1 and L["1 Upgrade"] or (L["%d Upgrades"]):format(info.ups)) .. "|r" end
    c.meta:SetPoint("RIGHT", c, "RIGHT", -10, 0)
    if d.closed then c.meta:SetText("|cffd9786b" .. L["noch geschlossen"] .. "|r")
    elseif #parts > 0 then c.meta:SetText(table.concat(parts, "  |cff666666·|r  "))
    else c.meta:SetText("|cff888888" .. (d.location or "") .. "|r") end
    c:SetAlpha(d.closed and 0.6 or 1)
end

------------------------------------------------------------------------
-- Karte im Reiter "Karte": eigene Position und Gruppe (Weltkarten-Position -> Dungeonbild, kalibriert)
------------------------------------------------------------------------
local MC = {}
D.MapCal = MC
-- bekannte Standardwerte je Dungeon/Ebene (Schluessel "dbKey:Ebene"); noch keine gemessen
MC.DEFAULTS = {}
function MC.Key(d, floor) return (d.dbKey or d.key) .. ":" .. tostring(floor or 1) end
function MC.Get(key)
    local own = ns.db and ns.db.dmapCal and ns.db.dmapCal[key]
    return own or MC.DEFAULTS[key]
end
local function lsq(xs, ys)
    local n, sx, sy, sxx, sxy = #xs, 0, 0, 0, 0
    for i = 1, n do sx, sy, sxx, sxy = sx + xs[i], sy + ys[i], sxx + xs[i] * xs[i], sxy + xs[i] * ys[i] end
    local den = n * sxx - sx * sx
    if math.abs(den) < 1e-9 then return nil end
    local a = (n * sxy - sx * sy) / den
    return a, (sy - a * sx) / n
end
-- Abbildung je Achse per kleinster Quadrate; Fehler = mittlerer Abstand in Bildanteilen
function MC.Solve(samples)
    if not samples or #samples < 2 then return nil end
    local mx, my, px, py = {}, {}, {}, {}
    for i, s in ipairs(samples) do mx[i], my[i], px[i], py[i] = s[1], s[2], s[3], s[4] end
    local ax, bx = lsq(mx, px)
    local ay, by = lsq(my, py)
    if not ax or not ay then return nil end
    local err = 0
    for i = 1, #samples do
        local dx, dy = ax * mx[i] + bx - px[i], ay * my[i] + by - py[i]
        err = err + math.sqrt(dx * dx + dy * dy)
    end
    return { ax = ax, bx = bx, ay = ay, by = by, err = err / #samples, n = #samples }
end
local function mapPos(mapID, unit)
    if not (C_Map and C_Map.GetPlayerMapPosition and mapID) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
    if not ok or not pos then return nil end
    local ok2, x, y = pcall(pos.GetXY, pos)
    x, y = ns.safe(x), ns.safe(y)
    if not ok2 or not x or not y or (x == 0 and y == 0) then return nil end
    return x, y
end
function MC.Save(key, res, map, from)
    ns.db.dmapCal = ns.db.dmapCal or {}
    ns.db.dmapCal[key] = { map = map, ax = res.ax, bx = res.bx, ay = res.ay, by = res.by, err = res.err, n = res.n, from = from, t = time() }
end
function MC.Share(key)
    local c = ns.db and ns.db.dmapCal and ns.db.dmapCal[key]
    if not c or not ns.Comm or not (IsInGuild and IsInGuild()) then return false end
    ns.Comm.SendEx({ ch = "GUILD" }, "DMCAL", key, tostring(c.map), ("%.5f"):format(c.ax), ("%.5f"):format(c.bx), ("%.5f"):format(c.ay), ("%.5f"):format(c.by))
    return true
end
if ns.Comm and ns.Comm.On then
    -- Kalibrierung von Gildenmitgliedern: nur uebernehmen, wenn man selbst keine hat
    ns.Comm.On("DMCAL", function(sender, _, key, map, ax, bx, ay, by)
        if not ns.db or type(key) ~= "string" or ns.isMe(sender) then return end
        if #key > 60 or key:find("[|%c]") then return end
        ns.db.dmapCal = ns.db.dmapCal or {}
        local own = ns.db.dmapCal[key]
        if own and not own.from then return end
        -- Zahlen endlich und in sinnvollem Bereich (sonst Zeichenfehler), gespeicherte Menge begrenzt
        ax, bx, ay, by = SEC.Num(ax, -1e6, 1e6), SEC.Num(bx, -1e6, 1e6), SEC.Num(ay, -1e6, 1e6), SEC.Num(by, -1e6, 1e6)
        map = SEC.Num(map, 1, 1e7, true)
        if not (ax and bx and ay and by and map) then return end
        if not own then
            local n = 0
            for _ in pairs(ns.db.dmapCal) do n = n + 1 end
            if n >= 300 then return end
        end
        ns.db.dmapCal[key] = { map = map, ax = ax, bx = bx, ay = ay, by = by, from = sender, t = time() }
    end)
end

local function mcBuild(mt)
    if mt.pos then return mt.pos end
    local P = CreateFrame("Frame", nil, mt)
    P:SetPoint("TOPLEFT", mt.canvas, "TOPLEFT")
    P:SetPoint("BOTTOMRIGHT", mt.canvas, "BOTTOMRIGHT")
    P:SetFrameLevel(mt.canvas:GetFrameLevel() + 25)
    P.dots = {}
    -- Statuszeile unten links mit Knoepfen
    local bar = CreateFrame("Frame", nil, mt)
    bar:SetFrameLevel(mt:GetFrameLevel() + 32)
    bar:SetPoint("BOTTOMLEFT", 6, 6)
    bar:SetSize(520, 24)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.75)
    bar.text = K.Text(bar, 11, C.muted)
    bar.text:SetPoint("LEFT", 8, 0)
    bar.cal = K.Button(bar, L["Kalibrieren"], 96, 20, "ghost", function()
        if S.cal then S.cal = nil else S.cal = { key = mt.calKey, samples = {} } end
        MC.Draw(mt)
    end)
    bar.save = K.Button(bar, L["Speichern"], 80, 20, "primary", function()
        local c = S.cal
        local res = c and MC.Solve(c.samples)
        if res then
            MC.Save(c.key, res, c.map)
            S.cal = nil
            ns.print(L["Kalibrierung gespeichert."])
        end
        MC.Draw(mt)
    end)
    bar.share = K.Button(bar, L["Mit Gilde teilen"], 110, 20, "ghost", function()
        if MC.Share(mt.calKey) then ns.print(L["Kalibrierung an die Gilde geschickt."]) end
    end)
    bar.share:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Mit Gilde teilen"], L["Schickt nur die Umrechnungswerte. Wer noch keine eigene Kalibrierung hat, uebernimmt sie."] }) end)
    bar.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.bar = bar
    -- Klick auf die Karte im Kalibriermodus: hier stehe ich
    mt.canvas:EnableMouse(true)
    mt.canvas:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and ns.InstancePos and IsInInstance and IsInInstance() then ns.InstancePos.ClickSet(self, mt.calKey) return end
        local c = S.cal
        if not c or btn ~= "LeftButton" then return end
        local r = self.lrect
        if not r then return end
        local map = C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player"))
        if c.map then map = c.map end
        local x, y = mapPos(map, "player")
        if not x then ns.print(L["Hier liefert das Spiel keine Kartenposition."]) return end
        local cx, cy = GetCursorPosition()
        local sc = self:GetEffectiveScale() or 1
        local px = (cx / sc - (self:GetLeft() or 0) - r[1]) / r[3]
        local py = ((self:GetTop() or 0) - cy / sc - r[2]) / r[4]
        if px < 0 or px > 1 or py < 0 or py > 1 then return end
        c.map = map
        c.samples[#c.samples + 1] = { x, y, px, py }
        MC.Draw(mt)
    end)
    local acc = 0
    P:SetScript("OnUpdate", function(self, el)
        acc = acc + (el or 0)
        if acc < 0.2 then return end
        acc = 0
        pcall(MC.Draw, mt)
    end)
    mt.pos = P
    return P
end

local function mcDot(P, n)
    local d = P.dots[n]
    if d then return d end
    d = CreateFrame("Frame", nil, P)
    d:SetSize(16, 16)
    d.ring = d:CreateTexture(nil, "ARTWORK")
    d.ring:SetTexture(CIRCLE)
    d.ring:SetAllPoints()
    d.ring:SetVertexColor(0, 0, 0, 1)
    d.c = d:CreateTexture(nil, "OVERLAY")
    d.c:SetTexture(CIRCLE)
    d.c:SetPoint("CENTER")
    d.c:SetSize(11, 11)
    d.arrow = d:CreateTexture(nil, "OVERLAY", nil, 2)
    d.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    d.arrow:SetPoint("CENTER")
    d.arrow:SetSize(26, 26)
    d:EnableMouse(true)
    d:SetScript("OnEnter", function(self) if self.name then K.ShowTip(self, { self.name }) end end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.dots[n] = d
    return d
end

function MC.Draw(mt)
    local P = mt.pos
    if not P then return end
    for _, d in ipairs(P.dots) do d:Hide() end
    local bar = P.bar
    local r = mt.canvas.lrect
    local key = mt.calKey
    local c = S.cal
    if c and c.key ~= key then S.cal = nil c = nil end
    bar.save:Hide()
    bar.share:Hide()
    bar.cal:SetLabel(c and L["Abbrechen"] or L["Kalibrieren"])
    local function layout()
        local x = math.floor((bar.text:GetStringWidth() or 100) + 16)
        for _, b in ipairs({ bar.cal, bar.save, bar.share }) do
            if b:IsShown() then
                b:ClearAllPoints()
                b:SetPoint("LEFT", x, 0)
                x = x + (b:GetWidth() or 80) + 6
            end
        end
        bar:SetWidth(x + 2)
    end
    local inInst = IsInInstance and IsInInstance()
    if ns.InstancePos then ns.InstancePos.HideOn(P) end
    if inInst and not c then
        local txt = ns.InstancePos and ns.InstancePos.DrawOn(mt.canvas, P, key, false)
        bar.text:SetText("|cffe8b44a" .. (txt or L["Positionen in Instanzen von WoW gesperrt"]) .. "|r")
        bar.cal:Hide()
        layout()
        return
    end
    bar.cal:Show()
    if c then
        local n = #c.samples
        local res = MC.Solve(c.samples)
        local t = (L["Kalibrieren: stell dich an eine markante Stelle und klick genau dort auf die Karte (%d Punkte)"]):format(n)
        if res then t = t .. "  ·  " .. (L["Abweichung ca. %d%%"]):format(math.floor(res.err * 100 + 0.5)) end
        bar.text:SetText(t)
        bar.save:SetShown(res ~= nil)
        layout()
        return
    end
    local cal = key and MC.Get(key)
    if not cal or not r then
        bar.text:SetText(L["Noch nicht kalibriert - Kalibrieren?"])
        layout()
        return
    end
    bar.share:SetShown(ns.db and ns.db.dmapCal and ns.db.dmapCal[key] ~= nil and not ns.db.dmapCal[key].from)
    local n, mates = 0, 0
    local function place(x, y, cr, cg, cb, name, me)
        local px, py = cal.ax * x + cal.bx, cal.ay * y + cal.by
        if px < -0.02 or px > 1.02 or py < -0.02 or py > 1.02 then return false end
        n = n + 1
        local d = mcDot(P, n)
        d.name = name
        local face = me and GetPlayerFacing and ns.safe(GetPlayerFacing())
        d.arrow:SetShown(face ~= nil)
        if face then pcall(d.arrow.SetRotation, d.arrow, face) end
        d.ring:SetShown(face == nil)
        d.c:SetShown(face == nil)
        d.c:SetVertexColor(cr, cg, cb)
        d:SetSize(me and 20 or 16, me and 20 or 16)
        d:ClearAllPoints()
        d:SetPoint("CENTER", mt.canvas, "TOPLEFT", r[1] + px * r[3], -(r[2] + py * r[4]))
        d:Show()
        return true
    end
    local meShown = false
    local x, y = mapPos(cal.map, "player")
    if x then
        local _, cls = UnitClass("player")
        local cr, cg, cb = ns.classColor(cls)
        meShown = place(x, y, cr or 1, cg or 1, cb or 1, L["Du"], true)
    end
    local raid = IsInRaid and IsInRaid()
    local num = raid and 40 or 4
    for i = 1, num do
        local u = (raid and "raid" or "party") .. i
        if UnitExists and UnitExists(u) and not UnitIsUnit(u, "player") then
            local ux, uy = mapPos(cal.map, u)
            local full = GetUnitName and GetUnitName(u, true)
            if not ux and full and ns.Map and ns.Map.pos then
                local p = ns.Map.pos[full] or ns.Map.pos[ns.full and ns.full(full) or full]
                if p and p.mapID == cal.map then ux, uy = p.x, p.y end
            end
            if ux then
                local _, cls = UnitClass(u)
                local cr, cg, cb = ns.classColor(cls)
                if place(ux, uy, cr or 1, cg or 1, cb or 1, ns.displayName(full or u)) then mates = mates + 1 end
            end
        end
    end
    local t = meShown and ((L["Du und %d aus der Gruppe auf der Karte"]):format(mates)) or L["Du bist gerade nicht auf dieser Karte"]
    if cal.from then t = t .. "  |cff777777(" .. (L["Kalibrierung von %s"]):format(ns.displayName(cal.from)) .. ")|r" end
    bar.text:SetText(t)
    layout()
end
-- vom Reiter "Karte" aus aufgerufen (nach dem Zeichnen der Karte)
function MC.Update(mt, d, floor, lok)
    local P = mcBuild(mt)
    mt.calKey = MC.Key(d, floor)
    P:SetShown(lok and true or false)
    P.bar:SetShown(lok and true or false)
    if mt.creditFrame then
        mt.creditFrame:ClearAllPoints()
        mt.creditFrame:SetPoint("TOPRIGHT", -6, -6)
    end
    if lok then MC.Draw(mt) end
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local ARMOR_KIND = { [1] = "Stoff", [2] = "Leder", [3] = "Kette", [4] = "Platte" }
local function kindOf(id)
    local ok, _, _, _, _, _, classID, sub = pcall(C_Item.GetItemInfoInstant, id)
    if not ok then return "Sonstiges" end
    if classID == 4 and ARMOR_KIND[sub] then return ARMOR_KIND[sub] end
    if classID == 4 and sub == 6 then return "Schild" end
    if classID == 2 then return "Waffe" end
    return "Sonstiges"
end
local function menuButton(parent, w, getLabel, getItems, title)
    local b = K.Button(parent, "", w, 24, "ghost")
    b.isDropdown = true
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    b.label:SetJustifyH("LEFT")
    b.arrow = K.Text(b, 10, C.dim, "RIGHT")
    b.arrow:SetPoint("RIGHT", -8, 0)
    b.arrow:SetText("v")
    function b:Update() self:SetLabel(getLabel()) end
    b:SetScript("OnClick", function(self) K.ShowMenu(self, getItems(), title, math.max(180, self:GetWidth())) end)
    return b
end
local function chip(parent, text, onClick)
    local b = K.Button(parent, text, 110, 24, "ghost", onClick)
    b:SetWidth(math.max(90, (b.label:GetStringWidth() or 60) + 30))
    function b:SetOn(on)
        self.on = on
        K.SetBorderColor(self, on and GREEN or C.line)
        self.label:SetTextColor(on and GREEN[1] or C.text[1], on and GREEN[2] or C.text[2], on and GREEN[3] or C.text[3])
    end
    return b
end

------------------------------------------------------------------------
-- Reiter Gilde / Quests: Personen-Kreise, runde Item-Symbole, Spalten-Karten
------------------------------------------------------------------------
local QUAL_RGB = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }
local function personMenu(owner, name)
    if not name then return end
    local me = ns.isMe(name)
    K.ShowMenu(owner, {
        { text = L["Fluestern"], disabled = me, fn = function() ns.Whisper(name) end },
        { text = L["In Gruppe einladen"], disabled = me, fn = function() ns.InviteName(name) end },
        { text = L["Profil ansehen"], disabled = not (ns.Profile and ns.Profile.Show), fn = function() ns.Profile.Show(name) end },
    }, ns.displayName(name), 180)
end
local function classOf(name)
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
    return (m and m.class) or (ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(name))
end
-- runder Klassenkreis (Klassensymbol, sonst Anfangsbuchstabe)
local function classDisc(parent, size)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(size, size)
    h.ring = h:CreateTexture(nil, "BORDER")
    h.ring:SetTexture(CIRCLE)
    h.ring:SetSize(size + 4, size + 4)
    h.ring:SetPoint("CENTER")
    h.disc = h:CreateTexture(nil, "ARTWORK")
    h.disc:SetTexture(CIRCLE)
    h.disc:SetAllPoints()
    h.icon = h:CreateTexture(nil, "OVERLAY")
    h.icon:SetPoint("TOPLEFT", 3, -3)
    h.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    h.letter = K.Title(h, math.floor(size * 0.45), C.text, "CENTER")
    h.letter:SetPoint("CENTER")
    function h:Set(cls, name)
        local r, g, b = ns.classColor(cls)
        self.ring:SetVertexColor(r, g, b, 0.95)
        self.disc:SetVertexColor(r * 0.28, g * 0.28, b * 0.28, 1)
        local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
        if tc then
            self.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            self.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            self.icon:Show()
            self.letter:SetText("")
        else
            self.icon:Hide()
            self.letter:SetText((ns.displayName(name or "?") or "?"):sub(1, 1):upper())
            self.letter:SetTextColor(r, g, b)
        end
    end
    return h
end
-- rundes Item-Symbol im Qualitaetsring
local function roundIcon(parent, size)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(size, size)
    h.ring = h:CreateTexture(nil, "BORDER")
    h.ring:SetTexture(CIRCLE)
    h.ring:SetSize(size + 4, size + 4)
    h.ring:SetPoint("CENTER")
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetAllPoints()
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if h.CreateMaskTexture and h.icon.AddMaskTexture then
        pcall(function()
            local m = h:CreateMaskTexture()
            m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(h.icon)
            h.icon:AddMaskTexture(m)
        end)
    end
    return h
end
-- Spalte als Karte: Akzentlinie, Titel, Zaehler, Liste, Leerzustand
local function colCard(parent, title, color, rowH, createRow, updateRow)
    local f = K.Panel(parent, C.panel)
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("TOPLEFT", 1, -1)
    f.accent:SetPoint("TOPRIGHT", -1, -1)
    f.accent:SetHeight(2)
    grad(f.accent, "HORIZONTAL", color, 0.9, 0.1)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetTexture(CIRCLE)
    f.dot:SetSize(8, 8)
    f.dot:SetPoint("TOPLEFT", 12, -15)
    f.dot:SetVertexColor(color[1], color[2], color[3])
    f.title = K.Title(f, 12, C.text)
    f.title:SetPoint("TOPLEFT", 26, -12)
    f.title:SetText(title)
    f.count = K.Text(f, 11, C.dim, "RIGHT")
    f.count:SetPoint("TOPRIGHT", -12, -13)
    f.list = K.List(f, rowH, createRow, updateRow)
    f.list:SetPoint("TOPLEFT", 6, -36)
    f.list:SetPoint("BOTTOMRIGHT", -4, 6)
    f.list.empty:SetText("")
    f.empty = emptyState(f)
    f.empty:SetPoint("TOP", f, "TOP", 0, -62)
    f.empty.halo:SetVertexColor(color[1], color[2], color[3])
    f.empty.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
    f.empty:Hide()
    f:SetScript("OnSizeChanged", function(self, w)
        w = math.max(120, (w or self:GetWidth() or 240) - 16)
        self.empty:SetWidth(w)
        self.empty.text:SetWidth(w - 8)
    end)
    return f
end

-- Gilden-Reiter: Daten (mit Demo-Ergaenzung, nichts davon wird gespeichert)
------------------------------------------------------------------------
-- 0.6.304: Mitkommen-Liste je Dungeon (geteilt, Sammlung "dgjoin", 4 Stunden gueltig, nur der Autor aendert)
-- Wer Lust auf einen Dungeon hat, traegt sich mit Rolle ein; daraus bildet jemand per Klick die Gruppe.
------------------------------------------------------------------------
local JOIN_TTL = 4 * 3600
local function joinId(key, who) return "dj-" .. tostring(key) .. "-" .. ns.short(who or ns.me()) end
function D.JoinList(key)
    local now = ns.now()
    local out = ns.Store.List("dgjoin", function(r) return r.dk == key and not r.del and now - (tonumber(r.ts) or 0) < JOIN_TTL end)
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end
function D.MyJoin(key)
    local r = ns.Store.Get("dgjoin", joinId(key))
    if r and not r.del and ns.now() - (tonumber(r.ts) or 0) < JOIN_TTL then return r end
end
function D.Join(key, role)
    local _, cls = UnitClass("player")
    ns.Store.Put("dgjoin", { id = joinId(key), dk = key, who = ns.me(), role = role, ts = ns.now(),
        class = ns.safe(cls), lvl = ns.safe(UnitLevel("player")) })
end
function D.Leave(key)
    if ns.Store.Get("dgjoin", joinId(key)) then ns.Store.Delete("dgjoin", joinId(key)) end
end
local function joinOnline(name)
    local m = ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, name)
    return (m and m.online) or ns.isMe(name)
end
-- Gruppe bilden: online Eingetragene einladen (hoechstens 4), erst je ein Tank und Heiler, dann Schaden
function D.FormGroup(key)
    local list, pick, have = D.JoinList(key), {}, { tank = 0, heal = 0, dps = 0 }
    local me = D.MyJoin(key)
    if me then have[me.role or "dps"] = 1 end
    local function take(role, max)
        for _, r in ipairs(list) do
            if #pick >= 4 then return end
            if not ns.isMe(r.who) and joinOnline(r.who) and (r.role or "dps") == role and not r.picked and have[role] < max then
                r.picked = true have[role] = have[role] + 1 pick[#pick + 1] = r
            end
        end
    end
    take("tank", 1) take("heal", 1) take("dps", 3)
    for _, r in ipairs(list) do r.picked = nil end
    for _, r in ipairs(pick) do ns.InviteName(r.who) end
    return #pick
end

local function guildData(d)
    local wanted = D.WantedLoot(d)
    local got = D.GuildLoot(d)
    local range = {}
    for _, m in ipairs(D.InRange(d)) do if not ns.isMe(m.name) then range[#range + 1] = m end end
    if ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() then
        local pool = {}
        local okB, bosses = pcall(D.Bosses, d)
        for _, b in ipairs(okB and bosses or {}) do
            for _, it in ipairs(b.loot or {}) do pool[#pool + 1] = { it = it, boss = b.name } end
        end
        local names = {}
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do if not ns.isMe(m.name) then names[#names + 1] = m.name end end
        if #wanted == 0 and #pool > 0 and #names > 0 then
            for i = 1, math.min(3, #pool) do
                local e = pool[(i * 3) % #pool + 1]
                wanted[#wanted + 1] = { itemID = e.it[1], name = e.it[2], qty = 1, who = names[(i * 2) % #names + 1], demo = true }
            end
        end
        if #got < 3 and #pool > 0 and #names > 0 then
            for i = 1, 4 - #got do
                local e = pool[(i * 5) % #pool + 1]
                local info = itemInfo(e.it)
                got[#got + 1] = { item = info.link or ("|c" .. info.color .. "|Hitem:" .. e.it[1] .. "|h[" .. info.name .. "]|h|r"),
                    itemID = e.it[1], who = names[(i * 3) % #names + 1], ts = ns.now() - i * 26000, demo = true }
            end
        end
    end
    return wanted, got, range
end

ns.RegisterPage({
    key = "dungeons", title = "Dungeons", order = 4.5,
    sub = "Welche Dungeons passen gerade, wer hat die Quests dabei, was sucht die Gilde daraus",
    build = function(p)
        -- ===== Startseite =====
        local home = CreateFrame("Frame", nil, p)
        home:SetAllPoints()
        p.home = home
        -- eine Bedienzeile: zwei Reiter, Suche, ein Filter-Menue (Sortierung, Upgrades, geoeffnet, Gebiet)
        home.seg = slideTabs(home, { { key = "mine", text = L["Fuer mich"] }, { key = "all", text = L["Alle"] } },
            function(k) S.filter = k S.homeOffset = 0 S.stagger = true ns.RefreshPage("dungeons") end)
        home.seg:SetPoint("TOPLEFT", 0, 0)
        home.count = K.Text(home, 11, C.dim, "RIGHT")
        home.count:SetPoint("TOPRIGHT", 0, -10)
        home.search = K.Input(home, 190, L["Dungeon suchen ..."], function(t)
            S.homeSearch = (t or ""):lower()
            S.homeOffset = 0
            ns.RefreshPage("dungeons")
        end)
        home.search:SetPoint("LEFT", home.seg, "RIGHT", 18, 1)
        local function go() S.homeOffset = 0 S.stagger = true ns.RefreshPage("dungeons") end
        local function zoneMenu()
            local zs, seen = {}, {}
            for _, d in ipairs(D.List()) do
                local z = d.location or ""
                if z ~= "" and not seen[z] then seen[z] = true zs[#zs + 1] = z end
            end
            table.sort(zs)
            local items = { { text = L["Alle Gebiete"], checked = S.homeZone == nil, fn = function() S.homeZone = nil go() end } }
            for _, z in ipairs(zs) do
                items[#items + 1] = { text = z, checked = S.homeZone == z, fn = function() S.homeZone = z go() end }
            end
            K.ShowMenu(home.filter, items, L["Gebiet"], 200)
        end
        home.filter = menuButton(home, 120, function()
            local n = (S.homeZone and 1 or 0) + (S.upOnly and 1 or 0) + (S.openOnly and 1 or 0)
            return L["Filter"] .. (n > 0 and ("  " .. K.hex(C.accent) .. n .. "|r") or "")
        end, function()
            local items = { { text = L["Sortieren"], header = true } }
            for _, so in ipairs(SORTS) do
                items[#items + 1] = { text = L[so[2]], checked = S.sort == so[1], fn = function() S.sort = so[1] go() end }
            end
            items[#items + 1] = { text = L["Anzeigen"], header = true }
            if upOn() then
                items[#items + 1] = { text = L["Nur mit Upgrades"], checked = S.upOnly, fn = function() S.upOnly = not S.upOnly go() end }
            end
            if S.filter == "all" then
                items[#items + 1] = { text = L["Nur geoeffnete"], checked = S.openOnly, fn = function() S.openOnly = not S.openOnly go() end }
            end
            items[#items + 1] = { text = L["Gebiet"] .. ": " .. (S.homeZone or L["Alle"]) .. " ...", fn = zoneMenu }
            if S.homeZone or S.upOnly or S.openOnly or S.sort ~= "level" then
                items[#items + 1] = { text = L["Filter zuruecksetzen"], fn = function() S.homeZone, S.upOnly, S.openOnly, S.sort = nil, false, false, "level" go() end }
            end
            return items
        end)
        home.filter:SetPoint("LEFT", home.search, "RIGHT", 8, 0)

        -- 0.6.303: "Jetzt mit der Gilde" - Dungeons, fuer die gerade mind. 2 aus der Gilde im Stufenbereich online sind;
        -- Klick oeffnet den Dungeon im Reiter Gilde & Gruppe (Gruppe suchen, alle einladen, wer hat die Quests)
        home.gbar = CreateFrame("Frame", nil, home)
        home.gbar:SetPoint("TOPLEFT", 0, -40)
        home.gbar:SetPoint("RIGHT", home, "RIGHT", 0, 0)
        home.gbar:SetHeight(42)
        -- 0.6.306: als Glasbox mit Oasis-Rahmen (wie die Karten)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(home.gbar, nil, nil, 12) end
        home.gbar.lbl = K.Text(home.gbar, 11, C.muted)
        home.gbar.lbl:SetPoint("LEFT", 14, 0)
        home.gbar.lbl:SetText(L["Jetzt mit der Gilde:"])
        home.gbar.chips = {}
        for i = 1, 4 do
            local b = CreateFrame("Button", nil, home.gbar)
            b:SetHeight(26)
            b.t = K.Text(b, 11, C.text)
            b.t:SetPoint("CENTER", 0, 0)
            b.noBoxFrame = true
            if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(b, { 0.40, 0.86, 0.62, 0.08 }, { 0.40, 0.86, 0.62, 0.35 }, 13) end
            b:SetScript("OnClick", function(self) if self.key then openDungeon(self.key) end end)
            b:SetScript("OnEnter", function(self)
                if not self.names then return end
                K.ShowTip(self, { self.title or "", self.names, "|cff888888" .. L["Klick: Gilde & Gruppe - Gruppe suchen, alle einladen"] .. "|r" })
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            home.gbar.chips[i] = b
        end
        home.gbar.none = K.Text(home.gbar, 11, C.dim)
        home.gbar.none:SetText(L["gerade niemand passend online"])
        function home.gbar:Update()
            local cand = {}
            for _, d in ipairs(D.List()) do
                if not d.closed then
                    local on = othersInRange(d)
                    if #on >= 2 then cand[#cand + 1] = { d = d, on = on } end
                end
            end
            table.sort(cand, function(a, b) return #a.on > #b.on end)
            local prev
            for i, b in ipairs(self.chips) do
                local c = cand[i]
                if c then
                    b.key, b.title = c.d.key, c.d.name
                    local nm = {}
                    for k = 1, math.min(8, #c.on) do nm[k] = ns.colorName and ns.colorName(c.on[k].name, c.on[k].class) or c.on[k].name end
                    b.names = table.concat(nm, ", ")
                    b.t:SetText(c.d.name .. "  |cff66db9e" .. #c.on .. "|r")
                    b:SetWidth((b.t:GetStringWidth() or 80) + 24)
                    b:ClearAllPoints()
                    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", self.lbl, "RIGHT", 10, 0) end
                    b:Show()
                    prev = b
                else
                    b.key, b.names = nil, nil
                    b:Hide()
                end
            end
            self.none:ClearAllPoints()
            self.none:SetPoint("LEFT", self.lbl, "RIGHT", 10, 0)
            self.none:SetShown(#cand == 0)
        end
        home.grid = CreateFrame("Frame", nil, home)
        home.grid:SetPoint("TOPLEFT", 0, -92)
        home.grid:SetPoint("BOTTOMRIGHT")
        home.grid:SetClipsChildren(true)
        home.grid:EnableMouseWheel(true)
        home.grid:SetScript("OnMouseWheel", function(_, delta)
            S.homeOffset = math.max(0, S.homeOffset - delta)
            ns.RefreshPage("dungeons")
        end)
        home.cards = {}
        for i = 1, 15 do home.cards[i] = buildCard(home.grid) end
        -- Raster je nach Breite: 3 / 2 / 1 Spalten
        function home:Layout()
            local W, H = self.grid:GetWidth() or 0, self.grid:GetHeight() or 0
            if W < 50 then W, H = 750, 380 end
            local cols = W >= 690 and 3 or (W >= 430 and 2 or 1)
            local cw = math.floor((W - GAP * (cols - 1)) / cols)
            local rows = math.max(1, math.floor((H + GAP) / (CH + GAP)))
            if rows * cols > #self.cards then rows = math.floor(#self.cards / cols) end
            self.cols, self.rowsVis = cols, rows
            for i, c in ipairs(self.cards) do
                local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
                c:SetSize(cw, CH)
                c.bx, c.by = col * (cw + GAP), row * (CH + GAP)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", c.bx, -c.by + 2 * (c.hz or 0))
                c.slot = row < rows and i or nil
            end
            -- schmal: Suche kuerzer, Zaehler weg
            local hw = self:GetWidth() or 750
            if hw < 50 then hw = 750 end
            self.search:SetWidth(hw < 620 and 130 or 190)
            self.count:SetShown(hw >= 720)
        end
        home.grid:SetScript("OnSizeChanged", function() home:Layout() if home:IsVisible() then ns.RefreshPage("dungeons") end end)
        home.empty = emptyState(home)
        home.empty:SetPoint("TOP", home.grid, "TOP", 0, -40)

        -- ===== Dungeon-Seite =====
        local dv = CreateFrame("Frame", nil, p)
        dv:SetAllPoints()
        p.dv = dv
        local banner = CreateFrame("Frame", nil, dv)
        banner:SetPoint("TOPLEFT")
        banner:SetPoint("TOPRIGHT")
        banner:SetHeight(124)
        banner:SetClipsChildren(true)
        dv.banner = banner
        dv.tone = banner:CreateTexture(nil, "BACKGROUND")
        dv.tone:SetAllPoints()
        dv.art = banner:CreateTexture(nil, "ARTWORK")
        dv.art:SetAllPoints()
        dv.art:SetTexCoord(0, 1, 0.30, 0.64)
        local shade = banner:CreateTexture(nil, "ARTWORK", nil, 2)
        shade:SetAllPoints()
        gradient(shade, "HORIZONTAL", 0.92, 0.2)
        local shade2 = banner:CreateTexture(nil, "ARTWORK", nil, 3)
        shade2:SetPoint("BOTTOMLEFT") shade2:SetPoint("BOTTOMRIGHT")
        shade2:SetHeight(60)
        gradient(shade2, "VERTICAL", 0.7, 0)
        dv.bannerLine = banner:CreateTexture(nil, "OVERLAY")
        dv.bannerLine:SetPoint("BOTTOMLEFT") dv.bannerLine:SetPoint("BOTTOMRIGHT")
        dv.bannerLine:SetHeight(2)
        K.Border(banner, C.line)
        dv.back = K.Button(banner, "‹  " .. L["Alle Dungeons"], 124, 22, "ghost", function()
            S.view = "home"
            S.fadeIn = "home"
            ns.RefreshPage("dungeons")
        end)
        dv.back:SetPoint("TOPLEFT", 10, -10)
        dv.title = K.Title(banner, 21, C.text)
        dv.title:SetPoint("BOTTOMLEFT", 16, 40)
        dv.meta = K.Text(banner, 12, C.muted)
        dv.meta:SetPoint("BOTTOMLEFT", 16, 18)
        -- Kennzahlen oben rechts
        dv.kpis = {}
        local KP = { { "bosses", "Bosse", C.accent }, { "ups", "Upgrades", GREEN }, { "quests", "Quests", { 1, 0.82, 0.3 } }, { "guild", "Gilde dabei", C.mint } }
        for i, kd in ipairs(KP) do
            local k = CreateFrame("Button", nil, banner)
            k:SetSize(80, 38)
            k:SetPoint("TOPRIGHT", -12 - (4 - i) * 86, -10)
            k.bg = k:CreateTexture(nil, "BACKGROUND")
            k.bg:SetAllPoints()
            k.bg:SetColorTexture(0, 0, 0, 0.55)
            k.top = k:CreateTexture(nil, "BORDER")
            k.top:SetPoint("TOPLEFT") k.top:SetPoint("TOPRIGHT")
            k.top:SetHeight(2)
            k.top:SetColorTexture(kd[3][1], kd[3][2], kd[3][3], 0.9)
            k.value = K.Title(k, 15, C.text)
            k.value:SetPoint("TOPLEFT", 8, -5)
            k.label = K.Text(k, 9, C.muted)
            k.label:SetPoint("BOTTOMLEFT", 8, 5)
            k.label:SetText(K.Upper and K.Upper(L[kd[2]]) or L[kd[2]])
            k.key = kd[1]
            k:SetScript("OnClick", function(self)
                local to = (self.key == "ups" and "loot") or (self.key == "quests" and "quests") or (self.key == "guild" and "guild") or "bosses"
                if self.key == "ups" then S.lootUp = true end
                S.tab = to
                ns.RefreshPage("dungeons")
            end)
            k:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            k:SetScript("OnLeave", function() GameTooltip:Hide() end)
            dv.kpis[kd[1]] = k
        end
        dv.lfg = K.Button(banner, L["Gruppe suchen"], 120, 24, "primary", function()
            local d = D.Get(S.dungeon)
            if d and ns.Groups then
                ns.Groups.Start(d.name, nil, true)
                ns.ShowPage("groups")
            end
        end)
        dv.lfg:SetPoint("BOTTOMRIGHT", -12, 12)
        dv.event = K.Button(banner, L["Als Termin planen"], 130, 24, "ghost", function()
            local d = D.Get(S.dungeon)
            if d and ns.Raid then
                ns.Raid.prefill = { title = d.name, inst = d.name .. (d.level ~= "" and (" (" .. d.level .. ")") or "") }
                ns.ShowPage("raid")
                ns.Raid.SetTab("events")
            end
        end)
        dv.event:SetPoint("RIGHT", dv.lfg, "LEFT", -6, 0)
        dv.journal = K.Button(banner, L["Dungeon-Journal"], 120, 24, "ghost", function()
            -- FojjiCore geladen: dessen Journal beim gewaehlten Boss oeffnen (Karten, Routen, Drop-Chancen liegen dort)
            if ns.Fojji and ns.Fojji.Dungeon(S.dungeon) then
                local d = D.Get(S.dungeon)
                local ok, bosses = pcall(D.Bosses, d)
                local b = ok and bosses and bosses[S.boss]
                local nm = b and not b.trash and not b.object and (b.nameEN or b.name) or nil
                if ns.Fojji.Open(S.dungeon, nm, S.tab == "map" and "map" or "overview") then return end
            end
            D.Open(S.dungeon)
        end)
        dv.journal:SetScript("OnEnter", function(self)
            if ns.Fojji and ns.Fojji.Dungeon(S.dungeon) then
                K.ShowTip(self, { "FojjiCore", L["Oeffnet diesen Dungeon im Journal von FojjiCore: Karten, Routen, Drop-Chancen."] })
            end
        end)
        dv.journal:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dv.journal:SetPoint("RIGHT", dv.event, "LEFT", -6, 0)
        banner:SetScript("OnSizeChanged", function(self, w)
            w = w or self:GetWidth() or 750
            dv.title:SetWidth(math.max(160, w - 420))
            dv.meta:SetWidth(math.max(160, w - 420))
            -- schmal: Kennzahlen kleiner
            local kw = w < 700 and 70 or 80
            for i, kd in ipairs(KP) do
                local k = dv.kpis[kd[1]]
                k:SetWidth(kw)
                k:ClearAllPoints()
                k:SetPoint("TOPRIGHT", -12 - (4 - i) * (kw + 6), -10)
            end
        end)

        -- drei Reiter statt fuenf; die Ansicht innerhalb eines Reiters schaltet der kleine Schalter rechts
        -- 0.6.303: Gemeinschaft zuerst - "Gilde & Gruppe" ist der erste Reiter und oeffnet sich standardmaessig
        dv.seg = slideTabs(dv, { { key = "guild", text = L["Gilde & Gruppe"] }, { key = "g1", text = L["Bosse & Beute"] },
            { key = "g2", text = L["Quests"] }, { key = "map", text = L["Karte"] } }, function(k)
            S.tab = (k == "guild" or k == "map") and k or S.sub[k]
            S.tabFade = true
            ns.RefreshPage("dungeons")
        end)
        dv.seg:SetPoint("TOPLEFT", 0, -132)
        dv.subs = {}
        for g, items in pairs({
            g1 = { { key = "bosses", text = L["Nach Boss"] }, { key = "loot", text = L["Gesamte Beute"] } },
        }) do
            local sw = K.Segments(dv, items, function(k)
                S.tab, S.sub[g] = k, k
                S.tabFade = true
                ns.RefreshPage("dungeons")
            end, nil, { size = 12, pad = 18 })
            sw:SetPoint("TOPRIGHT", 0, -136)
            dv.subs[g] = sw
        end

        local body = CreateFrame("Frame", nil, dv)
        body:SetPoint("TOPLEFT", 0, -170)
        body:SetPoint("BOTTOMRIGHT")
        dv.body = body

        -- Reiter Bosse: Bossliste links, Buehne mit Modell in der Mitte, Beute rechts
        local bt = CreateFrame("Frame", nil, body)
        bt:SetAllPoints()
        dv.bossTab = bt
        bt.list = K.List(bt, 46, function(l)
            local r = K.Row(l)
            r.card = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.card:SetPoint("TOPLEFT", 0, -1) r.card:SetPoint("BOTTOMRIGHT", 0, 1)
            r.card:SetColorTexture(1, 1, 1, 0.025)
            r.disc = r:CreateTexture(nil, "ARTWORK")
            r.disc:SetTexture(CIRCLE)
            r.disc:SetSize(26, 26)
            r.disc:SetPoint("LEFT", 8, 0)
            r.ring = r:CreateTexture(nil, "BORDER")
            r.ring:SetTexture(CIRCLE)
            r.ring:SetSize(28, 28)
            r.ring:SetPoint("CENTER", r.disc)
            r.skull = r:CreateTexture(nil, "OVERLAY")
            r.skull:SetSize(14, 14)
            r.skull:SetPoint("CENTER", r.disc)
            r.num = K.Text(r, 9, C.dim, "CENTER")
            r.num:SetPoint("BOTTOM", r.disc, "BOTTOM", 0, -3)
            r.up = K.Text(r, 11, GREEN, "RIGHT")
            r.up:SetPoint("RIGHT", -8, 0)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 42, -5)
            r.cols.name:SetPoint("RIGHT", r.up, "LEFT", -4, 0)
            r.cols.sub = K.Text(r, 11, C.muted)
            r.cols.sub:SetPoint("BOTTOMLEFT", 42, 5)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r:SetScript("OnClick", function(self) D.PickBoss(self.index) end)
            return r
        end, function(r, b, i)
            local t = bt.tone or C.accent
            r.disc:SetVertexColor(t[1] * 0.35, t[2] * 0.35, t[3] * 0.35)
            local selOn = S.boss == i
            r.ring:SetVertexColor(selOn and C.accent[1] or 0.2, selOn and C.accent[2] or 0.2, selOn and C.accent[3] or 0.22)
            if b.trash then
                r.skull:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
                r.skull:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.skull:SetVertexColor(1, 1, 1)
            elseif b.object then
                r.skull:SetTexture("Interface\\Icons\\INV_Box_01")
                r.skull:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.skull:SetVertexColor(1, 1, 1)
            else
                r.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                r.skull:SetTexCoord(0, 1, 0, 1)
                if b.rare then r.skull:SetVertexColor(1, 0.82, 0.3) else r.skull:SetVertexColor(1, 1, 1) end
            end
            r.num:SetText((b.trash or b.object) and "" or tostring(i))
            r.cols.name:SetText(b.trash and L["Trash-Gegner"] or b.name)
            local sub = {}
            if b.level then sub[#sub + 1] = (L["Stufe %s"]):format(b.level) end
            if b.rare then sub[#sub + 1] = "|cffffd24a" .. L["selten"] .. "|r" end
            sub[#sub + 1] = (L["%d Items"]):format(#(b.loot or {}))
            r.cols.sub:SetText(table.concat(sub, "  ·  "))
            local nu = 0
            for _, it in ipairs(b.loot or {}) do local pc = upPct(it[1]) if pc and pc > 0 then nu = nu + 1 end end
            r.up:SetText(nu > 0 and ("|TInterface\\Buttons\\Arrow-Up-Up:11:11|t" .. nu) or "")
            r.sel:SetShown(selOn and not bt.selBar:IsShown())
            r.card:SetColorTexture(1, 1, 1, selOn and 0.07 or 0.025)
            r.cols.name:SetTextColor(selOn and 1 or C.text[1], selOn and 1 or C.text[2], selOn and 1 or C.text[3])
        end)
        bt.list.empty:SetText(L["Keine Bosse bekannt."])
        -- Auswahlbalken gleitet zum gewaehlten Boss (nur solange die Liste nicht scrollt)
        bt.selBar = bt.list:CreateTexture(nil, "OVERLAY")
        bt.selBar:SetWidth(2)
        bt.selBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        bt.selBar:Hide()
        function bt:MoveSel(n, idx, animate)
            local l, bar = self.list, self.selBar
            local h = l.rowH
            local fits = n > 0 and idx and n * h <= (l:GetHeight() or 0) + 1
            bar:SetShown(fits and true or false)
            if not fits then self.selY = nil return end
            local to = (idx - 1) * h
            local from = self.selY or to
            local function place(y)
                self.selY = y
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", 0, -y - 1)
                bar:SetHeight(h - 2)
            end
            if animate and animOn() and from ~= to then
                K.Tween(bar, 0.22, function(q) local e = 1 - (1 - q) ^ 3 place(from + (to - from) * e) end, function() place(to) end)
            else
                place(to)
            end
        end

        -- Buehne: dunkler Verlauf, dezent das Dungeon-Bild, Lichtkegel, Boden-Schein
        local stage = CreateFrame("Frame", nil, bt)
        bt.stage = stage
        stage:SetClipsChildren(true)
        stage.bg = K.Fill(stage, { 0.02, 0.02, 0.03, 1 })
        stage.grad = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
        stage.grad:SetAllPoints()
        stage.art = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
        stage.art:SetAllPoints()
        stage.art:SetAlpha(0.18)
        stage.vig = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
        stage.vig:SetAllPoints()
        gradient(stage.vig, "VERTICAL", 0.75, 0.35)
        stage.vigL = stage:CreateTexture(nil, "BACKGROUND", nil, 4)
        stage.vigL:SetPoint("TOPLEFT") stage.vigL:SetPoint("BOTTOMLEFT")
        stage.vigL:SetWidth(44)
        gradient(stage.vigL, "HORIZONTAL", 0.85, 0)
        stage.vigR = stage:CreateTexture(nil, "BACKGROUND", nil, 4)
        stage.vigR:SetPoint("TOPRIGHT") stage.vigR:SetPoint("BOTTOMRIGHT")
        stage.vigR:SetWidth(44)
        gradient(stage.vigR, "HORIZONTAL", 0, 0.85)
        stage.beam = stage:CreateTexture(nil, "BACKGROUND", nil, 5)
        stage.beam:SetPoint("TOP", 0, 0)
        stage.beam:SetSize(130, 300)
        stage.beam:SetBlendMode("ADD")
        stage.lamp = stage:CreateTexture(nil, "BACKGROUND", nil, 6)
        stage.lamp:SetTexture(CIRCLE)
        stage.lamp:SetBlendMode("ADD")
        stage.lamp:SetSize(200, 50)
        stage.lamp:SetPoint("CENTER", stage, "TOP", 0, 0)
        stage.floor = stage:CreateTexture(nil, "BACKGROUND", nil, 6)
        stage.floor:SetTexture(CIRCLE)
        stage.floor:SetBlendMode("ADD")
        stage.floor:SetSize(180, 34)
        stage.floor:SetPoint("BOTTOM", 0, 30)
        stage.shadow = stage:CreateTexture(nil, "BACKGROUND", nil, 7)
        stage.shadow:SetTexture(CIRCLE)
        stage.shadow:SetSize(120, 14)
        stage.shadow:SetPoint("BOTTOM", 0, 40)
        stage.shadow:SetVertexColor(0, 0, 0, 0.55)
        stage.top = stage:CreateTexture(nil, "BORDER")
        stage.top:SetPoint("TOPLEFT") stage.top:SetPoint("TOPRIGHT")
        stage.top:SetHeight(2)
        stage.beam:Hide()
        stage.lamp:Hide()
        stage.floor:Hide()
        stage.shadow:Hide()
        stage.top:SetAlpha(0.2)
        K.Border(stage, C.line)
        bt.model = CreateFrame("PlayerModel", nil, stage)
        bt.model:SetPoint("TOPLEFT", 1, -22)
        bt.model:SetPoint("BOTTOMRIGHT", -1, 22)
        -- Modell: Ziehen dreht (mit Schwung), Mausrad zoomt, Doppelklick setzt zurueck
        local mdl = bt.model
        mdl.facing, mdl.zoom, mdl.spin = 0, 1.15, 0
        mdl:EnableMouse(true)
        mdl:EnableMouseWheel(true)
        function mdl:ResetView()
            self.facing, self.zoom, self.spin = 0, 1.15, 0
            pcall(self.SetPortraitZoom, self, 0)
            pcall(self.SetFacing, self, 0)
            pcall(self.SetCamDistanceScale, self, self.zoom)
        end
        mdl:SetScript("OnMouseDown", function(self, btn)
            if btn ~= "LeftButton" then return end
            self.dragX = GetCursorPosition()
            self.spin = 0
        end)
        mdl:SetScript("OnMouseUp", function(self, btn)
            self.dragX = nil
            local now = GetTime()
            if btn == "LeftButton" and self.lastUp and now - self.lastUp < 0.3 then self:ResetView() end
            self.lastUp = now
        end)
        mdl:SetScript("OnHide", function(self) self.dragX = nil self.spin = 0 end)
        mdl:SetScript("OnUpdate", function(self, el)
            if self.dragX then
                local x = GetCursorPosition()
                local dx = (x - self.dragX) / (self:GetEffectiveScale() or 1)
                self.dragX = x
                self.facing = (self.facing + dx * 0.02) % (math.pi * 2)
                self.spin = dx * 0.02 / math.max(el, 0.001)
                pcall(self.SetFacing, self, self.facing)
            elseif math.abs(self.spin or 0) > 0.05 then
                self.spin = self.spin * (1 - math.min(1, el * 4))
                self.facing = (self.facing + self.spin * el) % (math.pi * 2)
                pcall(self.SetFacing, self, self.facing)
            end
        end)
        mdl:SetScript("OnMouseWheel", function(self, delta)
            self.zoom = math.max(0.8, math.min(3.2, self.zoom - delta * 0.15))
            pcall(self.SetCamDistanceScale, self, self.zoom)
        end)
        mdl:SetScript("OnEnter", function() bt.modelHint:SetAlpha(1) end)
        mdl:SetScript("OnLeave", function() bt.modelHint:SetAlpha(0.45) end)
        bt.modelHint = K.Text(stage, 10, C.dim, "CENTER")
        bt.modelHint:SetPoint("BOTTOMLEFT", 6, 7)
        bt.modelHint:SetPoint("BOTTOMRIGHT", -6, 7)
        bt.modelHint:SetText(L["Ziehen: drehen  ·  Mausrad: zoomen  ·  Doppelklick: zurueck"])
        bt.modelHint:SetAlpha(0.45)
        bt.bossIdx = K.Text(stage, 10, C.dim)
        bt.bossIdx:SetPoint("TOPLEFT", 10, -8)
        -- Pfeile links/rechts: zum vorigen/naechsten Boss blaettern
        bt.nav = {}
        for i, dir in ipairs({ -1, 1 }) do
            local a = CreateFrame("Button", nil, stage)
            a:SetSize(30, 64)
            a:SetPoint(dir < 0 and "LEFT" or "RIGHT", dir < 0 and 2 or -2, 0)
            a:SetFrameLevel(bt.model:GetFrameLevel() + 5)
            a.bg = a:CreateTexture(nil, "BACKGROUND")
            a.bg:SetAllPoints()
            a.bg:SetColorTexture(0, 0, 0, 0.45)
            a.txt = K.Title(a, 18, C.text, "CENTER")
            a.txt:SetPoint("CENTER", 0, 1)
            a.txt:SetText(dir < 0 and "<" or ">")
            a:SetAlpha(0.3)
            a:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                K.ShowTip(self, { dir < 0 and L["Voriger Boss"] or L["Naechster Boss"] })
            end)
            a:SetScript("OnLeave", function(self) self:SetAlpha(0.3) GameTooltip:Hide() end)
            a:SetScript("OnClick", function()
                local n = bt.nBoss or 0
                if n < 2 then return end
                D.PickBoss(((math.min(S.boss or 1, n) - 1 + dir) % n) + 1)
            end)
            bt.nav[i] = a
        end
        -- ohne Modell: Boss-Symbol statt eines falschen Modells
        bt.noModel = CreateFrame("Frame", nil, stage)
        bt.noModel:SetSize(160, 140)
        bt.noModel:SetPoint("CENTER", 0, 10)
        bt.noModel.disc = bt.noModel:CreateTexture(nil, "ARTWORK")
        bt.noModel.disc:SetTexture(CIRCLE)
        bt.noModel.disc:SetSize(84, 84)
        bt.noModel.disc:SetPoint("TOP")
        bt.noModel.icon = bt.noModel:CreateTexture(nil, "OVERLAY")
        bt.noModel.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        bt.noModel.icon:SetSize(46, 46)
        bt.noModel.icon:SetPoint("CENTER", bt.noModel.disc)
        bt.noModel.text = K.Text(bt.noModel, 11, C.dim, "CENTER")
        bt.noModel.text:SetPoint("TOP", bt.noModel.disc, "BOTTOM", 0, -8)
        bt.noModel.text:SetWidth(160)
        bt.noModel.text:SetWordWrap(true)
        bt.noModel.text:SetText(L["Kein 3D-Modell fuer diesen Boss"])
        bt.noModel:Hide()

        local right = K.Panel(bt, { 0.045, 0.045, 0.06, 0.94 })
        bt.right = right
        bt.bossName = K.Title(right, 17, C.text)
        bt.bossName:SetPoint("TOPLEFT", 14, -12)
        bt.bossName:SetPoint("RIGHT", right, "RIGHT", -120, 0)
        bt.bossMeta = K.Text(right, 11, C.muted)
        bt.bossMeta:SetPoint("TOPLEFT", bt.bossName, "BOTTOMLEFT", 0, -5)
        bt.bossMeta:SetPoint("RIGHT", right, "RIGHT", -12, 0)
        bt.bossSep = right:CreateTexture(nil, "ARTWORK")
        bt.bossSep:SetPoint("TOPLEFT", 12, -52)
        bt.bossSep:SetPoint("TOPRIGHT", -12, -52)
        bt.bossSep:SetHeight(1)
        -- Beute oder Taktik zum gewaehlten Boss
        bt.view = K.Segments(right, { { key = "loot", text = L["Beute"] }, { key = "tac", text = L["Taktik"] } }, function(k)
            S.bossView, S.bossAnim = k, true
            ns.RefreshPage("dungeons")
        end, nil, { size = 12, pad = 18 })
        bt.view:SetPoint("TOPLEFT", 10, -58)
        bt.loot = K.List(right, 52, lootRow, lootUpdate)
        bt.loot:SetPoint("TOPLEFT", 6, -90)
        bt.loot:SetPoint("BOTTOMRIGHT", -6, 8)
        bt.more = CreateFrame("Frame", nil, right)
        bt.more:SetPoint("BOTTOMLEFT", 12, 10)
        bt.more:SetPoint("BOTTOMRIGHT", -12, 10)
        bt.more:SetHeight(22)
        bt.more:Hide()
        bt.more.line = bt.more:CreateTexture(nil, "ARTWORK")
        bt.more.line:SetPoint("TOPLEFT", 0, 8)
        bt.more.line:SetPoint("TOPRIGHT", 0, 8)
        bt.more.line:SetHeight(1)
        bt.more.line:SetColorTexture(1, 1, 1, 0.07)
        bt.more.label = K.Text(bt.more, 10, C.dim)
        bt.more.label:SetPoint("TOPLEFT", 4, 0)
        bt.more.label:SetText(K.Upper(L["Weitere Upgrades in diesem Dungeon"]))
        bt.more.row = {}
        for i = 1, 4 do
            local mr = CreateFrame("Button", nil, bt.more)
            mr:SetHeight(28)
            mr:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 30)
            mr:SetPoint("RIGHT", 0, 0)
            mr.hl = mr:CreateTexture(nil, "HIGHLIGHT")
            mr.hl:SetAllPoints()
            mr.hl:SetColorTexture(1, 1, 1, 0.06)
            mr.icon = mr:CreateTexture(nil, "ARTWORK")
            mr.icon:SetSize(22, 22)
            mr.icon:SetPoint("LEFT", 4, 0)
            mr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            mr.pct = K.Title(mr, 12, GREEN, "RIGHT")
            mr.pct:SetPoint("RIGHT", -8, 0)
            mr.name = K.Text(mr, 12, C.text)
            mr.name:SetPoint("LEFT", 34, 0)
            mr.name:SetPoint("RIGHT", mr.pct, "LEFT", -8, 0)
            mr.name:SetWordWrap(false)
            mr:SetScript("OnEnter", function(self)
                if not self.id then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
                GameTooltip:AddLine("|cff777777" .. L["Klick: zum Boss mit diesem Teil"] .. "|r")
                GameTooltip:Show()
            end)
            mr:SetScript("OnLeave", function() GameTooltip:Hide() end)
            mr:SetScript("OnClick", function(self) GameTooltip:Hide() D.PickBoss(self.boss) end)
            bt.more.row[i] = mr
        end
        local tac = CreateFrame("Frame", nil, right)
        tac:SetPoint("TOPLEFT", 16, -96)
        tac:SetPoint("BOTTOMRIGHT", -16, 10)
        tac:Hide()
        bt.tac = tac
        tac.text = K.Text(tac, 12, C.text)
        tac.text:SetPoint("TOPLEFT")
        tac.text:SetPoint("RIGHT")
        tac.text:SetWordWrap(true)
        tac.text:SetJustifyV("TOP")
        if tac.text.SetSpacing then tac.text:SetSpacing(3) end
        tac.label = K.Text(tac, 10, C.dim)
        tac.label:SetPoint("TOPLEFT", tac.text, "BOTTOMLEFT", 0, -18)
        -- Klasse waehlen: zeigt, was genau diese Klasse bei dem Boss tun kann
        tac.btn = {}
        for i = 1, 9 do
            local cb = CreateFrame("Button", nil, tac)
            cb:SetSize(26, 26)
            cb:SetPoint("TOPLEFT", tac.label, "BOTTOMLEFT", (i - 1) * 32 + 2, -10)
            cb.disc = classDisc(cb, 22)
            cb.disc:SetPoint("CENTER")
            cb:SetScript("OnClick", function(self)
                S.tacClass = self.cls
                ns.RefreshPage("dungeons")
            end)
            cb:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                K.ShowTip(self, { (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.cls or ""]) or self.cls or "" })
            end)
            cb:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                local cur = S.tacClass or ns.safe(select(2, UnitClass("player")))
                self:SetAlpha(self.cls == cur and 1 or 0.4)
            end)
            tac.btn[i] = cb
        end
        tac.cls = K.Text(tac, 12, C.text)
        tac.cls:SetPoint("TOPLEFT", tac.label, "BOTTOMLEFT", 0, -48)
        tac.cls:SetPoint("RIGHT")
        tac.cls:SetWordWrap(true)
        tac.cls:SetJustifyV("TOP")
        if tac.cls.SetSpacing then tac.cls:SetSpacing(3) end
        tac.note = K.Text(tac, 10, C.dim)
        tac.note:SetPoint("BOTTOMLEFT")
        tac.note:SetPoint("RIGHT")
        tac.note:SetText(L["Stand Classic - in WoW Forever kann ein Boss abweichen."])
        bt.loot.empty:SetText(L["Keine Beute bekannt."])
        -- 0.6.308: Modell standardmaessig aus - die Buehne nahm ein Drittel der Breite und war meist leer
        bt.modelHidden = not (ns.db and ns.db.settings.dgModel)
        bt.modelToggle = K.Button(right, L["3D-Modell"], 100, 22, "ghost", function()
            bt.modelHidden = not bt.modelHidden
            if ns.db then ns.db.settings.dgModel = not bt.modelHidden end
            bt:Layout()
        end)
        bt.modelToggle:SetPoint("TOPRIGHT", -10, -12)
        function bt:Layout()
            local W = self:GetWidth() or 0
            if W < 50 then W = 750 end
            local lw = math.min(290, math.max(210, math.floor(W * 0.29)))   -- 0.6.307: breiter, Bossnamen ganz
            local showModel = W >= 720 and not self.modelHidden
            local sw = showModel and math.min(340, math.max(220, math.floor(W * 0.31))) or 0
            self.list:ClearAllPoints()
            self.list:SetPoint("TOPLEFT")
            self.list:SetPoint("BOTTOMLEFT")
            self.list:SetWidth(lw)
            self.stage:ClearAllPoints()
            self.stage:SetPoint("TOPLEFT", lw + 10, 0)
            self.stage:SetHeight(math.max(180, self:GetHeight() or 360))
            self.stage:SetWidth(sw)
            self.stage:SetShown(showModel)
            self.modelToggle:SetShown(W >= 720)
            self.right:ClearAllPoints()
            self.right:SetPoint("TOPLEFT", lw + sw + (showModel and 20 or 10), 0)
            self.right:SetPoint("BOTTOMRIGHT")
            self.stage.beam:SetWidth(math.floor(sw * 0.5))
            self.stage.beam:SetHeight(math.floor((self:GetHeight() or 360) * 0.8))
        end
        bt:SetScript("OnSizeChanged", function(self) self:Layout() end)
        bt:Layout()

        -- Reiter Beute: Filter, Karten-Liste
        local lt = CreateFrame("Frame", nil, body)
        lt:SetAllPoints()
        dv.lootTab = lt
        lt.search = K.Input(lt, 190, L["Item suchen ..."], function(t) S.lootSearch = (t or ""):lower() ns.RefreshPage("dungeons") end)
        lt.search:SetPoint("TOPLEFT")
        lt.up = chip(lt, L["Nur Upgrades"], function() S.lootUp = not S.lootUp ns.RefreshPage("dungeons") end)
        lt.up:SetPoint("LEFT", lt.search, "RIGHT", 8, 0)
        lt.kind = menuButton(lt, 150, function()
            return "|cffa3a3a8" .. L["Art"] .. ":|r " .. (S.lootKind and L[S.lootKind] or L["Alle"])
        end, function()
            local items = { { text = L["Alle"], checked = S.lootKind == nil, fn = function() S.lootKind = nil ns.RefreshPage("dungeons") end } }
            for _, k in ipairs({ "Stoff", "Leder", "Kette", "Platte", "Schild", "Waffe", "Sonstiges" }) do
                items[#items + 1] = { text = L[k], checked = S.lootKind == k, fn = function() S.lootKind = k ns.RefreshPage("dungeons") end }
            end
            return items
        end, L["Ruestungsart"])
        lt.kind:SetPoint("LEFT", lt.up, "RIGHT", 8, 0)
        lt.slot = menuButton(lt, 160, function()
            return "|cffa3a3a8" .. L["Platz"] .. ":|r " .. (S.lootSlot or L["Alle"])
        end, function()
            local items = { { text = L["Alle"], checked = S.lootSlot == nil, fn = function() S.lootSlot = nil ns.RefreshPage("dungeons") end } }
            for _, s in ipairs(lt.slots or {}) do
                items[#items + 1] = { text = s, checked = S.lootSlot == s, fn = function() S.lootSlot = s ns.RefreshPage("dungeons") end }
            end
            return items
        end, L["Platz"])
        lt.slot:SetPoint("LEFT", lt.kind, "RIGHT", 8, 0)
        lt.hint = K.Text(lt, 10, C.dim, "RIGHT")
        lt.hint:SetPoint("TOPRIGHT", 0, -7)
        lt.hint:SetText(L["Shift-Klick: verlinken  ·  Rechtsklick: Menue"])
        lt.list = K.List(lt, 44, lootRow, lootUpdate)
        lt.list:SetPoint("TOPLEFT", 0, -34)
        lt.list:SetPoint("BOTTOMRIGHT")
        lt.list.empty:SetText(L["Keine Beute bekannt."])
        lt:SetScript("OnSizeChanged", function(self, w)
            w = w or self:GetWidth() or 750
            local used = 190 + 8 + (lt.up:GetWidth() or 100) + 8 + 150 + 8 + 160
            lt.hint:SetShown(w - used > (lt.hint:GetStringWidth() or 200) + 10)
        end)
        -- Reiter Quests: Liste links, Details rechts
        local qt = CreateFrame("Frame", nil, body)
        qt:SetAllPoints()
        dv.questTab = qt
        qt.list = K.List(qt, 50, function(l)
            local r = K.Row(l)
            -- leichter Farbverlauf je Zustand (von links auslaufend): fehlt rosa, aktiv gelb, erledigt gruen
            r.tint = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.tint:SetAllPoints()
            -- Stufen-Plakette in Questfarbe, Status-Symbol in der Ecke
            r.badge = CreateFrame("Frame", nil, r)
            r.badge:SetSize(32, 32)
            r.badge:SetPoint("LEFT", 7, 0)
            r.badge.bg = r.badge:CreateTexture(nil, "BACKGROUND", nil, 3)
            r.badge.bg:SetAllPoints()
            K.Border(r.badge, C.line)
            r.cols.lvl = K.Title(r.badge, 13, C.text, "CENTER")
            r.cols.lvl:SetPoint("CENTER", 0, 0)
            r.mark = r.badge:CreateTexture(nil, "OVERLAY")
            r.mark:SetSize(16, 16)
            r.mark:SetPoint("CENTER", r.badge, "BOTTOMRIGHT", -1, 2)
            -- Zustand ausgeschrieben oben rechts: fehlt / aktiv / erledigt
            r.cols.st = K.Text(r, 11, C.muted, "RIGHT")
            r.cols.st:SetPoint("TOPRIGHT", -8, -9)
            r.cols.name = K.Title(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 48, -8)
            r.cols.name:SetPoint("RIGHT", r.cols.st, "LEFT", -8, 0)
            r.cols.name:SetWordWrap(false)
            r.cols.who = K.Text(r, 10, C.mint or C.muted, "RIGHT")
            r.cols.who:SetPoint("BOTTOMRIGHT", -8, 8)
            r.cols.where = K.Text(r, 11, C.muted)
            r.cols.where:SetPoint("BOTTOMLEFT", 48, 8)
            r.cols.where:SetPoint("RIGHT", r.cols.who, "LEFT", -6, 0)
            r:SetScript("OnEnter", function(self)
                local q = self.item
                if not q then return end
                local ns_ = {}
                for _, n in ipairs(q.holders or {}) do if not ns.isMe(n) and #ns_ < 8 then ns_[#ns_ + 1] = ns.Radar.Colored(n) end end
                K.ShowTip(self, { q.name, q.level and (L["Stufe %s"]):format(q.level) or nil,
                    #ns_ > 0 and (L["In der Gilde dabei"] .. ": " .. table.concat(ns_, ", ")) or nil })
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.item then return end
                S.quest = self.item.id
                ns.RefreshPage("dungeons")
            end)
            return r
        end, function(r, q)
            r.mark:SetTexture(q.state == "done" and "Interface\\RaidFrame\\ReadyCheck-Ready"
                or q.state == "log" and "Interface\\GossipFrame\\ActiveQuestIcon"
                or "Interface\\GossipFrame\\AvailableQuestIcon")
            r.cols.name:SetText(q.name)
            local st = QUEST_STATE[q.state] or QUEST_STATE.open
            r.cols.st:SetText("|cff" .. st[2] .. L[st[1]] .. "|r")
            local tc = st[3]
            if not K.Gradient(r.tint, "HORIZONTAL", { tc[1], tc[2], tc[3], 0.20 }, { tc[1], tc[2], tc[3], 0.02 }) then
                r.tint:SetColorTexture(tc[1], tc[2], tc[3], 0.08)
            end
            local lv = tonumber(q.level)
            local lc = lv and lvlColor({ lo = lv }) or C.muted
            r.cols.lvl:SetText(lv and tostring(lv) or "?")
            r.cols.lvl:SetTextColor(lc[1], lc[2], lc[3])
            r.badge.bg:SetColorTexture(lc[1], lc[2], lc[3], 0.16)
            K.SetBorderColor(r.badge, lc, 0.55)
            local others = 0
            for _, n in ipairs(q.holders or {}) do if not ns.isMe(n) then others = others + 1 end end
            r.cols.who:SetText(others > 0 and (L["%d aus der Gilde"]):format(others) or "")
            r.cols.where:SetText(q.whereShort or "")
            r.sel:SetShown(S.quest == q.id)
            r:SetAlpha(q.state == "done" and 0.55 or 1)
        end)
        -- Zaehlzeile ueber der Liste: wie viele fehlen, laufen, sind erledigt
        qt.sum = K.Text(qt, 11, C.muted)
        qt.sum:SetPoint("TOPLEFT", 8, -4)
        qt.sum:SetWidth(288)
        qt.sum:SetWordWrap(false)
        qt.list:SetPoint("TOPLEFT", 0, -24)
        qt.list:SetPoint("BOTTOMLEFT")
        qt.list:SetWidth(300)
        qt.list.empty:SetText(L["Noch keine bekannt - sobald jemand mit Oasis eine Quest fuer diesen Dungeon hat, steht sie hier."])

        local qd = K.Panel(qt, C.panel)
        qd:SetPoint("TOPLEFT", 312, 0)
        qd:SetPoint("BOTTOMRIGHT")
        qt.detail = qd
        qd.icon = qd:CreateTexture(nil, "ARTWORK")
        qd.icon:SetSize(22, 22)
        qd.icon:SetPoint("TOPLEFT", 14, -14)
        qd.title = K.Title(qd, 15, C.text)
        qd.title:SetPoint("TOPLEFT", 44, -15)
        qd.title:SetPoint("RIGHT", qd, "RIGHT", -92, 0)
        qd.title:SetWordWrap(true)
        qd.share = K.Button(qd, L["Teilen"], 70, 22, "ghost", function()
            local id = S.quest
            local okI, idx = pcall(function() return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) end)
            if not (okI and idx) then return end
            if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
            if SelectQuestLogEntry then pcall(SelectQuestLogEntry, idx) end
            if QuestLogPushQuest then pcall(QuestLogPushQuest, idx) end
        end)
        qd.share:SetPoint("TOPRIGHT", -12, -12)
        qd.share:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Quest an die Gruppe teilen"], L["Nur in einer Gruppe und mit der Quest im Log."] }) end)
        qd.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Wer aus der Gilde hat die Quest: Klassenkreise (Klick: Fluestern, Einladen, Profil)
        qd.whoLabel = K.Label(qd, L["In der Gilde dabei"])
        qd.who = {}
        for i = 1, 6 do
            local b = CreateFrame("Button", nil, qd)
            b:SetSize(26, 26)
            b.disc = classDisc(b, 24)
            b.disc:SetPoint("CENTER")
            b:RegisterForClicks("AnyUp")
            b:SetScript("OnClick", function(self) personMenu(self, self.name) end)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { ns.Radar.Colored(self.name or ""), "|cff888888" .. L["Klick: Fluestern, Einladen, Profil"] .. "|r" }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            qd.who[i] = b
        end
        qd.whoMore = K.Text(qd, 11, C.dim)
        qd.meta = K.Text(qd, 11, C.muted)
        qd.meta:SetPoint("TOPLEFT", 44, -36)
        qd.meta:SetPoint("RIGHT", qd, "RIGHT", -14, 0)
        qd.text = K.Text(qd, 12, C.text)
        qd.text:SetPoint("TOPLEFT", 14, -62)
        qd.text:SetPoint("RIGHT", qd, "RIGHT", -14, 0)
        qd.text:SetWordWrap(true)
        qd.text:SetJustifyV("TOP")
        qd.text:SetHeight(150)
        -- rechts daneben: Zonenkarte mit Start (!) und Abgabe (?)
        local mh = CreateFrame("Frame", nil, qd)
        mh:SetPoint("TOPLEFT", 14, -230)
        mh:SetPoint("BOTTOMRIGHT", -14, 132)
        -- breit: Text links, Karte gross rechts ueber die ganze Hoehe; schmal: Karte unter dem Text
        function qd:Layout()
            local w, h = self:GetWidth() or 0, self:GetHeight() or 0
            if w < 50 then w, h = 560, 420 end
            self.text:ClearAllPoints()
            self.text:SetPoint("TOPLEFT", 14, -62)
            mh:ClearAllPoints()
            if w >= 460 then
                local tw = math.floor(w * 0.4)
                self.text:SetWidth(tw - 20)
                self.text:SetHeight(math.max(100, h - 62 - 116))
                mh:SetPoint("TOPLEFT", tw + 6, -62)
            else
                -- Karte gleich unter dem Text (so hoch wie er wirklich ist) statt mit festem Abstand
                local th = math.max(30, math.min(self.textH or 110, math.max(30, h - 62 - (self.bottomPad or 110) - 130)))
                self.text:SetPoint("RIGHT", self, "RIGHT", -14, 0)
                self.text:SetHeight(th)
                mh:SetPoint("TOPLEFT", 14, -(62 + th + 10))
            end
            mh:SetPoint("BOTTOMRIGHT", -14, self.bottomPad or 110)
        end
        qd:HookScript("OnSizeChanged", function(self)
            self:Layout()
            if self:IsVisible() and not self.relay then
                self.relay = true
                C_Timer.After(0, function() self.relay = nil if self:IsVisible() then ns.RefreshPage("dungeons") end end)
            end
        end)
        qd:Layout()
        mh:SetClipsChildren(true)
        K.Fill(mh, { 0.03, 0.03, 0.04, 1 })
        K.Border(mh, C.line)
        qd.mapHost = mh
        mh.cap = K.Text(qd, 10, C.dim)
        mh.cap:SetPoint("TOPLEFT", mh, "TOPLEFT", 8, -7)
        mh.cap:SetDrawLayer("OVERLAY")
        mh.cap:SetParent(mh)
        mh.none = K.Text(mh, 11, C.dim, "CENTER")
        mh.none:SetPoint("CENTER")
        mh.none:SetWidth(220)
        mh.none:SetText(L["Fuer diese Quest ist kein Ort bekannt."])
        mh.pins = {}
        for i = 1, 2 do
            local pin = CreateFrame("Button", nil, mh)
            pin:SetSize(24, 24)
            pin:SetFrameLevel(mh:GetFrameLevel() + 10)
            pin.glow = pin:CreateTexture(nil, "BACKGROUND")
            pin.glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            pin.glow:SetPoint("CENTER")
            pin.glow:SetSize(40, 40)
            pin.glow:SetBlendMode("ADD")
            pin.icon = pin:CreateTexture(nil, "ARTWORK")
            pin.icon:SetAllPoints()
            pin.icon:SetTexture(i == 1 and "Interface\\GossipFrame\\AvailableQuestIcon" or "Interface\\GossipFrame\\ActiveQuestIcon")
            pin.glow:SetVertexColor(1, 0.82, 0.2, 0.5)
            pin:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
            pin:SetScript("OnClick", function(self) if self.target and ns.Map then ns.Map.SetTarget(self.target) end end)
            pin:SetScript("OnUpdate", function(self)
                local a = 0.35 + 0.3 * math.sin(GetTime() * 4)
                self.glow:SetAlpha(a)
            end)
            pin:Hide()
            mh.pins[i] = pin
        end
        qd.rewLabel = K.Label(qd, L["Belohnungen"])
        qd.rewLabel:SetPoint("BOTTOMLEFT", 14, 86)
        qd.rewards = {}
        for i = 1, 6 do
            local b = CreateFrame("Button", nil, qd)
            b:SetSize(30, 30)
            b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 36, 50)
            b.border = b:CreateTexture(nil, "BACKGROUND")
            b.border:SetAllPoints()
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:SetScript("OnEnter", function(self)
                if not self.id then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                local _, link = C_Item.GetItemInfo(self.id or 0)
                if link and IsModifiedClick and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link) end
            end)
            qd.rewards[i] = b
        end
        qd.map = K.Button(qd, L["Auf Karte zeigen"], 140, 26, "primary")
        qd.map:SetPoint("BOTTOMLEFT", 14, 12)
        qd.turnin = K.Button(qd, L["Abgabe zeigen"], 120, 26, "ghost")
        qd.turnin:SetPoint("LEFT", qd.map, "RIGHT", 6, 0)
        qd.clear = K.Button(qd, L["Ziel entfernen"], 110, 26, "ghost", function()
            if ns.Map then ns.Map.ClearTarget() end
            ns.RefreshPage("dungeons")
        end)
        qd.clear:SetPoint("LEFT", qd.turnin, "RIGHT", 6, 0)
        -- zur Karte des Dungeons mit den Boss-Standorten (Reiter Karte)
        qd.dmap = K.Button(qd, L["Dungeonkarte"], 120, 26, "ghost", function()
            S.tab, S.tabFade = "map", true   -- 0.6.307: Karte ist eigener Reiter
            ns.RefreshPage("dungeons")
        end)
        qd.dmap:SetPoint("BOTTOMRIGHT", -14, 12)
        qd.dmap:HookScript("OnEnter",function(self) K.ShowTip(self, { L["Dungeonkarte"], L["Karte des Dungeons mit den Standorten der Bosse"] }) end)
        qd.dmap:HookScript("OnLeave",function() GameTooltip:Hide() end)

        -- Reiter Karte: Kartengrafik aus dem Client, Ebenen umschaltbar
        local mt = K.Panel(body, C.panel)
        mt:SetAllPoints()
        dv.mapTab = mt
        mt.floors = {}
        mt.canvas = CreateFrame("Frame", nil, mt)
        mt.canvas:SetPoint("TOPLEFT", 10, -38)
        mt.canvas:SetPoint("BOTTOMRIGHT", -10, 10)
        mt.canvas:SetClipsChildren(true)
        mt.empty = K.Text(mt, 13, C.dim, "CENTER")
        mt.empty:SetPoint("CENTER")
        mt.empty:SetWidth(460)
        mt.empty:SetWordWrap(true)
        mt.canvas:SetScript("OnSizeChanged", function() if mt.cur then drawMap(mt.canvas, mt.cur) end end)

        -- Reiter Gilde
        local gt = CreateFrame("Frame", nil, body)
        gt:SetAllPoints()
        dv.guildTab = gt
        local MINT, GOLD, EPIC = C.mint or { 0.4, 0.86, 0.62 }, { 1, 0.76, 0.3 }, { 0.64, 0.21, 0.93 }
        -- Kennzahl-Kopfzeile
        gt.stats = {}
        local prevStat
        for _, sd in ipairs({ { "on", "online", MINT }, { "loot", "Beute (7 Tage)", EPIC }, { "want", "gesucht", GOLD } }) do
            local s = K.Panel(gt, C.raised)
            s:SetSize(110, 26)
            s.bar = s:CreateTexture(nil, "ARTWORK")
            s.bar:SetPoint("TOPLEFT") s.bar:SetPoint("BOTTOMLEFT") s.bar:SetWidth(3)
            s.bar:SetColorTexture(sd[3][1], sd[3][2], sd[3][3], 0.9)
            s.value = K.Title(s, 14, C.text)
            s.value:SetPoint("LEFT", 11, 0)
            s.label = K.Text(s, 11, C.muted)
            s.label:SetPoint("LEFT", s.value, "RIGHT", 5, 0)
            s.label:SetText(L[sd[2]])
            function s:Set(v)
                self.value:SetText(v)
                self:SetWidth(math.floor((self.value:GetStringWidth() or 10) + (self.label:GetStringWidth() or 40) + 28))
            end
            if prevStat then s:SetPoint("LEFT", prevStat, "RIGHT", 6, 0) else s:SetPoint("TOPLEFT", 0, -1) end
            prevStat = s
            gt.stats[sd[1]] = s
        end
        gt.lfg = K.Button(gt, L["Gruppe suchen"], 112, 24, "primary", function() dv.lfg:Click() end)
        gt.lfg:SetPoint("TOPRIGHT", 0, -2)
        gt.invite = K.Button(gt, L["Alle einladen"], 104, 24, "ghost", function()
            local n = 0
            for _, m in ipairs(gt.range or {}) do
                if n >= 4 then break end
                n = n + 1
                ns.InviteName(m.name)
            end
            if n == 0 then ns.print(L["Keiner zum Einladen online."]) end
        end)
        gt.invite:SetPoint("RIGHT", gt.lfg, "LEFT", -6, 0)
        gt.invite:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Alle einladen"], (L["Laedt bis zu %d Mitglieder aus dem Stufenbereich in deine Gruppe ein."]):format(4) }) end)
        gt.invite:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- 0.6.304: Leiste "Wer will mit?" - eintragen mit Rolle, Eingetragene mit Klasse/Rolle/online, Gruppe bilden
        local ROLES = { "tank", "heal", "dps" }
        local RN = { tank = "Tank", heal = "Heiler", dps = "Schaden" }
        local jb = CreateFrame("Frame", nil, gt)
        jb:SetHeight(84)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(jb, nil, nil, 12) end
        gt.join = jb
        jb.title = K.Title(jb, 13, C.text)
        jb.title:SetPoint("TOPLEFT", 14, -10)
        jb.title:SetText(L["Wer will mit?"])
        jb.sub = K.Text(jb, 10, C.dim)
        jb.sub:SetPoint("LEFT", jb.title, "RIGHT", 8, 0)
        jb.sub:SetText(L["4 Std. sichtbar fuer die Gilde"])
        local function myRole() return (ns.db.settings.dgJoinRole and RN[ns.db.settings.dgJoinRole]) and ns.db.settings.dgJoinRole or "dps" end
        jb.roles = {}
        for i, k in ipairs(ROLES) do
            local b = CreateFrame("Button", nil, jb)
            b:SetSize(26, 26)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetTexture(ns.Profile and ns.Profile.RoleTexture(k))
            b.icon:SetSize(18, 18)
            b.icon:SetPoint("CENTER")
            b.noBoxFrame = true
            b:SetPoint("TOPLEFT", 14 + (i - 1) * 30, -36)
            b:SetScript("OnClick", function()
                ns.db.settings.dgJoinRole = k
                if D.MyJoin(S.dungeon) then D.Join(S.dungeon, k) end
                jb:Update()
            end)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { L[RN[k]], L["Mit dieser Rolle eintragen"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            jb.roles[k] = b
        end
        jb.toggle = K.Button(jb, L["Ich will mit"], 108, 24, "primary", function()
            if D.MyJoin(S.dungeon) then D.Leave(S.dungeon) else D.Join(S.dungeon, myRole()) end
            jb:Update()
        end)
        jb.toggle:SetPoint("LEFT", jb.roles.dps, "RIGHT", 10, 0)
        jb.ask = K.Button(jb, L["Im Gildenchat fragen"], 140, 24, "ghost", function()
            local d = D.Get(S.dungeon)
            if d and ns.OfferChat then
                ns.OfferChat(L["Im Gildenchat fragen"], (L["Wer kommt mit in %s? Ich bin %s dabei - eintragen in Oasis > Dungeons"]):format(d.name, L[RN[myRole()]]), "GUILD")
            end
        end)
        jb.ask:SetPoint("LEFT", jb.toggle, "RIGHT", 6, 0)
        jb.form = K.Button(jb, L["Gruppe bilden"], 112, 24, "primary", function()
            local n = D.FormGroup(S.dungeon)
            ns.print(n > 0 and (L["%d Eingetragene eingeladen."]):format(n) or L["Gerade niemand Eingetragenes online."])
        end)
        jb.form:SetPoint("TOPRIGHT", -12, -10)
        jb.form:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Gruppe bilden"], L["Laedt online Eingetragene ein - erst je ein Tank und Heiler, dann Schaden (hoechstens 4)."] }) end)
        jb.form:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Eingetragene: Klassenkreis mit Rollen-Symbol, Name, gedimmt wenn offline
        jb.people = {}
        for i = 1, 8 do
            local f = CreateFrame("Button", nil, jb)
            f:SetSize(118, 24)
            f.disc = classDisc(f, 20)
            f.disc:SetPoint("LEFT", 0, 0)
            f.role = f:CreateTexture(nil, "OVERLAY")
            f.role:SetSize(12, 12)
            f.role:SetPoint("BOTTOMRIGHT", f.disc, "BOTTOMRIGHT", 3, -2)
            f.name = K.Text(f, 11, C.text)
            f.name:SetPoint("LEFT", f.disc, "RIGHT", 6, 0)
            f.name:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            f.name:SetWordWrap(false)
            f:SetScript("OnClick", function(self) if self.who and not ns.isMe(self.who) then personMenu(self, self.who) end end)
            f:SetScript("OnEnter", function(self)
                if not self.who then return end
                K.ShowTip(self, { ns.Radar.Colored(self.who), L[RN[self.r or "dps"]] .. "  ·  " .. (self.on and L["online"] or L["offline"]),
                    (L["eingetragen %s"]):format(ns.ago(self.ts or 0)), "|cff888888" .. L["Klick: Fluestern, Einladen, Profil"] .. "|r" })
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            jb.people[i] = f
        end
        jb.none = K.Text(jb, 11, C.dim)
        jb.none:SetText(L["Noch niemand eingetragen - sei die oder der Erste."])
        function jb:Update()
            local key = S.dungeon
            if not key then return end
            local mine = D.MyJoin(key)
            local role = (mine and mine.role) or myRole()
            for k, b in pairs(self.roles) do
                local c = ns.Profile and ns.Profile.ROLE_COLORS[k] or { 1, 1, 1 }
                local on = k == role
                b.icon:SetVertexColor(on and c[1] or c[1] * 0.45, on and c[2] or c[2] * 0.45, on and c[3] or c[3] * 0.45)
                b:SetAlpha(on and 1 or 0.7)
            end
            self.toggle:SetLabel(mine and L["Austragen"] or L["Ich will mit"])
            local list = D.JoinList(key)
            local W = self:GetWidth() or 700
            if W < 100 then W = 700 end
            local x0, perRow = 14 + 3 * 30 + 10 + 108 + 6 + 140 + 18, nil
            local avail = W - x0 - 12
            perRow = math.max(1, math.floor(avail / 124))
            local shown = 0
            for i, f in ipairs(self.people) do
                local r = list[i]
                if r and i <= perRow * 1 then
                    f.who, f.r, f.ts = r.who, r.role, r.ts
                    f.on = joinOnline(r.who)
                    f.disc:Set(r.class or classOf(r.who))
                    f.role:SetTexture(ns.Profile and ns.Profile.RoleTexture(r.role or "dps"))
                    f.name:SetText(ns.Radar.Colored(r.who))
                    f:SetAlpha(f.on and 1 or 0.45)
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", x0 + (i - 1) * 124, -38)
                    f:Show()
                    shown = shown + 1
                else
                    f.who = nil
                    f:Hide()
                end
            end
            self.more = #list - shown
            self.none:ClearAllPoints()
            self.none:SetPoint("TOPLEFT", x0, -42)
            self.none:SetShown(#list == 0)
            local onlineOthers = 0
            for _, r in ipairs(list) do if not ns.isMe(r.who) and joinOnline(r.who) then onlineOthers = onlineOthers + 1 end end
            self.form:SetEnabled(onlineOthers > 0)
            self.form:SetAlpha(onlineOthers > 0 and 1 or 0.5)
            self.sub:SetText(#list > shown and ((L["%d eingetragen"]):format(#list) .. "  ·  ") .. L["4 Std. sichtbar fuer die Gilde"] or L["4 Std. sichtbar fuer die Gilde"])
        end

        -- (1) Online im Stufenbereich
        gt.on = colCard(gt, L["Online im Stufenbereich"], MINT, 44, function(l)
            local r = K.Row(l)
            r.disc = classDisc(r, 28)
            r.disc:SetPoint("LEFT", 6, 0)
            r.cols.name = K.Title(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 42, -7)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -34, 0)
            r.cols.lvl = K.Title(r, 13, C.text, "RIGHT")
            r.cols.lvl:SetPoint("TOPRIGHT", -8, -7)
            r.cols.sub = K.Text(r, 10, C.muted)
            r.cols.sub:SetPoint("BOTTOMLEFT", 42, 7)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnClick", function(self) if self.item then personMenu(self, self.item.name) end end)
            r:SetScript("OnEnter", function(self)
                local m = self.item
                if not m then return end
                local cls = (LOCALIZED_CLASS_NAMES_MALE and m.class and LOCALIZED_CLASS_NAMES_MALE[m.class]) or ""
                K.ShowTip(self, { ns.colorName(m.name, m.class), (L["Stufe %d"]):format(m.level or 0) .. (cls ~= "" and ("  ·  " .. cls) or ""),
                    m.zone ~= "" and m.zone or nil, "|cff888888" .. L["Klick: Fluestern, Einladen, Profil"] .. "|r" })
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, m)
            r.disc:Set(m.class, m.name)
            local cr, cg, cb = ns.classColor(m.class)
            r.cols.name:SetText(ns.displayName(m.name))
            r.cols.name:SetTextColor(cr, cg, cb)
            r.cols.lvl:SetText(m.level or "")
            local me = ns.safe(UnitLevel("player")) or 1
            local lc = lvlColor({ lo = m.level or me })
            r.cols.lvl:SetTextColor(lc[1], lc[2], lc[3])
            local sub = {}
            local stt = m.status
            if stt == 1 or (type(stt) == "string" and stt:find("AFK")) then sub[#sub + 1] = "|cffffd24a" .. L["AFK"] .. "|r"
            elseif stt == 2 or (type(stt) == "string" and stt:find("DND")) then sub[#sub + 1] = "|cffd9786b" .. L["DNB"] .. "|r" end
            local here = (m.zone or "") ~= "" and m.zone == (ns.safe(GetRealZoneText()) or "")
            if (m.zone or "") ~= "" then sub[#sub + 1] = here and ("|cff66db9e" .. m.zone .. "  ·  " .. L["hier"] .. "|r") or m.zone end
            r.cols.sub:SetText(table.concat(sub, "  ·  "))
        end)
        gt.on.empty.icon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
        -- (2) Zuletzt erbeutet: Zeitleiste
        local function lootLink(e) return e and e.item end
        local function lootID(e) return e and (e.itemID or ns.itemID(e.item or "")) end
        gt.loot = colCard(gt, L["Zuletzt erbeutet"], EPIC, 46, function(l)
            local r = K.Row(l)
            r.stripe:SetAlpha(0)
            r.line = r:CreateTexture(nil, "BACKGROUND", nil, 3)
            r.line:SetColorTexture(1, 1, 1, 0.12)
            r.line:SetWidth(2)
            r.line:SetPoint("TOP", r, "TOPLEFT", 22, 0)
            r.line:SetPoint("BOTTOM", r, "BOTTOMLEFT", 22, -1)
            r.iconHost = roundIcon(r, 28)
            r.iconHost:SetPoint("CENTER", r, "LEFT", 22, 0)
            r.pct = K.Title(r, 11, GREEN, "RIGHT")
            r.pct:SetPoint("TOPRIGHT", -8, -8)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 44, -8)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -46, 0)
            r.cols.sub = K.Text(r, 10, C.muted)
            r.cols.sub:SetPoint("BOTTOMLEFT", 44, 8)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local link, id = lootLink(e), lootID(e)
                if not (link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)) and id then pcall(GameTooltip.SetItemByID, GameTooltip, id) end
                local m = id and markOf(id)
                if m and m.up then GameTooltip:AddLine("|cff66db9e" .. (L["Besser als dein angelegtes Teil (+%d%%)"]):format(math.min(m.pct, 999)) .. "|r") end
                GameTooltip:AddLine("|cff777777" .. L["Shift-Klick: verlinken  ·  Rechtsklick: Menue"] .. "|r")
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self, btn)
                local e = self.item
                if not e then return end
                local link, id = lootLink(e), lootID(e)
                if btn == "RightButton" then if id then lootMenu(self, id) end return end
                if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
                elseif e.who then personMenu(self, e.who) end
            end)
            return r
        end, function(r, e, idx)
            local id = lootID(e)
            local info = id and itemInfo({ id }) or { icon = 134400, color = QCOL[2], quality = 2 }
            local q = e.quality or info.quality or 2
            local qc = QUAL_RGB[q] or QUAL_RGB[2]
            r.iconHost.icon:SetTexture(info.icon)
            r.iconHost.ring:SetVertexColor(qc[1], qc[2], qc[3], 1)
            local nm = (e.item or ""):match("%[(.-)%]") or info.name or "?"
            r.cols.name:SetText("|c" .. (QCOL[q] or info.color) .. nm .. "|r")
            r.cols.sub:SetText(ns.Radar.Colored(e.who or "?") .. "  |cff777777" .. ns.ago(e.ts or e.u) .. "|r")
            r.line:SetPoint("TOP", r, "TOPLEFT", 22, idx == 1 and -23 or 0)
            r.line:SetShown(#r:GetParent().data > 1)
            local m = id and markOf(id)
            local up = m and m.up
            r.pct:SetText(up and ("+" .. math.min(m.pct, 999) .. "%") or "")
            if ns.Upgrade and ns.Upgrade.Glow then pcall(ns.Upgrade.Glow, r.iconHost, up and m.pct or nil, not animOn()) end
        end)
        gt.loot.empty.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        -- (3) Gesucht aus diesem Dungeon
        gt.want = colCard(gt, L["Gesucht aus diesem Dungeon"], GOLD, 50, function(l)
            local r = K.Row(l)
            r.iconHost = CreateFrame("Frame", nil, r)
            r.iconHost:SetSize(30, 30)
            r.iconHost:SetPoint("LEFT", 6, 0)
            r.border = r.iconHost:CreateTexture(nil, "BORDER")
            r.border:SetAllPoints()
            r.icon = K.Icon(r.iconHost, 28)
            r.icon:SetPoint("CENTER")
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 44, -9)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -74, 0)
            r.cols.sub = K.Text(r, 10, C.muted)
            r.cols.sub:SetPoint("BOTTOMLEFT", 44, 9)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -74, 0)
            r.have = K.Button(r, L["Ich hab's"], 62, 22, "ghost", function(b)
                local w = b:GetParent().item
                if not w then return end
                local info = itemInfo({ w.itemID, w.name })
                ns.Whisper(w.who, (L["Ich habe %s - brauchst du das noch?"]):format(w.link or info.link or info.name))
            end)
            r.have:SetPoint("RIGHT", -6, 0)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnEnter", function(self)
                local w = self.item
                if not (w and w.itemID) then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, w.itemID)
                if w.note and w.note ~= "" then GameTooltip:AddLine("|cffffd24a" .. w.note .. "|r", 1, 1, 1, true) end
                GameTooltip:AddLine("|cff777777" .. L["Shift-Klick: verlinken  ·  Rechtsklick: Menue"] .. "|r")
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self, btn)
                local w = self.item
                if not w then return end
                local info = itemInfo({ w.itemID, w.name })
                if btn == "LeftButton" and info.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(info.link) return end
                personMenu(self, w.who)
            end)
            return r
        end, function(r, w)
            local info = itemInfo({ w.itemID, w.name })
            r.icon:SetTexture(info.icon)
            local rr, gg, bb = hexRGB(info.color)
            r.border:SetColorTexture(rr, gg, bb, 0.9)
            r.cols.name:SetText("|c" .. info.color .. info.name .. "|r" .. ((w.qty or 1) > 1 and ("  |cff888888x" .. w.qty .. "|r") or ""))
            local mine = ns.isMe(w.who or "")
            local src = D.Source(w.itemID)
            r.cols.sub:SetText((mine and ("|cff66db9e" .. L["dein Wunsch"] .. "|r") or (L["sucht: %s"]):format(ns.Radar.Colored(w.who or "?")))
                .. ((src and src.boss) and ("  ·  |cff888888" .. src.boss .. "|r") or ""))
            r.have:SetShown(not mine)
        end)
        gt.want.empty.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        -- 0.6.305: Hinweis statt zweier leerer Karten (keine Gildenbeute, keine Wuensche aus diesem Dungeon)
        gt.hint = CreateFrame("Button", nil, gt)
        gt.hint:SetHeight(20)
        gt.hint.t = K.Text(gt.hint, 11, C.dim)
        gt.hint.t:SetPoint("LEFT", 0, 0)
        gt.hint.t:SetText(L["Noch keine Gildenbeute und keine Wuensche aus diesem Dungeon."] .. "  |cffe8b44a" .. L["Beute ansehen"] .. " >|r")
        gt.hint:SetWidth(520)
        gt.hint:SetScript("OnClick", function() S.tab, S.tabFade = "loot", true ns.RefreshPage("dungeons") end)
        gt.hint:Hide()
        function gt:Layout()
            local W, H = self:GetWidth() or 0, self:GetHeight() or 0
            if W < 50 then W = 750 end
            if H < 50 then H = 390 end
            local gap = 10
            -- 0.6.305: aufgeraeumt - keine Kennzahl-Zeile (steht im Banner), kein zweites "Gruppe suchen" (Banner);
            -- "Wer will mit?" ganz oben, "Alle einladen" sitzt darin neben "Gruppe bilden"
            for _, st in pairs(self.stats) do st:Hide() end
            self.lfg:Hide()
            self.join:ClearAllPoints()
            self.join:SetPoint("TOPLEFT", 0, 0) self.join:SetPoint("TOPRIGHT", 0, 0)
            self.invite:SetParent(self.join)
            self.invite:ClearAllPoints()
            self.invite:SetPoint("RIGHT", self.join.form, "LEFT", -6, 0)
            self.invite:Show()
            local top = 84 + gap
            for _, c in ipairs({ self.on, self.loot, self.want }) do c:ClearAllPoints() end
            local bothEmpty = self.emptyBoth
            self.loot:SetShown(not bothEmpty) self.want:SetShown(not bothEmpty)
            self.hint:SetShown(bothEmpty and true or false)
            if bothEmpty then
                self.on:SetPoint("TOPLEFT", 0, -top) self.on:SetPoint("BOTTOMRIGHT", 0, 30)
                self.hint:ClearAllPoints() self.hint:SetPoint("BOTTOMLEFT", 2, 4)
            elseif W >= 640 then
                local wOn = math.floor((W - 2 * gap) * 0.31)
                local wLoot = math.floor((W - 2 * gap) * 0.36)
                self.on:SetPoint("TOPLEFT", 0, -top) self.on:SetPoint("BOTTOMLEFT") self.on:SetWidth(wOn)
                self.loot:SetPoint("TOPLEFT", wOn + gap, -top) self.loot:SetPoint("BOTTOMLEFT", wOn + gap, 0) self.loot:SetWidth(wLoot)
                self.want:SetPoint("TOPLEFT", wOn + wLoot + 2 * gap, -top) self.want:SetPoint("BOTTOMRIGHT")
            else
                -- schmal: Online links, rechts Beute oben / Gesucht unten
                local wOn = math.floor((W - gap) * 0.42)
                local half = math.floor((H - top - gap) / 2)
                self.on:SetPoint("TOPLEFT", 0, -top) self.on:SetPoint("BOTTOMLEFT") self.on:SetWidth(wOn)
                self.loot:SetPoint("TOPLEFT", wOn + gap, -top) self.loot:SetPoint("TOPRIGHT", 0, -top) self.loot:SetHeight(half)
                self.want:SetPoint("TOPLEFT", self.loot, "BOTTOMLEFT", 0, -gap) self.want:SetPoint("BOTTOMRIGHT")
            end
        end
        gt:SetScript("OnSizeChanged", function(self) self:Layout() end)
        gt:Layout()
    end,

    refresh = function(p)
        if not S.filter then
            -- persoenlicher Start-Filter (Einstellungen > Bereiche > Dungeons); ohne: "Fuer mich", sonst "Alle offenen"
            local pref = ns.db and ns.db.settings.dgFilter
            S.filter = pref or "mine"
            local any = false
            for _, d in ipairs(D.List()) do if not d.closed and fits(d) then any = true break end end
            if not any and not pref then S.filter = "open" end
            S.stagger = true
        end
        -- "Alle offenen" ist kein eigener Reiter mehr: Reiter "Alle" mit dem Filter "Nur geoeffnete"
        if S.filter == "open" then S.filter, S.openOnly = "all", true end
        local d = S.view == "dungeon" and D.Get(S.dungeon) or nil
        if not d then S.view = "home" end
        local wasHome = p.home:IsShown()
        p.home:SetShown(S.view == "home")
        p.dv:SetShown(S.view == "dungeon")
        -- weicher Uebergang zwischen Uebersicht und Dungeon
        if S.fadeIn == "dv" and S.view == "dungeon" then K.FadeIn(p.dv, 0) end
        if S.fadeIn == "home" and S.view == "home" then S.stagger = true end
        S.fadeIn = nil

        if S.view == "home" then
            local home = p.home
            if not home.cols then home:Layout() end
            if home.seg.value ~= S.filter then home.seg:Select(S.filter) end
            if S.upOnly and not upOn() then S.upOnly = false end
            home.filter:Update()
            pcall(home.gbar.Update, home.gbar)
            local list = homeList()
            local cols, rows = home.cols or 3, home.rowsVis or 2
            local rowsTotal = math.ceil(#list / cols)
            S.homeOffset = math.min(S.homeOffset, math.max(0, rowsTotal - rows))
            local stagger = (S.stagger or not wasHome) and animOn()
            S.stagger = nil
            local shown = 0
            for i, c in ipairs(home.cards) do
                local e = c.slot and list[S.homeOffset * cols + i]
                if e then
                    fillCard(c, e)
                    c:Show()
                    shown = shown + 1
                    if stagger then c.oasisFadedAt = nil K.FadeIn(c, (shown - 1) * 0.035) end
                else
                    c:Hide()
                end
            end
            home.count:SetText((L["%d Dungeons"]):format(#list) .. (rowsTotal > rows and ("  ·  " .. L["Mausrad: mehr"]) or ""))
            home.empty:SetShown(#list == 0)
            if #list == 0 then
                local filtered = (S.homeSearch ~= "") or S.homeZone or S.upOnly
                local function reset()
                    S.homeSearch, S.homeZone, S.upOnly, S.openOnly = "", nil, false, false
                    home.search:SetText("")
                    ns.RefreshPage("dungeons")
                end
                if filtered then
                    home.empty:Set(L["Keine Dungeons zu diesen Filtern."], L["Filter zuruecksetzen"], reset,
                        S.filter ~= "all" and L["Alle zeigen"] or nil, function() S.filter = "all" reset() end)
                else
                    home.empty:Set(L["Gerade passt kein offener Dungeon zu deiner Stufe."], L["Alle offenen zeigen"],
                        function() S.filter = "open" ns.RefreshPage("dungeons") end, L["Alle"], function() S.filter = "all" ns.RefreshPage("dungeons") end)
                end
            end
            do
                local cnt = { mine = 0, all = 0 }
                for _, x in ipairs(D.List()) do
                    cnt.all = cnt.all + 1
                    if not x.closed and fits(x) then cnt.mine = cnt.mine + 1 end
                end
                home.seg:SetCounts(cnt)
            end
            return
        end

        -- Dungeon-Seite
        local dv = p.dv
        local t = tone(d)
        dv.tone:SetColorTexture(t[1], t[2], t[3], 1)
        dv.bannerLine:SetColorTexture(t[1] * 0.6 + 0.3, t[2] * 0.6 + 0.3, t[3] * 0.6 + 0.3, 0.9)
        local art = artOf(d)
        dv.art:SetTexture(art)
        dv.art:SetShown(art ~= nil)
        dv.title:SetText(d.name)
        if D.LoadLoot then pcall(D.LoadLoot, d) end
        local bosses = D.Bosses(d)
        local nBoss = 0
        for _, b in ipairs(bosses) do if not b.trash and not b.object then nBoss = nBoss + 1 end end
        local meta = {}
        if d.level ~= "" then meta[#meta + 1] = (L["Stufe %s"]):format(d.level) end
        if (d.location or "") ~= "" then meta[#meta + 1] = d.location end
        if d.closed then meta[#meta + 1] = "|cffd9786b" .. L["noch geschlossen"] .. "|r" end
        dv.meta:SetText(table.concat(meta, "  ·  "))
        local fj = ns.Fojji and ns.Fojji.Dungeon(d.key) ~= nil
        dv.journal:SetShown(fj or D.CanOpenJournal(d))
        dv.journal:SetLabel(fj and L["In FojjiCore oeffnen"] or L["Dungeon-Journal"])
        dv.journal:SetWidth(fj and 150 or 120)
        -- Kennzahlen
        local nUps = dungeonUps(d)
        local qLog, qAll = questCount(d)
        local inRange = othersInRange(d)
        dv.kpis.bosses.value:SetText(nBoss)
        dv.kpis.bosses.tip = { L["Bosse"], "|cff888888" .. L["Klick: Bosse zeigen"] .. "|r" }
        dv.kpis.ups.value:SetText(upOn() and nUps or "-")
        dv.kpis.ups.value:SetTextColor(nUps > 0 and GREEN[1] or C.text[1], nUps > 0 and GREEN[2] or C.text[2], nUps > 0 and GREEN[3] or C.text[3])
        dv.kpis.ups.tip = { L["Upgrades"], upOn() and L["Beute, die besser ist als deine angelegte Ausruestung"] or L["Hervorheben ist in den Einstellungen aus"], "|cff888888" .. L["Klick: nur Upgrades zeigen"] .. "|r" }
        dv.kpis.quests.value:SetText(qAll > 0 and (qLog .. "/" .. qAll) or "0")
        dv.kpis.quests.tip = { L["Quests"], (L["%d in deinem Log, %d bekannt"]):format(qLog, qAll) }
        dv.kpis.guild.value:SetText(#inRange)
        dv.kpis.guild.tip = { L["Gilde dabei"], L["Online im Stufenbereich"] }
        dv.seg:SetCounts({ g1 = nUps > 0 and nUps or nil, g2 = qAll > 0 and qAll or nil })
        local grp = S.group[S.tab] or "g1"
        if S.sub[grp] then S.sub[grp] = S.tab end
        if dv.seg.value ~= grp then dv.seg:Select(grp) end
        for g, sw in pairs(dv.subs) do
            sw:SetShown(g == grp)
            if g == grp and sw.value ~= S.tab then sw:Select(S.tab) end
        end
        local tabs = { bosses = dv.bossTab, loot = dv.lootTab, quests = dv.questTab, guild = dv.guildTab, map = dv.mapTab }
        for k, f in pairs(tabs) do f:SetShown(S.tab == k) end
        if S.tabFade then
            S.tabFade = nil
            local f = tabs[S.tab]
            if f then f.oasisFadedAt = nil K.FadeIn(f, 0) end
        end
        if S.tab == "map" then
            local mt = dv.mapTab
            local lcfg = ns.DungeonMapsData and ns.DungeonMapsData[d.dbKey or d.key]
            local lok = false
            if lcfg and (lcfg.folder or lcfg.bundled) then
                for _, b in ipairs(mt.floors) do b:Hide() end
                if S.lmapFor ~= d.key then S.lmapFor, S.lfloor = d.key, (lcfg.floors or { 1 })[1] end
                local fls = lcfg.floors or { 1 }
                local function flName(i) return lcfg.floorNames and L[lcfg.floorNames[i]] or ((L["Ebene %d"]):format(i)) end
                if not mt.floorDrop then
                    mt.floorDrop = K.Button(mt, "", 260, 24, "ghost")
                    mt.floorDrop.label:ClearAllPoints()
                    mt.floorDrop.label:SetPoint("LEFT", 10, 0)
                    mt.floorDrop.label:SetPoint("RIGHT", -22, 0)
                    mt.floorDrop.label:SetJustifyH("LEFT")
                    mt.floorDrop.arrow = K.Text(mt.floorDrop, 10, C.dim, "RIGHT")
                    mt.floorDrop.arrow:SetPoint("RIGHT", -8, 0)
                    mt.floorDrop.arrow:SetText("v")
                    mt.floorDrop:SetPoint("TOPLEFT", 10, -8)
                end
                local curIdx = 1
                for i, fl in ipairs(fls) do if fl == S.lfloor then curIdx = i end end
                mt.floorDrop:SetLabel("|cffa3a3a8" .. L["Ebene"] .. ":|r " .. flName(curIdx) .. "  |cff666666(" .. curIdx .. "/" .. #fls .. ")|r")
                mt.floorDrop:SetScript("OnClick", function(self)
                    local items = {}
                    for i, fl in ipairs(fls) do
                        items[#items + 1] = { text = flName(i), checked = fl == S.lfloor, fn = function() S.lfloor = fl ns.RefreshPage("dungeons") end }
                    end
                    K.ShowMenu(self, items, nil, 260)
                end)
                mt.floorDrop:SetShown(#fls > 1)
                -- Blizzard-Kartenkacheln der neuen Schnittstelle ausblenden
                if mt.canvas.tiles then for _, t in ipairs(mt.canvas.tiles) do t:Hide() end end
                if mt.pins then for _, pin in ipairs(mt.pins) do pin:Hide() end end
                if ns.DungeonTrace then ns.DungeonTrace.Draw(mt.canvas, nil) end
                mt.canvas.curDungeon = d
                lok = drawLegacyMap(mt.canvas, lcfg, S.lfloor)
            else
                drawLegacyMap(mt.canvas, nil)
                if mt.floorDrop then mt.floorDrop:Hide() end
            end
            mt.empty:SetShown(not lok)
            if mt.link then mt.link:SetShown(not lok) mt.linkHint:SetShown(not lok) end
            if mt.atlas then mt.atlas:SetShown(not lok) end
            if mt.traceInfo then mt.traceInfo:SetShown(false) end
            if mt.credit == nil then
                -- eigene Ebene ueber der Karte mit dunklem Hintergrund, damit es lesbar bleibt
                local cf = CreateFrame("Frame", nil, mt)
                cf:SetFrameLevel(mt:GetFrameLevel() + 30)
                cf:SetPoint("BOTTOMRIGHT", -6, 6)
                cf:SetSize(10, 18)
                cf.bg = cf:CreateTexture(nil, "BACKGROUND")
                cf.bg:SetAllPoints()
                cf.bg:SetColorTexture(0, 0, 0, 0.75)
                mt.credit = K.Text(cf, 10, C.muted, "RIGHT")
                mt.credit:SetPoint("RIGHT", -6, 0)
                mt.creditFrame = cf
            end
            mt.credit:SetText(lok and L["Karten: WoW-Client  ·  Boss-Positionen: Forever Atlas (GPL) / SimpleDungeonMap (MIT)"] or "")
            mt.creditFrame:SetShown(lok and true or false)
            mt.creditFrame:SetWidth((mt.credit:GetStringWidth() or 300) + 12)
        end
        if S.tab == "map" and not (ns.DungeonMapsData and ns.DungeonMapsData[d.dbKey or d.key] and (ns.DungeonMapsData[d.dbKey or d.key].folder or ns.DungeonMapsData[d.dbKey or d.key].bundled)) then
            local mt = dv.mapTab
            local maps = dungeonMaps(d)
            for _, b in ipairs(mt.floors) do b:Hide() end
            if S.mapFor ~= d.key then S.mapFor, S.mapIdx = d.key, 1 end
            for i, m in ipairs(maps) do
                local b = mt.floors[i]
                if not b then
                    b = K.Button(mt, "", 120, 22, "ghost")
                    mt.floors[i] = b
                end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 10 + (i - 1) * 126, -8)
                b:SetLabel((i == S.mapIdx and (K.hex(C.accent) .. "> |r") or "") .. m.name)
                b:SetScript("OnClick", function() S.mapIdx = i ns.RefreshPage("dungeons") end)
                b:SetShown(#maps > 1)
            end
            local cur = maps[S.mapIdx or 1]
            mt.cur = cur and cur.id or nil
            local ok = cur and drawMap(mt.canvas, cur.id)
            -- Boss-Standorte auf der gewaehlten Ebene
            mt.pins = mt.pins or {}
            for _, pin in ipairs(mt.pins) do pin:Hide() end
            local list = ns.BossPos and ns.BossPos[d.dbKey or d.key]
            if ok and list and mt.canvas.mapRect then
                local R = mt.canvas.mapRect
                local n = 0
                for idx, bp in ipairs(list) do
                    if bp.map == cur.id then
                        n = n + 1
                        local pin = mt.pins[n]
                        if not pin then
                            pin = CreateFrame("Frame", nil, mt.canvas)
                            pin:SetSize(22, 22)
                            pin.ring = pin:CreateTexture(nil, "ARTWORK")
                            pin.ring:SetTexture(ns.MEDIA .. "dot")
                            pin.ring:SetAllPoints()
                            pin.ring:SetVertexColor(0.05, 0.05, 0.06)
                            pin.dot = pin:CreateTexture(nil, "OVERLAY")
                            pin.dot:SetTexture(ns.MEDIA .. "dot")
                            pin.dot:SetSize(16, 16)
                            pin.dot:SetPoint("CENTER")
                            pin.dot:SetVertexColor(C.red[1], C.red[2], C.red[3])
                            pin.num = K.Title(pin, 10, C.text, "CENTER")
                            K.CenterNum(pin.num, nil, "CENTER", 0, 0)
                            pin.lbl = K.Text(pin, 10, C.text, "CENTER")
                            pin.lbl:SetPoint("TOP", pin, "BOTTOM", 0, -1)
                            pin.lbl:SetShadowOffset(1, -1)
                            pin:EnableMouse(true)
                            pin:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                            mt.pins[n] = pin
                        end
                        pin:SetFrameLevel(mt.canvas:GetFrameLevel() + 10)
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", mt.canvas, "TOPLEFT", R.x + bp.x * R.w, -(R.y + bp.y * R.h))
                        pin.num:SetText(idx)
                        pin.lbl:SetText(bp.boss)
                        pin.tip = { bp.boss, "|cff888888" .. L["Boss-Standort laut Spieldaten"] .. "|r" }
                        pin:Show()
                    end
                end
            end
            -- keine Karte im Client: selbst erkundete Karte der Oasis-Spieler
            local traced = false
            if ns.DungeonTrace then
                if not ok then
                    local data = ns.DungeonTrace.Get(d.name, d.de)
                    traced = ns.DungeonTrace.Draw(mt.canvas, data)
                    mt.traceInfo = mt.traceInfo or K.Text(mt, 10, C.dim)
                    mt.traceInfo:SetPoint("BOTTOMLEFT", 12, 10)
                    mt.traceInfo:SetText(traced and (L["Von Oasis-Spielern erkundet: %d Punkte, %d Spieler, %d Bosse"]):format(data.n, data.players, (function() local c = 0 for _ in pairs(data.bosses) do c = c + 1 end return c end)()) or "")
                    mt.traceInfo:SetShown(traced)
                else
                    ns.DungeonTrace.Draw(mt.canvas, nil)
                    if mt.traceInfo then mt.traceInfo:Hide() end
                end
            end
            mt.empty:SetShown(not ok and not traced)
            -- keine Blizzard-Karte: Link zur Fan-Karte im Browser (zum Kopieren)
            if not mt.link then
                mt.link = K.Input(mt, 360, "", nil)
                mt.link:SetPoint("BOTTOM", mt, "BOTTOM", 0, 40)
                mt.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
                mt.link:SetScript("OnTextChanged", function(self, user) if user and self.url then self:SetText(self.url) self:HighlightText() end end)
                mt.linkHint = K.Text(mt, 10, C.dim, "CENTER")
                mt.linkHint:SetPoint("BOTTOM", mt.link, "TOP", 0, 6)
                mt.linkHint:SetText(L["Karte online ansehen: Link anklicken, Strg+C, im Browser einfuegen"])
            end
            local slug = tostring(d.nameEN or d.name or ""):lower():gsub("'", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
            mt.link.url = "https://foreverchanges.pro/map/" .. slug
            if not mt.link:HasFocus() then mt.link:SetText(mt.link.url) end
            mt.link:SetShown(not ok)
            mt.linkHint:SetShown(not ok)
            -- Atlas (Kartensammlung, GPL): wenn installiert, direkt oeffnen; sonst zur Installation auffordern
            if not mt.atlas then
                mt.atlas = K.Button(mt, "", 220, 26, "primary", function()
                    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Atlas")
                    if not loaded and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Atlas") end
                    if type(_G.Atlas_Toggle) == "function" then pcall(_G.Atlas_Toggle)
                    elseif _G.AtlasFrame then _G.AtlasFrame:SetShown(not _G.AtlasFrame:IsShown())
                    else ns.print(L["Atlas ist nicht installiert: in der CurseForge-App \"Atlas\" und \"Atlas Classic WoW\" installieren, dann WoW neu starten."]) end
                end)
                mt.atlas:SetPoint("BOTTOM", mt.linkHint, "TOP", 0, 10)
            end
            local hasAtlas = (C_AddOns and C_AddOns.GetAddOnInfo and select(2, pcall(C_AddOns.GetAddOnInfo, "Atlas"))) and true or false
            local atlasName = C_AddOns and C_AddOns.GetAddOnInfo and select(2, pcall(C_AddOns.GetAddOnInfo, "Atlas"))
            hasAtlas = type(atlasName) == "string" and atlasName ~= ""
            mt.atlas:SetLabel(hasAtlas and L["Karte in Atlas oeffnen"] or L["Atlas installieren fuer Karten"])
            mt.atlas:SetScript("OnEnter", function(self)
                K.ShowTip(self, hasAtlas and { L["Atlas"], L["Oeffnet die Atlas-Karten (Dungeon dort auswaehlen)."] }
                    or { L["Atlas fehlt"], L["WoW Classic hat keine Dungeon-Karten. Das kostenlose Addon Atlas bringt sie mit:"], L["CurseForge-App: \"Atlas\" und \"Atlas Classic WoW\" installieren, WoW neu starten."] })
            end)
            mt.atlas:SetScript("OnLeave", function() GameTooltip:Hide() end)
            mt.atlas:SetShown(not ok)
            mt.empty:SetText(L["Fuer diesen Dungeon hat der Client keine Karte. Oasis zeichnet sie selbst, sobald Oasis-Spieler den Dungeon ablaufen - je mehr Leute, desto genauer."])
        end
        if S.tab == "map" then
            local lcfg = ns.DungeonMapsData and ns.DungeonMapsData[d.dbKey or d.key]
            local lok = lcfg and (lcfg.folder or lcfg.bundled) and not dv.mapTab.empty:IsShown()
            pcall(MC.Update, dv.mapTab, d, S.lfloor, lok)
        end

        if S.tab == "bosses" then
            local bt = dv.bossTab
            bt.tone = t
            bt.nBoss = #bosses
            -- anderer Dungeon/Boss: Balken gleitet, Beute blendet gestaffelt ein
            local bossKey = d.key .. ":" .. tostring(S.boss)
            local switched = S.bossAnim or bt.shownBoss ~= bossKey
            bt:MoveSel(#bosses, bosses[S.boss] and S.boss or (bosses[1] and 1) or nil, S.bossAnim and bt.shownFor == d.key)
            bt.shownBoss, bt.shownFor, S.bossAnim = bossKey, d.key, nil
            bt.list:SetData(bosses)
            for _, a in ipairs(bt.nav) do a:SetShown(#bosses > 1) end
            local b = bosses[S.boss] or bosses[1]
            local stage = bt.stage
            -- Buehne: nur das eigene Ladebild des Dungeons (nie das Kontinentbild mit Logo), mittig und sehr dezent
            local own = ART[d.nameEN or ""] or ART[d.key or ""]
            stage.art:SetShown(own ~= nil)
            if own then
                stage.art:SetTexture(own)
                stage.art:SetTexCoord(0.38, 0.62, 0.30, 0.64)
                stage.art:SetVertexColor(0.7, 0.7, 0.75)
            end
            grad(stage.grad, "VERTICAL", { 0.08, 0.08, 0.11 }, 0.7, 0.15)
            if not K.Gradient(stage.beam, "VERTICAL", { t[1] * 0.5 + 0.5, t[2] * 0.5 + 0.5, t[3] * 0.5 + 0.5, 0 }, { t[1] * 0.5 + 0.5, t[2] * 0.5 + 0.5, t[3] * 0.5 + 0.5, 0.09 }) then stage.beam:Hide() end
            stage.lamp:SetVertexColor(t[1] * 0.5 + 0.5, t[2] * 0.5 + 0.5, t[3] * 0.5 + 0.5, 0.12)
            stage.floor:SetVertexColor(t[1], t[2], t[3], 0.3)
            stage.top:SetColorTexture(t[1], t[2], t[3], 0.9)
            bt.noModel.disc:SetVertexColor(t[1] * 0.35, t[2] * 0.35, t[3] * 0.35)
            bt.bossSep:SetColorTexture(t[1], t[2], t[3], 0.35)
            bt.bossIdx:SetText(#bosses > 0 and K.Upper((L["Boss %d / %d"]):format(math.min(S.boss or 1, #bosses), #bosses)) or "")
            if b then
                bt.bossName:SetText(b.trash and L["Trash-Gegner"] or b.name)
                local bm = {}
                if b.level then bm[#bm + 1] = (L["Stufe %s"]):format(b.level) end
                if b.rare then bm[#bm + 1] = "|cffffd24a" .. L["selten"] .. "|r" end
                bm[#bm + 1] = (L["%d Items"]):format(#(b.loot or {}))
                local nu = 0
                for _, it in ipairs(b.loot or {}) do local pc = upPct(it[1]) if pc and pc > 0 then nu = nu + 1 end end
                if nu > 0 then bm[#bm + 1] = "|cff66db9e" .. (L["%d Upgrades fuer dich"]):format(nu) .. "|r" end
                bt.bossMeta:SetText(table.concat(bm, "  ·  "))
                local raw = d.data and d.data.bosses and d.data.bosses[S.boss]
                local npc = b.npc or (raw and raw.npc) or (ns.DungeonNpc and (ns.DungeonNpc[b.nameEN or ""] or ns.DungeonNpc[raw and raw.name or ""] or ns.DungeonNpc[b.name or ""]))
                -- Anzeige-ID zuerst (wie Deathroll), sonst Kreatur; laedt nichts -> Symbol statt falschem Modell
                local disp = b.disp or (raw and raw.disp) or (npc and ns.DungeonNpcDisplay and ns.DungeonNpcDisplay[npc])
                local m = bt.model
                local want = (b.trash or b.object) and nil or (disp and ("d" .. disp) or (npc and ("n" .. npc)))
                if want then
                    if m.want ~= want then
                        m.want = want
                        pcall(m.ClearModel, m)
                        local ok = disp and m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, disp)
                        if not ok and npc and m.SetCreature then pcall(m.SetCreature, m, npc) end
                        m:ResetView()
                        m:Show()
                        bt.noModel:Hide()
                        if animOn() then m.oasisFadedAt = nil K.FadeIn(m, 0) end
                        local function check(retry)
                            if m.want ~= want or not m.GetModelFileID then return end
                            local okm, id = pcall(m.GetModelFileID, m)
                            if okm and (not id or id == 0) then
                                if retry and npc and m.SetCreature then
                                    pcall(m.SetCreature, m, npc)
                                    C_Timer.After(0.8, function() check(false) end)
                                else
                                    m:Hide()
                                    bt.noModel.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                                    bt.noModel.text:SetText(L["Modell nicht geladen - Boss-Symbol statt falscher Figur"])
                                    bt.noModel:Show()
                                end
                            end
                        end
                        C_Timer.After(0.6, function() check(true) end)
                    else
                        pcall(m.SetFacing, m, m.facing)
                        pcall(m.SetCamDistanceScale, m, m.zoom)
                    end
                else
                    m.want = nil
                    m:Hide()
                    bt.noModel.text:SetText((b.trash or b.object) and "" or L["Kein 3D-Modell fuer diesen Boss"])
                    bt.noModel.icon:SetTexture(b.trash and "Interface\\Icons\\INV_Misc_Bag_10" or b.object and "Interface\\Icons\\INV_Box_01" or "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                    bt.noModel:Show()
                end
                local rows = {}
                for i, it in ipairs(b.loot or {}) do rows[#rows + 1] = { it = it, n = i, noDim = true, versus = true } end
                sortLoot(rows)
                bt.loot:SetData(rows)
                D.FillMoreUps(bt, bosses, bosses[S.boss] and S.boss or 1, #rows)
                if switched and animOn() then
                    local k = 0
                    for _, row in ipairs(bt.loot.rows) do
                        if row.item and row:IsShown() then
                            row.oasisFadedAt = nil
                            K.FadeIn(row, k * 0.045)
                            k = k + 1
                        end
                    end
                end
            else
                bt.bossName:SetText("")
                bt.bossMeta:SetText("")
                bt.loot:SetData({})
                bt.more.want = false
                bt.model:Hide()
                bt.noModel:Show()
            end
            local view = S.bossView or "loot"
            bt.more:SetShown(bt.more.want and view == "loot" or false)
            if bt.more:IsShown() and switched and animOn() then bt.more.oasisFadedAt = nil K.FadeIn(bt.more, 0.15) end
            if bt.view.value ~= view then bt.view:Select(view) end
            bt.loot:SetShown(view == "loot")
            bt.tac:SetShown(view == "tac")
            if view == "tac" then
                D.FillTactic(bt, d, b)
                if switched and animOn() then bt.tac.oasisFadedAt = nil K.FadeIn(bt.tac, 0) end
            end
        elseif S.tab == "loot" then
            local lt = dv.lootTab
            local rows, slots, seenSlot = {}, {}, {}
            for _, b in ipairs(bosses) do
                for _, it in ipairs(b.loot or {}) do
                    local info = itemInfo(it)
                    if info.slot ~= "" and not seenSlot[info.slot] then seenSlot[info.slot] = true slots[#slots + 1] = info.slot end
                    local ok = S.lootSearch == "" or info.name:lower():find(S.lootSearch, 1, true) or info.slot:lower():find(S.lootSearch, 1, true)
                    if ok and S.lootSlot and info.slot ~= S.lootSlot then ok = false end
                    if ok and S.lootKind and kindOf(info.id) ~= S.lootKind then ok = false end
                    if ok and S.lootUp then local pc = upPct(info.id) ok = pc ~= nil and pc > 0 end
                    if ok then rows[#rows + 1] = { it = it, boss = b.trash and L["Trash-Gegner"] or b.name } end
                end
            end
            table.sort(slots)
            lt.slots = slots
            sortLoot(rows)
            lt.up:SetOn(S.lootUp)
            lt.up:SetShown(upOn())
            lt.kind:Update()
            lt.slot:Update()
            lt.list.empty:SetText((S.lootUp or S.lootSlot or S.lootKind or S.lootSearch ~= "") and L["Nichts passt zu diesen Filtern."] or L["Keine Beute bekannt."])
            lt.list:SetData(rows)
        elseif S.tab == "quests" then
            local qt = dv.questTab
            local quests = D.Quests(d)
            local ids = {}
            for _, q in ipairs(quests) do ids[#ids + 1] = q.id end
            local holders = D.QuestHolders(ids)
            for _, q in ipairs(quests) do
                q.holders = holders[q.id] or {}
                q.state = D.QuestState(q.id, q.holders)
                local loc = D.QuestLocation(q)
                q.loc = loc
                q.whereShort = loc.start and loc.start.text or ""
            end
            local cnt = questOrder(quests)
            local parts = {}
            for _, k in ipairs({ "open", "log", "done" }) do
                local st = QUEST_STATE[k]
                parts[#parts + 1] = "|cff" .. st[2] .. L[st[1]] .. "|r |cffffffff" .. cnt[k] .. "|r"
            end
            qt.sum:SetText(#quests > 0 and table.concat(parts, "   ·   ") or "")
            qt.list:SetData(quests)
            local q
            for _, x in ipairs(quests) do if x.id == S.quest then q = x end end
            q = q or quests[1]
            local qd = qt.detail
            qd:SetShown(q ~= nil)
            if not q then return end
            S.quest = q.id
            qd.icon:SetTexture(q.state == "done" and "Interface\\RaidFrame\\ReadyCheck-Ready"
                or q.state == "log" and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
            qd.title:SetText(q.name)
            local meta = {}
            if q.level then meta[#meta + 1] = (L["Stufe %s"]):format(q.level) end
            if q.min then meta[#meta + 1] = (L["ab %s"]):format(q.min) end
            if q.faction and q.faction ~= "Both" then meta[#meta + 1] = q.faction == "Alliance" and L["Allianz"] or L["Horde"] end
            meta[#meta + 1] = q.state == "done" and ("|cff66db9e" .. L["schon erledigt"] .. "|r")
                or q.state == "log" and ("|cffffd24a" .. L["in deinem Questlog"] .. "|r") or L["noch nicht angenommen"]
            qd.meta:SetText(table.concat(meta, "  ·  "))

            local lines = {}
            local loc = q.loc
            lines[#lines + 1] = "|cffece6ff" .. L["Wo bekommst du sie?"] .. "|r"
            lines[#lines + 1] = loc.start and loc.start.long or ("|cff777777" .. L["unbekannt"] .. "|r")
            if loc.finish then
                lines[#lines + 1] = " "
                lines[#lines + 1] = "|cffece6ff" .. L["Abgabe"] .. "|r"
                lines[#lines + 1] = loc.finish.long
            end
            if loc.prereq and #loc.prereq > 0 then
                lines[#lines + 1] = " "
                lines[#lines + 1] = "|cffece6ff" .. L["Vorher erledigen"] .. "|r"
                for _, p in ipairs(loc.prereq) do
                    lines[#lines + 1] = (p.done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " or "|cff777777•|r ") .. p.name
                end
            end
            qd.text:SetText(table.concat(lines, "\n"))
            qd.textH = qd.text.GetStringHeight and math.ceil((qd.text:GetStringHeight() or 0) + 4) or nil
            local others = {}
            for _, n in ipairs(q.holders) do if not ns.isMe(n) then others[#others + 1] = n end end
            local inGroup = IsInGroup and IsInGroup()
            qd.share:SetEnabledState(q.state == "log" and inGroup and true or false)

            local rew = q.rewards or (d.data and (function()
                for _, x in ipairs(d.data.quests or {}) do if x.id == q.id then return x.rewards or x.rewardItems end end
            end)()) or {}
            local n = 0
            for i, b in ipairs(qd.rewards) do
                local it = rew[i]
                local id = type(it) == "table" and it[1] or it
                if id then
                    n = n + 1
                    local info = itemInfo({ id })
                    b.id = id
                    b.icon:SetTexture(info.icon)
                    local cc = info.color
                    b.border:SetColorTexture(tonumber(cc:sub(3, 4), 16) / 255, tonumber(cc:sub(5, 6), 16) / 255, tonumber(cc:sub(7, 8), 16) / 255, 0.9)
                    b:Show()
                else
                    b.id = nil
                    b:Hide()
                end
            end
            qd.rewLabel:SetShown(n > 0)
            -- Gildenmitglieder mit der Quest rechts neben den Belohnungen
            local wx = 14 + (n > 0 and (n * 36 + 18) or 0)
            local room = math.max(0, math.floor(((qd:GetWidth() or 440) - wx - 40) / 28))
            qd.whoLabel:ClearAllPoints()
            qd.whoLabel:SetPoint("BOTTOMLEFT", wx, 86)
            qd.whoLabel:SetShown(#others > 0 and room > 0)
            local shownW = 0
            for i, b in ipairs(qd.who) do
                local nm = others[i]
                if nm and i <= room then
                    b.name = nm
                    b.disc:Set(classOf(nm), nm)
                    b:ClearAllPoints()
                    b:SetPoint("BOTTOMLEFT", wx + (i - 1) * 28, 52)
                    b:Show()
                    shownW = i
                else
                    b.name = nil
                    b:Hide()
                end
            end
            qd.whoMore:ClearAllPoints()
            qd.whoMore:SetPoint("BOTTOMLEFT", wx + shownW * 28 + 4, 60)
            qd.whoMore:SetText(#others > shownW and shownW > 0 and ("+" .. (#others - shownW)) or "")
            -- ohne Belohnungen und ohne Gildenmitglieder braucht der Fuss nur die Knopfzeile
            qd.bottomPad = (n > 0 or shownW > 0) and 110 or 50
            qd:Layout()

            local s, f = loc.start, loc.finish
            -- Karte daneben zeichnen
            local mh = qd.mapHost
            local function drawQuestMap()
                local mid = (s and s.target and s.target.mapID) or (s and s.zoneMap)
                local tg1 = s and s.target
                local focus = { zoom = 1.25 }
                if tg1 and tg1.mapID == mid and tg1.x then focus.x, focus.y = tg1.x, tg1.y end
                local ok = mid and drawMap(mh, mid, focus)
                for _, pin in ipairs(mh.pins) do pin:Hide() end
                mh.none:SetShown(not ok)
                local info = ok and C_Map.GetMapInfo and C_Map.GetMapInfo(mid)
                mh.cap:SetText(info and K.Upper(info.name or "") or "")
                if not ok or not mh.mapRect then return end
                local r = mh.mapRect
                for i, spot in ipairs({ s, f }) do
                    local tg = spot and spot.target
                    if tg and tg.mapID == mid and tg.x then
                        local pin = mh.pins[i]
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", mh, "TOPLEFT", r.x + tg.x * r.w, -(r.y + tg.y * r.h))
                        pin.target = tg
                        pin.tip = { (i == 1 and L["Quest-Start"] or L["Abgabe"]) .. ": " .. (tg.label or ""), tg.sub or "", "|cff888888" .. L["Klick: als Ziel auf der Karte"] .. "|r" }
                        pin:Show()
                    end
                end
            end
            drawQuestMap()
            if mh:GetWidth() < 50 then C_Timer.After(0, drawQuestMap) end
            qd.map:SetEnabledState(s ~= nil and (s.target ~= nil or s.zoneMap ~= nil))
            qd.map:SetLabel((s and s.target) and L["Auf Karte zeigen"] or L["Gebiet auf Karte"])
            qd.map:SetScript("OnClick", function()
                if not ns.Map or not s then return end
                if s.target then ns.Map.SetTarget(s.target) elseif s.zoneMap then ns.Map.ShowOnWorldMap(s.zoneMap) end
            end)
            qd.turnin:SetShown(f ~= nil and f.target ~= nil)
            qd.turnin:SetScript("OnClick", function() if f and f.target and ns.Map then ns.Map.SetTarget(f.target) end end)
            qd.clear:SetShown(ns.Map and ns.Map.target ~= nil)
        else
            local gt = dv.guildTab
            local wanted, got, range = guildData(d)
            gt.range = range
            pcall(gt.join.Update, gt.join)
            local now, week = ns.now(), 0
            for _, x in ipairs(got) do if (x.ts or 0) >= now - 7 * 86400 then week = week + 1 end end
            gt.stats.on:Set(#range)
            gt.stats.loot:Set(week)
            gt.stats.want:Set(#wanted)
            gt.invite:SetEnabledState(#range > 0)
            gt.emptyBoth = #got == 0 and #wanted == 0
            gt:Layout()
            gt.on.count:SetText(#range > 0 and tostring(#range) or "")
            gt.on.list:SetData(range)
            gt.on.empty:SetShown(#range == 0)
            if #range == 0 then
                gt.on.empty:Set(L["Gerade ist niemand aus der Gilde im Stufenbereich online."], L["Gruppe suchen"], function() dv.lfg:Click() end)
            end
            local shownGot = {}
            for i = 1, math.min(20, #got) do shownGot[i] = got[i] end
            gt.loot.count:SetText(#got > 0 and tostring(#got) or "")
            gt.loot.list:SetData(shownGot)
            gt.loot.empty:SetShown(#got == 0)
            if #got == 0 then
                gt.loot.empty:Set(L["Noch keine Beute aus diesem Dungeon im Gilden-Log."], L["Beute ansehen"], function()
                    S.tab, S.tabFade = "loot", true ns.RefreshPage("dungeons") end)
            end
            gt.want.count:SetText(#wanted > 0 and tostring(#wanted) or "")
            gt.want.list:SetData(wanted)
            gt.want.empty:SetShown(#wanted == 0)
            if #wanted == 0 then
                gt.want.empty:Set(L["Die Gilde sucht gerade nichts aus diesem Dungeon."], L["Auf Wunschliste setzen"], function()
                    ns.print(L["Rechtsklick auf einen Gegenstand: Auf meine Wunschliste"])
                    S.tab, S.tabFade = "loot", true ns.RefreshPage("dungeons") end)
            end
        end
    end,
})

-- Itemnamen kommen verzoegert: Seite neu zeichnen, gebuendelt
local pending
ns.On("GET_ITEM_INFO_RECEIVED", function()
    if pending then return end
    pending = true
    ns.After(0.4, function() pending = nil ns.RefreshPage("dungeons") end)
end)

-- Termin/Gruppensuche koennen direkt einen Dungeon oeffnen
function D.ShowDungeon(key)
    S.view, S.dungeon, S.tab, S.boss = "dungeon", key, "bosses", 1
    ns.ShowPage("dungeons")
end

------------------------------------------------------------------------
-- Im Dungeon: Oasis-Dungeonkarte direkt IN Blizzards Weltkarte (eigene Ebene ueber dem Kartenbereich).
-- Blizzards Karte selbst wird nicht veraendert; Knopf oben rechts schaltet zur normalen Weltkarte.
------------------------------------------------------------------------
local wmOverlay, wmUser
local function curDungeon()
    local inInst, kind = IsInInstance()
    local key
    if inInst and (kind == "party" or kind == "raid") then
        key = D.KeyByZone and D.KeyByZone(ns.safe(GetRealZoneText()) or "")
        if not key and D.KeyByZone and GetInstanceInfo then
            local ok, name = pcall(GetInstanceInfo)
            if ok then key = D.KeyByZone(ns.safe(name) or "") end
        end
    elseif not inInst then
        -- vor dem Dungeon (z.B. Hoehle vor den Hoehlen des Wehklagens): Unterzone heisst wie der Dungeon
        for _, z in ipairs({ ns.safe(GetSubZoneText and GetSubZoneText()), ns.safe(GetMinimapZoneText and GetMinimapZoneText()) }) do
            if not key and z and z ~= "" and D.KeyByZone then key = D.KeyByZone(z) end
        end
    else
        return
    end
    if not key then return end
    for _, x in ipairs(D.List()) do
        if x.key == key then
            local md = ns.DungeonMapsData and ns.DungeonMapsData[x.dbKey or x.key]
            if md and (md.folder or md.bundled) then return x, md end
        end
    end
end
local function buildOverlay()
    local host = WorldMapFrame.ScrollContainer or (WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()) or WorldMapFrame
    local o = CreateFrame("Frame", "OasisWorldMapDungeon", host)
    o:SetAllPoints(host)
    o:SetFrameLevel(host:GetFrameLevel() + 200)
    o:EnableMouse(true)
    K.Fill(o, { 0.02, 0.02, 0.025, 1 })
    o.canvas = CreateFrame("Frame", nil, o)
    o.canvas:SetPoint("TOPLEFT", 10, -40)
    o.canvas:SetPoint("BOTTOMRIGHT", -10, 10)
    o.title = K.Title(o, 15, C.text)
    o.title:SetPoint("TOPLEFT", 14, -12)
    o.floors = {}
    o.back = K.Button(o, L["Weltkarte"], 100, 22, "ghost", function() wmUser = "world" o:Hide() if o.toggle then o.toggle:Show() end end)
    o.back:SetPoint("TOPRIGHT", -12, -9)
    -- kleiner Knopf, um von der Weltkarte zurueck zur Dungeonkarte zu kommen
    local t
    t = K.Button(host, L["Dungeonkarte"], 110, 22, "primary", function() wmUser = nil o:Show() t:Hide() end)
    t:SetPoint("TOPRIGHT", host, "TOPRIGHT", -12, -9)
    t:SetFrameLevel(host:GetFrameLevel() + 210)
    t:Hide()
    o.toggle = t
    o:SetScript("OnSizeChanged", function(self) if self.d then self:Draw() end end)
    -- Position festlegen: Klick auf die Stelle, an der du gerade stehst (2x an verschiedenen Orten genuegt)
    o.cal = K.Button(o, L["Hier bin ich ..."], 120, 22, "ghost", function()
        o.calMode = not o.calMode
        o.cal:SetLabel(o.calMode and L["Jetzt auf deinen Ort klicken"] or L["Hier bin ich ..."])
    end)
    o.cal:SetWidth(190)
    o.cal:SetPoint("RIGHT", o.back, "LEFT", -6, 0)
    o.cal:Hide()   -- Einmessen per Klick entfernt (nur noch automatisch beim Pluendern von Bossen)
    o.cal:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Position auf der Karte"], L["Die Dungeonkarten haben keine Koordinaten. Klick hier, dann auf die Stelle der Karte, an der du gerade stehst. An zwei weit entfernten Stellen gemacht, zeigt Oasis dich und deine Gruppe auf der Karte - fuer die ganze Gilde."] }) end)
    o.cal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    o.canvas:EnableMouse(true)
    o.canvas:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and ns.InstancePos then ns.InstancePos.ClickSet(self, o.calKey) return end
        if not o.calMode or btn ~= "LeftButton" then return end
        o.calMode = false
        o.cal:SetLabel(L["Hier bin ich ..."])
        local r = self.lrect
        if not r then return end
        local cx, cy = GetCursorPosition()
        local sc = self:GetEffectiveScale()
        local px = (cx / sc - self:GetLeft() - r[1]) / r[3]
        local py = (self:GetTop() - cy / sc - r[2]) / r[4]
        if ns.DungeonPos then ns.DungeonPos.AddSample(o.calKey, px, py) end
    end)
    o.dots = {}
    local acc = 0
    o:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        if acc < 0.2 then return end
        acc = 0
        if ns.DungeonPos then pcall(ns.DungeonPos.DrawDots, self) end
    end)
    function o:Draw()
        local d, md = self.d, self.md
        if not d then return end
        self.title:SetText(d.name or "")
        self.canvas.curDungeon = d
        self.canvas.worldMapOverlay = true
        local fl = self.floor or (md.floors and md.floors[1]) or 1
        drawLegacyMap(self.canvas, md, fl)
        self.calKey = (d.dbKey or d.key) .. ":" .. tostring(fl)
        -- Ebenen-Knoepfe
        for _, b in ipairs(self.floors) do b:Hide() end
        local list = md.floors or {}
        if #list > 1 then
            local x = 0
            for i, f in ipairs(list) do
                local b = self.floors[i]
                if not b then
                    b = K.Button(self, "", 90, 20, "ghost")
                    self.floors[i] = b
                end
                local name = (md.floorNames and md.floorNames[i]) or (L["Ebene %d"]):format(i)
                b:SetLabel(name)
                b:SetWidth(math.max(70, (b.label:GetStringWidth() or 60) + 18))
                b:ClearAllPoints()
                b:SetPoint("LEFT", self.title, "RIGHT", 16 + x, 0)
                x = x + b:GetWidth() + 4
                b:SetScript("OnClick", function() self.floor = f self:Draw() end)
                K.SetBorderColor(b, f == fl and C.accent or C.line)
                b:Show()
            end
        end
    end
    wmOverlay = o
    return o
end
local function onWorldMapShow()
    if ns.db and ns.db.settings.dungeonMapOnM == false then return end
    -- Dungeonkarte auf der Weltkarte nur IN einer Instanz (draussen, z.B. Ruinen von Lordaeron: Blizzard-Karte)
    local okI, inInst, kind = pcall(IsInInstance)
    local inside = okI and ns.safe(inInst) and (kind == "party" or kind == "raid")
    local d, md
    if inside then d, md = curDungeon() end
    if not d then
        if wmOverlay then wmOverlay:Hide() wmOverlay.toggle:Hide() end
        return
    end
    local o = wmOverlay or buildOverlay()
    if not o.d or o.d.key ~= d.key then o.floor = nil end
    o.d, o.md = d, md
    o.openMapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if wmUser == "world" then o:Hide() o.toggle:Show() return end
    o:Show()
    o.toggle:Hide()
    C_Timer.After(0, function() o:Draw() end)
end
-- Weltkarte zeigt eine andere Karte (z.B. Klick auf eine Quest -> Questgebiet): Dungeonkarte weg
local function onMapChanged()
    if not (wmOverlay and wmOverlay:IsShown()) then return end
    local okI, inInst = pcall(IsInInstance)
    if not (okI and ns.safe(inInst)) then wmOverlay:Hide() wmOverlay.toggle:Hide() return end
    local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    -- Forever kann als Spielerkarte das Aussengebiet melden. Nur echte Navigation blendet die Instanz aus.
    if id and wmOverlay.openMapID and id ~= wmOverlay.openMapID then
        wmOverlay:Hide()
        wmOverlay.toggle:Show()
    end
end
local worldMapHooked
local function hookWorldMap()
    if worldMapHooked then return end
    if WorldMapFrame and WorldMapFrame.HookScript then
        worldMapHooked = true
        WorldMapFrame:HookScript("OnShow", function()
            -- Blizzard initialisiert die Karten-ID erst beim Oeffnen; danach unsere Ebene anzeigen.
            C_Timer.After(0, function() if WorldMapFrame:IsShown() then pcall(onWorldMapShow) end end)
        end)
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() pcall(onMapChanged) end) end
        if WorldMapFrame:IsShown() then pcall(onWorldMapShow) end
    end
end
ns.Listen("LOGIN", hookWorldMap)
ns.On("ADDON_LOADED", function(addon) if addon == "Blizzard_WorldMap" then hookWorldMap() end end)
-- neuer Dungeon: wieder mit der Dungeonkarte anfangen
ns.On("PLAYER_ENTERING_WORLD", function() wmUser = nil end)

------------------------------------------------------------------------
-- Positionen auf der Dungeonkarte
-- Classic liefert in Instanzen keine Kartenposition, wohl aber Weltkoordinaten (UnitPosition, nur fuer
-- einen selbst). Spieler legen 2+ Bezugspunkte fest ("Hier bin ich" + Klick) -> daraus wird die Umrechnung
-- Welt -> Karte berechnet (geteilt mit der Gilde, Store "mapcal"). Die Gruppe schickt sich die eigene
-- Weltposition alle 2 s per Addon-Nachricht (nur in Instanzen, nur an die Gruppe).
------------------------------------------------------------------------
local DP = {}
ns.DungeonPos = DP
DP.CurDungeon = curDungeon
local function myWorld()
    if not UnitPosition then return nil end
    local ok, y, x, _, inst = pcall(UnitPosition, "player")
    y, x = ns.safe(y), ns.safe(x)
    if not ok or not y or not x then return nil end
    return x, y, ns.safe(inst)
end
function DP.AddSample(key, px, py)
    if not key or not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    local wx, wy = myWorld()
    if not wx then ns.print(L["Hier liefert das Spiel keine Position."]) return end
    local rec = Store.Get("mapcal", "cal:" .. key)
    local samples = {}
    if rec and not rec.del and type(rec.s) == "string" then
        for a, b, c, dd in rec.s:gmatch("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+);") do
            samples[#samples + 1] = { tonumber(a), tonumber(b), tonumber(c), tonumber(dd) }
        end
    end
    samples[#samples + 1] = { wx, wy, px, py }
    while #samples > 8 do table.remove(samples, 1) end
    local parts = {}
    for _, sm in ipairs(samples) do parts[#parts + 1] = ("%.1f,%.1f,%.4f,%.4f;"):format(sm[1], sm[2], sm[3], sm[4]) end
    Store.Put("mapcal", { id = "cal:" .. key, s = table.concat(parts) })
    DP.cache = nil
    ns.print(#samples >= 2 and L["Bezugspunkt gespeichert - deine Position wird jetzt angezeigt."]
        or L["Bezugspunkt gespeichert - noch einen an einer weit entfernten Stelle setzen."])
end
-- lineare Umrechnung je Achse (kleinste Quadrate): Karte = a * Welt + b; pruefen, welche Weltachse passt
local function fit(xs, ys)
    local n, sx, sy, sxx, sxy = #xs, 0, 0, 0, 0
    for i = 1, n do sx, sy, sxx, sxy = sx + xs[i], sy + ys[i], sxx + xs[i] * xs[i], sxy + xs[i] * ys[i] end
    local den = n * sxx - sx * sx
    if math.abs(den) < 1e-6 then return nil end
    local a = (n * sxy - sx * sy) / den
    return a, (sy - a * sx) / n
end
function DP.Transform(key)
    DP.cache = DP.cache or {}
    if DP.cache[key] ~= nil then return DP.cache[key] or nil end
    local rec = Store.Get("mapcal", "cal:" .. (key or ""))
    local res = false
    if rec and not rec.del and type(rec.s) == "string" then
        local wx, wy, px, py = {}, {}, {}, {}
        for a, b, c, dd in rec.s:gmatch("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+);") do
            wx[#wx + 1], wy[#wy + 1], px[#px + 1], py[#py + 1] = tonumber(a), tonumber(b), tonumber(c), tonumber(dd)
        end
        if #wx >= 2 then
            -- WoW: Karten-x haengt an der Welt-y-Achse und umgekehrt (meist), beides probieren und das Bessere nehmen
            local ax, bx = fit(wy, px)
            local ay, by = fit(wx, py)
            if ax and ay then res = { ax = ax, bx = bx, ay = ay, by = by } end
        end
    end
    DP.cache[key] = res
    return res or nil
end
ns.Listen("STORE", function(coll) if coll == "mapcal" then DP.cache = nil end end)
-- 0.6.304: Mitkommen-Liste live nachziehen, wenn sich jemand ein- oder austraegt
ns.Listen("STORE", function(coll) if coll == "dgjoin" then ns.Debounce("dgjoin", 0.3, refreshSoon) end end)
local function toMap(tr, wx, wy, inst)
    if tr.ui then
        -- direkt ueber Blizzards Kartenzuordnung (uiMap der Dungeonkarte); Achsenreihenfolge einmal ermittelt
        local v = tr.swap and CreateVector2D(wx, wy) or CreateVector2D(wy, wx)
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst or tr.inst, v, tr.ui)
        if ok and pos then
            local ux, uy = pos:GetXY()
            -- Blizzards Dungeonkarte und das Oasis-Kartenbild sind nicht genau gleich geschnitten:
            -- Umrechnung aus den Bossen, die auf beiden Karten stehen
            if tr.fx then return tr.fx * ux + tr.gx, tr.fy * uy + tr.gy end
            return ux, uy
        end
        return -1, -1
    end
    return tr.ax * wy + tr.bx, tr.ay * wx + tr.by
end
-- Automatisch ohne Einmessen: Blizzards Dungeon-Karten-IDs (uiMap) aus den Boss-Daten probieren.
-- Klappt, wenn der Client die Zuordnung Welt -> Karte kennt (auch ohne Kartenbild).
local directCache = {}
function DP.Direct(dkey, floor, md0)
    local ck = tostring(dkey) .. ":" .. tostring(floor)
    if directCache[ck] ~= nil then return directCache[ck] or nil end
    local res = false
    local list = ns.BossPos and ns.BossPos[dkey]
    if list and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        -- Ebenen der Karte = verschiedene uiMap-IDs in der Reihenfolge ihres ersten Auftretens
        local maps, seen = {}, {}
        for _, b in ipairs(list) do if b.map and not seen[b.map] then seen[b.map] = true maps[#maps + 1] = b.map end end
        table.sort(maps)
        local ui = maps[tonumber(floor) or 1] or maps[1]
        local wx, wy, inst = myWorld()
        if ui and wx and inst then
            for _, swap in ipairs({ false, true }) do
                local v = swap and CreateVector2D(wx, wy) or CreateVector2D(wy, wx)
                local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, v, ui)
                if ok and pos then
                    local x, y = pos:GetXY()
                    if x and x > -0.2 and x < 1.2 and y > -0.2 and y < 1.2 then res = { ui = ui, swap = swap, inst = inst } break end
                end
            end
        end
        -- Bosse auf beiden Karten -> Umrechnung Blizzard-Karte -> Oasis-Bild (je Achse)
        if res and md0 and md0.pins then
            local function norm(t) return (tostring(t or ""):lower():gsub("%s*%b()", ""):gsub("[^%w]", "")) end
            local ux, px, uy, py = {}, {}, {}, {}
            for _, b in ipairs(list) do
                if b.map == res.ui then
                    for _, pin in ipairs(md0.pins) do
                        if norm(pin[1]) == norm(b.boss) and tostring(pin[4] or 1) == tostring(floor or 1) then
                            ux[#ux + 1], px[#px + 1] = b.x, (pin[2] or 0) / 100
                            uy[#uy + 1], py[#py + 1] = b.y, (pin[3] or 0) / 100
                        end
                    end
                end
            end
            if #ux >= 2 then
                local a1, b1 = fit(ux, px)
                local a2, b2 = fit(uy, py)
                if a1 and a2 then res.fx, res.gx, res.fy, res.gy = a1, b1, a2, b2 end
            end
        end
    end
    -- nur Erfolg dauerhaft merken (ohne Position wird spaeter erneut probiert)
    if res then directCache[ck] = res end
    return res or nil
end

-- direkte Kartenposition (nur wenn das Spiel Weltkoordinaten liefert), fuer InstancePos
function DP.MyMapXY(dkey, floor)
    local wx, wy, inst = myWorld()
    if not wx then return nil end
    local md = ns.DungeonMapsData and ns.DungeonMapsData[dkey]
    local tr = DP.Direct(dkey, floor, md) or DP.Transform(dkey .. ":" .. tostring(floor or 1))
    if not tr then return nil end
    return toMap(tr, wx, wy, inst)
end

-- Gruppe: eigene Weltposition verteilen (nur in Instanzen)
DP.party = {}
local sendAcc = 0
local sender = CreateFrame("Frame")
sender:SetScript("OnUpdate", function(_, el)
    sendAcc = sendAcc + el
    if sendAcc < 2 then return end
    sendAcc = 0
    -- in Dungeons und vor ihnen (Unterzone mit Dungeonkarte, z.B. Ruinen von Lordaeron)
    if not IsInGroup() or not curDungeon() or ns.db.settings.shareInstPos == false then return end
    local wx, wy, inst = myWorld()
    if not wx or not ns.Comm then return end
    ns.Comm.SendEx({ ch = IsInRaid() and "RAID" or "PARTY" }, "DPOS", ("%.1f"):format(wx), ("%.1f"):format(wy), tostring(inst or 0))
end)
if ns.Comm then
    ns.Comm.On("DPOS", function(sender, channel, x, y, inst)
        -- nur ueber den Gruppenkanal, endliche Zahlen
        if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
        x, y, inst = SEC.Num(x, -1e6, 1e6), SEC.Num(y, -1e6, 1e6), SEC.Num(inst, 0, 1e7, true)
        if not x or not y then return end
        DP.party[sender] = { x = x, y = y, inst = inst, t = GetTime() }
    end)
end

function DP.DrawDots(o)
    for _, dt in ipairs(o.dots) do dt:Hide() end
    local tr
    if o.d then tr = DP.Direct(o.d.dbKey or o.d.key, o.floor or (o.md and o.md.floors and o.md.floors[1]) or 1, o.md) end
    tr = tr or (o.calKey and DP.Transform(o.calKey))
    local r = o.canvas.lrect
    -- ohne Weltposition: Schaetzung aus InstancePos (Koppelnavigation/Boss-Anker/Rechtsklick)
    if (not tr or not myWorld()) and ns.InstancePos then
        ns.InstancePos.DrawOn(o.canvas, o, o.calKey, true)
        return
    end
    if ns.InstancePos then ns.InstancePos.HideOn(o) end
    if not tr or not r then return end
    local n = 0
    local function dot(px, py, cr, cg, cb, label, me)
        if px < -0.02 or px > 1.02 or py < -0.02 or py > 1.02 then return end
        n = n + 1
        local d = o.dots[n]
        if not d then
            d = CreateFrame("Frame", nil, o.canvas)
            d:SetSize(16, 16)
            d:SetFrameLevel(o.canvas:GetFrameLevel() + 20)
            d.ring = d:CreateTexture(nil, "ARTWORK")
            d.ring:SetTexture(ns.MEDIA .. "dot")
            d.ring:SetAllPoints()
            d.ring:SetVertexColor(0, 0, 0, 1)
            d.c = d:CreateTexture(nil, "OVERLAY")
            d.c:SetTexture(ns.MEDIA .. "dot")
            d.c:SetPoint("CENTER")
            d.c:SetSize(11, 11)
            d.lbl = K.Text(d, 10, C.text, "CENTER")
            d.lbl:SetPoint("TOP", d, "BOTTOM", 0, -1)
            o.dots[n] = d
        end
        d:SetSize(me and 20 or 16, me and 20 or 16)
        d.c:SetSize(me and 14 or 11, me and 14 or 11)
        d.c:SetVertexColor(cr, cg, cb)
        d.lbl:SetText(label or "")
        d:ClearAllPoints()
        d:SetPoint("CENTER", o.canvas, "TOPLEFT", r[1] + px * r[3], -(r[2] + py * r[4]))
        d:Show()
    end
    local wx, wy = myWorld()
    if wx then
        local px, py = toMap(tr, wx, wy)
        local _, cls = UnitClass("player")
        local cr, cg, cb = ns.classColor(cls)
        dot(px, py, cr or 1, cg or 1, cb or 1, L["Du"], true)
    end
    local now = GetTime()
    for name, p in pairs(DP.party) do
        local sh = ns.short(name)
        if now - p.t < 8 and p.x and (UnitInParty(sh) or UnitInRaid(sh)) then
            local px, py = toMap(tr, p.x, p.y, p.inst)
            local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
            local cr, cg, cb = ns.classColor(m and m.class or select(2, UnitClass(sh)))
            dot(px, py, cr or 1, cg or 1, cb or 1, sh)
        end
    end
end

-- Automatisch einmessen: beim Pluendern (oder Tod) eines Bosses steht man direkt an ihm -> Boss-Position
-- auf der Karte (aus den Kartendaten) + eigene Weltposition = Bezugspunkt. Nach 2 Bossen stimmt die Karte.
local function npcOf(guid)
    guid = ns.safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local autoDone = {}
local function autoSample(npc, near)
    if not npc then return end
    local d, md = curDungeon()
    if not d or not md or not md.pins then return end
    local boss
    for _, b in ipairs(D.Bosses(d) or {}) do
        local bn = b.npc or (ns.DungeonNpc and ns.DungeonNpc[b.name or ""])
        if bn == npc then boss = b break end
    end
    if not boss then return end
    local function norm(s) return (tostring(s or ""):lower():gsub("%s*%b()", ""):gsub("[^%w]", "")) end
    for _, pin in ipairs(md.pins) do
        if norm(pin[1]) == norm(boss.name) then
            local key = (d.dbKey or d.key) .. ":" .. tostring(pin[4] or 1)
            local id = key .. ":" .. npc
            if autoDone[id] and not near then return end
            autoDone[id] = true
            DP.AddSample(key, (pin[2] or 0) / 100, (pin[3] or 0) / 100)
            return
        end
    end
end
-- Pluendern: man steht am Boss (genau)
ns.On("LOOT_OPENED", function()
    if UnitExists("target") and UnitIsDead("target") then pcall(autoSample, npcOf(UnitGUID("target")), true) end
end)
-- (Kampflog absichtlich nicht: ist im Beta-Client fuer Addons eingeschraenkt)

-- Test: was liefert das Spiel hier an Positionsdaten? (/oasis kartentest oder Knopf "Test" auf der Dungeonkarte)
function DP.Test()
    local function v(x) if x == nil then return "nil" end if ns.safe(x) == nil then return "|cffff5a4a(geheim)|r" end return tostring(x) end
    ns.print("|cffe8b44a" .. L["Karten-Test"] .. "|r")
    local inInst, kind = IsInInstance()
    local name, _, _, _, _, _, _, instID = GetInstanceInfo()
    ns.print("  Instanz: " .. v(inInst) .. " / " .. v(kind) .. "  " .. v(name) .. "  ID " .. v(instID))
    local ok, y, x, z, inst = pcall(UnitPosition, "player")
    ns.print("  UnitPosition: " .. (ok and (v(y) .. ", " .. v(x) .. "  inst " .. v(inst)) or ("|cffff5a4aFehler|r")))
    local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    ns.print("  Karte (GetBestMapForUnit): " .. v(best) .. ((best and ns.safe(best) and C_Map.GetMapInfo(best)) and ("  " .. (C_Map.GetMapInfo(best).name or "")) or ""))
    if best and ns.safe(best) then
        local okp, pos = pcall(C_Map.GetPlayerMapPosition, best, "player")
        local px, py
        if okp and pos then px, py = pos:GetXY() end
        ns.print("  Position auf dieser Karte: " .. v(px) .. ", " .. v(py))
    end
    local d = curDungeon()
    ns.print("  Oasis-Dungeon: " .. (d and (d.name .. " (" .. (d.dbKey or d.key) .. ")") or "-"))
    if d and ns.BossPos and ns.BossPos[d.dbKey or d.key] then
        local seen = {}
        for _, b in ipairs(ns.BossPos[d.dbKey or d.key]) do
            if b.map and not seen[b.map] then
                seen[b.map] = true
                local wx, wy, wi = myWorld()
                local r = {}
                for _, sw in ipairs({ false, true }) do
                    local okm, _, pos = false, nil, nil
                    if wx and CreateVector2D and C_Map.GetMapPosFromWorldPos then
                        okm, _, pos = pcall(C_Map.GetMapPosFromWorldPos, wi or instID, sw and CreateVector2D(wx, wy) or CreateVector2D(wy, wx), b.map)
                    end
                    local px, py
                    if okm and pos then px, py = pos:GetXY() end
                    r[#r + 1] = (sw and "B: " or "A: ") .. v(px) .. ", " .. v(py)
                end
                ns.print("  uiMap " .. b.map .. ": " .. table.concat(r, "   "))
            end
        end
    end
    local n = 0
    for _, p in pairs(DP.party) do if GetTime() - p.t < 10 then n = n + 1 end end
    ns.print("  Gruppe sendet Positionen: " .. n)
end
ns.slash.kartentest = function() DP.Test() end

------------------------------------------------------------------------
-- Bereichs-Einstellungen "Dungeons" (inkl. neuem Schalter "Upgrades in der Beute hervorheben").
-- Settings.lua registriert den Bereich schon; ein zweiter Aufruf ersetzt ihn -> hier vollstaendig
-- (gleicher Inhalt wie dort + neuer Schalter), registriert nach dem Laden aller Dateien.
------------------------------------------------------------------------
local function dgSettings(det, y)
    local s = ns.db.settings
    for _, k in ipairs({ "dgForYou", "dgDimUnfit", "dgMarkers", "dgPreload", "dgUpgradeGlow" }) do
        if s[k] == nil then s[k] = true end
    end
    det.t = det.t or {}
    local function refreshDg() resetUp() ns.RefreshPage("dungeons") end
    local function tg(label, key, desc, onChange)
        local t = K.Toggle(det, L[label], function() return ns.db.settings[key] ~= false end,
            function(v) ns.db.settings[key] = v and true or false if onChange then onChange() end end, desc and L[desc] or nil)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        det.t[#det.t + 1] = t
        y = y - 32
    end
    local lbl = K.Text(det, 12, C.muted)
    lbl:SetPoint("TOPLEFT", 14, y - 6)
    lbl:SetText(L["Start-Filter"])
    det.dgFilter = K.Segments(det, {
        { key = "auto", text = L["Automatisch"] },
        { key = "mine", text = L["Fuer mich"] },
        { key = "open", text = L["Alle offenen"] },
        { key = "all", text = L["Alle"] },
    }, function(k)
        ns.db.settings.dgFilter = (k ~= "auto") and k or nil
        if D.ResetFilter then D.ResetFilter() end
    end)
    det.dgFilter:SetPoint("TOPLEFT", 184, y)
    det.dgFilter:Select(s.dgFilter or "auto")
    det.refreshers = det.refreshers or {}
    table.insert(det.refreshers, function() det.dgFilter:Select(ns.db.settings.dgFilter or "auto") end)
    y = y - 30
    local n1 = K.Text(det, 11, C.dim)
    n1:SetPoint("TOPLEFT", 14, y)
    n1:SetWidth(600)
    n1:SetText(L["Automatisch: passende Dungeons fuer dein Level, sonst alle offenen."])
    y = y - 34
    local h = K.Text(det, 12, C.muted)
    h:SetPoint("TOPLEFT", 14, y)
    h:SetText("|cffe8b44a" .. L["Beute-Liste"] .. "|r")
    y = y - 28
    tg("Upgrades in der Beute hervorheben", "dgUpgradeGlow", "Gegenstaende, die besser sind als deine angelegte Ausruestung, leuchten gruen (mit +%) - auch als Zaehler auf den Dungeon-Karten", refreshDg)
    tg("Passende Beute als fuer dich markieren", "dgForYou", "Gruener Hinweis bei Gegenstaenden mit Werten fuer deine Klasse", refreshDg)
    tg("Unpassende Beute abdunkeln", "dgDimUnfit", "Ruestung und Waffen, die deine Klasse nicht tragen kann, werden blasser", refreshDg)
    tg("Gesucht, Gildenbank und Besitz anzeigen", "dgMarkers", "Zusatz unter jedem Gegenstand: wer ihn sucht, wie viele in der Gildenbank liegen, ob du ihn hast", refreshDg)
    tg("Beute im Hintergrund vorladen", "dgPreload", "Nach dem Einloggen werden alle Dungeon-Beutelisten nach und nach gelesen (fuer Tooltips) - wirkt ab dem naechsten Login")
    return y - 10
end
ns.Listen("LOGIN", function()
    if ns.AddPageSettings then ns.AddPageSettings("dungeons", dgSettings) end
end)
end)

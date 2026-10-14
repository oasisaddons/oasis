-- Oasis Modul 7: Gildenkarte (Punkte auf der Weltkarte) + Live-Radar
local ADDON, ns = ...
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
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

local Map = {}
ns.Map = Map
-- [name] = { mapID, x, y, t }. Gesendet wird unter "Vorname-Realm", die Gildenliste (Forever) fuehrt
-- "Vorname Nachname-Realm" -> Nachschlagen klappt unter beiden Namen
Map.pos = setmetatable({}, { __index = function(t, k)
    local a = ns.Radar and ns.Radar.AliasOf and ns.Radar.AliasOf(k)
    if a and a ~= k then return rawget(t, a) end
end })
local EXPIRE = 150

------------------------------------------------------------------------
-- Eigene Position senden
------------------------------------------------------------------------
local lastKey, lastTime = nil, 0
-- Layer: steckt in der Kennung von NPCs (Creature-0-Server-Instanz-ZONE-...); wird beim Anvisieren gelernt
Map.myLayer = nil
local function learnLayer(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = ns.safe(UnitGUID(unit))
    if not guid then return end
    local typ, _, _, _, zone = strsplit("-", guid)
    if (typ == "Creature" or typ == "Vehicle") and tonumber(zone) and tonumber(zone) > 0 then
        if Map.myLayer ~= zone then Map.myLayer = zone lastKey = nil Map.dirty = true end
    end
end
ns.On("PLAYER_TARGET_CHANGED", function() pcall(learnLayer, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() pcall(learnLayer, "mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(u) if u then pcall(learnLayer, u) end end)
ns.On("ZONE_CHANGED_NEW_AREA", function() Map.myLayer = nil end)
-- gleicher Layer wie ich? true / false / nil (unbekannt)
-- Tooltip-Zeile "Layer 1234 (wie du / anderer Layer)" - nil, wenn der Layer unbekannt ist
function Map.LayerLine(p)
    if not (p and p.layer) then return nil end
    local t = (L["Layer %s"]):format(tostring(p.layer))
    if Map.myLayer then
        t = t .. (p.layer == Map.myLayer and ("  |cff66db9e" .. L["(wie du)"] .. "|r") or ("  |cffe8b44a" .. L["(anderer Layer)"] .. "|r"))
    end
    return "|cffaaaaaa" .. t .. "|r"
end
function Map.SameLayer(name)
    local p = Map.pos[name]
    if not (p and p.layer and Map.myLayer) then return nil end
    return p.layer == Map.myLayer
end
ns.GuildOption({ page = "map", key = "mpShare", default = true, label = "Positionen teilen erlaubt",
    desc = "Aus: niemand sendet seine Position an die Gilde (Gildenkarte und Minimap-Punkte bleiben leer)" })
ns.GuildOption({ page = "map", key = "mpMinInt", default = 3, min = 2, max = 60, step = 1, label = "Position hoechstens alle",
    desc = "Kleinster Abstand zwischen zwei Positionsmeldungen (gegen Last im Addon-Kanal)",
    fmt = function(v) return (ns.L["%d s"]):format(v) end })
local function sendPos()
    if not IsInGuild() then return end
    if not ns.db.settings.shareMap or ns.GuildOpt("mpShare") == false then
        if lastKey ~= "off" then
            Comm.SendEx({ ch = "GUILD", key = "pos" }, "POS", 0)
            lastKey = "off"
        end
        return
    end
    if ns.inInstance() then
        if lastKey ~= "inst" then
            Comm.SendEx({ ch = "GUILD", key = "pos" }, "POS", 0)
            lastKey = "inst"
        end
        return
    end
    local mapID, x, y = ns.Camp.MyPosition()
    if not mapID then return end
    local xi, yi = math.floor(x * 10000), math.floor(y * 10000)
    local key = mapID .. ":" .. math.floor(xi / 20) .. ":" .. math.floor(yi / 20) .. ":" .. tostring(Map.myLayer or "")
    if key == lastKey and GetTime() - lastTime < 60 then return end
    lastKey, lastTime = key, GetTime()
    Comm.SendEx({ ch = "GUILD", key = "pos" }, "POS", mapID, xi, yi, Map.myLayer or "")
end
Map.sendPos = sendPos
Comm.On("HELLOREQ", function() lastKey = nil end)

Comm.On("POS", function(sender, _, mapID, x, y, layer)
    mapID = SEC.Num(mapID, 0, 1e7, true)
    x, y = SEC.Num(x, 0, 10000), SEC.Num(y, 0, 10000)   -- Kartenkoordinaten 0..1 (x10000)
    if not mapID or mapID == 0 or not x or not y then
        Map.pos[sender] = nil
    else
        layer = (layer and layer ~= "") and SEC.Text(layer, 12) or nil
        local now = GetTime()
        local prev = Map.pos[sender]
        local np = { mapID = mapID, x = x / 10000, y = y / 10000, t = now, layer = layer }
        -- 0.6.139: gleiten statt springen - von der gerade angezeigten Stelle ueber die Zeit bis zur naechsten Meldung
        if prev and prev.mapID == mapID and now - prev.t < 20 then
            np.fx, np.fy = Map.Glide(prev, now)
            np.gt0 = now
            np.gdur = math.max(0.5, math.min(10, now - prev.t))
            -- weit gesprungen (Flugpunkt, Ruhestein): nicht ueber die Karte gleiten
            if math.abs(np.fx - np.x) + math.abs(np.fy - np.y) > 0.15 then np.fx = nil end
        end
        Map.pos[sender] = np
    end
    Map.dirty = true
end)

-- Eindeutige Roster-Zuordnung statt Vergleich von Vorname und vollem Namen.
local function memberKey(name)
    if not name then return end
    local full = ns.fullName(name)
    local member = ns.Radar and ns.Radar.byName and ns.Radar.byName[full]
    return member and member.name or full
end

-- angezeigte Position (gleitend zwischen zwei Meldungen); ohne Gleitdaten die gemeldete Stelle
function Map.Glide(p, now)
    if not p.fx then return p.x, p.y end
    local q = ((now or GetTime()) - p.gt0) / p.gdur
    if q >= 1 then p.fx = nil return p.x, p.y end
    if q < 0 then q = 0 end
    return p.fx + (p.x - p.fx) * q, p.fy + (p.y - p.fy) * q
end
function Map.Gliding()
    for _, p in pairs(Map.pos) do if p.fx then return true end end
    return false
end

function Map.Active()
    local out, newest, now = {}, {}, GetTime()
    for name, p in pairs(Map.pos) do
        if now - p.t < EXPIRE then
            local key = memberKey(name)
            local previous = newest[key]
            if not previous or p.t > previous.p.t or (p.t == previous.p.t and name < previous.name) then
                newest[key] = { name = name, p = p }
            end
        else
            Map.pos[name] = nil
        end
    end
    for _, entry in pairs(newest) do out[#out + 1] = entry end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

------------------------------------------------------------------------
-- Koordinaten zwischen Karten umrechnen
------------------------------------------------------------------------
local cache = {}
-- Rueckfall ueber Kartenrechtecke (klappt in Classic auch dort, wo die Weltkoordinaten fehlen):
-- Position erst auf den gemeinsamen Kontinent umrechnen, dann auf die Zielkarte
local function rectOn(child, parent)
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local ok, a, b, c, d = pcall(C_Map.GetMapRectOnMap, child, parent)
    if not ok or not a or not b or b == a or not c or not d or d == c then return nil end
    return a, b, c, d
end
local function continentOf(id)
    for _ = 1, 8 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == 2 then return id end   -- Enum.UIMapType.Continent
        id = info.parentMapID
    end
end
local function translateRect(src, x, y, dst)
    local cont = continentOf(src)
    if not cont then return nil end
    local cx, cy = x, y
    if src ~= cont then
        local a, b, c, d = rectOn(src, cont)
        if not a then return nil end
        cx, cy = a + x * (b - a), c + y * (d - c)
    end
    if dst == cont then return cx, cy end
    local a, b, c, d = rectOn(dst, cont)
    if not a then return nil end
    return (cx - a) / (b - a), (cy - c) / (d - c)
end
local function translate(src, x, y, dst)
    if src == dst then return x, y end
    local px, py
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, src, CreateVector2D(x, y))
    if ok and cont and world then
        local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, dst)
        if ok2 and pos then px, py = pos:GetXY() end
    end
    if not px then px, py = translateRect(src, x, y, dst) end
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end
Map.translate = translate

function Map.MapName(mapID)
    if cache[mapID] == nil then
        local info = C_Map.GetMapInfo(mapID)
        cache[mapID] = info and info.name or (L["Karte "] .. mapID)
    end
    return cache[mapID]
end

function Map.ShowOnWorldMap(mapID)
    if not mapID then return end
    -- 0.5.941: im Kampf nicht oeffnen/umschalten - aus Addon-Code geoeffnet, darf Blizzards Karte ihre Pins nicht
    -- einrichten (Blockiert-Meldung "Button:SetPassThroughButtons()"). Ziel und Minimap-Pfeil bleiben gesetzt.
    if ns.inCombat and ns.inCombat() then
        if not Map.combatHintAt or GetTime() - Map.combatHintAt > 15 then
            Map.combatHintAt = GetTime()
            ns.print(L["Im Kampf oeffnet Oasis die Karte nicht - das Ziel ist gesetzt, oeffne die Karte nach dem Kampf."])
        end
        return
    end
    if not WorldMapFrame:IsShown() then
        if C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap, mapID) else ToggleWorldMap() end
    end
    pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
end

-- Mitglied auf der Weltkarte zeigen: genaue Position (wenn es Oasis hat und teilt) oder wenigstens das Gebiet
local zoneCache = {}
local function mapIDForZone(zone)
    if not zone or zone == "" or not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    if zoneCache[zone] ~= nil then return zoneCache[zone] or nil end
    local found = false
    -- Azeroth, Kalimdor, Oestliche Koenigreiche, Scherbenwelt, Nordend
    for _, root in ipairs({ 947, 1414, 1415, 1945, 113, 12, 13 }) do
        local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        if ok and type(kids) == "table" then
            for _, k in ipairs(kids) do
                if ns.safe(k.name) == zone then found = k.mapID break end
            end
        end
        if found then break end
    end
    zoneCache[zone] = found
    return found or nil
end
function Map.PosOf(name, alias)
    local best, now = nil, GetTime()
    for n, p in pairs(Map.pos) do
        if now - p.t < EXPIRE and (ns.SameName(n, name) or (alias and ns.SameName(n, alias)))
            and (not best or p.t > best.t) then best = p end
    end
    return best
end
function Map.ShowMember(name, zone, alias)
    if ns.isMe(name) then
        local id = C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player"))
        if id then Map.ShowOnWorldMap(id) return true end
    end
    local p = Map.PosOf(name, alias)
    if p then
        Map.Flash(name)
        Map.ShowOnWorldMap(p.mapID)
        return true
    end
    local id = mapIDForZone(zone)
    if id then
        Map.ShowOnWorldMap(id)
        K.Toast(ns.displayName(name), L["Genaue Position unbekannt - zeige das Gebiet."] .. "  (" .. zone .. ")", C.muted)
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Weltkarten-Punkte
------------------------------------------------------------------------
local pins, pinPool = {}, {}
local provider

local function newPin(canvas)
    local p = CreateFrame("Frame", nil, canvas)
    p:SetSize(26, 26)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture(ns.MEDIA .. "dot")
    p.glow:SetSize(26, 26)
    p.glow:SetPoint("CENTER")
    p.glow:SetVertexColor(0, 0, 0)
    p.glow:SetAlpha(0.7)
    p.ring = p:CreateTexture(nil, "ARTWORK")
    p.ring:SetTexture(ns.MEDIA .. "ring")
    p.ring:SetAllPoints()
    p.dot = p:CreateTexture(nil, "OVERLAY")
    p.dot:SetTexture(ns.MEDIA .. "dot")
    p.dot:SetSize(20, 20)
    p.dot:SetPoint("CENTER")
    -- Oasis-Logo auf dem Punkt (nur bei Mitgliedern)
    p.logo = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.logo:SetTexture(ns.MEDIA .. "logo64")
    p.logo:SetSize(12, 12)
    p.logo:SetPoint("CENTER", 0, 0)
    p.logo:Hide()
    -- Gilden ohne Oasis-Logo: Anfangsbuchstaben des Gildennamens
    p.mono = K.Title(p, 9, C.text, "CENTER")
    p.mono:SetPoint("CENTER", 0, 0)
    p.mono:SetShadowOffset(1, -1)
    p.mono:Hide()
    p.label = K.Text(p, 11, C.text, "CENTER")
    p.label:SetPoint("TOP", p, "BOTTOM", 0, 2)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if self.hoverLabel then self.label:SetAlpha(1) end
        if self.tip then K.ShowTip(self, self.tip, "ANCHOR_RIGHT") end
    end)
    p:SetScript("OnLeave", function(self)
        if self.hoverLabel then self.label:SetAlpha(0) end
        GameTooltip:Hide()
    end)
    return p
end

local function acquire(canvas)
    local p = table.remove(pinPool) or newPin(canvas)
    p:SetParent(canvas)
    p.hoverLabel = nil
    p.label:SetAlpha(1)
    p.glow:SetVertexColor(0, 0, 0)
    p.glow:SetAlpha(0.7)
    p.ring:Show() p.glow:Show() p.dot:Show()
    -- Ziel-Puls eines frueheren Einsatzes abschalten
    p:SetScript("OnUpdate", nil)
    if p.pulse then p.pulse:Hide() end
    -- vorher als Mitglieder-Punkt benutzt: Standard-Aussehen wiederherstellen
    if p.isMemberStyle then
        p.isMemberStyle = nil
        p.ring:SetTexture(ns.MEDIA .. "ring")
        p.ring:ClearAllPoints()
        p.ring:SetAllPoints()
        p.dot:SetSize(20, 20)
        p:SetSize(26, 26)
        p.glow:SetSize(26, 26)
        p.glow:SetDrawLayer("BACKGROUND")
    end
    p.logo:Hide()
    p.mono:Hide()
    pins[#pins + 1] = p
    return p
end
local function releaseAll()
    for _, p in ipairs(pins) do
        p:Hide()
        pinPool[#pinPool + 1] = p
    end
    wipe(pins)
end

-- Gilden-Zeichen auf dem Mitglieder-Punkt: Oasis-Logo oder Anfangsbuchstaben des Gildennamens
-- (je nachdem, was die Gildenleitung als Logo eingestellt hat)
local function initials(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do
        local ch = word:match("^[%z\1-\127\194-\244][\128-\191]*")
        if ch and not ch:match("^%p$") then out[#out + 1] = ch end
        if #out >= 2 then break end
    end
    return table.concat(out)
end
-- Klasse eines Kartenpunkts: Gildenliste, sonst Oasis-Profil (Namen mit Akzenten/Realm sicher)
function Map.ClassOf(e)
    local c = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(e.name)
    if c then return c end
    local pr = ns.db.members and (ns.db.members[e.name] or (ns.Radar.AliasOf and ns.db.members[ns.Radar.AliasOf(e.name) or ""]))
    if pr and pr.class and pr.class ~= "" then return pr.class end
    return e.p and e.p.class
end
function Map.ApplyGuildMark(pin)
    local mode = ns.Admin and ns.Admin.LogoMode and ns.Admin.LogoMode() or "oasis"
    if mode == "oasis" then
        pin.logo:Show()
        pin.mono:Hide()
    else
        local t = initials(ns.Admin.BrandText())
        if t == "" then t = "?" end
        pin.mono:SetText(t)
        pin.mono:Show()
        pin.logo:Hide()
    end
end

------------------------------------------------------------------------
-- Heatmap: wo haelt sich die Gilde auf? Jede Minute: meine Position + alle geteilten Gilden-Positionen,
-- in einem 40x40-Raster je Karte. Hauptstaedte zaehlen nur 1/5 (dort steht man sowieso oft rum).
------------------------------------------------------------------------
local HEAT_N = 40
local CAPITAL = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local function heatAdd(mapID, x, y)
    if not mapID or not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return end
    ns.db.heat = ns.db.heat or {}
    local h = ns.db.heat[mapID] or {}
    ns.db.heat[mapID] = h
    local cell = math.floor(y * HEAT_N) * HEAT_N + math.floor(x * HEAT_N)
    h[cell] = (h[cell] or 0) + (CAPITAL[mapID] and 0.2 or 1)
end
local function heatTick()
    -- nur sammeln, wenn die Heatmap an ist (Standard aus) - sonst waechst die Speicherdatei umsonst
    if not ns.db or not ns.db.settings.mapHeat then return end
    if not ns.inInstance() and ns.Camp and ns.Camp.MyPosition then
        local mapID, x, y = ns.Camp.MyPosition()
        heatAdd(mapID, x, y)
    end
    for _, e in ipairs(Map.Active()) do
        if not ns.isMe(e.name) then heatAdd(e.p.mapID, e.p.x, e.p.y) end
    end
end
-- aeltere Werte langsam vergessen: pro Tag 3 %
local function heatDecay()
    ns.db.heat = ns.db.heat or {}
    local day = math.floor(ns.now() / 86400)
    local last = ns.db.heatDay or day
    local f = 0.97 ^ math.max(0, day - last)
    if f < 1 then
        for _, h in pairs(ns.db.heat) do
            for c, v in pairs(h) do
                v = v * f
                if v < 0.05 then h[c] = nil else h[c] = v end
            end
        end
    end
    ns.db.heatDay = day
end
ns.Listen("LOGIN", function()
    -- Heatmap ist standardmaessig aus (einmalig auch fuer alle, die sie schon an hatten)
    if not ns.db.settings.heatOffV2 then ns.db.settings.heatOffV2 = true ns.db.settings.mapHeat = false end
    -- 0.5.568: Heatmap aus -> gesammelte Felder nicht weiter im Speicher halten
    if not ns.db.settings.mapHeat then ns.db.heat, ns.db.heatDay = nil, nil end
    -- Levelbereiche standardmaessig aus (einmalig auch fuer alle, bei denen sie schon an waren)
    if not ns.db.settings.levelsOffV2 then ns.db.settings.levelsOffV2 = true ns.db.settings.mapLevels = false end
    heatDecay()
    C_Timer.NewTicker(60, function() pcall(heatTick) end)
end)
Map.HeatAdd = heatAdd

local heatTex = {}
-- Waerme-Verlauf: dunkles Orange -> Gelb -> Rot (keine Regenbogenfarben mehr)
local function heatColor(q)
    -- auf der hellen Karte gut sichtbar: Orange -> Rot -> Dunkelrot
    if q < 0.5 then local t = q / 0.5 return 1, 0.55 - 0.3 * t, 0.1 end
    local t = (q - 0.5) / 0.5
    return 1 - 0.3 * t, 0.25 - 0.2 * t, 0.1
end
-- Raster weichzeichnen (5x5-Gauss), damit aus einzelnen Punkten zusammenhaengende Flaechen werden
local KERNEL = { [0] = 1, [1] = 0.6, [2] = 0.22 }
local function smooth(h)
    local out = {}
    for c, v in pairs(h) do
        local cx, cy = c % HEAT_N, math.floor(c / HEAT_N)
        for dy = -2, 2 do
            for dx = -2, 2 do
                local x, y = cx + dx, cy + dy
                if x >= 0 and y >= 0 and x < HEAT_N and y < HEAT_N then
                    local k = KERNEL[math.abs(dx)] * KERNEL[math.abs(dy)]
                    local i = y * HEAT_N + x
                    out[i] = (out[i] or 0) + v * k
                end
            end
        end
    end
    return out
end
local function heatTexture(canvas, i)
    local t = heatTex[i]
    if not t then
        t = canvas:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        t:SetBlendMode("BLEND")
        heatTex[i] = t
    elseif t:GetParent() ~= canvas then
        t:SetParent(canvas)
    end
    return t
end
function Map.DrawHeat(canvas, mapID)
    for _, t in ipairs(heatTex) do t:Hide() end
    if not ns.db.settings.mapHeat or not mapID then return end
    local raw = ns.db.heat and ns.db.heat[mapID]
    if not raw then return end
    local h = smooth(raw)
    local max = 0
    for _, v in pairs(h) do if v > max then max = v end end
    if max <= 0 then return end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local sw, sh = cw / HEAT_N, ch / HEAT_N
    local i = 0
    for c, v in pairs(h) do
        local q = math.sqrt(v / max)
        if i > 1800 then break end   -- Obergrenze, damit die Karte fluessig bleibt
        if q > 0.12 then   -- ganz schwache Raender weglassen
            local r, g, b = heatColor(q)
            local x, y = ((c % HEAT_N) + 0.5) * sw, -((math.floor(c / HEAT_N)) + 0.5) * sh
            -- drei weiche Lagen pro Feld (gross + blass, mittel, klein + kraeftig) = unscharfer Fleck
            for layer = 1, 3 do
                i = i + 1
                local t = heatTexture(canvas, i)
                local size = ({ 3.2, 2.2, 1.3 })[layer]
                local alpha = ({ 0.10, 0.14, 0.22 })[layer] * (0.35 + q)
                t:SetVertexColor(r, g, b, alpha)
                t:SetSize(sw * size, sh * size)
                t:ClearAllPoints()
                t:SetPoint("CENTER", canvas, "TOPLEFT", x, y)
                t:Show()
            end
        end
    end
end

-- Levelbereiche der Gebiete (Classic-Stand) - klein und dezent in der Gebietsmitte auf der Kontinentkarte
local ZONE_LVL = {
    [1411] = { 1, 10 }, [1412] = { 1, 10 }, [1413] = { 10, 25 }, [1438] = { 1, 10 }, [1439] = { 10, 20 }, [1440] = { 18, 30 },
    [1441] = { 25, 35 }, [1442] = { 15, 27 }, [1443] = { 30, 40 }, [1444] = { 40, 50 }, [1445] = { 35, 45 }, [1446] = { 40, 50 },
    [1447] = { 45, 55 }, [1448] = { 48, 55 }, [1449] = { 48, 55 }, [1450] = { 55, 60 }, [1451] = { 55, 60 }, [1452] = { 55, 60 },
    [1416] = { 30, 40 }, [1417] = { 30, 40 }, [1418] = { 35, 45 }, [1419] = { 45, 55 }, [1420] = { 1, 10 }, [1421] = { 10, 20 },
    [1422] = { 51, 58 }, [1423] = { 53, 60 }, [1424] = { 20, 30 }, [1425] = { 40, 50 }, [1426] = { 1, 10 }, [1427] = { 43, 50 },
    [1428] = { 50, 58 }, [1429] = { 1, 10 }, [1430] = { 55, 60 }, [1431] = { 18, 30 }, [1432] = { 10, 20 }, [1433] = { 15, 25 },
    [1434] = { 30, 45 }, [1435] = { 35, 45 }, [1436] = { 10, 20 }, [1437] = { 20, 30 },
}
-- neue WoW-Forever-Gebiete (Kartennummer per Name gesucht): Flusslande/Riverglades 35-45, Hyjal 60, Zephras 1-12
local ZONE_BY_NAME = {
    { names = { "flusslande", "riverglades", "dieflusslande" }, lv = { 35, 45 } },
    { names = { "hyjal", "berghyjal", "mounthyjal" }, lv = { 60, 60 } },
    { names = { "zephras", "zephrasisle", "inselzephras", "zephrasinsel" }, lv = { 1, 12 } },
}
local zoneNamesDone = false
local function findNamedZones()
    if zoneNamesDone or not (C_Map and C_Map.GetMapInfo) then return end
    zoneNamesDone = true
    local want = {}
    for _, z in ipairs(ZONE_BY_NAME) do for _, n in ipairs(z.names) do want[n] = z.lv end end
    for id = 1, 3000 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info and info.name and info.mapType == 3 then
            local n = info.name:lower():gsub("[%p%s]", "")
            if want[n] and not ZONE_LVL[id] then ZONE_LVL[id] = want[n] end
        end
    end
end
local zoneLabels = {}
function Map.DrawZoneLevels(canvas, mapID)
    for _, t in ipairs(zoneLabels) do t:Hide() end
    if not ns.db.settings.mapLevels or not (C_Map and C_Map.GetMapRectOnMap) then return end
    if mapID ~= 1414 and mapID ~= 1415 then return end
    findNamedZones()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local me = ns.safe(UnitLevel("player")) or 1
    local i = 0
    for zone, lv in pairs(ZONE_LVL) do
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, zone, mapID)
        if ok and minX and maxX and maxX > minX then
            i = i + 1
            local t = zoneLabels[i]
            if not t then
                t = canvas:CreateFontString(nil, "OVERLAY")
                if K.SetFontSafe then K.SetFontSafe(t, K.FONT_HEAD or K.FONT, 13, "OUTLINE", K.FONT) else t:SetFont(K.FONT, 13, "OUTLINE") end
                zoneLabels[i] = t
            elseif t:GetParent() ~= canvas then
                t:SetParent(canvas)
            end
            -- zu leicht gruen, passend gelb, etwas zu hoch orange, viel zu hoch rot
            local c
            if me > lv[2] then c = { 0.4, 0.9, 0.5 }
            elseif me >= lv[1] then c = { 1, 0.85, 0.3 }
            elseif me >= lv[1] - 5 then c = { 1, 0.55, 0.2 }
            else c = { 1, 0.3, 0.25 } end
            t:SetTextColor(c[1], c[2], c[3], 0.75)
            t:SetText(lv[1] .. "-" .. lv[2])
            t:ClearAllPoints()
            t:SetPoint("CENTER", canvas, "TOPLEFT", (minX + maxX) / 2 * cw, -((minY + maxY) / 2 + 0.025) * ch)
            t:Show()
        end
    end
end

function Map.UpdateWorldPins()
    releaseAll()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local canvas = WorldMapFrame:GetCanvas()
    pcall(Map.DrawHeat, canvas, mapID)
    pcall(Map.DrawZoneLevels, canvas, mapID)
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    local s = 1 / math.max(cscale, 0.01)
    s = s * (ns.db.settings.mapPinScale or 1)   -- 0.5.933: Groesse einstellbar
    local function place(pin, x, y)
        pin:SetScale(s)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", (x * cw) / s, (-y * ch) / s)
        -- Ebene der Karte selbst: Pins liegen auf der Karte, aber nie ueber anderen Fenstern
        pin:SetFrameStrata(canvas:GetFrameStrata())
        pin:SetFrameLevel(math.min(9000, canvas:GetFrameLevel() + 2500))   -- ueber Blizzards Karten-Symbolen
        pin:Show()
    end
    -- Gruppenpositionen gehoeren Blizzard, unabhaengig vom Kartentyp.
    -- GUID zusaetzlich vergleichen: Forever liefert unterschiedliche Namensformen.
    local groupNames, groupGUIDs = {}, {}
    local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
    for i = 0, count do
        local unit = i == 0 and "player" or (prefix .. i)
        if UnitExists(unit) then
            local name, realm = ns.safeAll(ns.UnitName(unit))
            if name then
                local full = realm and realm ~= "" and (name .. "-" .. realm) or name
                groupNames[memberKey(full)] = true
            end
            local guid = UnitGUID and ns.safe(UnitGUID(unit))
            if guid then groupGUIDs[guid] = true end
        end
    end
    groupNames[memberKey(ns.me())] = true
    -- Mitglieder
    for _, e in ipairs(Map.Active()) do
        local gx, gy = Map.Glide(e.p)
        local x, y = translate(e.p.mapID, gx, gy, mapID)
        -- wer in meiner Gruppe ist, hat schon Blizzards Punkt: dann nur Name + Layer (kein zweiter Punkt)
        local sh = ns.short(e.name)
        local member = ns.Radar and ns.Radar.byName and ns.Radar.byName[memberKey(e.name)]
        local inGroup = groupNames[memberKey(e.name)] == true
            or (member and member.guid and groupGUIDs[member.guid] == true)
        -- Keine alte Oasis-Position neben dem aktuellen Blizzard-Gruppenpunkt zeichnen.
        if x and not inGroup and not ns.isMe(e.name) then
            local pin = acquire(canvas)
            local r, g, b = ns.classColor(Map.ClassOf(e))
            -- wie Blizzards Gruppenpunkte: kleiner runder Punkt in Klassenfarbe mit dunklem Rand
            pin.ring:SetTexture(ns.MEDIA .. "dot")
            pin.ring:SetVertexColor(0, 0, 0, 1)
            pin.ring:ClearAllPoints()
            pin.ring:SetPoint("CENTER")
            pin.ring:SetSize(24, 24)
            -- heller Innenrand, damit auch helle Klassenfarben auf der Karte gut sichtbar sind
            pin.glow:SetTexture(ns.MEDIA .. "dot")
            pin.glow:ClearAllPoints()
            pin.glow:SetPoint("CENTER")
            pin.glow:SetSize(21, 21)
            pin.glow:SetVertexColor(1, 1, 1)
            pin.glow:SetAlpha(0.9)
            pin.glow:SetDrawLayer("ARTWORK", 1)
            pin.dot:SetTexture(ns.MEDIA .. "dot")
            pin.dot:SetVertexColor(r, g, b)
            pin.dot:SetSize(18, 18)   -- grosse Klassenfarben-Flaeche, nur duenner heller Rand
            pin:SetSize(24, 24)   -- alle Mitglieder-Punkte gleich gross, Name direkt darunter
            pin.isMemberStyle = true
            -- Mitglieder: nur Klassenfarbe (kein Gilden-Logo darauf)
            pin.logo:Hide()
            pin.mono:Hide()
            local lay = Map.SameLayer(e.name)
            local layTxt = lay == true and ("\n|cff66db9e" .. L["gleicher Layer"] .. "|r") or (lay == false and ("\n|cffd9786b" .. L["anderer Layer"] .. "|r") or "")
            -- Name weiss, nur beim Drueberfahren ueber den Punkt (Gruppenmitglieder ohne eigenen Punkt: immer)
            pin.label:SetText(ns.db.settings.mapNames and (ns.displayName(e.name) .. layTxt) or "")
            pin.hoverLabel = not inGroup
            pin.label:SetAlpha(inGroup and 1 or 0)
            pin.ring:SetShown(not inGroup)
            pin.glow:SetShown(not inGroup)
            pin.dot:SetShown(not inGroup)
            -- "Auf der Karte zeigen": Kreis pulsiert ein paar Sekunden in der Akzentfarbe
            if Map.IsFlash(e.name) then
                pin.ring:Show() pin.glow:Show() pin.dot:Show()
                pin:SetScript("OnUpdate", function(self)
                    local left = (Map.flashUntil or 0) - GetTime()
                    if left <= 0 then
                        self:SetScript("OnUpdate", nil)
                        self.ring:SetSize(19, 19) self.ring:SetVertexColor(0, 0, 0, 1)
                        return
                    end
                    local q = 0.5 + 0.5 * math.sin(GetTime() * 9)
                    self.ring:SetSize(19 + q * 14, 19 + q * 14)
                    self.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35 + 0.55 * q)
                end)
                pin:SetFrameLevel(math.min(9100, canvas:GetFrameLevel() + 2600))
            else
                pin:SetScript("OnUpdate", nil)
            end
            local m = ns.Radar.byName[e.name]
            pin.tip = { ns.Radar.Colored(e.name) .. (m and (L["  |cffaaaaaaLevel "] .. m.level .. "|r") or ""),
                Map.MapName(e.p.mapID) .. (L["  %.1f, %.1f"]):format(e.p.x * 100, e.p.y * 100) }
            pin.tip[#pin.tip + 1] = Map.LayerLine(e.p)
            place(pin, x, y)
        end
    end
    -- Lagerfeuer
    if ns.Camp then
        for _, f in ipairs(ns.Camp.ActiveFires()) do
            local x, y = translate(f.mapID, (f.x or 0) / 10000, (f.y or 0) / 10000, mapID)
            if x then
                local pin = acquire(canvas)
                pin.dot:SetTexture(ns.MEDIA .. "diamond")
                pin.dot:SetVertexColor(C.pink[1], C.pink[2], C.pink[3])
                pin.ring:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
                pin.label:SetText(L["Lagerfeuer"] .. "  " .. math.max(0, math.ceil(((f.exp or 0) - ns.now()) / 60)) .. L[" Min"])   -- 0.5.936: Restlaufzeit
                pin.tip = { L["|cffff3fbfLagerfeuer|r von "] .. ns.Radar.Colored(f.by) }
                if (f.note or "") ~= "" then pin.tip[#pin.tip + 1] = f.note end
                pin.tip[#pin.tip + 1] = L["noch "] .. math.max(0, math.ceil(((f.exp or 0) - ns.now()) / 60)) .. L[" Min"]
                place(pin, x, y)
            end
        end
    end
    -- Sterbeorte der letzten 14 Tage
    if ns.Deaths and ns.db.settings.mapDeaths then
        for _, d in ipairs(ns.Deaths.MapPins()) do
            local x, y = translate(d.mapID, (d.x or 0) / 10000, (d.y or 0) / 10000, mapID)
            if x then
                local pin = acquire(canvas)
                pin.dot:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                pin.dot:SetVertexColor(1, 1, 1)
                pin.ring:SetVertexColor(0.08, 0.07, 0.11)
                pin.label:SetText("")
                pin.tip = { ns.Radar.Colored(d.who) .. " |cff888888" .. (d.lvl or "?") .. "|r", ns.ago(d.ts) .. (((d.killer or "") ~= "") and ("  ·  " .. d.killer) or "") }
                place(pin, x, y)
                pin:SetAlpha(0.85)
            end
        end
    end
    -- Questziel (Questgeber aus der Dungeon-Seite)
    local tg = Map.FollowTarget()
    if tg and not tg.member then
        local x, y = translate(tg.mapID, tg.x, tg.y, mapID)
        if x then
            local pin = acquire(canvas)
            pin.dot:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            pin.dot:SetVertexColor(1, 1, 1)
            pin.ring:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
            -- Ziel ist ein Mitglied: dessen Punkt beschriftet schon den Namen -> keine zweite Beschriftung
            pin.label:SetText(tg.member and "" or (tg.label or ""))
            pin.tip = { "|cffffd24a" .. (tg.label or "") .. "|r", tg.sub or "", L["|cff777777Ziel verschwindet, wenn du dort bist|r"] }
            place(pin, x, y)
            pin:SetAlpha(1)
            -- ueber allem (auch ueber Blizzards Quest-Symbolen) und die ersten Sekunden rot pulsieren
            pin:SetFrameStrata("FULLSCREEN_DIALOG")
            pin:SetFrameLevel(math.min(9200, canvas:GetFrameLevel() + 2700))
            if not pin.pulse then
                pin.pulse = pin:CreateTexture(nil, "BACKGROUND", nil, -2)
                pin.pulse:SetTexture(ns.MEDIA .. "dot")
                pin.pulse:SetPoint("CENTER")
                pin.pulse:SetBlendMode("ADD")
            end
            pin.pulse:Show()
            pin:SetScript("OnUpdate", function(self)
                local t = GetTime() - (Map.targetAt or 0)
                if t > 8 then
                    self.pulse:SetSize(26, 26)
                    self.pulse:SetVertexColor(1, 0.2, 0.15, 0.35)
                    return
                end
                local ph = (t * 1.6) % 1                  -- Welle von innen nach aussen
                local sz = 20 + 70 * ph
                self.pulse:SetSize(sz, sz)
                self.pulse:SetVertexColor(1, 0.15, 0.1, 0.9 * (1 - ph))
            end)
        end
    end
end

------------------------------------------------------------------------
-- Questziel setzen / entfernen (Welt- und Minimap)
------------------------------------------------------------------------
-- Punkt eines Mitglieds kurz blinken lassen (bewegt sich mit, weil es sein eigener Punkt ist)
function Map.Flash(name, secs)
    Map.flashName, Map.flashUntil = name, GetTime() + (secs or 4)
    Map.dirty = true
    if WorldMapFrame and WorldMapFrame:IsShown() then Map.UpdateWorldPins() end
end
function Map.IsFlash(n)
    local f = Map.flashName
    if not f or GetTime() > (Map.flashUntil or 0) then return false end
    return ns.SameName(n, f)
end
-- Ziel auf ein Mitglied: Position immer aus dessen aktuellem Standort
function Map.FollowTarget()
    local tg = Map.target
    if tg and tg.member then
        local p = Map.PosOf(tg.member)
        if p then tg.mapID, tg.x, tg.y = p.mapID, p.x, p.y end
    end
    return tg
end
function Map.SetTarget(t)
    if not t or not t.mapID or not t.x then return end
    Map.target = t
    Map.targetAt = GetTime()
    Map.dirty = true
    Map.ShowOnWorldMap(t.mapID)
    Map.UpdateWorldPins()
    if Map.UpdateMinimap then Map.UpdateMinimap() end
    K.Toast(L["Ziel gesetzt"], (t.label or "") .. ((t.sub or "") ~= "" and ("  ·  " .. t.sub) or ""), C.amber, function() Map.ClearTarget() end)
end
function Map.ClearTarget()
    Map.target = nil
    Map.dirty = true
    if Map.UpdateMinimap then Map.UpdateMinimap() end
    if WorldMapFrame and WorldMapFrame:IsShown() then Map.UpdateWorldPins() end
end

local function setupWorldMap()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() releaseAll() end
    function provider:RefreshAllData() Map.UpdateWorldPins() end
    function provider:OnMapChanged() Map.UpdateWorldPins() end
    function provider:OnCanvasScaleChanged() Map.UpdateWorldPins() end
    local ok, e = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider)
    if not ok then ns.err("Weltkarte", e) return end
    WorldMapFrame:HookScript("OnShow", function() Map.UpdateWorldPins() Map.ShowMapBar() end)
    WorldMapFrame:HookScript("OnHide", function() if Map.bar then Map.bar:Hide() end end)
end

-- Oasis-Leiste unter der Weltkarte: Position teilen, Namen, Minimap-Punkte, Heatmap
function Map.ShowMapBar()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not Map.bar then
        -- 0.5.965: Leiste mit kleinen Schiebeschaltern, alles in EINER Zeile. Wird es eng, rueckt sie zusammen
        -- (kleinere Schrift, engere Abstaende, Knoepfe rechts nur als Symbol); erst wenn auch das nicht reicht, bricht sie um.
        local b = CreateFrame("Frame", "OasisMapBar", UIParent)
        b:SetHeight(34)
        b:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "HIGH")
        K.Fill(b, { 0.035, 0.035, 0.045, 0.96 })
        K.Border(b, { 1, 1, 1, 0.08 })
        b.sheen = b:CreateTexture(nil, "BORDER")
        b.sheen:SetPoint("TOPLEFT", 1, -1)
        b.sheen:SetPoint("TOPRIGHT", -1, -1)
        b.sheen:SetHeight(16)
        if not K.Gradient(b.sheen, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.035 }) then b.sheen:Hide() end
        b.logo = b:CreateTexture(nil, "ARTWORK")
        b.logo:SetTexture(ns.MEDIA .. "logo64")
        b.logo:SetSize(18, 18)
        b.logo:SetPoint("TOPLEFT", 12, -8)
        b.boxes, b.seps = {}, {}
        -- { Schalter, Text, danach, Gruppe, Tooltip }  (Heatmap, Position teilen und Minimap-Punkte stehen nur noch in den Einstellungen)
        local defs = {
            { "mapNames", "Namen", function() Map.UpdateWorldPins() end, 1, "Namen neben den Punkten der Gildenmitglieder" },
            { "mapLevels", "Levelbereiche", function() Map.UpdateWorldPins() end, 2, "Stufenbereich der Gebiete auf der Karte" },
            { "mapDeaths", "Todesorte", function() Map.UpdateWorldPins() end, 2, "Wo Gildenmitglieder gestorben sind" },
            { "mapReveal", "Aufdecken", function() if ns.ComfortPlus then ns.ComfortPlus.ApplyReveal() end end, 2, "Noch unentdeckte Gebiete auf der Karte zeigen" },
            { "mapGather", "Sammelpunkte", function() ns.db.settings.gatherWorldOff = not ns.db.settings.mapGather Map.UpdateWorldPins() if ns.Gather then pcall(ns.Gather.DrawWorld) end end, 3, "Bekannte Fundorte von Kraeutern, Erzen und Kisten" },
            { "gatherRoute", "Sammelroute", function() if ns.Gather and ns.Gather.Refresh then ns.Gather.Refresh() end end, 3, "Verbindet die Fundorte des Gebiets zu einer Rundstrecke" },
        }
        local SW_W, SW_H, KNOB = 22, 12, 8
        for _, d in ipairs(defs) do
            local t = CreateFrame("Button", nil, b)
            t:SetHeight(26)
            t.hl = t:CreateTexture(nil, "HIGHLIGHT")
            t.hl:SetAllPoints()
            t.hl:SetColorTexture(1, 1, 1, 0.04)
            -- kleiner Schiebeschalter: Bahn + runder Knopf (rechts = an)
            t.pill = K.Pill(t, SW_W, SW_H)
            t.pill:SetPoint("LEFT", 4, 0)
            t.knob = K.KnobCircle(t.pill, KNOB)
            t.lbl = K.Text(t, 12, C.text)
            t.lbl:SetPoint("LEFT", t.pill, "RIGHT", 6, 1)
            t.lbl:SetText(L[d[2]])
            t.key, t.after, t.group, t.tip, t.title = d[1], d[3], d[4], d[5], d[2]
            function t:Fit() self:SetWidth(4 + SW_W + 6 + math.ceil(self.lbl:GetStringWidth() or 40) + 4) end
            t:Fit()
            function t:Update()
                local on = ns.db.settings[self.key] and true or false
                self.on = on
                local c = on and C.text or C.dim
                self.lbl:SetTextColor(c[1], c[2], c[3])
                local pc = on and C.accent or { 0.22, 0.22, 0.25 }
                self.pill:SetColor(pc[1], pc[2], pc[3], 1)
                local kc = on and 1 or 0.62
                self.knob:SetVertexColor(kc, kc, kc + (on and 0 or 0.04), 1)
                self.knob:ClearAllPoints()
                self.knob:SetPoint("CENTER", self.pill, "LEFT", on and (SW_W - SW_H / 2) or (SW_H / 2), 0)
            end
            t:SetScript("OnEnter", function(self)
                if not self.on then self.lbl:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
                K.ShowTip(self, { L[self.title] .. "  " .. (self.on and ("|cff66db9e" .. L["an"] .. "|r") or ("|cff888888" .. L["aus"] .. "|r")), L[self.tip] })
            end)
            t:SetScript("OnLeave", function(self) self:Update() GameTooltip:Hide() end)
            t:SetScript("OnClick", function(self)
                ns.db.settings[self.key] = not ns.db.settings[self.key]
                self:Update()
                pcall(self.after)
                if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
            end)
            b.boxes[#b.boxes + 1] = t
        end
        for i = 1, 2 do
            local sp = b:CreateTexture(nil, "ARTWORK")
            sp:SetColorTexture(1, 1, 1, 0.10)
            sp:SetSize(1, 14)
            b.seps[i] = sp
        end
        -- Knoepfe rechts: Symbol + Text (bei wenig Platz nur das Symbol), beim Ueberfahren hell
        local function action(text, icon, onClick, tip)
            local g = CreateFrame("Button", nil, b)
            g:SetHeight(26)
            g.hl = g:CreateTexture(nil, "HIGHLIGHT")
            g.hl:SetAllPoints()
            g.hl:SetColorTexture(1, 1, 1, 0.04)
            g.ic = g:CreateTexture(nil, "ARTWORK")
            g.ic:SetTexture(ns.MEDIA .. "icons\\" .. icon)
            g.ic:SetSize(14, 14)
            g.ic:SetPoint("LEFT", 8, 0)
            g.ic:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            g.lbl = K.Text(g, 12, C.muted)
            g.lbl:SetPoint("LEFT", g.ic, "RIGHT", 6, 1)
            g.lbl:SetText(L[text])
            g.title = text
            function g:Fit(labels)
                self.lbl:SetShown(labels)
                self:SetWidth(labels and (math.ceil(self.lbl:GetStringWidth() or 40) + 36) or 30)
            end
            g:Fit(true)
            g:SetScript("OnEnter", function(self)
                self.lbl:SetTextColor(C.text[1], C.text[2], C.text[3])
                self.ic:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                K.ShowTip(self, tip and tip() or { L[self.title] })
            end)
            g:SetScript("OnLeave", function(self)
                self.lbl:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
                self.ic:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
                GameTooltip:Hide()
            end)
            g:SetScript("OnClick", onClick)
            return g
        end
        b.gear = action("Einstellungen", "settings", function() if ns.OpenAreaSettings then ns.OpenAreaSettings("map") end end,
            function() return { L["Karten-Einstellungen"], L["Groesse, Deckkraft und mehr fuer alle Symbole auf Karte und Minimap"] } end)
        b.marker = action("Marker", "pin", function(self)
            if ns.MapExtras and ns.MapExtras.MenuItems then K.ShowMenu(self, ns.MapExtras.MenuItems(), L["Marker setzen"]) end
        end, function() return { L["Marker setzen"], L["Treffpunkt, Vorsicht oder Notiz: Art waehlen, dann auf die Karte klicken"] } end)
        b.layer = action("Layer", "map", function(self)
            if ns.MapExtras and ns.MapExtras.LayerMenuItems then K.ShowMenu(self, ns.MapExtras.LayerMenuItems(), L["Layer wechseln"]) end
        end, function() return { L["Layer wechseln"] } end)
        b.asep = b:CreateTexture(nil, "ARTWORK")
        b.asep:SetColorTexture(1, 1, 1, 0.10)
        b.asep:SetSize(1, 14)
        -- Stufen von luftig nach eng: { Schriftgroesse, Abstand zwischen Gruppen, Knoepfe mit Text }
        local STEPS = { { 12, 18, true }, { 11, 14, true }, { 11, 12, false }, { 10, 8, false } }
        function b:Layout()
            local w = self:GetWidth() or 0
            local LEFT, ROW = 38, 28
            local actions = { self.layer, self.marker, self.gear }
            local GAP, actionsW, need
            for _, st in ipairs(STEPS) do
                for _, t in ipairs(self.boxes) do K.SetFontSafe(t.lbl, K.FONT, st[1], "", K.FONT) t:Fit() end
                for _, g in ipairs(actions) do K.SetFontSafe(g.lbl, K.FONT, st[1], "", K.FONT) g:Fit(st[3]) end
                GAP, actionsW, need = st[2], 10, LEFT
                for _, g in ipairs(actions) do actionsW = actionsW + g:GetWidth() end
                local prev
                for _, t in ipairs(self.boxes) do
                    need = need + t:GetWidth() + ((prev and prev.group ~= t.group) and GAP or 0)
                    prev = t
                end
                if w < 300 or need + actionsW + 14 <= w then break end
            end
            local x, row, sepN, prev = LEFT, 0, 0, nil
            for _, s in ipairs(self.seps) do s:Hide() end
            for _, t in ipairs(self.boxes) do
                local newGroup = prev and prev.group ~= t.group
                -- erste Zeile teilt sich den Platz mit den Knoepfen rechts; Umbruch nur, wenn selbst die engste Stufe nicht passt
                local limit = w - 8 - (row == 0 and actionsW + 16 or 0)
                if w > 300 and x > LEFT and x + (newGroup and GAP or 0) + t:GetWidth() > limit then
                    row, x, newGroup = row + 1, LEFT, false
                end
                if newGroup then
                    sepN = sepN + 1
                    local s = self.seps[sepN]
                    if s then
                        s:ClearAllPoints()
                        s:SetPoint("TOPLEFT", self, "TOPLEFT", x + math.floor(GAP / 2), -10 - row * ROW)
                        s:Show()
                    end
                    x = x + GAP
                end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", x, -4 - row * ROW)
                x = x + t:GetWidth()
                prev = t
            end
            self.gear:ClearAllPoints()
            self.gear:SetPoint("TOPRIGHT", -6, -4)
            self.marker:ClearAllPoints()
            self.marker:SetPoint("RIGHT", self.gear, "LEFT", 0, 0)
            self.layer:ClearAllPoints()
            self.layer:SetPoint("RIGHT", self.marker, "LEFT", 0, 0)
            self.asep:ClearAllPoints()
            self.asep:SetPoint("RIGHT", self.layer, "LEFT", -6, 0)
            self:SetHeight(6 + (row + 1) * ROW)
        end
        Map.bar = b
    end
    local b = Map.bar
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", WorldMapFrame, "BOTTOMLEFT", 0, -2)
    b:SetPoint("TOPRIGHT", WorldMapFrame, "BOTTOMRIGHT", 0, -2)
    for _, t in ipairs(b.boxes) do t:Update() end
    if b.Layout then b:Layout() end
    b:Show()
end

------------------------------------------------------------------------
-- Minimap-Punkte (in die bestehende Minimap integriert)
------------------------------------------------------------------------
-- Durchmesser der Minimap in Metern je Zoomstufe (wie HereBeDragons)
local MINIMAP_SIZE = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}
local mmPins, mmUsed = {}, 0

local function getCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

-- Umrechnung je Punkt merken (Performance 0.5.482): Positionen aendern sich nur, wenn eine neue Meldung kommt -
-- vorher liefen pro Takt (0,15 s) und Mitglied zwei C_Map-Abfragen, Vektor-Objekte und pcalls.
local tcache = setmetatable({}, { __mode = "k" })
local function cachedTranslate(rec, src, x, y, dst)
    local c = tcache[rec]
    if c and c[1] == src and c[2] == x and c[3] == y and c[4] == dst then return c[5], c[6] end
    local tx, ty = translate(src, x, y, dst)
    if not c then c = {} tcache[rec] = c end
    c[1], c[2], c[3], c[4], c[5], c[6] = src, x, y, dst, tx, ty
    return tx, ty
end
-- wer in meiner Gruppe ist (Blizzard zeigt sie selbst) - nur bei Gruppenwechsel neu
local inGroup, groupDirty = {}, true
ns.On("GROUP_ROSTER_UPDATE", function() groupDirty = true end)
local function isGrouped(name)
    if groupDirty then
        groupDirty = false
        wipe(inGroup)
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        local pre = IsInRaid() and "raid" or "party"
        for i = 1, n do
            local un = ns.safe(ns.UnitName(pre .. i))
            if un then inGroup[ns.NameKey(un)] = true end
        end
    end
    return inGroup[ns.NameKey(name)] == true
end
-- Tooltip erst beim Ueberfahren bauen (vorher pro Takt und Punkt eine neue Tabelle)
local function pinTip(p)
    if p.kind == "m" then
        local m = ns.Radar.byName[p.who]
        return { ns.Radar.Colored(p.who) .. (m and (L["  |cffaaaaaaLevel "] .. m.level .. "|r") or ""), p.dist .. L[" m entfernt"], L["|cffff1200Oasis|r"] }
    elseif p.kind == "f" then
        return { L["|cffff3fbfLagerfeuer|r von "] .. ns.Radar.Colored(p.who), p.dist .. L[" m entfernt"] }
    elseif p.kind == "t" then
        return { "|cffffd24a" .. (p.label or "") .. "|r", p.dist .. L[" m entfernt"] }
    end
end
Map.PinTip = pinTip
local function setDot(p, tex, r, g, b)
    if p.tex ~= tex then p.dot:SetTexture(tex) p.tex = tex end
    p.dot:SetVertexColor(r, g, b)
end

local function mmPin(i)
    local p = mmPins[i]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(14, 14)
        if ns.MiniPinLayer then ns.MiniPinLayer(p, 4) end
        p.glow = p:CreateTexture(nil, "BACKGROUND")
        p.glow:SetTexture(ns.MEDIA .. "dot")
        p.glow:SetSize(18, 18)
        p.glow:SetPoint("CENTER")
        p.glow:SetVertexColor(0, 0, 0)
        p.glow:SetAlpha(0.7)
        p.ring = p:CreateTexture(nil, "ARTWORK")
        p.ring:SetTexture(ns.MEDIA .. "ring")
        p.ring:SetAllPoints()
        p.dot = p:CreateTexture(nil, "OVERLAY")
        p.dot:SetTexture(ns.MEDIA .. "dot")
        p.dot:SetSize(12, 12)
        p.dot:SetPoint("CENTER")
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) local t = pinTip(self) if t then K.ShowTip(self, t, "ANCHOR_LEFT") end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mmPins[i] = p
    end
    return p
end

function Map.UpdateMinimap()
    mmUsed = 0
    if Minimap and ns.db.settings.minimapDots and not ns.inInstance() then
        local myMap, mx, my = ns.Camp.MyPosition()
        local w, h
        if myMap then w, h = C_Map.GetMapWorldSize(myMap) end
        if myMap and w and w > 0 then
            local zoom = Minimap:GetZoom() or 0
            local indoors = (tonumber(getCVar("minimapZoom")) == zoom) and "outdoor" or "indoor"
            local radius = (MINIMAP_SIZE[indoors][zoom] or 300) / 2
            local half = Minimap:GetWidth() / 2
            local rotate = getCVar("rotateMinimap") == "1"
            local facing = rotate and ns.safe(GetPlayerFacing and GetPlayerFacing()) or nil
            local sinF, cosF = 0, 1
            if facing then sinF, cosF = math.sin(facing), math.cos(facing) end
            local sc, userAlpha = ns.db.settings.mmDotScale or 1, ns.db.settings.mmDotAlpha or 1   -- 0.5.933: einstellbar

            -- Punkt setzen; liefert Pin und Entfernung (Meter)
            local function place(x, y)
                local dx, dy = (x - mx) * w, (y - my) * h
                local dist = math.floor(math.sqrt(dx * dx + dy * dy))
                if facing then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
                local nx, ny = dx / radius, dy / radius
                local d = math.sqrt(nx * nx + ny * ny)
                local edge = d > 0.9
                if edge then nx, ny = nx / d * 0.9, ny / d * 0.9 end
                mmUsed = mmUsed + 1
                local p = mmPin(mmUsed)
                p:SetScale(sc)   -- Abstaende zaehlen im Massstab des Punkts -> durch sc teilen
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", nx * half / sc, -ny * half / sc)
                -- direkt ueber dem eigenen Pfeil: unsichtbar (wer neben mir steht, verdeckt mich sonst)
                p:SetAlpha((not ns.MiniPinVisible or ns.MiniPinVisible(nx * half, ny * half)) and (edge and 0.55 or 1) * userAlpha or 0)
                p:Show()
                p.dist = dist
                return p, dist
            end

            local now = GetTime()
            for name, pos in pairs(Map.pos) do
                -- Gruppenmitglieder zeigt Blizzard schon auf der Minimap -> keinen zweiten Punkt
                if now - pos.t < EXPIRE and not isGrouped(name) then
                    local gx, gy = Map.Glide(pos, now)
                    local x, y = cachedTranslate(pos, pos.mapID, gx, gy, myMap)
                    if x then
                        local p = place(x, y)
                        p.kind, p.who = "m", name
                        local r, g, b = ns.classColor((ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(name)) or pos.class)
                        setDot(p, ns.MEDIA .. "dot", r, g, b)
                        p.ring:SetVertexColor(0.08, 0.07, 0.11)
                    end
                end
            end
            if ns.Camp then
                for _, f in ipairs(Map.FiresCached and Map.FiresCached() or {}) do
                    local x, y = cachedTranslate(f, f.mapID, (f.x or 0) / 10000, (f.y or 0) / 10000, myMap)
                    if x then
                        local p = place(x, y)
                        p.kind, p.who = "f", f.by
                        setDot(p, ns.MEDIA .. "diamond", C.pink[1], C.pink[2], C.pink[3])
                        p.ring:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
                    end
                end
            end
            -- Questziel: immer zeigen, am Rand wenn weit weg; bei Ankunft entfernen
            local tg = Map.FollowTarget()
            if tg then
                local x, y = translate(tg.mapID, tg.x, tg.y, myMap)
                if x then
                    local p, dist = place(x, y)
                    p.kind, p.label = "t", tg.label
                    if tg.member then
                        local r, g, b = ns.classColor(ns.Radar and ns.Radar.ClassOf(tg.member))
                        setDot(p, ns.MEDIA .. "dot", r or 1, g or 1, b or 1)
                    else
                        setDot(p, "Interface\\GossipFrame\\AvailableQuestIcon", 1, 1, 1)
                    end
                    p.ring:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
                    if dist < 12 then
                        K.Toast(L["Ziel erreicht"], tg.label or "", C.mint)
                        Map.target = nil
                    end
                end
            end
        end
    end
    for i = mmUsed + 1, #mmPins do mmPins[i]:Hide() end
end

------------------------------------------------------------------------
-- Seite: Liste nach Gebiet (mit Entfernung + Richtung), Gebiete, Einstellungen
------------------------------------------------------------------------
local NEAR = 500   -- Meter fuer "in deiner Naehe"
local search, openZones = "", {}
local atan2 = math.atan2 or math.atan

-- Entfernung (Meter) und Richtung (Bogenmass, 0 = Norden, im Uhrzeigersinn) zu einer Position
function Map.Distance(p)
    local myMap, mx, my = ns.Camp.MyPosition()
    if not myMap then return nil end
    local x, y = translate(p.mapID, p.x, p.y, myMap)
    if not x then return nil end
    local w, h = C_Map.GetMapWorldSize(myMap)
    if not w or w <= 0 then return nil end
    local dx, dy = (x - mx) * w, (y - my) * h
    return math.sqrt(dx * dx + dy * dy), atan2(dx, -dy)
end

local function fmtDist(d)
    if d >= 1000 then return ("%.1f km"):format(d / 1000):gsub("%.", ",") end
    return math.floor(d / 10 + 0.5) * 10 .. " m"
end

local function whisper(name) ns.Whisper(name) end
local function invite(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName(name)) elseif InviteUnit then pcall(InviteUnit, ns.ChatName(name)) end
end

local function rowMenu(self, e)
    K.ShowMenu(self, {
        { text = L["Auf der Weltkarte zeigen"], func = function() Map.ShowOnWorldMap(e.p.mapID) end },
        { text = L["Als Ziel setzen (Pfeil auf der Minimap)"], func = function()
            Map.SetTarget({ mapID = e.p.mapID, x = e.p.x, y = e.p.y, label = ns.displayName(e.name), member = e.name })
        end },
        { text = L["Anfluestern"], func = function() whisper(e.name) end },
        { text = L["In Gruppe einladen"], func = function() invite(e.name) end },
    }, ns.displayName(e.name))
end

local function panel(parent, title)
    local f = K.Panel(parent, C.panel)
    f.head = K.GameHead(f, title, C.accent)
    f.head:SetPoint("TOPLEFT", 12, -12)
    f.head:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    return f
end

-- Daten fuer die Liste: nach Gebiet gruppiert, eigenes Gebiet zuerst, innen nach Entfernung/Name
local function buildRows()
    local myMap = C_Map.GetBestMapForUnit("player")
    local groups, order = {}, {}
    for _, e in ipairs(Map.Active()) do
        local ok = search == "" or ns.short(e.name):lower():find(search, 1, true) or Map.MapName(e.p.mapID):lower():find(search, 1, true)
        if ok then
            e.dist, e.dir = Map.Distance(e.p)
            local g = groups[e.p.mapID]
            if not g then
                g = { mapID = e.p.mapID, name = Map.MapName(e.p.mapID), list = {}, mine = e.p.mapID == myMap }
                groups[e.p.mapID] = g
                order[#order + 1] = g
            end
            g.list[#g.list + 1] = e
        end
    end
    table.sort(order, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if #a.list ~= #b.list then return #a.list > #b.list end
        return a.name < b.name
    end)
    local rows = {}
    for _, g in ipairs(order) do
        table.sort(g.list, function(a, b)
            if a.dist and b.dist then return a.dist < b.dist end
            if a.dist or b.dist then return a.dist ~= nil end
            return a.name < b.name
        end)
        local closed = openZones[g.mapID] == false
        rows[#rows + 1] = { header = true, g = g, closed = closed }
        if not closed then for _, e in ipairs(g.list) do rows[#rows + 1] = e end end
    end
    return rows, order
end

ns.RegisterPage({
    key = "map", title = "Karte & Radar", order = 7, parent = "settings",
    sub = "Wo ist die Gilde? Wer ist in deiner Naehe - mit Entfernung, Richtung und Punkten auf Welt- und Minimap",
    build = function(p)
        -- Kennzahlen
        p.cards = {}
        local TD = { { ns.ICONS.map, "Teilen ihre Position", C.accent }, { ns.ICONS.radar, "In deinem Gebiet", C.mint },
            { ns.ICONS.social, "In deiner Naehe (500 m)", C.amber } }
        for i, d in ipairs(TD) do
            local c = K.HudTile(p, d[1], L[d[2]], d[3])
            c:SetHeight(62)
            p.cards[i] = c
        end
        local function layoutCards(w)
            local tw = math.floor(((w or 750) - 150 - 30) / 3)
            for i, c in ipairs(p.cards) do
                c:SetWidth(tw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
            end
        end
        p:HookScript("OnSizeChanged", function(_, w) layoutCards(w) end)
        layoutCards(p:GetWidth())
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
        local open = K.Button(p, L["Weltkarte oeffnen"], 140, 26, "primary", function()
            Map.ShowOnWorldMap(C_Map.GetBestMapForUnit("player"))
        end)
        open:SetPoint("TOPRIGHT", 0, 0)

        local SIDE = 250
        p.search = K.Input(p, 200, L["Name oder Gebiet suchen ..."], function(t) search = (t or ""):lower() ns.RefreshPage("map") end)
        p.search:SetPoint("TOPLEFT", 0, -66)

        local list = K.List(p, 34, function(l)
            local r = K.Row(l)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(20, 20)
            r.cls:SetPoint("LEFT", 12, 0)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("TOPLEFT", 40, -3)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -110, 0)
            r.cols.zone = K.Text(r, 11, C.muted)
            r.cols.zone:SetPoint("BOTTOMLEFT", 40, 3)
            r.cols.zone:SetPoint("RIGHT", r, "RIGHT", -110, 0)
            r.arrow = r:CreateTexture(nil, "ARTWORK")
            r.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
            r.arrow:SetSize(20, 20)
            r.arrow:SetPoint("RIGHT", -8, 0)
            r.cols.dist = K.Text(r, 12, C.text, "RIGHT")
            r.cols.dist:SetPoint("RIGHT", -32, 0)
            -- Gebiets-Ueberschrift
            r.hTitle = K.Title(r, 13, C.text)
            r.hTitle:SetPoint("LEFT", 26, 0)
            r.hTwist = K.Text(r, 12, C.muted)
            r.hTwist:SetPoint("LEFT", 10, 0)
            r.hInfo = K.Text(r, 11, C.dim, "RIGHT")
            r.hInfo:SetPoint("RIGHT", -10, 0)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnClick", function(self, btn)
                local e = self.item
                if not e then return end
                if e.header then
                    openZones[e.g.mapID] = e.closed and true or false
                    ns.RefreshPage("map")
                elseif btn == "RightButton" then
                    GameTooltip:Hide()
                    rowMenu(self, e)
                else
                    Map.ShowOnWorldMap(e.p.mapID)
                end
            end)
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e or e.header then return end
                local lines = { ns.Radar.Colored(e.name), Map.MapName(e.p.mapID) .. ("  |cff888888%.1f, %.1f|r"):format(e.p.x * 100, e.p.y * 100) }
                lines[#lines + 1] = Map.LayerLine(e.p)
                if e.dist then lines[#lines + 1] = L["Entfernung: "] .. fmtDist(e.dist) end
                lines[#lines + 1] = " "
                lines[#lines + 1] = "|cff888888" .. L["Klick: Weltkarte  ·  Rechtsklick: Ziel, Fluestern, Einladen"] .. "|r"
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            local head = e.header
            for _, f in ipairs({ r.cls, r.cols.name, r.cols.zone, r.arrow, r.cols.dist }) do f:SetShown(not head) end
            r.hTitle:SetShown(head ~= nil)
            r.hTwist:SetShown(head ~= nil)
            r.hInfo:SetShown(head ~= nil)
            if head then
                r.stripe:SetColorTexture(1, 1, 1, 0.05)
                r.hTwist:SetText(e.closed and "+" or "-")
                r.hTitle:SetText(e.g.name .. (e.g.mine and ("  |cffff1200" .. L["dein Gebiet"] .. "|r") or ""))
                local lo, hi = 99, 0
                for _, x in ipairs(e.g.list) do
                    local m = ns.Radar.byName[x.name]
                    local lv = m and m.level or 0
                    if lv > 0 then lo, hi = math.min(lo, lv), math.max(hi, lv) end
                end
                r.hInfo:SetText(#e.g.list .. "  " .. (hi > 0 and ("|cff666666" .. L["Stufe"] .. " " .. (lo == hi and lo or (lo .. "-" .. hi)) .. "|r") or ""))
                return
            end
            r.stripe:SetColorTexture(1, 1, 1, 0.022)
            local cls = ns.Radar.ClassOf(e.name)
            local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
            if tc then
                r.cls:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                r.cls:SetTexCoord(tc[1] + 0.01, tc[2] - 0.01, tc[3] + 0.01, tc[4] - 0.01)
                r.cls:Show()
            else
                r.cls:Hide()
            end
            local m = ns.Radar.byName[e.name]
            r.cols.name:SetText(ns.Radar.Colored(e.name) .. (m and m.level and m.level > 0 and ("  |cff888888" .. m.level .. "|r") or ""))
            r.cols.zone:SetText(("%.0f, %.0f"):format(e.p.x * 100, e.p.y * 100) .. "  |cff666666" .. ns.ago(ns.now() - math.floor(GetTime() - e.p.t)) .. "|r")
            if e.dist then
                local near = e.dist <= NEAR
                r.cols.dist:SetText(fmtDist(e.dist))
                r.cols.dist:SetTextColor(unpack(near and C.mint or C.text))
                r.arrow:Show()
                r.arrow:SetRotation(-(e.dir or 0))
                r.arrow:SetVertexColor(unpack(near and C.mint or C.muted))
            else
                r.cols.dist:SetText("")
                r.arrow:Hide()
            end
        end)
        list:SetPoint("TOPLEFT", 0, -98)
        list:SetPoint("BOTTOMRIGHT", -(SIDE + 12), 0)
        list.empty:SetText(L["Gerade teilt niemand seine Position.\nWer Oasis hat und 'Meine Position teilen' anlaesst, erscheint hier."])
        p.list = list

        -- Gebiete
        local zp = panel(p, L["Gebiete"])
        zp:SetPoint("TOPRIGHT", 0, -66)
        zp:SetPoint("BOTTOMRIGHT", 0, 146)
        zp:SetWidth(SIDE)
        p.zones = K.List(zp, 28, function(l)
            local r = K.Row(l)
            r:Col("name", 10, 150, 12)
            r.bar = K.Bar(r, 40, 3)
            r.bar:SetPoint("RIGHT", -34, 0)
            r:Col("n", 0, 24, 12, C.text, "RIGHT")
            r.cols.n:ClearAllPoints()
            r.cols.n:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnClick", function(self) if self.item then Map.ShowOnWorldMap(self.item.mapID) end end)
            return r
        end, function(r, g)
            r.cols.name:SetText(g.mine and ("|cffff1200" .. g.name .. "|r") or g.name)
            r.bar:Set(g.max > 0 and #g.list / g.max or 0)
            r.cols.n:SetText(#g.list)
        end)
        p.zones:SetPoint("TOPLEFT", 4, -32)
        p.zones:SetPoint("BOTTOMRIGHT", -4, 6)
        p.zones.empty:SetText(L["Noch keine Positionen."])

        -- Einstellungen
        local sp = panel(p, L["Einstellungen"])
        sp:SetPoint("BOTTOMRIGHT", 0, 0)
        sp:SetSize(SIDE, 164)
        local share = K.Toggle(sp, L["Meine Position teilen"], function() return ns.db.settings.shareMap end, function(v)
            ns.db.settings.shareMap = v
            lastKey = nil
            sendPos()
        end, L["Nur Gilde mit Oasis, nie in Instanzen"])
        share:SetPoint("TOPLEFT", 12, -32)
        share:SetWidth(SIDE - 24)
        local names = K.Toggle(sp, L["Namen auf der Weltkarte"], function() return ns.db.settings.mapNames end, function(v)
            ns.db.settings.mapNames = v
            Map.UpdateWorldPins()
        end)
        names:SetPoint("TOPLEFT", 12, -74)
        names:SetWidth(SIDE - 24)
        local dots = K.Toggle(sp, L["Punkte auf der Minimap"], function() return ns.db.settings.minimapDots end, function(v)
            ns.db.settings.minimapDots = v
            Map.UpdateMinimap()
        end)
        dots:SetPoint("TOPLEFT", 12, -102)
        dots:SetWidth(SIDE - 24)
        local heat = K.Toggle(sp, L["Heatmap auf der Weltkarte"], function() return ns.db.settings.mapHeat end, function(v)
            ns.db.settings.mapHeat = v
            Map.UpdateWorldPins()
        end)
        heat:SetPoint("TOPLEFT", 12, -130)
        heat:SetWidth(SIDE - 24)
        heat:HookScript("OnEnter", function(self)
            K.ShowTip(self, { L["Heatmap"], L["Wo sich die Gilde aufhaelt - aus deiner Position und allen geteilten Gilden-Positionen, jede Minute."],
                L["Hauptstaedte zaehlen weniger. Aeltere Werte verblassen langsam."] })
        end)
        heat:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end,
    refresh = function(p)
        local rows, groups = buildRows()
        p.list:SetData(rows)
        local total, mine, near, max = 0, 0, 0, 0
        for _, g in ipairs(groups) do
            total = total + #g.list
            if g.mine then mine = #g.list end
            max = math.max(max, #g.list)
            for _, e in ipairs(g.list) do if e.dist and e.dist <= NEAR then near = near + 1 end end
        end
        for _, g in ipairs(groups) do g.max = max end
        local fr = p.fresh
        p.cards[1]:Set(total, nil, nil, fr)
        p.cards[2]:Set(mine, nil, nil, fr)
        p.cards[3]:Set(near, nil, nil, fr)
        if fr then for i, c in ipairs(p.cards) do K.FadeIn(c, (i - 1) * 0.06) end p.fresh = false end
        p.zones:SetData(groups)
    end,
})

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    setupWorldMap()
    ns.After(5, sendPos)
    C_Timer.NewTicker(1, function()
        local now = GetTime()
        -- 0.6.139: laufe ich, oefter senden (fluessigere Punkte bei den anderen); im Stand wie eingestellt
        local mm, mx, my = ns.Camp.MyPosition()
        local moving = mm and Map.lastMoveX and (mm ~= Map.lastMoveMap or math.abs(mx - Map.lastMoveX) + math.abs(my - Map.lastMoveY) > 0.0004)
        Map.lastMoveMap, Map.lastMoveX, Map.lastMoveY = mm, mx, my
        if moving and Map.nextSend and Map.nextSend - now > 2.5 then Map.nextSend = now end
        if not Map.nextSend or now >= Map.nextSend then
            local guildMin = tonumber(ns.GuildOpt("mpMinInt")) or 3
            Map.nextSend = now + (moving and math.max(2.5, guildMin) or math.max(ns.db.settings.mapInterval or 8, guildMin))
            local ok, e = pcall(sendPos)
            if not ok then ns.err("Position", e) end
        end
        if Map.dirty and WorldMapFrame and WorldMapFrame:IsShown() then
            Map.dirty = false
            local ok, e = pcall(Map.UpdateWorldPins)
            if not ok then ns.err("Kartenpunkte", e) end
        end
    end)
    ns.Every(3, function() ns.RefreshPage("map") end)
    -- Minimap fluessig nachfuehren (Bewegung/Drehung), aber nur wenn es etwas zu zeigen gibt
    -- "gibt es gerade Lagerfeuer?" nur bei Aenderung bzw. alle 30 s pruefen statt 10x pro Sekunde
    local hasFires = false
    local fires = {}
    local function checkFires()
        fires = ns.Camp and ns.Camp.ActiveFires() or {}
        hasFires = fires[1] ~= nil
    end
    function Map.FiresCached() return fires end
    ns.Listen("STORE", function(coll) if coll == "campfires" then checkFires() end end)
    ns.Every(30, checkFires)
    checkFires()
    local mmTick = 0
    -- 0.5.929: 20x statt 4x pro Sekunde - Gildenpunkte, Lagerfeuer und Ziel hingen beim Laufen sichtbar nach
    C_Timer.NewTicker(0.05, function()
        -- 0.5.722: abgelaufene Positionen regelmaessig loeschen, sonst bleibt next(Map.pos) dauerhaft wahr und der Ticker arbeitet immer
        mmTick = mmTick + 1
        if mmTick % 100 == 0 and next(Map.pos) then
            local now = GetTime()
            for n, p in pairs(Map.pos) do if now - p.t >= EXPIRE then Map.pos[n] = nil end end
        end
        if mmTick % 4 == 0 and WorldMapFrame and WorldMapFrame:IsShown() and Map.Gliding() then
            local ok2, e2 = pcall(Map.UpdateWorldPins)
            if not ok2 then ns.err("Kartenpunkte", e2) end
        end
        if mmUsed == 0 and not next(Map.pos) and not Map.target and not hasFires then return end
        local ok, e = pcall(Map.UpdateMinimap)
        if not ok then ns.err("Minimap", e) end
    end)
end)
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" then setupWorldMap() end
end)
ns.On("ZONE_CHANGED_NEW_AREA", function() lastKey = nil end)
ns.Listen("STORE", function(coll) if coll == "campfires" then Map.dirty = true end end)

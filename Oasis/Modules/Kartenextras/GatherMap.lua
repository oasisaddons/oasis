-- Oasis: Gilden-Sammelkarte (wie GatherMate, aber mit der Gilde geteilt)
-- Wer Kraeuter pflueckt, Erz abbaut oder eine Truhe oeffnet, traegt den Fundort ein (Store "nodes").
-- Alle mit Oasis sehen die Punkte auf Weltkarte und Minimap. Gleicher Fundort (sehr nah, gleicher Name)
-- = ein Punkt, der mitzaehlt, wie oft er gefunden wurde.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Kartenextras", function()   -- Modul Karten-Extras (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local GM = {}
ns.Gather = GM

-- Sammel-Zauber (alle Raenge) -> Art
local SPELLS = {
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
    [3365] = "treasure", [6247] = "treasure", [6477] = "treasure", [6478] = "treasure", [22810] = "treasure",
    -- 0.5.935: Angeln (alle Raenge) und Schloss knacken (verschlossene Kisten)
    [7620] = "fish", [7731] = "fish", [7732] = "fish", [18248] = "fish",
    [1804] = "lock",
}
GM.KINDS = {
    herb = { name = "Kraeuter", icon = "Interface\\Icons\\INV_Misc_Flower_02", color = { 0.4, 0.86, 0.45 } },
    ore = { name = "Erz", icon = "Interface\\Icons\\INV_Ore_Copper_01", color = { 0.85, 0.65, 0.35 } },
    treasure = { name = "Schaetze", icon = "Interface\\Icons\\INV_Box_01", color = { 0.98, 0.82, 0.3 } },
    fish = { name = "Angelstellen", icon = "Interface\\Icons\\Trade_Fishing", color = { 0.36, 0.68, 0.98 } },
    lock = { name = "Schlosskisten", icon = "Interface\\Icons\\INV_Misc_Key_03", color = { 0.78, 0.6, 0.95 } },
    -- 0.5.936: besuchte Orte (MapExtras traegt sie ein). poi = nur Weltkarte, keine Route, kein Verblassen
    vendor = { name = "Haendler", icon = "Interface\\Icons\\INV_Misc_Bag_10", color = { 0.8, 0.8, 0.82 }, poi = true },
    repair = { name = "Reparatur", icon = "Interface\\Icons\\Trade_BlackSmithing", color = { 0.8, 0.8, 0.82 }, poi = true },
    mail = { name = "Briefkaesten", icon = "Interface\\Icons\\INV_Letter_15", color = { 0.8, 0.8, 0.82 }, poi = true },
    flight = { name = "Flugpunkte", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01", color = { 0.8, 0.8, 0.82 }, poi = true },
}
local NEAR = 0.006   -- Kartenanteil: naeher = gleicher Fundort

local function S() return ns.db.settings end
local function showKind(k) return not S()["gatherOff_" .. k] end
-- 0.5.935: ein Fundort ist sichtbar, wenn Art, Mindestzahl und der Filter je Sorte (Name) passen
local function shown(r)
    local k = GM.KINDS[r.kind]
    if not k then return false end
    if k.poi then return S().mapPoi ~= false end
    if S()["gatherOff_" .. r.kind] or (r.n or 1) < (S().gatherMinCount or 1) then return false end
    local hide = S().gatherHide
    if hide and r.name and r.name ~= "" and hide[r.name] then return false end
    return true
end
-- Frische: 1 = hoechstens einen Tag alt, faellt bis 0.4 nach 30 Tagen (abschaltbar)
local function freshness(r, now)
    if S().gatherFresh == false or (GM.KINDS[r.kind] or {}).poi then return 1 end
    local age = (now - (r.ts or 0)) / 86400
    if age <= 1 then return 1 end
    if age >= 30 then return 0.4 end
    return 1 - 0.6 * (age - 1) / 29
end
-- gerade abgeerntet: jemand hat dort in den letzten 5 Minuten gesammelt
local HARVEST, RESEND = 300, 600
local function harvested(r, now) return S().gatherHarvest ~= false and now - (r.ts or 0) < HARVEST and not (GM.KINDS[r.kind] or {}).poi end
GM.Shown, GM.Freshness, GM.Harvested = shown, freshness, harvested

------------------------------------------------------------------------
-- Fundorte merken
------------------------------------------------------------------------
local pending = {}   -- castGUID -> { kind, name }
-- 0.6.251: Sammeln auch am Zaubernamen erkennen - Clients mit anderen Zauber-IDs (z. B. Forever) speicherten sonst
-- nichts mehr. Die Namen kommen aus den bekannten IDs (in der Sprache des Clients).
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id) if ok and n then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id) if ok and n then return n end end
end
local byName
local function kindOf(spellID)
    if not spellID then return nil end
    if SPELLS[spellID] then return SPELLS[spellID] end
    if not byName then
        byName = {}
        for id, k in pairs(SPELLS) do local n = spellName(id) if n then byName[n] = k end end
    end
    local n = spellName(spellID)
    return n and byName[n] or nil
end
GM.KindOf = kindOf
-- letzte Zauber fuer /oa sammeltest (nur lokal, hoechstens 8)
GM.diag = {}
local function diag(spellID, kind, note)
    local d = GM.diag
    table.insert(d, 1, { t = time(), id = spellID, name = spellID and spellName(spellID) or "?", kind = kind, note = note })
    if #d > 8 then d[#d] = nil end
end
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, guid, spellID)
    if unit ~= "player" then return end
    spellID = ns.safe(spellID)
    local kind = kindOf(spellID)
    if not kind then return end
    pending[ns.safe(guid) or "x"] = { kind = kind, name = ns.safe(target) or "" }
end)
local function myPos()
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or x == 0 then return nil end
    return map, x, y
end
-- Index je Karte, neu nur wenn sich die Sammlung aendert (Performance 0.5.482: vorher jede Sekunde ein Scan
-- der ganzen "nodes"-Sammlung fuer die Minimap)
local byMap, allNodes
ns.Listen("STORE", function(coll) if coll == "nodes" then byMap, allNodes = nil, nil end end)
function GM.Nodes(map)
    if not byMap then
        byMap, allNodes = {}, {}
        for _, r in ipairs(Store.List("nodes", function(r) return r.kind end)) do
            allNodes[#allNodes + 1] = r
            local l = byMap[r.map]
            if not l then l = {} byMap[r.map] = l end
            l[#l + 1] = r
        end
    end
    if not map then return allNodes end
    return byMap[map] or {}
end
function GM.Record(kind, name)
    if ns.inInstance() then return "Instanz" end
    if ns.db.settings.shareNodes == false then return "Sammelorte teilen ist aus" end
    local map, x, y = myPos()
    if not map then return "keine Kartenposition" end
    -- schon bekannt?
    for _, r in ipairs(GM.Nodes(map)) do
        if r.kind == kind and (r.name == name or name == "") and math.abs(r.x - x) < NEAR and math.abs(r.y - y) < NEAR then
            -- hoechstens alle 10 Minuten neu senden (0.5.935: vorher 6 Stunden - fuer "gerade abgeerntet" braucht die Gilde
            -- den Zeitpunkt); der Zaehler "wie oft gefunden" steigt weiter nur alle 6 Stunden
            local age = ns.now() - (r.ts or 0)
            -- 0.6.384: Position mit jedem Abbau mitteln (man steht mal links, mal rechts vom Erz) -> wandert zur echten
            -- Mitte, also zum Fundort-Punkt des Spiels; hoechstens 8 Abbauten zaehlen, damit er noch nachruecken kann
            local m = math.min(8, (r.m or 1))
            local c = {} for k, v in pairs(r) do c[k] = v end
            c.x = math.floor(((r.x * m + x) / (m + 1)) * 10000) / 10000
            c.y = math.floor(((r.y * m + y) / (m + 1)) * 10000) / 10000
            c.m = m + 1
            if age > RESEND then
                if age > 6 * 3600 then c.n = (c.n or 1) + 1 end
                c.ts, c.by = ns.now(), ns.me()
                Store.Put("nodes", c)
            elseif Store.merge then
                Store.merge("nodes", c)   -- nur lokal, ohne Senden
            end
            return "schon bekannt"
        end
    end
    Store.Put("nodes", { id = ("nd-%s-%d-%d-%d"):format(kind, map, math.floor(x * 1000), math.floor(y * 1000)),
        kind = kind, name = name, map = map, x = math.floor(x * 10000) / 10000, y = math.floor(y * 10000) / 10000,
        n = 1, ts = ns.now(), by = ns.me() })
    if ns.Map and WorldMapFrame and WorldMapFrame:IsShown() then ns.Map.UpdateWorldPins() end
    return "neu gespeichert"
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, guid, spellID)
    if unit ~= "player" then return end
    spellID = ns.safe(spellID)
    local p = pending[ns.safe(guid) or "x"]
    if not p then
        local kind = kindOf(spellID)
        if not kind then diag(spellID, nil, "kein Sammelzauber") return end
        p = { kind = kind, name = "" }
    end
    pending[ns.safe(guid) or "x"] = nil
    local ok, res = pcall(GM.Record, p.kind, p.name)
    diag(spellID, p.kind, ok and res or ("Fehler: " .. tostring(res)))
end)
-- /oa sammeltest: letzte Zauber und was daraus wurde
ns.slash.sammeltest = function()
    local s = ns.db.settings
    local map, x, y = myPos()
    ns.print(("Sammeltest | Sammelorte teilen=%s | Instanz=%s | Karte=%s (%.3f, %.3f) | Fundorte gesamt=%d"):format(
        tostring(s.shareNodes ~= false), tostring(ns.inInstance()), tostring(map), x or 0, y or 0, #GM.Nodes()))
    -- 0.6.389: was die Weltkarte zeigt (Karte, sichtbare Fundorte, Schalter)
    local here, vis = GM.Nodes(map), 0
    for _, r in ipairs(here) do if shown(r) then vis = vis + 1 end end
    local wm = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
    ns.print(("  diese Karte: %d Fundorte, %d sichtbar | Weltkarte zeigt Karte %s (%d Fundorte) | Weltkarte an=%s | Mindestzahl=%s"):format(
        #here, vis, tostring(wm), wm and #GM.Nodes(wm) or 0, tostring(S().mapGather ~= false), tostring(S().gatherMinCount or 1)))
    if #GM.diag == 0 then ns.print("Noch kein Zauber seit dem Einloggen - einmal sammeln, dann nochmal /oa sammeltest.") end
    for _, d in ipairs(GM.diag) do
        ns.print(("  %s  Zauber %s (%s) -> %s: %s"):format(date("%H:%M:%S", d.t), tostring(d.id), tostring(d.name), tostring(d.kind or "-"), tostring(d.note)))
    end
end
ns.slash.gathertest = ns.slash.sammeltest

------------------------------------------------------------------------
-- Weltkarte (haengt sich an Oasis' Kartenebene) und Minimap
------------------------------------------------------------------------
local wPool, wUsed = {}, 0
local function wPin(canvas)
    wUsed = wUsed + 1
    local p = wPool[wUsed]
    if not p then
        p = CreateFrame("Frame", nil, canvas)
        p:SetSize(14, 14)
        -- 0.5.930: auch auf der Weltkarte rund - dunkle Scheibe dahinter, Symbol kreisfoermig zugeschnitten (vorher lag der
        -- Ring ueber einem eckigen Symbol, die Ecken standen heraus)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetTexture(ns.MEDIA .. "pindisc")   -- 0.5.932: eigene Texturen, die die Flaeche ganz fuellen (dot/ring sind kleiner und hauchduenn)
        p.bg:SetPoint("TOPLEFT", -3, 3) p.bg:SetPoint("BOTTOMRIGHT", 3, -3)
        p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- VOR der Maske setzen (SetTexCoord auf maskierter Textur wirft Fehler)
        if p.CreateMaskTexture and p.icon.AddMaskTexture then
            pcall(function()
                local m = p:CreateMaskTexture()
                m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(p.icon)
                p.icon:AddMaskTexture(m)
            end)
        end
        p.ring = p:CreateTexture(nil, "OVERLAY")
        p.ring:SetTexture(ns.MEDIA .. "pinring")
        p.ring:SetPoint("TOPLEFT", -3, 3) p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wPool[wUsed] = p
    end
    if p:GetParent() ~= canvas then p:SetParent(canvas) end
    return p
end
local function tipOf(r)
    local k = GM.KINDS[r.kind]
    return { K.hex(k.color) .. ((r.name ~= "" and r.name) or L[k.name]) .. "|r" .. (harvested(r, ns.now()) and ("  |cff999999" .. L["gerade abgeerntet"] .. "|r") or ""),
        (L["%dx gefunden"]):format(r.n or 1) .. "  ·  " .. L["zuletzt"] .. " " .. ns.ago(r.ts),
        "|cff888888" .. L["eingetragen von"] .. " " .. ns.displayName(r.by or "?") .. "|r" }
end
function GM.DrawWorld()
    for i = 1, wUsed do wPool[i]:Hide() end
    wUsed = 0
    if GM.HideRoute then GM.HideRoute() end
    if S().mapGather == nil then S().mapGather = not S().gatherWorldOff end
    if not S().mapGather or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    -- 0.5.933: Groesse, Deckkraft, Kreisrahmen und Mindestzahl einstellbar (Einstellungen > Bereiche > Karte)
    local s = (1 / math.max(cscale, 0.01)) * (S().gatherWorldScale or 1)
    if GM.DrawRoute then pcall(GM.DrawRoute, mapID, canvas, cw, ch, 1 / math.max(cscale, 0.01)) end
    local alpha, frame, tnow = S().gatherWorldAlpha or 1, not S().gatherRingOff, ns.now()
    for _, r in ipairs(GM.Nodes(mapID)) do
        local k = GM.KINDS[r.kind]
        if k and shown(r) then
            local p = wPin(canvas)
            local hv = harvested(r, tnow)
            p:SetAlpha(alpha * freshness(r, tnow))
            p.bg:SetShown(frame) p.ring:SetShown(frame)
            p.icon:SetTexture(k.icon)
            p.icon:SetDesaturated(hv)
            if hv then p.ring:SetVertexColor(0.5, 0.5, 0.5) else p.ring:SetVertexColor(k.color[1], k.color[2], k.color[3]) end
            p.tip = tipOf(r)
            p:SetScale(s)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", (r.x * cw) / s, (-r.y * ch) / s)
            p:SetFrameStrata(canvas:GetFrameStrata())
            p:SetFrameLevel(canvas:GetFrameLevel() + 55)
            p:Show()
        end
    end
end

-- Minimap: gleiche Rechnung wie Oasis' Gildenpunkte (Radius je Zoomstufe)
local MM_SIZE = {
    indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
    outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 6, [4] = 200, [5] = 133 + 1 / 3 },
}
local mPool, mUsed = {}, 0
local function mPin()
    mUsed = mUsed + 1
    local p = mPool[mUsed]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(14, 14)
        if ns.MiniPinLayer then ns.MiniPinLayer(p, 2) end
        -- 0.6.380: weicher Glanz, wenn der echte Fundort-Punkt im Ring liegt (Helligkeit ueber die Farbe, ADD)
        p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
        p.glow:SetTexture(ns.MEDIA .. "halo_ring")   -- 0.6.383: weicher Schein um den Ring, Mitte frei
        p.glow:SetBlendMode("ADD")
        p.glow:SetPoint("TOPLEFT", -14, 14) p.glow:SetPoint("BOTTOMRIGHT", 14, -14)
        p.glow:Hide()
        -- 0.5.929: Symbol im Kreis - dunkle Scheibe, rund zugeschnittenes Symbol, Ring in der Farbe der Art
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetTexture(ns.MEDIA .. "pindisc")   -- 0.5.932: eigene Texturen, die die Flaeche ganz fuellen (dot/ring sind kleiner und hauchduenn)
        p.bg:SetPoint("TOPLEFT", -3, 3) p.bg:SetPoint("BOTTOMRIGHT", 3, -3)
        p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- VOR der Maske setzen (SetTexCoord auf maskierter Textur wirft Fehler)
        if p.CreateMaskTexture and p.icon.AddMaskTexture then
            pcall(function()
                local m = p:CreateMaskTexture()
                m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(p.icon)
                p.icon:AddMaskTexture(m)
            end)
        end
        p.ring = p:CreateTexture(nil, "OVERLAY")
        p.ring:SetTexture(ns.MEDIA .. "pinring")
        p.ring:SetPoint("TOPLEFT", -3, 3) p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.rec then K.ShowTip(self, tipOf(self.rec)) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mPool[mUsed] = p
    end
    return p
end
local function cvar(n) return (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(n)) or (GetCVar and GetCVar(n)) end
local lastSig
-- 0.5.929: Die Symbole hingen beim Laufen nach (Neuzeichnen nur 1x pro Sekunde). Jetzt zwei Takte:
--   * einmal pro Sekunde: Fundorte in der Naehe heraussuchen (near) und die Spiel-Einstellungen lesen
--   * rund 30x pro Sekunde: nur diese wenigen Punkte neu setzen - und nur, wenn sich Position/Blick/Zoom geaendert hat
local near, nearAt, nearMap, cvRotate, cvZoom = {}, 0, nil, false, nil
function GM.DrawMinimap()
    if S().gatherMiniOff or not Minimap or ns.inInstance() then
        if GM.RouteArrow then GM.RouteArrow() end
        for i = 1, mUsed do mPool[i]:Hide() end
        mUsed, lastSig, nearAt = 0, nil, 0
        return
    end
    local map, mx, my = myPos()
    local now = GetTime()
    local w, h
    if map then w, h = C_Map.GetMapWorldSize(map) end
    if map and w and w > 0 and (now - nearAt >= 1 or map ~= nearMap) then
        nearAt, nearMap = now, map
        cvRotate, cvZoom = cvar("rotateMinimap") == "1", tonumber(cvar("minimapZoom"))
        for i = #near, 1, -1 do near[i] = nil end
        local reach = 360   -- Meter: groesster Minimap-Radius (233) plus Weg, den man in einer Sekunde zuruecklegt
        for _, r in ipairs(GM.Nodes(map)) do
            if shown(r) and not GM.KINDS[r.kind].poi then
                local dx, dy = (r.x - mx) * w, (r.y - my) * h
                if dx * dx + dy * dy < reach * reach then near[#near + 1] = r end
            end
        end
        lastSig = nil
    end
    -- nichts bewegt, gedreht, gezoomt und keine neue Liste: nichts tun
    local sig = map and (map .. ":" .. math.floor((mx or 0) * 200000) .. ":" .. math.floor((my or 0) * 200000) .. ":" .. (Minimap:GetZoom() or 0)
        .. ":" .. math.floor((ns.safe(GetPlayerFacing and GetPlayerFacing()) or 0) * 200) .. ":" .. #near) or "none"
    if sig == lastSig then return end
    lastSig = sig
    for i = 1, mUsed do mPool[i]:Hide() end
    mUsed = 0
    if not map or not w or w == 0 then if GM.RouteArrow then GM.RouteArrow() end return end
    local zoom = Minimap:GetZoom() or 0
    local indoors = (cvZoom == zoom) and "outdoor" or "indoor"
    local radius = (MM_SIZE[indoors][zoom] or 300) / 2
    local half = Minimap:GetWidth() / 2
    local facing = cvRotate and ns.safe(GetPlayerFacing and GetPlayerFacing()) or nil
    local sinF, cosF = 0, 1
    if facing then sinF, cosF = math.sin(facing), math.cos(facing) end
    local sc, alpha, frame, tnow = S().gatherMiniScale or 1, S().gatherMiniAlpha or 1, not S().gatherRingOff, ns.now()
    for _, r in ipairs(near) do
        local k = GM.KINDS[r.kind]
        if k then
            local dx, dy = (r.x - mx) * w, (r.y - my) * h
            if facing then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
            local nx, ny = dx / radius, dy / radius
            if nx * nx + ny * ny < 0.81 and (not ns.MiniPinVisible or ns.MiniPinVisible(nx * half, ny * half)) then   -- nur im Kreis, nicht am Rand stapeln; Mitte frei
                local p = mPin()
                local hv = harvested(r, tnow)
                if p.tex ~= k.icon or p.hv ~= hv then
                    p.icon:SetTexture(k.icon)
                    p.icon:SetDesaturated(hv)
                    p.tex, p.hv = k.icon, hv
                    if p.ring then
                        if hv then p.ring:SetVertexColor(0.5, 0.5, 0.5) else p.ring:SetVertexColor(k.color[1], k.color[2], k.color[3]) end
                    end
                end
                p.rec = r
                p:SetScale(sc)   -- Abstaende zaehlen im Massstab des Symbols -> durch sc teilen
                p:SetAlpha(alpha * freshness(r, tnow))
                -- 0.6.144: durchsichtig - ohne dunkle Scheibe, Bild halb durchsichtig, nur der Ring bleibt kraeftig.
                -- So sieht man darunter den echten Fundort-Punkt des Spiels (der liegt immer unter Addon-Symbolen).
                if p.bg then p.bg:SetShown(false) p.ring:SetShown(frame) end
                -- 0.6.378: in der Naehe (bis 80 m) nur ein duenner, halb durchsichtiger Ring - dort zeigt das Spiel den
                -- echten Fundort-Punkt, der immer unter Addon-Symbolen liegt; weiter weg Symbol + Ring wie bisher
                local rx, ry = (r.x - mx) * w, (r.y - my) * h
                local close = rx * rx + ry * ry < 80 * 80
                p.icon:SetAlpha(close and 0 or 0.45)
                -- 0.6.386: in der Naehe kein harter Ring (zeigt jeden kleinen Versatz zum echten Punkt), nur weicher Schein
                if p.ring then p.ring:SetAlpha(close and 0.35 or 1) p.ring:SetShown(frame or close) end   -- 0.6.388: nah: ganz zarter Ring
                p.close, p.kcol = close and not hv, k.color
                if p.glow then p.glow:SetShown(p.close and true or false) end
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", nx * half / sc, -ny * half / sc)
                p:Show()
            end
        end
    end
    if GM.RouteArrow then GM.RouteArrow(map, mx, my, w, h, radius, half, facing, sinF, cosF) end
end
-- nach geaenderten Einstellungen sofort neu zeichnen (sonst erst bei der naechsten Bewegung)
function GM.Refresh()
    lastSig, nearAt = nil, 0
    if GM.ResetRoutes then GM.ResetRoutes() end
    pcall(GM.DrawMinimap)
    pcall(GM.DrawWorld)
end
ns.Listen("LOGIN", function()
    if ns.Map and ns.Map.UpdateWorldPins then hooksecurefunc(ns.Map, "UpdateWorldPins", function() pcall(GM.DrawWorld) end) end
    -- fluessig mitlaufen: eigener Taktgeber (rund 30x pro Sekunde); DrawMinimap arbeitet nur, wenn sich etwas geaendert hat
    local driver, acc = CreateFrame("Frame"), 0
    driver:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.033 then return end
        acc = 0
        pcall(GM.DrawMinimap)
        -- 0.6.380: nahe Fundorte pulsieren (Ring + Glanz), unabhaengig vom Neuzeichnen
        local tt = GetTime()
        local k = 0.85 + 0.35 * math.sin(tt * 4)   -- 0.6.388: deutlich kraeftiger (war auf dunklem Grund kaum zu sehen)
        if ns.db and ns.db.settings.noAnim then k = 1 end
        for i = 1, mUsed do
            local pin = mPool[i]
            if pin and pin.close and pin.glow and pin.kcol then
                local c = pin.kcol
                pin.glow:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, 1)
            end
        end
    end)
end)
ns.Listen("STORE", function(coll) if coll == "nodes" and WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end end)
------------------------------------------------------------------------
-- Minimap-Helfer fuer andere Module (Rares, Marker ...): einmal je Takt den Zustand holen, dann Punkte umrechnen
------------------------------------------------------------------------
function GM.MiniCtx()
    if not Minimap or ns.inInstance() then return nil end
    local map, mx, my = myPos()
    if not (map and mx) then return nil end
    local w, h = C_Map.GetMapWorldSize(map)
    if not w or w == 0 then return nil end
    local zoom = Minimap:GetZoom() or 0
    local kind = (tonumber(cvar("minimapZoom")) == zoom) and "outdoor" or "indoor"
    local facing = cvar("rotateMinimap") == "1" and ns.safe(GetPlayerFacing and GetPlayerFacing()) or nil
    return { map = map, mx = mx, my = my, w = w, h = h, radius = (MM_SIZE[kind][zoom] or 300) / 2, half = Minimap:GetWidth() / 2,
        sinF = facing and math.sin(facing) or 0, cosF = facing and math.cos(facing) or 1 }
end
-- liefert: Versatz x, y (Pixel ab Minimap-Mitte), Abstand als Anteil des Radius (>= 0.9 = am Rand), Entfernung in Metern
function GM.MiniPlace(c, x, y)
    local dx, dy = (x - c.mx) * c.w, (y - c.my) * c.h
    local meters = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx * c.cosF - dy * c.sinF, dx * c.sinF + dy * c.cosF
    local nx, ny = dx / c.radius, dy / c.radius
    return nx * c.half, -ny * c.half, math.sqrt(nx * nx + ny * ny), meters
end

------------------------------------------------------------------------
-- Sammelroute (0.5.934): verbindet die sichtbaren Fundorte eines Gebiets zu einer Rundstrecke.
-- Weltkarte: Linie. Minimap: Pfeil zum naechsten Punkt (Linksklick ueberspringt, Rechtsklick geht zurueck).
-- Reihenfolge: naechster Nachbar, danach 2-opt (entwirrt Kreuzungen). Hoechstens 120 Punkte - die meistgefundenen.
------------------------------------------------------------------------
local ROUTE_MAX, ARRIVE = 120, 12
local routes = {}   -- je Karte: { sig, list, len, idx } - die Weltkarte zeigt oft ein anderes Gebiet als das eigene
local function routeNodes(map)
    local out = {}
    for _, r in ipairs(GM.Nodes(map)) do
        if shown(r) and not GM.KINDS[r.kind].poi then out[#out + 1] = r end
    end
    if #out > ROUTE_MAX then
        table.sort(out, function(a, b) if (a.n or 1) ~= (b.n or 1) then return (a.n or 1) > (b.n or 1) end return tostring(a.id) < tostring(b.id) end)
        for i = #out, ROUTE_MAX + 1, -1 do out[i] = nil end
    end
    return out
end
function GM.BuildTour(nodes, w, h)
    local n = #nodes
    if n < 2 then return nodes, 0 end
    local function d(a, b) local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h return math.sqrt(dx * dx + dy * dy) end
    local tour, used = { nodes[1] }, { true }
    for _ = 2, n do
        local last, best, bd = tour[#tour], nil, nil
        for j = 1, n do
            if not used[j] then
                local dj = d(last, nodes[j])
                if not bd or dj < bd then best, bd = j, dj end
            end
        end
        used[best] = true
        tour[#tour + 1] = nodes[best]
    end
    local improved, pass = true, 0
    while improved and pass < 25 do
        improved, pass = false, pass + 1
        for i = 1, n - 2 do
            for j = i + 2, n do
                local a, b, c, e = tour[i], tour[i + 1], tour[j], tour[(j % n) + 1]
                if a ~= e and d(a, c) + d(b, e) < d(a, b) + d(c, e) - 0.01 then
                    local lo, hi = i + 1, j
                    while lo < hi do tour[lo], tour[hi] = tour[hi], tour[lo] lo, hi = lo + 1, hi - 1 end
                    improved = true
                end
            end
        end
    end
    local len = 0
    for i = 1, n do len = len + d(tour[i], tour[(i % n) + 1]) end
    return tour, len
end
function GM.Route(map)
    if not map or not S().gatherRoute then return nil end
    local nodes = routeNodes(map)
    local sig = map .. ":" .. #nodes .. ":" .. (S().gatherMinCount or 1) .. ":" .. tostring(byMap)
        .. (showKind("herb") and "h" or "") .. (showKind("ore") and "o" or "") .. (showKind("treasure") and "t" or "")
    local route = routes[map]
    if route and route.sig == sig then return route end
    local w, h = C_Map.GetMapWorldSize(map)
    if not w or w == 0 then w, h = 1, 1 end
    local list, len = GM.BuildTour(nodes, w, h)
    route = { map = map, sig = sig, list = list, len = len }
    routes[map] = route
    return route
end
-- naechster Punkt der Route; rueckt weiter, sobald man dort ist
function GM.RouteTarget(map, mx, my, w, h)
    local rt = GM.Route(map)
    if not rt or #rt.list < 2 then return nil end
    local function dist(t) local dx, dy = (t.x - mx) * w, (t.y - my) * h return math.sqrt(dx * dx + dy * dy) end
    if not rt.idx or rt.idx > #rt.list then
        local bd
        for i, t in ipairs(rt.list) do local di = dist(t) if not bd or di < bd then rt.idx, bd = i, di end end
    end
    local t = rt.list[rt.idx]
    local dm = dist(t)
    if dm < ARRIVE then
        rt.idx = rt.idx % #rt.list + 1
        t = rt.list[rt.idx]
        dm = dist(t)
    end
    return t, dm, rt.idx, #rt.list
end
function GM.RouteSkip(step)
    local map = myPos()
    local rt = map and routes[map]
    if not (rt and rt.idx) then return end
    rt.idx = (rt.idx - 1 + step) % #rt.list + 1
    lastSig = nil
end

function GM.ResetRoutes() for _, rt in pairs(routes) do rt.sig = nil end end
local rFrame, rLines = nil, {}
function GM.HideRoute() for _, l in ipairs(rLines) do l:Hide() end end
function GM.DrawRoute(mapID, canvas, cw, ch, cs)
    GM.HideRoute()
    local rt = GM.Route(mapID)
    if not rt or #rt.list < 2 then return end
    if not rFrame then rFrame = CreateFrame("Frame", nil, canvas) end
    if rFrame:GetParent() ~= canvas then rFrame:SetParent(canvas) end
    rFrame:SetAllPoints(canvas)
    rFrame:SetFrameStrata(canvas:GetFrameStrata())
    rFrame:SetFrameLevel(canvas:GetFrameLevel() + 54)
    local n = #rt.list
    for i, a in ipairs(rt.list) do
        local b = rt.list[(i % n) + 1]
        local l = rLines[i]
        if not l then
            l = rFrame:CreateLine(nil, "ARTWORK")
            rLines[i] = l
        end
        local now = rt.idx and (i == (rt.idx - 2) % n + 1) or false   -- das Stueck zum naechsten Punkt heller
        l:SetColorTexture(1, 0.84, 0.36, now and 1 or 0.6)
        l:SetThickness(math.max(1, (now and 3 or 2) * cs))
        l:SetStartPoint("TOPLEFT", rFrame, a.x * cw, -a.y * ch)
        l:SetEndPoint("TOPLEFT", rFrame, b.x * cw, -b.y * ch)
        l:Show()
    end
end

local arrow
function GM.RouteArrow(map, mx, my, w, h, radius, half, facing, sinF, cosF)
    local t, dm, idx, total
    if map and mx and S().gatherRoute then t, dm, idx, total = GM.RouteTarget(map, mx, my, w, h) end
    if not t then if arrow then arrow:Hide() end return end
    if not arrow then
        arrow = CreateFrame("Button", nil, Minimap)
        arrow:SetSize(20, 20)
        arrow:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        arrow.sh = arrow:CreateTexture(nil, "BACKGROUND")
        arrow.sh:SetTexture(ns.MEDIA .. "pinarrow")
        arrow.sh:SetPoint("TOPLEFT", -3, 3) arrow.sh:SetPoint("BOTTOMRIGHT", 3, -3)
        arrow.sh:SetVertexColor(0, 0, 0, 0.85)
        arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
        arrow.tex:SetTexture(ns.MEDIA .. "pinarrow")
        arrow.tex:SetAllPoints()
        arrow.tex:SetVertexColor(1, 0.84, 0.36)
        arrow.txt = K.Text(arrow, 10, C.text)
        arrow.txt:SetPoint("TOP", arrow, "BOTTOM", 0, 1)
        arrow.txt:SetShadowOffset(1, -1)
        arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        arrow:SetScript("OnClick", function(_, btn) GM.RouteSkip(btn == "RightButton" and -1 or 1) pcall(GM.DrawMinimap) if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end end)
        arrow:SetScript("OnEnter", function(self)
            local r = self.rec
            local k = r and GM.KINDS[r.kind]
            K.ShowTip(self, { L["Naechster Fundort der Route"] .. (self.pos or ""),
                k and (K.hex(k.color) .. ((r.name ~= "" and r.name) or L[k.name]) .. "|r") or "",
                "|cff888888" .. L["Linksklick: ueberspringen  ·  Rechtsklick: zurueck"] .. "|r" })
        end)
        arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local dx, dy = (t.x - mx) * w, (t.y - my) * h
    if facing then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then arrow:Hide() return end
    -- Pfeil sitzt kurz vor dem Punkt (oder am Rand, wenn der Punkt ausserhalb liegt) und zeigt auf ihn
    local px = math.max(0, math.min(len / radius, 0.8) * half - 15)
    local ux, uy = dx / len, dy / len
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", Minimap, "CENTER", ux * px, -uy * px)
    local atan2 = math.atan2 or math.atan
    arrow.tex:SetRotation(atan2(-ux, -uy))
    arrow.sh:SetRotation(atan2(-ux, -uy))
    arrow.txt:SetText(math.floor(dm + 0.5) .. " m")
    arrow.rec, arrow.pos = t, ("  |cff888888%d/%d|r"):format(idx, total)
    arrow:Show()
end
ns.Listen("STORE", function(coll) if coll == "nodes" then for _, rt in pairs(routes) do rt.sig = nil end end end)

------------------------------------------------------------------------
-- Beispieldaten (0.5.931): Fundorte rund um den eigenen Standort, damit Minimap und Weltkarte etwas
-- zeigen. /oa demo erneut eingeben setzt sie an den neuen Standort. Nur lokal (Store.merge sendet nichts);
-- Demo.Remove raeumt alle "demo-"-Eintraege wieder weg.
------------------------------------------------------------------------
local DEMO_NODES = {   -- { Art, Richtung in Grad, Entfernung in Metern, wie oft gefunden }
    { "herb", 20, 35, 4 }, { "herb", 75, 70, 2 }, { "herb", 140, 55, 7 }, { "herb", 200, 110, 1 }, { "herb", 265, 45, 3 },
    { "herb", 320, 150, 5 }, { "herb", 100, 190, 2 }, { "herb", 300, 85, 6 },
    { "ore", 45, 60, 3 }, { "ore", 115, 125, 1 }, { "ore", 170, 30, 8 }, { "ore", 235, 95, 2 }, { "ore", 290, 170, 4 }, { "ore", 350, 65, 2 },
    { "treasure", 10, 100, 1 }, { "treasure", 155, 160, 1 }, { "treasure", 250, 140, 2 }, { "treasure", 215, 50, 1 },
}
function GM.SeedDemo()
    local map, mx, my = myPos()
    local w, h
    if map then w, h = C_Map.GetMapWorldSize(map) end
    if not (map and w and w > 0 and h and h > 0) then return 0 end
    local now, n = ns.now(), 0
    for i, d in ipairs(DEMO_NODES) do
        local a = math.rad(d[2])
        local x, y = mx + math.sin(a) * d[3] / w, my - math.cos(a) * d[3] / h
        if x > 0.01 and x < 0.99 and y > 0.01 and y < 0.99 then
            Store.merge("nodes", { id = "demo-nd-" .. i, demo = true, kind = d[1], name = "", map = map,
                x = math.floor(x * 10000) / 10000, y = math.floor(y * 10000) / 10000,
                n = d[4], ts = now - ((i == 3 or i == 11) and 60 or (i - 1) * 130000), u = now, by = ns.me() })   -- zwei "gerade abgeerntet", Rest bis ~25 Tage alt
            n = n + 1
        end
    end
    byMap, allNodes = nil, nil
    if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end
    return n
end
ns.Listen("LOGIN", function()
    local D = ns.Demo
    if D and not D.gatherHooked then
        D.gatherHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) GM.SeedDemo() end
        D.Remove = function(...)
            remove(...)
            byMap, allNodes = nil, nil
            if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end
        end
        if D.IsActive and D.IsActive() then ns.After(4, GM.SeedDemo) end
    end
end)
function GM.Count()
    local t = {}
    for k in pairs(GM.KINDS) do t[k] = 0 end
    for _, r in ipairs(GM.Nodes()) do if t[r.kind] then t[r.kind] = t[r.kind] + 1 end end
    return t
end
-- benannte Sorten (z. B. "Friedensblume", "Kupferader") mit Anzahl der Fundorte - fuer den Filter je Sorte
function GM.Names()
    local seen, out = {}, {}
    for _, r in ipairs(GM.Nodes()) do
        if GM.KINDS[r.kind] and r.name and r.name ~= "" then
            local e = seen[r.name]
            if not e then e = { name = r.name, kind = r.kind, n = 0 } seen[r.name] = e out[#out + 1] = e end
            e.n = e.n + 1
        end
    end
    table.sort(out, function(a, b) if a.kind ~= b.kind then return a.kind < b.kind end return a.name < b.name end)
    return out
end
end)

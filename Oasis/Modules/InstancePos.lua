-- Oasis - eigene Position in Instanzen (Dungeonkarte), auch wenn WoW dort UnitPosition/Kartenposition sperrt.
-- Stufen: a) direkte API (falls doch erlaubt)  b) Koppelnavigation aus Blickrichtung + Tempo
-- c) Neu-Verankern an bekannten Bossen (Ziel/Mouseover/Namensplakette/Kampfbeginn/Pluendern) und per
--    Rechtsklick "Ich bin hier"  d) Gruppe: geschaetzte Position an Oasis-Mitspieler (Addon-Nachricht IPOS, 1 s).
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C
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

local IP = {}
ns.InstancePos = IP

local DEF_WIDTH = 420        -- geschaetzte Kartenbreite in Yards, wenn nichts Besseres bekannt
local DRIFT = 0.08           -- Unsicherheit waechst um 8 % der Strecke
local MAX_ACC = 300
-- Eingaenge (Kartenanteil 0..1, Ebene) - nur wo auf dem Kartenbild ablesbar
local ENTRANCE = {
    ruinsoflordaeron = { 0.63, 0.24, 1 },
}

IP.cur = nil                 -- { dkey, floor, x, y, acc, src, face }
IP.party = {}
IP.caps = {}
local lastAnchor, trav
local hooked = {}

local function S(v) if v == nil then return nil end return ns.safe(v) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, 6)
end
local function inInstance()
    local ok, i, k = pcall(IsInInstance)
    return ok and S(i) and (k == "party" or k == "raid") and true or false
end
local function curDungeon()
    if ns.DungeonPos and ns.DungeonPos.CurDungeon then
        local ok, d, md = pcall(ns.DungeonPos.CurDungeon)
        if ok then return d, md end
    end
end
local function dkeyOf(d) return d and (d.dbKey or d.key) end
local function aspectOf(dkey)
    local md = ns.DungeonMapsData and ns.DungeonMapsData[dkey]
    if md and md.folder then return 1.5 end
    return (md and md.aspect) or 1
end
local function uiMapOf(dkey, floor)
    local list = ns.BossPos and ns.BossPos[dkey]
    if not list then return nil end
    local maps, seen = {}, {}
    for _, b in ipairs(list) do if b.map and not seen[b.map] then seen[b.map] = true maps[#maps + 1] = b.map end end
    table.sort(maps)
    return maps[tonumber(floor) or 1] or maps[1]
end
-- Kartenbreite in Yards: gelernt > Blizzard-Kartengroesse > Schaetzung * Faktor
function IP.Width(dkey, floor)
    local db = ns.db or {}
    local k = tostring(dkey) .. ":" .. tostring(floor or 1)
    if db.instPosScale and db.instPosScale[k] then return db.instPosScale[k], "gelernt" end
    local ui = uiMapOf(dkey, floor)
    if ui and C_Map and C_Map.GetMapWorldSize then
        local w = S(call(C_Map.GetMapWorldSize, ui))
        if type(w) == "number" and w > 50 then return w, "karte" end
    end
    return DEF_WIDTH * (tonumber(db.instPosFactor) or 1), "schaetzung"
end
local function norm(s) return (tostring(s or ""):lower():gsub("%s*%b()", ""):gsub("[^%w]", "")) end
local function pinFor(md, name)
    if not md or not md.pins or not name then return nil end
    local n = norm(name)
    for _, pin in ipairs(md.pins) do
        local p = norm(pin[1])
        if p == n or (#n > 3 and p:find(n, 1, true)) then return (pin[2] or 0) / 100, (pin[3] or 0) / 100, pin[4] or 1 end
    end
end
local function bossList(d)
    local D = ns.Dungeons
    if D and D.Bosses then local ok, l = pcall(D.Bosses, d) if ok and l then return l end end
    return d and d.bosses or {}
end
local function npcOf(guid)
    guid = S(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local function pinByNpc(npc)
    if not npc then return nil end
    local d, md = curDungeon()
    if not d then return nil end
    for _, b in ipairs(bossList(d)) do
        local bn = b.npc or (ns.DungeonNpc and ns.DungeonNpc[b.name or ""])
        if bn == npc then
            local x, y, f = pinFor(md, b.name)
            if not x and b.de then x, y, f = pinFor(md, b.de) end
            if x then return x, y, f, b.name end
        end
    end
    for _, b in ipairs((ns.BossPos and ns.BossPos[dkeyOf(d)]) or {}) do
        if b.npc == npc then
            local x, y, f = pinFor(md, b.boss)
            if x then return x, y, f, b.boss end
        end
    end
end
local function pinByName(name)
    local d, md = curDungeon()
    if not d or not name then return nil end
    local x, y, f = pinFor(md, name)
    if x then return x, y, f, name end
    for _, b in ipairs(bossList(d)) do
        if norm(b.de) == norm(name) or norm(b.name) == norm(name) then
            x, y, f = pinFor(md, b.name)
            if x then return x, y, f, b.name end
        end
    end
end

-- Position setzen (Anker). learn: Massstab aus der seit dem letzten Anker gekoppelten Strecke lernen.
function IP.Anchor(dkey, floor, x, y, acc, src, learn)
    if not dkey or not x then return end
    floor = tonumber(floor) or 1
    if learn and (acc or 10) <= 10 and lastAnchor and (lastAnchor.acc or 99) <= 15 and trav and lastAnchor.dkey == dkey and lastAnchor.floor == floor then
        local asp = aspectOf(dkey)
        local mx, my = x - lastAnchor.x, (y - lastAnchor.y) / asp
        local M = math.sqrt(mx * mx + my * my)
        local Dy = math.sqrt(trav[1] * trav[1] + trav[2] * trav[2])
        if M > 0.08 and Dy > 25 then
            local w = Dy / M
            if w > 150 and w < 3000 and ns.db then
                ns.db.instPosScale = ns.db.instPosScale or {}
                local k = dkey .. ":" .. floor
                local old = ns.db.instPosScale[k]
                ns.db.instPosScale[k] = old and (old * 0.5 + w * 0.5) or w
            end
        end
    end
    local face = IP.cur and IP.cur.face
    IP.cur = { dkey = dkey, floor = floor, x = math.max(0, math.min(1, x)), y = math.max(0, math.min(1, y)), acc = acc or 10, src = src or "manuell", face = face }
    lastAnchor = { dkey = dkey, floor = floor, x = IP.cur.x, y = IP.cur.y, acc = IP.cur.acc }
    trav = { 0, 0 }
end
function IP.SetManual(calKey, px, py)
    if not calKey or not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    local dkey, floor = tostring(calKey):match("^(.-):(%d+)$")
    if not dkey then return end
    IP.Anchor(dkey, tonumber(floor), px, py, 6, "manuell", true)
    ns.print(L["Position gesetzt - Oasis fuehrt sie jetzt mit (Rechtsklick korrigiert)."])
end
-- Rechtsklick auf eine Oasis-Kartenflaeche (canvas mit lrect)
function IP.ClickSet(canvas, calKey)
    local r = canvas and canvas.lrect
    if not r then return end
    local cx, cy = GetCursorPosition()
    local sc = canvas:GetEffectiveScale() or 1
    local px = (cx / sc - (canvas:GetLeft() or 0) - r[1]) / r[3]
    local py = ((canvas:GetTop() or 0) - cy / sc - r[2]) / r[4]
    IP.SetManual(calKey, px, py)
end
function IP.Reset() IP.cur, lastAnchor, trav = nil, nil, nil end

-- Kern: alle 0,1 s
function IP.Tick(dt)
    if not inInstance() then return end
    local d = curDungeon()
    local dkey = dkeyOf(d)
    if not dkey then return end
    if IP.cur and IP.cur.dkey ~= dkey then IP.Reset() end
    local face = S(call(GetPlayerFacing))
    local speed = S(call(GetUnitSpeed, "player"))
    if type(face) ~= "number" then face = nil end
    if type(speed) ~= "number" then speed = nil end
    IP.caps.face, IP.caps.speed = face ~= nil, speed ~= nil
    -- a) direkt
    if ns.DungeonPos and ns.DungeonPos.MyMapXY then
        local floor = (IP.cur and IP.cur.floor) or 1
        local ok, x, y = pcall(ns.DungeonPos.MyMapXY, dkey, floor)
        if ok and x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            IP.cur = { dkey = dkey, floor = floor, x = x, y = y, acc = 2, src = "api", face = face }
            return
        end
    end
    if not IP.cur then
        local e = ENTRANCE[dkey]
        if e then IP.Anchor(dkey, e[3], e[1], e[2], 15, "eingang") else return end
    end
    local c = IP.cur
    c.face = face
    if c.src == "api" then c.src = "koppel" end
    dt = dt or 0.1
    if speed and speed > 0 then
        local dist = speed * dt
        if face then
            local W = IP.Width(dkey, c.floor)
            local asp = aspectOf(dkey)
            local east, south = -math.sin(face) * dist, -math.cos(face) * dist
            c.x = math.max(0, math.min(1, c.x + east / W))
            c.y = math.max(0, math.min(1, c.y + south * asp / W))
            c.acc = c.acc + dist * DRIFT
            if trav then trav[1], trav[2] = trav[1] + east, trav[2] + south end
            if c.src ~= "koppel" and c.acc > 8 then c.src = "koppel" end
        else
            c.acc = c.acc + dist
            trav = nil
        end
    elseif speed == nil then
        c.acc = c.acc + 2 * dt
        trav = nil
    end
    if c.acc > MAX_ACC then c.acc = MAX_ACC end
end

-- Neu-Verankern an Bossen
local function tryUnit(unit, range)
    if not inInstance() then return end
    if not (UnitExists and S(call(UnitExists, unit))) then return end
    local x, y, f = pinByNpc(npcOf(call(UnitGUID, unit)))
    if not x then return end
    local dist = range
    if S(call(CheckInteractDistance, unit, 3)) then dist = 8
    elseif S(call(CheckInteractDistance, unit, 4)) then dist = 28 end
    if IP.cur and IP.cur.acc <= dist then return end
    IP.Anchor(dkeyOf(curDungeon()), f, x, y, dist, "boss", dist <= 28)
end
IP.TryUnit = tryUnit
ns.On("PLAYER_TARGET_CHANGED", function() tryUnit("target", 40) end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() tryUnit("mouseover", 40) end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) if unit then tryUnit(unit, 45) end end)
local function byEncounter(name, acc)
    if not inInstance() then return end
    local x, y, f = pinByName(S(name))
    if x and (not IP.cur or IP.cur.acc > acc) then IP.Anchor(dkeyOf(curDungeon()), f, x, y, acc, "boss", true) end
end
ns.On("ENCOUNTER_START", function(_, name) byEncounter(name, 25) end)
ns.On("BOSS_KILL", function(_, name) byEncounter(name, 20) end)
ns.On("LOOT_OPENED", function()
    if not inInstance() or not S(call(UnitIsDead, "target")) then return end
    local x, y, f = pinByNpc(npcOf(call(UnitGUID, "target")))
    if x then IP.Anchor(dkeyOf(curDungeon()), f, x, y, 5, "boss", true) end
end)
ns.On("PLAYER_ENTERING_WORLD", function() IP.Reset() end)

-- Gruppe
local sendAcc, lastSent = 0, ""
local function send()
    local c = IP.cur
    if not c or not ns.Comm or not inInstance() or not (IsInGroup and IsInGroup()) or ns.db.settings.shareInstPos == false then return end
    local msg = ("%s|%d|%.3f|%.3f|%d"):format(c.dkey, c.floor, c.x, c.y, c.acc)
    sendAcc = sendAcc + 1
    if msg == lastSent and sendAcc < 5 then return end
    lastSent, sendAcc = msg, 0
    ns.Comm.SendEx({ ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY" }, "IPOS", c.dkey, tostring(c.floor),
        ("%.3f"):format(c.x), ("%.3f"):format(c.y), tostring(math.floor(c.acc)), c.face and ("%.2f"):format(c.face) or "")
end
IP.Send = send
if ns.Comm and ns.Comm.On then
    ns.Comm.On("IPOS", function(sender, _, dkey, floor, x, y, acc, face)
        if not sender or (ns.isMe and ns.isMe(sender)) then return end
        -- Koordinaten 0..1, Zahlen endlich, Schluessel ohne Escape-Sequenzen
        x, y = SEC.Num(x, 0, 1), SEC.Num(y, 0, 1)
        if not x or not y or type(dkey) ~= "string" or #dkey > 60 or dkey:find("[|%c]") then return end
        IP.party[sender] = { dkey = dkey, floor = SEC.Num(floor, 1, 50, true) or 1, x = x, y = y, acc = SEC.Num(acc, 0, 10000) or 50,
            face = SEC.Num(face, -100, 100), t = GetTime() }
    end)
end

-- Text "x, y" fuer Koordinatenanzeigen
function IP.CoordText()
    local c = IP.cur
    if not c or not inInstance() then return nil end
    return ("%.1f, %.1f"):format(c.x * 100, c.y * 100)
end
local function srcText(c)
    if c.src == "api" then return L["direkt"] end
    if c.src == "manuell" then return L["manuell gesetzt"] end
    if c.src == "boss" then return L["am Boss verankert"] end
    if c.src == "eingang" then return L["ab Eingang"] end
    return L["geschaetzt"]
end
function IP.Status()
    local c = IP.cur
    if inInstance() and not IP.caps.face and not IP.caps.speed and not (c and c.src == "api") then
        local t = L["In dieser Instanz sperrt WoW Positionsdaten - nur manuell (Rechtsklick: Ich bin hier)"]
        if c then t = L["Du"] .. ": " .. IP.CoordText() .. "  ·  " .. t end
        return t
    end
    if not c then return L["Position unbekannt - Rechtsklick auf die Karte: Ich bin hier"] end
    return L["Du"] .. ": " .. (IP.CoordText() or "--") .. "  ·  " .. srcText(c) .. (" ±%d m"):format(math.floor(c.acc + 0.5))
        .. "  ·  " .. L["Rechtsklick: Ich bin hier"]
end

-- Zeichnen auf einer Oasis-Kartenflaeche (canvas.lrect); holder merkt sich die Widgets
local function widgets(canvas, holder)
    local w = holder.ipw
    if w then return w end
    w = {}
    local f = CreateFrame("Frame", nil, canvas)
    f:SetAllPoints(canvas)
    f:SetFrameLevel((canvas:GetFrameLevel() or 1) + 30)
    w.frame = f
    w.circle = f:CreateTexture(nil, "ARTWORK")
    w.circle:SetTexture(ns.MEDIA .. "dot")
    w.circle:SetVertexColor(0.3, 0.75, 1, 0.22)
    w.arrow = f:CreateTexture(nil, "OVERLAY", nil, 2)
    w.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    w.arrow:SetSize(28, 28)
    w.dot = f:CreateTexture(nil, "OVERLAY")
    w.dot:SetTexture(ns.MEDIA .. "dot")
    w.dot:SetSize(14, 14)
    w.party = {}
    w.status = K.Text(f, 11, C.text)
    w.status:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 8, 6)
    w.statusBg = f:CreateTexture(nil, "BACKGROUND")
    w.statusBg:SetColorTexture(0, 0, 0, 0.7)
    w.statusBg:SetPoint("TOPLEFT", w.status, "TOPLEFT", -6, 4)
    w.statusBg:SetPoint("BOTTOMRIGHT", w.status, "BOTTOMRIGHT", 6, -4)
    holder.ipw = w
    return w
end
function IP.HideOn(holder)
    local w = holder and holder.ipw
    if w then w.frame:Hide() end
end
function IP.DrawOn(canvas, holder, calKey, withStatus)
    local w = widgets(canvas, holder)
    w.frame:Show()
    w.circle:Hide() w.arrow:Hide() w.dot:Hide()
    for _, p in ipairs(w.party) do p:Hide() end
    local status = IP.Status()
    w.status:SetText(withStatus and status or "")
    w.status:SetShown(withStatus and true or false)
    w.statusBg:SetShown(withStatus and true or false)
    local r = canvas.lrect
    local dkey, floor = tostring(calKey or ""):match("^(.-):(%d+)$")
    floor = tonumber(floor)
    if not r or not dkey then return status end
    local W = IP.Width(dkey, floor)
    local ppy = r[3] / W
    local function at(tex, x, y)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", canvas, "TOPLEFT", r[1] + x * r[3], -(r[2] + y * r[4]))
    end
    local c = IP.cur
    if c and c.dkey == dkey and c.floor == floor then
        local sz = math.max(14, math.min(r[3] * 1.5, 2 * c.acc * ppy))
        w.circle:SetSize(sz, sz) at(w.circle, c.x, c.y) w.circle:Show()
        local _, cls = UnitClass("player")
        local cr, cg, cb = ns.classColor(cls)
        if c.face then
            at(w.arrow, c.x, c.y)
            pcall(w.arrow.SetRotation, w.arrow, c.face)
            w.arrow:Show()
        else
            w.dot:SetVertexColor(cr or 1, cg or 1, cb or 1) at(w.dot, c.x, c.y) w.dot:Show()
        end
    end
    local n, now = 0, GetTime()
    for name, p in pairs(IP.party) do
        if now - p.t < 8 and p.x and p.dkey == dkey and p.floor == floor then
            n = n + 1
            local d = w.party[n]
            if not d then
                d = CreateFrame("Frame", nil, w.frame)
                d:SetSize(14, 14)
                d.c = d:CreateTexture(nil, "OVERLAY")
                d.c:SetTexture(ns.MEDIA .. "dot")
                d.c:SetAllPoints()
                d.lbl = K.Text(d, 10, C.text, "CENTER")
                d.lbl:SetPoint("TOP", d, "BOTTOM", 0, -1)
                w.party[n] = d
            end
            local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
            local cr, cg, cb = ns.classColor(m and m.class)
            d.c:SetVertexColor(cr or 1, cg or 1, cb or 1)
            d.lbl:SetText(ns.displayName(name))
            d:ClearAllPoints()
            d:SetPoint("CENTER", canvas, "TOPLEFT", r[1] + p.x * r[3], -(r[2] + p.y * r[4]))
            d:Show()
        end
    end
    return status
end

-- Koordinatenzeilen (Komfort: "Du: --" unter Weltkarte/Minimap) in Instanzen mit Schaetzung fuellen
local function hookCoords()
    local CP = ns.ComfortPlus
    if not CP then return end
    for _, k in ipairs({ "wmCoords", "mmCoords" }) do
        local f = CP[k]
        if f and not hooked[f] and f.HookScript then
            hooked[f] = true
            local acc = 0
            f:HookScript("OnUpdate", function(self, el)
                -- hoechstens 5x pro Sekunde (vorher jedes Bild, auch im Kampf)
                acc = acc + (el or 0)
                if acc < 0.2 then return end
                acc = 0
                local t = IP.CoordText()
                if not t or not self.text then return end
                local old = self.text:GetText() or ""
                if old:find("--", 1, true) then self.text:SetText((old:gsub("%-%-", "~" .. t, 1))) end
            end)
        end
    end
end

local ticker = CreateFrame("Frame")
local acc, secAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, el)
    acc = acc + (el or 0)
    if acc < 0.1 then return end
    local dt = acc
    acc = 0
    local ok, e = pcall(IP.Tick, dt)
    if not ok and ns.debug then ns.debug("InstancePos", e) end
    secAcc = secAcc + dt
    if secAcc >= 1 then
        secAcc = 0
        pcall(send)
        pcall(hookCoords)
    end
end)

-- /oa probe instpos [skala <faktor> | reset]
local function probe(rest)
    local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    if cmd == "skala" then
        ns.db.instPosFactor = tonumber(arg) or 1
        ns.db.instPosScale = nil
        ns.print("instpos: Faktor " .. ns.db.instPosFactor)
        return
    elseif cmd == "reset" then IP.Reset() ns.print("instpos: zurueckgesetzt") return end
    local function v(x)
        if x == nil then return "nil" end
        if issecretvalue and issecretvalue(x) then return "|cffff5a4a(geheim)|r" end
        return tostring(x)
    end
    local function line(label, fn, ...)
        if type(fn) ~= "function" then ns.print("  " .. label .. ": |cff888888fehlt|r") return end
        local r = { pcall(fn, ...) }
        if not r[1] then ns.print("  " .. label .. ": |cffff5a4aFehler|r " .. tostring(r[2])) return end
        local out = {}
        for i = 2, math.max(2, #r) do out[#out + 1] = v(r[i]) end
        ns.print("  " .. label .. ": " .. table.concat(out, ", "))
    end
    ns.print("|cffe8b44a/oa probe instpos|r")
    line("IsInInstance", IsInInstance)
    line("UnitPosition player", UnitPosition, "player")
    line("GetBestMapForUnit", C_Map and C_Map.GetBestMapForUnit, "player")
    local best = C_Map and C_Map.GetBestMapForUnit and S(call(C_Map.GetBestMapForUnit, "player"))
    if best and C_Map.GetPlayerMapPosition then
        local pos = call(C_Map.GetPlayerMapPosition, best, "player")
        if pos and pos.GetXY then line("GetPlayerMapPosition", pos.GetXY, pos) else ns.print("  GetPlayerMapPosition: nil") end
    end
    line("GetPlayerFacing", GetPlayerFacing)
    line("GetUnitSpeed", GetUnitSpeed, "player")
    line("IsIndoors", IsIndoors) line("IsFalling", IsFalling) line("IsSwimming", IsSwimming)
    if Minimap then
        line("Minimap:GetPingPosition", Minimap.GetPingPosition, Minimap)
        line("Minimap:GetZoom", Minimap.GetZoom, Minimap)
    end
    line("CVar rotateMinimap", GetCVar, "rotateMinimap")
    if C_Minimap then line("C_Minimap.GetViewRadius", C_Minimap.GetViewRadius) end
    for i = 1, 4 do if UnitExists and UnitExists("party" .. i) then line("UnitPosition party" .. i, UnitPosition, "party" .. i) end end
    if C_Navigation then line("C_Navigation.GetDistance", C_Navigation.GetDistance) else ns.print("  C_Navigation: fehlt") end
    if C_SuperTrack then line("C_SuperTrack.IsSuperTrackingAnything", C_SuperTrack.IsSuperTrackingAnything) end
    local d = curDungeon()
    local dkey = dkeyOf(d)
    ns.print("  Oasis-Dungeon: " .. v(dkey))
    if dkey then
        local w, how = IP.Width(dkey, (IP.cur and IP.cur.floor) or 1)
        ns.print(("  Kartenbreite: %d Yards (%s), uiMap %s, Eingang %s"):format(w, how, v(uiMapOf(dkey, 1)), ENTRANCE[dkey] and "ja" or "nein"))
    end
    local c = IP.cur
    ns.print("  Schaetzung: " .. (c and (("%.1f, %.1f  ±%d  Quelle %s  Ebene %d"):format(c.x * 100, c.y * 100, c.acc, c.src, c.floor)) or "keine"))
    local n = 0 for _ in pairs(IP.party) do n = n + 1 end
    ns.print("  Gruppe (IPOS): " .. n .. "   Status: " .. IP.Status())
    ns.print("  |cff888888/oa probe instpos skala 1.3  (Karte groesser/kleiner)  |  reset|r")
end
ns.probes = ns.probes or {}
ns.probes.instpos = probe
IP.Probe = probe

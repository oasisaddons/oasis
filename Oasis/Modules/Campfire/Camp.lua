-- Oasis Modul 3: Lagerfeuer-Planer (Camping-Buffs, Hersteller, Lagerfeuer-Signale)
local ADDON, ns = ...
ns.ModuleFile("Oasis_Campfire", function()   -- Modul Lagerfeuer (abschaltbar, siehe ModuleLoader.lua)
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

local Camp = {}
ns.Camp = Camp
Camp.state = {}   -- [name] = { t, buffs = { [spellId] = expTs }, demo }

local FIRE_TIME = 900

------------------------------------------------------------------------
-- Eigene Buffs lesen (nur ausserhalb des Kampfes, Secret-Werte werden ignoriert)
------------------------------------------------------------------------
function Camp.MyBuffs()
    local out = {}
    if ns.inCombat() or not C_UnitAuras then return out end
    local now, gt = ns.now(), GetTime()
    for i = 1, 40 do
        local ok, a
        if C_UnitAuras.GetBuffDataByIndex then
            ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
        else
            ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        end
        if not ok or not a then break end
        local name, sid = ns.safe(a.name), ns.safe(a.spellId)
        local exp, icon = ns.safe(a.expirationTime), ns.safe(a.icon)
        if name and sid then
            local expTs = (exp and exp > 0) and math.floor(now + (exp - gt)) or 0
            out[#out + 1] = { name = name, id = sid, exp = expTs, icon = icon }
        end
    end
    return out
end

local function catalogIds()
    local ids = {}
    for _, r in ipairs(Store.List("campCatalog")) do ids[r.spell] = r end
    return ids
end

------------------------------------------------------------------------
-- Status teilen: welche Katalog-Buffs habe ich gerade?
------------------------------------------------------------------------
local lastSent = ""
local function shareState(force)
    if ns.inCombat() then return end
    local ids = catalogIds()
    local parts, mine = {}, {}
    for _, b in ipairs(Camp.MyBuffs()) do
        if ids[b.id] then
            parts[#parts + 1] = b.id .. "@" .. b.exp
            mine[b.id] = b.exp
        end
    end
    table.sort(parts)
    local s = table.concat(parts, "+")
    Camp.state[ns.me()] = { t = ns.now(), buffs = mine }
    if s ~= lastSent or force then
        lastSent = s
        Comm.SendEx({ ch = "GUILD", key = "cstate" }, "CSTATE", s)
        ns.RefreshPage("camp")
    end
end
Camp.shareState = shareState

Comm.On("CSTATE", function(sender, _, s)
    local buffs, n = {}, 0
    for id, exp in tostring(s or ""):sub(1, 1200):gmatch("(%d+)@(%d+)") do
        n = n + 1
        if n > 60 then break end
        id, exp = SEC.Num(id, 1, 1e8, true), SEC.Num(exp, 0, 4102444800, true)
        if id and exp then buffs[id] = exp end
    end
    Camp.state[sender] = { t = ns.now(), buffs = buffs }
    ns.RefreshPage("camp")
end)

-- neu eingeloggte Mitglieder bekommen unseren Stand
Comm.On("HELLOREQ", function()
    if not SEC.Rate("helloreq", 20) then return end   -- auf Zuruf hoechstens alle 20 s senden
    ns.After(math.random(20, 90) / 10, function() shareState(true) end)
end)

local auraPending
ns.On("UNIT_AURA", function(unit)
    if unit ~= "player" or auraPending then return end
    auraPending = true
    ns.After(4, function()
        auraPending = nil
        shareState()
        ns.RefreshPage("camp")
    end)
end)
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(2, shareState) end)

local function demoOn() return ns.Demo and ns.Demo.IsActive() end

-- wer hat Buff X gerade aktiv?
function Camp.ActiveHolders(spellId)
    local out, now = {}, ns.now()
    local demo = demoOn()
    for name, st in pairs(Camp.state) do
        local exp = st.buffs[spellId]
        if exp and (exp == 0 or exp > now) and (demo or not st.demo) then out[#out + 1] = { name = name, exp = exp } end
    end
    table.sort(out, function(a, b) return (a.exp == 0 and math.huge or a.exp) > (b.exp == 0 and math.huge or b.exp) end)
    return out
end

------------------------------------------------------------------------
-- Katalog
------------------------------------------------------------------------
function Camp.AddToCatalog(b, recipe)
    Store.Put("campCatalog", {
        id = "buff-" .. b.id, spell = b.id, name = b.name, icon = b.icon or 0, recipe = recipe or "",
    })
    ns.After(1, function() shareState(true) end)
end

-- Buffname in der eigenen Sprache (per Zauber-ID)
function Camp.BuffName(e)
    if e.spell and not e.demo and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, e.spell)
        if ok and ns.safe(n) then return n end
    end
    return e.name or "?"
end

-- Hersteller: aus den geteilten Rezepten (Name enthaelt Rezept- oder Buffname)
-- liefert Liste + Berufs-ID des ersten passenden Rezepts
function Camp.Makers(entry)
    local q = ((entry.recipe or "") ~= "" and entry.recipe or Camp.BuffName(entry)):lower()
    local out, prof = {}, nil
    if entry.makers then for m in tostring(entry.makers):gmatch("[^,]+") do out[ns.fullName(m)] = true end end
    if ns.Crafting then
        for _, e in ipairs(ns.Crafting.Index()) do
            if e.name:lower():find(q, 1, true) then
                prof = prof or e.prof
                for _, m in ipairs(e.crafters) do out[m] = true end
            end
        end
    end
    local list = {}
    for m in pairs(out) do list[#list + 1] = m end
    local on = ns.Radar and ns.Radar.IsOnline
    table.sort(list, function(a, b)
        local oa, ob = on and on(a) and 1 or 0, on and on(b) and 1 or 0
        if oa ~= ob then return oa > ob end
        return a < b
    end)
    return list, prof
end

local function onlineCount(list)
    local n = 0
    if not (ns.Radar and ns.Radar.IsOnline) then return 0 end
    for _, m in ipairs(list) do if ns.Radar.IsOnline(m) then n = n + 1 end end
    return n
end

------------------------------------------------------------------------
-- Lagerfeuer-Signal
------------------------------------------------------------------------
-- 0.6.275: steht jetzt allgemein in Core.lua (ns.MyMapPosition), hier nur noch der alte Name
Camp.MyPosition = ns.MyMapPosition

ns.GuildOption({ page = "camp", key = "cpTime", default = 15, min = 5, max = 60, step = 5,
    label = "Dauer eines Lagerfeuers", desc = "So lange bleibt ein gemeldetes Lagerfeuer fuer die Gilde auf der Karte.",
    fmt = function(v) return v .. " Min" end })
local function fireTime() return (tonumber(ns.GuildOpt("cpTime")) or FIRE_TIME / 60) * 60 end

function Camp.Signal(note)
    if ns.inInstance() then ns.print(L["In Instanzen gibt es keine Kartenposition."]) return end
    local mapID, x, y = Camp.MyPosition()
    if not mapID then ns.print(L["Position nicht verfuegbar."]) return end
    Store.Put("campfires", {
        id = "fire-" .. ns.short(ns.me()), mapID = mapID, x = math.floor(x * 10000), y = math.floor(y * 10000),
        zone = ns.safe(GetRealZoneText()) or "", sub = ns.safe(GetSubZoneText()) or "",
        note = note or "", exp = ns.now() + fireTime(), start = ns.now(),
    })
    local mins = math.floor(fireTime() / 60)
    local msg = (mins == 15) and L["Die Gilde sieht dein Feuer 15 Minuten auf der Karte."] or (L["Die Gilde sieht dein Feuer %d Minuten auf der Karte."]):format(mins)
    if ns.db.settings.campOwnToast ~= false then K.Toast(L["Lagerfeuer gemeldet"], msg, C.pink) end
    if ns.Badges then ns.Badges.Add("campfires", 1) end
end
ns.slash.lagerfeuer = function(rest) Camp.Signal(rest) end

------------------------------------------------------------------------
-- Automatisch melden (Einstellung campAuto, Standard an):
--  1. ich zuende selbst ein Lagerfeuer an (Zauber, dessen Name "Lagerfeuer"/"Campfire" enthaelt - ohne feste ID)
--  2. ich bekomme einen Lagerfeuer-Buff (Katalog oder Name mit Feuer), und in der Naehe ist noch kein Feuer
--     gemeldet -> jemand (auch ohne Oasis) hat hier ein Feuer -> fuer die Gilde eintragen
------------------------------------------------------------------------
local FIRE_WORDS = { "lagerfeuer", "campfire", "feu de camp", "hoguera", "fogueira", "falò", "костёр", "костер" }
local function isFireName(n)
    n = tostring(n or ""):lower()
    if n == "" then return false end
    for _, w in ipairs(FIRE_WORDS) do if n:find(w, 1, true) then return true end end
    return false
end
local function autoOn() return ns.db and ns.db.settings.campAuto ~= false end
-- schon ein Feuer (von mir oder der Gilde) in der Naehe?
local function fireNearby()
    local mapID, x, y = Camp.MyPosition()
    if not mapID then return true end   -- ohne Position nichts melden
    for _, r in ipairs(Camp.ActiveFires()) do
        if r.mapID == mapID and not r.demo then
            local dx, dy = (r.x or 0) / 10000 - x, (r.y or 0) / 10000 - y
            if dx * dx + dy * dy < 0.012 * 0.012 then return true end
        end
    end
    return false
end
local lastAuto = 0
local function autoSignal(why)
    if not autoOn() or ns.inInstance() or ns.now() - lastAuto < 120 then return end
    if fireNearby() then return end
    lastAuto = ns.now()
    pcall(Camp.Signal, why == "spell" and "" or L["automatisch erkannt"])
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not autoOn() then return end
    spellID = ns.safe(spellID)
    if not spellID then return end
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
    if isFireName(ns.safe(name)) then
        -- eigenes Feuer: immer melden (auch wenn in der Naehe schon eins steht, ersetzt mein altes)
        lastAuto = ns.now()
        ns.After(1, function() pcall(Camp.Signal, "") end)
    end
end)
local hadFireBuff = false
-- gebuendelt: hoechstens alle 0,5 s pruefen (vorher bei JEDER Auren-Aenderung 40 Auren-Abfragen)
local function fireBuffCheck()
    if not autoOn() or ns.inCombat() then return end
    local ids = catalogIds()
    local has = false
    for _, b in ipairs(Camp.MyBuffs()) do
        if ids[b.id] or isFireName(b.name) then has = true break end
    end
    if has and not hadFireBuff then ns.After(2, function() autoSignal("buff") end) end
    hadFireBuff = has
end
ns.On("UNIT_AURA", function(unit)
    if unit ~= "player" or not autoOn() or ns.inCombat() then return end
    ns.Debounce("campAura", 0.5, fireBuffCheck)
end)

function Camp.MyFire()
    local r = Store.Get("campfires", "fire-" .. ns.short(ns.me()))
    if r and not r.del and (r.exp or 0) > ns.now() then return r end
end
function Camp.Extinguish()
    local r = Camp.MyFire()
    if not r then return end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.exp = ns.now()
    Store.Put("campfires", copy)
end

local function sortFires(out)
    table.sort(out, function(a, b) return (a.exp or 0) > (b.exp or 0) end)
    return out
end
function Camp.ActiveFires()
    local now, demo = ns.now(), demoOn()
    return sortFires(Store.List("campfires", function(r) return (r.exp or 0) > now and (demo or not r.demo) end))
end
-- alle Feuer der letzten Stunde (auch erloschene)
function Camp.AllFires()
    local demo = demoOn()
    return sortFires(Store.List("campfires", function(r) return demo or not r.demo end))
end

local quietStore
ns.Listen("STORE", function(coll, rec, old)
    if coll == "campfires" and not quietStore and not rec.del and rec.by ~= ns.me() and (rec.exp or 0) > ns.now()
        and not (old and (old.exp or 0) > ns.now())
        and not (ns.db.settings.campZoneOnly and rec.mapID ~= (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))) then
        ns.Sound.Next("camp")
        K.Toast(L["Lagerfeuer von "] .. ns.displayName(rec.by), ns.zoneName(rec.mapID, rec.zone) .. ((rec.note or "") ~= "" and (" - " .. rec.note) or ""), C.pink,
            function() if ns.Map then ns.Map.ShowOnWorldMap(rec.mapID) end end)
    end
    if coll == "campfires" or coll == "campCatalog" then ns.RefreshPage("camp") end
end)

------------------------------------------------------------------------
-- Demo-Daten (nur lokal, wie Demo.lua)
------------------------------------------------------------------------
local DEMO_BUFFS = {
    -- id, Name, Symbol, Rezept, Beruf, Wirkung, Hersteller, aktiv bei (Name = Restminuten, 0 = ohne Ablauf)
    { 990101, "Deftiger Lagerfeuer-Eintopf", "Interface\\Icons\\INV_Misc_Food_65", "Lagerfeuer-Eintopf", 185, "+12 Ausdauer und +6 Willenskraft, 30 Min", "Hoknar,Nakira,Mokrash", { Grukthar = 22, Hoknar = 25, Tavira = 11, ["Zul'mira"] = 25 } },
    { 990102, "Geschaerfte Klingen", "Interface\\Icons\\INV_Stone_02", "Schleifstein am Feuer", 164, "+8 Waffenschaden fuer Nahkaempfer, 30 Min", "Grukthar,Drogbar", { Grukthar = 18, Mokrash = 18 } },
    { 990103, "Waermende Decken", "Interface\\Icons\\INV_Fabric_Wool_03", "Lagerdecke", 197, "Ausgeruht sammelt sich 50 % schneller", "Zul'mira,Tavira", { Tavira = 0 } },
    { 990104, "Kraeuterdampf", "Interface\\Icons\\INV_Misc_Herb_07", "Kraeuteraufguss", 171, "+5 % Heilung erhalten, 20 Min", "Hoknar", {} },
    { 990105, "Gegerbte Polster", "Interface\\Icons\\INV_Misc_LeatherScrap_03", "Polsterlager", 165, "+60 Ruestung, 30 Min", "Mokrash", { ["Zul'mira"] = 9 } },
    { 990106, "Funkenschutz", "Interface\\Icons\\INV_Gizmo_02", "Funkenschirm", 202, "+15 Feuerwiderstand, 30 Min", "", {} },
    { 990107, "Runenglut", "Interface\\Icons\\INV_Enchant_ShardGlimmeringSmall", "Glutrune", 333, "+4 Intelligenz und +4 Willenskraft, 30 Min", "Tavira,Zul'mira", { Tavira = 27, Hoknar = 4 } },
}
local DEMO_FIRES = {
    -- Wer, mapID, x, y, Gebiet, Unterzone, Notiz, Rest (s), seit (s)
    { "Hoknar", 1413, 0.516, 0.297, "Brachland", "Das Wegekreuz", "Eintopf + Kraeuterdampf, kommt vorbei", 640, 260 },
    { "Tavira", 1441, 0.463, 0.512, "Tausend Nadeln", "Freiwindposten", "Runenglut fuer Caster", 380, 520 },
    { "Grukthar", 1411, 0.522, 0.431, "Durotar", "Klingenhuegel", "Schmiede-Pause, Klingen schaerfen", 820, 80 },
    { "Mokrash", 1442, 0.451, 0.595, "Steinkrallengebirge", "Sonnenfels", "", -900, 1800 },
    { "Nakira", 1454, 0.545, 0.683, "Orgrimmar", "Tal der Ehre", "Kochabend", -2100, 3000 },
}
local DEMO_SPOTS = {
    { 1413, 0.516, 0.297, "Brachland", "Das Wegekreuz" }, { 1413, 0.622, 0.371, "Brachland", "Ratschet" },
    { 1411, 0.522, 0.431, "Durotar", "Klingenhuegel" }, { 1440, 0.735, 0.604, "Eschental", "Splintertreeposten" },
    { 1441, 0.463, 0.512, "Tausend Nadeln", "Freiwindposten" }, { 1424, 0.620, 0.200, "Vorgebirge des Huegellands", "Tarrens Muehle" },
}
local DEMO_NOTES = { "Kochen + Schmieden, kommt vorbei", "Eintopf fuer alle", "kurze Pause vor dem Dungeon", "Runenglut, wer mag?", "", "Treffpunkt fuer die Gruppe" }

local function demoPut(coll, rec)
    rec.demo = true
    rec.u = rec.u or ns.now()
    quietStore = true
    Store.merge(coll, rec)
    quietStore = false
end

function Camp.SeedDemo()
    local now = ns.now()
    for i, b in ipairs(DEMO_BUFFS) do
        demoPut("campCatalog", { id = "demo-camp-" .. i, spell = b[1], name = L[b[2]], icon = b[3], recipe = L[b[4]], prof = b[5],
            desc = L[b[6]], makers = b[7], by = ns.fullName(i % 2 == 0 and "Grukthar" or "Hoknar") })
        for who, min in pairs(b[8]) do
            local key = ns.fullName(who)
            local st = Camp.state[key] or { t = now, buffs = {}, demo = true }
            st.buffs[b[1]] = min == 0 and 0 or now + min * 60
            Camp.state[key] = st
        end
    end
    for i, f in ipairs(DEMO_FIRES) do
        demoPut("campfires", { id = "demo-fire-" .. i, by = ns.fullName(f[1]), mapID = f[2], x = math.floor(f[3] * 10000), y = math.floor(f[4] * 10000),
            zone = f[5], sub = L[f[6]], note = L[f[7]], exp = now + f[8], start = now - f[9], u = now - f[9] })
    end
    ns.RefreshPage("camp")
end

function Camp.RemoveDemo()
    for name, st in pairs(Camp.state) do if st.demo then Camp.state[name] = nil end end
    ns.RefreshPage("camp")
end

-- Live: ab und zu zuendet jemand ein neues Feuer an
local function demoTick()
    if not demoOn() or math.random() > 0.35 then return end
    if #Store.List("campfires", function(r) return r.demo and (r.exp or 0) > ns.now() end) >= 4 then return end
    local who = ({ "Hoknar", "Tavira", "Grukthar", "Zul'mira", "Mokrash", "Nakira", "Yenzi", "Drogbar" })[math.random(1, 8)]
    local s = DEMO_SPOTS[math.random(1, #DEMO_SPOTS)]
    Store.merge("campfires", { id = "demo-fire-live-" .. ns.short(ns.fullName(who)), demo = true, u = ns.now(), by = ns.fullName(who),
        mapID = s[1], x = math.floor(s[2] * 10000), y = math.floor(s[3] * 10000), zone = s[4], sub = L[s[5]],
        note = L[DEMO_NOTES[math.random(1, #DEMO_NOTES)]], exp = ns.now() + FIRE_TIME, start = ns.now() })
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local view, catFilter, catSearch, selected = "home", "all", "", nil
local recipeBox

local function remaining(exp)
    if not exp or exp == 0 then return L["ohne Ablauf"] end
    local d = exp - ns.now()
    if d <= 0 then return L["abgelaufen"] end
    if d >= 3600 then return (L["%d Std"]):format(d / 3600) end
    return (L["%d Min"]):format(math.ceil(d / 60))
end

local function panel(parent, title)
    local f = K.Panel(parent, C.panel)
    f.head = K.GameHead(f, title, C.amber)
    f.head:SetPoint("TOPLEFT", 12, -12)
    f.head:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    return f
end

local function profIcon(id, size, c)
    if not id or not ns.Radar or not ns.Radar.ProfIcon then return "" end
    return ns.Radar.ProfIcon({ id = id }, size or 13, c)
end

local function buffIcon(e) return (e.icon and e.icon ~= 0) and e.icon or 134400 end

local function whisper(name) if name then ns.Whisper(name) end end

local function fireRow(l, withButtons)
    local r = K.Row(l)
    r.glyph = K.Glyph(r, 18, ns.MEDIA .. "icons\\camp", C.accent)
    r.glyph:SetPoint("LEFT", 10, 0)
    r.cols.zone = K.Text(r, 12, C.text)
    r.cols.zone:SetPoint("TOPLEFT", 38, -6)
    r.cols.zone:SetPoint("RIGHT", r, "RIGHT", -150, 0)
    r.cols.meta = K.Text(r, 11, C.muted)
    r.cols.meta:SetPoint("BOTTOMLEFT", 38, 6)
    r.cols.meta:SetPoint("RIGHT", r, "RIGHT", -150, 0)
    r.cols.rem = K.Text(r, 11, C.pink, "RIGHT")
    r.cols.rem:SetPoint("TOPRIGHT", -78, -7)
    r.bar = K.Bar(r, 60, 3)
    r.bar:SetPoint("TOPRIGHT", r.cols.rem, "BOTTOMRIGHT", 0, -4)
    r.map = K.Button(r, L["Karte"], 62, 22, "ghost")
    r.map:SetPoint("RIGHT", -8, 0)
    r.map.label:SetFont(K.FONT, 11, "")
    r:SetScript("OnEnter", function(self)
        local f = self.item
        if not f then return end
        local lines = { ns.zoneName(f.mapID, f.zone) .. ((f.sub or "") ~= "" and (" - " .. f.sub) or ""),
            L["Angezuendet von "] .. ns.Radar.Colored(f.by) }
        if (f.note or "") ~= "" then lines[#lines + 1] = "|cffc8c8c8" .. f.note .. "|r" end
        if f.x and f.y then lines[#lines + 1] = ("|cff888888%.1f, %.1f|r"):format(f.x / 100, f.y / 100) end
        lines[#lines + 1] = " "
        lines[#lines + 1] = L["Rechtsklick: anfluestern"]
        K.ShowTip(self, lines)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:RegisterForClicks("AnyUp")
    r:SetScript("OnClick", function(self, btn) if btn == "RightButton" and self.item then whisper(self.item.by) end end)
    return r
end

local function fireUpdate(r, f)
    local now = ns.now()
    local live = (f.exp or 0) > now
    r:SetAlpha(live and 1 or 0.45)
    r.glyph:SetVertexColor(unpack(live and C.accent or C.dim))
    r.cols.zone:SetText(ns.zoneName(f.mapID, f.zone) .. ((f.sub or "") ~= "" and (" |cff777777- " .. f.sub .. "|r") or ""))
    r.cols.meta:SetText(ns.Radar.Colored(f.by) .. ((f.note or "") ~= "" and ("  |cff999999" .. f.note .. "|r") or ""))
    if live then
        r.cols.rem:SetText((L["noch %s"]):format(remaining(f.exp)))
        r.cols.rem:SetTextColor(unpack(C.pink))
        r.bar:Show()
        r.bar:Set((f.exp - now) / FIRE_TIME)
    else
        r.cols.rem:SetText((L["erloschen %s"]):format(ns.ago(f.exp)))
        r.cols.rem:SetTextColor(unpack(C.dim))
        r.bar:Hide()
    end
    r.map:SetScript("OnClick", function() if ns.Map then ns.Map.ShowOnWorldMap(f.mapID) end end)
end

local function catalogList()
    local list = {}
    for _, e in ipairs(Store.List("campCatalog", function(r) return demoOn() or not r.demo end)) do
        local holders = Camp.ActiveHolders(e.spell)
        local makers, prof = Camp.Makers(e)
        e._n, e._makers, e._prof = #holders, makers, e.prof or prof
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        if a._n ~= b._n then return a._n > b._n end
        return Camp.BuffName(a) < Camp.BuffName(b)
    end)
    return list
end

local function selectBuff(p, e)
    selected = e and e.id or nil
    view = "catalog"
    p.seg:Select("catalog")
    ns.RefreshPage("camp")
end

ns.RegisterPage({
    key = "camp", title = "Lagerfeuer", order = 3,
    sub = "Camping-Buffs koordinieren: wer baut was, wer hat was aktiv, wo brennt gerade ein Feuer",
    build = function(p)
        p.seg = K.Segments(p, { { key = "home", text = L["Uebersicht"] }, { key = "catalog", text = L["Buff-Katalog"] },
            { key = "fires", text = L["Feuer"] } }, function(k) view = k ns.RefreshPage("camp") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.lightTop = K.Button(p, L["Hier brennt ein Lagerfeuer"], 190, 24, "primary", function() Camp.Signal("") end)
        p.lightTop:SetPoint("TOPRIGHT", 0, 0)

        ----------------------------------------------------------------
        -- Uebersicht
        ----------------------------------------------------------------
        p.home = CreateFrame("Frame", nil, p)
        p.home:SetPoint("TOPLEFT", 0, -40)
        p.home:SetPoint("BOTTOMRIGHT")
        p.cards = {}
        -- Kacheln wie auf den anderen Seiten (Zahl zaehlt hoch, farbige Kante)
        local TD = { { ns.ICONS.camp, "Feuer brennen", C.red }, { ns.ICONS.crafting, "Buffs im Katalog", C.amber },
            { ns.ICONS.social, "Aktive Buffs (Gilde)", C.mint }, { ns.ICONS.badges, "Deine Katalog-Buffs", C.blue } }
        for i, d in ipairs(TD) do
            local c = K.HudTile(p.home, d[1], L[d[2]], d[3])
            c:SetHeight(62)
            c:Hide()   -- Kennzahlen-Kacheln entfallen; die Zahlen stehen in den Karten-Ueberschriften
            p.cards[i] = c
        end
        local function layoutCards(w)
            local tw = math.floor(((w or 750) - 30) / 4)
            for i, c in ipairs(p.cards) do
                c:SetWidth(tw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
            end
        end
        p.home:HookScript("OnSizeChanged", function(_, w) layoutCards(w) end)
        layoutCards(p.home:GetWidth())
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true

        -- brennt gerade
        local fp = panel(p.home, L["Brennt gerade"])
        fp:SetPoint("TOPLEFT", 0, 0)
        fp:SetSize(370, 200)
        p.homeFires = K.List(fp, 42, function(l) return fireRow(l) end, fireUpdate)
        p.homeFires:SetPoint("TOPLEFT", 4, -32)
        p.homeFires:SetPoint("BOTTOMRIGHT", -4, 6)
        p.homeFires.empty:SetText(L["Gerade kein Lagerfeuer gemeldet.\nZuende selbst eins an - die Gilde bekommt Bescheid."])

        -- Lagerfeuer anzuenden
        local lp = panel(p.home, L["Lagerfeuer anzuenden"])
        lp:SetPoint("TOPLEFT", 380, 0)
        lp:SetPoint("TOPRIGHT", 0, 0)
        lp:SetHeight(200)
        local hint = K.Text(lp, 11, C.muted)
        hint:SetPoint("TOPLEFT", 12, -34)
        hint:SetPoint("RIGHT", lp, "RIGHT", -12, 0)
        hint:SetWordWrap(true)
        hint:SetText(L["Sitzt du an einem Feuer? Melde es - die Gilde sieht es 15 Minuten auf Karte und Minimap."])
        p.note = K.Input(lp, 300, L["Notiz, z.B. 'Kochen + Schmieden, kommt vorbei' ..."])
        p.note:SetPoint("TOPLEFT", 12, -72)
        p.note:SetPoint("RIGHT", lp, "RIGHT", -12, 0)
        p.light = K.Button(lp, L["Hier brennt ein Lagerfeuer"], 300, 28, "primary", function()
            Camp.Signal(p.note:GetText())
            p.note:SetText("")
        end)
        p.light:SetPoint("TOPLEFT", 12, -104)
        p.light:SetPoint("RIGHT", lp, "RIGHT", -12, 0)
        p.mine = K.Text(lp, 12, C.text)
        p.mine:SetPoint("TOPLEFT", 12, -146)
        p.mine:SetPoint("RIGHT", lp, "RIGHT", -110, 0)
        p.mine:SetWordWrap(true)
        p.mineBar = K.Bar(lp, 200, 4)
        p.mineBar:SetPoint("TOPLEFT", 12, -168)
        p.mineBar:SetPoint("RIGHT", lp, "RIGHT", -110, 0)
        p.douse = K.Button(lp, L["Loeschen"], 86, 24, "ghost", function() Camp.Extinguish() end)
        p.douse:SetPoint("TOPRIGHT", -12, -144)
        local sl = K.Text(lp, 10, C.dim)
        sl:SetPoint("BOTTOMLEFT", 12, 10)
        sl:SetText(L["Schneller: /oa lagerfeuer <Notiz>"])

        -- gerade aktiv in der Gilde
        local ap = panel(p.home, L["Gerade aktiv in der Gilde"])
        ap:SetPoint("TOPLEFT", 0, -210)
        ap:SetPoint("BOTTOMLEFT")
        ap:SetWidth(370)
        p.topBuffs = K.List(ap, 30, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 22, nil)
            r.icon:SetPoint("LEFT", 8, 0)
            r:Col("name", 38, 210, 12)
            r:Col("who", 0, 110, 11, C.mint, "RIGHT")
            r.cols.who:ClearAllPoints()
            r.cols.who:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnClick", function(self) if self.item then selectBuff(p, self.item) end end)
            return r
        end, function(r, e)
            r.icon:SetTexture(buffIcon(e))
            r.cols.name:SetText(profIcon(e._prof, 12) .. " " .. Camp.BuffName(e))
            r.cols.who:SetText(e._n > 0 and ((L["%d aktiv"]):format(e._n)) or "|cff555555-|r")
        end)
        p.topBuffs:SetPoint("TOPLEFT", 4, -32)
        p.topBuffs:SetPoint("BOTTOMRIGHT", -4, 6)
        p.topBuffs.empty:SetText(L["Der Katalog ist noch leer."])

        -- deine Buffs
        local bp = panel(p.home, L["Deine Buffs gerade"])
        bp:SetPoint("TOPLEFT", 380, -210)
        bp:SetPoint("BOTTOMRIGHT")
        -- zwei gleich breite Spalten, egal wie breit das Fenster ist
        p.homePanels = { fp, lp, ap, bp }
        local function layoutHome(w)
            w = w or p.home:GetWidth() or 0
            if w < 100 then w = 750 end
            local half = math.floor((w - 10) / 2)
            fp:SetWidth(half)
            ap:SetWidth(half)
            lp:ClearAllPoints()
            lp:SetPoint("TOPLEFT", half + 10, 0)
            lp:SetPoint("TOPRIGHT", 0, 0)
            bp:ClearAllPoints()
            bp:SetPoint("TOPLEFT", half + 10, -210)
            bp:SetPoint("BOTTOMRIGHT")
        end
        p.home:HookScript("OnSizeChanged", function(_, w) layoutHome(w) end)
        layoutHome()
        recipeBox = K.Input(bp, 200, L["Rezept dazu (optional) ..."])
        recipeBox:SetPoint("TOPRIGHT", -10, -6)
        recipeBox:SetWidth(170)
        p.myBuffs = K.List(bp, 28, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 20, nil)
            r.icon:SetPoint("LEFT", 8, 0)
            r:Col("name", 34, 200, 12)
            r:Col("rem", 0, 60, 11, C.muted, "RIGHT")
            r.cols.rem:ClearAllPoints()
            r.cols.rem:SetPoint("RIGHT", -104, 0)
            r.add = K.Button(r, L["+ Katalog"], 90, 20, "ghost")
            r.add:SetPoint("RIGHT", -6, 0)
            r.add:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Zum Gilden-Katalog hinzufuegen"] }) end)
            r.add:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.inCat = K.Text(r, 10, C.mint, "RIGHT")
            r.inCat:SetPoint("RIGHT", -10, 0)
            r.inCat:SetText(L["im Katalog"])
            return r
        end, function(r, b)
            r.icon:SetTexture(b.icon or 134400)
            local inCat = catalogIds()[b.id]
            r.cols.name:SetText(inCat and ("|cff66db9e" .. b.name .. "|r") or b.name)
            r.cols.rem:SetText(b.exp == 0 and "" or remaining(b.exp))
            r.add:SetShown(not inCat)
            r.inCat:SetShown(inCat and true or false)
            r.add:SetScript("OnClick", function()
                Camp.AddToCatalog(b, recipeBox:GetText())
                recipeBox:SetText("")
            end)
        end)
        p.myBuffs:SetPoint("TOPLEFT", 4, -32)
        p.myBuffs:SetPoint("BOTTOMRIGHT", -4, 6)
        p.myBuffs.empty:SetText(L["Keine Buffs (oder gerade im Kampf).\nGruen = schon im Katalog, '+' = hinzufuegen."])

        ----------------------------------------------------------------
        -- Buff-Katalog
        ----------------------------------------------------------------
        p.cat = CreateFrame("Frame", nil, p)
        p.cat:SetPoint("TOPLEFT", 0, -40)
        p.cat:SetPoint("BOTTOMRIGHT")
        p.catSeg = K.Segments(p.cat, { { key = "all", text = L["Alle"] }, { key = "active", text = L["Aktiv"] },
            { key = "makers", text = L["Mit Hersteller"] }, { key = "none", text = L["Ohne Hersteller"] } }, function(k)
            catFilter = k
            ns.RefreshPage("camp")
        end)
        p.catSeg:SetPoint("TOPLEFT", 0, 0)
        p.catSearch = K.Input(p.cat, 150, L["Suchen ..."], function(t) catSearch = (t or ""):lower() ns.RefreshPage("camp") end)
        p.catSearch:SetPoint("TOPLEFT", 270, 0)
        p.catSearch:SetWidth(130)
        p.catList = K.List(p.cat, 46, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 30, nil)
            r.icon:SetPoint("LEFT", 8, 0)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("TOPLEFT", 46, -7)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -60, 0)
            r.cols.makers = K.Text(r, 11, C.muted)
            r.cols.makers:SetPoint("BOTTOMLEFT", 46, 7)
            r.cols.makers:SetPoint("RIGHT", r, "RIGHT", -60, 0)
            r.cols.active = K.Title(r, 18, C.mint, "RIGHT")
            r.cols.active:SetPoint("RIGHT", -12, 4)
            r.cols.al = K.Text(r, 9, C.dim, "RIGHT")
            r.cols.al:SetPoint("TOPRIGHT", r.cols.active, "BOTTOMRIGHT", 0, -1)
            r.cols.al:SetText(L["AKTIV"])
            r.sel = r:CreateTexture(nil, "OVERLAY")
            r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            r.sel:SetPoint("TOPLEFT")
            r.sel:SetPoint("BOTTOMLEFT")
            r.sel:SetWidth(2)
            r:SetScript("OnClick", function(self) if self.item then selected = self.item.id ns.RefreshPage("camp") end end)
            return r
        end, function(r, e)
            r.icon:SetTexture(buffIcon(e))
            r.cols.name:SetText(profIcon(e._prof, 13) .. " " .. Camp.BuffName(e))
            local on = onlineCount(e._makers)
            local rec = (e.recipe or "") ~= "" and ("|cffc8c8c8" .. e.recipe .. "|r  ·  ") or ""
            r.cols.makers:SetText(rec .. (#e._makers > 0 and (L["%d koennen bauen"]):format(#e._makers) .. (on > 0 and (" |cff66db9e(" .. (L["%d online"]):format(on) .. ")|r") or "")
                or L["|cff666666Hersteller unbekannt|r"]))
            r.cols.active:SetText(e._n)
            r.cols.active:SetTextColor(unpack(e._n > 0 and C.mint or C.dim))
            r.sel:SetShown(e.id == selected)
        end)
        p.catList:SetPoint("TOPLEFT", 0, -34)
        p.catList:SetPoint("BOTTOMLEFT")
        p.catList:SetWidth(400)
        p.catList.empty:SetText(L["Noch leer. Setz dich an ein Lagerfeuer und fuege\nden Buff in der Uebersicht ueber '+' zum Katalog hinzu."])

        -- Detailkarte
        local d = K.Panel(p.cat, C.panel)
        d:SetPoint("TOPLEFT", 412, 0)
        d:SetPoint("BOTTOMRIGHT")
        p.detail = d
        p.dIcon = K.Icon(d, 40, nil)
        p.dIcon:SetPoint("TOPLEFT", 14, -14)
        p.dTitle = K.Title(d, 15, C.text)
        p.dTitle:SetPoint("TOPLEFT", 64, -16)
        p.dTitle:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dSub = K.Text(d, 11, C.muted)
        p.dSub:SetPoint("TOPLEFT", 64, -36)
        p.dSub:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dDesc = K.Text(d, 12, C.text)
        p.dDesc:SetPoint("TOPLEFT", 14, -66)
        p.dDesc:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dDesc:SetWordWrap(true)
        local ah = K.Label(d, L["Aktiv bei"])
        ah:SetPoint("TOPLEFT", 14, -98)
        p.dHolders = K.Text(d, 12, C.text)
        p.dHolders:SetPoint("TOPLEFT", 14, -116)
        p.dHolders:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dHolders:SetWordWrap(true)
        p.dHolders:SetJustifyV("TOP")
        p.dMakerHead = K.Label(d, L["Kann bauen"])
        p.dMakerHead:SetPoint("TOPLEFT", 14, -186)
        p.dMakers = K.Text(d, 12, C.text)
        p.dMakers:SetPoint("TOPLEFT", 14, -204)
        p.dMakers:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dMakers:SetWordWrap(true)
        p.dMakers:SetJustifyV("TOP")
        p.dAsk = K.Button(d, L["Im Gildenchat fragen"], 160, 26, "primary", function()
            local e = p.dItem
            if e then ns.OpenChat("/g " .. (L["Wer hat gerade %s am Lagerfeuer? Ich komme vorbei!"]):format(Camp.BuffName(e))) end
        end)
        p.dAsk:SetPoint("BOTTOMLEFT", 14, 14)
        p.dWhisper = K.Button(d, L["Hersteller anfluestern"], 150, 26, "ghost", function()
            local e = p.dItem
            if e and e._makers[1] then whisper(e._makers[1]) end
        end)
        p.dWhisper:SetPoint("LEFT", p.dAsk, "RIGHT", 8, 0)
        p.dDel = K.IconButton(d, "x", 18, function()
            if p.dItem then Store.Delete("campCatalog", p.dItem.id) selected = nil end
        end, L["Aus dem Katalog entfernen"])
        p.dDel:SetPoint("TOPRIGHT", -8, -8)
        p.dEmpty = K.Text(d, 12, C.dim, "CENTER")
        p.dEmpty:SetPoint("CENTER")
        p.dEmpty:SetWidth(260)
        p.dEmpty:SetWordWrap(true)
        p.dEmpty:SetText(L["Links einen Buff waehlen."])

        ----------------------------------------------------------------
        -- Feuer (aktiv + letzte Stunde)
        ----------------------------------------------------------------
        p.fires = K.List(p, 44, function(l)
            local r = fireRow(l)
            r.wh = K.Button(r, L["Anfluestern"], 86, 22, "ghost")
            r.wh:SetPoint("RIGHT", r.map, "LEFT", -6, 0)
            r.wh.label:SetFont(K.FONT, 11, "")
            r.cols.rem:ClearAllPoints()
            r.cols.rem:SetPoint("TOPRIGHT", -170, -8)
            r.cols.zone:SetPoint("RIGHT", r, "RIGHT", -250, 0)
            r.cols.meta:SetPoint("RIGHT", r, "RIGHT", -250, 0)
            return r
        end, function(r, f)
            fireUpdate(r, f)
            r.wh:SetShown(f.by ~= ns.me())
            r.wh:SetScript("OnClick", function() whisper(f.by) end)
        end)
        p.fires:SetPoint("TOPLEFT", 0, -40)
        p.fires:SetPoint("BOTTOMRIGHT", 0, 22)
        p.fires.empty:SetText(L["In der letzten Stunde hat niemand ein Lagerfeuer gemeldet."])
        p.firesFoot = K.Text(p, 10, C.dim)
        p.firesFoot:SetPoint("BOTTOMLEFT", 0, 4)
        p.firesFoot:SetText(L["Feuer brennen 15 Minuten; erloschene bleiben eine Stunde sichtbar.  Rechtsklick: anfluestern"])
    end,

    refresh = function(p)
        p.seg:Select(view)
        p.home:SetShown(view == "home")
        p.cat:SetShown(view == "catalog")
        p.fires:SetShown(view == "fires")
        p.firesFoot:SetShown(view == "fires")
        local myFire = Camp.MyFire()
        p.lightTop:SetShown(view ~= "home" and not myFire)

        local cat = catalogList()
        if view == "home" then
            local fires = Camp.ActiveFires()
            local mine, holders = 0, {}
            local myState = Camp.state[ns.me()]
            for _, e in ipairs(cat) do
                for _, h in ipairs(Camp.ActiveHolders(e.spell)) do holders[h.name] = true end
                if myState and myState.buffs[e.spell] then mine = mine + 1 end
            end
            local nh = 0
            for _ in pairs(holders) do nh = nh + 1 end
            local fr = p.fresh
            p.cards[1]:Set(#fires, nil, nil, fr)
            p.cards[2]:Set(#cat, nil, nil, fr)
            p.cards[3]:Set(nh, nh > 0 and ("· " .. L["Spieler"]) or nil, nil, fr)
            p.cards[4]:Set(mine, "/ " .. #cat, #cat > 0 and mine / #cat or nil, fr)
            if fr then
                for i, pn in ipairs(p.homePanels or {}) do pn.oasisFadedAt = nil K.FadeIn(pn, (i - 1) * 0.07) end
                p.fresh = false
            end
            p.homeFires:SetData(fires)
            p.topBuffs:SetData(cat)
            local buffs = Camp.MyBuffs()
            table.sort(buffs, function(a, b)
                local ia, ib = catalogIds()[a.id] and 1 or 0, catalogIds()[b.id] and 1 or 0
                if ia ~= ib then return ia > ib end
                return a.name < b.name
            end)
            p.myBuffs:SetData(buffs)
            if myFire then
                p.mine:SetText(L["Dein Feuer brennt: "] .. ns.zoneName(myFire.mapID, myFire.zone) .. "  |cffff7838" .. (L["noch %s"]):format(remaining(myFire.exp)) .. "|r")
                p.mineBar:Set((myFire.exp - ns.now()) / FIRE_TIME)
            else
                p.mine:SetText("|cff777777" .. L["Du hast gerade kein Feuer gemeldet."] .. "|r")
            end
            p.mineBar:SetShown(myFire ~= nil)
            p.douse:SetShown(myFire ~= nil)
            return
        end

        if view == "fires" then
            p.fires:SetData(Camp.AllFires())
            return
        end

        -- Katalog
        local list, sel = {}, nil
        for _, e in ipairs(cat) do
            local ok = catFilter == "all" or (catFilter == "active" and e._n > 0) or (catFilter == "makers" and #e._makers > 0)
                or (catFilter == "none" and #e._makers == 0)
            if ok and catSearch ~= "" then
                ok = Camp.BuffName(e):lower():find(catSearch, 1, true) or (e.recipe or ""):lower():find(catSearch, 1, true)
            end
            if ok then
                list[#list + 1] = e
                if e.id == selected then sel = e end
            end
        end
        if not sel then sel = list[1] selected = sel and sel.id end
        p.catList:SetData(list)
        p.dItem = sel
        for _, f in ipairs({ p.dIcon, p.dTitle, p.dSub, p.dDesc, p.dHolders, p.dMakers, p.dMakerHead, p.dAsk, p.dWhisper }) do f:SetShown(sel ~= nil) end
        p.dEmpty:SetShown(sel == nil)
        p.dDel:SetShown(sel ~= nil and (sel.by == ns.me() or ns.isOfficer()) and not sel.demo)
        if not sel then return end
        p.dIcon:SetTexture(buffIcon(sel))
        p.dTitle:SetText(Camp.BuffName(sel))
        local sub = {}
        if sel._prof then sub[#sub + 1] = profIcon(sel._prof, 12) end
        if (sel.recipe or "") ~= "" then sub[#sub + 1] = L["Rezept: "] .. sel.recipe end
        sub[#sub + 1] = (L["eingetragen von %s"]):format(ns.displayName(sel.by or "?"))
        p.dSub:SetText(table.concat(sub, "  "))
        p.dDesc:SetText((sel.desc or "") ~= "" and sel.desc or ("|cff777777" .. L["Keine Beschreibung - fahr mit der Maus ueber den Buff im Spiel."] .. "|r"))
        local hs = Camp.ActiveHolders(sel.spell)
        local t = {}
        for i, h in ipairs(hs) do
            if i > 8 then t[#t + 1] = "|cff888888+" .. (#hs - 8) .. "|r" break end
            t[#t + 1] = ns.Radar.Colored(h.name) .. " |cff888888" .. remaining(h.exp) .. "|r"
        end
        p.dHolders:SetText(#t > 0 and table.concat(t, "\n") or ("|cff777777" .. L["Gerade bei niemandem aktiv."] .. "|r"))
        local mk = {}
        for i, m in ipairs(sel._makers) do
            if i > 8 then mk[#mk + 1] = "|cff888888+" .. (#sel._makers - 8) .. "|r" break end
            local on = ns.Radar.IsOnline and ns.Radar.IsOnline(m)
            mk[#mk + 1] = (on and "|cff66db9e●|r " or "|cff555555●|r ") .. ns.Radar.Colored(m)
        end
        p.dMakers:SetText(#mk > 0 and table.concat(mk, "   ") or ("|cff777777" .. L["Noch niemand bekannt. Wer das Rezept hat, teilt es automatisch beim Oeffnen des Berufsfensters."] .. "|r"))
        p.dWhisper:SetShown(#sel._makers > 0)
    end,
})

ns.Listen("LOGIN", function()
    ns.After(12, function() shareState(true) end)
    ns.Every(30, function() ns.RefreshPage("camp") end)
    ns.Every(45, demoTick)
    -- Demo: Lagerfeuer-Daten mitladen/-entfernen
    local D = ns.Demo
    if D and not D.campHooked then
        D.campHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) Camp.SeedDemo() end
        D.Remove = function(...) remove(...) Camp.RemoveDemo() end
        if D.IsActive() then ns.After(3, Camp.SeedDemo) end
    end
end)
end)

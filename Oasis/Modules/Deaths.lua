-- Oasis: Friedhof (Tode der Gilde, Rangliste, Sterbeorte auf der Karte)
local ADDON, ns = ...
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

local Deaths = {}
ns.Deaths = Deaths
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- Gilden-Optionen (Gildenleitung): welche Tode zaehlen, wie lange Sterbeorte auf der Karte bleiben
ns.GuildOption({ page = "deaths", key = "deInst", default = true,
    label = "Tode in Dungeons und Raids zaehlen", desc = "Tode in Instanzen werden erfasst und zaehlen in der Rangliste. Aus: nur Tode in der offenen Welt." })
ns.GuildOption({ page = "deaths", key = "deDays", default = 14, min = 1, max = 60, step = 1,
    label = "Sterbeorte auf der Karte", desc = "So lange bleiben die Totenkoepfe auf der Weltkarte sichtbar.",
    fmt = function(v) return v .. " Tg" end })

------------------------------------------------------------------------
-- Eigenen Tod erfassen
------------------------------------------------------------------------
local lastHostile
-- zuletzt angegriffener/angreifender Gegner als "vermutlicher Toeter"
local function rememberTarget()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        local n = ns.safe(ns.UnitName("target"))
        if n then lastHostile = { name = n, t = GetTime(), player = UnitIsPlayer("target") and true or nil } end
    end
end
ns.On("PLAYER_TARGET_CHANGED", rememberTarget)
ns.On("PLAYER_REGEN_DISABLED", rememberTarget)

ns.On("PLAYER_DEAD", function()
    -- Entwickler: eigenen Todes-Sound auch selbst hoeren (die anderen hoeren ihn am Tod-Hinweis)
    if ns.IsDev() and ns.Sound and ns.Sound.eventByKey.mydeath and ns.db.settings.sound then
        pcall(ns.Sound.PlayChoice, ns.Sound.ChoiceFor("mydeath"), ns.db.settings.soundVol)
    end
    local mapID, x, y
    if ns.Camp then mapID, x, y = ns.Camp.MyPosition() end
    local inInst, instType = IsInInstance()
    if instType == "pvp" or instType == "arena" then return end
    if inInst and ns.GuildOpt("deInst") == false then return end
    if lastHostile and lastHostile.player and (GetTime() - lastHostile.t) < 30 then return end
    local instName = inInst and ns.safe((GetInstanceInfo())) or nil
    local killer = lastHostile and (GetTime() - lastHostile.t) < 30 and lastHostile.name or nil
    -- 0.5.617 Datenschutz: Sterbeort teilen abschaltbar (Einstellungen > Daten & Analyse)
    if ns.db.settings.shareDeaths == false then if ns.Badges then ns.Badges.Add("deaths", 1) end return end
    Store.Put("deaths", {
        id = ns.newId("death"), who = ns.me(),
        mapID = mapID or ns.safe(C_Map.GetBestMapForUnit("player")) or 0,
        x = x and math.floor(x * 10000) or 0, y = y and math.floor(y * 10000) or 0,
        zone = instName or ns.safe(GetRealZoneText()) or "", inst = inInst and true or false,
        killer = killer or "", lvl = ns.safe(UnitLevel("player")) or 0, ts = ns.now(),
    })
    if ns.Badges then ns.Badges.Add("deaths", 1) end
end)

------------------------------------------------------------------------
-- Auswertung
------------------------------------------------------------------------
-- 0.5.796: nur Tode, die zu DIESER Gilde gehoeren. Charaktere von einem anderen Realm, die nicht in der Gildenliste stehen
-- (z.B. ein Twink in einer anderen Gilde/Fraktion, dessen Tode in derselben Account-Datei liegen), zaehlen hier nicht mit.
local function belongs(d)
    local who = d and d.who
    if type(who) ~= "string" then return false end
    local R = ns.Radar
    if R and R.byName and rawget(R.byName, ns.ResolveName(who) or who) then return true end
    if not (R and R.roster and #R.roster > 0) then return true end   -- Gildenliste noch nicht da: nichts ausblenden
    -- 0.5.797: eigener Charakter dieses Accounts, der nicht in der Gilde ist (z.B. Allianz-Twink auf demselben Realm): gehoert nicht hierher
    if ns.db and ns.db.chars and ns.db.chars[who] and not ns.isMe(who) then return false end
    local realm = who:match("%-(.+)$")
    local me = ns.me()
    local mine = me and me:match("%-(.+)$")
    return not (realm and mine and realm ~= mine)
end
local function deathList()
    local out = {}
    for _, d in ipairs(Store.List("deaths")) do if belongs(d) then out[#out + 1] = d end end
    return out
end
Deaths.List = deathList
-- 0.5.798: Tode, die nicht zu dieser Gilde gehoeren (fremder Realm / eigener Charakter ausserhalb der Gilde), aus dem lokalen
-- Speicher nehmen - einmal je Sitzung, sobald die Gildenliste da ist. Nur lokal (kein Loesch-Befehl an die Gilde): so werden sie
-- beim Abgleich auch nicht mehr weiterverteilt. Betrifft nur Eintraege ohne Gildenkennzeichen oder mit dem Namen dieser Gilde.
local cleaned = false
ns.Listen("ROSTER", function()
    if cleaned or not IsInGuild() then return end
    local R = ns.Radar
    if not (R and R.roster and #R.roster > 0) then return end
    cleaned = true
    local c = Store.coll("deaths")
    local g = Store.MyGuild and Store.MyGuild()
    local n = 0
    for id, d in pairs(c) do
        if type(d) == "table" and not d.demo and (d.gn == nil or d.gn == g) and not belongs(d) then
            c[id] = nil
            n = n + 1
        end
    end
    if n > 0 then
        if ns.debug then ns.debug("Friedhof: fremde Tode entfernt", n) end
        ns.RefreshPage("deaths")
    end
end)
function Deaths.All()
    local out = deathList()
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- Rangliste pro Spieler (Main), dazu Lieblingsgegner und toedlichstes Gebiet
function Deaths.Ranking()
    local by = {}
    for _, d in ipairs(deathList()) do
        local main = ns.Alts and ns.Alts.Main(d.who) or d.who
        local s = by[main]
        if not s then
            s = { name = main, n = 0, last = 0, killers = {}, zones = {} }
            by[main] = s
        end
        s.n = s.n + 1
        s.last = math.max(s.last, d.ts or 0)
        if (d.killer or "") ~= "" then s.killers[d.killer] = (s.killers[d.killer] or 0) + 1 end
        local z = ns.zoneName(d.mapID, d.zone)
        if z ~= "" then s.zones[z] = (s.zones[z] or 0) + 1 end
    end
    local out = {}
    for _, s in pairs(by) do
        local function top(t) local b, bn = nil, 0 for k, v in pairs(t) do if v > bn then b, bn = k, v end end return b, bn end
        s.killer, s.killerN = top(s.killers)
        s.zone, s.zoneN = top(s.zones)
        out[#out + 1] = s
    end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.last > b.last end)
    return out
end

function Deaths.Zones()
    local z = {}
    for _, d in ipairs(deathList()) do
        local name = ns.zoneName(d.mapID, d.zone)
        if name ~= "" then z[name] = (z[name] or 0) + 1 end
    end
    local out = {}
    for k, v in pairs(z) do out[#out + 1] = { zone = k, n = v } end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out
end

-- Hinweis, wenn ein Gildenmitglied stirbt
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "deaths" then return end
    local age = ns.now() - (tonumber(rec.ts) or 0)
    -- Abgleich liefert auch historische Tode: nur frische Ereignisse als Live-Hinweis zeigen.
    if not old and not rec.del and not ns.isMe(rec.who) and age >= -5 and age <= 30 and ns.db.settings.deathToasts ~= false
        and SEC.Name(rec.who) and SEC.Rate("deathtoast:" .. rec.who, 20) then   -- je Person gedrosselt (Toast-/Ton-Flut)
        local where = SEC.Text(ns.zoneName(rec.mapID, rec.zone), 60)
        -- hat die Person einen eigenen Todes-Sound, spielt der statt des gewaehlten Tod-Sounds
        local pr = ns.db.members and ns.db.members[rec.who]
        if ns.Sound and ns.Sound.Force then ns.Sound.Force("death", type(pr) == "table" and pr.ds or nil, "death") end
        K.Toast((L["%s ist gestorben"]):format(ns.displayName(rec.who)),
            where .. ((rec.killer or "") ~= "" and ns.db.settings.deathKiller ~= false and ("  ·  " .. SEC.Text(rec.killer, 60)) or ""), C.red, function() ns.ShowPage("deaths") end, "death", (tonumber(rec.ts) or 0) + 30)
        if ns.Sound then ns.Sound.forced = nil end   -- nicht gespielt (Hinweis aus/zurueckgehalten): nicht fuer den naechsten Tod aufheben
    end
    if ns.Map then ns.Map.dirty = true end
    ns.RefreshPage("deaths")
end)

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local view = "rank"      -- "rank" | "recent" | "map"
local span = "all"       -- Zeitraum: "7" | "30" | "all"
local focus              -- nur Tode dieser Person (Main) zeigen
local flash              -- diese Tod-ID auf der Karte hervorheben
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function inSpan(d)
    if span == "all" then return true end
    return ns.now() - (d.ts or 0) < tonumber(span) * 86400
end
local function mainOf(n) return ns.Alts and ns.Alts.Main(n) or n end
-- 0.5.795: wem gehoert der Tote? Twinks zeigen ihren Main, Charaktere ausserhalb der aktuellen Gildenliste ihren Realm.
-- Anlass: ein Charakter heisst wirklich "Du" - in der Liste las sich das wie "du selbst".
local function ownerHint(name)
    local main = mainOf(name)
    if main and main ~= name and not ns.SameName(main, name) then
        return "  |cff888888(" .. (L["Twink von %s"]):format(ns.displayName(main)) .. ")|r"
    end
    local R = ns.Radar
    if R and R.byName and not rawget(R.byName, ns.ResolveName(name) or name) then
        local realm = tostring(name):match("%-(.+)$")
        return "  |cff888888(" .. (realm and (L["nicht in der Gildenliste"] .. ", " .. realm) or L["nicht in der Gildenliste"]) .. ")|r"
    end
    return ""
end
local function filtered()
    local out = {}
    for _, d in ipairs(Deaths.All()) do
        if inSpan(d) and (not focus or mainOf(d.who) == focus) then out[#out + 1] = d end
    end
    return out
end
local function deathLine(d)
    local k = (d.killer or "") ~= "" and ("  ·  " .. SEC.Text(d.killer, 60)) or ""
    return ns.displayName(d.who) .. " |cff888888" .. (d.lvl or "?") .. "|r  ·  " .. SEC.Text(ns.zoneName(d.mapID, d.zone), 60) .. k .. "  |cff666666" .. ns.ago(d.ts) .. "|r"
end

-- Karte: zwei Kontinente nebeneinander, Totenkoepfe (nahe Tode zusammengefasst)
local function buildMap(p)
    local m = CreateFrame("Frame", nil, p)
    m.panels = {}
    local Info = ns.GuildInfo
    for idx, cont in ipairs({ 1414, 1415 }) do
        local pn = CreateFrame("Button", nil, m)
        pn.cont = cont
        pn.art = CreateFrame("Frame", nil, pn)
        pn.art:SetClipsChildren(true)
        pn.art.bg = pn.art:CreateTexture(nil, "BACKGROUND")
        pn.art.bg:SetAllPoints()
        pn.art.bg:SetColorTexture(0.10, 0.11, 0.13, 1)
        K.Border(pn.art, { 1, 1, 1, 0.10 })
        pn.tiles, pn.pins = {}, {}
        local okL, layers = pcall(function() return C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(cont) end)
        local okT, texs = pcall(function() return C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(cont, 1) end)
        local L1 = okL and type(layers) == "table" and layers[1]
        if L1 and okT and type(texs) == "table" and #texs > 0 and (L1.layerWidth or 0) > 0 and (L1.tileWidth or 0) > 0 then
            pn.layer = { w = L1.layerWidth, h = L1.layerHeight, tw = L1.tileWidth, th = L1.tileHeight, cols = math.ceil(L1.layerWidth / L1.tileWidth) }
            for i, tex in ipairs(texs) do
                local t = pn.art:CreateTexture(nil, "BORDER")
                t:SetTexture(tex)
                t:SetVertexColor(0.55, 0.55, 0.6)   -- gedimmt, damit die Totenkoepfe tragen
                pn.tiles[i] = t
            end
        end
        pn.label = K.Text(pn, 11, C.muted)
        pn.label:SetPoint("TOPLEFT", pn.art, "BOTTOMLEFT", 0, -5)
        pn.label:SetText(L[(Info and Info.CONT and Info.CONT[cont]) or ""])
        pn.count = K.Text(pn, 11, C.text, "RIGHT")
        pn.count:SetPoint("TOPRIGHT", pn.art, "BOTTOMRIGHT", 0, -5)
        pn:SetScript("OnClick", function(self) if ns.Map and ns.Map.ShowOnWorldMap then ns.Map.ShowOnWorldMap(self.cont) end end)
        m.panels[idx] = pn
    end
    m.note = K.Text(m, 11, C.dim)
    function m:Layout(w, h)
        local GAP, LBL = 14, 22
        local pw, ph = math.floor((w - GAP) / 2), h - LBL
        for idx, pn in ipairs(self.panels) do
            pn:ClearAllPoints()
            pn:SetPoint("TOPLEFT", (idx - 1) * (pw + GAP), 0)
            pn:SetSize(pw, h)
            local asp = pn.layer and (pn.layer.w / pn.layer.h) or 1.5
            local aw, ah = pw, pw / asp
            if ah > ph then ah, aw = ph, ph * asp end
            pn.art:ClearAllPoints()
            pn.art:SetPoint("TOP", pn, "TOP", 0, 0)
            pn.art:SetSize(aw, ah)
            pn.aw, pn.ah = aw, ah
            if pn.layer then
                local ly = pn.layer
                local sc = aw / ly.w
                for i, t in ipairs(pn.tiles) do
                    local c, r = (i - 1) % ly.cols, math.floor((i - 1) / ly.cols)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", pn.art, "TOPLEFT", c * ly.tw * sc, -r * ly.th * sc)
                    t:SetSize(ly.tw * sc, ly.th * sc)
                end
            end
        end
        self.note:ClearAllPoints()
        self.note:SetPoint("BOTTOMLEFT", 0, 0)
    end
    local function pin(pn, i)
        local b = pn.pins[i]
        if b then return b end
        b = CreateFrame("Button", nil, pn.art)
        b.back = b:CreateTexture(nil, "BORDER")
        b.back:SetTexture(CIRCLE)
        b.back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
        b.back:SetPoint("CENTER")
        b.skull = b:CreateTexture(nil, "ARTWORK")
        b.skull:SetTexture(SKULL)
        b.skull:SetPoint("CENTER")
        b.n = b:CreateFontString(nil, "OVERLAY")
        K.SetFontSafe(b.n, K.FONT_HEAD or K.FONT, 9, "OUTLINE", K.FONT)
        b.n:SetPoint("BOTTOMRIGHT", 4, -3)
        b:SetScript("OnEnter", function(self)
            -- nur das Bild vergroessern, nicht den Knopf (sonst Enter/Leave-Schleife = Zucken)
            self.skull:SetSize(self.s + 4, self.s + 4)
            self.back:SetSize(self.s + 8, self.s + 8)
            local t = { (#self.list == 1 and L["1 Tod hier"] or (L["%d Tode hier"]):format(#self.list)) }
            for j = 1, math.min(6, #self.list) do t[#t + 1] = deathLine(self.list[j]) end
            if #self.list > 6 then t[#t + 1] = "|cff888888" .. (L["und %d weitere"]):format(#self.list - 6) .. "|r" end
            t[#t + 1] = "|cff888888" .. L["Klick: auf der Weltkarte zeigen"] .. "|r"
            K.ShowTip(self, t)
        end)
        b:SetScript("OnLeave", function(self) self.skull:SetSize(self.s, self.s) self.back:SetSize(self.s + 4, self.s + 4) GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            local d = self.list[1]
            if d and ns.Map and ns.Map.ShowOnWorldMap then ns.Map.ShowOnWorldMap(d.mapID) end
        end)
        pn.pins[i] = b
        return b
    end
    function m:Update(list)
        local Info = ns.GuildInfo
        local hidden = 0
        for _, pn in ipairs(self.panels) do
            for _, b in ipairs(pn.pins) do b:Hide() end
            -- nahe Tode in Rasterzellen zusammenfassen
            local CELL = 16
            local cells, order = {}, {}
            for _, d in ipairs(list) do
                if not d.inst and (d.mapID or 0) ~= 0 and Info and Info.PosOnCont then
                    local cx, cy, cont = Info.PosOnCont(d.mapID, (d.x or 0) / 10000, (d.y or 0) / 10000)
                    if cont == pn.cont and cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
                        local px, py = cx * (pn.aw or 100), cy * (pn.ah or 100)
                        local key = math.floor(px / CELL) .. ":" .. math.floor(py / CELL)
                        local c = cells[key]
                        if not c then c = { list = {}, x = 0, y = 0 } cells[key] = c order[#order + 1] = c end
                        c.list[#c.list + 1] = d
                        c.x, c.y = c.x + px, c.y + py
                    end
                end
            end
            local total = 0
            for i, c in ipairs(order) do
                local b = pin(pn, i)
                local n = #c.list
                total = total + n
                local s = n >= 5 and 15 or n >= 2 and 13 or 11
                b.s = s
                b:SetSize(s, s)
                b.back:SetSize(s + 4, s + 4)
                b.skull:SetSize(s, s)
                b.list = c.list
                b.n:SetText(n > 1 and n or "")
                b:ClearAllPoints()
                b:SetPoint("CENTER", pn.art, "TOPLEFT", c.x / n, -c.y / n)
                local hot = false
                for _, d in ipairs(c.list) do if flash and d.id == flash then hot = true end end
                b.skull:SetVertexColor(1, hot and 0.35 or 1, hot and 0.3 or 1)
                b:SetFrameLevel(pn.art:GetFrameLevel() + (hot and 20 or 2) + math.min(n, 10))
                b:Show()
            end
            pn.count:SetText(total == 1 and L["1 Tod"] or (L["%d Tode"]):format(total))
        end
        for _, d in ipairs(list) do if d.inst then hidden = hidden + 1 end end
        self.note:SetText(hidden > 0 and (L["%d Tode in Dungeons sind nicht auf der Karte."]):format(hidden) or "")
    end
    return m
end

ns.RegisterPage({
    key = "deaths", title = "Friedhof", order = 7.55,
    sub = "Wer stirbt am oeftesten, woran und wo - die Todes-Rangliste der Gilde",
    build = function(p)
        p.cTotal = K.StatCard(p, L["Tode gesamt"])
        p.cTotal:SetPoint("TOPLEFT", 0, 0)
        p.cWeek = K.StatCard(p, L["Diese Woche"])
        p.cWeek:SetPoint("TOPLEFT", 160, 0)
        p.cZone = K.StatCard(p, L["Toedlichstes Gebiet"])
        p.cZone:SetPoint("TOPLEFT", 320, 0)
        p.cZone:SetWidth(250)
        p.cZone.value:SetWidth(226)
        p.cZone.value:SetFont(K.FONT_HEAD, 14, "")
        p.cKiller = K.StatCard(p, L["Gefaehrlichster Gegner"])
        p.cKiller:SetPoint("TOPLEFT", 580, 0)
        p.cKiller:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        p.cKiller.value:SetPoint("RIGHT", -12, 0)
        p.cKiller.value:SetWordWrap(false)
        p.cKiller.value:SetFont(K.FONT_HEAD, 14, "")
        -- 0.5.853: die vier Karten entfallen, ihre Werte stehen in einer Zeile unter den Reitern
        for _, c in ipairs({ p.cTotal, p.cWeek, p.cZone, p.cKiller }) do c:Hide() end
        p.sum = K.Text(p, 11, C.muted)
        p.sum:SetPoint("TOPLEFT", 2, -32)
        p.sum:SetPoint("RIGHT", p, "RIGHT", -4, 0)
        p.sum:SetWordWrap(false)

        p.seg = K.Segments(p, { { key = "rank", text = L["Rangliste"] }, { key = "recent", text = L["Letzte Tode"] }, { key = "map", text = L["Todeskarte"] } }, function(k)
            view = k
            p.animNext = true
            ns.RefreshPage("deaths")
        end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.span = K.Segments(p, { { key = "all", text = L["Gesamt"] }, { key = "30", text = L["30 Tage"] }, { key = "7", text = L["7 Tage"] } }, function(k)
            span = k
            p.animNext = true
            ns.RefreshPage("deaths")
        end, nil, { size = 11, pad = 14 })
        p.span:SetPoint("TOPRIGHT", 0, 0)
        -- aktiver Personen-Filter: Name + x zum Aufheben
        p.focus = CreateFrame("Button", nil, p)
        p.focus:SetHeight(22)
        p.focus:SetPoint("RIGHT", p.span, "LEFT", -14, 0)
        p.focus.text = K.Text(p.focus, 12, C.text)
        p.focus.text:SetPoint("LEFT", 0, 0)
        p.focus.x = K.Text(p.focus, 13, C.muted)
        p.focus.x:SetText("×")
        p.focus.x:SetPoint("LEFT", p.focus.text, "RIGHT", 6, 0)
        p.focus:SetScript("OnClick", function() focus = nil flash = nil ns.RefreshPage("deaths") end)
        p.focus:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Filter aufheben"] }) end)
        p.focus:SetScript("OnLeave", function() GameTooltip:Hide() end)

        p:HookScript("OnShow", function() p.animNext = true end)
        local MEDAL = { { 1, 0.82, 0.3 }, { 0.78, 0.8, 0.85 }, { 0.85, 0.55, 0.3 } }
        p.rank = K.List(p, 48, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            -- Balken in Klassenfarbe hinter der ganzen Zeile: Anteil an den meisten Toden
            r.bar = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.bar:SetPoint("TOPLEFT", 0, -2)
            r.bar:SetPoint("BOTTOMLEFT", 0, 2)
            r.bar:SetWidth(1)
            r:Col("pos", 8, 30, 16, C.muted, "CENTER")
            r.cols.pos:SetFont(K.FONT_HEAD, 16, "")
            r.ring = r:CreateTexture(nil, "ARTWORK")
            r.ring:SetTexture(ns.MEDIA .. "dot")
            r.ring:SetSize(32, 32)
            r.ring:SetPoint("LEFT", 44, 0)
            r.av = r:CreateTexture(nil, "OVERLAY")
            r.av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.av:SetSize(28, 28)
            r.av:SetPoint("CENTER", r.ring, "CENTER")
            r.skull = r:CreateTexture(nil, "OVERLAY", nil, 2)
            r.skull:SetTexture(SKULL)
            r.skull:SetSize(14, 14)
            r.skull:SetPoint("BOTTOMRIGHT", r.ring, "BOTTOMRIGHT", 4, -3)
            r.cols.name = K.Text(r, 14, C.text)
            r.cols.name:SetPoint("TOPLEFT", 88, -8)
            r.cols.name:SetWidth(260)
            r.cols.sub = K.Text(r, 11, C.muted)
            r.cols.sub:SetPoint("BOTTOMLEFT", 88, 9)
            r.cols.sub:SetPoint("RIGHT", -90, 0)
            r.cols.sub:SetWordWrap(false)
            r.cols.n = K.Title(r, 20, C.text, "RIGHT")
            r.cols.n:SetPoint("TOPRIGHT", -14, -7)
            r.nl = K.Text(r, 9, C.dim, "RIGHT")
            r.nl:SetPoint("BOTTOMRIGHT", -14, 8)
            r.nl:SetText(K.Upper and K.Upper(L["Tode"]) or L["Tode"])
            r:HookScript("OnEnter", function(self)
                local s = self.item
                if not s then return end
                local t = { ns.Radar.Colored(s.name) }
                local n = 0
                for _, d in ipairs(Deaths.All()) do
                    if mainOf(d.who) == s.name and inSpan(d) then
                        n = n + 1
                        if n <= 5 then t[#t + 1] = deathLine(d) end
                    end
                end
                t[#t + 1] = "|cff888888" .. L["Klick: Tode auf der Karte zeigen"] .. "|r"
                K.ShowTip(self, t)
            end)
            r:HookScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.item then return end
                focus, flash, view = self.item.name, nil, "map"
                p.seg:Select("map")
                ns.RefreshPage("deaths")
            end)
            return r
        end, function(r, s, i)
            r.cols.pos:SetText(i)
            local md = MEDAL[i]
            r.cols.pos:SetTextColor((md or C.muted)[1], (md or C.muted)[2], (md or C.muted)[3])
            r.skull:SetShown(i == 1)
            local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(s.name)
            local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
            if tc then r.av:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) r.av:SetAlpha(1) else r.av:SetAlpha(0) end
            local cr, cg, cb = ns.classColor(cls)
            cr, cg, cb = cr or 0.6, cg or 0.6, cb or 0.6
            r.ring:SetVertexColor(cr, cg, cb, 0.9)
            r.cols.name:SetText(ns.Radar.Colored(s.name))
            local t = {}
            if s.killer then t[#t + 1] = "|cffd9786b" .. s.killer .. "|r |cff888888" .. s.killerN .. "x|r" end
            if s.zone then t[#t + 1] = s.zone end
            t[#t + 1] = "|cff777777" .. (L["zuletzt %s"]):format(ns.ago(s.last)) .. "|r"
            r.cols.sub:SetText(table.concat(t, "  ·  "))
            if not K.Gradient or not K.Gradient(r.bar, "HORIZONTAL", { cr, cg, cb, 0.20 }, { cr, cg, cb, 0.03 }) then r.bar:SetColorTexture(cr, cg, cb, 0.10) end
            local w = math.max(2, ((r:GetWidth() or 0) > 50 and r:GetWidth() or 700) * s.n / math.max(1, p.maxN or 1))
            if p.animNext and not (ns.db.settings.noAnim) then
                local d = math.min(i, 12) * 0.04
                r.bar:SetWidth(1)
                r:SetAlpha(0)
                K.Tween(r, 0.3, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, d)
                K.Tween(r.bar, 0.6, function(q) r.bar:SetWidth(math.max(1, w * (1 - (1 - q) ^ 3))) end, function() r.bar:SetWidth(w) end, d)
                if K.CountUp then K.CountUp(r.cols.n, s.n, 0.6, nil, d) else r.cols.n:SetText(s.n) end
            else
                r:SetAlpha(1)
                r.bar:SetWidth(w)
                r.cols.n:SetText(s.n)
            end
        end)
        p.rank:SetPoint("TOPLEFT", 0, -54)
        p.rank:SetPoint("BOTTOMRIGHT")
        p.rank.empty:SetText(L["Noch niemand gestorben. Respekt!"])

        p.recent = K.List(p, 38, function(l)
            local r = K.Row(l)
            r.av = r:CreateTexture(nil, "ARTWORK")
            r.av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.av:SetSize(24, 24)
            r.av:SetPoint("LEFT", 10, 0)
            r.skull = r:CreateTexture(nil, "OVERLAY")
            r.skull:SetTexture(SKULL)
            r.skull:SetSize(12, 12)
            r.skull:SetPoint("BOTTOMRIGHT", r.av, "BOTTOMRIGHT", 4, -3)
            r:Col("who", 44, 170, 13)
            r:Col("where", 222, 210, 12, C.muted)
            r:Col("killer", 440, 190, 12, C.text)
            r:Col("when", 0, 90, 11, C.dim, "RIGHT")
            r.cols.when:ClearAllPoints()
            r.cols.when:SetPoint("RIGHT", -10, 0)
            r:HookScript("OnEnter", function(self)
                if not self.item then return end
                K.ShowTip(self, { deathLine(self.item), "|cff888888" .. (self.item.inst and L["Im Dungeon - nicht auf der Karte"] or L["Klick: auf der Todeskarte zeigen"]) .. "|r" })
            end)
            r:HookScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.item or self.item.inst then return end
                flash, view = self.item.id, "map"
                p.seg:Select("map")
                ns.RefreshPage("deaths")
            end)
            return r
        end, function(r, d)
            local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(d.who)
            local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
            if tc then r.av:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) r.av:SetAlpha(1) else r.av:SetAlpha(0) end
            r.cols.who:SetText(ns.Radar.Label(d.who) .. " |cff888888" .. (d.lvl or "?") .. "|r" .. ownerHint(d.who))
            r.cols.where:SetText(ns.zoneName(d.mapID, d.zone))
            r.cols.killer:SetText((d.killer or "") ~= "" and ("|cffd9786b" .. d.killer .. "|r") or "|cff666666?|r")
            r.cols.when:SetText(ns.ago(d.ts))
            if p.animNext and not ns.db.settings.noAnim then
                r:SetAlpha(0)
                K.Tween(r, 0.25, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, math.min(r.index or 1, 16) * 0.025)
            else
                r:SetAlpha(1)
            end
        end)
        p.recent:SetPoint("TOPLEFT", 0, -54)
        p.recent:SetPoint("BOTTOMRIGHT")
        p.recent.empty:SetText(L["Noch niemand gestorben. Respekt!"])

        p.map = buildMap(p)
        p.map:SetPoint("TOPLEFT", 0, -58)
        p.map:SetPoint("BOTTOMRIGHT")
    end,
    refresh = function(p)
        local list = filtered()
        local week = 0
        for _, d in ipairs(Deaths.All()) do if ns.now() - (d.ts or 0) < 7 * 86400 then week = week + 1 end end
        p.cTotal:Set(#list)
        p.cWeek:Set(week)
        local z, k = {}, {}
        for _, d in ipairs(list) do
            local n = ns.zoneName(d.mapID, d.zone)
            if n ~= "" then z[n] = (z[n] or 0) + 1 end
            if (d.killer or "") ~= "" then k[d.killer] = (k[d.killer] or 0) + 1 end
        end
        local function top(t) local b, bn = nil, 0 for a, v in pairs(t) do if v > bn then b, bn = a, v end end return b, bn end
        local zn, zc = top(z)
        local kn, kc = top(k)
        p.cZone:Set(zn and (zn .. "  |cff888888" .. zc .. "x|r") or "–")
        do
            local t = { "|cffffffff" .. #list .. "|r " .. L["Tode"], "|cffffffff" .. week .. "|r " .. L["diese Woche"] }
            if zn then t[#t + 1] = L["Toedlichstes Gebiet"] .. ": |cffffffff" .. zn .. "|r " .. zc .. "x" end
            if kn then t[#t + 1] = L["Gefaehrlichster Gegner"] .. ": |cffd9786b" .. SEC.Text(kn, 40) .. "|r " .. kc .. "x" end
            p.sum:SetText(table.concat(t, "   ·   "))
        end
        p.cKiller:Set(kn and (SEC.Text(kn, 40) .. "  |cff888888" .. kc .. "x|r") or "–")

        p.focus:SetShown(focus ~= nil)
        if focus then
            p.focus.text:SetText((L["Nur %s"]):format(ns.Radar.Colored(focus)) .. ownerHint(focus))
            p.focus:SetWidth((p.focus.text:GetStringWidth() or 60) + 20)
        end
        p.seg:Select(view)
        p.rank:SetShown(view == "rank")
        p.recent:SetShown(view == "recent")
        p.map:SetShown(view == "map")
        if view == "rank" then
            -- Rangliste aus dem gefilterten Zeitraum
            local by, out = {}, {}
            for _, d in ipairs(list) do
                local mn = mainOf(d.who)
                local s = by[mn]
                if not s then s = { name = mn, n = 0, last = 0, killers = {}, zones = {} } by[mn] = s out[#out + 1] = s end
                s.n = s.n + 1
                s.last = math.max(s.last, d.ts or 0)
                if (d.killer or "") ~= "" then s.killers[d.killer] = (s.killers[d.killer] or 0) + 1 end
                local zz = ns.zoneName(d.mapID, d.zone)
                if zz ~= "" then s.zones[zz] = (s.zones[zz] or 0) + 1 end
            end
            p.maxN = 1
            for _, s in ipairs(out) do
                s.killer, s.killerN = top(s.killers)
                s.zone, s.zoneN = top(s.zones)
                if s.n > p.maxN then p.maxN = s.n end
            end
            table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.last > b.last end)
            p.rank:SetData(out)
            p.animNext = nil
        elseif view == "recent" then
            p.recent:SetData(list)
            p.animNext = nil
        else
            local w, h = p.map:GetWidth() or 0, p.map:GetHeight() or 0
            if w < 100 then w = 720 end
            if h < 100 then h = 420 end
            p.map:Layout(w, h)
            p.map:Update(list)
        end
    end,
})

-- Weltkarte: Totenkoepfe der letzten 14 Tage (vom Karten-Modul gezeichnet)
function Deaths.MapPins()
    if ns.db.settings.deathPins == false then return {} end
    local out = {}
    local days = tonumber(ns.GuildOpt("deDays")) or 14
    for _, d in ipairs(Store.List("deaths", function(d) return not d.inst and (d.mapID or 0) ~= 0 and ns.now() - (d.ts or 0) < days * 86400 end)) do
        out[#out + 1] = d
    end
    return out
end

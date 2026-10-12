-- Oasis: Leistung bei allen Mitgliedern aufzeichnen + Entwickler-Reiter (0.5.562)
--  * jeder Client misst still: Oasis-Rechenzeit je Bild (Blizzards AddOn-Profiler), Spitze, Bildrate, Speicher
--  * alle 15 Min (und auf Anfrage des Entwicklers) eine Zusammenfassung in den geteilten Store "perf"
--  * Seite Entwickler in der Seitenleiste (nur im Entwicklermodus): Freischaltungen, Werkzeuge, Leistungs-Tabelle
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local P = {}
ns.PerfShare = P
local COLL = "perf"

------------------------------------------------------------------------
-- Messen
------------------------------------------------------------------------
local acc = { n = 0, sum = 0, peak = 0, fps = 0, cn = 0, csum = 0, start = 0 }
-- 0.5.568: Kern + geladene Module (Zusatz-Addons) zusammen
local function parts() return ns.ModuleLoader and ns.ModuleLoader.Addons() or { ADDON } end
local function metric(k)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[k]) then return nil end
    local sum, any = 0, false
    for _, a in ipairs(parts()) do
        local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, a, Enum.AddOnProfilerMetric[k])
        if ok and type(v) == "number" then
            any = true
            if k == "PeakTime" then sum = math.max(sum, v) else sum = sum + v end
        end
    end
    return any and sum or nil
end
local function sample()
    local ra = metric("RecentAverageTime")
    local pk = metric("PeakTime")
    local fps = GetFramerate and GetFramerate() or 0
    if acc.start == 0 then acc.start = ns.now() end
    if ra then
        acc.n, acc.sum = acc.n + 1, acc.sum + ra
        if ns.inCombat() then acc.cn, acc.csum = acc.cn + 1, acc.csum + ra end
    end
    if pk and pk > acc.peak then acc.peak = pk end
    acc.fps = acc.fps + fps
    acc.fn = (acc.fn or 0) + 1
end
local function memKB()
    if ns.inCombat() then return P.lastMem end
    local up = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (up and get) then return nil end
    pcall(up)
    local sum = 0
    for _, a in ipairs(parts()) do
        local ok, v = pcall(get, a)
        if ok and v then sum = sum + v end
    end
    if sum > 0 then P.lastMem = math.floor(sum) end
    return P.lastMem
end
function P.Share(force)
    if not (ns.me and ns.me()) or not IsInGuild() or ns.db.settings.sharePerf == false then return end
    if (acc.fn or 0) == 0 then sample() end
    local rec = {
        id = "perf-" .. ns.me(), who = ns.me(), v = ns.version, t = ns.now(),
        avg = acc.n > 0 and math.floor(acc.sum / acc.n * 1000 + 0.5) / 1000 or nil,       -- ms je Bild (Durchschnitt)
        cav = acc.cn > 0 and math.floor(acc.csum / acc.cn * 1000 + 0.5) / 1000 or nil,    -- ms je Bild im Kampf
        peak = math.floor((acc.peak or 0) * 10 + 0.5) / 10,                              -- ms Spitze
        fps = math.floor(acc.fps / math.max(1, acc.fn or 1) + 0.5),
        mem = memKB(), n = acc.n, sess = math.floor((ns.now() - (acc.start or ns.now())) / 60),
        ses = metric("SessionAverageTime"),
        addons = P.AddonCount and P.AddonCount() or nil,
        mods = #parts() - 1,   -- geladene Oasis-Module
    }
    if rec.ses then rec.ses = math.floor(rec.ses * 1000 + 0.5) / 1000 end
    Store.Put(COLL, rec)
    P.lastShare = GetTime()
    if force then ns.print(L["Leistung gesendet."]) end
end
function P.AddonCount()
    local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local Loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not (GetNum and Loaded) then return nil end
    local n = 0
    for i = 1, GetNum() do local ok, l = pcall(Loaded, i) if ok and l then n = n + 1 end end
    return n
end
ns.Listen("LOGIN", function()
    ns.Every(30, function() pcall(sample) end)
    ns.Every(900, function() if not ns.inCombat() then pcall(P.Share) end end)
    ns.After(300, function() if not ns.inCombat() then pcall(P.Share) end end)
end)
-- Entwickler fragt alle: 60 s messen, dann senden
if ns.Comm then
    ns.Comm.On("PERFREQ", function(sender)
        if ns.Comm.FromGuild and not ns.Comm.FromGuild(sender) then return end
        -- 0.5.617: Messung nur auf Anfrage von Offizieren/Gildenleitung
        local role = ns.Admin and ns.Admin.RoleOf and ns.Admin.RoleOf(sender)
        if role ~= "officer" and role ~= "lead" then return end
        if P.reqAt and GetTime() - P.reqAt < 120 then return end
        P.reqAt = GetTime()
        acc.peak = 0
        ns.After(60, function() pcall(P.Share) end)
    end)
end
function P.RequestAll()
    if ns.Comm and ns.Comm.Guild then ns.Comm.Guild("PERFREQ") end
    P.reqAt = nil
    ns.After(60, function() pcall(P.Share) end)
    K.Toast(L["Leistung"], L["Alle Oasis-Nutzer messen jetzt 60 Sekunden und schicken das Ergebnis."], C.accent)
end
-- Rechte: nur der eigene Datensatz
local function installAuth()
    local A = ns.Admin
    if not (A and A.AUTH) then return end
    A.AUTH[COLL] = function(rec, actor) return rec.who ~= nil and A.SameName(rec.who, actor) end
end
installAuth()
ns.Listen("LOGIN", installAuth)
ns.Listen("STORE", function(coll) if coll == COLL then ns.Debounce("perfTab", 1, function() ns.RefreshPage("dev") end) end end)

-- 0.5.568: Diagnose-Daten (nur fuer den Entwickler gedacht) bei allen anderen nicht im Speicher halten
ns.Listen("LOGIN", function()
    if ns.IsDev and ns.IsDev() then return end
    ns.db.blizzProbe, ns.db.talentProbe = nil, nil
    local h = ns.db.talHarvest
    if type(h) == "table" then ns.db.talHarvest = { ts = h.ts, v = h.v, learned = h.learned } end
end)

------------------------------------------------------------------------
-- Emojis und Sounds fuer alle frei (Rang-Sperre aus): beim Entwickler einmalig in der Gilden-Einstellung
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    ns.After(20, function()
        if not (ns.IsDev and ns.IsDev()) or ns.db.emLockFreed then return end
        local A = ns.Admin
        if not (A and A.Cfg and A.Save and A.CanManage and A.CanManage()) then return end
        local ok, cfg = pcall(A.Cfg)
        if not ok or type(cfg) ~= "table" then return end
        ns.db.emLockFreed = true
        if cfg.emLock ~= false then
            local c = {}
            for k, v in pairs(cfg) do c[k] = v end
            c.emLock = false
            pcall(A.Save, c)
            ns.print(L["Emojis und Sounds sind jetzt fuer die ganze Gilde frei."])
        end
    end)
end)

------------------------------------------------------------------------
-- Seite "Entwickler" (Seitenleiste, nur im Entwicklermodus) - 0.5.570
------------------------------------------------------------------------
local function devCard(p, icon, title, sub)
    local c = CreateFrame("Frame", nil, p)
    c:SetFrameLevel(math.max(1, p:GetFrameLevel()))
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 12)) then
        K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
    end
    c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. icon, C.accent)
    c.ic:SetPoint("TOPLEFT", 14, -14)
    c.t = K.Title(c, 14, C.text)
    c.t:SetPoint("LEFT", c.ic, "RIGHT", 8, 0)
    c.t:SetText(title)
    if sub then
        c.s = K.Text(c, 10, C.dim)
        c.s:SetPoint("TOPLEFT", c.ic, "BOTTOMLEFT", 0, -6)
        c.s:SetPoint("RIGHT", -14, 0)
        c.s:SetJustifyH("LEFT")
        c.s:SetText(sub)
    end
    return c
end
local function guildCfg()
    local ok, cfg = pcall(ns.Admin.Cfg)
    return ok and type(cfg) == "table" and cfg or nil
end
-- Spalten der Leistungstabelle: Schluessel, Ueberschrift, x, Breite, rechtsbuendig
local COLS = {
    { k = "name", t = "Name", x = 14, w = 170 },
    { k = "avg", t = "ms/Bild", x = 190, w = 62, r = true },
    { k = "cav", t = "im Kampf", x = 256, w = 66, r = true },
    { k = "peak", t = "Spitze", x = 326, w = 58, r = true },
    { k = "fps", t = "FPS", x = 388, w = 44, r = true },
    { k = "mem", t = "Speicher", x = 436, w = 70, r = true },
    -- 0.5.671: Spalte "Module" weg (seit 0.5.580 ein einziger Ordner, immer 0)
    { k = "v", t = "Version", x = 524, w = 70 },
    { k = "t", t = "gemessen", x = 608, w = 90 },
}
local ROWS = 16
ns.RegisterPage({
    key = "dev", title = "Entwickler", order = 98.5,
    sub = "Freischaltungen, Werkzeuge und Leistung der Mitglieder",
    visible = function() return ns.IsDev and ns.IsDev() or false end,
    build = function(p)
        p.sortKey, p.sortDesc = "avg", true
        -- Freischaltungen (links oben)
        local a = devCard(p, "star_on", L["Freischaltungen"], L["Emojis und Sounds fuer die Gilde oder nur fuer dich"])
        a:SetPoint("TOPLEFT", 0, 0)
        a:SetPoint("RIGHT", p, "CENTER", -7, 0)
        a:SetHeight(128)
        p.lock = K.Toggle(a, L["Emojis & Sounds erst ab Oasis-Rang (Gilde)"], function() local c = guildCfg() return c and c.emLock == true or false end, function(v)
            local cfg = guildCfg()
            if not cfg then return end
            local c = {}
            for k, x in pairs(cfg) do c[k] = x end
            c.emLock = v and true or false
            if not ns.Admin.Save(c) then K.Toast(L["Freischaltungen"], L["Nur die Gildenleitung kann das aendern."], C.amber or C.accent) end
        end)
        p.lock:SetPoint("TOPLEFT", 14, -58)
        p.lock:SetWidth(320)
        p.mine = K.Toggle(a, L["Fuer mich alles freischalten"], function() return ns.db.settings.unlockAll == true end, function(v) ns.db.settings.unlockAll = v and true or nil end)
        p.mine:SetPoint("TOPLEFT", 14, -88)
        p.mine:SetWidth(320)
        -- Werkzeuge (rechts oben)
        local w = devCard(p, "settings", L["Werkzeuge"], L["Diagnose und Abgleich"])
        w:SetPoint("TOPRIGHT", 0, 0)
        w:SetPoint("LEFT", p, "CENTER", 7, 0)
        w:SetHeight(128)
        local tools = {
            { L["Fehler melden"], function() if ns.slash.bug then ns.slash.bug() end end },
            { L["Blockiert-Protokoll"], function() if ns.slash.fehler then ns.slash.fehler() end end },
            { L["Leistung messen (60 s)"], function() if ns.slash.leistung then ns.slash.leistung("60") end end },
            { L["Blizzard-Pruefung"], function() if ns.probes and ns.probes.blizz then ns.probes.blizz() end end },
            { L["Talent-Symbole lernen"], function() if ns.slash.talentsymbole then ns.slash.talentsymbole() end end },
            { L["Jetzt abgleichen"], function() if ns.Comm and ns.Comm.RequestSync then ns.Comm.RequestSync(true) end end },
        }
        p.tools = {}
        for i, t in ipairs(tools) do
            local b = K.Button(w, t[1], 150, 24, "ghost", t[2])
            p.tools[i] = b
        end
        local function layoutTools()
            local cw = (w:GetWidth() or 360) - 28
            local bw = math.floor((cw - 3 * 8) / 3)
            for i, b in ipairs(p.tools) do
                b:SetWidth(bw)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 14 + ((i - 1) % 3) * (bw + 8), -56 - math.floor((i - 1) / 3) * 32)
            end
        end
        w:SetScript("OnSizeChanged", layoutTools)
        layoutTools()
        -- Leistung der Mitglieder (volle Breite)
        local t = devCard(p, "stats", L["Leistung der Mitglieder"], L["Oasis-Rechenzeit je Bild bei jedem Mitglied - gruen gut, gelb mittel, rot hoch"])
        t:SetPoint("TOPLEFT", 0, -142)
        t:SetPoint("BOTTOMRIGHT", 0, 0)
        p.req = K.Button(t, L["Alle jetzt messen"], 150, 24, "primary", function() P.RequestAll() end)
        p.req:SetPoint("TOPRIGHT", -14, -12)
        p.heads = {}
        for _, c in ipairs(COLS) do
            local h = CreateFrame("Button", nil, t)
            h:SetSize(c.w, 18)
            h:SetPoint("TOPLEFT", c.x, -54)
            h.t = K.Text(h, 10, C.dim, c.r and "RIGHT" or "LEFT")
            h.t:SetAllPoints()
            h.t:SetText(K.Upper and K.Upper(L[c.t]) or L[c.t])
            h:SetScript("OnClick", function()
                if p.sortKey == c.k then p.sortDesc = not p.sortDesc else p.sortKey, p.sortDesc = c.k, c.k ~= "name" end
                ns.RefreshPage("dev")
            end)
            h:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
            h:SetScript("OnLeave", function(self) local d = C.dim self.t:SetTextColor(d[1], d[2], d[3]) end)
            p.heads[c.k] = h
        end
        local line = t:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 14, -74)
        line:SetPoint("TOPRIGHT", -14, -74)
        p.rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Frame", nil, t)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 0, -78 - (i - 1) * 21)
            r:SetPoint("RIGHT", t, "RIGHT", 0, 0)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetPoint("TOPLEFT", 8, 0) r.bg:SetPoint("BOTTOMRIGHT", -8, 0)
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
            -- kleiner Balken unter ms/Bild: wie schwer Oasis bei diesem Mitglied ist
            r.bar = r:CreateTexture(nil, "BORDER")
            r.bar:SetHeight(14)
            r.bar:SetPoint("RIGHT", r, "LEFT", COLS[2].x + COLS[2].w, 0)
            r.cells = {}
            for _, c in ipairs(COLS) do
                local fs = K.Text(r, 12, C.text, c.r and "RIGHT" or "LEFT")
                fs:SetPoint("LEFT", c.x, 0)
                fs:SetWidth(c.w)
                fs:SetWordWrap(false)
                r.cells[c.k] = fs
            end
            p.rows[i] = r
        end
        p.empty = K.Text(t, 12, C.dim)
        p.empty:SetPoint("TOPLEFT", 14, -84)
        p.empty:SetText(L["Noch keine Daten - Mitglieder schicken ihre Messung alle 15 Min (ab dieser Version)."])
        p.more = K.Text(t, 10, C.dim)
        p.more:SetPoint("BOTTOMLEFT", 14, 10)
    end,
    refresh = function(p)
        if p.lock then p.lock:Refresh() p.mine:Refresh() end
        local list = Store.List(COLL)
        -- 0.5.663: ein Eintrag je Spieler (Twinks zusammen, z. B. Anna + Tomas) - die neueste Messung zaehlt
        local A, best = ns.Alts, {}
        -- 0.5.671: nur Messungen der letzten 3 Stunden (alte Twink-/Altversionen-Zeilen fallen weg)
        local cutoff = ns.now() - 3 * 3600
        for _, r in ipairs(list) do
            if (r.t or 0) >= cutoff then
                local who = tostring(r.by or r.who or "")   -- voller Name (mit Realm) fuer die Twink-Zuordnung
                local key = who:lower()
                if A and A.Main then
                    local ok, m = pcall(A.Main, who)
                    if ok and m then key = tostring(m):lower() end
                end
                if not best[key] or (r.t or 0) > (best[key].t or 0) then best[key] = r end
            end
        end
        list = {}
        for _, r in pairs(best) do list[#list + 1] = r end
        local k, desc = p.sortKey, p.sortDesc
        table.sort(list, function(a, b)
            local x, y
            if k == "name" then x, y = tostring(a.who or ""):lower(), tostring(b.who or ""):lower()
            elseif k == "v" then x, y = tostring(a.v or ""), tostring(b.v or "")
            elseif k == "t" then x, y = a.t or 0, b.t or 0
            else x, y = tonumber(a[k]) or -1, tonumber(b[k]) or -1 end
            if x == y then return tostring(a.who) < tostring(b.who) end
            if desc then return x > y end
            return x < y
        end)
        for ck, h in pairs(p.heads) do
            local arrow = (ck == k) and (desc and "  v" or "  ^") or ""
            local c
            for _, cc in ipairs(COLS) do if cc.k == ck then c = cc end end
            h.t:SetText((K.Upper and K.Upper(L[c.t]) or L[c.t]) .. arrow)
        end
        p.empty:SetShown(#list == 0)
        local maxAvg = 0.01
        for _, e in ipairs(list) do if (e.avg or 0) > maxAvg then maxAvg = e.avg end end
        for i, r in ipairs(p.rows) do
            local e = list[i]
            r:SetShown(e ~= nil)
            if e then
                local avg = e.avg or 0
                local col = avg >= 1.5 and { 1, 0.38, 0.38 } or (avg >= 0.6 and { 0.91, 0.71, 0.29 } or { 0.4, 0.86, 0.62 })
                local who = tostring(e.who or "?")
                r.cells.name:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(who:match("^[^-]+") or who) or who)
                r.cells.avg:SetText(("%.2f"):format(avg))
                r.cells.avg:SetTextColor(col[1], col[2], col[3])
                r.cells.cav:SetText(e.cav and ("%.2f"):format(e.cav) or "|cff555555-|r")
                r.cells.peak:SetText(e.peak and ("%.0f"):format(e.peak) or "-")
                r.cells.fps:SetText(e.fps or "-")
                r.cells.mem:SetText(e.mem and ("%.1f MB"):format(e.mem / 1024) or "-")
                r.cells.v:SetText("|cff9a9aa5" .. tostring(e.v or "?") .. "|r")
                r.cells.t:SetText("|cff777777" .. ns.ago(e.t or 0) .. "|r")
                r.bar:SetColorTexture(col[1], col[2], col[3], 0.14)
                r.bar:SetWidth(math.max(1, COLS[2].w * math.min(1, avg / maxAvg)))
            end
        end
        p.more:SetText(#list > ROWS and (L["+%d weitere"]):format(#list - ROWS) or "")
    end,
})

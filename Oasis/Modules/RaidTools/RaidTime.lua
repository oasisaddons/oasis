-- Oasis: Raid-Zeit - bester Raid-Termin automatisch
--  * eigener Mitschnitt aus der Gildenliste: wer ist an welchem Wochentag zu welcher Stunde online (je Main, Twinks zaehlen zum Main)
--  * kompakte Wochen-Profile (168 Bits = 42 Hex-Zeichen je Main) werden gildenweit geteilt -> alle sehen dieselbe Heatmap
--    Wer einen Main am laengsten beobachtet hat ("Abdeckung"), dessen Profil gilt.
--  * Heatmap Wochentag x Stunde + Top-3-Zeitfenster je Raidgroesse (10/20/40) mit erwarteter Besetzung inkl. Tanks/Heiler
--  * "Als Termin anlegen" ueber Raid.CreateEvent (oeffentliche Funktion aus Raid.lua)
-- Teilen: eigene Nachrichten (RPLU/RPLQ/RPLA/RPLB), weil Comm.lua nur bekannte Sammlungen annimmt.
-- Die kleine Sync-Hilfe ns.PlannerSync nutzt auch RepPlanner.lua.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
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

local RT = {}
ns.RaidTime = RT
local COLL = "rtweek"
local KEEP = 60 * 86400
local SLOTS = 168
local RAID_START = time({ year = 2026, month = 12, day = 9, hour = 0, min = 0, sec = 0 })
local SIZES = {
    [10] = { t = 2, h = 3, inst = "Barrow Deeps" },
    [20] = { t = 3, h = 5, inst = "Hyjal" },
    [40] = { t = 4, h = 10, inst = "Onyxias Hort" },
}
local DAYS = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" }

if ns.ICONS then ns.ICONS.raidtime = ns.MEDIA .. "icons\\stats" end
-- eigener Navigationspunkt in der Gruppe "Raid" (direkt hinter "raid")
do
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        if g.key == "raid" then
            local has = false
            for _, k in ipairs(g.pages) do if k == "raidtime" then has = true end end
            if not has then
                local pos = #g.pages + 1
                for i, k in ipairs(g.pages) do if k == "raid" then pos = i + 1 end end
                table.insert(g.pages, pos, "raidtime")
            end
        end
    end
end

local function S() return ns.db.settings end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end

------------------------------------------------------------------------
-- Kleine Sync-Hilfe fuer eigene Sammlungen (auch fuer RepPlanner.lua)
-- Sync.Register(coll, keep, onChange) ; Sync.Put(coll, rec) ; Sync.Request(coll)
------------------------------------------------------------------------
local Sync = ns.PlannerSync or {}
ns.PlannerSync = Sync
Sync.colls = Sync.colls or {}
local pendingAns = {}
function Sync.Register(coll, keep, onChange) Sync.colls[coll] = { keep = keep, onChange = onChange } end
local function changed(coll)
    local c = Sync.colls[coll]
    if c and c.onChange then pcall(c.onChange) end
end
function Sync.Put(coll, rec)
    rec.u = math.max(ns.now(), (rec.u or 0) + 1)
    rec.by = rec.by or ns.me()
    Store.merge(coll, rec)
    changed(coll)
    if rec.demo or tostring(rec.id):find("demo-", 1, true) then return rec end
    if IsInGuild() then Comm.SendEx({ ch = "GUILD", bulk = true }, "RPLU", coll, Comm.encodeRecord(rec)) end
    return rec
end
function Sync.Request(coll)
    if not IsInGuild() or not Sync.colls[coll] then return end
    local newest = 0
    for _, r in pairs(Store.coll(coll)) do if not r.demo and (r.u or 0) > newest then newest = r.u end end
    Comm.Guild("RPLQ", coll, math.max(0, newest - 3600))
end
-- Empfang pruefen: direkt (RPLU) nur eigene Datensaetze des Absenders (by = Absender), weitergereicht (RPLB)
-- nie einen Datensatz einem anderen Ersteller zuschlagen; Zeitstempel nicht in der Zukunft; Texte
-- entschaerfen; Sammlung begrenzt
local function sameWho(a, b) return a and b and Comm.whoKey(a) == Comm.whoKey(b) end
local function netOk(coll, rec, sender, relay)
    if type(rec) ~= "table" or type(rec.id) ~= "string" or #rec.id > 80 then return false end
    if Comm.FromGuild and not Comm.FromGuild(sender) then return false end   -- nur Gildenmitglieder
    if rec.demo or rec.id:find("demo-", 1, true) or not rec.by or ns.isMe(rec.by) then return false end
    if not relay and not sameWho(rec.by, sender) then return false end
    rec.u = math.min(tonumber(rec.u) or 0, ns.now() + 300)
    for k, v in pairs(rec) do
        if type(v) == "string" then rec[k] = SEC.Text(v, 400)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then rec[k] = 0 end
    end
    local c = Store.coll(coll)
    local old = c[rec.id]
    if old and old.by and not sameWho(old.by, rec.by) then return false end
    if not old then
        local n = 0
        for _ in pairs(c) do n = n + 1 if n >= 1500 then return false end end
    end
    return true
end
Sync.NetOk = netOk
Comm.On("RPLU", function(sender, _, coll, s)
    if not Sync.colls[coll] or not s then return end
    local rec = Comm.decodeRecord(s)
    if netOk(coll, rec, sender, false) and Store.merge(coll, rec, true, sender) then changed(coll) end
end)
Comm.On("RPLB", function(sender, _, coll, ...)
    if not Sync.colls[coll] then return end
    local any = false
    for i = 1, math.min(select("#", ...), 200) do
        local s = select(i, ...)
        if s and s ~= "" then
            local rec = Comm.decodeRecord(s)
            if netOk(coll, rec, sender, true) and Store.merge(coll, rec, true, sender, true) then any = true end
        end
    end
    if any then changed(coll) end
end)
-- jemand anders antwortet schon
Comm.On("RPLA", function(_, _, target, coll)
    local k = tostring(target) .. "#" .. tostring(coll)
    if pendingAns[k] then pendingAns[k] = "cancel" end
end)
Comm.On("RPLQ", function(sender, channel, coll, since)
    if not Sync.colls[coll] then return end
    since = tonumber(since) or 0
    local k = sender .. "#" .. coll
    if pendingAns[k] then return end
    if not SEC.Rate("rplq:" .. k, 60) then return end   -- keine Fluester-Flut auf Zuruf
    pendingAns[k] = true
    ns.After(math.random(15, 70) / 10, function()
        if pendingAns[k] ~= true then pendingAns[k] = nil return end
        pendingAns[k] = nil
        local batch, size = {}, 0
        for _, r in pairs(Store.coll(coll)) do
            if (r.u or 0) > since and not r.demo and not tostring(r.id):find("demo-", 1, true) then
                batch[#batch + 1] = Comm.encodeRecord(r)
                size = size + #batch[#batch]
            end
        end
        if #batch == 0 then return end
        Comm.Guild("RPLA", sender, coll)
        local part, psize = {}, 0
        for _, s in ipairs(batch) do
            part[#part + 1] = s
            psize = psize + #s
            if psize > 1500 then Comm.WhisperBulk(sender, "RPLB", coll, unpack(part)) part, psize = {}, 0 end
        end
        if #part > 0 then Comm.WhisperBulk(sender, "RPLB", coll, unpack(part)) end
    end)
end)
function Sync.Prune(coll)
    local c = Sync.colls[coll]
    if not c then return end
    local now = ns.now()
    for id, r in pairs(Store.coll(coll)) do
        if now - (r.u or 0) > c.keep then Store.coll(coll)[id] = nil end
    end
end

------------------------------------------------------------------------
-- Bitmaske 168 Stunden <-> 42 Hex-Zeichen (Slot = Wochentag(Mo=0) * 24 + Stunde)
------------------------------------------------------------------------
local HEX = "0123456789abcdef"
function RT.Encode(bits)
    local out = {}
    for d = 0, 41 do
        local v = 0
        for b = 0, 3 do if bits[d * 4 + b] then v = v + 2 ^ b end end
        out[#out + 1] = HEX:sub(v + 1, v + 1)
    end
    return table.concat(out)
end
function RT.Decode(s)
    local bits = {}
    if type(s) ~= "string" then return bits end
    for d = 0, math.min(41, #s - 1) do
        local v = (HEX:find(s:sub(d + 1, d + 1), 1, true) or 1) - 1
        for b = 0, 3 do
            if v % 2 == 1 then bits[d * 4 + b] = true end
            v = math.floor(v / 2)
        end
    end
    return bits
end
local function slotOf(ts)
    local wd = (tonumber(date("%w", ts)) + 6) % 7
    return wd * 24 + tonumber(date("%H", ts)), wd
end
RT.SlotOf = slotOf

------------------------------------------------------------------------
-- Eigener Mitschnitt (lokal): je Slot, in wie vielen Wochen ich da war (cov)
-- und je Main, in wie vielen davon er online war (on)
------------------------------------------------------------------------
local function obs()
    local o = ns.db.rtObs
    if type(o) ~= "table" then o = {} ns.db.rtObs = o end
    o.cov, o.on, o.seen, o.cls = o.cov or {}, o.on or {}, o.seen or {}, o.cls or {}
    return o
end
local function mainOf(name)
    local m = (ns.Alts and ns.Alts.Main) and ns.Alts.Main(name) or name
    return m or name
end
local lastSample = 0
local function sample()
    if not (ns.Radar and ns.Radar.roster) or S().rtTrack == false then return end
    if GetTime() - lastSample < 240 then return end
    lastSample = GetTime()
    local now = ns.now()
    local o = obs()
    local wk = date("%Y-%W", now)
    if o.wk ~= wk then o.wk, o.seen = wk, {} end
    local slot = slotOf(now)
    if not o.seen[slot] then
        o.seen[slot] = true
        o.cov[slot] = (o.cov[slot] or 0) + 1
        -- alte Wochen verblassen lassen (Spielzeiten aendern sich)
        if o.cov[slot] > 8 then
            o.cov[slot] = o.cov[slot] * 0.75
            for _, t in pairs(o.on) do if t[slot] then t[slot] = t[slot] * 0.75 end end
        end
    end
    for _, m in ipairs(ns.Radar.roster) do
        -- 0.5.617 Datenschutz: nur Oasis-Nutzer (wer kein Oasis hat, wird nicht profiliert)
        if m.online and not m.demo and ns.Radar.UsesOasis and ns.Radar.UsesOasis(m.name) then
            local main = mainOf(m.name)
            local k = main .. "#" .. slot
            if not o.seen[k] then
                o.seen[k] = true
                local t = o.on[main] or {}
                o.on[main] = t
                t[slot] = (t[slot] or 0) + 1
                if m.class then o.cls[main] = m.class end
            end
        end
    end
end
ns.Listen("ROSTER", function() pcall(sample) end)

-- eigene Beobachtung eines Mains -> Bits + Abdeckung
local function ownMask(main)
    local o = obs()
    local t = o.on[main]
    if not t then return nil end
    local bits, cov = {}, 0
    for s = 0, SLOTS - 1 do
        local c = o.cov[s] or 0
        if c > 0 then
            cov = cov + math.min(c, 4)
            if (t[s] or 0) / c >= 0.34 then bits[s] = true end
        end
    end
    return bits, math.floor(cov)
end
-- Notbehelf aus dem Spielzeit-Mitschnitt (Members.lua: Tage + Stunden getrennt) -> grobe Maske, Abdeckung 1
local function playMask(main)
    local e = ns.db.play and ns.db.play[main]
    if not e or not e.h or not e.d then return nil end
    local hmax, dsum, dcnt = 0, {}, {}
    for _, s in pairs(e.h) do if s > hmax then hmax = s end end
    if hmax < 1800 then return nil end
    local dmax = 0
    for d, s in pairs(e.d) do
        local y, mo, da = d:match("^(%d+)%-(%d+)%-(%d+)$")
        if y then
            local wd = (tonumber(date("%w", time({ year = tonumber(y), month = tonumber(mo), day = tonumber(da), hour = 12 }))) + 6) % 7
            dsum[wd] = (dsum[wd] or 0) + s
            dcnt[wd] = (dcnt[wd] or 0) + 1
        end
    end
    for wd, s in pairs(dsum) do dsum[wd] = s / dcnt[wd] if dsum[wd] > dmax then dmax = dsum[wd] end end
    if dmax <= 0 then return nil end
    local bits = {}
    for wd = 0, 6 do
        if (dsum[wd] or 0) >= dmax * 0.5 then
            for h = 0, 23 do if (e.h[h] or 0) >= hmax * 0.5 then bits[wd * 24 + h] = true end end
        end
    end
    return bits, 1
end

------------------------------------------------------------------------
-- Teilen: je Main ein Datensatz { id = "rt-<main>", m, b (42 Hex), cov, cls }
------------------------------------------------------------------------
local function recId(main) return "rt-" .. main end
local function publish()
    if S().rtShare == false or demoOn() and not IsInGuild() then return end
    local by = ns.Radar and ns.Radar.byName or {}
    local o = obs()
    local sent = 0
    local mains = {}
    -- 0.5.617: jeder teilt nur noch seine EIGENEN Zeiten (vorher die aller beobachteten Mitglieder)
    local myMain = mainOf(ns.me())
    if o.on[myMain] then mains[1] = myMain end
    for _, main in ipairs(mains) do
        if sent >= 12 then break end
        if by[main] and not by[main].demo then
            local bits, cov = ownMask(main)
            if bits and cov >= 6 then
                local hex = RT.Encode(bits)
                local rec = Store.Get(COLL, recId(main))
                local mineOld = rec and ns.isMe(rec.by)
                local stale = rec and ns.now() - (rec.u or 0) > 7 * 86400
                if not rec or (rec.b ~= hex and (mineOld or cov >= (rec.cov or 0) or stale)) or (stale and mineOld) then
                    Sync.Put(COLL, { id = recId(main), m = main, b = hex, cov = cov, cls = o.cls[main] or "" })
                    sent = sent + 1
                end
            end
        end
    end
end
RT.Publish = publish

------------------------------------------------------------------------
-- Auswertung
------------------------------------------------------------------------
-- Profile aller Mains: geteilte Datensaetze, sonst eigene Beobachtung, sonst Spielzeit-Notbehelf
function RT.Profiles()
    local out, seen = {}, {}
    local by = ns.Radar and ns.Radar.byName or {}
    local hasRoster = ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0
    local minLvl = tonumber(S().rtMinLevel) or 0
    local function add(main, bits, src, cls)
        main = mainOf(main)
        if seen[main] then return end
        local m = by[main]
        if hasRoster and not m then return end
        if minLvl > 0 and m and (m.level or 0) < minLvl then return end
        seen[main] = true
        local roles, known = { dps = true }, false
        if ns.Profile and ns.Profile.RolesOf then roles, known = ns.Profile.RolesOf(main) end
        out[#out + 1] = { name = main, bits = bits, src = src, class = (m and m.class) or cls, roles = roles, known = known }
    end
    for _, r in ipairs(Store.List(COLL)) do
        -- nur selbst geteilte Zeiten (aeltere Versionen haben auch die anderer verteilt)
        if r.demo or (r.by and mainOf(r.by) == r.m) then add(r.m, RT.Decode(r.b), r.demo and "demo" or "shared", r.cls) end
    end
    -- frueher beobachtete Nicht-Nutzer wegwerfen
    if ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0 and ns.Radar.UsesOasis then
        for main in pairs(obs().on) do if not ns.Radar.UsesOasis(main) then obs().on[main] = nil end end
    end
    for main in pairs(obs().on) do
        local bits, cov = ownMask(main)
        if bits and cov > 0 then add(main, bits, "own") end
    end
    for main in pairs(ns.db.play or {}) do
        if not seen[mainOf(main)] then
            local bits = playMask(main)
            if bits then add(main, bits, "play") end
        end
    end
    return out
end

-- Heatmap: je Slot Anzahl Mains + Tanks + Heiler
function RT.Heat(profiles)
    local heat = {}
    for s = 0, SLOTS - 1 do heat[s] = { n = 0, t = 0, h = 0, who = {} } end
    for _, p in ipairs(profiles) do
        for s in pairs(p.bits) do
            local c = heat[s]
            if c then
                c.n = c.n + 1
                if p.roles.tank then c.t = c.t + 1 end
                if p.roles.heal then c.h = c.h + 1 end
                c.who[#c.who + 1] = p
            end
        end
    end
    return heat
end

-- Zeitfenster bewerten: Wahrscheinlichkeit je Main = Anteil der Fensterstunden mit Bit
function RT.Suggest(profiles, size, len)
    local need = SIZES[size] or SIZES[10]
    len = len or tonumber(S().rtLen) or 3
    local evening = S().rtEvening ~= false
    local cands = {}
    for wd = 0, 6 do
        for h = 0, 24 - len do
            if not evening or (h >= 17 and h <= 22) then
                local exp, t, hl, list = 0, 0, 0, {}
                for _, p in ipairs(profiles) do
                    local n = 0
                    for k = 0, len - 1 do if p.bits[wd * 24 + h + k] then n = n + 1 end end
                    local pr = n / len
                    if pr >= 0.5 then
                        exp = exp + pr
                        if p.roles.tank then t = t + pr end
                        if p.roles.heal then hl = hl + pr end
                        list[#list + 1] = { p = p, pr = pr }
                    end
                end
                local score = math.min(exp / size, 1) * 0.5 + math.min(t / need.t, 1) * 0.25 + math.min(hl / need.h, 1) * 0.25
                cands[#cands + 1] = { wd = wd, h = h, len = len, exp = exp, t = t, hl = hl, list = list, score = score + exp * 0.0001 }
            end
        end
    end
    table.sort(cands, function(a, b) return a.score > b.score end)
    local out = {}
    for _, c in ipairs(cands) do
        local clash = false
        for _, o in ipairs(out) do if o.wd == c.wd and math.abs(o.h - c.h) < len then clash = true end end
        if not clash and c.exp > 0 then
            table.sort(c.list, function(a, b) if a.pr ~= b.pr then return a.pr > b.pr end return a.p.name < b.p.name end)
            out[#out + 1] = c
            if #out >= 3 then break end
        end
    end
    return out
end

-- naechster Termin fuer Wochentag/Stunde (fruehestens zum Raidstart 09.12.2026)
function RT.NextTs(wd, h)
    local base = math.max(ns.now() + 3600, RAID_START)
    local t = date("*t", base)
    local ts = time({ year = t.year, month = t.month, day = t.day, hour = h, min = 0, sec = 0 })
    for _ = 0, 8 do
        local cur = (tonumber(date("%w", ts)) + 6) % 7
        if cur == wd and ts >= base then return ts end
        local d = date("*t", ts)
        ts = time({ year = d.year, month = d.month, day = d.day + 1, hour = h, min = 0, sec = 0 })
    end
    return ts
end

function RT.CanCreate()
    if not (ns.Raid and ns.Raid.CreateEvent) then return false, L["Raid-Modul fehlt"] end
    -- Rechte-Modell: Termine anlegen = Schlachtzugsleiter und hoeher (Admin.Can("raid.events"))
    if ns.Admin and ns.Admin.Can and not ns.Admin.Can("raid.events") then return false, L["Termine anlegen duerfen nur Schlachtzugsleiter und hoeher."] end
    return true
end
function RT.CreateFrom(c, size)
    local ok, why = RT.CanCreate()
    if not ok then ns.print(why) return end
    local need = SIZES[size] or SIZES[10]
    local inst = L[need.inst]
    local ts = RT.NextTs(c.wd, c.h)
    local made = ns.Raid.CreateEvent({ title = inst, inst = inst, ts = ts, max = size, kind = "raid",
        desc = (L["Vorschlag Raid-Zeit: erwartet %d (Tanks %d, Heiler %d)"]):format(math.floor(c.exp + 0.5), math.floor(c.t + 0.5), math.floor(c.hl + 0.5)) },
        ns.Raid.toCalendar, 1)
    if made and made[1] then
        K.Toast(L["Termin angelegt"], inst .. "  ·  " .. ns.fmtWhen(ts), C.mint, function()
            ns.ShowPage("raid")
            if ns.Raid.OpenEvent then ns.Raid.OpenEvent(made[1].id) end
        end)
    end
end

------------------------------------------------------------------------
-- Demo-Daten (nur lokal)
------------------------------------------------------------------------
local DEMO = {
    -- Name, Abende (Mo..So als 1/0), von, bis
    { "Grukthar", "1011101", 19, 23 }, { "Zul'mira", "1110110", 18, 22 }, { "Mokrash", "0101011", 20, 24 },
    { "Tavira", "1111100", 19, 22 }, { "Hoknar", "0011111", 17, 21 }, { "Vex'ra", "1010101", 20, 24 },
    { "Bramok", "0111010", 19, 23 }, { "Drogbar", "1011011", 19, 23 }, { "Ka'lesh", "1111000", 18, 22 },
    { "Thrallia", "0011101", 20, 23 }, { "Grimzog", "1001111", 21, 24 }, { "Nakira", "1011100", 19, 22 },
    { "Brokk", "0000111", 14, 20 }, { "Yenzi", "1111111", 19, 21 }, { "Oggrim", "1010110", 18, 22 },
    { "Seraxa", "0110101", 20, 24 }, { "Ragna", "1011001", 19, 23 }, { "Uktar", "0101110", 17, 21 },
}
function RT.SeedDemo()
    for i, d in ipairs(DEMO) do
        local bits = {}
        for wd = 0, 6 do
            if d[2]:sub(wd + 1, wd + 1) == "1" then for h = d[3], d[4] - 1 do if h < 24 then bits[wd * 24 + h] = true end end end
        end
        Store.merge(COLL, { id = "demo-rt-" .. i, demo = true, u = ns.now(), by = ns.fullName(d[1]), m = ns.fullName(d[1]), b = RT.Encode(bits), cov = 20 })
    end
    ns.RefreshPage("raidtime")
end
function RT.RemoveDemo()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    ns.RefreshPage("raidtime")
end

------------------------------------------------------------------------
-- Seite (Neugestaltung): Kopf-Kacheln, Heatmap-Karte, drei Vorschlags-Karten - alles in einer Scrollflaeche,
-- Anordnung haengt von der Breite ab (schmal: untereinander, nichts ueberlappt)
------------------------------------------------------------------------
local ROLE_TEX = { tank = "role_tank", heal = "role_heal", dps = "role_dps" }
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local RANK_COL = { C.amber, { 0.78, 0.80, 0.86, 1 }, { 0.84, 0.55, 0.32, 1 } }
local CARD_H = 190
local function roleIcon(k, size)
    return ("|T%sicons\\%s:%d:%d|t"):format(ns.MEDIA, ROLE_TEX[k], size or 12, size or 12)
end
local function glyph(n) return ns.MEDIA .. "icons\\" .. n end
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function dayShort(wd)
    -- erste 2 Zeichen UTF-8-sicher
    local chars = {}
    for ch in (L[DAYS[wd + 1]]):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
        if #chars >= 2 then break end
    end
    return table.concat(chars)
end
local function fmtWindow(c)
    return (L["%s, %d-%d Uhr"]):format(L[DAYS[c.wd + 1]], c.h, (c.h + c.len) % 24)
end
-- Rahmen auf feste Position setzen und merken (Layout-Pruefung im Test liest body.rects)
local function place(body, key, f, x, y, w, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
    f:SetSize(w, h)
    body.rects[key] = { x = x, y = y, w = w, h = h }
end

-- Messbalken: Symbol + Beschriftung | Balken | Wert
local function newMeter(parent, icon, label, color)
    local m = CreateFrame("Frame", nil, parent)
    m:SetHeight(16)
    m.color = color
    m.ico = K.Glyph(m, 12, glyph(icon), color)
    m.ico:SetPoint("LEFT", 0, 0)
    m.lab = K.Text(m, 10, C.muted)
    m.lab:SetPoint("LEFT", 17, 0)
    m.lab:SetWidth(56)
    m.lab:SetWordWrap(false)
    m.lab:SetText(label)
    m.track = CreateFrame("Frame", nil, m)
    m.track:SetHeight(6)
    K.Fill(m.track, { 1, 1, 1, 0.07 })
    m.fill = m.track:CreateTexture(nil, "ARTWORK")
    m.fill:SetPoint("TOPLEFT") m.fill:SetPoint("BOTTOMLEFT")
    m.fill:SetColorTexture(color[1], color[2], color[3], 0.95)
    m.val = K.Text(m, 11, C.text, "RIGHT")
    m.val:SetPoint("RIGHT", 0, 0)
    m.val:SetWidth(48)
    m.frac, m.tw = 0, 50
    function m:Paint(f)
        self.fill:SetWidth(math.max(0.01, self.tw * f))
        self.fill:SetShown(f > 0)
    end
    function m:Layout(w)
        self:SetWidth(w)
        self.tw = math.max(16, w - 76 - 54)
        self.track:ClearAllPoints()
        self.track:SetPoint("LEFT", 76, 0)
        self.track:SetWidth(self.tw)
        self:Paint(self.frac)
    end
    function m:Set(v, need, anim)
        local f = need > 0 and math.min(1, v / need) or 0
        local ok = v >= need - 0.01
        self.val:SetText(((ok and "|cff66db9e" or "|cffff8a3d") .. math.floor(v + 0.5) .. "|r|cff888888 / " .. need .. "|r"))
        self.frac = f
        if anim and animOn() and f > 0 then
            K.Tween(self.fill, 0.6, function(q) self:Paint(f * (1 - (1 - q) * (1 - q))) end, function() self:Paint(f) end)
        else
            self:Paint(f)
        end
    end
    return m
end

-- Vorschlags-Karte: Rang-Plakette (Ziffern-Grafik mittig), Zeitfenster, drei Balken, Klassen-Symbole, Knopf
local function newSugCard(p, body, i)
    local U = ns.RCUI
    local rc = RANK_COL[i] or C.accent
    local c = U.Card(body, rc)
    c:EnableMouse(true)
    c.idx = i
    c.badge = CreateFrame("Frame", nil, c)
    c.badge:SetSize(32, 32)
    c.badge:SetPoint("TOPLEFT", 12, -12)
    c.glow = c.badge:CreateTexture(nil, "BACKGROUND")
    c.glow:SetTexture(U.EMBER)
    c.glow:SetBlendMode("ADD")
    c.glow:SetSize(58, 58)
    c.glow:SetPoint("CENTER")
    c.glow:SetVertexColor(rc[1], rc[2], rc[3])
    c.glow:SetAlpha(0)
    c.glow:Hide()
    c.ring = c.badge:CreateTexture(nil, "BORDER")
    c.ring:SetTexture(CIRCLE)
    c.ring:SetAllPoints()
    c.ring:SetVertexColor(rc[1], rc[2], rc[3], 0.9)
    c.disc = c.badge:CreateTexture(nil, "ARTWORK")
    c.disc:SetTexture(CIRCLE)
    c.disc:SetSize(28, 28)
    c.disc:SetPoint("CENTER")
    c.disc:SetVertexColor(rc[1] * 0.22, rc[2] * 0.22, rc[3] * 0.22, 1)
    c.num = K.DigitText(c.badge, 14)
    c.num:SetTextColor(math.min(1, rc[1] + 0.15), math.min(1, rc[2] + 0.15), math.min(1, rc[3] + 0.15), 1)
    c.num:SetText(i)
    c.when = K.Title(c, 14, C.text)
    c.when:SetPoint("TOPLEFT", 54, -13)
    c.when:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.when:SetWordWrap(false)
    c.next = K.Text(c, 10, C.muted)
    c.next:SetPoint("TOPLEFT", 54, -32)
    c.next:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.next:SetWordWrap(false)
    c.mExp = newMeter(c, "groups", L["Besetzung"], C.accent)
    c.mTank = newMeter(c, "role_tank", L["Tanks"], C.blue)
    c.mHeal = newMeter(c, "role_heal", L["Heiler"], C.mint)
    c.avHead = K.Text(c, 9, C.dim)
    c.avHead:SetPoint("TOPLEFT", 12, -120)
    c.avHead:SetText(L["Wahrscheinlich dabei"])
    c.av = {}
    c.more = K.Text(c, 10, C.muted)
    c.btn = K.Button(c, L["Als Termin anlegen"], 150, 24, i == 1 and "primary" or "ghost", function()
        if c.cand then RT.CreateFrom(c.cand, p.size) end
    end)
    c.btn:SetScript("OnEnter", function(self)
        local ok, why = RT.CanCreate()
        if c.cand then
            K.ShowTip(self, { L["Als Termin anlegen"], L[SIZES[p.size].inst] .. "  ·  " .. ns.fmtWhen(RT.NextTs(c.cand.wd, c.cand.h)),
                ok and L["Legt einen Raidtermin an (wie auf der Raid-Seite)."] or ("|cffe64047" .. tostring(why) .. "|r") })
        end
    end)
    c.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    K.LockButton(c.btn, function() return (RT.CanCreate()) end, ns.Admin and ns.Admin.Need and ns.Admin.Need("raid.events") or "raidlead")
    -- ganze Karte: wer kommt wahrscheinlich (Rolle, Klassenfarbe, Anteil)
    c:SetScript("OnEnter", function(self)
        local cand = self.cand
        if not cand then return end
        local lines = { fmtWindow(cand) }
        local names = {}
        for k, e in ipairs(cand.list) do
            if k > 21 then names[#names + 1] = "..." break end
            local ic = e.p.roles.tank and roleIcon("tank", 11) or e.p.roles.heal and roleIcon("heal", 11) or ""
            names[#names + 1] = ic .. ns.colorName(e.p.name, e.p.class) .. (e.pr < 1 and (" |cff888888" .. math.floor(e.pr * 100) .. "%|r") or "")
        end
        for k = 1, #names, 3 do lines[#lines + 1] = table.concat(names, ", ", k, math.min(#names, k + 2)) end
        K.ShowTip(self, lines)
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function c:Layout(w)
        self.w = w
        local inner = w - 24
        for k, m in ipairs({ self.mExp, self.mTank, self.mHeal }) do
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", 12, -54 - (k - 1) * 20)
            m:Layout(inner)
        end
        self.fit = math.max(1, math.floor((inner - 30) / 18))
        self.btn:ClearAllPoints()
        self.btn:SetPoint("TOPLEFT", 12, -154)
        self.btn:SetSize(inner, 24)
        self:PaintAvatars()
    end
    function c:PaintAvatars()
        local list = self.cand and self.cand.list or {}
        local fit = self.fit or 8
        local n = math.min(#list, fit)
        for k = 1, math.max(n, #self.av) do
            local t = self.av[k]
            if k <= n then
                if not t then t = self:CreateTexture(nil, "ARTWORK") t:SetSize(16, 16) self.av[k] = t end
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", 12 + (k - 1) * 18, -132)
                U.ClassIcon(t, list[k].p.class)
                t:SetAlpha(list[k].pr >= 1 and 1 or 0.55)
                t:Show()
            elseif t then
                t:Hide()
            end
        end
        self.more:ClearAllPoints()
        self.more:SetPoint("TOPLEFT", 12 + n * 18 + 2, -134)
        self.more:SetText(#list > n and ("+" .. (#list - n)) or "")
    end
    return c
end

-- Heatmap-Karte
local function buildHeat(p, body)
    local U = ns.RCUI
    local hm = U.Card(body, C.accent)
    p.hm = hm
    hm.head = K.GameHead(hm, L["Wer ist wann online"], C.accent)
    hm.head.text:SetText(L["Wer ist wann online"])
    if hm.head.mark then hm.head.mark:Hide() end
    hm.head:SetPoint("TOPLEFT", 14, -12)
    hm.head:SetPoint("RIGHT", hm, "RIGHT", -12, 0)
    hm.cells, hm.hours, hm.days = {}, {}, {}
    for h = 0, 23 do
        hm.hours[h] = K.Text(hm, 9, C.dim, "CENTER")
    end
    hm.cur = CreateFrame("Frame", nil, hm)
    hm.cur:SetFrameLevel((hm:GetFrameLevel() or 1) + 5)
    K.Border(hm.cur, C.text)
    hm.cur:Hide()
    for wd = 0, 6 do
        local t = K.Text(hm, 10, C.muted)
        t:SetText(dayShort(wd))
        hm.days[wd] = t
        for h = 0, 23 do
            local s = wd * 24 + h
            local b = CreateFrame("Button", nil, hm)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b.tex:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
            b.mark = b:CreateTexture(nil, "OVERLAY")
            b.mark:SetPoint("TOPLEFT") b.mark:SetPoint("TOPRIGHT") b.mark:SetHeight(2)
            b.mark:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 1)
            b.mark:Hide()
            b.slot = s
            b:SetScript("OnEnter", function(self)
                hm.cur:ClearAllPoints()
                hm.cur:SetPoint("TOPLEFT", self, "TOPLEFT", -1, 1)
                hm.cur:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1)
                hm.cur:Show()
                hm.days[wd]:SetTextColor(C.text[1], C.text[2], C.text[3])
                local c = p.heat and p.heat[self.slot]
                if not c then return end
                local lines = { (L["%s, %d-%d Uhr"]):format(L[DAYS[wd + 1]], h, (h + 1) % 24),
                    (L["%d online (Tanks %d, Heiler %d)"]):format(c.n, c.t, c.h) }
                local names = {}
                for i, pr in ipairs(c.who) do
                    if i > 14 then names[#names + 1] = "..." break end
                    names[#names + 1] = ns.colorName(pr.name, pr.class)
                end
                if #names > 0 then lines[#lines + 1] = table.concat(names, ", ") end
                K.ShowTip(self, lines)
            end)
            b:SetScript("OnLeave", function()
                hm.cur:Hide()
                hm.days[wd]:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
                GameTooltip:Hide()
            end)
            hm.cells[s] = b
        end
    end
    -- Legende: Farbskala, Markierung, Quellen
    hm.lowT = K.Text(hm, 10, C.dim)
    hm.lowT:SetText(L["wenig"])
    hm.scale = {}
    for k = 1, 6 do
        local t = hm:CreateTexture(nil, "ARTWORK")
        t:SetSize(12, 8)
        local f = 0.15 + 0.85 * (k - 1) / 5
        local a = C.accent
        t:SetColorTexture(a[1] * f + C.field[1] * (1 - f), a[2] * f + C.field[2] * (1 - f), a[3] * f + C.field[3] * (1 - f), 1)
        hm.scale[k] = t
    end
    hm.highT = K.Text(hm, 10, C.dim)
    hm.highT:SetText(L["viele"])
    hm.markT = hm:CreateTexture(nil, "ARTWORK")
    hm.markT:SetSize(12, 3)
    hm.markT:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 1)
    hm.markL = K.Text(hm, 10, C.dim)
    hm.markL:SetText(L["vorgeschlagenes Fenster"])
    hm.src = K.Text(hm, 10, C.dim)
    hm.src:SetWordWrap(true)
    hm.src:SetJustifyV("TOP")
    -- Aufbau-Animation: Spalte fuer Spalte einblenden
    function hm:Sweep()
        if not animOn() then for _, b in pairs(self.cells) do b:SetAlpha(1) end return end
        for _, b in pairs(self.cells) do b:SetAlpha(0) end
        K.Tween(self, 0.7, function(q)
            for s, b in pairs(self.cells) do
                local col = s % 24
                b:SetAlpha(math.max(0, math.min(1, (q - col / 24 * 0.6) / 0.4)))
            end
        end, function() for _, b in pairs(self.cells) do b:SetAlpha(1) end end)
        ns.After(1.5, function() for _, b in pairs(self.cells) do b:SetAlpha(1) end end)
    end
    -- Raster in Breite w anordnen; liefert die Kartenhoehe
    function hm:Layout(w)
        local x0 = 46
        local cw = math.max(6, math.floor((w - x0 - 12) / 24))
        local ch = w >= 600 and 18 or 14
        local step = cw >= 15 and 3 or 6
        for h = 0, 23 do
            local t = self.hours[h]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", x0 + h * cw - 6, -36)
            t:SetWidth(cw + 12)
            t:SetText(h % step == 0 and tostring(h) or "")
        end
        for wd = 0, 6 do
            local y = -50 - wd * (ch + 2)
            self.days[wd]:ClearAllPoints()
            self.days[wd]:SetPoint("TOPLEFT", 14, y - math.floor((ch - 10) / 2))
            for h = 0, 23 do
                local b = self.cells[wd * 24 + h]
                b:ClearAllPoints()
                b:SetSize(math.max(2, cw - 2), ch)
                b:SetPoint("TOPLEFT", x0 + h * cw, y)
            end
        end
        local ly = -50 - 7 * (ch + 2) - 10
        self.lowT:ClearAllPoints()
        self.lowT:SetPoint("TOPLEFT", 14, ly)
        for k, t in ipairs(self.scale) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 52 + (k - 1) * 13, ly - 2)
        end
        self.highT:ClearAllPoints()
        self.highT:SetPoint("TOPLEFT", 52 + 6 * 13 + 4, ly)
        self.markT:ClearAllPoints()
        self.markT:SetPoint("TOPLEFT", 52 + 6 * 13 + 50, ly - 4)
        self.markL:ClearAllPoints()
        self.markL:SetPoint("TOPLEFT", 52 + 6 * 13 + 66, ly)
        self.markL:SetPoint("RIGHT", self, "RIGHT", -12, 0)
        self.markL:SetWordWrap(false)
        self.src:ClearAllPoints()
        self.src:SetPoint("TOPLEFT", 14, ly - 18)
        self.src:SetWidth(math.max(60, w - 28))
        self.src:SetHeight(26)
        return -(ly - 18 - 26) + 10
    end
    return hm
end

ns.RegisterPage({
    key = "raidtime", title = "Raid-Zeit", order = 5.1,
    sub = "Wann passt es den meisten? Heatmap der Gilde und die besten Zeitfenster je Raidgroesse",
    build = function(p)
        p.size = 20
        local U = ns.RCUI
        if not U then
            p.miss = K.Text(p, 13, C.dim, "CENTER")
            p.miss:SetPoint("CENTER")
            p.miss:SetText(L["Raid-Check-Modul fehlt - diese Ansicht braucht seine Bausteine."])
            return
        end
        local sc = U.Scroll(p)
        sc:SetAllPoints()
        p.sc = sc
        local body = sc.content
        p.body = body
        body.rects = {}
        -- 1) Kopf-Kacheln
        p.tiles = {}
        for i, d in ipairs({
            { "profile", "Wochen-Profile", C.blue }, { "raid", "Bestes Fenster", C.amber },
            { "role_tank", "Tanks", C.blue }, { "role_heal", "Heiler", C.mint } }) do
            p.tiles[i] = K.HudTile(body, glyph(d[1]), L[d[2]], d[3])
        end
        -- 2) Steuerleiste: Raidgroesse + Ziel
        local ctrl = CreateFrame("Frame", nil, body)
        p.ctrl = ctrl
        ctrl.lab = K.Text(ctrl, 10, C.dim)
        ctrl.lab:SetPoint("TOPLEFT", 0, -7)
        ctrl.lab:SetText(L["Raidgroesse"])
        p.seg = K.Segments(ctrl, { { key = 10, text = "10" }, { key = 20, text = "20" }, { key = 40, text = "40" } }, function(k)
            p.size = k
            p.animCards = true
            ns.RefreshPage("raidtime")
        end, 60)
        p.seg:SetPoint("TOPLEFT", 92, 0)
        p.seg:Select(20)
        p.info = K.Text(ctrl, 11, C.muted)
        p.info:SetWordWrap(false)
        -- 3) Heatmap
        buildHeat(p, body)
        -- 4) Vorschlaege
        p.sHead = K.GameHead(body, L["Beste Zeitfenster"], C.amber)
        p.sHead.text:SetText(L["Beste Zeitfenster"])
        if p.sHead.mark then p.sHead.mark:Hide() end
        p.cards = {}
        for i = 1, 3 do p.cards[i] = newSugCard(p, body, i) end
        p.empty = U.Empty(body, "stats", C.amber)
        -- Breite wechselt (Fenster ziehen) -> neu anordnen
        sc:HookScript("OnSizeChanged", function() if p.Layout then p:Layout() end end)
        function p:Layout()
            local W = math.floor((self.sc:GetWidth() or 0) - 8)
            if W < 200 then W = 700 end
            local b = self.body
            b.rects = {}
            local y = 0
            local tc = W >= 520 and 4 or 2
            local tw = math.floor((W - (tc - 1) * 8) / tc)
            for i, t in ipairs(self.tiles) do
                local ci, rr = (i - 1) % tc, math.floor((i - 1) / tc)
                place(b, "tile" .. i, t, ci * (tw + 8), y - rr * 74, tw, 66)
                t:Hide()   -- 0.5.854: Kacheln entfallen
            end
            -- Steuerleiste: breit = eine Zeile, schmal = Ziel darunter
            local wide = W >= 600
            place(b, "ctrl", self.ctrl, 0, y, W, wide and 26 or 46)
            self.info:ClearAllPoints()
            if wide then
                self.info:SetPoint("TOPLEFT", self.ctrl, "TOPLEFT", 92 + 160, -6)
            else
                self.info:SetPoint("TOPLEFT", self.ctrl, "TOPLEFT", 0, -30)
            end
            self.info:SetPoint("RIGHT", self.ctrl, "RIGHT", 0, 0)
            y = y - (wide and 26 or 46) - 8
            local hh = self.hm:Layout(W)
            place(b, "heat", self.hm, 0, y, W, hh)
            y = y - hh - 14
            place(b, "shead", self.sHead, 0, y, W, 18)
            y = y - 26
            local n = 0
            for _, c in ipairs(self.cards) do if c.cand then n = n + 1 end end
            if n == 0 then
                local ew = math.min(W, 340)
                place(b, "empty", self.empty, math.floor((W - ew) / 2), y - 6, ew, 150)
                y = y - 166
            else
                local cols = (W >= 660) and 3 or 1
                local cw = cols == 3 and math.floor((W - 20) / 3) or W
                local k = 0
                for _, c in ipairs(self.cards) do
                    if c.cand then
                        local ci, rr = k % cols, math.floor(k / cols)
                        place(b, "card" .. c.idx, c, ci * (cw + 10), y - rr * (CARD_H + 10), cw, CARD_H)
                        c:Layout(cw)
                        k = k + 1
                    end
                end
                y = y - math.ceil(k / cols) * (CARD_H + 10)
            end
            self.layoutH = -y + 6
            self.sc:SetContentHeight(self.layoutH)
        end
        p:HookScript("OnShow", function(self)
            self.fresh = true
            lastSample = 0
            pcall(sample)
        end)
        p.fresh = true
    end,
    refresh = function(p)
        if not p.body then return end
        local profiles = RT.Profiles()
        local heat = RT.Heat(profiles)
        p.heat = heat
        local maxN = 0
        for s = 0, SLOTS - 1 do if heat[s].n > maxN then maxN = heat[s].n end end
        local sugg = RT.Suggest(profiles, p.size)
        local inBest = {}
        for _, c in ipairs(sugg) do for k = 0, c.len - 1 do inBest[c.wd * 24 + c.h + k] = true end end
        local a = C.accent
        for s = 0, SLOTS - 1 do
            local b = p.hm.cells[s]
            local n = heat[s].n
            if n > 0 and maxN > 0 then
                local f = 0.15 + 0.85 * (n / maxN)
                b.tex:SetColorTexture(a[1] * f + C.field[1] * (1 - f), a[2] * f + C.field[2] * (1 - f), a[3] * f + C.field[3] * (1 - f), 1)
            else
                b.tex:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
            end
            b.mark:SetShown(inBest[s] and true or false)
        end
        local nShared, nOwn, nPlay = 0, 0, 0
        for _, pr in ipairs(profiles) do
            if pr.src == "own" then nOwn = nOwn + 1 elseif pr.src == "play" then nPlay = nPlay + 1 else nShared = nShared + 1 end
        end
        p.hm.head:SetCount(maxN > 0 and (L["max. %d gleichzeitig"]):format(maxN) or "")
        p.hm.src:SetText((L["Quellen: %d geteilt, %d eigene Beobachtung, %d grob aus Spielzeit. Ueberfahren zeigt, wer da ist."]):format(nShared, nOwn, nPlay))
        local need = SIZES[p.size]
        p.info:SetText((L["Ziel %d Spieler: mind. %d Tanks, %d Heiler  ·  Fenster %d Std  ·  %s"]):format(p.size, need.t, need.h,
            tonumber(S().rtLen) or 3, L[need.inst]))
        p.sHead:SetCount(#sugg > 0 and tostring(#sugg) or "")
        local fresh = p.fresh
        local anim = fresh or p.animCards
        local canMake = RT.CanCreate()
        for i, c in ipairs(p.cards) do
            local cand = sugg[i]
            c.cand = cand
            c:SetShown(cand ~= nil)
            if cand then
                c.when:SetText(fmtWindow(cand))
                c.next:SetText((L["naechster Termin: %s"]):format(ns.fmtWhen(RT.NextTs(cand.wd, cand.h))))
                c.mExp:Set(cand.exp, p.size, anim)
                c.mTank:Set(cand.t, need.t, anim)
                c.mHeal:Set(cand.hl, need.h, anim)
                c.btn:SetEnabledState(canMake and true or false)
                if anim then K.FadeIn(c, (i - 1) * 0.08) end
            end
        end
        -- freundlicher Leerzustand mit passendem Ausweg
        if #sugg == 0 then
            if #profiles == 0 then
                if S().rtTrack == false then
                    p.empty:Set(L["Der Mitschnitt der Spielzeiten ist aus. Schalte ihn ein, dann lernt Oasis mit jedem Abend dazu."],
                        L["Mitschnitt einschalten"], function() S().rtTrack = true lastSample = 0 pcall(sample) ns.RefreshPage("raidtime") end)
                else
                    p.empty:Set(L["Noch keine Spielzeiten bekannt. Oasis lernt mit jedem Abend, an dem du online bist - und uebernimmt die Profile der anderen."],
                        ns.Demo and ns.Demo.Load and not demoOn() and L["Beispiel ansehen"] or nil,
                        function() if ns.Demo and ns.Demo.Load then ns.Demo.Load() ns.RefreshPage("raidtime") end end)
                end
            elseif S().rtEvening ~= false then
                p.empty:Set(L["Abends ist noch kein Fenster mit genug Leuten. Probier eine kleinere Raidgroesse - oder lass auch Zeiten tagsueber zu."],
                    L["Auch tagsueber"], function() S().rtEvening = false ns.RefreshPage("raidtime") end)
            else
                p.empty:Set(L["Kein Zeitfenster mit genug Leuten. Probier eine kleinere Raidgroesse oder einen kuerzeren Raidabend (Zahnrad)."])
            end
            p.empty:Show()
        else
            p.empty:Hide()
        end
        -- Kacheln
        local best = sugg[1]
        local tAnim = fresh and animOn()
        p.tiles[1]:Set(#profiles, (L["%d geteilt"]):format(nShared), nil, tAnim)
        p.tiles[2]:Set(best and (dayShort(best.wd) .. " " .. best.h .. ":00") or "-",
            best and (L["%d erwartet"]):format(math.floor(best.exp + 0.5)) or "", best and math.min(1, best.exp / p.size), tAnim)
        p.tiles[3]:Set(best and math.floor(best.t + 0.5) or 0, (L["von %d"]):format(need.t), best and math.min(1, best.t / need.t), tAnim)
        p.tiles[4]:Set(best and math.floor(best.hl + 0.5) or 0, (L["von %d"]):format(need.h), best and math.min(1, best.hl / need.h), tAnim)
        p:Layout()
        if fresh then
            p.hm:Sweep()
            for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.06) end
        end
        p.fresh, p.animCards = false, false
    end,
})

------------------------------------------------------------------------
-- Einstellungen (Zahnrad der Seite)
------------------------------------------------------------------------
-- Settings.lua laedt erst nach diesem Modul -> Anmeldung nachholen, sobald alles geladen ist
local function addSettings(build)
    if ns.AddPageSettings then ns.AddPageSettings("raidtime", build)
    else ns.Listen("DB_READY", function() if ns.AddPageSettings then ns.AddPageSettings("raidtime", build) end end) end
end
addSettings(function(det, y)
    det.t = det.t or {}
    local function tog(label, key, desc, def)
        if S()[key] == nil then S()[key] = def end
        local t = K.Toggle(det, L[label], function() return S()[key] ~= false end, function(v) S()[key] = v ns.RefreshPage("raidtime") end, L[desc])
        t:SetPoint("TOPLEFT", 14, y)
        det.t[#det.t + 1] = t
        y = y - 44
    end
    tog("Spielzeiten mitschneiden", "rtTrack", "Merkt sich aus der Gildenliste, wer an welchem Wochentag zu welcher Stunde online ist (nur Mains, Twinks zaehlen zum Main)", true)
    tog("Wochen-Profile mit der Gilde teilen", "rtShare", "Teilt pro Main nur eine kleine Stunden-Maske (wann meist online) - so haben alle dieselbe Heatmap", true)
    tog("Nur Abende vorschlagen", "rtEvening", "Zeitfenster beginnen zwischen 17 und 22 Uhr", true)
    local lbl = K.Text(det, 12, C.text)
    lbl:SetPoint("TOPLEFT", 14, y - 2)
    lbl:SetText(L["Laenge eines Raidabends"])
    local sl = K.Slider(det, 220, 2, 5, 1, function() return tonumber(S().rtLen) or 3 end, function(v) S().rtLen = v ns.RefreshPage("raidtime") end,
        function(v) return (L["%d Std"]):format(v) end)
    sl:SetPoint("TOPLEFT", 220, y)
    det.t[#det.t + 1] = sl
    y = y - 32
    local lbl2 = K.Text(det, 12, C.text)
    lbl2:SetPoint("TOPLEFT", 14, y - 2)
    lbl2:SetText(L["Nur Mains ab Level"])
    local sl2 = K.Slider(det, 220, 0, 60, 5, function() return tonumber(S().rtMinLevel) or 0 end, function(v) S().rtMinLevel = v ns.RefreshPage("raidtime") end,
        function(v) return v == 0 and L["alle Level"] or tostring(v) end)
    sl2:SetPoint("TOPLEFT", 220, y)
    det.t[#det.t + 1] = sl2
    y = y - 32
    return y - 10
end)

------------------------------------------------------------------------
-- /oa probe raidzeit  (kette an vorhandene probe-Befehle anderer Module)
------------------------------------------------------------------------
local function probeRaidTime()
    local o = obs()
    local covSlots, mains = 0, 0
    for s = 0, SLOTS - 1 do if (o.cov[s] or 0) > 0 then covSlots = covSlots + 1 end end
    for _ in pairs(o.on) do mains = mains + 1 end
    ns.print(("Raid-Zeit: Slot jetzt %d (date %%w=%s %%H=%s), Woche %s"):format(slotOf(ns.now()), date("%w"), date("%H"), date("%Y-%W")))
    ns.print(("  beobachtete Stunden-Slots: %d/168, Mains beobachtet: %d, geteilte Profile: %d"):format(covSlots, mains, #Store.List(COLL)))
    ns.print(("  Gildenliste: %d Eintraege, Alts.Main: %s, Profile.RolesOf: %s, Raid.CreateEvent: %s, Termin-Recht: %s"):format(
        ns.Radar and ns.Radar.roster and #ns.Radar.roster or -1, tostring(ns.Alts and ns.Alts.Main ~= nil), tostring(ns.Profile and ns.Profile.RolesOf ~= nil),
        tostring(ns.Raid and ns.Raid.CreateEvent ~= nil), tostring((RT.CanCreate()))))
    local ps = RT.Profiles()
    ns.print(("  Profile gesamt: %d"):format(#ps))
end
RT.Probe = probeRaidTime
do
    local prev = ns.slash.probe
    ns.slash.probe = function(arg)
        local what = ((arg or ""):match("^(%S+)") or ""):lower()
        if what == "raidzeit" or what == "raidtime" then probeRaidTime() return end
        if prev then return prev(arg) end
        ns.print(L["Probe: /oa probe raidzeit | /oa probe ruf"])
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
Sync.Register(COLL, KEEP, function() ns.RefreshPage("raidtime") end)
ns.Listen("LOGIN", function()
    Sync.Prune(COLL)
    ns.After(25, function() Sync.Request(COLL) end)
    ns.After(90, publish)
    ns.Every(900, publish)
    local D = ns.Demo
    if D and not D.rtHooked then
        D.rtHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) RT.SeedDemo() end
        D.Remove = function(...) remove(...) RT.RemoveDemo() end
        if D.IsActive() then ns.After(3, RT.SeedDemo) end
    end
end)
end)

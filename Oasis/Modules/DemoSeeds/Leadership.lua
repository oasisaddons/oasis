-- Oasis: Demo-Daten fuer Gildenleitung und Kleinkram, der bisher leer blieb (nur /oa demo)
-- Gildenprotokoll ("audit"), Ehemalige ("formers"), Bewerber ("recruits"), Bannliste ("bans"), Sound-Sperren ("sndmute"),
-- Raid-Anwesenheit ("attend"), Bankwert-Verlauf ("bankworth"), angehefteter Chat ("chatpin"), Karten-Marker ("markers"),
-- Berufs-Abklingzeiten ("profcd").
-- Alles nur ueber ctx.put (Store.merge mit demo=true) - Comm schickt nichts davon an die Gilde. Echte Datensaetze mit
-- derselben ID werden nie ueberschrieben (putNew), sonst waeren sie nach "Demo aus" weg.
local ADDON, ns = ...

local function seed(ctx)
    local Store = ns.Store
    local nm, now, P = ctx.nm, ctx.now, ctx.people
    local function short(i) return ns.short(nm(i)) end
    local function putNew(coll, rec)
        local old = Store.Get(coll, rec.id)
        if old and not old.demo then return end
        ctx.put(coll, rec)
    end

    -- Gildenprotokoll: Befoerderungen, Beitritte, Austritte, ein Rauswurf
    local AUD = {
        { "join", 1800, 23 }, { "promote", 5400, 9, 5, "Veteran" }, { "join", 26 * 3600, 19 }, { "promote", 30 * 3600, 14, 16, "Offizier" },
        { "leave", 2 * 86400, nil, nil, nil, "Brakthar" }, { "demote", 3 * 86400, 9, 21, "Mitglied" }, { "join", 4 * 86400, 15 },
        { "kick", 5 * 86400, 14, nil, nil, "Grimmzahn" }, { "promote", 6 * 86400, 1, 2, "Veteran" }, { "join", 8 * 86400, 12 },
        { "join", 9 * 86400, 7 }, { "leave", 11 * 86400, nil, nil, nil, "Melvara" }, { "promote", 12 * 86400, 9, 10, "Raider" },
    }
    for i, a in ipairs(AUD) do
        local kind, ago, actor, target, rank, outsider = a[1], a[2], a[3], a[4], a[5], a[6]
        local rec = { id = "demo-aud-" .. i, kind = kind, ts = now - ago, b = "", r = "" }
        if kind == "promote" or kind == "demote" then rec.a, rec.b, rec.r = short(actor), short(target), rank
        elseif kind == "kick" then rec.a, rec.b = outsider, short(actor)
        elseif kind == "join" then rec.a = short(actor)
        else rec.a = outsider end
        ctx.put("audit", rec)
    end

    -- Ehemalige: mit Rang, Stufe, Klasse, Notiz und wie sie gegangen sind
    local FORM = {
        { "Brakthar", "Mitglied", 27, "WARRIOR", "", 41, 2, "leave" },
        { "Grimmzahn", "Anwaerter", 14, "ROGUE", "Probezeit", 9, 5, "kick", 14 },
        { "Melvara", "Veteran", 38, "PRIEST", "Heilerin, Twink von Sarnok", 96, 11, "leave" },
        { "Sarnok", "Veteran", 40, "HUNTER", "", 96, 11, "leave" },
        { "Uzgrim", "Mitglied", 22, "SHAMAN", "seit Wochen offline", 63, 19, "kick", 9 },
    }
    for i, f in ipairs(FORM) do
        ctx.put("formers", { id = "demo-fm-" .. i, name = f[1], full = ns.fullName(f[1]), rank = f[2], lvl = f[3], cls = f[4], note = f[5],
            joined = now - f[6] * 86400, left = now - f[7] * 86400, how = f[8], by = f[9] and short(f[9]) or nil,
            main = f[1] == "Melvara" and "Sarnok" or nil })
    end

    -- Bewerber in allen vier Stufen
    local REC = {
        { "Tharuk", "Schamane 24, sucht ruhige Gilde zum Leveln", "app", nil, 3 * 3600 },
        { "Ysmera", "Magierin 31, kennt Drogbar aus dem Dungeon", "app", nil, 20 * 3600 },
        { "Kazrim", "Krieger-Tank 36, will raiden", "trial", 9, 3 * 86400 },
        { "Lunaya", "Druidin 29, Probezeit bis Sonntag", "trial", 14, 5 * 86400 },
        { "Borgash", "Jaeger 40, aufgenommen", "member", 1, 9 * 86400 },
        { "Zilvik", "meldet sich nicht mehr", "no", nil, 12 * 86400 },
    }
    for i, r in ipairs(REC) do
        ctx.put("recruits", { id = "demo-rec-" .. i, name = r[1], note = r[2], st = r[3], pate = r[4] and nm(r[4]) or nil, ts = now - r[5] })
    end

    -- Bannliste und Sound-Sperren
    ctx.put("bans", { id = "demo-ban-1", name = "Ninjazul", reason = "Hat in Uldaman die Beute der Gruppe eingesteckt", by = nm(9), ts = now - 6 * 86400 })
    ctx.put("bans", { id = "demo-ban-2", name = "Goldspam", reason = "Goldverkaeufer, fluestert Mitglieder an", by = nm(14), ts = now - 15 * 86400 })
    ctx.put("sndmute", { id = "demo-sm-1", name = short(20), full = nm(20), reason = "Zu viele Sounds im Gildenchat", by = nm(9), ts = now - 2 * 86400 })

    -- Raid-Anwesenheit: vier Abende, nicht immer dieselben Leute
    local RAIDS = {
        { 2, "Geschmolzener Kern", "Ragnaros", 10, { 1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13, 14, 16, 18, 19, 21, 22, 23 } },
        { 5, "Onyxias Hort", "Onyxia", 1, { 1, 2, 3, 5, 6, 7, 9, 10, 12, 14, 16, 18, 21, 22 } },
        { 9, "Geschmolzener Kern", "Majordomus Exekutus", 9, { 1, 2, 4, 5, 6, 9, 10, 12, 13, 14, 16, 19, 21, 22, 23 } },
        { 16, "Zul'Gurub", "Hakkar", 10, { 2, 3, 4, 5, 7, 9, 10, 13, 14, 16, 18, 19 } },
    }
    for _, r in ipairs(RAIDS) do
        local day = date("%Y-%m-%d", now - r[1] * 86400)
        local names = {}
        for _, i in ipairs(r[5]) do if P[i] then names[#names + 1] = nm(i) end end
        table.sort(names)
        putNew("attend", { id = day .. "@" .. r[2], d = day, inst = r[2], n = table.concat(names, ","), b = r[4], last = r[3], ts = now - r[1] * 86400 })
    end

    -- Bankwert der letzten 30 Tage: waechst langsam, mit einem Einkauf dazwischen
    local worth = 1840000
    for d = 30, 0, -1 do
        worth = worth + 21000 + ((d * 7919) % 17) * 1500
        if d == 12 then worth = worth - 260000 end   -- Gildenbank hat Rezepte gekauft
        local key = date("%Y%m%d", now - d * 86400)
        putNew("bankworth", { id = "bw-" .. key, day = key, worth = worth, ts = now - d * 86400 })
    end

    -- angeheftete Nachricht im Gildenchat (nur wenn nichts Echtes angeheftet ist)
    putNew("chatpin", { id = "pin", s = nm(9), m = "Freitag 20 Uhr Raid - bitte im Kalender anmelden und Feuerschutz mitbringen!", ts = now - 3 * 3600 })

    -- Karten-Marker im eigenen Gebiet: Treffpunkt, Vorsicht, Notiz
    local map = C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player"))
    if type(map) == "number" then
        local MK = {
            { "meet", 0.46, 0.52, "Treffpunkt fuer die Dungeon-Gruppe", 9, 600, 3600 },
            { "danger", 0.61, 0.38, "Elite-Patrouille, nicht allein hingehen", 4, 1800, 2 * 3600 },
            { "note", 0.33, 0.66, "Hier steht der Haendler mit den Rezepten", 16, 86400, 7 * 86400 },
            { "note", 0.55, 0.71, "Guter Platz zum Kraeutersammeln", 2, 2 * 86400, 7 * 86400 },
        }
        for i, m in ipairs(MK) do
            ctx.put("markers", { id = "demo-mk-" .. i, kind = m[1], map = map, x = m[2], y = m[3], text = m[4], by = nm(m[5]),
                ts = now - m[6], exp = now + m[7] })
        end
    end

    -- Berufs-Abklingzeiten: wer kann gerade transmutieren, wer muss warten
    ctx.put("profcd", { id = "pcd-" .. nm(2), who = nm(2), cd = "transmute:0,salt:" .. (now + 2 * 86400) })
    ctx.put("profcd", { id = "pcd-" .. nm(16), who = nm(16), cd = "transmute:" .. (now + 19 * 3600) .. ",mooncloth:" .. (now + 3 * 86400) })
    ctx.put("profcd", { id = "pcd-" .. nm(22), who = nm(22), cd = "mooncloth:0" })
end

if ns.Demo and ns.Demo.AddSeed then ns.Demo.AddSeed("Leitung", seed) end

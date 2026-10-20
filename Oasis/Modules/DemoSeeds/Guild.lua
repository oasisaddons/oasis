-- Oasis: Demo-Daten fuer den Bereich "Gilde" (nur /oa demo)
-- Gildenchat (ns.db.gchat + ns.db.linkHist, lokal), Kampf-Rangliste ("combat"), Gildenziele
-- ("ggoals"/"ggcontrib") und Durchsagen ("notices"). Lagerfeuer fuellt Camp.lua selbst (Camp.SeedDemo).
-- Chatzeilen tragen src="discord" (ohne dc-Kennzeichen): so zeigt GuildChat sie normal an, gibt sie
-- beim Nachladen verpasster Nachrichten (GCREQ) aber nie an andere Oasis-Nutzer weiter.
local ADDON, ns = ...

-- Item-Links wie im echten Chat (Farbe nach Qualitaet)
local function link(id, name, q)
    local col = ({ [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" })[q or 1]
    return "|c" .. col .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r", "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h"
end

-- { Person, Minuten zurueck (heute) bzw. Uhrzeit "HH:MM" (gestern), Text }
-- Platzhalter: {L1}.. = Item-Links aus LINKS
local LINKS = {
    { 6505, "Krallen des Kreuzzueglers", 3 }, { 1482, "Schattenzahn", 3 }, { 9379, "Sang'thraze der Ablenker", 3 },
    { 6475, "Muster: Wildleder-Gamaschen", 2 }, { 10019, "Traumgewirkte Handschuhe", 2 }, { 4306, "Seidenstoff", 1 },
    { 6448, "Peitschenschwanzmesser", 3 }, { 13457, "Grosser Feuerschutztrank", 1 },
}
local YESTERDAY = {
    { 9, "17:42", "Abend zusammen :wave:" },
    { 14, "17:44", "n'Abend Drogbar o/" },
    { 3, "18:05", "Wer hat Lust auf Tiefschwarze Grotte? Brauchen noch Heiler + 1 DD" },
    { 5, "18:06", "ich komm mit, kann heilen" },
    { 21, "18:07", "bin dabei als Tank, bin aber erst 25 :sweat:" },
    { 3, "18:08", "passt scho, inv kommt" },
    { 12, "18:40", "{S:trommel}" },
    { 16, "19:12", "Hat jemand {L6} uebrig? Brauche 20 fuer Taschen" },
    { 2, "19:13", "hab 14 in der Bank, schick ich dir per Post" },
    { 16, "19:14", "du bist die Beste <3" },
    { 10, "20:01", "Raid-Anmeldung fuer Freitag ist offen, tragt euch bitte im Kalender ein :pray:" },
    { 4, "20:30", "Endlich {L1} aus dem Kloster :D" },
    { 18, "20:31", "gz! :party:" },
    { 1, "20:31", "gz Tavira" },
    { 13, "21:15", "Wer kann mir {L4} herstellen? Mats hab ich" },
    { 22, "21:17", "ich kann das, komm nach Orgrimmar" },
    { 6, "22:48", "gn8 Leute :sleep:" },
    { 20, "23:20", "{S:fanfare}" },
}
local TODAY = {
    { 14, 290, "Moin zusammen :coffee:" },
    { 2, 284, "Guten Morgen :)" },
    { 15, 251, "Kann mir wer den Weg nach Burg Schattenfang erklaeren? :think:" },
    { 9, 249, "Silberwald, suedlich vom Grabmal, oben auf dem Huegel" },
    { 15, 247, "danke dir! :thumbsup:" },
    { 7, 213, "Gruppe fuer Tiefschwarze Grotte sucht noch Heiler, Treffpunkt Zoram'gar" },
    { 23, 211, "bin dabei!" },
    { 7, 208, "inv ist raus" },
    { 1, 175, "Glueckwunsch zu Level 40, Ka'lesh! Reittier schon gekauft? :tada:" },
    { 10, 174, "Danke! Gold reicht leider noch nicht ganz :sob:" },
    { 16, 172, "gz! Ich leg dir was in die Gildenbank" },
    { 10, 171, "ernsthaft? danke Yenzi :love:" },
    { 12, 166, "{S:muenze}" },
    { 5, 140, "Seht mal, {L2} im AH fuer 18g. Lohnt sich das?" },
    { 13, 139, "fuer Schurken auf jeden Fall" },
    { 19, 120, "Wie kriegt man eigentlich den Totem der Erde? :hmm:" },
    { 10, 118, "Quest bei Kranal Fiss in Klingenhuegel, ganz easy" },
    { 18, 96, "Uldaman heute Abend 20 Uhr? Brauchen noch Tank" },
    { 9, 95, "ich tanke, Heiler?" },
    { 14, 93, "bin um 20 Uhr da :ok:" },
    { 18, 92, "top, damit sind wir 4 - noch ein DD" },
    { 24, 91, "Platz noch frei? Morgra meldet sich :muscle:" },
    { 4, 70, "Zul'Farrak gelaufen, {L3} gedroppt und keiner braucht ihn :lol:" },
    { 1, 69, "her damit :D" },
    { 17, 55, "{S:wuerfel}" },
    { 16, 41, "Bank-Info: {L8} sind wieder 12 Stueck auf Lager fuer den Raid" },
    { 3, 34, "Danke fuer die Gruppe vorhin, war super lustig :gg:" },
    { 21, 33, "jederzeit wieder!" },
    { 12, 22, "{L7} vom Grabhuegel... endlich :fire:" },
    { 2, 21, "gz Thrallia!" },
    { 20, 15, "Hat einer {L5} gesehen? Brauch die fuer mein Twink-Set" },
    { 14, 12, "Maraudon dropt die, frag Tavira" },
    { 4, 10, "jup, die hab ich sogar doppelt - meld dich" },
    { 9, 4, "Pre-Raid-Check in 30 min, bitte Flaschen und Buffs mitbringen :swords:" },
    { 23, 2, "alles klar Chef :salute:" },
}

local function fill(text)
    local used = {}
    text = text:gsub("{L(%d)}", function(n)
        local l = LINKS[tonumber(n)]
        if not l then return "" end
        local colored, raw = link(l[1], l[2], l[3])
        used[#used + 1] = { id = l[1], raw = raw }
        return colored
    end)
    -- Sounds: im Chat als {s:key} (wird von UI/Sound.lua als Lautsprecher-Zeile gezeigt)
    text = text:gsub("{S:(%w+)}", "{s:%1}")
    return text, used
end

local function seedChat(ctx)
    ns.db.gchat = ns.db.gchat or {}
    local l = ns.db.gchat
    local now = ctx.now
    local t = date("*t", now)
    local midnight = now - (t.hour * 3600 + t.min * 60 + t.sec)
    local rows = {}
    for _, y in ipairs(YESTERDAY) do
        local h, m = y[2]:match("(%d+):(%d+)")
        rows[#rows + 1] = { y[1], midnight - 86400 + tonumber(h) * 3600 + tonumber(m) * 60 + math.random(0, 50), y[3] }
    end
    -- heute: so weit zurueck wie angegeben, aber nie vor Mitternacht (frueh am Morgen zusammenschieben)
    local span = math.max(60, now - midnight - 60)
    for _, d in ipairs(TODAY) do
        local back = d[2] * 60
        if back > span then back = math.floor(span * d[2] / 300) end
        rows[#rows + 1] = { d[1], now - back - math.random(0, 20), d[3] }
    end
    local hist = {}
    for _, r in ipairs(rows) do
        local p = ctx.people[r[1]]
        local msg, used = fill(r[3])
        local e = { ts = r[2], s = ctx.nm(r[1]), m = msg, c = p and p[2], src = "discord", demo = true }
        -- nach Zeit einsortieren
        local pos = #l + 1
        while pos > 1 and (l[pos - 1].ts or 0) > e.ts do pos = pos - 1 end
        table.insert(l, pos, e)
        for _, u in ipairs(used) do hist[#hist + 1] = { id = u.id, raw = u.raw, who = e.s, ts = e.ts, demo = true } end
    end
    -- Link-Gedaechtnis (Seitenkarte "Zuletzt verlinkt" nimmt auch aeltere Links von hier)
    ns.db.linkHist = ns.db.linkHist or {}
    table.sort(hist, function(a, b) return a.ts > b.ts end)
    for i = #hist, 1, -1 do table.insert(ns.db.linkHist, 1, hist[i]) end
    if ns.GuildChat and ns.GuildChat.ClearRenderCache then pcall(ns.GuildChat.ClearRenderCache) end
end

-- Kampf-Rangliste: Werte grob nach Classic-Stufe
local HIT = { WARRIOR = 11565, MAGE = 8401, HUNTER = 20902, ROGUE = 11293, WARLOCK = 11660, SHAMAN = 15207, DRUID = 9912, PRIEST = 10947, PALADIN = 20271 }
local HEAL = { PRIEST = 10963, SHAMAN = 10396, DRUID = 9889, PALADIN = 19943 }
local ZONES = { "Tiefschwarze Grotte", "Scharlachrotes Kloster", "Uldaman", "Zul'Farrak", "Maraudon", "Arathihochland", "Desolace", "Tanaris", "Burg Schattenfang", "Kral der Klingenhauer" }
local function seedCombat(ctx)
    local now, wk = ctx.now, date("%Y-%W")
    for i, p in ipairs(ctx.people) do
        local cls, L, roles = p[2], p[3], p[6] or ""
        if L >= 10 then
            local f = 0.8 + ((i * 37) % 40) / 100           -- feste Streuung je Person
            local dps = (1.5 * L + 0.07 * L * L) * f
            if roles == "h" then dps = dps * 0.45 end
            local dur = 35 + (i * 13) % 60
            local z = ZONES[(i % #ZONES) + 1]
            local r = { id = "demo-cbt-" .. ctx.nm(i), who = ctx.nm(i), cls = cls, v = ns.version, t = now - i * 1800 }
            r.dps, r.dpsz, r.dpst = math.floor(dps + 0.5), z, now - i * 5400
            r.bd, r.bdz, r.bdt = math.floor(dps * dur * 1.1), z, now - i * 5400
            r.mh, r.mhz, r.mht, r.mhs = math.floor((6 * L + 0.25 * L * L) * f * (cls == "MAGE" and 1.3 or cls == "ROGUE" and 1.15 or 1)), z, now - i * 7200, HIT[cls]
            if HEAL[cls] and roles:find("h") then
                local hps = (2.2 * L + 0.09 * L * L) * f
                r.bh, r.bhz, r.bht = math.floor(hps * dur * 1.2), z, now - i * 4000
                r.mhh, r.mhhz, r.mhht, r.mhhs = math.floor((5 * L + 0.2 * L * L) * f), z, now - i * 4000, HEAL[cls]
            end
            local tankF = roles:find("t") and 3.2 or 0.9
            r.bt, r.btz, r.btt = math.floor((1.3 * L + 0.06 * L * L) * dur * tankF * f), z, now - i * 3000
            r.wk = wk
            r.wd = math.floor(dps * (600 + (i * 211) % 2400))
            r.wh = r.bh and math.floor(r.bh * (6 + i % 9)) or 0
            r.wt = math.floor(r.bt * (4 + i % 7))
            r.wf = 15 + (i * 7) % 60
            ctx.put("combat", r)
        end
    end
end

-- Gildenziele + Beitraege
local function seedGoals(ctx)
    local now, nm = ctx.now, ctx.nm
    ctx.put("ggoals", { id = "demo-gg1", by = nm(9), created = now - 9 * 86400, icon = 13457,
        title = "Vorrat fuer den Geschmolzenen Kern",
        desc = "Feuerschutz und Traenke fuer unseren ersten MC-Abend. Alles in die Gildenbank (Yenzi).",
        s1 = "Alchemist mit Rezept fuer Feuerschutz finden", k1 = 1,
        s2 = "Elementarfeuer farmen (Brennende Steppe)", k2 = 1,
        s3 = "Vorrat an Bankcharakter uebergeben",
        m1 = "13457:40", m2 = "13446:60", m3 = "13444:40" })
    ctx.put("ggoals", { id = "demo-gg2", by = nm(16), created = now - 4 * 86400, icon = 1251,
        title = "Stoff fuer Verbaende",
        desc = "Die Gildenbank verteilt Verbaende an alle unter 40. Spendet bitte euren Stoff!",
        m1 = "2589:500", m2 = "2592:300", m3 = "4306:200" })
    ctx.put("ggoals", { id = "demo-gg3", by = nm(1), created = now - 2 * 86400, icon = 5665,
        title = "Zehn Mitglieder mit Reittier",
        desc = "Wir helfen allen auf Stufe 40 mit Gold, Gruppen und Dungeon-Runs.",
        s1 = "Gold-Topf in der Gildenbank anlegen", k1 = 1,
        s2 = "Dungeon-Abende fuer Stufe 30-40 planen", k2 = 1,
        s3 = "5 Mitglieder mit Reittier", k3 = 1,
        s4 = "10 Mitglieder mit Reittier" })
    ctx.put("ggoals", { id = "demo-gg4", by = nm(14), created = now - 20 * 86400, icon = 5976, fin = 1,
        title = "Gildenwappenrock fuer alle",
        desc = "Einheitlicher Auftritt bei Raids und Fotos.",
        s1 = "Wappen im Gildenrat abstimmen", k1 = 1, s2 = "Wappenrock-Gold sammeln", k2 = 1, s3 = "An alle verteilt", k3 = 1 })
    -- Beitraege: { Ziel, Material-Nr, Person, Menge }
    local C = {
        { "demo-gg1", 1, 16, 12 }, { "demo-gg1", 1, 17, 9 }, { "demo-gg1", 1, 5, 4 },
        { "demo-gg1", 2, 7, 20 }, { "demo-gg1", 2, 13, 14 }, { "demo-gg1", 2, 17, 10 },
        { "demo-gg1", 3, 16, 18 }, { "demo-gg1", 3, 5, 6 },
        { "demo-gg2", 1, 2, 160 }, { "demo-gg2", 1, 15, 85 }, { "demo-gg2", 1, 19, 60 }, { "demo-gg2", 1, 23, 120 },
        { "demo-gg2", 2, 4, 90 }, { "demo-gg2", 2, 18, 70 }, { "demo-gg2", 2, 21, 45 },
        { "demo-gg2", 3, 14, 60 }, { "demo-gg2", 3, 16, 40 },
    }
    for _, c in ipairs(C) do
        ctx.put("ggcontrib", { id = c[1] .. "|" .. c[2] .. "|" .. nm(c[3]), g = c[1], i = c[2], n = c[4], who = nm(c[3]) })
    end
end

-- Durchsagen der Gildenleitung (Admin.Notices: g = Gildenname, by muss Leitung sein -> Offiziere der Demo)
local function seedNotices(ctx)
    local g = ns.Admin and ns.Admin.GuildName and ns.Admin.GuildName()
    if not g then return end
    local now, nm = ctx.now, ctx.nm
    ctx.put("notices", { id = "demo-note1", kind = "notice", g = g, by = nm(9), imp = true, ts = now - 3 * 3600,
        title = "Freitag: erster Raid-Abend", text = "20 Uhr Treffen vor Orgrimmar. Bitte im Kalender anmelden und Feuerschutz mitbringen." })
    ctx.put("notices", { id = "demo-note2", kind = "notice", g = g, by = nm(14), imp = false, ts = now - 30 * 3600,
        title = "Gildenbank aufgeraeumt", text = "Verbaende und Traenke fuer alle unter 40 liegen im zweiten Fach. Einfach nehmen!" })
    ctx.put("notices", { id = "demo-note3", kind = "notice", g = g, by = nm(1), imp = false, ts = now - 4 * 86400,
        title = "Willkommen, neue Mitglieder", text = "Schoen, dass ihr da seid. Fragen gerne in den Gildenchat - wir helfen." })
end

local function seed(ctx)
    for _, f in ipairs({ seedChat, seedCombat, seedGoals, seedNotices }) do
        local ok, e = pcall(f, ctx)
        if not ok and ns.err then ns.err("Demo Gilde", e) end
    end
end

local function clean()
    if type(ns.db.gchat) == "table" then
        local out = {}
        for _, e in ipairs(ns.db.gchat) do if not e.demo then out[#out + 1] = e end end
        ns.db.gchat = out
    end
    if type(ns.db.linkHist) == "table" then
        local out = {}
        for _, h in ipairs(ns.db.linkHist) do if not h.demo then out[#out + 1] = h end end
        ns.db.linkHist = out
    end
    if ns.GuildChat and ns.GuildChat.ClearRenderCache then pcall(ns.GuildChat.ClearRenderCache) end
end

if ns.Demo and ns.Demo.AddSeed then ns.Demo.AddSeed("Gilde", seed, clean) end

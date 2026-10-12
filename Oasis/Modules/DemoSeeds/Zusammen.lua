-- Oasis: Demo-Daten fuer den Bereich "Zusammen spielen" (nur /oa demo)
-- Gruppensuche, Gemeinsam questen, Questitems, Spielerbuch, Anwerben & Realm, Dungeons.
-- Alles bleibt lokal: Store-Saetze ueber ctx.put (demo=true, "demo-"-ID), sonstige Tabellen mit demo=true.
local ADDON, ns = ...

-- Mitspieler ausserhalb der Gilde (Spielerbuch + Anwerben): Name, Klasse, Level, Anzahl, Notiz, Flags, Gilde, Gebiet, Rolle, Tage her
local ALLIES = {
    { "Ashkara-Venoxis", "SHAMAN", 30, 4, "Heilt sauber, kennt jede Abkuerzung in der Grotte", "fav", "", "Eschental", "h", 0.2 },
    { "Brummvak-Everlook", "WARRIOR", 36, 2, "", nil, "", "Tausend Nadeln", "t", 1.5 },
    { "Feylin-Lakeshire", "MAGE", 28, 3, "Portal nach Orgrimmar gegen Trinkgeld", "fav", "", "Brachland", "d", 0.6 },
    { "Gorrash-Everlook", "ROGUE", 33, 1, "Hat in Burg Schattenfang alles gerollt und ist gegangen", "ninja", "Blutige Klingen", "Silberwald", "d", 3 },
    { "Ilyanna-Venoxis", "PRIEST", 24, 2, "Neu auf dem Server, sucht Anschluss", nil, "", "Brachland", "h", 0.4 },
    { "Kroggan-Lakeshire", "HUNTER", 31, 1, "Pet auf aggressiv im Dungeon...", "bad", "", "Steinkrallengebirge", "d", 5 },
    { "Narjaka-Everlook", "DRUID", 38, 3, "Kann Tank und Heiler", nil, "", "Arathihochland", "t", 2 },
    { "Ruuzh-Venoxis", "WARLOCK", 26, 1, "", nil, "Die Schattenrufer", "Brachland", "d", 7 },
    { "Thalzun-Everlook", "PALADIN", 22, 2, "Ruhig, puenktlich, gute Laune", nil, "", "Silberwald", "h", 1 },
}
-- Begegnungen fuer die Realm-Statistik
local SEEN_GUILDS = { "Die Schattenrufer", "Blutige Klingen", "Donnerhuf", "Erben der Horde", "Kor'kron Wacht", "Sturmwut" }
local SEEN_ZONES = { "Brachland", "Orgrimmar", "Steinkrallengebirge", "Eschental", "Tausend Nadeln", "Silberwald", "Desolace", "Arathihochland" }
local SEEN_CLASSES = { "WARRIOR", "WARRIOR", "ROGUE", "HUNTER", "HUNTER", "MAGE", "MAGE", "PRIEST", "WARLOCK", "SHAMAN", "DRUID", "PALADIN" }
local SEEN_SYL = { "Gar", "Zul", "Mok", "Ra", "Thra", "Ka", "Vor", "Nek", "Ur", "Zen", "Bro", "Shi", "Tal", "Gro", "Ji" }
local SEEN_END = { "ash", "gor", "ka", "rim", "zul", "ja", "nok", "thar", "ra", "esh", "ug", "is" }
local SEEN_REALMS = { "Everlook", "Venoxis", "Lakeshire" }

-- Dungeon-Quests in den Questlogs der Demo-Leute (Profilfeld dq: "schluessel:ids;...")
local DQ = {
    [3] = "wailingcaverns:1486,962", [5] = "ragefire:5728,5761", [7] = "wailingcaverns:1486,1491",
    [13] = "wailingcaverns:914,1487", [15] = "ragefire:5728", [21] = "shadowfangkeep:92401;wailingcaverns:914",
    [19] = "ragefire:5761,5725", [2] = "shadowfangkeep:92421,92422", [12] = "shadowfangkeep:92401",
}

-- Questitems: weitere Mitspieler (gleiches Format wie QI.SeedDemo)
local QI = {
    { 13, "0{Kolkar-Halsband{887{3{10", "5086{Zhevrahufe{3{881{d}0{Raptorkopf{2{870{o", "887", "887{Suedmeerfreibeuter}881{Echeyakee" },
    { 19, "0{Ziegenfell{1062{2{6", "", "1062", "1062{Ziegenwaerter" },
    { 21, "0{Raptorkopf{870{2{4}0{Kodo-Horn{6548{1{3", "0{Federn der Harpyie{5{1062{o", "870", "870{Die vergessenen Teiche}6548{Rache an meinem Dorf" },
    { 7, "", "0{Kolkar-Halsband{4{887{d}0{Ziegenfell{3{1062{o", "", "" },
}

local function applyMembers(ctx)
    if not (ns.db and ns.db.members) then return end
    for i, s in pairs(DQ) do
        local p = ns.db.members[ctx.nm(i)]
        if p and p.demo then p.dq = s end
    end
end

local function seed(ctx)
    local put, nm, now = ctx.put, ctx.nm, ctx.now

    -- Gruppensuche: weitere offene Gruppen (Leute aus der Demo-Gilde)
    local LFG = {
        { 3, "Tiefschwarze Grotte", "Treffpunkt Zoram'gar, bringt Wasser mit", { { 3, "d" }, { 1, "t" } }, 27 },
        { 21, "Burg Schattenfang", "Arugal + alle Quests", { { 21, "t" }, { 23, "h" }, { 15, "d" }, { 8, "d" } }, 24 },
        { 14, "Uldaman", "Ganze Instanz, Archaedas am Ende", { { 14, "h" }, { 22, "d" } }, 45 },
        { 17, "Kral der Klingenhauer", "Charlga + Quest fuer Willix", { { 17, "t" }, { 18, "d" }, { 4, "d" } }, 33 },
    }
    for k, g in ipairs(LFG) do
        local m, have = {}, {}
        for _, s in ipairs(g[4]) do m[#m + 1] = nm(s[1]) .. ":" .. s[2] have[s[2]] = true end
        put("lfg", { id = "demo-zs-lfg" .. k, who = nm(g[1]), title = g[2], note = g[3], layout = "thddd", m = table.concat(m, ","),
            tank = not have.t, heal = not have.h, dps = true, size = 5, count = #g[4], auto = k % 2 == 1, open = true,
            lvl = g[5], class = ctx.people[g[1]][2], exp = now + (60 + k * 25) * 60 })
    end

    -- Questitems: mehr Mitspieler mit Beduerfnissen / Uebrigem
    for k, d in ipairs(QI) do
        local who = nm(d[1])
        put("qitems", { id = "demo-zs-qi" .. k, who = who, by = who, n = d[2], s = d[3], p = d[4], t = d[5] })
    end

    -- Spielerbuch: weitere Mitspieler (nur, wenn noch nicht vorhanden)
    ns.db.allies = ns.db.allies or {}
    for k, a in ipairs(ALLIES) do
        local full = ns.fullName(a[1])
        if not ns.db.allies[full] then
            ns.db.allies[full] = { class = a[2], lvl = a[3], count = a[4], note = a[5], fav = a[6] == "fav" or nil,
                bad = a[6] == "bad" or nil, ninja = a[6] == "ninja" or nil, guild = a[7], zone = a[8], seen = a[9],
                last = now - math.floor(a[10] * 86400), demo = true, demoOnline = (k == 1 or k == 3) or nil }
        end
    end
    -- Erfahrungen der Gilde (Store "rep"): Gilde bewertet Mitspieler
    local REP = {
        { 2, "Ashkara-Venoxis", "up", "Tolle Heilerin" }, { 10, "Ashkara-Venoxis", "up", "" },
        { 9, "Narjaka-Everlook", "up", "Hat uns in Uldaman getankt" }, { 6, "Gorrash-Everlook", "down", "Ninja", 1 },
        { 1, "Gorrash-Everlook", "down", "Bedarf auf alles" }, { 14, "Ilyanna-Venoxis", "up", "Wuerde gut zu uns passen" },
        { 4, "Feylin-Lakeshire", "up", "" }, { 12, "Kroggan-Lakeshire", "down", "Zieht staendig Gruppen" },
        { 16, "Morvash-Everlook", "up", "Lustiger Kerl aus dem Kloster" },
    }
    for k, r in ipairs(REP) do
        local t = ns.fullName(r[2])
        local a = ns.db.allies[t]
        put("rep", { id = "demo-zs-rep" .. k, who = nm(r[1]), by = nm(r[1]), target = t, v = r[3], note = r[4], ninja = r[5],
            class = a and a.class or "SHAMAN", lvl = a and a.lvl or 34 })
    end

    -- Anwerben: Vorschlaege der Gilde (Store "scout")
    local SC = {
        { 14, "Ilyanna-Venoxis", "Sucht eine Gilde, sehr freundlich" },
        { 9, "Narjaka-Everlook", "Flexibel als Tank/Heiler, aktiv abends" },
        { 2, "Thalzun-Everlook", "" },
    }
    for k, s in ipairs(SC) do
        local t = ns.fullName(s[2])
        local a = ns.db.allies[t] or {}
        put("scout", { id = "demo-zs-sc" .. k, target = t, by = nm(s[1]), class = a.class, lvl = a.lvl, cnt = a.count or 1,
            note = s[3] ~= "" and s[3] or nil, t = now - k * 30000 })
    end

    -- Realm-Statistik: Begegnungen (ns.db.seen)
    ns.db.seen = ns.db.seen or {}
    local seen = ns.db.seen
    for _, a in ipairs(ALLIES) do
        local full = ns.fullName(a[1])
        if not seen[full] then
            seen[full] = { c = a[2], l = a[3], g = a[7], z = a[8], fa = "H", t = now - math.floor(a[10] * 86400), f = now - 20 * 86400, demo = true }
        end
    end

    for i = 1, 90 do
        local name = SEEN_SYL[(i * 7) % #SEEN_SYL + 1] .. SEEN_END[(i * 5) % #SEEN_END + 1] .. (i > 60 and "a" or "")
        local full = ns.fullName(name .. "-" .. SEEN_REALMS[(i % #SEEN_REALMS) + 1])
        if not seen[full] then
            local lvl = (i % 9 == 0) and 60 or math.min(60, 8 + (i * 13) % 50)
            local g = (i % 3 == 0) and "" or SEEN_GUILDS[(i * 11) % #SEEN_GUILDS + 1]
            seen[full] = { c = SEEN_CLASSES[(i * 5) % #SEEN_CLASSES + 1], l = lvl, g = g, z = SEEN_ZONES[(i % #SEEN_ZONES) + 1],
                fa = (i % 17 == 0) and "A" or "H", t = now - (i * 26113) % (25 * 86400), f = now - 28 * 86400, demo = true }

        end
    end

    -- Ausruestung betrachtet (ns.db.gear) fuer zwei Mitspieler
    ns.db.gear = ns.db.gear or {}
    local function link(id, q) return "|c" .. q .. "|Hitem:" .. id .. "::::::::|h[" .. id .. "]|h|r" end
    local GEAR = {
        { "Narjaka-Everlook", 31, { [1] = link(10775, "ff0070dd"), [5] = link(6505, "ff0070dd"), [16] = link(6505, "ff0070dd"), [15] = link(6630, "ff1eff00") } },
        { "Ashkara-Venoxis", 27, { [16] = link(1482, "ff0070dd"), [5] = link(6340, "ff0070dd"), [10] = link(15405, "ff1eff00") } },
    }
    for _, g in ipairs(GEAR) do
        local full = ns.fullName(g[1])
        if not ns.db.gear[full] then
            local a = ns.db.allies[full] or {}
            ns.db.gear[full] = { t = now - 7200, i = g[3], il = g[2], c = a.class, l = a.lvl, demo = true }
        end
    end

    -- Dungeons: Beute der Gilde + gesuchte Beute aus Dungeons
    local LOOT = {
        { 3, 6905, "Reef Axe", "Tiefschwarze Grotte", 1.2 }, { 13, 6340, "Fenrus' Hide", "Burg Schattenfang", 2.5 },
        { 9, 9379, "Sang'thraze the Deflector", "Uldaman", 3 }, { 18, 10775, "Carapace of Tuten'kash", "Huegel der Klingenhauer", 4 },
        { 4, 7720, "Whitemane's Chapeau", "Scharlachrotes Kloster - Kathedrale", 1.8 }, { 21, 6630, "Seedcloud Buckler", "Die Hoehlen des Wehklagens", 0.5 },
    }
    for k, l in ipairs(LOOT) do
        put("loot", { id = "demo-zs-loot" .. k, item = "|cff0070dd|Hitem:" .. l[2] .. "::::::::|h[" .. l[3] .. "]|h|r", who = nm(l[1]),
            src = l[4], zone = l[4], mapID = 0, ts = now - math.floor(l[5] * 86400), quality = 3 })
    end
    local WANTS = { { 15, 6505, "Crescent Staff", "Fuer meinen Druiden" }, { 8, 1482, "Shadowfang", "" }, { 22, 6340, "Fenrus' Hide", "" } }
    for k, w in ipairs(WANTS) do
        put("wants", { id = "demo-zs-want" .. k, itemID = w[2], name = w[3], qty = 1, note = w[4], who = nm(w[1]), created = now - k * 4000 })
    end

    -- Dungeon-Quests der Gilde (Profilfelder)
    applyMembers(ctx)
end

local function clean()
    for _, key in ipairs({ "allies", "seen", "gear" }) do
        local t = ns.db and ns.db[key]
        if t then for k, v in pairs(t) do if type(v) == "table" and v.demo then t[k] = nil end end end
    end
    -- Profilfeld dq haengt an Demo-Profilen, die Demo.Remove ohnehin loescht
end

if ns.Demo and ns.Demo.AddSeed then
    ns.Demo.AddSeed("Zusammen", seed, clean)
    -- nach /reload baut Demo.lua die Demo-Profile neu auf: Dungeon-Quests danach wieder eintragen
    ns.Listen("LOGIN", function()
        if not (ns.Demo.IsActive and ns.Demo.IsActive()) then return end
        ns.After(3, function()
            pcall(applyMembers, { nm = function(i) local p = ns.Demo.People()[i] return p and p.name end })
        end)
    end)
end

-- Oasis: demo data for the "Me" area (only /oa demo, developer version)
-- Display state only: badge counters (Badges.Mine(true)) and a sample life story for "My Journey" (Life.DB).
-- None of it is saved or sent to the guild; the real data stays untouched.
-- Legacy has its own demo state (Legacy.demoMine), Oasis rank and profile read the real values.
local ADDON, ns = ...
local Demo = ns.Demo
if not Demo then return end

local DAY = 86400
local HOUR = 3600

-- even "random numbers": always the same values (screenshots look the same after every /reload)
local function rng(seed)
    local s = seed
    return function(lo, hi)
        s = (s * 1103515245 + 12345) % 2147483648
        return lo + (s % (hi - lo + 1))
    end
end

------------------------------------------------------------------------
-- Badges: one sample value per counter so that all tiers appear (locked, bronze, silver, gold)
------------------------------------------------------------------------
function Demo.MineBadgeStats(real)
    local out = {}
    local B = ns.Badges
    if not (B and B.LIST) then return out end
    for _, b in ipairs(B.LIST) do
        local sum = 0
        for i = 1, #b.id do sum = sum + b.id:byte(i) end
        local t = b.tiers
        local k = sum % 6      -- 0 = still locked (with progress), 1-2 bronze, 3-4 silver, 5 gold
        local v
        if k == 0 then v = math.floor(t[1] * (0.35 + (sum % 4) * 0.12))
        elseif k <= 2 then v = math.floor(t[1] * (1.1 + (sum % 7) / 10))
        elseif k <= 4 then v = math.floor(t[2] * (1.05 + (sum % 5) / 20))
        else v = math.floor(t[3] * 1.15) end
        if v > (out[b.stat] or 0) then out[b.stat] = v end   -- if badges share a counter, the highest wins
    end
    return out
end

------------------------------------------------------------------------
-- My Journey: sample life story (journey, records, dungeons, companions, deaths, gold, goals)
------------------------------------------------------------------------
local life
local ICON = "Interface\\Icons\\"
local function dayKey(t) return date("%Y%m%d", t) end

local function buildLife()
    local now = time()
    local r = rng(4711)
    local P = Demo.People and Demo.People() or {}
    local function who(i) return P[i] and P[i].name or ("Gefaehrte" .. i) end
    local l = {
        created = now - 63 * DAY, played = 61 * HOUR + 20 * 60,
        events = {}, rec = {}, runs = {}, goals = {}, stats = {}, mates = {}, deaths = {}, zones = {}, firsts = {}, ms = {},
        gold = { days = {}, hist = {}, big = {} },
    }

    -- journey: { hours ago, type, text, icon }  (newest first)
    local E = {
        { 2, "level", "Stufe 22 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 3, "boss", "Aku'mai in der Tiefschwarzen Grotte besiegt", ICON .. "Achievement_Boss_Ragnaros" },
        { 3.4, "loot", "Beute: Klinge der Tiefen", ICON .. "INV_Misc_Bag_10" },
        { 9, "dungeon", "Tiefschwarze Grotte abgeschlossen (24:12)", ICON .. "INV_Misc_Key_03" },
        { 14, "record", "Neuer Rekord - Meiste Kills in einer Stunde: 84", ICON .. "INV_Misc_Trophy_03" },
        { 27, "zone", "Neues Gebiet entdeckt: Eschental", ICON .. "INV_Misc_Map_01" },
        { 30, "goal", "Ziel erreicht: Kochkunst auf 100", ICON .. "Achievement_General" },
        { 33, "prof", "Kochkunst: Stufe 100 erreicht", ICON .. "Trade_BlackSmithing" },
        { 50, "death", "Gestorben: Kolkar-Pirscher (Stufe 19)", ICON .. "Spell_Shadow_DeathScream" },
        { 55, "level", "Stufe 21 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 78, "dungeon", "Burg Schattenfang abgeschlossen (31:40)", ICON .. "INV_Misc_Key_03" },
        { 78.5, "boss", "Baron Silberlein in Burg Schattenfang besiegt", ICON .. "Achievement_Boss_Ragnaros" },
        { 100, "gold", "Erstes Mal 25 Gold besessen", ICON .. "INV_Misc_Coin_02" },
        { 122, "zone", "Neues Gebiet entdeckt: Steinkrallengebirge", ICON .. "INV_Misc_Map_01" },
        { 146, "level", "Stufe 20 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 170, "boss", "Edwin VanCleef in den Todesminen besiegt", ICON .. "Achievement_Boss_Ragnaros" },
        { 170.5, "loot", "Beute: Rotes Einhandschwert (Selten)", ICON .. "INV_Misc_Bag_10" },
        { 200, "dungeon", "Die Höhlen des Wehklagens abgeschlossen (38:05)", ICON .. "INV_Misc_Key_03" },
        { 244, "level", "Stufe 18 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 300, "zone", "Neues Gebiet entdeckt: Brachland", ICON .. "INV_Misc_Map_01" },
        { 340, "record", "Neuer Rekord - Meiste Quests an einem Tag: 19", ICON .. "INV_Misc_Trophy_03" },
        { 420, "level", "Stufe 15 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 500, "dungeon", "Der Flammenschlund abgeschlossen (19:48)", ICON .. "INV_Misc_Key_03" },
        { 640, "zone", "Neues Gebiet entdeckt: Durotar", ICON .. "INV_Misc_Map_01" },
        { 800, "level", "Stufe 10 erreicht", ICON .. "Spell_Holy_SurgeOfLight" },
        { 1100, "prof", "Kochkunst gelernt", ICON .. "Trade_BlackSmithing" },
        { 1500, "start", "Deine Reise in Azeroth beginnt", ICON .. "Achievement_General" },
    }
    for _, e in ipairs(E) do
        l.events[#l.events + 1] = { t = now - math.floor(e[1] * HOUR), k = e[2], x = e[3], i = e[4] }
    end

    -- records (keys as in Life.REC); prev = previous value
    local function rec(key, v, hoursAgo, prev, x) l.rec[key] = { v = v, t = now - hoursAgo * HOUR, prev = prev, x = x } end
    rec("killsHour", 84, 14, 61)
    rec("killsSession", 412, 52, 360)
    rec("questsDay", 19, 340, 14)
    rec("bossesDay", 4, 78, 2)
    rec("goldDay", 480000, 100, 310000)
    rec("bigLoot", 152000, 170, 90000)
    rec("fastLevel", 5400, 55, 7100)
    rec("session", 15600, 150, 11000)
    rec("noDeath", 270000, 5, 171000)
    rec("zonesDay", 3, 300, 2)
    rec("quickDeath", 95, 400, 210)
    l.rec["run:blackfathomdeeps"] = { v = 1452, t = now - 9 * HOUR, prev = 1710, x = { name = "Tiefschwarze Grotte", label = "Tiefschwarze Grotte - Bestzeit" } }
    l.rec["run:wailingcaverns"] = { v = 2285, t = now - 200 * HOUR, prev = 2610, x = { name = "Die Höhlen des Wehklagens", label = "Die Höhlen des Wehklagens - Bestzeit" } }
    l.rec["run:ragefire"] = { v = 1188, t = now - 500 * HOUR, x = { name = "Der Flammenschlund", label = "Der Flammenschlund - Bestzeit" } }

    -- Dungeon runs
    local D = {
        { "ragefire", "Der Flammenschlund", 500, 1188, 3, 1 },
        { "ragefire", "Der Flammenschlund", 650, 1320, 3, 0 },
        { "wailingcaverns", "Die Höhlen des Wehklagens", 200, 2285, 7, 2 },
        { "wailingcaverns", "Die Höhlen des Wehklagens", 340, 2610, 7, 3 },
        { "wailingcaverns", "Die Höhlen des Wehklagens", 430, 2450, 6, 1 },
        { "deadmines", "Die Todesminen", 170, 1980, 5, 1 },
        { "deadmines", "Die Todesminen", 260, 2240, 5, 2 },
        { "shadowfangkeep", "Burg Schattenfang", 78, 1900, 6, 0 },
        { "shadowfangkeep", "Burg Schattenfang", 120, 2105, 6, 1 },
        { "blackfathomdeeps", "Tiefschwarze Grotte", 9, 1452, 6, 0 },
        { "blackfathomdeeps", "Tiefschwarze Grotte", 36, 1688, 5, 1 },
        { "blackfathomdeeps", "Tiefschwarze Grotte", 88, 1790, 6, 1 },
    }
    for i, d in ipairs(D) do
        local party = {}
        party[who((i * 3) % 24 + 1)] = true
        party[who((i * 5) % 24 + 1)] = true
        party[who((i * 7) % 24 + 1)] = true
        local loot = {}
        for _ = 1, r(1, 3) do loot[#loot + 1] = { q = r(2, 3) } end
        local start = now - d[3] * HOUR
        l.runs[#l.runs + 1] = { key = d[1], name = d[2], start = start, t0 = start, dur = d[4], done = true,
            bosses = d[5], deaths = d[6], loot = loot, party = party }
    end

    -- Companions (group memory)
    local classes = { "WARRIOR", "PRIEST", "MAGE", "HUNTER", "SHAMAN", "ROGUE", "DRUID", "WARLOCK" }
    for i = 1, 14 do
        local nm = who(i + 1)
        l.mates[nm] = { runs = r(1, 8), last = now - r(2, 600) * HOUR, lastName = D[r(1, #D)][2], class = classes[(i % #classes) + 1],
            level = r(17, 34), guild = (i % 4 ~= 0) and "Sandwölfe" or nil,
            note = (i == 2 and "Immer pünktlich, heilt super") or (i == 5 and "Schlüsselmeister") or (i == 9 and "Bringt Kekse mit") or nil }
    end

    -- Deaths
    local DT = {
        { 50, "Kolkar-Pirscher", 19, false, nil, "Brachland", 28, 1 },
        { 160, "Wildtatzenjäger", 21, false, nil, "Steinkrallengebirge", 34, 1 },
        { 175, "Defias-Zauberer", 18, true, "Die Todesminen", nil, 41, 4 },
        { 210, "Hauptmann Grünhaut", 20, true, "Die Höhlen des Wehklagens", nil, 55, 5 },
        { 330, "Sturz", 0, false, nil, "Durotar", 0, 1 },
        { 420, "Harpyien-Windhexe", 17, false, nil, "Brachland", 22, 1 },
        { 560, "Skorpid-Schrecken", 14, false, nil, "Durotar", 18, 1 },
        { 700, "Ertrinken", 0, false, nil, "Brachland", 0, 1 },
        { 900, "Kolkar-Pirscher", 12, false, nil, "Brachland", 31, 1 },
    }
    for _, d in ipairs(DT) do
        l.deaths[#l.deaths + 1] = { t = now - d[1] * HOUR, killer = d[2], klvl = d[3], elite = d[4], inst = d[5], zone = d[6],
            dur = d[7], group = d[8], pot = (d[1] % 3 == 0) or nil, tips = {} }
    end

    -- Gold diary: 30 days, income/expenses by category, wealth history
    local balance, goldIn, goldOut = 40000, 0, 0
    for i = 29, 0, -1 do
        local t = now - i * DAY
        local inc = { quest = r(2000, 9000), loot = r(1500, 12000), vendor = r(800, 5000) }
        if i % 4 == 0 then inc.ah = r(6000, 24000) end
        if i % 9 == 0 then inc.mail = r(3000, 8000) end
        local out = { vendor = r(500, 4000), repair = r(600, 3000) }
        if i % 6 == 0 then out.train = r(4000, 12000) end
        if i % 8 == 0 then out.taxi = r(900, 2500) end
        if i % 5 == 0 then out.ah = r(2500, 9000) end
        local tin, tout = 0, 0
        for _, v in pairs(inc) do tin = tin + v end
        for _, v in pairs(out) do tout = tout + v end
        l.gold.days[dayKey(t)] = { inc = inc, out = out }
        balance = math.max(1000, balance + tin - tout)
        l.gold.hist[dayKey(t)] = balance
        goldIn, goldOut = goldIn + tin, goldOut + tout
    end
    local BIG = { { "train", "Orgrimmar", 98000, 6 }, { "ah", "Orgrimmar", 61500, 3 }, { "train", "Orgrimmar", 55000, 11 },
        { "vendor", "Kreuzungen", 42000, 5 }, { "taxi", "Orgrimmar", 18400, 8 }, { "repair", "Burg Schattenfang", 12700, 3 } }
    for _, b in ipairs(BIG) do l.gold.big[#l.gold.big + 1] = { c = b[1], z = b[2], v = b[3], t = now - b[4] * DAY } end

    -- Goals
    local function goal(g) g.id = "demo-g" .. (#l.goals + 1) l.goals[#l.goals + 1] = g end
    goal({ kind = "level", arg = 25, text = "Stufe 25 erreichen", t = now - 20 * DAY })
    goal({ kind = "gold", arg = 100, text = "100 Gold für das erste Reittier sparen", t = now - 30 * DAY })
    goal({ kind = "prof", prof = "Kochkunst", arg = 150, text = "Kochkunst auf 150", t = now - 12 * DAY })
    goal({ kind = "run", dkey = "blackfathomdeeps", arg = 5, text = "5x Tiefschwarze Grotte", t = now - 14 * DAY })
    goal({ kind = "free", text = "Die Sandwölfe beim Raid-Abend treffen", t = now - 8 * DAY })
    goal({ kind = "free", done = true, doneT = now - 5 * DAY, text = "Erste Gruppe für die Höhlen des Wehklagens finden", t = now - 26 * DAY })
    goal({ kind = "free", done = true, doneT = now - 12 * DAY, text = "Ersten Boss in einem Dungeon besiegen", t = now - 40 * DAY })

    -- counters, visited zones, "firsts", milestones
    l.stats = { kills = 2840, deaths = #l.deaths, quests = 186, bosses = 23, goldIn = goldIn, goldOut = goldOut, noDeathAcc = 270000, online = l.played }
    for i, z in ipairs({ "Durotar", "Brachland", "Steinkrallengebirge", "Eschental", "Orgrimmar", "Mulgore", "Silberwald", "Tirisfal", "Sümpfe des Elends", "Kreuzungen", "Splittertal", "Düstermarschen", "Tausend Nadeln", "Desolace" }) do
        l.zones[z] = now - (i * 60) * HOUR
    end
    for i, b in ipairs({ "Edwin VanCleef", "Baron Silberlein", "Aku'mai", "Hauptmann Grünhaut", "Lady Anacondra", "Lord Pythas", "Kresh", "Gelihast", "Mutanus der Verschlinger", "Arugal" }) do
        l.firsts["boss:" .. b] = now - (i * 70) * HOUR
    end
    l.ms["lvl:10"], l.ms["lvl:15"], l.ms["lvl:20"] = now - 800 * HOUR, now - 420 * HOUR, now - 146 * HOUR
    return l
end

-- called from Life.DB() in demo mode
function Demo.MineLife()
    if not life then
        local ok, res = pcall(buildLife)
        if ok then life = res else ns.err("Demo Mein Weg", res) return nil end
    end
    return life
end

-- demo off (/oa demo aus): discard state, rebuilt on next start
Demo.AddSeed("Ich", function() life = nil end, function() life = nil end)

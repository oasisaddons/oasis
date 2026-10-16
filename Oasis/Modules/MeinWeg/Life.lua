-- Oasis: Mein Weg - "dieses Addon erinnert sich an dein ganzes Leben in Azeroth"
--  Reise      Zeitleiste der wichtigsten Momente (Level, erste Bosse, neue Gebiete, besondere Beute, Meilensteine)
--  Rekorde    persoenliche Bestleistungen mit "NEUER REKORD!"-Hinweis
--  Dungeons   Dungeon-Laufbahn: Laeufe, Bestzeit, Schnitt, Tode, Bosse, Beute, Mitspieler
--  Mitspieler Gruppen-Gedaechtnis: mit wem du unterwegs warst (+ private Notiz)
--  Tode       Tod-Analyse: vermutlicher Toeter, Kampfdauer, Stufenunterschied, ungenutzter Trank/Gesundheitsstein
--  Gold       Gold-Tagebuch: Einnahmen/Ausgaben nach Kategorie, Verlauf, groesste Ausgaben
--  Ziele      eigene Ziele (Level, Gold, Beruf, Item, Dungeon, frei) mit automatischem Abhaken
--  Was tun?   Vorschlaege nach Level, Questlog, Berufen, Zeitbudget
--  Jahrbuch   Zusammenfassung des Charakters, teilbar im Gildenchat
-- Alles nur fuer den eigenen Charakter (ns.char.life), nichts wird gesendet.
-- Kampfwerte (Crits, Schaden, Leben) sind in Forever im Kampf gesperrt -> keine Crit-Rekorde, Analyse ohne Schadenszahlen.
local ADDON, ns = ...
ns.ModuleFile("Oasis_MeinWeg", function()   -- Modul Mein Weg (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local Life = {}
ns.Life = Life

local DAY = 86400
local function now() return time() end
local function dayKey(t) return date("%Y%m%d", t or now()) end
local function fmtDate(t) return date("%d.%m.%Y", t) end
local function fmtDur(s)
    s = math.floor(s or 0)
    if s >= 3600 then return ("%d:%02d:%02d"):format(s / 3600, (s % 3600) / 60, s % 60) end
    return ("%d:%02d"):format(s / 60, s % 60)
end
local function fmtLong(s)
    s = math.floor(s or 0)
    local d, h, m = math.floor(s / DAY), math.floor((s % DAY) / 3600), math.floor((s % 3600) / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end
local function money(c)
    c = math.floor(c or 0)
    local neg = c < 0
    if neg then c = -c end
    local s = (GetCoinTextureString and GetCoinTextureString(c)) or (("%dg %ds %dc"):format(c / 10000, (c % 10000) / 100, c % 100))
    return neg and ("-" .. s) or s
end
local function plain(c)
    c = math.floor(math.abs(c or 0))
    local g, s = math.floor(c / 10000), math.floor((c % 10000) / 100)
    if g > 0 then return ("%dg %ds"):format(g, s) end
    return ("%ds %dc"):format(s, c % 100)
end
local function S() return ns.db and ns.db.settings or {} end

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
local function db()
    -- 0.5.704: Demo-Modus - Beispiel-Lebenslauf (nur im Speicher, nie gespeichert oder gesendet)
    if ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() and ns.Demo.MineLife then
        local d = ns.Demo.MineLife()
        if d then return d end
    end
    local c = ns.char
    if not c then return nil end
    local l = c.life
    if not l then
        l = { created = now(), events = {}, rec = {}, runs = {}, gold = { days = {}, hist = {}, big = {} },
            goals = {}, stats = {}, mates = {}, deaths = {}, zones = {}, firsts = {}, ms = {} }
        c.life = l
    end
    for _, k in ipairs({ "events", "rec", "runs", "goals", "stats", "mates", "deaths", "zones", "firsts", "ms" }) do l[k] = l[k] or {} end
    l.gold = l.gold or { days = {}, hist = {}, big = {} }
    return l
end
Life.DB = db
local function stat(k, n)
    local l = db()
    if not l then return 0 end
    l.stats[k] = (l.stats[k] or 0) + (n or 1)
    return l.stats[k]
end
-- "Mein Weg" lebt jetzt im Profil (Life.host): dort mit auffrischen
local function refresh()
    ns.RefreshPage("life")
    if Life.host and Life.host:IsVisible() then
        local d = ns.PageDef("life")
        if d and d.refresh then pcall(d.refresh, Life.host) end
    end
end
-- Ansicht im Profil oeffnen
function Life.Open(view)
    Life.view = view or Life.view or "journey"
    ns.profileTab = Life.view
    ns.ShowPage("insta")
    ns.RefreshPage("insta")
end

-- Reise: Eintrag in die Zeitleiste
local KIND_COL = { level = "accent", boss = "red", dungeon = "amber", zone = "blue", loot = "amber", record = "mint",
    death = "muted", gold = "amber", prof = "mint", goal = "mint", start = "text" }
function Life.Event(kind, text, icon, link)
    local l = db()
    if not l then return end
    table.insert(l.events, 1, { t = now(), k = kind, x = text, i = icon, link = link })
    while #l.events > 1500 do table.remove(l.events) end
    refresh()
end

------------------------------------------------------------------------
-- Rekorde
------------------------------------------------------------------------
-- key -> { label, better = "high"|"low", fmt, icon }
local REC = {
    killsHour = { "Meiste Kills in einer Stunde", "high", function(v) return tostring(v) end, "Interface\\Icons\\Ability_Warrior_Rampage" },
    goldDay = { "Meistes Gold an einem Tag", "high", plain, "Interface\\Icons\\INV_Misc_Coin_02" },
    bigLoot = { "Groesster Goldfund", "high", plain, "Interface\\Icons\\INV_Misc_Bag_10" },
    questsDay = { "Meiste Quests an einem Tag", "high", function(v) return tostring(v) end, "Interface\\Icons\\INV_Misc_Note_01" },
    bossesDay = { "Meiste Bosse an einem Tag", "high", function(v) return tostring(v) end, "Interface\\Icons\\Achievement_Boss_Ragnaros" },
    fastLevel = { "Schnellstes Level", "low", fmtLong, "Interface\\Icons\\Spell_Holy_SurgeOfLight" },
    session = { "Laengste Spielsitzung", "high", fmtLong, "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    noDeath = { "Laengste Zeit ohne Tod", "high", fmtLong, "Interface\\Icons\\Spell_Holy_DivineIntervention" },
    killsSession = { "Meiste Kills in einer Sitzung", "high", function(v) return tostring(v) end, "Interface\\Icons\\Ability_DualWield" },
    quickDeath = { "Schnellster Tod nach dem Einloggen", "low", fmtDur, "Interface\\Icons\\Spell_Shadow_DeathScream" },
    zonesDay = { "Meiste neue Gebiete an einem Tag", "high", function(v) return tostring(v) end, "Interface\\Icons\\INV_Misc_Map_01" },
}
Life.REC = REC
local REC_ORDER = { "killsHour", "killsSession", "questsDay", "bossesDay", "goldDay", "bigLoot", "fastLevel", "session", "noDeath", "zonesDay", "quickDeath" }

-- Wert melden; gibt true zurueck, wenn neuer Rekord
-- quiet = nur speichern (z.B. laufende Zaehler, Hinweis kommt spaeter einmal)
function Life.Record(key, value, extra, quiet)
    local l = db()
    local def = REC[key] or (key:match("^run:") and { "", "low" })
    if not l or not def or not value then return false end
    local r = l.rec[key]
    local better = not r or (def[2] == "high" and value > r.v) or (def[2] == "low" and value < r.v)
    if not better then return false end
    local had = r ~= nil
    l.rec[key] = { v = value, t = now(), x = extra, prev = r and r.v }
    if not quiet and had and S().lifeRecToast ~= false then
        local label = extra and extra.label or L[def[1]]
        local shown = def[3] and def[3](value) or fmtDur(value)
        if ns.Sound and ns.Sound.Next then ns.Sound.Next("record") end
        K.Toast(L["NEUER PERSOENLICHER REKORD!"], label .. ": |cffffd100" .. shown .. "|r", C.amber,
            function() Life.Open("records") end)
        Life.Event("record", (L["Neuer Rekord - %s: %s"]):format(label, shown), def[4] or "Interface\\Icons\\INV_Misc_Trophy_03")
    end
    refresh()
    return true
end
-- Tageszaehler (Rekord "an einem Tag")
local function dayCount(key, recKey, n)
    local l = db()
    if not l then return end
    local dk = dayKey()
    l.stats.days = l.stats.days or {}
    local d = l.stats.days[dk] or {}
    l.stats.days[dk] = d
    d[key] = (d[key] or 0) + (n or 1)
    if recKey then Life.Record(recKey, d[key], nil, true) end
    return d[key]
end
-- "an einem Tag"-Rekorde melden wir erst beim Tageswechsel/Logout bzw. einmal, sobald der alte Wert ueberboten ist
local announced = {}
local function dayAnnounce(recKey)
    local l = db()
    local r = l and l.rec[recKey]
    if not r or not r.prev or announced[recKey] then return end
    if dayKey(r.t) ~= dayKey() then return end
    announced[recKey] = true
    local def = REC[recKey]
    if S().lifeRecToast ~= false then
        if ns.Sound and ns.Sound.Next then ns.Sound.Next("record") end
        K.Toast(L["NEUER PERSOENLICHER REKORD!"], L[def[1]] .. ": |cffffd100" .. def[3](r.v) .. "|r", C.amber,
            function() Life.Open("records") end)
    end
    Life.Event("record", (L["Neuer Rekord - %s: %s"]):format(L[def[1]], def[3](r.v)), def[4])
end
local function dayRecord(key, recKey, n)
    local v = dayCount(key, recKey, n)
    if recKey then dayAnnounce(recKey) end
    return v
end

------------------------------------------------------------------------
-- Sitzung, Spielzeit, Level-Tempo (Online-Minuten, nur solange Oasis laeuft)
------------------------------------------------------------------------
local session = { start = nil, kills = 0, killTimes = {} }
local noDeathSince
local function tick()
    local l = db()
    if not l or not session.start then return end
    l.stats.online = (l.stats.online or 0) + 60
    l.lvlSecs = (l.lvlSecs or 0) + 60
    Life.Record("session", now() - session.start, nil, true)
    if noDeathSince then Life.Record("noDeath", (l.stats.noDeathAcc or 0), nil, true) l.stats.noDeathAcc = (l.stats.noDeathAcc or 0) + 60 end
end

------------------------------------------------------------------------
-- Meilensteine
------------------------------------------------------------------------
local function milestone(key, steps, value, text, icon, kind)
    local l = db()
    if not l then return end
    for _, s in ipairs(steps) do
        local id = key .. ":" .. s
        if value >= s and not l.ms[id] then
            l.ms[id] = now()
            Life.Event(kind or "start", (L[text]):format(s), icon)
        end
    end
end

------------------------------------------------------------------------
-- Gold-Tagebuch
------------------------------------------------------------------------
local CATS = {
    { key = "quest", text = "Quests", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "loot", text = "Beute", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    { key = "vendor", text = "Haendler", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { key = "repair", text = "Reparaturen", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "train", text = "Training", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "taxi", text = "Flugmeister", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
    { key = "ah", text = "Auktionshaus", icon = "Interface\\Icons\\INV_Misc_Coin_05" },
    { key = "mail", text = "Post", icon = "Interface\\Icons\\INV_Letter_15" },
    { key = "trade", text = "Handel", icon = "Interface\\Icons\\INV_Misc_Coin_17" },
    { key = "gbank", text = "Gildenbank", icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth" },
    { key = "other", text = "Sonstiges", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
local CAT = {}
for _, c in ipairs(CATS) do CAT[c.key] = c end
Life.GOLD_CATS = CATS

local ctx = {}          -- offene Fenster: merchant, train, taxi, ah, mail, trade, gbank
local lastQuest, lastLoot, repairPending = 0, 0, nil
local lastMoney
local function moneyCategory(delta)
    local t = GetTime()
    if repairPending and delta < 0 and t - repairPending < 3 then repairPending = nil return "repair" end
    if delta > 0 and t - lastQuest < 3 then return "quest" end
    if delta > 0 and t - lastLoot < 3 then return "loot" end
    if ctx.ah then return "ah" end
    if ctx.mail then return "mail" end
    if ctx.trade then return "trade" end
    if ctx.gbank then return "gbank" end
    if ctx.taxi then return "taxi" end
    if ctx.train then return "train" end
    if ctx.merchant then return "vendor" end
    if delta > 0 then return "loot" end
    return "other"
end
local function onMoney()
    local m = GetMoney and GetMoney()
    if not m then return end
    local l = db()
    if not l then return end
    if not lastMoney then lastMoney = m return end
    local delta = m - lastMoney
    lastMoney = m
    if delta == 0 then return end
    local cat = moneyCategory(delta)
    local g = l.gold
    local dk = dayKey()
    local d = g.days[dk] or { inc = {}, out = {} }
    g.days[dk] = d
    if delta > 0 then
        d.inc[cat] = (d.inc[cat] or 0) + delta
        stat("goldIn", delta)
        local net = 0
        for _, v in pairs(d.inc) do net = net + v end
        Life.Record("goldDay", net, nil, true)
        dayAnnounce("goldDay")
        if cat == "loot" then Life.Record("bigLoot", delta) end
        for _, st in ipairs({ 100000, 1000000, 10000000, 100000000 }) do
            local id = "earned:" .. st
            if (l.stats.goldIn or 0) >= st and not l.ms[id] then
                l.ms[id] = now()
                Life.Event("gold", (L["Insgesamt %s verdient"]):format(plain(st)), "Interface\\Icons\\INV_Misc_Coin_02")
            end
        end
    else
        d.out[cat] = (d.out[cat] or 0) - delta
        stat("goldOut", -delta)
        if -delta >= 10000 then
            table.insert(g.big, { t = now(), v = -delta, c = cat, z = ns.safe(GetRealZoneText()) or "" })
            table.sort(g.big, function(a, b) return a.v > b.v end)
            while #g.big > 30 do table.remove(g.big) end
        end
    end
    g.hist[dk] = m
    -- Besitz-Meilensteine (1g, 10g, 100g, 1000g)
    for _, s in ipairs({ 10000, 100000, 1000000, 10000000 }) do
        local id = "own:" .. s
        if m >= s and not l.ms[id] then
            l.ms[id] = now()
            Life.Event("gold", (L["Zum ersten Mal %s besessen"]):format(plain(s)), "Interface\\Icons\\INV_Misc_Coin_02")
        end
    end
    Life.CheckGoals()
    refresh()
end

------------------------------------------------------------------------
-- Dungeon-Laufbahn
------------------------------------------------------------------------
local function dungeonInfo()
    local inInst, typ = IsInInstance()
    if not inInst or (typ ~= "party" and typ ~= "raid") then return nil end
    local name, _, _, _, _, _, _, instID = GetInstanceInfo()
    name = ns.safe(name)
    if not name then return nil end
    local key, d = "i" .. tostring(instID or name), nil
    if ns.Dungeons and ns.Dungeons.Match then
        local ok, m = pcall(ns.Dungeons.Match, name)
        if ok and m then d = m key = m.key end
    end
    return { key = key, name = name, instID = instID, raid = typ == "raid", bossTotal = d and d.bosses and #d.bosses or nil }
end
local function addMate(unit, run)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    local n, realm = ns.UnitName(unit)
    n = ns.safe(n)
    if not n or n == "" then return end
    realm = ns.safe(realm)
    local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
    local _, cls = UnitClass(unit)
    run.party = run.party or {}
    if run.party[full] then return end
    run.party[full] = cls or true
    local l = db()
    local m = l.mates[full] or { first = now(), runs = 0 }
    l.mates[full] = m
    m.class = cls or m.class
    m.level = ns.safe(UnitLevel(unit)) or m.level
    m.runs = (m.runs or 0) + 1
    m.last = now()
    m.lastName = run.name
    m.guild = ns.safe(GetGuildInfo(unit)) or m.guild
end
local function scanParty(run)
    if not run then return end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return end
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and n or 4 do addMate(raid and ("raid" .. i) or ("party" .. i), run) end
end
-- Lauf abschliessen und Statistiken bilden
local function finishRun(l)
    local r = l.cur
    if not r then return end
    l.cur = nil
    if (r.bosses or 0) == 0 and (now() - r.start) < 120 then return end   -- nur kurz reingeschaut
    r.done = r.bossTotal and r.bosses >= r.bossTotal or nil
    r.dur = r.lastBoss and (r.lastBoss - r.start) or nil
    table.insert(l.runs, 1, r)
    while #l.runs > 600 do table.remove(l.runs) end
    stat("runs", 1)
    -- Erster Abschluss / Bestzeit nur fuer vollstaendige Laeufe
    if r.done and r.dur then
        local first = not l.firsts["clear:" .. r.key]
        if first then
            l.firsts["clear:" .. r.key] = now()
            Life.Event("dungeon", (L["%s zum ersten Mal komplett abgeschlossen (%s)"]):format(r.name, fmtDur(r.dur)), "Interface\\Icons\\INV_Misc_Key_03")
        end
        Life.Record("run:" .. r.key, r.dur, { label = (L["Schnellster Lauf: %s"]):format(r.name), name = r.name })
    end
    local runsHere = 0
    for _, x in ipairs(l.runs) do if x.key == r.key then runsHere = runsHere + 1 end end
    milestone("runs-" .. r.key, { 10, 25, 50, 100 }, runsHere, r.name .. ": " .. L["%d Laeufe"], "Interface\\Icons\\INV_Misc_Key_03", "dungeon")
end
local function checkInstance()
    local l = db()
    if not l then return end
    local info = dungeonInfo()
    local r = l.cur
    if r and info and r.key == info.key and r.leftAt and now() - r.leftAt < 900 then
        r.leftAt = nil  -- zurueck (Geist, Nachschub)
        return
    end
    if r and (not info or r.key ~= info.key) then
        if info or (r.leftAt and now() - r.leftAt > 900) then finishRun(l) r = nil
        elseif not r.leftAt then r.leftAt = now() end
    end
    if info and not l.cur then
        l.cur = { key = info.key, name = info.name, start = now(), bosses = 0, bossList = {}, deaths = 0, loot = {},
            bossTotal = info.bossTotal, raid = info.raid, lvl = UnitLevel("player") }
        scanParty(l.cur)
    end
    refresh()
end

------------------------------------------------------------------------
-- Tod-Analyse
------------------------------------------------------------------------
local fight = { start = nil }
local lastFoe
local HEAL_POTS = { 118, 858, 929, 1710, 3928, 13446, 4596, 17348, 17349, 18839 }
local HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }
local function haveAny(list)
    for _, id in ipairs(list) do
        local ok, n = pcall(C_Item.GetItemCount, id)
        if ok and (ns.safe(n) or 0) > 0 then return id end
    end
end
local function rememberFoe()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        local n = ns.safe(ns.UnitName("target"))
        if n then
            lastFoe = { name = n, t = GetTime(), lvl = ns.safe(UnitLevel("target")), player = UnitIsPlayer("target") or nil,
                elite = (ns.safe(UnitClassification("target")) or ""):find("elite") and true or nil }
        end
    end
end
local function onDeath()
    local l = db()
    if not l then return end
    local inst = dungeonInfo()
    local me = UnitLevel("player") or 0
    local foe = lastFoe and (GetTime() - lastFoe.t) < 30 and lastFoe or nil
    local e = {
        t = now(), zone = ns.safe(GetRealZoneText()) or "", lvl = me,
        killer = foe and foe.name or nil, klvl = foe and foe.lvl or nil, elite = foe and foe.elite or nil, pvp = foe and foe.player or nil,
        dur = fight.start and math.floor(GetTime() - fight.start + 0.5) or nil,
        pot = haveAny(HEAL_POTS), hs = haveAny(HEALTHSTONES),
        inst = inst and inst.name or nil,
        group = (GetNumGroupMembers and GetNumGroupMembers() or 0),
        falling = (IsFalling and IsFalling()) or nil,
        swim = (IsSwimming and IsSwimming()) or nil,
    }
    -- Erklaerungen
    local tips = {}
    if e.pot then tips[#tips + 1] = "pot" end
    if e.hs then tips[#tips + 1] = "hs" end
    if e.klvl and e.klvl > 0 and e.klvl - me >= 3 then tips[#tips + 1] = "lvl" end
    if e.klvl == -1 then tips[#tips + 1] = "skull" end
    if e.elite and e.group <= 1 then tips[#tips + 1] = "elite" end
    if e.dur and e.dur <= 5 and not e.pvp then tips[#tips + 1] = "fast" end
    if not e.killer and not ns.inCombat() then tips[#tips + 1] = e.falling and "fall" or (e.swim and "drown" or "env") end
    e.tips = tips
    table.insert(l.deaths, 1, e)
    while #l.deaths > 300 do table.remove(l.deaths) end
    local total = stat("deaths", 1)
    if l.cur then l.cur.deaths = (l.cur.deaths or 0) + 1 end
    if session.start and (now() - session.start) < 3600 then Life.Record("quickDeath", now() - session.start) end
    if (l.stats.noDeathAcc or 0) > 0 then Life.Record("noDeath", l.stats.noDeathAcc) end
    l.stats.noDeathAcc = 0
    milestone("deaths", { 1, 10, 50, 100, 250, 500, 1000 }, total, "%d. Tod", "Interface\\Icons\\Spell_Shadow_DeathScream", "death")
    if S().lifeDeathToast ~= false then
        local why = Life.TipText(e.tips[1])
        K.Toast(L["Tod-Analyse"], (e.killer or L["Unbekannt"]) .. (why and (" - " .. why) or ""), C.red,
            function() Life.Open("deaths") end, "death")
    end
    refresh()
end
local TIPS = {
    pot = "Heiltrank war in der Tasche",
    hs = "Gesundheitsstein war in der Tasche",
    lvl = "Gegner war 3+ Stufen hoeher",
    skull = "Gegner war viel zu hoch (Totenkopf)",
    elite = "Elite-Gegner allein angegriffen",
    fast = "Sehr kurzer Kampf - mehrere Gegner oder Ueberraschung?",
    fall = "Fallschaden",
    drown = "Ertrunken / Erschoepfung",
    env = "Kein Gegner im Ziel - Umgebung oder Gegner ohne Ziel",
}
function Life.TipText(k) return k and TIPS[k] and L[TIPS[k]] or nil end

------------------------------------------------------------------------
-- Ziele
------------------------------------------------------------------------
-- kind: level (arg Stufe), gold (arg Gold), prof (arg Stufe, prof = Name), item (arg Anzahl, item = ID), run (arg Anzahl, dkey), free
local function profRank(name)
    if not (ns.Radar and ns.Radar.myProfessions) then return 0 end
    for _, p in ipairs(ns.Radar.myProfessions()) do if p.name == name then return p.rank or 0 end end
    return 0
end
function Life.GoalProgress(g)
    local l = db()
    if g.kind == "level" then return UnitLevel("player") or 0, g.arg end
    if g.kind == "gold" then return math.floor((GetMoney() or 0) / 10000), g.arg end
    if g.kind == "prof" then return profRank(g.prof), g.arg end
    if g.kind == "item" and g.item then
        local ok, n = pcall(C_Item.GetItemCount, g.item, true)
        return ok and (ns.safe(n) or 0) or 0, g.arg or 1
    end
    if g.kind == "run" then
        local n = 0
        for _, r in ipairs(l and l.runs or {}) do if r.key == g.dkey and (r.t0 or r.start) >= (g.t or 0) then n = n + 1 end end
        return n, g.arg or 1
    end
    return g.done and 1 or 0, 1
end
function Life.CheckGoals()
    local l = db()
    if not l then return end
    for _, g in ipairs(l.goals) do
        if not g.done and g.kind ~= "free" then
            local cur, max = Life.GoalProgress(g)
            if cur and max and cur >= max then Life.CompleteGoal(g) end
        end
    end
end
function Life.CompleteGoal(g, undo)
    if undo then g.done, g.doneT = nil, nil refresh() return end
    if g.done then return end
    g.done, g.doneT = true, now()
    Life.Event("goal", (L["Ziel erreicht: %s"]):format(g.text), "Interface\\Icons\\Achievement_General")
    if ns.Sound and ns.Sound.Next then ns.Sound.Next("record") end
    K.Toast(L["Ziel erreicht!"], g.text, C.mint, function() Life.Open("goals") end)
    refresh()
end
function Life.AddGoal(g)
    local l = db()
    if not l then return end
    g.id = ns.newId("goal")
    g.t = now()
    table.insert(l.goals, g)
    Life.CheckGoals()
    refresh()
end

------------------------------------------------------------------------
-- Was tun? (Vorschlaege)
------------------------------------------------------------------------
-- Rueckgabe: Liste { icon, title, sub, min = Minuten, score, page = Oasis-Seite }
function Life.Suggestions(budget)
    local out = {}
    local lvl = UnitLevel("player") or 1
    -- Questlog nach Gebiet
    local zones, ready = {}, 0
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    local zone
    for i = 1, okN and n or 0 do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" then
            if info.isHeader then zone = info.title
            elseif info.questID and not info.isHidden then
                local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                if done then ready = ready + 1
                elseif zone and not (ns.Dungeons and ns.Dungeons.KeyByZone(zone)) then
                    local ql = info.level or lvl
                    if ql <= lvl + 3 then
                        local z = zones[zone] or { n = 0, green = 0 }
                        zones[zone] = z
                        z.n = z.n + 1
                    end
                end
            end
        end
    end
    if ready > 0 then
        out[#out + 1] = { icon = "Interface\\Icons\\INV_Misc_Note_02", title = L["Quests abgeben"],
            sub = (L["%d Quests sind fertig - schnelle Erfahrung"]):format(ready), min = 15, score = 60 + ready * 5 }
    end
    for z, info in pairs(zones) do
        if info.n >= 2 then
            out[#out + 1] = { icon = "Interface\\Icons\\INV_Misc_Map_01", title = z,
                sub = (L["%d passende Quests im Log"]):format(info.n), min = 15 + info.n * 8, score = 30 + info.n * 6 }
        end
    end
    -- Dungeons im Stufenbereich
    if ns.Dungeons and ns.Dungeons.List then
        local ok, list = pcall(ns.Dungeons.List)
        for _, d in ipairs(ok and list or {}) do
            if d.lo and d.status ~= "closed" and d.status ~= "client" and lvl >= d.lo - 1 and lvl <= (d.hi or d.lo) + 1 then
                local okQ, mine = pcall(ns.Dungeons.MyQuestCount, d)
                mine = okQ and mine or 0
                local wants = 0
                if ns.Dungeons.WantedLoot then local okW, w = pcall(ns.Dungeons.WantedLoot, d) wants = okW and #w or 0 end
                local ups = Life.DungeonUpgrades(d)
                local parts = {}
                if mine > 0 then parts[#parts + 1] = (L["%d offene Quests"]):format(mine) end
                if ups > 0 then parts[#parts + 1] = (L["%d moegliche Upgrades"]):format(ups) end
                if wants > 0 then parts[#parts + 1] = (L["%d von der Gilde gesucht"]):format(wants) end
                parts[#parts + 1] = (L["Stufe %d-%d"]):format(d.lo, d.hi or d.lo)
                local name = (ns.lang == "de" and (d.nameDE or d.de)) or d.name
                out[#out + 1] = { icon = "Interface\\Icons\\INV_Misc_Key_03", title = name, sub = table.concat(parts, " · "),
                    min = d.raid and 150 or 75, score = 25 + mine * 10 + ups * 8 + wants * 3, page = "dungeons", group = true }
            end
        end
    end
    -- Berufe kurz vor der Grenze
    if ns.Radar and ns.Radar.myProfessions then
        for _, p in ipairs(ns.Radar.myProfessions()) do
            if p.max and p.max > 0 and p.max < 300 and p.rank >= p.max - 10 then
                out[#out + 1] = { icon = "Interface\\Icons\\INV_Misc_Book_09", title = p.name,
                    sub = (L["%d/%d - beim Lehrer die naechste Stufe lernen"]):format(p.rank, p.max), min = 10, score = 50 }
            elseif p.max and p.rank < p.max then
                out[#out + 1] = { icon = "Interface\\Icons\\Trade_Engineering", title = p.name,
                    sub = (L["%d/%d - noch %d Punkte bis zur Grenze"]):format(p.rank, p.max, p.max - p.rank), min = 30, score = 12 }
            end
        end
    end
    -- Klassenlehrer (neue Raenge auf geraden Stufen)
    local l = db()
    if l and lvl % 2 == 0 and (l.trainedAt or 0) < lvl and lvl >= 4 then
        out[#out + 1] = { icon = "Interface\\Icons\\INV_Misc_Book_11", title = L["Klassenlehrer"],
            sub = (L["Mit Stufe %d gibt es neue Zauber/Faehigkeiten"]):format(lvl), min = 10, score = 55 }
    end
    -- Reparatur
    local worst = 1
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        cur, max = ns.safe(cur), ns.safe(max)
        if cur and max and max > 0 then worst = math.min(worst, cur / max) end
    end
    if worst < 0.3 then
        out[#out + 1] = { icon = "Interface\\Icons\\Trade_BlackSmithing", title = L["Reparieren"],
            sub = (L["Ausruestung bei %d%%"]):format(worst * 100), min = 5, score = 70 }
    end
    -- Erholt-Bonus
    local rest = GetXPExhaustion and ns.safe(GetXPExhaustion())
    local maxXP = ns.safe(UnitXPMax("player")) or 0
    if rest and maxXP > 0 and rest > maxXP * 0.5 then
        out[#out + 1] = { icon = "Interface\\Icons\\Spell_Nature_Sleep", title = L["Erholt-Bonus nutzen"],
            sub = (L["%d%% einer Stufe doppelte Erfahrung"]):format(math.min(150, math.floor(rest / maxXP * 100))), min = 30, score = 35 }
    end
    -- offene Ziele
    for _, g in ipairs(l and l.goals or {}) do
        if not g.done then
            local cur, max = Life.GoalProgress(g)
            out[#out + 1] = { icon = "Interface\\Icons\\Achievement_General", title = L["Ziel"] .. ": " .. g.text,
                sub = (g.kind ~= "free" and (cur .. " / " .. max) or L["eigenes Ziel"]), min = 45, score = 20, page = nil, goal = true }
        end
    end
    -- Zeitbudget
    local limit = budget == "30" and 35 or (budget == "60" and 70 or 9999)
    local res = {}
    for _, s in ipairs(out) do
        if s.min <= limit then
            if budget == "120" and s.min >= 60 then s.score = s.score + 15 end
            res[#res + 1] = s
        end
    end
    table.sort(res, function(a, b) return a.score > b.score end)
    return res
end
-- Wie viele Beutestuecke eines Dungeons waeren fuer dich ein Upgrade? (nur bereits geladene Items)
local upCache, upAt = {}, 0
function Life.DungeonUpgrades(d)
    if not (ns.Upgrade and ns.Upgrade.Compare and d.bosses) then return 0 end
    if GetTime() - upAt > 60 then upCache, upAt = {}, GetTime() end
    if upCache[d.key] then return upCache[d.key] end
    local n = 0
    for _, b in ipairs(d.bosses) do
        for _, it in ipairs(b.loot or {}) do
            local id = type(it) == "table" and it[1] or it
            if id then
                local ok, _, link = pcall(C_Item.GetItemInfo, id)
                if ok and link then
                    local okC, pct = pcall(ns.Upgrade.Compare, link)
                    if okC and pct and pct > 2 then n = n + 1 end
                elseif C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            end
        end
    end
    upCache[d.key] = n
    return n
end

------------------------------------------------------------------------
-- Jahrbuch
------------------------------------------------------------------------
function Life.Yearbook()
    local l = db()
    if not l then return {} end
    local y = {}
    y.name = ns.displayName and ns.displayName(ns.me()) or ns.UnitName("player")
    y.level = UnitLevel("player")
    y.className = UnitClass("player")
    y.created = l.created
    y.played = l.played or l.stats.online or 0
    y.kills = l.stats.kills or 0
    y.deaths = l.stats.deaths or 0
    y.runs = #l.runs
    y.quests = l.stats.quests or 0
    y.goldIn = l.stats.goldIn or 0
    y.goldOut = l.stats.goldOut or 0
    y.bosses = l.stats.bosses or 0
    y.zones = 0
    for _ in pairs(l.zones) do y.zones = y.zones + 1 end
    -- Lieblingsdungeon
    local cnt = {}
    for _, r in ipairs(l.runs) do cnt[r.name] = (cnt[r.name] or 0) + 1 end
    for n, c in pairs(cnt) do if not y.favN or c > y.favN then y.fav, y.favN = n, c end end
    -- Erzfeind
    local k = {}
    for _, d in ipairs(l.deaths) do
        local who = d.killer or (d.tips and (d.tips[#d.tips] == "fall" and L["Fallschaden"] or nil))
        if who then k[who] = (k[who] or 0) + 1 end
    end
    for n, c in pairs(k) do if not y.nemN or c > y.nemN then y.nem, y.nemN = n, c end end
    -- liebster Mitspieler
    for n, m in pairs(l.mates) do if not y.buddyN or (m.runs or 0) > y.buddyN then y.buddy, y.buddyN = n, m.runs or 0 end end
    y.recs = 0
    for _ in pairs(l.rec) do y.recs = y.recs + 1 end
    y.goals = 0
    for _, g in ipairs(l.goals) do if g.done then y.goals = y.goals + 1 end end
    return y
end
function Life.YearbookText()
    local y = Life.Yearbook()
    local parts = { ("%s - %s %d %s"):format(L["Jahrbuch"], y.name or "?", y.level or 0, y.className or "") }
    parts[#parts + 1] = (L["%d Gegner besiegt"]):format(y.kills)
    parts[#parts + 1] = (L["%d Tode"]):format(y.deaths)
    parts[#parts + 1] = (L["%d Dungeon-Laeufe"]):format(y.runs)
    parts[#parts + 1] = plain(y.goldIn) .. " " .. L["verdient"]
    if y.fav then parts[#parts + 1] = L["Lieblingsdungeon"] .. ": " .. y.fav end
    if y.nem then parts[#parts + 1] = L["Erzfeind"] .. ": " .. y.nem end
    return table.concat(parts, " | ")
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
local function pat(g)
    local s = _G[g]
    if type(s) ~= "string" then return nil end
    s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. s .. "$"
end
local patCache = {}
local function P(g) if patCache[g] == nil then patCache[g] = pat(g) or false end return patCache[g] or nil end

ns.Listen("LOGIN", function()
    local l = db()
    if not l then return end
    if not l.ms.start then
        l.ms.start = now()
        Life.Event("start", (L["Oasis begleitet %s ab heute (Stufe %d)"]):format(ns.UnitName("player") or "?", UnitLevel("player") or 1), "Interface\\Icons\\INV_Misc_Book_07")
    end
    session.start = now()
    session.kills = 0
    noDeathSince = now()
    lastMoney = GetMoney and GetMoney()
    if lastMoney then l.gold.hist[dayKey()] = lastMoney end
    C_Timer.NewTicker(60, tick)
    ns.After(3, checkInstance)
    ns.After(5, function() Life.CheckGoals() Life.CheckProfs() end)
end)

ns.On("PLAYER_LEVEL_UP", function(level)
    local l = db()
    if not l then return end
    level = tonumber(ns.safe(level)) or UnitLevel("player")
    local secs = l.lvlSecs
    Life.Event("level", (L["Stufe %d erreicht"]):format(level), "Interface\\Icons\\Spell_Holy_SurgeOfLight")
    if secs and secs >= 300 and l.lvlFrom == level - 1 then
        Life.Record("fastLevel", secs, { label = (L["Schnellstes Level (%d > %d)"]):format(level - 1, level) })
    end
    l.lvlSecs, l.lvlFrom = 0, level
    ns.After(1, Life.CheckGoals)
end)
ns.Listen("LOGIN", function() local l = db() if l and not l.lvlFrom then l.lvlFrom = UnitLevel("player") l.lvlSecs = 0 end end)

-- 0.5.613: Kill = XP-Meldung mit "stirbt/dies". Im Kampf ist der Text in Forever geheim (vorher fiel dadurch
-- fast jeder Kill durch) -> dann zaehlt die Meldung selbst, ausser direkt nach einer Questabgabe/Entdeckung.
local noKillUntil = 0
ns.On("QUEST_TURNED_IN", function() noKillUntil = GetTime() + 2 end)
ns.On("UI_INFO_MESSAGE", function() noKillUntil = math.max(noKillUntil, GetTime() + 0.5) end)
function Life.IsKillXP(raw)
    local msg = ns.safe(raw)
    if msg then return (msg:find("stirbt") or msg:lower():find("dies")) and true or false end
    return raw ~= nil and GetTime() > noKillUntil
end
-- 0.5.616: Die XP-Chatmeldung kommt in Forever nicht zuverlaessig (Zaehler blieb bei 0). Kill jetzt ueber zwei
-- Wege, je Toetung nur einmal gezaehlt: (a) Erfahrung gestiegen ohne Questabgabe, (b) das eigene Ziel stirbt
-- (feindlich, kein Spieler, nicht von anderen markiert) - (b) zaehlt auch auf Stufe 60.
local lastKill = 0
local function kill()
    local t = GetTime()
    if t - lastKill < 1.5 then return end
    lastKill = t
    ns.Fire("KILL")
end
Life.CountKill = kill
do
    local xpL, xpX
    ns.On("PLAYER_XP_UPDATE", function()
        local x, l = ns.safe(UnitXP("player")), ns.safe(UnitLevel("player"))
        if not (x and l) then return end
        local gained = xpX and xpL == l and x > xpX
        xpL, xpX = l, x
        if gained then
            -- Questabgabe kommt manchmal erst nach dem XP-Ereignis -> kurz warten
            C_Timer.After(0.4, function() if GetTime() > noKillUntil then kill() end end)
        end
    end)
    ns.Listen("LOGIN", function() xpL, xpX = ns.safe(UnitLevel("player")), ns.safe(UnitXP("player")) end)
end
do
    local alive = false
    local function look()
        if not UnitExists("target") then alive = false return end
        local dead = ns.safe(UnitIsDead("target"))
        if dead == nil then return end
        if not dead then
            alive = ns.safe(UnitCanAttack("player", "target")) and not ns.safe(UnitIsPlayer("target")) and true or false
            return
        end
        if alive and not (UnitIsTapDenied and ns.safe(UnitIsTapDenied("target"))) then kill() end
        alive = false
    end
    ns.On("PLAYER_TARGET_CHANGED", function() alive = false look() end)
    ns.On("UNIT_HEALTH", function(unit) if unit == "target" then look() end end)
end
ns.Listen("KILL", function()
    local total = stat("kills", 1)
    session.kills = session.kills + 1
    Life.Record("killsSession", session.kills, nil, true)
    local t = GetTime()
    local kt = session.killTimes
    kt[#kt + 1] = t
    while kt[1] and t - kt[1] > 3600 do table.remove(kt, 1) end
    Life.Record("killsHour", #kt, nil, true)
    milestone("kills", { 100, 1000, 5000, 10000, 25000, 50000 }, total, "%d Gegner besiegt", "Interface\\Icons\\Ability_Warrior_Rampage")
end)

ns.On("QUEST_TURNED_IN", function()
    lastQuest = GetTime()
    local total = stat("quests", 1)
    dayRecord("quests", "questsDay")
    milestone("quests", { 10, 100, 250, 500, 1000, 2000 }, total, "%d Quests abgeschlossen", "Interface\\Icons\\INV_Misc_Note_01")
end)

ns.On("CHAT_MSG_MONEY", function() lastLoot = GetTime() end)
ns.On("LOOT_OPENED", function() lastLoot = GetTime() end)
ns.On("PLAYER_MONEY", onMoney)
for ev, k in pairs({ MERCHANT_SHOW = "merchant", TRAINER_SHOW = "train", TAXIMAP_OPENED = "taxi", AUCTION_HOUSE_SHOW = "ah",
    MAIL_SHOW = "mail", TRADE_SHOW = "trade", GUILDBANKFRAME_OPENED = "gbank" }) do
    ns.On(ev, function()
        ctx[k] = true
        if k == "train" then local l = db() if l then l.trainedAt = UnitLevel("player") end end
    end)
end
for ev, k in pairs({ MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "train", TAXIMAP_CLOSED = "taxi", AUCTION_HOUSE_CLOSED = "ah",
    MAIL_CLOSED = "mail", TRADE_CLOSED = "trade", GUILDBANKFRAME_CLOSED = "gbank" }) do
    ns.On(ev, function() ns.After(1, function() ctx[k] = nil end) end)
end
-- Flug: Geld wird abgezogen, waehrend das Fenster schliesst
if hooksecurefunc then
    if RepairAllItems then hooksecurefunc("RepairAllItems", function(gb) if not gb then repairPending = GetTime() end end) end
    if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function() ctx.taxi = true ns.After(2, function() ctx.taxi = nil end) end) end
end

ns.On("PLAYER_ENTERING_WORLD", function() ns.After(2, checkInstance) end)
ns.On("ZONE_CHANGED_NEW_AREA", function()
    ns.After(1, checkInstance)
    local l = db()
    local z = ns.safe(GetRealZoneText())
    if l and z and z ~= "" and not l.zones[z] then
        l.zones[z] = now()
        local first = l.ms.zoneInit
        if first then
            Life.Event("zone", (L["Neues Gebiet entdeckt: %s"]):format(z), "Interface\\Icons\\INV_Misc_Map_01")
            dayRecord("zones", "zonesDay")
        end
    end
    if l then l.ms.zoneInit = l.ms.zoneInit or now() end
end)
ns.On("GROUP_ROSTER_UPDATE", function() local l = db() if l and l.cur then scanParty(l.cur) end end)

ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    if ns.safe(success) ~= 1 then return end
    local l = db()
    if not l then return end
    encounterName = ns.safe(encounterName) or "?"
    stat("bosses", 1)
    dayRecord("bosses", "bossesDay")
    local r = l.cur
    if r then
        r.bosses = (r.bosses or 0) + 1
        r.lastBoss = now()
        r.bossList[#r.bossList + 1] = encounterName
        scanParty(r)
    end
    local id = "boss:" .. tostring(ns.safe(encounterID) or encounterName)
    if not l.firsts[id] then
        l.firsts[id] = now()
        Life.Event("boss", (L["Zum ersten Mal besiegt: %s"]):format(encounterName), "Interface\\Icons\\Achievement_Boss_Ragnaros")
    end
    refresh()
end)

ns.On("CHAT_MSG_LOOT", function(msg)
    msg = ns.safe(msg)
    if not msg then return end
    local link
    for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
        local p = P(g)
        if p then
            local m = msg:match(p)
            if m then link = m break end
        end
    end
    if not link or not link:find("|Hitem:") then return end
    local ok, _, _, q = pcall(C_Item.GetItemInfo, link)
    q = ok and q or nil
    local l = db()
    if not l then return end
    if l.cur and q and q >= 2 then
        l.cur.loot[#l.cur.loot + 1] = link
        stat("dloot", 1)
    end
    if q and q >= 3 then
        local id = tonumber(link:match("item:(%d+)"))
        if id and not l.firsts["item:" .. id] then
            l.firsts["item:" .. id] = now()
            Life.Event("loot", (q >= 4 and L["Episches Item erhalten:"] or L["Besonderes Item erhalten:"]), "Interface\\Icons\\INV_Misc_Gem_Variety_01", link)
        end
    end
    ns.After(1, Life.CheckGoals)
end)

ns.On("PLAYER_TARGET_CHANGED", rememberFoe)
ns.On("PLAYER_REGEN_DISABLED", function() fight.start = GetTime() rememberFoe() end)
ns.On("PLAYER_REGEN_ENABLED", function() fight.start = nil end)
ns.On("PLAYER_DEAD", onDeath)

ns.On("TIME_PLAYED_MSG", function(total)
    local l = db()
    total = tonumber(ns.safe(total))
    if l and total then l.played = total end
end)

-- Berufs-Meilensteine
function Life.CheckProfs()
    local l = db()
    if not (l and ns.Radar and ns.Radar.myProfessions) then return end
    for _, p in ipairs(ns.Radar.myProfessions()) do
        for _, s in ipairs({ 75, 150, 225, 300 }) do
            local id = "prof:" .. (p.id or p.name) .. ":" .. s
            if p.rank >= s and not l.ms[id] then
                l.ms[id] = now()
                if l.ms.profInit then Life.Event("prof", (L["%s: Fertigkeit %d erreicht"]):format(p.name, s), "Interface\\Icons\\INV_Misc_Book_09") end
            end
        end
    end
    l.ms.profInit = l.ms.profInit or now()
    Life.CheckGoals()
end
ns.On("SKILL_LINES_CHANGED", function() ns.After(1, Life.CheckProfs) end)
ns.On("BAG_UPDATE_DELAYED", function() if db() then Life.CheckGoals() end end)

-- Abmelden: offenen Lauf nicht verlieren (wird beim naechsten Login fortgesetzt oder abgeschlossen)
ns.On("PLAYER_LOGOUT", function()
    local l = db()
    if l and session.start then Life.Record("session", now() - session.start, nil, true) end
end)

-- eigener Sound-Typ fuer Rekorde (Einstellungen > Sound/Hinweise)
if ns.Sound and ns.Sound.EVENTS and not ns.Sound.eventByKey.record then
    local e = { key = "record", text = "Persoenlicher Rekord / Ziel erreicht", def = "arbeitszeit" }
    table.insert(ns.Sound.EVENTS, e)
    ns.Sound.eventByKey.record = e
end

------------------------------------------------------------------------
-- Oberflaeche
------------------------------------------------------------------------
Life.view = "journey"
local VIEWS = {
    { key = "journey", text = "Reise" }, { key = "records", text = "Rekorde" }, { key = "dungeons", text = "Dungeons" },
    { key = "mates", text = "Mitspieler" }, { key = "deaths", text = "Tode" }, { key = "gold", text = "Gold" },
    { key = "goals", text = "Ziele" }, { key = "todo", text = "Was tun?" }, { key = "year", text = "Jahrbuch" },
}

-- NIE "StaticPopupDialogs = ..." zuweisen (verseucht Blizzards Dialogliste -> Esc/Ausloggen blockiert)
StaticPopupDialogs["OASIS_LIFE_TEXT"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL, hasEditBox = true, editBoxWidth = 320,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetText(data and data.text or "") eb:HighlightText() eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        local t = eb and (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
        if data and data.fn then data.fn(t) end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
local function ask(text, cur, fn) StaticPopup_Show("OASIS_LIFE_TEXT", text, nil, { text = cur, fn = fn }) end

-- einfache Zeilenliste mit Symbol, Titel, Untertitel, Wert rechts
local function iconList(parent, rowH)
    return K.List(parent, rowH or 40, function(list)
        local r = K.Row(list)
        r.ic = r:CreateTexture(nil, "ARTWORK")
        r.ic:SetSize(rowH and rowH - 12 or 28, rowH and rowH - 12 or 28)
        r.ic:SetPoint("LEFT", 8, 0)
        r.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.title = K.Text(r, 13, C.text)
        r.title:SetPoint("TOPLEFT", r.ic, "TOPRIGHT", 10, -1)
        r.title:SetPoint("RIGHT", -150, 0)
        r.title:SetWordWrap(false)
        r.sub = K.Text(r, 11, C.muted)
        r.sub:SetPoint("BOTTOMLEFT", r.ic, "BOTTOMRIGHT", 10, 1)
        r.sub:SetPoint("RIGHT", -150, 0)
        r.sub:SetWordWrap(false)
        r.val = K.Text(r, 13, C.amber, "RIGHT")
        r.val:SetPoint("RIGHT", -12, 0)
        r.val:SetWidth(140)
        r:SetScript("OnEnter", function(s)
            if s.item and s.item.link then K.ItemTip(s, s.item.link)
            elseif s.item and s.item.tip then K.ShowTip(s, s.item.tip) end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(s, btn) if s.item and s.item.click then s.item.click(btn, s) end end)
        return r
    end, function(r, it)
        r.ic:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.ic:SetShown(it.icon ~= false)
        r.title:SetText(it.title or "")
        r.sub:SetText(it.sub or "")
        r.val:SetText(it.val or "")
        local c = it.color
        if c then r.title:SetTextColor(c[1], c[2], c[3]) else r.title:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        r.title:ClearAllPoints()
        if it.sub and it.sub ~= "" then r.title:SetPoint("TOPLEFT", r.ic, "TOPRIGHT", 10, -1)
        else r.title:SetPoint("LEFT", r.ic, "RIGHT", 10, 0) end
        r.title:SetPoint("RIGHT", -150, 0)
    end)
end

local function tiles(p, defs)
    p.tiles = {}
    for i, d in ipairs(defs) do
        local t = K.HudTile(p, d[1], L[d[2]], d[3])
        t:SetHeight(62)
        p.tiles[i] = t
    end
    p:HookScript("OnSizeChanged", function(self, w)
        local n = #self.tiles
        local tw = math.floor(((w or 750) - (n - 1) * 10) / n)
        for i, t in ipairs(self.tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
            t:SetWidth(tw)
        end
    end)
end

local function sub(p, key)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -36)
    f:SetPoint("BOTTOMRIGHT")
    p.views[key] = f
    return f
end

local function relDay(t)
    local d = dayKey(t)
    if d == dayKey() then return L["Heute"] end
    if d == dayKey(now() - DAY) then return L["Gestern"] end
    return fmtDate(t)
end

-- Seite
ns.RegisterPage({
    key = "life", title = "Mein Weg", order = 1.15, topbar = true,   -- im Profil eingebettet (Insta.lua)
    sub = "Dein Leben in Azeroth: Reise, Rekorde, Dungeons, Ziele und Jahrbuch",
    build = function(p)
        p.views = {}
        p.seg = K.Segments(p, (function()
            local t = {}
            for _, v in ipairs(VIEWS) do t[#t + 1] = { key = v.key, text = L[v.text] } end
            return t
        end)(), function(k) Life.view = k refresh() end, nil, { size = 12, pad = 16 })
        p.seg:SetPoint("TOPLEFT", 0, 0)

        -------------------------------------------------- Reise
        local j = sub(p, "journey")
        tiles(j, { { ns.ICONS.chronicle, "Momente", C.accent }, { ns.ICONS.map, "Gebiete entdeckt", C.blue },
            { ns.ICONS.dungeons, "Erste Bosskills", C.red }, { ns.ICONS.badges, "Mit Oasis seit", C.mint } })
        j.filter = "all"
        j.fseg = K.Segments(j, { { key = "all", text = L["Alles"] }, { key = "level", text = L["Level"] }, { key = "boss", text = L["Bosse"] },
            { key = "loot", text = L["Beute"] }, { key = "zone", text = L["Gebiete"] }, { key = "record", text = L["Rekorde"] } },
            function(k) j.filter = k refresh() end, nil, { size = 11, pad = 14 })
        j.fseg:SetPoint("TOPLEFT", 0, -74)
        j.list = iconList(j, 36)
        j.list:SetPoint("TOPLEFT", 0, -106)
        j.list:SetPoint("BOTTOMRIGHT")
        j.list.empty:SetText(L["Noch keine Momente - spiel einfach, Oasis schreibt mit."])

        -------------------------------------------------- Rekorde
        local r = sub(p, "records")
        r.head = K.GameHead(r, L["Persoenliche Rekorde"], C.amber)
        r.head:SetPoint("TOPLEFT", 0, -2)
        r.head:SetWidth(400)
        r.note = K.Text(r, 11, C.muted, "RIGHT")
        r.note:SetPoint("TOPRIGHT", 0, -4)
        r.note:SetText(L["Crits und Schaden sind in Forever fuer Addons gesperrt"])
        r.list = iconList(r, 44)
        r.list:SetPoint("TOPLEFT", 0, -28)
        r.list:SetPoint("BOTTOMRIGHT")

        -------------------------------------------------- Dungeons
        local d = sub(p, "dungeons")
        tiles(d, { { ns.ICONS.dungeons, "Laeufe", C.amber }, { ns.ICONS.raid, "Bosse besiegt", C.red },
            { ns.ICONS.deaths, "Tode in Dungeons", C.muted }, { ns.ICONS.wants, "Beute erhalten", C.mint } })
        d.cur = K.Text(d, 12, C.mint)
        d.cur:SetPoint("TOPLEFT", 0, -76)
        d.list = iconList(d, 44)
        d.list:SetPoint("TOPLEFT", 0, -98)
        d.list:SetPoint("BOTTOMRIGHT")
        d.list.empty:SetText(L["Noch keine Dungeon-Laeufe aufgezeichnet."])

        -------------------------------------------------- Mitspieler
        local m = sub(p, "mates")
        m.head = K.GameHead(m, L["Mit wem du unterwegs warst"], C.blue)
        m.head:SetPoint("TOPLEFT", 0, -2)
        m.head:SetWidth(400)
        m.search = K.Input(m, 200, L["Suchen..."], function() refresh() end)
        m.search:SetPoint("TOPRIGHT", 0, 0)
        m.list = iconList(m, 40)
        m.list:SetPoint("TOPLEFT", 0, -32)
        m.list:SetPoint("BOTTOMRIGHT")
        m.list.empty:SetText(L["Sobald du in einer Gruppe einen Dungeon betrittst, merkt sich Oasis deine Mitspieler."])

        -------------------------------------------------- Tode
        local t = sub(p, "deaths")
        tiles(t, { { ns.ICONS.deaths, "Tode", C.red }, { ns.ICONS.radar, "Erzfeind", C.amber },
            { ns.ICONS.wants, "Mit Trank in der Tasche", C.blue }, { ns.ICONS.badges, "Ohne Tod seit", C.mint } })
        t.list = iconList(t, 52)
        t.list:SetPoint("TOPLEFT", 0, -76)
        t.list:SetPoint("BOTTOMRIGHT")
        t.list.empty:SetText(L["Noch kein Tod - weiter so!"])

        -------------------------------------------------- Gold
        local g = sub(p, "gold")
        tiles(g, { { ns.ICONS.trade, "Heute", C.amber }, { ns.ICONS.trade, "7 Tage", C.mint },
            { ns.ICONS.trade, "30 Tage", C.blue }, { ns.ICONS.bank, "Insgesamt verdient", C.accent } })
        g.range = 7
        g.rseg = K.Segments(g, { { key = 1, text = L["Heute"] }, { key = 7, text = L["7 Tage"] }, { key = 30, text = L["30 Tage"] }, { key = 9999, text = L["Alles"] } },
            function(k) g.range = k refresh() end, nil, { size = 11, pad = 14 })
        g.rseg:SetPoint("TOPLEFT", 0, -74)
        g.spark = CreateFrame("Frame", nil, g)
        g.spark:SetPoint("TOPRIGHT", 0, -72)
        g.spark:SetSize(300, 28)
        g.spark.bars = {}
        g.inc = iconList(g, 30)
        g.inc:SetPoint("TOPLEFT", 0, -130)
        g.inc:SetPoint("BOTTOMRIGHT", g, "BOTTOM", -6, 0)
        g.out = iconList(g, 30)
        g.out:SetPoint("TOPLEFT", g, "TOP", 6, -130)
        g.out:SetPoint("BOTTOMRIGHT")
        g.h1 = K.GameHead(g, L["Einnahmen"], C.mint)
        g.h1:SetPoint("TOPLEFT", 0, -106)
        g.h1:SetWidth(300)
        g.h2 = K.GameHead(g, L["Ausgaben"], C.red)
        g.h2:SetPoint("TOPLEFT", g, "TOP", 6, -106)
        g.h2:SetWidth(300)

        -------------------------------------------------- Ziele
        local z = sub(p, "goals")
        z.kind = "level"
        z.kseg = K.Segments(z, { { key = "level", text = L["Stufe"] }, { key = "gold", text = L["Gold"] }, { key = "prof", text = L["Beruf"] },
            { key = "item", text = L["Item"] }, { key = "run", text = L["Dungeon"] }, { key = "free", text = L["Frei"] } },
            function(k) z.kind = k z.hint:SetText(L[({ level = "Zielstufe, z.B. 42", gold = "Gold, z.B. 100", prof = "Beruf und Stufe, z.B. Schneiderei 225",
                item = "Item-Link oder Name (+ Anzahl am Ende)", run = "Dungeon und Anzahl Laeufe, z.B. Kloster 5", free = "Was willst du schaffen?" })[k]]) end,
            nil, { size = 11, pad = 14 })
        z.kseg:SetPoint("TOPLEFT", 0, 0)
        z.input = K.Input(z, 330, "", nil)
        z.input:SetPoint("TOPLEFT", 0, -32)
        z.hint = K.Text(z, 11, C.muted)
        z.hint:SetPoint("LEFT", z.input, "RIGHT", 120, 0)
        z.hint:SetText(L["Zielstufe, z.B. 42"])
        z.add = K.Button(z, L["Ziel anlegen"], 110, 24, "primary", function() Life.AddFromInput(z.kind, z.input:GetText()) z.input:SetText("") z.input:ClearFocus() end)
        z.add:SetPoint("LEFT", z.input, "RIGHT", 6, 0)
        z.input:SetScript("OnEnterPressed", function() z.add:Click() end)
        -- Item-Link per Shift-Klick einfuegen
        if hooksecurefunc and ChatEdit_InsertLink then
            hooksecurefunc("ChatEdit_InsertLink", function(link)
                if z:IsVisible() and z.input:HasFocus() and link then z.input:Insert(link) end
            end)
        end
        z.list = iconList(z, 40)
        z.list:SetPoint("TOPLEFT", 0, -66)
        z.list:SetPoint("BOTTOMRIGHT")
        z.list.empty:SetText(L["Noch keine Ziele. Leg oben eins an - Oasis hakt es automatisch ab."])

        -------------------------------------------------- Was tun?
        local w = sub(p, "todo")
        w.budget = "60"
        w.bseg = K.Segments(w, { { key = "30", text = L["30 Minuten"] }, { key = "60", text = L["1 Stunde"] }, { key = "120", text = L["2+ Stunden"] } },
            function(k) w.budget = k refresh() end, nil, { size = 12, pad = 18 })
        w.bseg:SetPoint("TOPLEFT", 0, 0)
        w.info = K.Text(w, 11, C.muted, "RIGHT")
        w.info:SetPoint("TOPRIGHT", 0, -6)
        w.list = iconList(w, 46)
        w.list:SetPoint("TOPLEFT", 0, -34)
        w.list:SetPoint("BOTTOMRIGHT")
        w.list.empty:SetText(L["Gerade nichts Besonderes - einfach losziehen!"])

        -------------------------------------------------- Jahrbuch (2026: Glas-Hero + gruppierte Kacheln + Highlights)
        local y = sub(p, "year")
        local function glass(f, fill, line, r)
            local G = ns.Insta and ns.Insta.Glass
            if G then G(f, fill, line, r) elseif not f.bg then f.bg = K.Fill(f, C.panel) end
        end
        local ICO = ns.MEDIA .. "icons\\"
        -- Inhalt in einem Ausschnitt; reicht die Hoehe nicht, mit dem Mausrad schieben
        y.clip = CreateFrame("Frame", nil, y)
        y.clip:SetPoint("TOPLEFT", 0, 0)
        y.clip:SetPoint("BOTTOMRIGHT", 0, 38)
        y.clip:SetClipsChildren(true)
        y.clip:EnableMouseWheel(true)
        y.body = CreateFrame("Frame", nil, y.clip)
        y.body:SetPoint("TOPLEFT", 0, 0)
        y.body:SetPoint("RIGHT", y.clip, "RIGHT", -6, 0)
        y.body:SetHeight(342)
        y.off = 0
        y.sb = y.clip:CreateTexture(nil, "OVERLAY")
        y.sb:SetWidth(3)
        y.sb:SetColorTexture(1, 1, 1, 0.18)
        local function scrollTo(off)
            local maxOff = math.max(0, (y.body:GetHeight() or 0) - (y.clip:GetHeight() or 0))
            y.off = math.max(0, math.min(off or 0, maxOff))
            y.body:ClearAllPoints()
            y.body:SetPoint("TOPLEFT", 0, y.off)
            y.body:SetPoint("RIGHT", y.clip, "RIGHT", -6, 0)
            local ch = y.clip:GetHeight() or 0
            y.sb:SetShown(maxOff > 0 and ch > 0)
            if maxOff > 0 and ch > 0 then
                local th = math.max(20, ch * ch / (ch + maxOff))
                y.sb:ClearAllPoints()
                y.sb:SetPoint("TOPRIGHT", y.clip, "TOPRIGHT", 0, -(ch - th) * y.off / maxOff)
                y.sb:SetHeight(th)
            end
        end
        y.clip:SetScript("OnMouseWheel", function(_, d) scrollTo(y.off - d * 40) end)
        y.clip:SetScript("OnSizeChanged", function() scrollTo(y.off) end)
        y.ScrollTo = scrollTo

        -- Kopf: Portraet, Name, Klasse in Klassenfarbe, Zeitraum; rechts die Spielzeit gross
        y.hero = CreateFrame("Frame", nil, y.body)
        y.hero:SetPoint("TOPLEFT", 0, 0)
        y.hero:SetPoint("TOPRIGHT", 0, 0)
        y.hero:SetHeight(96)
        glass(y.hero, nil, nil, 14)
        y.portrait = y.hero:CreateTexture(nil, "ARTWORK")
        y.portrait:SetSize(68, 68)
        y.portrait:SetPoint("LEFT", 16, 0)
        pcall(y.portrait.SetMask, y.portrait, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        y.ring = y.hero:CreateTexture(nil, "BORDER")
        y.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        y.ring:SetSize(74, 74)
        y.ring:SetPoint("CENTER", y.portrait, "CENTER")
        y.kicker = K.Text(y.hero, 11, C.muted)
        y.kicker:SetPoint("TOPLEFT", 100, -16)
        y.name = K.Title(y.hero, 22, C.text)
        y.name:SetPoint("TOPLEFT", y.kicker, "BOTTOMLEFT", 0, -4)
        y.cls = K.Text(y.hero, 12, C.text)
        y.cls:SetPoint("TOPLEFT", y.name, "BOTTOMLEFT", 0, -5)
        y.since = K.Text(y.hero, 11, C.dim)
        y.since:SetPoint("TOPLEFT", y.cls, "BOTTOMLEFT", 0, -4)
        y.timeV = K.Title(y.hero, 24, C.text, "RIGHT")
        y.timeV:SetPoint("TOPRIGHT", -20, -26)
        y.timeL = K.Text(y.hero, 11, C.muted, "RIGHT")
        y.timeL:SetPoint("TOPRIGHT", y.timeV, "BOTTOMRIGHT", 0, -4)
        for _, fs in ipairs({ y.kicker, y.name, y.cls, y.since }) do fs:SetPoint("RIGHT", y.hero, "RIGHT", -190, 0) end

        -- Kennzahlen: vier Gruppen nebeneinander, je eine Spalte Glas-Kacheln mit Symbol
        local GROUPS = {
            { "Kampf", { { "kills", "raid", "Gegner besiegt" }, { "bosses", "dungeons", "Bosse besiegt" }, { "deaths", "deaths", "Tode" } } },
            { "Abenteuer", { { "runs", "dungeons", "Dungeon-Laeufe" }, { "quests", "checklist", "Quests abgeschlossen" }, { "zones", "map", "Gebiete entdeckt" } } },
            { "Gold", { { "goldIn", "bank", "Gold verdient" }, { "goldOut", "bank", "Gold ausgegeben" } } },
            { "Meilensteine", { { "recs", "badges", "Persoenliche Rekorde" }, { "goals", "pin", "Ziele erreicht" } } },
        }
        y.groups, y.tiles = {}, {}
        for gi, g in ipairs(GROUPS) do
            local col = CreateFrame("Frame", nil, y.body)
            col.cap = K.Text(col, 11, C.muted)
            col.cap:SetPoint("TOPLEFT", 4, 0)
            col.cap:SetText(L[g[1]])
            col.tiles = {}
            for ti, d in ipairs(g[2]) do
                local t = CreateFrame("Frame", nil, col)
                t:SetHeight(44)
                t:SetPoint("TOPLEFT", 0, -18 - (ti - 1) * 50)
                t:SetPoint("RIGHT", col, "RIGHT", 0, 0)
                glass(t, nil, nil, 10)
                t.icon = K.Glyph(t, 16, ICO .. d[2], C.muted)
                t.icon:SetPoint("LEFT", 12, 0)
                t.v = K.Title(t, 16, C.text)
                t.v:SetPoint("TOPLEFT", 38, -7)
                t.v:SetPoint("RIGHT", t, "RIGHT", -8, 0)
                t.l = K.Text(t, 10, C.muted)
                t.l:SetPoint("BOTTOMLEFT", 38, 7)
                t.l:SetPoint("RIGHT", t, "RIGHT", -8, 0)
                t.l:SetText(L[d[3]])
                t.key = d[1]
                col.tiles[ti] = t
                y.tiles[d[1]] = t
            end
            y.groups[gi] = col
        end

        -- Highlights: drei breitere Karten mit Text statt Zahl
        local HL = { { "fav", "dungeons", "Lieblingsdungeon" }, { "nem", "deaths", "Erzfeind" }, { "buddy", "groups", "Bester Mitspieler" } }
        y.hl = {}
        for i, d in ipairs(HL) do
            local c = CreateFrame("Frame", nil, y.body)
            c:SetHeight(58)
            glass(c, nil, nil, 12)
            c.icon = K.Glyph(c, 18, ICO .. d[2], C.amber)
            c.icon:SetPoint("TOPLEFT", 12, -10)
            c.cap = K.Text(c, 10, C.muted)
            c.cap:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
            c.cap:SetText(L[d[3]])
            c.v = K.Text(c, 13, C.text)
            c.v:SetPoint("BOTTOMLEFT", 12, 10)
            c.v:SetPoint("RIGHT", c, "RIGHT", -60, 0)
            c.n = K.Text(c, 11, C.dim, "RIGHT")
            c.n:SetPoint("BOTTOMRIGHT", -12, 10)
            c.key = d[1]
            y.hl[i] = c
        end

        local function layoutYear()
            local W = y.body:GetWidth() or 0
            if W < 200 then W = 745 end
            local gap = 10
            local cw = math.floor((W - gap * 3) / 4)
            local top = 96 + 14
            for gi, col in ipairs(y.groups) do
                col:ClearAllPoints()
                col:SetPoint("TOPLEFT", y.body, "TOPLEFT", (gi - 1) * (cw + gap), -top)
                col:SetSize(cw, 18 + 3 * 50)
            end
            local hy = top + 18 + 3 * 50 + 6
            local hw = math.floor((W - gap * 2) / 3)
            for i, c in ipairs(y.hl) do
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", y.body, "TOPLEFT", (i - 1) * (hw + gap), -hy)
                c:SetWidth(hw)
            end
            y.body:SetHeight(hy + 58 + 2)
            scrollTo(y.off)
        end
        y.body:SetScript("OnSizeChanged", layoutYear)
        y.Layout = layoutYear
        layoutYear()

        -- Knoepfe unten als ruhige Glas-Knoepfe
        local function glassBtn(b, primary)
            local ac = C.accent
            local fill = primary and { ac[1], ac[2], ac[3], 0.16 } or nil
            local line = primary and { ac[1], ac[2], ac[3], 0.45 } or nil
            glass(b, fill, line, 9)
            if b.sheen then b.sheen:Hide() end
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.05)
            if K.RoundMask then K.RoundMask(b.hl, b, 9) end
        end
        y.share = K.Button(y, L["Im Gildenchat teilen"], 170, 28, "ghost", function()
            if IsInGuild() then SendChatMessage(Life.YearbookText(), "GUILD") end
        end)
        y.share:SetPoint("BOTTOMLEFT", 0, 4)
        glassBtn(y.share, true)
        y.copy = K.Button(y, L["Als Text kopieren"], 150, 28, "ghost", function() ask(L["Strg+C zum Kopieren"], Life.YearbookText()) end)
        y.copy:SetPoint("LEFT", y.share, "RIGHT", 8, 0)
        glassBtn(y.copy)
        y.played = K.Button(y, L["/played abfragen"], 140, 28, "ghost", function() if RequestTimePlayed then RequestTimePlayed() end ns.After(1, refresh) end)
        y.played:SetPoint("LEFT", y.copy, "RIGHT", 8, 0)
        glassBtn(y.played)

        p.seg:Select(Life.view)
    end,

    refresh = function(p)
        local l = db()
        if not l then return end
        for k, f in pairs(p.views) do f:SetShown(k == Life.view) end
        if p.seg.Select then p.seg:Select(Life.view) end
        local v = p.views[Life.view]
        if Life.view == "journey" then Life.RefreshJourney(v, l)
        elseif Life.view == "records" then Life.RefreshRecords(v, l)
        elseif Life.view == "dungeons" then Life.RefreshDungeons(v, l)
        elseif Life.view == "mates" then Life.RefreshMates(v, l)
        elseif Life.view == "deaths" then Life.RefreshDeaths(v, l)
        elseif Life.view == "gold" then Life.RefreshGold(v, l)
        elseif Life.view == "goals" then Life.RefreshGoals(v, l)
        elseif Life.view == "todo" then Life.RefreshTodo(v, l)
        elseif Life.view == "year" then Life.RefreshYear(v, l) end
    end,
})

local function col(k) return C[KIND_COL[k] or "text"] or C.text end

function Life.RefreshJourney(j, l)
    local data, lastDay = {}, nil
    local nz, nb = 0, 0
    for _ in pairs(l.zones) do nz = nz + 1 end
    for k in pairs(l.firsts) do if k:find("^boss:") then nb = nb + 1 end end
    j.tiles[1]:Set(#l.events)
    j.tiles[2]:Set(nz)
    j.tiles[3]:Set(nb)
    j.tiles[4]:Set(fmtDate(l.created))
    for _, e in ipairs(l.events) do
        if j.filter == "all" or e.k == j.filter then
            local dk = dayKey(e.t)
            if dk ~= lastDay then
                lastDay = dk
                data[#data + 1] = { icon = false, title = "|cff888888" .. relDay(e.t) .. "|r" }
            end
            local text = e.x or ""
            if e.link then text = text .. " " .. e.link end
            data[#data + 1] = { icon = e.i, title = text, sub = date("%H:%M", e.t), color = col(e.k), link = e.link }
        end
    end
    j.list:SetData(data)
end

function Life.RefreshRecords(r, l)
    local data = {}
    for _, key in ipairs(REC_ORDER) do
        local def, rec = REC[key], l.rec[key]
        data[#data + 1] = { icon = def[4], title = L[def[1]] .. (rec and rec.x and rec.x.label and ("  |cff888888" .. rec.x.label .. "|r") or ""),
            sub = rec and ((L["aufgestellt am %s"]):format(fmtDate(rec.t)) .. (rec.prev and ("  ·  " .. L["vorher"] .. " " .. def[3](rec.prev)) or "")) or L["noch kein Wert"],
            val = rec and def[3](rec.v) or "–" }
    end
    local runs = {}
    for key, rec in pairs(l.rec) do if key:find("^run:") then runs[#runs + 1] = rec end end
    table.sort(runs, function(a, b) return (a.x and a.x.name or "") < (b.x and b.x.name or "") end)
    for _, rec in ipairs(runs) do
        data[#data + 1] = { icon = "Interface\\Icons\\INV_Misc_Key_03", title = rec.x and rec.x.label or "?",
            sub = (L["aufgestellt am %s"]):format(fmtDate(rec.t)) .. (rec.prev and ("  ·  " .. L["vorher"] .. " " .. fmtDur(rec.prev)) or ""), val = fmtDur(rec.v) }
    end
    r.list:SetData(data)
end

function Life.RefreshDungeons(d, l)
    local by, order = {}, {}
    local bosses, deaths, loot = 0, 0, 0
    for _, r in ipairs(l.runs) do
        local s = by[r.key]
        if not s then s = { name = r.name, key = r.key, n = 0, dur = 0, durN = 0, deaths = 0, bosses = 0, loot = 0, mates = {} } by[r.key] = s order[#order + 1] = s end
        s.n = s.n + 1
        s.last = math.max(s.last or 0, r.start)
        if r.done and r.dur then s.dur = s.dur + r.dur s.durN = s.durN + 1 s.best = math.min(s.best or 1e9, r.dur) end
        s.deaths = s.deaths + (r.deaths or 0)
        s.bosses = s.bosses + (r.bosses or 0)
        s.loot = s.loot + #(r.loot or {})
        for n in pairs(r.party or {}) do s.mates[n] = (s.mates[n] or 0) + 1 end
        bosses, deaths, loot = bosses + (r.bosses or 0), deaths + (r.deaths or 0), loot + #(r.loot or {})
    end
    d.tiles[1]:Set(#l.runs)
    d.tiles[2]:Set(bosses)
    d.tiles[3]:Set(deaths)
    d.tiles[4]:Set(loot)
    if l.cur then
        d.cur:SetText((L["Laeuft gerade: %s - %s, %d Bosse, %d Tode"]):format(l.cur.name, fmtDur(now() - l.cur.start), l.cur.bosses or 0, l.cur.deaths or 0))
    else d.cur:SetText("") end
    table.sort(order, function(a, b) return a.n > b.n end)
    local data = {}
    for _, s in ipairs(order) do
        local mate, mn
        for n, c in pairs(s.mates) do if not mn or c > mn then mate, mn = n, c end end
        local parts = { (L["%d Laeufe"]):format(s.n) }
        if s.best then parts[#parts + 1] = L["Bestzeit"] .. " " .. fmtDur(s.best) parts[#parts + 1] = L["Schnitt"] .. " " .. fmtDur(s.dur / s.durN) end
        parts[#parts + 1] = (L["%d Bosse"]):format(s.bosses)
        parts[#parts + 1] = (L["%d Tode"]):format(s.deaths)
        parts[#parts + 1] = (L["%d Beute"]):format(s.loot)
        local tip = { s.name, " " }
        if mate then tip[#tip + 1] = (L["Haeufigster Mitspieler: %s (%dx)"]):format(ns.displayName and ns.displayName(mate) or mate, mn) end
        local key = s.key
        local okD, dd = pcall(function() return ns.Dungeons and ns.Dungeons.Get(key) end)
        if okD and dd and ns.Dungeons and ns.Dungeons.WantedLoot then
            local okW, w = pcall(ns.Dungeons.WantedLoot, dd)
            if okW and #w > 0 then tip[#tip + 1] = (L["%d Items aus der Wunschliste droppen hier"]):format(#w) end
        end
        data[#data + 1] = { icon = "Interface\\Icons\\INV_Misc_Key_03", title = s.name, sub = table.concat(parts, "  ·  "),
            val = relDay(s.last), tip = tip }
    end
    d.list:SetData(data)
end

function Life.RefreshMates(m, l)
    local q = (m.search:GetText() or ""):lower()
    local data = {}
    for n, x in pairs(l.mates) do
        if q == "" or n:lower():find(q, 1, true) or (x.note or ""):lower():find(q, 1, true) then
            local hex = x.class and ns.classHex and ns.classHex(x.class) or "ffffff"
            local name = ns.displayName and ns.displayName(n) or n
            local cls = x.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[x.class]) or ""
            local oc = ns.Contacts and ns.Contacts.Get(n)
            local sub = (L["%d gemeinsame Laeufe"]):format(x.runs or 0) .. "  ·  " .. L["zuletzt"] .. ": " .. (x.lastName or "?")
            if x.note and x.note ~= "" then sub = sub .. "  ·  |cffffd100" .. x.note .. "|r" end
            data[#data + 1] = {
                icon = x.class and ("Interface\\Icons\\ClassIcon_" .. x.class:sub(1, 1) .. x.class:sub(2):lower()) or nil,
                title = "|cff" .. hex .. name .. "|r  |cff888888" .. cls .. (x.level and (" " .. x.level) or "") .. (x.guild and ("  <" .. x.guild .. ">") or "") .. "|r"
                    .. (oc and ("  " .. ns.Contacts.LOGO) or ""),
                sub = sub, val = relDay(x.last or 0), runs = x.runs or 0, last = x.last or 0,
                tip = oc and { name, "|cff66db9e" .. ns.Contacts.TipLine(oc) .. "|r", L["Linksklick: Notiz"], L["Rechtsklick: Fluestern / Einladen / Entfernen"] }
                    or { name, L["Linksklick: Notiz"], L["Rechtsklick: Fluestern / Einladen / Entfernen"] },
                click = function(btn, row)
                    if btn == "RightButton" then
                        K.ShowMenu(row, {
                            { text = L["Fluestern"], fn = function() ChatFrame_SendTell(n) end },
                            { text = L["Einladen"], fn = function() if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(n) elseif InviteUnit then InviteUnit(n) end end },
                            { text = L["Entfernen"], fn = function() l.mates[n] = nil refresh() end },
                        })
                    else
                        ask((L["Notiz zu %s"]):format(name), x.note or "", function(t) x.note = t ~= "" and t:sub(1, 120) or nil refresh() end)
                    end
                end,
            }
        end
    end
    table.sort(data, function(a, b) if a.runs ~= b.runs then return a.runs > b.runs end return a.last > b.last end)
    m.list:SetData(data)
end

function Life.RefreshDeaths(t, l)
    local total = l.stats.deaths or #l.deaths
    local k, pots = {}, 0
    for _, e in ipairs(l.deaths) do
        if e.killer then k[e.killer] = (k[e.killer] or 0) + 1 end
        if e.pot or e.hs then pots = pots + 1 end
    end
    local nem, nn
    for n, c in pairs(k) do if not nn or c > nn then nem, nn = n, c end end
    t.tiles[1]:Set(total)
    t.tiles[2]:Set(nem or "–", nn and ("x" .. nn) or nil)
    t.tiles[3]:Set(pots, #l.deaths > 0 and ("/ " .. #l.deaths) or nil)
    t.tiles[4]:Set(fmtLong(l.stats.noDeathAcc or 0))
    local data = {}
    for _, e in ipairs(l.deaths) do
        local head = (e.killer or L["Unbekannt"]) .. (e.klvl and e.klvl > 0 and ("  |cff888888" .. L["Stufe"] .. " " .. e.klvl .. (e.elite and " Elite" or "") .. "|r") or "")
        local parts = { e.inst or e.zone or "" }
        if e.dur then parts[#parts + 1] = L["Kampf"] .. " " .. fmtDur(e.dur) end
        parts[#parts + 1] = (e.group or 0) > 1 and (L["in Gruppe"]) or L["allein"]
        local tips = {}
        for _, tk in ipairs(e.tips or {}) do tips[#tips + 1] = Life.TipText(tk) end
        local sub = table.concat(parts, "  ·  ")
        if #tips > 0 then sub = sub .. "  ·  |cffffb347" .. table.concat(tips, ", ") .. "|r" end
        data[#data + 1] = { icon = "Interface\\Icons\\Spell_Shadow_DeathScream", title = head, sub = sub,
            val = relDay(e.t) .. " " .. date("%H:%M", e.t), tip = #tips > 0 and { L["Moegliche Ursachen"], unpack(tips) } or nil }
    end
    t.list:SetData(data)
end

function Life.RefreshGold(g, l)
    local days = l.gold.days
    local function sum(n)
        local inc, out, byIn, byOut = 0, 0, {}, {}
        for i = 0, math.min(n, 3650) - 1 do
            local d = days[dayKey(now() - i * DAY)]
            if d then
                for c, v in pairs(d.inc) do inc = inc + v byIn[c] = (byIn[c] or 0) + v end
                for c, v in pairs(d.out) do out = out + v byOut[c] = (byOut[c] or 0) + v end
            end
        end
        return inc, out, byIn, byOut
    end
    local function netTile(tile, n)
        local inc, out = sum(n)
        tile:Set(plain(inc - out), (inc - out) < 0 and "-" or "+")
        tile.tip = { L["Einnahmen"] .. ": " .. plain(inc), L["Ausgaben"] .. ": " .. plain(out) }
    end
    netTile(g.tiles[1], 1)
    netTile(g.tiles[2], 7)
    netTile(g.tiles[3], 30)
    g.tiles[4]:Set(plain(l.stats.goldIn or 0))
    local n = g.range == 9999 and 3650 or g.range
    local inc, out, byIn, byOut = sum(n)
    local function rows(by, total, sign)
        local d = {}
        for c, v in pairs(by) do
            local cat = CAT[c] or CAT.other
            d[#d + 1] = { icon = cat.icon, title = L[cat.text], sub = total > 0 and (("%d%%"):format(v / total * 100)) or "", val = money(v), v = v }
        end
        table.sort(d, function(a, b) return a.v > b.v end)
        return d
    end
    local outRows = rows(byOut, out)
    if #l.gold.big > 0 then
        outRows[#outRows + 1] = { icon = false, title = "|cff888888" .. L["Groesste Ausgaben"] .. "|r" }
        for i = 1, math.min(8, #l.gold.big) do
            local b = l.gold.big[i]
            local cat = CAT[b.c] or CAT.other
            outRows[#outRows + 1] = { icon = cat.icon, title = L[cat.text] .. (b.z ~= "" and (" - " .. b.z) or ""), sub = fmtDate(b.t), val = money(b.v) }
        end
    end
    g.inc:SetData(rows(byIn, inc))
    g.out:SetData(outRows)
    g.h1:SetCount(plain(inc))
    g.h2:SetCount(plain(out))
    -- Goldverlauf (Besitz) der letzten 30 Tage als kleine Balken
    local vals, max = {}, 1
    local last
    for i = 29, 0, -1 do
        local v = l.gold.hist[dayKey(now() - i * DAY)] or last
        last = v
        vals[#vals + 1] = v or 0
        max = math.max(max, v or 0)
    end
    local sp = g.spark
    local bw = math.floor(sp:GetWidth() / 30)
    for i, v in ipairs(vals) do
        local b = sp.bars[i]
        if not b then b = sp:CreateTexture(nil, "ARTWORK") sp.bars[i] = b end
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
        b:SetSize(math.max(1, bw - 2), math.max(1, 28 * v / max))
        b:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], i == #vals and 1 or 0.55)
    end
end

-- Ziel aus Eingabe
function Life.AddFromInput(kind, text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local num = tonumber(text:match("(%d+)%s*$"))
    if kind == "level" then
        if not num then return end
        Life.AddGoal({ kind = "level", arg = num, text = (L["Stufe %d erreichen"]):format(num) })
    elseif kind == "gold" then
        if not num then return end
        Life.AddGoal({ kind = "gold", arg = num, text = (L["%d Gold besitzen"]):format(num) })
    elseif kind == "prof" then
        local name = text:gsub("%s*%d+%s*$", "")
        Life.AddGoal({ kind = "prof", prof = name, arg = num or 300, text = ("%s %d"):format(name, num or 300) })
    elseif kind == "item" then
        local id = tonumber(text:match("item:(%d+)"))
        local label = text:match("|h%[(.-)%]|h") or text:gsub("%s*%d+%s*$", "")
        if not id and ns.ItemSearch and ns.ItemSearch.ExactID then id = ns.ItemSearch.ExactID(label) end
        local qty = (not text:match("%]|h|r%s*$") and num) or (text:match("|r%s*(%d+)%s*$") and tonumber(text:match("|r%s*(%d+)%s*$"))) or 1
        if id and qty > 1000 then qty = 1 end
        Life.AddGoal({ kind = id and "item" or "free", item = id, arg = qty, text = (qty > 1 and (qty .. "x ") or "") .. label })
    elseif kind == "run" then
        local name = text:gsub("%s*%d+%s*$", "")
        local d = ns.Dungeons and ns.Dungeons.Match and ns.Dungeons.Match(name)
        if not d then Life.AddGoal({ kind = "free", text = text }) return end
        local dn = (ns.lang == "de" and (d.nameDE or d.de)) or d.name
        Life.AddGoal({ kind = "run", dkey = d.key, arg = num or 1, text = (L["%s %dx laufen"]):format(dn, num or 1) })
    else
        Life.AddGoal({ kind = "free", text = text })
    end
end

function Life.RefreshGoals(z, l)
    local data = {}
    local open, done = {}, {}
    for _, g in ipairs(l.goals) do if g.done then done[#done + 1] = g else open[#open + 1] = g end end
    table.sort(done, function(a, b) return (a.doneT or 0) > (b.doneT or 0) end)
    local function row(g)
        local cur, max = Life.GoalProgress(g)
        local val = g.done and ("|cff66db9e" .. L["geschafft"] .. "|r") or (g.kind ~= "free" and (math.min(cur, max) .. " / " .. max) or "")
        return { icon = g.done and "Interface\\RaidFrame\\ReadyCheck-Ready" or (g.item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(g.item)) or "Interface\\Icons\\Achievement_General",
            title = g.done and ("|cff888888" .. g.text .. "|r") or g.text,
            sub = g.done and ((L["erreicht am %s"]):format(fmtDate(g.doneT))) or ((L["angelegt am %s"]):format(fmtDate(g.t)) .. (g.kind == "free" and ("  ·  " .. L["Klick: abhaken"]) or "")),
            val = val, tip = { g.text, L["Linksklick: abhaken / zurueck"], L["Rechtsklick: loeschen"] },
            click = function(btn)
                if btn == "RightButton" then
                    for i, x in ipairs(l.goals) do if x == g then table.remove(l.goals, i) break end end
                    refresh()
                elseif g.done then Life.CompleteGoal(g, true)
                elseif g.kind == "free" then Life.CompleteGoal(g) end
            end }
    end
    for _, g in ipairs(open) do data[#data + 1] = row(g) end
    if #done > 0 then
        data[#data + 1] = { icon = false, title = "|cff888888" .. (L["Erreicht (%d)"]):format(#done) .. "|r" }
        for _, g in ipairs(done) do data[#data + 1] = row(g) end
    end
    z.list:SetData(data)
end

function Life.RefreshTodo(w, l)
    local list = Life.Suggestions(w.budget)
    local data = {}
    for _, s in ipairs(list) do
        data[#data + 1] = { icon = s.icon, title = s.title, sub = s.sub, val = "~" .. (s.min >= 60 and (("%dh"):format(s.min / 60)) or (s.min .. " min")),
            click = s.page and function() ns.ShowPage(s.page) end or nil }
    end
    w.info:SetText((L["Stufe %d · %d Vorschlaege"]):format(UnitLevel("player") or 0, #data))
    w.list:SetData(data)
end

function Life.RefreshYear(y, l)
    local b = Life.Yearbook()
    local _, classFile = UnitClass("player")
    local cr, cg, cb = ns.classColor(ns.safe and ns.safe(classFile) or classFile)
    cr, cg, cb = cr or 0.7, cg or 0.7, cb or 0.7
    local yr = date("%Y")
    y.kicker:SetText((L["Jahrbuch %s"]):format(yr))
    y.name:SetText(b.name or "?")
    y.cls:SetText((L["Stufe %d %s"]):format(b.level or 0, b.className or ""))
    y.cls:SetTextColor(cr, cg, cb)
    local days = b.created and math.max(1, math.floor((now() - b.created) / DAY) + 1) or nil
    y.since:SetText(b.created and ((L["Mit Oasis seit %s"]):format(fmtDate(b.created)) .. "  ·  " .. (L["%d Tage"]):format(days)) or "")
    y.ring:SetVertexColor(cr, cg, cb, 0.55)
    if SetPortraitTexture then pcall(SetPortraitTexture, y.portrait, "player") end
    y.timeV:SetText((b.played or 0) > 0 and fmtLong(b.played) or "–")
    y.timeL:SetText(l.played and L["/played gesamt"] or L["Spielzeit mit Oasis"])
    -- Zahlen: 0 leise in grau, Gold mit Muenzsymbolen (0 Gold = "–")
    local function n(v)
        v = tonumber(v) or 0
        if v <= 0 then return "|cff6b6b70" .. "0" .. "|r" end
        return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)
    end
    local function gold(c)
        c = tonumber(c) or 0
        if c <= 0 then return "|cff6b6b70–|r" end
        return money(c)
    end
    local V = { kills = n(b.kills), bosses = n(b.bosses), deaths = n(b.deaths), runs = n(b.runs), quests = n(b.quests),
        zones = n(b.zones), goldIn = gold(b.goldIn), goldOut = gold(b.goldOut), recs = n(b.recs), goals = n(b.goals) }
    for k, t in pairs(y.tiles) do t.v:SetText(V[k] or "") end
    -- Highlights: Text statt Zahl, leer = freundlich in grau
    local none = "|cff6b6b70" .. L["noch keiner"] .. "|r"
    local HLV = {
        fav = { b.fav, b.favN and (L["%d Laeufe"]):format(b.favN) },
        nem = { b.nem, b.nemN and (L["%d Tode"]):format(b.nemN) },
        buddy = { b.buddy and (ns.displayName and ns.displayName(b.buddy) or b.buddy), b.buddyN and (L["%d Laeufe"]):format(b.buddyN) },
    }
    for _, c in ipairs(y.hl) do
        local d = HLV[c.key] or {}
        c.v:SetText(d[1] or none)
        c.n:SetText(d[1] and d[2] or "")
    end
    y.share:SetEnabled(IsInGuild() and true or false)
    if y.Layout then y.Layout() end
end

-- Bereichs-Einstellungen
if ns.AddPageSettings then
    ns.AddPageSettings("life", function(det, y)
        local t1 = K.Toggle(det, L["Hinweis bei neuem persoenlichen Rekord"], function() return S().lifeRecToast ~= false end, function(v) S().lifeRecToast = v end)
        t1:SetPoint("TOPLEFT", 14, y)
        t1:SetWidth(600)
        y = y - 30
        local t2 = K.Toggle(det, L["Tod-Analyse nach jedem Tod als Hinweis"], function() return S().lifeDeathToast ~= false end, function(v) S().lifeDeathToast = v end)
        t2:SetPoint("TOPLEFT", 14, y)
        t2:SetWidth(600)
        y = y - 30
        local b = K.Button(det, L["Reise-Eintraege leeren"], 170, 24, "ghost", function()
            local l = db()
            if l then l.events = {} refresh() end
        end)
        b:SetPoint("TOPLEFT", 14, y - 4)
        return y - 40
    end)
end

-- /oa weg
ns.slash = ns.slash or {}
ns.slash["weg"] = function() Life.Open("journey") end
end)

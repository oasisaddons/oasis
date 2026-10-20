-- Oasis: Oasis-Rang - eigene Gilden-Erfahrung, unabhaengig vom Spiel-Level
-- XP nur fuer Gemeinsames und was der Gilde dient (zusammen spielen, helfen, Raid, Berufe, Gemeinschaft) - siehe GUILD_XP;
-- Termine, Deathroll, Bosse, taegliches Einloggen ...). Jeder Zaehler bringt mit abnehmendem Ertrag
-- (log2), damit Dauerspringen nicht alles ueberholt; dazu Boni fuer Abzeichen-Stufen und Gilden-Titel.
-- Neue XP steigen als "+XP" im Bild auf, ein Rangaufstieg kommt mit Fanfare.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Rank = {}
ns.Rank = Rank

-- Gewicht je Abzeichen-Kategorie: Miteinander zaehlt am meisten
local WEIGHT = { zusammen = 1.6, helfen = 1.6, raid = 1.5, handel = 1.1, zeit = 1.0, stimmung = 1.0,
    glueck = 0.8, welt = 0.8, unfug = 0.5, insta = 0 }   -- Oasigram (Posts, Likes, Follower) gibt keine XP

-- Schutz gegen Ausnutzen: pro Tag zaehlt jeder Zaehler nur bis zu einer Grenze fuer die XP
-- (die Abzeichen selbst zaehlen weiter alles). Minuten-Zaehler: bis 8 Stunden am Tag.
local CAP = {
    chat = 30, jumps = 100, hugs = 10, slaps = 5, pokes = 5, dances = 5, laughs = 10, lols = 10, gz = 10,
    greetings = 10, goodnights = 5, thanks = 10, rolls = 10, whispers = 20, links = 10, votes = 10,
    pollsCreated = 2, eventsCreated = 2, lfgStarted = 3, wantsPosted = 3, ordersPlaced = 3, tips = 3,
    campfires = 3, drPlays = 15, drWins = 3, drLosses = 15, bigWins = 5, emotesReceived = 10, chickens = 5,
    drama = 5, mounts = 20, hearth = 10, eats = 10, drinks = 10, taxis = 20, duels = 10, duelWins = 10,
    trades = 10, mails = 10, signups = 5, joined = 5, groupsFilled = 5, crafted = 10, helped = 5,
    groupMin = 240, carryMin = 180, playMin = 300, swimMin = 60, afkMin = 30, kills = 400, loots = 300,
    quests = 60, questsGroup = 40, gathers = 150, fish = 150, deaths = 20, groupDeaths = 20,
}
local DEFAULT_CAP = 50
local UNCAPPED = { goldCopper = true, repairCopper = true, bankCopper = true }
function Rank.CountForXP(stat, n)
    n = tonumber(n) or 1
    if n <= 0 then return end
    ns.db.xpStats = ns.db.xpStats or {}
    local allowed = n
    if not UNCAPPED[stat] then
        local day = date("%Y%m%d")
        local D = ns.db.xpDay
        if not D or D.day ~= day then D = { day = day, c = {} } ns.db.xpDay = D end
        local cap = CAP[stat] or DEFAULT_CAP
        allowed = math.max(0, math.min(n, cap - (D.c[stat] or 0)))
        D.c[stat] = (D.c[stat] or 0) + allowed
    end
    if allowed > 0 then ns.db.xpStats[stat] = (ns.db.xpStats[stat] or 0) + allowed end
end
local TIER_BONUS = { 40, 120, 300 }
local TITLE_BONUS = 250
-- nur Titel fuer Gemeinsames/Gildendienliches (keine reinen Glueck-/Solo-Titel)
local TITLE_XP = { first10 = true, first20 = true, first30 = true, first40 = true, first50 = true, first60 = true, platzhirsch = true, topcrafter = true,
    dicemonth = true, saint = true, heart = true }

-- 100 Raenge: 20 Rangstufen mit je 5 Unterstufen (I-V), z.B. "Karawanenfuehrer III"
Rank.MAX = 100
Rank.NAMES = {
    "Newcomer", "Sand runner", "Desert wanderer", "Well finder", "Oasis keeper",
    "Camel whisperer", "Caravan leader", "Dune rider", "Scorpion tamer", "Sandstorm tamer",
    "Spring warden", "Star reader", "Mirage hunter", "Palm lord", "Sun warrior",
    "Desert king", "Oasis master", "Keeper of the spring", "Legend of the oasis", "Heart of Oasis",
}
local ROMAN = { "I", "II", "III", "IV", "V" }

-- Rahmen: alle 10 Raenge ein neuer, ab Smaragd leuchtend, ab Amethyst doppelt, ab Rubin mit Funken
Rank.FRAMES = {
    { name = "Wooden frame", color = { 0.62, 0.43, 0.25 }, width = 2 },
    { name = "Bronze frame", color = { 0.85, 0.53, 0.27 }, width = 2 },
    { name = "Silver frame", color = { 0.80, 0.83, 0.90 }, width = 2 },
    { name = "Gold frame", color = { 1.00, 0.80, 0.25 }, width = 3, gems = true },
    { name = "Emerald frame", color = { 0.30, 0.88, 0.50 }, width = 3, gems = true, glow = true },
    { name = "Sapphire frame", color = { 0.35, 0.58, 1.00 }, width = 3, gems = true, glow = true },
    { name = "Amethyst frame", color = { 0.72, 0.42, 1.00 }, width = 3, gems = true, glow = true, double = true },
    { name = "Ruby frame", color = { 1.00, 0.25, 0.32 }, width = 3, gems = true, glow = true, double = true, sparks = 1 },
    { name = "Diamond frame", color = { 0.78, 0.96, 1.00 }, width = 3, gems = true, glow = true, double = true, sparks = 2 },
    { name = "Legendary frame", color = { 1.00, 0.55, 0.10 }, width = 4, gems = true, glow = true, double = true, sparks = 3 },
    { name = "Heart of Oasis", color = { 1.00, 0.30, 0.50 }, width = 4, gems = true, glow = true, double = true, sparks = 4, cycle = true },
}
function Rank.FrameIndex(level)
    level = math.max(1, math.min(Rank.MAX, level or 1))
    return level >= Rank.MAX and #Rank.FRAMES or (math.floor(level / 10) + 1)
end
function Rank.Frame(level)
    level = math.max(1, math.min(Rank.MAX, level or 1))
    return Rank.FRAMES[level >= Rank.MAX and #Rank.FRAMES or (math.floor(level / 10) + 1)]
end

-- XP fuer den Schritt von Stufe l auf l+1: steigt immer staerker an (Rang 10 nach ~3 Tagen,
-- Rang 20 nach ~2 Wochen, Rang 100 erst nach gut zwei Jahren aktiven Spielens)
local function stepXP(l) local k = l - 1 return math.floor(150 + 45 * k + 1.8 * k * k) end
Rank.StepXP = stepXP
function Rank.LevelFor(xp)
    local l, need = 1, stepXP(1)
    while xp >= need and l < Rank.MAX do
        xp = xp - need
        l = l + 1
        need = stepXP(l)
    end
    return l, xp, need   -- Stufe, XP in der Stufe, XP fuer die naechste
end
function Rank.Title(level)
    level = math.max(1, math.min(Rank.MAX, level or 1))
    local tier = math.floor((level - 1) / 5) + 1
    return L[Rank.NAMES[tier]] .. " " .. ROMAN[(level - 1) % 5 + 1]
end

-- Zeit-Zaehler geben deutlich weniger (zu schnelle Raenge nur durchs Online-Sein)
local STAT_MULT = { groupMin = 0.35, carryMin = 0.3, playMin = 0.4, afkMin = 0, swimMin = 0.3 }
-- Ab V3: XP nur noch fuer Gemeinsames und was der Gilde dient (Gewicht je Zaehler); alles andere 0
local GUILD_XP = {
    -- zusammen spielen
    bossCrew = 1.6, carryMin = 1.6, dungeonRuns = 1.6, eventsCreated = 1.6, groupMin = 1.6, groupsFilled = 1.6,
    joined = 1.6, questsGroup = 1.6, signups = 1.6, lfgStarted = 1.0,
    -- helfen
    bandageGuild = 1.6, bankGold = 1.6, campfires = 1.6, castsOnGuild = 1.6, crafted = 1.6, helped = 1.6,
    mails = 1.0, rez = 1.6, tips = 1.6, trades = 1.2,
    -- Raid
    bossWins = 1.5, firstDown = 1.5, lastStanding = 1.0,
    -- Berufe (dienen der Gilde)
    profMax = 1.2, crafts = 1.1,
    -- Gemeinschaft
    gz = 0.8, welcomed = 0.8, greetings = 0.6, thanks = 0.6, votes = 0.6, pollsCreated = 0.8,
    -- Deathroll: Spielen gibt nichts, nur ein Sieg ein winziges bisschen (hoechstens 3 am Tag zaehlen)
    drWins = 0.1,
}
Rank.GUILD_XP = GUILD_XP
-- Gesamt-XP aus den (accountweiten) Zaehlern
local function total(useMult, guildOnly)
    local B = ns.Badges
    if not (B and B.accountStats and B.LIST) then return 0 end
    local ok, s = pcall(B.accountStats)
    if not ok or type(s) ~= "table" then return 0 end
    -- erster Start mit dem Schutz: bisherigen Stand uebernehmen
    if not ns.db.xpBase then
        ns.db.xpBase = {}
        for k, v in pairs(s) do if type(v) == "number" then ns.db.xpBase[k] = v end end
    end
    local base, tracked = ns.db.xpBase, ns.db.xpStats or {}
    local xp = 0
    for _, b in ipairs(B.LIST) do
        local v = s[b.stat] or 0
        -- ueber Badges.Add gezaehlte Werte nur bis zur Tagesgrenze (Tage, Gebiete, Level usw. bleiben wie sie sind)
        if tracked[b.stat] ~= nil or (base[b.stat] ~= nil and b.stat ~= "level" and b.stat ~= "profMax") then
            v = math.min(v, (base[b.stat] or 0) + (tracked[b.stat] or 0))
        end
        local t1 = b.tiers and b.tiers[1] or 1
        if v > 0 and b.stat ~= "level" then
            local w = (guildOnly and (GUILD_XP[b.stat] or 0) or (WEIGHT[b.cat] or 1)) * ((useMult and STAT_MULT[b.stat]) or 1)
            if w > 0 then
                xp = xp + 100 * w * (math.log(1 + v / t1) / math.log(2))
                for i, need in ipairs(b.tiers or {}) do if v >= need then xp = xp + TIER_BONUS[i] end end
            end
        end
    end
    -- Gilden-Titel, die man gerade haelt
    if B.UniqueHolders then
        local me = ns.Alts and ns.Alts.MyMain() or ns.me()
        local ok2, h = pcall(B.UniqueHolders)
        if ok2 and type(h) == "table" then
            -- nur Titel, die man nicht durch Spammen holen kann (keine Spruenge/Chat/Umarmungen)
            for id, holder in pairs(h) do
                if TITLE_XP[id] and (holder == me or ns.isMe(holder)) then xp = xp + TITLE_BONUS end
            end
        end
    end
    return math.floor(xp + (ns.db.rankBonus or 0))
end
function Rank.Total()
    -- einmalig umstellen: bisherigen Stand behalten (Ausgleich in rankBonus), ab jetzt langsamer
    if not ns.db.xpV2 and ns.Badges and ns.Badges.accountStats then
        local old, new = total(false), total(true)
        if old > 0 then
            ns.db.rankBonus = (ns.db.rankBonus or 0) + math.max(0, old - new)
            ns.db.xpV2 = true
        end
    end
    -- V3: nur noch Gemeinsames/Gildendienliches zaehlt; bisherigen Stand behalten (kein Rang geht verloren)
    if ns.db.xpV2 and not ns.db.xpV3 and ns.Badges and ns.Badges.accountStats then
        local old, new = total(true, false), total(true, true)
        if old > 0 then
            ns.db.rankBonus = (ns.db.rankBonus or 0) + math.max(0, old - new)
            ns.db.xpV3 = true
        end
    end
    if ns.db.xpV3 then return total(true, true) end
    return total(ns.db.xpV2 and true or false)
end

-- 0.6.436: Rang-Neustart (nur Entwickler, einmalig): bisheriger Stand wird als Sockel abgezogen -> zurueck auf Rang 1
local rawTotal = Rank.Total
function Rank.Total()
    local t = rawTotal() or 0
    if not ns.db.rankResetV1 and ns.IsDev and ns.IsDev() then
        ns.db.rankResetV1 = true
        ns.db.rankBase = t
        ns.db.settings.rankTest = nil
    end
    return math.max(0, t - (ns.db.rankBase or 0))
end
-- Stand fuer die Anzeige
function Rank.Mine(real)
    local xp = ns.db.rank and ns.db.rank.xp or Rank.Total()
    -- 0.6.433: Test-Rang (nur Entwickler, /oa testrang N) - nur Anzeige und Freischaltungen, nie an die Gilde
    local tr = not real and ns.IsDev and ns.IsDev() and tonumber(ns.db.settings.rankTest)
    if tr and tr >= 1 and Rank.XPFor then xp = Rank.XPFor(tr) end
    local lvl, into, need = Rank.LevelFor(xp)
    return { xp = xp, level = lvl, into = into, need = need, title = Rank.Title(lvl), frame = Rank.Frame(lvl) }
end
-- fuer das Profil (an die Gilde): Stufe + XP
function Rank.ProfileFields(p)
    local m = Rank.Mine(true)
    p.orl, p.orx = m.level, m.xp
end
-- Stufe eines anderen Mitglieds (aus seinem Profil)
-- XP, die fuer Stufe l insgesamt noetig ist
function Rank.XPFor(level)
    local xp = 0
    for l = 1, math.max(1, level) - 1 do xp = xp + stepXP(l) end
    return xp
end

-- Plausibilitaet: die Raenge anderer kommen aus deren eigenem Profil und liessen sich faelschen.
-- Jeder Client prueft deshalb selbst: hoechstens MAXDAY XP pro Tag seit dem letzten geprueften Stand,
-- und insgesamt hoechstens START + MAXDAY x Tage seit Einfuehrung des Oasis-Rangs. Was darueber liegt,
-- wird gedeckelt angezeigt und als "ungeprueft" markiert.
local MAXDAY = 3000                 -- grosszuegig: normale Spieler schaffen etwa ein Drittel davon
local START = 6000                  -- Stand, den jemand zum Start schon haben durfte
local LAUNCH = time({ year = 2026, month = 9, day = 29, hour = 0 })
function Rank.Verified(name)
    local p = ns.db.members[name]
    if not p then return nil end
    local rx = tonumber(p.orx) or (tonumber(p.orl) and Rank.XPFor(tonumber(p.orl))) or nil
    if not rx then return nil end
    local now = ns.now()
    local global = START + MAXDAY * math.max(0, (now - LAUNCH) / 86400)
    ns.db.rankSeen = ns.db.rankSeen or {}
    local key = ns.short(name)
    local rec = ns.db.rankSeen[key]
    if not rec then
        rec = { xp = math.min(rx, global), ts = now }
        ns.db.rankSeen[key] = rec
    end
    local days = math.max(1, (now - (rec.ts or now)) / 86400)
    local allowed = math.min(global, (rec.xp or 0) + MAXDAY * days)
    if rx <= allowed then
        if rx > (rec.xp or 0) then rec.xp, rec.ts = rx, now end
        return rx, true
    end
    return math.floor(allowed), false
end
-- Oasis-Rang eines Mitglieds -> Stufe, geprueft?
function Rank.Of(name)
    if ns.isMe(name) then return Rank.Mine().level, true end
    local xp, ok = Rank.Verified(name)
    if not xp then return nil end
    return (Rank.LevelFor(xp)), ok
end

------------------------------------------------------------------------
-- "+XP" im Bild (wie Kampftext) + Rangaufstieg
------------------------------------------------------------------------
-- 0.5.568: Fenster wiederverwenden (vorher je "+XP" ein neues Fenster - WoW gibt Fenster nie frei)
local floatPool = {}
local function floatText(text, big)
    if ns.db.settings.xpFloat == false then return end
    local f = table.remove(floatPool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(400, 40)
        f:SetFrameStrata("HIGH")
        f.fs = f:CreateFontString(nil, "OVERLAY")
        f.fs:SetPoint("CENTER")
        f.fs:SetTextColor(1, 0.82, 0.29)
        f:SetScript("OnHide", function(self) if not self.pooled then self.pooled = true floatPool[#floatPool + 1] = self end end)
    end
    f.pooled = nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    local fs = f.fs
    K.SetFontSafe(fs, K.FontPath and K.FontPath(nil, K.FONT_HEAD) or K.FONT, big and 30 or 20, "OUTLINE", K.FONT)
    fs:SetText(text)
    f.use = (f.use or 0) + 1
    local use = f.use
    f:SetAlpha(0)
    f:Show()
    K.Tween(f, big and 2.8 or 1.8, function(p)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 140 + p * (big and 40 or 60))
        f:SetAlpha(p < 0.15 and p / 0.15 or (p > 0.7 and (1 - p) / 0.3 or 1))
    end, function() if f.use == use then f:Hide() end end)
    ns.After(big and 3.2 or 2.2, function() if f.use == use then f:Hide() end end)
end
Rank.Float = floatText

local pending, flushAt = 0, nil
function Rank.Update(silent, noDouble)
    if not ns.db then return end
    ns.db.rank = ns.db.rank or {}
    local R = ns.db.rank
    local xp = Rank.Total()
    local old = R.xp
    -- XP-Wochenende: neue XP zaehlen doppelt (als Bonus gespeichert)
    if old and not silent and not noDouble and xp > old and ns.Rewards and ns.Rewards.DoubleUntil() then
        local extra = xp - old
        ns.db.rankBonus = (ns.db.rankBonus or 0) + extra
        xp = xp + extra
    end
    R.xp = xp
    ns.Fire("RANK")
    if old == nil or silent then return end
    local gain = xp - old
    if gain <= 0 then return end
    pending = pending + gain
    -- kleine Gewinne sammeln, damit es nicht flackert
    if not flushAt then
        flushAt = GetTime() + 1.5
        ns.After(1.5, function()
            flushAt = nil
            if pending >= 1 then floatText(("+%d %s"):format(math.floor(pending + 0.5), L["Oasis XP"])) end
            pending = 0
        end)
    end
    local oldLvl, newLvl = Rank.LevelFor(old), Rank.LevelFor(xp)
    if newLvl > oldLvl then
        local title = Rank.Title(newLvl)
        ns.After(1.8, function()
            floatText((L["Oasis rank %d!"]):format(newLvl), true)
            -- eigene Rang-Fanfare (Belohnung), sonst der normale Abzeichen-Klang
            -- Aufstiegs-Sound erst ab Rang 10, davor der normale Hinweis-Klang
            if ns.Sound then ns.Sound.Next(newLvl >= 10 and "rankup" or "badge") end
            K.Toast((L["Oasis rank %d!"]):format(newLvl), title, C.amber, function() ns.ShowPage("rank") end)
            -- neu freigeschaltete Belohnungen melden
            if ns.Rewards then
                for _, x in ipairs(ns.Rewards.LIST) do
                    if x.lvl > oldLvl and x.lvl <= newLvl then
                        ns.After(3, function() K.Toast(L["Reward unlocked!"], L[x.name], C.mint, function() ns.ShowPage("rank") end) end)
                    end
                end
            end
            -- neuer Profilrahmen freigeschaltet?
            local fr = Rank.Frame(newLvl)
            if fr ~= Rank.Frame(oldLvl) then
                ns.After(1.5, function()
                    K.Toast(L["New profile frame!"], L[fr.name], fr.color, function() ns.ShowPage("home") end)
                end)
            end
            if ns.Chronicle then
                ns.Chronicle.Add("level", ("rank-%s-%d"):format(ns.short(ns.me()), newLvl), "reached Oasis rank %s", { newLvl }, { rank = true })
            end
            if ns.Radar then ns.Radar.SendHello() end
        end)
    end
    ns.RefreshPage("home")
end

-- nach jedem Zaehler-Plus neu rechnen (gebuendelt)
local queued
local function queue()
    if queued then return end
    queued = true
    -- Leistung (0.6.481): bis zu 17 ms je Neuberechnung - seltener (5 s gebuendelt) und nie im Kampf
    local function run()
        if ns.inCombat and ns.inCombat() then ns.After(3, run) return end
        queued = false
        pcall(Rank.Update)
        if ns.Rewards then pcall(ns.Rewards.CheckTasks) end
    end
    ns.After(5, run)
end
ns.Listen("LOGIN", function()
    ns.After(15, function()
        if ns.Badges and ns.Badges.Add and not Rank.hooked then
            Rank.hooked = true
            local add = ns.Badges.Add
            ns.Badges.Add = function(stat, n, ...)
                add(stat, n, ...)
                pcall(Rank.CountForXP, stat, n or 1)
                queue()
            end
        end
        -- erster Start: aktuellen Stand still uebernehmen (kein Feuerwerk fuer alte Taten)
        pcall(Rank.Update, ns.db.rank == nil or ns.db.rank.xp == nil)
    end)
    ns.Every(60, queue)
end)

ns.slash.rang = function()
    local m = Rank.Mine()
    ns.print((L["Oasis rank %d"]):format(m.level) .. " - " .. m.title .. "  (" .. m.into .. " / " .. m.need .. " XP)")
end
ns.slash.xptest = function() floatText("+25 " .. L["Oasis XP"]) end
-- 0.6.433: /oa testrang N (aus mit /oa testrang) - Rang zum Testen der Freischaltungen, echter Stand bleibt
ns.slash.testrang = function(a)
    if not (ns.IsDev and ns.IsDev()) then return end
    local n = tonumber(a)
    ns.db.settings.rankTest = (n and n >= 1) and math.floor(n) or nil
    ns.print(ns.db.settings.rankTest and ("Test-Rang: " .. ns.db.settings.rankTest .. "  (aus: /oa testrang)") or "Test-Rang aus - echter Rang gilt wieder.")
    if ns.Rank and ns.Rank.Update then pcall(ns.Rank.Update, false, true) end
end

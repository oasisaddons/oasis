-- Oasis: Belohnungen fuer den Oasis-Rang, Wochenaufgaben, XP-Wochenende, XP-Leiste am Fenster
-- Belohnungen: Designs (Akzentfarben), Rang-Fanfaren, Deathroll-Wuerfel, Rang-Juwel + Schimmer im Gildenchat,
-- besondere (animierte) Gilden-Emojis.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local RW = {}
ns.Rewards = RW
local function S() return ns.db.settings end
local function myLevel() return ns.Rank and ns.Rank.Mine().level or 1 end

------------------------------------------------------------------------
-- Belohnungsleiste
------------------------------------------------------------------------
-- alle 2 Raenge eine Belohnung (50 Stueck)
local function E(n) return "Besondere Emojis " .. n end
RW.LIST = {
    { lvl = 2, kind = "bg", key = "abend", name = "Hintergrund: Sonnenuntergang", desc = "Neuer Hintergrund fuer deine Oasigram-Posts" },
    { lvl = 4, kind = "dice", key = "gold", name = "Goldene Wuerfel", desc = "Deathroll-Wuerfel in Gold", color = { 1, 0.82, 0.3 } },
    { lvl = 8, kind = "emoji", key = "emoji8", name = E("I"), desc = "Die ersten animierten Gilden-Emojis" },
    { lvl = 10, kind = "sound", key = "wow_levelup", name = "Fanfare: Stufenaufstieg", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 12, kind = "theme", key = "smaragd", name = "Design: Smaragd-Oase", desc = "Gruene Akzentfarbe fuer ganz Oasis", hex = "3fdc8a" },
    { lvl = 14, kind = "bg", key = "gewitter", name = "Hintergrund: Gewitter", desc = "Mit Blitzen - fuer deine Oasigram-Posts" },
    { lvl = 16, kind = "emoji", key = "emoji16", name = E("II"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 18, kind = "dice", key = "fire", name = "Feuerwuerfel", desc = "Deathroll-Wuerfel in Flammenfarbe", color = { 1, 0.45, 0.15 } },
    { lvl = 20, kind = "sound", key = "wow_mission", name = "Fanfare: Triumph", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 22, kind = "bg", key = "polar", name = "Hintergrund: Polarlicht", desc = "Schimmerndes Nordlicht fuer deine Posts" },
    { lvl = 24, kind = "theme", key = "sunset", name = "Design: Sonnenuntergang", desc = "Orange Akzentfarbe fuer ganz Oasis", hex = "ff7a3d" },
    { lvl = 26, kind = "emoji", key = "emoji26", name = E("III"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 28, kind = "dice", key = "frost", name = "Frostwuerfel", desc = "Deathroll-Wuerfel in Eisblau", color = { 0.55, 0.8, 1 } },
    { lvl = 30, kind = "chat", key = "chatgem", name = "Rang-Juwel im Gildenchat", desc = "Vor deinem Namen leuchtet dein Rang-Juwel" },
    { lvl = 32, kind = "bg", key = "vulkan", name = "Hintergrund: Vulkan", desc = "Flackernde Glut fuer deine Posts" },
    { lvl = 34, kind = "sound", key = "horn", name = "Fanfare: Kriegshorn", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 36, kind = "emoji", key = "emoji36", name = E("IV"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 38, kind = "dice", key = "poison", name = "Giftwuerfel", desc = "Deathroll-Wuerfel in Giftgruen", color = { 0.5, 1, 0.4 } },
    { lvl = 40, kind = "theme", key = "gold", name = "Design: Gold", desc = "Goldene Akzentfarbe fuer ganz Oasis", hex = "ffc83d" },
    { lvl = 42, kind = "bg", key = "sterne", name = "Hintergrund: Sternennacht", desc = "Funkelnde Sterne fuer deine Posts" },
    { lvl = 44, kind = "sound", key = "trommel", name = "Fanfare: Kriegstrommel", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 46, kind = "theme", key = "ozean", name = "Design: Ozean", desc = "Tiefblaue Akzentfarbe fuer ganz Oasis", hex = "3aa0ff" },
    { lvl = 48, kind = "emoji", key = "emoji48", name = E("V"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 50, kind = "dice", key = "arcane", name = "Arkanwuerfel", desc = "Deathroll-Wuerfel in Arkanviolett", color = { 0.8, 0.5, 1 } },
    { lvl = 52, kind = "bg", key = "tiefsee", name = "Hintergrund: Tiefsee", desc = "Blaue Tiefe fuer deine Posts" },
    { lvl = 54, kind = "sound", key = "glocke", name = "Fanfare: Glocke", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 56, kind = "theme", key = "rose", name = "Design: Rosengarten", desc = "Rosa Akzentfarbe fuer ganz Oasis", hex = "ff6fb1" },
    { lvl = 58, kind = "dice", key = "blood", name = "Blutwuerfel", desc = "Deathroll-Wuerfel in Blutrot", color = { 0.8, 0.08, 0.12 } },
    { lvl = 60, kind = "theme", key = "night", name = "Design: Nachtwueste", desc = "Nachtblaue Akzentfarbe fuer ganz Oasis", hex = "6f63ff" },
    { lvl = 62, kind = "emoji", key = "emoji62", name = E("VI"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 64, kind = "bg", key = "kristall", name = "Hintergrund: Kristallhoehle", desc = "Violettes Kristalllicht fuer deine Posts" },
    { lvl = 66, kind = "sound", key = "wow_quest", name = "Fanfare: Quest geschafft", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 68, kind = "dice", key = "nature", name = "Naturwuerfel", desc = "Deathroll-Wuerfel in Blattgruen", color = { 0.55, 0.85, 0.25 } },
    { lvl = 70, kind = "chat", key = "chatshine", name = "Schimmernder Name", desc = "Dein Name glaenzt im Gildenchat in deiner Rahmenfarbe" },
    { lvl = 72, kind = "bg", key = "gold", name = "Hintergrund: Goldstaub", desc = "Glitzernder Goldstaub fuer deine Posts" },
    { lvl = 74, kind = "dice", key = "shadow", name = "Schattenwuerfel", desc = "Deathroll-Wuerfel aus Schatten", color = { 0.5, 0.35, 0.7 } },
    { lvl = 76, kind = "emoji", key = "emoji76", name = E("VII"), desc = "Weitere animierte Gilden-Emojis" },
    { lvl = 78, kind = "theme", key = "lava", name = "Design: Lava", desc = "Gluehend rote Akzentfarbe fuer ganz Oasis", hex = "ff3d1f" },
    { lvl = 80, kind = "theme", key = "diamond", name = "Design: Diamant", desc = "Eisklare Akzentfarbe fuer ganz Oasis", hex = "8fe6ff" },
    { lvl = 82, kind = "sound", key = "wow_ready", name = "Fanfare: Bereitschaft", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 84, kind = "bg", key = "astral", name = "Hintergrund: Astralebene", desc = "Schillernde Astralebene fuer deine Posts" },
    { lvl = 86, kind = "dice", key = "holy", name = "Heilige Wuerfel", desc = "Deathroll-Wuerfel aus Licht", color = { 1, 0.95, 0.7 } },
    { lvl = 88, kind = "theme", key = "jade", name = "Design: Jade", desc = "Jadegruene Akzentfarbe fuer ganz Oasis", hex = "2fd1b0" },
    { lvl = 90, kind = "dice", key = "void", name = "Leerenwuerfel", desc = "Deathroll-Wuerfel aus der Leere", color = { 0.4, 0.25, 0.95 } },
    { lvl = 92, kind = "emoji", key = "emoji92", name = E("VIII"), desc = "Die seltensten Gilden-Emojis" },
    { lvl = 94, kind = "theme", key = "silber", name = "Design: Mondsilber", desc = "Silberne Akzentfarbe fuer ganz Oasis", hex = "c9d4e8" },
    { lvl = 96, kind = "bg", key = "legende", name = "Hintergrund: Legende", desc = "Der Hintergrund der Legenden" },
    { lvl = 98, kind = "sound", key = "erfolg", name = "Fanfare: Oasis-Triumph", desc = "Neuer Klang beim Rangaufstieg" },
    { lvl = 100, kind = "theme", key = "heart", name = "Design: Herz der Oasis", desc = "Die Farbe der Legenden", hex = "ff4f8a" },
}
RW.byKey = {}
for _, r in ipairs(RW.LIST) do RW.byKey[r.kind .. ":" .. r.key] = r end
function RW.Unlocked(kind, key, level)
    local r = RW.byKey[kind .. ":" .. key]
    return r ~= nil and (level or myLevel()) >= r.lvl
end
local KIND_ICON = { brachland = "chat", emoji = "chat", dice = "deathroll", sound = "settings", theme = "home", chat = "chat", bg = "insta" }
local KIND_NAME = { brachland = "Spass", emoji = "Emojis", dice = "Wuerfel", sound = "Fanfare", theme = "Design", chat = "Gildenchat", bg = "Oasigram" }

-- Ausruesten (nur freigeschaltet)
function RW.Equip(r)
    if not r or myLevel() < r.lvl then return end
    local s = S()
    if r.kind == "theme" then
        s.accent = r.hex      -- nur die Farbe; das Design (settings.theme) bleibt
        if ns.Admin and ns.Admin.ApplyAccent then ns.Admin.ApplyAccent(r.hex) end
    elseif r.kind == "sound" then
        s.rankSound = r.key
        if ns.Sound then ns.Sound.PlayChoice(r.key) end
    elseif r.kind == "dice" then
        s.diceDesign = r.key
    end
    ns.RefreshPage("rank")
end
function RW.IsEquipped(r)
    local s = S()
    if r.kind == "theme" then return s.accent == r.hex end
    if r.kind == "sound" then return s.rankSound == r.key end
    if r.kind == "dice" then return s.diceDesign == r.key end
    return myLevel() >= r.lvl
end
function RW.Unequip(kind)
    local s = S()
    if kind == "theme" then s.accent = "" if ns.Admin then ns.Admin.ApplyAccent("") end
    elseif kind == "sound" then s.rankSound = nil
    elseif kind == "dice" then s.diceDesign = nil end
    ns.RefreshPage("rank")
end
-- Farbe der eigenen Deathroll-Wuerfel (nil = normal)
function RW.DiceColor()
    local k = ns.db and S().diceDesign
    local r = k and RW.byKey["dice:" .. k]
    return (r and myLevel() >= r.lvl) and r.color or nil
end
function RW.RankSound()
    local k = ns.db and S().rankSound
    return (k and RW.Unlocked("sound", k)) and k or nil
end

------------------------------------------------------------------------
-- Gildenchat: Rang-Juwel ab 30, schimmernder Name ab 70 (fuer alle mit Rang, auch andere)
------------------------------------------------------------------------
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
ns.GuildOption({ page = "insta", key = "rwGem", default = true, label = "Rang-Juwel im Gildenchat",
    desc = "Zeigt ab Oasis-Rang 30 ein Juwel und ab Rang 70 einen schimmernden Namen im Oasis-Gildenchat" })
function RW.ChatName(name, plain)
    if ns.GuildOpt("rwGem") == false then return nil end
    local lvl = ns.Rank and ns.Rank.Of(name)
    if not lvl or lvl < 30 then return nil end
    local c = ns.Rank.Frame(lvl).color
    local gem = ("|T%s:10:10:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(MASK, c[1] * 255, c[2] * 255, c[3] * 255)
    if lvl < 70 then return gem .. plain end
    -- Schimmer: Buchstaben laufen von der Rahmenfarbe zu Weiss und zurueck
    local chars = {}
    for ch in ns.short(name):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    local out = {}
    for i, ch in ipairs(chars) do
        local t = 0.5 + 0.5 * math.sin(i / math.max(1, #chars) * math.pi)
        out[i] = ("|cff%02x%02x%02x"):format((c[1] + (1 - c[1]) * t * 0.7) * 255, (c[2] + (1 - c[2]) * t * 0.7) * 255, (c[3] + (1 - c[3]) * t * 0.7) * 255) .. ch .. "|r"
    end
    return gem .. table.concat(out)
end

------------------------------------------------------------------------
-- Besondere Emojis: animierte Gilden-Emojis werden nach Rang freigeschaltet
------------------------------------------------------------------------
local EMOJI_STEPS = { 10, 18, 26, 34, 44, 56, 70, 85 }   -- 0.6.439
local STATIC_STEPS = { 2, 4, 7, 10, 14 }   -- 0.6.439: ab Rang 2   -- 0.6.417: auch normale Gilden-Emojis erst ab Rang (ohne Rang gesperrt)
local emojiLock
function RW.EmojiLevel(e)
    -- 0.6.532: eigenes Gilden-Emoji -> Stufe aus der Freigabe der Gildenleitung (nicht aus den Dateien)
    local own = type(e) == "table" and type(e[1]) == "string" and e[1]:match("^x\\(.+)$")
    if own and ns.MediaPack and not ns.MediaPack.publishing then
        local lk = ns.MediaPack.EmojiLock(own)
        if lk then return lk end
    end
    -- eigenes Emoji einer Gilde mit festem Rang ("@20" im Dateinamen, Oasis_Emojis)
    if type(e) == "table" and e.lvl then return e.lvl end
    if not emojiLock then
        emojiLock = {}
        -- 0.6.442: alle Gilden-Emojis gleichmaessig auf Rang 2 bis 100 (normale zuerst, animierte danach)
        local stat, anim = {}, {}
        for _, cat in ipairs(ns.Emoji and ns.Emoji.CATS or {}) do
            if cat.custom then for _, x in ipairs(cat.items or {}) do
                if x.n and x.n > 1 then anim[#anim + 1] = x else stat[#stat + 1] = x end
            end end
        end
        local function byCode(a, b) return tostring(a[2]) < tostring(b[2]) end
        table.sort(stat, byCode) table.sort(anim, byCode)
        local all = {}
        for _, x in ipairs(stat) do all[#all + 1] = x end
        for _, x in ipairs(anim) do all[#all + 1] = x end
        local n = #all
        for i, x in ipairs(all) do emojiLock[x] = (n > 1) and (2 + math.floor((i - 1) * 98 / (n - 1) + 0.5)) or 2 end
    end
    return emojiLock[e]
end

------------------------------------------------------------------------
-- XP-Bonus (Wochenaufgaben) und XP-Wochenende
------------------------------------------------------------------------
function RW.GiveXP(n, reason)
    ns.db.rankBonus = (ns.db.rankBonus or 0) + n
    if ns.Rank then
        ns.Rank.Float(("+%d %s"):format(n, L["Oasis-XP"]) .. (reason and ("  |cffffffff" .. reason .. "|r") or ""))
        ns.After(0.5, function() ns.Rank.Update(false, true) end)
    end
end
-- Doppel-XP: von der Gildenleitung gesetzt (Zeitpunkt, bis wann)
function RW.DoubleUntil()
    local cfg = ns.Admin and ns.Admin.Cfg()
    local t = cfg and tonumber(cfg.xp2) or 0
    local s = cfg and tonumber(cfg.xp2s) or 0
    return (t > ns.now() and s <= ns.now()) and t or nil
end
-- geplantes Double XP (Start in der Zukunft): Start, Ende
function RW.DoublePlanned()
    local cfg = ns.Admin and ns.Admin.Cfg()
    local s = cfg and tonumber(cfg.xp2s) or 0
    local t = cfg and tonumber(cfg.xp2) or 0
    if s > ns.now() and t > s then return s, t end
end

------------------------------------------------------------------------
-- Wochenaufgaben: 3 pro Woche, fuer die ganze Gilde gleich
------------------------------------------------------------------------
RW.POOL = {
    { stat = "groupMin", need = 60, text = "60 Minuten mit Gildenmitgliedern in einer Gruppe" },
    { stat = "crafted", need = 1, text = "Einen Auftrag fuer jemanden herstellen" },
    { stat = "signups", need = 1, text = "Einem Gildentermin zusagen" },
    { stat = "drPlays", need = 3, text = "Deathroll gegen 3 verschiedene Leute spielen" },
    { stat = "questsGroup", need = 5, text = "5 Quests zusammen mit der Gilde abgeben" },
    { stat = "joined", need = 1, text = "Einer Gruppe der Gilde beitreten" },
    { stat = "lfgStarted", need = 1, text = "Eine Gruppensuche starten, bei der ein Gildenmitglied beitritt" },
    { stat = "hugs", need = 5, text = "5 verschiedene Gildenmitglieder umarmen oder bejubeln" },
    { stat = "chat", need = 20, text = "20 Nachrichten im Gildenchat" },
    { stat = "bossCrew", need = 1, text = "Einen Boss mit der Gilde legen" },
    { stat = "daysOnline", need = 3, text = "An 3 Tagen online sein" },
    { stat = "gz", need = 3, text = "3 verschiedenen Leuten gratulieren" },
    { stat = "dungeonRuns", need = 1, text = "Einen Dungeon-Boss mit 3+ Gildenmitgliedern legen" },
    { stat = "rez", need = 1, text = "Ein Gildenmitglied wiederbeleben" },
    { stat = "helped", need = 1, text = "Jemandem ein gesuchtes Item geben" },
    { stat = "trades", need = 2, text = "Mit 2 verschiedenen Gildenmitgliedern handeln" },
}
local TASK_XP, ALL_XP = 150, 200
local function weekKey() return date("%Y-%W") end
local function stats()
    local ok, s = pcall(ns.Badges.accountStats)
    return ok and s or {}
end
function RW.Week()
    local W = ns.db.weekly
    local key = weekKey()
    if not W or W.week ~= key then
        -- gleiche Aufgaben fuer alle: Auswahl aus der Kalenderwoche
        local seed = tonumber(ns.hash(key), 16) or 1
        local picks, used = {}, {}
        local i = 0
        while #picks < 3 and i < 50 do
            local idx = (seed + i * 7919) % #RW.POOL + 1
            if not used[idx] then used[idx] = true picks[#picks + 1] = idx end
            i = i + 1
        end
        local s = stats()
        local base = {}
        for _, idx in ipairs(picks) do base[idx] = s[RW.POOL[idx].stat] or 0 end
        W = { week = key, picks = picks, base = base, done = {} }
        ns.db.weekly = W
    end
    return W
end
-- Gegen Ausnutzen: diese Aufgaben zaehlen nur ueber RW.Credit (strenge Regeln, jede Person nur einmal pro Woche)
RW.STRICT = {
    dungeonRuns = true, gz = true, rez = true, trades = true, hugs = true, chat = true, drPlays = true,
    joined = true, lfgStarted = true, groupMin = true, questsGroup = true, signups = true, crafted = true,
}
function RW.Credit(stat, partner, n)
    if not (ns.db and stat) then return end
    local W = RW.Week()
    W.prog = W.prog or {}
    W.seen = W.seen or {}
    if partner and partner ~= "" then
        local key = stat .. "|" .. tostring(partner):lower()
        if W.seen[key] then return end
        W.seen[key] = true
    end
    W.prog[stat] = (W.prog[stat] or 0) + (n or 1)
    RW.CheckTasks()
end
function RW.Tasks()
    local W = RW.Week()
    local s = stats()
    local out = {}
    for _, idx in ipairs(W.picks) do
        local t = RW.POOL[idx]
        local have
        if RW.STRICT[t.stat] then have = (W.prog and W.prog[t.stat]) or 0
        else have = math.max(0, (s[t.stat] or 0) - (W.base[idx] or 0)) end
        out[#out + 1] = { idx = idx, text = L[t.text], have = math.min(have, t.need), need = t.need, done = W.done[idx] and true or false }
    end
    return out
end
function RW.CheckTasks()
    if not (ns.db and ns.Badges and ns.Badges.accountStats) then return end
    local W = RW.Week()
    local all = true
    for _, t in ipairs(RW.Tasks()) do
        if t.have >= t.need and not W.done[t.idx] then
            W.done[t.idx] = true
            if ns.Sound then ns.Sound.Next("badge") end
            K.Toast(L["Wochenaufgabe geschafft!"], t.text .. "  |cffffd24a+" .. TASK_XP .. " XP|r", C.amber, function() ns.ShowPage("rank") end)
            RW.GiveXP(TASK_XP, L["Wochenaufgabe"])
        end
        if not W.done[t.idx] then all = false end
    end
    if all and not W.allDone then
        W.allDone = true
        ns.After(2, function()
            K.Toast(L["Alle Wochenaufgaben geschafft!"], "|cffffd24a+" .. ALL_XP .. " XP " .. L["Bonus"] .. "|r", C.amber)
            RW.GiveXP(ALL_XP, L["Wochenbonus"])
        end)
    end
end
function RW.WeekSummary()
    local ok, W = pcall(RW.Week)
    if not ok or not W then return nil end
    local n = 0
    for _ in pairs(W.done or {}) do n = n + 1 end
    return W.week .. ":" .. n
end
function RW.WeekLeft()
    -- bis Montag 0 Uhr
    local t = date("*t", ns.now())
    local wd = (t.wday + 5) % 7   -- 0 = Montag
    local secs = (7 - wd) * 86400 - (t.hour * 3600 + t.min * 60 + t.sec)
    return math.max(0, secs)
end

------------------------------------------------------------------------
-- XP-Leiste unten am Hauptfenster (immer sichtbar)
------------------------------------------------------------------------
function RW.AttachBar(main, sidebar)
    -- 0.6.187: Ornament-Stil in einer Zeile - goldene Raute als Emblem, "Rang N" + Titel, Balken mit Goldkante,
    -- Rauten an den Enden und am aktuellen Stand, rechts die XP
    local b = CreateFrame("Button", nil, main)
    b:SetPoint("BOTTOMLEFT", (sidebar or 200) + 16, 6)
    b:SetPoint("BOTTOMRIGHT", -16, 6)
    b:SetHeight(26)
    b:SetFrameLevel(main:GetFrameLevel() + 20)
    local GOLD = { 1, 0.78, 0.36 }
    local H = 8
    local function diamond(parent, size, c, layer, sub)
        local d = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2)
        d:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        d:SetSize(size, size)
        if d.SetRotation then pcall(d.SetRotation, d, math.pi / 4) end
        return d
    end
    -- Emblem links: Raute mit dunklem Kern und weichem Schein
    b.emGlow = b:CreateTexture(nil, "BACKGROUND")
    b.emGlow:SetTexture(ns.MEDIA .. "softglow") b.emGlow:SetBlendMode("ADD")
    b.emGlow:SetVertexColor(1, 0.7, 0.3) b.emGlow:SetSize(40, 30) b.emGlow:SetAlpha(0.5)
    b.em = diamond(b, 14, GOLD, "ARTWORK", 1)
    b.em:SetPoint("LEFT", 6, 0)
    b.emIn = diamond(b, 8, { 0.14, 0.08, 0.03 }, "ARTWORK", 2)
    b.emIn:SetPoint("CENTER", b.em)
    b.emDot = diamond(b, 3, { 1, 0.95, 0.75 }, "ARTWORK", 3)
    b.emDot:SetPoint("CENTER", b.em)
    b.emGlow:SetPoint("CENTER", b.em)
    -- 0.6.421: Rang-Abzeichen mit Zahl statt der Raute
    if K.RankEmblem then
        b.badge = K.RankEmblem(b, 26)
        b.badge:SetPoint("CENTER", b.em)
        b.em:SetAlpha(0) b.emIn:SetAlpha(0) b.emDot:SetAlpha(0) b.emGlow:SetAlpha(0)
    end
    b.lbl = K.Text(b, 11, GOLD)
    b.lbl:SetPoint("LEFT", b.em, "RIGHT", 12, 0)
    b.title = K.Text(b, 11, { 0.86, 0.86, 0.88 })
    b.title:SetPoint("LEFT", b.lbl, "RIGHT", 8, 0)
    b.text = K.Text(b, 10, { 0.8, 0.8, 0.82 }, "RIGHT")
    b.text:SetPoint("RIGHT", -6, 0)
    b.x2 = K.Text(b, 10, C.amber, "RIGHT")
    b.x2:SetPoint("RIGHT", b.text, "LEFT", -14, 0)
    -- Balkenbereich zwischen Titel und XP
    local area = CreateFrame("Frame", nil, b)
    area:SetHeight(H + 4)
    area:SetPoint("LEFT", b.title, "RIGHT", 22, 0)
    area:SetPoint("RIGHT", b.text, "LEFT", -22, 0)
    b.area = area
    area.bg = area:CreateTexture(nil, "BACKGROUND")
    area.bg:SetAllPoints() area.bg:SetColorTexture(0.03, 0.03, 0.035, 0.9)
    K.Border(area, { GOLD[1], GOLD[2], GOLD[3], 0.45 })
    b.endL = diamond(b, 7, GOLD) b.endL:SetPoint("CENTER", area, "LEFT", -7, 0)
    b.endR = diamond(b, 7, GOLD) b.endR:SetPoint("CENTER", area, "RIGHT", 7, 0)
    b.fill = area:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 2, -2) b.fill:SetPoint("BOTTOMLEFT", 2, 2)
    b.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    if not (b.fill.SetGradient and CreateColor and pcall(b.fill.SetGradient, b.fill, "HORIZONTAL", CreateColor(0.7, 0.42, 0.1, 1), CreateColor(1, 0.86, 0.42, 1))) then
        b.fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    b.fill:SetWidth(1)
    b.track = area.bg
    -- Glanz innerhalb der Fuellung
    b.clip = CreateFrame("Frame", nil, area)
    b.clip:SetClipsChildren(true)
    b.clip:SetPoint("TOPLEFT", 2, -2) b.clip:SetPoint("BOTTOMLEFT", 2, 2)
    b.clip:SetWidth(1)
    b.shine = b.clip:CreateTexture(nil, "OVERLAY")
    b.shine:SetTexture(ns.MEDIA .. "shine") b.shine:SetBlendMode("ADD")
    b.shine:SetSize(70, H) b.shine:SetVertexColor(1, 0.95, 0.75) b.shine:SetAlpha(0.25)
    -- Raute am aktuellen Stand
    b.glow = area:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(ns.MEDIA .. "softglow") b.glow:SetBlendMode("ADD")
    b.glow:SetSize(30, 22) b.glow:SetVertexColor(1, 0.8, 0.35)
    b.tip = diamond(area, 9, { 1, 0.92, 0.6 }, "OVERLAY", 3)
    b.tipIn = diamond(area, 4, { 0.3, 0.16, 0.04 }, "OVERLAY", 4)
    local function place(x)
        local w = math.max(1, x)
        b.fillX = w
        b.fill:SetWidth(w)
        b.clip:SetWidth(w)
        b.tip:ClearAllPoints() b.tip:SetPoint("CENTER", area, "LEFT", 2 + w, 0)
        b.tipIn:ClearAllPoints() b.tipIn:SetPoint("CENTER", b.tip)
        b.glow:ClearAllPoints() b.glow:SetPoint("CENTER", b.tip)
    end
    b.t = 0
    b:SetScript("OnUpdate", function(self, el)
        if ns.db and ns.db.settings.noAnim then self.shine:Hide() self.glow:SetAlpha(0.6) return end
        self.t = self.t + el
        local fx = self.fillX or 0
        local q = (self.t % 6) / 6
        self.shine:Show()
        self.shine:ClearAllPoints()
        self.shine:SetPoint("LEFT", self.clip, "LEFT", -70 + (fx + 70) * q, 0)
        self.glow:SetAlpha(0.45 + 0.15 * math.sin(self.t * 1.6))
    end)
    local function innerW() local w = area:GetWidth() or 0 return math.max(10, w - 4) end
    area:SetScript("OnSizeChanged", function() if b.pct then place(innerW() * b.pct) end end)
    function b:Update(animate)
        local r = ns.Rank and ns.Rank.Mine()
        if not r then self:Hide() return end
        self.lbl:SetText((L["Rang %d"]):format(r.level))
        if self.badge then self.badge:SetRank(r.level) self.badge:Show() end
        self.title:SetText(r.title or "")
        self.text:SetText(r.into .. " / " .. r.need .. " XP")
        local until2 = RW.DoubleUntil()
        self.x2:SetText(until2 and ("2x XP  ·  " .. L["XP-Wochenende"]) or "")
        local w = innerW()
        local pct = math.min(1, r.into / math.max(1, r.need))
        local from = (self.pct or 0) * w
        self.pct = pct
        local target = w * pct
        if animate and math.abs(from - target) > 1 then
            K.Tween(self.fill, 0.8, function(q) place(from + (target - from) * q) end)
        else
            place(target)
        end
    end
    b:SetScript("OnShow", function(self) self:Update() end)
    b:SetScript("OnEnter", function(self)
        local r = ns.Rank and ns.Rank.Mine()
        if not r then return end
        local lines = { (L["Oasis-Rang %d"]):format(r.level) .. "  -  " .. r.title, (L["%d / %d XP bis zum naechsten Rang"]):format(r.into, r.need) }
        if RW.DoubleUntil() then lines[#lines + 1] = "|cffffd24a" .. L["XP-Wochenende: doppelte Oasis-XP!"] .. "|r" end
        lines[#lines + 1] = "|cff888888" .. L["Klick: Rang, Belohnungen und Wochenaufgaben"] .. "|r"
        K.ShowTip(self, lines)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() ns.ShowPage("rank") end)
    RW.bar = b
    b:Update()
    return b
end
ns.Listen("RANK", function() if RW.bar then RW.bar:Update(true) end end)

------------------------------------------------------------------------
-- Spielerkarte unten am Oasis-Fenster: Portraet im Rang-Rahmen, Stufe, Name + Klasse,
-- Level-Balken (Spiel-XP) und Oasis-Rang-Balken - ersetzt die duenne XP-Leiste
------------------------------------------------------------------------
local function bar(parent, colorA, colorB)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(8)
    b.track = b:CreateTexture(nil, "BACKGROUND")
    b.track:SetAllPoints()
    b.track:SetColorTexture(0, 0, 0, 0.55)
    K.Border(b, { 0.22, 0.22, 0.24, 1 })
    -- Glanz auf der oberen Haelfte
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.shine:SetPoint("TOPLEFT")
    b.shine:SetPoint("TOPRIGHT")
    b.shine:SetHeight(3)
    b.shine:SetColorTexture(1, 1, 1, 0.08)
    -- Zehntel-Striche
    b.ticks = {}
    for i = 1, 9 do
        local t = b:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetColorTexture(0, 0, 0, 0.45)
        t:SetWidth(1)
        t:SetPoint("TOP")
        t:SetPoint("BOTTOM")
        b.ticks[i] = t
    end
    b:SetScript("OnSizeChanged", function(self, w)
        for i, t in ipairs(self.ticks) do t:ClearAllPoints() t:SetPoint("TOPLEFT", self, "TOPLEFT", w * i / 10, 0) t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", w * i / 10, 0) end
    end)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    b.fill:SetWidth(1)
    if not K.Gradient(b.fill, "HORIZONTAL", colorA, colorB) then b.fill:SetColorTexture(colorB[1], colorB[2], colorB[3], 1) end
    b.spark = b:CreateTexture(nil, "OVERLAY")
    b.spark:SetTexture(MASK)
    b.spark:SetSize(14, 14)
    b.spark:SetBlendMode("ADD")
    b.spark:SetVertexColor(1, 0.95, 0.8)
    function b:Set(pct, animate)
        pct = math.max(0, math.min(1, pct or 0))
        local w = self:GetWidth()
        if not w or w < 10 then w = 300 end
        local target = math.max(1, w * pct)
        local from = self.fill:GetWidth() or 1
        local function place(x)
            self.fill:SetWidth(math.max(1, x))
            self.spark:ClearAllPoints()
            self.spark:SetPoint("CENTER", self, "LEFT", math.max(1, x), 0)
            self.spark:SetShown(pct > 0 and pct < 1)
        end
        if animate and math.abs(from - target) > 1 then
            K.Tween(self.fill, 0.8, function(q) place(from + (target - from) * q) end)
        else
            place(target)
        end
    end
    return b
end

function RW.AttachCard(main)
    local c = CreateFrame("Button", nil, main)
    c:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -4)
    c:SetPoint("TOPRIGHT", main, "BOTTOMRIGHT", 0, -4)
    c:SetHeight(88)   -- unten etwas Luft unter dem Rang-Balken
    c.bg = K.Fill(c, C.bg)
    K.Border(c, C.line)
    c.glow = c:CreateTexture(nil, "BORDER")
    c.glow:SetAllPoints()
    if not K.Gradient(c.glow, "HORIZONTAL", { C.accent[1], C.accent[2], C.accent[3], 0.07 }, { 0, 0, 0, 0 }) then c.glow:Hide() end
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.03)

    -- Portraet im Rang-Rahmen + Stufe
    c.rf = K.RankFrame(c, 50, "circle")
    c.rf:SetPoint("CENTER", c, "LEFT", 44, 0)
    c.face = c.rf:CreateTexture(nil, "ARTWORK", nil, 3)
    c.face:SetSize(48, 48)
    c.face:SetPoint("CENTER")
    pcall(c.face.SetMask, c.face, MASK)
    c.lvlBg = c.rf:CreateTexture(nil, "OVERLAY", nil, 5)
    c.lvlBg:SetTexture(MASK)
    c.lvlBg:SetSize(18, 18)
    c.lvlBg:SetPoint("CENTER", c.rf, "CENTER", 18, -18)
    c.lvlBg:SetVertexColor(0.08, 0.08, 0.09)
    c.lvl = c.rf:CreateFontString(nil, "OVERLAY", nil, 7)
    K.SetFontSafe(c.lvl, K.FONT_HEAD, 9, "OUTLINE", K.FONT)
    K.CenterNum(c.lvl, c.lvlBg, "CENTER", 0, 0)

    -- Spalte 1: Name, Klasse, Level-Balken
    c.name = K.Title(c, 15, C.text)
    c.name:SetPoint("TOPLEFT", 92, -8)
    c.class = K.Text(c, 12, C.muted)
    c.class:SetPoint("LEFT", c.name, "RIGHT", 8, 0)
    c.lvlLabel = K.Text(c, 10, C.red)
    c.lvlPct = K.Text(c, 10, C.muted, "RIGHT")
    c.lvlBar = bar(c, { 0.55, 0.08, 0.06, 1 }, { 0.95, 0.18, 0.12, 1 })
    -- Spalte 2: Oasis-Rang + Balken
    c.rankLabel = K.Text(c, 10, C.amber)
    c.rankXP = K.Text(c, 10, C.muted, "RIGHT")
    c.rankBar = bar(c, { 0.85, 0.5, 0.12, 1 }, { 1, 0.82, 0.29, 1 })
    -- rechts: Double XP
    c.x2 = K.Text(c, 11, C.amber, "RIGHT")
    c.x2:SetPoint("TOPRIGHT", -16, -9)
    -- Gildenwappen (von der Gildenleitung gewaehlt), dezent rechts
    c.crest = c:CreateTexture(nil, "ARTWORK")
    c.crest:SetSize(30, 30)
    c.crest:SetPoint("RIGHT", c, "TOPRIGHT", -16, -22)
    c.crest:SetAlpha(0.9)
    c.crest:Hide()
    RW.card = c

    -- beide Balken untereinander ueber die ganze Breite: Level (Spiel-XP) oben, Oasis-Rang darunter
    local function layout()
        local w = c:GetWidth() or 1000
        if w < 100 then w = 1000 end
        local x1, right = 92, 16
        local bw = w - x1 - right
        c.lvlLabel:ClearAllPoints() c.lvlLabel:SetPoint("TOPLEFT", c, "TOPLEFT", x1, -30)
        c.lvlPct:ClearAllPoints() c.lvlPct:SetPoint("TOPRIGHT", c, "TOPRIGHT", -right, -30)
        c.lvlBar:ClearAllPoints() c.lvlBar:SetPoint("TOPLEFT", c, "TOPLEFT", x1, -43) c.lvlBar:SetWidth(bw)
        c.rankLabel:ClearAllPoints() c.rankLabel:SetPoint("TOPLEFT", c, "TOPLEFT", x1, -54)
        c.rankXP:ClearAllPoints() c.rankXP:SetPoint("TOPRIGHT", c, "TOPRIGHT", -right, -54)
        c.rankBar:ClearAllPoints() c.rankBar:SetPoint("TOPLEFT", c, "TOPLEFT", x1, -67) c.rankBar:SetWidth(bw)
    end
    c:SetScript("OnSizeChanged", function() layout() c:Update() end)

    function c:Update(animate)
        layout()
        pcall(SetPortraitTexture, self.face, "player")
        local r = ns.Rank and ns.Rank.Mine()
        if r then
            self.rf:SetStyle(r.frame, r.level)
            self.rankLabel:SetText(K.Upper((L["Rang %d"]):format(r.level)) .. "  |cffe8b44a" .. r.title .. "|r")
            self.rankXP:SetText(r.into .. " / " .. r.need .. " XP")
            self.rankBar:Set(r.into / math.max(1, r.need), animate)
        end
        local lvl = ns.safe(UnitLevel("player")) or 1
        self.lvl:SetText(lvl)
        local _, classFile = UnitClass("player")
        local cname = ns.safe((UnitClass("player")))
        self.name:SetText(ns.colorName(ns.me() or ns.safe(ns.UnitName("player")) or "?", ns.safe(classFile)))
        self.class:SetText(cname or "")
        local cur, max = ns.safe(UnitXP("player")) or 0, ns.safe(UnitXPMax("player")) or 0
        if max > 0 then
            local pct = cur / max
            self.lvlLabel:SetText(K.Upper((L["Level %d"]):format(lvl)) .. "  |cff888888> " .. (lvl + 1) .. "|r")
            self.lvlPct:SetText(("%s / %s XP  |cff888888·|r  %d %%"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur, BreakUpLargeNumbers and BreakUpLargeNumbers(max) or max, math.floor(pct * 100)))
            self.lvlBar:Set(pct, animate)
        else
            self.lvlLabel:SetText(K.Upper((L["Level %d"]):format(lvl)) .. "  |cffe8b44a" .. L["Hoechststufe"] .. "|r")
            self.lvlPct:SetText("")
            self.lvlBar:Set(1, animate)
        end
        local until2 = RW.DoubleUntil()
        self.x2:SetText(until2 and ("2x XP  ·  " .. (L["noch %d h"]):format(math.ceil((until2 - ns.now()) / 3600))) or "")
    end
    c:SetScript("OnShow", function(self) self:Update() end)
    c:SetScript("OnEnter", function(self)
        local r = ns.Rank and ns.Rank.Mine()
        if not r then return end
        local lines = { (L["Oasis-Rang %d"]):format(r.level) .. "  -  " .. r.title, (L["%d / %d XP bis zum naechsten Rang"]):format(r.into, r.need),
            L["Rahmen:"] .. " " .. K.hex(r.frame.color) .. L[r.frame.name] .. "|r" }
        if RW.DoubleUntil() then lines[#lines + 1] = "|cffffd24a" .. L["XP-Wochenende: doppelte Oasis-XP!"] .. "|r" end
        lines[#lines + 1] = "|cff888888" .. L["Klick: Rang, Belohnungen und Wochenaufgaben"] .. "|r"
        K.ShowTip(self, lines, "ANCHOR_TOP")
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnClick", function() ns.ShowPage("rank") end)
    -- ein-/ausklappen: Lasche rechts oben; zugeklappt bleibt nur die Lasche unter dem Fenster
    local tab = CreateFrame("Button", nil, main)
    tab:SetSize(150, 22)
    tab:SetFrameLevel(c:GetFrameLevel() + 10)
    tab.bg = K.Fill(tab, C.bg)
    tab.glow = tab:CreateTexture(nil, "BORDER")
    tab.glow:SetAllPoints()
    if not K.Gradient(tab.glow, "VERTICAL", { C.amber[1], C.amber[2], C.amber[3], 0 }, { C.amber[1], C.amber[2], C.amber[3], 0.12 }) then tab.glow:Hide() end
    K.Border(tab, C.line)
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetPoint("BOTTOMLEFT", 1, 1) tab.line:SetPoint("BOTTOMRIGHT", -1, 1)
    tab.line:SetHeight(2)
    tab.line:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.8)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetTexture(ns.ICONS and ns.ICONS.insta or nil)
    tab.icon:SetSize(14, 14)
    tab.icon:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
    tab.t = K.Text(tab, 11, C.muted, "LEFT")
    tab.t:SetPoint("CENTER", 9, 0)
    tab.icon:SetPoint("RIGHT", tab.t, "LEFT", -7, 0)
    c.tab = tab
    local function apply()
        local closed = ns.db and ns.db.settings and ns.db.settings.cardClosed
        c:SetShown(not closed)
        tab:ClearAllPoints()
        if closed then
            tab:SetPoint("TOP", main, "BOTTOM", 0, 1)
            tab.line:SetPoint("BOTTOMLEFT", 1, 1) tab.line:SetPoint("BOTTOMRIGHT", -1, 1)
            tab.t:SetText(K.Upper(L["Profil anzeigen"]) .. "  |cffe8b44av|r")
        else
            tab:SetPoint("TOP", c, "BOTTOM", 0, 1)
            tab.t:SetText(K.Upper(L["einklappen"]) .. "  |cffe8b44a^|r")
        end
    end
    tab:SetScript("OnClick", function()
        ns.db.settings.cardClosed = not ns.db.settings.cardClosed or nil
        apply()
        if c:IsShown() then K.FadeIn(c, 0) end
    end)
    tab:SetScript("OnEnter", function(self) self.t:SetTextColor(C.amber[1], C.amber[2], C.amber[3]) end)
    tab:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    if ns.db and ns.db.settings then apply() else ns.Listen("LOGIN", apply) end
    RW.card = c
    c:Update()
    return c
end
ns.Listen("RANK", function() if RW.card then RW.card:Update(true) end end)
ns.On("PLAYER_XP_UPDATE", function() if RW.card and RW.card:IsVisible() then RW.card:Update(true) end end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(0.5, function() if RW.card then RW.card:Update(true) end end) end)


------------------------------------------------------------------------
-- XP-Wochenende (Gildenleitung)
------------------------------------------------------------------------
-- startAt = Zeitpunkt in der Zukunft (geplant) oder nil (sofort)
function RW.StartDouble(hours, startAt)
    if not (ns.Admin and ns.Admin.CanManage()) then return end
    local cfg = {}
    for k, v in pairs(ns.Admin.Cfg()) do cfg[k] = v end
    local from = (startAt and startAt > ns.now()) and startAt or ns.now()
    cfg.xp2s = (startAt and startAt > ns.now()) and startAt or 0
    cfg.xp2 = hours and hours > 0 and (from + hours * 3600) or 0
    ns.Admin.Save(cfg)
    if hours and hours > 0 then
        if cfg.xp2s > 0 then
            ns.Admin.SendNotice(L["XP-Wochenende!"], (L["Doppelte Oasis-XP ab %s fuer %d Stunden!"]):format(ns.fmtWhen(from), hours), true, false)
        else
            ns.Admin.SendNotice(L["XP-Wochenende!"], (L["Doppelte Oasis-XP fuer %d Stunden - viel Spass!"]):format(hours), true, false)
        end
    end
    ns.RefreshPage("admin")
    ns.RefreshPage("rank")
    if RW.bar then RW.bar:Update() end
end

ns.Listen("LOGIN", function()
    ns.After(20, function() pcall(RW.CheckTasks) end)
    ns.Every(60, function() pcall(RW.CheckTasks) if RW.bar then RW.bar:Update() end end)
end)

------------------------------------------------------------------------
-- Seite "Oasis-Rang": Rangkarte, Wochenaufgaben, Belohnungen
------------------------------------------------------------------------
local function panel(parent, title, color)
    local f = K.Panel(parent, C.panel)
    f.head = K.GameHead(f, title, color)
    f.head:SetPoint("TOPLEFT", 12, -12)
    f.head:SetPoint("RIGHT", -12, 0)
    return f
end

ns.RegisterPage({
    key = "rank", title = "Oasis-Rang", order = 7.85,
    visible = function() return false end,   -- steckt jetzt als Reiter im Profil
    sub = "Dein Rang in der Gilde - Belohnungen, Rahmen und Wochenaufgaben",
    build = function(p)
        p:SetScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
        -- Rangkarte
        local card = panel(p, L["Dein Rang"], C.amber)
        card:SetPoint("TOPLEFT", 0, 0)
        card:SetSize(370, 200)
        card.frame = K.RankFrame(card, 72, "circle")
        card.frame:SetPoint("CENTER", card, "TOPLEFT", 64, -100)
        card.face = card.frame:CreateTexture(nil, "OVERLAY", nil, 1)
        card.face:SetSize(72, 72)
        card.face:SetPoint("CENTER")
        card.num = card.frame:CreateFontString(nil, "OVERLAY", nil, 5)
        K.SetFontSafe(card.num, K.FONT_HEAD, 16, "OUTLINE", K.FONT)
        card.num:SetPoint("CENTER", card.frame, "CENTER", 0, -44)
        card.num:Hide()   -- 0.5.588: Rangzahl steht im Sechseck des gemalten Rahmens
        card.num.Show = function() end
        card.title = K.Title(card, 17, C.text)
        card.title:SetPoint("TOPLEFT", 124, -54)
        card.title:SetPoint("RIGHT", -12, 0)
        card.frameName = K.Text(card, 11, C.muted)
        card.frameName:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
        card.track = card:CreateTexture(nil, "ARTWORK")
        card.track:SetPoint("TOPLEFT", 124, -100)
        card.track:SetPoint("RIGHT", -14, 0)
        card.track:SetHeight(6)
        card.track:SetColorTexture(1, 1, 1, 0.07)
        card.fill = card:CreateTexture(nil, "OVERLAY")
        card.fill:SetPoint("TOPLEFT", card.track, "TOPLEFT")
        card.fill:SetHeight(6)
        if not K.Gradient(card.fill, "HORIZONTAL", { 0.85, 0.5, 0.12, 1 }, { 1, 0.82, 0.29, 1 }) then card.fill:SetColorTexture(1, 0.82, 0.29, 1) end
        card.xp = K.Text(card, 11, C.muted)
        card.xp:SetPoint("TOPLEFT", card.track, "BOTTOMLEFT", 0, -6)
        card.total = K.Text(card, 10, C.dim, "RIGHT")
        card.total:SetPoint("TOPRIGHT", card.track, "BOTTOMRIGHT", 0, -6)
        card.next = K.Text(card, 11, C.muted)
        card.next:SetPoint("TOPLEFT", 124, -142)
        card.next:SetPoint("RIGHT", -12, 0)
        card.next:SetWordWrap(true)
        p.card = card

        -- Wochenaufgaben
        local week = panel(p, L["Wochenaufgaben"], C.mint)
        week:SetPoint("TOPLEFT", 0, -210)
        week:SetPoint("BOTTOMLEFT")
        week:SetWidth(370)
        week.left = K.Text(week, 10, C.dim, "RIGHT")
        week.left:SetPoint("TOPRIGHT", -12, -15)
        week.rows = {}
        for i = 1, 3 do
            local r = CreateFrame("Frame", nil, week)
            r:SetHeight(54)
            r:SetPoint("TOPLEFT", 12, -40 - (i - 1) * 60)
            r:SetPoint("RIGHT", -12, 0)
            r.bg = K.Fill(r, C.raised)
            r.check = r:CreateTexture(nil, "ARTWORK")
            r.check:SetSize(18, 18)
            r.check:SetPoint("TOPLEFT", 10, -9)
            r.check:SetTexture(MASK)
            r.text = K.Text(r, 12, C.text)
            r.text:SetPoint("TOPLEFT", 36, -10)
            r.text:SetPoint("RIGHT", -70, 0)
            r.xp = K.Title(r, 11, C.amber, "RIGHT")
            r.xp:SetPoint("TOPRIGHT", -10, -10)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetPoint("BOTTOMLEFT", 36, 12)
            r.track:SetPoint("BOTTOMRIGHT", -60, 12)
            r.track:SetHeight(5)
            r.track:SetColorTexture(1, 1, 1, 0.07)
            r.fill = r:CreateTexture(nil, "OVERLAY")
            r.fill:SetPoint("BOTTOMLEFT", r.track, "BOTTOMLEFT")
            r.fill:SetHeight(5)
            r.fill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 1)
            r.prog = K.Text(r, 10, C.muted, "RIGHT")
            r.prog:SetPoint("BOTTOMRIGHT", -10, 9)
            week.rows[i] = r
        end
        week.bonus = K.Text(week, 11, C.muted)
        week.bonus:SetPoint("TOPLEFT", 12, -226)
        week.bonus:SetPoint("RIGHT", -12, 0)
        week.x2 = K.Text(week, 12, C.amber)
        week.x2:SetPoint("TOPLEFT", 12, -250)
        week.x2:SetPoint("RIGHT", -12, 0)
        p.week = week

        -- Belohnungen
        local rw = panel(p, L["Belohnungen"], C.accent)
        rw:SetPoint("TOPLEFT", 381, 0)
        rw:SetPoint("BOTTOMRIGHT")
        rw.list = K.List(rw, 40, function(l)
            local r = K.Row(l)
            r.lvl = CreateFrame("Frame", nil, r)
            r.lvl:SetSize(36, 30)
            r.lvl:SetPoint("LEFT", 6, 0)
            r.lvl.bg = K.Fill(r.lvl, C.raised)
            r.lvl.top = r.lvl:CreateTexture(nil, "ARTWORK")
            r.lvl.top:SetPoint("TOPLEFT") r.lvl.top:SetPoint("TOPRIGHT") r.lvl.top:SetHeight(2)
            r.lvl.a = K.Text(r.lvl, 8, C.dim, "CENTER")
            r.lvl.a:SetPoint("TOP", 0, -4)
            r.lvl.a:SetText(K.Upper(L["Rang"]))
            r.lvl.n = K.Title(r.lvl, 12, C.text, "CENTER")
            r.lvl.n:SetPoint("BOTTOM", 0, 3)
            r.icon = K.Glyph(r, 16, nil)
            r.icon:SetPoint("LEFT", 52, 0)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("TOPLEFT", 76, -6)
            r.name:SetPoint("RIGHT", -90, 0)
            r.desc = K.Text(r, 10, C.muted)
            r.desc:SetPoint("BOTTOMLEFT", 76, 6)
            r.desc:SetPoint("RIGHT", -90, 0)
            r.state = K.Text(r, 10, C.dim, "RIGHT")
            r.state:SetPoint("RIGHT", -10, 0)
            r:SetScript("OnClick", function(self)
                local x = self.item
                if not x or myLevel() < x.lvl then return end
                if x.kind == "theme" or x.kind == "sound" or x.kind == "dice" then
                    if RW.IsEquipped(x) then RW.Unequip(x.kind) else RW.Equip(x) end
                elseif x.kind == "bg" and ns.Insta and not ns.Insta.SOON then
                    ns.Insta.OpenComposer(false)
                elseif x.kind == "emoji" and ns.Emoji then
                    ns.Emoji.TogglePicker()
                end
            end)
            return r
        end, function(r, x, idx)
            local lvl = myLevel()
            local open = lvl >= x.lvl
            local fc = ns.Rank.Frame(x.lvl).color
            r.lvl.top:SetColorTexture(fc[1], fc[2], fc[3], 1)
            r.lvl.n:SetText(x.lvl)
            r.icon:SetTexture(ns.ICONS[KIND_ICON[x.kind]] or ns.ICONS.badges)
            local ic = open and (x.color or (x.hex and K.FromHex(x.hex)) or C.amber) or C.dim
            r.icon:SetVertexColor(ic[1], ic[2], ic[3])
            r.name:SetText(open and L[x.name] or ("|cff777777" .. L[x.name] .. "|r"))
            local soon = x.kind == "bg" and ns.Insta and ns.Insta.SOON
            r.desc:SetText("|cff888888" .. L[KIND_NAME[x.kind]] .. "  ·  |r" .. L[x.desc] .. (soon and ("  |cffff7fa8(" .. L["kommt bald"] .. ")|r") or ""))
            local equip = x.kind == "theme" or x.kind == "sound" or x.kind == "dice"
            if not open then
                r.state:SetText("|cff666666" .. L["gesperrt"] .. "|r")
            elseif equip and RW.IsEquipped(x) then
                r.state:SetText("|cff66db9e" .. L["AKTIV"] .. "|r")
            elseif equip then
                r.state:SetText("|cffffd24a" .. L["Anlegen"] .. "|r")
            else
                r.state:SetText("|cff66db9e" .. L["frei"] .. "|r")
            end
            r:SetAlpha(open and 1 or 0.7)
            if p.fresh then K.FadeIn(r, math.min(0.8, (idx or 1) * 0.03)) end
        end)
        rw.list:SetPoint("TOPLEFT", 4, -38)
        rw.list:SetPoint("BOTTOMRIGHT", -4, 6)
        p.rw = rw
    end,
    refresh = function(p)
        local fresh = p.fresh
        local r = ns.Rank and ns.Rank.Mine()
        if not r then return end
        local c = p.card
        local st = r.frame
        local key = st.name .. (K.RingTier and K.RingTier(r.level) or "")
        if c.frame.styleName ~= key then c.frame:SetStyle(st, r.level) c.frame.styleName = key end
        if SetPortraitTexture then
            pcall(SetPortraitTexture, c.face, "player")
            if c.face.SetMask and not c.masked then c.masked = pcall(c.face.SetMask, c.face, MASK) end
        end
        c.num:SetText(r.level)
        c.num:SetTextColor(st.color[1], st.color[2], st.color[3])
        c.title:SetText(r.title)
        c.frameName:SetText(K.hex(st.color) .. L[st.name] .. "|r  ·  " .. (L["Oasis-Rang %d"]):format(r.level))
        local w = (c.track:GetWidth() or 0) > 10 and c.track:GetWidth() or 220
        local pct = math.min(1, r.into / math.max(1, r.need))
        if fresh then
            c.fill:SetWidth(1)
            K.Tween(c.fill, 1.1, function(q) c.fill:SetWidth(math.max(1, w * pct * q)) end, nil, 0.2)
        else
            c.fill:SetWidth(math.max(1, w * pct))
        end
        c.xp:SetText((L["%d / %d XP bis zum naechsten Rang"]):format(r.into, r.need))
        c.total:SetText((L["%d XP gesamt"]):format(r.xp))
        -- naechste Belohnung + naechster Rahmen
        local nextR
        for _, x in ipairs(RW.LIST) do if x.lvl > r.level then nextR = x break end end
        local nextF = r.level < 100 and ns.Rank.Frame(math.min(100, (math.floor(r.level / 10) + 1) * 10)) or nil
        local lines = {}
        if nextR then lines[#lines + 1] = (L["Naechste Belohnung: %s (Rang %d)"]):format(L[nextR.name], nextR.lvl) end
        if nextF and nextF ~= st then lines[#lines + 1] = (L["Naechster Rahmen: %s (Rang %d)"]):format(K.hex(nextF.color) .. L[nextF.name] .. "|r", math.min(100, (math.floor(r.level / 10) + 1) * 10)) end
        c.next:SetText(table.concat(lines, "\n"))
        -- Wochenaufgaben
        local tasks = RW.Tasks()
        local left = RW.WeekLeft()
        p.week.left:SetText((L["noch %d Tg %d Std"]):format(math.floor(left / 86400), math.floor(left % 86400 / 3600)))
        local nDone = 0
        for i, row in ipairs(p.week.rows) do
            local t = tasks[i]
            if t then
                row.text:SetText(t.done and ("|cff66db9e" .. t.text .. "|r") or t.text)
                row.xp:SetText("+" .. TASK_XP .. " XP")
                row.prog:SetText(t.have .. " / " .. t.need)
                local cc = t.done and C.mint or C.dim
                row.check:SetVertexColor(cc[1], cc[2], cc[3])
                local tw = (row.track:GetWidth() or 0) > 10 and row.track:GetWidth() or 230
                local tp = math.min(1, t.have / math.max(1, t.need))
                if fresh then
                    row.fill:SetWidth(1)
                    K.Tween(row.fill, 0.9, function(q) row.fill:SetWidth(math.max(1, tw * tp * q)) end, nil, 0.2 + i * 0.1)
                else
                    row.fill:SetWidth(math.max(1, tw * tp))
                end
                if t.done then nDone = nDone + 1 end
                row:Show()
            else
                row:Hide()
            end
        end
        p.week.head:SetCount(nDone .. "/3")
        p.week.bonus:SetText((L["Alle drei geschafft: +%d XP Bonus"]):format(ALL_XP) .. (nDone == 3 and "  |cff66db9e✓|r" or ""))
        local until2 = RW.DoubleUntil()
        p.week.x2:SetText(until2 and ("|cffffd24a" .. L["XP-Wochenende: doppelte Oasis-XP!"] .. "|r  " .. (L["noch %d Std"]):format(math.ceil((until2 - ns.now()) / 3600))) or "")
        p.rw.list:SetData(RW.LIST)
        p.rw.head:SetCount(r.level >= 1 and (function() local n = 0 for _, x in ipairs(RW.LIST) do if r.level >= x.lvl then n = n + 1 end end return n .. "/" .. #RW.LIST end)() or nil)
        if fresh then K.FadeIn(p.card, 0) K.FadeIn(p.week, 0.1) end
        p.fresh = false
    end,
})
ns.slash.belohnungen = function() ns.ShowPage("rank") end


-- Gildenwappen auf der Profilleiste
function RW.UpdateCrest()
    local c = RW.card
    if not c or not c.crest then return end
    local tex, col = ns.Officer and ns.Officer.Crest and ns.Officer.Crest()
    if tex then
        c.crest:SetTexture(tex)
        c.crest:SetVertexColor(col[1], col[2], col[3])
        c.crest:Show()
        c.x2:ClearAllPoints()
        c.x2:SetPoint("RIGHT", c.crest, "LEFT", -10, 0)
    else
        c.crest:Hide()
        c.x2:ClearAllPoints()
        c.x2:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, -9)
    end
end
ns.Listen("LOGIN", function() ns.After(5, RW.UpdateCrest) end)
ns.Listen("STORE", function(coll) if coll == "guildcfg" then ns.After(0.5, RW.UpdateCrest) end end)

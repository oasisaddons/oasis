-- Oasis: Raid-IDs & Freischaltungen der ganzen Gilde
--  * jeder Charakter liest beim Login / UPDATE_INSTANCE_INFO seine Raid-IDs (gebunden, Boss-Fortschritt, Reset)
--    und Freischaltungen/Schluessel (Quests + Gegenstaende) - nur ausserhalb des Kampfes
--  * Daten je Charakter (auch Twinks: jeder Login merkt sich den Stand in OasisDB.chars) gehen an die Gilde
--    -> Store-Sammlung "lockouts", Datensatz-ID "lk-<Charakter>", ueber eigene Nachrichten LKU/LKREQ/LKB/LKACK
--    (die Sammlung steht nicht in Comms RETENTION-Liste, deshalb eigener Versand + eigenes Aufraeumen)
--  * Seite (Gruppe Raid): Raster Mitglieder x Raids, Filter, "Freie Gruppe vorschlagen", Reset-Countdown
--  * Oeffentlich: Lockouts.StateOf(name, raidKey), Lockouts.RaidFor(text), Lockouts.BoundHint(ev) (fuer Raid.lua)
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Modul Raidwerkzeuge (abschaltbar, siehe ModuleLoader.lua)
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
local Comm = ns.Comm

local LK = {}
ns.Lockouts = LK
local COLL = "lockouts"
LK.COLL = COLL
if ns.ICONS then ns.ICONS.lockouts = ns.MEDIA .. "icons\\raid" end
-- in die Navigationsgruppe "Raid" einhaengen (nach dem Raid-Check)
if ns.NAV_GROUPS then
    for _, g in ipairs(ns.NAV_GROUPS) do
        if g.key == "raid" then
            local pos = #g.pages + 1
            for i, k in ipairs(g.pages) do if k == "raidcheck" then pos = i + 1 end end
            local has = false
            for _, k in ipairs(g.pages) do if k == "lockouts" then has = true end end
            if not has then table.insert(g.pages, pos, "lockouts") end
        end
    end
end

------------------------------------------------------------------------
-- Raids und Freischaltungen (oben gesammelt, leicht zu pflegen)
------------------------------------------------------------------------
-- ids = Instanz-IDs (14. Rueckgabewert von GetSavedInstanceInfo), match = Teile des Namens (klein, de/en)
-- unlock = Schluessel aus UNLOCKS, ohne = keine Freischaltung noetig
-- Stufe: Gilden-Option "lkLvl_<key>" (Standard minLevel)
LK.RAIDS = {
    -- TODO Barrow Deeps (WoW Forever / Classic+): Instanz-ID, deutscher Name, Mindeststufe, Freischaltung unbekannt
    { key = "barrow", name = "Barrow Deeps", size = 10, minLevel = 60, ids = {}, match = { "barrow", "huegelgrab", "hügelgrab" } },
    -- TODO Hyjal (Classic+): Instanz-ID (TBC-Hyjal war 534), Mindeststufe, Freischaltung unbekannt
    { key = "hyjal", name = "Hyjal", size = 20, minLevel = 60, ids = { 534 }, match = { "hyjal" } },
    { key = "ony", name = "Onyxia's Lair", size = 40, minLevel = 60, ids = { 249 }, match = { "onyx" }, unlock = "ony" },
}
LK.RAID_BY = {}
for _, r in ipairs(LK.RAIDS) do LK.RAID_BY[r.key] = r end

-- quests = C_QuestLog.IsQuestFlaggedCompleted, items = Gegenstand im Besitz (Taschen/Bank/Schluesselbund)
-- Ein Treffer genuegt; einmal erkannt bleibt es gemerkt (Schluessel koennen auf der Bank liegen).
LK.UNLOCKS = {
    -- Horde: "Blood of the Black Dragon Champion" (6602) -> Drachenfeueramulett (16309)
    -- (Allianz waere 6502 "Drakefire Amulet" - Gilde ist Horde, trotzdem mitpruefen schadet nicht)
    { key = "ony", text = "Onyxia: Drakefire Amulet", quests = { 6602, 6502 }, items = { 16309 } },
    -- "Attunement to the Core" (7848)
    { key = "mc", text = "Molten Core: Attunement", quests = { 7848 } },
    { key = "ubrs", text = "Seal of Ascension (Upper Blackrock Spire)", items = { 12344 } },
    { key = "brd", text = "Shadowforge Key (Blackrock Depths)", items = { 11000 } },
    { key = "scholo", text = "Skeleton Key (Scholomance)", items = { 13704 } },
    { key = "strat", text = "Key to the City (Stratholme)", items = { 12382 } },
    { key = "dm", text = "Crescent Key (Dire Maul)", items = { 18249 } },
    { key = "zf", text = "Mallet of Zul'Farrak", items = { 9240 } },
    -- TODO Hyjal / Barrow Deeps: Freischaltungs-Quests von WoW Forever eintragen, sobald bekannt
}
LK.UNLOCK_BY = {}
for _, u in ipairs(LK.UNLOCKS) do LK.UNLOCK_BY[u.key] = u end

-- Rollenbedarf je Raidgroesse (Tanks, Heiler; Rest Schaden)
local NEED = { [10] = { 2, 3 }, [20] = { 3, 5 }, [25] = { 3, 6 }, [40] = { 5, 10 } }

for _, r in ipairs(LK.RAIDS) do
    ns.GuildOption({ page = "lockouts", key = "lkLvl_" .. r.key, default = r.minLevel, kind = "num", min = 1, max = 60, step = 1,
        label = "Minimum level " .. r.name, desc = "Below this a character counts as too low for this raid (also for group suggestions)." })
end

------------------------------------------------------------------------
-- Zustand (vor den Funktionen deklariert)
------------------------------------------------------------------------
local lastSent = nil        -- Hash des zuletzt gesendeten eigenen Datensatzes
local pendingFull = {}      -- Absender -> true / "cancel" (Voll-Antwort auf LKREQ)
local pendingOwn = {}
local scanQueued = false
local filter = { online = false, twinks = true }
local sugRaid = nil         -- gerade gezeigter Vorschlag (Raid-Schluessel)
local quietStore = false

local function S() return ns.db.settings end
local function showDemo() return ns.Demo and ns.Demo.IsActive() end
local function clean(s) return (tostring(s or ""):gsub("[~/+]", " ")) end
local function minLevel(r) return tonumber(ns.GuildOpt("lkLvl_" .. r.key)) or r.minLevel or 60 end

local function fmtLeft(sec)
    if not sec or sec <= 0 then return "-" end
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return (L["%dd %dh"]):format(d, h) end
    if h > 0 then return (L["%dh %dm"]):format(h, m) end
    return (L["%d min"]):format(math.max(1, m))
end
LK.FmtLeft = fmtLeft

local function raidOfSaved(name, instId)
    local ln = tostring(name or ""):lower()
    for _, r in ipairs(LK.RAIDS) do
        for _, id in ipairs(r.ids) do if instId and id == instId then return r.key end end
        for _, p in ipairs(r.match) do if ln:find(p, 1, true) then return r.key end end
    end
    return nil
end

------------------------------------------------------------------------
-- Eigene Daten lesen (alles per pcall; im Kampf geheim -> spaeter)
------------------------------------------------------------------------
local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function readSaved()
    local out = {}
    local ok, n = call(GetNumSavedInstances)
    n = ok and ns.safe(n) or 0
    local now = ns.now()
    for i = 1, n do
        local ok2, name, _, reset, _, locked, _, _, isRaid, maxP, _, numEnc, _, _, instId = call(GetSavedInstanceInfo, i)
        name, reset, locked, isRaid = ns.safe(name), ns.safe(reset), ns.safe(locked), ns.safe(isRaid)
        maxP, numEnc, instId = ns.safe(maxP), ns.safe(numEnc), ns.safe(instId)
        if ok2 and name and locked and (tonumber(reset) or 0) > 0 then
            local mask, killed = {}, {}
            for e = 1, (tonumber(numEnc) or 0) do
                local ok3, boss, _, isKilled = call(GetSavedInstanceEncounterInfo, i, e)
                boss, isKilled = ns.safe(boss), ns.safe(isKilled)
                mask[e] = (ok3 and isKilled) and "1" or "0"
                if ok3 and isKilled and boss then killed[#killed + 1] = clean(boss):sub(1, 30) end
            end
            local key = raidOfSaved(name, tonumber(instId)) or ("i" .. tostring(instId or i))
            out[#out + 1] = table.concat({ key, tostring(instId or 0), tostring(now + math.floor(reset)), table.concat(mask),
                table.concat(killed, "/"), tostring(maxP or 0), clean(name):sub(1, 40), isRaid and "1" or "0" }, "~")
        end
    end
    return out
end

local function hasItem(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, c = call(f, id, true)
    return ok and (tonumber(ns.safe(c)) or 0) > 0
end
local function questDone(id)
    local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    local ok, r = call(f, id)
    return ok and ns.safe(r) == true
end
local function readUnlocks(old)
    local have = {}
    for k in tostring(old or ""):gmatch("[^,]+") do have[k] = true end
    for _, u in ipairs(LK.UNLOCKS) do
        if not have[u.key] then
            for _, q in ipairs(u.quests or {}) do if questDone(q) then have[u.key] = true break end end
        end
        if not have[u.key] then
            for _, it in ipairs(u.items or {}) do if hasItem(it) then have[u.key] = true break end end
        end
    end
    local out = {}
    for k in pairs(have) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
end

------------------------------------------------------------------------
-- Datensaetze
------------------------------------------------------------------------
local function recordOf(char, snap)
    local rec = { id = "lk-" .. char, char = char, main = ns.Alts and ns.Alts.MyMain() or char, lvl = snap.lvl or 0,
        class = snap.class or "", rl = snap.rl or "", a = snap.a or "", ts = snap.ts or 0, n = #(snap.s or {}), v = 1 }
    for i, s in ipairs(snap.s or {}) do rec["s" .. i] = s end
    return rec
end
local function recHash(rec)
    local keys = {}
    for k in pairs(rec) do if k ~= "u" and k ~= "by" then keys[#keys + 1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(rec[k]) end
    return ns.hash(table.concat(parts, ";"))
end

local function sendRec(rec)
    if not IsInGuild() or S().lkShare == false then return end
    Comm.SendEx({ ch = "GUILD", key = "LKU" .. rec.id }, "LKU", Comm.encodeRecord(rec))
end
local function putLocal(rec)
    rec.u = math.max(ns.now(), ((Store.Get(COLL, rec.id) or {}).u or 0) + 1)
    rec.by = ns.me()
    Store.merge(COLL, rec)
end

function LK.Scan()
    scanQueued = false
    if not ns.char or not ns.me() then return end
    if ns.inCombat() then LK.QueueScan(10) return end
    local old = ns.char.lk or {}
    local _, cls = UnitClass("player")
    local rl = ""
    if ns.Radar and ns.Radar.myProfile then
        local ok, p = pcall(ns.Radar.myProfile)
        if ok and p and p.rl then rl = p.rl end
    end
    local snap = { ts = ns.now(), lvl = ns.safe(UnitLevel("player")) or old.lvl or 0, class = ns.safe(cls) or old.class or "",
        rl = rl ~= "" and rl or old.rl or "", a = readUnlocks(old.a), s = readSaved() }
    ns.char.lk = snap
    local rec = recordOf(ns.me(), snap)
    local h = recHash(rec)
    if h ~= lastSent then
        lastSent = h
        putLocal(rec)
        sendRec(rec)
    end
    ns.RefreshPage("lockouts")
end
function LK.QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    ns.After(delay or 2, LK.Scan)
end
local function request()
    ns.Trace("RequestRaidInfo")
    if call(RequestRaidInfo) then LK.QueueScan(3) else LK.QueueScan(1) end
end

-- Twinks: Stand vom letzten Login jedes eigenen Charakters ebenfalls teilen
local function shareMyChars()
    for name, c in pairs(ns.db.chars or {}) do
        if c.lk and not ns.isMe(name) and not (ns.Alts and ns.Alts.Shareable and not ns.Alts.Shareable(name)) then
            local rec = recordOf(name, c.lk)
            local cur = Store.Get(COLL, rec.id)
            if not cur or (cur.ts or 0) < rec.ts then putLocal(rec) end
            sendRec(Store.Get(COLL, rec.id) or rec)
        end
    end
end

------------------------------------------------------------------------
-- Lesen (alle Charaktere)
------------------------------------------------------------------------
-- gespeicherte IDs eines Datensatzes; abgelaufene (Reset vorbei) fallen weg
function LK.Saved(rec)
    local out, now = {}, ns.now()
    if not rec then return out end
    for i = 1, (tonumber(rec.n) or 0) do
        local s = rec["s" .. i]
        if type(s) == "string" then
            local f = {}
            for part in (s .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
            local reset = tonumber(f[3]) or 0
            if reset > now then
                local killed, total = 0, #(f[4] or "")
                for _ in (f[4] or ""):gmatch("1") do killed = killed + 1 end
                out[f[1]] = { key = f[1], inst = tonumber(f[2]), reset = reset, killed = killed, total = total,
                    bosses = f[5] or "", size = tonumber(f[6]) or 0, name = f[7] or f[1], raid = f[8] == "1" }
            end
        end
    end
    return out
end
function LK.Unlocked(rec, key)
    if not rec or not key then return false end
    for k in tostring(rec.a or ""):gmatch("[^,]+") do if k == key then return true end end
    return false
end
local function findRec(name)
    if not name then return nil end
    local r = Store.Get(COLL, "lk-" .. name)
    if r and not r.del then return r end
    if showDemo() then r = Store.Get(COLL, "demo-lk-" .. name) if r then return r end end
    local a = ns.Radar and ns.Radar.AliasOf and ns.Radar.AliasOf(name)
    if a then r = Store.Get(COLL, "lk-" .. a) if r and not r.del then return r end end
    if ns.isMe(name) and ns.me() then r = Store.Get(COLL, "lk-" .. ns.me()) if r and not r.del then return r end end
    return nil
end
LK.Find = findRec

-- "bound" (dazu Fortschritt), "free", "locked" (nicht freigeschaltet), "low" (Stufe zu niedrig), "nodata"
function LK.StateOf(name, raidKey, level)
    local r = LK.RAID_BY[raidKey]
    if not r then return "nodata" end
    local rec = findRec(name)
    local lvl = level or (rec and rec.lvl)
    if not lvl or lvl == 0 then
        local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
        lvl = m and m.level
    end
    if not rec then
        if lvl and lvl > 0 and lvl < minLevel(r) then return "low" end
        return "nodata"
    end
    local sv = LK.Saved(rec)[raidKey]
    if sv then return "bound", sv end
    if (rec.lvl or lvl or 0) < minLevel(r) then return "low" end
    if r.unlock and not LK.Unlocked(rec, r.unlock) then return "locked" end
    return "free"
end

function LK.RaidFor(text)
    local t = tostring(text or ""):lower()
    if t == "" then return nil end
    for _, r in ipairs(LK.RAIDS) do
        if t:find(r.name:lower(), 1, true) or t:find(L[r.name]:lower(), 1, true) then return r end
        for _, p in ipairs(r.match) do if t:find(p, 1, true) then return r end end
    end
    return nil
end

-- fuer die Raid-Terminansicht: "x Angemeldete sind schon gebunden" (nil = nichts zu sagen)
function LK.BoundHint(ev)
    if not ev then return nil end
    local r = LK.RaidFor(ev.inst) or LK.RaidFor(ev.title)
    if not r or not (ns.Raid and ns.Raid.Signups) then return nil end
    -- nur relevant, wenn der Termin vor dem Reset liegt
    local n, names = 0, {}
    for _, s in ipairs(ns.Raid.Signups(ev.id)) do
        if s.status == "yes" or s.status == "maybe" then
            local st, sv = LK.StateOf(s.who, r.key)
            if st == "bound" and sv and (not ev.ts or sv.reset > ev.ts) then
                n = n + 1
                names[#names + 1] = ns.displayName(s.who)
            end
        end
    end
    if n == 0 then return nil end
    local list = table.concat(names, ", ", 1, math.min(#names, 5)) .. (#names > 5 and " ..." or "")
    return "|cffe8b44a" .. (L["%d signed-up players are already saved"]):format(n) .. ":|r |cff888888" .. list .. "|r"
end

-- naechster Reset je Raid (aus allen bekannten IDs)
function LK.NextReset(raidKey)
    local best
    for _, rec in ipairs(Store.List(COLL)) do
        for key, sv in pairs(LK.Saved(rec)) do
            if (not raidKey or key == raidKey) and (not best or sv.reset < best) then best = sv.reset end
        end
    end
    return best
end

------------------------------------------------------------------------
-- Zeilen fuer das Raster: Datensaetze + Gildenliste, je Charakter eine Zeile
------------------------------------------------------------------------
local function online(name)
    if ns.isMe(name) then return true end
    return ns.Radar and ns.Radar.IsOnline and ns.Radar.IsOnline(name) and true or false
end
local function isAlt(name) return ns.Alts and ns.Alts.IsAlt(name) or false end

function LK.Rows()
    local rows, seen = {}, {}
    local canon = (ns.Alts and ns.Alts.Canon) or function(n) return n end
    local function add(name, rec, m)
        local c = canon(name)
        if not c or seen[c] then return end
        seen[c] = true
        local lvl = (rec and rec.lvl and rec.lvl > 0 and rec.lvl) or (m and m.level) or 0
        local cls = (rec and rec.class ~= "" and rec.class) or (m and m.class) or (ns.Radar and ns.Radar.ClassOf(name))
        rows[#rows + 1] = { name = name, rec = rec, lvl = lvl, class = cls, online = online(name), alt = isAlt(name),
            main = ns.Alts and ns.Alts.Main(name) or name }
    end
    for _, rec in ipairs(Store.List(COLL)) do
        if rec.char and (showDemo() or not rec.demo) then add(rec.char, rec, ns.Radar and ns.Radar.byName[rec.char]) end
    end
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do add(m.name, findRec(m.name), m) end
    local out = {}
    for _, r in ipairs(rows) do
        if (not filter.online or r.online) and (filter.twinks or not r.alt) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        local ma, mb = ns.displayName(a.main), ns.displayName(b.main)
        if ma ~= mb then return ma < mb end
        if a.alt ~= b.alt then return not a.alt end
        return ns.displayName(a.name) < ns.displayName(b.name)
    end)
    return out
end

------------------------------------------------------------------------
-- Freie Gruppe vorschlagen: je Spieler (Main + Twinks) ein freier, freigeschalteter Charakter passender Stufe
------------------------------------------------------------------------
local function rolesOf(row)
    local rl = row.rec and row.rec.rl or ""
    if rl == "" then
        local p = ns.db.members[row.name]
        rl = p and p.rl or ""
    end
    return rl
end
function LK.Suggest(raidKey)
    local r = LK.RAID_BY[raidKey]
    if not r then return {} end
    local saveF = { online = filter.online, twinks = filter.twinks }
    filter.online, filter.twinks = false, true
    local all = LK.Rows()
    filter.online, filter.twinks = saveF.online, saveF.twinks
    -- beste Wahl je Spieler: online vor offline, Main vor Twink, hoehere Stufe
    local byPlayer = {}
    for _, row in ipairs(all) do
        if row.rec and LK.StateOf(row.name, raidKey, row.lvl) == "free" then
            local key = ns.displayName(row.main)
            local cur = byPlayer[key]
            local better = not cur or (row.online and not cur.online)
                or (row.online == cur.online and ((not row.alt and cur.alt) or (row.alt == cur.alt and row.lvl > cur.lvl)))
            if better then byPlayer[key] = row end
        end
    end
    local cand = {}
    for _, row in pairs(byPlayer) do row.rl = rolesOf(row) cand[#cand + 1] = row end
    table.sort(cand, function(a, b)
        if a.online ~= b.online then return a.online end
        if #a.rl ~= #b.rl then return #a.rl < #b.rl end   -- Spezialisten zuerst verteilen
        return a.lvl > b.lvl
    end)
    local need = NEED[r.size] or { math.max(1, math.floor(r.size / 8)), math.max(1, math.floor(r.size / 4)) }
    local out, used = {}, {}
    local function take(letter, role, max)
        local n = 0
        for _, row in ipairs(cand) do
            if n >= max or #out >= r.size then break end
            if not used[row] and row.rl:find(letter, 1, true) then
                used[row] = true
                n = n + 1
                out[#out + 1] = { row = row, role = role }
            end
        end
    end
    take("t", "TANK", need[1])
    take("h", "HEALER", need[2])
    take("d", "DAMAGER", r.size)
    -- ohne Rollenangabe zuletzt als Schaden auffuellen
    for _, row in ipairs(cand) do
        if #out >= r.size then break end
        if not used[row] then used[row] = true out[#out + 1] = { row = row, role = "DAMAGER", guess = true } end
    end
    return out, need
end

function LK.InviteOnline(list)
    if ns.inCombat() then ns.print(L["Not possible in combat - try again shortly."]) return end
    local n = 0
    for _, e in ipairs(list or {}) do
        if e.row.online and not ns.isMe(e.row.name) and not (e.row.rec and e.row.rec.demo) then
            n = n + 1
            local who = e.row.name
            ns.After(n * 0.3, function() ns.InviteName(who) end)
        end
    end
    if n == 0 then ns.print(L["Nobody from the suggestion is online."]) end
end

------------------------------------------------------------------------
-- Gilden-Abgleich (eigene Nachrichten, damit nichts an Comm.lua haengt)
------------------------------------------------------------------------
-- Empfang: direkt (LKU) nur Datensaetze, die der Absender selbst erstellt hat; weitergereicht (LKB) nie
-- einem anderen Ersteller zuschlagen; Zeitstempel nicht in der Zukunft; Texte entschaerfen; Sammlung begrenzt
local function sameWho(a, b) return a and b and ns.Comm.whoKey(a) == ns.Comm.whoKey(b) end
local function acceptNet(rec, sender, relay)
    if type(rec) ~= "table" or type(rec.id) ~= "string" or #rec.id > 100 or not rec.id:find("^lk%-") or not rec.char then return end
    if rec.demo or rec.id:find("demo-", 1, true) then return end
    if ns.isMe(rec.char) then return end
    if sender and ns.Comm.FromGuild and not ns.Comm.FromGuild(sender) then return end   -- nur Gildenmitglieder
    if sender and not relay and rec.by and not sameWho(rec.by, sender) then return end
    rec.u = math.min(tonumber(rec.u) or 0, ns.now() + 300)
    for k, v in pairs(rec) do
        if type(v) == "string" then rec[k] = SEC.Text(v, 600)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then rec[k] = 0 end
    end
    local c = Store.coll(COLL)
    local old = c[rec.id]
    if old and old.by and rec.by and not sameWho(old.by, rec.by) then return end
    if not old then
        local n = 0
        for _ in pairs(c) do n = n + 1 if n >= 2000 then return end end
    end
    Store.merge(COLL, rec, true, sender, relay)
end
LK.AcceptNet = acceptNet
local function batchSend(target, recs)
    local batch, size = {}, 0
    local function flush()
        if #batch > 0 then Comm.WhisperBulk(target, "LKB", unpack(batch)) batch, size = {}, 0 end
    end
    for _, r in ipairs(recs) do
        local s = Comm.encodeRecord(r)
        batch[#batch + 1] = s
        size = size + #s
        if size > 1500 then flush() end
    end
    flush()
end
local function realRecs(onlyMine)
    local out = {}
    for _, r in pairs(Store.coll(COLL)) do
        if not r.demo and not tostring(r.id):find("demo-", 1, true) and r.char
            and (not onlyMine or (ns.db.chars[r.char] ~= nil)) then
            out[#out + 1] = r
        end
    end
    return out
end

if Comm then
    Comm.On("LKU", function(sender, channel, recStr)
        if recStr then acceptNet(Comm.decodeRecord(recStr), sender, false) ns.RefreshPage("lockouts") end
    end)
    Comm.On("LKB", function(sender, channel, ...)
        for i = 1, math.min(select("#", ...), 200) do
            local s = select(i, ...)
            if s and s ~= "" then acceptNet(Comm.decodeRecord(s), sender, true) end
        end
        ns.RefreshPage("lockouts")
    end)
    -- Neuankoemmling fragt: jeder schickt seine eigenen Charaktere, EINER (zufaellig) zusaetzlich alles
    Comm.On("LKREQ", function(sender)
        -- je Anfragendem hoechstens jede Minute (sonst laesst sich eine Fluester-Flut ausloesen)
        if not SEC.Rate("lkreq:" .. tostring(sender), 60) then return end
        if S().lkShare ~= false and not pendingOwn[sender] then
            pendingOwn[sender] = true
            ns.After(math.random(5, 30) / 10, function()
                pendingOwn[sender] = nil
                local mine = realRecs(true)
                if #mine > 0 then batchSend(sender, mine) end
            end)
        end
        if pendingFull[sender] then return end
        pendingFull[sender] = true
        ns.After(math.random(30, 90) / 10 + (ns.isOfficer() and 0 or 1), function()
            if pendingFull[sender] ~= true then pendingFull[sender] = nil return end
            pendingFull[sender] = nil
            Comm.Guild("LKACK", sender)
            batchSend(sender, realRecs(false))
        end)
    end)
    Comm.On("LKACK", function(sender, channel, target)
        if target and pendingFull[target] then pendingFull[target] = "cancel" end
    end)
end

-- abgelaufene/alte Datensaetze verwerfen (Comm.prune kennt die Sammlung nicht)
function LK.Prune()
    local now = ns.now()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do
        local hasLive = next(LK.Saved(r)) ~= nil
        local age = now - (r.u or 0)
        if r.del or (age > 60 * 86400) or (not hasLive and (r.a or "") == "" and age > 14 * 86400) then c[id] = nil end
    end
end

------------------------------------------------------------------------
-- Demo (/oa demo): Demo-Mitglieder bekommen Raid-IDs, bleibt lokal
------------------------------------------------------------------------
function LK.SeedDemo()
    if not showDemo() or not ns.Radar then return end
    local now = ns.now()
    local reset = now + 3 * 86400 + 5 * 3600
    local i = 0
    for _, m in ipairs(ns.Radar.roster or {}) do
        if m.demo then
            i = i + 1
            local lvl = math.max(m.level or 1, (i % 3 == 0) and 60 or (m.level or 1))
            local rec = { id = "demo-lk-" .. m.name, char = m.name, main = m.name, lvl = lvl, class = m.class or "",
                rl = (ns.db.members[m.name] and ns.db.members[m.name].rl) or "d", demo = true, ts = now, n = 0, v = 1,
                a = (i % 4 ~= 1) and "ony,ubrs" or "ubrs" }
            if lvl >= 60 then
                if i % 3 == 0 then rec.n = rec.n + 1 rec["s" .. rec.n] = "ony~249~" .. reset .. "~1~Onyxia~40~" .. L["Onyxia's Lair"] .. "~1" end
                if i % 5 == 0 then rec.n = rec.n + 1 rec["s" .. rec.n] = "hyjal~534~" .. reset .. "~11000~" .. "Rage Winterchill/Anetheron~20~Hyjal~1" end
                if i % 2 == 0 then rec.n = rec.n + 1 rec["s" .. rec.n] = "barrow~0~" .. (now + 86400 + 7200) .. "~1100~" .. "~10~Barrow Deeps~1" end
            end
            rec.u = now
            quietStore = true
            Store.merge(COLL, rec)
            quietStore = false
        end
    end
    ns.RefreshPage("lockouts")
end
function LK.RemoveDemo()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    ns.RefreshPage("lockouts")
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
ns.On("UPDATE_INSTANCE_INFO", function() LK.QueueScan(1) end)
ns.On("BOSS_KILL", function() ns.After(5, request) end)
ns.On("ENCOUNTER_END", function() ns.After(5, request) end)
ns.On("PLAYER_REGEN_ENABLED", function() if not scanQueued and ns.char and not ns.char.lk then request() end end)
ns.On("QUEST_TURNED_IN", function() LK.QueueScan(3) end)
ns.Listen("LEVEL_UP", function() LK.QueueScan(3) end)
ns.Listen("STORE", function(name) if name == COLL and not quietStore then ns.RefreshPage("lockouts") end end)

ns.Listen("LOGIN", function()
    if S().lkShare == nil then S().lkShare = true end
    if S().lkTwinks ~= nil then filter.twinks = S().lkTwinks end
    if S().lkOnline ~= nil then filter.online = S().lkOnline end
    LK.Prune()
    ns.After(6, request)
    ns.After(15, function()
        shareMyChars()
        if IsInGuild() and Comm then Comm.Guild("LKREQ") end
    end)
    ns.Every(60, function() ns.RefreshPage("lockouts") end)
    ns.Every(1800, request)
    -- Demo: Daten mitladen/-entfernen (Muster wie Camp.lua)
    local D = ns.Demo
    if D and not D.lkHooked then
        D.lkHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) if load then load(...) end ns.After(2, LK.SeedDemo) end
        D.Remove = function(...) if remove then remove(...) end LK.RemoveDemo() end
        if D.IsActive() then ns.After(5, LK.SeedDemo) end
    end
end)

------------------------------------------------------------------------
-- Einstellungen (Zahnrad des Bereichs)
------------------------------------------------------------------------
if ns.AddPageSettings then
    ns.AddPageSettings("lockouts", function(det, y)
        if S().lkShare == nil then S().lkShare = true end
        local t = K.Toggle(det, L["Share my raid lockouts with the guild"], function() return S().lkShare ~= false end,
            function(v) S().lkShare = v if v then lastSent = nil LK.QueueScan(1) end end)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        det.t[#det.t + 1] = t
        y = y - 32
        local hint = K.Text(det, 11, C.dim)
        hint:SetPoint("TOPLEFT", 14, y)
        hint:SetWidth(600)
        hint:SetWordWrap(true)
        hint:SetText(L["Alts show the state of their last login. Minimum levels per raid are set by the guild leadership."])
        return y - 30
    end)
end

------------------------------------------------------------------------
-- Seite (Neugestaltung): Kopf-Kacheln, je Raid eine Karte (Verteilung + Reset), Mitglieder-Liste
-- mit Status-Plaketten; Spalten passen sich der Breite an (schmal: Kurztexte, kein Einladen-Knopf)
------------------------------------------------------------------------
local ROLE_ICON = { TANK = "role_tank", HEALER = "role_heal", DAMAGER = "role_dps" }
local ROLE_COL = { TANK = C.blue, HEALER = C.mint, DAMAGER = C.red }
local ST_COL = { bound = C.red, free = C.mint, locked = C.amber, low = C.dim, nodata = C.line }
local ST_ORDER = { "bound", "free", "locked", "low" }
local RAID_COL = { barrow = C.blue, hyjal = C.mint, ony = C.amber }
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function glyph(n) return ns.MEDIA .. "icons\\" .. n end
local function place(p, key, f, x, y, w, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    if h then f:SetSize(w, h) else f:SetWidth(w) f:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0) end
    p.rects[key] = { x = x, y = y, w = w, h = h }
end
local function nameOf(name)
    return ns.Radar and ns.Radar.Label and ns.Radar.Label(name) or (ns.Radar and ns.Radar.Colored and ns.Radar.Colored(name)) or ns.displayName(name)
end

local function stateText(st, sv, rd, short)
    if st == "bound" then
        local prog = (sv and (sv.total or 0) > 0) and (sv.killed .. "/" .. sv.total) or nil
        if short then return prog or L["saved"] end
        return L["saved"] .. (prog and (" " .. prog) or "")
    elseif st == "free" then return L["open"]
    elseif st == "locked" then return short and L["locked"] or L["not attuned"]
    elseif st == "low" then return short and ("< " .. minLevel(rd)) or "-"   -- "Stufe zu niedrig" in jeder Zelle war eine Textwand
    end
    return "?"
end

-- Status-Plakette (farbige Flaeche mit Kante links)
local function newPill(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.edge = f:CreateTexture(nil, "ARTWORK")
    f.edge:SetPoint("TOPLEFT") f.edge:SetPoint("BOTTOMLEFT")
    f.edge:SetWidth(2)
    f.t = K.Text(f, 10, C.text, "CENTER")
    f.t:SetPoint("LEFT", 4, 0)
    f.t:SetPoint("RIGHT", -3, 0)
    f.t:SetWordWrap(false)
    function f:Set(text, c, faint)
        self.t:SetText(text)
        local k = faint and 0.10 or 0.22
        self.bg:SetColorTexture(c[1] * k, c[2] * k, c[3] * k, 1)
        self.edge:SetColorTexture(c[1], c[2], c[3], faint and 0.35 or 0.95)
        self.t:SetTextColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5)
    end
    return f
end

-- Spalten der Mitglieder-Liste fuer Breite w (Zeilen und Kopf nutzen dieselbe Tabelle)
local function columns(w)
    local n = #LK.RAIDS
    local x0, lvlW, gap = 30, 30, 6
    local invW = 66
    local pw = math.floor((w - x0 - 130 - lvlW - invW - n * gap) / n)
    pw = math.max(56, math.min(132, pw))
    local nameW = w - x0 - lvlW - invW - n * (pw + gap) - 8
    if nameW < 110 then
        invW = 0
        pw = math.max(50, math.min(132, math.floor((w - x0 - 110 - lvlW - n * gap - 8) / n)))
        nameW = w - x0 - lvlW - n * (pw + gap) - 8
    end
    nameW = math.max(70, nameW)
    local cols = { name = { x0, nameW }, lvl = { x0 + nameW + 4, lvlW }, raids = {}, inv = invW > 0 and invW or nil,
        short = pw < 118, key = w .. ":" .. pw .. ":" .. invW }
    local x = x0 + nameW + 4 + lvlW + gap
    for i = 1, n do cols.raids[i] = { x, pw } x = x + pw + gap end
    return cols
end

local function rowTip(self)
    local e = self.item
    if not e then return end
    local lines = { nameOf(e.name) }
    if not e.rec then
        lines[#lines + 1] = "|cff888888" .. L["No Oasis data (not logged in with Oasis yet)."] .. "|r"
    else
        lines[#lines + 1] = "|cff888888" .. (L["As of: %s"]):format(ns.ago(e.rec.ts)) .. "|r"
        local sv = LK.Saved(e.rec)
        for _, r in ipairs(LK.RAIDS) do
            local s = sv[r.key]
            if s then
                lines[#lines + 1] = (L["%s: saved, reset in %s"]):format(L[r.name], fmtLeft(s.reset - ns.now()))
                if s.bosses ~= "" then lines[#lines + 1] = "  |cff888888" .. s.bosses:gsub("/", ", ") .. "|r" end
            else
                local st = LK.StateOf(e.name, r.key, e.lvl)
                lines[#lines + 1] = L[r.name] .. ": " .. K.hex(ST_COL[st] or C.dim) .. stateText(st, nil, r, false) .. "|r"
            end
        end
        for key, s in pairs(sv) do
            if not LK.RAID_BY[key] then lines[#lines + 1] = "|cffaaaaaa" .. s.name .. "|r  " .. fmtLeft(s.reset - ns.now()) end
        end
        local un = {}
        for _, u in ipairs(LK.UNLOCKS) do if LK.Unlocked(e.rec, u.key) then un[#un + 1] = L[u.text] end end
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffe8b44a" .. L["Attunements & keys"] .. "|r"
        lines[#lines + 1] = #un > 0 and table.concat(un, "\n") or ("|cff666666" .. L["none known"] .. "|r")
    end
    K.ShowTip(self, lines)
end

local function showSuggest(p, key)
    sugRaid = key
    p.animSug = true
    ns.RefreshPage("lockouts")
    if ns.RCUI and p.sug then ns.RCUI.Reveal(p.sug) end
end

-- Karte je Raid: Name, Groesse + Reset, Verteilungsbalken, Zaehler, "Freie Gruppe"
local function newRaidCard(p, rd, idx)
    local U = ns.RCUI
    local col = RAID_COL[rd.key] or C.accent
    local c = U.Card(p, col)
    c.rd, c.idx = rd, idx
    c:EnableMouse(true)
    c.name = K.Title(c, 13, C.text)
    c.name:SetWordWrap(false)
    c.name:SetText(L[rd.name])
    c.meta = K.Text(c, 10, C.muted)
    c.meta:SetWordWrap(false)
    c.counts = K.Text(c, 10, C.muted)
    c.counts:SetWordWrap(false)
    c.bar = CreateFrame("Frame", nil, c)
    K.Fill(c.bar, C.field)
    c.segs = {}
    for _, st in ipairs(ST_ORDER) do
        local t = c.bar:CreateTexture(nil, "ARTWORK")
        local sc = ST_COL[st]
        t:SetColorTexture(sc[1], sc[2], sc[3], st == "low" and 0.6 or 0.95)
        t:Hide()
        c.segs[st] = t
    end
    c.btn = K.Button(c, L["Free group"], 104, 22, "ghost", function() showSuggest(p, rd.key) end)
    c.btn.label:SetFont(K.FONT, 11, "")
    c.btn:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Suggest free group"],
        L["Free, attuned mains and alts of fitting level, one per player, roles from the profiles."] }) end)
    c.btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    c:SetScript("OnEnter", function(self)
        local n = self.n or {}
        local lines = { L[rd.name] .. "  |cff888888(" .. rd.size .. ")|r" }
        for _, st in ipairs(ST_ORDER) do
            lines[#lines + 1] = K.hex(ST_COL[st]) .. stateText(st, nil, rd, false) .. "|r: " .. (n[st] or 0)
        end
        if rd.unlock and LK.UNLOCK_BY[rd.unlock] then lines[#lines + 1] = "|cff888888" .. L["Attunement"] .. ": " .. L[LK.UNLOCK_BY[rd.unlock].text] .. "|r" end
        K.ShowTip(self, lines)
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function c:PaintBar(f)
        local x, tot = 0, self.total or 0
        for _, st in ipairs(ST_ORDER) do
            local t = self.segs[st]
            local v = (self.n and self.n[st]) or 0
            local w = tot > 0 and (self.bw * v / tot * f) or 0
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", self.bar, "TOPLEFT", x, 0)
            t:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", x, 0)
            t:SetWidth(math.max(0.01, w))
            t:SetShown(w >= 0.5)
            x = x + w
        end
    end
    function c:Layout(w, compact)
        self.w, self.compact = w, compact
        self.btn:ClearAllPoints()
        self.name:ClearAllPoints() self.meta:ClearAllPoints() self.counts:ClearAllPoints() self.bar:ClearAllPoints()
        if compact then
            self.btn:SetPoint("RIGHT", self, "RIGHT", -10, 2)
            self.name:SetPoint("TOPLEFT", 14, -7)
            self.name:SetPoint("RIGHT", self, "RIGHT", -124, 0)
            self.meta:SetPoint("TOPLEFT", 14, -24)
            self.meta:SetPoint("RIGHT", self, "RIGHT", -124, 0)
            self.counts:Hide()
            self.bw = math.max(10, w - 28)
            self.bar:SetPoint("BOTTOMLEFT", 14, 4)
            self.bar:SetSize(self.bw, 3)
        else
            self.btn:SetPoint("TOPRIGHT", -10, -10)
            self.name:SetPoint("TOPLEFT", 14, -12)
            self.name:SetPoint("RIGHT", self, "RIGHT", -122, 0)
            self.meta:SetPoint("TOPLEFT", 14, -31)
            self.meta:SetPoint("RIGHT", self, "RIGHT", -122, 0)
            self.bw = math.max(10, w - 28)
            self.bar:SetPoint("TOPLEFT", 14, -56)
            self.bar:SetSize(self.bw, 6)
            self.counts:SetPoint("TOPLEFT", 14, -70)
            self.counts:SetPoint("RIGHT", self, "RIGHT", -12, 0)
            self.counts:Show()
        end
        self:PaintBar(1)
    end
    function c:SetData(n, total, nextReset, anim)
        self.n, self.total = n, total
        local sizeT = (L["%d players"]):format(rd.size)
        local res = nextReset and (L["Reset in %s"]):format(fmtLeft(nextReset - ns.now())) or (L["from level %d"]):format(minLevel(rd))
        local cnt = ("|cffe64047%d|r %s  ·  |cff66db9e%d|r %s  ·  |cffff8a3d%d|r %s"):format(n.bound or 0, L["saved"], n.free or 0, L["open"], n.locked or 0, L["locked"])
        if self.compact then
            self.meta:SetText(("|cffe64047%d|r / |cff66db9e%d|r / |cffff8a3d%d|r  ·  %s"):format(n.bound or 0, n.free or 0, n.locked or 0, res))
        else
            self.meta:SetText(sizeT .. "  ·  " .. res)
        end
        self.counts:SetText(cnt)
        if anim and animOn() then
            K.Tween(self.bar, 0.7, function(q) self:PaintBar(1 - (1 - q) * (1 - q)) end, function() self:PaintBar(1) end, (self.idx - 1) * 0.08)
        else
            self:PaintBar(1)
        end
    end
    return c
end

-- Zeile der Mitglieder-Liste: Klassensymbol, Name, Stufe, je Raid eine Plakette, Einladen
local function applyRowCols(p, r)
    local cols = p.cols
    if r.ck == cols.key then return end
    r.ck = cols.key
    r.cols.name:ClearAllPoints()
    r.cols.name:SetPoint("LEFT", cols.name[1], 0)
    r.cols.name:SetWidth(cols.name[2])
    r.cols.lvl:ClearAllPoints()
    r.cols.lvl:SetPoint("LEFT", cols.lvl[1], 0)
    r.cols.lvl:SetWidth(cols.lvl[2])
    for i, pl in ipairs(r.pills) do
        local c = cols.raids[i]
        pl:ClearAllPoints()
        pl:SetPoint("LEFT", r, "LEFT", c[1], 0)
        pl:SetWidth(c[2])
    end
    r.inv:SetWidth(cols.inv or 60)
end

ns.RegisterPage({
    key = "lockouts", title = "Raid Lockouts", order = 2.77,
    sub = "Who is already saved this week, who is free and attuned – mains and alts",
    build = function(p)
        local U = ns.RCUI
        p.rects = {}
        if not U then
            p.miss = K.Text(p, 13, C.dim, "CENTER")
            p.miss:SetPoint("CENTER")
            p.miss:SetText(L["Raid check module missing – this view needs its building blocks."])
            return
        end
        -- 1) Kopf-Kacheln
        p.tiles = {}
        for i, d in ipairs({ { "raid", "Saved this week", C.red }, { "groups", "Free & ready", C.mint },
            { "legacy", "Not attuned", C.amber }, { "chronicle", "Next reset", C.blue } }) do
            p.tiles[i] = K.HudTile(p, glyph(d[1]), L[d[2]], d[3])
        end
        -- 2) Raid-Karten
        p.cards = {}
        for i, rd in ipairs(LK.RAIDS) do p.cards[i] = newRaidCard(p, rd, i) end
        -- 3) Werkzeugleiste
        local bar = CreateFrame("Frame", nil, p)
        p.bar = bar
        p.seg = K.Segments(bar, { { key = "all", text = L["All"] }, { key = "online", text = L["Online only"] } }, function(k)
            filter.online = (k == "online")
            S().lkOnline = filter.online
            ns.RefreshPage("lockouts")
            U.Reveal(p.list)
        end)
        p.seg:SetPoint("LEFT", 0, 0)
        p.twk = K.Button(bar, "", 112, 22, "ghost", function()
            filter.twinks = not filter.twinks
            S().lkTwinks = filter.twinks
            ns.RefreshPage("lockouts")
            U.Reveal(p.list)
        end)
        p.twk:SetPoint("LEFT", p.seg, "RIGHT", 10, 0)
        p.twk:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Alts"], L["Alts show the state of their last login."] }) end)
        p.twk:HookScript("OnLeave", function() GameTooltip:Hide() end)
        p.scan = K.Button(bar, L["Refresh"], 104, 22, "ghost", function() lastSent = nil request() end)
        p.scan:SetPoint("RIGHT", 0, 0)
        p.cnt = K.Text(bar, 10, C.dim, "RIGHT")
        p.cnt:SetPoint("RIGHT", p.scan, "LEFT", -10, 0)
        p.cnt:SetWordWrap(false)
        -- 4) Spaltenkopf + Liste
        local hdr = CreateFrame("Frame", nil, p)
        p.hdr = hdr
        hdr.line = hdr:CreateTexture(nil, "ARTWORK")
        hdr.line:SetPoint("BOTTOMLEFT") hdr.line:SetPoint("BOTTOMRIGHT")
        hdr.line:SetHeight(1)
        hdr.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        hdr.name = K.Text(hdr, 10, C.dim)
        hdr.name:SetText(K.Upper(L["Character"]))
        hdr.lvl = K.Text(hdr, 10, C.dim)
        hdr.lvl:SetText(K.Upper(L["Lvl"]))
        hdr.raids = {}
        for i, rd in ipairs(LK.RAIDS) do
            local t = K.Text(hdr, 10, RAID_COL[rd.key] or C.muted, "CENTER")
            t:SetWordWrap(false)
            t:SetText(K.Upper(L[rd.name]))
            hdr.raids[i] = t
        end
        p.cols = columns(700)
        p.list = K.List(p, 26, function(l)
            local r = K.Row(l)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(16, 16)
            r.cls:SetPoint("LEFT", 8, 0)
            r.dot = r:CreateTexture(nil, "OVERLAY")
            r.dot:SetTexture(U.CIRCLE)
            r.dot:SetSize(6, 6)
            r.dot:SetPoint("BOTTOMRIGHT", r.cls, "BOTTOMRIGHT", 2, -2)
            r:Col("name", 30, 160, 12)
            r.cols.name:SetWordWrap(false)
            r:Col("lvl", 200, 30, 11, C.muted)
            r.pills = {}
            for i = 1, #LK.RAIDS do r.pills[i] = newPill(r) end
            r.inv = K.Button(r, L["Invite"], 60, 18, "ghost")
            r.inv:SetPoint("RIGHT", -4, 0)
            r.inv.label:SetFont(K.FONT, 10, "")
            r.inv:SetScript("OnClick", function(self) local e = self:GetParent().item if e then ns.InviteName(e.name) end end)
            r:SetScript("OnEnter", rowTip)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            applyRowCols(p, r)
            U.ClassIcon(r.cls, e.class)
            local oc = e.online and C.mint or C.dim
            r.dot:SetVertexColor(oc[1], oc[2], oc[3], e.online and 1 or 0.6)
            r.cols.name:SetText(nameOf(e.name) .. (e.alt and ("  |cff666666" .. L["Alt"] .. "|r") or ""))
            r.cols.lvl:SetText(e.lvl > 0 and e.lvl or "?")
            for i, rd in ipairs(LK.RAIDS) do
                local st, sv = LK.StateOf(e.name, rd.key, e.lvl)
                r.pills[i]:Set(stateText(st, sv, rd, p.cols.short), ST_COL[st] or C.line, st == "nodata" or st == "low")
            end
            r.inv:SetShown(p.cols.inv ~= nil and e.online and not ns.isMe(e.name) and not (e.rec and e.rec.demo))
            r:SetAlpha(e.online and 1 or 0.78)
        end)
        p.list.empty:SetText(L["No data yet. As soon as guild members log in with Oasis, their lockouts appear here."])

        -- 5) Vorschlag (ersetzt Karten + Liste)
        local sug = U.Card(p, C.mint)
        sug:Hide()
        p.sug = sug
        sug.head = K.GameHead(sug, L["Suggest free group"], C.mint)
        sug.head:SetPoint("TOPLEFT", 14, -14)
        sug.back = K.Button(sug, L["Back"], 90, 22, "ghost", function() sugRaid = nil ns.RefreshPage("lockouts") U.Reveal(p.list) end)
        sug.back:SetPoint("TOPRIGHT", -12, -10)
        sug.invAll = K.Button(sug, L["Invite all online"], 150, 22, "primary", function() LK.InviteOnline(sug.cur) end)
        sug.invAll:SetPoint("RIGHT", sug.back, "LEFT", -8, 0)
        sug.head:SetPoint("RIGHT", sug.invAll, "LEFT", -8, 0)
        sug.chips = {}
        for i, d in ipairs({ { "role_tank", "Tanks", C.blue }, { "role_heal", "Healer", C.mint }, { "role_dps", "Damage", C.red }, { "radar", "Online", C.accent } }) do
            local ch = CreateFrame("Frame", nil, sug)
            ch.bg = K.Fill(ch, C.raised)
            K.Border(ch, C.line)
            ch.top = ch:CreateTexture(nil, "ARTWORK")
            ch.top:SetPoint("TOPLEFT") ch.top:SetPoint("TOPRIGHT") ch.top:SetHeight(2)
            ch.top:SetColorTexture(d[3][1], d[3][2], d[3][3], 0.9)
            ch.icon = K.Glyph(ch, 18, glyph(d[1]), d[3])
            ch.icon:SetPoint("LEFT", 10, 0)
            ch.val = K.Title(ch, 16, C.text)
            ch.val:SetPoint("LEFT", 36, 5)
            ch.lab = K.Text(ch, 9, C.muted)
            ch.lab:SetPoint("LEFT", 36, -10)
            ch.lab:SetText(K.Upper(L[d[2]]))
            sug.chips[i] = ch
        end
        sug.info = K.Text(sug, 11, C.muted)
        sug.info:SetWordWrap(true)
        sug.info:SetJustifyV("TOP")
        sug.list = K.List(sug, 26, function(l)
            local r = K.Row(l)
            r.role = r:CreateTexture(nil, "ARTWORK")
            r.role:SetSize(16, 16)
            r.role:SetPoint("LEFT", 10, 0)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(16, 16)
            r.cls:SetPoint("LEFT", 32, 0)
            r:Col("name", 54, 200, 12)
            r.cols.name:SetWordWrap(false)
            r:Col("lvl", 260, 30, 11, C.muted)
            r:Col("state", 296, 160, 10, C.muted)
            r.cols.state:SetWordWrap(false)
            r.inv = K.Button(r, L["Invite"], 66, 18, "ghost")
            r.inv:SetPoint("RIGHT", -4, 0)
            r.inv.label:SetFont(K.FONT, 10, "")
            r.inv:SetScript("OnClick", function(self) local e = self:GetParent().item if e then ns.InviteName(e.row.name) end end)
            return r
        end, function(r, e)
            local sw = p.sugW or 600
            local nameW = math.max(80, math.min(220, sw - 54 - 40 - 150 - 80))
            r.cols.name:SetWidth(nameW)
            r.cols.lvl:ClearAllPoints() r.cols.lvl:SetPoint("LEFT", 58 + nameW, 0)
            r.cols.state:ClearAllPoints() r.cols.state:SetPoint("LEFT", 92 + nameW, 0)
            r.cols.state:SetWidth(math.max(40, sw - 92 - nameW - 84))
            local ic = ROLE_ICON[e.role or ""]
            if ic then
                r.role:SetTexture(glyph(ic))
                local rc = ROLE_COL[e.role]
                r.role:SetVertexColor(rc[1], rc[2], rc[3])
                r.role:Show()
            else r.role:Hide() end
            local row = e.row
            U.ClassIcon(r.cls, row.class)
            r.cols.name:SetText(nameOf(row.name) .. (row.alt and ("  |cff666666" .. L["Alt"] .. "|r") or ""))
            r.cols.lvl:SetText(row.lvl)
            r.cols.state:SetText((row.online and ("|cff66db9e" .. L["online"] .. "|r") or L["offline"]) .. (e.guess and ("  |cff666666" .. L["(role unknown)"] .. "|r") or ""))
            r.inv:SetShown(row.online and not ns.isMe(row.name) and not (row.rec and row.rec.demo))
            r:SetAlpha(row.online and 1 or 0.8)
        end)
        sug.list.empty:SetText(L["Nobody free: all fitting characters are saved, too low or not attuned."])

        function p:Layout()
            local W = math.floor(self:GetWidth() or 0)
            if W < 200 then W = 700 end
            self.rects = {}
            local y = 0
            local tc = W >= 520 and 4 or 2
            local tw = math.floor((W - (tc - 1) * 8) / tc)
            for i, t in ipairs(self.tiles) do
                local ci, rr = (i - 1) % tc, math.floor((i - 1) / tc)
                place(self, "tile" .. i, t, ci * (tw + 8), y - rr * 72, tw, 64)
                t:Hide()   -- 0.5.847: Zahlen-Kacheln entfallen, die Karten je Raid darunter zeigen dasselbe
            end
            if sugRaid then
                for _, c in ipairs(self.cards) do c:Hide() end
                self.bar:Hide() self.hdr:Hide() self.list:Hide()
                self.sug:Show()
                place(self, "sug", self.sug, 0, y, W, nil)
                local s = self.sug
                local inner = W - 28
                local cc = inner >= 4 * 110 + 24 and 4 or 2
                local cw = math.floor((inner - (cc - 1) * 8) / cc)
                for i, ch in ipairs(s.chips) do
                    local ci, rr = (i - 1) % cc, math.floor((i - 1) / cc)
                    ch:ClearAllPoints()
                    ch:SetPoint("TOPLEFT", s, "TOPLEFT", 14 + ci * (cw + 8), -44 - rr * 50)
                    ch:SetSize(cw, 42)
                end
                local iy = -44 - math.ceil(#s.chips / cc) * 50
                s.info:ClearAllPoints()
                s.info:SetPoint("TOPLEFT", s, "TOPLEFT", 14, iy)
                s.info:SetWidth(inner)
                s.info:SetHeight(30)
                s.list:ClearAllPoints()
                s.list:SetPoint("TOPLEFT", s, "TOPLEFT", 6, iy - 34)
                s.list:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -4, 4)
                self.sugW = W - 10
                -- schmal: Sammel-Einladen ueber dem Kopf ausblenden, damit der Titel Platz hat
                s.invAllRoom = W >= 460
                return
            end
            self.sug:Hide()
            -- Raid-Karten: breit nebeneinander, schmal als Streifen untereinander
            local n = #self.cards
            local wide = W >= 600
            if wide then
                local cw = math.floor((W - (n - 1) * 10) / n)
                for i, c in ipairs(self.cards) do
                    place(self, "card" .. i, c, (i - 1) * (cw + 10), y, cw, 92)
                    c:Layout(cw, false)
                    c:Show()
                end
                y = y - 92 - 10
            else
                for i, c in ipairs(self.cards) do
                    place(self, "card" .. i, c, 0, y, W, 44)
                    c:Layout(W, true)
                    c:Show()
                    y = y - 50
                end
                y = y - 4
            end
            self.bar:Show()
            place(self, "bar", self.bar, 0, y, W, 24)
            self.cnt:SetShown(W >= 520)
            y = y - 30
            -- Spalten
            self.cols = columns(W - 8)
            local cols = self.cols
            self.hdr:Show()
            place(self, "hdr", self.hdr, 0, y, W, 20)
            self.hdr.name:ClearAllPoints() self.hdr.name:SetPoint("LEFT", cols.name[1], 0)
            self.hdr.lvl:ClearAllPoints() self.hdr.lvl:SetPoint("LEFT", cols.lvl[1], 0)
            for i, t in ipairs(self.hdr.raids) do
                t:ClearAllPoints()
                t:SetPoint("LEFT", self.hdr, "LEFT", cols.raids[i][1], 0)
                t:SetWidth(cols.raids[i][2])
            end
            y = y - 22
            self.list:Show()
            place(self, "list", self.list, 0, y, W, nil)
        end
        p:HookScript("OnSizeChanged", function(self) if self.Layout then self:Layout() self.list:Refresh() end end)
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
    end,
    refresh = function(p)
        if not p.tiles then return end
        p.seg:Select(filter.online and "online" or "all")
        p.twk:SetLabel(filter.twinks and L["Alts: on"] or L["Alts: off"])
        local rows = LK.Rows()
        local fresh = p.fresh and animOn()
        -- Zaehlen: je Charakter (Kacheln) und je Raid (Karten)
        local bound, free, locked = 0, 0, 0
        local per = {}
        for _, rd in ipairs(LK.RAIDS) do per[rd.key] = { bound = 0, free = 0, locked = 0, low = 0 } end
        for _, e in ipairs(rows) do
            local b, f, l = false, false, false
            for _, rd in ipairs(LK.RAIDS) do
                local st = LK.StateOf(e.name, rd.key, e.lvl)
                if per[rd.key][st] then per[rd.key][st] = per[rd.key][st] + 1 end
                if st == "bound" then b = true elseif st == "free" then f = true elseif st == "locked" then l = true end
            end
            if b then bound = bound + 1 end
            if f then free = free + 1 end
            if l then locked = locked + 1 end
        end
        local nr = LK.NextReset()
        local nrName = ""
        if nr then
            for _, rd in ipairs(LK.RAIDS) do if LK.NextReset(rd.key) == nr then nrName = L[rd.name] break end end
        end
        local total = #rows
        p.tiles[1]:Set(bound, L["Characters"], total > 0 and bound / total or nil, fresh)
        p.tiles[2]:Set(free, L["Characters"], total > 0 and free / total or nil, fresh)
        p.tiles[3]:Set(locked, L["Characters"], total > 0 and locked / total or nil, fresh)
        p.tiles[4]:Set(nr and fmtLeft(nr - ns.now()) or "-", nrName, nil, false)
        p:Layout()
        for i, c in ipairs(p.cards) do
            local rd = LK.RAIDS[i]
            local n = per[rd.key]
            c:SetData(n, (n.bound or 0) + (n.free or 0) + (n.locked or 0) + (n.low or 0), LK.NextReset(rd.key), fresh)
        end
        p.cnt:SetText((L["%d characters"]):format(total))
        if p.fresh then
            for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.06) end
        end
        p.fresh = false
        if sugRaid then
            local s = p.sug
            local rd = LK.RAID_BY[sugRaid]
            if not rd then sugRaid = nil return ns.RefreshPage("lockouts") end
            local list, need = LK.Suggest(sugRaid)
            s.cur = list
            local t, h, d, on = 0, 0, 0, 0
            for _, e in ipairs(list) do
                if e.role == "TANK" then t = t + 1 elseif e.role == "HEALER" then h = h + 1 else d = d + 1 end
                if e.row.online then on = on + 1 end
            end
            s.head.text:SetText(K.Upper(L[rd.name]) .. "  ·  " .. K.Upper(L["Free group"]))
            s.head:SetCount(#list .. " / " .. rd.size)
            local vals = { { t, need[1] }, { h, need[2] }, { d, math.max(0, rd.size - need[1] - need[2]) }, { on, #list } }
            for i, ch in ipairs(s.chips) do
                local v, nd = vals[i][1], vals[i][2]
                local ok = v >= nd
                if p.animSug and animOn() and v > 0 then K.CountUp(ch.val, v, 0.5, function(x) return tostring(math.floor(x + 0.5)) .. " |cff888888/ " .. nd .. "|r" end)
                else ch.val:SetText(v .. " |cff888888/ " .. nd .. "|r") end
                ch.val:SetTextColor((ok or i == 4) and C.text[1] or C.amber[1], (ok or i == 4) and C.text[2] or C.amber[2], (ok or i == 4) and C.text[3] or C.amber[3])
            end
            s.info:SetText(L["One character per player (online, main and higher level first). Roles from the profiles."])
            s.invAll:SetShown(on > 0 and s.invAllRoom ~= false)
            s.list:SetData(list)
            p.animSug = false
        else
            p.list:SetData(rows)
        end
    end,
})
end)

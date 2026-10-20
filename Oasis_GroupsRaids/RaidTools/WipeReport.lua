-- Oasis: Kampfberichte - Auswertung nach jedem Bosskampf (Sieg oder Wipe)
--  * Beginn: ENCOUNTER_START; Ersatz, falls der Client das nicht meldet: Kampfbeginn in einer Raid-Instanz
--    gegen einen Boss im Ziel (PLAYER_REGEN_DISABLED), Ende dann mit PLAYER_REGEN_ENABLED
--  * Tode in Reihenfolge: eigener Tod (PLAYER_DEAD, exakt), Kampflog UNIT_DIED / UNIT_DIED-Ereignis (falls lesbar),
--    sonst sekuendliche Abfrage UnitIsDeadOrGhost der Gruppe + Abfrage nach dem Kampf
--  * jeder Client meldet "ich starb um t" (WRME); der Anfuehrer (oder ersatzweise ein anderer) teilt den Bericht (WREP)
--  * Kampfdauer, Boss-HP beim Wipe (falls lesbar), C_DamageMeter NACH dem Kampf (per pcall, geheime Werte fallen weg)
--  * Seite "Kampfberichte" (Nav-Gruppe Raid): Bosse -> Versuche -> Zeitstrahl der Tode, erster Tod, wiederkehrende Muster
--  * /oa probe kampf: zeigt, was C_DamageMeter im Spiel liefert
-- Ergaenzt Badges.lua (Raid-Momente) und Chronicle (Bosssiege) - hier geht es um das "Warum" eines Versuchs.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Modul Raidwerkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Core\Diagnostics\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C, Store, Comm = ns.K, ns.K.C, ns.Store, ns.Comm
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

local WR = {}
ns.WipeReport = WR
local COLL = "wipes"
local KEEP = 60 * 86400
if ns.ICONS then ns.ICONS.wipes = ns.MEDIA .. "icons\\deaths" end
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "raid" then
        local has
        for _, k in ipairs(g.pages) do if k == "wipes" then has = true end end
        if not has then g.pages[#g.pages + 1] = "wipes" end
    end
end
-- /oa probe (gleiches Muster wie RaidPrep.lua; wer zuerst laedt, legt den Verteiler an)
ns.Probes = ns.Probes or {}
if not ns._ProbesHooked then
    ns._ProbesHooked = true
    local prev = ns.slash.probe
    ns.slash.probe = function(rest)
        local topic = ((rest or ""):match("^(%S*)") or ""):lower()
        local fn = ns.Probes[topic]
        if fn then
            local ok, e = pcall(fn, rest)
            if not ok then ns.print("probe " .. topic .. ": " .. tostring(e)) end
            return
        end
        if prev then return prev(rest) end
        local keys = {}
        for k in pairs(ns.Probes) do keys[#keys + 1] = k end
        table.sort(keys)
        ns.print(L["Probe topics: "] .. table.concat(keys, ", "))
    end
end

local function S() return ns.db.settings end
local function shareOn() return S().wrShare ~= false end
ns.AddPageSettings("wipes", function(det, y)
    local t = K.Toggle(det, L["Share fight reports with the guild"], function() return shareOn() end, function(v) S().wrShare = v end,
        L["After every boss fight: duration, deaths, boss health, damage/healing (if readable)"])
    t:SetPoint("TOPLEFT", 14, y)
    t:SetWidth(600)
    det.t[#det.t + 1] = t
    y = y - 46
    local t2 = K.Toggle(det, L["Short summary in the chat window"], function() return S().wrPrint == true end, function(v) S().wrPrint = v end,
        L["Just for you: one line with duration and first death after the fight"])
    t2:SetPoint("TOPLEFT", 14, y)
    t2:SetWidth(600)
    det.t[#det.t + 1] = t2
    return y - 50
end)

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function plain(v)
    if v == nil then return nil end
    local ok, s = pcall(issecret, v)
    if ok and s then return nil end
    return v
end
local function groupUnits()
    local out = {}
    if ns.Group.IsInRaid() then for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else out[1] = "player" for i = 1, 4 do out[#out + 1] = "party" .. i end end
    return out
end
local function unitName(u)
    if not UnitExists(u) then return nil end
    return ns.fullName(ns.safe(ns.UnitName(u)))
end
local function deadUnit(u)
    local ok, v = pcall(UnitIsDeadOrGhost, u)
    if not ok then return nil end
    v = ns.safe(v)
    if v == nil then return nil end
    return v and true or false
end
local function bossHP()
    for i = 1, 5 do
        local u = "boss" .. i
        if UnitExists(u) then
            local ok, h, m = pcall(function() return UnitHealth(u), UnitHealthMax(u) end)
            if ok then
                h, m = ns.safe(h), ns.safe(m)
                if type(h) == "number" and type(m) == "number" and m > 0 then return math.floor(h / m * 1000 + 0.5) / 10 end
            end
        end
    end
    if UnitExists("target") and not UnitIsPlayer("target") then
        local ok, h, m = pcall(function() return UnitHealth("target"), UnitHealthMax("target") end)
        if ok then
            h, m = ns.safe(h), ns.safe(m)
            if type(h) == "number" and type(m) == "number" and m > 0 then return math.floor(h / m * 1000 + 0.5) / 10 end
        end
    end
end
local function isBossTarget()
    if not UnitExists("target") or UnitIsPlayer("target") then return false end
    local cl = ns.safe(UnitClassification and UnitClassification("target"))
    local lvl = ns.safe(UnitLevel("target"))
    return cl == "worldboss" or lvl == -1
end
local function instName()
    if not GetInstanceInfo then return "" end
    local ok, n = pcall(GetInstanceInfo)
    return ok and ns.safe(n) or ""
end

------------------------------------------------------------------------
-- Laufender Kampf
------------------------------------------------------------------------
local cur            -- { boss, eid, start (GetTime), ts, deaths = { [name] = { t, src } }, hp, viaEnc }
local poll
local SRC_RANK = { self = 4, msg = 3, log = 2, poll = 1, after = 0 }
local function noteDeath(name, t, src)
    if not cur or not name then return end
    local d = cur.deaths[name]
    if d and (SRC_RANK[d.src] or 0) >= (SRC_RANK[src] or 0) then return end
    cur.deaths[name] = { t = t, src = src }
end
local function startFight(boss, eid, viaEnc)
    cur = { boss = boss or "?", eid = eid, start = GetTime(), ts = ns.now(), deaths = {}, viaEnc = viaEnc, inst = instName(),
        size = ns.Group.Num() }
    if poll then poll:Cancel() end
    poll = ns.Every(1, function()
        if not cur then return end
        local t = GetTime() - cur.start
        for _, u in ipairs(groupUnits()) do
            local n = unitName(u)
            if n and deadUnit(u) == true and not cur.deaths[n] then noteDeath(n, t, "poll") end
        end
        local hp = bossHP()
        if hp then cur.hp = hp end
    end)
end

-- Kampfdaten C_DamageMeter: nur NACH dem Kampf, jede Zahl auf "geheim" pruefen
local DM_TYPES = { { "DamageDone", "dmg" }, { "HealingDone", "heal" } }
local function dmSources(session)
    if type(session) ~= "table" then return nil end
    local list = session.combatSources or session.sources or session.combatants or session
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, s in ipairs(list) do
        if type(s) == "table" then
            local name = plain(s.name or s.sourceName)
            local amt = plain(s.totalAmount or s.amount or s.total)
            if type(name) == "string" and type(amt) == "number" then out[#out + 1] = { n = name, v = amt } end
        end
    end
    table.sort(out, function(a, b) return a.v > b.v end)
    return #out > 0 and out or nil
end
local function readMeter()
    local DM = C_DamageMeter
    if type(DM) ~= "table" then return nil end
    local res = {}
    local E = Enum and Enum.DamageMeterType
    for _, tp in ipairs(DM_TYPES) do
        local typ = E and E[tp[1]]
        local session
        if typ ~= nil then
            local ST = Enum and Enum.DamageMeterSessionType
            if DM.GetCombatSessionFromType and ST then
                local ok, s = pcall(DM.GetCombatSessionFromType, ST.Current or ST.LastFight or 1, typ)
                if ok then session = s end
            end
            if not session and DM.GetAvailableCombatSessions and DM.GetCombatSessionFromID then
                local ok, list = pcall(DM.GetAvailableCombatSessions)
                if ok and type(list) == "table" and #list > 0 then
                    local last = list[#list]
                    local id = type(last) == "table" and (last.sessionID or last.id) or last
                    local ok2, s = pcall(DM.GetCombatSessionFromID, id, typ)
                    if ok2 then session = s end
                end
            end
        end
        local src = dmSources(session)
        if src then
            local parts = {}
            for i = 1, math.min(10, #src) do parts[#parts + 1] = ("%s~%d"):format(src[i].n:gsub("[~|]", ""), math.floor(src[i].v)) end
            res[tp[2]] = table.concat(parts, "|")
        end
    end
    return next(res) and res or nil
end

-- Tode kodieren: "Name~t~quelle|..." nach Zeit sortiert (ohne Zeit hinten)
local function encodeDeaths(deaths)
    local list = {}
    for n, d in pairs(deaths) do list[#list + 1] = { n = n, t = d.t, src = d.src } end
    table.sort(list, function(a, b)
        if (a.t ~= nil) ~= (b.t ~= nil) then return a.t ~= nil end
        if a.t and b.t and a.t ~= b.t then return a.t < b.t end
        return a.n < b.n
    end)
    local parts = {}
    for _, d in ipairs(list) do parts[#parts + 1] = ("%s~%s~%s"):format(d.n:gsub("[~|]", ""), d.t and ("%.1f"):format(d.t) or "", d.src or "") end
    return table.concat(parts, "|"), list[1] and list[1].t and list[1].n or nil
end
function WR.DecodeDeaths(s)
    local out = {}
    for part in tostring(s or ""):gmatch("[^|]+") do
        local n, t, src = part:match("^(.-)~(.-)~(.*)$")
        if n then out[#out + 1] = { n = n, t = tonumber(t), src = src } end
    end
    return out
end
function WR.DecodeMeter(s)
    local out = {}
    for part in tostring(s or ""):gmatch("[^|]+") do
        local n, v = part:match("^(.-)~(%d+)$")
        if n then out[#out + 1] = { n = n, v = tonumber(v) } end
    end
    return out
end

------------------------------------------------------------------------
-- Berichte speichern, zusammenfuehren, teilen
------------------------------------------------------------------------
-- derselbe Versuch von verschiedenen Clients: gleicher Boss, Beginn hoechstens 30 s auseinander
function WR.FindSame(boss, ts)
    for _, r in ipairs(Store.List(COLL)) do
        if r.boss == boss and math.abs((r.ts or 0) - (ts or 0)) <= 30 then return r end
    end
end
local function mergeDeaths(a, b)
    local map = {}
    for _, d in ipairs(WR.DecodeDeaths(a)) do map[d.n] = { t = d.t, src = d.src } end
    for _, d in ipairs(WR.DecodeDeaths(b)) do
        local o = map[d.n]
        if not o or (SRC_RANK[d.src] or 0) > (SRC_RANK[o.src] or 0) then map[d.n] = { t = d.t, src = d.src } end
    end
    return encodeDeaths(map)
end
local function storeReport(rec, fromNet, sender)
    local old = WR.FindSame(rec.boss, rec.ts)
    if old and old.id ~= rec.id then
        -- vorhandenen Versuch ergaenzen (Tode vereinen, fehlende Werte uebernehmen)
        local m = {}
        for k, v in pairs(old) do m[k] = v end
        m.deaths, m.first = mergeDeaths(old.deaths, rec.deaths)
        for _, k in ipairs({ "hp", "dmg", "heal", "dur", "inst" }) do if (m[k] == nil or m[k] == "") and rec[k] ~= nil then m[k] = rec[k] end end
        if m.ok == nil then m.ok = rec.ok end
        m.u = math.max(old.u or 0, rec.u or 0) + 1
        Store.merge(COLL, m)
        return m
    end
    Store.merge(COLL, rec, fromNet, sender)
    return rec
end
local pendingMe = {}   -- Meldungen "ich starb", die vor dem Bericht ankamen
local function applyMe(sender, boss, ts, t)
    local r = WR.FindSame(boss, ts)
    if not r then
        pendingMe[#pendingMe + 1] = { who = sender, boss = boss, ts = ts, t = t, at = GetTime() }
        return
    end
    local m = {}
    for k, v in pairs(r) do m[k] = v end
    m.deaths, m.first = mergeDeaths(r.deaths, ("%s~%.1f~msg"):format(sender:gsub("[~|]", ""), t))
    m.u = (r.u or 0) + 1
    Store.merge(COLL, m)
end
local function flushPending()
    for i = #pendingMe, 1, -1 do
        local p = pendingMe[i]
        if WR.FindSame(p.boss, p.ts) then
            table.remove(pendingMe, i)
            applyMe(p.who, p.boss, p.ts, p.t)
        elseif GetTime() - p.at > 120 then
            table.remove(pendingMe, i)
        end
    end
end

local function sendReport(rec)
    if not shareOn() or not IsInGuild() then return end
    local send = {}
    for k, v in pairs(rec) do if k ~= "by" and k:sub(1, 1) ~= "_" then send[k] = v end end
    Comm.SendEx({ ch = "GUILD", bulk = true }, "WREP", Comm.encodeRecord(send))
end
Comm.On("WREP", function(sender, _, s)
    if not s or #s > 6000 then return end
    if not SEC.Rate("wrep:" .. sender, 3) then return end
    local rec = Comm.decodeRecord(s)
    if not rec then return end
    if not rec.boss or not rec.ts or type(rec.id) ~= "string" or #rec.id > 80 then return end
    -- Felder entschaerfen, Zeiten plausibel, fremde Berichte nicht ueberschreiben
    local n = 0
    for k, v in pairs(rec) do
        n = n + 1
        if n > 60 then rec[k] = nil
        elseif type(v) == "string" then rec[k] = SEC.Text(v, k == "deaths" and 3000 or 200)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then rec[k] = 0 end
    end
    rec.demo, rec.sim = nil, nil
    rec.ts = SEC.Num(rec.ts, 0, ns.now() + 300)
    if not rec.ts then return end
    local old = Store.Get(COLL, rec.id)
    if old and old.by and old.by ~= sender then return end
    rec.by = sender
    rec.u = math.min(tonumber(rec.u) or ns.now(), ns.now() + 300)
    local sent = WR.sentFor
    if sent and sent.boss == rec.boss and math.abs(sent.ts - rec.ts) <= 30 then sent.seen = true end
    storeReport(rec, true, sender)
    flushPending()
    ns.RefreshPage("wipes")
end)
Comm.On("WRME", function(sender, _, boss, ts, t)
    ts, t = SEC.Num(ts, 0, ns.now() + 300), SEC.Num(t, 0, 7200)
    if not boss or not ts or not t then return end
    boss = SEC.Text(boss, 80)
    if not SEC.Rate("wrme:" .. sender, 2) then return end
    if #pendingMe >= 60 then table.remove(pendingMe, 1) end   -- Warteliste begrenzen
    applyMe(sender, boss, ts, t)
    ns.RefreshPage("wipes")
end)

local function finishFight(success)
    local f = cur
    if not f then return end
    cur = nil
    if poll then poll:Cancel() poll = nil end
    local dur = GetTime() - f.start
    if dur < 8 and not next(f.deaths) then return end   -- Fehlstart / nur kurz angezogen
    -- nach dem Kampf: wer jetzt tot ist und noch fehlt, kommt ohne Zeit dazu
    for _, u in ipairs(groupUnits()) do
        local n = unitName(u)
        if n and deadUnit(u) == true and not f.deaths[n] then f.deaths[n] = { src = "after" } end
    end
    local hp = bossHP()
    if success == true then hp = 0 elseif hp == nil then hp = f.hp end
    local meter = readMeter()
    -- 0.5.617: Tode von Fremden (nicht in der Gilde) nicht mit der Gilde teilen
    local gd = {}
    for name, d in pairs(f.deaths or {}) do
        local g = ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(name)
        if g ~= false then gd[name] = d end
    end
    local deaths, first = encodeDeaths(gd)
    local rec = {
        id = ns.newId("wr"), boss = f.boss, inst = f.inst or "", ts = f.ts, dur = math.floor(dur + 0.5),
        ok = success, hp = hp, deaths = deaths, first = first or "", size = f.size or 0, by = ns.me(), u = ns.now(),
        dmg = meter and meter.dmg or nil, heal = meter and meter.heal or nil,
    }
    rec = storeReport(rec)
    ns.RefreshPage("wipes")
    if S().wrPrint then
        ns.print((L["Fight report %s: %s, %s, first death: %s"]):format(f.boss, success == true and L["Kill"] or success == false and L["Wipe"] or L["End"],
            WR.FmtDur(dur), first and ns.displayName(first) or "-"))
    end
    -- eigener Tod: kleine Meldung an alle (exakte Zeit fuer die Reihenfolge)
    local mine = f.deaths[ns.me() or ""]
    if mine and mine.src == "self" and IsInGuild() and shareOn() then
        ns.After(math.random(5, 30) / 10, function() Comm.SendEx({ ch = "GUILD", bulk = true }, "WRME", f.boss, f.ts, ("%.1f"):format(mine.t)) end)
    end
    -- ganzer Bericht: Anfuehrer sofort, sonst nur, wenn nach kurzer Zeit noch keiner kam
    WR.sentFor = { boss = f.boss, ts = f.ts }
    local lead = ns.Group.IsInGroup() and ns.Group.IsLeader()
    local wait = lead and 1 or (8 + math.random(0, 80) / 10)
    local mark = WR.sentFor
    ns.After(wait, function()
        if mark.seen then return end
        local r = WR.FindSame(f.boss, f.ts) or rec
        sendReport(r)
    end)
end

-- Ereignisse
ns.On("ENCOUNTER_START", function(eid, name)
    startFight(ns.safe(name) or "?", ns.safe(eid), true)
end)
ns.On("ENCOUNTER_END", function(_, name, _, _, success)
    if not cur then return end
    local s = ns.safe(success)
    local res
    if s == 1 or s == true then res = true elseif s == 0 or s == false then res = false end
    finishFight(res)
end)
-- Ersatz ohne Encounter-Ereignis: Raid-Instanz + Boss im Ziel
ns.On("PLAYER_REGEN_DISABLED", function()
    if cur then return end
    local inInst, kind = IsInInstance()
    if not inInst or kind ~= "raid" then return end
    if isBossTarget() then startFight(ns.safe(ns.UnitName("target")) or "?", nil, false) end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    local f = cur
    if not f then return end
    if f.viaEnc then
        -- ENCOUNTER_END sollte gleich folgen; kommt es nicht (z.B. Client meldet es nicht), selbst abschliessen
        ns.After(6, function()
            if cur ~= f then return end
            local alive = false
            for _, u in ipairs(groupUnits()) do if UnitExists(u) and deadUnit(u) == false then alive = true break end end
            local res
            if not alive then res = false end
            finishFight(res)
        end)
        return
    end
    ns.After(1, function()
        if cur ~= f then return end
        local dead = UnitExists("target") and ns.safe(UnitIsDead("target"))
        local anyAlive = false
        for _, u in ipairs(groupUnits()) do if UnitExists(u) and deadUnit(u) == false then anyAlive = true break end end
        local res
        if dead == true then res = true elseif not anyAlive then res = false end
        finishFight(res)
    end)
end)
ns.On("PLAYER_DEAD", function()
    if cur then noteDeath(ns.me(), GetTime() - cur.start, "self") end
end)
-- Kampflog (falls der Client es Addons noch gibt und die Werte lesbar sind)
-- Kampflog NICHT anmelden: COMBAT_LOG_EVENT_UNFILTERED ist in Forever/Midnight fuer Addons verboten
-- (RegisterEvent loest 'Oasis wurde geblockt' aus).
ns.On("UNIT_DIED", function(a)
    if not cur then return end
    a = plain(a)
    if type(a) ~= "string" then return end
    local name
    if UnitExists(a) then name = unitName(a)
    elseif a:find("^Player%-") and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, a)
        if ok then name = ns.fullName(plain(n)) end
    end
    if name then noteDeath(name, GetTime() - cur.start, "log") end
end)

------------------------------------------------------------------------
-- Auswertung
------------------------------------------------------------------------
function WR.FmtDur(s)
    s = math.floor((s or 0) + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end
local function demoOn() return ns.Demo and ns.Demo.IsActive() end
-- Sim-Versuche (Raid-Simulator, demo-sim-ID) nur waehrend der Simulation
local function visible(r)
    if r.sim then return ns.Sim and ns.Sim.Active() or false end
    return not r.demo or demoOn()
end
-- Bosse mit Versuchen: { boss, inst, n, kills, last, list = {...} }
function WR.Bosses()
    local by, out = {}, {}
    for _, r in ipairs(Store.List(COLL, visible)) do
        local b = by[r.boss]
        if not b then b = { boss = r.boss, inst = r.inst, n = 0, kills = 0, last = 0, list = {} } by[r.boss] = b out[#out + 1] = b end
        b.n = b.n + 1
        if r.ok == true then b.kills = b.kills + 1 end
        if (r.ts or 0) > b.last then b.last = r.ts or 0 end
        b.list[#b.list + 1] = r
    end
    for _, b in ipairs(out) do
        table.sort(b.list, function(a, c) return (a.ts or 0) < (c.ts or 0) end)
        for i, r in ipairs(b.list) do r._nr = i end
    end
    table.sort(out, function(a, b) return a.last > b.last end)
    return out
end
-- wiederkehrende Muster eines Bosses (oder aller): wer stirbt oft zuerst, wer oft ueberhaupt
function WR.Patterns(list)
    local firsts, deaths, n = {}, {}, 0
    for _, r in ipairs(list) do
        n = n + 1
        local ds = WR.DecodeDeaths(r.deaths)
        if ds[1] and ds[1].t then firsts[ds[1].n] = (firsts[ds[1].n] or 0) + 1 end
        for _, d in ipairs(ds) do deaths[d.n] = (deaths[d.n] or 0) + 1 end
    end
    local out = {}
    for name, c in pairs(firsts) do
        if c >= 2 then out[#out + 1] = { w = c * 10 + 1, text = (L["%s dies first %dx"]):format(ns.displayName(name), c), name = name } end
    end
    for name, c in pairs(deaths) do
        if n >= 3 and c >= math.max(3, math.ceil(n * 0.6)) then
            out[#out + 1] = { w = c, text = (L["%s dies in %d of %d attempts"]):format(ns.displayName(name), c, n), name = name }
        end
    end
    table.sort(out, function(a, b) return a.w > b.w end)
    return out
end

------------------------------------------------------------------------
-- Demo
------------------------------------------------------------------------
function WR.SeedDemo()
    local now = ns.now()
    local base = now - 2 * 86400
    local runs = {
        { "Onyxia", "Onyxia's Lair", 0, 212, false, 38.5, "Zul'mira~41.2~self|Hoknar~63.0~msg|Mokrash~88.4~poll|Yenzi~131.9~log" },
        { "Onyxia", "Onyxia's Lair", 600, 274, false, 21.0, "Zul'mira~38.7~msg|Drogbar~150.2~log|Hoknar~171.0~poll|Nakira~250.5~msg" },
        { "Onyxia", "Onyxia's Lair", 1300, 301, false, 9.4, "Zul'mira~44.1~self|Yenzi~190.3~msg|Hoknar~299.0~after" },
        { "Onyxia", "Onyxia's Lair", 2000, 318, true, 0, "Mokrash~120.0~poll|Yenzi~201.5~msg" },
        { "Archimonde", "Hyjal", 86400, 402, false, 54.0, "Tavira~95.0~msg|Grukthar~140.0~self|Hoknar~141.5~log" },
        { "Archimonde", "Hyjal", 87200, 377, false, 47.5, "Hoknar~80.3~msg|Tavira~102.4~poll|Nakira~330.0~msg" },
    }
    for i, d in ipairs(runs) do
        local dmg = "Hoknar~412000|Mokrash~398500|Yenzi~350200|Zul'mira~120400"
        Store.merge(COLL, { id = "demo-wr-" .. i, demo = true, boss = d[1], inst = d[2], ts = base + d[3], dur = d[4], ok = d[5], hp = d[6],
            deaths = d[7], first = d[7]:match("^(.-)~") or "", size = 20, by = ns.fullName("Grukthar"), u = base + d[3] + d[4],
            dmg = i % 2 == 0 and dmg or nil })
    end
    ns.RefreshPage("wipes")
end
function WR.RemoveDemo()
    local c = ns.db.store[COLL] or {}
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    ns.RefreshPage("wipes")
end

------------------------------------------------------------------------
-- Seite (Neugestaltung): Kopf-Kacheln, Boss-Liste (schmal: Auswahlknopf), rechts eine Scrollflaeche mit
-- Kopf-Karte, Verlauf aller Versuche (Balken), Zeitstrahl der Tode, Schaden/Heilung und Mustern
------------------------------------------------------------------------
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SRC_TEXT = { self = "self-reported", msg = "reported via Oasis", log = "combat log", poll = "observed (approx.)", after = "dead after the fight" }
local CHART_H = 70
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function glyph(n) return ns.MEDIA .. "icons\\" .. n end
local function resultText(r)
    if r.ok == true then return "|cff66db9e" .. L["Kill"] .. "|r" end
    if r.ok == false then return "|cffe64047" .. L["Wipe"] .. "|r" end
    return "|cff9a9aa0" .. L["End"] .. "|r"
end
local function resultCol(r) return r.ok == true and C.mint or r.ok == false and C.red or C.dim end
-- Fortschritt eines Versuchs (0..1): Sieg = 1, sonst verlorenes Boss-Leben
local function progressOf(r)
    if r.ok == true then return 1 end
    local hp = tonumber(r.hp)
    if not hp then return 0 end
    return math.max(0, math.min(1, (100 - hp) / 100))
end
local function classOf(name)
    local m = ns.Group and ns.Group.Member and ns.Group.Member(name)
    if type(m) == "table" and m.class then return m.class end
    if ns.Radar and ns.Radar.ClassOf then
        local ok, c = pcall(ns.Radar.ClassOf, name)
        if ok and c then return c end
    end
    return nil
end
local function coloredName(name)
    local cls = classOf(name)
    if cls then return ns.colorName(name, cls) end
    return ns.displayName(name)
end
local function fmtNum(v) return v >= 1000000 and ("%.2fM"):format(v / 1000000) or v >= 1000 and ("%.1fk"):format(v / 1000) or tostring(v) end
local function place(body, key, f, x, y, w, h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
    if h then f:SetSize(w, h) else f:SetWidth(w) f:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", x, 0) end
    body.rects[key] = { x = x, y = y, w = w, h = h }
end

-- kleine Kennzahl-Box (Kopf-Karte)
local function newStat(parent, label, color)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = K.Fill(f, C.raised)
    K.Border(f, C.line)
    f.top = f:CreateTexture(nil, "ARTWORK")
    f.top:SetPoint("TOPLEFT") f.top:SetPoint("TOPRIGHT") f.top:SetHeight(2)
    f.top:SetColorTexture(color[1], color[2], color[3], 0.85)
    f.val = K.Title(f, 15, C.text)
    f.val:SetPoint("TOPLEFT", 10, -8)
    f.val:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.val:SetWordWrap(false)
    f.lab = K.Text(f, 9, C.muted)
    f.lab:SetPoint("BOTTOMLEFT", 10, 7)
    f.lab:SetText(K.Upper(label))
    return f
end

local function buildDetail(p, ct)
    local U = ns.RCUI
    -- a) Kopf-Karte
    local hd = U.Card(ct, C.red)
    p.hd = hd
    hd.title = K.Title(hd, 16, C.text)
    hd.title:SetPoint("TOPLEFT", 14, -12)
    hd.title:SetPoint("RIGHT", hd, "RIGHT", -100, 0)
    hd.title:SetWordWrap(false)
    hd.pill = K.Badge(hd, 18)
    hd.pill:SetPoint("TOPRIGHT", -12, -12)
    hd.sub = K.Text(hd, 11, C.muted)
    hd.sub:SetPoint("TOPLEFT", 14, -34)
    hd.sub:SetPoint("RIGHT", hd, "RIGHT", -14, 0)
    hd.sub:SetWordWrap(false)
    hd.stats = {
        newStat(hd, L["Duration"], C.blue), newStat(hd, L["Deaths"], C.red),
        newStat(hd, L["Boss health"], C.amber), newStat(hd, L["First death"], C.pink),
    }
    function hd:Layout(w)
        local inner = w - 28
        local per = inner >= 4 * 92 + 24 and 4 or 2
        local bw = math.floor((inner - (per - 1) * 8) / per)
        for i, s in ipairs(self.stats) do
            local ci, rr = (i - 1) % per, math.floor((i - 1) / per)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", self, "TOPLEFT", 14 + ci * (bw + 8), -58 - rr * 52)
            s:SetSize(bw, 44)
        end
        return 58 + math.ceil(#self.stats / per) * 52 + 6
    end
    -- b) Verlauf aller Versuche
    local ch = U.Card(ct, C.amber)
    p.chart = ch
    ch.head = K.GameHead(ch, L["All attempts"], C.amber)
    ch.head:SetPoint("TOPLEFT", 14, -12)
    ch.head:SetPoint("RIGHT", ch, "RIGHT", -14, 0)
    ch.base = ch:CreateTexture(nil, "ARTWORK")
    ch.base:SetHeight(1)
    ch.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    ch.bars = {}
    ch.hint = K.Text(ch, 10, C.dim)
    ch.hint:SetWordWrap(false)
    function ch:Bar(i)
        local b = self.bars[i]
        if b then return b end
        b = CreateFrame("Button", nil, self)
        b.track = b:CreateTexture(nil, "BACKGROUND")
        b.track:SetAllPoints()
        b.track:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetPoint("BOTTOMLEFT") b.fill:SetPoint("BOTTOMRIGHT")
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", 0, 3) b.sel:SetPoint("TOPRIGHT", 0, 3) b.sel:SetHeight(2)
        b.sel:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.08)
        b.nr = K.Text(self, 9, C.dim, "CENTER")
        b:SetScript("OnClick", function(s) if s.run then WR.selRun = s.run.id p.animRun = true ns.RefreshPage("wipes") end end)
        b:SetScript("OnEnter", function(s)
            local r = s.run
            if not r then return end
            local ds = WR.DecodeDeaths(r.deaths)
            K.ShowTip(s, { (L["Attempt %d"]):format(r._nr or 0) .. "  ·  " .. resultText(r),
                ns.fmtDate(r.ts) .. "  ·  " .. WR.FmtDur(r.dur) .. "  ·  " .. (L["%d deaths"]):format(#ds),
                (r.ok ~= true and r.hp) and (L["Boss at %.1f%%"]):format(r.hp) or nil })
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.bars[i] = b
        return b
    end
    -- c) Zeitstrahl der Tode
    local tl = U.Card(ct, C.red)
    p.tl = tl
    tl.head = K.GameHead(tl, L["Death timeline"], C.red)
    tl.head:SetPoint("TOPLEFT", 14, -12)
    tl.head:SetPoint("RIGHT", tl, "RIGHT", -14, 0)
    tl.bar = CreateFrame("Frame", nil, tl)
    K.Fill(tl.bar, C.field)
    tl.prog = tl.bar:CreateTexture(nil, "BORDER")
    tl.prog:SetPoint("TOPLEFT") tl.prog:SetPoint("BOTTOMLEFT")
    tl.prog:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.12)
    tl.t0 = K.Text(tl, 10, C.dim) tl.t0:SetText("0:00")
    tl.tm = K.Text(tl, 10, C.dim, "CENTER")
    tl.t1 = K.Text(tl, 10, C.dim, "RIGHT")
    tl.marks, tl.rows = {}, {}
    tl.none = K.Text(tl, 12, C.mint)
    tl.none:SetText(L["Nobody died – clean run."])
    function tl:Mark(i)
        local m = self.marks[i]
        if m then return m end
        m = CreateFrame("Frame", nil, self.bar)
        m:SetSize(12, 22)
        m.ring = m:CreateTexture(nil, "ARTWORK")
        m.ring:SetTexture(DOT)
        m.ring:SetSize(12, 12)
        m.ring:SetPoint("CENTER")
        m.t = m:CreateTexture(nil, "OVERLAY")
        m.t:SetTexture(DOT)
        m.t:SetSize(8, 8)
        m.t:SetPoint("CENTER")
        m:EnableMouse(true)
        m:SetScript("OnEnter", function(s) if s.tip then K.ShowTip(s, s.tip) end end)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.marks[i] = m
        return m
    end
    function tl:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, self)
        r:SetHeight(22)
        r.stripe = r:CreateTexture(nil, "BACKGROUND")
        r.stripe:SetAllPoints()
        r.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
        r.nr = K.Text(r, 11, C.dim, "RIGHT")
        r.nr:SetPoint("LEFT", 0, 0) r.nr:SetWidth(20)
        r.t = K.Text(r, 11, C.muted)
        r.t:SetPoint("LEFT", 28, 0) r.t:SetWidth(40)
        r.cls = r:CreateTexture(nil, "ARTWORK")
        r.cls:SetSize(14, 14)
        r.cls:SetPoint("LEFT", 72, 0)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 92, 0)
        r.name:SetWordWrap(false)
        r.src = K.Text(r, 10, C.dim, "RIGHT")
        r.src:SetPoint("RIGHT", -4, 0)
        r.src:SetWordWrap(false)
        self.rows[i] = r
        return r
    end
    -- d) Schaden / Heilung
    local mt = U.Card(ct, C.blue)
    p.mt = mt
    mt.head = K.GameHead(mt, L["Damage & healing"], C.blue)
    mt.head:SetPoint("TOPLEFT", 14, -12)
    mt.head:SetPoint("RIGHT", mt, "RIGHT", -14, 0)
    mt.none = K.Text(mt, 11, C.dim)
    mt.none:SetWordWrap(true)
    mt.none:SetText(L["Damage/healing: not readable or not transmitted."])
    mt.cols = {}
    for k = 1, 2 do
        local col = { lab = K.Text(mt, 10, C.dim), lines = {} }
        col.lab:SetText(K.Upper(L[k == 1 and "Damage" or "Healing"]))
        for j = 1, 5 do
            local ln = CreateFrame("Frame", nil, mt)
            ln:SetHeight(18)
            ln.track = ln:CreateTexture(nil, "BACKGROUND")
            ln.track:SetPoint("BOTTOMLEFT") ln.track:SetPoint("BOTTOMRIGHT") ln.track:SetHeight(3)
            ln.track:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
            ln.fill = ln:CreateTexture(nil, "ARTWORK")
            ln.fill:SetPoint("BOTTOMLEFT") ln.fill:SetHeight(3)
            ln.name = K.Text(ln, 11, C.text)
            ln.name:SetPoint("TOPLEFT", 0, -1)
            ln.name:SetWordWrap(false)
            ln.val = K.Text(ln, 11, C.muted, "RIGHT")
            ln.val:SetPoint("TOPRIGHT", 0, -1)
            col.lines[j] = ln
        end
        mt.cols[k] = col
    end
    -- e) Muster
    local pt = U.Card(ct, C.pink)
    p.pt = pt
    pt.head = K.GameHead(pt, L["Patterns"], C.pink)
    pt.head:SetPoint("TOPLEFT", 14, -12)
    pt.head:SetPoint("RIGHT", pt, "RIGHT", -14, 0)
    pt.lines = {}
    for j = 1, 4 do
        local ln = CreateFrame("Frame", nil, pt)
        ln:SetHeight(20)
        ln.dot = ln:CreateTexture(nil, "ARTWORK")
        ln.dot:SetTexture(DOT)
        ln.dot:SetSize(6, 6)
        ln.dot:SetPoint("LEFT", 2, 0)
        ln.dot:SetVertexColor(C.pink[1], C.pink[2], C.pink[3])
        ln.t = K.Text(ln, 12, C.text)
        ln.t:SetPoint("LEFT", 14, 0)
        ln.t:SetPoint("RIGHT", 0, 0)
        ln.t:SetWordWrap(false)
        pt.lines[j] = ln
    end
    pt.none = K.Text(pt, 11, C.dim)
    pt.none:SetWordWrap(true)
    pt.none:SetText(L["No pattern yet – that needs several attempts."])
end

-- Detail fuellen + anordnen (Breite dw); liefert die Inhaltshoehe
local function fillDetail(p, b, r, dw, anim)
    local ct = p.det.content
    ct.rects = {}
    local y = 0
    local inner = dw - 28
    -- a) Kopf
    local hd = p.hd
    hd:SetColor(resultCol(r))
    hd.title:SetText(r.boss or "?")
    local rc = resultCol(r)
    hd.pill:Set(r.ok == true and L["Kill"] or r.ok == false and L["Wipe"] or L["End"], rc)
    hd.sub:SetText((L["Attempt %d"]):format(r._nr or 0) .. "  ·  " .. ns.fmtWhen(r.ts or 0) .. (((r.inst or "") ~= "") and ("  ·  " .. r.inst) or "")
        .. ((tonumber(r.size) or 0) > 0 and ("  ·  " .. (L["%d players"]):format(r.size)) or ""))
    local ds = WR.DecodeDeaths(r.deaths)
    local first = ds[1] and ds[1].t and ds[1].n
    hd.stats[1].val:SetText(WR.FmtDur(r.dur))
    if anim and animOn() and #ds > 0 then K.CountUp(hd.stats[2].val, #ds, 0.5) else hd.stats[2].val:SetText(#ds) end
    hd.stats[3].val:SetText(r.ok == true and ("|cff66db9e" .. L["Kill"] .. "|r") or (r.hp and ("%.1f%%"):format(r.hp)) or "-")
    hd.stats[4].val:SetText(first and coloredName(first) or "-")
    local hh = hd:Layout(dw)
    place(ct, "head", hd, 0, y, dw, hh)
    y = y - hh - 10
    -- b) Verlauf: ein Balken je Versuch (Hoehe = geschafftes Boss-Leben), passt sich der Breite an
    local ch = p.chart
    local list = b.list
    local n = #list
    local fit = math.max(1, math.floor((inner + 4) / 16))
    local from = math.max(1, n - fit + 1)
    local shown = n - from + 1
    local bw = math.max(10, math.min(34, math.floor((inner + 4) / shown) - 4))
    local by = -40
    for i = 1, math.max(shown, #ch.bars) do
        local bar = ch.bars[i]
        if i <= shown then
            bar = ch:Bar(i)
            local run = list[from + i - 1]
            bar.run = run
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", ch, "TOPLEFT", 14 + (i - 1) * (bw + 4), by)
            bar:SetSize(bw, CHART_H)
            local prog = progressOf(run)
            local c = run.ok == true and C.mint or (prog >= 0.8 and C.amber or C.red)
            local selOn = run.id == WR.selRun
            bar.fill:SetColorTexture(c[1], c[2], c[3], selOn and 1 or 0.7)
            bar.sel:SetShown(selOn)
            local hFull = math.max(1, CHART_H * prog)
            if anim and animOn() then
                bar.fill:SetHeight(1)
                K.Tween(bar.fill, 0.55, function(q) bar.fill:SetHeight(math.max(1, hFull * (1 - (1 - q) * (1 - q)))) end,
                    function() bar.fill:SetHeight(hFull) end, (i - 1) * 0.03)
            else
                bar.fill:SetHeight(hFull)
            end
            bar.fill:SetShown(prog > 0)
            bar.nr:ClearAllPoints()
            bar.nr:SetPoint("TOP", bar, "BOTTOM", 0, -3)
            bar.nr:SetText((bw >= 14 or (run._nr or 0) % 2 == 1 or selOn) and tostring(run._nr or "") or "")
            bar.nr:SetTextColor(selOn and C.text[1] or C.dim[1], selOn and C.text[2] or C.dim[2], selOn and C.text[3] or C.dim[3])
            bar:Show() bar.nr:Show()
        elseif bar then
            bar:Hide() bar.nr:Hide()
        end
    end
    ch.base:ClearAllPoints()
    ch.base:SetPoint("TOPLEFT", ch, "TOPLEFT", 14, by - CHART_H)
    ch.base:SetWidth(inner)
    ch.head:SetCount((L["%d attempts, %d kills"]):format(b.n, b.kills))
    ch.hint:ClearAllPoints()
    ch.hint:SetPoint("TOPLEFT", ch, "TOPLEFT", 14, by - CHART_H - 18)
    ch.hint:SetWidth(inner)
    ch.hint:SetText((from > 1 and ((L["last %d"]):format(shown) .. "  ·  ") or "") .. L["Height = boss health taken down, click selects the attempt"])
    local chH = -by + CHART_H + 36
    place(ct, "chart", ch, 0, y, dw, chH)
    y = y - chH - 10
    -- c) Zeitstrahl
    local tl = p.tl
    tl.bar:ClearAllPoints()
    tl.bar:SetPoint("TOPLEFT", tl, "TOPLEFT", 14, -40)
    tl.bar:SetSize(inner, 22)
    local dur = math.max(1, tonumber(r.dur) or 1)
    tl.prog:SetWidth(math.max(0.01, inner * progressOf(r)))
    tl.t0:ClearAllPoints() tl.t0:SetPoint("TOPLEFT", tl.bar, "BOTTOMLEFT", 0, -3)
    tl.tm:ClearAllPoints() tl.tm:SetPoint("TOP", tl.bar, "BOTTOM", 0, -3) tl.tm:SetText(WR.FmtDur(dur / 2))
    tl.t1:ClearAllPoints() tl.t1:SetPoint("TOPRIGHT", tl.bar, "BOTTOMRIGHT", 0, -3) tl.t1:SetText(WR.FmtDur(r.dur))
    for _, m in ipairs(tl.marks) do m:Hide() end
    for i, x in ipairs(ds) do
        if x.t then
            local m = tl:Mark(i)
            local cls = classOf(x.n)
            local cr, cg, cb = ns.classColor(cls)
            m.t:SetVertexColor(cr, cg, cb)
            local rcol = i == 1 and C.red or C.bg
            m.ring:SetVertexColor(rcol[1], rcol[2], rcol[3], 1)
            m.ring:SetSize(i == 1 and 14 or 11, i == 1 and 14 or 11)
            m:ClearAllPoints()
            local px = math.max(6, math.min(inner - 6, inner * math.min(1, x.t / dur)))
            m:SetPoint("CENTER", tl.bar, "LEFT", px, 0)
            m.tip = { coloredName(x.n), WR.FmtDur(x.t) .. "  ·  " .. L[SRC_TEXT[x.src] or "-"] .. (i == 1 and ("  ·  |cffe64047" .. L["first death"] .. "|r") or "") }
            m:Show()
            if anim and animOn() then
                m:SetAlpha(0)
                K.Tween(m, 0.3, function(q) m:SetAlpha(q) end, function() m:SetAlpha(1) end, 0.1 + (i - 1) * 0.06)
            else
                m:SetAlpha(1)
            end
        end
    end
    local showSrc = inner >= 360
    local ry = -82
    for i = 1, math.max(#ds, #tl.rows) do
        local row = tl.rows[i]
        if i <= #ds then
            row = tl:Row(i)
            local x = ds[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tl, "TOPLEFT", 14, ry - (i - 1) * 22)
            row:SetWidth(inner)
            row.nr:SetText(i .. ".")
            row.t:SetText(x.t and WR.FmtDur(x.t) or "?")
            ns.RCUI.ClassIcon(row.cls, classOf(x.n))
            row.name:SetText(coloredName(x.n) .. (i == 1 and x.t and ("  |cffe64047" .. L["first death"] .. "|r") or ""))
            row.name:SetWidth(math.max(60, inner - 92 - (showSrc and 130 or 4)))
            row.src:SetShown(showSrc)
            row.src:SetWidth(126)
            row.src:SetText(L[SRC_TEXT[x.src] or "-"])
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    tl.none:ClearAllPoints()
    tl.none:SetPoint("TOPLEFT", tl, "TOPLEFT", 14, ry - 2)
    tl.none:SetShown(#ds == 0)
    tl.head:SetCount(#ds > 0 and tostring(#ds) or "")
    local tlH = -ry + math.max(1, #ds) * 22 + 10
    place(ct, "tl", tl, 0, y, dw, tlH)
    y = y - tlH - 10
    -- d) Schaden / Heilung: Balken in Klassenfarbe (nur wenn lesbar uebertragen)
    local mt = p.mt
    local data = { WR.DecodeMeter(r.dmg), WR.DecodeMeter(r.heal) }
    local present = {}
    for k = 1, 2 do if #data[k] > 0 then present[#present + 1] = k end end
    local any = #present > 0
    local two = inner >= 440 and #present == 2
    local colW = two and math.floor((inner - 16) / 2) or inner
    local cy, used = -40, {}
    local mtH = 70
    for idx, k in ipairs(present) do
        local col, m = mt.cols[k], data[k]
        used[k] = true
        local cx = 14 + ((two and idx == 2) and (colW + 16) or 0)
        if idx == 2 and not two then cy = cy - (math.min(5, #data[present[1]]) * 22 + 16 + 10) end
        col.lab:ClearAllPoints()
        col.lab:SetPoint("TOPLEFT", mt, "TOPLEFT", cx, cy)
        col.lab:Show()
        local top = m[1].v
        for j, ln in ipairs(col.lines) do
            local e = m[j]
            if e then
                ln:ClearAllPoints()
                ln:SetPoint("TOPLEFT", mt, "TOPLEFT", cx, cy - 16 - (j - 1) * 22)
                ln:SetWidth(colW)
                ln.name:SetWidth(math.max(40, colW - 60))
                ln.name:SetText(coloredName(e.n))
                ln.val:SetText(fmtNum(e.v))
                local cr, cg, cb = ns.classColor(classOf(e.n))
                ln.fill:SetColorTexture(cr, cg, cb, 0.9)
                local fw = math.max(1, colW * e.v / math.max(1, top))
                if anim and animOn() then
                    ln.fill:SetWidth(1)
                    K.Tween(ln.fill, 0.6, function(q) ln.fill:SetWidth(math.max(1, fw * q)) end, function() ln.fill:SetWidth(fw) end, (j - 1) * 0.05)
                else
                    ln.fill:SetWidth(fw)
                end
                ln:Show()
            else
                ln:Hide()
            end
        end
        local rowsHere = math.min(5, #m)
        mtH = math.max(mtH, -cy + 16 + rowsHere * 22 + 12)
    end
    for k, col in ipairs(mt.cols) do
        if not used[k] then
            col.lab:Hide()
            for _, ln in ipairs(col.lines) do ln:Hide() end
        end
    end
    mt.none:ClearAllPoints()
    mt.none:SetPoint("TOPLEFT", mt, "TOPLEFT", 14, -40)
    mt.none:SetWidth(inner)
    mt.none:SetShown(not any)
    place(ct, "meter", mt, 0, y, dw, mtH)
    y = y - mtH - 10
    -- e) Muster ueber alle Versuche dieses Bosses
    local pt = p.pt
    local pats = WR.Patterns(b.list)
    local np = math.min(4, #pats)
    for j, ln in ipairs(pt.lines) do
        if j <= np then
            ln:ClearAllPoints()
            ln:SetPoint("TOPLEFT", pt, "TOPLEFT", 14, -40 - (j - 1) * 22)
            ln:SetWidth(inner)
            ln.t:SetText(pats[j].text)
            ln:Show()
        else
            ln:Hide()
        end
    end
    pt.none:ClearAllPoints()
    pt.none:SetPoint("TOPLEFT", pt, "TOPLEFT", 14, -40)
    pt.none:SetWidth(inner)
    pt.none:SetShown(np == 0)
    pt.head:SetCount(np > 0 and tostring(np) or "")
    local ptH = np > 0 and (40 + np * 22 + 8) or 70
    place(ct, "pat", pt, 0, y, dw, ptH)
    y = y - ptH - 6
    return -y
end

ns.RegisterPage({
    key = "wipes", title = "Fight reports", order = 2.764,
    sub = "Every boss attempt: duration, order of deaths, boss health and recurring patterns",
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
        for i, d in ipairs({ { "deaths", "Attempts", C.accent }, { "checklist", "wins", C.mint },
            { "raid", "Best result", C.amber }, { "heart", "Deaths per attempt", C.red } }) do
            p.tiles[i] = K.HudTile(p, glyph(d[1]), L[d[2]], d[3])
        end
        -- 2) Boss-Liste (breit) bzw. Auswahlknopf (schmal)
        p.bossHead = K.GameHead(p, L["Bosses"], C.accent)
        p.bosses = K.List(p, 56, function(l)
            local r = K.Row(l)
            r.name = K.Title(r, 13, C.text)
            r.name:SetPoint("TOPLEFT", 12, -8)
            r.name:SetPoint("RIGHT", r, "RIGHT", -30, 0)
            r.name:SetWordWrap(false)
            r.meta = K.Text(r, 10, C.dim)
            r.meta:SetPoint("TOPLEFT", 12, -27)
            r.meta:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            r.meta:SetWordWrap(false)
            r.check = r:CreateTexture(nil, "OVERLAY")
            r.check:SetSize(14, 14)
            r.check:SetPoint("TOPRIGHT", -10, -9)
            r.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetPoint("BOTTOMLEFT", 12, 8)
            r.track:SetPoint("BOTTOMRIGHT", -12, 8)
            r.track:SetHeight(3)
            r.track:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
            r.fill = r:CreateTexture(nil, "OVERLAY")
            r.fill:SetPoint("BOTTOMLEFT", 12, 8)
            r.fill:SetHeight(3)
            r:SetScript("OnClick", function(self)
                if self.item then WR.selBoss, WR.selRun = self.item.boss, nil p.animRun = true ns.RefreshPage("wipes") end
            end)
            return r
        end, function(r, e)
            r.name:SetText(e.boss)
            r.meta:SetText((L["%d attempts, %d kills"]):format(e.n, e.kills) .. ((e.inst or "") ~= "" and ("  ·  " .. e.inst) or ""))
            r.check:SetShown(e.kills > 0)
            local best = 0
            for _, x in ipairs(e.list) do best = math.max(best, progressOf(x)) end
            local c = e.kills > 0 and C.mint or C.amber
            r.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
            r.fill:SetWidth(math.max(0.01, ((p.listW or 210) - 32) * best))
            r.fill:SetShown(best > 0)
            r.sel:SetShown(WR.selBoss == e.boss)
        end)
        p.bosses.empty:SetText("")
        p.pick = K.Button(p, "", 200, 26, "ghost", function(self)
            local items = {}
            for _, x in ipairs(p.bossData or {}) do
                items[#items + 1] = { text = x.boss .. "  |cff888888" .. (L["%d attempts, %d kills"]):format(x.n, x.kills) .. "|r", checked = x.boss == WR.selBoss,
                    fn = function() WR.selBoss, WR.selRun = x.boss, nil p.animRun = true ns.RefreshPage("wipes") end }
            end
            K.ShowMenu(self, items, L["Choose boss"], 220)
        end)
        p.pick.isDropdown = true
        p.pick.label:ClearAllPoints()
        p.pick.label:SetPoint("LEFT", 10, 0)
        p.pick.label:SetPoint("RIGHT", -20, 0)
        p.pick.label:SetJustifyH("LEFT")
        p.pick.arrow = K.Text(p.pick, 10, C.dim, "RIGHT")
        p.pick.arrow:SetPoint("RIGHT", -8, 0)
        p.pick.arrow:SetText("v")
        -- 3) Einzelheiten in einer Scrollflaeche
        p.det = U.Scroll(p)
        p.det.content.rects = {}
        buildDetail(p, p.det.content)
        p.empty = U.Empty(p, "deaths", C.red)

        function p:Layout(r, b, anim)
            local W = math.floor(self:GetWidth() or 0)
            if W < 200 then W = 700 end
            self.rects = {}
            local y = 0
            local tc = W >= 520 and 4 or 2
            local tw = math.floor((W - (tc - 1) * 8) / tc)
            for i, t in ipairs(self.tiles) do
                local ci, rr = (i - 1) % tc, math.floor((i - 1) / tc)
                place(self, "tile" .. i, t, ci * (tw + 8), y - rr * 72, tw, 64)
                t:Hide()   -- 0.5.855: Kacheln entfallen, die Karte des gewaehlten Versuchs zeigt die Werte
            end
            local hasData = b ~= nil
            local wide = W >= 640
            self.bossHead:SetShown(hasData and wide)
            self.bosses:SetShown(hasData and wide)
            self.pick:SetShown(hasData and not wide)
            self.det:SetShown(hasData and r ~= nil)
            self.empty:SetShown(not hasData)
            if not hasData then
                local ew = math.min(W, 340)
                place(self, "empty", self.empty, math.floor((W - ew) / 2), y - 20, ew, 150)
                return
            end
            local dx, dw = 0, W
            if wide then
                local lw = 210
                self.listW = lw
                place(self, "bhead", self.bossHead, 0, y, lw, 18)
                place(self, "bosses", self.bosses, 0, y - 26, lw, nil)
                dx, dw = lw + 14, W - lw - 14
            else
                place(self, "pick", self.pick, 0, y, W, 26)
                y = y - 34
            end
            place(self, "det", self.det, dx, y, dw, nil)
            if r then
                local h = fillDetail(self, b, r, dw - 8, anim)
                self.det:SetContentHeight(h)
            end
        end
        p.det:HookScript("OnSizeChanged", function() if p.lastB then p:Layout(p.lastR, p.lastB, false) end end)
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
    end,
    refresh = function(p)
        if not p.tiles then return end
        local bosses = WR.Bosses()
        p.bossData = bosses
        local b
        for _, x in ipairs(bosses) do if x.boss == WR.selBoss then b = x end end
        if not b then b = bosses[1] WR.selBoss = b and b.boss end
        local r
        if b then for _, x in ipairs(b.list) do if x.id == WR.selRun then r = x end end end
        if not r and b then r = b.list[#b.list] WR.selRun = r and r.id end
        -- Kacheln (ueber alle sichtbaren Versuche)
        local nRuns, nKills, nDeaths = 0, 0, 0
        for _, x in ipairs(bosses) do
            nRuns, nKills = nRuns + x.n, nKills + x.kills
            for _, run in ipairs(x.list) do nDeaths = nDeaths + #WR.DecodeDeaths(run.deaths) end
        end
        local fresh = p.fresh and animOn()
        p.tiles[1]:Set(nRuns, (L["%d bosses"]):format(#bosses), nil, fresh)
        p.tiles[2]:Set(nKills, nRuns > 0 and (L["%d%% rate"]):format(math.floor(nKills / nRuns * 100 + 0.5)) or "", nRuns > 0 and nKills / nRuns or nil, fresh)
        local bestTxt, bestSub, bestProg = "-", "", nil
        if b then
            local best = 0
            for _, x in ipairs(b.list) do best = math.max(best, progressOf(x)) end
            if b.kills > 0 then bestTxt = L["Kill"]
            else
                local hpMin
                for _, x in ipairs(b.list) do local hp = tonumber(x.hp) if hp and (not hpMin or hp < hpMin) then hpMin = hp end end
                bestTxt = hpMin and ("%.0f%%"):format(hpMin) or "-"
            end
            bestSub, bestProg = b.boss, best
        end
        p.tiles[3]:Set(bestTxt, bestSub, bestProg, false)
        p.tiles[4]:Set(nRuns > 0 and ("%.1f"):format(nDeaths / nRuns) or "-", L["on average"], nil, false)
        p.bosses:SetData(bosses)
        p.pick:SetLabel(b and ("|cffa3a3a8" .. L["Boss"] .. ":|r " .. b.boss .. "  |cff888888" .. (L["%d attempts, %d kills"]):format(b.n, b.kills) .. "|r") or "")
        if not b then
            p.empty:Set(L["No combat reports yet. After the first boss fight every attempt shows up here – with a death timeline and recurring patterns."],
                (ns.Demo and ns.Demo.Load and not demoOn()) and L["Show example"] or nil,
                function() if ns.Demo and ns.Demo.Load then ns.Demo.Load() ns.RefreshPage("wipes") end end)
        end
        local anim = p.fresh or p.animRun or (p.lastR and r and p.lastR.id ~= r.id)
        local boxChanged = p.lastBoss ~= (b and b.boss)
        p.lastR, p.lastB, p.lastBoss = r, b, b and b.boss
        p:Layout(r, b, anim)
        if boxChanged or p.fresh then p.det:Top() end
        if p.fresh then
            for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.06) end
            if b then ns.RCUI.Reveal(p.det) end
        end
        p.fresh, p.animRun = false, false
    end,
})

------------------------------------------------------------------------
-- /oa probe kampf: was liefert C_DamageMeter (nach dem Kampf aufrufen)
------------------------------------------------------------------------
local function dump(v, depth, prefix, out)
    if #out > 60 then return end
    local secret = false
    pcall(function() secret = issecret(v) and true or false end)
    if secret then out[#out + 1] = prefix .. " = <secret>" return end
    if type(v) ~= "table" then out[#out + 1] = prefix .. " = " .. tostring(v) .. " (" .. type(v) .. ")" return end
    if depth <= 0 then out[#out + 1] = prefix .. " = {...}" return end
    local n = 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 12 then out[#out + 1] = prefix .. " ..." break end
        dump(x, depth - 1, prefix .. "." .. tostring(k), out)
    end
    if n == 0 then out[#out + 1] = prefix .. " = {}" end
end
ns.Probes.kampf = function()
    ns.print(L["Probe fight (C_DamageMeter):"])
    local DM = C_DamageMeter
    if type(DM) ~= "table" then ns.print("  C_DamageMeter: " .. L["not available"]) else
        local fns = {}
        for k, v in pairs(DM) do fns[#fns + 1] = k .. (type(v) == "function" and "()" or "") end
        table.sort(fns)
        ns.print("  " .. L["Functions: "] .. table.concat(fns, ", "))
        for _, f in ipairs({ "IsDamageMeterAvailable", "GetAvailableCombatSessions" }) do
            if DM[f] then
                local out = {}
                local res = { pcall(DM[f]) }
                dump(res, 3, "  " .. f, out)
                for _, l in ipairs(out) do ns.print(l) end
            end
        end
        local E = Enum and Enum.DamageMeterType
        local ST = Enum and Enum.DamageMeterSessionType
        local out = {}
        dump(E, 1, "  Enum.DamageMeterType", out)
        dump(ST, 1, "  Enum.DamageMeterSessionType", out)
        for _, l in ipairs(out) do ns.print(l) end
        if E and DM.GetCombatSessionFromType then
            local o2 = {}
            local res = { pcall(DM.GetCombatSessionFromType, ST and (ST.Current or ST.LastFight) or 1, E.DamageDone or 0) }
            dump(res, 4, "  GetCombatSessionFromType", o2)
            for _, l in ipairs(o2) do ns.print(l) end
        end
        local m = readMeter()
        ns.print("  " .. L["Parsed: "] .. (m and ((m.dmg and ("dmg=" .. m.dmg:sub(1, 120)) or "") .. " " .. (m.heal and ("heal=" .. m.heal:sub(1, 120)) or "")) or "-"))
    end
    ns.print("  CombatLogGetCurrentEventInfo: " .. tostring(CombatLogGetCurrentEventInfo ~= nil) .. "  issecretvalue: " .. tostring(issecretvalue ~= nil))
    ns.print("  " .. L["Current fight: "] .. (cur and (cur.boss .. " " .. WR.FmtDur(GetTime() - cur.start)) or "-") .. "  Boss-HP: " .. tostring(bossHP()))
end
ns.Probes.combat = ns.Probes.kampf

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    local c = Store.coll(COLL)
    local now = ns.now()
    for id, r in pairs(c) do if not r.demo and now - (r.u or r.ts or 0) > KEEP then c[id] = nil end end
    ns.Every(30, flushPending)
    local D = ns.Demo
    if D and not D.wrHooked then
        D.wrHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) WR.SeedDemo() end
        D.Remove = function(...) remove(...) WR.RemoveDemo() end
        if D.IsActive() then ns.After(3, WR.SeedDemo) end
    end
end)
end)

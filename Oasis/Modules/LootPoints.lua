-- Oasis: Punkte fuer faire Beuteverteilung (EPGP-Prinzip, ohne Bieten)
--  Einsatz  = Punkte fuers Dabeisein (puenktlich, je Boss, bis zum Ende, Ersatzbank)
--  Beute    = Punkte fuer erhaltene Items (Hauptspec voll, Zweitspec ein Viertel, Transmog frei)
--  Prioritaet = Einsatz / (Beute + Grundwert). Hoechste Prioritaet bei "Bedarf" bekommt das Item.
--  Jede Woche verfallen x % (Standard 10), damit Neue aufholen koennen.
-- Punkte vergeben duerfen Offiziere (Rang einstellbar). Jede Buchung ist ein eigener Datensatz,
-- alle Clients rechnen den Stand selbst aus -> nichts geht verloren, alles ist nachvollziehbar.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Points = {}
ns.Points = Points

local DEFAULTS = {
    onTime = 10, boss = 10, finish = 10, bench = 1, base = 100,
    epic = 100, rare = 40, uncommon = 10, weapon = 1.5, offspec = 0.25, decay = 10, rank = 1,
}

function Points.Cfg()
    local c = Store.Get("points", "points-cfg") or Store.Get("points", "demo-points-cfg")
    local out = {}
    for k, v in pairs(DEFAULTS) do out[k] = (c and tonumber(c[k])) or v end
    return out
end
function Points.SetCfg(changes)
    local c = Store.Get("points", "points-cfg") or {}
    local r = { id = "points-cfg", kind = "cfg" }
    for k in pairs(DEFAULTS) do r[k] = c[k] end
    for k, v in pairs(changes) do r[k] = v end
    Store.Put("points", r)
end

------------------------------------------------------------------------
-- Wer darf buchen?
------------------------------------------------------------------------
local function rankOf(name)
    if ns.isMe(name) and ns.Admin and ns.Admin.TestMode() then return 0 end
    local m = ns.Radar and ns.Radar.byName[name]
    return m and m.rankIndex or 99
end
function Points.CanManage()
    if ns.isOfficer() then return true end
    return rankOf(ns.me()) <= Points.Cfg().rank
end
local function trusted(rec)
    if rec.demo then return true end
    local by = rec.by or ""
    if ns.isMe(by) then return Points.CanManage() end
    return rankOf(by) <= Points.Cfg().rank
end

------------------------------------------------------------------------
-- Stand ausrechnen
------------------------------------------------------------------------
local function mainOf(name) return ns.Alts and ns.Alts.Main(name) or name end
local cache, cacheKey

function Points.Records()
    local list = Store.List("points", function(r) return r.kind and r.kind ~= "cfg" end)
    table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return list
end

function Points.Standings()
    local list = Points.Records()
    local key = #list .. ":" .. (list[#list] and (list[#list].u or 0) or 0)
    if cache and cacheKey == key then return cache end
    local cfg = Points.Cfg()
    local by = {}
    local function get(n)
        local m = mainOf(n)
        local e = by[m]
        if not e then e = { name = m, ep = 0, gp = 0, items = 0, raids = 0, log = {} } by[m] = e end
        return e
    end
    for _, r in ipairs(list) do
        if trusted(r) then
            if r.kind == "ep" or r.kind == "adj" then
                for n in (r.who or ""):gmatch("[^,]+") do
                    local e = get(n)
                    if r.kind == "ep" then e.ep = e.ep + (r.amount or 0) else e.ep = e.ep + (r.ep or 0) e.gp = e.gp + (r.gp or 0) end
                    if r.start then e.raids = e.raids + 1 end
                    table.insert(e.log, r)
                end
            elseif r.kind == "gp" then
                local e = get(r.who or "?")
                e.gp = e.gp + (r.amount or 0)
                if (r.amount or 0) > 0 then e.items = e.items + 1 end
                table.insert(e.log, r)
            elseif r.kind == "decay" then
                local f = 1 - (r.pct or 0) / 100
                for _, e in pairs(by) do e.ep, e.gp = e.ep * f, e.gp * f end
            end
        end
    end
    local out = {}
    for _, e in pairs(by) do
        e.pr = e.ep / (e.gp + cfg.base)
        -- Raid-Anwesenheit der letzten 4 Wochen (Gildenpflege): entscheidet bei gleichem PR
        e.att = ns.Officer and ns.Officer.Attendance and ns.Officer.Attendance(e.name, 28) or nil
        out[#out + 1] = e
    end
    table.sort(out, function(a, b)
        if a.pr ~= b.pr then return a.pr > b.pr end
        if (a.att or 0) ~= (b.att or 0) then return (a.att or 0) > (b.att or 0) end
        return a.name < b.name
    end)
    for i, e in ipairs(out) do e.rank = i end
    local byName = {}
    for _, e in ipairs(out) do byName[e.name] = e end
    cache, cacheKey = { list = out, by = byName }, key
    return cache
end
function Points.Of(name)
    local s = Points.Standings()
    return s.by[mainOf(name)] or { name = mainOf(name), ep = 0, gp = 0, pr = 0, items = 0, raids = 0, log = {}, rank = #s.list + 1 }
end
function Points.FmtPR(pr) return ("%.2f"):format(pr or 0) end

------------------------------------------------------------------------
-- Buchen
------------------------------------------------------------------------
function Points.Award(names, amount, reason, id, extra)
    if #names == 0 or not amount or amount == 0 then return end
    local rec = { id = id or ns.newId("pts"), kind = "ep", who = table.concat(names, ","), amount = amount, reason = reason or "", ts = ns.now() }
    for k, v in pairs(extra or {}) do rec[k] = v end
    Store.Put("points", rec)
    return rec
end
function Points.Charge(name, amount, item, choice)
    return Store.Put("points", { id = ns.newId("pts"), kind = "gp", who = name, amount = amount or 0, item = item, choice = choice, ts = ns.now() })
end
function Points.Adjust(name, ep, gp, reason)
    return Store.Put("points", { id = ns.newId("pts"), kind = "adj", who = name, ep = ep or 0, gp = gp or 0, reason = reason or "", ts = ns.now() })
end

-- Preis eines Items je nach Wahl
function Points.ItemCost(link, choice)
    local cfg = Points.Cfg()
    if choice == "mog" or choice == "pass" then return 0 end
    local _, _, q, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link or "")
    q = ns.safe(q) or 4
    local base = (q >= 4 and cfg.epic) or (q == 3 and cfg.rare) or cfg.uncommon
    if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then base = base * cfg.weapon end
    if choice == "greed" then base = base * cfg.offspec end
    return math.floor(base + 0.5)
end

------------------------------------------------------------------------
-- Raid-Abend: Start / Bosse / Ende / Ersatzbank
------------------------------------------------------------------------
Points.bench = {}
local function groupNames()
    local out = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return { ns.me() } end
    if IsInRaid() then
        for i = 1, n do
            local name = ns.safe(GetRaidRosterInfo(i))
            if name then out[#out + 1] = ns.fullName(name) end
        end
    else
        out[1] = ns.me()
        for i = 1, n - 1 do
            local name = ns.safe(GetUnitName and GetUnitName("party" .. i, true) or ns.UnitName("party" .. i))
            if name then out[#out + 1] = ns.fullName(name) end
        end
    end
    return out
end
local function withBench(names)
    local cfg = Points.Cfg()
    if cfg.bench <= 0 then return names end
    local seen, out = {}, {}
    for _, n in ipairs(names) do seen[n] = true out[#out + 1] = n end
    for n in pairs(Points.bench) do if not seen[n] then out[#out + 1] = n end end
    return out
end
Points.GroupNames = groupNames

function Points.Active()
    local r = ns.db.pointsRaid
    if r and ns.now() - (r.t or 0) < 8 * 3600 then return r end
end
function Points.StartRaid(title)
    if not Points.CanManage() then ns.print(L["Punkte vergeben duerfen nur Offiziere."]) return end
    local cfg = Points.Cfg()
    local rid = date("%Y%m%d%H") .. ns.short(ns.me())
    ns.db.pointsRaid = { id = rid, t = ns.now(), title = title or (ns.safe(GetRealZoneText()) or ""), bosses = 0 }
    Points.Award(withBench(groupNames()), cfg.onTime, L["Puenktlich da"], "pts-start-" .. rid, { start = true, raid = title })
    K.Toast(L["Raid gestartet"], (L["+%d Einsatz fuer alle, die da sind"]):format(cfg.onTime), C.mint)
    ns.RefreshPage("raid")
end
function Points.BossKill(bossName, encounterID)
    local r = Points.Active()
    if not r or not Points.CanManage() then return end
    local cfg = Points.Cfg()
    local id = "pts-boss-" .. (encounterID or bossName or "?") .. "-" .. date("%Y%m%d")
    if Store.Get("points", id) then return end
    r.bosses = (r.bosses or 0) + 1
    Points.Award(withBench(groupNames()), cfg.boss, bossName or L["Boss"], id, { raid = r.title })
    K.Toast((L["%s besiegt"]):format(bossName or L["Boss"]), (L["+%d Einsatz fuer den Raid"]):format(cfg.boss), C.mint)
    ns.RefreshPage("raid")
end
function Points.EndRaid()
    local r = Points.Active()
    if not r then return end
    local cfg = Points.Cfg()
    Points.Award(withBench(groupNames()), cfg.finish, L["Bis zum Ende dabei"], "pts-end-" .. r.id, { raid = r.title })
    ns.db.pointsRaid = nil
    wipe(Points.bench)
    K.Toast(L["Raid beendet"], (L["+%d Einsatz fuer alle bis zum Schluss"]):format(cfg.finish), C.mint)
    ns.RefreshPage("raid")
end
-- Offizier betritt mit Schlachtzug eine Raid-Instanz: an den Start erinnern
local reminded
ns.On("PLAYER_ENTERING_WORLD", function()
    ns.After(5, function()
        local inInst, kind = IsInInstance()
        if not (inInst and kind == "raid" and IsInRaid() and Points.CanManage()) or Points.Active() then return end
        local zone = ns.safe(GetRealZoneText()) or ""
        if reminded == zone or ns.db.settings.raidPointsPrompt == false then return end
        reminded = zone
        K.Toast(L["Raid-Punkte starten?"], (L["%s  -  Klick: +%d Einsatz fuer alle, die da sind"]):format(zone, Points.Cfg().onTime), C.accent,
            function() Points.StartRaid(zone) end)
    end)
end)
ns.On("ENCOUNTER_END", function(encounterID, name, _, _, success)
    if ns.safe(success) == 1 then pcall(Points.BossKill, ns.safe(name), ns.safe(encounterID)) end
end)

-- woechentlicher Verfall: eine feste ID je Woche, damit er nur einmal gilt
local function weekKey() return date("%Y-%W") end
local function weeklyDecay()
    if not Points.CanManage() then return end
    local cfg = Points.Cfg()
    if cfg.decay <= 0 then return end
    local id = "pts-decay-" .. weekKey()
    if Store.Get("points", id) then return end
    if #Points.Records() == 0 then return end
    Store.Put("points", { id = id, kind = "decay", pct = cfg.decay, ts = ns.now() })
end
ns.Listen("LOGIN", function()
    ns.After(60, function() pcall(weeklyDecay) end)
    ns.Every(3600, function() pcall(weeklyDecay) end)
end)
ns.Listen("STORE", function(coll) if coll == "points" then cache = nil ns.RefreshPage("raid") end end)

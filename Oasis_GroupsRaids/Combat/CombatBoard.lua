-- Oasis: guild combat leaderboard (0.5.577, new 0.5.582)
-- Totals: Blizzard's built-in damage meter (C_DamageMeter) AFTER every fight.
-- Crits: confirmed single hits from readable combat log or log file import (CombatCrit.lua).
-- Everyone remembers their best values and shares them (store "combat", one record per player).
-- 0.5.582: In instances the values stay locked for a while after combat (addon restriction "Combat"/"ChallengeMode",
-- values come as secret). Each fight is therefore queued with its session ID and evaluated as soon as
-- Blizzard releases the values (ADDON_RESTRICTION_STATE_CHANGED, boss end, leaving the instance, else every 20 s).
-- Secret values are never compared or guessed.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Combat", function()   -- Module Combat leaderboard (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local CB = {}
ns.CombatBoard = CB
local COLL = "combat"
local issecret = issecretvalue or function() return false end
local function num(v) if type(v) == "number" and not issecret(v) and v == v and v < 1e12 then return v end end
local function week() return date("%Y-%W") end
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end

------------------------------------------------------------------------
-- Read out
------------------------------------------------------------------------
local function DMT(k) return Enum and Enum.DamageMeterType and Enum.DamageMeterType[k] end
local function currentType()
    local ST = Enum and Enum.DamageMeterSessionType
    return ST and (ST.Current or ST.LastFight or ST.Overall) or 1
end
-- Session per type: via the remembered ID, else "current" session (older clients)
local function session(entry, typ)
    local DM = C_DamageMeter
    if not DM or typ == nil then return nil end
    local ok, s
    if entry.id and DM.GetCombatSessionFromID then ok, s = pcall(DM.GetCombatSessionFromID, entry.id, typ)
    elseif DM.GetCombatSessionFromType then ok, s = pcall(DM.GetCombatSessionFromType, currentType(), typ) end
    return ok and type(s) == "table" and s or nil
end
-- own row: isLocalPlayer is never secret per Blizzard; name/GUID only if readable
local function mySource(s)
    -- some clients deliver the source list directly (as nesUI reads it)
    local list = s and (s.combatSources or s.sources or (type(s[1]) == "table" and s))
    if type(list) ~= "table" then return nil end
    local guid = UnitGUID and UnitGUID("player")
    local me = UnitName and ns.UnitName("player")
    for _, src in ipairs(list) do
        if type(src) == "table" then
            local own = src.isLocalPlayer
            if own ~= nil and not issecret(own) and own == true then return src end
            local g, n = src.sourceGUID, src.name
            if (g and not issecret(g) and g == guid) or (n and not issecret(n) and n == me) then return src end
            -- 0.5.621: name with realm ("Mira-Realm") or "First Last"
            if n and not issecret(n) and type(n) == "string" and me and ns.SameName(n, me) then return src end
        end
    end
    -- solo: exactly one source = me
    if not (IsInGroup and IsInGroup()) and #list == 1 and type(list[1]) == "table" then return list[1] end
end
-- Result per type: number, false = locked (secret), nil = no value
local function amount(entry, typ)
    local s = session(entry, typ)
    local src = s and mySource(s)
    -- 0.5.621: nothing found via the session ID -> like nesUI via "current fight" (only the most recent fight)
    if not src and entry.newest and C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and typ ~= nil then
        local ok, s2 = pcall(C_DamageMeter.GetCombatSessionFromType, currentType(), typ)
        if ok and type(s2) == "table" then
            local src2 = mySource(s2)
            if src2 then s, src = s2, src2 end
        end
    end
    if not s then return nil end
    if not src then
        -- List itself locked? (entries present, but nothing readable)
        local list = s.combatSources or s.sources or (type(s[1]) == "table" and s)
        if type(list) == "table" and #list > 0 and type(list[1]) == "table" and issecret(list[1].totalAmount) then return false end
        return nil
    end
    local v = src.totalAmount
    if issecret(v) then return false end
    return num(v), num(src.amountPerSecond)
end
local function sessionList()
    local DM = C_DamageMeter
    if not (DM and DM.GetAvailableCombatSessions) then return nil end
    local ok, l = pcall(DM.GetAvailableCombatSessions)
    return ok and type(l) == "table" and l or nil
end
local function listEntry(id)
    for _, e in ipairs(sessionList() or {}) do
        if type(e) == "table" and num(e.sessionID) == id then return e end
    end
end
local function duration(entry, s)
    if entry.id then
        local e = listEntry(entry.id)
        local d = e and num(e.durationSeconds)
        if d then return d end
    elseif C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local ok, d = pcall(C_DamageMeter.GetSessionDurationSeconds, currentType())
        if ok and num(d) then return d end
    end
    return s and num(s.durationSeconds or s.duration)
end
-- Field names of a table (for diagnostics), values only as type
function CB.KeysOf(t)
    if type(t) ~= "table" then return tostring(t) end
    local out = {}
    for k, v in pairs(t) do
        if #out >= 30 then break end
        out[#out + 1] = tostring(k) .. "=" .. (issecret(v) and "secret" or type(v))
    end
    table.sort(out)
    return table.concat(out, ", ")
end

-- queued fights (survive /reload, discarded on real login - session IDs restart then)
local function pend() ns.db.cbPending = ns.db.cbPending or {} return ns.db.cbPending end
local function done() ns.db.cbDone = ns.db.cbDone or {} return ns.db.cbDone end
CB.lost = 0

local function myRec()
    local me = ns.me and ns.me()
    if not me then return nil end
    local id = "cbt-" .. me
    local r = Store.Get(COLL, id)
    if not r then
        for _, old in ipairs(Store.List(COLL)) do
            if ns.SameName(old.who, me) and (not r or (old.t or 0) > (r.t or 0)) then r = old end
        end
    end
    local c = {}
    if r then for k, v in pairs(r) do c[k] = v end end
    c.id, c.who = id, me
    c.cls = select(2, UnitClass("player"))
    if c.wk ~= week() then c.wk, c.wd, c.wh, c.wt, c.wf = week(), 0, 0, 0, 0 end
    return c
end

local REC_NAMES = { bd = "Damage", dps = "DPS", mh = "Biggest hit", bh = "Healing", mhh = "Biggest heal", bt = "Damage taken" }
local function fmt(v)
    if not v then return "-" end
    if v >= 1e6 then return ("%.1f Mio"):format(v / 1e6) end
    if v >= 1e4 then return ("%.1fk"):format(v / 1e3) end
    return tostring(math.floor(v + 0.5))
end
CB.fmt = fmt

local pendingShare = false
local function queueShare(c)
    CB.pending = c
    -- share batched (don't send constantly after many small fights)
    if not pendingShare then
        pendingShare = true
        ns.After(90, function()
            pendingShare = false
            if CB.pending and not ns.inCombat() then
                if ns.db.settings.shareCombat ~= false then Store.Put(COLL, CB.pending) end
                CB.pending = nil
            end
        end)
    end
end

-- Single records come from the character statistics, not from spell totals.
-- This source does NOT distinguish critical and normal hits.
local statIDs = {}
local function statKind(name)
    if type(name) ~= "string" or issecret(name) then return end
    name = name:lower():gsub("ö", "oe"):gsub("ä", "ae"):gsub("ü", "ue")
    if name == "largest hit dealt" or name == "schwerster verursachter treffer" then return "mh" end
    if name == "largest heal cast" or name == "hoechste gewirkte heilung" then return "mhh" end
end
local function discoverStats()
    if not (GetAchievementInfo and GetStatistic) then return end
    local function inspect(id, index)
        local ok, aid, name
        if index then ok, aid, name = pcall(GetAchievementInfo, id, index)
        else ok, aid, name = pcall(GetAchievementInfo, id) end
        local kind = ok and statKind(name)
        if kind and num(aid) then statIDs[kind] = aid end
    end
    -- Use old IDs only if the client confirms the matching title.
    inspect(193); inspect(189)
    if statIDs.mh and statIDs.mhh then return end
    if not (GetStatisticsCategoryList and GetCategoryNumAchievements) then return end
    local ok, categories = pcall(GetStatisticsCategoryList)
    if not ok or type(categories) ~= "table" then return end
    for _, category in ipairs(categories) do
        local good, count = pcall(GetCategoryNumAchievements, category)
        count = good and num(count)
        if count then
            for i = 1, math.min(count, 2000) do inspect(category, i) end
        end
    end
end
local function statNumber(value)
    if issecret(value) then return end
    if type(value) == "number" then return num(value) end
    if type(value) ~= "string" then return end
    -- GetStatistic returns localized integers, e.g. 1.234 / 1,234 / 1 234.
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("[.,%s]", ""):gsub("\194\160", ""):gsub("\226\128\175", "")
    if value:match("^%d+$") then return num(tonumber(value)) end
end
function CB.ReadStatistics()
    if not ns.db or ns.inCombat() then return end
    if not GetStatistic then
        ns.db.cbStatDiag = { t = ns.now(), v = ns.version, source = "GetStatistic", unavailable = true }
        return
    end
    if not (statIDs.mh and statIDs.mhh) then discoverStats() end
    local c = myRec()
    if not c then return end
    local changed = false
    local diag = { t = ns.now(), v = ns.version, source = "GetStatistic" }
    for _, key in ipairs({ "mh", "mhh" }) do
        local id = statIDs[key]
        diag[key .. "ID"] = id
        if id then
            local ok, raw = pcall(GetStatistic, id)
            local value = ok and statNumber(raw)
            diag[key] = value
            diag[key .. "State"] = not ok and "error" or value == nil and "unreadable" or value <= 0 and "empty" or "ok"
            if c[key .. "crit"] ~= true and value and value > 0 and value > (c[key] or 0) then
                c[key] = value
                -- Historic character record: don't invent a current location or spell.
                c[key .. "z"], c[key .. "s"], c[key .. "t"] = nil, nil, ns.now()
                c[key .. "src"] = "statistic"
                changed = true
            end
        end
    end
    ns.db.cbStatDiag = diag
    ns.Debounce("combatStatsState", 0.5, function() ns.RefreshPage("fight") end)
    if changed then
        c.v, c.t = ns.version, ns.now()
        Store.coll(COLL)[c.id] = c
        queueShare(c)
        ns.Debounce("combatBoard", 0.5, function() ns.RefreshPage("fight") end)
    end
end

-- Only record confirmed critical single hits, no spell/session totals.
function CB.RecordCrit(key, value, spellID, source)
    value = num(value)
    if (key ~= "mh" and key ~= "mhh") or not value or value <= 0 then return false end
    local c = myRec()
    if not c then return false end
    if c[key .. "crit"] == true and value <= (num(c[key]) or 0) then return false end
    -- estimated group crit overwrites a reliably detected one: keep the reliable value alongside (key .. "c")
    if source == "group" and c[key .. "crit"] == true and c[key .. "src"] ~= "group" then c[key .. "c"] = num(c[key]) end
    c[key], c[key .. "crit"], c[key .. "src"] = value, true, source
    c[key .. "t"], c[key .. "z"], c[key .. "s"] = ns.now(), nil, nil
    spellID = num(spellID)
    if spellID and spellID > 0 then
        c[key .. "sid"] = spellID
        if C_Spell and C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, spellID)
            if ok and not issecret(name) and type(name) == "string" then c[key .. "s"] = name end
        end
    else c[key .. "sid"] = nil end
    c.v, c.t = ns.version, ns.now()
    Store.coll(COLL)[c.id] = c
    queueShare(c)
    ns.Debounce("combatBoard", 0.5, function() ns.RefreshPage("fight") end)
    return true
end

-- try a queued fight: "ok" | "wait" (locked) | "lost" (session gone)
local function tryEntry(entry)
    if entry.id and not listEntry(entry.id) then return "lost" end
    local dmg, dps0 = amount(entry, DMT("DamageDone"))
    local heal = amount(entry, DMT("HealingDone"))
    local taken = amount(entry, DMT("DamageTaken"))
    if dmg == false or heal == false or taken == false then return "wait" end
    -- Diagnostics for the saved-variables file (what arrived when reading)
    ns.db.cbDiag = { t = ns.now(), id = entry.id, newest = entry.newest, d = dmg, h = heal, tk = taken,
        types = DMT("DamageDone") ~= nil, sess = #(sessionList() or {}), v = ns.version }
    if not (dmg or heal or taken) then ns.db.cbDiag.res = "empty" return "empty" end
    -- 0.5.621: vehicle fights don't count (cannons, siege engines, quest vehicles)
    if entry.veh then ns.db.cbDiag.res = "vehicle" CB.skipped = (CB.skipped or 0) + 1 return "ok" end
    local c = myRec()
    if not c then return "wait" end
    local key = entry.id and tostring(entry.id) or "cur"
    local prev = done()[key] or {}
    local dur = duration(entry, session(entry, DMT("DamageDone")))
    -- don't count the same session twice (a session can grow over several fights)
    local dd, dh, dt = (dmg or 0) - (prev.d or 0), (heal or 0) - (prev.h or 0), (taken or 0) - (prev.t or 0)
    if dd <= 0 and dh <= 0 and dt <= 0 and prev.d then return "ok" end
    done()[key] = { d = dmg or 0, h = heal or 0, t = taken or 0, at = ns.now() }
    local now = ns.now()
    local recs = {}
    -- 0.5.621: unrealistic values (quest buffs, vehicles, test values) not as a record - limits by level
    local lvl = math.max(1, tonumber(ns.safe(UnitLevel("player"))) or 1)
    local CAP = {
        mh = 40 * lvl + 3 * lvl * lvl,          -- Level 60: 13,200 highest hit
        mhh = 40 * lvl + 3 * lvl * lvl,
        dps = 15 * lvl + 0.5 * lvl * lvl,       -- Stufe 60: 2.700 DPS
    }
    local durC = math.max(10, dur or 10)
    CAP.bd = CAP.dps * durC + CAP.mh
    CAP.bh = CAP.dps * 1.5 * durC + CAP.mhh
    CAP.bt = CAP.dps * 4 * durC + CAP.mh * 3
    if (dmg and dmg > CAP.bd) or (heal and heal > CAP.bh) then
        ns.db.cbDiag.res = "implausible"
        CB.skipped = (CB.skipped or 0) + 1
        return "ok"
    end
    local function better(k, v, extra)
        if v and CAP[k] and v > CAP[k] then return end
        if v and v > (c[k] or 0) then
            if (c[k] or 0) > 0 then recs[#recs + 1] = { k = k, old = c[k], new = v } end
            c[k] = math.floor(v + 0.5)
            c[k .. "z"], c[k .. "t"] = entry.z, now
            if extra then for x, y in pairs(extra) do c[k .. x] = y end end
        end
    end
    better("bd", dmg)
    better("bh", heal)
    better("bt", taken)
    local dps = (dmg and dur and dur >= 10) and dmg / dur or (dur == nil and dps0) or nil
    better("dps", dps)
    ns.db.cbDiag.res = "ok"
    c.wd = (c.wd or 0) + math.max(0, math.floor(dd))
    c.wh = (c.wh or 0) + math.max(0, math.floor(dh))
    c.wt = (c.wt or 0) + math.max(0, math.floor(dt))
    if not prev.d then c.wf = (c.wf or 0) + 1 end
    c.v, c.t = ns.version, now
    ns.db.cbLast = { d = dmg, h = heal, tk = taken, dur = dur, dps = dps, z = entry.z, t = entry.t or now, inst = entry.inst, late = (now - (entry.t or now)) > 5 }
    Store.coll(COLL)[c.id] = c   -- lokal sofort sichtbar
    queueShare(c)
    -- new personal record (not on the very first value): one notice per fight
    if #recs > 0 then
        local r = recs[1]
        local more = #recs > 1 and ("  |cff888888+" .. (#recs - 1) .. "|r") or ""
        if ns.Sound and ns.Sound.Next then ns.Sound.Next("record") end
        K.Toast(L["New record!"], (L["%s: %s (was %s)"]):format(L[REC_NAMES[r.k]], fmt(r.new), fmt(r.old)) .. more, nil,
            function() CB.Open(r.k) end)
        CB.flash = r.k
    end
    return "ok"
end

local pumpTimer = false
function CB.Pump()
    if not C_DamageMeter or not ns.db or ns.inCombat() then return end
    local P = pend()
    local now = ns.now()
    local keep = {}
    for _, e in ipairs(P) do
        local ok, res = pcall(tryEntry, e)
        res = ok and res or "wait"
        if res == "wait" and now - (e.t or now) < 3 * 3600 then
            keep[#keep + 1] = e
        elseif res == "lost" or res == "wait" then
            CB.lost = CB.lost + 1
        end
        CB.lastRead = res
    end
    ns.db.cbPending = keep
    ns.Debounce("combatBoard", 0.5, function() ns.RefreshPage("fight") end)
    -- while something is pending: retry every 20 s (one timer)
    if #keep > 0 and not pumpTimer then
        pumpTimer = true
        ns.After(20, function() pumpTimer = false CB.Pump() end)
    end
end
CB.Waiting = function() return ns.db and ns.db.cbPending and #ns.db.cbPending or 0 end

-- Combat end: queue the most recent session
local function noteFight()
    if not C_DamageMeter or not ns.db then return end
    local id
    for _, e in ipairs(sessionList() or {}) do
        local sid = type(e) == "table" and num(e.sessionID)
        if sid and (not id or sid > id) then id = sid end
    end
    local P = pend()
    local key = id or "cur"
    local veh = CB.vehicleFight
    CB.vehicleFight = nil
    for _, e in ipairs(P) do e.newest = nil end
    for _, e in ipairs(P) do if (e.id or "cur") == key then e.t = ns.now() e.newest = true e.veh = e.veh or veh return end end
    local inst = IsInInstance and select(1, IsInInstance()) and true or false
    P[#P + 1] = { id = id, z = GetRealZoneText and ns.safe(GetRealZoneText()) or "", t = ns.now(), inst = inst, newest = true, veh = veh }
    while #P > 40 do table.remove(P, 1) end
end
-- 0.5.621: fought in a vehicle? (then the fight doesn't count for records)
local function vehCheck()
    local v = (UnitInVehicle and ns.safe(UnitInVehicle("player"))) or (UnitHasVehicleUI and ns.safe(UnitHasVehicleUI("player")))
        or (UnitControllingVehicle and ns.safe(UnitControllingVehicle("player")))
    if v then CB.vehicleFight = true end
end
ns.On("PLAYER_REGEN_DISABLED", function() CB.vehicleFight = nil pcall(vehCheck) end)
ns.On("UNIT_ENTERED_VEHICLE", function(unit) if unit == "player" then CB.vehicleFight = true end end)
ns.On("PLAYER_REGEN_ENABLED", function()
    pcall(vehCheck)
    pcall(noteFight)
    ns.After(1.5, function() CB.Pump(); CB.ReadStatistics() end)
end)
-- Blizzard lifts an addon restriction (exactly then the values are readable again)
ns.On("ADDON_RESTRICTION_STATE_CHANGED", function() if CB.Waiting() > 0 then ns.After(0.3, CB.Pump) end end)
ns.On("ENCOUNTER_END", function() if CB.Waiting() > 0 then ns.After(2, CB.Pump) end end)
ns.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", function()
    if CB.Waiting() > 0 and not ns.inCombat() then ns.Debounce("cbPump", 2, CB.Pump) end
end)
-- Sessions deleted (reset) -> pending data is lost
ns.On("DAMAGE_METER_RESET", function()
    if not ns.db then return end
    local n = CB.Waiting()
    if n > 0 then pcall(CB.Pump) end
    CB.lost = CB.lost + CB.Waiting()
    ns.db.cbPending = {}
    ns.db.cbDone = {}
end)
ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not ns.db then return end
    if isLogin and not isReload then ns.db.cbPending, ns.db.cbDone = {}, {} return end
    if CB.Waiting() > 0 then ns.After(3, CB.Pump) end
end)
ns.On("PLAYER_LOGOUT", function() if CB.pending then pcall(Store.Put, COLL, CB.pending) end end)
ns.On("PLAYER_REGEN_ENABLED", function() if CB.pending then queueShare(CB.pending) end end)

-- Statistics also work without an available damage meter session.
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(3, CB.ReadStatistics) end)
ns.On("CRITERIA_UPDATE", function()
    if ns.db and not ns.inCombat() then ns.Debounce("cbStatistics", 5, CB.ReadStatistics) end
end)

-- Permissions: only own record
local function installAuth()
    local A = ns.Admin
    if A and A.AUTH then A.AUTH[COLL] = function(rec, actor) return rec.who ~= nil and A.SameName(rec.who, actor) end end
end
installAuth()
ns.Listen("LOGIN", installAuth)
ns.Listen("STORE", function(coll) if coll == COLL then ns.Debounce("combatBoard", 1, function() ns.RefreshPage("fight") end) end end)

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local CATS = {
    { key = "bd", text = "Damage", sub = "Most damage in one fight", icon = "raid" },
    { key = "dps", text = "DPS", sub = "Highest damage per second (fights of 10 s or more)", icon = "stats" },
    { key = "mh", text = "Highest critical hit", sub = "biggest single critical hit", icon = "star_on", spell = true },
    { key = "bh", text = "Healing", sub = "Most healing in one fight", icon = "heart" },
    { key = "mhh", text = "Critical heal", sub = "biggest single critical heal", icon = "heart", spell = true },
    { key = "bt", text = "Damage taken", sub = "Most damage taken in one fight", icon = "deaths" },
    { key = "wd", text = "week", sub = "Total damage this week", icon = "checklist", week = true },
}
local function catOf(k) for _, c in ipairs(CATS) do if c.key == k then return c end end return CATS[1] end
local function valueOf(r, cat, wk)
    if cat.week then return (r.wk == wk) and r.wd or nil end
    if cat.spell and r[cat.key .. "crit"] ~= true then return nil end
    return r[cat.key]
end
-- sorted list per category
local function ranking(cat)
    local wk = week()
    local list, byName = {}, {}
    for _, r in ipairs(Store.List(COLL)) do
        local v = valueOf(r, cat, wk)
        -- the same character sometimes arrives twice (different realm suffix, first name only): count as one
        local key = (ns.ResolveName and ns.ResolveName(r.who, true) or tostring(r.who)):lower()
        if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then key = key:match("^(.*)%-[^%-]+$") or key end
        if v and v > 0 and (not byName[key] or v > byName[key].v) then byName[key] = { r = r, v = v } end
    end
    for _, entry in pairs(byName) do list[#list + 1] = entry end
    table.sort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return tostring(a.r.who) < tostring(b.r.who) end)
    return list
end
local function shortName(who) who = tostring(who or "?") return who:match("^[^-]+") or who end
local function colored(who)
    local n = shortName(who)
    return ns.Radar and ns.Radar.Colored and ns.Radar.Colored(n) or n
end
local function setClass(tex, cls)
    local ok = ns.GuildInfo and ns.GuildInfo.SetClassIcon and select(2, pcall(ns.GuildInfo.SetClassIcon, tex, cls))
    if not ok then tex:SetColorTexture(0.25, 0.25, 0.28, 1) end
end
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function circle(owner, tex)
    if not owner.CreateMaskTexture then return end
    pcall(function()
        local m = owner:CreateMaskTexture()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
    end)
end
local function card(p, icon, title, sub)
    local c = CreateFrame("Frame", nil, p)
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 12)) then
        K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
    end
    c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. icon, C.accent)
    c.ic:SetPoint("TOPLEFT", 16, -16)
    c.t = K.Title(c, 14, C.text)
    c.t:SetPoint("LEFT", c.ic, "RIGHT", 8, 0)
    c.t:SetText(title)
    c.s = K.Text(c, 10, C.dim)
    c.s:SetPoint("TOPLEFT", c.ic, "BOTTOMLEFT", 0, -6)
    c.s:SetPoint("RIGHT", -16, 0)
    c.s:SetJustifyH("LEFT")
    c.s:SetText(sub or "")
    return c
end
local MEDAL = { { 1, 0.80, 0.32 }, { 0.80, 0.84, 0.92 }, { 0.86, 0.56, 0.32 } }
local POD_H = { 62, 44, 30 }       -- Pedestal height place 1/2/3
local POD_IC = { 46, 38, 38 }      -- Icon size
local ROWS = 9

-- Podest-Platz (1-3)
local function podSlot(p, parent, i)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(132, POD_H[i] + POD_IC[i] + 52)
    local m = MEDAL[i]
    s.base = s:CreateTexture(nil, "BACKGROUND")
    s.base:SetPoint("BOTTOMLEFT", 6, 0)
    s.base:SetPoint("BOTTOMRIGHT", -6, 0)
    s.base:SetHeight(POD_H[i])
    s.base:SetColorTexture(m[1], m[2], m[3], 0.10)
    if K.RoundMask then K.RoundMask(s.base, s.base, 8) end
    s.top = s:CreateTexture(nil, "BORDER")
    s.top:SetPoint("TOPLEFT", s.base, "TOPLEFT", 0, 0)
    s.top:SetPoint("TOPRIGHT", s.base, "TOPRIGHT", 0, 0)
    s.top:SetHeight(2)
    s.top:SetColorTexture(m[1], m[2], m[3], 0.75)
    s.rank = K.Title(s, i == 1 and 22 or 18, m, "CENTER")
    s.rank:SetPoint("CENTER", s.base, "CENTER", 0, -1)
    s.rank:SetText(i)
    s.val = K.Title(s, i == 1 and 16 or 14, C.text, "CENTER")
    s.val:SetPoint("BOTTOM", s.base, "TOP", 0, 8)
    s.name = K.Text(s, 11, C.text, "CENTER")
    s.name:SetPoint("BOTTOM", s.val, "TOP", 0, 3)
    s.name:SetWidth(126)
    s.name:SetWordWrap(false)
    s.ring = s:CreateTexture(nil, "ARTWORK")
    s.ring:SetTexture(CIRCLE)
    s.ring:SetSize(POD_IC[i] + 4, POD_IC[i] + 4)
    s.ring:SetPoint("BOTTOM", s.name, "TOP", 0, 6)
    s.ring:SetVertexColor(m[1], m[2], m[3], 0.9)
    s.ic = s:CreateTexture(nil, "OVERLAY")
    s.ic:SetSize(POD_IC[i], POD_IC[i])
    s.ic:SetPoint("CENTER", s.ring, "CENTER")
    circle(s, s.ic)
    s.hl = s:CreateTexture(nil, "BACKGROUND", nil, -1)
    s.hl:SetPoint("TOPLEFT", s.ring, "TOPLEFT", -14, 6)
    s.hl:SetPoint("BOTTOMRIGHT", 0, 0)
    s.hl:SetColorTexture(1, 1, 1, 0.035)
    if K.RoundMask then K.RoundMask(s.hl, s.hl, 10) end
    s.hl:Hide()
    -- 0.6.445: with the guild module the same image cards as the deathroll leaderboard (gold/silver/bronze + crown)
    if ns.GuildPack then
        local MED = { "gold", "silver", "bronze" }
        s.card = s:CreateTexture(nil, "BACKGROUND", nil, -2)
        s.card:SetPoint("TOPLEFT", 0, 4)
        s.card:SetPoint("BOTTOMRIGHT", 0, 0)
        s.card:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_podium_" .. MED[i])
        s.base:SetAlpha(0) s.top:Hide()
        if i == 1 then
            s.crown = s:CreateTexture(nil, "OVERLAY")
            s.crown:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_crown")
            s.crown:SetSize(40, 20)
            s.crown:SetPoint("BOTTOM", s.ring, "TOP", 0, -2)
        end
    end
    s:SetScript("OnEnter", function(self) self.hl:Show() if self.e then CB.ShowTip(self, self.e.r) end end)
    s:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
    s:SetScript("OnClick", function(self) if self.e then p.sel = self.e.r.who ns.RefreshPage("fight", true) end end)
    return s
end

-- Listenzeile (ab Platz 4)
local function listRow(p, parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(26)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.045)
    if K.RoundMask then K.RoundMask(r.hl, r.hl, 6) end
    r.hl:Hide()
    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT", 0, 0)
    r.bar:SetPoint("BOTTOMLEFT", 0, 0)
    r.bar:SetWidth(1)
    r.pos = K.Title(r, 12, C.dim, "CENTER")
    r.pos:SetPoint("LEFT", 0, 0)
    r.pos:SetWidth(30)
    r.ic = r:CreateTexture(nil, "ARTWORK")
    r.ic:SetSize(16, 16)
    r.ic:SetPoint("LEFT", 32, 0)
    circle(r, r.ic)
    r.name = K.Text(r, 12, C.text)
    r.name:SetPoint("LEFT", r.ic, "RIGHT", 8, 0)
    r.name:SetWidth(150)
    r.name:SetWordWrap(false)
    r.name:SetJustifyH("LEFT")
    r.val = K.Title(r, 12, C.text, "RIGHT")
    r.val:SetPoint("RIGHT", -10, 0)
    r.val:SetWidth(80)
    r.info = K.Text(r, 10, C.dim)
    r.info:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.info:SetPoint("RIGHT", r.val, "LEFT", -8, 0)
    r.info:SetWordWrap(false)
    r.info:SetJustifyH("LEFT")
    r:SetScript("OnEnter", function(self) self.hl:Show() if self.e then CB.ShowTip(self, self.e.r) end end)
    r:SetScript("OnLeave", function(self) if not self.sel then self.hl:Hide() end GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) if self.e then p.sel = self.e.r.who ns.RefreshPage("fight", true) end end)
    return r
end

-- Tooltip: all records of a person with place
function CB.ShowTip(owner, rec)
    local lines = { colored(rec.who) }
    local wk = week()
    for _, c in ipairs(CATS) do
        local v = valueOf(rec, c, wk)
        if v and v > 0 then
            local pos
            for i, e in ipairs(ranking(c)) do if e.r == rec or e.r.who == rec.who then pos = i break end end
            lines[#lines + 1] = L[c.text] .. ":  |cffffffff" .. fmt(v) .. "|r" .. (pos and ("  |cff888888#" .. pos .. "|r") or "")
        end
    end
    lines[#lines + 1] = "|cff888888" .. L["Click: details"] .. "|r"
    K.ShowTip(owner, lines)
end
function CB.Open(catKey)
    if ns.ShowPage then pcall(ns.ShowPage, "fight") end
    if catKey and CB.page then CB.page.cat = catKey CB.page.animNext = true end
    ns.RefreshPage("fight", true)
end

ns.RegisterPage({
    key = "fight", title = "Combat ranking", order = 2.6,
    sub = "Who deals, heals and takes the most?",
    build = function(p)
        CB.page = p
        p.cat = "bd"
        local items = {}
        for _, c in ipairs(CATS) do items[#items + 1] = { key = c.key, text = L[c.text] } end
        p.seg = K.Segments(p, items, function(k)
            if p.cat ~= k then p.cat = k p.animNext = true end
            if K.TabAnim then K.TabAnim(p.seg, k) end
            ns.RefreshPage("fight", true)
        end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p:HookScript("OnShow", function() p.animNext = true end)

        -- Leaderboard (left): podium + list
        local list = card(p, "raid", L["Ranking"], "")
        list:SetPoint("TOPLEFT", 0, -40)
        list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -282, 0)
        p.listCard = list
        list.s:SetWordWrap(true)
        list.s:SetHeight(24)
        p.pod = CreateFrame("Frame", nil, list)
        p.pod:SetPoint("TOPLEFT", 12, -68)
        p.pod:SetPoint("TOPRIGHT", -12, -68)
        p.pod:SetHeight(POD_H[1] + POD_IC[1] + 52)
        p.slots = {}
        for i = 1, 3 do p.slots[i] = podSlot(p, p.pod, i) end
        p.slots[1]:SetPoint("BOTTOM", p.pod, "BOTTOM", 0, 0)
        p.slots[2]:SetPoint("BOTTOMRIGHT", p.slots[1], "BOTTOMLEFT", -4, 0)
        p.slots[3]:SetPoint("BOTTOMLEFT", p.slots[1], "BOTTOMRIGHT", 4, 0)
        p.podLine = list:CreateTexture(nil, "BORDER")
        p.podLine:SetHeight(1)
        p.podLine:SetPoint("TOPLEFT", p.pod, "BOTTOMLEFT", 0, -10)
        p.podLine:SetPoint("TOPRIGHT", p.pod, "BOTTOMRIGHT", 0, -10)
        p.podLine:SetColorTexture(1, 1, 1, 0.06)
        p.rows = {}
        for i = 1, ROWS do
            local r = listRow(p, list, i)
            r:SetPoint("TOPLEFT", p.pod, "BOTTOMLEFT", 0, -18 - (i - 1) * 27)
            r:SetPoint("RIGHT", list, "RIGHT", -12, 0)
            p.rows[i] = r
        end
        p.more = K.Text(list, 10, C.dim)
        p.more:SetPoint("BOTTOMLEFT", 16, 44)
        -- few entries: instead of an empty area briefly explain how values get here
        p.hintT = K.Text(list, 12, C.muted)
        p.hintT:SetPoint("TOPLEFT", p.pod, "BOTTOMLEFT", 6, -26)
        p.hint = K.Text(list, 12, C.dim)
        p.hint:SetPoint("TOPLEFT", p.hintT, "BOTTOMLEFT", 0, -8)
        p.hint:SetPoint("RIGHT", list, "RIGHT", -22, 0)
        p.hint:SetWordWrap(true)
        p.hint:SetJustifyV("TOP")
        if p.hint.SetSpacing then p.hint:SetSpacing(4) end
        -- own place, pinned at the bottom
        p.meBar = CreateFrame("Button", nil, list)
        p.meBar:SetHeight(30)
        p.meBar:SetPoint("BOTTOMLEFT", 10, 10)
        p.meBar:SetPoint("BOTTOMRIGHT", -10, 10)
        p.meBar.bg = p.meBar:CreateTexture(nil, "BACKGROUND")
        p.meBar.bg:SetAllPoints()
        p.meBar.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
        if K.RoundMask then K.RoundMask(p.meBar.bg, p.meBar.bg, 8) end
        p.meBar.l = K.Text(p.meBar, 11, C.muted)
        p.meBar.l:SetPoint("LEFT", 12, 0)
        p.meBar.v = K.Title(p.meBar, 13, C.text, "RIGHT")
        p.meBar.v:SetPoint("RIGHT", -12, 0)
        p.meBar:SetScript("OnClick", function() p.sel = ns.me() ns.RefreshPage("fight", true) end)
        p.empty = K.Text(list, 12, C.dim, "CENTER")
        p.empty:SetPoint("CENTER", list, "CENTER", 0, 10)
        p.empty:SetWidth(320)
        p.empty:SetWordWrap(true)
        p.retryStats = K.Button(list, L["Check critical hit source"], 200, 24, "ghost", function()
            if CB.CheckCritSource then CB.CheckCritSource(true) end
            ns.RefreshPage("fight", true)
        end)
        p.retryStats:SetPoint("TOP", p.empty, "BOTTOM", 0, -16)

        -- Player card (top right)
        local pc = card(p, "profile", L["Player"], "")
        pc:SetPoint("TOPRIGHT", 0, -40)
        pc:SetSize(270, 262)
        p.pc = pc
        pc.ic:Hide()
        pc.t:ClearAllPoints()
        pc.av = pc:CreateTexture(nil, "ARTWORK")
        pc.av:SetSize(36, 36)
        pc.av:SetPoint("TOPLEFT", 16, -16)
        circle(pc, pc.av)
        pc.t:SetPoint("TOPLEFT", pc.av, "TOPRIGHT", 10, -2)
        pc.s:ClearAllPoints()
        pc.s:SetPoint("TOPLEFT", pc.t, "BOTTOMLEFT", 0, -4)
        pc.s:SetPoint("RIGHT", -16, 0)
        pc.rows = {}
        for i, c in ipairs(CATS) do
            local r = CreateFrame("Button", nil, pc)
            r:SetHeight(26)
            r:SetPoint("TOPLEFT", 10, -64 - (i - 1) * 27)
            r:SetPoint("RIGHT", pc, "RIGHT", -10, 0)
            r.hl = r:CreateTexture(nil, "BACKGROUND")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.04)
            if K.RoundMask then K.RoundMask(r.hl, r.hl, 6) end
            r.hl:Hide()
            r.l = K.Text(r, 11, C.muted)
            r.l:SetPoint("TOPLEFT", 6, -4)
            r.l:SetText(L[c.text])
            r.pos = K.Text(r, 10, C.dim, "RIGHT")
            r.pos:SetPoint("TOPRIGHT", -6, -5)
            r.pos:SetWidth(30)
            r.v = K.Title(r, 12, C.text, "RIGHT")
            r.v:SetPoint("RIGHT", r.pos, "LEFT", -6, 0)
            r.track = r:CreateTexture(nil, "BORDER")
            r.track:SetHeight(2)
            r.track:SetPoint("BOTTOMLEFT", 6, 3)
            r.track:SetPoint("BOTTOMRIGHT", -6, 3)
            r.track:SetColorTexture(1, 1, 1, 0.06)
            r.fill = r:CreateTexture(nil, "ARTWORK")
            r.fill:SetHeight(2)
            r.fill:SetPoint("BOTTOMLEFT", r.track, "BOTTOMLEFT")
            r.fill:SetWidth(1)
            r.key = c.key
            r:SetScript("OnEnter", function(self) self.hl:Show() K.ShowTip(self, { L[c.text], "|cff888888" .. L[c.sub] .. "|r", "|cff888888" .. L["Click: ranking"] .. "|r" }) end)
            r:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
            r:SetScript("OnClick", function() p.cat = c.key p.animNext = true ns.RefreshPage("fight", true) end)
            pc.rows[i] = r
        end

        -- Last fight (bottom right)
        local lf = card(p, "stats", L["Last fight"], "")
        lf:SetPoint("TOPRIGHT", pc, "BOTTOMRIGHT", 0, -12)
        lf:SetPoint("BOTTOMLEFT", p, "BOTTOMRIGHT", -270, 0)
        p.lf = lf
        lf.big = K.Title(lf, 22, C.text)
        lf.big:SetPoint("TOPLEFT", 16, -58)
        lf.bigL = K.Text(lf, 10, C.dim)
        lf.bigL:SetPoint("LEFT", lf.big, "RIGHT", 8, -2)
        lf.cells = {}
        local CELL = { { "DPS", "dps" }, { "Healing", "h" }, { "Damage taken", "tk" }, { "Duration", "dur" } }
        for i, d in ipairs(CELL) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local l = K.Text(lf, 10, C.dim)
            l:SetPoint("TOPLEFT", 16 + col * 122, -92 - row * 34)
            l:SetText(L[d[1]])
            local v = K.Title(lf, 13, C.text)
            v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
            lf.cells[d[2]] = v
        end
        lf.state = K.Text(lf, 10, C.dim)
        lf.state:SetPoint("BOTTOMLEFT", 16, 14)
        lf.state:SetPoint("RIGHT", -16, 0)
        lf.state:SetJustifyH("LEFT")
        lf.state:SetWordWrap(true)
    end,
    refresh = function(p)
        local cat = catOf(p.cat)
        p.seg:Select(cat.key)
        p.listCard.t:SetText(L[cat.text])
        local diag = ns.db.cbStatDiag
        local checked = cat.spell and ns.db.cbCritDiag and ns.db.cbCritDiag.t or diag and diag.t
        local source = cat.spell and L["Source: your own crits. Reliable when solo; estimated in groups and dungeons (hit right after your own attack)."] or L["Source: Blizzard damage meter."]
        -- clarify what is counted: the best SINGLE fight, wherever - location and time belong to that fight
        if not cat.spell and not cat.week then source = L["Counts each player's best single fight - dungeon or open world."] .. "\n" .. source end
        p.listCard.s:SetText(source .. (cat.spell and checked and ("\n" .. (L["Last check: %s"]):format(ns.ago(checked))) or ""))
        local anim = p.animNext and animOn()
        p.animNext = false
        local list = ranking(cat)
        local top = list[1] and list[1].v or 1
        local any = #list > 0
        p.pod:SetShown(any)
        p.podLine:SetShown(any)
        p.empty:SetShown(not any)
        p.retryStats:SetShown(cat.spell and not any and not ns.inCombat())
        local emptyStat = not GetStatistic and L["Character statistics are unavailable in this client."]
            or (not diag or not diag[cat.key .. "ID"]) and L["The matching character statistic has not been found yet."]
            or diag[cat.key .. "State"] == "empty" and L["No positive single-hit record has been reported yet."]
            or L["The statistic currently provides no readable value."]
        if cat.spell then
            local cd = ns.db.cbCritDiag
            emptyStat = cd and (cd.mode == "restricted" or cd.mode == "unavailable")
                and L["No crit recorded yet. Critical hits count automatically while you fight alone in the open world."]
                or L["No readable critical hit from you recorded yet. New critical hits are recorded automatically."]
        end
        p.empty:SetText(cat.spell and emptyStat or C_DamageMeter and L["No values yet - after the next fight you'll see who is ahead."]
            or L["Blizzard's damage meter is not available in this client - rankings can't be measured."])
        local function info(r)
            if cat.week then return (L["%d fights"]):format(r.wf or 0) end
            if r[cat.key .. "src"] == "statistic" then
                local at = r[cat.key .. "t"]
                return L["Character statistic – highest single value, critical status unknown"] .. (at and ("  ·  " .. ns.ago(at)) or "")
            end
            if r[cat.key .. "crit"] == true then
                local sp = r[cat.key .. "s"]
                local label = r[cat.key .. "src"] == "logfile" and L["Log file: confirmed critical hit"] or L["confirmed crit"]
                if r[cat.key .. "src"] == "group" then
                    local safe = tonumber(r[cat.key .. "c"])
                    label = L["Group: estimated crit"] .. (safe and safe > 0 and ("  ·  " .. (L["confirmed: %d"]):format(safe)) or "")
                end
                return label .. (sp and ("  ·  " .. sp) or "")
            end
            local z, t = r[cat.key .. "z"], r[cat.key .. "t"]
            local sp = cat.spell and r[cat.key .. "s"]
            local spn = sp and C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, sp))
            return (type(spn) == "string" and (spn .. (t and "  ·  " or "")) or "") .. (t and ns.ago(t) or "")
        end
        -- Podest
        for i = 1, 3 do
            local s, e = p.slots[i], list[i]
            s.e = e
            if e then
                setClass(s.ic, e.r.cls)
                s.ic:SetDesaturated(false)
                s.ic:SetAlpha(1)
                s.name:SetText(colored(e.r.who) .. (ns.isMe(e.r.who) and ("  |cff888888" .. L["you"] .. "|r") or ""))
                s.rank:SetText(i)
            else
                s.ic:SetColorTexture(1, 1, 1, 0.06)
                s.name:SetText("|cff555555" .. L["open"] .. "|r")
                K.Tween(s.val, 0.01, function() end, function() s.val:SetText("") end)
                s.val:SetText("")
                s.rank:SetText(i)
            end
            -- free slot: no colored circle, only a faded base
            local ra, ia, ba = e and 0.9 or 0, e and 1 or 0, e and 1 or 0.45
            s.base:SetAlpha(ba)
            local h = POD_H[i]
            if anim then
                s.base:SetHeight(1)
                s.ring:SetAlpha(0) s.ic:SetAlpha(0) s.name:SetAlpha(0) s.val:SetAlpha(0) s.rank:SetAlpha(0)
                local d = ({ 0.12, 0, 0.24 })[i]
                K.Tween(s.base, 0.45, function(q) s.base:SetHeight(math.max(1, h * q)) end, function() s.base:SetHeight(h) end, d)
                K.Tween(s.ring, 0.35, function(q)
                    s.ring:SetAlpha(q * ra) s.ic:SetAlpha(q * ia) s.name:SetAlpha(q) s.val:SetAlpha(q) s.rank:SetAlpha(q * ba)
                end, function() s.ring:SetAlpha(ra) s.ic:SetAlpha(ia) s.name:SetAlpha(1) s.val:SetAlpha(1) s.rank:SetAlpha(ba) end, d + 0.25)
                if e then K.CountUp(s.val, e.v, 0.9, fmt, d + 0.25) end
            else
                s.base:SetHeight(h)
                s.ring:SetAlpha(ra) s.ic:SetAlpha(ia) s.rank:SetAlpha(ba)
                if e then s.val:SetText(fmt(e.v)) end
            end
        end
        -- List from place 4
        local listW = math.max(100, (p.listCard:GetWidth() or 400) - 24)
        for i, row in ipairs(p.rows) do
            local e = list[i + 3]
            row.e = e
            row:SetShown(e ~= nil)
            if e then
                local r = e.r
                local pos = i + 3
                row.pos:SetText(pos)
                setClass(row.ic, r.cls)
                row.name:SetText(colored(r.who) .. (ns.isMe(r.who) and ("  |cff888888" .. L["you"] .. "|r") or ""))
                row.info:SetText(info(r))
                local cr, cg, cb = ns.classColor(r.cls)
                row.bar:SetColorTexture(cr or 0.6, cg or 0.6, cb or 0.6, 0.13)
                row.sel = (p.sel and r.who == p.sel) or false
                row.hl:SetShown(row.sel)
                local w = math.max(1, listW * math.min(1, e.v / top))
                if anim then
                    row.bar:SetWidth(1)
                    row:SetAlpha(0)
                    local d = 0.3 + i * 0.04
                    K.Tween(row, 0.3, function(q) row:SetAlpha(q) end, function() row:SetAlpha(1) end, d)
                    K.Tween(row.bar, 0.6, function(q) row.bar:SetWidth(math.max(1, w * q)) end, function() row.bar:SetWidth(w) end, d)
                    K.CountUp(row.val, e.v, 0.6, fmt, d)
                else
                    row:SetAlpha(1)
                    row.bar:SetWidth(w)
                    row.val:SetText(fmt(e.v))
                end
            end
        end
        -- up to three entries the list stays empty: it says how to get onto the leaderboard
        local few = any and #list <= 3 and not cat.spell
        p.hintT:SetShown(few)
        p.hint:SetShown(few)
        if few then
            p.hintT:SetText(cat.spell and L["How your crit gets onto the board"] or L["Room for more"])
            p.hint:SetText(cat.spell and L["Critical hits while playing solo count automatically. In groups and dungeons Oasis estimates them and marks them as such."]
                or L["More places fill up as more guild members with Oasis have fought."])
        end
        local shown = math.min(#list, ROWS + 3)
        p.more:SetText(#list > shown and (L["+ %d more"]):format(#list - shown) or "")
        -- own place
        local me = ns.me()
        local myPos, myVal
        for i, e in ipairs(list) do if ns.isMe(e.r.who) then myPos, myVal = i, e.v break end end
        if myPos then
            p.meBar.l:SetText(L["Your rank"] .. "  |cffffffff#" .. myPos .. "|r  |cff888888" .. (L["of %d"]):format(#list) .. "|r")
            p.meBar.v:SetText(fmt(myVal) .. (myPos > 1 and ("  |cff888888-" .. fmt(list[myPos - 1].v - myVal) .. " " .. L["to place %d"]:format(myPos - 1) .. "|r") or ""))
        else
            p.meBar.l:SetText(L["Your rank"])
            p.meBar.v:SetText("|cff888888" .. L["no value yet"] .. "|r")
        end
        p.meBar:SetShown(any or CB.Waiting() > 0)

        -- Player card
        local selWho = p.sel or me
        local rec
        for _, r in ipairs(Store.List(COLL)) do if r.who == selWho then rec = r break end end
        local pc = p.pc
        if rec then
            setClass(pc.av, rec.cls)
            pc.t:SetText(colored(rec.who))
            pc.s:SetText(ns.isMe(rec.who) and L["Your records"] or (rec.t and (L["last"] .. " " .. ns.ago(rec.t)) or ""))
        else
            pc.av:SetColorTexture(1, 1, 1, 0.06)
            pc.t:SetText(colored(selWho or "?"))
            pc.s:SetText(L["Automatically after every fight"])
        end
        local wk = week()
        for i, c in ipairs(CATS) do
            local r = pc.rows[i]
            local v = rec and valueOf(rec, c, wk)
            local rk = ranking(c)
            local pos
            if v and v > 0 then for j, e in ipairs(rk) do if e.r.who == rec.who then pos = j break end end end
            r.v:SetText(v and v > 0 and fmt(v) or "|cff555555-|r")
            local m = pos and MEDAL[pos]
            r.pos:SetText(pos and ("#" .. pos) or "")
            if m then r.pos:SetTextColor(m[1], m[2], m[3]) else r.pos:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
            local active = c.key == cat.key
            r.l:SetTextColor(active and C.text[1] or C.muted[1], active and C.text[2] or C.muted[2], active and C.text[3] or C.muted[3])
            r.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], active and 0.9 or 0.45)
            local lead = rk[1] and rk[1].v or 0
            local tw = math.max(1, (r:GetWidth() or 240) - 12)
            local w = (v and lead > 0) and math.max(1, tw * math.min(1, v / lead)) or 1
            if anim then
                r.fill:SetWidth(1)
                K.Tween(r.fill, 0.6, function(q) r.fill:SetWidth(math.max(1, w * q)) end, function() r.fill:SetWidth(w) end, 0.2 + i * 0.03)
            else
                r.fill:SetWidth(w)
            end
            -- fresh record: briefly highlight the row
            if CB.flash == c.key and ns.isMe(selWho) then
                CB.flash = nil
                r.hl:Show()
                r.hl:SetAlpha(1)
                K.Tween(r.hl, 2.5, function(q) r.hl:SetAlpha(1 - q) end, function() r.hl:Hide() r.hl:SetAlpha(1) end, 0.4)
            end
        end

        -- Letzter Kampf
        local lf, last = p.lf, ns.db.cbLast
        local waiting = CB.Waiting()
        if last then
            lf.s:SetText((last.z or "") .. (last.t and ("  ·  " .. ns.ago(last.t)) or ""))
            if anim and last.d then K.CountUp(lf.big, last.d, 0.8, fmt, 0.2) else lf.big:SetText(last.d and fmt(last.d) or "-") end
            lf.bigL:SetText(L["Damage"])
            lf.cells.dps:SetText(last.dps and fmt(last.dps) or "-")
            lf.cells.h:SetText(last.h and fmt(last.h) or "-")
            lf.cells.tk:SetText(last.tk and fmt(last.tk) or "-")
            lf.cells.dur:SetText(last.dur and (SecondsToTime and SecondsToTime(math.floor(last.dur)) or (math.floor(last.dur) .. " s")) or "-")
        else
            lf.s:SetText(L["No fight recorded yet"])
            lf.big:SetText("-")
            lf.bigL:SetText("")
            for _, v in pairs(lf.cells) do v:SetText("-") end
        end
        local st
        if waiting > 0 then
            st = "|cffe8b44a" .. (L["%d fights waiting for release"]):format(waiting) .. "|r  " ..
                L["Blizzard locks the values in instances for a while after combat - Oasis records them as soon as they are released (usually after the boss or when you leave)."]
        elseif last and last.late then
            st = "|cff66db9e" .. L["Caught up"] .. "|r  " .. L["The fight was locked at first and was recorded afterwards."]
        elseif CB.lost > 0 then
            st = "|cff888888" .. (L["%d fights lost (damage meter was reset)"]):format(CB.lost) .. "|r"
        else
            st = L["Oasis reads Blizzard's built-in damage meter after every fight - in instances too."]
        end
        lf.state:SetText(st .. ((ns.db.cbDiag and ns.db.cbDiag.t) and ("  " .. (L["Last check: %s"]):format(ns.ago(ns.db.cbDiag.t))) or ""))
    end,
})
ns.probes = ns.probes or {}
ns.probes.kampfliste = function()
    pcall(noteFight)
    CB.Pump()
    ns.print("Kampf-Rangliste: " .. tostring(CB.lastRead) .. ", wartend " .. CB.Waiting() .. ", verloren " .. CB.lost)
end
end)

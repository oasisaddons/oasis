-- Oasis: Rare mobs - guild-wide shared sightings of rares/rare elites/world bosses
--  Sources: vignettes (C_VignetteInfo), nameplates, own target; death via combat log (if readable)
--  or "target is dead" after combat. From deaths per mob: respawn estimate (shortest/average interval).
--  Shared via the store (own collections "rare_seen" + "rare_kills", own messages OARU/OARQ/OARA/OARB,
--  because Comm.lua only accepts registered collections).
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Rares", function()   -- Module Rare mobs (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
-- Security on receipt (others' addon messages may be manipulated):
-- Sanitize texts, limit numbers, check names, throttle floods
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Neutralize escape sequences (|c |r |n |H |T |K |A ...) and control chars; links: valid item/spell links stay
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

local Rares = {}
ns.Rares = Rares
if ns.ICONS then ns.ICONS.rares = ns.MEDIA .. "icons\\deaths" end

local SEEN, KILLS = "rare_seen", "rare_kills"
local GROUP = "rares"
local KEEP = { [SEEN] = 30 * 86400, [KILLS] = 120 * 86400 }
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local CLS_TAG = { worldboss = "World boss", rareelite = "Rare elite", rare = "Rare", elite = "Elite" }
local CLS_COLOR = { worldboss = "|cffff5060", rareelite = "|cffe8b44a", rare = "|cffc8c8ff", elite = "|cffff8a3d" }
local FRESH = 300            -- this long a sighting counts as "fresh" (hint)
local ALIVE_FOR = 20 * 60    -- this long we show "alive" after the last sighting
local RESEND = 300           -- same mob, same state: resend at most every 5 min
local KILL_BUCKET = 600      -- Tode innerhalb 10 Min = derselbe Tod

local state = {
    sent = {},        -- key -> { t, st } zuletzt von mir gesendet
    guids = {},       -- GUID -> key (seen this session, for death via combat log)
    toastAt = {},     -- key -> time of the last hint
    toastAll = 0,
    targetGUID = nil, targetKey = nil,
    vigAt = 0,
    quiet = false,
    sources = {},     -- Diagnostics: which source delivered something last
}
Rares.state = state

local function S() return ns.db.settings end
local function opt(key) local v = S()[key] if v == nil then return true end return v end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end

------------------------------------------------------------------------
-- Probe command /oa probe <topic> (shared dispatcher, also for other modules)
------------------------------------------------------------------------
ns.probes = ns.probes or {}
local function installProbe()
    if ns.slash.probe and ns.slash.probe == ns._probeDispatch then return end
    local prev = ns.slash.probe
    local busy = false
    local function dispatch(arg)
        local key, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
        key = (key or ""):lower()
        local fn = ns.probes[key]
        if fn then
            local ok, e = pcall(fn, rest)
            if not ok then ns.print("Probe-Fehler: " .. tostring(e)) end
            return
        end
        if prev and not busy then
            busy = true
            local ok, e = pcall(prev, arg)
            busy = false
            if not ok then ns.err("probe", e) end
            return
        end
        local keys = {}
        for k in pairs(ns.probes) do keys[#keys + 1] = k end
        table.sort(keys)
        ns.print(L["Probe topics: "] .. table.concat(keys, ", "))
    end
    ns._probeDispatch = dispatch
    ns.slash.probe = dispatch
end
installProbe()

------------------------------------------------------------------------
-- Own store binding (send, receive, sync for later logins)
------------------------------------------------------------------------
local function isDemoRec(r) return r.demo or tostring(r.id):find("demo-", 1, true) end
-- Never send display helper fields ("_zone" ...)
local function clean(r)
    local c = {}
    for k, v in pairs(r) do if type(k) == "string" and k:sub(1, 1) ~= "_" then c[k] = v end end
    return c
end
local function put(coll, rec)
    rec.u = math.max(ns.now(), (rec.u or 0) + 1)
    rec.by = rec.by or ns.me()
    Store.merge(coll, rec)
    if isDemoRec(rec) or not opt("rareShare") then return rec end
    if IsInGuild() then Comm.SendEx({ ch = "GUILD" }, "OARU", coll, Comm.encodeRecord(clean(rec))) end
    return rec
end
Rares.put = put

-- Check receipt: shared sightings (anyone may report), but limit fields, sanitize texts,
-- Timestamps not in the future, coordinates within map area, collection limited
local function netOk(coll, rec, sender)
    if type(rec) ~= "table" or type(rec.id) ~= "string" or #rec.id > 80 or isDemoRec(rec) then return false end
    if sender and Comm.FromGuild and not Comm.FromGuild(sender) then return false end   -- guild members only
    rec.demo, rec.sim = nil, nil
    rec.u = math.min(tonumber(rec.u) or 0, ns.now() + 300)
    if rec.ts then rec.ts = math.min(tonumber(rec.ts) or 0, ns.now() + 300) end
    for k, v in pairs(rec) do
        if type(v) == "string" then rec[k] = SEC.Text(v, 120)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then rec[k] = 0 end
    end
    for _, k in ipairs({ "x", "y" }) do
        local v = tonumber(rec[k])
        if v and (v < 0 or v > 10000) then rec[k] = 0 end   -- stored as 0..10000
    end
    local c = Store.coll(coll)
    if not c[rec.id] then
        local n = 0
        for _ in pairs(c) do n = n + 1 if n >= 3000 then return false end end
    end
    return true
end
Rares.NetOk = netOk
Comm.On("OARU", function(sender, _, coll, s)
    if not KEEP[coll] or not s then return end
    local rec = Comm.decodeRecord(s)
    if netOk(coll, rec, sender) then Store.merge(coll, rec, true, sender) end
end)
Comm.On("OARB", function(sender, _, coll, ...)
    if not KEEP[coll] then return end
    for i = 1, math.min(select("#", ...), 200) do
        local s = select(i, ...)
        if s and s ~= "" then
            local rec = Comm.decodeRecord(s)
            if netOk(coll, rec, sender) then Store.merge(coll, rec, true, sender, true) end
        end
    end
    ns.db.rareMeta = ns.db.rareMeta or {}
    ns.db.rareMeta.lastSync = ns.now()
    ns.RefreshPage("rares")
end)
local pendingAnswer = {}
Comm.On("OARQ", function(sender, channel, grp, since)
    if grp ~= GROUP or pendingAnswer[sender] then return end
    if not SEC.Rate("oarq:" .. sender, 60) then return end   -- no whisper flood on request
    since = tonumber(since) or 0
    pendingAnswer[sender] = true
    ns.After(math.random(20, 90) / 10, function()
        if pendingAnswer[sender] ~= true then pendingAnswer[sender] = nil return end
        pendingAnswer[sender] = nil
        local any = false
        for coll in pairs(KEEP) do
            local batch, size = {}, 0
            local function flush()
                if #batch > 0 then Comm.WhisperBulk(sender, "OARB", coll, unpack(batch)) batch, size = {}, 0 end
            end
            for _, r in pairs(Store.coll(coll)) do
                if type(r) == "table" and (r.u or 0) > since and not isDemoRec(r) then
                    if not any then any = true Comm.Guild("OARA", GROUP, sender) end
                    local s = Comm.encodeRecord(clean(r))
                    batch[#batch + 1] = s
                    size = size + #s
                    if size > 1500 then flush() end
                end
            end
            flush()
        end
    end)
end)
Comm.On("OARA", function(_, _, grp, target)
    if grp == GROUP and target and pendingAnswer[target] then pendingAnswer[target] = "cancel" end
end)

local function prune()
    local now = ns.now()
    for coll, keep in pairs(KEEP) do
        local c = Store.coll(coll)
        for id, r in pairs(c) do
            if type(r) ~= "table" or now - (r.u or 0) > keep then c[id] = nil end
        end
    end
end

------------------------------------------------------------------------
-- Helpers: position, unit -> mob
------------------------------------------------------------------------
local function myPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = ns.safe(C_Map.GetBestMapForUnit("player"))
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return map end
    local x, y = pos:GetXY()
    x, y = ns.safe(x), ns.safe(y)
    if not x or x == 0 then return map end
    return map, x, y
end
Rares.myPos = myPos

local function npcFromGUID(guid)
    guid = ns.safe(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
Rares.npcFromGUID = npcFromGUID

local function keyOf(npc, name)
    if npc and npc > 0 then return tostring(npc) end
    return ((name or "?"):lower():gsub("[^%w]", ""))
end
Rares.keyOf = keyOf

local function wanted(cls)
    if cls == "rare" or cls == "rareelite" or cls == "worldboss" then return true end
    if cls == "elite" and S().rareElites then return true end
    return false
end

-- Faction leaders/city NPCs: WoW classifies them as "worldboss", but they are not world bosses (0.5.535)
local NOT_BOSS = {}
for _, n in ipairs({ "Thrall", "Vol'jin", "Cairne Bloodhoof", "Cairne Bloodhoof", "Sylvanas Windlaeufer", "Sylvanas Windläufer",
    "Sylvanas Windrunner", "Lor'themar Theron", "Magni Bronzebart", "Magni Bronzebeard", "Bolvar Fordragon", "Tyrande Wisperwind",
    "Tyrande Whisperwind", "Hochkoenig Mekkadrill", "Hochkönig Mekkadrill", "High Tinker Mekkatorque", "Koenig Varian Wrynn",
    "König Varian Wrynn", "King Varian Wrynn", "Prophet Velen", "Lady Katrana Prestor", "Rexxar", "Baine Bluthuf", "Baine Bloodhoof",
    "Varimathras", "Jaina Prachtmeer", "Jaina Proudmoore", "Fandral Hirschhaupt", "Fandral Staghelm" }) do NOT_BOSS[n:lower()] = true end
function Rares.NotBoss(name) return NOT_BOSS[tostring(name or ""):lower()] == true end
-- Check unit: { key, npc, name, cls, guid, dead } or nil
local function unitInfo(unit)
    if not UnitExists(unit) then return nil end
    if ns.safe(UnitIsPlayer(unit)) then return nil end
    -- only attackable mobs (friendly leaders like Thrall are "worldboss" to WoW too)
    if UnitCanAttack and ns.safe(UnitCanAttack("player", unit)) == false then return nil end
    if UnitPlayerControlled and ns.safe(UnitPlayerControlled(unit)) then return nil end
    local cls = ns.safe(UnitClassification and UnitClassification(unit))
    if not wanted(cls) then return nil end
    local name = ns.safe(ns.UnitName(unit))
    if not ns.validName(name) or Rares.NotBoss(name) then return nil end
    local guid = ns.safe(UnitGUID(unit))
    local npc = npcFromGUID(guid)
    return { key = keyOf(npc, name), npc = npc or 0, name = name, cls = cls, guid = guid,
        dead = ns.safe(UnitIsDead(unit)) == true }
end

------------------------------------------------------------------------
-- Report sighting / death
------------------------------------------------------------------------
function Rares.Get(key) local r = Store.Get(SEEN, "rs-" .. key) if r and not r.del then return r end end

-- info: { key, npc, name, cls }, map/x/y optional (else own position), src = source
function Rares.Sight(info, map, x, y, src, dead)
    if not info or not info.key or ns.inInstance() then return end
    if not map then map, x, y = myPos() end
    if not map then return end
    local st = dead and "d" or "a"
    state.sources[src or "?"] = ns.now()
    local now = ns.now()
    local last = state.sent[info.key]
    local old = Rares.Get(info.key)
    -- throttled: same state in quick succession not again
    if last and last.st == st and now - last.t < RESEND then return end
    if not dead and old and old.st == "a" and now - (old.ts or 0) < RESEND / 2 and old.by ~= ns.me() then return end
    state.sent[info.key] = { t = now, st = st }
    local rec = {}
    if old then for k, v in pairs(old) do if type(k) == "string" and k:sub(1, 1) ~= "_" then rec[k] = v end end end
    rec.id = "rs-" .. info.key
    rec.npc = info.npc or rec.npc or 0
    rec.name = info.name or rec.name
    rec.cls = info.cls or rec.cls or "rare"
    rec.map = map
    rec.x = x and math.floor(x * 10000) or rec.x or 0
    rec.y = y and math.floor(y * 10000) or rec.y or 0
    rec.zone = ns.safe(GetRealZoneText and GetRealZoneText()) or rec.zone or ""
    rec.ts = now
    rec.st = st
    rec.src = src or ""
    rec.by = ns.me()
    rec.demo = nil
    if dead then rec.dts = now end
    put(SEEN, rec)
    if dead then Rares.Kill(info, map, now) end
    ns.RefreshPage("rares")
end

function Rares.Kill(info, map, ts)
    ts = ts or ns.now()
    -- already a death in the last 10 min (by anyone)?
    for _, k in ipairs(Store.List(KILLS, function(r) return r.key == info.key end)) do
        if math.abs((k.ts or 0) - ts) < KILL_BUCKET then return end
    end
    put(KILLS, { id = ("rk-%s-%d"):format(info.key, math.floor(ts / KILL_BUCKET)), key = info.key, npc = info.npc or 0,
        name = info.name, map = map or 0, ts = ts })
end

------------------------------------------------------------------------
-- Respawn estimate from deaths
------------------------------------------------------------------------
function Rares.Respawn(key)
    local ts = {}
    local demo = demoOn()
    for _, k in ipairs(Store.List(KILLS, function(r) return r.key == key and (demo or not r.demo) end)) do ts[#ts + 1] = k.ts or 0 end
    table.sort(ts)
    local gaps = {}
    for i = 2, #ts do
        local g = ts[i] - ts[i - 1]
        if g >= 120 then gaps[#gaps + 1] = g end
    end
    local out = { kills = #ts, last = ts[#ts] }
    if #gaps == 0 then return out end
    table.sort(gaps)
    out.min = gaps[1]
    local m = #gaps
    out.median = (m % 2 == 1) and gaps[(m + 1) / 2] or math.floor((gaps[m / 2] + gaps[m / 2 + 1]) / 2)
    out.samples = m
    return out
end

local function dur(sec)
    sec = math.max(0, sec or 0)
    if sec >= 86400 then return (L["%dd %dh"]):format(sec / 86400, (sec % 86400) / 3600) end
    if sec >= 3600 then return (L["%dh %dm"]):format(sec / 3600, (sec % 3600) / 60) end
    return (L["%d min"]):format(math.max(1, math.ceil(sec / 60)))
end
Rares.dur = dur

-- Text for "next spawn"; second value: sortable time (nil = unknown)
function Rares.NextText(rec)
    local now = ns.now()
    if rec.st == "a" and now - (rec.ts or 0) < ALIVE_FOR then return "|cff66db9e" .. L["alive now"] .. "|r", now end
    local r = Rares.Respawn(rec._key or keyOf(rec.npc, rec.name))
    local last = r.last or rec.dts
    if not last then return "|cff777777" .. L["no kill known yet"] .. "|r", nil end
    if not r.min then return "|cff777777" .. (L["%d kill(s), interval unknown"]):format(r.kills) .. "|r", nil end
    local from, to = last + r.min, last + r.median
    if now < from then return (L["in %s - %s"]):format(dur(from - now), dur(to - now)), from end
    if now < to then return "|cffe8b44a" .. (L["possible now (until ~%s)"]):format(dur(to - now)) .. "|r", now end
    return "|cffff8a3d" .. (L["overdue for %s"]):format(dur(now - to)) .. "|r", to
end

------------------------------------------------------------------------
-- Sources
------------------------------------------------------------------------
-- report nothing on a flight master flight: you can neither stop nor attack there
local function flying()
    return opt("rareFlyQuiet") and UnitOnTaxi and ns.safe(UnitOnTaxi("player")) == true
end
local function checkUnit(unit, src)
    if ns.inInstance() or flying() then return end
    local info = unitInfo(unit)
    if not info then return end
    if info.guid then state.guids[info.guid] = info end
    Rares.Sight(info, nil, nil, nil, src, info.dead)
    return info
end

-- Target
ns.On("PLAYER_TARGET_CHANGED", function()
    local info = checkUnit("target", "t")
    if info and not info.dead then state.targetGUID, state.targetKey = info.guid, info else state.targetGUID, state.targetKey = nil, nil end
end)
-- Target dead? (fallback when the combat log isn't readable) - cheap, only while a rare is targeted
local function checkTargetDead()
    if not state.targetKey then return end
    if not UnitExists("target") then return end
    local g = ns.safe(UnitGUID("target"))
    if g and state.targetGUID and g ~= state.targetGUID then return end
    if ns.safe(UnitIsDead("target")) == true then
        local info = state.targetKey
        state.targetGUID, state.targetKey = nil, nil
        Rares.Sight(info, nil, nil, nil, "tot", true)
    end
end
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(0.5, checkTargetDead) end)
ns.On("UNIT_HEALTH", function(unit) if unit == "target" and state.targetKey and not ns.inCombat() then checkTargetDead() end end)

-- Name plates
ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    unit = ns.safe(unit)
    if unit then checkUnit(unit, "n") end
end)

-- Kampflog (in Midnight ggf. gesperrt/geheim -> still ignorieren)
-- Do NOT register combat log: COMBAT_LOG_EVENT_UNFILTERED is forbidden for addons in Forever/Midnight
-- (RegisterEvent triggers 'Oasis was blocked').

-- Vignettes (skull/star on the minimap)
local function vignetteInfo(vguid)
    local V = C_VignetteInfo
    if not (V and V.GetVignetteInfo) then return nil end
    local ok, vi = pcall(V.GetVignetteInfo, vguid)
    if not ok or type(vi) ~= "table" then return nil end
    return vi
end
function Rares.ScanVignettes(force)
    local V = C_VignetteInfo
    if not (V and V.GetVignettes) or ns.inInstance() or flying() then return end
    if not force and GetTime() - state.vigAt < 2 then return end
    state.vigAt = GetTime()
    local ok, list = pcall(V.GetVignettes)
    if not ok or type(list) ~= "table" then return end
    local map = myPos()
    for _, vg in ipairs(list) do
        local vi = vignetteInfo(vg)
        if vi then
            local name = ns.safe(vi.name)
            local atlas = tostring(ns.safe(vi.atlasName) or ""):lower()
            local npc = npcFromGUID(vi.objectGUID)
            local isMob = npc ~= nil or atlas:find("kill", 1, true) or atlas:find("elite", 1, true) or atlas:find("rare", 1, true)
            if isMob and ns.validName(name) then
                local cls = atlas:find("elite", 1, true) and "rareelite" or "rare"
                local x, y
                if map and V.GetVignettePosition then
                    local okp, pos = pcall(V.GetVignettePosition, vg, map)
                    if okp and pos and pos.GetXY then x, y = pos:GetXY() x, y = ns.safe(x), ns.safe(y) end
                end
                local info = { key = keyOf(npc, name), npc = npc or 0, name = name, cls = cls }
                local og = ns.safe(vi.objectGUID)
                if og then state.guids[og] = info end
                Rares.Sight(info, map, x, y, "v", false)
            end
        end
    end
end
ns.On("VIGNETTE_MINIMAP_UPDATED", function() ns.After(0.3, function() Rares.ScanVignettes() end) end)
ns.On("VIGNETTES_UPDATED", function() ns.After(0.3, function() Rares.ScanVignettes() end) end)

------------------------------------------------------------------------
-- List for the page
------------------------------------------------------------------------
function Rares.List(filter)
    local demo = demoOn()
    local out = {}
    for _, r in ipairs(Store.List(SEEN, function(r) return (demo or not r.demo) and not Rares.NotBoss(r.name) end)) do
        r._key = keyOf(r.npc, r.name)
        r._zone = ns.zoneName(r.map, r.zone)
        if not filter or filter(r) then out[#out + 1] = r end
    end
    return out
end

local function clsText(cls) return (CLS_COLOR[cls] or "|cffc8c8c8") .. L[CLS_TAG[cls] or "Rare"] .. "|r" end
Rares.clsText = clsText

-- World map: set target (public API of Map.lua)
function Rares.ShowOnMap(rec)
    if type(rec) == "string" then rec = Rares.Get(rec) end
    if not rec or not rec.map then return end
    if ns.Map and ns.Map.SetTarget and rec.x and rec.x > 0 then
        ns.Map.SetTarget({ mapID = rec.map, x = rec.x / 10000, y = rec.y / 10000, label = rec.name,
            sub = ns.zoneName(rec.map, rec.zone) .. "  ·  " .. ns.ago(rec.ts) })
    elseif ns.Map and ns.Map.ShowOnWorldMap then
        ns.Map.ShowOnWorldMap(rec.map)
    end
end

------------------------------------------------------------------------
-- Notice on fresh sighting in own zone (throttled)
------------------------------------------------------------------------
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= SEEN and coll ~= KILLS then return end
    ns.RefreshPage("rares")
    if coll ~= SEEN or state.quiet or ns.demoLoading or rec.demo or rec.del then return end
    if not opt("rareToast") or ns.isMe(rec.by) or rec.st ~= "a" then return end
    if opt("rareFlyQuiet") and UnitOnTaxi and ns.safe(UnitOnTaxi("player")) == true then return end   -- don't disturb during flight
    local now = ns.now()
    if now - (rec.ts or 0) > FRESH then return end
    if old and old.st == "a" and now - (old.ts or 0) < 1800 then return end
    local myMap = myPos()
    if not myMap or myMap ~= rec.map then return end
    local key = keyOf(rec.npc, rec.name)
    if now - (state.toastAt[key] or 0) < 900 or now - state.toastAll < 45 then return end
    state.toastAt[key], state.toastAll = now, now
    K.Toast(L["Rare enemy in your zone"], (rec.name or "?") .. "  " .. clsText(rec.cls) .. "  ·  " .. (L["spotted by %s"]):format(ns.displayName(rec.by)),
        C.amber, function() Rares.ShowOnMap(rec) end)
end)

------------------------------------------------------------------------
-- World map pins (pattern like GatherMap: hooks Map.UpdateWorldPins)
------------------------------------------------------------------------
local wPool, wUsed = {}, 0
local function wPin(canvas)
    wUsed = wUsed + 1
    local p = wPool[wUsed]
    if not p then
        p = CreateFrame("Frame", nil, canvas)
        p:SetSize(16, 16)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.lbl = K.Text(p, 10, C.text)   -- 0.5.934: "40 min ago" next to the skull
        p.lbl:SetPoint("LEFT", p, "RIGHT", 2, 0)
        p.lbl:SetShadowOffset(1, -1)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wPool[wUsed] = p
    end
    if p:GetParent() ~= canvas then p:SetParent(canvas) end
    return p
end
local function pinTip(r)
    local next = Rares.NextText(r)
    return { (r.name or "?") .. "  " .. clsText(r.cls),
        (r.st == "d" and ("|cffe64047" .. L["killed"] .. "|r") or ("|cff66db9e" .. L["seen"] .. "|r")) .. " " .. ns.ago(r.ts) .. "  ·  " .. ns.displayName(r.by or "?"),
        L["Next spawn"] .. ": " .. next }
end
function Rares.DrawWorld()
    for i = 1, wUsed do wPool[i]:Hide() end
    wUsed = 0
    if not opt("rarePins") or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    local s = 1 / math.max(cscale, 0.01)
    local now = ns.now()
    for _, r in ipairs(Rares.List(function(r) return r.map == mapID and (r.x or 0) > 0 and now - (r.ts or 0) < 7 * 86400 end)) do
        local p = wPin(canvas)
        p.icon:SetTexture(SKULL)
        local alive = r.st == "a" and now - (r.ts or 0) < ALIVE_FOR
        p.icon:SetDesaturated(not alive)
        p.icon:SetAlpha(alive and 1 or 0.55)
        p.tip = pinTip(r)
        if opt("rareClock") then
            p.lbl:SetText(alive and ("|cff66db9e" .. L["alive now"] .. "|r") or ("|cffc8c8c8" .. ns.ago(r.ts) .. "|r"))
        else
            p.lbl:SetText("")
        end
        p:SetScale(s)
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", (r.x / 10000 * cw) / s, (-r.y / 10000 * ch) / s)
        p:SetFrameStrata(canvas:GetFrameStrata())
        p:SetFrameLevel(canvas:GetFrameLevel() + 56)
        p:Show()
    end
end

------------------------------------------------------------------------
-- Demo data (local only)
------------------------------------------------------------------------
local DEMO = {
    -- npc, name, class, mapID, x, y, zone, finder, seen ago (min), state, deaths ago (h)
    { 990501, "Grimfur the Elder", "rare", 1413, 0.42, 0.33, "The Barrens", "Hoknar", 3, "a", { 30, 22, 13.5, 6 } },
    { 990502, "Stormwing", "rareelite", 1413, 0.61, 0.52, "The Barrens", "Tavira", 95, "d", { 1.6, 9.1, 17.0 } },
    { 990503, "Clawmother Ishka", "rare", 1411, 0.38, 0.22, "Durotar", "Grukthar", 420, "d", { 7, 15, 26, 33 } },
    { 990504, "The Stone Eater", "rareelite", 1442, 0.55, 0.71, "Stonetalon Mountains", "Mokrash", 1500, "a", {} },
    { 990505, "Nightpaw", "rare", 1440, 0.71, 0.47, "Ashenvale", "Nakira", 50, "d", { 0.8, 4.9, 9.0, 13.2, 17.5 } },
    { 990506, "Azurewing", "worldboss", 1447, 0.52, 0.81, "Azshara", "Zul'mira", 2880, "d", { 48 } },
}
function Rares.SeedDemo()
    local now = ns.now()
    state.quiet = true
    for i, d in ipairs(DEMO) do
        local key = tostring(d[1])
        Store.merge(SEEN, { id = "demo-rs-" .. key, demo = true, u = now - d[9] * 60, npc = d[1], name = L[d[2]], cls = d[3],
            map = d[4], x = math.floor(d[5] * 10000), y = math.floor(d[6] * 10000), zone = L[d[7]], by = ns.fullName(d[8]),
            ts = now - d[9] * 60, st = d[10], dts = d[10] == "d" and (now - d[9] * 60) or nil })
        for j, h in ipairs(d[11]) do
            Store.merge(KILLS, { id = ("demo-rk-%s-%d"):format(key, j), demo = true, u = now - h * 3600, key = key, npc = d[1],
                name = L[d[2]], map = d[4], ts = math.floor(now - h * 3600), by = ns.fullName(d[8]) })
        end
    end
    state.quiet = false
    ns.RefreshPage("rares")
end
function Rares.RemoveDemo() ns.RefreshPage("rares") end

------------------------------------------------------------------------
-- Probe: what do the in-game interfaces deliver?
------------------------------------------------------------------------
ns.probes.rares = function()
    local function has(t, f) return (t and t[f]) and "ja" or "NEIN" end
    ns.print("|cffe8b44aProbe Seltene Gegner|r")
    ns.print(("  C_VignetteInfo: %s  GetVignettes: %s  GetVignetteInfo: %s  GetVignettePosition: %s"):format(
        C_VignetteInfo and "ja" or "NEIN", has(C_VignetteInfo, "GetVignettes"), has(C_VignetteInfo, "GetVignetteInfo"), has(C_VignetteInfo, "GetVignettePosition")))
    ns.print(("  UnitClassification: %s  CombatLogGetCurrentEventInfo: %s  Kampflog schon gelesen: %s"):format(
        UnitClassification and "ja" or "NEIN", CombatLogGetCurrentEventInfo and "ja" or "NEIN", tostring(state.combatLogOk or false)))
    local map, x, y = myPos()
    ns.print(("  Karte: %s (%s)  Position: %s"):format(tostring(map), ns.zoneName(map, "?"), x and ("%.3f, %.3f"):format(x, y) or "keine"))
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local ok, list = pcall(C_VignetteInfo.GetVignettes)
        ns.print(("  Vignetten jetzt: %s"):format(ok and type(list) == "table" and #list or ("Fehler " .. tostring(list))))
        if ok and type(list) == "table" then
            for i, vg in ipairs(list) do
                if i > 8 then break end
                local vi = vignetteInfo(vg)
                if vi then
                    local pos = "-"
                    if map and C_VignetteInfo.GetVignettePosition then
                        local okp, p = pcall(C_VignetteInfo.GetVignettePosition, vg, map)
                        if okp and p and p.GetXY then local px, py = p:GetXY() pos = ("%.3f, %.3f"):format(ns.safe(px) or -1, ns.safe(py) or -1) end
                    end
                    ns.print(("   - %s | atlas=%s | obj=%s | npc=%s | pos=%s"):format(tostring(ns.safe(vi.name)), tostring(ns.safe(vi.atlasName)),
                        tostring(ns.safe(vi.objectGUID)), tostring(npcFromGUID(vi.objectGUID)), pos))
                end
            end
        end
    end
    if UnitExists("target") then
        ns.print(("  Ziel: %s | Klasse=%s | GUID=%s | npc=%s | tot=%s"):format(tostring(ns.safe(ns.UnitName("target"))),
            tostring(ns.safe(UnitClassification and UnitClassification("target"))), tostring(ns.safe(UnitGUID("target"))),
            tostring(npcFromGUID(UnitGUID("target"))), tostring(ns.safe(UnitIsDead("target")))))
    else
        ns.print("  Ziel: keins (fuer den Test einen Gegner anvisieren)")
    end
    local plates, rare = 0, 0
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then
            plates = plates + 1
            local c = ns.safe(UnitClassification and UnitClassification(u))
            if wanted(c) then rare = rare + 1 ns.print(("   Plakette %s: %s (%s)"):format(u, tostring(ns.safe(ns.UnitName(u))), tostring(c))) end
        end
    end
    ns.print(("  Namensplaketten: %d, davon gesucht: %d"):format(plates, rare))
    local srcs = {}
    for k, t in pairs(state.sources) do srcs[#srcs + 1] = k .. "=" .. ns.ago(t) end
    ns.print(("  Gespeichert: %d Sichtungen, %d Tode  ·  Quellen zuletzt: %s"):format(#Store.List(SEEN), #Store.List(KILLS),
        #srcs > 0 and table.concat(srcs, ", ") or "-"))
end

------------------------------------------------------------------------
-- Settings (page gear)
------------------------------------------------------------------------
if ns.AddPageSettings then
    ns.AddPageSettings("rares", function(det, y)
        local items = {
            { "Share sightings with the guild", "rareShare", "Location, time and whether the enemy is alive or dead" },
            { "Notify on fresh sightings in my zone", "rareToast", "At most every 45 seconds, every 15 minutes per enemy" },
            { "Detect and report nothing while on a flight path", "rareFlyQuiet", "You cannot stop on a flight path anyway" },
            { "Skulls on the world map", "rarePins", "Sightings of the last 7 days" },
            { "Show time next to the skull", "rareClock", "Shows on the world map when the enemy was last seen" },
            { "Rare enemies on the minimap", "rareMini", "Sightings from the last 7 days near you" },
            { "Also record regular elites", "rareElites", "Open world only; can create many entries", true },
        }
        for _, it in ipairs(items) do
            local key, offDefault = it[2], it[4]
            local t = K.Toggle(det, L[it[1]], function()
                local v = S()[key]
                if v == nil then return not offDefault end
                return v and true or false
            end, function(v)
                S()[key] = v
                if WorldMapFrame and WorldMapFrame:IsShown() then pcall(Rares.DrawWorld) end
            end, L[it[3]])
            t:SetPoint("TOPLEFT", 14, y)
            t:SetWidth(600)
            if det.t then det.t[#det.t + 1] = t end
            y = y - 44
        end
        return y - 6
    end)
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local view, onlyZone, search = "recent", false, ""

local function rowsFor(list)
    -- group by zone, within that by last sighting
    table.sort(list, function(a, b)
        if a._zone ~= b._zone then return a._zone < b._zone end
        return (a.ts or 0) > (b.ts or 0)
    end)
    local out, last = {}, nil
    for _, r in ipairs(list) do
        if r._zone ~= last then
            last = r._zone
            out[#out + 1] = { header = true, text = r._zone ~= "" and r._zone or L["Unknown zone"] }
        end
        out[#out + 1] = r
    end
    return out
end

ns.RegisterPage({
    key = "rares", title = "Rare Enemies", order = 4.6,
    sub = "Rares and world bosses: who saw them where, when do they return",
    build = function(p)
        p.seg = K.Segments(p, { { key = "recent", text = L["Last 24 h"] }, { key = "all", text = L["All known"] },
            { key = "kills", text = L["Deaths"] } }, function(k) view = k ns.RefreshPage("rares") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.zoneBtn = K.Button(p, L["Only my zone"], 130, 24, "ghost", function()
            onlyZone = not onlyZone
            ns.RefreshPage("rares")
        end)
        p.zoneBtn:SetPoint("TOPRIGHT", 0, 0)
        p.search = K.Input(p, 150, L["Search ..."], function(t) search = (t or ""):lower() ns.RefreshPage("rares") end)
        p.search:SetPoint("RIGHT", p.zoneBtn, "LEFT", -8, 0)

        p.cards = {}
        local TD = { { ns.ICONS.rares, "Alive now", C.mint }, { ns.ICONS.map or ns.ICONS.rares, "Sightings 24 h", C.amber },
            { ns.ICONS.deaths or ns.ICONS.rares, "Kills 24 h", C.red }, { ns.ICONS.badges or ns.ICONS.rares, "Known enemies", C.blue } }
        for i, d in ipairs(TD) do
            local c = K.HudTile(p, d[1], L[d[2]], d[3])
            c:SetHeight(62)
            p.cards[i] = c
        end
        local function layoutCards(w)
            local tw = math.floor(((w or 750) - 30) / 4)
            for i, c in ipairs(p.cards) do
                c:SetWidth(tw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (tw + 10), -36)
            end
        end
        p:HookScript("OnSizeChanged", function(_, w) layoutCards(w) end)
        layoutCards(p:GetWidth())
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true

        p.list = K.List(p, 50, function(l)   -- 0.6.451: rows as calm cards with more air
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            r.card = r:CreateTexture(nil, "BACKGROUND", nil, -1)
            r.card:SetPoint("TOPLEFT", 0, -3) r.card:SetPoint("BOTTOMRIGHT", 0, 3)
            r.card:SetColorTexture(1, 1, 1, 0.035)
            if K.RoundMask then pcall(K.RoundMask, r.card, r, 8) end
            r.disc = r:CreateTexture(nil, "BORDER")
            r.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.disc:SetSize(30, 30)
            r.disc:SetPoint("LEFT", 8, 0)
            r.disc:SetVertexColor(0, 0, 0, 0.45)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("CENTER", r.disc, "CENTER")
            r.icon:SetTexture(SKULL)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("TOPLEFT", 48, -9)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -330, 0)
            r.cols.meta = K.Text(r, 11, C.muted)
            r.cols.meta:SetPoint("BOTTOMLEFT", 48, 9)
            r.cols.meta:SetPoint("RIGHT", r, "RIGHT", -330, 0)
            r.cols.state = K.Text(r, 11, C.text, "RIGHT")
            r.cols.state:SetPoint("TOPRIGHT", -82, -10)
            r.cols.state:SetWidth(250)
            r.cols.next = K.Text(r, 11, C.muted, "RIGHT")
            r.cols.next:SetPoint("BOTTOMRIGHT", -82, 10)
            r.cols.next:SetWidth(250)
            r.head = K.Title(r, 12, C.amber)
            r.head:SetPoint("LEFT", 10, -4)
            r.map = K.Button(r, L["Map"], 62, 22, "ghost")
            r.map:SetPoint("RIGHT", -10, 0)
            r.map.label:SetFont(K.FONT, 11, "")
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e or e.header then return end
                local lines = pinTip(e)
                local rs = Rares.Respawn(e._key)
                if rs.min then
                    lines[#lines + 1] = (L["Time between kills: shortest %s, median %s (%d samples)"]):format(dur(rs.min), dur(rs.median), rs.samples)
                end
                if (e.x or 0) > 0 then lines[#lines + 1] = ("|cff888888%s  %.1f, %.1f|r"):format(e._zone, e.x / 100, e.y / 100) end
                lines[#lines + 1] = " "
                lines[#lines + 1] = L["Click: show on map"]
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.item and not self.item.header then Rares.ShowOnMap(self.item) end end)
            return r
        end, function(r, e)
            local isHead = e.header
            r.head:SetShown(isHead)
            for _, f in ipairs({ r.icon, r.disc, r.card, r.cols.name, r.cols.meta, r.cols.state, r.cols.next, r.map }) do f:SetShown(not isHead) end
            if r.stripe then r.stripe:SetShown(not isHead and r.stripe:IsShown()) end
            if isHead then r.head:SetText(K.Upper(e.text)) return end
            local now = ns.now()
            if e._kill then
                r.icon:SetDesaturated(true)
                r.cols.name:SetText((e.name or "?"))
                r.cols.meta:SetText(ns.fmtDate(e.ts) .. "  ·  " .. ns.Radar.Colored(e.by or "?"))
                r.cols.state:SetText("|cffe64047" .. L["killed"] .. "|r " .. ns.ago(e.ts))
                r.cols.next:SetText(e._gap and ((L["Since previous kill: %s"]):format(dur(e._gap))) or "")
                r.map:Hide()
                return
            end
            local alive = e.st == "a" and now - (e.ts or 0) < ALIVE_FOR
            r.icon:SetDesaturated(not alive)
            r.cols.name:SetText((e.name or "?") .. "  " .. clsText(e.cls))
            r.cols.meta:SetText(((e.x or 0) > 0 and ("%.1f, %.1f  ·  "):format(e.x / 100, e.y / 100) or "") .. ns.Radar.Colored(e.by or "?"))
            r.cols.state:SetText((e.st == "d" and ("|cffe64047" .. L["killed"] .. "|r ") or ("|cff66db9e" .. L["seen"] .. "|r ")) .. ns.ago(e.ts))
            r.cols.next:SetText(Rares.NextText(e))
            r.map:SetScript("OnClick", function() Rares.ShowOnMap(e) end)
        end)
        p.list:SetPoint("TOPLEFT", 0, -108)
        p.list:SetPoint("BOTTOMRIGHT", 0, 20)
        p.foot = K.Text(p, 10, C.dim)
        p.foot:SetPoint("BOTTOMLEFT", 0, 3)
        p.foot:SetText(L["Recorded automatically: minimap skull, nameplates, your target.  Diagnostics: /oa probe rares"])
    end,

    refresh = function(p)
        p.seg:Select(view)
        p.zoneBtn.label:SetText(onlyZone and ("|cff66db9e" .. L["Only my zone"] .. "|r") or L["Only my zone"])
        local now = ns.now()
        local myMap = myPos()
        local all = Rares.List()
        -- Kacheln
        local alive, seen24, keys = 0, 0, 0
        for _, r in ipairs(all) do
            keys = keys + 1
            if r.st == "a" and now - (r.ts or 0) < ALIVE_FOR then alive = alive + 1 end
            if now - (r.ts or 0) < 86400 then seen24 = seen24 + 1 end
        end
        local demo = demoOn()
        local kills = Store.List(KILLS, function(r) return demo or not r.demo end)
        local k24 = 0
        for _, k in ipairs(kills) do if now - (k.ts or 0) < 86400 then k24 = k24 + 1 end end
        local fr = p.fresh
        p.cards[1]:Set(alive, nil, nil, fr)
        p.cards[2]:Set(seen24, nil, nil, fr)
        p.cards[3]:Set(k24, nil, nil, fr)
        p.cards[4]:Set(keys, nil, nil, fr)
        if fr then for i, c in ipairs(p.cards) do K.FadeIn(c, (i - 1) * 0.06) end p.fresh = false end

        local function match(r)
            if onlyZone and r.map ~= myMap then return false end
            if search ~= "" and not ((r.name or ""):lower():find(search, 1, true) or (r._zone or ""):lower():find(search, 1, true)) then return false end
            return true
        end
        if view == "kills" then
            local list = {}
            local byKey = {}
            for _, k in ipairs(kills) do
                k._zone = ns.zoneName(k.map, "")
                byKey[k.key] = byKey[k.key] or {}
                table.insert(byKey[k.key], k)
            end
            for _, ks in pairs(byKey) do
                table.sort(ks, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
                for i, k in ipairs(ks) do
                    k._gap = i > 1 and (k.ts - ks[i - 1].ts) or nil
                    k._kill = true
                    if match(k) then list[#list + 1] = k end
                end
            end
            table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
            p.list:SetData(list)
            p.list.empty:SetText(L["No rare kill recorded yet."])
            return
        end
        local list = {}
        for _, r in ipairs(all) do
            if (view == "all" or now - (r.ts or 0) < 86400) and match(r) then list[#list + 1] = r end
        end
        p.list:SetData(rowsFor(list))
        if C_VignetteInfo == nil and not UnitClassification then
            p.list.empty:SetText(L["This client does not report rare enemies (API missing). /oa probe rares shows details."])
        else
            p.list.empty:SetText(view == "all" and L["No sightings yet. As soon as someone with Oasis spots a rare enemy, it shows up here."]
                or L["Nobody has seen a rare enemy in the last 24 hours."])
        end
    end,
})

-- Navigation: in the "Play together" group, right after Dungeons
do
    local groups = ns.NAV_GROUPS
    if groups then
        for _, g in ipairs(groups) do
            if g.key == "raid" then
                local has = false
                for _, k in ipairs(g.pages) do if k == "rares" then has = true end end
                if not has then
                    local pos = #g.pages + 1
                    for i, k in ipairs(g.pages) do if k == "dungeons" then pos = i + 1 end end
                    table.insert(g.pages, pos, "rares")
                end
            end
        end
    end
end

ns.Listen("LOGIN", function()
    installProbe()
    prune()
    if ns.Map and ns.Map.UpdateWorldPins then hooksecurefunc(ns.Map, "UpdateWorldPins", function() pcall(Rares.DrawWorld) end) end
    ns.After(25, function()
        if IsInGuild() then
            local since = math.max(0, ((ns.db.rareMeta and ns.db.rareMeta.lastSync) or 0) - 3600)
            Comm.Guild("OARQ", GROUP, since)
        end
    end)
    ns.After(8, function() Rares.ScanVignettes(true) end)
    ns.Every(1, checkTargetDead)
    ns.Every(60, function() ns.RefreshPage("rares") end)
    ns.Every(1800, prune)
    local D = ns.Demo
    if D and not D.raresHooked then
        D.raresHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) Rares.SeedDemo() end
        D.Remove = function(...) remove(...) Rares.RemoveDemo() end
        if D.IsActive() then ns.After(3, Rares.SeedDemo) end
    end
end)
ns.Listen("STORE", function(coll)
    if (coll == SEEN) and WorldMapFrame and WorldMapFrame:IsShown() then pcall(Rares.DrawWorld) end
end)

------------------------------------------------------------------------
-- Minimap (0.5.934): sightings of the last 7 days in own zone as a small skull.
-- Math and state come from GatherMap (GM.MiniCtx / GM.MiniPlace).
------------------------------------------------------------------------
local mPool, mUsed, mList, mAt, mMap = {}, 0, {}, 0, nil
function Rares.DrawMinimap()
    for i = 1, mUsed do mPool[i]:Hide() end
    mUsed = 0
    local G = ns.Gather
    if not opt("rareMini") or not (G and G.MiniCtx) then return end
    local c = G.MiniCtx()
    if not c then return end
    local t = GetTime()
    if t - mAt > 2 or mMap ~= c.map then
        mAt, mMap = t, c.map
        local now = ns.now()
        mList = Rares.List(function(r) return r.map == c.map and (r.x or 0) > 0 and now - (r.ts or 0) < 7 * 86400 end)
    end
    local now = ns.now()
    for _, r in ipairs(mList) do
        local ox, oy, d = G.MiniPlace(c, r.x / 10000, r.y / 10000)
        if d < 0.9 and (not ns.MiniPinVisible or ns.MiniPinVisible(ox, oy)) then
            mUsed = mUsed + 1
            local p = mPool[mUsed]
            if not p then
                p = CreateFrame("Frame", nil, Minimap)
                p:SetSize(14, 14)
                if ns.MiniPinLayer then ns.MiniPinLayer(p, 3) end
                p.icon = p:CreateTexture(nil, "ARTWORK")
                p.icon:SetAllPoints()
                p.icon:SetTexture(SKULL)
                p:EnableMouse(true)
                p:SetScript("OnEnter", function(self) if self.rec then K.ShowTip(self, pinTip(self.rec)) end end)
                p:SetScript("OnLeave", function() GameTooltip:Hide() end)
                mPool[mUsed] = p
            end
            local alive = r.st == "a" and now - (r.ts or 0) < ALIVE_FOR
            p.icon:SetDesaturated(not alive)
            p:SetAlpha(alive and 1 or 0.6)
            p.rec = r
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
            p:Show()
        end
    end
end
ns.Listen("LOGIN", function()
    local f, acc = CreateFrame("Frame"), 0
    f:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.05 then return end
        acc = 0
        pcall(Rares.DrawMinimap)
    end)
end)
ns.Listen("STORE", function(coll) if coll == SEEN then mAt = 0 end end)
end)

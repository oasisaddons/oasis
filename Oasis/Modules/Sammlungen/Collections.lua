-- Oasis: Sammlungen - Reittiere, Haustiere, Spielzeuge der Gilde
--  Jeder Charakter teilt Zaehler + kompakte ID-Listen (Basis 36), nur bei Aenderung und gedrosselt.
--  Seite: Gilden-Rangliste, "Wer hat ...?", seltenste Stuecke der Gilde, Vergleich mit mir.
--  Eigene Sammlungen "coll_chars", "coll_mounts", "coll_pets", "coll_toys" (NICHT "collections" - so heisst
--  in Export.lua die Liste der geteilten Store-Sammlungen). Eigene Nachrichten OARU/OARQ/OARA/OARB wie Rares.lua.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Sammlungen", function()   -- Modul Sammlungen (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
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

local Coll = {}
ns.Collections = Coll
if ns.ICONS then ns.ICONS.sammlung = ns.MEDIA .. "icons\\badges" end

local CHARS = "coll_chars"
local LISTS = { mount = "coll_mounts", pet = "coll_pets", toy = "coll_toys" }
local KEEP = { coll_chars = 365 * 86400, coll_mounts = 365 * 86400, coll_pets = 365 * 86400, coll_toys = 365 * 86400 }
local GROUP = "sammlung"
local KINDS = { "mount", "pet" }   -- Spielzeuge gibt es in WoW Forever nicht
local KIND_NAME = { mount = "Reittiere", pet = "Haustiere", toy = "Spielzeuge" }
local KIND_ICON = { mount = "Interface\\Icons\\Ability_Mount_RidingHorse", pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
    toy = "Interface\\Icons\\INV_Misc_Toy_10" }
local SEND_GAP = 600       -- hoechstens alle 10 Min senden
local cache = { dirty = true }
local nameCache = {}
local lastScan = { mount = nil, pet = nil, toy = nil }
local scanPending, sendPending = false, false
local lastSentAt = 0

local function S() return ns.db.settings end
local function opt(key) local v = S()[key] if v == nil then return true end return v end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end

------------------------------------------------------------------------
-- Probe-Verteiler (gleiches Muster wie Rares.lua)
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
        ns.print(L["Probe-Themen: "] .. table.concat(keys, ", "))
    end
    ns._probeDispatch = dispatch
    ns.slash.probe = dispatch
end
installProbe()

------------------------------------------------------------------------
-- Kompakte ID-Listen (Basis 36, Komma)
------------------------------------------------------------------------
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIG:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end
local function packIds(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    for i, id in ipairs(ids) do ids[i] = b36(id) end
    return table.concat(ids, ","), #ids
end
local function unpackIds(s)
    local out = {}
    for p in (s or ""):gmatch("[^,]+") do
        local n = tonumber(p, 36)
        if n then out[n] = true end
    end
    return out
end
Coll.b36, Coll.packIds, Coll.unpackIds = b36, packIds, unpackIds

------------------------------------------------------------------------
-- Eigene Store-Anbindung
------------------------------------------------------------------------
local function isDemoRec(r) return r.demo or tostring(r.id):find("demo-", 1, true) end
local function clean(r)
    local c = {}
    for k, v in pairs(r) do if type(k) == "string" and k:sub(1, 1) ~= "_" then c[k] = v end end
    return c
end
local function put(coll, rec, send)
    rec.u = math.max(ns.now(), (rec.u or 0) + 1)
    rec.by = rec.by or ns.me()
    Store.merge(coll, rec)
    if send and not isDemoRec(rec) and IsInGuild() then
        Comm.SendEx({ ch = "GUILD", bulk = true }, "OARU", coll, Comm.encodeRecord(clean(rec)))
    end
    return rec
end
-- Empfang pruefen: jeder Datensatz gehoert seinem Ersteller (id = "<art>-<Name>", by = Name).
-- direkt (OARU): nur der eigene Datensatz des Absenders; weitergereicht (OARB): fremde Datensaetze nie
-- einem anderen Ersteller zuschlagen. Zeitstempel nicht in der Zukunft, Sammlung begrenzt.
local function sameWho(a, b) return a and b and Comm.whoKey(a) == Comm.whoKey(b) end
local function netOk(coll, rec, sender, relay)
    if type(rec) ~= "table" or type(rec.id) ~= "string" or #rec.id > 80 or isDemoRec(rec) then return false end
    if Comm.FromGuild and not Comm.FromGuild(sender) then return false end   -- nur Gildenmitglieder
    if rec.id:sub(1, #coll + 1) ~= coll .. "-" then return false end
    local owner = rec.id:sub(#coll + 2)
    if owner == "" or not rec.by or not sameWho(owner, rec.by) then return false end
    if not relay and not sameWho(rec.by, sender) then return false end
    if ns.isMe(rec.by) then return false end
    rec.u = math.min(tonumber(rec.u) or 0, ns.now() + 300)
    local c = Store.coll(coll)
    local old = c[rec.id]
    if old and old.by and not sameWho(old.by, rec.by) then return false end
    if not old then
        local n = 0
        for _ in pairs(c) do n = n + 1 if n >= 1500 then return false end end
    end
    return true
end
Coll.NetOk = netOk
Comm.On("OARU", function(sender, _, coll, s)
    if not KEEP[coll] or not s then return end
    local rec = Comm.decodeRecord(s)
    if netOk(coll, rec, sender, false) then Store.merge(coll, rec, true, sender) end
end)
Comm.On("OARB", function(sender, _, coll, ...)
    if not KEEP[coll] then return end
    for i = 1, math.min(select("#", ...), 200) do
        local s = select(i, ...)
        if s and s ~= "" then
            local rec = Comm.decodeRecord(s)
            if netOk(coll, rec, sender, true) then Store.merge(coll, rec, true, sender, true) end
        end
    end
    ns.db.collMeta = ns.db.collMeta or {}
    ns.db.collMeta.lastSync = ns.now()
end)
local pendingAnswer = {}
Comm.On("OARQ", function(sender, _, grp, since)
    if grp ~= GROUP or pendingAnswer[sender] then return end
    if not SEC.Rate("oarq:" .. sender, 60) then return end   -- keine Fluester-Flut auf Zuruf
    since = tonumber(since) or 0
    pendingAnswer[sender] = true
    ns.After(math.random(30, 120) / 10, function()
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

------------------------------------------------------------------------
-- Eigene Sammlung lesen (jede Schnittstelle per pcall - Forever kann sie weglassen)
------------------------------------------------------------------------
local function call(t, f, ...)
    if not t or type(t[f]) ~= "function" then return false end
    return pcall(t[f], ...)
end

-- Forever/Classic: Reittiere und Haustiere sind oft noch Gegenstaende in der Tasche (Journal leer).
-- Fallback: Taschen nach Gegenstaenden "Verschiedenes > Reittier" (15/5) bzw. "Haustier" (15/2) durchsuchen.
-- Quelle "b" = Item-ID. Liefert nil, wenn die Taschen-Schnittstelle fehlt.
local function scanBags(subclass, kindKey)
    local CC = C_Container
    local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
    local itemAt = (CC and CC.GetContainerItemID) or GetContainerItemID
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not (numSlots and itemAt and instant) then return nil end
    local set, n = {}, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local okN, slots = pcall(numSlots, bag)
        for slot = 1, (okN and tonumber(ns.safe(slots)) or 0) do
            local okI, id = pcall(itemAt, bag, slot)
            id = okI and ns.safe(id)
            if id and not set[id] then
                local okX, _, _, _, _, icon, classID, subID = pcall(instant, id)
                if okX and classID == 15 and subID == subclass then
                    set[id] = true n = n + 1
                    nameCache[kindKey .. ":b:" .. id .. ":i"] = icon
                end
            end
        end
    end
    return set, n
end
Coll.ScanBags = scanBags

-- Reittiere: { [id] = true }, Quelle ("j" = Journal-ID, "s" = Zauber-ID, "b" = Item in der Tasche) oder nil = keine Schnittstelle
function Coll.ScanMounts()
    local r1, r2, r3 = Coll.ScanMountsApi()
    if r1 and (r3 or 0) > 0 then return r1, r2, r3 end
    local bs, bn = scanBags(5, "mount")
    if bs and bn > 0 then return bs, "b", bn end
    return r1, r2, r3
end
function Coll.ScanMountsApi()
    local set, n = {}, 0
    local ok, ids = call(C_MountJournal, "GetMountIDs")
    if ok and type(ids) == "table" and #ids > 0 then
        for _, id in ipairs(ids) do
            local ok2, name, _, _, _, _, _, _, _, _, _, isCollected = call(C_MountJournal, "GetMountInfoByID", id)
            if ok2 and ns.safe(isCollected) == true then
                set[id] = true n = n + 1
                if ns.safe(name) then nameCache["mount:j:" .. id] = name end
            end
        end
        return set, "j", n
    end
    if GetNumCompanions and GetCompanionInfo then
        local okc, num = pcall(GetNumCompanions, "MOUNT")
        if okc and (num or 0) > 0 then
            for i = 1, num do
                local ok2, _, name, spellID = pcall(GetCompanionInfo, "MOUNT", i)
                if ok2 and spellID then set[spellID] = true n = n + 1 if name then nameCache["mount:s:" .. spellID] = name end end
            end
            return set, "s", n
        end
        if okc then return set, "s", 0 end
    end
    return nil
end

-- Haustiere: Arten-IDs; total = alle Exemplare (Fallback wie bei Reittieren: Tasche)
function Coll.ScanPets()
    local r1, r2, r3 = Coll.ScanPetsApi()
    if r1 and (r3 or 0) > 0 then return r1, r2, r3 end
    local bs, bn = scanBags(2, "pet")
    if bs and bn > 0 then return bs, "b", bn end
    return r1, r2, r3
end
function Coll.ScanPetsApi()
    local set, total = {}, 0
    local ok, num = call(C_PetJournal, "GetNumPets")
    if ok and type(num) == "number" then
        for i = 1, num do
            local ok2, petID, speciesID, owned, _, _, _, _, speciesName = call(C_PetJournal, "GetPetInfoByIndex", i)
            if ok2 and ns.safe(owned) and ns.safe(speciesID) then
                set[speciesID] = true total = total + 1
                if ns.safe(speciesName) then nameCache["pet:j:" .. speciesID] = speciesName end
            end
        end
        return set, "j", total
    end
    if GetNumCompanions and GetCompanionInfo then
        local okc, n = pcall(GetNumCompanions, "CRITTER")
        if okc then
            for i = 1, (n or 0) do
                local ok2, _, name, spellID = pcall(GetCompanionInfo, "CRITTER", i)
                if ok2 and spellID then set[spellID] = true total = total + 1 if name then nameCache["pet:s:" .. spellID] = name end end
            end
            return set, "s", total
        end
    end
    return nil
end

-- Spielzeuge: Item-IDs (angezeigte Liste + Gegenprobe fuer alle aus der Gilde bekannten IDs)
function Coll.ScanToys()
    if not C_ToyBox then return nil end
    local set, n = {}, 0
    local ok, num = call(C_ToyBox, "GetNumFilteredToys")
    if not ok then ok, num = call(C_ToyBox, "GetNumTotalDisplayedToys") end
    if not ok or type(num) ~= "number" then return nil end
    -- ohne PlayerHasToy laesst sich "besessen" nicht von "nur angezeigt" trennen -> lieber nichts melden
    local has = PlayerHasToy
    if not has then return nil end
    for i = 1, num do
        local ok2, itemID = call(C_ToyBox, "GetToyFromIndex", i)
        itemID = ok2 and ns.safe(itemID)
        if itemID and itemID > 0 then
            local okh, r = pcall(has, itemID)
            if okh and ns.safe(r) then set[itemID] = true end
        end
    end
    for id in pairs((cache.index and cache.index.toy) or {}) do
        if not set[id] then local okh, r = pcall(has, id) if okh and ns.safe(r) then set[id] = true end end
    end
    for _ in pairs(set) do n = n + 1 end
    return set, "j", n
end

------------------------------------------------------------------------
-- Namen und Symbole
------------------------------------------------------------------------
local DEMO_NAMES = {}
function Coll.Name(kind, id, src)
    src = src or "j"
    local ck = kind .. ":" .. src .. ":" .. id
    if nameCache[ck] then return nameCache[ck], nameCache[ck .. ":i"] end
    local name, icon
    if kind == "mount" and src == "j" then
        local ok, n, _, ic = call(C_MountJournal, "GetMountInfoByID", id)
        if ok then name, icon = ns.safe(n), ns.safe(ic) end
    elseif kind == "pet" and src == "j" then
        local ok, n, ic = call(C_PetJournal, "GetPetInfoBySpeciesID", id)
        if ok then name, icon = ns.safe(n), ns.safe(ic) end
    elseif kind == "toy" then
        local ok, _, n, ic = call(C_ToyBox, "GetToyInfo", id)
        if ok then name, icon = ns.safe(n), ns.safe(ic) end
        if not name and C_Item and C_Item.GetItemNameByID then
            local ok2, n2 = pcall(C_Item.GetItemNameByID, id)
            if ok2 then name = ns.safe(n2) end
        end
    end
    if not name and src == "b" then
        if C_Item and C_Item.GetItemNameByID then
            local ok2, n2 = pcall(C_Item.GetItemNameByID, id)
            if ok2 then name = ns.safe(n2) end
        end
        icon = nameCache[ck .. ":i"]
        if not icon and C_Item and C_Item.GetItemIconByID then
            local okI, ic = pcall(C_Item.GetItemIconByID, id)
            if okI then icon = ns.safe(ic) end
        end
        if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    if not name and src == "s" and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = ns.safe(n) end
    end
    if not name and DEMO_NAMES[kind] and DEMO_NAMES[kind][id] then name = L[DEMO_NAMES[kind][id]] end
    if name then nameCache[ck] = name nameCache[ck .. ":i"] = icon end
    return name or ("#" .. id), icon
end

------------------------------------------------------------------------
-- Eigene Daten erfassen und (gedrosselt, nur bei Aenderung) teilen
------------------------------------------------------------------------
local function myId(prefix) return prefix .. "-" .. (ns.me() or "?") end

function Coll.Scan()
    if not ns.me() then return end
    local scans = { mount = { Coll.ScanMounts() }, pet = { Coll.ScanPets() }, toy = {} }
    local counts, changed = {}, false
    for _, kind in ipairs(KINDS) do
        local set, src, n = scans[kind][1], scans[kind][2], scans[kind][3]
        lastScan[kind] = set and { n = n, src = src } or false
        if set then
            local packed, uniq = packIds(set)
            counts[kind] = { n = n, uniq = uniq }
            local h = ns.hash(src .. packed)
            local old = Store.Get(LISTS[kind], myId(LISTS[kind]))
            if not old or old.h ~= h then
                changed = true
                Store.merge(LISTS[kind], { id = myId(LISTS[kind]), by = ns.me(), ids = packed, n = n, src = src, h = h,
                    u = ns.now(), pending = true })
            end
        end
    end
    local _, cls = UnitClass("player")
    local cr = Store.Get(CHARS, myId(CHARS))
    local newC = { id = myId(CHARS), by = ns.me(), cls = cls or "", lvl = ns.safe(UnitLevel("player")) or 0,
        m = counts.mount and counts.mount.uniq or -1, p = counts.pet and counts.pet.uniq or -1,
        pt = counts.pet and counts.pet.n or -1, t = counts.toy and counts.toy.uniq or -1 }
    if not cr or cr.m ~= newC.m or cr.p ~= newC.p or cr.pt ~= newC.pt or cr.t ~= newC.t or cr.lvl ~= newC.lvl then
        changed = true
        newC.u = ns.now()
        newC.pending = true
        Store.merge(CHARS, newC)
    end
    cache.dirty = true
    if changed then Coll.QueueSend() end
    ns.RefreshPage("sammlung")
end

function Coll.QueueSend()
    if sendPending then return end
    sendPending = true
    local wait = math.max(5, SEND_GAP - (ns.now() - lastSentAt))
    ns.After(wait, function()
        sendPending = false
        Coll.SendPending()
    end)
end
function Coll.SendPending()
    if not opt("collShare") then return end
    lastSentAt = ns.now()
    for _, coll in ipairs({ CHARS, LISTS.mount, LISTS.pet, LISTS.toy }) do
        local r = Store.Get(coll, myId(coll))
        if r and r.pending then
            r.pending = nil
            put(coll, clean(r), true)
        end
    end
end

local function scanSoon(delay)
    if scanPending then return end
    scanPending = true
    ns.After(delay or 20, function()
        scanPending = false
        if ns.inCombat() then scanSoon(30) return end
        local ok, e = pcall(Coll.Scan)
        if not ok then ns.err("Sammlung", e) end
    end)
end
for _, ev in ipairs({ "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "COMPANION_UPDATE", "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE",
    "NEW_TOY_ADDED", "TOYS_UPDATED" }) do
    ns.On(ev, function() scanSoon(20) end)
end
-- Taschen-Fallback (Forever): Reittier/Haustier gekauft, gelernt oder abgegeben -> gedrosselt neu zaehlen
ns.On("BAG_UPDATE_DELAYED", function() scanSoon(60) end)

------------------------------------------------------------------------
-- Gilden-Auswertung
------------------------------------------------------------------------
-- Liefert eine Funktion Name -> einheitlicher Name. Erst ueber die Gildenliste (ns.ResolveName), danach - bei regional
-- eindeutigen Namen - ueber den Namen ohne Realm, damit auch Ausgetretene nicht doppelt stehen.
function Coll.NameMerger()
    local regional = RegionalUniqueNamesEnabled and ns.safe(RegionalUniqueNamesEnabled()) and true or false
    local byBase = {}
    local function base(n) return (n:match("^(.*)%-[^%-]+$") or n):lower() end
    local me = ns.me()
    if me and regional then byBase[base(me)] = me end
    return function(name)
        if ns.isMe(name) then return me end
        local who = ns.ResolveName and ns.ResolveName(name, true) or name
        if not regional then return who end
        local b = base(who)
        if not byBase[b] then byBase[b] = who end
        return byBase[b]
    end
end
-- cache.chars = { [name] = rec }, cache.own[kind][name] = set, cache.index[kind][id] = { owners }
local function rebuild()
    if not cache.dirty then return end
    local demo = demoOn()
    cache.chars, cache.own, cache.index, cache.src = {}, {}, {}, {}
    -- Derselbe Charakter kommt unter mehreren Schreibweisen an (nur Vorname, anderer Realm-Anhang): auf den Namen
    -- aus der Gildenliste zusammenfuehren, je Charakter zaehlt der neueste Datensatz.
    local canon = Coll.NameMerger()
    local stamp = {}
    for _, r in ipairs(Store.List(CHARS, function(r) return demo or not r.demo end)) do
        if r.by then
            local who = canon(r.by)
            if not cache.chars[who] or (r.u or 0) >= (stamp[who] or 0) then
                cache.chars[who], stamp[who] = r, r.u or 0
            end
        end
    end
    for _, kind in ipairs(KINDS) do
        cache.own[kind], cache.index[kind], cache.src[kind] = {}, {}, {}
        local newest, srcOf = {}, {}
        for _, r in ipairs(Store.List(LISTS[kind], function(r) return demo or not r.demo end)) do
            if r.by then
                local who = canon(r.by)
                if not cache.own[kind][who] or (r.u or 0) >= (newest[who] or 0) then
                    cache.own[kind][who], newest[who], srcOf[who] = unpackIds(r.ids), r.u or 0, r.src or "j"
                end
                if not cache.chars[who] then cache.chars[who] = { by = who, m = -1, p = -1, t = -1 } end
            end
        end
        cache.src[kind] = srcOf   -- 0.6.529: Quelle je Person (Sammlung einer Person ansehen)
        for who, set in pairs(cache.own[kind]) do
            for id in pairs(set) do
                local e = cache.index[kind][id]
                if not e then e = { id = id, owners = {}, src = srcOf[who] } cache.index[kind][id] = e end
                e.owners[#e.owners + 1] = who
            end
        end
    end
    cache.dirty = false
end
function Coll.Index(kind) rebuild() return cache.index[kind] or {} end
-- 0.6.529: was eine Person hat -> { { id, src, name, icon, mine }, ... } alphabetisch
function Coll.OwnedBy(kind, who)
    rebuild()
    local set = cache.own[kind] and cache.own[kind][who]
    local src = cache.src[kind] and cache.src[kind][who] or "j"
    local mine = {}
    for k, v in pairs(cache.own[kind] or {}) do if ns.isMe(k) then mine = v break end end
    local out = {}
    for id in pairs(set or {}) do
        local n, ic = Coll.Name(kind, id, src)
        out[#out + 1] = { id = id, src = src, name = n, icon = ic, mine = mine[id] == true }
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

------------------------------------------------------------------------
-- 0.6.529: Sammlung einer Person ansehen (Klick in der Rangliste)
------------------------------------------------------------------------
local pv
local function personView()
    if pv then return pv end
    local f = CreateFrame("Frame", "OasisCollPerson", UIParent)
    f:SetSize(440, 520)
    f:SetPoint("CENTER", 140, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true) f:EnableMouse(true) f:SetClampedToScreen(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, f, { 0.04, 0.04, 0.05, 0.97 }, { 1, 1, 1, 0.10 }, 12)) then K.Fill(f, { 0.04, 0.04, 0.05, 0.97 }) K.Border(f, C.line) end
    f.title = K.Title(f, 16, C.text) f.title:SetPoint("TOPLEFT", 18, -16) f.title:SetPoint("RIGHT", -40, 0)
    f.sub = K.Text(f, 11, C.muted) f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4) f.sub:SetPoint("RIGHT", -18, 0)
    local x = K.CloseButton(f, function() f:Hide() end) x:SetPoint("TOPRIGHT", -6, -6)
    f.kind, f.missing = "mount", false
    f.seg = K.Segments(f, { { key = "mount", text = L["Reittiere"] }, { key = "pet", text = L["Haustiere"] }, { key = "toy", text = L["Spielzeuge"] } },
        function(k) f.kind = k f:Fill() end, nil, { size = 12 })
    f.seg:SetPoint("TOPLEFT", 14, -60)
    f.miss = K.Toggle(f, L["Nur was mir fehlt"], function() return f.missing end, function(v) f.missing = v and true or false f:Fill() end)
    f.miss:SetPoint("TOPLEFT", 18, -90)
    f.miss:SetWidth(260)
    f.list = K.List(f, 30, function(l)
        local r = K.Row(l)
        r.icon = K.Icon(r, 22, nil) r.icon:SetPoint("LEFT", 8, 0)
        r.n = K.Text(r, 12, C.text) r.n:SetPoint("LEFT", 38, 0) r.n:SetPoint("RIGHT", -110, 0) r.n:SetWordWrap(false)
        r.tag = K.Text(r, 10, C.dim, "RIGHT") r.tag:SetPoint("RIGHT", -10, 0)
        r:SetScript("OnEnter", function(self)
            local e = self.item
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = false
            if e.src == "b" or f.kind == "toy" then ok = pcall(GameTooltip.SetItemByID, GameTooltip, e.id)
            elseif f.kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
                local okM, _, spell = pcall(C_MountJournal.GetMountInfoByID, e.id)
                if okM and ns.safe(spell) then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, spell) end
            end
            if not ok then GameTooltip:AddLine(e.name or "?") end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e)
        r.icon:SetTexture(e.icon or KIND_ICON[f.kind])
        r.n:SetText(e.name or ("#" .. e.id))
        r.tag:SetText(f.self and "" or (e.mine and ("|cff66db9e" .. L["hast du auch"] .. "|r") or ("|cffe8b44a" .. L["fehlt dir"] .. "|r")))
    end)
    f.list:SetPoint("TOPLEFT", 12, -124) f.list:SetPoint("BOTTOMRIGHT", -12, 14)
    function f:Fill()
        local all = Coll.OwnedBy(self.kind, self.who)
        local list, both = {}, 0
        for _, e in ipairs(all) do
            if e.mine then both = both + 1 end
            if not (self.missing and e.mine) then list[#list + 1] = e end
        end
        self.list:SetData(list)
        self.list.empty:SetText(#all == 0 and L["Davon hat Oasis bei dieser Person noch nichts gesehen."] or (#list == 0 and L["Du hast alles davon."] or ""))
        self.sub:SetText(self.self and ((L["%d Stueck"]):format(#all))
            or ((L["%d Stueck  -  %d hast du auch, %d fehlen dir"]):format(#all, both, #all - both)))
        self.miss:SetShown(not self.self)
        self.seg:Select(self.kind)
    end
    if ns.EscClose then ns.EscClose("OasisCollPerson") end
    pv = f
    return f
end
function Coll.ShowPerson(who, kind)
    if not who then return end
    local f = personView()
    f.who, f.self = who, ns.isMe(who)
    if kind then f.kind = kind end
    f.title:SetText((L["Sammlung von %s"]):format(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(who) or ns.short(who)))
    f:Fill()
    f:Show()
    f:Raise()
end
function Coll.Chars() rebuild() return cache.chars or {} end

local function countOf(c, kind)
    local v = kind == "mount" and c.m or kind == "pet" and c.p or c.t
    return (v and v >= 0) and v or 0
end
function Coll.Ranking(kind)
    local out = {}
    for name, c in pairs(Coll.Chars()) do
        -- Charaktere ohne jede Sammlungs-Schnittstelle (alle -1) nicht in die Rangliste
        if (c.m or -1) >= 0 or (c.p or -1) >= 0 or (c.t or -1) >= 0 then
            local m, p, t = countOf(c, "mount"), countOf(c, "pet"), countOf(c, "toy")
            out[#out + 1] = { name = name, m = m, p = p, t = t, total = m + p, score = kind and countOf(c, kind) or (m + p), cls = c.cls }
        end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
    return out
end

ns.Listen("STORE", function(coll)
    if coll == CHARS or KEEP[coll] then cache.dirty = true ns.RefreshPage("sammlung") end
end)

------------------------------------------------------------------------
-- Demo-Daten (nur lokal)
------------------------------------------------------------------------
DEMO_NAMES.mount = { [990601] = "Schneller Steppenwolf", [990602] = "Rostiger Kodo", [990603] = "Skelettpferd der Verlassenen",
    [990604] = "Schwarzer Kriegsraptor", [990605] = "Kriegsbaer der Frostwoelfe", [990606] = "Smaragdgruener Drachenhabicht" }
DEMO_NAMES.pet = { [990701] = "Praeriehund", [990702] = "Kakerlake", [990703] = "Mechanisches Eichhoernchen", [990704] = "Kleiner Drache (Smaragd)" }
DEMO_NAMES.toy = { [990801] = "Leuchtrakete", [990802] = "Trommel der Ahnen", [990803] = "Diskoball", [990804] = "Gnomen-Verkleinerer" }
local DEMO_PEOPLE = {
    { "Hoknar", "SHAMAN", 60, { 990601, 990602, 990605 }, { 990701, 990702 }, { 990801, 990803 } },
    { "Tavira", "MAGE", 58, { 990601, 990606 }, { 990701, 990703, 990704 }, { 990801 } },
    { "Grukthar", "WARRIOR", 60, { 990601, 990602, 990604 }, { 990702 }, { 990801, 990802, 990803, 990804 } },
    { "Nakira", "HUNTER", 44, { 990602 }, { 990701, 990702, 990703 }, {} },
    { "Mokrash", "PALADIN", 37, { 990603 }, {}, { 990801 } },
}
function Coll.SeedDemo()
    local now = ns.now()
    for _, d in ipairs(DEMO_PEOPLE) do
        local who = ns.fullName(d[1])
        local sets = { mount = d[4], pet = d[5], toy = d[6] }
        for _, kind in ipairs(KINDS) do
            local set = {}
            for _, id in ipairs(sets[kind]) do set[id] = true end
            local packed, n = packIds(set)
            Store.merge(LISTS[kind], { id = "demo-" .. LISTS[kind] .. "-" .. d[1], demo = true, u = now, by = who, ids = packed, n = n, src = "j" })
        end
        Store.merge(CHARS, { id = "demo-cc-" .. d[1], demo = true, u = now, by = who, cls = d[2], lvl = d[3],
            m = #d[4], p = #d[5], pt = #d[5], t = #d[6] })
    end
    cache.dirty = true
    ns.RefreshPage("sammlung")
end
function Coll.RemoveDemo() cache.dirty = true ns.RefreshPage("sammlung") end

------------------------------------------------------------------------
-- Probe
------------------------------------------------------------------------
ns.probes.sammlung = function()
    local function has(t, f) return (t and type(t[f]) == "function") and "ja" or "NEIN" end
    ns.print("|cffe8b44aProbe Sammlungen|r")
    ns.print(("  C_MountJournal: %s (GetMountIDs %s, GetMountInfoByID %s)  GetNumCompanions: %s"):format(C_MountJournal and "ja" or "NEIN",
        has(C_MountJournal, "GetMountIDs"), has(C_MountJournal, "GetMountInfoByID"), GetNumCompanions and "ja" or "NEIN"))
    ns.print(("  C_PetJournal: %s (GetNumPets %s, GetPetInfoByIndex %s, GetPetInfoBySpeciesID %s)"):format(C_PetJournal and "ja" or "NEIN",
        has(C_PetJournal, "GetNumPets"), has(C_PetJournal, "GetPetInfoByIndex"), has(C_PetJournal, "GetPetInfoBySpeciesID")))
    ns.print(("  C_ToyBox: %s (GetNumFilteredToys %s, GetToyFromIndex %s, GetToyInfo %s)  PlayerHasToy: %s"):format(C_ToyBox and "ja" or "NEIN",
        has(C_ToyBox, "GetNumFilteredToys"), has(C_ToyBox, "GetToyFromIndex"), has(C_ToyBox, "GetToyInfo"), PlayerHasToy and "ja" or "NEIN"))
    local ok, a, b = call(C_PetJournal, "GetNumPets")
    if ok then ns.print(("  GetNumPets: %s / %s (Filter im Haustier-Fenster beeinflussen das!)"):format(tostring(a), tostring(b))) end
    for _, kind in ipairs(KINDS) do
        local fn = kind == "mount" and Coll.ScanMounts or kind == "pet" and Coll.ScanPets or Coll.ScanToys
        local okS, set, src, n = pcall(fn)
        if not okS then
            ns.print(("  %s: Fehler %s"):format(L[KIND_NAME[kind]], tostring(set)))
        elseif not set then
            ns.print(("  %s: keine Schnittstelle"):format(L[KIND_NAME[kind]]))
        else
            local packed, uniq = packIds(set)
            local ex = {}
            for id in pairs(set) do
                if #ex >= 3 then break end
                ex[#ex + 1] = id .. "=" .. tostring((Coll.Name(kind, id, src)))
            end
            ns.print(("  %s: %d verschieden, %s gesamt, Quelle %s, %d Zeichen  z.B. %s"):format(L[KIND_NAME[kind]], uniq, tostring(n), tostring(src), #packed,
                #ex > 0 and table.concat(ex, ", ") or "-"))
        end
    end
    local nChars = 0
    for _ in pairs(Coll.Chars()) do nChars = nChars + 1 end
    ns.print(("  Bekannte Charaktere mit Sammlung: %d  ·  Teilen: %s"):format(nChars, opt("collShare") and "an" or "aus"))
end

------------------------------------------------------------------------
-- Einstellungen
------------------------------------------------------------------------
if ns.AddPageSettings then
    ns.AddPageSettings("sammlung", function(det, y)
        local t = K.Toggle(det, L["Meine Sammlung mit der Gilde teilen"], function() return opt("collShare") end,
            function(v) S().collShare = v if v then Coll.QueueSend() end end,
            L["Anzahl und Liste von Reittieren, Haustieren und Spielzeugen - nur bei Aenderung, hoechstens alle 10 Minuten"])
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        if det.t then det.t[#det.t + 1] = t end
        return y - 50
    end)
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local view, kind, search, selected = "rank", "mount", "", nil

local function ownersText(owners, max)
    local t = {}
    table.sort(owners)
    for i, n in ipairs(owners) do
        if i > (max or 6) then t[#t + 1] = "|cff888888+" .. (#owners - (max or 6)) .. "|r" break end
        t[#t + 1] = ns.Radar.Colored(n)
    end
    return table.concat(t, ", ")
end

local function itemList(filter, sorter)
    local out = {}
    local mine = (cache.own and cache.own[kind] and cache.own[kind][ns.me()]) or {}
    for id, e in pairs(Coll.Index(kind)) do
        e._name = Coll.Name(kind, id, e.src)
        e._mine = mine[id] and true or false
        if not filter or filter(e) then out[#out + 1] = e end
    end
    table.sort(out, sorter or function(a, b) return a._name < b._name end)
    return out
end

local function apiMissing()
    return lastScan.mount == false and lastScan.pet == false
end

local rankSort = nil     -- Rangliste nach "mount" / "pet" / "toy" sortiert, nil = Gesamt
local KCOL = { mount = C.amber, pet = C.mint, toy = C.blue }
local KORDER = { "mount", "pet" }
local CLASS_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function setClass(tex, cls)
    local tc = type(cls) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if tc then
        tex:SetTexture(CLASS_TEX)
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        tex:Show()
    else
        tex:Hide()
    end
end

ns.RegisterPage({
    key = "sammlung", title = "Sammlungen", order = 7.82,
    sub = "Reittiere und Haustiere der Gilde: Rangliste, wer hat was, Seltenes",
    build = function(p)
        -- 2026: Glas-Reiterleiste wie im Profil (Fallback: einfache Segmente)
        local IGL = ns.Insta
        local glass = function(f, fill, line, r) if IGL and IGL.Glass then IGL.Glass(f, fill, line, r) end end
        local round = function(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
        local function onTab(k) view = k selected = nil p.fresh = true ns.RefreshPage("sammlung") end
        local TABS = { { key = "rank", text = L["Rangliste"], icon = "stats" }, { key = "who", text = L["Wer hat ...?"], icon = "groups" },
            { key = "rare", text = L["Selten"], icon = "badges" }, { key = "me", text = L["Ich und die Gilde"], icon = "profile" } }
        if IGL and IGL.ProfileTabs then
            p.seg = IGL.ProfileTabs(p, TABS, onTab)
            p.seg:SetPoint("TOPRIGHT", 0, 0)
        else
            p.seg = K.Segments(p, TABS, onTab)
        end
        p.seg:SetPoint("TOPLEFT", 0, 0)
        local TOP = 44   -- Beginn der Karten unter der Reiterleiste
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true

        ----------------------------------------------------------------
        -- Sammlungs-Karten: eigene Zahl, Fortschritt gegen den Besten der Gilde, Klick = Auswahl/Sortierung
        ----------------------------------------------------------------
        p.cards = {}
        local function card(key, label, icon, col)
            local c = CreateFrame("Button", nil, p)
            -- 2026: Glaskarte, Zahl gross, Beschriftung normal geschrieben, runde Leiste; Auswahl = Kante in Sammlungsfarbe
            c:SetHeight(80)
            c.key = key
            c.col = col
            glass(c, nil, nil, 12)
            c.hov = c:CreateTexture(nil, "BORDER", nil, 3)
            c.hov:SetAllPoints()
            c.hov:SetColorTexture(1, 1, 1, 0.035)
            c.hov:Hide()
            round(c.hov, c, 12)
            c.icon = K.Icon(c, 30, icon)
            c.icon:SetPoint("TOPRIGHT", -14, -14)
            round(c.icon, c.icon, 6)
            c.lbl = K.Text(c, 11, C.muted)
            c.lbl:SetPoint("TOPLEFT", 14, -12)
            c.lbl:SetText(label)
            c.num = K.Title(c, 24, C.text)
            c.num:SetPoint("TOPLEFT", c.lbl, "BOTTOMLEFT", 0, -5)
            c.of = K.Text(c, 11, C.dim)
            c.of:SetPoint("BOTTOMLEFT", c.num, "BOTTOMRIGHT", 6, 3)
            c.of:SetPoint("RIGHT", c, "RIGHT", -10, 0)
            c.bar = K.Bar(c, 100, 4)
            c.bar:SetPoint("BOTTOMLEFT", 14, 12)
            c.bar:SetPoint("BOTTOMRIGHT", -14, 12)
            c.bar.fill:SetColorTexture(col[1], col[2], col[3], 0.9)
            round(c.bar.fill, c.bar, 2)
            c.sel = c:CreateTexture(nil, "OVERLAY")   -- nur noch Merker fuer den Auswahlzustand
            c.sel:SetAlpha(0)
            c.sel:Hide()
            function c:Mark(on)
                self.sel:SetShown(on and true or false)
                local k = self.col
                glass(self, on and { k[1], k[2], k[3], 0.07 } or nil, on and { k[1], k[2], k[3], 0.5 } or nil)
            end
            c:SetScript("OnEnter", function(self)
                self.hov:Show()
                if self.tipLines then K.ShowTip(self, self.tipLines) end
            end)
            c:SetScript("OnLeave", function(self)
                self.hov:Hide()
                GameTooltip:Hide()
            end)
            return c
        end
        for _, k in ipairs(KORDER) do
            local c = card(k, L[KIND_NAME[k]], KIND_ICON[k], KCOL[k])
            c:SetScript("OnClick", function(self)
                kind = self.key
                if view == "rank" then rankSort = (rankSort == self.key) and nil or self.key end
                selected = nil
                ns.RefreshPage("sammlung")
            end)
            p.cards[#p.cards + 1] = c
        end
        local pc = card("place", L["Dein Platz"], ns.ICONS.rank or ns.ICONS.badges, C.pink)
        pc:SetScript("OnClick", function() rankSort = nil view = "rank" p.fresh = true ns.RefreshPage("sammlung") end)
        p.cards[#p.cards + 1] = pc
        local function layoutCards(w)
            local n = #p.cards
            local tw = math.floor(((w or 750) - 10 * (n - 1)) / n)
            for i, c in ipairs(p.cards) do
                c:SetWidth(tw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (tw + 10), -TOP)
            end
        end
        p:HookScript("OnSizeChanged", function(_, w) layoutCards(w) if p.Relayout then p:Relayout() end end)
        layoutCards(p:GetWidth())

        p.search = K.Input(p, 220, L["Name suchen, z.B. Raptor ..."], function(t) search = (t or ""):lower() ns.RefreshPage("sammlung") end)
        p.search:SetPoint("TOPLEFT", 0, -(TOP + 80 + 12))
        p.search:SetHeight(26)
        glass(p.search, { 1, 1, 1, 0.03 }, nil, 9)
        p.hint = K.Text(p, 11, C.muted)
        p.hint:SetPoint("LEFT", p.search, "RIGHT", 12, 0)
        p.hint:SetPoint("RIGHT", p, "RIGHT", 0, 0)

        ----------------------------------------------------------------
        -- Rangliste: Podest fuer Platz 1-3, darunter die uebrigen mit Mehrfarben-Balken
        ----------------------------------------------------------------
        local pod = CreateFrame("Frame", nil, p)
        -- 2026: Podest als drei ruhige Glaskarten (Platz 1 in der Mitte etwas hoeher), Medaillenfarbe nur als
        -- dezente Toenung, Ring und Platz-Text; keine Bloecke, keine pulsierende Krone
        pod:SetPoint("TOPLEFT", 0, -(TOP + 80 + 10))
        pod:SetPoint("TOPRIGHT", 0, -(TOP + 80 + 10))
        pod:SetHeight(150)
        p.pod = pod
        pod.cols = {}
        local ORDER = { 2, 1, 3 }
        local PH = { 150, 134, 126 }
        local PCOL = { { 1, 0.80, 0.25 }, { 0.80, 0.83, 0.90 }, { 0.85, 0.55, 0.32 } }
        local PLACE_TXT = { "1. Platz", "2. Platz", "3. Platz" }
        for slot, place in ipairs(ORDER) do
            local col = CreateFrame("Button", nil, pod)
            col.place, col.slot = place, slot
            local pcl = PCOL[place]
            col:SetSize(200, PH[place])
            glass(col, { pcl[1], pcl[2], pcl[3], place == 1 and 0.07 or 0.045 }, { pcl[1], pcl[2], pcl[3], place == 1 and 0.45 or 0.28 }, 14)
            -- 0.6.445: mit Gildenmodul dieselben Bildkarten wie die Todeswuerfel-Rangliste (Gold/Silber/Bronze + Krone)
            if ns.GuildPack then
                local MED = { "gold", "silver", "bronze" }
                glass(col, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 14)
                col.card = col:CreateTexture(nil, "BACKGROUND", nil, 1)
                col.card:SetAllPoints()
                col.card:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_podium_" .. MED[place])
                if place == 1 then
                    col.crown = col:CreateTexture(nil, "OVERLAY")
                    col.crown:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_crown")
                    col.crown:SetSize(44, 22)
                    col.crown:SetPoint("BOTTOM", col, "TOP", 0, -8)
                end
            end
            col.num = K.Text(col, 11, pcl)
            col.num:SetPoint("TOPLEFT", 12, -10)
            col.num:SetText(L[PLACE_TXT[place]])
            col.ring = col:CreateTexture(nil, "BORDER", nil, 3)
            col.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            col.ring:SetSize(48, 48)
            col.ring:SetPoint("TOP", col, "TOP", 0, place == 1 and -24 or -18)
            col.ring:SetVertexColor(pcl[1], pcl[2], pcl[3], 0.5)
            col.cls = col:CreateTexture(nil, "ARTWORK")
            col.cls:SetSize(42, 42)
            col.cls:SetPoint("CENTER", col.ring)
            col.name = K.Text(col, 12, C.text, "CENTER")
            col.name:SetPoint("TOPLEFT", col.ring, "BOTTOMLEFT", -60, -8)
            col.name:SetPoint("TOPRIGHT", col.ring, "BOTTOMRIGHT", 60, -8)
            col.name:SetWordWrap(false)
            col.score = K.Title(col, place == 1 and 22 or 18, C.text, "CENTER")
            col.score:SetPoint("BOTTOM", col, "BOTTOM", 0, 14)
            col.hov = col:CreateTexture(nil, "BORDER", nil, 4)
            col.hov:SetAllPoints()
            col.hov:SetColorTexture(1, 1, 1, 0.035)
            col.hov:Hide()
            round(col.hov, col, 14)
            col:SetScript("OnEnter", function(self)
                if not self.e then return end
                local e = self.e
                self.hov:Show()
                K.ShowTip(self, { ns.displayName(e.name), (L["Reittiere"] .. ": " .. e.m), (L["Haustiere"] .. ": " .. e.p), L["Gesamt"] .. ": " .. e.total })
            end)
            col:SetScript("OnLeave", function(self) self.hov:Hide() GameTooltip:Hide() end)
            pod.cols[place] = col
        end
        function pod:Layout()
            local W = self:GetWidth() or 600
            local gap = 12
            local cw = math.min(230, math.floor((W - 2 * gap) / 3))
            local total = cw * 3 + gap * 2
            local x0 = math.floor((W - total) / 2)
            for place, col in pairs(self.cols) do
                col:ClearAllPoints()
                col:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x0 + (col.slot - 1) * (cw + gap), 0)
                col:SetSize(cw, PH[place])
            end
        end
        pod:SetScript("OnSizeChanged", function(self) self:Layout() end)

        p.rank = K.List(p, 30, function(l)
            local r = K.Row(l)
            r:Col("pos", 10, 30, 12, C.dim)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(20, 20)
            r.cls:SetPoint("LEFT", 44, 0)
            r:Col("name", 70, 190, 12)
            r.segs = {}
            for i = 1, 3 do
                local s = r:CreateTexture(nil, "ARTWORK")
                s:SetHeight(8)
                r.segs[i] = s
            end
            r.bg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.bg:SetHeight(6)
            r.bg:SetColorTexture(1, 1, 1, 0.06)
            -- runde Leiste: Ecken an der Spur, die Segmente werden an denselben Ecken abgerundet
            round(r.bg, r.bg, 3)
            for _, s in ipairs(r.segs) do s:SetHeight(6) round(s, r.bg, 3) end
            round(r.cls, r.cls, 10)
            r.sum = K.Title(r, 14, C.text, "RIGHT")
            r.sum:SetPoint("RIGHT", -14, 0)
            r.det = K.Text(r, 10, C.dim, "RIGHT")
            r.det:SetPoint("RIGHT", r.sum, "LEFT", -12, 0)
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if e then K.ShowTip(self, { ns.displayName(e.name), L["Reittiere"] .. ": " .. e.m, L["Haustiere"] .. ": " .. e.p, "|cff888888" .. L["Klick: ansehen, was genau"] .. "|r" }) end
            end)
            r:SetScript("OnClick", function(self) if self.item then Coll.ShowPerson(self.item.name, rankSort) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            r.cols.pos:SetText(e._pos .. ".")
            local me = ns.isMe(e.name)
            r.cols.name:SetText(ns.Radar.Colored(e.name) .. (me and ("  |cffe8b44a" .. L["(du)"] .. "|r") or ""))
            setClass(r.cls, e.cls)
            -- Mehrfarben-Balken (Reittiere/Haustiere/Spielzeuge) relativ zum Besten
            local W = math.max(80, (r:GetWidth() or 700) - 70 - 190 - 150)
            r.bg:ClearAllPoints()
            r.bg:SetPoint("LEFT", r, "LEFT", 266, 0)
            r.bg:SetWidth(W)
            local top = math.max(1, e.top or 1)
            local x = 0
            for i, k in ipairs(KORDER) do
                local v = (k == "mount" and e.m) or (k == "pet" and e.p) or e.t
                local w = math.max(0, math.floor(W * v / top))
                local s = r.segs[i]
                s:ClearAllPoints()
                s:SetPoint("LEFT", r, "LEFT", 266 + x, 0)
                s:SetWidth(math.max(0.01, w))
                s:SetShown(w > 0)
                local c = KCOL[k]
                s:SetColorTexture(c[1], c[2], c[3], rankSort and rankSort ~= k and 0.35 or 0.95)
                x = x + w
            end
            r.det:SetText(("|cffe8b44a%d|r  |cff66db9e%d|r"):format(e.m, e.p))
            r.sum:SetText(e.total)
            if r.sel then r.sel:SetShown(me) end
        end)

        -- Gegenstaende (Wer hat / Selten / Ich)
        p.items = K.List(p, 38, function(l)
            local r = K.Row(l)
            r.stripe = r:CreateTexture(nil, "ARTWORK")
            r.stripe:SetPoint("LEFT", 3, 0) r.stripe:SetSize(3, 14)
            round(r.stripe, r.stripe, 1)
            r.icon = K.Icon(r, 26, nil)
            r.icon:SetPoint("LEFT", 12, 0)
            round(r.icon, r.icon, 6)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 48, -5)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -150, 0)
            r.cols.name:SetWordWrap(false)
            r.cols.who = K.Text(r, 11, C.muted)
            r.cols.who:SetPoint("BOTTOMLEFT", 48, 5)
            r.cols.who:SetPoint("RIGHT", r, "RIGHT", -150, 0)
            r.cols.who:SetWordWrap(false)
            r.tag = K.Text(r, 9, C.pink, "RIGHT")
            r.tag:SetPoint("TOPRIGHT", -14, -6)
            r.cols.n = K.Title(r, 17, C.amber, "RIGHT")
            r.cols.n:SetPoint("BOTTOMRIGHT", -14, 5)
            r.share = K.Bar(r, 60, 4)
            r.share:SetPoint("RIGHT", r.cols.n, "LEFT", -10, 0)
            round(r.share.fill, r.share, 2)
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e then return end
                local lines = { e._name, (L["%d Charaktere haben es:"]):format(#e.owners) }
                local o = {}
                for _, n in ipairs(e.owners) do o[#o + 1] = n end
                table.sort(o)
                for i, n in ipairs(o) do
                    if i > 20 then lines[#lines + 1] = "|cff888888+" .. (#o - 20) .. "|r" break end
                    lines[#lines + 1] = "  " .. ns.Radar.Colored(n)
                end
                lines[#lines + 1] = e._mine and ("|cff66db9e" .. L["Hast du auch."] .. "|r") or ("|cff888888" .. L["Hast du noch nicht."] .. "|r")
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            local _, icon = Coll.Name(kind, e.id, e.src)
            r.icon:SetTexture(icon or KIND_ICON[kind])
            local kc = KCOL[kind]
            r.stripe:SetColorTexture(kc[1], kc[2], kc[3], e._mine and 0.9 or 0.25)
            r.cols.name:SetText((e._mine and "|cff66db9e" or "") .. e._name .. (e._mine and "|r" or ""))
            r.cols.who:SetText(ownersText(e.owners, 6))
            r.cols.n:SetText(#e.owners)
            local uniq = #e.owners == 1
            r.cols.n:SetTextColor(unpack(uniq and C.pink or C.amber))
            r.tag:SetText(uniq and L["Einzigartig"] or "")
            local chars = 0
            for _ in pairs(Coll.Chars()) do chars = chars + 1 end
            r.share:Set(chars > 0 and #e.owners / chars or 0)
            r.share.fill:SetColorTexture(uniq and C.pink[1] or kc[1], uniq and C.pink[2] or kc[2], uniq and C.pink[3] or kc[3], 0.9)
        end)

        function p:Relayout()
            local isRank = view == "rank"
            self.pod:SetShown(isRank)
            self.rank:ClearAllPoints()
            self.rank:SetPoint("TOPLEFT", 0, -(TOP + 80 + 10 + 150 + 10))
            self.rank:SetPoint("BOTTOMRIGHT")
            self.items:ClearAllPoints()
            self.items:SetPoint("TOPLEFT", 0, -(TOP + 80 + 12 + 26 + 10))
            self.items:SetPoint("BOTTOMRIGHT")
            self.pod:Layout()
        end
        -- Listen in eine ruhige Glasflaeche
        glass(p.rank, nil, nil, 12)
        glass(p.items, nil, nil, 12)
        p:Relayout()
    end,

    refresh = function(p)
        p.seg:Select(view)
        rebuild()
        local mineC = Coll.Chars()[ns.me()]
        local ranking = Coll.Ranking(view == "rank" and rankSort or kind)
        local pos
        for i, e in ipairs(ranking) do e._pos = i if ns.isMe(e.name) then pos = i end end
        local fr = p.fresh
        local function cnt(k)
            if lastScan[k] == false then return nil end
            return mineC and countOf(mineC, k) or 0
        end
        local function best(k)
            local b, who = 0, nil
            for n, c in pairs(Coll.Chars()) do local v = countOf(c, k) if v > b then b, who = v, n end end
            return b, who
        end
        for i, k in ipairs(KORDER) do
            local c = p.cards[i]
            local mine = cnt(k)
            local bv, bwho = best(k)
            -- freundliche leere Zustaende: keine Schnittstelle / noch nichts erfasst
            if mine == nil then
                c.num:SetText("|cff6b6b70–|r")
                c.of:SetText(L["in diesem Client nicht verfuegbar"])
            elseif mine == 0 and bv == 0 then
                c.num:SetText("|cff6b6b700|r")
                c.of:SetText(L["noch keine Daten"])
            else
                c.num:SetText(mine)
                c.of:SetText((L["von %d (Gildenbestwert)"]):format(bv))
            end
            local frac = (mine and bv > 0) and mine / bv or 0
            if fr and K.Tween and not (ns.db and ns.db.settings.noAnim) then
                K.Tween(c.bar, 0.6, function(q) c.bar:Set(frac * q) end, nil, i * 0.07)
            else
                c.bar:Set(frac)
            end
            c:Mark((view ~= "rank" and kind == k) or (view == "rank" and rankSort == k))
            c.tipLines = { L[KIND_NAME[k]], bwho and ((L["Meiste: %s (%d)"]):format(ns.displayName(bwho), bv)) or L["Noch keine Daten aus der Gilde."],
                "|cff666666" .. (view == "rank" and L["Klick: Rangliste danach sortieren"] or L["Klick: diese Sammlung zeigen"]) .. "|r" }
        end
        local pcard = p.cards[#p.cards]
        pcard.num:SetText(pos or "–")
        pcard.of:SetText((L["von %d"]):format(#ranking))
        pcard.bar:Set((pos and #ranking > 0) and (1 - (pos - 1) / #ranking) or 0)
        pcard:Mark(view == "rank" and rankSort == nil)
        if not pos then pcard.of:SetText(#ranking > 0 and L["noch nicht in der Rangliste"] or L["noch keine Daten"]) end
        pcard.tipLines = { L["Dein Platz"], "|cff666666" .. L["Klick: Gesamtrangliste"] .. "|r" }
        if fr then
            if K.FadeIn then for i, c in ipairs(p.cards) do K.FadeIn(c, (i - 1) * 0.06) end end
            p.fresh = false
        end

        local isRank = view == "rank"
        p:Relayout()
        p.rank:SetShown(isRank)
        p.items:SetShown(not isRank)
        p.search:SetShown(view == "who" or view == "me")
        p.hint:SetShown(not isRank)
        if isRank then
            -- Balken-Bezug: bei Sortierung nach einer Art zaehlt trotzdem die Gesamtsumme des Besten
            local maxTot = 1
            for _, e in ipairs(ranking) do maxTot = math.max(maxTot, e.total) end
            -- Podest
            p.pod:Layout()
            for place, col in pairs(p.pod.cols) do
                local e = ranking[place]
                col.e = e
                if e then
                    col.name:SetText(ns.Radar.Colored(e.name))
                    col.score:SetText(rankSort and (rankSort == "mount" and e.m or rankSort == "pet" and e.p or e.t) or e.total)
                    setClass(col.cls, e.cls)
                    if col.crown then col.crown:Show() end
                    col:SetAlpha(1)
                else
                    col.name:SetText("|cff555555" .. L["frei"] .. "|r")
                    col.score:SetText("")
                    col.cls:Hide()
                    if col.crown then col.crown:Hide() end
                    col:SetAlpha(0.45)
                end
            end
            local rest = {}
            for i = 4, #ranking do ranking[i].top = maxTot rest[#rest + 1] = ranking[i] end
            p.rank:SetData(rest)
            p.rank.empty:SetText(#ranking > 3 and "" or (#ranking > 0 and ("|cff6b6b70" .. L["Weitere Plaetze erscheinen, sobald mehr Gildenmitglieder mit Oasis ihre Sammlung teilen."] .. "|r")
                or (apiMissing() and L["Dieser Client hat keine Sammlungs-Schnittstelle. /oa probe sammlung zeigt Details."]
                or L["Noch keine Daten - oeffne einmal das Sammlungsfenster oder trage Reittiere und Haustiere in der Tasche. Sobald Gildenmitglieder mit Oasis online sind, erscheinen sie hier."])))
            return
        end
        local function hit(e) return search == "" or e._name:lower():find(search, 1, true) end
        local list
        if view == "who" then
            list = itemList(hit, function(a, b) if #a.owners ~= #b.owners then return #a.owners > #b.owners end return a._name < b._name end)
            p.hint:SetText((L["%d verschiedene %s in der Gilde"]):format(#list, L[KIND_NAME[kind]]))
            p.items.empty:SetText(search ~= "" and L["Niemand in der Gilde hat etwas mit diesem Namen."] or L["Noch keine Daten aus der Gilde."])
        elseif view == "rare" then
            list = itemList(nil, function(a, b) if #a.owners ~= #b.owners then return #a.owners < #b.owners end return a._name < b._name end)
            local only = 0
            for _, e in ipairs(list) do if #e.owners == 1 then only = only + 1 end end
            p.hint:SetText((L["%d Stuecke besitzt nur ein einziger Charakter"]):format(only))
            p.items.empty:SetText(L["Noch keine Daten aus der Gilde."])
        else
            list = itemList(function(e) return not e._mine and hit(e) end,
                function(a, b) if #a.owners ~= #b.owners then return #a.owners > #b.owners end return a._name < b._name end)
            local mineN, onlyMe = 0, 0
            for _, e in pairs(Coll.Index(kind)) do
                if e._mine then mineN = mineN + 1 if #e.owners == 1 then onlyMe = onlyMe + 1 end end
            end
            local total = 0
            for _ in pairs(Coll.Index(kind)) do total = total + 1 end
            p.hint:SetText((L["Du hast %d von %d bekannten %s, %d davon nur du. Liste: was andere haben und dir fehlt."]):format(
                mineN, total, L[KIND_NAME[kind]], onlyMe))
            p.items.empty:SetText(L["Dir fehlt nichts, was die Gilde hat - stark!"])
        end
        p.items:SetData(list)
    end,
})

-- Navigation: Gruppe "Ich"
do
    local groups = ns.NAV_GROUPS
    if groups then
        for _, g in ipairs(groups) do
            if g.key == "me" then
                local has = false
                for _, k in ipairs(g.pages) do if k == "sammlung" then has = true end end
                if not has then table.insert(g.pages, "sammlung") end
            end
        end
    end
end

ns.Listen("LOGIN", function()
    installProbe()
    local now = ns.now()
    for coll, keep in pairs(KEEP) do
        local c = Store.coll(coll)
        for id, r in pairs(c) do if type(r) ~= "table" or now - (r.u or 0) > keep then c[id] = nil end end
    end
    scanSoon(45)
    ns.After(35, function()
        if IsInGuild() then
            local since = math.max(0, ((ns.db.collMeta and ns.db.collMeta.lastSync) or 0) - 3600)
            Comm.Guild("OARQ", GROUP, since)
        end
    end)
    local D = ns.Demo
    if D and not D.collHooked then
        D.collHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) Coll.SeedDemo() end
        D.Remove = function(...) remove(...) Coll.RemoveDemo() end
        if D.IsActive() then ns.After(3, Coll.SeedDemo) end
    end
end)
end)

-- Oasis: Gildenweite Upgrade-Suche (BoE-Matching)
-- Jeder Oasis-Client teilt freiwillig seine HANDELBAREN Ausruestungsteile (nicht seelengebunden, Taschen + Bank)
-- und kompakt seine angelegte Ausruestung (Platz -> Wertung nach eigener Rolle) + Klasse/Stufe/Rolle.
-- Lokal wird verglichen: welches geteilte Teil (auch Gildenbank) ist fuer wen ein Upgrade?
-- Daten: ns.db.store.gearmatch (ein Datensatz je Charakter, id = Charaktername), Nachricht "GMS".
-- Feld gb = beste Wertung je Platz aus ALLEN tragbaren Teilen in Taschen + gemerkter Bank (auch seelengebunden),
-- damit gelagerte bessere Teile (z.B. Tank-Schild) kein schlechteres "Upgrade" ausloesen. Schluessel wie g
-- (Platznummer), dazu 21 = Zweihand, 22 = Schild, 23 = Nebenhand-Gegenstand. Alte Clients ohne gb: wie bisher.
-- Bewertung kommt aus Upgrade.lua (UP.Score / UP.Role / UP.CanWearFor) - hier wird nichts nachgebaut.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Upgrades", function()   -- Modul Upgrade-Suche (abschaltbar, siehe ModuleLoader.lua)
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

local GM = {}
ns.GearMatch = GM

local COLL = "gearmatch"
local KEEP = 21 * 86400          -- aeltere Datensaetze (Spieler lange nicht da) verwerfen
local MAX_ITEMS = 80
local SEND_GAP = 60              -- hoechstens alle 60 s senden
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local GB_OWNER = "@gildenbank"
-- Lagerschluessel fuer gb (Ausruestungsort -> Schluessel)
local STORE_KEY = { INVTYPE_2HWEAPON = 21, INVTYPE_SHIELD = 22, INVTYPE_HOLDABLE = 23,
    INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17 }

if ns.ICONS and ns.MEDIA then ns.ICONS.gearmatch = ns.MEDIA .. "icons\\stats" end
-- Navigation: unter "Handel" einsortieren (ohne Main.lua zu aendern)
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "trade" then
        local has = false
        for _, k in ipairs(g.pages) do if k == "gearmatch" then has = true end end
        if not has then g.pages[#g.pages + 1] = "gearmatch" end
    end
end

-- Zustand (vor allen Funktionen, die ihn nutzen)
local lastHash, lastSent, sendPending = nil, 0, false
local myCache, myCacheT = nil, -100
local gainCache = {}
local tipCache = {}
local recalcPending = false
local quiet = false
local view = "forme"
local bankOpen = false

local function S() return ns.db.settings end
local function UP() return ns.Upgrade end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() or false end
local function shareOn() return not S().gmShareOff end
local function minPct() return tonumber(S().gmMinPct) or 5 end

------------------------------------------------------------------------
-- Item-Schluessel: "id" oder "id_suffix" (Zufallswerte "...des Adlers") <-> Link
------------------------------------------------------------------------
local function keyOf(link)
    if type(link) ~= "string" then return nil end
    local s = link:match("item:([%-%d:]*)")
    if not s then return nil end
    local f, i = {}, 0
    for part in (s .. ":"):gmatch("([^:]*):") do i = i + 1 f[i] = part end
    local id = tonumber(f[1])
    if not id then return nil end
    local suf = tonumber(f[7] or "")
    if suf and suf ~= 0 then return id .. "_" .. suf end
    return tostring(id)
end
GM.KeyOf = keyOf
local function linkOf(key)
    local id, suf = tostring(key):match("^(%d+)_?(%-?%d*)$")
    if not id then return nil end
    return "item:" .. id .. ":0:0:0:0:0:" .. ((suf ~= "" and suf) or "0")
end
GM.LinkOf = linkOf
local function idOf(key) return tonumber(tostring(key):match("^(%d+)")) end

local function itemName(id)
    local ok, n = pcall(function() return C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) end)
    n = ok and ns.safe(n) or nil
    if not n and ns.db.itemNames then
        local t = ns.db.itemNames[GetLocale()]
        n = t and t[id]
    end
    return n
end
local function qualityHex(id)
    local ok, q = pcall(function() return C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) end)
    q = ok and ns.safe(q) or nil
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return (c and c.hex) or "|cffffffff"
end
local function itemIcon(id)
    local ok, ic = pcall(function() return C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) end)
    return (ok and ns.safe(ic)) or 134400
end
-- echter Chat-Link (fuer die Fluester-Bitte), sonst [Name]
local function chatLink(key)
    local ok, _, hl = pcall(C_Item.GetItemInfo, linkOf(key))
    hl = ok and ns.safe(hl) or nil
    if type(hl) == "string" and hl:find("|H", 1, true) then return hl end
    return "[" .. (itemName(idOf(key)) or ("#" .. tostring(idOf(key)))) .. "]"
end
local function equipLoc(link)
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    return ok and ns.safe(loc) or nil
end
local function minLevel(link)
    local ok, _, _, _, _, req = pcall(C_Item.GetItemInfo, link)
    return ok and tonumber(ns.safe(req)) or 0
end

------------------------------------------------------------------------
-- Eigene Daten einlesen
------------------------------------------------------------------------
local function tradableIn(bags, out, seen)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    for _, bag in ipairs(bags) do
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, ((okN and tonumber(n)) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and info.hyperlink and not ns.safe(info.isBound) then
                local link = ns.safe(info.hyperlink)
                local loc = link and equipLoc(link)
                local q = tonumber(ns.safe(info.quality)) or 2
                if loc and UP() and UP().SLOTS[loc] and q >= 2 then
                    local k = keyOf(link)
                    if k and not seen[k] and #out < MAX_ITEMS then seen[k] = true out[#out + 1] = k end
                end
            end
        end
    end
end
-- beste Wertung je Lagerschluessel aus ALLEN tragbaren Teilen (auch seelengebunden) nach eigener Rolle
local function bestIn(bags, best, role, cls, lvl)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) or not UP() then return end
    for _, bag in ipairs(bags) do
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, ((okN and tonumber(n)) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            local link = ok and type(info) == "table" and ns.safe(info.hyperlink) or nil
            local loc = link and equipLoc(link)
            local slots = loc and UP().SLOTS[loc]
            if slots and UP().CanWearFor(link, cls, lvl) and minLevel(link) <= lvl then
                local k = STORE_KEY[loc] or slots[1]
                local sc = math.floor((UP().Score(link, role) or 0) * 10 + 0.5) / 10
                if sc > 0 and sc > (best[k] or 0) then best[k] = sc end
            end
        end
    end
end
local function packBest(best)
    local ks, parts = {}, {}
    for k in pairs(best) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do parts[#parts + 1] = k .. "=" .. best[k] end
    return table.concat(parts, ",")
end
local function bagIds() local t = {} for b = 0, (NUM_BAG_SLOTS or 4) do t[#t + 1] = b end return t end
local function bankIds()
    local t = { (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or (BANK_CONTAINER or -1) }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do t[#t + 1] = b end
    return t
end
local function bankStore()
    ns.db.gmBank = ns.db.gmBank or {}
    return ns.db.gmBank
end
function GM.ScanBank()
    if not bankOpen or ns.inCombat() then return end
    local out = {}
    tradableIn(bankIds(), out, {})
    bankStore()[ns.me() or "?"] = table.concat(out, ",")
    -- Bestwerte der Bank (alle tragbaren Teile) fuer gb merken
    if UP() then
        local _, cls = UnitClass("player")
        local lvl = tonumber(ns.safe(UnitLevel("player"))) or 1
        local role = UP().Role()
        local best = {}
        bestIn(bankIds(), best, role, cls, lvl)
        ns.db.gmBankBest = ns.db.gmBankBest or {}
        ns.db.gmBankBest[ns.me() or "?"] = { role = role, gb = packBest(best) }
    end
end

local function myGear(role)
    local parts, h2 = {}, false
    for _, s in ipairs(GEAR_SLOTS) do
        local ok, l = pcall(GetInventoryItemLink, "player", s)
        l = ok and ns.safe(l) or nil
        if l then
            local sc = UP().Score(l, role) or 0
            parts[#parts + 1] = s .. "=" .. (math.floor(sc * 10 + 0.5) / 10)
            -- Waffenstil: 1 = Zweihand, 2 = zwei Einhaender (Waffe in der Nebenhand)
            if s == 16 and equipLoc(l) == "INVTYPE_2HWEAPON" then h2 = 1 end
            if s == 17 and not h2 then
                local ol = equipLoc(l)
                if ol == "INVTYPE_WEAPON" or ol == "INVTYPE_WEAPONOFFHAND" then h2 = 2 end
            end
        end
    end
    return table.concat(parts, ","), h2
end

-- eigener Datensatz (live, kurz zwischengespeichert)
function GM.MyRecord(force)
    if not force and myCache and GetTime() - myCacheT < 2 then return myCache end
    if not UP() or not ns.me() then return nil end
    local _, cls = UnitClass("player")
    local role = UP().Role()
    local g, h2 = myGear(role)
    -- beste gelagerte Teile (Taschen + gemerkte Bank, gleiche Rolle)
    local lvl = tonumber(ns.safe(UnitLevel("player"))) or 1
    local best = {}
    pcall(bestIn, bagIds(), best, role, cls, lvl)
    local bb = ns.db.gmBankBest and ns.db.gmBankBest[ns.me()]
    if type(bb) == "table" and bb.role == role then
        for s, v in tostring(bb.gb or ""):gmatch("(%d+)=([%-%d%.]+)") do
            s, v = tonumber(s), tonumber(v)
            if s and v and v > (best[s] or 0) then best[s] = v end
        end
    end
    local items, seen = {}, {}
    if shareOn() then
        tradableIn(bagIds(), items, seen)
        for k in tostring(bankStore()[ns.me()] or ""):gmatch("[^,]+") do
            if not seen[k] and #items < MAX_ITEMS then seen[k] = true items[#items + 1] = k end
        end
    end
    myCache = { id = ns.me(), by = ns.me(), cls = cls, lvl = ns.safe(UnitLevel("player")) or 1, role = role,
        g = g, h2 = h2 or 0, gb = packBest(best), it = table.concat(items, ",") }
    myCacheT = GetTime()
    return myCache
end

------------------------------------------------------------------------
-- Teilen (gedrosselt, nur bei Aenderung)
------------------------------------------------------------------------
local function doShare(force)
    sendPending = false
    if ns.inCombat() or not IsInGuild() then return end
    local r = GM.MyRecord(true)
    if not r then return end
    local h = table.concat({ r.cls or "", r.lvl or 0, r.role or "", r.g or "", r.h2 or 0, r.gb or "", r.it or "" }, "|")
    if h == lastHash and not force then return end
    local wait = SEND_GAP - (GetTime() - lastSent)
    if wait > 0 then
        sendPending = true
        ns.After(wait + 0.5, function() doShare(force) end)
        return
    end
    lastHash, lastSent = h, GetTime()
    local rec = {}
    for k, v in pairs(r) do rec[k] = v end
    rec.u = ns.now()
    quiet = true
    Store.merge(COLL, rec)
    quiet = false
    Comm.SendEx({ ch = "GUILD", key = "gmshare", bulk = true }, "GMS", Comm.encodeRecord(rec))
end
function GM.Share(force)
    if sendPending and not force then return end
    sendPending = true
    ns.After(force and (math.random(20, 90) / 10) or 5, function() pcall(doShare, force) end)
end

Comm.On("GMS", function(sender, _, recStr)
    if not recStr or not sender or ns.isMe(sender) then return end
    if #recStr > 8000 then return end
    local r = Comm.decodeRecord(recStr)
    if not r then return end
    -- Texte ohne Escape-Sequenzen, Feldzahl begrenzt
    local n = 0
    for k, v in pairs(r) do
        n = n + 1
        if n > 60 then r[k] = nil
        elseif type(v) == "string" then r[k] = SEC.Text(v, 2000)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then r[k] = 0 end
    end
    -- nur eigener Datensatz des Absenders (kein Weiterreichen, keine fremden Namen)
    r.id, r.by, r.demo = sender, sender, nil
    r.u = math.min(tonumber(r.u) or ns.now(), ns.now() + 300)
    Store.merge(COLL, r, true, sender)
end)
-- neu eingeloggte Mitglieder bekommen unseren Stand
Comm.On("HELLOREQ", function() GM.Share(true) end)

------------------------------------------------------------------------
-- Matching
------------------------------------------------------------------------
local function parseGear(g)
    local t = {}
    for s, v in tostring(g or ""):gmatch("(%d+)=([%-%d%.]+)") do t[tonumber(s)] = tonumber(v) end
    return t
end
local function levelOf(rec)
    local lvl = tonumber(rec.lvl) or 1
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[rec.id]
    if m and tonumber(m.level) and tonumber(m.level) > lvl then lvl = tonumber(m.level) end
    return lvl
end
-- Demo: feste, plausible Werte (Itemwerte sind dort evtl. nicht geladen)
local function demoGain(key, who)
    local h = 0
    for b in (tostring(key) .. "#" .. tostring(who)):gmatch(".") do h = (h * 31 + b:byte()) % 100003 end
    if h % 3 == 0 then return nil end
    return 4 + h % 29
end

-- Prozent-Gewinn eines Teils fuer einen Datensatz, nil = kein Upgrade / nicht nutzbar
function GM.Gain(key, rec)
    if not rec or not key or not UP() then return nil end
    local ck = key .. "@" .. tostring(rec.id) .. "@" .. tostring(rec.u or 0) .. "@" .. tostring(rec.g or "") .. "@" .. tostring(rec.gb or "") .. "@" .. tostring(rec.lvl or "")
        .. ((rec.demo or rec._demoPair) and "@d" or "")
    local c = gainCache[ck]
    if c ~= nil then return c or nil end
    local link = linkOf(key)
    -- Item noch nicht im Cache (fremde Teile!): Werte fehlen -> nachladen und NICHT als "kein Upgrade" merken
    if link and C_Item and C_Item.GetItemInfo then
        local okI, nm = pcall(C_Item.GetItemInfo, link)
        if not (okI and ns.safe(nm)) then
            local id = idOf(key)
            if id then
                GM.pending = GM.pending or {}
                GM.pending[id] = true
                if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            end
            return nil
        end
    end
    local loc = link and equipLoc(link)
    local slots = loc and UP().SLOTS[loc]
    local pct
    if slots and UP().CanWearFor(link, rec.cls, levelOf(rec)) and minLevel(link) <= levelOf(rec) + 2 then
        local new = UP().Score(link, rec.role) or 0
        if new > 0 then
            local g = parseGear(rec.g)
            -- gb: beste gelagerte Wertung je Platz (fehlt bei alten Clients -> leer, Verhalten wie bisher)
            local gb = parseGear(rec.gb)
            local sk = STORE_KEY[loc] or slots[1]
            local old
            if loc == "INVTYPE_2HWEAPON" then old = (g[16] or 0) + (g[17] or 0)
            elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then old = g[16] or 0
            elseif (loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE") and (tonumber(rec.h2) or 0) >= 1 then
                -- spielt mit Zweihand oder zwei Waffen: Schild/Nebenhand-Gegenstand ist kein echtes Upgrade -
                -- ausser er hat so ein Teil gelagert (z.B. Tank-Schild fuer Instanzen): dann gegen das gelagerte
                if gb[sk] then old = gb[sk] else old = nil new = 0 end
            elseif loc == "INVTYPE_WEAPONOFFHAND" or loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE" then
                old = (tonumber(rec.h2) == 1) and (g[16] or 0) or (g[17] or 0)
            else
                for _, s in ipairs(slots) do local v = g[s] or 0 if not old or v < old then old = v end end
            end
            -- gelagertes besseres Teil fuer denselben Platz zaehlt als "hat er schon"
            if old and gb[sk] and gb[sk] > old then old = gb[sk] end
            old = old or 0
            if new <= 0 then pct = nil
            else pct = old <= 0 and 100 or math.floor((new - old) / old * 100 + 0.5) end
        elseif rec.demo or rec._demoPair then
            pct = demoGain(key, rec.id)
        end
    end
    if pct and pct < minPct() then pct = nil end
    gainCache[ck] = pct or false
    return pct
end

-- nachgeladene Items: neu rechnen (gebuendelt)
ns.On("GET_ITEM_INFO_RECEIVED", function(id)
    id = tonumber(ns.safe(id))
    if not (id and GM.pending and GM.pending[id]) then return end
    GM.pending[id] = nil
    if GM.reloadQueued then return end
    GM.reloadQueued = true
    C_Timer.After(1, function()
        GM.reloadQueued = nil
        wipe(gainCache) wipe(tipCache)
        ns.RefreshPage("gearmatch")
    end)
end)
local function valid(rec)
    if not rec or rec.del or not rec.id then return false end
    if rec.demo and not demoOn() then return false end
    return (ns.now() - (rec.u or 0)) < KEEP
end
-- alle fremden Datensaetze (Empfaenger)
function GM.Others()
    local out = {}
    for _, r in pairs(Store.coll(COLL)) do
        if valid(r) and not ns.isMe(r.id) then out[#out + 1] = r end
    end
    return out
end

-- Gildenbank: tragbare Teile (immer handelbar)
local function bankKeys()
    local out = {}
    local B = ns.GuildBank
    if not (B and B.AllItems) then return out end
    local ok, list = pcall(B.AllItems)
    if not ok or type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        local key = e.id and tostring(e.id)
        local loc = key and equipLoc(linkOf(key))
        if loc and UP() and UP().SLOTS[loc] then out[#out + 1] = key end
    end
    return out
end

-- Sicht 1: was in der Gilde (andere + Gildenbank) ist ein Upgrade fuer mich?
function GM.ForMe()
    local me = GM.MyRecord()
    local out = {}
    if not me then return out end
    for _, r in ipairs(GM.Others()) do
        for key in tostring(r.it or ""):gmatch("[^,]+") do
            local pct
            if r.demo then
                local tmp = { id = me.id, cls = me.cls, lvl = me.lvl, role = me.role, g = me.g, gb = me.gb, h2 = me.h2, u = me.u, _demoPair = true }
                pct = GM.Gain(key, tmp)
            else
                pct = GM.Gain(key, me)
            end
            if pct then out[#out + 1] = { key = key, owner = r.id, pct = pct, demo = r.demo } end
        end
    end
    for _, key in ipairs(bankKeys()) do
        local pct = GM.Gain(key, me)
        if pct then out[#out + 1] = { key = key, owner = GB_OWNER, pct = pct, bank = true } end
    end
    table.sort(out, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.key < b.key end)
    return out
end

-- Sicht 3: ALLE geteilten handelbaren Teile der anderen (nicht seelengebunden, unbenutzt im Inventar/Bank) - mit Upgrade-Wert, falls passend
function GM.AllShared()
    local me = GM.MyRecord()
    local out = {}
    for _, r in ipairs(GM.Others()) do
        if not r.demo or demoOn() then
            for key in tostring(r.it or ""):gmatch("[^,]+") do
                out[#out + 1] = { key = key, owner = r.id, pct = me and GM.Gain(key, me) or nil, any = true, demo = r.demo }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.pct or -1) ~= (b.pct or -1) then return (a.pct or -1) > (b.pct or -1) end
        local na, nb = itemName(idOf(a.key)) or a.key, itemName(idOf(b.key)) or b.key
        return na < nb
    end)
    return out
end

-- Demo: diese Teile gelten als "meine", damit Sicht 2 etwas zeigt
local DEMO_MINE = { "15062", "14551", "2099", "12793", "869" }

-- Sicht 2: meine handelbaren Teile -> wem helfen sie?
function GM.MyHelps()
    local me = GM.MyRecord()
    local out = {}
    if not me then return out end
    local mine = {}
    for key in tostring(me.it or ""):gmatch("[^,]+") do mine[#mine + 1] = { key = key } end
    if demoOn() then for _, k in ipairs(DEMO_MINE) do mine[#mine + 1] = { key = k, demo = true } end end
    local others = GM.Others()
    for _, m in ipairs(mine) do
        for _, r in ipairs(others) do
            if (not m.demo) or r.demo then
                local pct = GM.Gain(m.key, r)
                if pct then out[#out + 1] = { key = m.key, target = r.id, pct = pct, cls = r.cls, demo = m.demo or r.demo } end
            end
        end
    end
    table.sort(out, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.key < b.key end)
    return out
end

-- fuer wen (ausser mir) ist dieses Teil ein Upgrade? -> Namensliste
function GM.WhoNeeds(link)
    local key = keyOf(link)
    if not key then return {} end
    local t = tipCache[key]
    if t and GetTime() - t.t < 30 then return t.list end
    local list = {}
    for _, r in ipairs(GM.Others()) do
        local pct = GM.Gain(key, r)
        if pct then list[#list + 1] = { name = r.id, pct = pct, cls = r.cls } end
    end
    table.sort(list, function(a, b) return a.pct > b.pct end)
    tipCache[key] = { t = GetTime(), list = list }
    return list
end

local function ownerText(owner)
    if owner == GB_OWNER then return "|cffe8b44a" .. L["Gildenbank"] .. "|r" end
    local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(owner)
    if not cls then
        local r = Store.Get(COLL, owner)
        cls = r and r.cls
    end
    return ns.colorName(ns.displayName(owner), cls)
end

------------------------------------------------------------------------
-- Hinweis bei neuem Upgrade fuer mich (je Teil + Besitzer nur einmal)
------------------------------------------------------------------------
local function seenStore()
    ns.db.gmSeen = ns.db.gmSeen or {}
    return ns.db.gmSeen
end
function GM.CheckNew()
    if S().gmToastOff then return end
    local seen = seenStore()
    local fresh = {}
    for _, e in ipairs(GM.ForMe()) do
        if not e.demo then
            local k = e.owner .. ":" .. e.key
            if not seen[k] then
                seen[k] = ns.now()
                fresh[#fresh + 1] = e
            end
        end
    end
    -- alte Merker (60 Tage) aufraeumen
    for k, ts in pairs(seen) do if (tonumber(ts) or 0) < ns.now() - 60 * 86400 then seen[k] = nil end end
    local best = fresh[1]
    if not best then return end
    local more = #fresh > 1 and ("  |cff888888" .. (L["(+%d weitere)"]):format(#fresh - 1) .. "|r") or ""
    if ns.Sound and ns.Sound.Next then ns.Sound.Next("toast") end
    K.Toast(L["Upgrade in der Gilde"],
        qualityHex(idOf(best.key)) .. (itemName(idOf(best.key)) or "?") .. "|r  |cff66db9e+" .. math.min(best.pct, 999) .. "%|r  ·  " .. ownerText(best.owner) .. more,
        C.mint, function() if ns.ShowPage then ns.ShowPage("gearmatch") end end)
end

local function recalcSoon()
    if recalcPending then return end
    recalcPending = true
    ns.After(3, function()
        recalcPending = false
        wipe(tipCache)
        pcall(GM.CheckNew)
        ns.RefreshPage("gearmatch")
    end)
end

ns.Listen("STORE", function(coll, rec)
    if coll ~= COLL or quiet then return end
    if rec and rec.demo then return end
    recalcSoon()
end)

------------------------------------------------------------------------
-- Tooltip: "Upgrade fuer: Name1, Name2"
------------------------------------------------------------------------
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if not ns.db or S().gmTipOff then return end
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local ok, _, link = pcall(tt.GetItem, tt)
        link = ok and ns.safe(link) or nil
        if not link then return end
        local ok2, list = pcall(GM.WhoNeeds, link)
        if not ok2 or not list or #list == 0 then return end
        -- eigener Block wie "Entzaubern ergibt": Abstand, Ueberschrift, je Person eine Zeile (Name in Klassenfarbe, Gewinn rechts)
        tt:AddLine(" ")
        tt:AddLine(L["Upgrade fuer"], 0.4, 0.86, 0.62)
        for i, x in ipairs(list) do
            if i > 4 then
                tt:AddLine("  |cff888888" .. (L["+ %d weitere"]):format(#list - 4) .. "|r")
                break
            end
            tt:AddDoubleLine("  " .. ns.colorName(ns.displayName(x.name), x.cls), "+" .. math.min(x.pct, 999) .. " %", 0.9, 0.9, 0.9, 0.4, 0.86, 0.62)
        end
    end)
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
local function changed()
    myCache = nil
    GM.Share(false)
end
ns.On("BAG_UPDATE_DELAYED", changed)
ns.On("PLAYER_EQUIPMENT_CHANGED", changed)
ns.On("PLAYER_LEVEL_UP", changed)
ns.On("BANKFRAME_OPENED", function() bankOpen = true ns.After(1, function() pcall(GM.ScanBank) changed() end) end)
ns.On("BANKFRAME_CLOSED", function() pcall(GM.ScanBank) bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then ns.After(1, function() pcall(GM.ScanBank) changed() end) end end)
-- im Kampf wird nicht gelesen/gesendet -> danach nachholen
ns.On("PLAYER_REGEN_ENABLED", function() if lastHash and not sendPending then changed() end end)

------------------------------------------------------------------------
-- Demo-Daten (nur lokal)
------------------------------------------------------------------------
local DEMO_PEOPLE = {
    -- Name, Klasse, Stufe, Rolle, angelegt (Platz=Wertung), handelbare Teile
    { "Hoknar", "SHAMAN", 38, "healer", "1=18,3=14,5=22,7=19,8=11,10=10,16=21,17=12", "12640,14154,2244" },
    { "Tavira", "PRIEST", 41, "healer", "1=20,5=25,7=21,9=8,10=9,15=7,16=30", "15063,811" },
    { "Grukthar", "WARRIOR", 44, "tank", "1=40,3=31,5=52,7=44,8=29,10=26,16=24,17=30", "12793,869,14551" },
    { "Zul'mira", "MAGE", 36, "caster", "1=15,5=19,7=17,8=9,15=6,16=22", "2099" },
    { "Mokrash", "ROGUE", 43, "agile", "1=22,5=28,7=25,8=15,10=16,16=20,17=14", "15062" },
    { "Nakira", "HUNTER", 39, "ranged", "1=21,5=26,7=23,18=30", "" },
}
function GM.SeedDemo()
    local now = ns.now()
    quiet = true
    for i, d in ipairs(DEMO_PEOPLE) do
        local who = ns.fullName(d[1])
        Store.merge(COLL, { id = who, by = who, demo = true, u = now - i * 600, cls = d[2], lvl = d[3], role = d[4], g = d[5], h2 = 0, it = d[6] })
    end
    quiet = false
    wipe(gainCache) wipe(tipCache)
    ns.RefreshPage("gearmatch")
end
function GM.RemoveDemo()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    wipe(gainCache) wipe(tipCache)
    ns.RefreshPage("gearmatch")
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local function askText(e)
    if not e.pct then return (L["Hi! Du hast %s - koenntest du es mir geben oder verkaufen?"]):format(chatLink(e.key)) end
    if e.bank then return (L["Kann mir jemand %s aus der Gildenbank geben? Waere ein Upgrade fuer mich (+%d%%)."]):format(chatLink(e.key), math.min(e.pct, 999)) end
    return (L["Hi! Du hast %s - das waere ein Upgrade fuer mich (+%d%%). Wuerdest du es mir geben oder verkaufen?"]):format(chatLink(e.key), math.min(e.pct, 999))
end
local function offerText(e)
    return (L["Hi! Ich habe %s - laut Oasis ein Upgrade fuer dich (+%d%%). Magst du es haben? Ich schicke es dir gern per Post."]):format(chatLink(e.key), math.min(e.pct, 999))
end

-- Platz-Gruppen fuer den Filter
local JEWEL = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true }
local WEAPONLOC = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true }
local slotFilter, search = "all", ""
local function groupOf(key)
    local loc = equipLoc(linkOf(key))
    if not loc then return "armor", nil end
    if JEWEL[loc] then return "jewel", loc end
    if WEAPONLOC[loc] then return "weapon", loc end
    return "armor", loc
end
-- "Kopf · Platte" aus den Spiel-Texten (automatisch in der Client-Sprache)
local function slotText(key)
    local ok, _, _, sub, loc = pcall(C_Item.GetItemInfoInstant, linkOf(key))
    if not ok then return "" end
    local a = loc and _G[loc] or ""
    if type(a) ~= "string" then a = "" end
    if sub and sub ~= "" and sub ~= a and sub ~= MISCELLANEOUS then return a ~= "" and (a .. "  ·  " .. sub) or sub end
    return a
end
local function passFilter(e)
    if e.quest then return slotFilter == "all" and (search == "" or (itemName(idOf(e.key)) or ""):lower():find(search, 1, true)) end
    if slotFilter ~= "all" and groupOf(e.key) ~= slotFilter then return false end
    if search ~= "" and not (itemName(idOf(e.key)) or ""):lower():find(search, 1, true) then return false end
    return true
end
local function glass(f, r, a)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.035 }, { 1, 1, 1, 0.10 }, r or 12) end
end
local function pctColor(pct)
    return pct >= 50 and C.amber or (pct >= 15 and C.mint or { 0.6, 0.8, 0.65 })
end

ns.RegisterPage({
    key = "gearmatch", title = "Upgrade-Boerse", order = 5.46,
    sub = "Handelbare Ausruestung in der Gilde: was ist ein Upgrade fuer dich, wem helfen deine Teile?",
    build = function(p)
        p.seg = K.Segments(p, { { key = "forme", text = L["Fuer mich"] }, { key = "helps", text = L["Meine Teile helfen"] }, { key = "all", text = L["Basar"] } },
            function(k) view = k p.fresh = true ns.RefreshPage("gearmatch") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        -- Suche rechts oben
        p.search = K.Input(p, 180, L["Teil suchen..."], function(t)
            search = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            ns.RefreshPage("gearmatch")
        end)
        p.search:SetPoint("TOPRIGHT", 0, 0)
        glass(p.search, 8, 0.04)

        -- Ueberblick: drei Glaskarten, Zahl zaehlt hoch, Klick wechselt die Sicht
        local ov = CreateFrame("Frame", nil, p)
        ov:SetPoint("TOPLEFT", 0, -38)
        ov:SetPoint("TOPRIGHT", 0, -38)
        ov:SetHeight(70)
        ov:Hide()   -- 0.5.858: die drei Kacheln doppelten die Reiter; die Zahlen stehen jetzt an den Reitern
        p.stats = {}
        local SD = {
            { "forme", "Upgrades fuer dich", C.mint, "Teile anderer, die dich verbessern" },
            { "helps", "Deine Teile helfen", C.amber, "Deine handelbaren Teile als Upgrade fuer andere" },
            { "all", "Im Basar", C.blue, "Alles Handelbare, das die Gilde teilt" },
        }
        for i, d in ipairs(SD) do
            local c = CreateFrame("Button", nil, ov)
            glass(c, 12)
            c.v = K.Title(c, 26, C.text)
            c.v:SetPoint("TOPLEFT", 16, -12)
            c.l = K.Text(c, 12, C.text)
            c.l:SetPoint("LEFT", c.v, "RIGHT", 10, -2)
            c.l:SetText(L[d[2]])
            c.d = K.Text(c, 10, C.dim)
            c.d:SetPoint("BOTTOMLEFT", 16, 11)
            c.d:SetPoint("RIGHT", -12, 0)
            c.d:SetWordWrap(false)
            c.d:SetText(L[d[4]])
            -- feine Markierung unten, nur bei der aktiven Sicht
            c.mark = c:CreateTexture(nil, "ARTWORK")
            c.mark:SetHeight(2)
            c.mark:SetPoint("BOTTOMLEFT", 16, 1)
            c.mark:SetPoint("BOTTOMRIGHT", -16, 1)
            c.mark:SetColorTexture(d[3][1], d[3][2], d[3][3], 0.8)
            c.key, c.col = d[1], d[3]
            c:SetScript("OnClick", function(self) view = self.key p.fresh = true ns.RefreshPage("gearmatch") end)
            c:SetScript("OnEnter", function(self)
                glass(self, 12, 0.06)
                if self.key == "all" and self.names then K.ShowTip(self, self.names) end
            end)
            c:SetScript("OnLeave", function(self) glass(self, 12) GameTooltip:Hide() end)
            p.stats[i] = c
        end
        ov:SetScript("OnSizeChanged", function(self, w)
            local cw = math.floor(((w or 700) - 20) / 3)
            for i, c in ipairs(p.stats) do c:ClearAllPoints() c:SetPoint("TOPLEFT", (i - 1) * (cw + 10), 0) c:SetSize(cw, 70) end
        end)

        local panel = CreateFrame("Frame", nil, p)
        glass(panel, 14, 0.025)
        panel:SetPoint("TOPLEFT", 0, -40)
        panel:SetPoint("BOTTOMRIGHT", 0, 22)
        p.panel = panel
        p.headT = K.Title(panel, 14, C.text)
        p.headT:SetPoint("TOPLEFT", 16, -14)
        p.headN = K.Text(panel, 11, C.dim)
        p.headN:SetPoint("LEFT", p.headT, "RIGHT", 10, -1)
        -- Platz-Filter rechts im Kopf
        p.slot = K.Segments(panel, { { key = "all", text = L["Alle"] }, { key = "armor", text = L["Ruestung"] }, { key = "weapon", text = L["Waffen"] }, { key = "jewel", text = L["Schmuck"] } },
            function(k) slotFilter = k ns.RefreshPage("gearmatch") end, nil, { size = 11, pad = 14 })
        p.slot:SetPoint("TOPRIGHT", -10, -9)
        p.sum = K.Text(panel, 10, C.dim, "RIGHT")
        p.sum:SetPoint("RIGHT", p.slot, "LEFT", -12, 0)

        p.list = K.List(panel, 52, function(l)
            local r = K.Row(l)
            r.card = CreateFrame("Frame", nil, r)
            r.card:SetPoint("TOPLEFT", 0, -3)
            r.card:SetPoint("BOTTOMRIGHT", 0, 3)
            r.card:SetFrameLevel(r:GetFrameLevel())
            glass(r.card, 10, 0.02)
            r.icon = K.Icon(r, 32, nil)
            r.icon:SetPoint("LEFT", 12, 0)
            r.qual = r:CreateTexture(nil, "OVERLAY")
            r.qual:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMLEFT", 0, 0)
            r.qual:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 0, 0)
            r.qual:SetHeight(2)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("TOPLEFT", 56, -10)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -250, 0)
            r.cols.name:SetWordWrap(false)
            r.cols.slot = K.Text(r, 10, C.dim, "RIGHT")
            r.cols.slot:SetPoint("TOPRIGHT", r, "TOPRIGHT", -250, -11)
            r.cols.who = K.Text(r, 11, C.muted)
            r.cols.who:SetPoint("BOTTOMLEFT", 56, 10)
            r.cols.who:SetPoint("RIGHT", r, "RIGHT", -250, 0)
            r.cols.who:SetWordWrap(false)
            -- Zuwachs: Zahl + Balken (Laenge = Anteil am besten Teil der Liste)
            r.cols.pct = K.Title(r, 16, C.mint, "RIGHT")
            r.cols.pct:SetPoint("TOPRIGHT", r, "TOPRIGHT", -124, -10)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetColorTexture(1, 1, 1, 0.07)
            r.track:SetSize(90, 3)
            r.track:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -124, 14)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(3)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.btn = K.Button(r, L["Anfluestern"], 100, 24, "ghost")
            r.btn:SetPoint("RIGHT", -12, 0)
            r.btn.label:SetFont(K.FONT, 11, "")
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e then return end
                glass(self.card, 10, 0.05)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, linkOf(e.key))
                if e.target then GameTooltip:AddLine(L["Per Post: Briefkasten, Empfaenger "] .. ns.displayName(e.target), 0.6, 0.6, 0.6, true) end
                GameTooltip:AddLine("|cff888888" .. L["Shift-Klick: in den Chat einfuegen"] .. "|r")
                GameTooltip:Show()
                -- Vergleich mit dem, was ich gerade trage
                if not e.target and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
            end)
            r:SetScript("OnLeave", function(self) glass(self.card, 10, 0.02) GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if self.item and IsShiftKeyDown() then
                    local link = chatLink(self.item.key)
                    if ChatEdit_InsertLink and not ChatEdit_InsertLink(link) then ns.OpenChat(link) end
                end
            end)
            return r
        end, function(r, e, i)
            local id = idOf(e.key)
            r.icon:SetTexture(itemIcon(id))
            r.cols.name:SetText(qualityHex(id) .. (itemName(id) or ("#" .. tostring(id))) .. "|r")
            r.cols.slot:SetText(e.quest and L["Questitem"] or slotText(e.key))
            local okQ, q = pcall(function() return C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) end)
            local qc = okQ and q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[ns.safe(q) or 1]
            r.qual:SetColorTexture(qc and qc.r or 0.6, qc and qc.g or 0.6, qc and qc.b or 0.6, 0.9)
            local pct = e.pct
            r.track:SetShown(pct ~= nil)
            r.fill:SetShown(pct ~= nil)
            if e.quest then
                r.cols.pct:SetText(L["Quest"])
                r.cols.pct:SetTextColor(C.blue[1], C.blue[2], C.blue[3])
            elseif pct then
                local pc = pctColor(pct)
                r.cols.pct:SetText("+" .. math.min(pct, 999) .. "%")
                r.cols.pct:SetTextColor(pc[1], pc[2], pc[3])
                r.fill:SetColorTexture(pc[1], pc[2], pc[3], 0.9)
                local w = math.max(3, 90 * math.min(1, pct / math.max(1, p.maxPct or pct)))
                if p.fresh and not (ns.db and ns.db.settings.noAnim) and K.Tween then
                    r.fill:SetWidth(1)
                    K.Tween(r.fill, 0.5, function(t) r.fill:SetWidth(math.max(1, w * t)) end, function() r.fill:SetWidth(w) end, (i or 1) * 0.03)
                else
                    r.fill:SetWidth(w)
                end
            else
                r.cols.pct:SetText("")   -- 0.5.859: "kein Upgrade" in jeder Zeile war Laerm - nur echte Upgrades tragen eine Zahl
            end
            if e.quest then
                r.cols.who:SetText(L["hat "] .. ownerText(e.owner) .. "  |cff888888" .. (L["uebrig - fuer %s"]):format(e.qtitle) .. "|r")
                r.btn.label:SetText(L["Anfragen"])
                r.btn:SetScript("OnClick", function() if ns.QuestItems then ns.QuestItems.AskFor(e.owner, e.nd, e.qtitle, e.demo) end end)
            elseif e.target then
                r.cols.who:SetText(L["hilft "] .. ownerText(e.target) .. "  |cff777777" .. L["per Post oder anfluestern"] .. "|r")
                r.btn.label:SetText(L["Anbieten"])
                r.btn:SetScript("OnClick", function() ns.Whisper(e.target, offerText(e)) end)
            elseif e.bank then
                r.cols.who:SetText(L["liegt in der "] .. ownerText(GB_OWNER))
                r.btn.label:SetText(L["Gilde fragen"])
                r.btn:SetScript("OnClick", function() ns.OpenChat("/g " .. askText(e)) end)
            else
                r.cols.who:SetText(L["hat "] .. ownerText(e.owner) .. ((ns.Radar and ns.Radar.IsOnline and ns.Radar.IsOnline(e.owner)) and "  |cff66db9e" .. L["online"] .. "|r" or ""))
                r.btn.label:SetText(e.any and L["Anfragen"] or L["Anfluestern"])
                r.btn:SetScript("OnClick", function() ns.Whisper(e.owner, askText(e)) end)
            end
            if p.fresh and K.FadeIn then r.oasisFadedAt = nil K.FadeIn(r, (i or 1) * 0.03) end
        end)
        p.list:SetPoint("TOPLEFT", 8, -44)
        p.list:SetPoint("BOTTOMRIGHT", -8, 8)
        p.list.empty:SetText("")

        -- leere Liste: ruhiger Hinweis mit naechstem Schritt statt nur Text
        local em = CreateFrame("Frame", nil, panel)
        em:SetSize(420, 150)
        em:SetPoint("CENTER", 0, 10)
        em.ico = K.Glyph(em, 34, ns.MEDIA .. "icons\\wants", C.dim)
        em.ico:SetPoint("TOP", 0, 0)
        em.t = K.Title(em, 15, C.text, "CENTER")
        em.t:SetPoint("TOP", em.ico, "BOTTOM", 0, -12)
        em.t:SetWidth(420)
        em.d = K.Text(em, 11, C.muted, "CENTER")
        em.d:SetPoint("TOP", em.t, "BOTTOM", 0, -6)
        em.d:SetWidth(400)
        em.d:SetWordWrap(true)
        em.b = K.Button(em, "", 170, 26, "ghost")
        em.b:SetPoint("TOP", em.d, "BOTTOM", 0, -14)
        p.emptyBox = em

        p.foot = K.Text(p, 10, C.dim)
        p.foot:SetPoint("BOTTOMLEFT", 0, 4)
        p.foot:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        p.foot:SetText(L["Nur handelbare (nicht seelengebundene) Teile. Werte nach Klasse und Rolle wie beim Verbesserungs-Pfeil; Bank zaehlt erst nach einmal Oeffnen."])
        p.fresh = true
    end,
    refresh = function(p)
        p.seg:Select(view)
        p.slot:Select(slotFilter)
        local rows, title
        local em = p.emptyBox
        if view == "helps" then
            rows = GM.MyHelps()
            title = L["Deine Teile - wem helfen sie?"]
            em.t:SetText(L["Gerade hilft keines deiner Teile"])
            em.d:SetText(shareOn() and L["Keines deiner handelbaren Teile ist ein Upgrade fuer jemanden mit Oasis. Bank einmal oeffnen, damit sie mitzaehlt."]
                or L["Teilen ist aus (Einstellungen > Upgrade-Boerse)."])
            em.b.label:SetText(L["Im Basar stoebern"])
            em.b:SetScript("OnClick", function() view = "all" p.fresh = true ns.RefreshPage("gearmatch") end)
        elseif view == "all" then
            rows = GM.AllShared()
            title = L["Basar - alles Handelbare der Gilde"]
            em.t:SetText(L["Der Basar ist leer"])
            em.d:SetText(L["Noch teilt niemand mit Oasis handelbare Teile. Je mehr Mitglieder Oasis nutzen, desto voller wird es hier."])
            em.b.label:SetText(L["Zu den Mitgliedern"])
            em.b:SetScript("OnClick", function() ns.ShowPage("radar") end)
        else
            rows = GM.ForMe()
            local QI = ns.QuestItems
            if QI and QI.HelpForMe and QI.MyQuests then
                local okQ, qrows = pcall(function() return QI.HelpForMe(QI.MyQuests()) end)
                if okQ and type(qrows) == "table" then
                    for _, row in ipairs(qrows) do
                        if row.kind == "need" and row.nd and row.nd.id then
                            for _, g in ipairs(row.givers or {}) do
                                rows[#rows + 1] = { key = tostring(row.nd.id), owner = g.who, quest = true, nd = row.nd,
                                    qtitle = row.q and row.q.title or "?", demo = g.demo }
                            end
                        end
                    end
                end
            end
            title = L["Fuer dich - Upgrades und Questitems"]
            em.t:SetText(L["Gerade kein Upgrade dabei"])
            em.d:SetText(L["Sobald jemand mit Oasis ein passendes handelbares Teil hat, erscheint es hier - mit Hinweis."])
            em.b.label:SetText(L["Im Basar stoebern"])
            em.b:SetScript("OnClick", function() view = "all" p.fresh = true ns.RefreshPage("gearmatch") end)
        end
        local shown = {}
        p.maxPct = 1
        for _, e in ipairs(rows) do
            if passFilter(e) then
                shown[#shown + 1] = e
                if e.pct and e.pct > p.maxPct then p.maxPct = e.pct end
            end
        end
        if #rows > 0 and #shown == 0 then
            em.t:SetText(L["Nichts passt zum Filter"])
            em.d:SetText(L["Andere Kategorie waehlen oder die Suche leeren."])
            em.b.label:SetText(L["Filter zuruecksetzen"])
            em.b:SetScript("OnClick", function() slotFilter, search = "all", "" p.search:SetText("") ns.RefreshPage("gearmatch") end)
        end
        p.headT:SetText(title)
        p.headN:SetText(#shown > 0 and ((#shown == 1) and L["1 Teil"] or (L["%d Teile"]):format(#shown)) or "")
        p.sum:SetText(view ~= "all" and (L["ab +%d%%"]):format(minPct()) or "")
        em:SetShown(#shown == 0)
        p.list:SetData(shown)

        local others = GM.Others()
        local counts = { #GM.ForMe(), #GM.MyHelps(), #GM.AllShared() }
        for i, c in ipairs(p.stats) do
            if p.fresh or c.last ~= counts[i] then K.CountUp(c.v, counts[i], 0.6) else c.v:SetText(counts[i]) end
            c.last = counts[i]
            c.v:SetTextColor(counts[i] > 0 and c.col[1] or C.dim[1], counts[i] > 0 and c.col[2] or C.dim[2], counts[i] > 0 and c.col[3] or C.dim[3])
            c.mark:SetShown(c.key == view)
        end
        -- Zahlen an den Reitern
        for _, b in ipairs(p.seg.buttons or {}) do
            local i = (b.key == "forme" and 1) or (b.key == "helps" and 2) or 3
            local base = (i == 1 and L["Fuer mich"]) or (i == 2 and L["Meine Teile helfen"]) or L["Basar"]
            if b.label then b.label:SetText(base .. (counts[i] > 0 and ("  |cff888888" .. counts[i] .. "|r") or "")) end
        end
        local names = { (L["%d Charaktere teilen"]):format(#others) }
        for i, r in ipairs(others) do
            if i > 15 then names[#names + 1] = "|cff888888+" .. (#others - 15) .. "|r" break end
            local n = 0
            for _ in tostring(r.it or ""):gmatch("[^,]+") do n = n + 1 end
            names[#names + 1] = ownerText(r.id) .. "  |cff888888" .. (L["%d handelbare Teile"]):format(n) .. "|r"
        end
        p.stats[3].names = names
        p.fresh = nil
    end,
})

-- Bereichs-Einstellungen
if ns.AddPageSettings then
    ns.AddPageSettings("gearmatch", function(det, y)
        det.t = det.t or {}
        local function tog(label, desc, key, invert, after)
            local t = K.Toggle(det, L[label], function()
                if invert then return not S()[key] end
                return S()[key] and true or false
            end, function(v)
                if invert then S()[key] = (not v) or nil else S()[key] = v or nil end
                if after then after() end
            end, L[desc])
            t:SetPoint("TOPLEFT", 14, y)
            t:SetWidth(600)
            det.t[#det.t + 1] = t
            y = y - 44
        end
        tog("Handelbare Ausruestung mit der Gilde teilen", "Taschen und Bank (nur nicht seelengebundene Teile) - andere sehen, was ihnen hilft", "gmShareOff", true,
            function() myCache = nil GM.Share(true) end)
        tog("Hinweis bei neuem Upgrade fuer mich", "Hoechstens einmal je Teil", "gmToastOff", true)
        tog("Zeile 'Upgrade fuer' im Item-Tooltip", "Zeigt, fuer wen in der Gilde ein Teil ein Upgrade ist", "gmTipOff", true)
        local lbl = K.Text(det, 13, C.text)
        lbl:SetPoint("TOPLEFT", 14, y - 2)
        lbl:SetText(L["Mindest-Verbesserung"])
        det.t[#det.t + 1] = lbl
        if K.Slider then
            local sl = K.Slider(det, 180, 1, 30, 1, function() return minPct() end,
                function(v) S().gmMinPct = v wipe(gainCache) wipe(tipCache) end, function(v) return "+" .. v .. "%" end)
            sl:SetPoint("TOPLEFT", 184, y)
            det.t[#det.t + 1] = sl
        end
        return y - 40
    end)
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    -- alte Datensaetze verwerfen
    local c = Store.coll(COLL)
    for id, r in pairs(c) do
        if type(r) ~= "table" or (not r.demo and ns.now() - (r.u or 0) > KEEP) then c[id] = nil end
    end
    ns.After(20, function() GM.Share(true) end)
    ns.After(30, function() pcall(GM.CheckNew) end)
    local D = ns.Demo
    if D and not D.gmHooked then
        D.gmHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) GM.SeedDemo() end
        D.Remove = function(...) remove(...) GM.RemoveDemo() end
        if D.IsActive() then ns.After(3, GM.SeedDemo) end
    end
end)
end)

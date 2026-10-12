-- Oasis: "Neu seit deinem letzten Besuch" - generischer Zaehler je Seite
-- Merkt sich je Seite, wann sie zuletzt angesehen wurde (ns.db.pageSeen[key]), zaehlt neue Store-Eintraege
-- seitdem und setzt sie als Badge - aber nur, wenn das Modul selbst keinen Badge setzt.
-- Eigene Eintraege und Demo-Daten (ausser Demo aktiv) zaehlen nicht. Erster Start: nichts ist neu.
local ADDON, ns = ...
local L = ns.L

local NS = {}
ns.NewSince = NS

-- Seite -> Sammlung + Zeitfelder (erstes vorhandenes zaehlt)
local SOURCES = {
    chronicle = { coll = "chronicle", time = { "ts", "created", "u" } },
    raid      = { coll = "events",    time = { "created", "u" } },
    polls     = { coll = "polls",     time = { "created", "u" } },
    wants     = { coll = "wants",     time = { "created", "u" } },
    crafting  = { coll = "orders",    time = { "created", "u" } },
    bank      = { coll = "banklog",   time = { "ts", "u" } },
    rares     = { coll = "rare_seen", time = { "u" } },
}
NS.SOURCES = SOURCES
local BY_COLL = {}
for key, s in pairs(SOURCES) do BY_COLL[s.coll] = key end

local counts = {}   -- key -> Anzahl neu (nur wenn wir den Badge setzen)
local mine = {}     -- key -> Text, den wir selbst gesetzt haben
local pending, timerOn = {}, false

local function seenTable()
    if not ns.db then return nil end
    ns.db.pageSeen = ns.db.pageSeen or {}
    return ns.db.pageSeen
end
local function demoActive() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end
local function recTime(r, fields)
    for _, f in ipairs(fields) do
        local v = tonumber(r[f])
        if v and v > 0 then return v end
    end
    return 0
end
local function isOwn(r)
    for _, f in ipairs({ "by", "who", "from" }) do
        if r[f] and ns.isMe(r[f]) then return true end
    end
    return false
end
local function isDemo(r) return r.demo or tostring(r.id or ""):find("demo-", 1, true) end

-- Anzahl neuer Eintraege seit dem letzten Ansehen
function NS.Count(key)
    local src, seen = SOURCES[key], seenTable()
    if not src or not seen or not seen[key] or not ns.Store then return 0 end
    local since, demo, n = seen[key], demoActive(), 0
    for _, r in pairs(ns.Store.coll(src.coll)) do
        if not r.del and (demo or not isDemo(r)) and not isOwn(r) and recTime(r, src.time) > since then n = n + 1 end
    end
    return n
end

function NS.Update(key)
    local src = SOURCES[key]
    if not src or not ns.SetNavBadge then return end
    local seen = seenTable()
    if not seen then return end
    -- Seite gerade offen: gilt als gesehen
    if ns.MainShown and ns.MainShown() and ns.CurrentPage and ns.CurrentPage() == key then seen[key] = ns.now() end
    if not seen[key] then seen[key] = ns.now() end
    local cur = ns._badges and ns._badges[key]
    -- das Modul setzt selbst einen Badge: nicht ueberschreiben
    if cur ~= nil and tostring(cur) ~= "" and cur ~= mine[key] then
        mine[key], counts[key] = nil, nil
        return
    end
    local n = NS.Count(key)
    local text = n > 0 and tostring(n > 99 and "99+" or n) or nil
    counts[key] = n > 0 and n or nil
    if text ~= mine[key] or (text and cur ~= text) then
        mine[key] = text
        if text or (cur ~= nil and tostring(cur) ~= "") then ns.SetNavBadge(key, text) end
    end
end
function NS.UpdateAll() for key in pairs(SOURCES) do NS.Update(key) end end

-- Tooltip: nur fuer Badges, die von hier kommen
function NS.TipFor(key)
    local n = counts[key]
    local cur = ns._badges and ns._badges[key]
    if n and n > 0 and cur ~= nil and cur == mine[key] then
        return n == 1 and L["1 neu seit deinem letzten Besuch"] or (L["%d neu seit deinem letzten Besuch"]):format(n)
    end
end

-- Haken aus UI\Main.lua (showPage)
function ns.OnPageSeen(key)
    local seen = seenTable()
    if not seen then return end
    seen[key] = ns.now()
    if SOURCES[key] then NS.Update(key) end
end

-- Store-Aenderungen gedrosselt sammeln
local function flush()
    timerOn = false
    local list = pending
    pending = {}
    for key in pairs(list) do pcall(NS.Update, key) end
end
local function schedule(key)
    pending[key] = true
    if timerOn then return end
    timerOn = true
    if C_Timer and C_Timer.After then C_Timer.After(2, flush) else flush() end
end
ns.Listen("STORE", function(name)
    local key = BY_COLL[name]
    if key then schedule(key) end
end)
ns.Listen("LOGIN", function()
    local seen = seenTable()
    if seen then
        -- erster Start: ab jetzt zaehlen
        local now = ns.now()
        for key in pairs(SOURCES) do if not seen[key] then seen[key] = now end end
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, function() pcall(NS.UpdateAll) end) end
end)

-- /oa probe neu : zeigt die Zaehler
ns.probes = ns.probes or {}
ns.probes.neu = function()
    local seen = seenTable() or {}
    for key in pairs(SOURCES) do
        ns.print(("%s: %d neu (seit %s), Badge=%s"):format(key, NS.Count(key), seen[key] and ns.ago(seen[key]) or "-", tostring(ns._badges and ns._badges[key])))
    end
end

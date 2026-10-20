-- Oasis: "New since your last visit" - generic counter per page
-- Remembers per page when it was last viewed (ns.db.pageSeen[key]), counts new store entries
-- since then and sets them as a badge - but only if the module does not set a badge itself.
-- Own entries and demo data (unless demo is active) do not count. First start: nothing is new.
local ADDON, ns = ...
local L = ns.L

local NS = {}
ns.NewSince = NS

-- Page -> collection + time fields (first one present counts)
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

local counts = {}   -- key -> number of new entries (only if we set the badge)
local mine = {}     -- key -> text we set ourselves
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

-- Number of new entries since last viewed
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
    -- Page currently open: counts as seen
    if ns.MainShown and ns.MainShown() and ns.CurrentPage and ns.CurrentPage() == key then seen[key] = ns.now() end
    if not seen[key] then seen[key] = ns.now() end
    local cur = ns._badges and ns._badges[key]
    -- the module sets a badge itself: do not overwrite
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

-- Tooltip: only for badges that come from here
function NS.TipFor(key)
    local n = counts[key]
    local cur = ns._badges and ns._badges[key]
    if n and n > 0 and cur ~= nil and cur == mine[key] then
        return n == 1 and L["1 new since your last visit"] or (L["%d new since your last visit"]):format(n)
    end
end

-- Hook from UI\Main.lua (showPage)
function ns.OnPageSeen(key)
    local seen = seenTable()
    if not seen then return end
    seen[key] = ns.now()
    if SOURCES[key] then NS.Update(key) end
end

-- Collect store changes, throttled
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
        -- first start: count from now on
        local now = ns.now()
        for key in pairs(SOURCES) do if not seen[key] then seen[key] = now end end
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, function() pcall(NS.UpdateAll) end) end
end)

-- /oa probe neu : shows the counters
ns.probes = ns.probes or {}
ns.probes.neu = function()
    local seen = seenTable() or {}
    for key in pairs(SOURCES) do
        ns.print(("%s: %d neu (seit %s), Badge=%s"):format(key, NS.Count(key), seen[key] and ns.ago(seen[key]) or "-", tostring(ns._badges and ns._badges[key])))
    end
end

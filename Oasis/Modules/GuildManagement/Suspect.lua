-- Oasis: suspicion monitor for officers
-- A genuine Oasis practically never sends data that others reject. So every client counts
-- which DIRECTLY sent records it rejects from whom (no permissions, forged author, timestamp in the
-- future, made-up log entries, flood limits). Relayed data from the sync doesn't count.
-- Officers exchange their counters in the officer channel; the list shows how many officers independently
-- reported something (so a single person can't smear anyone).
-- Whoever sends a lot of forged data in a short time is ignored for one hour.
local ADDON, ns = ...
ns.ModuleFile("Oasis_GuildManagement", function()   -- Guild care module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm

local SP = {}
ns.Suspect = SP

local KEEP = 14 * 86400      -- keep entries this long
local LIST_MIN = 5           -- from this many rejections someone appears in the list
local IGNORE_N = 30          -- this many rejections ...
local IGNORE_WIN = 600       -- ... within 10 minutes -> ignore
local IGNORE_FOR = 3600      -- for one hour

local function db()
    ns.db.suspect = ns.db.suspect or {}
    return ns.db.suspect
end
local function key(name) return ns.NameKey(name) end

local burst = {}    -- key -> { t0, n } (session only)
local ignored = {}  -- key -> until (GetTime)

function SP.Ignored(name)
    local k = key(name)
    local t = ignored[k]
    if not t then return false end
    if GetTime() > t then ignored[k] = nil return false end
    return true
end

local function shortWhy(why)
    why = tostring(why or "?")
    return why:sub(1, 40)
end

function SP.Note(name, why, coll)
    if not name or name == "" or ns.isMe(name) then return end
    local k = key(name)
    if k == "" then return end
    local d = db()
    local e = d[k] or { name = name, n = 0, why = {}, first = ns.now(), rep = {} }
    d[k] = e
    e.name, e.n, e.last = name, e.n + 1, ns.now()
    local w = shortWhy(why) .. (coll and (" (" .. tostring(coll):sub(1, 16) .. ")") or "")
    local kinds = 0
    for _ in pairs(e.why) do kinds = kinds + 1 end
    if e.why[w] or kinds < 8 then e.why[w] = (e.why[w] or 0) + 1 end
    -- flood: ignore for one hour
    local b = burst[k]
    if not b or GetTime() - b.t0 > IGNORE_WIN then b = { t0 = GetTime(), n = 0 } burst[k] = b end
    b.n = b.n + 1
    if b.n >= IGNORE_N and not ignored[k] then
        ignored[k] = GetTime() + IGNORE_FOR
        e.ignored = (e.ignored or 0) + 1
        ns.debug("Verdacht: ignoriere", name)
    end
    SP.dirty = true
end

-- entries with enough rejections, by count
function SP.List()
    local out = {}
    local now = ns.now()
    for k, e in pairs(db()) do
        if type(e) == "table" then
            if (e.last or 0) < now - KEEP then
                db()[k] = nil
            else
                local reporters = 0
                for _ in pairs(e.rep or {}) do reporters = reporters + 1 end
                if e.n >= LIST_MIN then reporters = reporters + 1 end   -- myself
                local total = e.n
                for _, r in pairs(e.rep or {}) do total = total + (r.n or 0) end
                if total >= LIST_MIN then
                    out[#out + 1] = { key = k, name = e.name, n = total, mine = e.n, reporters = reporters,
                        last = e.last, why = e.why, ignored = SP.Ignored(e.name) }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.reporters ~= b.reporters then return a.reporters > b.reporters end return a.n > b.n end)
    return out
end

------------------------------------------------------------------------
-- exchange among officers (officer channel, only accepted from officers)
------------------------------------------------------------------------
local function amOfficer() return ns.isOfficer and ns.isOfficer() end
local function share()
    if not amOfficer() or not IsInGuild() then return end
    local sent = 0
    for _, e in pairs(db()) do
        if type(e) == "table" and e.n >= LIST_MIN and (e.last or 0) > ns.now() - KEEP and sent < 20 then
            local top, topN = "?", 0
            for w, c in pairs(e.why) do if c > topN then top, topN = w, c end end
            Comm.SendEx({ ch = "OFFICER", bulk = true }, "SUSP", e.name, e.n, e.last or 0, top)
            sent = sent + 1
        end
    end
end
Comm.On("SUSP", function(sender, channel, name, n, last, top)
    if Comm.rawChannel ~= "OFFICER" or not amOfficer() then return end
    if ns.isMe(sender) or type(name) ~= "string" or name == "" or #name > 64 then return end
    local A = ns.Admin
    local role = A and A.RoleOf and A.RoleOf(sender)
    if role ~= "lead" and role ~= "officer" then return end
    n, last = tonumber(n), tonumber(last)
    if not n or n < 1 or n > 100000 or not last then return end
    if key(name) == key(sender) then return end
    local d = db()
    local k = key(name)
    local e = d[k] or { name = name, n = 0, why = {}, first = ns.now(), rep = {} }
    d[k] = e
    e.rep = e.rep or {}
    e.rep[key(sender)] = { n = math.floor(n), t = math.min(last, ns.now()), top = ns.CleanText(tostring(top or ""), 60) }
    e.last = math.max(e.last or 0, math.min(last, ns.now()))
    SP.dirty = true
end)
ns.Listen("LOGIN", function()
    ns.After(90, function() pcall(share) end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1800, function() pcall(share) end) end
end)

------------------------------------------------------------------------
-- tab under Crown > Tools
------------------------------------------------------------------------
local O = ns.Officer
if O and O.BUILD and O.makeList then
    O.TEXT.suspect = "Verdacht"
    O.BUILD.suspect = function(f)
        local n = K.Text(f, 10, C.dim)
        n:SetPoint("TOPLEFT", 0, 0)
        n:SetPoint("RIGHT", -10, 0)
        n:SetWordWrap(true)
        n:SetText(L["Who sends data that others reject (no permission, forged author, made-up entries). An unmodified Oasis practically never does this - a hint, not proof."])
        f.list = O.makeList(f, -34, 26, { { "who", 10, 160, 12 }, { "cnt", 175, 90, 11, C.text }, { "rep", 270, 110, 11, C.muted }, { "why", 385, 420, 10, C.dim } }, function(r, e)
            r.cols.who:SetText((ns.colorName and ns.colorName(e.name)) or ns.short(e.name))
            r.cols.cnt:SetText((e.ignored and "|cffff4040" or "") .. (L["%d declined"]):format(e.n) .. (e.ignored and "|r" or ""))
            r.cols.rep:SetText((L["%d officers"]):format(e.reporters))
            local parts = {}
            for w, c in pairs(e.why or {}) do parts[#parts + 1] = w .. " x" .. c end
            table.sort(parts)
            r.cols.why:SetText(date(L["%m/%d %H:%M"], e.last or 0) .. "  " .. table.concat(parts, ", "))
        end)
        f.list.empty:SetText(L["Nothing unusual."])
    end
    O.REFRESH.suspect = function(f) f.list:SetData(SP.List()) end
end
end)

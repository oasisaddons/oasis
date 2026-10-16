-- Oasis: Verdachts-Monitor fuer Offiziere
-- Ein echtes Oasis schickt praktisch nie Daten, die bei anderen abgelehnt werden. Jeder Client zaehlt deshalb mit,
-- welche DIREKT gesendeten Datensaetze er von wem verwirft (keine Rechte, gefaelschter Urheber, Zeitstempel in der
-- Zukunft, ausgedachte Protokolleintraege, Flut-Grenzen). Weitergereichtes aus dem Abgleich zaehlt nicht.
-- Offiziere tauschen ihre Zaehler im Offizierskanal aus; die Liste zeigt, wie viele Offiziere unabhaengig
-- etwas gemeldet haben (ein Einzelner kann so niemanden anschwaerzen).
-- Wer in kurzer Zeit sehr viel Gefaelschtes schickt, wird fuer eine Stunde ignoriert.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gildenpflege", function()   -- Modul Gildenpflege (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm

local SP = {}
ns.Suspect = SP

local KEEP = 14 * 86400      -- Eintraege so lange behalten
local LIST_MIN = 5           -- ab so vielen Ablehnungen erscheint jemand in der Liste
local IGNORE_N = 30          -- so viele Ablehnungen ...
local IGNORE_WIN = 600       -- ... innerhalb von 10 Minuten -> ignorieren
local IGNORE_FOR = 3600      -- fuer eine Stunde

local function db()
    ns.db.suspect = ns.db.suspect or {}
    return ns.db.suspect
end
local function key(name) return ns.NameKey(name) end

local burst = {}    -- key -> { t0, n } (nur Sitzung)
local ignored = {}  -- key -> bis (GetTime)

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
    -- Flut: eine Stunde ignorieren
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

-- Eintraege mit genug Ablehnungen, nach Anzahl
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
                if e.n >= LIST_MIN then reporters = reporters + 1 end   -- ich selbst
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
-- Austausch unter Offizieren (Offizierskanal, nur von Offizieren angenommen)
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
-- Reiter unter Krone > Werkzeuge
------------------------------------------------------------------------
local O = ns.Officer
if O and O.BUILD and O.makeList then
    O.TEXT.suspect = "Verdacht"
    O.BUILD.suspect = function(f)
        local n = K.Text(f, 10, C.dim)
        n:SetPoint("TOPLEFT", 0, 0)
        n:SetPoint("RIGHT", -10, 0)
        n:SetWordWrap(true)
        n:SetText(L["Wer Daten schickt, die bei anderen abgelehnt werden (keine Rechte, gefaelschter Urheber, ausgedachte Eintraege). Ein unveraendertes Oasis tut das praktisch nie - ein Hinweis, kein Beweis."])
        f.list = O.makeList(f, -34, 26, { { "who", 10, 160, 12 }, { "cnt", 175, 90, 11, C.text }, { "rep", 270, 110, 11, C.muted }, { "why", 385, 420, 10, C.dim } }, function(r, e)
            r.cols.who:SetText((ns.colorName and ns.colorName(e.name)) or ns.short(e.name))
            r.cols.cnt:SetText((e.ignored and "|cffff4040" or "") .. (L["%d abgelehnt"]):format(e.n) .. (e.ignored and "|r" or ""))
            r.cols.rep:SetText((L["%d Offiziere"]):format(e.reporters))
            local parts = {}
            for w, c in pairs(e.why or {}) do parts[#parts + 1] = w .. " x" .. c end
            table.sort(parts)
            r.cols.why:SetText(date(L["%d.%m. %H:%M"], e.last or 0) .. "  " .. table.concat(parts, ", "))
        end)
        f.list.empty:SetText(L["Keine Auffaelligkeiten."])
    end
    O.REFRESH.suspect = function(f) f.list:SetData(SP.List()) end
end
end)

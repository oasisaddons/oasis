-- Oasis: Import von der Gilden-Webseite (Rueckrichtung zu Export.lua)
-- WoW-Addons koennen nicht ins Internet. OasisSync.exe holt deshalb Daten vom Portal und schreibt sie als
-- Lua-Datei Oasis\Import.lua (globale Tabelle OasisImport). WoW liest sie beim Start bzw. /reload ein,
-- dieses Modul uebernimmt sie dann in die gemeinsamen Daten (Store) -> von dort an die ganze Gilde.
-- Format: Tools\OasisSync-Format.md, Abschnitt "Web -> Oasis".
--
-- Sicherheit (die Datei liegt auf dem eigenen PC, wird aber an die Gilde weitergegeben):
--   * Anmeldungen (signups): nur die EIGENEN (who = ich)
--   * Termine, Aufstellungen, Durchsagen, Umfragen: nur wenn ich Offizier/Gildenleitung bin
--   * Datensatz nur uebernehmen, wenn er neuer ist als der vorhandene (gleiche Regel wie im Gilden-Abgleich)
local ADDON, ns = ...
local L = ns.L
local Store = ns.Store

local Import = {}
ns.Import = Import
Import.SCHEMA = 1

local LEAD_ONLY = { events = true, raidplan = true, notices = true, polls = true }
local ALLOWED = { events = true, raidplan = true, notices = true, polls = true, signups = true }

local function canLead()
    return ns.isOfficer() or (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) or false
end

-- nur einfache Werte/Tabellen uebernehmen
local function clean(v, depth)
    local t = type(v)
    -- Texte entschaerfen/kuerzen, nur endliche Zahlen (die Daten gehen an die ganze Gilde)
    if t == "string" then return ns.CleanText(v, 4000) end
    if t == "number" then if v == v and v > -1e15 and v < 1e15 then return v end return nil end
    if t == "boolean" then return v end
    if t ~= "table" or depth > 6 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            local c = clean(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

function Import.Run(silent)
    local data = _G.OasisImport
    if type(data) ~= "table" or type(data.collections) ~= "table" then return 0 end
    if (tonumber(data.schema) or 0) > Import.SCHEMA then
        if not silent then ns.print(L["Website import: newer format - please update Oasis."]) end
        return 0
    end
    -- dieselbe Datei nicht mehrfach einlesen
    local stamp = tostring(data.ts or "") .. ":" .. tostring(data.n or "")
    if ns.db.importStamp == stamp then return 0 end
    local lead = canLead()
    local n, skipped = 0, 0
    for coll, list in pairs(data.collections) do
        if ALLOWED[coll] and type(list) == "table" then
            for idx, raw in ipairs(list) do
                if idx > 2000 then break end
                local rec = clean(raw, 0)
                local ok = rec and type(rec.id) == "string" and rec.id ~= "" and #rec.id <= 160
                -- Zeitstempel nie in der Zukunft (sonst gewaenne der Satz gegen jede spaetere Aenderung)
                if ok and type(rec.u) == "number" and rec.u > ns.now() then rec.u = ns.now() end
                if ok and rec.by ~= nil and type(rec.by) ~= "string" then rec.by = nil end
                if ok and LEAD_ONLY[coll] and not lead then ok = false end
                if ok and coll == "signups" and not (rec.who and ns.isMe(rec.who)) then ok = false end
                if ok then
                    local old = Store.Get(coll, rec.id)
                    if not old or (tonumber(rec.u) or 0) > (old.u or 0) then
                        rec.src = "web"
                        rec.by = rec.by or ns.me()
                        Store.Put(coll, rec)
                        n = n + 1
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    ns.db.importStamp = stamp
    ns.db.importAt = ns.now()
    if n > 0 then
        ns.print((L["Taken over from the guild website: %d entries."]):format(n))
        ns.Fire("SYNCED")
    elseif skipped > 0 and not silent then
        ns.print(L["Website import: nothing taken over (events/rosters only for officers, sign-ups only your own)."])
    end
    return n
end

-- nach dem Login (Gildenrang muss bekannt sein) einlesen
ns.Listen("LOGIN", function() ns.After(8, function() pcall(Import.Run, true) end) end)
ns.slash.import = function() ns.db.importStamp = nil Import.Run(false) end

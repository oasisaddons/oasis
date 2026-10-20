-- Oasis: import from the guild website (reverse direction of Export.lua)
-- WoW addons cannot access the internet. So OasisSync.exe fetches data from the portal and writes it as the
-- Lua file Oasis\Import.lua (global table OasisImport). WoW reads it on startup or /reload,
-- this module then takes it into the shared data (Store) -> from there to the whole guild.
-- Format: Tools\OasisSync-Format.md, section "Web -> Oasis".
--
-- Security (the file lives on your own PC but is passed on to the guild):
--   * Sign-ups (signups): only your OWN (who = me)
--   * Events, lineups, announcements, polls: only if I am officer/guild leadership
--   * Only take a record if it is newer than the existing one (same rule as in guild sync)
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

-- only take simple values/tables
local function clean(v, depth)
    local t = type(v)
    -- Sanitize/shorten strings, finite numbers only (the data goes to the whole guild)
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
    -- don't read the same file more than once
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
                -- Timestamps never in the future (otherwise the record would win against every later change)
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

-- read after login (guild rank must be known)
ns.Listen("LOGIN", function() ns.After(8, function() pcall(Import.Run, true) end) end)
ns.slash.import = function() ns.db.importStamp = nil Import.Run(false) end

-- Oasis: measuring probe for Blizzard's damage meter (0.5.576, developer mode only)
-- Question: what does C_DamageMeter deliver after combat? (damage, healing, taken, highest hit, crits per spell ...)
-- Basis for guild leaderboards. The combat log is locked for addons in Forever.
-- Result: OasisDB.meterProbe (last 3 fights) - readable in the saved variables file after /reload. /oa probe meter = immediately.
local ADDON, ns = ...

local issecret = issecretvalue or function() return false end
local function dump(v, depth, seen)
    depth = depth or 0
    local tv = type(v)
    if issecret(v) then return "<geheim>" end
    if tv ~= "table" then
        if tv == "string" then return v:sub(1, 80) end
        return tostring(v)
    end
    if depth >= 4 then return "{...}" end
    seen = seen or {}
    if seen[v] then return "{zyklisch}" end
    seen[v] = true
    local out, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 25 then out["..."] = "mehr" break end
        local ok, d = pcall(dump, x, depth + 1, seen)
        out[tostring(k)] = ok and d or "<Fehler>"
    end
    return out
end

local function probe(why)
    local DM = C_DamageMeter
    local res = { t = time and time() or 0, why = why, v = ns.version }
    if type(DM) ~= "table" then res.fehlt = true return res end
    res.api = {}
    for k, f in pairs(DM) do res.api[#res.api + 1] = k .. (type(f) == "function" and "()" or "") end
    table.sort(res.api)
    res.types = dump(Enum and Enum.DamageMeterType)
    res.sessionTypes = dump(Enum and Enum.DamageMeterSessionType)
    res.available = dump(select(2, pcall(function() return DM.IsDamageMeterAvailable and DM.IsDamageMeterAvailable() end)))
    res.sessions = dump(select(2, pcall(function() return DM.GetAvailableCombatSessions and DM.GetAvailableCombatSessions() end)))
    -- each type (damage, healing, taken ...) for the last/current session
    res.data = {}
    local ST = Enum and Enum.DamageMeterSessionType
    local guid = UnitGUID and UnitGUID("player")
    for name, typ in pairs((Enum and Enum.DamageMeterType) or {}) do
        local entry = {}
        for sname, sval in pairs(ST or {}) do
            if DM.GetCombatSessionFromType then
                local ok, s = pcall(DM.GetCombatSessionFromType, sval, typ)
                entry[sname] = ok and dump(s) or ("Fehler: " .. tostring(s))
            end
        end
        -- Breakdown for your own character (spells, highest hit, crits?)
        for k, f in pairs(DM) do
            if type(f) == "function" and k:find("Source") and ST then
                local ok, s = pcall(f, ST.Current or ST.Overall or 1, typ, guid)
                entry[k] = ok and dump(s) or ("Fehler: " .. tostring(s))
            end
        end
        res.data[name] = entry
    end
    return res
end
local function save(why)
    if not (ns.IsDev and ns.IsDev()) then return end
    local ok, r = pcall(probe, why)
    ns.db.meterProbe = ns.db.meterProbe or {}
    table.insert(ns.db.meterProbe, 1, ok and r or { fehler = tostring(r) })
    while #ns.db.meterProbe > 3 do table.remove(ns.db.meterProbe) end
end
-- after every fight (values are only readable out of combat)
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(1.5, function() if not ns.inCombat() then save("Kampfende") end end) end)
ns.probes = ns.probes or {}
ns.probes.meter = function()
    save("Befehl")
    local r = ns.db.meterProbe and ns.db.meterProbe[1]
    ns.print("Schadensanzeige-Sonde gespeichert (" .. ((r and r.api and #r.api) or 0) .. " Funktionen). Nach /reload steht sie in der Speicherdatei.")
end

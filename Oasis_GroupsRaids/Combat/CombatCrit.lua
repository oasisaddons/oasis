-- Real crits: public combat log events or manual import of a local log file.
local _, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Combat", function()   -- Module Combat leaderboard (can be disabled, see ModuleLoader.lua)
local CB = ns.CombatBoard
local secret = issecretvalue or function() return false end
local readFailed
-- The modern Forever client already forbids registering CLEU.
-- pcall doesn't protect against this: the blocked message still appears on load.
local legacyLive = CombatLogGetCurrentEventInfo and not (C_CombatLog and C_CombatLog.IsCombatLogRestricted)
local function plain(v) return not secret(v) end
local function numeric(v) return plain(v) and type(v) == "number" and v > 0 and v < 1e12 and v == math.floor(v) end
function CB.CheckCritSource(report)
    if not ns.db then return end
    if report then readFailed = nil end
    local mode = "unavailable"
    if readFailed then mode = "restricted"
    elseif not legacyLive then mode = CombatLogGetCurrentEventInfo and "restricted" or "unavailable"
    elseif CombatLogGetCurrentEventInfo then
        if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
            local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
            mode = ok and plain(restricted) and restricted == false and "live" or "restricted"
        else mode = "live" end
    end
    ns.db.cbCritDiag = ns.db.cbCritDiag or {}
    ns.db.cbCritDiag.mode, ns.db.cbCritDiag.t = mode, ns.now()
    if report then
        ns.print(mode == "live" and ns.L["Live combat log available. Your new critical hits are recorded."]
            or ns.L["Live combat log blocked. Enable /combatlog, then import the log file."])
        if mode ~= "live" then
            pcall(CB.TakeCritFile)
        end
    end
    return mode
end
function CB.ReadCritEvent(_, event, _, sourceGUID, _, _, _, _, _, _, _, ...)
    if not plain(event) or type(event) ~= "string" then return end
    local me = UnitGUID("player")
    if not plain(sourceGUID) or not plain(me) or not me or sourceGUID ~= me then return end
    local a = { ... }
    local key, amount, crit, sid
    if event == "SWING_DAMAGE" then key, amount, crit = "mh", a[1], a[7]
    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" then
        key, amount, crit, sid = "mh", a[4], a[10], a[1]
    elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
        key, amount, crit, sid = "mhh", a[4], a[7], a[1]
    end
    if key and plain(crit) and crit == true and numeric(amount) then
        if not numeric(sid) then sid = nil end
        CB.RecordCrit(key, amount, sid, "combatlog")
        ns.db.cbCritDiag = ns.db.cbCritDiag or {}
        ns.db.cbCritDiag.lastEvent = ns.now()
    end
end
if legacyLive then ns.On("COMBAT_LOG_EVENT_UNFILTERED", function()
    if CB.CheckCritSource() ~= "live" then return end
    -- Check secret values in our own reader first; never convert via tostring/arithmetic.
    local ok = pcall(function() CB.ReadCritEvent(CombatLogGetCurrentEventInfo()) end)
    if not ok then readFailed = true ns.db.cbCritDiag.mode = "restricted" end
end) end
ns.Listen("LOGIN", CB.CheckCritSource)
-- Without combat log: WoW reports every hit on a unit (UNIT_COMBAT) including "CRITICAL". Who hit is not included,
-- so it only counts while you're in combat solo (no group, no instance) - then the hit on your own target comes
-- from yourself (or your own pet). Groups and dungeons still come via the log file (OasisSync).
function CB.ReadUnitCombat(unit, action, flag, amount)
    if secret(unit) or secret(action) or secret(flag) or secret(amount) then return false end
    if flag ~= "CRITICAL" or not numeric(amount) then return false end
    if ns.db and ns.db.settings and ns.db.settings.cbLiveCrit == false then return false end
    if (IsInGroup and IsInGroup()) or (ns.inInstance and ns.inInstance()) then return false end
    if unit == "target" and action == "WOUND" then
        if not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
        if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return false end
        return CB.RecordCrit("mh", amount, nil, "live")
    elseif unit == "player" and action == "HEAL" then
        return CB.RecordCrit("mhh", amount, nil, "live")
    end
    return false
end
ns.On("UNIT_COMBAT", function(unit, action, flag, amount) pcall(CB.ReadUnitCombat, unit, action, flag, amount) end)
ns.On("PLAYER_ENTERING_WORLD", function() readFailed = nil CB.CheckCritSource() end)
ns.On("ADDON_RESTRICTION_STATE_CHANGED", function() readFailed = nil CB.CheckCritSource() end)
-- Short, copyable import code from ImportCrits.py, exclusively for the own name.
ns.slash.critimport = function(text)
    if ns.inCombat() then ns.print(ns.L["Not possible in combat - try again shortly."]) return end
    local name, damage, dsid, heal, hsid = (text or ""):match("^OAC1:([^:]+):(%d+),(%d+):(%d+),(%d+)$")
    if not name or #name > 300 then ns.print(ns.L["Invalid critical hit import code."]) return end
    name = name:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    if not ns.SameName(name, ns.me()) then ns.print(ns.L["Critical hit import belongs to another character."]) return end
    damage, dsid, heal, hsid = tonumber(damage), tonumber(dsid), tonumber(heal), tonumber(hsid)
    if not damage or not heal or damage >= 1e12 or heal >= 1e12
        or not dsid or not hsid or dsid >= 1e12 or hsid >= 1e12 then ns.print(ns.L["Invalid critical hit import code."]) return end
    CB.RecordCrit("mh", damage, dsid, "logfile")
    CB.RecordCrit("mhh", heal, hsid, "logfile")
    ns.print(ns.L["Confirmed critical hit records imported from the log file."])
    ns.RefreshPage("fight", true)
end

-- Automatic path without pasting code: ImportCrits.bat writes CritImport.lua (OasisCritImport) from the local
-- combat log files. In the Forever log the name appears as "Name-Realm-"; only the own character is taken.
function CB.TakeCritFile()
    local t = rawget(_G, "OasisCritImport")
    local me = ns.me and ns.me()
    if type(t) ~= "table" or type(t.players) ~= "table" or not me then return 0 end
    local first = (me:match("^([^%s%-]+)") or ""):lower()
    local realm = (me:match("%-([^%-]+)$") or ""):lower()
    if first == "" then return 0 end
    local n = 0
    for _, e in ipairs(t.players) do
        if type(e) == "table" and type(e.n) == "string" then
            local f, r = e.n:lower():match("^([^%-]+)%-?([^%-]*)")
            if f == first and (realm == "" or r == "" or r == realm) then
                if CB.RecordCrit("mh", tonumber(e.mh), tonumber(e.mhsid), "logfile") then n = n + 1 end
                if CB.RecordCrit("mhh", tonumber(e.mhh), tonumber(e.mhhsid), "logfile") then n = n + 1 end
            end
        end
    end
    if n > 0 then
        ns.print(ns.L["Critical hit records imported from the combat log files."])
        if ns.RefreshPage then ns.RefreshPage("fight", true) end
    end
    return n
end
ns.Listen("LOGIN", function() if ns.After then ns.After(6, function() pcall(CB.TakeCritFile) end) end end)
-- 0.5.787: have the combat log file written by default (like /combatlog) so crit import works without prep.
-- Can be disabled with /oa kampflog. If the client blocks the call, the automation permanently turns itself off (no repeated message).
do
    local triedAt
    -- 0.5.938: without own choice only on with the guild module - the public version doesn't write a file unasked
    local function wanted()
        local s = ns.db and ns.db.settings
        if not s then return false end
        if s.cbAutoLog == nil then return ns.GuildPack and true or false end
        return s.cbAutoLog and true or false
    end
    CB.AutoLogWanted = wanted
    local function autoLog()
        if not wanted() or not LoggingCombat then return end
        local ok, on = pcall(LoggingCombat)
        if ok and on then return end
        triedAt = GetTime()
        if ns.Trace then ns.Trace("LoggingCombat") end
        pcall(LoggingCombat, true)
    end
    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "ADDON_ACTION_BLOCKED")
    pcall(ev.RegisterEvent, ev, "ADDON_ACTION_FORBIDDEN")
    ev:SetScript("OnEvent", function()
        if triedAt and GetTime() - triedAt < 0.5 and ns.db then
            ns.db.settings.cbAutoLog = false
            triedAt = nil
            ns.print(ns.L["The client does not let Oasis enable combat logging - please type /combatlog yourself."])
        end
    end)
    ns.Listen("LOGIN", function() ns.After(8, function() pcall(autoLog) end) end)
    -- Toggle in settings (Sections > Combat leaderboard): apply immediately
    function CB.ApplyAutoLog()
        if wanted() then pcall(autoLog) elseif LoggingCombat then pcall(LoggingCombat, false) end
    end
    ns.slash.kampflog = function()
        local s = ns.db.settings
        s.cbAutoLog = not wanted()
        if s.cbAutoLog then pcall(autoLog) elseif LoggingCombat then pcall(LoggingCombat, false) end
        ns.print(s.cbAutoLog and ns.L["Combat log file: written automatically."] or ns.L["Combat log file: automatic logging off."])
    end
end

------------------------------------------------------------------------
-- Developer query (/oa probe dm): what does Blizzard's damage meter give per source and per spell?
-- Underlying question: is there a highest single hit / crit - then dungeon crits would work without a log file.
-- Writes only field names, types and readable own values to ns.db.dmProbe (in the SavedVariables after /reload).
------------------------------------------------------------------------
do
    local function describe(out, pre, t, depth)
        if type(t) ~= "table" then out[#out + 1] = pre .. " = " .. (secret(t) and "<secret>" or (type(t) .. ":" .. tostring(t):sub(1, 40))) return end
        local keys = {}
        for k in pairs(t) do if type(k) ~= "number" then keys[#keys + 1] = tostring(k) end end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = t[k]
            if secret(v) then out[#out + 1] = pre .. "." .. k .. " = <secret>"
            elseif type(v) == "table" then
                out[#out + 1] = pre .. "." .. k .. " = table #" .. #v
                if depth > 0 then describe(out, pre .. "." .. k, v, depth - 1) end
            else out[#out + 1] = pre .. "." .. k .. " = " .. type(v) .. ":" .. tostring(v):sub(1, 40) end
        end
        -- List: break down only the first element
        if type(t[1]) == "table" and depth > 0 then describe(out, pre .. "[1]", t[1], depth - 1)
        elseif t[1] ~= nil then out[#out + 1] = pre .. "[1] = " .. (secret(t[1]) and "<secret>" or type(t[1])) end
    end
    ns.probes = ns.probes or {}
    ns.probes.dm = function()
        if not (ns.IsDev and ns.IsDev()) then return end
        local out = {}
        local DM = C_DamageMeter
        if type(DM) ~= "table" then
            out[1] = "C_DamageMeter fehlt"
        else
            local fn = {}
            for k, v in pairs(DM) do if type(v) == "function" then fn[#fn + 1] = k end end
            table.sort(fn)
            out[#out + 1] = "Functions: " .. table.concat(fn, ", ")
            for _, en in ipairs({ "DamageMeterType", "DamageMeterSessionType" }) do
                local e, parts = Enum and Enum[en], {}
                for k, v in pairs(type(e) == "table" and e or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
                table.sort(parts)
                out[#out + 1] = en .. ": " .. table.concat(parts, ", ")
            end
            local guid = UnitGUID and UnitGUID("player")
            local okL, list = pcall(function() return DM.GetAvailableCombatSessions and DM.GetAvailableCombatSessions() end)
            local lastID
            if okL and type(list) == "table" then
                out[#out + 1] = "Sitzungen: " .. #list
                if type(list[#list]) == "table" then
                    describe(out, "sitzung", list[#list], 1)
                    local id = list[#list].sessionID
                    if type(id) == "number" and not secret(id) then lastID = id end
                end
            end
            local typ = Enum and Enum.DamageMeterType and (Enum.DamageMeterType.DamageDone or Enum.DamageMeterType.Damage) or 0
            local ST = Enum and Enum.DamageMeterSessionType or {}
            for stName, st in pairs(ST) do
                if DM.GetCombatSessionFromType then
                    local ok, se = pcall(DM.GetCombatSessionFromType, st, typ)
                    out[#out + 1] = "-- FromType " .. tostring(stName) .. ": " .. (ok and type(se) or ("Fehler " .. tostring(se):sub(1, 80)))
                    if ok and type(se) == "table" then describe(out, "S", se, 2) end
                end
                if DM.GetCombatSessionSourceFromType and guid then
                    local ok, so = pcall(DM.GetCombatSessionSourceFromType, st, typ, guid)
                    out[#out + 1] = "-- SourceFromType " .. tostring(stName) .. ": " .. (ok and type(so) or ("Fehler " .. tostring(so):sub(1, 80)))
                    if ok and type(so) == "table" then describe(out, "Q", so, 3) end
                end
            end
            if lastID and DM.GetCombatSessionSourceFromID and guid then
                local ok, so = pcall(DM.GetCombatSessionSourceFromID, lastID, typ, guid)
                out[#out + 1] = "-- SourceFromID " .. lastID .. ": " .. (ok and type(so) or ("Fehler " .. tostring(so):sub(1, 80)))
                if ok and type(so) == "table" then describe(out, "QI", so, 3) end
            end
        end
        while #out > 400 do table.remove(out) end
        ns.db.dmProbe = { t = ns.now(), v = ns.version, group = IsInGroup and IsInGroup() and true or false,
            inst = ns.inInstance and ns.inInstance() and true or false, lines = out }
        -- Summary right in chat: how much is locked, what is readable
        local sec, open, sample = 0, 0, {}
        for _, l in ipairs(out) do
            if l:find("<secret>", 1, true) then sec = sec + 1
            elseif l:find("Amount", 1, true) or l:find("PerSecond", 1, true) or l:find("spellID", 1, true) then
                open = open + 1
                if #sample < 4 then sample[#sample + 1] = l end
            end
        end
        ns.print(("Schadensanzeige-Abfrage: %d Zeilen. Gesperrt: %d, lesbare Zahlen: %d. Im Kampf: %s, Gruppe: %s, Instanz: %s"):format(
            #out, sec, open, ns.inCombat() and "ja" or "nein", ns.db.dmProbe.group and "ja" or "nein", ns.db.dmProbe.inst and "ja" or "nein"))
        for _, l in ipairs(sample) do ns.print("  " .. l:sub(1, 160)) end
    end
end

------------------------------------------------------------------------
-- Developer query (/oa probe stat): client character statistics ("Largest hit dealt" etc.).
-- WoW counts these itself - also in group and dungeon. Question: does Forever return numbers there or just "--"?
------------------------------------------------------------------------
do
    ns.probes = ns.probes or {}
    ns.probes.stat = function()
        if not (ns.IsDev and ns.IsDev()) then return end
        if not (GetStatistic and GetAchievementInfo) then ns.print("Statistik: GetStatistic/GetAchievementInfo fehlt") return end
        local function show(v) if secret(v) then return "<secret>" end return type(v) .. ":" .. tostring(v):sub(1, 40) end
        local out, n = {}, 0
        local function line(id, index)
            local ok, aid, name
            if index then ok, aid, name = pcall(GetAchievementInfo, id, index) else ok, aid, name = pcall(GetAchievementInfo, id) end
            if not ok or secret(aid) or type(aid) ~= "number" then return end
            local okS, rawV = pcall(GetStatistic, aid)
            n = n + 1
            local nm = secret(name) and "<secret>" or tostring(name)
            local low = nm:lower()
            -- remember everything with hit/heal/damage/critical, only count the rest
            if low:find("hit", 1, true) or low:find("treffer", 1, true) or low:find("heal", 1, true) or low:find("heil", 1, true)
                or low:find("crit", 1, true) or low:find("krit", 1, true) or low:find("damage", 1, true) or low:find("schaden", 1, true) then
                out[#out + 1] = ("%d %s = %s"):format(aid, nm, okS and show(rawV) or "Bug")
            end
        end
        line(193) line(189) line(197)
        local okC, cats = pcall(function() return GetStatisticsCategoryList and GetStatisticsCategoryList() end)
        if okC and type(cats) == "table" and GetCategoryNumAchievements then
            for _, cat in ipairs(cats) do
                local okN, cnt = pcall(GetCategoryNumAchievements, cat)
                if okN and type(cnt) == "number" and not secret(cnt) then
                    for i = 1, math.min(cnt, 400) do line(cat, i) end
                end
            end
        end
        ns.db.statProbe = { t = ns.now(), v = ns.version, n = n, lines = out }
        ns.print(("Statistik-Abfrage: %d Statistiken gesehen, %d passende:"):format(n, #out))
        for i = 1, math.min(#out, 14) do ns.print("  " .. out[i]:sub(1, 160)) end
    end
end

------------------------------------------------------------------------
-- Developer query (/oa probe log): READ lines from Blizzard's combat log chat window (change nothing).
-- It says "Your X crits Y for 123" - also in group/dungeon. Question: are the lines readable for addons?
------------------------------------------------------------------------
do
    ns.probes = ns.probes or {}
    ns.probes.log = function()
        if not (ns.IsDev and ns.IsDev()) then return end
        local out, frames = {}, {}
        local cl = rawget(_G, "COMBATLOG")
        if type(cl) == "table" then frames[#frames + 1] = { "COMBATLOG", cl } end
        for i = 1, 10 do
            local f = rawget(_G, "ChatFrame" .. i)
            if type(f) == "table" and f ~= cl and f.GetNumMessages then
                local nm = rawget(_G, "ChatFrame" .. i .. "Tab")
                local okT, t = pcall(function() return nm and nm.GetText and nm:GetText() end)
                frames[#frames + 1] = { "ChatFrame" .. i .. " (" .. tostring(okT and not secret(t) and t or "?") .. ")", f }
            end
        end
        for _, fr in ipairs(frames) do
            local f = fr[2]
            local okN, n = pcall(function() return f.GetNumMessages and f:GetNumMessages() end)
            n = okN and type(n) == "number" and not secret(n) and n or 0
            local sec, crit, shown = 0, 0, 0
            for i = math.max(1, n - 60), n do
                local okM, text = pcall(f.GetMessageInfo, f, i)
                if okM then
                    if secret(text) then sec = sec + 1
                    elseif type(text) == "string" then
                        local low = text:lower()
                        local isCrit = low:find("krit", 1, true) or low:find("crit", 1, true)
                        if isCrit then crit = crit + 1 end
                        if (isCrit or fr[1] == "COMBATLOG") and shown < 6 then
                            shown = shown + 1
                            out[#out + 1] = "   " .. text:gsub("|", "||"):sub(1, 150)
                        end
                    end
                end
            end
            if n > 0 and (fr[1] == "COMBATLOG" or crit > 0 or sec > 0) then
                table.insert(out, #out - shown + 1, ("%s: %d Zeilen, gesperrt %d, mit Crit %d"):format(fr[1], n, sec, crit))
            end
        end
        if #out == 0 then out[1] = "Kein Kampflog-Fenster mit Zeilen gefunden (Reiter Kampflog einmal oeffnen, kaempfen, erneut)." end
        ns.db.logProbe = { t = ns.now(), v = ns.version, lines = out }
        ns.print("Kampflog-Abfrage (im Kampf: " .. (ns.inCombat() and "ja" or "nein") .. "):")
        for i = 1, math.min(#out, 16) do ns.print(out[i]) end
    end
end

------------------------------------------------------------------------
-- 0.5.900: ESTIMATE crits in group and dungeon (all in game, no log file).
-- In a group WoW only reports "unit was critically hit for X", not by whom. Oasis only takes the hit
--   1. if it lands at most half a second after an OWN spell/special attack on my own target and
--   2. if Blizzard's damage meter after combat confirms that exactly this spell did at least that much for me.
-- White hits (no spell event) and spells with long travel time are dropped. Source in record: "group" (= estimated).
-- Counters for debugging: ns.db.cbGroupDiag.
------------------------------------------------------------------------
do
    local WINDOW = 0.5
    local lastCast, cands, batches, retry = nil, {}, {}, false
    local function diag(k)
        if not ns.db then return end
        ns.db.cbGroupDiag = ns.db.cbGroupDiag or {}
        local d = ns.db.cbGroupDiag
        d[k] = (d[k] or 0) + 1
        d.t, d.v = ns.now(), ns.version
    end
    local function active()
        if not ns.db or ns.db.settings.cbGroupCrit == false then return false end
        return ((IsInGroup and IsInGroup()) or (ns.inInstance and ns.inInstance())) and true or false
    end
    ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if secret(unit) or unit ~= "player" or not active() then return end
        if secret(spellID) or type(spellID) ~= "number" then diag("castSecret") return end
        lastCast = { t = GetTime(), sid = spellID }
        diag("casts")
    end)
    function CB.ReadGroupCombat(unit, action, flag, amount)
        if secret(unit) or secret(action) or secret(flag) or type(unit) ~= "string" then return false end
        if flag ~= "CRITICAL" or not active() then return false end
        local key
        if unit == "target" and action == "WOUND" then key = "mh"
        elseif action == "HEAL" and (unit == "target" or unit == "player" or unit:find("^party") or unit:find("^raid")) then key = "mhh" end
        if not key then return false end
        diag("crits")
        if secret(amount) or not numeric(amount) then diag("amountSecret") return false end
        if key == "mh" and not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
        if not lastCast or GetTime() - lastCast.t > WINDOW then diag("noCast") return false end
        if lastCast.used then return false end   -- per own attack only the first hit (also: the same unit under two names)
        lastCast.used = true
        cands[#cands + 1] = { key = key, amount = amount, sid = lastCast.sid }
        while #cands > 30 do table.remove(cands, 1) end
        diag("cands")
        return true
    end
    ns.On("UNIT_COMBAT", function(unit, action, flag, amount) pcall(CB.ReadGroupCombat, unit, action, flag, amount) end)

    -- my spell totals of a session: { [spellID] = total, [name] = total } | false = still locked | nil = not present
    local function mySpells(id, typ)
        local DM = C_DamageMeter
        local guid = UnitGUID and UnitGUID("player")
        if not (DM and typ ~= nil and guid) or secret(guid) then return nil end
        local ok, src
        if id and DM.GetCombatSessionSourceFromID then ok, src = pcall(DM.GetCombatSessionSourceFromID, id, typ, guid) end
        if not (ok and type(src) == "table") then return nil end
        local list = src.combatSpells
        if type(list) ~= "table" then return nil end
        local map = {}
        for _, sp in ipairs(list) do
            if type(sp) == "table" then
                local sid, tot = sp.spellID, sp.totalAmount
                if secret(sid) or secret(tot) then return false end
                if type(sid) == "number" and type(tot) == "number" then
                    map[sid] = math.max(map[sid] or 0, tot)
                    local okN, nm = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) end)
                    if okN and type(nm) == "string" and not secret(nm) then map[nm] = math.max(map[nm] or 0, tot) end
                end
            end
        end
        return map
    end
    local function validate()
        retry = false
        if not ns.db or ns.inCombat() then return end
        local T = Enum and Enum.DamageMeterType or {}
        local keep = {}
        for _, b in ipairs(batches) do
            local maps = { mh = mySpells(b.id, T.DamageDone), mhh = mySpells(b.id, T.HealingDone) }
            local locked = false
            for _, c in ipairs(b.list) do if maps[c.key] == false then locked = true end end
            if locked then
                if ns.now() - b.t < 3 * 3600 then keep[#keep + 1] = b else diag("lost") end
            else
                for _, c in ipairs(b.list) do
                    local map = maps[c.key]
                    local okN, nm = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(c.sid) end)
                    local tot = map and (map[c.sid] or (okN and type(nm) == "string" and not secret(nm) and map[nm]))
                    if tot and tot >= c.amount then
                        diag("valid")
                        CB.RecordCrit(c.key, c.amount, c.sid, "group")
                    else
                        diag(map and "rejected" or "noMeter")
                    end
                end
            end
        end
        batches = keep
        if #batches > 0 and not retry then retry = true ns.After(20, validate) end
    end
    CB.ValidateGroupCrits = validate
    ns.On("PLAYER_REGEN_ENABLED", function()
        if #cands == 0 then return end
        local list = cands
        cands = {}
        -- Session of the fight that just ended: wait briefly until the damage meter lists it
        ns.After(2, function()
            local id
            local ok, l = pcall(function() return C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetAvailableCombatSessions() end)
            for _, e in ipairs(ok and type(l) == "table" and l or {}) do
                local sid = type(e) == "table" and e.sessionID
                if type(sid) == "number" and not secret(sid) and (not id or sid > id) then id = sid end
            end
            if not id then diag("noSession") return end
            batches[#batches + 1] = { id = id, t = ns.now(), list = list }
            while #batches > 20 do table.remove(batches, 1) end
            validate()
        end)
    end)
    ns.On("ENCOUNTER_END", function() if #batches > 0 then ns.After(3, validate) end end)
    ns.On("ADDON_RESTRICTION_STATE_CHANGED", function() if #batches > 0 then ns.After(0.5, validate) end end)
end
end)

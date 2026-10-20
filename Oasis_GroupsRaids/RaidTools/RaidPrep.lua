-- Oasis: Raid-Vorbereitung - bin ich (und sind alle) bereit fuer den naechsten Raidtermin?
--  * je Raid ein Profil (Barrow Deeps / Hyjal / Onyxia): Widerstaende, Pflicht-Ausruestung, Schluessel
--  * Verbrauchsgueter in den Taschen je Rolle + Klassen-Reagenzien (Item-IDs in Tabellen unten)
--  * Haltbarkeit der Ausruestung
--  * fehlende Schluessel/Freischaltungen: ns.Lockouts (falls vorhanden), sonst eigene Item-Pruefung
--  * jeder teilt seinen Stand gedrosselt vor dem Termin (Nachricht RPREP, Sammlung "raidprep" lokal)
--  * Seite "Raid-Vorbereitung" (Nav-Gruppe Raid): Ampel je Teilnehmer + eigene Checkliste
-- Ergaenzt RaidCheck (Bereitschaft/Buffs/Verzauberungen direkt vor dem Pull) - hier geht es um die Tage davor.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raidwerkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Core\Diagnostics\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C, Store, Comm = ns.K, ns.K.C, ns.Store, ns.Comm
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

local RP = {}
ns.RaidPrep = RP
local COLL = "raidprep"
if ns.ICONS then ns.ICONS.raidprep = ns.MEDIA .. "icons\\checklist" end
-- in die Navigationsgruppe "Raid" einhaengen (ohne Main.lua anzufassen)
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "raid" then
        local has
        for _, k in ipairs(g.pages) do if k == "raidprep" then has = true end end
        local pos = #g.pages + 1
        for i, k in ipairs(g.pages) do if k == "raidcheck" then pos = i + 1 end end
        if not has then table.insert(g.pages, pos, "raidprep") end
    end
end

------------------------------------------------------------------------
-- Gemeinsame Hilfen: /oa probe <thema> (andere Module koennen ns.Probes[thema] eintragen)
------------------------------------------------------------------------
ns.Probes = ns.Probes or {}
if not ns._ProbesHooked then
    ns._ProbesHooked = true
    local prev = ns.slash.probe
    ns.slash.probe = function(rest)
        local topic = ((rest or ""):match("^(%S*)") or ""):lower()
        local fn = ns.Probes[topic]
        if fn then
            local ok, e = pcall(fn, rest)
            if not ok then ns.print("probe " .. topic .. ": " .. tostring(e)) end
            return
        end
        if prev then return prev(rest) end
        local keys = {}
        for k in pairs(ns.Probes) do keys[#keys + 1] = k end
        table.sort(keys)
        ns.print(L["Probe-Themen: "] .. table.concat(keys, ", "))
    end
end

------------------------------------------------------------------------
-- Daten: Widerstaende, Verbrauchsgueter, Profile
------------------------------------------------------------------------
-- UnitResistance-Index: 1 Heilig, 2 Feuer, 3 Natur, 4 Frost, 5 Schatten, 6 Arkan
local RES_NAME = { [1] = "Heilig", [2] = "Feuer", [3] = "Natur", [4] = "Frost", [5] = "Schatten", [6] = "Arkan" }
RP.RES_NAME = RES_NAME

-- Verbrauchsgueter je Rolle: ids = gleichwertige Alternativen (zusammengezaehlt), n = Sollmenge, opt = nur Empfehlung
local BASE = {
    all = {
        { ids = { 13446, 3928 }, n = 5, label = "Erheblicher Heiltrank" },
        { ids = { 20452, 18254, 13931, 13928, 21023, 12218, 13929, 18045 }, n = 10, label = "Buff-Essen" },
    },
    tank = {
        { ids = { 13445 }, n = 2, label = "Elixier der hoeheren Verteidigung" },
        { ids = { 3825 }, n = 2, label = "Elixier der Seelenstaerke" },
        { ids = { 5634 }, n = 1, label = "Trank der freien Aktion" },
        { ids = { 13510 }, n = 1, label = "Flaeschchen der Titanen", opt = true },
    },
    melee = {
        { ids = { 13452 }, n = 2, label = "Elixier des Mungos" },
        { ids = { 9206 }, n = 2, label = "Elixier der Riesen" },
        { ids = { 5634 }, n = 1, label = "Trank der freien Aktion", opt = true },
    },
    caster = {
        { ids = { 13454 }, n = 2, label = "Grosses Arkanelixier" },
        { ids = { 13444 }, n = 5, label = "Erheblicher Manatrank" },
        { ids = { 13512 }, n = 1, label = "Flaeschchen der obersten Macht", opt = true },
    },
    heal = {
        { ids = { 13444 }, n = 5, label = "Erheblicher Manatrank" },
        { ids = { 20007 }, n = 2, label = "Magiebluttrank" },
        { ids = { 12662, 20520 }, n = 3, label = "Daemonische oder Dunkle Rune" },
        { ids = { 13511 }, n = 1, label = "Flaeschchen der destillierten Weisheit", opt = true },
    },
}
-- Klassen-Reagenzien
local REAGENTS = {
    MAGE = { { ids = { 17020 }, n = 20, label = "Arkanes Pulver" }, { ids = { 17031 }, n = 2, label = "Rune der Teleportation", opt = true } },
    PRIEST = { { ids = { 17029 }, n = 20, label = "Heilige Kerze" } },
    DRUID = { { ids = { 17026 }, n = 10, label = "Wilde Dornwurzel" } },
    PALADIN = { { ids = { 21177 }, n = 40, label = "Symbol der Koenige" }, { ids = { 17033 }, n = 2, label = "Symbol der Goettlichkeit", opt = true } },
    SHAMAN = { { ids = { 17030 }, n = 3, label = "Ankh" } },
    WARLOCK = { { ids = { 6265 }, n = 10, label = "Seelensplitter" }, { ids = { 5565 }, n = 1, label = "Hoellenstein", opt = true } },
    ROGUE = { { ids = { 5140 }, n = 10, label = "Blitzpulver" }, { ids = { 8928 }, n = 20, label = "Sofort wirkendes Gift VI" } },
}
-- Raid-Profile: match = Suchworte in Termin-Titel/Instanz; res[schule] = { tank =, other = }
-- keys = Item, das man besitzen muss (Bank zaehlt); gear = Item, das angelegt sein muss
RP.RAIDS = {
    { key = "barrow", name = "Barrow Deeps", size = 10, match = { "barrow", "deeps", "huegelgrab" },
        res = {}, cons = {}, keys = {}, gear = {} },
    { key = "hyjal", name = "Hyjal", size = 20, match = { "hyjal" },
        res = { [2] = { tank = 120, other = 60 } },
        cons = { all = { { ids = { 13457 }, n = 3, label = "Grosser Feuerschutztrank" } },
                 tank = { { ids = { 13457 }, n = 5, label = "Grosser Feuerschutztrank" } } },
        keys = {}, gear = {} },
    { key = "onyxia", name = "Onyxias Hort", size = 40, match = { "onyx" },
        res = { [2] = { tank = 150, other = 40 } },
        cons = { all = { { ids = { 13457 }, n = 2, label = "Grosser Feuerschutztrank" } },
                 tank = { { ids = { 13457 }, n = 4, label = "Grosser Feuerschutztrank" } } },
        keys = { { id = 16309, label = "Drachenfeueramulett" } },
        gear = { { id = 15138, label = "Onyxiaschuppenumhang" } } },
}
RP.byKey = {}
for _, r in ipairs(RP.RAIDS) do RP.byKey[r.key] = r end
-- Beschriftung je Item (erste ID eines Eintrags) fuer die Anzeige fremder Staende
local LABEL = {}
local function regLabels(list) for _, e in ipairs(list or {}) do LABEL[e.ids and e.ids[1] or e.id] = e.label end end
for _, l in pairs(BASE) do regLabels(l) end
for _, l in pairs(REAGENTS) do regLabels(l) end
for _, r in ipairs(RP.RAIDS) do
    for _, l in pairs(r.cons) do regLabels(l) end
    regLabels(r.keys) regLabels(r.gear)
end

local ROLES = { { key = "tank", text = "Tank" }, { key = "heal", text = "Heiler" }, { key = "melee", text = "Nahkampf" }, { key = "caster", text = "Zauber-DD" } }
local ROLE_TEXT = {}
for _, r in ipairs(ROLES) do ROLE_TEXT[r.key] = r.text end
local CASTER = { MAGE = true, WARLOCK = true }
local HEALER = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }

------------------------------------------------------------------------
-- Einstellungen
------------------------------------------------------------------------
local function S() return ns.db.settings end
local function shareOn() return S().rpShare ~= false end
ns.AddPageSettings("raidprep", function(det, y)
    local t = K.Toggle(det, L["Meinen Stand vor Raidterminen teilen"], function() return shareOn() end, function(v) S().rpShare = v end,
        L["Ampel, Haltbarkeit, Widerstaende und was fehlt - hoechstens alle paar Minuten, nur am Tag des Termins"])
    t:SetPoint("TOPLEFT", 14, y)
    t:SetWidth(600)
    det.t[#det.t + 1] = t
    y = y - 46
    local t2 = K.Toggle(det, L["Hinweis, wenn mir etwas fehlt"], function() return S().rpToast ~= false end, function(v) S().rpToast = v end,
        L["Einmal am Termintag, wenn deine Ampel nicht gruen ist"])
    t2:SetPoint("TOPLEFT", 14, y)
    t2:SetWidth(600)
    det.t[#det.t + 1] = t2
    return y - 50
end)

------------------------------------------------------------------------
-- Termin und Profil
------------------------------------------------------------------------
local function lower(s) return tostring(s or ""):lower() end
function RP.ProfileFor(ev)
    if not ev then return nil end
    local hay = lower(ev.title) .. " " .. lower(ev.inst)
    for _, r in ipairs(RP.RAIDS) do
        for _, m in ipairs(r.match) do if hay:find(m, 1, true) then return r end end
    end
end
-- naechster Termin: mit eigener Zusage zuerst, sonst der naechste ueberhaupt
function RP.NextEvent()
    local R = ns.Raid
    if not R then return nil end
    if R.NextMine then
        local ok, ev = pcall(R.NextMine)
        if ok and ev then return ev end
    end
    if R.Events then
        local ok, list = pcall(R.Events)
        if ok and list then
            local now = ns.now()
            for _, ev in ipairs(list) do if (ev.ts or 0) > now - 3 * 3600 and not ev.del then return ev end end
        end
    end
end
-- aktives Profil: selbst gewaehlt > aus dem Termin > Onyxia (bekanntester Fall)
function RP.CurrentProfile(ev)
    local own = ns.char and ns.char.rpRaid
    if own and RP.byKey[own] then return RP.byKey[own], true end
    -- Raid-Simulator: Profil des simulierten Raids
    if ns.Sim and ns.Sim.Active() then
        local inst = ns.Group.Instance()
        if inst and inst.key and RP.byKey[inst.key] then return RP.byKey[inst.key], false end
    end
    return RP.ProfileFor(ev or RP.NextEvent()) or RP.byKey.onyxia, false
end

-- Anforderungen aendern: Raidleitung (wie Boss-Taktiken)
function RP.CanEditReq()
    if ns.RaidCheck and ns.RaidCheck.CanEdit then return ns.RaidCheck.CanEdit() end
    return ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.tactics.edit") or false
end
function RP.MyRole(ev)
    local own = ns.char and ns.char.rpRole
    if own and ROLE_TEXT[own] then return own end
    local _, cls = UnitClass("player")
    local r
    if ev and ns.Raid and ns.Raid.MySignup then
        local ok, s = pcall(ns.Raid.MySignup, ev.id)
        if ok and s then r = lower(s.role) end
    end
    if not r or r == "" then
        local m = ns.db.members[ns.me() or ""]
        r = m and lower(m.role) or ""
    end
    if r == "tank" then return "tank" end
    if r == "heal" or r == "healer" then return "heal" end
    if r == "dps" or r == "damager" then return CASTER[cls] and "caster" or "melee" end
    if HEALER[cls] then return "heal" end
    return CASTER[cls] and "caster" or "melee"
end

------------------------------------------------------------------------
-- Eigener Stand (nur ausserhalb des Kampfes)
------------------------------------------------------------------------
local function count(id, bank)
    local n
    if C_Item and C_Item.GetItemCount then
        local ok, v = pcall(C_Item.GetItemCount, id, bank and true or false)
        if ok then n = ns.safe(v) end
    end
    if n == nil and GetItemCount then
        local ok, v = pcall(GetItemCount, id, bank and true or false)
        if ok then n = ns.safe(v) end
    end
    return tonumber(n) or 0
end
local function equipped(id)
    local f = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
    if not f then return nil end
    local ok, v = pcall(f, id)
    if not ok then return nil end
    return ns.safe(v) and true or false
end
local function resistance(school)
    if not UnitResistance then return nil end
    local ok, _, total = pcall(UnitResistance, "player", school)
    if not ok then return nil end
    return tonumber(ns.safe(total))
end
local function durability()
    if not GetInventoryItemDurability then return nil end
    local low, sum, n = nil, 0, 0
    for slot = 1, 18 do
        local ok, cur, mx = pcall(GetInventoryItemDurability, slot)
        if ok then
            cur, mx = ns.safe(cur), ns.safe(mx)
            if type(cur) == "number" and type(mx) == "number" and mx > 0 then
                local p = cur / mx
                sum, n = sum + p, n + 1
                if not low or p < low then low = p end
            end
        end
    end
    if n == 0 then return nil end
    return math.floor(low * 100 + 0.5), math.floor(sum / n * 100 + 0.5)
end
-- Schluessel/Freischaltungen ueber Lockouts.lua (falls vorhanden): liefert Liste fehlender Texte oder nil
local function lockoutMissing(profile)
    local LO = ns.Lockouts
    if type(LO) ~= "table" then return nil end
    -- Lockouts.lua: StateOf(name, raidKey) -> "bound" | "free" | "locked" | "low" | "nodata"
    if type(LO.StateOf) == "function" then
        local r
        if type(LO.RaidFor) == "function" then
            local ok, x = pcall(LO.RaidFor, profile.name)
            if ok and type(x) == "table" then r = x end
        end
        if not r and type(LO.RAID_BY) == "table" then r = LO.RAID_BY[profile.key] end
        if r and r.key then
            local ok, st = pcall(LO.StateOf, ns.me(), r.key)
            if ok then
                if st == "locked" then
                    local u = r.unlock and type(LO.UNLOCK_BY) == "table" and LO.UNLOCK_BY[r.unlock]
                    return { u and u.text and L[u.text] or (L["Freischaltung fuer %s"]):format(L[profile.name]) }
                elseif st == "low" then
                    return { L["Stufe fuer diesen Raid"] }
                elseif st == "bound" then
                    return { L["schon gebunden (Raid-ID diese Woche)"] }
                elseif st == "free" then
                    return {}
                end
            end
        end
    end
    for _, fname in ipairs({ "MissingKeys", "MissingAttunements", "Missing" }) do
        if type(LO[fname]) == "function" then
            local ok, res = pcall(LO[fname], profile.key, profile.name)
            if ok and type(res) == "table" then
                local out = {}
                for _, v in ipairs(res) do out[#out + 1] = tostring(type(v) == "table" and (v.name or v.label or v.text) or v) end
                return out
            end
        end
    end
    for _, fname in ipairs({ "HasAccess", "IsAttuned", "HasKey" }) do
        if type(LO[fname]) == "function" then
            local ok, res = pcall(LO[fname], profile.key, profile.name)
            if ok and res == false then return { (L["Freischaltung fuer %s"]):format(L[profile.name]) } end
            if ok and res == true then return {} end
        end
    end
    return nil
end
RP.lockoutMissing = lockoutMissing

------------------------------------------------------------------------
-- Anforderungen der Raidleitung je Raid (Sammlung "rpreq", id "req-<raid>"):
--   fireT/fireO = Feuer-Widerstand Tank/andere, off = "id,id" (abgeschaltet), n = "id:n,..." (Sollmenge),
--   add = "id:n:rolle,..." (zusaetzlich, rolle = all/tank/heal/melee/caster)
------------------------------------------------------------------------
function RP.Req(key)
    local r = Store.Get("rpreq", "req-" .. tostring(key))
    if r and not r.del then return r end
end
local function parseSet(str) local t = {} for id in tostring(str or ""):gmatch("%d+") do t[tonumber(id)] = true end return t end
local function parseN(str) local t = {} for id, n in tostring(str or ""):gmatch("(%d+):(%d+)") do t[tonumber(id)] = tonumber(n) end return t end
local function parseAdd(str)
    local t = {}
    for id, n, role in tostring(str or ""):gmatch("(%d+):(%d+):(%a+)") do t[#t + 1] = { id = tonumber(id), n = tonumber(n), role = role } end
    return t
end
RP.parseSet, RP.parseN, RP.parseAdd = parseSet, parseN, parseAdd
local function itemLabel(id)
    local n = C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
    return n or ("#" .. id)
end
-- wirksame Widerstaende eines Profils (Raidleitung kann Feuer anpassen, 0 = aus)
function RP.EffRes(profile)
    if not profile then return {} end
    local rq = RP.Req(profile.key)
    if not rq or (rq.fireT == nil and rq.fireO == nil) then return profile.res end
    local out = {}
    for k, v in pairs(profile.res) do out[k] = v end
    local t, o = tonumber(rq.fireT) or 0, tonumber(rq.fireO) or 0
    if t > 0 or o > 0 then out[2] = { tank = t, other = o } else out[2] = nil end
    return out
end
local function needList(profile, role, cls)
    local out = {}
    local function add(list) for _, e in ipairs(list or {}) do out[#out + 1] = e end end
    add(BASE.all) add(BASE[role]) add(REAGENTS[cls])
    if profile then
        add(profile.cons.all) add(profile.cons[role])
    end
    -- Raidleitung: zusaetzliche Items fuer diese Rolle
    local rq = profile and RP.Req(profile.key)
    if rq then
        for _, a in ipairs(parseAdd(rq.add)) do
            if a.role == "all" or a.role == role then out[#out + 1] = { ids = { a.id }, n = a.n, label = itemLabel(a.id), lead = true } end
        end
    end
    -- gleiche Items zusammenfassen (Profil hebt die Sollmenge an)
    local merged, byId = {}, {}
    for _, e in ipairs(out) do
        local k = e.ids[1]
        local m = byId[k]
        if m then
            m.n = math.max(m.n, e.n)
            if not e.opt then m.opt = nil end
        else
            m = { ids = e.ids, n = e.n, label = e.label, opt = e.opt }
            byId[k] = m
            merged[#merged + 1] = m
        end
    end
    -- Raidleitung: abgeschaltete Items raus, Sollmengen ueberschreiben
    if rq then
        local off, nn = parseSet(rq.off), parseN(rq.n)
        local f = {}
        for _, m in ipairs(merged) do
            if not off[m.ids[1]] then
                if nn[m.ids[1]] then m.n = nn[m.ids[1]] end
                f[#f + 1] = m
            end
        end
        merged = f
    end
    return merged
end
RP.needList = needList

-- Liefert { light = "g"|"a"|"r", lines = { {text, sev, ok} }, miss = "kodiert", dura, res = {}, role, raid }
-- Kodierung fehlt: i<id>x<n> (Pflicht), o<id>x<n> (optional), r<schule>:<soll>:<ist>, k<id>, g<id>, d<prozent>, l:<text>
function RP.MyState(profile, role)
    local ev = RP.NextEvent()
    profile = profile or RP.CurrentProfile(ev)
    role = role or RP.MyRole(ev)
    local _, cls = UnitClass("player")
    local st = { lines = {}, codes = {}, res = {}, role = role, raid = profile and profile.key or "", light = "g" }
    local worst = 0
    local function sev(s) if s > worst then worst = s end end
    local function line(text, s, ok) st.lines[#st.lines + 1] = { text = text, sev = s, ok = ok } end
    -- Haltbarkeit
    local low, avg = durability()
    st.dura = low
    if low then
        if low < 30 then sev(2) st.codes[#st.codes + 1] = "d" .. low
            line((L["Haltbarkeit: %d%% (reparieren!)"]):format(low), 2)
        elseif low < 70 then sev(1) st.codes[#st.codes + 1] = "d" .. low
            line((L["Haltbarkeit: %d%% (reparieren)"]):format(low), 1)
        else line((L["Haltbarkeit: %d%%"]):format(avg or low), 0, true) end
    else
        line(L["Haltbarkeit: nicht lesbar"], 0, true)
    end
    if profile then
        -- Widerstaende
        for school, need in pairs(RP.EffRes(profile)) do
            local want = (role == "tank") and need.tank or need.other
            local have = resistance(school)
            st.res[school] = have
            if have == nil then
                line((L["%s-Widerstand: nicht lesbar"]):format(L[RES_NAME[school]]), 0, true)
            elseif have < want then
                local s = have < want / 2 and 2 or 1
                sev(s)
                st.codes[#st.codes + 1] = ("r%d:%d:%d"):format(school, want, have)
                line((L["fehlt: %d %s-Widerstand (%d von %d)"]):format(want - have, L[RES_NAME[school]], have, want), s)
            else
                line((L["%s-Widerstand: %d (Ziel %d)"]):format(L[RES_NAME[school]], have, want), 0, true)
            end
        end
        -- Pflicht-Ausruestung
        for _, g in ipairs(profile.gear) do
            local eq = equipped(g.id)
            if eq == false then
                sev(2)
                st.codes[#st.codes + 1] = "g" .. g.id
                line((L["fehlt: %s angelegt"]):format(L[g.label]), 2)
            elseif eq then
                line((L["%s angelegt"]):format(L[g.label]), 0, true)
            end
        end
        -- Schluessel / Freischaltungen
        local lo = lockoutMissing(profile)
        if lo then
            for _, t in ipairs(lo) do
                sev(2)
                st.codes[#st.codes + 1] = "l:" .. t:gsub("[,]", " ")
                line((L["fehlt: %s"]):format(t), 2)
            end
        end
        for _, k in ipairs(profile.keys) do
            if count(k.id, true) <= 0 and equipped(k.id) ~= true then
                sev(2)
                st.codes[#st.codes + 1] = "k" .. k.id
                line((L["fehlt: %s"]):format(L[k.label]), 2)
            else
                line((L["%s vorhanden"]):format(L[k.label]), 0, true)
            end
        end
        if not lo and #profile.keys == 0 then
            line(L["Freischaltungen: keine Daten (Lockouts-Modul fehlt)"], 0, true)
        end
    end
    -- Verbrauchsgueter in den Taschen
    for _, e in ipairs(needList(profile, role, cls)) do
        local have = 0
        for _, id in ipairs(e.ids) do have = have + count(id, false) end
        if have >= e.n then
            line(("%dx %s"):format(have, L[e.label]), 0, true)
        elseif e.opt then
            st.codes[#st.codes + 1] = ("o%dx%d"):format(e.ids[1], e.n - have)
            line((L["optional: %dx %s"]):format(e.n - have, L[e.label]), 0)
        else
            -- fehlende Verbrauchsgueter machen die Ampel gelb (rot nur bei Ausruestung/Schluessel/Widerstand)
            local s = have == 0 and 2 or 1
            sev(1)
            st.codes[#st.codes + 1] = ("i%dx%d"):format(e.ids[1], e.n - have)
            line((L["fehlt: %dx %s"]):format(e.n - have, L[e.label]), s)
        end
    end
    st.light = worst >= 2 and "r" or worst == 1 and "a" or "g"
    st.miss = table.concat(st.codes, ",")
    return st
end

-- fremden Stand (Kodierung) lesbar machen
function RP.FormatCode(code)
    local id, n = code:match("^i(%d+)x(%d+)$")
    if id then return (L["fehlt: %dx %s"]):format(tonumber(n), L[LABEL[tonumber(id)] or ("#" .. id)]), 1 end
    id, n = code:match("^o(%d+)x(%d+)$")
    if id then return (L["optional: %dx %s"]):format(tonumber(n), L[LABEL[tonumber(id)] or ("#" .. id)]), 0 end
    local sc, want, have = code:match("^r(%d+):(%d+):(%d+)$")
    if sc then return (L["fehlt: %d %s-Widerstand (%d von %d)"]):format(tonumber(want) - tonumber(have), L[RES_NAME[tonumber(sc)] or "?"], tonumber(have), tonumber(want)), 1 end
    id = code:match("^k(%d+)$")
    if id then return (L["fehlt: %s"]):format(L[LABEL[tonumber(id)] or ("#" .. id)]), 2 end
    id = code:match("^g(%d+)$")
    if id then return (L["fehlt: %s angelegt"]):format(L[LABEL[tonumber(id)] or ("#" .. id)]), 2 end
    n = code:match("^d(%d+)$")
    if n then return (L["Haltbarkeit: %d%% (reparieren)"]):format(tonumber(n)), tonumber(n) < 30 and 2 or 1 end
    local t = code:match("^l:(.*)$")
    if t then return (L["fehlt: %s"]):format(t), 2 end
    return code, 0
end
function RP.FormatMiss(s, withOpt)
    local out = {}
    for code in tostring(s or ""):gmatch("[^,]+") do
        local t, sv = RP.FormatCode(code)
        if withOpt or code:sub(1, 1) ~= "o" then out[#out + 1] = { text = t, sev = sv } end
    end
    return out
end

------------------------------------------------------------------------
-- Teilen (gedrosselt) und Empfangen
------------------------------------------------------------------------
local lastSent, lastHash, lastReq = 0, nil, 0
local function myRecord(st, ev)
    return {
        id = "rp@" .. (ns.me() or "?"), who = ns.me(), ev = ev and ev.id or "", raid = st.raid, role = st.role,
        light = st.light, dura = st.dura or -1, fire = st.res[2] or -1, miss = st.miss or "", ts = ns.now(), ver = ns.version,
    }
end
function RP.Share(force)
    if not ns.loggedIn or ns.inCombat() then return false end
    local ev = RP.NextEvent()
    local st = RP.MyState(nil, nil)
    local rec = myRecord(st, ev)
    rec.u = ns.now()
    Store.merge(COLL, rec)
    if not IsInGuild() then return false end
    local h = ns.hash(rec.light .. rec.miss .. rec.raid .. rec.ev .. rec.dura .. rec.fire)
    local now = GetTime()
    if not force and h == lastHash and now - lastSent < 1800 then return false end
    if not force and now - lastSent < 180 then return false end
    lastSent, lastHash = now, h
    local send = {}
    for k, v in pairs(rec) do if k ~= "id" and k ~= "who" then send[k] = v end end
    Comm.SendEx({ ch = "GUILD", key = "rprep", bulk = true }, "RPREP", Comm.encodeRecord(send))
    return true
end
Comm.On("RPREP", function(sender, _, s)
    if not s or #s > 4000 then return end
    local rec = Comm.decodeRecord(s)
    if not rec then return end
    -- Felder entschaerfen/begrenzen, Zeitstempel nicht in der Zukunft
    local n = 0
    for k, v in pairs(rec) do
        n = n + 1
        if n > 60 then rec[k] = nil
        elseif type(v) == "string" then rec[k] = SEC.Text(v, 600)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then rec[k] = 0 end
    end
    rec.demo, rec.sim = nil, nil
    rec.who = sender
    rec.by = sender
    rec.id = "rp@" .. sender
    rec.ts = math.min(tonumber(rec.ts) or ns.now(), ns.now() + 300)
    rec.u = rec.ts
    rec.ts = rec.u
    Store.merge(COLL, rec, true, sender)
    ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
end)
-- jemand oeffnet die Ansicht und bittet um aktuelle Staende -> gestreut antworten
Comm.On("RPREQ", function()
    if not shareOn() then return end
    ns.After(math.random(10, 80) / 10, function() RP.Share(false) end)
end)
function RP.RequestAll()
    if GetTime() - lastReq < 300 or not IsInGuild() then return end
    lastReq = GetTime()
    Comm.SendEx({ ch = "GUILD", key = "rpreq" }, "RPREQ", "1")
end

-- Takt: am Termintag (bis 24 Std vorher, bis 3 Std nach Beginn) automatisch teilen
local toastDay
local function tick()
    if not shareOn() or ns.inCombat() then return end
    local ev = RP.NextEvent()
    if not ev then return end
    local d = (ev.ts or 0) - ns.now()
    if d > 24 * 3600 or d < -3 * 3600 then return end
    RP.Share(false)
    if S().rpToast ~= false then
        local day = date("%Y%m%d")
        if toastDay ~= day and (ns.char.rpToastDay or "") ~= day then
            local st = RP.MyState()
            if st.light ~= "g" then
                toastDay = day
                ns.char.rpToastDay = day
                local first
                for _, l in ipairs(st.lines) do if not l.ok and l.sev > 0 then first = l.text break end end
                K.Toast(L["Raid-Vorbereitung"], first or "", st.light == "r" and C.red or C.amber, function() ns.ShowPage("raidprep") end)
            end
        end
    end
end
local dirty
local function markDirty()
    if dirty then return end
    dirty = true
    ns.After(8, function()
        dirty = nil
        tick()
        ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
    end)
end
ns.On("BAG_UPDATE_DELAYED", markDirty)
ns.On("UPDATE_INVENTORY_DURABILITY", markDirty)
ns.On("PLAYER_EQUIPMENT_CHANGED", markDirty)

------------------------------------------------------------------------
-- Teilnehmer fuer den naechsten Termin
------------------------------------------------------------------------
local function demoOn() return ns.Demo and ns.Demo.IsActive() end
local function simOn() return ns.Sim and ns.Sim.Active() or false end
-- Raid-Simulator: Stand je Sim-Mitglied aus Haltbarkeit, Feuerwiderstand und Buffs (nur angezeigt, nie gespeichert)
local SIM_CASTER = { MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true }
local function simRole(m)
    if m.role == "TANK" then return "tank" end
    if m.role == "HEALER" then return "heal" end
    return SIM_CASTER[m.class or ""] and "caster" or "melee"
end
local function simRec(m, raid)
    local miss, sev = {}, 0
    local dura = m.dura or -1
    if dura >= 0 and dura < 30 then miss[#miss + 1] = "d" .. dura sev = 2 elseif dura >= 0 and dura < 50 then sev = math.max(sev, 1) end
    local fire = m.fireRes or -1
    if raid == "onyxia" then
        local need = m.role == "TANK" and 150 or 40
        if fire >= 0 and fire < need then miss[#miss + 1] = ("r2:%d:%d"):format(need, fire) sev = math.max(sev, fire < need / 2 and 2 or 1) end
        if not (m.buffs and m.buffs.fireprot) then miss[#miss + 1] = "i13457x2" sev = math.max(sev, 1) end
    end
    if not (m.buffs and m.buffs.flask) and m.role ~= "DAMAGER" then miss[#miss + 1] = "o13511x1" end
    if not m.online then sev = 2 end
    return { light = sev == 0 and "g" or (sev == 1 and "a" or "r"), dura = dura, fire = fire, miss = table.concat(miss, ","),
        ts = ns.now(), role = simRole(m), raid = raid, sim = true }
end
function RP.Participants(ev)
    local out, seen = {}, {}
    if simOn() then
        local inst = ns.Group.Instance()
        local raid = inst and inst.key or "onyxia"
        for _, m in ipairs(ns.Group.Members()) do
            if not seen[m.name] then
                seen[m.name] = true
                local p = { name = m.name, role = simRole(m), class = m.class }
                if m.isMe then
                    local st = RP.MyState()
                    p.rec = { light = st.light, dura = st.dura or -1, fire = st.res[2] or -1, miss = st.miss, ts = ns.now(), role = st.role, raid = st.raid }
                else
                    p.rec = simRec(m, raid)
                end
                p.old = false
                out[#out + 1] = p
            end
        end
        local order = { r = 1, a = 2, g = 3 }
        table.sort(out, function(a, b)
            local oa, ob = order[a.rec.light] or 4, order[b.rec.light] or 4
            if oa ~= ob then return oa < ob end
            return ns.displayName(a.name) < ns.displayName(b.name)
        end)
        return out
    end
    local function add(name, role, class)
        if not name or seen[name] then return end
        seen[name] = true
        out[#out + 1] = { name = name, role = role, class = class }
    end
    if ev and ns.Raid and ns.Raid.Signups then
        local ok, list = pcall(ns.Raid.Signups, ev.id)
        if ok and list then for _, s in ipairs(list) do if s.status == "yes" then add(s.who, s.role, s.class) end end end
    end
    if ns.Group.IsInGroup() then
        local raid = ns.Group.IsInRaid()
        for i = 1, raid and 40 or 5 do
            local u = raid and ("raid" .. i) or (i == 5 and "player" or ("party" .. i))
            if UnitExists(u) then
                local n = ns.fullName(ns.safe(ns.UnitName(u)))
                local _, cls = UnitClass(u)
                add(n, nil, cls)
            end
        end
    end
    add(ns.me(), RP.MyRole(ev))
    local evId = ev and ev.id or ""
    for _, r in ipairs(Store.List(COLL)) do
        if (r.ev == evId and evId ~= "") or (r.demo and demoOn()) then add(r.who, r.role) end
    end
    local now = ns.now()
    for _, p in ipairs(out) do
        local r = Store.Get(COLL, "rp@" .. p.name)
        if r and (r.demo and not demoOn()) then r = nil end
        if ns.isMe(p.name) then
            local st = RP.MyState()
            r = { light = st.light, dura = st.dura or -1, fire = st.res[2] or -1, miss = st.miss, ts = now, role = st.role, raid = st.raid }
        end
        p.rec = r
        p.old = r and (now - (r.ts or r.u or 0)) > 3 * 86400
        p.role = p.role or (r and r.role)
    end
    local order = { r = 1, a = 2, g = 3 }
    table.sort(out, function(a, b)
        local oa = a.rec and (order[a.rec.light] or 4) or 5
        local ob = b.rec and (order[b.rec.light] or 4) or 5
        if oa ~= ob then return oa < ob end
        return ns.displayName(a.name) < ns.displayName(b.name)
    end)
    return out
end

------------------------------------------------------------------------
-- Demo (Wrapper-Muster wie Camp.SeedDemo)
------------------------------------------------------------------------
local DEMO = {
    { "Grukthar", "tank", "g", 92, 168, "" },
    { "Hoknar", "melee", "a", 64, 22, "i13457x2,i13452x1" },
    { "Tavira", "heal", "g", 88, 45, "" },
    { "Zul'mira", "caster", "r", 18, 12, "d18,i13457x3,k16309" },
    { "Mokrash", "melee", "a", 75, 41, "r2:40:31,i9206x2" },
    { "Nakira", "heal", "g", 100, 52, "o13511x1" },
    { "Yenzi", "caster", "a", 81, 30, "i13454x2,r2:40:30" },
    { "Drogbar", "tank", "r", 55, 96, "r2:150:96,g15138" },
}
function RP.SeedDemo()
    local now = ns.now()
    for i, d in ipairs(DEMO) do
        local who = ns.fullName(d[1])
        Store.merge(COLL, { id = "rp@" .. who, demo = true, who = who, role = d[2], light = d[3], dura = d[4], fire = d[5],
            miss = d[6], raid = "onyxia", ev = "", ts = now - i * 900, u = now - i * 900 })
    end
    ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
end
function RP.RemoveDemo()
    local c = ns.db.store[COLL] or {}
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
end

------------------------------------------------------------------------
-- Seite (Optik wie Raid-Check: Reiter mit gleitendem Balken, Kacheln, Ampeln; Bausteine ns.RCUI)
------------------------------------------------------------------------
local LIGHT = { g = C.mint, a = C.amber, r = C.red }
local LIGHT_TEXT = { g = "bereit", a = "fast", r = "fehlt viel" }
local LIGHT_SEV = { g = "ok", a = "warn", r = "bad" }
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SEV_HEX = { [0] = "|cff9a9aa0", [1] = "|cfffac257", [2] = "|cffe64047" }
local ROLE_GLYPH = { tank = "role_tank", heal = "role_heal", melee = "role_dps", caster = "role_dps", dps = "role_dps" }
local ROLE_COL = { tank = C.blue, heal = C.mint, melee = C.red, caster = C.pink, dps = C.red }

local PREP = {
    key = "raidprep", title = "Raid-Vorbereitung", order = 2.762,
    sub = "Was du fuer den naechsten Raid noch brauchst - Widerstaende, Verbrauchsgueter, Haltbarkeit, Schluessel",
    build = function(p)
        local UI = ns.RCUI
        p.view = "team"
        p.seg = UI.Tabs(p, {
            { key = "team", text = L["Teilnehmer"], icon = "groups", color = C.mint, tip = L["Ampel je Teilnehmer fuer den naechsten Termin"] },
            { key = "me", text = L["Meine Checkliste"], icon = "checklist", color = C.amber, tip = L["Was dir selbst noch fehlt"] },
        }, function(k)
            p.view = k
            ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
            UI.Reveal(k == "team" and p.tm or p.me)
        end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.seg:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        p.seg:Select("team")
        p.ev = K.Text(p, 12, C.muted, "RIGHT")
        p.ev:SetPoint("TOPRIGHT", -4, -9)
        p.ev:SetPoint("LEFT", p, "LEFT", (p.seg.natW or 300) + 16, 0)
        -- Profilwahl
        p.profHead = K.Text(p, 10, C.dim)
        p.profHead:SetPoint("TOPLEFT", 0, -48)
        p.profHead:SetText(L["Raid"])
        local items = { { key = "auto", text = L["Automatisch"] } }
        for _, r in ipairs(RP.RAIDS) do items[#items + 1] = { key = r.key, text = L[r.name] } end
        p.prof = K.Segments(p, items, function(k)
            ns.char.rpRaid = (k ~= "auto") and k or nil
            ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
        end, nil, { size = 11, pad = 16 })
        p.prof:SetPoint("LEFT", p.profHead, "RIGHT", 10, 0)
        p.profLbl = K.Text(p, 10, C.dim)
        p.profLbl:SetPoint("LEFT", p.prof, "RIGHT", 12, 0)
        ------------------------------------------------------------ Teilnehmer
        local tm = CreateFrame("Frame", nil, p)
        tm:SetPoint("TOPLEFT", 0, -74) tm:SetPoint("BOTTOMRIGHT")
        p.tm = tm
        tm.tiles, tm.tileList = {}, {}
        for i, d in ipairs({ { "g", "Bereit", C.mint, "checklist" }, { "a", "Fast bereit", C.amber, "stats" }, { "r", "Fehlt viel", C.red, "deaths" }, { "x", "Kein Stand", C.dim, "sync" } }) do
            local t = UI.Tile(tm, d[4], L[d[2]], d[3])
            tm.tiles[d[1]] = t
            tm.tileList[i] = t
        end
        tm.ask = K.Button(tm, L["Staende anfragen"], 150, 26, "ghost", function()
            lastReq = 0
            RP.RequestAll()
            K.Toast(L["Raid-Vorbereitung"], L["Anfrage an die Gilde geschickt."], C.mint)
        end)
        tm.ask:SetPoint("TOPRIGHT", 0, -34)
        -- Raidleitung: Anforderungen je Raid festlegen
        tm.reqBtn = K.Button(tm, L["Anforderungen"], 150, 26, "ghost", function()
            tm.editing = not tm.editing
            ns.RefreshPage("raidprepteam")
        end)
        tm.reqBtn:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Anforderungen festlegen"], L["Was jeder fuer diesen Raid dabei haben muss - gilt fuer die ganze Gilde."] }) end)
        tm.reqBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        tm.reqBtn:SetPoint("TOPRIGHT", -158, 0)
        tm.reqBtn:SetHeight(60)
        K.LockButton(tm.reqBtn, function() return RP.CanEditReq() end, "raidlead")
        local ed = CreateFrame("Frame", nil, tm)
        ed:SetPoint("TOPLEFT", 0, -72)
        ed:SetPoint("BOTTOMRIGHT")
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(ed, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 14) end
        ed:Hide()
        tm.ed = ed
        ed.title = K.Title(ed, 14, C.text)
        ed.title:SetPoint("TOPLEFT", 16, -14)
        ed.hint = K.Text(ed, 10, C.dim)
        ed.hint:SetPoint("LEFT", ed.title, "RIGHT", 10, -1)
        ed.hint:SetText(L["Haken = Pflicht  ·  Mausrad oder +/- = Menge  ·  gilt fuer die ganze Gilde"])
        -- Feuer-Widerstand
        local function stepper(parent, label, x, y, get, set, step, max)
            local w = CreateFrame("Frame", nil, parent)
            w:SetSize(170, 24)
            w:SetPoint("TOPLEFT", x, y)
            w.l = K.Text(w, 11, C.muted)
            w.l:SetPoint("LEFT", 0, 0)
            w.l:SetText(label)
            w.v = K.Title(w, 12, C.text, "CENTER")
            w.v:SetPoint("RIGHT", -24, 0)
            w.v:SetWidth(36)
            local function bump(d)
                set(math.max(0, math.min(max, get() + d * ((IsShiftKeyDown and IsShiftKeyDown()) and step * 5 or step))))
                w.v:SetText(get())
            end
            w.minus = K.Button(w, "-", 20, 20, "ghost", function() bump(-1) end)
            w.minus:SetPoint("RIGHT", w.v, "LEFT", -2, 0)
            w.plus = K.Button(w, "+", 20, 20, "ghost", function() bump(1) end)
            w.plus:SetPoint("RIGHT", 0, 0)
            w:EnableMouseWheel(true)
            w:SetScript("OnMouseWheel", function(_, d) bump(d) end)
            function w:Sync() self.v:SetText(get()) end
            return w
        end
        ed.draft = {}
        ed.fT = stepper(ed, L["Feuer-Wid. Tank"], 16, -44, function() return ed.draft.fireT or 0 end, function(v) ed.draft.fireT = v end, 5, 315)
        ed.fO = stepper(ed, L["Feuer-Wid. andere"], 200, -44, function() return ed.draft.fireO or 0 end, function(v) ed.draft.fireO = v end, 5, 315)
        -- Liste der Verbrauchsgueter (alle Rollen)
        ed.rows = {}
        ed.list = CreateFrame("Frame", nil, ed)
        ed.list:SetPoint("TOPLEFT", 16, -80)
        ed.list:SetPoint("BOTTOMRIGHT", -16, 84)
        ed.list:SetClipsChildren(true)
        ed.list:EnableMouseWheel(true)
        ed.off = 0
        ed.list:SetScript("OnMouseWheel", function(_, d) ed.off = math.max(0, ed.off - d * 2) ed:Draw() end)
        local ROLE_SHORT = { all = "alle", tank = "Tank", heal = "Heiler", melee = "Nahkampf", caster = "Zauber-DD" }
        local function row(i)
            local r = ed.rows[i]
            if r then return r end
            r = CreateFrame("Frame", nil, ed.list)
            r:SetHeight(26)
            r.chk = K.Toggle(r, "", function() return r.item and not ed.draft.off[r.item.id] end, function(v)
                if r.item then ed.draft.off[r.item.id] = (not v) or nil end
                ed:Draw()
            end)
            r.chk:SetPoint("LEFT", 0, 0)
            r.chk:SetWidth(40)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", 44, 0)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 68, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -230, 0)
            r.name:SetWordWrap(false)
            r.role = K.Text(r, 10, C.muted, "RIGHT")
            r.role:SetPoint("RIGHT", r, "RIGHT", -150, 0)
            r.role:SetWidth(76)
            r.n = stepper(r, "", 0, 0, function() return r.item and (ed.draft.n[r.item.id] or r.item.n) or 0 end,
                function(v) if r.item then ed.draft.n[r.item.id] = v end end, 1, 99)
            r.n:ClearAllPoints()
            r.n:SetPoint("RIGHT", r, "RIGHT", -28, 0)
            r.n:SetWidth(96)
            r.del = K.Button(r, "x", 20, 20, "ghost", function()
                if r.item and r.item.added then
                    for k, a in ipairs(ed.draft.add) do if a.id == r.item.id and a.role == r.item.role then table.remove(ed.draft.add, k) break end end
                    ed:Draw()
                end
            end)
            r.del:SetPoint("RIGHT", 0, 0)
            ed.rows[i] = r
            return r
        end
        function ed:Items()
            local prof = self.prof
            local out, seen = {}, {}
            local function addList(list, role)
                for _, x in ipairs(list or {}) do
                    local id = x.ids[1]
                    local k = id .. role
                    if not seen[id] then seen[id] = true out[#out + 1] = { id = id, n = x.n, label = x.label, role = role, opt = x.opt } end
                end
            end
            addList(BASE.all, "all")
            if prof then addList(prof.cons.all, "all") end
            for _, rk in ipairs({ "tank", "heal", "melee", "caster" }) do
                addList(BASE[rk], rk)
                if prof then addList(prof.cons[rk], rk) end
            end
            for _, a in ipairs(self.draft.add) do out[#out + 1] = { id = a.id, n = a.n, label = itemLabel(a.id), role = a.role, added = true } end
            return out
        end
        function ed:Draw()
            local items = self:Items()
            local vis = math.max(3, math.floor(((self.list:GetHeight() or 240)) / 28))
            self.off = math.max(0, math.min(self.off, math.max(0, #items - vis)))
            for _, r in ipairs(self.rows) do r:Hide() end
            for i = 1, math.min(vis, #items - self.off) do
                local it = items[i + self.off]
                local r = row(i)
                r.item = it
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(i - 1) * 28)
                r:SetPoint("RIGHT", self.list, "RIGHT", 0, 0)
                r.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or 134400)
                local on = not self.draft.off[it.id]
                r.name:SetText((on and "" or "|cff666666") .. L[it.label] .. (it.opt and ("  |cff888888" .. L["optional"] .. "|r") or "") .. (it.added and ("  |cffe8b44a" .. L["von der Leitung"] .. "|r") or "") .. (on and "" or "|r"))
                r.role:SetText(L[ROLE_SHORT[it.role] or it.role])
                r.chk:Refresh()
                r.n:Sync()
                r.n:SetAlpha(on and 1 or 0.35)
                r.del:SetShown(it.added and true or false)
                r:Show()
            end
            self.more = #items > vis
        end
        -- Item hinzufuegen (Shift-Klick) + Rolle
        ed.addBox = K.Input(ed, 220, L["Item per Shift-Klick hinzufuegen ..."])
        ed.addBox:SetPoint("BOTTOMLEFT", 16, 48)
        if hooksecurefunc and ChatEdit_InsertLink then
            hooksecurefunc("ChatEdit_InsertLink", function(link) if ed.addBox:HasFocus() and link then ed.addBox:SetText(link) end end)
        end
        ed.addRole = K.Segments(ed, { { key = "all", text = L["alle"] }, { key = "tank", text = L["Tank"] }, { key = "heal", text = L["Heiler"] },
            { key = "melee", text = L["Nahkampf"] }, { key = "caster", text = L["Zauber-DD"] } }, function() end, nil, { size = 11, pad = 10 })
        ed.addRole:SetPoint("LEFT", ed.addBox, "RIGHT", 8, 0)
        ed.addBtn = K.Button(ed, L["Hinzufuegen"], 100, 24, "ghost", function()
            local id = ns.itemID(ed.addBox:GetText())
            if not id then K.Toast(L["Anforderungen"], L["Item per Shift-Klick einfuegen."], C.amber) return end
            table.insert(ed.draft.add, { id = id, n = 1, role = ed.addRole.value or "all" })
            ed.addBox:SetText("")
            ed:Draw()
        end)
        ed.addBtn:SetPoint("BOTTOMRIGHT", -16, 48)
        ed.save = K.Button(ed, L["Speichern"], 120, 26, "primary", function()
            local d = ed.draft
            local off, nn, add = {}, {}, {}
            for id in pairs(d.off) do off[#off + 1] = id end
            for id, n in pairs(d.n) do nn[#nn + 1] = id .. ":" .. n end
            for _, a in ipairs(d.add) do add[#add + 1] = a.id .. ":" .. (d.n[a.id] or a.n) .. ":" .. a.role end
            Store.Put("rpreq", { id = "req-" .. ed.prof.key, fireT = d.fireT or 0, fireO = d.fireO or 0,
                off = table.concat(off, ","), n = table.concat(nn, ","), add = table.concat(add, ",") })
            K.Toast(L["Anforderungen gespeichert"], L[ed.prof.name], C.mint)
            tm.editing = false
            ns.RefreshPage("raidprepteam") ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
        end)
        ed.save:SetPoint("BOTTOMRIGHT", -16, 12)
        ed.reset = K.Button(ed, L["Standard"], 100, 26, "ghost", function()
            if RP.Req(ed.prof.key) then Store.Delete("rpreq", "req-" .. ed.prof.key) end
            ed:Load(ed.prof)
        end)
        ed.reset:SetPoint("RIGHT", ed.save, "LEFT", -8, 0)
        ed.cancel = K.Button(ed, L["Abbrechen"], 100, 26, "ghost", function() tm.editing = false ns.RefreshPage("raidprepteam") end)
        ed.cancel:SetPoint("RIGHT", ed.reset, "LEFT", -8, 0)
        function ed:Load(prof)
            self.prof = prof
            local rq = RP.Req(prof.key)
            local fire = prof.res[2] or { tank = 0, other = 0 }
            self.draft = { fireT = rq and rq.fireT or fire.tank, fireO = rq and rq.fireO or fire.other,
                off = rq and parseSet(rq.off) or {}, n = rq and parseN(rq.n) or {}, add = rq and parseAdd(rq.add) or {} }
            self.title:SetText((L["Anforderungen: %s"]):format(L[prof.name]))
            self.fT:Sync() self.fO:Sync()
            self.off = 0
            self:Draw()
        end
        tm.share = K.Button(tm, L["Meinen Stand teilen"], 150, 26, "ghost", function()
            if RP.Share(true) then K.Toast(L["Raid-Vorbereitung"], L["Dein Stand wurde geteilt."], C.mint) end
            ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
        end)
        tm.share:SetPoint("TOPRIGHT", 0, 0)
        local function layout()
            UI.LayoutTiles(tm.tileList, 0, 0, (tm:GetWidth() or 770) - 162 - (tm.reqBtn and 158 or 0), 8)
        end
        tm:SetScript("OnSizeChanged", layout)
        layout()
        -- Kopf
        tm.head = CreateFrame("Frame", nil, tm)
        tm.head:SetPoint("TOPLEFT", 0, -72)
        tm.head:SetPoint("RIGHT", tm, "RIGHT", -8, 0)
        tm.head:SetHeight(18)
        local heads = { { "Name", 54 }, { "Haltbar", 230 }, { "Feuer-Wid.", 320 }, { "Fehlt", 380 } }
        for _, h in ipairs(heads) do
            local t = K.Text(tm.head, 10, C.dim) t:SetPoint("LEFT", h[2], 0) t:SetText(L[h[1]])
        end
        local ht = K.Text(tm.head, 10, C.dim, "RIGHT") ht:SetPoint("RIGHT", -8, 0) ht:SetText(L["Stand"])
        local hl = tm.head:CreateTexture(nil, "ARTWORK")
        hl:SetPoint("BOTTOMLEFT") hl:SetPoint("BOTTOMRIGHT")
        hl:SetHeight(1)
        hl:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        tm.list = K.List(tm, 32, function(l)
            local r = K.Row(l)
            r.bar = r:CreateTexture(nil, "ARTWORK")
            r.bar:SetPoint("TOPLEFT", 0, -4) r.bar:SetPoint("BOTTOMLEFT", 0, 4)
            r.bar:SetWidth(2)
            r.light = UI.Light(r, 11)
            r.light:SetPoint("LEFT", 2, 0)
            r.light:SetScript("OnEnter", function(self) local row = self:GetParent() local f = row:GetScript("OnEnter") if f then f(row) end end)
            r.light:SetScript("OnClick", function(self) local row = self:GetParent() local f = row:GetScript("OnEnter") if f then f(row) end end)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(20, 20)
            r.cls:SetPoint("LEFT", 28, 0)
            r:Col("name", 54, 165, 13)
            r.cols.name:ClearAllPoints()
            r.cols.name:SetPoint("TOPLEFT", 54, -3)
            r.roleIc = K.Glyph(r, 10, ns.MEDIA .. "icons\\role_dps", C.dim)
            r.roleIc:SetPoint("TOPLEFT", 54, -19)
            r.role = K.Text(r, 10, C.muted)
            r.role:SetPoint("LEFT", r.roleIc, "RIGHT", 4, 0)
            r.duraBg = r:CreateTexture(nil, "ARTWORK")
            r.duraBg:SetPoint("LEFT", 230, -7)
            r.duraBg:SetSize(60, 3)
            r.duraBg:SetColorTexture(1, 1, 1, 0.07)
            r.duraFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.duraFill:SetPoint("LEFT", r.duraBg, "LEFT")
            r.duraFill:SetHeight(3)
            r:Col("dura", 230, 60, 11)
            r.cols.dura:ClearAllPoints()
            r.cols.dura:SetPoint("LEFT", 230, 4)
            r:Col("fire", 320, 55, 11)
            r:Col("miss", 380, 300, 11)
            r.cols.miss:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            r:Col("ts", 0, 86, 10, C.dim, "RIGHT")
            r.cols.ts:ClearAllPoints()
            r.cols.ts:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not (e and e.rec) then return end
                local lines = { ns.displayName(e.name) }
                for _, m in ipairs(RP.FormatMiss(e.rec.miss, true)) do lines[#lines + 1] = SEV_HEX[m.sev] .. m.text .. "|r" end
                if #lines == 1 then lines[2] = L["Alles da."] end
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            local rec = e.rec
            local c = rec and LIGHT[rec.light] or C.dim
            r.light:SetState(rec and (LIGHT_SEV[rec.light] or "none") or "none", nil)
            r.light:SetAlpha(e.old and 0.45 or 1)
            r.bar:SetColorTexture(c[1], c[2], c[3], 0)
            local rm = ns.Radar and ns.Radar.byName and ns.Radar.byName[e.name]
            UI.ClassIcon(r.cls, e.class or (rm and rm.class))
            r.cols.name:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(e.name) or ns.displayName(e.name))
            local rk = lower(e.role)
            r.role:SetText(L[ROLE_TEXT[rk] or (rk == "dps" and "Schaden") or "-"])
            local rc = ROLE_COL[rk] or C.dim
            r.roleIc:SetTexture(ns.MEDIA .. "icons\\" .. (ROLE_GLYPH[rk] or "role_dps"))
            r.roleIc:SetVertexColor(rc[1], rc[2], rc[3])
            r.roleIc:SetShown(ROLE_GLYPH[rk] ~= nil)
            if not rec then
                r.cols.dura:SetText("|cff555555-|r") r.cols.fire:SetText("|cff555555-|r")
                r.duraFill:Hide()
                r.cols.miss:SetText("|cff777777" .. L["kein Stand (ohne Oasis oder noch nicht geteilt)"] .. "|r")
                r.cols.ts:SetText("")
                return
            end
            local d = tonumber(rec.dura) or -1
            local dc = d < 30 and C.red or d < 70 and C.amber or C.mint
            r.cols.dura:SetText(d < 0 and "|cff555555?|r" or (K.hex(dc) .. d .. "%|r"))
            r.duraFill:SetShown(d >= 0)
            if d >= 0 then
                r.duraFill:SetWidth(math.max(1, 60 * math.min(100, d) / 100))
                r.duraFill:SetColorTexture(dc[1], dc[2], dc[3], 1)
            end
            local f = tonumber(rec.fire) or -1
            r.cols.fire:SetText(f < 0 and "|cff555555-|r" or tostring(f))
            local ms = RP.FormatMiss(rec.miss, false)
            local parts = {}
            for _, m in ipairs(ms) do parts[#parts + 1] = SEV_HEX[m.sev] .. m.text:gsub("^" .. L["fehlt: "], "") .. "|r" end
            r.cols.miss:SetText(#parts > 0 and table.concat(parts, ", ") or ("|cff66db9e" .. L[LIGHT_TEXT.g] .. "|r"))
            r.cols.ts:SetText(e.old and ("|cffff8a3d" .. ns.ago(rec.ts or rec.u) .. "|r") or ns.ago(rec.ts or rec.u))
        end)
        tm.list:SetPoint("TOPLEFT", 0, -92)
        tm.list:SetPoint("BOTTOMRIGHT")
        tm.list.empty:SetText("")
        tm.empty = UI.Empty(tm, "raid", C.mint)
        tm.empty:SetPoint("TOP", tm.list, "TOP", 0, -24)
        ------------------------------------------------------------ Meine Checkliste
        local me = CreateFrame("Frame", nil, p)
        me:SetPoint("TOPLEFT", 0, -74) me:SetPoint("BOTTOMRIGHT")
        p.me = me
        me.light = UI.Card(me, C.mint)
        me.light:SetPoint("TOPLEFT", 0, 0)
        me.light:SetSize(250, 214)
        me.light.halo = me.light:CreateTexture(nil, "BORDER", nil, 2)
        me.light.halo:SetTexture(UI.EMBER)
        me.light.halo:SetBlendMode("ADD")
        me.light.halo:SetSize(120, 120)
        me.light.halo:SetPoint("TOP", 0, 0)
        me.light.halo:SetAlpha(0)
        me.light.halo:Hide()
        me.light.dot = me.light:CreateTexture(nil, "ARTWORK")
        me.light.dot:SetTexture(DOT)
        me.light.dot:SetSize(40, 40)
        me.light.dot:SetPoint("TOP", 0, -34)
        me.light.shine = me.light:CreateTexture(nil, "OVERLAY")
        me.light.shine:SetTexture(DOT)
        me.light.shine:SetSize(18, 18)
        me.light.shine:SetPoint("CENTER", me.light.dot, "CENTER", -10, 10)
        me.light.shine:SetVertexColor(1, 1, 1, 0)
        me.light.shine:Hide()
        me.light.title = K.Title(me.light, 18, C.text, "CENTER")
        me.light.title:SetPoint("TOP", me.light.dot, "BOTTOM", 0, -12)
        me.light.title:SetWidth(230)
        me.light.sub = K.Text(me.light, 11, C.muted, "CENTER")
        me.light.sub:SetPoint("TOP", me.light.title, "BOTTOM", 0, -4)
        me.light.sub:SetWidth(220)
        me.light.sub:SetWordWrap(true)
        me.light.count = K.Text(me.light, 11, C.dim, "CENTER")
        me.light.count:SetPoint("TOP", me.light.sub, "BOTTOM", 0, -4)
        me.light.count:SetWidth(220)
        me.btn = K.Button(me.light, L["Meinen Stand teilen"], 218, 26, "ghost", function()
            if RP.Share(true) then K.Toast(L["Raid-Vorbereitung"], L["Dein Stand wurde geteilt."], C.mint) end
        end)
        me.btn:SetPoint("BOTTOM", 0, 12)
        me.roleLbl = K.Text(me, 10, C.dim)
        me.roleLbl:SetPoint("TOPLEFT", 0, -226)
        me.roleLbl:SetText(L["Meine Rolle:"])
        local ritems = { { key = "auto", text = L["Automatisch"] } }
        for _, r in ipairs(ROLES) do ritems[#ritems + 1] = { key = r.key, text = L[r.text] } end
        me.role = K.Segments(me, ritems, function(k)
            ns.char.rpRole = (k ~= "auto") and k or nil
            ns.RefreshPage("raidprep") ns.RefreshPage("raidprepteam")
        end, nil, { size = 11, pad = 10 })
        me.role:SetPoint("TOPLEFT", 0, -242)
        me.combat = K.Text(me, 12, C.amber)
        me.combat:SetPoint("TOPLEFT", 0, -276)
        me.combat:SetWidth(250)
        me.combat:SetWordWrap(true)
        me.listHead = K.GameHead(me, L["Meine Checkliste"], C.amber)
        if me.listHead.mark then me.listHead.mark:Hide() end
        me.listHead:SetPoint("TOPLEFT", 266, 0)
        me.listHead:SetPoint("RIGHT", me, "RIGHT", 0, 0)
        me.list = K.List(me, 30, function(l)
            local r = K.Row(l)
            r.light = UI.Light(r, 9)
            r.light:SetPoint("LEFT", 2, 0)
            r.light:EnableMouse(false)
            r:Col("text", 30, 480, 12)
            r.cols.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            return r
        end, function(r, e)
            r.light:SetState(e.ok and "ok" or e.sev == 0 and "none" or e.sev == 1 and "warn" or "bad")
            local tx = tostring(e.text or ""):gsub("^" .. L["fehlt: "], "|cff888888" .. L["fehlt: "] .. "|r")
            r.cols.text:SetText((e.ok and "|cff8a8a90" or (e.sev == 2 and "|cffe8e8ea" or "|cffcfcfd4")) .. tx .. "|r")
        end)
        me.list:SetPoint("TOPLEFT", 266, -26)
        me.list:SetPoint("BOTTOMRIGHT")
        me.list.empty:SetText(L["Nichts zu pruefen."])
        p:SetScript("OnShow", function() RP.RequestAll() end)
        RP.RequestAll()
    end,
    refresh = function(p)
        p.seg:Select(p.view)
        p.tm:SetShown(p.view == "team")
        p.me:SetShown(p.view == "me")
        local tmE = p.tm
        if tmE.ed then
            local editing = tmE.editing and RP.CanEditReq() and p.view == "team"
            if editing and (not tmE.ed:IsShown()) then tmE.ed:Load(select(1, RP.CurrentProfile(RP.NextEvent()))) end
            tmE.ed:SetShown(editing and true or false)
            tmE.list:SetShown(not editing)
            if tmE.head then tmE.head:SetShown(not editing) end
            if tmE.empty and editing then tmE.empty:Hide() end
            tmE.reqBtn:SetLabel(editing and L["Fertig"] or L["Anforderungen"])
            K.UpdateLockButton(tmE.reqBtn)
            if editing then return end
        end
        local ev = RP.NextEvent()
        local prof, manual = RP.CurrentProfile(ev)
        p.prof:Select(manual and prof.key or "auto")
        p.profLbl:SetText(manual and "" or (L["Profil: %s"]):format(L[prof.name]))
        if ev then
            p.ev:SetText(("|cffe8e8ea%s|r  %s%s"):format(ev.title or "?", ns.fmtWhen(ev.ts or 0), (ev.inst or "") ~= "" and ("  ·  " .. ev.inst) or ""))
        else
            p.ev:SetText(L["Kein kommender Termin"])
        end
        if p.view == "team" then
            local list = RP.Participants(ev)
            if not ev and not ns.Group.IsInGroup() and not demoOn() then list = {} end
            p.tm.list:SetData(list)
            local n = { g = 0, a = 0, r = 0, x = 0 }
            for _, e in ipairs(list) do local k = e.rec and e.rec.light or "x" n[k] = (n[k] or 0) + 1 end
            for k, t in pairs(p.tm.tiles) do
                local v = n[k] or 0
                t:Set(v, #list > 0 and ("/ " .. #list) or "", #list > 0 and v / #list or 0, (v > 0 and k ~= "x") and t.color or C.text)
                t:SetShown(#list > 0)
            end
            p.tm.head:SetShown(#list > 0)
            if #list == 0 then
                p.tm.empty:Set(L["Kein kommender Raidtermin und keine Gruppe. Lege im Bereich Raids einen Termin an."],
                    L["Zu den Raids"], function() ns.ShowPage("raid") end)
                p.tm.empty:Show()
            else
                p.tm.empty:Hide()
            end
        else
            local me = p.me
            me.role:Select(ns.char.rpRole or "auto")
            local fight = ns.inCombat()
            me.combat:SetText(fight and L["Im Kampf werden Taschen und Widerstaende nicht neu gelesen."] or "")
            local st = me.last
            if not fight or not st then st = RP.MyState(prof, nil) me.last = st end
            local c = LIGHT[st.light]
            me.light.dot:SetVertexColor(c[1], c[2], c[3])
            me.light.halo:SetVertexColor(c[1], c[2], c[3])
            me.light:SetColor(c)
            me.light.title:SetText(L[st.light == "g" and "Alles bereit" or st.light == "a" and "Fast bereit" or "Es fehlt etwas"])
            me.light.sub:SetText((L["%s als %s"]):format(L[prof.name], L[ROLE_TEXT[st.role] or "?"]))
            -- fehlende zuerst
            local lines, open = {}, 0
            for _, l in ipairs(st.lines) do if not l.ok and l.sev > 0 then lines[#lines + 1] = l open = open + 1 end end
            for _, l in ipairs(st.lines) do if not l.ok and l.sev == 0 then lines[#lines + 1] = l end end
            for _, l in ipairs(st.lines) do if l.ok then lines[#lines + 1] = l end end
            me.light.count:SetText(open > 0 and (L["%d Punkte offen"]):format(open) or L["Alles erledigt"])
            if me.lastLight ~= st.light and ns.RCUI.animOn() then
                me.lastLight = st.light
                K.Tween(me.light.dot, 0.5, function(q)
                    local k = 1 + 0.25 * math.sin(q * math.pi)
                    me.light.dot:SetSize(40 * k, 40 * k)
                end, function() me.light.dot:SetSize(40, 40) end)
            end
            me.list:SetData(lines)
            me.btn:SetShown(IsInGuild())
        end
    end,
}
-- zwei Seiten aus einem Bauplan: eigene Checkliste (Raids) und Kader der Angemeldeten (Raidleitung)
local function variant(key, title, sub, order, view)
    local d = {}
    for k, v in pairs(PREP) do d[k] = v end
    d.key, d.title, d.sub, d.order = key, title, sub, order
    d.build = function(p)
        PREP.build(p)
        p.view = view
        p.seg:Hide()
        p.ev:ClearAllPoints()
        p.ev:SetPoint("TOPRIGHT", -4, -9)
        p.ev:SetPoint("LEFT", p, "LEFT", 0, 0)
        p.ev:SetJustifyH("LEFT")
    end
    return d
end
ns.RegisterPage(variant("raidprep", "Raid-Vorbereitung", "Was du fuer den naechsten Raid noch brauchst - Widerstaende, Verbrauchsgueter, Haltbarkeit, Schluessel", 2.762, "me"))
ns.RegisterPage(variant("raidprepteam", "Kader-Check", "Wie gut sind die Angemeldeten vorbereitet - und was die Raidleitung je Raid verlangt", 2.7621, "team"))
if ns.ICONS then ns.ICONS.raidprepteam = ns.MEDIA .. "icons\\\\checklist" end

------------------------------------------------------------------------
-- /oa probe vorbereitung
------------------------------------------------------------------------
ns.Probes.vorbereitung = function()
    ns.print(L["Probe Raid-Vorbereitung:"])
    ns.print("  UnitResistance: " .. tostring(UnitResistance ~= nil))
    for school = 1, 6 do
        local ok, a, b, c2 = pcall(UnitResistance or error, "player", school)
        ns.print(("    %d %s: ok=%s base=%s total=%s bonus=%s"):format(school, RES_NAME[school], tostring(ok), tostring(ns.safe(a)), tostring(ns.safe(b)), tostring(ns.safe(c2))))
    end
    ns.print("  C_Item.GetItemCount: " .. tostring(C_Item and C_Item.GetItemCount ~= nil) .. "  13457=" .. count(13457, false) .. " (Bank: " .. count(13457, true) .. ")")
    ns.print("  IsEquippedItem: " .. tostring((C_Item and C_Item.IsEquippedItem) ~= nil or IsEquippedItem ~= nil) .. "  15138=" .. tostring(equipped(15138)))
    local low, avg = durability()
    ns.print("  Haltbarkeit: min=" .. tostring(low) .. " avg=" .. tostring(avg))
    ns.print("  ns.Lockouts: " .. tostring(ns.Lockouts ~= nil))
    if type(ns.Lockouts) == "table" then
        local fns = {}
        for k, v in pairs(ns.Lockouts) do if type(v) == "function" then fns[#fns + 1] = k end end
        table.sort(fns)
        ns.print("    Funktionen: " .. table.concat(fns, ", "))
    end
    local ev = RP.NextEvent()
    ns.print("  Naechster Termin: " .. tostring(ev and ev.title) .. "  Profil: " .. tostring((RP.CurrentProfile(ev) or {}).key) .. "  Rolle: " .. RP.MyRole(ev))
    local st = RP.MyState()
    ns.print("  Ampel: " .. st.light .. "  Kodiert: " .. (st.miss ~= "" and st.miss or "-"))
end
ns.Probes.prep = ns.Probes.vorbereitung

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    -- eigene Aufbewahrung (Sammlung steht nicht in Comm.lua RETENTION): 14 Tage
    local c = Store.coll(COLL)
    local now = ns.now()
    for id, r in pairs(c) do if not r.demo and now - (r.u or 0) > 14 * 86400 then c[id] = nil end end
    ns.After(20, tick)
    ns.Every(60, tick)
    local D = ns.Demo
    if D and not D.rpHooked then
        D.rpHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) RP.SeedDemo() end
        D.Remove = function(...) remove(...) RP.RemoveDemo() end
        if D.IsActive() then ns.After(3, RP.SeedDemo) end
    end
end)
end)

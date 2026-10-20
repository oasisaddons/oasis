-- Oasis: raid simulator (developer version only, ns.IsDev())
--  * /oa raidsim [10|20|40] [onyxia|hyjal|barrow]  |  /oa raidsim aus  (also: kampf, beute, bereit)
--  * Right-click on the demo toggle at the top of the window: simulator menu
--  * ns.Group: central group queries for the raid modules. Without the simulator the values come 1:1 from the
--    Blizzard APIs, with the simulator from a made-up raid (me = raid leader in group 1).
--    NO Blizzard functions are overwritten (taint) - only Oasis's own functions are redirected.
--  * During the simulation nothing goes to guild/group: chat and addon messages of the raid modules
--    only land in your own chat window, records carry "demo-sim-" IDs and disappear on stop.
local ADDON, ns = ...
local L = ns.L
local Store = ns.Store

local Sim = {}
ns.Sim = Sim
local G = {}
ns.Group = G

local SIM_PREFIX = "demo-sim-"
Sim.PREFIX = SIM_PREFIX

local INST = {
    onyxia = { key = "onyxia", name = "Onyxia's Lair", mapID = 248, board = "m248", bosses = { "Onyxia" } },
    hyjal = { key = "hyjal", name = "Hyjal", mapID = 329, board = "m329", bosses = { "Rage Winterchill", "Anetheron", "Kaz'rogal", "Azgalor", "Archimonde" } },
    barrow = { key = "barrow", name = "Barrow Deeps", board = "barrow", bosses = { "Grabwächter Moradin", "Die Knochenhexe", "Varrok der Verschlinger" } },
}
local INST_ALIAS = { ony = "onyxia", onyxia = "onyxia", onyxias = "onyxia", hyjal = "hyjal", hyj = "hyjal", barrow = "barrow", deeps = "barrow" }
local LOOT = {
    onyxia = {
        "|cffa335ee|Hitem:17068::::::::|h[Deathbringer]|h|r", "|cffa335ee|Hitem:17075::::::::|h[Vis'kag the Bloodletter]|h|r",
        "|cffa335ee|Hitem:18404::::::::|h[Onyxia Tooth Pendant]|h|r", "|cffa335ee|Hitem:18813::::::::|h[Ring of Binding]|h|r",
        "|cffa335ee|Hitem:18205::::::::|h[Eskhandar's Collar]|h|r", "|cffa335ee|Hitem:17078::::::::|h[Sapphiron Drape]|h|r",
    },
    hyjal = {
        "|cffa335ee|Hitem:17063::::::::|h[Band of Accuria]|h|r", "|cffa335ee|Hitem:18203::::::::|h[Eskhandar's Right Claw]|h|r",
        "|cffa335ee|Hitem:17105::::::::|h[Aurastone Hammer]|h|r", "|cffa335ee|Hitem:16800::::::::|h[Arcanist Boots]|h|r",
    },
    barrow = {
        "|cff0070dd|Hitem:13963::::::::|h[Voone's Vice Grips]|h|r", "|cffa335ee|Hitem:18823::::::::|h[Aged Core Leather Gloves]|h|r",
        "|cff0070dd|Hitem:13955::::::::|h[Stoneform Shoulders]|h|r", "|cffa335ee|Hitem:16800::::::::|h[Arcanist Boots]|h|r",
    },
}
-- Roles per class (order = class mix in the raid)
local TANKS = { "WARRIOR", "WARRIOR", "DRUID", "WARRIOR" }
local HEALS = { "PRIEST", "SHAMAN", "PRIEST", "DRUID", "SHAMAN", "PRIEST" }
local DPS = { "ROGUE", "MAGE", "WARLOCK", "HUNTER", "WARRIOR", "MAGE", "ROGUE", "SHAMAN", "HUNTER", "WARLOCK", "PRIEST", "DRUID", "MAGE" }
local COMP = { [10] = { 2, 3 }, [20] = { 3, 5 }, [40] = { 4, 10 } }
local EXTRA = { "Throkk", "Ulgra", "Mazrok", "Kezzik", "Rasha", "Gorvash", "Tazluk", "Shenna", "Borgun", "Vashka", "Draknor", "Zulgai",
    "Mog'ra", "Trezza", "Hurak", "Oshma", "Kaldor", "Nyxa", "Rokhan", "Grizza", "Ulthar", "Feyka", "Sornak", "Bazrah", "Kruuk", "Lashi",
    "Torvek", "Ixira", "Gundar", "Muzga", "Rekka", "Thal'zo", "Varga", "Okrim", "Selun", "Durza", "Kragg", "Yazmi", "Bolgar", "Hesha" }
local SLOTS = { "Cloak", "Chest", "Weapon", "Boots", "Bracers", "Gloves" }

local S = nil          -- running simulation (in memory only)
local fightN = 0

local function rnd(a, b) return math.random(a, b) end
local function chance(p) return math.random() < p end
local function now() return GetTime() end
local function console(what, msg)
    ns.print("|cff8a8a90[" .. L["Raid sim"] .. "]|r " .. tostring(what) .. (msg and (": " .. tostring(msg)) or ""))
end

function Sim.Active() return S ~= nil and ns.IsDev() end
function Sim.State() return S end
function Sim.Instances() return INST end

------------------------------------------------------------------------
-- Roster
------------------------------------------------------------------------
local function namePool()
    local out = {}
    if ns.Demo and ns.Demo.People then
        local ok, list = pcall(ns.Demo.People)
        if ok and type(list) == "table" then for _, p in ipairs(list) do out[#out + 1] = { name = p.name, class = p.class } end end
    end
    for _, n in ipairs(EXTRA) do out[#out + 1] = { name = ns.fullName(n) } end
    return out
end
local function roleOfClass(cls)
    if cls == "WARRIOR" then return "TANK" end
    if cls == "PRIEST" or cls == "SHAMAN" or cls == "PALADIN" or cls == "DRUID" then return "HEALER" end
    return "DAMAGER"
end

local function has(m, key) return m.buffs[key] ~= nil end
local function giveBuff(m, key, minS, maxS)
    m.buffs[key] = now() + rnd(minS, maxS)
end
local function rollBuffs(m, cls)
    m.buffs = {}
    local inOny = S.inst.key == "onyxia"
    if cls.PRIEST then
        if chance(0.85) then giveBuff(m, "fort", 240, 3600) end
        if chance(0.5) then giveBuff(m, "spirit", 600, 3600) end
        if inOny and chance(0.3) then giveBuff(m, "shadow", 600, 3600) end
    end
    if cls.DRUID and chance(0.85) then giveBuff(m, "motw", 200, 1800) end
    if cls.MAGE and chance(0.75) then giveBuff(m, "int", 300, 1800) end
    if cls.SHAMAN and chance(0.6) then giveBuff(m, "totem", 60, 120) end
    if chance(0.35) then giveBuff(m, "flask", 1800, 7200) end
    if chance(0.65) then giveBuff(m, "elixir", 120, 3600) end
    if chance(0.6) then giveBuff(m, "food", 150, 900) end
    if chance(0.15) then giveBuff(m, "world", 1800, 7200) end
    if inOny and chance(0.55) then giveBuff(m, "fireprot", 300, 3600) end
end

local function build(size, inst)
    local pool, used = namePool(), {}
    local me = ns.me()
    used[me] = true
    local _, myCls = UnitClass("player")
    myCls = myCls or "WARRIOR"
    local comp = COMP[size]
    local need = {}
    local myRole = roleOfClass(myCls)
    local t, h = comp[1], comp[2]
    for i = 1, t do need[#need + 1] = { role = "TANK", class = TANKS[(i - 1) % #TANKS + 1] } end
    for i = 1, h do need[#need + 1] = { role = "HEALER", class = HEALS[(i - 1) % #HEALS + 1] } end
    for i = 1, size - t - h do need[#need + 1] = { role = "DAMAGER", class = DPS[(i - 1) % #DPS + 1] } end
    -- my slot replaces a matching one
    for i, n in ipairs(need) do if n.role == myRole then table.remove(need, i) break end end
    local function take(cls)
        for _, p in ipairs(pool) do if p.class == cls and not used[p.name] then used[p.name] = true return p.name end end
        for _, p in ipairs(pool) do if not p.class and not used[p.name] then used[p.name] = true return p.name end end
        for _, p in ipairs(pool) do if not used[p.name] then used[p.name] = true return p.name end end
        return ns.fullName("Sim" .. rnd(100, 999))
    end
    local list = { { name = me, class = myCls, role = myRole, isMe = true } }
    for _, n in ipairs(need) do list[#list + 1] = { name = take(n.class), class = n.class, role = n.role } end
    -- Groups: me in 1, tanks and healers spread out, fill up the rest
    local groups = size / 5
    local free = {}
    for g = 1, groups do free[g] = 5 end
    list[1].group, free[1] = 1, 4
    local rr = 1
    local function place(m)
        for step = 0, groups - 1 do
            local g = ((rr - 1 + step) % groups) + 1
            if free[g] > 0 then m.group = g free[g] = free[g] - 1 rr = g % groups + 1 return end
        end
    end
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        for i = 2, #list do if list[i].role == role then place(list[i]) end end
    end
    local cls = {}
    for _, m in ipairs(list) do cls[m.class] = true end
    local nAssist = 0
    for i, m in ipairs(list) do
        m.unit = "sim" .. i
        m.sim, m.level = true, 60
        m.online, m.afk, m.dead = true, false, false
        m.isLeader = m.isMe or false
        m.isAssist = false
        if not m.isMe and nAssist < 2 and (m.role == "TANK" or (m.role == "HEALER" and nAssist == 1)) then m.isAssist = true nAssist = nAssist + 1 end
        rollBuffs(m, cls)
        m.ench = {}
        if not m.isMe and chance(0.3) then
            m.ench[1] = L[SLOTS[rnd(1, #SLOTS)]]
            if chance(0.3) then local s2 = L[SLOTS[rnd(1, #SLOTS)]] if s2 ~= m.ench[1] then m.ench[2] = s2 end end
        end
        m.dura = rnd(55, 100)
        m.fireRes = inst.key == "onyxia" and (m.role == "TANK" and rnd(90, 190) or rnd(0, 120)) or rnd(0, 40)
    end
    -- a few outliers: low durability, AFK, offline, far away
    local others = {}
    for i = 2, #list do others[#others + 1] = list[i] end
    local function pick() return table.remove(others, rnd(1, #others)) end
    local p = pick() p.dura = rnd(8, 25)
    p = pick() p.dura = rnd(20, 29)
    p = pick() p.afk = true
    if size >= 20 then
        p = pick() p.online = false p.buffs = {}
        p = pick() p.afk = true p.far = true p.zone = L["Orgrimmar"]
    end
    if size >= 40 then
        p = pick() p.online = false p.buffs = {}
        p = pick() p.far = true p.zone = L["Orgrimmar"]
    end
    table.sort(list, function(a, b) if a.group ~= b.group then return a.group < b.group end return a.name < b.name end)
    local by = {}
    for _, m in ipairs(list) do by[m.name] = m end
    return list, by, cls
end

------------------------------------------------------------------------
-- ns.Group: real data from the Blizzard APIs, the made-up raid in the simulator
------------------------------------------------------------------------
local function realInGroup() return (IsInGroup and IsInGroup()) and true or false end
local function realInRaid() return (IsInRaid and IsInRaid()) and true or false end
function G.IsSim() return Sim.Active() end
function G.IsInGroup() if Sim.Active() then return true end return realInGroup() end
function G.IsInRaid() if Sim.Active() then return true end return realInRaid() end
function G.Num()
    if Sim.Active() then return #S.list end
    return (GetNumGroupMembers and GetNumGroupMembers()) or 0
end
function G.InInstance()
    if Sim.Active() then return true, "raid" end
    if not IsInInstance then return false, "none" end
    return IsInInstance()
end
local function keyOfName(n)
    n = type(n) == "string" and n:lower() or ""
    if n:find("onyxia", 1, true) then return "onyxia" end
    if n:find("hyjal", 1, true) then return "hyjal" end
    if n:find("barrow", 1, true) then return "barrow" end
    return nil
end
function G.Instance()
    if Sim.Active() then return { name = L[S.inst.name], mapID = S.inst.mapID, key = S.inst.key, sim = true } end
    local inInst = IsInInstance and IsInInstance()
    if not inInst then return nil end
    local name
    if GetInstanceInfo then
        local ok, n = pcall(GetInstanceInfo)
        if ok then name = ns.safe(n) end
    end
    local mid
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mid = ns.safe(m) end
    end
    return { name = name, mapID = mid, key = keyOfName(name) }
end
-- real member list (without a group: empty)
local function realMembers()
    local out = {}
    if realInRaid() then
        for i = 1, ((GetNumGroupMembers and GetNumGroupMembers()) or 0) do
            local ok, name, rank, sub, lvl, _, cls, zone, online, dead, _, _, combatRole = pcall(GetRaidRosterInfo, i)
            name = ok and ns.safe(name) or nil
            if name then
                local u = "raid" .. i
                local full = ns.fullName(name)
                out[#out + 1] = { unit = u, name = full, class = ns.safe(cls), role = ns.safe(combatRole) or (UnitGroupRolesAssigned and ns.safe(UnitGroupRolesAssigned(u))),
                    group = ns.safe(sub) or 1, online = ns.safe(online) and true or false, isLeader = ns.safe(rank) == 2, isAssist = ns.safe(rank) == 1,
                    level = ns.safe(lvl) or 0, dead = ns.safe(dead) and true or false, zone = ns.safe(zone), isMe = ns.isMe(full) }
            end
        end
    elseif realInGroup() then
        local units = { "player" }
        for i = 1, 4 do units[#units + 1] = "party" .. i end
        for _, u in ipairs(units) do
            if UnitExists(u) then
                local n = ns.safe(ns.UnitName(u))
                if n then
                    local _, cls = UnitClass(u)
                    local full = ns.fullName(n)
                    out[#out + 1] = { unit = u, name = full, class = cls, role = UnitGroupRolesAssigned and ns.safe(UnitGroupRolesAssigned(u)) or nil,
                        group = 1, online = ns.safe(UnitIsConnected(u)) and true or false, isLeader = ns.safe(UnitIsGroupLeader(u)) and true or false,
                        isAssist = false, level = ns.safe(UnitLevel(u)) or 0, dead = ns.safe(UnitIsDeadOrGhost(u)) and true or false, isMe = u == "player" }
                end
            end
        end
    end
    return out
end
function G.Members()
    if Sim.Active() then return S.list end
    return realMembers()
end
function G.Member(name)
    if not name then return nil end
    if Sim.Active() then return S.by[ns.fullName(name)] or S.by[name] end
    local want = ns.fullName(name)
    for _, m in ipairs(realMembers()) do if m.name == want or ns.short(m.name) == ns.short(want) then return m end end
end
function G.IsLeader(name)
    if Sim.Active() then
        if not name or ns.isMe(name) then return true end
        local m = G.Member(name)
        return m and m.isLeader or false
    end
    if not name or ns.isMe(name) then return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end
    local m = G.Member(name)
    return m and m.isLeader or false
end
function G.IsAssist(name)
    local m = G.Member(name or ns.me())
    return m and (m.isAssist or m.isLeader) or false
end
function G.IsSimName(name)
    if not S or not name then return false end
    local m = S.by[ns.fullName(name)] or S.by[name]
    return m ~= nil and not m.isMe
end

------------------------------------------------------------------------
-- Send nothing outside (only Oasis's own functions, no Blizzard globals)
------------------------------------------------------------------------
local GROUP_CH = { RAID = true, PARTY = true, RAID_WARNING = true, INSTANCE_CHAT = true }
local SIM_TYPES = { WREP = true, WRME = true, RPREP = true, RPREQ = true, RBSET = true, RBREQ = true, LMSTART = true, LMITEM = true,
    LMRESP = true, LMVOTE = true, LMAWARD = true, LMEND = true, LMBID = true }
local function simRecord(rec)
    if type(rec) ~= "table" then return false end
    if rec.sim or tostring(rec.id or ""):find(SIM_PREFIX, 1, true) then return true end
    if G.IsSimName(rec.who) then return true end
    return false
end
local wrapped = false
local function install()
    if wrapped then return end
    wrapped = true
    local oSend, oChan, oLead = ns.SendChat, ns.groupChannel, ns.isGroupLead
    ns.SendChat = function(msg, channel, target)
        if S then console(channel or "GUILD", msg) return true end
        return oSend(msg, channel, target)
    end
    ns.groupChannel = function(...)
        if Sim.Active() then return "RAID" end
        return oChan(...)
    end
    ns.isGroupLead = function(...)
        if Sim.Active() then return true end
        return oLead(...)
    end
    local Comm = ns.Comm
    if Comm then
        local oGroup, oEx = Comm.Group, Comm.SendEx
        Comm.Group = function(msgType, ...)
            if S then ns.debug("Raid-Sim: Gruppe", msgType) return true end
            return oGroup(msgType, ...)
        end
        Comm.SendEx = function(opts, msgType, ...)
            if S and type(opts) == "table" and (GROUP_CH[opts.ch or ""] or SIM_TYPES[msgType or ""]) then
                ns.debug("Raid-Sim: nicht gesendet", opts.ch, msgType)
                return
            end
            return oEx(opts, msgType, ...)
        end
    end
    if Store and Store.Put then
        local oPut = Store.Put
        Store.Put = function(name, rec)
            if S and simRecord(rec) then
                rec.u = math.max(ns.now(), (rec.u or 0) + 1)
                rec.by = rec.by or ns.me()
                rec.sim = true
                Store.merge(name, rec)
                return rec
            end
            return oPut(name, rec)
        end
    end
end
install()

------------------------------------------------------------------------
-- Flow
------------------------------------------------------------------------
local PAGES = { "raidcheck", "raidprep", "raidboard", "wipes", "raid", "home" }
local function refresh()
    for _, k in ipairs(PAGES) do ns.RefreshPage(k) end
    if ns.BuffMonitor and ns.BuffMonitor.Update then pcall(ns.BuffMonitor.Update) end
    if ns.UpdateDemoSwitch then pcall(ns.UpdateDemoSwitch) end
end
Sim.Refresh = refresh

local function nextFightIn() return rnd(150, 240) end

-- Response to a ready check: true / false / "afk"
function Sim.ReadyAnswer(m)
    if not m then return "afk" end
    if m.isMe then return true end
    if not m.online or m.afk then return "afk" end
    if m.dead or m.dura < 20 then return chance(0.6) and false or true end
    return chance(0.08) and false or true
end

function Sim.Start(size, instKey)
    if not ns.IsDev() then ns.print(L["The raid simulator is only available in the developer version."]) return false end
    size = tonumber(size) or 20
    if not COMP[size] then size = 20 end
    instKey = INST_ALIAS[tostring(instKey or ""):lower()] or "onyxia"
    if S then Sim.Stop(true) end
    S = { size = size, inst = INST[instKey], started = now(), tries = {}, bossIdx = 1, nextFight = now() + 90 }
    local ok, list, by, cls = pcall(build, size, S.inst)
    if not ok then S = nil ns.err("RaidSim", list) return false end
    S.list, S.by, S.cls = list, by, cls
    local st = ns.db and ns.db.settings
    S.bmWas = st and st.buffShow or false
    if ns.RaidCheck then ns.RaidCheck.demoReady = nil ns.RaidCheck.ready = {} ns.RaidCheck.readyEnd = nil end
    if ns.BuffMonitor and ns.BuffMonitor.Toggle then pcall(ns.BuffMonitor.Toggle, true) end
    refresh()
    ns.print((L["Raid simulator: %d players in %s (only for you, nothing is sent to the guild). Stop: /oa raidsim aus"]):format(size, L[S.inst.name]))
    return true
end

function Sim.Stop(quiet)
    if not S then return end
    local was = S
    -- close a running loot round while the redirects still apply
    if ns.LootMaster and ns.LootMaster.session and ns.LootMaster.session.sim and ns.LootMaster.End then pcall(ns.LootMaster.End) end
    if ns.LootMaster and ns.LootMaster.session and ns.LootMaster.session.sim then ns.LootMaster.session = nil end
    if ns.RaidPlanner and ns.RaidPlanner.running and ns.RaidPlanner.running.sim and ns.RaidPlanner.Stop then pcall(ns.RaidPlanner.Stop) end
    S = nil
    local n = Sim.Cleanup()
    if ns.RaidCheck then ns.RaidCheck.demoReady = nil ns.RaidCheck.ready = {} ns.RaidCheck.readyEnd = nil ns.RaidCheck.readyDone = nil end
    if ns.RaidBoard then ns.RaidBoard.simFor = nil end
    if not was.bmWas and ns.BuffMonitor and ns.BuffMonitor.Toggle then pcall(ns.BuffMonitor.Toggle, false) end
    refresh()
    if not quiet then ns.print((L["Raid simulator stopped (%d entries removed)."]):format(n)) end
end

-- remove all sim records (also leftovers after /reload)
function Sim.Cleanup()
    local n = 0
    if not (ns.db and ns.db.store) then return 0 end
    for _, c in pairs(ns.db.store) do
        if type(c) == "table" then
            for id, r in pairs(c) do
                if tostring(id):find(SIM_PREFIX, 1, true) or (type(r) == "table" and r.sim) then c[id] = nil n = n + 1 end
            end
        end
    end
    return n
end

-- Change a sim member's group (raid planner sorts)
function Sim.SetGroup(name, g)
    local m = S and S.by[name]
    if not m or not g then return false end
    local cnt = 0
    for _, o in ipairs(S.list) do if o.group == g and o ~= m then cnt = cnt + 1 end end
    if cnt >= 5 then return false end
    m.group = g
    return true
end

-- Combat: attempt with death order -> combat reports; victory -> loot round, next boss
function Sim.Fight(forceOk)
    if not Sim.Active() then return end
    local inst = S.inst
    local boss = inst.bosses[S.bossIdx] or inst.bosses[#inst.bosses]
    local tries = (S.tries[boss] or 0) + 1
    S.tries[boss] = tries
    local ok = forceOk
    if ok == nil then ok = tries >= 2 and chance(0.25 + 0.2 * tries) end
    local dur = ok and rnd(150, 360) or rnd(60, 300)
    local alive = {}
    for _, m in ipairs(S.list) do if m.online and not m.afk and not m.dead then alive[#alive + 1] = m end end
    -- Unlucky one: often dies first (pattern in the combat reports)
    if not S.unlucky then
        for _, m in ipairs(alive) do if m.role == "DAMAGER" and not m.isMe then S.unlucky = m.name break end end
    end
    local nDead = ok and rnd(0, math.min(3, #alive)) or math.max(1, math.floor(#alive * (0.6 + math.random() * 0.4)))
    local order = {}
    for _, m in ipairs(alive) do
        local w = math.random() + (m.role == "HEALER" and 0.5 or 0) + (m.role == "TANK" and 0.3 or 0)
        if m.name == S.unlucky and chance(0.7) then w = -1 end
        order[#order + 1] = { m = m, w = w }
    end
    table.sort(order, function(a, b) return a.w < b.w end)
    local parts, t = {}, rnd(15, 45)
    local srcs = { "self", "msg", "poll", "log" }
    for i = 1, math.min(nDead, #order) do
        local m = order[i].m
        parts[#parts + 1] = ("%s~%.1f~%s"):format(m.name:gsub("[~|]", ""), math.min(t, dur), m.isMe and "self" or srcs[rnd(2, 4)])
        t = t + math.random() * (dur / math.max(1, nDead)) * 1.2
        if not ok then m.dead = true m.reviveAt = now() + rnd(20, 45) end
        m.dura = math.max(0, m.dura - 10)
    end
    fightN = fightN + 1
    local rec = { id = SIM_PREFIX .. "wr-" .. fightN .. "-" .. ns.now(), sim = true, boss = boss, inst = L[inst.name], ts = ns.now() - dur, dur = dur,
        ok = ok, hp = (not ok) and (math.floor((5 + math.random() * 60) * 10) / 10) or 0, deaths = table.concat(parts, "|"),
        first = parts[1] and parts[1]:match("^(.-)~") or "", size = #S.list, by = ns.me(), u = ns.now() }
    Store.merge("wipes", rec)
    if not ok then
        for _, m in ipairs(S.list) do m.dura = math.max(0, m.dura - 10) end
    end
    ns.print((L["Raid sim: %s - %s after %s, %d deaths"]):format(boss, ok and L["Kill"] or L["Wipe"],
        ("%d:%02d"):format(math.floor(dur / 60), dur % 60), math.min(nDead, #order)))
    if ok then
        S.bossIdx = math.min(#inst.bosses, S.bossIdx + 1)
        ns.After(3, function() Sim.LootRound() end)
    end
    S.nextFight = now() + nextFightIn()
    refresh()
    return rec
end

function Sim.LootRound()
    if not Sim.Active() or not (ns.LootMaster and ns.LootMaster.SimRound) then return end
    local pool = LOOT[S.inst.key] or LOOT.onyxia
    local items, seen = {}, {}
    for _ = 1, (S.size >= 40 and 3 or 2) do
        local it = pool[rnd(1, #pool)]
        if not seen[it] then seen[it] = true items[#items + 1] = { link = it } end
    end
    if ns.LootMaster then ns.LootMaster.SimRound(items) end
end

function Sim.ReadyCheck()
    if not Sim.Active() then return end
    if ns.RaidCheck and ns.RaidCheck.DemoReadyCheck then ns.RaidCheck.DemoReadyCheck() end
    ns.ShowPage("raidcheck")
end

-- Tick: buffs expire and get renewed, people go AFK/come back, fights
local function tick()
    if not S then return end
    if not ns.IsDev() then Sim.Stop(true) return end
    local t = now()
    local changed = false
    for _, m in ipairs(S.list) do
        for k, exp in pairs(m.buffs) do if exp <= t then m.buffs[k] = nil changed = true end end
        if m.online and not m.afk then
            if S.cls.PRIEST and not has(m, "fort") and chance(0.04) then giveBuff(m, "fort", 1500, 1800) changed = true end
            if S.cls.DRUID and not has(m, "motw") and chance(0.04) then giveBuff(m, "motw", 1500, 1800) changed = true end
            if S.cls.MAGE and not has(m, "int") and chance(0.03) then giveBuff(m, "int", 1500, 1800) changed = true end
            if S.cls.SHAMAN and not has(m, "totem") and chance(0.08) then giveBuff(m, "totem", 60, 120) changed = true end
            if not has(m, "food") and chance(0.01) then giveBuff(m, "food", 600, 900) changed = true end
        end
        if m.dead and m.reviveAt and t >= m.reviveAt then m.dead, m.reviveAt = false, nil changed = true end
        if not m.isMe and m.online and chance(0.003) then m.afk = not m.afk changed = true end
    end
    if t >= (S.nextFight or 0) then Sim.Fight() return end
    if changed then refresh() end
end
ns.Every(2, tick)

------------------------------------------------------------------------
-- Command, menu on the demo toggle, probe
------------------------------------------------------------------------
function Sim.Menu(owner)
    local K = ns.K
    if not (K and K.ShowMenu) then return end
    local items = {
        { text = L["Raid sim: 10 Barrow Deeps"], fn = function() Sim.Start(10, "barrow") end },
        { text = L["Raid sim: 20 Hyjal"], fn = function() Sim.Start(20, "hyjal") end },
        { text = L["Raid sim: 20 Onyxia"], fn = function() Sim.Start(20, "onyxia") end },
        { text = L["Raid sim: 40 Onyxia"], fn = function() Sim.Start(40, "onyxia") end },
    }
    if Sim.Active() then
        items[#items + 1] = { text = L["Simulate ready check"], fn = Sim.ReadyCheck }
        items[#items + 1] = { text = L["Boss fight now"], fn = function() Sim.Fight() end }
        items[#items + 1] = { text = L["Loot round"], fn = Sim.LootRound }
        items[#items + 1] = { text = L["Raid simulator off"], fn = function() Sim.Stop() end }
    end
    K.ShowMenu(owner, items, L["Raid simulator"])
end

ns.slash.raidsim = function(rest)
    rest = tostring(rest or ""):lower()
    local size, inst, cmd
    for w in rest:gmatch("%S+") do
        if tonumber(w) then size = tonumber(w)
        elseif INST_ALIAS[w] then inst = w
        else cmd = w end
    end
    if cmd == "aus" or cmd == "off" or cmd == "stop" or cmd == "weg" then
        if S then Sim.Stop() else ns.print(L["Raid simulator is not running."]) end
        return
    end
    if not ns.IsDev() then ns.print(L["The raid simulator is only available in the developer version."]) return end
    if cmd == "kampf" or cmd == "fight" then if Sim.Active() then Sim.Fight() end return end
    if cmd == "beute" or cmd == "loot" then if Sim.Active() then Sim.LootRound() end return end
    if cmd == "bereit" or cmd == "ready" then Sim.ReadyCheck() return end
    Sim.Start(size or (S and S.size) or 20, inst or (S and S.inst.key) or "onyxia")
end

local hooked = false
local function hookChip()
    if hooked then return end
    local main = ns.MainFrame and ns.MainFrame()
    local chip = main and main.demo
    if not chip or not chip.HookScript then return end
    hooked = true
    chip:HookScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and ns.IsDev() then Sim.Menu(self) end
    end)
    chip:HookScript("OnEnter", function()
        if not ns.IsDev() or not GameTooltip or not GameTooltip.AddLine then return end
        GameTooltip:AddLine("|cff777777" .. L["Right-click: raid simulator"] .. (Sim.Active() and (" (" .. L["on"] .. ")") or "") .. "|r")
        GameTooltip:Show()
    end)
end
Sim.HookChip = hookChip
ns.Listen("LOGIN", function()
    -- remove leftovers of a simulation from before /reload
    Sim.Cleanup()
    ns.After(2, hookChip)
end)
ns.Every(5, hookChip)

ns.Probes = ns.Probes or {}
ns.Probes.raidsim = function()
    ns.print(("Raid-Sim: aktiv=%s  IsInGroup=%s IsInRaid=%s Num=%s Inst=%s"):format(tostring(Sim.Active()), tostring(G.IsInGroup()), tostring(G.IsInRaid()),
        tostring(G.Num()), tostring((G.Instance() or {}).name)))
    for i, m in ipairs(G.Members()) do
        if i > 6 then break end
        ns.print(("  %s %s %s G%s %s%s"):format(m.unit or "-", tostring(m.name), tostring(m.class), tostring(m.group), tostring(m.role),
            m.isLeader and " (Leiter)" or (m.isAssist and " (Assist)" or "")))
    end
end

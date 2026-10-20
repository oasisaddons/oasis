-- Oasis: tactics map - instance map with lineup
--  * Map of the current instance automatically (C_Map tiles, else old world map tiles from DungeonMapsData, else grid)
--  * Zoom with mouse wheel (around the cursor), pan with right/middle mouse button
--  * Raid leader/assistant/officer: tank/healer/DPS icons, target markers 1-8, players, arrows, text, freehand
--  * Changes go throttled to raid/group (RBSET); on open/join the state is requested (RBREQ)
--  * Receivers only accept plans from the group leader or assistants
--  Coordinates normalized 0..1 to the map; stored per map in ns.db.raidBoards[map].plans[A/B/C]
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Module Raid tools (can be disabled, see ModuleLoader.lua)
-- ns.Group comes from Core\Diagnostics\RaidSim.lua; if the file is missing, the real Blizzard queries apply
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C = ns.K, ns.K.C
-- Security on receipt (others' addon messages may be manipulated):
-- Sanitize texts, limit numbers, check names, throttle floods
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Neutralize escape sequences (|c |r |n |H |T |K |A ...) and control chars; links: valid item/spell links stay
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

local RB = {}
ns.RaidBoard = RB
if ns.ICONS then ns.ICONS.raidboard = ns.ICONS.map or (ns.MEDIA .. "icons\\map") end

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ICON = ns.MEDIA .. "icons\\"
local PLANS = { "A", "B", "C" }
local COLORS = {
    { 0.95, 0.25, 0.25 },   -- 1 rot
    { 1.00, 0.85, 0.25 },   -- 2 gelb
    { 0.35, 0.90, 0.45 },   -- 3 green
    { 0.35, 0.65, 1.00 },   -- 4 blau
    { 1.00, 1.00, 1.00 },   -- 5 weiss
}
local COLOR_NAMES = { "Red", "Yellow", "Green", "Blue", "White" }
local ROLE_TEX = { T = ICON .. "role_tank", H = ICON .. "role_heal", D = ICON .. "role_dps" }
local ROLE_COL = { T = { 0.40, 0.62, 1.00 }, H = { 0.40, 0.90, 0.55 }, D = { 0.95, 0.35, 0.35 } }
local ROLE_NAME = { T = "Tank", H = "Healer", D = "Damage" }
local MAX_ENC = 6000          -- largest plan in characters (approx. 25 messages)
local MAX_UNDO = 30
local ALPH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"

-- Maps to choose (raids first); map = uiMapID (retail map catalog), legacy = world map tiles
local RAIDS = {
    { key = "m248", name = "Onyxia's Lair", map = 248, legacy = { folder = "OnyxiasLair", floors = { 1 } } },
    { key = "m329", name = "Hyjal", map = 329 },
    { key = "barrow", name = "Barrow Deeps" },   -- TODO uiMapID unknown: detected automatically in the raid
}

------------------------------------------------------------------------
-- Zustand
------------------------------------------------------------------------
RB.board = nil        -- current map (key)
RB.plan = "A"
RB.auto = true        -- Map automatically by location
RB.follow = true      -- Follow the leader's plans
RB.tool = "move"      -- move | draw | arrow | label | erase | place
RB.place = nil        -- { k = "m", t = "T" } or { k = "p", n = name, c = class }
RB.color = 1
RB.undo = {}
local page            -- Page frame (after build)
local sendPending, lastReqAnswer, lastReq, lastToast = false, 0, 0, 0

------------------------------------------------------------------------
-- Speicher
------------------------------------------------------------------------
local function store()
    ns.db.raidBoards = ns.db.raidBoards or {}
    return ns.db.raidBoards
end
function RB.Plan(board, plan, create)
    board, plan = board or RB.board, plan or RB.plan
    if not board then return nil end
    local s = store()
    local b = s[board]
    if not b then
        if not create then return nil end
        b = { plans = {} }
        s[board] = b
    end
    b.plans = b.plans or {}
    local p = b.plans[plan]
    if not p and create then p = { items = {}, nid = 0, rev = 0 } b.plans[plan] = p end
    return p
end
local function curPlan() return RB.Plan(nil, nil, true) end

------------------------------------------------------------------------
-- Encoding (compact, without , ; ^ |)
------------------------------------------------------------------------
local DEC = {}
for i = 1, #ALPH do DEC[ALPH:sub(i, i)] = i - 1 end
local function q(v)
    v = math.floor(math.max(0, math.min(1, v or 0)) * 4095 + 0.5)
    local a, b = math.floor(v / 64), v % 64
    return ALPH:sub(a + 1, a + 1) .. ALPH:sub(b + 1, b + 1)
end
local function dq(s, i)
    local a, b = DEC[s:sub(i, i)], DEC[s:sub(i + 1, i + 1)]
    if not a or not b then return nil end
    return (a * 64 + b) / 4095
end
local function clean(s, n) return ((tostring(s or "")):gsub("[,;|%^\r\n]", " "):sub(1, n or 40)) end

function RB.Encode(plan)
    local out = {}
    for _, it in ipairs(plan and plan.items or {}) do
        local id = tostring(it.id or 0)
        if it.k == "m" then out[#out + 1] = "m" .. id .. "," .. it.t .. "," .. q(it.x) .. q(it.y)
        elseif it.k == "p" then out[#out + 1] = "p" .. id .. "," .. q(it.x) .. q(it.y) .. "," .. clean(it.c, 12) .. "," .. clean(it.n, 48)
        elseif it.k == "l" then out[#out + 1] = "l" .. id .. "," .. (it.c or 5) .. "," .. q(it.x) .. q(it.y) .. "," .. clean(it.s, 40)
        elseif it.k == "a" then out[#out + 1] = "a" .. id .. "," .. (it.c or 1) .. "," .. q(it.x) .. q(it.y) .. q(it.x2) .. q(it.y2)
        elseif it.k == "s" then
            local pts = {}
            for i = 1, #it.p, 2 do pts[#pts + 1] = q(it.p[i]) .. q(it.p[i + 1]) end
            out[#out + 1] = "s" .. id .. "," .. (it.c or 1) .. "," .. table.concat(pts)
        end
    end
    return table.concat(out, ";")
end
function RB.Decode(s)
    local items, nid = {}, 0
    for part in ((s or "") .. ";"):gmatch("([^;]*);") do
        local k = part:sub(1, 1)
        local f = {}
        for v in (part:sub(2) .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
        local id = tonumber(f[1]) or 0
        local it
        if k == "m" and f[3] and (ROLE_TEX[f[2]] or f[2]:match("^[1-8]$")) then
            it = { k = "m", t = f[2], x = dq(f[3], 1), y = dq(f[3], 3) }
        elseif k == "p" and f[2] then
            it = { k = "p", x = dq(f[2], 1), y = dq(f[2], 3), c = f[3] ~= "" and f[3] or nil, n = f[4] or "?" }
        elseif k == "l" and f[3] then
            it = { k = "l", c = tonumber(f[2]) or 5, x = dq(f[3], 1), y = dq(f[3], 3), s = f[4] or "" }
        elseif k == "a" and f[3] and #f[3] >= 8 then
            it = { k = "a", c = tonumber(f[2]) or 1, x = dq(f[3], 1), y = dq(f[3], 3), x2 = dq(f[3], 5), y2 = dq(f[3], 7) }
        elseif k == "s" and f[3] then
            local p = {}
            for i = 1, #f[3] - 3, 4 do
                local x, y = dq(f[3], i), dq(f[3], i + 2)
                if x and y then p[#p + 1] = x p[#p + 1] = y end
            end
            if #p >= 4 then it = { k = "s", c = tonumber(f[2]) or 1, p = p } end
        end
        if it and it.x ~= nil and it.y == nil then it = nil end
        if it then
            it.id = id
            if not COLORS[it.c or 1] then it.c = 1 end
            items[#items + 1] = it
            if id > nid then nid = id end
        end
    end
    return items, nid
end

------------------------------------------------------------------------
-- Permissions / group
------------------------------------------------------------------------
local function simOn() return ns.Sim and ns.Sim.Active() or false end
local function groupUnits()
    local out = {}
    if ns.Group.IsInRaid() then for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else out[1] = "player" for i = 1, 4 do out[#out + 1] = "party" .. i end end
    return out
end
local function unitFull(u)
    if not UnitExists(u) then return nil end
    local n = ns.safe(ns.UnitName(u))
    return n and ns.fullName(n)
end
-- Leader or assistant of the current group?
function RB.IsLeadName(sender)
    if not sender or not ns.Group.IsInGroup() then return false end
    if simOn() then return ns.Group.IsAssist(sender) end
    local want = ns.fullName(sender)
    for _, u in ipairs(groupUnits()) do
        local n = unitFull(u)
        if n and (n == want or ns.short(n) == ns.short(want)) then
            return (UnitIsGroupLeader(u) or (UnitIsGroupAssistant and UnitIsGroupAssistant(u))) and true or false
        end
    end
    return false
end
local function iAmLead()
    if simOn() then return true end   -- Raid-Simulator: ich bin Raidleiter
    return IsInGroup() and (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) and true or false
end
-- Drawing: solo (local plan) and in a normal group everyone; in a raid only
-- Leaders/assistants, guild leadership, named raid leaders (Admin.IsRaidLead) and developers
function RB.CanEdit()
    if ns.Demo and ns.Demo.IsActive() then return true end
    if ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.board") then return true end
    if not ns.Group.IsInRaid() then return true end
    return iAmLead()
end
-- Member of my current group?
function RB.InMyGroup(sender)
    if not sender or not ns.Group.IsInGroup() then return false end
    local want = ns.fullName(sender)
    for _, u in ipairs(groupUnits()) do
        local n = unitFull(u)
        if n and (n == want or ns.short(n) == ns.short(want)) then return true end
    end
    return false
end
-- Accept this sender's plan? Group: any member; raid: leader/assistant or named raid leader
function RB.AcceptFrom(sender)
    if RB.IsLeadName(sender) then return true end
    if simOn() then return false end
    if not ns.Group.IsInRaid() then return RB.InMyGroup(sender) end
    local r = ns.Admin and ns.Admin.RaidRole and ns.Admin.RaidRole(sender)
    return r ~= nil and RB.InMyGroup(sender)
end
local function canSend()
    if not ns.Group.IsInGroup() then return false end
    if iAmLead() or not ns.Group.IsInRaid() then return true end
    return (ns.Admin and ns.Admin.RaidRole and ns.Admin.RaidRole(ns.me())) ~= nil
end
function RB.Members()
    local out = {}
    if simOn() then
        for _, m in ipairs(ns.Group.Members()) do out[#out + 1] = { n = m.name, c = m.class, r = m.role } end
    elseif IsInGroup() then
        for _, u in ipairs(groupUnits()) do
            local n = unitFull(u)
            if n then
                local _, cls = UnitClass(u)
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
                out[#out + 1] = { n = n, c = cls, r = role }
            end
        end
    end
    if #out == 0 and ns.Demo and ns.Demo.IsActive() then
        for _, d in ipairs({ { "Grukthar", "WARRIOR" }, { "Zul'mira", "PRIEST" }, { "Mokrash", "HUNTER" }, { "Tavira", "MAGE" },
            { "Hoknar", "SHAMAN" }, { "Vex'ra", "ROGUE" }, { "Bramok", "DRUID" }, { "Shazira", "WARLOCK" } }) do
            out[#out + 1] = { n = d[1], c = d[2] }
        end
    end
    if #out == 0 then
        local _, cls = UnitClass("player")
        out[1] = { n = ns.me(), c = cls }
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

------------------------------------------------------------------------
-- Maps
------------------------------------------------------------------------
local function dungeonName(key)
    for _, d in ipairs(ns.DungeonData or {}) do
        if d.key == key then return (ns.lang == "de" and d.de) or d.name end
    end
    return key
end
local function legacyByName(name)
    if not name or name == "" then return nil end
    name = name:lower()
    for _, d in ipairs(ns.DungeonData or {}) do
        if ((d.name or ""):lower() == name or (d.de or ""):lower() == name) and ns.DungeonMapsData and ns.DungeonMapsData[d.key] then
            return d.key, ns.DungeonMapsData[d.key]
        end
    end
end
local function mapInfo(id)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, mi = pcall(C_Map.GetMapInfo, id)
    return ok and type(mi) == "table" and mi or nil
end
-- Layers of a map: { { map = id, name = "..." }, ... }
local function floorsOf(mapID)
    if not (C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo) then return nil end
    local ok, gid = pcall(C_Map.GetMapGroupID, mapID)
    if not ok or not gid then return nil end
    local ok2, list = pcall(C_Map.GetMapGroupMembersInfo, gid)
    if not ok2 or type(list) ~= "table" or #list < 2 then return nil end
    local out = {}
    for _, m in ipairs(list) do if m.mapID then out[#out + 1] = { map = m.mapID, name = m.name, idx = m.relativeHeightIndex or #out } end end
    table.sort(out, function(a, b) return a.idx < b.idx end)
    return out
end
-- Map tiles via C_Map (retail client)
local function artOf(mapID)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if not ok or type(layers) ~= "table" or not layers[1] then return nil end
    local ly = layers[1]
    local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not ok2 or type(tex) ~= "table" or #tex == 0 then return nil end
    local lw, lh, tw, th = ly.layerWidth, ly.layerHeight, ly.tileWidth, ly.tileHeight
    if not (lw and lh and tw and th) or lw <= 0 or lh <= 0 or tw <= 0 or th <= 0 then return nil end
    return { tex = tex, lw = lw, lh = lh, tw = tw, th = th, cols = math.ceil(lw / tw), rows = math.ceil(lh / th) }
end
-- Key -> { title, mapID, art, legacy, floor, floors }
function RB.BoardInfo(key)
    if not key then return nil end
    local info = { key = key }
    local mid = tonumber(key:match("^m(%d+)$"))
    if mid then
        info.mapID = mid
        local mi = mapInfo(mid)
        info.title = mi and mi.name
        for _, r in ipairs(RAIDS) do if r.key == key then info.title = info.title or L[r.name] info.legacy = r.legacy and { cfg = r.legacy, floor = r.legacy.floors[1] } end end
        info.art = artOf(mid)
        if not info.art and not info.legacy and info.title then
            local dk, cfg = legacyByName(info.title)
            if cfg then info.legacy = { cfg = cfg, floor = cfg.floors[1] } info.dkey = dk end
        end
        info.floors = floorsOf(mid)
        info.title = info.title or ("Map " .. mid)
        return info
    end
    local dk, fl = key:match("^d([%w_]+):(%d+)$")
    if dk then
        local cfg = ns.DungeonMapsData and ns.DungeonMapsData[dk]
        if cfg then
            fl = tonumber(fl)
            info.legacy = { cfg = cfg, floor = fl }
            info.dkey = dk
            info.title = dungeonName(dk)
            if #cfg.floors > 1 then
                info.floors = {}
                for i, f in ipairs(cfg.floors) do info.floors[#info.floors + 1] = { key = "d" .. dk .. ":" .. f, name = cfg.floorNames and cfg.floorNames[i] or tostring(i), cur = f == fl } end
            end
            return info
        end
    end
    for _, r in ipairs(RAIDS) do if r.key == key then info.title = L[r.name] return info end end
    info.title = key:match("^x(.+)$") or key
    return info
end
-- Dungeon key (DungeonMapsData/BossPos) from instance or zone name, German or English
-- (Forever: GetBestMapForUnit/UnitPosition return nil in instances -> go by name)
local function dungeonKeyByName(name)
    local D = ns.Dungeons
    if not (D and name and name ~= "") then return nil end
    local d
    local k = D.KeyByZone and D.KeyByZone(name)
    if k and D.List then for _, x in ipairs(D.List()) do if x.key == k then d = x break end end end
    if not d and D.Match then d = D.Match(name) end
    if not d then return nil end
    return d.dbKey or d.key
end
local function boardByDungeon(dk)
    if not dk then return nil end
    local bp = ns.BossPos and ns.BossPos[dk]
    local m = bp and bp[1] and tonumber(bp[1].map)
    if m and artOf(m) then return "m" .. m end
    local cfg = ns.DungeonMapsData and ns.DungeonMapsData[dk]
    if cfg and cfg.floors and cfg.floors[1] then
        -- Floor of the first boss, else the first
        local fl = cfg.pins and cfg.pins[1] and tonumber(cfg.pins[1][4]) or cfg.floors[1]
        return "d" .. dk .. ":" .. fl
    end
    if m then return "m" .. m end
end
RB.DungeonBoard = function(name) return boardByDungeon(dungeonKeyByName(name)) end
-- Map at current location
function RB.Detect()
    -- Raid simulator: map of the simulated raid
    if simOn() then
        local inst = ns.Group.Instance()
        local k = inst and inst.key
        if k == "onyxia" then return "m248" elseif k == "hyjal" then return "m329" elseif k == "barrow" then return "barrow" end
    end
    local inInst, iType = IsInInstance()
    local mid
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mid = ns.safe(m) end
    end
    if inInst then
        local iname = GetInstanceInfo and ns.safe((GetInstanceInfo()))
        if mid and (artOf(mid) or not legacyByName(iname)) then return "m" .. mid end
        local dk, cfg = legacyByName(iname)
        if cfg then return "d" .. dk .. ":" .. cfg.floors[1] end
        if iname and iname:lower():find("barrow") then return "barrow" end
        if not mid then
            for _, n in ipairs({ iname, ns.safe(GetRealZoneText and GetRealZoneText()) }) do
                local b = boardByDungeon(dungeonKeyByName(n))
                if b then return b end
            end
        end
        if mid then return "m" .. mid end
        if iname then return "x" .. clean(iname, 40) end
        return nil, iType
    end
    return mid and ("m" .. mid) or nil
end
function RB.Catalog()
    local out = {}
    for _, r in ipairs(RAIDS) do out[#out + 1] = { key = r.key, text = L[r.name], raid = true } end
    local dl = {}
    for dk, cfg in pairs(ns.DungeonMapsData or {}) do
        if cfg.floors and cfg.floors[1] then dl[#dl + 1] = { key = "d" .. dk .. ":" .. cfg.floors[1], text = dungeonName(dk) } end
    end
    table.sort(dl, function(a, b) return a.text < b.text end)
    for _, d in ipairs(dl) do out[#out + 1] = d end
    return out
end

------------------------------------------------------------------------
-- Changes (local + sending)
------------------------------------------------------------------------
local function pushUndo()
    local p = curPlan()
    local u = RB.undo
    u[#u + 1] = { board = RB.board, plan = RB.plan, enc = RB.Encode(p) }
    if #u > MAX_UNDO then table.remove(u, 1) end
end
function RB.Send()
    if sendPending then return end
    sendPending = true
    ns.After(0.8, function()
        sendPending = false
        RB.SendNow()
    end)
end
function RB.SendNow(force)
    if not canSend() or not RB.board then return false end
    local p = curPlan()
    local enc = RB.Encode(p)
    if #enc > MAX_ENC then ns.print(L["Tactics map: plan too large to send – please reduce drawings."]) return false end
    ns.Comm.Group("RBSET", RB.board, RB.plan, tostring(p.rev or 0), enc)
    return true
end
local function changed()
    local p = curPlan()
    p.rev = (p.rev or 0) + 1
    p.ts = ns.now()
    p.by = ns.me()
    RB.Send()
    if page then RB.Layout() end
end
function RB.Add(it)
    if not RB.board then return nil end
    local p = curPlan()
    if #RB.Encode(p) > MAX_ENC then ns.print(L["Tactics map: plan is full."]) return nil end
    pushUndo()
    p.nid = (p.nid or 0) + 1
    it.id = p.nid
    p.items[#p.items + 1] = it
    changed()
    return it
end
function RB.Remove(id)
    local p = curPlan()
    for i, it in ipairs(p.items) do
        if it.id == id then pushUndo() table.remove(p.items, i) changed() return true end
    end
    return false
end
function RB.Move(it, x, y, noUndo)
    if not noUndo then pushUndo() end
    local dx, dy = x - it.x, y - it.y
    it.x, it.y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y))
    if it.k == "a" then it.x2 = math.max(0, math.min(1, it.x2 + dx)) it.y2 = math.max(0, math.min(1, it.y2 + dy)) end
    changed()
end
function RB.Clear()
    local p = curPlan()
    if #p.items == 0 then return end
    pushUndo()
    p.items = {}
    changed()
end
function RB.Undo()
    local u = table.remove(RB.undo)
    if not u then return false end
    RB.board, RB.plan = u.board, u.plan
    local p = curPlan()
    p.items, p.nid = RB.Decode(u.enc)
    changed()
    return true
end
-- nearest element at point (for eraser)
function RB.HitTest(x, y, rad)
    rad = rad or 0.025
    local best, bd
    local function seg(ax, ay, bx, by)
        local vx, vy = bx - ax, by - ay
        local l2 = vx * vx + vy * vy
        local t = l2 > 0 and math.max(0, math.min(1, ((x - ax) * vx + (y - ay) * vy) / l2)) or 0
        local px, py = ax + t * vx - x, ay + t * vy - y
        return math.sqrt(px * px + py * py)
    end
    for _, it in ipairs(curPlan().items) do
        local d
        if it.k == "s" then
            for i = 1, #it.p - 3, 2 do
                local dd = seg(it.p[i], it.p[i + 1], it.p[i + 2], it.p[i + 3])
                if not d or dd < d then d = dd end
            end
        elseif it.k == "a" then d = seg(it.x, it.y, it.x2, it.y2)
        else d = math.sqrt((it.x - x) ^ 2 + (it.y - y) ^ 2) end
        if d and d <= rad and (not bd or d < bd) then best, bd = it, d end
    end
    return best
end

------------------------------------------------------------------------
-- Empfang
------------------------------------------------------------------------
local function onSet(sender, _, board, plan, rev, enc)
    if not board or board == "" or ns.isMe(sender) then return end
    if not RB.AcceptFrom(sender) then ns.debug("RBSET ignoriert (keine Rechte)", sender) return end
    -- only known maps (else the stored data grows with arbitrary keys), size limited
    if type(board) ~= "string" or #board > 44 or board:find("[|%c,;%^]") then return end
    if not (board:match("^m%d+$") or board:match("^d[%w_]+:%d+$") or board:match("^x.+$") or board:match("^[%w_]+$")) then return end
    if not RB.Plan(board, plan) then
        local n = 0
        for _ in pairs(store()) do n = n + 1 end
        if n >= 60 then return end
    end
    if type(enc) == "string" and #enc > 20000 then return end
    plan = (plan == "B" or plan == "C") and plan or "A"
    local items, nid = RB.Decode(enc)
    -- Limit elements/points, sanitize labels
    while #items > 400 do table.remove(items) end
    for _, it in ipairs(items) do
        if it.n then it.n = SEC.Text(it.n, 40) end
        if it.s then it.s = SEC.Text(it.s, 80) end
        if it.p and #it.p > 600 then for i = #it.p, 601, -1 do it.p[i] = nil end end
    end
    nid = math.min(tonumber(nid) or 0, 100000)
    local p = RB.Plan(board, plan, true)
    p.items, p.nid, p.rev, p.ts, p.by = items, nid, tonumber(rev) or 0, ns.now(), sender
    RB.lastFrom = sender
    if RB.follow then RB.board, RB.plan, RB.auto = board, plan, false end
    local shown = ns.MainShown() and ns.CurrentPage() == "raidboard"
    if shown then
        ns.RefreshPage("raidboard")
    elseif GetTime() - lastToast > 30 then
        lastToast = GetTime()
        local bi = RB.BoardInfo(board)
        K.Toast(L["New positions from the raid leader"], (bi and bi.title or board) .. " - " .. L["Plan"] .. " " .. plan .. " (" .. ns.displayName(sender) .. ")",
            C.amber, function() ns.ShowPage("raidboard") end)
    end
end
local function onReq(sender)
    if ns.isMe(sender) or not UnitIsGroupLeader("player") then return end
    if GetTime() - lastReqAnswer < 3 then return end
    local p = RB.board and RB.Plan()
    if not p or #p.items == 0 then return end
    lastReqAnswer = GetTime()
    RB.SendNow()
end
function RB.Request()
    if not IsInGroup() or simOn() or GetTime() - lastReq < 10 then return end
    lastReq = GetTime()
    ns.Comm.Group("RBREQ")
end
if ns.Comm then
    ns.Comm.On("RBSET", onSet)
    ns.Comm.On("RBREQ", onReq)
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------
local V = {}  -- Ansicht: zoom, ox, oy, bw, bh
V.z, V.ox, V.oy = 1, 0, 0

local function getLine(host)
    host.lineN = host.lineN + 1
    local ln = host.lines[host.lineN]
    if not ln then
        if host.canLine ~= false and host.canvas.CreateLine then
            local ok, l = pcall(host.canvas.CreateLine, host.canvas, nil, "OVERLAY")
            if ok and l and l.SetStartPoint then ln = l l.isLine = true else host.canLine = false end
        end
        if not ln then ln = { isLine = false, dots = {} } end
        host.lines[host.lineN] = ln
    end
    return ln
end
local function getDot(host)
    host.dotN = host.dotN + 1
    local d = host.dots[host.dotN]
    if not d then d = host.canvas:CreateTexture(nil, "OVERLAY") host.dots[host.dotN] = d end
    return d
end
-- Line in pixels (x to the right, y down) relative to the canvas
local function seg(host, x1, y1, x2, y2, col, th)
    local ln = getLine(host)
    if ln.isLine then
        ln:SetThickness(th)
        ln:SetColorTexture(col[1], col[2], col[3], 0.95)
        ln:SetStartPoint("TOPLEFT", host.canvas, x1, -y1)
        ln:SetEndPoint("TOPLEFT", host.canvas, x2, -y2)
        ln:Show()
    else
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local n = math.min(40, math.max(1, math.floor(len / 3)))
        for i = 0, n do
            local d = getDot(host)
            d:SetColorTexture(col[1], col[2], col[3], 0.95)
            d:SetSize(th, th)
            d:ClearAllPoints()
            d:SetPoint("CENTER", host.canvas, "TOPLEFT", x1 + (x2 - x1) * i / n, -(y1 + (y2 - y1) * i / n))
            d:Show()
        end
    end
end
local function arrow(host, x1, y1, x2, y2, col, th)
    seg(host, x1, y1, x2, y2, col, th)
    local a = math.atan2(y2 - y1, x2 - x1)
    local hl = 10 + th * 2
    for _, s in ipairs({ 2.6, -2.6 }) do seg(host, x2, y2, x2 + math.cos(a + s) * hl, y2 + math.sin(a + s) * hl, col, th) end
end

local function markerFrame(host, i)
    local m = host.marks[i]
    if m then return m end
    m = CreateFrame("Button", nil, host.canvas)
    m:SetFrameLevel(host.canvas:GetFrameLevel() + 3)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.ic = m:CreateTexture(nil, "ARTWORK")
    m.ic:SetPoint("CENTER")
    m.tx = K.Text(m, 12, C.text, "CENTER")
    m.tx:SetPoint("CENTER")
    m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    m:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" or not RB.CanEdit() or not self.item then return end
        if RB.tool == "erase" then RB.Remove(self.item.id) return end
        RB.StartDrag(self.item)
    end)
    m:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and RB.CanEdit() and self.item then RB.Remove(self.item.id) return end
        if btn == "LeftButton" then RB.EndAction() end
    end)
    m:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        local t = it.k == "p" and ns.displayName(it.n) or it.k == "l" and it.s or it.k == "m" and (ROLE_NAME[it.t] and L[ROLE_NAME[it.t]] or (L["Raid marker"] .. " " .. it.t)) or ""
        local lines = { t }
        if RB.CanEdit() then lines[2] = L["Drag = move, right-click = delete"] end
        K.ShowTip(self, lines)
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    host.marks[i] = m
    return m
end

function RB.Layout()
    local host = page and page.view
    if not host then return end
    local W, H = host:GetWidth(), host:GetHeight()
    if not W or W < 50 then W, H = 640, 470 end
    local info = host.info
    -- Map aspect ratio
    local asp = 1.5
    if info and info.art then asp = info.art.lw / info.art.lh
    elseif info and info.legacy and info.legacy.cfg.bundled then asp = info.legacy.cfg.aspect or 1 end
    local bw = math.min(W, H * asp)
    local bh = bw / asp
    V.bw, V.bh = bw, bh
    local cw, ch = bw * V.z, bh * V.z
    -- Clamp edge: map stays visible
    local minX, maxX = math.min(0, W - cw), math.max(0, W - cw)
    local minY, maxY = math.min(0, H - ch), math.max(0, H - ch)
    if V.z <= 1 then V.ox, V.oy = (W - cw) / 2, (H - ch) / 2 end
    V.ox = math.max(minX - 40, math.min(maxX + 40, V.ox))
    V.oy = math.max(minY - 40, math.min(maxY + 40, V.oy))
    local cv = host.canvas
    cv:SetSize(cw, ch)
    cv:ClearAllPoints()
    cv:SetPoint("TOPLEFT", host, "TOPLEFT", V.ox, -V.oy)
    -- Kacheln
    for _, t in ipairs(host.tiles) do t:Hide() end
    local n = 0
    local function tile()
        n = n + 1
        local t = host.tiles[n]
        if not t then t = cv:CreateTexture(nil, "ARTWORK") host.tiles[n] = t end
        t:ClearAllPoints()
        t:SetTexCoord(0, 1, 0, 1)
        t:Show()
        return t
    end
    host.grid:SetShown(false)
    if info and info.art then
        local a = info.art
        local s = cw / a.lw
        for r = 0, a.rows - 1 do
            for c = 0, a.cols - 1 do
                local f = a.tex[r * a.cols + c + 1]
                if f then
                    local t = tile()
                    local pw, ph = math.min(a.tw, a.lw - c * a.tw), math.min(a.th, a.lh - r * a.th)
                    t:SetTexture(f)
                    t:SetTexCoord(0, pw / a.tw, 0, ph / a.th)
                    t:SetSize(pw * s, ph * s)
                    t:SetPoint("TOPLEFT", cv, "TOPLEFT", c * a.tw * s, -r * a.th * s)
                end
            end
        end
    elseif info and info.legacy then
        local cfg, fl = info.legacy.cfg, info.legacy.floor
        if cfg.folder then
            for i = 1, 12 do
                local t = tile()
                local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
                t:SetTexture(cfg.special and ("Interface\\Worldmap\\" .. cfg.folder .. "\\" .. cfg.folder .. i)
                    or ("Interface\\Worldmap\\" .. cfg.folder .. "\\" .. cfg.folder .. fl .. "_" .. i))
                t:SetSize(cw / 4, ch / 3)
                t:SetPoint("TOPLEFT", cv, "TOPLEFT", c * cw / 4, -r * ch / 3)
            end
        elseif cfg.bundled then
            local t = tile()
            t:SetTexture(cfg.bundled)
            t:SetSize(cw, ch)
            t:SetPoint("TOPLEFT", cv, "TOPLEFT", 0, 0)
        end
    else
        host.grid:SetShown(true)
    end
    host.noArt:SetShown(info ~= nil and not info.art and not info.legacy)
    -- Grid without map image
    if host.grid:IsShown() then
        for i, g in ipairs(host.gridLines) do
            local vert = i <= 9
            local k = vert and i or i - 9
            g:ClearAllPoints()
            if vert then g:SetSize(1, ch) g:SetPoint("TOPLEFT", cv, "TOPLEFT", cw * k / 10, 0)
            else g:SetSize(cw, 1) g:SetPoint("TOPLEFT", cv, "TOPLEFT", 0, -ch * k / 10) end
        end
    end
    -- Drawings
    host.lineN, host.dotN = 0, 0
    local p = RB.board and RB.Plan() or nil
    local items = p and p.items or {}
    local th = math.max(2, math.min(5, 2 + V.z))
    for _, it in ipairs(items) do
        if it.k == "s" then
            local col = COLORS[it.c] or COLORS[1]
            for i = 1, #it.p - 3, 2 do seg(host, it.p[i] * cw, it.p[i + 1] * ch, it.p[i + 2] * cw, it.p[i + 3] * ch, col, th) end
        elseif it.k == "a" then
            arrow(host, it.x * cw, it.y * ch, it.x2 * cw, it.y2 * ch, COLORS[it.c] or COLORS[1], th + 1)
        end
    end
    -- laufender Strich / Pfeil
    local cur = RB.active
    if cur and cur.k == "s" and #cur.p >= 4 then
        local col = COLORS[cur.c] or COLORS[1]
        for i = 1, #cur.p - 3, 2 do seg(host, cur.p[i] * cw, cur.p[i + 1] * ch, cur.p[i + 2] * cw, cur.p[i + 3] * ch, col, th) end
    elseif cur and cur.k == "a" and cur.x2 then
        arrow(host, cur.x * cw, cur.y * ch, cur.x2 * cw, cur.y2 * ch, COLORS[cur.c] or COLORS[1], th + 1)
    end
    for i = host.lineN + 1, #host.lines do local l = host.lines[i] if l.isLine then l:Hide() end end
    for i = host.dotN + 1, #host.dots do host.dots[i]:Hide() end
    -- Marker
    local mi = 0
    local edit = RB.CanEdit()
    for _, it in ipairs(items) do
        if it.k == "m" or it.k == "p" or it.k == "l" then
            mi = mi + 1
            local m = markerFrame(host, mi)
            m.item = it
            m:EnableMouse(edit)
            m.ic:Hide() m.tx:SetText("") m.bg:SetColorTexture(0, 0, 0, 0)
            if it.k == "m" then
                local sz = 26
                m:SetSize(sz, sz)
                m.ic:SetSize(sz - 2, sz - 2)
                if ROLE_TEX[it.t] then
                    m.ic:SetTexture(ROLE_TEX[it.t])
                    local c = ROLE_COL[it.t]
                    m.ic:SetVertexColor(c[1], c[2], c[3])
                    m.bg:SetColorTexture(0, 0, 0, 0.55)
                else
                    m.ic:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. it.t)
                    m.ic:SetVertexColor(1, 1, 1)
                end
                m.ic:Show()
            elseif it.k == "p" then
                local r, g, b = ns.classColor(it.c)
                m.tx:SetText(ns.displayName(it.n))
                m.tx:SetTextColor(r or 1, g or 1, b or 1)
                m:SetSize(math.max(30, (m.tx:GetStringWidth() or 40) + 10), 18)
                m.bg:SetColorTexture(0, 0, 0, 0.7)
            else
                local c = COLORS[it.c] or COLORS[5]
                m.tx:SetText(it.s or "")
                m.tx:SetTextColor(c[1], c[2], c[3])
                m:SetSize(math.max(20, (m.tx:GetStringWidth() or 40) + 8), 18)
                m.bg:SetColorTexture(0, 0, 0, 0.45)
            end
            m:ClearAllPoints()
            m:SetPoint("CENTER", cv, "TOPLEFT", it.x * cw, -it.y * ch)
            m:Show()
        end
    end
    for i = mi + 1, #host.marks do host.marks[i]:Hide() host.marks[i].item = nil end
    RB.LayoutDots()
end

-- Group positions (only outside instances and when map = current map)
function RB.LayoutDots()
    local host = page and page.view
    if not host then return end
    local shown = 0
    local info = host.info
    local inInst = ns.Group.InInstance()
    if info and info.mapID and not inInst and C_Map and C_Map.GetPlayerMapPosition then
        local units = IsInGroup() and groupUnits() or { "player" }
        if IsInGroup() and not IsInRaid() then units = groupUnits() end
        for _, u in ipairs(units) do
            if UnitExists(u) then
                local ok, pos = pcall(C_Map.GetPlayerMapPosition, info.mapID, u)
                local x, y
                if ok and pos then
                    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
                end
                x, y = ns.safe(x), ns.safe(y)
                if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then
                    shown = shown + 1
                    local d = host.pdots[shown]
                    if not d then
                        d = host.canvas:CreateTexture(nil, "OVERLAY", nil, 7)
                        d:SetTexture(ns.MEDIA .. "dot")
                        host.pdots[shown] = d
                    end
                    local _, cls = UnitClass(u)
                    local r, g, b = ns.classColor(cls)
                    d:SetVertexColor(r or 1, g or 1, b or 1)
                    d:SetSize(u == "player" and 12 or 9, u == "player" and 12 or 9)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", host.canvas, "TOPLEFT", x * host.canvas:GetWidth(), -y * host.canvas:GetHeight())
                    d:Show()
                end
            end
        end
    end
    for i = shown + 1, #host.pdots do host.pdots[i]:Hide() end
    RB.dotsShown = shown
    RB.posLocked = inInst and true or false
end

------------------------------------------------------------------------
-- Maus
------------------------------------------------------------------------
-- Mouse position -> normalized (0..1) on the map, plus local pixels in the view
function RB.CursorPos()
    local host = page and page.view
    if not host then return 0.5, 0.5, 0, 0 end
    local cx, cy = GetCursorPosition()
    local s = host:GetEffectiveScale() or 1
    cx, cy = cx / s, cy / s
    local left, top = host:GetLeft() or 0, host:GetTop() or 0
    local lx, ly = cx - left, top - cy
    local cw, ch = host.canvas:GetWidth(), host.canvas:GetHeight()
    if not cw or cw <= 0 then cw, ch = V.bw or 1, V.bh or 1 end
    return (lx - V.ox) / cw, (ly - V.oy) / ch, lx, ly
end
function RB.Zoom(delta, lx, ly, nx, ny)
    local old = V.z
    V.z = math.max(1, math.min(6, V.z * (delta > 0 and 1.25 or 0.8)))
    if V.z == old then return end
    if V.z <= 1 then V.ox, V.oy = 0, 0
    elseif lx then
        V.ox = lx - nx * V.bw * V.z
        V.oy = ly - ny * V.bh * V.z
    end
    RB.Layout()
end
function RB.ResetView() V.z, V.ox, V.oy = 1, 0, 0 RB.Layout() end
local function startUpdate()
    if page and page.view then page.view:SetScript("OnUpdate", RB.OnUpdate) end
end
local function stopUpdate()
    if page and page.view then page.view:SetScript("OnUpdate", nil) end
end
function RB.StartDrag(it)
    pushUndo()
    RB.drag = { it = it, moved = false }
    startUpdate()
end
function RB.OnUpdate()
    local nx, ny, lx, ly = RB.CursorPos()
    if RB.pan then
        V.ox = RB.pan.ox + (lx - RB.pan.lx)
        V.oy = RB.pan.oy + (ly - RB.pan.ly)
        if math.abs(lx - RB.pan.lx) + math.abs(ly - RB.pan.ly) > 1 then RB.Layout() end
    elseif RB.drag then
        local it = RB.drag.it
        local dx, dy = nx - it.x, ny - it.y
        it.x, it.y = math.max(0, math.min(1, nx)), math.max(0, math.min(1, ny))
        if it.k == "a" then it.x2, it.y2 = it.x2 + dx, it.y2 + dy end
        RB.drag.moved = true
        RB.Layout()
    elseif RB.erasing then
        if not IsMouseButtonDown("LeftButton") then RB.erasing = nil stopUpdate() return end
        local it = RB.HitTest(nx, ny, 0.03 / V.z)
        if it then RB.Remove(it.id) end
    elseif RB.active then
        local a = RB.active
        if a.k == "s" then
            local px, py = a.p[#a.p - 1], a.p[#a.p]
            if math.abs(nx - px) + math.abs(ny - py) > 0.006 and #a.p < 400 then
                a.p[#a.p + 1] = math.max(0, math.min(1, nx))
                a.p[#a.p + 1] = math.max(0, math.min(1, ny))
                RB.Layout()
            end
        elseif a.k == "a" then
            a.x2, a.y2 = math.max(0, math.min(1, nx)), math.max(0, math.min(1, ny))
            RB.Layout()
        end
    end
    if page.ghost:IsShown() then
        page.ghost:ClearAllPoints()
        page.ghost:SetPoint("CENTER", page.view, "TOPLEFT", lx, -ly)
    end
end
function RB.MouseDown(btn)
    local nx, ny, lx, ly = RB.CursorPos()
    local edit = RB.CanEdit()
    if btn == "RightButton" or btn == "MiddleButton" or not edit or RB.tool == "move" then
        RB.pan = { ox = V.ox, oy = V.oy, lx = lx, ly = ly }
        startUpdate()
        return
    end
    if nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
    local t = RB.tool
    if t == "place" and RB.place then
        local pl = RB.place
        RB.Add({ k = pl.k, t = pl.t, n = pl.n, c = pl.c, x = nx, y = ny })
    elseif t == "label" then
        local s = clean(page.labelInput and page.labelInput:GetText() or "", 40)
        if s:match("%S") then RB.Add({ k = "l", s = s, c = RB.color, x = nx, y = ny }) end
    elseif t == "erase" then
        local it = RB.HitTest(nx, ny, 0.03 / V.z)
        if it then RB.Remove(it.id) end
        -- keep wiping while the mouse button is held
        RB.erasing = true
        startUpdate()
    elseif t == "draw" then
        RB.active = { k = "s", c = RB.color, p = { nx, ny } }
        startUpdate()
    elseif t == "arrow" then
        RB.active = { k = "a", c = RB.color, x = nx, y = ny }
        startUpdate()
    end
end
function RB.EndAction()
    RB.erasing = nil
    if RB.drag then
        local d = RB.drag
        RB.drag = nil
        if d.moved then changed() else table.remove(RB.undo) end
    end
    if RB.active then
        local a = RB.active
        RB.active = nil
        if a.k == "s" and #a.p >= 4 then RB.Add(a)
        elseif a.k == "a" and a.x2 and (math.abs(a.x2 - a.x) + math.abs(a.y2 - a.y)) > 0.01 then RB.Add(a)
        else RB.Layout() end
    end
    RB.pan = nil
    if not (page and page.ghost:IsShown()) then stopUpdate() end
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function setBoard(key, manual)
    if manual then RB.auto = false end
    if RB.board ~= key then RB.board = key V.z, V.ox, V.oy = 1, 0, 0 end
    ns.RefreshPage("raidboard")
end
function RB.SetTool(t, place)
    RB.tool = t
    RB.place = place
    if page then RB.UpdateTools() end
end
function RB.UpdateTools()
    if not page then return end
    for _, b in ipairs(page.toolBtns) do
        local on = (b.tool == RB.tool) and (b.tool ~= "place" or (RB.place and b.ptype == (RB.place.t or "P")))
        K.SetBorderColor(b, on and C.accent or C.line)
    end
    for i, sw in ipairs(page.swatches) do K.SetBorderColor(sw, i == RB.color and C.text or C.line) end
end
local function toolButton(parent, tex, tip, tool, ptype, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 30)
    K.Fill(b, C.raised)
    K.Border(b, C.line)
    b.tool, b.ptype = tool, ptype
    if tex then
        b.ic = b:CreateTexture(nil, "ARTWORK")
        b.ic:SetPoint("CENTER")
        b.ic:SetSize(22, 22)
        b.ic:SetTexture(tex)
    else
        b.tx = K.Text(b, 12, C.text, "CENTER")
        b.tx:SetPoint("CENTER")
        b.tx:SetText(text or "?")
    end
    b:SetScript("OnEnter", function(self) K.ShowTip(self, tip) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
-- Palette button: click = placement tool; hold and drag onto the map = place directly
local function paletteButton(parent, tex, tip, place, col)
    local b = toolButton(parent, tex, tip, "place", place.t or "P")
    if col and b.ic then b.ic:SetVertexColor(col[1], col[2], col[3]) end
    b:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        RB.SetTool("place", place)
        page.ghost.ic:SetTexture(tex)
        if col then page.ghost.ic:SetVertexColor(col[1], col[2], col[3]) else page.ghost.ic:SetVertexColor(1, 1, 1) end
        page.ghost:Show()
        startUpdate()
    end)
    b:SetScript("OnMouseUp", function()
        page.ghost:Hide()
        stopUpdate()
        if page.view:IsMouseOver() then
            local nx, ny = RB.CursorPos()
            if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then RB.Add({ k = place.k, t = place.t, n = place.n, c = place.c, x = nx, y = ny }) end
        end
    end)
    return b
end

ns.RegisterPage({
    key = "raidboard", title = "Tactics map", order = 2.765,
    sub = "Instance map with positions – the raid leader draws, everyone sees it",
    build = function(p)
        page = p
        -- Kopfzeile
        p.mapBtn = K.Button(p, "", 230, 24, "ghost", function(self)
            local items = { { text = L["Automatic (current location)"], checked = RB.auto, fn = function() RB.auto = true ns.RefreshPage("raidboard") end } }
            for _, e in ipairs(RB.Catalog()) do
                items[#items + 1] = { text = (e.raid and "|cffffc85a" or "") .. e.text .. (e.raid and "|r" or ""), checked = RB.board == e.key and not RB.auto,
                    fn = function() setBoard(e.key, true) end }
            end
            K.ShowMenu(self, items, L["Map"], 230)
        end)
        p.mapBtn:SetPoint("TOPLEFT", 0, 0)
        p.mapBtn.label:ClearAllPoints()
        p.mapBtn.label:SetPoint("LEFT", 10, 0)
        p.mapBtn.label:SetPoint("RIGHT", -10, 0)
        p.mapBtn.label:SetJustifyH("LEFT")
        p.floorBtn = K.Button(p, L["Level"], 120, 24, "ghost", function(self)
            local info = p.view.info
            if not info or not info.floors then return end
            local items = {}
            for _, f in ipairs(info.floors) do
                local key = f.key or ("m" .. f.map)
                items[#items + 1] = { text = f.name or key, checked = key == RB.board, fn = function() setBoard(key, true) end }
            end
            K.ShowMenu(self, items, L["Level"], 160)
        end)
        p.floorBtn:SetPoint("LEFT", p.mapBtn, "RIGHT", 6, 0)
        local segs = {}
        for _, k in ipairs(PLANS) do segs[#segs + 1] = { key = k, text = L["Plan"] .. " " .. k } end
        p.seg = K.Segments(p, segs, function(k)
            RB.plan = k
            if iAmLead() then RB.Send() end
            ns.RefreshPage("raidboard")
        end, 60)
        p.seg:SetPoint("TOPRIGHT", -96, 0)
        p.reset = K.Button(p, L["Reset view"], 90, 24, "ghost", function() RB.ResetView() end)
        p.reset:SetPoint("TOPRIGHT", 0, 0)
        -- Werkzeugleiste links
        p.bar = CreateFrame("Frame", nil, p)
        p.bar:SetPoint("TOPLEFT", 0, -32)
        if K.LeadTag then p.leadTag = K.LeadTag(p.bar) p.leadTag:SetPoint("LEFT", p.mapBtn, "RIGHT", 136, 0) end
        p.bar:SetPoint("BOTTOMLEFT", 0, 22)
        p.bar:SetWidth(66)
        p.toolBtns = {}
        local defs = {
            { "move", "Interface\\CURSOR\\Point", { L["Move"], L["Drag the map, move markers"] } },
            { "draw", ICON .. "brush", { L["Draw"], L["Hold the left mouse button to draw"] } },
            { "arrow", "Interface\\MINIMAP\\ROTATING-MINIMAPGUIDEARROW", { L["Arrow"], L["Drag from start to end"] } },
            { "label", nil, { L["Text"], L["Enter text below, then click on the map"] }, "Aa" },
            { "erase", ICON .. "eraser", { L["Eraser"], L["Click or hold the mouse button and swipe over lines, arrows and markers"] } },
        }
        local btns = {}
        for _, d in ipairs(defs) do
            local b = toolButton(p.bar, d[2], d[3], d[1], nil, d[4])
            b:SetScript("OnClick", function() RB.SetTool(d[1]) end)
            btns[#btns + 1] = b
        end
        for _, r in ipairs({ "T", "H", "D" }) do
            btns[#btns + 1] = paletteButton(p.bar, ROLE_TEX[r], { L[ROLE_NAME[r]], L["Click or drag onto the map"] }, { k = "m", t = r }, ROLE_COL[r])
        end
        for i = 1, 8 do
            btns[#btns + 1] = paletteButton(p.bar, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i, { L["Raid marker"] .. " " .. i, L["Click or drag onto the map"] }, { k = "m", t = tostring(i) })
        end
        local pb = toolButton(p.bar, ICON .. "profile", { L["Player"], L["Pick a group member, then click on the map"] }, "place", "P")
        pb:SetScript("OnClick", function(self)
            local items = {}
            for _, m in ipairs(RB.Members()) do
                items[#items + 1] = { text = ns.Radar and ns.Radar.Colored and ns.Radar.Colored(m.n) or ns.displayName(m.n), fn = function() RB.SetTool("place", { k = "p", n = m.n, c = m.c, t = "P" }) end }
            end
            K.ShowMenu(self, items, L["Player"], 160)
        end)
        btns[#btns + 1] = pb
        for i, b in ipairs(btns) do
            b:SetPoint("TOPLEFT", ((i - 1) % 2) * 34, -math.floor((i - 1) / 2) * 34)
            p.toolBtns[#p.toolBtns + 1] = b
        end
        local y = -math.ceil(#btns / 2) * 34 - 4
        p.swatches = {}
        for i, c in ipairs(COLORS) do
            local sw = CreateFrame("Button", nil, p.bar)
            sw:SetSize(12, 12)
            sw.bg = sw:CreateTexture(nil, "ARTWORK")
            sw.bg:SetPoint("TOPLEFT", 1, -1) sw.bg:SetPoint("BOTTOMRIGHT", -1, 1)
            sw.bg:SetColorTexture(c[1], c[2], c[3], 1)
            K.Border(sw, C.line)
            sw:SetPoint("TOPLEFT", (i - 1) * 13, y)
            sw:SetScript("OnClick", function() RB.color = i RB.UpdateTools() end)
            sw:SetScript("OnEnter", function(self) K.ShowTip(self, L[COLOR_NAMES[i]]) end)
            sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.swatches[i] = sw
        end
        p.undoBtn = K.Button(p.bar, L["Undo"], 64, 22, "ghost", function() RB.Undo() end)
        p.undoBtn:SetPoint("TOPLEFT", 0, y - 18)
        p.clearBtn = K.Button(p.bar, L["Clear"], 64, 22, "danger", function() RB.Clear() end)
        p.clearBtn:SetPoint("TOPLEFT", 0, y - 44)
        p.sendBtn = K.Button(p.bar, L["Send"], 64, 22, "primary", function()
            if RB.SendNow() then K.Toast(L["Tactics map"], L["Positions sent to the group"], C.mint) end
        end)
        p.sendBtn:SetPoint("TOPLEFT", 0, y - 70)
        -- Kartenansicht
        local view = CreateFrame("Frame", nil, p)
        p.view = view
        view:SetPoint("TOPLEFT", 74, -32)
        view:SetPoint("BOTTOMRIGHT", 0, 22)
        if view.SetClipsChildren then view:SetClipsChildren(true) end
        K.Fill(view, C.field)
        K.Border(view, C.line)
        view:EnableMouse(true)
        if view.EnableMouseWheel then view:EnableMouseWheel(true) end
        view.canvas = CreateFrame("Frame", nil, view)
        view.canvas:SetPoint("TOPLEFT")
        view.canvas:SetSize(100, 100)
        view.tiles, view.lines, view.dots, view.marks, view.pdots = {}, {}, {}, {}, {}
        view.lineN, view.dotN = 0, 0
        view.grid = CreateFrame("Frame", nil, view.canvas)
        view.grid:SetAllPoints()
        view.gridLines = {}
        for i = 1, 18 do
            local g = view.grid:CreateTexture(nil, "BACKGROUND", nil, 3)
            g:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
            view.gridLines[i] = g
        end
        view.noArt = K.Text(view, 11, C.dim, "CENTER")
        view.noArt:SetPoint("BOTTOM", 0, 8)
        view.noArt:SetText(L["No map art for this instance – plan on a grid"])
        view:SetScript("OnMouseWheel", function(_, delta)
            local nx, ny, lx, ly = RB.CursorPos()
            RB.Zoom(delta, lx, ly, nx, ny)
        end)
        view:SetScript("OnMouseDown", function(_, btn) RB.MouseDown(btn) end)
        view:SetScript("OnMouseUp", function() RB.EndAction() end)
        view:SetScript("OnSizeChanged", function() RB.Layout() end)
        p.ghost = CreateFrame("Frame", nil, view)
        p.ghost:SetSize(26, 26)
        p.ghost:SetFrameLevel(view:GetFrameLevel() + 20)
        p.ghost.ic = p.ghost:CreateTexture(nil, "OVERLAY")
        p.ghost.ic:SetAllPoints()
        p.ghost:Hide()
        -- Fusszeile
        p.labelInput = K.Input(p, 160, L["Label text"])
        p.labelInput:SetPoint("BOTTOMLEFT", 74, -2)
        p.status = K.Text(p, 11, C.muted)
        p.status:SetPoint("BOTTOMRIGHT", 0, 4)
        p.status:SetJustifyH("RIGHT")
        p.follow = K.Toggle and K.Toggle(p, L["Follow leader"], function() return RB.follow end, function(v) RB.follow = v end) or nil
        if p.follow then p.follow:SetPoint("BOTTOMLEFT", 244, 0) p.follow:SetWidth(130) end
        -- only when visible: refresh positions every second
        p:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            if self.acc < 1 then return end
            self.acc = 0
            if RB.auto and not RB.pan and not RB.drag and not RB.active then
                local d = RB.Detect()
                if d and d ~= RB.board then ns.RefreshPage("raidboard") return end
            end
            if not ns.Group.InInstance() then RB.LayoutDots() end
        end)
        p:SetScript("OnShow", function() RB.Request() end)
        RB.Request()
    end,
    refresh = function(p)
        if RB.auto then
            local d = RB.Detect()
            if d then RB.board = d end
        end
        -- Raid simulator: on start jump once to the simulated raid's map (freely selectable afterwards)
        if simOn() then
            local d = RB.Detect()
            if d and RB.simFor ~= d then RB.board, RB.simFor = d, d end
        end
        if not RB.board and ns.Demo and ns.Demo.IsActive() then RB.board = "m248" end
        if not RB.board then RB.board = RAIDS[1].key end
        local info = RB.BoardInfo(RB.board)
        if not p.view.info or p.view.info.key ~= RB.board then V.z, V.ox, V.oy = 1, 0, 0 end
        p.view.info = info
        p.mapBtn.label:SetText((RB.auto and (K.hex(C.accent) .. L["Auto"] .. ":|r ") or "") .. (info and info.title or "-"))
        p.floorBtn:SetShown(info and info.floors ~= nil)
        p.seg:Select(RB.plan)
        local edit = RB.CanEdit()
        -- Tools stay visible, dimmed and locked for the unauthorized (only in raid)
        p.bar:Show()
        if not p.barLock then p.barLock = K.Lock(p.bar, { who = "raidlead", compact = true, check = RB.CanEdit }) end
        p.barLock:Update()
        p.labelInput:Show()
        p.labelInput:EnableMouse(edit)
        p.labelInput:SetAlpha(edit and 1 or 0.4)
        if not edit then p.labelInput:ClearFocus() end
        p.view:ClearAllPoints()
        p.view:SetPoint("TOPLEFT", 74, -32)
        p.view:SetPoint("BOTTOMRIGHT", 0, 22)
        p.sendBtn:SetShown(canSend())
        if p.follow then p.follow:SetShown(not iAmLead()) end
        RB.UpdateTools()
        RB.Layout()
        local plan = RB.Plan()
        local st = {}
        if plan and plan.by and not ns.isMe(plan.by) then st[#st + 1] = (L["by %s"]):format(ns.displayName(plan.by)) end
        if RB.posLocked then st[#st + 1] = L["Positions are locked in instances – plan only"]
        elseif (RB.dotsShown or 0) > 0 then st[#st + 1] = (L["%d positions"]):format(RB.dotsShown) end
        if not edit then st[#st + 1] = L["View only – the raid leader draws"] end
        st[#st + 1] = L["Mouse wheel = zoom, right mouse button = pan"]
        p.status:SetText(table.concat(st, "  |cff555555-|r  "))
    end,
})

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------
local wasInGroup = false
ns.On("GROUP_ROSTER_UPDATE", function()
    local now = IsInGroup()
    if now and not wasInGroup then ns.After(3, RB.Request) end
    wasInGroup = now
    ns.RefreshPage("raidboard")
end)
ns.On("PLAYER_ENTERING_WORLD", function()
    ns.After(2, function() if RB.auto then ns.RefreshPage("raidboard") end end)
end)
ns.On("ZONE_CHANGED_NEW_AREA", function()
    if IsInGroup() and IsInInstance() then ns.After(4, RB.Request) end
    ns.RefreshPage("raidboard")
end)

------------------------------------------------------------------------
-- Demo: sample lineup for Onyxia
------------------------------------------------------------------------
function RB.SeedDemo()
    local b = store()["m248"]
    if b and b.plans and b.plans.A and #b.plans.A.items > 0 and not b.demo then return end
    local items = {
        { k = "m", t = "T", x = 0.50, y = 0.30 }, { k = "p", n = "Grukthar", c = "WARRIOR", x = 0.50, y = 0.25 },
        { k = "m", t = "8", x = 0.50, y = 0.36 },
        { k = "m", t = "H", x = 0.40, y = 0.50 }, { k = "p", n = "Zul'mira", c = "PRIEST", x = 0.40, y = 0.55 },
        { k = "m", t = "H", x = 0.60, y = 0.50 }, { k = "p", n = "Hoknar", c = "SHAMAN", x = 0.60, y = 0.55 },
        { k = "m", t = "D", x = 0.35, y = 0.34 }, { k = "p", n = "Tavira", c = "MAGE", x = 0.33, y = 0.39 },
        { k = "m", t = "D", x = 0.65, y = 0.34 }, { k = "p", n = "Mokrash", c = "HUNTER", x = 0.67, y = 0.39 },
        { k = "m", t = "1", x = 0.20, y = 0.30 }, { k = "m", t = "2", x = 0.80, y = 0.30 },
        { k = "l", c = 2, s = "Welpen links", x = 0.20, y = 0.24 }, { k = "l", c = 2, s = "Welpen rechts", x = 0.80, y = 0.24 },
        { k = "a", c = 1, x = 0.50, y = 0.80, x2 = 0.50, y2 = 0.42 },
        { k = "l", c = 1, s = "Phase 2: nicht unter Onyxia stehen", x = 0.50, y = 0.86 },
        { k = "s", c = 4, p = { 0.30, 0.62, 0.40, 0.68, 0.50, 0.70, 0.60, 0.68, 0.70, 0.62 } },
    }
    for i, it in ipairs(items) do it.id = i end
    store()["m248"] = { demo = true, plans = { A = { items = items, nid = #items, rev = 1, ts = ns.now(), by = "Grukthar" } } }
    ns.RefreshPage("raidboard")
end
function RB.RemoveDemo()
    local b = store()["m248"]
    if b and b.demo then store()["m248"] = nil end
    ns.RefreshPage("raidboard")
end
ns.Listen("LOGIN", function()
    wasInGroup = IsInGroup()
    local D = ns.Demo
    if D and not D.boardHooked then
        D.boardHooked = true
        local load, remove = D.Load, D.Remove
        -- no prebuilt demo lineup anymore; remove old demo plans
        D.Remove = function(...) remove(...) RB.RemoveDemo() end
        ns.After(3, RB.RemoveDemo)
    end
end)

------------------------------------------------------------------------
-- /oa probe raidboard
------------------------------------------------------------------------
ns.Probes = ns.Probes or {}
ns.Probes.raidboard = function()
    local mid
    if C_Map and C_Map.GetBestMapForUnit then local ok, m = pcall(C_Map.GetBestMapForUnit, "player") mid = ok and m or nil end
    ns.print("Taktik-Karte: BestMap=" .. tostring(mid) .. " Instanz=" .. tostring((GetInstanceInfo and GetInstanceInfo())) .. " erkannt=" .. tostring(RB.Detect()))
    ns.print("  C_Map.GetMapArtLayers=" .. tostring(C_Map and C_Map.GetMapArtLayers ~= nil) .. " GetMapArtLayerTextures=" .. tostring(C_Map and C_Map.GetMapArtLayerTextures ~= nil)
        .. " GetMapGroupMembersInfo=" .. tostring(C_Map and C_Map.GetMapGroupMembersInfo ~= nil))
    if mid then
        local a = artOf(mid)
        ns.print("  Kartengrafik: " .. (a and (a.cols .. "x" .. a.rows .. " Kacheln, " .. a.lw .. "x" .. a.lh) or "keine"))
        local fl = floorsOf(mid)
        ns.print("  Ebenen: " .. (fl and #fl or 0))
    end
    for _, r in ipairs(RAIDS) do
        if r.map then local a = artOf(r.map) ns.print("  " .. r.name .. " (" .. r.map .. "): " .. (a and "Grafik ok" or "keine Grafik")) end
    end
    local f = CreateFrame("Frame")
    ns.print("  CreateLine=" .. tostring(f.CreateLine ~= nil) .. " SetClipsChildren=" .. tostring(f.SetClipsChildren ~= nil))
end
end)

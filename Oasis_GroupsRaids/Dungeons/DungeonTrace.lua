-- Oasis - self-explored dungeon maps: for dungeons without a map in the client (new Forever dungeons)
-- Oasis remembers the paths of Oasis players (coarse grid) and where bosses were killed.
-- From this the dungeon view builds an outline map. Shared via normal sync.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Dungeons", function()   -- Module Dungeons (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C
local Store = ns.Store

local DT = {}
ns.DungeonTrace = DT
local CELL = 4          -- Grid size in meters (world coordinates)
local MAX_CELLS = 900   -- per player and dungeon

local function key(name) return (tostring(name or "?"):lower():gsub("[^%w]", "")) end
local function mine(inst)
    ns.db.trace = ns.db.trace or {}
    local t = ns.db.trace[inst]
    if not t then t = { cells = {}, n = 0, bosses = {} } ns.db.trace[inst] = t end
    return t
end

-- Position in dungeon: world coordinates (works even without a map in the client)
local function worldPos()
    if not UnitPosition then return nil end
    local ok, y, x = pcall(UnitPosition, "player")
    if not ok or not x or not y then return nil end
    return x, y
end
local dirty = false
local function sample()
    local inInst, kind = IsInInstance()
    if not (inInst and (kind == "party" or kind == "raid")) then return end
    local x, y = worldPos()
    if not x then return end
    local inst = key(ns.safe(GetInstanceInfo()))
    local t = mine(inst)
    if t.n >= MAX_CELLS then return end
    local c = math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
    if not t.cells[c] then t.cells[c] = true t.n = t.n + 1 dirty = true end
end
ns.On("ENCOUNTER_END", function(_, encName, _, _, success)
    if ns.safe(success) ~= 1 then return end
    local inInst = IsInInstance()
    if not inInst then return end
    local x, y = worldPos()
    if not x then return end
    local inst = key(ns.safe(GetInstanceInfo()))
    local t = mine(inst)
    t.bosses[ns.safe(encName) or "?"] = math.floor(x) .. ":" .. math.floor(y)
    dirty = true
end)

-- share: one record per player and dungeon (cells as text)
local function share()
    if not dirty or not ns.db.trace or ns.db.settings.shareTrace == false then return end
    dirty = false
    for inst, t in pairs(ns.db.trace) do
        local cells = {}
        for c in pairs(t.cells) do cells[#cells + 1] = c end
        local bosses = {}
        for name, pos in pairs(t.bosses) do bosses[#bosses + 1] = name:gsub("[,=]", " ") .. "=" .. pos end
        Store.Put("trace", { id = inst .. "@" .. ns.me(), inst = inst, c = table.concat(cells, ","), b = table.concat(bosses, ","), ts = ns.now() })
    end
end
ns.Listen("LOGIN", function()
    C_Timer.NewTicker(2, function() pcall(sample) end)
    ns.Every(300, function() pcall(share) end)
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(5, function() pcall(share) end) end)

-- all data for a dungeon (own + shared): cell set, bosses, bounds
function DT.Get(dungeonName, altName)
    local keys = { [key(dungeonName)] = true }
    if altName then keys[key(altName)] = true end
    local cells, bosses, players = {}, {}, {}
    local function addCells(s, who)
        for c in tostring(s or ""):gmatch("[^,]+") do cells[c] = true end
        if who then players[who] = true end
    end
    for k in pairs(keys) do
        local t = ns.db.trace and ns.db.trace[k]
        if t then
            for c in pairs(t.cells) do cells[c] = true end
            for n, pos in pairs(t.bosses) do bosses[n] = pos end
            players[ns.me()] = true
        end
    end
    for _, r in ipairs(Store.List("trace", function(r) return keys[r.inst] end)) do
        addCells(r.c, r.by)
        for pair in tostring(r.b or ""):gmatch("[^,]+") do
            local n, pos = pair:match("^(.-)=(.+)$")
            if n and not bosses[n] then bosses[n] = pos end
        end
    end
    local minX, maxX, minY, maxY, n = math.huge, -math.huge, math.huge, -math.huge, 0
    local list = {}
    for c in pairs(cells) do
        local x, y = c:match("^(%-?%d+):(%-?%d+)$")
        x, y = tonumber(x), tonumber(y)
        if x then
            n = n + 1
            list[#list + 1] = { x, y }
            minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
        end
    end
    local np = 0
    for _ in pairs(players) do np = np + 1 end
    return { cells = list, n = n, bosses = bosses, minX = minX, maxX = maxX, minY = minY, maxY = maxY, players = np }
end

-- Draw outline: north up (world X upward, world Y to the left)
function DT.Draw(host, data)
    host.traceTex = host.traceTex or {}
    host.tracePins = host.tracePins or {}
    for _, t in ipairs(host.traceTex) do t:Hide() end
    for _, p in ipairs(host.tracePins) do p:Hide() end
    if not data or data.n < 10 then return false end
    local W, H = host:GetWidth(), host:GetHeight()
    if W < 50 then W, H = 600, 400 end
    local spanX = (data.maxY - data.minY + 1)   -- Screen width = world Y
    local spanY = (data.maxX - data.minX + 1)   -- Screen height = world X
    local s = math.min((W - 40) / spanX, (H - 40) / spanY)
    local ox = (W - spanX * s) / 2
    local oy = (H - spanY * s) / 2
    local function toScreen(wx, wy)   -- Weltkoordinaten in Rastereinheiten
        return ox + (data.maxY - wy + 0.5) * s, oy + (data.maxX - wx + 0.5) * s
    end
    for i, cxy in ipairs(data.cells) do
        local t = host.traceTex[i]
        if not t then
            t = host:CreateTexture(nil, "ARTWORK")
            t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            host.traceTex[i] = t
        end
        local sx, sy = toScreen(cxy[1], cxy[2])
        t:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 0.55)
        t:SetSize(math.max(4, s * 2.2), math.max(4, s * 2.2))
        t:ClearAllPoints()
        t:SetPoint("CENTER", host, "TOPLEFT", sx, -sy)
        t:Show()
    end
    local i = 0
    for name, pos in pairs(data.bosses) do
        local wx, wy = pos:match("^(%-?%d+):(%-?%d+)$")
        wx, wy = tonumber(wx), tonumber(wy)
        if wx then
            i = i + 1
            local p = host.tracePins[i]
            if not p then
                p = CreateFrame("Frame", nil, host)
                p:SetSize(20, 20)
                p.dot = p:CreateTexture(nil, "OVERLAY")
                p.dot:SetTexture(ns.MEDIA .. "dot")
                p.dot:SetAllPoints()
                p.dot:SetVertexColor(C.red[1], C.red[2], C.red[3])
                p.lbl = K.Text(p, 10, C.text, "CENTER")
                p.lbl:SetPoint("TOP", p, "BOTTOM", 0, -1)
                p.lbl:SetShadowOffset(1, -1)
                host.tracePins[i] = p
            end
            local sx, sy = toScreen(wx / CELL, wy / CELL)
            p:SetFrameLevel(host:GetFrameLevel() + 10)
            p:ClearAllPoints()
            p:SetPoint("CENTER", host, "TOPLEFT", sx, -sy)
            p.lbl:SetText(name)
            p:Show()
        end
    end
    return true
end
end)

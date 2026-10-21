-- Oasis: gathering helpers on top of the minimap scan (0.6.592)
--   * arrow: points to the nearest herb or ore (dots on the minimap right now, else known guild nodes)
--   * map pin: the game's own pin on that node, so the in-world marker shows the way
--   * sparkles: gold sparkles on the herb or ore nameplate in front of you (game's soft interact plates)
-- All three are off by default (Settings > Areas > Map > Guild gathering map, or /oa gatherarrow, gathersparkle, gatherpin).
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local L = ns.L
local GM = ns.Gather
if not GM then return end

local GS = {}
ns.GatherSight = GS

local function S() return ns.db.settings end
local atan2 = math.atan2 or math.atan
local LIVE_FOR = 8      -- seconds a scanned dot counts as "there right now"
local FAR = 300         -- meters: known nodes further away are ignored
local AT = 6            -- meters: the node you stand at is skipped
local SPARKLE = 984391  -- the game's gathering node sparkle

local function here()
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    local w, h = C_Map.GetMapWorldSize(map)
    if not x or x == 0 or not w or w == 0 then return nil end
    return map, x, y, w, h
end

-- nearest node: dots seen on the minimap in the last seconds win, otherwise visible known nodes nearby
function GS.Nearest()
    if ns.inInstance() then return nil end
    local map, mx, my, w, h = here()
    if not map then return nil end
    local best, bd
    local function try(r)
        if r.map ~= map then return end
        local dx, dy = (r.x - mx) * w, (r.y - my) * h
        local d = math.sqrt(dx * dx + dy * dy)
        if d > AT and d <= FAR and (not bd or d < bd) then best, bd = r, d end
    end
    local now = GetTime and GetTime() or 0
    if GM.scanLive and now - (GM.scanLiveAt or 0) <= LIVE_FOR then
        for _, r in ipairs(GM.scanLive) do if GM.OwnKind(r.kind) then try(r) end end
    end
    if not best then
        local t = ns.now()
        for _, r in ipairs(GM.Nodes(map)) do
            if (r.kind == "herb" or r.kind == "ore") and GM.Shown(r) and not GM.Harvested(r, t) then try(r) end
        end
    end
    if not best then return nil end
    local dx, dy = (best.x - mx) * w, (best.y - my) * h
    return best, bd, atan2(-dx, -dy)   -- bearing: radians counterclockwise from north (like GetPlayerFacing)
end

------------------------------------------------------------------------
-- arrow
------------------------------------------------------------------------
local arrow
local function makeArrow()
    arrow = CreateFrame("Frame", "OasisGatherArrow", UIParent)
    arrow:SetSize(56, 56)
    local p = S().gatherArrowPos
    if p then arrow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2]) else arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 200) end
    arrow:SetMovable(true) arrow:EnableMouse(true) arrow:RegisterForDrag("LeftButton")
    arrow:SetClampedToScreen(true)
    arrow:SetScript("OnDragStart", arrow.StartMoving)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        S().gatherArrowPos = { math.floor(x), math.floor(y) }
    end)
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetAllPoints()
    if not (arrow.tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("MiniMap-QuestArrow") and arrow.tex:SetAtlas("MiniMap-QuestArrow") ~= false) then
        arrow.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
    arrow.icon:SetSize(18, 18)
    arrow.icon:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow.text:SetPoint("TOP", arrow.icon, "BOTTOM", 0, -2)
    arrow:Hide()
end
local function updateArrow(r, d, bearing)
    if not S().gatherArrow or not r then if arrow then arrow:Hide() end return end
    if not arrow then makeArrow() end
    local facing = ns.safe(GetPlayerFacing and GetPlayerFacing())
    if type(facing) ~= "number" then arrow:Hide() return end
    arrow.tex:SetRotation(bearing - facing)
    local k = GM.KINDS[r.kind]
    arrow.icon:SetTexture(k and k.icon)
    arrow.text:SetText(("%s  |cffffd100%d m|r"):format(r.name or "", math.floor(d + 0.5)))
    arrow:Show()
end

------------------------------------------------------------------------
-- map pin (the game's user waypoint + super track = marker in the world)
------------------------------------------------------------------------
local ourPin   -- { map, x, y } of the pin we set
local function samePin(wp)
    return wp and ourPin and wp.uiMapID == ourPin[1] and wp.position
        and math.abs(wp.position.x - ourPin[2]) < 0.0005 and math.abs(wp.position.y - ourPin[3]) < 0.0005
end
local function clearPin()
    if ourPin and C_Map.GetUserWaypoint and samePin(C_Map.GetUserWaypoint()) then pcall(C_Map.ClearUserWaypoint) end
    ourPin = nil
end
GS.ClearPin = clearPin
local function updatePin(r)
    if not (C_Map.SetUserWaypoint and UiMapPoint and C_SuperTrack) then return end
    if not S().gatherPin or not r then clearPin() return end
    if InCombatLockdown and InCombatLockdown() then return end
    if WorldMapFrame and WorldMapFrame:IsShown() then return end   -- the map builds its pin frame then (taint)
    local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if wp and not samePin(wp) then ourPin = nil return end          -- the player's own pin: hands off
    if ourPin and ourPin[1] == r.map and math.abs(ourPin[2] - r.x) < 0.0005 and math.abs(ourPin[3] - r.y) < 0.0005 then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(r.map) then return end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(r.map, r.x, r.y))
    if ok then
        ourPin = { r.map, r.x, r.y }
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end

------------------------------------------------------------------------
-- sparkles on the soft interact nameplate of a herb or ore
------------------------------------------------------------------------
local CVARS = {
    { "softTargetInteract", "3" },
    { "SoftTargetIconGameObject", "1" },
    { "SoftTargetInteractArc", "2" },
    { "SoftTargetInteractRange", "30" },
}
local function getCVar(n) return (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(n)) or (GetCVar and GetCVar(n)) end
local function setCVar(n, v) if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, n, v) elseif SetCVar then pcall(SetCVar, n, v) end end
local function applyCVars(on)
    if InCombatLockdown and InCombatLockdown() then GS.pendingCVars = true return end
    GS.pendingCVars = nil
    local saved = S().gatherSparkleSaved
    if on then
        if saved then return end
        saved = {}
        for _, c in ipairs(CVARS) do saved[c[1]] = getCVar(c[1]) or false setCVar(c[1], c[2]) end
        S().gatherSparkleSaved = saved
    elseif saved then
        for _, c in ipairs(CVARS) do
            local old = saved[c[1]]
            -- only put it back if nobody changed it since
            if old and tonumber(getCVar(c[1])) == tonumber(c[2]) then setCVar(c[1], old) end
        end
        S().gatherSparkleSaved = nil
    end
end
local plates, spare, active = {}, {}, {}
local function newSparkles()
    local f = CreateFrame("Frame")
    f:SetSize(90, 90)
    f.parts = {}
    for i = 1, 8 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(SPARKLE)
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.85, 0.35)
        t.phase, t.speed = math.random() * 6.28, 1.5 + math.random() * 1.5
        t.size = 14 + math.random() * 12
        t:SetSize(t.size, t.size)
        t:SetPoint("CENTER", f, "CENTER", (math.random() - 0.5) * 70, (math.random() - 0.5) * 70)
        f.parts[i] = t
    end
    return f
end
local function showOn(plate)
    local f = plates[plate]
    if not f then
        f = table.remove(spare) or newSparkles()
        f:SetParent(plate)
        f:ClearAllPoints()
        f:SetPoint("CENTER", plate, "BOTTOM", 0, -50)
        plates[plate] = f
        active[f] = true
    end
    f:Show()
end
local function hideOn(plate)
    local f = plates[plate]
    if not f then return end
    f:Hide() f:SetParent(nil)
    plates[plate], active[f] = nil, nil
    spare[#spare + 1] = f
end
GS.plates = plates
function GS.PlateUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local name = S().gatherSparkle and ns.safe(UnitName(unit))
    local kind = type(name) == "string" and GM.KindForName(name)
    if kind and GM.OwnKind(kind) then showOn(plate) else hideOn(plate) end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) pcall(GS.PlateUnit, unit) end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate then hideOn(plate) end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if GS.pendingCVars then applyCVars(S().gatherSparkle and true or false) end end)

------------------------------------------------------------------------
-- tick
------------------------------------------------------------------------
local acc, pinAcc = 0, 0
function GS.Tick(el)
    el = el or 0
    -- twinkle (only while sparkles are visible)
    if next(active) then
        local t = GetTime and GetTime() or 0
        for f in pairs(active) do
            for _, p in ipairs(f.parts) do
                local a = 0.5 + 0.5 * math.sin(t * p.speed + p.phase)
                p:SetAlpha(a * a)
            end
        end
    end
    acc, pinAcc = acc + el, pinAcc + el
    if acc < 0.05 then return end
    acc = 0
    if not (S().gatherArrow or S().gatherPin) then
        if arrow then arrow:Hide() end
        return
    end
    local r, d, b = GS.Nearest()
    updateArrow(r, d, b)
    if pinAcc >= 1 then pinAcc = 0 updatePin(r) end
end
CreateFrame("Frame"):SetScript("OnUpdate", function(_, el) GS.Tick(el) end)

-- settings changed (toggle in the settings or slash command)
function GS.Apply()
    applyCVars(S().gatherSparkle and true or false)
    if not S().gatherSparkle then for plate in pairs(plates) do hideOn(plate) end end
    if not S().gatherPin then clearPin() end
    if not S().gatherArrow and arrow then arrow:Hide() end
end
ns.On("PLAYER_LOGIN", function() if S().gatherSparkle or S().gatherSparkleSaved then GS.Apply() end end)
if ns.db and ns.db.settings and (S().gatherSparkle or S().gatherSparkleSaved) then GS.Apply() end

local function toggle(key, on, off)
    return function()
        S()[key] = not S()[key] or nil
        GS.Apply()
        ns.print(S()[key] and L[on] or L[off])
    end
end
ns.slash.gatherarrow = toggle("gatherArrow", "Arrow to the nearest node on.", "Arrow to the nearest node off.")
ns.slash.gathersparkle = toggle("gatherSparkle", "Sparkles on.", "Sparkles off.")
ns.slash.gatherpin = toggle("gatherPin", "Map pin on the nearest node on.", "Map pin on the nearest node off.")
ns.slash.sammelpfeil, ns.slash.glitzern, ns.slash.sammelpin = ns.slash.gatherarrow, ns.slash.gathersparkle, ns.slash.gatherpin
end)

-- Oasis: world map extras (0.6.604) - what WoW Forever does not bring itself
--   * move the world map and scale it (windowed and maximised kept apart)
--   * tint for the revealed unexplored areas (color + opacity, see ComfortPlus reveal)
--   * no reading emote when the map opens
--   * hide town and city icons on the continent and world maps
-- Coordinates, map fade while moving and the zone map's lock/opacity are already in the game.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local WM = {}
ns.WorldMapPlus = WM
local function S() return ns.db.settings end

-- tint of the revealed areas (used by ComfortPlus): r, g, b, a
function WM.Tint()
    if S().mapRevealTint == false then return 1, 1, 1, 1 end
    return S().wmTintR or 0.55, S().wmTintG or 0.55, S().wmTintB or 0.6, S().wmTintA or 0.85
end

local function maximized()
    local f = WorldMapFrame
    if not f then return false end
    if f.IsMaximized then local ok, r = pcall(f.IsMaximized, f) if ok then return r and true or false end end
    return f.isMaximized and true or false
end
local function modeKey() return maximized() and "max" or "win" end

-- scale and position for the current mode (not in combat: the map is a UI panel)
function WM.Apply()
    local f = WorldMapFrame
    if not f or (InCombatLockdown and InCombatLockdown()) then return end
    local mode = modeKey()
    local sc = mode == "max" and S().wmScaleMax or S().wmScale
    pcall(f.SetScale, f, sc or 1)
    -- 0.6.607: opacity (window / maximised)
    local al = mode == "max" and S().wmAlphaMax or S().wmAlpha
    pcall(f.SetAlpha, f, al or 1)
    pcall(WM.GroupPins)
    local pos = S().wmMove and S().wmPos and S().wmPos[mode]
    if pos then
        pcall(function()
            f:ClearAllPoints()
            f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end)
    end
end
local function startDrag()
    local f = WorldMapFrame
    if not (S().wmMove and f) or (InCombatLockdown and InCombatLockdown()) then return end
    f:SetMovable(true)
    f:StartMoving()
end
local function stopDrag()
    local f = WorldMapFrame
    if not f then return end
    f:StopMovingOrSizing()
    if not S().wmMove then return end
    local p, _, rp, x, y = f:GetPoint(1)
    S().wmPos = S().wmPos or {}
    S().wmPos[modeKey()] = { p or "CENTER", rp or "CENTER", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
end
function WM.ResetPosition()
    S().wmPos = nil
    if WorldMapFrame and WorldMapFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
        -- the game places the panel again on its next show
        pcall(HideUIPanel, WorldMapFrame)
    end
end

-- town and city icons on continent / world maps (point-of-interest sheet 136441, three cells)
local CELLS = { { 0.35546875, 0.001953125 }, { 0.28515625, 0.107421875 }, { 0.42578125, 0.107421875 } }
local function isTownIcon(pin)
    local t = pin.Texture
    if not (t and t.GetTexture and t:GetTexture() == 136441) then return false end
    local l, top = t:GetTexCoord()
    for _, c in ipairs(CELLS) do
        if math.abs(l - c[1]) < 0.002 and math.abs(top - c[2]) < 0.002 then return true end
    end
    return false
end
local function onPoiAcquired(pin)
    if not S().wmHideTowns or not WorldMapFrame then return end
    local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local info = id and C_Map.GetMapInfo(id)
    local mt = info and info.mapType
    if (mt == 1 or mt == 2) and isTownIcon(pin) then pin:Hide() end
end

-- 0.6.607: party/raid members on the world map: own size and class colours (the game's group pin)
function WM.GroupPins()
    local f = WorldMapFrame
    if not (f and f.EnumeratePinsByTemplate) then return end
    local size, class = S().wmGroupSize, S().wmGroupClass
    if not size and not class then return end
    for pin in f:EnumeratePinsByTemplate("GroupMembersPinTemplate") do
        if size and pin.SetPinSize then
            pcall(pin.SetPinSize, pin, "party", size)
            pcall(pin.SetPinSize, pin, "raid", math.floor(size * 0.85 + 0.5))
        end
        if pin.SetAppearanceField then
            pcall(pin.SetAppearanceField, pin, "party", "useClassColor", class and true or false)
            pcall(pin.SetAppearanceField, pin, "raid", "useClassColor", class and true or false)
        end
        if pin.SetShouldShowUnits then pcall(pin.SetShouldShowUnits, pin, "party", true) end
    end
end
local hooked
function WM.Hook()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function()
        pcall(WM.Apply)
        -- no reading emote
        if S().wmNoEmote then
            local cancel = (C_ChatInfo and C_ChatInfo.CancelEmote) or CancelEmote
            if cancel then pcall(cancel) end
        end
    end)
    -- dragging: on the title/border area (the map canvas itself keeps its clicks)
    local grab = WorldMapFrame.BorderFrame or WorldMapFrame.TitleCanvasSpacerFrame or WorldMapFrame
    if grab.HookScript then
        if grab.RegisterForDrag then grab:RegisterForDrag("LeftButton") end
        grab:HookScript("OnDragStart", startDrag)
        grab:HookScript("OnDragStop", stopDrag)
        if grab.EnableMouse and grab ~= WorldMapFrame then grab:EnableMouse(true) end
    end
    if WorldMapFrame.Maximize then hooksecurefunc(WorldMapFrame, "Maximize", function() pcall(WM.Apply) end) end
    if WorldMapFrame.Minimize then hooksecurefunc(WorldMapFrame, "Minimize", function() pcall(WM.Apply) end) end
    if BaseMapPoiPinMixin and BaseMapPoiPinMixin.OnAcquired then
        hooksecurefunc(BaseMapPoiPinMixin, "OnAcquired", function(self) pcall(onPoiAcquired, self) end)
    end
end
WM.IsTownIcon = isTownIcon
if WorldMapFrame then pcall(WM.Hook) end
ns.On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then pcall(WM.Hook) end end)
ns.On("PLAYER_REGEN_ENABLED", function() if WorldMapFrame and WorldMapFrame:IsShown() then pcall(WM.Apply) end end)

end)

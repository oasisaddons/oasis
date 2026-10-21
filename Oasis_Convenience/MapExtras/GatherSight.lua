-- Oasis: gathering helpers on top of the minimap scan (0.6.592, 0.6.593)
--   * symbols: the scanned dots as real herb/ore pictures on the minimap (red = skill too low, faded = held)
--   * arrow: points to the nearest node you can gather (herbs, ore, treasures, rares, leylines)
--   * map pin: the game's own pin on that node, so the in-world marker shows the way (+ sparkles on that marker)
--   * sparkles: gold sparkles on the herb or ore nameplate in front of you (game's soft interact plates)
-- Settings > Areas > Map > Guild gathering map, slash commands below, key bindings (Settings > Keybindings).
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local L = ns.L
local GM = ns.Gather
if not GM then return end

local GS = {}
ns.GatherSight = GS

local function S() return ns.db.settings end
local atan2 = math.atan2 or math.atan
local LIVE_FOR = 8      -- seconds a scanned dot counts as "there right now" (held dots: until looted or 2 min)
local FAR = 300         -- meters: known nodes further away are ignored
local AT = 6            -- meters: the node you stand at is skipped
local SPARKLE = 984391  -- the game's gathering node sparkle
GS.COLORS = {
    gold = { 1, 0.85, 0.35 }, white = { 1, 1, 1 }, green = { 0.45, 1, 0.5 },
    blue = { 0.45, 0.75, 1 }, purple = { 0.8, 0.5, 1 }, red = { 1, 0.4, 0.35 },
}

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

-- dots from the last scans: live ones a few seconds, held ones (other finder) until looted
function GS.Live()
    local now = GetTime and GetTime() or 0
    if not GM.scanLive then return {} end
    if now - (GM.scanLiveAt or 0) > LIVE_FOR then
        local out = {}
        for _, d in ipairs(GM.scanLive) do if d.held then out[#out + 1] = d end end
        return out
    end
    return GM.scanLive
end
-- a known guild node already drawn as a live symbol (no double icon on the minimap)
function GM.LiveCovers(r)
    if S().gatherSymbols == false then return false end
    for _, d in ipairs(GS.Live()) do
        if d.map == r.map and math.abs(d.x - r.x) < 0.003 and math.abs(d.y - r.y) < 0.003 then return true end
    end
    return false
end

local ARROW_KEY = { herb = "gatherArrowHerb", ore = "gatherArrowOre", treasure = "gatherArrowTreasure", rare = "gatherArrowRare", leyline = "gatherArrowLeyline" }
local function arrowWants(kind)
    local k = ARROW_KEY[kind]
    if not k or S()[k] == false then return false end
    if GM.PROF_KINDS[kind] then return GM.OwnKind(kind) end
    return true
end
-- nearest node: dots on the minimap win, otherwise visible known nodes nearby; too hard nodes are skipped
function GS.Nearest()
    if ns.inInstance() then return nil end
    local map, mx, my, w, h = here()
    if not map then return nil end
    local best, bd, bscore
    local profOnly = S().gatherArrowProfFirst
    local GG = ns.GatherGuild
    -- 0.6.598: guild members farming nearby get their side; wanted nodes count as 40 % nearer
    local farmers = GG and GG.Farmers() or {}
    if GG and farmers[1] then GG.TellFarmers(farmers) end
    local function try(r)
        if r.map ~= map then return end
        -- 0.6.600: distance first (cheap) - the name checks only for nodes that could win
        local dx, dy = (r.x - mx) * w, (r.y - my) * h
        local d2 = dx * dx + dy * dy
        if d2 <= AT * AT or d2 > FAR * FAR or (bscore and d2 * 0.36 >= bscore * bscore) then return end
        if not arrowWants(r.kind) or GM.TooHard(r.name) then return end
        if r.cave and not S().gatherArrowCaves then return end
        if profOnly and not GM.PROF_KINDS[r.kind] then return end
        if GG and GG.Theirs(r, farmers, mx, my) then return end
        local d = math.sqrt(d2)
        local score = d * ((GG and GG.WantedBy(r.name)) and 0.6 or 1)
        if not bscore or score < bscore then best, bd, bscore = r, d, score end
    end
    for _, r in ipairs(GS.Live()) do try(r) end
    -- 0.6.597: herbs and ore first - the others only if there is none
    if profOnly and not best then profOnly = false for _, r in ipairs(GS.Live()) do try(r) end end
    if not best then
        local t = ns.now()
        for _, r in ipairs(GM.Nodes(map)) do
            if (r.kind == "herb" or r.kind == "ore") then
                local dx, dy = (r.x - mx) * w, (r.y - my) * h
                -- 0.6.618: stored nodes only outside the scanned minimap view - inside it the scan's live dots count
            if dx * dx + dy * dy <= FAR * FAR and GM.Shown(r) and not GM.Harvested(r, t) and not (GM.InScanView and GM.InScanView(r)) then try(r) end
            end
        end
    end
    if not best then return nil end
    local dx, dy = (best.x - mx) * w, (best.y - my) * h
    return best, bd, atan2(-dx, -dy)   -- bearing: radians counterclockwise from north (like GetPlayerFacing)
end

local function iconOf(d)
    local info = GM.NodeInfo(d.name)
    if info then return info.icon, info end
    local k = GM.KINDS[d.kind]
    return k and k.icon, nil
end

------------------------------------------------------------------------
-- symbols on the minimap (follow every frame, also on a rotating minimap)
------------------------------------------------------------------------
local sPool = {}
-- 0.6.602: one symbol (also used by the preview on the comfort settings page)
function GS.NewSymbol(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(13, 13)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetTexture(ns.MEDIA .. "pindisc")
    p.bg:SetPoint("TOPLEFT", -2, 2) p.bg:SetPoint("BOTTOMRIGHT", 2, -2)
    p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
    -- 0.6.597: square shape = plain icon without mask
    p.square = p:CreateTexture(nil, "ARTWORK")
    p.square:SetAllPoints()
    p.square:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if p.CreateMaskTexture and p.icon.AddMaskTexture then
        pcall(function()
            local m = p:CreateMaskTexture()
            m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(p.icon)
            p.icon:AddMaskTexture(m)
        end)
    end
    p.ring = p:CreateTexture(nil, "OVERLAY")
    p.ring:SetTexture(ns.MEDIA .. "pinring")
    p.ring:SetPoint("TOPLEFT", -2, 2) p.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    -- 0.6.598: someone in the guild wants it: soft gold halo
    p.want = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.want:SetTexture(ns.MEDIA .. "halo_ring")
    p.want:SetBlendMode("ADD")
    p.want:SetVertexColor(1, 0.8, 0.25)
    p.want:SetPoint("TOPLEFT", -8, 8) p.want:SetPoint("BOTTOMRIGHT", 8, -8)
    p.want:Hide()
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if not (self.d and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.d.name or "")
        local line, r, g, b = GM.SkillLine(self.d.name)
        if line then GameTooltip:AddLine(line, r, g, b) end
        if self.d.held then GameTooltip:AddLine(L["Seen before the finder switched"], 0.6, 0.6, 0.6) end
        if self.d.cave then GameTooltip:AddLine(L["In a cave or on another level"], 0.6, 0.6, 0.6) end
        local who = ns.GatherGuild and ns.GatherGuild.WantedBy(self.d.name)
        if who then GameTooltip:AddLine((L["Wanted by %s"]):format(ns.displayName(who)), 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return p
end
local function sym(i)
    local p = sPool[i]
    if p then return p end
    p = GS.NewSymbol(Minimap)
    if ns.MiniPinLayer then ns.MiniPinLayer(p, 3) else p:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6) end
    sPool[i] = p
    return p
end
GS.symbols = sPool
-- look of a symbol from the settings (shape, ring color, too hard, cave, held, wanted); d.hard / d.wanted for the preview
function GS.StyleSymbol(p, d, ox, oy)
    local icon, info = iconOf(d)
    -- 0.6.621: own size for the symbols (slider "Gathering symbols: size")
    local sz = 13 * (S().gatherSymbolSize or 1)
    p:SetSize(sz, sz)
    -- shape: 1 square, 2 round, 3 round with ring, 4 slim ring
    local shape = S().gatherShape or 3
    local tex = shape == 1 and p.square or p.icon
    p.square:SetShown(shape == 1) p.icon:SetShown(shape ~= 1)
    p.bg:SetShown(shape == 2 or shape == 3)
    p.ring:SetShown(shape >= 3)
    p.ring:ClearAllPoints()
    local o = shape == 4 and 1 or 2
    p.ring:SetPoint("TOPLEFT", -o, o) p.ring:SetPoint("BOTTOMRIGHT", o, -o)
    tex:SetTexture(icon)
    p.want:SetShown((d.wanted or (ns.GatherGuild and ns.GatherGuild.WantedBy(d.name))) and S().gatherWanted ~= false and true or false)
    local k = GM.KINDS[d.kind] or {}
    local ring = info and info.ring or k.color or { 1, 1, 1 }
    p.ring:SetVertexColor(ring[1], ring[2], ring[3], shape == 4 and 0.7 or 1)
    if d.hard or GM.TooHard(d.name) then tex:SetVertexColor(1, 0.25, 0.25) else tex:SetVertexColor(1, 1, 1) end
    -- cave / other level: gray like the game's own dot
    if tex.SetDesaturated then tex:SetDesaturated(d.cave and true or false) end
    -- over your own arrow in the middle: see-through; held or cave: faded
    local a = (d.held or d.cave) and 0.55 or 1
    if ox * ox + oy * oy < 81 then a = math.min(a, 0.35) end
    p:SetAlpha(a)
end
GS.IconOf = iconOf
function GS.DrawSymbols()
    local used = 0
    local c = S().gatherSymbols ~= false and GM.MiniCtx()
    if c then
        for _, d in ipairs(GS.Live()) do
            if d.map == c.map and used < 40 then
                local ox, oy, dist = GM.MiniPlace(c, d.x, d.y)
                if dist <= 1 then
                    used = used + 1
                    local p = sym(used)
                    p.d = d
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
                    GS.StyleSymbol(p, d, ox, oy)
                    p:Show()
                end
            end
        end
    end
    for i = used + 1, #sPool do sPool[i]:Hide() sPool[i].d = nil end
    return used
end

------------------------------------------------------------------------
-- arrow
------------------------------------------------------------------------
local arrow
local function lockArrow() if arrow then arrow:EnableMouse(not S().gatherArrowLock) end end
local function makeArrow()
    arrow = CreateFrame("Frame", "OasisGatherArrow", UIParent)
    arrow:SetSize(56, 56)
    local p = S().gatherArrowPos
    if p then arrow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2]) else arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 200) end
    arrow:SetMovable(true) arrow:RegisterForDrag("LeftButton")
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
    lockArrow()
    -- spring: stiffness 70, damping 10 (a bit under critical -> a small, calm overshoot)
    arrow.rot, arrow.vel = 0, 0
    arrow:SetScript("OnUpdate", function(self, el)
        if not self.target then return end
        el = math.min(el or 0, 0.05)
        local diff = (self.target - self.rot + math.pi) % (2 * math.pi) - math.pi   -- shortest way round
        self.vel = self.vel + (diff * 70 - self.vel * 10) * el
        self.rot = self.rot + self.vel * el
        self.tex:SetRotation(self.rot)
    end)
    arrow:Hide()
end
local function updateArrow(r, d, bearing)
    if not S().gatherArrow or not r then if arrow then arrow:Hide() end return end
    if not arrow then makeArrow() end
    local facing = ns.safe(GetPlayerFacing and GetPlayerFacing())
    if type(facing) ~= "number" then arrow:Hide() return end
    -- 0.6.620: the needle swings to the new direction on a spring (overshoots a little, then settles)
    arrow.target = bearing - facing
    arrow.icon:SetTexture((iconOf(r)))
    arrow.text:SetText(("%s  |cffffd100%d m|r"):format(r.name or "", math.floor(d + 0.5)))
    arrow:Show()
end

------------------------------------------------------------------------
-- map pin (the game's user waypoint + super track = marker in the world)
------------------------------------------------------------------------
local ourPin   -- { map, x, y } of the pin we set
local function pinWanted() return S().gatherPin or S().gatherSparkleFar end
local function samePin(wp)
    return wp and ourPin and wp.uiMapID == ourPin[1] and wp.position
        and math.abs(wp.position.x - ourPin[2]) < 0.0005 and math.abs(wp.position.y - ourPin[3]) < 0.0005
end
local function clearPin()
    if ourPin and C_Map.GetUserWaypoint and samePin(C_Map.GetUserWaypoint()) then pcall(C_Map.ClearUserWaypoint) end
    ourPin = nil
end
GS.ClearPin = clearPin
function GS.PinActive() return ourPin ~= nil end
local function updatePin(r)
    if not (C_Map.SetUserWaypoint and UiMapPoint and C_SuperTrack) then return end
    if not pinWanted() or not r then clearPin() return end
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
-- sparkles
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
local plates, spare, active, dimmed = {}, {}, {}, {}
local function color() return GS.COLORS[S().gatherSparkleColor or "gold"] or GS.COLORS.gold end
local function scale() return math.max(0.5, math.min(2, (S().gatherSparkleSize or 100) / 100)) end
local function newSparkles()
    local f = CreateFrame("Frame")
    f.parts = {}
    for i = 1, 9 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(SPARKLE)
        t:SetBlendMode("ADD")
        t.phase, t.speed = math.random() * 6.28, 1.5 + math.random() * 1.5
        t.size, t.px, t.py = 14 + math.random() * 12, math.random() - 0.5, math.random() - 0.5
        f.parts[i] = t
    end
    return f
end
-- size and color from the settings (also when they change)
local function style(f)
    local sc, c = scale(), color()
    f:SetSize(90 * sc, 90 * sc)
    for _, t in ipairs(f.parts) do
        t:SetSize(t.size * sc, t.size * sc)
        t:ClearAllPoints()
        t:SetPoint("CENTER", f, "CENTER", t.px * 70 * sc, t.py * 70 * sc)
        t:SetVertexColor(c[1], c[2], c[3])
    end
end
local function sparkleOn(parent, key, dy)
    local f = plates[key]
    if not f then
        f = table.remove(spare) or newSparkles()
        f:SetParent(parent)
        plates[key] = f
        active[f] = true
    end
    style(f)
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", parent, dy and "CENTER" or "BOTTOM", 0, dy or -50)
    f:Show()
    return f
end
local function sparkleOff(key)
    local f = plates[key]
    if not f then return end
    f:Hide() f:SetParent(nil)
    plates[key], active[f] = nil, nil
    spare[#spare + 1] = f
end
-- the game's own interact icon on the plate can be hidden (only the sparkles stay)
local function dim(plate, on)
    local uf = plate.UnitFrame
    if not uf then return end
    if on and not dimmed[plate] then dimmed[plate] = uf:GetAlpha() or 1 uf:SetAlpha(0)
    elseif not on and dimmed[plate] then uf:SetAlpha(dimmed[plate]) dimmed[plate] = nil end
end
GS.plates = plates
GS.SparkleOn, GS.SparkleOff = function(parent, key, dy) return sparkleOn(parent, key, dy) end, function(key) sparkleOff(key) end
function GS.PlateUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local name = S().gatherSparkle and ns.safe(UnitName(unit))
    local info = type(name) == "string" and GM.NodeInfo(name)
    local kind = info and info.kind or (type(name) == "string" and GM.ExtraKind(name) == "treasure" and "treasure")
    if kind and (kind == "treasure" or GM.OwnKind(kind)) and not GM.TooHard(name) then
        sparkleOn(plate, plate)
        dim(plate, S().gatherSparkleHideIcons and true or false)
    else
        sparkleOff(plate) dim(plate, false)
    end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) pcall(GS.PlateUnit, unit) end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate then sparkleOff(plate) dim(plate, false) end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if GS.pendingCVars then applyCVars(S().gatherSparkle and true or false) end end)

-- far away: sparkles on the game's navigation marker of our pin (the herb itself is out of nameplate range)
local FAR_KEY = "far"
local function updateFar()
    local nav = C_Navigation
    local f = S().gatherSparkleFar and ourPin and nav and nav.GetFrame and nav.GetFrame()
    local ok = f and (not nav.HasValidScreenPosition or nav.HasValidScreenPosition())
        and not (nav.WasClampedToScreen and nav.WasClampedToScreen())
    local dist = ok and nav.GetDistance and ns.safe(nav.GetDistance())
    if ok and (type(dist) ~= "number" or dist > 25) then sparkleOn(f, FAR_KEY, 0) else sparkleOff(FAR_KEY) end
    GS.FarOthers(ok and f)
end
-- 0.6.594: up to four more nodes far away. The pinned node's marker is the reference: its screen position gives
-- the camera's turn against your facing and the horizon; the others are placed on the ground from there
-- (flat ground, camera height from the zoom). Approximate on purpose - it is a hint where to look.
local MORE = 4
function GS.Project(ref, refX, refY, list, facing, f, cx, camH)
    local out = {}
    local sideRef = ref.bearing - facing
    local yaw = sideRef - math.atan((cx - refX) / f)
    local dRef = ref.dist * math.cos(sideRef - yaw)
    if dRef <= 1 then return out end
    local horizon = refY + f * camH / dRef
    for _, o in ipairs(list) do
        local side = o.bearing - facing - yaw
        local d = o.dist * math.cos(side)
        if d > 20 and math.abs(side) < 1.1 then
            out[#out + 1] = { o = o, x = cx - f * math.tan(side), y = horizon - f * camH / d }
        end
    end
    return out
end
function GS.FarOthers(nf)
    local placed = 0
    if GS.cal.state then return 0 end   -- the pin is hopping for the measurement
    if nf and S().gatherSparkleFar and UIParent then
        local map, mx, my, w, h = here()
        local facing = ns.safe(GetPlayerFacing and GetPlayerFacing())
        local rx, ry = nf:GetCenter()
        if map and type(facing) == "number" and rx and ourPin then
            local function polar(x, y)
                local dx, dy = (x - mx) * w, (y - my) * h
                return math.sqrt(dx * dx + dy * dy), atan2(-dx, -dy)
            end
            local ref = {} ref.dist, ref.bearing = polar(ourPin[2], ourPin[3])
            local list = {}
            for _, d in ipairs(GS.Live()) do
                if d.map == map and (d.kind == "herb" or d.kind == "ore") and not d.held
                    and not (math.abs(d.x - ourPin[2]) < 0.0005 and math.abs(d.y - ourPin[3]) < 0.0005) and not GM.TooHard(d.name) then
                    local dist, b = polar(d.x, d.y)
                    if dist > 25 and dist < 200 and not d.cave then list[#list + 1] = { dist = dist, bearing = b, x = d.x, y = d.y } end
                end
            end
            table.sort(list, function(a, b) return a.dist < b.dist end)
            local fov = tonumber(getCVar("cameraFov")) or 90
            local cx = UIParent:GetWidth() / 2
            local f = cx / math.tan(math.rad(fov) / 2)
            local camH = 1.8 + (GetCameraZoom and ns.safe(GetCameraZoom()) or 8) * 0.4
            -- measured values win over the estimate
            local mf, mh = GS.Camera()
            if mf then f = mf end
            if mh then camH = mh end
            GS.TryCalibrate(ourPin, here, polar, list)
            for _, p in ipairs(GS.Project(ref, rx, ry, list, facing, f, cx, camH)) do
                if placed >= MORE then break end
                if p.x > 0 and p.x < UIParent:GetWidth() and p.y > 0 and p.y < UIParent:GetHeight() then
                    placed = placed + 1
                    local fr = sparkleOn(UIParent, "far" .. placed, 0)
                    fr:ClearAllPoints()
                    fr:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
                    -- further away = smaller
                    fr:SetScale(math.max(0.4, math.min(1, 60 / p.o.dist)))
                end
            end
        end
    end
    for i = placed + 1, MORE do sparkleOff("far" .. i) end
    return placed
end

-- 0.6.597: size of the game's own yellow dots (Minimap:SetIconScale) - only touched once the slider was moved
local dotApplied
function GS.ApplyDotScale()
    local v = S().gatherDotScale
    if not (Minimap and Minimap.SetIconScale) then return end
    if v and v ~= dotApplied then pcall(Minimap.SetIconScale, Minimap, v) dotApplied = v
    elseif not v and dotApplied then pcall(Minimap.SetIconScale, Minimap, 1) dotApplied = nil end
end

-- 0.6.597: measuring the camera for the far sparkles. Standing still, the pin hops for a moment to a second
-- node; the two markers on screen give the focal length, the camera's turn and its height over the ground
-- (per zoom level, kept in the settings). Without a measurement the field of view and zoom are estimated.
GS.cal = { state = nil }
function GS.Solve(a, b, facing, cx)
    -- a, b = { dist, bearing, x, y } of two markers; returns f, yaw, h or nil
    local best
    for yawI = -900, 900 do
        local yaw = yawI / 1000
        local sa, sb = a.bearing - facing - yaw, b.bearing - facing - yaw
        local ta, tb = math.tan(sa), math.tan(sb)
        local f
        if math.abs(ta) > 0.03 then f = (cx - a.x) / ta elseif math.abs(tb) > 0.03 then f = (cx - b.x) / tb end
        if f and f > 150 and f < 4000 then
            local err = math.abs(cx - f * ta - a.x) + math.abs(cx - f * tb - b.x)
            if not best or err < best.err then best = { err = err, f = f, yaw = yaw } end
        end
    end
    if not best or best.err > 12 then return nil end
    local da = a.dist * math.cos(a.bearing - facing - best.yaw)
    local db = b.dist * math.cos(b.bearing - facing - best.yaw)
    local k = 1 / db - 1 / da
    if math.abs(k) < 0.003 then return best.f, best.yaw, nil end
    local h = (a.y - b.y) / (best.f * k)
    if h < 0.3 or h > 40 then return best.f, best.yaw, nil end
    return best.f, best.yaw, h
end
local function zoomKey() local z = GetCameraZoom and ns.safe(GetCameraZoom()) return type(z) == "number" and math.floor(z + 0.5) or 0 end
function GS.Camera()
    local c = S().gatherCam and S().gatherCam[zoomKey()]
    if c and c.f then return c.f, c.h end
end
local lastPos
local function calibrate(el)
    local cal = GS.cal
    local nav = C_Navigation
    local nf = nav and nav.GetFrame and nav.GetFrame()
    if cal.state == "hop" then
        cal.t = cal.t + el
        if cal.t < 0.2 then return true end
        local x, y = nf and nf:GetCenter()
        local ok = x and (not nav.HasValidScreenPosition or nav.HasValidScreenPosition())
        if ok then
            local facing = ns.safe(GetPlayerFacing and GetPlayerFacing())
            local f, _, h = GS.Solve(cal.a, { dist = cal.b.dist, bearing = cal.b.bearing, x = x, y = y }, facing or 0, UIParent:GetWidth() / 2)
            if f then
                S().gatherCam = S().gatherCam or {}
                local old = S().gatherCam[zoomKey()] or {}
                S().gatherCam[zoomKey()] = { f = f, h = h or old.h }
            end
        end
        -- back to the real target
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(cal.pin[1], cal.pin[2], cal.pin[3]))
        cal.state, cal.at = nil, GetTime and GetTime() or 0
        return true
    end
    return false
end
function GS.TryCalibrate(ourPin, here, polar, list)
    local cal = GS.cal
    if cal.state or not ourPin or not (C_Map.SetUserWaypoint and UiMapPoint) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if WorldMapFrame and WorldMapFrame:IsShown() then return end
    local now = GetTime and GetTime() or 0
    if now - (cal.at or -100) < 20 and GS.Camera() then return end
    local map, mx, my = here()
    local pos = map and (map .. ":" .. math.floor(mx * 5000) .. ":" .. math.floor(my * 5000))
    local still = pos == lastPos
    lastPos = pos
    if not still or not list[1] then return end
    local nav = C_Navigation
    local nf = nav and nav.GetFrame and nav.GetFrame()
    local x, y = nf and nf:GetCenter()
    if not x then return end
    local d1, b1 = polar(ourPin[2], ourPin[3])
    cal.a = { dist = d1, bearing = b1, x = x, y = y }
    cal.b = list[1]
    cal.pin = { ourPin[1], ourPin[2], ourPin[3] }
    cal.state, cal.t = "hop", 0
    pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(ourPin[1], list[1].x, list[1].y))
end
GS.Calibrating = function() return GS.cal.state ~= nil end

------------------------------------------------------------------------
-- tick
------------------------------------------------------------------------
local acc, pinAcc, pickAcc, picked = 0, 0, 0, nil
function GS.Tick(el)
    el = el or 0
    if GS.cal.state and calibrate(el) then return end
    GS.ApplyDotScale()
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
    -- symbols follow every frame (cheap: at most 40)
    if GM.scanLive or next(sPool) then GS.DrawSymbols() end
    acc, pinAcc = acc + el, pinAcc + el
    if acc < 0.05 then return end
    acc = 0
    if not (S().gatherArrow or pinWanted()) then
        if arrow then arrow:Hide() end
        sparkleOff(FAR_KEY) GS.FarOthers(nil)
        return
    end
    -- 0.6.600: choosing the target walks all nodes of the zone - only 4x per second; in between only the
    -- distance and direction of the chosen one are updated (cheap), so the arrow still turns smoothly
    pickAcc = pickAcc + 0.05
    local r, d, b
    if pickAcc >= 0.25 or not picked then
        pickAcc = 0
        r, d, b = GS.Nearest()
        picked = r
    else
        r = picked
        local map, mx, my, w, h = here()
        if map and r.map == map then
            local dx, dy = (r.x - mx) * w, (r.y - my) * h
            d, b = math.sqrt(dx * dx + dy * dy), atan2(-dx, -dy)
        else r, picked = nil, nil end
    end
    updateArrow(r, d, b)
    if pinAcc >= 1 then pinAcc = 0 updatePin(r) end
    updateFar()
end
CreateFrame("Frame"):SetScript("OnUpdate", function(_, el) GS.Tick(el) end)

-- settings changed (toggle in the settings, slash command or key)
function GS.Apply()
    applyCVars(S().gatherSparkle and true or false)
    for key, f in pairs(plates) do
        if not S().gatherSparkle and key ~= FAR_KEY then sparkleOff(key) dim(key, false) else style(f) end
    end
    if type(next(dimmed)) == "table" and not S().gatherSparkleHideIcons then for p in pairs(dimmed) do dim(p, false) end end
    if not pinWanted() then clearPin() end
    if not S().gatherArrow and arrow then arrow:Hide() end
    lockArrow()
    GS.DrawSymbols()
end
ns.On("PLAYER_LOGIN", function() if S().gatherSparkle or S().gatherSparkleSaved then GS.Apply() end end)
if ns.db and ns.db.settings and (S().gatherSparkle or S().gatherSparkleSaved) then GS.Apply() end

local MSG = {
    gatherArrow = { "Arrow to the nearest node on.", "Arrow to the nearest node off." },
    gatherSparkle = { "Sparkles on.", "Sparkles off." },
    gatherPin = { "Map pin on the nearest node on.", "Map pin on the nearest node off." },
    gatherSymbols = { "Gathering symbols on the minimap on.", "Gathering symbols on the minimap off." },
    gatherSwitch = { "Switching finders on.", "Switching finders off." },
}
-- default on: symbols (nil = on); the rest is off until switched on
function GS.Toggle(key)
    if key == "gatherSymbols" then S()[key] = S()[key] == false
    else S()[key] = not S()[key] or nil end
    GS.Apply()
    local on = S()[key] ~= nil and S()[key] ~= false
    local m = MSG[key]
    if m then ns.print(L[on and m[1] or m[2]]) end
end
ns.slash.gatherarrow = function() GS.Toggle("gatherArrow") end
ns.slash.gatherpin = function() GS.Toggle("gatherPin") end
ns.slash.gathersymbols = function() GS.Toggle("gatherSymbols") end
ns.slash.gatherswitch = function() GS.Toggle("gatherSwitch") end
-- /oa gathersparkle [color gold|white|green|blue|purple|red] [size 50-200]
ns.slash.gathersparkle = function(rest)
    local what, val = tostring(rest or ""):lower():match("^(%a+)%s*(%S*)")
    if what == "color" or what == "farbe" then
        if GS.COLORS[val] then S().gatherSparkleColor = val GS.Apply() end
        ns.print(L["Sparkle color"] .. ": " .. (S().gatherSparkleColor or "gold") .. "  (gold, white, green, blue, purple, red)")
        return
    elseif what == "size" or what == "groesse" then
        local n = tonumber(val)
        if n then S().gatherSparkleSize = math.max(50, math.min(200, math.floor(n))) GS.Apply() end
        ns.print(L["Sparkle size"] .. ": " .. (S().gatherSparkleSize or 100) .. " %  (50-200)")
        return
    end
    GS.Toggle("gatherSparkle")
end
ns.slash.sammelpfeil, ns.slash.glitzern, ns.slash.sammelpin = ns.slash.gatherarrow, ns.slash.gathersparkle, ns.slash.gatherpin
ns.slash.sammelsymbole, ns.slash.finderwechsel = ns.slash.gathersymbols, ns.slash.gatherswitch
-- the key names in WoW's list lose the "(Oasis - Convenience)" hint now that it is here
if ns.Keybinds and ns.Keybinds.Names then pcall(ns.Keybinds.Names) end
end)

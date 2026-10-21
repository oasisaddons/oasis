-- Oasis: guild gathering map (like GatherMate, but shared with the guild)
-- Whoever picks herbs, mines ore or opens a chest records the location (store "nodes").
-- Everyone with Oasis sees the points on world map and minimap. Same location (very close, same name)
-- = one point that counts how often it was found.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local GM = {}
ns.Gather = GM

-- gathering spells (all ranks) -> kind
local SPELLS = {
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
    [3365] = "treasure", [6247] = "treasure", [6477] = "treasure", [6478] = "treasure", [22810] = "treasure",
    -- 0.5.935: fishing (all ranks) and pick lock (locked boxes)
    [7620] = "fish", [7731] = "fish", [7732] = "fish", [18248] = "fish",
    [1804] = "lock",
}
GM.KINDS = {
    herb = { name = "Herbs", icon = "Interface\\Icons\\INV_Misc_Flower_02", color = { 0.4, 0.86, 0.45 } },
    ore = { name = "Ore", icon = "Interface\\Icons\\INV_Ore_Copper_01", color = { 0.85, 0.65, 0.35 } },
    treasure = { name = "Treasures", icon = "Interface\\Icons\\INV_Box_01", color = { 0.98, 0.82, 0.3 } },
    fish = { name = "Fishing spots", icon = "Interface\\Icons\\Trade_Fishing", color = { 0.36, 0.68, 0.98 } },
    lock = { name = "Locked chests", icon = "Interface\\Icons\\INV_Misc_Key_03", color = { 0.78, 0.6, 0.95 } },
    -- 0.5.936: visited places (MapExtras records them). poi = world map only, no route, no fading
    vendor = { name = "Vendors", icon = "Interface\\Icons\\INV_Misc_Bag_10", color = { 0.8, 0.8, 0.82 }, poi = true },
    repair = { name = "Repair", icon = "Interface\\Icons\\Trade_BlackSmithing", color = { 0.8, 0.8, 0.82 }, poi = true },
    mail = { name = "Mailboxes", icon = "Interface\\Icons\\INV_Letter_15", color = { 0.8, 0.8, 0.82 }, poi = true },
    flight = { name = "Flight points", icon = "Interface\\Icons\\Ability_Mount_Wyvern_01", color = { 0.8, 0.8, 0.82 }, poi = true },
}
local NEAR = 0.006   -- map fraction: closer = same node

local function S() return ns.db.settings end
local function showKind(k) return not S()["gatherOff_" .. k] end
-- 0.5.935: a node is visible when kind, minimum count and the per-type filter (name) match
GM.PROF_KINDS = { herb = true, ore = true, fish = true }
-- 0.6.520: by default only nodes of your own gathering professions (herbalism 182, mining 186, fishing 356); toggle shows all
local KIND_SKILL = { herb = 182, ore = 186, fish = 356 }
local ownKinds, ownAt
local function ownKind(kind)
    if S().gatherAllProfs or not GetProfessions then return true end
    local now = GetTime and GetTime() or 0
    if not ownKinds or now - (ownAt or 0) > 30 then
        ownAt, ownKinds = now, {}
        local ok, list = pcall(ns.Radar and ns.Radar.myProfessions or function() return {} end)
        if ok and type(list) == "table" then
            for _, p in ipairs(list) do for k, id in pairs(KIND_SKILL) do if p.id == id then ownKinds[k] = true end end end
        end
    end
    return ownKinds[kind] == true
end
GM.OwnKind = ownKind
function GM.ResetOwnKinds() ownKinds = nil end
local function shown(r)
    local k = GM.KINDS[r.kind]
    if not k then return false end
    -- 0.6.431: professions only (herbs, ore, fishing) - no vendors, boxes, treasures etc.
    if not GM.PROF_KINDS[r.kind] then return false end
    if k.poi then return S().mapPoi ~= false end
    if S()["gatherOff_" .. r.kind] or (r.n or 1) < (S().gatherMinCount or 1) then return false end
    if not ownKind(r.kind) then return false end
    local hide = S().gatherHide
    if hide and r.name and r.name ~= "" and hide[r.name] then return false end
    return true
end
-- freshness: 1 = at most one day old, drops to 0.4 after 30 days (can be turned off)
local function freshness(r, now)
    if S().gatherFresh == false or (GM.KINDS[r.kind] or {}).poi then return 1 end
    local age = (now - (r.ts or 0)) / 86400
    if age <= 1 then return 1 end
    if age >= 30 then return 0.4 end
    return 1 - 0.6 * (age - 1) / 29
end
-- just harvested: someone gathered there in the last 5 minutes
local HARVEST, RESEND = 300, 600
local function harvested(r, now) return S().gatherHarvest ~= false and now - (r.ts or 0) < HARVEST and not (GM.KINDS[r.kind] or {}).poi end
GM.Shown, GM.Freshness, GM.Harvested = shown, freshness, harvested

------------------------------------------------------------------------
-- remember nodes
------------------------------------------------------------------------
local pending = {}   -- castGUID -> { kind, name }
-- 0.6.251: also detect gathering by spell name - clients with different spell IDs (e.g. Forever) otherwise saved
-- nothing anymore. The names come from the known IDs (in the client's language).
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id) if ok and n then return n end end
    if GetSpellInfo then local ok, n = pcall(GetSpellInfo, id) if ok and n then return n end end
end
local byName
local function kindOf(spellID)
    if not spellID then return nil end
    if SPELLS[spellID] then return SPELLS[spellID] end
    if not byName then
        byName = {}
        for id, k in pairs(SPELLS) do local n = spellName(id) if n then byName[n] = k end end
    end
    local n = spellName(spellID)
    return n and byName[n] or nil
end
GM.KindOf = kindOf
-- last spells for /oa sammeltest (local only, at most 8)
GM.diag = {}
local function diag(spellID, kind, note)
    local d = GM.diag
    table.insert(d, 1, { t = time(), id = spellID, name = spellID and spellName(spellID) or "?", kind = kind, note = note })
    if #d > 8 then d[#d] = nil end
end
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, guid, spellID)
    if unit ~= "player" then return end
    spellID = ns.safe(spellID)
    local kind = kindOf(spellID)
    if not kind then return end
    pending[ns.safe(guid) or "x"] = { kind = kind, name = ns.safe(target) or "" }
end)
local function myPos()
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or x == 0 then return nil end
    return map, x, y
end
-- index per map, rebuilt only when the collection changes (performance 0.5.482: previously a scan every second
-- of the whole "nodes" collection for the minimap)
local byMap, allNodes
ns.Listen("STORE", function(coll) if coll == "nodes" then byMap, allNodes = nil, nil end end)
function GM.Nodes(map)
    if not byMap then
        byMap, allNodes = {}, {}
        for _, r in ipairs(Store.List("nodes", function(r) return r.kind end)) do
            allNodes[#allNodes + 1] = r
            local l = byMap[r.map]
            if not l then l = {} byMap[r.map] = l end
            l[#l + 1] = r
        end
    end
    if not map then return allNodes end
    return byMap[map] or {}
end
function GM.Record(kind, name, px, py)
    if ns.inInstance() then return "Instance" end
    if ns.db.settings.shareNodes == false then return "Sammelorte teilen ist aus" end
    local map, x, y = myPos()
    if not map then return "keine Kartenposition" end
    -- 0.6.487: node from the minimap (mouse over Blizzard's yellow dot): position from the cursor
    local hover = px ~= nil
    if hover then x, y = px, py end
    -- already known?
    for _, r in ipairs(GM.Nodes(map)) do
        if r.kind == kind and (r.name == name or name == "") and math.abs(r.x - x) < NEAR and math.abs(r.y - y) < NEAR then
            if hover then return "schon bekannt" end   -- only average the position on real gathering
            -- resend at most every 10 minutes (0.5.935: previously 6 hours - "just harvested" needs the guild to know
            -- the time); the "times found" counter still only rises every 6 hours
            local age = ns.now() - (r.ts or 0)
            -- 0.6.384: average the position with each harvest (you stand left, then right of the ore) -> drifts to the real
            -- center, i.e. the game's node dot; at most 8 harvests count so it can still move
            local m = math.min(8, (r.m or 1))
            local c = {} for k, v in pairs(r) do c[k] = v end
            c.x = math.floor(((r.x * m + x) / (m + 1)) * 10000) / 10000
            c.y = math.floor(((r.y * m + y) / (m + 1)) * 10000) / 10000
            c.m = m + 1
            if age > RESEND then
                if age > 6 * 3600 then c.n = (c.n or 1) + 1 end
                c.ts, c.by = ns.now(), ns.me()
                Store.Put("nodes", c)
            elseif Store.merge then
                Store.merge("nodes", c)   -- local only, without sending
            end
            return "schon bekannt"
        end
    end
    Store.Put("nodes", { id = ("nd-%s-%d-%d-%d"):format(kind, map, math.floor(x * 1000), math.floor(y * 1000)),
        kind = kind, name = name, map = map, x = math.floor(x * 10000) / 10000, y = math.floor(y * 10000) / 10000,
        n = 1, ts = ns.now(), by = ns.me() })
    if ns.Map and WorldMapFrame and WorldMapFrame:IsShown() then ns.Map.UpdateWorldPins() end
    return "neu gespeichert"
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, guid, spellID)
    if unit ~= "player" then return end
    spellID = ns.safe(spellID)
    local p = pending[ns.safe(guid) or "x"]
    if not p then
        local kind = kindOf(spellID)
        if not kind then diag(spellID, nil, "kein Sammelzauber") return end
        p = { kind = kind, name = "" }
    end
    pending[ns.safe(guid) or "x"] = nil
    local ok, res = pcall(GM.Record, p.kind, p.name)
    diag(spellID, p.kind, ok and res or ("Fehler: " .. tostring(res)))
end)
-- /oa sammeltest: last spells and what came of them
ns.slash.sammeltest = function()
    local s = ns.db.settings
    local map, x, y = myPos()
    ns.print(("Sammeltest | Sammelorte teilen=%s | Instanz=%s | Karte=%s (%.3f, %.3f) | Fundorte gesamt=%d"):format(
        tostring(s.shareNodes ~= false), tostring(ns.inInstance()), tostring(map), x or 0, y or 0, #GM.Nodes()))
    -- 0.6.389: what the world map shows (map, visible nodes, toggles)
    local here, vis = GM.Nodes(map), 0
    for _, r in ipairs(here) do if shown(r) then vis = vis + 1 end end
    local wm = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
    ns.print(("  diese Karte: %d Fundorte, %d sichtbar | Weltkarte zeigt Karte %s (%d Fundorte) | Weltkarte an=%s | Mindestzahl=%s"):format(
        #here, vis, tostring(wm), wm and #GM.Nodes(wm) or 0, tostring(S().mapGather ~= false), tostring(S().gatherMinCount or 1)))
    if wm then
        local okD, errD = pcall(GM.DrawWorld)
        ns.print(("  Weltkarte neu gezeichnet: ok=%s gezeichnet=%d %s"):format(tostring(okD), GM.WorldCount and GM.WorldCount() or -1, okD and "" or ("Fehler: " .. tostring(errD))))
        local pin = GM.WorldPin and GM.WorldPin(1)
        if pin then
            local cv = WorldMapFrame:GetCanvas()
            local _, _, _, px, py = pin:GetPoint(1)
            ns.print(("  Punkt 1: shown=%s visible=%s alpha=%.2f eff=%.2f scale=%.2f pos=%.0f,%.0f size=%.0f level=%s/%s strata=%s/%s parent=%s"):format(
                tostring(pin:IsShown()), tostring(pin:IsVisible()), pin:GetAlpha() or -1, pin:GetEffectiveAlpha() or -1, pin:GetScale() or -1,
                px or 0, py or 0, pin:GetWidth() or 0, tostring(pin:GetFrameLevel()), tostring(cv and cv:GetFrameLevel()),
                tostring(pin:GetFrameStrata()), tostring(cv and cv:GetFrameStrata()), tostring(pin:GetParent() == cv)))
            ns.print(("  Karte: canvas %.0f x %.0f, icon=%s alpha=%.2f"):format(cv and cv:GetWidth() or 0, cv and cv:GetHeight() or 0,
                tostring(pin.icon and pin.icon:GetTexture()), pin.icon and pin.icon:GetAlpha() or -1))
        end
    end
    if #GM.diag == 0 then ns.print("Noch kein Zauber seit dem Einloggen - einmal sammeln, dann nochmal /oa sammeltest.") end
    for _, d in ipairs(GM.diag) do
        ns.print(("  %s  Zauber %s (%s) -> %s: %s"):format(date("%H:%M:%S", d.t), tostring(d.id), tostring(d.name), tostring(d.kind or "-"), tostring(d.note)))
    end
end
ns.slash.gathertest = ns.slash.sammeltest

------------------------------------------------------------------------
-- world map (hooks onto Oasis' map layer) and minimap
------------------------------------------------------------------------
local wPool, wUsed = {}, 0
function GM.WorldCount() return wUsed end   -- 0.6.391: for /oa sammeltest
function GM.WorldPin(i) return wPool[i] end
local function wPin(canvas)
    wUsed = wUsed + 1
    local p = wPool[wUsed]
    if not p then
        p = CreateFrame("Frame", nil, canvas)
        p:SetSize(14, 14)
        -- 0.5.930: round on the world map too - dark disc behind, icon cropped to a circle (previously the
        -- ring lay over a square icon, the corners stuck out)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetTexture(ns.MEDIA .. "pindisc")   -- 0.5.932: own textures that fill the area completely (dot/ring are smaller and paper-thin)
        p.bg:SetPoint("TOPLEFT", -3, 3) p.bg:SetPoint("BOTTOMRIGHT", 3, -3)
        p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- set BEFORE the mask (SetTexCoord on a masked texture throws errors)
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
        p.ring:SetPoint("TOPLEFT", -3, 3) p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wPool[wUsed] = p
    end
    if p:GetParent() ~= canvas then p:SetParent(canvas) end
    return p
end
local function tipOf(r)
    local k = GM.KINDS[r.kind]
    return { K.hex(k.color) .. ((r.name ~= "" and r.name) or L[k.name]) .. "|r" .. (harvested(r, ns.now()) and ("  |cff999999" .. L["just harvested"] .. "|r") or ""),
        (L["Found %dx"]):format(r.n or 1) .. "  ·  " .. L["last"] .. " " .. ns.ago(r.ts),
        "|cff888888" .. L["added by"] .. " " .. ns.displayName(r.by or "?") .. "|r" }
end
-- 0.6.431: continent/world map - nodes of the zones below converted (C_Map.GetMapRectOnMap)
function GM.NodesOn(mapID)
    local own = GM.Nodes(mapID)
    if #own > 0 or not (C_Map and C_Map.GetMapRectOnMap) then return own end
    GM.Nodes()
    local out = {}
    for m, list in pairs(byMap or {}) do
        if m ~= mapID then
            local ok, x1, x2, y1, y2 = pcall(C_Map.GetMapRectOnMap, m, mapID)
            if ok and x1 and x2 and y1 and y2 and x2 > x1 and y2 > y1 and (x2 - x1) < 0.9 then
                for _, r in ipairs(list) do
                    out[#out + 1] = setmetatable({ x = x1 + (r.x or 0) * (x2 - x1), y = y1 + (r.y or 0) * (y2 - y1) }, { __index = r })
                end
            end
        end
    end
    return out
end
function GM.DrawWorld()
    for i = 1, wUsed do wPool[i]:Hide() end
    wUsed = 0
    if GM.HideRoute then GM.HideRoute() end
    if S().mapGather == nil then S().mapGather = not S().gatherWorldOff end
    if not S().mapGather or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    -- 0.5.933: size, opacity, circle border and minimum count adjustable (Settings > Areas > Map)
    local s = (1 / math.max(cscale, 0.01)) * (S().gatherWorldScale or 1)
    if GM.DrawRoute then pcall(GM.DrawRoute, mapID, canvas, cw, ch, 1 / math.max(cscale, 0.01)) end
    local alpha, frame, tnow = S().gatherWorldAlpha or 1, not S().gatherRingOff, ns.now()
    -- 0.6.406: merge nearby nodes of the same kind into one icon with a number (distance on screen, so
    -- depending on zoom: zooming in splits the groups again); icons a bit smaller
    local GAP = 22 * (S().gatherWorldScale or 1)   -- screen pixels
    local groups = {}
    for _, r in ipairs(GM.NodesOn(mapID)) do
        local k = GM.KINDS[r.kind]
        if k and shown(r) then
            local sx, sy = r.x * cw * cscale, r.y * ch * cscale
            local hit
            for _, g in ipairs(groups) do
                if g.kind == r.kind and (g.sx - sx) ^ 2 + (g.sy - sy) ^ 2 < GAP * GAP then hit = g break end
            end
            if hit then
                hit.n = hit.n + 1
                hit.x, hit.y = hit.x + r.x, hit.y + r.y
                hit.list[#hit.list + 1] = r
                if not harvested(r, tnow) then hit.hv = false end
            else
                groups[#groups + 1] = { kind = r.kind, sx = sx, sy = sy, x = r.x, y = r.y, n = 1, list = { r }, hv = harvested(r, tnow) }
            end
        end
    end
    local ps = s * 0.85
    for _, g in ipairs(groups) do
        local k = GM.KINDS[g.kind]
        local r = g.list[1]
        local p = wPin(canvas)
        local hv = g.hv
        p:SetAlpha(alpha * freshness(r, tnow))
        p.bg:SetShown(frame) p.ring:SetShown(frame)
        p.icon:SetTexture(k.icon)
        p.icon:SetDesaturated(hv)
        if hv then p.ring:SetVertexColor(0.5, 0.5, 0.5) else p.ring:SetVertexColor(k.color[1], k.color[2], k.color[3]) end
        if not p.cnt then
            p.cnt = p:CreateFontString(nil, "OVERLAY")
            p.cnt:SetFont(K.FONT, 9, "OUTLINE")
            p.cnt:SetPoint("CENTER", p, "BOTTOMRIGHT", 1, 1)
        end
        p.cnt:SetText(g.n > 1 and tostring(g.n) or "")
        if g.n > 1 then
            p.tip = { (L[k.name] or k.name or "") .. "  |cff888888x" .. g.n .. "|r", L["Several nodes close together - zoom in to see them one by one."] }
        else
            p.tip = tipOf(r)
        end
        p:SetScale(ps)
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", (g.x / g.n * cw) / ps, (-g.y / g.n * ch) / ps)
        p:SetFrameStrata(canvas:GetFrameStrata())
        p:SetFrameLevel(math.min(8900, canvas:GetFrameLevel() + 2400))   -- 0.6.393: above all map layers (at +55 painted over)
        p:Show()
    end
end

-- minimap: same math as Oasis' guild dots (radius per zoom level)
local MM_SIZE = {
    indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
    outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 6, [4] = 200, [5] = 133 + 1 / 3 },
}
local mPool, mUsed = {}, 0
local function mPin()
    mUsed = mUsed + 1
    local p = mPool[mUsed]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(14, 14)
        if ns.MiniPinLayer then ns.MiniPinLayer(p, 2) end
        -- 0.6.380: soft glow when the real node dot lies in the ring (brightness via color, ADD)
        p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
        p.glow:SetTexture(ns.MEDIA .. "halo_ring")   -- 0.6.383: soft glow around the ring, center clear
        p.glow:SetBlendMode("ADD")
        p.glow:SetPoint("TOPLEFT", -14, 14) p.glow:SetPoint("BOTTOMRIGHT", 14, -14)
        p.glow:Hide()
        -- 0.5.929: icon in a circle - dark disc, round-cropped icon, ring in the color of the kind
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetTexture(ns.MEDIA .. "pindisc")   -- 0.5.932: own textures that fill the area completely (dot/ring are smaller and paper-thin)
        p.bg:SetPoint("TOPLEFT", -3, 3) p.bg:SetPoint("BOTTOMRIGHT", 3, -3)
        p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- set BEFORE the mask (SetTexCoord on a masked texture throws errors)
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
        p.ring:SetPoint("TOPLEFT", -3, 3) p.ring:SetPoint("BOTTOMRIGHT", 3, -3)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if self.rec then K.ShowTip(self, tipOf(self.rec)) end end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mPool[mUsed] = p
    end
    return p
end
local function cvar(n) return (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(n)) or (GetCVar and GetCVar(n)) end
local lastSig
-- 0.5.929: the icons lagged behind while running (redraw only once per second). Now two ticks:
--   * once per second: pick nearby nodes (near) and read the game settings
--   * about 30x per second: only reposition these few points - and only if position/facing/zoom changed
local near, nearAt, nearMap, cvRotate, cvZoom = {}, 0, nil, false, nil
function GM.DrawMinimap()
    if S().gatherMiniOff or not Minimap or ns.inInstance() then
        if GM.RouteArrow then GM.RouteArrow() end
        for i = 1, mUsed do mPool[i]:Hide() end
        mUsed, lastSig, nearAt = 0, nil, 0
        return
    end
    local map, mx, my = myPos()
    local now = GetTime()
    local w, h
    if map then w, h = C_Map.GetMapWorldSize(map) end
    if map and w and w > 0 and (now - nearAt >= 1 or map ~= nearMap) then
        nearAt, nearMap = now, map
        cvRotate, cvZoom = cvar("rotateMinimap") == "1", tonumber(cvar("minimapZoom"))
        for i = #near, 1, -1 do near[i] = nil end
        local reach = 360   -- meters: largest minimap radius (233) plus the distance travelled in one second
        for _, r in ipairs(GM.Nodes(map)) do
            if shown(r) and not GM.KINDS[r.kind].poi then
                local dx, dy = (r.x - mx) * w, (r.y - my) * h
                if dx * dx + dy * dy < reach * reach then near[#near + 1] = r end
            end
        end
        lastSig = nil
    end
    -- nothing moved, rotated, zoomed and no new list: do nothing
    local sig = map and (map .. ":" .. math.floor((mx or 0) * 200000) .. ":" .. math.floor((my or 0) * 200000) .. ":" .. (Minimap:GetZoom() or 0)
        .. ":" .. math.floor((ns.safe(GetPlayerFacing and GetPlayerFacing()) or 0) * 200) .. ":" .. #near) or "none"
    if sig == lastSig then return end
    lastSig = sig
    for i = 1, mUsed do mPool[i]:Hide() end
    mUsed = 0
    if not map or not w or w == 0 then if GM.RouteArrow then GM.RouteArrow() end return end
    local zoom = Minimap:GetZoom() or 0
    local indoors = (cvZoom == zoom) and "outdoor" or "indoor"
    local radius = (MM_SIZE[indoors][zoom] or 300) / 2
    local half = Minimap:GetWidth() / 2
    local facing = cvRotate and ns.safe(GetPlayerFacing and GetPlayerFacing()) or nil
    local sinF, cosF = 0, 1
    if facing then sinF, cosF = math.sin(facing), math.cos(facing) end
    local sc, alpha, frame, tnow = S().gatherMiniScale or 1, S().gatherMiniAlpha or 1, not S().gatherRingOff, ns.now()
    for _, r in ipairs(near) do
        local k = GM.KINDS[r.kind]
        if k then
            local dx, dy = (r.x - mx) * w, (r.y - my) * h
            if facing then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
            local nx, ny = dx / radius, dy / radius
            if nx * nx + ny * ny < 0.81 and (not ns.MiniPinVisible or ns.MiniPinVisible(nx * half, ny * half)) then   -- only inside the circle, do not stack at the edge; center clear
                local p = mPin()
                local hv = harvested(r, tnow)
                if p.tex ~= k.icon or p.hv ~= hv then
                    p.icon:SetTexture(k.icon)
                    p.icon:SetDesaturated(hv)
                    p.tex, p.hv = k.icon, hv
                    if p.ring then
                        if hv then p.ring:SetVertexColor(0.5, 0.5, 0.5) else p.ring:SetVertexColor(k.color[1], k.color[2], k.color[3]) end
                    end
                end
                p.rec = r
                p:SetScale(sc)   -- distances count in icon scale -> divide by sc
                -- 0.6.405: shared nodes (from others) much more transparent than own; fade softly near the player arrow
                local own = r.by and ns.isMe(r.by)
                local cd = math.sqrt((nx * half) ^ 2 + (ny * half) ^ 2)
                local nearFade = math.max(0, math.min(1, (cd - 20) / 14))
                p:SetAlpha(alpha * freshness(r, tnow) * (own and 1 or 0.45) * nearFade)
                -- 0.6.144: transparent - no dark disc, image half transparent, only the ring stays strong.
                -- This way you see the game's real node dot below (it always lies under addon icons).
                if p.bg then p.bg:SetShown(false) p.ring:SetShown(frame) end
                -- 0.6.378: nearby (up to 80 m) only a thin, half-transparent ring - there the game shows the
                -- real node dot, which always lies under addon icons; farther away icon + ring as before
                local rx, ry = (r.x - mx) * w, (r.y - my) * h
                local close = rx * rx + ry * ry < 80 * 80
                p.icon:SetAlpha(close and 0 or 0.45)
                -- 0.6.386: nearby no hard ring (shows every small offset to the real dot), only a soft glow
                if p.ring then p.ring:SetAlpha(close and 0.35 or 1) p.ring:SetShown(frame or close) end   -- 0.6.388: near: very faint ring
                p.close, p.kcol = close and not hv, k.color
                -- 0.6.390: no glow - Oasis does not know whether something is really there right now (empty nodes glowed too)
                if p.glow then p.glow:Hide() end
                p.close = nil
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", nx * half / sc, -ny * half / sc)
                p:Show()
            end
        end
    end
    if GM.RouteArrow then GM.RouteArrow(map, mx, my, w, h, radius, half, facing, sinF, cosF) end
end
-- redraw immediately after changed settings (otherwise only on the next movement)
function GM.Refresh()
    lastSig, nearAt = nil, 0
    if GM.ResetRoutes then GM.ResetRoutes() end
    pcall(GM.DrawMinimap)
    pcall(GM.DrawWorld)
end
ns.Listen("LOGIN", function()
    if ns.Map and ns.Map.UpdateWorldPins then hooksecurefunc(ns.Map, "UpdateWorldPins", function() pcall(GM.DrawWorld) end) end
    -- follow smoothly: own ticker (about 30x per second); DrawMinimap only works when something changed
    local driver, acc = CreateFrame("Frame"), 0
    driver:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.033 then return end
        acc = 0
        pcall(GM.DrawMinimap)
        -- 0.6.380: nearby nodes pulse (ring + glow), independent of redrawing
        local tt = GetTime()
        local k = 0.85 + 0.35 * math.sin(tt * 4)   -- 0.6.388: much stronger (was barely visible on dark background)
        if ns.db and ns.db.settings.noAnim then k = 1 end
        for i = 1, mUsed do
            local pin = mPool[i]
            if pin and pin.close and pin.glow and pin.kcol then
                local c = pin.kcol
                pin.glow:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, 1)
            end
        end
    end)
end)
ns.Listen("STORE", function(coll) if coll == "nodes" and WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end end)
------------------------------------------------------------------------
-- minimap helper for other modules (rares, markers ...): fetch the state once per tick, then convert points
------------------------------------------------------------------------
function GM.MiniCtx()
    if not Minimap or ns.inInstance() then return nil end
    local map, mx, my = myPos()
    if not (map and mx) then return nil end
    local w, h = C_Map.GetMapWorldSize(map)
    if not w or w == 0 then return nil end
    local zoom = Minimap:GetZoom() or 0
    local kind = (tonumber(cvar("minimapZoom")) == zoom) and "outdoor" or "indoor"
    local facing = cvar("rotateMinimap") == "1" and ns.safe(GetPlayerFacing and GetPlayerFacing()) or nil
    return { map = map, mx = mx, my = my, w = w, h = h, radius = (MM_SIZE[kind][zoom] or 300) / 2, half = Minimap:GetWidth() / 2,
        sinF = facing and math.sin(facing) or 0, cosF = facing and math.cos(facing) or 1 }
end
-- returns: offset x, y (pixels from minimap center), distance as fraction of the radius (>= 0.9 = at the edge), distance in meters
function GM.MiniPlace(c, x, y)
    local dx, dy = (x - c.mx) * c.w, (y - c.my) * c.h
    local meters = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx * c.cosF - dy * c.sinF, dx * c.sinF + dy * c.cosF
    local nx, ny = dx / c.radius, dy / c.radius
    return nx * c.half, -ny * c.half, math.sqrt(nx * nx + ny * ny), meters
end

------------------------------------------------------------------------
-- 0.6.487: take nodes from the minimap - no addon can read Blizzard's yellow dots (herb/ore tracking),
-- but on mouseover their name is in the tooltip. Known herb/ore names + mouse position -> guild gathering map.
------------------------------------------------------------------------
local NODE_NAMES = {
    herb = { "Peacebloom", "Friedensblume", "Silverleaf", "Silberblatt", "Earthroot", "Erdwurzel", "Mageroyal", "Maguskoenigskraut",
        "Briarthorn", "Wilddornrose", "Bruiseweed", "Beulengras", "Stranglekelp", "Wuergetang", "Wild Steelbloom", "Wildstahlblume",
        "Grave Moss", "Grabmoos", "Kingsblood", "Koenigsblut", "Liferoot", "Lebenswurz", "Fadeleaf", "Blassblatt", "Goldthorn", "Golddorn",
        "Khadgar's Whisker", "Khadgars Schnurrbart", "Wintersbite", "Winterbiss", "Firebloom", "Feuerbluete", "Purple Lotus", "Lila Lotus",
        "Arthas' Tears", "Arthas' Traenen", "Sungrass", "Sonnengras", "Blindweed", "Blindkraut", "Ghost Mushroom", "Geisterpilz",
        "Gromsblood", "Gromsblut", "Golden Sansam", "Goldener Sansam", "Dreamfoil", "Traumblatt", "Mountain Silversage", "Bergsilbersalbei",
        "Plaguebloom", "Pestbluete", "Icecap", "Eiskappe", "Black Lotus", "Schwarzer Lotus" },
    ore = { "Copper Vein", "Kupferader", "Tin Vein", "Zinnader", "Silver Vein", "Silberader", "Iron Deposit", "Eisenvorkommen",
        "Gold Vein", "Goldader", "Mithril Deposit", "Mithrilablagerung", "Truesilver Deposit", "Echtsilberablagerung",
        "Small Thorium Vein", "Kleine Thoriumader", "Rich Thorium Vein", "Reiche Thoriumader", "Dark Iron Deposit", "Dunkeleisenablagerung",
        "Incendicite Mineral Vein", "Pyrophormineralvorkommen", "Lesser Bloodstone Deposit", "Geringe Blutsteinablagerung",
        "Ooze Covered Silver Vein", "Ooze Covered Iron Deposit", "Ooze Covered Mithril Deposit", "Ooze Covered Thorium Vein" },
}
local function umlautLess(t) return (t:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")) end
local nameKind
local function kindForName(n)
    if not nameKind then
        nameKind = {}
        for kind, list in pairs(NODE_NAMES) do for _, x in ipairs(list) do nameKind[x:lower()] = kind end end
    end
    local k = nameKind[n:lower()] or nameKind[umlautLess(n):lower()]
    if k then return k end
    -- already harvested by the guild once (any language)
    for _, r in ipairs(GM.Nodes()) do
        if (r.kind == "herb" or r.kind == "ore") and r.name and r.name ~= "" and r.name:lower() == n:lower() then
            nameKind[n:lower()] = r.kind
            return r.kind
        end
    end
end
GM.KindForName = kindForName
local hoverSeen = {}
local function fromMinimapTooltip()
    -- 0.6.506: the tooltip owner is the minimap, its border or a child depending on the client - what matters is the mouse over the minimap
    if not (Minimap and GameTooltip and GameTooltip:IsShown() and Minimap:IsMouseOver()) then return end
    if ns.db.settings.shareNodes == false or ns.db.settings.gatherHoverOff then return end
    local c = GM.MiniCtx()
    if not c then return end
    local cx, cy = GetCursorPosition()
    local sc = Minimap:GetEffectiveScale()
    local mx0, my0 = Minimap:GetCenter()
    if not (cx and mx0) then return end
    local ox, oy = cx / sc - mx0, cy / sc - my0
    -- pixels -> meters (inverse of GM.MiniPlace), undo minimap rotation
    local nx, ny = ox / c.half, -oy / c.half
    if nx * nx + ny * ny > 1.05 then return end
    local rx, ry = nx * c.radius, ny * c.radius
    local dx = rx * c.cosF + ry * c.sinF
    local dy = -rx * c.sinF + ry * c.cosF
    local x, y = c.mx + dx / c.w, c.my + dy / c.h
    for i = 1, GameTooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local txt = fs and ns.safe(fs:GetText())
        if type(txt) == "string" then
            for line in txt:gmatch("[^\n]+") do
                local n = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local kind = n ~= "" and kindForName(n)
                if kind then
                    local key = kind .. n .. math.floor(x * 400) .. ":" .. math.floor(y * 400)
                    if not hoverSeen[key] then
                        hoverSeen[key] = true
                        local ok, res = pcall(GM.Record, kind, n, x, y)
                        -- 0.6.489: short feedback so you see that it works
                        if ok and res == "neu gespeichert" then ns.print((L["Gathering spot added: %s"]):format(n))
                        elseif ok and res == "schon bekannt" then ns.print((L["Node already known: %s"]):format(n)) end
                    end
                end
            end
        end
    end
end
if GameTooltip then
    GameTooltip:HookScript("OnShow", function() pcall(fromMinimapTooltip) end)
end
local ghAcc = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, el)
    ghAcc = ghAcc + (el or 0)
    if ghAcc < 0.5 then return end
    ghAcc = 0
    if Minimap and Minimap:IsMouseOver() then pcall(fromMinimapTooltip) end
end)

------------------------------------------------------------------------
-- 0.6.591: minimap scan - finds the yellow tracking dots by itself, without hovering or gathering.
-- An invisible probe (Minimap:UpdateMouseoverAtPoint) walks a grid over the minimap, a few points per frame,
-- and C_TooltipInfo.GetMinimapMouseover names what lies under it. Hits of the same name lying together
-- = one dot, its center goes into the gathering map like a hovered node. Off with /oa gatherscan.
-- Paused in combat, in instances, while the mouse is over the minimap and while the minimap is hidden.
------------------------------------------------------------------------
local SCAN_STEP, SCAN_PER_FRAME, SCAN_PAUSE = 7, 50, 2
local scanJob, scanWait = nil, 0
GM.scanStats = { runs = 0, hits = 0, added = 0 }
local function canScan()
    local s = ns.db and ns.db.settings
    if not s or s.gatherScan == false or s.shareNodes == false then return false end
    if not (Minimap and Minimap.UpdateMouseoverAtPoint and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover) then return false end
    if not Minimap:IsVisible() or Minimap:IsMouseOver() then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if ns.inInstance() then return false end
    return true
end
-- pixel offset from the minimap center -> map position (same math as the hover reader above)
local function pxToMap(c, ox, oy)
    local nx, ny = ox / c.half, -oy / c.half
    local rx, ry = nx * c.radius, ny * c.radius
    local dx = rx * c.cosF + ry * c.sinF
    local dy = -rx * c.sinF + ry * c.cosF
    return c.mx + dx / c.w, c.my + dy / c.h
end
local function newScan()
    local c = GM.MiniCtx()
    if not c then return nil end
    local pts, r = {}, c.half - 3
    for ox = -r, r, SCAN_STEP do
        for oy = -r, r, SCAN_STEP do
            if ox * ox + oy * oy <= r * r then pts[#pts + 1] = { ox, oy } end
        end
    end
    return { c = c, pts = pts, i = 1, hits = {} }
end
local function probe(job, sc, cx, cy, p)
    Minimap:UpdateMouseoverAtPoint((cx + p[1]) * sc, (cy + p[2]) * sc)
    local data = ns.safe(C_TooltipInfo.GetMinimapMouseover())
    local lines = type(data) == "table" and ns.safe(data.lines)
    if type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        local txt = ns.safe(line.leftText)
        if type(txt) == "string" then
            for part in txt:gmatch("[^\n]+") do
                local n = part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local kind = n ~= "" and kindForName(n)
                if kind then
                    local h = job.hits[n]
                    if not h then h = { kind = kind } job.hits[n] = h end
                    h[#h + 1] = p
                end
            end
        end
    end
end
-- connected groups: grid points next to each other (also diagonally) belong together
local function components(list, step)
    local lim, out, used = (step * 1.5) ^ 2, {}, {}
    for i = 1, #list do
        if not used[i] then
            used[i] = true
            local comp, q = { list[i] }, 1
            while q <= #comp do
                local p = comp[q]
                for j = 1, #list do
                    if not used[j] then
                        local dx, dy = list[j][1] - p[1], list[j][2] - p[2]
                        if dx * dx + dy * dy <= lim then used[j] = true comp[#comp + 1] = list[j] end
                    end
                end
                q = q + 1
            end
            out[#out + 1] = comp
        end
    end
    return out
end
local function center(pts)
    local x, y = 0, 0
    for _, p in ipairs(pts) do x, y = x + p[1], y + p[2] end
    return x / #pts, y / #pts
end
-- k centers in a blob of overlapping dots (k-means, started from points far apart)
local function kmeans(pts, k)
    local cs = { { pts[1][1], pts[1][2] } }
    while #cs < k do
        local best, bd = nil, -1
        for _, p in ipairs(pts) do
            local m = math.huge
            for _, c in ipairs(cs) do m = math.min(m, (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2) end
            if m > bd then best, bd = p, m end
        end
        cs[#cs + 1] = { best[1], best[2] }
    end
    for _ = 1, 8 do
        local sx, sy, n = {}, {}, {}
        for i = 1, k do sx[i], sy[i], n[i] = 0, 0, 0 end
        for _, p in ipairs(pts) do
            local bi, bd = 1, math.huge
            for i, c in ipairs(cs) do
                local d = (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2
                if d < bd then bi, bd = i, d end
            end
            sx[bi], sy[bi], n[bi] = sx[bi] + p[1], sy[bi] + p[2], n[bi] + 1
        end
        for i = 1, k do if n[i] > 0 then cs[i] = { sx[i] / n[i], sy[i] / n[i] } end end
    end
    return cs
end
-- 0.6.592: dots lying close together melt into one blob on the coarse grid. Such blobs are probed again on a
-- fine grid (spread over frames); the dot size is measured from the smallest blob, the area then says how many
-- dots a blob holds.
local FINE, MAX_FINE = 3, 900
GM.dotRadius = nil   -- measured radius of one minimap dot (minimap units)
local function singlePoints()
    local r = GM.dotRadius
    if not r then return 0 end   -- not measured yet: probe every blob once
    return math.floor(math.pi * r * r / SCAN_STEP ^ 2)   -- coarse hits vary a lot: rather probe once too often
end
local function fineList(job)
    local list, single = {}, singlePoints()
    for name, h in pairs(job.hits) do
        for _, comp in ipairs(components(h, SCAN_STEP)) do
            if #comp > single and #list < 40 then
                local x0, y0 = center(comp)
                local r = SCAN_STEP * (1.5 + math.sqrt(#comp) / 2)
                list[#list + 1] = { name = name, kind = h.kind, x = x0, y = y0, r = r, comp = comp }
            else
                list[#list + 1] = { name = name, kind = h.kind, done = { center(comp) } }
            end
        end
    end
    -- the fine points of all blobs, in a queue
    local pts, budget = {}, MAX_FINE
    for gi, g in ipairs(list) do
        if not g.done then
            g.hits = {}
            for ox = g.x - g.r, g.x + g.r, FINE do
                for oy = g.y - g.r, g.y + g.r, FINE do
                    if budget > 0 then budget = budget - 1 pts[#pts + 1] = { ox, oy, gi } end
                end
            end
        end
    end
    job.groups, job.fpts, job.fi = list, pts, 1
end
local function fineProbe(job, sc, cx, cy, p)
    local g = job.groups[p[3]]
    Minimap:UpdateMouseoverAtPoint((cx + p[1]) * sc, (cy + p[2]) * sc)
    local data = ns.safe(C_TooltipInfo.GetMinimapMouseover())
    local lines = type(data) == "table" and ns.safe(data.lines)
    if type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        local txt = ns.safe(line.leftText)
        if type(txt) == "string" and txt:find(g.name, 1, true) then g.hits[#g.hits + 1] = { p[1], p[2] } return end
    end
end
local function finishScan(job)
    -- dot size: the smallest fine blob is one dot
    for _, g in ipairs(job.groups) do
        if g.hits then
            g.parts = components(g.hits, FINE)
            for _, c in ipairs(g.parts) do
                local r = math.sqrt(#c * FINE * FINE / math.pi)
                if r >= 2 and (not GM.dotRadius or r < GM.dotRadius) then GM.dotRadius = r end
            end
        end
    end
    local added, live = {}, {}
    local one = GM.dotRadius and math.pi * GM.dotRadius ^ 2 or nil
    for _, g in ipairs(job.groups) do
        local centers = {}
        if g.done then centers[1] = g.done
        elseif not g.parts or #g.parts == 0 then centers[1] = { center(g.comp) }
        else
            for _, c in ipairs(g.parts) do
                local k = one and math.max(1, math.floor(#c * FINE * FINE / one + 0.35)) or 1
                if k == 1 then centers[#centers + 1] = { center(c) }
                else for _, m in ipairs(kmeans(c, math.min(k, 6))) do centers[#centers + 1] = m end end
            end
        end
        for _, m in ipairs(centers) do
            GM.scanStats.hits = GM.scanStats.hits + 1
            local x, y = pxToMap(job.c, m[1], m[2])
            live[#live + 1] = { kind = g.kind, name = g.name, map = job.c.map, x = x, y = y }
            local ok, res = pcall(GM.Record, g.kind, g.name, x, y)
            if ok and res == "neu gespeichert" then added[#added + 1] = g.name end
        end
    end
    -- dots on the minimap right now (for arrow, pin and sparkles)
    GM.scanLive, GM.scanLiveAt = live, GetTime and GetTime() or 0
    GM.scanStats.runs = GM.scanStats.runs + 1
    GM.scanStats.added = GM.scanStats.added + #added
    if #added > 0 then ns.print((L["Minimap scan: %d new gathering spots (%s)"]):format(#added, table.concat(added, ", "))) end
end
function GM.ScanStep(el)
    if not scanJob then
        scanWait = scanWait - (el or 0)
        if scanWait > 0 or not canScan() then return end
        scanJob = newScan()
        if not scanJob then scanWait = SCAN_PAUSE return end
    end
    -- the player moved the mouse onto the minimap or a fight started: drop this run, the tooltip belongs to the player
    if not canScan() then scanJob, scanWait = nil, SCAN_PAUSE return end
    local job = scanJob
    local sc = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    if not cx then scanJob = nil return end
    local soft = Minimap.SetUsingSoftCursor
    if soft then pcall(soft, Minimap, true) end
    if not job.fpts then
        for i = job.i, math.min(job.i + SCAN_PER_FRAME - 1, #job.pts) do pcall(probe, job, sc, cx, cy, job.pts[i]) end
        job.i = job.i + SCAN_PER_FRAME
        if job.i > #job.pts then fineList(job) end
    else
        for i = job.fi, math.min(job.fi + SCAN_PER_FRAME - 1, #job.fpts) do pcall(fineProbe, job, sc, cx, cy, job.fpts[i]) end
        job.fi = job.fi + SCAN_PER_FRAME
    end
    if soft then pcall(soft, Minimap, false) end
    if job.fpts and job.fi > #job.fpts then
        scanJob, scanWait = nil, SCAN_PAUSE
        local ok, err = pcall(finishScan, job)
        if not ok and ns.Debug then ns.Debug("gatherscan", err) end
    end
end
CreateFrame("Frame"):SetScript("OnUpdate", function(_, el) GM.ScanStep(el) end)
ns.slash.gatherscan = function()
    ns.db.settings.gatherScan = ns.db.settings.gatherScan == false and true or false
    local st = GM.scanStats
    ns.print((ns.db.settings.gatherScan and L["Minimap scan on: herb and ore dots are found by themselves."] or L["Minimap scan off."])
        .. (" (%d / %d / %d)"):format(st.runs, st.hits, st.added))
end
ns.slash.sammelscan = ns.slash.gatherscan

------------------------------------------------------------------------
-- Gathering route (0.5.934): connects the visible nodes of a zone into a round trip.
-- World map: line. Minimap: arrow to the next point (left-click skips, right-click goes back).
-- Order: nearest neighbor, then 2-opt (untangles crossings). At most 120 points - the most found.
------------------------------------------------------------------------
local ROUTE_MAX, ARRIVE = 120, 12
local routes = {}   -- per map: { sig, list, len, idx } - the world map often shows a different zone than your own
local function routeNodes(map)
    local out = {}
    for _, r in ipairs(GM.Nodes(map)) do
        if shown(r) and not GM.KINDS[r.kind].poi then out[#out + 1] = r end
    end
    if #out > ROUTE_MAX then
        table.sort(out, function(a, b) if (a.n or 1) ~= (b.n or 1) then return (a.n or 1) > (b.n or 1) end return tostring(a.id) < tostring(b.id) end)
        for i = #out, ROUTE_MAX + 1, -1 do out[i] = nil end
    end
    return out
end
function GM.BuildTour(nodes, w, h)
    local n = #nodes
    if n < 2 then return nodes, 0 end
    local function d(a, b) local dx, dy = (a.x - b.x) * w, (a.y - b.y) * h return math.sqrt(dx * dx + dy * dy) end
    local tour, used = { nodes[1] }, { true }
    for _ = 2, n do
        local last, best, bd = tour[#tour], nil, nil
        for j = 1, n do
            if not used[j] then
                local dj = d(last, nodes[j])
                if not bd or dj < bd then best, bd = j, dj end
            end
        end
        used[best] = true
        tour[#tour + 1] = nodes[best]
    end
    local improved, pass = true, 0
    while improved and pass < 25 do
        improved, pass = false, pass + 1
        for i = 1, n - 2 do
            for j = i + 2, n do
                local a, b, c, e = tour[i], tour[i + 1], tour[j], tour[(j % n) + 1]
                if a ~= e and d(a, c) + d(b, e) < d(a, b) + d(c, e) - 0.01 then
                    local lo, hi = i + 1, j
                    while lo < hi do tour[lo], tour[hi] = tour[hi], tour[lo] lo, hi = lo + 1, hi - 1 end
                    improved = true
                end
            end
        end
    end
    local len = 0
    for i = 1, n do len = len + d(tour[i], tour[(i % n) + 1]) end
    return tour, len
end
function GM.Route(map)
    if not map or not S().gatherRoute then return nil end
    local nodes = routeNodes(map)
    local sig = map .. ":" .. #nodes .. ":" .. (S().gatherMinCount or 1) .. ":" .. tostring(byMap)
        .. (showKind("herb") and "h" or "") .. (showKind("ore") and "o" or "") .. (showKind("treasure") and "t" or "")
    local route = routes[map]
    if route and route.sig == sig then return route end
    local w, h = C_Map.GetMapWorldSize(map)
    if not w or w == 0 then w, h = 1, 1 end
    local list, len = GM.BuildTour(nodes, w, h)
    route = { map = map, sig = sig, list = list, len = len }
    routes[map] = route
    return route
end
-- next point of the route; advances as soon as you are there
function GM.RouteTarget(map, mx, my, w, h)
    local rt = GM.Route(map)
    if not rt or #rt.list < 2 then return nil end
    local function dist(t) local dx, dy = (t.x - mx) * w, (t.y - my) * h return math.sqrt(dx * dx + dy * dy) end
    if not rt.idx or rt.idx > #rt.list then
        local bd
        for i, t in ipairs(rt.list) do local di = dist(t) if not bd or di < bd then rt.idx, bd = i, di end end
    end
    local t = rt.list[rt.idx]
    local dm = dist(t)
    if dm < ARRIVE then
        rt.idx = rt.idx % #rt.list + 1
        t = rt.list[rt.idx]
        dm = dist(t)
    end
    return t, dm, rt.idx, #rt.list
end
function GM.RouteSkip(step)
    local map = myPos()
    local rt = map and routes[map]
    if not (rt and rt.idx) then return end
    rt.idx = (rt.idx - 1 + step) % #rt.list + 1
    lastSig = nil
end

function GM.ResetRoutes() for _, rt in pairs(routes) do rt.sig = nil end end
local rFrame, rLines = nil, {}
function GM.HideRoute() for _, l in ipairs(rLines) do l:Hide() end end
function GM.DrawRoute(mapID, canvas, cw, ch, cs)
    GM.HideRoute()
    local rt = GM.Route(mapID)
    if not rt or #rt.list < 2 then return end
    if not rFrame then rFrame = CreateFrame("Frame", nil, canvas) end
    if rFrame:GetParent() ~= canvas then rFrame:SetParent(canvas) end
    rFrame:SetAllPoints(canvas)
    rFrame:SetFrameStrata(canvas:GetFrameStrata())
    rFrame:SetFrameLevel(canvas:GetFrameLevel() + 54)
    local n = #rt.list
    for i, a in ipairs(rt.list) do
        local b = rt.list[(i % n) + 1]
        local l = rLines[i]
        if not l then
            l = rFrame:CreateLine(nil, "ARTWORK")
            rLines[i] = l
        end
        local now = rt.idx and (i == (rt.idx - 2) % n + 1) or false   -- the segment to the next point brighter
        l:SetColorTexture(1, 0.84, 0.36, now and 1 or 0.6)
        l:SetThickness(math.max(1, (now and 3 or 2) * cs))
        l:SetStartPoint("TOPLEFT", rFrame, a.x * cw, -a.y * ch)
        l:SetEndPoint("TOPLEFT", rFrame, b.x * cw, -b.y * ch)
        l:Show()
    end
end

local arrow
function GM.RouteArrow(map, mx, my, w, h, radius, half, facing, sinF, cosF)
    local t, dm, idx, total
    if map and mx and S().gatherRoute then t, dm, idx, total = GM.RouteTarget(map, mx, my, w, h) end
    if not t then if arrow then arrow:Hide() end return end
    if not arrow then
        arrow = CreateFrame("Button", nil, Minimap)
        arrow:SetSize(20, 20)
        arrow:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        arrow.sh = arrow:CreateTexture(nil, "BACKGROUND")
        arrow.sh:SetTexture(ns.MEDIA .. "pinarrow")
        arrow.sh:SetPoint("TOPLEFT", -3, 3) arrow.sh:SetPoint("BOTTOMRIGHT", 3, -3)
        arrow.sh:SetVertexColor(0, 0, 0, 0.85)
        arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
        arrow.tex:SetTexture(ns.MEDIA .. "pinarrow")
        arrow.tex:SetAllPoints()
        arrow.tex:SetVertexColor(1, 0.84, 0.36)
        arrow.txt = K.Text(arrow, 10, C.text)
        arrow.txt:SetPoint("TOP", arrow, "BOTTOM", 0, 1)
        arrow.txt:SetShadowOffset(1, -1)
        arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        arrow:SetScript("OnClick", function(_, btn) GM.RouteSkip(btn == "RightButton" and -1 or 1) pcall(GM.DrawMinimap) if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end end)
        arrow:SetScript("OnEnter", function(self)
            local r = self.rec
            local k = r and GM.KINDS[r.kind]
            K.ShowTip(self, { L["Next node on the route"] .. (self.pos or ""),
                k and (K.hex(k.color) .. ((r.name ~= "" and r.name) or L[k.name]) .. "|r") or "",
                "|cff888888" .. L["Left-click: skip  ·  Right-click: back"] .. "|r" })
        end)
        arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local dx, dy = (t.x - mx) * w, (t.y - my) * h
    if facing then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then arrow:Hide() return end
    -- arrow sits just before the point (or at the edge if the point is outside) and points at it
    local px = math.max(0, math.min(len / radius, 0.8) * half - 15)
    local ux, uy = dx / len, dy / len
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", Minimap, "CENTER", ux * px, -uy * px)
    local atan2 = math.atan2 or math.atan
    arrow.tex:SetRotation(atan2(-ux, -uy))
    arrow.sh:SetRotation(atan2(-ux, -uy))
    arrow.txt:SetText(math.floor(dm + 0.5) .. " m")
    arrow.rec, arrow.pos = t, ("  |cff888888%d/%d|r"):format(idx, total)
    arrow:Show()
end
ns.Listen("STORE", function(coll) if coll == "nodes" then for _, rt in pairs(routes) do rt.sig = nil end end end)

------------------------------------------------------------------------
-- Sample data (0.5.931): nodes around your own location so minimap and world map show
-- something. Entering /oa demo again moves them to the new location. Local only (Store.merge sends nothing);
-- Demo.Remove clears all "demo-" entries again.
------------------------------------------------------------------------
local DEMO_NODES = {   -- { kind, direction in degrees, distance in meters, times found }
    { "herb", 20, 35, 4 }, { "herb", 75, 70, 2 }, { "herb", 140, 55, 7 }, { "herb", 200, 110, 1 }, { "herb", 265, 45, 3 },
    { "herb", 320, 150, 5 }, { "herb", 100, 190, 2 }, { "herb", 300, 85, 6 },
    { "ore", 45, 60, 3 }, { "ore", 115, 125, 1 }, { "ore", 170, 30, 8 }, { "ore", 235, 95, 2 }, { "ore", 290, 170, 4 }, { "ore", 350, 65, 2 },
    { "treasure", 10, 100, 1 }, { "treasure", 155, 160, 1 }, { "treasure", 250, 140, 2 }, { "treasure", 215, 50, 1 },
}
function GM.SeedDemo()
    local map, mx, my = myPos()
    local w, h
    if map then w, h = C_Map.GetMapWorldSize(map) end
    if not (map and w and w > 0 and h and h > 0) then return 0 end
    local now, n = ns.now(), 0
    for i, d in ipairs(DEMO_NODES) do
        local a = math.rad(d[2])
        local x, y = mx + math.sin(a) * d[3] / w, my - math.cos(a) * d[3] / h
        if x > 0.01 and x < 0.99 and y > 0.01 and y < 0.99 then
            Store.merge("nodes", { id = "demo-nd-" .. i, demo = true, kind = d[1], name = "", map = map,
                x = math.floor(x * 10000) / 10000, y = math.floor(y * 10000) / 10000,
                n = d[4], ts = now - ((i == 3 or i == 11) and 60 or (i - 1) * 130000), u = now, by = ns.me() })   -- two "just harvested", rest up to ~25 days old
            n = n + 1
        end
    end
    byMap, allNodes = nil, nil
    if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end
    return n
end
ns.Listen("LOGIN", function()
    local D = ns.Demo
    if D and not D.gatherHooked then
        D.gatherHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) GM.SeedDemo() end
        D.Remove = function(...)
            remove(...)
            byMap, allNodes = nil, nil
            if WorldMapFrame and WorldMapFrame:IsShown() then pcall(GM.DrawWorld) end
        end
        if D.IsActive and D.IsActive() then ns.After(4, GM.SeedDemo) end
    end
end)
function GM.Count()
    local t = {}
    for k in pairs(GM.KINDS) do t[k] = 0 end
    for _, r in ipairs(GM.Nodes()) do if t[r.kind] then t[r.kind] = t[r.kind] + 1 end end
    return t
end
-- named types (e.g. "Peacebloom", "Copper Vein") with number of nodes - for the per-type filter
function GM.Names()
    local seen, out = {}, {}
    for _, r in ipairs(GM.Nodes()) do
        if GM.KINDS[r.kind] and r.name and r.name ~= "" then
            local e = seen[r.name]
            if not e then e = { name = r.name, kind = r.kind, n = 0 } seen[r.name] = e out[#out + 1] = e end
            e.n = e.n + 1
        end
    end
    table.sort(out, function(a, b) if a.kind ~= b.kind then return a.kind < b.kind end return a.name < b.name end)
    return out
end
end)

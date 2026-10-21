-- Oasis: settings page of the Comfort add-on (0.6.602) - sidebar "Comfort > Settings"
-- Gathering (minimap, arrow, sparkles, guild) with a live preview minimap on sample data, plus the comfort
-- helpers and the game chat. These tabs leave the big settings window while this add-on is loaded.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
local L = ns.L
local K, C = ns.K, ns.K.C
if not (K and ns.RegisterPage) then return end

-- 0.6.603: two pages - "Gathering & minimap" (everything map/gathering, with preview) and "Comfort settings"
local KEY, GKEY = "comfortset", "gatherset"
ns.GatherSettingsPage = GKEY
ns.SETTINGS_ELSEWHERE = ns.SETTINGS_ELSEWHERE or {}
ns.SETTINGS_ELSEWHERE.comfort, ns.SETTINGS_ELSEWHERE.gamechat = true, true
if ns.ICONS then
    ns.ICONS[KEY] = ns.ICONS.settings or ns.ICONS.home
    ns.ICONS[GKEY] = ns.ICONS.map or ns.ICONS.compass or ns.ICONS.settings or ns.ICONS.home
end
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "convenience" then
        for i, k in ipairs({ GKEY, KEY }) do
            local has = false
            for _, x in ipairs(g.pages) do if x == k then has = true end end
            if not has then table.insert(g.pages, i, k) end
        end
    end
end

local function S() return ns.db.settings end
-- toggles that are on until switched off (nil = on)
local ON = { mapRevealTint = true, gatherScan = true, gatherSymbols = true, gatherArrowHerb = true, gatherArrowOre = true, gatherArrowTreasure = true,
    gatherArrowRare = true, gatherArrowLeyline = true, gatherAlerts = true, gatherAlertsShare = true, gatherWanted = true, gatherShareArea = true }
local function get(k) if ON[k] then return S()[k] ~= false end return S()[k] and true or false end
local function set(k, v) if ON[k] then S()[k] = v and true or false else S()[k] = v and true or nil end end

local GTABS = {
    { key = "mini", text = "Minimap", preview = true },
    { key = "arrow", text = "Arrow", preview = true },
    { key = "sparkle", text = "Sparkles & pin", preview = true },
    { key = "guild", text = "Guild", preview = true },
    { key = "worldmap", text = "World map", mappreview = true },
}
local CTABS = {
    { key = "comfort", text = "Helpers", tab = "comfort" },
    { key = "gamechat", text = "Game chat", tab = "gamechat" },
}
local OPTS = {
    mini = {
        { "Minimap scan: find nodes by themselves", "gatherScan" },
        { "Gathering symbols on the minimap", "gatherSymbols" },
        { "Switch finders automatically", "gatherSwitch" },
        { "Sound for new nodes", "gatherSound" },
        { "Hide the skill needed in the tooltip", "gatherSkillOff" },
        slider = {
            { "Gathering symbols: shape", "gatherShape", 1, 4, 1, 3, function(v) return L[({ "Square", "Round", "Round with ring", "Slim ring" })[v] or "Round with ring"] end },
            { "Game's gathering dots: size", "gatherDotScale", 0.5, 1, 0.05, 1 },
        },
    },
    arrow = {
        { "Arrow to the nearest node", "gatherArrow" },
        { "Lock arrow", "gatherArrowLock" },
        { "Arrow: herbs and ore first", "gatherArrowProfFirst" },
        { "Arrow: also nodes in caves", "gatherArrowCaves" },
        { "Arrow: herbs", "gatherArrowHerb" },
        { "Arrow: ore", "gatherArrowOre" },
        { "Arrow: treasures", "gatherArrowTreasure" },
        { "Arrow: rares", "gatherArrowRare" },
        { "Arrow: leylines", "gatherArrowLeyline" },
    },
    sparkle = {
        { "Sparkles on herbs and ore nearby", "gatherSparkle" },
        { "Sparkles: hide the game's interact icons", "gatherSparkleHideIcons" },
        { "Sparkles far away (beta)", "gatherSparkleFar" },
        { "Map pin on the nearest node", "gatherPin" },
        slider = {
            { "Sparkle size", "gatherSparkleSize", 50, 200, 10, 100, function(v) return v .. " %" end },
        },
        colors = true,
    },
    worldmap = {
        { "Show unexplored areas on the world map", "mapReveal" },
        { "Tint unexplored areas", "mapRevealTint" },
        { "Move the world map (drag the frame)", "wmMove" },
        { "No reading emote when opening the map", "wmNoEmote" },
        { "Hide town and city icons on continent maps", "wmHideTowns" },
        slider = {
            { "Tint: red", "wmTintR", 0, 1, 0.05, 0.55 },
            { "Tint: green", "wmTintG", 0, 1, 0.05, 0.55 },
            { "Tint: blue", "wmTintB", 0, 1, 0.05, 0.6 },
            { "Tint: opacity", "wmTintA", 0.1, 1, 0.05, 0.85 },
            { "World map size (window)", "wmScale", 0.5, 2, 0.05, 1 },
            { "World map size (maximised)", "wmScaleMax", 0.5, 2, 0.05, 1 },
        },
        resetPos = true,
    },
    guild = {
        { "Guild finds: notices", "gatherAlerts" },
        { "Guild finds: share mine", "gatherAlertsShare" },
        { "Wishlist nodes first", "gatherWanted" },
        { "Leave nearby guild farmers their side", "gatherShareArea" },
        { "Skill-up route", "gatherRouteSkill" },
        { "Gathering route", "gatherRoute" },
        buttons = true,
    },
}

------------------------------------------------------------------------
-- preview minimap with sample nodes (pixels from the middle, 110 = edge)
------------------------------------------------------------------------
local SAMPLE = {
    { name = "Peacebloom", kind = "herb", x = 42, y = 30 },
    { name = "Copper Vein", kind = "ore", x = -52, y = 18 },
    { name = "Tin Vein", kind = "ore", x = -22, y = -58 },
    { name = "Iron Deposit", kind = "ore", x = 70, y = -42 },
    { name = "Kingsblood", kind = "herb", x = -80, y = -30, wanted = true },
    { name = "Liferoot", kind = "herb", x = 22, y = 78, cave = true },
    { name = "Battered Chest", kind = "treasure", x = 86, y = 52 },
    { name = "Silverleaf", kind = "herb", x = -44, y = 82, held = true },
    { name = "Icecap", kind = "herb", x = 6, y = -94, hard = true },
    { name = "Leyline", kind = "leyline", x = -96, y = 40 },
}
local function previewTarget()
    local best, bd
    local ARROW_KEY = { herb = "gatherArrowHerb", ore = "gatherArrowOre", treasure = "gatherArrowTreasure", rare = "gatherArrowRare", leyline = "gatherArrowLeyline" }
    local function try(d, profOnly)
        if not get(ARROW_KEY[d.kind] or "") or d.hard or d.held then return end
        if d.cave and not get("gatherArrowCaves") then return end
        if profOnly and not (d.kind == "herb" or d.kind == "ore") then return end
        local dist = math.sqrt(d.x * d.x + d.y * d.y) * ((d.wanted and get("gatherWanted")) and 0.6 or 1)
        if not bd or dist < bd then best, bd = d, dist end
    end
    for _, d in ipairs(SAMPLE) do try(d, get("gatherArrowProfFirst")) end
    if not best and get("gatherArrowProfFirst") then for _, d in ipairs(SAMPLE) do try(d, false) end end
    return best
end

local function buildPreview(p)
    local pv = CreateFrame("Frame", nil, p)
    pv:SetSize(250, 300)
    pv:SetPoint("TOPLEFT", 0, -44)
    local map = CreateFrame("Frame", nil, pv)
    map:SetSize(200, 200)
    map:SetPoint("TOP", 0, -26)
    -- 0.6.605: Blizzard look - ground in the minimap's terrain colors (the world map art is parchment, the
    -- minimap is not), border and zone plate copied 1:1 from the real minimap (texture, cut-out, size, offset),
    -- so it also fits a minimap restyled by a UI addon
    map.bg = map:CreateTexture(nil, "BACKGROUND")
    map.bg:SetAllPoints()
    map.bg:SetColorTexture(1, 1, 1, 1)
    if map.bg.SetGradient and CreateColor then
        pcall(map.bg.SetGradient, map.bg, "VERTICAL", CreateColor(0.17, 0.22, 0.12, 1), CreateColor(0.27, 0.33, 0.18, 1))
    else
        map.bg:SetColorTexture(0.22, 0.28, 0.15, 1)
    end
    -- a little terrain: two soft patches (meadow / path)
    map.p1 = map:CreateTexture(nil, "BACKGROUND", nil, 1)
    map.p1:SetTexture(ns.MEDIA .. "dot") map.p1:SetVertexColor(0.36, 0.42, 0.22, 0.6)
    map.p1:SetSize(120, 90) map.p1:SetPoint("CENTER", -30, 25)
    map.p2 = map:CreateTexture(nil, "BACKGROUND", nil, 1)
    map.p2:SetTexture(ns.MEDIA .. "dot") map.p2:SetVertexColor(0.45, 0.38, 0.24, 0.55)
    map.p2:SetSize(150, 26) map.p2:SetPoint("CENTER", 20, -20) map.p2:SetRotation(0.5)
    if map.CreateMaskTexture and map.bg.AddMaskTexture then
        pcall(function()
            local m = map:CreateMaskTexture()
            m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(map)
            map.bg:AddMaskTexture(m) map.p1:AddMaskTexture(m) map.p2:AddMaskTexture(m)
        end)
    end
    local rimF = CreateFrame("Frame", nil, map)
    rimF:SetAllPoints()
    rimF:SetFrameLevel(map:GetFrameLevel() + 8)
    -- copy a texture of the real minimap into the preview (same place relative to the minimap, scaled)
    local function mirror(src)
        if not (src and src.GetTexture and Minimap and Minimap.GetCenter) then return nil end
        local mx, my = Minimap:GetCenter()
        local sx, sy = src:GetCenter()
        local mw = Minimap:GetWidth()
        if not (mx and sx and mw and mw > 0) then return nil end
        local t = rimF:CreateTexture(nil, "OVERLAY")
        local atlas = src.GetAtlas and src:GetAtlas()
        if atlas then t:SetAtlas(atlas) else
            local file = src:GetTexture()
            if not file then return nil end
            t:SetTexture(file)
            t:SetTexCoord(src:GetTexCoord())
        end
        local me, se = Minimap:GetEffectiveScale(), src:GetEffectiveScale()
        local k = 200 / mw
        local w, h = src:GetSize()
        t:SetSize(w * se / me * k, h * se / me * k)
        t:SetPoint("CENTER", map, "CENTER", (sx * se - mx * me) / me * k, (sy * se - my * me) / me * k)
        local r, g, b, a = src:GetVertexColor()
        if r then t:SetVertexColor(r, g, b, a) end
        return t
    end
    map.rim = mirror(_G.MinimapBorder or (MinimapCompassTexture))
    map.top = mirror(_G.MinimapBorderTop or (MinimapCluster and MinimapCluster.BorderTop))
    if not map.rim then
        -- no game border found: simple dark ring
        map.rim = rimF:CreateTexture(nil, "OVERLAY")
        map.rim:SetTexture(ns.MEDIA .. "pinring")
        map.rim:SetPoint("TOPLEFT", -5, 5) map.rim:SetPoint("BOTTOMRIGHT", 5, -5)
        map.rim:SetVertexColor(0.25, 0.22, 0.18, 1)
    end
    map.zone = rimF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if map.top then map.zone:SetPoint("CENTER", map.top, "CENTER", 0, 0) else map.zone:SetPoint("BOTTOM", map, "TOP", 0, 8) end
    local zoneText = _G.MinimapZoneText or (MinimapCluster and MinimapCluster.ZoneTextButton and MinimapCluster.ZoneTextButton.Text)
    map.zone:SetText((zoneText and zoneText.GetText and ns.safe(zoneText:GetText())) or (GetMinimapZoneText and GetMinimapZoneText()) or "")
    map.me = map:CreateTexture(nil, "OVERLAY")
    map.me:SetTexture("Interface\\Minimap\\MinimapArrow")
    map.me:SetSize(22, 22)
    map.me:SetPoint("CENTER")
    pv.map = map
    pv.dots, pv.syms = {}, {}
    for i, d in ipairs(SAMPLE) do
        local dot = map:CreateTexture(nil, "ARTWORK")
        -- the game's tracking icons (herb / ore), else a plain yellow dot
        local atlas = (d.kind == "herb" and "Professions_Tracking_Herb") or (d.kind == "ore" and "Professions_Tracking_Ore") or nil
        if not (atlas and dot.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and dot:SetAtlas(atlas) ~= false) then
            dot:SetTexture("Interface\\Minimap\\ObjectIcons")
            dot:SetTexCoord(0.25, 0.375, 0, 0.5)   -- yellow tracking dot
            dot.plain = true
        end
        dot:SetPoint("CENTER", map, "CENTER", d.x * 200 / 230, d.y * 200 / 230)
        pv.dots[i] = dot
        local s = ns.GatherSight and ns.GatherSight.NewSymbol(map)
        if s then
            s:SetPoint("CENTER", map, "CENTER", d.x * 200 / 230, d.y * 200 / 230)
            s:SetFrameLevel(map:GetFrameLevel() + 3)
            s.d = d
            pv.syms[i] = s
        end
    end
    -- arrow below the map (like the one on the screen)
    pv.arrow = pv:CreateTexture(nil, "ARTWORK")
    pv.arrow:SetSize(34, 34)
    pv.arrow:SetPoint("TOP", map, "BOTTOM", -60, -10)
    if not (pv.arrow.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("MiniMap-QuestArrow") and pv.arrow:SetAtlas("MiniMap-QuestArrow") ~= false) then
        pv.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    pv.arrowText = K.Text(pv, 11, C.text)
    pv.arrowText:SetPoint("LEFT", pv.arrow, "RIGHT", 8, 0)
    pv.note = K.Text(pv, 10, C.dim)
    pv.note:SetPoint("TOP", map, "BOTTOM", 0, -52)
    pv.note:SetText(L["Preview with sample nodes - changes show at once"])
    function pv:Update(tab)
        local dotScale = S().gatherDotScale or 1
        local symbols = get("gatherSymbols")
        for i, d in ipairs(SAMPLE) do
            local gray = d.cave
            self.dots[i]:SetSize(14 * dotScale, 14 * dotScale)
            if self.dots[i].SetDesaturated then self.dots[i]:SetDesaturated(gray and true or false) end
            self.dots[i]:SetVertexColor(gray and 0.7 or 1, gray and 0.7 or 1, gray and 0.7 or 1, 1)
            local s = self.syms[i]
            if s then
                if symbols then ns.GatherSight.StyleSymbol(s, d, d.x, d.y) s:Show() else s:Hide() end
            end
        end
        local t = previewTarget()
        local GS = ns.GatherSight
        if get("gatherArrow") and t then
            self.arrow:SetRotation(math.atan2 and math.atan2(-t.x, t.y) or math.atan(-t.x, t.y))
            self.arrow:Show()
            self.arrowText:SetText(("%s  |cffffd100%d m|r"):format(t.name, math.floor(math.sqrt(t.x * t.x + t.y * t.y) * 2)))
        else
            self.arrow:Hide()
            self.arrowText:SetText(get("gatherArrow") and "" or ("|cff888888" .. L["Arrow is off"] .. "|r"))
        end
        -- sparkles on the arrow's node (tab "Sparkles & pin")
        if GS and GS.SparkleOn then
            local host
            for i, d in ipairs(SAMPLE) do if d == t then host = self.syms[i] end end
            if tab == "sparkle" and get("gatherSparkle") and host and host:IsShown() then GS.SparkleOn(host, "preview", 0)
            else GS.SparkleOff("preview") end
        end
    end
    pv:SetScript("OnHide", function() if ns.GatherSight and ns.GatherSight.SparkleOff then ns.GatherSight.SparkleOff("preview") end end)
    return pv
end

local buildMapPreview
-- world map preview: a piece of a zone map, the right half "unexplored" in the chosen tint
buildMapPreview = function(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetSize(250, 300)
    f:SetPoint("TOPLEFT", 0, -44)
    local w, h = 240, 160
    f.map = f:CreateTexture(nil, "BACKGROUND")
    f.map:SetSize(w, h)
    f.map:SetPoint("TOP", 0, -26)
    f.map:SetTexture("Interface\\WorldMap\\Elwynn\\Elwynn6")
    f.dark = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.dark:SetSize(w / 2, h)
    f.dark:SetPoint("TOPRIGHT", f.map, "TOPRIGHT")
    f.dark:SetColorTexture(0, 0, 0, 1)
    f.unex = f:CreateTexture(nil, "ARTWORK")
    f.unex:SetSize(w / 2, h)
    f.unex:SetPoint("TOPRIGHT", f.map, "TOPRIGHT")
    f.unex:SetTexture("Interface\\WorldMap\\Elwynn\\Elwynn6")
    f.unex:SetTexCoord(0.5, 1, 0, 1)
    f.frame = f:CreateTexture(nil, "OVERLAY")
    f.frame:SetPoint("TOPLEFT", f.map, -3, 3) f.frame:SetPoint("BOTTOMRIGHT", f.map, 3, -3)
    f.frame:SetColorTexture(0, 0, 0, 0)
    f.l1 = K.Text(f, 10, C.dim) f.l1:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 4, -6) f.l1:SetText(L["explored"])
    f.l2 = K.Text(f, 10, C.dim) f.l2:SetPoint("TOPRIGHT", f.map, "BOTTOMRIGHT", -4, -6) f.l2:SetText(L["unexplored (revealed)"])
    f.note = K.Text(f, 10, C.dim)
    f.note:SetPoint("TOP", f.map, "BOTTOM", 0, -30)
    f.note:SetText(L["Preview - changes show at once"])
    function f:Update()
        local reveal = S().mapReveal
        local r, g, b, a = 1, 1, 1, 1
        if ns.WorldMapPlus then r, g, b, a = ns.WorldMapPlus.Tint() end
        self.unex:SetShown(reveal and true or false)
        self.unex:SetVertexColor(r, g, b)
        self.unex:SetAlpha(a)
        self.l2:SetText(reveal and L["unexplored (revealed)"] or L["unexplored (hidden)"])
    end
    f:Update()
    return f
end

------------------------------------------------------------------------
-- page
------------------------------------------------------------------------
local cur = "mini"
local function apply(p)
    if ns.GatherSight then pcall(ns.GatherSight.Apply) end
    if ns.WorldMapPlus then pcall(ns.WorldMapPlus.Apply) end
    if ns.ComfortPlus and ns.ComfortPlus.ApplyReveal then pcall(ns.ComfortPlus.ApplyReveal) end
    if p.pv then p.pv:Update(cur) end
    if p.mpv then p.mpv:Update() end
end
local function buildControls(p, key)
    local box = CreateFrame("Frame", nil, p)
    box:SetPoint("TOPLEFT", 280, -44)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    local o = OPTS[key]
    local y = 0
    box.ctrls = {}
    for _, row in ipairs(o) do
        local t = K.Toggle(box, L[row[1]], function() return get(row[2]) end, function(v) set(row[2], v) apply(p) end)
        t:SetPoint("TOPLEFT", 0, y)
        box.ctrls[#box.ctrls + 1] = t
        y = y - 30
    end
    local sliders = o.slider or {}
    local two = #sliders > 2
    for i, sd in ipairs(sliders) do
        local col = two and ((i - 1) % 2) or 0
        if col == 0 then y = y - 6 end
        local x = col * 250
        local lab = K.Text(box, 11, C.muted)
        lab:SetPoint("TOPLEFT", x, y)
        lab:SetText(L[sd[1]])
        local sl = K.Slider(box, two and 220 or 260, sd[3], sd[4], sd[5], function() return S()[sd[2]] or sd[6] end,
            function(v) S()[sd[2]] = (v ~= sd[6]) and v or nil apply(p) end, sd[7] or function(v) return math.floor(v * 100 + 0.5) .. " %" end)
        sl:SetPoint("TOPLEFT", x, y - 18)
        box.ctrls[#box.ctrls + 1] = sl
        if not two or col == 1 or i == #sliders then y = y - 54 end
    end
    if o.resetPos and ns.WorldMapPlus then
        local rb = K.Button(box, L["Reset map position"], 200, 26, nil, function() ns.WorldMapPlus.ResetPosition() end)
        rb:SetPoint("TOPLEFT", 0, y - 4)
        y = y - 36
    end
    if o.colors and ns.GatherSight then
        y = y - 4
        local lab = K.Text(box, 11, C.muted)
        lab:SetPoint("TOPLEFT", 0, y)
        lab:SetText(L["Sparkle color"])
        local x = 0
        for _, name in ipairs({ "gold", "white", "green", "blue", "purple", "red" }) do
            local c = ns.GatherSight.COLORS[name]
            local b = CreateFrame("Button", nil, box)
            b:SetSize(26, 26)
            b:SetPoint("TOPLEFT", x, y - 18)
            b.t = b:CreateTexture(nil, "ARTWORK")
            b.t:SetAllPoints()
            b.t:SetTexture(ns.MEDIA .. "dot")
            b.t:SetVertexColor(c[1], c[2], c[3])
            b:SetScript("OnClick", function() S().gatherSparkleColor = name apply(p) end)
            x = x + 34
        end
        y = y - 54
    end
    if o.buttons and ns.GatherGuild then
        y = y - 4
        local watch
        watch = K.Button(box, L["Guild finds: notify me for"], 230, 26, nil, function() ns.GatherGuild.WatchMenu(watch) end)
        watch:SetPoint("TOPLEFT", 0, y)
        local stats = K.Button(box, L["Farm statistics"], 180, 26, nil, function() ns.GatherGuild.ShowPanel() end)
        stats:SetPoint("TOPLEFT", 240, y)
    end
    function box:Refresh() for _, c in ipairs(self.ctrls) do if c.Refresh then pcall(c.Refresh, c) end end end
    return box
end
local function show(p, key)
    p.cur = key
    if p.tabs == GTABS then cur = key end
    for _, t in ipairs(p.tabs) do
        local f = p.views[t.key]
        if t.key == key then
            if not f then
                if t.tab then
                    f = CreateFrame("Frame", nil, p)
                    f:SetPoint("TOPLEFT", 0, -44) f:SetPoint("BOTTOMRIGHT", 0, 0)
                    ns.BuildSettingsTab(t.tab, f)
                else
                    f = buildControls(p, t.key)
                end
                p.views[t.key] = f
            end
            if t.tab then ns.RefreshSettingsTab(t.tab, f) elseif f.Refresh then f:Refresh() end
            f:Show()
        elseif f then f:Hide() end
    end
    local tdef
    for _, t in ipairs(p.tabs) do if t.key == key then tdef = t end end
    if p.pv then p.pv:SetShown(tdef and tdef.preview and true or false) end
    if tdef and tdef.mappreview and not p.mpv then p.mpv = buildMapPreview(p) end
    if p.mpv then p.mpv:SetShown(tdef and tdef.mappreview and true or false) end
    apply(p)
end

local function register(key, title, sub, order, tabs, withPreview)
    ns.RegisterPage({
        key = key, title = title, order = order, sub = sub,
        build = function(p)
            p.tabs = tabs
            local items = {}
            for _, t in ipairs(tabs) do items[#items + 1] = { key = t.key, text = L[t.text] } end
            p.seg = K.Segments(p, items, function(k) show(p, k) end)
            p.seg:SetPoint("TOPLEFT", 0, 0)
            p.views = {}
            p.ShowTab = function(k) show(p, k) end
            if withPreview then p.pv = buildPreview(p) end
            show(p, tabs[1].key)
        end,
        refresh = function(p) if p.views then show(p, p.cur or tabs[1].key) end end,
    })
end
register(GKEY, "Gathering & minimap", "Minimap, arrow, sparkles and gathering with the guild - with a live preview", 5.44, GTABS, true)
register(KEY, "Comfort settings", "Helpers and game chat", 5.45, CTABS, false)

-- Oasis: settings page of the Comfort add-on (0.6.602) - sidebar "Comfort > Settings"
-- Gathering (minimap, arrow, sparkles, guild) with a live preview minimap on sample data, plus the comfort
-- helpers and the game chat. These tabs leave the big settings window while this add-on is loaded.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
local L = ns.L
local K, C = ns.K, ns.K.C
if not (K and ns.RegisterPage) then return end

-- 0.6.606: four sidebar pages under "Comfort" - Gathering & minimap, World map, Everyday helpers, Game chat.
-- None of the Comfort settings stay in the big Oasis settings window while this add-on is loaded.
-- 0.6.610: seven sidebar pages under "Comfort" (gathering, world map, quests & vendor, interface, game chat,
-- helpers, upgrade exchange) instead of few big ones
local KEY, GKEY, WKEY, CHKEY, QKEY, UKEY = "comfortset", "gatherset", "worldmapset", "chatset", "questset", "uiset"
ns.GatherSettingsPage = GKEY
ns.ConvenienceOwnPages = true
ns.SETTINGS_ELSEWHERE = ns.SETTINGS_ELSEWHERE or {}
ns.SETTINGS_ELSEWHERE.comfort, ns.SETTINGS_ELSEWHERE.gamechat, ns.SETTINGS_ELSEWHERE.helpers = true, true, true
if ns.ICONS then
    ns.ICONS[KEY] = ns.ICONS.settings or ns.ICONS.home
    ns.ICONS[GKEY] = ns.ICONS.map or ns.ICONS.compass or ns.ICONS.settings or ns.ICONS.home
    ns.ICONS[WKEY] = ns.ICONS.map or ns.ICONS.compass or ns.ICONS.home
    ns.ICONS[CHKEY] = ns.ICONS.announce or ns.ICONS.chat or ns.ICONS.home
    ns.ICONS[QKEY] = ns.ICONS.checklist or ns.ICONS.quest or ns.ICONS.home
    ns.ICONS[UKEY] = ns.ICONS.brush or ns.ICONS.eye or ns.ICONS.home
end
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "convenience" then
        for i, k in ipairs({ GKEY, WKEY, QKEY, UKEY, CHKEY, KEY }) do
            local has = false
            for _, x in ipairs(g.pages) do if x == k then has = true end end
            if not has then table.insert(g.pages, i, k) end
        end
    end
end

local function S() return ns.db.settings end
-- toggles that are on until switched off (nil = on)
local ON = { mapDungeons = true, mapPoi = true, layerAsk = true, mapRevealTint = true, gatherScan = true, gatherSymbols = true, gatherArrowHerb = true, gatherArrowOre = true, gatherArrowTreasure = true,
    gatherArrowRare = true, gatherArrowLeyline = true, gatherAlerts = true, gatherAlertsShare = true, gatherWanted = true, gatherShareArea = true }
local function get(k) if ON[k] then return S()[k] ~= false end return S()[k] and true or false end
local function set(k, v) if ON[k] then S()[k] = v and true or false else S()[k] = v and true or nil end end

local GTABS = {
    { key = "mini", text = "Minimap", preview = true },
    { key = "arrow", text = "Arrow", preview = true },
    { key = "sparkle", text = "Sparkles & pin", preview = true },
    { key = "guild", text = "Guild", preview = true },
}
local WTABS = {
    { key = "worldmap", text = "World map", mappreview = true },
    { key = "mapextras", text = "Map extras" },
}
local CTABS = {
    { key = "comfort", text = "Helpers", tab = "comfort" },
    { key = "helpers", text = "Guild helpers", tab = "helpers" },
}
local QTABS = {
    { key = "quests", text = "Quests" },
    { key = "vendor", text = "Vendor & bags" },
}
local UTABS = {
    { key = "tooltips", text = "Mouse over players & NPCs" },
    { key = "minimapcam", text = "Minimap & camera" },
    { key = "sounds", text = "Sounds" },
}
local CHTABS = {
    { key = "gamechat", text = "Game chat", tab = "gamechat" },
    { key = "chatclean", text = "Tidy up" },
    { key = "whisper", text = "Whispers" },
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
            { "Gathering symbols: size", "gatherSymbolSize", 0.6, 1.8, 0.05, 1 },
            { "Game's yellow dots under the symbols: size", "gatherDotScale", 0.5, 1, 0.05, 1 },
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
        { "Group members in class colours", "wmGroupClass" },
        slider = {
            { "Tint: red", "wmTintR", 0, 1, 0.05, 0.55 },
            { "Tint: green", "wmTintG", 0, 1, 0.05, 0.55 },
            { "Tint: blue", "wmTintB", 0, 1, 0.05, 0.6 },
            { "Tint: opacity", "wmTintA", 0.1, 1, 0.05, 0.85 },
            { "World map size (window)", "wmScale", 0.5, 2, 0.05, 1 },
            { "World map size (maximised)", "wmScaleMax", 0.5, 2, 0.05, 1 },
            { "World map opacity (window)", "wmAlpha", 0.3, 1, 0.05, 1 },
            { "World map opacity (maximised)", "wmAlphaMax", 0.3, 1, 0.05, 1 },
            { "Group member icons: size", "wmGroupSize", 8, 40, 1, 16, function(v) return v .. " px" end },
        },
        resetPos = true,
    },
    mapextras = {
        { "Dungeon entrances", "mapDungeons" },
        { "Danger zones", "mapDanger" },
        { "Vendors, repair, mailboxes and flight points", "mapPoi" },
        { "Dungeon quest givers", "mapQuestGivers" },
        { "Own trail", "mapTrails" },
        { "Long trail: whole session", "trailSession" },
        { "Other players' trails", "mapTrailsGuild" },
        { "Coordinates on the minimap", "mmCoords" },
        { "Accept layer requests from the guild", "layerAsk" },
    },
    quests = {
        { "Quest levels in the quest log", "twQuestLevel" },
        { "Flight master: straight to the flight map", "twTaxi" },
        { "\"Train all\" at the trainer", "twTrainAll" },
        { "Battleground: release automatically", "twBgRelease" },
        { "Quest items always sparkle", "twLootSparkle" },
        { "Quest progress on enemy nameplates", "cfQuestPlates" },
        { "Key for the next quest enemy (game key bindings)", "cfQuestTarget" },
        slider = {
            { "Forever's own quests", "cfForeverQuests", 1, 3, 1, 3, function(v) return L[({ "Leave to me", "Turn in only", "Accept and turn in" })[v] or "Accept and turn in"] end },
            { "Quest reward", "cfRewardPick", 1, 3, 1, 1, function(v) return L[({ "Let me pick", "Best upgrade", "Highest price" })[v] or "Let me pick"] end },
        },
    },
    vendor = {
        { "Restock at vendors (your list)", "cfRestockOn" },
        { "Fill the quiver with the best ammo", "cfAmmo" },
        { "Alt+right-click marks items as junk", "twJunkMark" },
        { "Gear groups (Ctrl+right-click in the bags)", "twGear" },
        { "Confirm bind-on-pickup loot automatically", "cfLootConfirm" },
        { "Delete items without typing DELETE", "cfEasyDestroy" },
        { "Auction house: item level in the list", "twAhIlvl" },
        { "Bags full: offer to destroy the cheapest item", "cfDestroyCheap" },
        { "Open button for clams, sacks and boxes", "cfOpenButton" },
        restockButtons = true,
        gearButtons = true,
    },
    tooltips = {
        intro = "The small info box that appears when your mouse is over a player, NPC or enemy:",
        { "Player names in class colour", "twTipClass" },
        { "Health bar inside the box", "twTipBar" },
        { "Show guild and rank", "cfTipRank" },
        { "Show whom they are targeting", "cfTipTarget" },
        { "Hide in combat (hold Shift to see it)", "cfTipCombat" },
        { "Background in faction colour (blue Alliance, red Horde)", "cfTipFaction" },
    },
    minimapcam = {
        { "Square minimap", "cfSquareMap" },
        { "Addon buttons only on minimap mouse-over", "cfMapButtons" },
        { "Camera: zoom out further", "twCamera" },
        { "No screen glow", "twNoGlow" },
    },
    sounds = {
        { "Mute clock chimes", "cfMuteChimes" },
        { "Mute spell fizzle", "cfMuteFizzle" },
        { "Mute /train emotes", "cfMuteTrains" },
        { "Mute cat yawns", "cfMuteYawns" },
    },
    chatclean = {
        { "Hide the combat log tab", "cfNoCombatTab" },
        { "Hide chat buttons", "cfNoChatButtons" },
        { "Filter duel and drunk spam", "cfSpamFilter" },
        slider = {
            { "Chat font size", "cfChatFont", 10, 20, 1, 14, function(v) return v .. " pt" end },
        },
    },
    whisper = {
        { "Offer whispers to offline characters to their alt", "whisperForward" },
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
    -- 0.6.615: a real piece of WoW - the map art of the zone you are in, around your position
    map.art = map:CreateTexture(nil, "BACKGROUND", nil, 2)
    map.art:SetAllPoints()
    pcall(function()
        local mid = C_Map.GetBestMapForUnit("player")
        local pos = mid and C_Map.GetPlayerMapPosition(mid, "player")
        local layers = mid and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mid)
        local texs = mid and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mid, 1)
        local lay = layers and layers[1]
        if not (pos and lay and texs and #texs > 0) then return end
        local px, py = pos:GetXY()
        local tw, th = lay.tileWidth or 256, lay.tileHeight or 256
        local cols = math.ceil((lay.layerWidth or 1002) / tw)
        local ax, ay = px * (lay.layerWidth or 1002), py * (lay.layerHeight or 668)
        local col, row = math.floor(ax / tw), math.floor(ay / th)
        local id = texs[row * cols + col + 1]
        if not id then return end
        map.art:SetTexture(id)
        -- the part of the tile around you (a third of it, like the minimap's view)
        local fx, fy = (ax - col * tw) / tw, (ay - row * th) / th
        local r = 0.33
        local l, t = math.max(0, math.min(1 - 2 * r, fx - r)), math.max(0, math.min(1 - 2 * r, fy - r))
        map.art:SetTexCoord(l, l + 2 * r, t, t + 2 * r)
        map.realArt = true
    end)
    if not map.realArt then map.art:Hide() end
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
            map.bg:AddMaskTexture(m) map.p1:AddMaskTexture(m) map.p2:AddMaskTexture(m) map.art:AddMaskTexture(m)
        end)
    end
    local rimF = CreateFrame("Frame", nil, map)
    rimF:SetAllPoints()
    rimF:SetFrameLevel(map:GetFrameLevel() + 8)
    -- copy a texture of the real minimap into the preview (same place relative to the minimap, scaled)
    local function mirror(src)
        if not (src and src.GetTexture and Minimap and Minimap.GetCenter) then return nil end
        if src.IsVisible and not src:IsVisible() then return nil end   -- hidden (other UI): try the next one
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
    map.rim = mirror(_G.MinimapBorder) or mirror(_G.MinimapCompassTexture)
    map.top = mirror(_G.MinimapBorderTop) or mirror(MinimapCluster and MinimapCluster.BorderTop)
    -- not found on the minimap: Blizzard's own minimap frame art
    if not map.rim and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ui-hud-minimap-frame") then
        map.rim = rimF:CreateTexture(nil, "OVERLAY")
        map.rim:SetAtlas("ui-hud-minimap-frame")
        map.rim:SetPoint("TOPLEFT", -14, 14) map.rim:SetPoint("BOTTOMRIGHT", 14, -14)
    end
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
    -- 0.6.612: everything a switch does is visible here
    local over = CreateFrame("Frame", nil, map)
    over:SetAllPoints() over:SetFrameLevel(map:GetFrameLevel() + 12)
    pv.over = over
    -- scan: a sweeping line
    pv.sweep = over:CreateTexture(nil, "OVERLAY")
    pv.sweep:SetColorTexture(1, 1, 0.6, 0.35)
    pv.sweep:SetSize(2, 96) pv.sweep:SetPoint("BOTTOM", map, "CENTER", 0, 0)
    pv.sweepA = 0
    over:SetScript("OnUpdate", function(_, el)
        if not pv.sweep:IsShown() then return end
        pv.sweepA = (pv.sweepA + (el or 0) * 2) % 6.283
        pv.sweep:SetRotation(pv.sweepA)
        pv.sweep:ClearAllPoints()
        pv.sweep:SetPoint("CENTER", map, "CENTER", -math.sin(pv.sweepA) * 48, math.cos(pv.sweepA) * 48)
        pv.flip = (pv.flip or 0) + (el or 0)
        if pv.flip > 2 and pv.switching then pv.flip = 0 pv.herbs = not pv.herbs pv:Update(pv.tab) end
    end)
    -- finder line, skill tooltip, dot legend
    pv.finder = K.Text(pv, 10, C.muted) pv.finder:SetPoint("TOP", map, "BOTTOM", 0, -50)
    pv.tip = CreateFrame("Frame", nil, over)
    pv.tip:SetSize(196, 58) pv.tip:SetPoint("BOTTOMLEFT", map, "CENTER", -92, 0)
    K.Fill(pv.tip, { 0.03, 0.03, 0.05, 0.92 }) K.Border(pv.tip, C.line)
    pv.tip.a = K.Text(pv.tip, 10, C.text) pv.tip.a:SetPoint("TOPLEFT", 6, -4) pv.tip.a:SetText("Kingsblood")
    pv.tip.b = K.Text(pv.tip, 9, { 1, 0.5, 0.25 }) pv.tip.b:SetPoint("TOPLEFT", 6, -18) pv.tip.b:SetText((ITEM_MIN_SKILL or "Requires %s (%d)"):format(L["Herbalism"], 125))
    pv.tip.c = K.Text(pv.tip, 8, C.dim) pv.tip.c:SetPoint("TOPLEFT", 6, -31) pv.tip.c:SetWidth(184) pv.tip.c:SetJustifyH("LEFT") pv.tip.c:SetWordWrap(true)
    pv.tip.c:SetText(L["Oasis adds this line: skill needed. Red = too low, orange/yellow/green = chance of a skill-up"])
    pv.legend = map:CreateTexture(nil, "OVERLAY")
    pv.legend:SetPoint("CENTER", map, "TOPRIGHT", 4, 2)
    pv.legendT = K.Text(pv, 10, C.muted) pv.legendT:SetPoint("BOTTOM", pv.legend, "TOP", 0, 2) pv.legendT:SetText(L["game dot"])
    -- arrow lock, pin, interact icon, far sparkle spots
    pv.lock = pv:CreateTexture(nil, "OVERLAY") pv.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon") pv.lock:SetSize(14, 14)
    pv.lock:SetPoint("BOTTOMRIGHT", pv.arrow, "BOTTOMRIGHT", 4, -2)
    pv.pin = over:CreateTexture(nil, "OVERLAY") pv.pin:SetTexture("Interface\\Minimap\\Waypoint-MapPin-Untracked") pv.pin:SetSize(20, 20)
    if pv.pin.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Waypoint-MapPin-Tracked") then pv.pin:SetAtlas("Waypoint-MapPin-Tracked") end
    pv.hand = over:CreateTexture(nil, "OVERLAY") pv.hand:SetTexture("Interface\\Cursor\\UnableGatherHerbs") pv.hand:SetSize(16, 16)
    if pv.hand.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Cursor_Herb_32") then pv.hand:SetAtlas("Cursor_Herb_32") end
    -- guild: a farming guild member, a notice, route lines
    pv.mate = over:CreateTexture(nil, "OVERLAY") pv.mate:SetTexture(ns.MEDIA .. "dot") pv.mate:SetVertexColor(0.3, 1, 0.4) pv.mate:SetSize(12, 12)
    pv.mate:SetPoint("CENTER", map, "CENTER", 60, -60)
    pv.toast = K.Text(pv, 10, { 1, 0.82, 0 }) pv.toast:SetPoint("BOTTOM", map, "TOP", 0, 22)
    pv.lines = {}
    pv.note = K.Text(pv, 10, C.dim)
    pv.note:SetPoint("TOP", map, "BOTTOM", 0, -68)
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
        self.tab = tab
        local k = 200 / 230
        -- minimap tab: scan sweep, finder switch, skill line, dot legend
        self.sweep:SetShown(tab == "mini" and get("gatherScan"))
        self.switching = tab == "mini" and get("gatherSwitch")
        if self.switching then
            self.finder:SetText(self.herbs and ("|cff7fd77f" .. L["Find Herbs"] .. "|r  ⇄  " .. L["Find Minerals"]) or (L["Find Herbs"] .. "  ⇄  |cffd8b04a" .. L["Find Minerals"] .. "|r"))
            for i, d in ipairs(SAMPLE) do
                local held = (self.herbs and d.kind == "ore") or (not self.herbs and d.kind == "herb")
                if self.syms[i] and self.syms[i]:IsShown() and held then self.syms[i]:SetAlpha(0.45) end
            end
        else
            self.finder:SetText(tab == "mini" and (get("gatherSound") and L["A soft ping for new nodes"] or "") or "")
        end
        self.tip:Hide()
        self.finder:SetText(self.switching and self.finder:GetText() or (tab == "mini" and not get("gatherSkillOff") and L["Hover a symbol: shows the skill you need"] or self.finder:GetText()))
        local ds = 24 * (S().gatherDotScale or 1)
        if self.legend.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Professions_Tracking_Herb") then self.legend:SetAtlas("Professions_Tracking_Herb")
        else self.legend:SetTexture(ns.MEDIA .. "dot") self.legend:SetVertexColor(1, 0.85, 0.2) end
        self.legend:SetSize(ds, ds)
        self.legend:SetShown(tab == "mini") self.legendT:SetShown(tab == "mini")
        -- arrow tab: lock
        self.lock:SetShown(get("gatherArrow") and get("gatherArrowLock") and true or false)
        -- sparkle tab: pin and the game's interact icon on the target
        self.pin:Hide() self.hand:Hide()
        if t and tab == "sparkle" then
            if get("gatherPin") or get("gatherSparkleFar") then self.pin:ClearAllPoints() self.pin:SetPoint("BOTTOM", self.map, "CENTER", t.x * k, t.y * k + 8) self.pin:Show() end
            if get("gatherSparkle") and not get("gatherSparkleHideIcons") then self.hand:ClearAllPoints() self.hand:SetPoint("BOTTOM", self.map, "CENTER", t.x * k, t.y * k + 22) self.hand:Show() end
        end
        -- guild tab: farmer, notice, route
        local guild = tab == "guild"
        self.mate:SetShown(guild and get("gatherShareArea"))
        if guild and get("gatherShareArea") then
            for i, d in ipairs(SAMPLE) do
                if self.syms[i] and self.syms[i]:IsShown() and d.x > 30 and d.y < -20 then self.syms[i]:SetAlpha(0.3) end
            end
        end
        self.toast:SetText(guild and get("gatherAlerts") and ("|TInterface\\Icons\\INV_Misc_Herb_BlackLotus:14|t " .. L["Guild find: Black Lotus - Toran sees it"]) or "")
        for _, l in ipairs(self.lines) do l:Hide() end
        if guild and get("gatherRoute") and self.map.CreateLine then
            local pts = {}
            for _, d in ipairs(SAMPLE) do
                local skip = d.kind ~= "herb" and d.kind ~= "ore" or (get("gatherRouteSkill") and (d.hard or d.name == "Peacebloom" or d.name == "Copper Vein"))
                if not skip then pts[#pts + 1] = d end
            end
            for i = 1, #pts do
                local a, b = pts[i], pts[i % #pts + 1]
                local l = self.lines[i]
                if not l then
                    l = self.over:CreateLine(nil, "ARTWORK")
                    if l then l:SetThickness(2) l:SetColorTexture(1, 0.85, 0.3, 0.7) self.lines[i] = l end
                end
                if l then
                    l:SetStartPoint("CENTER", self.map, a.x * k, a.y * k)
                    l:SetEndPoint("CENTER", self.map, b.x * k, b.y * k)
                    l:Show()
                end
            end
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
    if ns.ComfortTweaks then pcall(ns.ComfortTweaks.Apply) end
    if ns.ComfortMore then pcall(ns.ComfortMore.Apply) end
    if ns.ComfortQuestBags then pcall(ns.ComfortQuestBags.Apply) end
    if ns.Map then pcall(ns.Map.UpdateWorldPins) pcall(ns.Map.UpdateMinimap) end
    if ns.ComfortPlus and ns.ComfortPlus.ApplyAll then pcall(ns.ComfortPlus.ApplyAll) end
    S().trailMinutes = S().trailSession and 0 or nil
    if ns.WorldMapPlus then pcall(ns.WorldMapPlus.Apply) end
    if ns.ComfortPlus and ns.ComfortPlus.ApplyReveal then pcall(ns.ComfortPlus.ApplyReveal) end
    if p.pv then p.pv:Update(cur) end
    if p.mpv then p.mpv:Update() end
    local PV = ns.ComfortPreviews
    local g = p.gen and p.gen[p.cur]
    if g and PV and PV[p.cur] then pcall(PV[p.cur].update, g) end
end
local function buildControls(p, key, withPreview)
    local box = CreateFrame("Frame", nil, p)
    box:SetPoint("TOPLEFT", withPreview and 280 or 0, -44)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    local o = OPTS[key]
    local y = 0
    box.ctrls = {}
    -- 0.6.622: one sentence above the switches when the tab name alone does not say it
    if o.intro then
        local it = K.Text(box, 11, C.muted)
        it:SetPoint("TOPLEFT", 0, 0) it:SetPoint("RIGHT", box, "RIGHT", -10, 0)
        it:SetJustifyH("LEFT") it:SetWordWrap(true)
        it:SetText(L[o.intro])
        y = -26
    end
    -- without a preview and with many switches: two columns
    local twoCol = not withPreview and #o > 7
    local half = math.ceil(#o / 2)
    for i, row in ipairs(o) do
        local t = K.Toggle(box, L[row[1]], function() return get(row[2]) end, function(v)
            set(row[2], v) apply(p)
            if v and row[2] == "gatherSound" and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "Master") end
        end)
        if twoCol then
            local col = i > half and 1 or 0
            t:SetPoint("TOPLEFT", col * 400, -((col == 1 and i - half or i) - 1) * 30)
            if t.SetWidth then t:SetWidth(380) end
        else
            t:SetPoint("TOPLEFT", 0, y)
        end
        box.ctrls[#box.ctrls + 1] = t
        if not twoCol then y = y - 30 end
    end
    if twoCol then y = -half * 30 end
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
            function(v)
                S()[sd[2]] = (v ~= sd[6]) and v or nil
                apply(p)
            end, sd[7] or function(v) return math.floor(v * 100 + 0.5) .. " %" end)
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
    if o.restockButtons and ns.ComfortMore then
        y = y - 4
        local rb
        rb = K.Button(box, L["Restock list"], 200, 26, nil, function() ns.ComfortMore.RestockMenu(rb) end)
        rb:SetPoint("TOPLEFT", 0, y)
        local hint = K.Text(box, 10, C.dim)
        hint:SetPoint("TOPLEFT", 0, y - 32)
        hint:SetText(L["Add: /oa restock [item link] [count]"])
        y = y - 54
    end
    if o.gearButtons and ns.ComfortTweaks then
        y = y - 10
        local lab = K.Text(box, 11, C.muted)
        lab:SetPoint("TOPLEFT", 0, y)
        lab:SetText(L["Equip gear group"])
        local x = 0
        for _, g in ipairs(ns.ComfortTweaks.GROUPS) do
            local b = K.Button(box, K.hex(g.color) .. g.text .. "|r", 90, 26, nil, function()
                ns.print((L["Equipped %d items of %s."]):format(ns.ComfortTweaks.EquipGroup(g.key), g.text))
            end)
            b:SetPoint("TOPLEFT", x, y - 18)
            x = x + 98
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
                    local PV = ns.ComfortPreviews
                    f = buildControls(p, t.key, t.preview or t.mappreview or (PV and PV[t.key]))
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
    -- 0.6.612: own preview for every other tab with switches (ComfortPreviews.lua)
    local PV = ns.ComfortPreviews
    p.gen = p.gen or {}
    if PV and PV[key] and not p.gen[key] then
        local g = CreateFrame("Frame", nil, p)
        g:SetSize(260, 300)
        g:SetPoint("TOPLEFT", 0, -44)
        local ok, err = pcall(PV[key].build, g)
        if not ok and ns.err then ns.err("preview " .. key, err) end
        p.gen[key] = g
    end
    for k2, g in pairs(p.gen) do g:SetShown(k2 == key) end
    if p.mpv then p.mpv:SetShown(tdef and tdef.mappreview and true or false) end
    apply(p)
end

local MODULE_OF = { gatherset = "Oasis_MapExtras", worldmapset = "Oasis_MapExtras", questset = "Oasis_Comfort", uiset = "Oasis_Comfort",
    comfortset = "Oasis_Comfort", chatset = "Oasis_GameChat" }
local function register(key, title, sub, order, tabs, withPreview)
    ns.RegisterPage({
        key = key, title = title, order = order, sub = sub, module = MODULE_OF[key],
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
register(GKEY, "Gathering & minimap", "Minimap, arrow, sparkles and gathering with the guild - with a live preview", 5.441, GTABS, true)
register(WKEY, "World map", "Reveal, tint, size and position of the world map, map extras", 5.442, WTABS, false)
register(QKEY, "Quests & vendor", "Quest automation, rewards, restock, junk, gear groups", 5.443, QTABS, false)
register(UKEY, "Interface", "Tooltips, minimap, camera and sounds", 5.444, UTABS, false)
register(CHKEY, "Game chat", "Game chat, tidy up and whispers", 5.445, CHTABS, false)
register(KEY, "Everyday helpers", "Repair, junk, quests and more - and the guild helpers", 5.446, CTABS, false)

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
local ON = { gcLiveSelect = true, gcAltSelect = true, mapDungeons = true, mapPoi = true, layerAsk = true, mapRevealTint = true, gatherScan = true, gatherSymbols = true, gatherArrowHerb = true, gatherArrowOre = true, gatherArrowTreasure = true,
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
-- 0.6.653: the old helper tabs rebuilt in tiles; their switches sorted to where they belong
local CTABS = {
    { key = "road", text = "On the road" },
    { key = "groupguild", text = "Group & guild" },
}
local QTABS = {
    { key = "quests", text = "Quests" },
    { key = "vendor", text = "Vendor & bags" },
}
local UTABS = {
    { key = "tooltips", text = "Mouse over players & NPCs" },
    { key = "itemtips", text = "Item tooltips" },
    { key = "bars", text = "Bars & window" },
    { key = "minimapcam", text = "Minimap & camera" },
    { key = "sounds", text = "Sounds" },
}
-- 0.6.652: game chat rebuilt in tiles, sorted by topic (was one long old settings page)
local CHTABS = {
    { key = "chatmain", text = "Game chat" },
    { key = "chatnames", text = "Names & icons" },
    { key = "chatfilter", text = "Filters" },
    { key = "chathist", text = "History & alerts" },
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
            { "Sparkle size", "gatherSparklePct", 0, 100, 5, 50, function(v) return v .. " %" end },   -- 0.6.646: 0-100, 50 = normal
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
        { "Accept and turn in quests automatically", "cfQuests" },
        { "Accept summons and resurrections", "cfSummon" },
        { "Decline quests shared by others", "cfBlockShared" },
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
        { "Sell grey items automatically", "cfSellJunk" },
        { "Repair automatically", "cfRepair" },
        { "Repair from guild bank (if allowed)", "cfRepairGuild" },
        { "Restock reagents and ammo", "cpReagBuy" },
        { "Restock at vendors (your list)", "cfRestockOn" },
        { "Better ammo at the vendor: fill the quiver", "cfAmmo" },
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
        { "Hide the chat menu button", "gcHideMenu" },
        { "Hide the channel button", "gcHideChannel" },
        { "Hide the social button", "gcHideSocial" },
        { "Hide the scroll buttons", "gcHideScroll" },
        { "Filter duel and drunk spam", "cfSpamFilter" },
        slider = {
            { "Chat font size", "cfChatFont", 10, 20, 1, 14, function(v) return v .. " pt" end },
        },
    },
    chatmain = {
        intro = "Oasis changes nothing in Blizzard's chat itself - it adjusts the lines afterwards.",
        { "Improve Blizzard's chat windows", "gcOn" },
        { "Chat: copy links, class colours", "cpChatLinks" },
        { "No emoji suggestions while typing", "emojiNoComplete" },
        { "Also public channels, say and yell", "gcAllChannels" },
        { "Select text by dragging", "gcLiveSelect" },
        { "Alt + click opens the selection box", "gcAltSelect" },
        { "Arrow keys in chat without Alt", "cfChatArrows" },
        { "Don't fade chat", "cfChatNoFade" },
        { "Keep chat after /reload", "cfChatRestore" },
        { "Edit box above the chat window", "cfChatTop" },
        extra = "stamp",
    },
    chatnames = {
        { "Shorten names", "gcShort" },
        { "Level before the name", "gcLevel" },
        { "Class icon before the name", "gcClassIcon" },
        { "Race icon before the name", "gcRaceIcon" },
        { "Icons on item and spell links", "gcLinkIcons" },
        { "Resolve shortcuts in text", "gcTokens" },
        { "Shorten channel names", "gcChNum" },
        { "Quiet text", "gcQuiet" },
        { "Item tooltip on hover", "gcHover" },
    },
    chatfilter = {
        { "Enable filters", "gcFilter" },
        { "Whole words only", "gcWhole" },
        { "Hide Cyrillic text", "gcCyr" },
        { "Hide Chinese characters", "gcHan" },
        { "Hide repeated messages", "gcRepeat" },
        slider = {
            { "Time window for repeats", "gcRepeatSec", 5, 600, 5, 60, function(v) return v .. " s" end },
        },
        extra = "filterLists",
    },
    chathist = {
        { "Keep chat history between sessions", "gcHist" },
        { "Notify me about keywords", "gcAlert" },
        { "Sound on alert", "gcAlertSound" },
        slider = {
            { "Lines per tab", "gcHistLines", 20, 300, 10, 100, function(v) return tostring(v) end },
        },
        extra = "histAlerts",
    },
    road = {
        { "XP per hour and time to level", "cpXP" },
        { "Tell the guild about upcoming level milestones", "cpXPShare" },
        { "Show flight time", "cpFlight" },
        { "Re-enable tracking after death", "cpTracking" },
        { "Instance counter (5 per hour)", "cpInstances" },
        { "New spells at the trainer", "cpTrainer" },
        { "Ammo, reagents and soul shards", "cpReagents" },
        { "Hunter: pet happiness and food", "cpPet" },
        { "Mail: \"Open all\" button", "cpMail" },
        { "Faster looting (with auto loot)", "cfFastLoot" },
        { "Show durability and warn", "cfDurability" },
        { "Fishing helper", "cpFishing" },
        extra = "overview",
    },
    groupguild = {
        { "Decline duels", "cfBlockDuels" },
        { "Invites only from guild and friends", "cfInvites" },
        { "Invite by whisper (guild/friends only)", "cfWhisperInv" },
        { "Group quest progress", "cpQuestShare" },
        { "Share profession cooldowns with the guild", "cpProfCD" },
        { "Rare alert", "cpRare" },
        { "Report rares to the guild", "cpRareShare" },
        extra = "invKeyword",
    },
    itemtips = {
        { "Tooltip: vendor price, item level and ID", "cpTooltip" },
        { "Tooltip: disenchants into ...", "cpDisenchant" },
        { "Tooltip: guild info", "cpTooltipGuild" },
        { "Item level when inspecting", "cpInspect" },
        { "No upgrade arrow in the tooltip", "upgradeTipOff" },
        { "No upgrade arrows on items", "upgradeIconOff" },
        { "No alt inventory in the tooltip", "invTooltipOff" },
    },
    bars = {
        { "Hide menu bar", "cfHideMicro" },
        { "Hide bag bar", "cfHideBags" },
        { "Show on mouseover", "cfBarsHover" },
        { "Hide red error messages", "cfHideErrors" },
        { "Range on action bars", "cpRange" },
    },
    whisper = {
        { "Offer whispers to offline characters to their alt", "whisperForward" },
    },
    guild = {
        { "Guild finds: notices", "gatherAlerts" },
        { "Guild finds: share mine", "gatherAlertsShare" },
        { "Wishlist nodes first", "gatherWanted" },
        { "Leave nearby guild farmers their side", "gatherShareArea" },
        { "Gathering route", "gatherRoute" },
        { "Skill-up route", "gatherRouteSkill" },
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
    { name = "Iron Deposit", kind = "ore", x = 69, y = -41 },
    { name = "Kingsblood", kind = "herb", x = -75, y = -28, wanted = true },
    { name = "Liferoot", kind = "herb", x = 22, y = 77, cave = true },
    { name = "Battered Chest", kind = "treasure", x = 68, y = 41 },
    { name = "Silverleaf", kind = "herb", x = -38, y = 70, held = true },
    { name = "Icecap", kind = "herb", x = 5, y = -80, hard = true },
    { name = "Leyline", kind = "leyline", x = -74, y = 31 },
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
        local dx, dy = (sx * se - mx * me) / me * k, (sy * se - my * me) / me * k
        -- 0.6.623: a ring sits centred on the map - its measured offset only counts for the zone plate above it
        if math.abs(dx) < 30 and math.abs(dy) < 30 then
            local size = math.max(w, h) * se / me * k
            if size < 206 or size > 240 then size = 218 end   -- odd measurement: Blizzard's ring is about 9 % larger than the map
            t:SetSize(size, size)
            t:SetPoint("CENTER", map, "CENTER", 0, 0)
        else
            t:SetSize(w * se / me * k, h * se / me * k)
            t:SetPoint("CENTER", map, "CENTER", dx, dy)
        end
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
            self.finder:SetText(self.herbs and ("|cff7fd77f" .. L["Find Herbs"] .. "|r  /  " .. L["Find Minerals"]) or (L["Find Herbs"] .. "  /  |cffd8b04a" .. L["Find Minerals"] .. "|r"))
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
        self.legend:Hide() self.legendT:Hide()   -- 0.6.645: the lone sample dot only confused
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

-- 0.6.630: settings tabs (game chat, helpers, guild helpers) - before they sat in a plain frame and ran out of the
-- window at the bottom. Now: scroll area like the settings page, with a live example on top (ComfortPreviews "tab_<key>").
local function buildTabPage(p, tabKey)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -44) f:SetPoint("BOTTOMRIGHT", 0, 0)
    local sc = CreateFrame("ScrollFrame", nil, f)
    sc:SetPoint("TOPLEFT") sc:SetPoint("BOTTOMRIGHT")
    local child = CreateFrame("Frame", nil, sc)
    child:SetSize(740, 400)
    sc:SetScrollChild(child)
    sc.thumb = sc:CreateTexture(nil, "OVERLAY")
    sc.thumb:SetWidth(3)
    sc.thumb:SetColorTexture(1, 1, 1, 0.18)
    sc.thumb:Hide()
    local PV = ns.ComfortPreviews and ns.ComfortPreviews["tab_" .. tabKey]
    local top, pv = 0, nil
    if PV then
        -- 0.6.637: the example stays fixed on top, only the settings below scroll
        pv = CreateFrame("Frame", nil, f)
        pv:SetPoint("TOPLEFT", 0, 0)
        pv:SetSize(738, PV.h or 130)
        local ok, err = pcall(PV.build, pv)
        if not ok and ns.err then ns.err("preview " .. tabKey, err) end
        sc:SetPoint("TOPLEFT", 0, -((PV.h or 130) + 14))
        sc:SetClipsChildren(true)
        -- switches in these tabs do not report back - keep the example current while it is visible
        local acc = 0
        pv:SetScript("OnUpdate", function(self, el)
            acc = acc + el
            if acc < 0.25 then return end
            acc = 0
            pcall(PV.update, self)
        end)
    end
    local inner = CreateFrame("Frame", nil, child)
    inner:SetPoint("TOPLEFT", 0, -top)
    inner:SetSize(740, 2000)
    -- 0.6.650: catch every switch the tab builds and give it the tile look
    local H = ns.SettingsHelpers
    local orig, made = H and H.toggle, {}
    if orig then H.toggle = function(...) local t = orig(...) made[#made + 1] = t return t end end
    local okB, errB = pcall(ns.BuildSettingsTab, tabKey, inner)
    if orig then H.toggle = orig end
    if not okB and ns.err then ns.err("settings tab " .. tabKey, errB) end
    p.skinned = made
    if ns.ComfortSkinToggle then for _, t in ipairs(made) do pcall(ns.ComfortSkinToggle, t) end end
    local function measure()
        local h = sc:GetHeight() or 0
        if h < 50 then return end
        local w = math.max(300, sc:GetWidth() or 740)
        child:SetWidth(w) inner:SetWidth(w)
        local t0 = inner:GetTop()
        local low
        local function see(o)
            if o and o.IsShown and o:IsShown() and o.GetBottom then
                local b = o:GetBottom()
                if b and (not low or b < low) then low = b end
            end
        end
        for _, c in ipairs({ inner:GetChildren() }) do see(c) end
        for _, r in ipairs({ inner:GetRegions() }) do see(r) end
        local need = (t0 and low) and (t0 - low + 18) or 400
        inner:SetHeight(need)
        child:SetHeight(math.max(h, top + need))
        local over = child:GetHeight() - h
        sc.thumb:SetShown(over > 4)
        if over > 4 then
            local th = math.max(24, h * h / child:GetHeight())
            sc.thumb:SetHeight(th)
            sc.thumb:ClearAllPoints()
            sc.thumb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -((sc:GetVerticalScroll() or 0) / over) * (h - th))
        else
            sc:SetVerticalScroll(0)
        end
    end
    sc:SetScript("OnSizeChanged", function() measure() end)
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        if max <= 0 then return end
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 48)))
        measure()
    end)
    function f:Refresh()
        ns.RefreshSettingsTab(tabKey, inner)
        if pv then pcall(PV.update, pv) end
        measure()
        if C_Timer then C_Timer.After(0, measure) end
    end
    return f
end

local buildMapPreview
-- world map preview: a piece of a zone map, the right half "unexplored" in the chosen tint
buildMapPreview = function(p)
    -- 0.6.634: a real zone (Tirisfal Glades) instead of a plain parchment tile - left half explored, right half
    -- unexplored; the right half shows the hidden areas tinted (or not at all), like the world map
    local MAP = 1420
    local f = CreateFrame("Frame", nil, p)
    f:SetSize(266, 300)
    f:SetPoint("TOPLEFT", 0, -44)
    local w = 262
    local sc = w / 1002
    local h = math.floor(668 * sc + 0.5)
    f.box = CreateFrame("Frame", nil, f)
    f.box:SetSize(w, h)
    f.box:SetPoint("TOP", 0, -26)
    f.box:SetClipsChildren(true)
    f.base = f.box:CreateTexture(nil, "BACKGROUND")
    f.base:SetAllPoints()
    f.base:SetColorTexture(0.32, 0.27, 0.18, 1)
    -- base art (parchment with fog) from the game: 4 x 3 tiles of 256 px
    local ok, tiles = pcall(function() return C_Map and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(MAP, 1) end)
    if ok and type(tiles) == "table" then
        for i, id in ipairs(tiles) do
            local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
            local t = f.box:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetTexture(id)
            t:SetSize(256 * sc, 256 * sc)
            t:SetPoint("TOPLEFT", c * 256 * sc, -r * 256 * sc)
        end
    end
    -- the explorable areas (same data as the world map reveal)
    f.pieces = {}
    local list = ns.MapRevealData and ns.MapRevealData[MAP] or {}
    for _, entry in ipairs(list) do
        local pw, ph, ox, oy, texs = entry:match("^(%d+):(%d+):(%d+):(%d+):(.+)$")
        pw, ph, ox, oy = tonumber(pw), tonumber(ph), tonumber(ox), tonumber(oy)
        if pw then
            local ids = {}
            for id in texs:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
            local cols, rows = math.ceil(pw / 256), math.ceil(ph / 256)
            local right = (ox + pw / 2) > 501   -- which half the area belongs to
            for r = 1, rows do
                for c = 1, cols do
                    local id = ids[(r - 1) * cols + c]
                    if id then
                        local tw = (c < cols) and 256 or (pw - 256 * (cols - 1))
                        local th = (r < rows) and 256 or (ph - 256 * (rows - 1))
                        local t = f.box:CreateTexture(nil, "ARTWORK")
                        t:SetTexture(id)
                        local fw, fh = 16, 16
                        while fw < tw do fw = fw * 2 end
                        while fh < th do fh = fh * 2 end
                        t:SetTexCoord(0, tw / fw, 0, th / fh)
                        t:SetSize(tw * sc, th * sc)
                        t:SetPoint("TOPLEFT", (ox + 256 * (c - 1)) * sc, -(oy + 256 * (r - 1)) * sc)
                        t.right = right
                        f.pieces[#f.pieces + 1] = t
                    end
                end
            end
        end
    end
    f.split = f.box:CreateTexture(nil, "OVERLAY")
    f.split:SetColorTexture(1, 1, 1, 0.35)
    f.split:SetSize(1, h)
    f.split:SetPoint("TOP", f.box, "TOP", 0, 0)
    f.frame = f:CreateTexture(nil, "OVERLAY")
    f.frame:SetPoint("TOPLEFT", f.box, -3, 3) f.frame:SetPoint("BOTTOMRIGHT", f.box, 3, -3)
    f.frame:SetColorTexture(0, 0, 0, 0)
    f.l1 = K.Text(f, 10, C.dim) f.l1:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 4, -6) f.l1:SetText(L["explored"])
    f.l2 = K.Text(f, 10, C.dim) f.l2:SetPoint("TOPRIGHT", f.box, "BOTTOMRIGHT", -4, -6) f.l2:SetText(L["unexplored (revealed)"])
    f.note = K.Text(f, 10, C.dim)
    f.note:SetPoint("TOP", f.box, "BOTTOM", 0, -30)
    f.note:SetText(L["Preview - changes show at once"])
    function f:Update()
        local reveal = S().mapReveal
        local r, g, b, a = 1, 1, 1, 1
        if ns.WorldMapPlus then r, g, b, a = ns.WorldMapPlus.Tint() end
        for _, t in ipairs(self.pieces) do
            if t.right then
                t:SetShown(reveal and true or false)
                t:SetVertexColor(r, g, b)
                t:SetAlpha(a)
            else
                t:Show()
                t:SetVertexColor(1, 1, 1)
                t:SetAlpha(1)
            end
        end
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
    if ns.GameChat then pcall(ns.GameChat.ApplyAll) if ns.GameChat.ApplyButtons then pcall(ns.GameChat.ApplyButtons) end end
    if ns.Comfort then
        for _, fn in ipairs({ "ApplyChat", "ApplyBars", "ApplyErrors" }) do if ns.Comfort[fn] then pcall(ns.Comfort[fn]) end end
    end
    if ns.ComfortPlus and ns.ComfortPlus.ApplyChat then pcall(ns.ComfortPlus.ApplyChat) end
    if ns.ComfortPlus and ns.ComfortPlus.UpdateXP then pcall(ns.ComfortPlus.UpdateXP) end
    if ns.Upgrade and ns.Upgrade.RefreshBadges then pcall(ns.Upgrade.RefreshBadges) end
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
-- 0.6.643: with a preview the page is split in half - left the example (scaled to fill it), right the controls
local function halfW(p) local w = p:GetWidth() or 0 if w < 300 then w = 900 end return math.floor(w / 2) end
local function fitPreview(p, fr)
    if not fr then return end
    local base = fr.baseW or fr:GetWidth() or 270
    if base < 50 then base = 270 end
    fr.baseW = base
    local sc = math.max(0.8, math.min(2, (halfW(p) - 24) / base))
    fr:SetScale(sc)
    -- offsets scale too: keep the top edge where it was
    fr:ClearAllPoints()
    fr:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -44 / sc)
end
ns.ComfortFitPreview = fitPreview
-- 0.6.644: switches as tiles - icon, title, one short explanation; click switches, bright = on
local TILE = {
    cpFishing = { "Interface\\Icons\\Trade_Fishing", "Double right-click casts, catch statistics in the overview" },
    cfQuests = { "Interface\\Icons\\INV_Misc_Note_01", "Without a reward choice or costs; Shift talks normally" },
    cfSummon = { "Interface\\Icons\\Spell_Shadow_Twilight", "Summons (not in combat) and resurrections" },
    cfBlockShared = { "Interface\\Icons\\Spell_Holy_Silence", "Quests strangers share are declined" },
    cfSellJunk = { "Interface\\Icons\\INV_Misc_Coin_19", "Grey items sold at every vendor; Shift skips" },
    cfRepair = { "Interface\\Icons\\Trade_BlackSmithing", "Repaired at every vendor who can" },
    cfRepairGuild = { "Interface\\Icons\\INV_Misc_Bag_10", "Pays from the guild bank when you may" },
    cpReagBuy = { "Interface\\Icons\\INV_Misc_Dust_02", "Refills your class reagents and the same ammo" },
    cpChatLinks = { "Interface\\Icons\\INV_Misc_Note_03", "Click a link: copy window; names in class colours" },
    emojiNoComplete = { "Interface\\Icons\\INV_Misc_Toy_10", "No emoji list after ':' and two letters" },
    cpXP = { "Interface\\Icons\\INV_Misc_Book_09", "XP per hour, time to level, rested bar" },
    cpXPShare = { "Interface\\Icons\\INV_Letter_15", "Tells the guild '~40 min to level 30' once" },
    cpFlight = { "Interface\\Icons\\Ability_Mount_Wyvern_01", "Time left while flying, learns every route" },
    cpTracking = { "Interface\\Icons\\INV_Misc_Spyglass_02", "After dying one click turns tracking back on" },
    cpInstances = { "Interface\\Icons\\INV_Misc_Key_14", "How many instances in the last hour (max 5)" },
    cpTrainer = { "Interface\\Icons\\INV_Misc_Book_11", "On level up: what you can learn and what it costs" },
    cpReagents = { "Interface\\Icons\\INV_Ammo_Arrow_02", "Warns when ammo, reagents or shards run low" },
    cpPet = { "Interface\\Icons\\Ability_Hunter_BeastTraining", "Warns when your pet is hungry" },
    cpMail = { "Interface\\Icons\\INV_Letter_02", "Takes gold and items from all mails (no COD)" },
    cfFastLoot = { "Interface\\Icons\\INV_Misc_Bag_08", "Loot windows empty at once (with auto loot)" },
    cfDurability = { "Interface\\Icons\\Trade_BlackSmithing", "Durability shown, warning before it breaks" },
    cfBlockDuels = { "Interface\\Icons\\INV_Sword_04", "Duel requests are declined" },
    cfInvites = { "Interface\\Icons\\INV_Misc_GroupLooking", "Group invites only from guild and friends" },
    cfWhisperInv = { "Interface\\Icons\\INV_Letter_15", "Guild or friends whisper the keyword: invited" },
    cpQuestShare = { "Interface\\Icons\\INV_Misc_Note_02", "Quest progress of group members in their tooltip" },
    cpProfCD = { "Interface\\Icons\\Trade_Alchemy", "Who in the guild can transmute or make cloth now" },
    cpRare = { "Interface\\Icons\\Ability_Hunter_MarkedForDeath", "Sound and notice for rares nearby" },
    cpRareShare = { "Interface\\Icons\\INV_Misc_Map_01", "Others see where you found a rare" },
    cpTooltip = { "Interface\\Icons\\INV_Misc_Coin_01", "Vendor price, item level and ID in the tooltip" },
    cpDisenchant = { "Interface\\Icons\\INV_Enchant_DustArcane", "What green, blue and epic items disenchant into" },
    cpTooltipGuild = { "Interface\\Icons\\INV_Misc_Tabard_Guild", "Oasis rank, alts and professions of guild members" },
    cpInspect = { "Interface\\Icons\\INV_Misc_Spyglass_03", "Item level of inspected players, compared to you" },
    upgradeTipOff = { "Interface\\Icons\\INV_Misc_ArrowUp", "No green upgrade arrow in item tooltips" },
    upgradeIconOff = { "Interface\\Icons\\INV_Misc_ArrowDown", "No upgrade arrows on items in bags and loot" },
    invTooltipOff = { "Interface\\Icons\\INV_Misc_Bag_07", "No list of which character has the item" },
    cfHideMicro = { "Interface\\Icons\\INV_Misc_Gear_01", "Character, spellbook buttons hidden - keys still work" },
    cfHideBags = { "Interface\\Icons\\INV_Misc_Bag_10", "Bag buttons hidden - B still opens your bags" },
    cfBarsHover = { "Interface\\Icons\\Spell_Holy_MindVision", "Hidden bars appear when the mouse is over them" },
    cfHideErrors = { "Interface\\Icons\\Spell_Shadow_DetectInvisibility", "No red error texts in the middle of the screen" },
    cpRange = { "Interface\\Icons\\Ability_Hunter_SniperShot", "Action buttons turn red when out of range" },
    gcOn = { "Interface\\Icons\\INV_Letter_15", "Everything on these pages only works with this on" },
    gcAllChannels = { "Interface\\Icons\\INV_Misc_Note_06", "Not only guild, group and whispers - also Trade, General, say, yell" },
    gcLiveSelect = { "Interface\\Icons\\INV_Feather_05", "Drag across the chat to select, Ctrl+C copies" },
    gcAltSelect = { "Interface\\Icons\\INV_Misc_Note_01", "Alt + click: the chat as a text box to select from" },
    cfChatArrows = { "Interface\\Icons\\INV_Misc_ArrowUp", "Arrow up recalls your last message" },
    cfChatNoFade = { "Interface\\Icons\\Spell_Holy_MindVision", "Old lines stay visible" },
    cfChatRestore = { "Interface\\Icons\\INV_Misc_Book_08", "The chat is still there after /reload" },
    cfChatTop = { "Interface\\Icons\\INV_Misc_Note_02", "Type above the chat window instead of below" },
    gcShort = { "Interface\\Icons\\INV_Misc_Head_Human_01", "Only the first name - whisper still uses the full one" },
    gcLevel = { "Interface\\Icons\\INV_Misc_Book_09", "The level in the difficulty colour" },
    gcClassIcon = { "Interface\\Icons\\INV_Misc_Head_Orc_01", "Small class icon before the name" },
    gcRaceIcon = { "Interface\\Icons\\INV_Misc_Head_Troll_01", "Small race icon before the name" },
    gcLinkIcons = { "Interface\\Icons\\INV_Sword_04", "Item and spell links with their icon" },
    gcTokens = { "Interface\\Icons\\INV_Misc_Gem_02", "item:6948 becomes a link, :mage: an icon (only for you)" },
    gcChNum = { "Interface\\Icons\\INV_Misc_Note_03", "[2. Trade - Orgrimmar] becomes [2]" },
    gcQuiet = { "Interface\\Icons\\INV_Misc_Ink_01", "Messages in light grey, names keep their colour" },
    gcHover = { "Interface\\Icons\\INV_Misc_Spyglass_03", "Tooltip on hovering a link, not only on click" },
    gcFilter = { "Interface\\Icons\\Spell_Holy_Silence", "Never touches guild, group, raid and your own lines" },
    gcWhole = { "Interface\\Icons\\INV_Misc_Note_05", "\"boost\" no longer matches \"boosting\"" },
    gcCyr = { "Interface\\Icons\\INV_Misc_Book_07", "Hides lines in Cyrillic letters" },
    gcHan = { "Interface\\Icons\\INV_Misc_Book_06", "Hides lines with Chinese characters" },
    gcRepeat = { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Same message, same player within the time window" },
    gcHist = { "Interface\\Icons\\INV_Misc_Book_11", "The last lines are back after logging in" },
    gcAlert = { "Interface\\Icons\\INV_Misc_Bell_01", "A notice when a line has one of your keywords" },
    gcAlertSound = { "Interface\\Icons\\INV_Misc_Drum_01", "A sound with the notice" },
    gcHideMenu = { "Interface\\Icons\\INV_Misc_Gear_02", "Removes the chat menu button" },
    gcHideChannel = { "Interface\\Icons\\INV_Misc_Gear_03", "Removes the channel button" },
    gcHideSocial = { "Interface\\Icons\\INV_Misc_GroupLooking", "Removes the social button" },
    gcHideScroll = { "Interface\\Icons\\INV_Misc_ArrowDown", "Removes the scroll buttons" },
    gatherScan = { "Interface\\Icons\\INV_Misc_Spyglass_02", "Finds herb and ore dots on the minimap by itself" },
    gatherSymbols = { "Interface\\Icons\\INV_Misc_Flower_02", "Real herb and ore pictures instead of yellow dots" },
    gatherSwitch = { "Interface\\Icons\\INV_Pick_02", "Switches herb and mineral search while you walk" },
    gatherSound = { "Interface\\Icons\\INV_Misc_Bell_01", "A soft ping when something new appears" },
    gatherSkillOff = { "Interface\\Icons\\INV_Misc_Book_09", "No skill line when you hover a dot" },
    gatherArrow = { "Interface\\Icons\\Ability_Hunter_Pathfinding", "An arrow on the screen to the nearest node" },
    gatherArrowLock = { "Interface\\Icons\\INV_Misc_Key_03", "The arrow stays put, clicks go through it" },
    gatherArrowProfFirst = { "Interface\\Icons\\INV_Misc_Herb_10", "Treasures and rares only when no herb or ore is near" },
    gatherArrowCaves = { "Interface\\Icons\\INV_Misc_Lantern_01", "Also nodes in caves and on other levels" },
    gatherArrowHerb = { "Interface\\Icons\\INV_Misc_Flower_02", "The arrow points to herbs" },
    gatherArrowOre = { "Interface\\Icons\\INV_Ore_Copper_01", "The arrow points to ore" },
    gatherArrowTreasure = { "Interface\\Icons\\INV_Box_01", "The arrow points to chests" },
    gatherArrowRare = { "Interface\\Icons\\Ability_Hunter_MarkedForDeath", "The arrow points to rare enemies" },
    gatherArrowLeyline = { "Interface\\Icons\\Spell_Arcane_Arcane04", "The arrow points to leylines" },
    gatherSparkle = { "Interface\\Icons\\Spell_Holy_HolyBolt", "Gold sparkles on the node in front of you" },
    gatherSparkleHideIcons = { "Interface\\Icons\\Spell_Shadow_DetectInvisibility", "Only the sparkles, no game icon above the node" },
    gatherSparkleFar = { "Interface\\Icons\\Spell_Holy_MindVision", "Sparkles on nodes further away (beta)" },
    gatherPin = { "Interface\\Icons\\INV_Misc_Map_01", "The game's map pin with a marker in the world" },
    gatherAlerts = { "Interface\\Icons\\INV_Misc_Herb_BlackLotus", "A notice when the guild sees a node you watch" },
    gatherAlertsShare = { "Interface\\Icons\\INV_Letter_15", "Your valuable finds go to the guild" },
    gatherWanted = { "Interface\\Icons\\INV_Misc_Bag_10", "What the guild needs glows gold and comes first" },
    gatherShareArea = { "Interface\\Icons\\Spell_Holy_PrayerOfSpirit", "The arrow leaves nearby guild farmers their side" },
    gatherRouteSkill = { "Interface\\Icons\\INV_Misc_Book_11", "The route only takes nodes that still give skill" },
    gatherRoute = { "Interface\\Icons\\INV_Misc_Map02", "A round trip through the zone's nodes" },
    mapReveal = { "Interface\\Icons\\INV_Misc_Map_01", "Shows the parts of the map you have not explored" },
    mapRevealTint = { "Interface\\Icons\\INV_Misc_Ink_01", "Those parts slightly tinted" },
    wmMove = { "Interface\\Icons\\Spell_Nature_FarSight", "Drag the world map by its title bar" },
    wmNoEmote = { "Interface\\Icons\\INV_Misc_Book_08", "No reading animation when you open the map" },
    wmHideTowns = { "Interface\\Icons\\INV_Misc_Flag", "Fewer icons on continent maps" },
    wmGroupClass = { "Interface\\Icons\\INV_Misc_GroupLooking", "Your group on the map in class colours" },
    mapDungeons = { "Interface\\Icons\\INV_Misc_Key_14", "Dungeon entrances with level range" },
    mapDanger = { "Interface\\Icons\\Ability_Creature_Cursed_02", "Red where several guild members died" },
    mapPoi = { "Interface\\Icons\\INV_Misc_Coin_01", "Vendors, repair, mailboxes and flight points" },
    mapQuestGivers = { "Interface\\Icons\\INV_Misc_Note_01", "Where dungeon quests start" },
    mapTrails = { "Interface\\Icons\\Ability_Tracking", "Your path of the last minutes" },
    trailSession = { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Keep your whole session's path" },
    mapTrailsGuild = { "Interface\\Icons\\Ability_Hunter_SniperShot", "Paths of guild members" },
    mmCoords = { "Interface\\Icons\\INV_Misc_Spyglass_03", "Coordinates under the minimap" },
    layerAsk = { "Interface\\Icons\\Spell_Arcane_PortalDalaran", "Join guild members on their layer" },
    twQuestLevel = { "Interface\\Icons\\INV_Misc_Book_09", "[12] before each quest in the log" },
    twTaxi = { "Interface\\Icons\\Ability_Mount_Wyvern_01", "Flight masters open the flight map at once" },
    twTrainAll = { "Interface\\Icons\\INV_Misc_Book_11", "A button that learns everything you can afford" },
    twBgRelease = { "Interface\\Icons\\Spell_Holy_Resurrection", "Released at once when you die in a battleground" },
    twLootSparkle = { "Interface\\Icons\\INV_Misc_Gem_Pearl_04", "Quest items in the world always sparkle" },
    cfQuestPlates = { "Interface\\Icons\\INV_Misc_Note_02", "Enemies your quests need show 3/8 on their plate" },
    cfQuestTarget = { "Interface\\Icons\\Ability_Hunter_MarkedForDeath", "A key that targets the next quest enemy" },
    cfRestockOn = { "Interface\\Icons\\INV_Drink_07", "Buys water, food, reagents from your list" },
    cfAmmo = { "Interface\\Icons\\INV_Ammo_Arrow_02", "Only when the vendor has better ammo than yours" },
    twJunkMark = { "Interface\\Icons\\INV_Misc_Coin_19", "Alt+right-click marks anything as junk" },
    twGear = { "Interface\\Icons\\INV_Chest_Plate06", "Gear sets: Ctrl+right-click, equip in one click" },
    cfLootConfirm = { "Interface\\Icons\\INV_Misc_Bag_08", "No question for bind-on-pickup loot" },
    cfEasyDestroy = { "Interface\\Icons\\Spell_Fire_Fire", "No typing DELETE to destroy" },
    twAhIlvl = { "Interface\\Icons\\INV_Misc_Coin_02", "Item level in the auction house list" },
    cfDestroyCheap = { "Interface\\Icons\\INV_Misc_Bag_07", "Bags full: offers to destroy the cheapest item" },
    cfOpenButton = { "Interface\\Icons\\INV_Box_01", "One button opens clams, sacks and boxes" },
    twTipClass = { "Interface\\Icons\\INV_Misc_Head_Human_01", "Names in class colour" },
    twTipBar = { "Interface\\Icons\\INV_Potion_51", "Health bar inside the box" },
    cfTipRank = { "Interface\\Icons\\INV_Misc_Tabard_Guild", "Guild and rank of players" },
    cfTipTarget = { "Interface\\Icons\\Ability_Hunter_SniperShot", "Whom they are targeting" },
    cfTipCombat = { "Interface\\Icons\\Ability_Warrior_BattleShout", "Hidden in combat, Shift shows it" },
    cfTipFaction = { "Interface\\Icons\\INV_BannerPVP_02", "Blue for Alliance, red for Horde" },
    cfSquareMap = { "Interface\\Icons\\INV_Misc_Map_01", "Square instead of round minimap" },
    cfMapButtons = { "Interface\\Icons\\INV_Misc_Gear_01", "Addon buttons only on mouse-over" },
    twCamera = { "Interface\\Icons\\INV_Misc_Spyglass_01", "Zoom out much further" },
    twNoGlow = { "Interface\\Icons\\Spell_Shadow_Twilight", "Sharper picture without the glow" },
    cfMuteChimes = { "Interface\\Icons\\INV_Misc_Bell_01", "No clock chimes in towns" },
    cfMuteFizzle = { "Interface\\Icons\\Spell_Fire_SelfDestruct", "No sound when a spell fizzles" },
    cfMuteTrains = { "Interface\\Icons\\INV_Misc_Toy_10", "No /train sounds" },
    cfMuteYawns = { "Interface\\Icons\\Ability_Druid_CatForm", "No yawning hunter cats" },
    cfNoCombatTab = { "Interface\\Icons\\INV_Sword_04", "Hides the combat log tab" },
    cfNoChatButtons = { "Interface\\Icons\\INV_Misc_Gear_02", "Hides the buttons next to the chat" },
    cfSpamFilter = { "Interface\\Icons\\INV_Drink_04", "No duel results and drunk messages" },
    whisperForward = { "Interface\\Icons\\INV_Letter_15", "Offers to send a whisper to the alt who is online" },
}
-- 0.6.647: options that only work with another one: shown indented under it, greyed while it is off
local PARENT = {
    gatherSymbols = "gatherScan", gatherSwitch = "gatherScan", gatherSound = "gatherScan",
    gatherArrowLock = "gatherArrow", gatherArrowProfFirst = "gatherArrow", gatherArrowCaves = "gatherArrow",
    gatherArrowHerb = "gatherArrow", gatherArrowOre = "gatherArrow", gatherArrowTreasure = "gatherArrow",
    gatherArrowRare = "gatherArrow", gatherArrowLeyline = "gatherArrow",
    gatherSparkleHideIcons = "gatherSparkle",
    gatherRouteSkill = "gatherRoute",
    mapRevealTint = "mapReveal", trailSession = "mapTrails",
    -- game chat: everything hangs on the master switch, the filter options on "Enable filters"
    gcAllChannels = "gcOn", gcLiveSelect = "gcOn", gcAltSelect = "gcOn",
    gcShort = "gcOn", gcLevel = "gcOn", gcClassIcon = "gcOn", gcRaceIcon = "gcOn", gcLinkIcons = "gcOn", gcTokens = "gcOn",
    gcChNum = "gcOn", gcQuiet = "gcOn", gcHover = "gcOn",
    gcFilter = "gcOn", gcWhole = "gcFilter", gcCyr = "gcFilter", gcHan = "gcFilter", gcRepeat = "gcFilter",
    gcHist = "gcOn", gcAlert = "gcOn", gcAlertSound = "gcAlert",
    cfRepairGuild = "cfRepair", cpXPShare = "cpXP", cpRareShare = "cpRare",
}
ns.ComfortParent = PARENT
local INDENT = 26
local function makeTile(box, row, p, w)
    -- 0.6.648: rounded glass card, icon in a round frame, soft hover (brighter, icon grows), press, the knob glides, children hang on a tree line
    local info = TILE[row[2]] or {}
    local parent = PARENT[row[2]]
    if parent then w = w - INDENT end
    local G = ns.Insta and ns.Insta.Glass
    local t = CreateFrame("Button", nil, box)
    t:SetSize(w, 44)
    t.glass = G and pcall(G, t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 9)
    if not t.glass then t.bg = K.Fill(t, { 1, 1, 1, 0.03 }) K.Border(t, C.line) end
    -- "on": a soft colour from the left that fades out
    t.onFill = t:CreateTexture(nil, "BACKGROUND", nil, 3)
    t.onFill:SetPoint("TOPLEFT", 1, -1) t.onFill:SetPoint("BOTTOMLEFT", 1, 1) t.onFill:SetWidth(w * 0.6)
    t.onFill:SetColorTexture(1, 1, 1, 1)
    -- icon in a round frame
    t.iconBox = CreateFrame("Frame", nil, t)
    t.iconBox:SetSize(30, 30) t.iconBox:SetPoint("LEFT", 9, 0)
    t.ring = t.iconBox:CreateTexture(nil, "BACKGROUND")
    t.ring:SetPoint("TOPLEFT", -2, 2) t.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    t.ring:SetTexture(ns.MEDIA .. "pinring")
    t.icon = t.iconBox:CreateTexture(nil, "ARTWORK") t.icon:SetAllPoints()
    t.icon:SetTexture(info[1] or "Interface\\Icons\\INV_Misc_QuestionMark") t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if t.iconBox.CreateMaskTexture and t.icon.AddMaskTexture then
        pcall(function()
            local m = t.iconBox:CreateMaskTexture()
            m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t.icon)
            t.icon:AddMaskTexture(m)
        end)
    end
    t.title = K.Text(t, 12, C.text) t.title:SetPoint("TOPLEFT", t.iconBox, "TOPRIGHT", 11, info[2] and 0 or -8)
    t.title:SetPoint("RIGHT", t, "RIGHT", -54, 0) t.title:SetJustifyH("LEFT") t.title:SetWordWrap(false)
    t.title:SetText(L[row[1]])
    t.desc = K.Text(t, 10, C.dim) t.desc:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3)
    t.desc:SetPoint("RIGHT", t, "RIGHT", -54, 0) t.desc:SetJustifyH("LEFT") t.desc:SetWordWrap(true)
    if t.desc.SetMaxLines then t.desc:SetMaxLines(2) end
    t.desc:SetText(info[2] and L[info[2]] or "")
    local dh = (t.desc.GetStringHeight and t.desc:GetStringHeight()) or 10
    t:SetHeight(math.max(46, 28 + math.min(dh, 24)))
    t.parentKey, t.indent = parent, parent and INDENT or 0
    -- tree line to the parent: vertical from above, short horizontal into the card
    if parent then
        t.treeV = t:CreateTexture(nil, "BACKGROUND")
        t.treeV:SetColorTexture(1, 1, 1, 0.12) t.treeV:SetWidth(1)
        t.treeV:SetPoint("TOPRIGHT", t, "TOPLEFT", -12, 6) t.treeV:SetPoint("BOTTOMRIGHT", t, "LEFT", -12, 0)
        t.treeH = t:CreateTexture(nil, "BACKGROUND")
        t.treeH:SetColorTexture(1, 1, 1, 0.12) t.treeH:SetHeight(1)
        t.treeH:SetPoint("LEFT", t, "LEFT", -12, 0) t.treeH:SetPoint("RIGHT", t, "LEFT", 0, 0)
    end
    t.state = K.Text(t, 10, C.dim) t.state:Hide()
    t.pill = K.Pill(t, 32, 17) t.pill:SetPoint("RIGHT", -12, 0)
    if row[2] == "gcOn" then
        t.tag = K.Text(t, 9, C.accent) t.tag:SetPoint("RIGHT", t.pill, "LEFT", -10, 0)
        t.tag:SetText(K.Upper and K.Upper(L["Master switch"]) or L["Master switch"])
        t.title:SetPoint("RIGHT", t.tag, "LEFT", -8, 0)
    end
    t.knob = K.KnobCircle(t.pill, 13)
    -- animation state: hover 0..1, knob position 0..1, press
    t.hov, t.kx, t.kTarget, t.press = 0, 0, 0, 0
    local function paint(self)
        local ac, on = C.accent, self.onv
        local h = self.hov
        if self.glass and G then
            local fa = 0.03 + h * 0.05 + (on and 0.02 or 0)
            local la = on and (0.35 + h * 0.25) or (0.08 + h * 0.10)
            local lc = on and ac or { 1, 1, 1 }
            pcall(G, self, { 1, 1, 1, fa }, { lc[1], lc[2], lc[3], la }, 9)
        end
        if K.Gradient and on then
            K.Gradient(self.onFill, "HORIZONTAL", { ac[1], ac[2], ac[3], 0.16 + h * 0.06 }, { ac[1], ac[2], ac[3], 0 })
        end
        self.onFill:SetShown(on and true or false)
        local sc = 1 + h * 0.08 - self.press * 0.06
        self.iconBox:SetScale(sc)
        local rc = on and ac or { 0.35, 0.35, 0.4 }
        self.ring:SetVertexColor(rc[1], rc[2], rc[3], on and 0.9 or 0.6)
        -- knob glides between left and right
        self.knob:ClearAllPoints()
        self.knob:SetPoint("CENTER", self.pill, "LEFT", 8.5 + self.kx * 15, 0)
        self:SetAlpha((self.usable == false and 0.35) or 1)
    end
    t:SetScript("OnUpdate", function(self, el)
        el = math.min(el or 0, 0.05)
        local hT = (self:IsMouseOver() and self.usable ~= false) and 1 or 0
        local busy = false
        if math.abs(self.hov - hT) > 0.01 then self.hov = self.hov + (hT - self.hov) * math.min(1, el * 12) busy = true else self.hov = hT end
        if math.abs(self.kx - self.kTarget) > 0.01 then self.kx = self.kx + (self.kTarget - self.kx) * math.min(1, el * 16) busy = true else self.kx = self.kTarget end
        if self.press > 0 then self.press = math.max(0, self.press - el * 6) busy = true end
        if busy or self.dirty then self.dirty = nil paint(self) end
    end)
    function t:Refresh()
        local onv = get(row[2])
        self.onv = onv
        local usable = true
        local par = self.parentKey
        while par do if not get(par) then usable = false break end par = PARENT[par] end
        self.usable = usable and true or false
        self:EnableMouse(usable)
        self.state:SetText(onv and L["On"] or L["Off"])
        self.kTarget = onv and 1 or 0
        if self.kx == nil then self.kx = self.kTarget end
        local pc = onv and C.accent or { 0.22, 0.22, 0.25 }
        self.pill:SetColor(pc[1], pc[2], pc[3], 1)
        local kc = onv and 1 or 0.62
        self.knob:SetVertexColor(kc, kc, kc + (onv and 0 or 0.04), 1)
        local tc = onv and C.text or C.muted
        self.title:SetTextColor(tc[1], tc[2], tc[3])
        self.icon:SetDesaturated(not onv) self.icon:SetAlpha(onv and 1 or 0.6)
        self.dirty = true
        paint(self)
    end
    t:SetScript("OnMouseDown", function(self) self.press = 1 self.dirty = true end)
    -- 0.6.649: show in the preview what this option changes
    t:SetScript("OnEnter", function()
        local PV = ns.ComfortPreviews
        local g = p.gen and p.gen[p.cur]
        -- 0.6.655: gathering/world map previews get the caption too
        if not g then g = (p.mpv and p.mpv:IsShown() and p.mpv) or (p.pv and p.pv:IsShown() and p.pv) or nil end
        if PV and PV.Focus and g then pcall(PV.Focus, g, row[2], L[row[1]], info[2] and L[info[2]]) end
    end)
    t:SetScript("OnLeave", function()
        local PV = ns.ComfortPreviews
        local g = p.gen and p.gen[p.cur]
        if not g then g = (p.mpv and p.mpv:IsShown() and p.mpv) or (p.pv and p.pv:IsShown() and p.pv) or nil end
        if PV and PV.Focus and g then pcall(PV.Focus, g, nil) end
    end)
    t:SetScript("OnClick", function(self)
        local v = not get(row[2])
        set(row[2], v)
        self:Refresh()
        -- children follow their parent
        if box.ctrls then for _, c in ipairs(box.ctrls) do if c.parentKey and c.Refresh then c:Refresh() end end end
        apply(p)
        if v and row[2] == "gatherSound" and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "Master") end
    end)
    t.kx = get(row[2]) and 1 or 0
    t:Refresh()
    return t
end
-- 0.6.650: the switches of the tabs taken over from the big settings (game chat, helpers, guild helpers) get the
-- tile look on top - glass card, icon, switch on the right, soft hover, coloured edge when on. Their places stay.
local PREFIX_ICON = { gc = "INV_Letter_15", cf = "INV_Misc_Gear_01", cp = "INV_Misc_Book_09", tw = "INV_Misc_Gear_02" }
-- 0.6.651: dependencies on these tabs too - master switches are marked, their options greyed while they are off
local SKIN_PARENT = {
    gcWhole = "gcFilter", gcCyr = "gcFilter", gcHan = "gcFilter", gcRepeat = "gcFilter", gcAlertSound = "gcAlert",
    cfRepairGuild = "cfRepair", cpXPShare = "cpXP", cpRareShare = "cpRare",
}
local MASTER = { gcOn = true }
local function parentOf(key)
    if SKIN_PARENT[key] then return SKIN_PARENT[key] end
    if key:sub(1, 2) == "gc" and key ~= "gcOn" then return "gcOn" end
end
local skinned = {}
local function repaintAll() for _, f in ipairs(skinned) do if f.oaPaint then pcall(f.oaPaint, f:IsMouseOver()) end end end
local function skinToggle(f)
    if f.oaSkinned or not (f.settingKey and f.lbl) then return end
    f.oaSkinned = true
    skinned[#skinned + 1] = f
    local key = f.settingKey
    f.oaParent = parentOf(key)
    -- an option whose own parent has a parent (filter options under the master switch) follows both
    if MASTER[key] then
        f.oaTag = K.Text(f, 9, C.accent)
        f.oaTag:SetPoint("RIGHT", f, "RIGHT", -48, 0)
        f.oaTag:SetText(K.Upper and K.Upper(L["Master switch"]) or L["Master switch"])
    end
    local G = ns.Insta and ns.Insta.Glass
    local track
    for _, c in ipairs({ f:GetChildren() }) do if c.GetObjectType and c:GetObjectType() == "Frame" then track = c break end end
    local par = f:GetParent()
    local _, _, _, x = f:GetPoint(1)
    local pw = par and par.GetWidth and par:GetWidth() or 0
    if pw and pw > 120 then f:SetWidth(pw - (x or 14) - 12) end
    local h = f.hasSub and 40 or 28
    f:SetHeight(h)
    -- glass card slightly larger than the row
    local card = CreateFrame("Frame", nil, f)
    card:SetPoint("TOPLEFT", -6, 4) card:SetPoint("BOTTOMRIGHT", 4, -4)
    card:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    card.glass = G and pcall(G, card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 8)
    f.oaCard = card
    -- icon
    local info = TILE[key]
    local pre = key:match("^(%l%l)")
    local ic = info and info[1] or (pre and PREFIX_ICON[pre] and ("Interface\\Icons\\" .. PREFIX_ICON[pre]))
    if ic then
        f.oaIcon = f:CreateTexture(nil, "ARTWORK")
        f.oaIcon:SetSize(20, 20) f.oaIcon:SetPoint("LEFT", 2, 0)
        f.oaIcon:SetTexture(ic) f.oaIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if f.CreateMaskTexture and f.oaIcon.AddMaskTexture then
            pcall(function()
                local m = f:CreateMaskTexture()
                m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(f.oaIcon) f.oaIcon:AddMaskTexture(m)
            end)
        end
    end
    -- label after the icon, switch to the right
    f.lbl:ClearAllPoints()
    f.lbl:SetPoint(f.hasSub and "TOPLEFT" or "LEFT", f, f.hasSub and "TOPLEFT" or "LEFT", ic and 30 or 6, f.hasSub and -6 or 0)
    if f.sub then f.sub:SetPoint("RIGHT", f, "RIGHT", -50, 0) end
    if track then track:ClearAllPoints() track:SetPoint("RIGHT", f, "RIGHT", -6, 0) end
    local function usableNow()
        local par = f.oaParent
        while par do
            if not ns.db.settings[par] then return false end
            par = parentOf(par)
        end
        return true
    end
    local function paint(hover)
        local on = (ns.db.settings[key] and true) or false
        local usable = usableNow()
        f:SetAlpha(usable and 1 or 0.35)
        f:EnableMouse(usable)
        if not usable then hover = false end
        local ac = C.accent
        if card.glass and G then
            local lc = on and ac or { 1, 1, 1 }
            pcall(G, card, { 1, 1, 1, 0.03 + (hover and 0.04 or 0) }, { lc[1], lc[2], lc[3], on and (hover and 0.6 or 0.4) or (hover and 0.16 or 0.08) }, 8)
        end
        if f.oaIcon then f.oaIcon:SetDesaturated(not on) f.oaIcon:SetAlpha(on and 1 or 0.6) end
    end
    f:HookScript("OnEnter", function() paint(true) end)
    f:HookScript("OnLeave", function() paint(false) end)
    f:HookScript("OnClick", function() paint(f:IsMouseOver()) repaintAll() end)
    f.oaPaint = paint
    if f.Refresh then hooksecurefunc(f, "Refresh", function() paint(f:IsMouseOver()) end) end
    paint(false)
end
local function skinAll(root)
    if not root then return end
    local function walk(fr, depth)
        if depth > 8 then return end
        if fr.settingKey then pcall(skinToggle, fr) end
        for _, c in ipairs({ fr:GetChildren() }) do walk(c, depth + 1) end
    end
    walk(root, 0)
end
ns.ComfortSkinToggles = skinAll
ns.ComfortSkinToggle = skinToggle
local function buildControls(p, key, withPreview)
    local box = CreateFrame("Frame", nil, p)
    box:SetPoint("TOPLEFT", withPreview and halfW(p) or 0, -44)
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
    -- 0.6.644: tiles instead of switches; without a preview and with many of them: two columns
    local twoCol = not withPreview and #o > 5
    local half = math.ceil(#o / 2)
    local fullW = withPreview and (halfW(p) - 24) or 380
    local startY = y
    local colY = { startY, startY }
    for i, row in ipairs(o) do
        local t = makeTile(box, row, p, fullW)
        local col = (twoCol and i > half) and 1 or 0
        t:SetPoint("TOPLEFT", col * 392 + t.indent, colY[col + 1])
        colY[col + 1] = colY[col + 1] - t:GetHeight() - 4
        box.ctrls[#box.ctrls + 1] = t
    end
    y = math.min(colY[1], colY[2])
    y = y - 4
    local sliders = o.slider or {}
    local two = #sliders > 2
    for i, sd in ipairs(sliders) do
        local col = two and ((i - 1) % 2) or 0
        if col == 0 then y = y - 2 end   -- 0.6.636: more compact
        local colW = withPreview and math.floor((halfW(p) - 20) / 2) or 250
        local x = col * colW
        local lab = K.Text(box, 11, C.muted)
        lab:SetPoint("TOPLEFT", x, y)
        lab:SetText(L[sd[1]])
        local sl = K.Slider(box, two and (colW - 30) or 260, sd[3], sd[4], sd[5], function() return S()[sd[2]] or sd[6] end,
            function(v)
                S()[sd[2]] = (v ~= sd[6]) and v or nil
                apply(p)
            end, sd[7] or function(v) return math.floor(v * 100 + 0.5) .. " %" end)
        sl:SetPoint("TOPLEFT", x, y - 15)
        box.ctrls[#box.ctrls + 1] = sl
        if not two or col == 1 or i == #sliders then y = y - 40 end
    end
    if o.extra then
        local ok, ny = pcall(function()
            local UI, GC = ns.GameChat and ns.GameChat.UI or {}, ns.GameChat or {}
            local yy = y - 4
            local w = (withPreview and (halfW(p) - 24)) or 740
            if o.extra == "stamp" then
                local lab = K.Text(box, 11, C.muted) lab:SetPoint("TOPLEFT", 0, yy) lab:SetText(L["Timestamp"])
                local b = K.Button(box, UI.stampText(), 170, 24, "ghost")
                b:SetPoint("TOPLEFT", 140, yy + 4)
                b:SetScript("OnClick", function(self) UI.stampMenu(self) end)
                yy = yy - 34
            elseif o.extra == "filterLists" then
                local h1 = K.Text(box, 11, C.amber or C.accent) h1:SetPoint("TOPLEFT", 0, yy) h1:SetText(L["Blocked words"])
                UI.editor(box, yy + 6, math.min(w, 560) - 14, "gcPhrases", "Word or phrase")
                yy = yy - 96
                local h2 = K.Text(box, 11, C.amber or C.accent) h2:SetPoint("TOPLEFT", 0, yy) h2:SetText(L["Mute a player in one channel"])
                UI.editor(box, yy + 6, math.min(w, 560) - 14, "gcMutes", "Channel; player name", UI.muteValue)
                yy = yy - 96
                pcall(UI.refresh)
            elseif o.extra == "overview" then
                local b = K.Button(box, L["Characters & helpers - overview"], 260, 26, "primary", function() if ns.Helpers2 then ns.Helpers2.Overview() end end)
                b:SetPoint("TOPLEFT", 0, yy)
                local n = K.Text(box, 10, C.dim) n:SetPoint("TOPLEFT", 0, yy - 30)
                n:SetText(L["Gold, hearthstone, instance IDs, guild cooldowns, sets and fishing stats (/oa chars)"])
                yy = yy - 50
            elseif o.extra == "invKeyword" then
                local lab = K.Text(box, 11, C.muted) lab:SetPoint("TOPLEFT", 0, yy) lab:SetText(L["Keyword"] .. " (" .. L["Invite by whisper (guild/friends only)"] .. ")")
                local kw = K.Input(box, 140, "inv", function(t) S().cfInvKeyword = t end)
                kw:SetPoint("TOPLEFT", 0, yy - 18)
                kw:SetText(S().cfInvKeyword or "")
                yy = yy - 52
            elseif o.extra == "histAlerts" then
                local find = K.Button(box, L["Search chat"], 160, 24, "primary", function() GC.OpenViewer("search") end)
                find:SetPoint("TOPLEFT", 0, yy)
                local hits = K.Button(box, L["View matches"], 160, 24, "ghost", function() GC.OpenViewer("alerts") end)
                hits:SetPoint("TOPLEFT", 170, yy)
                yy = yy - 34
                local h1 = K.Text(box, 11, C.amber or C.accent) h1:SetPoint("TOPLEFT", 0, yy) h1:SetText(L["Keyword alerts"])
                UI.editor(box, yy + 6, math.min(w, 560) - 14, "gcWords", "Keyword, e.g. looking for healer")
                yy = yy - 96
                pcall(UI.refresh)
            end
            return yy
        end)
        if ok and ny then y = ny end
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
                    f = buildTabPage(p, t.tab)
                else
                    local PV = ns.ComfortPreviews
                    f = buildControls(p, t.key, t.preview or t.mappreview or (PV and PV[t.key]))
                end
                p.views[t.key] = f
            end
            if f.Refresh then f:Refresh() end
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
    fitPreview(p, p.pv) fitPreview(p, p.mpv)
    for _, g in pairs(p.gen or {}) do fitPreview(p, g) end
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

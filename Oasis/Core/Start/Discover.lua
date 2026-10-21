-- Oasis: tidy onboarding
--  * on first start (after the tour): "What are you interested in?" - only matching sections stay in the navigation
--  * Page "Entdecken": all sections as cards with a one-sentence explanation and on/off
--  * gradually: every few days a hint about a hidden section (click = turn on)
-- Uses settings.hiddenPages; what was hidden here is remembered in settings.focusHidden (own decisions stay).
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local D = {}
ns.Discover = D

-- always visible
D.CORE = { home = true, chat = true, radar = true, settings = true, discover = true, admin = true }
-- never hideable (no eye); chat and members can be hidden by the user
D.LOCKED = { settings = true, admin = true, home = true }   -- 0.6.468: dashboard fixed again (once hidden it could not be brought back)   -- 0.5.550: dashboard and Discover can also be hidden
-- Interests -> sections
-- 0.6.573: the tiles are the sidebar groups - Oasis itself (Me, Play together, Fun) and the add-ons
-- (Groups & Raids, Trade, Convenience). Guild pages are always on. Keys stay (saved choices, tile art).
D.INTERESTS = {
    { key = "level", text = "Me", sub = "My Journey, profile, bags, badges, legacy, Oasis rank, reputation", icon = "life", color = C.accent, group = "me" },
    { key = "group", text = "Play together", sub = "Quest partners, quest items, recruiting, campfires", icon = "groups", color = C.mint, group = "play" },
    { key = "fun", text = "Fun", sub = "Deathroll, Guildotchi and more", icon = "deathroll", color = C.pink, group = "fun" },
    { key = "raid", text = "Groups & Raids", sub = "Groups, dungeons, raids, loot, raid check", icon = "raid", color = C.red, group = "raid", addon = "Oasis_GroupsRaids" },
    { key = "trade", text = "Trade", sub = "Crafting, market, wishlist", icon = "crafting", color = C.amber, group = "trade", addon = "Oasis_Trade" },
    { key = "collect", text = "Convenience", sub = "Comfort helpers, map extras, game chat, upgrade search", icon = "home", color = C.blue, group = "convenience", addon = "Oasis_Convenience" },
}
local function navGroup(key)
    for _, g in ipairs(ns.NAV_GROUPS or {}) do if g.key == key then return g end end
end
-- pages of a tile = pages of its sidebar group (modules add their pages there while loading)
function D.PagesOf(it)
    local g = navGroup(it.group)
    return g and g.pages or {}
end
-- add-on of the tile installed? (Oasis itself always)
function D.Available(it)
    return not it.addon or (ns.ModuleLoader and ns.ModuleLoader.PartLoaded and ns.ModuleLoader.PartLoaded(it.addon)) or false
end
local interestOf = setmetatable({}, { __index = function(_, k)
    for _, it in ipairs(D.INTERESTS) do for _, p in ipairs(D.PagesOf(it)) do if p == k then return it end end end
end })

local function S() return ns.db.settings end
local function relayout()
    if ns.LayoutNav then pcall(ns.LayoutNav) end
    if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end
    ns.RefreshPage("discover")
end
-- all sections that can be toggled
function D.Pages()
    local out = {}
    for _, d in ipairs(ns.Pages()) do
        if d.title and not d.topbar and not d.parent and not D.CORE[d.key] and d.key ~= "officer" and (not d.visible or d.visible()) and not (ns.GuildOnly and ns.GuildOnly(d.key)) then out[#out + 1] = d end
    end
    return out
end
function D.IsOn(key) return not (S().hiddenPages and S().hiddenPages[key]) end
function D.Set(key, on)
    local s = S()
    s.hiddenPages = s.hiddenPages or {}
    s.focusHidden = s.focusHidden or {}
    if on then
        s.hiddenPages[key] = nil
        s.focusHidden[key] = nil
    else
        s.hiddenPages[key] = true
        s.focusHidden[key] = true
    end
    if ns.ModuleLoader and ns.ModuleLoader.PageToggled then pcall(ns.ModuleLoader.PageToggled, key, on) end
    relayout()
end
-- show only the chosen interests
function D.ApplyInterests(sel)
    local s = S()
    s.interests = sel
    local keep = {}
    for _, it in ipairs(D.INTERESTS) do if sel[it.key] then for _, k in ipairs(D.PagesOf(it)) do keep[k] = true end end end
    -- guild pages are Oasis itself - never hidden by the tiles
    for _, gk in ipairs({ "top", "guild" }) do local g = navGroup(gk) if g then for _, k in ipairs(g.pages) do keep[k] = true end end end
    s.hiddenPages = s.hiddenPages or {}
    s.focusHidden = s.focusHidden or {}
    for _, d in ipairs(D.Pages()) do
        if keep[d.key] then
            if s.focusHidden[d.key] then s.hiddenPages[d.key] = nil s.focusHidden[d.key] = nil end
        elseif not s.hiddenPages[d.key] then
            s.hiddenPages[d.key] = true
            s.focusHidden[d.key] = true
        end
    end
    s.interestsDone = ns.now()
    s.hintLast = ns.now()   -- first hint only in a few days
    D.Calm(true)
    relayout()
end
-- Calm start: plain start page, calm banner, less motion (all switchable under Settings > Dashboard)
function D.Calm(on)
    local s = S()
    if on then
        s.dashStill = true
        s.dashTicker, s.dashHero = false, false
        s.hideMidasAd = true
        s.calmStart = true
    else
        s.dashSimple, s.dashStill, s.dashTicker, s.dashHero, s.hideMidasAd, s.calmStart = nil, nil, nil, nil, nil, nil
    end
    local def = ns.PageDef and ns.PageDef("home")
    if def and def.frame and def.frame.Layout then pcall(def.frame.Layout, def.frame) end
    ns.RefreshPage("home")
end
function D.ShowAll()
    local s = S()
    for k in pairs(s.focusHidden or {}) do if s.hiddenPages then s.hiddenPages[k] = nil end end
    s.focusHidden = nil
    if s.calmStart then D.Calm(false) end   -- whoever wants everything also gets the full start page
    relayout()
end

------------------------------------------------------------------------
-- "What are you interested in?" (small window)
------------------------------------------------------------------------
local pick
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function grad(tex, dir, a, b)
    if not K.Gradient(tex, dir, a, b) then tex:SetColorTexture(b[1], b[2], b[3], (b[4] or 1) * 0.6) end
end
-- plain text button (footer): quiet, bright on hover
-- 0.6.123: small, subtle glass buttons (semi-transparent, rounded corners) instead of bare text
local function textBtn(parent, label, w, fn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 24)
    local G = ns.Insta and ns.Insta.Glass
    b.glass = G and pcall(G, b, { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.12 }, 8)
    b.hov = b:CreateTexture(nil, "BACKGROUND", nil, 3)
    b.hov:SetPoint("TOPLEFT", 3, -3) b.hov:SetPoint("BOTTOMRIGHT", -3, 3)
    b.hov:SetColorTexture(1, 1, 1, 0.06)
    b.hov:Hide()
    b.label = K.Text(b, 11, C.muted, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", b.label, "BOTTOMLEFT", 0, -3)
    b.line:SetPoint("BOTTOMRIGHT", b.label, "BOTTOMRIGHT", 0, -3)
    b.line:SetColorTexture(1, 1, 1, 0.25)
    b.line:Hide()
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) self.hov:Show() end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) self.hov:Hide() end)
    b:SetScript("OnClick", fn)
    return b
end
function D.ShowPicker(mode)
    if not pick then
        local W, COLS, TW, TH, GAP = 660, 3, 196, 128, 12
        -- 0.6.124: wider with image tiles - tile 228 x 56 = exactly the 4:1 image format (previously clipped on the right)
        if ns.ART then W, TW = 760, 228 end
        local f = CreateFrame("Frame", "OasisInterests", UIParent)
        f:SetSize(W, 500)
        f:SetPoint("CENTER", 0, 30)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        -- 0.5.564: while nothing is chosen yet, a dark veil lies over everything else
        -- (Oasis window, topbar, game) - clicks beside it go nowhere, the window shakes briefly
        local veil = CreateFrame("Button", nil, UIParent)
        veil:SetAllPoints(UIParent)
        veil:SetFrameStrata("FULLSCREEN_DIALOG")
        veil:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
        veil:EnableMouse(true)
        veil:EnableMouseWheel(true)
        veil:SetScript("OnMouseWheel", function() end)
        veil.bg = veil:CreateTexture(nil, "BACKGROUND")
        veil.bg:SetAllPoints()
        veil.bg:SetColorTexture(0, 0, 0, 0.62)
        veil:Hide()
        veil:SetScript("OnClick", function()
            -- 0.6.156: short rejection sound with the shake (also without animation)
            if PlaySound and SOUNDKIT then
                local id = SOUNDKIT.IG_PLAYER_INVITE_DECLINE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
                if id then pcall(PlaySound, id) end
            end
            if not K.Tween or (ns.db and ns.db.settings.noAnim) then return end
            local p1, rel, p2, x0, y0 = f:GetPoint(1)
            K.Tween(f, 0.32, function(q)
                f:ClearAllPoints()
                f:SetPoint(p1, rel, p2, x0 + math.sin(q * math.pi * 6) * 8 * (1 - q), y0)
            end, function() f:ClearAllPoints() f:SetPoint(p1, rel, p2, x0, y0) end)
        end)
        f.veil = veil
        f:HookScript("OnShow", function()
            if InCombatLockdown and InCombatLockdown() then return end
            veil:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
            veil:SetAlpha(0)
            veil:Show()
            if K.Tween and not (ns.db and ns.db.settings.noAnim) then K.Tween(veil, 0.25, function(q) veil:SetAlpha(q) end) else veil:SetAlpha(1) end
        end)
        f:HookScript("OnHide", function() veil:Hide() end)
        -- never block the game in combat
        ns.On("PLAYER_REGEN_DISABLED", function() veil:Hide() end)
        -- Background: deep dark with a soft accent glow at the top left
        -- 0.6.122: rounded corners (glass surface like the cards); images reaching the edge are masked at the corners
        local RAD = 16
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.035, 0.035, 0.045, 0.97 }, { 1, 1, 1, 0.08 }, RAD)) then
            K.Fill(f, { 0.035, 0.035, 0.045, 0.97 })
            K.Border(f, { 1, 1, 1, 0.08 })
        end
        f.box = f.box or CreateFrame("Frame", nil, f)
        f.box:SetAllPoints(f)
        local function round(tex, corners) if K.RoundMask then pcall(K.RoundMask, tex, f.box, RAD, corners) end end
        -- 0.6.118: background image faint (only with guild module - image origin not clearly licensed)
        f.artTop = f:CreateTexture(nil, "ARTWORK", nil, -8)   -- 0.6.124: above the glass fill (was below it)
        f.artTop:SetPoint("TOPLEFT", 1, -1) f.artTop:SetPoint("RIGHT", -1, 0) f.artTop:SetPoint("BOTTOM", f, "CENTER")
        f.artBot = f:CreateTexture(nil, "ARTWORK", nil, -8)
        f.artBot:SetPoint("BOTTOMLEFT", 1, 1) f.artBot:SetPoint("RIGHT", -1, 0) f.artBot:SetPoint("TOP", f, "CENTER")
        for _, t in ipairs({ f.artTop, f.artBot }) do t:SetAlpha(0.11) t:Hide() end   -- 0.6.140: 11 % (20 % was too busy behind the tiles)
        -- 0.6.130: as a function - called directly on every open (new windows are already "visible",
        -- so the first call got no OnShow and the image was missing until the second open)
        function f:ApplyArt()
            if not ns.ART then return end
            local r = (f:GetWidth() or 660) / math.max(1, f:GetHeight() or 350) / 2   -- Image is 2:1
            local l, rr = 0, 1
            if r < 1 then l, rr = (1 - r) / 2, 1 - (1 - r) / 2 end
            f.artTop:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\updatebg")
            f.artBot:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\updatebg")
            pcall(f.artTop.SetTexCoord, f.artTop, l, rr, 0, 0.5)
            pcall(f.artBot.SetTexCoord, f.artBot, l, rr, 0.5, 1)
            if not f.artRound then
                f.artRound = true
                round(f.artTop, { "tl", "tr" })
                round(f.artBot, { "bl", "br" })
            end
            f.artTop:Show() f.artBot:Show()
            if not f.dots and K.DotGrid then f.dots = K.DotGrid(f, 0.04, 10) end
            -- 0.6.142: vignette - darken the image towards the edges (two halves because of at most 3 masks)
            if not f.vigTop then
                f.vigTop = f:CreateTexture(nil, "ARTWORK", nil, -7)
                f.vigTop:SetPoint("TOPLEFT", 1, -1) f.vigTop:SetPoint("RIGHT", -1, 0) f.vigTop:SetPoint("BOTTOM", f, "CENTER")
                f.vigBot = f:CreateTexture(nil, "ARTWORK", nil, -7)
                f.vigBot:SetPoint("BOTTOMLEFT", 1, 1) f.vigBot:SetPoint("RIGHT", -1, 0) f.vigBot:SetPoint("TOP", f, "CENTER")
                for i, t in ipairs({ f.vigTop, f.vigBot }) do
                    t:SetTexture(ns.MEDIA .. "vignette")
                    t:SetTexCoord(0, 1, i == 1 and 0 or 0.5, i == 1 and 0.5 or 1)
                    t:SetVertexColor(1, 1, 1, 0.85)
                end
                round(f.vigTop, { "tl", "tr" })
                round(f.vigBot, { "bl", "br" })
            end
        end
        f:HookScript("OnShow", function() pcall(f.ApplyArt, f) end)
        local glow = f:CreateTexture(nil, "BORDER")
        glow:SetPoint("TOPLEFT") glow:SetPoint("TOPRIGHT") glow:SetHeight(180)
        grad(glow, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.16 })
        round(glow, { "tl", "tr" })
        f.glowTex = glow
        local orb = f:CreateTexture(nil, "BORDER")
        orb:SetTexture(ns.MEDIA .. "softglow")
        orb:SetSize(420, 320)
        orb:SetPoint("TOPLEFT", 0, 0)
        orb:SetVertexColor(C.accent[1] * 0.16, C.accent[2] * 0.16, C.accent[3] * 0.16, 1)
        orb:SetBlendMode("ADD")
        if K.Embers then f.embers = K.Embers(f, { n = 26, col = C.accent, level = 1, size = 6, speed = 12, alpha = 0.7 }) end
        local top = f:CreateTexture(nil, "ARTWORK")
        top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(2)
        grad(top, "HORIZONTAL", { C.accent[1], C.accent[2], C.accent[3], 1 }, { C.accent[1], C.accent[2], C.accent[3], 0 })
        round(top, { "tl", "tr" })
        f.topTex = top
        -- 0.6.140: border - fine hairline, accent color at the top, fading out down the sides,
        -- plus a second light line 1 px inside (looks like cut glass)
        f.edges = {}
        local function edge(side)
            local t = f:CreateTexture(nil, "OVERLAY")
            t:SetWidth(1)
            if side == "L" then t:SetPoint("TOPLEFT", 0, -RAD) else t:SetPoint("TOPRIGHT", 0, -RAD) end
            t:SetPoint("BOTTOM", f, "CENTER", 0, -40)
            f.edges[#f.edges + 1] = t
            return t
        end
        f.edgeL, f.edgeR = edge("L"), edge("R")
        f.inner = f:CreateTexture(nil, "OVERLAY")
        f.inner:SetPoint("TOPLEFT", RAD, -3) f.inner:SetPoint("TOPRIGHT", -RAD, -3) f.inner:SetHeight(1)
        grad(f.inner, "HORIZONTAL", { 1, 1, 1, 0.10 }, { 1, 1, 1, 0 })
        f.bottomLine = f:CreateTexture(nil, "OVERLAY")
        f.bottomLine:SetPoint("BOTTOMLEFT", RAD, 0) f.bottomLine:SetPoint("BOTTOMRIGHT", -RAD, 0) f.bottomLine:SetHeight(1)
        function f:PaintEdges(ac)
            grad(self.edgeL, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.70 })
            grad(self.edgeR, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.25 })
            grad(self.bottomLine, "HORIZONTAL", { 1, 1, 1, 0.02 }, { 1, 1, 1, 0.07 })
        end
        f:PaintEdges(C.accent)
        -- 0.6.165: new decorative frame with shimmer like the main window - old lines stay created but off
        if K.FrameLines then
            f.frameLines = K.FrameLines(f, RAD)
            for _, t in ipairs({ f.topTex, f.edgeL, f.edgeR, f.inner, f.bottomLine }) do t:SetAlpha(0) end
        end
        -- 0.6.189: with guild module the same image frame as the main window (decorative lines then off)
        if ns.ART and K.ImageFrame then
            local ok, fr = pcall(K.ImageFrame, f, 0.3)
            if ok and fr then
                f.imageFrame = fr
                if K.ApplyFrameStyle then K.ApplyFrameStyle(f) end   -- 0.6.192: can be turned off
            end
        end

        -- 0.6.142: header centered - overline between two fading lines (like the separator below)
        f.eyebrow = K.Text(f, 10, C.accent)
        f.eyebrow:SetPoint("TOP", 0, -24)
        if f.eyebrow.SetSpacing then pcall(f.eyebrow.SetSpacing, f.eyebrow, 0) end
        f.ebL = f:CreateTexture(nil, "ARTWORK")
        f.ebL:SetHeight(1) f.ebL:SetWidth(70)
        f.ebL:SetPoint("RIGHT", f.eyebrow, "LEFT", -12, 0)
        f.ebR = f:CreateTexture(nil, "ARTWORK")
        f.ebR:SetHeight(1) f.ebR:SetWidth(70)
        f.ebR:SetPoint("LEFT", f.eyebrow, "RIGHT", 12, 0)
        f.title = K.Title(f, 26, C.text)
        f.title:SetPoint("TOP", f.eyebrow, "BOTTOM", 0, -10)
        f.sub = K.Text(f, 12, C.muted)
        f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
        f.sub:SetPoint("LEFT", 60, 0)
        f.sub:SetPoint("RIGHT", -60, 0)
        f.sub:SetWordWrap(true)
        f.sub:SetJustifyH("CENTER")
        f.close = K.CloseButton(f, function() f:Hide() end)
        f.close:SetPoint("TOPRIGHT", -12, -12)

        --------------------------------------------------------------------
        -- New version: large card "Wie bisher weitermachen" at the very top
        --------------------------------------------------------------------
        local a, b = C.accent, C.amber
        local hero = CreateFrame("Button", nil, f)
        hero:SetHeight(66)
        hero:SetPoint("TOPLEFT", 28, -118)
        hero:SetPoint("TOPRIGHT", -28, -118)
        if hero.SetClipsChildren then hero:SetClipsChildren(true) end
        hero.bg = K.Fill(hero, { 1, 1, 1, 0.03 })
        K.Border(hero, { a[1], a[2], a[3], 0.55 })
        hero.tint = hero:CreateTexture(nil, "BORDER")
        hero.tint:SetAllPoints()
        grad(hero.tint, "HORIZONTAL", { a[1], a[2], a[3], 0.34 }, { b[1], b[2], b[3], 0.08 })
        -- Light streak that moves across the card now and then
        hero.halo = hero:CreateTexture(nil, "ARTWORK", nil, 2)
        hero.halo:SetTexture(CIRCLE)
        hero.halo:SetSize(42, 42)
        hero.halo:SetPoint("CENTER", hero, "LEFT", 35, 0)
        hero.halo:SetVertexColor(a[1], a[2], a[3], 0.45)
        hero.icon = K.Glyph(hero, 22, ns.ICONS.home, { 1, 1, 1 })
        hero.icon:SetDrawLayer("ARTWORK", 3)
        hero.icon:SetPoint("CENTER", hero.halo, "CENTER")
        hero.t = K.Title(hero, 15, C.text)
        hero.t:SetPoint("BOTTOMLEFT", hero, "LEFT", 70, 1)
        hero.t:SetText(L["Continue as before"])
        hero.s = K.Text(hero, 11, C.muted)
        hero.s:SetPoint("TOPLEFT", hero, "LEFT", 70, -3)
        hero.s:SetPoint("RIGHT", -60, 0)
        hero.s:SetJustifyH("LEFT")
        hero.s:SetText(L["Your sections and settings stay exactly as they are."])
        hero.arrow = hero:CreateTexture(nil, "ARTWORK", nil, 3)
        hero.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        hero.arrow:SetSize(18, 18)
        hero.arrow:SetVertexColor(1, 1, 1, 0.8)
        hero:SetScript("OnClick", function()
            f:Hide()
            if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            K.Toast(L["Oasis is ready"], L["Everything as before."], C.mint)
        end)
        hero:SetScript("OnEnter", function(self) self.hover = true end)
        hero:SetScript("OnLeave", function(self) self.hover = nil end)
        -- 0.6.123: image button (text, icon and frame in the image) - only with guild module and German language,
        -- because the text in the image is German. Image 7:1, the button gets taller for it.
        hero.extra = 0
        -- 0.6.215: all languages - German with the text in the image, otherwise text-free version (Tools/make_start_keep_blank.py)
        -- and the translated text lies on top
        local de = ns.lang == "de" or (not ns.lang and GetLocale and GetLocale() == "deDE")
        hero.artFile = de and "start_keep" or "start_keep_blank"
        if ns.ART then
            hero.art = hero:CreateTexture(nil, "ARTWORK", nil, 4)
            hero.art:SetAllPoints()
            hero.art:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\" .. hero.artFile)
            hero.art:SetTexCoord(0, 1, 0, 1)
            for _, x in ipairs({ hero.bg, hero.tint, hero.halo, hero.icon, hero.arrow }) do x:Hide() end
            if de then hero.t:Hide() hero.s:Hide()
            else
                -- Text where it is in the German image (from ~19 % of the width), with shadow
                for _, fs in ipairs({ hero.t, hero.s }) do
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end
                    fs:SetDrawLayer("OVERLAY", 7)
                end
                hero.t:ClearAllPoints() hero.t:SetPoint("LEFT", hero, "LEFT", math.floor((W - 56) * 0.19), 9)
                hero.s:ClearAllPoints() hero.s:SetPoint("TOPLEFT", hero.t, "BOTTOMLEFT", 0, -6)
                hero.s:SetPoint("RIGHT", hero, "LEFT", math.floor((W - 56) * 0.70), 0)
                K.SetFontSafe(hero.t, K.FONT_HEAD or K.FONT, 18, "", K.FONT)
                hero.t:SetTextColor(1, 0.96, 0.9)
                hero.s:SetTextColor(0.9, 0.85, 0.8)
            end
            hero.bg.Show = function() end
            K.SetBorderColor(hero, { 0, 0, 0, 0 })
            local H = math.floor((W - 56) / 7 + 0.5)
            hero.extra = H - 66
            hero:SetHeight(H)
        end
        f.hero, f.keep = hero, hero
        -- 0.6.143: instead of an outer glow the card itself pulses (image added once more on top),
        -- plus now and then a shimmer runs along the top and bottom edge
        if hero.art then
            hero.pulse = hero:CreateTexture(nil, "ARTWORK", nil, 5)
            hero.pulse:SetAllPoints(hero.art)
            hero.pulse:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\" .. hero.artFile)
            hero.pulse:SetBlendMode("ADD")
            hero.pulse:SetAlpha(0)
        end
        hero.edge = {}
        for _, side in ipairs({ "TOP", "BOTTOM" }) do
            for half = 1, 2 do
                local t = hero:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetSize(90, 3)
                t:SetBlendMode("ADD")
                t.side, t.half = side, half
                if half == 1 then grad(t, "HORIZONTAL", { 1, 1, 1, 0 }, { 1, 0.9, 0.75, 0.9 })
                else grad(t, "HORIZONTAL", { 1, 0.9, 0.75, 0.9 }, { 1, 1, 1, 0 }) end
                t:Hide()
                hero.edge[#hero.edge + 1] = t
            end
        end
        -- Separator "oder neu zusammenstellen"
        f.orLbl = K.Text(f, 10, C.dim)
        f.orLbl:SetPoint("TOP", hero, "BOTTOM", 0, -14)
        f.orLbl:SetText(K.Upper(L["or put together anew"]))
        f.orL = f:CreateTexture(nil, "ARTWORK")
        f.orL:SetHeight(1)
        f.orL:SetPoint("LEFT", hero, "LEFT", 0, 0)
        f.orL:SetPoint("RIGHT", f.orLbl, "LEFT", -12, 0)
        f.orL:SetPoint("TOP", f.orLbl, "CENTER", 0, 0)
        grad(f.orL, "HORIZONTAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.12 })
        f.orR = f:CreateTexture(nil, "ARTWORK")
        f.orR:SetHeight(1)
        f.orR:SetPoint("LEFT", f.orLbl, "RIGHT", 12, 0)
        f.orR:SetPoint("RIGHT", hero, "RIGHT", 0, 0)
        f.orR:SetPoint("TOP", f.orLbl, "CENTER", 0, 0)
        grad(f.orR, "HORIZONTAL", { 1, 1, 1, 0.12 }, { 1, 1, 1, 0 })

        --------------------------------------------------------------------
        -- Focus cards
        --------------------------------------------------------------------
        f.sel = {}
        f.tiles = {}
        local gridW = COLS * TW + (COLS - 1) * GAP
        local x0 = math.floor((W - gridW) / 2)
        for i, it in ipairs(D.INTERESTS) do
            local c = it.color
            local t = CreateFrame("Button", nil, f)
            t:SetSize(TW, TH)
            t.col, t.row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            t.bg = K.Fill(t, { 1, 1, 1, 0.035 })
            K.Border(t, { 1, 1, 1, 0.07 })
            -- Color glow from below (strong when selected)
            t.tint = t:CreateTexture(nil, "BORDER")
            t.tint:SetAllPoints()
            t.bar = t:CreateTexture(nil, "ARTWORK")
            t.bar:SetPoint("TOPLEFT", 1, -1) t.bar:SetPoint("TOPRIGHT", -1, -1) t.bar:SetHeight(2)
            t.bar:SetColorTexture(c[1], c[2], c[3], 1)
            -- Icon in the color circle (grows on hover)
            -- 0.6.119: image tile (frame, icon and scene in the image) - only with guild module
            if ns.ART then
                t.art = t:CreateTexture(nil, "BORDER", nil, -1)
                t.art:SetAllPoints()
                t.art:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\interest_" .. it.key .. "_clean")   -- 0.6.150: image without the old circle
                -- 0.6.142: circle badge as its own round graphic on top (Tools/make_interest_badges.py) -
                -- in the images the circles differ in size and are oval; this way all are equally round and large
                t.badge = t:CreateTexture(nil, "BORDER", nil, 0)
                t.badge:SetPoint("CENTER", t, "LEFT", 34, 0)
                t.badge:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\interest_" .. it.key .. "_badge")
                -- dark gradient behind the name (right of the icon) so the text stays readable
                t.shade = t:CreateTexture(nil, "BORDER", nil, 1)
                t.shade:SetPoint("TOPLEFT", t, "TOPLEFT", 4, -4)
                t.shade:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -4, 4)
                grad(t.shade, "HORIZONTAL", { 0, 0, 0, 0.0 }, { 0, 0, 0, 0.55 })
                t.bg:Hide()
            end
            t.halo = t:CreateTexture(nil, "ARTWORK")
            t.halo:SetTexture(CIRCLE)
            t.halo:SetSize(46, 46)
            t.halo:SetPoint("CENTER", t, "TOPLEFT", 37, -37)
            t.halo:SetVertexColor(c[1], c[2], c[3], 0.16)
            t.icon = K.Glyph(t, 26, ns.ICONS[it.icon] or ns.ICONS.home, c)
            t.icon:SetPoint("CENTER", t.halo, "CENTER")
            t.n = K.Title(t, 14, C.text)
            t.n:SetPoint("TOPLEFT", 16, -70)
            t.n:SetPoint("RIGHT", -12, 0)
            t.n:SetJustifyH("LEFT")
            t.n:SetText(L[it.text])
            t.s = K.Text(t, 10, C.dim)
            t.s:SetPoint("TOPLEFT", t.n, "BOTTOMLEFT", 0, -4)
            t.s:SetPoint("RIGHT", -12, 0)
            t.s:SetJustifyH("LEFT")
            t.s:SetJustifyV("TOP")
            t.s:SetWordWrap(true)
            t.s:SetHeight(28)
            t.s:SetText(L[it.sub])
            -- Check circle at the top right
            t.ring = t:CreateTexture(nil, "OVERLAY")
            t.ring:SetTexture(CIRCLE)
            t.ring:SetSize(20, 20)
            t.ring:SetPoint("CENTER", t, "TOPRIGHT", -22, -24)
            t.check = t:CreateTexture(nil, "OVERLAY", nil, 2)
            t.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            t.check:SetSize(14, 14)
            t.check:SetPoint("CENTER", t.ring, "CENTER")
            t.it = it
            -- add-on missing or switched off: tile greyed out; a click shows the download link or where to switch it on
            local ML = ns.ModuleLoader
            if not D.Available(it) then
                local st = ML and ML.PartState and ML.PartState(it.addon)
                t.s:SetText(st == "DISABLED" and L["Switched off - turn it on in the AddOn list (character screen)"]
                    or L["Not installed - click for the download link"])
                t:SetAlpha(0.45)
                t.unavail = st or "MISSING"
                if t.ring then t.ring:Hide() end
                if t.check then t.check:Hide() end
            end
            t:SetScript("OnClick", function(self)
                if self.unavail then
                    -- 0.6.588: info panel inside the start window (toasts and popups were hidden behind it)
                    if f.partInfo then f.partInfo:Open(self.it, self.unavail) end
                    return
                end
                f.sel[self.it.key] = not f.sel[self.it.key] or nil
                if f.sel[self.it.key] then self.pop = 0 end
                f:Mark()
                if PlaySound and SOUNDKIT then pcall(PlaySound, f.sel[self.it.key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
            end)
            t:SetScript("OnEnter", function(self) self.hover = true f:Mark() end)
            t:SetScript("OnLeave", function(self) self.hover = nil f:Mark() end)
            f.tiles[i] = t
        end
        -- compact (new version): flat, calm row cards - "Wie bisher" at the top stays the eye-catcher
        function f:Place(y0, compact)
            -- 0.6.123: a bit taller with image tiles so the name fits on two lines next to the badge
            local th = compact and (self.tiles[1] and self.tiles[1].art and 56 or 46) or TH
            local gap = compact and 8 or GAP
            self.compact = compact
            for _, t in ipairs(self.tiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", x0 + t.col * (TW + GAP), y0 - t.row * (th + gap))
                t:SetHeight(th)
                t.baseHalo, t.baseIcon = compact and 28 or 46, compact and 16 or 26
                t.halo:SetSize(t.baseHalo, t.baseHalo)
                t.icon:SetSize(t.baseIcon, t.baseIcon)
                t.halo:ClearAllPoints()
                t.n:ClearAllPoints()
                t.ring:ClearAllPoints()
                if t.art then
                    -- Badge always square (tile height), the image below fills the tile
                    t.badge:SetSize(th, th)
                    t.art:SetTexCoord(0, 1, 0, 1)
                    t.halo:Hide() t.icon:Hide()
                end
                if compact then
                    t.halo:SetPoint("CENTER", t, "LEFT", 24, 0)
                    -- Name to the right of the badge in the image (circle ends at a good 27 % of the image width)
                    t.n:SetPoint("LEFT", t, "LEFT", t.art and 66 or 46, 0)
                    t.n:SetPoint("RIGHT", -34, 0)
                    t.ring:SetPoint("CENTER", t, "RIGHT", -18, 0)
                    t.n:SetWordWrap(t.art and true or false)
                    if t.n.SetMaxLines then t.n:SetMaxLines(t.art and 2 or 1) end
                    t.nFont = t.nFont or { t.n:GetFont() }
                    if t.nFont[1] then pcall(t.n.SetFont, t.n, t.nFont[1], 12, t.nFont[3] or "") end
                    t.s:Hide()
                else
                    t.halo:SetPoint("CENTER", t, "TOPLEFT", 37, -37)
                    t.n:SetPoint("TOPLEFT", 16, -70)
                    t.n:SetPoint("RIGHT", -12, 0)
                    t.ring:SetPoint("CENTER", t, "TOPRIGHT", -22, -24)
                    if t.nFont and t.nFont[1] then pcall(t.n.SetFont, t.n, t.nFont[1], t.nFont[2] or 14, t.nFont[3] or "") end
                    t.s:Show()
                end
            end
            return th, gap
        end
        function f:Mark()
            local n = 0
            for _, t in ipairs(self.tiles) do
                if t.unavail then self.sel[t.it.key] = nil end   -- 0.6.587: missing/disabled add-on can not be chosen
                local on, c = self.sel[t.it.key], t.it.color
                if on then n = n + 1 end
                K.SetBorderColor(t, on and { c[1], c[2], c[3], 0.9 } or (t.hover and { c[1], c[2], c[3], 0.4 } or { 1, 1, 1, 0.07 }))
                t.bg:SetColorTexture(1, 1, 1, t.hover and 0.06 or 0.035)
                local tintA = self.compact and (on and 0.14 or (t.hover and 0.07 or 0)) or (on and 0.26 or (t.hover and 0.1 or 0))
                grad(t.tint, self.compact and "HORIZONTAL" or "VERTICAL", { c[1], c[2], c[3], tintA }, { c[1], c[2], c[3], 0 })
                if self.compact then K.SetBorderColor(t, on and { c[1], c[2], c[3], 0.55 } or (t.hover and { c[1], c[2], c[3], 0.3 } or { 1, 1, 1, 0.05 })) end
                -- 0.6.121: image tiles have their own frame - Oasis frame invisible
                if t.art then K.SetBorderColor(t, { 0, 0, 0, 0 }) end
                t.bar:SetShown(on and not t.art and true or false)
                if t.art then
                    t.art:SetAlpha(on and 1 or (t.hover and 0.85 or 0.55))
                    t.art:SetDesaturated(not on and not t.hover)
                    t.badge:SetAlpha(on and 1 or (t.hover and 0.85 or 0.55))
                    t.badge:SetDesaturated(not on and not t.hover)
                    t.shade:SetAlpha(on and 0.7 or 1)
                end
                t.halo:SetVertexColor(c[1], c[2], c[3], on and 0.32 or (t.hover and 0.22 or 0.14))
                t.icon:SetAlpha((on or t.hover) and 1 or 0.75)
                t.ring:SetVertexColor(on and c[1] or 1, on and c[2] or 1, on and c[3] or 1, on and 1 or 0.12)
                t.check:SetShown(on and true or false)
                t.n:SetTextColor(on and 1 or C.text[1], on and 1 or C.text[2], on and 1 or C.text[3])
            end
            self.count:SetText((L["%d of %d selected"]):format(n, #self.tiles))
            self.ok:SetEnabled(n > 0)
            if self.ok.SetLabel then self.ok:SetLabel(n > 0 and (L["Let's go (%d)"]):format(n) or L["Let's go"]) end
            if self.go then
                self.go.label:SetText(n > 0 and (L["Let's go (%d)"]):format(n) or L["Let's go"])
                self.go:SetAlpha(n > 0 and 1 or 0.5)
            end
        end

        --------------------------------------------------------------------
        -- Footer
        --------------------------------------------------------------------
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.06)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", 20, 64) line:SetPoint("BOTTOMRIGHT", -20, 64)
        f.count = K.Text(f, 11, C.muted)
        f.count:SetPoint("BOTTOMLEFT", 28, 32)
        -- 0.6.588/0.6.590: panel for a missing or switched-off add-on (inside the start window): what it brings,
        -- three steps and the download link - or switch it on and reload
        do
            local ML = ns.ModuleLoader
            local pi = CreateFrame("Frame", nil, f)
            pi:SetSize(520, 262)
            pi:SetPoint("CENTER", f, "CENTER", 0, -10)
            pi:SetFrameLevel(f:GetFrameLevel() + 40)
            pi:EnableMouse(true)
            pi.bg = K.Fill(pi, { 0.035, 0.035, 0.045, 0.98 })
            K.Border(pi, C.line)
            if K.ApplySkin then K.ApplySkin(pi, "panel", { 0.035, 0.035, 0.045, 0.98 }) end
            pi.bar = pi:CreateTexture(nil, "ARTWORK")
            pi.bar:SetPoint("TOPLEFT", 1, -1) pi.bar:SetPoint("TOPRIGHT", -1, -1) pi.bar:SetHeight(3)
            -- badge / icon
            pi.badge = pi:CreateTexture(nil, "ARTWORK")
            pi.badge:SetSize(64, 64)
            pi.badge:SetPoint("TOPLEFT", 22, -22)
            pi.icon = K.Glyph(pi, 30, ns.ICONS and ns.ICONS.home, C.text)
            pi.icon:SetPoint("CENTER", pi.badge, "CENTER")
            pi.kick = K.Text(pi, 10, C.dim)
            pi.kick:SetPoint("TOPLEFT", pi.badge, "TOPRIGHT", 16, -4)
            pi.kick:SetText(K.Upper and K.Upper(L["Optional add-on for OASIS"]) or L["Optional add-on for OASIS"])
            pi.h = K.Title(pi, 18, C.text)
            pi.h:SetPoint("TOPLEFT", pi.kick, "BOTTOMLEFT", 0, -4)
            pi.d = K.Text(pi, 12, C.muted)
            pi.d:SetPoint("TOPLEFT", pi.h, "BOTTOMLEFT", 0, -6)
            pi.d:SetPoint("RIGHT", pi, "RIGHT", -22, 0)
            pi.d:SetJustifyH("LEFT") pi.d:SetWordWrap(true)
            pi.line = pi:CreateTexture(nil, "ARTWORK")
            pi.line:SetColorTexture(1, 1, 1, 0.07)
            pi.line:SetHeight(1)
            pi.line:SetPoint("TOPLEFT", 22, -104) pi.line:SetPoint("TOPRIGHT", -22, -104)
            -- steps / state text
            pi.t = K.Text(pi, 12, C.text)
            pi.t:SetPoint("TOPLEFT", 22, -118)
            pi.t:SetPoint("RIGHT", pi, "RIGHT", -22, 0)
            pi.t:SetJustifyH("LEFT") pi.t:SetWordWrap(true) pi.t:SetSpacing(4)
            -- link field (Oasis input, read only)
            pi.lab = K.Text(pi, 10, C.dim)
            pi.lab:SetPoint("BOTTOMLEFT", 22, 84)
            pi.lab:SetText(K.Upper and K.Upper(L["Download link - Ctrl+C copies it"]) or L["Download link - Ctrl+C copies it"])
            pi.eb = K.Input(pi, 352, "")
            pi.eb:SetPoint("BOTTOMLEFT", 22, 52)
            pi.eb:SetHeight(26)
            pi.eb:SetScript("OnTextChanged", function(self, user) self.ph:Hide() if user and pi.url then self:SetText(pi.url) self:HighlightText() end end)
            pi.eb:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
            pi.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() pi:Hide() end)
            pi.sel = K.Button(pi, L["Select link"], 116, 26, "ghost", function() pi.eb:SetFocus() pi.eb:HighlightText() end)
            pi.sel:SetPoint("LEFT", pi.eb, "RIGHT", 8, 0)
            pi.btn = K.Button(pi, L["Turn on"], 150, 28, "primary", function()
                if pi.mode == "on" then
                    -- 0.6.601: also ends the test switch "only the base" (/oa nurbasis)
                    ns.db.settings.onlyBase = nil
                    if ML and ML.EnablePart then ML.EnablePart(pi.addon) end
                    pi.mode = "reload"
                    pi.btn:SetLabel(L["Reload now"])
                    pi.t:SetText(L["Switched on. It loads after a reload of the interface."])
                elseif pi.mode == "reload" then
                    if ReloadUI then ReloadUI() end
                end
            end)
            pi.btn:SetPoint("BOTTOMLEFT", 22, 16)
            pi.close = K.Button(pi, L["Close"], 110, 28, "ghost", function() pi:Hide() end)
            pi.close:SetPoint("BOTTOMRIGHT", -22, 16)
            pi:Hide()
            function pi:Open(it, state)
                local part = ML and ML.Part and ML.Part(it.addon)
                self.addon, self.url = it.addon, part and part.url
                local c = it.color or C.accent
                self.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
                if ns.ART then
                    self.badge:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\interest_" .. it.key .. "_badge")
                    self.badge:SetVertexColor(1, 1, 1) self.icon:Hide()
                else
                    self.badge:SetTexture(ns.MEDIA .. "dot") self.badge:SetVertexColor(c[1], c[2], c[3], 0.25)
                    if self.icon.SetTexture and ns.ICONS then self.icon:SetTexture(ns.ICONS[it.icon] or ns.ICONS.home) end
                    self.icon:Show()
                end
                self.h:SetText(part and part.title or L[it.text])
                self.d:SetText(L[it.sub] or "")
                -- installed, but hidden by the test switch "only the base": switch on here as well
                local ex = C_AddOns and C_AddOns.DoesAddOnExist
                local installed = ex and select(2, pcall(ex, it.addon)) == true
                local testMode = ns.db.settings.onlyBase and installed
                if state == "DISABLED" or testMode then
                    self.mode = "on"
                    self.t:SetText(testMode and L["Installed, but the test switch \"only the base\" is on. Switch it on here - it is there after a reload."]
                        or L["This add-on is installed but switched off in the AddOn list. Switch it on here - it is there after a reload."])
                    self.btn:SetLabel(L["Turn on"]) self.btn:Show()
                    self.lab:Hide() self.eb:Hide() self.sel:Hide()
                else
                    self.mode = nil
                    self.t:SetText("|cffd8d8d8" .. L["1.  Copy the link and open it in your browser"] .. "\n" .. L["2.  Download and unpack it into Interface/AddOns"] .. "\n" .. L["3.  Restart the game - the area appears by itself"] .. "|r")
                    self.btn:Hide()
                    self.lab:Show() self.sel:Show()
                    self.eb:SetText(self.url or "") self.eb:Show() self.eb:SetCursorPosition(0)
                    self.eb:SetFocus() self.eb:HighlightText()
                end
                self:Show()
            end
            f.partInfo = pi
        end
        f.ok = K.Button(f, L["Let's go"], 120, 26, "ghost", function()
            D.ApplyInterests(f.sel)
            f:Hide()
            if ns.ShowPage then pcall(ns.ShowPage, "home") end
            K.Toast(L["All set"], L["You can find more areas anytime under 'Discover'."], C.mint, function() ns.ShowPage("discover") end)
        end)
        f.ok:SetPoint("BOTTOMRIGHT", -24, 22)
        -- 0.6.125: image button at the bottom center (guild module) - own plain button made only of the image, the
        -- default button drew a surface and border around the semi-transparent edges
        if ns.ART then
            f.ok:Hide()
            f.ok.Show = function() end
            local g = CreateFrame("Button", nil, f)
            g:SetSize(216, 52)
            g:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
            g.art = g:CreateTexture(nil, "ARTWORK")
            g.art:SetAllPoints()
            g.art:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\start_go")
            g.label = K.Text(g, 12, { 1, 0.92, 0.85 }, "CENTER")
            g.label:SetPoint("CENTER", -10, 0)
            g:SetScript("OnClick", function() local fn = f.ok:GetScript("OnClick") if fn and f.ok:IsEnabled() then fn(f.ok, "LeftButton") end end)
            g:SetScript("OnEnter", function(self) if f.ok:IsEnabled() then self.art:SetAlpha(1) self.hl:Show() end end)
            g:SetScript("OnLeave", function(self) self.hl:Hide() end)
            g.hl = g:CreateTexture(nil, "ARTWORK", nil, 2)
            g.hl:SetAllPoints()
            g.hl:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\start_go")
            g.hl:SetBlendMode("ADD")
            g.hl:SetAlpha(0.25)
            g.hl:Hide()
            f.go = g
        end
        f.ok.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        K.SetBorderColor(f.ok, { C.accent[1], C.accent[2], C.accent[3], 0.55 })
        f.ok:HookScript("OnLeave", function(self)
            K.SetBorderColor(self, { C.accent[1], C.accent[2], C.accent[3], 0.55 })
            self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        end)
        f.all = textBtn(f, L["Turn all on"], 110, function()
            S().interestsDone = ns.now()
            -- really everything: including what "Nur das Noetigste" hid
            if ns.UpdateStart and ns.UpdateStart.AllOn then ns.UpdateStart.AllOn() else D.ShowAll() end
            f:Hide()
        end)
        if ns.ART then f.all:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 28) else f.all:SetPoint("RIGHT", f.ok, "LEFT", -12, 0) end
        f.min = textBtn(f, L["Essentials only"], 116, function()
            if ns.UpdateStart then ns.UpdateStart.Minimal() end
            S().interestsDone = ns.now()
            f:Hide()
            K.Toast(L["Oasis is ready"], L["Only the most important areas are on."], C.mint)
        end)
        f.min:SetPoint("RIGHT", f.all, "LEFT", -8, 0)
        f.never = K.Toggle(f, L["Don't ask again"], function() return S().updateAsk == false end,
            function(v) if v then S().updateAsk = false else S().updateAsk = nil end end)   -- 0.6.125: could not be turned off
        f.never:SetPoint("BOTTOMLEFT", 20, 28)
        f.never:SetWidth(150)
        f.never:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Don't ask again"], L["New versions will then simply start as before."] }) end)
        f.never:HookScript("OnLeave", function() GameTooltip:Hide() end)

        --------------------------------------------------------------------
        -- Motion: cards grow on hover, check mark pops, light streak over "Wie bisher"
        --------------------------------------------------------------------
        f.shT = 0
        f:SetScript("OnUpdate", function(self, el)
            if ns.db and ns.db.settings.noAnim then return end
            local k = math.min(1, el * 12)
            for _, t in ipairs(self.tiles) do
                local want = t.hover and 1 or 0
                local hv = t.hv or 0
                if hv ~= want then
                    hv = math.abs(want - hv) < 0.01 and want or hv + (want - hv) * k
                    t.hv = hv
                    local bh, bi = t.baseHalo or 46, t.baseIcon or 26
                    t.halo:SetSize(bh + bh * 0.17 * hv, bh + bh * 0.17 * hv)
                    t.icon:SetSize(bi + bi * 0.15 * hv, bi + bi * 0.15 * hv)
                end
                if t.pop then
                    t.pop = t.pop + el
                    local p = math.min(1, t.pop / 0.3)
                    local bump = math.sin(p * math.pi)
                    t.check:SetSize(14 * (0.3 + 0.7 * p) + 6 * bump, 14 * (0.3 + 0.7 * p) + 6 * bump)
                    t.ring:SetSize(20 + 8 * bump, 20 + 8 * bump)
                    if p >= 1 then t.pop = nil t.check:SetSize(14, 14) t.ring:SetSize(20, 20) end
                end
            end
            local h = self.hero
            if h:IsShown() then
                local want = h.hover and 1 or 0
                h.hv = (h.hv or 0) + (want - (h.hv or 0)) * k
                h.arrow:ClearAllPoints()
                h.arrow:SetPoint("RIGHT", h, "RIGHT", -22 + 6 * h.hv, 0)
                h.bg:SetColorTexture(1, 1, 1, 0.03 + 0.05 * h.hv)
                h.halo:SetSize(42 + 6 * h.hv, 42 + 6 * h.hv)
                h.arrow:SetVertexColor(1, 1, 1, 0.6 + 0.4 * h.hv)
                if h.art then h.art:SetAlpha(0.85 + 0.15 * h.hv) end
                -- like the cards below: grey as soon as something else is in focus (card selected or under the mouse),
                -- colored when the mouse is on "Wie bisher" or nothing is chosen yet
                local other = next(self.sel or {}) ~= nil
                for _, t in ipairs(self.tiles) do if t.hover then other = true break end end
                local wantDim = (other and not h.hover) and 1 or 0
                h.dim = (h.dim or 0) + (wantDim - (h.dim or 0)) * k
                if math.abs(h.dim - wantDim) < 0.01 then h.dim = wantDim end
                h:SetAlpha(1 - 0.4 * h.dim)
                local grey = h.dim > 0.5
                if h.art then h.art:SetDesaturated(grey or self.heroRed == false) end
                if h.pulse then h.pulse:SetDesaturated(grey or self.heroRed == false) end
                -- Pulsing: 3 s in and out, stronger on hover
                h.gT = ((h.gT or 0) + el) % 3
                if h.pulse then h.pulse:SetAlpha((0.5 - 0.5 * math.cos(h.gT / 3 * math.pi * 2)) * 0.22 + 0.10 * h.hv) end
                -- Shimmer along the edge: every 6 s, top to the right, bottom to the left (1.2 s)
                self.shT = (self.shT + el) % 6
                local p = self.shT / 1.2
                local wd = (h:GetWidth() or 600) - 40
                for _, t in ipairs(h.edge) do
                    if p < 1 then
                        local e = p * p * (3 - 2 * p)
                        local x = (t.side == "TOP") and (20 + e * wd) or (20 + (1 - e) * wd)
                        t:ClearAllPoints()
                        t:SetPoint(t.half == 1 and "RIGHT" or "LEFT", h, t.side .. "LEFT", x, t.side == "TOP" and -3 or 3)
                        t:SetAlpha(math.sin(p * math.pi))
                        t:Show()
                    else
                        t:Hide()
                    end
                end
            end
        end)
        -- 0.6.126: adapt colors to the chosen accent color on every open (the window is built only once)
        function f:Retint()
            local ac = C.accent
            grad(self.glowTex, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.16 })
            grad(self.topTex, "HORIZONTAL", { ac[1], ac[2], ac[3], 1 }, { ac[1], ac[2], ac[3], 0 })
            self:PaintEdges(ac)
            grad(self.ebL, "HORIZONTAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.6 })
            grad(self.ebR, "HORIZONTAL", { ac[1], ac[2], ac[3], 0.6 }, { ac[1], ac[2], ac[3], 0 })
            -- the images are painted red: original with a red accent color, otherwise desaturated in the accent color
            local red = ac[1] > 0.55 and ac[2] < 0.45 and ac[3] < 0.45
            self.heroRed = red
            local function paint(tex, boost)
                if not tex then return end
                tex:SetDesaturated(not red)
                if red then tex:SetVertexColor(1, 1, 1)
                else tex:SetVertexColor(math.min(1, ac[1] * boost), math.min(1, ac[2] * boost), math.min(1, ac[3] * boost)) end
            end
            paint(self.hero and self.hero.art, 1.6)
            paint(self.hero and self.hero.pulse, 1.6)
            paint(self.go and self.go.art, 1.6)
            paint(self.artTop, 1.4)
            paint(self.artBot, 1.4)
        end
        f:HookScript("OnShow", function(self) pcall(self.Retint, self) end)
        ns.EscClose("OasisInterests")
        pick = f
    end
    -- Display depending on occasion: first setup or new version
    local upd = mode == "update"
    pick.mode = mode
    pick.eyebrow:SetText(K.Upper(upd and ((L["Oasis %s is here"]):format(ns.version) .. ((ns.versionDate and ns.versionDate ~= "") and ("  ·  " .. ns.versionDate) or "")) or L["Welcome to Oasis"]))
    pick.title:SetText(upd and L["How do you want to start?"] or L["What are you interested in?"])
    pick.sub:SetText(upd and L["Pick focuses, turn everything on or keep things as they are - you can change it any time under 'Discover'."]
        or L["Oasis can do a lot. Pick what you want to use - the rest stays off for now and can be turned on anytime under 'Discover'."])
    for _, w in ipairs({ pick.hero, pick.orLbl, pick.orL, pick.orR, pick.min, pick.never }) do w:SetShown(upd) end
    pick.count:SetShown(not upd)
    -- Cards below "Wie bisher" or directly below the text; height to match
    local y0 = upd and (-222 - (pick.hero.extra or 0)) or -122
    local th, gap = pick:Place(y0, upd)
    pick:SetHeight(-y0 + 2 * th + gap + 88)
    if upd and pick.never.Refresh then pick.never:Refresh() end
    -- Preselection: previous choice or "Zusammen spielen" + "Leveln & Questen"
    pick.sel = {}
    local prev = S().interests
    if type(prev) == "table" and next(prev) then for k, v in pairs(prev) do pick.sel[k] = v end else pick.sel.group = true pick.sel.level = true end
    pick:Mark()
    pcall(pick.ApplyArt, pick)
    pcall(pick.Retint, pick)
    pick:Show()
    if pick.veil and not pick.veil:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
        pick.veil:SetFrameLevel(math.max(0, pick:GetFrameLevel() - 1))
        pick.veil:SetAlpha(1)
        pick.veil:Show()
    end
    pick:Raise()
    if K.FadeIn then pcall(K.FadeIn, pick, 0, 12) end
    if upd and K.FadeIn then pcall(K.FadeIn, pick.hero, 0.05, 10) end
    for i, t in ipairs(pick.tiles) do if K.FadeIn then pcall(K.FadeIn, t, (upd and 0.12 or 0) + 0.04 * i, 8) end end
end
ns.slash.interessen = function() D.ShowPicker() end

-- first window after install or update: choose interests (once, until a choice is made)
ns.Listen("LOGIN", function()
    S().dashSimple = nil   -- always the full start page
    if S().interestsDone then return end
    ns.After(6, function()
        if S().interestsDone or ns.inCombat() then return end
        D.ShowPicker()
    end)
end)

------------------------------------------------------------------------
-- Gradually: every 3 days a hidden section as a tip
------------------------------------------------------------------------
local HINT_EVERY = 3 * 86400
local function hint()
    local s = S()
    if not s.focusHidden or not next(s.focusHidden) then return end
    if s.hintLast and ns.now() - s.hintLast < HINT_EVERY then return end
    s.hinted = s.hinted or {}
    local cand = {}
    for _, d in ipairs(D.Pages()) do
        if s.focusHidden[d.key] and s.hiddenPages and s.hiddenPages[d.key] and not s.hinted[d.key] then cand[#cand + 1] = d end
    end
    if #cand == 0 then return end
    local d = cand[math.random(#cand)]
    s.hinted[d.key] = true
    s.hintLast = ns.now()
    K.Toast((L["Discovered yet? %s"]):format(L[d.title]), (d.sub and L[d.sub] or "") .. "  |cff66db9e" .. L["Click: turn on"] .. "|r", C.accent, function()
        D.Set(d.key, true)
        if ns.OpenMain then ns.OpenMain() end
        if ns.ShowPage then pcall(ns.ShowPage, d.key) end
    end)
end
ns.Listen("LOGIN", function()
    ns.After(120, function() if not ns.inCombat() then pcall(hint) end end)
end)

------------------------------------------------------------------------
-- Page "Entdecken"
------------------------------------------------------------------------
local filter = "all"
if ns.ICONS and not ns.ICONS.discover then ns.ICONS.discover = ns.ICONS.map end
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- small toggle (pill + knob): on = interest color, off = grey
local function switch(parent, onClick)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(30, 16)
    local function cap(point)
        local t = s:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE) t:SetSize(16, 16) t:SetPoint(point)
        return t
    end
    s.l, s.r = cap("LEFT"), cap("RIGHT")
    s.mid = s:CreateTexture(nil, "ARTWORK")
    s.mid:SetPoint("TOPLEFT", 8, 0) s.mid:SetPoint("BOTTOMRIGHT", -8, 0)
    s.knob = s:CreateTexture(nil, "OVERLAY")
    s.knob:SetTexture(CIRCLE) s.knob:SetSize(12, 12)
    function s:Set(on, col)
        local c = on and col or { 0.32, 0.32, 0.36 }
        for _, t in ipairs({ self.l, self.r }) do t:SetVertexColor(c[1], c[2], c[3], on and 0.9 or 1) end
        self.mid:SetColorTexture(c[1], c[2], c[3], on and 0.9 or 1)
        self.knob:SetVertexColor(1, 1, 1, on and 1 or 0.75)
        self.knob:ClearAllPoints()
        self.knob:SetPoint("CENTER", self, on and "RIGHT" or "LEFT", on and -8 or 8, 0)
    end
    s:SetScript("OnClick", onClick)
    return s
end

ns.RegisterPage({
    key = "discover", title = "Discover", order = 0.5,
    sub = "All Oasis areas at a glance - turn on what you need",
    build = function(p)
        p.seg = K.Segments(p, { { key = "all", text = L["All"] }, { key = "off", text = L["Still off"] }, { key = "on", text = L["Turned on"] } },
            function(k) filter = k ns.RefreshPage("discover") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.btnAll = K.Button(p, L["Turn everything on"], 140, 24, "ghost", function() D.ShowAll() end)
        p.btnAll:SetPoint("TOPRIGHT", 0, 0)
        p.btnPick = K.Button(p, L["Pick interests"], 140, 24, "ghost", function() D.ShowPicker() end)
        p.btnPick:SetPoint("RIGHT", p.btnAll, "LEFT", -8, 0)

        p.info = K.Text(p, 11, C.muted)
        p.info:SetPoint("TOPLEFT", 0, -36)
        p.info:SetPoint("RIGHT", p, "RIGHT", 0, 0)

        -- Card: icon | title + toggle | description (2 lines, full width)
        local function card(row)
            local c = CreateFrame("Button", nil, row)
            c:SetSize(220, 70)
            c.bg = K.Fill(c, C.panel)
            K.Border(c, C.line)
            if K.ApplySkin then K.ApplySkin(c, "panel", C.panel) end
            c.hl = c:CreateTexture(nil, "HIGHLIGHT")
            c.hl:SetPoint("TOPLEFT", 2, -2) c.hl:SetPoint("BOTTOMRIGHT", -2, 2)
            c.hl:SetColorTexture(1, 1, 1, 0.035)
            c.icon = K.Glyph(c, 20, nil)
            c.icon:SetPoint("TOPLEFT", 12, -11)
            c.n = K.Title(c, 13, C.text)
            c.n:SetPoint("LEFT", c.icon, "RIGHT", 9, 0)
            c.n:SetPoint("RIGHT", -50, 0)
            c.n:SetWordWrap(false)
            c.s = K.Text(c, 10, C.muted)
            c.s:SetPoint("TOPLEFT", 12, -37)
            c.s:SetPoint("RIGHT", -12, 0)
            c.s:SetWordWrap(true)
            if c.s.SetMaxLines then c.s:SetMaxLines(2) end
            c.sw = switch(c, function()
                local d = c.d
                if d then D.Set(d.key, not D.IsOn(d.key)) end
            end)
            c.sw:SetPoint("TOPRIGHT", -12, -13)
            c.sw:SetScript("OnEnter", function(self)
                local d = c.d
                if d then K.ShowTip(self, { L[d.title], D.IsOn(d.key) and L["Click: hide"] or L["Click: turn on"] }) end
            end)
            c.sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
            c:SetScript("OnClick", function(self)
                if not self.d then return end
                -- disabled section: click turns it on, enabled: open it
                if D.IsOn(self.d.key) then ns.ShowPage(self.d.key) else D.Set(self.d.key, true) end
            end)
            return c
        end
        local function fill(c, d, col)
            c.d = d
            if not d then c:Hide() return end
            c:Show()
            local on = D.IsOn(d.key)
            local it = interestOf[d.key]
            c.icon:SetTexture((ns.ICONS and (ns.ICONS[d.key] or (it and ns.ICONS[it.icon]))) or nil)
            local ic = on and col or C.dim
            c.icon:SetVertexColor(ic[1], ic[2], ic[3])
            c.n:SetText(L[d.title])
            local tc = on and C.text or C.muted
            c.n:SetTextColor(tc[1], tc[2], tc[3])
            c.s:SetText(d.sub and L[d.sub] or "")
            c.s:SetAlpha(on and 1 or 0.7)
            c.sw:Set(on, col)
        end
        -- Scroll area with free height: group header (28) + card rows (80)
        local sf = CreateFrame("ScrollFrame", nil, p)
        sf:SetPoint("TOPLEFT", 0, -58)
        sf:SetPoint("BOTTOMRIGHT", 0, 0)
        sf:EnableMouseWheel(true)
        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(700, 10)
        sf:SetScrollChild(content)
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 48)))
        end)
        sf:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w or 700) if p:IsShown() then ns.RefreshPage("discover") end end)
        p.sf, p.content = sf, content
        p.cards, p.heads = {}, {}
        function p:Card(i)
            local c = self.cards[i]
            if not c then c = card(content) self.cards[i] = c end
            return c
        end
        function p:Head(i)
            local h = self.heads[i]
            if not h then
                h = CreateFrame("Frame", nil, content)
                h:SetHeight(28)
                h.dot = h:CreateTexture(nil, "ARTWORK")
                h.dot:SetTexture(CIRCLE) h.dot:SetSize(7, 7)
                h.dot:SetPoint("LEFT", 2, -2)
                h.t = K.Text(h, 12, C.text)
                h.t:SetPoint("LEFT", h.dot, "RIGHT", 7, 0)
                h.sub = K.Text(h, 10, C.dim)
                h.sub:SetPoint("LEFT", h.t, "RIGHT", 10, 0)
                h.line = h:CreateTexture(nil, "ARTWORK")
                h.line:SetHeight(1)
                h.line:SetPoint("LEFT", h.sub, "RIGHT", 10, 0)
                h.line:SetPoint("RIGHT", 0, -2)
                h.line:SetColorTexture(1, 1, 1, 0.07)
                self.heads[i] = h
            end
            return h
        end
        p.fill = fill
    end,
    refresh = function(p)
        p.seg:Select(filter)
        local all = D.Pages()
        local groups, gOrder, on = {}, {}, 0
        for _, d in ipairs(all) do
            local isOn = D.IsOn(d.key)
            if isOn then on = on + 1 end
            if filter == "all" or (filter == "on" and isOn) or (filter == "off" and not isOn) then
                local it = interestOf[d.key]
                local k = it and it.key or "_more"
                if not groups[k] then
                    groups[k] = { it = it, list = {} }
                    gOrder[#gOrder + 1] = k
                end
                table.insert(groups[k].list, d)
            end
        end
        -- Order as in the interests window, "Weitere" last
        local idx = {}
        for i, it in ipairs(D.INTERESTS) do idx[it.key] = i end
        table.sort(gOrder, function(a, b) return (idx[a] or 99) < (idx[b] or 99) end)
        local W = p.content:GetWidth() or 700
        if W < 100 then W = 700 end
        local cw = math.floor((W - 16) / 3)
        local y, ci, hi = 0, 0, 0
        for _, k in ipairs(gOrder) do
            local g = groups[k]
            table.sort(g.list, function(a, b) return L[a.title] < L[b.title] end)
            local col = g.it and g.it.color or C.muted
            local nOn = 0
            for _, d in ipairs(g.list) do if D.IsOn(d.key) then nOn = nOn + 1 end end
            hi = hi + 1
            local h = p:Head(hi)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
            h.dot:SetVertexColor(col[1], col[2], col[3])
            h.t:SetText(g.it and L[g.it.text] or L["More"])
            h.sub:SetText((L["%d of %d on"]):format(nOn, #g.list))
            h:Show()
            y = y + (hi == 1 and 28 or 30)
            for i, d in ipairs(g.list) do
                ci = ci + 1
                local c = p:Card(ci)
                local col3 = (i - 1) % 3
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", col3 * (cw + 8), -y)
                c:SetSize(cw, 72)
                p.fill(c, d, col)
                if col3 == 2 or i == #g.list then y = y + 80 end
            end
            y = y + 6
        end
        for i = ci + 1, #p.cards do p.cards[i]:Hide() end
        for i = hi + 1, #p.heads do p.heads[i]:Hide() end
        p.content:SetHeight(math.max(10, y))
        p.info:SetText((L["%d of %d areas turned on. Click a card to open it."]):format(on, #all))
    end,
})
-- 0.6.625: no longer in the sidebar (pages are switched on under Settings > Modules); the page stays reachable by link
-- if ns.NAV_GROUPS and ns.NAV_GROUPS[1] then table.insert(ns.NAV_GROUPS[1].pages, "discover") end

-- Replay the first start (for testing): reset onboarding, tour + interest picker as for new users.
-- Data is kept; afterwards show everything again with "Alles einschalten" (Discover).
ns.slash.erststart = function()
    local s = S()
    D.ShowAll()
    s.onboarded, s.interestsDone, s.interests, s.hinted, s.hintLast = nil, nil, nil, nil, nil
    ns.print(L["Replaying the first start - tour and interest selection like a new user."])
    D.ShowPicker()
end

-- Check sync: what was discarded, is anything still running, trigger a full sync
ns.slash.abgleich = function(arg)
    local St, Co = ns.Store, ns.Comm
    ns.print("|cffe8b44a" .. L["Sync"] .. "|r  " .. (L["last: %s"]):format(ns.db.meta.lastSync and ns.fmtDate(ns.db.meta.lastSync) or "-")
        .. "  ·  " .. (L["Send queue: %d"]):format(Co and Co.QueueSize and Co.QueueSize() or 0)
        .. "  ·  " .. (L["deferred: %d"]):format(St and St.HeldCount and St.HeldCount() or 0))
    local list = {}
    for k, n in pairs((St and St.rejectWhy) or {}) do list[#list + 1] = { k = k, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    if #list == 0 then ns.print("  " .. L["Nothing discarded."]) end
    local np = 0
    for _ in pairs(St.coll("polls")) do np = np + 1 end
    local hb = St.HeldByColl and St.HeldByColl() or {}
    local ht = {}
    for k, n in pairs(hb) do ht[#ht + 1] = k .. " " .. n end
    ns.print(("  Umfragen gespeichert: %d  ·  zurueckgestellt je Sammlung: %s"):format(np, #ht > 0 and table.concat(ht, ", ") or "-"))
    for i = 1, math.min(12, #list) do ns.print(("  %d x %s"):format(list[i].n, list[i].k)) end
    if tostring(arg or ""):lower():find("voll") and Co and Co.RequestSync then
        Co.RequestSync(true)
        if Co.PullImportant then ns.After(20, function() pcall(Co.PullImportant) end) end
        if ns.GuildChat and ns.GuildChat.RequestMissed then ns.GuildChat.RequestMissed(72) end
        ns.print("  " .. L["Full sync requested."])
    else
        ns.print("  |cff888888" .. L["/oa abgleich voll - fetch everything fresh from the guild"] .. "|r")
    end
end

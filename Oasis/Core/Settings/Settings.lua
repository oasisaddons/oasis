-- Oasis - settings (personal) with tabs
local ADDON, ns = ...
local resetButton   -- 0.6.180: forward declaration (assigned further down, used earlier)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm

local QUALITY = { [2] = "Green", [3] = "Blue", [4] = "Epic" }
local TABS = {
    { key = "quick", text = "Quick start" },
    { key = "general", text = "Window & minimap" },
    { key = "pages", text = "Pages" },
    { key = "look", text = "Theme" },
    { key = "tips", text = "Tooltips" },
    { key = "mapset", text = "Map" },
    { key = "toasts", text = "Notifications" },
    { key = "sound", text = "Sound" },
    { key = "char", text = "Main & alts" },
    { key = "status", text = "Status" },
    { key = "share", text = "Privacy" },
    { key = "lists", text = "Lists & map" },
}

local page
local compact
local function S() return ns.db.settings end
-- 0.6.596: settings that belong to an optional add-on are only shown while that add-on is loaded
local NEEDS = {
    whisperForward = "Oasis_Convenience", shareNodes = "Oasis_Convenience", mmCoords = "Oasis_Convenience", layerAsk = "Oasis_Convenience",
    mapDungeons = "Oasis_Convenience", mapDanger = "Oasis_Convenience", mapPoi = "Oasis_Convenience", mapQuestGivers = "Oasis_Convenience",
    mapTrails = "Oasis_Convenience", mapTrailsGuild = "Oasis_Convenience", trailSession = "Oasis_Convenience",
    rareShare = "Oasis_GroupsRaids", shareTrace = "Oasis_GroupsRaids", shareInstPos = "Oasis_GroupsRaids", shareCombat = "Oasis_GroupsRaids",
    wrShare = "Oasis_GroupsRaids", lkShare = "Oasis_GroupsRaids",
    shareTrade = "Oasis_Trade", wantsBagHint = "Oasis_Trade", tipReagent = "Oasis_Trade",
}
local NEEDS_PREFIX = { { "gather", "Oasis_Convenience" }, { "glimmer", "Oasis_Convenience" } }
function ns.SettingAvailable(key)
    if type(key) ~= "string" then return true end
    local addon = NEEDS[key]
    if not addon then
        for _, pf in ipairs(NEEDS_PREFIX) do if key:sub(1, #pf[1]) == pf[1] then addon = pf[2] break end end
    end
    if not addon then return true end
    local ML = ns.ModuleLoader
    if not (ML and ML.PartLoaded) then return true end
    return ML.PartLoaded(addon) and true or false
end
-- the rows of a settings list that can be shown ({ text, key, ... })
local function avail(list)
    local out = {}
    for _, o in ipairs(list or {}) do if ns.SettingAvailable(o[2]) then out[#out + 1] = o end end
    return out
end
ns.SettingsAvail = avail

-- small helpers for consistent forms
-- Remember headings: after building, every one not yet inside a card automatically gets
-- a glass card around itself and its content (0.5.554 - consistent design for other modules' pages too)
local secParents = setmetatable({}, { __mode = "k" })
local function section(p, text, x, y, w)
    local h = K.Header(p, text)
    h:SetPoint("TOPLEFT", x, y)
    h:SetWidth(w or 340)
    local d = K.Divider(p)
    d:SetPoint("TOPLEFT", x, y - 20)
    d:SetWidth(w or 340)
    p._secs = p._secs or {}
    p._secs[#p._secs + 1] = { h = h, d = d, x = x, y = y, w = w or 340 }
    secParents[p] = true
    return h
end
local function autoCards()
    for p in pairs(secParents) do
        if not p._carded and p:IsVisible() and p:GetTop() and p:GetLeft() then
            p._carded = true
            local top, left = p:GetTop(), p:GetLeft()
            local objs, cards = {}, {}
            for _, c in ipairs({ p:GetChildren() }) do
                if c._isCard then cards[#cards + 1] = c else objs[#objs + 1] = c end
            end
            for _, r in ipairs({ p:GetRegions() }) do objs[#objs + 1] = r end
            local function inCard(x, y)
                for _, c in ipairs(cards) do
                    local cl, ct = c:GetLeft(), c:GetTop()
                    if cl and ct then
                        local cx, cy = cl - left, ct - top
                        if x >= cx - 2 and x <= cx + c:GetWidth() and y <= cy + 2 and y >= cy - c:GetHeight() then return true end
                    end
                end
            end
            for _, sc in ipairs(p._secs or {}) do
                if not inCard(sc.x + 2, sc.y - 2) then
                    local nextY
                    for _, o in ipairs(p._secs) do
                        if o ~= sc and math.abs(o.x - sc.x) < 60 and o.y < sc.y and (not nextY or o.y > nextY) then nextY = o.y end
                    end
                    local low = sc.y - 26
                    for _, o in ipairs(objs) do
                        if o ~= sc.h and o ~= sc.d and o.IsShown and o:IsShown() and o.GetTop then
                            local ot, ol, ob = o:GetTop(), o:GetLeft(), o:GetBottom()
                            if ot and ol and ob then
                                local oy, ox = ot - top, ol - left
                                if ox >= sc.x - 8 and ox < sc.x + sc.w and oy <= sc.y - 8 and (not nextY or oy > nextY + 4) then
                                    local b = ob - top
                                    if b < low then low = b end
                                end
                            end
                        end
                    end
                    local c = CreateFrame("Frame", nil, p)
                    c._isCard = true
                    c:SetPoint("TOPLEFT", p, "TOPLEFT", sc.x - 14, sc.y + 12)
                    c:SetSize(sc.w + 28, (sc.y + 12) - (low - 14))
                    c:SetFrameLevel(math.max(1, p:GetFrameLevel() - 1))
                    local G = ns.Insta and ns.Insta.Glass
                    if not (G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 12)) then
                        K.Fill(c, { 1, 1, 1, 0.025 })
                        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
                    end
                    if sc.d then sc.d:Hide() end
                end
            end
        end
    end
end
local function note(p, text, x, y, w, color)
    local fs = K.Text(p, 11, color or C.dim)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(w or 340)
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    fs:SetText(text)
    return fs
end
-- Search index: every setting with its tab (for the search at the top right)
local INDEX = {}
local function indexAdd(label, frame, desc)
    if not page or not page.buildingTab then return end
    INDEX[#INDEX + 1] = { label = label, desc = desc, tab = page.buildingTab, frame = frame, area = page.buildingArea, settingKey = frame and frame.settingKey }
end
-- 0.6.113: on the summary pages and in the sections, the explanation is a grey subline directly under the
-- toggle (descInline); the layout adds the extra height DESC_H. Full text still on hover.
local DESC_H = 14
local descInline = false
-- 0.6.471: rarely used toggles - only visible with "Alle Optionen zeigen" (next to the search);
-- the others move up (compact or toggleList skips them)
-- 0.6.485: only toggles from toggle lists (tooltips, map) - on freely built pages (sound, design, window)
-- gaps remained or boxes overlapped
local ADV = {
    tipWanted = true, tipCrafters = true, tipBank = true, tipReagent = true, srTooltip = true, srTooltipGroupOnly = true,
    mapHeat = true, mapReveal = true,
}
local function advHidden(key) return ADV[key] and not (ns.db and ns.db.settings.setAll) end
local function toggle(p, x, y, label, key, desc, after, w)
    local t = K.Toggle(p, L[label], function() return S()[key] and true or false end, function(v)
        S()[key] = v
        if after then after(v) end
    end)
    t:SetPoint("TOPLEFT", x, y)
    t:SetWidth(w or 340)
    t.settingKey = key
    if advHidden(key) then
        t:Hide()
        -- 0.6.476: the box contracts after building and gets shorter (otherwise a gap remains)
        if p ~= page and p.SetHeight then p.advGap = true end
    end
    if desc and descInline then
        t.sub = K.Text(t, 10, C.dim)
        t.sub:SetPoint("TOPLEFT", t.lbl, "BOTTOMLEFT", 0, -3)
        t.sub:SetWidth(math.max(80, (w or 340) - 44))
        t.sub:SetJustifyH("LEFT")
        t.sub:SetWordWrap(false)
        t.sub:SetText(L[desc])
        t.hasSub = true
    end
    -- Explanation (full) on hover
    if desc then
        t.tipText = L[desc]
        if not t.hasSub then
            t.info = K.Text(t, 11, C.dim)
            t.info:SetPoint("LEFT", t.lbl, "RIGHT", 6, 0)
            t.info:SetText("|cff666666(?)|r")
        end
        t:HookScript("OnEnter", function(self) K.ShowTip(self, { L[label], self.tipText }) end)
        t:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    indexAdd(L[label], t, desc and L[desc])
    return t
end
-- move everything in the same frame below a toggle with subline down by DESC_H; returns the
-- total extra height. Toggles with noReflow (own grid) are skipped.
local function reflowDescs(fr)
    local ys = {}
    for _, c in ipairs({ fr:GetChildren() }) do
        if c.hasSub and not c.noReflow then
            local _, rel, _, _, y = c:GetPoint(1)
            if rel == fr and type(y) == "number" then ys[#ys + 1] = y end
        end
    end
    if #ys == 0 then return 0 end
    local objs = { fr:GetChildren() }
    for _, r in ipairs({ fr:GetRegions() }) do objs[#objs + 1] = r end
    for _, o in ipairs(objs) do
        local n = o.GetNumPoints and o:GetNumPoints() or 0
        if n > 0 then
            local pts, moved = {}, false
            for i = 1, n do
                local pt, rel, rp, x, y = o:GetPoint(i)
                if rel == fr and type(y) == "number" and rp and rp:find("^TOP") then
                    local sh = 0
                    for _, sy in ipairs(ys) do if y < sy - 1 then sh = sh + DESC_H end end
                    if sh > 0 then y = y - sh moved = true end
                end
                pts[i] = { pt, rel, rp, x, y }
            end
            if moved then
                o:ClearAllPoints()
                for _, q in ipairs(pts) do o:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
            end
        end
    end
    return #ys * DESC_H
end
local function rowLabel(p, text, x, y)
    local fs = K.Text(p, 13, C.text)
    fs:SetPoint("TOPLEFT", x, y - 3)
    fs:SetText(text)
    return fs
end

------------------------------------------------------------------------
-- General
------------------------------------------------------------------------
-- Card as background for a section (subtly set apart)
local function card(f, x, y, w, h)
    local c = CreateFrame("Frame", nil, f)
    c._isCard = true
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(w, h)
    c:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    -- 0.5.544: glass card (semi-transparent, rounded corners) - otherwise flat with border
    local G = ns.Insta and ns.Insta.Glass
    if G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 12) then
        c.glass = true
    else
        K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
    end
    local bar = c:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT") bar:SetPoint("TOPRIGHT") bar:SetHeight(2)
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    -- Design frames (Modern rund, Future Neon, Fantasy Bronze, Classic Blizzard ...)
    if c.glass then bar:Hide()
    elseif K.ApplySkin and K.ApplySkin(c, "panel", { C.panel[1], C.panel[2], C.panel[3], 0.55 }) then bar:Hide() end
    return c
end
-- Card with header (icon, title, short description) - 0.5.517
local function cardH(f, x, y, w, h, icon, title, sub, right)
    local c = card(f, x, y, w, h)
    if right then c:ClearAllPoints() c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y) end
    c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. icon, C.accent)
    c.ic:SetPoint("TOPLEFT", 14, -14)
    c.t = K.Title(c, 14, C.text)
    c.t:SetPoint("LEFT", c.ic, "RIGHT", 8, 0)
    c.t:SetText(title)
    if sub then
        c.s = K.Text(c, 10, C.dim)
        c.s:SetPoint("TOPLEFT", c.ic, "BOTTOMLEFT", 0, -6)
        c.s:SetPoint("RIGHT", -14, 0)
        c.s:SetJustifyH("LEFT")
        c.s:SetText(sub)
    end
    -- slight brightening while the mouse is over the card
    c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.025)
    c.hl:Hide()
    c.hl:SetAlpha(0)
    c.hl:Show()
    c:SetScript("OnUpdate", function(self, el)
        -- 0.5.722: check only 10x per second (previously every frame per card)
        self.hAcc = (self.hAcc or 0) + (el or 0)
        if self.hAcc < 0.1 then return end
        self.hAcc = 0
        local over = self:IsMouseOver()
        if over ~= self.over then
            self.over = over
            local anim = K.Tween and not S().noAnim
            if anim then
                local a0 = self.hl:GetAlpha()
                K.Tween(self.hl, 0.18, function(q) self.hl:SetAlpha(a0 + ((over and 1 or 0) - a0) * q) end)
                if over then
                    K.Tween(self.ic, 0.38, function(q)
                        local z = 16 + 5 * math.sin(q * math.pi) * (1 - q * 0.3)
                        self.ic:SetSize(z, z)
                    end, function() self.ic:SetSize(16, 16) end)
                end
            else
                self.hl:SetAlpha(over and 1 or 0)
            end
        end
    end)
    return c
end
-- 0.5.563: cards appear one after another on tab switch (background fades in, icon pops up)
local function staggerCards(fr)
    if not fr or S().noAnim or not K.Tween then return end
    local list = {}
    for _, c in ipairs({ fr:GetChildren() }) do
        if c._isCard and c:IsShown() and c:GetTop() then list[#list + 1] = c end
    end
    table.sort(list, function(a, b)
        local ta, tb = math.floor(a:GetTop() / 20), math.floor(b:GetTop() / 20)
        if ta ~= tb then return ta > tb end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    for i, c in ipairs(list) do
        c:SetAlpha(0)
        K.Tween(c, 0.28, function(q) c:SetAlpha(1 - (1 - q) * (1 - q)) end, function() c:SetAlpha(1) end, (i - 1) * 0.06)
        if c.ic then
            c.ic:SetSize(6, 6)
            K.Tween(c.ic, 0.34, function(q)
                local z = 6 + 10 * q + 4 * math.sin(q * math.pi)
                c.ic:SetSize(z, z)
            end, function() c.ic:SetSize(16, 16) end, (i - 1) * 0.06 + 0.08)
        end
    end
end
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local refreshSoundSpk
local function buildGeneral(f)
    -- General = the Oasis window itself (size, startup, behavior) + language + minimap button.
    -- Everything belonging to a section (chat, deathroll ...) is under Sections.
    f.noCompact = true
    local LX, SX = 14, 136     -- Label, slider (relative to the page; left column starts at 0)
    local RX = 376

    -- Window -------------------------------------------------------------
    -- 0.5.677: language as a row here (previously its own card), minimap card trimmed to its content
    cardH(f, 0, 0, 362, 196, "home", L["Window"], L["How Oasis starts - size and transparency are under Appearance"])
    rowLabel(f, L["On login"], LX, -60)
    f.openSeg = K.Segments(f, {
        { key = "auto", text = L["As last time"] }, { key = "always", text = L["Open"] }, { key = "never", text = L["Keep closed"] },
    }, function(k) S().openOnLogin = (k ~= "auto") and k or nil end)
    f.openSeg:SetPoint("TOPLEFT", SX, -58)
    indexAdd(L["On login"], f.openSeg, L["Open Oasis on login"])
    rowLabel(f, L["Start page"], LX, -94)
    f.startSeg = K.Segments(f, {
        { key = "home", text = L["Dashboard"] }, { key = "last", text = L["Last opened"] },
    }, function(k) S().startPage = (k == "last") and "last" or nil end)
    f.startSeg:SetPoint("TOPLEFT", SX, -92)
    indexAdd(L["Start page"], f.startSeg)
    local rp = K.Button(f, L["Reset position"], 160, 22, "ghost", function()
        if ns.ResetWindowPos then ns.ResetWindowPos() end
        K.Toast(L["Window"], L["Back in the middle of the screen."], C.mint)
    end)
    rp:SetPoint("TOPLEFT", LX, -164)
    -- Language (can also be switched at the top next to the crown)
    rowLabel(f, L["Language"], LX, -128)
    f.lang = K.Button(f, "", 200, 24, "ghost")
    f.lang.isDropdown = true
    f.lang:SetPoint("TOPLEFT", SX, -124)
    f.lang:SetScript("OnClick", function(self) ns.ShowLanguageMenu(self) end)
    indexAdd(L["Language"], f.lang)

    -- Behavior -----------------------------------------------------------
    cardH(f, 0, -210, 362, 176, "settings", L["Behaviour"], L["How the window behaves in game"])
    f.hideCombat = toggle(f, LX, -262, "Hide in combat", "hideInCombat", "The Oasis window disappears as soon as combat starts (Esc cannot close it in combat)", function() if f.reshow then f.reshow:Refresh() end end, 330)
    -- 0.5.596: show again afterwards (on) or keep closed (off)
    f.reshow = toggle(f, LX + 20, -290, "Show again after combat", "combatReshow", "On: the window comes back after combat. Off: it stays closed.", nil, 310)
    f.lockWin = toggle(f, LX, -318, "Lock window", "lockWindow", "The window can no longer be moved by accident", nil, 330)
    f.noAnim = toggle(f, LX, -346, "Reduce animations", "noAnim", "No fades or count-ups - everything appears instantly", nil, 330)

    -- Minimap button (with preview for dragging) -----------------------------
    cardH(f, RX, 0, 362, 400, "map", L["Minimap button"], L["Drag the button in the preview or fine-tune below"], true)
    local MX = RX + 14
    if S().minimapBadge == nil then S().minimapBadge = true end
    local function place() if ns.PlaceMinimap then ns.PlaceMinimap() end end
    -- Preview: round minimap, button sits on the edge
    local pv = CreateFrame("Frame", nil, f)
    pv:SetSize(140, 140)
    pv:SetPoint("TOPLEFT", f, "TOPLEFT", MX, -58)
    pv:EnableMouse(true)
    pv.ring = pv:CreateTexture(nil, "BACKGROUND")
    pv.ring:SetTexture(CIRCLE) pv.ring:SetSize(104, 104) pv.ring:SetPoint("CENTER")
    pv.ring:SetVertexColor(C.accent[1] * 0.5, C.accent[2] * 0.5, C.accent[3] * 0.5, 0.55)
    pv.map = pv:CreateTexture(nil, "BORDER")
    pv.map:SetTexture(CIRCLE) pv.map:SetSize(98, 98) pv.map:SetPoint("CENTER")
    pv.map:SetVertexColor(0.09, 0.1, 0.12, 1)
    pv.me = pv:CreateTexture(nil, "ARTWORK")
    pv.me:SetTexture("Interface\\Minimap\\MinimapArrow") pv.me:SetSize(18, 18) pv.me:SetPoint("CENTER")
    pv.btn = CreateFrame("Frame", nil, pv)
    pv.btn:SetSize(22, 22)
    pv.btn.bg = pv.btn:CreateTexture(nil, "ARTWORK")
    pv.btn.bg:SetTexture(CIRCLE) pv.btn.bg:SetAllPoints() pv.btn.bg:SetVertexColor(0.05, 0.05, 0.06, 1)
    pv.btn.ic = pv.btn:CreateTexture(nil, "OVERLAY")
    pv.btn.ic:SetTexture(ns.MEDIA .. "logo64") pv.btn.ic:SetPoint("TOPLEFT", 3, -3) pv.btn.ic:SetPoint("BOTTOMRIGHT", -3, 3)
    pv.btn.glow = pv.btn:CreateTexture(nil, "BACKGROUND")
    pv.btn.glow:SetTexture(CIRCLE) pv.btn.glow:SetPoint("CENTER") pv.btn.glow:SetSize(30, 30)
    pv.btn.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
    pv.hint = K.Text(pv, 9, C.dim, "CENTER")
    pv.hint:SetPoint("TOP", pv, "BOTTOM", 0, 2)
    pv.hint:SetText(L["drag"])
    function pv:Update()
        local st = S()
        local a = math.rad(st.minimapAngle or 215)
        local r = 49 + (st.minimapDist or 5) * 0.75
        local sz = 22 * (st.minimapScale or 1)
        self.btn:SetSize(sz, sz)
        self.btn.glow:SetSize(sz + 8, sz + 8)
        self.btn:ClearAllPoints()
        self.btn:SetPoint("CENTER", self, "CENTER", math.cos(a) * r, math.sin(a) * r)
        self.btn:SetAlpha(st.minimap and 1 or 0.35)
    end
    -- Drag: angle from the mouse position (5-degree steps), minimap button moves along live
    pv:SetScript("OnMouseDown", function(self) self.drag = true end)
    pv:SetScript("OnMouseUp", function(self) self.drag = nil ns.RefreshPage("settings") end)
    pv:SetScript("OnUpdate", function(self, el)
        local over = self:IsMouseOver()
        self.pulse = (self.pulse or 0) + el
        self.btn.glow:SetAlpha((over or self.drag) and (0.55 + 0.25 * math.sin(self.pulse * 6)) or 0.35)
        if not self.drag then return end
        if S().minimapLock then return end
        local cx, cy = GetCursorPosition()
        local s = self:GetEffectiveScale()
        local mx, my = self:GetCenter()
        if not mx then return end
        local ang = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
        ang = math.floor(ang / 5 + 0.5) * 5 % 360
        if ang ~= S().minimapAngle then
            S().minimapAngle = ang
            place()
            self:Update()
            if f.mmAngle and f.mmAngle.Refresh then f.mmAngle:Refresh() end
        end
    end)
    pv:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Minimap button"], L["Click and drag: move the button around the minimap"] }) end)
    pv:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.mmPreview = pv
    -- Toggle to the right of the preview
    local TX = MX + 156
    f.t1 = toggle(f, TX, -62, "Show", "minimap", "Left-click opens Oasis, right-click the settings", function() ns.UpdateMinimapButton() pv:Update() end, 180)
    f.mmLock = toggle(f, TX, -92, "Lock", "minimapLock", "The button can no longer be dragged", nil, 180)
    f.mmBadge = toggle(f, TX, -122, "News counter", "minimapBadge", "Small number on the button when there is something new", function() if ns.UpdateNotify then ns.UpdateNotify() end end, 180)
    -- Fine-tuning
    rowLabel(f, L["Position"], MX, -226)
    f.mmAngle = K.Slider(f, 170, 0, 355, 5, function() return math.floor(((S().minimapAngle or 215) % 360) / 5 + 0.5) * 5 end,
        function(v) S().minimapAngle = v place() pv:Update() end, function(v) return v .. "°" end)
    f.mmAngle:SetPoint("TOPLEFT", MX + 130, -224)
    indexAdd(L["Position"], f.mmAngle, L["Minimap button"])
    rowLabel(f, L["Distance from edge"], MX, -258)
    f.mmDist = K.Slider(f, 170, -10, 25, 1, function() return S().minimapDist or 5 end,
        function(v) S().minimapDist = v place() pv:Update() end, function(v) return tostring(v) end)
    f.mmDist:SetPoint("TOPLEFT", MX + 130, -256)
    indexAdd(L["Distance from edge"], f.mmDist, L["Minimap button"])
    rowLabel(f, L["Size"], MX, -290)
    f.mmScale = K.Slider(f, 170, 0.6, 1.6, 0.05, function() return S().minimapScale or 1 end,
        function(v) S().minimapScale = v place() pv:Update() end, function(v) return (L["%d%%"]):format(v * 100 + 0.5) end)
    f.mmScale:SetPoint("TOPLEFT", MX + 130, -288)
    indexAdd(L["Size"], f.mmScale, L["Minimap button"])
    note(f, L["You can also drag the button around the minimap."], MX, -330, 330, C.dim)
    local mr = K.Button(f, L["Reset"], 120, 22, "ghost", function()
        S().minimapAngle, S().minimapDist, S().minimapScale = 215, 5, 1
        place()
        ns.RefreshPage("settings")
    end)
    mr:SetPoint("TOPLEFT", MX, -362)
end
local function refreshGeneral(f)
    if f.reshow then f.reshow:SetAlpha(S().hideInCombat and 1 or 0.4) end
    for _, x in ipairs({ f.hideCombat, f.reshow, f.noAnim, f.lockWin, f.t1, f.mmAngle, f.mmDist, f.mmScale, f.mmLock, f.mmBadge }) do x:Refresh() end
    f.openSeg:Select(S().openOnLogin or "auto")
    f.startSeg:Select(S().startPage == "last" and "last" or "home")
    if f.mmPreview then f.mmPreview:Update() end
    local l = ns.langByKey[ns.lang]
    local auto = (S().lang or "auto") == "auto"
    f.lang:SetLabel("|T" .. ns.MEDIA .. "flags\\" .. l.flag .. ":12:16:0:0:64:64:0:64:0:48|t  " .. (auto and (L["Like the game"] .. " (" .. l.name .. ")") or l.name))
    K.SetFontSafe(f.lang.label, K.fontByKey[l.cjk or "ptsans"].path, 12, "")
end

------------------------------------------------------------------------
-- Sections: each navigation section via a picker at the top, with its settings
------------------------------------------------------------------------
-- Settings per section (same toggles as in the other tabs, just collected here)
local function updPins() if ns.Map and ns.Map.UpdateWorldPins then ns.Map.UpdateWorldPins() end end
local PAGE_OPTS = {
    chat = {
        { "Show emojis in chat", "chatEmoji", ":lol: or <3 becomes a picture – everyone with Oasis sees it" },
        { "Emoji button in the input box", "emojiButton", "Small face on the right of the chat input box", function() if ns.Emoji then ns.Emoji.UpdateButtons() end end },
        { "Offer whispers to offline characters to their alt", "whisperForward", "If the character you whispered is offline and an alt of the same player is online, Oasis offers to send the message there - it is only sent after your click." },
        emojiPicker = true,
    },
    radar = {
        { "Clear default sound for online notices", "entranceLoud", "Two-tone instead of a short blip when the person has not picked an online sound", nil, true },
        inactive = true, listDark = true,
    },
    deathroll = { { "Deathroll leise wuerfeln", "drSilent", "Unter Oasis-Spielern fair per Addon statt /roll - nichts im Chat" } },
    raid = { lootQuality = true },
}
-- other modules can register their own section settings: build(frame, y) -> new y
local PAGE_EXTRA = {}
-- Subpages (no own navigation entry) -> their settings appear under the main section
local AREA_CHILDREN = { insta = { "life" } }
-- Sections whose tooltip/map toggles now live under Tooltips & Map: { tab, button text }
-- Paths to the summary pages: sections only show their own toggles; tooltip, map, notice, sound and
-- sharing toggles are collected (0.6.112: notices and sharing no longer duplicated in the sections either)
local LK = {
    map = { "mapset", "Map and minimap settings" }, tips = { "tips", "Tooltip line settings" },
    toast = { "toasts", "Turn notifications on and off" }, share = { "share", "Sharing and privacy" },
    sound = { "sound", "Online sound and display" },
}
local AREA_LINKS = {
    radar = { LK.map, LK.toast, LK.sound }, map = { LK.map }, deaths = { LK.map, LK.toast },
    wants = { LK.tips, LK.toast }, crafting = { LK.tips, LK.toast }, bank = { LK.tips }, raid = { LK.tips },
    allies = { LK.tips, LK.share }, chat = { LK.tips, LK.sound }, groups = { LK.toast }, legacy = { LK.toast },
    chronicle = { LK.toast, LK.share }, polls = { LK.toast }, camp = { LK.toast, LK.share }, deathroll = { LK.toast },
    trade = { LK.share }, insta = { LK.share },
}
function ns.AddPageSettings(key, build) PAGE_EXTRA[key] = build end
-- 0.6.289: modules attach their own toggles to an existing section (e.g. Discord to "chat"), regardless of the
-- order it is loaded in - previously DiscordBridge.lua had to come before this file for that
function ns.AppendPageSettings(key, build)
    local prev = PAGE_EXTRA[key]
    PAGE_EXTRA[key] = function(det, y)
        local ny = y
        if prev then ny = prev(det, y) if type(ny) ~= "number" then ny = y end end
        local ok, r = pcall(build, det, ny)
        return (ok and type(r) == "number") and r or ny
    end
end

-- Section "Profil": what everyone sets for themselves (about me, visibility, rewards)
local function sendProfile() if ns.Radar and ns.Radar.SendHello then ns.After(0.5, function() pcall(ns.Radar.SendHello) end) end end
-- Picker button with image preview; click opens tiles (unlocked + locked with rank)
local DICE = "Interface\\Icons\\INV_Misc_Dice_01"
local function rewardVisual(kind, r)
    if kind == "dice" then return DICE, r and r.color or { 1, 1, 1 }, false end
    if kind == "theme" then return nil, r and K.FromHex(r.hex) or C.accent, true end
    return ns.MEDIA .. "icons\\speaker", r and C.text or C.muted, false
end
local function rewardPicker(parent, kind, x, y, label, get, set)
    rowLabel(parent, L[label], x, y)
    local b = K.Button(parent, "", 220, 28, "ghost")
    b.isDropdown = true
    b.img = b:CreateTexture(nil, "ARTWORK")
    b.img:SetSize(20, 20)
    b.img:SetPoint("LEFT", 6, 0)
    b.label:ClearAllPoints() b.label:SetPoint("LEFT", 34, 0) b.label:SetPoint("RIGHT", -20, 0) b.label:SetJustifyH("LEFT")
    b.arrow = K.Text(b, 10, C.dim, "RIGHT") b.arrow:SetPoint("RIGHT", -8, 0) b.arrow:SetText("v")
    b:SetPoint("TOPLEFT", x + 150, y + 6)
    local RW = ns.Rewards
    local function short(r) return (L[r.name]:gsub("^[^:]+: ", "")) end
    function b:Update()
        local cur = get()
        local r = cur and RW and RW.byKey[kind .. ":" .. cur]
        local icon, col, round = rewardVisual(kind, r)
        self.img:SetTexCoord(0, 1, 0, 1)
        if icon then
            self.img:SetTexture(icon)
            if icon:find("Icons\\") then self.img:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        else
            self.img:SetTexture(round and "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" or "Interface\\Buttons\\WHITE8X8")
        end
        self.img:SetVertexColor(col[1], col[2], col[3])
        self.label:SetText(r and short(r) or ("|cff999999" .. L["Default"] .. "|r"))
    end
    b:SetScript("OnClick", function(self)
        local lvl = ns.Rank and ns.Rank.Mine() and ns.Rank.Mine().level or 1
        local cur = get()
        local items = {}
        do
            local icon, col, round = rewardVisual(kind, nil)
            if kind == "theme" then col = ns.Admin and ns.Admin.GuildAccentColor() or C.accent end
            items[1] = { key = false, text = L["Default"], icon = icon, color = col, round = round, checked = cur == nil }
        end
        for _, r in ipairs(RW and RW.LIST or {}) do
            if r.kind == kind then
                local icon, col, round = rewardVisual(kind, r)
                local key = r.key
                items[#items + 1] = { key = key, text = short(r), icon = icon, color = col, round = round, checked = cur == key,
                    locked = lvl < r.lvl and (L["Rank %d"]):format(r.lvl) or nil,
                    onEnter = function(tile)
                        if kind == "sound" and ns.Sound then ns.Sound.PlayChoice(key) end
                        K.ShowTip(tile, { L[r.name], L[r.desc or ""], lvl < r.lvl and ("|cffe8b44a" .. (L["From Oasis rank %d"]):format(r.lvl) .. "|r") or nil })
                    end }
            end
        end
        K.TilePicker(self, L[label], items, function(k)
            set(k or nil)
            self:Update()
        end)
    end)
    b:Update()
    return b
end
-- Section "Abzeichen": notices, chronicle, guild chat, showcase (up to 4 favorite badges on the profile card)
ns.AddPageSettings("badges", function(det, y)
    local s = S()
    local B = ns.Badges
    det.t[#det.t + 1] = (function()
        local t = K.Toggle(det, L["Notify me about new badges"], function()
            return not (S().toastOff and S().toastOff.badge)
        end, function(v)
            S().toastOff = S().toastOff or {}
            S().toastOff.badge = (not v) or nil
        end)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        return t
    end)()
    y = y - 32
    if s.badgeChronicle == nil then s.badgeChronicle = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Add new badges to the chronicle", "badgeChronicle", "The guild sees your achievements in the chronicle", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Celebrate gold badges in guild chat", "badgeAnnounce", "Posts a short line in guild chat for gold badges and guild titles", nil, 600)
    y = y - 40

    -- Showcase
    rowLabel(det, "|cffe8b44a" .. L["Your showcase"] .. "|r", 14, y)
    note(det, L["Your profile card shows these badges first - for you and the guild."], 150, y - 2, 450, C.dim)
    y = y - 34
    det.slots = {}
    local function mineList()
        local out = {}
        if not B then return out end
        for id, tier in pairs(B.Mine()) do
            local b = B.byId[id]
            if b and tier and tier > 0 then out[#out + 1] = { b = b, tier = tier } end
        end
        for id, holder in pairs(B.UniqueHolders()) do
            local me = ns.Alts and ns.Alts.MyMain() or ns.me()
            if (holder == me or ns.isMe(holder)) and B.byId[id] then out[#out + 1] = { b = B.byId[id], tier = 4 } end
        end
        table.sort(out, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.b.id < b.b.id end)
        return out
    end
    local function tierOf(id)
        for _, e in ipairs(mineList()) do if e.b.id == id then return e.tier end end
    end
    for i = 1, 4 do
        local slot = CreateFrame("Button", nil, det)
        slot:SetSize(64, 64)
        slot:SetPoint("TOPLEFT", 14 + (i - 1) * 74, y)
        slot.bg = K.Fill(slot, { 1, 1, 1, 0.03 })
        K.Border(slot, C.line)
        slot.em = B and B.Emblem(slot, 46)
        if slot.em then slot.em:SetPoint("CENTER") slot.em:EnableMouse(false) end
        slot.plus = K.Text(slot, 22, C.dim, "CENTER")
        slot.plus:SetPoint("CENTER")
        slot.plus:SetText("+")
        function slot:Update()
            local id = (S().badgeShowcase or {})[i]
            local tier = id and tierOf(id)
            if id and tier and B.byId[id] then
                self.em:Set(B.byId[id], tier) self.em:Show() self.plus:Hide()
                K.SetBorderColor(self, B.Color(tier))
            else
                if self.em then self.em:Hide() end
                self.plus:Show()
                K.SetBorderColor(self, C.line)
            end
        end
        slot:SetScript("OnEnter", function(self)
            local id = (S().badgeShowcase or {})[i]
            local b = id and B.byId[id]
            K.ShowTip(self, b and { B.Label(id, tierOf(id) or 1), L["Click: choose another badge"] } or { L["Empty slot"], L["Click: choose a badge"] })
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slot:SetScript("OnClick", function(self)
            local cur = (S().badgeShowcase or {})[i]
            local items = { { key = false, text = L["Empty"], icon = nil, color = { 0.25, 0.25, 0.28 }, round = true, checked = cur == nil } }
            for _, e in ipairs(mineList()) do
                local c = B.Color(e.tier)
                items[#items + 1] = { key = e.b.id, text = L[e.b.name], icon = e.b.wow or e.b.icon, color = e.b.wow and { 1, 1, 1 } or c,
                    checked = cur == e.b.id,
                    onEnter = function(tile) K.ShowTip(tile, { B.Label(e.b.id, e.tier), L[e.b.desc or ""] }) end }
            end
            if #items == 1 then items[2] = { key = false, text = L["No badges yet"], color = { 0.3, 0.3, 0.3 }, round = true, locked = " " } end
            K.TilePicker(self, (L["Showcase - slot %d"]):format(i), items, function(k)
                local sc = S().badgeShowcase or {}
                -- the same badge not twice
                for j = 1, 4 do if j ~= i and sc[j] == k then sc[j] = nil end end
                sc[i] = k or nil
                S().badgeShowcase = sc
                for _, sl in ipairs(det.slots) do sl:Update() end
                if ns.Radar and ns.Radar.SendHello then ns.After(0.5, function() pcall(ns.Radar.SendHello) end) end
            end)
        end)
        slot:Update()
        det.slots[i] = slot
    end
    y = y - 76
    return y - 10
end)

-- Section "Taschen & Twinks": bank placeholder (0.5.481)
ns.AddPageSettings("bags", function(det, y)
    -- 0.6.569: bank slots and action bars live in Oasis Convenience - no rows without that sub-addon
    if not (ns.BankSlots or ns.ActionBars) then return y end
    if S().bankGhosts == nil then S().bankGhosts = true end
    if ns.BankSlots then det.t[#det.t + 1] = toggle(det, 14, y, "Bank placeholders", "bankGhosts", "Bar above the bank: remember the layout, empty slots show a faded icon (Oasis moves nothing)",
        function() if ns.BankSlots then ns.BankSlots.Refresh() end end, 600)
    y = y - 32 end
    -- 0.6.521: save/load action bars (convenience module)
    if ns.ActionBars then
        y = y - 8
        rowLabel(det, "|cffe8b44a" .. L["Action bars"] .. "|r", 14, y)
        y = y - 28
        local name = K.Input(det, 160, L["Name, e.g. Raid"])
        name:SetPoint("TOPLEFT", 14, y)
        local sv = K.Button(det, L["Save"], 90, 24, "ghost", function() ns.ActionBars.Save(name:GetText()) end)
        sv:SetPoint("LEFT", name, "RIGHT", 8, 0)
        local ld
        ld = K.Button(det, L["Load …"], 90, 24, "ghost", function()
            local items = {}
            for _, n in ipairs(ns.ActionBars.Names()) do
                items[#items + 1] = { text = n, fn = function() ns.ActionBars.Load(n) end }
            end
            if #items == 0 then items[1] = { text = L["No bars saved yet."], fn = function() end } end
            K.ShowMenu(ld, items, L["Load action bars"])
        end)
        ld:SetPoint("LEFT", sv, "RIGHT", 6, 0)
        local del
        del = K.Button(det, L["Delete …"], 90, 24, "ghost", function()
            local items = {}
            for _, n in ipairs(ns.ActionBars.Names()) do items[#items + 1] = { text = n, fn = function() ns.ActionBars.Delete(n) end } end
            if #items > 0 then K.ShowMenu(del, items, L["Put out"]) end
        end)
        del:SetPoint("LEFT", ld, "RIGHT", 6, 0)
        y = y - 36
    end
    return y - 10
end)

-- Section "Chat": typing indicator, @ suggestions, mention sound, emoji size, muted people
ns.AddPageSettings("chat", function(det, y)
    -- Private tab (0.5.857)
    do
        local st = S()
        if st.wlGroupAlts == nil then st.wlGroupAlts = true end
        if st.wlOnlineBg == nil then st.wlOnlineBg = true end
        local function rf() ns.RefreshPage("chat") end
        det.t[#det.t + 1] = toggle(det, 14, y, "Private: alt conversations under the main", "wlGroupAlts", "Conversations with alts are nested under the conversation with their main", rf, 600)
        y = y - 30
        det.t[#det.t + 1] = toggle(det, 14, y, "Private: green background for who is online", "wlOnlineBg", "Green background for contacts who are online right now", rf, 600)
        y = y - 36
    end
    local s = S()
    if s.chatTyping == nil then s.chatTyping = true end
    if s.chatMentionSuggest == nil then s.chatMentionSuggest = true end
    if s.chatMentionSound == nil then s.chatMentionSound = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Show when someone is typing", "chatTyping", "Others will then also see when you are typing", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "@name suggestions in the normal chat", "chatMentionSuggest", "Typing @ suggests guild members (Tab completes)", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Sound on @mention", "chatMentionSound", "Short ping when someone mentions you in guild chat", nil, 600)
    y = y - 38
    rowLabel(det, L["Emoji size in chat"], 14, y - 2)
    det.esize = K.Slider(det, 180, 0, 32, 2, function() return tonumber(S().emojiChatSize) or 0 end,
        function(v) S().emojiChatSize = v if ns.GuildChat and ns.GuildChat.ClearRenderCache then ns.GuildChat.ClearRenderCache() end end,
        function(v) return v == 0 and L["automatic"] or (v .. " px") end,
        function() if ns.GuildChat and ns.GuildChat.ApplyLook then ns.GuildChat.ApplyLook() end end)
    det.esize:SetPoint("TOPLEFT", 184, y)
    y = y - 40
    -- Appearance: font, spacing, colors (same sliders as the gear in the chat)
    if ns.GuildChat and ns.GuildChat.BuildLook then
        local ok, ny = pcall(ns.GuildChat.BuildLook, det, y, { x = 14, width = 600 })
        if ok and type(ny) == "number" then y = ny - 6 end
    end
    -- Muted people
    rowLabel(det, "|cffe8b44a" .. L["Muted"] .. "|r", 14, y)
    y = y - 26
    det.muteBox = CreateFrame("Frame", nil, det)
    det.muteBox:SetPoint("TOPLEFT", 14, y)
    det.muteBox:SetSize(640, 28)
    det.muteChips = {}
    function det:UpdateMuted()
        for _, c in ipairs(self.muteChips) do c:Hide() end
        local names = {}
        for n, on in pairs(S().chatMuted or {}) do if on then names[#names + 1] = n end end
        table.sort(names)
        local x = 0
        for i, n in ipairs(names) do
            local c = self.muteChips[i]
            if not c then
                c = K.Button(self.muteBox, "", 100, 22, "ghost")
                self.muteChips[i] = c
            end
            c:SetLabel(ns.displayName(n) .. "  |cffff5a4ax|r")
            local w = math.min(180, (c.label:GetStringWidth() or 60) + 24)
            c:SetWidth(w)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x, 0)
            x = x + w + 6
            c:SetScript("OnClick", function()
                S().chatMuted[n] = nil
                self:UpdateMuted()
                if ns.GuildChat and ns.GuildChat.ClearRenderCache then ns.GuildChat.ClearRenderCache() end
            end)
            c:SetShown(x < 640)
        end
        if not self.muteEmpty then
            self.muteEmpty = K.Text(self.muteBox, 11, C.dim)
            self.muteEmpty:SetPoint("TOPLEFT", 0, -4)
            self.muteEmpty:SetText(L["Nobody. Mute someone by right-clicking a name in guild chat."])
        end
        self.muteEmpty:SetShown(#names == 0)
    end
    det:UpdateMuted()
    return y - 36
end)

-- Section "Mitglieder": notices, new marker, track playtime
ns.AddPageSettings("radar", function(det, y)
    local s = S()
    if s.trackPlay == nil then s.trackPlay = true end
    rowLabel(det, L["Mark as new"], 14, y - 2)
    det.newDays = K.Slider(det, 180, 3, 30, 1, function() return S().newDays or 14 end,
        function(v) S().newDays = v end, function(v) return (L["%d d"]):format(v) end)
    det.newDays:SetPoint("TOPLEFT", 184, y)
    y = y - 26
    note(det, L["How long new members show a green NEW."], 14, y, 600, C.dim)
    y = y - 30
    det.t[#det.t + 1] = toggle(det, 14, y, "Record play times", "trackPlay", "For 'usually online at' and level pace in the member list - stored only on your PC", nil, 600)
    return y - 36
end)

-- Section "Kampf-Rangliste": write the combat log file (default on) - basis for the crit import
ns.AddPageSettings("fight", function(det, y)
    local s = S()
    if s.cbAutoLog == nil then s.cbAutoLog = ns.GuildPack and true or false end   -- public version: off
    -- the log file is only useful with the crit import via OasisSync, which is not distributed - guild module only
    if ns.GuildPack then
        det.t[#det.t + 1] = toggle(det, 14, y, "Write combat log (/combatlog)", "cbAutoLog",
            "Turns on combat logging at login (like /combatlog). OasisSync reads group and dungeon crits from it.",
            function() if ns.CombatBoard and ns.CombatBoard.ApplyAutoLog then ns.CombatBoard.ApplyAutoLog() end end, 600)
        y = y - 30
    end
    if s.cbLiveCrit == nil then s.cbLiveCrit = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Count crits automatically when fighting alone", "cbLiveCrit",
        "Without a group and outside dungeons, every critical hit on your target counts for highest crit right away - no log file.", nil, 600)
    y = y - 30
    if s.cbGroupCrit == nil then s.cbGroupCrit = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Estimate crits in groups and dungeons", "cbGroupCrit",
        "In a group WoW does not tell addons who landed a hit. Oasis only counts a critical hit if it directly follows your own attack and matches the damage meter after the fight. Marked as estimated in the ranking.", nil, 600)
    return y - 36
end)

-- ==== Sections Play together / Raid / Trade / Guild & Fun ====
-- [A]
-- Group A (Play together): groups, social, allies, dungeons, buffs
-- Default = previous behavior (nil -> as before). Default-ON toggles are preset to true here.

-- Section "Gruppen"
ns.AddPageSettings("groups", function(det, y)
    local s = S()
    if s.lfgAccept == nil then s.lfgAccept = true end
    if s.lfgAuto == nil then s.lfgAuto = true end
    local function refreshGroups() ns.RefreshPage("groups") end
    rowLabel(det, "|cffe8b44a" .. L["Notifications"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Also notify about searches without a spot for my role", "lfgAllRoles", "Otherwise you are only notified when a spot for one of your roles is free", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Notices in dungeons and battlegrounds too", "lfgInInstance", "Otherwise new group searches stay silent inside instances", nil, 600)
    y = y - 40
    rowLabel(det, "|cffe8b44a" .. L["Automation"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Automatically accept invites to groups I requested", "lfgAccept", "Only from leaders you asked via Oasis", refreshGroups, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Auto-invite on my own search", "lfgAuto", "Default for new searches: requesters are invited right away instead of after a click", refreshGroups, 600)
    y = y - 32
    return y - 10
end)

-- Section "Gemeinsam questen"
ns.AddPageSettings("social", function(det, y)
    local s = S()
    if s.socialQuestHint == nil then s.socialQuestHint = true end
    local function refreshSocial() ns.RefreshPage("social") end
    det.t[#det.t + 1] = toggle(det, 14, y, "Notice when someone accepts the same quest", "socialQuestHint", "Clicking the notice invites that player to your group", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Group quests only", "socialGroupOnly", "List and notices only show quests meant for groups", refreshSocial, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Show completed quests in the list", "socialShowDone", "Also quests you only need to turn in (same as the Completed button on the page)", refreshSocial, 600)
    y = y - 32
    note(det, L["Whether others see your quests is set under Profile (Share my quests)."], 14, y, 600, C.dim)
    y = y - 28
    return y - 10
end)

-- Section "Spielerbuch" (shareRep is already above from PAGE_OPTS)
ns.AddPageSettings("allies", function(det, y)
    local s = S()
    for _, k in ipairs({ "allyRemember", "allyWarnWhisper", "allyWarnGroup", "allyWarnGuild", "allyTooltip" }) do
        if s[k] == nil then s[k] = true end
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Remember players from groups", "allyRemember", "Players outside the guild you grouped with go into the player book - stored only on your side", nil, 600)
    y = y - 32
    y = y - 8
    rowLabel(det, "|cffe8b44a" .. L["Warnings"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Warn when a badly rated player joins the group", "allyWarnGroup", nil, nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Warn when a badly rated player whispers you", "allyWarnWhisper", nil, nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Also warn based on guild ratings", "allyWarnGuild", "Off: only for players YOU marked as bad", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Dungeons"
ns.AddPageSettings("dungeons", function(det, y)
    local s = S()
    for _, k in ipairs({ "dgForYou", "dgDimUnfit", "dgMarkers", "dgPreload" }) do
        if s[k] == nil then s[k] = true end
    end
    local function refreshDg() ns.RefreshPage("dungeons") end
    rowLabel(det, L["Start filter"], 14, y - 2)
    det.dgFilter = K.Segments(det, {
        { key = "auto", text = L["Automatic"] },
        { key = "mine", text = L["For me"] },
        { key = "open", text = L["All open"] },
        { key = "all", text = L["All"] },
    }, function(k)
        S().dgFilter = (k ~= "auto") and k or nil
        if ns.Dungeons and ns.Dungeons.ResetFilter then ns.Dungeons.ResetFilter() end
    end)
    det.dgFilter:SetPoint("TOPLEFT", 184, y)
    det.dgFilter:Select(S().dgFilter or "auto")
    det.refreshers = det.refreshers or {}
    table.insert(det.refreshers, function() det.dgFilter:Select(S().dgFilter or "auto") end)
    y = y - 30
    note(det, L["Automatic: dungeons fitting your level, otherwise all open ones."], 14, y, 600, C.dim)
    y = y - 34
    rowLabel(det, "|cffe8b44a" .. L["Loot list"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Mark fitting loot as for you", "dgForYou", "Green tag on items with stats for your class", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Dim unusable loot", "dgDimUnfit", "Armor and weapons your class cannot use are faded", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Show wanted, guild bank and owned", "dgMarkers", "Extra line under each item: who wants it, how many are in the guild bank, whether you own it", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Preload loot in the background", "dgPreload", "After login all dungeon loot lists are read bit by bit (for tooltips) - takes effect on next login", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Buff-Monitor"
ns.AddPageSettings("buffs", function(det, y)
    local s = S()
    if s.buffCons == nil then s.buffCons = true end
    local function upd()
        if ns.BuffMonitor and ns.BuffMonitor.Update then ns.BuffMonitor.Update() end
        ns.RefreshPage("buffs")
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Show automatically when joining a group", "buffAuto", "The floating buff window opens as soon as you join a group", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Hide when leaving the group", "buffAutoHide", "Gone while solo - it comes back in your next group", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Lock window", "buffLock", "The floating window can no longer be moved by accident", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Check flasks, elixirs and food", "buffCons", "Off: class buffs only (Stamina, Intellect, Blessings ...)", upd, 600)
    y = y - 32
    return y - 10
end)
-- [B]
ns.AddPageSettings("raid", function(det, y)
    for _, k in ipairs({ "raidReminder", "raidNewEventToast", "raidWinToast", "lootHelper", "raidPointsPrompt" }) do
        if S()[k] == nil then S()[k] = true end
    end
    rowLabel(det, "|cffe8b44a" .. L["Notifications"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Reminder 15 min before my raids", "raidReminder", "Short notice when an event you signed up for (or created) is about to start", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify about new raid events", "raidNewEventToast", "Shows a notice as soon as a guildmate creates a new event", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify when I receive an item", "raidWinToast", "Notice during Oasis loot distribution when the item goes to you", nil, 600)
    y = y - 32
    rowLabel(det, "|cffe8b44a" .. L["As leader"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Distribution helper at the loot window", "lootHelper", "As leader, a list for distributing via Oasis appears next to the loot window", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Offer raid points on entering", "raidPointsPrompt", "As an officer, Oasis asks on entering a raid instance whether to start points", nil, 600)
    y = y - 32
    return y - 10
end)

-- [C]
-- Group C (Trade): crafting exchange, market, wish list, guild bank

-- Section "Handwerks-Boerse": notices, counter, tooltip
ns.AddPageSettings("crafting", function(det, y)
    local s = S()
    if s.craftStatusToasts == nil then s.craftStatusToasts = true end
    if s.craftBadge == nil then s.craftBadge = true end
    if s.tipCrafters == nil then s.tipCrafters = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Updates on my orders", "craftStatusToasts", "Accepted, done, declined or returned - a notice when your own orders change", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Open order count in the menu", "craftBadge", "Small number on the Crafting menu entry for orders you could craft",
        function() if ns.Crafting and ns.Crafting.UpdateBadge then ns.Crafting.UpdateBadge() end end, 600)
    y = y - 32
    return y - 10
end)

-- Section "Markt": wish list alert, price queries, trade balance (same toggles as on the market page)
ns.AddPageSettings("trade", function(det, y)
    local s = S()
    if s.wantAlarm == nil then s.wantAlarm = true end
    if s.priceAnswer == nil then s.priceAnswer = true end
    local function upd() ns.RefreshPage("trade") end
    det.t[#det.t + 1] = toggle(det, 14, y, "Wishlist alert", "wantAlarm", "If something from your wishlist is cheap in the AH, you get a notice - even if someone else scanned.", upd, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Answer price checks", "priceAnswer", "When someone types 'pc [item]' in guild chat, exactly one Oasis user answers with the price and 7-day low.", upd, 600)
    y = y - 32
    if _G.MidasDB then
        if s.midasAutoScan == nil then s.midasAutoScan = true end
        det.t[#det.t + 1] = toggle(det, 14, y, "Midas scans automatically", "midasAutoScan", "When you open the auction house, Midas starts its scan in the background (at most every 15 minutes, server limit).",
            function() upd() if ns.ApplyMidasAutoScan then ns.ApplyMidasAutoScan() end end, 600)
        y = y - 32
    end
    return y - 10
end)

-- Section "Wunschliste": notices, counter, tooltip, item suggestions
ns.AddPageSettings("wants", function(det, y)
    local s = S()
    for _, k in ipairs({ "wantsLootHint", "wantsBagHint", "wantsBadge", "tipOasis", "tipWanted", "itemSuggest", "wantsDungeonHint", "wantsGotHint", "tipReagent" }) do
        if s[k] == nil then s[k] = true end
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify when I loot something someone wants", "wantsLootHint", "If you loot an item a guild member is looking for, you get a notice to let them know", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify when my bags hold a wanted item", "wantsBagHint", "Someone added a wish and you carry the item", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "In dungeons, show which wishlist items drop here", "wantsDungeonHint", "On entering: your wishlist items and those of your guild group mates that drop in this dungeon", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Announce goal reached", "wantsGotHint", "When you loot an item from your wishlist, a notice appears (click to tick it off)", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Count in the menu when I can help", "wantsBadge", "Small number on the Wishlist menu entry",
        function() if ns.Wants and ns.Wants.UpdateBadge then ns.Wants.UpdateBadge() end end, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Item suggestions while typing", "itemSuggest", "While typing an item name, Oasis suggests matching items", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Gildenbank": scan/share, tooltip, start filter of the log
ns.AddPageSettings("bank", function(det, y)
    local s = S()
    if s.bankShareScan == nil then s.bankShareScan = true end
    if s.tipBank == nil then s.tipBank = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Read the guild bank for the guild", "bankShareScan", "When you open the guild vault, Oasis reads tabs, gold and log and shares them with the guild", nil, 600)
    y = y - 38
    rowLabel(det, L["Log shows first"], 14, y - 2)
    det.bankLog = K.Segments(det, { { key = "all", text = L["All"] }, { key = "items", text = L["Items"] },
        { key = "gold", text = L["Gold"] }, { key = "mine", text = L["Mine"] } }, function(k)
        S().bankLogFilter = (k ~= "all") and k or nil
    end)
    det.bankLog:SetPoint("TOPLEFT", 184, y)
    det.bankLog:Select(S().bankLogFilter or "all")
    det.refreshers = det.refreshers or {}
    table.insert(det.refreshers, function() det.bankLog:Select(S().bankLogFilter or "all") end)
    y = y - 32
    return y - 10
end)
-- [D]
-- Group D: chronicle, polls, campfire, deathroll, graveyard, legacy, map

-- Section "Chronik": notices, level notices, legacy posts
ns.AddPageSettings("chronicle", function(det, y)
    local s = S()
    if s.chrToastLevels == nil then s.chrToastLevels = true end
    if s.chrPostLegacy == nil then s.chrPostLegacy = true end
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify on others' level-ups", "chrToastLevels", "Off: no more notices when someone reaches a level - bosses and legacy stay", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Post completed legacy challenges in guild chat", "chrPostLegacy", "Only applies when posting milestones is on - off: only levels are posted", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Umfragen": new poll, result, counter
ns.AddPageSettings("polls", function(det, y)
    local s = S()
    if s.pollEndToast == nil then s.pollEndToast = true end
    if s.pollBadge == nil then s.pollBadge = true end
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Show the result when a poll ends", "pollEndToast", "Only for polls you started or voted in", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Count open polls in the navigation", "pollBadge", "Number on the menu item for polls you have not voted in yet",
        function() if ns.Polls and ns.Polls.UpdateBadge then ns.Polls.UpdateBadge() end end, 600)
    y = y - 32
    return y - 10
end)

-- Section "Gildenziele" (0.5.481)
ns.AddPageSettings("goals", function(det, y)
    if S().ggHint == nil then S().ggHint = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Notice for new guild goals", "ggHint", "Shows a notice as soon as someone creates a guild goal", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Lagerfeuer": others' notices, own zone only, own confirmation
ns.AddPageSettings("camp", function(det, y)
    local s = S()
    if s.campOwnToast == nil then s.campOwnToast = true end
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Only notify on campfires in my zone", "campZoneOnly", "Notices only when the fire burns in your current zone - the map still shows all", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Confirmation for my own campfire", "campOwnToast", "Short notice that the guild can see your fire", nil, 600)
    y = y - 32
    if s.campAuto == nil then s.campAuto = true end
    return y - 10
end)

-- Section "Deathroll": challenges, open invitations, move
ns.AddPageSettings("deathroll", function(det, y)
    local s = S()
    if s.drOpenInvites == nil then s.drOpenInvites = true end
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Notify on open guild game invites", "drOpenInvites", "Off: players looking for an opponent only show up on the Deathroll page", nil, 600)
    y = y - 32
    -- 0.6.213: cross-guild lobby via hidden channels (default on)
    if s.drNet == nil then s.drNet = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Find opponents outside the guild too", "drNet", "Hidden channel per stake level - players from other guilds appear quietly in the list", function(v)
        local DR = ns.Deathroll
        if DR then if v then DR.NetJoin(DR.inQueue and DR.inQueue.start or 100) else DR.NetLeave() end end
    end, 600)
    y = y - 32
    return y - 10
end)

-- Section "Friedhof": death notices, cause of death
ns.AddPageSettings("deaths", function(det, y)
    local s = S()
    if s.deathKiller == nil then s.deathKiller = true end
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Show cause of death in the notice", "deathKiller", "Off: the notice only shows name and location", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Legacy": companion searches
ns.AddPageSettings("legacy", function(det, y)
    rowLabel(det, "|cffe8b44a" .. L["Personal"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Also notify on searches for challenges I already finished", "legacyLfgDone", "Normally Oasis only notifies on searches you still have open yourself", nil, 600)
    y = y - 32
    return y - 10
end)

-- Section "Karte & Radar": further map layers, send interval
-- 0.6.113: map card in two columns and by topic (world map, collection map, icons, sending); explanation as subline
ns.AddPageSettings("map", function(det, y)
    det.t, det.refreshers = det.t or {}, det.refreshers or {}
    local function upd() if ns.Map then ns.Map.UpdateWorldPins() end end
    local function gupd() if ns.Gather then if ns.Gather.Refresh then ns.Gather.Refresh() else pcall(ns.Gather.DrawWorld) pcall(ns.Gather.DrawMinimap) end end end
    local function symUpd()
        if ns.Gather and ns.Gather.Refresh then ns.Gather.Refresh() end
        if ns.Map then pcall(ns.Map.UpdateMinimap) pcall(ns.Map.UpdateWorldPins) end
    end
    local function xupd() symUpd() if ns.MapExtras then ns.MapExtras.Redraw() end end
    -- two columns; row as tall as its tallest toggle (with or without subline)
    local function grid(list)
        list = avail(list)
        local was = descInline
        descInline = true
        for r = 0, math.ceil(#list / 2) - 1 do
            local tall = false
            for c = 1, 2 do
                local o = list[r * 2 + c]
                if o then
                    if o[5] and S()[o[2]] == nil then S()[o[2]] = true end
                    local t = toggle(det, 14 + (c - 1) * 370, y, o[1], o[2], o[3], o[4], 340)
                    t.noReflow = true
                    det.t[#det.t + 1] = t
                    det.rk = det.rk or {}
                    det.rk[#det.rk + 1] = { o[2], o[5] and true or nil }
                    if o[3] then tall = true end
                end
            end
            y = y - 32 - (tall and DESC_H or 0)
        end
        descInline = was
    end
    local function head(text) y = y - 6 rowLabel(det, "|cffe8b44a" .. L[text] .. "|r", 14, y) y = y - 28 end

    head("World map")
    if S().lfgPins == nil then S().lfgPins = true end
    grid({
        { "Level ranges on the world map", "mapLevels", "Shows the level range of each zone", upd },
        { "Death locations on the world map", "mapDeaths", "Guild skulls as an extra map layer", upd },
        { "Group searches at the dungeon entrance", "lfgPins", "Players looking for a group appear at the dungeon entrance", symUpd },
        { "Markers and notes", "mapMarkers", "Meeting points, warnings and notes on the world map and minimap", xupd, true },
        { "Dungeon entrances", "mapDungeons", "Entrances with level range and guild members in range", xupd, true },
        { "Danger zones", "mapDanger", "Red tint where several guild members died (7 days)", xupd },
        { "Vendors, repair, mailboxes and flight points", "mapPoi", "Places someone in the guild has already visited", xupd, true },
        { "Dungeon quest givers", "mapQuestGivers", "Where dungeon quests start in the open world", xupd },
        { "Own trail", "mapTrails", "Your path of the last 5 minutes as a thin line", xupd },
        { "Long trail: whole session", "trailSession", "Off = only the last 10 minutes of your route, older paths fade out", function() ns.db.settings.trailMinutes = ns.db.settings.trailSession and 0 or nil xupd() end },
        { "Other players' trails", "mapTrailsGuild", "Guild members' paths of the last 5 minutes (only those sharing their position)", xupd },
        { "Campfires on the map", "mapCamp", "Guild campfires on the world map and minimap", function() if ns.Map then pcall(ns.Map.UpdateWorldPins) pcall(ns.Map.UpdateMinimap) end end },
        { "Coordinates on the minimap", "mmCoords", "Your position and distance to the target", xupd },
        { "Targets also as TomTom waypoint", "tomtom", "Only with TomTom installed: Oasis targets also get a TomTom arrow", nil, true },
        { "Accept layer requests from the guild", "layerAsk", "Notice when someone wants to join your layer through your group", xupd, true },
    })

    -- 0.6.595: gathering map lives in Oasis - Convenience: without that add-on the section is not shown at all
    if ns.Gather then
    head("Guild gathering map")
    if S().gatherFresh == nil then S().gatherFresh = true end
    if S().gatherHarvest == nil then S().gatherHarvest = true end
    grid({
        { "Hide gathering map on the world map", "gatherWorldOff", "Nodes someone in the guild has found", gupd },
        { "Hide gathering map on the minimap", "gatherMiniOff", "Nodes someone in the guild has found", gupd },
        { "Hide herbs", "gatherOff_herb", nil, gupd },
        { "Hide ore", "gatherOff_ore", nil, gupd },
        { "Hide treasures", "gatherOff_treasure", nil, gupd },
        { "Hide fishing spots", "gatherOff_fish", nil, gupd },
        { "Hide locked chests", "gatherOff_lock", nil, gupd },
        { "Gather nodes without circle frame", "gatherRingOff", "Only the icon, without dark disc and ring", symUpd },
        { "Color nodes by freshness", "gatherFresh", "Fresh nodes bright, old ones fade", gupd },
        { "Show just-harvested spots in gray", "gatherHarvest", "If someone gathered there in the last 5 minutes", gupd },
        { "Gathering route", "gatherRoute", "Round trip through the nodes, minimap arrow to the next one", symUpd },
        { "Glimmer: nearby nodes light up", "glimmer", "Known nodes within 60 m pulse on the minimap, a soft sound at 25 m", gupd, true },
        { "Glimmer sound", "glimmerSound", "Soft sound when you get close to a node", nil, true },
        { "Minimap scan: find nodes by themselves", "gatherScan", "Reads the herb and ore dots on the minimap and adds them to the gathering map", nil, true },
        { "Arrow to the nearest node", "gatherArrow", "An arrow on the screen points to the next herb or ore (drag to move)", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Gathering symbols on the minimap", "gatherSymbols", "The scanned dots as herb and ore pictures (red = your skill is too low)", function() if ns.GatherSight then ns.GatherSight.Apply() end end, true },
        { "Switch finders automatically", "gatherSwitch", "With herbalism and mining: changes between Find Herbs and Find Minerals every 40 m (out of combat)", nil },
        { "Sound for new nodes", "gatherSound", "A soft ping when the minimap scan finds something new", nil },
        { "Hide the skill needed in the tooltip", "gatherSkillOff", "No \"Requires Herbalism (115)\" line on minimap dots and nodes", nil },
        { "Arrow: herbs", "gatherArrowHerb", nil, nil, true },
        { "Arrow: ore", "gatherArrowOre", nil, nil, true },
        { "Arrow: treasures", "gatherArrowTreasure", nil, nil, true },
        { "Arrow: rares", "gatherArrowRare", "Rares your guild has seen, while Track Beasts/Humanoids shows them", nil, true },
        { "Arrow: leylines", "gatherArrowLeyline", nil, nil, true },
        { "Arrow: herbs and ore first", "gatherArrowProfFirst", "Treasures, rares and leylines only when no herb or ore is near", nil },
        { "Arrow: also nodes in caves", "gatherArrowCaves", "Off = nodes the minimap shows in gray (cave, other level) are skipped", nil },
        { "Lock arrow", "gatherArrowLock", "Cannot be dragged, clicks go through", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Sparkles on herbs and ore nearby", "gatherSparkle", "Gold sparkles on the node in front of you (turns on the game's interact icons, up to 30 m)", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Sparkles: hide the game's interact icons", "gatherSparkleHideIcons", "Only the sparkles stay on the node", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Sparkles far away (beta)", "gatherSparkleFar", "Sparkles on the in-world marker of the nearest node (sets the map pin)", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Map pin on the nearest node", "gatherPin", "Sets the game's map pin, the in-world marker shows the way (only if you have no own pin)", function() if ns.GatherSight then ns.GatherSight.Apply() end end },
        { "Show nodes for all professions", "gatherAllProfs", "Off = only herbs/ore/fishing spots of your own gathering professions", function() if ns.Gather and ns.Gather.ResetOwnKinds then ns.Gather.ResetOwnKinds() end gupd() end },
    })
    local sorts
    sorts = K.Button(det, L["Filter individual types"], 226, 24, nil, function()
        local items = {}
        local G = ns.Gather
        for _, e in ipairs(G and G.Names and G.Names() or {}) do
            local k = G.KINDS[e.kind]
            items[#items + 1] = { text = K.hex(k.color) .. e.name .. "|r  |cff888888" .. e.n .. "|r", checked = not (S().gatherHide and S().gatherHide[e.name]),
                fn = function()
                    S().gatherHide = S().gatherHide or {}
                    S().gatherHide[e.name] = (not S().gatherHide[e.name]) or nil
                    gupd()
                end }
        end
        if #items == 0 then items[1] = { text = L["No named nodes yet."], disabled = true } end
        K.ShowMenu(sorts, items, L["Filter individual types"])
    end)
    sorts:SetPoint("TOPLEFT", 14, y)
    y = y - 36
    end

    head("Adjust icons")
    local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
    local SYM = {   -- { text, key, from, to, step, default, format }
        { "Gathering nodes minimap: size", "gatherMiniScale", 0.6, 2, 0.05, 1 },
        { "Gathering nodes minimap: opacity", "gatherMiniAlpha", 0.2, 1, 0.05, 1 },
        { "Gathering nodes world map: size", "gatherWorldScale", 0.6, 2.5, 0.05, 1 },
        { "Gathering nodes world map: opacity", "gatherWorldAlpha", 0.2, 1, 0.05, 1 },
        { "Guild dots minimap: size", "mmDotScale", 0.6, 2, 0.05, 1 },
        { "Guild dots minimap: opacity", "mmDotAlpha", 0.2, 1, 0.05, 1 },
        { "World map dots: size", "mapPinScale", 0.6, 2, 0.05, 1 },
        { "Only show nodes from", "gatherMinCount", 1, 10, 1, 1, function(v) return (L["%d finds"]):format(v) end },
        -- 0.6.597: look of the live gathering symbols and the size of the game's own yellow dots
        { "Gathering symbols: shape", "gatherShape", 1, 4, 1, 3, function(v) return L[({ "Square", "Round", "Round with ring", "Slim ring" })[v] or "Round with ring"] end },
        { "Game's gathering dots: size", "gatherDotScale", 0.5, 1, 0.05, 1 },
    }
    local syms = avail(SYM)
    for i, d in ipairs(syms) do
        local cx = 14 + ((i - 1) % 2) * 370
        rowLabel(det, L[d[1]], cx, y)
        local sl = K.Slider(det, 200, d[3], d[4], d[5], function() return S()[d[2]] or d[6] end,
            function(v) S()[d[2]] = v symUpd() end, d[7] or pct)
        sl:SetPoint("TOPLEFT", cx, y - 22)
        table.insert(det.refreshers, function() sl:Refresh() end)
        if i % 2 == 0 or i == #syms then y = y - 54 end
    end
    local reset = K.Button(det, L["Reset icons"], 226, 24, nil, function()
        for _, d in ipairs(SYM) do S()[d[2]] = nil end
        S().gatherRingOff, S().gatherHide = nil, nil
        symUpd()
        for _, fn in ipairs(det.refreshers) do pcall(fn) end
        for _, t in ipairs(det.t) do if t.Refresh then pcall(t.Refresh, t) end end
    end)
    reset:SetPoint("TOPLEFT", 14, y)
    y = y - 40

    head("Send")
    rowLabel(det, L["Send position every"], 14, y)
    det.mapInterval = K.Slider(det, 160, 5, 30, 1, function() return S().mapInterval or 8 end,
        function(v) S().mapInterval = v if ns.Map then ns.Map.nextSend = nil end end,
        function(v) return (L["%d sec"]):format(v) end)
    det.mapInterval:SetPoint("TOPLEFT", 184, y + 2)
    table.insert(det.refreshers, function() det.mapInterval:Refresh() end)
    y = y - 30
    note(det, L["Sending less often = less traffic, but the guild sees you move less smoothly."], 14, y, 600, C.dim)
    y = y - 22
    return y - 10
end)
ns.AddPageSettings("insta", function(det, y)
    local s = S()
    if s.profShareQuests == nil then s.profShareQuests = true end
    if s.profShareGear == nil then s.profShareGear = true end
    -- About me
    rowLabel(det, L["About me"], 14, y - 2)
    local bio = K.Input(det, 330, L["One line about you, e.g. Always up for dungeons"])
    bio:SetMaxLetters(80)
    bio:SetPoint("TOPLEFT", 164, y + 2)
    bio:SetText(s.bio or "")
    bio:SetScript("OnTextChanged", function(self)
        self.ph:SetShown(self:GetText() == "")
        local t = (self:GetText() or ""):gsub("|", "")
        S().bio = t ~= "" and t or nil
    end)
    bio.onEnter = function() sendProfile() end
    bio:HookScript("OnEditFocusLost", function() sendProfile() end)
    y = y - 30
    note(det, L["Shown on your profile card for the guild."], 164, y, 330, C.dim)
    y = y - 30
    -- Visibility
    det.t[#det.t + 1] = toggle(det, 14, y, "Show Oasis XP on screen", "xpFloat", "New Oasis experience briefly floats up as +XP in the middle of the screen", nil, 600)
    y = y - 40
    -- Rewards from the Oasis rank
    rowLabel(det, "|cffe8b44a" .. L["Your rewards"] .. "|r", 14, y)
    y = y - 30
    det.rw = {}
    det.rw[1] = rewardPicker(det, "sound", 14, y, "Rank-up fanfare", function() return S().rankSound end,
        function(k) S().rankSound = k if k and ns.Sound then ns.Sound.PlayChoice(k) end end)
    y = y - 36
    det.rw[2] = rewardPicker(det, "dice", 14, y, "Deathroll dice", function() return S().diceDesign end,
        function(k) S().diceDesign = k end)
    y = y - 36
    det.rw[3] = rewardPicker(det, "theme", 14, y, "Rank colour", function()
            local acc = S().accent
            for _, r in ipairs(ns.Rewards and ns.Rewards.LIST or {}) do if r.kind == "theme" and r.hex == acc then return r.key end end
        end,
        function(k)
            local r = k and ns.Rewards.byKey["theme:" .. k]
            S().accent = r and r.hex or ""
            if ns.Admin then ns.Admin.ApplyBrand(true) end
        end)
    y = y - 36
    note(det, L["You unlock new rewards with your Oasis rank."], 14, y, 600, C.dim)
    return y - 20
end)

-- Feature catalog by usefulness to the player, independent of the main navigation.
local AREA_SCOPE = {
    home = "personal", discover = "personal", life = "personal", bags = "personal",
    badges = "personal", legacy = "personal", rank = "personal", fight = "personal",
    -- 0.6.530: quest items and dungeons are interplay; new pages My group, Guild life, Raid roster
    questitems = "social", dungeons = "social", party = "social", guildlife = "guild", kader = "guild",
    insta = "social", chat = "social", community = "social", groups = "social",
    social = "social", allies = "social", scout = "social", camp = "social", deathroll = "social",
    radar = "guild", chronicle = "guild", polls = "guild", board = "guild", goals = "guild",
    bank = "guild", deaths = "guild", raid = "guild", raidlead = "guild", loot = "guild",
    buffs = "guild", tactics = "guild", crafting = "guild", trade = "guild", wants = "guild",
    raidboard = "guild", lockouts = "guild", softres = "guild",
}
for parent, children in pairs(AREA_CHILDREN) do
    for _, child in ipairs(children) do
        if not AREA_SCOPE[child] then AREA_SCOPE[child] = AREA_SCOPE[parent] end
    end
end
local SCOPE_TAB = { guild = "guildtools", social = "socialtools", personal = "personaltools" }
local function areaTab(key) return SCOPE_TAB[AREA_SCOPE[key] or "personal"] end
ns.SettingsAreaTab = areaTab

-- Sections in navigation order (groups), rest at the end
local function pageGroups(scope)
    local out, seen = {}, {}
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        local items = {}
        for _, k in ipairs(g.pages) do
            local d = ns.PageDef(k)
            -- leave out pages that don't exist on their own (anymore) (e.g. Oasis rank lives in the profile)
            if scope and (AREA_SCOPE[k] or "personal") ~= scope then seen[k] = true
            elseif d and d.visible and not d.visible() then seen[k] = true
            elseif d and d.nav then items[#items + 1] = d seen[k] = true end   -- 0.5.679: dashboard included (always on)
        end
        if #items > 0 then out[#out + 1] = { text = (g.text and g.text ~= "") and g.text or "Start", items = items } end
    end
    local rest = {}
    for _, d in ipairs(ns.Pages()) do
        if d.nav and not seen[d.key] and d.key ~= "home" and not d.topbar and not (d.visible and not d.visible()) and (not scope or (AREA_SCOPE[d.key] or "personal") == scope) then rest[#rest + 1] = d end
    end
    if #rest > 0 then out[#out + 1] = { text = "More", items = rest } end
    return out
end
local function pageShown(key) return not (S().hiddenPages and S().hiddenPages[key]) end
local function setPageShown(key, v)
    if ns.Admin and not ns.Admin.PageEnabled(key) then return end
    S().hiddenPages = S().hiddenPages or {}
    S().hiddenPages[key] = (not v) or nil
    ns.LayoutNav()
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
end

local function buildPages(f, scope)
    f.noCompact = true
    -- Picker at the top: button with icon, click opens a section card (groups in two columns, with icons)
    local function iconTag(key, c)
        local path = ns.ICONS and ns.ICONS[key]
        if not path then return "" end
        c = c or C.text
        return ("|T%s:14:14:0:0:64:64:0:64:0:64:%d:%d:%d|t  "):format(path, c[1] * 255, c[2] * 255, c[3] * 255)
    end
    -- 0.5.550: no more dropdown - overview as cards (like "Entdecken"), gear opens the settings
    f.pick = { Update = function() end }
    f.back = K.Button(f, "< " .. L["All sections"], 140, 22, "ghost", function() f.sel = nil f:ShowSel() end)
    f.back:SetPoint("TOPLEFT", 0, -6)
    f.back:Hide()
    f.intro = note(f, L["Switch: show in your navigation. Cog: configure this feature. Disable modules under System & modules."], 0, -6, 620, C.muted)
    f.pickHint = { SetShown = function(_, v) f.back:SetShown(not v) f.intro:SetShown(v) end }
    -- Restart the tour (Onboarding.lua)
    f.tourBtn = K.Button(f, L["Tour"], 88, 22, "ghost", function() ns.Onboarding.Show() end)
    f.tourBtn:SetPoint("TOPRIGHT", 0, -6)

    -- Overview: all sections as cards by group (icon, name, short text, toggle, gear)
    f.ov = CreateFrame("Frame", nil, f)
    f.ov:SetPoint("TOPLEFT", 0, -54)
    f.ov:SetPoint("TOPRIGHT", 0, -54)
    f.ov:SetHeight(400)
    f.ov.heads, f.nav = {}, {}
    local G = ns.Insta and ns.Insta.Glass
    for _, gr in ipairs(pageGroups(scope)) do
        local h = K.Text(f.ov, 10, C.dim)
        h:SetText(K.Upper(L[gr.text]))
        h.line = K.Divider(f.ov)
        local ts = {}
        for _, d in ipairs(gr.items) do
            local key = d.key
            local t = CreateFrame("Button", nil, f.ov)
            t:SetHeight(62)
            t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            if not (G and pcall(G, t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.09 }, 10)) then K.Fill(t, { 1, 1, 1, 0.03 }) K.Border(t, C.line) end
            t.tint = t:CreateTexture(nil, "BACKGROUND", nil, 3)
            t.tint:SetPoint("TOPLEFT", 3, -3) t.tint:SetPoint("BOTTOMRIGHT", -3, 3)
            t.icon = K.Glyph(t, 18, (ns.ICONS and ns.ICONS[key]) or (ns.MEDIA .. "icons\\home"), C.muted)
            t.icon:SetPoint("TOPLEFT", 12, -11)
            t.lbl = K.Title(t, 12, C.text)
            t.lbl:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
            t.lbl:SetPoint("RIGHT", -62, 0)
            t.lbl:SetJustifyH("LEFT")
            t.lbl:SetWordWrap(false)
            t.lbl:SetText(L[d.title])
            t.sub = K.Text(t, 10, C.dim)
            t.sub:SetPoint("TOPLEFT", 12, -34)
            t.sub:SetPoint("RIGHT", -12, 0)
            t.sub:SetJustifyH("LEFT")
            t.sub:SetJustifyV("TOP")
            t.sub:SetWordWrap(true)
            t.sub:SetHeight(24)
            t.sub:SetText(d.sub and L[d.sub] or "")
            -- Toggle (top right) + gear next to it
            t.sw = K.Pill(t, 24, 13)
            t.sw:SetPoint("TOPRIGHT", -34, -13)
            t.knob = K.KnobCircle(t.sw, 10)
            t.gear = CreateFrame("Button", nil, t)
            t.gear:SetSize(20, 20)
            t.gear:SetPoint("TOPRIGHT", -8, -9)
            t.gear.ic = K.Glyph(t.gear, 14, ns.MEDIA .. "icons\\settings", C.dim)
            t.gear.ic:SetPoint("CENTER")
            t.gear:SetScript("OnClick", function() f.sel = key f:ShowSel() end)
            t.gear:SetScript("OnEnter", function(self) self.ic:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { L[d.title], L["Settings of this area"] }) end)
            t.gear:SetScript("OnLeave", function(self) self.ic:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
            t.key = key
            -- Dashboard cannot be hidden: no toggle, click opens its settings
            local fixed = key == "home"
            if fixed then t.sw:Hide() t.gear:ClearAllPoints() t.gear:SetPoint("TOPRIGHT", -8, -9) end
            function t:Refresh()
                local on = fixed or pageShown(key)
                local adminOff = ns.Admin and not ns.Admin.PageEnabled(key)
                local ac = C.accent
                self.tint:SetColorTexture(ac[1], ac[2], ac[3], (on and not adminOff) and 0.10 or 0)
                self.sw:SetColor(on and ac[1] or 0.25, on and ac[2] or 0.25, on and ac[3] or 0.27, 1)
                self.knob:ClearAllPoints()
                self.knob:SetPoint("CENTER", self.sw, on and "RIGHT" or "LEFT", on and -6 or 6, 0)
                local ic = on and ac or C.dim
                self.icon:SetVertexColor(ic[1], ic[2], ic[3])
                local c = on and C.text or C.muted
                self.lbl:SetTextColor(c[1], c[2], c[3])
                self:SetAlpha(adminOff and 0.45 or 1)
            end
            t:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" or fixed then f.sel = key f:ShowSel() return end
                setPageShown(key, not pageShown(key))
                self:Refresh()
                if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            end)
            t:SetScript("OnEnter", function(self)
                self.tint:SetAlpha(1.7)
                local lines = { L[d.title] }
                if d.sub then lines[#lines + 1] = L[d.sub] end
                if ns.Admin and not ns.Admin.PageEnabled(key) then lines[#lines + 1] = "|cffffc24d" .. L["Turned off by guild leadership."] .. "|r" end
                lines[#lines + 1] = "|cff888888" .. L["Click: show/hide  ·  Gear or right-click: settings"] .. "|r"
                K.ShowTip(self, lines)
            end)
            t:SetScript("OnLeave", function(self) self.tint:SetAlpha(1) GameTooltip:Hide() end)
            indexAdd(L[d.title], t, L["Show in my navigation"])
            ts[#ts + 1] = t
            f.nav[#f.nav + 1] = t
        end
        f.ov.heads[#f.ov.heads + 1] = { h = h, ts = ts }
    end
    local function layoutOv()
        local w = f.ov:GetWidth()
        if not w or w < 200 then w = 740 end
        local cols = w >= 700 and 3 or 2
        local cw = math.floor((w - (cols - 1) * 10) / cols)
        local y = 0
        for _, g in ipairs(f.ov.heads) do
            g.h:ClearAllPoints() g.h:SetPoint("TOPLEFT", 0, y)
            g.h.line:ClearAllPoints() g.h.line:SetPoint("TOPLEFT", 0, y - 15) g.h.line:SetPoint("RIGHT", f.ov, "RIGHT", 0, 0)
            y = y - 24
            for i, t in ipairs(g.ts) do
                local k = i - 1
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", (k % cols) * (cw + 10), y - math.floor(k / cols) * 70)
                t:SetWidth(cw)
            end
            y = y - math.ceil(#g.ts / cols) * 70 - 10
        end
        f.ov:SetHeight(-y + 10)
        -- Re-measure the scroll area of the settings page
        local sc = f:GetParent()
        if sc and sc.Measure then pcall(sc.Measure) end
    end
    f.ov:SetScript("OnSizeChanged", layoutOv)
    layoutOv()

    -- Single section: rebuilt on every selection
    function f:ShowSel()
        self.ov:SetShown(self.sel == nil)
        self.pickHint:SetShown(self.sel == nil)
        if self.detScroll then self.detScroll:Hide() self.detScroll:SetParent(nil) self.detScroll = nil end
        self.det = nil
        if not self.sel then
            self:Refresh()
            local o = self:GetParent()
            while o and not (o.Measure and o.SetVerticalScroll) do o = o:GetParent() end
            if o then o:SetVerticalScroll(0) C_Timer.After(0, function() pcall(o.Measure) end) end
            return
        end
        local d = ns.PageDef(self.sel)
        if not d then return end
        local key = d.key
        -- scrollable in case a section has more settings than fit (mouse wheel + thin bar)
        local sf = CreateFrame("ScrollFrame", nil, self)
        sf:SetPoint("TOPLEFT", 0, -46)
        sf:SetPoint("BOTTOMRIGHT", 0, 0)
        self.detScroll = sf
        -- 0.5.615: if the section overview was scrolled down, the section lay outside the view and the
        -- mouse wheel only landed here -> scroll the outer area to the top and anchor this one to its bottom edge
        local outer = self:GetParent()
        while outer and not (outer.Measure and outer.SetVerticalScroll) do outer = outer:GetParent() end
        if outer then
            outer:SetVerticalScroll(0)
            if ns._setScroll then for k in pairs(ns._setScroll) do ns._setScroll[k] = 0 end end
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -46)
            sf:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            sf:SetPoint("BOTTOM", outer, "BOTTOM", 0, 0)
            C_Timer.After(0, function() pcall(outer.Measure) if sf.UpdateBar then pcall(sf.UpdateBar, sf) end end)
        end
        local det = CreateFrame("Frame", nil, sf)
        det:SetSize(math.max(300, (sf:GetWidth() or 0) > 50 and sf:GetWidth() - 10 or 728), 600)
        sf:SetScrollChild(det)
        sf:SetScript("OnSizeChanged", function(_, w) if w and w > 50 then det:SetWidth(w - 10) end end)
        sf.bar = sf:CreateTexture(nil, "OVERLAY")
        sf.bar:SetWidth(3)
        sf.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        function sf:UpdateBar()
            local h, ch = self:GetHeight() or 0, det:GetHeight() or 0
            local max = math.max(0, ch - h)
            self.bar:SetShown(max > 0 and h > 0)
            if max > 0 and h > 0 then
                local th = math.max(24, h * h / ch)
                local pos = (h - th) * ((self:GetVerticalScroll() or 0) / max)
                self.bar:ClearAllPoints()
                self.bar:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -pos)
                self.bar:SetHeight(th)
            end
        end
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, (det:GetHeight() or 0) - (self:GetHeight() or 0))
            local v = math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40))
            self:SetVerticalScroll(v)
            self:UpdateBar()
        end)
        self.det = det
        det.t = {}
        -- 0.5.912: no more header with icon, "Bereich oeffnen" and "In meiner Navigation zeigen" - showing/hiding
        -- is already one level up in the section list. The card carries the section name.
        local adminOff = ns.Admin and not ns.Admin.PageEnabled(key)
        local c2 = card(det, 0, 0, 740, 300)
        c2:SetPoint("TOPRIGHT", det, "TOPRIGHT", -2, 0)
        section(det, L[d.title], 14, -12, 700)
        if adminOff then
            note(det, "|cffffc24d" .. L["Turned off by guild leadership."] .. "|r", 360, -13, 300)
        end
        det:SetScript("OnSizeChanged", nil)
        local Y0 = -46
        local y = Y0
        descInline = true   -- Explanations as subline, then reflow (reflowDescs)
        local opts = avail(PAGE_OPTS[key])
        for _, o in ipairs(opts) do
            if o[5] and S()[o[2]] == nil then S()[o[2]] = true end   -- Default on
            det.t[#det.t + 1] = toggle(det, 14, y, o[1], o[2], o[3], o[4], 600)
            y = y - 32
        end
        if opts.inactive then
            rowLabel(det, L["Inactive after"], 14, y - 2)
            det.inact = K.Slider(det, 180, 7, 90, 1, function() return S().inactiveDays or 30 end,
                function(v) S().inactiveDays = v end, function(v) return (L["%d d"]):format(v) end)
            det.inact:SetPoint("TOPLEFT", 184, y)
            y = y - 28
            note(det, L["After this many days offline a member counts as inactive in the member list."], 14, y, 600)
            y = y - 24
        end
        if opts.listDark then
            rowLabel(det, L["List background"], 14, y - 2)
            det.listDark = K.Slider(det, 180, 0.2, 1, 0.01, function() return S().memberListAlpha or 0.82 end,
                function(v) S().memberListAlpha = v if ns.Radar and ns.Radar.ApplyListBg then pcall(ns.Radar.ApplyListBg) end end,
                function(v) return ("%d %%"):format(v * 100 + 0.5) end)
            det.listDark:SetPoint("TOPLEFT", 184, y)
            det.t[#det.t + 1] = det.listDark
            y = y - 36
        end
        if opts.emojiPicker then
            local ep = K.Button(det, L["Browse emojis"], 140, 22, "ghost", function() if ns.Emoji then ns.Emoji.TogglePicker() end end)
            ep:SetPoint("TOPLEFT", 14, y)
            y = y - 36
        end
        if opts.lootQuality then
            rowLabel(det, L["Log loot from quality"], 14, y - 2)
            det.q = K.Segments(det, {
                { key = 2, text = L["Green"] }, { key = 3, text = L["Blue"] }, { key = 4, text = L["Epic"] },
            }, function(k) S().lootMinQuality = k end)
            det.q:SetPoint("TOPLEFT", 184, y)
            y = y - 34
        end
        if PAGE_EXTRA[key] then
            local ok, ny = pcall(PAGE_EXTRA[key], det, y)
            if ok and type(ny) == "number" then y = ny
            elseif not ok then ns.err(L["Setup"] .. " settings/pages/" .. key, ny) end
        end
        -- Subpages without own navigation entry: show settings under the main section
        for _, ck in ipairs(AREA_CHILDREN[key] or {}) do
            local cd = ns.PageDef(ck)
            if cd and (PAGE_OPTS[ck] or PAGE_EXTRA[ck]) then
                y = y - 10
                rowLabel(det, "|cffe8b44a" .. L[cd.title] .. "|r", 14, y)
                y = y - 30
                for _, o in ipairs(avail(PAGE_OPTS[ck])) do
                    if o[5] and S()[o[2]] == nil then S()[o[2]] = true end
                    det.t[#det.t + 1] = toggle(det, 14, y, o[1], o[2], o[3], o[4], 600)
                    y = y - 32
                end
                if PAGE_EXTRA[ck] then
                    local ok, ny = pcall(PAGE_EXTRA[ck], det, y)
                    if ok and type(ny) == "number" then y = ny
                    elseif not ok then ns.err(L["Setup"] .. " settings/pages/" .. ck, ny) end
                end
            end
        end
        -- 0.5.995: tooltip and map toggles are collected under Tooltips & Map - here only the way there
        local links = AREA_LINKS[key]
        if links then
            y = y - 6
            for i, link in ipairs(links) do
                local lb = K.Button(det, L[link[2]] .. "  >", 226, 24, "ghost", function() if ns.Settings then ns.Settings.SetTab(link[1]) end end)
                lb:SetPoint("TOPLEFT", 14 + (i - 1) * 234, y)
            end
            y = y - 36
        end
        if y == Y0 then
            note(det, L["This section has no settings of its own."], 14, y, 600, C.dim)
            y = y - 24
        end
        descInline = false
        y = y - reflowDescs(det)
        c2:SetHeight(-y + 12)
        det:SetHeight(-y + 24)
        sf:SetVerticalScroll(0)
        sf:UpdateBar()
        self:Refresh()
    end
    -- 0.5.524: refresh each element only if it can (previously the page broke on a missing Refresh)
    local function rf(x) if x and x.Refresh then pcall(x.Refresh, x) end end
    function f:Refresh()
        for _, t in ipairs(self.nav) do
            local on = not ns.Admin or ns.Admin.PageEnabled(t.key)
            t:SetAlpha(on and 1 or 0.35)
            rf(t)
            if t.icon then
                local c = pageShown(t.key) and C.text or C.dim
                t.icon:SetVertexColor(c[1], c[2], c[3])
            end
        end
        if self.det then
            for _, t in ipairs(self.det.t) do rf(t) end
            rf(self.det.inact)
            if self.det.q then self.det.q:Select(S().lootMinQuality or 3) end
            for _, b in ipairs(self.det.rw or {}) do b:Update() end
            for _, b in ipairs(self.det.slots or {}) do b:Update() end
            rf(self.det.esize)
            rf(self.det.newDays)
            if self.det.UpdateMuted then self.det:UpdateMuted() end
            for _, fn in ipairs(self.det.refreshers or {}) do pcall(fn) end
        end
        self.pick:Update()
    end
    f:ShowSel()
end
local function refreshPages(f) f:Refresh() end

------------------------------------------------------------------------
-- Appearance
------------------------------------------------------------------------
local SAMPLE = "Oasis Gildenzentrale  äöü ÄÖÜ ß 1234"
local function fontList(f, x, y, w, h, fonts, field, head)
    local list = K.List(f, 30, function(l)
        local r = K.Row(l)
        r.sample = r:CreateFontString(nil, "OVERLAY")
        r.sample:SetPoint("LEFT", 10, 3)
        r.sample:SetPoint("RIGHT", -8, 3)
        r.sample:SetJustifyH("LEFT")
        r.sample:SetWordWrap(false)
        r.name = K.Text(r, 9, C.dim, "RIGHT")
        r.name:SetPoint("BOTTOMRIGHT", -8, 2)
        r:SetScript("OnClick", function(self)
            if not self.item then return end
            S()[field] = self.item.key
            K.ApplyUserFonts()
            ns.RefreshPage("settings")
        end)
        return r
    end, function(r, it)
        K.SetFontSafe(r.sample, it.path, head and 16 or 13, "")
        r.sample:SetText(head and it.text or SAMPLE)
        local on = S()[field] == it.key
        local c = on and C.text or C.muted
        r.sample:SetTextColor(c[1], c[2], c[3])
        r.name:SetText(head and "" or it.text)
        r.sel:SetShown(on)
    end)
    list:SetPoint("TOPLEFT", x, y)
    list:SetSize(w, h)
    list:SetData(fonts)
    return list
end
-- Switch design: swap palette, rebuild window (throttled)
local themeGen = 0
local function rebuildSoon()
    themeGen = themeGen + 1
    local gen = themeGen
    ns.After(0.25, function()
        if gen ~= themeGen then return end
        if K.ApplyTheme then K.ApplyTheme() end
        -- ApplyBrand -> ApplyAccent rebuilds the window itself (throttled); not again here (otherwise it loads twice)
        if ns.Admin then ns.Admin.ApplyBrand(true) elseif ns.RebuildMain then ns.RebuildMain() end
    end)
end
-- Remember the state of the color settings -> function that restores it (color picker "Cancel")
local LOOK_KEYS = { "theme", "duoBase", "duoAccent", "duoSide", "accent", "themeGrad", "glowColor", "glowColorSide", "glowStrengthL", "glowStrengthR", "glowBreath" }
local function lookSnapshot()
    local t, s = {}, S()
    for _, k in ipairs(LOOK_KEYS) do t[k] = s[k] end
    return function()
        local s2 = S()
        for _, k in ipairs(LOOK_KEYS) do s2[k] = t[k] end
        rebuildSoon()
    end
end
-- small preview card per design (shows background/gradient, sidebar, accent, frame)
local function themeCard(f, th, x, y, w, h)
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, h)
    local bg = th.bg or { 0.035, 0.035, 0.038, 1 }
    local side = th.side or { 0.020, 0.020, 0.022, 1 }
    local line = th.frame or th.line or { 0.19, 0.19, 0.2, 1 }
    local text = th.text or { 0.94, 0.94, 0.94, 1 }
    local acc = K.FromHex(th.accent ~= "" and th.accent or "ff1200") or C.accent
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", 1, -1) b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    if (th.gradDef or 0) > 0 and th.grad then
        K.Gradient(b.bg, "VERTICAL", th.grad.bottom, th.grad.top)
    else
        b.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
    end
    local sd = b:CreateTexture(nil, "BORDER")
    sd:SetPoint("TOPLEFT", 1, -1) sd:SetPoint("BOTTOMLEFT", 1, 1) sd:SetWidth(22)
    sd:SetColorTexture(side[1], side[2], side[3], 1)
    local nameX = 30
    local own   -- Design with its own preview (add-on module): th.preview(b) -> name spacing, text color
    if th.preview then
        local ok, nx, tc = pcall(th.preview, b)
        if ok and nx then own, nameX, text = true, nx, tc or text end
    end
    if not own then
        for i = 1, 3 do   -- hinted navigation
            local n = b:CreateTexture(nil, "ARTWORK")
            n:SetSize(12, 2) n:SetPoint("TOPLEFT", 6, -12 - i * 7)
            local c = i == 1 and acc or text
            n:SetColorTexture(c[1], c[2], c[3], i == 1 and 1 or 0.35)
        end
        local bar = b:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", 30, -10) bar:SetSize(26, 3)
        bar:SetColorTexture(acc[1], acc[2], acc[3], 1)
        local ln = b:CreateTexture(nil, "ARTWORK")
        ln:SetPoint("TOPLEFT", 30, -18) ln:SetPoint("RIGHT", -8, 0) ln:SetHeight(1)
        ln:SetColorTexture(line[1], line[2], line[3], 1)
    end
    b.name = K.Text(b, 12, text)
    b.name:SetTextColor(text[1], text[2], text[3])
    b.name:SetPoint("BOTTOMLEFT", nameX, 8)
    b.name:SetText(L[th.name])
    K.Border(b, line)
    b.check = K.Text(b, 12, acc, "RIGHT")
    b.check:SetPoint("TOPRIGHT", -6, -5)
    b.check:SetTextColor(acc[1], acc[2], acc[3])
    b.check:SetText("|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t")
    b.th = th
    b:SetScript("OnEnter", function(self)
        K.SetBorderColor(self, acc)
        K.ShowTip(self, { L[th.name], L[th.desc], "|cff888888" .. L["Click: apply theme (colours, accent, font)"] .. "|r" })
    end)
    b:SetScript("OnLeave", function(self)
        K.SetBorderColor(self, self.on and C.accent or line, self.on and 1 or 0.9)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        local s = S()
        -- Design click = reset base: own accent color/gradient revert to the design's values
        -- (contrast, border, graphics, opacity stay - they are independent of the design)
        local cur = K.CurrentTheme()
        local hadOverride = (s.accent or "") ~= (cur.accent or "") or s.themeGrad ~= nil
        if hadOverride and s.theme ~= th.key and K.Toast then
            K.Toast(L[th.name], L["Accent colour and gradient reset to the design"], C.accent)
        end
        s.theme = th.key
        s.colorOn = nil                      -- Design click = the design's colors (own colors off again)
        s.themeGrad = nil                    -- Gradient back to what the design intends
        s.accent = th.accent                 -- Default = guild color
        -- 0.6.160: design click = everything to default - including own base/accent/bar color, glow colors,
        -- glow strength and breathing
        s.duoBase, s.duoAccent, s.duoSide, s.glowColor, s.glowColorSide, s.frameColor = nil, nil, nil, nil, nil, nil
        s.glowStrengthL, s.glowStrengthR, s.glowBreath = nil, nil, nil
        if th.font and K.fontByKey[th.font] then s.uiFont = th.font K.ApplyUserFonts() end
        -- Design with its own click sound pack (th.uiPack); whoever has click sounds off stays off
        if th.uiPack and ns.Sound and ns.Sound.SetUiPack and ns.Sound.UiPack() ~= "none" then ns.Sound.SetUiPack(th.uiPack) end
        if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
        rebuildSoon()
    end)
    return b
end

local function buildLook(f)
    -- 0.5.544: airy at full width (page scrolls), glass cards, design cards lift on hover
    f.noCompact = true
    local LX = 16
    local function cardW(y, h, icon, title, sub)
        local c = cardH(f, 0, y, 740, h, icon, title, sub)
        c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
        return c
    end

    -- Design ---------------------------------------------------------------
    -- 0.5.555: two columns - left design + font, right own colors + details
    local RXc = 376
    local themeRows = math.ceil(#K.THEMES / 2)
    local designH = 54 + themeRows * 72 + 4
    cardH(f, 0, 0, 362, designH, "brush", L["Theme"], L["Ready-made looks - colours, accent and font in one click"])
    f.themes = {}
    local PER, GAPX = 2, 10
    local CW, CH = 160, 62
    for i, th in ipairs(K.THEMES) do
        local k = i - 1
        local x, y = LX + (k % PER) * (CW + GAPX), -54 - math.floor(k / PER) * (CH + 10)
        local b = themeCard(f, th, x, y, CW, CH)
        b.x0, b.y0 = x, y
        b:HookScript("OnEnter", function(self)
            self.lift = 1
            if K.Tween then K.Tween(self, 0.12, function(q) self:ClearAllPoints() self:SetPoint("TOPLEFT", self.x0, self.y0 + 3 * q) end) end
        end)
        b:HookScript("OnLeave", function(self)
            if K.Tween then K.Tween(self, 0.12, function(q) self:ClearAllPoints() self:SetPoint("TOPLEFT", self.x0, self.y0 + 3 * (1 - q)) end)
            else self:ClearAllPoints() self:SetPoint("TOPLEFT", self.x0, self.y0) end
        end)
        f.themes[#f.themes + 1] = b
        indexAdd(L[th.name], b, L["Theme"])
    end

    -- Own colors ----------------------------------------------------------
    local Y = 0
    local RX0 = RXc + 16
    -- Height from the number of presets (6 per row)
    local duoRows = math.ceil(#K.DUO_PRESETS / 6)
    local farbH = 68 + duoRows * 28 + 8 + 24 + 20 + 30 + 34 + 104   -- 0.6.232: two sliders (glow, image brightness)   -- 0.6.136/0.6.149 button rows; 0.6.158: glow strength and breathing
    cardH(f, RXc, Y, 362, farbH, "heart", L["Own colours"], L["Mix two colours - base, accent and sidebar individually"], true)
    local function applyDuo(base, acc)
        local s = S()
        -- 0.5.786: own colors recolor the SELECTED design - the design itself (style, border, font) stays
        s.colorOn, s.duoBase, s.duoAccent, s.accent, s.themeGrad = true, base, acc, acc, nil
        if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
        rebuildSoon()
    end
    local l0 = K.Text(f, 10, C.dim) l0:SetPoint("TOPLEFT", RX0, Y - 52) l0:SetText(K.Upper(L["Two colours"]))
    f.duo = {}
    local DPER, DGAP = 6, 5
    local DW = (330 - DGAP * (DPER - 1)) / DPER
    for i, pr in ipairs(K.DUO_PRESETS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(DW, 22)
        b:SetPoint("TOPLEFT", RX0 + ((i - 1) % DPER) * (DW + DGAP), Y - 68 - math.floor((i - 1) / DPER) * 28)
        local bc, ac = K.FromHex(pr.base), K.FromHex(pr.acc)
        b.l = b:CreateTexture(nil, "ARTWORK")
        b.l:SetPoint("TOPLEFT", 1, -1) b.l:SetPoint("BOTTOMLEFT", 1, 1) b.l:SetWidth(12)
        b.l:SetColorTexture(bc[1], bc[2], bc[3], 1)
        b.r = b:CreateTexture(nil, "ARTWORK")
        b.r:SetPoint("TOPRIGHT", -1, -1) b.r:SetPoint("BOTTOMRIGHT", -1, 1) b.r:SetPoint("LEFT", b.l, "RIGHT")
        if not K.Gradient(b.r, "HORIZONTAL", { bc[1], bc[2], bc[3], 1 }, { ac[1], ac[2], ac[3], 1 }) then b.r:SetColorTexture(ac[1], ac[2], ac[3], 1) end
        K.Border(b, C.line)
        b.pr = pr
        b:SetScript("OnEnter", function(self) K.SetBorderColor(self, ac) K.ShowTip(self, { L[pr.name], "|cff888888" .. L["Click: the selected design in these colours"] .. "|r" }) end)
        b:SetScript("OnLeave", function(self) K.SetBorderColor(self, self.on and C.accent or C.line) GameTooltip:Hide() end)
        b:SetScript("OnClick", function() S().duoSide = pr.side applyDuo(pr.base, pr.acc) end)
        f.duo[i] = b
    end
    local by = Y - 68 - math.ceil(#K.DUO_PRESETS / DPER) * 28 - 8
    f.duoBase = K.ColorPickButton(f, function() return S().duoBase or "15171d" end, function(hex) applyDuo(hex, S().duoAccent or (S().accent ~= "" and S().accent) or "ff4d6d") end, L["Window background"], lookSnapshot)
    f.duoBase:SetWidth(162)
    f.duoBase:SetPoint("TOPLEFT", RX0, by)
    f.duoAcc = K.ColorPickButton(f, function() return S().duoAccent or "ff4d6d" end, function(hex) applyDuo(S().duoBase or "15171d", hex) end, L["Accent / highlight"], lookSnapshot)
    f.duoAcc:SetWidth(162)
    f.duoAcc:SetPoint("LEFT", f.duoBase, "RIGHT", 6, 0)
    -- 0.6.170: clear names + explanation of exactly what gets colored
    f.duoBase:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Window background"], L["Base colour of the whole Oasis window (surfaces and cards)."] }) end)
    f.duoAcc:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Accent / highlight"], L["Colour for frames, buttons, markers and active entries."] }) end)
    -- 0.6.159: keep the current base/accent color (previously default colors -> everything on the right changed too)
    local function curBase() return S().duoBase or (C.bg and K.ToHex(C.bg)) or "15171d" end
    local function curAcc() return S().duoAccent or (C.accent and K.ToHex(C.accent)) or "ff4d6d" end
    f.duoSide = K.ColorPickButton(f, function()
        local th = K.DuoTheme(S().duoBase, S().duoAccent, S().duoSide)
        return (S().duoSide and S().duoSide ~= "") and S().duoSide or K.ToHex(th.side)
    end, function(hex)
        S().duoSide = hex
        applyDuo(curBase(), curAcc())
    end, L["Navigation (left)"], lookSnapshot)
    f.duoSide:SetWidth(162)
    f.duoSide:SetPoint("TOPLEFT", f.duoBase, "BOTTOMLEFT", 0, -6)
    f.duoSide:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.duoSide:HookScript("OnClick", function(_, btn)
        if btn == "RightButton" then S().duoSide = nil applyDuo(curBase(), curAcc()) end
    end)
    f.duoSide:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Navigation (left)"], L["Background colour of the navigation bar on the left. Right-click: automatic again."] }) end)
    f.duoSide:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.136: own color for the glow backgrounds (bar on the left and content on the right); no choice = accent color
    f.glowCol = K.ColorPickButton(f, function()
        return (S().glowColor and S().glowColor ~= "") and S().glowColor or K.ToHex(C.accent)
    end, function(hex) S().glowColor = hex end, L["Embers in content"], lookSnapshot)
    f.glowCol:SetWidth(162)
    f.glowCol:SetPoint("LEFT", f.duoSide, "RIGHT", 6, 0)
    f.glowCol:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.glowCol:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().glowColor = nil if self.Update then self:Update() end end
    end)
    f.glowCol:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Embers in content"], L["Colour of the glowing ember veins in the large content area on the right. Right-click: same as accent again."] }) end)
    f.glowCol:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.149: own color for the background of the left bar (no choice: like the right or accent color)
    f.glowSide = K.ColorPickButton(f, function()
        local v = S().glowColorSide
        if v and v ~= "" then return v end
        return K.ToHex(C.accent)   -- 0.6.159: like the right - no choice = accent color
    end, function(hex) S().glowColorSide = hex end, L["Embers in navigation"], lookSnapshot)
    f.glowSide:SetWidth(162)
    f.glowSide:SetPoint("TOPLEFT", f.duoSide, "BOTTOMLEFT", 0, -6)
    f.glowSide:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.glowSide:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().glowColorSide = nil if self.Update then self:Update() end end
    end)
    f.glowSide:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Embers in navigation"], L["Colour of the glowing ember veins in the navigation bar on the left. Right-click: same as accent again."] }) end)
    f.glowSide:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.191: color of the glow in the window frame (image frame); no choice = like the accent color
    f.frameCol = K.ColorPickButton(f, function()
        local v = S().frameColor
        if v and v ~= "" then return v end
        return K.ToHex(C.accent)
    end, function(hex) S().frameColor = hex end, L["Window frame"], lookSnapshot)
    f.frameCol:SetWidth(162)
    f.frameCol:SetPoint("LEFT", f.glowSide, "RIGHT", 6, 0)
    f.frameCol:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.frameCol:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().frameColor = nil if self.Update then self:Update() end end
    end)
    f.frameCol:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Window frame"], L["Colour of the embers in the window frame. Right-click: same as accent again."] }) end)
    f.frameCol:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.158: glow strength left/right and "Glut atmet"
    local pct = function(v) return (L["%d%%"]):format(v * 100 + 0.5) end
    local function glowRow(label, key, below, dy, def)
        local lb = K.Text(f, 13, C.text)
        lb:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, dy)
        lb:SetText(L[label])
        local sl = K.Slider(f, 200, 0, 2, 0.05, function() return tonumber(S()[key]) or def end,
            function(v) S()[key] = (math.abs(v - def) > 0.001) and v or nil end, pct)
        sl:SetPoint("LEFT", lb, "LEFT", 130, 0)
        indexAdd(L[label], sl)
        return lb, sl
    end
    -- 0.6.231: simplified to three sliders that each set left AND right (previously six separate ones)
    local function pairRow(label, keys, below, dy, maxV, def, tipKey, after)
        local lb = K.Text(f, 13, C.text)
        lb:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, dy)
        lb:SetText(L[label])
        local sl = K.Slider(f, 200, 0, maxV, 0.05, function() return tonumber(S()[keys[1]]) or def end,
            function(v)
                for _, k in ipairs(keys) do S()[k] = (math.abs(v - def) > 0.001) and v or nil end
                if after then after() end
            end, pct)
        sl:SetPoint("LEFT", lb, "LEFT", 130, 0)
        indexAdd(L[label], sl)
        sl:HookScript("OnEnter", function(self) K.ShowTip(self, { L[label], L[tipKey] }) end)
        sl:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return lb, sl
    end
    local applyBg = function() if K.ApplyBgBright then K.ApplyBgBright() end end
    f.glowAllLbl, f.glowAll = pairRow("Embers", { "glowStrengthR", "glowStrengthL" }, f.glowSide, -16, 2, 1,
        "Glow strength of the ember veins left and right. 0 % = off.")
    -- 0.6.232: image opacity dropped (brightness 0 % = black covers it); old values reset to 100 % once
    S().bgBright, S().bgBrightL = nil, nil
    f.bgLiLbl, f.bgLi = pairRow("Image brightness", { "bgLight", "bgLightL" }, f.glowAllLbl, -14, 2, 1,
        "0 % = black, 100 % = normal, above that stronger and brighter.", applyBg)
    f.glowBreath = K.Toggle(f, L["Glow breathes"], function() return S().glowBreath and true or false end,
        function(v) S().glowBreath = v or nil end)
    f.glowBreath:SetPoint("TOPLEFT", f.bgLiLbl, "BOTTOMLEFT", 0, -12)
    f.glowBreath:SetWidth(330)
    indexAdd(L["Glow breathes"], f.glowBreath)
    -- Font (left) + details (right) --------------------------------------
    local Y3 = -designH - 14
    cardH(f, 0, Y3, 362, 300, "chronicle", L["Font"], L["Applies to the whole Oasis interface. Takes effect right away, some spots after /reload."])
    f.head = fontList(f, LX, Y3 - 54, 330, 232, K.PickFonts(), "uiFont", true)
    Y3 = Y - farbH - 14
    -- 0.6.107: details as a calm list - three toggles at full width, below them size and transparency, at the bottom
    -- reset (previously tiles with truncated titles and a big gap before the sliders)
    cardH(f, RXc, Y3, 362, 362, "settings", L["Details"], L["Contrast, border, texture, size and transparency"], true)
    local MX = RXc + 16
    local restyle = function() local m = ns.MainFrame and ns.MainFrame() if m and K.StyleWindow then K.StyleWindow(m) end end
    if S().themeTexture == nil then S().themeTexture = true end
    if S().imageFrame == nil then S().imageFrame = true end
    f.contrast = toggle(f, MX, Y3 - 62, "High contrast", "highContrast", "Brighter grey text and lines", function() rebuildSoon() end, 330)
    f.frameAcc = toggle(f, MX, Y3 - 94, "Frame in accent colour", "frameAccent", "Window edge in your colour", function() restyle() end, 330)
    f.texT = toggle(f, MX, Y3 - 126, "Background texture", "themeTexture", "Leather, stone, hex grid ... depending on the design", function(v)
        S().themeTexture = v and true or false
        restyle()
    end, 330)
    -- 0.6.192: image frame (lava glow) on/off - off = slim modern frame with shimmer as before
    f.imgFrame = toggle(f, MX, Y3 - 158, "Ornate window frame", "imageFrame", "Ornate frame with embers (off: slim modern frame)", function(v)
        S().imageFrame = v and true or false
        if K.ApplyFrameStyle then
            local m = ns.MainFrame and ns.MainFrame()
            if m then K.ApplyFrameStyle(m) end
            if _G.OasisInterests then K.ApplyFrameStyle(_G.OasisInterests) end if _G.OasisFighterSelect then K.ApplyFrameStyle(_G.OasisFighterSelect) end
        end
        if K.RefreshBoxFrames then K.RefreshBoxFrames() end
    end, 330)
    -- 0.6.281: the same frame, thin, around all boxes (only with guild module, only if the ornate frame is on)
    if S().boxFrame == nil then S().boxFrame = true end
    f.boxFrameT = toggle(f, MX, Y3 - 190, "Frame around boxes too", "boxFrame", "The red line also thin around cards and boxes in the addon", function(v)
        S().boxFrame = v and true or false
        if K.RefreshBoxFrames then K.RefreshBoxFrames() end
    end, 330)
    f.logoSeg = { Select = function() end }   -- 0.5.681: no more logo picker (stub for refreshLook)
    local dv = K.Divider(f)
    dv:SetPoint("TOPLEFT", MX, Y3 - 226)
    dv:SetWidth(330)
    rowLabel(f, L["Window size"], MX, Y3 - 242)
    local pendingScale
    f.winScale = K.Slider(f, 200, 0.7, 1.4, 0.05, function() return pendingScale or S().scale or 1 end,
        function(v) pendingScale = v end, function(v) return (L["%d%%"]):format(v * 100 + 0.5) end,
        function(v)
            pendingScale = nil
            if v ~= S().scale then ns.SetScale(v) end
        end)
    f.winScale:SetPoint("TOPLEFT", MX + 110, Y3 - 240)
    indexAdd(L["Window size"], f.winScale)
    rowLabel(f, L["Transparency"], MX, Y3 - 274)
    f.winAlpha = K.Slider(f, 200, 0.1, 1, 0.01, function() return S().windowAlpha or 1 end,
        function(v) S().windowAlpha = v if ns.ApplyWindowAlpha then ns.ApplyWindowAlpha() end end,
        function(v) return ("%d %%"):format(v * 100 + 0.5) end)
    f.winAlpha:SetPoint("TOPLEFT", MX + 110, Y3 - 272)
    indexAdd(L["Transparency"], f.winAlpha, L["How transparent the Oasis window is"])
    local rs = K.Button(f, L["Reset appearance"], 170, 24, "ghost", function()
        local st = S()
        st.theme, st.themeGrad, st.highContrast, st.frameAccent, st.accent, st.uiFont = nil, nil, nil, nil, "", "inter"
        st.duoBase, st.duoAccent, st.duoSide, st.glowColor, st.glowColorSide, st.frameColor, st.bgBright, st.bgBrightL, st.bgLight, st.bgLightL = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
        st.glowStrengthL, st.glowStrengthR, st.glowBreath = nil, nil, nil
        st.themeTexture, st.logoAnim, st.logoMode, st.windowAlpha = true, true, nil, 1
        K.ApplyUserFonts()
        if ns.ApplyWindowAlpha then ns.ApplyWindowAlpha() end
        if K.Toast then K.Toast(L["Reset appearance"], L["All colour and design settings are back to default."], C.accent) end
        rebuildSoon()
    end)
    rs:SetPoint("TOPLEFT", MX, Y3 - 314)
    note(f, L["Some spots only change color after /reload."], MX + 182, Y3 - 316, 150, C.dim)
end
local function refreshLook(f)
    for _, b in ipairs(f.duo or {}) do
        b.on = S().colorOn and S().duoBase == b.pr.base and S().duoAccent == b.pr.acc
        K.SetBorderColor(b, b.on and C.accent or C.line)
    end
    if f.duoBase and f.duoBase.Update then f.duoBase:Update() f.duoAcc:Update() if f.duoSide.Update then f.duoSide:Update() end end
    if f.glowCol and f.glowCol.Update then f.glowCol:Update() end
    local cur = K.CurrentTheme().key
    for _, b in ipairs(f.themes) do
        local on = b.th.key == cur
        b.on = on
        b.check:SetShown(on)
        K.SetBorderColor(b, on and C.accent or (b.th.frame or b.th.line or C.line), on and 1 or 0.9)
    end
    f.contrast:Refresh()
    f.frameAcc:Refresh()
    f.texT:Refresh()
    f.logoSeg:Select(S().logoMode or "auto")
    if f.winAlpha and f.winAlpha.Refresh then f.winAlpha:Refresh() end
    if f.winScale and f.winScale.Refresh then f.winScale:Refresh() end
    f.head:Refresh()
end

------------------------------------------------------------------------
-- Notices
------------------------------------------------------------------------
local function buildToasts(f)
    f.noCompact = true
    f.t = {}
    -- Card: General
    card(f, 0, 0, 362, 214)
    section(f, L["Notifications"], 14, -12, 334)
    f.t[1] = toggle(f, 14, -46, "Show notifications", "toasts", "Orders, events, group searches, announcements ...", nil, 320)
    f.t[2] = toggle(f, 14, -78, "Hold back in combat", "toastHoldCombat", "Shown together once combat is over", nil, 320)
    rowLabel(f, L["Display time"], 14, -118)
    f.dur = K.Slider(f, 160, 1, 20, 1, function() return S().toastDur or 7 end,
        function(v) S().toastDur = v end, function(v) return (L["%d s"]):format(v) end)
    f.dur:SetPoint("TOPLEFT", 144, -116)
    note(f, L["Important announcements from the guild leadership stay twice as long."], 14, -144, 334)
    local test = K.Button(f, L["Test notification"], 120, 24, "ghost", function()
        K.Toast(L["Oasis is running"], L["This is what notifications look like."], C.accent)
    end)
    test:SetPoint("TOPLEFT", 14, -174)

    -- Card: size and position
    local RX = 376
    local rc = card(f, RX, 0, 362, 214)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["Size and position"], RX + 14, -12, 330)
    rowLabel(f, L["Size"], RX + 14, -48)
    f.scale = K.Slider(f, 160, 0.7, 1.5, 0.05, function() return S().toastScale or 1 end,
        function(v) S().toastScale = v K.LayoutToasts() end,
        function(v) return (L["%d%%"]):format(v * 100 + 0.5) end,
        function() K.Toast(L["Oasis is running"], L["This is what notifications look like."], C.accent) end)
    f.scale:SetPoint("TOPLEFT", RX + 130, -46)
    local move = K.Button(f, L["Change position"], 150, 24, "primary", function()
        K.ToastMover(function() ns.RefreshPage("settings") end)
    end)
    move:SetPoint("TOPLEFT", RX + 14, -84)
    local reset = K.Button(f, L["Reset"], 120, 24, "ghost", function()
        S().toastPos, S().toastScale = nil, 1
        K.LayoutToasts()
        ns.RefreshPage("settings")
    end)
    reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
    f.posNote = note(f, "", RX + 14, -120, 330, C.muted)

    -- Notices by occasion; the selection is kept when collapsing/expanding.
    f.kinds, f.kindGroups = {}, {}
    local scopes = {
        { key = "guild", title = "Guild & organisation", desc = "Announcements, events, crafting and shared progress." },
        { key = "social", title = "Socialising", desc = "Group searches, new members, birthdays and games together." },
        { key = "personal", title = "My achievements & general", desc = "Your levels, badges and personal notifications." },
    }
    local eventScope = {
        announce = "guild", alert = "guild", order = "guild", wants = "guild", event = "guild",
        loot = "guild", poll = "guild", death = "guild", chronicle = "guild",
        request = "social", group = "social", welcome = "social", birthday = "social", camp = "social",
        dr_invite = "social", dr_turn = "social", dr_win = "social", dr_lose = "social",
    }
    local function enabled(key)
        if key == "death" and S().deathToasts == false then return false end
        return not (S().toastOff and S().toastOff[key])
    end
    local function change(key, v)
        S().toastOff = S().toastOff or {}
        S().toastOff[key] = not v or nil
        if key == "death" then S().deathToasts = v end
    end
    local function layoutKinds()
        local y = -278
        for _, g in ipairs(f.kindGroups) do
            g.card:ClearAllPoints()
            g.card:SetPoint("TOPLEFT", 0, y)
            g.card:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
            local w = g.card:GetWidth() or 738
            local cw = (w - 42) / 2
            local rows = math.ceil(#g.items / 2)
            for i, t in ipairs(g.items) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", g.card, "TOPLEFT", 14 + ((i - 1) % 2) * (cw + 14), -76 - math.floor((i - 1) / 2) * 34)
                t:SetWidth(cw)
                t:SetShown(not g.closed)
            end
            local h = g.closed and 68 or 84 + rows * 34
            g.card:SetHeight(h)
            local on = 0
            for _, t in ipairs(g.items) do if enabled(t.kindKey) then on = on + 1 end end
            g.fold:SetLabel((g.closed and ">  " or "v  ") .. L[g.title] .. "  (" .. on .. "/" .. #g.items .. ")")
            y = y - h - 14
        end
        local sc = f:GetParent()
        if sc and sc.Measure then C_Timer.After(0, function() sc.Measure() end) end
    end
    local head = K.Header(f, L["Which notifications do you want?"])
    head:SetPoint("TOPLEFT", 0, -234)
    local go = K.Button(f, L["Sounds"], 110, 24, "ghost", function() page.SetTab("sound") end)
    go:SetPoint("TOPRIGHT", -2, -230)
    local allOn = K.Button(f, L["All on"], 80, 24, "ghost", function()
        S().toastOff, S().toastMuted, S().deathToasts = {}, nil, nil
        ns.RefreshPage("settings")
    end)
    allOn:SetPoint("RIGHT", go, "LEFT", -8, 0)
    f.kindSum = K.Text(f, 11, C.muted)
    f.kindSum:SetPoint("TOPLEFT", 0, -258)
    for _, spec in ipairs(scopes) do
        local g = { title = spec.title, items = {} }
        g.card = card(f, 0, -278, 738, 100)
        g.fold = K.Button(g.card, L[spec.title], 320, 26, "ghost", function()
            g.closed = not g.closed
            layoutKinds()
            if not S().noAnim and K.FadeIn and not g.closed then K.FadeIn(g.card, 0) end
        end)
        g.fold:SetPoint("TOPLEFT", 12, -10)
        g.fold.label:ClearAllPoints()
        g.fold.label:SetPoint("LEFT", 8, 0)
        note(g.card, L[spec.desc], 14, -44, 660, C.muted)
        g.bulk = K.Button(g.card, L["Turn group off"], 170, 24, "ghost", function()
            local any = false
            for _, t in ipairs(g.items) do if enabled(t.kindKey) then any = true end end
            for _, t in ipairs(g.items) do change(t.kindKey, not any) end
            ns.RefreshPage("settings")
        end)
        g.bulk:SetPoint("TOPRIGHT", -14, -10)
        for _, e in ipairs(ns.Sound and ns.Sound.EVENTS or {}) do
            if not e.dev and e.key ~= "entrance" and e.key ~= "open" and e.key ~= "close" and (eventScope[e.key] or "personal") == spec.key then
                local key = e.key
                local t = K.Toggle(g.card, L[e.text], function() return enabled(key) end, function(v)
                    change(key, v)
                    ns.RefreshPage("settings")
                end)
                t.kindKey = key
                indexAdd(L[e.text], t, L[spec.title])
                g.items[#g.items + 1] = t
                f.kinds[#f.kinds + 1] = t
                f.t[#f.t + 1] = t
            end
        end
        g.card.ExpandSearch = function() g.closed = false layoutKinds() end
        g.card:HookScript("OnSizeChanged", function(_, w)
            if g.width ~= w then g.width = w layoutKinds() end
        end)
        f.kindGroups[#f.kindGroups + 1] = g
    end
    layoutKinds()

end
local function refreshToasts(f)
    for _, t in ipairs(f.t) do t:Refresh() end
    -- mark disabled notice types red, counter at the top
    local on, n = 0, 0
    for _, t in ipairs(f.kinds or {}) do
        n = n + 1
        local off = (S().toastOff and S().toastOff[t.kindKey]) or (t.kindKey == "death" and S().deathToasts == false)
        if not off then on = on + 1 end
        if t.lbl then
            local c = off and C.muted or C.text
            t.lbl:SetTextColor(c[1], c[2], c[3])
        end
    end
    if f.kindSum then
        f.kindSum:SetText(("|cff66db9e%d %s|r  |cff666666·|r  %s"):format(on, L["on"],
            n - on > 0 and ("|cffe06060" .. (n - on) .. " " .. L["off"] .. "|r") or ("|cff888888" .. L["none off"] .. "|r")))
    end
    for _, g in ipairs(f.kindGroups or {}) do
        local on = 0
        for _, t in ipairs(g.items) do
            if not (S().toastOff and S().toastOff[t.kindKey]) and not (t.kindKey == "death" and S().deathToasts == false) then on = on + 1 end
        end
        g.bulk:SetLabel(on > 0 and L["Turn group off"] or L["Turn group on"])
        g.fold:SetLabel((g.closed and ">  " or "v  ") .. L[g.title] .. "  (" .. on .. "/" .. #g.items .. ")")
    end
    f.dur:Refresh()
    f.scale:Refresh()
    f.posNote:SetText(S().toastPos and L["Custom position. In the lower half of the screen, new notifications stack upwards."]
        or L["Default: top center. 'Change position' shows a sample notification you can drag with the mouse."])
end

------------------------------------------------------------------------
-- Sound & music
------------------------------------------------------------------------
local function choiceText(key)
    local c = ns.Sound.byKey[key]
    return c and L[c.text] or key
end
local EV_ICON = { toast = "announce", announce = "announce", alert = "announce", request = "groups", group = "groups",
    order = "crafting", wants = "wants", event = "checklist", loot = "raid", poll = "polls", rankup = "star_on",
    levelup = "stats", badge = "badges", welcome = "social", birthday = "heart", death = "deaths", chronicle = "chronicle",
    camp = "camp", dr_invite = "deathroll", dr_turn = "deathroll", dr_win = "deathroll", dr_lose = "deathroll",
    open = "home", close = "home" }
refreshSoundSpk = function(f)
    local v = S().soundVol or 14
    local on = S().sound ~= false
    f.spk:SetTexture(ns.MEDIA .. "icons\\" .. ((v == 0 or not on) and "speaker_off" or "speaker"))
    f.spk:SetAlpha(0.55 + 0.45 * v / 10)
end
local function buildSound(f)
    local Snd = ns.Sound
    f.noCompact = true
    if S().soundEntrance == nil then S().soundEntrance = true end
    if S().chatSounds == nil then S().chatSounds = true end
    if S().entrancePopup == nil then S().entrancePopup = true end

    -- simple sound picker: speaker (listen) + name, click opens the picker
    local function chip(parent, w, getKey, onPick, title)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, 24)
        b.bg = K.Fill(b, C.field)
        K.Border(b, C.line)
        if K.ApplySkin then K.ApplySkin(b, "field", C.field) end
        b.play = CreateFrame("Button", nil, b)
        b.play:SetSize(24, 24)
        b.play:SetPoint("LEFT", 0, 0)
        b.play.icon = K.Glyph(b.play, 14, ns.MEDIA .. "icons\\speaker", C.muted)
        b.play.icon:SetPoint("CENTER")
        b.play:SetScript("OnClick", function() local k = getKey() if k and k ~= "none" then Snd.Preview(k) b.playAt = GetTime() end end)
        if K.NoUiSound then K.NoUiSound(b.play) end   -- Listen: only the sound, no click sound before it
        -- while your own preview is playing: small equalizer instead of the speaker
        b.eq = K.Equalizer(b.play, 3, 11, 11, C.accent2, function() return b.playAt and GetTime() - b.playAt < 1.6 end)
        b.eq:SetPoint("CENTER", 0, 0)
        b.eq:Hide()
        b.play:HookScript("OnUpdate", function()
            local on = b.playAt and GetTime() - b.playAt < 1.6 or false
            if on ~= b.eqOn then b.eqOn = on b.eq:SetShown(on) b.play.icon:SetShown(not on) end
        end)
        b.play:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) K.ShowTip(self, L["Lists"]) end)
        b.play:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
        b.label = K.Text(b, 12, C.text)
        b.label:SetPoint("LEFT", 28, 0)
        b.label:SetPoint("RIGHT", -22, 0)
        b.label:SetWordWrap(false)
        b.arrow = K.Text(b, 10, C.dim, "RIGHT")
        b.arrow:SetPoint("RIGHT", -8, 0)
        b.arrow:SetText("v")
        b:SetScript("OnEnter", function(self) K.SetBorderColor(self, C.accent2) end)
        b:SetScript("OnLeave", function(self) K.SetBorderColor(self, C.line) end)
        b:SetScript("OnClick", function(self)
            Snd.OpenPicker(self, getKey(), function(k) onPick(k) Snd.Preview(k) self.playAt = GetTime() if K.OnSaved then pcall(K.OnSaved) end ns.RefreshPage("settings") end, title and title())
        end)
        function b:Update()
            local k = getKey()
            if not k or k == "none" then
                self.label:SetText("|cff777777" .. L["No sound"] .. "|r")
                self.play:SetAlpha(0.3)
            else
                local c = Snd.byKey[k]
                self.label:SetText(c and (L[c.text]:gsub("^Oasis: ", ""):gsub("^Meme: ", ""):gsub("^Musik: ", ""):gsub("^WoW: ", "")) or k)
                self.play:SetAlpha(1)
            end
        end
        return b
    end

    -- Card: Playback ---------------------------------------------------
    local X = 14
    card(f, 0, 0, 362, ns.TOOLS_RELEASED and 270 or 228)
    section(f, L["Playback"], X, -12, 334)
    f.on = toggle(f, X, -44, "Play sounds", "sound", nil, nil, 320)
    f.quiet = toggle(f, X, -72, "Silent in combat", "soundQuietCombat", nil, nil, 320)
    f.chs = toggle(f, X, -100, "Sounds from chat", "chatSounds", "Sounds others send in guild chat", nil, 320)
    rowLabel(f, L["Volume"], X, -140)
    f.vol = K.Slider(f, 160, 0, Snd.VOL_MAX, 1, function() return S().soundVol or 14 end,
        function(v) S().soundVol = v if f.spk then refreshSoundSpk(f) end end,
        function(v) return v == 0 and L["off"] or Snd.VolText(v) end,
        function(v) Snd.Preview("glocke", v) end)
    f.vol:SetPoint("TOPLEFT", X + 116, -138)
    -- UI sound pack: click sounds for buttons, tabs, toggles and window open/close
    rowLabel(f, L["Click sounds"], X, -168)
    f.uis = K.Button(f, "", 160, 24, "ghost")
    f.uis:SetPoint("TOPLEFT", X + 116, -164)
    f.uis.label:ClearAllPoints()
    f.uis.label:SetPoint("LEFT", 10, 0)
    f.uis.label:SetPoint("RIGHT", -20, 0)
    f.uis.label:SetJustifyH("LEFT")
    local arrow = K.Text(f.uis, 10, C.dim, "RIGHT")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    function f.uis:Refresh()
        local p = Snd.uiPackByKey[Snd.UiPack()]
        self.label:SetText(p and L[p.text] or "")
    end
    f.uis:SetScript("OnClick", function(self)
        local cur, list = Snd.UiPack(), {}
        for _, p in ipairs(Snd.UI_PACKS) do
            list[#list + 1] = { text = L[p.text], checked = p.key == cur, fn = function()
                Snd.SetUiPack(p.key)
                self:Refresh()
                if p.key ~= "none" then Snd.PlayChoice("ui_confirm") end
            end }
        end
        K.ShowMenu(self, list, nil, 160)
    end)
    f.uis:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Click sounds"], L["Sound pack for buttons, tabs, switches and windows"] }) end)
    -- 0.5.948: a guild's own sounds and emojis - how it works and what is currently loaded
    -- depends on ns.TOOLS_RELEASED (Core.lua): the template is in Oasis-Tools on GitHub/Discord
    if ns.TOOLS_RELEASED then
        local STEPS = {
            "1. Get the template Oasis-Tools from the Oasis Discord (channel oasis-download).",
            "2. Unpack it into Interface/AddOns: this creates the folders Oasis_Sounds and Oasis_Emojis.",
            "3. Drop your files in, double-click the import file, restart WoW.",
            "4. Share the two folders with your guild. Oasis updates never touch them.",
        }
        local function loaded()
            local s = rawget(_G, "OasisSoundsList")
            local e = rawget(_G, "OasisEmojiList")
            local ns_, ne = type(s) == "table" and #s or 0, 0
            for _, c in ipairs(type(e) == "table" and e or {}) do ne = ne + (type(c) == "table" and type(c.items) == "table" and #c.items or 0) end
            return (L["Loaded: %d own sounds, %d own emojis"]):format(ns_, ne)
        end
        f.own = K.Button(f, L["Your own sounds and emojis ..."], 334, 22, "ghost", function()
            ns.print(L["Your own sounds and emojis for your guild"] .. ":")
            for _, t in ipairs(STEPS) do ns.print("  " .. L[t]) end
            ns.print("  " .. loaded())
        end)
        f.own:SetPoint("TOPLEFT", X, -236)   -- 0.6.111: below the click volume (previously sat right on top of it)
        f.own:HookScript("OnEnter", function(self)
            local lines = { L["Your own sounds and emojis for your guild"] }
            for _, t in ipairs(STEPS) do lines[#lines + 1] = L[t] end
            lines[#lines + 1] = "|cff66db9e" .. loaded() .. "|r"
            lines[#lines + 1] = "|cff888888" .. L["Click: print the instructions to chat"] .. "|r"
            K.ShowTip(self, lines)
        end)
        f.own:HookScript("OnLeave", function() GameTooltip:Hide() end)
        -- 0.6.475: rarely needed - only with "Alle Optionen" (otherwise sat on the box edge after reflow)
        if not S().setAll then f.own:Hide() end
    end
    f.uis:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- assign individual sounds: small window, pick a pack per action (with preview)
    f.uiRoles = K.Button(f, "...", 44, 24, "ghost", function(self)
        local w = Snd.rolePop
        if not w then
            w = CreateFrame("Frame", "OasisUiRoles", UIParent)
            Snd.rolePop = w
            w:SetSize(330, 74 + #Snd.UI_ROLES * 32)
            w:SetFrameStrata("DIALOG")
            w:SetClampedToScreen(true)
            w:EnableMouse(true)
            -- opaque (glass surfaces are semi-transparent -> the list behind showed through)
            local solid = { C.bg[1], C.bg[2], C.bg[3], 0.98 }
            K.Fill(w, solid)
            K.Border(w, C.line)
            if K.ApplySkin then K.ApplySkin(w, "panel", solid) end
            local t = K.Title(w, 14, C.text)
            t:SetPoint("TOPLEFT", 16, -14)
            t:SetText(L["Click sounds one by one"])
            local x = K.CloseButton(w, function() w:Hide() end)
            x:SetPoint("TOPRIGHT", -8, -8)
            w.rows = {}
            for i, r in ipairs(Snd.UI_ROLES) do
                local role = r[1]
                local b = K.Button(w, "", 170, 24, "ghost")
                b:SetPoint("TOPLEFT", 112, -44 - (i - 1) * 32)
                local lb = K.Text(w, 12, C.muted)
                lb:SetPoint("RIGHT", b, "LEFT", -8, 0)   -- centered on the row
                lb:SetWidth(88)
                lb:SetJustifyH("LEFT")
                lb:SetText(L[r[2]])
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", 10, 0)
                b.label:SetPoint("RIGHT", -10, 0)
                b.label:SetJustifyH("LEFT")
                b.label:SetWordWrap(false)
                function b:Refresh()
                    local o = Snd.UiRoleChoice(role)
                    local p = o and Snd.uiPackByKey[o]
                    self:SetLabel(p and L[p.text] or ("|cff888888" .. L["as in the pack"] .. "|r"))
                end
                b:SetScript("OnClick", function(btn)
                    local cur, list = Snd.UiRoleChoice(role), {}
                    list[1] = { text = L["as in the pack"], checked = cur == nil, fn = function() Snd.SetUiRole(role, nil) btn:Refresh() Snd.PlayChoice("ui_" .. role) end }
                    for _, p in ipairs(Snd.UI_PACKS) do
                        list[#list + 1] = { text = L[p.text], checked = cur == p.key, fn = function()
                            Snd.SetUiRole(role, p.key)
                            btn:Refresh()
                            if p.key ~= "none" then Snd.PlayChoice("ui_" .. role) end
                        end }
                    end
                    K.ShowMenu(btn, list, nil, 170)
                end)
                local pl = K.IconButton(w, "", 22, function() Snd.PlayChoice("ui_" .. role) end, L["Lists"])
                if K.NoUiSound then K.NoUiSound(pl) end
                pl:SetPoint("LEFT", b, "RIGHT", 6, 0)
                pl.label:Hide()
                pl.ic = K.Glyph(pl, 14, ns.MEDIA .. "icons\\speaker", C.muted)
                pl.ic:SetPoint("CENTER")
                w.rows[i] = b
            end
            local reset = K.Button(w, L["All as in the pack"], 150, 22, "ghost", function()
                S().uiRole = nil
                for _, b in ipairs(w.rows) do b:Refresh() end
            end)
            reset:SetPoint("BOTTOMLEFT", 16, 14)
            if ns.EscClose then ns.EscClose(w) end
        end
        for _, b in ipairs(w.rows) do b:Refresh() end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -6)
        w:Show()
        w:Raise()
    end)
    f.uiRoles:SetPoint("LEFT", f.uis, "RIGHT", 6, 0)
    f.uiRoles:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Click sounds one by one"], L["Pick the sound for each action from any pack"] }) end)
    f.uiRoles:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- own volume for the click sounds (no value: 70 % of the sound volume)
    rowLabel(f, L["Click volume"], X, -202)
    f.uivol = K.Slider(f, 160, 0, Snd.VOL_MAX, 1, function() return K.UiVolume() end,
        function(v) S().uiVol = v end,
        function(v) return v == 0 and L["off"] or Snd.VolText(v) end,
        function() K.UiSound("ui_click") end)
    f.uivol:SetPoint("TOPLEFT", X + 116, -200)
    -- Equalizer at the top right of the card: dances on every preview
    f.eq = K.Equalizer(f, 16, 92, 17, C.accent2, function() return Snd.previewAt and GetTime() - Snd.previewAt < 1.6 end)
    f.eq:SetPoint("TOPRIGHT", f, "TOPLEFT", 362 - 16, -12)
    f.eq:EnableMouse(true)
    f.eq:SetScript("OnMouseDown", function() Snd.Preview("glocke") end)
    f.eq:SetScript("OnEnter", function(self) K.ShowTip(self, L["Click to listen"]) end)
    f.eq:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Speaker before the volume: shows the level
    f.spk = K.Glyph(f, 14, ns.MEDIA .. "icons\\speaker", C.muted)
    f.spk:SetPoint("TOPLEFT", X + 92, -142)

    -- Card: Coming online --------------------------------------------------
    local RX = 376
    local rc = card(f, RX, 0, 362, 228)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["When someone comes online"], RX + 14, -12, 330)
    rowLabel(f, L["Your sound"], RX + 14, -46)
    f.entrChip = chip(f, 200, function() return Snd.ChoiceFor("entrance") end,
        function(k) Snd.SetChoice("entrance", k) end, function() return L["Your online sound"] end)
    f.entrChip:SetPoint("TOPLEFT", RX + 130, -42)
    f.entrChip:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Your online sound"], L["Everyone with Oasis hears it when you come online."] }) end)
    f.entrChip:HookScript("OnLeave", function() GameTooltip:Hide() end)
    rowLabel(f, L["Volume"], RX + 14, -80)
    f.evol = K.Slider(f, 160, 1, Snd.VOL_MAX, 1, function() return S().soundEntranceVol or 10 end,
        function(v) S().soundEntranceVol = v end,
        function(v) return Snd.VolText(v) .. (v > 20 and ("  |cffe8b44a" .. L["loud"] .. "|r") or "") end,
        function(v) Snd.PreviewLoud("hallo", v) end)
    f.evol:SetPoint("TOPLEFT", RX + 130, -78)
    f.entr = toggle(f, RX + 14, -110, "Play other players' online sounds", "soundEntrance", nil, nil, 320)
    f.epop = toggle(f, RX + 14, -138, "Show when someone comes online", "entrancePopup", nil, nil, 320)

    -- Card: Sounds per notice -----------------------------------------------
    local bc = card(f, 0, -242, 738, 260)
    bc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -242)
    bc:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
    local bh = K.Header(bc, L["Sounds for notifications"])
    bh:SetPoint("TOPLEFT", 14, -12)
    bh:SetPoint("RIGHT", -140, 0)
    local bl = K.Divider(bc)
    bl:SetPoint("TOPLEFT", 14, -32)
    bl:SetPoint("RIGHT", bc, "RIGHT", -14, 0)
    local def = K.Button(bc, L["Reset all"], 120, 20, "ghost", function()
        S().soundEvents = {}
        ns.RefreshPage("settings")
    end)
    def:SetPoint("TOPRIGHT", -14, -10)
    -- Presets: set all notice sounds at once
    local pre = K.Button(bc, L["Choose preset"], 130, 20, "ghost", function(self)
        local list = {}
        for _, p in ipairs(Snd.PRESETS) do
            if not p.need or Snd.byKey[p.need] then list[#list + 1] = { text = L[p.text], fn = function() Snd.ApplyPreset(p.key) ns.RefreshPage("settings") end } end
        end
        K.ShowMenu(self, list, nil, 220)
    end)
    pre:SetPoint("RIGHT", def, "LEFT", -6, 0)
    local events = {}
    for _, e in ipairs(Snd.EVENTS) do if e.key ~= "entrance" and (not e.dev or ns.IsDev()) then events[#events + 1] = e end end
    f.list = K.List(bc, 30, function(l)
        local r = K.Row(l)
        r.ic = K.Glyph(r, 14, ns.MEDIA .. "icons\\sound", C.muted)
        r.ic:SetPoint("LEFT", 10, 0)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 32, 0)
        r.name:SetPoint("RIGHT", r, "CENTER", -10, 0)
        r.name:SetWordWrap(false)
        -- Hover: name shifts slightly right, icon takes the accent color
        r:HookScript("OnEnter", function(self)
            self.ic:SetVertexColor(C.accent2[1], C.accent2[2], C.accent2[3])
            if K.Tween and not S().noAnim then K.Tween(self.name, 0.14, function(q) self.name:SetPoint("LEFT", 32 + 4 * q, 0) end) end
        end)
        r:HookScript("OnLeave", function(self)
            self.ic:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            if K.Tween and not S().noAnim then K.Tween(self.name, 0.18, function(q) self.name:SetPoint("LEFT", 36 - 4 * q, 0) end) else self.name:SetPoint("LEFT", 32, 0) end
        end)
        r.chip = chip(r, 240, function() return r.item and Snd.ChoiceFor(r.item.key) end,
            function(k) if r.item then Snd.SetChoice(r.item.key, k) end end,
            function() return r.item and L[r.item.text] end)
        r.chip:SetPoint("RIGHT", -10, 0)
        r.chip:SetPoint("LEFT", r, "CENTER", 0, 0)
        return r
    end, function(r, ev)
        r.name:SetText(L[ev.text])
        r.ic:SetTexture(ns.MEDIA .. "icons\\" .. (EV_ICON[ev.key] or "sound"))
        r.chip:Update()
    end)
    f.list:SetPoint("TOPLEFT", bc, "TOPLEFT", 6, -40)
    f.list:SetPoint("BOTTOMRIGHT", bc, "BOTTOMRIGHT", -6, 6)
    f.list:SetData(events)

    -- Music section removed; Oasis no longer plays window music
    S().music = "off"
    if Snd.StopMusic then Snd.StopMusic() end
end
local function refreshSound(f)
    for _, t in ipairs({ f.on, f.quiet, f.chs, f.uis, f.uivol, f.entr, f.epop, f.vol, f.evol }) do t:Refresh() end
    -- Sounds off: everything below looks visibly calm
    local on = S().sound ~= false
    for _, t in ipairs({ f.quiet, f.chs, f.vol, f.eq, f.list }) do if t then t:SetAlpha(on and 1 or 0.4) end end
    if f.spk then
        local v = S().soundVol or 14
        f.spk:SetTexture(ns.MEDIA .. "icons\\" .. ((v == 0 or not on) and "speaker_off" or "speaker"))
        local c = (v == 0 or not on) and C.dim or C.accent2
        f.spk:SetVertexColor(c[1], c[2], c[3])
        f.spk:SetAlpha(0.55 + 0.45 * v / 10)
    end
    f.entrChip:Update()
    f.list:Refresh()
end

------------------------------------------------------------------------
-- Map & sharing
------------------------------------------------------------------------
-- 0.5.617: privacy - everything concerning yourself can be toggled in one place
local PRIV_ON = { "shareDeaths", "shareNodes", "shareTrace", "shareInstPos", "sharePerf", "shareCombat", "rtShare", "rtTrack",
    "trackPlay", "scoutSeen", "wrShare", "lkShare", "profShareGear", "profShareQuests", "shareErrors", "campAuto", "cpProfCD",
    "chatSounds", "entrancePopup", "soundEntrance" }   -- 0.6.112: sound defaults (previously only set the section page)
ns.Listen("DB_READY", function()
    local s = ns.db and ns.db.settings
    if not s then return end
    for _, k in ipairs(PRIV_ON) do if s[k] == nil then s[k] = true end end
    -- once: privacy-friendly defaults for existing users too
    if not s.priv617 then
        s.priv617 = true
        s.shareMap, s.shareRep, s.rareShare, s.cpRareShare = false, false, false, false
        if s.oasisNet ~= true then s.oasisNet = nil end
    end
    -- 0.5.674: always send whisper reactions (toggle removed) - turn back on once
    if not s.wlr674 then s.wlr674 = true s.wlReactSend = nil end
end)
local function buildShare(f)
    f.noCompact = true
    local LX, RX = 14, 376
    local MX = RX + 14
    f.t = {}
    local function tg(x, y, label, key, desc, after)
        local t = toggle(f, x, y, label, key, desc, after, 330)
        f.t[#f.t + 1] = t
        f.rk = f.rk or {}
        f.rk[#f.rk + 1] = { key }
        return t
    end
    -- left: what the guild sees of you
    local ROW = 27
    local L1 = {
        { "Share position on the world map", "shareMap", "Guild map and minimap dots for others. Default: off" },
        { "Share where you died", "shareDeaths", "Skulls on the guild map (90 days)" },
        { "Share gathering nodes", "shareNodes", "Herb and ore finds for the guild gathering map" },
        { "Announce campfires automatically", "campAuto", "When you light one, Oasis shows the guild where it burns" },
        { "Report rare sightings", "rareShare", "Rare mobs with location to the guild. Default: off" },
        { "Share dungeon paths", "shareTrace", "For self-explored dungeon maps" },
        { "Dungeon position to your group", "shareInstPos", "Only to your own group, for the dungeon map" },
        { "Share player ratings", "shareRep", "Thumbs and notes on players. Default: off (only for you)" },
        { "Show alts outside the guild", "shareAltsOutside", "Otherwise bank and chill alts stay private" },
        { "Gear in profile", "profShareGear", nil },
        { "Quests in profile", "profShareQuests", nil },
        { "Share your own online times", "rtShare", "For raid time planning (only your own times)" },
        { "Share combat records", "shareCombat", "Best values for the combat ranking" },
        { "Share fight reports", "wrShare", "Boss fights with death order (guild members only)" },
        { "Share raid IDs", "lkShare", nil },
        { "Share trade balance", "shareTrade", "For the trade ranking. Default: off" },
        { "Post my milestones in guild chat", "announceMilestones", "Every 5 levels and Legacy challenges" },
    }
    descInline = true
    local c1 = cardH(f, 0, 0, 362, 100, "social", L["What the guild sees of you"], L["Everything can be switched off - privacy-friendly defaults"])
    local yy = -56
    for _, r in ipairs(avail(L1)) do
        tg(LX, yy, r[1], r[2], r[3], r[2] == "rareShare" and function(v) S().cpRareShare = v end
            or (r[2] == "shareAltsOutside" and function() if ns.Radar and ns.Radar.SendHello then pcall(ns.Radar.SendHello) end end) or nil)
        yy = yy - ROW - (r[3] and DESC_H or 0)
    end
    c1:SetHeight(-yy + 6)
    -- top right: technical
    local L2 = {
        { "Error reports to the guild", "shareErrors", "Helps fix bugs" },
        { "Include list of other addons", "shareAddonList", "Only for debugging. Default: off" },
        { "Share performance data", "sharePerf", "Frame rate and memory, every 15 minutes" },
    }
    local c2 = cardH(f, RX, 0, 362, 100, "settings", L["Technical"], L["Error reports and network"], true)
    yy = -56
    for _, r in ipairs(avail(L2)) do
        tg(MX, yy, r[1], r[2], r[3])
        yy = yy - ROW - (r[3] and DESC_H or 0)
    end
    c2:SetHeight(-yy + 10)
    descInline = false
    local low = math.min(-(c1:GetHeight() or 0), yy - 10)
    resetButton(f, low - 16, function() if ns.Radar and ns.Radar.SendHello then pcall(ns.Radar.SendHello) end end)
    -- 0.5.675: Oasis network is always on - no toggle anymore
    -- 0.5.673: card "Nur auf diesem PC" removed - playtimes, online times, encounters always run, raid check without names
end
local function refreshShare(f)
    for _, t in ipairs(f.t) do if t.Refresh then t:Refresh() end end
end

-- 0.5.617: lists + map display (previously under "Teilen & Karte")

------------------------------------------------------------------------
-- Character
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Back up settings: export/import as text + saved profiles
-- own safe format (no loadstring): tables, strings, numbers, true/false
------------------------------------------------------------------------
local NOEXPORT = { mainPos = true, miniPos = true, toastPos = true, mainOpen = true, collapsed = true, lastPage = true,
    settingsTab = true, debug = true, adminTest = true, soundRecent = true, cardClosed = true }
local function ser(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("|", "\\p") .. '"'
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return v and "T" or "F"
    elseif t == "table" and depth < 6 then
        local parts = {}
        local keys = {}
        for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            if not (depth == 0 and NOEXPORT[k]) then
                local val = ser(v[k], depth + 1)
                if val then parts[#parts + 1] = ser(k, depth + 1) .. "=" .. val end
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end
-- Reader for exactly this format; returns nil on any error
local function deser(str)
    local pos = 1
    local function ws() pos = str:find("[^%s]", pos) or (#str + 1) end
    local val
    local function readString()
        pos = pos + 1
        local out = {}
        while pos <= #str do
            local ch = str:sub(pos, pos)
            if ch == '"' then pos = pos + 1 return table.concat(out) end
            if ch == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                out[#out + 1] = (n == "n" and "\n") or (n == "p" and "|") or n
                pos = pos + 2
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        error("string")
    end
    function val(depth)
        if depth > 8 then error("tief") end
        ws()
        local ch = str:sub(pos, pos)
        if ch == '"' then return readString()
        elseif ch == "T" then pos = pos + 1 return true
        elseif ch == "F" then pos = pos + 1 return false
        elseif ch == "{" then
            pos = pos + 1
            local t = {}
            ws()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                local k = val(depth + 1)
                ws()
                if str:sub(pos, pos) ~= "=" then error("=") end
                pos = pos + 1
                t[k] = val(depth + 1)
                ws()
                local c = str:sub(pos, pos)
                pos = pos + 1
                if c == "}" then return t end
                if c ~= "," then error(",") end
            end
        else
            local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then error("wert") end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local ok, res = pcall(function()
        local r = val(0)
        ws()
        if pos <= #str then error("rest") end
        return r
    end)
    if ok and type(res) == "table" then return res end
end
local PREFIX = "OASIS-EINSTELLUNGEN:1:"
local function exportString() return PREFIX .. ser(S()) end
-- apply: set values (positions etc. stay), then reapply everything
local function applySettings(t)
    local s = S()
    -- foreign text (e.g. copied from chat): only accept known types, sanitize strings
    for k, v in pairs(t) do
        if type(k) == "string" and #k <= 64 and not NOEXPORT[k] then
            local cur = s[k]
            if cur == nil or type(cur) == type(v) then
                if type(v) == "string" then v = ns.CleanText(v, 2000) end
                if type(v) ~= "number" or (v == v and v > -1e12 and v < 1e12) then s[k] = v end
            end
        end
    end
    if K.ApplyTheme then K.ApplyTheme() end
    if K.ApplyUserFonts then K.ApplyUserFonts() end
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    if ns.PlaceMinimap then ns.PlaceMinimap() end
    if ns.Admin then ns.Admin.ApplyBrand(true) end
    ns.After(0.3, function() if ns.RebuildMain then ns.RebuildMain() end end)
end
local function importString(str)
    str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if str:sub(1, #PREFIX) ~= PREFIX then return false end
    local t = deser(str:sub(#PREFIX + 1))
    if not t then return false end
    applySettings(t)
    return true
end
ns.SettingsIO = { Export = exportString, Import = importString,
    -- load a saved profile (Settings > Profile & Data)
    LoadPreset = function(name)
        local p = ns.db.presets and ns.db.presets[name]
        local t = p and deser(p.s)
        if t then applySettings(t) return true end
        return false
    end }

local function buildChar(f)
    f.noCompact = true
    local X = 14
    -- Left card: Profile ---------------------------------------------------
    card(f, 0, 0, 362, 470)
    section(f, L["Main and alts"], X, -12, 334)
    rowLabel(f, L["Main character"], X, -46)
    f.main = K.Button(f, "", 180, 24, "ghost")
    f.main.isDropdown = true
    f.main:SetPoint("TOPLEFT", X + 150, -42)
    f.main:SetScript("OnClick", function(self)
        local cur = ns.Alts.MyMain()
        local items = {}
        for _, c in ipairs(ns.Alts.MyChars()) do
            items[#items + 1] = { text = ns.displayName(c), checked = c == cur, fn = function() ns.Alts.SetMain(c) ns.RefreshPage("settings") end }
        end
        K.ShowMenu(self, items, nil, 180)
    end)
    note(f, L["Oasis detects your alts automatically after their first login."], X, -76, 334, C.muted)
    -- 0.5.794: the toggle "Twinks ausserhalb der Gilde zeigen" existed twice (here and under privacy, same setting) -
    -- now only under privacy; here a reference that jumps there
    f.altsLink = K.Button(f, L["Alts outside the guild: see Privacy"], 334, 22, "ghost", function() if page and page.SetTab then page.SetTab("share") end end)
    f.altsLink:SetPoint("TOPLEFT", X, -98)
    f.altsLink:SetHeight(20)
    -- alts on other WoW accounts confirmed by you: list with remove
    -- 0.5.874: sits in the "Main-Charakter" row; below it didn't fit (overlapped birthday) -> own narrow row directly under the reference
    f.extraAlts = K.Button(f, "", 334, 18, "ghost")
    f.extraAlts.isDropdown = true
    f.extraAlts:SetPoint("TOPLEFT", X, -122)
    local function extraLabel()
        local n = #ns.Alts.ExtraAlts()
        f.extraAlts:SetLabel((L["Alts on other accounts: %d"]):format(n))
        f.extraAlts:SetAlpha(n > 0 and 1 or 0.55)
    end
    f.extraAlts:SetScript("OnClick", function(self)
        local items = {}
        for _, n in ipairs(ns.Alts.ExtraAlts()) do
            items[#items + 1] = { text = ns.displayName(n) .. "  |cffd9786b" .. L["remove"] .. "|r", fn = function() ns.Alts.RemoveExtra(n) extraLabel() end }
        end
        if #items == 0 then items[1] = { text = L["None confirmed yet - the alt sets you as main with /oa twink."], disabled = true } end
        K.ShowMenu(self, items, L["Click removes the link"], 334)
    end)
    f.extraAlts:HookScript("OnShow", extraLabel)
    extraLabel()

    section(f, L["Birthday"], X, -144, 334)
    rowLabel(f, L["Birthday (DD.MM)"], X, -176)
    f.bstate = K.Text(f, 11, C.muted)
    f.bday = K.Input(f, 80, "12.10", function(t)
        if t == "" then
            ns.Members.SetBirthday(nil)
            f.bstate:SetText(L["not set"])
        elseif ns.Members.SetBirthday(t) then
            f.bstate:SetText("|cff66db9e" .. L["saved"] .. "|r")
        else
            f.bstate:SetText("|cffff5a4a" .. L["Format: DD.MM"] .. "|r")
        end
    end)
    f.bday:SetPoint("TOPLEFT", X + 150, -172)
    f.bstate:SetPoint("LEFT", f.bday, "RIGHT", 10, 0)
    note(f, L["Optional. The guild gets a notice on the day and can congratulate you."], X, -204, 334)

    -- 0.5.926: for every guild (previously only with the guild module) - data for your own website / Discord bot
    -- 0.5.956: guild module only again, as long as the export tools are not published
    if ns.ExternTools() then
        -- Guild website: provide data for OasisSync (package Oasis-Tools)
        section(f, L["Guild website"], X, -240, 334)
        f.webEx = K.Toggle(f, L["Provide data for the guild website"],
            function() return ns.Officer and ns.Officer.ExportWanted and ns.Officer.ExportWanted() or S().webExport == true end,
            function(v) S().webExport = v and true or false end)
        f.webEx:SetPoint("TOPLEFT", X, -270)
        f.webEx:SetWidth(334)
        note(f, L["Members, events, guild bank etc. are written to saved data on logout - OasisSync (folder Oasis/Tools) can send them to the guild website. Never included: officer notes, chats, whispers."], X, -300, 334)
    end

    -- 0.5.793: Oasis network (realm-wide channel) completely removed

    -- Right card: Backup -------------------------------------------------
    local RX, MX = 376, 390
    local rc = card(f, RX, 0, 362, 470)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["Back up settings"], MX, -12, 330)
    note(f, L["Your settings automatically apply to all characters on this account."], MX, -40, 330, C.muted)

    -- Export / Import
    rowLabel(f, L["As text"], MX, -78)
    f.io = K.Input(f, 330, L["Paste text here or click Export"])
    f.io:SetMaxLetters(0)
    f.io:SetPoint("TOPLEFT", MX, -100)
    f.ioState = K.Text(f, 11, C.muted)
    f.ioState:SetPoint("TOPLEFT", MX, -160)
    f.ioState:SetWidth(330)
    f.ioState:SetJustifyH("LEFT")
    local ex = K.Button(f, L["Export"], 120, 24, "primary", function()
        f.io:SetText(exportString())
        f.io:SetFocus()
        f.io:HighlightText()
        f.ioState:SetText("|cff66db9e" .. L["Selected - copy with Ctrl+C."] .. "|r")
    end)
    ex:SetPoint("TOPLEFT", MX, -130)
    local im = K.Button(f, L["Import"], 120, 24, "ghost", function()
        if importString(f.io:GetText()) then
            f.ioState:SetText("|cff66db9e" .. L["Applied."] .. "|r")
            f.io:SetText("")
        else
            f.ioState:SetText("|cffff5a4a" .. L["That is not a valid Oasis text."] .. "|r")
        end
    end)
    im:SetPoint("LEFT", ex, "RIGHT", 8, 0)

    -- Saved profiles
    section(f, L["Saved profiles"], MX, -194, 330)
    f.pname = K.Input(f, 200, L["Name, e.g. Raid night"])
    f.pname:SetPoint("TOPLEFT", MX, -226)
    local save = K.Button(f, L["Save"], 122, 24, "ghost", function()
        local n = (f.pname:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        ns.db.presets = ns.db.presets or {}
        ns.db.presets[n] = { s = ser(S()), ts = ns.now() }
        f.pname:SetText("")
        f.pname:ClearFocus()
        K.Toast(L["Profile saved"], n, C.mint)
        ns.RefreshPage("settings")
    end)
    save:SetPoint("LEFT", f.pname, "RIGHT", 8, 0)
    f.plist = K.List(f, 28, function(l)
        local r = K.Row(l)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 10, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -150, 0)
        r.name:SetWordWrap(false)
        r.when = K.Text(r, 10, C.dim, "RIGHT")
        r.when:SetPoint("RIGHT", -150, 0)
        r.load = K.Button(r, L["Load"], 70, 20, "ghost", function()
            local p = r.item and ns.db.presets and ns.db.presets[r.item.name]
            local t = p and deser(p.s)
            if t then applySettings(t) K.Toast(L["Profile loaded"], r.item.name, C.mint) end
        end)
        r.load:SetPoint("RIGHT", -64, 0)
        r.del = K.Button(r, L["Put out"], 56, 20, "danger", function()
            if not r.item then return end
            -- click twice to delete
            if r.armed ~= r.item.name then
                r.armed = r.item.name
                r.del:SetLabel(L["Sure?"])
                ns.After(3, function() r.armed = nil if r.del then r.del:SetLabel(L["Put out"]) end end)
                return
            end
            ns.db.presets[r.item.name] = nil
            r.armed = nil
            ns.RefreshPage("settings")
        end)
        r.del:SetPoint("RIGHT", -4, 0)
        return r
    end, function(r, p)
        r.name:SetText(p.name)
        r.when:SetText(p.ts and ns.ago(p.ts) or "")
        r.del:SetLabel(r.armed == p.name and L["Sure?"] or L["Put out"])
    end)
    f.plist:SetPoint("TOPLEFT", MX - 4, -258)
    f.plist:SetPoint("BOTTOMRIGHT", rc, "BOTTOMRIGHT", -10, 10)
    f.plist.empty:SetText(L["No profiles saved yet."])
end
local function refreshChar(f)
    f.main:SetLabel(ns.displayName(ns.Alts.MyMain()))
    if not f.bday:HasFocus() then
        f.bday:SetText(S().birthday or "")
        if f.bstate:GetText() == nil or f.bstate:GetText() == "" then f.bstate:SetText(S().birthday and "" or L["optional"]) end
    end
    local list = {}
    for n, p in pairs(ns.db.presets or {}) do list[#list + 1] = { name = n, ts = p.ts } end
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    f.plist:SetData(list)
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------
-- Display names of the saved collections
local STORE_NAMES = {
    orders = "Crafting orders", events = "Events", signups = "Sign-ups", chronicle = "Chronicle",
    loot = "Loot", campCatalog = "Buff catalog", campfires = "Campfire", wants = "Wish list",
    lfg = "Group searches", duels = "Dice games", notices = "Announcements", guildcfg = "Gilden-Einstellungen",
    audit = "Leadership log", bank = "Guild bank tabs", banklog = "Guild bank log",
    bankworth = "Bank value history", deaths = "Graveyard", links = "Links", points = "Loot points",
    posts = "Oasigram posts", prices = "Market prices", raidplan = "Raid plans", rep = "Player book ratings",
    votes = "Poll votes", polls = "Polls", likes = "Likes", comments = "Comments", follows = "Follows",
    flights = "Flight points", mapcal = "Map events", wtrain = "Weapon masters", rpreq = "Reputation requests", invites = "Invites",
    reacts = "Reactions", lfgreq = "Group requests", chatpin = "Pinned in chat", attend = "Raid attendance", formers = "Former members",
    tactics = "Boss tactics", nodes = "Gather nodes", bans = "Bans", sndmute = "Sound mutes", recruits = "Recruits", sres = "Reservations",
    trace = "Dungeon traces", raidint = "Raid interest", bugs = "Bug reports", ggoals = "Guild goals", ggcontrib = "Guild goal contributions",
    talents = "Talents", scout = "Recruiting suggestions", perf = "Performance samples", combat = "Combat records", profcd = "Profession cooldowns",
    coll_chars = "Collections: characters", coll_mounts = "Collections: mounts", coll_pets = "Collections: pets", coll_toys = "Collections: toys",
    gearmatch = "Upgrade Exchange", lockouts = "Raid Lockouts", qitems = "Quest items", rtweek = "Raid Time", repfac = "Reputation Planner",
}
local function buildStatus(f)
    -- 0.5.570: glass cards with header, data list fits into the card (previously 30 rows ran off the bottom, headings were missing)
    f.noCompact = true
    local hc = card(f, 0, 0, 738, 104)
    hc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    f.logo = ns.Wordmark(hc, 160, 40, false)   -- 0.5.683: this is about the addon, not the guild -> Oasis wordmark
    f.logo:SetPoint("LEFT", hc, "LEFT", 22, 0)
    f.ver = K.Title(hc, 16, C.text)
    f.ver:SetPoint("TOPLEFT", hc, "TOPLEFT", 214, -20)
    f.guild = K.Text(hc, 12, C.muted)
    f.guild:SetPoint("TOPLEFT", f.ver, "BOTTOMLEFT", 0, -6)
    f.author = K.Text(hc, 11, C.dim)
    f.author:SetPoint("TOPLEFT", f.guild, "BOTTOMLEFT", 0, -5)
    f.author:SetText(L["Developed by"] .. " " .. K.hex(C.accent) .. "Oasis Addons|r")
    f.lead = K.Text(hc, 11, C.amber)
    f.lead:SetPoint("TOPLEFT", f.author, "BOTTOMLEFT", 0, -5)
    f.tour = K.Button(hc, L["Start tour"], 140, 24, "ghost", function() if ns.Onboarding then ns.Onboarding.Show() end end)
    f.tour:SetPoint("RIGHT", hc, "RIGHT", -18, 16)
    -- 0.5.949: sample data for everyone - for trying out and setting up before your own guild has data
    f.demoBtn = K.Button(hc, "", 140, 24, "ghost", function(self)
        if not ns.Demo then return end
        if ns.Demo.IsActive() then ns.Demo.Remove() else ns.Demo.Load() end
        self:Refresh()
        if ns.UpdateDemoSwitch then ns.UpdateDemoSwitch() end
    end)
    f.demoBtn:SetPoint("RIGHT", hc, "RIGHT", -18, -16)
    function f.demoBtn:Refresh()
        local on = ns.Demo and ns.Demo.IsActive()
        self.label:SetText(on and L["Remove sample data"] or L["Show sample data"])
    end
    f.demoBtn:Refresh()
    f.demoBtn:HookScript("OnShow", function(self) self:Refresh() end)
    f.demoBtn:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Sample data"],
            L["Fills Oasis with sample members, events, chronicle, polls etc. Stays on your client only and is never sent to the guild."],
            L["While they are on, the window shows 'Demo on' at the top. One click there or here removes everything again."] })
    end)
    f.demoBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.5.996: developer - leadership rights (guild leadership, officers, raid leadership) via button instead of only /oa testleitung
    f.devLead = K.Button(hc, "", 170, 24, "ghost", function(self)
        if ns.slash.testleitung then ns.slash.testleitung() end
        self:Refresh()
        ns.RefreshPage("settings")
    end)
    f.devLead:SetPoint("RIGHT", f.tour, "LEFT", -10, 0)
    function f.devLead:Refresh()
        local dev = ns.IsDev and ns.IsDev()
        self:SetShown(dev and true or false)
        local on = ns.Admin and ns.Admin.TestMode()
        self.label:SetText(on and L["Leadership rights off"] or L["Leadership rights on"])
    end
    f.devLead:Refresh()
    f.devLead:HookScript("OnShow", function(self) self:Refresh() end)
    f.devLead:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Leadership rights (developer)"],
            L["On this PC you are treated like the guild master: guild leadership, officer and raid leader settings are unlocked."],
            L["Others do NOT see changes saved for the guild - their Oasis checks your real rank."] })
    end)
    f.devLead:HookScript("OnLeave", function() GameTooltip:Hide() end)

    f.tiles = {}
    local labels = { L["Known profiles"], L["Recipe lists"], L["Legacy data"], L["Last sync"] }
    for i, lab in ipairs(labels) do
        local t = K.StatCard(f, lab)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 186, -118)
        t:SetSize(176, 56)
        f.tiles[i] = t
    end

    -- Saved data: 2 columns x 9 rows, largest first
    local ROWS = 9
    local dc = cardH(f, 0, -188, 470, 56 + ROWS * 20 + 14, "stats", L["Stored data"], L["What Oasis currently knows from the guild"])
    f.dataRows = {}
    for i = 1, ROWS * 2 do
        local col, row = math.floor((i - 1) / ROWS), (i - 1) % ROWS
        local x = 14 + col * 226
        local name = K.Text(dc, 12, C.muted)
        name:SetPoint("TOPLEFT", dc, "TOPLEFT", x, -58 - row * 20)
        name:SetWidth(168)
        name:SetWordWrap(false)
        name:SetJustifyH("LEFT")
        local val = K.Text(dc, 12, C.text, "RIGHT")
        val:SetPoint("TOPRIGHT", dc, "TOPLEFT", x + 214, -58 - row * 20)
        f.dataRows[i] = { name = name, val = val }
    end
    f.dataEmpty = K.Text(dc, 12, C.dim)
    f.dataEmpty:SetPoint("TOPLEFT", 14, -60)
    f.dataEmpty:SetText(L["No data from the guild yet."])

    -- Connection
    local cc = cardH(f, 484, -188, 254, 56 + ROWS * 20 + 14, "sync", L["Connection"], L["Exchange with the guild"], true)
    f.netDot = cc:CreateTexture(nil, "ARTWORK")
    f.netDot:SetTexture(ns.MEDIA .. "dot")
    f.netDot:SetSize(9, 9)
    f.netDot:SetPoint("TOPLEFT", 14, -64)
    f.netState = K.Text(cc, 12, C.text)
    f.netState:SetPoint("LEFT", f.netDot, "RIGHT", 8, 0)
    f.net = {}
    for i, lab in ipairs({ L["Sent"], L["Received"], L["Queue"] }) do
        local n = K.Text(cc, 12, C.muted)
        n:SetPoint("TOPLEFT", cc, "TOPLEFT", 14, -90 - (i - 1) * 22)
        n:SetText(lab)
        local v = K.Text(cc, 12, C.text, "RIGHT")
        v:SetPoint("TOPRIGHT", cc, "TOPRIGHT", -14, -90 - (i - 1) * 22)
        f.net[i] = v
    end
    note(cc, L["Oasis only exchanges data with guild members who also use Oasis. Exchange pauses in combat and instances."], 14, -162, 226, C.dim)
    -- Credits and licenses at the bottom (Core/Start/Credits.lua, loads after this file - it exists when the tab is built)
    if ns.Credits and ns.Credits.Build then
        local ok, e = pcall(ns.Credits.Build, f, 0, -188 - (56 + ROWS * 20 + 14) - 26, 738)
        if not ok then ns.err(L["Setup"] .. " settings/credits", e) end
    end
end
local function refreshStatus(f)
    local guild = IsInGuild() and (GetGuildInfo("player") or "?") or L["no guild"]
    local _, rankName = GetGuildInfo("player")
    f.ver:SetText("OASIS  " .. K.hex(C.accent) .. ns.version .. "|r")
    f.guild:SetText(L["Guild: "] .. "|cffffffff" .. guild .. "|r" .. (rankName and ("   |cff888888" .. rankName .. "|r") or ""))
    f.lead:SetText(ns.Admin and ns.Admin.CanManage() and L["You have access to Guild Leadership."] or "")
    if f.devLead then f.devLead:Refresh() end

    local members, recipes, legacy = 0, 0, 0
    for _ in pairs(ns.db.members) do members = members + 1 end
    for _ in pairs(ns.db.recipes) do recipes = recipes + 1 end
    for _ in pairs(ns.db.legacy) do legacy = legacy + 1 end
    f.tiles[1]:Set(members)
    f.tiles[2]:Set(recipes)
    f.tiles[3]:Set(legacy)
    f.tiles[4]:Set(ns.ago(ns.db.meta.lastSync ~= 0 and ns.db.meta.lastSync or nil))

    local list = {}
    for name, coll in pairs(ns.db.store) do
        local n = 0
        for _, r in pairs(coll) do if not r.del then n = n + 1 end end
        if n > 0 then list[#list + 1] = { L[STORE_NAMES[name] or name], n } end
    end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local nr = #f.dataRows
    for i, row in ipairs(f.dataRows) do
        local e = list[i]
        if i == nr and #list > nr then
            -- last cell: summarize the rest
            local rest = 0
            for j = nr, #list do rest = rest + list[j][2] end
            row.name:SetText("|cff888888" .. (L["+%d more"]):format(#list - nr + 1) .. "|r")
            row.val:SetText(rest)
        else
            row.name:SetText(e and e[1] or "")
            row.val:SetText(e and e[2] or "")
        end
    end
    f.dataEmpty:SetShown(#list == 0)

    local blocked = Comm.restricted()
    local c = blocked and C.amber or C.mint
    f.netDot:SetVertexColor(c[1], c[2], c[3])
    f.netState:SetText(blocked and L["Paused (combat/instance)"] or L["Ready"])
    f.net[1]:SetText(Comm.sent)
    f.net[2]:SetText(Comm.received)
    f.net[3]:SetText(Comm.QueueSize())
end

------------------------------------------------------------------------
local BUILD = { general = buildGeneral, pages = buildPages, look = buildLook, toasts = buildToasts, sound = buildSound, share = buildShare, char = buildChar, status = buildStatus }
local REFRESH = { general = refreshGeneral, pages = refreshPages, look = refreshLook, toasts = refreshToasts, sound = refreshSound, share = refreshShare, char = refreshChar, status = refreshStatus }
-- Tab "Leiste": what the pinned Oasis bar shows
local function buildBar(f)
    -- 0.5.549: topbar page in glass style, full width (page scrolls); the real bar is visible meanwhile
    f.noCompact = true
    f:HookScript("OnShow", function() if ns.PreviewMiniBar then ns.PreviewMiniBar(true) end end)
    f:HookScript("OnHide", function() if ns.PreviewMiniBar then ns.PreviewMiniBar(false) end end)
    local LX = 16
    local function cardW(y, h, icon, title, sub)
        local c = cardH(f, 0, y, 740, h, icon, title, sub)
        c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
        return c
    end
    local function glassOn(b, r)
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, b, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.09 }, r or 10)) then K.Fill(b, { 1, 1, 1, 0.03 }) K.Border(b, C.line) end
    end
    local function selQuick(k, v)
        local sel = S().miniPages
        if sel == nil then
            sel = {}
            for kk, on in pairs(ns.MINI_QUICK_DEFAULT) do sel[kk] = on end
            S().miniPages = sel
        end
        sel[k] = v or nil
        if ns.UpdateMiniBar then ns.UpdateMiniBar() end
        for _, t in ipairs(f.qt or {}) do t:Refresh() end
    end
    local panelIcon, panelLabel = {}, {}
    for _, pq in ipairs(ns.MINI_QUICK_PANELS or {}) do panelIcon[pq.key] = pq.icon panelLabel[pq.key] = pq.label end
    local function iconOf(k)
        if panelIcon[k] then return panelIcon[k], true end
        if k == "mark" then return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", true end
        return (ns.ICONS and ns.ICONS[k]) or (ns.MEDIA .. "icons\\home"), false
    end
    local function labelOf(k)
        if panelLabel[k] then return L[panelLabel[k]] end
        if k == "mark" then return L["Auto marker (in group)"] end
        local def = ns.PageDef and ns.PageDef(k)
        return def and L[def.title] or k
    end
    -- Choice tile (title, text, optional icon + drawing), group with :Select
    local function choiceGroup(list, x, y, w, h, onPick)
        local g = { btns = {} }
        for i, it in ipairs(list) do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(w, h)
            b:SetPoint("TOPLEFT", x + (i - 1) * (w + 12), y)
            glassOn(b, 10)
            b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 3)
            b.tint:SetPoint("TOPLEFT", 3, -3) b.tint:SetPoint("BOTTOMRIGHT", -3, 3)
            b.bar = b:CreateTexture(nil, "ARTWORK")
            b.bar:SetPoint("TOPLEFT", 3, -3) b.bar:SetPoint("BOTTOMLEFT", 3, 3) b.bar:SetWidth(3)
            if it.icon then
                b.ic = K.Glyph(b, 16, ns.MEDIA .. "icons\\" .. it.icon, C.muted)
                b.ic:SetPoint("TOPLEFT", 14, -12)
            end
            b.t = K.Title(b, 13, C.text)
            b.t:SetPoint("TOPLEFT", it.icon and 38 or 14, -12)
            b.t:SetText(it.text)
            b.d = K.Text(b, 10, C.dim)
            b.d:SetPoint("TOPLEFT", b.t, "BOTTOMLEFT", 0, -5)
            b.d:SetPoint("RIGHT", it.draw and -(w * 0.45) or -12, 0)
            b.d:SetJustifyH("LEFT")
            b.d:SetWordWrap(true)
            b.d:SetText(it.desc or "")
            if it.draw then it.draw(b, w, h) end
            b.key = it.key
            b:SetScript("OnClick", function(self)
                onPick(self.key) g:Select(self.key)
                if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            end)
            b:SetScript("OnEnter", function(self) if not self.on then self.tint:SetColorTexture(1, 1, 1, 0.05) end end)
            b:SetScript("OnLeave", function(self) if not self.on then self.tint:SetColorTexture(1, 1, 1, 0) end end)
            g.btns[i] = b
        end
        function g:Select(key)
            local ac = C.accent
            for _, b in ipairs(self.btns) do
                b.on = b.key == key
                b.tint:SetColorTexture(ac[1], ac[2], ac[3], b.on and 0.12 or 0)
                b.bar:SetColorTexture(ac[1], ac[2], ac[3], 1)
                b.bar:SetShown(b.on)
                local c = b.on and C.text or C.muted
                b.t:SetTextColor(c[1], c[2], c[3])
                if b.ic then local ic = b.on and ac or C.muted b.ic:SetVertexColor(ic[1], ic[2], ic[3]) end
                if b.mini then b.mini:SetVertexColor(ac[1], ac[2], ac[3], b.on and 1 or 0.45) end
            end
        end
        return g
    end
    -- small screen drawing for the style tiles
    local function screen(b, w, h, full, kind)
        local sw, sh = 120, h - 22
        local sc = b:CreateTexture(nil, "ARTWORK")
        sc:SetSize(sw, sh)
        sc:SetPoint("RIGHT", -14, 0)
        sc:SetColorTexture(0, 0, 0, 0.45)
        local brd = CreateFrame("Frame", nil, b)
        brd:SetAllPoints(sc)
        K.Border(brd, { 1, 1, 1, 0.12 })
        b.mini = b:CreateTexture(nil, "OVERLAY")
        if full then
            b.mini:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0) b.mini:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, 0) b.mini:SetHeight(5)
        elseif kind == "minimal" then
            b.mini:SetSize(26, 5) b.mini:SetPoint("TOP", sc, "TOP", 0, -3)
        elseif kind == "dock" then
            b.mini:SetSize(62, 10) b.mini:SetPoint("BOTTOM", sc, "BOTTOM", 0, 3)
        else
            b.mini:SetSize(48, 7) b.mini:SetPoint("TOP", sc, "TOP", 0, -3)
        end
        b.mini:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    -- Toggle tile (as under Oasis > Details)
    local function optTile(x, y, w, icon, title, desc, key, after)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(w, 58)
        b:SetPoint("TOPLEFT", x, y)
        glassOn(b, 10)
        b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 3)
        b.tint:SetPoint("TOPLEFT", 3, -3) b.tint:SetPoint("BOTTOMRIGHT", -3, 3)
        b.ic = K.Glyph(b, 15, ns.MEDIA .. "icons\\" .. icon, C.muted)
        b.ic:SetPoint("TOPLEFT", 12, -11)
        b.t = K.Title(b, 12, C.text)
        b.t:SetPoint("LEFT", b.ic, "RIGHT", 8, 0)
        b.t:SetText(L[title])
        b.d = K.Text(b, 10, C.dim)
        b.d:SetPoint("TOPLEFT", 12, -32)
        b.d:SetPoint("RIGHT", -12, 0)
        b.d:SetJustifyH("LEFT")
        b.d:SetText(L[desc])
        b.sw = K.Pill(b, 24, 13)
        b.sw:SetPoint("TOPRIGHT", -10, -12)
        b.knob = K.KnobCircle(b.sw, 10)
        function b:Refresh()
            local on = S()[key] and true or false
            local ac = C.accent
            self.tint:SetColorTexture(ac[1], ac[2], ac[3], on and 0.12 or 0)
            self.sw:SetColor(on and ac[1] or 0.25, on and ac[2] or 0.25, on and ac[3] or 0.27, 1)
            self.knob:ClearAllPoints()
            self.knob:SetPoint("CENTER", self.sw, on and "RIGHT" or "LEFT", on and -6 or 6, 0)
            local ic = on and ac or C.muted
            self.ic:SetVertexColor(ic[1], ic[2], ic[3])
            local tc = on and C.text or C.muted
            self.t:SetTextColor(tc[1], tc[2], tc[3])
        end
        b:SetScript("OnClick", function(self)
            S()[key] = not S()[key] or nil
            if after then pcall(after) end
            self:Refresh()
            if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        end)
        b:SetScript("OnEnter", function(self) self.tint:SetAlpha(1.6) K.ShowTip(self, { L[title], L[desc] }) end)
        b:SetScript("OnLeave", function(self) self.tint:SetAlpha(1) GameTooltip:Hide() end)
        indexAdd(L[title], b, L[desc])
        return b
    end

    -- When does the bar appear? -------------------------------------------
    -- 0.5.555: two columns - left When + Style, right Bar + Buttons
    local RXc, RX0 = 376, 392
    local function stackY(g, gap)
        -- Tiles of a group stacked instead of side by side
        for i, b in ipairs(g.btns) do
            local _, _, _, x, y = b:GetPoint(1)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", LX, g.y0 - (i - 1) * (b:GetHeight() + gap))
        end
    end
    cardH(f, 0, 0, 362, 50 + 3 * 54 + 8, "pin", L["When does the top bar show?"], L["The real bar above shows every change instantly"])
    f.modeSeg = choiceGroup({
        { key = "collapse", text = L["On close"], desc = L["window X collapses"], icon = "home" },
        { key = "always", text = L["Always"], desc = L["there from login"], icon = "star_on" },
        { key = "off", text = L["Never"], desc = L["window only"], icon = "eye_off" },
    }, LX, -50, 330, 48, function(k)
        S().topbarMode = (k ~= "collapse") and k or nil
        if ns.ApplyTopbarMode then ns.ApplyTopbarMode() end
    end)
    f.modeSeg.y0 = -50
    stackY(f.modeSeg, 6)
    indexAdd(L["When does the top bar show?"], f.modeSeg.btns[1], L["Always show the top bar or never"])

    -- Style ----------------------------------------------------------------
    local YS = -(50 + 3 * 54 + 8) - 14
    cardH(f, 0, YS, 362, 50 + 4 * 66 + 8, "brush", L["Style"], L["How the bar looks - the real bar above changes instantly"])
    f.styleSeg = choiceGroup({
        { key = "normal", text = L["Normal"], desc = L["slim, movable"], draw = function(b, w, h) screen(b, w, h, false) end },
        { key = "compact", text = L["Compact"], desc = L["full width, with clock"], draw = function(b, w, h) screen(b, w, h, true) end },
        { key = "minimal", text = L["Minimal"], desc = L["icons only, very slim"], draw = function(b, w, h) screen(b, w, h, false, "minimal") end },
        { key = "dock", text = L["Dock"], desc = L["big icons, grow on hover"], draw = function(b, w, h) screen(b, w, h, false, "dock") end },
    }, LX, YS - 50, 330, 60, function(k)
        S().miniStyle = (k ~= "normal") and k or nil
        if ns.UpdateMiniBarNow then pcall(ns.UpdateMiniBarNow) end
    end)
    f.styleSeg.y0 = YS - 50
    stackY(f.styleSeg, 6)
    indexAdd(L["Style"], f.styleSeg.btns[2], L["Compact top bar across the full screen width"])

    -- Bar ---------------------------------------------------------------
    local Y2 = 0
    cardH(f, RXc, Y2, 362, 292, "settings", L["Bar"], nil, true)
    f.autoHide = optTile(RX0, Y2 - 46, 330, "eye_off", "Roll up", "only the edge stays visible, mouse at the top brings it back", "miniAutoHide",
        function() if ns.PlaceMiniBar then ns.PlaceMiniBar() end end)
    f.noLogo = optTile(RX0, Y2 - 110, 330, "chronicle", "Hide logo", "Bar without the wordmark, clicking on the left still expands it", "miniNoLogo",
        function() if ns.UpdateMiniBar then ns.UpdateMiniBar() end end)
    rowLabel(f, L["Background"], RX0, Y2 - 182)
    f.miniAlpha = K.Slider(f, 200, 0.1, 1, 0.05, function() return S().miniAlpha or 1 end,
        function(v) S().miniAlpha = v if ns.ApplyMiniAlpha then ns.ApplyMiniAlpha() end end,
        function(v) return (L["%d %%"]):format(v * 100 + 0.5) end)
    f.miniAlpha:SetPoint("TOPLEFT", RX0 + 110, Y2 - 180)
    indexAdd(L["Top bar transparency"], f.miniAlpha, L["How transparent the top bar is"])
    rowLabel(f, L["Size"], RX0, Y2 - 214)
    f.miniScale = K.Slider(f, 200, 0.6, 1.6, 0.05, function() return S().miniScale or 1 end,
        function(v) S().miniScale = v if ns.UpdateMiniBarNow then pcall(ns.UpdateMiniBarNow) elseif ns.UpdateMiniBar then ns.UpdateMiniBar() end end,
        function(v) return (L["%d%%"]):format(v * 100 + 0.5) end)
    f.miniScale:SetPoint("TOPLEFT", RX0 + 110, Y2 - 212)
    indexAdd(L["Topbar size"], f.miniScale, L["How big the topbar is"])
    local c = K.Button(f, L["Collapse now"], 158, 24, "ghost", function() if ns.Collapse then ns.Collapse(true) end end)
    c:SetPoint("TOPLEFT", RX0, Y2 - 248)
    local r = K.Button(f, L["Reset position"], 164, 24, "ghost", function()
        S().miniPos = nil
        if ns.HideMiniBar and ns.ShowMiniBar then ns.HideMiniBar() ns.ShowMiniBar() end
    end)
    r:SetPoint("LEFT", c, "RIGHT", 8, 0)

    -- Buttons in the bar ------------------------------------------------
    local keys = {}
    for _, k in ipairs(ns.MINI_QUICK_ALL or {}) do if ns.PageDef and ns.PageDef(k) then keys[#keys + 1] = k end end
    keys[#keys + 1] = "mark"
    for _, pq in ipairs(ns.MINI_QUICK_PANELS or {}) do keys[#keys + 1] = pq.key end
    local PER, CW, CHh = 2, 162, 28
    local Y3 = Y2 - 306
    cardH(f, RXc, Y3, 362, 58 + math.ceil(#keys / PER) * (CHh + 5), "modules", L["Buttons in the bar"], L["Click toggles a button"], true)
    f.qt = {}
    for i, k in ipairs(keys) do
        local col, row = (i - 1) % PER, math.floor((i - 1) / PER)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(CW, CHh)
        b:SetPoint("TOPLEFT", RX0 + col * (CW + 6), Y3 - 50 - row * (CHh + 5))
        glassOn(b, 8)
        b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 3)
        b.tint:SetPoint("TOPLEFT", 2, -2) b.tint:SetPoint("BOTTOMRIGHT", -2, 2)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT", 2, -4) b.bar:SetPoint("BOTTOMLEFT", 2, 4) b.bar:SetWidth(3)
        local tex, raw = iconOf(k)
        b.ic = b:CreateTexture(nil, "ARTWORK")
        b.ic:SetTexture(tex)
        b.ic:SetSize(16, 16)
        b.ic:SetPoint("LEFT", 12, 0)
        b.raw = raw
        b.t = K.Text(b, 11, C.muted)
        b.t:SetPoint("LEFT", b.ic, "RIGHT", 7, 0)
        b.t:SetPoint("RIGHT", -8, 0)
        b.t:SetJustifyH("LEFT")
        b.t:SetWordWrap(false)
        b.t:SetText(labelOf(k))
        b.key = k
        function b:Refresh()
            local on = ns.MiniQuickOn(self.key)
            local ac = C.accent
            self.tint:SetColorTexture(ac[1], ac[2], ac[3], on and 0.10 or 0)
            self.bar:SetColorTexture(ac[1], ac[2], ac[3], 1)
            self.bar:SetShown(on)
            local c2 = on and C.text or C.dim
            self.t:SetTextColor(c2[1], c2[2], c2[3])
            if self.raw then self.ic:SetDesaturated(not on) self.ic:SetAlpha(on and 1 or 0.4)
            else local ic = on and C.text or C.dim self.ic:SetVertexColor(ic[1], ic[2], ic[3]) end
        end
        b:SetScript("OnClick", function(self)
            selQuick(self.key, not ns.MiniQuickOn(self.key))
            if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        end)
        b:SetScript("OnEnter", function(self) self.tint:SetAlpha(1.8) end)
        b:SetScript("OnLeave", function(self) self.tint:SetAlpha(1) end)
        indexAdd(labelOf(k), b, L["Buttons in the bar"])
        f.qt[#f.qt + 1] = b
    end
end
local function refreshBar(f)
    if f.styleSeg then f.styleSeg:Select(ns.MiniStyle and ns.MiniStyle() or "normal") end
    if f.autoHide then f.autoHide:Refresh() end
    if f.noLogo then f.noLogo:Refresh() end
    if f.modeSeg then f.modeSeg:Select(ns.TopbarMode and ns.TopbarMode() or "collapse") end
    if f.miniAlpha and f.miniAlpha.Refresh then f.miniAlpha:Refresh() end
    if f.miniScale and f.miniScale.Refresh then f.miniScale:Refresh() end
    if ns.PreviewMiniBar and f:IsVisible() then ns.PreviewMiniBar(true) end
    for _, t in ipairs(f.qt or {}) do t:Refresh() end
end
BUILD.bar, REFRESH.bar = buildBar, refreshBar
table.insert(TABS, #TABS, { key = "bar", text = "Top bar" })

-- further tabs from other modules (register before the settings are first opened)
function ns.AddSettingsTab(key, text, build, refresh)
    if BUILD[key] then return end
    table.insert(TABS, #TABS, { key = key, text = text })   -- before "Status"
    BUILD[key] = build
    REFRESH[key] = refresh or function() end
end
ns.SettingsHelpers = { section = section, note = note, toggle = toggle, rowLabel = rowLabel, cardH = cardH }

-- Tighten spacing: stack each column's elements more tightly in order (only large gaps)
compact = function(fr, inBox)
    if fr.noCompact and not inBox then return end
    local items = {}
    local function scan(obj)
        if not obj.GetNumPoints or obj:GetNumPoints() ~= 1 then return end
        local pt, rel, rp, x, y = obj:GetPoint(1)
        if pt == "TOPLEFT" and rel == fr and rp == "TOPLEFT" and type(y) == "number" and obj:IsShown() then
            items[#items + 1] = { o = obj, x = math.floor(x + 0.5), y = y, h = obj:GetHeight() or 20 }
        end
    end
    for _, c in ipairs({ fr:GetChildren() }) do scan(c) end
    for _, r in ipairs({ fr:GetRegions() }) do scan(r) end
    local cols = {}
    -- two columns (left/right); elements of the same row move together
    for _, it in ipairs(items) do local cx = it.x < 380 and 0 or 1 cols[cx] = cols[cx] or {} table.insert(cols[cx], it) end
    local maxShift = 0
    for _, list in pairs(cols) do
        table.sort(list, function(a, b) if a.y ~= b.y then return a.y > b.y end return a.x < b.x end)
        local shift = 0
        for i, it in ipairs(list) do
            if i > 1 then
                local prev = list[i - 1]
                local gap = (prev.y - it.y) - prev.h
                local want = (prev.h <= 2) and 8 or 6    -- a bit more after separator lines
                if gap > want + 6 then shift = shift + (gap - want) end
            end
            if shift > 0 then
                local pt, rel, rp, x = it.o:GetPoint(1)
                it.o:ClearAllPoints()
                it.o:SetPoint(pt, rel, rp, x, it.y + shift)
            end
        end
        if shift > maxShift then maxShift = shift end
    end
    return maxShift
end
-- Topic picker: guild organization, social activities and personal helpers kept separate.
-- Design, notifications, privacy and technical module management have their own topics.
local GROUPS = {
    { key = "start", text = "Overview", icon = "home", tabs = { "quick" },
        desc = "Choose a topic or search for a setting directly." },
    { key = "guild", text = "Guild & organisation", icon = "modules", tabs = { "guildtools", "helpers" },
        desc = "Members, events, raids, crafting and shared guild goals." },
    { key = "social", text = "Socialising", icon = "social", tabs = { "socialtools", "greet" },
        desc = "Meet people, find groups and do things together." },
    { key = "help", text = "My convenience", icon = "checklist", tabs = { "personaltools", "comfort", "gamechat", "mapset", "tips", "keys" },
        desc = "Personal helpers, chat, maps and tooltips for everyday play." },
    { key = "look", text = "Look & controls", icon = "brush", tabs = { "look", "general", "bar", "ownmedia" },
        desc = "Adjust the design, font, window and bars to your play style." },
    { key = "notify", text = "Notices & sound", icon = "announce", tabs = { "toasts", "sound" },
        desc = "Choose what you hear about, how it looks and how it sounds." },
    { key = "char", text = "Profile & privacy", icon = "profile", tabs = { "char", "share", "lexport" },
        desc = "Link characters, control shared data and back up settings." },
    { key = "adv", text = "System & modules", icon = "settings", tabs = { "modules", "status", "perf" },
        desc = "Load modules, check connectivity and adjust performance." },
}
for _, entry in ipairs({
    { "guildtools", "Guild tools", "guild" },
    { "socialtools", "Together", "social" },
    { "personaltools", "My tools", "personal" },
}) do
    local scope = entry[3]
    BUILD[entry[1]] = function(f) buildPages(f, scope) end
    REFRESH[entry[1]] = refreshPages
    TABS[#TABS + 1] = { key = entry[1], text = entry[2] }
end
local HIDDEN_TABS = { lists = true, pages = true }   -- still reachable (old links), but without its own tab
local function tabText(key)
    for _, t in ipairs(TABS) do if t.key == key then return L[t.text] end end
    return key
end
-- Tabs of a group that really exist (modules register via AddSettingsTab; unknown -> game aids)
local function groupTabs(g)
    if g.dev and not (ns.IsDev and ns.IsDev()) then return {} end
    local out, known = {}, {}
    for _, gg in ipairs(GROUPS) do for _, k in ipairs(gg.tabs) do known[k] = true end end
    for _, k in ipairs(g.tabs) do if BUILD[k] and (k ~= "perf" or (ns.IsDev and ns.IsDev())) then out[#out + 1] = k end end   -- 0.6.523: performance only for developers
    if g.key == "help" then
        for _, t in ipairs(TABS) do if not known[t.key] and not HIDDEN_TABS[t.key] and BUILD[t.key] then out[#out + 1] = t.key end end
    end
    return out
end
local function groupOf(key)
    for _, g in ipairs(GROUPS) do for _, k in ipairs(groupTabs(g)) do if k == key then return g end end end
    return GROUPS[1]
end
local function tabTop(g) return page and page.contentTop or -194 end
local function setTab(key)
    if not page then return end
    if key == "lists" then key = "mapset" elseif key == "pages" then key = "guildtools" end   -- old links to "Listen & Karte"
    if not BUILD[key] then key = "quick" end
    page.tab = key
    local g = groupOf(key)
    page.group = g.key
    if page.UpdateNav then page:UpdateNav(g, key) end
    local top = tabTop(g)
    page.scrolls = page.scrolls or {}
    for k, fr in pairs(page.tabs) do
        fr:SetShown(k == key)
        if page.scrolls[k] then page.scrolls[k]:SetShown(k == key) end
    end
    if not page.tabs[key] then
        -- 0.5.538: every page sits in a scroll area - if the content is taller than the window, the mouse wheel scrolls
        local sc = CreateFrame("ScrollFrame", nil, page)
        sc:SetPoint("TOPLEFT", 0, top)
        sc:SetPoint("BOTTOMRIGHT")
        local fr = CreateFrame("Frame", nil, sc)
        fr:SetSize(math.max(300, page:GetWidth() or 740), math.max(200, (page:GetHeight() or 560) + top))
        sc:SetScrollChild(fr)
        sc.thumb = sc:CreateTexture(nil, "OVERLAY")
        sc.thumb:SetWidth(3)
        sc.thumb:SetColorTexture(1, 1, 1, 0.18)
        sc.thumb:Hide()
        local function measure()
            local h = sc:GetHeight() or 0
            if h < 50 then return end
            fr:SetWidth(math.max(300, sc:GetWidth() or 740))
            local top0 = fr:GetTop()
            local low
            local function see(o)
                if o and o.IsShown and o:IsShown() and o.GetBottom then
                    local b = o:GetBottom()
                    if b and (not low or b < low) then low = b end
                end
            end
            for _, c in ipairs({ fr:GetChildren() }) do see(c) end
            for _, r in ipairs({ fr:GetRegions() }) do see(r) end
            local need = (top0 and low) and (top0 - low + 18) or h
            fr:SetHeight(math.max(h, need))
            local over = fr:GetHeight() - h
            sc.thumb:SetShown(over > 4)
            if over > 4 then
                local th = math.max(24, h * h / fr:GetHeight())
                sc.thumb:SetHeight(th)
                sc.thumb:ClearAllPoints()
                sc.thumb:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -((sc:GetVerticalScroll() or 0) / over) * (h - th))
            else
                sc:SetVerticalScroll(0)
            end
        end
        sc.Measure = measure
        sc:SetScript("OnSizeChanged", function() measure() end)
        sc:EnableMouseWheel(true)
        sc:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, fr:GetHeight() - self:GetHeight())
            if max <= 0 then return end
            self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 48)))
            ns._setScroll = ns._setScroll or {}
            ns._setScroll[key] = self:GetVerticalScroll()
            measure()
        end)
        page.tabs[key], page.scrolls[key] = fr, sc
        page.buildingTab = key
        local ok, e = pcall(BUILD[key], fr)
        page.buildingTab = nil
        if not ok then ns.err(L["Setup"] .. " settings/" .. key, e) end
        -- 0.6.476: first contract boxes with hidden toggles and shorten them by the gap
        local function boxes(o, depth)
            if depth > 3 then return end
            for _, ch in ipairs({ o:GetChildren() }) do
                if ch.advGap then
                    ch.advGap = nil
                    local ok, sh = pcall(compact, ch, true)
                    if ok and type(sh) == "number" and sh > 0 then ch:SetHeight(math.max(30, (ch:GetHeight() or 0) - sh)) end
                end
                boxes(ch, depth + 1)
            end
        end
        pcall(boxes, fr, 0)
        pcall(compact, fr)
        -- after a rebuild (design switch etc.) continue where you were
        local function restore()
            local v = ns._setScroll and ns._setScroll[key]
            if v and v > 0 then
                local max = math.max(0, fr:GetHeight() - sc:GetHeight())
                sc:SetVerticalScroll(math.min(max, v))
            end
        end
        C_Timer.After(0, function() pcall(autoCards) measure() restore() measure() end)
        C_Timer.After(0.3, function() pcall(autoCards) measure() restore() measure() end)
    end
    local fr = page.scrolls[key] or page.tabs[key]
    if fr then
        -- slide in smoothly (12 px from the right) + fade in
        fr:ClearAllPoints()
        fr:SetPoint("TOPLEFT", 0, top)
        fr:SetPoint("BOTTOMRIGHT")
        if not (S().noAnim) and K.Tween then
            local from = 12
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", from, top)
            fr:SetPoint("BOTTOMRIGHT", from, 0)
            K.Tween(fr, 0.18, function(p)
                local e = 1 - (1 - p) * (1 - p)
                fr:ClearAllPoints()
                fr:SetPoint("TOPLEFT", from * (1 - e), top)
                fr:SetPoint("BOTTOMRIGHT", from * (1 - e), 0)
            end)
        end
        if S().noAnim then fr:SetAlpha(1) else K.FadeIn(fr, 0) end
        local stFr = page.tabs[key]
        C_Timer.After(0.02, function() pcall(staggerCards, stFr) end)
        -- 0.5.561: always set the final position safely (an interrupted slide-in left the content indented)
        local snapFr, snapTop = fr, top
        C_Timer.After(0.25, function()
            if not snapFr then return end
            snapFr:ClearAllPoints()
            snapFr:SetPoint("TOPLEFT", 0, snapTop)
            snapFr:SetPoint("BOTTOMRIGHT", 0, 0)
        end)
    end
    S().settingsTab = key
    ns.RefreshPage("settings")
end
-- Open settings on a specific tab (e.g. click on the logo)
function ns.OpenSettingsTab(key)
    if ns.db then ns.db.settings.settingsTab = key end
    ns.ShowPage("settings")
    if page then setTab(key) end
end
-- Open a section's settings (e.g. "map" from the bar under the world map); brings Oasis in front of the map
function ns.OpenAreaSettings(area)
    -- Map toggles have their own tab since 0.5.995
    if area == "map" then ns.OpenSettingsTab("mapset") if ns.OasisFront then ns.OasisFront() end return end
    local tab = areaTab(area)
    ns.OpenSettingsTab(tab)
    local pf = page and page.tabs and page.tabs[tab]
    if pf and pf.ShowSel then
        pf.sel = area
        if pf.pick then pcall(pf.pick.Update, pf.pick) end
        pf:ShowSel()
    end
    if ns.OasisFront then ns.OasisFront() end
end

------------------------------------------------------------------------
-- 0.5.995: quick start, tooltips, map
-- Quick start = the essentials + signposts to all groups; Tooltips and Map collect what was previously
-- scattered over six sections and two tabs.
------------------------------------------------------------------------
-- Glass card across the full width with title; returns the card and the first free row
local function wideCard(f, y, icon, title, sub)
    local c = cardH(f, 0, y, 740, 100, icon, title, sub)
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
    return c, y - (sub and 62 or 46)
end
-- Subheading in a card (same style as in the sections)
local function subHead(f, text, y)
    rowLabel(f, "|cffe8b44a" .. L[text] .. "|r", 14, y)
    return y - 28
end
-- List { text, key, explanation, after, default on } as toggles stacked
-- 0.6.0: two columns (left 14, right 384) - single column left half the card empty
local function toggleList(f, list, y, cols)
    list = avail(list)
    cols = cols or 2
    -- 0.6.471: rare toggles only with "Alle Optionen zeigen"
    local vis = {}
    for _, o in ipairs(list) do
        if advHidden(o[2]) then
            -- build invisibly (without space): so the search finds them and turns on "Alle Optionen"
            local t = toggle(f, 14, y, o[1], o[2], o[3], o[4], 340)
            t.noReflow = true
            f.t[#f.t + 1] = t
        else
            vis[#vis + 1] = o
        end
    end
    list = vis
    local was = descInline
    descInline = true
    for r = 0, math.ceil(#list / cols) - 1 do
        local tall = false
        for c = 1, cols do
            local o = list[r * cols + c]
            if o then
                if o[5] and S()[o[2]] == nil then S()[o[2]] = true end
                local t = toggle(f, cols == 1 and 14 or (14 + (c - 1) * 370), y, o[1], o[2], o[3], o[4], cols == 1 and 600 or 340)
                t.noReflow = true
                f.t[#f.t + 1] = t
                f.rk = f.rk or {}
                f.rk[#f.rk + 1] = { o[2], o[5] and true or nil }
                if o[3] then tall = true end
            end
        end
        y = y - 32 - (tall and DESC_H or 0)
    end
    descInline = was
    return y
end

-- 0.6.115: "Diese Seite zuruecksetzen" - every toggle on the page to its default (core default, privacy
-- default on, or the default on noted at the toggle); then redraw the page
local PRIV_SET = {}
for _, k in ipairs(PRIV_ON) do PRIV_SET[k] = true end
local function resetPage(f, after)
    local D = ns.DEFAULT_SETTINGS or {}
    for _, r in ipairs(f.rk or {}) do
        local k, on = r[1], r[2]
        local d = D[k]
        if type(d) == "table" then d = nil end
        if d == nil and (on or PRIV_SET[k]) then d = true end
        S()[k] = d
    end
    if after then pcall(after) end
    for _, t in ipairs(f.t or {}) do if t.Refresh then pcall(t.Refresh, t) end end
    for _, fn in ipairs(f.refreshers or {}) do pcall(fn) end
    if K.Toast then K.Toast(L["Reset"], L["The switches on this page are back to default."], C.accent) end
end
function resetButton(f, y, after)   -- 0.6.180: declared local up front (page 'Teilen' called it earlier -> nil)
    -- two-step: first click asks, second (within 4 s) resets
    local b
    b = K.Button(f, L["Reset this page"], 190, 22, "ghost", function(self)
        if self.armed and GetTime() - self.armed < 4 then
            self.armed = nil
            self:SetLabel(L["Reset this page"])
            resetPage(f, after)
            return
        end
        self.armed = GetTime()
        self:SetLabel(L["Sure? Click again"])
        C_Timer.After(4, function() if b.armed and GetTime() - b.armed >= 3.9 then b.armed = nil b:SetLabel(L["Reset this page"]) end end)
    end)
    b:SetPoint("TOPLEFT", 0, y)
    return b
end

local function buildQuick(f)
    f.noCompact = true
    f.t = {}
    -- The essentials ----------------------------------------------------
    local c, y = wideCard(f, 0, "settings", L["The essentials"], L["The switches almost everyone needs at some point - everything else is sorted by topic below"])
    -- Language is always available at the top of the window (flag) - not duplicated here
    y = toggleList(f, {
        { "Show notifications", "toasts", "Short messages at the edge of the screen: orders, events, group searches, announcements ..." },
        { "Play sounds", "sound", "All Oasis sounds on or off" },
        { "Hide in combat", "hideInCombat", "The Oasis window disappears as soon as combat starts" },
        { "Show minimap button", "minimap", "Left-click opens Oasis, right-click the settings", function() if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end },
        { "Share position on the world map", "shareMap", "Guild map and minimap dots for others. Default: off" },
        { "Show emojis in chat", "chatEmoji", ":lol: or <3 becomes a picture" },
        { "Oasis lines in item tooltips", "tipOasis", "Wanted by, orders, guild bank and source below every item tooltip", nil, true },
        { "Reduce animations", "noAnim", "No fades or count-ups - everything appears instantly" },
        { "Guild window key (J) opens Oasis", "guildKeyOasis", "The key opens and closes the Oasis window instead of Blizzard's guild window", function() if ns.Keybinds and ns.Keybinds.ApplyGuildKey then ns.Keybinds.ApplyGuildKey() end end },
    }, y)
    c:SetHeight(-y + 4)
    -- Signposts ---------------------------------------------------------
    y = y - 18
    local h = K.Text(f, 10, C.dim)
    h:SetPoint("TOPLEFT", 0, y)
    h:SetText(K.Upper(L["All settings by topic"]))
    y = y - 20
    local G = ns.Insta and ns.Insta.Glass
    f.tiles = {}
    for _, g in ipairs(GROUPS) do
        if g.key ~= "start" and #groupTabs(g) > 0 then
            local t = CreateFrame("Button", nil, f)
            t:SetHeight(56)
            if not (G and pcall(G, t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.09 }, 10)) then K.Fill(t, { 1, 1, 1, 0.03 }) K.Border(t, C.line) end
            t.icon = K.Glyph(t, 16, ns.MEDIA .. "icons\\" .. g.icon, C.accent)
            t.icon:SetPoint("TOPLEFT", 12, -11)
            t.lbl = K.Title(t, 12, C.text)
            t.lbl:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
            t.lbl:SetText(L[g.text])
            t.sub = K.Text(t, 10, C.dim)
            t.sub:SetPoint("TOPLEFT", 12, -32)
            t.sub:SetPoint("RIGHT", -10, 0)
            t.sub:SetJustifyH("LEFT")
            t.sub:SetWordWrap(false)
            t.sub:SetText(L[g.desc or ""])
            t.hl = t:CreateTexture(nil, "HIGHLIGHT")
            t.hl:SetAllPoints()
            t.hl:SetColorTexture(1, 1, 1, 0.05)
            t.g = g
            t:SetScript("OnClick", function(self) setTab(groupTabs(self.g)[1]) end)
            f.tiles[#f.tiles + 1] = t
        end
    end
    local function layout()
        local w = f:GetWidth()
        if not w or w < 200 then w = 740 end
        local cols = w >= 600 and 3 or 2
        local cw = math.floor((w - 2 - (cols - 1) * 10) / cols)
        for i, t in ipairs(f.tiles) do
            local k = i - 1
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (k % cols) * (cw + 10), y - math.floor(k / cols) * 64)
            t:SetWidth(cw)
        end
    end
    f:HookScript("OnSizeChanged", layout)
    layout()
    -- Restart the tour (Onboarding.lua)
    if ns.Onboarding and ns.Onboarding.Show then
        local tb = K.Button(f, L["Start tour"], 140, 22, "ghost", function() ns.Onboarding.Show() end)
        tb:SetPoint("TOPLEFT", 0, y - math.ceil(#f.tiles / 3) * 64 - 8)
    end
end
local function refreshQuick(f)
    for _, t in ipairs(f.t) do if t.Refresh then pcall(t.Refresh, t) end end
    local l = ns.langByKey and ns.langByKey[ns.lang]
    if l and f.lang then
        local auto = (S().lang or "auto") == "auto"
        f.lang:SetLabel("|T" .. ns.MEDIA .. "flags\\" .. l.flag .. ":12:16:0:0:64:64:0:64:0:48|t  " .. (auto and (L["Like the game"] .. " (" .. l.name .. ")") or l.name))
    end
end

-- Tooltips: all extra lines in one place (previously under wish list, crafting, guild bank, softres, player book and chat)
local function buildTips(f)
    f.noCompact = true
    f.t = {}
    local c, y = wideCard(f, 0, "wants", L["Item tooltip"], L["What Oasis shows below items"])
    y = toggleList(f, {
        { "Oasis lines in item tooltips", "tipOasis", "Master switch: wanted by, orders, guild price, guild bank and source", nil, true },
        { "Wanted by in item tooltip", "tipWanted", "Who in the guild has the item on their wishlist", nil, true },
        { "Craftable by in item tooltip", "tipCrafters", "Shows in the tooltip who in the guild can craft the item", nil, true },
        { "Guild bank stock in item tooltip", "tipBank", "Shows in the tooltip how many are in the guild bank", nil, true },
        { "Reagent tooltip: what the guild needs it for", "tipReagent", "Below reagents: which guild recipes use them (Shift = all)", nil, true },
        { "Show reservations in item tooltip", "srTooltip", "Shows in the item tooltip who reserved the item for an upcoming event", nil, true },
        { "Tooltip line only in a group", "srTooltipGroupOnly", "The reservation line only appears while you are in a group or raid" },
    }, y)
    c:SetHeight(-y + 4)
    y = y - 18
    local c2
    local top2 = y
    c2, y = wideCard(f, y, "profile", L["Player tooltip"], L["What Oasis shows below players"])
    y = toggleList(f, {
        { "Mark Oasis users in tooltips", "oasisMark", "Small tooltip marker for members using Oasis", nil, true },
        { "Show rating in the player tooltip", "allyTooltip", "Your rating, note and the guild's experiences on mouseover", nil, true },
    }, y)
    c2:SetHeight(top2 - y + 4)
    resetButton(f, y - 16)
end
local function refreshTips(f) for _, t in ipairs(f.t) do if t.Refresh then pcall(t.Refresh, t) end end end

-- Map: everything about world map and minimap (previously Sections > Members > Map, plus Lists & Map and Graveyard)
local function buildMapTab(f)
    f.noCompact = true
    f.t, f.refreshers = {}, {}
    local c, y = wideCard(f, 0, "map", L["Guild on the map"], L["What you share and what you see of the guild"])
    y = toggleList(f, {
        { "Names on the world map", "mapNames", nil, updPins },
        { "Guild dots on the minimap", "minimapDots", nil, function() if ns.Map then ns.Map.UpdateMinimap() end end },
        { "Heatmap on the world map", "mapHeat", "Where the guild has been", updPins },
        { "Skulls on the map", "deathPins", "Where guild members died" },
        { "Reveal world map", "mapReveal", "Shows unexplored areas dimmed (off by default)", function() if ns.ComfortPlus then ns.ComfortPlus.ApplyReveal() end end },
    }, y)
    -- the detailed map toggles (collection map, extras, icons) from Modules/Settings "map"
    if PAGE_EXTRA.map then
        y = y - 8
        local ok, ny = pcall(PAGE_EXTRA.map, f, y)
        if ok and type(ny) == "number" then y = ny elseif not ok then ns.err(L["Setup"] .. " settings/mapset", ny) end
    end
    c:SetHeight(-y + 4)
    resetButton(f, y - 16, function() if ns.Map then pcall(ns.Map.UpdateWorldPins) pcall(ns.Map.UpdateMinimap) end if ns.Gather and ns.Gather.Refresh then pcall(ns.Gather.Refresh) end end)
end
local function refreshMapTab(f)
    for _, t in ipairs(f.t) do if t.Refresh then pcall(t.Refresh, t) end end
    for _, fn in ipairs(f.refreshers or {}) do pcall(fn) end
end
BUILD.quick, REFRESH.quick = buildQuick, refreshQuick
BUILD.tips, REFRESH.tips = buildTips, refreshTips
BUILD.mapset, REFRESH.mapset = buildMapTab, refreshMapTab

------------------------------------------------------------------------
-- 0.6.114: search with synonyms, ignoring umlauts, with tab/section names and sorted
------------------------------------------------------------------------
local function norm(x)
    x = tostring(x or ""):lower()
    x = x:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (x:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")
        :gsub("\195\132", "ae"):gsub("\195\150", "oe"):gsub("\195\156", "ue"))
end
-- Word groups: searching for one counts all
local SYN = {
    { "ton", "toene", "sound", "klang", "laut", "audio", "musik" },
    { "hinweis", "meldung", "toast", "benachrichtig", "popup", "notification" },
    { "minimap", "gildenpunkte", "minikarte" },
    { "karte", "map", "weltkarte" },
    { "tooltip", "maus", "drueberfahren", "hover" },
    { "teilen", "datenschutz", "privat", "share", "privacy" },
    { "farbe", "design", "aussehen", "theme", "look", "akzent" },
    { "schrift", "font" },
    { "groesse", "skalierung", "scale", "size" },
    { "emoji", "smiley" },
    { "chat", "fluester", "whisper" },
    { "durchsicht", "transparenz", "alpha" },
    { "kampf", "combat" },
    { "taste", "kuerzel", "keybind", "hotkey" },
}
local function variants(q)
    local out = { q }
    for _, g in ipairs(SYN) do
        for _, w in ipairs(g) do
            if q:find(w, 1, true) or w:find(q, 1, true) then
                for _, w2 in ipairs(g) do out[#out + 1] = w2 end
                break
            end
        end
    end
    return out
end
local function searchHits(q)
    q = norm(q)
    local vs = variants(q)
    local hits = {}
    local function score(label, rest)
        local l, r = norm(label), norm(rest)
        if l:find(q, 1, true) == 1 then return 1 end
        if l:find(q, 1, true) then return 2 end
        for _, v in ipairs(vs) do if l:find(v, 1, true) then return 3 end end
        if r:find(q, 1, true) then return 4 end
        for _, v in ipairs(vs) do if r:find(v, 1, true) then return 5 end end
    end
    -- Tabs themselves
    for _, tb in ipairs(TABS) do
        if BUILD[tb.key] and not HIDDEN_TABS[tb.key] then
            local sc = score(L[tb.text], "")
            if sc then hits[#hits + 1] = { label = L[tb.text], tab = tb.key, isTab = true, sc = sc - 0.5 } end
        end
    end
    local seen = {}
    for _, e in ipairs(INDEX) do
        local tabName = e.tab
        for _, tb in ipairs(TABS) do if tb.key == e.tab then tabName = L[tb.text] end end
        local ad = e.area and ns.PageDef(e.area)
        local sc = score(e.label, (e.desc or "") .. " " .. tabName .. " " .. (ad and L[ad.title] or ""))
        local id = e.label .. "|" .. (e.area or e.tab)
        if sc and not seen[id] then
            seen[id] = true
            hits[#hits + 1] = { label = e.label, desc = e.desc, tab = e.tab, area = e.area, frame = e.frame, settingKey = e.settingKey, sc = sc }
        end
    end
    table.sort(hits, function(a, b) if a.sc ~= b.sc then return a.sc < b.sc end return a.label < b.label end)
    return hits
end
ns.SettingsSearch = searchHits   -- for tests

ns.RegisterPage({
    key = "settings", title = "Settings", order = 8, topbar = true,
    sub = "Make Oasis your own",
    build = function(p)
        page = p
        wipe(INDEX)
        p.SetTab = setTab
        p.tabs = {}
        -- Search, topic picker and subpages each have their own row.
        local nav = CreateFrame("Frame", nil, p)
        nav:SetPoint("TOPLEFT", 0, -40)
        nav:SetPoint("TOPRIGHT", 0, -40)
        nav:SetHeight(68)
        p.nav = nav
        nav.btns = {}
        nav.ind = nav:CreateTexture(nil, "BACKGROUND")
        nav.ind:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
        p.context = K.Text(p, 11, C.muted)
        p.context:SetPoint("TOPLEFT", 0, -120)
        p.context:SetPoint("RIGHT", -4, 0)
        p.context:SetWordWrap(false)
        for _, g in ipairs(GROUPS) do
            if #groupTabs(g) > 0 then
                local b = CreateFrame("Button", nil, nav)
                b.g = g
                b:SetHeight(32)
                b.icon = K.Glyph(b, 14, ns.MEDIA .. "icons\\" .. g.icon, C.muted)
                b.icon:SetPoint("LEFT", 8, 0)
                b.t = K.Text(b, 12, C.muted)
                b.t:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
                b.t:SetPoint("RIGHT", -6, 0)
                b.t:SetWordWrap(false)
                b.t:SetJustifyH("LEFT")
                b.t:SetText(L[g.text])
                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints()
                b.hl:SetColorTexture(1, 1, 1, 0.04)
                -- 0.6.478: sections at the top tinted in accent color (stand out from the grey sub-tabs)
                b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -2)
                b.bg:SetAllPoints()
                b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.07)
                if K.RoundMask then pcall(K.RoundMask, b.bg, b, 6) end
                b.edge = b:CreateTexture(nil, "BORDER")
                b.edge:SetPoint("TOPLEFT", 0, -6) b.edge:SetPoint("BOTTOMLEFT", 0, 6)
                b.edge:SetWidth(2)
                b.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
                b:SetScript("OnClick", function(self)
                    local tabs = groupTabs(self.g)
                    local last = S().settingsSub and S().settingsSub[self.g.key]
                    local want = tabs[1]
                    for _, k in ipairs(tabs) do if k == last then want = k end end
                    setTab(want)
                end)
                b:SetScript("OnEnter", function(self) K.ShowTip(self, { L[self.g.text], L[self.g.desc] }) end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                nav.btns[#nav.btns + 1] = b
            end
        end
        local function justify()
            local w = nav:GetWidth() or 740
            if w < 100 then return end
            local cw = (w - 18) / 4
            for i, b in ipairs(nav.btns) do
                b.nx, b.ny = ((i - 1) % 4) * (cw + 6), -math.floor((i - 1) / 4) * 36
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", nav, "TOPLEFT", b.nx, b.ny)
                b:SetWidth(cw)
            end
            if p.UpdateNav and p.curGroup then p:UpdateNav(p.curGroup, p.tab) end
        end
        nav.Justify = justify
        nav:SetScript("OnSizeChanged", justify)
        p.subSeg = {}
        function p:UpdateNav(g, key)
            self.curGroup = g
            nav.ind:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.26)
            self.context:SetText(L[g.desc])
            for _, b in ipairs(nav.btns) do
                local on = b.g.key == g.key
                local c = on and C.text or C.muted
                b.t:SetTextColor(c[1], c[2], c[3])
                b.icon:SetVertexColor(on and C.accent[1] or c[1], on and C.accent[2] or c[2], on and C.accent[3] or c[3])
                if b.edge then b.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], on and 1 or 0.35) end
                if on then
                    local x, y, w = b.nx or 0, b.ny or 0, b:GetWidth()
                    local from = nav.position or { x, y }
                    local function move(q)
                        nav.position = { from[1] + (x - from[1]) * q, from[2] + (y - from[2]) * q }
                        nav.ind:ClearAllPoints()
                        nav.ind:SetPoint("TOPLEFT", nav, "TOPLEFT", nav.position[1], nav.position[2])
                        nav.ind:SetSize(w, 32)
                    end
                    if not S().noAnim and K.Tween then K.Tween(nav, 0.16, move) else move(1) end
                end
            end
            for gk, sg in pairs(self.subSeg) do sg:SetShown(gk == g.key) end
            local tabs = groupTabs(g)
            local sg = self.subSeg[g.key]
            if not sg then
                sg = CreateFrame("Frame", nil, self)
                sg:SetPoint("TOPLEFT", 0, -144)
                sg:SetPoint("TOPRIGHT", 0, -144)
                sg.btns = {}
                for _, k in ipairs(tabs) do
                    local b = K.Button(sg, tabText(k), 100, 26, "ghost", function() setTab(k) end)
                    b.key = k
                    b.mark = b:CreateTexture(nil, "ARTWORK")
                    b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                    b.mark:SetPoint("BOTTOMLEFT", 8, 0)
                    b.mark:SetPoint("BOTTOMRIGHT", -8, 0)
                    b.mark:SetHeight(2)
                    sg.btns[#sg.btns + 1] = b
                end
                self.subSeg[g.key] = sg
            end
            local x, row, avail = 0, 0, self:GetWidth() or 740
            for _, b in ipairs(sg.btns) do
                local w = math.min(avail, math.max(80, (b.label and b.label:GetStringWidth() or #tabText(b.key) * 7) + 24))
                if x > 0 and x + w > avail then x, row = 0, row + 1 end
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -row * 32)
                b:SetWidth(w)
                b.mark:SetShown(b.key == key)
                x = x + w + 6
            end
            sg:SetHeight((row + 1) * 32)
            sg:Show()
            self.contentTop = -144 - (row + 1) * 32 - 16
            -- On resize the content stays below the wrapped sub-tabs.
            local sc = self.scrolls and self.scrolls[key]
            if sc then sc:ClearAllPoints() sc:SetPoint("TOPLEFT", 0, self.contentTop) sc:SetPoint("BOTTOMRIGHT") end
            S().settingsSub = S().settingsSub or {}
            S().settingsSub[g.key] = key
        end
        justify()
        C_Timer.After(0, justify)
        -- old interface (other modules/tests call p.seg:Select)
        p.seg = { Select = function(_, k) if k ~= p.tab then setTab(k) end end, Hide = function() end, Show = function() end,
            GetWidth = function() return nav:GetWidth() end }
        -- Search: finds every setting, jumps there and highlights it
        -- 0.5.563: every change confirms itself briefly with a check mark
        p.saved = K.Text(p, 11, C.good or { 0.4, 0.86, 0.62 }, "RIGHT")
        p.saved:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. L["Saved"])
        p.saved:SetAlpha(0)
        K.OnSaved = function()
            if not (p.saved and p:IsVisible()) then return end
            local sv = p.saved
            if not p.find then return end
            sv:ClearAllPoints()
            sv:SetPoint("RIGHT", p.allOpt or p.find, "LEFT", -12, 0)
            if S().noAnim or not K.Tween then sv:SetAlpha(1) C_Timer.After(1.4, function() sv:SetAlpha(0) end) return end
            K.Tween(sv, 1.8, function(q)
                local a = q < 0.12 and q / 0.12 or (q > 0.7 and (1 - q) / 0.3 or 1)
                sv:SetAlpha(a)
                sv:ClearAllPoints()
                sv:SetPoint("RIGHT", p.allOpt or p.find, "LEFT", -12, (q < 0.12) and (-4 * (1 - q / 0.12)) or 0)
            end, function() sv:SetAlpha(0) end)
        end
        p.find = K.Input(p, 170, L["Search settings ..."], function(t)
            t = (t or ""):lower()
            local res = p.findRes
            for _, b in ipairs(res.btns) do b:Hide() end
            if #t < 2 then res:Hide() return end
            -- build all tabs once so everything is in the index
            if not p.allBuilt then
                p.allBuilt = true
                local cur = p.tab
                for _, tb in ipairs(TABS) do
                    if not HIDDEN_TABS[tb.key] and not p.tabs[tb.key] and BUILD[tb.key] then setTab(tb.key) end
                end
                for _, tab in ipairs({ "guildtools", "socialtools", "personaltools" }) do
                    local pf = p.tabs[tab]
                    if pf and pf.nav and pf.ShowSel then
                        local keep = pf.sel
                        p.buildingTab = tab
                        for _, t in ipairs(pf.nav) do
                            p.buildingArea = t.key
                            pf.sel = t.key
                            pcall(pf.ShowSel, pf)
                        end
                        p.buildingArea, p.buildingTab = nil, nil
                        pf.sel = keep
                        pcall(pf.ShowSel, pf)
                    end
                end
                setTab(cur)
                if p.tabs[cur] then p.tabs[cur]:Show() end
            end
            local n = 0
            for _, e in ipairs(searchHits(t)) do
                if n < 10 then
                    n = n + 1
                    local b = res.btns[n]
                    if not b then
                        b = CreateFrame("Button", nil, res)
                        b:SetSize(300, 24)
                        b:SetPoint("TOPLEFT", 4, -4 - (n - 1) * 24)
                        b.hl = b:CreateTexture(nil, "HIGHLIGHT") b.hl:SetAllPoints() b.hl:SetColorTexture(1, 1, 1, 0.08)
                        b.t = K.Text(b, 12, C.text) b.t:SetPoint("LEFT", 8, 0) b.t:SetPoint("RIGHT", -80, 0) b.t:SetWordWrap(false)
                        b.tab = K.Text(b, 10, C.dim, "RIGHT") b.tab:SetPoint("RIGHT", -8, 0)
                        res.btns[n] = b
                    end
                    local tabName = e.tab
                    for _, tb in ipairs(TABS) do if tb.key == e.tab then tabName = L[tb.text] end end
                    if e.area then
                        local ad = ns.PageDef(e.area)
                        tabName = ad and L[ad.title] or tabName
                    end
                    b.t:SetText(e.label)
                    b.tab:SetText(tabName)
                    b:SetScript("OnClick", function()
                        res:Hide()
                        p.find:ClearFocus()
                        local rebuilt = e.settingKey and advHidden(e.settingKey)
                        if rebuilt then
                            S().setAll = true
                            for k, fr in pairs(p.tabs) do
                                fr:Hide()
                                if p.scrolls and p.scrolls[k] then p.scrolls[k]:Hide() end
                            end
                            p.tabs, p.scrolls, p.allBuilt = {}, {}, nil
                            wipe(INDEX)
                            if p.allOpt.Refresh then p.allOpt:Refresh() end
                        end
                        setTab(e.tab)
                        if e.isTab then return end
                        local f = e.frame
                        if rebuilt and not e.area then
                            f = nil
                            for _, item in ipairs(INDEX) do
                                if item.tab == e.tab and item.settingKey == e.settingKey then f = item.frame break end
                            end
                        end
                        -- Section setting: open the section and find the freshly built toggle
                        if e.area and p.tabs[e.tab] then
                            local pf = p.tabs[e.tab]
                            pf.sel = e.area
                            if pf.pick then pf.pick:Update() end
                            pf:ShowSel()
                            f = nil
                            for _, t in ipairs(pf.det and pf.det.t or {}) do
                                if t.lbl and t.lbl:GetText() == e.label then f = t end
                            end
                            if not f then return end
                        end
                        local parent = f and f:GetParent()
                        if parent and parent.ExpandSearch then parent.ExpandSearch() end
                        local sc = p.scrolls[e.tab]
                        if e.area then sc = p.tabs[e.tab].detScroll end
                        if sc and f and f.GetTop then
                            local child = sc:GetScrollChild()
                            local ct, ft = child and child:GetTop(), f:GetTop()
                            if ct and ft then
                                local limit = math.max(0, child:GetHeight() - sc:GetHeight())
                                sc:SetVerticalScroll(math.min(limit, math.max(0, ct - ft - 16)))
                                if sc.UpdateBar then sc:UpdateBar() elseif sc.Measure then sc.Measure() end
                            end
                        end
                        if not f then return end
                        -- Briefly highlight the match; reduced motion stays static.
                        if not f.flash then
                            f.flash = f:CreateTexture(nil, "BACKGROUND")
                            f.flash:SetPoint("TOPLEFT", -6, 4) f.flash:SetPoint("BOTTOMRIGHT", 6, -4)
                        end
                        f.flash:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
                        f.flash:Show()
                        local t0 = GetTime()
                        f:SetScript("OnUpdate", function(self)
                            local d = GetTime() - t0
                            if d > 1.6 then self.flash:Hide() self:SetScript("OnUpdate", nil) return end
                            self.flash:SetAlpha(S().noAnim and 0.6 or math.max(0, 1 - d / 1.6))
                        end)
                    end)
                    b:Show()
                end
            end
            res:SetHeight(8 + math.max(1, n) * 24)
            res.none:SetShown(n == 0)
            res:Show()
        end)
        p.find:SetPoint("TOPLEFT", 0, 0)
        p.find:SetWidth(280)
        -- 0.6.471: "Alle Optionen" - also shows the rarely used toggles (pages are rebuilt)
        p.allOpt = K.Toggle(p, L["All options"], function() return S().setAll and true or false end, function(v)
            S().setAll = v or nil
            local cur = p.tab
            for k, fr in pairs(p.tabs) do fr:Hide() if p.scrolls and p.scrolls[k] then p.scrolls[k]:Hide() end end
            p.tabs, p.scrolls, p.allBuilt = {}, {}, nil
            wipe(INDEX)
            p.findRes:Hide()
            setTab(cur)
        end)
        p.allOpt:SetPoint("TOPRIGHT", 0, 0)
        p.allOpt:SetWidth(130)
        p.allOpt:HookScript("OnEnter", function(self) K.ShowTip(self, { L["All options"], L["Also shows rarely used switches. Off: only the essentials."] }) end)
        p.allOpt:HookScript("OnLeave", function() GameTooltip:Hide() end)
        p.findRes = CreateFrame("Frame", nil, p)
        p.findRes:SetPoint("TOPLEFT", p.find, "BOTTOMLEFT", 0, -4)
        p.findRes:SetWidth(308)
        p.findRes:SetFrameLevel(p:GetFrameLevel() + 50)
        K.Fill(p.findRes, { 0.05, 0.05, 0.06, 0.98 })
        K.Border(p.findRes, C.line)
        p.findRes.btns = {}
        p.findRes.none = K.Text(p.findRes, 11, C.dim)
        p.findRes.none:SetPoint("LEFT", 12, 0)
        p.findRes.none:SetText(L["Nothing found."])
        p.findRes:Hide()
        local line = K.Divider(p)
        line:SetPoint("TOPLEFT", 0, -32)
        line:SetPoint("TOPRIGHT", 0, -32)
        -- 0.5.995: after the rework, start on the quick start once
        if not S().settingsV2 then S().settingsV2 = true S().settingsTab = "quick" S().settingsSub = nil end
        local tab = S().settingsTab
        -- remembered tab only if it still exists (e.g. "Teilen" was dropped)
        local known = false
        for _, t in ipairs(TABS) do if t.key == tab and not HIDDEN_TABS[tab] then known = true end end
        setTab(known and REFRESH[tab] and tab or "quick")
    end,
    refresh = function(p)
        local fr = p.tabs[p.tab]
        if fr and REFRESH[p.tab] then
            local ok, e = pcall(REFRESH[p.tab], fr)
            if not ok then ns.err(L["Page"] .. " settings/" .. p.tab, e) end
        end
    end,
})
-- 0.5.733: after a resize (window size/scaling) re-measure the scroll areas - otherwise the old heights
-- remain and the mouse wheel stops scrolling
local function remeasureAll()
    for _, sc in pairs(page and page.scrolls or {}) do
        if sc.Measure then pcall(sc.Measure) end
    end
end
ns.Settings = { SetTab = function(k) ns.ShowPage("settings") setTab(k) end, Remeasure = remeasureAll }
ns.Listen("BRAND", function() ns.RefreshPage("settings") end)

-- Minimap counter: open tasks for me
ns.Listen("BADGES", function()
    ns.SetMinimapBadge((ns.Crafting and ns.Crafting.badge) or 0)
end)

-- English commands as alias
ns.slash.award = ns.slash.vergabe
ns.slash.campfire = ns.slash.lagerfeuer
ns.slash.roll = ns.slash.wuerfeln
ns.slash.sound = function() ns.Settings.SetTab("sound") end

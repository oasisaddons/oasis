-- Oasis: spinning ring around the logo + collapsed Oasis bar (freely draggable, snaps to the top screen edge)
local ADDON, ns = ...
local K, C, L = ns.K, ns.K.C, ns.L
local M = ns.MEDIA

-- 0.6.507: idle bar icons with a very light gradient (lighter at the top, a bit darker at the bottom)
local function restTint(t)
    local m = C.muted
    t:SetVertexColor(m[1], m[2], m[3])
    if t.SetGradient and CreateColor then
        pcall(t.SetGradient, t, "VERTICAL", CreateColor(m[1] * 0.62, m[2] * 0.62, m[3] * 0.62, 1),
            CreateColor(math.min(1, m[1] * 1.35), math.min(1, m[2] * 1.35), math.min(1, m[3] * 1.35), 1))
    end
end

------------------------------------------------------------------------
-- spinning ring (gradient blue > violet > pink) around a round logo
------------------------------------------------------------------------
function ns.SpinRing(parent, anchor, size, speed)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(M .. "arc")
    t:SetAllPoints()
    t:SetBlendMode("ADD")
    local angle, spd = 0, speed or 0.9
    f:SetScript("OnUpdate", function(_, el)
        angle = (angle - el * spd) % (math.pi * 2)
        t:SetRotation(angle)
    end)
    f.tex = t
    return f
end

------------------------------------------------------------------------
-- animated wordmark: red light streak runs through the letters
-- (via mask only on the lettering), below it a line with a wandering light dot
------------------------------------------------------------------------
local wordmarks = setmetatable({}, { __mode = "k" })
-- accent color changed: recolor all wordmarks (sidebar, bar)
ns.Listen("BRAND", function() for wm in pairs(wordmarks) do wm:UpdateColor() end end)
function ns.Wordmark(parent, w, h, withLine)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    local base = f:CreateTexture(nil, "ARTWORK")
    base:SetTexture(M .. "wordmark_base")     -- letters without i
    base:SetAllPoints()
    f.base = base
    -- the i as its own layer in the accent color (follows design/accent)
    local dot = f:CreateTexture(nil, "ARTWORK", nil, 1)
    dot:SetTexture(M .. "wordmark_i")
    dot:SetAllPoints()
    f.dot = dot
    function f:UpdateColor()
        self.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end
    f:UpdateColor()
    wordmarks[f] = true

    local shine = f:CreateTexture(nil, "OVERLAY")
    shine:SetTexture(M .. "shine")
    shine:SetBlendMode("ADD")
    shine:SetSize(h * 1.6, h)
    shine:Hide()
    local masked = false
    if f.CreateMaskTexture and shine.AddMaskTexture then
        local ok = pcall(function()
            local mask = f:CreateMaskTexture()
            mask:SetTexture(M .. "wordmark", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(base)
            shine:AddMaskTexture(mask)
        end)
        masked = ok
    end

    local line, spark
    if withLine then
        line = f:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
        line:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
        spark = f:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(M .. "shine")
        spark:SetBlendMode("ADD")
        spark:SetSize(34, 3)
    end

    -- tick: one pass every 5 s (1.4 s), the line runs slowly all the time
    local t, CYCLE, RUN = 0, 5, 1.4
    f:SetScript("OnUpdate", function(_, el)
        t = t + el
        local c = t % CYCLE
        local anim = not ns.db or ns.db.settings.logoAnim ~= false
        if spark then spark:SetShown(anim) end
        if not anim then shine:Hide() if line then line:SetAlpha(1) end return end
        if masked and c < RUN then
            local p = c / RUN
            p = p * p * (3 - 2 * p)
            shine:ClearAllPoints()
            shine:SetPoint("CENTER", f, "LEFT", -h + p * (w + 2 * h), 0)
            shine:Show()
        else
            shine:Hide()
        end
        if spark then
            local q = (t % 3.2) / 3.2
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", line, "LEFT", q * w, 0)
            spark:SetAlpha(math.sin(q * math.pi))
            line:SetAlpha(0.7 + 0.3 * math.sin(t * 1.3))
        end
    end)
    return f
end

------------------------------------------------------------------------
-- Oasis bar
------------------------------------------------------------------------
local bar
-- pages that can be a button in the bar (selection in the settings, tab "Bar")
local QUICK_ALL = { "home", "insta", "chat", "radar", "chronicle", "polls", "groups", "social", "allies", "dungeons", "camp",
    "raid", "buffs", "crafting", "trade", "wants", "bank", "deathroll", "deaths", "legacy", "badges" }
local QUICK_DEFAULT = { home = true, chat = true, groups = true, dungeons = true, raid = true, crafting = true, mark = true }
ns.MINI_QUICK_ALL, ns.MINI_QUICK_DEFAULT = QUICK_ALL, QUICK_DEFAULT
function ns.MiniQuickOn(key)
    local sel = ns.db and ns.db.settings.miniPages
    if sel == nil then return QUICK_DEFAULT[key] or false end
    -- former own button "Buff monitor window" is now the buff monitor button itself
    if key == "buffs" and sel.buffmon then return true end
    return sel[key] and true or false
end
local QUICK = {}
for _, k in ipairs(QUICK_ALL) do QUICK[#QUICK + 1] = { key = k } end
-- buff monitor in the bar: opens the small floating window instead of the large page
for _, q in ipairs(QUICK) do
    if q.key == "buffs" then
        q.tip = { "Buff monitor", "Click: window on/off", "Right-click: page in the Oasis window" }
        q.fn = function(btn)
            if btn == "RightButton" then ns.Expand("buffs") return end
            if ns.BuffMonitor and ns.BuffMonitor.Toggle then ns.BuffMonitor.Toggle() end
        end
    end
end
-- action instead of page: auto marker (only visible in a group)
QUICK[#QUICK + 1] = { key = "mark", action = true, icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    tip = { "Auto marker", "Left-click: mark enemies (again = remove)", "Right-click: clear marks", "Shift + click: auto marker window" },
    -- if the click arrives here, the secure button wasn't on top -> realign
    fn = function()
        -- 0.5.735: Shift + click opens the window even if the secure button doesn't catch the click (macro /oa mark button)
        if IsShiftKeyDown and IsShiftKeyDown() and ns.Marker and ns.Marker.Toggle then ns.Marker.Toggle() return end
        if InCombatLockdown() then ns.print(ns.L["Auto marker: click again after combat."]) return end
        if ns.UpdateMiniBar then ns.UpdateMiniBar() end
        ns.print(ns.L["Auto marker realigned - please click again."])
    end }

-- popout window on/off (auto marker box, buff monitor)
QUICK[#QUICK + 1] = { key = "markbox", panel = true, icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    tip = { "Auto marker window", "Click: window on/off" },
    fn = function() if ns.Marker and ns.Marker.Toggle then ns.Marker.Toggle() end end }
-- for settings/preview
ns.MINI_QUICK_PANELS = {
    { key = "markbox", label = "Auto marker window", icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath" },
}

local SNAP = 36   -- this close to the top edge the bar snaps in

local function savePos()
    local p, _, rp, x, y = bar:GetPoint(1)
    ns.db.settings.miniPos = { p = p, rp = rp, x = x, y = y, docked = bar.docked }
end

local function applyDockLook()
    if bar.Shape then bar:Shape() end
end

local function dock()
    local x = bar:GetCenter() - UIParent:GetCenter()
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", x, 0)
    bar.docked = true
    applyDockLook()
end

local function build()
    bar = CreateFrame("Frame", "OasisMiniBar", UIParent)
    bar:SetHeight(38)
    bar:SetFrameStrata("HIGH")   -- above action bars (otherwise no longer grabbable when pinned at the bottom)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    -- background from 9 parts: corners round or square depending on which screen edge the bar sits at
    -- (top -> bottom round, bottom -> top round, left -> right round, right -> left round, free -> all round)
    local R = 10
    local RF = M .. "skins\\round_fill"
    local W8 = "Interface\\Buttons\\WHITE8X8"
    local bc = C.bg
    bar.bgParts = {}
    local function part(tex)
        local t = bar:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(tex or W8)
        t:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
        bar.bgParts[#bar.bgParts + 1] = t
        return t
    end
    bar.bgTex = part()
    bar.bgTex:SetPoint("TOPLEFT", R, -R) bar.bgTex:SetPoint("BOTTOMRIGHT", -R, R)
    local e1 = part() e1:SetPoint("TOPLEFT", R, 0) e1:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -R, -R)
    local e2 = part() e2:SetPoint("BOTTOMLEFT", R, 0) e2:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -R, R)
    local e3 = part() e3:SetPoint("TOPLEFT", 0, -R) e3:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", R, R)
    local e4 = part() e4:SetPoint("TOPRIGHT", 0, -R) e4:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", -R, R)
    bar.corners = {}
    for _, d in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local c = part()
        c:SetSize(R, R)
        c:SetPoint(d[1])
        c.tc = { d[2], d[3], d[4], d[5] }
        bar.corners[d[1]] = c
    end
    -- light gloss
    local sheen = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", R, 0) sheen:SetPoint("TOPRIGHT", -R, 0) sheen:SetHeight(16)
    if not K.Gradient(sheen, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.045 }) then sheen:Hide() end
    bar.sheen = sheen   -- Shape() pulls it to the edge (0.5.702)
    bar.topLine = bar:CreateTexture(nil, "BORDER")   -- old (floating freely), stays invisible
    bar.topLine:Hide()
    ns._miniBar = bar
    if ns.ApplyMiniAlpha then ns.ApplyMiniAlpha() end
    -- accent line + glow on the inner side (away from the edge)
    bar.accent = bar:CreateTexture(nil, "ARTWORK")
    bar.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar.accentGlow = bar:CreateTexture(nil, "ARTWORK")
    -- determine edge and set corners/accent
    function bar:EdgeOf()
        if self.docked then return "TOP" end
        local l, r, t, b = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
        if not l then return nil end
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local d = { TOP = UIParent:GetTop() - t * s, BOTTOM = b * s - UIParent:GetBottom(),
            LEFT = l * s - UIParent:GetLeft(), RIGHT = UIParent:GetRight() - r * s }
        local best, bd
        for k, v in pairs(d) do if v < 6 and (not bd or v < bd) then best, bd = k, v end end
        return best
    end
    function bar:Shape()
        local edge = self:EdgeOf()
        -- full width (compact bar): left/right the bar touches the screen edge -> square there,
        -- line and glow run all the way to the edge
        local sL, sR = false, false
        do
            local l, r = self:GetLeft(), self:GetRight()
            if l and r then
                local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                sL = l * sc - UIParent:GetLeft() < 3
                sR = UIParent:GetRight() - r * sc < 3
            end
        end
        local touch = {
            TOPLEFT = edge == "TOP" or edge == "LEFT" or sL, TOPRIGHT = edge == "TOP" or edge == "RIGHT" or sR,
            BOTTOMLEFT = edge == "BOTTOM" or edge == "LEFT" or sL, BOTTOMRIGHT = edge == "BOTTOM" or edge == "RIGHT" or sR,
        }
        for k, c in pairs(self.corners) do
            if touch[k] then c:SetTexture(W8) c:SetTexCoord(0, 1, 0, 1)
            else c:SetTexture(RF) c:SetTexCoord(unpack(c.tc)) end
        end
        -- gloss all the way to the edge (previously 10 px inset -> the bar looked darker left/right);
        -- round top corners are cut off by mask (only these two corners, WoW allows at most 3 masks)
        if self.sheen then
            self.sheen:ClearAllPoints()
            self.sheen:SetPoint("TOPLEFT", 0, 0) self.sheen:SetPoint("TOPRIGHT", 0, 0) self.sheen:SetHeight(16)
            local rc = {}
            if not touch.TOPLEFT then rc[#rc + 1] = "tl" end
            if not touch.TOPRIGHT then rc[#rc + 1] = "tr" end
            if #rc > 0 and K.RoundMask then pcall(K.RoundMask, self.sheen, self, R, rc) end
        end
        local a, g = self.accent, self.accentGlow
        a:ClearAllPoints() g:ClearAllPoints()
        local ac = C.accent
        local inner = ({ TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" })[edge or ""]
        a:SetShown(inner ~= nil) g:SetShown(inner ~= nil)
        -- accent continues in the round corners as an arc up to the edge
        self.arcs = self.arcs or {}
        for k, c in pairs(self.corners) do
            local arc = self.arcs[k]
            if not arc then
                -- arc (same strength as the line) + glow, both exactly on the rounding (Media/skins/arc_corner, glow_corner)
                arc = self:CreateTexture(nil, "ARTWORK", nil, 2)
                arc:SetTexture(M .. "skins" .. string.char(92) .. "arc_corner")
                arc:SetSize(R, R)
                arc:SetPoint(k)
                arc:SetTexCoord(unpack(c.tc))
                arc.glow = self:CreateTexture(nil, "ARTWORK", nil, 1)
                arc.glow:SetTexture(M .. "skins" .. string.char(92) .. "glow_corner")
                arc.glow:SetSize(R, R)
                arc.glow:SetPoint(k)
                arc.glow:SetTexCoord(unpack(c.tc))
                self.arcs[k] = arc
            end
            local on = inner ~= nil and not touch[k] and k:find(inner) ~= nil
            arc:SetVertexColor(ac[1], ac[2], ac[3], 1)
            arc.glow:SetVertexColor(ac[1], ac[2], ac[3], 0.22)
            arc:SetShown(on) arc.glow:SetShown(on)
        end
        if not inner then return end
        local from = { ac[1], ac[2], ac[3], 0.22 }
        local to = { ac[1], ac[2], ac[3], 0 }
        if inner == "BOTTOM" or inner == "TOP" then
            local y = inner == "BOTTOM" and 0 or 0
            -- line ends at the arc (or at the screen edge); the glow continues into the rounding
            local lx, rx = sL and 0 or R, sR and 0 or R
            local gl, gr = sL and 0 or 4, sR and 0 or 4
            a:SetPoint(inner .. "LEFT", lx, y) a:SetPoint(inner .. "RIGHT", -rx, y) a:SetHeight(2)
            g:SetPoint(inner .. "LEFT", gl, inner == "BOTTOM" and 2 or -2) g:SetPoint(inner .. "RIGHT", -gr, inner == "BOTTOM" and 2 or -2) g:SetHeight(10)
            if inner == "BOTTOM" then K.Gradient(g, "VERTICAL", from, to) else K.Gradient(g, "VERTICAL", to, from) end
        else
            a:SetPoint("TOP" .. inner, 0, -R) a:SetPoint("BOTTOM" .. inner, 0, R) a:SetWidth(2)
            local dx = inner == "RIGHT" and -2 or 2
            g:SetPoint("TOP" .. inner, dx, -R) g:SetPoint("BOTTOM" .. inner, dx, R) g:SetWidth(10)
            if inner == "RIGHT" then K.Gradient(g, "HORIZONTAL", to, from) else K.Gradient(g, "HORIZONTAL", from, to) end
        end
    end

    -- 0.6.244: pinned at the top = ember bar as image (guild module, Tools/make_minibar.py): straight on top, round at the bottom.
    -- three parts (ends + stretchable middle), so the roundings stay round at any width. Otherwise the normal bar.
    if ns.ART then
        local GP = "Interface\\AddOns\\Oasis\\Media\\art\\"
        bar.art = {}
        for _, k in ipairs({ "l", "m", "r" }) do
            local t = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
            t:SetTexture(GP .. "minibar_" .. k)
            t:Hide()
            bar.art[k] = t
        end
        -- 0.6.248: image sticks out 8 below the bar - glow line sat too close under the icons
        local DROP = 8
        bar.art.l:SetPoint("TOPLEFT") bar.art.l:SetPoint("BOTTOMLEFT", 0, -DROP)
        bar.art.r:SetPoint("TOPRIGHT") bar.art.r:SetPoint("BOTTOMRIGHT", 0, -DROP)
        bar.art.m:SetPoint("TOPLEFT", bar.art.l, "TOPRIGHT") bar.art.m:SetPoint("BOTTOMRIGHT", bar.art.r, "BOTTOMLEFT")
        -- 0.6.311: light shimmer - additive copy of the image breathes slowly (off with "Animations off")
        bar.shine = {}
        for _, k in ipairs({ "l", "m", "r" }) do
            local s = bar:CreateTexture(nil, "BACKGROUND", nil, 3)
            s:SetTexture(GP .. "minibar_" .. k)
            s:SetBlendMode("ADD")
            s:SetAllPoints(bar.art[k])
            s:SetAlpha(0)
            bar.shine[k] = s
        end
        -- 0.6.330: light streak runs along the ember line at the bottom every 5 s
        local sw = bar:CreateTexture(nil, "BACKGROUND", nil, 4)
        sw:SetSize(170, 6)   -- 0.6.379: thin streak exactly on the ember line
        sw:SetBlendMode("ADD")
        sw:SetTexture(ns.MEDIA .. "ember")
        local sw2 = bar:CreateTexture(nil, "BACKGROUND", nil, 4)
        sw2:SetBlendMode("ADD")
        if not K.Gradient(sw2, "HORIZONTAL", { 1, 0.85, 0.7, 0.9 }, { 1, 0.85, 0.7, 0 }) then sw2:SetColorTexture(1, 0.85, 0.7, 0.4) end
        sw2:SetPoint("TOPLEFT", sw, "TOPRIGHT") sw2:SetPoint("BOTTOMLEFT", sw, "BOTTOMRIGHT") sw2:SetWidth(14)
        sw:Hide() sw2:Hide()
        local swWait, swRun, swX0, swLen, swDir = 1.5, nil, 0, 120, 1   -- 0.6.338: subtle flash every 8-12 s instead of continuous run
        local clock = 0
        local pulse = CreateFrame("Frame", nil, bar)
        local pAcc = 0
        pulse:SetScript("OnUpdate", function(_, el)
            -- performance (0.6.479): the bar is always visible - shimmer at most 30x per second instead of every frame
            pAcc = pAcc + (el or 0)
            if pAcc < 0.033 then return end
            el, pAcc = pAcc, 0
            local st = ns.db and ns.db.settings
            local on = not (st and st.noAnim)
            if on then clock = clock + (el or 0) end
            -- streak only when the ember image is visible
            local showArt = on and bar.art.m:IsShown()
            if showArt then
                local W = bar:GetWidth() or 600
                if not swRun then
                    swWait = swWait - (el or 0)
                    sw:Hide() sw2:Hide()
                    -- 0.6.362: start and end only in the straight middle piece (between the round ends)
                    local cw = bar.art.l:GetWidth() or 60
                    -- 0.6.413: random direction, travels a long stretch along the edge
                    if swWait <= 0 then
                        swRun = 0
                        swLen = math.max(60, (W - 2 * cw - 100) * (0.45 + math.random() * 0.4))
                        swDir = math.random() < 0.5 and 1 or -1
                        local room = math.max(1, W - 2 * cw - 100 - swLen)
                        swX0 = cw + math.random() * room + (swDir < 0 and swLen or 0)
                    end
                else
                    swRun = swRun + (el or 0) / 4.5
                    if swRun >= 1 then
                        swRun, swWait = nil, 3 + math.random() * 5
                        sw:Hide() sw2:Hide()
                    else
                        local x = swX0 + swDir * swRun * swLen
                        sw:ClearAllPoints()
                        sw:SetPoint("LEFT", bar, "BOTTOMLEFT", x, -4)   -- 0.6.429: minimally lower
                        local a = math.sin(swRun * math.pi) ^ 0.8 * 1.0 * (bar.art.m:GetAlpha() or 1)   -- 0.6.413: more subtle, soft fade in/out
                        sw:SetVertexColor(1 * a, 0.85 * a, 0.7 * a, 1)
                        sw:Show() sw2:Hide()
                    end
                end
            else
                sw:Hide() sw2:Hide()
            end
            local a = on and (0.12 + 0.12 * math.sin(clock * 1.6)) or 0
            for k, s in pairs(bar.shine) do
                local base = bar.art[k]
                s:SetShown(base:IsShown())
                if base:IsShown() then
                    local r, g, b = base:GetVertexColor()
                    s:SetVertexColor(r or 1, g or 1, b or 1)
                    if base.IsDesaturated then s:SetDesaturated(base:IsDesaturated() and true or false) end
                    s:SetAlpha(a * (base:GetAlpha() or 1))
                end
            end
        end)
        C_Timer.After(0, function() if ns.ApplyMiniAlpha then pcall(ns.ApplyMiniAlpha) end end)   -- 0.6.263: apply opacity + color right away
        local baseShape = bar.Shape
        function bar:Shape()
            baseShape(self)
            -- 0.6.257: only with image (texture loaded) - otherwise the bar had no background at all
            local on = self:EdgeOf() == "TOP" and (self.art.m:GetTexture() ~= nil)
            local cw = ((self:GetHeight() or 38) + 8) * 1.09
            self.art.l:SetWidth(cw) self.art.r:SetWidth(cw)
            for _, k in ipairs({ "l", "m", "r" }) do self.art[k]:SetShown(on) end
            if not on then return end
            for _, t in ipairs(self.bgParts) do t:Hide() end
            if self.sheen then self.sheen:Hide() end
            self.accent:Hide() self.accentGlow:Hide()
            for _, arc in pairs(self.arcs or {}) do arc:Hide() arc.glow:Hide() end
        end
        -- show previously hidden parts again when the bar is dragged away from the top edge
        local baseShape2 = bar.Shape
        function bar:Shape()
            for _, t in ipairs(self.bgParts) do t:Show() end
            if self.sheen then self.sheen:Show() end
            baseShape2(self)
        end
        -- 0.6.257: UI scale changed (e.g. EllesmereUI sets UIParent:SetScale) -> redetermine edge and update shape
        local reshape = CreateFrame("Frame")
        for _, ev in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_ENTERING_WORLD" }) do pcall(reshape.RegisterEvent, reshape, ev) end
        reshape:SetScript("OnEvent", function() C_Timer.After(1, function() if bar and bar.Shape then pcall(bar.Shape, bar) end end) end)
        -- end width follows the height (compact / docked)
        bar:HookScript("OnSizeChanged", function(self) if self.art then local cw = ((self:GetHeight() or 38) + 8) * 1.09 self.art.l:SetWidth(cw) self.art.r:SetWidth(cw) end end)
    end

    -- wordmark (animated): click = expand
    local logoBtn = CreateFrame("Button", nil, bar)
    logoBtn:SetSize(76, 19)
    logoBtn:SetPoint("LEFT", 12, 0)
    local wm = ns.GuildLogo(logoBtn, 76, 19)
    wm:SetPoint("TOPLEFT")
    logoBtn:SetScript("OnClick", function() ns.Expand() end)
    logoBtn:SetScript("OnEnter", function(self) K.ShowTip(self, { "Oasis", L["Click: expand"], L["Drag: move (snaps to the top edge)"] }) end)
    logoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    logoBtn:RegisterForDrag("LeftButton")
    logoBtn:SetScript("OnDragStart", function() bar:GetScript("OnDragStart")(bar) end)
    logoBtn:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
    logoBtn.oasisDragFwd = true
    bar.name = logoBtn
    bar.wm = wm
    -- without logo: small plus to expand
    bar.plus = K.Text(logoBtn, 14, C.accent, "CENTER")
    bar.plus:SetPoint("CENTER")
    bar.plus:SetText("+")
    bar.plus:Hide()

    bar.dot = bar:CreateTexture(nil, "ARTWORK")
    bar.dot:SetTexture(M .. "dot")
    bar.dot:SetSize(12, 12)
    bar.dot:SetPoint("LEFT", bar.name, "RIGHT", 10, 0)
    bar.dot:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
    bar.online = K.Text(bar, 12, C.muted)
    bar.online:SetPoint("LEFT", bar.dot, "RIGHT", 3, 0)
    -- 0.5.574: "4 online" clickable -> member list, online only
    bar.onlineBtn = CreateFrame("Button", nil, bar)
    bar.onlineBtn:SetPoint("TOPLEFT", bar.dot, "TOPLEFT", -4, 6)
    bar.onlineBtn:SetPoint("BOTTOMRIGHT", bar.online, "BOTTOMRIGHT", 4, -6)
    bar.onlineBtn:SetScript("OnClick", function()
        if ns.Radar and ns.Radar.SetFilterOnly then ns.Radar.SetFilterOnly("online") end
        if ns.Expand then ns.Expand("radar") else ns.ShowPage("radar") end
        if ns.Radar and ns.Radar.SetFilter then ns.Radar.SetFilter("online") end
    end)
    bar.onlineBtn:SetScript("OnEnter", function(self)
        bar.online:SetTextColor(C.text[1], C.text[2], C.text[3])
        K.ShowTip(self, L["Click: who is online right now"])
    end)
    bar.onlineBtn:SetScript("OnLeave", function()
        bar.online:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Hide()
    end)

    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetSize(1, 20)
    bar.sep = sep

    bar.quick = {}
    for i, q in ipairs(QUICK) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(22, 22)
        if q.icon then
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(17, 17)
            b.icon:SetTexture(q.icon)
            b.realColor = true
        else
            b.icon = K.Glyph(b, 18, (ns.ICONS and ns.ICONS[q.key]) or (M .. "icons\\home"))
            restTint(b.icon)
        end
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.icon:SetPoint("CENTER")
        b.pill = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.pill:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        b.pill:SetSize(14, 14)
        b.pill:SetPoint("CENTER", b, "TOPRIGHT", -1, -2)
        b.pill:Hide()
        b.badge = b:CreateFontString(nil, "OVERLAY", nil, 3)
        K.SetFontSafe(b.badge, K.FONT_HEAD, 8, "OUTLINE", K.FONT)
        K.CenterNum(b.badge, b.pill, "CENTER", 0, 0)
        -- Neuigkeiten: weiches Leuchten (gemeinsamer, gedrosselter Takt in UI\Main.lua)
        if ns.AttachGlow and not q.action and not q.panel then
            ns.AttachGlow(b, b.icon, 30)
            b.glowKeepColor = b.realColor
            b.glowOff = function(self)
                if self.realColor then self.icon:SetVertexColor(1, 1, 1) else restTint(self.icon) end
            end
        end
        b:SetScript("OnClick", function(_, btn) if q.fn then q.fn(btn) else ns.Expand(q.key) end end)
        b:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            if q.tip then
                local t = {}
                for _, line in ipairs(q.tip) do t[#t + 1] = L[line] end
                K.ShowTip(self, t)
            else
                local def = ns.PageDef and ns.PageDef(q.key)
                local tip = ns.BadgeTip and ns.BadgeTip(q.key)
                if tip then
                    K.ShowTip(self, { L[def and def.title or q.key], tip })
                else
                    K.ShowTip(self, L[def and def.title or q.key])
                end
            end
        end)
        b:SetScript("OnLeave", function(self)
            if self.glowOn then
                self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            elseif self.realColor then
                self.icon:SetVertexColor(1, 1, 1)
            else
                restTint(self.icon)
            end
            GameTooltip:Hide()
        end)
        b.key = q.key
        b.always = q.always
        b.action = q.action
        b.panel = q.panel
        bar.quick[i] = b
    end

    bar.hint = K.Text(bar, 11, C.accent, "RIGHT")
    -- 0.5.954: "N new" is clickable - one page with news: go straight there; several: list to choose from
    bar.hintBtn = CreateFrame("Button", nil, bar)
    bar.hintBtn:SetPoint("TOPLEFT", bar.hint, "TOPLEFT", -4, 6)
    bar.hintBtn:SetPoint("BOTTOMRIGHT", bar.hint, "BOTTOMRIGHT", 4, -6)
    bar.hintBtn:SetFrameLevel(bar:GetFrameLevel() + 6)
    bar.hintBtn:Hide()
    local function news() local _, _, lines = ns.NotifyTotal() return lines or {} end
    bar.hintBtn:SetScript("OnEnter", function(self)
        bar.hint:SetTextColor(C.text[1], C.text[2], C.text[3])
        local tip = { L["News"] }
        for i, l in ipairs(news()) do if i <= 8 then tip[#tip + 1] = l.text .. "  |cffffffff" .. l.n .. "|r" end end
        tip[#tip + 1] = "|cff888888" .. L["Click: open"] .. "|r"
        K.ShowTip(self, tip)
    end)
    bar.hintBtn:SetScript("OnLeave", function()
        bar.hint:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:Hide()
    end)
    bar.hintBtn:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        local lines = news()
        if #lines == 0 then return end
        if #lines == 1 then ns.ShowPage(lines[1].key) return end
        local items = {}
        for _, l in ipairs(lines) do
            local key = l.key
            items[#items + 1] = { text = l.text .. "  |cffff5a4a" .. l.n .. "|r", fn = function() ns.ShowPage(key) end }
        end
        K.ShowMenu(self, items, L["News"])
    end)
    -- compact style (FuBar): lettering instead of wordmark, time on the right
    bar.label = K.Title(logoBtn, 12, C.accent)
    bar.label:SetPoint("LEFT", 0, 0)
    bar.label:SetText("OASIS")
    bar.label:Hide()
    bar.clock = K.Text(bar, 11, C.muted, "RIGHT")
    bar.clock:Hide()

    -- status: own group search, own requests, join requests
    local st = CreateFrame("Button", nil, bar)
    st:SetHeight(28)
    st.sep = st:CreateTexture(nil, "ARTWORK")
    st.sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    st.sep:SetSize(1, 20)
    st.sep:SetPoint("LEFT", 0, 0)
    st.spin = st:CreateTexture(nil, "OVERLAY")
    st.spin:SetTexture(M .. "arc")
    st.spin:SetBlendMode("ADD")
    st.spin:SetSize(18, 18)
    st.spin:SetPoint("LEFT", 10, 0)
    st.dot = st:CreateTexture(nil, "ARTWORK")
    st.dot:SetTexture(M .. "dot")
    st.dot:SetSize(7, 7)
    st.dot:SetPoint("CENTER", st.spin, "CENTER")
    st.text = K.Text(st, 11, C.text)
    st.text:SetPoint("LEFT", st.spin, "RIGHT", 6, 0)
    st.req = K.Title(st, 11, C.accent)
    st.req:SetPoint("LEFT", st.text, "RIGHT", 8, 0)
    local ang, pulse = 0, 0
    st:SetScript("OnUpdate", function(self, el)
        ang = (ang - el * 4) % (math.pi * 2)
        self.spin:SetRotation(ang)
        pulse = pulse + el * 4
        self.req:SetAlpha(0.55 + 0.45 * math.abs(math.sin(pulse)))
    end)
    st:SetScript("OnClick", function() ns.Expand("groups") end)
    st:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
    st:SetScript("OnLeave", function() GameTooltip:Hide() end)
    st:Hide()
    bar.status = st

    -- guide line in the screen center while the bar is nearby
    local guideF = CreateFrame("Frame", nil, UIParent)   -- own layer at the very top, otherwise the lines lie below other frames
    guideF:SetAllPoints(UIParent)
    guideF:SetFrameStrata("FULLSCREEN_DIALOG")
    guideF:EnableMouse(false)
    local guide = guideF:CreateTexture(nil, "OVERLAY")
    guide:SetWidth(2)
    guide:SetPoint("TOP", UIParent, "TOP", 0, 0)
    guide:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    guide:Hide()
    local guideH = guideF:CreateTexture(nil, "OVERLAY")
    guideH:SetHeight(2)
    guideH:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    guideH:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
    guideH:Hide()
    local MID = 70   -- this close to the center it snaps in
    bar:SetScript("OnDragStart", function(self)
        if ns.MiniCompact() then return end   -- compact bar sits fixed at the top
        self.docked = false
        applyDockLook()
        self:StartMoving()
        local ac = C.accent
        guide:SetColorTexture(ac[1], ac[2], ac[3], 0.6)
        guideH:SetColorTexture(ac[1], ac[2], ac[3], 0.6)
        self.dragging = true
    end)
    local drv = CreateFrame("Frame", nil, bar)   -- own tick (bar sets OnUpdate itself later)
    drv:SetScript("OnUpdate", function()
        local self = bar
        if not self.dragging then return end
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not cx then return end
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        guide:SetShown(math.abs(cx * s - ux) < MID)
        guideH:SetShown(math.abs(cy * s - uy) < MID and (UIParent:GetTop() - (self:GetTop() or 0)) >= SNAP)
    end)
    bar:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self:StopMovingOrSizing()
        self.dragging = nil
        guide:Hide() guideH:Hide()
        local top = self:GetTop() or 0
        if (UIParent:GetTop() - top) < SNAP then dock() end
        -- snap in the center: horizontally (and vertically too when floating freely)
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local dx, dy = cx * s - ux, cy * s - uy
        if math.abs(dx) < MID then dx = 0 end
        if self.docked then
            self:ClearAllPoints()
            self:SetPoint("TOP", UIParent, "TOP", dx / s, 0)
        else
            if math.abs(dy) < MID then dy = 0 end
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", dx / s, dy / s)
        end
        savePos()
        applyDockLook()
    end)
    -- dragging also over the buttons (otherwise there's hardly any free surface to grab)
    local function fwd(c)
        if c == bar.closeX or not c.RegisterForDrag or c.oasisDragFwd then return end
        c.oasisDragFwd = true
        c:RegisterForDrag("LeftButton")
        c:HookScript("OnDragStart", function() if not InCombatLockdown() then bar:GetScript("OnDragStart")(bar) end end)
        c:HookScript("OnDragStop", function() if bar.dragging then bar:GetScript("OnDragStop")(bar) end end)
    end
    bar.FwdDrag = function() for _, c in ipairs({ bar:GetChildren() }) do if c:IsObjectType("Button") and not c:IsProtected() then fwd(c) end end end
    C_Timer.After(1, bar.FwdDrag)

    -- roll up: bar slides up to a narrow edge, comes down on hover
    bar.slide = 0          -- 0 = fully visible, 1 = rolled up
    local slideDrv = CreateFrame("Frame", nil, UIParent)
    local away = 0
    slideDrv:SetScript("OnUpdate", function(_, el)
        if not bar:IsShown() then return end
        local auto = ns.MiniAutoHide and ns.MiniAutoHide()
        local want = 0
        if auto and not bar.dragging and not bar.preview then
            -- 0.6.260: with ember image the rolled-up bar sits entirely above the screen edge - only the image
            -- below is visible; the mouse there must also roll it out (extend area downward around the image + leeway)
            local below = (bar.art and bar.art.m and bar.art.m:IsShown()) and -14 or 0
            if bar:IsMouseOver(4, below, 0, 0) or (GameTooltip:IsShown() and GameTooltip:GetOwner() and GameTooltip:GetOwner():GetParent() == bar) then
                away = 0
            else
                away = away + el
            end
            want = away > 0.8 and 1 or 0
        end
        if math.abs(bar.slide - want) < 0.01 then
            if bar.slide ~= want then bar.slide = want ns.PlaceMiniBar() end
            return
        end
        bar.slide = bar.slide + (want - bar.slide) * math.min(1, el * 12)
        ns.PlaceMiniBar()
    end)

    -- restore position (default: docked at the top center)
    local pos = ns.db.settings.miniPos
    bar:ClearAllPoints()
    if pos and pos.p then
        bar:SetPoint(pos.p, UIParent, pos.rp or pos.p, pos.x or 0, pos.y or 0)
        bar.docked = pos.docked
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
        bar.docked = true
    end
    applyDockLook()

    local elapsed = 0
    bar:SetScript("OnUpdate", function(self, el)
        elapsed = elapsed + el
        if elapsed < 2 then return end
        elapsed = 0
        ns.UpdateMiniBar()
    end)
    bar:Hide()
end

-- content and width of the bar
-- top bar background transparency (Settings > Top bar)
function ns.ApplyMiniAlpha()
    local b = ns._miniBar
    local a = ns.db and ns.db.settings.miniAlpha or 1
    if b and b.bgParts then for _, t in ipairs(b.bgParts) do t:SetAlpha(a) end
    elseif b and b.bgTex then b.bgTex:SetAlpha(a) end
    -- 0.6.261: also the ember image (guild module) - otherwise the slider had no effect when pinned at the top
    if b and b.art then for _, k in ipairs({ "l", "m", "r" }) do if b.art[k] then b.art[k]:SetAlpha(a) end end end
    if ns.TintMiniArt then pcall(ns.TintMiniArt) end   -- 0.6.263: also tint when building/adjusting
end
-- 0.6.263: the bar's ember image follows the accent color (like start window and backgrounds): original for red,
-- otherwise desaturated and in the accent color
local function tintMiniArt()
    local b = ns._miniBar
    if not (b and b.art) then return end
    local ac = C.accent or { 1, 0.2, 0.2 }
    local red = ac[1] > 0.55 and ac[2] < 0.45 and ac[3] < 0.45
    for _, k in ipairs({ "l", "m", "r" }) do
        local t = b.art[k]
        if t then
            t:SetDesaturated(not red)
            if red then t:SetVertexColor(1, 1, 1)
            else t:SetVertexColor(math.min(1, ac[1] * 1.6), math.min(1, ac[2] * 1.6), math.min(1, ac[3] * 1.6)) end
        end
    end
end
ns.TintMiniArt = tintMiniArt
-- bundled (performance 0.5.482): triggered on every counter update, group change and sync record
-- - now at most once per 0.1 s instead of hundreds of times during login sync
local mbPending = false
local updateMiniBarNow
function ns.UpdateMiniBar()
    if mbPending then return end
    mbPending = true
    C_Timer.After(0.1, function()
        mbPending = false
        local ok, e = pcall(updateMiniBarNow)
        if not ok then ns.err("Top bar", e) end
    end)
end
function ns.UpdateMiniBarNow() return updateMiniBarNow() end
function updateMiniBarNow()
    if bar and bar.wm then
        local hide = ns.db and ns.db.settings.miniNoLogo
        bar.name:SetWidth(hide and 16 or 76)
        bar.wm:SetShown(not hide)
        bar.plus:SetShown(false)   -- 0.6.252: no plus anymore (click on the left keeps expanding)
    end
    if not bar then return end
    local compact = ns.MiniCompact()
    -- 0.5.560: more styles - minimal (icons only, narrow) and dock (large icons, grow on hover)
    local style = ns.MiniStyle and ns.MiniStyle() or "normal"
    local minimal, dock = style == "minimal", style == "dock"
    local slim = minimal or dock
    bar:SetScale(math.max(0.6, math.min(1.6, (ns.db and ns.db.settings.miniScale) or 1)))
    bar:SetHeight(compact and 24 or (minimal and 30) or (dock and 48) or 38)
    bar.wm:SetShown(not compact and not slim and not (ns.db and ns.db.settings.miniNoLogo))
    bar.plus:SetShown(false)   -- 0.6.252: no plus anymore
    bar.label:SetShown(compact)
    if compact then bar.name:SetWidth(bar.label:GetStringWidth() + 2) elseif slim then bar.name:SetWidth(16) end
    bar.dot:SetSize(compact and 8 or 12, compact and 8 or 12)
    bar.dot:SetShown(not slim)
    bar.online:SetShown(not slim)
    if bar.onlineBtn then bar.onlineBtn:SetShown(not slim) end
    bar.sep:SetShown(not slim)
    bar.sep:SetHeight(compact and 14 or 20)
    local online = ns.Radar and ns.Radar.online or 0
    bar.online:SetText((L["%d online"]):format(online))
    -- without logo everything moves together (bar gets narrower)
    local logoW = compact and (bar.label:GetStringWidth() + 2) or ((slim or (ns.db and ns.db.settings.miniNoLogo)) and 16 or 76)
    local x
    if slim then
        x = 12 + logoW + 12
    else
        x = (compact and 10 or 12) + logoW + (compact and 10 or 12) + 12 + 3 + bar.online:GetStringWidth() + 12
        bar.sep:ClearAllPoints()
        bar.sep:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + 10
    end
    local BS = compact and 20 or (dock and 34) or 22
    local IS = compact and 14 or (dock and 26) or nil
    local STEP = compact and 22 or (dock and 38) or (minimal and 24) or 26
    local total = 0
    for _, b in ipairs(bar.quick) do
        b:ClearAllPoints()
        local vis
        if b.action then
            vis = ns.MiniQuickOn(b.key) and IsInGroup and IsInGroup() and true or false
        elseif b.panel then
            vis = ns.MiniQuickOn(b.key)
        else
            vis = ns.MiniQuickOn(b.key) and (not ns.PageVisible or ns.PageVisible(b.key)) and (ns.PageDef and ns.PageDef(b.key) ~= nil)
        end
        b:SetShown(vis)
        b:SetSize(BS, BS)
        local isz = IS or (b.realColor and 17 or 18)
        b.baseIcon = isz
        if b.icon then b.icon:SetSize(isz, isz) end
        -- dock: icon grows on hover
        if b.icon and not b.dockHook then
            b.dockHook = true
            b:HookScript("OnEnter", function(self)
                if not (ns.MiniStyle and ns.MiniStyle() == "dock") or not K.Tween then return end
                local base = self.baseIcon or 26
                K.Tween(self.icon, 0.12, function(q) self.icon:SetSize(base * (1 + 0.32 * q), base * (1 + 0.32 * q)) end)
            end)
            b:HookScript("OnLeave", function(self)
                if not (ns.MiniStyle and ns.MiniStyle() == "dock") or not K.Tween then return end
                local base = self.baseIcon or 26
                K.Tween(self.icon, 0.15, function(q) self.icon:SetSize(base * (1.32 - 0.32 * q), base * (1.32 - 0.32 * q)) end)
            end)
        end
        if vis then
            b:SetPoint("LEFT", bar, "LEFT", x, 0)
            x = x + STEP
        end
        local raw = tostring(ns._badges and ns._badges[b.key] or "")
        local n = tonumber(raw:match("(%d+)")) or ((raw ~= "") and 1 or 0)
        if n > 0 and ns.NavMuted and ns.NavMuted(b.key) then n = 0 end
        local c = raw:find("@", 1, true) and C.amber or C.accent
        b.pill:SetVertexColor(c[1], c[2], c[3])
        b.pill:SetShown(n > 0)
        b.badge:SetText(n > 0 and (n > 99 and "99" or tostring(n)) or "")
        b.hot = n > 0
        -- glows while there is news that hasn't been viewed yet (also subpages of a hub)
        if b.nglow then
            local on, ping = false, nil
            if vis and ns.GlowState then on, ping = ns.GlowState(b.key) end
            b.glowOn = on
            ns.SetGlow(b, on, ping)
        end
        if b.action then
            local sec = ns.Marker and ns.Marker.Secure and ns.Marker.Secure()
            if sec and not InCombatLockdown() then
                -- don't attach to the bar (otherwise the bar would be locked in combat): screen coordinates
                local function place()
                    if InCombatLockdown() then return end
                    local l, bt = b:GetLeft(), b:GetBottom()
                    if not (l and bt and b:IsVisible()) then sec:Hide() return end
                    local r = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    -- 0.5.741: all the way to the front (same strata as the bar, but higher than all its children) - otherwise the bar caught the click
                    -- and only 'Auto marker realigned' appeared
                    sec:SetFrameStrata("HIGH")
                    sec:SetFrameLevel(math.min(65000, bar:GetFrameLevel() + 80))
                    sec:ClearAllPoints()
                    sec:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * r, bt * r)
                    sec:SetSize(b:GetWidth() * r, b:GetHeight() * r)
                    sec:Show()
                end
                if not sec.barHooked then
                    sec.barHooked = true
                    bar:HookScript("OnHide", function() if not InCombatLockdown() then sec:Hide() end end)
                    bar:HookScript("OnDragStop", function() C_Timer.After(0, place) end)
                    bar:HookScript("OnShow", function() C_Timer.After(0, place) end)
                end
                if vis then
                    C_Timer.After(0, place)
                    if not sec.tipHooked then
                        sec.tipHooked = true
                        sec:HookScript("OnEnter", function() local s = b:GetScript("OnEnter") if s then s(b) end end)
                        sec:HookScript("OnLeave", function() local s = b:GetScript("OnLeave") if s then s(b) end end)
                    end
                else
                    sec:Hide()
                end
            end
        end
        if not b.glowOn then
            if b.realColor then b.icon:SetVertexColor(1, 1, 1) else restTint(b.icon) end
        end
    end
    total = ns.NotifyTotal and ns.NotifyTotal() or 0
    bar.hint:ClearAllPoints()
    bar.hint:SetPoint("LEFT", bar, "LEFT", x + 6, 0)
    bar.hint:SetText(total > 0 and (L["%d new"]):format(total) or "")
    if bar.hintBtn then bar.hintBtn:SetShown(total > 0) end
    local w = x + 10 + (total > 0 and (bar.hint:GetStringWidth() + 8) or 0)

    -- group status
    local st = bar.status
    local G = ns.Groups
    local mine = G and G.Mine()
    local asked = {}
    if G and G.joined then
        for _, g in ipairs(G.Active()) do
            local role = G.MyRequest(g)
            if role then asked[#asked + 1] = g end
        end
    end
    local reqs = 0
    if mine then for _, q in pairs(G.requests) do if q.state ~= "invited" then reqs = reqs + 1 end end end
    if mine or #asked > 0 then
        if mine then
            local taken = 0
            for _, s in ipairs(G.Slots(mine)) do if s.who then taken = taken + 1 end end
            st.text:SetText((L["Looking: %s"]):format(mine.title or "?") .. "  |cff888888" .. taken .. "/5|r")
            st.tip = { L["Your group search is running"], mine.title or "?", L["Click: open groups"] }
        else
            local g = asked[1]
            st.text:SetText((L["Requested: %s"]):format(g.title or "?") .. (#asked > 1 and ("  |cff888888+" .. (#asked - 1) .. "|r") or ""))
            local t = { L["Waiting for an invite"] }
            for _, a in ipairs(asked) do t[#t + 1] = (a.title or "?") .. "  |cff888888" .. ns.displayName(a.who) .. "|r" end
            t[#t + 1] = L["Click: open groups"]
            st.tip = t
        end
        st.req:SetText(reqs > 0 and ((reqs == 1 and L["1 request"]) or (L["%d requests"]):format(reqs)) or "")
        st.dot:SetVertexColor(reqs > 0 and C.accent[1] or C.mint[1], reqs > 0 and C.accent[2] or C.mint[2], reqs > 0 and C.accent[3] or C.mint[3])
        st:ClearAllPoints()
        st:SetPoint("LEFT", bar, "LEFT", w, 0)
        local sw = 34 + st.text:GetStringWidth() + (reqs > 0 and (st.req:GetStringWidth() + 10) or 0)
        st:SetWidth(sw)
        st:Show()
        w = w + sw + 8
    else
        st:Hide()
    end
    -- compact: time on the right (before the X), width = whole screen (see PlaceMiniBar)
    bar.clock:SetShown(compact)
    if compact then
        bar.clock:ClearAllPoints()
        bar.clock:SetPoint("RIGHT", bar, "RIGHT", (bar.closeX and bar.closeX:IsShown()) and -34 or -10, 0)
        bar.clock:SetText(date("%H:%M"))
    end
    bar:SetWidth(math.max(200, w + 26))
    ns.PlaceMiniBar()
end

-- style / roll up (Settings > Top bar)
function ns.MiniCompact() return ns.db and ns.db.settings.miniStyle == "compact" or false end
function ns.MiniStyle()
    local st = ns.db and ns.db.settings.miniStyle
    return (st == "compact" or st == "minimal" or st == "dock") and st or "normal"
end
function ns.MiniAutoHide()
    if not (ns.db and ns.db.settings.miniAutoHide) or not bar then return false end
    return ns.MiniCompact() or bar.docked == true
end
-- put the bar in its place: compact = full width at the top; docked = at the top at the remembered spot;
-- when rolled up shifted up by (height - 3)
function ns.PlaceMiniBar()
    if not bar or bar.dragging then return end
    local compact = ns.MiniCompact()
    local auto = ns.MiniAutoHide()
    -- 0.6.259: with ember image (sticks out 8 below the bar) further up - only the lowest red line stays visible
    local art = bar.art and bar.art.m and bar.art.m:IsShown()
    local travel = art and (bar:GetHeight() + 8 - 5) or (bar:GetHeight() - 3)
    local off = auto and math.floor(travel * (bar.slide or 0) + 0.5) or 0
    bar:SetClampedToScreen(not auto)
    if compact then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, off)
        bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, off)
        bar.docked = true
    elseif bar.docked then
        local pos = ns.db.settings.miniPos
        local x = pos and pos.docked and pos.p == "TOP" and pos.x or bar.dockX or 0
        bar.dockX = x
        bar:ClearAllPoints()
        bar:SetPoint("TOP", UIParent, "TOP", x, off)
    end
    if bar.Shape then
        bar:Shape()
        -- compact: all corners square (continuous bar)
        if compact then for _, c in pairs(bar.corners) do c:SetTexture("Interface\\Buttons\\WHITE8X8") c:SetTexCoord(0, 1, 0, 1) end
            for _, a in pairs(bar.arcs or {}) do a:Hide() a.glow:Hide() end end
    end
end

-- when does the top bar appear? (Settings > Top bar, guild request 07.10.)
--   collapse = on close Oasis collapses into the bar (previous behavior)
--   always   = bar is always there from login and never disappears
--   off      = never: the X simply closes Oasis, no bar
function ns.TopbarMode()
    local m = ns.db and ns.db.settings.topbarMode
    return (m == "always" or m == "off") and m or "collapse"
end

-- X on the bar: close Oasis completely (open via minimap button or /oasis) - not with "always"
local function addCloseX()
    do return end   -- 0.6.252: no X on the bar anymore (close via Settings > Top bar or /oasis)
    if not bar or bar.closeX then return end
    bar.closeX = ns.K.CloseButton(bar, function() ns.HideMiniBar() end, L["Close fully (/oasis reopens)"])
    bar.closeX:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.closeX:SetFrameLevel(bar:GetFrameLevel() + 10)
end
-- design/accent changed: recolor top bar (0.5.540 - previously it kept the old colors until /reload)
function ns.RestyleMiniBar()
    if not bar then return end
    local bc, ac = C.bg, C.accent
    for _, t in ipairs(bar.bgParts or {}) do t:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1) end
    if bar.accent then bar.accent:SetColorTexture(ac[1], ac[2], ac[3], 1) end
    for _, fs in ipairs({ bar.plus, bar.hint, bar.label }) do if fs and fs.SetTextColor then fs:SetTextColor(ac[1], ac[2], ac[3]) end end
    if bar.Shape then pcall(bar.Shape, bar) end
    if ns.ApplyMiniAlpha then pcall(ns.ApplyMiniAlpha) end
    pcall(tintMiniArt)   -- 0.6.263
    if ns.UpdateMiniBarNow then pcall(ns.UpdateMiniBarNow) elseif ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end
end
ns.Listen("BRAND", function() ns.Debounce("miniRestyle", 0.2, function() pcall(ns.RestyleMiniBar) end) end)
function ns.ShowMiniBar()
    if not bar then build() end
    addCloseX()
    if not bar then build() end
    bar.preview = nil
    if bar.closeX then bar.closeX:SetShown(ns.TopbarMode() ~= "always") end
    ns.UpdateMiniBar()
    bar:Show()
    ns.db.settings.collapsed = true
end
function ns.HideMiniBar(force)
    if not force and ns.TopbarMode() == "always" then return end
    if bar then bar:Hide() bar.preview = nil end
    if ns.db then ns.db.settings.collapsed = false end
end
-- setting changed: apply immediately
function ns.ApplyTopbarMode()
    local m = ns.TopbarMode()
    if m == "always" then ns.ShowMiniBar()
    elseif m == "off" then ns.HideMiniBar(true)
    elseif bar and bar.closeX then bar.closeX:Show() end
end
-- preview (Settings > Top bar): show the real bar in its place without collapsing
function ns.PreviewMiniBar(on)
    if on then
        if not bar then build() addCloseX() end
        if bar:IsShown() then return end
        bar.preview = true
        ns.UpdateMiniBar()
        if ns.ApplyMiniAlpha then ns.ApplyMiniAlpha() end
        bar:Show()
    elseif bar and bar.preview then
        bar.preview = nil
        if not (ns.db and ns.db.settings.collapsed) then bar:Hide() end
    end
end

-- window <-> bar: the window shrinks into the top bar (or grows out of it).
-- real movement instead of an effect: center moves to the bar, size shrinks, at the end it fades out.
-- positions in UIParent units; the frame is set via center+scale meanwhile.
local flyDrv
local function uiCenter(f)
    local x, y = f:GetCenter()
    if not x then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k
end
-- 0.5.645: instead of scaling the real window every frame (hundreds of elements, fonts, masks -> stutter)
-- a light ghost frame flies (surface + border). The real window stays still and only fades in/out softly.
local ghost
local function ghostFrame()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("HIGH")
    ghost:SetFrameLevel(50)
    ghost.bg = K.Fill(ghost, C.bg)
    K.Border(ghost, C.line)
    ghost:Hide()
    return ghost
end
local function flyWindow(mf, toBar, done, target)
    local tgt = target or bar
    local anim = not (ns.db and ns.db.settings.noAnim)
    -- without animation: final state immediately
    local function bail()
        if toBar then mf:Hide() else mf:SetAlpha(1) end
        if done then done() end
    end
    if not (anim and mf and tgt and tgt:IsShown()) then return bail() end
    if flyDrv and flyDrv.finish then flyDrv.finish() end
    if not toBar then mf:SetAlpha(0) mf:Show() end
    local bx, by = uiCenter(tgt)
    local wx, wy = uiCenter(mf)
    if not (bx and wx) then return bail() end
    local k = mf:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local ww, wh = mf:GetWidth() * k, mf:GetHeight() * k
    local tw, th = math.max(24, tgt:GetWidth() * 0.5), math.max(12, tgt:GetHeight())
    local a0 = 1
    local g = ghostFrame()
    g:SetScale(1)
    g:SetAlpha(1)
    local barA = tgt:GetAlpha()
    flyDrv = flyDrv or CreateFrame("Frame", nil, UIParent)
    ns._flyDrv = flyDrv
    local dur, t = toBar and 0.22 or 0.24, 0
    local function place(p)
        -- p: 0 = window in its place, 1 = fully in the bar
        local cx, cy = wx + (bx - wx) * p, wy + (by - wy) * p
        g:SetSize(ww + (tw - ww) * p, wh + (th - wh) * p)
        g:ClearAllPoints()
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        g:SetAlpha(math.min(1, (1 - p) * 1.4 + 0.15))
    end
    if toBar then
        -- real window gone immediately (costs nothing anymore), the ghost takes over
        mf:Hide()
        mf:SetAlpha(a0)
    end
    function flyDrv.finish()
        flyDrv:SetScript("OnUpdate", nil)
        flyDrv.finish = nil
        g:Hide()
        mf:SetAlpha(a0)
        tgt:SetAlpha(barA)
        if done then done() end
    end
    place(toBar and 0 or 1)
    g:Show()
    flyDrv:SetScript("OnUpdate", function(_, el)
        -- don't count the first frame after building (building the page can take a while) as a jump
        t = t + math.min(el, 1 / 30)
        local q = math.min(1, t / dur)
        if toBar then
            place(q * q * q)                                   -- in: start softly, speed up
        else
            local e = 1 - (1 - q) ^ 3                          -- out: start fast, ease out gently
            place(1 - e)
            -- last third: real window fades in over the ghost
            if q > 0.66 then mf:SetAlpha(a0 * (q - 0.66) / 0.34) end
        end
        if toBar and q > 0.6 then tgt:SetAlpha(barA * (0.75 + 0.25 * math.sin((q - 0.6) / 0.4 * math.pi))) end
        if q >= 1 then flyDrv.finish() end
    end)
end

-- minimap button: window flies into the button or out of it
function ns.FlyToggle(target)
    local mf = ns.MainFrame and ns.MainFrame()
    if mf and mf:IsShown() then
        if not pcall(flyWindow, mf, true, nil, target) then mf:Hide() end
    else
        ns.OpenMain()
        mf = ns.MainFrame and ns.MainFrame()
        if mf and mf:IsShown() then pcall(flyWindow, mf, false, nil, target) end
    end
end

-- collapse: main window closed, bar open
function ns.Collapse(force)
    local mf = ns.MainFrame and ns.MainFrame()
    -- top bar "never": simply close (unless explicitly /oa mini or "Collapse now")
    if ns.TopbarMode() == "off" and not force then
        if mf and mf:IsShown() then mf:Hide() end
        return
    end
    ns.ShowMiniBar()
    if mf and mf:IsShown() then
        local ok = pcall(flyWindow, mf, true)
        if not ok then mf:Hide() end
    end
end
-- expand, optionally straight to a page
function ns.Expand(page)
    -- top bar stays visible (only the X on the bar closes it)
    local mf = ns.MainFrame and ns.MainFrame()
    local wasShown = mf and mf:IsShown()
    if page then ns.ShowPage(page) else ns.OpenMain() end
    mf = ns.MainFrame and ns.MainFrame()
    if mf and not wasShown and mf:IsShown() then pcall(flyWindow, mf, false) end
end

ns.slash.mini = function()
    if bar and bar:IsShown() then ns.Expand() else ns.Collapse(true) end
end
ns.slash.leiste = ns.slash.mini

-- keep collapsed state across /reload and login
ns.Listen("LOGIN", function()
    local m = ns.TopbarMode()
    if m == "off" then ns.db.settings.collapsed = false return end
    if m == "always" or ns.db.settings.collapsed then ns.After(3, ns.ShowMiniBar) end
end)
-- on logout record whether the bar was really open (otherwise it got lost at the next login)
ns.On("PLAYER_LOGOUT", function()
    if bar and ns.db then
        if bar:IsShown() and not bar.preview then ns.db.settings.collapsed = true end
    end
end)

-- join/leave group: show/hide marker button
ns.On("GROUP_ROSTER_UPDATE", function() if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end end)

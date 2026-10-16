-- Oasis: drehender Ring ums Logo + eingeklappte Oasis-Leiste (frei ziehbar, rastet oben am Bildschirmrand ein)
local ADDON, ns = ...
local K, C, L = ns.K, ns.K.C, ns.L
local M = ns.MEDIA

------------------------------------------------------------------------
-- Drehender Ring (Verlauf Blau > Violett > Pink) um ein rundes Logo
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
-- Animierte Wortmarke: roter Lichtstreifen laeuft durch die Buchstaben
-- (per Maske nur auf der Schrift), darunter eine Linie mit wanderndem Lichtpunkt
------------------------------------------------------------------------
local wordmarks = setmetatable({}, { __mode = "k" })
-- Akzentfarbe geaendert: alle Wortmarken (Seitenleiste, Leiste) umfaerben
ns.Listen("BRAND", function() for wm in pairs(wordmarks) do wm:UpdateColor() end end)
function ns.Wordmark(parent, w, h, withLine)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    local base = f:CreateTexture(nil, "ARTWORK")
    base:SetTexture(M .. "wordmark_base")     -- Buchstaben ohne i
    base:SetAllPoints()
    f.base = base
    -- das i als eigene Ebene in der Akzentfarbe (folgt Design/Akzent)
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

    -- Takt: alle 5 s ein Durchlauf (1,4 s), die Linie laeuft staendig langsam
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
-- Oasis-Leiste
------------------------------------------------------------------------
local bar
-- Seiten, die als Knopf in der Leiste stehen koennen (Auswahl in den Einstellungen, Reiter "Leiste")
local QUICK_ALL = { "home", "insta", "chat", "radar", "chronicle", "polls", "groups", "social", "allies", "dungeons", "camp",
    "raid", "buffs", "crafting", "trade", "wants", "bank", "deathroll", "deaths", "legacy", "badges" }
local QUICK_DEFAULT = { home = true, chat = true, groups = true, dungeons = true, raid = true, crafting = true, mark = true }
ns.MINI_QUICK_ALL, ns.MINI_QUICK_DEFAULT = QUICK_ALL, QUICK_DEFAULT
function ns.MiniQuickOn(key)
    local sel = ns.db and ns.db.settings.miniPages
    if sel == nil then return QUICK_DEFAULT[key] or false end
    -- frueherer eigener Knopf "Buff-Monitor-Fenster" ist jetzt der Buff-Monitor-Knopf selbst
    if key == "buffs" and sel.buffmon then return true end
    return sel[key] and true or false
end
local QUICK = {}
for _, k in ipairs(QUICK_ALL) do QUICK[#QUICK + 1] = { key = k } end
-- Buff-Monitor in der Leiste: oeffnet das kleine schwebende Fenster statt der grossen Seite
for _, q in ipairs(QUICK) do
    if q.key == "buffs" then
        q.tip = { "Buff-Monitor", "Klick: Fenster ein/aus", "Rechtsklick: Seite im Oasis-Fenster" }
        q.fn = function(btn)
            if btn == "RightButton" then ns.Expand("buffs") return end
            if ns.BuffMonitor and ns.BuffMonitor.Toggle then ns.BuffMonitor.Toggle() end
        end
    end
end
-- Aktion statt Seite: Auto-Marker (nur in einer Gruppe sichtbar)
QUICK[#QUICK + 1] = { key = "mark", action = true, icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    tip = { "Auto-Marker", "Linksklick: Gegner markieren (nochmal = Marken weg)", "Rechtsklick: Marken entfernen", "Shift + Klick: Auto-Marker-Fenster" },
    -- kommt der Klick hier an, lag der sichere Knopf nicht darueber -> neu ausrichten
    fn = function()
        -- 0.5.735: Shift + Klick oeffnet das Fenster auch dann, wenn der sichere Knopf den Klick nicht abfaengt (Makro /oa mark button)
        if IsShiftKeyDown and IsShiftKeyDown() and ns.Marker and ns.Marker.Toggle then ns.Marker.Toggle() return end
        if InCombatLockdown() then ns.print(ns.L["Auto-Marker: nach dem Kampf nochmal klicken."]) return end
        if ns.UpdateMiniBar then ns.UpdateMiniBar() end
        ns.print(ns.L["Auto-Marker neu ausgerichtet - bitte nochmal klicken."])
    end }

-- Popout-Fenster ein/aus (Auto-Marker-Box, Buff-Monitor)
QUICK[#QUICK + 1] = { key = "markbox", panel = true, icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    tip = { "Auto-Marker-Fenster", "Klick: Fenster ein/aus" },
    fn = function() if ns.Marker and ns.Marker.Toggle then ns.Marker.Toggle() end end }
-- fuer Einstellungen/Vorschau
ns.MINI_QUICK_PANELS = {
    { key = "markbox", label = "Auto-Marker-Fenster", icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath" },
}

local SNAP = 36   -- so nah am oberen Rand rastet die Leiste ein

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
    bar:SetFrameStrata("HIGH")   -- ueber Aktionsleisten (unten angeheftet sonst nicht mehr greifbar)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    -- Hintergrund aus 9 Teilen: Ecken rund oder eckig, je nachdem an welchem Bildschirmrand die Leiste sitzt
    -- (oben -> unten rund, unten -> oben rund, links -> rechts rund, rechts -> links rund, frei -> alle rund)
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
    -- leichter Glanz
    local sheen = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetPoint("TOPLEFT", R, 0) sheen:SetPoint("TOPRIGHT", -R, 0) sheen:SetHeight(16)
    if not K.Gradient(sheen, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.045 }) then sheen:Hide() end
    bar.sheen = sheen   -- Shape() zieht ihn bis an den Rand (0.5.702)
    bar.topLine = bar:CreateTexture(nil, "BORDER")   -- alt (frei schwebend), bleibt unsichtbar
    bar.topLine:Hide()
    ns._miniBar = bar
    if ns.ApplyMiniAlpha then ns.ApplyMiniAlpha() end
    -- Akzentlinie + Schein auf der Innenseite (vom Rand weg)
    bar.accent = bar:CreateTexture(nil, "ARTWORK")
    bar.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar.accentGlow = bar:CreateTexture(nil, "ARTWORK")
    -- Rand bestimmen und Ecken/Akzent setzen
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
        -- volle Breite (Kompakt-Leiste): links/rechts liegt die Leiste am Bildschirmrand -> dort eckig,
        -- Linie und Schein laufen bis ganz an den Rand
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
        -- Glanz bis ganz an den Rand (vorher 10 px Einzug -> links/rechts wirkte die Leiste dunkler);
        -- runde obere Ecken werden per Maske abgeschnitten (nur diese beiden Ecken, WoW erlaubt hoechstens 3 Masken)
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
        -- Akzent laeuft in den runden Ecken als Bogen bis an den Rand weiter
        self.arcs = self.arcs or {}
        for k, c in pairs(self.corners) do
            local arc = self.arcs[k]
            if not arc then
                -- Bogen (gleiche Staerke wie die Linie) + Schein, beide exakt auf der Rundung (Media/skins/arc_corner, glow_corner)
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
            -- Linie endet am Bogen (bzw. am Bildschirmrand); der Schein laeuft weiter in die Rundung hinein
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

    -- 0.6.244: oben angeheftet = Glut-Leiste als Bild (Gildenmodul, Tools/make_minibar.py): oben gerade, unten rund.
    -- Drei Teile (Enden + dehnbare Mitte), damit die Rundungen bei jeder Breite rund bleiben. Sonst die normale Leiste.
    if ns.GuildPack then
        local GP = "Interface\\AddOns\\Oasis_Guild\\Media\\"
        bar.art = {}
        for _, k in ipairs({ "l", "m", "r" }) do
            local t = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
            t:SetTexture(GP .. "minibar_" .. k)
            t:Hide()
            bar.art[k] = t
        end
        -- 0.6.248: Bild ragt unten 8 ueber die Leiste hinaus - Gluehlinie sass zu dicht unter den Symbolen
        local DROP = 8
        bar.art.l:SetPoint("TOPLEFT") bar.art.l:SetPoint("BOTTOMLEFT", 0, -DROP)
        bar.art.r:SetPoint("TOPRIGHT") bar.art.r:SetPoint("BOTTOMRIGHT", 0, -DROP)
        bar.art.m:SetPoint("TOPLEFT", bar.art.l, "TOPRIGHT") bar.art.m:SetPoint("BOTTOMRIGHT", bar.art.r, "BOTTOMLEFT")
        -- 0.6.311: leichter Schimmer - additive Kopie des Bildes atmet langsam (aus mit "Animationen aus")
        bar.shine = {}
        for _, k in ipairs({ "l", "m", "r" }) do
            local s = bar:CreateTexture(nil, "BACKGROUND", nil, 3)
            s:SetTexture(GP .. "minibar_" .. k)
            s:SetBlendMode("ADD")
            s:SetAllPoints(bar.art[k])
            s:SetAlpha(0)
            bar.shine[k] = s
        end
        -- 0.6.330: Lichtstreif laeuft alle 5 s entlang der Glutlinie unten
        local sw = bar:CreateTexture(nil, "BACKGROUND", nil, 4)
        sw:SetSize(160, 4)
        sw:SetBlendMode("ADD")
        if not K.Gradient(sw, "HORIZONTAL", { 1, 0.85, 0.7, 0 }, { 1, 0.85, 0.7, 0.9 }) then sw:SetColorTexture(1, 0.85, 0.7, 0.4) end
        local sw2 = bar:CreateTexture(nil, "BACKGROUND", nil, 4)
        sw2:SetBlendMode("ADD")
        if not K.Gradient(sw2, "HORIZONTAL", { 1, 0.85, 0.7, 0.9 }, { 1, 0.85, 0.7, 0 }) then sw2:SetColorTexture(1, 0.85, 0.7, 0.4) end
        sw2:SetPoint("TOPLEFT", sw, "TOPRIGHT") sw2:SetPoint("BOTTOMLEFT", sw, "BOTTOMRIGHT") sw2:SetWidth(160)
        sw:Hide() sw2:Hide()
        local swT = 0
        local clock = 0
        local pulse = CreateFrame("Frame", nil, bar)
        pulse:SetScript("OnUpdate", function(_, el)
            local st = ns.db and ns.db.settings
            local on = not (st and st.noAnim)
            if on then clock = clock + (el or 0) end
            -- Streif nur, wenn das Glut-Bild zu sehen ist
            local showArt = on and bar.art.m:IsShown()
            if showArt then
                swT = (swT + (el or 0)) % 5
                local p = swT / 1.8
                local W = bar:GetWidth() or 600
                if p < 1 then
                    local e = p * p * (3 - 2 * p)
                    local x = -320 + e * (W + 320)
                    sw:ClearAllPoints()
                    sw:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, -5)
                    local a = math.sin(p * math.pi) * (bar.art.m:GetAlpha() or 1)
                    sw:SetAlpha(a) sw2:SetAlpha(a)
                    sw:SetShown(x > -160 and x < W) sw2:SetShown(x + 160 > 0 and x + 160 < W)
                else
                    sw:Hide() sw2:Hide()
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
        C_Timer.After(0, function() if ns.ApplyMiniAlpha then pcall(ns.ApplyMiniAlpha) end end)   -- 0.6.263: Deckkraft + Farbe gleich anwenden
        local baseShape = bar.Shape
        function bar:Shape()
            baseShape(self)
            -- 0.6.257: nur mit Bild (Textur geladen) - sonst stand die Leiste ganz ohne Hintergrund da
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
        -- vorher versteckte Teile wieder zeigen, wenn die Leiste vom oberen Rand weggezogen wird
        local baseShape2 = bar.Shape
        function bar:Shape()
            for _, t in ipairs(self.bgParts) do t:Show() end
            if self.sheen then self.sheen:Show() end
            baseShape2(self)
        end
        -- 0.6.257: UI-Skala geaendert (z. B. EllesmereUI setzt UIParent:SetScale) -> Rand neu bestimmen und Form nachziehen
        local reshape = CreateFrame("Frame")
        for _, ev in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_ENTERING_WORLD" }) do pcall(reshape.RegisterEvent, reshape, ev) end
        reshape:SetScript("OnEvent", function() C_Timer.After(1, function() if bar and bar.Shape then pcall(bar.Shape, bar) end end) end)
        -- Enden-Breite folgt der Hoehe (kompakt / angedockt)
        bar:HookScript("OnSizeChanged", function(self) if self.art then local cw = ((self:GetHeight() or 38) + 8) * 1.09 self.art.l:SetWidth(cw) self.art.r:SetWidth(cw) end end)
    end

    -- Wortmarke (animiert): Klick = aufklappen
    local logoBtn = CreateFrame("Button", nil, bar)
    logoBtn:SetSize(76, 19)
    logoBtn:SetPoint("LEFT", 12, 0)
    local wm = ns.GuildLogo(logoBtn, 76, 19)
    wm:SetPoint("TOPLEFT")
    logoBtn:SetScript("OnClick", function() ns.Expand() end)
    logoBtn:SetScript("OnEnter", function(self) K.ShowTip(self, { "Oasis", L["Klick: aufklappen"], L["Ziehen: verschieben (oben am Rand rastet sie ein)"] }) end)
    logoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    logoBtn:RegisterForDrag("LeftButton")
    logoBtn:SetScript("OnDragStart", function() bar:GetScript("OnDragStart")(bar) end)
    logoBtn:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
    logoBtn.oasisDragFwd = true
    bar.name = logoBtn
    bar.wm = wm
    -- ohne Logo: kleines Plus zum Aufklappen
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
    -- 0.5.574: "4 online" anklickbar -> Mitgliederliste, nur Online
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
        K.ShowTip(self, L["Klick: wer gerade online ist"])
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
                if self.realColor then self.icon:SetVertexColor(1, 1, 1) else self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) end
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
                self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
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
    -- 0.5.954: "N neu" ist anklickbar - eine Seite mit Neuigkeiten: direkt dorthin; mehrere: Liste zum Auswaehlen
    bar.hintBtn = CreateFrame("Button", nil, bar)
    bar.hintBtn:SetPoint("TOPLEFT", bar.hint, "TOPLEFT", -4, 6)
    bar.hintBtn:SetPoint("BOTTOMRIGHT", bar.hint, "BOTTOMRIGHT", 4, -6)
    bar.hintBtn:SetFrameLevel(bar:GetFrameLevel() + 6)
    bar.hintBtn:Hide()
    local function news() local _, _, lines = ns.NotifyTotal() return lines or {} end
    bar.hintBtn:SetScript("OnEnter", function(self)
        bar.hint:SetTextColor(C.text[1], C.text[2], C.text[3])
        local tip = { L["Neuigkeiten"] }
        for i, l in ipairs(news()) do if i <= 8 then tip[#tip + 1] = l.text .. "  |cffffffff" .. l.n .. "|r" end end
        tip[#tip + 1] = "|cff888888" .. L["Klick: oeffnen"] .. "|r"
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
        K.ShowMenu(self, items, L["Neuigkeiten"])
    end)
    -- Kompakt-Stil (FuBar): Schriftzug statt Wortmarke, rechts Uhrzeit
    bar.label = K.Title(logoBtn, 12, C.accent)
    bar.label:SetPoint("LEFT", 0, 0)
    bar.label:SetText("OASIS")
    bar.label:Hide()
    bar.clock = K.Text(bar, 11, C.muted, "RIGHT")
    bar.clock:Hide()

    -- Status: eigene Gruppensuche, eigene Anfragen, Beitrittswuensche
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

    -- Hilfslinie in der Bildschirmmitte, solange die Leiste in der Naehe ist
    local guideF = CreateFrame("Frame", nil, UIParent)   -- eigene Ebene ganz oben, sonst liegen die Linien unter anderen Fenstern
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
    local MID = 70   -- so nah an der Mitte rastet sie ein
    bar:SetScript("OnDragStart", function(self)
        if ns.MiniCompact() then return end   -- Kompakt-Leiste sitzt fest oben
        self.docked = false
        applyDockLook()
        self:StartMoving()
        local ac = C.accent
        guide:SetColorTexture(ac[1], ac[2], ac[3], 0.6)
        guideH:SetColorTexture(ac[1], ac[2], ac[3], 0.6)
        self.dragging = true
    end)
    local drv = CreateFrame("Frame", nil, bar)   -- eigener Takt (bar setzt OnUpdate spaeter selbst)
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
        -- Einrasten in der Mitte: waagerecht (und frei schwebend auch senkrecht)
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
    -- Ziehen auch ueber den Knoepfen (sonst bleibt kaum freie Flaeche zum Anfassen)
    local function fwd(c)
        if c == bar.closeX or not c.RegisterForDrag or c.oasisDragFwd then return end
        c.oasisDragFwd = true
        c:RegisterForDrag("LeftButton")
        c:HookScript("OnDragStart", function() if not InCombatLockdown() then bar:GetScript("OnDragStart")(bar) end end)
        c:HookScript("OnDragStop", function() if bar.dragging then bar:GetScript("OnDragStop")(bar) end end)
    end
    bar.FwdDrag = function() for _, c in ipairs({ bar:GetChildren() }) do if c:IsObjectType("Button") and not c:IsProtected() then fwd(c) end end end
    C_Timer.After(1, bar.FwdDrag)

    -- Einrollen: Leiste rutscht bis auf einen schmalen Rand nach oben, beim Ueberfahren herunter
    bar.slide = 0          -- 0 = ganz zu sehen, 1 = eingerollt
    local slideDrv = CreateFrame("Frame", nil, UIParent)
    local away = 0
    slideDrv:SetScript("OnUpdate", function(_, el)
        if not bar:IsShown() then return end
        local auto = ns.MiniAutoHide and ns.MiniAutoHide()
        local want = 0
        if auto and not bar.dragging and not bar.preview then
            -- 0.6.260: mit Glut-Bild steckt die Leiste eingerollt ganz ueber dem Bildschirmrand - sichtbar ist nur das
            -- Bild darunter; die Maus dort muss sie auch ausrollen (Bereich nach unten um das Bild + Spielraum erweitern)
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

    -- Position wiederherstellen (Standard: oben mittig angedockt)
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

-- Inhalt und Breite der Leiste
-- Hintergrund-Transparenz der Topbar (Einstellungen > Topbar)
function ns.ApplyMiniAlpha()
    local b = ns._miniBar
    local a = ns.db and ns.db.settings.miniAlpha or 1
    if b and b.bgParts then for _, t in ipairs(b.bgParts) do t:SetAlpha(a) end
    elseif b and b.bgTex then b.bgTex:SetAlpha(a) end
    -- 0.6.261: auch das Glut-Bild (Gildenmodul) - sonst wirkte der Regler oben angeheftet gar nicht
    if b and b.art then for _, k in ipairs({ "l", "m", "r" }) do if b.art[k] then b.art[k]:SetAlpha(a) end end end
    if ns.TintMiniArt then pcall(ns.TintMiniArt) end   -- 0.6.263: auch beim Bauen/Einstellen einfaerben
end
-- 0.6.263: Glut-Bild der Leiste folgt der Akzentfarbe (wie Startfenster und Hintergruende): bei Rot das Original,
-- sonst entsaettigt und in der Akzentfarbe
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
-- gebuendelt (Performance 0.5.482): wird bei jedem Zaehler-Update, Gruppenwechsel und Abgleich-Datensatz
-- angestossen - jetzt hoechstens einmal je 0,1 s statt hunderte Male beim Login-Abgleich
local mbPending = false
local updateMiniBarNow
function ns.UpdateMiniBar()
    if mbPending then return end
    mbPending = true
    C_Timer.After(0.1, function()
        mbPending = false
        local ok, e = pcall(updateMiniBarNow)
        if not ok then ns.err("Topbar", e) end
    end)
end
function ns.UpdateMiniBarNow() return updateMiniBarNow() end
function updateMiniBarNow()
    if bar and bar.wm then
        local hide = ns.db and ns.db.settings.miniNoLogo
        bar.name:SetWidth(hide and 16 or 76)
        bar.wm:SetShown(not hide)
        bar.plus:SetShown(false)   -- 0.6.252: kein Plus mehr (Klick links klappt weiter auf)
    end
    if not bar then return end
    local compact = ns.MiniCompact()
    -- 0.5.560: weitere Stile - minimal (nur Symbole, schmal) und dock (grosse Symbole, wachsen beim Ueberfahren)
    local style = ns.MiniStyle and ns.MiniStyle() or "normal"
    local minimal, dock = style == "minimal", style == "dock"
    local slim = minimal or dock
    bar:SetScale(math.max(0.6, math.min(1.6, (ns.db and ns.db.settings.miniScale) or 1)))
    bar:SetHeight(compact and 24 or (minimal and 30) or (dock and 48) or 38)
    bar.wm:SetShown(not compact and not slim and not (ns.db and ns.db.settings.miniNoLogo))
    bar.plus:SetShown(false)   -- 0.6.252: kein Plus mehr
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
    -- ohne Logo schiebt sich alles zusammen (Leiste wird schmaler)
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
        -- Dock: Symbol waechst beim Ueberfahren
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
        -- leuchtet, solange Neues da ist, das noch nicht angesehen wurde (auch Unterseiten eines Hubs)
        if b.nglow then
            local on, ping = false, nil
            if vis and ns.GlowState then on, ping = ns.GlowState(b.key) end
            b.glowOn = on
            ns.SetGlow(b, on, ping)
        end
        if b.action then
            local sec = ns.Marker and ns.Marker.Secure and ns.Marker.Secure()
            if sec and not InCombatLockdown() then
                -- nicht an die Leiste anheften (sonst waere die Leiste im Kampf gesperrt): Bildschirm-Koordinaten
                local function place()
                    if InCombatLockdown() then return end
                    local l, bt = b:GetLeft(), b:GetBottom()
                    if not (l and bt and b:IsVisible()) then sec:Hide() return end
                    local r = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    -- 0.5.741: ganz nach vorn (gleiche Ebene wie die Leiste, aber hoeher als alle ihre Kinder) - sonst fing die Leiste den Klick ab
                    -- und es kam nur 'Auto-Marker neu ausgerichtet'
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
            if b.realColor then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) end
        end
    end
    total = ns.NotifyTotal and ns.NotifyTotal() or 0
    bar.hint:ClearAllPoints()
    bar.hint:SetPoint("LEFT", bar, "LEFT", x + 6, 0)
    bar.hint:SetText(total > 0 and (L["%d neu"]):format(total) or "")
    if bar.hintBtn then bar.hintBtn:SetShown(total > 0) end
    local w = x + 10 + (total > 0 and (bar.hint:GetStringWidth() + 8) or 0)

    -- Gruppenstatus
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
            st.text:SetText((L["Suche: %s"]):format(mine.title or "?") .. "  |cff888888" .. taken .. "/5|r")
            st.tip = { L["Deine Gruppensuche laeuft"], mine.title or "?", L["Klick: Gruppen oeffnen"] }
        else
            local g = asked[1]
            st.text:SetText((L["Angefragt: %s"]):format(g.title or "?") .. (#asked > 1 and ("  |cff888888+" .. (#asked - 1) .. "|r") or ""))
            local t = { L["Du wartest auf eine Einladung"] }
            for _, a in ipairs(asked) do t[#t + 1] = (a.title or "?") .. "  |cff888888" .. ns.displayName(a.who) .. "|r" end
            t[#t + 1] = L["Klick: Gruppen oeffnen"]
            st.tip = t
        end
        st.req:SetText(reqs > 0 and ((reqs == 1 and L["1 Anfrage"]) or (L["%d Anfragen"]):format(reqs)) or "")
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
    -- Kompakt: Uhrzeit rechts (vor dem X), Breite = ganzer Bildschirm (siehe PlaceMiniBar)
    bar.clock:SetShown(compact)
    if compact then
        bar.clock:ClearAllPoints()
        bar.clock:SetPoint("RIGHT", bar, "RIGHT", (bar.closeX and bar.closeX:IsShown()) and -34 or -10, 0)
        bar.clock:SetText(date("%H:%M"))
    end
    bar:SetWidth(math.max(200, w + 26))
    ns.PlaceMiniBar()
end

-- Stil / Einrollen (Einstellungen > Topbar)
function ns.MiniCompact() return ns.db and ns.db.settings.miniStyle == "compact" or false end
function ns.MiniStyle()
    local st = ns.db and ns.db.settings.miniStyle
    return (st == "compact" or st == "minimal" or st == "dock") and st or "normal"
end
function ns.MiniAutoHide()
    if not (ns.db and ns.db.settings.miniAutoHide) or not bar then return false end
    return ns.MiniCompact() or bar.docked == true
end
-- Leiste an ihren Platz setzen: Kompakt = ganze Breite oben; angedockt = oben an der gemerkten Stelle;
-- beim Einrollen um (Hoehe - 3) nach oben verschoben
function ns.PlaceMiniBar()
    if not bar or bar.dragging then return end
    local compact = ns.MiniCompact()
    local auto = ns.MiniAutoHide()
    -- 0.6.259: mit Glut-Bild (ragt 8 unter die Leiste) weiter hoch - nur die unterste rote Linie bleibt zu sehen
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
        -- Kompakt: alle Ecken eckig (durchgehende Leiste)
        if compact then for _, c in pairs(bar.corners) do c:SetTexture("Interface\\Buttons\\WHITE8X8") c:SetTexCoord(0, 1, 0, 1) end
            for _, a in pairs(bar.arcs or {}) do a:Hide() a.glow:Hide() end end
    end
end

-- Wann erscheint die Topbar? (Einstellungen > Topbar, Wunsch aus der Gilde 07.10.)
--   collapse = beim Schliessen klappt Oasis in die Leiste ein (bisheriges Verhalten)
--   always   = Leiste ist ab dem Einloggen immer da und verschwindet nie
--   off      = nie: das X schliesst Oasis einfach, keine Leiste
function ns.TopbarMode()
    local m = ns.db and ns.db.settings.topbarMode
    return (m == "always" or m == "off") and m or "collapse"
end

-- X an der Leiste: Oasis ganz schliessen (oeffnen per Minimap-Knopf oder /oasis) - nicht bei "immer"
local function addCloseX()
    do return end   -- 0.6.252: kein X mehr an der Leiste (schliessen ueber Einstellungen > Topbar bzw. /oasis)
    if not bar or bar.closeX then return end
    bar.closeX = ns.K.CloseButton(bar, function() ns.HideMiniBar() end, L["Ganz schliessen (/oasis oeffnet wieder)"])
    bar.closeX:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.closeX:SetFrameLevel(bar:GetFrameLevel() + 10)
end
-- Design/Akzent gewechselt: Topbar umfaerben (0.5.540 - vorher blieb sie bis /reload in den alten Farben)
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
-- Einstellung gewechselt: sofort umsetzen
function ns.ApplyTopbarMode()
    local m = ns.TopbarMode()
    if m == "always" then ns.ShowMiniBar()
    elseif m == "off" then ns.HideMiniBar(true)
    elseif bar and bar.closeX then bar.closeX:Show() end
end
-- Vorschau (Einstellungen > Topbar): echte Leiste an ihrem Platz zeigen, ohne einzuklappen
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

-- Fenster <-> Leiste: das Fenster zieht sich in die Topbar hinein (bzw. waechst aus ihr heraus).
-- Echte Bewegung statt Effekt: Mittelpunkt wandert zur Leiste, Groesse schrumpft, am Ende blendet es aus.
-- Positionen in UIParent-Einheiten; der Rahmen wird waehrenddessen ueber Mitte+Skalierung gesetzt.
local flyDrv
local function uiCenter(f)
    local x, y = f:GetCenter()
    if not x then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k
end
-- 0.5.645: Statt das echte Fenster jedes Bild zu skalieren (hunderte Elemente, Schriften, Masken -> Ruckeln)
-- fliegt ein leichter Geister-Rahmen (Flaeche + Rand). Das echte Fenster bleibt still und blendet nur weich ein/aus.
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
    -- ohne Animation: sofort Endzustand
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
        -- p: 0 = Fenster an seinem Platz, 1 = ganz in der Leiste
        local cx, cy = wx + (bx - wx) * p, wy + (by - wy) * p
        g:SetSize(ww + (tw - ww) * p, wh + (th - wh) * p)
        g:ClearAllPoints()
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        g:SetAlpha(math.min(1, (1 - p) * 1.4 + 0.15))
    end
    if toBar then
        -- echtes Fenster sofort weg (kostet nichts mehr), der Geist uebernimmt
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
        -- erstes Bild nach dem Aufbau (Seite bauen kann dauern) nicht als Sprung mitzaehlen
        t = t + math.min(el, 1 / 30)
        local q = math.min(1, t / dur)
        if toBar then
            place(q * q * q)                                   -- hinein: weich anfahren, schneller werden
        else
            local e = 1 - (1 - q) ^ 3                          -- heraus: schnell los, sanft auslaufen
            place(1 - e)
            -- letztes Drittel: echtes Fenster blendet ueber den Geist ein
            if q > 0.66 then mf:SetAlpha(a0 * (q - 0.66) / 0.34) end
        end
        if toBar and q > 0.6 then tgt:SetAlpha(barA * (0.75 + 0.25 * math.sin((q - 0.6) / 0.4 * math.pi))) end
        if q >= 1 then flyDrv.finish() end
    end)
end

-- Minimap-Knopf: Fenster fliegt in den Knopf hinein bzw. aus ihm heraus
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

-- Einklappen: Hauptfenster zu, Leiste auf
function ns.Collapse(force)
    local mf = ns.MainFrame and ns.MainFrame()
    -- Topbar "nie": einfach schliessen (ausser ausdruecklich /oa mini bzw. "Jetzt einklappen")
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
-- Aufklappen, optional direkt auf eine Seite
function ns.Expand(page)
    -- Topbar bleibt sichtbar (nur das X an der Leiste schliesst sie)
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

-- eingeklappten Zustand ueber /reload und Login behalten
ns.Listen("LOGIN", function()
    local m = ns.TopbarMode()
    if m == "off" then ns.db.settings.collapsed = false return end
    if m == "always" or ns.db.settings.collapsed then ns.After(3, ns.ShowMiniBar) end
end)
-- beim Ausloggen festhalten, ob die Leiste wirklich offen war (sonst ging sie beim naechsten Login verloren)
ns.On("PLAYER_LOGOUT", function()
    if bar and ns.db then
        if bar:IsShown() and not bar.preview then ns.db.settings.collapsed = true end
    end
end)

-- Gruppe betreten/verlassen: Marker-Knopf ein-/ausblenden
ns.On("GROUP_ROSTER_UPDATE", function() if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end end)

-- Oasis: Raid-Check - alles vor dem Pull auf einen Blick
--  * Bereitschaftscheck (Blizzard /readycheck) mit Ergebnis je Spieler (Ring "18/20 bereit", Ampeln je Kriterium)
--  * Kacheln: Bereit, Verzauberungen, Buffs, Abwesend/AFK, Haltbarkeit (Klick = Liste filtern)
--  * "Fehlende ansagen" schreibt eine kurze Liste in den Raidchat
--  * Boss-Taktiken (Store "tactics"): Leitung schreibt sie, alle sehen sie als Karte mit Rollen-Abschnitten
--    (Zeilen "Tank:", "Heiler:", "DD:" beginnen einen Abschnitt); beim Anvisieren des Bosses kommt ein Hinweis
--  * Gemeinsame Bausteine fuer Raid-Check, Pluender-Regeln und Raid-Vorbereitung: ns.RCUI
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Core\Diagnostics\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local RC = {}
ns.RaidCheck = RC
if ns.ICONS then ns.ICONS.raidcheck = ns.MEDIA .. "icons\\checklist" end

ns.GuildOption({ page = "raidcheck", key = "rcTactTip", default = true,
    label = "Tactic on target", desc = "When someone targets a boss that has a tactic, a short notice appears (out of combat)." })

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() or false end
local function simOn() return ns.Sim and ns.Sim.Active() or false end
local function glyph(name) return ns.MEDIA .. "icons\\" .. name end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

------------------------------------------------------------------------
-- Gemeinsame Bausteine (auch fuer LootRules.lua und RaidPrep.lua)
------------------------------------------------------------------------
local U = {}
ns.RCUI = U
if ns.ICONS then ns.ICONS.tactics = ns.MEDIA .. "icons\\raid" ns.ICONS.lootrules = ns.MEDIA .. "icons\\wants" end
-- Raid-Check, Boss-Taktiken und Pluender-Regeln teilen Daten: alle drei auffrischen
function ns.RCRefresh()
    ns.RefreshPage("raidcheck")
    ns.RefreshPage("tactics")
    ns.RefreshPage("lootrules")
end
U.CIRCLE, U.EMBER = CIRCLE, EMBER
U.animOn, U.demoOn = animOn, demoOn
U.SEV = { ok = C.mint, warn = C.amber, bad = C.red, wait = C.blue, none = C.dim }

-- Glas 2026: ruhige Flaeche + feine Kante (Kante optional farbig)
local GLINE = { 1, 1, 1, 0.10 }
function U.Glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or GLINE, r or 12) return true end
end
local glass = U.Glass
local function gl(c, a) return { c[1], c[2], c[3], a or 0.5 } end
function U.gradient(tex, dir, c, a1, a2, fallbackA)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fallbackA or (a1 + a2) / 2)
    end
end

-- Klassensymbol (Blizzard-Bogen), sonst Kreis in Klassenfarbe
function U.ClassIcon(tex, class)
    local tc = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then
        tex:SetTexture(CLASS_SHEET)
        tex:SetTexCoord(tc[1] + 0.012, tc[2] - 0.012, tc[3] + 0.012, tc[4] - 0.012)
        tex:SetVertexColor(1, 1, 1)
    else
        tex:SetTexture(CIRCLE)
        tex:SetTexCoord(0, 1, 0, 1)
        local cc = ns.classColor and class and ns.classColor(class)
        if type(cc) == "table" and cc.r then tex:SetVertexColor(cc.r, cc.g, cc.b)
        elseif type(cc) == "table" and cc[1] then tex:SetVertexColor(cc[1], cc[2], cc[3])
        else tex:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) end
    end
end

-- weich einblenden (ohne Flackern: laeuft nur beim Wechsel, nicht bei jedem Auffrischen)
function U.Reveal(f, dist)
    if not f then return end
    if not animOn() then f:SetAlpha(1) return end
    f:SetAlpha(0)
    K.Tween(f, 0.22, function(q) f:SetAlpha(q) end, function() f:SetAlpha(1) end)
    ns.After(0.8, function() if (f:GetAlpha() or 1) < 1 then f:SetAlpha(1) end end)
end

-- Reiterleiste: Symbol + Text, gleitender Balken in der Farbe des Reiters
function U.Tabs(parent, items, onPick)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(32)
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT") f.base:SetPoint("BOTTOMRIGHT")
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.buttons = {}
    local x = 0
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.key = it.key
        b.color = it.color or C.accent
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        b.hov:SetColorTexture(1, 1, 1, 0.03)
        b.hov:SetAlpha(0)
        b.ico = K.Glyph(b, 14, glyph(it.icon or "checklist"), C.muted)
        b.ico:SetPoint("LEFT", 12, 0)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetPoint("LEFT", b.ico, "RIGHT", 7, 0)
        b.label:SetText(it.text)
        b.badge = K.Text(b, 10, C.dim)
        b.badge:SetPoint("LEFT", b.label, "RIGHT", 5, 0)
        local bw = math.floor(12 + 14 + 7 + (b.label:GetStringWidth() or 40) + 26)
        b:SetSize(bw, 31)
        b:SetPoint("TOPLEFT", x, 0)
        b.x, b.w = x, bw
        x = x + bw + 2
        b:SetScript("OnClick", function() if f.value ~= it.key then f:Select(it.key, true) onPick(it.key) end end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
            if it.tip then K.ShowTip(self, it.tip) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(0)
            if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
            GameTooltip:Hide()
        end)
        f.buttons[i] = b
    end
    f.natW = x
    f.ind = f:CreateTexture(nil, "OVERLAY")
    f.ind:SetHeight(2)
    f.indGlow = f:CreateTexture(nil, "ARTWORK")
    f.indGlow:SetHeight(12)
    f.indGlow:SetPoint("BOTTOMLEFT", f.ind, "TOPLEFT")
    f.indGlow:SetPoint("BOTTOMRIGHT", f.ind, "TOPRIGHT")
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb then return end
        local c = tb.color
        self.ind:SetColorTexture(c[1], c[2], c[3], 1)
        self.indGlow:Hide()
        local x1, w1 = tb.x + 8, math.max(1, tb.w - 16)
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(px, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", px, 0)
            self.ind:SetWidth(math.max(1, w))
        end
        if not animate or not animOn() then put(x1, w1) return end
        K.Tween(self.ind, 0.24, function(q)
            local e = 1 - (1 - q) * (1 - q)
            put(x0 + (x1 - x0) * e, w0 + (w1 - w0) * e)
        end, function() put(x1, w1) end)
    end
    function f:Select(key, animate)
        local changed = self.value ~= key
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and b.color or C.muted
            b.ico:SetVertexColor(ic[1], ic[2], ic[3])
            b.hov:SetAlpha(0)
        end
        if changed or not self.indX then self:MoveInd(key, animate) end
    end
    function f:SetBadge(key, text)
        for _, b in ipairs(self.buttons) do if b.key == key then b.badge:SetText(text or "") end end
    end
    return f
end

-- Kachel mit Verlauf, Glow und Hover-Lift; Klick optional (z.B. Filter)
function U.Tile(parent, icon, label, color, onClick)
    local c = color or C.accent
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(60)
    t.lift, t.color = 0, c
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetColorTexture(1, 1, 1, 0)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:Hide()
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:Hide()
    glass(t, 12)
    t.icon = K.Glyph(t, 16, glyph(icon), c)
    t.icon:SetPoint("TOPRIGHT", -12, -11)
    t.icon:SetAlpha(0.8)
    t.value = K.Title(t, 20, C.text)
    t.value:SetPoint("TOPLEFT", 14, -9)
    t.sub = K.Text(t, 10, c)
    t.sub:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 5, 2)
    t.sub:SetPoint("RIGHT", t.icon, "LEFT", -2, 0)
    t.label = K.Text(t, 11, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 14, 9)
    t.label:SetPoint("RIGHT", t, "RIGHT", -6, 0)
    t.label:SetText(label or "")
    t.bar = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.bar:SetPoint("BOTTOMLEFT", 10, 1)
    t.bar:SetHeight(2)
    t.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
    t.bar:Hide()
    function t:Place()
        if not self.bx then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", self.bx, self.by + self.lift)
        self:SetWidth(self.bw)
    end
    function t:SetPos(x, y, w) self.bx, self.by, self.bw = x, y, math.max(20, w) self:Place() end
    local function hover(on)
        glass(t, 12, (on or t.sel) and 0.06 or 0.03, t.sel and gl(c, 0.55) or GLINE)
        local from, to = t.lift, on and 2 or 0
        if animOn() then
            K.Tween(t.hov, 0.16, function(q)
                t.lift = from + (to - from) * q
                t:Place()
            end)
        else
            t.lift = to
            t:Place()
        end
    end
    t:SetScript("OnEnter", function(self) hover(true) if self.tip then K.ShowTip(self, self.tip) end end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    if onClick then t:SetScript("OnClick", function(self) onClick(self) end) end
    function t:SetSel(on)
        self.sel = on and true or false
        glass(self, 12, on and 0.06 or 0.03, on and gl(c, 0.55) or GLINE)
    end
    -- Wert setzen; zaehlt nur hoch, wenn er sich geaendert hat (kein Flackern beim Auffrischen)
    function t:Set(value, sub, progress, vcolor)
        self.sub:SetText(sub or "")
        local key = tostring(value)
        if self.lastV ~= key then
            local n = tonumber(value)
            if n and animOn() and self.lastV ~= nil then K.CountUp(self.value, n, 0.5) else self.value:SetText(value == nil and "-" or tostring(value)) end
            self.lastV = key
        end
        local vc = vcolor or C.text
        self.value:SetTextColor(vc[1], vc[2], vc[3])
        if progress then
            self.bar:Show()
            self.bar:SetWidth(math.max(1, ((self.bw or self:GetWidth() or 100) - 20) * math.max(0, math.min(1, progress))))
        else
            self.bar:Hide()
        end
    end
    return t
end
-- Kacheln gleichmaessig in einer Reihe verteilen
function U.LayoutTiles(tiles, x0, y, w, gap)
    gap = gap or 8
    local n = #tiles
    local tw = math.floor((w - (n - 1) * gap) / n)
    for i, t in ipairs(tiles) do t:SetPos(x0 + (i - 1) * (tw + gap), y, tw) end
end

-- Leerzustand: Symbol mit Halo, Text, bis zu zwei Knoepfe
function U.Empty(parent, icon, color)
    color = color or C.accent
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(340, 130)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(96, 96)
    f.halo:SetPoint("TOP", 0, 20)
    f.halo:SetVertexColor(color[1], color[2], color[3])
    f.halo:SetAlpha(0)
    f.halo:Hide()
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(46, 46)
    f.disc:SetPoint("TOP", 0, -5)
    f.disc:SetVertexColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18)
    f.icon = K.Glyph(f, 22, glyph(icon or "checklist"), color)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 13, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(320)
    f.text:SetWordWrap(true)
    f.btn = K.Button(f, "", 150, 24, "ghost")
    f.btn2 = K.Button(f, "", 110, 24, "ghost")
    function f:Set(msg, b1, fn1, b2, fn2)
        self.text:SetText(msg or "")
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetWidth(math.max(120, (self.btn.label:GetStringWidth() or 0) + 28))
            self.btn:SetScript("OnClick", fn1)
        end
        if b2 then
            self.btn2:SetLabel(b2)
            self.btn2:SetWidth(math.max(100, (self.btn2.label:GetStringWidth() or 0) + 28))
            self.btn2:SetScript("OnClick", fn2)
            self.btn:SetPoint("TOPRIGHT", self.text, "BOTTOM", -4, -12)
            self.btn2:ClearAllPoints()
            self.btn2:SetPoint("TOPLEFT", self.text, "BOTTOM", 4, -12)
        else
            self.btn:SetPoint("TOP", self.text, "BOTTOM", 0, -12)
        end
    end
    f:Hide()
    return f
end

-- Ampel: farbiger Punkt mit Schein; Ueberfahren/Klick = Details
function U.Light(parent, size)
    size = size or 12
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size + 10, size + 10)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(EMBER)
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(size * 2.6, size * 2.6)
    b.glow:SetPoint("CENTER")
    b.glow:SetAlpha(0)
    b.ring = b:CreateTexture(nil, "BORDER")
    b.ring:SetTexture(CIRCLE)
    b.ring:SetSize(size + 4, size + 4)
    b.ring:SetPoint("CENTER")
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetTexture(CIRCLE)
    b.dot:SetSize(size, size)
    b.dot:SetPoint("CENTER")
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetTexture(CIRCLE)
    b.shine:SetSize(size * 0.4, size * 0.4)
    b.shine:SetPoint("CENTER", -size * 0.18, size * 0.18)
    b.shine:SetVertexColor(1, 1, 1, 0.35)
    function b:SetState(sev, tip)
        self.sev, self.tip = sev, tip
        local c = U.SEV[sev] or C.dim
        local dim = sev == "none"
        self.dot:SetVertexColor(c[1], c[2], c[3], dim and 0.35 or 1)
        self.ring:SetVertexColor(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 1)
        self.shine:SetShown(not dim)
        self.glow:SetVertexColor(c[1], c[2], c[3])
        if not self.pulsing then self.glow:SetAlpha(0) end
    end
    function b:Pulse()
        if not animOn() then return end
        self.pulsing = true
        local s = size
        K.Tween(self.dot, 0.6, function(q)
            local k = 1 + 0.6 * math.sin(q * math.pi)
            self.dot:SetSize(s * k, s * k)
            self.glow:SetAlpha(0.35 * math.sin(q * math.pi))
        end, function()
            self.pulsing = nil
            self.dot:SetSize(s, s)
            self:SetState(self.sev, self.tip)
        end)
    end
    local function tip(self) if self.tip then K.ShowTip(self, self.tip) end end
    b:SetScript("OnEnter", tip)
    b:SetScript("OnClick", tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Fortschrittsring aus Punkten (zaehlt animiert hoch)
function U.Ring(parent, size, n)
    n = n or 40
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(size * 1.45, size * 1.45)
    f.halo:SetPoint("CENTER")
    f.halo:SetAlpha(0)
    f.halo:Hide()
    f.core = f:CreateTexture(nil, "BORDER")
    f.core:SetTexture(CIRCLE)
    f.core:SetSize(size - 22, size - 22)
    f.core:SetPoint("CENTER")
    f.core:SetVertexColor(0, 0, 0, 0.35)
    f.dots = {}
    local rad = size / 2 - 5
    for i = 1, n do
        local a = math.pi / 2 - (i - 1) / n * 2 * math.pi
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetTexture(CIRCLE)
        d:SetSize(6, 6)
        d:SetPoint("CENTER", f, "CENTER", math.cos(a) * rad, math.sin(a) * rad)
        f.dots[i] = d
    end
    f.value = K.Title(f, 22, C.text)
    K.CenterNum(f.value, f, "CENTER", 0, 6)
    f.label = K.Text(f, 10, C.muted, "CENTER")
    f.label:SetPoint("TOP", f, "CENTER", 0, -10)
    local function paint(k, c)
        for i, d in ipairs(f.dots) do
            if i <= k then d:SetVertexColor(c[1], c[2], c[3], 1)
            else d:SetVertexColor(1, 1, 1, 0.10) end
        end
    end
    function f:Set(done, total, c, text, label)
        c = c or C.mint
        local k = (total or 0) > 0 and math.floor(n * math.min(1, (done or 0) / total) + 0.5) or 0
        self.value:SetText(text or "")
        self.label:SetText(label or "")
        self.halo:SetVertexColor(c[1], c[2], c[3])
        local key = k .. ":" .. c[1] .. c[2] .. c[3]
        if self.key == key then return end
        local from = self.shown or 0
        self.key = key
        if not animOn() or from == k then paint(k, c) self.shown = k return end
        K.Tween(self, 0.6, function(q)
            local e = 1 - (1 - q) * (1 - q)
            local cur = math.floor(from + (k - from) * e + 0.5)
            paint(cur, c)
            self.shown = cur
        end, function() paint(k, c) self.shown = k end)
    end
    return f
end

-- Karte (Flaeche mit Rahmen und farbiger Kante links)
function U.Card(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    f.grad = f:CreateTexture(nil, "BORDER", nil, 1)
    f.grad:Hide()
    f.edge = f:CreateTexture(nil, "ARTWORK")
    f.edge:Hide()
    glass(f, 14, 0.03)
    -- Farbe nur als feine Kante (z.B. alle bereit = gruen)
    function f:SetColor(nc)
        glass(self, 14, 0.03, (nc and nc ~= C.accent) and gl(nc, 0.35) or GLINE)
    end
    return f
end

-- Bereich mit eigenem Inhalt, Mausrad scrollt (fuer Karten mit variabler Hoehe)
function U.Scroll(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetClipsChildren(true)
    f:EnableMouseWheel(true)
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT")
    f.content:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.content:SetHeight(10)
    f.off, f.ch = 0, 10
    f.thumb = f:CreateTexture(nil, "OVERLAY")
    f.thumb:SetWidth(3)
    f.thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    function f:Apply()
        local h = self:GetHeight() or 100
        local maxOff = math.max(0, self.ch - h)
        self.off = math.max(0, math.min(self.off, maxOff))
        self.content:ClearAllPoints()
        self.content:SetPoint("TOPLEFT", 0, self.off)
        self.content:SetPoint("RIGHT", self, "RIGHT", -6, 0)
        if maxOff > 0 then
            local th = math.max(20, h * h / self.ch)
            self.thumb:SetHeight(th)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", 0, -((h - th) * self.off / maxOff))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end
    function f:SetContentHeight(h) self.ch = math.max(10, h or 10) self.content:SetHeight(self.ch) self:Apply() end
    function f:Top() self.off = 0 self:Apply() end
    f:SetScript("OnMouseWheel", function(self, d) self.off = self.off - d * 30 self:Apply() end)
    f:SetScript("OnSizeChanged", function(self) self:Apply() end)
    return f
end

------------------------------------------------------------------------
-- Bereitschaftscheck
------------------------------------------------------------------------
RC.ready = {}      -- Name -> true/false/"wait"/"afk"
RC.readyAt = nil
RC.flash = {}      -- Name -> GetTime() der letzten Antwort (Ampel pulsiert)
local function units()
    local out = {}
    if ns.Group.IsInRaid() then for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else out[1] = "player" for i = 1, 4 do out[#out + 1] = "party" .. i end end
    return out
end
local function unitName(u) local n = ns.safe(ns.UnitName(u)) return n and ns.fullName(n) end
ns.On("READY_CHECK", function(starter, timeout)
    RC.ready, RC.readyAt, RC.readyDone = {}, ns.now(), false
    RC.readyStart = GetTime()
    RC.readyEnd = RC.readyStart + (tonumber(ns.safe(timeout)) or 35)
    for _, u in ipairs(units()) do local n = UnitExists(u) and unitName(u) if n then RC.ready[n] = "wait" end end
    local s = ns.safe(starter)
    if s then RC.ready[ns.fullName(s)] = true RC.flash[ns.fullName(s)] = GetTime() end
    ns.RCRefresh()
end)
ns.On("READY_CHECK_CONFIRM", function(unit, isReady)
    local n = unit and unitName(unit)
    if n then
        RC.ready[n] = ns.safe(isReady) and true or false
        RC.flash[n] = GetTime()
    end
    ns.RCRefresh()
end)
ns.On("READY_CHECK_FINISHED", function()
    for n, v in pairs(RC.ready) do if v == "wait" then RC.ready[n] = "afk" RC.flash[n] = GetTime() end end
    RC.readyDone, RC.readyEnd = true, nil
    ns.RCRefresh()
end)

------------------------------------------------------------------------
-- Daten je Spieler
------------------------------------------------------------------------
-- eigene Haltbarkeit (niedrigstes Teil in %)
local function myDurability()
    if not GetInventoryItemDurability then return nil end
    local low
    for slot = 1, 18 do
        local ok, cur, mx = pcall(GetInventoryItemDurability, slot)
        if ok then
            cur, mx = ns.safe(cur), ns.safe(mx)
            if type(cur) == "number" and type(mx) == "number" and mx > 0 then
                local p = cur / mx
                if not low or p < low then low = p end
            end
        end
    end
    return low and math.floor(low * 100 + 0.5) or nil
end
-- Haltbarkeit anderer aus dem geteilten Stand der Raid-Vorbereitung (hoechstens 2 Tage alt)
local function sharedDurability(n)
    if not (Store and Store.Get) then return nil end
    local ok, r = pcall(Store.Get, "raidprep", "rp@" .. n)
    if not ok or type(r) ~= "table" or (r.demo and not demoOn()) then return nil end
    if ns.now() - (tonumber(r.ts or r.u) or 0) > 2 * 86400 then return nil end
    local d = tonumber(r.dura)
    return d and d >= 0 and d or nil
end

-- Beispielgruppe (Demo): Name, Klasse, Rolle, bereit, fehlende Verzauberungen, fehlende Buffs, Haltbarkeit, Zustand
local DEMO = {
    { "Grukthar", "WARRIOR", "TANK", true, {}, {}, 94 },
    { "Drogbar", "WARRIOR", "TANK", true, { "Cloak" }, {}, 61 },
    { "Tavira", "PRIEST", "HEALER", true, {}, {}, 88 },
    { "Nakira", "DRUID", "HEALER", true, {}, { "Seelenstaerke" }, 100 },
    { "Wolkenruf", "SHAMAN", "HEALER", "wait", {}, {}, 77 },
    { "Heilfix", "PRIEST", "HEALER", true, {}, {}, 92 },
    { "Hoknar", "ROGUE", "DAMAGER", true, { "Weapon" }, {}, 64 },
    { "Zul'mira", "MAGE", "DAMAGER", false, {}, { "Food" }, 18 },
    { "Mokrash", "HUNTER", "DAMAGER", true, {}, {}, 83 },
    { "Yenzi", "WARLOCK", "DAMAGER", true, {}, { "Flasks" }, 71 },
    { "Funkenbart", "MAGE", "DAMAGER", true, {}, {}, 99 },
    { "Brumm", "WARRIOR", "DAMAGER", true, { "Chest", "Boots" }, {}, 55 },
    { "Krallix", "DRUID", "DAMAGER", true, {}, {}, 90 },
    { "Donnerhuf", "SHAMAN", "DAMAGER", "afk", {}, { "Food" }, 80, "far" },
    { "Schattenzahn", "ROGUE", "DAMAGER", true, {}, {}, 86 },
    { "Gorlak", "HUNTER", "DAMAGER", true, {}, {}, 74 },
    { "Rasselbein", "WARLOCK", "DAMAGER", true, {}, {}, 97 },
    { "Ishkra", "MAGE", "DAMAGER", true, {}, {}, 91 },
    { "Ugruk", "WARRIOR", "DAMAGER", true, {}, {}, 68 },
    { "Tikka", "PRIEST", "DAMAGER", true, {}, {}, 85, "dead" },
}
RC.demoReady = nil   -- simulierter Ready-Check in der Demo
local function demoRows()
    local rows = {}
    for i, d in ipairs(DEMO) do
        local n = ns.fullName(d[1])
        local rd = d[4]
        if RC.demoReady then rd = RC.demoReady[n] end
        rows[#rows + 1] = {
            name = n, class = d[2], role = d[3], level = 60, ready = rd, ench = d[5], buffs = d[6], dura = d[7],
            far = d[8] == "far", dead = d[8] == "dead", off = false, zone = d[8] == "far" and L["Orgrimmar"] or nil, demo = true,
        }
    end
    return rows
end
-- Raid-Simulator: Zeilen aus ns.Group, Ready-Check mit nach und nach eintreffenden Antworten
local function simRows()
    local buffMiss = {}
    if ns.BuffMonitor and ns.BuffMonitor.Scan then
        local ok, list, cols = pcall(ns.BuffMonitor.Scan)
        if ok and list then
            for _, r in ipairs(list) do
                local miss = {}
                for _, b in ipairs(cols or {}) do if r.has and not r.has[b.key] and not b.soft then miss[#miss + 1] = L[b.short or b.key] end end
                buffMiss[r.name] = miss
            end
        end
    end
    local rows = {}
    for _, m in ipairs(ns.Group.Members()) do
        rows[#rows + 1] = {
            name = m.name, class = m.class, role = m.role, level = m.level or 60, ready = RC.demoReady and RC.demoReady[m.name] or nil,
            ench = m.ench or {}, buffs = (m.online and buffMiss[m.name]) or {}, dura = m.dura, dead = m.dead and true or false,
            off = not m.online, far = m.far and true or false, zone = m.zone, sim = true,
        }
    end
    local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(rows, function(a, b)
        local oa, ob = order[a.role or ""] or 4, order[b.role or ""] or 4
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return rows
end
local function simReadyCheck()
    local list = ns.Group.Members()
    RC.demoReady = {}
    RC.readyAt, RC.readyDone = ns.now(), false
    RC.readyStart = GetTime()
    RC.readyEnd = RC.readyStart + 10
    for _, m in ipairs(list) do RC.demoReady[m.name] = m.isMe and true or "wait" end
    local step = 8 / math.max(1, #list)
    for i, m in ipairs(list) do
        if not m.isMe then
            local ans = ns.Sim.ReadyAnswer(m)
            if ans ~= "afk" then
                ns.After(0.3 + i * step + math.random() * 0.4, function()
                    if not RC.demoReady or not simOn() then return end
                    RC.demoReady[m.name] = ans
                    RC.flash[m.name] = GetTime()
                    ns.RCRefresh()
                end)
            end
        end
    end
    ns.After(10, function()
        if not RC.demoReady then return end
        for n, v in pairs(RC.demoReady) do if v == "wait" then RC.demoReady[n] = "afk" RC.flash[n] = GetTime() end end
        RC.readyDone, RC.readyEnd = true, nil
        ns.RCRefresh()
    end)
    ns.print(L["Raid sim: ready check started."])
    ns.RCRefresh()
end
function RC.DemoReadyCheck()
    if simOn() then return simReadyCheck() end
    RC.demoReady = {}
    RC.readyAt, RC.readyDone = ns.now(), false
    RC.readyStart = GetTime()
    RC.readyEnd = RC.readyStart + 9
    for _, d in ipairs(DEMO) do RC.demoReady[ns.fullName(d[1])] = "wait" end
    for i, d in ipairs(DEMO) do
        ns.After(0.25 + i * 0.32 + math.random() * 0.3, function()
            if not RC.demoReady then return end
            local n = ns.fullName(d[1])
            RC.demoReady[n] = d[4] == "wait" and "afk" or d[4]
            RC.flash[n] = GetTime()
            ns.RCRefresh()
        end)
    end
    ns.After(9, function() RC.readyDone, RC.readyEnd = true, nil ns.RCRefresh() end)
    ns.RCRefresh()
end

function RC.Rows()
    if simOn() then return simRows() end
    if not ns.Group.IsInGroup() then return demoOn() and demoRows() or {} end
    local rows = {}
    local buffMiss, buffOk = {}, false
    if ns.BuffMonitor and ns.BuffMonitor.Scan then
        local ok, list, cols = pcall(ns.BuffMonitor.Scan)
        if ok and list then
            buffOk = true
            for _, r in ipairs(list) do
                local miss = {}
                for _, b in ipairs(cols or {}) do if r.has and not r.has[b.key] then miss[#miss + 1] = L[b.short or b.key] end end
                buffMiss[ns.fullName(r.name)] = miss
            end
        end
    end
    for _, u in ipairs(units()) do
        if UnitExists(u) then
            local n = unitName(u)
            if n then
                local _, cls = UnitClass(u)
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
                if (not role or role == "NONE") and ns.db.members[n] and ns.db.members[n].role then role = ns.db.members[n].role end
                local missE
                if ns.Officer and ns.Officer.MissingEnchants then
                    local ok, m = pcall(ns.Officer.MissingEnchants, n)
                    if ok then missE = m end
                end
                local inRange = UnitInRange and select(1, UnitInRange(u))
                local dura
                if u == "player" or ns.isMe(n) then dura = myDurability() else dura = sharedDurability(n) end
                rows[#rows + 1] = {
                    unit = u, name = n, class = cls, level = ns.safe(UnitLevel(u)) or 0, role = role,
                    dead = ns.safe(UnitIsDeadOrGhost(u)) and true or false, off = not ns.safe(UnitIsConnected(u)),
                    far = (u ~= "player") and ns.safe(inRange) == false,
                    ready = RC.ready[n], ench = missE, buffs = buffMiss[n] or (buffOk and {} or nil), dura = dura,
                    zone = (u ~= "player" and not ns.safe(UnitIsVisible(u))) and (ns.Radar and ns.Radar.byName[n] and ns.Radar.byName[n].zone) or nil,
                }
            end
        end
    end
    local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(rows, function(a, b)
        local oa, ob = order[a.role or ""] or 4, order[b.role or ""] or 4
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return rows
end
local function problems(r)
    local p = {}
    if r.off then p[#p + 1] = L["offline"] end
    if r.dead then p[#p + 1] = L["dead"] end
    if r.far then p[#p + 1] = L["far away"] end
    if r.ready == false then p[#p + 1] = L["not ready"] elseif r.ready == "afk" then p[#p + 1] = L["no answer"] end
    if r.ench and #r.ench > 0 then p[#p + 1] = L["Enchant"] .. ": " .. table.concat(r.ench, ", ") end
    if r.buffs and #r.buffs > 0 then p[#p + 1] = L["Buffs"] .. ": " .. table.concat(r.buffs, ", ") end
    if r.dura and r.dura < 30 then p[#p + 1] = (L["Durability %d%%"]):format(r.dura) end
    return p
end
RC.Problems = problems
function RC.Report()
    local ch = ns.groupChannel()
    local lines = {}
    for _, r in ipairs(RC.Rows()) do
        local p = problems(r)
        if #p > 0 then lines[#lines + 1] = ns.short(r.name) .. ": " .. table.concat(p, ", ") end
    end
    if not ch then
        -- allein/Demo: nur lokal zeigen, nichts senden
        ns.print(#lines == 0 and L["[Oasis] Raid check: all ready!"] or L["[Oasis] Raid check - open:"])
        for i, l in ipairs(lines) do if i <= 8 then ns.print("  " .. l) end end
        if not demoOn() then ns.print(L["You are not in a group."]) end
        return
    end
    if #lines == 0 then ns.SendChat(L["[Oasis] Raid check: all ready!"], ch) return end
    -- 0.5.617: ohne Namen (niemand wird oeffentlich vorgefuehrt) - Namen nur mit Einstellung rcChatNames
    if not ns.db.settings.rcChatNames then
        ns.SendChat((L["[Oasis] Raid check: %d players still have something open - please check (buffs, ready, durability)."]):format(#lines), ch)
        return
    end
    ns.SendChat(L["[Oasis] Raid check - open:"], ch)
    for i, l in ipairs(lines) do
        if i > 8 then ns.SendChat((L["... and %d more"]):format(#lines - 8), ch) break end
        ns.SendChat(l:sub(1, 250), ch)
    end
end

-- Kriterien je Spieler -> Ampel ("ok"/"warn"/"bad"/"wait"/"none") + Tooltip-Zeilen
local CRIT = {
    { key = "ready", label = "Ready", icon = "checklist" },
    { key = "ench", label = "Enchants", icon = "crafting" },
    { key = "buffs", label = "Buffs", icon = "heart" },
    { key = "here", label = "Here", icon = "radar" },
    { key = "dura", label = "Durab.", icon = "settings" },
}
local OKH, WARNH, BADH, DIMH = "|cff66db9e", "|cfffac257", "|cffe64047", "|cff888888"
local function crit(r, key)
    local who = ns.displayName(r.name)
    if key == "ready" then
        local v = r.ready
        if v == true then return "ok", { who, OKH .. L["clicked Ready"] .. "|r" } end
        if v == false then return "bad", { who, BADH .. L["clicked Not ready"] .. "|r" } end
        if v == "afk" then return "bad", { who, BADH .. L["no answer to the ready check (AFK?)"] .. "|r" } end
        if v == "wait" then return "wait", { who, DIMH .. L["waiting for answer ..."] .. "|r" } end
        return "none", { who, DIMH .. L["No ready check yet."] .. "|r" }
    elseif key == "ench" then
        if r.ench == nil then return "none", { who, DIMH .. L["Unknown - no Oasis or profile not shared yet."] .. "|r" } end
        if #r.ench > 0 then
            local t = { who, WARNH .. L["Enchant missing:"] .. "|r" }
            for _, e in ipairs(r.ench) do t[#t + 1] = "  " .. e end
            return #r.ench >= 2 and "bad" or "warn", t
        end
        return "ok", { who, OKH .. L["All enchants present."] .. "|r" }
    elseif key == "buffs" then
        if r.buffs == nil then return "none", { who, DIMH .. L["Buff monitor not available."] .. "|r" } end
        if #r.buffs > 0 then
            local t = { who, WARNH .. L["Buffs missing:"] .. "|r" }
            for _, e in ipairs(r.buffs) do t[#t + 1] = "  " .. e end
            return "warn", t
        end
        return "ok", { who, OKH .. L["All buffs present."] .. "|r" }
    elseif key == "here" then
        if r.off then return "bad", { who, BADH .. L["offline"] .. "|r" } end
        if r.dead then return "bad", { who, BADH .. L["dead"] .. "|r" } end
        if r.ready == "afk" then return "warn", { who, WARNH .. L["not responding (AFK?)"] .. "|r" } end
        if r.far then return "warn", { who, WARNH .. L["far away"] .. (r.zone and (": " .. r.zone) or "") .. "|r" } end
        return "ok", { who, OKH .. L["nearby"] .. "|r" }
    elseif key == "dura" then
        local d = r.dura
        if not d then return "none", { who, DIMH .. L["Durability unknown (no raid preparation status)."] .. "|r" } end
        if d < 30 then return "bad", { who, BADH .. (L["Durability %d%%"]):format(d) .. " - " .. L["repair!"] .. "|r" } end
        if d < 70 then return "warn", { who, WARNH .. (L["Durability %d%%"]):format(d) .. "|r" } end
        return "ok", { who, OKH .. (L["Durability %d%%"]):format(d) .. "|r" }
    end
    return "none", nil
end
RC.Crit = crit
-- Kachel-Filter
local FILTER = {
    ready = function(r) return r.ready ~= true end,
    ench = function(r) return r.ench ~= nil and #r.ench > 0 end,
    buffs = function(r) return r.buffs ~= nil and #r.buffs > 0 end,
    away = function(r) return r.off or r.dead or r.far or r.ready == "afk" end,
    dura = function(r) return r.dura ~= nil and r.dura < 70 end,
}

------------------------------------------------------------------------
-- Boss-Taktiken
------------------------------------------------------------------------
local function tkey(boss) return "tac-" .. (boss or ""):lower():gsub("[^%w]", "") end
-- Beispiel-Taktiken (Demo, nur Anzeige - Speichern legt eine echte an)
local DEMO_TAC = {
    { boss = "Onyxia", inst = "Onyxias Hort", text = "All: Never stand in front of or behind Onyxia (breath/tail).\nPhase 2 from 65%: dodge fireballs, kill whelps at once.\nPhase 3 from 40%: fear - grounding totem and fear ward ready.\nTank: Onyxia with her back to the wall, head away from the raid.\nTank: phase 3 take aggro back at once.\nHealer: tank first, spread out in phase 2.\nDPS: go full only after 3 sunders from the tank.\nDPS: phase 2: whelps before Onyxia." },
    { boss = "Rage Winterchill", inst = "Hyjal", text = "All: leave Death and Decay at once.\nTank: hold the middle, don't move during frost nova.\nHealer: heal the ice block target fast.\nDPS: ranged spread wide (icebolt chain)." },
    { boss = "Anetheron", inst = "Hyjal", text = "All: swarm target: run out.\nTank: infernal tank off to the side.\nHealer: remove sleep where possible.\nDPS: ignore infernals, everything on the boss." },
}
-- Taktik-Bibliothek: fertige Kurz-Taktiken der Classic-Raids. Jeder sieht sie (nur lesen),
-- die Raidleitung uebernimmt sie mit einem Klick als Gilden-Taktik und passt sie an.
local LIB = {
    { inst = "Onyxias Hort", boss = "Onyxia", text = "All: Never stand in front of or behind Onyxia (breath and tail sweep).\nAll: Phase 2 (65%): dodge fireballs, stay out of the cave entrances.\nAll: Phase 3 (40%): fear - Fear Ward/Tremor Totem ready, avoid the lava cracks.\nTank: Onyxia sideways at the wall, head away from the raid.\nTank: Phase 2: pick up the whelps. Phase 3: get aggro back at once.\nHealer: Tank has priority, spread out in phase 2.\nDD: Wait for 3 attacks of the tank. Phase 2: whelps first." },
    { inst = "Geschmolzener Kern", boss = "Lucifron", text = "All: Remove Lucifron's Curse and Impending Doom at once (mages/druids, priests/paladins).\nTank: Tank the two guards apart - mind control!\nHealer: Spread out, dispel mind-controlled players.\nDD: Guards first, then Lucifron." },
    { inst = "Geschmolzener Kern", boss = "Magmadar", text = "All: Panic - Fear Ward/Tremor Totem, hunters: Tranquilizing Shot on Frenzy.\nAll: Get out of the lava fire on the ground.\nTank: Magmadar with his back to the raid.\nDD: Ranged spread out at the back." },
    { inst = "Geschmolzener Kern", boss = "Gehennas", text = "All: Remove Gehennas' Curse (reduced healing) at once.\nAll: Get out of the Rain of Fire.\nTank: Tank the two Flamewakers apart.\nDD: Flamewakers first, then Gehennas." },
    { inst = "Geschmolzener Kern", boss = "Garr", text = "All: Do not let the 8 Firesworn die near the raid (explosion).\nTank: Each add tank pulls their Firesworn away, warlocks banish.\nHealer: Dispel, keep an eye on the add tanks.\nDD: Garr first, adds only when called." },
    { inst = "Geschmolzener Kern", boss = "Baron Geddon", text = "All: Living Bomb: run out of the raid AT ONCE!\nAll: Inferno - away from the boss, dispel Ignite Mana.\nTank: Hold the middle, step out briefly on Inferno.\nDD: Melee back off on Inferno." },
    { inst = "Geschmolzener Kern", boss = "Shazzrah", text = "All: He teleports - whoever has aggro, do not run away.\nAll: Remove Shazzrah's Curse, Arcane Explosion: melee keep your distance.\nTank: Get back on him right after every blink.\nHealer: Dispel (Deaden Magic)." },
    { inst = "Geschmolzener Kern", boss = "Sulfuronherold", text = "All: The 4 priests first, they heal each other.\nTank: Keep Sulfuron and the priests apart.\nDD: Interrupt! Stop the priests' Dark Mending." },
    { inst = "Geschmolzener Kern", boss = "Golemagg der Verbrenner", text = "All: Tank the two Core Ragers away from the boss, do not kill them.\nTank: Swap the Golemagg tank when Magma Splash stacks too high.\nDD: Only on Golemagg." },
    { inst = "Geschmolzener Kern", boss = "Majordomus Exekutus", text = "All: Watch the guards' magic reflection/damage shield - stop damage then.\nTank: One guard per tank, mages sheep the elite guards.\nDD: Healer guards (Flamewaker Healer) first." },
    { inst = "Geschmolzener Kern", boss = "Ragnaros", text = "All: Fire protection! Wrath of Ragnaros knocks melee back - then get back in.\nAll: Sons phase (after 3 min or when he submerges): kill all Sons of Flame.\nTank: Second tank ready when the first is knocked away.\nHealer: Spread out, ranged not too close (Lava Burst).\nDD: Melee: keep mana under control, ranged keep your distance." },
    { inst = "Pechschwingenhort", boss = "Feuerkralle der Ungezaehmte", text = "All: Phase 1: destroy the eggs (mind control via the orb), pick up the adds.\nAll: After all eggs: boss in the room - Fire Nova.\nTank: Gather the adds at the stairs.\nDD: Mages and dragonkin first." },
    { inst = "Pechschwingenhort", boss = "Vaelastrasz der Verdorbene", text = "All: Burning Adrenaline: run out of the raid AT ONCE (you are about to die).\nAll: Full resources at the start - use everything.\nTank: Set a tank order (Adrenaline on the tank).\nDD: Not in front of or behind the dragon." },
    { inst = "Pechschwingenhort", boss = "Brutlord Dreschbringer", text = "All: Knockback - stand against the wall.\nTank: Two tanks, aggro is split by Knock Away.\nDD: Mortal Strike on the tank: healers be prepared." },
    { inst = "Pechschwingenhort", boss = "Feuerschwinge", text = "All: Flame Buffet stacks - ranged behind pillars to let it drop.\nTank: Two tanks behind pillars, Wing Buffet knocks back.\nDD: Onyxia Scale Cloak required." },
    { inst = "Pechschwingenhort", boss = "Schattenschwinge", text = "All: Shadow of Ebonroc heals the boss - the tank with the debuff swaps.\nTank: Two tanks swap on Shadow.\nDD: Onyxia Scale Cloak required." },
    { inst = "Pechschwingenhort", boss = "Flammenmaul", text = "All: Frenzy - hunters: Tranquilizing Shot.\nTank: Two tanks, watch Wing Buffet.\nDD: Onyxia Scale Cloak required." },
    { inst = "Pechschwingenhort", boss = "Chromaggus", text = "All: Two of the five breath types per week - avoid the breath behind the corner.\nAll: Hourglass Sand for the Bronze affliction.\nTank: Tank at the gate, raid behind the corner.\nDD: Tranquilizing Shot on Frenzy." },
    { inst = "Pechschwingenhort", boss = "Nefarian", text = "All: Phase 1: dragonkin from both sides, watch the class calls.\nAll: Phase 3 (20%): the skeletons rise again - kill them again.\nTank: Nefarian at the wall, fear - Fear Ward.\nHealer: Class call for priests: healing hurts - be careful.\nDD: Hunters/warriors: watch the class calls (weapons gone, stance)." },
}
local function libTactics()
    local out = {}
    for _, d in ipairs(LIB) do
        out[#out + 1] = { id = "tpl-" .. tkey(d.boss), boss = d.boss, inst = L[d.inst], text = L[d.text], tpl = true }
    end
    return out
end
RC.LIB = LIB
-- eigene Rolle fuer die Rollen-Ansicht: tank / heal / dd
local function myRoleKey()
    local r = ns.RaidPrep and ns.RaidPrep.MyRole and select(2, pcall(ns.RaidPrep.MyRole)) or nil
    r = type(r) == "string" and r or ""
    if r == "tank" then return "tank" end
    if r:find("heal") then return "heal" end
    return "dd"
end
local function demoTactics()
    local out = {}
    for _, d in ipairs(DEMO_TAC) do out[#out + 1] = { id = "demo-" .. tkey(d.boss), boss = d.boss, inst = L[d.inst], text = L[d.text], demo = true, ts = ns.now() - 86400 } end
    return out
end
function RC.Tactics()
    local l = Store.List("tactics")
    local real = {}
    for _, r in ipairs(l) do if not r.del then real[#real + 1] = r end end
    if #real == 0 and demoOn() then real = demoTactics() end
    -- Bibliothek: nur Bosse, fuer die die Gilde noch keine eigene Taktik hat
    local have = {}
    for _, r in ipairs(real) do have[tkey(r.boss)] = true end
    for _, t in ipairs(libTactics()) do if not have[tkey(t.boss)] then real[#real + 1] = t end end
    table.sort(real, function(a, b)
        if (a.tpl and 1 or 0) ~= (b.tpl and 1 or 0) then return not a.tpl end
        if (a.inst or "") ~= (b.inst or "") then return (a.inst or "") < (b.inst or "") end
        return (a.boss or "") < (b.boss or "")
    end)
    return real
end
function RC.TacticOf(boss) local r = Store.Get("tactics", tkey(boss)) return r and not r.del and r or nil end
local function tacticById(id)
    if not id or id == "new" then return nil end
    local r = Store.Get("tactics", id)
    if r and not r.del then return r end
    if tostring(id):find("^demo%-") and demoOn() then
        for _, d in ipairs(demoTactics()) do if d.id == id then return d end end
    end
    if tostring(id):find("^tpl%-") then
        for _, d in ipairs(libTactics()) do if d.id == id then return d end end
    end
end
-- Taktiken dauerhaft bearbeiten: ab Schlachtzugsleiter (Admin.Can); in einer normalen Gruppe der Gruppenleiter
function RC.CanEdit()
    if ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.tactics.edit") then return true end
    return (not simOn() and ns.Group.IsInGroup() and not ns.Group.IsInRaid() and ns.isGroupLead()) and true or false
end
function RC.SaveTactic(boss, inst, text)
    boss = (boss or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if boss == "" then return end
    Store.Put("tactics", { id = tkey(boss), boss = boss, inst = inst or "", text = text or "", ts = ns.now() })
end
-- Abschnitte: "Tank:", "Heiler:", "DD:", "Alle:" beginnen einen Abschnitt (auch "[Tank]")
local SECT = {
    { key = "all", text = "For everyone", color = C.violet, icon = "raid" },
    { key = "tank", text = "Tanks", color = C.blue, icon = "role_tank" },
    { key = "heal", text = "Healer", color = C.mint, icon = "role_heal" },
    { key = "dd", text = "Damage (DPS)", color = C.red, icon = "role_dps" },
}
RC.SECT = SECT
local SECT_WORD = { alle = "all", all = "all", allgemein = "all", raid = "all", tank = "tank", tanks = "tank", heiler = "heal", heal = "heal",
    healer = "heal", heals = "heal", dd = "dd", dds = "dd", dps = "dd", schaden = "dd", damage = "dd", nahkampf = "dd", fernkampf = "dd" }
function RC.ParseTactic(text)
    local by = {}
    local cur = "all"
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = trim(line)
        local w, rest = line:match("^%[?([%a]+)%]?%s*:%s*(.*)$")
        if not w then w, rest = line:match("^%[([%a]+)%]%s*(.*)$") end
        local k = w and SECT_WORD[w:lower()]
        if k then cur, line = k, trim(rest) end
        line = line:gsub("^[%-%*]+%s*", "")
        if line ~= "" then
            by[cur] = by[cur] or {}
            table.insert(by[cur], line)
        end
    end
    local out = {}
    for _, s in ipairs(SECT) do if by[s.key] then out[#out + 1] = { key = s.key, def = s, lines = by[s.key] } end end
    return out
end
-- in den Chat: je Abschnitt eine Zeile (gekuerzt), hoechstens 6 Nachrichten
function RC.PostTactic(r)
    local ch = ns.groupChannel()
    if not ch or not r then return end
    -- Taktiken schreiben auch andere: ohne Escape-Sequenzen/Steuerzeichen in den Chat (ein "|" laesst
    -- den Server die Nachricht ablehnen und waere sonst ein Weg fuer fremde Sequenzen)
    local function plainChat(s) return (tostring(s or ""):gsub("[%c|]", " ")) end
    ns.SendChat("[Oasis] " .. plainChat(r.boss):sub(1, 80) .. ":", ch)
    local n = 0
    for _, s in ipairs(RC.ParseTactic(r.text)) do
        n = n + 1
        if n > 5 then break end
        local parts = {}
        for i, l in ipairs(s.lines) do parts[i] = plainChat(l) end
        local msg = (s.key == "all" and "" or (L[s.def.text] .. ": ")) .. table.concat(parts, " / ")
        if #msg > 240 then msg = msg:sub(1, 236) .. " ..." end
        ns.SendChat(msg, ch)
    end
end
-- Hinweis beim Anvisieren eines Bosses mit Taktik
local shown = {}
ns.On("PLAYER_TARGET_CHANGED", function()
    if ns.GuildOpt("rcTactTip") == false or ns.inCombat() then return end
    local n = ns.safe(ns.UnitName("target"))
    if not n or UnitIsPlayer("target") then return end
    local r = RC.TacticOf(n)
    if not r or shown[r.id] and GetTime() - shown[r.id] < 600 then return end
    shown[r.id] = GetTime()
    local first = (r.text or ""):match("[^\n]+") or ""
    K.Toast((L["Tactic: %s"]):format(r.boss), first, C.amber, function()
        RC.sel = r.id
        ns.ShowPage("tactics")
        ns.RCRefresh()
    end)
end)

------------------------------------------------------------------------
-- Seite: Teil "Raid-Check"
------------------------------------------------------------------------
local ROLE_ICON = { TANK = "role_tank", HEALER = "role_heal", DAMAGER = "role_dps" }
local ROLE_COL = { TANK = C.blue, HEALER = C.mint, DAMAGER = C.red }
local TILE_DEF = {
    { "ready", "checklist", "Ready", C.mint, "Clicked Ready in the ready check.", "Ready" },
    { "ench", "crafting", "Enchant missing", C.amber, "Players with missing enchants (from the shared profile).", "Enchant" },
    { "buffs", "heart", "Buffs missing", C.pink, "Players missing buffs (buff monitor).", "Buffs" },
    { "away", "radar", "Away / AFK", C.red, "Offline, dead, far away or no answer to the ready check.", "Away" },
    { "dura", "settings", "Low durability", C.blue, "Gear below 70 % (from raid preparation).", "Durability" },
}
local TILE_SUB = { ench = "fehlt", buffs = "fehlen", away = "weg", dura = "niedrig" }
local LIGHT_W = 58

local function buildCheck(p, ck)
    -- Bereitschafts-Ring
    ck.ringCard = U.Card(ck, C.mint)
    ck.ringCard:SetPoint("TOPLEFT", 0, 0)
    ck.ringCard:SetSize(250, 100)
    ck.ring = U.Ring(ck.ringCard, 86, 36)
    ck.ring:SetPoint("LEFT", 10, 0)
    ck.rTitle = K.Title(ck.ringCard, 14, C.text)
    ck.rTitle:SetPoint("TOPLEFT", ck.ring, "TOPRIGHT", 10, -10)
    ck.rTitle:SetPoint("RIGHT", ck.ringCard, "RIGHT", -8, 0)
    ck.rSub = K.Text(ck.ringCard, 11, C.muted)
    ck.rSub:SetPoint("TOPLEFT", ck.rTitle, "BOTTOMLEFT", 0, -4)
    ck.rSub:SetPoint("RIGHT", ck.ringCard, "RIGHT", -8, 0)
    ck.rSub:SetWordWrap(true)
    ck.rSub:SetJustifyV("TOP")
    ck.rSub:SetHeight(42)
    ck.timer = CreateFrame("Frame", nil, ck.ringCard)
    ck.timer:SetPoint("BOTTOMLEFT", ck.ring, "BOTTOMRIGHT", 10, 6)
    ck.timer:SetPoint("RIGHT", ck.ringCard, "RIGHT", -10, 0)
    ck.timer:SetHeight(3)
    glass(ck.timer, 8, 0.05)
    ck.timer.fill = ck.timer:CreateTexture(nil, "ARTWORK")
    ck.timer.fill:SetPoint("TOPLEFT") ck.timer.fill:SetPoint("BOTTOMLEFT")
    ck.timer.fill:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 1)
    ck.timer:Hide()
    -- Kacheln (Klick = Liste filtern)
    ck.tiles = {}
    for i, d in ipairs(TILE_DEF) do
        local t = U.Tile(ck, d[2], L[d[6]], d[4], function()
            p.filter = (p.filter ~= d[1]) and d[1] or nil
            ns.RCRefresh()
        end)
        t.key = d[1]
        t.tip = { L[d[3]], L[d[5]], "|cff888888" .. L["Click: show only these / clear filter"] .. "|r" }
        ck.tiles[i] = t
    end
    -- Knoepfe
    ck.rcBtn = K.Button(ck, L["Start ready check"], 160, 26, "primary", function()
        if simOn() then
            RC.DemoReadyCheck()
        elseif ns.Group.IsInGroup() then
            if ns.isGroupLead() and DoReadyCheck then pcall(DoReadyCheck) end
        elseif demoOn() then
            RC.DemoReadyCheck()
        end
    end)
    ck.rcBtn:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Start ready check"], simOn() and L["Raid sim: plays a ready check with the simulated raid."]
            or (ns.Group.IsInGroup() and L["Asks everyone in the group: ready?"] or L["Demo: plays a ready check with the sample group."]) })
    end)
    ck.rcBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    ck.report = K.Button(ck, L["Announce missing"], 140, 26, "ghost", function() RC.Report() end)
    if K.LeadTag then ck.rcLead = K.LeadTag(ck, true) ck.rcLead:SetPoint("BOTTOMRIGHT", ck.rcBtn, "TOPRIGHT", 0, 2) end
    ck.report:SetPoint("LEFT", ck.rcBtn, "RIGHT", 8, 0)
    ck.filterTxt = K.Text(ck, 11, C.muted)
    ck.filterTxt:SetPoint("LEFT", ck.report, "RIGHT", 12, 0)
    ck.filterTxt:SetPoint("RIGHT", ck, "RIGHT", -4, 0)
    -- Kopf der Teilnehmerliste
    ck.head = CreateFrame("Frame", nil, ck)
    ck.head:SetPoint("TOPLEFT", 0, -110)
    ck.head:SetPoint("RIGHT", ck, "RIGHT", -8, 0)
    ck.head:SetHeight(18)
    local hn = K.Text(ck.head, 10, C.dim)
    hn:SetPoint("LEFT", 52, 0)
    hn:SetText(L["Roster"])
    ck.head.count = K.Text(ck.head, 10, C.muted)
    ck.head.count:SetPoint("LEFT", hn, "RIGHT", 6, 0)
    for i, c in ipairs(CRIT) do
        local t = K.Text(ck.head, 10, C.dim, "CENTER")
        t:SetPoint("CENTER", ck.head, "RIGHT", -(#CRIT - i) * LIGHT_W - LIGHT_W / 2 - 4, 0)
        t:SetWidth(LIGHT_W)
        t:SetText(L[c.label])
    end
    local hl = ck.head:CreateTexture(nil, "ARTWORK")
    hl:SetPoint("BOTTOMLEFT") hl:SetPoint("BOTTOMRIGHT")
    hl:SetHeight(1)
    hl:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    -- Teilnehmer als Zeilen mit Ampeln
    ck.list = K.List(ck, 32, function(l)
        local r = K.Row(l)
        r.roleBar = r:CreateTexture(nil, "ARTWORK")
        r.roleBar:SetPoint("TOPLEFT", 0, -4) r.roleBar:SetPoint("BOTTOMLEFT", 0, 4)
        r.roleBar:SetWidth(2)
        r.role = r:CreateTexture(nil, "ARTWORK")
        r.role:SetSize(14, 14)
        r.role:SetPoint("LEFT", 9, 0)
        r.cls = r:CreateTexture(nil, "ARTWORK")
        r.cls:SetSize(20, 20)
        r.cls:SetPoint("LEFT", 28, 0)
        r.clsMask = r.cls
        r:Col("name", 54, 150, 13)
        r.cols.name:ClearAllPoints()
        r.cols.name:SetPoint("TOPLEFT", 54, -3)
        r.prob = K.Text(r, 10, C.muted)
        r.prob:SetPoint("TOPLEFT", r.cols.name, "BOTTOMLEFT", 0, -1)
        r.prob:SetPoint("RIGHT", r, "RIGHT", -(#CRIT * LIGHT_W + 10), 0)
        r.lights = {}
        for i, c in ipairs(CRIT) do
            local lt = U.Light(r, 11)
            lt:SetPoint("CENTER", r, "RIGHT", -(#CRIT - i) * LIGHT_W - LIGHT_W / 2 + 4, 0)
            r.lights[i] = lt
        end
        return r
    end, function(r, e)
        local ic = ROLE_ICON[e.role or ""]
        if ic then r.role:SetTexture(glyph(ic)) r.role:Show() else r.role:Hide() end
        local rc = ROLE_COL[e.role or ""] or C.dim
        r.role:SetVertexColor(rc[1], rc[2], rc[3])
        r.roleBar:SetColorTexture(rc[1], rc[2], rc[3], 0.8)
        U.ClassIcon(r.cls, e.class)
        r.cols.name:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(e.name) or ns.colorName(e.name, e.class))
        local pr = problems(e)
        r.prob:SetText(#pr > 0 and ("|cfffac257" .. table.concat(pr, "  ·  ") .. "|r") or ("|cff66db9e" .. L["all good"] .. "|r"))
        for i, c in ipairs(CRIT) do
            local sev, tip = crit(e, c.key)
            local lt = r.lights[i]
            lt:SetState(sev, tip)
        end
        -- frische Antwort auf den Ready-Check: Ampel pulsiert einmal
        local fl = RC.flash[e.name]
        if fl and fl ~= r.lights[1].seenFlash and GetTime() - fl < 1.5 then
            r.lights[1].seenFlash = fl
            r.lights[1]:Pulse()
        end
    end)
    ck.list:SetPoint("TOPLEFT", 0, -130)
    ck.list:SetPoint("BOTTOMRIGHT")
    ck.list.empty:SetText("")
    ck.empty = U.Empty(ck, "groups", C.mint)
    ck.empty:SetPoint("TOP", ck.list, "TOP", 0, -30)
    -- Breite verteilen (Kacheln neben dem Ring)
    local function layout()
        local w = ck:GetWidth() or 770
        U.LayoutTiles(ck.tiles, 260, 0, w - 260, 8)
        ck.rcBtn:ClearAllPoints()
        ck.rcBtn:SetPoint("TOPLEFT", ck, "TOPLEFT", 260, -72)
    end
    ck:SetScript("OnSizeChanged", layout)
    layout()
end

local function refreshCheck(p)
    local ck = p.ck
    local rows = RC.Rows()
    local n, ready, waiting, nok = #rows, 0, 0, 0
    local cnt = { ready = 0, ench = 0, buffs = 0, away = 0, dura = 0 }
    for _, r in ipairs(rows) do
        if r.ready == true then ready = ready + 1 end
        if r.ready == "wait" then waiting = waiting + 1 end
        for k, fn in pairs(FILTER) do if k ~= "ready" and fn(r) then cnt[k] = cnt[k] + 1 end end
        if #problems(r) == 0 then nok = nok + 1 end
    end
    cnt.ready = ready
    local running = RC.readyEnd and GetTime() < RC.readyEnd and waiting > 0
    -- Ring
    if n == 0 then
        ck.ring:Set(0, 1, C.dim, "-", L["nobody here"])
        ck.ringCard:Hide()
        ck.rTitle:SetText(L["No group"])
        ck.rSub:SetText(L["Once you are in a group you can see here whether everyone is ready."])
    elseif RC.readyAt or rows[1].demo then
        local all = ready == n
        ck.ring:Set(ready, n, all and C.mint or running and C.blue or C.amber, ready .. "/" .. n, L["ready"])
        if running then
            ck.rTitle:SetText(L["Ready check running ..."])
            ck.rSub:SetText((L["%d answers still missing."]):format(waiting))
        elseif all then
            ck.rTitle:SetText("|cff66db9e" .. L["Everyone ready!"] .. "|r")
            ck.rSub:SetText(L["Let's go - good luck on the pull."])
        else
            ck.rTitle:SetText((L["%d not ready"]):format(n - ready))
            ck.rSub:SetText(RC.readyAt and ((L["Last ready check %s"]):format(ns.ago(RC.readyAt))) or L["Example group (demo)"])
        end
    else
        ck.ring:Set(nok, n, nok == n and C.mint or C.amber, nok .. "/" .. n, L["without issues"])
        ck.rTitle:SetText(L["No ready check yet"])
        ck.rSub:SetText(L["The ring shows who has nothing open."])
    end
    ck.ringCard:SetShown(n > 0)
    ck.ringCard:SetColor(n > 0 and (ready == n and C.mint or running and C.blue or C.amber) or C.dim)
    if running then
        ck.timer:Show()
        local total = math.max(1, (RC.readyEnd or 0) - (RC.readyStart or ((RC.readyEnd or 0) - 35)))
        local left = math.max(0, (RC.readyEnd or 0) - GetTime())
        ck.timer.fill:SetWidth(math.max(1, (ck.timer:GetWidth() or 100) * math.min(1, left / total)))
    else
        ck.timer:Hide()
    end
    -- Kacheln
    for _, t in ipairs(ck.tiles) do
        local k = t.key
        if k == "ready" then
            t:Set(ready, "/ " .. n, n > 0 and ready / n or 0, ready == n and n > 0 and C.mint or C.text)
        else
            local v = cnt[k]
            t:Set(v, v > 0 and L[TILE_SUB[k] or "Player"] or L["ok"], nil, v > 0 and t.color or C.mint)
        end
        t:SetSel(p.filter == k)
        t:SetShown(n > 0)
    end
    -- Knoepfe
    local lead = ns.Group.IsInGroup() and ns.isGroupLead()
    ck.rcBtn:SetShown(ns.Group.IsInGroup() or n > 0)
    K.LockButton(ck.rcBtn, function() return not ns.Group.IsInGroup() or ns.isGroupLead() end, ns.Group.IsInRaid() and "raidassist" or "grouplead")
    ck.rcBtn:SetEnabledState(not running)
    ck.report:SetShown(n > 0)
    if not ck.rcBtn:IsShown() then
        ck.report:ClearAllPoints()
        ck.report:SetPoint("TOPLEFT", ck, "TOPLEFT", 260, -72)
    else
        ck.report:ClearAllPoints()
        ck.report:SetPoint("LEFT", ck.rcBtn, "RIGHT", 8, 0)
    end
    -- Filter
    local list = rows
    if p.filter and FILTER[p.filter] then
        list = {}
        for _, r in ipairs(rows) do if FILTER[p.filter](r) then list[#list + 1] = r end end
        for _, d in ipairs(TILE_DEF) do
            if d[1] == p.filter then ck.filterTxt:SetText((L["Filter: %s"]):format(L[d[3]]) .. "  |cff888888(" .. L["click the tile again"] .. ")|r") end
        end
    else
        ck.filterTxt:SetText(n > 0 and ("|cff888888" .. L["Tip: click a light for details"] .. "|r") or "")
    end
    ck.head.count:SetText(n > 0 and (#list .. (#list ~= n and (" / " .. n) or "")) or "")
    ck.head:SetShown(n > 0)
    ck.list:SetData(list)
    if n == 0 then
        ck.empty:Set(L["You are not in a group. Once you are in a group or raid, everything for the pull shows up here."],
            L["Show example"], function() if ns.Demo and ns.Demo.Load then ns.Demo.Load() ns.RCRefresh() end end)
        ck.empty.btn:SetShown(ns.Demo and ns.Demo.Load and ns.IsDev() and not demoOn() and true or false)
        ck.empty:Show()
    elseif #list == 0 then
        ck.empty:Set(L["Nobody in this filter - great!"], L["Clear filter"], function() p.filter = nil ns.RCRefresh() end)
        ck.empty:Show()
    else
        ck.empty:Hide()
    end
end

------------------------------------------------------------------------
-- Seite: Teil "Boss-Taktiken"
------------------------------------------------------------------------
local tacSearch, tacRole = "", "all"
-- einen Abschnitt in den Gruppen-/Raidchat
local function postSection(r, s)
    local ch = ns.groupChannel()
    if not ch or not r or not s then return end
    local function plainChat(x) return (tostring(x or ""):gsub("[%c|]", " ")) end
    local parts = {}
    for i, l in ipairs(s.lines) do parts[i] = plainChat(l) end
    local msg = "[" .. plainChat(r.boss):sub(1, 60) .. "] " .. L[s.def.text] .. ": " .. table.concat(parts, " / ")
    if #msg > 240 then msg = msg:sub(1, 236) .. " ..." end
    ns.SendChat(msg, ch)
end
local function buildTactics(p, tc)
    tc.side = CreateFrame("Frame", nil, tc)
    tc.side:SetPoint("TOPLEFT", 0, 0)
    tc.side:SetPoint("BOTTOMLEFT", 0, 36)
    tc.side:SetWidth(236)
    U.Glass(tc.side, 14, 0.025)
    tc.search = K.Input(tc.side, 212, L["Search boss or instance ..."], function(t)
        tacSearch = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        ns.RefreshPage("tactics")
    end)
    tc.search:SetPoint("TOP", 0, -10)
    U.Glass(tc.search, 8, 0.04)
    tc.list = K.List(tc, 30, function(l)
        local r = K.Row(l)
        r.stripe:SetAlpha(0)
        r.hdr = K.Text(r, 10, C.dim)
        r.hdr:SetPoint("BOTTOMLEFT", 4, 4)
        r.hdrLine = r:CreateTexture(nil, "ARTWORK")
        r.hdrLine:SetPoint("BOTTOMLEFT", 4, 1) r.hdrLine:SetPoint("BOTTOMRIGHT", -4, 1)
        r.hdrLine:SetHeight(1)
        r.hdrLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        r.selBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.selBg:SetAllPoints()
        r.selBg:SetColorTexture(1, 1, 1, 0.06)
        r.ico = K.Glyph(r, 14, glyph("raid"), C.muted)
        r.ico:SetPoint("LEFT", 10, 0)
        r:Col("boss", 32, 130, 13)
        r.cols.boss:SetWordWrap(false)
        r.tgt = r:CreateTexture(nil, "OVERLAY")
        r.tgt:SetTexture(CIRCLE)
        r.tgt:SetSize(7, 7)
        r.tgt:SetPoint("LEFT", r.ico, "RIGHT", -3, 6)
        r.tgt:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
        r.secs = {}
        for i = 1, 4 do
            local d = r:CreateTexture(nil, "ARTWORK")
            d:SetTexture(CIRCLE)
            d:SetSize(6, 6)
            d:SetPoint("RIGHT", -(4 - i) * 9 - 10, 0)
            r.secs[i] = d
        end
        r:SetScript("OnClick", function(self)
            if self.item and not self.item.hdr then
                RC.sel, p.tcEdit = self.item.id, false
                ns.RCRefresh()
                U.Reveal(tc.card)
            end
        end)
        return r
    end, function(r, e)
        local isH = e.hdr ~= nil
        r.hdr:SetShown(isH) r.hdrLine:SetShown(isH)
        r.ico:SetShown(not isH) r.cols.boss:SetShown(not isH)
        r:EnableMouse(not isH)
        if isH then
            r.hdr:SetText(e.hdr .. "  |cff666666" .. e.n .. "|r")
            r.selBg:Hide() r.sel:Hide() r.tgt:Hide()   -- 0.6.466: Ziel-Punkt stand auf den Kapitel-Zeilen
            for _, d in ipairs(r.secs) do d:Hide() end
            return
        end
        local on = RC.sel == e.id
        r.cols.boss:SetText(e.boss)
        r.ico:SetAlpha(e.tpl and 0.5 or 1)
        local tn = ns.safe(ns.UnitName("target"))
        r.tgt:SetShown(tn ~= nil and tkey(tn) == tkey(e.boss))
        local bc = on and C.text or (e.tpl and C.dim or C.muted)
        r.cols.boss:SetTextColor(bc[1], bc[2], bc[3])
        local ic = on and C.accent or C.muted
        r.ico:SetVertexColor(ic[1], ic[2], ic[3])
        r.selBg:SetShown(on)
        r.sel:SetShown(on)
        local have = {}
        for _, s in ipairs(RC.ParseTactic(e.text)) do have[s.key] = true end
        for i, s in ipairs(SECT) do
            local d = r.secs[i]
            d:SetShown(true)
            d:SetVertexColor(s.color[1], s.color[2], s.color[3], have[s.key] and (e.tpl and 0.45 or 1) or 0.12)
        end
    end)
    tc.list:SetPoint("TOPLEFT", tc.side, "TOPLEFT", 4, -44)
    tc.list:SetPoint("BOTTOMRIGHT", tc.side, "BOTTOMRIGHT", -4, 6)
    tc.list.empty:SetText(L["Nothing found."])
    tc.new = K.Button(tc, "+ " .. L["New tactic"], 236, 26, "ghost", function()
        RC.sel, p.tcEdit = "new", true
        tc.shownId = nil
        ns.RCRefresh()
        U.Reveal(tc.card)
    end)
    tc.new:SetPoint("BOTTOMLEFT", 0, 2)
    -- Karte rechts
    tc.card = U.Card(tc, C.accent)
    tc.card:SetPoint("TOPLEFT", 244, 0)
    tc.card:SetPoint("BOTTOMRIGHT")
    local cd = tc.card
    cd.title = K.Title(cd, 20, C.text)
    cd.title:SetPoint("TOPLEFT", 18, -14)
    cd.title:SetPoint("RIGHT", cd, "RIGHT", -310, 0)
    cd.inst = K.Text(cd, 11, C.muted)
    cd.inst:SetPoint("TOPLEFT", cd.title, "BOTTOMLEFT", 0, -4)
    cd.inst:SetPoint("RIGHT", cd, "RIGHT", -280, 0)
    cd.post = K.Button(cd, L["Post in raid chat"], 140, 24, "ghost", function()
        local r = tacticById(RC.sel)
        if r and ns.Group.IsInGroup() then RC.PostTactic(r) K.Toast(L["Tactic posted"], r.boss, C.mint) end
    end)
    cd.post:SetPoint("TOPRIGHT", -14, -14)
    -- Vorlage aus der Bibliothek als Gilden-Taktik uebernehmen
    cd.take = K.Button(cd, L["Apply"], 110, 24, "ghost", function()
        local r = tacticById(RC.sel)
        if not (r and r.tpl and RC.CanEdit()) then return end
        RC.SaveTactic(r.boss, r.inst, r.text)
        RC.sel = tkey(r.boss)
        K.Toast(L["Tactic applied"], r.boss, C.mint)
        ns.RCRefresh()
    end)
    cd.take:SetPoint("RIGHT", cd.post, "LEFT", -6, 0)
    cd.take:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Apply"], L["Save as guild tactic - editable afterwards and visible to all."] }) end)
    cd.take:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Ansicht: alles oder nur, was meine Rolle angeht
    cd.role = K.Segments(cd, { { key = "all", text = L["All"] }, { key = "mine", text = L["My role"] } },
        function(k) tacRole = k ns.RefreshPage("tactics") end, nil, { size = 11, pad = 14 })
    cd.role:SetPoint("TOPRIGHT", -14, -44)
    cd.post:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Post in raid chat"], L["Shortened: one line per section."], not ns.Group.IsInGroup() and ("|cfffac257" .. L["Only in a group."] .. "|r") or nil }) end)
    cd.post:HookScript("OnLeave", function() GameTooltip:Hide() end)
    cd.edit = K.Button(cd, L["Edit"], 96, 24, "ghost", function() p.tcEdit = true tc.shownId = nil ns.RCRefresh() U.Reveal(tc.ed) end)
    if K.LeadTag then cd.leadTag = K.LeadTag(cd, true) cd.leadTag:SetPoint("RIGHT", cd.edit, "LEFT", -6, 0) end
    cd.edit:SetPoint("RIGHT", cd.post, "LEFT", -6, 0)
    cd.del = K.Button(cd, L["Put out"], 80, 24, "danger", function()
        local r = tacticById(RC.sel)
        if r and not r.demo then Store.Delete("tactics", r.id) RC.sel = nil ns.RCRefresh() end
    end)
    cd.del:SetPoint("RIGHT", cd.edit, "LEFT", -6, 0)
    -- Ansicht: Abschnitte als farbige Bloecke
    cd.view = U.Scroll(cd)
    cd.view:SetPoint("TOPLEFT", 14, -74)
    cd.view:SetPoint("BOTTOMRIGHT", -10, 10)
    cd.blocks = {}
    local function block(i)
        local b = cd.blocks[i]
        if b then return b end
        b = CreateFrame("Frame", nil, cd.view.content)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:Hide()
        U.Glass(b, 10, 0.03)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:Hide()
        b.bar:SetPoint("TOPLEFT") b.bar:SetPoint("BOTTOMLEFT")
        b.bar:SetWidth(3)
        b.ico = K.Glyph(b, 14, glyph("raid"), C.muted)
        b.ico:SetPoint("TOPLEFT", 12, -9)
        b.head = K.Title(b, 12, C.text)
        b.head:SetPoint("LEFT", b.ico, "RIGHT", 7, 0)
        -- nur diesen Abschnitt posten (z.B. nur fuer die Heiler)
        b.post = CreateFrame("Button", nil, b)
        b.post:SetSize(70, 18)
        b.post:SetPoint("TOPRIGHT", -8, -6)
        b.post.t = K.Text(b.post, 10, C.dim, "RIGHT")
        b.post.t:SetPoint("RIGHT", 0, 0)
        b.post.t:SetText(L["post"] .. "  >")
        b.post:SetScript("OnEnter", function(self)
            self.t:SetTextColor(C.text[1], C.text[2], C.text[3])
            K.ShowTip(self, { L["Post only this section"], not ns.Group.IsInGroup() and ("|cfffac257" .. L["Only in a group."] .. "|r") or nil })
        end)
        b.post:SetScript("OnLeave", function(self) self.t:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
        b.post:SetScript("OnClick", function(self)
            if not ns.Group.IsInGroup() then return end
            postSection(tacticById(RC.sel), self.sec)
            K.Toast(L["Section posted"], self.sec and L[self.sec.def.text] or "", C.mint)
        end)
        b.lines = {}
        cd.blocks[i] = b
        return b
    end
    function cd:ShowSections(secs)
        local y = 0
        local W = (cd.view:GetWidth() or 480) - 10
        for i, s in ipairs(secs) do
            local b = block(i)
            local c = s.def.color
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", cd.view.content, "TOPLEFT", 0, -y)
            b:SetPoint("RIGHT", cd.view.content, "RIGHT", 0, 0)
            U.Glass(b, 10, 0.03, { c[1], c[2], c[3], 0.25 })
            b.ico:SetTexture(glyph(s.def.icon))
            b.ico:SetVertexColor(c[1], c[2], c[3])
            b.head:SetText(L[s.def.text])
            b.post.sec = s
            local mine = tacRole == "mine" and s.key ~= "all"
            b.head:SetText(L[s.def.text] .. (mine and ("  |cffe8b44a" .. L["your role"] .. "|r") or ""))
            b.head:SetTextColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5)
            local ly = 32
            for j, line in ipairs(s.lines) do
                local ln = b.lines[j]
                if not ln then
                    ln = {}
                    ln.dot = b:CreateTexture(nil, "ARTWORK")
                    ln.dot:SetTexture(CIRCLE)
                    ln.dot:SetSize(5, 5)
                    ln.fs = K.Text(b, 12, C.text)
                    ln.fs:SetWordWrap(true)
                    ln.fs:SetJustifyV("TOP")
                    b.lines[j] = ln
                end
                ln.dot:SetVertexColor(c[1], c[2], c[3])
                ln.dot:ClearAllPoints()
                ln.dot:SetPoint("TOPLEFT", 16, -(ly + 5))
                ln.fs:ClearAllPoints()
                ln.fs:SetPoint("TOPLEFT", 28, -ly)
                ln.fs:SetWidth(math.max(60, W - 40))
                ln.fs:SetText(line)
                ln.dot:Show() ln.fs:Show()
                ly = ly + math.max(15, (ln.fs:GetStringHeight() or 14)) + 5
            end
            for j = #s.lines + 1, #b.lines do b.lines[j].dot:Hide() b.lines[j].fs:Hide() end
            local h = ly + 6
            b:SetHeight(h)
            b:Show()
            y = y + h + 8
        end
        for i = #secs + 1, #cd.blocks do cd.blocks[i]:Hide() end
        cd.view:SetContentHeight(y)
    end
    cd.noText = K.Text(cd, 12, C.dim, "CENTER")
    cd.noText:SetPoint("CENTER", cd.view, "CENTER", 0, 0)
    cd.noText:SetText(L["This tactic is still empty."])
    -- Bearbeiten
    local ed = CreateFrame("Frame", nil, cd)
    ed:SetPoint("TOPLEFT", 14, -12)
    ed:SetPoint("BOTTOMRIGHT", -14, 10)
    tc.ed = ed
    tc.boss = K.Input(ed, 220, L["Boss (exactly as in game)"])
    tc.boss:SetPoint("TOPLEFT", 0, 0)
    tc.inst = K.Input(ed, 170, L["Instance"])
    tc.inst:SetPoint("LEFT", tc.boss, "RIGHT", 8, 0)
    ed.quick = {}
    local qx = 0
    for i, s in ipairs(SECT) do
        local word = ({ all = "All", tank = "Tank", heal = "Healer", dd = "DD" })[s.key]
        local b = K.Button(ed, "+ " .. L[word], 70, 22, "ghost", function()
            local t = tc.text:GetText() or ""
            if t ~= "" and not t:find("\n$") then t = t .. "\n" end
            tc.text:SetText(t .. L[word] .. ": ")
            tc.text:SetFocus()
            tc.text:SetCursorPosition(#tc.text:GetText())
        end)
        b.label:SetTextColor(s.color[1], s.color[2], s.color[3])
        b:SetPoint("TOPLEFT", qx, -32)
        qx = qx + 74
        ed.quick[i] = b
    end
    ed.hint = K.Text(ed, 10, C.dim)
    ed.hint:SetPoint("LEFT", ed.quick[#ed.quick], "RIGHT", 10, 0)
    ed.hint:SetPoint("RIGHT", ed, "RIGHT", 0, 0)
    ed.hint:SetText(L["Lines starting with Tank:, Healer:, DPS: or All: begin a section."])
    tc.text = CreateFrame("EditBox", nil, ed)
    tc.text:SetMultiLine(true)
    tc.text:SetAutoFocus(false)
    tc.text:SetFont(K.FONT, 13, "")
    tc.text:SetTextColor(C.text[1], C.text[2], C.text[3])
    tc.text:SetPoint("TOPLEFT", 6, -66)
    tc.text:SetPoint("BOTTOMRIGHT", -6, 40)
    tc.text:SetMaxLetters(2000)
    tc.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local bg = ed:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetPoint("TOPLEFT", tc.text, -6, 6) bg:SetPoint("BOTTOMRIGHT", tc.text, 6, -6)
    bg:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
    local click = CreateFrame("Button", nil, ed)
    click:SetPoint("TOPLEFT", tc.text, -6, 6) click:SetPoint("BOTTOMRIGHT", tc.text, 6, -6)
    click:SetFrameLevel(math.max(1, (tc.text:GetFrameLevel() or 2) - 1))
    click:SetScript("OnClick", function() tc.text:SetFocus() end)
    tc.save = K.Button(ed, L["Save"], 100, 24, "primary", function()
        local boss = trim(tc.boss:GetText())
        if boss == "" then K.Toast(L["Boss tactics"], L["Please enter a boss name."], C.amber) return end
        RC.SaveTactic(boss, tc.inst:GetText(), tc.text:GetText())
        RC.sel, p.tcEdit = tkey(boss), false
        K.Toast(L["Tactic saved"], boss, C.mint)
        ns.RCRefresh()
        U.Reveal(tc.card)
    end)
    tc.save:SetPoint("BOTTOMRIGHT", 0, 0)
    tc.cancel = K.Button(ed, L["Cancel"], 96, 24, "ghost", function()
        p.tcEdit = false
        if RC.sel == "new" then RC.sel = nil end
        tc.shownId = nil
        ns.RCRefresh()
    end)
    tc.cancel:SetPoint("RIGHT", tc.save, "LEFT", -8, 0)
    ed.count = K.Text(ed, 10, C.dim)
    ed.count:SetPoint("BOTTOMLEFT", 0, 6)
    tc.text:SetScript("OnTextChanged", function(self)
        local n = #RC.ParseTactic(self:GetText())
        ed.count:SetText((L["%d sections"]):format(n))
    end)
    tc.empty = U.Empty(tc, "raid", C.amber)
    tc.empty:SetPoint("TOP", tc.card, "TOP", 0, -60)
end

local function refreshTactics(p)
    local tc = p.tc
    local all = RC.Tactics()
    -- nach Instanz gruppiert
    local data, last, hdr = {}, nil, nil
    for _, r in ipairs(all) do
        local hit = tacSearch == "" or tostring(r.boss or ""):lower():find(tacSearch, 1, true) or tostring(r.inst or ""):lower():find(tacSearch, 1, true)
        if not hit then r = nil end
        if r then
        local inst = (r.inst or "") ~= "" and r.inst or L["No instance"]
        if r.tpl then inst = L["Library"] .. " · " .. inst end
        if inst ~= last then hdr = { hdr = inst, n = 0 } data[#data + 1] = hdr last = inst end
        hdr.n = hdr.n + 1
        data[#data + 1] = r
        end
    end
    local edit = RC.CanEdit()
    tc.new:Show()
    K.LockButton(tc.new, RC.CanEdit, "raidlead")

    local r = tacticById(RC.sel)
    if r == nil and RC.sel ~= "new" then r = all[1] RC.sel = r and r.id or nil end
    if not edit then p.tcEdit = false end
    if RC.sel == "new" then p.tcEdit = true end
    tc.list:SetData(data)
    if not r and RC.sel ~= "new" then
        tc.card:Hide()
        tc.empty:Set(L["No tactics yet. Raid leaders can add a short tactic per boss - everyone sees it here and gets it when targeting the boss."],
            edit and L["Add first tactic"] or nil, function() RC.sel, p.tcEdit = "new", true tc.shownId = nil ns.RCRefresh() end)
        tc.empty:Show()
        return
    end
    tc.empty:Hide()
    tc.card:Show()
    local cd = tc.card
    local editing = p.tcEdit and edit
    tc.ed:SetShown(editing)
    cd.view:SetShown(not editing)
    cd.title:SetShown(not editing) cd.inst:SetShown(not editing)
    cd.post:SetShown(not editing and r ~= nil)
    cd.take:SetShown(not editing and r ~= nil and r.tpl == true)
    if r and r.tpl then K.LockButton(cd.take, RC.CanEdit, "raidlead") end
    cd.role:SetShown(not editing and r ~= nil)
    cd.role:Select(tacRole)
    cd.post:SetEnabledState(ns.Group.IsInGroup() and ns.isGroupLead())
    cd.edit:SetShown(not editing and r ~= nil and not r.tpl)
    cd.del:SetShown(not editing and r ~= nil and not r.demo and not r.tpl)
    K.LockButton(cd.edit, RC.CanEdit, "raidlead")
    K.LockButton(cd.del, RC.CanEdit, "raidlead")
    if cd.leadTag then
        local anchor = (cd.take:IsShown() and cd.take) or (cd.del:IsShown() and cd.del) or (cd.edit:IsShown() and cd.edit) or nil
        cd.leadTag:SetShown(anchor ~= nil)
        if anchor then
            cd.leadTag:ClearAllPoints()
            cd.leadTag:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        end
    end
    if editing then
        cd:SetColor(C.accent)
        cd.noText:Hide()
        local sid = (RC.sel or "") .. ":" .. tostring(r and r.u)
        if not tc.text:HasFocus() and tc.shownId ~= sid then
            tc.shownId = sid
            tc.boss:SetText(r and r.boss or "")
            tc.inst:SetText(r and r.inst or (RC.sel == "new" and (ns.safe(GetRealZoneText()) or "") or ""))
            tc.text:SetText(r and r.text or "")
        end
        return
    end
    tc.shownId = nil
    cd.title:SetText(r.boss or "?")
    local meta = (r.inst or "") ~= "" and r.inst or L["No instance"]
    if r.tpl then meta = meta .. "  ·  |cff8fa8ff" .. L["from the Oasis library"] .. "|r"
    elseif r.demo then meta = meta .. "  ·  |cfffac257" .. L["Example (demo)"] .. "|r"
    elseif r.ts then meta = meta .. "  ·  " .. (L["changed %s"]):format(ns.ago(r.ts)) end
    cd.inst:SetText(meta)
    local secs = RC.ParseTactic(r.text)
    if tacRole == "mine" then
        local mk = myRoleKey()
        local f = {}
        for _, x in ipairs(secs) do if x.key == "all" or x.key == mk then f[#f + 1] = x end end
        secs = f
    end
    local col = secs[1] and secs[1].def.color or C.accent
    cd:SetColor(col)
    if cd.shownSel ~= r.id .. tostring(r.u) .. tostring(r.text and #r.text) then
        cd.shownSel = r.id .. tostring(r.u) .. tostring(r.text and #r.text)
        cd.view:Top()
    end
    cd:ShowSections(secs)
    cd.noText:SetShown(#secs == 0)
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local function area(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetAllPoints()
    return f
end
ns.RegisterPage({
    key = "raidcheck", title = "Raid check", order = 2.76,
    sub = "Ready for the pull? Readiness, enchants and buffs per player",
    build = function(p)
        p.view = "check"
        p.ck = area(p)
        buildCheck(p, p.ck)
        p:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            local fast = RC.readyEnd and GetTime() < RC.readyEnd + 1
            if self.acc > (fast and 0.5 or 2) and (ns.Group.IsInGroup() or fast) then self.acc = 0 ns.RefreshPage("raidcheck") end
        end)
    end,
    refresh = function(p) refreshCheck(p) end,
})
ns.RegisterPage({
    key = "tactics", title = "Boss tactics", order = 2.763,
    sub = "Short tactic per boss, by role - into raid chat with one click",
    build = function(p)
        p.view = "tac"
        p.tc = area(p)
        buildTactics(p, p.tc)
    end,
    refresh = function(p) refreshTactics(p) end,
})
ns.RegisterPage({
    key = "lootrules", title = "Loot rules", order = 2.766,
    sub = "Distribute loot automatically when you are master looter",
    build = function(p)
        p.view = "rules"
        p.ru = area(p)
        if ns.LootRules then ns.LootRules.Build(p.ru) end
    end,
    refresh = function(p) if ns.LootRules then ns.LootRules.Refresh(p.ru) end end,
})
end)

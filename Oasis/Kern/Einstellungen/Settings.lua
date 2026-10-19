-- Oasis - Einstellungen (persoenlich) mit Reitern
local ADDON, ns = ...
local resetButton   -- 0.6.180: Vorab-Deklaration (wird weiter unten belegt, schon frueher benutzt)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm

local QUALITY = { [2] = "Gruen", [3] = "Blau", [4] = "Episch" }
local TABS = {
    { key = "quick", text = "Schnellstart" },
    { key = "general", text = "Fenster & Minimap" },
    { key = "pages", text = "Seiten" },
    { key = "look", text = "Design" },
    { key = "tips", text = "Tooltips" },
    { key = "mapset", text = "Karte" },
    { key = "toasts", text = "Hinweise" },
    { key = "sound", text = "Sound" },
    { key = "char", text = "Main & Twinks" },
    { key = "status", text = "Status" },
    { key = "share", text = "Datenschutz" },
    { key = "lists", text = "Listen & Karte" },
}

local page
local compact
local function S() return ns.db.settings end

-- kleine Helfer fuer einheitliche Formulare
-- Ueberschriften merken: nach dem Aufbau bekommt jede, die noch nicht in einer Karte steht, automatisch
-- eine Glas-Karte um sich und ihren Inhalt (0.5.554 - einheitliches Design auch fuer Seiten anderer Module)
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
-- Suchindex: jede Einstellung mit Reiter (fuer die Suche oben rechts)
local INDEX = {}
local function indexAdd(label, frame, desc)
    if not page or not page.buildingTab then return end
    INDEX[#INDEX + 1] = { label = label, desc = desc, tab = page.buildingTab, frame = frame, area = page.buildingArea, settingKey = frame and frame.settingKey }
end
-- 0.6.113: auf den Sammelseiten und in den Bereichen steht die Erklaerung als graue Unterzeile direkt unter dem
-- Schalter (descInline); der Aufbau rechnet die zusaetzliche Hoehe DESC_H ein. Ganzer Text weiter beim Drueberfahren.
local DESC_H = 14
local descInline = false
-- 0.6.471: selten gebrauchte Schalter - nur sichtbar mit "Alle Optionen zeigen" (oben neben der Suche);
-- die uebrigen ruecken nach oben (compact bzw. toggleList ueberspringt sie)
-- 0.6.485: nur noch Schalter aus Schalter-Listen (Tooltips, Karte) - auf frei gebauten Seiten (Sound, Design, Fenster)
-- blieben Luecken bzw. Kaesten ueberlappten sich
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
        -- 0.6.476: der Kasten rueckt nach dem Aufbau zusammen und wird kuerzer (sonst bleibt eine Luecke)
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
    -- Erklaerung (ganz) beim Drueberfahren
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
-- alles, was im selben Rahmen unter einem Schalter mit Unterzeile steht, um DESC_H nach unten ruecken; gibt die
-- gesamte zusaetzliche Hoehe zurueck. Schalter mit noReflow (eigenes Raster) werden uebersprungen.
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
-- Allgemein
------------------------------------------------------------------------
-- Karte als Hintergrund fuer einen Abschnitt (dezent abgesetzt)
local function card(f, x, y, w, h)
    local c = CreateFrame("Frame", nil, f)
    c._isCard = true
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(w, h)
    c:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    -- 0.5.544: Glas-Karte (halbtransparent, runde Ecken) - sonst flach mit Rahmen
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
    -- Design-Rahmen (Modern rund, Future Neon, Fantasy Bronze, Classic Blizzard ...)
    if c.glass then bar:Hide()
    elseif K.ApplySkin and K.ApplySkin(c, "panel", { C.panel[1], C.panel[2], C.panel[3], 0.55 }) then bar:Hide() end
    return c
end
-- Karte mit Kopf (Symbol, Titel, Kurzbeschreibung) - 0.5.517
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
    -- leichtes Aufhellen, solange die Maus ueber der Karte ist
    c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.025)
    c.hl:Hide()
    c.hl:SetAlpha(0)
    c.hl:Show()
    c:SetScript("OnUpdate", function(self, el)
        -- 0.5.722: nur 10x pro Sekunde nachsehen (vorher jeder Frame je Karte)
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
-- 0.5.563: Karten erscheinen beim Reiterwechsel nacheinander (Hintergrund blendet ein, Symbol springt auf)
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
    -- Allgemein = das Oasis-Fenster selbst (Groesse, Start, Verhalten) + Sprache + Minimap-Knopf.
    -- Alles, was zu einem Bereich gehoert (Chat, Deathroll ...), steht unter Bereiche.
    f.noCompact = true
    local LX, SX = 14, 136     -- Beschriftung, Regler (relativ zur Seite; linke Spalte beginnt bei 0)
    local RX = 376

    -- Fenster -------------------------------------------------------------
    -- 0.5.677: Sprache als Zeile hier (vorher eigene Karte), Minimap-Karte auf den Inhalt gekuerzt
    cardH(f, 0, 0, 362, 196, "home", L["Fenster"], L["Womit Oasis startet - Groesse und Durchsicht stehen unter Aussehen"])
    rowLabel(f, L["Beim Einloggen"], LX, -60)
    f.openSeg = K.Segments(f, {
        { key = "auto", text = L["Wie zuletzt"] }, { key = "always", text = L["Oeffnen"] }, { key = "never", text = L["Zu lassen"] },
    }, function(k) S().openOnLogin = (k ~= "auto") and k or nil end)
    f.openSeg:SetPoint("TOPLEFT", SX, -58)
    indexAdd(L["Beim Einloggen"], f.openSeg, L["Oasis beim Einloggen oeffnen"])
    rowLabel(f, L["Startseite"], LX, -94)
    f.startSeg = K.Segments(f, {
        { key = "home", text = L["Dashboard"] }, { key = "last", text = L["Zuletzt offen"] },
    }, function(k) S().startPage = (k == "last") and "last" or nil end)
    f.startSeg:SetPoint("TOPLEFT", SX, -92)
    indexAdd(L["Startseite"], f.startSeg)
    local rp = K.Button(f, L["Position zuruecksetzen"], 160, 22, "ghost", function()
        if ns.ResetWindowPos then ns.ResetWindowPos() end
        K.Toast(L["Fenster"], L["Wieder in der Bildschirmmitte."], C.mint)
    end)
    rp:SetPoint("TOPLEFT", LX, -164)
    -- Sprache (auch oben neben der Krone umschaltbar)
    rowLabel(f, L["Sprache"], LX, -128)
    f.lang = K.Button(f, "", 200, 24, "ghost")
    f.lang.isDropdown = true
    f.lang:SetPoint("TOPLEFT", SX, -124)
    f.lang:SetScript("OnClick", function(self) ns.ShowLanguageMenu(self) end)
    indexAdd(L["Sprache"], f.lang)

    -- Verhalten -----------------------------------------------------------
    cardH(f, 0, -210, 362, 176, "settings", L["Verhalten"], L["Wie sich das Fenster im Spiel verhaelt"])
    f.hideCombat = toggle(f, LX, -262, "Im Kampf ausblenden", "hideInCombat", "Das Oasis-Fenster verschwindet, sobald ein Kampf beginnt (im Kampf schliesst Esc es nicht)", function() if f.reshow then f.reshow:Refresh() end end, 330)
    -- 0.5.596: danach wieder zeigen (an) oder geschlossen lassen (aus)
    f.reshow = toggle(f, LX + 20, -290, "Nach dem Kampf wieder zeigen", "combatReshow", "An: das Fenster kommt nach dem Kampf zurueck. Aus: es bleibt zu.", nil, 310)
    f.lockWin = toggle(f, LX, -318, "Fenster fixieren", "lockWindow", "Das Fenster laesst sich nicht mehr versehentlich verschieben", nil, 330)
    f.noAnim = toggle(f, LX, -346, "Animationen reduzieren", "noAnim", "Kein Einblenden und Hochzaehlen - alles erscheint sofort", nil, 330)

    -- Minimap-Knopf (mit Vorschau zum Ziehen) -----------------------------
    cardH(f, RX, 0, 362, 400, "map", L["Minimap-Knopf"], L["Knopf in der Vorschau ziehen oder unten genau einstellen"], true)
    local MX = RX + 14
    if S().minimapBadge == nil then S().minimapBadge = true end
    local function place() if ns.PlaceMinimap then ns.PlaceMinimap() end end
    -- Vorschau: runde Minimap, Knopf liegt auf dem Rand
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
    pv.hint:SetText(L["ziehen"])
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
    -- Ziehen: Winkel aus der Mausposition (5-Grad-Schritte), Minimap-Knopf wandert live mit
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
    pv:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Minimap-Knopf"], L["Klicken und ziehen: Knopf um die Minimap bewegen"] }) end)
    pv:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.mmPreview = pv
    -- Schalter rechts neben der Vorschau
    local TX = MX + 156
    f.t1 = toggle(f, TX, -62, "Anzeigen", "minimap", "Linksklick oeffnet Oasis, Rechtsklick die Einstellungen", function() ns.UpdateMinimapButton() pv:Update() end, 180)
    f.mmLock = toggle(f, TX, -92, "Fixieren", "minimapLock", "Der Knopf laesst sich nicht mehr mit der Maus verschieben", nil, 180)
    f.mmBadge = toggle(f, TX, -122, "Neuigkeiten-Zahl", "minimapBadge", "Kleine Zahl am Knopf, wenn es etwas Neues gibt", function() if ns.UpdateNotify then ns.UpdateNotify() end end, 180)
    -- Feineinstellung
    rowLabel(f, L["Position"], MX, -226)
    f.mmAngle = K.Slider(f, 170, 0, 355, 5, function() return math.floor(((S().minimapAngle or 215) % 360) / 5 + 0.5) * 5 end,
        function(v) S().minimapAngle = v place() pv:Update() end, function(v) return v .. "°" end)
    f.mmAngle:SetPoint("TOPLEFT", MX + 130, -224)
    indexAdd(L["Position"], f.mmAngle, L["Minimap-Knopf"])
    rowLabel(f, L["Abstand zum Rand"], MX, -258)
    f.mmDist = K.Slider(f, 170, -10, 25, 1, function() return S().minimapDist or 5 end,
        function(v) S().minimapDist = v place() pv:Update() end, function(v) return tostring(v) end)
    f.mmDist:SetPoint("TOPLEFT", MX + 130, -256)
    indexAdd(L["Abstand zum Rand"], f.mmDist, L["Minimap-Knopf"])
    rowLabel(f, L["Groesse"], MX, -290)
    f.mmScale = K.Slider(f, 170, 0.6, 1.6, 0.05, function() return S().minimapScale or 1 end,
        function(v) S().minimapScale = v place() pv:Update() end, function(v) return (L["%d%%"]):format(v * 100 + 0.5) end)
    f.mmScale:SetPoint("TOPLEFT", MX + 130, -288)
    indexAdd(L["Groesse"], f.mmScale, L["Minimap-Knopf"])
    note(f, L["Den Knopf kannst du auch direkt an der Minimap mit der Maus verschieben."], MX, -330, 330, C.dim)
    local mr = K.Button(f, L["Zuruecksetzen"], 120, 22, "ghost", function()
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
    f.lang:SetLabel("|T" .. ns.MEDIA .. "flags\\" .. l.flag .. ":12:16:0:0:64:64:0:64:0:48|t  " .. (auto and (L["Wie das Spiel"] .. " (" .. l.name .. ")") or l.name))
    K.SetFontSafe(f.lang.label, K.fontByKey[l.cjk or "ptsans"].path, 12, "")
end

------------------------------------------------------------------------
-- Bereiche: jeder Bereich der Navigation per Auswahl oben, mit seinen Einstellungen
------------------------------------------------------------------------
-- Einstellungen je Bereich (dieselben Schalter wie in den anderen Reitern, nur hier gesammelt)
local function updPins() if ns.Map and ns.Map.UpdateWorldPins then ns.Map.UpdateWorldPins() end end
local PAGE_OPTS = {
    chat = {
        { "Emojis im Chat anzeigen", "chatEmoji", "Aus :lol: oder <3 wird ein Bild - sehen alle mit Oasis" },
        { "Emoji-Knopf im Eingabefeld", "emojiButton", "Kleines Gesicht rechts im Chat-Eingabefeld", function() if ns.Emoji then ns.Emoji.UpdateButtons() end end },
        { "Fluestern an Offline-Charaktere dem Twink anbieten", "whisperForward", "Ist der angefluesterte Charakter offline und ein Twink desselben Spielers online, bietet Oasis an, die Nachricht dorthin zu schicken - gesendet wird erst nach deinem Klick." },
        emojiPicker = true,
    },
    radar = {
        { "Deutlicher Standard-Ton bei Online-Meldungen", "entranceLoud", "Zweiklang statt kurzem Ton, wenn die Person keinen eigenen Online-Sound gewaehlt hat", nil, true },
        inactive = true, listDark = true,
    },
    deathroll = { { "Deathroll leise wuerfeln", "drSilent", "Unter Oasis-Spielern fair per Addon statt /roll - nichts im Chat" } },
    raid = { lootQuality = true },
}
-- andere Module koennen eigene Bereichs-Einstellungen anmelden: build(frame, y) -> neue y
local PAGE_EXTRA = {}
-- Unterseiten (kein eigener Navigationspunkt) -> ihre Einstellungen erscheinen beim Hauptbereich
local AREA_CHILDREN = { insta = { "life" } }
-- Bereiche, deren Tooltip-/Kartenschalter jetzt unter Tooltips & Karte stehen: { Reiter, Knopftext }
-- Wege zu den Sammelseiten: Bereiche zeigen nur ihre eigenen Schalter, Tooltip-, Karten-, Hinweis-, Klang- und
-- Teilen-Schalter stehen gesammelt (0.6.112: Hinweise und Teilen auch nicht mehr doppelt in den Bereichen)
local LK = {
    map = { "mapset", "Karte und Minimap einstellen" }, tips = { "tips", "Tooltip-Zeilen einstellen" },
    toast = { "toasts", "Hinweise ein- und ausschalten" }, share = { "share", "Teilen und Datenschutz" },
    sound = { "sound", "Online-Ton und Anzeige" },
}
local AREA_LINKS = {
    radar = { LK.map, LK.toast, LK.sound }, map = { LK.map }, deaths = { LK.map, LK.toast },
    wants = { LK.tips, LK.toast }, crafting = { LK.tips, LK.toast }, bank = { LK.tips }, raid = { LK.tips },
    allies = { LK.tips, LK.share }, chat = { LK.tips, LK.sound }, groups = { LK.toast }, legacy = { LK.toast },
    chronicle = { LK.toast, LK.share }, polls = { LK.toast }, camp = { LK.toast, LK.share }, deathroll = { LK.toast },
    trade = { LK.share }, insta = { LK.share },
}
function ns.AddPageSettings(key, build) PAGE_EXTRA[key] = build end
-- 0.6.289: Module haengen eigene Schalter an einen bestehenden Bereich an (z. B. Discord an "chat"), egal in welcher
-- Reihenfolge geladen wird - frueher musste DiscordBridge.lua dafuer vor dieser Datei stehen
function ns.AppendPageSettings(key, build)
    local prev = PAGE_EXTRA[key]
    PAGE_EXTRA[key] = function(det, y)
        local ny = y
        if prev then ny = prev(det, y) if type(ny) ~= "number" then ny = y end end
        local ok, r = pcall(build, det, ny)
        return (ok and type(r) == "number") and r or ny
    end
end

-- Bereich "Profil": was jeder fuer sich selbst einstellt (Ueber mich, Sichtbarkeit, Belohnungen)
local function sendProfile() if ns.Radar and ns.Radar.SendHello then ns.After(0.5, function() pcall(ns.Radar.SendHello) end) end end
-- Auswahlknopf mit Bild-Vorschau; Klick oeffnet Kacheln (freigeschaltet + gesperrt mit Rang)
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
        self.label:SetText(r and short(r) or ("|cff999999" .. L["Standard"] .. "|r"))
    end
    b:SetScript("OnClick", function(self)
        local lvl = ns.Rank and ns.Rank.Mine() and ns.Rank.Mine().level or 1
        local cur = get()
        local items = {}
        do
            local icon, col, round = rewardVisual(kind, nil)
            if kind == "theme" then col = ns.Admin and ns.Admin.GuildAccentColor() or C.accent end
            items[1] = { key = false, text = L["Standard"], icon = icon, color = col, round = round, checked = cur == nil }
        end
        for _, r in ipairs(RW and RW.LIST or {}) do
            if r.kind == kind then
                local icon, col, round = rewardVisual(kind, r)
                local key = r.key
                items[#items + 1] = { key = key, text = short(r), icon = icon, color = col, round = round, checked = cur == key,
                    locked = lvl < r.lvl and (L["Rang %d"]):format(r.lvl) or nil,
                    onEnter = function(tile)
                        if kind == "sound" and ns.Sound then ns.Sound.PlayChoice(key) end
                        K.ShowTip(tile, { L[r.name], L[r.desc or ""], lvl < r.lvl and ("|cffe8b44a" .. (L["Ab Oasis-Rang %d"]):format(r.lvl) .. "|r") or nil })
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
-- Bereich "Abzeichen": Hinweise, Chronik, Gildenchat, Vitrine (bis zu 4 Lieblings-Abzeichen auf der Profilkarte)
ns.AddPageSettings("badges", function(det, y)
    local s = S()
    local B = ns.Badges
    det.t[#det.t + 1] = (function()
        local t = K.Toggle(det, L["Hinweis bei neuem Abzeichen"], function()
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
    det.t[#det.t + 1] = toggle(det, 14, y, "Neue Abzeichen in der Chronik eintragen", "badgeChronicle", "Die Gilde sieht in der Chronik, was du erreicht hast", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Gold-Abzeichen im Gildenchat feiern", "badgeAnnounce", "Schreibt bei Gold-Abzeichen und Gilden-Titeln eine kurze Zeile in den Gildenchat", nil, 600)
    y = y - 40

    -- Vitrine
    rowLabel(det, "|cffe8b44a" .. L["Deine Vitrine"] .. "|r", 14, y)
    note(det, L["Diese Abzeichen zeigt deine Profilkarte zuerst - bei dir und bei der Gilde."], 150, y - 2, 450, C.dim)
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
            K.ShowTip(self, b and { B.Label(id, tierOf(id) or 1), L["Klick: anderes Abzeichen waehlen"] } or { L["Freier Platz"], L["Klick: Abzeichen waehlen"] })
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slot:SetScript("OnClick", function(self)
            local cur = (S().badgeShowcase or {})[i]
            local items = { { key = false, text = L["Leer"], icon = nil, color = { 0.25, 0.25, 0.28 }, round = true, checked = cur == nil } }
            for _, e in ipairs(mineList()) do
                local c = B.Color(e.tier)
                items[#items + 1] = { key = e.b.id, text = L[e.b.name], icon = e.b.wow or e.b.icon, color = e.b.wow and { 1, 1, 1 } or c,
                    checked = cur == e.b.id,
                    onEnter = function(tile) K.ShowTip(tile, { B.Label(e.b.id, e.tier), L[e.b.desc or ""] }) end }
            end
            if #items == 1 then items[2] = { key = false, text = L["Noch keine Abzeichen"], color = { 0.3, 0.3, 0.3 }, round = true, locked = " " } end
            K.TilePicker(self, (L["Vitrine - Platz %d"]):format(i), items, function(k)
                local sc = S().badgeShowcase or {}
                -- dasselbe Abzeichen nicht doppelt
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

-- Bereich "Chat": Tippen-Anzeige, @-Vorschlaege, Erwaehnungs-Ton, Emoji-Groesse, Stummgeschaltete
ns.AddPageSettings("chat", function(det, y)
    -- Privat-Reiter (0.5.857)
    do
        local st = S()
        if st.wlGroupAlts == nil then st.wlGroupAlts = true end
        if st.wlOnlineBg == nil then st.wlOnlineBg = true end
        local function rf() ns.RefreshPage("chat") end
        det.t[#det.t + 1] = toggle(det, 14, y, "Privat: Twink-Gespraeche unter dem Main", "wlGroupAlts", "Gespraeche mit Twinks haengen aufklappbar unter dem Gespraech mit ihrem Main", rf, 600)
        y = y - 30
        det.t[#det.t + 1] = toggle(det, 14, y, "Privat: wer online ist, gruen hinterlegen", "wlOnlineBg", "Gruener Hintergrund fuer Gespraechspartner, die gerade online sind", rf, 600)
        y = y - 36
    end
    local s = S()
    if s.chatTyping == nil then s.chatTyping = true end
    if s.chatMentionSuggest == nil then s.chatMentionSuggest = true end
    if s.chatMentionSound == nil then s.chatMentionSound = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Zeigen, wenn jemand schreibt", "chatTyping", "Auch die anderen sehen dann, wenn du gerade schreibst", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "@Namen-Vorschlaege im normalen Chat", "chatMentionSuggest", "Beim Tippen von @ schlaegt Oasis Gildenmitglieder vor (Tab vervollstaendigt)", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Ton bei @Erwaehnung", "chatMentionSound", "Kurzer Ping, wenn dich jemand im Gildenchat erwaehnt", nil, 600)
    y = y - 38
    rowLabel(det, L["Emoji-Groesse im Chat"], 14, y - 2)
    det.esize = K.Slider(det, 180, 0, 32, 2, function() return tonumber(S().emojiChatSize) or 0 end,
        function(v) S().emojiChatSize = v if ns.GuildChat and ns.GuildChat.ClearRenderCache then ns.GuildChat.ClearRenderCache() end end,
        function(v) return v == 0 and L["automatisch"] or (v .. " px") end,
        function() if ns.GuildChat and ns.GuildChat.ApplyLook then ns.GuildChat.ApplyLook() end end)
    det.esize:SetPoint("TOPLEFT", 184, y)
    y = y - 40
    -- Darstellung: Schrift, Abstaende, Farben (gleiche Regler wie am Zahnrad im Chat)
    if ns.GuildChat and ns.GuildChat.BuildLook then
        local ok, ny = pcall(ns.GuildChat.BuildLook, det, y, { x = 14, width = 600 })
        if ok and type(ny) == "number" then y = ny - 6 end
    end
    -- Stummgeschaltete Personen
    rowLabel(det, "|cffe8b44a" .. L["Stummgeschaltet"] .. "|r", 14, y)
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
            self.muteEmpty:SetText(L["Niemand. Stummschalten geht per Rechtsklick auf einen Namen im Gildenchat."])
        end
        self.muteEmpty:SetShown(#names == 0)
    end
    det:UpdateMuted()
    return y - 36
end)

-- Bereich "Mitglieder": Hinweise, Neu-Markierung, Spielzeit mitschreiben
ns.AddPageSettings("radar", function(det, y)
    local s = S()
    if s.trackPlay == nil then s.trackPlay = true end
    rowLabel(det, L["Als neu markieren"], 14, y - 2)
    det.newDays = K.Slider(det, 180, 3, 30, 1, function() return S().newDays or 14 end,
        function(v) S().newDays = v end, function(v) return (L["%d Tg"]):format(v) end)
    det.newDays:SetPoint("TOPLEFT", 184, y)
    y = y - 26
    note(det, L["So lange steht ein gruenes NEU vor neuen Mitgliedern."], 14, y, 600, C.dim)
    y = y - 30
    det.t[#det.t + 1] = toggle(det, 14, y, "Spielzeiten mitschreiben", "trackPlay", "Fuer 'meist online um' und das Level-Tempo in der Mitgliederliste - nur bei dir gespeichert", nil, 600)
    return y - 36
end)

-- Bereich "Kampf-Rangliste": Kampflog-Datei mitschreiben (Standard an) - Grundlage fuer den Crit-Import
ns.AddPageSettings("fight", function(det, y)
    local s = S()
    if s.cbAutoLog == nil then s.cbAutoLog = ns.GuildPack and true or false end   -- oeffentliche Version: aus
    -- die Logdatei nuetzt nur mit dem Crit-Import ueber OasisSync, und der wird nicht verteilt - nur mit Gildenmodul
    if ns.GuildPack then
        det.t[#det.t + 1] = toggle(det, 14, y, "Kampflog mitschreiben (/combatlog)", "cbAutoLog",
            "Schaltet beim Einloggen das Kampflog ein (wie /combatlog). OasisSync liest daraus die Crits aus Gruppen und Dungeons.",
            function() if ns.CombatBoard and ns.CombatBoard.ApplyAutoLog then ns.CombatBoard.ApplyAutoLog() end end, 600)
        y = y - 30
    end
    if s.cbLiveCrit == nil then s.cbLiveCrit = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Crits beim Kampf allein automatisch zaehlen", "cbLiveCrit",
        "Ohne Gruppe und ausserhalb von Dungeons zaehlt jeder kritische Treffer auf dein Ziel sofort fuer Hoechster Crit - ohne Logdatei.", nil, 600)
    y = y - 30
    if s.cbGroupCrit == nil then s.cbGroupCrit = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Crits in Gruppe und Dungeon schaetzen", "cbGroupCrit",
        "WoW sagt Addons in der Gruppe nicht, wer getroffen hat. Oasis zaehlt einen kritischen Treffer nur, wenn er direkt auf deinen eigenen Angriff folgt und nach dem Kampf zur Schadensanzeige passt. In der Rangliste als geschaetzt markiert.", nil, 600)
    return y - 36
end)

-- ==== Bereiche Zusammen spielen / Raid / Handel / Gilde & Spass ====
-- [A]
-- Gruppe A (Zusammen spielen): groups, social, allies, dungeons, buffs
-- Standard = bisheriges Verhalten (nil -> wie bisher). Standard-AN-Schalter werden hier auf true vorbelegt.

-- Bereich "Gruppen"
ns.AddPageSettings("groups", function(det, y)
    local s = S()
    if s.lfgAccept == nil then s.lfgAccept = true end
    if s.lfgAuto == nil then s.lfgAuto = true end
    local function refreshGroups() ns.RefreshPage("groups") end
    rowLabel(det, "|cffe8b44a" .. L["Hinweise"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Auch Suchen ohne Platz fuer meine Rolle melden", "lfgAllRoles", "Sonst kommt der Hinweis nur, wenn ein Platz fuer eine deiner Rollen frei ist", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweise auch in Dungeons und Schlachtfeldern", "lfgInInstance", "Sonst bleiben neue Gruppensuchen in Instanzen still", nil, 600)
    y = y - 40
    rowLabel(det, "|cffe8b44a" .. L["Automatik"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Einladung zu angefragten Gruppen automatisch annehmen", "lfgAccept", "Nur von Leitern, bei denen du ueber Oasis angefragt hast", refreshGroups, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Bei eigener Suche automatisch einladen", "lfgAuto", "Standard fuer neue Suchen: Anfragende werden sofort eingeladen statt erst nach Klick", refreshGroups, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Gemeinsam questen"
ns.AddPageSettings("social", function(det, y)
    local s = S()
    if s.socialQuestHint == nil then s.socialQuestHint = true end
    local function refreshSocial() ns.RefreshPage("social") end
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweis, wenn jemand dieselbe Quest annimmt", "socialQuestHint", "Klick auf den Hinweis laedt die Person in deine Gruppe ein", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Nur Gruppenquests beruecksichtigen", "socialGroupOnly", "Liste und Hinweise zeigen nur Quests, die fuer Gruppen gedacht sind", refreshSocial, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Fertige Quests in der Liste zeigen", "socialShowDone", "Auch Quests, die du nur noch abgeben musst (wie der Knopf Fertige auf der Seite)", refreshSocial, 600)
    y = y - 32
    note(det, L["Ob andere deine Quests sehen, stellst du unter Profil ein (Meine Quests teilen)."], 14, y, 600, C.dim)
    y = y - 28
    return y - 10
end)

-- Bereich "Spielerbuch" (shareRep steht schon oben aus PAGE_OPTS)
ns.AddPageSettings("allies", function(det, y)
    local s = S()
    for _, k in ipairs({ "allyRemember", "allyWarnWhisper", "allyWarnGroup", "allyWarnGuild", "allyTooltip" }) do
        if s[k] == nil then s[k] = true end
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Mitspieler aus Gruppen merken", "allyRemember", "Spieler ausserhalb der Gilde, mit denen du in einer Gruppe warst, landen im Spielerbuch - nur bei dir gespeichert", nil, 600)
    y = y - 32
    y = y - 8
    rowLabel(det, "|cffe8b44a" .. L["Warnungen"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Warnen, wenn ein schlecht Bewerteter in die Gruppe kommt", "allyWarnGroup", nil, nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Warnen, wenn ein schlecht Bewerteter dir schreibt", "allyWarnWhisper", nil, nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Auch nach Bewertungen der Gilde warnen", "allyWarnGuild", "Aus: nur bei Spielern, die DU als schlecht markiert hast", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Dungeons"
ns.AddPageSettings("dungeons", function(det, y)
    local s = S()
    for _, k in ipairs({ "dgForYou", "dgDimUnfit", "dgMarkers", "dgPreload" }) do
        if s[k] == nil then s[k] = true end
    end
    local function refreshDg() ns.RefreshPage("dungeons") end
    rowLabel(det, L["Start-Filter"], 14, y - 2)
    det.dgFilter = K.Segments(det, {
        { key = "auto", text = L["Automatisch"] },
        { key = "mine", text = L["Fuer mich"] },
        { key = "open", text = L["Alle offenen"] },
        { key = "all", text = L["Alle"] },
    }, function(k)
        S().dgFilter = (k ~= "auto") and k or nil
        if ns.Dungeons and ns.Dungeons.ResetFilter then ns.Dungeons.ResetFilter() end
    end)
    det.dgFilter:SetPoint("TOPLEFT", 184, y)
    det.dgFilter:Select(S().dgFilter or "auto")
    det.refreshers = det.refreshers or {}
    table.insert(det.refreshers, function() det.dgFilter:Select(S().dgFilter or "auto") end)
    y = y - 30
    note(det, L["Automatisch: passende Dungeons fuer dein Level, sonst alle offenen."], 14, y, 600, C.dim)
    y = y - 34
    rowLabel(det, "|cffe8b44a" .. L["Beute-Liste"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Passende Beute als fuer dich markieren", "dgForYou", "Gruener Hinweis bei Gegenstaenden mit Werten fuer deine Klasse", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Unpassende Beute abdunkeln", "dgDimUnfit", "Ruestung und Waffen, die deine Klasse nicht tragen kann, werden blasser", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Gesucht, Gildenbank und Besitz anzeigen", "dgMarkers", "Zusatz unter jedem Gegenstand: wer ihn sucht, wie viele in der Gildenbank liegen, ob du ihn hast", refreshDg, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Beute im Hintergrund vorladen", "dgPreload", "Nach dem Einloggen werden alle Dungeon-Beutelisten nach und nach gelesen (fuer Tooltips) - wirkt ab dem naechsten Login", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Buff-Monitor"
ns.AddPageSettings("buffs", function(det, y)
    local s = S()
    if s.buffCons == nil then s.buffCons = true end
    local function upd()
        if ns.BuffMonitor and ns.BuffMonitor.Update then ns.BuffMonitor.Update() end
        ns.RefreshPage("buffs")
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Beim Gruppenbeitritt automatisch einblenden", "buffAuto", "Das schwebende Buff-Fenster geht auf, sobald du in eine Gruppe kommst", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Beim Verlassen der Gruppe ausblenden", "buffAutoHide", "Allein ist das Fenster weg - in der naechsten Gruppe kommt es wieder", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Fenster festsetzen", "buffLock", "Das schwebende Fenster laesst sich nicht mehr versehentlich verschieben", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Flaeschchen, Elixiere und Essen pruefen", "buffCons", "Aus: nur Klassen-Buffs (Ausdauer, Intelligenz, Segen ...)", upd, 600)
    y = y - 32
    return y - 10
end)
-- [B]
ns.AddPageSettings("raid", function(det, y)
    for _, k in ipairs({ "raidReminder", "raidNewEventToast", "raidWinToast", "lootHelper", "raidPointsPrompt" }) do
        if S()[k] == nil then S()[k] = true end
    end
    rowLabel(det, "|cffe8b44a" .. L["Hinweise"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Erinnerung 15 Min vor meinen Raids", "raidReminder", "Kurzer Hinweis, wenn ein Termin mit deiner Zusage (oder deiner eigener) gleich beginnt", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweis bei neuen Raidterminen", "raidNewEventToast", "Zeigt einen Hinweis, sobald jemand aus der Gilde einen neuen Termin anlegt", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweis, wenn ich ein Item bekomme", "raidWinToast", "Meldung bei der Oasis-Verteilung, wenn das Item an dich geht", nil, 600)
    y = y - 32
    rowLabel(det, "|cffe8b44a" .. L["Als Anfuehrer"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Verteil-Helfer am Beutefenster", "lootHelper", "Als Anfuehrer erscheint neben dem Beutefenster eine Liste zum Verteilen per Oasis", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Raid-Punkte beim Betreten anbieten", "raidPointsPrompt", "Als Offizier fragt Oasis beim Betreten einer Raid-Instanz, ob die Punkte starten sollen", nil, 600)
    y = y - 32
    return y - 10
end)

-- [C]
-- Gruppe C (Handel): Handwerks-Boerse, Markt, Wunschliste, Gildenbank

-- Bereich "Handwerks-Boerse": Hinweise, Zaehler, Tooltip
ns.AddPageSettings("crafting", function(det, y)
    local s = S()
    if s.craftStatusToasts == nil then s.craftStatusToasts = true end
    if s.craftBadge == nil then s.craftBadge = true end
    if s.tipCrafters == nil then s.tipCrafters = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweise zu meinen Auftraegen", "craftStatusToasts", "Angenommen, fertig, abgelehnt oder zurueckgegeben - Meldung bei Aenderungen deiner eigenen Bestellungen", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Zahl offener Auftraege im Menue", "craftBadge", "Kleine Zahl am Menuepunkt Handwerks-Boerse fuer Auftraege, die du herstellen koenntest",
        function() if ns.Crafting and ns.Crafting.UpdateBadge then ns.Crafting.UpdateBadge() end end, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Markt": Wunschliste-Alarm, Preisabfragen, Handelsbilanz (gleiche Schalter wie auf der Markt-Seite)
ns.AddPageSettings("trade", function(det, y)
    local s = S()
    if s.wantAlarm == nil then s.wantAlarm = true end
    if s.priceAnswer == nil then s.priceAnswer = true end
    local function upd() ns.RefreshPage("trade") end
    det.t[#det.t + 1] = toggle(det, 14, y, "Wunschliste-Alarm", "wantAlarm", "Liegt etwas von deiner Wunschliste guenstig im AH, bekommst du einen Hinweis - auch wenn ein anderer gescannt hat.", upd, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Preisabfragen beantworten", "priceAnswer", "Schreibt jemand 'pc [Item]' in den Gildenchat, antwortet genau ein Oasis-Nutzer mit Preis und 7-Tage-Tief.", upd, 600)
    y = y - 32
    if _G.MidasDB then
        if s.midasAutoScan == nil then s.midasAutoScan = true end
        det.t[#det.t + 1] = toggle(det, 14, y, "Midas scannt automatisch", "midasAutoScan", "Beim Oeffnen des Auktionshauses startet Midas den Scan im Hintergrund (hoechstens alle 15 Minuten, Server-Sperre).",
            function() upd() if ns.ApplyMidasAutoScan then ns.ApplyMidasAutoScan() end end, 600)
        y = y - 32
    end
    return y - 10
end)

-- Bereich "Wunschliste": Hinweise, Zaehler, Tooltip, Item-Vorschlaege
ns.AddPageSettings("wants", function(det, y)
    local s = S()
    for _, k in ipairs({ "wantsLootHint", "wantsBagHint", "wantsBadge", "tipOasis", "tipWanted", "itemSuggest", "wantsDungeonHint", "wantsGotHint", "tipReagent" }) do
        if s[k] == nil then s[k] = true end
    end
    det.t[#det.t + 1] = toggle(det, 14, y, "Beim Looten melden, wenn jemand das sucht", "wantsLootHint", "Hebst du ein Item auf, das ein Gildenmitglied sucht, kommt ein Hinweis zum Bescheid sagen", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Melden, wenn ich Gesuchtes in den Taschen habe", "wantsBagHint", "Neuer Wunsch eines anderen und du hast das Item dabei", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Im Dungeon zeigen, welche Wunsch-Items hier droppen", "wantsDungeonHint", "Beim Betreten: deine Wunsch-Items und die deiner Gilden-Mitspieler, die in diesem Dungeon droppen", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Ziel erreicht melden", "wantsGotHint", "Lootest du ein Item von deiner Wunschliste, kommt ein Hinweis (Klick hakt es ab)", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Zahl im Menue, wenn ich helfen kann", "wantsBadge", "Kleine Zahl am Menuepunkt Wunschliste",
        function() if ns.Wants and ns.Wants.UpdateBadge then ns.Wants.UpdateBadge() end end, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Item-Vorschlaege beim Tippen", "itemSuggest", "Beim Eintippen eines Item-Namens schlaegt Oasis passende Items vor", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Gildenbank": Einlesen/Teilen, Tooltip, Start-Filter des Protokolls
ns.AddPageSettings("bank", function(det, y)
    local s = S()
    if s.bankShareScan == nil then s.bankShareScan = true end
    if s.tipBank == nil then s.tipBank = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Gildenbank fuer die Gilde einlesen", "bankShareScan", "Oeffnest du den Gildentresor, liest Oasis Faecher, Gold und Protokoll und teilt sie mit der Gilde", nil, 600)
    y = y - 38
    rowLabel(det, L["Protokoll zeigt zuerst"], 14, y - 2)
    det.bankLog = K.Segments(det, { { key = "all", text = L["Alles"] }, { key = "items", text = L["Items"] },
        { key = "gold", text = L["Gold"] }, { key = "mine", text = L["Meine"] } }, function(k)
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
-- Gruppe D: Chronik, Umfragen, Lagerfeuer, Deathroll, Friedhof, Legacy, Karte

-- Bereich "Chronik": Hinweise, Level-Hinweise, Legacy-Posts
ns.AddPageSettings("chronicle", function(det, y)
    local s = S()
    if s.chrToastLevels == nil then s.chrToastLevels = true end
    if s.chrPostLegacy == nil then s.chrPostLegacy = true end
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Level-Aufstiege anderer melden", "chrToastLevels", "Aus: keine Hinweise mehr, wenn jemand ein Level erreicht - Bosse und Legacy bleiben", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Geschaffte Legacy-Challenges im Gildenchat posten", "chrPostLegacy", "Gilt nur, wenn Meilensteine posten an ist - Aus: nur Level werden gepostet", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Umfragen": neue Umfrage, Ergebnis, Zaehler
ns.AddPageSettings("polls", function(det, y)
    local s = S()
    if s.pollEndToast == nil then s.pollEndToast = true end
    if s.pollBadge == nil then s.pollBadge = true end
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Ergebnis melden, wenn eine Umfrage endet", "pollEndToast", "Nur fuer Umfragen, die du gestartet oder bei denen du abgestimmt hast", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Offene Umfragen in der Navigation zaehlen", "pollBadge", "Zahl am Menuepunkt fuer Umfragen, bei denen du noch nicht abgestimmt hast",
        function() if ns.Polls and ns.Polls.UpdateBadge then ns.Polls.UpdateBadge() end end, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Gildenziele" (0.5.481)
ns.AddPageSettings("goals", function(det, y)
    if S().ggHint == nil then S().ggHint = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Hinweis bei neuen Gildenzielen", "ggHint", "Ein Hinweis erscheint, sobald jemand ein Gildenziel anlegt", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Taschen & Twinks": Bank-Platzhalter (0.5.481)
ns.AddPageSettings("bags", function(det, y)
    if S().bankGhosts == nil then S().bankGhosts = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Bank-Platzhalter", "bankGhosts", "Leiste ueber der Bank: Belegung merken, leere Plaetze zeigen ein blasses Symbol (Oasis verschiebt nichts)",
        function() if ns.BankSlots then ns.BankSlots.Refresh() end end, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Lagerfeuer": Hinweise anderer, nur eigenes Gebiet, eigene Bestaetigung
ns.AddPageSettings("camp", function(det, y)
    local s = S()
    if s.campOwnToast == nil then s.campOwnToast = true end
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Nur Lagerfeuer in meinem Gebiet melden", "campZoneOnly", "Hinweise nur, wenn das Feuer in deiner aktuellen Zone brennt - auf der Karte siehst du weiter alle", nil, 600)
    y = y - 32
    det.t[#det.t + 1] = toggle(det, 14, y, "Bestaetigung beim eigenen Lagerfeuer", "campOwnToast", "Kurzer Hinweis, dass die Gilde dein Feuer sieht", nil, 600)
    y = y - 32
    if s.campAuto == nil then s.campAuto = true end
    return y - 10
end)

-- Bereich "Deathroll": Herausforderungen, offene Einladungen, Spielzug
ns.AddPageSettings("deathroll", function(det, y)
    local s = S()
    if s.drOpenInvites == nil then s.drOpenInvites = true end
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Offene Spiel-Einladungen der Gilde melden", "drOpenInvites", "Aus: Wer in der Warteschlange einen Gegner sucht, erscheint nur noch auf der Deathroll-Seite", nil, 600)
    y = y - 32
    -- 0.6.213: gildenuebergreifende Lobby ueber versteckte Kanaele (Standard an)
    if s.drNet == nil then s.drNet = true end
    det.t[#det.t + 1] = toggle(det, 14, y, "Gegner auch ausserhalb der Gilde finden", "drNet", "Versteckter Kanal je Einsatzhoehe - Suchende anderer Gilden erscheinen still in der Liste", function(v)
        local DR = ns.Deathroll
        if DR then if v then DR.NetJoin(DR.inQueue and DR.inQueue.start or 100) else DR.NetLeave() end end
    end, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Friedhof": Todes-Hinweise, Todesursache
ns.AddPageSettings("deaths", function(det, y)
    local s = S()
    if s.deathKiller == nil then s.deathKiller = true end
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Todesursache im Hinweis zeigen", "deathKiller", "Aus: der Hinweis nennt nur Name und Ort", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Legacy": Mitstreiter-Suchen
ns.AddPageSettings("legacy", function(det, y)
    rowLabel(det, "|cffe8b44a" .. L["Persoenlich"] .. "|r", 14, y)
    y = y - 28
    det.t[#det.t + 1] = toggle(det, 14, y, "Auch Suchen fuer bereits geschaffte Challenges melden", "legacyLfgDone", "Normal meldet Oasis nur Suchen, die du selbst noch offen hast", nil, 600)
    y = y - 32
    return y - 10
end)

-- Bereich "Karte & Radar": weitere Kartenebenen, Sendetakt
-- 0.6.113: Karte zweispaltig und nach Themen (Weltkarte, Sammelkarte, Symbole, Senden); Erklaerung als Unterzeile
ns.AddPageSettings("map", function(det, y)
    det.t, det.refreshers = det.t or {}, det.refreshers or {}
    local function upd() if ns.Map then ns.Map.UpdateWorldPins() end end
    local function gupd() if ns.Gather then if ns.Gather.Refresh then ns.Gather.Refresh() else pcall(ns.Gather.DrawWorld) pcall(ns.Gather.DrawMinimap) end end end
    local function symUpd()
        if ns.Gather and ns.Gather.Refresh then ns.Gather.Refresh() end
        if ns.Map then pcall(ns.Map.UpdateMinimap) pcall(ns.Map.UpdateWorldPins) end
    end
    local function xupd() symUpd() if ns.MapExtras then ns.MapExtras.Redraw() end end
    -- zwei Spalten; Reihe so hoch wie ihr hoechster Schalter (mit oder ohne Unterzeile)
    local function grid(list)
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

    head("Weltkarte")
    if S().lfgPins == nil then S().lfgPins = true end
    grid({
        { "Levelbereiche auf der Weltkarte", "mapLevels", "Zeigt die Levelspanne der Gebiete", upd },
        { "Todesorte auf der Weltkarte", "mapDeaths", "Totenkoepfe der Gilde zusaetzlich in der Kartenebene", upd },
        { "Gruppensuchen am Dungeon-Eingang", "lfgPins", "Wer Mitstreiter sucht, erscheint am Eingang des Dungeons", symUpd },
        { "Marker und Notizen", "mapMarkers", "Treffpunkte, Warnungen und Notizen auf Weltkarte und Minimap", xupd, true },
        { "Dungeon-Eingaenge", "mapDungeons", "Eingaenge mit Levelspanne und Gildenmitgliedern im Levelbereich", xupd, true },
        { "Gefahrenzonen", "mapDanger", "Roter Schimmer, wo mehrere aus der Gilde gestorben sind (7 Tage)", xupd },
        { "Haendler, Reparatur, Briefkaesten und Flugpunkte", "mapPoi", "Orte, die jemand aus der Gilde schon besucht hat", xupd, true },
        { "Questgeber der Dungeon-Quests", "mapQuestGivers", "Wo Dungeon-Quests in der offenen Welt beginnen", xupd },
        { "Eigene Laufspur", "mapTrails", "Dein Weg der letzten 5 Minuten als duenne Linie", xupd },
        { "Laufspuren anderer Spieler", "mapTrailsGuild", "Die Wege der Gildenmitglieder (nur mit Eigene Laufspur)", xupd },
        { "Lagerfeuer auf der Karte", "mapCamp", "Gemeldete Lagerfeuer der Gilde auf Weltkarte und Minimap", function() if ns.Map then pcall(ns.Map.UpdateWorldPins) pcall(ns.Map.UpdateMinimap) end end },
        { "Koordinaten an der Minimap", "mmCoords", "Eigene Position und Entfernung zum Ziel", xupd },
        { "Layer-Anfragen aus der Gilde annehmen", "layerAsk", "Hinweis, wenn jemand ueber deine Gruppe auf deinen Layer will", xupd, true },
    })

    head("Gilden-Sammelkarte")
    if S().gatherFresh == nil then S().gatherFresh = true end
    if S().gatherHarvest == nil then S().gatherHarvest = true end
    grid({
        { "Sammelkarte auf der Weltkarte ausblenden", "gatherWorldOff", "Fundorte, die jemand aus der Gilde gefunden hat", gupd },
        { "Sammelkarte auf der Minimap ausblenden", "gatherMiniOff", "Fundorte, die jemand aus der Gilde gefunden hat", gupd },
        { "Kraeuter ausblenden", "gatherOff_herb", nil, gupd },
        { "Erz ausblenden", "gatherOff_ore", nil, gupd },
        { "Schaetze ausblenden", "gatherOff_treasure", nil, gupd },
        { "Angelstellen ausblenden", "gatherOff_fish", nil, gupd },
        { "Schlosskisten ausblenden", "gatherOff_lock", nil, gupd },
        { "Sammelpunkte ohne Kreisrahmen", "gatherRingOff", "Nur das Symbol, ohne dunkle Scheibe und Ring", symUpd },
        { "Fundorte nach Frische einfaerben", "gatherFresh", "Frische Stellen kraeftig, alte verblassen", gupd },
        { "Gerade abgeerntete Stellen grau zeigen", "gatherHarvest", "Wenn dort in den letzten 5 Minuten gesammelt wurde", gupd },
        { "Sammelroute", "gatherRoute", "Rundstrecke durch die Fundorte, Pfeil an der Minimap zum naechsten", symUpd },
    })
    local sorts
    sorts = K.Button(det, L["Einzelne Sorten filtern"], 226, 24, nil, function()
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
        if #items == 0 then items[1] = { text = L["Noch keine benannten Fundorte."], disabled = true } end
        K.ShowMenu(sorts, items, L["Einzelne Sorten filtern"])
    end)
    sorts:SetPoint("TOPLEFT", 14, y)
    y = y - 36

    head("Symbole anpassen")
    local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
    local SYM = {   -- { Text, Schluessel, von, bis, Schritt, Standard, Format }
        { "Sammelpunkte Minimap: Groesse", "gatherMiniScale", 0.6, 2, 0.05, 1 },
        { "Sammelpunkte Minimap: Deckkraft", "gatherMiniAlpha", 0.2, 1, 0.05, 1 },
        { "Sammelpunkte Weltkarte: Groesse", "gatherWorldScale", 0.6, 2.5, 0.05, 1 },
        { "Sammelpunkte Weltkarte: Deckkraft", "gatherWorldAlpha", 0.2, 1, 0.05, 1 },
        { "Gilden-Punkte Minimap: Groesse", "mmDotScale", 0.6, 2, 0.05, 1 },
        { "Gilden-Punkte Minimap: Deckkraft", "mmDotAlpha", 0.2, 1, 0.05, 1 },
        { "Punkte auf der Weltkarte: Groesse", "mapPinScale", 0.6, 2, 0.05, 1 },
        { "Nur Fundorte zeigen ab", "gatherMinCount", 1, 10, 1, 1, function(v) return (L["%d Funden"]):format(v) end },
    }
    for i, d in ipairs(SYM) do
        local cx = 14 + ((i - 1) % 2) * 370
        rowLabel(det, L[d[1]], cx, y)
        local sl = K.Slider(det, 200, d[3], d[4], d[5], function() return S()[d[2]] or d[6] end,
            function(v) S()[d[2]] = v symUpd() end, d[7] or pct)
        sl:SetPoint("TOPLEFT", cx, y - 22)
        table.insert(det.refreshers, function() sl:Refresh() end)
        if i % 2 == 0 or i == #SYM then y = y - 54 end
    end
    local reset = K.Button(det, L["Symbole zuruecksetzen"], 226, 24, nil, function()
        for _, d in ipairs(SYM) do S()[d[2]] = nil end
        S().gatherRingOff, S().gatherHide = nil, nil
        symUpd()
        for _, fn in ipairs(det.refreshers) do pcall(fn) end
        for _, t in ipairs(det.t) do if t.Refresh then pcall(t.Refresh, t) end end
    end)
    reset:SetPoint("TOPLEFT", 14, y)
    y = y - 40

    head("Senden")
    rowLabel(det, L["Position senden alle"], 14, y)
    det.mapInterval = K.Slider(det, 160, 5, 30, 1, function() return S().mapInterval or 8 end,
        function(v) S().mapInterval = v if ns.Map then ns.Map.nextSend = nil end end,
        function(v) return (L["%d Sek."]):format(v) end)
    det.mapInterval:SetPoint("TOPLEFT", 184, y + 2)
    table.insert(det.refreshers, function() det.mapInterval:Refresh() end)
    y = y - 30
    note(det, L["Seltener senden = weniger Datenverkehr, die Gilde sieht dich aber ruckeliger."], 14, y, 600, C.dim)
    y = y - 22
    return y - 10
end)
ns.AddPageSettings("insta", function(det, y)
    local s = S()
    if s.profShareQuests == nil then s.profShareQuests = true end
    if s.profShareGear == nil then s.profShareGear = true end
    -- Ueber mich
    rowLabel(det, L["Ueber mich"], 14, y - 2)
    local bio = K.Input(det, 330, L["Ein Satz ueber dich, z.B. Immer fuer Dungeons zu haben"])
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
    note(det, L["Steht auf deiner Profilkarte, die die Gilde sieht."], 164, y, 330, C.dim)
    y = y - 30
    -- Sichtbarkeit
    det.t[#det.t + 1] = toggle(det, 14, y, "Oasis-XP im Bild anzeigen", "xpFloat", "Neue Oasis-Erfahrung steigt kurz als +XP in der Bildmitte auf", nil, 600)
    y = y - 40
    -- Belohnungen aus dem Oasis-Rang
    rowLabel(det, "|cffe8b44a" .. L["Deine Belohnungen"] .. "|r", 14, y)
    y = y - 30
    det.rw = {}
    det.rw[1] = rewardPicker(det, "sound", 14, y, "Fanfare beim Rangaufstieg", function() return S().rankSound end,
        function(k) S().rankSound = k if k and ns.Sound then ns.Sound.PlayChoice(k) end end)
    y = y - 36
    det.rw[2] = rewardPicker(det, "dice", 14, y, "Deathroll-Wuerfel", function() return S().diceDesign end,
        function(k) S().diceDesign = k end)
    y = y - 36
    det.rw[3] = rewardPicker(det, "theme", 14, y, "Rang-Farbe", function()
            local acc = S().accent
            for _, r in ipairs(ns.Rewards and ns.Rewards.LIST or {}) do if r.kind == "theme" and r.hex == acc then return r.key end end
        end,
        function(k)
            local r = k and ns.Rewards.byKey["theme:" .. k]
            S().accent = r and r.hex or ""
            if ns.Admin then ns.Admin.ApplyBrand(true) end
        end)
    y = y - 36
    note(det, L["Neue Belohnungen schaltest du mit deinem Oasis-Rang frei."], 14, y, 600, C.dim)
    return y - 20
end)

-- Funktionskatalog nach dem Nutzen fuer den Spieler, unabhaengig von der Hauptnavigation.
local AREA_SCOPE = {
    home = "personal", discover = "personal", life = "personal", bags = "personal",
    badges = "personal", legacy = "personal", rank = "personal", fight = "personal",
    questitems = "personal", dungeons = "personal",
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

-- Bereiche in der Reihenfolge der Navigation (Gruppen), Rest am Ende
local function pageGroups(scope)
    local out, seen = {}, {}
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        local items = {}
        for _, k in ipairs(g.pages) do
            local d = ns.PageDef(k)
            -- Seiten, die es nicht (mehr) eigenstaendig gibt (z.B. Oasis-Rang steckt im Profil), weglassen
            if scope and (AREA_SCOPE[k] or "personal") ~= scope then seen[k] = true
            elseif d and d.visible and not d.visible() then seen[k] = true
            elseif d and d.nav then items[#items + 1] = d seen[k] = true end   -- 0.5.679: Dashboard mit drin (fest an)
        end
        if #items > 0 then out[#out + 1] = { text = (g.text and g.text ~= "") and g.text or "Start", items = items } end
    end
    local rest = {}
    for _, d in ipairs(ns.Pages()) do
        if d.nav and not seen[d.key] and d.key ~= "home" and not d.topbar and not (d.visible and not d.visible()) and (not scope or (AREA_SCOPE[d.key] or "personal") == scope) then rest[#rest + 1] = d end
    end
    if #rest > 0 then out[#out + 1] = { text = "Weitere", items = rest } end
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
    -- Auswahl oben: Knopf mit Symbol, Klick oeffnet eine Bereichs-Karte (Gruppen in zwei Spalten, mit Symbolen)
    local function iconTag(key, c)
        local path = ns.ICONS and ns.ICONS[key]
        if not path then return "" end
        c = c or C.text
        return ("|T%s:14:14:0:0:64:64:0:64:0:64:%d:%d:%d|t  "):format(path, c[1] * 255, c[2] * 255, c[3] * 255)
    end
    -- 0.5.550: kein Dropdown mehr - Uebersicht als Karten (wie "Entdecken"), Zahnrad oeffnet die Einstellungen
    f.pick = { Update = function() end }
    f.back = K.Button(f, "< " .. L["Alle Bereiche"], 140, 22, "ghost", function() f.sel = nil f:ShowSel() end)
    f.back:SetPoint("TOPLEFT", 0, -6)
    f.back:Hide()
    f.intro = note(f, L["Schalter: in deiner Navigation anzeigen. Zahnrad: Funktion einstellen. Module schaltest du unter System & Module ab."], 0, -6, 620, C.muted)
    f.pickHint = { SetShown = function(_, v) f.back:SetShown(not v) f.intro:SetShown(v) end }
    -- Rundgang erneut starten (Onboarding.lua)
    f.tourBtn = K.Button(f, L["Rundgang"], 88, 22, "ghost", function() ns.Onboarding.Show() end)
    f.tourBtn:SetPoint("TOPRIGHT", 0, -6)

    -- Uebersicht: alle Bereiche als Karten nach Gruppen (Symbol, Name, Kurztext, Schalter, Zahnrad)
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
            -- Schalter (oben rechts) + Zahnrad daneben
            t.sw = K.Pill(t, 24, 13)
            t.sw:SetPoint("TOPRIGHT", -34, -13)
            t.knob = K.KnobCircle(t.sw, 10)
            t.gear = CreateFrame("Button", nil, t)
            t.gear:SetSize(20, 20)
            t.gear:SetPoint("TOPRIGHT", -8, -9)
            t.gear.ic = K.Glyph(t.gear, 14, ns.MEDIA .. "icons\\settings", C.dim)
            t.gear.ic:SetPoint("CENTER")
            t.gear:SetScript("OnClick", function() f.sel = key f:ShowSel() end)
            t.gear:SetScript("OnEnter", function(self) self.ic:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { L[d.title], L["Einstellungen dieses Bereichs"] }) end)
            t.gear:SetScript("OnLeave", function(self) self.ic:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
            t.key = key
            -- Dashboard laesst sich nicht ausblenden: kein Schalter, Klick oeffnet seine Einstellungen
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
                if ns.Admin and not ns.Admin.PageEnabled(key) then lines[#lines + 1] = "|cffffc24d" .. L["Von der Gildenleitung abgeschaltet."] .. "|r" end
                lines[#lines + 1] = "|cff888888" .. L["Klick: zeigen/ausblenden  ·  Zahnrad oder Rechtsklick: Einstellungen"] .. "|r"
                K.ShowTip(self, lines)
            end)
            t:SetScript("OnLeave", function(self) self.tint:SetAlpha(1) GameTooltip:Hide() end)
            indexAdd(L[d.title], t, L["In meiner Navigation zeigen"])
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
        -- Rollbereich der Einstellungsseite neu vermessen
        local sc = f:GetParent()
        if sc and sc.Measure then pcall(sc.Measure) end
    end
    f.ov:SetScript("OnSizeChanged", layoutOv)
    layoutOv()

    -- Einzelner Bereich: wird bei jeder Auswahl neu aufgebaut
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
        -- scrollbar, falls ein Bereich mehr Einstellungen hat als Platz ist (Mausrad + schmale Leiste)
        local sf = CreateFrame("ScrollFrame", nil, self)
        sf:SetPoint("TOPLEFT", 0, -46)
        sf:SetPoint("BOTTOMRIGHT", 0, 0)
        self.detScroll = sf
        -- 0.5.615: war die Bereichs-Uebersicht nach unten gerollt, lag der Bereich ausserhalb des Sichtfelds und das
        -- Mausrad landete nur noch hier -> aeusseren Rollbereich nach oben setzen und diesen hier an dessen Unterkante binden
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
        -- 0.5.912: kein Kopf mehr mit Symbol, "Bereich oeffnen" und "In meiner Navigation zeigen" - das Ein-/Ausblenden
        -- steht schon eine Ebene hoeher in der Bereichsliste. Die Karte traegt den Namen des Bereichs.
        local adminOff = ns.Admin and not ns.Admin.PageEnabled(key)
        local c2 = card(det, 0, 0, 740, 300)
        c2:SetPoint("TOPRIGHT", det, "TOPRIGHT", -2, 0)
        section(det, L[d.title], 14, -12, 700)
        if adminOff then
            note(det, "|cffffc24d" .. L["Von der Gildenleitung abgeschaltet."] .. "|r", 360, -13, 300)
        end
        det:SetScript("OnSizeChanged", nil)
        local Y0 = -46
        local y = Y0
        descInline = true   -- Erklaerungen als Unterzeile, danach nachruecken (reflowDescs)
        local opts = PAGE_OPTS[key] or {}
        for _, o in ipairs(opts) do
            if o[5] and S()[o[2]] == nil then S()[o[2]] = true end   -- Standard an
            det.t[#det.t + 1] = toggle(det, 14, y, o[1], o[2], o[3], o[4], 600)
            y = y - 32
        end
        if opts.inactive then
            rowLabel(det, L["Inaktiv ab"], 14, y - 2)
            det.inact = K.Slider(det, 180, 7, 90, 1, function() return S().inactiveDays or 30 end,
                function(v) S().inactiveDays = v end, function(v) return (L["%d Tg"]):format(v) end)
            det.inact:SetPoint("TOPLEFT", 184, y)
            y = y - 28
            note(det, L["Ab so vielen Tagen offline gilt ein Mitglied in der Mitgliederliste als inaktiv."], 14, y, 600)
            y = y - 24
        end
        if opts.listDark then
            rowLabel(det, L["Listen-Hintergrund"], 14, y - 2)
            det.listDark = K.Slider(det, 180, 0.2, 1, 0.01, function() return S().memberListAlpha or 0.82 end,
                function(v) S().memberListAlpha = v if ns.Radar and ns.Radar.ApplyListBg then pcall(ns.Radar.ApplyListBg) end end,
                function(v) return ("%d %%"):format(v * 100 + 0.5) end)
            det.listDark:SetPoint("TOPLEFT", 184, y)
            det.t[#det.t + 1] = det.listDark
            y = y - 36
        end
        if opts.emojiPicker then
            local ep = K.Button(det, L["Emojis ansehen"], 140, 22, "ghost", function() if ns.Emoji then ns.Emoji.TogglePicker() end end)
            ep:SetPoint("TOPLEFT", 14, y)
            y = y - 36
        end
        if opts.lootQuality then
            rowLabel(det, L["Beute-Log ab Qualitaet"], 14, y - 2)
            det.q = K.Segments(det, {
                { key = 2, text = L["Gruen"] }, { key = 3, text = L["Blau"] }, { key = 4, text = L["Episch"] },
            }, function(k) S().lootMinQuality = k end)
            det.q:SetPoint("TOPLEFT", 184, y)
            y = y - 34
        end
        if PAGE_EXTRA[key] then
            local ok, ny = pcall(PAGE_EXTRA[key], det, y)
            if ok and type(ny) == "number" then y = ny
            elseif not ok then ns.err(L["Aufbau"] .. " settings/pages/" .. key, ny) end
        end
        -- Unterseiten ohne eigenen Navigationspunkt: Einstellungen beim Hauptbereich zeigen
        for _, ck in ipairs(AREA_CHILDREN[key] or {}) do
            local cd = ns.PageDef(ck)
            if cd and (PAGE_OPTS[ck] or PAGE_EXTRA[ck]) then
                y = y - 10
                rowLabel(det, "|cffe8b44a" .. L[cd.title] .. "|r", 14, y)
                y = y - 30
                for _, o in ipairs(PAGE_OPTS[ck] or {}) do
                    if o[5] and S()[o[2]] == nil then S()[o[2]] = true end
                    det.t[#det.t + 1] = toggle(det, 14, y, o[1], o[2], o[3], o[4], 600)
                    y = y - 32
                end
                if PAGE_EXTRA[ck] then
                    local ok, ny = pcall(PAGE_EXTRA[ck], det, y)
                    if ok and type(ny) == "number" then y = ny
                    elseif not ok then ns.err(L["Aufbau"] .. " settings/pages/" .. ck, ny) end
                end
            end
        end
        -- 0.5.995: Tooltip- und Karten-Schalter stehen gesammelt unter Tooltips & Karte - hier nur der Weg dorthin
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
            note(det, L["Fuer diesen Bereich gibt es keine eigenen Einstellungen."], 14, y, 600, C.dim)
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
    -- 0.5.524: jedes Element nur aktualisieren, wenn es das kann (vorher brach die Seite bei einem fehlenden Refresh ab)
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
-- Darstellung
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
-- Design wechseln: Palette tauschen, Fenster neu aufbauen (gebremst)
local themeGen = 0
local function rebuildSoon()
    themeGen = themeGen + 1
    local gen = themeGen
    ns.After(0.25, function()
        if gen ~= themeGen then return end
        if K.ApplyTheme then K.ApplyTheme() end
        -- ApplyBrand -> ApplyAccent baut das Fenster selbst (gebremst) neu auf; hier nicht nochmal (sonst laedt es doppelt)
        if ns.Admin then ns.Admin.ApplyBrand(true) elseif ns.RebuildMain then ns.RebuildMain() end
    end)
end
-- Zustand der Farb-Einstellungen merken -> Funktion, die ihn wiederherstellt (Farbwaehler "Abbrechen")
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
-- kleine Vorschaukarte je Design (zeigt Hintergrund/Verlauf, Seitenleiste, Akzent, Rahmen)
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
    local own   -- Design mit eigener Vorschau (Zusatzmodul): th.preview(b) -> Abstand des Namens, Textfarbe
    if th.preview then
        local ok, nx, tc = pcall(th.preview, b)
        if ok and nx then own, nameX, text = true, nx, tc or text end
    end
    if not own then
        for i = 1, 3 do   -- angedeutete Navigation
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
        K.ShowTip(self, { L[th.name], L[th.desc], "|cff888888" .. L["Klick: Design uebernehmen (Farben, Akzent, Schrift)"] .. "|r" })
    end)
    b:SetScript("OnLeave", function(self)
        K.SetBorderColor(self, self.on and C.accent or line, self.on and 1 or 0.9)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        local s = S()
        -- Design-Klick = Basis neu setzen: eigene Akzentfarbe/Verlauf gehen auf die Werte des Designs zurueck
        -- (Kontrast, Rahmen, Grafik, Deckkraft bleiben - die sind unabhaengig vom Design)
        local cur = K.CurrentTheme()
        local hadOverride = (s.accent or "") ~= (cur.accent or "") or s.themeGrad ~= nil
        if hadOverride and s.theme ~= th.key and K.Toast then
            K.Toast(L[th.name], L["Akzentfarbe und Verlauf auf das Design zurueckgesetzt"], C.accent)
        end
        s.theme = th.key
        s.colorOn = nil                      -- Design-Klick = Farben des Designs (eigene Farben wieder aus)
        s.themeGrad = nil                    -- Verlauf wieder wie im Design vorgesehen
        s.accent = th.accent                 -- Standard = Farbe der Gilde
        -- 0.6.160: Design-Klick = alles auf Standard - auch eigene Grund-/Akzent-/Leistenfarbe, Glut-Farben,
        -- Glut-Staerke und Atmen
        s.duoBase, s.duoAccent, s.duoSide, s.glowColor, s.glowColorSide, s.frameColor = nil, nil, nil, nil, nil, nil
        s.glowStrengthL, s.glowStrengthR, s.glowBreath = nil, nil, nil
        if th.font and K.fontByKey[th.font] then s.uiFont = th.font K.ApplyUserFonts() end
        -- Design mit eigenem Klick-Soundpaket (th.uiPack); wer Klick-Toene aus hat, bleibt bei aus
        if th.uiPack and ns.Sound and ns.Sound.SetUiPack and ns.Sound.UiPack() ~= "none" then ns.Sound.SetUiPack(th.uiPack) end
        if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
        rebuildSoon()
    end)
    return b
end

local function buildLook(f)
    -- 0.5.544: luftig in voller Breite (Seite scrollt), Glas-Karten, Design-Karten heben sich beim Ueberfahren
    f.noCompact = true
    local LX = 16
    local function cardW(y, h, icon, title, sub)
        local c = cardH(f, 0, y, 740, h, icon, title, sub)
        c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
        return c
    end

    -- Design ---------------------------------------------------------------
    -- 0.5.555: zwei Spalten - links Design + Schrift, rechts Eigene Farben + Details
    local RXc = 376
    local themeRows = math.ceil(#K.THEMES / 2)
    local designH = 54 + themeRows * 72 + 4
    cardH(f, 0, 0, 362, designH, "brush", L["Design"], L["Fertige Looks - Farben, Akzent und Schrift auf einen Klick"])
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
        indexAdd(L[th.name], b, L["Design"])
    end

    -- Eigene Farben ----------------------------------------------------------
    local Y = 0
    local RX0 = RXc + 16
    -- Hoehe aus der Zahl der Vorlagen (6 je Reihe)
    local duoRows = math.ceil(#K.DUO_PRESETS / 6)
    local farbH = 68 + duoRows * 28 + 8 + 24 + 20 + 30 + 34 + 104   -- 0.6.232: zwei Regler (Glut, Bild-Helligkeit)   -- 0.6.136/0.6.149 Knopfzeilen; 0.6.158: Glut-Staerke und Atmen
    cardH(f, RXc, Y, 362, farbH, "heart", L["Eigene Farben"], L["Zwei Farben mischen - Grundfarbe, Akzent und Leiste einzeln waehlbar"], true)
    local function applyDuo(base, acc)
        local s = S()
        -- 0.5.786: eigene Farben faerben das GEWAEHLTE Design um - das Design selbst (Stil, Rahmen, Schrift) bleibt
        s.colorOn, s.duoBase, s.duoAccent, s.accent, s.themeGrad = true, base, acc, acc, nil
        if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
        rebuildSoon()
    end
    local l0 = K.Text(f, 10, C.dim) l0:SetPoint("TOPLEFT", RX0, Y - 52) l0:SetText(K.Upper(L["Zwei Farben"]))
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
        b:SetScript("OnEnter", function(self) K.SetBorderColor(self, ac) K.ShowTip(self, { L[pr.name], "|cff888888" .. L["Klick: das gewaehlte Design in diesen Farben"] .. "|r" }) end)
        b:SetScript("OnLeave", function(self) K.SetBorderColor(self, self.on and C.accent or C.line) GameTooltip:Hide() end)
        b:SetScript("OnClick", function() S().duoSide = pr.side applyDuo(pr.base, pr.acc) end)
        f.duo[i] = b
    end
    local by = Y - 68 - math.ceil(#K.DUO_PRESETS / DPER) * 28 - 8
    f.duoBase = K.ColorPickButton(f, function() return S().duoBase or "15171d" end, function(hex) applyDuo(hex, S().duoAccent or (S().accent ~= "" and S().accent) or "ff4d6d") end, L["Fenster-Hintergrund"], lookSnapshot)
    f.duoBase:SetWidth(162)
    f.duoBase:SetPoint("TOPLEFT", RX0, by)
    f.duoAcc = K.ColorPickButton(f, function() return S().duoAccent or "ff4d6d" end, function(hex) applyDuo(S().duoBase or "15171d", hex) end, L["Akzent / Hervorhebung"], lookSnapshot)
    f.duoAcc:SetWidth(162)
    f.duoAcc:SetPoint("LEFT", f.duoBase, "RIGHT", 6, 0)
    -- 0.6.170: klare Namen + Erklaerung, was genau gefaerbt wird
    f.duoBase:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Fenster-Hintergrund"], L["Grundfarbe des ganzen Oasis-Fensters (Flaechen und Karten)."] }) end)
    f.duoAcc:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Akzent / Hervorhebung"], L["Farbe fuer Rahmen, Knoepfe, Markierungen und aktive Eintraege."] }) end)
    -- 0.6.159: aktuelle Grund-/Akzentfarbe behalten (vorher Standardfarben -> rechts aenderte sich alles mit)
    local function curBase() return S().duoBase or (C.bg and K.ToHex(C.bg)) or "15171d" end
    local function curAcc() return S().duoAccent or (C.accent and K.ToHex(C.accent)) or "ff4d6d" end
    f.duoSide = K.ColorPickButton(f, function()
        local th = K.DuoTheme(S().duoBase, S().duoAccent, S().duoSide)
        return (S().duoSide and S().duoSide ~= "") and S().duoSide or K.ToHex(th.side)
    end, function(hex)
        S().duoSide = hex
        applyDuo(curBase(), curAcc())
    end, L["Navigation links"], lookSnapshot)
    f.duoSide:SetWidth(162)
    f.duoSide:SetPoint("TOPLEFT", f.duoBase, "BOTTOMLEFT", 0, -6)
    f.duoSide:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.duoSide:HookScript("OnClick", function(_, btn)
        if btn == "RightButton" then S().duoSide = nil applyDuo(curBase(), curAcc()) end
    end)
    f.duoSide:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Navigation links"], L["Hintergrundfarbe der Navigationsleiste links. Rechtsklick: wieder automatisch."] }) end)
    f.duoSide:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.136: eigene Farbe fuer die Glut-Hintergruende (Leiste links und Inhalt rechts); ohne Wahl = Akzentfarbe
    f.glowCol = K.ColorPickButton(f, function()
        return (S().glowColor and S().glowColor ~= "") and S().glowColor or K.ToHex(C.accent)
    end, function(hex) S().glowColor = hex end, L["Glut im Inhalt"], lookSnapshot)
    f.glowCol:SetWidth(162)
    f.glowCol:SetPoint("LEFT", f.duoSide, "RIGHT", 6, 0)
    f.glowCol:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.glowCol:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().glowColor = nil if self.Update then self:Update() end end
    end)
    f.glowCol:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Glut im Inhalt"], L["Farbe der leuchtenden Glutadern im grossen Inhaltsbereich rechts. Rechtsklick: wieder wie die Akzentfarbe."] }) end)
    f.glowCol:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.149: eigene Farbe fuer den Hintergrund der Leiste links (ohne Wahl wie rechts bzw. Akzentfarbe)
    f.glowSide = K.ColorPickButton(f, function()
        local v = S().glowColorSide
        if v and v ~= "" then return v end
        return K.ToHex(C.accent)   -- 0.6.159: wie rechts - ohne Wahl die Akzentfarbe
    end, function(hex) S().glowColorSide = hex end, L["Glut in der Navigation"], lookSnapshot)
    f.glowSide:SetWidth(162)
    f.glowSide:SetPoint("TOPLEFT", f.duoSide, "BOTTOMLEFT", 0, -6)
    f.glowSide:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.glowSide:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().glowColorSide = nil if self.Update then self:Update() end end
    end)
    f.glowSide:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Glut in der Navigation"], L["Farbe der leuchtenden Glutadern in der Navigationsleiste links. Rechtsklick: wieder wie die Akzentfarbe."] }) end)
    f.glowSide:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.191: Farbe der Glut im Fensterrahmen (Bild-Rahmen); ohne Wahl wie die Akzentfarbe
    f.frameCol = K.ColorPickButton(f, function()
        local v = S().frameColor
        if v and v ~= "" then return v end
        return K.ToHex(C.accent)
    end, function(hex) S().frameColor = hex end, L["Fensterrahmen"], lookSnapshot)
    f.frameCol:SetWidth(162)
    f.frameCol:SetPoint("LEFT", f.glowSide, "RIGHT", 6, 0)
    f.frameCol:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.frameCol:HookScript("OnClick", function(self, btn)
        if btn == "RightButton" then S().frameColor = nil if self.Update then self:Update() end end
    end)
    f.frameCol:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Fensterrahmen"], L["Farbe der Glut im Fensterrahmen. Rechtsklick: wieder wie die Akzentfarbe."] }) end)
    f.frameCol:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.6.158: Glut-Staerke links/rechts und "Glut atmet"
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
    -- 0.6.231: vereinfacht auf drei Regler, die jeweils links UND rechts setzen (vorher sechs einzelne)
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
    f.glowAllLbl, f.glowAll = pairRow("Glut", { "glowStrengthR", "glowStrengthL" }, f.glowSide, -16, 2, 1,
        "Leuchtkraft der Glutadern links und rechts. 0 % = aus.")
    -- 0.6.232: Bild-Deckkraft entfaellt (Helligkeit 0 % = schwarz deckt das ab); alte Werte einmalig auf 100 %
    S().bgBright, S().bgBrightL = nil, nil
    f.bgLiLbl, f.bgLi = pairRow("Bild-Helligkeit", { "bgLight", "bgLightL" }, f.glowAllLbl, -14, 2, 1,
        "0 % = schwarz, 100 % = normal, darueber kraeftiger und leuchtender.", applyBg)
    f.glowBreath = K.Toggle(f, L["Glut atmet"], function() return S().glowBreath and true or false end,
        function(v) S().glowBreath = v or nil end)
    f.glowBreath:SetPoint("TOPLEFT", f.bgLiLbl, "BOTTOMLEFT", 0, -12)
    f.glowBreath:SetWidth(330)
    indexAdd(L["Glut atmet"], f.glowBreath)
    -- Schrift (links) + Details (rechts) --------------------------------------
    local Y3 = -designH - 14
    cardH(f, 0, Y3, 362, 300, "chronicle", L["Schrift"], L["Gilt fuer die ganze Oasis-Oberflaeche. Wirkt sofort, einzelne Stellen erst nach /reload."])
    f.head = fontList(f, LX, Y3 - 54, 330, 232, K.PickFonts(), "uiFont", true)
    Y3 = Y - farbH - 14
    -- 0.6.107: Details als ruhige Liste - drei Schalter in voller Breite, darunter Groesse und Durchsicht, unten
    -- Zuruecksetzen (vorher Kacheln mit abgeschnittenem Titel und einer grossen Luecke vor den Reglern)
    cardH(f, RXc, Y3, 362, 362, "settings", L["Details"], L["Kontrast, Rahmen, Grafik, Groesse und Durchsicht"], true)
    local MX = RXc + 16
    local restyle = function() local m = ns.MainFrame and ns.MainFrame() if m and K.StyleWindow then K.StyleWindow(m) end end
    if S().themeTexture == nil then S().themeTexture = true end
    if S().imageFrame == nil then S().imageFrame = true end
    f.contrast = toggle(f, MX, Y3 - 62, "Hoher Kontrast", "highContrast", "Graue Texte und Linien heller", function() rebuildSoon() end, 330)
    f.frameAcc = toggle(f, MX, Y3 - 94, "Rahmen in Akzentfarbe", "frameAccent", "Fensterrand in deiner Farbe", function() restyle() end, 330)
    f.texT = toggle(f, MX, Y3 - 126, "Hintergrundgrafik", "themeTexture", "Leder, Stein, Hex-Raster ... je nach Design", function(v)
        S().themeTexture = v and true or false
        restyle()
    end, 330)
    -- 0.6.192: Bild-Rahmen (Lavaglut) an/aus - aus = schlanker moderner Rahmen mit Schimmer wie vorher
    f.imgFrame = toggle(f, MX, Y3 - 158, "Verzierter Fensterrahmen", "imageFrame", "Bild-Rahmen mit Glut (aus: schlanker moderner Rahmen)", function(v)
        S().imageFrame = v and true or false
        if K.ApplyFrameStyle then
            local m = ns.MainFrame and ns.MainFrame()
            if m then K.ApplyFrameStyle(m) end
            if _G.OasisInterests then K.ApplyFrameStyle(_G.OasisInterests) end if _G.OasisFighterSelect then K.ApplyFrameStyle(_G.OasisFighterSelect) end
        end
        if K.RefreshBoxFrames then K.RefreshBoxFrames() end
    end, 330)
    -- 0.6.281: derselbe Rahmen schmal um alle Boxen (nur mit Gildenmodul, nur wenn der verzierte Rahmen an ist)
    if S().boxFrame == nil then S().boxFrame = true end
    f.boxFrameT = toggle(f, MX, Y3 - 190, "Rahmen auch um Boxen", "boxFrame", "Die rote Linie auch schmal um Karten und Boxen im Addon", function(v)
        S().boxFrame = v and true or false
        if K.RefreshBoxFrames then K.RefreshBoxFrames() end
    end, 330)
    f.logoSeg = { Select = function() end }   -- 0.5.681: keine Logo-Auswahl mehr (Stub fuer refreshLook)
    local dv = K.Divider(f)
    dv:SetPoint("TOPLEFT", MX, Y3 - 226)
    dv:SetWidth(330)
    rowLabel(f, L["Fenstergroesse"], MX, Y3 - 242)
    local pendingScale
    f.winScale = K.Slider(f, 200, 0.7, 1.4, 0.05, function() return pendingScale or S().scale or 1 end,
        function(v) pendingScale = v end, function(v) return (L["%d%%"]):format(v * 100 + 0.5) end,
        function(v)
            pendingScale = nil
            if v ~= S().scale then ns.SetScale(v) end
        end)
    f.winScale:SetPoint("TOPLEFT", MX + 110, Y3 - 240)
    indexAdd(L["Fenstergroesse"], f.winScale)
    rowLabel(f, L["Durchsicht"], MX, Y3 - 274)
    f.winAlpha = K.Slider(f, 200, 0.1, 1, 0.01, function() return S().windowAlpha or 1 end,
        function(v) S().windowAlpha = v if ns.ApplyWindowAlpha then ns.ApplyWindowAlpha() end end,
        function(v) return ("%d %%"):format(v * 100 + 0.5) end)
    f.winAlpha:SetPoint("TOPLEFT", MX + 110, Y3 - 272)
    indexAdd(L["Durchsicht"], f.winAlpha, L["Wie durchsichtig das Oasis-Fenster ist"])
    local rs = K.Button(f, L["Aussehen zuruecksetzen"], 170, 24, "ghost", function()
        local st = S()
        st.theme, st.themeGrad, st.highContrast, st.frameAccent, st.accent, st.uiFont = nil, nil, nil, nil, "", "inter"
        st.duoBase, st.duoAccent, st.duoSide, st.glowColor, st.glowColorSide, st.frameColor, st.bgBright, st.bgBrightL, st.bgLight, st.bgLightL = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
        st.glowStrengthL, st.glowStrengthR, st.glowBreath = nil, nil, nil
        st.themeTexture, st.logoAnim, st.logoMode, st.windowAlpha = true, true, nil, 1
        K.ApplyUserFonts()
        if ns.ApplyWindowAlpha then ns.ApplyWindowAlpha() end
        if K.Toast then K.Toast(L["Aussehen zuruecksetzen"], L["Alle Farb- und Design-Einstellungen stehen wieder auf Standard."], C.accent) end
        rebuildSoon()
    end)
    rs:SetPoint("TOPLEFT", MX, Y3 - 314)
    note(f, L["Manche Stellen faerben sich erst nach /reload um."], MX + 182, Y3 - 316, 150, C.dim)
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
-- Hinweise
------------------------------------------------------------------------
local function buildToasts(f)
    f.noCompact = true
    f.t = {}
    -- Karte: Allgemein
    card(f, 0, 0, 362, 214)
    section(f, L["Hinweise"], 14, -12, 334)
    f.t[1] = toggle(f, 14, -46, "Hinweise anzeigen", "toasts", "Auftraege, Termine, Gruppensuchen, Durchsagen ...", nil, 320)
    f.t[2] = toggle(f, 14, -78, "Im Kampf zurueckhalten", "toastHoldCombat", "Erscheinen gesammelt, sobald der Kampf vorbei ist", nil, 320)
    rowLabel(f, L["Anzeigedauer"], 14, -118)
    f.dur = K.Slider(f, 160, 1, 20, 1, function() return S().toastDur or 7 end,
        function(v) S().toastDur = v end, function(v) return (L["%d s"]):format(v) end)
    f.dur:SetPoint("TOPLEFT", 144, -116)
    note(f, L["Wichtige Durchsagen der Gildenleitung bleiben doppelt so lange stehen."], 14, -144, 334)
    local test = K.Button(f, L["Test-Hinweis"], 120, 24, "ghost", function()
        K.Toast(L["Oasis laeuft"], L["So sehen Hinweise aus."], C.accent)
    end)
    test:SetPoint("TOPLEFT", 14, -174)

    -- Karte: Groesse und Position
    local RX = 376
    local rc = card(f, RX, 0, 362, 214)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["Groesse und Position"], RX + 14, -12, 330)
    rowLabel(f, L["Groesse"], RX + 14, -48)
    f.scale = K.Slider(f, 160, 0.7, 1.5, 0.05, function() return S().toastScale or 1 end,
        function(v) S().toastScale = v K.LayoutToasts() end,
        function(v) return (L["%d%%"]):format(v * 100 + 0.5) end,
        function() K.Toast(L["Oasis laeuft"], L["So sehen Hinweise aus."], C.accent) end)
    f.scale:SetPoint("TOPLEFT", RX + 130, -46)
    local move = K.Button(f, L["Position aendern"], 150, 24, "primary", function()
        K.ToastMover(function() ns.RefreshPage("settings") end)
    end)
    move:SetPoint("TOPLEFT", RX + 14, -84)
    local reset = K.Button(f, L["Zuruecksetzen"], 120, 24, "ghost", function()
        S().toastPos, S().toastScale = nil, 1
        K.LayoutToasts()
        ns.RefreshPage("settings")
    end)
    reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
    f.posNote = note(f, "", RX + 14, -120, 330, C.muted)

    -- Hinweise nach Anlass; die Auswahl bleibt beim Zu-/Aufklappen erhalten.
    f.kinds, f.kindGroups = {}, {}
    local scopes = {
        { key = "guild", title = "Gilde & Organisation", desc = "Durchsagen, Termine, Handwerk und gemeinsame Fortschritte." },
        { key = "social", title = "Socializing", desc = "Gruppensuche, neue Mitglieder, Geburtstage und gemeinsame Spiele." },
        { key = "personal", title = "Meine Erfolge & Allgemeines", desc = "Deine Stufen, Abzeichen und persoenlichen Hinweise." },
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
    local head = K.Header(f, L["Welche Hinweise willst du sehen?"])
    head:SetPoint("TOPLEFT", 0, -234)
    local go = K.Button(f, L["Sounds dazu"], 110, 24, "ghost", function() page.SetTab("sound") end)
    go:SetPoint("TOPRIGHT", -2, -230)
    local allOn = K.Button(f, L["Alle an"], 80, 24, "ghost", function()
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
        g.bulk = K.Button(g.card, L["Gruppe ausschalten"], 170, 24, "ghost", function()
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
    -- ausgeschaltete Hinweis-Arten rot markieren, Zaehler oben
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
        f.kindSum:SetText(("|cff66db9e%d %s|r  |cff666666·|r  %s"):format(on, L["an"],
            n - on > 0 and ("|cffe06060" .. (n - on) .. " " .. L["aus"] .. "|r") or ("|cff888888" .. L["keiner aus"] .. "|r")))
    end
    for _, g in ipairs(f.kindGroups or {}) do
        local on = 0
        for _, t in ipairs(g.items) do
            if not (S().toastOff and S().toastOff[t.kindKey]) and not (t.kindKey == "death" and S().deathToasts == false) then on = on + 1 end
        end
        g.bulk:SetLabel(on > 0 and L["Gruppe ausschalten"] or L["Gruppe einschalten"])
        g.fold:SetLabel((g.closed and ">  " or "v  ") .. L[g.title] .. "  (" .. on .. "/" .. #g.items .. ")")
    end
    f.dur:Refresh()
    f.scale:Refresh()
    f.posNote:SetText(S().toastPos and L["Eigene Position. Liegt sie in der unteren Bildschirmhaelfte, stapeln sich neue Hinweise nach oben."]
        or L["Standard: oben in der Mitte. 'Position aendern' zeigt einen Beispiel-Hinweis, den du mit der Maus verschiebst."])
end

------------------------------------------------------------------------
-- Sound & Musik
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

    -- schlichte Sound-Auswahl: Lautsprecher (anhoeren) + Name, Klick oeffnet die Auswahl
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
        if K.NoUiSound then K.NoUiSound(b.play) end   -- Anhoeren: nur der Sound, kein Klick-Ton davor
        -- waehrend die eigene Vorschau laeuft: kleiner Equalizer statt Lautsprecher
        b.eq = K.Equalizer(b.play, 3, 11, 11, C.accent2, function() return b.playAt and GetTime() - b.playAt < 1.6 end)
        b.eq:SetPoint("CENTER", 0, 0)
        b.eq:Hide()
        b.play:HookScript("OnUpdate", function()
            local on = b.playAt and GetTime() - b.playAt < 1.6 or false
            if on ~= b.eqOn then b.eqOn = on b.eq:SetShown(on) b.play.icon:SetShown(not on) end
        end)
        b.play:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) K.ShowTip(self, L["Anhoeren"]) end)
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
                self.label:SetText("|cff777777" .. L["Kein Sound"] .. "|r")
                self.play:SetAlpha(0.3)
            else
                local c = Snd.byKey[k]
                self.label:SetText(c and (L[c.text]:gsub("^Oasis: ", ""):gsub("^Meme: ", ""):gsub("^Musik: ", ""):gsub("^WoW: ", "")) or k)
                self.play:SetAlpha(1)
            end
        end
        return b
    end

    -- Karte: Wiedergabe ---------------------------------------------------
    local X = 14
    card(f, 0, 0, 362, ns.TOOLS_RELEASED and 270 or 228)
    section(f, L["Wiedergabe"], X, -12, 334)
    f.on = toggle(f, X, -44, "Sounds abspielen", "sound", nil, nil, 320)
    f.quiet = toggle(f, X, -72, "Im Kampf stumm", "soundQuietCombat", nil, nil, 320)
    f.chs = toggle(f, X, -100, "Sounds aus dem Chat", "chatSounds", "Sounds, die andere im Gildenchat schicken", nil, 320)
    rowLabel(f, L["Lautstaerke"], X, -140)
    f.vol = K.Slider(f, 160, 0, Snd.VOL_MAX, 1, function() return S().soundVol or 14 end,
        function(v) S().soundVol = v if f.spk then refreshSoundSpk(f) end end,
        function(v) return v == 0 and L["aus"] or Snd.VolText(v) end,
        function(v) Snd.Preview("glocke", v) end)
    f.vol:SetPoint("TOPLEFT", X + 116, -138)
    -- UI-Soundpaket: Klick-Toene bei Knoepfen, Reitern, Schaltern und Fenster auf/zu
    rowLabel(f, L["Klick-Toene"], X, -168)
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
    f.uis:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Klick-Toene"], L["Soundpaket fuer Knoepfe, Reiter, Schalter und Fenster"] }) end)
    -- 0.5.948: eigene Sounds und Emojis einer Gilde - wie es geht und was gerade geladen ist
    -- haengt an ns.TOOLS_RELEASED (Core.lua): die Vorlage dazu liegt in Oasis-Tools auf GitHub/Discord
    if ns.TOOLS_RELEASED then
        local STEPS = {
            "1. Die Vorlage Oasis-Tools gibt es im Oasis-Discord (Kanal oasis-download).",
            "2. Nach Interface/AddOns entpacken: dort entstehen die Ordner Oasis_Sounds und Oasis_Emojis.",
            "3. Eigene Dateien hineinlegen, die Einlese-Datei doppelklicken, WoW neu starten.",
            "4. Die beiden Ordner an eure Gilde weitergeben. Updates von Oasis fassen sie nicht an.",
        }
        local function loaded()
            local s = rawget(_G, "OasisSoundsList")
            local e = rawget(_G, "OasisEmojiList")
            local ns_, ne = type(s) == "table" and #s or 0, 0
            for _, c in ipairs(type(e) == "table" and e or {}) do ne = ne + (type(c) == "table" and type(c.items) == "table" and #c.items or 0) end
            return (L["Geladen: %d eigene Sounds, %d eigene Emojis"]):format(ns_, ne)
        end
        f.own = K.Button(f, L["Eigene Sounds und Emojis ..."], 334, 22, "ghost", function()
            ns.print(L["Eigene Sounds und Emojis fuer eure Gilde"] .. ":")
            for _, t in ipairs(STEPS) do ns.print("  " .. L[t]) end
            ns.print("  " .. loaded())
        end)
        f.own:SetPoint("TOPLEFT", X, -236)   -- 0.6.111: unter die Klick-Lautstaerke (lag vorher genau darauf)
        f.own:HookScript("OnEnter", function(self)
            local lines = { L["Eigene Sounds und Emojis fuer eure Gilde"] }
            for _, t in ipairs(STEPS) do lines[#lines + 1] = L[t] end
            lines[#lines + 1] = "|cff66db9e" .. loaded() .. "|r"
            lines[#lines + 1] = "|cff888888" .. L["Klick: Anleitung in den Chat schreiben"] .. "|r"
            K.ShowTip(self, lines)
        end)
        f.own:HookScript("OnLeave", function() GameTooltip:Hide() end)
        -- 0.6.475: selten gebraucht - nur mit "Alle Optionen" (lag sonst nach dem Aufruecken auf der Kastenkante)
        if not S().setAll then f.own:Hide() end
    end
    f.uis:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- einzelne Toene zuweisen: kleines Fenster, je Aktion ein Paket waehlen (mit Vorhoeren)
    f.uiRoles = K.Button(f, "...", 44, 24, "ghost", function(self)
        local w = Snd.rolePop
        if not w then
            w = CreateFrame("Frame", "OasisUiRoles", UIParent)
            Snd.rolePop = w
            w:SetSize(330, 74 + #Snd.UI_ROLES * 32)
            w:SetFrameStrata("DIALOG")
            w:SetClampedToScreen(true)
            w:EnableMouse(true)
            -- deckend (Glas-Flaechen sind halbtransparent -> die Liste dahinter schien durch)
            local solid = { C.bg[1], C.bg[2], C.bg[3], 0.98 }
            K.Fill(w, solid)
            K.Border(w, C.line)
            if K.ApplySkin then K.ApplySkin(w, "panel", solid) end
            local t = K.Title(w, 14, C.text)
            t:SetPoint("TOPLEFT", 16, -14)
            t:SetText(L["Klick-Toene einzeln"])
            local x = K.CloseButton(w, function() w:Hide() end)
            x:SetPoint("TOPRIGHT", -8, -8)
            w.rows = {}
            for i, r in ipairs(Snd.UI_ROLES) do
                local role = r[1]
                local b = K.Button(w, "", 170, 24, "ghost")
                b:SetPoint("TOPLEFT", 112, -44 - (i - 1) * 32)
                local lb = K.Text(w, 12, C.muted)
                lb:SetPoint("RIGHT", b, "LEFT", -8, 0)   -- mittig zur Zeile
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
                    self:SetLabel(p and L[p.text] or ("|cff888888" .. L["wie das Paket"] .. "|r"))
                end
                b:SetScript("OnClick", function(btn)
                    local cur, list = Snd.UiRoleChoice(role), {}
                    list[1] = { text = L["wie das Paket"], checked = cur == nil, fn = function() Snd.SetUiRole(role, nil) btn:Refresh() Snd.PlayChoice("ui_" .. role) end }
                    for _, p in ipairs(Snd.UI_PACKS) do
                        list[#list + 1] = { text = L[p.text], checked = cur == p.key, fn = function()
                            Snd.SetUiRole(role, p.key)
                            btn:Refresh()
                            if p.key ~= "none" then Snd.PlayChoice("ui_" .. role) end
                        end }
                    end
                    K.ShowMenu(btn, list, nil, 170)
                end)
                local pl = K.IconButton(w, "", 22, function() Snd.PlayChoice("ui_" .. role) end, L["Anhoeren"])
                if K.NoUiSound then K.NoUiSound(pl) end
                pl:SetPoint("LEFT", b, "RIGHT", 6, 0)
                pl.label:Hide()
                pl.ic = K.Glyph(pl, 14, ns.MEDIA .. "icons\\speaker", C.muted)
                pl.ic:SetPoint("CENTER")
                w.rows[i] = b
            end
            local reset = K.Button(w, L["Alle wie das Paket"], 150, 22, "ghost", function()
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
    f.uiRoles:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Klick-Toene einzeln"], L["Fuer jede Aktion den Ton aus einem beliebigen Paket waehlen"] }) end)
    f.uiRoles:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- eigene Lautstaerke fuer die Klick-Toene (ohne Wert: 70 % der Sound-Lautstaerke)
    rowLabel(f, L["Klick-Lautstaerke"], X, -202)
    f.uivol = K.Slider(f, 160, 0, Snd.VOL_MAX, 1, function() return K.UiVolume() end,
        function(v) S().uiVol = v end,
        function(v) return v == 0 and L["aus"] or Snd.VolText(v) end,
        function() K.UiSound("ui_click") end)
    f.uivol:SetPoint("TOPLEFT", X + 116, -200)
    -- Equalizer oben rechts in der Karte: tanzt bei jeder Vorschau
    f.eq = K.Equalizer(f, 16, 92, 17, C.accent2, function() return Snd.previewAt and GetTime() - Snd.previewAt < 1.6 end)
    f.eq:SetPoint("TOPRIGHT", f, "TOPLEFT", 362 - 16, -12)
    f.eq:EnableMouse(true)
    f.eq:SetScript("OnMouseDown", function() Snd.Preview("glocke") end)
    f.eq:SetScript("OnEnter", function(self) K.ShowTip(self, L["Antippen zum Anhoeren"]) end)
    f.eq:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Lautsprecher vor der Lautstaerke: zeigt den Pegel
    f.spk = K.Glyph(f, 14, ns.MEDIA .. "icons\\speaker", C.muted)
    f.spk:SetPoint("TOPLEFT", X + 92, -142)

    -- Karte: Online kommen --------------------------------------------------
    local RX = 376
    local rc = card(f, RX, 0, 362, 228)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["Wenn jemand online kommt"], RX + 14, -12, 330)
    rowLabel(f, L["Dein Sound"], RX + 14, -46)
    f.entrChip = chip(f, 200, function() return Snd.ChoiceFor("entrance") end,
        function(k) Snd.SetChoice("entrance", k) end, function() return L["Dein Online-Sound"] end)
    f.entrChip:SetPoint("TOPLEFT", RX + 130, -42)
    f.entrChip:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Dein Online-Sound"], L["Hoeren alle mit Oasis, wenn du online kommst."] }) end)
    f.entrChip:HookScript("OnLeave", function() GameTooltip:Hide() end)
    rowLabel(f, L["Lautstaerke"], RX + 14, -80)
    f.evol = K.Slider(f, 160, 1, Snd.VOL_MAX, 1, function() return S().soundEntranceVol or 10 end,
        function(v) S().soundEntranceVol = v end,
        function(v) return Snd.VolText(v) .. (v > 20 and ("  |cffe8b44a" .. L["laut"] .. "|r") or "") end,
        function(v) Snd.PreviewLoud("hallo", v) end)
    f.evol:SetPoint("TOPLEFT", RX + 130, -78)
    f.entr = toggle(f, RX + 14, -110, "Online-Sounds anderer abspielen", "soundEntrance", nil, nil, 320)
    f.epop = toggle(f, RX + 14, -138, "Anzeige, wenn jemand online kommt", "entrancePopup", nil, nil, 320)

    -- Karte: Sounds je Hinweis -----------------------------------------------
    local bc = card(f, 0, -242, 738, 260)
    bc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -242)
    bc:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 4)
    local bh = K.Header(bc, L["Sounds fuer Hinweise"])
    bh:SetPoint("TOPLEFT", 14, -12)
    bh:SetPoint("RIGHT", -140, 0)
    local bl = K.Divider(bc)
    bl:SetPoint("TOPLEFT", 14, -32)
    bl:SetPoint("RIGHT", bc, "RIGHT", -14, 0)
    local def = K.Button(bc, L["Alle auf Standard"], 120, 20, "ghost", function()
        S().soundEvents = {}
        ns.RefreshPage("settings")
    end)
    def:SetPoint("TOPRIGHT", -14, -10)
    -- Vorlagen: setzt alle Hinweis-Sounds auf einmal
    local pre = K.Button(bc, L["Vorlage waehlen"], 130, 20, "ghost", function(self)
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
        -- Ueberfahren: Name rueckt etwas nach rechts, Symbol nimmt Akzentfarbe an
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

    -- Musik-Bereich entfernt; Oasis spielt keine Fenster-Musik mehr
    S().music = "off"
    if Snd.StopMusic then Snd.StopMusic() end
end
local function refreshSound(f)
    for _, t in ipairs({ f.on, f.quiet, f.chs, f.uis, f.uivol, f.entr, f.epop, f.vol, f.evol }) do t:Refresh() end
    -- Sounds aus: alles darunter wirkt sichtbar ruhig
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
-- Karte & Teilen
------------------------------------------------------------------------
-- 0.5.617: Datenschutz - alles, was dich selbst betrifft, an einer Stelle an-/abschaltbar
local PRIV_ON = { "shareDeaths", "shareNodes", "shareTrace", "shareInstPos", "sharePerf", "shareCombat", "rtShare", "rtTrack",
    "trackPlay", "scoutSeen", "wrShare", "lkShare", "profShareGear", "profShareQuests", "shareErrors", "campAuto", "cpProfCD",
    "chatSounds", "entrancePopup", "soundEntrance" }   -- 0.6.112: Klang-Standards (setzte vorher nur die Bereichsseite)
ns.Listen("DB_READY", function()
    local s = ns.db and ns.db.settings
    if not s then return end
    for _, k in ipairs(PRIV_ON) do if s[k] == nil then s[k] = true end end
    -- einmalig: datenschutzfreundliche Standards auch fuer bestehende Nutzer
    if not s.priv617 then
        s.priv617 = true
        s.shareMap, s.shareRep, s.rareShare, s.cpRareShare = false, false, false, false
        if s.oasisNet ~= true then s.oasisNet = nil end
    end
    -- 0.5.674: Fluester-Reaktionen immer senden (Schalter entfernt) - einmalig wieder an
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
    -- links: was die Gilde von dir sieht
    local ROW = 27
    local L1 = {
        { "Position auf der Weltkarte teilen", "shareMap", "Gildenkarte und Minimap-Punkte der anderen. Standard: aus" },
        { "Sterbeort teilen", "shareDeaths", "Totenkoepfe auf der Gildenkarte (90 Tage)" },
        { "Sammelorte teilen", "shareNodes", "Kraeuter- und Erzfunde fuer die Gilden-Sammelkarte" },
        { "Lagerfeuer automatisch melden", "campAuto", "Beim Anzuenden zeigt Oasis der Gilde, wo das Feuer brennt" },
        { "Rare-Sichtungen melden", "rareShare", "Seltene Gegner mit Ort an die Gilde. Standard: aus" },
        { "Dungeon-Laufwege teilen", "shareTrace", "Fuer selbst erkundete Dungeon-Karten" },
        { "Position im Dungeon an die Gruppe", "shareInstPos", "Nur an die eigene Gruppe, fuer die Dungeon-Karte" },
        { "Mitspieler-Bewertungen teilen", "shareRep", "Daumen und Notiz zu Mitspielern. Standard: aus (nur fuer dich)" },
        { "Twinks ausserhalb der Gilde zeigen", "shareAltsOutside", "Bank- und Chill-Twinks bleiben sonst privat" },
        { "Ausruestung im Profil", "profShareGear", nil },
        { "Quests im Profil", "profShareQuests", nil },
        { "Eigene Online-Zeiten teilen", "rtShare", "Fuer die Raid-Zeit-Planung (nur deine eigenen Zeiten)" },
        { "Kampf-Rekorde teilen", "shareCombat", "Bestwerte fuer die Kampf-Rangliste" },
        { "Kampfberichte teilen", "wrShare", "Bosskaempfe mit Todesreihenfolge (nur Gildenmitglieder)" },
        { "Raid-IDs teilen", "lkShare", nil },
        { "Handelsbilanz teilen", "shareTrade", "Fuer die Handels-Rangliste. Standard: aus" },
        { "Eigene Meilensteine im Gildenchat posten", "announceMilestones", "Level alle 5 Stufen und Legacy-Challenges" },
    }
    descInline = true
    local c1 = cardH(f, 0, 0, 362, 100, "social", L["Was die Gilde von dir sieht"], L["Alles abschaltbar - Standard ist datenschutzfreundlich"])
    local yy = -56
    for _, r in ipairs(L1) do
        tg(LX, yy, r[1], r[2], r[3], r[2] == "rareShare" and function(v) S().cpRareShare = v end
            or (r[2] == "shareAltsOutside" and function() if ns.Radar and ns.Radar.SendHello then pcall(ns.Radar.SendHello) end end) or nil)
        yy = yy - ROW - (r[3] and DESC_H or 0)
    end
    c1:SetHeight(-yy + 6)
    -- rechts oben: Technik
    local L2 = {
        { "Fehlerberichte an die Gilde", "shareErrors", "Hilft beim Beheben von Fehlern" },
        { "Liste anderer Addons mitsenden", "shareAddonList", "Nur fuer die Fehlersuche. Standard: aus" },
        { "Leistungsdaten teilen", "sharePerf", "Bildrate und Speicher, alle 15 Minuten" },
    }
    local c2 = cardH(f, RX, 0, 362, 100, "settings", L["Technik"], L["Fehlerberichte und Netz"], true)
    yy = -56
    for _, r in ipairs(L2) do
        tg(MX, yy, r[1], r[2], r[3])
        yy = yy - ROW - (r[3] and DESC_H or 0)
    end
    c2:SetHeight(-yy + 10)
    descInline = false
    local low = math.min(-(c1:GetHeight() or 0), yy - 10)
    resetButton(f, low - 16, function() if ns.Radar and ns.Radar.SendHello then pcall(ns.Radar.SendHello) end end)
    -- 0.5.675: Oasis-Netz ist immer an - kein Schalter mehr
    -- 0.5.673: Karte "Nur auf diesem PC" entfernt - Spielzeiten, Online-Zeiten, Begegnungen laufen immer, Raid-Check ohne Namen
end
local function refreshShare(f)
    for _, t in ipairs(f.t) do if t.Refresh then t:Refresh() end end
end

-- 0.5.617: Listen + Karten-Anzeige (vorher unter "Teilen & Karte")

------------------------------------------------------------------------
-- Charakter
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Einstellungen sichern: Export/Import als Text + gespeicherte Profile
-- eigenes, sicheres Format (kein loadstring): Tabellen, Texte, Zahlen, true/false
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
-- Leser fuer genau dieses Format; liefert nil bei jedem Fehler
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
-- uebernehmen: Werte setzen (Positionen u.a. bleiben), danach alles neu anwenden
local function applySettings(t)
    local s = S()
    -- fremder Text (z.B. aus dem Chat kopiert): nur bekannte Typen uebernehmen, Texte entschaerfen
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
    -- gespeichertes Profil laden (Einstellungen > Profil & Daten)
    LoadPreset = function(name)
        local p = ns.db.presets and ns.db.presets[name]
        local t = p and deser(p.s)
        if t then applySettings(t) return true end
        return false
    end }

local function buildChar(f)
    f.noCompact = true
    local X = 14
    -- Karte links: Profil ---------------------------------------------------
    card(f, 0, 0, 362, 470)
    section(f, L["Main und Twinks"], X, -12, 334)
    rowLabel(f, L["Main-Charakter"], X, -46)
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
    note(f, L["Twinks erkennt Oasis nach dem ersten Login automatisch."], X, -76, 334, C.muted)
    -- 0.5.794: der Schalter "Twinks ausserhalb der Gilde zeigen" stand doppelt (hier und unter Datenschutz, dieselbe Einstellung) -
    -- jetzt nur noch unter Datenschutz; hier ein Verweis mit Sprung dorthin
    f.altsLink = K.Button(f, L["Twinks ausserhalb der Gilde: unter Datenschutz"], 334, 22, "ghost", function() if page and page.SetTab then page.SetTab("share") end end)
    f.altsLink:SetPoint("TOPLEFT", X, -98)
    f.altsLink:SetHeight(20)
    -- von dir bestaetigte Twinks auf anderen WoW-Accounts: Liste mit Entfernen
    -- 0.5.874: sitzt in der Zeile "Main-Charakter" darunter passte er nicht (Geburtstag ueberlagerte sich) -> eigene schmale Zeile direkt unter dem Verweis
    f.extraAlts = K.Button(f, "", 334, 18, "ghost")
    f.extraAlts.isDropdown = true
    f.extraAlts:SetPoint("TOPLEFT", X, -122)
    local function extraLabel()
        local n = #ns.Alts.ExtraAlts()
        f.extraAlts:SetLabel((L["Twinks auf anderen Accounts: %d"]):format(n))
        f.extraAlts:SetAlpha(n > 0 and 1 or 0.55)
    end
    f.extraAlts:SetScript("OnClick", function(self)
        local items = {}
        for _, n in ipairs(ns.Alts.ExtraAlts()) do
            items[#items + 1] = { text = ns.displayName(n) .. "  |cffd9786b" .. L["entfernen"] .. "|r", fn = function() ns.Alts.RemoveExtra(n) extraLabel() end }
        end
        if #items == 0 then items[1] = { text = L["Noch keiner bestaetigt - der Twink traegt dich mit /oa twink als Main ein."], disabled = true } end
        K.ShowMenu(self, items, L["Klick entfernt die Verknuepfung"], 334)
    end)
    f.extraAlts:HookScript("OnShow", extraLabel)
    extraLabel()

    section(f, L["Geburtstag"], X, -144, 334)
    rowLabel(f, L["Geburtstag (TT.MM)"], X, -176)
    f.bstate = K.Text(f, 11, C.muted)
    f.bday = K.Input(f, 80, "12.10", function(t)
        if t == "" then
            ns.Members.SetBirthday(nil)
            f.bstate:SetText(L["nicht angegeben"])
        elseif ns.Members.SetBirthday(t) then
            f.bstate:SetText("|cff66db9e" .. L["gespeichert"] .. "|r")
        else
            f.bstate:SetText("|cffff5a4a" .. L["Format: TT.MM"] .. "|r")
        end
    end)
    f.bday:SetPoint("TOPLEFT", X + 150, -172)
    f.bstate:SetPoint("LEFT", f.bday, "RIGHT", 10, 0)
    note(f, L["Freiwillig. Die Gilde bekommt am Tag einen Hinweis und kann gratulieren."], X, -204, 334)

    -- 0.5.926: fuer jede Gilde (vorher nur mit dem Gildenmodul) - Daten fuer die eigene Webseite / den eigenen Discord-Bot
    -- 0.5.956: wieder nur mit dem Gildenmodul, solange die Export-Werkzeuge nicht veroeffentlicht sind
    if ns.ExternTools() then
        -- Gilden-Webseite: Daten fuer OasisSync (Paket Oasis-Tools) bereitstellen
        section(f, L["Gilden-Webseite"], X, -240, 334)
        f.webEx = K.Toggle(f, L["Daten fuer die Gilden-Webseite bereitstellen"],
            function() return ns.Officer and ns.Officer.ExportWanted and ns.Officer.ExportWanted() or S().webExport == true end,
            function(v) S().webExport = v and true or false end)
        f.webEx:SetPoint("TOPLEFT", X, -270)
        f.webEx:SetWidth(334)
        note(f, L["Mitglieder, Termine, Gildenbank usw. landen beim Ausloggen in den gespeicherten Daten - OasisSync (Ordner Oasis/Tools) kann sie an die Gilden-Webseite schicken. Nie dabei: Offiziersnotizen, Chats, Fluestern."], X, -300, 334)
    end

    -- 0.5.793: Oasis-Netz (realmweiter Kanal) komplett entfernt

    -- Karte rechts: Sichern -------------------------------------------------
    local RX, MX = 376, 390
    local rc = card(f, RX, 0, 362, 470)
    rc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    section(f, L["Einstellungen sichern"], MX, -12, 330)
    note(f, L["Deine Einstellungen gelten automatisch fuer alle Charaktere auf diesem Account."], MX, -40, 330, C.muted)

    -- Export / Import
    rowLabel(f, L["Als Text"], MX, -78)
    f.io = K.Input(f, 330, L["Hier Text einfuegen oder Exportieren klicken"])
    f.io:SetMaxLetters(0)
    f.io:SetPoint("TOPLEFT", MX, -100)
    f.ioState = K.Text(f, 11, C.muted)
    f.ioState:SetPoint("TOPLEFT", MX, -160)
    f.ioState:SetWidth(330)
    f.ioState:SetJustifyH("LEFT")
    local ex = K.Button(f, L["Exportieren"], 120, 24, "primary", function()
        f.io:SetText(exportString())
        f.io:SetFocus()
        f.io:HighlightText()
        f.ioState:SetText("|cff66db9e" .. L["Markiert - mit Strg+C kopieren."] .. "|r")
    end)
    ex:SetPoint("TOPLEFT", MX, -130)
    local im = K.Button(f, L["Importieren"], 120, 24, "ghost", function()
        if importString(f.io:GetText()) then
            f.ioState:SetText("|cff66db9e" .. L["Uebernommen."] .. "|r")
            f.io:SetText("")
        else
            f.ioState:SetText("|cffff5a4a" .. L["Das ist kein gueltiger Oasis-Text."] .. "|r")
        end
    end)
    im:SetPoint("LEFT", ex, "RIGHT", 8, 0)

    -- Gespeicherte Profile
    section(f, L["Gespeicherte Profile"], MX, -194, 330)
    f.pname = K.Input(f, 200, L["Name, z.B. Raid-Abend"])
    f.pname:SetPoint("TOPLEFT", MX, -226)
    local save = K.Button(f, L["Speichern"], 122, 24, "ghost", function()
        local n = (f.pname:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        ns.db.presets = ns.db.presets or {}
        ns.db.presets[n] = { s = ser(S()), ts = ns.now() }
        f.pname:SetText("")
        f.pname:ClearFocus()
        K.Toast(L["Profil gespeichert"], n, C.mint)
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
        r.load = K.Button(r, L["Laden"], 70, 20, "ghost", function()
            local p = r.item and ns.db.presets and ns.db.presets[r.item.name]
            local t = p and deser(p.s)
            if t then applySettings(t) K.Toast(L["Profil geladen"], r.item.name, C.mint) end
        end)
        r.load:SetPoint("RIGHT", -64, 0)
        r.del = K.Button(r, L["Loeschen"], 56, 20, "danger", function()
            if not r.item then return end
            -- zweimal klicken zum Loeschen
            if r.armed ~= r.item.name then
                r.armed = r.item.name
                r.del:SetLabel(L["Sicher?"])
                ns.After(3, function() r.armed = nil if r.del then r.del:SetLabel(L["Loeschen"]) end end)
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
        r.del:SetLabel(r.armed == p.name and L["Sicher?"] or L["Loeschen"])
    end)
    f.plist:SetPoint("TOPLEFT", MX - 4, -258)
    f.plist:SetPoint("BOTTOMRIGHT", rc, "BOTTOMRIGHT", -10, 10)
    f.plist.empty:SetText(L["Noch keine Profile gespeichert."])
end
local function refreshChar(f)
    f.main:SetLabel(ns.displayName(ns.Alts.MyMain()))
    if not f.bday:HasFocus() then
        f.bday:SetText(S().birthday or "")
        if f.bstate:GetText() == nil or f.bstate:GetText() == "" then f.bstate:SetText(S().birthday and "" or L["freiwillig"]) end
    end
    local list = {}
    for n, p in pairs(ns.db.presets or {}) do list[#list + 1] = { name = n, ts = p.ts } end
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    f.plist:SetData(list)
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------
-- Namen der gespeicherten Sammlungen fuer die Anzeige
local STORE_NAMES = {
    orders = "Handwerks-Auftraege", events = "Termine", signups = "Anmeldungen", chronicle = "Chronik",
    loot = "Beute", campCatalog = "Buff-Katalog", campfires = "Lagerfeuer", wants = "Wunschliste",
    lfg = "Gruppensuchen", duels = "Wuerfelspiele", notices = "Durchsagen", guildcfg = "Gilden-Einstellungen",
    audit = "Protokoll Gildenleitung", bank = "Gildenbank-Faecher", banklog = "Gildenbank-Protokoll",
    bankworth = "Bankwert-Verlauf", deaths = "Friedhof", links = "Links", points = "Lootpunkte",
    posts = "Oasigram-Beitraege", prices = "Marktpreise", raidplan = "Raidplaene", rep = "Spielerbuch-Bewertungen",
    votes = "Umfrage-Stimmen", polls = "Umfragen", likes = "Likes", comments = "Kommentare", follows = "Folgen",
    flights = "Flugpunkte", mapcal = "Karten-Termine", wtrain = "Waffenmeister", rpreq = "Ruf-Anfragen", invites = "Einladungen",
    reacts = "Reaktionen", lfgreq = "Gruppen-Anfragen", chatpin = "Angeheftet im Chat", attend = "Raid-Teilnahme", formers = "Ehemalige",
    tactics = "Boss-Taktiken", nodes = "Sammelpunkte", bans = "Sperren", sndmute = "Sound-Sperren", recruits = "Anwerbungen", sres = "Reservierungen",
    trace = "Dungeon-Spuren", raidint = "Raid-Interesse", bugs = "Fehlerberichte", ggoals = "Gildenziele", ggcontrib = "Gildenziel-Beitraege",
    talents = "Talente", scout = "Anwerbe-Vorschlaege", perf = "Leistungsmessungen", combat = "Kampf-Rekorde", profcd = "Berufs-Abklingzeiten",
    coll_chars = "Sammlungen: Charaktere", coll_mounts = "Sammlungen: Reittiere", coll_pets = "Sammlungen: Haustiere", coll_toys = "Sammlungen: Spielzeuge",
    gearmatch = "Upgrade-Boerse", lockouts = "Raid-IDs", qitems = "Questitems", rtweek = "Raid-Zeit", repfac = "Ruf-Planer",
}
local function buildStatus(f)
    -- 0.5.570: Glas-Karten mit Kopf, Datenliste passt in die Karte (vorher liefen 30 Zeilen unten hinaus, Ueberschriften fehlten)
    f.noCompact = true
    local hc = card(f, 0, 0, 738, 104)
    hc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    f.logo = ns.Wordmark(hc, 160, 40, false)   -- 0.5.683: hier steht das Addon, nicht die Gilde -> Oasis-Wortmarke
    f.logo:SetPoint("LEFT", hc, "LEFT", 22, 0)
    f.ver = K.Title(hc, 16, C.text)
    f.ver:SetPoint("TOPLEFT", hc, "TOPLEFT", 214, -20)
    f.guild = K.Text(hc, 12, C.muted)
    f.guild:SetPoint("TOPLEFT", f.ver, "BOTTOMLEFT", 0, -6)
    f.author = K.Text(hc, 11, C.dim)
    f.author:SetPoint("TOPLEFT", f.guild, "BOTTOMLEFT", 0, -5)
    f.author:SetText(L["Entwickelt von"] .. " " .. K.hex(C.accent) .. "Oasis Addons|r")
    f.lead = K.Text(hc, 11, C.amber)
    f.lead:SetPoint("TOPLEFT", f.author, "BOTTOMLEFT", 0, -5)
    f.tour = K.Button(hc, L["Rundgang starten"], 140, 24, "ghost", function() if ns.Onboarding then ns.Onboarding.Show() end end)
    f.tour:SetPoint("RIGHT", hc, "RIGHT", -18, 16)
    -- 0.5.949: Beispieldaten fuer alle - zum Ausprobieren und Einrichten, bevor die eigene Gilde Daten hat
    f.demoBtn = K.Button(hc, "", 140, 24, "ghost", function(self)
        if not ns.Demo then return end
        if ns.Demo.IsActive() then ns.Demo.Remove() else ns.Demo.Load() end
        self:Refresh()
        if ns.UpdateDemoSwitch then ns.UpdateDemoSwitch() end
    end)
    f.demoBtn:SetPoint("RIGHT", hc, "RIGHT", -18, -16)
    function f.demoBtn:Refresh()
        local on = ns.Demo and ns.Demo.IsActive()
        self.label:SetText(on and L["Beispieldaten entfernen"] or L["Beispieldaten ansehen"])
    end
    f.demoBtn:Refresh()
    f.demoBtn:HookScript("OnShow", function(self) self:Refresh() end)
    f.demoBtn:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Beispieldaten"],
            L["Fuellt Oasis mit Beispiel-Mitgliedern, Terminen, Chronik, Umfragen usw. Bleibt nur bei dir und wird nie an die Gilde gesendet."],
            L["Solange sie laufen, steht oben im Fenster 'Demo an'. Ein Klick dort oder hier entfernt alles wieder."] })
    end)
    f.demoBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- 0.5.996: Entwickler - Leitungsrechte (Gildenleitung, Offiziere, Raidleitung) per Knopf statt nur /oa testleitung
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
        self.label:SetText(on and L["Leitungsrechte aus"] or L["Leitungsrechte an"])
    end
    f.devLead:Refresh()
    f.devLead:HookScript("OnShow", function(self) self:Refresh() end)
    f.devLead:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Leitungsrechte (Entwickler)"],
            L["Du wirst auf diesem PC wie der Gildenmeister behandelt: Gildenleitung, Offiziers- und Raidleiter-Einstellungen sind offen."],
            L["Fuer die Gilde gespeicherte Aenderungen sehen die anderen NICHT - deren Oasis prueft deinen echten Rang."] })
    end)
    f.devLead:HookScript("OnLeave", function() GameTooltip:Hide() end)

    f.tiles = {}
    local labels = { L["Profile bekannt"], L["Rezeptlisten"], L["Legacy-Daten"], L["Letzter Abgleich"] }
    for i, lab in ipairs(labels) do
        local t = K.StatCard(f, lab)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 186, -118)
        t:SetSize(176, 56)
        f.tiles[i] = t
    end

    -- Gespeicherte Daten: 2 Spalten x 9 Zeilen, groesste zuerst
    local ROWS = 9
    local dc = cardH(f, 0, -188, 470, 56 + ROWS * 20 + 14, "stats", L["Gespeicherte Daten"], L["Was Oasis von der Gilde gerade kennt"])
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
    f.dataEmpty:SetText(L["Noch keine Daten von der Gilde."])

    -- Verbindung
    local cc = cardH(f, 484, -188, 254, 56 + ROWS * 20 + 14, "sync", L["Verbindung"], L["Austausch mit der Gilde"], true)
    f.netDot = cc:CreateTexture(nil, "ARTWORK")
    f.netDot:SetTexture(ns.MEDIA .. "dot")
    f.netDot:SetSize(9, 9)
    f.netDot:SetPoint("TOPLEFT", 14, -64)
    f.netState = K.Text(cc, 12, C.text)
    f.netState:SetPoint("LEFT", f.netDot, "RIGHT", 8, 0)
    f.net = {}
    for i, lab in ipairs({ L["Gesendet"], L["Empfangen"], L["Warteschlange"] }) do
        local n = K.Text(cc, 12, C.muted)
        n:SetPoint("TOPLEFT", cc, "TOPLEFT", 14, -90 - (i - 1) * 22)
        n:SetText(lab)
        local v = K.Text(cc, 12, C.text, "RIGHT")
        v:SetPoint("TOPRIGHT", cc, "TOPRIGHT", -14, -90 - (i - 1) * 22)
        f.net[i] = v
    end
    note(cc, L["Oasis tauscht Daten nur mit Gildenmitgliedern, die Oasis auch haben. Im Kampf und in Instanzen pausiert der Austausch."], 14, -162, 226, C.dim)
    -- Credits und Lizenzen unten (Kern/Start/Credits.lua, laedt nach dieser Datei - beim Aufbau des Reiters ist es da)
    if ns.Credits and ns.Credits.Build then
        local ok, e = pcall(ns.Credits.Build, f, 0, -188 - (56 + ROWS * 20 + 14) - 26, 738)
        if not ok then ns.err(L["Aufbau"] .. " settings/credits", e) end
    end
end
local function refreshStatus(f)
    local guild = IsInGuild() and (GetGuildInfo("player") or "?") or L["keine Gilde"]
    local _, rankName = GetGuildInfo("player")
    f.ver:SetText("OASIS  " .. K.hex(C.accent) .. ns.version .. "|r")
    f.guild:SetText(L["Gilde: "] .. "|cffffffff" .. guild .. "|r" .. (rankName and ("   |cff888888" .. rankName .. "|r") or ""))
    f.lead:SetText(ns.Admin and ns.Admin.CanManage() and L["Du hast Zugriff auf die Gildenleitung."] or "")
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
            -- letzte Zelle: Rest zusammenfassen
            local rest = 0
            for j = nr, #list do rest = rest + list[j][2] end
            row.name:SetText("|cff888888" .. (L["+%d weitere"]):format(#list - nr + 1) .. "|r")
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
    f.netState:SetText(blocked and L["Gerade pausiert (Kampf/Instanz)"] or L["Bereit"])
    f.net[1]:SetText(Comm.sent)
    f.net[2]:SetText(Comm.received)
    f.net[3]:SetText(Comm.QueueSize())
end

------------------------------------------------------------------------
local BUILD = { general = buildGeneral, pages = buildPages, look = buildLook, toasts = buildToasts, sound = buildSound, share = buildShare, char = buildChar, status = buildStatus }
local REFRESH = { general = refreshGeneral, pages = refreshPages, look = refreshLook, toasts = refreshToasts, sound = refreshSound, share = refreshShare, char = refreshChar, status = refreshStatus }
-- Reiter "Leiste": was die angeheftete Oasis-Leiste zeigt
local function buildBar(f)
    -- 0.5.549: Topbar-Seite im Glas-Stil, volle Breite (Seite scrollt); die echte Leiste ist waehrenddessen sichtbar
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
        if k == "mark" then return L["Auto-Marker (in Gruppe)"] end
        local def = ns.PageDef and ns.PageDef(k)
        return def and L[def.title] or k
    end
    -- Auswahl-Kachel (Titel, Text, optional Symbol + Zeichnung), Gruppe mit :Select
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
    -- kleine Bildschirm-Zeichnung fuer die Stil-Kacheln
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
    -- Schalter-Kachel (wie unter Oasis > Details)
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

    -- Wann erscheint die Leiste? -------------------------------------------
    -- 0.5.555: zwei Spalten - links Wann + Stil, rechts Leiste + Knoepfe
    local RXc, RX0 = 376, 392
    local function stackY(g, gap)
        -- Kacheln einer Gruppe untereinander statt nebeneinander
        for i, b in ipairs(g.btns) do
            local _, _, _, x, y = b:GetPoint(1)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", LX, g.y0 - (i - 1) * (b:GetHeight() + gap))
        end
    end
    cardH(f, 0, 0, 362, 50 + 3 * 54 + 8, "pin", L["Wann erscheint die Topbar?"], L["Die echte Leiste oben zeigt jede Aenderung sofort"])
    f.modeSeg = choiceGroup({
        { key = "collapse", text = L["Beim Schliessen"], desc = L["X am Fenster klappt ein"], icon = "home" },
        { key = "always", text = L["Immer"], desc = L["ab dem Einloggen da"], icon = "star_on" },
        { key = "off", text = L["Nie"], desc = L["nur das Fenster"], icon = "eye_off" },
    }, LX, -50, 330, 48, function(k)
        S().topbarMode = (k ~= "collapse") and k or nil
        if ns.ApplyTopbarMode then ns.ApplyTopbarMode() end
    end)
    f.modeSeg.y0 = -50
    stackY(f.modeSeg, 6)
    indexAdd(L["Wann erscheint die Topbar?"], f.modeSeg.btns[1], L["Topbar immer zeigen oder nie"])

    -- Stil ----------------------------------------------------------------
    local YS = -(50 + 3 * 54 + 8) - 14
    cardH(f, 0, YS, 362, 50 + 4 * 66 + 8, "brush", L["Stil"], L["Wie die Leiste aussieht - die echte Leiste oben aendert sich sofort"])
    f.styleSeg = choiceGroup({
        { key = "normal", text = L["Normal"], desc = L["schmal, frei verschiebbar"], draw = function(b, w, h) screen(b, w, h, false) end },
        { key = "compact", text = L["Kompakt"], desc = L["ganze Breite, mit Uhr"], draw = function(b, w, h) screen(b, w, h, true) end },
        { key = "minimal", text = L["Minimal"], desc = L["nur Symbole, ganz schmal"], draw = function(b, w, h) screen(b, w, h, false, "minimal") end },
        { key = "dock", text = L["Dock"], desc = L["grosse Symbole, wachsen beim Ueberfahren"], draw = function(b, w, h) screen(b, w, h, false, "dock") end },
    }, LX, YS - 50, 330, 60, function(k)
        S().miniStyle = (k ~= "normal") and k or nil
        if ns.UpdateMiniBarNow then pcall(ns.UpdateMiniBarNow) end
    end)
    f.styleSeg.y0 = YS - 50
    stackY(f.styleSeg, 6)
    indexAdd(L["Stil"], f.styleSeg.btns[2], L["Kompakte Topbar ueber die ganze Bildschirmbreite"])

    -- Leiste ---------------------------------------------------------------
    local Y2 = 0
    cardH(f, RXc, Y2, 362, 292, "settings", L["Leiste"], nil, true)
    f.autoHide = optTile(RX0, Y2 - 46, 330, "eye_off", "Einrollen", "nur der Rand bleibt sichtbar, Maus oben holt sie", "miniAutoHide",
        function() if ns.PlaceMiniBar then ns.PlaceMiniBar() end end)
    f.noLogo = optTile(RX0, Y2 - 110, 330, "chronicle", "Logo ausblenden", "Leiste ohne Schriftzug, Klick links klappt weiter auf", "miniNoLogo",
        function() if ns.UpdateMiniBar then ns.UpdateMiniBar() end end)
    rowLabel(f, L["Hintergrund"], RX0, Y2 - 182)
    f.miniAlpha = K.Slider(f, 200, 0.1, 1, 0.05, function() return S().miniAlpha or 1 end,
        function(v) S().miniAlpha = v if ns.ApplyMiniAlpha then ns.ApplyMiniAlpha() end end,
        function(v) return (L["%d %%"]):format(v * 100 + 0.5) end)
    f.miniAlpha:SetPoint("TOPLEFT", RX0 + 110, Y2 - 180)
    indexAdd(L["Topbar-Transparenz"], f.miniAlpha, L["Wie durchsichtig die Topbar ist"])
    rowLabel(f, L["Groesse"], RX0, Y2 - 214)
    f.miniScale = K.Slider(f, 200, 0.6, 1.6, 0.05, function() return S().miniScale or 1 end,
        function(v) S().miniScale = v if ns.UpdateMiniBarNow then pcall(ns.UpdateMiniBarNow) elseif ns.UpdateMiniBar then ns.UpdateMiniBar() end end,
        function(v) return (L["%d%%"]):format(v * 100 + 0.5) end)
    f.miniScale:SetPoint("TOPLEFT", RX0 + 110, Y2 - 212)
    indexAdd(L["Topbar-Groesse"], f.miniScale, L["Wie gross die Topbar ist"])
    local c = K.Button(f, L["Jetzt einklappen"], 158, 24, "ghost", function() if ns.Collapse then ns.Collapse(true) end end)
    c:SetPoint("TOPLEFT", RX0, Y2 - 248)
    local r = K.Button(f, L["Position zuruecksetzen"], 164, 24, "ghost", function()
        S().miniPos = nil
        if ns.HideMiniBar and ns.ShowMiniBar then ns.HideMiniBar() ns.ShowMiniBar() end
    end)
    r:SetPoint("LEFT", c, "RIGHT", 8, 0)

    -- Knoepfe in der Leiste ------------------------------------------------
    local keys = {}
    for _, k in ipairs(ns.MINI_QUICK_ALL or {}) do if ns.PageDef and ns.PageDef(k) then keys[#keys + 1] = k end end
    keys[#keys + 1] = "mark"
    for _, pq in ipairs(ns.MINI_QUICK_PANELS or {}) do keys[#keys + 1] = pq.key end
    local PER, CW, CHh = 2, 162, 28
    local Y3 = Y2 - 306
    cardH(f, RXc, Y3, 362, 58 + math.ceil(#keys / PER) * (CHh + 5), "modules", L["Knoepfe in der Leiste"], L["Klick schaltet einen Knopf an oder aus"], true)
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
        indexAdd(labelOf(k), b, L["Knoepfe in der Leiste"])
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
table.insert(TABS, #TABS, { key = "bar", text = "Topbar" })

-- weitere Reiter aus anderen Modulen (vor dem ersten Oeffnen der Einstellungen anmelden)
function ns.AddSettingsTab(key, text, build, refresh)
    if BUILD[key] then return end
    table.insert(TABS, #TABS, { key = key, text = text })   -- vor "Status"
    BUILD[key] = build
    REFRESH[key] = refresh or function() end
end
ns.SettingsHelpers = { section = section, note = note, toggle = toggle, rowLabel = rowLabel, cardH = cardH }

-- Abstaende zusammenziehen: je Spalte die Elemente der Reihe nach enger stapeln (nur grosse Luecken)
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
    -- zwei Spalten (links/rechts); Elemente derselben Zeile ruecken gemeinsam
    for _, it in ipairs(items) do local cx = it.x < 380 and 0 or 1 cols[cx] = cols[cx] or {} table.insert(cols[cx], it) end
    local maxShift = 0
    for _, list in pairs(cols) do
        table.sort(list, function(a, b) if a.y ~= b.y then return a.y > b.y end return a.x < b.x end)
        local shift = 0
        for i, it in ipairs(list) do
            if i > 1 then
                local prev = list[i - 1]
                local gap = (prev.y - it.y) - prev.h
                local want = (prev.h <= 2) and 8 or 6    -- nach Trennlinien etwas mehr
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
-- Themenwahl: Gildenorganisation, soziale Aktivitaeten und persoenliche Helfer getrennt.
-- Design, Benachrichtigungen, Datenschutz und technische Modulverwaltung haben eigene Themen.
local GROUPS = {
    { key = "start", text = "Uebersicht", icon = "home", tabs = { "quick" },
        desc = "Waehle ein Thema oder suche direkt nach einer Einstellung." },
    { key = "guild", text = "Gilde & Organisation", icon = "modules", tabs = { "guildtools" },
        desc = "Mitglieder, Termine, Raids, Handwerk und gemeinsame Gildenziele." },
    { key = "social", text = "Socializing", icon = "social", tabs = { "socialtools", "greet" },
        desc = "Leute kennenlernen, Gruppen finden und gemeinsam etwas unternehmen." },
    { key = "help", text = "Mein Komfort", icon = "checklist", tabs = { "personaltools", "comfort", "helpers", "gamechat", "mapset", "tips", "keys" },
        desc = "Persoenliche Spielhilfen, Chat, Karte und Tooltips fuer deinen Alltag." },
    { key = "look", text = "Aussehen & Bedienung", icon = "brush", tabs = { "look", "general", "bar" },
        desc = "Design, Schrift, Fenster und Leisten an deinen Spielstil anpassen." },
    { key = "notify", text = "Hinweise & Klang", icon = "announce", tabs = { "toasts", "sound" },
        desc = "Bestimme, was du mitbekommst, wie es aussieht und wie es klingt." },
    { key = "char", text = "Profil & Datenschutz", icon = "profile", tabs = { "char", "share", "lexport" },
        desc = "Charaktere zuordnen, geteilte Daten kontrollieren und Einstellungen sichern." },
    { key = "adv", text = "System & Module", icon = "settings", tabs = { "modules", "status", "perf" },
        desc = "Module laden, Verbindung pruefen und Leistung einstellen." },
}
for _, entry in ipairs({
    { "guildtools", "Gildenfunktionen", "guild" },
    { "socialtools", "Miteinander", "social" },
    { "personaltools", "Meine Werkzeuge", "personal" },
}) do
    local scope = entry[3]
    BUILD[entry[1]] = function(f) buildPages(f, scope) end
    REFRESH[entry[1]] = refreshPages
    TABS[#TABS + 1] = { key = entry[1], text = entry[2] }
end
local HIDDEN_TABS = { lists = true, pages = true }   -- weiter aufrufbar (alte Links), aber ohne eigenen Reiter
local function tabText(key)
    for _, t in ipairs(TABS) do if t.key == key then return L[t.text] end end
    return key
end
-- Reiter einer Gruppe, die es wirklich gibt (Module melden sich per AddSettingsTab an; unbekannte -> Spielhilfen)
local function groupTabs(g)
    if g.dev and not (ns.IsDev and ns.IsDev()) then return {} end
    local out, known = {}, {}
    for _, gg in ipairs(GROUPS) do for _, k in ipairs(gg.tabs) do known[k] = true end end
    for _, k in ipairs(g.tabs) do if BUILD[k] then out[#out + 1] = k end end
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
    if key == "lists" then key = "mapset" elseif key == "pages" then key = "guildtools" end   -- alte Links auf "Listen & Karte"
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
        -- 0.5.538: jede Seite liegt in einem Rollbereich - ist der Inhalt hoeher als das Fenster, scrollt das Mausrad
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
        if not ok then ns.err(L["Aufbau"] .. " settings/" .. key, e) end
        -- 0.6.476: Kaesten mit ausgeblendeten Schaltern zuerst zusammenruecken und um die Luecke kuerzen
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
        -- nach Neuaufbau (Design-Wechsel o.ae.) dort weitermachen, wo man war
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
        -- weich hereingleiten (12 px von rechts) + einblenden
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
        -- 0.5.561: Endposition immer sicher setzen (unterbrochenes Hereingleiten liess den Inhalt eingerueckt stehen)
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
-- Einstellungen auf einem bestimmten Reiter oeffnen (z. B. Klick aufs Logo)
function ns.OpenSettingsTab(key)
    if ns.db then ns.db.settings.settingsTab = key end
    ns.ShowPage("settings")
    if page then setTab(key) end
end
-- Einstellungen eines Bereichs oeffnen (z. B. "map" aus der Leiste unter der Weltkarte); holt Oasis vor die Karte
function ns.OpenAreaSettings(area)
    -- Karten-Schalter haben seit 0.5.995 einen eigenen Reiter
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
-- 0.5.995: Schnellstart, Tooltips, Karte
-- Schnellstart = das Wichtigste + Wegweiser zu allen Gruppen; Tooltips und Karte sammeln, was vorher
-- verstreut in sechs Bereichen und zwei Reitern stand.
------------------------------------------------------------------------
-- Glas-Karte ueber die volle Breite mit Titel; liefert die Karte und die erste freie Zeile
local function wideCard(f, y, icon, title, sub)
    local c = cardH(f, 0, y, 740, 100, icon, title, sub)
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, y)
    return c, y - (sub and 62 or 46)
end
-- Zwischenueberschrift in einer Karte (gleiche Art wie in den Bereichen)
local function subHead(f, text, y)
    rowLabel(f, "|cffe8b44a" .. L[text] .. "|r", 14, y)
    return y - 28
end
-- Liste { Text, Schluessel, Erklaerung, nachher, Standard an } als Schalter untereinander
-- 0.6.0: zweispaltig (links 14, rechts 384) - einspaltig blieb die halbe Karte leer
local function toggleList(f, list, y, cols)
    cols = cols or 2
    -- 0.6.471: seltene Schalter nur mit "Alle Optionen zeigen"
    local vis = {}
    for _, o in ipairs(list) do
        if advHidden(o[2]) then
            -- unsichtbar mitbauen (ohne Platz): so findet die Suche sie und schaltet "Alle Optionen" ein
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

-- 0.6.115: "Diese Seite zuruecksetzen" - jeder Schalter der Seite auf seinen Standard (Kern-Standard, Datenschutz-
-- Standard an, oder der beim Schalter vermerkte Standard an); danach Seite neu zeichnen
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
    if K.Toast then K.Toast(L["Zurueckgesetzt"], L["Die Schalter dieser Seite stehen wieder auf Standard."], C.accent) end
end
function resetButton(f, y, after)   -- 0.6.180: oben vorab als local deklariert (Seite 'Teilen' rief sie vorher auf -> nil)
    -- zweistufig: erster Klick fragt nach, zweiter (innerhalb von 4 s) setzt zurueck
    local b
    b = K.Button(f, L["Diese Seite zuruecksetzen"], 190, 22, "ghost", function(self)
        if self.armed and GetTime() - self.armed < 4 then
            self.armed = nil
            self:SetLabel(L["Diese Seite zuruecksetzen"])
            resetPage(f, after)
            return
        end
        self.armed = GetTime()
        self:SetLabel(L["Wirklich? Nochmal klicken"])
        C_Timer.After(4, function() if b.armed and GetTime() - b.armed >= 3.9 then b.armed = nil b:SetLabel(L["Diese Seite zuruecksetzen"]) end end)
    end)
    b:SetPoint("TOPLEFT", 0, y)
    return b
end

local function buildQuick(f)
    f.noCompact = true
    f.t = {}
    -- Das Wichtigste ----------------------------------------------------
    local c, y = wideCard(f, 0, "settings", L["Das Wichtigste"], L["Die Schalter, die fast jeder einmal braucht - alles andere findest du unten nach Themen sortiert"])
    -- Sprache steht oben im Fenster (Flagge) immer bereit - hier nicht doppelt
    y = toggleList(f, {
        { "Hinweise anzeigen", "toasts", "Kurze Meldungen am Bildschirmrand: Auftraege, Termine, Gruppensuchen, Durchsagen ..." },
        { "Sounds abspielen", "sound", "Alle Oasis-Klaenge an oder aus" },
        { "Im Kampf ausblenden", "hideInCombat", "Das Oasis-Fenster verschwindet, sobald ein Kampf beginnt" },
        { "Minimap-Knopf anzeigen", "minimap", "Linksklick oeffnet Oasis, Rechtsklick die Einstellungen", function() if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end },
        { "Position auf der Weltkarte teilen", "shareMap", "Gildenkarte und Minimap-Punkte der anderen. Standard: aus" },
        { "Emojis im Chat anzeigen", "chatEmoji", "Aus :lol: oder <3 wird ein Bild" },
        { "Oasis-Zeilen im Item-Tooltip", "tipOasis", "Gesucht von, Auftraege, Gildenbank und Herkunft unter jedem Item-Tooltip", nil, true },
        { "Animationen reduzieren", "noAnim", "Kein Einblenden und Hochzaehlen - alles erscheint sofort" },
        { "Gildenfenster-Taste (J) oeffnet Oasis", "guildKeyOasis", "Statt Blizzards Gildenfenster oeffnet und schliesst die Taste das Oasis-Fenster", function() if ns.Keybinds and ns.Keybinds.ApplyGuildKey then ns.Keybinds.ApplyGuildKey() end end },
    }, y)
    c:SetHeight(-y + 4)
    -- Wegweiser ---------------------------------------------------------
    y = y - 18
    local h = K.Text(f, 10, C.dim)
    h:SetPoint("TOPLEFT", 0, y)
    h:SetText(K.Upper(L["Alle Einstellungen nach Thema"]))
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
    -- Rundgang erneut starten (Onboarding.lua)
    if ns.Onboarding and ns.Onboarding.Show then
        local tb = K.Button(f, L["Rundgang starten"], 140, 22, "ghost", function() ns.Onboarding.Show() end)
        tb:SetPoint("TOPLEFT", 0, y - math.ceil(#f.tiles / 3) * 64 - 8)
    end
end
local function refreshQuick(f)
    for _, t in ipairs(f.t) do if t.Refresh then pcall(t.Refresh, t) end end
    local l = ns.langByKey and ns.langByKey[ns.lang]
    if l and f.lang then
        local auto = (S().lang or "auto") == "auto"
        f.lang:SetLabel("|T" .. ns.MEDIA .. "flags\\" .. l.flag .. ":12:16:0:0:64:64:0:64:0:48|t  " .. (auto and (L["Wie das Spiel"] .. " (" .. l.name .. ")") or l.name))
    end
end

-- Tooltips: alle Zusatzzeilen an einer Stelle (vorher bei Wunschliste, Handwerk, Gildenbank, Softres, Spielerbuch und Chat)
local function buildTips(f)
    f.noCompact = true
    f.t = {}
    local c, y = wideCard(f, 0, "wants", L["Item-Tooltip"], L["Was Oasis unter Gegenstaenden anzeigt"])
    y = toggleList(f, {
        { "Oasis-Zeilen im Item-Tooltip", "tipOasis", "Hauptschalter: Gesucht von, Auftraege, Gilden-Preis, Gildenbank und Herkunft", nil, true },
        { "Gesucht von im Item-Tooltip", "tipWanted", "Wer aus der Gilde das Item auf der Wunschliste hat", nil, true },
        { "Herstellbar von im Item-Tooltip", "tipCrafters", "Zeigt im Tooltip, wer in der Gilde das Item herstellen kann", nil, true },
        { "Gildenbank-Bestand im Item-Tooltip", "tipBank", "Zeigt im Tooltip, wie viele davon in der Gildenbank liegen", nil, true },
        { "Material-Tooltip: wofuer die Gilde es braucht", "tipReagent", "Unter Materialien: in welchen Rezepten der Gilde sie stecken (Shift = alle)", nil, true },
        { "Reservierungen im Item-Tooltip zeigen", "srTooltip", "Zeigt im Item-Tooltip, wer das Item fuer einen anstehenden Termin reserviert hat", nil, true },
        { "Tooltip-Zeile nur in einer Gruppe", "srTooltipGroupOnly", "Die Reservierungs-Zeile erscheint nur, wenn du in einer Gruppe oder einem Schlachtzug bist" },
    }, y)
    c:SetHeight(-y + 4)
    y = y - 18
    local c2
    local top2 = y
    c2, y = wideCard(f, y, "profile", L["Spieler-Tooltip"], L["Was Oasis unter Spielern anzeigt"])
    y = toggleList(f, {
        { "Oasis-Nutzer im Tooltip markieren", "oasisMark", "Kleines Zeichen im Tooltip bei Mitgliedern, die Oasis nutzen", nil, true },
        { "Bewertung im Spieler-Tooltip zeigen", "allyTooltip", "Deine Bewertung, Notiz und die Erfahrungen der Gilde beim Drueberfahren", nil, true },
    }, y)
    c2:SetHeight(top2 - y + 4)
    resetButton(f, y - 16)
end
local function refreshTips(f) for _, t in ipairs(f.t) do if t.Refresh then pcall(t.Refresh, t) end end end

-- Karte: alles zu Weltkarte und Minimap (vorher Bereiche > Mitglieder > Karte, dazu Listen & Karte und Friedhof)
local function buildMapTab(f)
    f.noCompact = true
    f.t, f.refreshers = {}, {}
    local c, y = wideCard(f, 0, "map", L["Gilde auf der Karte"], L["Was du teilst und was du von der Gilde siehst"])
    y = toggleList(f, {
        { "Namen auf der Weltkarte", "mapNames", nil, updPins },
        { "Gildenpunkte auf der Minimap", "minimapDots", nil, function() if ns.Map then ns.Map.UpdateMinimap() end end },
        { "Heatmap auf der Weltkarte", "mapHeat", "Wo die Gilde unterwegs war", updPins },
        { "Totenkoepfe auf der Karte", "deathPins", "Wo Gildenmitglieder gestorben sind" },
        { "Weltkarte aufdecken", "mapReveal", "Zeigt unerforschte Gebiete abgedunkelt an (Standard aus)", function() if ns.ComfortPlus then ns.ComfortPlus.ApplyReveal() end end },
    }, y)
    -- die ausfuehrlichen Karten-Schalter (Sammelkarte, Extras, Symbole) aus Modules/Settings "map"
    if PAGE_EXTRA.map then
        y = y - 8
        local ok, ny = pcall(PAGE_EXTRA.map, f, y)
        if ok and type(ny) == "number" then y = ny elseif not ok then ns.err(L["Aufbau"] .. " settings/mapset", ny) end
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
-- 0.6.114: Suche mit Synonymen, ohne Umlaut-Unterschied, mit Reiter-/Bereichsnamen und sortiert
------------------------------------------------------------------------
local function norm(x)
    x = tostring(x or ""):lower()
    x = x:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (x:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")
        :gsub("\195\132", "ae"):gsub("\195\150", "oe"):gsub("\195\156", "ue"))
end
-- Wortgruppen: sucht man eines, zaehlen alle
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
    -- Reiter selbst
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
ns.SettingsSearch = searchHits   -- fuer Tests

ns.RegisterPage({
    key = "settings", title = "Einstellungen", order = 8, topbar = true,
    sub = "Oasis an deinen Stil anpassen",
    build = function(p)
        page = p
        wipe(INDEX)
        p.SetTab = setTab
        p.tabs = {}
        -- Suche, Themenwahl und Unterseiten haben jeweils eine eigene Zeile.
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
                -- 0.6.478: Bereiche oben in Akzentfarbe getoent (heben sich von den grauen Unterreitern ab)
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
            -- Bei Groessenaenderungen bleibt der Inhalt unter den umgebrochenen Unterreitern.
            local sc = self.scrolls and self.scrolls[key]
            if sc then sc:ClearAllPoints() sc:SetPoint("TOPLEFT", 0, self.contentTop) sc:SetPoint("BOTTOMRIGHT") end
            S().settingsSub = S().settingsSub or {}
            S().settingsSub[g.key] = key
        end
        justify()
        C_Timer.After(0, justify)
        -- alte Schnittstelle (andere Module/Tests rufen p.seg:Select)
        p.seg = { Select = function(_, k) if k ~= p.tab then setTab(k) end end, Hide = function() end, Show = function() end,
            GetWidth = function() return nav:GetWidth() end }
        -- Suche: findet jede Einstellung, springt hin und laesst sie aufleuchten
        -- 0.5.563: jede Aenderung bestaetigt sich kurz mit einem Haken
        p.saved = K.Text(p, 11, C.good or { 0.4, 0.86, 0.62 }, "RIGHT")
        p.saved:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. L["Gespeichert"])
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
        p.find = K.Input(p, 170, L["Einstellung suchen ..."], function(t)
            t = (t or ""):lower()
            local res = p.findRes
            for _, b in ipairs(res.btns) do b:Hide() end
            if #t < 2 then res:Hide() return end
            -- alle Reiter einmal aufbauen, damit alles im Index ist
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
                        -- Bereichs-Einstellung: Bereich oeffnen und den frisch gebauten Schalter suchen
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
                        -- Fundstelle kurz markieren; reduzierte Bewegung bleibt statisch.
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
        -- 0.6.471: "Alle Optionen" - zeigt auch die selten gebrauchten Schalter (Seiten werden neu aufgebaut)
        p.allOpt = K.Toggle(p, L["Alle Optionen"], function() return S().setAll and true or false end, function(v)
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
        p.allOpt:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Alle Optionen"], L["Zeigt auch selten gebrauchte Schalter. Aus: nur das Wichtigste."] }) end)
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
        p.findRes.none:SetText(L["Nichts gefunden."])
        p.findRes:Hide()
        local line = K.Divider(p)
        line:SetPoint("TOPLEFT", 0, -32)
        line:SetPoint("TOPRIGHT", 0, -32)
        -- 0.5.995: nach dem Umbau einmal auf dem Schnellstart beginnen
        if not S().settingsV2 then S().settingsV2 = true S().settingsTab = "quick" S().settingsSub = nil end
        local tab = S().settingsTab
        -- gemerkter Reiter nur, wenn es ihn noch gibt (z.B. "Teilen" ist entfallen)
        local known = false
        for _, t in ipairs(TABS) do if t.key == tab and not HIDDEN_TABS[tab] then known = true end end
        setTab(known and REFRESH[tab] and tab or "quick")
    end,
    refresh = function(p)
        local fr = p.tabs[p.tab]
        if fr and REFRESH[p.tab] then
            local ok, e = pcall(REFRESH[p.tab], fr)
            if not ok then ns.err(L["Seite"] .. " settings/" .. p.tab, e) end
        end
    end,
})
-- 0.5.733: nach einer Groessenaenderung (Fenstergroesse/Skalierung) die Rollbereiche neu vermessen - sonst bleiben die alten Hoehen
-- stehen und das Mausrad scrollt nicht mehr
local function remeasureAll()
    for _, sc in pairs(page and page.scrolls or {}) do
        if sc.Measure then pcall(sc.Measure) end
    end
end
ns.Settings = { SetTab = function(k) ns.ShowPage("settings") setTab(k) end, Remeasure = remeasureAll }
ns.Listen("BRAND", function() ns.RefreshPage("settings") end)

-- Minimap-Zaehler: offene Auftraege fuer mich
ns.Listen("BADGES", function()
    ns.SetMinimapBadge((ns.Crafting and ns.Crafting.badge) or 0)
end)

-- englische Befehle als Alias
ns.slash.award = ns.slash.vergabe
ns.slash.campfire = ns.slash.lagerfeuer
ns.slash.roll = ns.slash.wuerfeln
ns.slash.sound = function() ns.Settings.SetTab("sound") end

-- Oasis: Schafweide (0.6.539) - jedes Gildenmitglied mit Oasis laeuft als Schaf ueber die Wiese.
-- Je hoeher der Oasis-Rang, desto groesser das Schaf; ab bestimmten Raengen gibt es Farben (Skins).
-- Den eigenen Skin meldet jeder selbst (Sammlung "sheep", OWNED); beim Anzeigen wird der Rang des Besitzers
-- geprueft - wer sich einen Skin ueber seinem Rang einstellt, erscheint bei den anderen trotzdem weiss.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gemeinschaft", function()
local K, C, L = ns.K, ns.K.C, ns.L
local Store = ns.Store
local Weide = {}
ns.Weide = Weide

local SHEEP_NPC = 1933        -- Schaf (wie beim Todeswuerfeln)
local SHEEP_DISPLAY = 856     -- Schaf-Modell (Verwandlung), geht auch ohne Kreatur im Zwischenspeicher
local MAX_SHEEP = 40          -- mehr Modelle kosten zu viel Leistung
local ART = "Interface\\AddOns\\Oasis_Guild\\Media\\weide_bg"   -- Bild nur im Gildenmodul
local MEADOW_TOP, MEADOW_BOTTOM = 0.56, 0.96   -- Laufbereich (Fuesse), Anteil der Hoehe von oben: hinten an den Baeumen bis ganz vorne - nie im Himmel

-- Skins: Licht-Farbe auf dem Schafmodell. lvl = ab Oasis-Rang
Weide.SKINS = {
    { key = "white", text = "Weiss", lvl = 1, amb = { 1, 1, 1 }, ai = 0.8, dif = { 1, 0.95, 0.9 }, di = 0.9 },
    { key = "cream", text = "Creme", lvl = 10, amb = { 1, 0.9, 0.7 }, ai = 0.8, dif = { 1, 0.85, 0.6 }, di = 0.9 },
    { key = "grey", text = "Grau", lvl = 20, amb = { 0.55, 0.55, 0.58 }, ai = 0.7, dif = { 0.6, 0.6, 0.62 }, di = 0.7 },
    { key = "pink", text = "Rosa", lvl = 30, amb = { 1, 0.6, 0.78 }, ai = 0.85, dif = { 1, 0.55, 0.75 }, di = 0.9 },
    { key = "blue", text = "Himmelblau", lvl = 40, amb = { 0.5, 0.72, 1 }, ai = 0.85, dif = { 0.5, 0.7, 1 }, di = 0.9 },
    { key = "black", text = "Schwarzes Schaf", lvl = 50, amb = { 0.12, 0.11, 0.13 }, ai = 0.6, dif = { 0.22, 0.2, 0.24 }, di = 0.5 },
    { key = "green", text = "Moosgruen", lvl = 60, amb = { 0.5, 0.95, 0.45 }, ai = 0.85, dif = { 0.45, 0.9, 0.4 }, di = 0.9 },
    { key = "gold", text = "Gold", lvl = 70, amb = { 1, 0.8, 0.3 }, ai = 0.9, dif = { 1, 0.75, 0.25 }, di = 1 },
    { key = "violet", text = "Lila", lvl = 80, amb = { 0.7, 0.45, 1 }, ai = 0.85, dif = { 0.65, 0.4, 1 }, di = 0.9 },
    { key = "rainbow", text = "Regenbogen", lvl = 100, rainbow = true },
}
local BY = {}
for _, s in ipairs(Weide.SKINS) do BY[s.key] = s end
-- 0.6.540: Verkleidungen - andere Tiere ab hoeheren Raengen (Kreatur-IDs aus der Spielwelt; laedt eine nicht, bleibt es ein Schaf)
Weide.FORMS = {
    { key = "sheep", text = "Schaf", lvl = 1 },
    { key = "rabbit", text = "Hase", lvl = 15, npc = 721 },
    { key = "chicken", text = "Huhn", lvl = 25, npc = 620 },
    { key = "toad", text = "Kroete", lvl = 35, npc = 1420 },
    { key = "squirrel", text = "Eichhoernchen", lvl = 45, npc = 1412 },
    { key = "prairie", text = "Praeriehund", lvl = 55, npc = 2620 },
    { key = "fawn", text = "Rehkitz", lvl = 65, npc = 890 },
    { key = "cow", text = "Kuh", lvl = 75, npc = 2442 },
    { key = "deer", text = "Hirsch", lvl = 90, npc = 883 },
}
local FBY = {}
for _, f in ipairs(Weide.FORMS) do FBY[f.key] = f end

local function myRank() return ns.Rank and ns.Rank.Mine and ns.Rank.Mine().level or 1 end
local function rankOf(name)
    if ns.isMe(name) then return myRank() end
    return (ns.Rank and ns.Rank.Of and ns.Rank.Of(name)) or 1
end
-- Skin eines Mitglieds - nur wenn sein Rang ihn erlaubt (sonst weiss)
function Weide.SkinOf(name, lvl)
    local key
    if ns.isMe(name) then key = ns.db.settings.sheepSkin
    else local r = Store.Get("sheep", "shp-" .. ns.NameKey(name)) key = r and r.skin end
    local s = BY[key or ""]
    if not s or (lvl or 1) < s.lvl then return BY.white end
    return s
end
function Weide.FormOf(name, lvl)
    local key
    if ns.isMe(name) then key = ns.db.settings.sheepForm
    else local r = Store.Get("sheep", "shp-" .. ns.NameKey(name)) key = r and r.form end
    local f = FBY[key or ""]
    if not f or (lvl or 1) < f.lvl then return FBY.sheep end
    return f
end
function Weide.SetMyForm(key)
    local f = FBY[key]
    if not f or myRank() < f.lvl then return false end
    ns.db.settings.sheepForm = key
    Weide.Report()
    return true
end
function Weide.SetMySkin(key)
    local s = BY[key]
    if not s or myRank() < s.lvl then return false end
    ns.db.settings.sheepSkin = key
    Weide.Report()
    return true
end

-- 0.6.540 Gildotchi: drei Beduerfnisse, jedes faellt von 100 auf 0 in "span" Sekunden nach der letzten Pflege
Weide.NEEDS = {
    { key = "f", text = "Satt", act = "Fuettern", span = 24 * 3600, cd = 3 * 3600, say = "Hunger!" },
    { key = "j", text = "Gluecklich", act = "Streicheln", span = 12 * 3600, cd = 1 * 3600, say = "Streichel mich!" },
    { key = "c", text = "Gepflegt", act = "Buersten", span = 48 * 3600, cd = 8 * 3600, say = "Ich bin ganz zerzaust!" },
}
local function careRec(name)
    if ns.isMe(name) then ns.db.settings.gildotchi = ns.db.settings.gildotchi or {} return ns.db.settings.gildotchi end
    local r = Store.Get("sheep", "shp-" .. ns.NameKey(name))
    return r or {}
end
-- Werte 0-100 je Beduerfnis + Laune (Durchschnitt); ohne jede Pflege startet ein Schaf halb zufrieden
function Weide.Needs(name)
    local r, out, sum = careRec(name), {}, 0
    for _, n in ipairs(Weide.NEEDS) do
        local ts = tonumber(r[n.key])
        local v = ts and math.max(0, math.min(100, 100 - (ns.now() - ts) / n.span * 100)) or 50
        out[n.key] = v
        sum = sum + v
    end
    out.mood = sum / #Weide.NEEDS
    return out
end
function Weide.MoodText(m)
    if m >= 75 then return "Gluecklich", C.mint elseif m >= 45 then return "Zufrieden", C.text
    elseif m >= 20 then return "Quengelig", C.amber or C.accent else return "Traurig", C.accent end
end
function Weide.Report()
    if not IsInGuild() then return end
    local g = ns.db.settings.gildotchi or {}
    Store.Put("sheep", { id = "shp-" .. ns.NameKey(ns.me()), skin = ns.db.settings.sheepSkin, form = ns.db.settings.sheepForm,
        f = g.f, j = g.j, c = g.c, by = ns.me(), ts = ns.now() })
end
local report = function() Weide.Report() end
local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return ("%d Std. %d Min."):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%d Min."):format(math.max(1, math.ceil(sec / 60)))
end
-- Pflegen: true oder false + Restzeit in Sekunden
function Weide.Care(key)
    local g = careRec(ns.me())
    for _, n in ipairs(Weide.NEEDS) do
        if n.key == key then
            local left = (tonumber(g[key]) or 0) + n.cd - ns.now()
            if left > 0 then return false, left end
            g[key] = ns.now()
            report()
            return true
        end
    end
    return false, 0
end

-- Wer steht auf der Weide? Mains mit Oasis, in den letzten 14 Tagen gesehen
function Weide.Flock()
    local out = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local p = ns.db.members and ns.db.members[m.name]
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        local uses = ns.isMe(m.name) or (type(p) == "table" and p.v and ns.now() - (p.seen or 0) < 14 * 86400)
        if uses and not isAlt then
            local lvl = rankOf(m.name)
            out[#out + 1] = { name = m.name, lvl = lvl, online = m.online or ns.isMe(m.name) }
        end
    end
    if not IsInGuild() or #out == 0 then out[#out + 1] = { name = ns.me(), lvl = myRank(), online = true } end
    table.sort(out, function(a, b) if a.lvl ~= b.lvl then return a.lvl > b.lvl end return a.name < b.name end)
    return out
end

local function light(m, s, r, g, b)
    if not (m.SetLight and CreateVector3D and CreateColor) then return end
    local amb, dif, ai, di = s.amb, s.dif, s.ai, s.di
    if s.rainbow then amb, dif, ai, di = { r, g, b }, { r, g, b }, 0.85, 0.9 end
    pcall(m.SetLight, m, true, {
        omnidirectional = false, point = CreateVector3D(-0.6, 1, -0.6),
        ambientIntensity = ai, ambientColor = CreateColor(amb[1], amb[2], amb[3]),
        diffuseIntensity = di, diffuseColor = CreateColor(dif[1], dif[2], dif[3]),
    })
end

------------------------------------------------------------------------
-- Ein Schaf: eigenes Modell, laeuft zu zufaelligen Zielen, bleibt mal stehen und grast
------------------------------------------------------------------------
local function newSheep(field)
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, field)
    if not ok or not m then return nil end
    m:EnableMouse(true)
    function m:LoadSheep()
        pcall(self.ClearModel, self)
        local f = self.form
        if f and f.npc then
            pcall(self.SetCreature, self, f.npc)
        else
            local ok = self.SetDisplayInfo and pcall(self.SetDisplayInfo, self, SHEEP_DISPLAY)
            if not ok then pcall(self.SetCreature, self, SHEEP_NPC) end
        end
        C_Timer.After(0.5, function()
            local okm, id = pcall(self.GetModelFileID, self)
            if not okm or not id or id == 0 then
                -- Tier nicht geladen (noch nicht im Zwischenspeicher): Schaf nehmen
                local ok2 = self.SetDisplayInfo and pcall(self.SetDisplayInfo, self, SHEEP_DISPLAY)
                if not ok2 then pcall(self.SetCreature, self, SHEEP_NPC) end
            end
        end)
    end
    m:LoadSheep()
    m:SetScript("OnShow", function(self)
        local okm, id = pcall(self.GetModelFileID, self)
        if not okm or not id or id == 0 then self:LoadSheep() end
    end)
    -- Name (dezent) und darueber die Sprechblase
    m.name = K.Text(field, 10, C.text, "CENTER")
    m.name:SetPoint("BOTTOM", m, "TOP", 0, -10)
    m.name:SetDrawLayer("OVERLAY", 6)
    m.name:SetShadowOffset(1, -1)
    m.name:SetShadowColor(0, 0, 0, 0.9)
    m.name:SetAlpha(0.75)
    m.say = K.Text(field, 11, C.text, "CENTER")
    m.say:SetPoint("BOTTOM", m.name, "TOP", 0, 5)
    m.say:SetDrawLayer("OVERLAY", 7)
    m.sayBg = field:CreateTexture(nil, "OVERLAY")
    m.sayBg:SetColorTexture(0, 0, 0, 0.55)
    m.sayBg:SetPoint("TOPLEFT", m.say, "TOPLEFT", -6, 3)
    m.sayBg:SetPoint("BOTTOMRIGHT", m.say, "BOTTOMRIGHT", 6, -3)
    m.say:Hide() m.sayBg:Hide()
    m.sayIn = 3 + math.random() * 20
    m:SetScript("OnModelLoaded", function(self)
        pcall(self.SetPortraitZoom, self, 0)
        pcall(self.SetCamDistanceScale, self, 1.1)
        pcall(self.SetPosition, self, 0, 0, 0)
        if self.skin then light(self, self.skin, 1, 1, 1) end
        self.anim = nil
    end)
    m:SetScript("OnEnter", function(self)
        if not self.who then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.short(self.who.name), 1, 1, 1)
        GameTooltip:AddLine((L["Oasis-Rang %d"]):format(self.who.lvl), C.accent2[1], C.accent2[2], C.accent2[3])
        GameTooltip:AddLine(L[self.form and self.form.text or "Schaf"] .. " - " .. L[self.skin and self.skin.text or "Weiss"], 0.8, 0.8, 0.8)
        local nd = Weide.Needs(self.who.name)
        local mt, mc = Weide.MoodText(nd.mood)
        GameTooltip:AddLine(L["Laune"] .. ": " .. L[mt], mc[1], mc[2], mc[3])
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return m
end
local function setAnim(m, id)
    if m.anim ~= id then m.anim = id pcall(m.SetAnimation, m, id) end
end
local function pickTarget(s)
    s.tx = math.max(0.02, math.min(0.98, s.x + (math.random() - 0.5) * 0.6))
    s.ty = math.max(0, math.min(1, s.y + (math.random() - 0.5) * 0.7))   -- y: 0 = hinten (klein), 1 = vorne (gross)
    s.wait = nil
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local LIST_W = 250
ns.RegisterPage({
    key = "pasture", title = "Gildotchi", order = 7.64,
    sub = "Jedes Mitglied mit Oasis hat ein Schaf - fuettern, streicheln, buersten. Je hoeher der Rang, desto groesser, ab hoeheren Raengen neue Farben.",
    build = function(p)
        -- Wiese
        local field = CreateFrame("Frame", nil, p)
        field:SetPoint("TOPLEFT", 0, 0)
        field:SetPoint("BOTTOMRIGHT", -(LIST_W + 14), 96)
        -- kein SetClipsChildren: 3D-Modelle werden in beschnittenen Rahmen nicht gezeichnet (0.6.540)
        p.field = field
        field.bg = field:CreateTexture(nil, "BACKGROUND")
        field.bg:SetAllPoints()
        field.bg:SetColorTexture(0.32, 0.55, 0.22, 1)   -- ohne Gildenmodul: schlichte gruene Wiese
        if ns.GuildPack then   -- Kennzeichen: Gildenmodul geladen
            field.bg:SetTexture(ART)
            field.bg:SetTexCoord(0, 1, 0, 0.75)
        end
        K.Border(field, C.line)
        field.sheep = {}
        field.empty = K.Text(field, 13, C.text, "CENTER")
        field.empty:SetPoint("CENTER")

        -- Bewegung: ein OnUpdate fuer alle Schafe
        local tick, hue = 0, 0
        field:SetScript("OnUpdate", function(self, dt)
            dt = math.min(dt or 0, 0.1)
            local W, H = self:GetWidth(), self:GetHeight()
            if not W or W < 50 then return end
            tick, hue = tick + dt, (hue + dt * 0.15) % 1
            local rb = tick > 0.12
            if rb then tick = 0 end
            for _, s in ipairs(self.sheep) do
                if s:IsShown() and s.who then
                    if s.wait then
                        s.wait = s.wait - dt
                        setAnim(s, 0)
                        if s.wait <= 0 then pickTarget(s) end
                        s.sayIn = (s.sayIn or 10) - dt
                    else
                        local dx, dy = s.tx - s.x, s.ty - s.y
                        local d = math.sqrt(dx * dx + dy * dy)
                        s.sayIn = (s.sayIn or 10) - dt
                        if d < 0.01 then
                            s.wait = (1.5 + math.random() * 4) * (s.mood and s.mood < 30 and 2.5 or 1)
                        else
                            local v = 0.045 * (0.6 + 0.6 * s.y) * (s.mood and (0.45 + s.mood / 120) or 1)   -- vorne schneller, traurige Schafe trotten
                            local step = math.min(d, v * dt)
                            s.x, s.y = s.x + dx / d * step, s.y + dy / d * step
                            setAnim(s, 4)
                            -- Blickrichtung: 0 = zur Kamera, rechts = -pi/2, weg = pi
                            local face = math.atan2 and math.atan2(-dx, dy) or 0
                            if not s.face or math.abs(face - s.face) > 0.05 then s.face = face pcall(s.SetFacing, s, face) end
                        end
                    end
                    -- Sprechblase: alle 15-40 s kurz "Maeh!" oder was gerade fehlt
                    if s.sayLeft then
                        s.sayLeft = s.sayLeft - dt
                        if s.sayLeft <= 0 then s.sayLeft = nil s.say:Hide() s.sayBg:Hide() end
                    elseif (s.sayIn or 10) <= 0 then
                        s.sayIn = 15 + math.random() * 25
                        s.say:SetText(s.wish or L["Maeh!"])
                        s.say:Show() s.sayBg:Show() s.sayLeft = 3
                    end
                    -- Groesse: Rang (1-100) und Tiefe
                    local size = (40 + math.min(100, s.who.lvl) * 0.8) * (0.35 + 0.65 * s.y) * math.max(0.6, H / 520)
                    local feet = H * (MEADOW_TOP + s.y * (MEADOW_BOTTOM - MEADOW_TOP))
                    s:SetSize(size, size)
                    s:ClearAllPoints()
                    s:SetPoint("BOTTOMLEFT", self, "TOPLEFT", s.x * (W - size), -feet - size * 0.08)   -- Unterkante = Fuesse (kleiner Rand im Modell)
                    local lvl = 5 + math.floor(s.y * 40)
                    if s.lvlSet ~= lvl then s.lvlSet = lvl s:SetFrameLevel(self:GetFrameLevel() + lvl) end
                    if rb and s.skin and s.skin.rainbow then
                        local r, g, b = 0.5 + 0.5 * math.sin(hue * 6.283), 0.5 + 0.5 * math.sin(hue * 6.283 + 2.09), 0.5 + 0.5 * math.sin(hue * 6.283 + 4.19)
                        light(s, s.skin, r, g, b)
                    end
                end
            end
        end)

        -- Skins: eigene Farbe waehlen
        local bar = CreateFrame("Frame", nil, p)
        bar:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -10)
        bar:SetPoint("RIGHT", field, "RIGHT", 0, 0)
        bar:SetHeight(84)
        p.bar = bar
        bar.t = K.Text(bar, 11, C.muted)
        bar.t:SetPoint("TOPLEFT", 0, 0)
        bar.t:SetText(L["Dein Tier:"])
        bar.t2 = K.Text(bar, 11, C.muted)
        bar.t2:SetText(L["Farbe:"])
        bar.fbtn = {}
        for i, f in ipairs(Weide.FORMS) do
            local b = K.Button(bar, L[f.text], 0, 22, "ghost", function()
                if Weide.SetMyForm(f.key) then
                    ns.RefreshPage("pasture", true)
                else
                    K.Toast(L["Gildotchi"], (L["%s gibt es ab Oasis-Rang %d."]):format(L[f.text], f.lvl), C.amber or C.accent)
                end
            end)
            b:SetWidth(math.max(54, b.label:GetStringWidth() + 18))
            b.form = f
            bar.fbtn[i] = b
        end
        bar.btn = {}
        for i, s in ipairs(Weide.SKINS) do
            local b = K.Button(bar, L[s.text], 0, 22, "ghost", function()
                if Weide.SetMySkin(s.key) then
                    ns.RefreshPage("pasture", true)
                else
                    K.Toast(L["Schafweide"], (L["%s gibt es ab Oasis-Rang %d."]):format(L[s.text], s.lvl), C.amber or C.accent)
                end
            end)
            b:SetWidth(math.max(54, b.label:GetStringWidth() + 18))
            b.skin = s
            bar.btn[i] = b
        end
        function bar:Layout()
            local w = self:GetWidth() or 600
            local function row(list, label, y0)
                label:ClearAllPoints()
                label:SetPoint("TOPLEFT", 0, y0 - 5)
                local x, y = 70, y0
                for _, b in ipairs(list) do
                    if x + b:GetWidth() > w and x > 70 then x, y = 70, y - 24 end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", x, y)
                    x = x + b:GetWidth() + 4
                end
                return y - 26
            end
            local y = row(self.fbtn, self.t, 0)
            row(self.btn, self.t2, y - 4)
        end
        bar:SetScript("OnSizeChanged", function(self) self:Layout() end)

        -- Rangliste rechts
        local side = CreateFrame("Frame", nil, p)
        side:SetPoint("TOPLEFT", field, "TOPRIGHT", 14, 0)
        side:SetPoint("BOTTOMRIGHT", 0, 0)
        p.side = side
        side.bg = K.Fill(side, C.panel or { 0, 0, 0, 0.4 })
        K.Border(side, C.line)
        -- Mein Gildotchi: Laune, drei Balken, drei Knoepfe
        side.me = K.Text(side, 13, C.text)
        side.me:SetPoint("TOPLEFT", 12, -10)
        side.me:SetText(L["Mein Gildotchi"])
        side.mood = K.Text(side, 11, C.muted)
        side.mood:SetPoint("TOPLEFT", side.me, "BOTTOMLEFT", 0, -3)
        side.need = {}
        for i, n in ipairs(Weide.NEEDS) do
            local y = -48 - (i - 1) * 40
            local r = {}
            r.t = K.Text(side, 11, C.text)
            r.t:SetPoint("TOPLEFT", 12, y)
            r.bar = K.Bar(side, LIST_W - 120, 6)
            r.bar:SetPoint("TOPLEFT", 12, y - 16)
            r.btn = K.Button(side, L[n.act], 86, 22, "ghost", function()
                local ok, left = Weide.Care(n.key)
                if ok then
                    K.Toast(L["Gildotchi"], L["Maeh! Danke!"], C.mint)
                else
                    K.Toast(L["Gildotchi"], (L["Wieder in %s."]):format(fmtLeft(left)), C.amber or C.accent)
                end
                ns.RefreshPage("pasture", true)
            end)
            r.btn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, y - 4)
            r.need = n
            side.need[i] = r
        end
        side.h = K.Text(side, 13, C.text)
        side.h:SetPoint("TOPLEFT", 12, -178)
        side.h:SetText(L["Rangliste der Herde"])
        side.sum = K.Text(side, 11, C.muted)
        side.sum:SetPoint("TOPLEFT", side.h, "BOTTOMLEFT", 0, -3)
        side.rows = {}
        for i = 1, 16 do
            local r = CreateFrame("Frame", nil, side)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 10, -214 - (i - 1) * 21)
            r:SetPoint("RIGHT", side, "RIGHT", -10, 0)
            r.pos = K.Text(r, 11, C.dim, "RIGHT")
            r.pos:SetPoint("LEFT", 0, 0) r.pos:SetWidth(22)
            r.dot = r:CreateTexture(nil, "ARTWORK")
            r.dot:SetSize(8, 8) r.dot:SetPoint("LEFT", 28, 0)
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("LEFT", 42, 0) r.n:SetPoint("RIGHT", -40, 0)
            r.n:SetWordWrap(false) r.n:SetJustifyH("LEFT")
            r.l = K.Text(r, 12, C.accent2, "RIGHT")
            r.l:SetPoint("RIGHT", 0, 0)
            side.rows[i] = r
        end
    end,
    refresh = function(p)
        local flock = Weide.Flock()
        local field = p.field
        -- Schafe zuteilen (bekannte behalten ihren Platz)
        local n = math.min(#flock, MAX_SHEEP)
        for i = 1, n do
            local s = field.sheep[i]
            if not s then
                s = newSheep(field)
                if not s then break end
                field.sheep[i] = s
                s.x, s.y = math.random() * 0.9 + 0.05, math.random()
                pickTarget(s)
                s.wait = math.random() * 3
            end
            local who = flock[i]
            s.who = who
            local skin = Weide.SkinOf(who.name, who.lvl)
            if s.skin ~= skin then s.skin = skin light(s, skin, 1, 1, 1) end
            local form = Weide.FormOf(who.name, who.lvl)
            if s.form ~= form then s.form = form s:LoadSheep() end
            local nd = Weide.Needs(who.name)
            s.mood, s.wish = nd.mood, nil
            for _, n in ipairs(Weide.NEEDS) do if nd[n.key] < 25 then s.wish = L[n.say] break end end
            s:SetAlpha(who.online and 1 or 0.75)
            s.name:SetText(ns.short(who.name))
            s.name:SetAlpha(who.online and 0.75 or 0.45)
            s.name:Show()
            s:Show()
        end
        for i = n + 1, #field.sheep do
            local s = field.sheep[i]
            s:Hide() s.who = nil s.name:Hide() s.say:Hide() s.sayBg:Hide()
        end
        field.empty:SetText(#flock == 0 and L["Noch keine Schafe auf der Weide."] or "")

        -- Tier- und Farb-Knoepfe
        local mine, cur = myRank(), Weide.SkinOf(ns.me(), myRank())
        local curF = Weide.FormOf(ns.me(), mine)
        for _, b in ipairs(p.bar.fbtn) do
            local f = b.form
            local open = mine >= f.lvl
            b:SetLabel((f == curF and "> " or "") .. L[f.text] .. (open and "" or ("  |cff777777" .. f.lvl .. "|r")))
            b:SetWidth(math.max(54, b.label:GetStringWidth() + 18))
            b:SetAlpha(open and 1 or 0.55)
        end
        for _, b in ipairs(p.bar.btn) do
            local s = b.skin
            local open = mine >= s.lvl
            b:SetLabel((s == cur and "> " or "") .. L[s.text] .. (open and "" or ("  |cff777777" .. s.lvl .. "|r")))
            b:SetWidth(math.max(54, b.label:GetStringWidth() + 18))
            b:SetAlpha(open and 1 or 0.55)
        end
        p.bar:Layout()

        -- Mein Gildotchi
        local side = p.side
        local nd = Weide.Needs(ns.me())
        local mt, mc = Weide.MoodText(nd.mood)
        side.mood:SetText(L["Laune"] .. ": " .. K.hex(mc) .. L[mt] .. "|r")
        local g = ns.db.settings.gildotchi or {}
        for _, r in ipairs(side.need) do
            local v = nd[r.need.key]
            r.t:SetText(L[r.need.text] .. "  |cff9a9a9a" .. math.floor(v + 0.5) .. "%|r")
            r.bar:Set(v / 100)
            local left = (tonumber(g[r.need.key]) or 0) + r.need.cd - ns.now()
            r.btn:SetAlpha(left > 0 and 0.5 or 1)
        end
        -- Rangliste
        local on = 0
        for _, f in ipairs(flock) do if f.online then on = on + 1 end end
        side.sum:SetText((L["%d Schafe, %d gerade online"]):format(#flock, on))
        for i, r in ipairs(side.rows) do
            local f = flock[i]
            r:SetShown(f ~= nil)
            if f then
                r.pos:SetText(i .. ".")
                r.n:SetText(ns.short(f.name) .. (ns.isMe(f.name) and ("  |cff9a9a9a" .. L["(du)"] .. "|r") or ""))
                r.l:SetText(f.lvl)
                local sk = Weide.SkinOf(f.name, f.lvl)
                local c = sk.amb or { 1, 0.4, 0.4 }
                r.dot:SetColorTexture(c[1], c[2], c[3], f.online and 1 or 0.4)
            end
        end
    end,
})
ns.Listen("STORE", function(name) if name == "sheep" then ns.RefreshPage("pasture") end end)
ns.slash.weide = function() ns.ShowPage("pasture") end
ns.slash.gildotchi = ns.slash.weide
-- Diagnose: laden die Schafmodelle?
ns.slash.schaftest = function()
    local def = ns.PageDef and ns.PageDef("pasture")
    local f = def and def.frame and def.frame.field
    if not f then ns.print("Gildotchi: Seite erst einmal oeffnen.") return end
    ns.print(("Gildotchi: %d Schafe, Wiese %dx%d sichtbar=%s"):format(#f.sheep, f:GetWidth() or 0, f:GetHeight() or 0, tostring(f:IsVisible())))
    for i, m in ipairs(f.sheep) do
        local ok, id = pcall(m.GetModelFileID, m)
        ns.print(("Schaf %d: %s  Modell=%s  sichtbar=%s  Groesse=%dx%d"):format(i, m.who and ns.short(m.who.name) or "-", tostring(ok and id),
            tostring(m:IsVisible()), m:GetWidth() or 0, m:GetHeight() or 0))
    end
end
end)

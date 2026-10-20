-- Oasis: Schafweide (0.6.539) - jedes Gildenmitglied mit Oasis laeuft als Schaf ueber die Wiese.
-- Ab bestimmten Oasis-Raengen gibt es andere Tiere und Farben (Skins). Groesse nur nach Tiefe (0.6.548).
-- Den eigenen Skin meldet jeder selbst (Sammlung "sheep", OWNED); beim Anzeigen wird der Rang des Besitzers
-- geprueft - wer sich einen Skin ueber seinem Rang einstellt, erscheint bei den anderen trotzdem weiss.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Community", function()
local K, C, L = ns.K, ns.K.C, ns.L
local Store = ns.Store
local Weide = {}
ns.Weide = Weide

local SHEEP_NPC = 1933        -- Schaf (wie beim Todeswuerfeln)
local SHEEP_DISPLAY = 856     -- Schaf-Modell (Verwandlung), geht auch ohne Kreatur im Zwischenspeicher
local MAX_SHEEP = 40          -- mehr Modelle kosten zu viel Leistung
local ART = "Interface\\AddOns\\Oasis_Guild\\Media\\weide_bg"   -- Bild nur im Gildenmodul
local MEADOW_TOP, MEADOW_BOTTOM = 0.34, 0.82   -- 0.6.562: weiter in die Tiefe   -- Laufbereich (Fuesse), Anteil der Hoehe von oben: hinten an den Baeumen bis ganz vorne - nie im Himmel

-- Skins: Licht-Farbe auf dem Schafmodell. lvl = ab Oasis-Rang
Weide.SKINS = {
    { key = "white", text = "White", lvl = 1, amb = { 1, 1, 1 }, ai = 0.8, dif = { 1, 0.95, 0.9 }, di = 0.9 },
    { key = "cream", text = "Cream", lvl = 10, amb = { 1, 0.9, 0.7 }, ai = 0.8, dif = { 1, 0.85, 0.6 }, di = 0.9 },
    { key = "grey", text = "Grey", lvl = 20, amb = { 0.55, 0.55, 0.58 }, ai = 0.7, dif = { 0.6, 0.6, 0.62 }, di = 0.7 },
    { key = "pink", text = "Pink", lvl = 30, amb = { 1, 0.6, 0.78 }, ai = 0.85, dif = { 1, 0.55, 0.75 }, di = 0.9 },
    { key = "blue", text = "Sky blue", lvl = 40, amb = { 0.5, 0.72, 1 }, ai = 0.85, dif = { 0.5, 0.7, 1 }, di = 0.9 },
    { key = "black", text = "Black sheep", lvl = 50, amb = { 0.12, 0.11, 0.13 }, ai = 0.6, dif = { 0.22, 0.2, 0.24 }, di = 0.5 },
    { key = "green", text = "Moss green", lvl = 60, amb = { 0.5, 0.95, 0.45 }, ai = 0.85, dif = { 0.45, 0.9, 0.4 }, di = 0.9 },
    { key = "gold", text = "Gold", lvl = 70, amb = { 1, 0.8, 0.3 }, ai = 0.9, dif = { 1, 0.75, 0.25 }, di = 1 },
    { key = "violet", text = "Purple", lvl = 80, amb = { 0.7, 0.45, 1 }, ai = 0.85, dif = { 0.65, 0.4, 1 }, di = 0.9 },
    { key = "rainbow", text = "Rainbow", lvl = 100, rainbow = true },
}
local BY = {}
for _, s in ipairs(Weide.SKINS) do BY[s.key] = s end
-- 0.6.540: Verkleidungen - andere Tiere ab hoeheren Raengen (Kreatur-IDs aus der Spielwelt; laedt eine nicht, bleibt es ein Schaf)
Weide.FORMS = {
    { key = "sheep", text = "Sheep", lvl = 1 },
    { key = "rabbit", text = "Rabbit", lvl = 15, npc = 721 },
    { key = "chicken", text = "Chicken", lvl = 25, npc = 620 },
    { key = "toad", text = "Toad", lvl = 35, npc = 1420 },
    { key = "squirrel", text = "Squirrel", lvl = 45, npc = 1412 },
    { key = "prairie", text = "Prairie dog", lvl = 55, npc = 2620 },
    { key = "fawn", text = "Fawn", lvl = 65, npc = 890 },
    { key = "cow", text = "Cow", lvl = 75, npc = 2442 },
    { key = "deer", text = "Stag", lvl = 90, npc = 883 },
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
    { key = "f", text = "Fed", act = "Feed", span = 24 * 3600, cd = 3 * 3600, say = "Hungry!" },
    { key = "j", text = "Happy", act = "Pet", span = 12 * 3600, cd = 1 * 3600, say = "Pet me!" },
    { key = "c", text = "Groomed", act = "Brush", span = 48 * 3600, cd = 8 * 3600, say = "I am all scruffy!" },
}
local function careRec(name)
    if ns.isMe(name) then ns.db.settings.gildotchi = ns.db.settings.gildotchi or {} return ns.db.settings.gildotchi end
    local r = Store.Get("sheep", "shp-" .. ns.NameKey(name))
    return r or {}
end
-- Werte 0-100 je Beduerfnis + Laune (Durchschnitt); ohne jede Pflege startet ein Schaf halb zufrieden
-- 0.6.548: Gilde hilft - juengstes Fuettern durch andere (Sammlung "gfeed", jeder meldet nur sich)
function Weide.GuildFed(name)
    local key, best, by = ns.NameKey(name), nil, nil
    for _, g in ipairs(Store.List("gfeed")) do
        if g.target == key and (tonumber(g.ts) or 0) > (best or 0) then best, by = tonumber(g.ts), g.by end
    end
    return best, by
end
local function today(off) return date("%Y-%m-%d", (ns.now() + (off or 0) * 86400)) end
-- letzte Pflege ueberhaupt (eigene oder durch die Gilde); nil = noch nie gepflegt
function Weide.LastCare(name)
    local r, last = careRec(name), nil
    for _, n in ipairs(Weide.NEEDS) do local t = tonumber(r[n.key]) if t and t > (last or 0) then last = t end end
    local gf = Weide.GuildFed(name)
    if gf and gf > (last or 0) then last = gf end
    return last
end
-- 0.6.548: nach 7 Tagen ohne Pflege ist das Tier ausgebuext (nicht auf der Weide, "Zurueckholen" bringt es sofort wieder)
Weide.AWAY = 7 * 86400
function Weide.IsAway(name)
    local last = Weide.LastCare(name)
    return last ~= nil and ns.now() - last > Weide.AWAY
end
function Weide.Recall()
    local g = careRec(ns.me())
    for _, n in ipairs(Weide.NEEDS) do g[n.key] = ns.now() - n.span * 0.5 end   -- halb zufrieden zurueck
    Weide.Report()
end
-- 0.6.548: Pflege-Serie - Tage am Stueck mit mindestens einer Pflege; zaehlt nur, wenn heute oder gestern gepflegt
function Weide.Streak(name)
    local r = careRec(name)
    if r.sd == today() or r.sd == today(-1) then return tonumber(r.sn) or 0 end
    return 0
end
Weide.EXTRAS = {
    { n = 3, text = "Sparkle" },
    { n = 7, text = "Star by the name" },
    { n = 14, text = "Golden name" },
    { n = 30, text = "Crown" },
}
function Weide.Needs(name)
    local r, out, sum = careRec(name), {}, 0
    local gf = Weide.GuildFed(name)
    for _, n in ipairs(Weide.NEEDS) do
        local ts = tonumber(r[n.key])
        if n.key == "f" and gf and gf > (ts or 0) then ts = gf end
        local v = ts and math.max(0, math.min(100, 100 - (ns.now() - ts) / n.span * 100)) or 50
        out[n.key] = v
        sum = sum + v
    end
    out.mood = sum / #Weide.NEEDS
    return out
end
function Weide.MoodText(m)
    if m >= 75 then return "Happy", C.mint elseif m >= 45 then return "Content", C.text
    elseif m >= 20 then return "Grumpy", C.amber or C.accent else return "Sad", C.accent end
end
function Weide.Report()
    if not IsInGuild() then return end
    local g = ns.db.settings.gildotchi or {}
    Store.Put("sheep", { id = "shp-" .. ns.NameKey(ns.me()), skin = ns.db.settings.sheepSkin, form = ns.db.settings.sheepForm,
        f = g.f, j = g.j, c = g.c, sd = g.sd, sn = g.sn, by = ns.me(), ts = ns.now() })
end
local report = function() Weide.Report() end
local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return ("%d Std. %d Min."):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%d min"):format(math.max(1, math.ceil(sec / 60)))
end
-- Pflegen: true oder false + Restzeit in Sekunden
function Weide.Care(key)
    local g = careRec(ns.me())
    for _, n in ipairs(Weide.NEEDS) do
        if n.key == key then
            local left = (tonumber(g[key]) or 0) + n.cd - ns.now()
            if left > 0 then return false, left end
            g[key] = ns.now()
            -- Serie: heute schon gezaehlt? sonst gestern -> +1, laenger her -> neu bei 1
            if g.sd ~= today() then
                g.sn = (g.sd == today(-1)) and ((tonumber(g.sn) or 0) + 1) or 1
                g.sd = today()
            end
            report()
            return true
        end
    end
    return false, 0
end

-- Fremdes Tier fuettern: einmal am Tag je Tier
function Weide.FeedOther(name)
    if not name or ns.isMe(name) or not IsInGuild() then return false end
    local id = "gf-" .. ns.NameKey(ns.me()) .. "-" .. ns.NameKey(name) .. "-" .. today()
    if Store.Get("gfeed", id) then return false, "today" end
    Store.Put("gfeed", { id = id, target = ns.NameKey(name), by = ns.me(), ts = ns.now() })
    local f = Weide.FormOf(name, (ns.Rank and ns.Rank.Of and ns.Rank.Of(name)) or 1)
    if ns.Chronicle and ns.Chronicle.Add then
        pcall(ns.Chronicle.Add, "guild", "gfc-" .. id, "fed %s", { (L["%s's %s"]):format(ns.short(name), L[f.text]) })
    end
    return true
end

-- Wer steht auf der Weide? Mains mit Oasis, in den letzten 14 Tagen gesehen
function Weide.Flock()
    local out = {}
    Weide.away = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local p = ns.db.members and ns.db.members[m.name]
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        local uses = ns.isMe(m.name) or (type(p) == "table" and p.v and ns.now() - (p.seen or 0) < 14 * 86400)
        if uses and not isAlt then
            local lvl = rankOf(m.name)
            local row = { name = m.name, lvl = lvl, online = m.online or ns.isMe(m.name), away = Weide.IsAway(m.name) }
            out[#out + 1] = row
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
    -- 0.6.548: vernachlaessigt -> Farbe Richtung Grau, etwas dunkler
    local sad = m.sad or 0
    if sad > 0 then
        local function mix(c) return { c[1] + (0.5 - c[1]) * sad * 0.7, c[2] + (0.5 - c[2]) * sad * 0.7, c[3] + (0.5 - c[3]) * sad * 0.7 } end
        amb, dif, ai, di = mix(amb), mix(dif), ai * (1 - 0.3 * sad), di * (1 - 0.3 * sad)
    end
    pcall(m.SetLight, m, true, {
        omnidirectional = false, point = CreateVector3D(-0.6, 1, -0.6),
        ambientIntensity = ai, ambientColor = CreateColor(amb[1], amb[2], amb[3]),
        diffuseIntensity = di, diffuseColor = CreateColor(dif[1], dif[2], dif[3]),
    })
end

------------------------------------------------------------------------
-- Ein Schaf: eigenes Modell, laeuft zu zufaelligen Zielen, bleibt mal stehen und grast
------------------------------------------------------------------------
-- Tier in ein Modell laden; laedt es nicht (nicht im Zwischenspeicher), wird es ein Schaf
function Weide.LoadForm(m, f)
    pcall(m.ClearModel, m)
    if f and f.npc then
        pcall(m.SetCreature, m, f.npc)
    else
        local ok = m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, SHEEP_DISPLAY)
        if not ok then pcall(m.SetCreature, m, SHEEP_NPC) end
    end
    C_Timer.After(0.5, function()
        local okm, id = pcall(m.GetModelFileID, m)
        if not okm or not id or id == 0 then
            local ok2 = m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, SHEEP_DISPLAY)
            if not ok2 then pcall(m.SetCreature, m, SHEEP_NPC) end
        end
    end)
end
local function newSheep(field)
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, field)
    if not ok or not m then return nil end
    m:EnableMouse(true)
    function m:LoadSheep() Weide.LoadForm(self, self.form) end
    m:LoadSheep()
    m:SetScript("OnShow", function(self)
        local okm, id = pcall(self.GetModelFileID, self)
        if not okm or not id or id == 0 then self:LoadSheep() end
    end)
    -- Name (dezent) und darueber die Sprechblase - eigener Rahmen direkt ueber diesem Tier (0.6.546)
    m.lab = CreateFrame("Frame", nil, field)
    m.lab:SetAllPoints(m)
    m.name = K.Text(m.lab, 12, C.text, "CENTER")
    m.name:SetPoint("BOTTOM", m, "TOP", 0, -14)
    do local fnt, sz = m.name:GetFont() if fnt then m.name:SetFont(fnt, sz or 12, "OUTLINE") end end
    m.name:SetDrawLayer("OVERLAY", 6)
    m.name:SetShadowOffset(1, -1)
    m.name:SetShadowColor(0, 0, 0, 0.9)
    m.name:SetAlpha(0.95)
    m.say = K.Text(m.lab, 11, C.text, "CENTER")
    m.say:SetPoint("BOTTOM", m.name, "TOP", 0, 5)
    m.say:SetDrawLayer("OVERLAY", 7)
    m.sayBg = m.lab:CreateTexture(nil, "OVERLAY")
    m.sayBg:SetColorTexture(0, 0, 0, 0.55)
    m.sayBg:SetPoint("TOPLEFT", m.say, "TOPLEFT", -6, 3)
    m.sayBg:SetPoint("BOTTOMRIGHT", m.say, "BOTTOMRIGHT", 6, -3)
    m.say:Hide() m.sayBg:Hide()
    m.sayIn = 3 + math.random() * 20
    m:SetScript("OnModelLoaded", function(self)
        pcall(self.SetPortraitZoom, self, 0)
        pcall(self.SetCamDistanceScale, self, 0.85)   -- naeher dran: Tier fuellt den Rahmen
        pcall(self.SetPosition, self, 0, 0, 0)
        if self.skin then light(self, self.skin, 1, 1, 1) end
        self.anim = nil
    end)
    m:SetScript("OnEnter", function(self)
        if not self.who then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.short(self.who.name), 1, 1, 1)
        GameTooltip:AddLine((L["Oasis rank %d"]):format(self.who.lvl), C.accent2[1], C.accent2[2], C.accent2[3])
        GameTooltip:AddLine(L[self.form and self.form.text or "Sheep"] .. " - " .. L[self.skin and self.skin.text or "White"], 0.8, 0.8, 0.8)
        local nd = Weide.Needs(self.who.name)
        local mt, mc = Weide.MoodText(nd.mood)
        GameTooltip:AddLine(L["Mood"] .. ": " .. L[mt], mc[1], mc[2], mc[3])
        local st = Weide.Streak(self.who.name)
        if st >= 2 then GameTooltip:AddLine((L["Cared for %d days in a row"]):format(st), 1, 0.82, 0.3) end
        if not ns.isMe(self.who.name) then GameTooltip:AddLine(L["Click: feed (once a day)"], 0.6, 0.8, 1) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnMouseUp", function(self)
        if not self.who or ns.isMe(self.who.name) then return end
        local ok = Weide.FeedOther(self.who.name)
        if ok then
            K.Toast(L["Guildotchi"], (L["You fed %s."]):format(ns.short(self.who.name)), C.mint)
            self.say:SetText(L["Baa! Thanks!"]) self.say:Show() self.sayBg:Show() self.sayLeft = 3
            ns.RefreshPage("pasture", true)
        else
            K.Toast(L["Guildotchi"], L["Already fed today - again tomorrow."], C.amber or C.accent)
        end
    end)
    -- Glitzern (Pflege-Serie ab 3 Tagen)
    m.spark = {}
    for i = 1, 3 do
        local t = m.lab:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ns.MEDIA .. "icons\\star_on")
        t:SetVertexColor(1, 0.9, 0.5)
        t:SetSize(10, 10)
        t:Hide()
        m.spark[i] = t
    end
    return m
end
-- 0.6.547: Maeh-Geraeusch (CC0, "Sheep Baa" von AntumDeluge nach mikewest, opengameart.org/node/132779) - nur mit Gildenmodul,
-- folgt dem Oasis-Lautstaerkeregler, nur wenn die Wiese sichtbar ist
-- 0.6.557: jedes Maeh eines Schafs ist zu hoeren (Toene duerfen sich ueberlagern), zufaellig aus fuenf Stimmen;
-- vier davon CC0 von Joseph Sardin / BigSoundBank (sheep 3, 4, 5, 7)
local SND = "Interface\\AddOns\\Oasis_Guild\\Media\\sounds\\"
local VOICES = { "maeh", "maeh03", "maeh04", "maeh05", "maeh07" }
function Weide.Maeh()
    if not ns.GuildPack or ns.db.settings.gotchiSound == false then return end
    local vol = math.floor(tonumber(ns.db.settings.soundVol or 14) or 14)
    if vol <= 0 then return end
    local dir = SND .. VOICES[math.random(#VOICES)] .. "\\"
    vol = math.min(vol, 20)
    while vol > 0 do
        local lv = math.min(10, vol)
        vol = vol - lv
        pcall(PlaySoundFile, dir .. lv .. ".ogg", "Master")
    end
end
local function setAnim(m, id)
    if m.anim ~= id then m.anim = id pcall(m.SetAnimation, m, id) end
end
-- zu nah an einem anderen Tier? (x quer in Anteilen der Breite, y = Tiefe)
local GAP_X, GAP_Y = 0.13, 0.12   -- 0.6.548: deutlich mehr Abstand
-- 0.6.558: Abstand nach der echten Groesse (wie beim Zeichnen: 0.35 + 1.25 * y^1.8) - vorne waren die Tiere
-- dreimal so breit wie der feste Abstand und liefen ineinander
local function bodyW(y) return 0.16 + 1.44 * (y or 0) ^ 1.6 end   -- 0.6.560: hinten viel kleiner (wie beim Zeichnen)
local function crowded(s, x, y, flock)
    for _, o in ipairs(flock or {}) do
        if o ~= s and o:IsShown() and o.who then
            local need = 0.17 * (bodyW(y) + bodyW(o.y))   -- 0.6.559: seitlich ist ein Schaf fast doppelt so lang wie breit
            local needY = GAP_Y * (0.9 + 0.9 * math.max(y, o.y))
            if math.abs(o.x - x) < need and math.abs(o.y - y) < needY then return o end
        end
    end
end
-- 0.6.549: Ziel mit moeglichst viel Platz - von 10 Vorschlaegen (halb in der Naehe, halb irgendwo auf der Wiese)
-- gewinnt der mit dem groessten Abstand zum naechsten Tier -> die Herde verteilt sich ueber die ganze Flaeche
local function room(s, x, y, flock)
    local best = 9
    for _, o in ipairs(flock or {}) do
        if o ~= s and o:IsShown() and o.who then
            local ox, oy = o.tx or o.x, o.ty or o.y   -- auch dahin, wo die anderen gerade hinlaufen
            local d = math.sqrt((ox - x) ^ 2 + ((oy - y) * 1.3) ^ 2)
            -- 0.6.555: vorne sind die Tiere bis zu dreimal so gross - gleicher Abstand wirkt dort viel enger
            d = d / (0.45 + 0.9 * math.max(y, oy))
            if d < best then best = d end
        end
    end
    return best
end
-- 0.6.562: zu nah -> langsam auseinanderschieben, ohne sich umzudrehen (vorher: wegrennen, blockieren, umdrehen -> Zappeln)
local function push(s, o, dt)
    local dx, dy = s.x - o.x, s.y - o.y
    if math.abs(dx) + math.abs(dy) < 0.001 then dx = (math.random() - 0.5) end
    local len = math.sqrt(dx * dx + dy * dy)
    s.x = math.max(0.02, math.min(0.98, s.x + dx / len * 0.05 * dt))
    s.y = math.max(0, math.min(1, s.y + dy / len * 0.05 * dt))
end
local function pickTarget(s, flock)
    local bx, by, bs = s.x, s.y, -1
    for i = 1, 10 do
        local x, y
        if i % 2 == 0 then
            x, y = 0.03 + math.random() * 0.94, math.random() ^ 1.8   -- 0.6.562: deutlich eher hinten (dort ist mehr Platz)
        else
            x = math.max(0.02, math.min(0.98, s.x + (math.random() - 0.5) * 0.5))
            y = math.max(0, math.min(1, s.y + (math.random() - 0.5) * 0.6))   -- y: 0 = hinten (klein), 1 = vorne (gross)
        end
        local sc = room(s, x, y, flock)
        if sc > bs then bx, by, bs = x, y, sc end
    end
    s.tx, s.ty = bx, by
    s.wait = nil
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local LIST_W = 190   -- 0.6.546: schmaler, mehr Platz fuer die Wiese
ns.RegisterPage({
    key = "pasture", title = "Guildotchi", order = 7.64,
    sub = "Every guild member with Oasis has an animal on the pasture - feed, pet and brush it. Higher ranks unlock new animals and colours.",
    build = function(p)
        -- Wiese
        local field = CreateFrame("Frame", nil, p)
        field:SetPoint("TOPLEFT", 4, -4)   -- Platz fuer den Rahmen
        field:SetPoint("BOTTOMRIGHT", -(LIST_W + 24), 46)
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
        -- 0.6.543: Rahmen im Stil des Logos (Gold, Petrol-Innenkante, Edelsteine), 9-teilig damit die Ecken scharf bleiben
        if ns.GuildPack then
            local fr = CreateFrame("Frame", nil, p)
            fr:SetPoint("TOPLEFT", field, "TOPLEFT", -6, 6)
            fr:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 7, -12)   -- 0.6.555: Wiese ragte unten heraus   -- unten liegt das Band im Bild hoeher (Rand 53 statt 43 px)
            fr:SetFrameLevel(field:GetFrameLevel() + 55)
            -- 0.6.552: Rahmen aus der Vorlage (1448x1086, als 1024x768 in 1024x1024): Ecken und Mittelschmuck unverzerrt, Kanten gestreckt
            local TEX = "Interface\\AddOns\\Oasis_Guild\\Media\\gildotchi_frame"
            local SW, SH, KK = 1448, 1086, 0.3
            local function piece(x1, y1, x2, y2)
                local x = fr:CreateTexture(nil, "OVERLAY")
                x:SetTexture(TEX)
                x:SetTexCoord(x1 / SW, x2 / SW, y1 / SH * 0.75, y2 / SH * 0.75)
                x:SetSize((x2 - x1) * KK, (y2 - y1) * KK)
                return x
            end
            local CO, EW = 115, 60          -- Eckgroesse, Kantenstaerke (Vorlage)
            local tl, tr = piece(0, 0, CO, CO), piece(SW - CO, 0, SW, CO)
            local bl, br = piece(0, SH - CO, CO, SH), piece(SW - CO, SH - CO, SW, SH)
            tl:SetPoint("TOPLEFT") tr:SetPoint("TOPRIGHT") bl:SetPoint("BOTTOMLEFT") br:SetPoint("BOTTOMRIGHT")
            local tm, bm = piece(600, 0, 848, 80), piece(600, SH - 80, 848, SH)
            tm:SetPoint("TOP") bm:SetPoint("BOTTOM")
            local lm, rm = piece(0, 505, EW, 585), piece(SW - EW, 505, SW, 585)
            lm:SetPoint("LEFT") rm:SetPoint("RIGHT")
            local function hseg(a, b, y1, y2, top)
                local x = piece(300, y1, 500, y2)
                if top then x:SetPoint("TOPLEFT", a, "TOPRIGHT") x:SetPoint("TOPRIGHT", b, "TOPLEFT")
                else x:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT") x:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT") end
            end
            hseg(tl, tm, 0, EW, true) hseg(tm, tr, 0, EW, true)
            hseg(bl, bm, SH - EW, SH, false) hseg(bm, br, SH - EW, SH, false)
            local function vseg(a, b, x1, x2, left)
                local x = piece(x1, 250, x2, 450)
                if left then x:SetPoint("TOPLEFT", a, "BOTTOMLEFT") x:SetPoint("BOTTOMLEFT", b, "TOPLEFT")
                else x:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT") x:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT") end
            end
            vseg(tl, lm, 0, EW, true) vseg(lm, bl, 0, EW, true)
            vseg(tr, rm, SW - EW, SW, false) vseg(rm, br, SW - EW, SW, false)
            p.frameArt = fr
        end
        -- 0.6.542: Logo oben mittig, ragt ueber die Wiese hinaus (nur mit Gildenmodul)
        if ns.GuildPack then
            local logo = CreateFrame("Frame", nil, p)
            logo:SetSize(210, 77)   -- 0.6.547: kleiner
            logo:SetPoint("TOP", field, "TOP", 0, 24)
            logo:SetFrameLevel(field:GetFrameLevel() + 70)
            logo.t = logo:CreateTexture(nil, "OVERLAY")
            logo.t:SetAllPoints()
            logo.t:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\gildotchi_logo")
            logo.t:SetTexCoord(0, 1, 0, 187 / 256)
            p.logo = logo
        end
        field.sheep = {}
        field.empty = K.Text(field, 13, C.text, "CENTER")
        field.empty:SetPoint("CENTER")

        -- Bewegung: ein OnUpdate fuer alle Schafe
        local tick, hue, sortT = 0, 0, 0
        local order = {}
        field:SetScript("OnUpdate", function(self, dt)
            dt = math.min(dt or 0, 0.1)
            local W, H = self:GetWidth(), self:GetHeight()
            if not W or W < 50 then return end
            tick, hue = tick + dt, (hue + dt * 0.15) % 1
            local rb = tick > 0.12
            if rb then tick = 0 end
            -- 0.6.546: Zeichenreihenfolge nach Tiefe - ein Tier weiter vorne liegt immer vor den hinteren (je Tier eigene Ebene)
            sortT = sortT + dt
            if sortT > 0.1 then
                sortT = 0
                wipe(order)
                for _, s in ipairs(self.sheep) do if s:IsShown() then order[#order + 1] = s end end
                table.sort(order, function(a, b) return a.y < b.y end)
                local base = self:GetFrameLevel() + 2
                for i, s in ipairs(order) do
                    local lv = base + i * 3
                    if s.lvlSet ~= lv then
                        s.lvlSet = lv
                        s:SetFrameLevel(lv)
                        s.lab:SetFrameLevel(lv + 1)
                    end
                end
            end
            -- 0.6.548: Todeswuerfeln - selten laufen zwei Tiere zusammen und wuerfeln, bis eins die 1 hat (nur Optik, jeder sieht sein eigenes)
            self.duelIn = (self.duelIn or (90 + math.random() * 120)) - dt
            if self.duelIn <= 0 and not self.duel then
                self.duelIn = 180 + math.random() * 180
                local cand = {}
                for _, s in ipairs(self.sheep) do if s:IsShown() and s.who and not s.lying then cand[#cand + 1] = s end end
                if #cand >= 2 then
                    local a = table.remove(cand, math.random(#cand))
                    local b = table.remove(cand, math.random(#cand))
                    local mx, my = (a.x + b.x) / 2, math.max(0.15, math.min(0.9, (a.y + b.y) / 2))
                    self.duel = { a = a, b = b, phase = "walk", t = 0, max = 100, turn = a }
                    a.duel, b.duel = self.duel, self.duel
                    a.tx, a.ty, a.wait = math.max(0.03, mx - 0.05), my, nil
                    b.tx, b.ty, b.wait = math.min(0.97, mx + 0.05), my, nil
                end
            end
            local du = self.duel
            if du then
                du.t = du.t + dt
                local function say(sh, txt, sec) sh.say:SetText(txt) sh.say:Show() sh.sayBg:Show() sh.sayLeft = sec or 1.5 end
                if du.phase == "walk" then
                    local da = math.abs(du.a.x - du.a.tx) + math.abs(du.a.y - du.a.ty)
                    local db = math.abs(du.b.x - du.b.tx) + math.abs(du.b.y - du.b.ty)
                    if (da < 0.02 and db < 0.02) or du.t > 25 then
                        du.phase, du.t = "roll", 0
                        pcall(du.a.SetFacing, du.a, -1.5708) du.a.face = -1.5708   -- schauen sich an
                        pcall(du.b.SetFacing, du.b, 1.5708) du.b.face = 1.5708
                        say(du.a, L["Death roll?"], 1.6)
                    end
                elseif du.phase == "roll" and du.t > 1.8 then
                    du.t = 0
                    local roll = math.random(1, du.max)
                    say(du.turn, ("%d (1-%d)"):format(roll, du.max), 1.7)
                    if roll == 1 then
                        local other = du.turn == du.a and du.b or du.a
                        du.phase, du.loser, du.winner = "end", du.turn, other
                    else
                        du.max = roll
                        du.turn = du.turn == du.a and du.b or du.a
                    end
                elseif du.phase == "end" and du.t > 1.8 then
                    say(du.loser, L["Lost!"], 2.5)
                    say(du.winner, L["Won!"], 2.5)
                    du.phase, du.t = "done", 0
                elseif du.phase == "done" and du.t > 2.5 then
                    du.a.duel, du.b.duel = nil, nil
                    du.a.wait, du.b.wait = 1 + math.random() * 2, 1 + math.random() * 2
                    self.duel = nil
                end
            end
            for _, s in ipairs(self.sheep) do
                if s:IsShown() and s.who then
                    if s.lying then
                        -- 0.6.548: ganz vernachlaessigt - liegt im Gras
                        setAnim(s, 1)
                        s.sayIn = (s.sayIn or 10) - dt
                    elseif s.duel and s.duel.phase ~= "walk" then
                        setAnim(s, 0)
                    elseif s.wait then
                        s.wait = s.wait - dt
                        setAnim(s, 0)
                        if s.wait <= 0 then pickTarget(s, self.sheep) end
                        -- steht es zu nah an einem anderen (z. B. nach dem Start)? sanft auseinander
                        if not s.duel then
                            local o = crowded(s, s.x, s.y, self.sheep)
                            if o then push(s, o, dt) end
                        end
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
                            local nx, ny = s.x + dx / d * step, s.y + dy / d * step
                            local o = crowded(s, nx, ny, self.sheep)
                            if o and s.duel and (o == s.duel.a or o == s.duel.b) then o = nil end   -- zum Duell darf man nah ran
                            -- 0.6.546: nicht ineinanderlaufen - wer vor einem anderen Tier steht, bleibt kurz stehen und sucht sich ein neues Ziel
                            local away = o and (math.abs(nx - o.x) + math.abs(ny - o.y)) > (math.abs(s.x - o.x) + math.abs(s.y - o.y))
                            if o and not away then
                                -- 0.6.562: im Weg -> sanft zur Seite, nach 1 s ein neues Ziel mit Platz (kein Umdrehen auf der Stelle)
                                push(s, o, dt)
                                setAnim(s, 0)
                                s.blocked = (s.blocked or 0) + dt
                                if s.blocked > 1 then s.blocked = 0 pickTarget(s, self.sheep) end
                            else
                                s.blocked = 0
                                s.x, s.y = nx, ny
                                setAnim(s, 4)
                                -- Blickrichtung: 0 = zur Kamera, rechts = -pi/2, weg = pi; nur beim Laufen und erst ab merklicher Aenderung
                                local face = math.atan2 and math.atan2(-dx, dy) or 0
                                if not s.face or math.abs(face - s.face) > 0.25 then s.face = face pcall(s.SetFacing, s, face) end
                            end
                        end
                    end
                    -- Sprechblase: alle 15-40 s kurz "Maeh!" oder was gerade fehlt
                    if s.sayLeft then
                        s.sayLeft = s.sayLeft - dt
                        if s.sayLeft <= 0 then s.sayLeft = nil s.say:Hide() s.sayBg:Hide() end
                    elseif (s.sayIn or 10) <= 0 and not s.duel then
                        s.sayIn = 15 + math.random() * 25
                        s.say:SetText(s.wish or L["Baa!"])
                        s.say:Show() s.sayBg:Show() s.sayLeft = 3
                        if self:IsVisible() and (not s.form or s.form.key == "sheep") then Weide.Maeh() end
                    end
                    -- Groesse: nur nach Tiefe
                    local size = 140 * bodyW(s.y) * math.max(0.6, H / 520)   -- 0.6.548: Groesse nur nach Tiefe, nicht nach Rang
                    size = size * (1 - 0.15 * (s.sad or 0))   -- 0.6.548: vernachlaessigt etwas kleiner
                    local feet = H * (MEADOW_TOP + s.y * (MEADOW_BOTTOM - MEADOW_TOP))
                    -- 0.6.547: Namen hinten kleiner, vorne groesser (9-14 pt)
                    local fs = 9 + math.floor(s.y * 5 + 0.5)
                    if s.fs ~= fs then
                        s.fs = fs
                        local face, _, flags = s.name:GetFont()
                        if face then s.name:SetFont(face, fs, flags or "OUTLINE") end
                    end
                    s:SetSize(size, size)
                    s:ClearAllPoints()
                    s:SetPoint("BOTTOMLEFT", self, "TOPLEFT", s.x * (W - size), -feet - size * 0.08)   -- Unterkante = Fuesse (kleiner Rand im Modell)

                    -- Glitzern (Serie ab 3 Tagen): drei Sternchen kreisen kurz um den Kopf
                    if (s.streak or 0) >= 3 then
                        s.sparkT = (s.sparkT or math.random() * 6) + dt
                        local ph = s.sparkT % 6
                        for i, t in ipairs(s.spark) do
                            if ph < 2 then
                                local a = ph * 3 + i * 2.09
                                t:ClearAllPoints()
                                t:SetPoint("CENTER", s, "TOP", math.cos(a) * size * 0.3, -size * 0.2 + math.sin(a) * size * 0.08)
                                t:SetAlpha(math.sin(ph / 2 * math.pi))
                                t:Show()
                            else
                                t:Hide()
                            end
                        end
                    else
                        for _, t in ipairs(s.spark) do t:Hide() end
                    end
                    if rb and s.skin and s.skin.rainbow then
                        local r, g, b = 0.5 + 0.5 * math.sin(hue * 6.283), 0.5 + 0.5 * math.sin(hue * 6.283 + 2.09), 0.5 + 0.5 * math.sin(hue * 6.283 + 4.19)
                        light(s, s.skin, r, g, b)
                    end
                end
            end
        end)

        -- 0.6.545: Aussehen waehlen - Knopf unter der Wiese oeffnet eine Auswahl mit Modell-Vorschau
        local bar = CreateFrame("Frame", nil, p)
        bar:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -12)
        bar:SetPoint("RIGHT", field, "RIGHT", 0, 0)
        bar:SetHeight(26)
        p.bar = bar
        bar.btn = K.Button(bar, L["Change look"], 150, 24, "primary", function()
            p.pick:SetShown(not p.pick:IsShown())
            if p.pick:IsShown() then p.pick:Update() end
        end)
        bar.btn:SetPoint("LEFT", 0, 0)
        bar.cur = K.Text(bar, 11, C.muted)
        bar.cur:SetPoint("LEFT", bar.btn, "RIGHT", 12, 0)
        -- 0.6.545: als AFK-Bildschirm (Vollbild, sobald du AFK bist)
        bar.afk = K.Toggle(bar, L["As AFK screen"], function() return ns.db.settings.gotchiAfk == true end,
            function(v) ns.db.settings.gotchiAfk = v and true or nil end)
        bar.afk:SetWidth(190)
        bar.afk:SetPoint("RIGHT", bar, "RIGHT", 0, -2)
        bar.snd = K.Toggle(bar, L["Baa sounds"], function() return ns.db.settings.gotchiSound ~= false end,
            function(v) if v then ns.db.settings.gotchiSound = nil else ns.db.settings.gotchiSound = false end end)
        bar.snd:SetWidth(170)
        bar.snd:SetPoint("RIGHT", bar.afk, "LEFT", -12, 0)
        -- 0.6.556: Text "Aussehen" endet vor den Schaltern (lag darunter)
        bar.cur:SetPoint("RIGHT", bar.snd, "LEFT", -12, 0)
        bar.cur:SetJustifyH("LEFT") bar.cur:SetWordWrap(false)

        local pick = CreateFrame("Frame", nil, p)
        pick:SetPoint("TOPLEFT", field, "TOPLEFT", 16, -60)
        pick:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -16, 16)
        pick:SetFrameLevel(field:GetFrameLevel() + 80)
        pick:EnableMouse(true)
        pick:Hide()
        K.Fill(pick, { 0.03, 0.04, 0.06, 0.92 })
        K.Border(pick, C.line)
        p.pick = pick
        pick.close = K.Button(pick, L["Done"], 80, 22, "ghost", function() pick:Hide() end)
        pick.close:SetPoint("TOPRIGHT", -10, -8)
        pick.h1 = K.Text(pick, 12, C.text)
        pick.h1:SetPoint("TOPLEFT", 14, -12)
        pick.h1:SetText(L["Your animal"])
        pick.h2 = K.Text(pick, 12, C.text)
        pick.h2:SetText(L["Colour"])
        local TILE = 74
        local function tile(kind, def)
            local t = CreateFrame("Button", nil, pick)
            t:SetSize(TILE, TILE + 18)
            t.bg = K.Fill(t, { 1, 1, 1, 0.04 })
            t.sel = t:CreateTexture(nil, "BORDER")
            t.sel:SetPoint("TOPLEFT", -2, 2) t.sel:SetPoint("BOTTOMRIGHT", 2, -2)
            t.sel:SetColorTexture(C.accent2[1], C.accent2[2], C.accent2[3], 0.7)
            t.sel:Hide()
            local ok, m = pcall(CreateFrame, "PlayerModel", nil, t)
            if ok and m then
                m:SetPoint("TOPLEFT", 2, -2)
                m:SetSize(TILE - 4, TILE - 4)
                m:SetScript("OnModelLoaded", function(self)
                    pcall(self.SetPortraitZoom, self, 0)
                    pcall(self.SetCamDistanceScale, self, 0.95)
                    pcall(self.SetFacing, self, -0.5)
                    if self.skin then light(self, self.skin, 1, 0.6, 0.9) end
                end)
                t.m = m
            end
            t.label = K.Text(t, 10, C.text, "CENTER")
            t.label:SetPoint("BOTTOM", 0, 3)
            t.label:SetWidth(TILE)
            t.label:SetWordWrap(false)
            t.lock = K.Text(t, 11, C.amber or C.accent, "CENTER")
            t.lock:SetPoint("CENTER", 0, 8)
            t.kind, t.def = kind, def
            t:SetScript("OnClick", function(self)
                local d = self.def
                local ok2 = (self.kind == "form") and Weide.SetMyForm(d.key) or (self.kind == "skin" and Weide.SetMySkin(d.key))
                if not ok2 then
                    K.Toast(L["Guildotchi"], (L["%s unlocks at Oasis rank %d."]):format(L[d.text], d.lvl), C.amber or C.accent)
                end
                ns.RefreshPage("pasture", true)
                pick:Update()
            end)
            return t
        end
        pick.ft, pick.st = {}, {}
        for i, f in ipairs(Weide.FORMS) do pick.ft[i] = tile("form", f) end
        for i, sk in ipairs(Weide.SKINS) do pick.st[i] = tile("skin", sk) end
        function pick:Update()
            local w = math.max(200, (self:GetWidth() or 600) - 28)
            local per = math.max(1, math.floor((w + 6) / (TILE + 6)))
            local mine = myRank()
            local curF, curS = Weide.FormOf(ns.me(), mine), Weide.SkinOf(ns.me(), mine)
            local function place(list, y0)
                for i, t in ipairs(list) do
                    local c, r = (i - 1) % per, math.floor((i - 1) / per)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", 14 + c * (TILE + 6), y0 - r * (TILE + 24))
                    local d = t.def
                    local open = mine >= d.lvl
                    local form = t.kind == "form" and d or curF
                    local skin = t.kind == "skin" and d or curS
                    if t.m then
                        if t.m.form ~= form or not t.m.loaded then t.m.form = form t.m.loaded = true Weide.LoadForm(t.m, form) end
                        t.m.skin = skin
                        if skin.rainbow then light(t.m, skin, 1, 0.6, 0.9) else light(t.m, skin, 1, 1, 1) end
                        t.m:SetAlpha(open and 1 or 0.35)
                    end
                    t.label:SetText(L[d.text])
                    t.lock:SetText(open and "" or ((L["from %d"]):format(d.lvl)))
                    t.sel:SetShown((t.kind == "form" and d == curF) or (t.kind == "skin" and d == curS))
                end
                return y0 - math.ceil(#list / per) * (TILE + 24)
            end
            local y = place(self.ft, -34)
            self.h2:ClearAllPoints()
            self.h2:SetPoint("TOPLEFT", 14, y - 6)
            place(self.st, y - 26)
        end
        pick:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Update() end end)

        -- Rangliste rechts
        local side = CreateFrame("Frame", nil, p)
        side:SetPoint("TOPLEFT", field, "TOPRIGHT", 24, 10)
        side:SetPoint("BOTTOMRIGHT", 0, 0)
        p.side = side
        side.bg = K.Fill(side, C.panel or { 0, 0, 0, 0.4 })
        K.Border(side, C.line)
        -- Mein Gildotchi: Laune, drei Balken, drei Knoepfe
        side.me = K.Text(side, 13, C.text)
        side.me:SetPoint("TOPLEFT", 12, -10)
        side.me:SetText(L["My Guildotchi"])
        side.mood = K.Text(side, 11, C.muted)
        side.mood:SetPoint("TOPLEFT", side.me, "BOTTOMLEFT", 0, -3)
        side.mood:SetPoint("RIGHT", side, "RIGHT", -8, 0)
        side.mood:SetJustifyH("LEFT")
        side.mood:SetWordWrap(false)
        -- 0.6.548: ausgebuext -> Zurueckholen
        side.recall = K.Button(side, L["Bring back"], 100, 20, "primary", function()
            Weide.Recall()
            K.Toast(L["Guildotchi"], L["Your animal is back on the pasture."], C.mint)
            ns.RefreshPage("pasture", true)
        end)
        side.recall:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -8)
        side.recall:Hide()
        side.need = {}
        for i, n in ipairs(Weide.NEEDS) do
            local y = -48 - (i - 1) * 40
            local r = {}
            r.t = K.Text(side, 11, C.text)
            r.t:SetPoint("TOPLEFT", 12, y)
            r.bar = K.Bar(side, LIST_W - 24, 6)
            r.bar:SetPoint("TOPLEFT", 12, y - 20)
            r.btn = K.Button(side, L[n.act], 76, 20, "ghost", function()
                local ok, left = Weide.Care(n.key)
                if ok then
                    K.Toast(L["Gildotchi"], L["Baa! Thanks!"], C.mint)
                else
                    K.Toast(L["Gildotchi"], (L["Again in %s."]):format(fmtLeft(left)), C.amber or C.accent)
                end
                ns.RefreshPage("pasture", true)
            end)
            r.btn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, y + 3)
            r.need = n
            side.need[i] = r
        end
        side.h = K.Text(side, 13, C.text)
        side.h:SetPoint("TOPLEFT", 12, -178)
        side.h:SetText(L["Flock leaderboard"])
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
        local all = Weide.Flock()
        local flock = {}
        for _, f in ipairs(all) do if not f.away then flock[#flock + 1] = f end end   -- ausgebuexte Tiere sind nicht auf der Weide
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
                -- Startplatz: die freieste von 12 Stellen
                local bs = -1
                for _ = 1, 12 do
                    local x, y = math.random() * 0.9 + 0.05, math.random()
                    local sc = room(s, x, y, field.sheep)
                    if sc > bs then s.x, s.y, bs = x, y, sc end
                end
                pickTarget(s, field.sheep)
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
            -- 0.6.548: vernachlaessigt (Laune unter 20) grauer/kleiner, unter 8 legt es sich hin
            local sad = nd.mood < 20 and (20 - nd.mood) / 20 or 0
            if math.abs((s.sad or 0) - sad) > 0.05 then s.sad = sad light(s, s.skin, 1, 1, 1) end
            s.lying = nd.mood < 8 and not s.duel
            if s.lying then s.wish = L["Zzz ..."] s.wait = nil end
            s.streak = Weide.Streak(who.name)
            s:SetAlpha(who.online and 1 or 0.75)
            local st, nm = s.streak or 0, ns.short(who.name)
            if st >= 30 then nm = (ns.GuildPack and "|TInterface\\AddOns\\Oasis_Guild\\Media\\dr_crown:0|t " or "|T" .. ns.MEDIA .. "icons\\star_on:0|t ") .. "|cffffd24a" .. nm .. "|r"
            elseif st >= 14 then nm = "|T" .. ns.MEDIA .. "icons\\star_on:0|t |cffffd24a" .. nm .. "|r"
            elseif st >= 7 then nm = "|T" .. ns.MEDIA .. "icons\\star_on:0|t " .. nm end
            s.name:SetText(nm)
            s.name:SetAlpha(who.online and 0.95 or 0.6)
            s.name:Show()
            s:Show()
        end
        for i = n + 1, #field.sheep do
            local s = field.sheep[i]
            s:Hide() s.who = nil s.name:Hide() s.say:Hide() s.sayBg:Hide()
        end
        field.empty:SetText(#flock == 0 and L["No sheep on the pasture yet."] or "")

        -- aktuelles Aussehen
        local mine = myRank()
        p.bar.cur:SetText(L[Weide.FormOf(ns.me(), mine).text] .. " - " .. L[Weide.SkinOf(ns.me(), mine).text])
        if p.pick:IsShown() then p.pick:Update() end

        -- Mein Gildotchi
        local side = p.side
        local nd = Weide.Needs(ns.me())
        local mt, mc = Weide.MoodText(nd.mood)
        local st = Weide.Streak(ns.me())
        local nextX
        for _, x in ipairs(Weide.EXTRAS) do if st < x.n then nextX = x break end end
        side.mood:SetText(L["Mood"] .. ": " .. K.hex(mc) .. L[mt] .. "|r   " .. (L["Streak: %d days"]):format(st)
            .. (nextX and ("  |cff8a8a8a(" .. (L["%s from %d"]):format(L[nextX.text], nextX.n) .. ")|r") or ""))
        side.recall:SetShown(Weide.IsAway(ns.me()))
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
        side.sum:SetText((L["%d sheep, %d online now"]):format(#flock, on))
        for i, r in ipairs(side.rows) do
            local f = all[i]
            r:SetShown(f ~= nil)
            if f then
                r.pos:SetText(i .. ".")
                r.n:SetText(ns.short(f.name) .. (ns.isMe(f.name) and ("  |cff9a9a9a" .. L["(you)"] .. "|r") or "")
                    .. (f.away and ("  |cffe8a040" .. L["ran away"] .. "|r") or ""))
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

-- 0.6.545: AFK-Bildschirm - eigene Wiese im Vollbild, solange du AFK bist (nie im Kampf).
-- Klick, Taste oder "nicht mehr AFK" schliesst ihn.
local saver
function Weide.ShowSaver(force)
    if not force and ns.db.settings.gotchiAfk ~= true then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local def = ns.PageDef and ns.PageDef("pasture")
    if not def then return end
    if not saver then
        saver = CreateFrame("Frame", nil, UIParent)
        saver:SetFrameStrata("FULLSCREEN_DIALOG")
        saver:SetAllPoints(UIParent)
        saver:EnableMouse(true)
        K.Fill(saver, { 0, 0, 0, 1 })
        local inner = CreateFrame("Frame", nil, saver)
        inner:SetAllPoints()
        local ok, e = pcall(def.build, inner)
        if not ok then ns.err(L["Setup"] .. " Guildotchi AFK", e) saver:Hide() saver = nil return end
        inner.field:ClearAllPoints()
        inner.field:SetAllPoints(saver)
        for _, k in ipairs({ "bar", "side", "pick", "frameArt" }) do if inner[k] then inner[k]:Hide() end end
        if inner.logo then
            inner.logo:ClearAllPoints()
            inner.logo:SetPoint("TOP", saver, "TOP", 0, -24)
            inner.logo:SetSize(480, 176)
        end
        saver.inner = inner
        saver.hint = K.Text(saver, 13, C.text, "CENTER")
        saver.hint:SetPoint("BOTTOM", 0, 24)
        saver.hint:SetAlpha(0.7)
        saver.hint:SetText(L["You are AFK - click or press a key to close this screen."])
        saver:SetScript("OnMouseDown", function(self) self:Hide() end)
        saver:SetScript("OnKeyDown", function(self)
            if self.SetPropagateKeyboardInput and not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, true) end
            self:Hide()
        end)
        local t = 0
        saver:HookScript("OnUpdate", function(self, dt)
            t = t + (dt or 0)
            if t > 30 then t = 0 pcall(def.refresh, self.inner) end
        end)
    end
    pcall(saver.EnableKeyboard, saver, true)
    pcall(def.refresh, saver.inner)
    saver:Show()
end
function Weide.HideSaver() if saver then saver:Hide() end end
ns.On("PLAYER_FLAGS_CHANGED", function(unit)
    if unit ~= "player" then return end
    if UnitIsAFK and UnitIsAFK("player") then Weide.ShowSaver() else Weide.HideSaver() end
end)
ns.On("PLAYER_REGEN_DISABLED", function() Weide.HideSaver() end)
ns.slash.afkschafe = function() Weide.ShowSaver(true) end
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

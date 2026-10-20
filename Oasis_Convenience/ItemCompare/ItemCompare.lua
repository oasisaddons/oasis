-- Oasis: Item-Vergleich als eigenes Fenster neben dem Tooltip (Einstellungen > Helfer, Standard AUS)
--   Band oben:  BESSER +x % / SCHLECHTER / GLEICHWERTIG / NICHT TRAGBAR  + "statt <altes Item> · Wertung <Rolle>"
--   AUSWIRKUNG: was die Werte fuer deine Klasse bedeuten (DPS, Angriffskraft, Leben, Ruestung ...)
--   WERTE:      Tabelle jetzt / neu / +-
-- Blizzards Vergleichsfenster werden nur unsichtbar gemacht, solange dieses Fenster zu sehen ist (Shift = Blizzard).
-- Ist nesUI geladen und dessen Vergleich an, zeigt Oasis nichts (kein doppeltes Fenster).
-- Kein Taint: nur hooksecurefunc / HookScript / TooltipDataProcessor, nichts Geschuetztes wird ersetzt.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Itemvergleich", function()   -- Modul Item-Vergleich (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local IC = {}
ns.ItemCompare = IC

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARROW_UP = "Interface\\Buttons\\Arrow-Up-Up"
local ARROW_DN = "Interface\\Buttons\\Arrow-Down-Up"
local SHOP = { "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }
local W = 344
local COL_NOW, COL_NEW, COL_DIFF = -138, -80, -16

local function S() return ns.db and ns.db.settings or {} end

-- nesUI zeigt denselben Vergleich -> dann bleibt Oasis still
function IC.NesUIActive()
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, r = pcall(C_AddOns.IsAddOnLoaded, "nesUI")
        loaded = ok and r and true or false
    elseif IsAddOnLoaded then
        local ok, r = pcall(IsAddOnLoaded, "nesUI")
        loaded = ok and r and true or false
    end
    if not loaded then return false end
    return not (type(nesUIDB) == "table" and nesUIDB.compareOff == true)
end
function IC.Enabled()
    return S().itemCompare == true and not IC.NesUIActive()
end

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
local function fmt(v)
    local r = math.floor(math.abs(v) * 10 + 0.5) / 10
    local s = (r == math.floor(r)) and tostring(math.floor(r)) or (tostring(r):gsub("%.", ","))
    return (v > 0 and "+" or v < 0 and "-" or "") .. s
end

-- Blizzard-Schluessel -> Kurzname, Anzeige-Reihenfolge, Anzeigename
local STATS = {
    { "DAMAGE_PER_SECOND", "dps", "Waffen-DPS" },
    { "STRENGTH", "str", "Staerke" }, { "AGILITY", "agi", "Beweglichkeit" }, { "STAMINA", "sta", "Ausdauer" },
    { "INTELLECT", "int", "Intelligenz" }, { "SPIRIT", "spi", "Willenskraft" },
    { "RANGED_ATTACK_POWER", "rap", "Distanz-Angriffskraft" }, { "ATTACK_POWER", "ap", "Angriffskraft" },
    { "SPELL_HEALING", "heal", "Heilung" }, { "HEALING", "heal", "Heilung" },
    { "SPELL_DAMAGE", "sp", "Zauberschaden" }, { "SPELL_POWER", "sp", "Zauberschaden" },
    { "SPELL_CRIT", "scrit", "Zauberkrit" }, { "SPELL_HIT", "shit", "Zaubertreffer" },
    { "CRIT", "crit", "Krit" }, { "HIT", "hit", "Trefferchance" },
    { "MANA_REGENERATION", "mp5", "Mana alle 5 Sek." }, { "POWER_REGEN0", "mp5", "Mana alle 5 Sek." },
    { "DEFENSE", "def", "Verteidigung" }, { "DODGE", "dodge", "Ausweichen" }, { "PARRY", "parry", "Parieren" },
    { "BLOCK", "block", "Blocken" }, { "RESISTANCE0", "armor", "Ruestung" },
}
local ORDER, NAMES = {}, {}
for i, s in ipairs(STATS) do
    if not ORDER[s[2]] then ORDER[s[2]] = i; NAMES[s[2]] = s[3] end
end

-- Wertungen ("_RATING", neuere Clients): Name im Klartext ("Kritischer Trefferwert"), fuer die
-- Auswirkung in Prozent umgerechnet
local RATED = {}
local RATING_NAMES = { crit = "Kritischer Trefferwert", hit = "Trefferwertung", scrit = "Zauberkrit-Wertung", shit = "Zaubertreffer-Wertung",
    dodge = "Ausweichwertung", parry = "Parierwertung", block = "Blockwertung", def = "Verteidigungswertung" }
function IC.StatName(k)
    if RATED[k] and RATING_NAMES[k] then return L[RATING_NAMES[k]] end
    return L[NAMES[k] or k]
end
local function itemStats(link)
    local out = {}
    if not link or not (C_Item and C_Item.GetItemStats) then return out end
    local ok, t = pcall(C_Item.GetItemStats, link)
    if not ok or type(t) ~= "table" then return out end
    for k, v in pairs(t) do
        if type(k) == "string" then
            for _, s in ipairs(STATS) do
                if k:find(s[1], 1, true) then
                    out[s[2]] = (out[s[2]] or 0) + (tonumber(v) or 0)
                    if k:find("_RATING", 1, true) then RATED[s[2]] = true end
                    break
                end
            end
        end
    end
    return out
end

local function instant(link)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, id, _, _, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return nil end
    return id, loc, classID, subID
end

-- getragene Teile, die das neue ersetzen wuerde; false = genau dieses Teil wird getragen, nil = kein Platz
local function replaced(link, loc)
    local UP = ns.Upgrade
    local slots = UP and UP.SLOTS and UP.SLOTS[loc or ""]
    if not slots then return nil end
    if loc == "INVTYPE_2HWEAPON" then
        local mh, oh = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17)
        if mh == link then return false end
        return { mh, oh }
    end
    local best, bestScore
    for _, s in ipairs(slots) do
        local l = GetInventoryItemLink("player", s)
        if l == link then return false end
        local sc = l and (UP.Score and UP.Score(l) or 0) or -1
        if not bestScore or sc < bestScore then best, bestScore = l, sc end
        if not l then break end
    end
    return { best }
end

-- Was die Werte fuer DEINE Klasse bedeuten (Classic-Faustregeln)
local STR_AP = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2 }
local AGI_AP = { ROGUE = 1, HUNTER = 1 }
local function plusMinus(d, nm)
    local ks = {}
    for k, v in pairs(d) do if v ~= 0 then ks[#ks + 1] = k end end
    table.sort(ks, function(a, b) return (ORDER[a] or 99) < (ORDER[b] or 99) end)
    local p, m = {}, {}
    for _, k in ipairs(ks) do
        local t = d[k] > 0 and p or m
        if #t < 3 then t[#t + 1] = nm(k) end
    end
    return p, m
end
local function effects(d, role, cls)
    local e = {}
    local ap = (d.ap or 0) + (d.str or 0) * (STR_AP[cls] or 1) + (d.agi or 0) * (AGI_AP[cls] or 0)
    local rap = (d.rap or 0) + (d.ap or 0) + (cls == "HUNTER" and (d.agi or 0) * 2 or 0)
    if role == "ranged" then
        local dps = (d.dps or 0) + rap / 14
        if math.abs(dps) > 0.01 then e[#e + 1] = { "Schaden pro Sekunde", dps, true } end
        if rap ~= 0 then e[#e + 1] = { "Distanz-Angriffskraft", rap } end
    elseif role == "melee" or role == "agile" or role == "tank" then
        local dps = (d.dps or 0) + ap / 14
        if math.abs(dps) > 0.01 then e[#e + 1] = { "Schaden pro Sekunde", dps, role ~= "tank" } end
        if ap ~= 0 then e[#e + 1] = { "Angriffskraft", ap } end
    elseif role == "caster" then
        if (d.sp or 0) ~= 0 then e[#e + 1] = { "Zauberschaden", d.sp, true } end
    elseif role == "healer" then
        local h = (d.heal or 0) + (d.sp or 0)
        if h ~= 0 then e[#e + 1] = { "Heilung", h, true } end
    end
    if (d.sta or 0) ~= 0 then e[#e + 1] = { "Leben", d.sta * 10, role == "tank" } end
    if (d.int or 0) ~= 0 and cls ~= "WARRIOR" and cls ~= "ROGUE" then e[#e + 1] = { "Mana", d.int * 15 } end
    -- Krit/Treffer als Prozent (Wertung umgerechnet) - damit sichtbar ist, woher ein "Besser" kommt
    local rpp = (ns.Upgrade and ns.Upgrade.RatingPerPct and ns.Upgrade.RatingPerPct()) or 14
    local function pctOf(k) local v = d[k] or 0 if RATED[k] then v = v / rpp end return v end
    local critK, hitK = (role == "caster" or role == "healer") and "scrit" or "crit", (role == "caster") and "shit" or "hit"
    if role ~= "healer" and math.abs(pctOf(hitK)) > 0.005 then e[#e + 1] = { "Trefferchance", pctOf(hitK), false, " %" } end
    if math.abs(pctOf(critK)) > 0.005 then e[#e + 1] = { "Kritische Trefferchance", pctOf(critK), false, " %" } end
    local armor = (d.armor or 0) + (d.agi or 0) * 2
    if armor ~= 0 then e[#e + 1] = { "Ruestung", armor } end
    return e
end

-- Grund, warum ich es nicht anziehen kann (nil = tragbar)
local HEAVY = { SHAMAN = true, HUNTER = true, WARRIOR = true, PALADIN = true }
function IC.Blocked(link)
    local UP = ns.Upgrade
    local _, cls = UnitClass("player")
    local lvl = ns.safe and ns.safe(UnitLevel("player")) or UnitLevel("player")
    lvl = tonumber(lvl) or 1
    -- 0.5.942: lernbar, aber noch nicht gelernt (rote Zeile im Tooltip)
    if UP and UP.CanWearFor and UP.CanWearFor(link, cls, lvl) and UP.Unlearned and UP.Unlearned(link) then
        return L["Noch nicht gelernt - diese Waffen- oder Ruestungsart kannst du noch nicht anlegen"]
    end
    if UP and UP.CanWearFor and not UP.CanWearFor(link, cls, lvl) then
        local _, _, classID, subID = instant(link)
        if classID == 4 and (subID == 3 or subID == 4) and lvl < 40 and HEAVY[cls] then
            return (L[subID == 3 and "Schwere Ruestung erst ab Stufe 40" or "Platte erst ab Stufe 40"])
        end
        return L["Fuer deine Klasse nicht tragbar"]
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, req = pcall(C_Item.GetItemInfo, link)
        req = ok and tonumber(req)
        if req and req > lvl then return (L["Benoetigt Stufe %d"]):format(req) end
    end
    return nil
end

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------
local P = CreateFrame("Frame", "OasisItemCompare", UIParent)
IC.frame = P
P:SetFrameStrata("TOOLTIP")
P:SetFrameLevel(200)
P:SetClampedToScreen(true)
P:Hide()

-- Ruhige Glaskarte: Urteil und Rollenwertung, ohne farbige Pille oder Leuchteffekte.
-- Vergleichsteil umbricht statt abgeschnitten zu werden, Abschnitte in normaler Schreibweise
local function tex(layer, sub) local t = P:CreateTexture(nil, layer, nil, sub) t:SetTexture(WHITE) return t end
local glassDone = false
local function ensureGlass()
    if glassDone then return end
    local G = ns.Insta and ns.Insta.Glass
    if G then
        G(P, { 0.045, 0.045, 0.05, 0.94 }, { 1, 1, 1, 0.12 }, 12)
        glassDone = true
    elseif not P.bg then
        P.bg = tex("BACKGROUND", -8) P.bg:SetAllPoints() P.bg:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 0.95)
    end
end
-- Urteil oben links; reine Typografie statt einer zweiten Karte in der Karte.
local pill = CreateFrame("Frame", nil, P)
pill:SetHeight(20)
pill:SetPoint("TOPLEFT", 12, -12)
pill.t = pill:CreateFontString(nil, "OVERLAY")
pill.t:SetPoint("LEFT", 2, 0)

-- Pools
local texts, nText = {}, 0
local function txt(size, color, justify)
    nText = nText + 1
    local fs = texts[nText]
    if not fs then fs = P:CreateFontString(nil, "OVERLAY") texts[nText] = fs end
    fs:ClearAllPoints() fs:SetWidth(0) fs:SetWordWrap(false)
    if K.SetFontSafe then K.SetFontSafe(fs, K.FONT, size, "", "Fonts\\ARIALN.TTF") else fs:SetFont(K.FONT, size, "") end
    fs:SetShadowOffset(1, -1) fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetTextColor(color[1], color[2], color[3]) fs:SetJustifyH(justify or "LEFT") fs:Show()
    return fs
end
local stripes, nStripe = {}, 0
local function stripe(y, h, c, a)
    nStripe = nStripe + 1
    local t = stripes[nStripe]
    if not t then t = tex("BACKGROUND", -5) stripes[nStripe] = t end
    t:ClearAllPoints() t:SetPoint("TOPLEFT", 8, y) t:SetPoint("TOPRIGHT", -8, y) t:SetHeight(h)
    t:SetVertexColor(c[1], c[2], c[3], a) t:Show()
end
local lines, nLine = {}, 0
local function divider(y)
    nLine = nLine + 1
    local t = lines[nLine]
    if not t then t = tex("ARTWORK") lines[nLine] = t end
    t:ClearAllPoints() t:SetPoint("TOPLEFT", 12, y) t:SetPoint("TOPRIGHT", -12, y) t:SetHeight(1)
    t:SetVertexColor(1, 1, 1, 0.07) t:Show()
end

-- Prozent-Wertungen (Krit, Treffer ...) kommen auf neueren Clients als Wertung ("_RATING") -> Umrechnung
local PCT_KEYS = { crit = true, hit = true, scrit = true, shit = true, dodge = true, parry = true, block = true }
local function ratingPerPct()
    local UP = ns.Upgrade
    return (UP and UP.RatingPerPct and UP.RatingPerPct()) or 14
end

-- Standard: nur veraenderte Werte. Alt: auch unveraenderte Werte und Erklaerung.
function IC.DetailMode()
    return IsAltKeyDown and IsAltKeyDown() and true or false
end
function IC.CompareRows(keys, current, candidate, details)
    local rows = {}
    for k in pairs(keys) do
        if details or math.abs((candidate[k] or 0) - (current[k] or 0)) > 0.001 then rows[#rows + 1] = k end
    end
    table.sort(rows, function(a, b)
        local x, y = ORDER[a] or 99, ORDER[b] or 99
        return x == y and a < b or x < y
    end)
    return rows
end

-- baut den Inhalt; false = nichts zu vergleichen. Ergebnis zum Testen in IC.last
function IC.Build(link)
    for i = 1, #texts do texts[i]:Hide() end
    for i = 1, #stripes do stripes[i]:Hide() end
    for i = 1, #lines do lines[i]:Hide() end
    nText, nStripe, nLine = 0, 0, 0
    ensureGlass()

    local _, loc = instant(link)
    local UP = ns.Upgrade
    -- Vergleichsteil aus UP.CompareInfo: Kopf, "statt"-Zeile und Tabelle zeigen dasselbe Teil
    local info = UP and UP.CompareInfo and UP.CompareInfo(link)
    local old
    if info then
        if info.worn then return false end
        old = info.against
    else
        old = replaced(link, loc)
    end
    if not old then return false end

    local new, cur = itemStats(link), {}
    for _, l in pairs(old) do for k, v in pairs(itemStats(l)) do cur[k] = (cur[k] or 0) + v end end
    local diff, keys = {}, {}
    for k in pairs(new) do keys[k] = true end
    for k in pairs(cur) do keys[k] = true end
    for k in pairs(keys) do
        local v = (new[k] or 0) - (cur[k] or 0)
        if math.abs(v) > 0.001 then diff[k] = v end
    end

    local pct, roleName, role
    if info then pct, roleName = info.pct, info.roleName
    elseif UP and UP.Compare then pct, roleName = UP.Compare(link) end
    role = UP and UP.Role and UP.Role() or "melee"
    local _, cls = UnitClass("player")
    local blocked = IC.Blocked(link)
    local useless = (not blocked) and info and info.useless
    -- 0.5.877: tragbar, bringt der Rolle aber nichts -> das ist "Schlechter", nicht "Unpassend"
    if blocked then pct = nil end
    if useless and (pct == nil or pct >= 0) then pct = nil end
    -- kleine Unterschiede (unter 3 %) sind "seitwaerts", kein echtes Besser/Schlechter
    local side = pct and math.abs(pct) < 3
    local up = pct and pct > 0 and not side
    -- Teil ohne Rollenwerte (z.B. reine Ruestung): Urteil aus den rohen Werten - nur Plus = besser, nur Minus = schlechter, gemischt = neutral
    local rawDir
    if useless and pct == nil then
        local nPlus, nMinus = 0, 0
        for _, v in pairs(diff) do if v > 0 then nPlus = nPlus + 1 elseif v < 0 then nMinus = nMinus + 1 end end
        rawDir = (nPlus > 0 and nMinus == 0 and "BESSER") or (nMinus > 0 and nPlus == 0 and "SCHLECHTER") or (nPlus == 0 and nMinus == 0 and "GLEICHWERTIG") or "VOR- & NACHTEILE"
    end
    local tone = blocked and C.muted or (rawDir and ((rawDir == "BESSER" and C.mint) or (rawDir == "SCHLECHTER" and C.red) or C.blue))
        or ((pct == nil or side) and C.blue or (up and C.mint or C.red))
    local verdict = blocked and "NICHT TRAGBAR" or rawDir or (pct == nil and "VOR- & NACHTEILE")
        or (pct == 0 and "GLEICHWERTIG") or (side and "SEITWAERTS") or (up and "BESSER" or "SCHLECHTER")
    local LABEL = { ["NICHT TRAGBAR"] = "Nicht tragbar", ["UNPASSEND"] = "Unpassend", ["VOR- & NACHTEILE"] = "Vor- und Nachteile",
        ["GLEICHWERTIG"] = "Gleichwertig", ["SEITWAERTS"] = "Seitwaerts", ["BESSER"] = "Besser", ["SCHLECHTER"] = "Schlechter" }
    local verdictText = L[LABEL[verdict]]
    -- Kopf (Urteil + Prozent) als eigener, kraeftiger getoenter Bereich mit Trennlinie; darunter laeuft die Farbe weich aus.
    -- gruen = besser, rot = schlechter, blau = neutral
    local HEAD_H = 50
    if not P.head then
        P.head = P:CreateTexture(nil, "BACKGROUND", nil, 4)
        P.head:SetPoint("TOPLEFT", 1, -1)
        P.head:SetPoint("TOPRIGHT", -1, -1)
        P.head:SetHeight(HEAD_H)
        P.head:SetTexture(WHITE)
        if K.RoundMask then pcall(K.RoundMask, P.head, P, 12, { "tl", "tr" }) end
        P.headLine = P:CreateTexture(nil, "BACKGROUND", nil, 5)
        P.headLine:SetPoint("TOPLEFT", 1, -1 - HEAD_H)
        P.headLine:SetPoint("TOPRIGHT", -1, -1 - HEAD_H)
        P.headLine:SetHeight(1)
        P.headLine:SetTexture(WHITE)
        P.tone = P:CreateTexture(nil, "BACKGROUND", nil, 4)
        P.tone:SetPoint("TOPLEFT", 1, -2 - HEAD_H)
        P.tone:SetPoint("TOPRIGHT", -1, -2 - HEAD_H)
        P.tone:SetHeight(90)
    end
    do
        local strong = (rawDir == "BESSER" or rawDir == "SCHLECHTER") or (not rawDir and not (pct == nil or side))
        local on = not blocked
        P.head:SetShown(on) P.headLine:SetShown(on) P.tone:SetShown(on)
        if on then
            P.head:SetVertexColor(tone[1], tone[2], tone[3], strong and 0.26 or 0.14)
            P.headLine:SetVertexColor(tone[1], tone[2], tone[3], strong and 0.55 or 0.30)
            P.tone:SetTexture(WHITE)
            local a = strong and 0.12 or 0.06
            if not (K.Gradient and K.Gradient(P.tone, "VERTICAL", { tone[1], tone[2], tone[3], 0 }, { tone[1], tone[2], tone[3], a })) then
                P.tone:SetColorTexture(tone[1], tone[2], tone[3], a * 0.4)
            end
        end
    end

    local details = IC.DetailMode()
    -- 1) Kopf: klares Urteil, Prozentwert mit eigener Bezeichnung.
    pill.t:SetFont(K.FONT, 14, "")
    pill.t:SetTextColor(math.min(1, tone[1] + 0.15), math.min(1, tone[2] + 0.15), math.min(1, tone[3] + 0.15))
    pill.t:SetText(verdictText)
    pill:SetWidth(math.max(40, (pill.t:GetStringWidth() or 50) + 22))
    pill:Show()
    local pctText
    -- Teile ohne Rollenwerte: Prozent aus den rohen Werten (Summe neu gegen Summe jetzt), damit oben immer eine Zahl steht
    local showPct, capText = pct, L["Rollenwertung"]
    if rawDir == "BESSER" or rawDir == "SCHLECHTER" then
        local sn, sc = 0, 0
        for _, v in pairs(new) do sn = sn + v end
        for _, v in pairs(cur) do sc = sc + v end
        local base = math.max(sn, sc)
        if base > 0 then
            showPct = math.floor((sn - sc) / base * 100 + (sn >= sc and 0.5 or -0.5))
            capText = L["Rohwerte"]
        end
    end
    if showPct and showPct ~= 0 then
        pctText = (showPct > 0 and "+" or "") .. showPct .. " %"
        local p = txt(22, tone, "RIGHT") p:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, -10) p:SetText(pctText)
        local caption = txt(9, C.dim, "RIGHT")
        caption:SetPoint("TOPRIGHT", P, "TOPRIGHT", -16, -35)
        caption:SetText(capText)
    end
    local y = -58
    local oldName = old[1] and old[1]:match("%[(.-)%]") or L["leerer Platz"]
    local subText
    if blocked then
        subText = blocked .. "  ·  " .. L["Werte nur zur Info"]
    elseif useless then
        subText = L["statt"] .. " " .. oldName
    else
        local p, m = plusMinus(diff, function(k) return IC.StatName(k) end)
        if pct == nil and #p > 0 and #m > 0 then
            subText = L["Mehr"] .. " " .. table.concat(p, ", ") .. "  ·  " .. L["weniger"] .. " " .. table.concat(m, ", ")
        else
            subText = L["statt"] .. " " .. oldName
        end
    end
    if not P.oldIcon then
        P.oldIcon = P:CreateTexture(nil, "ARTWORK")
        P.oldIcon:SetSize(26, 26)
        P.oldIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        P.oldEdge = P:CreateTexture(nil, "BORDER")
        P.oldEdge:SetPoint("TOPLEFT", P.oldIcon, "TOPLEFT", -1, 1)
        P.oldEdge:SetPoint("BOTTOMRIGHT", P.oldIcon, "BOTTOMRIGHT", 1, -1)
    end
    local oldID = old[1] and tonumber(tostring(old[1]):match("item:(%d+)"))
    local oldIcon = oldID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(oldID)
    local plainOld = subText == (L["statt"] .. " " .. oldName)
    P.oldIcon:SetShown(plainOld and oldIcon ~= nil)
    P.oldEdge:SetShown(plainOld and oldIcon ~= nil)
    if plainOld and oldIcon then
        -- "statt" klein, darunter Symbol + Name in der Farbe der Seltenheit
        local lab = txt(10, C.dim) lab:SetPoint("TOPLEFT", 14, y) lab:SetText(L["statt"])
        y = y - 14
        P.oldIcon:ClearAllPoints()
        P.oldIcon:SetPoint("TOPLEFT", 15, y - 1)
        P.oldIcon:SetTexture(oldIcon)
        local q = select(3, C_Item.GetItemInfo(old[1]))
        if issecretvalue and issecretvalue(q) then q = nil end
        if type(q) ~= "number" then q = tonumber(tostring(old[1]):match("|cnIQ(%d):")) or 1 end
        local QC = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.55, 1 }, [4] = { 0.78, 0.35, 1 }, [5] = { 1, 0.5, 0 } }
        local qc = QC[q] or QC[1]
        P.oldEdge:SetColorTexture(qc[1], qc[2], qc[3], 0.9)
        local nm = txt(13, qc) nm:SetPoint("TOPLEFT", 50, y - 1) nm:SetWidth(W - 64) nm:SetWordWrap(true) nm:SetText(oldName)
        y = y - math.max(28, (nm:GetStringHeight() or 14) + 2) - 6
    else
        local sub = txt(12, C.text) sub:SetPoint("TOPLEFT", 14, y) sub:SetWidth(W - 28) sub:SetWordWrap(true) sub:SetText(subText)
        y = y - math.max(14, sub:GetStringHeight() or 14) - 6
    end
    if roleName and not blocked then
        local rl = txt(10, C.dim) rl:SetPoint("TOPLEFT", 14, y) rl:SetText((L["Bewertet fuer %s"]):format(roleName) .. (useless and ("  ·  " .. L["bringt dieser Rolle keine Werte"]) or ""))
        y = y - 18
    end
    y = y - 8

    -- 2) Auswirkung
    local eff = effects(diff, role, cls)
    if #eff > 0 then
        divider(y) y = y - 8
        local h = txt(11, C.muted) h:SetPoint("TOPLEFT", 14, y) h:SetText(L["Auswirkung"])
        y = y - 21
        for _, e in ipairs(eff) do
            local big = e[3]
            local c = e[2] > 0 and C.mint or C.red
            local rh = big and 24 or 21
            local l = txt(big and 13 or 12, big and C.text or C.muted) l:SetPoint("TOPLEFT", 14, y)
            l:SetWidth(W - 112) l:SetText(L[e[1]])
            local r = txt(big and 13 or 12, c, "RIGHT") r:SetPoint("TOPRIGHT", P, "TOPRIGHT", -14, y) r:SetText(fmt(e[2]) .. (e[4] or ""))
            y = y - rh
        end
        y = y - 6
    end

    -- 3) Werte-Tabelle: Name | jetzt | neu | +-
    local list = IC.CompareRows(keys, cur, new, details)
    if #list > 0 then
        divider(y) y = y - 8
        local h1 = txt(11, C.muted) h1:SetPoint("TOPLEFT", 14, y) h1:SetText(L["Werte"])
        local h2 = txt(10, C.dim, "RIGHT") h2:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_NOW, y) h2:SetText(L["Jetzt"])
        local h3 = txt(10, C.dim, "RIGHT") h3:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_NEW, y) h3:SetText(L["Neu"])
        local h4 = txt(10, C.dim, "RIGHT") h4:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_DIFF, y) h4:SetText("±")
        y = y - 22
        for i, k in ipairs(list) do
            local a, b = cur[k] or 0, new[k] or 0
            local d = b - a
            if i % 2 == 1 then stripe(y + 3, 22, C.text, 0.025) end
            local n = txt(12, C.text) n:SetPoint("TOPLEFT", 14, y) n:SetWidth(W + COL_NOW - 14 - 30) n:SetText(IC.StatName(k))
            local c1 = txt(12, C.dim, "RIGHT") c1:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_NOW, y) c1:SetText((fmt(a):gsub("^%+", "")))
            local c2 = txt(12, C.text, "RIGHT") c2:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_NEW, y) c2:SetText((fmt(b):gsub("^%+", "")))
            local changed = math.abs(d) > 0.001
            local c3 = txt(12, changed and (d > 0 and C.mint or C.red) or C.dim, "RIGHT")
            c3:SetPoint("TOPRIGHT", P, "TOPRIGHT", COL_DIFF, y) c3:SetText(changed and fmt(d) or "=")
            y = y - 22
        end
    end

    if #list == 0 then
        local same = txt(11, C.dim)
        same:SetPoint("TOPLEFT", 14, y) same:SetText(L["Keine veraenderten Grundwerte."])
        y = y - 20
    end
    y = y - 8
    divider(y) y = y - 10
    if details then
        local note = txt(10, C.muted)
        note:SetPoint("TOPLEFT", 14, y) note:SetWidth(W - 28) note:SetWordWrap(true)
        note:SetText(L["Die Prozentzahl vergleicht die Item-Wertung fuer deine Rolle, nicht deinen gesamten Schaden. Auswirkungen sind Schaetzwerte."])
        y = y - math.max(14, note:GetStringHeight() or 14) - 10
    end
    local hint = txt(10, C.dim)
    hint:SetPoint("TOPLEFT", 14, y) hint:SetWidth(W - 28) hint:SetWordWrap(true)
    hint:SetText(details and L["Alt loslassen: kompakter Vergleich. Shift: Blizzard-Vergleich."]
        or L["Alt halten: alle Werte und Bewertung. Shift: Blizzard-Vergleich."])
    y = y - math.max(14, hint:GetStringHeight() or 14) - 4

    P:SetSize(W, -y + 10)
    IC.last = { verdict = verdict, text = verdictText, pct = pct, sub = subText, nowName = oldName, effects = eff, rows = #list, blocked = blocked, details = details }
    return true
end

------------------------------------------------------------------------
-- Blizzards Vergleichsfenster: unsichtbar, solange UNSER Fenster da ist (Shift = zeigen)
------------------------------------------------------------------------
local function shiftDown() return IsShiftKeyDown and IsShiftKeyDown() and true or false end
local function hideShopping()
    local hide = P:IsShown() and not shiftDown()
    for _, n in ipairs(SHOP) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(hide and 0 or 1) end
        -- 0.5.974: zusaetzlich wirklich ausblenden. Die Deckkraft allein reicht in diesem Client nicht: Blizzards
        -- Einblend-Animation setzt sie wieder hoch und der Kopf "Ausgeruestet" blieb sichtbar -> es blinkte dahinter.
        if hide and t and t.IsShown and t:IsShown() then pcall(t.Hide, t) end
    end
end
IC.HideShopping = hideShopping
P:HookScript("OnHide", hideShopping)
P:HookScript("OnHide", function(self)
    if K.Tween then K.Tween(self, 0.01, function() end) end
    self:SetAlpha(1)
end)
local hooked = false
local function hookShopping()
    if hooked then return end
    hooked = true
    for _, n in ipairs(SHOP) do
        local t = _G[n]
        if t then
            -- Blizzard setzt die Deckkraft selbst zurueck -> nur solange unser Fenster sichtbar ist, wieder auf 0
            if hooksecurefunc and t.SetAlpha then
                hooksecurefunc(t, "SetAlpha", function(self, a)
                    if a and a > 0 and P:IsShown() and not shiftDown() then self:SetAlpha(0) end
                end)
            end
            -- sofort (im selben Frame) wieder weg: ein Frame spaeter war es schon einmal gezeichnet -> Blinken
            if t.HookScript then
                t:HookScript("OnShow", function(self)
                    if P:IsShown() and not shiftDown() then
                        self:SetAlpha(0)
                        pcall(self.Hide, self)
                    end
                end)
            end
        end
    end
end

-- Blizzard-Fenster, das trotzdem sichtbar bleibt: genau darueberlegen
local contentH = 0
P:HookScript("OnShow", function(self) contentH = self:GetHeight() or 0 end)
local function coverShopping(self)
    if shiftDown() then return end
    for _, n in ipairs(SHOP) do
        local t = _G[n]
        if t and t:IsShown() and (t:GetAlpha() or 0) > 0.05 and t:GetLeft() then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
            self:SetWidth(math.max(W, t:GetWidth() or W))
            self:SetHeight(math.max(contentH, t:GetHeight() or 0))
            return
        end
    end
end
P:HookScript("OnUpdate", coverShopping)

function IC.ShowFor(tt, link)
    if not IC.Enabled() or not tt or type(link) ~= "string" or not link:find("item:") then P:Hide() return false end
    local ok, built = pcall(IC.Build, link)
    if not ok then ns.debug("ItemCompare: " .. tostring(built)) P:Hide() return false end
    if not built then P:Hide() return false end
    hookShopping()
    local changed = not P:IsShown() or IC.link ~= link
    IC.tooltip, IC.link = tt, link
    contentH = P:GetHeight() or 0
    local ts, us = tt:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
    P:SetScale(us > 0 and ts / us or 1)
    P:ClearAllPoints()
    -- 0.5.978: Platz suchen, der auf den Bildschirm passt UND das Fenster des ueberfahrenen Items nicht verdeckt
    -- (beim Verkaufen lag das Vergleichsfenster ueber den Taschen). Reihenfolge: rechts, links, darueber, darunter.
    local placed = false
    do
        local tl, tr, tT, tb
        if tt.GetLeft and tt.GetTop then tl, tr, tT, tb = tt:GetLeft(), tt:GetRight(), tt:GetTop(), tt:GetBottom() end
        if tl and tr and tT and tb then
            tl, tr, tT, tb = tl * ts, tr * ts, tT * ts, tb * ts            -- alles in Bildschirm-Pixeln
            local sw, sh = (UIParent:GetWidth() or 0) * us, (UIParent:GetHeight() or 0) * us
            local pw, ph = W * ts, (P:GetHeight() or contentH or 200) * ts
            -- Fenster, zu dem das Item gehoert: vom Besitzer des Tooltips hoch bis zum Fenster direkt unter UIParent
            local box
            local ok, owner = pcall(function() return tt.GetOwner and tt:GetOwner() end)
            local f, guard = ok and owner or nil, 0
            while f and f.GetParent and guard < 12 do
                local par = f:GetParent()
                if par == UIParent or par == nil then break end
                f, guard = par, guard + 1
            end
            if f and f ~= UIParent and f.GetLeft and f:GetLeft() then
                local fs = f:GetEffectiveScale() or 1
                box = { f:GetLeft() * fs, f:GetRight() * fs, f:GetTop() * fs, f:GetBottom() * fs }
            end
            local G = 6 * ts
            local cands = {
                { "TOPLEFT", "TOPRIGHT", 6, 0, tr + G, tT - ph },
                { "TOPRIGHT", "TOPLEFT", -6, 0, tl - G - pw, tT - ph },
                { "BOTTOMLEFT", "TOPLEFT", 0, 6, tl, tT + G },
                { "TOPLEFT", "BOTTOMLEFT", 0, -6, tl, tb - G - ph },
            }
            for _, c in ipairs(cands) do
                local l, b = c[5], c[6]
                local r, t = l + pw, b + ph
                local onScreen = l >= 0 and r <= sw and b >= 0 and t <= sh
                local hits = box and not (r <= box[1] or l >= box[2] or t <= box[4] or b >= box[3])
                if onScreen and not hits then
                    P:SetPoint(c[1], tt, c[2], c[3], c[4])
                    placed = true
                    break
                end
            end
        end
    end
    if not placed then
        if (tt:GetRight() or 0) + W + 6 < (UIParent:GetWidth() or 0) then
            P:SetPoint("TOPLEFT", tt, "TOPRIGHT", 6, 0)
        else
            P:SetPoint("TOPRIGHT", tt, "TOPLEFT", -6, 0)
        end
    end
    P:Show()
    if changed and K.Tween and not S().noAnim then
        P:SetAlpha(0.72)
        K.Tween(P, 0.14, function(p) P:SetAlpha(0.72 + 0.28 * p) end, function() P:SetAlpha(1) end)
    elseif S().noAnim then
        if K.Tween then K.Tween(P, 0.01, function() end) end
        P:SetAlpha(1)
    end
    hideShopping()
    return true
end

-- Einstieg aus dem Tooltip (einen Frame spaeter: andere Addons haengen Zeilen nach)
function IC.OnItem(tt)
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    if not IC.Enabled() then if P:IsShown() then P:Hide() end return end
    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok or not link then return end
    ns.After(0, function()
        if not tt:IsShown() then return end
        local ok2, _, l2 = pcall(tt.GetItem, tt)
        if ok2 and l2 == link then IC.ShowFor(tt, link) end
    end)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) pcall(IC.OnItem, tt) end)
else
    for _, n in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tt = _G[n]
        if tt and tt.HasScript and tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self) pcall(IC.OnItem, self) end)
        end
    end
end

if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnHide", function()
        if not P:IsShown() then return end
        P:Hide()
        -- angeklickter Link noch offen: dessen Vergleich wieder zeigen
        if ItemRefTooltip and ItemRefTooltip:IsShown() and IC.Enabled() then
            local ok, _, l = pcall(ItemRefTooltip.GetItem, ItemRefTooltip)
            if ok and l then pcall(IC.ShowFor, ItemRefTooltip, l) end
        end
    end)
end
if ItemRefTooltip and ItemRefTooltip.HookScript then
    ItemRefTooltip:HookScript("OnHide", function() if not GameTooltip:IsShown() then P:Hide() end end)
end

-- Shift: Blizzard-Vergleich ein-/ausblenden
local shiftEv = CreateFrame("Frame")
shiftEv:RegisterEvent("MODIFIER_STATE_CHANGED")
shiftEv:SetScript("OnEvent", function()
    local tt = IC.tooltip
    if not P:IsShown() or not tt or not tt:IsShown() then return end
    if IC.last and IC.last.details ~= IC.DetailMode() then IC.ShowFor(tt, IC.link) end
    if shiftDown() and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, tt) end
    hideShopping()
end)

------------------------------------------------------------------------
-- Einstellung: Reiter "Helfer" > "Charaktere & Ausruestung" (an ComfortPlus2-Liste anhaengen, nichts ersetzen)
------------------------------------------------------------------------
local OPT = { "itemCompare", "Vergleichsfenster unter dem Item-Tooltip",
    "Zeigt Besser / Schlechter / Nicht tragbar mit Auswirkung (DPS, Leben, Ruestung) und Werte-Tabelle. Blizzards Vergleich erscheint dann nur mit Shift. Ist nesUI mit eigenem Vergleich geladen, zeigt Oasis nichts (sonst doppelt) - dort mit /nes vergleich abschalten.",
    function(v) if not v then P:Hide() end end }
local function addOption()
    local H2 = ns.Helpers2
    if not (H2 and type(H2.OPTS) == "table") then return false end
    for _, grp in ipairs(H2.OPTS) do
        for _, o in ipairs(grp[2] or {}) do if o[1] == OPT[1] then return true end end
    end
    local target
    for _, grp in ipairs(H2.OPTS) do if grp[1] == "Charaktere & Ausruestung" then target = grp end end
    if target then table.insert(target[2], OPT)
    else table.insert(H2.OPTS, { "Charaktere & Ausruestung", { OPT } }) end
    return true
end
if not addOption() and ns.Listen then ns.Listen("DB_READY", addOption) end

-- /oa probe vergleich: was liefern die APIs hier?
ns.probes = ns.probes or {}
ns.probes.vergleich = function()
    local p = ns.print or print
    p("|cffe8b44a/oa probe vergleich|r an=" .. tostring(S().itemCompare == true) .. " nesUI=" .. tostring(IC.NesUIActive())
        .. " TooltipDataProcessor=" .. tostring(TooltipDataProcessor ~= nil) .. " GetItemStats=" .. tostring(C_Item and C_Item.GetItemStats ~= nil))
    for _, n in ipairs(SHOP) do p("  " .. n .. "=" .. tostring(_G[n] ~= nil)) end
    local l = GetInventoryItemLink("player", 16)
    if l then
        local ok, t = pcall(C_Item.GetItemStats, l)
        local c = 0
        if ok and type(t) == "table" then for _ in pairs(t) do c = c + 1 end end
        p("  Waffe: " .. l .. " Werte=" .. c .. " gesperrt=" .. tostring(IC.Blocked(l)))
    end
end
end)

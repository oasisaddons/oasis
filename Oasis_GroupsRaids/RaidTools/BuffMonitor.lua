-- Oasis - Buff-Monitor (schwebendes Fenster): wer in Gruppe/Raid welche Buffs hat, was fehlt, was DU geben kannst
-- Kategorien schaltbar: Klassen-Buffs, Flaeschchen, Elixiere, Essen, Weltbuffs, Schutztraenke.
-- Auren nur ausserhalb des Kampfes lesen (im Kampf "secret") - im Kampf zeigt das Fenster den letzten Stand.
-- Schnittstelle (BuffPage.lua, RaidCheck.lua): BM.Scan() -> list, cols, missing, total, done, info
--   list[i] = { unit, name, class, dead, away, has = { [key] = true }, exp = { [key] = Ablaufzeit }, src = { [key] = Aura-Name } }
--   cols[j] = Buff-Definition { key, cat, cls, short, label, icon, cons }
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Core\Diagnostics\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C = ns.K, ns.K.C

local BM = {}
ns.BuffMonitor = BM

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
-- Kategorien in Anzeigereihenfolge
local CATS = {
    { key = "class", label = "Klassen-Buffs", short = "Klasse" },
    { key = "flask", label = "Flaeschchen", short = "Flasche" },
    { key = "elixir", label = "Elixiere", short = "Elixier" },
    { key = "food", label = "Essen", short = "Essen" },
    { key = "world", label = "Weltbuffs", short = "Welt" },
    { key = "prot", label = "Schutztraenke", short = "Schutz" },
}
local CAT_BY = {}
for i, c in ipairs(CATS) do c.order = i CAT_BY[c.key] = c end

-- Buffs: ids = Einzelzauber (Raenge aufsteigend, Classic-IDs), gids = Gruppenversion, pat = Namens-Teilstuecke (klein, DE+EN)
-- cons = Verbrauchsgut/Weltbuff (keine Klasse noetig), soft = nur Hinweis (zaehlt nicht zur Vollstaendigkeit)
local NOT_CLASS = { "elixier", "elixir", "trank", "potion", "fläschchen", "flask" }
local BUFFS = {
    { key = "fort", cat = "class", cls = "PRIEST", short = "Ausdauer",
        ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, gids = { 21562, 21564 },
        pat = { "seelenstärke", "fortitude" } },
    { key = "spirit", cat = "class", cls = "PRIEST", short = "Willen",
        ids = { 14752, 14818, 14819, 27841 }, gids = { 27681 },
        pat = { "göttlicher wille", "willenskraft", "divine spirit", "prayer of spirit" } },
    { key = "shadow", cat = "class", cls = "PRIEST", short = "Schatten",
        ids = { 976, 10957, 10958 }, gids = { 27683 },
        pat = { "schattenschutz", "shadow protection" } },
    { key = "motw", cat = "class", cls = "DRUID", short = "Wildnis",
        ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, gids = { 21849, 21850 },
        pat = { "mal der wildnis", "gabe der wildnis", "mark of the wild", "gift of the wild" } },
    { key = "int", cat = "class", cls = "MAGE", short = "Intelligenz",
        ids = { 1459, 1460, 1461, 10156, 10157 }, gids = { 23028 },
        pat = { "arkane intelligenz", "arkane brillanz", "arcane intellect", "arcane brilliance" } },
    { key = "kings", cat = "class", cls = "PALADIN", short = "Koenige",
        ids = { 20217 }, gids = { 25898 },
        pat = { "segen der könige", "blessing of kings" } },
    { key = "might", cat = "class", cls = "PALADIN", short = "Macht",
        ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, gids = { 25782, 25916 },
        pat = { "segen der macht", "blessing of might" } },
    { key = "wisdom", cat = "class", cls = "PALADIN", short = "Weisheit",
        ids = { 19742, 19850, 19852, 19853, 19854, 25290 }, gids = { 25894, 25918 },
        pat = { "segen der weisheit", "blessing of wisdom" } },
    -- Totems: Aura nur in Totem-Reichweite und nur fuer die eigene Gruppe -> Hinweis, zaehlt nicht
    { key = "totem", cat = "class", cls = "SHAMAN", short = "Totem", soft = true, icon = 136023,
        ids = { 8076, 8162, 8163, 10441, 25362, 8836, 10627, 25359, 5677, 10491, 10493, 10494 }, gids = {},
        pat = { "stärke der erde", "strength of earth", "anmut der luft", "grace of air", "manaquelle", "mana spring" } },
    -- Flaeschchen
    { key = "flask", cat = "flask", cons = true, short = "Fläschchen", item = 13510,
        ids = { 17626, 17627, 17628, 17629 },
        pat = { "fläschchen", "flask" } },
    -- Elixiere (Kampf- und Zauberelixiere zusammen)
    { key = "elixir", cat = "elixir", cons = true, short = "Elixier", item = 13452,
        ids = { 17538, 11405, 26276, 11474, 11334, 17537, 24363, 17539, 11390, 3593, 11348, 11349, 16323, 16329, 17038 },
        pat = { "elixier", "elixir", "mungo", "mongoose", "der riesen", "of the giants", "feuermacht", "firepower",
            "schattenmacht", "shadow power", "zanza", "mojo", "rohe gewalt", "brute force", "blutmagie", "mageblood" } },
    -- Essen
    { key = "food", cat = "food", cons = true, short = "Essen", item = 13935,
        ids = { 19705, 19706, 19708, 19709, 19710, 19711, 24799, 25661, 18192, 18194, 18222, 18141, 22730 },
        pat = { "satt", "well fed", "gut genährt", "gut gesättigt" } },
    -- Weltbuffs
    { key = "world", cat = "world", cons = true, short = "Weltbuff", item = 19002,
        ids = { 22888, 16609, 15366, 24425, 22817, 22818, 22820 },
        pat = { "drachentöter", "dragonslayer", "kriegshäuptling", "warchief's blessing", "liebliche serenade", "songflower",
            "geist von zandalar", "spirit of zandalar", "fengus", "mol'dar", "slip'kik" } },
    -- Schutztraenke (Feuer - Onyxia)
    { key = "fireprot", cat = "prot", cons = true, short = "Feuerschutz", item = 13457,
        ids = { 17543, 7233, 7230 },
        pat = { "feuerschutz", "fire protection" } },
}
BM.CATS = CATS

local CLASSNAME = { PRIEST = "Priester", MAGE = "Magier", DRUID = "Druide", PALADIN = "Paladin", SHAMAN = "Schamane",
    WARRIOR = "Krieger", ROGUE = "Schurke", HUNTER = "Jaeger", WARLOCK = "Hexenmeister" }
local SOON = 120   -- Sekunden: darunter "laeuft bald ab"

-- Zustand
local f                    -- Fenster
local lastAuras = {}       -- Name -> Auren vom letzten Lesen ausserhalb des Kampfes
local myCast = {}          -- Buff-Key -> Zaubername, den ich wirken kann
local prepared, castPrepared = false, false
local scrollOff = 0
local pendingShow          -- im Kampf gewuenschtes Ein-/Ausblenden
local pending

------------------------------------------------------------------------
-- Helfer
------------------------------------------------------------------------
local function S() return ns.db and ns.db.settings or {} end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() or false end
local function simOn() return ns.Sim and ns.Sim.Active() or false end
local function spellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, t = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(t) == "table" then return ns.safe(t.name), ns.safe(t.iconID) end
    end
    local n
    if C_Spell and C_Spell.GetSpellName then
        local ok, r = pcall(C_Spell.GetSpellName, id)
        if ok then n = ns.safe(r) end
    end
    local ic
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, r = pcall(C_Spell.GetSpellTexture, id)
        if ok then ic = ns.safe(r) end
    end
    if (not n or not ic) and GetSpellInfo then
        local ok, a, _, b = pcall(GetSpellInfo, id)
        if ok then n = n or ns.safe(a) ic = ic or ns.safe(b) end
    end
    return n, ic
end
local function itemIcon(id)
    local ok, ic = pcall(function()
        return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    end)
    return ok and ic or nil
end
local function knows(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, r = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and r then return true end
    end
    if IsPlayerSpell then
        local ok, r = pcall(IsPlayerSpell, id)
        if ok and r then return true end
    end
    if IsSpellKnown then
        local ok, r = pcall(IsSpellKnown, id)
        if ok and r then return true end
    end
    return false
end
local function className(cls)
    return L[CLASSNAME[cls] or cls or "?"]
end
local function colorName(name, cls)
    local r, g, b = ns.classColor(cls)
    return ("|cff%02x%02x%02x"):format((r or 0.8) * 255, (g or 0.8) * 255, (b or 0.8) * 255) .. ns.displayName(name) .. "|r"
end
local function fmtLeft(sec)
    if not sec then return L["ohne Ablauf"] end
    if sec >= 3600 then return ("%d h %02d min"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return ("%d min"):format(math.floor(sec / 60)) end
    return ("%d s"):format(math.max(0, math.floor(sec)))
end
local function inOnyxia()
    if simOn() then local i = ns.Group.Instance() return i and i.key == "onyxia" or false end
    local n
    if GetInstanceInfo then
        local ok, a = pcall(GetInstanceInfo)
        if ok then n = ns.safe(a) end
    end
    n = type(n) == "string" and n:lower() or ""
    return n:find("onyxia", 1, true) ~= nil
end

-- Kategorie an? (prot: "auto" = nur in Onyxias Hort)
local function catOn(key)
    local s = S()
    local t = s.buffCats
    local v = t and t[key]
    if v == nil then
        if key == "class" then v = true
        elseif key == "flask" or key == "elixir" or key == "food" then v = s.buffCons ~= false
        elseif key == "prot" then v = "auto"
        else v = false end
    end
    if v == "auto" then return inOnyxia(), "auto" end
    return v and true or false, v
end
BM.CatOn = catOn
local function setCat(key, v)
    local s = S()
    s.buffCats = s.buffCats or {}
    s.buffCats[key] = v
end

-- Namen/Symbole aus dem Spiel (lokalisiert)
local function prep()
    if prepared then return end
    for _, b in ipairs(BUFFS) do
        b.names, b.idset = {}, {}
        for _, id in ipairs(b.ids or {}) do b.idset[id] = true end
        for _, id in ipairs(b.gids or {}) do b.idset[id] = true end
        local ic
        if b.item then ic = itemIcon(b.item) end
        for _, id in ipairs(b.ids or {}) do
            local n, i2 = spellInfo(id)
            if n and not b.cons then b.names[n] = true end
            ic = ic or i2
        end
        for _, id in ipairs(b.gids or {}) do
            local n = spellInfo(id)
            if n then b.names[n] = true end
        end
        b.icon = b.icon or ic or 134400
        if b.cons then b.label = L[b.short]
        else b.label = (b.ids[1] and spellInfo(b.ids[1])) or L[b.short] end
    end
    prepared = true
end
BM.BUFFS, BM.Prep = BUFFS, prep

-- Was kann ich buffen? (hoechster bekannter Rang des Einzelzaubers)
local function prepCast()
    if castPrepared then return end
    for k in pairs(myCast) do myCast[k] = nil end
    local _, me = UnitClass("player")
    for _, b in ipairs(BUFFS) do
        if not b.cons and not b.soft and b.cls == me then
            for i = #b.ids, 1, -1 do
                if knows(b.ids[i]) then
                    myCast[b.key] = spellInfo(b.ids[i]) or false
                    break
                end
            end
        end
    end
    castPrepared = true
end
BM.MyCast = function() prepCast() return myCast end

------------------------------------------------------------------------
-- Auren lesen
------------------------------------------------------------------------
local function readAuras(unit)
    local out = {}
    for i = 1, 40 do
        local ok, a
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        elseif C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
            ok, a = pcall(C_UnitAuras.GetBuffDataByIndex, unit, i)
        elseif UnitBuff then
            local ok2, n, _, _, _, _, exp, _, _, _, sid = pcall(UnitBuff, unit, i)
            ok = ok2
            a = ok2 and n and { name = n, expirationTime = exp, spellId = sid } or nil
        end
        if not ok or not a then break end
        local name = ns.safe(a.name)
        local exp = ns.safe(a.expirationTime)
        out[#out + 1] = {
            name = type(name) == "string" and name or nil,
            low = type(name) == "string" and name:lower() or nil,
            id = tonumber(ns.safe(a.spellId)),
            exp = (type(exp) == "number" and exp > 0) and exp or nil,
        }
    end
    return out
end
local function matches(b, au)
    if au.id and b.idset[au.id] then return true end
    if au.name and b.names[au.name] then return true end
    if au.low then
        if not b.cons then
            for _, x in ipairs(NOT_CLASS) do if au.low:find(x, 1, true) then return false end end
        end
        for _, pt in ipairs(b.pat) do if au.low:find(pt, 1, true) then return true end end
    end
    return false
end

------------------------------------------------------------------------
-- Gruppe
------------------------------------------------------------------------
local function units()
    local out = {}
    local n = ns.Group.Num()
    if ns.Group.IsInRaid() then
        for i = 1, n do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, math.max(0, n - 1) do out[#out + 1] = "party" .. i end
    end
    return out
end
-- Beispielgruppe (Demo): Restzeiten in Sekunden, fehlende Keys = Buff fehlt
local function demoList()
    local _, me = UnitClass("player")
    local myName = ns.safe(ns.UnitName("player")) or "Du"
    local rows = {
        { name = myName, class = me or "WARRIOR", d = { fort = 1500, motw = 1600, flask = 5400, food = 700, elixir = 90 } },
        { name = "Heilfix", class = "PRIEST", d = { fort = 1700, int = 1500, motw = 1700, spirit = 1600, flask = 6200, food = 800 } },
        { name = "Funkenbart", class = "MAGE", d = { fort = 80, int = 1700, food = 400, elixir = 2400 } },
        { name = "Krallix", class = "DRUID", d = { motw = 1750, int = 1400, flask = 3000 } },
        { name = "Brumm", class = "WARRIOR", d = { fort = 1600, motw = 100, elixir = 3000, food = 900, totem = 10 } },
        { name = "Donnerhuf", class = "SHAMAN", d = { food = 300, totem = 10, world = 4000 } },
    }
    local list = {}
    for i, r in ipairs(rows) do
        list[i] = { unit = nil, name = r.name, class = r.class, demo = r.d, dead = false, away = false }
    end
    list[1].unit = "player"
    return list
end

-- Stand: Spalten (eingeschaltete Kategorien, Klassen-Buffs nur wenn die Klasse da ist), Zeilen je Mitglied
function BM.Scan()
    prep()
    prepCast()
    local list, classes, byClass = {}, {}, {}
    local sim = simOn()
    local demo = not sim and demoOn() and not ns.Group.IsInGroup()
    if sim then
        -- Raid-Simulator: Restzeiten aus den simulierten Buffs (Ablaufzeit GetTime)
        local t0 = GetTime and GetTime() or 0
        for _, m in ipairs(ns.Group.Members()) do
            local d = {}
            for k, exp in pairs(m.buffs or {}) do if exp > t0 then d[k] = exp - t0 end end
            list[#list + 1] = { unit = m.isMe and "player" or nil, name = m.name, class = m.class, demo = d, dead = m.dead and true or false, away = not m.online, sim = true }
        end
    elseif demo then
        list = demoList()
    else
        for _, u in ipairs(units()) do
            if UnitExists(u) then
                local _, cf = UnitClass(u)
                list[#list + 1] = { unit = u, name = ns.safe(ns.UnitName(u)) or "?", class = cf, dead = ns.safe(UnitIsDeadOrGhost(u)) and true or false,
                    away = not ns.safe(UnitIsConnected(u)) }
            end
        end
    end
    for _, r in ipairs(list) do
        if r.class then
            classes[r.class] = true
            if not r.away then
                byClass[r.class] = byClass[r.class] or {}
                table.insert(byClass[r.class], r.name)
            end
        end
    end
    local cols = {}
    for _, b in ipairs(BUFFS) do
        if catOn(b.cat) and (b.cons or classes[b.cls]) then cols[#cols + 1] = b end
    end
    local combat = ns.inCombat()
    local now = GetTime and GetTime() or 0
    local missing, total, done = {}, 0, 0
    local info = { providers = {}, mine = {}, complete = 0, players = 0, soon = 0, demo = demo, sim = sim, combat = combat }
    for _, r in ipairs(list) do
        r.has, r.exp, r.src = {}, {}, {}
        local auras
        if r.demo then
            auras = nil
        elseif r.away then
            auras = {}
        elseif combat then
            auras = lastAuras[r.name] or {}
        else
            auras = readAuras(r.unit)
            lastAuras[r.name] = auras
        end
        local full = true
        for _, b in ipairs(cols) do
            local hit, exp, src = false, nil, nil
            if r.demo then
                local left = r.demo[b.key]
                if left then hit = true exp = now + left src = b.label end
            else
                for _, au in ipairs(auras) do
                    if matches(b, au) then hit = true exp = au.exp src = au.name break end
                end
            end
            r.has[b.key] = hit or nil
            r.exp[b.key] = exp
            r.src[b.key] = src
            if not r.away and not r.dead and not b.soft then
                total = total + 1
                if hit then
                    done = done + 1
                    if exp and exp - now < SOON then info.soon = info.soon + 1 end
                else
                    missing[b.key] = (missing[b.key] or 0) + 1
                    full = false
                end
            end
        end
        if not r.away and not r.dead then
            info.players = info.players + 1
            if full then info.complete = info.complete + 1 end
        end
    end
    for _, b in ipairs(cols) do
        if b.cls then info.providers[b.key] = byClass[b.cls] or {} end
        if myCast[b.key] then info.mine[b.key] = myCast[b.key] end
    end
    return list, cols, missing, total, done, info
end

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------
local function dims()
    if S().buffCompact then return { RH = 16, CS = 12, CW = 16, NW = 84, GAP = 4, compact = true } end
    return { RH = 22, CS = 18, CW = 24, NW = 116, GAP = 8 }
end
local function hasSecure() return f and f.secureMade end
local function lockedNow() return ns.inCombat() and hasSecure() end

local function savePos()
    if not f then return end
    local l, t = f:GetLeft(), f:GetTop()
    if l and t then S().buffPos = { l, t } end
end

local function cellTip(self)
    if self.tipLines then K.ShowTip(self, self.tipLines) end
end

local function build()
    f = CreateFrame("Frame", "OasisBuffMonitor", UIParent)
    f:SetSize(320, 200)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    pcall(f.SetResizable, f, true)
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 220, 120, 1200, 1000)
    elseif f.SetMinResize then pcall(f.SetMinResize, f, 220, 120) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if S().buffLock or lockedNow() then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not S().buffLock then savePos() end
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, d)
        if lockedNow() then return end
        scrollOff = math.max(0, scrollOff - (d or 0) * 3)
        BM.Update()
    end)
    local pos = S().buffPos
    if pos and pos[1] then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2]) else f:SetPoint("CENTER", 300, 0) end
    K.Fill(f, { 0.04, 0.04, 0.05, 0.94 })
    K.Border(f, C.line)

    f.head = K.GameHead(f, L["Buff-Monitor"], C.mint)
    f.head:SetPoint("TOPLEFT", 10, -8)
    f.head:SetWidth(120)
    f.close = K.CloseButton(f, function() BM.Toggle(false) end)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    f.gear = K.IconButton(f, "*", 18, function(self) BM.Menu(self) end, { L["Einstellungen"], L["Kategorien ein- und ausschalten, kompakt, festsetzen"] })
    f.gear:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    if f.gear.label then
        f.gear.label:SetText("")
        f.gear.ic = f.gear:CreateTexture(nil, "ARTWORK")
        f.gear.ic:SetTexture(ns.MEDIA .. "icons\\settings")
        f.gear.ic:SetSize(14, 14)
        f.gear.ic:SetPoint("CENTER")
        f.gear.ic:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
    end
    f.sum = K.Text(f, 11, C.muted, "RIGHT")
    f.sum:SetPoint("RIGHT", f.gear, "LEFT", -6, 0)

    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetPoint("TOPLEFT", 10, -28)
    f.bar:SetPoint("TOPRIGHT", -10, -28)
    f.bar:SetHeight(3)
    K.Fill(f.bar, { 1, 1, 1, 0.07 })
    f.bar.fill = f.bar:CreateTexture(nil, "ARTWORK")
    f.bar.fill:SetPoint("LEFT")
    f.bar.fill:SetHeight(3)

    -- Hinweise: was ich buffen kann / was andere buffen koennten
    f.info = K.Text(f, 11, C.text)
    f.info:SetPoint("TOPLEFT", 10, -38)
    f.info:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.info:SetJustifyH("LEFT")
    f.info:SetWordWrap(true)

    f.catLabels, f.colHeads, f.rows = {}, {}, {}
    f.note = K.Text(f, 11, C.dim, "CENTER")
    f.note:SetWordWrap(true)

    f.post = K.Button(f, L["Ansagen"], 70, 18, "ghost", function() BM.Post() end)
    f.post:SetPoint("BOTTOMLEFT", 8, 6)
    f.post:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Fehlende Buffs ansagen"], L["Kurze Nachricht im Gruppen- bzw. Raidchat (nur ausserhalb des Kampfes)"] }) end)
    f.post:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.hint = K.Text(f, 10, C.dim)
    f.hint:SetPoint("LEFT", f.post, "RIGHT", 8, 0)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -22, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetWordWrap(false)

    -- Groesse aendern (Hoehe; Breite folgt den Spalten)
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(14, 14)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip.t = f.grip:CreateTexture(nil, "OVERLAY")
    f.grip.t:SetAllPoints()
    f.grip.t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetScript("OnMouseDown", function()
        if S().buffLock or lockedNow() then return end
        f.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    f.grip:SetScript("OnMouseUp", function()
        if not f.sizing then return end
        f.sizing = false
        f:StopMovingOrSizing()
        local h = f:GetHeight()
        if h and h > 0 then S().buffH = math.floor(h + 0.5) end
        savePos()
        BM.Update()
    end)

    -- gedrosselt: Restzeiten nachziehen (alle 5 s), Leuchten der Zeilen (nur sichtbar, ohne noAnim)
    f.tick, f.pulse = 0, 0
    f:SetScript("OnUpdate", function(self, el)
        self.tick = self.tick + el
        if self.tick >= 5 then self.tick = 0 if not ns.inCombat() then BM.Update() end end
        if S().noAnim or not self.glowing then return end
        self.pulse = self.pulse + el
        if self.pulse < 0.05 then return end
        self.t2 = ((self.t2 or 0) + self.pulse) % 1.6
        self.pulse = 0
        local a = 0.10 + 0.10 * (0.5 + 0.5 * math.cos(self.t2 / 1.6 * math.pi * 2))
        for _, r in ipairs(self.rows) do if r.glowOn and r:IsShown() then r.glow:SetAlpha(a) end end
    end)
end

local function catLabel(i)
    local t = f.catLabels[i]
    if t then return t end
    t = K.Text(f, 9, C.dim, "LEFT")
    t:SetWordWrap(false)
    t.line = f:CreateTexture(nil, "ARTWORK")
    t.line:SetHeight(1)
    f.catLabels[i] = t
    return t
end
local function head(i)
    local h = f.colHeads[i]
    if h then return h end
    h = CreateFrame("Frame", nil, f)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetPoint("TOP", 0, 0)
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.n = K.Text(h, 10, C.text, "CENTER")
    h.n:SetPoint("TOP", h.icon, "BOTTOM", 0, -1)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.colHeads[i] = h
    return h
end
local function row(i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    r.glow = r:CreateTexture(nil, "BORDER")
    r.glow:SetAllPoints()
    r.glow:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
    r.glow:SetAlpha(0)
    r.cls = r:CreateTexture(nil, "ARTWORK")
    r.cls:SetPoint("TOPLEFT") r.cls:SetPoint("BOTTOMLEFT") r.cls:SetWidth(2)
    r.name = K.Text(r, 12, C.text)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetWordWrap(false)
    r.cells = {}
    f.rows[i] = r
    return r
end
-- Kaestchen: sicherer Knopf (Linksklick = mein Buff wirken bzw. Ziel, Rechtsklick = Ziel) - nur ausserhalb des Kampfes angelegt/umgestellt
local function cell(r, j)
    local c = r.cells[j]
    if c then return c end
    local ok, b = pcall(CreateFrame, "Button", nil, r, "SecureActionButtonTemplate")
    if ok and b then
        c = b
        c.secure = true
        f.secureMade = true
        pcall(c.RegisterForClicks, c, "AnyUp", "AnyDown")
    else
        c = CreateFrame("Button", nil, r)
    end
    c.border = c:CreateTexture(nil, "BORDER")
    c.border:SetPoint("TOPLEFT", -1, 1) c.border:SetPoint("BOTTOMRIGHT", 1, -1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.mark = c:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("CENTER")
    c.x = c:CreateTexture(nil, "OVERLAY", nil, -1)
    c.x:SetAllPoints()
    c:SetScript("OnEnter", cellTip)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.cells[j] = c
    return c
end
local function setCellAction(c, unit, spell)
    if not c.secure or ns.inCombat() then return end
    pcall(function()
        c:SetAttribute("unit", unit)
        if unit and spell then
            c:SetAttribute("type1", "spell")
            c:SetAttribute("spell1", spell)
        elseif unit then
            c:SetAttribute("type1", "target")
            c:SetAttribute("spell1", nil)
        else
            c:SetAttribute("type1", nil)
            c:SetAttribute("spell1", nil)
        end
        c:SetAttribute("type2", unit and "target" or nil)
    end)
end

local function providerText(b, info, list)
    local who = info.providers[b.key] or {}
    if #who == 0 then return nil end
    local parts = {}
    for i, n in ipairs(who) do
        if i > 3 then parts[#parts + 1] = "..." break end
        parts[#parts + 1] = ns.isMe(n) and L["du"] or ns.displayName(n)
    end
    return className(b.cls) .. " (" .. table.concat(parts, ", ") .. ")"
end

function BM.Update()
    if not f or not f:IsShown() then return end
    if ns.inCombat() then
        f.hint:SetText("|cffe8b44a" .. L["Im Kampf: letzter Stand, nichts klickbar umgestellt"] .. "|r")
        return
    end
    local D = dims()
    local list, cols, missing, total, done, info = BM.Scan()
    local now = GetTime and GetTime() or 0

    -- Kopf
    f.sum:SetText(info.players > 0 and (L["%d/%d vollstaendig"]):format(info.complete, info.players) or "")
    local pct = total > 0 and done / total or 1
    local bc = pct >= 1 and C.mint or (pct >= 0.7 and C.amber or C.red)
    f.bar.fill:SetColorTexture(bc[1], bc[2], bc[3], 1)
    f.bar.fill:SetWidth(math.max(1, (f.bar:GetWidth() or 300) * pct))

    -- Hinweiszeilen
    local lines = {}
    local mineMissing = {}   -- key -> true, wenn ich ihn geben kann und er jemandem fehlt
    for _, b in ipairs(cols) do
        local m = missing[b.key] or 0
        if info.mine[b.key] ~= nil and m > 0 then
            mineMissing[b.key] = true
            lines[#lines + 1] = "|cffe8b44a" .. L["Du kannst"] .. ":|r " .. b.label .. " - " .. (L["fehlt bei %d"]):format(m)
        end
    end
    if not D.compact then
        for _, b in ipairs(cols) do
            local m = missing[b.key] or 0
            if b.cls and m > 0 and info.mine[b.key] == nil then
                local p = providerText(b, info, list)
                if p then lines[#lines + 1] = "|cff9999a0" .. p .. " " .. L["da"] .. ":|r " .. b.label .. " " .. (L["fehlt bei %d"]):format(m) end
            end
            if #lines >= 4 then break end
        end
    end
    f.info:SetText(table.concat(lines, "\n"))
    f.info:SetShown(#lines > 0)
    local infoH = #lines > 0 and (#lines * 13 + 4) or 0

    -- Spalten-Positionen, nach Kategorie gruppiert
    local x0 = 10 + D.NW
    local xs, lastCat, x = {}, nil, x0
    local groups = {}
    for j, b in ipairs(cols) do
        if lastCat and lastCat ~= b.cat then x = x + D.GAP end
        if lastCat ~= b.cat then groups[#groups + 1] = { cat = b.cat, x1 = x } end
        xs[j] = x
        groups[#groups].x2 = x + D.CW
        x = x + D.CW
        lastCat = b.cat
    end
    local width = math.max(D.compact and 200 or 260, x + 10)
    local top = 36 + infoH
    -- Kategorie-Beschriftungen
    for _, t in ipairs(f.catLabels) do t:Hide() t.line:Hide() end
    for i, g in ipairs(groups) do
        local t = catLabel(i)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", g.x1, -top)
        t:SetWidth(math.max(8, g.x2 - g.x1 + D.GAP))
        t:SetText(K.Upper(L[CAT_BY[g.cat].short]))
        t.line:ClearAllPoints()
        t.line:SetPoint("TOPLEFT", f, "TOPLEFT", g.x1 + 2, -(top + 11))
        t.line:SetWidth(math.max(2, g.x2 - g.x1 - 4))
        t.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        t:SetShown(not D.compact)
        t.line:Show()
    end
    local headTop = top + (D.compact and 4 or 14)

    -- Spaltenkoepfe
    for _, h in ipairs(f.colHeads) do h:Hide() end
    local isize = D.compact and 14 or 20
    for j, b in ipairs(cols) do
        local h = head(j)
        h:SetSize(D.CW, isize + 12)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", f, "TOPLEFT", xs[j], -headTop)
        h.icon:SetSize(isize, isize)
        h.icon:SetTexture(b.icon)
        local m = missing[b.key] or 0
        if b.soft then h.n:SetText("|cff888888-|r")
        else h.n:SetText(m > 0 and ("|cffff5a4a" .. m .. "|r") or ("|cff66db9e" .. L["ok"] .. "|r")) end
        local who = {}
        for _, r in ipairs(list) do if not r.has[b.key] and not r.away and not r.dead then who[#who + 1] = ns.displayName(r.name) end end
        local tip = { b.label, "|cff888888" .. L[CAT_BY[b.cat].label] .. "|r" }
        tip[#tip + 1] = m > 0 and ((L["fehlt bei %d"]):format(m) .. ": " .. table.concat(who, ", ")) or L["alle haben ihn"]
        if b.cls then tip[#tip + 1] = L["Geben kann"] .. ": " .. (providerText(b, info, list) or className(b.cls)) end
        if b.soft then tip[#tip + 1] = L["Totem-Auren nur in Reichweite - zaehlt nicht zur Vollstaendigkeit"] end
        if info.mine[b.key] ~= nil then tip[#tip + 1] = "|cffe8b44a" .. L["Du kannst diesen Buff geben"] .. "|r" end
        h.tip = tip
        h:Show()
    end
    local rowsTop = headTop + isize + 14

    -- Zeilen: Hoehe aus Einstellung (Groessengriff), Rest per Mausrad
    local footer = 28
    local maxH = S().buffH or (ns.Group.IsInRaid() and 520 or 400)
    local fit = math.max(1, math.floor((maxH - rowsTop - footer) / D.RH))
    local n = #list
    if scrollOff > math.max(0, n - fit) then scrollOff = math.max(0, n - fit) end
    local shown = math.min(n - scrollOff, fit)
    local glowing = false
    for _, r in ipairs(f.rows) do r:Hide() end
    for vi = 1, shown do
        local m = list[vi + scrollOff]
        local r = row(vi)
        r:SetHeight(D.RH - 2)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(rowsTop + (vi - 1) * D.RH))
        r:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        local cr, cg, cb = ns.classColor(m.class)
        r.cls:SetColorTexture(cr or 0.5, cg or 0.5, cb or 0.5, 1)
        K.SetFontSafe(r.name, K.FONT, D.compact and 10 or 12, "", K.FONT)
        r.name:SetWidth(D.NW - 6)
        local tag = m.away and ("  |cff777777" .. L["offline"] .. "|r") or (m.dead and ("  |cff777777" .. L["tot"] .. "|r") or "")
        r.name:SetText(colorName(m.name, m.class) .. tag)
        local needMe = false
        for _, c in pairs(r.cells) do c:Hide() end
        for j, b in ipairs(cols) do
            local c = cell(r, j)
            c:SetSize(D.CS, D.CS)
            c:ClearAllPoints()
            c:SetPoint("LEFT", r, "LEFT", xs[j] - 6 + (D.CW - D.CS) / 2, 0)
            local has = m.has[b.key]
            local left = m.exp[b.key] and (m.exp[b.key] - now) or nil
            local soon = has and left and left < SOON
            local off = m.away or m.dead
            local canMe = info.mine[b.key] ~= nil and not has and not off and not b.soft
            if canMe then needMe = true end
            -- Darstellung: Symbol (normal) bzw. Farbflaeche (kompakt), Rand gruen/gelb/rot
            local col = has and (soon and C.amber or C.mint) or (b.soft and C.dim or C.red)
            if D.compact then
                c.icon:SetTexture(nil)
                c.icon:SetColorTexture(col[1], col[2], col[3], off and 0.15 or (has and 0.85 or 0.55))
            else
                c.icon:SetTexture(b.icon)
                c.icon:SetDesaturated(not has)
                c.icon:SetAlpha(has and 1 or 0.3)
            end
            local bcol = canMe and C.accent or col
            c.border:SetColorTexture(bcol[1], bcol[2], bcol[3], off and 0 or (has and 0.55 or 0.85))
            c.x:SetColorTexture(0.9, 0.2, 0.2, (has or off or b.soft or D.compact) and 0 or 0.22)
            if not D.compact and has and not soon then
                c.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                c.mark:SetSize(D.CS * 0.6, D.CS * 0.6)
                c.mark:ClearAllPoints() c.mark:SetPoint("BOTTOMRIGHT", 2, -2)
                c.mark:Show()
            else
                c.mark:Hide()
            end
            -- Tooltip
            local tip = { colorName(m.name, m.class) .. "  -  " .. b.label }
            if has then
                tip[#tip + 1] = (soon and "|cffe8b44a" or "|cff66db9e") .. L["drauf"] .. "|r" .. (m.src[b.key] and (": " .. m.src[b.key]) or "")
                tip[#tip + 1] = L["Restzeit"] .. ": " .. fmtLeft(left)
            elseif off then
                tip[#tip + 1] = "|cff777777" .. (m.away and L["offline"] or L["tot"]) .. "|r"
            else
                tip[#tip + 1] = "|cffff5a4a" .. L["fehlt"] .. "|r"
            end
            if b.cls then tip[#tip + 1] = L["Geben kann"] .. ": " .. (providerText(b, info, list) or className(b.cls)) end
            if m.unit and c.secure then
                tip[#tip + 1] = "|cff888888" .. (canMe and L["Linksklick: Buff wirken - Rechtsklick: als Ziel"] or L["Klick: als Ziel waehlen"]) .. "|r"
            end
            c.tipLines = tip
            setCellAction(c, m.unit, (canMe or (has and info.mine[b.key] ~= nil)) and info.mine[b.key] or nil)
            c:Show()
        end
        r.glowOn = needMe
        r.glow:SetAlpha(needMe and 0.14 or 0)
        if needMe then glowing = true end
        r:Show()
    end
    f.glowing = glowing

    -- Hinweis ohne Spalten/Gruppe
    local empty = #cols == 0 or #list == 0
    f.note:ClearAllPoints()
    f.note:SetPoint("TOP", f, "TOP", 0, -(top + 10))
    f.note:SetWidth(width - 20)
    f.note:SetShown(empty)
    f.note:SetText(#list == 0 and L["Nicht in einer Gruppe."]
        or L["Keine Kategorie aktiv oder keine passende Klasse in der Gruppe - Zahnrad oben rechts."])

    local h = empty and (top + 70) or (rowsTop + shown * D.RH + footer + 4)
    f:SetSize(width, h)
    local more = n - scrollOff - shown
    local hint
    if info.demo then hint = "|cff9999a0" .. L["Beispielgruppe (Demo)"] .. "|r"
    elseif info.sim and scrollOff == 0 and more <= 0 then hint = "|cff9999a0" .. L["Simulierter Raid"] .. "|r"
    elseif scrollOff > 0 or more > 0 then hint = (L["Mausrad: %d weitere"]):format(scrollOff + more)
    elseif pct >= 1 and total > 0 then hint = "|cff66db9e" .. L["Alles gebufft!"] .. "|r"
    elseif info.soon > 0 then hint = "|cffe8b44a" .. (L["%d laufen bald ab"]):format(info.soon) .. "|r"
    else hint = "" end
    f.hint:SetText(hint)
    f.post:SetShown(total > done and #list > 1)
    f.hint:ClearAllPoints()
    if f.post:IsShown() then f.hint:SetPoint("LEFT", f.post, "RIGHT", 8, 0) else f.hint:SetPoint("BOTTOMLEFT", 10, 10) end
    f.hint:SetPoint("RIGHT", f, "RIGHT", -20, 0)
end

-- Zahnrad-Menue: Kategorien, kompakt, festsetzen
function BM.Menu(owner)
    if lockedNow() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
    local items = {}
    for _, c in ipairs(CATS) do
        local on, raw = catOn(c.key)
        local txt = L[c.label]
        if c.key == "prot" then
            txt = txt .. "  |cff888888(" .. (raw == "auto" and L["automatisch: Onyxia"] or (raw and L["an"] or L["aus"])) .. ")|r"
        end
        items[#items + 1] = { text = txt, checked = on, fn = function()
            if c.key == "prot" then
                setCat("prot", (raw == "auto") and true or ((raw == true) and false or "auto"))
            else
                setCat(c.key, not on)
            end
            BM.Update()
            if ns.RefreshPage then ns.RefreshPage("buffs") end
        end }
    end
    items[#items + 1] = { text = L["Kompakt"], checked = S().buffCompact, fn = function() S().buffCompact = not S().buffCompact or nil BM.Update() end }
    items[#items + 1] = { text = L["Fenster festsetzen"], checked = S().buffLock, fn = function() S().buffLock = not S().buffLock BM.Update() end }
    items[#items + 1] = { text = L["Fehlende Buffs ansagen"], fn = function() BM.Post() end }
    K.ShowMenu(owner, items, L["Buff-Monitor"], 220)
end

-- Fehlende Buffs in den Gruppen-/Raidchat (kurz, nur ausserhalb des Kampfes)
function BM.Post()
    if ns.inCombat() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
    local list, cols, missing = BM.Scan()
    local parts = {}
    for _, b in ipairs(cols) do
        if not b.soft and (missing[b.key] or 0) > 0 then parts[#parts + 1] = b.label .. " (" .. missing[b.key] .. ")" end
        if #parts >= 6 then break end
    end
    if #parts == 0 then return end
    local msg = L["Es fehlen Buffs: "] .. table.concat(parts, ", ")
    if not ns.Group.IsInGroup() then ns.print(msg) return end   -- Demo/allein: nur lokal (Simulator: ns.SendChat schreibt nur lokal)
    local ch = ns.Group.IsInRaid() and "RAID" or "PARTY"
    ns.SendChat(msg, ch)
end

function BM.Toggle(force)
    if not f then build() f:Hide() end
    local show = force
    if show == nil then show = not f:IsShown() end
    if lockedNow() and show ~= f:IsShown() then
        pendingShow = show
        ns.print(L["Buff-Monitor: nach dem Kampf"])
        return
    end
    f:SetShown(show)
    S().buffShow = show
    BM.Update()
end

-- automatisch aktualisieren (gedrosselt, nur sichtbar)
local function soon()
    if pending then return end
    pending = true
    ns.After(0.5, function() pending = false BM.Update() end)
end
ns.On("UNIT_AURA", function(u) if f and f:IsShown() and u and (u == "player" or u:find("^party") or u:find("^raid")) then soon() end end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if ns.inCombat() then return end
    local s = S()
    if s.buffAuto and IsInGroup() and (not f or not f:IsShown()) then BM.Toggle(true) end
    if s.buffAutoHide and not IsInGroup() and f and f:IsShown() then f:Hide() return end
    if s.buffAutoHide and s.buffShow and IsInGroup() and f and not f:IsShown() then f:Show() end
    soon()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingShow ~= nil and f then
        local v = pendingShow
        pendingShow = nil
        f:SetShown(v)
        S().buffShow = v
    end
    soon()
end)
local function spellsChanged() castPrepared = false prepared = false if f and f:IsShown() then soon() end end
ns.On("SPELLS_CHANGED", spellsChanged)
ns.On("LEARNED_SPELL_IN_TAB", spellsChanged)
ns.On("ZONE_CHANGED_NEW_AREA", function() if f and f:IsShown() then soon() end end)
ns.Listen("LOGIN", function() if S().buffShow and (IsInGroup() or demoOn()) then BM.Toggle(true) end end)
ns.slash.buffs = function() BM.Toggle() end

------------------------------------------------------------------------
-- Bereichs-Einstellungen (Seite "raidcheck" hat noch keinen eigenen Block -> neuer Block, nichts ersetzt)
------------------------------------------------------------------------
local settingsAdded = false
local function addSettings()
    if settingsAdded or not ns.AddPageSettings then return end
    settingsAdded = true
    ns.AddPageSettings("raidcheck", function(det, y)
        local t = K.Text(det, 12, C.amber)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetText(L["Buff-Monitor: Kategorien"])
        y = y - 26
        det.t = det.t or {}
        for _, c in ipairs(CATS) do
            if c.key ~= "prot" then
                local tg = K.Toggle(det, L[c.label], function() return (catOn(c.key)) end, function(v) setCat(c.key, v and true or false) BM.Update() end)
                tg:SetPoint("TOPLEFT", 14, y)
                tg:SetWidth(600)
                det.t[#det.t + 1] = tg
                y = y - 30
            end
        end
        local lab = K.Text(det, 12, C.text)
        lab:SetPoint("TOPLEFT", 14, y - 4)
        lab:SetText(L["Schutztraenke (Feuer)"])
        local function protKey() local _, raw = catOn("prot") return raw == "auto" and "auto" or (raw and "on" or "off") end
        local seg = K.Segments(det, {
            { key = "auto", text = L["Automatisch (Onyxia)"] }, { key = "on", text = L["an"] }, { key = "off", text = L["aus"] },
        }, function(k) setCat("prot", k == "auto" and "auto" or (k == "on")) BM.Update() end)
        seg:SetPoint("TOPLEFT", 200, y)
        seg:Select(protKey())
        y = y - 32
        local tg = K.Toggle(det, L["Kompakte Darstellung"], function() return S().buffCompact and true or false end, function(v) S().buffCompact = v or nil BM.Update() end)
        tg:SetPoint("TOPLEFT", 14, y)
        tg:SetWidth(600)
        det.t[#det.t + 1] = tg
        y = y - 32
        return y - 10
    end)
end
addSettings()
ns.Listen("LOGIN", addSettings)

------------------------------------------------------------------------
-- /oa probe buffs: was liefern die APIs hier?
------------------------------------------------------------------------
ns.Probes = ns.Probes or {}
ns.Probes.buffs = function()
    ns.print("C_UnitAuras.GetAuraDataByIndex: " .. tostring(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex ~= nil)
        .. "  GetBuffDataByIndex: " .. tostring(C_UnitAuras and C_UnitAuras.GetBuffDataByIndex ~= nil)
        .. "  UnitBuff: " .. tostring(UnitBuff ~= nil)
        .. "  C_SpellBook.IsSpellKnown: " .. tostring(C_SpellBook and C_SpellBook.IsSpellKnown ~= nil)
        .. "  IsPlayerSpell: " .. tostring(IsPlayerSpell ~= nil) .. "  Kampf: " .. tostring(ns.inCombat()))
    castPrepared, prepared = false, false
    prepCast()
    local mine = {}
    for k, v in pairs(myCast) do mine[#mine + 1] = k .. "=" .. tostring(v) end
    ns.print("Ich kann buffen: " .. (#mine > 0 and table.concat(mine, ", ") or "-"))
    if ns.inCombat() then ns.print("Im Kampf: Auren gesperrt") return end
    for _, au in ipairs(readAuras("player")) do
        local hit = {}
        for _, b in ipairs(BUFFS) do if matches(b, au) then hit[#hit + 1] = b.key end end
        ns.print(("  %s  id=%s  rest=%s  -> %s"):format(tostring(au.name), tostring(au.id),
            au.exp and fmtLeft(au.exp - GetTime()) or "-", #hit > 0 and table.concat(hit, ",") or "-"))
    end
end
end)

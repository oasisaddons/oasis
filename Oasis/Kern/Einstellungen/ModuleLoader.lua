-- Oasis: abschaltbare Module (0.5.568 als Zusatz-Addons, seit 0.5.580 wieder alles in EINEM Oasis-Ordner)
-- Grosse Bereiche liegen in Modules\<Name>\. Jede Datei dort verpackt ihren Inhalt in ns.ModuleFile("<Schluessel>", function() ... end).
-- Beim Start (ADDON_LOADED) werden nur eingeschaltete Module ausgefuehrt; abgeschaltete Funktionen werden verworfen
-- und belegen nach dem naechsten /reload keinen Speicher. Einstellungen > Bereiche > Module.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local M = {}
ns.ModuleLoader = M
-- ns.ModuleFile steht seit 0.6.272 in Core.lua (Moduldateien duerfen ueberall in der toc stehen), gesammelt in ns.moduleFiles
-- 0.6.272: nach Kategorien geordnet (cat); die Einstellungsseite zeigt je Kategorie eine Ueberschrift
M.CATS = { "Spielinhalte", "Gilde und Gruppe", "Chat", "Komfort und Karte" }
M.LIST = {
    { cat = "Spielinhalte", addon = "Oasis_Dungeons", title = "Dungeons", icon = "dungeons", desc = "Dungeon-Datenbank, Bosse, Karten, Questorte und die Dungeon-Seite" },
    { cat = "Spielinhalte", addon = "Oasis_Raidwerkzeuge", title = "Raids und Termine", icon = "raid", desc = "Termine und Anmeldungen, Raid-Planer, Raid-Check, Buffs, Pluendermeister und Lootpunkte, Taktik-Karte, Raid-IDs, Kampfberichte" },
    { cat = "Spielinhalte", addon = "Oasis_Legacy", title = "Legacy", icon = "legacy", desc = "Legacy-Erfolge und Sammelstuecke" },
    { cat = "Spielinhalte", addon = "Oasis_Questitems", title = "Questitems", icon = "checklist", desc = "Questitems der Gilde suchen und anbieten" },
    { cat = "Spielinhalte", addon = "Oasis_Rares", title = "Seltene Gegner", icon = "star_on", desc = "Gildenweit geteilte Sichtungen von Rares und Weltbossen mit Wiederkehr-Schaetzung" },
    { cat = "Spielinhalte", addon = "Oasis_Ruf", title = "Ruf-Planer", icon = "badges", desc = "Eigener Ruf und der Stand der Gilde je Fraktion" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Gruppe", title = "Meine Gruppe", icon = "groups", desc = "Gruppenuebersicht, Quests teilen, Gruppen-XP, Segen-Plan, Bedrohung und Pull-Warnung, Wuerfelrunde, Gebiet im Chat" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Deathroll", title = "Todeswuerfeln", icon = "deathroll", desc = "Deathroll-Duelle mit Rangliste" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Umfragen", title = "Umfragen", icon = "polls", desc = "Abstimmungen in der Gilde" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Gemeinschaft", title = "Gemeinschaft", icon = "heart", desc = "Steckbriefe, Geburtstage, Paten fuer Neulinge, Danke und Helfer der Woche, Gilden-Erfolge" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Kampf", title = "Kampf-Rangliste", icon = "stats", desc = "Schaden und Heilung der Gilde nach jedem Kampf, echte Crits" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Upgrades", title = "Upgrade-Suche", icon = "wants", desc = "Handelbare Ausruestung der Gilde, die fuer dich besser waere" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Talente", title = "Talente", icon = "profile", desc = "Talente von Gildenmitgliedern und betrachteten Spielern ansehen" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Discord", title = "Discord", icon = "speaker", desc = "Discord-Bruecke und Sprachkanal der Gilde" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Handwerk", title = "Handwerk", icon = "crafting", desc = "Wer kann was herstellen, Handwerks-Auftraege an die Gilde, Materialien im Tooltip" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Gildenbank", title = "Gildenbank", icon = "bank", desc = "Inhalt und Verlauf der Gildenbank" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Handel", title = "Handel", icon = "bank", desc = "Kaufen und verkaufen in der Gilde, Marktwerte" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Chronik", title = "Chronik", icon = "chronicle", desc = "Was in der Gilde passiert ist: Level, Abzeichen, Erfolge" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Lager", title = "Lagerfeuer", icon = "camp", desc = "Lagerfeuer fuer die Gilde melden und auf der Karte zeigen" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Tode", title = "Tode", icon = "deaths", desc = "Tode in der Gilde, Sterbeorte auf der Karte" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Mitspieler", title = "Mitspieler", icon = "groups", desc = "Quest-Partner in der Gilde, kuerzliche Mitspieler von ausserhalb, Neulinge" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Sammlungen", title = "Sammlungen", icon = "star_on", desc = "Reittiere, Haustiere und Spielzeuge der Gilde" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Gildenziele", title = "Gildenziele", icon = "checklist", desc = "Gemeinsame Vorhaben mit Schritten und Fortschritt" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Begruessung", title = "Begruessung", icon = "smile", desc = "Abgestimmter Gruss im Gildenchat, wenn jemand online kommt" },
    { cat = "Gilde und Gruppe", addon = "Oasis_Gildenpflege", title = "Gildenpflege", icon = "admin", desc = "Nur Gildenleitung: Inaktive, Bewerber, Werbung, Anwesenheit, Protokoll mit Gildenverlauf, Bannliste, Verdachts-Monitor" },
    { cat = "Chat", addon = "Oasis_Fluestern", title = "Fluesterverlauf", icon = "social", desc = "Gespraeche im Fluesterchat, privater Reiter im Gildenchat, Weiterleitung an Twinks" },
    { cat = "Chat", addon = "Oasis_Spielchat", title = "Spielchat", icon = "social", desc = "Blizzards Chatfenster lesbarer: Namen, Stufen und Symbole, Filter, Suche, Verlauf und Stichwort-Alarme" },
    { cat = "Chat", addon = "Oasis_EmojiVorschlaege", title = "Emoji-Vorschlaege", icon = "smile", desc = "Beim Tippen passende Emojis vorschlagen" },
    { cat = "Komfort und Karte", addon = "Oasis_Komfort", title = "Komfort", icon = "home", desc = "Automatisch reparieren und verkaufen, Quests, Einladungen, Leisten, Tooltips" },
    { cat = "Komfort und Karte", addon = "Oasis_Kartenextras", title = "Karten-Extras", icon = "pin", desc = "Sammelorte der Gilde, Marker, Laufspuren, Gefahrenzonen, Zielpfeil" },
    { cat = "Komfort und Karte", addon = "Oasis_MeinWeg", title = "Mein Weg", icon = "chronicle", desc = "Zeitleiste und Rekorde deines Charakters" },
    { cat = "Komfort und Karte", addon = "Oasis_Questmarken", title = "Quest-Markierungen", icon = "checklist", desc = "Gruppenquests im Questlog markieren" },
    { cat = "Komfort und Karte", addon = "Oasis_Leistung", dev = true, title = "Leistungsmessung", icon = "stats", desc = "Live-Anzeige der Rechenzeit und Messwerte der Gilde" },
}
M.state = {}   -- [addon] = "loaded" | "off" | "missing" | "disabled" | Fehlertext

local function off() return (ns.db and ns.db.settings.modOff) or {} end
function M.IsOn(addon) return not off()[addon] end
function M.Loaded(addon) return M.state[addon] == "loaded" end
-- Ordner aus 0.5.564-0.5.579 (eigene Zusatz-Addons): werden nicht mehr gebraucht
M.OLD_FOLDERS = { "Oasis_Dungeons", "Oasis_Raidwerkzeuge", "Oasis_Deathroll", "Oasis_Brachland", "Oasis_Legacy", "Oasis_Questitems", "Oasis_Sprachen",
    "Oasis_Locale_FR", "Oasis_Locale_ES", "Oasis_Locale_IT", "Oasis_Locale_PT", "Oasis_Locale_RU", "Oasis_Locale_ZH", "Oasis_Locale_KO" }
-- beim Start (ADDON_LOADED, vor DB_READY/LOGIN): eingeschaltete Module ausfuehren, den Rest verwerfen
-- 0.6.566: Oasis wird in Teil-Addons zerlegt (Ordner Addons\<Teil>\, eigene toc mit LoadOnDemand).
-- Oasis laedt sie hier selbst, BEVOR die Module laufen - so haengen sie wie bisher an ns.ModuleFile und laufen vor DB_READY.
-- Ist ein Teil nicht installiert oder in der AddOn-Liste aus, fehlen seine Module (Zustand "missing").
M.PARTS = {
    { addon = "Oasis_Raid", title = "Oasis - Raid", modules = { "Oasis_Raidwerkzeuge", "Oasis_Kampf", "Oasis_Talente", "Oasis_Rares" } },
}
M.partOf = {}
for _, p in ipairs(M.PARTS) do for _, k in ipairs(p.modules) do M.partOf[k] = p end end
M.partState = {}   -- [Teil] = "loaded" | Grund von LoadAddOn ("MISSING", "DISABLED" ...)
local function loadParts()
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    for _, p in ipairs(M.PARTS) do
        if not load then M.partState[p.addon] = "MISSING" else
            local ok, loaded, reason = pcall(load, p.addon)
            M.partState[p.addon] = (ok and loaded) and "loaded" or tostring(reason or (not ok and loaded) or "MISSING")
        end
    end
end
function M.PartLoaded(addon) return M.partState[addon] == "loaded" end
function M.LoadAll()
    pcall(loadParts)
    local files = ns.moduleFiles or {}
    ns.moduleFiles = nil
    -- 0.6.285: in der Reihenfolge der toc ausfuehren (nicht der Anzeigeliste) - z. B. erweitert ein Modul ein anderes
    local byKey, ordered = {}, {}
    for _, m in ipairs(M.LIST) do byKey[m.addon] = m end
    for _, k in ipairs(ns.moduleOrder or {}) do if byKey[k] then ordered[#ordered + 1] = byKey[k] byKey[k] = nil end end
    for _, m in ipairs(M.LIST) do if byKey[m.addon] then ordered[#ordered + 1] = m end end
    ns.moduleOrder = nil
    for _, m in ipairs(ordered) do
        local fns = files[m.addon]
        if not M.IsOn(m.addon) then
            M.state[m.addon] = "off"
        elseif not fns then
            M.state[m.addon] = "missing"
        else
            M.state[m.addon] = "loaded"
            for _, fn in ipairs(fns) do
                local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "") end)
                if not ok then
                    M.state[m.addon] = tostring(err):match("^[^\n]*")
                    if ns.err then pcall(ns.err, "Modul " .. m.addon, err) end
                end
            end
        end
    end
    -- alte Zusatz-Ordner noch vorhanden? Dann Hinweis (Toast + Einstellungen > Module)
    -- 0.5.583: GetAddOnInfo liefert auch fuer FEHLENDE Addons einen Namen (Grund "MISSING") -> DoesAddOnExist bzw. Grund pruefen
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    M.stale = {}
    for _, n in ipairs(M.OLD_FOLDERS) do
        local found = false
        if exists then
            local ok, r = pcall(exists, n)
            found = ok and r == true
        elseif info then
            local ok, name, _, _, _, reason = pcall(info, n)
            found = ok and name ~= nil and reason ~= "MISSING"
        end
        if found then M.stale[#M.stale + 1] = n end
    end
end
-- Gildenmodul (Addon Oasis_Guild): vorhanden / eingeschaltet / ein- bzw. ausschalten ueber die AddOn-Verwaltung des Spiels
local GUILD = "Oasis_Guild"
function M.GuildInstalled()
    local ex = C_AddOns and C_AddOns.DoesAddOnExist
    if ex then local ok, r = pcall(ex, GUILD) return ok and r == true end
    return ns.GuildPack and true or false
end
function M.GuildEnabled()
    local f = C_AddOns and C_AddOns.GetAddOnEnableState
    if f then
        local ok, r = pcall(f, GUILD, ns.UnitName("player"))
        if not (ok and type(r) == "number") then ok, r = pcall(f, ns.UnitName("player"), GUILD) end
        if ok and type(r) == "number" then return r > 0 end
    end
    return ns.GuildPack and true or false
end
function M.SetGuildEnabled(on)
    local f = C_AddOns and (on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn) or (on and EnableAddOn or DisableAddOn)
    if f then
        local ok = pcall(f, GUILD, ns.UnitName("player"))
        if not ok then pcall(f, GUILD) end
    end
    M.dirty = true
end
function M.Set(addon, on)
    ns.db.settings.modOff = ns.db.settings.modOff or {}
    ns.db.settings.modOff[addon] = (not on) and true or nil
    M.dirty = true
end
-- Speicher des ganzen Addons (Module zaehlen seit 0.5.580 mit zu Oasis)
function M.MemKB(addon)
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not get then return nil end
    local ok, v = pcall(get, addon)
    return ok and v or nil
end
function M.UpdateMem()
    if ns.inCombat() then return end
    local up = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    if up then pcall(up) end
end
-- alle Oasis-Teile fuer die Leistungsmessung (seit 0.5.580 nur noch ein Addon)
function M.Addons() return { ADDON } end

-- Einstellungen > Bereiche > Module -------------------------------------------------------
local STATE_TXT = {
    loaded = { "geladen", "66db9e" }, off = { "aus", "888888" },
    missing = { "fehlt", "e8b44a" },
}
local function fmtMB(kb) if not kb then return "" end return ("%.1f MB"):format(kb / 1024) end
local function build(f)
    local H = ns.SettingsHelpers
    -- 0.6.480: schlichte Kategorie-Zeilen statt section() - die automatische Kasten-Umrandung legte sich sonst um die Karten
    local function cathead(text, yy)
        local t = K.Text(f, 11, C.dim)
        t:SetPoint("TOPLEFT", 2, yy)
        t:SetText(K.Upper(text))
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1)
        d:SetPoint("LEFT", t, "RIGHT", 10, 0)
        d:SetPoint("RIGHT", f, "LEFT", 738, 0)
        d:SetColorTexture(1, 1, 1, 0.08)
    end
    local intro = K.Text(f, 11, C.muted)
    intro:SetPoint("TOPLEFT", 2, -4)
    intro:SetWidth(730)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["Grosse Bereiche lassen sich abschalten. Was du abschaltest, wird nach dem naechsten /reload gar nicht mehr geladen und belegt keinen Speicher."])
    -- 0.5.713: je Modul eine Glas-Karte (Symbol + Name, Schalter rechts, Beschreibung, Zustand unten rechts)
    f.noCompact = true
    f.rows = {}
    local W, TH, GAP = 362, 96, 12
    local y = -40
    -- je Kategorie Ueberschrift + Karten in zwei Spalten

    for _, cat in ipairs(M.CATS) do
      local list = {}
      -- 0.6.523: Entwickler-Module (Leistungsmessung) nur im Entwicklermodus
      for _, m in ipairs(M.LIST) do if m.cat == cat and (not m.dev or (ns.IsDev and ns.IsDev())) then list[#list + 1] = m end end
      if #list > 0 then
        cathead(L[cat], y)
        y = y - 26
      end
      for i, m in ipairs(list) do
        local col = (i - 1) % 2
        if col == 0 and i > 1 then y = y - (TH + GAP) end

        local c = H.cardH(f, col * (W + 14), y, W, TH, m.icon, L[m.title], L[m.desc])
        if c.s then c.s:SetWordWrap(true) c.s:SetPoint("RIGHT", -70, 0) end
        local tg = K.Toggle(c, "", function() return M.IsOn(m.addon) end, function(v)
            M.Set(m.addon, v)
            if f.reload then f.reload:Show() f.hint:Show() end
        end)
        tg:SetWidth(46)
        tg:SetPoint("TOPRIGHT", -14, -12)
        local st = K.Text(c, 10, C.dim, "RIGHT")
        st:SetPoint("BOTTOMRIGHT", -14, 10)
        f.rows[#f.rows + 1] = { m = m, tg = tg, st = st }
      end
      if #list > 0 then y = y - (TH + GAP) - 8 end
    end
    -- 0.5.728: Gildenmodul = eigenes Addon "Oasis_Guild" (Meme-Sounds, Musik, Gilden-Emojis, Fehlerberichte); hier und
    -- in der AddOn-Liste des Spiels einzeln an-/abschaltbar. In der oeffentlichen Version ist der Ordner gar nicht dabei.
    local gm = H.cardH(f, 0, y, 2 * W + 14, 72, "home", L["Gildenmodul"],
        L["Meme-Sounds, Musik, Gilden-Emojis und Fehlerberichte - ein eigenes Addon nur fuer die Gilde."])
    gm.s:SetWordWrap(true)
    gm.s:SetPoint("RIGHT", -70, 0)
    f.gmState = K.Text(gm, 10, C.dim, "RIGHT")
    f.gmState:SetPoint("BOTTOMRIGHT", -14, 10)
    f.gmT = K.Toggle(gm, "", function() return M.GuildEnabled() end, function(v)
        M.SetGuildEnabled(v)
        if f.reload then f.reload:Show() f.hint:Show() end
        f.gmState:SetText("|cffe8b44a" .. L[v and "an nach /reload" or "aus nach /reload"] .. "|r")
    end)
    f.gmT:SetWidth(46)
    f.gmT:SetPoint("TOPRIGHT", -14, -12)
    f.gmT:SetShown(M.GuildInstalled())
    y = y - 72 - GAP - 8
    f.total = K.Text(f, 11, C.muted)
    f.total:SetPoint("TOPLEFT", 0, y)
    f.hint = K.Text(f, 11, C.amber or C.accent)
    f.hint:SetPoint("TOPLEFT", 0, y - 30)
    f.hint:SetText(L["Aenderungen gelten nach dem Neuladen."])
    f.hint:SetShown(M.dirty and true or false)
    f.reload = K.Button(f, L["Jetzt neu laden"], 150, 24, "primary", function() ReloadUI() end)
    f.reload:SetPoint("LEFT", f.hint, "RIGHT", 14, 0)
    f.reload:SetShown(M.dirty and true or false)
    f.stale = K.Text(f, 11, C.amber or C.accent)
    f.stale:SetPoint("TOPLEFT", 0, y - 64)
    f.stale:SetWidth(730)
    f.stale:SetJustifyH("LEFT")
    f.stale:SetWordWrap(true)
end
local function staleText()
    return (L["Alte Oasis-Zusatzordner liegen noch im AddOns-Ordner und werden nicht mehr gebraucht (alles steckt jetzt im Ordner Oasis). Du kannst sie loeschen: %s"]):format(table.concat(M.stale, ", "))
end
local function refresh(f)
    M.UpdateMem()
    if f.gmT then
        f.gmT:SetShown(M.GuildInstalled())
        f.gmT:Refresh()
        if not M.GuildInstalled() then f.gmState:SetText("|cff888888" .. L["nicht installiert (oeffentliche Version)"] .. "|r")
        elseif ns.GuildPack then f.gmState:SetText("|cff66db9e" .. L["geladen"] .. "|r")
        else f.gmState:SetText("|cff888888" .. L["aus"] .. "|r") end
    end
    local sum = M.MemKB(ADDON) or 0
    for _, r in ipairs(f.rows or {}) do
        r.tg:Refresh()
        local s = M.state[r.m.addon]
        local sd = STATE_TXT[s]
        local txt = sd and ("|cff" .. sd[2] .. L[sd[1]] .. "|r") or ("|cffff6060" .. tostring(s or "?") .. "|r")
        if not M.IsOn(r.m.addon) and s == "loaded" then txt = "|cffe8b44a" .. L["aus nach /reload"] .. "|r" end
        if M.IsOn(r.m.addon) and s == "off" then txt = "|cffe8b44a" .. L["an nach /reload"] .. "|r" end
        -- 0.6.566: Modul steckt in einem Teil-Addon, das fehlt oder aus ist
        local part = M.partOf[r.m.addon]
        if part and s == "missing" and not M.PartLoaded(part.addon) then
            txt = "|cffe8b44a" .. (L["%s fehlt"]):format(part.title) .. "|r"
        end
        r.st:SetText(txt)
    end
    f.total:SetText((L["Oasis belegt gerade %s."]):format(fmtMB(sum)))
    local has = M.stale and #M.stale > 0
    f.stale:SetText(has and staleText() or "")
    f.stale:SetShown(has and true or false)
end
-- einmal je Version nach dem Login Bescheid sagen
ns.Listen("LOGIN", function()
    if not (M.stale and #M.stale > 0) or not ns.db then return end
    if ns.db.staleDirHint == ns.version then return end
    ns.db.staleDirHint = ns.version
    C_Timer.After(12, function()
        K.Toast(L["Alte Oasis-Ordner"], staleText(), nil, function() ns.slash.module() end)
    end)
end)
if ns.AddSettingsTab then ns.AddSettingsTab("modules", "Module", build, refresh) end
ns.slash.module = function() if ns.Settings then ns.Settings.SetTab("modules") end end

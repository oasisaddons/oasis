-- Oasis: abschaltbare Module (0.5.568 als Zusatz-Addons, seit 0.5.580 wieder alles in EINEM Oasis-Ordner)
-- Grosse Bereiche liegen in Modules\<Name>\. Jede Datei dort verpackt ihren Inhalt in ns.ModuleFile("<Schluessel>", function() ... end).
-- Beim Start (ADDON_LOADED) werden nur eingeschaltete Module ausgefuehrt; abgeschaltete Funktionen werden verworfen
-- und belegen nach dem naechsten /reload keinen Speicher. Einstellungen > Bereiche > Module.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local M = {}
ns.ModuleLoader = M
M.files = {}   -- [Schluessel] = { fn, ... } bis zum Start
-- wird von den Moduldateien beim Laden aufgerufen (sie stehen in der toc HINTER dieser Datei)
function ns.ModuleFile(key, fn)
    if not M.files then return end
    local t = M.files[key] or {}
    M.files[key] = t
    t[#t + 1] = fn
end
M.LIST = {
    { addon = "Oasis_Dungeons", title = "Dungeons", icon = "dungeons", desc = "Dungeon-Datenbank, Bosse, Karten, Questorte und die Dungeon-Seite" },
    { addon = "Oasis_Raidwerkzeuge", title = "Raid-Werkzeuge", icon = "raid", desc = "Taktik-Karte, Raid-IDs, Raid-Vorbereitung, Kampfberichte, Pluender-Regeln, Reservierungen" },
    { addon = "Oasis_Deathroll", title = "Todeswuerfeln", icon = "deathroll", desc = "Deathroll-Duelle mit Rangliste" },
    { addon = "Oasis_Legacy", title = "Legacy", icon = "legacy", desc = "Legacy-Erfolge und Sammelstuecke" },
    { addon = "Oasis_Questitems", title = "Questitems", icon = "checklist", desc = "Questitems der Gilde suchen und anbieten" },
}
M.state = {}   -- [addon] = "loaded" | "off" | "missing" | "disabled" | Fehlertext

local function off() return (ns.db and ns.db.settings.modOff) or {} end
function M.IsOn(addon) return not off()[addon] end
function M.Loaded(addon) return M.state[addon] == "loaded" end
-- Ordner aus 0.5.564-0.5.579 (eigene Zusatz-Addons): werden nicht mehr gebraucht
M.OLD_FOLDERS = { "Oasis_Dungeons", "Oasis_Raidwerkzeuge", "Oasis_Deathroll", "Oasis_Brachland", "Oasis_Legacy", "Oasis_Questitems", "Oasis_Sprachen",
    "Oasis_Locale_FR", "Oasis_Locale_ES", "Oasis_Locale_IT", "Oasis_Locale_PT", "Oasis_Locale_RU", "Oasis_Locale_ZH", "Oasis_Locale_KO" }
-- beim Start (ADDON_LOADED, vor DB_READY/LOGIN): eingeschaltete Module ausfuehren, den Rest verwerfen
function M.LoadAll()
    local files = M.files or {}
    M.files = nil
    for _, m in ipairs(M.LIST) do
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
    H.section(f, L["Module"], 0, 0, 730)
    H.note(f, L["Grosse Bereiche lassen sich abschalten. Was du abschaltest, wird nach dem naechsten /reload gar nicht mehr geladen und belegt keinen Speicher."], 0, -30, 730)
    -- 0.5.713: je Modul eine Glas-Karte (Symbol + Name, Schalter rechts, Beschreibung, Zustand unten rechts)
    f.noCompact = true
    f.rows = {}
    local W, TH, GAP = 362, 96, 12
    local y = -70
    for i, m in ipairs(M.LIST) do
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
    y = y - (TH + GAP) - 8
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

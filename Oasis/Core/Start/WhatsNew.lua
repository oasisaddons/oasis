-- Oasis: "Was ist neu" - einmal je neuer Version ein kleines Fenster mit hoechstens 5 Punkten
-- Gezeigt wird alles aus NEWS, was neuer ist als die zuletzt gesehene Version (settings.newsSeen).
-- Ganz neue Nutzer bekommen es nicht (Rundgang). Abschaltbar: settings.newsOff.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local W = {}
ns.WhatsNew = W
local function S() return ns.db.settings end

-- neueste zuerst; Texte = Schluessel in LocaleData481 (deutsch ohne Umlaute)
local NEWS = {
    -- 0.6.144: Punkte mit Titel (t), Text (d) und Symbol (icon = Schluessel in ns.ICONS)
    { v = "0.6.117", items = {
        { t = "Einstellungen", d = "Die Suche findet auch verwandte Woerter und springt direkt zum passenden Schalter.", icon = "settings" },
        { t = "Mehr Uebersicht", d = "Unter jedem Schalter steht kurz, was er tut.", icon = "polls" },
        { t = "Karte", d = "Alle Karten-Schalter auf einer Seite, nach Themen sortiert.", icon = "map" },
        { t = "Sammelseiten", d = "Jede Sammelseite hat einen Knopf zum Zuruecksetzen.", icon = "bank" },
        { t = "Gildenchat", d = "Text mit der Maus markieren und mit Strg+C kopieren.", icon = "chat" },
    } },
    { v = "0.6.112", items = {
        "Einstellungen neu geordnet: Start, Aussehen, Hinweise & Klang, Tooltips & Karte, Bereiche, Spielhilfen, Profil, Erweitert",
        "Hinweise, Tooltip-Zeilen, Karte und Teilen stehen jetzt je an einer Stelle statt in den einzelnen Bereichen",
        "Chat: Text mit der Maus markieren, Strg+C kopiert, Rechtsklick zeigt mehr",
    } },
}

local function vnum(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    if not a then return 0 end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
-- Punkte, die seit "seen" dazugekommen sind (hoechstens 5, neueste zuerst)
function W.Items(seen)
    local out, from = {}, vnum(seen)
    for _, n in ipairs(NEWS) do
        if vnum(n.v) > from and vnum(n.v) <= vnum(ns.version) then
            for _, it in ipairs(n.items) do if #out < 5 then out[#out + 1] = it end end
        end
    end
    return out
end

local win
local BG = "Interface\\AddOns\\Oasis_Guild\\Media\\news_bg"
local WIDTH, ROW, HEAD, FOOT = 700, 58, 104, 66
-- Eintrag in Titel, Text und Symbol zerlegen (alte Eintraege: "Titel: Text")
local function parts(it)
    if type(it) == "table" then return L[it.t], L[it.d], it.icon end
    local text = L[it]
    local t, d = text:match("^([^:]+):%s*(.+)$")
    if t and #t <= 24 then return t, d:sub(1, 1):upper() .. d:sub(2), nil end
    return nil, text, nil
end
local function line(parent, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    if K.Gradient then K.Gradient(t, "HORIZONTAL", { 1, 1, 1, a }, { 1, 1, 1, a * 0.4 }) else t:SetColorTexture(1, 1, 1, a) end
    return t
end
local function build()
    local f = CreateFrame("Frame", "OasisWhatsNew", UIParent)
    f:SetSize(WIDTH, 300)
    f:SetPoint("TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    -- 0.6.144: Hintergrund als Bild mit eigenem Rahmen (Gildenmodul), sonst Glas-Flaeche
    if ns.GuildPack then
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetTexture(BG)
    else
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.04, 0.04, 0.05, 0.97 }, { 1, 1, 1, 0.09 }, 14)) then
            K.Fill(f, C.bg)
            K.Border(f, C.line)
        end
    end
    -- Kopf: Logo, Titel mit Versionsschild, Unterzeile
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetTexture(ns.MEDIA .. "logo64")
    f.logo:SetSize(48, 48)
    f.logo:SetPoint("TOPLEFT", 34, -30)
    f.title = K.Title(f, 24, C.text)
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 18, -2)
    f.ver = CreateFrame("Frame", nil, f)
    f.ver:SetHeight(22)
    f.ver:SetPoint("LEFT", f.title, "RIGHT", 14, 0)
    K.Fill(f.ver, { C.accent[1] * 0.25, C.accent[2] * 0.25, C.accent[3] * 0.25, 0.75 })
    K.Border(f.ver, { C.accent[1], C.accent[2], C.accent[3], 0.6 })
    f.ver.t = K.Text(f.ver, 12, { 1, 0.62, 0.55 })
    f.ver.t:SetPoint("CENTER")
    f.sub = K.Text(f, 13, C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.sub:SetText(L["Das ist neu in dieser Version."])
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -22, -22)
    f.rows = {}
    -- Fussleiste: Trennlinie, "Nicht mehr zeigen" links, Knoepfe rechts
    f.footLine = line(f, 0.10)
    f.footLine:SetPoint("BOTTOMLEFT", 24, FOOT)
    f.footLine:SetPoint("BOTTOMRIGHT", -24, FOOT)
    f.go = K.Button(f, L["Zu den Einstellungen"], 190, 30, "primary", function()
        f:Hide()
        if ns.OpenSettingsTab then ns.OpenSettingsTab("quick") end
    end)
    f.go:SetPoint("BOTTOMRIGHT", -30, 18)
    f.ok = K.Button(f, L["Schliessen"], 140, 30, "ghost", function() f:Hide() end)
    f.ok:SetPoint("RIGHT", f.go, "LEFT", -12, 0)
    f.never = K.Toggle(f, L["Nicht mehr zeigen"], function() return S().newsOff == true end,
        function(v) S().newsOff = v or nil end)
    f.never:SetWidth(200)
    f.never:SetPoint("BOTTOMLEFT", 30, 20)
    if ns.EscClose then ns.EscClose("OasisWhatsNew") end
    f:HookScript("OnHide", function() S().newsSeen = ns.version end)
    win = f
    return f
end
local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r:SetHeight(ROW)
    r.icon = K.Glyph(r, 30, ns.ICONS.home, C.accent)
    r.icon:SetPoint("LEFT", 14, 0)
    r.t = K.Title(r, 16, C.text)
    r.t:SetPoint("TOPLEFT", r, "TOPLEFT", 62, -9)
    r.t:SetPoint("RIGHT", -10, 0)
    r.t:SetJustifyH("LEFT")
    r.d = K.Text(r, 12, C.muted)
    r.d:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -4)
    r.d:SetPoint("RIGHT", -10, 0)
    r.d:SetJustifyH("LEFT")
    r.d:SetWordWrap(true)
    r.sep = line(r, 0.07)
    r.sep:SetPoint("TOPLEFT") r.sep:SetPoint("TOPRIGHT")
    f.rows[i] = r
    return r
end

function W.Show(items)
    items = items or W.Items(S().newsSeen)
    if #items == 0 then return false end
    local f = win or build()
    f.title:SetText(L["Neu in Oasis"])
    f.ver.t:SetText(ns.version)
    f.ver:SetWidth((f.ver.t:GetStringWidth() or 40) + 22)
    local y = -HEAD
    for i, it in ipairs(items) do
        local r = row(f, i)
        local t, d, icon = parts(it)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 24, y)
        r:SetPoint("TOPRIGHT", -24, y)
        r.icon:SetTexture((icon and ns.ICONS[icon]) or ns.ICONS.home)
        r.t:SetText(t or "")
        r.t:SetShown(t ~= nil)
        r.d:ClearAllPoints()
        if t then r.d:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -4)
        else r.d:SetPoint("LEFT", r, "LEFT", 62, 0) end
        r.d:SetPoint("RIGHT", -10, 0)
        r.d:SetText(d or "")
        local h = math.max(ROW, (t and 30 or 14) + (r.d:GetStringHeight() or 14))
        r:SetHeight(h)
        r:Show()
        y = y - h
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetHeight(-y + FOOT + 14)
    f:Show()
    return true
end
function W.IsShown() return win and win:IsShown() or false end   -- fuer Tests
ns.slash.neu = function() W.Show(W.Items("0.0.0")) end
ns.slash.news = ns.slash.neu

-- einmal je Version nach dem Einloggen; nach dem Start-Fenster (UpdateStart) und nie im Kampf
ns.Listen("LOGIN", function()
    local s = S()
    if s.newsSeen == nil then
        -- ganz neu: nichts zeigen, ab jetzt mitzaehlen. Bestehende Nutzer (startVersion gesetzt): ab ihrer Version
        s.newsSeen = (s.onboarded or s.interestsDone) and "0.5.994" or ns.version   -- 0.5.994 = letzte oeffentliche Version davor
    end
    if s.newsOff or s.newsSeen == ns.version then return end
    -- warten, bis das Start-Fenster (Interessen-Auswahl) zu ist und kein Kampf laeuft (hoechstens 5 Minuten)
    local tries = 0
    local function try()
        tries = tries + 1
        local busy = (_G.OasisInterests and _G.OasisInterests:IsShown()) or (_G.OasisUpdateStart and _G.OasisUpdateStart:IsShown()) or ns.inCombat()
        if busy then
            if tries < 60 then ns.After(5, try) end
            return
        end
        if not W.Show() then s.newsSeen = ns.version end
    end
    ns.After(10, try)
end)

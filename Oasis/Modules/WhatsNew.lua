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
    { v = "0.6.117", items = {
        "Einstellungen: Suche findet auch verwandte Woerter (Ton, privat, Groesse ...) und springt direkt zum Schalter",
        "Einstellungen: unter jedem Schalter steht kurz, was er tut",
        "Karte: alle Karten-Schalter auf einer Seite, nach Themen sortiert",
        "Jede Sammelseite hat einen Knopf zum Zuruecksetzen",
        "Gildenchat: Text mit der Maus markieren und mit Strg+C kopieren",
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
local function build()
    local f = CreateFrame("Frame", "OasisWhatsNew", UIParent)
    f:SetSize(460, 200)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetTexture(ns.MEDIA .. "logo64")
    f.logo:SetSize(26, 26)
    f.logo:SetPoint("TOPLEFT", 16, -14)
    f.title = K.Title(f, 15, C.text)
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.rows = {}
    f.go = K.Button(f, L["Zu den Einstellungen"], 170, 24, "primary", function()
        f:Hide()
        if ns.OpenSettingsTab then ns.OpenSettingsTab("quick") end
    end)
    f.ok = K.Button(f, L["OK"], 80, 24, "ghost", function() f:Hide() end)
    f.ok:SetPoint("LEFT", f.go, "RIGHT", 8, 0)
    f.never = K.Toggle(f, L["Nicht mehr zeigen"], function() return S().newsOff == true end,
        function(v) S().newsOff = v or nil end)
    f.never:SetWidth(170)
    if ns.EscClose then ns.EscClose("OasisWhatsNew") end
    f:HookScript("OnHide", function() S().newsSeen = ns.version end)
    win = f
    return f
end

function W.Show(items)
    items = items or W.Items(S().newsSeen)
    if #items == 0 then return false end
    local f = win or build()
    f.title:SetText((L["Neu in Oasis %s"]):format(ns.version))
    local y = -52
    for i, text in ipairs(items) do
        local r = f.rows[i]
        if not r then
            r = K.Text(f, 12, C.text)
            r:SetWidth(410)
            r:SetJustifyH("LEFT")
            r:SetWordWrap(true)
            f.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 24, y)
        r:SetText(K.hex and (K.hex(C.accent) .. "\226\128\162|r  " .. L[text]) or ("- " .. L[text]))
        r:Show()
        y = y - (r:GetStringHeight() or 16) - 8
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f.go:ClearAllPoints()
    f.go:SetPoint("TOPLEFT", 16, y - 10)
    f.never:ClearAllPoints()
    f.never:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, y - 12)
    f:SetHeight(-y + 52)
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

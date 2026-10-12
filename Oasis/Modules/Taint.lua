-- Oasis: Fehler-Rekorder fuer "Oasis wurde blockiert (nur fuer die Blizzard-Oberflaeche)"
-- WoW meldet dabei, WELCHE geschuetzte Funktion blockiert wurde (ADDON_ACTION_FORBIDDEN / _BLOCKED).
-- Oasis merkt sich das zusammen mit den letzten eigenen Aktionen (ns.Trace) und zeigt es mit /oa fehler.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Taint = {}
ns.Taint = Taint
local KEEP = 30

-- bekannte Ausloeser: Funktion -> Erklaerung (Sprach-Schluessel)
local WHY = {
    UNKNOWN = "Die geschuetzte Funktion wurde blockiert. Der genaue Ausloeser ist noch unbekannt.",
    SendChatMessage = "Chatnachrichten erfordern in diesem Client eine direkte Eingabe.",
    ["C_ChatInfo.SendChatMessage"] = "Chatnachrichten erfordern in diesem Client eine direkte Eingabe.",
    CastSpellByName = "Chat-Eingabe und Zauberbefehle koennen beteiligt sein.",
    CastSpellByID = "Chat-Eingabe und Zauberbefehle koennen beteiligt sein.",
    TargetUnit = "Chat-Eingabe und Zielwechsel koennen beteiligt sein.",
    FocusUnit = "Chat-Eingabe und Zielwechsel koennen beteiligt sein.",
    SetRaidSubgroup = "Raid-Gruppen lassen sich im Kampf nicht umsortieren.",
    SwapRaidSubgroup = "Raid-Gruppen lassen sich im Kampf nicht umsortieren.",
    SetCVar = "Eine Einstellung wurde waehrend einer geschuetzten Aktion geaendert.",
    UseContainerItem = "Eine Taschenaktion wurde blockiert.",
    ["C_Container.UseContainerItem"] = "Eine Taschenaktion wurde blockiert.",
}

function Taint.Why(fn)
    local why = WHY[tostring(fn or "")] or WHY[(tostring(fn or "")):gsub("%(%)$", "")]
    if not why then return (L["Blockierung von %s beobachtet; Ausloeser nicht bestaetigt."]):format(tostring(fn or "?")) end
    if tostring(fn or ""):gsub("%(%)$", "") == "UNKNOWN" then return L[why] end
    return L["Moeglicher Zusammenhang:"] .. " " .. L[why]
end

local function db()
    ns.db.taint = ns.db.taint or {}
    return ns.db.taint
end
-- vorab deklariert: Taint.Fill nutzt sie, definiert werden sie weiter unten
-- (vorher globale nil-Aufrufe -> /oa fehler stuerzte beim Oeffnen ab)
local gdb, fillGuild, otherAddons

-- Taint-Protokoll automatisch: nach der ersten Blockierung schaltet Oasis WoWs Taint-Log ein
-- (Logs\taint.log nennt die genaue Codezeile) und nach 3 Tagen ohne neue Blockierung wieder aus.
-- Nur ausserhalb des Kampfes; ein selbst eingeschaltetes Protokoll laesst Oasis in Ruhe.
local function cvarOn() return GetCVar and tostring(GetCVar("taintLog") or "0") ~= "0" end
local function setLog(v)
    if not SetCVar then return end
    if ns.inCombat() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self) self:UnregisterAllEvents() pcall(SetCVar, "taintLog", v) end)
    else
        pcall(SetCVar, "taintLog", v)
    end
end
function Taint.AutoLog()
    if not ns.db then return end
    ns.db.taintAutoLast = ns.now()
    if ns.db.settings.taintAuto == false or cvarOn() then return end
    ns.db.taintAutoAt = ns.now()
    setLog(1)
end
ns.Listen("LOGIN", function()
    local d = ns.db
    if d.taintAutoAt and ns.now() - (d.taintAutoLast or d.taintAutoAt) > 3 * 86400 then
        d.taintAutoAt, d.taintAutoLast = nil, nil
        if cvarOn() then setLog(0) end
    end
end)

local function record(event, addon, fn)
    addon, fn = ns.safe(addon), ns.safe(fn)
    if addon ~= ADDON then return end
    -- Oasis-Netz: Kanal-Beitritt vom Client gesperrt -> still aufgeben, nicht als Fehler melden
    if ns.Net and ns.Net.OnBlocked and ns.Net.OnBlocked(fn) then return end
    -- Beobachtete Funktion beibehalten; zeitliche Naehe ist nur ein Hinweis.
    local suspected
    do
        local last = ns.trail[#ns.trail]
        if fn == "UNKNOWN()" and last and GetTime() - last.t < 0.5 and tostring(last.w):find("^SendChatMessage") then suspected = "SendChatMessage()" end
    end
    local now = GetTime()
    local existing = db()[#db()]
    local page = ns.MainShown() and ns.CurrentPage() or nil
    local ev = event == "ADDON_ACTION_FORBIDDEN" and "F" or "B"
    if existing and existing.fn == tostring(fn or "?") and existing.ev == ev
        and existing.page == page and existing.combat == (ns.inCombat() or nil)
        and ns.now() - (existing.lastTs or existing.ts) <= 30 then
        existing.count = (existing.count or 1) + 1
        existing.lastTs = ns.now()
        Taint.AutoLog()
        if Taint.win and Taint.win:IsShown() then Taint.Fill() end
        return
    end
    local trail = {}
    for i = #ns.trail, math.max(1, #ns.trail - 7), -1 do
        local t = ns.trail[i]
        trail[#trail + 1] = ("%s (vor %.1fs%s)"):format(t.w, now - t.t, t.c and ", Kampf" or "")
    end
    -- 0.5.775: Lua-Aufrufkette im Moment der Blockierung (das Ereignis kommt synchron aus dem blockierten Aufruf) - nennt die Funktion
    -- in Oasis, die den geschuetzten Aufruf gemacht hat. Pfade gekuerzt, die ersten acht Zeilen.
    do
        local ok, st = pcall(function() return debugstack and debugstack(2, 14, 0) or "" end)
        if ok and type(st) == "string" and st ~= "" then
            local keep = {}
            for line in st:gmatch("[^" .. string.char(10) .. "]+") do
                line = line:gsub("Interface.AddOns.", ""):gsub('%[string "(.-)"%]', "%1")
                if #keep < 8 then keep[#keep + 1] = line:sub(1, 110) end
            end
            if #keep > 0 then trail[#trail + 1] = "Aufrufkette: " .. table.concat(keep, " < ") end
        end
    end
    -- automatisch dazu: welche Ereignisse Oasis kurz davor verarbeitet hat
    local evs = ns.LastEvents and ns.LastEvents(3) or ""
    if evs ~= "" then table.insert(trail, 1, "Ereignisse: " .. evs) end
    Taint.AutoLog()
    local l = db()
    l[#l + 1] = {
        ts = ns.now(), lastTs = ns.now(), count = 1, v = ns.version, ev = ev, fn = tostring(fn or "?"), suspected = suspected,
        combat = ns.inCombat() or nil, page = ns.MainShown() and ns.CurrentPage() or nil,
        trail = table.concat(trail, "\n"),
    }
    while #l > KEEP do table.remove(l, 1) end
    if Taint.Report then pcall(Taint.Report, l[#l]) end
    -- geteilte Fehlerberichte (Abgleich): kommt beim Entwickler auch an, wenn er gerade offline ist
    if ns.Bugs and ns.Bugs.RecordBlock then
        local e = l[#l]
        pcall(ns.Bugs.RecordBlock, { fn = e.fn, combat = e.combat, page = e.page,
            trail = (e.trail or ""):gsub("\n", " | "), addons = otherAddons and otherAddons() or "" })
    end
    ns.print("|cffff5060" .. L["Blockiert:"] .. "|r " .. tostring(fn) .. "  |cff888888- " .. L["/oa fehler zeigt, warum"] .. "|r")
    if Taint.win and Taint.win:IsShown() then Taint.Fill() end
end
ns.On("ADDON_ACTION_FORBIDDEN", function(addon, fn) record("ADDON_ACTION_FORBIDDEN", addon, fn) end)
ns.On("ADDON_ACTION_BLOCKED", function(addon, fn) record("ADDON_ACTION_BLOCKED", addon, fn) end)

------------------------------------------------------------------------
-- Anzeige
------------------------------------------------------------------------
function Taint.Fill()
    local f = Taint.win
    local smf = f.smf
    smf:Clear()
    if f.guildBtn then f.guildBtn:SetLabel(Taint.guildView and L["Eigene Meldungen"] or ((L["Aus der Gilde (%d)"]):format(#gdb()))) end
    if Taint.guildView then fillGuild(smf) smf:ScrollToTop() return end
    local l = db()
    if #l == 0 then
        smf:AddMessage("|cff888888" .. L["Noch nichts blockiert. Sobald WoW Oasis blockiert, steht hier welche Funktion und was Oasis kurz vorher gemacht hat."] .. "|r")
    end
    for i = #l, 1, -1 do
        local e = l[i]
        local head = ("|cffffd24a%s|r  |cffff5060%s|r%s%s"):format(ns.fmtDate(e.ts), e.fn,
            e.ev == "F" and "  |cff888888(Popup)|r" or "  |cff888888(still)|r",
            e.combat and ("  |cffff8a3d" .. L["im Kampf"] .. "|r") or "")
        smf:AddMessage(head)
        if (e.count or 1) > 1 then smf:AddMessage("   " .. (L["%d Wiederholungen, zuletzt %s"]):format(e.count, ns.fmtDate(e.lastTs or e.ts))) end
        local why = Taint.Why(e.fn)
        smf:AddMessage("   " .. (why or ("|cff888888" .. L["Unbekannter Ausloeser - Taint-Log einschalten (Knopf unten), nachstellen, /reload."] .. "|r")))
        if e.suspected then smf:AddMessage("   " .. L["Moeglicher Zusammenhang:"] .. " " .. e.suspected) end
        if e.page then smf:AddMessage("   |cff888888" .. L["Offene Seite:"] .. "|r " .. e.page) end
        if e.trail and e.trail ~= "" then
            smf:AddMessage("   |cff888888" .. L["Zuletzt in Oasis:"] .. "|r")
            for line in e.trail:gmatch("[^\n]+") do smf:AddMessage("     · " .. line) end
        end
        smf:AddMessage(" ")
    end
    smf:ScrollToTop()
    local on = GetCVar and tostring(GetCVar("taintLog") or "0") ~= "0"
    f.logBtn.label:SetText(on and L["Taint-Log: an"] or L["Taint-Log einschalten"])
end

------------------------------------------------------------------------
-- Meldungen in der Gilde teilen: jede Oasis-Version schickt Blockierungen (nur Technik: Funktion, Version,
-- Seite, letzte Oasis-Aktionen, sichtbare sichere Oasis-Knoepfe, andere Addons) an die Gilde.
-- Gespeichert/angezeigt wird das nur bei Entwicklern (/oa entwickler) - im Fenster unter "Aus der Gilde".
------------------------------------------------------------------------
local SECURE = { "OasisMarkerButton", "OasisMarkSecure", "OasisTrackButton", "OasisFishButton" }
local function secureShown()
    local t = {}
    for _, n in ipairs(SECURE) do
        local f = _G[n]
        if f and f.IsShown and f:IsShown() then t[#t + 1] = n:gsub("^Oasis", "") end
    end
    if ns.BuffMonitor and ns.BuffMonitor.frame and ns.BuffMonitor.frame.IsShown and ns.BuffMonitor.frame:IsShown() then t[#t + 1] = "BuffMonitor" end
    return table.concat(t, ",")
end
function otherAddons()
    local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local GetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local Loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local t = {}
    if not (GetNum and GetInfo and Loaded) then return "" end
    for i = 1, GetNum() do
        local name = GetInfo(i)
        if type(name) == "string" and name ~= ADDON and not name:find("^Blizzard_") and Loaded(name) then t[#t + 1] = name end
        if #t >= 25 then break end
    end
    return table.concat(t, ",")
end
local sent, sentAny = {}, 0
function Taint.Report(e)
    if not (e and ns.Comm and IsInGuild()) or ns.db.settings.shareErrors == false then return end
    local key = tostring(e.fn)
    if sent[key] and GetTime() - sent[key] < 600 then return end   -- je Funktion hoechstens alle 10 Min
    if sentAny >= 5 then return end                                 -- hoechstens 5 Meldungen je Sitzung
    sent[key] = GetTime()
    sentAny = sentAny + 1
    local zone = ns.safe(GetRealZoneText()) or ""
    local trail = (e.trail or ""):gsub("\n", " | "):sub(1, 400)
    -- erst nach dem Kampf schicken (Addon-Nachrichten gehen zwar, aber nicht stoeren)
    local function go()
        ns.Comm.Guild("TNT", ns.version or "?", key:sub(1, 60), e.ev or "B", e.combat and "1" or "0", tostring(e.page or ""):sub(1, 30),
            zone:sub(1, 40), trail, secureShown(), ns.db.settings.shareAddonList and otherAddons():sub(1, 400) or "", (GetLocale and GetLocale()) or "")
    end
    if ns.inCombat() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self) self:UnregisterAllEvents() pcall(go) end)
    else
        pcall(go)
    end
end
function gdb()
    ns.db.taintGuild = ns.db.taintGuild or {}
    return ns.db.taintGuild
end
if ns.Comm then
    ns.Comm.On("TNT", function(sender, _, v, fn, ev, combat, page, zone, trail, sec, addons, loc)
        if not (ns.IsDev and ns.IsDev()) then return end
        if ns.Comm.FromGuild and not ns.Comm.FromGuild(sender) then return end
        local clean = function(x, n) return ns.CleanText and ns.CleanText(tostring(x or ""), n) or tostring(x or ""):sub(1, n) end
        local l = gdb()
        l[#l + 1] = { ts = ns.now(), who = clean(sender, 64), v = clean(v, 16), fn = clean(fn, 60), ev = ev == "F" and "F" or "B",
            combat = combat == "1" or nil, page = clean(page, 30), zone = clean(zone, 40), trail = clean(trail, 400),
            sec = clean(sec, 120), addons = clean(addons, 400), loc = clean(loc, 8) }
        while #l > 60 do table.remove(l, 1) end
        if Taint.win and Taint.win:IsShown() then Taint.Fill() end
    end)
end
function fillGuild(smf)
    local l = gdb()
    if #l == 0 then smf:AddMessage("|cff888888" .. L["Noch keine Meldungen aus der Gilde."] .. "|r") return end
    for i = #l, 1, -1 do
        local e = l[i]
        smf:AddMessage(("|cffffd24a%s|r  %s  |cff888888v%s %s|r  |cffff5060%s|r%s"):format(ns.fmtDate(e.ts), ns.Radar and ns.Radar.Colored and ns.Radar.Colored(e.who) or e.who,
            e.v or "?", e.loc or "", e.fn or "?", e.combat and ("  |cffff8a3d" .. L["im Kampf"] .. "|r") or ""))
        if (e.page or "") ~= "" or (e.zone or "") ~= "" then smf:AddMessage("   |cff888888" .. L["Seite/Gebiet:"] .. "|r " .. (e.page or "-") .. "  ·  " .. (e.zone or "")) end
        if (e.sec or "") ~= "" then smf:AddMessage("   |cff888888" .. L["Sichere Knoepfe sichtbar:"] .. "|r " .. e.sec) end
        if (e.trail or "") ~= "" then smf:AddMessage("   |cff888888" .. L["Zuletzt in Oasis:"] .. "|r " .. e.trail) end
        if (e.addons or "") ~= "" then smf:AddMessage("   |cff888888" .. L["Andere Addons:"] .. "|r " .. e.addons) end
        smf:AddMessage(" ")
    end
end

local function build()
    local f = CreateFrame("Frame", "OasisTaintFrame", UIParent)
    f:SetSize(620, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    ns.EscClose("OasisTaintFrame")
    local t = K.Title(f, 16, C.text)
    t:SetPoint("TOPLEFT", 18, -16)
    t:SetText(L["Oasis wurde blockiert - warum?"])
    local sub = K.Text(f, 11, C.muted)
    sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", -40, 0)
    sub:SetWordWrap(true)
    sub:SetText(L["WoW sperrt einige Funktionen fuer Addons (Kampf, Boss, Chat-Eingabe). Hier steht, welche Funktion es war und was Oasis davor gemacht hat."])
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local box = K.Panel(f, C.panel)
    box:SetPoint("TOPLEFT", 16, -70)
    box:SetPoint("BOTTOMRIGHT", -16, 52)
    local smf = CreateFrame("ScrollingMessageFrame", nil, box)
    smf:SetPoint("TOPLEFT", 10, -8)
    smf:SetPoint("BOTTOMRIGHT", -10, 8)
    smf:SetFont(K.FONT, 12, "")
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(1000)
    smf:SetSpacing(2)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, d)
        for _ = 1, 3 do if d > 0 then self:ScrollUp() else self:ScrollDown() end end
    end)
    f.smf = smf

    -- Taint-Log: WoW schreibt dann Logs\taint.log (nach /reload bzw. Ausloggen) - die Datei zeigt die genaue Zeile
    f.logBtn = K.Button(f, L["Taint-Log einschalten"], 170, 26, "primary", function()
        if ns.inCombat() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
        local on = tostring(GetCVar("taintLog") or "0") ~= "0"
        pcall(SetCVar, "taintLog", on and 0 or 2)
        ns.print(on and L["Taint-Log aus."] or L["Taint-Log an: Fehler nachstellen, dann /reload. Die Datei liegt unter World of Warcraft\\_classic_beta_\\Logs\\taint.log"])
        Taint.Fill()
    end)
    f.logBtn:SetPoint("BOTTOMLEFT", 16, 14)
    local clear = K.Button(f, L["Liste leeren"], 110, 26, "ghost", function()
        ns.db.taint = {}
        Taint.Fill()
    end)
    clear:SetPoint("LEFT", f.logBtn, "RIGHT", 8, 0)
    -- nur Entwickler: Meldungen aller Oasis-Nutzer der Gilde
    f.guildBtn = K.Button(f, "", 170, 26, "ghost", function() Taint.guildView = not Taint.guildView Taint.Fill() end)
    f.guildBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    f.guildBtn:SetShown(ns.IsDev and ns.IsDev() or false)
    f:HookScript("OnShow", function(self) self.guildBtn:SetShown(ns.IsDev and ns.IsDev() or false) end)
    Taint.win = f
    return f
end

function Taint.Show()
    local f = Taint.win or build()
    f:Show()
    Taint.Fill()
end
ns.slash.fehler = Taint.Show
ns.slash.taint = Taint.Show

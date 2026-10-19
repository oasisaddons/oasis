-- Oasis: Gildenpaket (eigene Emojis & Sounds) - 0.6.531
--  * Gebaut wird das Paket auf oasisaddon.com/studio (im Browser, nichts wird hochgeladen) -> ZIP mit
--    Oasis_Emojis + Oasis_Sounds; List.lua setzt OasisGuildPack = { guild, v, made, emojis, sounds }.
--  * Oasis teilt die eigene Paketversion in der Gilde ("GPK") und merkt sich die neueste, die es gesehen hat.
--    Wer ein aelteres oder kein Paket hat, bekommt einmal je Version einen Hinweis.
--  * Einstellungen > Aussehen & Bedienung > Emojis & Sounds: Stand, Link zur Bau-Seite, Anleitung.
-- Bilder/Sounds kann ein Addon nicht ueber Addon-Nachrichten verschicken - jeder braucht die Dateien selbst.
local ADDON, ns = ...
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
local GP = {}
ns.GuildPack = GP
GP.URL = "oasisaddon.com/studio"

function GP.Mine()
    local p = rawget(_G, "OasisGuildPack")
    if type(p) ~= "table" then return nil end
    return { guild = type(p.guild) == "string" and p.guild:sub(1, 40) or "?", v = tonumber(p.v) or 0, made = type(p.made) == "string" and p.made or "",
        emojis = tonumber(p.emojis) or 0, sounds = tonumber(p.sounds) or 0 }
end
local function seen() ns.db.packSeen = ns.db.packSeen or {} return ns.db.packSeen end
function GP.Newest()
    local g = (GetGuildInfo and ns.safe(GetGuildInfo("player"))) or ""
    return seen()[g]
end
-- Paket von Hand oder alte Import-Skripte (ohne Versionsangabe), aber Ordner vorhanden?
function GP.LegacyInstalled()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not loaded then return false end
    return (loaded("Oasis_Emojis") or loaded("Oasis_Sounds")) and true or false
end

function GP.Announce()
    local m = GP.Mine()
    if m and IsInGuild() then Comm.Guild("GPK", m.v, m.made, m.emojis, m.sounds, ns.version or "") end
end
Comm.On("GPK", function(sender, _, v, made, ne, nsnd)
    if ns.isMe(sender) or not Comm.FromGuild(sender) then return end
    v = tonumber(v)
    if not v or v < 1 or v > 100000 then return end
    local g = (GetGuildInfo and ns.safe(GetGuildInfo("player"))) or ""
    local cur = seen()[g]
    if cur and cur.v >= v then return end
    seen()[g] = { v = math.floor(v), made = tostring(made or ""):sub(1, 10), by = sender, emojis = tonumber(ne) or 0, sounds = tonumber(nsnd) or 0, ts = ns.now() }
    local m = GP.Mine()
    if not m or m.v < v then
        ns.db.packHint = ns.db.packHint or {}
        if ns.db.packHint[g] ~= v then
            ns.db.packHint[g] = v
            K.Toast(L["Neues Gildenpaket"], (L["Version %d mit eigenen Emojis und Sounds ist in der Gilde unterwegs (von %s). Frag die Leitung nach der ZIP und entpacke sie in den AddOns-Ordner."]):format(v, ns.short(sender)),
                C.accent, function() if ns.Settings and ns.Settings.SetTab then ns.ShowPage("settings") pcall(ns.Settings.SetTab, "ownmedia") end end)
        end
    end
    ns.RefreshPage("settings")
end)
ns.Listen("LOGIN", function() C_Timer.After(30, function() pcall(GP.Announce) end) end)

------------------------------------------------------------------------
-- Einstellungs-Reiter
------------------------------------------------------------------------
local copy
local function showUrl()
    if not copy then
        StaticPopupDialogs["OASIS_PACK_URL"] = {
            text = "%s", button1 = OKAY or "OK", hasEditBox = true, editBoxWidth = 260,
            OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("https://" .. GP.URL) eb:HighlightText() eb:SetFocus() end end,
            EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
            EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        copy = true
    end
    StaticPopup_Show("OASIS_PACK_URL", L["Strg+C kopiert den Link - im Browser oeffnen:"])
end
GP.ShowUrl = showUrl
local function build(f)
    local H = ns.SettingsHelpers
    f.noCompact = true
    local c = H.cardH(f, 0, 0, 740, 150, "smile", L["Eigene Emojis & Sounds fuer deine Gilde"])
    f.how = K.Text(c, 12, C.text)
    f.how:SetPoint("TOPLEFT", 14, -48) f.how:SetPoint("RIGHT", -14, 0)
    f.how:SetJustifyH("LEFT") f.how:SetWordWrap(true) f.how:SetSpacing(4)
    f.how:SetText(L["1. Auf der Webseite Bilder und Sounds hineinziehen - alles passiert in deinem Browser.\n2. Gildenpaket herunterladen und in den AddOns-Ordner entpacken, WoW neu starten.\n3. Die ZIP in eurem Discord teilen - alle in der Gilde entpacken sie genauso."])
    f.go = K.Button(c, L["Link zur Bau-Seite"], 180, 26, "primary", showUrl)
    f.go:SetPoint("BOTTOMLEFT", 14, 14)
    f.url = K.Text(c, 12, C.muted) f.url:SetPoint("LEFT", f.go, "RIGHT", 12, 0) f.url:SetText(GP.URL)
    local s = H.cardH(f, 0, -164, 740, 170, "checklist", L["Dein Stand"])
    f.state = K.Text(s, 12, C.text)
    f.state:SetPoint("TOPLEFT", 14, -48) f.state:SetPoint("RIGHT", -14, 0)
    f.state:SetJustifyH("LEFT") f.state:SetWordWrap(true) f.state:SetSpacing(5)
    f.send = K.Button(s, L["Version an die Gilde melden"], 220, 24, "ghost", function() GP.Announce() K.Toast(L["Gildenpaket"], L["Deine Paketversion wurde an die Gilde gemeldet."], C.mint) end)
    f.send:SetPoint("BOTTOMLEFT", 14, 14)
end
local function refresh(f)
    local m, n = GP.Mine(), GP.Newest()
    local lines = {}
    if m then
        lines[#lines + 1] = (L["Installiert: Gildenpaket %s, Version %d (%s) - %d Emojis, %d Sounds"]):format(m.guild, m.v, m.made, m.emojis, m.sounds)
    elseif GP.LegacyInstalled() then
        lines[#lines + 1] = L["Installiert: eigene Emojis/Sounds ohne Versionsangabe (altes Import-Skript). Mit der Bau-Seite neu bauen, dann sieht die Gilde die Version."]
    else
        lines[#lines + 1] = "|cff888888" .. L["Kein Gildenpaket installiert."] .. "|r"
    end
    if n then
        local newer = not m or m.v < n.v
        lines[#lines + 1] = (newer and "|cffe8b44a" or "|cff66db9e") .. (L["Neueste Version in der Gilde: %d (von %s, %s)"]):format(n.v, ns.short(n.by or "?"), n.made or "") .. "|r"
        if newer then lines[#lines + 1] = L["Frag die Leitung nach der neuen ZIP, entpacke sie in den AddOns-Ordner und starte WoW neu."] end
    else
        lines[#lines + 1] = "|cff888888" .. L["Noch keine Paketversion aus der Gilde gesehen."] .. "|r"
    end
    lines[#lines + 1] = "|cff888888" .. L["Wer das Paket nicht hat, sieht Emojis als :code: und hoert bei eigenen Sounds den Standardton."] .. "|r"
    f.state:SetText(table.concat(lines, "\n"))
    f.send:SetShown(m ~= nil and IsInGuild())
end
if ns.AddSettingsTab then ns.AddSettingsTab("ownmedia", "Emojis & Sounds", build, refresh) end
ns.slash.paket = function() showUrl() end
ns.slash.studio = ns.slash.paket

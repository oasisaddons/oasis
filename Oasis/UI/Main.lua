-- Oasis - Hauptfenster, Navigation, Minimap-Knopf
local ADDON, ns = ...
local K, C, L = ns.K, ns.K.C, ns.L
local M = ns.MEDIA

local W, H, SIDEBAR = 1042, 700, 242
local pages, pageOrder = {}, {}
local main, current

-- Eigene Symbole (game-icons.net, CC BY 3.0 - siehe Media\\icons\\CREDITS.txt), weiss, im Spiel eingefaerbt
local ICONS = {}
for _, k in ipairs({ "radar", "crafting", "wants", "groups", "camp", "legacy", "raid", "chronicle", "map", "deathroll", "polls", "home", "bank", "deaths", "social", "dungeons", "badges", "settings" }) do ICONS[k] = M .. "icons\\" .. k end
ICONS.admin = M .. "icons\\admin"
ICONS.trade = M .. "icons\\stats"
ICONS.chat = M .. "icons\\badges\\chat"
ICONS.dev = M .. "icons\\bug"
ICONS.fight = M .. "icons\\raid"
ICONS.bugs = ICONS.bugs or (M .. "icons\\bug")
ICONS.rank = M .. "icons\\badges"
ICONS.insta = M .. "icons\\profile"
ICONS.allies = M .. "icons\\badges\\loyal"
ICONS.life = M .. "icons\\chronicle"
ns.ICONS = ICONS

-- Seite registrieren: { key, title, sub, order, build(page), refresh(page), visible() }
-- title/sub sind Sprach-Schluessel und werden erst bei der Anzeige uebersetzt
function ns.RegisterPage(def)
    pages[def.key] = def
    table.insert(pageOrder, def)
    table.sort(pageOrder, function(a, b) return a.order < b.order end)
end
function ns.Pages() return pageOrder end
function ns.CurrentPage() return current end
function ns.MainFrame() return main end
function ns.MainShown() return main ~= nil and main:IsShown() end
function ns.HideMain() if main then main:Hide() end end
function ns.PageDef(key) return pages[key] end
-- Ohne Gilde: diese Seiten brauchen eine Gilde und verschwinden aus der Navigation (Hinweis statt leerer Seite)
local GUILD_ONLY = { radar = true, chat = true, chronicle = true, polls = true, bank = true, raid = true, raidcheck = true,
    raidboard = true, raidprep = true, raidtime = true, softres = true, wipes = true, groups = true, crafting = true, trade = true,
    wants = true, camp = true, deaths = true, admin = true, officer = true, map = true, gearmatch = true, questitems = true,
    lockouts = true, repplan = true, rares = true }
function ns.InGuild() return not IsInGuild or IsInGuild() and true or false end
-- Mit Beispieldaten (/oa demo) sind die Gildenseiten auch ohne Gilde zu sehen: zum Ausprobieren, alles bleibt auf diesem PC
function ns.GuildView()
    if ns.InGuild() then return true end
    return ns.Demo ~= nil and ns.Demo.IsActive ~= nil and ns.Demo.IsActive() or false
end
function ns.GuildOnly(key) return GUILD_ONLY[key] == true and not ns.GuildView() end
-- sichtbar = eigene Bedingung + von der Gildenleitung eingeschaltet + nicht selbst ausgeblendet
function ns.PageVisible(key)
    local def = pages[key]
    if not def then return false end
    if def.visible and not def.visible() then return false end
    if key == "noguild" then return true end
    if key ~= "home" and ns.GuildOnly(key) then return false end
    if key == "settings" then return true end
    if key ~= "home" and ns.Admin and not ns.Admin.PageEnabled(key) then return false end
    local hidden = ns.db and ns.db.settings.hiddenPages
    if hidden and hidden[key] and key ~= "home" then return false end   -- 0.6.468: Dashboard immer sichtbar
    return true
end
-- 0.5.572: teure Seiten (letzter Aufbau > 25 ms) hoechstens alle 1,2 s neu aufbauen - weitere Aufrufe in dieser
-- Zeit werden gebuendelt nachgeholt (Abgleich/Profile/Chat riefen die Mitglieder-Seite sonst dutzendfach auf)
local refreshAt, refreshCost = {}, {}
local refreshBusy = {}
function ns.RefreshPage(key, force)
    if not main or not main:IsShown() then return end
    if key and current ~= key then return end
    local def = pages[current]
    if def and def.frame and def.refresh then
        local k = current
        -- Layout-/Store-Haken duerfen keinen verschachtelten Seitenaufbau starten.
        if refreshBusy[k] then
            ns.Debounce("pageRefresh:" .. k, 0.15, function() ns.RefreshPage(k) end)
            return
        end
        local now = GetTime()
        if not force and (k == "radar" or (refreshCost[k] or 0) > 25) and refreshAt[k] and now - refreshAt[k] < 1.2 then
            ns.Debounce("pageRefresh:" .. k, 1.2 - (now - refreshAt[k]) + 0.05, function() ns.RefreshPage(k, true) end)
            return
        end
        refreshAt[k] = now
        local t0 = debugprofilestop and debugprofilestop()
        refreshBusy[k] = true
        local ok, e = pcall(def.refresh, def.frame)
        refreshBusy[k] = nil
        if t0 then
            local dt = debugprofilestop() - t0
            refreshCost[k] = dt
            if ns.prof then ns.prof.add(def.refresh, "Seite " .. tostring(k), dt) end
        end
        if not ok then ns.err(L["Seite"] .. " " .. k, e) end
        -- 0.6.448: auf allen Seiten schwarze Box-Rahmen (neu entstandene Boxen nach jedem Aufbau)
        local fr = def.frame
        if k ~= "home" and ns.K and ns.K.DarkFramesIn and ns.Debounce then ns.Debounce("darkFrames", 0.1, function() pcall(ns.K.DarkFramesIn, fr) end) end
    end
end
-- Reiter stummgeschaltet (Lautsprecher in der Seitenleiste): seine Neuigkeiten gehen nicht an Minimap-Knopf und Topbar.
-- Gilt auch fuer die Unterseiten eines Hubs. Die Zahl in der Seitenleiste selbst bleibt sichtbar.
function ns.NavMuted(key)
    local m = ns.db and ns.db.settings and ns.db.settings.navMute
    if not (m and key) then return false end
    if m[key] then return true end
    local d = pages[key]
    return (d and d.parent and m[d.parent]) and true or false
end
function ns.NavSetMuted(key, on)
    local S = ns.db.settings
    S.navMute = S.navMute or {}
    S.navMute[key] = on and true or nil
    if not next(S.navMute) then S.navMute = nil end
    if ns.UpdateNotify then pcall(ns.UpdateNotify) end
    if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end
end
function ns.SetNavBadge(key, text)
    if text and ns.Admin and ns.Admin.NoBadge and ns.Admin.NoBadge(key) then text = nil end
    local def = pages[key]
    if def and def.nav then
        def.nav.badge:SetText(text or "")
        def.nav.badgeBg:SetShown((text or "") ~= "")
        if def.nav.FitBadge then def.nav:FitBadge() end
    end
    ns._badges = ns._badges or {}
    ns._badges[key] = text
    if ns.GlowNoteBadge then ns.GlowNoteBadge(key, text) end
    if ns.UpdateNotify then ns.UpdateNotify() end
end
-- Summe aller Neuigkeiten ("3", "@2", "!1", "99+") -> Zahl, erwaehnt?, Liste fuer den Tooltip
-- 0.5.569: ohne "all" zaehlt nur, was seit dem letzten Ansehen der Seite NEU dazukam (Blase am Minimap-Knopf/Topbar
-- verschwand vorher nie: offene Gruppen, Auftraege, Wunschliste sind Dauerzaehler). Ausgeblendete Seiten zaehlen nicht.
function ns.NotifyTotal(all)
    local total, mention, lines = 0, false, {}
    local ack = ns._glowAck or {}
    for key, v in pairs(ns._badges or {}) do
        local s = tostring(v or "")
        local n = tonumber(s:match("(%d+)")) or ((s ~= "") and 1 or 0)
        if n > 0 and (not pages[key] or (ns.PageVisible and not ns.PageVisible(key))) then n = 0 end
        if n > 0 and ns.NavMuted(key) then n = 0 end
        if n > 0 and not all then n = math.max(0, n - (ack[key] or 0)) end
        if n > 0 then
            total = total + n
            if s:find("@", 1, true) then mention = true end
            local def = pages[key]
            lines[#lines + 1] = { key = key, n = n, text = def and L[def.title] or key }
        end
    end
    table.sort(lines, function(a, b) return a.n > b.n end)
    return total, mention, lines
end

-- Leuchten bei Neuigkeiten (Seitenleiste + Topbar): pulsiert, bis die Seite angesehen wurde
local glowAck, glowMax, glowPingAt = {}, {}, {}
ns._glowAck = glowAck
-- "gesehen" ueber /reload hinaus merken
ns.Listen("DB_READY", function()
    for k, v in pairs(ns.db.badgeAck or {}) do if glowAck[k] == nil then glowAck[k] = v end end
    ns.db.badgeAck = glowAck
end)
local glowList, glowDrv = {}, nil
local glowQuietUntil = 0
local function badgeNum(raw)
    local s = tostring(raw or "")
    return tonumber(s:match("(%d+)")) or ((s ~= "") and 1 or 0)
end
ns.BadgeNum = badgeNum
local function glowEnabled() return not (ns.db and ns.db.settings and ns.db.settings.navGlow == false) end
local function noAnim() return ns.db and ns.db.settings and ns.db.settings.noAnim end
-- neuer Badge-Stand: steigt die Zahl ueber das bisher Gezeigte, kurz "pingen"
local function glowNote(key, n)
    if n <= 0 then glowAck[key], glowMax[key] = nil, nil return end
    -- Seite ist gerade offen: gilt sofort als gesehen
    if main and main:IsShown() and current == key then glowAck[key], glowMax[key] = n, n return end
    if n > (glowMax[key] or glowAck[key] or 0) then
        if GetTime and GetTime() > glowQuietUntil then glowPingAt[key] = GetTime() end
        glowMax[key] = n
    end
end
-- leuchtet die Seite (oder eine Unterseite ihres Hubs)? -> an, Zeitpunkt des letzten Pings
function ns.GlowState(key)
    if key == "home" or not glowEnabled() then return false end
    local on, ping = false, nil
    for k, v in pairs(ns._badges or {}) do
        local d = pages[k]
        if k == key or (d and d.parent == key) then
            if badgeNum(v) > (glowAck[k] or 0) and not ns.NavMuted(k) then
                on = true
                if glowPingAt[k] and (not ping or glowPingAt[k] > ping) then ping = glowPingAt[k] end
            end
        end
    end
    return on, ping
end
-- Tooltip-Zeile zur Neuigkeit (NewSince liefert "x neu seit deinem letzten Besuch")
function ns.BadgeTip(key)
    if ns.NewSince and ns.NewSince.TipFor then
        local t = ns.NewSince.TipFor(key)
        if t then return t end
    end
    local raw = ns._badges and ns._badges[key]
    if raw and tostring(raw) ~= "" then return (L["Neuigkeiten: %s"]):format(tostring(raw)) end
end
local function glowTick(b, t, el)
    local c = C.accent
    if b.glowIcon and not b.glowKeepColor then b.glowIcon:SetVertexColor(c[1], c[2], c[3]) end
    b.nglow:SetVertexColor(c[1], c[2], c[3])
    local base = noAnim() and 0.45 or (0.28 + 0.3 * (0.5 + 0.5 * math.sin(t * 3)))
    b.nglow:SetAlpha(base)
    if b.pingT then
        b.pingT = b.pingT + el
        local p = b.pingT / 0.9
        if p >= 1 or noAnim() then
            b.pingT = nil
            b.nring:Hide()
        else
            b.nring:SetVertexColor(c[1], c[2], c[3])
            local sz = b.glowSize * (0.8 + 1.2 * p)
            b.nring:SetSize(sz, sz)
            b.nring:SetAlpha(0.9 * (1 - p))
            b.nring:Show()
            b.nglow:SetAlpha(math.min(1, base + 0.6 * (1 - p)))
        end
    end
end
local function glowDriver()
    if glowDrv then return glowDrv end
    glowDrv = CreateFrame("Frame")
    local acc, t = 0, 0
    glowDrv:SetScript("OnUpdate", function(self, el)
        acc = acc + el
        t = t + el
        if acc < 0.033 then return end
        local step = acc
        acc = 0
        local any = false
        for b in pairs(glowList) do
            any = true
            if b:IsVisible() then glowTick(b, t, step) end
        end
        if not any then self:Hide() end
    end)
    return glowDrv
end
-- b = Knopf, icon = Symbol-Textur, size = Glow-Groesse
function ns.AttachGlow(b, icon, size)
    if b.nglow then return end
    b.glowIcon, b.glowSize = icon, size or 30
    b.nglow = b:CreateTexture(nil, "BORDER")
    b.nglow:SetTexture(ns.MEDIA .. "ember")
    b.nglow:SetBlendMode("ADD")
    b.nglow:SetSize(b.glowSize, b.glowSize)
    b.nglow:SetPoint("CENTER", icon, "CENTER")
    b.nglow:Hide()
    b.nring = b:CreateTexture(nil, "OVERLAY")
    b.nring:SetTexture(ns.MEDIA .. "ring")
    b.nring:SetBlendMode("ADD")
    b.nring:SetPoint("CENTER", icon, "CENTER")
    b.nring:Hide()
end
function ns.SetGlow(b, on, pingAt)
    if not b or not b.nglow then return end
    if on then
        if pingAt and pingAt ~= b.lastPing then
            b.lastPing = pingAt
            if not noAnim() and GetTime and GetTime() - pingAt < 5 then b.pingT = 0 end
        end
        b.nglow:Show()
        glowList[b] = true
        glowDriver():Show()
        glowTick(b, 0, 0)
    elseif glowList[b] then
        glowList[b] = nil
        b.nglow:Hide()
        b.nring:Hide()
        b.pingT = nil
        if b.glowOff then b.glowOff(b) end
    end
end
function ns.RefreshGlows()
    for _, d in ipairs(pageOrder) do
        if d.nav and d.nav.nglow then ns.SetGlow(d.nav, ns.GlowState(d.key)) end
    end
    if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end
end
-- Seite angesehen: Leuchten aus (bis wieder mehr Neues kommt)
function ns.GlowAck(key)
    local n = badgeNum(ns._badges and ns._badges[key])
    glowAck[key] = n > 0 and n or nil
    glowMax[key] = n > 0 and n or nil
    glowPingAt[key] = nil
    if ns.UpdateNotify then ns.UpdateNotify() end
end
-- aus SetNavBadge: Stand merken (Ping) und Nav-Eintrag (bzw. Hub) neu leuchten lassen
function ns.GlowNoteBadge(key, text)
    glowNote(key, badgeNum(text))
    local d = pages[key]
    local navKey = (d and d.parent) or key
    local nd = pages[navKey]
    if nd and nd.nav and nd.nav.nglow then ns.SetGlow(nd.nav, ns.GlowState(navKey)) end
end
ns.Listen("LOGIN", function() glowQuietUntil = (GetTime and GetTime() or 0) + 20 end)

-- Zusammengefasste Seiten: EIN Navigationspunkt, die weiteren Seiten als Reiter oben auf der Seite
-- 0.5.846: Raid in DREI Navigationspunkte statt fuenf:
--   Raids (Termine, Beute, Reservierungen, Regeln, IDs) | Raid-Vorbereitung (Taktik, Karte, Abend-Check, Buffs, Berichte) | Raidleitung
-- Die frueheren Eintraege "Beute" und "Buff-Monitor" sind jetzt Reiter; ns.ShowPage("loot"/"buffs") funktioniert unveraendert.
local HUBS = {
    raid = { "raid", "loot", "softres", "lootrules", "lockouts" },
    tactics = { "tactics", "raidboard", "raidprep", "buffs", "wipes" },
    raidlead = { "raidlead", "raidprepteam", "raidcheck", "raidtime" },
    -- Handel: Handwerk bleibt eigener Punkt; Markt, Wunschliste und Upgrade-Boerse teilen sich einen
    trade = { "trade", "wants", "gearmatch" },
    -- 0.6.443: Entwickler und Fehlerberichte in einem Navigationspunkt
    dev = { "dev", "bugs" },
    -- 0.6.450: Schwarzes Brett mit den Gildenzielen als zweitem Reiter
    board = { "board", "goals" },
}
-- Name des Navigationspunkts bzw. des ersten Reiters, wenn er vom Seitentitel abweichen soll
local HUB_NAV = { tactics = "Raid-Vorbereitung", trade = "Markt & Wuensche" }
local HUB_TAB = { dev = "Werkzeuge", board = "Schwarzes Brett", raid = "Termine", tactics = "Taktiken", raidprep = "Abend-Check", buffs = "Buffs", loot = "Beute", lockouts = "IDs", lootrules = "Regeln" }
function ns.HubNavTitle(key) return HUB_NAV[key] end
ns.PAGE_HUBS = HUBS
local HUB_OF = {}
for hub, list in pairs(HUBS) do for _, k in ipairs(list) do HUB_OF[k] = hub end end
local HUB_TABS_H = 38
function ns.HubOf(key) return HUB_OF[key] end
-- Unterseiten bekommen ihren Hub als "parent" (kein eigener Nav-Eintrag, Hub bleibt markiert)
local function applyHubs()
    for hub, list in pairs(HUBS) do
        if pages[hub] then
            for i = 2, #list do
                local d = pages[list[i]]
                if d and not d.parent then d.parent = hub d.hubChild = true end
            end
        end
    end
end
local function hubStrip(hub, key)
    main.hubStrips = main.hubStrips or {}
    for h, s in pairs(main.hubStrips) do s:SetShown(h == hub) end
    if not hub then return end
    local s = main.hubStrips[hub]
    local items = {}
    for _, k in ipairs(HUBS[hub]) do
        if pages[k] and ns.PageVisible(k) then items[#items + 1] = { key = k, text = L[HUB_TAB[k] or pages[k].title] } end
    end
    if #items < 2 then if s then s:Hide() end return end
    local sig = {}
    for _, it in ipairs(items) do sig[#sig + 1] = it.key end
    sig = table.concat(sig, ",")
    if not s or s.sig ~= sig then
        if s then s:Hide() end
        s = CreateFrame("Frame", nil, main.content)
        s:SetPoint("TOPLEFT", 0, 0)
        s:SetPoint("TOPRIGHT", 0, 0)
        s:SetHeight(HUB_TABS_H)
        s.seg = K.Segments(s, items, function(k) ns.ShowPage(k) end, nil, { size = 14, pad = 30 })
        s.seg:SetPoint("TOPLEFT", 0, -4)
        s.line = K.Divider(s)
        s.line:SetPoint("BOTTOMLEFT", 0, 4)
        s.line:SetPoint("BOTTOMRIGHT", 0, 4)
        s.sig = sig
        -- 0.6.464: Reiter gleichmaessig ueber die ganze Breite verteilen
        function s:Fit()
            local W = self:GetWidth() or 0
            local btns = self.seg.buttons or {}
            if W < 100 or #btns == 0 then return end
            local bw = math.floor(W / #btns)
            self.seg:SetWidth(W)
            for i, b in ipairs(btns) do
                b:SetWidth(bw)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.seg, "TOPLEFT", (i - 1) * bw, 0)
            end
        end
        s:SetScript("OnSizeChanged", function(self) self:Fit() end)
        main.hubStrips[hub] = s
    end
    s:Fit()
    s.seg:Select(key)
    s:Show()
end

local function showPage(key)
    -- ohne Gilde: Start/Dashboard -> eigener Startbildschirm, Gildenseiten -> Hinweis mit "Gilde finden"
    if pages.noguild and ns.GuildOnly(key) then
        pages.noguild.blocked = (key ~= "home") and key or nil
        key = "noguild"
    elseif key == "noguild" and ns.InGuild() then
        key = "home"
    end
    local def = pages[key]
    if not def then return end
    if key ~= "home" and not ns.PageVisible(key) then
        key, def = "home", pages.home
        if not def then return end
    end
    local prevKey = current
    current = key
    if main and main.UpdateContentArt then pcall(main.UpdateContentArt) end
    ns.Trace("Seite " .. key)
    -- aus einer zugeklappten Gruppe geoeffnet: Navigation neu setzen, damit der Eintrag sichtbar ist
    local closed = ns.db and ns.db.settings.navClosed
    if closed and next(closed) and ns.LayoutNav and prevKey ~= key then ns.LayoutNav() end
    for _, d in ipairs(pageOrder) do
        if d.frame then d.frame:Hide() end
        if d.nav then d.nav:SetActive(d.key == key or def.parent == d.key) end
        if main.gearColor then main.gearColor() end
    end
    if not def.frame then
        local p = CreateFrame("Frame", nil, main.content)
        if HUB_OF[key] then
            p:SetPoint("TOPLEFT", 0, -HUB_TABS_H)
            p:SetPoint("BOTTOMRIGHT")
        else
            p:SetAllPoints()
        end
        def.frame = p
        local ok, e = pcall(def.build, p)
        if not ok then ns.err(L["Aufbau"] .. " " .. key, e) end
    end
    local tt = def.headTitle or def.title   -- 0.6.327: eigener Kopf-Titel moeglich (Profil -> "Charakterprofil")
    main.title:SetText((K.Skin and K.Skin("upperTitle")) and K.Upper(L[tt]) or L[tt])
    main.sub:SetText(def.sub and L[def.sub] or "")
    main.icon:SetTexture(ICONS[key])
    def.frame:Show()
    local hub = HUB_OF[key]
    hubStrip(hub and pages[hub] and hub or nil, key)
    ns.RefreshPage(key, true)   -- Seitenwechsel: immer sofort
    -- Klick-Toene fuer alle Knoepfe der Seite (auch spaeter aufgebaute Zeilen beim naechsten Wechsel)
    if C_Timer and K.SoundifyTree then C_Timer.After(0.4, function() K.SoundifyTree(main) end) end   -- nach der Auf-Animation
    ns.db.settings.lastPage = key
    -- angesehen: "neu seit letztem Besuch" zuruecksetzen, Leuchten aus
    if ns.OnPageSeen then pcall(ns.OnPageSeen, key) end
    ns.GlowAck(key)
    ns.RefreshGlows()
end
ns.ShowPage = function(key)
    ns.OpenMain()
    if key == "rank" and pages.insta then
        ns.profileTab = "rank"
        key = "insta"
    end
    -- "Mein Weg" ist ins Profil gewandert
    if key == "life" and pages.insta then
        ns.profileTab = (ns.Life and ns.Life.view) or "journey"
        key = "insta"
    end
    showPage(key)
end

local function buildMain()
    main = CreateFrame("Frame", "OasisMainFrame", UIParent)
    _G.OasisMainFrame = main   -- nach Neuaufbau (Design/Kontrast) zeigt der Name sicher aufs neue Fenster
    main:SetSize(W, H)
    -- gemerkte Position (obere linke Ecke) - sonst Bildschirmmitte
    local pos = ns.db.settings.mainPos
    if pos and pos[1] and pos[2] then
        main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        main:SetPoint("CENTER")
    end
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    -- 0.5.565: Esc schliesst Oasis, solange es den Fokus hat (zuletzt hineingeklickt / gerade geoeffnet)
    -- 0.5.594: Esc schliesst Oasis IMMER zuerst (wie Blizzards Fenster), ausser man stellt "nur bei Fokus" ein
    ns.mainFocus = true
    if ns.EscClose then ns.EscClose(main, function() return not ns.db.settings.escFocusOnly or ns.mainFocus ~= false end,
        function() if ns.Collapse then ns.Collapse() else main:Hide() end end) end   -- Esc schliesst wie der X-Knopf (mit Animation)
    main:HookScript("OnShow", function() ns.mainFocus = true if ns.EscUpdate then ns.EscUpdate() end end)
    -- Klick-Toene: neu aufgebaute Knoepfe (Listenzeilen ...) regelmaessig nachruesten, solange Oasis offen ist
    if C_Timer and C_Timer.NewTicker and not ns.sndTicker then
        ns.sndTicker = C_Timer.NewTicker(2, function() if main and main:IsShown() and K.SoundifyTree then K.SoundifyTree(main) end end)
    end
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    -- Mac mit Notch: WoW legt die Oberflaeche unter die Kamera-Aussparung -> oben ueber den Rand
    -- hinaus schieben erlauben, damit das Fenster bis an die echte Bildschirmkante andocken kann
    if IsMacClient and IsMacClient() then
        main:SetClampRectInsets(0, 0, -50, 0)
    end
    main:EnableMouse(true)
    main:SetScale(ns.db.settings.scale or 1)
    ns.EscClose("OasisMainFrame")

    main.bgTex = K.Fill(main, C.bg)
    -- 0.5.600: Flaeche erst rechts der Seitenleiste (die hat ihre eigene Flaeche) -> braucht nur die rechten Ecken-Masken
    main.bgTex:ClearAllPoints()
    main.bgTex:SetPoint("TOPLEFT", main, "TOPLEFT", SIDEBAR, 0)
    main.bgTex:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
    K.Border(main, C.line)
    -- 0.6.128: Glut-Grafik im Inhaltsbereich rechts, wie links in der Akzentfarbe (Graustufen-Maske + ADD), dazu
    -- das feine Punktraster; Ecken rechts gerundet. Nur mit Gildenmodul.
    if ns.GuildPack then
        local art = main:CreateTexture(nil, "ARTWORK", nil, -8)
        art:SetPoint("TOPLEFT", main, "TOPLEFT", SIDEBAR, 0)
        art:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
        -- 0.6.146: Felsbild mit Glutrissen statt Glut-Verlauf - normal gezeichnet, auf das Seitenverhaeltnis
        -- des Inhaltsbereichs zugeschnitten (Bild 4:3)
        -- 0.6.154: zwei Ebenen (Tools/split_glow.py) - Fels in Grau, darueber nur die Glut in der gewaehlten Farbe
        art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\content_bg_base")
        local artGlow = main:CreateTexture(nil, "ARTWORK", nil, -8)
        artGlow:SetAllPoints(art)
        artGlow:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\content_bg_glow")
        artGlow:SetBlendMode("ADD")
        local function fitArt()
            local w, h = art:GetWidth() or 0, art:GetHeight() or 0
            if w <= 0 or h <= 0 then return end
            local r = (w / h) / (4 / 3)
            for _, t in ipairs({ art, artGlow }) do
                if r < 1 then pcall(t.SetTexCoord, t, (1 - r) / 2, 1 - (1 - r) / 2, 0, 1)
                else pcall(t.SetTexCoord, t, 0, 1, (1 - 1 / r) / 2, 1 - (1 - 1 / r) / 2) end
            end
        end
        if K.RoundMask then
            pcall(K.RoundMask, art, main, 12, { "tr", "br" })
            pcall(K.RoundMask, artGlow, main, 12, { "tr", "br" })
        end
        main.contentGlow = artGlow
        main.contentArt = art
        art.oasisBgNoAlpha = true   -- 0.6.230: Deckkraft macht tint() selbst (40 % Grundwert), Helligkeit ueber BgImg
        if K.BgImg then K.BgImg(art) end
        -- 0.6.147: Vignette ueber dem Bild - zu den Raendern dunkler, Inhalt in der Mitte bleibt ruhig
        local vig = main:CreateTexture(nil, "ARTWORK", nil, -7)
        vig:SetAllPoints(art)
        vig:SetTexture(ns.MEDIA .. "vignette")
        vig:SetVertexColor(1, 1, 1, 0.9)
        if K.RoundMask then pcall(K.RoundMask, vig, main, 12, { "tr", "br" }) end
        main.contentVig = vig
        local dots = main:CreateTexture(nil, "ARTWORK", nil, -6)
        dots:SetPoint("TOPLEFT", main, "TOPLEFT", SIDEBAR + 4, -4)
        dots:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 4)
        dots:SetTexture(ns.MEDIA .. "dotgrid", "REPEAT", "REPEAT")
        dots:SetVertexColor(1, 1, 1, 0.035)
        local function fitDots()
            local w, h = dots:GetWidth() or 0, dots:GetHeight() or 0
            if w > 0 and h > 0 then dots:SetTexCoord(0, w / 8, 0, h / 8) end   -- 0.6.143: so fein wie links (K.DotGrid)
        end
        main:HookScript("OnSizeChanged", function() fitDots() fitArt() end)
        fitDots()
        -- 0.6.131: das Dashboard hat sein eigenes Hintergrundbild - dort keine Glut und kein Raster
        function main.UpdateContentArt()
            local home = ns.CurrentPage and ns.CurrentPage() == "home"
            art:SetShown(not home)
            artGlow:SetShown(not home)
            vig:SetShown(false)   -- 0.6.231: Vignette aus
            dots:SetShown(not home)
        end
        local last, acc = nil, 0
        local function tint()
            local gh = ns.db and ns.db.settings.glowColor
            local ac = (gh and gh ~= "" and K.FromHex(gh)) or C.accent or { 1, 0.2, 0.2 }   -- 0.6.136: eigene Hintergrundfarbe
            local key = ac[1] .. ":" .. ac[2] .. ":" .. ac[3]
            local bv = K.BgBright and K.BgBright() or 1
            local lv = K.BgLight and K.BgLight() or 1
            key = key .. ":" .. bv .. ":" .. lv .. ":" .. tostring(C.accent and C.accent[1]) .. tostring(C.accent and C.accent[2]) .. tostring(C.accent and C.accent[3])
            if key == last then return end
            last = key
            -- 0.6.154: nur die Glut nimmt die Farbe an, der Fels bleibt grau (40 % wie bisher)
            -- 0.6.227: Helligkeit (bgBright): Fels kraeftiger, Vignette schwaecher
            art:SetVertexColor(1, 1, 1, 0.40 * bv)
            vig:Hide()   -- 0.6.231: Vignette rechts ganz weg (Wunsch)
            artGlow:SetVertexColor(ac[1], ac[2], ac[3], 1)   -- 0.6.158: Staerke ueber SetAlpha (Standard 0,8 = wie bisher)
        end
        tint()
        main:HookScript("OnUpdate", function(_, el)
            acc = acc + (el or 0)
            if acc < 0.5 then return end
            acc = 0
            tint()
            main.UpdateContentArt()
            if not main.dotsFit then main.dotsFit = true fitDots() fitArt() end
        end)
    end


    -- Seitenleiste
    local side = CreateFrame("Frame", nil, main)
    side:SetPoint("TOPLEFT", 1, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR)
    main.sideTex = K.Fill(side, C.side)
    -- 0.6.126: Glut-Grafik hinter der Leiste in der Akzentfarbe des Nutzers (nur mit Gildenmodul).
    -- Die Datei ist eine Graustufen-Maske (Glut hell, Grund schwarz); "ADD" + Akzentfarbe = Glut in jeder Farbe,
    -- der schwarze Teil veraendert die Leiste nicht. Farbwechsel in den Einstellungen wird sofort uebernommen.
    if ns.GuildPack then
        side.art = side:CreateTexture(nil, "ARTWORK", nil, -8)
        if K.BgImg then K.BgImg(side.art, "L") end   -- 0.6.227: Helligkeit einstellbar
        side.art:SetAllPoints()
        -- 0.6.148: Schieferbild mit feinen Glutadern statt Glut-Maske (normal gezeichnet, Seitenverhaeltnis passt fast genau)
        -- 0.6.154: zwei Ebenen wie rechts - Schiefer in Grau, darueber nur die Glutadern in der gewaehlten Farbe
        side.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\sidebar_bg_base")
        side.glow = side:CreateTexture(nil, "ARTWORK", nil, -8)
        side.glow:SetAllPoints(side.art)
        side.glow:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\sidebar_bg_glow")
        side.glow:SetBlendMode("ADD")
        -- 0.6.157: weicher Lichtschein in der gewaehlten Farbe, faellt von oben in die Leiste und verblasst nach unten
        side.wash = side:CreateTexture(nil, "ARTWORK", nil, -7)
        -- 0.6.237: Farbverlauf ueber die ganze Leiste - oben in der Farbe, nach unten auslaufend
        side.wash:SetAllPoints(side.art)
        -- 0.6.149: wie rechts eingepasst statt gestreckt (Bild 668:2000, mittig zugeschnitten)
        local function fitSide()
            local w, h = side.art:GetWidth() or 0, side.art:GetHeight() or 0
            if w <= 0 or h <= 0 then return end
            local r = (w / h) / (668 / 2000)
            for _, t in ipairs({ side.art, side.glow }) do
                if r < 1 then pcall(t.SetTexCoord, t, (1 - r) / 2, 1 - (1 - r) / 2, 0, 1)
                else pcall(t.SetTexCoord, t, 0, 1, (1 - 1 / r) / 2, 1 - (1 - 1 / r) / 2) end
            end
        end
        side:HookScript("OnSizeChanged", fitSide)
        fitSide()
        if K.RoundMask then
            pcall(K.RoundMask, side.art, main, 12, { "tl", "bl" })
            pcall(K.RoundMask, side.glow, main, 12, { "tl", "bl" })
            pcall(K.RoundMask, side.wash, main, 12, { "tl", "bl" })
        end
        local last
        local function tint()
            -- 0.6.159: links wie rechts - eigene Farbe (glowColorSide), ohne Wahl die Akzentfarbe
            local gh = ns.db and ns.db.settings.glowColorSide
            local ac = (gh and gh ~= "" and K.FromHex(gh)) or C.accent or { 1, 0.2, 0.2 }
            local key = ac[1] .. ":" .. ac[2] .. ":" .. ac[3] .. ":" .. tostring(ns.db and ns.db.settings.duoSide)
            if key == last then return end
            last = key
            -- 0.6.154: nur die Glutadern nehmen die Farbe an, der Schiefer bleibt grau
            -- 0.6.159: "Leiste links" (duoSide) faerbt den Schiefer selbst ein - das Bild deckt die Leistenflaeche ab
            local sh = ns.db and ns.db.settings.duoSide
            local sc = sh and sh ~= "" and K.FromHex(sh)
            if sc then
                local m = math.max(sc[1], sc[2], sc[3], 0.01)
                side.art:SetVertexColor(sc[1] / m, sc[2] / m, sc[3] / m, 1)
            else
                side.art:SetVertexColor(1, 1, 1, 1)
            end
            side.glow:SetVertexColor(ac[1], ac[2], ac[3], 1)
            -- 0.6.237: Farbverlauf in der Farbe "Hintergrund links" (sonst Akzentfarbe), unabhaengig von der Glut
            if not K.Gradient(side.wash, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.11 }) then   -- 0.6.255: halb so stark
                side.wash:SetColorTexture(ac[1], ac[2], ac[3], 0.04)
            end
            side.wash:Show()
        end
        tint()
        if K.DotGrid then side.dots = K.DotGrid(side, 0.045, 4) end
        -- 0.6.158: Glut-Staerke links/rechts (glowStrengthL/R, 0..2) und "Glut atmet" (glowBreath) - jedes Bild
        -- einmal, danach nur SetAlpha; beim Atmen pulsiert die Glut in 5 s langsam auf und ab
        local gt = 0
        main:HookScript("OnUpdate", function(_, el)
            local st = ns.db and ns.db.settings
            if not st then return end
            local b = 1
            if st.glowBreath then
                gt = (gt + (el or 0)) % 5
                b = 0.55 + 0.45 * (0.5 - 0.5 * math.cos(gt / 5 * math.pi * 2))
            end
            local sl, sr = tonumber(st.glowStrengthL) or 0, tonumber(st.glowStrengthR) or 1   -- 0.6.161: links Standard 0 (aus)
            if side.glow then side.glow:SetAlpha(math.min(1, sl * b)) end
            if main.contentGlow then main.contentGlow:SetAlpha(math.min(1, sr * b * 0.8)) end
        end)
        local acc = 0
        side:HookScript("OnUpdate", function(_, el)
            acc = acc + (el or 0)
            if acc < 0.5 then return end
            acc = 0
            tint()
        end)
    end
    if K.SkinWindow then pcall(K.SkinWindow, main) end     -- Design: echter Rahmen/Seitenleiste
    if K.StyleWindow then pcall(K.StyleWindow, main) end   -- Design: Verlauf + Rahmenfarbe
    -- 0.6.165: Zierrahmen mit Schimmer - gemeinsam mit dem Startfenster (K.FrameLines in Kit.lua)
    -- 0.6.168: erst NACH dem Design - Eckenradius vom Design uebernehmen (rund = 14, sonst lagen zwei Boegen
    -- nebeneinander), die graue Design-Kante zuruecknehmen; eckige/Metall-Designs ohne Boegen
    do
        local sk = main.skinDef
        main.frameLines = K.FrameLines(main, (sk and sk.r) or 12)
        main.frameShimmer = main.frameLines.shimmer
        if sk and sk.line ~= "round_line" then for _, t in ipairs(main.frameLines.corners) do t:Hide() end end
        if main.lineFrame then main.lineFrame:SetAlpha(0.35) end
        -- 0.6.186: mit Gildenmodul Bild-Rahmen aussen ums Fenster - Zierlinien und graue Kante dann aus
        if ns.GuildPack and K.ImageFrame then
            local ok, f = pcall(K.ImageFrame, main, 0.3)
            if ok and f then
                main.imageFrame = f
                K.ApplyFrameStyle(main)   -- 0.6.192: abschaltbar (Einstellungen > Details)
            end
        end
    end
    if ns.ApplyWindowAlpha then ns.ApplyWindowAlpha(main) end
    local sep = side:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetWidth(1)
    if K.Skin and K.Skin("noRules") then sep:Hide() end   -- Design mit eigenem Rahmen trennt Leiste und Inhalt selbst

    -- Logo: Oasis-Wortmarke oder Gildenname (stellt die Gildenleitung ein)
    -- Logo und Untertitel: gleich breit (156), linksbuendig mit der Navigation
    local BRAND_X = 18   -- linksbuendig mit den Symbolen der Navigation (0.5.919, vorher mittig in der Leiste)
    local logo = ns.GuildLogo(side, 156, 39, false)   -- ohne Strich darunter
    logo:SetPoint("TOPLEFT", BRAND_X, -12)
    logo:MakeClickable()
    -- Untertitel genauso breit wie der Strich unter dem Logo, mit etwas Abstand
    local gsub = K.Tracked(side, 9, C.muted)
    gsub:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -9)
    main.gsub = gsub
    function main.FitSub()
        local sub = ns.Admin and ns.Admin.BrandSub() or ""
        gsub:Set(K.Upper(sub), 156, K.FONT)
        gsub:SetShown(sub ~= "")
    end
    main.FitSub()
    local topSep = K.Divider(side)
    topSep:SetPoint("TOPLEFT", BRAND_X, -84)
    topSep:SetPoint("TOPRIGHT", -BRAND_X, -84)
    topSep:Hide()

    -- Navigation (Positionen setzt layoutNav, abgeschaltete Seiten fallen raus)
    applyHubs()
    for _, def in ipairs(pageOrder) do
      if not def.topbar and not def.parent then
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDEBAR - 16, 27)
        b.bg = K.Fill(b, C.raised)
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.bar:SetWidth(2)
        b.icon = K.Glyph(b, 18, ICONS[def.key])
        b.icon:SetPoint("LEFT", 10, 0)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 9, 0)
        b.label:SetText(L[(ns.HubNavTitle and ns.HubNavTitle(def.key)) or def.title])
        -- Zahl rechts: runde Pille in Akzentfarbe, Breite folgt der Zahl (1 Ziffer = Kreis)
        local DOTM = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
        b.badgeBg = CreateFrame("Frame", nil, b)
        b.badgeBg:SetSize(18, 16)
        b.badgeBg:SetPoint("RIGHT", -10, 0)
        local ac = C.accent
        b.badgeBg.l = b.badgeBg:CreateTexture(nil, "ARTWORK")
        b.badgeBg.l:SetTexture(DOTM) b.badgeBg.l:SetSize(16, 16) b.badgeBg.l:SetPoint("LEFT")
        b.badgeBg.r = b.badgeBg:CreateTexture(nil, "ARTWORK")
        b.badgeBg.r:SetTexture(DOTM) b.badgeBg.r:SetSize(16, 16) b.badgeBg.r:SetPoint("RIGHT")
        b.badgeBg.m = b.badgeBg:CreateTexture(nil, "ARTWORK")
        b.badgeBg.m:SetPoint("TOPLEFT", 8, 0) b.badgeBg.m:SetPoint("BOTTOMRIGHT", -8, 0)
        for _, t in ipairs({ b.badgeBg.l, b.badgeBg.r }) do t:SetVertexColor(ac[1], ac[2], ac[3], 1) end
        b.badgeBg.m:SetColorTexture(ac[1], ac[2], ac[3], 1)
        b.badge = b.badgeBg:CreateFontString(nil, "OVERLAY")
        K.SetFontSafe(b.badge, K.FONT_HEAD or K.FONT, 10, "", K.FONT)
        b.badge:SetTextColor(1, 1, 1)
        K.CenterNum(b.badge, b.badgeBg, "CENTER", 0, 0)
        function b:FitBadge()
            local w = tonumber(self.badge:GetStringWidth()) or 0
            self.badgeBg:SetWidth(math.max(16, math.ceil(w) + 10))
        end
        local bt = ns._badges and ns._badges[def.key] or ""
        b.badge:SetText(bt)
        b.badgeBg:SetShown(bt ~= "")
        b:FitBadge()
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.035)
        function b:SetActive(on)
            self.isActive = on
            local pill = K.Skin and K.Skin("navPill")   -- Design mit Pillen-Navigation: liefert die Farbe
            if pill then
                -- aktiver Eintrag als farbige Pille mit schwarzer Schrift
                if not self.lp then
                    local PM = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
                    local h = self:GetHeight()
                    self.lp = {}
                    for _, k in ipairs({ "l", "r", "m" }) do
                        local t = self:CreateTexture(nil, "BACKGROUND", nil, 2)
                        if k == "m" then t:SetColorTexture(1, 1, 1, 1) else t:SetTexture(PM) t:SetSize(h, h) end
                        self.lp[k] = t
                    end
                    self.lp.l:SetPoint("LEFT") self.lp.r:SetPoint("RIGHT")
                    self.lp.m:SetPoint("TOPLEFT", h / 2, 0) self.lp.m:SetPoint("BOTTOMRIGHT", -h / 2, 0)
                end
                local o = pill()
                self.lp.l:SetVertexColor(o[1], o[2], o[3], 1) self.lp.r:SetVertexColor(o[1], o[2], o[3], 1)
                self.lp.m:SetColorTexture(o[1], o[2], o[3], 1)
                for _, t in pairs(self.lp) do t:SetShown(on) end
                self.bg:Hide()
                self.bar:Hide()
                local c = on and { 0, 0, 0 } or C.muted
                self.label:SetTextColor(c[1], c[2], c[3])
                self.icon:SetVertexColor(c[1], c[2], c[3])
                return
            end
            -- 0.6.202: aktiver Eintrag mit Verlauf in der Akzentfarbe (links kraeftig, nach rechts aus), feiner Kante oben/
            -- unten, die ebenfalls auslaeuft, und hellem Strich links - wie eine glimmende Platte
            if not self.act then
                local a = {}
                a.fill = self:CreateTexture(nil, "BACKGROUND", nil, 2) a.fill:SetAllPoints()
                a.top = self:CreateTexture(nil, "ARTWORK", nil, 1) a.top:SetPoint("TOPLEFT") a.top:SetPoint("TOPRIGHT") a.top:SetHeight(1)
                a.bot = self:CreateTexture(nil, "ARTWORK", nil, 1) a.bot:SetPoint("BOTTOMLEFT") a.bot:SetPoint("BOTTOMRIGHT") a.bot:SetHeight(1)
                a.rgt = self:CreateTexture(nil, "ARTWORK", nil, 1) a.rgt:SetPoint("TOPRIGHT") a.rgt:SetPoint("BOTTOMRIGHT") a.rgt:SetWidth(1)
                a.glow = self:CreateTexture(nil, "BACKGROUND", nil, 3)
                a.glow:SetTexture(ns.MEDIA .. "softglow") a.glow:SetBlendMode("ADD")
                a.glow:SetPoint("CENTER", self.icon, "CENTER") a.glow:SetSize(46, 34)
                self.act = a
            end
            local ac = C.accent
            local a = self.act
            K.Gradient(a.fill, "HORIZONTAL", { ac[1] * 0.55, ac[2] * 0.55, ac[3] * 0.55, 0.75 }, { ac[1] * 0.15, ac[2] * 0.15, ac[3] * 0.15, 0.25 })
            K.Gradient(a.top, "HORIZONTAL", { ac[1], ac[2], ac[3], 0.9 }, { ac[1], ac[2], ac[3], 0.15 })
            K.Gradient(a.bot, "HORIZONTAL", { ac[1], ac[2], ac[3], 0.7 }, { ac[1], ac[2], ac[3], 0.1 })
            a.rgt:SetColorTexture(ac[1], ac[2], ac[3], 0.15)
            a.glow:SetVertexColor(ac[1], ac[2], ac[3])
            a.glow:SetAlpha(0.45)
            for _, t in pairs(a) do t:SetShown(on) end
            self.bg:SetShown(false)
            self.bar:SetShown(on)
            local c = on and C.text or C.muted
            self.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and C.accent or C.muted
            self.icon:SetVertexColor(ic[1], ic[2], ic[3])
        end
        b:SetActive(false)
        b.key = def.key
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mb)
            if self.dragEnd and GetTime() - self.dragEnd < 0.25 then return end   -- Loslassen nach dem Ziehen
            if mb == "RightButton" then ns.NavMenu(self, def) return end
            if ns.NoGuild and ns.NoGuild.AutoWho then pcall(ns.NoGuild.AutoWho) end
            showPage(def.key)
        end)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self) ns.NavDragStart(self) end)
        b:SetScript("OnDragStop", function(self) ns.NavDragStop(self) end)
        -- Neuigkeiten: Leuchten hinter dem Symbol + Tooltip
        if def.key ~= "home" then
            ns.AttachGlow(b, b.icon, 34)
            b.glowOff = function(self) self:SetActive(self.isActive) end
            b:SetScript("OnEnter", function(self)
                local tip = ns.BadgeTip(def.key)
                if not tip then
                    for _, sd in ipairs(pageOrder) do
                        if sd.parent == def.key then tip = ns.BadgeTip(sd.key) if tip then tip = L[sd.title] .. ": " .. tip break end end
                    end
                end
                if tip then K.ShowTip(self, { L[def.title], tip }) end
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        def.nav = b
        if b.nglow then ns.SetGlow(b, ns.GlowState(def.key)) end
        -- rechts: durchgestrichenes Auge (ganz schwach, beim Ueberfahren deutlicher) = Bereich ausblenden
        local e
        if not (ns.Discover and (ns.Discover.LOCKED or ns.Discover.CORE)[def.key]) then
            e = CreateFrame("Button", nil, b)
            e:SetSize(18, 18)
            e:SetPoint("RIGHT", -8, 0)
            e.icon = K.Glyph(e, 13, M .. "icons\\eye_off", C.muted)
            e.icon:SetPoint("CENTER")
            e:SetAlpha(0.12)
            b.eye = e
            b:HookScript("OnEnter", function(self) self.eye:SetAlpha(0.55) end)
            b:HookScript("OnLeave", function(self) if not self.eye:IsMouseOver() then self.eye:SetAlpha(0.12) end end)
            e:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
                K.ShowTip(self, { L["Ausblenden"], L["Unter Entdecken jederzeit wieder einschalten"] })
            end)
            e:SetScript("OnLeave", function(self)
                self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
                self:SetAlpha(b:IsMouseOver() and 0.55 or 0.12)
                GameTooltip:Hide()
            end)
            e:SetScript("OnClick", function()
                GameTooltip:Hide()
                if ns.Discover and ns.Discover.Set then ns.Discover.Set(def.key, false) end
                if current == def.key then showPage("home") end
            end)
        end
        do
            -- Stern links neben dem Auge: Favorit an/aus (Favorit = goldener Stern, immer sichtbar)
            local st = CreateFrame("Button", nil, b)
            st:SetSize(18, 18)
            st:SetPoint("RIGHT", e or b, e and "LEFT" or "RIGHT", e and -2 or -8, 0)
            st.icon = K.Glyph(st, 12, M .. "icons\\star_off", C.muted)
            st.icon:SetPoint("CENTER")
            b.star = st
            function b:UpdateStar()
                local fav = ns.NavIsFav and ns.NavIsFav(def.key)
                self.star.fav = fav
                self.star.icon:SetTexture(M .. (fav and "icons\\star_on" or "icons\\star_off"))
                local c = fav and { 1, 0.82, 0.3 } or C.muted
                self.star.icon:SetVertexColor(c[1], c[2], c[3])
                self.star:SetAlpha(fav and 0.95 or (self:IsMouseOver() and 0.55 or 0.12))
            end
            b:UpdateStar()
            b:HookScript("OnEnter", function(self) if not self.star.fav then self.star:SetAlpha(0.55) end end)
            b:HookScript("OnLeave", function(self) if not self.star:IsMouseOver() then self:UpdateStar() end end)
            st:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                if not self.fav then self.icon:SetVertexColor(1, 0.82, 0.3) end
                K.ShowTip(self, { self.fav and L["Aus Favoriten entfernen"] or L["Zu Favoriten"], L["Favoriten stehen ganz oben in der Navigation"] })
            end)
            st:SetScript("OnLeave", function() b:UpdateStar() GameTooltip:Hide() end)
            st:SetScript("OnClick", function()
                GameTooltip:Hide()
                if ns.NavSetFav then ns.NavSetFav(def.key, not (ns.NavIsFav and ns.NavIsFav(def.key))) end
                b:UpdateStar()
            end)
            -- Lautsprecher links vom Stern: Reiter stummschalten (nichts mehr an Minimap-Knopf / Topbar)
            local mu = st
            if def.key ~= "home" then
                mu = CreateFrame("Button", nil, b)
                mu:SetSize(18, 18)
                mu:SetPoint("RIGHT", st, "LEFT", -2, 0)
                mu.icon = K.Glyph(mu, 12, M .. "icons\\speaker", C.muted)
                mu.icon:SetPoint("CENTER")
                b.mute = mu
                function b:UpdateMute()
                    local on = ns.db and ns.db.settings.navMute and ns.db.settings.navMute[def.key] and true or false
                    self.mute.on = on
                    self.mute.icon:SetTexture(M .. (on and "icons\\speaker_off" or "icons\\speaker"))
                    local c = on and C.accent or C.muted
                    self.mute.icon:SetVertexColor(c[1], c[2], c[3])
                    self.mute:SetAlpha(on and 0.95 or (self:IsMouseOver() and 0.55 or 0.12))
                end
                b:UpdateMute()
                b:HookScript("OnEnter", function(self) if not self.mute.on then self.mute:SetAlpha(0.55) end end)
                b:HookScript("OnLeave", function(self) if not self.mute:IsMouseOver() then self:UpdateMute() end end)
                mu:SetScript("OnEnter", function(self)
                    self:SetAlpha(1)
                    if not self.on then self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3]) end
                    K.ShowTip(self, { self.on and L["Stummschaltung aufheben"] or L["Stummschalten"], L["Stumm: Neuigkeiten dieses Reiters erscheinen nicht am Minimap-Knopf und in der Topbar"] })
                end)
                mu:SetScript("OnLeave", function() b:UpdateMute() GameTooltip:Hide() end)
                mu:SetScript("OnClick", function()
                    GameTooltip:Hide()
                    ns.NavSetMuted(def.key, not b.mute.on)
                    b:UpdateMute()
                end)
            end
            -- langer Name endet vor den Knoepfen statt darunter zu laufen
            b.label:SetPoint("RIGHT", mu, "LEFT", -2, 0)
            b.label:SetWordWrap(false)
            b.label:SetJustifyH("LEFT")
            b.badgeBg:ClearAllPoints()
            b.badgeBg:SetPoint("RIGHT", mu, "LEFT", -4, 0)
        end
      end
    end
    main.side = side

    -- Fusszeile der Seitenleiste
    main.foot = K.Text(side, 11, C.muted, "LEFT")
    main.foot:SetPoint("BOTTOMLEFT", 22, 46)
    main.foot:SetWordWrap(true)
    main.foot:SetWidth(SIDEBAR - 32)
    -- 0.6.319: unten "OASIS  v0.6.x" und rechts ein Zahnrad zu den Einstellungen
    main.foot2 = K.Text(side, 11, C.muted, "LEFT")
    main.foot2:SetPoint("BOTTOMLEFT", 22, 16)
    main.foot2:SetText("OASIS   |cff8a8a90v" .. ns.version .. "|r")
    if main.foot2.SetSpacing then pcall(main.foot2.SetSpacing, main.foot2, 0) end
    local fg = CreateFrame("Button", nil, side)
    fg:SetSize(26, 26)
    fg:SetPoint("BOTTOMRIGHT", -14, 10)
    fg.icon = K.Glyph(fg, 18, ns.MEDIA .. "icons\\settings", C.muted)
    fg.icon:SetPoint("CENTER")
    fg:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { L["Einstellungen"] }) end)
    fg:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
    fg:SetScript("OnClick", function() if ns.ShowPage then ns.ShowPage("settings") end end)
    main.footGear = fg

    -- Kopfzeile (zum Verschieben)
    local head = CreateFrame("Frame", nil, main)
    head:SetPoint("TOPLEFT", SIDEBAR + 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(70)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not ns.db.settings.lockWindow then main:StartMoving() end end)
    main.dragHead = head   -- 0.6.190: Griffleisten am Bildrahmen nutzen dieselben Skripte (Sperre, Position speichern)
    head:SetScript("OnDragStop", function()
        main:StopMovingOrSizing()
        -- Position merken (auch ueber /reload und Neustart)
        local l, t = main:GetLeft(), main:GetTop()
        if l and t then ns.db.settings.mainPos = { math.floor(l + 0.5), math.floor(t + 0.5) } end
    end)
    main.icon = K.Glyph(head, 30, nil, C.accent)
    main.icon:SetPoint("LEFT", 24, 0)
    main.title = K.Title(head, 18, C.text)
    main.title:SetPoint("LEFT", main.icon, "RIGHT", 12, 0)
    main.sub = K.Text(head, 12, C.muted)
    -- 0.6.327: Titel und Untertitel in einer Zeile
    main.sub:SetPoint("LEFT", main.title, "RIGHT", 14, -1)
    main.sub:SetWordWrap(false)
    main.sub:SetPoint("RIGHT", head, "RIGHT", -96, 0)
    local hl = K.Divider(head)
    hl:SetPoint("BOTTOMLEFT", 24, 0)
    hl:SetPoint("BOTTOMRIGHT", -24, 0)
    if K.Skin and K.Skin("noRules") then hl:Hide() end   -- Design mit eigenem Rahmen: dessen Balken statt Linie

    -- Rechts oben, von rechts nach links:
    --   [Schliessen][Einklappen] | [Einstellungen][Gildenleitung][Sprache] | Status: [Demo][AH][Abgleich]
    -- X: je nach Einstellungen > Topbar einklappen (Leiste auf) oder einfach schliessen
    local close = K.CloseButton(head, function() if ns.Collapse then ns.Collapse() else main:Hide() end end, function()
        local m = ns.TopbarMode and ns.TopbarMode() or "collapse"
        if m == "off" then return L["Schliessen (/oasis oeffnet wieder)"] end
        if m == "always" then return L["Schliessen (die Topbar bleibt)"] end
        return L["Einklappen (an der Leiste: ganz schliessen)"]
    end, true)
    close:SetPoint("RIGHT", -12, 0)   -- 0.6.328: mittig - rechte Leiste auf einer Linie mit dem Titel
    local function hover(b, round)
        local t = b:CreateTexture(nil, "HIGHLIGHT")
        if round then
            t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            t:SetPoint("CENTER")
            t:SetSize(26, 26)
            t:SetVertexColor(1, 1, 1, 0.08)
        else
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1, 0.04)
        end
    end
    local function vsep(anchor, gap)
        local t = head:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.55)
        t:SetSize(1, 14)
        t:SetPoint("RIGHT", anchor, "LEFT", -(gap or 8), 0)
        return t
    end
    local function iconBtn(anchor, gap, w)
        local b = CreateFrame("Button", nil, head)
        b:SetSize(w or 28, 28)
        b:SetPoint("RIGHT", anchor, "LEFT", -(gap or 2), 0)
        hover(b, true)
        return b
    end

    -- Einklappen: Hauptfenster zu, schmale Oasis-Leiste auf
    local mini = CreateFrame("Button", nil, head)
    mini:SetSize(22, 22)
    mini:SetPoint("RIGHT", close, "LEFT", -4, 0)
    hover(mini)
    mini.line = mini:CreateTexture(nil, "ARTWORK")
    mini.line:SetSize(12, 1.5)
    mini.line:SetPoint("CENTER", 0, -3)
    mini.line:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
    mini:SetScript("OnEnter", function(self)
        self.line:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
        K.ShowTip(self, L["Einklappen (Oasis-Leiste)"])
    end)
    mini:SetScript("OnLeave", function(self)
        self.line:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
        GameTooltip:Hide()
    end)
    mini:SetScript("OnClick", function() ns.Collapse() end)
    -- das X klappt schon ein -> eigener Knopf ueberfluessig (bleibt nur als unsichtbarer Anker)
    mini:SetWidth(1)
    mini:Hide()
    local sep1 = vsep(mini, 8)
    main.langAnchor = sep1

    -- Bedienung: Einstellungen, Gildenleitung, Sprache
    local gear = iconBtn(sep1, 8)
    gear.icon = K.Glyph(gear, 16, ICONS.settings)
    gear.icon:SetPoint("CENTER")
    gear:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
        K.ShowTip(self, L["Einstellungen"])
    end)
    gear:SetScript("OnClick", function() showPage("settings") end)
    main.gear = gear

    local crown = iconBtn(gear, 2)
    crown.icon = K.Glyph(crown, 17, ICONS.admin)
    crown.icon:SetPoint("CENTER")
    crown:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
        if ns.PageVisible("admin") then
            K.ShowTip(self, { L["Gildenleitung"], L["Module, Rechte und Durchsagen fuer die ganze Gilde"] })
        else
            K.ShowTip(self, { L["Gildenleitung"], L["Nur fuer Gildenmeister und Offiziere."], "|cffe8b44a" .. L["Klick: zum Ausprobieren nur bei dir freischalten (Testmodus)"] .. "|r" })
        end
    end)
    crown:SetScript("OnClick", function()
        -- ohne Rechte: Testmodus einschalten (nur lokal), sonst direkt zur Gildenleitung
        if not ns.PageVisible("admin") then
            if ns.IsDev() and ns.slash.testleitung then ns.slash.testleitung() end
            return
        end
        showPage("admin")
    end)
    main.crown = crown
    local function gearColor()
        local c = (current == "settings") and C.accent or C.muted
        gear.icon:SetVertexColor(c[1], c[2], c[3])
        local a = (current == "admin") and C.accent or (ns.PageVisible("admin") and C.muted or C.dim)
        crown.icon:SetVertexColor(a[1], a[2], a[3])
    end
    gear:SetScript("OnLeave", function() gearColor() GameTooltip:Hide() end)
    crown:SetScript("OnLeave", function() gearColor() GameTooltip:Hide() end)
    main.gearColor = gearColor
    -- 0.6.327: Zahnrad und Krone unten in die Seitenleiste (nebeneinander), oben weg
    -- 0.6.422: Zahnrad wieder oben rechts im Kopf, nur die Krone bleibt unten in der Seitenleiste
    crown:SetParent(main.side) crown:SetFrameLevel(main.side:GetFrameLevel() + 5)
    crown:ClearAllPoints()
    crown:SetPoint("BOTTOMRIGHT", main.side, "BOTTOMRIGHT", -12, 9)
    if main.footGear then main.footGear:Hide() end

    -- Sprache: Flagge + Kuerzel, Klick = Auswahl
    local lang = iconBtn(gear, 2, 28)
    lang.flag = lang:CreateTexture(nil, "ARTWORK")
    lang.flag:SetSize(18, 13.5)
    lang.flag:SetPoint("CENTER", 0, 0)
    lang.flag:SetTexCoord(0, 1, 0, 0.75)
    lang.code = K.Text(lang, 11, C.muted)
    lang.code:SetPoint("LEFT", lang.flag, "RIGHT", 5, 0)
    lang.isDropdown = true
    function lang:Update()
        local l = ns.langByKey[ns.lang] or ns.LANGS[1]
        self.flag:SetTexture(M .. "flags\\" .. l.flag)
        self.code:SetText("")   -- nur die Flagge, Name steht im Tooltip
        self.langName = l.name
    end
    lang:SetScript("OnClick", function(self) ns.ShowLanguageMenu(self) end)
    lang:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Sprache"] .. (self.langName and (": " .. self.langName) or ""), L["Klick: Sprache von Oasis wechseln"] }) end)
    lang:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lang:Update()
    main.lang = lang
    -- Bug melden (fuer alle); Entwickler: Rechtsklick = eingegangene Berichte, Zahl = neue
    local bugBtn = iconBtn(lang, 2)
    if ns.Bugs and ns.Bugs.AttachHeader then ns.Bugs.AttachHeader(bugBtn) end
    main.bugBtn = bugBtn
    local sep2 = vsep(bugBtn, 8)
    -- 0.5.725: Fehlerberichte gibt es nur im Gildenmodul (Modules/Bugs.lua fehlt in der oeffentlichen Version) -> Knopf ausblenden
    if not (ns.Bugs and ns.Bugs.AttachHeader) then
        bugBtn:SetSize(1, 28)
        bugBtn:EnableMouse(false)
        bugBtn:SetAlpha(0)
        sep2:Hide()
    end

    -- Status-Kacheln: Punkt (Zustand) + Symbol + kurzer Text, alle gleich aufgebaut
    local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
    local function chip(iconPath, glyph)
        local c = CreateFrame("Button", nil, head)
        c:SetHeight(22)
        hover(c)
        c.dot = c:CreateTexture(nil, "OVERLAY")
        c.dot:SetSize(6, 6)
        c.dot:SetPoint("LEFT", 4, 0)
        c.dot:SetTexture(DOT)
        local left = c.dot
        if glyph then
            c.icon = K.Glyph(c, 13, iconPath)
        elseif iconPath then
            c.icon = c:CreateTexture(nil, "ARTWORK")
            c.icon:SetSize(12, 12)
            c.icon:SetTexture(iconPath)
        end
        if c.icon then
            c.icon:SetPoint("LEFT", c.dot, "RIGHT", 6, 0)
            left = c.icon
        end
        c.text = K.Text(c, 11, C.muted)
        c.text:SetPoint("LEFT", left, "RIGHT", 5, 0)
        c:HookScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
        c:HookScript("OnLeave", function(self) local t = self.tc or C.muted self.text:SetTextColor(t[1], t[2], t[3]) end)
        function c:Set(dot, text, tc)
            self.dot:SetVertexColor(dot[1], dot[2], dot[3], 1)
            self.text:SetText(text)
            -- Text gedaempft; nur Hervorhebungen (z. B. "Demo an", "gleicht ab") farbig
            local t = (tc and tc ~= C.text) and tc or C.muted
            self.tc = t
            self.text:SetTextColor(t[1], t[2], t[3])
            -- 0.6.329: Kacheln mit Symbol (AH, Abgleich) nur noch Punkt + Symbol, der Text steht im Tooltip
            self.text:SetShown(not self.icon)
            self:SetWidth(self.icon and 32 or math.ceil(16 + (self.text:GetStringWidth() or 40)))
        end
        return c
    end

    -- Abgleich mit der Gilde: Klick = jetzt abgleichen
    local sync = chip(M .. "icons\\sync", true)
    sync:SetPoint("RIGHT", sep2, "LEFT", -10, 0)
    main.sync = sync
    local function syncState()
        local last = ns.db.meta.lastSync or 0
        local age = last > 0 and (ns.now() - last) or nil
        local busy = ns.Comm.syncing and GetTime() - ns.Comm.syncing < 12
        local c = busy and C.accent or (age and age < 1800 and C.mint) or (age and age < 86400 and C.muted) or C.amber
        sync.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        local idle = (age and ns.ago(last)) or (ns.Comm.noAnswer and L["niemand online"]) or L["noch nie"]
        sync:Set(c, busy and L["gleicht ab ..."] or idle, busy and C.accent or C.text)
        return busy
    end
    local angle = 0
    sync:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        local busy = ns.Comm.syncing and GetTime() - ns.Comm.syncing < 12
        if busy then
            angle = (angle - el * 5) % (math.pi * 2)
            self.icon:SetRotation(angle)
        elseif angle ~= 0 then
            angle = 0
            self.icon:SetRotation(0)
        end
        if self.t > 1 then self.t = 0 syncState() end
    end)
    sync:SetScript("OnClick", function()
        ns.Comm.RequestSync(true)
        if ns.Radar then ns.Radar.SendHello() end
        syncState()
    end)
    sync:SetScript("OnEnter", function(self)
        -- 0.5.543: schlank - Technik-Diagnose nur noch mit gedrueckter Shift-Taste
        local last = ns.db.meta.lastSync or 0
        local lines = { L["Abgleich mit der Gilde"] }
        lines[#lines + 1] = (last > 0 and ("|cff66db9e" .. ns.ago(last) .. "|r") or L["noch nie"])
            .. (ns.db.meta.lastSyncFrom and ("  ·  " .. ns.Radar.Colored(ns.db.meta.lastSyncFrom)) or "")
        lines[#lines + 1] = (L["%d mit Oasis gerade online"]):format(math.max(0, (ns.Radar.withAddon or 1) - 1))
        lines[#lines + 1] = "|cff777777" .. L["Klick: jetzt komplett abgleichen"] .. "|r"
        if IsShiftKeyDown() then
            lines[#lines + 1] = " "
            for _, l in ipairs(ns.Comm.Diag()) do lines[#lines + 1] = "|cff888888" .. l .. "|r" end
        end
        K.ShowTip(self, lines)
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.Listen("SYNCED", syncState)
    syncState()

    -- AH-Stand (nur mit Midas oder wenn jemand in der Gilde gescannt hat), Klick = Markt
    local ah = chip("Interface\\MoneyFrame\\UI-GoldIcon")
    -- Demo-Daten (nur lokal, wird nie gesendet), Klick = an/aus
    local demo = chip()
    local function layoutChips()
        demo:ClearAllPoints()
        demo:SetPoint("RIGHT", ah:IsShown() and ah or sync, "LEFT", -12, 0)
    end
    ah:SetPoint("RIGHT", sync, "LEFT", -12, 0)
    function ah:Update()
        local ts = ns.Trade and ns.Trade.LatestScan()
        local show = ts ~= nil or (ns.Trade and ns.Trade.HasMidas and ns.Trade.HasMidas())
        self:SetShown(show and true or false)
        if show then
            local c = ns.Trade and ns.Trade.ScanColor(ts) or C.dim
            self.icon:SetDesaturated(not ts)
            self:Set(c, "AH " .. (ts and ns.ago(ts) or "-"))
        end
        layoutChips()
    end
    ah:SetScript("OnClick", function() showPage("trade") end)
    ah:SetScript("OnEnter", function(self)
        local ts, who = ns.Trade and ns.Trade.LatestScan()
        local lines = { L["Auktionshaus-Preise"] }
        if ts then
            lines[#lines + 1] = (L["Stand: %s, gescannt von %s"]):format(ns.ago(ts), ns.Radar.Colored(who))
        else
            lines[#lines + 1] = L["Noch kein Scan in der Gilde."]
        end
        lines[#lines + 1] = "|cff777777" .. L["Einer scannt im AH mit Midas, alle bekommen die Preise."] .. "|r"
        lines[#lines + 1] = "|cff777777" .. L["Klick: Markt oeffnen"] .. "|r"
        K.ShowTip(self, lines)
    end)
    ah:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ah:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t > 20 then self.t = 0 self:Update() end
    end)
    main.ah = ah
    ns.UpdateAHChip = function() ah:Update() end

    function demo:Update()
        -- oben nur, solange Beispieldaten laufen (damit man sieht, dass es Beispiele sind, und sie mit einem Klick loswird);
        -- Entwickler sehen den Schalter immer. Einschalten geht fuer alle ueber Einstellungen oder /oa demo.
        local on = ns.Demo and ns.Demo.IsActive()
        if not on and not ns.IsDev() then self:Hide() return end
        self:Show()
        if on then
            self:Set(C.amber, L["Demo an"], C.amber)
        else
            self:Set(C.dim, L["Demo"], C.muted)
        end
    end
    demo:SetScript("OnClick", function(self)
        if not ns.Demo then return end
        if ns.Demo.IsActive() then ns.Demo.Remove() else ns.Demo.Load() end
        self:Update()
        ns.RefreshPage("settings")
    end)
    demo:SetScript("OnEnter", function(self)
        local on = ns.Demo and ns.Demo.IsActive()
        K.ShowTip(self, { L["Demo-Daten"] .. ": " .. (on and L["an"] or L["aus"]),
            L["Fuellt Oasis mit Beispiel-Mitgliedern, Terminen, Chronik, Umfragen usw. Bleibt nur bei dir und wird nie an die Gilde gesendet."],
            "|cff777777" .. L["Klick: an / aus"] .. "|r" })
    end)
    demo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    main.demo = demo
    ns.UpdateDemoSwitch = function() demo:Update() end
    -- Gruppensuche laeuft: Chip mit drehendem Ring (Klick = Gruppen-Seite)
    local lfg = chip()
    lfg:SetPoint("RIGHT", demo, "LEFT", -12, 0)
    if ns.SpinRing then lfg.spin = ns.SpinRing(lfg, lfg.dot, 17, 2.2) lfg.spin:SetFrameLevel(lfg:GetFrameLevel() + 5) end
    function lfg:Update()
        local g = ns.Groups and ns.Groups.Mine and ns.Groups.Mine()
        if not g then self:Hide() return end
        self:Show()
        local n = 0
        for _, s in ipairs((ns.Groups.Slots and ns.Groups.Slots(g)) or {}) do if s.who then n = n + 1 end end
        self:Set(C.mint, L["Suche"] .. " " .. n .. "/5", C.mint)
    end
    lfg:SetScript("OnClick", function() showPage("groups") end)
    lfg:SetScript("OnEnter", function(self)
        local g = ns.Groups and ns.Groups.Mine and ns.Groups.Mine()
        K.ShowTip(self, { L["Gruppensuche laeuft"], g and g.title or "", "|cff777777" .. L["Klick: Gruppen oeffnen"] .. "|r" })
    end)
    lfg:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- eigener Takt (OnUpdate eines versteckten Chips laeuft nicht)
    local lfgTick = CreateFrame("Frame", nil, main)
    lfgTick:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t > 2 then self.t = 0 lfg:Update() end
    end)
    lfg:Update()
    main.lfgChip = lfg
    demo:Update()
    ah:Update()
    -- Seitenbeschreibung endet vor den Status-Kacheln
    main.sub:SetPoint("RIGHT", demo, "LEFT", -16, 0)

    -- Anheften: kleiner Reiter oben mittig am Fenster -> Oasis wird zur schmalen Leiste oben am Bildschirm
    -- Pin oben am Fenster entfernt (Einklappen ueber den Knopf oben rechts)

    -- Oasis-XP-Leiste unten am Fenster (immer sichtbar)
    -- Spielerkarte unter dem Fenster (Portraet, Level, Oasis-Rang) statt der duennen XP-Leiste
    -- unten nur die schlanke Gildenrang-XP-Leiste (die grosse Profilkarte mit "Profil anzeigen" ist weg)
    if ns.Rewards and ns.Rewards.AttachBar then main.xpbar = ns.Rewards.AttachBar(main, SIDEBAR) end

    -- Inhaltsbereich
    main.content = CreateFrame("Frame", nil, main)
    main.content:SetPoint("TOPLEFT", SIDEBAR + 25, -86)
    main.content:SetPoint("BOTTOMRIGHT", -24, 46)   -- unten Platz fuer die Rang-Leiste (Text + Balken, 6..28) + 18 px Luft
    -- Design mit eigenem Fensterrahmen (aus einem Zusatzmodul, K.WindowDecor): liegt unter dem Inhalt
    if K.WindowDecor then
        pcall(K.WindowDecor, main, SIDEBAR, -71, 25)
        if main.decor and main.decor:IsShown() then main.content:SetFrameLevel(main.decor:GetFrameLevel() + 1) end
    end

    -- 0.5.599: HookScript statt SetScript - SetScript loeschte die vorher angehaengten Haken (Esc-Stapel, Fokus,
    -- Akzentrahmen) -> Esc schloss Oasis nur beim ersten Mal
    -- 0.5.603: beim ersten Oeffnen nach dem Start die Schriften nachziehen (eigene Schriften sind dann oft noch nicht geladen)
    local fontFixes = 0
    main:HookScript("OnShow", function()
        if fontFixes < 2 and K.RefreshFonts then
            fontFixes = fontFixes + 1
            C_Timer.After(0.3, function() pcall(K.RefreshFonts) end)
            C_Timer.After(2, function() pcall(K.RefreshFonts) end)
        end
    end)
    main:HookScript("OnShow", function()
        ns.db.settings.mainOpen = true
        -- kein zweiter Ton, wenn der Klick (Kreuz/Knopf) gerade schon einen gespielt hat (auch waehrend der Animation)
        if ns.Sound and not (K._uiLast and GetTime() - K._uiLast < 0.8) then ns.Sound.Play("open") end
        ns.Fire("MAIN_SHOWN")
        ns.RefreshPage()
    end)
    main:HookScript("OnHide", function()
        -- beim Ladebildschirm schliesst WoW alle Fenster: das zaehlt nicht als "zugemacht"
        if not ns.rebuilding and not ns.loadingScreen then ns.db.settings.mainOpen = false end
        if ns.Sound and not (K._uiLast and GetTime() - K._uiLast < 0.8) then ns.Sound.Play("close") end
        ns.Fire("MAIN_HIDDEN")
    end)
    main:Hide()
    -- Blizzard-Fenster (Karte, Freunde "O", Charakter, Zauberbuch, Gilde ...) liegen ueber Oasis:
    -- oeffnet sich eines, rutscht Oasis nach hinten; Klick in Oasis / neu oeffnen holt es wieder nach vorn
    local function back() if main then main:SetFrameStrata("LOW") if K.FixEdge then K.FixEdge(main) end end end
    local function front() if main then main:SetFrameStrata("HIGH") main:Raise() if K.FixEdge then K.FixEdge(main) end end end
    ns.OasisFront, ns.OasisBack = front, back
    if not ns._panelHooked then
        ns._panelHooked = true
        if ShowUIPanel then hooksecurefunc("ShowUIPanel", function(f) if f ~= main then back() end end) end
        if WorldMapFrame then WorldMapFrame:HookScript("OnShow", back) end
    end
    main:SetScript("OnMouseDown", front)
    head:HookScript("OnMouseDown", front)
    -- Klick irgendwo IN Oasis (auch auf Knoepfe/Listen) holt es nach vorn, Klick in die Weltkarte schickt es
    -- nach hinten -> das zuletzt angeklickte Fenster liegt oben (wie bei normalen Fenstern)
    if not main.zTick then
        main.zTick = CreateFrame("Frame", nil, main)
        local wasDown = false
        main.zTick:SetScript("OnUpdate", function()
            local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            if down and not wasDown then
                if main:IsMouseOver() and main:GetFrameStrata() ~= "HIGH" then
                    local overMap = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:IsMouseOver()
                    -- liegt die Karte darueber und die Maus auf beiden: nur wenn Oasis wirklich sichtbar ist
                    if not overMap then front() end
                elseif WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:IsMouseOver() and not main:IsMouseOver() then
                    back()
                end
            end
            wasDown = down
        end)
    end
    if WorldMapFrame and WorldMapFrame:IsShown() then back() end
    ns.LayoutNav()
end

-- Gruppen der Navigation (einklappbar, Zustand wird gemerkt)
local NAV_GROUPS = {
    { key = "top", text = "", pages = { "home" }, nohead = true },   -- Dashboard: ganz oben, ohne Gruppen-Ueberschrift
    { key = "me", text = "Ich", pages = { "life", "insta", "bags", "badges", "legacy", "rank" } },
    { key = "guild", text = "Gilde", pages = { "chat", "radar", "fight", "chronicle", "polls", "community", "board", "goals", "bank", "deaths" } },
    { key = "play", text = "Zusammen spielen", pages = { "groups", "social", "questitems", "allies", "scout", "dungeons", "camp" } },
    { key = "raid", text = "Raid", pages = { "raid", "raidlead", "loot", "buffs", "tactics" } },
    { key = "trade", text = "Handel", pages = { "crafting", "trade", "wants" } },
    { key = "fun", text = "Spass", pages = { "deathroll" } },
    { key = "dev", text = "Entwickler", pages = { "dev", "bugs" } },   -- nur im Entwicklermodus sichtbar
}
ns.NAV_GROUPS = NAV_GROUPS
local function navHead(g)
    main.navHeads = main.navHeads or {}
    local h = main.navHeads[g.key]
    if h then return h end
    h = CreateFrame("Button", nil, main.side)
    h:SetSize(SIDEBAR - 16, 18)
    h.t = K.Text(h, 10, C.dim)
    h.t:SetPoint("LEFT", 10, 0)
    h.t:SetText(K.Upper(L[g.text]))
    h.arrow = K.Text(h, 10, C.dim, "RIGHT")
    h.arrow:SetPoint("RIGHT", -10, 0)
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
    h.line:SetHeight(1)
    h.line:SetPoint("LEFT", h.t, "RIGHT", 8, 0)
    h.line:SetPoint("RIGHT", h.arrow, "LEFT", -8, 0)
    h:SetScript("OnClick", function()
        local c = ns.db.settings.navClosed or {}
        ns.db.settings.navClosed = c
        c[g.key] = not c[g.key] or nil
        ns.LayoutNav()
    end)
    h:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    h:SetScript("OnLeave", function(self) self.t:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end)
    main.navHeads[g.key] = h
    return h
end

-- Favoriten + Reihenfolge der Navigation (Rechtsklick-Menue, Ziehen innerhalb der Gruppe)
function ns.NavIsFav(key)
    for _, k in ipairs(ns.db.settings.navFav or {}) do if k == key then return true end end
    return false
end
local function refreshStars()
    for _, d in pairs(pages) do if d.nav and d.nav.UpdateStar then d.nav:UpdateStar() end end
end
function ns.NavSetFav(key, on)
    local S = ns.db.settings
    S.navFav = S.navFav or {}
    for i = #S.navFav, 1, -1 do if S.navFav[i] == key then table.remove(S.navFav, i) end end
    if on then S.navFav[#S.navFav + 1] = key end
    if #S.navFav == 0 then S.navFav = nil end
    ns.LayoutNav()
    refreshStars()
end
function ns.NavMenu(owner, def)
    local fav = ns.NavIsFav(def.key)
    -- Symbol vor dem Eintrag (eingefaerbt, Glyphen aus Media\icons)
    local function ic(file, r, g, b)
        local path = file:find("\\", 1, true) and file or (M .. "icons\\" .. file)
        return ("|T%s:14:14:0:0:64:64:0:64:0:64:%d:%d:%d|t  "):format(path, math.floor((r or 0.75) * 255), math.floor((g or 0.75) * 255), math.floor((b or 0.8) * 255))
    end
    local items = {
        { text = ic(fav and "star_on" or "star_off", 1, 0.82, 0.3) .. (fav and L["Aus Favoriten entfernen"] or L["Zu Favoriten"]), fn = function() ns.NavSetFav(def.key, not fav) end },
        { text = ic(ICONS[def.key] or "home") .. L["Oeffnen"], fn = function() showPage(def.key) end },
    }
    -- Ausblenden (nicht fuer Kernseiten, die immer sichtbar bleiben)
    if not (ns.Discover and (ns.Discover.LOCKED or ns.Discover.CORE)[def.key]) then
        items[#items + 1] = { text = ic("eye_off") .. L["Ausblenden"], fn = function()
            if ns.Discover and ns.Discover.Set then ns.Discover.Set(def.key, false) end
            if current == def.key then showPage("home") end
        end }
    end
    local g = owner.navGroup
    if g and g ~= "fav" and ns.db.settings.navOrder and ns.db.settings.navOrder[g] then
        items[#items + 1] = { text = ic("sync") .. L["Reihenfolge zuruecksetzen"], fn = function() ns.db.settings.navOrder[g] = nil ns.LayoutNav() end }
    end
    K.ShowMenu(owner, items, L[def.title], 180)
end
local function cursorTop()
    local scale = main.side:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    return cy / scale - (main.side:GetTop() or 0)
end
function ns.NavDragStart(b)
    if not main or ns.db.settings.lockWindow or not b.navGroup then return end
    local slots = main.navSlots and main.navSlots[b.navGroup]
    if not slots or #slots < 2 then return end
    local order = {}
    for _, sl in ipairs(slots) do order[#order + 1] = sl.key end
    main.navDrag = { b = b, group = b.navGroup, order = order, grab = (b.navY or 0) - cursorTop() }
    b:SetFrameLevel(b:GetFrameLevel() + 10)
    b.bg:Show()
    b:SetAlpha(0.95)
    GameTooltip:Hide()
    b:SetScript("OnUpdate", function(self)
        local d = main.navDrag
        if not d or d.b ~= self then self:SetScript("OnUpdate", nil) return end
        local sl = main.navSlots[d.group]
        if not sl or #sl == 0 then return end
        -- nur innerhalb der eigenen Gruppe: zwischen erstem und letztem Platz
        local y = cursorTop() + d.grab
        -- etwas Spielraum ueber dem ersten / unter dem letzten Platz (sonst kommt man nie ganz nach oben)
        y = math.min(sl[1].top + 10, math.max(sl[#sl].top - 10, y))
        self.navY = y
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", main.side, "TOPLEFT", 8, y)
        -- neue Reihenfolge: nach Hoehe sortieren (die anderen an ihrem Ziel, der gezogene an der Maus)
        local list = {}
        for _, s2 in ipairs(sl) do list[#list + 1] = { key = s2.key, y = (s2.key == self.key) and y or s2.top } end
        table.sort(list, function(a, c)
            if a.y == c.y then return a.key == self.key end
            return a.y > c.y
        end)
        local changed = false
        for i, it in ipairs(list) do if d.order[i] ~= it.key then changed = true end end
        if changed then
            for i, it in ipairs(list) do d.order[i] = it.key end
            ns.LayoutNav()
        end
    end)
end
function ns.NavDragStop(b)
    local d = main and main.navDrag
    b:SetScript("OnUpdate", nil)
    b.dragEnd = GetTime()
    if not d or d.b ~= b then return end
    b:SetFrameLevel(math.max(1, b:GetFrameLevel() - 10))
    b:SetAlpha(1)
    b.bg:SetShown(b.isActive)
    local S = ns.db.settings
    if d.group == "fav" then
        S.navFav = d.order
    else
        S.navOrder = S.navOrder or {}
        S.navOrder[d.group] = d.order
    end
    main.navDrag = nil
    main.navAnimReady = true
    ns.LayoutNav()
    if main.navAnimDriver then main.navAnimDriver:Show() end
end

-- Navigation neu anordnen (Module an/aus, eigene Auswahl, Rechte)
function ns.LayoutNav()
    if not main then return end
    local closed = ns.db.settings.navClosed or {}
    local S = ns.db.settings
    -- 0.6.420: einmalig "Fehlerberichte" direkt unter "Entwickler" (Favoriten und Gruppe)
    if not S.navBugsAfterDev then
        S.navBugsAfterDev = true
        local function fix(list)
            if type(list) ~= "table" then return end
            local bi, di
            for i, k in ipairs(list) do if k == "bugs" then bi = i elseif k == "dev" then di = i end end
            if bi and di and bi < di then table.remove(list, bi) table.insert(list, di, "bugs") end
        end
        fix(S.navFav)
        for _, l in pairs(S.navOrder or {}) do fix(l) end
    end
    -- Favoriten (Rechtsklick) stehen in eigener Gruppe ganz oben und nur dort
    local isFav = {}
    for _, k in ipairs(S.navFav or {}) do isFav[k] = true end
    -- eigene Reihenfolge je Gruppe (Ziehen); beim Ziehen gilt die vorlaeufige Reihenfolge
    local function ordered(gkey, items)
        local drag = main.navDrag
        local ord = (drag and drag.group == gkey and drag.order) or (gkey == "fav" and S.navFav) or (S.navOrder and S.navOrder[gkey])
        if not ord then return items end
        local idx, base = {}, {}
        for i, k in ipairs(ord) do idx[k] = i end
        for i, d in ipairs(items) do base[d.key] = i end
        table.sort(items, function(a, b2) return (idx[a.key] or (1000 + base[a.key])) < (idx[b2.key] or (1000 + base[b2.key])) end)
        return items
    end
    -- Seiten den Gruppen zuordnen; was in keiner Gruppe steht, kommt ans Ende
    local inGroup, groups = {}, {}
    for gi, g in ipairs(NAV_GROUPS) do
        local items = {}
        for _, k in ipairs(g.pages) do
            local d = pages[k]
            if d and d.nav then inGroup[k] = true if ns.PageVisible(k) and not isFav[k] then items[#items + 1] = d end end
        end
        groups[#groups + 1] = { g = g, items = ordered(g.key, items) }
        if gi == 1 then
            local favItems = {}
            for _, k in ipairs(S.navFav or {}) do
                local d = pages[k]
                if d and d.nav and ns.PageVisible(k) then favItems[#favItems + 1] = d end
            end
            groups[#groups + 1] = { g = { key = "fav", text = "Favoriten" }, items = ordered("fav", favItems) }
        end
    end
    local rest = {}
    for _, d in ipairs(pageOrder) do if d.nav and not inGroup[d.key] and not isFav[d.key] and ns.PageVisible(d.key) then rest[#rest + 1] = d end end
    if #rest > 0 then groups[#groups + 1] = { g = { key = "more", text = "Weitere" }, items = ordered("more", rest) } end
    -- Hoehe: Kopfzeilen + sichtbare Eintraege muessen zwischen Logo und Fusszeile passen
    local n, heads = 0, 0
    for _, gr in ipairs(groups) do
        if #gr.items > 0 then
            if not gr.g.nohead then heads = heads + 1 end
            for _, d in ipairs(gr.items) do if not closed[gr.g.key] or d.key == current then n = n + 1 end end
        end
    end
    local room = H - 92 - 56 - heads * 22
    -- nicht mehr quetschen: lieber scrollen (Mausrad / Leiste rechts)
    local step = math.max(26, math.min(28, math.floor(room / math.max(n, 1))))
    local TOP, BOTTOM = -90, -(H - 56)
    local total = heads * 22 + n * step
    local avail = TOP - BOTTOM
    local maxOff = math.max(0, total - avail)
    main.navOff = math.max(0, math.min(main.navOff or 0, maxOff))
    local off = main.navOff
    -- Ziel je Eintrag setzen; die Bewegung macht der Animator (weiches Gleiten + Ein-/Ausblenden)
    main.navAnim = main.navAnim or {}
    local seen = {}
    local function target(f, top, want)
        f.navTarget, f.navWant = top, want
        main.navAnim[f] = true
        seen[f] = true
    end
    local function place(f, yy, hgt, from)
        local top = yy + off
        local inside = top <= TOP + 0.5 and top - hgt >= BOTTOM - 0.5
        -- neu erscheinende Eintraege kommen unter ihrer Ueberschrift hervor
        if not f.navY then f.navY, f.navA = (from or top), 0 end
        target(f, top, inside)
    end
    local y = -90
    for _, gr in ipairs(groups) do
        if #gr.items > 0 then
            local isClosed = (not gr.g.nohead) and closed[gr.g.key]
            local headTop = y + off
            if not gr.g.nohead then
                local h = navHead(gr.g)
                h.arrow:SetText(isClosed and "+" or "-")
                place(h, y, 18)
                y = y - 20
            end
            main.navSlots = main.navSlots or {}
            local slots = {}
            main.navSlots[gr.g.key] = slots
            for _, d in ipairs(gr.items) do
                if not isClosed or d.key == current then
                    d.nav:SetHeight(step - 2)
                    d.nav.navGroup = gr.g.key
                    place(d.nav, y, step - 2, headTop)
                    slots[#slots + 1] = { key = d.key, top = y + off, h = step - 2 }
                    y = y - step
                elseif d.nav.navY then
                    target(d.nav, headTop, false)      -- zuklappen: unter die Ueberschrift gleiten
                end
            end
            y = y - 2
        end
    end
    -- alles andere (ausgeblendete Seiten/Gruppen) ausblenden
    for f in pairs(main.navAnim) do
        if not seen[f] then f.navWant = false end
    end
    -- nie platzierte Eintraege (z. B. Gildenseiten ohne Gilde) gar nicht erst zeigen
    for _, d in ipairs(pageOrder) do
        if d.nav and not seen[d.nav] and not main.navAnim[d.nav] then d.nav:Hide() end
    end
    -- erster Aufbau oder "Animationen reduzieren": sofort an die Stelle
    local instant = not main.navAnimReady or (ns.db.settings.noAnim)
    main.navAnimReady = true
    local function apply(f)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", main.side, "TOPLEFT", 8, f.navY)
        f:SetAlpha(f.navA)
        if f.navA <= 0.01 and not f.navWant then f:Hide() else f:Show() end
    end
    if instant then
        for f in pairs(main.navAnim) do
            if not (main.navDrag and main.navDrag.b == f) then
                f.navY = f.navTarget or f.navY or 0
                f.navA = f.navWant and 1 or 0
                apply(f)
            end
        end
    elseif not main.navAnimDriver then
        local drv = CreateFrame("Frame", nil, main.side)
        main.navAnimDriver = drv
        drv:SetScript("OnUpdate", function(self, el)
            local busy = false
            local k = math.min(1, el * 12)          -- Geschwindigkeit des Gleitens
            for f in pairs(main.navAnim) do
              if not (main.navDrag and main.navDrag.b == f) then
                local ty, ta = f.navTarget or f.navY or 0, f.navWant and 1 or 0
                local dy, da = ty - (f.navY or ty), ta - (f.navA or 0)
                if math.abs(dy) > 0.3 or math.abs(da) > 0.01 then
                    busy = true
                    f.navY = (f.navY or ty) + dy * k
                    f.navA = math.max(0, math.min(1, (f.navA or 0) + da * math.min(1, el * 9)))
                else
                    f.navY, f.navA = ty, ta
                end
                -- ausserhalb des Navigationsbereichs (Scrollen) nicht ueber Logo/Fusszeile zeichnen
                if f.navY > TOP + 4 or f.navY - 18 < BOTTOM - 4 then f.navA = math.min(f.navA, 0) end
                apply(f)
              end
            end
            if not busy then self:Hide() end
        end)
    end
    if main.navAnimDriver and not instant then main.navAnimDriver:Show() end
    -- Scrollleiste
    if not main.navBar then
        local tr = main.side:CreateTexture(nil, "ARTWORK")
        tr:SetWidth(3)
        tr:SetPoint("TOPRIGHT", main.side, "TOPRIGHT", -3, TOP)
        tr:SetPoint("BOTTOMRIGHT", main.side, "TOPRIGHT", -3, BOTTOM)
        tr:SetColorTexture(1, 1, 1, 0.05)
        local th = main.side:CreateTexture(nil, "OVERLAY")
        th:SetWidth(3)
        th:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        main.navBar, main.navThumb = tr, th
        main.side:EnableMouseWheel(true)
        main.side:SetScript("OnMouseWheel", function(_, delta)
            main.navOff = (main.navOff or 0) - delta * 40
            ns.LayoutNav()
        end)
    end
    main.navBar:SetShown(maxOff > 0)
    main.navThumb:SetShown(maxOff > 0)
    if maxOff > 0 then
        local th = math.max(30, avail * avail / total)
        local pos = (avail - th) * (off / maxOff)
        main.navThumb:ClearAllPoints()
        main.navThumb:SetPoint("TOPRIGHT", main.side, "TOPRIGHT", -3, TOP - pos)
        main.navThumb:SetHeight(th)
    end
    local lead = ns.PageVisible("admin")
    -- Krone immer zeigen (ohne Rechte grau: Klick startet den Testmodus)
    main.crown:SetShown(not ns.Admin or ns.Admin.ShowCrown())   -- spaeter: nur fuer die Leitung (Gilden-Einstellung)
    lead = true
    main.lang:ClearAllPoints()
    main.lang:SetPoint("RIGHT", main.gear, "LEFT", -2, 0)   -- 0.6.432: Zahnrad steht wieder oben (lag sonst unter der Flagge)
    if main.FitSub then main.FitSub() end
    if main.gearColor then main.gearColor() end
    if current and current ~= "home" and not ns.PageVisible(current) and main:IsShown() then showPage("home") end
    if current == "noguild" and ns.InGuild() and main:IsShown() then showPage("home") end
end
-- Gilde betreten/verlassen: Navigation sofort anpassen
ns.On("PLAYER_GUILD_UPDATE", function() if ns.LayoutNav and main then ns.LayoutNav() end end)
ns.Listen("BRAND", function() ns.LayoutNav() end)

------------------------------------------------------------------------
-- Sprache wechseln: Fenster wird mit den neuen Texten neu aufgebaut
------------------------------------------------------------------------
local function flagTag(l) return "|T" .. M .. "flags\\" .. l.flag .. ":12:16:0:0:64:64:0:64:0:48|t  " end
-- 0.5.922: eigene Liste mit SICHEREN Knoepfen. ReloadUI() aus Addon-Code ist in diesem Client gesperrt (der Klick tat
-- nichts) - ein sicherer Knopf mit dem Makro "/reload" darf es. Vor dem Klick (PreClick) wird die Sprache gemerkt.
-- Sichere Knoepfe lassen sich im Kampf nicht anlegen/aendern: dann gibt es nur einen Hinweis.
local langMenu
function ns.ShowLanguageMenu(owner)
    if InCombatLockdown and InCombatLockdown() then
        ns.print(L["Im Kampf nicht moeglich - gleich nochmal."])
        return
    end
    local m = langMenu
    if m and m:IsShown() then m:Hide() return end
    local client = ns.langByKey[ns.ClientLang()]
    if not m then
        m = CreateFrame("Frame", "OasisLangMenu", UIParent)
        langMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        K.Fill(m, C.raised)
        K.Border(m, C.line)
        m.catcher = CreateFrame("Button", nil, UIParent)
        m.catcher:SetAllPoints(UIParent)
        m.catcher:SetFrameStrata("FULLSCREEN")
        m.catcher:SetScript("OnClick", function() if not (InCombatLockdown and InCombatLockdown()) then m:Hide() end end)
        m.catcher:Hide()
        m:SetScript("OnHide", function() m.catcher:Hide() end)
        m.rows = {}
        local list = { { key = "auto", lang = client } }
        for _, l in ipairs(ns.LANGS) do list[#list + 1] = { key = l.key, lang = l } end
        local RH = 22
        for i, e in ipairs(list) do
            local r = CreateFrame("Button", nil, m, "SecureActionButtonTemplate")
            r:SetHeight(RH)
            r:SetPoint("TOPLEFT", 1, -4 - (i - 1) * RH)
            r:SetPoint("RIGHT", m, "RIGHT", -1, 0)
            r:RegisterForClicks("AnyUp", "AnyDown")
            r.key, r.lang = e.key, e.lang
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.06)
            r.sel = r:CreateTexture(nil, "BACKGROUND")
            r.sel:SetAllPoints()
            r.selBar = r:CreateTexture(nil, "ARTWORK")
            r.selBar:SetPoint("TOPLEFT")
            r.selBar:SetPoint("BOTTOMLEFT")
            r.selBar:SetWidth(2)
            r.text = K.Text(r, 12, C.text)
            r.text:SetPoint("LEFT", 10, 0)
            -- laeuft VOR dem sicheren Makro: Sprache merken (und Klick-Ton)
            r:SetScript("PreClick", function(self)
                if self.isCurrent then return end
                ns.db.settings.lang = self.key
            end)
            r:SetScript("PostClick", function(self)
                -- gleiche Sprache gewaehlt (kein Neuladen): Liste einfach schliessen
                if self.isCurrent and not (InCombatLockdown and InCombatLockdown()) then m:Hide() end
            end)
            m.rows[i] = r
        end
        m:SetHeight(#list * RH + 8)
    end
    local cur = ns.db.settings.lang or "auto"
    local maxW = 150
    for _, r in ipairs(m.rows) do
        local l = r.lang
        local on = r.key == cur
        r.isCurrent = on
        -- nur ein Wechsel laedt neu
        r:SetAttribute("type", (not on) and "macro" or nil)
        r:SetAttribute("macrotext", (not on) and "/reload" or nil)
        K.SetFontSafe(r.text, K.fontByKey[l.cjk or "ptsans"].path, 12, "", K.FONT)
        local label = flagTag(l) .. (r.key == "auto" and (L["Wie das Spiel"] .. "  |cff777777(" .. l.name .. ")|r") or l.name)
        r.text:SetText(label)
        local c = on and C.text or C.muted
        r.text:SetTextColor(c[1], c[2], c[3])
        r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.14)
        r.selBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        r.sel:SetShown(on)
        r.selBar:SetShown(on)
        maxW = math.max(maxW, (tonumber(r.text:GetStringWidth()) or 0) + 26)
    end
    m:SetWidth(maxW)
    m:ClearAllPoints()
    -- Die Liste ist durch ihre sicheren Knoepfe selbst geschuetzt und darf nicht an Oasis-Elemente geankert werden
    -- ("Cannot anchor protected frames to regions") -> Bildschirm-Koordinaten des Knopfes ausrechnen, an UIParent haengen
    local right, bottom = owner and owner.GetRight and owner:GetRight(), owner and owner.GetBottom and owner:GetBottom()
    if right and bottom then
        local k = (owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        m:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * k, bottom * k - 4)
    else
        m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    m.catcher:Show()
    m:Show()
end
-- Kampfbeginn: Liste schliessen, solange das noch erlaubt ist (sichere Knoepfe lassen sich im Kampf nicht ausblenden)
ns.On("PLAYER_REGEN_DISABLED", function() if langMenu and langMenu:IsShown() then pcall(langMenu.Hide, langMenu) end end)
-- reload = true (Klick im Sprach-Umschalter): Sprache merken und sofort neu laden - dann stimmt ueberall alles
-- (ohne Neuladen blieben Schriften und schon gebaute Stellen in der alten Sprache). ReloadUI braucht den Klick.
function ns.SetLanguage(key, reload)
    local before = ns.db.settings.lang or "auto"
    ns.db.settings.lang = key
    local want = (key == "auto") and ns.ClientLang() or key
    if reload then
        if key ~= before or want ~= ns.lang then ReloadUI() end
        return
    end
    -- 0.5.564: Grundsprache wurde beim Start verworfen (Speicher) -> Wechsel nach /reload
    if ns.LangNeedsReload and ns.LangNeedsReload(want) then
        local l = ns.langByKey[want]
        K.Toast(l and l.name or want, L["Diese Sprache gilt nach dem naechsten /reload - hier klicken zum Neuladen."], C.accent, function() ReloadUI() end)
        return
    end
    if ns.EnsureLang and not ns.EnsureLang(want) then
        K.Toast(L["Sprache fehlt"], L["Das Sprachpaket ist nicht installiert - bitte alle Ordner aus der Oasis-ZIP nach AddOns kopieren."], C.red or C.accent)
        return
    end
    ns.lang = want
    if ns.RelabelAll then ns.RelabelAll() end
    if ns.Demo and ns.Demo.Relang then ns.Demo.Relang() end
    K.ApplyUserFonts()
    ns.RebuildMain()
    local l = ns.langByKey[ns.lang]
    K.Toast(l and l.name or ns.lang, L["Oasis-Texte umgestellt. Ein /reload stellt auch die restlichen Stellen um."], C.accent)
end
-- Hauptfenster verwerfen und mit den aktuellen Texten neu aufbauen
function ns.RebuildMain()
    if not main then return end
    ns.rebuilding = true
    local wasShown, page = main:IsShown(), current
    main:Hide()
    for _, def in ipairs(pageOrder) do
        if def.frame then def.frame:Hide() end
        def.frame, def.nav = nil, nil
    end
    main, current = nil, nil
    ns.rebuilding = nil
    if wasShown then
        ns.OpenMain()
        if page then showPage(page) end
    end
end

function ns.UpdateFooter(text)
    if main and main.foot then main.foot:SetText("") main.foot:Hide() end   -- 0.6.331: Online-Zeile in der Seitenleiste entfaellt
end

function ns.OpenMain()
    if not main then buildMain() end
    -- angeheftete Topbar bleibt stehen, auch wenn das grosse Fenster offen ist
    if not main:IsShown() then main:Show() end
    if ns.OasisFront then ns.OasisFront() end
    if not current then
        local start = ns.db.settings.startPage == "last" and ns.db.settings.lastPage or "home"
        showPage(start or pageOrder[1].key)
    end
end
-- Fenster wieder in die Bildschirmmitte (Einstellungen > Allgemein)
function ns.ResetWindowPos()
    ns.db.settings.mainPos = nil
    if main then main:ClearAllPoints() main:SetPoint("CENTER") end
end
-- Fokus: Klick ins Oasis-Fenster (oder andere Oasis-Fenster/Topbar) = Fokus, Klick in die Welt/andere Fenster = weg
do
    local fx = CreateFrame("Frame")
    local function isOasis(fr)
        local n = 0
        while fr and n < 30 do
            if fr == main then return true end
            local nm = fr.GetName and fr:GetName()
            if nm then
                if nm:find("^Oasis") then return true end
                if nm == "WorldFrame" or nm == "UIParent" then return false end
            end
            fr = fr.GetParent and fr:GetParent()
            n = n + 1
        end
        return nil   -- unbekannt (namenlose Menues): Fokus bleibt, wie er ist
    end
    if pcall(fx.RegisterEvent, fx, "GLOBAL_MOUSE_DOWN") then
        fx:SetScript("OnEvent", function()
            if not (main and main:IsShown()) then return end
            local foc
            if GetMouseFoci then local t = GetMouseFoci() foc = t and t[1] elseif GetMouseFocus then foc = GetMouseFocus() end
            local v
            if main:IsMouseOver() then v = true elseif foc then v = isOasis(foc) else v = false end
            if v ~= nil and v ~= ns.mainFocus then
                ns.mainFocus = v
                if ns.EscUpdate then ns.EscUpdate() end
            end
        end)
    end
end
ns.Listen("TOGGLE_MAIN", function()
    if ns.NoGuild and ns.NoGuild.AutoWho then pcall(ns.NoGuild.AutoWho) end
    if main and main:IsShown() then
        main:Hide()
    else
        ns.OpenMain()
    end
end)
function ns.SetScale(s)
    ns.db.settings.scale = s
    if main then main:SetScale(s) end
    -- Rollbereiche der Einstellungen neu vermessen, sobald WoW die neue Groesse berechnet hat
    for _, d in ipairs({ 0.05, 0.3 }) do
        C_Timer.After(math.max(0, tonumber(d) or 0), function() if ns.Settings and ns.Settings.Remeasure then ns.Settings.Remeasure() end end)
    end
end

------------------------------------------------------------------------
-- Minimap-Knopf im Blizzard-Stil (Logo im runden Rahmen)
------------------------------------------------------------------------
local mm
local function placeMinimap()
    local st = ns.db.settings
    local a = math.rad(st.minimapAngle or 215)
    local r = (Minimap:GetWidth() / 2) + (st.minimapDist or 5)
    local sc = st.minimapScale or 1
    mm:SetScale(sc)
    mm:ClearAllPoints()
    -- Versatz gilt im Massstab des Knopfs -> durch die Groesse teilen
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r / sc, math.sin(a) * r / sc)
end
function ns.PlaceMinimap() if mm then placeMinimap() end end
function ns.UpdateMinimapButton()
    if not mm then return end
    mm:SetShown(ns.db.settings.minimap)
end
ns.Listen("LOGIN", function()
    if not Minimap then return end
    mm = CreateFrame("Button", "OasisMinimapButton", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    local bg = mm:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    local ic = mm:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(M .. "logo64")
    ic:SetSize(21, 21)
    ic:SetPoint("CENTER", 0, 0)   -- 0.6.482: genau mittig (bei eckigen Minimap-Knoepfen sonst sichtbar versetzt)
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- 0.6.483: uebliche Feldnamen (wie LibDBIcon), damit Knopf-Sammler (eckige Minimap-Leisten) das Logo finden und mittig setzen
    mm.icon, mm.background, mm.border = ic, bg, border
    local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
    -- Neuigkeiten: feiner pulsierender Farbring um das Logo (statt grossem Schein) + Zahl-Abzeichen mit dunklem Rand
    mm.glow = mm:CreateTexture(nil, "ARTWORK", nil, 2)
    mm.glow:SetTexture(M .. "ring")
    mm.glow:SetSize(26, 26)
    mm.glow:SetPoint("CENTER", 0, 0)
    mm.glow:Hide()
    mm.pillEdge = mm:CreateTexture(nil, "OVERLAY", nil, 1)
    mm.pillEdge:SetTexture(MASK)
    mm.pillEdge:SetSize(19, 19)
    mm.pillEdge:SetPoint("CENTER", mm, "TOPRIGHT", -3, -3)
    mm.pillEdge:SetVertexColor(0.05, 0.05, 0.06, 1)
    mm.pillEdge:Hide()
    mm.pill = mm:CreateTexture(nil, "OVERLAY", nil, 2)
    mm.pill:SetTexture(MASK)
    mm.pill:SetSize(14, 14)
    mm.pill:SetPoint("CENTER", mm.pillEdge, "CENTER")
    mm.pill:Hide()
    mm.badge = mm:CreateFontString(nil, "OVERLAY", nil, 3)
    K.SetFontSafe(mm.badge, K.FONT_HEAD, 10, "OUTLINE", K.FONT)
    K.CenterNum(mm.badge, mm.pill, "CENTER", 0, 0)
    mm:HookScript("OnUpdate", function(self, el)
        if not self.pulseOn then return end
        self.gt = (self.gt or 0) + el
        local q = 0.5 + 0.5 * math.sin(self.gt * 2.5)
        -- Abzeichen pulsiert leicht in der Groesse
        local sz = 15 + q * 1.5
        self.pill:SetSize(sz, sz)
    end)
    mm:RegisterForClicks("AnyUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns.ShowPage("settings") elseif ns.FlyToggle then ns.FlyToggle(mm) else ns.Fire("TOGGLE_MAIN") end
    end)
    mm:SetScript("OnDragStart", function(self)
        if ns.db.settings.minimapLock then return end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            cx, cy = cx / s, cy / s
            ns.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            placeMinimap()
        end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
        local lines = { "Oasis" }
        local total, _, list = ns.NotifyTotal(true)
        if total > 0 then
            for _, x in ipairs(list) do lines[#lines + 1] = K.hex(C.accent) .. x.n .. "|r  " .. x.text end
            lines[#lines + 1] = " "
        end
        lines[#lines + 1] = "|cff888888" .. L["Linksklick: oeffnen"] .. "  ·  " .. L["Rechtsklick: Einstellungen"] .. "|r"
        K.ShowTip(self, lines, "ANCHOR_LEFT")
    end)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
    placeMinimap()
    ns.UpdateMinimapButton()
end)
function ns.SetMinimapBadge() if ns.UpdateNotify then ns.UpdateNotify() end end
-- Minimap-Knopf + Oasis-Leiste mit allen Neuigkeiten aktualisieren
function ns.UpdateNotify()
    local total, mention = ns.NotifyTotal()
    if mm then
        local on = total > 0 and ns.db.settings.minimapBadge ~= false
        local c = mention and C.amber or C.accent
        mm.pill:SetVertexColor(c[1], c[2], c[3])
        mm.glow:SetVertexColor(c[1], c[2], c[3])
        mm.pill:SetShown(on)
        mm.pillEdge:SetShown(on)
        mm.glow:SetShown(false)   -- kein Ring mehr (lag auf Blizzards Rahmen)
        mm.pulseOn = on
        mm.badge:SetText(on and (total > 99 and "99" or tostring(total)) or "")
    end
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
end

-- Ladebildschirm: danach wieder oeffnen, wenn Oasis vorher offen war
ns.On("LOADING_SCREEN_ENABLED", function() ns.loadingScreen = true end)
ns.On("LOADING_SCREEN_DISABLED", function()
    ns.After(0.6, function()
        ns.loadingScreen = false
        if ns.db and ns.db.settings.mainOpen and (not ns.db.settings.collapsed or (ns.TopbarMode and ns.TopbarMode() == "always")) and not ns.inCombat()
            and not (main and main:IsShown()) then ns.OpenMain() end
        if ns.db and ns.db.settings.collapsed and ns.ShowMiniBar then ns.ShowMiniBar() end
    end)
end)
-- war Oasis beim /reload offen: wieder oeffnen (gleiche Stelle, gleiche Seite)
ns.Listen("LOGIN", function()
    local mode = ns.db.settings.openOnLogin
    if mode == "never" then return end
    if mode == "always" or ns.db.settings.mainOpen then ns.After(1, function() if not ns.inCombat() then ns.OpenMain() end end) end
end)

-- Hintergrund-Deckkraft (Einstellungen > Aussehen)
-- Fenster, Seitenleiste (+ Schimmer) und Grafik mit EINEM Faktor; die Flaechen im Fenster
-- (Karten, Felder) bekommen denselben Faktor ueber K.ApplyTheme -> beim Loslassen des Reglers Neuaufbau
function ns.ApplyWindowAlpha(m)
    m = m or main
    if not (m and m.bgTex) then return end
    local a = K.WindowAlpha and K.WindowAlpha() or (ns.db and ns.db.settings.windowAlpha or 1)
    -- Flaechen mit gemerkter Farbe: Deckkraft in die Farbe rechnen (wirkt auch auf Verlaeufe)
    if not (K.RepaintWindowTex and K.RepaintWindowTex(m.bgTex)) then m.bgTex:SetAlpha(a) end
    if m.sideTex and not (K.RepaintWindowTex and K.RepaintWindowTex(m.sideTex)) then m.sideTex:SetAlpha(a) end
    if m.sideGlow then m.sideGlow:SetAlpha(a) end
    if m.themeTex and K.CurrentTheme then m.themeTex:SetAlpha((K.CurrentTheme().texAlpha or 1) * a) end
end
ns.Listen("LOGIN", function() C_Timer.After(0.5, function() pcall(ns.ApplyWindowAlpha) end) end)
-- im Kampf ausblenden und danach wieder zeigen
local hiddenForCombat
ns.On("PLAYER_REGEN_DISABLED", function()
    local m = main
    if ns.db and ns.db.settings.hideInCombat and m and m:IsShown() then
        hiddenForCombat = true
        m:Hide()
    end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if hiddenForCombat then
        hiddenForCombat = nil
        local m = main
        -- 0.5.596: "Nach dem Kampf wieder zeigen" aus -> bleibt zu
        if m and ns.db.settings.combatReshow ~= false then m:Show() end
    end
end)
-- 0.5.596: Ausblenden im Kampf ist jetzt Standard (einmalig fuer alle eingeschaltet), danach wieder zeigen an
ns.Listen("DB_READY", function()
    local s = ns.db and ns.db.settings
    if s and not s.combat596 then
        s.combat596 = true
        s.hideInCombat = true
        if s.combatReshow == nil then s.combatReshow = true end
    end
end)

-- Pruefbefehl: /oa ecke -> welche sichtbaren Flaechen reichen bis in die Ecke unten rechts (eckige Kante ueber der Rundung)
ns.slash.ecke = function()
    local m = main
    if not (m and m:IsShown()) then print("Oasis: erst das Fenster oeffnen") return end
    local R, B = m:GetRight(), m:GetBottom()
    local found = 0
    local function path(o)
        local t, n = {}, 0
        while o and n < 6 do
            t[#t + 1] = (o.GetName and o:GetName()) or (o.GetObjectType and o:GetObjectType()) or "?"
            o = o.GetParent and o:GetParent()
            n = n + 1
        end
        return table.concat(t, " < ")
    end
    local function check(o)
        if found > 25 or not (o.IsVisible and o:IsVisible()) then return end
        local r, b = o:GetRight(), o:GetBottom()
        if r and b and r >= R - 3 and b <= B + 3 then
            local info = ""
            if o.GetObjectType and o:GetObjectType() == "Texture" then
                local tex = o.GetTexture and o:GetTexture()
                local nm = (o.GetNumMaskTextures and o:GetNumMaskTextures()) or 0
                info = ("  tex=%s masken=%d a=%.2f"):format(tostring(tex), nm, o:GetAlpha() or 1)
            end
            found = found + 1
            print(("Oasis Ecke: %s  %dx%d%s"):format(path(o), o:GetWidth() or 0, o:GetHeight() or 0, info))
        end
    end
    local function walk(f, depth)
        if depth > 8 or not f:IsVisible() then return end
        for _, rg in ipairs({ f:GetRegions() }) do check(rg) end
        check(f)
        for _, c in ipairs({ f:GetChildren() }) do walk(c, depth + 1) end
    end
    walk(m, 0)
    print("Oasis Ecke: " .. found .. " Treffer")
end

-- Pruefbefehl: /oa rahmen -> zeigt, was mit dem Akzentrahmen los ist
ns.slash.rahmen = function()
    local m = main
    if not m then print("Oasis: Fenster noch nicht gebaut - erst /oa oeffnen") return end
    local e = m.accentEdge
    local b = e and e.borders and e.borders[1]
    local r, g, bl, a = 0, 0, 0, 0
    if b and b.GetVertexColor then r, g, bl, a = b:GetVertexColor() end
    print(("Oasis Rahmen: Einstellung=%s  Rahmen=%s sichtbar=%s  Ebene Fenster=%s/%d Rahmen=%s/%d  Breite=%d  Linie alpha=%.2f shown=%s"):format(
        tostring(ns.db.settings.frameAccent), tostring(e ~= nil), tostring(e and e:IsVisible()),
        m:GetFrameStrata(), m:GetFrameLevel(), e and e:GetFrameStrata() or "-", e and e:GetFrameLevel() or -1,
        e and e:GetWidth() or -1, b and b:GetAlpha() or -1, tostring(b and b:IsShown())))
    -- 0.6.165: Zierrahmen mit Schimmer pruefen (wird auch in OasisDB.frameDiag gespeichert)
    local fl = m.frameLines
    local d = { "Zierrahmen=" .. tostring(fl ~= nil) }
    if fl then
        local t = fl.lines and fl.lines[1]
        local tr, tg, tb, ta = 0, 0, 0, 0
        if t and t.GetVertexColor then tr, tg, tb, ta = t:GetVertexColor() end
        d[#d + 1] = ("sichtbar=%s alpha=%.2f eff=%.2f Ebene=%s/%d Groesse=%.0fx%.0f Linie=%s tex=%s farbe=%.2f/%.2f/%.2f/%.2f gezeigt=%s"):format(
            tostring(fl:IsVisible()), fl:GetAlpha() or -1, fl.GetEffectiveAlpha and fl:GetEffectiveAlpha() or -1,
            fl:GetFrameStrata(), fl:GetFrameLevel(), fl:GetWidth() or 0, fl:GetHeight() or 0,
            tostring(t ~= nil), tostring(t and t:GetTexture()), tr, tg, tb, ta, tostring(t and t:IsVisible()))
        d[#d + 1] = ("Linie Groesse=%.1fx%.1f  Fenster-Ebene max Kind=%s  noAnim=%s frameShimmer=%s"):format(
            t and t:GetWidth() or -1, t and t:GetHeight() or -1, tostring(m.lineFrame and m.lineFrame:GetFrameLevel()),
            tostring(ns.db.settings.noAnim), tostring(ns.db.settings.frameShimmer))
    end
    for _, x in ipairs(d) do print("Oasis Zierrahmen: " .. x) end
    OasisDB.frameDiag = d
end

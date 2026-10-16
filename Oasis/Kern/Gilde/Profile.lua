-- Oasis: Profilkarte (Klick auf einen Namen) und Rollen-Symbole
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Profile = {}
ns.Profile = Profile
-- Charakter ausserhalb der Gilde? (Absender kommen in Forever nur als "Vorname-Realm" -> auch per Vorname pruefen)
function Profile.OutsideGuild(c)
    if not c or ns.isMe(c) or not (ns.Admin and ns.Admin.InGuildList) then return false end
    if ns.Admin.InGuildList(c) ~= false then return false end
    return true
end

------------------------------------------------------------------------
-- Rollen: eigene Symbole (Schild / Verbandskasten / Schwert), je Rolle eingefaerbt
------------------------------------------------------------------------
local ROLE_NAMES = { tank = "Tank", heal = "Heiler", dps = "Schaden" }
Profile.ROLE_COLORS = { tank = { 0.38, 0.62, 1.00 }, heal = { 0.40, 0.86, 0.62 }, dps = { 1.00, 0.35, 0.30 } }
function Profile.RoleTexture(role) return ns.MEDIA .. "icons\\role_" .. role end

function Profile.RoleIcon(role, size, dim)
    local c = Profile.ROLE_COLORS[role]
    if not c then return "" end
    local f = dim and 0.35 or 1
    return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(Profile.RoleTexture(role), size or 14, size or 14,
        math.floor(c[1] * 255 * f), math.floor(c[2] * 255 * f), math.floor(c[3] * 255 * f))
end
-- Rollen als Kurzstring "thd" <-> Tabelle
function Profile.EncodeRoles(r)
    return (r.tank and "t" or "") .. (r.heal and "h" or "") .. (r.dps and "d" or "")
end
function Profile.RolesOf(name)
    local s
    if ns.isMe(name) then
        s = ns.Groups and Profile.EncodeRoles(ns.Groups.MyRoles()) or ""
    else
        local p = ns.db.members[name]
        s = p and p.rl or ""
    end
    return { tank = s:find("t") ~= nil, heal = s:find("h") ~= nil, dps = s:find("d") ~= nil }, s ~= ""
end
function Profile.RoleIcons(name, size)
    local r, known = Profile.RolesOf(name)
    if not known then return "" end
    local t = {}
    for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then t[#t + 1] = Profile.RoleIcon(k, size) end end
    return table.concat(t, "  ")
end

------------------------------------------------------------------------
-- Rollenwahl: drei Knoepfe (eigene Rollen anklickbar, fremde nur Anzeige)
------------------------------------------------------------------------
local ROLE_ORDER = { "tank", "heal", "dps" }
function Profile.SetMyRole(role, on)
    local r = ns.Groups and ns.Groups.MyRoles()
    if not r then return end
    -- nur EINE Rolle (wie Blizzards Gruppenrolle)
    for _, k in ipairs(ROLE_ORDER) do r[k] = false end
    r[role] = on and true or false
    -- bewusste Wahl: 4 s lang keine Rueckmeldung von Blizzard uebernehmen (sonst springt es hin und her)
    Profile.lockUntil = GetTime() + 4
    ns.RoleLog("SetMyRole", role, on)
    Profile.PushBlizzardRoles(on and role or nil)
    if ns.Radar then ns.Radar.SendHello() end
    ns.Fire("ROLES_CHANGED")
    ns.RefreshPage("radar")
end
-- Abgleich mit Blizzards Rollenwahl (Gruppensuche / Rollencheck), falls der Client sie hat
local B2O = { TANK = "tank", HEALER = "heal", DAMAGER = "dps" }
local O2B = { tank = "TANK", heal = "HEALER", dps = "DAMAGER" }
function Profile.PushBlizzardRoles(justOn)
    local r = ns.Groups and ns.Groups.MyRoles()
    if not r or ns.inCombat() then return end
    -- Gruppenrolle (Rechtsklick auf dein Portrait > Rolle waehlen): kennt nur EINE Rolle, nur in einer Gruppe.
    -- Gerade angeklickte Rolle nehmen, sonst die einzige/erste gewaehlte
    if UnitSetRole and IsInGroup and IsInGroup() then
        local pick = justOn
        if not pick then for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then pick = k break end end end
        local want = pick and O2B[pick] or "NONE"
        local cur = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
        if cur ~= want then ns.RoleLog("UnitSetRole", cur, "->", want) pcall(UnitSetRole, "player", want) end
    end
    if SetLFGRoles then
        local leader = GetLFGRoles and select(1, GetLFGRoles()) or false
        pcall(SetLFGRoles, leader and true or false, r.tank and true or false, r.heal and true or false, r.dps and true or false)
    end
end
function Profile.PullBlizzardRoles()
    if not GetLFGRoles or not ns.Groups then return end
    local ok, _, tank, heal, dps = pcall(GetLFGRoles)
    if not ok or not (tank or heal or dps) then return end
    local r = ns.Groups.MyRoles()
    if r.tank == (tank and true or false) and r.heal == (heal and true or false) and r.dps == (dps and true or false) then return end
    -- nur eine Rolle uebernehmen (erste gewaehlte)
    r.tank, r.heal, r.dps = tank and true or false, (heal and not tank) and true or false, (dps and not tank and not heal) and true or false
    if ns.Radar then ns.Radar.SendHello() end
    ns.Fire("ROLES_CHANGED")
    ns.RefreshPage("radar")
end
-- (abgeschaltet: Rollen der Gruppensuche stehen standardmaessig auf Schaden und ueberschrieben die Oasis-Rolle)
-- Gruppenrolle im Blizzard-Menue geaendert -> in Oasis als (zusaetzliche) Rolle uebernehmen
local function pullGroupRole()
    if not (UnitGroupRolesAssigned and ns.Groups) then return end
    local k = B2O[UnitGroupRolesAssigned("player") or ""]
    if GetTime() < (Profile.lockUntil or 0) then ns.RoleLog("pull skip (lock)", k) return end
    if not k then return end
    ns.RoleLog("pull from Blizzard", k)
    local r = ns.Groups.MyRoles()
    if r[k] and not (r.tank and r.heal or r.tank and r.dps or r.heal and r.dps) then return end
    for _, x in ipairs(ROLE_ORDER) do r[x] = false end
    r[k] = true
    if ns.Radar then ns.Radar.SendHello() end
    ns.Fire("ROLES_CHANGED")
    ns.RefreshPage("radar")
end
-- Beim Beitritt setzt WoW eine Standardrolle (meist Schaden) -> NICHT uebernehmen, sondern die Oasis-Rolle
-- an Blizzard geben. Erst danach gelten Aenderungen im Blizzard-Menue als echte Wahl.
local wasInGroup, joinedAt = IsInGroup and IsInGroup() or false, 0
ns.On("GROUP_ROSTER_UPDATE", function()
    local now = IsInGroup and IsInGroup() or false
    if now and not wasInGroup then
        joinedAt = GetTime()
        ns.After(1, function() Profile.PushBlizzardRoles() end)
        ns.After(4, function() Profile.PushBlizzardRoles() end)
    end
    wasInGroup = now
end)
ns.On("PLAYER_ROLES_ASSIGNED", function()
    if GetTime() - joinedAt < 8 then return end
    ns.After(0.2, pullGroupRole)
end)
-- (abgeschaltet: Rollen der Gruppensuche stehen standardmaessig auf Schaden und ueberschrieben die Oasis-Rolle)
-- (abgeschaltet: Rollen der Gruppensuche stehen standardmaessig auf Schaden und ueberschrieben die Oasis-Rolle)

-- nameFn() liefert den Spieler; bei mir selbst sind die Knoepfe klickbar
function Profile.RoleChips(parent, w, nameFn)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, 26)
    f.chips = {}
    local cw = (w - 12) / 3
    for i, role in ipairs(ROLE_ORDER) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(cw, 26)
        b:SetPoint("LEFT", (i - 1) * (cw + 6), 0)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.icon = K.Glyph(b, 15, Profile.RoleTexture(role))
        b.icon:SetPoint("LEFT", 10, 0)
        b.label = K.Text(b, 12, C.muted)
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
        b.label:SetText(L[ROLE_NAMES[role]])
        b.role = role
        b:SetScript("OnClick", function(self)
            if not ns.isMe(nameFn()) then return end
            local r = ns.Groups.MyRoles()
            Profile.SetMyRole(self.role, not r[self.role])
            f:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            if ns.isMe(nameFn()) then K.ShowTip(self, { L[ROLE_NAMES[role]], (IsInGroup and IsInGroup()) and L["Klick: Rolle an/aus - die Gilde sieht deine Wahl"] or L["Klick: Wunschrolle - wird beim naechsten Gruppenbeitritt an WoW gegeben"] }) end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.chips[i] = b
    end
    function f:Refresh()
        local name = nameFn()
        local r, known = Profile.RolesOf(name)
        local mine = ns.isMe(name)
        for _, b in ipairs(self.chips) do
            local on = known and r[b.role]
            local c = Profile.ROLE_COLORS[b.role]
            b.bg:SetColorTexture(on and c[1] * 0.22 or C.raised[1], on and c[2] * 0.22 or C.raised[2], on and c[3] * 0.22 or C.raised[3], 1)
            K.SetBorderColor(b, on and { c[1], c[2], c[3], 1 } or C.line)
            b.icon:SetVertexColor(c[1], c[2], c[3])
            b.icon:SetAlpha(on and 1 or 0.35)
            local tc = on and C.text or C.dim
            b.label:SetTextColor(tc[1], tc[2], tc[3])
            b:EnableMouse(mine)
        end
        -- eigene Rolle nur in einer Gruppe aenderbar (wie Blizzards Gruppenrolle); sonst ausgegraut, letzte Wahl bleibt
        -- ohne Gruppe: Wunschrolle (wird beim naechsten Gruppenbeitritt an Blizzard gegeben) - immer waehlbar
        local wish = mine and not (IsInGroup and IsInGroup())
        self:SetAlpha(1)
        if self.onLock then self.onLock(wish) end
    end
    ns.On("GROUP_ROSTER_UPDATE", function() if f:IsVisible() then f:Refresh() end end)
    return f
end

------------------------------------------------------------------------
-- Karte
------------------------------------------------------------------------
local card
local W, H = 420, 560   -- breiter (08.10.): fuenf Reiter mit Zaehlern passten nicht
-- 2026: Glas-Optik wie Profil-Seite/Sammlungen (Helfer aus ns.Insta; fehlen sie, bleibt die alte Karte)
local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
local function glass(f, fill, line, r) if hasGlass() then ns.Insta.Glass(f, fill, line, r) end end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
local function label(parent, text, y)
    local l = K.Text(parent, hasGlass() and 11 or 10, hasGlass() and C.muted or C.dim)
    l:SetPoint("TOPLEFT", 18, y)
    l:SetText(hasGlass() and text or K.Upper(text))
    return l
end
local function calmBtn(b, primary)
    if not (b and hasGlass()) then return b end
    local ac = C.accent
    local fill = primary and { ac[1], ac[2], ac[3], 0.16 } or { 1, 1, 1, 0.05 }
    local line = primary and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.10 }
    if b.sheen then b.sheen:Hide() end
    glass(b, fill, line, 9)
    b:SetScript("OnEnter", function(self) glass(self, { fill[1], fill[2], fill[3], fill[4] + 0.05 }, { line[1], line[2], line[3], line[4] + 0.12 }) end)
    b:SetScript("OnLeave", function(self) glass(self, fill, line) end)
    return b
end
local function divider(parent, y)
    local d = K.Divider(parent)
    d:SetPoint("TOPLEFT", 14, y)
    d:SetPoint("TOPRIGHT", -14, y)
    return d
end

local function build()
    local f = CreateFrame("Frame", "OasisProfileCard", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", -300, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.bg = K.Fill(f, C.bg)
    K.Border(f, C.line)
    glass(f, { C.bg[1], C.bg[2], C.bg[3], 0.97 }, { 1, 1, 1, 0.10 }, 14)
    ns.EscClose("OasisProfileCard")

    -- Kopf: Klassenfarbe als Streifen + zarter Verlauf, Name gross, Status als Plakette
    f.stripe = f:CreateTexture(nil, "ARTWORK")
    f.stripe:SetPoint("TOPLEFT", 1, -1)
    f.stripe:SetPoint("TOPRIGHT", -1, -1)
    f.stripe:SetHeight(3)
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.glow:SetPoint("TOPLEFT", 1, -4)
    f.glow:SetPoint("TOPRIGHT", -1, -4)
    f.glow:SetHeight(70)
    f.glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    if hasGlass() then
        f.stripe:Hide()
        f.glow:ClearAllPoints()
        f.glow:SetPoint("TOPLEFT", 0, 0)
        f.glow:SetPoint("TOPRIGHT", 0, 0)
        f.glow:SetHeight(120)
        round(f.glow, f, 14)
    end
    -- Kopfbild: echtes Modell (ich / Ziel / Gruppe), sonst Volk+Geschlecht aus dem Oasis-Profil, sonst Klassensymbol
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetSize(56, 56)   -- 0.5.586: kleiner, der gemalte Rangrahmen liegt aussen herum
    f.head:SetPoint("TOPLEFT", 20, -22)
    f.head.bg = K.Fill(f.head, C.side)
    f.head.border = K.Border(f.head, C.line)
    f.model = CreateFrame("PlayerModel", nil, f.head)
    f.model:SetPoint("TOPLEFT", 1, -1)
    f.model:SetPoint("BOTTOMRIGHT", -1, 1)
    f.model:SetScript("OnModelLoaded", function(self)
        pcall(self.SetPortraitZoom, self, 1)
        pcall(self.SetFacing, self, 0.25)
    end)
    -- Rang-Rahmen um das Kopfbild (Oasis-Rang: Holz, Bronze, Silber, Gold, Smaragd ...)
    f.rframe = K.RankFrame(f, 56, hasGlass() and "circle" or "square")
    f.rframe:SetPoint("CENTER", f.head, "CENTER")
    -- Rangrahmen UNTER das Kopfbild: sein Ring ist eine gefuellte Scheibe (Holz = brauner Kreis lag sonst ueber
    -- Portrait/Klassensymbol, 08.10.); das Kopfbild ist kleiner, der Ring bleibt als Rand sichtbar
    f.rframe:SetFrameLevel(f.head:GetFrameLevel())
    f.head:SetFrameLevel(f.rframe:GetFrameLevel() + 3)
    f.rframe:EnableMouse(false)
    -- die gefuellte Innenscheibe des Rangrahmens liegt ueber dem Portrait (hoehere Ebene) -> weg, nur der Rand bleibt
    if f.rframe.inner then f.rframe.inner:Hide() f.rframe.inner.Show = function() end end
    f.headIcon = f.head:CreateTexture(nil, "ARTWORK")
    f.headIcon:SetPoint("TOPLEFT", 6, -6)
    f.headIcon:SetPoint("BOTTOMRIGHT", -6, 6)
    if hasGlass() then
        f.head.bg:Hide()
        for _, t in ipairs(f.head.borders or {}) do t:Hide() end
        f.head.disc = f.head:CreateTexture(nil, "BACKGROUND")
        f.head.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        f.head.disc:SetAllPoints()
        f.head.disc:SetVertexColor(0.06, 0.06, 0.08, 1)
        f.head.ring = f.head:CreateTexture(nil, "OVERLAY")
        f.head.ring:SetTexture(ns.MEDIA .. "ring")
        f.head.ring:SetPoint("TOPLEFT", -2, 2)
        f.head.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        f.headIcon:ClearAllPoints()
        f.headIcon:SetPoint("TOPLEFT", 3, -3)
        f.headIcon:SetPoint("BOTTOMRIGHT", -3, 3)
        if f.headIcon.SetMask then pcall(f.headIcon.SetMask, f.headIcon, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end K.MaskSafe(f.headIcon)
        f.model:Hide()
        -- 0.5.582: kein zweiter Rangrahmen-Ring mehr um das Bild (lag versetzt ueber dem Klassenring);
        -- der Oasis-Rang sitzt wie im grossen Profil als Wappen unten am Kopfbild
        -- 0.5.586: gemalter Rangrahmen (Media/avatar) ueber dem Kopfbild; Klassenring nur ohne Rang
        f.rframe:SetFrameLevel(f.head:GetFrameLevel() + 4)
        if K.RankEmblem then
            f.remb = K.RankEmblem(f, 30)
            f.remb:SetPoint("CENTER", f.head, "BOTTOM", 0, -3)
            f.remb:SetFrameLevel(f.head:GetFrameLevel() + 10)
            f.remb:Hide()
        end
    end
    f.name = K.Title(f, hasGlass() and 22 or 20, C.text)
    f.name:SetPoint("TOPLEFT", 100, -20)
    -- Chips unter dem Namen (Level, Klasse, Gildenrang, Oasis-Rang, Online + Gebiet), bis zwei Zeilen
    f.tags = {}
    function f:SetTags(list)
        local x, y, maxW = 100, -50, W - 18
        for i, it in ipairs(list) do
            local c = self.tags[i]
            if not c then
                c = CreateFrame("Frame", nil, self)
                c:SetHeight(19)
                c.dot = c:CreateTexture(nil, "ARTWORK")
                c.dot:SetTexture(ns.MEDIA .. "dot")
                c.dot:SetSize(7, 7)
                c.dot:SetPoint("LEFT", 8, 0)
                c.t = K.Text(c, 11, C.text)
                c.t:SetWordWrap(false)
                self.tags[i] = c
            end
            c.t:SetText(it.text)
            c.dot:SetShown(it.dot and true or false)
            if it.dot then c.dot:SetVertexColor(it.dot[1], it.dot[2], it.dot[3]) end
            c.t:ClearAllPoints()
            c.t:SetPoint("LEFT", it.dot and 19 or 8, 0)
            local w = math.min(maxW - 94, (c.t:GetStringWidth() or 40) + (it.dot and 27 or 16))
            c.t:SetWidth(w - (it.dot and 25 or 14))
            c:SetWidth(w)
            if x + w > maxW and x > 94 then x, y = 94, y - 23 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
            local k = it.color
            glass(c, k and { k[1], k[2], k[3], 0.12 } or { 1, 1, 1, 0.05 }, k and { k[1], k[2], k[3], 0.45 } or { 1, 1, 1, 0.10 }, 9)
            c:Show()
            x = x + w + 5
        end
        for i = #list + 1, #self.tags do self.tags[i]:Hide() end
        return y
    end
    f.name:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.sub = K.Text(f, 12, C.muted)
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
    f.pill = CreateFrame("Frame", nil, f)
    f.pill:SetHeight(18)
    f.pill:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -7)
    f.bio = K.Text(f, 12, C.text)
    f.bio:SetPoint("LEFT", f.pill, "RIGHT", 12, 0)
    f.bio:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.bio:SetWordWrap(false)
    if hasGlass() then
        f.sub:Hide()
        f.pill:Hide()
        f.bio:ClearAllPoints()
        f.bio:SetPoint("TOPLEFT", 18, -98)
        f.bio:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    end
    f.pill.bg = K.Fill(f.pill, C.raised)
    f.pill.dot = f.pill:CreateTexture(nil, "ARTWORK")
    f.pill.dot:SetTexture(ns.MEDIA .. "dot")
    f.pill.dot:SetSize(10, 10)
    f.pill.dot:SetPoint("LEFT", 6, 0)
    f.pill.text = K.Text(f.pill, 11, C.text)
    f.pill.text:SetPoint("LEFT", f.pill.dot, "RIGHT", 4, 0)
    f.oasis = f:CreateTexture(nil, "ARTWORK")
    f.oasis:SetTexture(ns.MEDIA .. "logo64")
    f.oasis:SetSize(18, 18)
    f.oasis:SetPoint("TOPRIGHT", -40, -18)
    local close = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
    close:SetPoint("TOPRIGHT", -8, -8)
    ----------------------------------------------------------------
    -- 2026: Aktionsleiste (runde Icon-Knoepfe) + Reiter in der Karte; nichts wird mehr abgeschnitten
    ----------------------------------------------------------------
    local ICO = ns.MEDIA .. "icons\\"
    f.actions = {}
    local function action(key, icon, tip)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(32, 32)
        b.key = key
        glass(b, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 16)
        if not hasGlass() then b.bg = K.Fill(b, C.raised) K.Border(b, C.line) end
        b.ico = K.Glyph(b, 15, ICO .. icon, C.muted)
        b.ico:SetPoint("CENTER", 0, 0)
        b.tip = tip
        b.enabled = true
        function b:SetEnabledState(on)
            self.enabled = on and true or false
            self:SetAlpha(self.enabled and 1 or 0.35)
        end
        function b:SetLabel() end
        b:SetScript("OnEnter", function(self)
            local ac = (self.key == "whisper") and C.accent or C.mint
            if self.enabled then
                glass(self, { ac[1], ac[2], ac[3], 0.16 }, { ac[1], ac[2], ac[3], 0.6 })
                self.ico:SetVertexColor(ac[1], ac[2], ac[3])
            end
            K.ShowTip(self, self.enabled and self.tip or { self.tip, "|cff888888" .. (self.why or L["gerade nicht moeglich"]) .. "|r" })
        end)
        b:SetScript("OnLeave", function(self)
            glass(self, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 })
            self.ico:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            GameTooltip:Hide()
        end)
        local click = b.SetScript
        -- Klick nur, wenn aktiv (alte Aufrufer setzen OnClick wie bei K.Button)
        function b:SetScript(ev, fn)
            if ev == "OnClick" then
                self.onClick = fn
                return click(self, "OnClick", function(s, ...) if s.enabled and s.onClick then s.onClick(s, ...) end end)
            end
            return click(self, ev, fn)
        end
        f.actions[#f.actions + 1] = b
        return b
    end
    f.whisper = action("whisper", "social", L["Anfluestern"])
    f.invite = action("invite", "groups", L["In Gruppe einladen"])
    f.duel = action("duel", "deathroll", L["Todeswuerfeln"])
    f.mapBtn = action("map", "map", L["Auf der Karte zeigen"])
    f.noteBtn = action("note", "checklist", L["Offiziersnotiz bearbeiten"])
    f.chatBtn = action("chat", "announce", L["Im Gildenchat erwaehnen"])
    -- Talente ansehen (geteilt per Oasis oder beim Betrachten gemerkt)
    f.talBtn = action("talents", "stats", L["Talente ansehen"])
    f.talBtn:SetScript("OnClick", function() if ns.Talents and f.who then ns.Talents.Show(f.who) end end)
    function f:LayoutActions()
        local x = 18
        for _, b in ipairs(self.actions) do
            if b.avail ~= false then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -118)
                b:Show()
                x = x + 32 + 8
            else
                b:Hide()
            end
        end
    end

    -- Reiter: Uebersicht | Berufe | Abzeichen | Chronik
    local TABS = { { "over", L["Uebersicht"] }, { "chars", L["Charaktere"] }, { "prof", L["Berufe"] }, { "badge", L["Abzeichen"] }, { "chron", L["Chronik"] } }
    f.tabBtns, f.panes = {}, {}
    f.tabBar = CreateFrame("Frame", nil, f)
    f.tabBar:SetPoint("TOPLEFT", 16, -160)
    f.tabBar:SetPoint("TOPRIGHT", -16, -160)
    f.tabBar:SetHeight(28)
    glass(f.tabBar, nil, nil, 10)
    local tw = (W - 32 - 8 - 6) / 4
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f.tabBar)
        b:SetSize(tw, 22)
        b:SetPoint("LEFT", 4 + (i - 1) * (tw + 2), 0)
        b.key = t[1]
        b.label = K.Text(b, 12, C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 0)
        b.label:SetText(t[2])
        b.count = t[2]
        b:SetScript("OnClick", function(self) f:SelectTab(self.key) end)
        b:SetScript("OnEnter", function(self) if f.tab ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
        b:SetScript("OnLeave", function(self) if f.tab ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
        f.tabBtns[i] = b
        local pane = CreateFrame("Frame", nil, f)
        pane:SetPoint("TOPLEFT", 0, -196)
        pane:SetPoint("BOTTOMRIGHT", 0, 12)
        pane:Hide()
        f.panes[t[1]] = pane
    end
    -- Reiter verteilen; "Charaktere" nur, wenn mehr als ein Charakter bekannt ist
    function f:LayoutTabs(showChars)
        self.showChars = showChars
        local vis = {}
        for _, b in ipairs(self.tabBtns) do
            if b.key ~= "chars" or showChars then vis[#vis + 1] = b else b:Hide() end
        end
        -- Breite je Reiter nach Text (Zaehler "Berufe 5" brauchen mehr), Rest gleichmaessig verteilen
        local avail = W - 32 - 8 - (#vis - 1) * 2
        local size = 12
        local nat, sum
        for _ = 1, 3 do
            nat, sum = {}, 0
            for i, b in ipairs(vis) do
                if K.FONT then pcall(b.label.SetFont, b.label, K.FONT, size, "") end
                b.label:SetWidth(0)
                nat[i] = (b.label:GetStringWidth() or 40) + 14
                sum = sum + nat[i]
            end
            if sum <= avail or size <= 10 then break end
            size = size - 1
        end
        local extra = (avail - sum) / #vis
        local x = 4
        for i, b in ipairs(vis) do
            local w = math.max(30, nat[i] + extra)
            b:SetSize(w, 22)
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            b.label:SetWidth(w - 4)
            b.label:SetWordWrap(false)
            b:Show()
            x = x + w + 2
        end
        if not showChars and self.tab == "chars" then self:SelectTab("over") end
    end
    function f:SelectTab(key)
        self.tab = key
        local ac = C.accent
        for _, b in ipairs(self.tabBtns) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            if hasGlass() then glass(b, on and { ac[1], ac[2], ac[3], 0.15 } or { 1, 1, 1, 0 }, on and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0 }, 8) end
            self.panes[b.key]:SetShown(on)
        end
    end
    local over, profP, badgeP, chronP, charsP = f.panes.over, f.panes.prof, f.panes.badge, f.panes.chron, f.panes.chars

    -- Charaktere: Main oben, Twinks eingerueckt an einer feinen Baumlinie
    f.treeRows = {}
    f.treeLine = charsP:CreateTexture(nil, "ARTWORK")
    f.treeLine:SetColorTexture(1, 1, 1, 0.14)
    f.treeLine:SetWidth(1)
    for i = 1, 8 do
        local r = CreateFrame("Button", nil, charsP)
        r:SetHeight(38)
        glass(r, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 10)
        if not hasGlass() then r.bg = K.Fill(r, C.panel) K.Border(r, C.line) end
        r.branch = charsP:CreateTexture(nil, "ARTWORK")
        r.branch:SetColorTexture(1, 1, 1, 0.14)
        r.branch:SetHeight(1)
        r.branch:SetWidth(10)
        r.branch:SetPoint("RIGHT", r, "LEFT", 0, 0)
        r.avDisc = r:CreateTexture(nil, "ARTWORK", nil, 0)
        r.avDisc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        r.avDisc:SetSize(26, 26)
        r.avDisc:SetPoint("LEFT", 8, 0)
        r.av = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.av:SetSize(26, 26)
        r.av:SetPoint("CENTER", r.avDisc)
        if r.av.SetMask then pcall(r.av.SetMask, r.av, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
        K.MaskSafe(r.av)
        r.dot = r:CreateTexture(nil, "OVERLAY")
        r.dot:SetTexture(ns.MEDIA .. "dot")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("CENTER", r.avDisc, "BOTTOMRIGHT", -2, 2)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("TOPLEFT", 42, -5)
        r.name:SetWordWrap(false)
        r.pill = CreateFrame("Frame", nil, r)
        r.pill:SetHeight(15)
        r.pill:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
        r.pill.t = K.Text(r.pill, 10, C.text, "CENTER")
        r.pill.t:SetPoint("CENTER", 0, 0)
        r.sub = K.Text(r, 10, C.muted)
        r.sub:SetPoint("TOPLEFT", 42, -21)
        r.sub:SetWordWrap(false)
        r.profs = K.Text(r, 11, C.text, "RIGHT")
        r.profs:SetPoint("RIGHT", -10, 0)
        r.profs:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            glass(self, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.16 })
            if not self.who then return end
            local GT = GameTooltip
            GT:SetOwner(self, "ANCHOR_RIGHT")
            GT:SetText(ns.colorName(self.who, self.cls), 1, 1, 1)
            GT:AddLine(self.subText or "", 0.75, 0.75, 0.78)
            local pfs = ns.Radar.decodeProfs(self.raw)
            if #pfs > 0 then
                GT:AddLine(" ")
                for _, pf in ipairs(pfs) do
                    local hasMax = pf.max and pf.max > 0
                    local maxed = hasMax and pf.rank >= pf.max
                    GT:AddDoubleLine(ns.Radar.ProfIcon(pf, 13, maxed and C.amber or C.text) .. " " .. pf.name,
                        (maxed and "|cffe8b44a" or "") .. pf.rank .. (maxed and "|r" or "") .. (hasMax and (" |cff777777/ " .. pf.max .. "|r") or ""),
                        0.9, 0.9, 0.9, 0.9, 0.9, 0.9)
                end
            else
                GT:AddLine(L["Keine Berufe bekannt."], 0.5, 0.5, 0.5)
            end
            if self.who ~= f.who then
                GT:AddLine(" ")
                GT:AddLine(L["Klick: Profilkarte oeffnen"], 0.53, 0.53, 0.53)
            end
            GT:Show()
        end)
        r:SetScript("OnLeave", function(self) glass(self, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }) GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self) if self.who and self.who ~= f.who then Profile.Show(self.who) end end)
        f.treeRows[i] = r
    end
    f.treeMore = K.Text(charsP, 11, C.dim)

    -- Uebersicht: Kennzahlen, Rollen, Charaktere/Notiz/Beute
    f.tiles = {}
    local ktw = (W - 36 - 16) / 3
    for i, lab in ipairs({ "Gegenstandsstufe", "Legacy", "Abzeichen" }) do
        local t = CreateFrame("Button", nil, over)
        t:SetSize(ktw, 54)
        t:SetPoint("TOPLEFT", 18 + (i - 1) * (ktw + 8), 0)
        if hasGlass() then glass(t, nil, nil, 11) else t.bg = K.Fill(t, C.panel) K.Border(t, C.line) end
        t.hov = t:CreateTexture(nil, "BORDER", nil, 3)
        t.hov:SetAllPoints()
        t.hov:SetColorTexture(1, 1, 1, 0.04)
        round(t.hov, t, 11)
        t.hov:Hide()
        t.value = K.Title(t, 20, C.text, "CENTER")
        t.value:SetPoint("TOP", 0, -9)
        t.label = K.Text(t, 10, C.muted, "CENTER")
        t.label:SetPoint("BOTTOM", 0, 8)
        t.label:SetPoint("LEFT", 6, 0) t.label:SetPoint("RIGHT", -6, 0)
        t.label:SetWordWrap(false)
        t.label:SetText(L[i == 1 and "Gegenstandsstufe" or lab])
        t:SetScript("OnEnter", function(self) self.hov:Show() if self.tip then K.ShowTip(self, self.tip) end end)
        t:SetScript("OnLeave", function(self) self.hov:Hide() GameTooltip:Hide() end)
        f.tiles[i] = t
    end
    f.tiles[1].tip = { L["Gegenstandsstufe"], "|cff888888" .. L["Schnitt der angelegten Ausruestung (per Oasis geteilt)"] .. "|r" }
    f.tiles[2].tip = { L["Legacy"], "|cff888888" .. L["Klick: Legacy-Seite"] .. "|r" }
    f.tiles[2]:SetScript("OnClick", function() ns.ShowPage("legacy") end)
    f.tiles[3].tip = { L["Abzeichen"], "|cff888888" .. L["Klick: Abzeichen ansehen"] .. "|r" }
    f.tiles[3]:SetScript("OnClick", function() f:SelectTab("badge") end)

    label(over, L["Rollen"], -70)
    f.roleHint = K.Text(over, 10, C.dim, "RIGHT")
    f.roleHint:SetPoint("TOPRIGHT", -18, -70)
    f.chips = Profile.RoleChips(over, W - 36, function() return f.who end)
    f.chips:SetPoint("TOPLEFT", 18, -86)
    if hasGlass() then
        for _, b in ipairs(f.chips.chips) do glass(b, nil, nil, 10) end
        local refresh = f.chips.Refresh
        function f.chips:Refresh(...)
            refresh(self, ...)
            local r, known = Profile.RolesOf(f.who)
            for _, b in ipairs(self.chips) do
                local c = Profile.ROLE_COLORS[b.role]
                local on = known and r[b.role]
                glass(b, on and { c[1], c[2], c[3], 0.14 } or { 1, 1, 1, 0.03 }, on and { c[1], c[2], c[3], 0.55 } or { 1, 1, 1, 0.08 })
            end
        end
    end
    -- ruhige Info-Zeilen (Glasflaeche)
    f.info = CreateFrame("Frame", nil, over)
    f.info:SetPoint("TOPLEFT", 16, -126)
    f.info:SetPoint("RIGHT", over, "RIGHT", -16, 0)
    f.info:SetHeight(96)
    glass(f.info, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.07 }, 10)
    local function infoRow(y, lab)
        local l = K.Text(f.info, 11, C.muted)
        l:SetPoint("TOPLEFT", 12, y)
        l:SetText(lab)
        local v = K.Text(f.info, 12, C.text)
        v:SetPoint("TOPLEFT", 96, y)
        v:SetPoint("RIGHT", f.info, "RIGHT", -12, 0)
        v:SetWordWrap(false)
        return v
    end
    f.vChars = infoRow(-12, L["Charaktere"])
    f.vNote = infoRow(-40, L["Notiz"])
    f.vLoot = infoRow(-68, L["Beute"])
    f.charHit = CreateFrame("Frame", nil, f.info)
    f.charHit:SetPoint("TOPLEFT", 6, -6)
    f.charHit:SetPoint("RIGHT", -6, 0)
    f.charHit:SetHeight(24)
    f.charHit:EnableMouse(true)
    f.charHit:SetScript("OnEnter", function(self) if f.charLines then K.ShowTip(self, f.charLines) end end)
    f.charHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.lootHit = CreateFrame("Frame", nil, f.info)
    f.lootHit:SetPoint("TOPLEFT", 6, -62)
    f.lootHit:SetPoint("RIGHT", -6, 0)
    f.lootHit:SetHeight(24)
    f.lootHit:EnableMouse(true)
    f.lootHit:SetScript("OnEnter", function(self)
        if f.who and ns.LootMaster and ns.LootMaster.StatsTip then K.ShowTip(self, ns.LootMaster.StatsTip({ L["Beute"] }, f.who)) end
    end)
    f.lootHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.noteHit = CreateFrame("Frame", nil, f.info)
    f.noteHit:SetPoint("TOPLEFT", 6, -34)
    f.noteHit:SetPoint("RIGHT", -6, 0)
    f.noteHit:SetHeight(24)
    f.noteHit:EnableMouse(true)
    f.noteHit:SetScript("OnEnter", function(self) if f.noteFull and f.noteFull ~= "" then K.ShowTip(self, { L["Notiz"], f.noteFull }) end end)
    f.noteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Berufe: Zeilen mit Symbol, runder Leiste, Tooltip (Rezepte), Klick -> Handwerks-Boerse
    f.profRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, profP)
        r:SetSize(W - 32, 36)
        r:SetPoint("TOPLEFT", 16, -(i - 1) * 40)
        glass(r, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 10)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 12, 0)
        r.name:SetWidth(150)
        r.name:SetWordWrap(false)
        r.bar = K.Bar(r, 110, 5)
        r.bar:SetPoint("LEFT", 170, 0)
        round(r.bar.fill, r.bar, 2)
        r.val = K.Text(r, 11, C.muted, "RIGHT")
        r.val:SetPoint("RIGHT", -12, 0)
        r:SetScript("OnEnter", function(self)
            glass(self, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.16 })
            if self.raw and ns.Radar.ProfTip then
                ns.Radar.ProfTip(self, f.who, self.raw)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Klick: in der Handwerks-Boerse suchen"], 0.53, 0.53, 0.53)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self) glass(self, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }) GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            if self.prof and ns.Crafting and ns.Crafting.ShowItem and ns.PageDef("crafting") then ns.Crafting.ShowItem(self.prof) end
        end)
        f.profRows[i] = r
    end
    f.noProfs = K.Text(profP, 12, C.dim)
    f.noProfs:SetPoint("TOPLEFT", 18, -4)
    f.noProfs:SetText(L["Keine Berufe bekannt."])

    -- Abzeichen: Raster mit Tooltip, Klick -> Abzeichen-Seite
    f.emblems = {}
    for i = 1, 32 do
        local e = ns.Badges.Emblem(badgeP, 34)
        e:SetPoint("TOPLEFT", 18 + ((i - 1) % 8) * 43, -((math.floor((i - 1) / 8)) * 43))
        e:EnableMouse(true)
        e:SetScript("OnEnter", function(self)
            if self.b then K.ShowTip(self, { ns.Badges.Label(self.b.id, self.tier), L[self.b.desc], " ", "|cff888888" .. L["Klick: Abzeichen-Seite"] .. "|r" }) end
        end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        e:SetScript("OnMouseUp", function() ns.ShowPage("badges") end)
        f.emblems[i] = e
    end
    f.noBadges = K.Text(badgeP, 12, C.dim)
    f.noBadges:SetPoint("TOPLEFT", 18, -4)
    f.noBadges:SetText(L["Noch keine Abzeichen."])
    f.moreBadges = K.Text(badgeP, 11, C.dim)
    f.moreBadges:SetPoint("TOPLEFT", 18, -4 * 43 - 2)

    -- Chronik: vollstaendig, scrollbar
    f.chronList = K.List(chronP, 34, function(l)
        local r = K.Row(l)
        if r.stripe then r.stripe:Hide() end
        r.hl:SetColorTexture(1, 1, 1, 0.04)
        round(r.hl, r, 8)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetTexture(ns.MEDIA .. "dot")
        r.dot:SetSize(7, 7)
        r.dot:SetPoint("LEFT", 8, 0)
        r.when = K.Text(r, 10, C.dim)
        r.when:SetPoint("TOPLEFT", 22, -4)
        r.text = K.Text(r, 11, C.text)
        r.text:SetPoint("TOPLEFT", 22, -17)
        r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            if self.item then K.ShowTip(self, { self.item.when, self.item.full }) end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function() ns.ShowPage("chronicle") end)
        return r
    end, function(r, x)
        r.when:SetText(x.when)
        r.text:SetText(x.text)
        local c = x.first and C.accent or C.muted
        r.dot:SetVertexColor(c[1], c[2], c[3], x.first and 0.9 or 0.6)
    end)
    f.chronList:SetPoint("TOPLEFT", 12, 0)
    f.chronList:SetPoint("BOTTOMRIGHT", -12, 4)
    f.chronList.empty:SetText(L["Noch nichts passiert."])
    f.recent = K.Text(chronP, 11, C.text)   -- Kompatibilitaet (unsichtbar)
    f.recent:Hide()

    f:SelectTab("over")
    card = f
    return f
end

-- Einheit zu einem Gildenmitglied (fuer das echte Modell): ich, Ziel, Maus, Gruppe/Schlachtzug
local function unitFor(name)
    if ns.isMe(name) then return "player" end
    local want = ns.Radar.byName[name]
    local units = { "target", "mouseover", "focus" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    if IsInRaid() then for i = 1, 40 do units[#units + 1] = "raid" .. i end end
    for _, u in ipairs(units) do
        local n = UnitExists and UnitExists(u) and (not UnitIsPlayer or UnitIsPlayer(u)) and ns.safe(ns.UnitName(u))
        if n then
            local full = ns.fullName(n)
            if full == name or (want and ns.Radar.byName[full] == want) then return u end
        end
    end
end
local function hasModel(m)
    local ok, id = pcall(m.GetModelFileID, m)
    return ok and id and id ~= 0
end
local function showHead(f, name, p, classFile)
    if f.head.disc then
        -- Glas: maskierte Textur NUR fuer das echte Portrait (SetTexCoord ist bei Masken verboten),
        -- Klassensymbol/Fragezeichen in eigener, unmaskierter Textur
        if not f.headCls then
            f.headCls = f.head:CreateTexture(nil, "ARTWORK", nil, 1)
            f.headCls:SetPoint("CENTER")
            f.headCls:SetSize(34, 34)
        end
        local unit = unitFor(name)
        local ok = false
        -- echtes Portrait nur, wenn WoW die Person gerade "sieht" (sonst liefert es eine leere braune Scheibe)
        local visible = unit and (not UnitIsVisible or ns.safe(UnitIsVisible(unit)))
        if visible and SetPortraitTexture then ok = pcall(SetPortraitTexture, f.headIcon, unit) and f.headIcon:GetTexture() ~= nil end
        f.headIcon:SetShown(ok and true or false)
        f.headCls:SetShown(not ok)
        if not ok then
            -- sonst einfach das Klassensymbol
            f.headCls:SetSize(34, 34)
            local GI = ns.GuildInfo
            local okC = classFile and GI and GI.SetClassIcon and GI.SetClassIcon(f.headCls, classFile)
            if not okC then
                f.headCls:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                f.headCls:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
        f.model:Hide()
        local cr, cg, cb = ns.classColor(classFile)
        f.head.ring:SetVertexColor(cr, cg, cb, 0.85)
        return
    end
    local m = f.model
    pcall(m.ClearModel, m)
    local unit = unitFor(name)
    local shown = false
    if unit then
        shown = pcall(m.SetUnit, m, unit)
    elseif p and tonumber(p.rc) and tonumber(p.rc) > 0 and m.SetCustomRace then
        shown = pcall(m.SetCustomRace, m, tonumber(p.rc), tonumber(p.sx) or 0)
    end
    m:SetShown(shown)
    f.headIcon:SetShown(not shown)
    if shown then
        pcall(m.SetPortraitZoom, m, 1)
        pcall(m.SetFacing, m, 0.25)
        -- klappt das Modell nicht, Klassensymbol zeigen
        ns.After(0.3, function()
            if f.who == name and not hasModel(m) then m:Hide() f.headIcon:Show() end
        end)
    end
    local tc = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if tc then
        f.headIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        f.headIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        f.headIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local cr, cg, cb = ns.classColor(classFile)
    K.SetBorderColor(f.head, { cr, cg, cb, 0.8 })
end

-- Name, den WoW fuer Fluestern/Einladen versteht (Forever: nur der Vorname)
local function chatName(name)
    return ns.ChatName(name)
end

-- Reiter "Charaktere": Baum Main -> Twinks
function Profile.FillTree(f, name, R)
    local A = ns.Alts
    local main, alts, info
    if A and A.Tree then main, alts, info = A.Tree(name) else main, alts, info = name, {}, {} end
    local list = { main }
    for _, c in ipairs(alts) do list[#list + 1] = c end
    f.treeCount = #list
    f:LayoutTabs(#list > 1)
    local GI = ns.GuildInfo
    local rows = f.treeRows
    local INDENT = 30
    local y, lastY = 0, nil
    for i, r in ipairs(rows) do
        local c = list[i]
        if c and #list > 1 then
            local it = info[c] or (A and A.CharInfo and A.CharInfo(c)) or {}
            local isMain = i == 1
            r.who, r.cls, r.raw = c, it.class, it.profs
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", f.panes.chars, "TOPLEFT", 16 + (isMain and 0 or INDENT), -y)
            r:SetPoint("RIGHT", f.panes.chars, "RIGHT", -16, 0)
            r.branch:SetShown(not isMain)
            if not isMain then lastY = y + 19 end
            -- Avatar
            local ok = it.class and GI and GI.SetClassIcon and GI.SetClassIcon(r.av, it.class)
            r.av:SetShown(ok and true or false)
            local cr, cg, cb = ns.classColor(it.class)
            r.avDisc:SetVertexColor(ok and 0 or cr * 0.35, ok and 0 or cg * 0.35, ok and 0 or cb * 0.35, ok and 0.4 or 1)
            r.av:SetDesaturated(not it.online)
            local dc = it.online and C.mint or C.dim
            r.dot:SetVertexColor(dc[1], dc[2], dc[3])
            r.dot:SetAlpha(it.online and 1 or 0.6)
            -- Name + Pille
            r.name:SetText(ns.colorName(c, it.class))
            local nw = math.min(r.name:GetStringWidth() or 80, 150)
            r.name:SetWidth(nw + 2)
            local pc = isMain and C.amber or C.muted
            r.pill.t:SetText(isMain and L["Main"] or L["Twink"])
            r.pill.t:SetTextColor(pc[1], pc[2], pc[3])
            r.pill:SetWidth((r.pill.t:GetStringWidth() or 28) + 12)
            glass(r.pill, { pc[1], pc[2], pc[3], 0.12 }, { pc[1], pc[2], pc[3], 0.40 }, 7)
            -- "Lvl 30 Schurke"
            local cls = (LOCALIZED_CLASS_NAMES_MALE and it.class and LOCALIZED_CLASS_NAMES_MALE[it.class]) or ""
            r.subText = (L["Lvl %s %s"]):format(it.level or "?", cls):gsub("%s+$", "")
            if c == f.who then r.subText = r.subText .. "  |cff888888·  " .. L["diese Karte"] .. "|r" end
            if Profile.OutsideGuild(c) then r.subText = r.subText .. "  |cff666666·  " .. L["nicht in der Gilde"] .. "|r" end
            r.sub:SetText(r.subText)
            -- Berufe: Haupt- und Sammelberufe, Symbol + Stufe (Hoechststufe gold)
            local pt = R.ProfIcons(it.profs, 13, 4)
            r.profs:SetText(pt ~= "" and pt or "|cff555555-|r")
            r:SetAlpha(it.online and 1 or 0.8)
            r:Show()
            y = y + 42
        else
            r.who = nil
            r:Hide()
            r.branch:Hide()
        end
    end
    -- senkrechte Baumlinie vom Main bis zum letzten Twink
    if #list > 1 and lastY then
        f.treeLine:ClearAllPoints()
        f.treeLine:SetPoint("TOPLEFT", f.panes.chars, "TOPLEFT", 16 + 20, -38)
        f.treeLine:SetHeight(math.max(1, lastY - 38))
        f.treeLine:Show()
    else
        f.treeLine:Hide()
    end
    local more = #list - #rows
    f.treeMore:ClearAllPoints()
    f.treeMore:SetPoint("TOPLEFT", f.panes.chars, "TOPLEFT", 18 + INDENT, -y - 2)
    f.treeMore:SetText(more > 0 and ("|cff888888" .. (L["+ %d weitere"]):format(more) .. "|r") or "")
end

function Profile.Show(name)
    if not name then return end
    local f = card or build()
    f.who = name
    local R = ns.Radar
    local m = R.byName[name]
    local me = ns.isMe(name)
    local p = me and R.myProfile() or ns.db.members[name]
    local classFile = R.ClassOf(name)
    local cr, cg, cb = ns.classColor(classFile)
    f.stripe:SetColorTexture(cr, cg, cb, 1)
    if not (CreateColor and pcall(f.glow.SetGradient, f.glow, "VERTICAL", CreateColor(cr, cg, cb, 0), CreateColor(cr, cg, cb, 0.10))) then
        f.glow:SetColorTexture(cr, cg, cb, 0.05)
    end
    f.name:SetText(ns.colorName(name, classFile))
    showHead(f, name, p, classFile)
    local lvl = (m and m.level) or (p and p.lvl) or "?"
    local cls = (LOCALIZED_CLASS_NAMES_MALE and classFile and LOCALIZED_CLASS_NAMES_MALE[classFile]) or ""
    local parts = { (L["Level %s"]):format(lvl) }
    if cls ~= "" then parts[#parts + 1] = cls end
    if m and m.rank ~= "" then parts[#parts + 1] = m.rank end
    local orl, verified = nil, true
    if ns.Rank then orl, verified = ns.Rank.Of(name) end
    if orl then
        local st = ns.Rank.Frame(orl)
        parts[#parts + 1] = K.hex(st.color) .. (L["Rang %d"]):format(orl) .. "  " .. ns.Rank.Title(orl) .. "|r" .. (verified and "" or (" |cffe69a4a(" .. L["ungeprueft"] .. ")|r"))
        local key = st.name .. (K.RingTier and K.RingTier(orl) or "")
        if f.rframe.styleName ~= key then f.rframe:SetStyle(st, orl) f.rframe.styleName = key end
        f.rframe:Show()
        if f.remb then f.remb:SetRank(orl) f.remb:SetShown(not (f.rframe.art and f.rframe.art:IsShown())) end
        if f.head.ring then f.head.ring:SetShown(not (f.rframe.art and f.rframe.art:IsShown())) end
    else
        f.rframe:Hide()
        if f.remb then f.remb:Hide() end
        if f.head.ring then f.head.ring:Show() end
    end
    f.sub:SetText(table.concat(parts, "  ·  "))
    if hasGlass() then
        local tags = { { text = (L["Level %s"]):format(lvl) } }
        if cls ~= "" then tags[#tags + 1] = { text = ns.colorName(cls, classFile), color = { cr, cg, cb } } end
        if m and m.rank ~= "" then tags[#tags + 1] = { text = m.rank } end
        if orl then
            local st = ns.Rank.Frame(orl)
            tags[#tags + 1] = { text = K.hex(st.color) .. (L["Rang %d"]):format(orl) .. "  " .. ns.Rank.Title(orl) .. "|r" .. (verified and "" or (" |cffe69a4a(" .. L["ungeprueft"] .. ")|r")), color = st.color }
        end
        local onl = ns.isMe(name) or (m and m.online)
        local zn = m and m.zone ~= "" and m.zone or nil
        tags[#tags + 1] = onl and { text = L["Online"] .. (zn and ("  ·  " .. zn) or ""), color = C.mint, dot = C.mint } or { text = L["Offline"], dot = C.dim }
        f.tagBottom = f:SetTags(tags)
    end
    local online = me or (m and m.online)
    local zone = m and m.zone ~= "" and m.zone or nil
    local dc = online and C.mint or C.dim
    f.pill.dot:SetVertexColor(dc[1], dc[2], dc[3])
    f.pill.text:SetText(online and (L["Online"] .. (zone and ("  ·  " .. zone) or "")) or L["Offline"])
    f.pill:SetWidth(f.pill.text:GetStringWidth() + 28)
    local bioText = me and ns.db.settings.bio or (p and p.bi)
    f.bio:SetText((bioText and bioText ~= "") and ("|cffbbbbbb\226\128\158|r" .. bioText .. "|cffbbbbbb\226\128\156|r") or "")
    local hasOasis = me or p ~= nil
    f.oasis:SetShown(hasOasis)
    f.oasis:SetDesaturated(not (me or R.HasAddon(name)))

    -- Rollen
    f.chips:Refresh()
    local _, known = Profile.RolesOf(name)
    f.roleHint:SetText(me and L["Klick zum Aendern"] or (known and "" or L["nicht angegeben"]))

    -- Kennzahlen
    local ln = me and (ns.Legacy and ns.Legacy.myDoneCount() or 0) or (p and p.ln or 0)
    local list = {}
    for id, tier in pairs(ns.Badges.Of(name)) do
        local b = ns.Badges.byId[id]
        if b then list[#list + 1] = { b = b, tier = tier } end
    end
    f.tiles[1].value:SetText(p and (p.ilvl or 0) > 0 and p.ilvl or "-")
    f.tiles[2].value:SetText(ln or 0)
    f.tiles[3].value:SetText(#list)

    -- Abzeichen: zuerst die Vitrine (vom Spieler gewaehlt), dann hoechste zuerst
    local fav = {}
    if me then
        for i, id in pairs(ns.db.settings.badgeShowcase or {}) do fav[id] = i end
    elseif p and p.bf then
        local i = 0
        for id in tostring(p.bf):gmatch("[^,]+") do i = i + 1 fav[id] = i end
    end
    table.sort(list, function(a, b)
        local fa, fb = fav[a.b.id], fav[b.b.id]
        if fa or fb then
            if fa and fb then return fa < fb end
            return fa ~= nil
        end
        if a.tier ~= b.tier then return a.tier > b.tier end
        return a.b.id < b.b.id
    end)
    for i, e in ipairs(f.emblems) do
        local it = list[i]
        if it then
            e.b, e.tier = it.b, it.tier
            e:Set(it.b, it.tier)
            e:Show()
        else
            e:Hide()
        end
    end
    f.noBadges:SetShown(#list == 0)
    f.moreBadges:SetText(#list > #f.emblems and ("|cff888888" .. (L["+ %d weitere"]):format(#list - #f.emblems) .. "|r") or "")

    -- Berufe (eigene aus dem Profil, sonst Blizzard-Gildenberufe)
    local raw = p and p.profs or (ns.db.guildProfs and ns.db.guildProfs[name])
    local profs = R.decodeProfs(raw)
    for i, r in ipairs(f.profRows) do
        local pf = profs[i]
        if pf then
            local hasMax = pf.max and pf.max > 0
            local maxed = hasMax and pf.rank >= pf.max
            r.name:SetText(R.ProfIcon(pf, 14, maxed and C.amber or C.text) .. "  " .. pf.name)
            r.bar:Set(hasMax and pf.rank / pf.max or 0)
            if hasGlass() then
                -- neutral, Gold bei Hoechststufe
                if maxed then r.bar.fill:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.9)
                else r.bar.fill:SetColorTexture(0.72, 0.75, 0.82, 0.75) end
            end
            r.bar:SetShown(hasMax)
            r.raw, r.prof = raw, pf.name
            r.val:SetText((maxed and "|cffe8b44a" or "|cffe6e6e6") .. pf.rank .. "|r" .. (hasMax and (" |cff777777/ " .. pf.max .. "|r") or ""))
            r:Show()
        else
            r:Hide()
        end
    end
    f.noProfs:SetShown(#profs == 0)

    -- Charaktere (Main + Twinks); Twinks ausserhalb der Gilde gekennzeichnet (sie tragen nichts zur Gilde bei)
    local main = ns.Alts and ns.Alts.Main(name) or name
    local chars = ns.Alts and ns.Alts.CharsOf(main) or { name }
    local t = {}
    for _, c in ipairs(chars) do
        local cm = R.byName[c]
        local lv = cm and cm.level or (ns.db.members[c] and ns.db.members[c].lvl)
        t[#t + 1] = ns.colorName(c, R.ClassOf(c)) .. (lv and (" |cff888888" .. lv .. "|r") or "") .. (c == main and #chars > 1 and (" |cffff1200" .. L["Main"] .. "|r") or "")
            .. (Profile.OutsideGuild(c) and (" |cff666666(" .. L["nicht in der Gilde"] .. ")|r") or "")
    end
    f.vChars:SetText(table.concat(t, ",  "))
    Profile.FillTree(f, name, R)
    f.charLines = { L["Charaktere"] }
    for _, s in ipairs(t) do f.charLines[#f.charLines + 1] = s end
    f.vNote:SetText(m and m.note ~= "" and m.note or "|cff666666-|r")
    f.noteFull = m and m.note or ""
    if ns.LootMaster and ns.LootMaster.Stats then
        local st = ns.LootMaster.Stats(name)
        f.vLoot:SetText(st.total > 0 and ((L["%d Items  ·  %d in 30 Tagen"]):format(st.total, st.d30) .. (st.last and ("  ·  " .. st.last) or "")) or "|cff666666-|r")
    else
        f.vLoot:SetText("|cff666666-|r")
    end

    -- Chronik aller Charaktere dieses Spielers
    local set = {}
    for _, c in ipairs(chars) do set[c] = true end
    local entries = Store.List("chronicle", function(e) return set[e.who] or (R.byName[e.who] and set[R.byName[e.who].name]) end)
    table.sort(entries, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    local rows = {}
    for i, e in ipairs(entries) do
        local item = ns.Chronicle and ns.Chronicle.Item(e)
        local txt = (ns.Chronicle and ns.Chronicle.Text(e) or "") .. (item and (" " .. item) or "")
        rows[#rows + 1] = { when = ns.ago(e.ts) .. "  ·  " .. date("%d.%m. %H:%M", e.ts or 0), text = txt, full = txt, first = i == 1 }
    end
    f.chronList:SetData(rows)

    f.whisper:SetEnabledState(not me)
    f.invite:SetEnabledState(not me and online and true or false)
    f.duel:SetEnabledState(not me and online and true or false)
    f.whisper:SetScript("OnClick", function() ns.Whisper(name) end)
    f.invite:SetScript("OnClick", function() if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, chatName(name)) end end)
    f.duel:SetScript("OnClick", function() if ns.Deathroll then ns.Deathroll.Challenge(name, 100, "", false) end end)
    local whyOff = me and L["Das bist du"] or L["Nur wenn online"]
    f.whisper.why, f.invite.why, f.duel.why = me and L["Das bist du"] or nil, whyOff, whyOff
    f.duel.avail = ns.Deathroll ~= nil
    -- Auf der Karte zeigen (nur online und wenn die Position bekannt ist)
    f.mapBtn.avail = ns.Map and ns.Map.ShowMember and true or false
    f.mapBtn:SetEnabledState(online and true or false)
    f.mapBtn.why = L["Nur wenn online"]
    f.mapBtn:SetScript("OnClick", function()
        if not ns.Map.ShowMember(name, zone) then K.Toast(L["Position unbekannt"], ns.displayName(name), C.dim) end
    end)
    -- Offiziersnotiz bearbeiten (nur mit Recht und echtem Gildeneintrag)
    local canNote = ns.Members and ns.Members.CanEditOfficerNote and ns.Members.CanEditOfficerNote() and m and m.index and not m.demo
    f.noteBtn.avail = canNote and true or false
    f.noteBtn:SetEnabledState(true)
    f.noteBtn:SetScript("OnClick", function() ns.Members.EditOfficerNote(m) end)
    -- im Gildenchat erwaehnen
    f.chatBtn.avail = (ChatFrame_OpenChat ~= nil) and not me
    f.chatBtn:SetEnabledState(true)
    f.chatBtn:SetScript("OnClick", function() ChatFrame_OpenChat("/g " .. chatName(name) .. " ") end)
    f:LayoutActions()
    -- Reiter-Beschriftungen mit Anzahl
    for _, b in ipairs(f.tabBtns) do
        local n = b.key == "chars" and f.treeCount or b.key == "prof" and #profs or b.key == "badge" and #list or b.key == "chron" and #entries or nil
        b.label:SetText(b.count .. ((n and n > 0) and ("  |cff888888" .. n .. "|r") or ""))
    end
    f:LayoutTabs(f.showChars)   -- Breiten nach den Texten mit Zaehlern neu verteilen
    if f.lastWho ~= name then f.lastWho = name f:SelectTab("over") end
    f:Show()
end
ns.Listen("ROLES_CHANGED", function() if card and card:IsShown() and card.who then Profile.Show(card.who) end end)
-- Main/Twink geaendert (eigene Wahl oder geteiltes Profil): offene Karte nachziehen, gebuendelt
local altsSoon
ns.Listen("ALTS", function()
    if altsSoon or not (card and card:IsShown()) then return end
    altsSoon = true
    ns.After(0.5, function() altsSoon = false if card and card:IsShown() and card.who then Profile.Show(card.who) end end)
end)

ns.slash.profil = function(rest)
    local n = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if n == "" then n = ns.safe(ns.UnitName("target")) or ns.short(ns.me()) end
    Profile.Show(ns.fullName(n))
end
ns.slash.profile = ns.slash.profil

-- Oasis: "Neue Version - wie moechtest du starten?"
-- Beim ersten Einloggen bzw. /reload nach einem Versionswechsel fragt Oasis einmal:
--   Wie bisher | Alles an | Nur das Noetigste | Schwerpunkt (Leveln, Zusammen spielen, Raiden ...) | eigenes Profil
-- Ganz neue Nutzer bekommen weiter den Rundgang/die Interessen-Auswahl (nicht dieses Fenster).
-- "Nicht mehr fragen": settings.updateAsk = false
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local U = {}
ns.UpdateStart = U
local function S() return ns.db.settings end

local win
local function done(text)
    S().startVersion = ns.version
    if win then win:Hide() end
    if text then K.Toast(L["Oasis is ready"], text, C.mint) end
end
local function relayout()
    if ns.LayoutNav then pcall(ns.LayoutNav) end
    if ns.UpdateMiniBar then pcall(ns.UpdateMiniBar) end
end
-- alles einschalten: auch die vom "Noetigsten"/Schwerpunkt ausgeblendeten Bereiche
function U.AllOn()
    local s = S()
    s.hiddenPages, s.focusHidden, s.simpleHidden, s.simpleMode = {}, nil, nil, nil
    if ns.Discover and ns.Discover.Calm and s.calmStart then pcall(ns.Discover.Calm, false) end
    relayout()
end
function U.Minimal()
    U.AllOn()
    if ns.Onboarding and ns.Onboarding.Simple then pcall(ns.Onboarding.Simple) end
    relayout()
end
function U.Focus(key)
    U.AllOn()
    if ns.Discover and ns.Discover.ApplyInterests then pcall(ns.Discover.ApplyInterests, { [key] = true }) end
end

-- style: nil = normal, "primary" = Hauptweg (volle Akzentflaeche), "quiet" = untergeordnet (grau, flach)
local function card(parent, w, h, icon, title, sub, color, onClick, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local primary, quiet = style == "primary", style == "quiet"
    local textC = primary and { 1, 1, 1 } or (quiet and C.muted or C.text)
    if primary then
        b.bg = K.Fill(b, C.accent, 0.92)
        K.Border(b, C.accent)
    else
        b.bg = K.Fill(b, C.panel)
        if K.ApplySkin then K.ApplySkin(b, "panel", C.panel) else K.Border(b, C.line) end
    end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    if primary then b.hl:SetColorTexture(1, 1, 1, 0.08) else b.hl:SetColorTexture(color[1], color[2], color[3], 0.08) end
    local iconC = primary and { 1, 1, 1 } or (quiet and C.dim or color)
    b.icon = K.Glyph(b, primary and 22 or (quiet and 14 or 18), (ns.ICONS and ns.ICONS[icon]) or (ns.MEDIA .. "icons\\" .. icon), iconC)
    b.icon:SetPoint("TOPLEFT", primary and 16 or 12, primary and -16 or (quiet and -10 or -12))
    b.t = K.Title(b, primary and 16 or (quiet and 12 or 13), textC)
    b.t:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.t:SetPoint("RIGHT", -8, 0)
    b.t:SetWordWrap(false)
    b.t:SetText(title)
    b.s = K.Text(b, primary and 12 or 10, primary and { 1, 1, 1 } or C.dim)
    if primary then b.s:SetAlpha(0.85) end
    b.s:SetPoint("TOPLEFT", primary and 16 or 12, primary and -46 or (quiet and -30 or -38))
    b.s:SetPoint("RIGHT", -10, 0)
    b.s:SetWordWrap(true)
    b.s:SetJustifyV("TOP")
    b.s:SetText(sub or "")
    b:SetScript("OnClick", onClick)
    if not primary then
        b:SetScript("OnEnter", function(self) self.t:SetTextColor(color[1], color[2], color[3]); self.icon:SetVertexColor(color[1], color[2], color[3]) end)
        b:SetScript("OnLeave", function(self) self.t:SetTextColor(textC[1], textC[2], textC[3]); self.icon:SetVertexColor(iconC[1], iconC[2], iconC[3]) end)
    end
    return b
end

local function build()
    local f = CreateFrame("Frame", "OasisUpdateStart", UIParent)
    f:SetSize(600, 500)
    f:SetPoint("CENTER", 0, 40)
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
    -- Esc / X = wie bisher
    ns.EscClose("OasisUpdateStart")
    f:HookScript("OnHide", function() if S().startVersion ~= ns.version then S().startVersion = ns.version end end)
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetTexture(ns.MEDIA .. "logo64")
    f.logo:SetSize(36, 36)
    f.logo:SetPoint("TOPLEFT", 18, -16)
    f.title = K.Title(f, 18, C.text)
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 12, -1)
    f.sub = K.Text(f, 12, C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.sub:SetText(L["How do you want to start? You can change everything later in the settings."])
    local close = K.CloseButton(f, function() f:Hide() end, L["Keep as is"])
    close:SetPoint("TOPRIGHT", -8, -8)

    -- Hauptweg: Wie bisher (gross, Akzentfarbe) - alles andere klein darunter
    local W3 = (600 - 36 - 16) / 3
    local y = -74
    local c1 = card(f, 564, 84, "checklist", L["Keep as is"],
        L["Your settings, game aids and areas stay exactly the same. New things are only added."], C.accent,
        function() done(L["Everything as before."]) end, "primary")
    c1:SetPoint("TOPLEFT", 18, y)
    c1.rec = K.Text(c1, 11, { 1, 1, 1 })
    c1.rec:SetPoint("TOPRIGHT", -16, -18)
    c1.rec:SetText(L["Recommended"])
    c1.rec:SetAlpha(0.75)

    local h0 = K.Text(f, 11, C.dim)
    h0:SetPoint("TOPLEFT", 20, y - 104)
    h0:SetText(K.Upper and K.Upper(L["Or choose areas again"]) or L["Or choose areas again"])
    local W2 = (564 - 8) / 2
    local c2 = card(f, W2, 50, "modules", L["Everything on"], L["Turn on all areas in the menu."], C.accent,
        function() U.AllOn() done(L["All areas are turned on."]) end, "quiet")
    c2:SetPoint("TOPLEFT", 18, y - 122)
    local c3 = card(f, W2, 50, "home", L["Essentials only"], L["Chat, members, groups, raids, crafting."], C.blue,
        function() U.Minimal() done(L["Only the most important areas are on."]) end, "quiet")
    c3:SetPoint("LEFT", c2, "RIGHT", 8, 0)

    local h = K.Text(f, 11, C.dim)
    h:SetPoint("TOPLEFT", 20, y - 190)
    h:SetText(K.Upper and K.Upper(L["Or by focus"]) or L["Or by focus"])
    local list = (ns.Discover and ns.Discover.INTERESTS) or {}
    for i, it in ipairs(list) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local c = card(f, W3, 50, it.icon or "home", L[it.text], L[it.sub], it.color or C.accent,
            function() U.Focus(it.key) done((L["Focus: %s"]):format(L[it.text])) end, "quiet")
        c:SetPoint("TOPLEFT", 18 + col * (W3 + 8), y - 208 - row * 58)
    end
    local note = K.Text(f, 10, C.dim)
    note:SetPoint("TOPLEFT", 20, y - 208 - 2 * 58 - 2)
    note:SetText(L["Settings and game aids are kept whatever you choose."])
    -- mehrere Schwerpunkte: das bekannte Interessen-Fenster
    f.multi = K.Button(f, L["Choose several focuses ..."], 200, 24, "ghost", function()
        done(nil)
        if ns.Discover and ns.Discover.ShowPicker then ns.Discover.ShowPicker() end
    end)
    f.multi:SetPoint("BOTTOMLEFT", 18, 52)
    -- eigenes gespeichertes Profil
    f.preset = K.Button(f, L["Load own profile ..."], 180, 24, "ghost", function(self)
        local items = {}
        for name in pairs(ns.db.presets or {}) do
            items[#items + 1] = { text = name, icon = ns.MEDIA .. "icons\\profile", fn = function()
                if ns.SettingsIO and ns.SettingsIO.LoadPreset and ns.SettingsIO.LoadPreset(name) then
                    done((L["Profile loaded: %s"]):format(name))
                end
            end }
        end
        table.sort(items, function(a, b) return a.text < b.text end)
        K.ShowMenu(self, items, L["Saved profiles"])
    end)
    f.preset.isDropdown = true
    f.preset:SetPoint("LEFT", f.multi, "RIGHT", 8, 0)
    -- nicht mehr fragen
    f.never = K.Toggle(f, L["Don't ask again on new versions"], function() return S().updateAsk == false end,
        function(v) if v then S().updateAsk = false else S().updateAsk = nil end end)   -- 0.6.125: liess sich nicht ausschalten
    f.never:SetPoint("BOTTOMLEFT", 14, 16)
    f.never:SetWidth(320)
    win = f
    return f
end

function U.Show()
    -- gleiche Oberflaeche wie die Interessen-Auswahl, mit "Wie bisher"/"Nur das Noetigste"
    S().startVersion = ns.version
    if ns.Discover and ns.Discover.ShowPicker then ns.Discover.ShowPicker("update") end
end
ns.slash.start = U.Show

-- einmal je Version (nach Login/Reload), nicht beim allerersten Start (dafuer gibt es Rundgang + Interessen)
ns.Listen("LOGIN", function()
    local s = S()
    if s.startVersion == ns.version then return end
    if s.startVersion == nil and not s.onboarded and not s.interestsDone then
        s.startVersion = ns.version     -- ganz neu: Rundgang/Interessen uebernehmen das
        return
    end
    if s.updateAsk == false then s.startVersion = ns.version return end
    ns.After(6, function()
        if ns.inCombat() then return end
        U.Show()
    end)
end)

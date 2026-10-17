-- Oasis: Tastenkuerzel fuer das Fenster (0.5.565)
--  * stehen auch in WoWs Tastaturbelegung unter "Oasis" (Bindings.xml)
--  * Einstellungen > Allgemein > Tastenkuerzel: Knopf anklicken, Taste druecken - fertig
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local KB = {}
ns.Keybinds = KB

-- Reihenfolge = Anzeige; page = Seite direkt oeffnen (nochmal druecken schliesst)
KB.ACTIONS = {
    { cmd = "OASIS_TOGGLE", text = "Oasis oeffnen / schliessen", icon = "home" },
    { cmd = "OASIS_TOPBAR", text = "Topbar ein / aus", icon = "brush" },
    { cmd = "OASIS_SETTINGS", text = "Einstellungen", icon = "settings", page = "settings" },
    { cmd = "OASIS_EMOJI", text = "Emoji-Auswahl", icon = "smile" },
    { cmd = "OASIS_HOME", text = "Dashboard", icon = "home", page = "home" },
    { cmd = "OASIS_MEMBERS", text = "Mitglieder", icon = "social", page = "radar" },
    { cmd = "OASIS_CHAT", text = "Chat", icon = "announce", page = "chat" },
    { cmd = "OASIS_GROUPS", text = "Gruppen", icon = "groups", page = "groups" },
    { cmd = "OASIS_RAID", text = "Raids", icon = "raid", page = "raid" },
    { cmd = "OASIS_PROFILE", text = "Profil", icon = "profile", page = "insta" },
}
-- Namen fuer WoWs Tastaturbelegung (erst wenn alle Texte geladen sind - LocaleData481 steht in der toc dahinter)
local function names() for _, a in ipairs(KB.ACTIONS) do _G["BINDING_NAME_" .. a.cmd] = L[a.text] end end
names()
ns.Listen("DB_READY", names)

function KB.Run(cmd)
    if not ns.loggedIn then return end
    for _, a in ipairs(KB.ACTIONS) do
        if a.cmd == cmd then
            if cmd == "OASIS_TOGGLE" then
                ns.Fire("TOGGLE_MAIN")
            elseif cmd == "OASIS_TOPBAR" then
                if ns.db.settings.collapsed then ns.HideMiniBar(true) else ns.ShowMiniBar() end
            elseif cmd == "OASIS_EMOJI" then
                if ns.Emoji and ns.Emoji.TogglePicker then ns.Emoji.TogglePicker() end
            elseif a.page then
                local open = ns.MainShown and ns.MainShown() and ns.CurrentPage and ns.CurrentPage() == a.page
                if open then ns.HideMain() elseif ns.Expand then ns.Expand(a.page) else ns.ShowPage(a.page) end
            end
            return
        end
    end
end
-- aus Bindings.xml aufgerufen
function Oasis_KeyAction(cmd) local ok, e = pcall(KB.Run, cmd) if not ok and ns.err then ns.err("Taste " .. tostring(cmd), e) end end

local MODS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1, UNKNOWN = 1 }
local function combo(key)
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end
local function keyText(k)
    if not k then return "|cff666666" .. L["nicht belegt"] .. "|r" end
    return (GetBindingText and GetBindingText(k)) or k
end
function KB.Set(cmd, key)
    if InCombatLockdown() then K.Toast(L["Tastenkuerzel"], L["Im Kampf nicht moeglich - gleich nochmal."], C.amber or C.accent) return false end
    local old = { GetBindingKey(cmd) }
    for _, k in ipairs(old) do SetBinding(k) end
    if key then
        local prev = GetBindingAction(key)
        if prev and prev ~= "" and prev ~= cmd then
            local name = _G["BINDING_NAME_" .. prev] or prev
            K.Toast(L["Tastenkuerzel"], (L["%s war belegt mit: %s - jetzt Oasis."]):format(keyText(key), name), C.accent)
        end
        SetBinding(key, cmd)
    end
    SaveBindings(GetCurrentBindingSet())
    if K.OnSaved then pcall(K.OnSaved) end
    return true
end

-- Einstellungen > Allgemein > Tastenkuerzel ---------------------------------------------
local capture   -- Knopf, der gerade auf eine Taste wartet
local function stopCapture()
    if not capture then return end
    local b = capture
    capture = nil
    b:EnableKeyboard(false)
    b:SetScript("OnKeyDown", nil)
    if b.Update then b:Update() end
end
local function keyButton(parent, a)
    local b = K.Button(parent, "", 150, 24, "ghost")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function b:Update()
        local k = GetBindingKey(a.cmd)
        self:SetLabel(capture == self and ("|cffffd27a" .. L["Taste druecken ..."] .. "|r") or keyText(k))
    end
    b:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then stopCapture() KB.Set(a.cmd, nil) self:Update() return end
        if capture == self then stopCapture() return end
        if InCombatLockdown() then K.Toast(L["Tastenkuerzel"], L["Im Kampf nicht moeglich - gleich nochmal."], C.accent) return end
        stopCapture()
        capture = self
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, false) end
        self:SetScript("OnKeyDown", function(me, key)
            if MODS[key] then return end
            if key == "ESCAPE" then stopCapture() return end
            stopCapture()
            KB.Set(a.cmd, combo(key))
            me:Update()
        end)
        self:Update()
    end)
    b:HookScript("OnEnter", function(self) K.ShowTip(self, { L[a.text], L["Klick: neue Taste festlegen  ·  Rechtsklick: entfernen  ·  Esc: abbrechen"] }) end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("OnHide", function(self) if capture == self then stopCapture() end end)
    return b
end
-- 0.5.601: neu aufgebaut - Glas-Karten, jede Zeile ein eigenes Element (Symbol, Text, Tasten-Knopf), Esc-Karte darunter
local function glass(c, fill, line, r)
    local G = ns.Insta and ns.Insta.Glass
    if G and pcall(G, c, fill or { 1, 1, 1, 0.035 }, line or { 1, 1, 1, 0.09 }, r or 12) then return end
    K.Fill(c, { 1, 1, 1, 0.03 }) K.Border(c, C.line)
end
local ROWH = 38
local function card(f, x, y, w, h, icon, title, sub)
    local c = CreateFrame("Frame", nil, f)
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(w, h)
    glass(c)
    c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. icon, C.accent)
    c.ic:SetPoint("TOPLEFT", 16, -16)
    c.t = K.Title(c, 14, C.text)
    c.t:SetPoint("LEFT", c.ic, "RIGHT", 8, 0)
    c.t:SetText(title)
    if sub then
        c.s = K.Text(c, 10, C.dim)
        c.s:SetPoint("TOPLEFT", c.ic, "BOTTOMLEFT", 0, -6)
        c.s:SetPoint("RIGHT", -16, 0)
        c.s:SetJustifyH("LEFT")
        c.s:SetText(sub)
    end
    return c
end
local function row(c, i, a, top)
    local r = CreateFrame("Frame", nil, c)
    r:SetHeight(ROWH - 4)
    r:SetPoint("TOPLEFT", 8, top - (i - 1) * ROWH)
    r:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.035)
    if K.RoundMask then K.RoundMask(r.hl, r.hl, 6, { "tl", "tr", "bl" }) end
    r.hl:SetShown(i % 2 == 1)
    r.ic = K.Glyph(r, 15, ns.MEDIA .. "icons\\" .. a.icon, C.muted)
    r.ic:SetPoint("LEFT", 10, 0)
    r.t = K.Text(r, 13, C.text)
    r.t:SetPoint("LEFT", 34, 0)
    r.t:SetPoint("RIGHT", -160, 0)
    r.t:SetJustifyH("LEFT")
    r.t:SetWordWrap(false)
    r.t:SetText(L[a.text])
    r.btn = keyButton(r, a)
    r.btn:SetSize(140, 26)
    r.btn:SetPoint("RIGHT", -6, 0)
    -- belegt: Taste in Akzentfarbe als "Tastenkappe", sonst gedimmt
    local upd = r.btn.Update
    function r.btn:Update()
        upd(self)
        local k = GetBindingKey(a.cmd)
        r.ic:SetVertexColor((k and C.accent or C.muted)[1], (k and C.accent or C.muted)[2], (k and C.accent or C.muted)[3])
        if K.SetBorderColor then K.SetBorderColor(self, (capture == self and C.amber) or (k and C.accent) or C.line) end
    end
    return r
end
-- 0.6.476: Taste des Gildenfensters (Standard J) oeffnet Oasis - als Override-Belegung, nur ausserhalb des Kampfes;
-- aus = Blizzards Gildenfenster wieder. Fremde Belegungen bleiben unangetastet.
local gk = CreateFrame("Frame")
local applying = false
function KB.ApplyGuildKey()
    if applying or not (ClearOverrideBindings and SetOverrideBinding and GetBindingKey) then return end
    if InCombatLockdown and InCombatLockdown() then gk:RegisterEvent("PLAYER_REGEN_ENABLED") return end
    applying = true
    ClearOverrideBindings(gk)
    if ns.db and ns.db.settings.guildKeyOasis then
        local keys = { GetBindingKey("TOGGLEGUILDTAB") }
        if #keys == 0 then keys = { "J" } end
        for _, k in ipairs(keys) do if k then SetOverrideBinding(gk, false, k, "OASIS_TOGGLE") end end
    end
    applying = false
end
gk:SetScript("OnEvent", function(self, ev)
    if ev == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    KB.ApplyGuildKey()
end)
gk:RegisterEvent("UPDATE_BINDINGS")
ns.Listen("DB_READY", function() if ns.After then ns.After(1, KB.ApplyGuildKey) else KB.ApplyGuildKey() end end)

local function build(f)
    f.btns = {}
    local GAP, W = 14, 360
    local function fill(c, from, to)
        for i = from, to do
            local r = row(c, i - from + 1, KB.ACTIONS[i], -50)
            f.btns[#f.btns + 1] = r.btn
        end
    end
    local nWin, nPages = 4, #KB.ACTIONS - 4
    local left = card(f, 0, 0, W, 58 + nWin * ROWH, "settings", L["Fenster"])
    fill(left, 1, 4)
    local right = card(f, W + GAP, 0, W, 58 + nPages * ROWH, "home", L["Seiten direkt oeffnen"])
    fill(right, 5, #KB.ACTIONS)
    -- Esc + Hinweis
    local esc = card(f, 0, -(58 + nWin * ROWH) - GAP, W, 170, "eye_off", L["Esc-Taste"],
        L["Esc schliesst das Oasis-Fenster (im Kampf nicht - dort gehoert Esc dem Spiel)."])
    f.escFocus = K.Toggle(esc, L["Esc nur, wenn ich zuletzt in Oasis geklickt habe"], function() return ns.db.settings.escFocusOnly and true or false end,
        function(v) ns.db.settings.escFocusOnly = v and true or nil if ns.EscUpdate then ns.EscUpdate() end end)
    f.escFocus:SetWidth(W - 32)
    f.escFocus:SetPoint("TOPLEFT", 16, -72)
    f.guildKey = K.Toggle(esc, L["Gildenfenster-Taste (J) oeffnet Oasis"], function() return ns.db.settings.guildKeyOasis and true or false end,
        function(v) ns.db.settings.guildKeyOasis = v and true or nil KB.ApplyGuildKey() end)
    f.guildKey:SetWidth(W - 32)
    f.guildKey:SetPoint("TOPLEFT", 16, -108)
    -- Bedienung
    local help = K.Text(f, 11, C.dim)
    help:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 4, -12)
    help:SetWidth(W - 8)
    help:SetJustifyH("LEFT")
    help:SetWordWrap(true)
    help:SetText(L["Knopf anklicken, dann die Taste druecken (mit Shift/Strg/Alt moeglich). Rechtsklick entfernt die Belegung, Esc bricht ab. Die Kuerzel stehen auch in WoWs Tastaturbelegung unter AddOns > Oasis."])
end
local function refresh(f)
    for _, b in ipairs(f.btns or {}) do b:Update() end
    if f.escFocus then f.escFocus:Refresh() end
    if f.guildKey then f.guildKey:Refresh() end
end
if ns.AddSettingsTab then ns.AddSettingsTab("keys", "Tastenkuerzel", build, refresh) end

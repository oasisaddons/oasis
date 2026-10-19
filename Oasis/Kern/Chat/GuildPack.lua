-- Oasis: Gildenpaket (eigene Emojis & Sounds) - 0.6.531/0.6.532
--  * Gebaut wird das Paket auf oasisaddon.com (Studio im Kopf der Seite, im Browser - nichts wird hochgeladen):
--    ZIP mit Oasis_Emojis + Oasis_Sounds; List.lua setzt OasisGuildPack = { guild, v, made, emojis, sounds }.
--  * FAELSCHUNGSSICHER (0.6.532): Rangsperren und Version kommen NICHT aus den Dateien der anderen, sondern aus dem
--    offiziellen Eintrag der Gildenleitung (Store "gpack", nur Offiziere mit Recht guildcfg duerfen ihn schreiben).
--    Darin: Version, Fingerabdruck des Pakets und die Rangstufe jedes eigenen Emojis/Sounds.
--      - Emojis: Rewards.EmojiLevel nimmt die offizielle Stufe; unbekannte eigene Codes gelten als Stufe 100.
--      - Sounds: der Online-Sound eines anderen spielt nur, wenn SEIN verifizierter Oasis-Rang reicht
--        (sonst der Standardton) - egal was in seiner oder meiner Datei steht.
--      - Wer ein Paket mit anderem Fingerabdruck bei gleicher Version hat, bekommt einen Hinweis.
--  * Einstellungen > Aussehen & Bedienung > Emojis & Sounds: Stand, Link zur Bau-Seite, Freigabe (Leitung).
-- Achtung: NICHT ns.GuildPack nennen - das ist das Kennzeichen "Gildenmodul geladen" (Oasis_Guild/Guild.lua).
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local MP = {}
ns.MediaPack = MP
MP.URL = "oasisaddon.com/#studio"
local OFFICIAL = "gpack-official"

function MP.Mine()
    local p = rawget(_G, "OasisGuildPack")
    if type(p) ~= "table" then return nil end
    return { guild = type(p.guild) == "string" and p.guild:sub(1, 40) or "?", v = tonumber(p.v) or 0, made = type(p.made) == "string" and p.made or "",
        emojis = tonumber(p.emojis) or 0, sounds = tonumber(p.sounds) or 0 }
end
function MP.LegacyInstalled()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not loaded then return false end
    return (loaded("Oasis_Emojis") or loaded("Oasis_Sounds")) and true or false
end

-- Inhalt des installierten Pakets: Codes/Schluessel mit eigener Stufe (aus den Dateien) - nur fuer Fingerabdruck und Freigabe
local function localItems()
    local em, so = {}, {}
    for _, c in ipairs(type(rawget(_G, "OasisEmojiList")) == "table" and OasisEmojiList or {}) do
        for _, e in ipairs(type(c) == "table" and type(c.items) == "table" and c.items or {}) do
            if type(e) == "table" and type(e[1]) == "string" then em[#em + 1] = { e[1], tonumber(e.lvl), tonumber(e.n) } end
        end
    end
    for _, e in ipairs(type(rawget(_G, "OasisSoundsList")) == "table" and OasisSoundsList or {}) do
        if type(e) == "table" and type(e.key) == "string" then so[#so + 1] = { e.key, tonumber(e.lvl) } end
    end
    table.sort(em, function(a, b) return a[1] < b[1] end)
    table.sort(so, function(a, b) return a[1] < b[1] end)
    return em, so
end
-- Fingerabdruck: Codes + Stufen + Anzahl Bilder (djb2, 2 Bahnen)
function MP.Fingerprint()
    local em, so = localItems()
    local parts = {}
    for _, e in ipairs(em) do parts[#parts + 1] = "e:" .. e[1] .. ":" .. (e[2] or 0) .. ":" .. (e[3] or 1) end
    for _, s in ipairs(so) do parts[#parts + 1] = "s:" .. s[1] .. ":" .. (s[2] or 0) end
    local str = table.concat(parts, "|")
    local a, b = 5381, 52711
    for i = 1, #str do
        local c = str:byte(i)
        a = (a * 33 + c) % 16777213
        b = (b * 31 + c * 7) % 16777199
    end
    return ("%06x%06x"):format(a, b), #em, #so
end

------------------------------------------------------------------------
-- Offizieller Eintrag der Leitung
------------------------------------------------------------------------
local offEm, offSo, offAt
-- "code:stufe,..." - Stufe 0 = von der Leitung ausgeschaltet
local function parseMap(s)
    local t = {}
    for k, v in tostring(s or ""):gmatch("([%w_]+):(%d+)") do v = tonumber(v) t[k] = (v == 0) and 0 or math.max(1, math.min(100, v)) end
    return t
end
MP.OFF = 101   -- ausgeschaltet: Stufe, die niemand erreicht (Oasis-Rang geht bis 100)
function MP.Official()
    local r = Store.Get("gpack", OFFICIAL)
    if not r or not tonumber(r.v) then return nil end
    if offAt ~= r.u then offAt, offEm, offSo = r.u, parseMap(r.el), parseMap(r.sl) end
    return r
end
-- offizielle Stufe eines eigenen Emojis (Code ohne Doppelpunkte) / Sounds (Schluessel x_...): nil = keine Vorgabe
function MP.EmojiLock(code)
    if not MP.Official() or not code then return nil end
    local v = offEm[code]
    if v == 0 then return MP.OFF end
    return v or 100   -- nicht im offiziellen Paket -> nur fuer die Hoechsten
end
-- von der Leitung ausgeschaltet?
function MP.IsOff(kind, key)
    if not MP.Official() then return false end
    return ((kind == "sound") and offSo or offEm)[key] == 0
end
-- offizielle Einstellung je Eintrag (fuer den Leitungs-Reiter): Stufe, 0 = aus, nil = nicht freigegeben
function MP.OfficialLevel(kind, key)
    if not MP.Official() then return nil end
    return ((kind == "sound") and offSo or offEm)[key]
end
-- Inhalt des installierten Pakets mit eigener Stufe aus den Dateien
function MP.Items() local em, so = localItems() return em, so end
function MP.SoundLock(key)
    if not MP.Official() or not key then return nil end
    local v = offSo[key]
    if v == 0 then return MP.OFF end
    return v or 100
end
function MP.CanPublish()
    return ns.Admin and ns.Admin.MayAuthor and ns.Admin.MayAuthor(ns.me(), "guildcfg") == true
end
-- Freigeben: Version, Fingerabdruck und die Stufen, die bei MIR gerade gelten (Rewards/Sound rechnen sie aus)
function MP.Publish(over)
    over = over or {}
    local m = MP.Mine()
    if not m or not MP.CanPublish() then return false end
    local fp = MP.Fingerprint()
    local em, so = localItems()
    MP.publishing = true   -- Stufen aus den Dateien/Regeln, nicht aus der alten Freigabe
    local el, sl = {}, {}
    local byCode = ns.Emoji and ns.Emoji.Entry
    for _, e in ipairs(em) do
        local entry = byCode and byCode(":" .. e[1] .. ":")
        local lvl = (over.em and over.em[e[1]]) or e[2] or (entry and ns.Rewards and ns.Rewards.EmojiLevel and ns.Rewards.EmojiLevel(entry)) or 2
        el[#el + 1] = e[1] .. ":" .. math.floor(lvl)
    end
    for _, s in ipairs(so) do
        local c = ns.Sound and ns.Sound.byKey and ns.Sound.byKey[s[1]]
        sl[#sl + 1] = s[1] .. ":" .. math.floor((over.so and over.so[s[1]]) or s[2] or (c and c.lvl) or 2)
    end
    MP.publishing = nil
    Store.Put("gpack", { id = OFFICIAL, v = m.v, made = m.made, fp = fp, el = table.concat(el, ","), sl = table.concat(sl, ","),
        ne = #em, ns = #so, by = ns.me(), ts = ns.now() })
    return true
end

-- Hinweis an Mitglieder: neuere Version freigegeben oder anderer Inhalt bei gleicher Version
local function check()
    local o, m = MP.Official(), MP.Mine()
    if not o or not ns.db then return end
    ns.db.packHint = ns.db.packHint or {}
    local key = tostring(o.v) .. ":" .. tostring(o.fp)
    if ns.db.packHint.last == key then return end
    if not m or m.v < o.v then
        ns.db.packHint.last = key
        K.Toast(L["Neues Gildenpaket"], (L["Die Gildenleitung hat Version %d mit eigenen Emojis und Sounds freigegeben. Frag nach der ZIP und entpacke sie in den AddOns-Ordner."]):format(o.v),
            C.accent, function() ns.ShowPage("settings") if ns.Settings and ns.Settings.SetTab then pcall(ns.Settings.SetTab, "ownmedia") end end)
    elseif m.v == o.v and MP.Fingerprint() ~= o.fp then
        ns.db.packHint.last = key
        K.Toast(L["Gildenpaket weicht ab"], L["Dein Paket hat dieselbe Version wie das offizielle, aber einen anderen Inhalt. Hol dir die ZIP von der Gildenleitung."], C.amber or C.accent)
    end
end
ns.Listen("STORE", function(name) if name == "gpack" then ns.After(2, function() pcall(check) end) ns.RefreshPage("settings") end end)
ns.Listen("LOGIN", function() C_Timer.After(40, function() pcall(check) end) end)
function MP.ReportMine()
    local m = MP.Mine()
    if not m or not IsInGuild() then return end
    local fp = MP.Fingerprint()
    local id = "gph-" .. ns.NameKey(ns.me())
    local old = Store.Get("gpackhave", id)
    if old and old.v == m.v and old.fp == fp and (old.ts or 0) > ns.now() - 7 * 86400 then return end
    Store.Put("gpackhave", { id = id, v = m.v, fp = fp, by = ns.me(), ts = ns.now() })
end
ns.Listen("LOGIN", function() C_Timer.After(60, function() pcall(MP.ReportMine) end) end)
-- Mitglieder (Mains) und ihr Paketstand: { name, v, ok (= offizielle Version + gleicher Inhalt) }
function MP.Holders()
    local o = MP.Official()
    local have = {}
    for _, r in ipairs(Store.List("gpackhave")) do if r.by then have[ns.NameKey(r.by)] = r end end
    local out = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        if not isAlt and (m.online or (m.offDays or 99) < 14) then
            local h = have[ns.NameKey(m.name)]
            out[#out + 1] = { name = m.name, v = h and h.v, ok = (o and h and h.v == o.v and h.fp == o.fp) and true or false }
        end
    end
    table.sort(out, function(a, b) if a.ok ~= b.ok then return not a.ok end return a.name < b.name end)
    return out
end

------------------------------------------------------------------------
-- Einstellungs-Reiter
------------------------------------------------------------------------
StaticPopupDialogs["OASIS_PACK_URL"] = {
    text = "%s", button1 = OKAY or "OK", hasEditBox = true, editBoxWidth = 260,
    OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("https://" .. MP.URL) eb:HighlightText() eb:SetFocus() end end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function MP.ShowUrl() StaticPopup_Show("OASIS_PACK_URL", L["Strg+C kopiert den Link - im Browser oeffnen:"]) end
local function build(f)
    local H = ns.SettingsHelpers
    f.noCompact = true
    local c = H.cardH(f, 0, 0, 740, 150, "smile", L["Eigene Emojis & Sounds fuer deine Gilde"])
    f.how = K.Text(c, 12, C.text)
    f.how:SetPoint("TOPLEFT", 14, -48) f.how:SetPoint("RIGHT", -14, 0)
    f.how:SetJustifyH("LEFT") f.how:SetWordWrap(true) f.how:SetSpacing(4)
    f.how:SetText(L["1. Auf der Webseite Bilder und Sounds hineinziehen - alles passiert in deinem Browser.\n2. Gildenpaket herunterladen und in den AddOns-Ordner entpacken, WoW neu starten.\n3. Die ZIP in eurem Discord teilen - alle in der Gilde entpacken sie genauso."])
    f.go = K.Button(c, L["Link zur Bau-Seite"], 180, 26, "primary", MP.ShowUrl)
    f.go:SetPoint("BOTTOMLEFT", 14, 14)
    f.url = K.Text(c, 12, C.muted) f.url:SetPoint("LEFT", f.go, "RIGHT", 12, 0) f.url:SetText(MP.URL)
    local s = H.cardH(f, 0, -164, 740, 196, "checklist", L["Dein Stand"])
    f.state = K.Text(s, 12, C.text)
    f.state:SetPoint("TOPLEFT", 14, -48) f.state:SetPoint("RIGHT", -14, 0)
    f.state:SetJustifyH("LEFT") f.state:SetWordWrap(true) f.state:SetSpacing(5)
    f.pub = K.Button(s, L["Als offizielles Gildenpaket freigeben"], 270, 24, "ghost", function()
        if MP.Publish() then K.Toast(L["Gildenpaket"], L["Freigegeben: Version, Inhalt und Rangsperren gelten jetzt fuer die ganze Gilde."], C.mint) end
        ns.RefreshPage("settings")
    end)
    f.pub:SetPoint("BOTTOMLEFT", 14, 14)
end
local function refresh(f)
    local m, o = MP.Mine(), MP.Official()
    local lines = {}
    if m then
        lines[#lines + 1] = (L["Installiert: Gildenpaket %s, Version %d (%s) - %d Emojis, %d Sounds"]):format(m.guild, m.v, m.made, m.emojis, m.sounds)
    elseif MP.LegacyInstalled() then
        lines[#lines + 1] = L["Installiert: eigene Emojis/Sounds ohne Versionsangabe (altes Import-Skript). Mit der Bau-Seite neu bauen, dann sieht die Gilde die Version."]
    else
        lines[#lines + 1] = "|cff888888" .. L["Kein Gildenpaket installiert."] .. "|r"
    end
    if o then
        local same = m and m.v == o.v and MP.Fingerprint() == o.fp
        local col = same and "|cff66db9e" or "|cffe8b44a"
        lines[#lines + 1] = col .. (L["Offiziell freigegeben: Version %d (von %s, %s)"]):format(o.v, ns.short(o.by or "?"), o.made or "") .. "|r"
        if not same then lines[#lines + 1] = (m and m.v == o.v) and L["Dein Paket hat einen anderen Inhalt als das offizielle - hol dir die ZIP von der Gildenleitung."]
            or L["Frag die Leitung nach der neuen ZIP, entpacke sie in den AddOns-Ordner und starte WoW neu."] end
    else
        lines[#lines + 1] = "|cff888888" .. L["Die Gildenleitung hat noch kein Paket freigegeben."] .. "|r"
    end
    lines[#lines + 1] = "|cff888888" .. L["Rangsperren gelten nach der Freigabe der Leitung - Aendern der eigenen Dateien hebt sie nicht auf. Ohne Paket erscheinen Emojis als :code:, eigene Sounds als Standardton."] .. "|r"
    f.state:SetText(table.concat(lines, "\n"))
    f.pub:SetShown(m ~= nil and MP.CanPublish() and IsInGuild())
end
if ns.AddSettingsTab then ns.AddSettingsTab("ownmedia", "Emojis & Sounds", build, refresh) end
ns.slash.paket = function() MP.ShowUrl() end
ns.slash.studio = ns.slash.paket

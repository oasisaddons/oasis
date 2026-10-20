-- Oasis: Twink-Verknuepfung (Main + Twinks = ein Spieler)
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Alts = {}
ns.Alts = Alts

------------------------------------------------------------------------
-- Eigene Charaktere: OasisDB ist account-weit, also kennen wir alle,
-- die schon einmal mit Oasis eingeloggt waren
------------------------------------------------------------------------
function Alts.MyChars()
    local out = {}
    for name in pairs(ns.db.chars) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Alts.MyMain()
    local m = ns.db.settings.main
    if m and ns.db.chars[m] then return m end
    -- Standard: hoechster Charakter
    local best, bestLvl = ns.me(), -1
    for name, c in pairs(ns.db.chars) do
        if (c.level or 0) > bestLvl then best, bestLvl = name, c.level or 0 end
    end
    return best
end

function Alts.SetMain(name)
    ns.db.settings.main = name
    ns.Radar.SendHello()
    ns.Fire("ALTS")
end

-- Main eines beliebigen Charakters
-- WoW Forever: derselbe Charakter heisst "Vorname Nachname-Realm" (Gildenliste) und "Vorname-Realm" (Addons)
-- -> beide Formen sind EIN Charakter, kein Main/Twink-Paar
function Alts.SameChar(a, b) return ns.SameName(a, b) end
-- einheitliche Form: immer der Name aus der Gildenliste ("Vorname Nachname-Realm"),
-- damit Listen, die nach Main zusammenfassen, niemanden doppelt fuehren
function Alts.Canon(n) return ns.ResolveName(n) end
local canon = Alts.Canon
-- Twink-Eintraege stehen unter der Kurzform aus Addon-Nachrichten ("Tomas-Realm"),
-- die Gildenliste fuehrt "Tomas Berg-Realm" -> unter allen Formen nachsehen
local function lookup(t, name, c)
    if t[name] then return t[name] end
    if t[c] then return t[c] end
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[c]
    local a = m and m.aname
    if a then return t[a] or t[a .. "2"] end
end
function Alts.Main(name)
    if not name then return name end
    local c = canon(name)
    local main
    if ns.isMe(name) and Alts.OtherConfirmed and Alts.OtherConfirmed() then main = Alts.OtherConfirmed()
    elseif ns.db.chars[name] or ns.isMe(name) then main = Alts.MyMain()
    else main = lookup(ns.db.alts, name, c) or lookup(ns.db.altNotes, name, c) or c end
    main = canon(main)
    if Alts.SameChar(main, c) then return c end
    -- Main, den es in der Gilde nicht (mehr) gibt (umbenannt/geloescht/andere Gilde): ignorieren
    local by = ns.Radar and ns.Radar.byName
    if by and ns.Radar.roster and #ns.Radar.roster > 0 and not by[main] then
        if by[c] then return c end
        -- Name selbst nicht in der Gilde (z.B. alter Main): ein Gildenmitglied nehmen, das ihn als Main hat
        for alt, m in pairs(ns.db.alts) do if canon(m) == main and by[alt] then return canon(alt) end end
        for alt, m in pairs(ns.db.altNotes) do if canon(m) == main and by[alt] then return canon(alt) end end
    end
    return main
end
function Alts.IsAlt(name) return not Alts.SameChar(Alts.Main(name), canon(name)) end

-- alle bekannten Charaktere eines Spielers
function Alts.CharsOf(main)
    -- alle Namensformen auf die Gildenlisten-Form bringen und doppelte weglassen
    local c = Alts.Canon
    main = c(main)
    local out, seen = {}, {}
    local function add(n)
        n = c(n)
        if n and not seen[n] then seen[n] = true out[#out + 1] = n end
    end
    add(main)
    -- 0.5.617: fremde Twinks ausserhalb der Gilde nie zeigen (auch wenn eine alte Version sie noch mitschickt),
    -- ausser der Spieler hat sie selbst freigegeben (Profilfeld ao)
    local open = ns.db.altsOpen and ns.db.altsOpen[main]
    local function visible(alt)
        if open or (ns.db.chars and ns.db.chars[alt]) then return true end
        local g = ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(alt)
        return g ~= false
    end
    for alt, m in pairs(ns.db.alts) do if c(m) == main and visible(alt) then add(alt) end end
    for alt, m in pairs(ns.db.altNotes) do if c(m) == main and not ns.db.alts[alt] then add(alt) end end
    if main == c(Alts.MyMain()) then for _, ch in ipairs(Alts.MyChars()) do add(ch) end end
    return out
end

-- 0.5.610: nur Charaktere teilen, die in der Gilde sind - Bank-/Chill-Twinks ausserhalb der Gilde bleiben privat.
-- Ergebnis je Charakter merken (inGuild), damit es auch gilt, solange die Gildenliste noch nicht geladen ist.
function Alts.Shareable(name)
    if ns.isMe(name) then return IsInGuild() and true or false end
    -- 0.5.614: Einstellung "Twinks ausserhalb der Gilde zeigen" (Standard aus)
    if ns.db.settings.shareAltsOutside and ns.db.chars[name] then return true end
    local c = ns.db.chars[name]
    local g = ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(name)
    if g ~= nil and c then c.inGuild = g end
    if g == nil then g = c and c.inGuild end
    return g == true
end

------------------------------------------------------------------------
-- Twink auf einem ANDEREN WoW-Account (0.5.811)
-- Die Account-Datei kennt nur die eigenen Charaktere. Liegt der Main auf einem anderen Account, traegt man ihn
-- hier von Hand ein (ns.char.mainOther). Damit sich niemand einfach als Twink eines anderen ausgeben kann,
-- gilt die Verknuepfung erst, wenn der MAIN sie bestaetigt hat:
--   Twink schickt im Profil xm = "<gewuenschter Main>"  (Anfrage, aendert noch nichts)
--   Main bekommt eine Rueckfrage; bei Ja kommt der Twink in settings.extraAlts und damit in die eigene Twink-Liste
--   Erst wenn das Profil des Mains den Twink auffuehrt, meldet sich der Twink selbst als dessen Twink.
------------------------------------------------------------------------
local function inGuild(name)
    local A = ns.Admin
    if A and A.InGuildList then return A.InGuildList(name) end
end
local function listedIn(pr, name)
    if type(pr) ~= "table" or type(pr.alts) ~= "string" then return false end
    for alt in pr.alts:gmatch("[^+]+") do if ns.SameName(alt, name) then return true end end
    return false
end
local function profileOf(name)
    local res = ns.ResolveName(name) or name
    return ns.db.members[res] or ns.db.members[name], res
end
function Alts.OtherMain() return ns.char and ns.char.mainOther or nil end
-- hat der Main mich bestaetigt? -> sein Main-Name, sonst nil
function Alts.OtherConfirmed()
    local o = Alts.OtherMain()
    if not o then return nil end
    local pr, res = profileOf(o)
    if not listedIn(pr, ns.me()) then return nil end
    return (type(pr.main) == "string" and pr.main ~= "" and pr.main) or res, pr
end
function Alts.SetOtherMain(name)
    if not ns.char then return end
    ns.char.mainOther = name or nil
    if ns.Radar and ns.Radar.SendHello then ns.Radar.SendHello() end
    ns.Fire("ALTS")
end
-- vom Main bestaetigte Twinks anderer Accounts
function Alts.ExtraAlts()
    local out = {}
    for name in pairs((ns.db and ns.db.settings.extraAlts) or {}) do out[#out + 1] = name end
    table.sort(out)
    return out
end
function Alts.RemoveExtra(name)
    local s = ns.db.settings
    if s.extraAlts then s.extraAlts[name] = nil end
    if ns.Radar and ns.Radar.SendHello then ns.Radar.SendHello() end
    ns.Fire("ALTS")
end

function Alts.ProfileFields()
    -- Twink eines anderen Accounts: bestaetigt -> Main und Twink-Liste des Mains uebernehmen (damit auch aeltere
    -- Oasis-Versionen ein stimmiges Bild bekommen); unbestaetigt -> normale Angaben + Anfrage (xm)
    local o = Alts.OtherMain()
    if o and inGuild(o) == false then o = nil end
    if o then
        local cm, pr = Alts.OtherConfirmed()
        if cm then return cm, pr.alts, o end
    end
    local main = Alts.MyMain()
    -- Main ausserhalb der Gilde wird nicht verraten: dann gilt der eingeloggte Charakter als Main
    if not Alts.Shareable(main) then main = ns.me() end
    local alts = {}
    for _, c in ipairs(Alts.MyChars()) do if c ~= main and Alts.Shareable(c) then alts[#alts + 1] = c end end
    -- bestaetigte Twinks anderer Accounts (nur solange sie in der Gilde sind)
    for _, x in ipairs(Alts.ExtraAlts()) do if inGuild(x) ~= false then alts[#alts + 1] = x end end
    return main, table.concat(alts, "+"), o
end

------------------------------------------------------------------------
-- Daten anderer Spieler (per HELLO) und Gildennotizen als Fallback
------------------------------------------------------------------------
-- Anfrage "ich bin Twink von <xm>" von einem anderen Account: betrifft sie einen MEINER Charaktere, nachfragen
ns.Listen("PROFILE", function(name, p)
    if ns.isMe(name) or type(p.xm) ~= "string" or p.xm == "" or #p.xm > 120 then return end
    local s = ns.db.settings
    local want, mine = ns.ResolveName(p.xm) or p.xm, false
    for c in pairs(ns.db.chars) do if ns.SameName(c, want) then mine = true break end end
    if not mine then return end
    local key = ns.ResolveName(name) or name
    if ns.db.chars[key] or inGuild(key) ~= true then return end
    if (s.extraAlts and s.extraAlts[key]) or (s.altDeclined and s.altDeclined[key]) then return end
    Alts.AskConfirm(key)
end)
ns.Listen("PROFILE", function(name, p)
    if ns.isMe(name) or not p.main or p.main == "" then return end
    local main = p.main
    -- alte Zuordnungen dieses Spielers entfernen (auch unter einem frueheren Main), dann neu setzen
    local old = ns.db.alts[name]
    for alt, m in pairs(ns.db.alts) do if m == main or (old and m == old) then ns.db.alts[alt] = nil end end
    if name ~= main then ns.db.alts[name] = main end
    ns.db.altsOpen = ns.db.altsOpen or {}
    ns.db.altsOpen[main] = (tonumber(p.ao) == 1) or nil
    for alt in (p.alts or ""):gmatch("[^+]+") do
        if alt ~= main then ns.db.alts[alt] = main end
    end
    ns.Fire("ALTS")
end)

-- "Twink von Mira", "Twink: Mira", "Alt Mira", "Mira Twink"
local function parseNote(note)
    if not note or note == "" then return nil end
    local n = note:lower()
    local W = "([%a\128-\255][%a\128-\255%s%-'%.]*)"
    -- Deutsch: "Twink von Mira", "Twink: Mira", "Mira Twink" / Englisch: "alt of Mira", "Mira's alt", "Mira alt"
    return n:match("twink%s+von%s+" .. W) or n:match("twink%s+of%s+" .. W)
        or n:match("alt%s+von%s+" .. W) or n:match("alt%s+of%s+" .. W)
        or n:match("twink%s*[:%-]%s*" .. W) or n:match("alt%s*[:%-]%s*" .. W)
        or n:match("main%s*[:%-]%s*" .. W)
        or n:match("^" .. W .. "'?s%s+alt") or n:match("^" .. W .. "s?%s+twink") or n:match("^" .. W .. "%s+alt$")
        or n:match("^twink%s+" .. W) or n:match("^alt%s+" .. W)
end

ns.Listen("ROSTER", function()
    local byShort = {}
    for _, m in ipairs(ns.Radar.roster) do byShort[ns.short(m.name):lower()] = m.name end
    wipe(ns.db.altNotes)
    for _, m in ipairs(ns.Radar.roster) do
        local target = parseNote(m.note)
        if target and target ~= "von" and target ~= "of" then
            target = target:gsub("%s+$", "")
            local full = byShort[target]
            if not full then
                local resolved = ns.ResolveName(target)
                local m2 = resolved and ns.Radar.byNameLower and ns.Radar.byNameLower[resolved:lower()]
                full = m2 and m2.name
            end
            if full and full ~= m.name then ns.db.altNotes[m.name] = full end
        end
    end
end)

------------------------------------------------------------------------
-- Anzeige-Hilfe: "Mira (Anna)"
------------------------------------------------------------------------
function ns.Radar.Label(name)
    local main = Alts.Main(name)
    if main and not Alts.SameChar(main, canon(name)) then
        return ns.Radar.Colored(name) .. L[" |cff8a84a8("] .. ns.displayName(main) .. L[")|r"]
    end
    return ns.Radar.Colored(name)
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.Listen("DB_READY", function()
    ns.db.alts = ns.db.alts or {}
    ns.db.altNotes = ns.db.altNotes or {}
end)
ns.Listen("LOGIN", function()
    ns.db.alts = ns.db.alts or {}
    ns.db.altNotes = ns.db.altNotes or {}
    ns.char.level = ns.safe(UnitLevel("player")) or ns.char.level
end)
ns.Listen("LEVEL_UP", function(level) ns.char.level = level end)

------------------------------------------------------------------------
-- Charakter-Infos fuer Baum/Listen: Klasse, Stufe, online, Berufe (Rohtext)
-- Quellen: Gildenliste, geteiltes Profil, eigene Charaktere (account-weit gemerkt)
------------------------------------------------------------------------
function Alts.CharInfo(name)
    local R = ns.Radar
    local m = R and R.byName and R.byName[name]
    local me = ns.isMe(name)
    local pr = me and R and R.myProfile and R.myProfile() or ns.db.members[name]
    local own = ns.db.chars[name]
    local raw = pr and pr.profs or (own and own.profs) or (ns.db.guildProfs and ns.db.guildProfs[name])
    return {
        class = (m and m.class) or (own and own.class) or (R and R.ClassOf and R.ClassOf(name)),
        level = (m and m.level) or (pr and tonumber(pr.lvl)) or (own and own.level),
        online = me or (m and m.online) or false,
        profs = raw,
    }
end
-- Main zuerst, dann Twinks (online zuerst, dann hoechste Stufe)
function Alts.Tree(name)
    local main = Alts.Main(name)
    local chars = Alts.CharsOf(main)
    local alts = {}
    for _, c in ipairs(chars) do if c ~= main then alts[#alts + 1] = c end end
    local info = {}
    for _, c in ipairs(chars) do info[c] = Alts.CharInfo(c) end
    table.sort(alts, function(a, b)
        local ia, ib = info[a], info[b]
        if ia.online ~= ib.online then return ia.online end
        if (ia.level or 0) ~= (ib.level or 0) then return (ia.level or 0) > (ib.level or 0) end
        return a < b
    end)
    return main, alts, info
end

-- eigene Klasse + Berufe merken, damit Baum/Abfrage auch ausgeloggte eigene Charaktere zeigen
local function rememberMe()
    if not ns.char then return end
    local _, cls = UnitClass("player")
    cls = ns.safe(cls)
    if cls then ns.char.class = cls end
    local R = ns.Radar
    if R and R.myProfile then
        local ok, p = pcall(R.myProfile)
        if ok and p and p.profs and p.profs ~= "" then ns.char.profs = p.profs end
    end
end

------------------------------------------------------------------------
-- Abfrage beim ersten Einloggen: "Ist <Name> dein Main oder ein Twink?"
-- Nur wenn mindestens 2 eigene Charaktere bekannt sind (bei einem ist er automatisch Main),
-- nicht im Kampf, ~8 s nach dem Login, einmal je Charakter ("Spaeter" fragt hoechstens noch einmal)
------------------------------------------------------------------------
local ask
local function others()
    local me, out = ns.me(), {}
    for _, c in ipairs(Alts.MyChars()) do if c ~= me then out[#out + 1] = c end end
    return out
end
local function glassOn(f, fill, line, r)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(f, fill, line, r) end
end
local function buildAsk()
    local f = CreateFrame("Frame", "OasisAltAsk", UIParent)
    f:SetSize(380, 196)
    f:SetPoint("CENTER", 0, 140)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.bg = K.Fill(f, C.bg)
    K.Border(f, C.line)
    glassOn(f, { C.bg[1], C.bg[2], C.bg[3], 0.97 }, { 1, 1, 1, 0.10 }, 14)
    ns.EscClose("OasisAltAsk")

    f.av = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.av:SetSize(30, 30)
    f.av:SetPoint("TOPLEFT", 18, -16)
    if f.av.SetMask then pcall(f.av.SetMask, f.av, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
    K.MaskSafe(f.av)
    f.title = K.Title(f, 15, C.text)
    f.title:SetPoint("LEFT", f.av, "RIGHT", 10, 0)
    f.title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.title:SetWordWrap(false)
    f.close = K.CloseButton(f, function() f.later() end, L["Schliessen"])
    f.close:SetPoint("TOPRIGHT", -10, -10)
    f.sub = K.Text(f, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", 18, -56)
    f.sub:SetPoint("RIGHT", -18, 0)
    f.sub:SetWordWrap(true)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetText(L["Oasis fasst deine Charaktere in der Gilde zu einem Spieler zusammen. Spaeter aenderbar unter Einstellungen > Profil & Sichern."])

    -- Auswahl "Twink von ..." (nur sichtbar nach Klick auf Twink, wenn es mehrere andere gibt)
    f.ofLabel = K.Text(f, 11, C.muted)
    f.ofLabel:SetPoint("TOPLEFT", 18, -104)
    f.ofLabel:SetText(L["Twink von"])
    f.of = K.Button(f, "", 200, 24, "ghost")
    f.of.isDropdown = true
    f.of:SetPoint("LEFT", f.ofLabel, "RIGHT", 10, 0)
    f.of:SetScript("OnClick", function(self)
        local items = {}
        for _, c in ipairs(others()) do
            items[#items + 1] = { text = ns.displayName(c), checked = c == f.pick, fn = function() f.pick = c self:SetLabel(ns.displayName(c)) end }
        end
        K.ShowMenu(self, items, nil, 200)
    end)
    f.ok = K.Button(f, L["Speichern"], 100, 26, "primary", function()
        if f.mode == "other" then
            local txt = (f.otherIn:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if txt == "" then
                -- leer = Verknuepfung zum anderen Account wieder loesen
                Alts.SetOtherMain(nil)
                f:Hide()
                return
            end
            local res = ns.ResolveName(txt)
            local m = res and ns.Radar.byName and ns.Radar.byName[res]
            if not m then
                -- nur mit Vornamen eingegeben: eindeutig in der Gildenliste?
                local hit, n = nil, 0
                for _, x in ipairs(ns.Radar.roster or {}) do
                    if ns.short(x.name):lower():find(txt:lower(), 1, true) == 1 then hit, n = x, n + 1 end
                end
                if n == 1 then m = hit end
            end
            if not m or ns.isMe(m.name) or ns.db.chars[m.name] then
                K.Toast(L["Nicht gefunden"], L["Bitte den Namen eines Gildenmitglieds eingeben (nicht einen eigenen Charakter)."], C.dim)
                return
            end
            ns.char.altRoleAsked = true
            Alts.SetOtherMain(m.name)
            K.Toast(L["Anfrage geschickt"], (L["%s muss dich einmal bestaetigen - beim naechsten Einloggen mit Oasis kommt dort die Rueckfrage."]):format(ns.displayName(m.name)), C.mint)
            f:Hide()
            return
        end
        if f.pick then
            ns.char.altRoleAsked = true
            Alts.SetMain(f.pick)
            K.Toast(L["Gespeichert"], (L["%s ist jetzt Twink von %s."]):format(ns.displayName(ns.me()), ns.displayName(f.pick)), C.mint)
        end
        f:Hide()
    end)
    f.ok:SetPoint("BOTTOMRIGHT", -18, 16)
    f.back = K.Button(f, L["Zurueck"], 90, 26, "ghost", function() f:SetMode("ask") end)
    f.back:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)

    f.main = K.Button(f, L["Main"], 110, 26, "primary", function()
        ns.char.altRoleAsked = true
        Alts.SetMain(ns.me())
        K.Toast(L["Gespeichert"], (L["%s ist jetzt dein Main."]):format(ns.displayName(ns.me())), C.mint)
        f:Hide()
    end)
    f.main:SetPoint("BOTTOMLEFT", 18, 16)
    f.twink = K.Button(f, L["Twink"], 110, 26, "ghost", function()
        local o = others()
        if #o == 1 then
            ns.char.altRoleAsked = true
            Alts.SetMain(o[1])
            K.Toast(L["Gespeichert"], (L["%s ist jetzt Twink von %s."]):format(ns.displayName(ns.me()), ns.displayName(o[1])), C.mint)
            f:Hide()
        else
            f:SetMode("pick")
        end
    end)
    f.twink:SetPoint("LEFT", f.main, "RIGHT", 8, 0)
    f.laterBtn = K.Button(f, L["Spaeter"], 80, 22, "ghost", function() f.later() end)
    f.laterBtn:SetPoint("BOTTOMRIGHT", -18, 18)
    -- Main liegt auf einem anderen WoW-Account: Namen eintragen, der Main bestaetigt
    f.otherBtn = K.Button(f, L["Mein Main ist auf einem anderen Account"], 290, 22, "ghost", function() f:SetMode("other") end)
    f.otherBtn:SetPoint("TOPLEFT", 18, -108)
    f.otherIn = K.Input(f, 240, L["Name des Mains (Gildenmitglied)"])
    f.otherIn:SetPoint("TOPLEFT", 18, -108)
    if K.AttachNameSuggest then K.AttachNameSuggest(f.otherIn) end
    f.otherIn:Hide()
    function f.later()
        ns.char.altRoleLater = (ns.char.altRoleLater or 0) + 1
        if ns.char.altRoleLater >= 2 then ns.char.altRoleAsked = true end
        f:Hide()
    end
    function f:SetMode(mode)
        self.mode = mode
        local pick, other = mode == "pick", mode == "other"
        self.main:SetShown(not pick and not other)
        self.twink:SetShown(not pick and not other and #others() > 0)
        self.laterBtn:SetShown(not pick and not other)
        self.otherBtn:SetShown(not pick and not other)
        self.otherIn:SetShown(other)
        if other then
            self.otherIn:SetText(Alts.OtherMain() and ns.displayName(Alts.OtherMain()) or "")
            if self.otherIn.SetFocus then self.otherIn:SetFocus() end
        end
        self.ofLabel:SetShown(pick)
        self.of:SetShown(pick)
        self.ok:SetShown(pick or other)
        self.back:SetShown(pick or other)
        if pick then
            -- vorbelegt: bisheriger Main (sonst der hoechste andere Charakter)
            local cur = Alts.MyMain()
            if cur == ns.me() or not ns.db.chars[cur] then
                local best, bl = nil, -1
                for _, c in ipairs(others()) do
                    local lv = ns.db.chars[c] and ns.db.chars[c].level or 0
                    if lv > bl then best, bl = c, lv end
                end
                cur = best
            end
            self.pick = cur
            self.of:SetLabel(cur and ns.displayName(cur) or "")   -- 0.6.249: SetLabel (SetText traf WoWs unsichtbaren Knopftext)
        end
    end
    f:Hide()
    return f
end
-- Rueckfrage beim Main: "<Name> sagt, er ist dein Twink (anderer Account)" - eine nach der anderen, nie im Kampf
local confirmQueue, confirmWin = {}, nil
local function nextConfirm()
    if confirmWin and confirmWin:IsShown() then return end
    if ns.inCombat() then ns.After(10, nextConfirm) return end
    local name = table.remove(confirmQueue, 1)
    if not name then return end
    if not confirmWin then
        local f = CreateFrame("Frame", "OasisAltConfirm", UIParent)
        f:SetSize(400, 150)
        f:SetPoint("CENTER", 0, 180)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f.bg = K.Fill(f, C.bg)
        K.Border(f, C.line)
        glassOn(f, { C.bg[1], C.bg[2], C.bg[3], 0.97 }, { 1, 1, 1, 0.10 }, 14)
        ns.EscClose("OasisAltConfirm")
        f.title = K.Title(f, 15, C.text)
        f.title:SetPoint("TOPLEFT", 18, -16)
        f.title:SetPoint("RIGHT", -18, 0)
        f.title:SetWordWrap(false)
        f.sub = K.Text(f, 11, C.muted)
        f.sub:SetPoint("TOPLEFT", 18, -44)
        f.sub:SetPoint("RIGHT", -18, 0)
        f.sub:SetWordWrap(true)
        f.sub:SetJustifyH("LEFT")
        f.yes = K.Button(f, L["Ja, mein Twink"], 140, 26, "primary", function()
            local s = ns.db.settings
            s.extraAlts = s.extraAlts or {}
            s.extraAlts[f.who] = true
            if ns.Radar and ns.Radar.SendHello then ns.Radar.SendHello() end
            ns.Fire("ALTS")
            K.Toast(L["Gespeichert"], (L["%s ist jetzt Twink von %s."]):format(ns.displayName(f.who), ns.displayName(Alts.MyMain())), C.mint)
            f:Hide()
            ns.After(0.5, nextConfirm)
        end)
        f.yes:SetPoint("BOTTOMLEFT", 18, 16)
        f.no = K.Button(f, L["Nein, kenne ich nicht"], 170, 26, "ghost", function()
            local s = ns.db.settings
            s.altDeclined = s.altDeclined or {}
            s.altDeclined[f.who] = true
            f:Hide()
            ns.After(0.5, nextConfirm)
        end)
        f.no:SetPoint("LEFT", f.yes, "RIGHT", 8, 0)
        f:Hide()
        confirmWin = f
    end
    confirmWin.who = name
    confirmWin.title:SetText((L["Ist %s dein Twink?"]):format(ns.Radar.Colored and ns.Radar.Colored(name) or ns.displayName(name)))
    confirmWin.sub:SetText(L["Dieser Charakter liegt auf einem anderen WoW-Account und hat dich als Main eingetragen. Nur wenn du bestaetigst, zaehlt er in der Gilde als dein Twink."])
    confirmWin:Show()
    confirmWin:Raise()
end
function Alts.AskConfirm(name)
    for _, n in ipairs(confirmQueue) do if n == name then return end end
    if confirmWin and confirmWin:IsShown() and confirmWin.who == name then return end
    confirmQueue[#confirmQueue + 1] = name
    ns.After(1, nextConfirm)
end

function Alts.ShowAsk()
    ask = ask or buildAsk()
    local me = ns.me()
    local _, cls = UnitClass("player")
    cls = ns.safe(cls) or (ns.char and ns.char.class)
    local GI = ns.GuildInfo
    local ok = cls and GI and GI.SetClassIcon and GI.SetClassIcon(ask.av, cls)
    ask.av:SetShown(ok and true or false)
    ask.title:SetText((L["Ist %s dein Main oder ein Twink?"]):format(ns.colorName and ns.colorName(me, cls) or ns.displayName(me)))
    ask:SetMode("ask")
    ask:Show()
    ask:Raise()
end
-- true, wenn gefragt werden soll; bei nur einem Charakter still als Main werten
function Alts.NeedsAsk()
    local c = ns.char
    if not c or c.altRoleAsked then return false end
    if #others() == 0 then return false end
    if ns.db.settings.main == ns.me() then c.altRoleAsked = true return false end
    return true
end
local function tryAsk(tries)
    if not Alts.NeedsAsk() then return end
    if ns.inCombat() or (ns.loadingScreen) then
        if (tries or 0) < 20 then ns.After(15, function() tryAsk((tries or 0) + 1) end) end
        return
    end
    Alts.ShowAsk()
end
ns.Listen("LOGIN", function()
    ns.After(2, rememberMe)
    ns.After(30, rememberMe)
    ns.After(8, function() tryAsk(0) end)
end)
ns.slash.twink = function() Alts.ShowAsk() end

-- Einmalig (0.5.495): Eintraege von Twinks OHNE Gilde, die ueber die gemeinsame Account-Datei in die Gilde
-- gerutscht sind (z. B. Lagerfeuer/Abzeichen eines gildenlosen Twinks), wieder entfernen. Erkennung:
-- Urheber ist als Twink bekannt, steht nicht in der Gildenliste und der Eintrag ist hoechstens 7 Tage alt.
ns.Listen("ROSTER", function()
    if ns.db.leakClean495 or not (ns.Admin and ns.Admin.InGuildList) then return end
    if not (ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0) then return end
    ns.db.leakClean495 = true
    local alts, cut, n = ns.db.alts or {}, ns.now() - 7 * 86400, 0
    -- Vornamen aller Gildenmitglieder: Absender kommen in Forever nur als "Vorname-Realm" an ->
    -- nur loeschen, wenn KEIN Mitglied diesen Vornamen traegt (sonst koennte es ein echtes Mitglied sein)
    local firsts = {}
    for _, m in ipairs(ns.Radar.roster) do
        local f = ns.NameKey(m.name)
        if f ~= "" then firsts[f] = true end
    end
    for name in pairs(ns.db.store or {}) do
        for id, r in pairs(ns.Store.coll(name)) do
            local by = type(r) == "table" and r.by
            local first = by and ns.NameKey(by)
            if by and not r.del and alts[by] and (r.u or 0) > cut and ns.Admin.InGuildList(by) == false and not ns.isMe(by)
                and not firsts[first] then
                ns.Store.Delete(name, id)
                n = n + 1
            end
        end
    end
    if n > 0 then ns.debug("Twink-Eintraege ohne Gilde entfernt:", n) end
end)

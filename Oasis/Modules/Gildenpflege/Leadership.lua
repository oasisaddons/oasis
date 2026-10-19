-- Oasis: Entscheidungshilfen fuer die Gildenleitung (0.6.526)
--  * Reiter "Heute": was steht an (Bewerber, Probezeit vorbei, Befoerderung faellig, Inaktive, Neulinge ohne Paten,
--    Termine mit zu wenig Anmeldungen, Verdachtsmeldungen, offene Abstimmungen, altes Oasis) - je Zeile ein Knopf zur Aktion
--  * Gilden-Puls: aktive Mitglieder, Beitritte/Austritte (30 Tage), Klassenverteilung der Aktiven -> "Es fehlen" fuer Werbung
--  * Reiter "Entscheiden": Abstimmungen nur unter Offizieren (Ja / Nein / Enthaltung, Frist, Ergebnis) - Offizierskanal
--  * Mitglieder-Akte: alles zu einer Person auf einen Blick (Rang seit, Beitritt, zuletzt online, Anwesenheit, Danke,
--    Pate, Twinks, Verlauf, Notizen) - aus Mitglieder-Liste, Rechtsklick-Menue und /oa akte Name
--  * Wochenrueckblick: kurze Zeile fuer den Gildenchat (nur per Klick, ns.OfferChat)
-- Andere Addons: Guild Roster Manager (GRM) fuehrt eigene Historie - Oasis ergaenzt mit gildenweit geteilten Daten
-- (Anwesenheit, Danke, Paten, Abstimmungen); nichts wird aus GRM gelesen oder veraendert.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gildenpflege", function()
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local LD = {}
ns.Leadership = LD
local DAY = 86400

local function roster() return (ns.Radar and ns.Radar.roster) or {} end
local function isAlt(n) return ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(n) or false end
local function short(n) return ns.displayName and ns.displayName(n) or ns.short(n) end
local function inactiveDays() return tonumber(ns.GuildOpt and ns.GuildOpt("ldInactive")) or 30 end

if ns.GuildOption then
    ns.GuildOption({ page = "admin", key = "ldInactive", default = 30, min = 7, max = 120, step = 1, lead = true,
        label = "Inaktiv ab", desc = "Ab so vielen Tagen offline zaehlt ein Mitglied in der Leitung als inaktiv (Twinks zaehlen nicht)",
        fmt = function(v) return v .. " " .. L["Tage"] end })
end

------------------------------------------------------------------------
-- Heute anstehend
------------------------------------------------------------------------
-- { prio (1 = dringend), icon, text, sub, btn, fn }
function LD.Inbox()
    local out = {}
    local O, GH, CO, SP = ns.Officer, ns.GuildHistory, ns.Community, ns.Suspect
    local function add(prio, icon, text, sub, btn, fn) out[#out + 1] = { prio = prio, icon = icon, text = text, sub = sub, btn = btn, fn = fn } end
    local function open(group, sub) return function() if ns.Admin and ns.Admin.OpenOfficer then ns.Admin.OpenOfficer(group, sub) end end end
    -- Bewerber und Probezeit
    if O and O.Recruits then
        local apps, trialDone = {}, {}
        for _, r in ipairs(O.Recruits()) do
            if (r.st or "app") == "app" then apps[#apps + 1] = r.name
            elseif r.st == "trial" and O.TrialLeft and O.TrialLeft(r) == 0 then trialDone[#trialDone + 1] = r.name end
        end
        if #apps > 0 then add(1, "groups", (L["%d Bewerbung(en) warten auf eine Antwort"]):format(#apps), table.concat(apps, ", "), L["Bewerber"], open("members", "recruits")) end
        if #trialDone > 0 then add(1, "checklist", (L["Probezeit vorbei: %s"]):format(table.concat(trialDone, ", ")), L["Aufnehmen oder verlaengern?"], L["Entscheiden"], open("members", "recruits")) end
    end
    -- Befoerderung faellig
    if GH and GH.PromoDue then
        local ok, due = pcall(GH.PromoDue)
        if ok and type(due) == "table" and #due > 0 then
            local names = {}
            for i, d in ipairs(due) do if i <= 4 then names[#names + 1] = short(d.m.name) .. " (" .. d.days .. " " .. L["Tage"] .. ")" end end
            add(2, "badges", (L["%d Mitglied(er) lange im selben Rang"]):format(#due), table.concat(names, ", "), L["Befoerdern"], open("members", "promo"))
        end
    end
    -- Inaktive (ohne Twinks und ohne Leitung)
    local lim, inact = inactiveDays(), 0
    local leadRank = ns.Admin and ns.Admin.LeaderRank and ns.Admin.LeaderRank() or 1
    for _, m in ipairs(roster()) do
        if not m.online and (m.offDays or 0) >= lim and not isAlt(m.name) and (m.rankIndex or 0) > leadRank then inact = inact + 1 end
    end
    if inact > 0 then add(3, "deaths", (L["%d Mitglieder seit %d+ Tagen nicht online"]):format(inact, lim), L["Nachfragen, Rang anpassen oder aufraeumen"], L["Ansehen"], open("members", "inactive")) end
    -- Neulinge ohne Paten
    if CO and CO.MentorOf and ns.Welcome and ns.Welcome.IsNew then
        local list = {}
        for _, m in ipairs(roster()) do
            local okN, new = pcall(ns.Welcome.IsNew, m.name)
            if okN and new and not CO.MentorOf(m.name) and not isAlt(m.name) then list[#list + 1] = short(m.name) end
        end
        if #list > 0 then add(2, "heart", (L["%d Neuling(e) ohne Paten"]):format(#list), table.concat(list, ", ", 1, math.min(#list, 5)),
            L["Gemeinschaft"], function() if ns.Expand then ns.Expand("community") else ns.ShowPage("community") end end) end
    end
    -- Termine in den naechsten 3 Tagen mit wenig Zusagen
    if ns.Raid and ns.Raid.Events and ns.Raid.Signups then
        local now = ns.now()
        for _, ev in ipairs(ns.Raid.Events()) do
            if (ev.ts or 0) > now and ev.ts < now + 3 * DAY then
                local yes = 0
                for _, s in ipairs(ns.Raid.Signups(ev.id)) do if s.status == "yes" then yes = yes + 1 end end
                local want = tonumber(ev.size) or 10
                if yes < want then
                    add(2, "raid", (L["%s am %s: %d von %d Zusagen"]):format(ev.title or "?", date("%d.%m. %H:%M", ev.ts), yes, want),
                        L["Erinnern oder Termin anpassen"], L["Termine"], function() if ns.Admin then ns.Admin.SetTab("events") end end)
                end
            end
        end
    end
    -- Verdachtsmeldungen (mehrere Offiziere unabhaengig)
    if SP and SP.List then
        local ok, list = pcall(SP.List)
        local n = 0
        for _, e in ipairs(ok and list or {}) do if (e.reporters or 0) >= 2 then n = n + 1 end end
        if n > 0 then add(1, "bug", (L["%d Auffaelligkeit(en) im Verdachts-Monitor"]):format(n), L["Von mehreren Offizieren gemeldet"], L["Protokoll"], function() if ns.Admin then ns.Admin.SetTab("tools") end end) end
    end
    -- offene Abstimmungen ohne meine Stimme
    local open_ = 0
    for _, v in ipairs(LD.Votes(true)) do if not LD.MyBallot(v.id) then open_ = open_ + 1 end end
    if open_ > 0 then add(1, "polls", (L["%d Abstimmung(en) warten auf deine Stimme"]):format(open_), nil, L["Abstimmen"], function() if ns.Admin then ns.Admin.SetTab("decide") end end) end
    -- altes Oasis
    if ns.Radar and ns.Radar.VerNum then
        local mine, old = ns.Radar.VerNum(ns.version), 0
        for _, m in ipairs(roster()) do
            local p = ns.db.members[m.name]
            if m.online and type(p) == "table" and p.v and ns.Radar.VerNum(p.v) < mine then old = old + 1 end
        end
        if old > 0 then add(4, "sync", (L["%d online mit aelterem Oasis"]):format(old), L["Kurz an das Update erinnern"], L["Mitglieder"], function() if ns.Admin then ns.Admin.SetTab("overview") end end) end
    end
    table.sort(out, function(a, b) return a.prio < b.prio end)
    return out
end

------------------------------------------------------------------------
-- Gilden-Puls
------------------------------------------------------------------------
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
function LD.Pulse()
    local now = ns.now()
    local p = { members = 0, active = 0, online = 0, joins = 0, leaves = 0, classes = {}, mains = 0 }
    for _, m in ipairs(roster()) do
        p.members = p.members + 1
        if m.online then p.online = p.online + 1 end
        local act = m.online or (m.offDays or 99) < 7
        if act then p.active = p.active + 1 end
        if act and not isAlt(m.name) and m.class then
            p.mains = p.mains + 1
            p.classes[m.class] = (p.classes[m.class] or 0) + 1
        end
    end
    for _, r in ipairs(Store.List("audit")) do
        if (r.ts or 0) > now - 30 * DAY then
            if r.kind == "join" or r.kind == "rejoin" then p.joins = p.joins + 1
            elseif r.kind == "leave" or r.kind == "kick" then p.leaves = p.leaves + 1 end
        end
    end
    -- "Es fehlen": Klassen deutlich unter dem Schnitt (Horde-Gilde: Paladin gibt es nicht immer -> nur Klassen mit Mitgliedern im Spiel)
    local _, myFaction = UnitFactionGroup and UnitFactionGroup("player")
    local avg = p.mains / 8
    p.need = {}
    if p.mains < 15 then return p end   -- bei kleinen Gilden waere "es fehlen" nur Raten
    for _, c in ipairs(CLASSES) do
        if not ((c == "PALADIN" and myFaction == "Horde") or (c == "SHAMAN" and myFaction == "Alliance")) then
            if (p.classes[c] or 0) < avg * 0.6 then p.need[#p.need + 1] = c end
        end
    end
    return p
end
local function className(c) return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c end
LD.ClassName = className

------------------------------------------------------------------------
-- Abstimmungen unter Offizieren (Sammlungen lvotes/lballots, nur Offizierskanal)
------------------------------------------------------------------------
function LD.Votes(onlyOpen)
    local now = ns.now()
    local list = Store.List("lvotes", function(v) return not onlyOpen or ((v.ends or 0) > now and not v.closed) end)
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return list
end
function LD.NewVote(title, days)
    title = (title or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" or not ns.isOfficer() then return end
    Store.Put("lvotes", { id = ns.newId("lv"), title = title:sub(1, 140), by = ns.me(), ts = ns.now(), ends = ns.now() + (days or 3) * DAY })
end
function LD.MyBallot(vid) local b = Store.Get("lballots", vid .. "@" .. ns.me()) return b and b.v end
function LD.Vote(vid, v)
    if not ns.isOfficer() or (v ~= "y" and v ~= "n" and v ~= "a") then return end
    Store.Put("lballots", { id = vid .. "@" .. ns.me(), vid = vid, v = v, by = ns.me(), ts = ns.now() })
end
function LD.Tally(vid)
    local t = { y = 0, n = 0, a = 0, who = {} }
    for _, b in ipairs(Store.List("lballots", function(b) return b.vid == vid end)) do
        if t[b.v] then t[b.v] = t[b.v] + 1 t.who[#t.who + 1] = { n = b.by, v = b.v } end
    end
    return t
end
function LD.Close(vid)
    local v = Store.Get("lvotes", vid)
    if not v or not (ns.isMe(v.by) or (ns.Admin and ns.Admin.IsGM and ns.Admin.IsGM())) then return end
    local copy = {}
    for k, x in pairs(v) do copy[k] = x end
    copy.closed = true
    Store.Put("lvotes", copy)
end

------------------------------------------------------------------------
-- Mitglieder-Akte
------------------------------------------------------------------------
function LD.Dossier(name)
    local d = { name = name }
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[ns.fullName(name)]
    d.m = m
    local GH, O, CO = ns.GuildHistory, ns.Officer, ns.Community
    if GH then
        d.rankSince = GH.RankSince and GH.RankSince(name)
        d.joined = GH.JoinedAt and GH.JoinedAt(name)
        d.timeline = GH.Timeline and GH.Timeline(name) or {}
        d.note = GH.Note and GH.Note(name)
        d.former = GH.Former and GH.Former(name)
    end
    if O and O.Attendance then d.att, d.attHere, d.attTotal = O.Attendance(name, 28) end
    if O and O.MissingEnchants then local ok, n = pcall(O.MissingEnchants, name) d.missEnch = ok and n or nil end
    if O and O.BanOf then d.ban = O.BanOf(name) end
    if CO then
        local n = 0
        for _, r in ipairs(CO.Thanks and CO.Thanks(ns.now() - 30 * DAY) or {}) do if ns.SameName(r.to, name) then n = n + 1 end end
        d.thanks = n
        d.mentor = CO.MentorOf and CO.MentorOf(name)
        d.mentees = CO.MenteesOf and #(CO.MenteesOf(name) or {}) or 0
    end
    if ns.Alts and ns.Alts.Main then
        d.main = ns.Alts.Main(name)
        d.chars = ns.Alts.CharsOf and ns.Alts.CharsOf(d.main) or {}
    end
    local p = ns.db.members[ns.fullName(name)]
    d.ver = type(p) == "table" and p.v or nil
    return d
end
local akte
local function line(f, y, k, v)
    f.n = f.n + 1
    local r = f.rows[f.n]
    if not r then
        r = { k = K.Text(f.body, 11, C.muted), v = K.Text(f.body, 12, C.text) }
        r.v:SetJustifyH("LEFT") r.v:SetWordWrap(true)
        f.rows[f.n] = r
    end
    r.k:ClearAllPoints() r.k:SetPoint("TOPLEFT", 0, y) r.k:SetWidth(130) r.k:SetText(k) r.k:Show()
    r.v:ClearAllPoints() r.v:SetPoint("TOPLEFT", 140, y) r.v:SetPoint("RIGHT", f.body, "RIGHT", 0, 0) r.v:SetText(v or "-") r.v:Show()
    return y - math.max(18, (r.v:GetStringHeight() or 14) + 6)
end
local function ago(ts) if not ts then return L["unbekannt"] end local d = math.floor((ns.now() - ts) / DAY) return (L["vor %d Tagen"]):format(d) .. "  |cff777777(" .. date("%d.%m.%Y", ts) .. ")|r" end
function LD.ShowDossier(name)
    if not name or not ns.isOfficer() then return end
    if not akte then
        local f = CreateFrame("Frame", "OasisDossier", UIParent)
        f:SetSize(520, 540)
        f:SetPoint("CENTER", 120, 0)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true) f:EnableMouse(true) f:SetClampedToScreen(true) f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.04, 0.04, 0.05, 0.97 }, { 1, 1, 1, 0.10 }, 12)) then K.Fill(f, { 0.04, 0.04, 0.05, 0.97 }) K.Border(f, C.line) end
        f.title = K.Title(f, 16, C.text)
        f.title:SetPoint("TOPLEFT", 18, -16)
        f.sub = K.Text(f, 11, C.muted)
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
        local x = K.CloseButton(f, function() f:Hide() end)
        x:SetPoint("TOPRIGHT", -6, -6)
        f.body = CreateFrame("Frame", nil, f)
        f.body:SetPoint("TOPLEFT", 18, -64)
        f.body:SetPoint("BOTTOMRIGHT", -18, 50)
        f.rows = {}
        f.noteBtn = K.Button(f, L["Notiz bearbeiten"], 130, 24, "ghost", function()
            if not f.who then return end
            local cur = ns.GuildHistory and ns.GuildHistory.Note and ns.GuildHistory.Note(f.who)
            StaticPopup_Show("OASIS_LD_NOTE", short(f.who), nil, { who = f.who, text = cur and cur.t or "" })
        end)
        f.noteBtn:SetPoint("BOTTOMLEFT", 18, 14)
        f.voteBtn = K.Button(f, L["Abstimmung starten"], 150, 24, "ghost", function()
            if f.who then StaticPopup_Show("OASIS_LD_NEWVOTE", nil, nil, (L["Entscheidung zu %s: "]):format(short(f.who))) end
        end)
        f.voteBtn:SetPoint("LEFT", f.noteBtn, "RIGHT", 8, 0)
        f.wBtn = K.Button(f, L["Anfluestern"], 110, 24, "ghost", function() if f.who and ns.Whisper then ns.Whisper(f.who) end end)
        f.wBtn:SetPoint("LEFT", f.voteBtn, "RIGHT", 8, 0)
        if ns.EscClose then ns.EscClose("OasisDossier") end
        akte = f
    end
    local f = akte
    local d = LD.Dossier(name)
    f.who = name
    for _, r in ipairs(f.rows) do r.k:Hide() r.v:Hide() end
    f.n = 0
    local m = d.m
    f.title:SetText(ns.colorName and ns.colorName(short(name), m and m.class) or short(name))
    f.sub:SetText(m and ((m.rank or "") .. "  ·  " .. L["Stufe"] .. " " .. (m.level or "?") .. "  ·  " .. (m.online and ("|cff66db9e" .. L["online"] .. "|r") or ((L["offline seit %d Tagen"]):format(math.floor(m.offDays or 0))))) or L["nicht (mehr) in der Gilde"])
    local y = 0
    y = line(f, y, L["In der Gilde seit"], ago(d.joined))
    y = line(f, y, L["Im Rang seit"], ago(d.rankSince))
    if d.att then y = line(f, y, L["Raid-Anwesenheit"], ("%d%%  |cff777777(%d/%d, 28 Tage)|r"):format(math.floor(d.att * 100 + 0.5), d.attHere or 0, d.attTotal or 0)) end
    y = line(f, y, L["Danke bekommen"], (L["%d in 30 Tagen"]):format(d.thanks or 0))
    if d.mentor then y = line(f, y, L["Pate"], short(d.mentor)) end
    if (d.mentees or 0) > 0 then y = line(f, y, L["Pate fuer"], (L["%d Neuling(e)"]):format(d.mentees)) end
    if d.chars and #d.chars > 1 then
        local cs = {}
        for _, c in ipairs(d.chars) do cs[#cs + 1] = short(type(c) == "table" and c.name or c) end
        y = line(f, y, L["Charaktere"], table.concat(cs, ", "))
    end
    if d.missEnch and d.missEnch > 0 then y = line(f, y, L["Fehlende Verzauberungen"], tostring(d.missEnch)) end
    y = line(f, y, L["Oasis"], d.ver or ("|cff777777" .. L["nicht installiert"] .. "|r"))
    if m and (m.onote or "") ~= "" then y = line(f, y, L["Offiziersnotiz"], m.onote) end
    if d.note and (d.note.t or "") ~= "" then y = line(f, y, L["Leitungsnotiz"], d.note.t .. "  |cff777777(" .. short(d.note.by or "?") .. ")|r") end
    if d.ban then y = line(f, y, "|cffff6a5a" .. L["Bannliste"] .. "|r", tostring(d.ban.reason or d.ban.r or "")) end
    local tl = {}
    for i, r in ipairs(d.timeline or {}) do
        if i > 6 then break end
        local txt = ns.Officer and ns.Officer.AuditText and select(2, pcall(ns.Officer.AuditText, r)) or r.kind
        tl[#tl + 1] = date("%d.%m.%y", r.ts or 0) .. "  " .. tostring(txt)
    end
    if #tl > 0 then y = line(f, y, L["Verlauf"], table.concat(tl, "\n")) end
    f.noteBtn:SetShown(ns.GuildHistory and ns.GuildHistory.SetNote ~= nil and ns.GuildHistory.CanNotes and ns.GuildHistory.CanNotes())
    f:Show()
    f:Raise()
end
StaticPopupDialogs["OASIS_LD_NEWVOTE"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Abbrechen", hasEditBox = true, maxLetters = 140,
    OnShow = function(self, data) local eb = self.editBox or self.EditBox if eb then eb:SetText(data or "") eb:SetFocus() end end,
    OnAccept = function(self) local eb = self.editBox or self.EditBox LD.NewVote(eb and eb:GetText(), 3) ns.RefreshPage("admin") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["OASIS_LD_NOTE"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Abbrechen", hasEditBox = true, maxLetters = 500,
    OnShow = function(self, data) local eb = self.editBox or self.EditBox if eb and data then eb:SetText(data.text or "") eb:SetFocus() end end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        if data and ns.GuildHistory and ns.GuildHistory.SetNote then ns.GuildHistory.SetNote(data.who, eb and eb:GetText() or "") end
        if akte and akte:IsShown() and data then LD.ShowDossier(data.who) end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
ns.slash.akte = function(arg) if arg and arg ~= "" then LD.ShowDossier(ns.fullName(arg)) end end
ns.slash.dossier = ns.slash.akte

------------------------------------------------------------------------
-- Wochenrueckblick fuer den Gildenchat
------------------------------------------------------------------------
function LD.WeekRecap()
    local cut = ns.now() - 7 * DAY
    local joins, lvls, bosses = 0, 0, 0
    for _, r in ipairs(Store.List("audit")) do if (r.ts or 0) > cut and (r.kind == "join" or r.kind == "rejoin") then joins = joins + 1 end end
    for _, r in ipairs(Store.List("chronicle", function(r) return (r.ts or 0) > cut end)) do
        if r.kind == "level" then lvls = lvls + 1 elseif r.kind == "boss" then bosses = bosses + 1 end
    end
    local parts = { (L["Oasis-Woche: %d neue Mitglieder, %d Level-Meilensteine, %d Bosse"]):format(joins, lvls, bosses) }
    local helper, n = ns.Community and ns.Community.Helper and ns.Community.Helper()
    if helper and (n or 0) > 0 then parts[#parts + 1] = (L["Helfer der Woche: %s (%d x Danke)"]):format(ns.short(helper), n) end
    return table.concat(parts, " - ")
end

------------------------------------------------------------------------
-- Reiter in der Gildenleitung
------------------------------------------------------------------------
local function glass(f, a) local G = ns.Insta and ns.Insta.Glass if not (G and pcall(G, f, { 1, 1, 1, a or 0.035 }, { 1, 1, 1, 0.09 }, 10)) then K.Fill(f, { 1, 1, 1, 0.03 }) end end
local PRIO = { [1] = C.red or C.accent, [2] = C.amber or C.accent, [3] = C.blue or C.muted, [4] = C.muted }
local function buildToday(f)
    f.head = K.Title(f, 16, C.text)
    f.head:SetPoint("TOPLEFT", 4, -4)
    f.head:SetText(L["Heute anstehend"])
    f.list = K.List(f, 46, function(l)
        local r = K.Row(l)
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT", 0, -6) r.bar:SetPoint("BOTTOMLEFT", 0, 6) r.bar:SetWidth(3)
        r.ic = K.Glyph(r, 18, ns.MEDIA .. "icons\\home", C.muted)
        r.ic:SetPoint("LEFT", 12, 0)
        r.t = K.Text(r, 13, C.text)
        r.t:SetPoint("TOPLEFT", 40, -7) r.t:SetPoint("RIGHT", -130, 0) r.t:SetWordWrap(false)
        r.s = K.Text(r, 11, C.muted)
        r.s:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -3) r.s:SetPoint("RIGHT", -130, 0) r.s:SetWordWrap(false)
        r.b = K.Button(r, "", 110, 24, "ghost", function(self) if self.fn then pcall(self.fn) end end)
        r.b:SetPoint("RIGHT", -8, 0)
        return r
    end, function(r, it)
        local c = PRIO[it.prio] or C.muted
        r.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
        r.ic:SetTexture(ns.MEDIA .. "icons\\" .. (it.icon or "home"))
        r.ic:SetVertexColor(c[1], c[2], c[3])
        r.t:SetText(it.text) r.s:SetText(it.sub or "")
        r.b:SetLabel(it.btn or L["Oeffnen"]) r.b.fn = it.fn
    end)
    f.list:SetPoint("TOPLEFT", 0, -30)
    f.list:SetPoint("BOTTOMRIGHT", -330, 0)
    glass(f.list, 0.025)
    -- rechts: Gilden-Puls
    f.pulse = CreateFrame("Frame", nil, f)
    f.pulse:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 14, 0)
    f.pulse:SetPoint("BOTTOMRIGHT", 0, 0)
    glass(f.pulse, 0.03)
    f.ph = K.Title(f.pulse, 14, C.text)
    f.ph:SetPoint("TOPLEFT", 14, -12)
    f.ph:SetText(L["Gilden-Puls"])
    f.stats = K.Text(f.pulse, 12, C.text)
    f.stats:SetPoint("TOPLEFT", 14, -36) f.stats:SetPoint("RIGHT", -14, 0)
    f.stats:SetJustifyH("LEFT") f.stats:SetSpacing(4)
    f.bars = {}
    for i, c in ipairs(CLASSES) do
        local b = CreateFrame("Frame", nil, f.pulse)
        b:SetSize(10, 14)
        b.l = K.Text(b, 10, C.muted) b.l:SetPoint("LEFT", 0, 0) b.l:SetWidth(70) b.l:SetJustifyH("LEFT")
        b.bar = K.Bar(b, 160, 6) b.bar:SetPoint("LEFT", 74, 0)
        b.n = K.Text(b, 10, C.dim, "RIGHT") b.n:SetPoint("LEFT", b.bar, "RIGHT", 6, 0)
        b.cls = c
        f.bars[i] = b
    end
    f.need = K.Text(f.pulse, 11, C.amber or C.accent)
    f.need:SetJustifyH("LEFT") f.need:SetWordWrap(true)
    f.recap = K.Button(f.pulse, L["Wochenrueckblick posten"], 200, 24, "ghost", function() ns.OfferChat(L["Wochenrueckblick"], LD.WeekRecap(), "GUILD") end)
    f.recap:SetPoint("BOTTOMLEFT", 14, 14)
end
local function refreshToday(f)
    local items = LD.Inbox()
    f.list:SetData(items)
    f.list.empty:SetText(#items == 0 and L["Alles erledigt - gerade steht nichts an."] or "")
    local p = LD.Pulse()
    f.stats:SetText((L["%d Mitglieder, %d aktiv (7 Tage), %d online"]):format(p.members, p.active, p.online) .. "\n"
        .. (L["30 Tage: %d dazu, %d gegangen"]):format(p.joins, p.leaves))
    local y = -36 - (f.stats:GetStringHeight() or 30) - 14
    local max = 1
    for _, n in pairs(p.classes) do if n > max then max = n end end
    for _, b in ipairs(f.bars) do
        local n = p.classes[b.cls] or 0
        local cr, cg, cb = ns.classColor(b.cls)
        b.l:SetText(className(b.cls)) b.l:SetTextColor(cr or 1, cg or 1, cb or 1)
        b.bar:Set(n / max) b.n:SetText(n)
        b:ClearAllPoints() b:SetPoint("TOPLEFT", f.pulse, "TOPLEFT", 14, y) b:SetPoint("RIGHT", f.pulse, "RIGHT", -14, 0)
        y = y - 18
    end
    local need = {}
    for _, c in ipairs(p.need) do need[#need + 1] = className(c) end
    f.need:ClearAllPoints() f.need:SetPoint("TOPLEFT", f.pulse, "TOPLEFT", 14, y - 8) f.need:SetPoint("RIGHT", f.pulse, "RIGHT", -14, 0)
    f.need:SetText(#need > 0 and ((L["Wenige aktive: %s - gut fuer die Werbung"]):format(table.concat(need, ", "))) or "")
end

local function buildDecide(f)
    f.head = K.Title(f, 16, C.text)
    f.head:SetPoint("TOPLEFT", 4, -4)
    f.head:SetText(L["Entscheidungen der Leitung"])
    f.info = K.Text(f, 11, C.muted)
    f.info:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -4)
    f.info:SetText(L["Nur Offiziere sehen und stimmen ab (Offizierskanal). Jede Stimme ist mit Namen sichtbar."])
    f.new = K.Button(f, L["Neue Abstimmung"], 150, 24, nil, function() StaticPopup_Show("OASIS_LD_NEWVOTE", L["Worueber soll die Leitung entscheiden?"], nil, "") end)
    f.new:SetPoint("TOPRIGHT", 0, -2)
    f.list = K.List(f, 70, function(l)
        local r = K.Row(l)
        r.t = K.Text(r, 13, C.text) r.t:SetPoint("TOPLEFT", 12, -8) r.t:SetPoint("RIGHT", -300, 0) r.t:SetWordWrap(false)
        r.s = K.Text(r, 11, C.muted) r.s:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -4) r.s:SetPoint("RIGHT", -300, 0) r.s:SetWordWrap(false)
        r.res = K.Text(r, 11, C.text) r.res:SetPoint("TOPLEFT", r.s, "BOTTOMLEFT", 0, -4) r.res:SetPoint("RIGHT", -300, 0) r.res:SetWordWrap(false)
        r.btns = {}
        for i, d in ipairs({ { "y", "Ja" }, { "n", "Nein" }, { "a", "Enthaltung" } }) do
            local b = K.Button(r, L[d[2]], 84, 24, "ghost", function(self) if r.item then LD.Vote(r.item.id, d[1]) ns.RefreshPage("admin") end end)
            b:SetPoint("RIGHT", -8 - (3 - i) * 90, 8)
            b.v = d[1]
            r.btns[i] = b
        end
        r.close = K.Button(r, L["Beenden"], 84, 20, "ghost", function() if r.item then LD.Close(r.item.id) ns.RefreshPage("admin") end end)
        r.close:SetPoint("BOTTOMRIGHT", -8, 6)
        return r
    end, function(r, v)
        local t = LD.Tally(v.id)
        local done = v.closed or (v.ends or 0) <= ns.now()
        r.t:SetText(v.title)
        r.s:SetText(short(v.by or "?") .. "  ·  " .. (done and L["beendet"] or ((L["laeuft bis %s"]):format(date("%d.%m. %H:%M", v.ends or 0)))))
        local who = {}
        for _, w in ipairs(t.who) do who[#who + 1] = short(w.n) .. ((w.v == "y" and " |cff66db9e+|r") or (w.v == "n" and " |cffff6a5a-|r") or " |cff888888o|r") end
        local res = ("|cff66db9e%s %d|r   |cffff6a5a%s %d|r   |cff888888%s %d|r"):format(L["Ja"], t.y, L["Nein"], t.n, L["Enthaltung"], t.a)
        if done then res = res .. "   -   " .. ((t.y > t.n) and ("|cff66db9e" .. L["angenommen"] .. "|r") or ("|cffff6a5a" .. L["abgelehnt"] .. "|r")) end
        r.res:SetText(res .. (#who > 0 and ("   |cff777777" .. table.concat(who, ", ") .. "|r") or ""))
        local mine = LD.MyBallot(v.id)
        for _, b in ipairs(r.btns) do
            b:SetShown(not done)
            if K.SetBorderColor then K.SetBorderColor(b, mine == b.v and C.accent or C.line) end
        end
        r.close:SetShown(not done and (ns.isMe(v.by) or (ns.Admin and ns.Admin.IsGM and ns.Admin.IsGM())))
    end)
    f.list:SetPoint("TOPLEFT", 0, -50)
    f.list:SetPoint("BOTTOMRIGHT", 0, 0)
    glass(f.list, 0.025)
end
local function refreshDecide(f)
    local list = LD.Votes(false)
    f.list:SetData(list)
    f.list.empty:SetText(#list == 0 and L["Noch keine Abstimmungen. Beispiel: 'Oni zum Raidleiter machen?'"] or "")
    f.new:SetShown(ns.isOfficer())
end
if ns.Admin and ns.Admin.AddTab then
    ns.Admin.AddTab("today", "Heute", buildToday, refreshToday, "Was steht an? Bewerber, Befoerderungen, Inaktive, Neulinge ohne Paten, Termine - je Zeile ein Klick zur Aktion. Rechts: der Gilden-Puls.", 1)
    ns.Admin.AddTab("decide", "Entscheiden", buildDecide, refreshDecide, "Abstimmungen unter Offizieren: Vorschlag machen, Ja/Nein/Enthaltung, Ergebnis nach Ablauf der Frist.", 3)
end

end)

-- Oasis: Mitglieder-Extras
-- Spielzeit + Tageszeit, Level-Tempo, Gruppen-/Dungeonstatus, Online-Aufstellung,
-- Offiziersnotiz, Geburtstage und Gildenjubilaeen, Rechtsklick-Menue
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Members = {}
ns.Members = Members
local KEEP_DAYS = 30

local function dayKey(ts) return date("%Y-%m-%d", ts or ns.now()) end
local function store()
    ns.db.play = ns.db.play or {}       -- [name] = { d = { [Tag] = Sekunden }, h = { [Stunde] = Sekunden } }
    ns.db.lvlHist = ns.db.lvlHist or {} -- [name] = { [Tag] = Level }
    return ns.db.play, ns.db.lvlHist
end
Members.Store = store
Members.DayKey = dayKey

------------------------------------------------------------------------
-- Mitschnitt aus der Gildenliste (jedes Einlesen, ca. alle 45 s)
------------------------------------------------------------------------
local lastSample
local function sample()
    if not (ns.Radar and ns.Radar.roster) then return end
    local now = ns.now()
    local delta = lastSample and (now - lastSample) or 0
    lastSample = now
    if delta > 180 then delta = 0 end   -- Luecke (z.B. Ladebildschirm): nicht hochrechnen
    local play, hist = store()
    local today, hour = dayKey(now), tonumber(date("%H", now))
    for _, m in ipairs(ns.Radar.roster) do
        if m.online then
            local e = play[m.name] or { d = {}, h = {} }
            play[m.name] = e
            if delta > 0 and ns.db.settings.trackPlay ~= false and ns.Radar.UsesOasis and ns.Radar.UsesOasis(m.name) then
                e.d[today] = (e.d[today] or 0) + delta
                e.h[hour] = (e.h[hour] or 0) + delta
            end
        end
        if (m.level or 0) > 0 then
            local h = hist[m.name] or {}
            hist[m.name] = h
            if (h[today] or 0) < m.level then h[today] = m.level end
        end
    end
end
ns.Listen("ROSTER", function() pcall(sample) end)

-- alte Tage wegraeumen
local function prune()
    local play, hist = store()
    local cut = dayKey(ns.now() - KEEP_DAYS * 86400)
    for name, e in pairs(play) do
        for d in pairs(e.d or {}) do if d < cut then e.d[d] = nil end end
        -- 0.5.617: keine Tage mehr im Zeitraum (oder kein Oasis-Nutzer) -> auch das Stunden-Profil loeschen
        if not next(e.d or {}) or (ns.Radar and ns.Radar.UsesOasis and next(ns.db.members or {}) and not ns.Radar.UsesOasis(name)) then play[name] = nil end
    end
    for _, h in pairs(hist) do for d in pairs(h) do if d < cut then h[d] = nil end end end
end

------------------------------------------------------------------------
-- Auswertung
------------------------------------------------------------------------
function Members.PlayToday(name)
    local e = store()[name]
    return e and e.d and e.d[dayKey()] or 0
end
function Members.PlayWeek(name)
    local e, sum = store()[name], 0
    if not e or not e.d then return 0 end
    local cut = dayKey(ns.now() - 7 * 86400)
    for d, s in pairs(e.d) do if d > cut then sum = sum + s end end
    return sum
end
function Members.FmtDuration(sec)
    sec = math.floor(sec or 0)
    if sec < 60 then return L["unter 1 Min."] end
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h == 0 then return (L["%d Min."]):format(m) end
    return (L["%d:%02d Std."]):format(h, m)
end
-- Tageszeit mit der meisten Spielzeit (4-Stunden-Fenster)
local PARTS = {
    { 5, 11, "morgens" }, { 11, 14, "mittags" }, { 14, 18, "nachmittags" }, { 18, 23, "abends" },
}
function Members.Peak(name)
    local e = store()[name]
    if not e or not e.h then return end
    local total = 0
    for _, s in pairs(e.h) do total = total + s end
    if total < 1800 then return end
    local best, bestH = -1, 0
    for start = 0, 23 do
        local sum = 0
        for k = 0, 3 do sum = sum + (e.h[(start + k) % 24] or 0) end
        if sum > best then best, bestH = sum, start end
    end
    local mid = (bestH + 2) % 24
    local part = "nachts"
    for _, p in ipairs(PARTS) do if mid >= p[1] and mid < p[2] then part = p[3] end end
    return (L["meist %s (%d-%d Uhr)"]):format(L[part], bestH, (bestH + 4) % 24), part
end
-- gewonnene Level in den letzten Tagen
function Members.LevelGain(name, days, current)
    local _, hist = store()
    local h = hist[name]
    if not h then return 0 end
    current = current or 0
    local cut = dayKey(ns.now() - (days or 7) * 86400)
    local oldestDay, oldestLvl
    for d, lv in pairs(h) do
        if d >= cut and (not oldestDay or d < oldestDay) then oldestDay, oldestLvl = d, lv end
        if lv > current then current = lv end
    end
    if not oldestLvl then return 0 end
    return math.max(0, current - oldestLvl)
end

------------------------------------------------------------------------
-- Gruppenstatus (wird per HELLO geteilt: "i5" = im Dungeon mit 5, "g3" = Gruppe mit 3)
------------------------------------------------------------------------
-- Vollstaendige Namen, gleiche Signatur auf allen Gruppenclients; keine Gebietsschaetzung.
function Members.MyGroupNames()
    local n = ns.safe(GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n < 2 then return "" end
    local names, seen = {}, {}
    local function add(unit)
        local name = ns.UnitName(unit)
        if not name then return end
        local key = ns.NameKey(name)
        if key ~= "" and not seen[key] then seen[key] = true names[#names + 1] = key end
    end
    if IsInRaid() then
        for i = 1, math.min(n, 40) do add("raid" .. i) end
    else
        add("player")
        for i = 1, math.min(n - 1, 4) do add("party" .. i) end
    end
    if #names < 2 then return "" end
    table.sort(names)
    local raw = table.concat(names, ",")
    return #raw <= 1500 and raw or ""
end
function Members.MyGroupState()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local inInst = ns.inInstance and ns.inInstance()
    if inInst then return "i" .. math.max(1, n) end
    if n > 1 then return "g" .. n end
    return ""
end
function Members.Status(name)
    local p = ns.db.members[name]
    if ns.isMe(name) then p = { gs = Members.MyGroupState(), seen = ns.now() } end
    if not p or not p.gs or p.gs == "" then return end
    if ns.now() - (p.seen or 0) > 900 then return end
    local kind, n = p.gs:match("^(%a)(%d+)$")
    if kind == "i" then return "inst", tonumber(n) end
    if kind == "g" then return "group", tonumber(n) end
end
-- kleines Symbol fuer die Gebietsspalte
function Members.StatusIcon(name, size)
    local kind, n = Members.Status(name)
    if not kind then return "", nil end
    local c = kind == "inst" and C.accent or C.amber
    local icon = ns.MEDIA .. "icons\\" .. (kind == "inst" and "dungeons" or "groups")
    local tex = ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(icon, size or 12, size or 12, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
    local txt = kind == "inst" and (L["im Dungeon (%d)"]):format(n or 1) or (L["in Gruppe (%d/5)"]):format(n or 2)
    return tex, txt
end

-- Status aenderung schnell an die Gilde (hoechstens alle 20 s)
local lastHello, pending = 0, false
local function helloSoon()
    if pending then return end
    local wait = math.max(1, 20 - (GetTime() - lastHello))
    pending = true
    ns.After(wait, function()
        pending = false
        lastHello = GetTime()
        if ns.Radar and IsInGuild() then pcall(ns.Radar.SendHello) end
    end)
end
local lastState
local function checkState()
    local s = Members.MyGroupState() .. ":" .. Members.MyGroupNames()
    if s ~= lastState then
        lastState = s
        if ns.Radar and ns.Radar.myProfileFresh then ns.Radar.myProfileFresh() end
        ns.RefreshPage("radar")
        helloSoon()
    end
end
ns.On("GROUP_ROSTER_UPDATE", checkState)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(3, checkState) end)

------------------------------------------------------------------------
-- Online-Aufstellung: Klassen und Rollen der Leute, die gerade da sind
------------------------------------------------------------------------
function Members.Composition()
    local classes, order = {}, {}
    local roles = { tank = 0, heal = 0, dps = 0, unknown = 0 }
    local total = 0
    for _, m in ipairs(ns.Radar.roster) do
        if m.online then
            total = total + 1
            local c = m.class or "?"
            if not classes[c] then classes[c] = 0 order[#order + 1] = c end
            classes[c] = classes[c] + 1
            local r, known
            if ns.Profile then r, known = ns.Profile.RolesOf(m.name) end
            if known then
                for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then roles[k] = roles[k] + 1 end end
            else
                roles.unknown = roles.unknown + 1
            end
        end
    end
    table.sort(order, function(a, b) if classes[a] ~= classes[b] then return classes[a] > classes[b] end return a < b end)
    return { total = total, classes = classes, order = order, roles = roles }
end

------------------------------------------------------------------------
-- Geburtstage und Jubilaeen
------------------------------------------------------------------------
function Members.ParseBirthday(s)
    local d, m = tostring(s or ""):match("^%s*(%d%d?)%.(%d%d?)%.?%s*$")
    d, m = tonumber(d), tonumber(m)
    if not d or not m or m < 1 or m > 12 or d < 1 or d > 31 then return end
    return ("%02d.%02d"):format(d, m)
end
function Members.Birthday(name)
    if ns.isMe(name) then return ns.db.settings.birthday end
    local p = ns.db.members[name]
    return p and p.gb ~= "" and p.gb or nil
end
function Members.IsBirthday(name)
    local b = Members.Birthday(name)
    return b and b == date("%d.%m", ns.now())
end
-- volle Monate/Jahre in der Gilde, falls heute ein Jubilaeum ist
function Members.Anniversary(name)
    local t = ns.Welcome and ns.Welcome.JoinedAt(name)
    if not t then return end
    local j, n = date("*t", t), date("*t", ns.now())
    if j.day ~= n.day then return end
    local months = (n.year - j.year) * 12 + (n.month - j.month)
    if months < 1 then return end
    if months % 12 == 0 then return (L["%d Jahr(e) in der Gilde"]):format(months / 12) end
    return (L["%d Monat(e) in der Gilde"]):format(months)
end
function Members.MemberSince(name)
    local t = ns.Welcome and ns.Welcome.JoinedAt(name)
    return t and date(L["%d.%m.%Y"], t)
end

-- einmal pro Tag nach dem Einloggen: wer hat heute Geburtstag/Jubilaeum
ns.GuildOption({ page = "radar", key = "mbBday", default = true, label = "Geburtstage und Jubilaeen melden",
    desc = "Einmal am Tag ein Hinweis, wer heute Geburtstag oder ein Gilden-Jubilaeum hat" })
local function announce()
    if ns.GuildOpt("mbBday") == false then return end
    local today = dayKey()
    if ns.db.meta and ns.db.meta.bdayShown == today then return end
    if ns.db.meta then ns.db.meta.bdayShown = today end
    for _, m in ipairs(ns.Radar.roster) do
        if Members.IsBirthday(m.name) and not ns.isMe(m.name) then
            ns.Sound.Next("birthday")
            K.Toast((L["%s hat heute Geburtstag!"]):format(ns.displayName(m.name)), L["Klick: gratulieren (Flüstern)"], C.pink, function()
                ns.Whisper(m.name, L["Alles Gute zum Geburtstag!"] .. " ")
            end)
        end
        local a = Members.Anniversary(m.name)
        if a then K.Toast(ns.displayName(m.name) .. ": " .. a, L["Schon so lange in der Gilde"], C.amber) end
    end
    if Members.IsBirthday(ns.me()) then ns.Sound.Next("birthday") K.Toast(L["Alles Gute zum Geburtstag!"], L["Die Oasis gratuliert."], C.pink) end
end

function Members.SetBirthday(s)
    if s == nil or s == "" then ns.db.settings.birthday = nil return true end
    local b = Members.ParseBirthday(s)
    if not b then return false end
    ns.db.settings.birthday = b
    helloSoon()
    return true
end
ns.slash.geburtstag = function(arg)
    if arg == "" or arg == nil then
        ns.print(L["Geburtstag: "] .. (ns.db.settings.birthday or "-") .. "  |cff888888(/oa geburtstag TT.MM)|r")
    elseif Members.SetBirthday(arg) then
        ns.print(L["Geburtstag gespeichert: "] .. ns.db.settings.birthday)
    else
        ns.print(L["Bitte als TT.MM angeben, z.B. /oa geburtstag 12.10"])
    end
end
ns.slash.birthday = ns.slash.geburtstag

------------------------------------------------------------------------
-- Offiziersnotiz (Blizzard-Gildenliste)
------------------------------------------------------------------------
function Members.CanSeeOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() end
    return CanViewOfficerNote and CanViewOfficerNote()
end
function Members.CanEditOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then return C_GuildInfo.CanEditOfficerNote() end
    return CanEditOfficerNote and CanEditOfficerNote()
end
-- nie die globale Tabelle selbst neu setzen (das "beruehrt" Blizzards Popups und blockiert Esc/Zauber)
StaticPopupDialogs.OASIS_OFFICER_NOTE = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Abbrechen",
    hasEditBox = true, maxLetters = 31, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetText(data and data.note or "") eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        if not (eb and data and data.index) then return end
        if C_GuildInfo and C_GuildInfo.SetNote then
            pcall(C_GuildInfo.SetNote, data.guid, eb:GetText(), false)
        elseif GuildRosterSetOfficerNote then
            pcall(GuildRosterSetOfficerNote, data.index, eb:GetText())
        end
        ns.After(1, function() if ns.Radar then ns.Radar.RequestRoster() end end)
    end,
}
function Members.EditOfficerNote(m)
    if not (m and m.index) then return end
    StaticPopup_Show("OASIS_OFFICER_NOTE", (L["Offiziersnotiz fuer %s"]):format(ns.displayName(m.name)), nil,
        { index = m.index, guid = m.guid, note = m.onote or "" })
end

------------------------------------------------------------------------
-- Rechtsklick-Menue einer Mitgliederzeile
------------------------------------------------------------------------
function Members.ShowMenu(owner, m)
    if not m then return end
    local me = ns.isMe(m.name)
    local I = ns.MEDIA .. "icons\\"
    -- Karte: Position ueber den Vornamen finden (Forever-Doppelnamen: Absender "Lena", Gildenliste
    -- "Lena Berg"), sonst wenigstens das Gebiet aus der Gildenliste
    local canMap = ns.Map and ns.Map.ShowMember and (me or (ns.Map.PosOf and ns.Map.PosOf(m.name)) or (m.online and (m.zone or "") ~= ""))
    local items = {
        { text = L["Profil anzeigen"], icon = I .. "profile", fn = function() if ns.Profile then ns.Profile.Show(m.name) end end },
        { text = L["Talente ansehen"], icon = I .. "stats", fn = function() if ns.Talents then ns.Talents.Show(m.name) end end },
        { text = L["Anfluestern"], icon = I .. "social", disabled = me or not m.online, fn = function() ns.Whisper(m.name) end },
        { text = L["In Gruppe einladen"], icon = I .. "groups", disabled = me or not m.online, fn = function()
            if m.demo then ns.print(L["(Demo) Einladung an "] .. ns.displayName(m.name)) return end
            if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(ns.ChatName(m.name)) elseif InviteUnit then InviteUnit(ns.ChatName(m.name)) end
        end },
        { text = L["Auf der Karte zeigen"], icon = I .. "map", disabled = not canMap, fn = function()
            if not ns.Map.ShowMember(m.name, m.zone) then ns.print(L["Position und Gebiet unbekannt."]) end
        end },
    }
    -- 0.6.469: Danke sagen und Pate werden (Modul Gemeinschaft)
    local CO = ns.Community
    if CO and not me and not m.demo then
        items[#items + 1] = { text = L["Danke sagen"], icon = I .. "heart", fn = function() CO.Thank(m.name, "") end }
        if ns.Welcome and ns.Welcome.IsNew and ns.Welcome.IsNew(m.name) and not CO.MentorOf(m.name) then
            items[#items + 1] = { text = L["Pate werden"], icon = I .. "groups", fn = function() CO.BecomeMentor(m.name) end }
        end
    end
    if Members.CanEditOfficerNote() and not m.demo and m.index then
        items[#items + 1] = { text = L["Offiziersnotiz bearbeiten"], icon = I .. "checklist", fn = function() Members.EditOfficerNote(m) end }
    end
    K.ShowMenu(owner, items, ns.colorName(m.name, m.class))
end

------------------------------------------------------------------------
-- Tooltip-Zeilen fuer die Mitgliederliste
------------------------------------------------------------------------
function Members.TooltipLines(m, lines)
    local today = Members.PlayToday(m.name)
    if today > 0 or m.online then
        lines[#lines + 1] = L["Heute online: "] .. Members.FmtDuration(today) .. "  |cff888888(" .. L["7 Tage: "] .. Members.FmtDuration(Members.PlayWeek(m.name)) .. ")|r"
    end
    local peak = Members.Peak(m.name)
    if peak then lines[#lines + 1] = L["Aktiv: "] .. peak end
    local gain = Members.LevelGain(m.name, 7, m.level)
    if gain > 0 then lines[#lines + 1] = "|cff66db9e" .. (L["+%d Level in 7 Tagen"]):format(gain) .. "|r" end
    local _, st = Members.StatusIcon(m.name)
    if st and m.online then lines[#lines + 1] = L["Gerade: "] .. st end
    if m.zone ~= "" and m.online and not ns.isMe(m.name) and m.zone == (ns.safe(GetRealZoneText()) or "") then
        lines[#lines + 1] = "|cff66db9e" .. L["Im selben Gebiet wie du"] .. "|r"
    end
    local shared = Members.SharedQuests(m.name)
    if #shared > 0 then
        lines[#lines + 1] = "|cffe8b44a" .. L["Gleiche Quests: "] .. "|r" .. table.concat(shared, ", ")
        if m.online then lines[#lines + 1] = "|cff888888" .. L["Das gelbe Ausrufezeichen am Symbol zeigt das an."] .. "|r" end
    end
    local b = Members.Birthday(m.name)
    if b then lines[#lines + 1] = L["Geburtstag: "] .. b .. (Members.IsBirthday(m.name) and ("  |cffff77aa" .. L["heute!"] .. "|r") or "") end
    local since = Members.MemberSince(m.name)
    if since then lines[#lines + 1] = L["In der Gilde seit "] .. since end
    if (m.onote or "") ~= "" and (m.demo or Members.CanSeeOfficerNote()) then
        lines[#lines + 1] = "|cffff7a5c" .. L["Offiziersnotiz: "] .. "|r" .. m.onote
    end
end

-- Quests, die ich und das Mitglied gerade beide haben
local partnerCache, partnerTime = {}, 0
function Members.SharedQuests(name)
    if not ns.Social then return {} end
    if GetTime() - partnerTime > 5 then
        partnerCache, partnerTime = {}, GetTime()
        local ok, list = pcall(ns.Social.Partners)
        if ok then
            for _, e in ipairs(list) do
                for _, who in ipairs(e.online) do
                    partnerCache[who] = partnerCache[who] or {}
                    table.insert(partnerCache[who], e.q.title)
                end
                for _, who in ipairs(e.offline) do
                    partnerCache[who] = partnerCache[who] or {}
                    table.insert(partnerCache[who], e.q.title)
                end
            end
        end
    end
    return partnerCache[name] or {}
end

ns.Listen("LOGIN", function()
    pcall(prune)
    ns.After(25, function() pcall(announce) end)
end)

-- Oasis: Gilden-Historie (wie Guild Roster Manager)
--  * Abgleich der Gildenliste: Beitritte, Austritte, Rangwechsel und Notiz-Aenderungen werden auch dann
--    erkannt, wenn niemand mit Oasis die Systemmeldung gesehen hat (Vergleich mit dem letzten Stand)
--  * Ehemalige (Store "formers"): wer wann mit welchem Rang/Level ging; Rueckkehrer werden gemeldet
--  * Verlauf je Mitglied: Beitritt, Rangwechsel, Tage im aktuellen Rang, fruehere Mitgliedschaften
--  * Befoerderung faellig: aktive Mitglieder, die lange genug im Rang sind (Gilden-Option)
-- Reiter in der Gildenleitung > Mitglieder: Verlauf, Ehemalige, Befoerderung.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
-- Sicherheit beim Empfang (Addon-Nachrichten anderer koennen manipuliert sein):
-- Texte entschaerfen, Zahlen begrenzen, Namen pruefen, Flut drosseln
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape-Sequenzen (|c |r |n |H |T |K |A ...) und Steuerzeichen unschaedlich; links: gueltige Item-/Zauberlinks bleiben
    function SEC.Text(s, max, links)
        if s == nil then return "" end
        s = tostring(s):gsub("[%z\1-\31\127]", " ")
        local keep
        if links then
            keep = {}
            s = s:gsub("(|c([^|]-)|H(%a+):([^|]*)|h(%[[^|%]]*%])|h|r)", function(all, col, kind, data)
                if #keep < 8 and (kind == "item" or kind == "spell") and data:match("^[%d:%-]+$")
                    and (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then
                    keep[#keep + 1] = all
                    return "\1" .. #keep .. "\2"
                end
            end)
        end
        s = cut((s:gsub("|", "/")), max)
        if keep then s = s:gsub("\1%d*$", ""):gsub("\1(%d+)\2", function(i) return keep[tonumber(i)] or "" end) end
        return s
    end
    function SEC.Link(s)
        if type(s) ~= "string" or #s > 300 then return nil end
        local col = s:match("^|c([^|]-)|Hitem:[%d:%-]+|h%[[^|%]]*%]|h|r$")
        if not col or not (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then return nil end
        return s
    end
    function SEC.Num(v, lo, hi, int)
        v = tonumber(v)
        if not v or v ~= v or v < lo or v > hi then return nil end
        if int then v = math.floor(v) end
        return v
    end
    function SEC.Name(s)
        if type(s) ~= "string" or s == "" or #s > 64 or s:find("[|%c]") then return nil end
        return s
    end
    local last, lastN = {}, 0
    function SEC.Rate(key, sec)
        local now = GetTime()
        local t = last[key]
        if t and now - t < sec then return false end
        if not t then lastN = lastN + 1 if lastN > 500 then last, lastN = {}, 0 end end
        last[key] = now
        return true
    end
end
local O = ns.Officer

local GH = {}
ns.GuildHistory = GH

ns.GuildOption({ page = "radar", key = "ghPromo", default = 30, min = 0, max = 180, step = 5,
    label = "Befoerderung vorschlagen nach", desc = "Aktive Mitglieder unterhalb der Offiziersraenge erscheinen nach so vielen Tagen im selben Rang in der Liste 'Befoerderung'. 0 = aus.",
    fmt = function(v) return v == 0 and ns.L["aus"] or (v .. " " .. ns.L["Tage"]) end })
ns.GuildOption({ page = "radar", key = "ghReturn", default = true,
    label = "Rueckkehrer melden", desc = "Kommt ein ehemaliges Mitglied zurueck, bekommt die Gildenleitung einen Hinweis mit dem frueheren Rang und Austrittsdatum." })

local DAY = 86400
local function key(name) return ns.NameKey(name) end
local function dayStr(t) return date("%Y%m%d", t or ns.now()) end
local function isLead() return ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() end

------------------------------------------------------------------------
-- Protokoll-Eintraege aus dem Abgleich
------------------------------------------------------------------------
-- gibt es schon einen Eintrag aus der Systemmeldung (oder einem anderen Abgleich) fuer diese Person?
local function recentAudit(kinds, name, since)
    local k = key(name)
    for _, r in ipairs(Store.List("audit")) do
        if kinds[r.kind] and (r.ts or 0) >= since then
            if key(r.a) == k or key(r.b) == k then return r end
        end
    end
end
local function put(kind, name, extra)
    local id = "scan:" .. kind .. ":" .. key(name) .. ":" .. dayStr()
    if Store.Get("audit", id) then return end
    local r = { id = id, kind = kind, a = ns.short(name), b = "", r = "", ts = ns.now(), src = "scan" }
    for k, v in pairs(extra or {}) do r[k] = v end
    Store.Put("audit", r)
end

-- Text fuer die neuen Arten (scan-Eintraege) ergaenzen
local baseText = O.AuditText
function O.AuditText(r)
    if r.kind == "rankup" then return (L["%s ist jetzt %s (vorher %s)"]):format(r.a, r.r, r.b)
    elseif r.kind == "rankdown" then return (L["%s ist jetzt %s (vorher %s)"]):format(r.a, r.r, r.b)
    elseif r.kind == "gone" then return (L["%s ist nicht mehr in der Gilde"]):format(r.a)
    elseif r.kind == "note" then return (L["Notiz von %s: %s"]):format(r.a, r.r ~= "" and r.r or L["(geloescht)"])
    elseif r.kind == "rejoin" then return (L["%s ist zurueck (war %s, ging am %s)"]):format(r.a, r.b, r.r)
    end
    return baseText(r)
end
if O.KIND_COL then
    O.KIND_COL.rankup, O.KIND_COL.rankdown, O.KIND_COL.gone = C.mint, C.amber, C.dim
    O.KIND_COL.note, O.KIND_COL.rejoin = C.muted, C.blue
end

------------------------------------------------------------------------
-- Abgleich der Gildenliste
------------------------------------------------------------------------
local function snap()
    ns.db.rsnap = ns.db.rsnap or {}
    return ns.db.rsnap
end
function GH.Former(name)
    local r = Store.Get("formers", "fm-" .. key(name))
    if r and not r.del then return r end
    for _, old in ipairs(Store.List("formers")) do
        if not old.del and ns.SameName(old.full or old.name, name) then return old end
    end
end

local function compare()
    if not IsInGuild() or not ns.Radar then return end
    local roster = ns.Radar.roster or {}
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    -- nur bei vollstaendiger Liste vergleichen (sonst wuerden "fehlende" als Austritte gelten)
    if #roster == 0 or #roster < total or (ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive()) then return end
    local guild = GetGuildInfo("player")
    local s = snap()
    if s.__guild and s.__guild ~= guild then wipe(s) end
    local first = s.__guild == nil
    s.__guild = guild
    local now = ns.now()
    local here = {}
    for _, m in ipairs(roster) do
        local k = key(m.name)
        here[k] = true
        local o = s[k]
        if not o then
            if not first then
                local fm = GH.Former(m.name)
                if fm then
                    put("rejoin", m.name, { b = fm.rank or "?", r = date(L["%d.%m.%Y"], fm.left or 0) })
                    if ns.GuildOpt("ghReturn") ~= false and isLead() then
                        K.Toast((L["%s ist zurueck"]):format(ns.displayName(m.name)),
                            (L["War %s, Level %d, ging am %s"]):format(fm.rank or "?", fm.lvl or 0, date(L["%d.%m.%Y"], fm.left or 0)), C.blue)
                    end
                    local c = {} for kk, v in pairs(fm) do c[kk] = v end
                    c.back = (c.back or 0) + 1
                    c.returned = now
                    Store.Put("formers", c)
                elseif not recentAudit({ join = true }, m.name, now - 2 * DAY) then
                    put("join", m.name)
                end
            end
            s[k] = { n = m.name, ri = m.rankIndex, rank = m.rank, lvl = m.level, note = m.note, cls = m.class, first = first and 0 or now, since = first and 0 or now }
        else
            if o.ri ~= m.rankIndex and m.rankIndex then
                if not recentAudit({ promote = true, demote = true }, m.name, now - DAY) then
                    put(m.rankIndex < (o.ri or 99) and "rankup" or "rankdown", m.name, { b = o.rank or "?", r = m.rank or "?" })
                end
                o.ri, o.rank, o.since = m.rankIndex, m.rank, now
            end
            if (o.note or "") ~= (m.note or "") then
                if not first then put("note", m.name, { b = o.note or "", r = m.note or "" }) end
                o.note = m.note
            end
            o.lvl, o.cls, o.n = m.level, m.class, m.name
        end
        s[k].seen = now
    end
    -- weg: Ehemalige anlegen
    for k, o in pairs(s) do
        if k ~= "__guild" and type(o) == "table" and not here[k] then
            local kicked = recentAudit({ kick = true }, o.n, now - 2 * DAY)
            local left = recentAudit({ leave = true }, o.n, now - 2 * DAY)
            if not kicked and not left then put("gone", o.n) end
            local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(o.n) or o.n
            Store.Put("formers", { id = "fm-" .. k, name = ns.short(o.n), full = o.n, rank = o.rank, lvl = o.lvl, cls = o.cls,
                note = o.note, joined = (o.first and o.first > 0) and o.first or nil, left = now,
                how = kicked and "kick" or (left and "leave" or "?"), by = kicked and kicked.b or nil,
                main = main ~= o.n and ns.short(main) or nil })
            s[k] = nil
        end
    end
end
ns.Listen("ROSTER", function() pcall(compare) end)

------------------------------------------------------------------------
-- Auswertungen
------------------------------------------------------------------------
-- Verlauf einer Person (neueste zuerst)
function GH.Timeline(name)
    local k = key(name)
    local out = {}
    for _, r in ipairs(Store.List("audit")) do
        if key(r.a) == k or key(r.b) == k then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end
-- seit wann im aktuellen Rang / in der Gilde (nil = unbekannt, vor Oasis)
function GH.RankSince(name)
    local o = snap()[key(name)]
    local best = o and o.since and o.since > 0 and o.since or nil
    for _, r in ipairs(GH.Timeline(name)) do
        local target = (r.kind == "promote" or r.kind == "demote") and r.b or r.a
        if key(target) == key(name) and (r.kind == "promote" or r.kind == "demote" or r.kind == "rankup" or r.kind == "rankdown" or r.kind == "join" or r.kind == "rejoin") then
            if not best or (r.ts or 0) > best then best = r.ts end
            break
        end
    end
    return best
end
function GH.JoinedAt(name)
    local first
    for _, r in ipairs(GH.Timeline(name)) do
        if (r.kind == "join" or r.kind == "rejoin") and key(r.a) == key(name) then first = r.ts end
    end
    if first then return first end
    local o = snap()[key(name)]
    return o and o.first and o.first > 0 and o.first or nil
end
function GH.Formers()
    local list = Store.List("formers", function(r) return not r.returned or (r.left or 0) > (r.returned or 0) end)
    table.sort(list, function(a, b) return (a.left or 0) > (b.left or 0) end)
    return list
end
-- aktive Mitglieder unterhalb der Leitung, lange genug im Rang
function GH.PromoDue()
    local days = tonumber(ns.GuildOpt("ghPromo")) or 30
    if days <= 0 then return {} end
    local leadRank = (ns.Admin and ns.Admin.LeaderRank and ns.Admin.LeaderRank()) or 1
    local out = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        if (m.rankIndex or 0) > leadRank and not isAlt and (m.online or (m.offDays or 99) < 7) then
            local since = GH.RankSince(m.name)
            local d = since and math.floor((ns.now() - since) / DAY)
            if d and d >= days then out[#out + 1] = { m = m, days = d } end
        end
    end
    table.sort(out, function(a, b) return a.days > b.days end)
    return out
end

------------------------------------------------------------------------
-- Eigene Notizen je Mitglied (wie GRM): laenger als Blizzards Notizfeld, nur fuer Offiziere.
-- Laufen ueber den Offizierskanal (Blizzard stellt ihn nur Offizieren zu), nicht ueber die Gilde.
------------------------------------------------------------------------
local Comm = ns.Comm
local function notes() ns.db.mnotes = ns.db.mnotes or {} return ns.db.mnotes end
local function isOfficer()
    if ns.db.settings.adminTest ~= false and ns.IsDev() then return true end
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end
GH.CanNotes = isOfficer
function GH.Note(name) return notes()[key(name)] end
function GH.SetNote(name, text)
    if not isOfficer() then return end
    text = (text or ""):sub(1, 500)
    local n = { t = text, by = ns.me(), u = ns.now() }
    notes()[key(name)] = n
    Comm.Send("OFFICER", nil, "MNOTE", key(name), n.u, n.by, (text:gsub("[%c]", " ")))
end
Comm.On("MNOTE", function(sender, channel, k, u, by, text)
    if channel ~= "OFFICER" or not k then return end
    -- Zeitstempel nicht in der Zukunft (sonst nie mehr aenderbar), Text entschaerft, Menge begrenzt
    -- (Verfasser bleibt beim Weiterreichen erhalten; der Offizierskanal erreicht nur Offiziere)
    u = math.min(SEC.Num(u, 0, 4102444800) or 0, ns.now() + 300)
    k = SEC.Text(k, 80)
    local old = notes()[k]
    if old and (old.u or 0) >= u then return end
    if not old then
        local n = 0
        for _ in pairs(notes()) do n = n + 1 end
        if n >= 3000 then return end
    end
    notes()[k] = { t = SEC.Text(text, 500), by = SEC.Name(by) or sender, u = u }
    ns.RefreshPage("admin")
end)
-- beim Einloggen: fehlende Notizen bei den anderen Offizieren anfragen
Comm.On("MNREQ", function(sender, channel, since)
    if channel ~= "OFFICER" or not isOfficer() then return end
    if not SEC.Rate("mnreq:" .. tostring(sender), 60) then return end
    since = tonumber(since) or 0
    local n = 0
    for k, v in pairs(notes()) do
        if (v.u or 0) > since and n < 60 then
            n = n + 1
            Comm.Send("OFFICER", nil, "MNOTE", k, v.u, v.by or "", ((v.t or ""):gsub("[%c]", " ")))
        end
    end
end)
ns.Listen("LOGIN", function()
    ns.After(25 + math.random(0, 20), function()
        if not (IsInGuild() and isOfficer()) then return end
        local newest = 0
        for _, v in pairs(notes()) do if (v.u or 0) > newest then newest = v.u end end
        Comm.Send("OFFICER", nil, "MNREQ", newest)
    end)
end)

------------------------------------------------------------------------
-- Reiter in der Gildenleitung
------------------------------------------------------------------------
local function ago(t)
    if not t then return "|cff666666?|r" end
    local d = math.floor((ns.now() - t) / DAY)
    return d <= 0 and L["heute"] or (L["%d Tage"]):format(d)
end
local function head(f, x, y, text, w, j)
    local t = K.Text(f, 10, C.dim, j or "LEFT")
    t:SetPoint("TOPLEFT", x, y)
    if w then t:SetWidth(w) end
    t:SetText(K.Upper(L[text]))
    return t
end

-- Verlauf: links Mitglieder (Rang, im Rang seit, in der Gilde seit), rechts Zeitleiste
O.BUILD.history = function(f)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("TOPLEFT", 0, 0)
    n:SetText(L["Beitritte, Rangwechsel und Notizen je Mitglied - aus Systemmeldungen und dem Abgleich der Gildenliste (auch wenn niemand online war)."])
    f.search = K.Input(f, 200, L["Name suchen"], function() O.Refresh() end)
    f.search:SetPoint("TOPLEFT", 0, -20)
    head(f, 10, -54, "Name") head(f, 170, -54, "Rang") head(f, 270, -54, "im Rang") head(f, 340, -54, "dabei seit")
    f.list = K.List(f, 24, function(l)
        local r = K.Row(l)
        r:Col("name", 10, 155, 12) r:Col("rank", 170, 95, 11, C.muted) r:Col("inrank", 270, 65, 11) r:Col("since", 340, 70, 11, C.muted)
        r.noteIc = K.Glyph(r, 12, ns.MEDIA .. "icons\\brush", C.amber)
        r.noteIc:SetPoint("RIGHT", -6, 0)
        r:SetScript("OnClick", function(self) f.sel = self.item and self.item.name O.Refresh() end)
        return r
    end, function(r, m)
        r.cols.name:SetText(ns.Radar.Colored(m.name))
        r.cols.rank:SetText(m.rank or "")
        r.cols.inrank:SetText(ago(GH.RankSince(m.name)))
        local j = GH.JoinedAt(m.name)
        r.cols.since:SetText(j and date(L["%d.%m.%y"], j) or "|cff666666?|r")
        local nt = GH.CanNotes() and GH.Note(m.name)
        r.noteIc:SetShown(nt and nt.t ~= "" or false)
        r.sel:SetShown(f.sel == m.name)
    end)
    f.list:SetPoint("TOPLEFT", 0, -70)
    f.list:SetPoint("BOTTOMLEFT", 0, 0)
    f.list:SetWidth(430)
    -- rechts
    f.card = K.Panel(f, C.panel)
    f.card:SetPoint("TOPLEFT", 446, -20)
    f.card:SetPoint("BOTTOMRIGHT", 0, 0)
    f.who = K.Title(f.card, 15, C.text)
    f.who:SetPoint("TOPLEFT", 14, -12)
    f.sub = K.Text(f.card, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", 14, -34)
    f.sub:SetPoint("RIGHT", f.card, "RIGHT", -14, 0)
    f.sub:SetWordWrap(true)
    f.tl = K.List(f.card, 22, function(l)
        local r = K.Row(l)
        r:Col("when", 8, 90, 11, C.dim) r:Col("text", 100, 300, 12)
        return r
    end, function(r, e)
        r.cols.when:SetText(date(L["%d.%m.%y"], e.ts or 0))
        local c = O.KIND_COL and O.KIND_COL[e.kind] or C.text
        r.cols.text:SetText(K.hex(c) .. O.AuditText(e) .. "|r" .. (e.src == "scan" and "  |cff555555(" .. L["Abgleich"] .. ")|r" or ""))
    end)
    f.tl:SetPoint("TOPLEFT", 6, -76)
    f.tl:SetPoint("BOTTOMRIGHT", -6, 118)
    f.tl.empty:SetText(L["Noch nichts aufgezeichnet."])
    -- eigene Notiz (nur Offiziere)
    f.noteHead = K.Text(f.card, 10, C.dim)
    f.noteHead:SetPoint("BOTTOMLEFT", 14, 96)
    f.noteHead:SetText(K.Upper(L["Notiz der Gildenleitung"]))
    f.noteBy = K.Text(f.card, 10, C.dim, "RIGHT")
    f.noteBy:SetPoint("BOTTOMRIGHT", -14, 96)
    f.note = CreateFrame("EditBox", nil, f.card)
    f.note:SetMultiLine(true)
    f.note:SetAutoFocus(false)
    f.note:SetFont(K.FONT, 12, "")
    f.note:SetTextColor(C.text[1], C.text[2], C.text[3])
    f.note:SetMaxLetters(500)
    f.note:SetPoint("TOPLEFT", f.card, "BOTTOMLEFT", 14, 88)
    f.note:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -120, 12)
    f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local nbg = f.card:CreateTexture(nil, "BACKGROUND", nil, 2)
    nbg:SetPoint("TOPLEFT", f.note, -6, 4) nbg:SetPoint("BOTTOMRIGHT", f.note, 6, -4)
    nbg:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
    f.noteSave = K.Button(f.card, L["Speichern"], 96, 24, "primary", function()
        if f.sel then GH.SetNote(f.sel, f.note:GetText()) f.note:ClearFocus() O.Refresh() end
    end)
    f.noteSave:SetPoint("BOTTOMRIGHT", -12, 12)
    f.noteLock = K.Text(f.card, 11, C.dim)
    f.noteLock:SetPoint("BOTTOMLEFT", 14, 40)
    f.noteLock:SetText(L["Notizen sehen und schreiben nur Offiziere."])
end
O.REFRESH.history = function(f)
    local q = (f.search:GetText() or ""):lower()
    local list = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        if q == "" or ns.displayName(m.name):lower():find(q, 1, true) then list[#list + 1] = m end
    end
    table.sort(list, function(a, b)
        if (a.rankIndex or 99) ~= (b.rankIndex or 99) then return (a.rankIndex or 99) < (b.rankIndex or 99) end
        return a.name < b.name
    end)
    f.list:SetData(list)
    local name = f.sel or (list[1] and list[1].name)
    f.sel = name
    if not name then f.who:SetText("") f.sub:SetText("") f.tl:SetData({}) return end
    local m = ns.Radar.byName[name]
    f.who:SetText(ns.Radar.Colored(name))
    local parts = {}
    if m then parts[#parts + 1] = (m.rank or "") .. "  ·  " .. (L["Level %d"]):format(m.level or 0) end
    local j = GH.JoinedAt(name)
    parts[#parts + 1] = L["dabei seit"] .. " " .. (j and date(L["%d.%m.%Y"], j) or L["vor Oasis"])
    parts[#parts + 1] = L["im Rang"] .. " " .. ago(GH.RankSince(name))
    local fm = GH.Former(name)
    if fm then parts[#parts + 1] = "|cff6199ff" .. (L["war schon einmal da (bis %s)"]):format(date(L["%d.%m.%Y"], fm.left or 0)) .. "|r" end
    local alts = ns.Alts and ns.Alts.CharsOf and ns.Alts.CharsOf(ns.Alts.Main(name)) or {}
    if #alts > 1 then
        local t = {}
        for _, a in ipairs(alts) do if a ~= name then t[#t + 1] = ns.displayName(a) end end
        if #t > 0 then parts[#parts + 1] = L["Twinks"] .. ": " .. table.concat(t, ", ") end
    end
    f.sub:SetText(table.concat(parts, "   ·   "))
    f.tl:SetData(GH.Timeline(name))
    local can = GH.CanNotes()
    f.note:SetShown(can) f.noteSave:SetShown(can) f.noteBy:SetShown(can) f.noteLock:SetShown(not can)
    if can then
        local n = GH.Note(name)
        if not f.note:HasFocus() and f.noteFor ~= name .. ":" .. tostring(n and n.u) then
            f.noteFor = name .. ":" .. tostring(n and n.u)
            f.note:SetText(n and n.t or "")
        end
        f.noteBy:SetText(n and n.u and ((L["%s, %s"]):format(ns.displayName(n.by or "?"), date(L["%d.%m.%y"], n.u))) or "")
    end
end

-- Ehemalige
O.BUILD.formers = function(f)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("TOPLEFT", 0, 0)
    n:SetText(L["Wer die Gilde verlassen hat oder entfernt wurde. Kommt jemand zurueck, meldet Oasis das der Gildenleitung."])
    head(f, 10, -24, "Name") head(f, 170, -24, "Rang") head(f, 270, -24, "Level") head(f, 320, -24, "gegangen")
    head(f, 410, -24, "wie") head(f, 520, -24, "Notiz")
    f.list = K.List(f, 24, function(l)
        local r = K.Row(l)
        r:Col("name", 10, 155, 12) r:Col("rank", 170, 95, 11, C.muted) r:Col("lvl", 270, 45, 11)
        r:Col("left", 320, 85, 11, C.muted) r:Col("how", 410, 105, 11) r:Col("note", 520, 230, 11, C.dim)
        r:SetScript("OnEnter", function(self)
            local e = self.item
            if not e then return end
            local lines = { ns.colorName(e.name or "?", e.cls) }
            if e.main then lines[#lines + 1] = L["Twink von"] .. " " .. e.main end
            if e.joined then lines[#lines + 1] = L["dabei seit"] .. " " .. date(L["%d.%m.%Y"], e.joined) end
            if e.back then lines[#lines + 1] = (L["schon %dx zurueckgekommen"]):format(e.back) end
            local ban = O.BanOf and O.BanOf(e.name)
            if ban then lines[#lines + 1] = "|cffff5a4a" .. L["Oasis-Bannliste"] .. "|r" end
            K.ShowTip(self, lines)
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e)
        r.cols.name:SetText(ns.colorName(e.name or "?", e.cls))
        r.cols.rank:SetText(e.rank or "")
        r.cols.lvl:SetText(e.lvl or "")
        r.cols.left:SetText(date(L["%d.%m.%y"], e.left or 0))
        local how = e.how == "kick" and ("|cffe64047" .. L["entfernt"] .. (e.by and e.by ~= "" and (" (" .. e.by .. ")") or "") .. "|r")
            or e.how == "leave" and L["selbst gegangen"] or "|cff888888" .. L["unbekannt"] .. "|r"
        r.cols.how:SetText(how)
        r.cols.note:SetText(e.note or "")
    end)
    f.list:SetPoint("TOPLEFT", 0, -40)
    f.list:SetPoint("BOTTOMRIGHT", 0, 0)
    f.list.empty:SetText(L["Noch niemand gegangen, seit Oasis mitschreibt."])
end
O.REFRESH.formers = function(f) f.list:SetData(GH.Formers()) end

-- Befoerderung faellig
O.BUILD.promo = function(f)
    f.hint = K.Text(f, 10, C.dim)
    f.hint:SetPoint("TOPLEFT", 0, 0)
    head(f, 10, -24, "Name") head(f, 170, -24, "Rang") head(f, 270, -24, "im Rang") head(f, 350, -24, "Level")
    head(f, 410, -24, "Anwesenheit")
    f.list = K.List(f, 26, function(l)
        local r = K.Row(l)
        r:Col("name", 10, 155, 12) r:Col("rank", 170, 95, 11, C.muted) r:Col("days", 270, 75, 11, C.amber)
        r:Col("lvl", 350, 55, 11) r:Col("att", 410, 90, 11, C.muted)
        r.up = K.Button(r, L["Befoerdern"], 96, 20, "primary")
        r.up:SetPoint("RIGHT", -6, 0)
        return r
    end, function(r, e)
        local m = e.m
        r.cols.name:SetText(ns.Radar.Colored(m.name))
        r.cols.rank:SetText(m.rank or "")
        r.cols.days:SetText((L["%d Tage"]):format(e.days))
        r.cols.lvl:SetText(m.level or "")
        local rate = O.Attendance and O.Attendance(m.name)
        r.cols.att:SetText(rate and (math.floor(rate * 100) .. " %") or "|cff555555-|r")
        r.up:SetShown(GuildPromote ~= nil)
        r.up:SetScript("OnClick", function()
            local ok = pcall(GuildPromote, ns.ChatName and ns.ChatName(m.name) or ns.short(m.name))
            if not ok then ns.print(L["Befoerdern hat nicht geklappt - fehlt dir das Recht?"]) end
            ns.After(1, function() if ns.Radar.RequestRoster then ns.Radar.RequestRoster() end end)
        end)
    end)
    f.list:SetPoint("TOPLEFT", 0, -40)
    f.list:SetPoint("BOTTOMRIGHT", 0, 0)
end
O.REFRESH.promo = function(f)
    local days = tonumber(ns.GuildOpt("ghPromo")) or 30
    f.hint:SetText(days > 0 and (L["Aktive Mitglieder (letzte 7 Tage online), die seit mindestens %d Tagen im selben Rang sind. Zeitraum: Gildenleitung > Module > Mitglieder."]):format(days)
        or L["Ausgeschaltet - in der Gildenleitung unter Module > Mitglieder einen Zeitraum einstellen."])
    f.list:SetData(GH.PromoDue())
    f.list.empty:SetText(L["Gerade ist niemand faellig."])
end
O.TEXT.history, O.TEXT.formers, O.TEXT.promo = "Verlauf", "Ehemalige", "Befoerderung"

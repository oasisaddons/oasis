-- Oasis: Umfragen ("Raid Mittwoch oder Donnerstag?")
local ADDON, ns = ...
ns.ModuleFile("Oasis_Umfragen", function()   -- Modul Umfragen (abschaltbar, siehe ModuleLoader.lua)
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

local Polls = {}
ns.Polls = Polls

local MAXOPT = 6

-- Gilden-Optionen (Gildenleitung): wer darf Umfragen starten, duerfen Offiziere fremde verwalten
ns.GuildOption({ page = "polls", key = "plOffEd", default = true,
    label = "Offiziere verwalten fremde Umfragen", desc = "Offiziere duerfen Umfragen anderer beenden, verlaengern, posten und loeschen. Aus: nur der Ersteller und die Gildenleitung." })
local function canManage() return ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() or false end
local function rankAllowed(limit)
    if not limit or limit >= 10 then return true end
    if canManage() then return true end
    local ri = ns.Admin and ns.Admin.RankOf and ns.Admin.RankOf(ns.me())
    return ri == nil or ri < limit
end
-- Umfragen starten duerfen nur Offiziere und die Gildenleitung
function Polls.CanCreate() return canManage() or ns.isOfficer() end

------------------------------------------------------------------------
-- Daten: Umfrage = { q, o1..o6, multi, exp, closed }, Stimme = { poll, who, pick = "1,3" }
-- Eine Stimme pro Spieler (Main), Twinks zaehlen nicht doppelt.
------------------------------------------------------------------------
local function voter() return ns.Alts and ns.Alts.MyMain() or ns.me() end
-- 0.5.617: geheime Umfrage (poll.anon) - Stimme in "avotes" ohne Namen, nur mit zufaelligem Kennzeichen,
-- das der Account sich merkt (Twinks desselben Accounts stimmen also nicht doppelt ab)
local function token(pollId)
    ns.db.pollTok = ns.db.pollTok or {}
    local t = ns.db.pollTok[pollId]
    if not t then
        t = ("%08x%08x"):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
        ns.db.pollTok[pollId] = t
    end
    return t
end
local function voteColl(p) return p.anon and "avotes" or "votes" end
local function voteId(p) return p.id .. "@" .. (p.anon and token(p.id) or voter()) end

function Polls.Options(p)
    local out = {}
    for i = 1, MAXOPT do
        local o = p["o" .. i]
        if o and o ~= "" then out[#out + 1] = { idx = i, text = o } end
    end
    return out
end
function Polls.IsOpen(p) return not p.closed and (p.exp or 0) > ns.now() end

function Polls.All()
    local out = Store.List("polls")
    table.sort(out, function(a, b)
        local oa, ob = Polls.IsOpen(a), Polls.IsOpen(b)
        if oa ~= ob then return oa end
        return (a.created or a.u or 0) > (b.created or b.u or 0)
    end)
    return out
end

-- Ergebnis: counts[idx], total Stimmen, voters[idx] = { namen }
function Polls.Result(p)
    local counts, voters, total = {}, {}, 0
    -- 0.5.624: geheime Umfrage zaehlt auch Stimmen alter Versionen (die schreiben noch in "votes") - Namen nur bei p.names
    local list = Store.List(voteColl(p), function(v) return v.poll == p.id end)
    if p.anon then for _, v in ipairs(Store.List("votes", function(v) return v.poll == p.id end)) do list[#list + 1] = v end end
    for _, v in ipairs(list) do
        if (v.pick or "") ~= "" then
            total = total + 1
            for idx in v.pick:gmatch("%d+") do
                idx = tonumber(idx)
                counts[idx] = (counts[idx] or 0) + 1
                voters[idx] = voters[idx] or {}
                if v.who and p.names then table.insert(voters[idx], v.who) end
            end
        end
    end
    return counts, total, voters
end

function Polls.MyPick(p)
    local v = Store.Get(voteColl(p), voteId(p))
    local set = {}
    if v and v.pick then for idx in v.pick:gmatch("%d+") do set[tonumber(idx)] = true end end
    return set
end

function Polls.Vote(p, idx)
    if not Polls.IsOpen(p) then return end
    local set = Polls.MyPick(p)
    if p.multi then
        set[idx] = not set[idx] or nil
    else
        local had = set[idx]
        set = {}
        if not had then set[idx] = true end
    end
    local t = {}
    for i in pairs(set) do t[#t + 1] = tostring(i) end
    table.sort(t)
    local old = Store.Get(voteColl(p), voteId(p))
    if p.anon then
        Store.Put("avotes", { id = voteId(p), poll = p.id, pick = table.concat(t, ","), u = old and old.u or nil })
    else
        Store.Put("votes", { id = voteId(p), poll = p.id, who = voter(), pick = table.concat(t, ","), u = old and old.u or nil })
    end
    if not old and ns.Badges and not tostring(p.id):find("demo-", 1, true) then ns.Badges.Add("votes", 1) end
end

function Polls.Create(q, opts, multi, dur, anon)
    if not Polls.CanCreate() then ns.print(L["Umfragen koennen nur Offiziere und die Gildenleitung starten."]) return end
    local rec = { id = ns.newId("poll"), q = q, multi = multi and true or false, anon = anon and true or nil, names = (not anon) or nil, exp = ns.now() + dur, created = ns.now() }
    local n = 0
    for _, o in ipairs(opts) do
        o = o:gsub("^%s+", ""):gsub("%s+$", "")
        if o ~= "" and n < MAXOPT then
            n = n + 1
            rec["o" .. n] = o
        end
    end
    if q == "" or n < 2 then ns.print(L["Eine Frage und mindestens zwei Antworten angeben."]) return end
    return Store.Put("polls", rec)
end
function Polls.Close(p)
    local r = {}
    for k, v in pairs(p) do r[k] = v end
    r.closed = true
    Store.Put("polls", r)
end

local function updateBadge()
    local n = 0
    for _, p in ipairs(Polls.All()) do
        if Polls.IsOpen(p) and not next(Polls.MyPick(p)) then n = n + 1 end
    end
    if ns.db.settings.pollBadge == false then n = 0 end
    ns.SetNavBadge("polls", n > 0 and tostring(n) or "")
end
Polls.UpdateBadge = updateBadge

ns.Listen("STORE", function(coll, rec, old)
    if coll == "polls" then
        if not old and not rec.del and not ns.isMe(rec.by) and Polls.IsOpen(rec) then
            ns.Sound.Next("poll")
            K.Toast(L["Neue Umfrage"], SEC.Text(rec.q or "?", 120), C.accent, function()
                Polls.selected = rec.id
                ns.ShowPage("polls")
            end)
        end
        ns.Debounce("pollStore", 0.4, function() updateBadge() ns.RefreshPage("polls") end)
    elseif coll == "votes" or coll == "avotes" then
        ns.Debounce("pollStore", 0.4, function() updateBadge() ns.RefreshPage("polls") end)
    end
end)

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local creating = false
local multi, durIdx, customHours = false, 4, nil
local secret = true   -- 0.5.617: neue Umfragen standardmaessig geheim
local DUR = {
    { 1800, "30 Min" }, { 3600, "1 Std" }, { 3 * 3600, "3 Std" }, { 86400, "1 Tag" }, { 3 * 86400, "3 Tage" }, { 7 * 86400, "1 Woche" },
}
local function chosenDuration()
    if customHours and customHours > 0 then return math.floor(customHours * 3600) end
    return DUR[durIdx][1]
end

-- "noch 2 Tg 3 Std" / "noch 3:12 Std" / "noch 12 Min"
local function remaining(p, precise)
    if p.closed then return L["beendet"] end
    local d = math.floor((p.exp or 0) - ns.now())
    if d <= 0 then return L["beendet"] end
    if precise then
        local days = math.floor(d / 86400)
        local rest = d % 86400
        local t = ("%02d:%02d:%02d"):format(math.floor(rest / 3600), math.floor((rest % 3600) / 60), rest % 60)
        return days > 0 and ((L["endet in %d Tg %s"]):format(days, t)) or ((L["endet in %s"]):format(t))
    end
    if d >= 86400 then
        local h = math.floor((d % 86400) / 3600)
        return (L["noch %d Tg"]):format(math.floor(d / 86400)) .. (h > 0 and (" " .. (L["%d Std"]):format(h)) or "")
    end
    if d >= 3600 then return (L["noch %d:%02d Std"]):format(math.floor(d / 3600), math.floor((d % 3600) / 60)) end
    return (L["noch %d Min"]):format(math.max(1, math.floor(d / 60)))
end
Polls.Remaining = remaining

-- Sieger (bei Gleichstand mehrere)
function Polls.Winner(p)
    local counts, total = Polls.Result(p)
    local best, names = 0, {}
    for _, o in ipairs(Polls.Options(p)) do
        local n = counts[o.idx] or 0
        if n > best then best, names = n, { o.text } elseif n == best and n > 0 then names[#names + 1] = o.text end
    end
    if best == 0 then return nil, 0, total end
    return table.concat(names, " / "), best, total
end

-- Hinweis, wenn eine Umfrage endet, bei der ich abgestimmt oder die ich gestartet habe
local announced = {}
local function checkEnded()
    for _, p in ipairs(Polls.All()) do
        if not Polls.IsOpen(p) and not announced[p.id] then
            announced[p.id] = true
            local recent = ns.now() - (p.exp or 0) < 3600 or p.closed
            local involved = ns.isMe(p.by) or next(Polls.MyPick(p)) ~= nil
            if recent and involved and ns.db.settings.pollEndToast ~= false and (ns.db.pollSeen or {})[p.id] == nil then
                ns.db.pollSeen = ns.db.pollSeen or {}
                ns.db.pollSeen[p.id] = true
                local w, n, total = Polls.Winner(p)
                K.Toast(L["Umfrage beendet: "] .. SEC.Text(p.q or "?", 120), w and ((L["Gewonnen: %s (%d von %d)"]):format(SEC.Text(w, 60), n, total)) or L["Keine Stimmen"], C.accent,
                    function() Polls.selected = p.id ns.ShowPage("polls") end)
            end
        end
    end
end

-- Liste mit Abschnitten "Laufend" / "Beendet"
local function listRows()
    local open, done = {}, {}
    for _, p in ipairs(Polls.All()) do
        if Polls.IsOpen(p) then open[#open + 1] = p else done[#done + 1] = p end
    end
    table.sort(open, function(a, b) return (a.exp or 0) < (b.exp or 0) end)
    table.sort(done, function(a, b) return (a.exp or 0) > (b.exp or 0) end)
    local rows = {}
    if #open > 0 then rows[#rows + 1] = { header = L["Laufend"], n = #open } end
    for _, p in ipairs(open) do rows[#rows + 1] = p end
    if #done > 0 then rows[#rows + 1] = { header = L["Beendet"], n = #done } end
    for _, p in ipairs(done) do rows[#rows + 1] = p end
    return rows
end

-- 0.5.597: Seite neu - Glas-Design, Kennzahlen, Countdown, Antwort-Karten mit Verlauf, Vorlagen, Emojis
local function animOn() return not (ns.db and ns.db.settings.noAnim) end
local function glass(f, fill, line, r)
    local G = ns.Insta and ns.Insta.Glass
    if G and pcall(G, f, fill or { 1, 1, 1, 0.035 }, line or { 1, 1, 1, 0.09 }, r or 12) then return true end
    if not f.oasisFlat then f.oasisFlat = K.Fill(f, { 1, 1, 1, 0.03 }) K.Border(f, C.line) end
    return false
end
-- Emoji-Codes als Bilder (gesperrte Emojis nur, wenn der Ersteller den Rang hat)
local function emo(text, who)
    text = SEC.Text(text or "?", 200)
    if ns.Emoji and ns.Emoji.Render then
        local ok, r = pcall(ns.Emoji.Render, text, who)
        if ok and type(r) == "string" then return r end
    end
    return text
end
-- Vorlagen fuer schnelle Umfragen
local TEMPLATES = {
    { "Ja / Nein", { "Ja", "Nein" } },
    { "Ja / Nein / Vielleicht", { "Ja", "Nein", "Vielleicht" } },
    { "Wochentag", { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" } },
    { "Uhrzeit", { "18:00", "19:00", "20:00", "21:00" } },
    { "Bewertung", { ":D Super", ":) Gut", ":| Geht so", ":( Schlecht" } },
}
local LISTW = 288
ns.RegisterPage({
    key = "polls", title = "Umfragen", order = 7.6,
    sub = "Die Gilde abstimmen lassen - jeder Spieler hat eine Stimme, das Ergebnis ist live",
    build = function(p)
        -- Kennzahlen oben
        p.tiles = {}
        local TT = { { "announce", "Laufend" }, { "star_on", "Offen fuer dich" }, { "checklist", "Beendet" }, { "social", "Stimmen gesamt" } }
        for i, t in ipairs(TT) do
            local c = CreateFrame("Frame", nil, p)
            c:SetHeight(52)
            glass(c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.08 }, 12)
            c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. t[1], C.accent)
            c.ic:SetPoint("LEFT", 14, 0)
            c.v = K.Title(c, 18, C.text)
            c.v:SetPoint("TOPLEFT", 40, -8)
            c.l = K.Text(c, 10, C.dim)
            c.l:SetPoint("TOPLEFT", c.v, "BOTTOMLEFT", 0, -2)
            c.l:SetText(L[t[2]])
            p.tiles[i] = c
            c:Hide()   -- Kennzahlen-Kacheln entfallen; Werte stehen in der Liste
        end
        local new = K.Button(p, L["Neue Umfrage"], 130, 30, "primary", function()
            creating = not creating
            ns.RefreshPage("polls")
        end)
        new:SetPoint("TOPRIGHT", 0, -2)
        p.newBtn = new
        local function placeTiles()
            local W = (p:GetWidth() or 700) - 142
            local w = (W - 3 * 10) / 4
            for i, c in ipairs(p.tiles) do
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (w + 10), 0)
                c:SetWidth(math.max(60, w))
            end
        end
        p:HookScript("OnSizeChanged", placeTiles)
        placeTiles()
        p:HookScript("OnShow", function() p.animAll = true end)

        -- Liste links: Abschnitte + Glas-Karten
        p.list = K.List(p, 64, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            if r.sel then r.sel:SetAlpha(0) end
            if r.hl then r.hl:SetAlpha(0) end
            r.card = CreateFrame("Frame", nil, r)
            r.card:SetPoint("TOPLEFT", 0, -3)
            r.card:SetPoint("BOTTOMRIGHT", -6, 3)
            r.card:EnableMouse(false)
            glass(r.card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.07 }, 10)
            r.head = K.Text(r, 11, C.muted)
            r.head:SetPoint("BOTTOMLEFT", 4, 10)
            r.q = K.Text(r.card, 13, C.text)
            r.q:SetPoint("TOPLEFT", 12, -10)
            r.q:SetPoint("RIGHT", -70, 0)
            r.q:SetWordWrap(false)
            r.meta = K.Text(r.card, 10, C.dim)
            r.meta:SetPoint("TOPLEFT", r.q, "BOTTOMLEFT", 0, -4)
            r.meta:SetPoint("RIGHT", -12, 0)
            r.meta:SetWordWrap(false)
            r.tag = K.Title(r.card, 10, C.accent, "RIGHT")
            r.tag:SetPoint("TOPRIGHT", -12, -11)
            r.leadBg = r.card:CreateTexture(nil, "BACKGROUND", nil, 2)
            r.leadBg:SetPoint("BOTTOMLEFT", 12, 8) r.leadBg:SetPoint("BOTTOMRIGHT", -12, 8)
            r.leadBg:SetHeight(3)
            r.leadBg:SetColorTexture(1, 1, 1, 0.06)
            r.lead = r.card:CreateTexture(nil, "ARTWORK")
            r.lead:SetPoint("BOTTOMLEFT", 12, 8)
            r.lead:SetHeight(3)
            r:SetScript("OnClick", function(self)
                if not self.item or self.item.header then return end
                if Polls.selected ~= self.item.id then p.animDetail = true end
                Polls.selected = self.item.id
                creating = false
                ns.RefreshPage("polls", true)
            end)
            r:SetScript("OnEnter", function(self) if self.item and not self.item.header and Polls.selected ~= self.item.id then glass(self.card, { 1, 1, 1, 0.055 }, { 1, 1, 1, 0.12 }) end end)
            r:SetScript("OnLeave", function(self) if self.item and not self.item.header then self.paint(self) end end)
            function r.paint(self)
                local sel = self.item and Polls.selected == self.item.id and not creating
                glass(self.card, sel and { C.accent[1], C.accent[2], C.accent[3], 0.10 } or { 1, 1, 1, 0.03 },
                    sel and { C.accent[1], C.accent[2], C.accent[3], 0.55 } or { 1, 1, 1, 0.07 })
            end
            return r
        end, function(r, poll)
            if poll.header then
                r.card:Hide()
                r.head:SetText(K.Upper and K.Upper(poll.header) .. "  |cff666666" .. poll.n .. "|r" or poll.header)
                r.head:Show()
                r:SetAlpha(1)
                return
            end
            r.head:Hide()
            r.card:Show()
            r.q:SetText(emo(poll.q, poll.by))
            local open = Polls.IsOpen(poll)
            local counts, total = Polls.Result(poll)
            local voted = next(Polls.MyPick(poll)) ~= nil
            if open then
                r.meta:SetText(ns.displayName(poll.by) .. "  ·  " .. (L["%d Stimmen"]):format(total) .. "  ·  |cffe8b44a" .. remaining(poll) .. "|r")
                r.tag:SetText(voted and ("|cff66db9e" .. L["ABGESTIMMT"] .. "|r") or K.hex(C.accent) .. L["OFFEN"] .. "|r")
            else
                local w, n = Polls.Winner(poll)
                r.meta:SetText(w and ("|cff66db9e" .. emo(w, poll.by) .. "|r  |cff777777" .. (L["%d von %d"]):format(n, total) .. "|r") or ("|cff666666" .. L["keine Stimmen"] .. "|r"))
                r.tag:SetText("|cff777777" .. L["BEENDET"] .. "|r")
            end
            local best = 0
            for _, n in pairs(counts) do best = math.max(best, n) end
            local w = (r.card:GetWidth() > 40 and r.card:GetWidth() or 270) - 24
            r.lead:SetWidth(math.max(1, w * (total > 0 and best / total or 0)))
            local lc = open and C.accent or C.mint
            if not K.Gradient(r.lead, "HORIZONTAL", { lc[1], lc[2], lc[3], 0.35 }, { lc[1], lc[2], lc[3], 0.95 }) then r.lead:SetColorTexture(lc[1], lc[2], lc[3], 0.9) end
            r.lead:SetShown(total > 0)
            r.paint(r)
            r:SetAlpha(open and 1 or 0.75)
        end)
        -- 25 px hoeher: die erste Karte (unter der Abschnitts-Zeile) schliesst oben buendig mit der Karte rechts ab
        p.list:SetPoint("TOPLEFT", 0, 25)
        p.list:SetPoint("BOTTOMLEFT", 0, 0)
        p.list:SetWidth(LISTW)
        p.list.empty:SetText(L["Noch keine Umfragen."])

        -- Detail rechts -------------------------------------------------
        local d = CreateFrame("Frame", nil, p)
        d:SetPoint("TOPLEFT", LISTW + 12, -42)
        d:SetPoint("BOTTOMRIGHT")
        glass(d, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 14)
        p.detail = d
        d.glow = d:CreateTexture(nil, "BACKGROUND", nil, 2)
        d.glow:SetPoint("TOPLEFT", 3, -3) d.glow:SetPoint("TOPRIGHT", -3, -3) d.glow:SetHeight(120)
        d.q = K.Title(d, 18, C.text)
        d.q:SetPoint("TOPLEFT", 18, -16)
        d.q:SetPoint("RIGHT", -120, 0)
        d.q:SetWordWrap(true)
        d.q:SetJustifyH("LEFT")
        d.q:SetJustifyV("TOP")
        if ns.Emoji and ns.Emoji.Track then pcall(ns.Emoji.Track, d.q) end
        d.meta = K.Text(d, 11, C.muted)
        d.meta:SetPoint("TOPLEFT", d.q, "BOTTOMLEFT", 0, -6)
        d.meta:SetPoint("RIGHT", -18, 0)
        -- Countdown rechts oben (grosse Ziffern)
        d.timer = K.Title(d, 20, C.amber, "RIGHT")
        d.timer:SetPoint("TOPRIGHT", -18, -16)
        d.timerL = K.Text(d, 10, C.dim, "RIGHT")
        d.timerL:SetPoint("TOPRIGHT", d.timer, "BOTTOMRIGHT", 0, -2)
        -- Zeitbalken + Beteiligung
        d.tbar = CreateFrame("Frame", nil, d)
        d.tbar:SetHeight(4)
        d.tbar:SetPoint("TOPLEFT", d.meta, "BOTTOMLEFT", 0, -10)
        d.tbar:SetPoint("RIGHT", d, "RIGHT", -18, 0)
        d.tbar.bg = d.tbar:CreateTexture(nil, "BACKGROUND") d.tbar.bg:SetAllPoints() d.tbar.bg:SetColorTexture(1, 1, 1, 0.06)
        d.tbar.fill = d.tbar:CreateTexture(nil, "ARTWORK") d.tbar.fill:SetPoint("TOPLEFT") d.tbar.fill:SetPoint("BOTTOMLEFT")
        if not K.Gradient(d.tbar.fill, "HORIZONTAL", { C.amber[1], C.amber[2], C.amber[3], 0.4 }, { C.amber[1], C.amber[2], C.amber[3], 1 }) then d.tbar.fill:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1) end
        d.part = K.Text(d, 10, C.dim)
        d.part:SetPoint("TOPLEFT", d.tbar, "BOTTOMLEFT", 0, -5)
        d.winner = K.Title(d, 13, C.mint)
        d.winner:SetPoint("TOPLEFT", d.tbar, "BOTTOMLEFT", 0, -4)
        d.winner:SetPoint("RIGHT", d, "RIGHT", -18, 0)
        d:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            if self.acc < 1 or not self.poll then return end
            self.acc = 0
            local poll = self.poll
            if Polls.IsOpen(poll) then
                self.timer:SetText(remaining(poll, true):gsub("^%S+ %S+ ", ""))
                local span = (poll.exp or 0) - (poll.created or poll.exp or 0)
                local f = span > 0 and ((poll.exp - ns.now()) / span) or 0
                self.tbar.fill:SetWidth(math.max(1, (self.tbar:GetWidth() or 300) * math.max(0, math.min(1, f))))
            elseif not self.ended then
                self.ended = true
                ns.RefreshPage("polls")
            end
        end)
        -- Antwort-Karten
        d.opts = {}
        for i = 1, MAXOPT do
            local o = CreateFrame("Button", nil, d)
            o:SetHeight(48)
            o:SetPoint("LEFT", 18, 0)
            o:SetPoint("RIGHT", d, "RIGHT", -18, 0)
            glass(o, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 10)
            o.fill = o:CreateTexture(nil, "BACKGROUND", nil, 3)
            o.fill:SetPoint("TOPLEFT", 2, -2)
            o.fill:SetPoint("BOTTOMLEFT", 2, 2)
            if K.RoundMask then K.RoundMask(o.fill, o, 10) end
            o.badge = o:CreateTexture(nil, "ARTWORK")
            o.badge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            o.badge:SetSize(26, 26)
            o.badge:SetPoint("LEFT", 11, 0)
            o.letter = K.Title(o, 12, C.text, "CENTER")
            o.letter:SetPoint("CENTER", o.badge, "CENTER", 0, 0)
            o.letter:SetText(string.char(64 + i))
            o.check = o:CreateTexture(nil, "OVERLAY")
            o.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            o.check:SetSize(14, 14)
            o.check:SetPoint("CENTER", o.badge, "BOTTOMRIGHT", -3, 3)
            o.crown = o:CreateTexture(nil, "OVERLAY")
            o.crown:SetTexture(ns.MEDIA .. "icons\\badges\\first30")
            o.crown:SetSize(18, 18)
            o.crown:SetPoint("CENTER", o.badge, "TOP", 0, 3)
            o.crown:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
            o.text = K.Text(o, 14, C.text)
            o.text:SetPoint("TOPLEFT", 48, -8)
            o.text:SetPoint("RIGHT", -86, 0)
            o.text:SetWordWrap(false)
            if ns.Emoji and ns.Emoji.Track then pcall(ns.Emoji.Track, o.text) end
            o.who = K.Text(o, 10, C.dim)
            o.who:SetPoint("BOTTOMLEFT", 48, 8)
            o.who:SetPoint("RIGHT", -86, 0)
            o.who:SetWordWrap(false)
            o.pct = K.Title(o, 18, C.text, "RIGHT")
            o.pct:SetPoint("RIGHT", -14, 4)
            o.cnt = K.Text(o, 10, C.muted, "RIGHT")
            o.cnt:SetPoint("TOPRIGHT", o.pct, "BOTTOMRIGHT", 0, -1)
            o:SetScript("OnEnter", function(self)
                if self.voters and #self.voters > 0 then
                    local t = {}
                    for _, n in ipairs(self.voters) do t[#t + 1] = ns.Radar.Colored(n) end
                    K.ShowTip(self, { self.label or "", table.concat(t, ", ") })
                end
                if self:IsEnabled() then glass(self, { 1, 1, 1, 0.06 }, { C.accent[1], C.accent[2], C.accent[3], 0.5 }) end
            end)
            o:SetScript("OnLeave", function(self) GameTooltip:Hide() self.paint(self) end)
            function o.paint(self)
                local c = self.mine and C.accent or (self.lead and self.closed and C.amber) or nil
                glass(self, c and { c[1], c[2], c[3], 0.07 } or { 1, 1, 1, 0.03 }, c and { c[1], c[2], c[3], 0.6 } or { 1, 1, 1, 0.08 })
            end
            d.opts[i] = o
        end
        d.close = K.Button(d, L["Jetzt beenden"], 120, 24, "ghost")
        d.close:SetPoint("BOTTOMLEFT", 18, 14)
        d.extend = K.Button(d, L["+1 Tag"], 70, 24, "ghost")
        d.extend:SetPoint("LEFT", d.close, "RIGHT", 6, 0)
        d.post = K.Button(d, L["Ergebnis im Gildenchat posten"], 200, 24, "primary")
        d.post:SetPoint("BOTTOMLEFT", 18, 14)
        d.del = K.Button(d, L["Loeschen"], 90, 24, "danger")
        d.del:SetPoint("BOTTOMRIGHT", -18, 14)
        d.hint = K.Text(d, 10, C.dim)
        d.hint:SetPoint("BOTTOMLEFT", 18, 46)

        -- Formular --------------------------------------------------------
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", LISTW + 12, -42)
        f:SetPoint("BOTTOMRIGHT")
        glass(f, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 14)
        p.form = f
        local h = K.Title(f, 15, C.text)
        h:SetPoint("TOPLEFT", 18, -14)
        h:SetText(L["Neue Umfrage"])
        -- Vorlagen
        f.tpl = {}
        local tx = 18
        local tl = K.Text(f, 10, C.dim)
        tl:SetPoint("TOPLEFT", 18, -38)
        tl:SetText(L["Vorlagen:"])
        tx = 18 + 56
        for i, t in ipairs(TEMPLATES) do
            local b = K.Button(f, L[t[1]], 10, 20, "ghost", function()
                for j = 1, MAXOPT do f.o[j]:SetText(t[2][j] and L[t[2][j]] or "") end
                if animOn() then for j = 1, MAXOPT do local e = f.o[j] e:SetAlpha(0.2) K.Tween(e, 0.25, function(q) e:SetAlpha(0.2 + 0.8 * q) end, function() e:SetAlpha(1) end, (j - 1) * 0.04) end end
                f:Preview()
            end)
            b:SetWidth((b.label and b.label:GetStringWidth() or 60) + 18)
            b:SetPoint("TOPLEFT", tx, -34)
            tx = tx + b:GetWidth() + 4
            f.tpl[i] = b
        end
        -- Eingaben mit Emoji-Knopf
        local function emojiBtn(e)
            local b = CreateFrame("Button", nil, e)
            b:SetSize(18, 18)
            b:SetPoint("RIGHT", -4, 0)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            if ns.Emoji and ns.Emoji.Entry and ns.Emoji.SetIcon then ns.Emoji.SetIcon(b.icon, ns.Emoji.Entry(":)")) else b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.6)
            b:SetScript("OnEnter", function(self) self.icon:SetDesaturated(false) self.icon:SetAlpha(1) K.ShowTip(self, { L["Emoji einfuegen"] }) end)
            b:SetScript("OnLeave", function(self) self.icon:SetDesaturated(true) self.icon:SetAlpha(0.6) GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                if ns.Emoji and ns.Emoji.TogglePicker then
                    ns.Emoji.target = e
                    e:SetFocus()
                    ns.Emoji.TogglePicker(self)
                end
            end)
            e:SetTextInsets(7, 26, 0, 0)
            return b
        end
        f.q = K.Input(f, 400, L["Frage, z.B. Raid am Mittwoch oder Donnerstag?"], function() f:Preview() end)
        f.q:SetPoint("TOPLEFT", 18, -62)
        f.q:SetPoint("RIGHT", -18, 0)
        f.q:SetMaxLetters(140)
        emojiBtn(f.q)
        f.o = {}
        for i = 1, MAXOPT do
            local e = K.Input(f, 400, (L["Antwort %d"]):format(i) .. (i > 2 and (" " .. L["(optional)"]) or ""), function() f:Preview() end)
            e:SetPoint("TOPLEFT", 18, -96 - (i - 1) * 28)
            e:SetPoint("RIGHT", -18, 0)
            e:SetMaxLetters(80)
            emojiBtn(e)
            f.o[i] = e
        end
        local by = -96 - MAXOPT * 28
        local mt = K.Toggle(f, L["Mehrfachauswahl erlauben"], function() return multi end, function(v) multi = v end)
        mt:SetPoint("TOPLEFT", 18, by - 4)
        local st = K.Toggle(f, L["Geheime Abstimmung (ohne Namen)"], function() return secret end, function(v) secret = v end)
        st:SetPoint("TOPLEFT", 260, by - 4)
        local dl = K.Text(f, 11, C.muted)
        dl:SetPoint("TOPLEFT", 18, by - 36)
        dl:SetText(L["Wie lange?"])
        f.durBtns = {}
        for i, dd in ipairs(DUR) do
            local b = K.Button(f, L[dd[2]], 60, 22, "ghost", function()
                durIdx, customHours = i, nil
                f.custom:SetText("")
                ns.RefreshPage("polls")
            end)
            b:SetPoint("TOPLEFT", 18 + (i - 1) * 64, by - 52)
            f.durBtns[i] = b
        end
        f.custom = K.Input(f, 60, L["Std"], function(t)
            customHours = tonumber(t)
            ns.RefreshPage("polls")
        end)
        f.custom:SetNumeric(true)
        f.custom:SetPoint("TOPLEFT", 18, by - 80)
        local cl = K.Text(f, 11, C.muted)
        cl:SetPoint("LEFT", f.custom, "RIGHT", 8, 0)
        cl:SetText(L["eigene Dauer in Stunden"])
        f.ends = K.Text(f, 11, C.amber)
        f.ends:SetPoint("LEFT", cl, "RIGHT", 14, 0)
        -- Vorschau: so sieht die Frage mit Emojis aus
        f.prev = K.Text(f, 12, C.text)
        f.prev:SetPoint("BOTTOMLEFT", 196, 20)
        f.prev:SetPoint("RIGHT", -18, 0)
        f.prev:SetWordWrap(false)
        if ns.Emoji and ns.Emoji.Track then pcall(ns.Emoji.Track, f.prev) end
        function f:Preview()
            local q = self.q:GetText() or ""
            local n = 0
            for i = 1, MAXOPT do if (self.o[i]:GetText() or "") ~= "" then n = n + 1 end end
            self.prev:SetText(q ~= "" and ("|cff777777" .. L["Vorschau:"] .. "|r  " .. emo(q, ns.me()) .. "  |cff777777(" .. (L["%d Antworten"]):format(n) .. ")|r") or "")
        end
        local go = K.Button(f, L["Umfrage starten"], 160, 28, "primary", function(self)
            local opts = {}
            for i = 1, MAXOPT do opts[i] = f.o[i]:GetText() end
            local rec = Polls.Create(f.q:GetText(), opts, multi, chosenDuration(), secret)
            if rec then
                K.Burst(p, self, 30)
                f.q:SetText("")
                for i = 1, MAXOPT do f.o[i]:SetText("") end
                f.custom:SetText("")
                customHours = nil
                Polls.selected = rec.id
                creating = false
                p.animDetail = true
                ns.RefreshPage("polls")
            end
        end)
        go:SetPoint("BOTTOMLEFT", 18, 14)
    end,
    refresh = function(p)
        checkEnded()
        local rows = listRows()
        p.list:SetData(rows)
        -- Kennzahlen
        local nOpen, nMine, nDone, nVotes = 0, 0, 0, 0
        for _, r in ipairs(rows) do
            if not r.header then
                if Polls.IsOpen(r) then
                    nOpen = nOpen + 1
                    if not next(Polls.MyPick(r)) then nMine = nMine + 1 end
                else nDone = nDone + 1 end
                local _, t = Polls.Result(r)
                nVotes = nVotes + t
            end
        end
        local vals = { nOpen, nMine, nDone, nVotes }
        for i, c in ipairs(p.tiles) do
            if p.animAll and animOn() then K.CountUp(c.v, vals[i], 0.7, nil, (i - 1) * 0.06) else c.v:SetText(vals[i]) end
        end
        p.tiles[2].v:SetTextColor((nMine > 0 and C.amber or C.text)[1], (nMine > 0 and C.amber or C.text)[2], (nMine > 0 and C.amber or C.text)[3])
        if not Polls.CanCreate() then creating = false end
        K.LockButton(p.newBtn, Polls.CanCreate, L["Umfragen koennen nur Offiziere und die Gildenleitung starten."])
        p.list.empty:SetText(Polls.CanCreate() and L["Noch keine Umfragen."] or (L["Noch keine Umfragen."] .. "\n|cff777777" .. L["Umfragen koennen nur Offiziere und die Gildenleitung starten."] .. "|r"))
        p.newBtn:SetLabel(creating and L["Abbrechen"] or L["Neue Umfrage"])
        local wasForm = p.form:IsShown()
        p.form:SetShown(creating)
        if creating then
            local f = p.form
            if not wasForm and animOn() then K.FadeIn(f, 0) end
            for i, b in ipairs(f.durBtns) do K.SetBorderColor(b, (not customHours and durIdx == i) and C.accent or C.line) end
            f.ends:SetText(L["Endet "] .. ns.weekday(ns.now() + chosenDuration(), true) .. " " .. date(L["%d.%m. um %H:%M"], ns.now() + chosenDuration()))
            f:Preview()
            p.detail:Hide()
            p.animAll = nil
            return
        end
        local poll = Polls.selected and Store.Get("polls", Polls.selected)
        if not poll or poll.del then
            poll = nil
            for _, r in ipairs(rows) do if not r.header then poll = r break end end
            Polls.selected = poll and poll.id
        end
        p.detail:SetShown(poll ~= nil)
        if not poll then p.animAll = nil return end

        local d = p.detail
        local newPoll = d.poll ~= poll and d.pollId ~= poll.id
        local animate = (newPoll or p.animAll or p.animDetail) and animOn()
        d.poll, d.pollId, d.ended = poll, poll.id, nil
        local open = Polls.IsOpen(poll)
        local ac = open and C.accent or C.mint
        if not K.Gradient(d.glow, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.14 }) then d.glow:SetColorTexture(ac[1], ac[2], ac[3], 0.05) end
        if newPoll and animOn() then K.FadeIn(d, 0) end
        d.q:SetText(emo(poll.q, poll.by))
        local counts, total, voters = Polls.Result(poll)
        local members = 0
        for _ in pairs(ns.db.members) do members = members + 1 end
        d.meta:SetText(ns.Radar.Colored(poll.by) .. "  ·  " .. (L["%d Stimmen"]):format(total) .. (poll.multi and ("  ·  " .. L["Mehrfachauswahl"]) or "")
            .. ((not poll.names) and ("  ·  |cff66db9e" .. L["geheim"] .. "|r") or ""))
        d.timer:SetShown(open)
        d.timerL:SetShown(open)
        d.tbar:SetShown(open)
        d.part:SetShown(open)
        d.winner:SetShown(not open)
        if open then
            d.timer:SetText((remaining(poll, true):gsub("^%S+ %S+ ", "")))
            d.timerL:SetText(L["bis zum Ende"])
            local span = (poll.exp or 0) - (poll.created or poll.exp or 0)
            local fr = span > 0 and ((poll.exp - ns.now()) / span) or 0
            d.tbar.fill:SetWidth(math.max(1, (d.tbar:GetWidth() > 2 and d.tbar:GetWidth() or 300) * math.max(0, math.min(1, fr))))
            d.part:SetText(members > 0 and ((L["Beteiligung %d %%"]):format(math.floor(math.min(1, total / (members + 1)) * 100 + 0.5)) .. "  |cff555555" .. (L["(von %d mit Oasis)"]):format(members + 1) .. "|r") or "")
        else
            local w, n = Polls.Winner(poll)
            d.winner:SetText(w and ((L["Ergebnis: %s gewinnt (%d von %d Stimmen)"]):format(emo(w, poll.by), n, total)) or L["Beendet - keine Stimmen"])
        end
        local mine = Polls.MyPick(poll)
        local opts = Polls.Options(poll)
        local best = 0
        for _, o in ipairs(opts) do best = math.max(best, counts[o.idx] or 0) end
        local y = -(open and 92 or 86) - math.max(0, (d.q:GetStringHeight() or 20) - 22)
        for i, row in ipairs(d.opts) do
            local o = opts[i]
            if o then
                local n = counts[o.idx] or 0
                local pctv = total > 0 and n / total or 0
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 18, y)
                row:SetPoint("RIGHT", d, "RIGHT", -18, 0)
                y = y - 54
                row.label = emo(o.text, poll.by)
                row.voters = voters[o.idx]
                local wasMine = row.mine
                row.mine = mine[o.idx] and true or false
                row.lead = n > 0 and n == best
                row.closed = not open
                row.crown:SetShown(row.lead and not open)
                row.text:SetText(emo(o.text, poll.by) .. (row.mine and ("  |cff66db9e" .. L["(deine Stimme)"] .. "|r") or ""))
                if animate then K.CountUp(row.pct, math.floor(pctv * 100 + 0.5), 0.6, function(v) return math.floor(v + 0.5) .. "%" end, (i - 1) * 0.05)
                else row.pct:SetText(("%d%%"):format(pctv * 100 + 0.5)) end
                row.cnt:SetText((L["%d Stimmen"]):format(n))
                local names = {}
                for j, vn in ipairs(row.voters or {}) do
                    if j > 5 then names[#names + 1] = "|cff777777+" .. (#row.voters - 5) .. "|r" break end
                    names[#names + 1] = ns.Radar.Colored(vn)
                end
                if not poll.names then row.who:SetText("|cff555555" .. L["geheime Abstimmung"] .. "|r")
                else row.who:SetText(#names > 0 and table.concat(names, "|cff555555, |r") or ("|cff555555" .. L["noch keine Stimme"] .. "|r")) end
                local bc = row.mine and C.accent or { 0.22, 0.22, 0.25 }
                row.badge:SetVertexColor(bc[1], bc[2], bc[3], 1)
                -- Balken mit Verlauf, wachsen weich zum neuen Stand
                local fc = (row.lead and not open) and C.amber or (row.mine and C.accent or { 0.6, 0.6, 0.66 })
                if not K.Gradient(row.fill, "HORIZONTAL", { fc[1], fc[2], fc[3], 0.30 }, { fc[1], fc[2], fc[3], 0.06 }) then row.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.15) end
                local w = math.max(1, ((row:GetWidth() > 10 and row:GetWidth() or 380) - 4) * pctv)
                local from = animate and 1 or (row.lastW or 1)
                row.lastW = w
                row.fill:SetShown(pctv > 0)
                if math.abs(from - w) > 1 and animOn() then
                    K.Tween(row.fill, 0.55, function(q) row.fill:SetWidth(math.max(1, from + (w - from) * q)) end, function() row.fill:SetWidth(w) end, animate and (i - 1) * 0.05 or 0)
                else
                    row.fill:SetWidth(w)
                end
                row.check:SetShown(row.mine)
                row:SetEnabled(open)
                row:SetScript("OnClick", function(self)
                    local had = self.mine
                    Polls.Vote(poll, o.idx)
                    -- Rueckmeldung: Haken ploppt, Konfetti beim ersten Kreuz
                    if not had and animOn() then
                        local c = self.check
                        c:Show()
                        K.Tween(c, 0.35, function(q) local k = 0.5 + 0.9 * math.sin(q * math.pi * 0.75) c:SetSize(14 * k + 4, 14 * k + 4) end, function() c:SetSize(14, 14) end)
                        K.Burst(p, self.badge, 14, { C.accent, C.mint, { 1, 1, 1 } })
                    end
                end)
                row.paint(row)
                if animate and animOn() then
                    row:SetAlpha(0)
                    K.Tween(row, 0.25, function(q) row:SetAlpha(q) end, function() row:SetAlpha(1) end, (i - 1) * 0.05)
                end
                row:Show()
            else
                row:Hide()
            end
        end
        local canEdit = ns.isMe(poll.by) or canManage() or (ns.isOfficer() and ns.GuildOpt("plOffEd") ~= false)
        d.close:SetShown(canEdit and open)
        d.close:SetScript("OnClick", function() Polls.Close(poll) end)
        d.extend:SetShown(canEdit and open)
        d.extend:SetScript("OnClick", function()
            local r = {}
            for k, v in pairs(poll) do r[k] = v end
            r.exp = (r.exp or ns.now()) + 86400
            Store.Put("polls", r)
        end)
        d.post:SetShown(canEdit and not open and total > 0)
        d.post:SetScript("OnClick", function()
            local w, n = Polls.Winner(poll)
            -- Klick = Eingabe -> Senden erlaubt; fremde Texte ohne Escape-Sequenzen
            if w then ns.SendChat((L["[Oasis] Umfrage \"%s\": %s gewinnt (%d von %d Stimmen)"]):format(SEC.Text(poll.q or "?", 100), SEC.Text(w, 60), n, total):sub(1, 255), "GUILD") end
        end)
        d.del:SetShown(canEdit)
        d.del:SetScript("OnClick", function() Store.Delete("polls", poll.id) Polls.selected = nil end)
        d.hint:SetText(open and (poll.multi and L["Klick: Antwort an/abwaehlen"] or L["Klick: abstimmen - du kannst deine Stimme aendern"]) or "")
        -- Sieger-Konfetti einmal, wenn man eine frisch beendete Umfrage ansieht
        if not open and total > 0 and newPoll and not (p.cheered or {})[poll.id] and ns.now() - (poll.exp or 0) < 86400 then
            p.cheered = p.cheered or {}
            p.cheered[poll.id] = true
            for _, row in ipairs(d.opts) do if row:IsShown() and row.lead then ns.After(0.4, function() K.Burst(p, row.crown, 30, { C.amber, C.mint, { 1, 1, 1 } }) end) break end end
        end
        p.animAll, p.animDetail = nil, nil
    end,
})

ns.Listen("LOGIN", function() ns.Every(30, function() pcall(checkEnded) updateBadge() end) end)

ns.Listen("LOGIN", function()
    ns.After(12, updateBadge)
    ns.Every(60, function() updateBadge() ns.RefreshPage("polls") end)
end)
end)

-- Oasis - Fluester-Verlauf: alle Fluesternachrichten (rein + raus) werden gemerkt.
-- Was ankam, waehrend du AFK/beschaeftigt warst, zeigt Oasis dir beim Zurueckkommen.
-- Reiter "Privat" auf der Chat-Seite: Gespraeche anheften/stummschalten, Suche, Filter, Merkliste,
-- Reaktionen, Zitieren, Entwuerfe je Gespraech. Alles bleibt lokal (ns.char) - nur eine Reaktion
-- geht auf Wunsch per Addon-Nachricht an den Gespraechspartner (wenn er Oasis hat).
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Whispers", function()   -- Modul Fluestern (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local WL = {}
ns.WhisperLog = WL
local MAX = 150
local function S() return (ns.db and ns.db.settings) or {} end
local function maxKeep() return math.max(MAX, tonumber(S().wlKeep) or 300) end

-- Fluesterverlauf gilt fuer den ganzen Account (alle Charaktere), nicht je Charakter:
-- beim ersten Start werden die bisherigen Verlaeufe aller Charaktere zusammengefuehrt (e.char = wer es war)
local function migrate()
    local all, metas = {}, {}
    for cname, c in pairs(ns.db.chars or {}) do
        for _, e in ipairs(c.whispers or {}) do e.char = e.char or cname all[#all + 1] = e end
        for who, m in pairs(c.wlMeta or {}) do if not metas[who] then metas[who] = m end end
        c.whispers, c.wlMeta = nil, nil
    end
    table.sort(all, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local seq = 0
    for _, e in ipairs(all) do seq = seq + 1 e.id = seq end
    ns.db.whispersAll, ns.db.wlMetaAll, ns.db.wlSeqAll = all, metas, seq
end
local function log()
    if not ns.db.whispersAll then migrate() end
    return ns.db.whispersAll
end
-- Angaben je Gespraech: pin, mute, unread (von Hand), draft, note, created
local function metaAll()
    if not ns.db.whispersAll then migrate() end
    ns.db.wlMetaAll = ns.db.wlMetaAll or {}
    return ns.db.wlMetaAll
end
local function meta(name, make)
    if not name or not ns.char then return nil end
    local m = metaAll()
    if not m[name] and make then m[name] = {} end
    return m[name]
end
WL.Meta = meta
local function isMuted(name) local m = name and ns.char and meta(name) return m and m.mute end
local function away() return (UnitIsAFK and ns.safe(UnitIsAFK("player"))) or (UnitIsDND and ns.safe(UnitIsDND("player"))) end
function WL.Unread()
    if not ns.char then return 0 end
    local n, seen = 0, {}
    for _, e in ipairs(log()) do
        if e.new then
            local p = e.from or e.to
            if not isMuted(p) then n = n + 1 seen[p or ""] = true end
        end
    end
    -- von Hand "als ungelesen" markierte Gespraeche zaehlen je 1
    for name, m in pairs(metaAll()) do if m.unread and not seen[name] and not m.mute then n = n + 1 end end
    return n
end
local function nextId()
    ns.db.wlSeqAll = (ns.db.wlSeqAll or 0) + 1
    return ns.db.wlSeqAll
end
local function add(e)
    local l = log()
    e.id = nextId()
    e.char = e.char or ns.me()
    l[#l + 1] = e
    local keep = maxKeep()
    -- zu viele: aelteste ungemerkte zuerst raus (gemerkte bleiben)
    while #l > keep do
        local drop = 1
        for i = 1, #l - 1 do if not l[i].star then drop = i break end end
        table.remove(l, drop)
    end
    WL.ver = (WL.ver or 0) + 1
    if WL.frame and WL.frame:IsShown() then WL.Refresh() end
    if WL.priv and WL.priv:IsShown() then WL.RefreshPrivate() end
end
-- Oasis-Sound im Privatchat als eigene Zeile ({s:key} wird als Lautsprecher-Link gezeigt)
function WL.AddSound(name, key, outgoing)
    if not (ns.char and name and key) then return end
    if outgoing then add({ t = ns.now(), to = name, msg = "{s:" .. key .. "}" })
    else add({ t = ns.now(), from = name, msg = "{s:" .. key .. "}" }) end
end
-- gerade sichtbar geoeffnetes Gespraech (dann ist eine neue Nachricht sofort gelesen)
local function viewing(name)
    return WL.priv and WL.priv:IsVisible() and WL.privSel == name
end

ns.On("CHAT_MSG_WHISPER", function(msg, sender)
    msg, sender = ns.safe(msg), ns.safe(sender)
    if not msg or not sender or not ns.char then return end
    local mu = isMuted(sender)
    local m = meta(sender)
    if m then m.created = nil end
    add({ t = ns.now(), from = sender, msg = msg, new = (not mu and not viewing(sender)) or nil, afk = (not mu and away()) and true or nil })
end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(msg, target)
    msg, target = ns.safe(msg), ns.safe(target)
    if not msg or not target or not ns.char then return end
    -- wer antwortet, hat die Nachrichten dieser Person gelesen
    for _, e in ipairs(log()) do if e.new and e.from == target then e.new = nil end end
    local m = meta(target)
    if m then m.unread = nil m.created = nil end
    add({ t = ns.now(), to = target, msg = msg })
end)
-- Battle.net-Fluestern: Absender ist der Account-Name (z.B. "PewPew"), nicht der Charakter.
-- Den gerade gespielten Charakter holen wir ueber die Battle.net-ID und merken ihn je Account.
local function bnCharOf(bnID)
    bnID = ns.safe(bnID)
    if not (bnID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil end
    local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnID)
    local g = ok and type(info) == "table" and info.gameAccountInfo
    if not g then return nil end
    local name = ns.safe(g.characterName)
    if not name or name == "" then return nil end
    return { char = name, realm = ns.safe(g.realmName), class = ns.safe(g.className), lvl = ns.safe(g.characterLevel),
        zone = ns.safe(g.areaName), online = ns.safe(g.isOnline) and true or nil, t = ns.now(),
        tag = ns.safe(info.battleTag), acc = ns.safe(info.accountName) }
end
-- WICHTIG: der Absender eines Battle.net-Fluesterns ist ein Platzhalter (|Kq..|k), dessen Nummer nur
-- fuer DIESE Sitzung gilt - spaeter zeigt dieselbe Nummer evtl. einen ANDEREN Freund an. Darum speichern
-- wir einen festen Schluessel: den BattleTag-Namen (z.B. "Tomas"), sonst "Battle.net".
local function bnKey(sender, bnID)
    local info = bnCharOf(bnID)
    local tag = info and info.tag
    local key = tag and tag:match("^([^#]+)")
    if not key or key == "" then
        key = (sender and not sender:find("|K", 1, true)) and sender or L["Battle.net"]
    end
    if info and ns.char then
        ns.char.bnChars = ns.char.bnChars or {}
        ns.char.bnChars[key] = info
    end
    return key
end
-- Anzeige: "Tomas (Charaktername)" fuer Battle.net-Gespraeche, sonst der normale Name
function WL.Label(name)
    local b = ns.char and ns.char.bnChars and name and ns.char.bnChars[name]
    if b and b.tag and b.char and b.char ~= name then return name .. " |cff888888(" .. b.char .. ")|r" end
    return ns.displayName(name or "?")
end
function WL.BnInfo(name) return ns.char and ns.char.bnChars and name and ns.char.bnChars[name] end
ns.On("CHAT_MSG_BN_WHISPER", function(msg, sender, ...)
    msg, sender = ns.safe(msg), ns.safe(sender)
    if not msg or not ns.char then return end
    local ok, key = pcall(bnKey, sender, select(11, ...))   -- 13. Argument = bnSenderID
    sender = ok and key or L["Battle.net"]
    local alias = ns.char.bnAlias and ns.char.bnAlias[sender]
    if alias then sender = alias end
    local mu = isMuted(sender)
    add({ t = ns.now(), from = sender, msg = msg, bn = (not alias) or nil, viaBN = alias and true or nil, new = (not mu and not viewing(sender)) or nil, afk = (not mu and away()) and true or nil })
end)
-- eigene Battle.net-Antworten (fehlten bisher im Verlauf)
ns.On("CHAT_MSG_BN_WHISPER_INFORM", function(msg, target, ...)
    msg, target = ns.safe(msg), ns.safe(target)
    if not msg or not ns.char then return end
    local ok, key = pcall(bnKey, target, select(11, ...))
    target = ok and key or L["Battle.net"]
    local alias = ns.char.bnAlias and ns.char.bnAlias[target]
    if alias then target = alias end
    for _, e in ipairs(log()) do if e.new and e.from == target then e.new = nil end end
    local m = meta(target)
    if m then m.unread = nil m.created = nil end
    add({ t = ns.now(), to = target, msg = msg, bn = (not alias) or nil, viaBN = alias and true or nil })
end)
-- alte Eintraege mit Sitzungs-Platzhalter: Absender laesst sich nicht mehr sicher bestimmen
ns.Listen("LOGIN", function()
    if not ns.char then return end
    local fixed = false
    for _, e in ipairs(log()) do
        for _, k in ipairs({ "from", "to" }) do
            if type(e[k]) == "string" and e[k]:find("|K", 1, true) then e[k] = L["Battle.net (alt)"] fixed = true end
        end
    end
    if ns.char.bnChars then
        for k, v in pairs(ns.char.bnChars) do if type(k) ~= "string" or k:find("|K", 1, true) or not v.tag then ns.char.bnChars[k] = nil end end
    end
end)

-- zurueck vom AFK: Hinweis, wenn etwas verpasst wurde
local function missed()
    local n = 0
    for _, e in ipairs(log()) do if e.new and e.afk then n = n + 1 end end
    return n
end
local wasAway = false
ns.On("PLAYER_FLAGS_CHANGED", function(unit)
    if unit ~= "player" then return end
    local now = away() and true or false
    if wasAway and not now and ns.char then
        local n = missed()
        if n > 0 then
            if ns.Sound then ns.Sound.Play("toast") end
            K.Toast((L["%d Fluesternachrichten verpasst"]):format(n), L["Klick: anzeigen"], C.pink, function() WL.Show() end)
        end
        for _, e in ipairs(log()) do e.afk = nil end
    end
    wasAway = now
end)
ns.Listen("LOGIN", function() wasAway = away() and true or false end)

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------
local ROW_H = 40
local function build()
    local f = CreateFrame("Frame", "OasisWhisperLog", UIParent)
    f:SetSize(460, 420)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
    K.Border(f, C.line)
    f.head = K.GameHead(f, L["Fluester-Verlauf"], C.pink)
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.head:SetWidth(260)
    local x = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
    x:SetPoint("TOPRIGHT", -6, -6)
    f.sub = K.Text(f, 10, C.dim)
    f.sub:SetPoint("TOPLEFT", 12, -34)
    f.list = K.List(f, ROW_H, function(l)
        local r = K.Row(l)
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT") r.bar:SetWidth(2)
        r.who = K.Text(r, 12, C.text)
        r.who:SetPoint("TOPLEFT", 10, -5)
        r.when = K.Text(r, 10, C.dim, "RIGHT")
        r.when:SetPoint("TOPRIGHT", -8, -6)
        r.msg = K.Text(r, 12, C.muted)
        r.msg:SetPoint("TOPLEFT", 10, -21)
        r.msg:SetPoint("RIGHT", -8, 0)
        r.msg:SetWordWrap(false)
        r:RegisterForClicks("AnyUp")
        r:SetScript("OnClick", function(self)
            local e = self.e
            if not e then return end
            local who = e.from or e.to
            if e.bn then return end
            if who then ns.Whisper(who) end
        end)
        r:SetScript("OnEnter", function(self)
            local e = self.e
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine((e.from and L["von"] or L["gesendet an"]) .. " " .. ns.displayName(e.from or e.to or "?"), 1, 1, 1)
            GameTooltip:AddLine(e.msg, 0.85, 0.85, 0.85, true)
            if not e.bn then GameTooltip:AddLine(L["Klick: antworten"], 0.4, 0.86, 0.62) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e)
        r.e = e
        local inc = e.from ~= nil
        local name = ns.displayName(e.from or e.to or "?")
        r.who:SetText((inc and "" or "|cff888888" .. L["gesendet an"] .. "|r ") .. (inc and ("|cfff08ac8" .. name .. "|r") or name) .. (e.new and ("  |cffff5a4a" .. L["neu"] .. "|r") or ""))
        r.when:SetText(date(L["%d.%m. %H:%M"], e.t or 0))
        r.msg:SetText(e.msg or "")
        local c = e.new and C.red or (inc and C.pink or C.line)
        r.bar:SetColorTexture(c[1], c[2], c[3], inc and 0.9 or 0.4)
    end)
    f.list:SetPoint("TOPLEFT", 8, -54)
    f.list:SetPoint("BOTTOMRIGHT", -8, 42)
    f.list.empty:SetText(L["Noch keine Fluesternachrichten."])
    f.read = K.Button(f, L["Alle gelesen"], 120, 24, "ghost", function()
        for _, e in ipairs(log()) do e.new = nil end
        WL.Refresh()
    end)
    f.read:SetPoint("BOTTOMLEFT", 10, 10)
    f.only = K.Button(f, "", 150, 24, "ghost", function() WL.onlyNew = not WL.onlyNew WL.Refresh() end)
    f.only:SetPoint("LEFT", f.read, "RIGHT", 8, 0)
    f.clear = K.Button(f, L["Verlauf leeren"], 120, 24, "danger", function() ns.db.whispersAll = {} WL.Refresh() end)
    f.clear:SetPoint("BOTTOMRIGHT", -10, 10)
    ns.EscClose("OasisWhisperLog")
    WL.frame = f
end
function WL.Refresh()
    local f = WL.frame
    if not f then return end
    local out = {}
    local l = log()
    for i = #l, 1, -1 do
        local e = l[i]
        if not WL.onlyNew or e.new then out[#out + 1] = e end
    end
    local n = WL.Unread()
    f.sub:SetText((L["%d gespeichert"]):format(#l) .. (n > 0 and ("  ·  |cffff5a4a" .. (L["%d neu"]):format(n) .. "|r") or ""))
    f.only.label:SetText(WL.onlyNew and L["Alle anzeigen"] or L["Nur neue"])
    f.list:SetData(out)
end
function WL.Show()
    if ns.GuildChat then ns.GuildChat.mode = "priv" end
    ns.ShowPage("chat")
    ns.RefreshPage("chat")
end
function WL.ShowWindow()
    if not WL.frame then build() end
    WL.frame:Show()
    WL.Refresh()
end
function WL.Toggle()
    if WL.frame and WL.frame:IsShown() then WL.frame:Hide() else WL.ShowWindow() end
end
ns.slash.whispers = function() WL.Toggle() end
ns.slash.fl = ns.slash.whispers

------------------------------------------------------------------------
-- Reiter "Privat" im Chat: Unterhaltungen links, Verlauf rechts, Antworten unten
------------------------------------------------------------------------
local function partnerOf(e) return e.from or e.to end
local function sameName(a, b)
    if not a or not b then return false end
    return ns.SameName(a, b)
end
-- Mitglied der Gilde (Radar) zu einem Fluesternamen
local function member(name)
    local R = ns.Radar
    if not name or not R or not R.byName then return nil end
    local full = ns.fullName(name)
    return (full and rawget(R.byName, full)) or rawget(R.byName, name)
end
-- Freundesliste (C_FriendList, falls vorhanden)
local function friendInfo(name)
    if not name or not C_FriendList or not C_FriendList.GetFriendInfo then return nil end
    local ok, info = pcall(C_FriendList.GetFriendInfo, ns.ChatName(name))
    if ok and type(info) == "table" then return info end
end
function WL.Threads()
    local by, order = {}, {}
    for _, e in ipairs(log()) do
        local p = partnerOf(e)
        if p then
            local t = by[p]
            if not t then t = { name = p, msgs = {}, unread = 0, bn = e.bn } by[p] = t order[#order + 1] = t end
            t.msgs[#t.msgs + 1] = e
            t.last = e
            if e.new then t.unread = t.unread + 1 end
        end
    end
    -- neu angelegte Gespraeche ohne Nachricht
    for name, m in pairs(metaAll()) do
        if m.created and not by[name] then
            local t = { name = name, msgs = {}, unread = 0, last = { t = m.created, msg = "" }, fresh = true }
            by[name] = t order[#order + 1] = t
        end
    end
    for _, t in ipairs(order) do
        local m = meta(t.name)
        t.pin, t.mute = m and m.pin, m and m.mute
        if t.mute then t.unread = 0 end
        t.manual = m and m.unread and not t.mute
    end
    table.sort(order, function(a, b)
        if (a.pin and true or false) ~= (b.pin and true or false) then return a.pin and true or false end
        return (a.last.t or 0) > (b.last.t or 0)
    end)
    return order
end
-- Farbe je Name (fuer den Avatar-Kreis): gleiche Person = gleiche Farbe
local AV = { { 0.95, 0.45, 0.55 }, { 0.40, 0.75, 1.00 }, { 0.45, 0.85, 0.55 }, { 1.00, 0.70, 0.30 }, { 0.70, 0.55, 1.00 }, { 0.30, 0.85, 0.85 }, { 1.00, 0.55, 0.85 } }
local function avColor(name)
    local h = 0
    for i = 1, #(name or "") do h = (h * 31 + name:byte(i)) % 997 end
    return AV[h % #AV + 1]
end
local function initial(name)
    local n = ns.displayName and ns.displayName(name or "?") or (name or "?")
    return (n:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
end
local function dayLabel(t)
    local d, today = date("%Y%m%d", t), date("%Y%m%d")
    if d == today then return L["Heute"] end
    if d == date("%Y%m%d", time() - 86400) then return L["Gestern"] end
    return date(L["%d.%m.%Y"], t)
end
local function render(msg)
    msg = msg or ""
    if ns.Sound and ns.Sound.RenderCodes then
        local ok, r = pcall(ns.Sound.RenderCodes, msg)
        if ok and type(r) == "string" then msg = r end
    end
    if ns.Emoji and ns.Emoji.Render then
        ns.Emoji.sizeOverride = 16   -- passend zur Blasen-Schrift (vorher Groesse des WoW-Chats -> zu gross)
        local ok, r = pcall(ns.Emoji.Render, msg)
        ns.Emoji.sizeOverride = nil
        if ok and r then return r end
    end
    return msg
end
-- Text ohne Farb-/Link-/Bildcodes (Kopieren, Suche, Zitat)
local function plain(text)
    return ((text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
WL.Plain = plain
-- Zitat am Nachrichtenanfang: "»Name: Text« Antwort"
local QOPEN, QCLOSE = "\194\187", "\194\171"
local function splitQuote(msg)
    if type(msg) ~= "string" or msg:sub(1, 2) ~= QOPEN then return nil, msg end
    local s = msg:find(QCLOSE, 3, true)
    if not s then return nil, msg end
    return msg:sub(3, s - 1), (msg:sub(s + 2):gsub("^%s+", ""))
end
local function hashOf(s)
    local h = 5381
    s = plain(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return tostring(h)
end
local function emo(code)
    if ns.Emoji and ns.Emoji.Render then
        ns.Emoji.sizeOverride = 16
        local ok, r = pcall(ns.Emoji.Render, code)
        ns.Emoji.sizeOverride = nil
        if ok and r then return r end
    end
    return code
end
local REACTS = { ":+1:", ":lol:", "<3", ":fire:", ":tada:", ":eyes:" }

-- Messenger-Farben (dunkles Chat-App-Schema): eigene Blasen gruen-tuerkis, fremde schiefergrau
local WA = { bg = { 0.043, 0.071, 0.094 }, head = { 0.090, 0.118, 0.141 }, mine = { 0.000, 0.361, 0.294 }, other = { 0.145, 0.184, 0.220 },
    time = { 0.60, 0.68, 0.70 }, tick = { 0.33, 0.73, 0.95 } }

------------------------------------------------------------------------
-- kleine Fenster: Kopieren, Eingabe (Notiz / neues Gespraech), Rueckfrage
------------------------------------------------------------------------
local pop
local function popup()
    if pop then return pop end
    local f = CreateFrame("Frame", "OasisWhisperPopup", UIParent)
    f:SetSize(440, 150)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, { 0.04, 0.04, 0.05, 0.98 })
    K.Border(f, C.line)
    f.head = K.GameHead(f, "", C.pink)
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.head:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    local x = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
    x:SetPoint("TOPRIGHT", -6, -6)
    f.text = K.Text(f, 11, C.muted)
    f.text:SetPoint("TOPLEFT", 14, -38)
    f.text:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.text:SetWordWrap(true)
    -- einzeilige Eingabe
    f.input = K.Input(f, 412, "")
    f.input:SetPoint("TOPLEFT", 14, -62)
    f.input:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.input:SetHeight(26)
    f.input:SetScript("OnEnterPressed", function() if f.ok:IsShown() then f.ok:Click() end end)
    if K.AttachNameSuggest then pcall(function() f.suggest = K.AttachNameSuggest(f.input) end) end
    -- mehrzeiliges Kopierfeld
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 14, -58)
    sf:SetPoint("BOTTOMRIGHT", -14, 46)
    K.Fill(sf, C.field)
    K.Border(sf, C.line)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetTextInsets(6, 6, 6, 6)
    eb:SetWidth(400)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    -- nur kopieren, nicht veraendern
    eb:SetScript("OnTextChanged", function(self, user) if user and f.copyText then self:SetText(f.copyText) self:HighlightText() end end)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, eb:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
    end)
    sf:HookScript("OnSizeChanged", function(_, w) if w and w > 20 then eb:SetWidth(w - 4) end end)
    f.copySF, f.copy = sf, eb
    f.ok = K.Button(f, L["OK"], 100, 26, "primary", function()
        local fn = f.onOk
        local v = (f.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        f:Hide()
        if fn then fn(v) end
    end)
    f.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    f.cancel = K.Button(f, L["Abbrechen"], 100, 26, "ghost", function() f:Hide() end)
    f.cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
    f.hint = K.Text(f, 10, C.dim)
    f.hint:SetPoint("BOTTOMLEFT", 14, 20)
    f:SetScript("OnHide", function() f.onOk, f.copyText = nil, nil end)
    ns.EscClose("OasisWhisperPopup")
    f:Hide()
    pop = f
    return f
end
local function placePopup(f)
    f:ClearAllPoints()
    local main = ns.MainFrame and ns.MainFrame()
    if main and main:IsShown() then f:SetPoint("CENTER", main, "CENTER", 0, 30) else f:SetPoint("CENTER", 0, 60) end
end
function WL.Copy(title, text)
    local f = popup()
    f.head.text:SetText(K.Upper(title or L["Kopieren"]))
    f:SetSize(480, 340)
    f.text:SetText(L["Markiert - mit Strg+C kopieren."])
    f.input:Hide()
    if f.suggest and f.suggest.Hide then f.suggest:Hide() end
    f.copySF:Show()
    f.ok:Hide()
    f.cancel:Show()
    f.cancel.label:SetText(L["Schliessen"])
    f.hint:SetText("")
    f.copyText = text or ""
    f.copy:SetText(f.copyText)
    placePopup(f)
    f:Show()
    f.copySF:SetVerticalScroll(0)
    f.copy:SetFocus()
    f.copy:HighlightText()
end
function WL.Prompt(title, text, initialText, onOk, okLabel, hint)
    local f = popup()
    f.head.text:SetText(K.Upper(title or ""))
    f:SetSize(440, 150)
    f.text:SetText(text or "")
    f.copySF:Hide()
    f.input:Show()
    f.input:SetText(initialText or "")
    f.input.ph:SetShown((initialText or "") == "")
    f.ok:Show()
    f.ok.label:SetText(okLabel or L["OK"])
    f.cancel:Show()
    f.cancel.label:SetText(L["Abbrechen"])
    f.hint:SetText(hint or "")
    f.onOk = onOk
    placePopup(f)
    f:Show()
    f.input:SetFocus()
    f.input:HighlightText()
end
function WL.Confirm(title, text, onOk, okLabel)
    local f = popup()
    f.head.text:SetText(K.Upper(title or ""))
    f:SetSize(440, 120)
    f.text:SetText(text or "")
    f.copySF:Hide()
    f.input:Hide()
    f.ok:Show()
    f.ok.label:SetText(okLabel or L["OK"])
    f.cancel:Show()
    f.cancel.label:SetText(L["Abbrechen"])
    f.hint:SetText("")
    f.onOk = function() if onOk then onOk() end end
    placePopup(f)
    f:Show()
end

------------------------------------------------------------------------
-- Aktionen
------------------------------------------------------------------------
local function refreshAll()
    WL.ver = (WL.ver or 0) + 1
    if WL.priv and WL.priv:IsShown() then WL.RefreshPrivate() end
    if ns.RefreshPage then ns.RefreshPage("chat") end
end
function WL.Invite(name)
    if not name then return end
    local n = ns.ChatName(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, n)
    elseif InviteUnit then pcall(InviteUnit, n) end
end
function WL.AddFriend(name)
    if not name then return end
    local n = ns.ChatName(name)
    if C_FriendList and C_FriendList.AddFriend then pcall(C_FriendList.AddFriend, n)
    elseif AddFriend then pcall(AddFriend, n)
    else ns.print(L["Freundesliste ist hier nicht verfuegbar."]) end
end
function WL.ShowOnMap(name)
    local m = member(name)
    if not m or not ns.Map or not ns.Map.ShowMember then return end
    local ok, shown = pcall(ns.Map.ShowMember, m.name, m.zone)
    if not ok or not shown then ns.print(L["Position unbekannt."]) end
end
function WL.Export(name)
    local lines = {}
    for _, e in ipairs(log()) do
        if partnerOf(e) == name then
            local who = e.from and ns.displayName(e.from) or L["Du"]
            lines[#lines + 1] = date("[%d.%m.%Y %H:%M] ", e.t or 0) .. who .. ": " .. plain(e.msg)
        end
    end
    WL.Copy((L["Verlauf mit %s"]):format(ns.displayName(name)), table.concat(lines, "\n"))
end
function WL.DeleteThread(name)
    WL.Confirm(L["Gespraech loeschen"], (L["Den ganzen Verlauf mit %s loeschen? Gemerkte Nachrichten gehen mit."]):format(ns.displayName(name)), function()
        local l = log()
        for i = #l, 1, -1 do if partnerOf(l[i]) == name then table.remove(l, i) end end
        metaAll()[name] = nil
        if WL.privSel == name then WL.privSel = nil end
        refreshAll()
    end, L["Loeschen"])
end
function WL.EditNote(name)
    local m = meta(name, true)
    WL.Prompt(L["Notiz zur Person"], (L["Nur fuer dich sichtbar - steht im Kopf des Gespraechs mit %s."]):format(ns.displayName(name)), m.note or "", function(v)
        m.note = v ~= "" and v or nil
        refreshAll()
    end, L["Speichern"])
end
function WL.NewChat()
    WL.Prompt(L["Neues Gespraech"], L["Name eingeben - Gildenmitglieder werden vorgeschlagen."], "", function(v)
        if not v or v == "" then return end
        local m = member(v)
        local name = (m and m.name) or v
        -- schon vorhandenes Gespraech (gleicher vollstaendiger Name) weiterverwenden
        for _, th in ipairs(WL.Threads()) do if sameName(th.name, name) then name = th.name end end
        local hasMsgs = false
        for _, e in ipairs(log()) do if partnerOf(e) == name then hasMsgs = true break end end
        if not hasMsgs then meta(name, true).created = ns.now() end
        WL.privSel, WL.noAuto = name, nil
        WL.query = nil
        refreshAll()
        if WL.priv and WL.priv.input and WL.priv.input:IsShown() then WL.priv.input:SetFocus() end
    end, L["Starten"])
end
function WL.SetSelected(name)
    WL.privSel, WL.noAuto = name, nil
    local m = meta(name)
    if m then m.unread = nil end
    refreshAll()
end

-- Reaktion: lokal + optional als Addon-Nachricht an den Partner (nur wenn er Oasis hat)
local Comm = ns.Comm
local function partnerHasOasis(name)
    local R = ns.Radar
    if not R or not R.HasAddon then return false end
    local ok, r = pcall(R.HasAddon, ns.fullName(name))
    return ok and r and true or false
end
function WL.React(e, em)
    if not e then return end
    if e.rMe == em then em = nil end
    e.rMe = em
    local p = partnerOf(e)
    if S().wlReactSend ~= false and Comm and Comm.SendEx and p and not e.bn and partnerHasOasis(p) then
        -- nur an Online-Partner; Forever stellt Addon-Fluestern an den Vornamen nicht zu ("kein Spieler namens ...")
        -- -> Comm.Whisper nimmt fuer Gildenmitglieder den Gildenkanal mit Empfaenger
        local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[ns.fullName(p)]
        local online = m and m.online
        if online and Comm.Whisper and IsInGuild() then
            pcall(Comm.Whisper, p, "WLR", hashOf(e.msg), em or "-")
        end
    end
    refreshAll()
end
if Comm and Comm.On then
    Comm.On("WLR", function(sender, _, h, em)
        if not sender or not h or not ns.char or ns.isMe(sender) then return end
        if em == "-" then em = nil end
        if em and not ({ [":+1:"] = 1, [":lol:"] = 1, ["<3"] = 1, [":fire:"] = 1, [":tada:"] = 1, [":eyes:"] = 1 })[em] then return end
        local l = log()
        for i = #l, 1, -1 do
            local e = l[i]
            if sameName(partnerOf(e), sender) and hashOf(e.msg) == h then
                e.rThem = em
                refreshAll()
                return
            end
        end
    end)
end
function WL.ToggleStar(e)
    if not e then return end
    e.star = (not e.star) or nil
    refreshAll()
end
function WL.DeleteMsg(e)
    local l = log()
    for i = #l, 1, -1 do if l[i] == e then table.remove(l, i) break end end
    refreshAll()
end
function WL.Quote(e)
    local f = WL.priv
    if not f or not e then return end
    f.quote = e
    f:UpdateQuote()
    if f.input:IsShown() then f.input:SetFocus() end
end

-- Kontextmenue: Gespraech
function WL.ThreadMenu(owner, name)
    if not name then return end
    local m = meta(name) or {}
    local bn = false
    for _, e in ipairs(log()) do if partnerOf(e) == name and e.bn then bn = true break end end
    local mem = member(name)
    local items = {
        { text = m.pin and L["Losloesen"] or L["Anheften"], fn = function() local mm = meta(name, true) mm.pin = (not mm.pin) or nil refreshAll() end },
        { text = m.mute and L["Stummschaltung aufheben"] or L["Stummschalten"], fn = function()
            local mm = meta(name, true)
            mm.mute = (not mm.mute) or nil
            if mm.mute then for _, e in ipairs(log()) do if partnerOf(e) == name then e.new = nil end end mm.unread = nil end
            refreshAll()
        end },
        { text = L["Als ungelesen markieren"], fn = function()
            meta(name, true).unread = true
            if WL.privSel == name then WL.privSel, WL.noAuto = nil, true end
            refreshAll()
        end },
    }
    if not bn then
        items[#items + 1] = { text = L["Einladen"], fn = function() WL.Invite(name) end }
        items[#items + 1] = { text = L["Freund hinzufuegen"], disabled = not (C_FriendList and C_FriendList.AddFriend) and not AddFriend, fn = function() WL.AddFriend(name) end }
        if ns.Profile and ns.Profile.Show then items[#items + 1] = { text = L["Profil ansehen"], fn = function() ns.Profile.Show(name) end } end
        if ns.Talents then items[#items + 1] = { text = L["Talente ansehen"], fn = function() ns.Talents.Show(name) end } end
        items[#items + 1] = { text = L["Auf Karte zeigen"], disabled = not (mem and ns.Map and ns.Map.ShowMember), fn = function() WL.ShowOnMap(name) end }
    end
    items[#items + 1] = { text = m.note and L["Notiz bearbeiten"] or L["Notiz zur Person"], fn = function() WL.EditNote(name) end }
    items[#items + 1] = { text = L["Verlauf exportieren"], fn = function() WL.Export(name) end }
    items[#items + 1] = { text = L["Zuordnen zu ..."], fn = function() WL.AssignMenu(owner, name, bn) end }
    items[#items + 1] = { text = "|cffff5a4a" .. L["Gespraech loeschen"] .. "|r", fn = function() WL.DeleteThread(name) end }
    K.ShowMenu(owner, items, ns.displayName(name), 200)
end
-- Gespraech einer Person zuordnen (z.B. "Battle.net (alt)" -> "Anna Berg"): alle Nachrichten wandern hinueber.
-- Bei Battle.net-Gespraechen merkt sich Oasis die Zuordnung, kuenftige Nachrichten dieses BattleTags landen gleich dort.
function WL.Assign(from, to)
    if not (from and to) or from == to then return end
    for _, e in ipairs(log()) do
        if e.from == from then e.from = to e.viaBN = e.bn or e.viaBN e.bn = nil end
        if e.to == from then e.to = to e.viaBN = e.bn or e.viaBN e.bn = nil end
    end
    if from ~= L["Battle.net"] and from ~= L["Battle.net (alt)"] then
        ns.char.bnAlias = ns.char.bnAlias or {}
        ns.char.bnAlias[from] = to
    end
    if WL.privSel == from then WL.privSel = to end
    refreshAll()
    K.Toast(L["Zugeordnet"], (L["Verlauf von %s steht jetzt bei %s."]):format(from, ns.displayName(to)), C.mint)
end
function WL.AssignMenu(owner, name, bn)
    local seen, items = { [name] = true }, {}
    for i = #log(), 1, -1 do
        local e = log()[i]
        local p = partnerOf(e)
        if p and not seen[p] and not e.bn then
            seen[p] = true
            items[#items + 1] = { text = ns.displayName(p), fn = function() WL.Assign(name, p) end }
            if #items >= 12 then break end
        end
    end
    items[#items + 1] = { text = L["Name eingeben ..."], fn = function()
        WL.Prompt(L["Zuordnen zu ..."], L["Charaktername der Person (z.B. Anna Berg)"], "", function(v)
            v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if v ~= "" then WL.Assign(name, (ns.fullName and ns.fullName(v)) or v) end
        end)
    end }
    K.ShowMenu(owner, items, L["Zuordnen zu ..."], 200)
end
-- Kontextmenue: Nachricht
function WL.MsgMenu(owner, e)
    if not e then return end
    local items = {}
    for _, em in ipairs(REACTS) do
        items[#items + 1] = { text = emo(em) .. "  " .. (e.rMe == em and ("|cff66db9e" .. L["(deine Reaktion)"] .. "|r") or L["Reagieren"]), checked = e.rMe == em,
            fn = function() WL.React(e, em) end }
    end
    items[#items + 1] = { text = L["Kopieren"], fn = function() WL.Copy(L["Nachricht kopieren"], plain(e.msg)) end }
    if not e.bn then
        items[#items + 1] = { text = L["Antworten / Zitieren"], fn = function() WL.Quote(e) end }
    end
    items[#items + 1] = { text = e.star and L["Nicht mehr merken"] or L["Nachricht merken"], fn = function() WL.ToggleStar(e) end }
    items[#items + 1] = { text = "|cffff5a4a" .. L["Loeschen (nur bei dir)"] .. "|r", fn = function() WL.DeleteMsg(e) end }
    K.ShowMenu(owner, items, (e.from and ns.displayName(e.from) or L["Du"]) .. "  |cff777777" .. date("%d.%m. %H:%M", e.t or 0) .. "|r", 190)
end

-- Gildenchat: gemerkte Nachrichten (aus GuildChat.MsgMenu)
local function gcStars()
    ns.char.gcStars = ns.char.gcStars or {}
    return ns.char.gcStars
end
function WL.GuildStarred(key)
    if not ns.char or not key then return false end
    for _, s in ipairs(gcStars()) do if s.k == key then return true end end
    return false
end
function WL.ToggleGuildStar(key, sender, msg, ts)
    if not ns.char or not key then return end
    local l = gcStars()
    for i, s in ipairs(l) do if s.k == key then table.remove(l, i) refreshAll() return false end end
    l[#l + 1] = { k = key, s = sender, m = msg, t = ts or ns.now() }
    while #l > 200 do table.remove(l, 1) end
    refreshAll()
    return true
end

------------------------------------------------------------------------
-- Ansicht
------------------------------------------------------------------------
local FILTERS = { { key = "all", text = "Alle" }, { key = "unread", text = "Ungelesen" }, { key = "pin", text = "Angeheftet" }, { key = "star", text = "Gemerkt" } }
ns.Relabel(function()
    FILTERS[1].text, FILTERS[2].text, FILTERS[3].text, FILTERS[4].text = L["Alle"], L["Ungelesen"], L["Angeheftet"], L["Gemerkt"]
end)
local function lowerFind(hay, q) return q and q ~= "" and plain(hay or ""):lower():find(q, 1, true) end
-- Treffer hervorheben (nur in reinem Text ohne Codes, sonst unveraendert)
local function mark(text, q)
    if not q or q == "" or (text or ""):find("|", 1, true) then return text end
    local low = text:lower()
    local out, pos = {}, 1
    while true do
        local a, b = low:find(q, pos, true)
        if not a then break end
        out[#out + 1] = text:sub(pos, a - 1) .. "|cffffd24a" .. text:sub(a, b) .. "|r"
        pos = b + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end
local function noAnim() return S().noAnim end

local function statusOf(name, bn)
    if not name then return "" end
    if bn then
        local b = WL.BnInfo(name)
        if b then
            local parts = { "Battle.net" }
            if b.lvl and b.lvl > 0 then parts[#parts + 1] = (L["Level %d"]):format(b.lvl) end
            if b.class then parts[#parts + 1] = b.class end
            if b.zone and b.zone ~= "" then parts[#parts + 1] = b.zone end
            return table.concat(parts, "  ·  ")
        end
        return L["Battle.net"]
    end
    local m = member(name)
    local fi = friendInfo(name)
    local online = (m and m.online) or (fi and fi.connected)
    local parts = {}
    parts[1] = online and ("|cff66db9e" .. L["online"] .. "|r") or ("|cff777777" .. ((m or fi) and L["offline"] or L["offline oder nicht in der Gilde"]) .. "|r")
    local cls = (m and m.class) or nil
    local clsName = cls and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or (fi and fi.className)
    local lvl = (m and tonumber(m.level) and m.level > 0 and m.level) or (fi and fi.level)
    if clsName or lvl then
        local hex = cls and ns.classHex and ns.classHex(cls)
        parts[#parts + 1] = (hex and ("|c" .. hex) or "|cffcccccc") .. ((lvl and (L["Stufe"] .. " " .. lvl .. " ") or "") .. (clsName or "")) .. "|r"
    end
    local zone = (m and m.zone ~= "" and m.zone) or (fi and fi.area)
    if online and zone then parts[#parts + 1] = "|cff9aa3a8" .. zone .. "|r" end
    if not m and fi then parts[#parts + 1] = "|cff8fb8ff" .. L["Freund"] .. "|r" end
    return table.concat(parts, "  |cff555555·|r  ")
end
local function isOnline(name)
    local m = member(name)
    if m and m.online then return true end
    local fi = friendInfo(name)
    return fi and fi.connected and true or false
end

------------------------------------------------------------------------
-- Design-Bausteine der Privat-Ansicht (runde Flaechen, Klassenkreise)
------------------------------------------------------------------------
local DOT = ns.MEDIA .. "dot"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
-- abgerundetes Rechteck als 9-Slice: Ecken aus Media\skins\round_fill (wie ns.Insta.Glass), Kanten + Mitte einfarbig
local ROUND_FILL = ns.MEDIA .. "skins\\round_fill"
local function roundBox(owner, layer, r, sub)
    local o = { t = {} }
    local function tex()
        local t = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        o.t[#o.t + 1] = t
        return t
    end
    for _, d in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local t = tex()
        t:SetTexture(ROUND_FILL)
        t:SetTexCoord(d[2], d[3], d[4], d[5])
        t:SetSize(r, r)
        t:SetPoint(d[1])
    end
    local top = tex() top:SetPoint("TOPLEFT", r, 0) top:SetPoint("TOPRIGHT", -r, 0) top:SetHeight(r)
    local bot = tex() bot:SetPoint("BOTTOMLEFT", r, 0) bot:SetPoint("BOTTOMRIGHT", -r, 0) bot:SetHeight(r)
    local mid = tex() mid:SetPoint("TOPLEFT", 0, -r) mid:SetPoint("BOTTOMRIGHT", 0, r)
    function o:SetColor(cr, cg, cb, a)
        for i, t in ipairs(self.t) do
            if i <= 4 then t:SetVertexColor(cr, cg, cb, a or 1) else t:SetColorTexture(cr, cg, cb, a or 1) end
        end
    end
    function o:SetAlpha(a) for _, t in ipairs(self.t) do t:SetAlpha(a) end end
    function o:SetShown(v) for _, t in ipairs(self.t) do t:SetShown(v) end end
    return o
end
-- ruhiger Glasknopf (primaer = dezent getoent)
local function glassBtn(parent, text, w, h, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.box = roundBox(b, "BACKGROUND", 6)
    b.label = K.Text(b, 12, primary and C.text or C.muted, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    function b:Paint(hover)
        local ac = C.accent
        if primary then self.box:SetColor(ac[1], ac[2], ac[3], hover and 0.30 or 0.20)
        else self.box:SetColor(1, 1, 1, hover and 0.09 or 0.05) end
    end
    b:SetScript("OnEnter", function(self) self:Paint(true) self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    b:SetScript("OnLeave", function(self) self:Paint(false) local c = primary and C.text or C.muted self.label:SetTextColor(c[1], c[2], c[3]) end)
    b:SetScript("OnClick", onClick)
    b:Paint(false)
    return b
end
local function mix(a, b, t) return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t end
-- Klasse zu einem Gespraechspartner (Gilde, sonst Freundesliste ueber den Klassennamen)
local function classOf(name, bn)
    if not name or bn then return nil end
    local m = member(name)
    if m and m.class then return m.class end
    local fi = friendInfo(name)
    if fi and fi.className and LOCALIZED_CLASS_NAMES_MALE then
        for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE) do if v == fi.className then return k end end
    end
end
-- runder Avatar: Klassensymbol (wie GuildInfo) oder Anfangsbuchstabe, Ring, Online-Punkt
local function makeAvatar(parent, size, dot)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(size, size)
    a.ring = a:CreateTexture(nil, "BORDER")
    a.ring:SetTexture(DOT)
    a.ring:SetPoint("CENTER")
    a.ring:SetSize(size + 2, size + 2)
    a.bg = a:CreateTexture(nil, "ARTWORK", nil, 0)
    a.bg:SetTexture(DOT)
    a.bg:SetPoint("CENTER")
    a.bg:SetSize(size - 1, size - 1)
    a.icon = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.icon:SetPoint("CENTER")
    a.icon:SetSize(size - 3, size - 3)
    if a.CreateMaskTexture then
        local ok, m = pcall(a.CreateMaskTexture, a)
        if ok and m then
            pcall(function()
                m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(a.icon)
                a.icon:AddMaskTexture(m)
            end)
        end
    end
    if K.RoundMask then pcall(K.RoundMask, a.icon, a.icon, math.floor((size - 3) / 2)) end
    a.ini = K.Title(a, math.max(9, math.floor(size * 0.42)), C.text, "CENTER")
    a.ini:SetPoint("CENTER", 0, 0)
    if dot and dot > 0 then
        a.rim = a:CreateTexture(nil, "OVERLAY", nil, 0)
        a.rim:SetTexture(DOT)
        a.rim:SetSize(dot + 4, dot + 4)
        a.rim:SetPoint("CENTER", a, "BOTTOMRIGHT", -dot * 0.35, dot * 0.35)
        a.rim:SetVertexColor(WA.head[1], WA.head[2], WA.head[3])
        a.on = a:CreateTexture(nil, "OVERLAY", nil, 1)
        a.on:SetTexture(DOT)
        a.on:SetSize(dot, dot)
        a.on:SetPoint("CENTER", a.rim, "CENTER", 0, 0)
    end
    return a
end
-- online: true/false = Punkt gruen/grau, nil = kein Punkt
local function setAvatar(a, name, bn, online)
    local cls = classOf(name, bn)
    local GI = ns.GuildInfo
    local okIcon = false
    if cls and GI and GI.SetClassIcon then
        local ok, r = pcall(GI.SetClassIcon, a.icon, cls)
        okIcon = ok and r and true or false
    end
    if okIcon then
        local r, g, b = ns.classColor(cls)
        a.icon:Show() a.ini:Hide()
        a.ring:SetVertexColor(r, g, b, 0.95)
        a.bg:SetVertexColor(0.06, 0.07, 0.08)
    else
        local ac = avColor(name or "?")
        a.icon:Hide() a.ini:Show()
        a.ini:SetText(initial(name))
        a.ini:SetTextColor(ac[1], ac[2], ac[3])
        a.ring:SetVertexColor(ac[1] * 0.6, ac[2] * 0.6, ac[3] * 0.6, 0.9)
        a.bg:SetVertexColor(ac[1] * 0.25, ac[2] * 0.25, ac[3] * 0.25)
    end
    if a.on then
        a.on:SetShown(online ~= nil) a.rim:SetShown(online ~= nil)
        if online then a.on:SetVertexColor(0.40, 0.86, 0.62) else a.on:SetVertexColor(0.45, 0.47, 0.50) end
    end
end
-- Kopfzeile: Zustand (on/off/afk/bn) + Text "Stufe 28 Krieger · Gebiet"
local function headStatus(name, bn)
    if bn then
        local b = WL.BnInfo(name)
        local parts = {}
        if b then
            if b.lvl and b.lvl > 0 then parts[#parts + 1] = (L["Level %d"]):format(b.lvl) end
            if b.class then parts[#parts + 1] = b.class end
            if b.zone and b.zone ~= "" then parts[#parts + 1] = b.zone end
        end
        return "bn", table.concat(parts, "  |cff555555·|r  ")
    end
    local m, fi = member(name), friendInfo(name)
    local online = (m and m.online) or (fi and fi.connected)
    local afk = online and ((m and (m.status == 1 or m.status == "<AFK>")) or (fi and fi.afk))
    local parts = {}
    local cls = m and m.class
    local clsName = cls and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or (fi and fi.className)
    local lvl = (m and tonumber(m.level) and m.level > 0 and m.level) or (fi and fi.level)
    if clsName or lvl then
        local hex = cls and ns.classHex and ns.classHex(cls)
        parts[#parts + 1] = (hex and ("|c" .. hex) or "|cffcccccc") .. ((lvl and (L["Stufe"] .. " " .. lvl .. " ") or "") .. (clsName or "")) .. "|r"
    end
    local zone = (m and m.zone ~= "" and m.zone) or (fi and fi.area)
    if online and zone then parts[#parts + 1] = "|cff9aa3a8" .. zone .. "|r" end
    if not m and fi then parts[#parts + 1] = "|cff8fb8ff" .. L["Freund"] .. "|r" end
    if not m and not fi then parts[#parts + 1] = "|cff777777" .. L["nicht in der Gilde"] .. "|r" end
    return afk and "afk" or (online and "on" or "off"), table.concat(parts, "  |cff555555·|r  ")
end
-- runder Symbol-Knopf (Kopf): Kreis, Symbol oder Zeichen, Tooltip
local function roundBtn(parent, size, icon, glyph, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetTexture(DOT)
    b.bg:SetAllPoints()
    b.bg:SetVertexColor(1, 1, 1, 0.07)
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetTexture(icon)
        b.icon:SetSize(size * 0.55, size * 0.55)
        b.icon:SetPoint("CENTER")
        b.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
    else
        b.label = K.Title(b, math.floor(size * 0.5), C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 2)
        b.label:SetText(glyph or "")
    end
    local function tint(c) if b.icon then b.icon:SetVertexColor(c[1], c[2], c[3]) else b.label:SetTextColor(c[1], c[2], c[3]) end end
    b:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.22)
        tint(C.text)
        if tip then K.ShowTip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.07)
        tint(C.muted)
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35) end)
    b:SetScript("OnMouseUp", function(self) self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.22) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

function WL.BuildPrivate(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 30)
    f:EnableMouse(true)
    f.bg = K.Fill(f, C.bg)
    WL.filter = WL.filter or "all"
    local LEFT = 278
    -- Unterhaltungen (wie eine Chat-App: Avatar, Name, letzte Nachricht, Zeit, Ungelesen-Zahl)
    local lp = K.Panel(f, C.panel)
    lp:SetPoint("TOPLEFT") lp:SetPoint("BOTTOMLEFT")
    lp:SetWidth(LEFT)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(lp, nil, nil, 12) end   -- Glaskarte wie im Gildenchat
    -- 0.6.285: ruhiger Kopf - Suche, daneben zwei kleine Knoepfe (+ neues Gespraech, ... mehr); darunter Text-Reiter
    f.newBtn = roundBtn(lp, 26, nil, "+", { L["Neues Gespraech"] }, function() WL.NewChat() end)
    f.moreList = roundBtn(lp, 26, nil, "...", { L["Mehr"] }, function(self)
        K.ShowMenu(self, {
            { text = L["Alle gelesen"], fn = function()
                for _, e in ipairs(log()) do e.new = nil end
                for _, m in pairs(metaAll()) do m.unread = nil end
                refreshAll()
            end },
            { text = L["Neues Gespraech"], fn = function() WL.NewChat() end },
        }, L["Privat"], 170)
    end)
    f.moreList.isDropdown = true
    f.moreList:SetPoint("TOPRIGHT", -10, -10)
    f.newBtn:SetPoint("RIGHT", f.moreList, "LEFT", -6, 0)
    f.search = K.Input(lp, LEFT - 86, L["Suchen ..."], function(t)
        f.searchGen = (f.searchGen or 0) + 1
        local g = f.searchGen
        ns.After(0.25, function()
            if g ~= f.searchGen then return end
            t = (t or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
            WL.query = #t >= 2 and t or nil
            WL.RefreshPrivate()
        end)
    end)
    f.search:SetPoint("TOPLEFT", 10, -10)
    f.search:SetPoint("RIGHT", f.newBtn, "LEFT", -8, 0)
    f.search:SetHeight(26)
    -- Suchfeld als Glasfeld (eigene Flaeche/Rahmen des Feldes ausblenden)
    if f.search.bg then f.search.bg:SetColorTexture(0, 0, 0, 0) end
    K.SetBorderColor(f.search, { 0, 0, 0, 0 })
    f.search.glass = roundBox(f.search, "BACKGROUND", 13, -1)
    f.search.glass:SetColor(1, 1, 1, 0.05)
    f.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() WL.query = nil WL.RefreshPrivate() end)
    -- Reiter als schlichter Text mit Strich unter dem gewaehlten (keine Kaesten)
    f.filter = CreateFrame("Frame", nil, lp)
    f.filter:SetPoint("TOPLEFT", 10, -44)
    f.filter:SetSize(LEFT - 20, 22)
    f.filter.buttons = {}
    local fx = 0
    for i, it in ipairs(FILTERS) do
        local b = CreateFrame("Button", nil, f.filter)
        b.key = it.key
        b:SetHeight(22)
        b.label = K.Text(b, 11, C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 1)
        b.label:SetText(it.text)
        b:SetWidth((b.label:GetStringWidth() or 40) + 14)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 6, 0) b.line:SetPoint("BOTTOMRIGHT", -6, 0)
        b.line:SetHeight(2)
        b:SetPoint("LEFT", fx, 0)
        fx = fx + b:GetWidth() + 2
        b:SetScript("OnClick", function() WL.filter = it.key WL.RefreshPrivate() end)
        b:SetScript("OnEnter", function(self) if WL.filter ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
        b:SetScript("OnLeave", function() f.filter:Select(WL.filter or "all") end)
        f.filter.buttons[i] = b
    end
    function f.filter:Select(key)
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            b.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], on and 0.9 or 0)
        end
    end
    f.filterLine = lp:CreateTexture(nil, "BORDER")
    f.filterLine:SetPoint("TOPLEFT", f.filter, "BOTTOMLEFT", 0, 0)
    f.filterLine:SetPoint("RIGHT", -10, 0)
    f.filterLine:SetHeight(1)
    f.filterLine:SetColorTexture(1, 1, 1, 0.06)
    -- Liste: eine Zeile je Person (Main + Twinks), bzw. Treffer bei Suche/Gemerkt
    f.threads = K.List(lp, 56, function(l)
        local r = K.Row(l)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if r.stripe then r.stripe:SetAlpha(0) end
        if r.hl then r.hl:SetAlpha(0) end
        r.hov = roundBox(r, "BACKGROUND", 8, 2)
        r.hov:SetColor(1, 1, 1, 0.045)
        r.hov:SetAlpha(0)
        r.selBox = roundBox(r, "BACKGROUND", 8, 3)
        r.selBox:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
        r.selBox:SetShown(false)
        r.av = makeAvatar(r, 34, 10)
        r.av:SetPoint("LEFT", 8, 0)
        r.when = K.Text(r, 10, C.dim, "RIGHT")
        r.when:SetPoint("TOPRIGHT", -10, -11)
        r.name = K.Text(r, 13, C.text)
        r.name:SetPoint("TOPLEFT", 52, -10)
        r.name:SetPoint("RIGHT", r.when, "LEFT", -8, 0)
        r.name:SetWordWrap(false)
        r.prev = K.Text(r, 11, C.dim)
        r.prev:SetPoint("TOPLEFT", 52, -30)
        r.prev:SetPoint("RIGHT", -34, 0)
        r.prev:SetWordWrap(false)
        r.pill = r:CreateTexture(nil, "ARTWORK")
        r.pill:SetTexture(ns.MEDIA .. "dot")
        r.pill:SetSize(18, 18)
        r.pill:SetPoint("BOTTOMRIGHT", -10, 8)
        r.badge = K.Text(r, 10, C.text, "CENTER")
        r.badge:SetPoint("CENTER", r.pill, "CENTER", 0, 0)
        r.flags = K.Text(r, 10, C.dim, "RIGHT")
        r.flags:SetPoint("BOTTOMRIGHT", -10, 10)
        r:SetScript("OnClick", function(self, btn)
            local it = self.it
            if not it then return end
            if it.hit then
                if it.guild then
                    if ns.GuildChat then ns.GuildChat.mode = "guild" end
                    ns.RefreshPage("chat")
                    return
                end
                if btn == "RightButton" then WL.MsgMenu(self, it.hit) return end
                WL.jump = it.hit
                WL.SetSelected(it.name)
                return
            end
            -- Person: an den passenden Charakter schreiben (online zuerst); Rechtsklick wie bisher je Charakter
            local target = WL.PersonOf({ it }, WL.privSel) and WL.privSel or WL.BestChar(it, isOnline)
            if btn == "RightButton" then WL.ThreadMenu(self, target) return end
            WL.SetSelected(target)
        end)
        r:SetScript("OnEnter", function(self)
            if K.Tween and not noAnim() then
                K.Tween(self.hov, 0.12, function(p) self.hov:SetAlpha(p) end)
            else self.hov:SetAlpha(1) end
            local it = self.it
            if not it then return end
            local lines = { ns.displayName(it.main or it.name or "?") }
            if it.hit then
                lines[#lines + 1] = date(L["%d.%m.%Y %H:%M"], it.hit.t or 0)
                lines[#lines + 1] = it.guild and L["Klick: zum Gildenchat"] or L["Klick: zur Nachricht springen"]
            else
                if it.chars and #it.chars > 1 then
                    local t = {}
                    for _, th in ipairs(it.chars) do t[#t + 1] = WL.Label(th.name) end
                    lines[#lines + 1] = "|cff888888" .. L["Charaktere"] .. ":|r " .. table.concat(t, ", ")
                end
                local m = meta(it.name)
                if m and m.note then lines[#lines + 1] = "|cffe8b44a" .. L["Notiz"] .. ":|r " .. m.note end
                lines[#lines + 1] = "|cff888888" .. L["Rechtsklick: mehr"] .. "|r"
            end
            K.ShowTip(self, lines)
        end)
        r:SetScript("OnLeave", function(self)
            if K.Tween and not noAnim() then
                K.Tween(self.hov, 0.14, function(p) self.hov:SetAlpha(1 - p) end)
            else self.hov:SetAlpha(0) end
            GameTooltip:Hide()
        end)
        return r
    end, function(r, it)
        r.it = it
        r.hov:SetAlpha(0)
        if K.Tween then K.Tween(r.hov, 0.01, function() end) end
        local name = it.name or "?"
        local onl
        if not it.guild and not it.bn then
            for _, th in ipairs(it.chars or { it }) do if isOnline(th.name) then onl, name = true, th.name break end end
        end
        setAvatar(r.av, name, it.bn, onl)
        r.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        if it.hit then
            -- Treffer / gemerkte Nachricht
            local e = it.hit
            r.name:SetText(WL.Label(it.name or "?") .. (it.guild and ("  |cff888888" .. L["Gildenchat"] .. "|r") or ""))
            local txt = plain(e.msg or e.m)
            r.prev:SetText(((e.to and ("|cff888888" .. L["Du"] .. ":|r ")) or "") .. (e.star and "|cffe8b44a*|r " or "") .. mark(txt, WL.query))
            r.when:SetText(date(L["%d.%m."], e.t or 0))
            r.pill:Hide() r.badge:SetText("") r.flags:SetText("")
            r.when:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
            r.sel:SetShown(false)
            r.selBox:SetShown(false)
            return
        end
        -- Name der Person (Main); mehrere Charaktere: dezente Zahl dahinter
        local many = it.chars and #it.chars > 1
        r.name:SetText(WL.Label(it.main or name) .. (many and ("  |cff666666" .. #it.chars .. " " .. L["Chars"] .. "|r") or ""))
        local last = it.last or {}
        if it.fresh then
            r.prev:SetText("|cff888888" .. L["Neues Gespraech"] .. "|r")
        else
            local m = meta(it.name)
            local draft = m and m.draft and m.draft ~= "" and S().wlDrafts ~= false and WL.privSel ~= it.name
            -- kam die letzte Nachricht von einem Twink, steht sein Name davor
            local who = (last.to and (L["Du"] .. ": ")) or ((many and it.name ~= it.main) and (WL.Label(it.name) .. ": ")) or ""
            r.prev:SetText(draft and ("|cffff7a7a" .. L["Entwurf"] .. ":|r " .. m.draft) or ((who ~= "" and ("|cff888888" .. who .. "|r") or "") .. render(last.msg or "")))
        end
        local shownTime = last.t or 0
        local today = date("%Y%m%d", shownTime) == date("%Y%m%d")
        r.when:SetText(today and date("%H:%M", shownTime) or date(L["%d.%m."], shownTime))
        local num = it.unread or 0
        local un = num > 0 or it.manual
        r.pill:SetShown(un and true or false)
        r.pill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        r.pill:SetSize(num > 0 and 18 or 9, num > 0 and 18 or 9)
        r.badge:SetText(num > 0 and tostring(math.min(99, num)) or "")
        r.badge:SetTextColor(1, 1, 1)
        r.when:SetTextColor(unpack(un and C.accent or C.dim))
        if not un then r.name:SetTextColor(0.86, 0.86, 0.88) end
        r.flags:SetText(un and "" or (((it.pin and ("|T" .. ns.MEDIA .. "icons\\pin:12:12|t") or "")) .. (it.mute and " |cff777777" .. L["stumm"] .. "|r" or "")))
        r.sel:SetShown(false)
        r.selBox:SetShown(WL.PersonOf({ it }, WL.privSel) ~= nil)
    end)
    f.threads:SetPoint("TOPLEFT", 6, -74)
    f.threads:SetPoint("BOTTOMRIGHT", -6, 8)
    f.threads.empty:SetText("")
    -- Leerzustand links (keine Gespraeche / keine Treffer)
    local le = CreateFrame("Frame", nil, lp)
    le:SetPoint("TOPLEFT", 8, -96)
    le:SetPoint("RIGHT", -8, 0)
    le:SetHeight(130)
    le.icon = le:CreateTexture(nil, "ARTWORK")
    le.icon:SetTexture(ns.MEDIA .. "icons\\badges\\whisper")
    le.icon:SetSize(36, 36)
    le.icon:SetPoint("TOP", 0, 0)
    le.icon:SetVertexColor(C.pink[1], C.pink[2], C.pink[3], 0.7)
    le.text = K.Text(le, 11, C.dim, "CENTER")
    le.text:SetPoint("TOP", le.icon, "BOTTOM", 0, -8)
    le.text:SetPoint("LEFT", 4, 0) le.text:SetPoint("RIGHT", -4, 0)
    le.text:SetWordWrap(true)
    le:Hide()
    f.lempty = le

    -- Verlauf rechts
    local rp = K.Panel(f, C.panel)
    rp:SetPoint("TOPLEFT", LEFT + 12, 0)
    rp:SetPoint("BOTTOMRIGHT")
    f.rp = rp
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(rp, nil, nil, 12) end
    -- Kopf: Avatar + Name + Status + Knoepfe
    local hd = CreateFrame("Frame", nil, rp)
    hd:SetPoint("TOPLEFT", 1, -1) hd:SetPoint("TOPRIGHT", -1, -1)
    hd:SetHeight(56)
    hd:EnableMouse(true)
    -- Kopf ohne eigene eckige Flaeche (die Glaskarte ist der Hintergrund), nur feine Linie
    hd.line = hd:CreateTexture(nil, "BORDER")
    hd.line:SetPoint("BOTTOMLEFT", 12, 0) hd.line:SetPoint("BOTTOMRIGHT", -12, 0)
    hd.line:SetHeight(1)
    hd.line:SetColorTexture(1, 1, 1, 0.06)
    f.hav = makeAvatar(hd, 38, 11)
    f.hav:SetPoint("LEFT", 12, 0)
    f.more = roundBtn(hd, 28, nil, "...", { L["Mehr"] }, function(self) if WL.privSel then WL.ThreadMenu(self, WL.privSel) end end)
    f.more:SetPoint("RIGHT", -12, 0)
    f.more.isDropdown = true
    f.profile = roundBtn(hd, 28, ns.MEDIA .. "icons\\profile", nil, { L["Profil"] }, function() if WL.privSel and ns.Profile then ns.Profile.Show(WL.privSel) end end)
    f.profile:SetPoint("RIGHT", f.more, "LEFT", -6, 0)
    f.invite = roundBtn(hd, 28, ns.MEDIA .. "icons\\groups", nil, { L["Einladen"] }, function() WL.Invite(WL.privSel) end)
    f.invite:SetPoint("RIGHT", f.profile, "LEFT", -6, 0)
    f.hname = K.Title(hd, 15, C.text)
    f.hname:SetPoint("TOPLEFT", 62, -10)
    f.hname:SetPoint("RIGHT", f.invite, "LEFT", -10, 0)
    f.hname:SetWordWrap(false)
    -- Status-Pille (online / offline / AFK / Battle.net)
    f.hpill = CreateFrame("Frame", nil, hd)
    f.hpill:SetSize(50, 15)
    f.hpill:SetPoint("TOPLEFT", f.hname, "BOTTOMLEFT", 0, -4)
    f.hpill.box = roundBox(f.hpill, "BACKGROUND", 7)
    f.hpill.t = K.Text(f.hpill, 9, C.text, "CENTER")
    f.hpill.t:SetPoint("CENTER", 0, 0)
    -- 0.6.285: an welchen Charakter geschrieben wird (nur bei mehreren Charakteren der Person)
    f.hto = CreateFrame("Button", nil, hd)
    f.hto:SetHeight(16)
    f.hto:SetPoint("LEFT", f.hpill, "RIGHT", 8, 0)
    f.hto.t = K.Text(f.hto, 10, C.muted)
    f.hto.t:SetPoint("LEFT", 0, 0)
    f.hto:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { L["Schreiben an"], "|cff888888" .. L["Klick: anderen Charakter waehlen"] .. "|r" }) end)
    f.hto:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
    f.hto:SetScript("OnClick", function(self)
        local p = f.person
        if not p then return end
        local items = {}
        for _, th in ipairs(p.chars) do
            local n = th.name
            items[#items + 1] = { text = WL.Label(n) .. (isOnline(n) and ("  |cff66db9e" .. L["online"] .. "|r") or ""), checked = n == WL.privSel,
                fn = function() WL.SetSelected(n) end }
        end
        K.ShowMenu(self, items, L["Schreiben an"], 200)
    end)
    f.hto.isDropdown = true
    f.hto:Hide()
    f.hstate = K.Text(hd, 10, C.dim)
    f.hstate:SetPoint("LEFT", f.hpill, "RIGHT", 8, 0)
    f.hstate:SetPoint("RIGHT", f.invite, "LEFT", -10, 0)
    f.hstate:SetWordWrap(false)
    hd:SetScript("OnEnter", function(self)
        local n = WL.privSel
        if not n then return end
        local m = meta(n)
        local lines = { ns.displayName(n), statusOf(n, f.selBN) }
        if m and m.note then lines[#lines + 1] = "|cffe8b44a" .. L["Notiz"] .. ":|r " .. m.note end
        K.ShowTip(self, lines)
    end)
    hd:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Nachrichten: eigene Scrollflaeche mit Sprechblasen variabler Hoehe
    local sf = CreateFrame("ScrollFrame", nil, rp)
    sf:SetPoint("TOPLEFT", 1, -57)
    sf:SetPoint("BOTTOMRIGHT", -1, 52)
    sf:SetClipsChildren(true)
    -- Hintergrund: leichter Verlauf (oben etwas heller) + dezenter Schein in Akzentfarbe
    local cbg = sf:CreateTexture(nil, "BACKGROUND", nil, -2)
    cbg:SetAllPoints()
    cbg:SetColorTexture(WA.bg[1], WA.bg[2], WA.bg[3], 1)
    K.Gradient(cbg, "VERTICAL", { WA.bg[1] * 0.8, WA.bg[2] * 0.8, WA.bg[3] * 0.8, 1 }, { WA.bg[1] * 1.45, WA.bg[2] * 1.35, WA.bg[3] * 1.3, 1 })
    f.cbg = cbg
    -- Farbe/Deckkraft aus der Chat-Darstellung (Einstellungen > Bereiche > Chat)
    f.lookBg = sf:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.lookBg:SetAllPoints()
    f.lookBg:SetColorTexture(0, 0, 0, 0)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(10, 10)
    sf:SetScrollChild(content)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 50)))
    end)
    f.sf, f.content = sf, content
    -- schmale Scrollleiste rechts (ziehbar)
    local track = CreateFrame("Frame", nil, rp)
    track:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -3, -4)
    track:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -3, 4)
    track:SetWidth(5)
    track:SetFrameLevel(sf:GetFrameLevel() + 10)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.05)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(5)
    thumb.t = thumb:CreateTexture(nil, "ARTWORK")
    thumb.t:SetAllPoints()
    thumb.t:SetColorTexture(1, 1, 1, 0.28)
    thumb:SetScript("OnEnter", function(self) self.t:SetColorTexture(1, 1, 1, 0.5) end)
    thumb:SetScript("OnLeave", function(self) if not self.drag then self.t:SetColorTexture(1, 1, 1, 0.28) end end)
    local function updThumb()
        local ch, vh = content:GetHeight() or 1, sf:GetHeight() or 1
        local max = math.max(0, ch - vh)
        track:SetShown(max > 1)
        if max <= 1 then return end
        local th = math.max(24, (track:GetHeight() or 100) * vh / ch)
        thumb:SetHeight(th)
        local pos = ((track:GetHeight() or 100) - th) * (sf:GetVerticalScroll() / max)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos)
    end
    f.updThumb = updThumb
    sf:SetScript("OnVerticalScroll", updThumb)
    sf:HookScript("OnScrollRangeChanged", updThumb)
    thumb:SetScript("OnMouseDown", function(self)
        self.drag = true
        local _, cy = GetCursorPosition()
        self.y0, self.s0 = cy / self:GetEffectiveScale(), sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(me)
            local _, y = GetCursorPosition()
            y = y / me:GetEffectiveScale()
            local max = math.max(0, content:GetHeight() - sf:GetHeight())
            local room = math.max(1, track:GetHeight() - me:GetHeight())
            sf:SetVerticalScroll(math.max(0, math.min(max, me.s0 + (me.y0 - y) * max / room)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.drag = nil
        self:SetScript("OnUpdate", nil)
        self.t:SetColorTexture(1, 1, 1, 0.28)
    end)
    -- Leerzustand rechts: Symbol + Aktion
    local re = CreateFrame("Frame", nil, sf)
    re:SetSize(300, 140)
    re:SetPoint("CENTER")
    re.icon = re:CreateTexture(nil, "ARTWORK")
    re.icon:SetTexture(ns.MEDIA .. "icons\\badges\\whisper")
    re.icon:SetSize(44, 44)
    re.icon:SetPoint("TOP", 0, 0)
    re.icon:SetVertexColor(C.pink[1], C.pink[2], C.pink[3], 0.6)
    re.text = K.Text(re, 12, C.dim, "CENTER")
    re.text:SetPoint("TOP", re.icon, "BOTTOM", 0, -10)
    re.text:SetWidth(300)
    re.text:SetWordWrap(true)
    re.btn = K.Button(re, L["Neues Gespraech"], 150, 26, "primary", function() WL.NewChat() end)
    re.btn:SetPoint("TOP", re.text, "BOTTOM", 0, -12)
    re:Hide()
    f.rempty = re
    f.bubbles, f.seps = {}, {}

    local function onLink(self, link, text, button)
        if ns.Sound and ns.Sound.OnLink and ns.Sound.OnLink(link) then return end
        if SetItemRef then pcall(SetItemRef, link, text, button, self) end
    end
    local function bubble(i)
        local b = f.bubbles[i]
        if b then return b end
        b = CreateFrame("Button", nil, content)
        b:RegisterForClicks("RightButtonUp")
        -- abgerundete Blase (Flaeche, Hover-Schimmer, Sprung-Aufblitzen)
        b.box = roundBox(b, "BACKGROUND", 12)
        function b:SetBoxColor(r, g, bb, a) self.box:SetColor(r, g, bb, a or 1) end
        b.hl = roundBox(b, "HIGHLIGHT", 12)
        b.hl:SetColor(1, 1, 1, 0.05)
        b.flash = roundBox(b, "ARTWORK", 12)
        b.flash:SetColor(1, 0.82, 0.29, 0.35)
        b.flash:SetAlpha(0)
        -- Zitat in der Blase: dunklere Karte mit Farbbalken
        b.qf = CreateFrame("Frame", nil, b)
        b.qf:SetHeight(20)
        b.qf.box = roundBox(b.qf, "BACKGROUND", 5)
        b.qf.box:SetColor(0, 0, 0, 0.22)
        b.qbar = b.qf:CreateTexture(nil, "ARTWORK")
        b.qbar:SetWidth(2)
        b.qbar:SetPoint("TOPLEFT", 4, -4) b.qbar:SetPoint("BOTTOMLEFT", 4, 4)
        b.quote = K.Text(b.qf, 10, C.muted)
        b.quote:SetWordWrap(false)
        b.quote:SetPoint("LEFT", 11, 0)
        b.quote:SetPoint("RIGHT", -6, 0)
        b.txt = K.Text(b, 12, C.text)
        b.txt:SetWordWrap(true)
        b.txt:SetJustifyV("TOP")
        b.time = K.Text(b, 9, C.dim, "RIGHT")
        -- kleiner Avatar links neben der ersten Blase einer Gruppe (nur fremde)
        b.av = makeAvatar(content, 24)
        b.av:SetPoint("TOPRIGHT", b, "TOPLEFT", -7, 0)
        b.av:Hide()
        -- Reaktionen als Chip unter der Blase
        b.rc = CreateFrame("Frame", nil, content)
        b.rc:SetSize(30, 18)
        b.rc:SetFrameLevel(b:GetFrameLevel() + 2)
        b.rc.box = roundBox(b.rc, "BACKGROUND", 9)
        b.rc.box:SetColor(WA.head[1] * 1.15, WA.head[2] * 1.15, WA.head[3] * 1.15, 1)
        b.react = K.Text(b.rc, 12, C.text, "CENTER")
        b.react:SetPoint("CENTER", 0, 0)
        b.rc:Hide()
        -- Item- und andere Links in der Blase anklickbar
        if b.SetHyperlinksEnabled then pcall(b.SetHyperlinksEnabled, b, true) end
        b:SetScript("OnHyperlinkClick", onLink)
        b:SetScript("OnHyperlinkEnter", function(self, link)
            if type(link) == "string" and (link:find("^item:") or link:find("^spell:") or link:find("^quest:") or link:find("^achievement:")) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self, btn) if btn == "RightButton" and self.e then WL.MsgMenu(self, self.e) end end)
        b:SetScript("OnEnter", function(self)
            local e = self.e
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine(date(L["%A, %d.%m.%Y %H:%M:%S"], e.t or 0), 1, 1, 1)
            if e.star then GameTooltip:AddLine(L["Gemerkt"], 0.91, 0.71, 0.29) end
            GameTooltip:AddLine(L["Rechtsklick: Kopieren, Zitieren, Reagieren, Merken"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bubbles[i] = b
        return b
    end
    local function sep(i)
        local s = f.seps[i]
        if s then return s end
        s = CreateFrame("Frame", nil, content)
        -- Trenner: durchgehende Linie, in der Mitte eine Pille mit Text
        s:SetSize(90, 20)
        s.line = s:CreateTexture(nil, "BACKGROUND")
        s.line:SetHeight(1)
        s.line:SetPoint("LEFT") s.line:SetPoint("RIGHT")
        s.p = CreateFrame("Frame", nil, s)
        s.p:SetPoint("CENTER")
        s.p:SetSize(80, 22)
        s.p.box = roundBox(s.p, "BACKGROUND", 11)
        s.t = K.Text(s.p, 10, C.muted, "CENTER")
        s.t:SetPoint("CENTER", 0, 0)
        f.seps[i] = s
        return s
    end
    -- msgs: Liste, opts.newFrom = Index der ersten ungelesenen, opts.jump = Nachricht, opts.keep = Scrollstand halten
    function f:SetMessages(msgs, opts)
        opts = opts or {}
        for _, b in ipairs(self.bubbles) do b:Hide() b.rc:Hide() b.av:Hide() b.e = nil end
        for _, s in ipairs(self.seps) do s:Hide() end
        local W = sf:GetWidth()
        if not W or W < 100 then W = 600 end
        content:SetWidth(W)
        local maxW = math.floor(W * 0.68)
        local q = WL.query
        local y, lastDay, nsep, lastWho = -10, nil, 0, nil
        local jumpY
        -- eigene Blasen: Akzentfarbe gedaempft (folgt dem Farbschema), fremde schiefergrau-blau
        local GCx = ns.GuildChat
        local mr, mg, mb = mix(WA.bg, C.accent, 0.42)
        local orr, og, ob = WA.other[1], WA.other[2], WA.other[3]
        local tr, tg, tbb = C.text[1], C.text[2], C.text[3]
        local zr, zg, zb = WA.time[1], WA.time[2], WA.time[3]
        local font, fsize, showT = K.FONT, 12, true
        if GCx and GCx.Look then
            mr, mg, mb = GCx.MineBubbleColor()
            orr, og, ob = GCx.LookColor("chatBubbleOther")
            tr, tg, tbb = GCx.LookColor("chatTextColor")
            zr, zg, zb = GCx.LookColor("chatTimeColor")
            font, fsize = GCx.LookFont(), (tonumber(GCx.Look("chatFontSize")) or 13) - 1
            showT = GCx.Look("chatShowTime") ~= false
        end
        -- Gruppen: gleiche Seite, gleicher Tag, hoechstens 3 Minuten Abstand, nicht ueber die Neu-Linie
        local gStart, gEnd = {}, {}
        for i, e in ipairs(msgs) do
            local p = msgs[i - 1]
            local cont = p and ((p.to ~= nil) == (e.to ~= nil)) and date("%Y%m%d", p.t or 0) == date("%Y%m%d", e.t or 0)
                and math.abs((e.t or 0) - (p.t or 0)) <= 180 and opts.newFrom ~= i and not (p.rMe or p.rThem)
                and (not opts.multi or partnerOf(p) == partnerOf(e))   -- 0.6.285: Charakterwechsel beendet die Gruppe
            gStart[i] = not cont
            if i > 1 then gEnd[i - 1] = not cont end
        end
        gEnd[#msgs] = true
        local function placeSep(s, text, tr, tg, tb, lr, lg, lb, la)
            s.t:SetText(text)
            s.t:SetTextColor(tr, tg, tb)
            s.line:SetColorTexture(lr, lg, lb, la)
            s.p:SetWidth((s.t:GetStringWidth() or 60) + 22)
            s:SetWidth(W - 40)
            s:ClearAllPoints()
            s:SetPoint("TOP", content, "TOPLEFT", W / 2, y)
            s:Show()
        end
        local animFrom = (not noAnim() and K.Tween and opts.animFrom) or nil
        for i, e in ipairs(msgs) do
            local day = date("%Y%m%d", e.t or 0)
            if day ~= lastDay then
                nsep = nsep + 1
                local s = sep(nsep)
                s.p.box:SetColor(1, 1, 1, 0.06)
                placeSep(s, dayLabel(e.t or 0), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1, 0.07)
                y = y - 32
                lastDay = day
            end
            -- 0.6.285: gemeinsamer Verlauf mehrerer Charaktere - beim Wechsel eine leise Zeile "ueber <Charakter>"
            local who = partnerOf(e)
            if opts.multi and who ~= lastWho then
                nsep = nsep + 1
                local s = sep(nsep)
                s.p.box:SetColor(1, 1, 1, 0)
                placeSep(s, (L["ueber %s"]):format(WL.Label(who or "?")), C.dim[1], C.dim[2], C.dim[3], 1, 1, 1, 0)
                y = y - 24
            end
            lastWho = who
            if opts.newFrom == i then
                -- Trennlinie "Neue Nachrichten"
                nsep = nsep + 1
                local s = sep(nsep)
                s.p.box:SetColor(1, 0.62, 0.55, 0.08)
                placeSep(s, L["Neue Nachrichten"], 1, 0.62, 0.55, 1, 0.45, 0.38, 0.35)
                if not opts.jump then jumpY = -y - 10 end
                y = y - 30
            end
            local mine = e.to ~= nil
            local first, last = gStart[i], gEnd[i]
            local showTime = (showT and last) or e.star
            local b = bubble(i)
            b.e = e
            K.SetFontSafe(b.txt, font, fsize, "", K.FONT)
            b.txt:SetTextColor(tr, tg, tbb)
            local quote, body = splitQuote(e.msg)
            b.txt:SetWidth(maxW - 24)
            b.txt:SetText(mark(render(body), q))
            if ns.Emoji and ns.Emoji.Track then ns.Emoji.Track(b.txt) end
            local tw = b.txt.GetUnboundedStringWidth and b.txt:GetUnboundedStringWidth() or b.txt:GetStringWidth() or maxW
            local qh = 0
            if quote then
                b.quote:SetText(render(quote))
                if ns.Emoji and ns.Emoji.Track then ns.Emoji.Track(b.quote) end
                local qw = b.quote.GetUnboundedStringWidth and b.quote:GetUnboundedStringWidth() or b.quote:GetStringWidth() or 0
                tw = math.max(tw, math.min(qw + 20, maxW - 24))
                qh = 24
            end
            b.time:SetText((e.star and "|cffe8b44a*|r " or "") .. ((showT and last) and date("%H:%M", e.t or 0) or ""))
            local bw = math.max(showTime and 64 or 40, math.min(maxW, tw + 26))
            b.txt:SetWidth(bw - 24)
            local th = b.txt:GetStringHeight() or 14
            local bh = th + 18 + qh + (showTime and 11 or 0)
            if i > 1 then y = y - (first and 10 or 2) end
            b:ClearAllPoints()
            b:SetSize(bw, math.max(26, bh))
            b.qf:SetShown(quote ~= nil)
            if quote then
                b.qf:ClearAllPoints()
                b.qf:SetPoint("TOPLEFT", 7, -7)
                b.qf:SetPoint("TOPRIGHT", -7, -7)
                b.qbar:SetColorTexture(mine and 1 or C.accent[1], mine and 1 or C.accent[2], mine and 1 or C.accent[3], mine and 0.6 or 0.9)
            end
            b.txt:ClearAllPoints()
            b.txt:SetPoint("TOPLEFT", 12, -9 - qh)
            b.time:ClearAllPoints()
            b.time:SetPoint("BOTTOMRIGHT", -10, 5)
            b.time:SetShown(showTime and true or false)
            if mine then b:SetBoxColor(mr, mg, mb, 1) else b:SetBoxColor(orr, og, ob, 1) end
            if mine then b.time:SetTextColor(0.80, 0.80, 0.82, 0.75) else b.time:SetTextColor(zr, zg, zb, 0.9) end
            local ax = mine and (W - 18) or 48
            local pt = mine and "TOPRIGHT" or "TOPLEFT"
            b.anc, b.ax, b.ay = pt, ax, y
            b:SetPoint(pt, content, "TOPLEFT", ax, y)
            if not mine and first then
                setAvatar(b.av, e.from, e.bn)
                b.av:Show()
            end
            b.flash:SetAlpha(0)
            b:Show()
            if opts.jump == e then jumpY = -y - 40 b.doFlash = true else b.doFlash = nil end
            y = y - math.max(20, bh)
            -- Reaktionen als Chip unter der Blase
            if e.rMe or e.rThem then
                local parts = {}
                if e.rThem then parts[#parts + 1] = emo(e.rThem) end
                if e.rMe and e.rMe ~= e.rThem then parts[#parts + 1] = emo(e.rMe) end
                if e.rMe and e.rMe == e.rThem then parts[#parts] = parts[#parts] .. "|cff999999 2|r" end
                b.react:SetText(table.concat(parts, " "))
                b.rc:SetWidth(math.max(26, (b.react:GetStringWidth() or 16) + 14))
                b.rc:ClearAllPoints()
                if mine then b.rc:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -8, 5) else b.rc:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 8, 5) end
                b.rc:Show()
                y = y - 14
            end
            -- weiche Einblendung nur fuer neu hinzugekommene Nachrichten im offenen Gespraech
            if animFrom and i >= animFrom then
                b:SetAlpha(0) b.rc:SetAlpha(0) b.av:SetAlpha(0)
                b.tw = true
                K.Tween(b, 0.28, function(p)
                    b:SetAlpha(p) b.rc:SetAlpha(p) b.av:SetAlpha(p)
                    b:SetPoint(b.anc, content, "TOPLEFT", b.ax, b.ay - 14 * (1 - p))
                end, function()
                    b.tw = nil
                    b:SetAlpha(1) b.rc:SetAlpha(1) b.av:SetAlpha(1)
                    b:SetPoint(b.anc, content, "TOPLEFT", b.ax, b.ay)
                end)
                -- Sicherheitsnetz: nie unsichtbar haengen bleiben
                local ay = b.ay
                ns.After(1, function()
                    if b.tw and b.ay == ay then
                        b.tw = nil
                        b:SetAlpha(1) b.rc:SetAlpha(1) b.av:SetAlpha(1)
                        b:SetPoint(b.anc, content, "TOPLEFT", b.ax, b.ay)
                    end
                end)
            else
                if b.tw then b.tw = nil K.Tween(b, 0.01, function() end) end
                b:SetAlpha(1) b.rc:SetAlpha(1) b.av:SetAlpha(1)
            end
        end
        content:SetHeight(math.max(10, -y + 12))
        local keepAt = opts.keep and sf:GetVerticalScroll()
        C_Timer.After(0, function()
            local max = math.max(0, content:GetHeight() - sf:GetHeight())
            if keepAt then sf:SetVerticalScroll(math.min(max, keepAt))
            elseif jumpY then sf:SetVerticalScroll(math.max(0, math.min(max, jumpY)))
            else sf:SetVerticalScroll(max) end
            if f.updThumb then f.updThumb() end
            for _, b in ipairs(f.bubbles) do
                if b.doFlash and b:IsShown() then
                    b.doFlash = nil
                    if noAnim() or not K.Tween then
                        b.flash:SetAlpha(0.8)
                        C_Timer.After(1.2, function() b.flash:SetAlpha(0) end)
                    else
                        K.Tween(b.flash, 1.6, function(p) b.flash:SetAlpha(0.9 * (1 - p)) end)
                    end
                end
            end
        end)
    end

    -- Zitat-Vorschau ueber der Eingabe
    local qb = CreateFrame("Frame", nil, rp)
    qb:SetPoint("BOTTOMLEFT", 10, 54) qb:SetPoint("BOTTOMRIGHT", -10, 54)
    qb:SetHeight(28)
    qb:SetFrameLevel(rp:GetFrameLevel() + 20)
    qb.box = roundBox(qb, "BACKGROUND", 8)
    qb.box:SetColor(WA.head[1] * 1.2, WA.head[2] * 1.2, WA.head[3] * 1.2, 0.97)
    qb.bar = qb:CreateTexture(nil, "ARTWORK")
    qb.bar:SetPoint("TOPLEFT", 8, -6) qb.bar:SetPoint("BOTTOMLEFT", 8, 6)
    qb.bar:SetWidth(3)
    qb.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    qb.t = K.Text(qb, 11, C.muted)
    qb.t:SetPoint("LEFT", 18, 0)
    qb.t:SetPoint("RIGHT", -34, 0)
    qb.t:SetWordWrap(false)
    qb.x = K.CloseButton(qb, function() f.quote = nil f:UpdateQuote() end, L["Zitat entfernen"])
    qb.x:SetPoint("RIGHT", -6, 0)
    qb:Hide()
    f.qb = qb
    local function quoteText(e)
        local _, body = splitQuote(e.msg)
        local t = plain(body)
        if #t > 60 then t = t:sub(1, 58) .. ".." end
        return (e.from and ns.displayName(e.from) or L["Du"]) .. ": " .. t
    end
    f.quoteText = quoteText

    -- Eingabe: Emoji | Sound | Feld | Zaehler | Senden
    local bar = CreateFrame("Frame", nil, rp)
    bar:SetPoint("BOTTOMLEFT", 1, 1) bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetHeight(50)
    bar.line = bar:CreateTexture(nil, "BORDER")
    bar.line:SetPoint("TOPLEFT", 12, 0) bar.line:SetPoint("TOPRIGHT", -12, 0)
    bar.line:SetHeight(1)
    bar.line:SetColorTexture(1, 1, 1, 0.06)
    -- durchgehende abgerundete Leiste (Rand + Flaeche), Senden-Knopf rechts daneben
    local pill = CreateFrame("Frame", nil, bar)
    pill:SetPoint("TOPLEFT", 10, -8)
    pill:SetPoint("BOTTOMRIGHT", -52, 8)
    pill.edge = roundBox(pill, "BACKGROUND", 17, 0)
    pill.edge:SetColor(1, 1, 1, 0.10)
    pill.inner = CreateFrame("Frame", nil, pill)
    pill.inner:SetPoint("TOPLEFT", 1, -1) pill.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    pill.fill = roundBox(pill.inner, "BACKGROUND", 16, 0)
    pill.fill:SetColor(WA.bg[1], WA.bg[2], WA.bg[3], 1)
    f.pill = pill
    f.emo = CreateFrame("Button", nil, pill)
    f.emo:SetFrameLevel(pill.inner:GetFrameLevel() + 2)
    f.emo:SetSize(22, 22)
    f.emo:SetPoint("LEFT", 9, 0)
    f.emo.icon = f.emo:CreateTexture(nil, "ARTWORK")
    f.emo.icon:SetAllPoints()
    f.emo.icon:SetTexture(ns.MEDIA .. "emoji\\smile")
    f.emo.icon:SetDesaturated(true)
    f.emo:SetScript("OnEnter", function(self) self.icon:SetDesaturated(false) K.ShowTip(self, { L["Emojis"] }) end)
    f.emo:SetScript("OnLeave", function(self) self.icon:SetDesaturated(true) GameTooltip:Hide() end)
    f.emo:SetScript("OnClick", function(self)
        if ns.Emoji then ns.Emoji.target = f.input ns.Emoji.TogglePicker(self) end
    end)
    -- Sound nur an diese Person (wie der Knopf am WoW-Chat beim Fluestern)
    f.snd = CreateFrame("Button", nil, pill)
    f.snd:SetFrameLevel(pill.inner:GetFrameLevel() + 2)
    f.snd:SetSize(18, 18)
    f.snd:SetPoint("LEFT", f.emo, "RIGHT", 6, 0)
    f.snd.icon = f.snd:CreateTexture(nil, "ARTWORK")
    f.snd.icon:SetAllPoints()
    f.snd.icon:SetTexture(ns.MEDIA .. "icons\\speaker")
    f.snd.icon:SetVertexColor(0.6, 0.6, 0.62)
    f.snd:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        K.ShowTip(self, { L["Sound schicken"], L["Nur diese Person hoert ihn (wenn sie Oasis hat)."] })
    end)
    f.snd:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.62) GameTooltip:Hide() end)
    if ns.Sound and ns.Sound.AttachCooldown then pcall(ns.Sound.AttachCooldown, f.snd) end
    f.snd:SetScript("OnClick", function(self)
        local who = WL.privSel
        if not who or not ns.Sound or not ns.Sound.OpenPicker then return end
        if ns.Sound.SetSendTarget then ns.Sound.SetSendTarget("WHISPER", who) end
        ns.Sound.restoreChat = nil   -- hier gibt es keine WoW-Eingabe wiederherzustellen
        ns.Sound.OpenPicker(self, nil, function(k)
            ns.Sound.SendInChat(k, "WHISPER", ns.ChatName(who))
            if f.input:IsShown() then f.input:SetFocus() end
        end, "send")
    end)
    f.input = K.Input(pill, 300, L["Nachricht schreiben ..."], nil)
    f.input:SetFrameLevel(pill.inner:GetFrameLevel() + 2)
    if ns.EmojiComplete and ns.EmojiComplete.Attach then pcall(ns.EmojiComplete.Attach, f.input) end
    -- Feld ohne eigenen Kasten (die Leiste ist der Kasten)
    if f.input.GetRegions then
        for _, rg in ipairs({ f.input:GetRegions() }) do
            if rg.GetObjectType and rg:GetObjectType() == "Texture" then rg:SetAlpha(0) end
        end
    end
    f.input:HookScript("OnEditFocusGained", function() pill.edge:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.55) end)
    f.input:HookScript("OnEditFocusLost", function() pill.edge:SetColor(1, 1, 1, 0.10) end)
    f.counter = K.Text(pill, 9, C.dim, "RIGHT")
    -- runder Senden-Knopf mit Pfeil (aktiv nur mit Text, Schein beim Ueberfahren)
    local sb = CreateFrame("Button", nil, bar)
    sb:SetSize(34, 34)
    sb:SetPoint("RIGHT", -10, 0)
    sb.glow = sb:CreateTexture(nil, "BACKGROUND", nil, -1)
    sb.glow:SetTexture(ns.MEDIA .. "dot")
    sb.glow:SetPoint("CENTER")
    sb.glow:SetSize(48, 48)
    sb.glow:SetBlendMode("ADD")
    sb.glow:Hide()
    sb.bg = sb:CreateTexture(nil, "BACKGROUND")
    sb.bg:SetTexture(ns.MEDIA .. "dot")
    sb.bg:SetAllPoints()
    sb.arrow = {}
    for i, d in ipairs({ { 2, 12, 0, -1, 0 }, { 2, 9, -2.8, 2.6, -math.pi / 4 }, { 2, 9, 2.8, 2.6, math.pi / 4 } }) do
        local t = sb:CreateTexture(nil, "ARTWORK")
        t:SetSize(d[1], d[2])
        t:SetPoint("CENTER", d[3], d[4])
        t:SetColorTexture(1, 1, 1, 1)
        if d[5] ~= 0 and t.SetRotation then pcall(t.SetRotation, t, d[5]) end
        sb.arrow[i] = t
    end
    function sb:Paint()
        local on = self.active
        local ac = C.accent
        if on then self.bg:SetVertexColor(ac[1] * 0.8, ac[2] * 0.8, ac[3] * 0.8, self.hover and 0.95 or 0.75) else self.bg:SetVertexColor(1, 1, 1, 0.07) end
        for _, t in ipairs(self.arrow) do t:SetAlpha(on and 1 or 0.35) end
        self.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
        self.glow:SetShown(false)   -- kein Schein (ruhiges Design)
    end
    function sb:SetActive(on) self.active = on and true or false self:Paint() end
    sb:SetScript("OnEnter", function(self) self.hover = true self:Paint() K.ShowTip(self, { L["Senden"], "|cff888888" .. L["Enter"] .. "|r" }) end)
    sb:SetScript("OnLeave", function(self) self.hover = nil self:Paint() GameTooltip:Hide() end)
    sb:SetScript("OnClick", function(self) if self.active then f:Send() end end)
    sb:SetActive(false)
    f.send = sb
    f.counter:SetPoint("RIGHT", pill, "RIGHT", -14, 0)
    f.counter:SetWidth(46)
    f.input:SetPoint("LEFT", f.snd, "RIGHT", 6, 0)
    f.input:SetPoint("RIGHT", f.counter, "LEFT", -4, 0)
    f.input:SetHeight(30)
    f.input:SetMaxLetters(255)
    local function prefix()
        if not f.quote then return "" end
        return QOPEN .. quoteText(f.quote) .. QCLOSE .. " "
    end
    function f:UpdateCounter()
        local n = #(self.input:GetText() or "") + #prefix()
        local c = n > 255 and C.red or (n > 220 and C.amber or C.dim)
        -- dezent: Zaehler erst ab 150 Zeichen
        self.counter:SetText(n >= 150 and (n .. "/255") or "")
        self.counter:SetTextColor(c[1], c[2], c[3])
        local has = (self.input:GetText() or ""):find("%S") ~= nil
        if self.send.SetActive then self.send:SetActive(has and not self.selBN) end
    end
    function f:UpdateQuote()
        local q = self.quote
        qb:SetShown(q ~= nil and self.input:IsShown())
        if q then qb.t:SetText(K.hex(C.accent) .. L["Antwort auf"] .. "|r  " .. render(quoteText(q))) end
        sf:SetPoint("BOTTOMRIGHT", -1, (q and self.input:IsShown()) and 86 or 52)
        self:UpdateCounter()
    end
    function f:Send()
        local t = (self.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" or not WL.privSel or self.selBN then return end
        local msg = prefix() .. t
        if #msg > 255 then msg = msg:sub(1, 255) end
        local ok = pcall(SendChatMessage, msg, "WHISPER", nil, ns.ChatName(WL.privSel))
        if not ok then ns.print(L["Senden fehlgeschlagen."]) return end
        -- fuer Pfeil hoch: zuletzt Gesendetes
        WL.sent = WL.sent or {}
        table.insert(WL.sent, 1, t)
        while #WL.sent > 20 do table.remove(WL.sent) end
        f.input.histIdx = nil
        self.quote = nil
        local m = meta(WL.privSel)
        if m then m.draft = nil end
        self.input:SetText("")
        self:UpdateQuote()
    end
    f.input:SetScript("OnEnterPressed", function() f:Send() end)
    f.input:HookScript("OnTextChanged", function(self, user)
        f:UpdateCounter()
        if user and WL.privSel and S().wlDrafts ~= false then
            local t = self:GetText() or ""
            local m = meta(WL.privSel, t ~= "")
            if m then m.draft = t ~= "" and t or nil end
        end
    end)
    -- Pfeil hoch/runter: zuletzt gesendete Nachrichten zurueckholen (zum Wiederholen/Bearbeiten)
    K.InputHistory(f.input, function()
        local list = {}
        for i, s in ipairs(WL.sent or {}) do list[i] = s end
        -- noch nichts gesendet in dieser Sitzung: eigene Nachrichten aus dem Verlauf
        if #list == 0 and WL.privSel then
            for i = #log(), 1, -1 do
                local e = log()[i]
                if e.to == WL.privSel then local _, b = splitQuote(e.msg) list[#list + 1] = b if #list >= 20 then break end end
            end
        end
        return list
    end)
    f:HookScript("OnSizeChanged", function() if f.lastMsgs then f.sig = nil WL.RefreshPrivate() end end)
    -- Gildenchat-Verlauf darf nie durchscheinen: Flaechen deckend
    if f.bg and f.bg.SetColorTexture then f.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1) end
    f:Hide()
    WL.priv = f
    return f
end

-- Chat-Darstellung geaendert: Hintergrund umfaerben, Blasen beim naechsten Zeichnen neu aufbauen
function WL.ApplyLook()
    local f = WL.priv
    if not f then return end
    local GCx = ns.GuildChat
    if f.lookBg and GCx and GCx.LookColor then
        local r, g, b = GCx.LookColor("chatBgColor")
        local a = (tonumber(GCx.Look("chatBgAlpha")) or 90) / 100
        if ns.Insta and ns.Insta.Glass and f.rp then
            -- Farbe auf die runde Karte legen, eckige Flaechen im Verlauf durchsichtig
            ns.Insta.Glass(f.rp, { r, g, b, a }, nil, 12)
            f.lookBg:SetColorTexture(0, 0, 0, 0)
            if f.cbg then f.cbg:Hide() end
        else
            f.lookBg:SetColorTexture(r, g, b, a)
        end
    end
    f.sig = nil
    if f:IsShown() then WL.RefreshPrivate() end
end

-- Kopf (Status live) ohne den Verlauf neu aufzubauen
function WL.UpdateHead()
    local f = WL.priv
    if not f or not f:IsShown() then return end
    local name = WL.privSel
    -- 0.6.285: Kopf zeigt die Person (Main), der Ziel-Charakter steht im Knopf "an <Charakter>"
    local p = name and WL.PersonOf(WL.People(WL.Threads()), name)
    f.person = p
    f.hname:SetText(name and WL.Label((p and p.main) or name) or L["Privat"])
    local cls = name and classOf(name, f.selBN)
    if cls then f.hname:SetTextColor(ns.classColor(cls)) else f.hname:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    f.hav:SetShown(name ~= nil)
    local key, st = "off", ""
    if name then
        key, st = headStatus(name, f.selBN)
        setAvatar(f.hav, name, f.selBN, key ~= "bn" and (key ~= "off") or nil)
        if key == "off" then f.hav.on:Show() f.hav.rim:Show() f.hav.on:SetVertexColor(0.45, 0.47, 0.50) end
        if key == "afk" then f.hav.on:SetVertexColor(C.amber[1], C.amber[2], C.amber[3]) end
    end
    -- Status-Pille
    local PC = { on = { C.mint, L["online"] }, afk = { C.amber, L["AFK"] }, off = { { 0.55, 0.57, 0.60 }, L["offline"] }, bn = { C.blue, L["Battle.net"] } }
    local pc = PC[key] or PC.off
    f.hpill:SetShown(name ~= nil)
    f.hpill.t:SetText(pc[2])
    f.hpill.t:SetTextColor(pc[1][1], pc[1][2], pc[1][3])
    f.hpill.box:SetColor(pc[1][1], pc[1][2], pc[1][3], 0.16)
    f.hpill:SetWidth(math.max(30, (f.hpill.t:GetStringWidth() or 30) + 14))
    local m = name and meta(name)
    if m and m.note then st = st .. (st ~= "" and "  |cff555555·|r  " or "") .. "|cffe8b44a" .. L["Notiz"] .. ":|r |cffbbbbbb" .. m.note .. "|r" end
    f.hstate:SetText(st)
    local multi = p ~= nil and #p.chars > 1
    f.hto:SetShown(multi)
    f.hstate:ClearAllPoints()
    if multi then
        f.hto.t:SetText((L["an %s"]):format(WL.Label(name)) .. " |cff777777v|r")
        f.hto:SetWidth((f.hto.t:GetStringWidth() or 60) + 4)
        f.hstate:SetPoint("LEFT", f.hto, "RIGHT", 10, 0)
    else
        f.hstate:SetPoint("LEFT", f.hpill, "RIGHT", 8, 0)
    end
    f.hstate:SetPoint("RIGHT", f.invite, "LEFT", -10, 0)
    local can = name ~= nil and not f.selBN
    f.profile:SetShown(can and ns.Profile ~= nil)
    f.invite:SetShown(can)
    f.more:SetShown(name ~= nil)
end

-- 0.6.285: Personen statt Twink-Baum. Alle Gespraeche mit den Charakteren eines Spielers (Main + Twinks, ns.Alts)
-- bilden EINE Zeile und EINEN gemeinsamen Verlauf. Geschrieben wird an WL.privSel (ein echter Charakter) -
-- standardmaessig an den, der gerade online ist bzw. zuletzt geschrieben hat; im Kopf umstellbar.
-- Battle.net-Kontakte bleiben eigene Personen (auch bei gleichem Namen). Einstellung wlGroupAlts = false: jeder
-- Charakter ist eine eigene Person.
local function personKey(th)
    local function key(n) return (ns.NameKey and ns.NameKey(n)) or tostring(n):lower() end
    local grp = ns.Alts and ns.Alts.Main and not (ns.db and ns.db.settings and ns.db.settings.wlGroupAlts == false)
    local main = (grp and not th.bn and th.name and ns.Alts.Main(th.name)) or th.name
    return (th.bn and "bn:" or "char:") .. key(main), main
end
function WL.People(threads)
    local by, out = {}, {}
    for _, th in ipairs(threads) do
        local k, main = personKey(th)
        local p = by[k]
        if not p then
            p = { person = true, key = k, main = main, name = th.name, bn = th.bn, chars = {}, unread = 0, last = th.last, fresh = true }
            by[k] = p
            out[#out + 1] = p
        end
        p.chars[#p.chars + 1] = th
        p.unread = p.unread + (th.unread or 0)
        if th.manual then p.manual = true end
        if th.pin then p.pin = true end
        if th.mute then p.mute = true end
        if not th.fresh then p.fresh = nil end
        -- Zeile zeigt die neueste Nachricht der Person; name = Charakter dieser Nachricht
        if ((th.last and th.last.t) or 0) > ((p.last and p.last.t) or 0) then p.last, p.name = th.last, th.name end
    end
    table.sort(out, function(a, b)
        if (a.pin and true or false) ~= (b.pin and true or false) then return a.pin and true or false end
        return ((a.last and a.last.t) or 0) > ((b.last and b.last.t) or 0)
    end)
    return out
end
-- Person, zu der ein Charakter gehoert
function WL.PersonOf(people, name)
    if not name then return nil end
    for _, p in ipairs(people) do
        for _, th in ipairs(p.chars) do if th.name == name then return p end end
    end
end
-- gemeinsamer Verlauf aller Charaktere, zeitlich (bei gleicher Sekunde nach Eingang)
function WL.PersonMsgs(p)
    if not p then return {} end
    if #p.chars == 1 then return p.chars[1].msgs end
    local all = {}
    for _, th in ipairs(p.chars) do for _, e in ipairs(th.msgs) do all[#all + 1] = e end end
    table.sort(all, function(a, b)
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
        return (a.id or 0) < (b.id or 0)
    end)
    return all
end
-- an wen schreiben: online zuerst, sonst der Charakter mit der neuesten Nachricht
function WL.BestChar(p, online)
    if not p then return nil end
    local best, bestOn
    for _, th in ipairs(p.chars) do
        local on = online and online(th.name) and true or false
        local t = (th.last and th.last.t) or 0
        if not best or (on and not bestOn) or (on == bestOn and t > ((best.last and best.last.t) or 0)) then best, bestOn = th, on end
    end
    return best and best.name
end

local function buildList(threads)
    local q, filt = WL.query, WL.filter or "all"
    local out = {}
    if filt == "star" or q then
        -- Nachrichten-Treffer (Suche) bzw. Merkliste, neueste zuerst
        local l = log()
        for i = #l, 1, -1 do
            local e = l[i]
            local okF = filt ~= "star" or e.star
            if okF and (not q or lowerFind(e.msg, q)) then
                out[#out + 1] = { hit = e, name = partnerOf(e), bn = e.bn }
                if #out >= 300 then break end
            end
        end
        if filt == "star" and ns.char then
            for i = #gcStars(), 1, -1 do
                local s = gcStars()[i]
                if not q or lowerFind(s.m, q) then out[#out + 1] = { hit = { m = s.m, t = s.t, from = s.s, star = true }, name = s.s, guild = true } end
            end
            table.sort(out, function(a, b) return (a.hit.t or 0) > (b.hit.t or 0) end)
        end
        return out
    end
    for _, p in ipairs(WL.People(threads)) do
        if filt == "all" or (filt == "unread" and (p.unread > 0 or p.manual)) or (filt == "pin" and p.pin) then out[#out + 1] = p end
    end
    return out
end

function WL.RefreshPrivate()
    local f = WL.priv
    if not f or not f:IsShown() then return end
    local threads = WL.Threads()
    if WL.privSel then
        local found = false
        for _, th in ipairs(threads) do if th.name == WL.privSel then found = true end end
        if not found then WL.privSel = nil end
    end
    -- 0.6.285: geoeffnet ist eine Person (alle Charaktere eines Spielers), geschrieben wird an WL.privSel
    local people = WL.People(threads)
    if not WL.privSel and not WL.noAuto and people[1] then WL.privSel = WL.BestChar(people[1], isOnline) end
    local cur = WL.PersonOf(people, WL.privSel)
    local msgs = WL.PersonMsgs(cur)
    -- geoeffnete Unterhaltung gilt als gelesen (alle Charaktere); erste ungelesene merken (Trennlinie)
    local newFrom
    if cur then
        for i, e in ipairs(msgs) do
            if e.new then newFrom = newFrom or i e.new = nil end
        end
        if cur.unread > 0 then WL.ver = (WL.ver or 0) + 1 end
        cur.unread, cur.manual = 0, nil
        for _, th in ipairs(cur.chars) do
            th.unread = 0
            local m = meta(th.name)
            if m and m.unread then m.unread = nil th.manual = nil end
        end
    end
    f.filter:Select(WL.filter or "all")
    local list = buildList(threads)
    f.threads:SetData(list)
    -- Leerzustand links
    local empty = #list == 0
    f.lempty:SetShown(empty)
    if empty then
        f.lempty.text:SetText(WL.query and L["Keine Treffer."]
            or (WL.filter == "star" and L["Noch nichts gemerkt - Rechtsklick auf eine Nachricht: Nachricht merken."])
            or (WL.filter == "pin" and L["Nichts angeheftet - Rechtsklick auf ein Gespraech: Anheften."])
            or (WL.filter == "unread" and L["Alles gelesen."])
            or L["Noch keine Fluesternachrichten."])
    end
    f.selBN = cur and cur.bn
    WL.UpdateHead()
    local can = cur ~= nil and not cur.bn
    f.input:SetShown(can)
    f.send:SetShown(can)
    f.emo:SetShown(can)
    f.snd:SetShown(can)
    f.counter:SetShown(can)
    f.pill:SetShown(can)
    -- Entwurf des Gespraechs zurueckholen (beim Wechsel)
    if f.inputFor ~= WL.privSel then
        f.inputFor = WL.privSel
        f.quote = nil
        f.input.histIdx = nil
        local m = WL.privSel and meta(WL.privSel)
        f.input:SetText((S().wlDrafts ~= false and m and m.draft) or "")
        f.input.ph:SetShown((f.input:GetText() or "") == "")
    end
    f:UpdateQuote()
    -- rechter Leerzustand
    f.rempty:SetShown(cur == nil)
    if cur == nil then
        f.rempty.text:SetText(#threads == 0 and L["Noch keine Fluesternachrichten. Schreib jemandem aus der Gilde!"] or L["Links eine Unterhaltung waehlen."])
    end
    f.lastMsgs = msgs
    -- Verlauf nur neu aufbauen, wenn sich etwas geaendert hat (kein Zucken)
    local jump = WL.jump
    WL.jump = nil
    local sig = tostring(cur and cur.key) .. "|" .. tostring(WL.privSel) .. "|" .. #msgs .. "|" .. tostring(msgs[#msgs] and msgs[#msgs].id) .. "|" .. tostring(WL.ver) .. "|" .. tostring(WL.query)
        .. "|" .. tostring(math.floor(f.sf:GetWidth() or 0))
    if sig ~= f.sig or jump then
        if f.sigSel ~= (cur and cur.key) and K.Tween then
            if not noAnim() then
                f.sf:SetAlpha(0.55)
                K.Tween(f.sf, 0.16, function(p) f.sf:SetAlpha(0.55 + 0.45 * p) end, function() f.sf:SetAlpha(1) end)
            else
                K.Tween(f.sf, 0.01, function() end)
                f.sf:SetAlpha(1)
            end
        end
        local sameThread = f.sigSel == (cur and cur.key) and f.sigN == #msgs
        -- im offenen Gespraech dazugekommen: nur diese weich einblenden
        local animFrom = (f.sigSel == (cur and cur.key) and f.sigN and #msgs > f.sigN and #msgs - f.sigN <= 5) and (f.sigN + 1) or nil
        f.sig, f.sigSel, f.sigN = sig, cur and cur.key, #msgs
        f:SetMessages(msgs, { newFrom = newFrom, jump = jump, keep = sameThread and not jump and not newFrom, animFrom = animFrom,
            multi = cur ~= nil and #cur.chars > 1 })
    end
end

-- Online-Status live nachziehen (nur der Kopf und die Punkte, kein Neuaufbau des Verlaufs)
local function liveStatus()
    if WL.priv and WL.priv:IsShown() then
        WL.UpdateHead()
        if WL.priv.threads then WL.priv.threads:Refresh() end
    end
end
ns.On("FRIENDLIST_UPDATE", liveStatus)
ns.On("GUILD_ROSTER_UPDATE", function() if ns.After then ns.After(0.5, liveStatus) else liveStatus() end end)

------------------------------------------------------------------------
-- Einstellungen (Bereich "Chat"): an den vorhandenen Block anhaengen, nichts ersetzen.
-- Settings.lua legt "chat" an, DiscordBridge haengt seine Schalter ueber DB.BuildSettings an ->
-- wir haengen uns hinter DB.BuildSettings (wird bei jedem Aufbau frisch nachgeschlagen).
------------------------------------------------------------------------
function WL.BuildSettings(det, y)
    if not K or not K.Toggle then return y end
    y = y - 10
    local h = K.Text(det, 12, C.amber)
    h:SetPoint("TOPLEFT", 14, y)
    h:SetText(L["Privatnachrichten"])
    y = y - 26
    local function tg(label, key, def, desc)
        local t = K.Toggle(det, L[label], function() local v = S()[key] if v == nil then return def end return v and true or false end,
            function(v) S()[key] = v and true or false end, desc and L[desc] or nil)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        if det.t then det.t[#det.t + 1] = t end
        y = y - (desc and 40 or 30)
        return t
    end
    tg("Entwuerfe je Gespraech merken", "wlDrafts", true, "Angefangener Text bleibt beim Wechsel des Gespraechs stehen")
    local lbl = K.Text(det, 11, C.muted)
    lbl:SetPoint("TOPLEFT", 14, y - 2)
    lbl:SetText(L["Gespeicherte Fluesternachrichten"])
    if K.Slider then
        local sl = K.Slider(det, 180, 150, 1000, 50, function() return maxKeep() end, function(v) S().wlKeep = v end,
            function(v) return tostring(v) end)
        sl:SetPoint("TOPLEFT", 184, y)
        if det.t then det.t[#det.t + 1] = sl end
    end
    return y - 34
end
do
    local DB = ns.DiscordBridge
    if DB and type(DB.BuildSettings) == "function" and not DB.wlHooked then
        DB.wlHooked = true
        local orig = DB.BuildSettings
        DB.BuildSettings = function(det, y)
            local ok, ny = pcall(orig, det, y)
            if not ok or type(ny) ~= "number" then ny = y end
            local ok2, r = pcall(WL.BuildSettings, det, ny)
            return (ok2 and type(r) == "number") and r or ny
        end
    end
end
end)

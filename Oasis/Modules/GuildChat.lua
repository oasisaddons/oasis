-- Oasis: Gildenchat als eigene Seite
-- Verlauf mit Emojis, Item-Links, Uhrzeit und Tagestrennern; Filter (Erwaehnungen, Links, Offiziere) + Suche;
-- direkt schreiben (mit Emoji-Auswahl); verpasste Nachrichten holt Oasis beim Einloggen von einem anderen
-- Oasis-Nutzer, der online war. Gespeichert wird nur bei dir (30 Tage, hoechstens 3000 Nachrichten).
local ADDON, ns = ...
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
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
                local okKind = type(links) == "table" and links[kind] or (kind == "item" or kind == "spell")
                if #keep < 8 and okKind and data:match("^[%w:%-]+$")
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

local GC = {}
ns.GuildChat = GC

local KEEP_DAYS, KEEP_MAX = 30, 3000
local function S() return ns.db.settings end
local function log()
    ns.db.gchat = ns.db.gchat or {}
    return ns.db.gchat
end

------------------------------------------------------------------------
-- Aufzeichnen
------------------------------------------------------------------------
local unread, mentioned = 0, false
local function myFirst() return ns.displayName(ns.me()) end
local function mentionsMe(text)
    local n = myFirst()
    return n and #n >= 3 and text:lower():find(n:lower(), 1, true) ~= nil
end
-- Text saeubern: unsichtbare Zeichen (Null-Breite, BOM, Steuerzeichen) raus, geschuetztes Leerzeichen -> normal.
-- Der Community-Verlauf liefert solche Zeichen mit; sie verhindern Emoji-Erkennung und Doppelt-Pruefung.
local function clean(m)
    if type(m) ~= "string" then return m end
    m = m:gsub("\226\128[\139-\143]", ""):gsub("\226\129\160", ""):gsub("\239\187\191", "")
    m = m:gsub("\194\160", " "):gsub("[%z\1-\8\11\12\14-\31]", "")
    return (m:gsub("^%s+", ""):gsub("%s+$", ""))
end
GC.Clean = clean
-- Platzhalter, die WoW fuer noch nicht geladene Nachrichten liefert ("Unbekannt"/"Unknown")
local function placeholder(m)
    m = (m or ""):lower()
    return m == "" or m == "unbekannt" or m == "unknown" or (UNKNOWN and m == UNKNOWN:lower())
        or (UNKNOWNOBJECT and m == UNKNOWNOBJECT:lower())
end
-- Vergleichsform: nur Buchstaben/Ziffern, klein, Emoji-Bilder zurueck in Codes
local function norm(m)
    m = clean(m or "")
    if ns.Emoji and ns.Emoji.Unrender then m = ns.Emoji.Unrender(m) end
    -- Farben: klassisch |cffRRGGBB und neu |cnIQ3: (Item-Qualitaet)
    m = m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return (m:lower():gsub("[%s%p]", ""))
end
-- Absender vergleichen ueber den Vornamen: der Community-Verlauf liefert "Jonas", die Gildenliste
-- (WoW Forever) "Jonas Wald" - beides dieselbe Person
local function who(n) return ns.NameKey(n) end
local function same(x, e)
    if who(x.s) ~= who(e.s) then return false end
    if x.m == e.m then return true end
    return norm(x.m) == norm(e.m)
end

local function isK(m) return type(m) == "string" and m:find("|K", 1, true) ~= nil end
GC.IsProtected = isK
-- Sitzungskennung: geschuetzte Texte (|K) loest WoW nur in der Sitzung auf, in der sie live ankamen
GC.sess = tostring(time and time() or 0) .. "-" .. tostring(math.random(100000))
local function isDup(e)
    local l = log()
    -- Eintraege aus dem Community-Verlauf: ueber die Server-ID, und nicht, wenn es die Nachricht schon live gibt
    if e.cid or isK(e.m) then
        local w = ns.NameKey(e.s)
        for i = #l, 1, -1 do
            local x = l[i]
            if e.cid and x.cid == e.cid then return true end
            -- gleicher Absender + gleicher Text innerhalb 5 min: Server- und eigene Uhr weichen oft ab
            if not isK(e.m) and not isK(x.m) and math.abs((x.ts or 0) - (e.ts or 0)) < 300 and same(x, e) then return true end
            -- geschuetzte Kopie: Text nicht vergleichbar -> gleicher Absender, Server-Zeit weicht bis ~1 min ab
            if math.abs((x.ts or 0) - (e.ts or 0)) <= (isK(e.m) and not isK(x.m) and 60 or 3) and ns.NameKey(x.s) == w then return true end
            if (x.ts or 0) < (e.ts or 0) - 86400 then break end
        end
        return false
    end
    -- live empfangen (0.5.512): nur dasselbe Ereignis zweimal ist doppelt (< 2 s) - wer zweimal dasselbe
    -- schreibt (z.B. ein Emoji), soll es auch zweimal sehen (vorher 5 Min lang verschluckt)
    if e.src == "live" then
        local l2 = log()
        for i = #l2, math.max(1, #l2 - 60), -1 do
            local x = l2[i]
            if x.src == "live" and math.abs((x.ts or 0) - (e.ts or 0)) < 2 and same(x, e) then return true end
        end
        return false
    end
    -- gleiche Nachricht vom selben Absender innerhalb von 5 Minuten = doppelt (z.B. aus dem Nachladen)
    local l = log()
    for i = #l, math.max(1, #l - 200), -1 do
        local x = l[i]
        if math.abs((x.ts or 0) - e.ts) < 300 and same(x, e) then return true end
    end
    return false
end
local function prune()
    local l, cut = log(), ns.now() - KEEP_DAYS * 86400
    local first = 1
    while l[first] and ((l[first].ts or 0) < cut or #l - first + 1 > KEEP_MAX) do first = first + 1 end
    if first > 1 then
        local n = {}
        for i = first, #l do n[#n + 1] = l[i] end
        ns.db.gchat = n
    end
end
local function rememberLinks(e)
    if type(e.m) ~= "string" or isK(e.m) or e.k == "off" then return end
    ns.db.linkHist = ns.db.linkHist or {}
    local h = ns.db.linkHist
    for raw in e.m:gmatch("|Hitem:[^|]+|h%[[^%]]+%]|h") do
        local id = ns.itemID(raw)
        if id then
            for i = #h, 1, -1 do if h[i].id == id then table.remove(h, i) end end
            table.insert(h, 1, { id = id, raw = raw, who = e.s, ts = e.ts or ns.now() })
            -- mit der Gilde teilen: wer offline war, bekommt die Links beim naechsten Abgleich.
            -- Nur live gesehene, kurz zufaellig warten und nur senden, wenn es noch keiner getan hat
            if not GC.bulk and (ns.now() - (e.ts or 0)) < 120 and ns.Store then
                local sid = "l" .. id
                ns.After(math.random() * 6, function()
                    local old = ns.Store.Get("links", sid)
                    if old and not old.del and math.abs((old.ts or 0) - (e.ts or 0)) < 600 then return end
                    ns.Store.Put("links", { id = sid, raw = raw, who = e.s, ts = e.ts or ns.now() })
                end)
            end
        end
    end
    while #h > 30 do table.remove(h) end
end
GC.RememberLinks = rememberLinks
-- Eigene Nachricht? (0.5.969) Der Name allein reicht nicht immer: WoW Forever liefert den Absender im Gildenchat teils nur
-- mit Vornamen ("Tomas-Realm"), waehrend der eigene Name als "Tomas Berg-Realm" bekannt ist - dann zaehlte die eigene
-- Nachricht als ungelesen. Sicher ist die GUID (e.me, vom Chat-Ereignis); sonst Vorname + Realm, wenn der Vorname
-- in der Gilde nur einmal vorkommt.
local function firstAndRealm(n)
    n = type(n) == "string" and n or ""
    local base, realm = n:match("^(.*)%-([^%-]+)$")
    base = (base or n):lower()
    return base:match("^(%S+)") or base, (realm or ""):lower()
end
local function isMine(e)
    if e.me or ns.isMe(e.s) then return true end
    local me = ns.me and ns.me()
    if not me or type(e.s) ~= "string" then return false end
    local f1, r1 = firstAndRealm(e.s)
    local f2, r2 = firstAndRealm(me)
    if f1 == "" or f1 ~= f2 or (r1 ~= "" and r2 ~= "" and r1 ~= r2) then return false end
    local n = 0
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        if firstAndRealm(m.name) == f1 then n = n + 1 end
    end
    return n <= 1
end
GC.IsMine = isMine
function GC.Add(e, silent)
    local mine = isMine(e)
    e.me = nil   -- nur fuer diese Pruefung: nicht speichern, nicht an andere weitergeben
    e.m = clean(e.m)
    -- geschuetzte Texte nur aus dem Community-Verlauf (mit ID) - nie von anderen Oasis-Nutzern
    if isK(e.m) and not e.cid then return false end
    if not e.m or placeholder(e.m) or isDup(e) then return false end
    -- kommt die Nachricht live, eine schon vorhandene geschuetzte Kopie (gleicher Absender, +-3 s) ersetzen
    if not isK(e.m) then
        local l, w = log(), ns.NameKey(e.s)
        for i = #l, math.max(1, #l - 60), -1 do
            local x = l[i]
            if isK(x.m) and math.abs((x.ts or 0) - (e.ts or 0)) <= 60 and ns.NameKey(x.s) == w then
                table.remove(l, i)
                break
            end
        end
    end
    pcall(rememberLinks, e)
    local l = log()
    -- nach Zeit einsortieren (nachgeladene Nachrichten koennen aelter sein)
    local pos = #l + 1
    while pos > 1 and (l[pos - 1].ts or 0) > e.ts do pos = pos - 1 end
    table.insert(l, pos, e)
    if #l > KEEP_MAX + 200 then prune() end
    if not silent and e.src == "live" and ns.Sound and ns.Sound.OnChatSound then pcall(ns.Sound.OnChatSound, e.s, e.m) end
    if not silent and not mine and e.k ~= "sys" and e.src == "live" and S().chatMentionSound ~= false
        and mentionsMe(e.m) and ns.Sound and ns.Sound.PlayChoice and not (S().soundQuietCombat and ns.inCombat()) then
        pcall(ns.Sound.PlayChoice, "ping", S().soundVol)
    end
    if not silent and not mine and e.k ~= "sys" then
        if ns.CurrentPage and ns.CurrentPage() == "chat" and ns.MainShown and ns.MainShown() then
            unread = 0
        else
            unread = unread + 1
            if mentionsMe(e.m) then mentioned = true end
        end
        ns.SetNavBadge("chat", unread > 0 and ((mentioned and "@" or "") .. (unread > 99 and "99+" or unread)) or nil)
    end
    if not GC.bulk and not (GC.Live and pos == #l and GC.Live(e)) then ns.RefreshPage("chat") end
    return true
end

local function classOf(sender)
    return ns.Radar and ns.Radar.ClassOf(sender) or nil
end
-- 12. Wert des Chat-Ereignisses = GUID des Absenders: daran erkennt man die eigene Nachricht sicher
local function ownGuid(...)
    local guid = ns.safe((select(10, ...)))
    local mine = UnitGUID and ns.safe(UnitGUID("player"))
    return (type(guid) == "string" and guid ~= "" and guid == mine) or nil
end
ns.On("CHAT_MSG_GUILD", function(msg, sender, ...)
    msg, sender = ns.safe(msg), ns.safe(sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    GC.Add({ ts = ns.now(), s = ns.fullName(sender), m = msg, c = classOf(sender), src = "live", sess = isK(msg) and GC.sess or nil, me = ownGuid(...) })
end)
ns.On("CHAT_MSG_OFFICER", function(msg, sender, ...)
    msg, sender = ns.safe(msg), ns.safe(sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    GC.Add({ ts = ns.now(), s = ns.fullName(sender), m = msg, c = classOf(sender), k = "off", src = "live", me = ownGuid(...) })
end)
ns.On("CHAT_MSG_GUILD_ACHIEVEMENT", function(msg, sender)
    msg, sender = ns.safe(msg), ns.safe(sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    GC.Add({ ts = ns.now(), s = ns.fullName(sender), m = msg:gsub("%%s", ns.short(sender)), c = classOf(sender), k = "ach" }, true)
end)

------------------------------------------------------------------------
-- Verlauf aus den WoW-Chatfenstern uebernehmen: was dort schon steht (vor dem Einloggen von Oasis,
-- nach /reload wiederhergestellt ...), kommt einmalig mit in den Oasis-Verlauf.
------------------------------------------------------------------------
local KIND_OF = { CHAT_MSG_GUILD = "", CHAT_MSG_OFFICER = "off", CHAT_MSG_GUILD_ACHIEVEMENT = "ach" }
local TYPE_OF = { GUILD = "", OFFICER = "off", GUILD_ACHIEVEMENT = "ach" }

-- Chat-Art einer Zeile: Event-Name > Chat-Typ-ID > Farbe
local function kindOf(entry)
    local x = entry.extraData
    if type(x) == "table" then
        for i = 1, (x.n or #x) do
            local v = x[i]
            if type(v) == "string" and KIND_OF[v] then return KIND_OF[v], x end
            if type(v) == "string" and v:find("^CHAT_MSG_") then return nil end
        end
        local id = x[1]
        if type(id) == "number" and ChatTypeInfo then
            for t, k in pairs(TYPE_OF) do
                if ChatTypeInfo[t] and ChatTypeInfo[t].id == id then return k, x end
            end
        end
    end
    if ChatTypeInfo and entry.r then
        for t, k in pairs(TYPE_OF) do
            local c = ChatTypeInfo[t]
            if c and c.r and math.abs(c.r - entry.r) < 0.01 and math.abs(c.g - entry.g) < 0.01 and math.abs(c.b - entry.b) < 0.01 then
                return k, x
            end
        end
    end
end

-- Absender + Text: aus den Original-Event-Daten, sonst aus der fertigen Chatzeile
local function parseLine(entry, extra)
    if type(extra) == "table" then
        for i = 1, (extra.n or #extra) do
            local a = extra[i]
            if type(a) == "table" and type(a[1]) == "string" and type(a[2]) == "string" then
                local m, s = ns.safe(a[1]), ns.safe(a[2])
                if m and s and s ~= "" then return s, m end
            end
        end
    end
    local text = ns.safe(entry.message)
    if type(text) ~= "string" then return end
    local s, m = text:match("|Hplayer:([^:|]+)[^|]*|h.-|h:%s(.*)$")
    return s, m
end

-- sichtbarer Zeitstempel der Chatzeile ("[21:14]" o.ae.) -> Serverzeit heute/gestern
local function visibleTs(text)
    local h, mi = (text or ""):match("^[^%d]-(%d%d?):(%d%d)")
    h, mi = tonumber(h), tonumber(mi)
    if not h or h > 23 or mi > 59 then return nil end
    local now = ns.now()
    local t = date("*t", now)
    t.hour, t.min, t.sec = h, mi, 0
    local ts = time(t)
    if ts > now + 60 then ts = ts - 86400 end
    return ts
end

-- schon im Verlauf? (sicher: gleiche Zeit; unsicher: gleicher Text in den letzten 24 Std)
local function known(s, m, ts, loose)
    local l, short = log(), ns.short(s)
    for i = #l, 1, -1 do
        local x = l[i]
        if (x.ts or 0) < ts - 86400 then break end
        if (loose or math.abs((x.ts or 0) - ts) < 300) and same(x, { s = s, m = m }) then return true end
    end
    return false
end

function GC.ImportChatFrames()
    if not ns.db then return 0 end
    local nowGT, now = GetTime(), ns.now()
    local found = {}
    for f = 1, (NUM_CHAT_WINDOWS or 10) do
        local hb = _G["ChatFrame" .. f] and _G["ChatFrame" .. f].historyBuffer
        if hb and hb.GetNumElements and hb.GetEntryAtIndex then
            -- Index 1 = neueste Zeile; von alt nach neu durchgehen
            local stamps, first = {}, #found + 1
            for i = hb:GetNumElements(), 1, -1 do
                local entry = hb:GetEntryAtIndex(i)
                if type(entry) == "table" then
                    local kind, extra = kindOf(entry)
                    if kind and kind ~= "ach" then
                        local s, m = parseLine(entry, extra)
                        if s and m and m ~= "" then
                            local t = tonumber(entry.timestamp)
                            found[#found + 1] = { f = f, s = ns.fullName(s), m = m, k = (kind ~= "" and kind) or nil,
                                gt = (t and t <= nowGT) and t or nil, vis = visibleTs(ns.safe(entry.message)) }
                            if t then stamps[t] = (stamps[t] or 0) + 1 end
                        end
                    end
                end
            end
            -- nach /reload wiederhergestellte Zeilen tragen alle denselben Zeitpunkt -> Zeit unsicher
            for i = first, #found do
                local e = found[i]
                if e.gt and (stamps[e.gt] or 0) > 3 then e.gt = nil end
            end
        end
    end
    GC.bulk = true
    local n, prevTs, prevF = 0, 0, nil
    for _, e in ipairs(found) do
        if e.f ~= prevF then prevTs, prevF = 0, e.f end
        local loose = e.gt == nil
        local ts = e.gt and math.floor(now - (nowGT - e.gt)) or e.vis or now
        if ts < prevTs then ts = prevTs end    -- Reihenfolge der Chatzeilen beibehalten
        prevTs = ts
        if ns.Emoji and ns.Emoji.Unrender then e.m = ns.Emoji.Unrender(e.m) end
        if not known(e.s, e.m, ts, loose) then
            if GC.Add({ ts = ts, s = e.s, m = e.m, c = classOf(e.s), k = e.k }, true) then n = n + 1 end
        end
    end
    GC.bulk = nil
    if n > 0 then ns.RefreshPage("chat") end
    ns.debug("Chatverlauf uebernommen:", n)
    return n
end
------------------------------------------------------------------------
-- Gildenverlauf aus WoWs Community-Schnittstelle (C_Club) holen: das ist der Verlauf, den das
-- Fenster "Gilde & Communitys" zeigt - serverseitig gespeichert, mit echter Uhrzeit.
------------------------------------------------------------------------
local function classFileOf(classID)
    if classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, classID)
        if ok and info then return info.classFile end
    end
end
local function guildStreams()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams) then return nil end
    local ok, clubId = pcall(C_Club.GetGuildClubId)
    clubId = ok and ns.safe(clubId) or nil
    if not clubId then return nil end
    local ok2, streams = pcall(C_Club.GetStreams, clubId)
    if not ok2 or type(streams) ~= "table" then return clubId, {} end
    local T = Enum and Enum.ClubStreamType or {}
    local out = {}
    for _, st in ipairs(streams) do
        local t = st.streamType
        if t == T.Guild then out[#out + 1] = { id = st.streamId, kind = nil }
        elseif t == T.Officer then out[#out + 1] = { id = st.streamId, kind = "off" } end
    end
    return clubId, out
end
-- Discord-Kennzeichen suchen: Felder der Nachricht / des Autors, die "discord" o.ae. enthalten
local function flat(t, out, prefix, depth)
    out = out or {}
    if depth and depth > 2 then return out end
    for k, v in pairs(t) do
        local key = (prefix or "") .. tostring(k)
        local tv = type(v)
        if tv == "table" then flat(v, out, key .. ".", (depth or 0) + 1)
        elseif tv ~= "function" and tv ~= "userdata" then
            local sv = ns.safe(v)
            if sv ~= nil then out[key] = tostring(sv):sub(1, 60) end
        end
    end
    return out
end
local function fromDiscord(m)
    -- WoW liefert ein eindeutiges Feld: author.discordInfo.fromDiscord (bzw. isRemoteChat)
    local a = m.author or {}
    local d = a.discordInfo
    if type(d) == "table" and ns.safe(d.fromDiscord) == true then return true end
    if ns.safe(a.isRemoteChat) == true then return true end
    return false
end
-- einige Nachrichten roh speichern, damit wir das Kennzeichen genau bestimmen koennen (nur die ersten 12)
-- (Mitschnitt zur Fehlersuche abgeschaltet 0.5.482 - Kennzeichen ist bestimmt; alte Daten weg)
local function sample(m)
    if ns.db.clubSample then ns.db.clubSample = nil end
end

function GC.ImportClub()
    if not ns.db then return 0 end
    local clubId, streams = guildStreams()
    if not clubId then return 0 end
    local n = 0
    GC.bulk = true
    for _, st in ipairs(streams) do
        local ok, ranges = pcall(C_Club.GetMessageRanges, clubId, st.id)
        if ok and type(ranges) == "table" then
            for _, r in ipairs(ranges) do
                local ok2, msgs = pcall(C_Club.GetMessagesInRange, clubId, st.id, r.oldestMessageId, r.newestMessageId)
                if ok2 and type(msgs) == "table" then
                    for _, m in ipairs(msgs) do
                        local text = ns.safe(m.content)
                        local a = m.author or {}
                        local who = ns.safe(a.name)
                        local epoch = m.messageId and tonumber(ns.safe(m.messageId.epoch))
                        pcall(sample, m)
                        if not m.destroyed and text and text ~= "" and who and who ~= "" and epoch then
                            local ts = math.floor(epoch / 1000000)
                            local full = ns.fullName(who)
                            local alias = ns.Radar and ns.Radar.AliasOf and ns.Radar.AliasOf(full)
                            if alias and alias:find(" ", 1, true) then full = alias end
                            if ns.Emoji and ns.Emoji.Unrender then text = ns.Emoji.Unrender(text) end
                            local cid = tostring(epoch) .. "-" .. tostring(ns.safe(m.messageId.position) or 0)
                            if isK(text) or not known(full, text, ts, false) then
                                local okd, isDc = pcall(fromDiscord, m)
                                local dc = okd and isDc or nil
                                if GC.Add({ ts = ts, s = full, m = text, c = classFileOf(a.classID) or classOf(full), k = st.kind, src = "club", cid = cid, dc = dc or nil }, true) then n = n + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    GC.bulk = nil
    if n > 0 then ns.RefreshPage("chat") end
    ns.debug("Gildenverlauf (Community) uebernommen:", n)
    return n
end
-- aeltere Nachrichten beim Server anfragen; sie kommen per CLUB_MESSAGE_HISTORY_RECEIVED
function GC.RequestClubHistory()
    local clubId, streams = guildStreams()
    if not clubId then return end
    for _, st in ipairs(streams) do
        if C_Club.RequestMoreMessagesBefore then pcall(C_Club.RequestMoreMessagesBefore, clubId, st.id, nil, 100) end
    end
end
-- geschuetzte Platzhalter nie speichern (nach /reload waeren sie "Unbekannt")
ns.On("PLAYER_LOGOUT", function()
    local l = ns.db and ns.db.gchat
    if not l then return end
    local out = {}
    for _, e in ipairs(l) do if not isK(e.m) then out[#out + 1] = e end end
    ns.db.gchat = out
end)
local function redraw()
    GC.ClearRenderCache()
    if GC.page and GC.page:IsVisible() then ns.RefreshPage("chat") end
    if GC.page and GC.page.loader then GC.page.loader:Hide() end
end
ns.On("CLUB_MESSAGE_HISTORY_RECEIVED", function()
    ns.After(0.5, GC.ImportClub)
    ns.After(1.5, redraw)
end)
-- auch beim Oeffnen der Seite und kurz danach neu zeichnen (Texte, die inzwischen aufgeloest sind)
ns.Listen("LOGIN", function()
    ns.After(15, redraw)
    ns.After(40, redraw)
end)
-- neue Community-Nachricht (z.B. aus Discord ueber die Gilden-Verknuepfung - die kommt nicht als Gildenchat-Ereignis)
local clubPending
ns.On("CLUB_MESSAGE_ADDED", function(clubId)
    if clubPending then return end
    clubPending = true
    -- kurz warten: normale Gildenchat-Nachrichten kommen zusaetzlich live und sollen Vorrang haben
    ns.After(1.5, function() clubPending = nil GC.ImportClub() end)
end)
ns.Listen("LOGIN", function()
    ns.After(5, function()
        GC.RequestClubHistory()
        GC.ImportClub()
    end)
end)

ns.slash.chatimport = function()
    GC.RequestClubHistory()
    local n = GC.ImportClub()
    ns.print((L["Aus dem WoW-Chat uebernommen: %d Nachrichten"]):format(n))
end

------------------------------------------------------------------------
-- Verpasste Nachrichten von anderen Oasis-Nutzern nachladen
-- Ich frage mit meinem letzten Zeitstempel; einer mit neueren Nachrichten meldet sich ("habe ich")
-- und schickt bis zu 80 Nachrichten per Fluestern. Offiziers-Chat wird nie geteilt.
------------------------------------------------------------------------
local answered = {}
local function lastPublicTs()
    local l = log()
    for i = #l, 1, -1 do if l[i].k ~= "off" and l[i].k ~= "sys" and l[i].src ~= "discord" and l[i].src ~= "snd" then return l[i].ts or 0 end end
    return 0
end
ns.GuildOption({ page = "chat", key = "chSync", default = true, label = "Verpasste Nachrichten teilen",
    desc = "Oasis-Nutzer schicken sich beim Einloggen verpasste Gildenchat-Nachrichten zu (nie den Offizierschat)" })
ns.GuildOption({ page = "chat", key = "chPin", default = "note", lead = true, label = "Anpinnen duerfen",
    desc = "Wer eine Nachricht oben im Gildenchat anpinnen darf",
    choices = { { key = "note", text = "Offiziersnotiz-Recht" }, { key = "lead", text = "Nur Gildenleitung" } } })
ns.GuildOption({ page = "chat", key = "chPinD", default = 14, min = 1, max = 60, step = 1, label = "Angepinnt bleibt",
    desc = "So lange wird eine angepinnte Nachricht oben im Gildenchat gezeigt",
    fmt = function(v) return (ns.L["%d Tg"]):format(v) end })
-- wann war ich zuletzt online (jede Minute gemerkt): Nachladen ab dort, nicht ab der neuesten Nachricht -
-- die WoW-Chathistorie beim Einloggen liefert oft nur die letzten Zeilen, dazwischen bliebe sonst eine Luecke
C_Timer.NewTicker(60, function() if ns.db then ns.db.chatOnlineAt = ns.now() end end)
function GC.RequestMissed(hours)
    if not IsInGuild() or ns.GuildOpt("chSync") == false then return end
    local since = lastPublicTs()
    -- immer mindestens die letzten 24 Std anfragen (doppelte Nachrichten werden verworfen): eigene neue Zeilen,
    -- Sounds oder ein anderer PC liessen sonst Luecken entstehen
    since = math.min(since, ns.now() - (tonumber(hours) or 24) * 3600)
    local seen = ns.db.chatSeenBefore
    if seen and seen > 0 and seen < since then since = seen - 120 end
    -- noch kein Online-Zeitpunkt bekannt (erster Start nach dem Update): mindestens 12 Std zurueck fragen
    if not seen then since = math.min(since, ns.now() - 12 * 3600) end
    if since == 0 then since = ns.now() - 2 * 86400 end
    GC.reqAt, GC.reqSince, GC.reqGot = GetTime(), since, {}
    Comm.Guild("GCREQ", tostring(since))
end
Comm.On("GCREQ", function(sender, _, since)
    since = tonumber(since)
    if not since or ns.isMe(sender) or ns.GuildOpt("chSync") == false then return end
    -- je Anfragendem hoechstens alle 2 Minuten (sonst laesst sich eine Fluester-Flut ausloesen)
    if not SEC.Rate("gcreq:" .. sender, 120) then return end
    -- nur Gildenmitgliedern den Verlauf schicken
    if ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(sender) == false then return end
    local key = ns.short(sender) .. since
    local l, out = log(), {}
    for i = #l, 1, -1 do
        local e = l[i]
        if (e.ts or 0) <= since + 1 then break end
        -- Discord-Nachrichten aus OasisSync (DiscordBridge.lua) nur anzeigen, nie weiterverteilen
        if e.k ~= "off" and e.k ~= "sys" and not isK(e.m) and e.src ~= "discord" then table.insert(out, 1, e) end
    end
    if #out == 0 then return end
    -- wer mehr hat, meldet sich schneller
    ns.After(math.max(0.1, 0.5 + math.random() * 2.5 - math.min(#out, 50) / 50), function()   -- 0.5.660: nie negativ
        if answered[key] then return end
        answered[key] = true
        Comm.Guild("GCCLAIM", key)
        -- bis zu 300 Nachrichten (vorher 80: bei viel Betrieb fehlte dann der Vormittag/Mittag)
        for i = math.max(1, #out - 299), #out do
            local e = out[i]
            Comm.Whisper(sender, "GCMSG", tostring(e.ts), e.s, e.m, e.k or "")
        end
    end)
end)
Comm.On("GCCLAIM", function(_, _, key) if key then answered[key] = true end end)
-- nachgereichte Nachrichten: nur kurz nach der eigenen Anfrage, je Absender begrenzt, nur Gildenmitglieder
-- als Verfasser, Zeit im angefragten Fenster, Text ohne Escape-Sequenzen (nur Item-/Zauber-/Erfolgs-Links)
local SYNC_LINKS = { item = true, spell = true, enchant = true, quest = true, achievement = true }
Comm.On("GCMSG", function(sender, _, ts, who, msg, kind)
    ts = tonumber(ts)
    if not ts or not who or not msg or kind == "off" then return end
    if not GC.reqAt or GetTime() - GC.reqAt > 400 then return end   -- 300 Nachrichten brauchen gedrosselt ein paar Minuten
    if kind ~= "" and kind ~= "ach" then return end
    if ts ~= ts or ts <= (GC.reqSince or 0) or ts > ns.now() + 120 then return end
    who = SEC.Name(who)
    if not who then return end
    local inGuild = ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(who)
    if inGuild == false then return end
    local got = GC.reqGot or {}
    GC.reqGot = got
    got[sender] = (got[sender] or 0) + 1
    if got[sender] > 320 then return end
    msg = SEC.Text(msg, 400, SYNC_LINKS)
    if msg == "" then return end
    GC.Add({ ts = ts, s = who, m = msg, c = classOf(who), k = (kind ~= "" and kind) or nil, late = true, src = "sync:" .. ns.short(sender) }, true)
end)
local function cleanLog()
    local l = log()
    local out = {}
    for _, e in ipairs(l) do
        e.m = clean(e.m)
        local dup = false
        for i = #out, math.max(1, #out - 60), -1 do
            local x = out[i]
            local bothLive = x.src == "live" and e.src == "live" and math.abs((x.ts or 0) - (e.ts or 0)) >= 2
            if not bothLive and math.abs((x.ts or 0) - (e.ts or 0)) < 300 and same(x, e) then
                -- die Oasis-eigene Zeile behalten (hat Klassenfarbe/Art), sonst die erste
                dup = true
                break
            end
        end
        if isK(e.m) then
            -- geschuetzte Platzhalter gelten nur fuer eine Sitzung (danach "Unbekannt") -> beim Einloggen
            -- immer verwerfen; der Community-Verlauf wird kurz danach frisch geholt
            dup = true
            for i = #out, math.max(1, #out - 60), -1 do
                local x = out[i]
                if (e.cid and x.cid == e.cid) or (math.abs((x.ts or 0) - (e.ts or 0)) <= 3
                    and ns.NameKey(x.s) == ns.NameKey(e.s)) then
                    dup = true break
                end
            end
        end
        if not dup and not placeholder(e.m) then out[#out + 1] = e end
    end
    if #out ~= #l then ns.db.gchat = out end
    if not ns.db.linkHistInit then
        ns.db.linkHistInit = true
        for _, e in ipairs(out) do pcall(rememberLinks, e) end
    end
    return #l - #out
end
GC.CleanLog = cleanLog

ns.Listen("LOGIN", function()
    prune()
    pcall(cleanLog)
    ns.db.chatSeenBefore = ns.db.chatOnlineAt   -- Zeitpunkt vor diesem Login
    ns.db.chatOnlineAt = ns.now()
    ns.After(25, GC.RequestMissed)
end)

------------------------------------------------------------------------
-- Anzeige
------------------------------------------------------------------------
local filter, search = "all", ""
local dayFilter   -- "JJJJMMTT" = nur dieser Tag
local DAYNAME
local function dayLabel(ts)
    local d = date("%Y%m%d", ts)
    if d == date("%Y%m%d") then return L["Heute"] end
    if d == date("%Y%m%d", ns.now() - 86400) then return L["Gestern"] end
    return date(L["%d.%m."], ts)
end
------------------------------------------------------------------------
-- Extras: Reaktionen, Antworten/Zitieren, Pin, Stummschalten, Helfer-Knopf
------------------------------------------------------------------------
-- Schluessel einer Nachricht (bei allen Oasis-Nutzern gleich): Vorname + Tag + Text-Hash
local mkCache = setmetatable({}, { __mode = "k" })
local function msgKey(e)
    local k = mkCache[e]
    if not k then
        k = who(e.s) .. ":" .. date("%y%m%d", e.ts) .. ":" .. tostring(ns.hash(norm(e.m)))
        mkCache[e] = k
    end
    return k
end
-- Zeilen-Links: Nummer -> Eintrag (nur im Speicher)
local byLid, lidOf, lidN = {}, setmetatable({}, { __mode = "k" }), 0
local function lid(e)
    local n = lidOf[e]
    if not n then
        lidN = lidN + 1
        n = lidN
        lidOf[e] = n
        byLid[n] = e
    end
    return n
end
GC.REACTS = { ":+1:", ":lol:", "<3", ":fire:", ":tada:", ":eyes:" }
local reactIdx, reactVer = nil, 0
local function reactIndex()
    if reactIdx then return reactIdx end
    reactIdx = {}
    local okEm = {}
    for _, x in ipairs(GC.REACTS) do okEm[x] = true end
    for _, r in pairs(ns.Store.coll("reacts")) do
        -- nur bekannte Reaktionen, und nur die eigene (id = Nachricht#Absender) - niemand reagiert im Namen anderer
        if not r.del and r.mk and r.em and okEm[r.em] and r.by and r.id == tostring(r.mk) .. "#" .. r.by then
            local t = reactIdx[r.mk] or { order = {}, n = {}, who = {} }
            reactIdx[r.mk] = t
            if not t.n[r.em] then t.n[r.em] = 0 t.order[#t.order + 1] = r.em t.who[r.em] = {} end
            t.n[r.em] = t.n[r.em] + 1
            table.insert(t.who[r.em], ns.displayName(r.by or "?"))
        end
    end
    return reactIdx
end
local function emo(code)
    if ns.Emoji and ns.Emoji.Render then
        local ok, r = pcall(ns.Emoji.Render, code)
        if ok and r then return r end
    end
    return code
end
local function reactLine(e)
    local t = reactIndex()[msgKey(e)]
    if not t then return "" end
    local out = {}
    for _, em in ipairs(t.order) do out[#out + 1] = emo(em) .. "|cff999999" .. t.n[em] .. "|r" end
    return "   " .. table.concat(out, "  ")
end
function GC.ToggleReact(e, em)
    local id = msgKey(e) .. "#" .. ns.me()
    local old = ns.Store.Get("reacts", id)
    if old and not old.del and old.em == em then
        ns.Store.Delete("reacts", id)
    else
        ns.Store.Put("reacts", { id = id, mk = msgKey(e), em = em })
    end
end
local function muted(name)
    local m = S().chatMuted
    return m and m[who(name)]
end
-- Fragen erkennen ("haben wir nen ingi?", "suche Gruppe ...")
local PROFKEY = { { "ingi", "ingen" }, { "ingenieur", "ingen" }, { "schmied", "schmied" }, { "alchi", "alchi" },
    { "verzauber", "verzaub" }, { "vz", "verzaub" }, { "enchant", "verzaub" }, { "schneider", "schneid" }, { "lederer", "leder" },
    { "kürschner", "kürsch" }, { "koch", "koch" }, { "bergbau", "bergbau" }, { "kräuter", "kräuter" }, { "angler", "angel" } }
local function askOf(e)
    if ns.isMe(e.s) or e.k == "ach" or (ns.now() - (e.ts or 0)) > 3 * 3600 then return end
    local t = (e.m or ""):lower()
    local q = t:find("?", 1, true) or t:find("^suche") or t:find("brauch") or t:find("lfg")
    if not q then return end
    for _, pk in ipairs(PROFKEY) do
        if t:find("%f[%w]" .. pk[1]) then return "prof", pk[2] end
    end
    if t:find("lfg") or t:find("suche gruppe") or t:find("wer kommt mit") or t:find("wer ist dabei") then return "group" end
    if t:find("^wer kann") or t:find("kann mir wer") or t:find("kann mir jemand") or t:find("hat jemand") or t:find("^wer hat") then return "ask" end
end
local function profHolders(sub)
    local out = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        local pr = ns.db.members[m.name]
        local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
        for part in tostring(raw or ""):gmatch("[^+]+") do
            local n, r = part:match("^([^/]+)/(%d+)")
            if n and n:lower():find(sub, 1, true) then out[#out + 1] = { m = m, prof = n, r = tonumber(r) or 0 } end
        end
    end
    table.sort(out, function(a, b)
        if a.m.online ~= b.m.online then return a.m.online and true or false end
        return a.r > b.r
    end)
    return out
end
GC.ProfHolders = profHolders
local function plain(text)
    text = (text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return text
end
GC.Plain = plain

local function nameLink(e)
    local short = ns.short(e.s)
    local col = ns.Radar and ns.Radar.Colored(e.s) or short
    -- Belohnung Oasis-Rang: Juwel ab 30, schimmernder Name ab 70
    local fancy = ns.Rewards and ns.Rewards.ChatName(e.s, col)
    if fancy then
        local gem, name = fancy:match("^(|T.-|t )(.*)$")
        return (gem or "") .. ("|Hplayer:%s|h%s|h"):format(ns.ChatName(e.s), name or col)
    end
    -- Farbe ausserhalb des Links + geschuetztes Leerzeichen: sonst ist bei "Vorname Nachname" nur das erste Wort klickbar
    local hex = ns.classHex and ns.classHex(ns.Radar and ns.Radar.ClassOf(e.s)) or "ffffffff"
    local disp = (short:gsub(" ", "\194\160"))
    return ("|c%s|Hplayer:%s|h%s|h|r"):format(hex, ns.ChatName(e.s), disp) 
end
local function highlight(text)
    local n = myFirst()
    if not n or #n < 3 then return text end
    -- eigenen Namen gelb markieren (nicht innerhalb von Links)
    if text:find("|H", 1, true) then return text end
    return (text:gsub("(" .. n:gsub("%p", "%%%0") .. ")", "|cffffd24a%1|r"))
end
local BADGE_ICON = ns.MEDIA .. "icons\\badges"
-- fertige Zeilen merken (nur im Speicher, nicht in der Datei) -> Neuaufbau bei 3000 Nachrichten
-- muss nicht jedes Mal alle Emojis/Links neu umwandeln. Leeren, wenn sich Anzeige-Einstellungen aendern.
local renderCache = setmetatable({}, { __mode = "k" })
local renderKey
function GC.ClearRenderCache() renderCache = setmetatable({}, { __mode = "k" }) end
local renderRaw
------------------------------------------------------------------------
-- Darstellung (persoenlich, ns.db.settings). Standardwerte = ruhiges, gut lesbares Design.
-- chatFont "" = Oasis-Schrift, chatBubbleMine "" = gedaempfte Akzentfarbe
------------------------------------------------------------------------
GC.LOOK_DEF = {
    chatFont = "", chatFontSize = 13, chatSpacing = 5,
    chatTextColor = "e2e2e6", chatTimeColor = "6a6a74",
    chatBgColor = "111215", chatBgAlpha = 90,
    chatBubbleMine = "", chatBubbleOther = "252c33",
    chatShowTime = true, chatGroup = true,
}
function GC.Look(k)
    local v = ns.db and ns.db.settings and ns.db.settings[k]
    if v == nil then return GC.LOOK_DEF[k] end
    return v
end
function GC.LookColor(k)
    local c = K.FromHex(GC.Look(k)) or K.FromHex(GC.LOOK_DEF[k]) or { 1, 1, 1, 1 }
    return c[1], c[2], c[3]
end
function GC.LookFont()
    local key = GC.Look("chatFont")
    if key and key ~= "" and K.fontByKey and K.fontByKey[key] then return K.fontByKey[key].path end
    return K.FONT
end
local function lookHex(k) return "|cff" .. K.ToHex({ GC.LookColor(k) }) end

local function render(e)
    local key = tostring(S().chatEmoji) .. ":" .. tostring(S().emojiChatSize) .. ":" .. (ns.lang or "") .. ":" .. reactVer
        .. ":" .. tostring(GC.Look("chatTimeColor")) .. ":" .. tostring(GC.Look("chatShowTime"))
    if key ~= renderKey then renderKey = key GC.ClearRenderCache() end
    local c = renderCache[e]
    if c then return c end
    c = renderRaw(e)
    renderCache[e] = c
    return c
end
-- liefert { head = Namenszeile, body = Nachrichtenzeile }; ach = Erfolg (eine Zeile, kein Kopf)
renderRaw = function(e)
    local text = e.m
    if S().chatEmoji ~= false and ns.Emoji then text = ns.Emoji.Render(text, e.s) end
    if ns.Sound and ns.Sound.RenderCodes then text = ns.Sound.RenderCodes(text) end
    -- Zeit dezent vorne; ist sie aus, bleibt ein kleiner Punkt als Klickziel fuer das Nachrichtenmenue
    local time = ""   -- Zeit steht in der Liste neben dem Namen (bei Folgebeitraegen beim Ueberfahren)
    if e.k == "ach" then
        -- Erfolg: goldener Pokal vorne
        return { ach = true, body = time .. "|T" .. BADGE_ICON .. ":14:14:0:0:64:64:0:64:0:64:255:210:74|t |cffffd24a" .. text .. "|r" }
    end
    local tag = e.k == "off" and ("|cff66db9e" .. L["Offiziere"] .. "|r  ") or ""
    local late = ""
    local mention = (not ns.isMe(e.s) and mentionsMe(e.m)) and "|cffffd24a@|r " or ""
    local dcIcon = e.dc and ("|T" .. ns.ICONS.chat .. ":13:13:0:0:64:64:0:64:0:64:88:101:242|t ") or ""
    local help = ""
    local kind = askOf(e)
    if kind then help = "  |Hoasishelp:" .. lid(e) .. "|h|cff66db9e[" .. (kind == "group" and L["Bin dabei"] or L["Ich helfe"]) .. "]|r|h" end
    return {
        head = tag .. dcIcon .. nameLink(e) .. late,
        body = time .. mention .. highlight(text) .. reactLine(e) .. help,
    }
end
local function matches(e)
    -- nie "Unbekannt"-Platzhalter anzeigen (geschuetzte Texte schon - die loest WoW beim Zeichnen auf)
    if placeholder(e.m) then return false end
    -- geschuetzte Texte aus dem Community-Verlauf/frueheren Sitzungen erscheinen sonst als "Unbekannt"
    if isK(e.m) and e.sess ~= GC.sess then return false end
    if muted(e.s) and not ns.isMe(e.s) then return false end
    if filter == "mention" and not (mentionsMe(e.m) and not ns.isMe(e.s)) then return false end
    if filter == "links" and not e.m:find("|Hitem:", 1, true) then return false end
    if filter == "off" and e.k ~= "off" then return false end
    if filter == "all" and e.k == "off" then return false end
    if dayFilter and date("%Y%m%d", e.ts or 0) ~= dayFilter then return false end
    if search ~= "" then
        local hay = (e.m .. " " .. ns.short(e.s)):lower()
        if not hay:find(search, 1, true) then return false end
    end
    return true
end
function GC.HasOfficer()
    for _, e in ipairs(log()) do if e.k == "off" then return true end end
    return false
end

local function tc() return GC.LookColor("chatTextColor") end
-- Glasflaeche (runde, halbtransparente Flaeche wie Profil/Sammlungen); ohne Insta: schlichte Flaeche
local function glass(f, fill, line, r)
    if ns.Insta and ns.Insta.Glass then return ns.Insta.Glass(f, fill, line, r) end
    local c = fill or { 1, 1, 1, 0.04 }
    if not f.glassBg then f.glassBg = K.Fill(f, c) end
    f.glassBg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return f
end
GC.Glass = glass
local GLASS_NONE = { 0, 0, 0, 0 }
-- gehoert e zur Gruppe der vorigen Nachricht? (gleicher Absender, gleicher Kanal, hoechstens 5 Minuten)
local function sameGroup(prev, e)
    if not prev or GC.Look("chatGroup") == false then return false end
    if e.k == "ach" or prev.k == "ach" then return false end
    if (e.k == "off") ~= (prev.k == "off") then return false end
    if who(e.s) ~= who(prev.s) then return false end
    if date("%Y%m%d", e.ts or 0) ~= date("%Y%m%d", prev.ts or 0) then return false end
    return math.abs((e.ts or 0) - (prev.ts or 0)) <= 300
end
local function dayText(ts)
    local lbl = dayLabel(ts)
    local d = date(L["%d.%m."], ts)
    if lbl ~= d then lbl = lbl .. ", " .. d end
    return lbl
end

------------------------------------------------------------------------
-- Verlauf: eigene virtuelle Liste. Es werden nur die sichtbaren Zeilen gebaut (Pool),
-- Hoehen werden einmal gemessen und je Nachricht gemerkt (bis Breite/Schrift sich aendern).
------------------------------------------------------------------------
local AVATAR, CONTENT_X, RIGHT_PAD = 32, 58, 16
local heightCache = setmetatable({}, { __mode = "k" })
local function lookSig(list)
    return math.floor(list.cw or 0) .. ":" .. tostring(GC.Look("chatFont")) .. ":" .. tostring(GC.Look("chatFontSize")) .. ":" .. (renderKey or "")
end
local function applyFonts(list, row)
    local size = tonumber(GC.Look("chatFontSize")) or 13
    local font = GC.LookFont()
    K.SetFontSafe(row.body, font, size, "", K.FONT)
    K.SetFontSafe(row.name, font, size, "", K.FONT)
    local r, g, b = tc()
    row.body:SetTextColor(r, g, b)
    local tr, tg, tb = GC.LookColor("chatTimeColor")
    row.time:SetTextColor(tr, tg, tb)
    row.gut:SetTextColor(tr, tg, tb)
    row.fontSig = font .. size
end
local function itemHeight(list, it)
    if it.kind ~= "msg" then return it.kind == "day" and 40 or 34 end
    local e = it.e
    local sig = lookSig(list)
    local c = heightCache[e]
    local bh
    if c and c.sig == sig then
        bh = c.h
    else
        local m = list.meas
        local size = tonumber(GC.Look("chatFontSize")) or 13
        if m.fontSig ~= GC.LookFont() .. size then
            K.SetFontSafe(m, GC.LookFont(), size, "", K.FONT)
            m.fontSig = GC.LookFont() .. size
        end
        m:SetWidth(list.cw)
        m:SetText(render(e).body)
        bh = math.max(size + 2, math.ceil(m:GetStringHeight() or size))
        heightCache[e] = { sig = sig, h = bh }
    end
    local sp = tonumber(GC.Look("chatSpacing")) or 5
    if it.first then
        -- Kopf (Name + Zeit) ueber dem Text, oben etwas Luft zum vorigen Absender
        return math.max(AVATAR + 4, 8 + 18 + bh + 4) + sp
    end
    return bh + 4 + math.floor(sp / 2)
end

local function newRow(list)
    local row = CreateFrame("Button", nil, list)
    row:RegisterForClicks("RightButtonUp")
    if row.SetHyperlinksEnabled then pcall(row.SetHyperlinksEnabled, row, true) end
    -- Flaeche fuer eigene Nachrichten / Erwaehnungen (sonst unsichtbar)
    row.tint = CreateFrame("Frame", nil, row)
    row.tint:SetPoint("TOPLEFT", 6, -2)
    row.tint:SetPoint("BOTTOMRIGHT", -6, 1)
    row.tint:SetFrameLevel(row:GetFrameLevel())
    glass(row.tint, GLASS_NONE, GLASS_NONE, 10)
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.hl:SetPoint("TOPLEFT", 6, -1) row.hl:SetPoint("BOTTOMRIGHT", -6, 1)
    row.hl:SetColorTexture(1, 1, 1, 0.025)
    row.hl:Hide()
    -- Avatar: Kreis mit Klassensymbol, sonst Anfangsbuchstabe
    local av = CreateFrame("Frame", nil, row)
    av:SetSize(AVATAR, AVATAR)
    av:SetPoint("TOPLEFT", 14, -8)
    av.bg = av:CreateTexture(nil, "ARTWORK", nil, 0)
    av.bg:SetTexture(ns.MEDIA .. "dot")
    av.bg:SetAllPoints()
    av.icon = av:CreateTexture(nil, "ARTWORK", nil, 1)
    av.icon:SetPoint("CENTER")
    av.icon:SetSize(AVATAR - 4, AVATAR - 4)
    if av.CreateMaskTexture then
        pcall(function()
            local m = av:CreateMaskTexture()
            m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(av.icon)
            av.icon:AddMaskTexture(m)
        end)
    end
    av.ini = K.Title(av, 14, C.text, "CENTER")
    av.ini:SetPoint("CENTER")
    row.av = av
    row.name = K.Text(row, 13, C.text)
    row.name:SetPoint("TOPLEFT", CONTENT_X, -9)
    row.name:SetWordWrap(false)
    row.time = K.Text(row, 10, C.dim)
    row.time:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.body = K.Text(row, 13, C.text)
    row.body:SetJustifyH("LEFT")
    row.body:SetJustifyV("TOP")
    row.body:SetWordWrap(true)
    -- Zeit links neben Folgebeitraegen, nur beim Ueberfahren
    row.gut = K.Text(row, 9, C.dim, "RIGHT")
    row.gut:SetPoint("TOPRIGHT", row, "TOPLEFT", CONTENT_X - 8, -3)
    row.gut:Hide()
    -- Trenner: zentrierte Pille mit feinen Linien links/rechts
    row.pill = CreateFrame("Frame", nil, row)
    row.pill:SetHeight(22)
    row.pill:SetPoint("CENTER", 0, 0)
    glass(row.pill, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.08 }, 11)
    row.pill.t = K.Text(row.pill, 11, C.muted, "CENTER")
    row.pill.t:SetPoint("CENTER", 0, 0)
    row.lineL = row:CreateTexture(nil, "BORDER")
    row.lineL:SetHeight(1)
    row.lineL:SetPoint("LEFT", 18, 0)
    row.lineL:SetPoint("RIGHT", row.pill, "LEFT", -10, 0)
    row.lineR = row:CreateTexture(nil, "BORDER")
    row.lineR:SetHeight(1)
    row.lineR:SetPoint("LEFT", row.pill, "RIGHT", 10, 0)
    row.lineR:SetPoint("RIGHT", -18, 0)
    row:SetScript("OnHyperlinkClick", list.onLinkClick)
    row:SetScript("OnHyperlinkEnter", list.onLinkEnter)
    row:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, btn) if btn == "RightButton" and self.e then GC.MsgMenu(list.page, self.e) end end)
    row:SetScript("OnEnter", function(self)
        if not self.e then return end
        self.hl:Show()
        if not self.first and GC.Look("chatShowTime") ~= false then self.gut:Show() end
        if list.onRowEnter then list.onRowEnter(self, self.e) end
    end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() self.gut:Hide() GameTooltip:Hide() end)
    row:SetScript("OnMouseWheel", nil)
    applyFonts(list, row)
    return row
end
local function setAvatar(av, name)
    local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(name)
    local okIcon = false
    if cls and ns.GuildInfo and ns.GuildInfo.SetClassIcon then
        local ok, r = pcall(ns.GuildInfo.SetClassIcon, av.icon, cls)
        okIcon = ok and r and true or false
    end
    if okIcon then
        av.icon:Show() av.ini:Hide()
        av.bg:SetVertexColor(0.07, 0.075, 0.085, 1)
    else
        av.icon:Hide() av.ini:Show()
        av.ini:SetText(((ns.short(name or "?")):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper())
        local hex = ns.classHex and ns.classHex(cls) or "ff9a9aa6"
        local c = K.FromHex(hex) or { 0.6, 0.6, 0.65 }
        av.ini:SetTextColor(c[1], c[2], c[3])
        av.bg:SetVertexColor(c[1] * 0.22, c[2] * 0.22, c[3] * 0.22, 1)
    end
end
local function paintRow(list, row, it)
    if row.fontSig ~= GC.LookFont() .. (tonumber(GC.Look("chatFontSize")) or 13) then applyFonts(list, row) end
    row.e, row.first = nil, nil
    local isMsg = it.kind == "msg"
    row.av:SetShown(isMsg and it.first and true or false)
    row.name:SetShown(isMsg and it.first and true or false)
    row.time:SetShown(isMsg and it.first and true or false)
    row.body:SetShown(isMsg)
    row.pill:SetShown(not isMsg)
    row.lineL:SetShown(not isMsg)
    row.lineR:SetShown(not isMsg)
    row.gut:Hide()
    row.hl:Hide()
    if not isMsg then
        glass(row.tint, GLASS_NONE, GLASS_NONE, 10)
        local amber = it.kind == "new"
        row.pill.t:SetText(amber and L["Neu seit deinem letzten Besuch"] or dayText(it.ts))
        local c = amber and C.amber or C.muted
        row.pill.t:SetTextColor(c[1], c[2], c[3])
        row.pill:SetWidth((row.pill.t:GetStringWidth() or 60) + 24)
        if amber then glass(row.pill, { C.amber[1], C.amber[2], C.amber[3], 0.10 }, { C.amber[1], C.amber[2], C.amber[3], 0.25 }, 11)
        else glass(row.pill, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.08 }, 11) end
        local la = amber and 0.18 or 0.06
        row.lineL:SetColorTexture(c[1], c[2], c[3], la)
        row.lineR:SetColorTexture(c[1], c[2], c[3], la)
        return
    end
    local e = it.e
    row.e, row.first = e, it.first
    local r = render(e)
    row.body:ClearAllPoints()
    row.body:SetPoint("TOPLEFT", CONTENT_X, it.first and -28 or -2)
    row.body:SetWidth(list.cw)
    row.body:SetText(r.body)
    local stamp = date("%H:%M", e.ts or 0)
    row.gut:SetText(stamp)
    if it.first then
        setAvatar(row.av, e.s)
        row.name:SetText(r.head or "")
        row.time:SetText(GC.Look("chatShowTime") ~= false and stamp or "")
    end
    -- eigene Nachrichten leicht getoent, Erwaehnungen dezent bernsteinfarben
    if ns.isMe(e.s) then
        local mr, mg, mb = GC.MineBubbleColor()
        glass(row.tint, { mr, mg, mb, 0.16 }, GLASS_NONE, 10)
    elseif e.k ~= "ach" and mentionsMe(e.m) then
        glass(row.tint, { C.amber[1], C.amber[2], C.amber[3], 0.07 }, { C.amber[1], C.amber[2], C.amber[3], 0.18 }, 10)
    else
        glass(row.tint, GLASS_NONE, GLASS_NONE, 10)
    end
end

-- Liste anlegen; handlers: onLinkClick, onLinkEnter, onRowEnter, onScroll
function GC.NewList(parent, page, handlers)
    local list = CreateFrame("Frame", nil, parent)
    list.page = page
    list:SetClipsChildren(true)
    list:EnableMouseWheel(true)
    for k, v in pairs(handlers or {}) do list[k] = v end
    list.items, list.tops, list.rows, list.offset, list.total = {}, {}, {}, 0, 0
    list.stick = true
    list.visibleLines = {}
    list.meas = list:CreateFontString(nil, "ARTWORK")
    K.SetFontSafe(list.meas, GC.LookFont(), tonumber(GC.Look("chatFontSize")) or 13, "", K.FONT)
    list.meas:SetWordWrap(true)
    list.meas:SetJustifyH("LEFT")
    list.meas:Hide()
    list.empty = K.Text(list, 12, C.dim, "CENTER")
    list.empty:SetPoint("CENTER", 0, 10)
    list.empty:SetWidth(360)
    list.empty:SetWordWrap(true)
    function list:Width()
        local w = self:GetWidth() or 0
        if w < 120 then w = 600 end
        return w
    end
    function list:MaxOffset() return math.max(0, self.total - (self:GetHeight() or 0)) end
    function list:AtBottom() return self.offset >= self:MaxOffset() - 2 end
    -- Positionen neu berechnen (nach Aenderung von Inhalt, Breite oder Schrift)
    function list:Measure(from)
        self.cw = self:Width() - CONTENT_X - RIGHT_PAD
        local y = 0
        from = from or 1
        if from > 1 and self.tops[from - 1] then y = self.tops[from - 1] + self.items[from - 1].h else from = 1 end
        for i = from, #self.items do
            local it = self.items[i]
            it.h = itemHeight(self, it)
            self.tops[i] = y
            y = y + it.h
        end
        for i = #self.items + 1, #self.tops do self.tops[i] = nil end
        self.total = y + 8
    end
    function list:SetItems(items)
        self.items = items
        self:Measure(1)
        self.offset = self:MaxOffset()
        self.stick = true
        self:Draw()
    end
    -- neue Eintraege unten anhaengen (nur diese messen)
    function list:Append(newItems)
        local was = self:AtBottom()
        local from = #self.items + 1
        for _, it in ipairs(newItems) do self.items[#self.items + 1] = it end
        self:Measure(from)
        if was then self.offset = self:MaxOffset() end
        self:Draw()
        return was
    end
    function list:ScrollTo(off)
        self.offset = math.max(0, math.min(self:MaxOffset(), math.floor(off + 0.5)))
        self:Draw()
    end
    function list:ScrollToBottom() self:ScrollTo(self:MaxOffset()) end
    function list:ScrollToTop() self:ScrollTo(0) end
    -- Kompatibilitaet zu alten Aufrufen (ScrollingMessageFrame)
    function list:GetScrollOffset() return math.max(0, self:MaxOffset() - self.offset) end
    function list:Draw()
        local top, h = self.offset, self:GetHeight() or 0
        if h < 10 then h = 400 end
        wipe(self.visibleLines)
        -- erste sichtbare Zeile per Binaersuche
        local lo, hi = 1, #self.items
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if self.tops[mid] + self.items[mid].h <= top then lo = mid + 1 else hi = mid end
        end
        local n = 0
        local i = lo
        while i <= #self.items and self.tops[i] < top + h do
            n = n + 1
            local row = self.rows[n]
            if not row then row = newRow(self) self.rows[n] = row end
            local it = self.items[i]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(self.tops[i] - top))
            row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            row:SetHeight(it.h)
            paintRow(self, row, it)
            row:Show()
            if it.kind == "msg" then self.visibleLines[#self.visibleLines + 1] = row.body end
            i = i + 1
        end
        for j = n + 1, #self.rows do self.rows[j]:Hide() self.rows[j].e = nil end
        self.empty:SetShown(#self.items == 0)
        self.stick = self:AtBottom()
        if self.onScroll then self.onScroll(self) end
    end
    list:SetScript("OnMouseWheel", function(self, d)
        if IsShiftKeyDown() then
            if d > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        else
            self:ScrollTo(self.offset - d * 66)
        end
    end)
    list:SetScript("OnSizeChanged", function(self)
        local w = math.floor(self:Width())
        if w ~= self.lastW then
            self.lastW = w
            local stick = self.stick
            self:Measure(1)
            if stick then self.offset = self:MaxOffset() end
        end
        self:Draw()
    end)
    return list
end

-- Eintraege (Trenner + Nachrichten) aus dem Log bauen
local function buildItems()
    local items, n, prev, lastDay = {}, 0, nil, nil
    local seen, marked = S().chatSeen, false
    for _, e in ipairs(log()) do
        if matches(e) then
            if seen and not marked and (e.ts or 0) > seen and not ns.isMe(e.s) and n > 0 then
                items[#items + 1] = { kind = "new" }
                marked = true
                prev = nil
            end
            local d = date("%Y%m%d", e.ts)
            if d ~= lastDay then
                items[#items + 1] = { kind = "day", ts = e.ts }
                lastDay = d
                prev = nil
            end
            items[#items + 1] = { kind = "msg", e = e, first = not sameGroup(prev, e) }
            prev = e
            n = n + 1
        end
    end
    return items, n, prev, lastDay
end
local function fill(p)
    local list = p.list
    local items, n, prev, lastDay = buildItems()
    p.lastDay, p.lastShown, p.shownCount = lastDay, prev, n
    list.empty:SetText(search ~= "" and L["Nichts gefunden."] or (filter == "mention" and L["Noch niemand hat dich erwaehnt."]
        or L["Noch keine Nachrichten. Alles, was ab jetzt im Gildenchat geschrieben wird, landet hier."]))
    list:SetItems(items)
    p.newCount = 0
    p.jump:Hide()
    if p.barTitle then
        p.barTitle:SetText((L["%d Nachrichten"]):format(n))
    end
    if p.UpdateScrollbar then p.UpdateScrollbar() end
    if p.dayDrop then p.dayDrop:Update() end
end

-- neue Nachricht, waehrend die Seite offen ist: unten anhaengen statt alles neu aufzubauen
-- Oasis-Sound im Gildenchat als eigene Zeile
function GC.AddSound(sender, key)
    local e = { s = ns.fullName(sender), m = "{s:" .. key .. "}", ts = ns.now(), src = "snd" }
    GC.Add(e, true)   -- 0.5.656: GC.Add haengt schon live an (vorher zusaetzlich GC.Live -> Zeile doppelt)
end
function GC.Live(e)
    local p = GC.page
    if not (p and p:IsVisible() and p.list) or not matches(e) then return false end
    local add = {}
    local d = date("%Y%m%d", e.ts)
    if d ~= p.lastDay then
        add[#add + 1] = { kind = "day", ts = e.ts }
        p.lastDay = d
        p.lastShown = nil
    end
    add[#add + 1] = { kind = "msg", e = e, first = not sameGroup(p.lastShown, e) }
    p.lastShown = e
    p.shownCount = (p.shownCount or 0) + 1
    if p.barTitle then p.barTitle:SetText((L["%d Nachrichten"]):format(p.shownCount)) end
    local wasBottom = p.list:Append(add)
    if p.UpdateScrollbar then p.UpdateScrollbar() end
    if not wasBottom and not ns.isMe(e.s) then
        -- man liest gerade weiter oben: nicht springen, sondern Hinweis zeigen
        p.newCount = (p.newCount or 0) + 1
        p.jump.text:SetText((L["%d neue Nachrichten"]):format(p.newCount))
        if not p.jump:IsShown() then p.jump:Show() K.FadeIn(p.jump, 0) end
    elseif ns.isMe(e.s) then
        p.list:ScrollToBottom()
    end
    return true
end

-- Seitenleiste: Glaskarten "Heute im Chat", "Vielschreiber", "Zuletzt verlinkt"
local function sideStats(p, animate)
    local today = date("%Y%m%d")
    local count, by, links, writers, linkCount = 0, {}, {}, 0, 0
    local l = log()
    for i = #l, 1, -1 do
        local e = l[i]
        local isToday = date("%Y%m%d", e.ts) == today
        if e.k ~= "off" and e.k ~= "ach" and isToday then
            count = count + 1
            local m = ns.Alts and ns.Alts.Main(e.s) or e.s
            if not by[m] then writers = writers + 1 end
            by[m] = (by[m] or 0) + 1
            if e.m:find("|Hitem:", 1, true) then linkCount = linkCount + 1 end
        end
        if #links < 10 and e.k ~= "off" then
            -- Farbe egal ob |cffRRGGBB oder neu |cnIQ3: -> nur den Link selbst nehmen, Farbe nach Qualitaet
            for raw in e.m:gmatch("|Hitem:[^|]+|h%[[^%]]+%]|h") do
                local id = ns.itemID(raw) or 0
                if #links < 10 and not links["i" .. id] then
                    links["i" .. id] = true
                    local q = C_Item.GetItemQualityByID and ns.safe(C_Item.GetItemQualityByID(id))
                    local hex = "ffffffff"
                    if q and GetItemQualityColor then hex = select(4, GetItemQualityColor(q)) or hex end
                    links[#links + 1] = { link = "|c" .. hex .. raw .. "|r", who = e.s }
                end
            end
        end
    end
    -- aeltere Links: eigenes Gedaechtnis + von der Gilde geteilte, neueste zuerst
    local pool = {}
    for _, h in ipairs(ns.db.linkHist or {}) do pool[#pool + 1] = h end
    if ns.Store then
        for _, r in ipairs(ns.Store.List("links")) do
            -- geteilte Links: nur reine Item-Links ohne weitere Escape-Sequenzen
            if type(r.raw) == "string" and #r.raw < 300 and r.raw:match("^|Hitem:[%d:%-]+|h%[[^|%]]*%]|h$") then
                pool[#pool + 1] = { id = ns.itemID(r.raw), raw = r.raw, who = r.who, ts = r.ts or r.u or 0 }
            end
        end
    end
    table.sort(pool, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    for _, h in ipairs(pool) do
        if #links >= 10 then break end
        if h.id and not links["i" .. h.id] then
            links["i" .. h.id] = true
            local q = C_Item.GetItemQualityByID and ns.safe(C_Item.GetItemQualityByID(h.id))
            local hex = "ffffffff"
            if q and GetItemQualityColor then hex = select(4, GetItemQualityColor(q)) or hex end
            links[#links + 1] = { link = "|c" .. hex .. h.raw .. "|r", who = h.who }
        end
    end
    local top = {}
    for n, c in pairs(by) do top[#top + 1] = { n = n, c = c } end
    table.sort(top, function(a, b) return a.c > b.c end)
    if animate then K.CountUp(p.stToday, count, 0.8) else p.stToday:SetText(count) end
    p.stWriters:SetText(writers)
    p.stLinks:SetText(linkCount)
    local maxC = top[1] and top[1].c or 1
    for i, r in ipairs(p.topRows) do
        local t = top[i]
        if t then
            local hex = ns.classHex and ns.classHex(ns.Radar and ns.Radar.ClassOf(t.n)) or "ffd0d0d6"
            local c = K.FromHex(hex) or { 0.8, 0.8, 0.85 }
            setAvatar(r.av, t.n)
            r.name:SetText("|c" .. hex .. ns.displayName(t.n) .. "|r")
            r.val:SetText(t.c)
            local full = (r.track:GetWidth() or 0) > 10 and r.track:GetWidth() or 120
            local w = math.max(6, full * t.c / maxC)
            glass(r.bar, { c[1], c[2], c[3], 0.55 }, GLASS_NONE, 3)
            if animate then
                r.bar:SetWidth(6)
                K.Tween(r.bar, 0.9, function(q) r.bar:SetWidth(math.max(6, w * q)) end, nil, i * 0.08)
            else
                r.bar:SetWidth(w)
            end
            r:Show()
        else
            r:Hide()
        end
    end
    p.topEmpty:SetShown(#top == 0)
    -- so viele Links, wie in die Karte passen (die Karte fuellt den Rest der Spalte)
    local room = (p.linkCard and p.linkCard:GetHeight() or 0) - 44
    local fit = room > 30 and math.floor(room / 30) or #p.linkRows
    for i, r in ipairs(p.linkRows) do
        local x = links[i]
        if x and i <= fit then
            r.link = x.link
            local id = ns.itemID(x.link) or 0
            r.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
            r.text:SetText(x.link)
            r.who:SetText(ns.displayName(x.who or ""))
            r:Show()
        else
            r:Hide()
        end
    end
    p.linkEmpty:SetShown(#links == 0)
end

local function send(p, text)
    local t = (text or p.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return end
    ns.SendChat(t:sub(1, 255), filter == "off" and "OFFICER" or "GUILD")
    -- fuer Pfeil hoch: zuletzt Gesendetes (neueste zuerst)
    if not text then
        GC.sent = GC.sent or {}
        table.insert(GC.sent, 1, t)
        while #GC.sent > 20 do table.remove(GC.sent) end
        p.input.histIdx = nil
    end
    if ns.db.settings.emojiCloseOnSend ~= false and ns.Emoji and ns.Emoji.picker and ns.Emoji.picker:IsShown() then ns.Emoji.picker:Hide() end
    if not text then
        p.input:SetText("")
        p.input:SetFocus()
    end
end

local QUICK = {}   -- Kurzantworten entfernt

ns.RegisterPage({
    key = "chat", title = "Chat", order = 0.7,
    sub = "Gildenchat und private Nachrichten - nichts geht verloren",
    build = function(p)
        GC.page = p
        p:SetScript("OnShow", function(self)
            self.fresh = true
            -- Verlauf frisch anfordern und kurz danach neu zeichnen, damit geschuetzte Texte aufgeloest sind
            if GC.RequestClubHistory then pcall(GC.RequestClubHistory) end
            if self.loader then self.loader:Show() end
            ns.After(1.2, function() if self:IsVisible() then ns.RefreshPage("chat") end end)
            ns.After(2.5, function() if self.loader then self.loader:Hide() end end)
        end)
        p.fresh = true
        local SIDE, TOP = 214, 46
        p.SIDE, p.TOP = SIDE, TOP
        -- Reiterleiste oben: Gildenchat / Privat (gleitende Akzent-Pille wie im Profil)
        local TABS = { { key = "guild", text = L["Gildenchat"], icon = "social" }, { key = "priv", text = L["Privat"], icon = "profile" } }
        local function onMode(k) GC.mode = k ns.RefreshPage("chat") end
        if ns.Insta and ns.Insta.ProfileTabs then
            p.mode = ns.Insta.ProfileTabs(p, TABS, onMode)
        else
            p.mode = K.Segments(p, TABS, onMode, 100)
        end
        p.mode:SetPoint("TOPLEFT", 0, 0)
        p.mode:SetWidth(300)

        -- Verlauf als Glaskarte
        local box = CreateFrame("Frame", nil, p)
        box:SetPoint("TOPLEFT", 0, -TOP)
        box:SetPoint("BOTTOMRIGHT", -(SIDE + 12), 58)
        p.chatBox = box
        glass(box, nil, nil, 12)
        -- Kopf der Karte: Filter als Glas-Pillen links, Kalender + Suche rechts
        p.seg = CreateFrame("Frame", nil, box)
        p.seg:SetPoint("TOPLEFT", 12, -10)
        p.seg:SetSize(400, 26)
        p.seg.buttons = {}
        local FILTERS = { { key = "all", text = L["Alle"] }, { key = "mention", text = L["Erwaehnungen"] },
            { key = "links", text = L["Links"] }, { key = "off", text = L["Offiziere"] } }
        for i, it in ipairs(FILTERS) do
            local b = CreateFrame("Button", nil, p.seg)
            b.key = it.key
            b:SetHeight(26)
            b.label = K.Text(b, 12, C.muted, "CENTER")
            b.label:SetPoint("CENTER", 0, 0)
            b.label:SetText(it.text)
            b:SetWidth(math.max(54, (b.label:GetStringWidth() or 40) + 26))
            glass(b, GLASS_NONE, GLASS_NONE, 13)
            b:SetScript("OnClick", function() filter = it.key ns.RefreshPage("chat") end)
            b:SetScript("OnEnter", function(self) if p.seg.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
            b:SetScript("OnLeave", function(self) if p.seg.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
            p.seg.buttons[i] = b
        end
        function p.seg:Layout()
            local x = 0
            for _, b in ipairs(self.buttons) do
                if b:IsShown() then
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", self, "LEFT", x, 0)
                    x = x + b:GetWidth() + 6
                end
            end
            self.used = x
            -- kein Ueberlappen mit Kalender/Suche: zu schmal -> Kalender nur als Symbol, Suche schmaler
            local dd, sr = p.dayDrop, p.search
            local bw = box:GetWidth() or 0
            if dd and sr and bw > 100 then
                local full = 12 + x + 8 + 112 + 8 + 170 + 12
                local compact = bw < full
                sr:SetWidth(compact and 120 or 170)
                dd:SetWidth(compact and 30 or 112)
                if dd.t then dd.t:SetShown(not compact) end
            end
        end
        function p.seg:Select(key)
            self.value = key
            for _, b in ipairs(self.buttons) do
                local on = b.key == key
                local ac = C.accent
                if on then glass(b, { ac[1], ac[2], ac[3], 0.16 }, { ac[1], ac[2], ac[3], 0.42 }, 13)
                else glass(b, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.07 }, 13) end
                local c = on and C.text or C.muted
                b.label:SetTextColor(c[1], c[2], c[3])
            end
            self:Layout()
        end
        -- Suche erst kurz nach dem Tippen ausfuehren (nicht bei jedem Buchstaben alles neu aufbauen)
        local searchGen = 0
        p.search = K.Input(box, 170, L["Im Verlauf suchen ..."], function(t)
            searchGen = searchGen + 1
            local gen = searchGen
            ns.After(0.3, function()
                if gen ~= searchGen then return end
                search = (t or ""):lower()
                ns.RefreshPage("chat")
            end)
        end)
        p.search:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -11)
        p.search:SetHeight(24)
        p.search:SetFrameLevel(box:GetFrameLevel() + 20)
        if p.search.bg then p.search.bg:SetColorTexture(0, 0, 0, 0) end
        K.SetBorderColor(p.search, { 0, 0, 0, 0 })
        glass(p.search, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 }, 12)
        -- Trennlinie unter dem Kopf, rechts davon die Nachrichtenzahl
        box.barLine = box:CreateTexture(nil, "ARTWORK")
        box.barLine:SetPoint("TOPLEFT", 12, -45)
        box.barLine:SetPoint("TOPRIGHT", -12, -45)
        box.barLine:SetHeight(1)
        box.barLine:SetColorTexture(1, 1, 1, 0.06)
        box.barTitle = K.Text(box, 11, C.dim, "RIGHT")
        box.barTitle:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -16, 8)
        box.barTitle:Hide()
        p.barTitle = box.barTitle

        -- Hyperlinks im Verlauf (Namen, Items, Hilfe-Knopf, Emojis/Sounds)
        local function onLinkClick(self, link, text, button)
            if ns.Sound and ns.Sound.OnLink and ns.Sound.OnLink(link) then return end
            local hl = link:match("^oasishelp:(%d+)")
            if hl then if byLid[tonumber(hl)] then GC.HelpMenu(p, byLid[tonumber(hl)]) end return end
            -- Name anklicken: anfluestern (Shift/Rechtsklick wie gewohnt)
            local whoName = link:match("^player:([^:]+)")
            if whoName and button == "LeftButton" and not IsModifiedClick() then
                ns.Whisper(whoName)
                return
            end
            if button == "RightButton" and self.e then GC.MsgMenu(p, self.e) return end
            if SetItemRef then pcall(SetItemRef, link, text, button, self) end
        end
        local function onLinkEnter(self, link)
            local hl = link:match("^oasishelp:(%d+)")
            if hl then
                local e = byLid[tonumber(hl)]
                local kind, sub = e and askOf(e)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(L["Hilfe anbieten"], 1, 1, 1)
                if kind == "prof" then
                    local n = 0
                    for _, h in ipairs(profHolders(sub)) do
                        if n >= 6 then break end
                        n = n + 1
                        GameTooltip:AddDoubleLine(ns.displayName(h.m.name) .. (h.m.online and "  |cff66db9eonline|r" or ""), h.prof .. " " .. h.r, 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
                    end
                    if n == 0 then GameTooltip:AddLine(L["Niemand in der Gilde hat diesen Beruf eingetragen."], 0.6, 0.6, 0.6, true) end
                end
                GameTooltip:AddLine(L["Klick: anfluestern / Gildenmitglied vorschlagen"], 0.5, 0.5, 0.5, true)
                GameTooltip:Show()
                return
            end
            local pl = link:match("^player:([^:]+)")
            if pl and GC.NameTip then GC.NameTip(self, pl) return end
            if ns.Emoji and ns.Emoji.ShowLinkTip(self, link) then return end
            if link:find("^item:") then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end
        -- Zeile ueberfahren: Datum, Reaktionen, Hinweis auf das Menue
        local function onRowEnter(row, e)
            local lines = { date("%d.%m.%Y  %H:%M", e.ts or 0), "|cff888888" .. L["Rechtsklick: Reagieren, Antworten, Zitieren, Anpinnen ..."] .. "|r" }
            local t = reactIndex()[msgKey(e)]
            if t then
                for _, em in ipairs(t.order) do lines[#lines + 1] = emo(em) .. "  " .. table.concat(t.who[em], ", ") end
            end
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            for i, l in ipairs(lines) do if i == 1 then GameTooltip:SetText(l, 1, 1, 1) else GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end end
            GameTooltip:Show()
        end
        local list = GC.NewList(box, p, { onLinkClick = onLinkClick, onLinkEnter = onLinkEnter, onRowEnter = onRowEnter,
            onScroll = function(self)
                if p.UpdateScrollbar then p.UpdateScrollbar() end
                if self:AtBottom() and p.jump then p.newCount = 0 p.jump:Hide() end
            end })
        p.list, p.smf = list, list   -- p.smf: Anker fuer Menues (frueher ScrollingMessageFrame)
        function p.LayoutList(pinShown)
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", box, "TOPLEFT", 2, pinShown and -(48 + math.ceil(p.pin:GetHeight() or 28) + 4) or -48)
            list:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -14, 6)
        end
        if ns.Emoji and ns.Emoji.frames then table.insert(ns.Emoji.frames, list) end

        -- schmale Scrollleiste rechts (ziehbar, Klick in die Spur springt dorthin)
        local track = CreateFrame("Button", nil, box)
        track:SetPoint("TOPRIGHT", -6, -52)
        track:SetPoint("BOTTOMRIGHT", -6, 10)
        track:SetWidth(4)
        track.bg = track:CreateTexture(nil, "BACKGROUND")
        track.bg:SetAllPoints()
        track.bg:SetColorTexture(1, 1, 1, 0.04)
        local thumb = CreateFrame("Frame", nil, track)
        thumb:SetWidth(4)
        thumb.t = thumb:CreateTexture(nil, "ARTWORK")
        thumb.t:SetAllPoints()
        thumb.t:SetColorTexture(1, 1, 1, 0.22)
        thumb:EnableMouse(true)
        p.sbTrack, p.sbThumb = track, thumb
        function p.UpdateScrollbar()
            local max = list:MaxOffset()
            local h = track:GetHeight() or 100
            if max <= 0 or h < 20 then thumb:Hide() return end
            local vh = list:GetHeight() or 100
            local th = math.max(24, h * vh / math.max(vh, list.total))
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -((h - th) * list.offset / max))
            thumb:Show()
        end
        local function scrollTo(cursorY)
            local max = list:MaxOffset()
            if max <= 0 then return end
            local top, h = track:GetTop(), track:GetHeight()
            local th = thumb:GetHeight() or 24
            local scale = track:GetEffectiveScale()
            local rel = (top - cursorY / scale - th / 2) / math.max(1, h - th)
            list:ScrollTo(math.max(0, math.min(1, rel)) * max)
        end
        track:SetScript("OnMouseDown", function() local _, y = GetCursorPosition() scrollTo(y) end)
        thumb:SetScript("OnMouseDown", function(self) self.drag = true self.t:SetColorTexture(1, 1, 1, 0.45) end)
        thumb:SetScript("OnMouseUp", function(self) self.drag = nil self.t:SetColorTexture(1, 1, 1, 0.22) end)
        thumb:SetScript("OnUpdate", function(self)
            if self.drag then
                if not IsMouseButtonDown("LeftButton") then self.drag = nil self.t:SetColorTexture(1, 1, 1, 0.22) return end
                local _, y = GetCursorPosition()
                scrollTo(y)
            end
        end)

        -- Kalender: Glas-Knopf, Klick oeffnet die Monatsansicht (Tage mit Nachrichten markiert)
        local calBtn = CreateFrame("Button", nil, box)
        calBtn:SetSize(112, 24)
        calBtn:SetPoint("RIGHT", p.search, "LEFT", -8, 0)
        calBtn:SetFrameLevel(box:GetFrameLevel() + 20)
        glass(calBtn, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 }, 12)
        calBtn.icon = calBtn:CreateTexture(nil, "ARTWORK")
        calBtn.icon:SetTexture(ns.MEDIA .. "icons\\chronicle")
        calBtn.icon:SetSize(13, 13)
        calBtn.icon:SetPoint("LEFT", 10, 0)
        calBtn.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        calBtn.t = K.Text(calBtn, 12, C.text)
        calBtn.t:SetPoint("LEFT", calBtn.icon, "RIGHT", 7, 0)
        calBtn.t:SetPoint("RIGHT", -8, 0)
        calBtn.t:SetWordWrap(false)
        p.dayDrop = calBtn
        box:HookScript("OnSizeChanged", function() if p.seg and p.seg.Layout then p.seg:Layout() end end)
        function calBtn:Update()
            self.t:SetText(dayFilter and dayLabel(time({ year = tonumber(dayFilter:sub(1, 4)), month = tonumber(dayFilter:sub(5, 6)), day = tonumber(dayFilter:sub(7, 8)), hour = 12 }))
                or L["Alle Tage"])
            local ac = C.accent
            if dayFilter then glass(self, { ac[1], ac[2], ac[3], 0.14 }, { ac[1], ac[2], ac[3], 0.4 }, 12)
            else glass(self, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 }, 12) end
        end
        local cal
        local MONTHS = { "Januar", "Februar", "Maerz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
        local function counts()
            local c = {}
            for _, e in ipairs(log()) do
                local d = date("%Y%m%d", e.ts or 0)
                c[d] = (c[d] or 0) + 1
            end
            return c
        end
        local function paint()
            local y, m = cal.y, cal.m
            cal.title:SetText(L[MONTHS[m]] .. " " .. y)
            local first = time({ year = y, month = m, day = 1, hour = 12 })
            local wd = (tonumber(date("%w", first)) + 6) % 7    -- 0 = Montag
            local days = tonumber(date("%d", time({ year = y, month = m + 1, day = 0, hour = 12 })))
            local cnt = counts()
            local maxC = 1
            for _, v in pairs(cnt) do if v > maxC then maxC = v end end
            local today = date("%Y%m%d")
            for i, cell in ipairs(cal.cells) do
                local dnum = i - wd
                if dnum >= 1 and dnum <= days then
                    local key = ("%04d%02d%02d"):format(y, m, dnum)
                    local n = cnt[key] or 0
                    cell.key, cell.n = key, n
                    cell.t:SetText(dnum)
                    local a = n > 0 and (0.10 + 0.4 * math.sqrt(n / maxC)) or 0
                    local lc = key == dayFilter and { 1, 1, 1, 0.6 } or (key == today and { C.amber[1], C.amber[2], C.amber[3], 0.6 } or GLASS_NONE)
                    glass(cell, { C.accent[1], C.accent[2], C.accent[3], a }, lc, 8)
                    local tcol = n > 0 and C.text or C.dim
                    cell.t:SetTextColor(tcol[1], tcol[2], tcol[3])
                    cell:Show()
                else
                    cell.key = nil
                    cell:Hide()
                end
            end
        end
        local function buildCal()
            cal = CreateFrame("Frame", "OasisChatCalendar", UIParent)
            cal:SetSize(250, 248)
            cal:SetFrameStrata("DIALOG")
            cal:SetToplevel(true)
            cal:EnableMouse(true)
            glass(cal, { 0.06, 0.065, 0.075, 0.97 }, { 1, 1, 1, 0.1 }, 12)
            cal.title = K.Title(cal, 14, C.text, "CENTER")
            cal.title:SetPoint("TOP", 0, -12)
            local prev = K.Button(cal, "<", 26, 22, "ghost", function() cal.m = cal.m - 1 if cal.m < 1 then cal.m, cal.y = 12, cal.y - 1 end paint() end)
            prev:SetPoint("TOPLEFT", 10, -8)
            local nxt = K.Button(cal, ">", 26, 22, "ghost", function() cal.m = cal.m + 1 if cal.m > 12 then cal.m, cal.y = 1, cal.y + 1 end paint() end)
            nxt:SetPoint("TOPRIGHT", -10, -8)
            for i, wdn in ipairs({ "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }) do
                local t = K.Text(cal, 10, C.dim, "CENTER")
                t:SetPoint("TOPLEFT", 12 + (i - 1) * 32, -40)
                t:SetWidth(30)
                t:SetText(L[wdn])
            end
            cal.cells = {}
            for i = 1, 42 do
                local c = CreateFrame("Button", nil, cal)
                c:SetSize(30, 26)
                c:SetPoint("TOPLEFT", 12 + ((i - 1) % 7) * 32, -56 - math.floor((i - 1) / 7) * 28)
                c.t = K.Text(c, 11, C.text, "CENTER")
                c.t:SetPoint("CENTER")
                c:SetScript("OnClick", function(self)
                    if not self.key or (self.n or 0) == 0 then return end
                    dayFilter = self.key
                    cal:Hide()
                    ns.RefreshPage("chat")
                end)
                c:SetScript("OnEnter", function(self) if self.key then K.ShowTip(self, { dayLabel(time({ year = tonumber(self.key:sub(1, 4)), month = tonumber(self.key:sub(5, 6)), day = tonumber(self.key:sub(7, 8)), hour = 12 })), (L["%d Nachrichten"]):format(self.n or 0) }) end end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
                cal.cells[i] = c
            end
            local all = K.Button(cal, L["Alle Tage"], 110, 22, "ghost", function() dayFilter = nil cal:Hide() ns.RefreshPage("chat") end)
            all:SetPoint("BOTTOMLEFT", 10, 8)
            local x = K.CloseButton(cal, function() cal:Hide() end)
            x:SetPoint("BOTTOMRIGHT", -8, 8)
            ns.EscClose("OasisChatCalendar")
        end
        calBtn:SetScript("OnClick", function(self)
            if not cal then buildCal() end
            if cal:IsShown() then cal:Hide() return end
            local ref = dayFilter and time({ year = tonumber(dayFilter:sub(1, 4)), month = tonumber(dayFilter:sub(5, 6)), day = 1, hour = 12 }) or time()
            cal.y, cal.m = tonumber(date("%Y", ref)), tonumber(date("%m", ref))
            cal:ClearAllPoints()
            cal:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
            paint()
            cal:Show()
        end)
        calBtn:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Kalender"], L["Klick: Tag waehlen - nur Nachrichten dieses Tages"] }) end)
        calBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        calBtn:Update()

        p.loader = CreateFrame("Frame", nil, box)
        p.loader:SetPoint("TOPLEFT", 2, -48)
        p.loader:SetPoint("BOTTOMRIGHT", -2, 2)
        p.loader:SetFrameLevel(list:GetFrameLevel() + 8)
        local lb = p.loader:CreateTexture(nil, "BACKGROUND")
        lb:SetAllPoints()
        lb:SetColorTexture(GC.LookColor("chatBgColor"))
        lb:SetAlpha(0.92)
        p.loader.ring = p.loader:CreateTexture(nil, "ARTWORK")
        p.loader.ring:SetTexture(ns.MEDIA .. "arc")
        p.loader.ring:SetSize(40, 40)
        p.loader.ring:SetPoint("CENTER", 0, 14)
        p.loader.ring:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        p.loader.text = K.Text(p.loader, 12, C.muted, "CENTER")
        p.loader.text:SetPoint("TOP", p.loader.ring, "BOTTOM", 0, -10)
        p.loader:SetScript("OnUpdate", function(self, el)
            self.a = ((self.a or 0) + el * 4) % (math.pi * 2)
            self.ring:SetRotation(-self.a)
            self.t = (self.t or 0) + el
            local dots = string.rep(".", math.floor(self.t * 2) % 4)
            self.text:SetText(L["Lade Nachrichten"] .. dots)
            if self.t > 6 then self:Hide() end   -- spaetestens nach 6 s ausblenden
        end)
        p.loader:SetScript("OnShow", function(self) self.t = 0 end)
        p.loader:Hide()
        -- angepinnte Nachricht: schmale Glaszeile unter dem Kopf
        p.pin = CreateFrame("Button", nil, box)
        p.pin:SetPoint("TOPLEFT", 12, -52)
        p.pin:SetPoint("TOPRIGHT", -16, -52)
        p.pin:SetHeight(28)
        p.pin:SetFrameLevel(list:GetFrameLevel() + 6)
        glass(p.pin, { C.amber[1], C.amber[2], C.amber[3], 0.08 }, { C.amber[1], C.amber[2], C.amber[3], 0.25 }, 10)
        p.pin.icon = p.pin:CreateTexture(nil, "ARTWORK")
        p.pin.icon:SetTexture(ns.MEDIA .. "icons\\pin")
        p.pin.icon:SetSize(13, 13)
        p.pin.icon:SetPoint("LEFT", 10, 0)
        p.pin.icon:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
        p.pin.text = K.Text(p.pin, 12, C.text)
        p.pin.text:SetPoint("LEFT", p.pin.icon, "RIGHT", 8, 0)
        p.pin.text:SetPoint("RIGHT", -12, 0)
        p.pin.text:SetJustifyH("LEFT")
        p.pin.text:SetWordWrap(false)
        p.pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p.pin:SetScript("OnEnter", function(self)
            local r = ns.Store.Get("chatpin", "pin")
            if not r or not GC.PinOk(r) then return end
            K.ShowTip(self, { L["Angepinnt"], ns.displayName(SEC.Name(r.s) or "?") .. ": " .. plain(SEC.Text(r.m, 300, SYNC_LINKS)), "|cff888888" .. (L["von %s"]):format(ns.displayName(r.by or "?")) .. "|r",
                GC.CanPin() and ("|cff888888" .. L["Rechtsklick: loesen"] .. "|r") or nil })
        end)
        p.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.pin:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" and GC.CanPin() then ns.Store.Delete("chatpin", "pin") end
        end)
        p.pin:Hide()
        p.LayoutList(false)
        p:HookScript("OnHide", function() S().chatSeen = ns.now() end)

        -- "neue Nachrichten"-Knopf, wenn man weiter oben liest
        p.jump = CreateFrame("Button", nil, box)
        p.jump:SetSize(170, 26)
        p.jump:SetPoint("BOTTOM", 0, 12)
        p.jump:SetFrameLevel(list:GetFrameLevel() + 5)
        glass(p.jump, { 0.09, 0.095, 0.11, 0.96 }, { C.accent[1], C.accent[2], C.accent[3], 0.45 }, 13)
        p.jump.text = K.Text(p.jump, 11, C.text, "CENTER")
        p.jump.text:SetPoint("CENTER")
        p.jump:SetScript("OnClick", function(self)
            list:ScrollToBottom()
            p.newCount = 0
            self:Hide()
        end)
        p.jump:Hide()
        p.quick = {}

        -- Eingabeleiste: Emoji-Knopf | Textfeld | Zeichen | Senden
        -- runde Glasleiste
        local bar = CreateFrame("Frame", nil, p)
        bar:SetPoint("BOTTOMLEFT", 0, 4)
        bar:SetPoint("RIGHT", box, "RIGHT", 0, 0)
        bar:SetHeight(44)
        glass(bar, { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.09 }, 20)
        p.inputBar = bar
        p.emoji = CreateFrame("Button", nil, bar)
        p.emoji:SetSize(22, 22)
        p.emoji:SetPoint("LEFT", 14, 0)
        p.emoji.icon = p.emoji:CreateTexture(nil, "ARTWORK")
        p.emoji.icon:SetAllPoints()
        p.emoji.icon:SetTexture(ns.MEDIA .. "emoji\\smile")
        p.emoji.icon:SetDesaturated(true)
        p.emoji:SetScript("OnEnter", function(self) self.icon:SetDesaturated(false) K.ShowTip(self, { L["Emojis"], L["Klick: Auswahl oeffnen"] }) end)
        p.emoji:SetScript("OnLeave", function(self) self.icon:SetDesaturated(true) GameTooltip:Hide() end)
        p.emoji:SetScript("OnClick", function(self)
            if ns.Emoji then
                ns.Emoji.target = p.input
                ns.Emoji.TogglePicker(self)
            end
        end)
        -- Sound schicken (mit Abklingzeit)
        p.sndBtn = CreateFrame("Button", nil, bar)
        p.sndBtn:SetSize(22, 22)
        p.sndBtn:SetPoint("LEFT", p.emoji, "RIGHT", 6, 0)
        p.sndBtn.icon = p.sndBtn:CreateTexture(nil, "ARTWORK")
        p.sndBtn.icon:SetAllPoints()
        p.sndBtn.icon:SetTexture(ns.MEDIA .. "icons\\speaker")
        p.sndBtn.icon:SetVertexColor(0.6, 0.6, 0.62)
        p.sndBtn:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            K.ShowTip(self, { L["Sound schicken"], L["Alle mit Oasis hoeren ihn - hoechstens alle 30 Sekunden."] })
        end)
        p.sndBtn:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.62) GameTooltip:Hide() end)
        if ns.Sound and ns.Sound.AttachCooldown then pcall(ns.Sound.AttachCooldown, p.sndBtn) end
        p.sndBtn:SetScript("OnClick", function(self)
            if ns.Sound and ns.Sound.OpenPicker then ns.Sound.OpenPicker(self, nil, function(k)
                ns.Sound.SendInChat(k)
                -- angefangenen Text behalten und weiterschreiben koennen
                if (p.input:GetText() or "") ~= "" then p.input:SetFocus() end
            end, "send") end
        end)
        -- Fluester-Verlauf (verpasste Nachrichten)
        p.wlBtn = CreateFrame("Button", nil, bar)
        p.wlBtn:SetSize(22, 22)
        p.wlBtn:SetPoint("LEFT", p.sndBtn, "RIGHT", 6, 0)
        p.wlBtn.icon = p.wlBtn:CreateTexture(nil, "ARTWORK")
        p.wlBtn.icon:SetAllPoints()
        p.wlBtn.icon:SetTexture(ns.MEDIA .. "icons\\badges\\whisper")
        p.wlBtn.icon:SetVertexColor(0.6, 0.6, 0.62)
        p.wlBtn.n = K.Text(p.wlBtn, 9, C.text, "CENTER")
        K.CenterNum(p.wlBtn.n, p.wlBtn, "TOPRIGHT", -2, -2)
        p.wlBtn:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.pink[1], C.pink[2], C.pink[3])
            K.ShowTip(self, { L["Fluester-Verlauf"], L["Alle Fluesternachrichten - auch die, die du verpasst hast (/oa fl)."] })
        end)
        p.wlBtn:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.62) GameTooltip:Hide() end)
        p.wlBtn:SetScript("OnClick", function() GC.mode = "priv" ns.RefreshPage("chat") end)
        p.wlBtn:Hide()
        p.wlBtn:SetScript("OnUpdate", function(self, el)
            self.t = (self.t or 0) + el
            if self.t < 1 then return end
            self.t = 0
            local n = ns.WhisperLog and ns.WhisperLog.Unread() or 0
            self.n:SetText(n > 0 and ("|cffff5a4a" .. n .. "|r") or "")
        end)
        -- ruhiger, runder Senden-Knopf: gedaempfte Akzentfarbe, nur mit Text aktiv
        p.sendBtn = CreateFrame("Button", nil, bar)
        p.sendBtn:SetSize(32, 32)
        p.sendBtn:SetPoint("RIGHT", -6, 0)
        p.sendBtn.bg = p.sendBtn:CreateTexture(nil, "BACKGROUND")
        p.sendBtn.bg:SetTexture(ns.MEDIA .. "dot")
        p.sendBtn.bg:SetAllPoints()
        p.sendBtn.arrow = {}
        for i, d in ipairs({ { 2, 12, 0, -1, 0 }, { 2, 8, -2.6, 2.4, -math.pi / 4 }, { 2, 8, 2.6, 2.4, math.pi / 4 } }) do
            local t = p.sendBtn:CreateTexture(nil, "ARTWORK")
            t:SetSize(d[1], d[2])
            t:SetPoint("CENTER", d[3], d[4])
            t:SetColorTexture(1, 1, 1, 1)
            if d[5] ~= 0 and t.SetRotation then pcall(t.SetRotation, t, d[5]) end
            p.sendBtn.arrow[i] = t
        end
        function p.sendBtn:Paint()
            local on, ac = self.active, C.accent
            if on then self.bg:SetVertexColor(ac[1] * 0.8, ac[2] * 0.8, ac[3] * 0.8, self.hover and 0.95 or 0.75)
            else self.bg:SetVertexColor(1, 1, 1, 0.07) end
            for _, t in ipairs(self.arrow) do t:SetAlpha(on and 1 or 0.35) end
        end
        p.sendBtn:SetScript("OnEnter", function(self) self.hover = true self:Paint() K.ShowTip(self, { L["Senden"], "|cff888888" .. L["Enter"] .. "|r" }) end)
        p.sendBtn:SetScript("OnLeave", function(self) self.hover = nil self:Paint() GameTooltip:Hide() end)
        p.sendBtn:SetScript("OnClick", function() send(p) end)
        p.sendBtn:Paint()
        p.counter = K.Text(bar, 10, C.dim, "RIGHT")
        p.counter:SetPoint("RIGHT", p.sendBtn, "LEFT", -8, 0)
        p.input = K.Input(bar, 300, L["Schreib was an die Gilde ... (Enter sendet)"])
        if ns.EmojiComplete then ns.EmojiComplete.Attach(p.input) end   -- :xx -> Emoji-Vorschlaege
        p.input:SetPoint("LEFT", p.sndBtn, "RIGHT", 6, 0)
        p.input:SetPoint("RIGHT", p.counter, "LEFT", -8, 0)
        p.input.bg:SetColorTexture(0, 0, 0, 0)
        K.SetBorderColor(p.input, { 0, 0, 0, 0 })
        p.input:SetScript("OnEditFocusGained", function() glass(bar, { 1, 1, 1, 0.055 }, { C.accent[1], C.accent[2], C.accent[3], 0.45 }, 20) end)
        p.input:SetScript("OnEditFocusLost", function() glass(bar, { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.09 }, 20) end)
        p.input:SetMaxLetters(255)
        p.input:HookScript("OnTextChanged", function(self)
            local n = #(self:GetText() or "")
            p.counter:SetText(n >= 150 and (n .. "/255") or "")
            p.sendBtn.active = (self:GetText() or ""):find("%S") ~= nil
            p.sendBtn:Paint()
            p.counter:SetTextColor((n > 230 and C.red or C.dim)[1], (n > 230 and C.red or C.dim)[2], (n > 230 and C.red or C.dim)[3])
        end)
        p.input:SetScript("OnEnterPressed", function() send(p) end)
        K.InputHistory(p.input, function() return GC.sent end)
        p.input:HookScript("OnTextChanged", function(self, user)
            local t = self:GetText() or ""
            if user and t ~= "" and t:sub(1, 1) ~= "/" and GetTime() - (GC.lastTyp or 0) > 4 and S().chatTyping ~= false then
                GC.lastTyp = GetTime()
                if Comm and Comm.Guild then Comm.Guild("TYP", filter == "off" and "o" or "g") end
            end
        end)
        p.typing = K.Text(box, 11, C.dim, "LEFT")
        p.typing:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 58, 6)
        p:HookScript("OnUpdate", function(self, el)
            self.typT = (self.typT or 0) + el
            if self.typT < 0.5 then return end
            self.typT = 0
            local names, now = {}, GetTime()
            for n, t in pairs(GC.typers) do
                if now - t > 6 then GC.typers[n] = nil else names[#names + 1] = ns.displayName(n) end
            end
            table.sort(names)
            if #names == 0 then self.typing:SetText("")
            elseif #names == 1 then self.typing:SetText((L["%s schreibt ..."]):format(names[1]))
            else self.typing:SetText((L["%s schreiben ..."]):format(table.concat(names, ", "))) end
        end)
        if ns.Emoji and ns.Emoji.AttachHotkey then ns.Emoji.AttachHotkey(p.input, function() return p.emoji end) end

        -- Items per Shift-Klick direkt ins Oasis-Eingabefeld verlinken
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if link and p.input:HasFocus() then p.input:Insert(link) end
        end)

        -- @Name: Vorschlaege aus der Gildenliste (Online zuerst), Tab/Klick vervollstaendigt
        local ac = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        ac:SetFrameStrata("DIALOG")
        ac:SetPoint("BOTTOMLEFT", p.input, "TOPLEFT", 0, 6)
        ac:SetSize(200, 10)
        K.Fill(ac, C.raised)
        K.Border(ac, C.accent2)
        ac:Hide()
        ac.rows = {}
        local function complete(name)
            local t = p.input:GetText() or ""
            local short = name:match("^([^%-]+)") or name
            p.input:SetText((t:gsub("@[^@]*$", "@" .. short .. " ")))
            p.input:SetCursorPosition(#p.input:GetText())
            ac:Hide()
        end
        for i = 1, 6 do
            local r = CreateFrame("Button", nil, ac)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
            r:SetPoint("RIGHT", -4, 0)
            r.t = K.Text(r, 12, C.text)
            r.t:SetPoint("LEFT", 6, 0)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnClick", function(self) complete(self.name) end)
            ac.rows[i] = r
        end
        local function suggest(prefix)
            local list = {}
            prefix = prefix:lower()
            for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
                local short = (m.name or ""):match("^([^%-]+)") or ""
                if short ~= "" and not ns.isMe(m.name) and short:lower():sub(1, #prefix) == prefix then
                    list[#list + 1] = m
                end
            end
            table.sort(list, function(a, b)
                if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
                return (a.name or "") < (b.name or "")
            end)
            return list
        end
        p.input:HookScript("OnTextChanged", function(self, user)
            local pre = (self:GetText() or ""):match("@([^@]*)$")
            if not user or not pre then ac:Hide() return end
            local list = suggest(pre)
            if #list == 0 then ac:Hide() return end
            for i, r in ipairs(ac.rows) do
                local m = list[i]
                r:SetShown(m ~= nil)
                if m then
                    r.name = m.name
                    local cc = RAID_CLASS_COLORS and m.class and RAID_CLASS_COLORS[m.class]
                    local short = m.name:match("^([^%-]+)") or m.name
                    r.t:SetText((cc and ("|c" .. cc.colorStr) or "") .. short .. (cc and "|r" or "")
                        .. (m.online and "  |cff66db9eonline|r" or "  |cff777777offline|r"))
                end
            end
            ac:SetHeight(8 + math.min(#list, 6) * 20)
            ac.first = list[1].name
            ac:Show()
        end)
        p.input:HookScript("OnTabPressed", function() if ac:IsShown() and ac.first then complete(ac.first) end end)
        p.input:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() ac:Hide() end) end)
        p.input:HookScript("OnEscapePressed", function() ac:Hide() end)

        -- rechte Spalte: drei Glaskarten
        local side = CreateFrame("Frame", nil, p)
        side:SetPoint("TOPRIGHT", 0, -TOP)
        side:SetPoint("BOTTOMRIGHT", 0, 0)
        side:SetWidth(SIDE)
        p.sidePanel = side
        local function cardHead(card, text)
            local h = K.Text(card, 13, C.text)
            h:SetPoint("TOPLEFT", 14, -12)
            h:SetText(text)
            return h
        end
        -- Karte 1: Heute im Chat (Zahl gross, zwei kleine Kennzahlen)
        local c1 = CreateFrame("Frame", nil, side)
        c1:SetPoint("TOPLEFT") c1:SetPoint("TOPRIGHT")
        c1:SetHeight(104)
        glass(c1, nil, nil, 12)
        cardHead(c1, L["Heute im Chat"])
        p.stToday = K.Title(c1, 26, C.text)
        p.stToday:SetPoint("TOPLEFT", 14, -36)
        local stl = K.Text(c1, 11, C.muted)
        stl:SetPoint("BOTTOMLEFT", p.stToday, "BOTTOMRIGHT", 7, 3)
        stl:SetText(L["Nachrichten"])
        local function mini(x, label)
            local v = K.Title(c1, 13, C.text)
            v:SetPoint("TOPLEFT", x, -74)
            local t = K.Text(c1, 11, C.dim)
            t:SetPoint("LEFT", v, "RIGHT", 5, 0)
            t:SetText(label)
            return v
        end
        p.stWriters = mini(14, L["schreiben"])
        p.stLinks = mini(110, L["Links"])
        -- Karte 2: Vielschreiber (Klassensymbol, Name, runde Balken)
        local c2 = CreateFrame("Frame", nil, side)
        c2:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, -10)
        c2:SetPoint("TOPRIGHT", c1, "BOTTOMRIGHT", 0, -10)
        c2:SetHeight(40 + 5 * 34)
        glass(c2, nil, nil, 12)
        cardHead(c2, L["Vielschreiber"])
        p.topRows = {}
        for i = 1, 5 do
            local r = CreateFrame("Frame", nil, c2)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 34)
            r:SetPoint("RIGHT", -14, 0)
            local av = CreateFrame("Frame", nil, r)
            av:SetSize(24, 24)
            av:SetPoint("LEFT", 0, 0)
            av.bg = av:CreateTexture(nil, "ARTWORK", nil, 0)
            av.bg:SetTexture(ns.MEDIA .. "dot")
            av.bg:SetAllPoints()
            av.icon = av:CreateTexture(nil, "ARTWORK", nil, 1)
            av.icon:SetPoint("CENTER")
            av.icon:SetSize(21, 21)
            if av.CreateMaskTexture then
                pcall(function()
                    local m = av:CreateMaskTexture()
                    m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    m:SetAllPoints(av.icon)
                    av.icon:AddMaskTexture(m)
                end)
            end
            av.ini = K.Title(av, 11, C.text, "CENTER")
            av.ini:SetPoint("CENTER")
            r.av = av
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("TOPLEFT", 32, -1)
            r.name:SetPoint("RIGHT", -30, 0)
            r.name:SetWordWrap(false)
            r.val = K.Text(r, 12, C.muted, "RIGHT")
            r.val:SetPoint("TOPRIGHT", 0, -1)
            r.track = CreateFrame("Frame", nil, r)
            r.track:SetPoint("BOTTOMLEFT", 32, 3)
            r.track:SetPoint("BOTTOMRIGHT", 0, 3)
            r.track:SetHeight(6)
            glass(r.track, { 1, 1, 1, 0.05 }, GLASS_NONE, 3)
            r.bar = CreateFrame("Frame", nil, r.track)
            r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT")
            r.bar:SetWidth(6)
            p.topRows[i] = r
        end
        p.topEmpty = K.Text(c2, 11, C.dim)
        p.topEmpty:SetPoint("TOPLEFT", 14, -40)
        p.topEmpty:SetText(L["Heute noch still."])
        -- Karte 3: Zuletzt verlinkt (fuellt den Rest der Spalte)
        local c3 = CreateFrame("Frame", nil, side)
        c3:SetPoint("TOPLEFT", c2, "BOTTOMLEFT", 0, -10)
        c3:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
        glass(c3, nil, nil, 12)
        cardHead(c3, L["Zuletzt verlinkt"])
        p.linkCard = c3
        c3:SetScript("OnSizeChanged", function() if p:IsVisible() and GC.mode ~= "priv" then sideStats(p) end end)
        p.linkRows = {}
        for i = 1, 10 do
            local r = CreateFrame("Button", nil, c3)
            r:SetHeight(28)
            r:SetPoint("TOPLEFT", 8, -36 - (i - 1) * 30)
            r:SetPoint("RIGHT", -8, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.04)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 6, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if K.RoundMask then pcall(K.RoundMask, r.icon, r.icon, 5) end
            r.text = K.Text(r, 12, C.text)
            r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
            r.text:SetPoint("RIGHT", -6, 0)
            r.text:SetWordWrap(false)
            r.who = K.Text(r, 10, C.dim)
            r.who:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -1)
            r.who:SetPoint("RIGHT", -6, 0)
            r.who:SetWordWrap(false)
            r:SetScript("OnEnter", function(self) if self.link then K.ItemTip(self, self.link) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
            end)
            p.linkRows[i] = r
        end
        p.linkEmpty = K.Text(c3, 11, C.dim)
        p.linkEmpty:SetPoint("TOPLEFT", 14, -40)
        p.linkEmpty:SetText(L["Noch keine Items verlinkt."])
        if ns.WhisperLog and ns.WhisperLog.BuildPrivate then
            p.priv = ns.WhisperLog.BuildPrivate(p)
            p.priv:SetPoint("TOPLEFT", 0, -TOP)
            p.priv:SetPoint("BOTTOMRIGHT", 0, 0)
        end
        -- Zahnrad oben rechts: Darstellung des Chats (Schrift, Farben, Abstaende)
        local gear = CreateFrame("Button", nil, p)
        gear:SetSize(30, 30)
        gear:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -2)
        gear:SetFrameLevel(p:GetFrameLevel() + 40)
        glass(gear, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.085 }, 10)
        gear.icon = gear:CreateTexture(nil, "ARTWORK")
        gear.icon:SetTexture(ns.MEDIA .. "icons\\settings")
        gear.icon:SetSize(15, 15)
        gear.icon:SetPoint("CENTER")
        gear.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        gear:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
            K.ShowTip(self, { L["Chat-Darstellung"], L["Schrift, Farben und Abstaende - nur fuer dich"] })
        end)
        gear:SetScript("OnLeave", function(self)
            self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            GameTooltip:Hide()
        end)
        gear:SetScript("OnClick", function(self) GC.ToggleLookPopup(self) end)
        p.gear = gear
        GC.ApplyLook(true)
    end,
    refresh = function(p)
        -- Reiter Gilde / Privat
        local isPriv = GC.mode == "priv" and p.priv ~= nil
        if p.mode then
            p.mode:Select(isPriv and "priv" or "guild")
            local n = ns.WhisperLog and ns.WhisperLog.Unread() or 0
            if p.mode.buttons and p.mode.buttons[2] and p.mode.buttons[2].label then
                p.mode.buttons[2].label:SetText(L["Privat"] .. (n > 0 and ("  |cffff7a6a" .. n .. "|r") or ""))
                if p.mode.Layout then pcall(p.mode.Layout, p.mode) end
            end
        end
        -- Gildenchat in der Privat-Ansicht wirklich ausblenden (schien sonst durch die Gespraechsliste)
        if p.chatBox then p.chatBox:SetShown(not isPriv) end
        if p.inputBar then p.inputBar:SetShown(not isPriv) end
        if p.typing then p.typing:SetShown(not isPriv) end
        if p.sidePanel then p.sidePanel:SetShown(not isPriv) end
        if p.priv then
            p.priv:SetShown(isPriv)
            if isPriv then ns.WhisperLog.RefreshPrivate() return end
        end
        local fresh = p.fresh
        unread, mentioned = 0, false
        ns.SetNavBadge("chat", nil)
        local off = GC.HasOfficer()
        if p.seg.buttons and p.seg.buttons[4] then p.seg.buttons[4]:SetShown(off) end
        if filter == "off" and not off then filter = "all" end
        p.seg:Select(filter)
        GC.UpdatePin(p)
        fill(p)
        sideStats(p, fresh)
        if fresh then K.FadeIn(p.list, 0) end
        p.fresh = false
    end,
})

------------------------------------------------------------------------
-- Darstellung anwenden + Einstellungs-Bausteine (Einstellungen > Bereiche > Chat und Zahnrad-Fenster)
------------------------------------------------------------------------
function GC.ApplyLook(noRefresh)
    GC.ClearRenderCache()
    local p = GC.page
    if p and p.chatBox then
        -- Kartenflaeche des Verlaufs: Farbe + Deckkraft aus der Darstellung
        local r, g, b = GC.LookColor("chatBgColor")
        glass(p.chatBox, { r, g, b, (tonumber(GC.Look("chatBgAlpha")) or 90) / 100 }, nil, 12)
    end
    local WL = ns.WhisperLog
    if WL and WL.ApplyLook then pcall(WL.ApplyLook) end
    if not noRefresh and p and p:IsVisible() then ns.RefreshPage("chat") end
end
-- beim Ziehen eines Reglers nicht bei jedem Pixel alles neu aufbauen
local lookGen = 0
local function applySoon()
    lookGen = lookGen + 1
    local g = lookGen
    ns.After(0.15, function() if g == lookGen then GC.ApplyLook() end end)
end
local function setLook(k, v) S()[k] = v applySoon() end
-- eigene Blasenfarbe: leer = gedaempfte Akzentfarbe (wie bisher)
function GC.MineBubbleColor()
    local c = K.FromHex(GC.Look("chatBubbleMine"))
    if c then return c[1], c[2], c[3] end
    -- Akzent stark entsaettigt und abgedunkelt: ruhiges Grau mit leichtem Farbstich
    local g, t = 0.17, 0.2
    return g + (C.accent[1] - g) * t, g + (C.accent[2] - g) * t, g + 0.01 + (C.accent[3] - g) * t
end

-- baut die Darstellungs-Regler in parent ab Hoehe y; liefert das neue y
-- opts.emoji = Emoji-Groesse mit anbieten (in den Einstellungen gibt es den Regler schon), opts.x = linker Rand
function GC.BuildLook(parent, y, opts)
    opts = opts or {}
    local X, CX = opts.x or 14, (opts.x or 14) + 170
    local widgets = {}
    local function label(text, yy)
        local fs = K.Text(parent, 13, C.text)
        fs:SetPoint("TOPLEFT", X, yy - 3)
        fs:SetText(text)
        return fs
    end
    local function track(w) widgets[#widgets + 1] = w if parent.t then parent.t[#parent.t + 1] = w end return w end
    local h = K.Text(parent, 12, C.amber)
    h:SetPoint("TOPLEFT", X, y)
    h:SetText(L["Darstellung"])
    y = y - 26
    -- Schriftart
    label(L["Schriftart"], y)
    local fb = K.Button(parent, "", 180, 24, "ghost")
    fb.isDropdown = true
    fb:SetPoint("TOPLEFT", CX, y + 2)
    function fb:Refresh()
        local k = GC.Look("chatFont")
        local f = k ~= "" and K.fontByKey[k]
        self:SetLabel(f and f.text or L["Oasis-Schrift"])
    end
    fb:SetScript("OnClick", function(self)
        local cur = GC.Look("chatFont")
        local list = { { text = L["Oasis-Schrift"], checked = cur == "", fn = function() setLook("chatFont", "") self:Refresh() end } }
        for _, f in ipairs(K.PickFonts(function(x) return x.ui end)) do
            list[#list + 1] = { text = f.text, checked = cur == f.key, fn = function() setLook("chatFont", f.key) self:Refresh() end }
        end
        K.ShowMenu(self, list, nil, 180)
    end)
    fb:Refresh()
    track(fb)
    y = y - 32
    local function slider(text, key, minV, maxV, step, fmt)
        label(text, y)
        local s = K.Slider(parent, 200, minV, maxV, step, function() return tonumber(GC.Look(key)) or minV end,
            function(v) setLook(key, v) end, fmt)
        s:SetPoint("TOPLEFT", CX, y)
        track(s)
        y = y - 30
        return s
    end
    slider(L["Schriftgroesse"], "chatFontSize", 10, 18, 1, function(v) return v .. " px" end)
    slider(L["Zeilenabstand"], "chatSpacing", 0, 12, 1, function(v) return v .. " px" end)
    if opts.emoji then
        label(L["Emoji-Groesse im Chat"], y)
        local s = K.Slider(parent, 200, 0, 32, 2, function() return tonumber(S().emojiChatSize) or 0 end,
            function(v) S().emojiChatSize = v applySoon() end, function(v) return v == 0 and L["automatisch"] or (v .. " px") end)
        s:SetPoint("TOPLEFT", CX, y)
        track(s)
        y = y - 30
    end
    local function color(text, key, getHex)
        label(text, y)
        local b = K.ColorPickButton(parent, getHex or function() return K.ToHex({ GC.LookColor(key) }) end,
            function(hex) S()[key] = (hex and hex ~= "") and hex or nil applySoon() end, L["Farbe waehlen"],
            function() return S()[key] end)
        b:SetPoint("TOPLEFT", CX, y + 2)
        b:SetWidth(140)
        b.Refresh = b.Update
        track(b)
        y = y - 30
        return b
    end
    color(L["Schriftfarbe"], "chatTextColor")
    color(L["Zeitstempel"], "chatTimeColor")
    color(L["Hintergrund"], "chatBgColor")
    slider(L["Deckkraft Hintergrund"], "chatBgAlpha", 0, 100, 5, function(v) return v .. " %" end)
    color(L["Blase eigene (Privat)"], "chatBubbleMine", function() return K.ToHex({ GC.MineBubbleColor() }) end)
    color(L["Blase fremde (Privat)"], "chatBubbleOther")
    local function tg(text, key, desc)
        local t = K.Toggle(parent, text, function() return GC.Look(key) ~= false end, function(v) setLook(key, v and true or false) end, desc)
        t:SetPoint("TOPLEFT", X, y)
        t:SetWidth(opts.width or 360)
        track(t)
        y = y - (desc and 42 or 30)
    end
    tg(L["Zeitstempel anzeigen"], "chatShowTime")
    tg(L["Nachrichten gruppieren"], "chatGroup", L["Mehrere Nachrichten derselben Person kurz hintereinander stehen unter einem Namen"])
    local reset = K.Button(parent, L["Zuruecksetzen"], 130, 24, "ghost", function()
        for k in pairs(GC.LOOK_DEF) do S()[k] = nil end
        if opts.emoji then S().emojiChatSize = nil end
        for _, w in ipairs(widgets) do if w.Refresh then pcall(w.Refresh, w) end end
        GC.ApplyLook()
    end)
    reset:SetPoint("TOPLEFT", X, y - 2)
    track(reset)
    return y - 36
end

-- kleines Fenster am Zahnrad
local lookPop
function GC.ToggleLookPopup(owner)
    if lookPop and lookPop:IsShown() then lookPop:Hide() return end
    if not lookPop then
        lookPop = CreateFrame("Frame", "OasisChatLook", UIParent)
        lookPop:SetFrameStrata("DIALOG")
        lookPop:SetToplevel(true)
        lookPop:EnableMouse(true)
        lookPop:SetClampedToScreen(true)
        lookPop:SetWidth(420)
        K.Fill(lookPop, { 0.07, 0.075, 0.085, 0.98 })
        K.Border(lookPop, C.line)
        if K.ApplySkin then pcall(K.ApplySkin, lookPop, "panel", { 0.07, 0.075, 0.085, 0.98 }) end
        local title = K.Title(lookPop, 15, C.text)
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText(L["Chat-Darstellung"])
        local x = K.CloseButton(lookPop, function() lookPop:Hide() end)
        x:SetPoint("TOPRIGHT", -10, -10)
        local y = GC.BuildLook(lookPop, -46, { emoji = true, x = 16, width = 380 })
        lookPop:SetHeight(-y + 8)
        if ns.EscClose then ns.EscClose("OasisChatLook") end
    end
    lookPop:ClearAllPoints()
    lookPop:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -6)
    lookPop:Show()
end

ns.slash.chat = function() ns.ShowPage("chat") end

-- Diagnose: /oa chatdebug - letzte Eintraege mit Quelle (live / club = Community-Verlauf / sync:Name = von anderem Oasis)
ns.slash.chatdebug = function()
    local l = log()
    ns.print(("Gildenchat: %d Eintraege"):format(#l))
    for i = math.max(1, #l - 11), #l do
        local e = l[i]
        ns.print(("%s  %s  [%s]  %q  k=%s"):format(date("%H:%M:%S", e.ts or 0), ns.displayName(e.s or "?"), tostring(e.src or "-"),
            tostring(e.m):sub(1, 40), tostring(e.k)))
    end
end


------------------------------------------------------------------------
-- Extras: Menues, Pin, Tipp-Anzeige, Namens-Karte
------------------------------------------------------------------------
GC.typers = {}
if Comm and Comm.On then
    Comm.On("TYP", function(sender, channel, kind)
        if ns.isMe(sender) or muted(sender) then return end
        if S().chatTyping == false then return end
        if kind == "o" and not GC.HasOfficer() then return end
        GC.typers[sender] = GetTime()
    end)
end
-- neue Nachricht von jemandem -> "schreibt" sofort weg
local baseAdd = GC.Add
GC.Add = function(e, silent)
    if e and e.s then
        for n in pairs(GC.typers) do if who(n) == who(e.s) then GC.typers[n] = nil end end
    end
    return baseAdd(e, silent)
end

function GC.CanPin()
    if ns.GuildOpt("chPin") == "lead" then
        return (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) and true or false
    end
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then
        local ok, v = pcall(C_GuildInfo.CanEditOfficerNote)
        if ok and v then return true end
    end
    if CanEditOfficerNote then
        local ok, v = pcall(CanEditOfficerNote)
        if ok and v then return true end
    end
    return false
end

-- Pin nur zeigen, wenn ihn jemand mit Rechten gesetzt hat (Pruefung beim Empfaenger, nicht nur im Menue)
function GC.PinOk(r)
    if not r or r.del or type(r.m) ~= "string" then return false end
    local by = r.mb or r.by
    if not by then return false end
    if ns.isMe(by) then return true end
    local A = ns.Admin
    if not (A and A.RoleOf) then return true end
    local role = A.RoleOf(by)
    if ns.GuildOpt("chPin") == "lead" then return role == "lead" end
    return role == "lead" or role == "officer"
end
function GC.UpdatePin(p)
    if not (p and p.pin) then return end
    local r = ns.Store.Get("chatpin", "pin")
    local show = r and GC.PinOk(r) and (ns.now() - (r.u or 0)) < (tonumber(ns.GuildOpt("chPinD")) or 14) * 86400
    if show then
        r = { s = SEC.Name(r.s) or "?", m = SEC.Text(r.m, 300, SYNC_LINKS), by = r.by, u = r.u }
    end
    p.pin:SetShown(show and true or false)
    if p.LayoutList then p.LayoutList(show and true or false) end
    if show then
        p.pin.text:SetText("|cffe8b44a" .. L["Angepinnt"] .. "|r   |cffcccccc" .. ns.displayName(r.s or "?") .. ":|r  " .. emo(plain(r.m)))
    end
end

local function firstName(n) return ns.displayName(n) end
function GC.MsgMenu(p, e)
    local items = {}
    local mine = ns.Store.Get("reacts", msgKey(e) .. "#" .. ns.me())
    local cur = mine and not mine.del and mine.em
    local row = {}
    for _, em in ipairs(GC.REACTS) do
        items[#items + 1] = { text = emo(em) .. "  " .. (cur == em and ("|cff66db9e" .. L["(deine Reaktion)"] .. "|r") or L["Reagieren"]), checked = cur == em,
            fn = function() GC.ToggleReact(e, em) end }
    end
    items[#items + 1] = { text = L["Antworten"], fn = function()
        p.input:SetText("@" .. firstName(e.s) .. " ")
        p.input:SetFocus()
        p.input:SetCursorPosition(#p.input:GetText())
    end }
    items[#items + 1] = { text = L["Zitieren"], fn = function()
        local q = plain(e.m)
        if #q > 50 then q = q:sub(1, 48) .. ".." end
        p.input:SetText("\"" .. firstName(e.s) .. ": " .. q .. "\"  ")
        p.input:SetFocus()
        p.input:SetCursorPosition(#p.input:GetText())
    end }
    -- Kopieren (Kopierfenster, Text markiert) und Merken (Merkliste im Reiter Privat > Gemerkt)
    local WLx = ns.WhisperLog
    if WLx and WLx.Copy then
        items[#items + 1] = { text = L["Kopieren"], fn = function() WLx.Copy(L["Nachricht kopieren"], plain(e.m)) end }
    end
    if WLx and WLx.ToggleGuildStar then
        local starred = WLx.GuildStarred(msgKey(e))
        items[#items + 1] = { text = starred and L["Nicht mehr merken"] or L["Nachricht merken"], fn = function()
            WLx.ToggleGuildStar(msgKey(e), e.s, e.m, e.ts)
        end }
    end
    if not ns.isMe(e.s) then
        items[#items + 1] = { text = L["Anfluestern"], fn = function() ns.Whisper(e.s) end }
        if ns.Profile and ns.Profile.Show then items[#items + 1] = { text = L["Profil ansehen"], fn = function() ns.Profile.Show(e.s) end } end
        if ns.Talents then items[#items + 1] = { text = L["Talente ansehen"], fn = function() ns.Talents.Show(e.s) end } end
    end
    if GC.CanPin() then
        items[#items + 1] = { text = L["Anpinnen"], fn = function()
            ns.Store.Put("chatpin", { id = "pin", s = e.s, m = e.m, ts = e.ts })
        end }
    end
    if not ns.isMe(e.s) then
        local isM = muted(e.s)
        items[#items + 1] = { text = isM and L["Stummschaltung aufheben"] or (L["%s stummschalten"]):format(firstName(e.s)), fn = function()
            S().chatMuted = S().chatMuted or {}
            S().chatMuted[who(e.s)] = (not isM) or nil
            GC.ClearRenderCache()
            ns.RefreshPage("chat")
        end }
    end
    K.ShowMenu(p.smf, items, firstName(e.s) .. "  |cff777777" .. date("%H:%M", e.ts) .. "|r", 190)
end

function GC.HelpMenu(p, e)
    local kind, sub = askOf(e)
    local asker = ns.ChatName(e.s)
    local items = {}
    if kind == "group" then
        items[#items + 1] = { text = L["Einladen"], fn = function()
            if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, asker) elseif InviteUnit then pcall(InviteUnit, asker) end
        end }
    end
    items[#items + 1] = { text = L["Ich helfe (anfluestern)"], fn = function() ns.Whisper(e.s) end }
    if kind == "prof" then
        local n = 0
        for _, h in ipairs(profHolders(sub)) do
            if n >= 6 then break end
            if not ns.isMe(h.m.name) and who(h.m.name) ~= who(e.s) then
                n = n + 1
                items[#items + 1] = { text = (L["Vorschlagen: %s (%s %d)"]):format(ns.displayName(h.m.name), h.prof, h.r) .. (h.m.online and "  |cff66db9e*|r" or ""),
                    fn = function()
                        ns.SendChat(("@%s %s: %s (%s %d)"):format(firstName(e.s), L["frag mal"], ns.ChatName(h.m.name), h.prof, h.r), "GUILD")
                    end }
            end
        end
    end
    K.ShowMenu(p.smf, items, L["Hilfe anbieten"], 200)
end

-- Namens-Karte beim Hovern
function GC.NameTip(owner, name)
    local R = ns.Radar
    local m = R and R.byName and R.byName[name]
    if not m and R and R.roster then
        for _, x in ipairs(R.roster) do if who(x.name) == who(name) then m = x break end end
    end
    local full = m and m.name or name
    local cls = m and m.class
    local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    local cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
    local d = ns.Card and ns.Card.Of(full) or {}
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    -- Kopf: Name in Klassenfarbe + Vitrine, darunter Titel
    local badges = ns.Card and ns.Card.NameBadges(full, 14) or ""
    GameTooltip:SetText(ns.displayName(full) .. badges, cr, cg, cb)
    if d.t and d.t ~= "" then GameTooltip:AddLine(d.t, 0.91, 0.71, 0.29) end
    if m then
        local clsName = (LOCALIZED_CLASS_NAMES_MALE and cls and LOCALIZED_CLASS_NAMES_MALE[cls]) or ""
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["Level"], (m.level or "?") .. "  " .. clsName, 0.55, 0.55, 0.6, cr, cg, cb)
        if m.rank and m.rank ~= "" then GameTooltip:AddDoubleLine(L["Gildenrang"], m.rank, 0.55, 0.55, 0.6, 0.9, 0.9, 0.9) end
        if m.online then
            GameTooltip:AddDoubleLine(L["Online"], m.zone ~= "" and m.zone or "-", 0.4, 0.86, 0.62, 0.9, 0.9, 0.9)
        else
            GameTooltip:AddDoubleLine(L["Offline"], "", 0.5, 0.5, 0.5)
        end
        if ns.Profile and ns.Profile.RoleIcons then
            local ri = ns.Profile.RoleIcons(full, 14)
            if ri ~= "" then GameTooltip:AddDoubleLine(L["Rollen"], ri, 0.55, 0.55, 0.6) end
        end
        -- Berufe: je Zeile Name + Stufe (farbig nach Fortschritt)
        local pr = ns.db.members[m.name]
        local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
        local list = {}
        for part in tostring(raw or ""):gmatch("[^+]+") do
            local n, r = part:match("^([^/]+)/(%d+)")
            if n then list[#list + 1] = { n = n, r = tonumber(r) or 0 } end
        end
        if #list > 0 then
            table.sort(list, function(a, b) return a.r > b.r end)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(K.Upper(L["Berufe"]), 0.91, 0.71, 0.29)
            for _, x in ipairs(list) do
                local q = x.r >= 225 and { 0.64, 0.21, 0.93 } or x.r >= 150 and { 0, 0.44, 0.87 } or x.r >= 75 and { 0.12, 1, 0 } or { 0.8, 0.8, 0.8 }
                GameTooltip:AddDoubleLine("  " .. x.n, tostring(x.r), 0.85, 0.85, 0.85, q[1], q[2], q[3])
            end
        end
    end
    if d.s and d.s ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("\"" .. d.s .. "\"", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Klick: anfluestern  ·  Rechtsklick: Menue"], 0.45, 0.45, 0.5)
    GameTooltip:Show()
end

ns.Listen("STORE", function(coll)
    if coll == "reacts" then
        reactIdx = nil
        reactVer = reactVer + 1
        if GC.page and GC.page:IsVisible() then ns.RefreshPage("chat") end
    elseif coll == "chatpin" then
        if GC.page and GC.page:IsVisible() then GC.UpdatePin(GC.page) end
    end
end)
ns.Listen("SYNCED", function() reactIdx = nil reactVer = reactVer + 1 end)

------------------------------------------------------------------------
-- @Name-Vorschlaege auch im normalen Blizzard-Chat (Gildenmitglieder, online zuerst)
-- nur HookScript + SetText auf dem Eingabefeld, keine Attribute -> kein Taint
------------------------------------------------------------------------
do
    local ac
    local function build()
        ac = CreateFrame("Frame", "OasisMentionList", UIParent)
        ac:SetFrameStrata("TOOLTIP")
        ac:SetSize(210, 10)
        K.Fill(ac, { 0.05, 0.05, 0.06, 0.97 })
        K.Border(ac, C.accent2)
        ac.head = K.Text(ac, 10, C.dim)
        ac.head:SetPoint("TOPLEFT", 8, -5)
        ac.head:SetText(L["Gildenmitglied erwaehnen  ·  Tab / Klick"])
        ac.rows = {}
        for i = 1, 8 do
            local r = CreateFrame("Button", nil, ac)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 4, -20 - (i - 1) * 20)
            r:SetPoint("RIGHT", -4, 0)
            r.t = K.Text(r, 12, C.text)
            r.t:SetPoint("LEFT", 6, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnClick", function(self) GC.CompleteMention(ac.eb, self.name) end)
            ac.rows[i] = r
        end
        ac:Hide()
    end
    local function list(prefix)
        local out, seen = {}, {}
        prefix = prefix:lower()
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
            local cn = ns.ChatName(m.name)
            if cn ~= "" and not seen[cn] and not ns.isMe(m.name) and cn:lower():sub(1, #prefix) == prefix then
                seen[cn] = true
                out[#out + 1] = m
            end
        end
        table.sort(out, function(a, b)
            if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
            return (a.name or "") < (b.name or "")
        end)
        return out
    end
    function GC.CompleteMention(eb, name)
        if not (eb and name) then return end
        local t = eb:GetText() or ""
        eb:SetText((t:gsub("@[^@]*$", "@" .. ns.ChatName(name) .. " ")))
        eb:SetCursorPosition(#eb:GetText())
        eb:SetFocus()
        if ac then ac:Hide() end
    end
    local function update(eb, user)
        if ns.db and ns.db.settings.chatMentionSuggest == false then if ac then ac:Hide() end return end
        local pre = user and (eb:GetText() or ""):match("@([^@]*)$")
        if not pre then if ac and ac.eb == eb then ac:Hide() end return end
        local l = list(pre)
        if #l == 0 then if ac then ac:Hide() end return end
        if not ac then build() end
        ac.eb = eb
        for i, r in ipairs(ac.rows) do
            local m = l[i]
            r:SetShown(m ~= nil)
            if m then
                r.name = m.name
                local cc = RAID_CLASS_COLORS and m.class and RAID_CLASS_COLORS[m.class]
                r.t:SetText((cc and ("|c" .. cc.colorStr) or "") .. ns.displayName(m.name) .. (cc and "|r" or "")
                    .. "  |cff777777" .. (m.level or "") .. "|r" .. (m.online and "  |cff66db9e●|r" or ""))
            end
        end
        ac:SetHeight(24 + math.min(#l, 8) * 20)
        ac.first = l[1].name
        ac:ClearAllPoints()
        ac:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 4)
        ac:Show()
    end
    local hooked = {}
    local function hook(eb)
        if not eb or hooked[eb] then return end
        hooked[eb] = true
        eb:HookScript("OnTextChanged", function(self, user) pcall(update, self, user) end)
        eb:HookScript("OnTabPressed", function(self)
            if ac and ac:IsShown() and ac.eb == self and ac.first then GC.CompleteMention(self, ac.first) end
        end)
        eb:HookScript("OnEditFocusLost", function(self) C_Timer.After(0.2, function() if ac and ac.eb == self then ac:Hide() end end) end)
        eb:HookScript("OnHide", function(self) if ac and ac.eb == self then ac:Hide() end end)
    end
    ns.Listen("LOGIN", function()
        for i = 1, (NUM_CHAT_WINDOWS or 10) do hook(_G["ChatFrame" .. i .. "EditBox"]) end
    end)
end

ns.Listen("STORE", function(coll)
    if coll == "links" and GC.page and GC.page:IsVisible() then ns.RefreshPage("chat") end
end)

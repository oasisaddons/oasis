-- Oasis - Kommunikation zwischen den Addons (Gilde / Gruppe / Fluestern)
-- plus replizierte Sammlungen ("Store") mit Sync fuer spaeter eingeloggte Mitglieder
local ADDON, ns = ...
local L = ns.L

local PREFIX = "OASIS1"
-- mehrere Kuerzel: WoW drosselt je Kuerzel (~1 Nachricht/s) -> 3 Kuerzel = etwa dreifacher Durchsatz
local PREFIXES = { "OASIS1", "OASIS2", "OASIS3" }
local IS_PREFIX = {}
for _, p in ipairs(PREFIXES) do IS_PREFIX[p] = true end
local Comm = {}
ns.Comm = Comm

------------------------------------------------------------------------
-- Komprimierung mit WoWs eingebautem Packer (C_EncodingUtil), falls der Client ihn hat:
-- "~" + Base64(Deflate(payload)). Lohnt erst ab ~120 Zeichen; ist das Ergebnis nicht kuerzer, bleibt Klartext.
------------------------------------------------------------------------
local EU = C_EncodingUtil
local DEFLATE = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
local canZip = EU and EU.CompressString and EU.DecompressString and EU.EncodeBase64 and EU.DecodeBase64 and DEFLATE ~= nil
Comm.canZip = canZip and true or false
Comm.zipSaved = 0
local function zip(payload)
    if not canZip or #payload < 120 then return payload end
    local ok, z = pcall(EU.CompressString, payload, DEFLATE, Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize or nil)
    if not ok or not z then return payload end
    local ok2, b = pcall(EU.EncodeBase64, z)
    if not ok2 or not b or #b + 1 >= #payload or #b + 1 > ns.SyncRules.Limits.zip then return payload end
    Comm.zipSaved = Comm.zipSaved + (#payload - #b - 1)
    return "~" .. b
end
-- Obergrenze fuer entpackte Nachrichten (Schutz vor "Zip-Bomben" aus manipulierten Clients)
local UNZIP_MAX = 262144
local ZIP_IN_MAX = 24000   -- gepackte Nachricht schon vor dem Entpacken begrenzen (Zip-Bombe)
local function unzip(payload)
    if #payload > ns.SyncRules.Limits.message then return nil end
    if payload:sub(1, 1) ~= "~" then return payload end
    if not canZip then return nil end
    if #payload > ZIP_IN_MAX then return nil end
    local ok, z = pcall(EU.DecodeBase64, payload:sub(2))
    if not ok or type(z) ~= "string" then return nil end
    local ok2, out = pcall(EU.DecompressString, z, DEFLATE)
    if not ok2 or type(out) ~= "string" or #out > UNZIP_MAX then return nil end
    return out
end

------------------------------------------------------------------------
-- Kodierung: Felder mit ^ getrennt, Sonderzeichen als %XX
------------------------------------------------------------------------
local function esc(s)
    s = tostring(s == nil and "" or s)
    return (s:gsub("[%%%^\n|;=,:]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
Comm.esc, Comm.unesc = esc, unesc

-- Einheitliche Grenzen und atomare Datensaetze (keine still abgeschnittenen Felder).
local RULES, LIMITS = ns.SyncRules, ns.SyncRules.Limits
local REC_MAX_FIELDS, REC_MAX_KEY, REC_MAX_VAL = LIMITS.fields, LIMITS.key, LIMITS.value
Comm.REC_MAX_VAL = REC_MAX_VAL
local finite = RULES.Finite
Comm.finite = finite
Comm.encodeRecord = RULES.Encode
function Comm.decodeRecord(s)
    local rec, err = RULES.Decode(s)
    if not rec then Comm.badMsg = (Comm.badMsg or 0) + 1 ns.debug("Datensatz abgewiesen", err) end
    return rec
end

------------------------------------------------------------------------
-- Sende-Warteschlange mit Drossel (Blizzard erlaubt ca. 10 Nachrichten
-- am Stueck, danach ~1 pro Sekunde je Prefix)
------------------------------------------------------------------------
local queue = {}
local MAXTOK, REGEN = 8, 1.05
local tokens = {}
for _, p in ipairs(PREFIXES) do tokens[p] = MAXTOK end
local lastRegen = GetTime()
-- gemeinsame Bremse fuer alle Kuerzel: der Server begrenzt pro Spieler insgesamt
-- ("The number of messages ... is limited") - kurz bis 10 am Stueck, danach ca. 1,5 pro Sekunde
local G_MAX, G_REGEN = 10, 0.65
local gTok = G_MAX
local pausedUntil = 0
local msgCounter = 0
Comm.sent, Comm.received = 0, 0

-- Beide Sperr-Abfragen roh (fuer die Diagnose). Der Beta-Client meldet hier dauerhaft "gesperrt",
-- obwohl Senden klappt -> NICHT mehr davon abhaengig machen, sondern senden und den Rueckgabewert pruefen.
local function lockState()
    local a, b
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        a = ok and tostring(r) or "Fehler"
    end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
        local ok, r = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
        b = ok and tostring(r) or "Fehler"
    end
    return a or "-", b or "-"
end
Comm.lockState = lockState
local function restricted() return false end
Comm.restricted = restricted

local function channelOk(ch)
    if ch == "GUILD" or ch == "OFFICER" then return IsInGuild() end
    if ch == "RAID" then return IsInRaid() end
    if ch == "PARTY" then return IsInGroup() end
    if ch == "INSTANCE_CHAT" then return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    return true
end

local function pump()
    if #queue == 0 then return end   -- 0.5.722: nichts zu senden -> keine Marken-Rechnung (die naechste holt den Rest nach, gedeckelt)
    local now = GetTime()
    for p, t in pairs(tokens) do tokens[p] = math.min(MAXTOK, t + (now - lastRegen) / REGEN) end
    gTok = math.min(G_MAX, gTok + (now - lastRegen) / G_REGEN)
    lastRegen = now
    if now < pausedUntil or #queue == 0 then return end
    while #queue > 0 do
        -- Kuerzel mit den meisten freien Marken nehmen
        local pfx, best = nil, 0
        for _, p in ipairs(PREFIXES) do if tokens[p] > best then pfx, best = p, tokens[p] end end
        if not pfx or best < 1 or gTok < 1 then return end
        local m = table.remove(queue, 1)
        if channelOk(m.ch) then
            local ok, r = pcall(C_ChatInfo.SendAddonMessage, pfx, m.text, m.ch, m.target)
            Comm.lastResult = ok and tostring(r) or ("Fehler: " .. tostring(r))
            if not ok or (type(r) == "number" and r ~= 0) or r == false then
                -- gedrosselt oder abgelehnt: zurueck an den Anfang, kurz warten
                m.tries = (m.tries or 0) + 1
                if m.tries < 5 then table.insert(queue, 1, m) end
                tokens[pfx] = 0
                gTok = 0
                pausedUntil = now + 2
                ns.debug("Senden verzoegert", tostring(r))
                return
            end
            tokens[pfx] = tokens[pfx] - 1
            gTok = gTok - 1
            Comm.sent = Comm.sent + 1
        end
    end
end
C_Timer.NewTicker(0.25, function()
    local ok, e = pcall(pump)
    if not ok then ns.err("Comm", e) end
end)

-- Obergrenze: beantworten viele gleichzeitig Abgleich-Anfragen, waechst die Schlange sonst auf Tausende.
-- Dann fallen die aeltesten Sync-Pakete (UB) weg - der Empfaenger holt sie beim naechsten Abgleich nach.
local QUEUE_MAX = 1200
local function dropAt(i)
    local group = queue[i] and queue[i].group
    if not group then table.remove(queue, i) return end
    for j = #queue, 1, -1 do if queue[j].group == group then table.remove(queue, j) end end
end
local function trimQueue()
    if #queue <= QUEUE_MAX then return end
    local i = 1
    while #queue > QUEUE_MAX and i <= #queue do
        if queue[i].bulk then dropAt(i) else i = i + 1 end
    end
    while #queue > QUEUE_MAX * 1.5 do dropAt(#queue) end
    Comm.dropped = (Comm.dropped or 0) + 1
end
local function enqueue(ch, target, text, prio, key, bulk, group)
    if key then
        for i = 1, #queue do
            if queue[i].key == key then queue[i].text = text return end
        end
    end
    local m = { ch = ch, target = target, text = text, key = key, bulk = bulk, prio = prio, group = group }
    if prio then
        -- hinter die schon wartenden Prio-Nachrichten (Teile bleiben in Reihenfolge)
        local pos = 1
        while queue[pos] and queue[pos].prio do pos = pos + 1 end
        table.insert(queue, pos, m)
        -- eilige Nachricht: sofort senden statt auf den naechsten Takt (0,25 s) zu warten
        if not group then C_Timer.After(0, function() pcall(pump) end) end
    elseif bulk then
        queue[#queue + 1] = m
    else
        -- 0.5.788: normale (Live-)Nachrichten VOR die Abgleich-Pakete (bulk) - sonst warteten z.B. Online-/Aufstiegs-/Beute-Meldungen
        -- hinter bis zu 400 Sync-Paketen und kamen minutenlang verspaetet an. Reihenfolge: eilig > normal > Abgleich.
        local pos = #queue + 1
        for i = 1, #queue do
            if queue[i].bulk and not queue[i].prio then pos = i break end
        end
        table.insert(queue, pos, m)
    end
    if not group then trimQueue() end
end

-- Comm.Send("GUILD", nil, "TYP", feld1, feld2, ...) ; opts: Comm.SendEx
function Comm.SendEx(opts, msgType, ...)
    local ch, target = opts.ch, opts.target
    if not ch then return end
    local n = select("#", ...)
    local fields = { msgType }
    for i = 1, n do fields[#fields + 1] = esc((select(i, ...))) end
    local raw = table.concat(fields, "^")
    if #raw > LIMITS.message then
        ns.err("Comm", L["Nachricht zu gross - nicht gesendet."])
        return false
    end
    local payload = zip(raw)
    if #payload <= 245 then
        enqueue(ch, target, "!" .. payload, opts.prio, opts.key, opts.bulk)
    else
        msgCounter = (msgCounter + 1) % 1000
        local mid = ("%03d"):format(msgCounter)
        local size = LIMITS.chunk
        local group = {}
        local total = math.ceil(#payload / size)
        for i = 1, total do
            local chunk = payload:sub((i - 1) * size + 1, i * size)
            enqueue(ch, target, ("#%s:%d:%d:"):format(mid, i, total) .. chunk, opts.prio, nil, opts.bulk, group)
        end
        if opts.prio then C_Timer.After(0, function() pcall(pump) end) end
    end
    trimQueue()
    return true
end
function Comm.Send(ch, target, msgType, ...)
    Comm.SendEx({ ch = ch, target = target }, msgType, ...)
end
function Comm.Guild(msgType, ...)
    if IsInGuild() then Comm.SendEx({ ch = "GUILD", prio = Comm.URGENT and Comm.URGENT[msgType] }, msgType, ...) end
end
-- Fluester-Ziel: WoW Forever liefert Absender als "Vorname Nachname-Realm", fluestern geht aber
-- an den vollstaendigen Charakter, eigener Realm kann entfallen
function Comm.WhisperName(name)
    local full = ns.ResolveName(name)
    if not full then return name end
    local base, realm = full:match("^(.-)%-(.+)$")
    local ownRealm = ns.me() and ns.me():match("%-(.+)$")
    if realm and realm ~= ownRealm then return full end
    return base or full
end
-- WoW Forever stellt Addon-Fluestern nicht zu ("kein Spieler namens ..."), Gilden-Nachrichten aber schon.
-- Deshalb geht "Fluestern" ueber den Gildenkanal mit Empfaenger (vollstaendiger Name): W^empfaenger^typ^felder...
-- Nur der Empfaenger wertet aus; fuer die Handler sieht es aus wie eine normale Fluester-Nachricht.
local function whoKey(name) return ns.NameKey(name) end
Comm.whoKey = whoKey
-- wie Whisper, aber als verzichtbares Sync-Paket markiert (darf bei voller Schlange wegfallen)
function Comm.WhisperBulk(target, msgType, ...)
    if IsInGuild() then
        Comm.SendEx({ ch = "GUILD", bulk = true }, "W", whoKey(target), msgType, ...)
    else
        Comm.SendEx({ ch = "WHISPER", target = Comm.WhisperName(target), bulk = true }, msgType, ...)
    end
end
-- zeitkritische Nachrichten (Gruppen) vor alles andere in die Schlange
local URGENT = { JOIN = true, JOINNO = true, MERGE = true, MERGEOK = true, TYP = true, JOINCANCEL = true, GROLE = true,
    DRINV = true, DRACC = true, DRNO = true, DRBUSY = true, DRROLL = true, DRGIVEUP = true, DRCOMMIT = true, DRSEED = true,
    DRJOIN = true, DRFULL = true, DRQ = true, DRQX = true, DRLOOK = true }
Comm.URGENT = URGENT
-- Ziel in meiner Gruppe, aber nicht ueber die Gilde erreichbar? -> Gruppenkanal (Forever stellt Addon-Fluestern nicht zu)
local function viaGroup(target)
    local ch = ns.groupChannel and ns.groupChannel()
    if not ch or not target then return nil end
    if IsInGuild() then
        local A = ns.Admin
        if not (A and A.InGuildList) or A.InGuildList(target) == true then return nil end
    end
    local s = Comm.WhisperName(target)
    if (UnitInParty and UnitInParty(s)) or (UnitInRaid and UnitInRaid(s)) then return ch end
end
Comm.ViaGroup = viaGroup
function Comm.Whisper(target, msgType, ...)
    local gch = viaGroup(target)
    if gch then
        Comm.SendEx({ ch = gch, prio = URGENT[msgType] }, "W", whoKey(target), msgType, ...)
        return
    end
    -- 0.6.468: Ziel sicher nicht in der eigenen Gilde (z. B. Freund aus einer anderen Gilde) -> echtes Fluestern,
    -- ueber den Gildenkanal kaeme es nie an
    local A = ns.Admin
    local outside = A and A.InGuildList and A.InGuildList(target) == false
    if IsInGuild() and not outside then
        Comm.SendEx({ ch = "GUILD", prio = URGENT[msgType] }, "W", whoKey(target), msgType, ...)
    else
        -- 0.6.512: Forever stellt Addon-Fluestern nicht zu - gibt es einen gemeinsamen Kanal (Todeswuerfel-Netz),
        -- dort mit Empfaenger senden; nur der Empfaenger wertet aus
        local cid = Comm.DirectChannel and Comm.DirectChannel(msgType)
        if cid then
            Comm.SendEx({ ch = "CHANNEL", target = cid, prio = URGENT[msgType] }, "W", whoKey(target), msgType, ...)
        else
            Comm.Send("WHISPER", Comm.WhisperName(target), msgType, ...)
        end
    end
end
function Comm.Group(msgType, ...)
    local ch = ns.groupChannel()
    if ch then Comm.Send(ch, nil, msgType, ...) return true end
    return false
end
function Comm.QueueSize() return #queue end

------------------------------------------------------------------------
-- Empfang
------------------------------------------------------------------------
local handlers = {}
function Comm.On(msgType, fn)
    handlers[msgType] = handlers[msgType] or {}
    table.insert(handlers[msgType], fn)
end

local partial = {}
-- Grenzen fuer fremde Nachrichten
local MAX_FIELDS, MAX_FIELD_LEN = 600, LIMITS.wireField
Comm.badMsg, Comm.flood = 0, 0
-- Comm.rawChannel: echter WoW-Kanal der gerade ausgewerteten Nachricht (vor der "W"-Umdeutung auf WHISPER).
-- Handler koennen so pruefen, ob etwas wirklich ueber den Gildenkanal kam.
Comm.rawChannel = nil
local function dispatch(sender, channel, payload)
    payload = unzip(payload)
    if not payload then ns.debug("Nachricht nicht entpackbar", sender) Comm.badMsg = Comm.badMsg + 1 return end
    local fields = {}
    for f in (payload .. "^"):gmatch("([^%^]*)%^") do
        if #fields >= MAX_FIELDS then Comm.badMsg = Comm.badMsg + 1 return end
        -- fremde Texte entschaerfen (Itemlinks/Farben bleiben, |K/|A/Riesen-Texturen nicht)
        local value = unesc(f)
        if #value > MAX_FIELD_LEN then Comm.badMsg = Comm.badMsg + 1 return end
        fields[#fields + 1] = ns.CleanText(value)
    end
    local msgType = table.remove(fields, 1)
    if type(msgType) ~= "string" or msgType == "" or #msgType > 24 then return end
    local raw = channel
    if msgType == "W" then
        local to = table.remove(fields, 1)
        if not ns.SameName(to, ns.me()) and not ns.SameName(to, ns._meRoster) then return end
        msgType = table.remove(fields, 1)
        if type(msgType) ~= "string" or msgType == "W" then return end
        channel = "WHISPER"
    end
    local list = handlers[msgType]
    ns.debug("<-", msgType, ns.short(sender), channel)
    if not list then return end
    for i = 1, #list do
        Comm.rawChannel = raw
        local ok, e = pcall(list[i], sender, channel, unpack(fields))
        Comm.rawChannel = nil
        if not ok then ns.err(L["Comm "] .. tostring(msgType), e) end
    end
end
-- kam die gerade ausgewertete Nachricht von einem Gildenmitglied? (Gildenkanal = vom Server bestaetigt)
function Comm.FromGuild(sender)
    local raw = Comm.rawChannel
    if raw == "GUILD" or raw == "OFFICER" then return true end
    local A = ns.Admin
    if A and A.InGuildList then return A.InGuildList(sender) == true end
    return false
end

-- Drossel je Absender: manipulierte Clients koennen sonst mit Nachrichten fluten
-- (der Server bremst zwar auch, aber nicht ueber alle Kanaele/Kuerzel zusammen)
local RL_MAX, RL_REGEN = 120, 8   -- 120 am Stueck, danach 8 pro Sekunde
local rate = {}
local function allowFrom(sender)
    local now = GetTime()
    local b = rate[sender]
    if not b then b = { tok = RL_MAX, t = now } rate[sender] = b end
    b.tok = math.min(RL_MAX, b.tok + (now - b.t) * RL_REGEN)
    b.t = now
    if b.tok < 1 then Comm.flood = Comm.flood + 1 return false end
    b.tok = b.tok - 1
    return true
end
local PART_MAX_TOTAL, PART_MAX_PER_SENDER = math.ceil(LIMITS.message / LIMITS.chunk), 4

-- Eingangs-Zaehler (Diagnose): wo gehen Nachrichten verloren?
Comm.inRaw, Comm.inOasis, Comm.inSecret, Comm.inSelf, Comm.lastFrom = 0, 0, 0, 0, nil
local rawFrame = CreateFrame("Frame")
rawFrame:RegisterEvent("CHAT_MSG_ADDON")
rawFrame:SetScript("OnEvent", function(_, _, prefix, _, _, sender)
    Comm.inRaw = Comm.inRaw + 1
    if IS_PREFIX[ns.safe(prefix) or ""] then
        Comm.inOasis = Comm.inOasis + 1
        Comm.lastFrom = tostring(ns.safe(sender) or "(geheim)")
        -- rohe Absendernamen merken (nur Sitzung): /oa probe wer <Name> zeigt, ob und unter welchem Namen jemand ankommt
        local rs = ns.safe(sender)
        if type(rs) == "string" and #rs <= 80 then
            Comm.rawSeen = Comm.rawSeen or {}
            local e = Comm.rawSeen[rs]
            if not e then
                Comm.rawSeenN = (Comm.rawSeenN or 0) + 1
                if Comm.rawSeenN > 400 then Comm.rawSeen, Comm.rawSeenN = {}, 1 end
                e = { n = 0 }
                Comm.rawSeen[rs] = e
            end
            e.n, e.t = e.n + 1, GetTime()
        end
    end
end)
ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if not IS_PREFIX[ns.safe(prefix) or ""] then return end
    text, channel, sender = ns.safe(text), ns.safe(channel), ns.safe(sender)
    if not text or not sender then Comm.inSecret = Comm.inSecret + 1 return end
    if type(text) ~= "string" or type(sender) ~= "string" or #sender > 80 then return end
    -- Absender auf den Namen aus der Gildenliste bringen (Forever: der Realm-Anhang weicht je nach Client ab,
    -- sonst liegt das Profil unter "...-ClassicBetaPvE2", die Liste sucht aber "...-ClassicBetaPvE")
    sender = (ns.ResolveName and ns.ResolveName(sender, channel == "GUILD" or channel == "OFFICER")) or ns.fullName(sender)
    if not sender or ns.isMe(sender) then Comm.inSelf = Comm.inSelf + 1 return end
    if not allowFrom(sender) then return end
    Comm.received = Comm.received + 1
    ns.Fire("OASIS_SEEN", sender)
    local kind = text:sub(1, 1)
    if kind == "!" then
        dispatch(sender, channel, text:sub(2))
    elseif kind == "#" then
        local mid, i, total, chunk = text:match("^#(%d%d?%d?):(%d+):(%d+):(.*)$")
        if not mid then return end
        i, total = tonumber(i), tonumber(total)
        if not i or not total or total < 1 or total > PART_MAX_TOTAL or i < 1 or i > total then Comm.badMsg = Comm.badMsg + 1 return end
        local key = sender .. "\001" .. mid
        local p = partial[key]
        if p and (p.total ~= total or p.channel ~= channel) then partial[key] = nil Comm.badMsg = Comm.badMsg + 1 return end
        if not p then
            -- je Absender nur wenige offene Teilnachrichten gleichzeitig (Speicher)
            if not p then
                local open = 0
                for _, q in pairs(partial) do if q.sender == sender then open = open + 1 end end
                if open >= PART_MAX_PER_SENDER then Comm.badMsg = Comm.badMsg + 1 return end
            end
            p = { total = total, got = 0, parts = {}, bytes = 0, t = GetTime(), start = GetTime(), sender = sender, channel = channel }
            partial[key] = p
        end
        if #chunk > LIMITS.chunk or (p.parts[i] and p.parts[i] ~= chunk) then partial[key] = nil Comm.badMsg = Comm.badMsg + 1 return end
        p.t = GetTime()
        if not p.parts[i] then
            p.bytes = p.bytes + #chunk
            if p.bytes > LIMITS.message then partial[key] = nil Comm.badMsg = Comm.badMsg + 1 return end
            p.parts[i] = chunk
            p.got = p.got + 1
        end
        if p.got == p.total then
            partial[key] = nil
            dispatch(sender, channel, table.concat(p.parts))
        end
    end
end)
-- verwaiste Teilnachrichten aufraeumen
C_Timer.NewTicker(60, function()
    local now = GetTime()
    for k, p in pairs(partial) do
        if now - p.t > 120 or now - p.start > 1800 then partial[k] = nil end
    end
    -- volle Drossel-Eimer brauchen keinen Eintrag mehr
    for k, b in pairs(rate) do
        if now - b.t > 60 then rate[k] = nil end
    end
end)

local function registerPrefix()
    if C_ChatInfo.RegisterAddonMessagePrefix then
        for _, p in ipairs(PREFIXES) do
            local ok, r = pcall(C_ChatInfo.RegisterAddonMessagePrefix, p)
            if p == PREFIX then Comm.prefixResult = ok and tostring(r) or ("Fehler: " .. tostring(r)) end
        end
    end
    Comm.prefixOk = C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
end
-- schon beim Laden anmelden (nicht erst beim Login), damit keine fruehen Nachrichten verloren gehen
registerPrefix()
ns.On("PLAYER_LOGIN", registerPrefix)

-- /oa ping: alle mit Oasis antworten per Fluestern -> zeigt, ob Nachrichten hin und zurueck kommen
-- PING/PONG gebremst: sonst kann ein manipulierter Client per Dauer-PING Chat-Zeilen und Antworten erzwingen
local pingAt, pingAny, pongAny = {}, 0, 0
Comm.On("PING", function(sender, channel, t)
    local now = GetTime()
    if now - (pingAt[sender] or -999) < 30 or now - pingAny < 2 then return end
    pingAt[sender], pingAny = now, now
    ns.print(("PING von %s empfangen (%s) - antworte ..."):format(ns.short(sender), tostring(channel)))
    Comm.Whisper(sender, "PONG", tostring(t or ""):sub(1, 20), ns.version)
end)
Comm.On("PONG", function(sender, _, t, ver)
    local now = GetTime()
    if now - pongAny < 0.2 then return end
    pongAny = now
    local ms = tonumber(t) and math.floor((now - tonumber(t)) * 1000) or nil
    if ms and (ms < 0 or ms > 600000) then ms = nil end
    ns.print(("PONG von %s  (v%s%s)"):format(ns.short(sender), tostring(ver or "?"):sub(1, 16), ms and (", " .. ms .. " ms") or ""))
end)
function Comm.Diag()
    return {
        ("Prefix %s angemeldet: %s (%s)"):format(PREFIX, tostring(Comm.prefixOk), tostring(Comm.prefixResult)),
        ("Gesendet: %d  ·  Empfangen: %d  ·  Warteschlange: %d"):format(Comm.sent, Comm.received, #queue),
        ("Letztes Senden: %s"):format(tostring(Comm.lastResult or "-")),
        ("Sperr-Abfragen (nur Info): Lockdown=%s  AddonRestricted=%s"):format(lockState()),
        ("In Gilde: %s"):format(tostring(IsInGuild())),
        ("Komprimierung: %s  ·  gespart: %d Zeichen"):format(canZip and "an" or "nicht verfuegbar", Comm.zipSaved),
        ("Profile empfangen: %d  ·  unvollstaendige Teilnachrichten: %d"):format(Comm.hellos or 0, (function() local n = 0 for _ in pairs(partial) do n = n + 1 end return n end)()),
        ("Eingang: alle Addons %d  ·  Oasis %d  ·  geheim %d  ·  als 'ich' verworfen %d"):format(Comm.inRaw, Comm.inOasis, Comm.inSecret, Comm.inSelf),
        ("Zuletzt von: %s  ·  ich bin: %s / %s"):format(tostring(Comm.lastFrom), tostring(ns.me()), tostring(ns._meRoster)),
        ("Schutz: gedrosselt %d  ·  kaputt/zu gross %d  ·  verworfen %d (Zukunft %d, Grenze %d)"):format(Comm.flood or 0, Comm.badMsg or 0,
            ns.Store and ns.Store.rejected or 0, ns.Store and ns.Store.future or 0, ns.Store and ns.Store.capped or 0),
    }
end
ns.slash.ping = function(target)
    if target and target ~= "" then
        Comm.Whisper(target, "PING", tostring(GetTime()))
        ns.print("PING per Fluestern an " .. target .. " gesendet.")
    else
        Comm.Guild("PING", tostring(GetTime()))
        ns.print("PING an die Gilde gesendet - wer Oasis hat, antwortet gleich.")
    end
    for _, l in ipairs(Comm.Diag()) do ns.print("  " .. l) end
end

------------------------------------------------------------------------
-- Store: replizierte Sammlungen
-- Jeder Datensatz: id, u (geaendert), by (Autor), del (geloescht)
------------------------------------------------------------------------
local Store = {}
ns.Store = Store
local RETENTION = {
    orders = 21 * 86400,
    events = 3 * 86400,     -- ab Terminende
    signups = 30 * 86400,
    chronicle = 45 * 86400,
    loot = 45 * 86400,
    campCatalog = 365 * 86400,
    campfires = 3600,
    wants = 60 * 86400,
    rep = 365 * 86400,
    flights = 365 * 86400,
    mapcal = 365 * 86400,   -- Abgleich Dungeonkarte <-> Spielposition (von Spielern gesetzt, fuer alle)  -- gelernte Flugzeiten (Strecke -> Sekunden), mit der Gilde geteilt      -- Erfahrungen mit Mitspielern (gut/schlecht + Notiz), mit der Gilde geteilt
    lfg = 3 * 3600,
    dgjoin = 4 * 3600,   -- 0.6.304: Mitkommen-Liste je Dungeon (Dungeons > Gilde & Gruppe)
    duels = 400 * 86400,   -- Deathroll: Saisons brauchen den Vormonat komplett
    polls = 30 * 86400,
    votes = 30 * 86400,
    avotes = 30 * 86400,       -- 0.5.617: geheime Umfragen - Stimmen ohne Namen (nur zufaelliges Kennzeichen)
    deaths = 90 * 86400,       -- 0.5.617: Sterbeorte 90 Tage statt 1 Jahr
    wtrain = 3650 * 86400,
    rpreq = 3650 * 86400,      -- Raid-Vorbereitung: Anforderungen je Raid (von der Raidleitung festgelegt)     -- Waffenmeister: was sie in WoW Forever wirklich lehren (beim Besuch gelesen)
    bank = 60 * 86400,
    banklog = 60 * 86400,
    prices = 30 * 86400,
    bankworth = 120 * 86400,   -- Wert der Gildenbank je Tag
    posts = 120 * 86400,       -- Oasigram
    likes = 120 * 86400,
    comments = 120 * 86400,
    follows = 3650 * 86400,
    points = 365 * 86400,
    raidplan = 14 * 86400,
    guildcfg = 3650 * 86400,   -- Einstellungen der Gildenleitung
    notices = 14 * 86400,      -- Durchsagen
    invites = 3650 * 86400,    -- wer schon einen Oasis-Hinweis per Fluestern bekommen hat
    reacts = 14 * 86400,       -- Gildenchat: Reaktionen
    links = 30 * 86400,        -- Gildenchat: zuletzt verlinkte Items (geteilt)
    lfgreq = 3600,             -- Gruppen: Anfragen (Sicherung zum Fluestern)
    chatpin = 30 * 86400,      -- Gildenchat: angepinnte Nachricht
    attend = 120 * 86400,      -- Raid-Anwesenheit (je Raidtag und Instanz)
    formers = 365 * 86400,     -- 0.5.617: Ehemalige 1 Jahr statt 10
    lvotes = 90 * 86400,       -- 0.6.526: Abstimmungen der Leitung (nur Offizierskanal)
    lballots = 90 * 86400,
    tactics = 3650 * 86400,
    markers = 8 * 86400,       -- Kartenmarker der Gilde (MapExtras; laufen selbst frueher ab)
    nodes = 365 * 86400,      -- Gilden-Sammelkarte (GatherMap)    -- Boss-Taktiken (RaidCheck)    -- Ehemalige (GuildHistory)
    audit = 180 * 86400,       -- Gildenprotokoll: Befoerdern, Degradieren, Kicks, Beitritte
    bans = 3650 * 86400,       -- Bannliste der Gildenleitung
    sndmute = 3650 * 86400,    -- Sound-Sperren der Gildenleitung (gehen an alle: jeder Client blendet Sounds der Gesperrten aus)
    recruits = 365 * 86400,    -- Bewerber und Probezeit
    sres = 30 * 86400,         -- Soft-Reserve je Raidtermin
    trace = 365 * 86400,
    raidint = 21 * 86400,      -- Raid-Interesse (Rollen + Tage)
    bugs = 90 * 86400,         -- Fehlerberichte + Bug-Meldungen (nur der Entwickler sieht sie)
    ggoals = 3650 * 86400,     -- Gildenziele (GuildGoals.lua)
    ggcontrib = 3650 * 86400,  -- Beitraege zu Gildenzielen
    board = 60 * 86400,        -- Schwarzes Brett (GuildGoals.lua, 0.6.450)
    gcard = 3650 * 86400,      -- Steckbriefe (Community.lua, 0.6.469)
    mentor = 365 * 86400,      -- Paten fuer Neulinge
    thanks = 60 * 86400,       -- Danke
    talents = 120 * 86400,     -- Talent-Export je Charakter (Talents.lua)
    scout = 120 * 86400,       -- Anwerbe-Vorschlaege (Scout.lua)
    perf = 30 * 86400,         -- Leistungs-Messung je Mitglied (PerfShare.lua)
    combat = 365 * 86400,      -- Kampf-Rekorde je Spieler (CombatBoard.lua)
    profcd = 14 * 86400,       -- Berufs-Abklingzeiten (Transmutation, Mondstoff ...)       -- selbst erkundete Dungeon-Karten (Laufwege + Bosse)
}

-- 0.5.617 Datenschutz: Leitungs-Sammlungen (Protokoll, Ehemalige, Bannliste, Bewerber, Bank-Protokoll) gehen nur
-- ueber den Offizierskanal, werden nur von Offizieren angenommen und bei allen anderen geloescht
local OFFICER_ONLY = { audit = true, formers = true, bans = true, recruits = true, banklog = true, lvotes = true, lballots = true }   -- 0.6.526: Abstimmungen der Leitung
Store.OFFICER_ONLY = OFFICER_ONLY
local function amOfficer() return ns.isOfficer() and true or false end
local function isOfficerName(name)
    local r = ns.Admin and ns.Admin.RoleOf and ns.Admin.RoleOf(name)
    return r == "officer" or r == "lead"
end

local function coll(name)
    ns.db.store[name] = ns.db.store[name] or {}
    return ns.db.store[name]
end
Store.coll = coll

function Store.Get(name, id) return coll(name)[id] end

-- alle nicht geloeschten Datensaetze, optional gefiltert
-- Gildenname des aktuellen Charakters: Oasis speichert pro ACCOUNT - Twinks ohne/mit anderer Gilde teilen
-- dieselbe Datei. Datensaetze tragen daher den Gildennamen (gn); fremde werden weder gezeigt noch verteilt (08.10.).
local function myGuild()
    local g = IsInGuild() and ns.safe((GetGuildInfo("player"))) or nil
    return g
end
Store.MyGuild = myGuild
local function ownGuild(r)
    if not r.gn then return true end      -- alte Datensaetze ohne Kennzeichen: wie bisher
    local g = myGuild()
    return RULES.CanReadGuild(r, g)      -- unbekannte Gilde: markierte fremde Daten nicht anzeigen
end
Store.OwnGuild = ownGuild
function Store.List(name, filter)
    local out = {}
    for _, r in pairs(coll(name)) do
        if not r.del and ownGuild(r) and (not filter or filter(r)) then out[#out + 1] = r end
    end
    return out
end

------------------------------------------------------------------------
-- Urheber-Pruefung beim Empfang (Regeln je Sammlung: ns.Admin.AUTH, Rechte: ns.Admin.MayAuthor)
-- actor = wer die Aenderung gemacht hat: bei "U" der Absender selbst, beim Abgleich ("UB",
-- weitergereicht) das Feld mb (zuletzt geaendert von) bzw. by (Ersteller).
-- Unbekannt (Gildenliste noch nicht geladen) -> zurueckstellen und bei ROSTER erneut pruefen.
------------------------------------------------------------------------
local held, heldN = {}, 0
Store.rejected = 0
local function sameName(a, b)
    if ns.Admin and ns.Admin.SameName then return ns.Admin.SameName(a, b) end
    return a == b
end
local function isDemoRec(rec) return rec.demo or tostring(rec.id or ""):find("demo-", 1, true) ~= nil end
-- true | false | nil (zurueckstellen)
local function authorize(name, rec, actor)
    local A = ns.Admin
    local g = A and A.AUTH and A.AUTH[name]
    if not g then return true end
    if isDemoRec(rec) or rec.sim then return false end   -- Demo-/Sim-Daten werden nie verschickt
    if not actor or actor == "" then return false end
    local ok, r = pcall(g, rec, actor, coll(name)[rec.id])
    if not ok then ns.debug("Urheber-Pruefung", name, r) return false end
    return r
end
Store.Authorize = authorize
function Store.HeldCount() return heldN end

------------------------------------------------------------------------
-- Haertung beim Empfang (Bedrohung: manipulierte Clients in Gilde/Gruppe/Fluestern)
--  * Zeitstempel u hoechstens FUTURE_SLACK in der Zukunft (sonst "ewiger Sieg" ueber jede spaetere Aenderung)
--  * Weitergereichte Datensaetze (UB) tragen ein unpruefbares mb/by. Fuer Leitungsdaten (STRICT_RELAY)
--    muss deshalb auch der WEITERREICHENDE mindestens Offizier sein - sonst koennte jedes Mitglied
--    Gildeneinstellungen/Ernennungen/Durchsagen "im Namen des Gildenmeisters" einschleusen.
--  * OWNED: persoenliche Sammlungen - fremde Datensaetze aendern/loeschen nur der Autor (oder Offiziere),
--    der Autor (by) eines vorhandenen Datensatzes ist unveraenderlich.
--  * Mengen: hoechstens COLL_MAX Datensaetze je Sammlung und AUTHOR_MAX je Autor (Speicher/SavedVariables).
------------------------------------------------------------------------
local FUTURE_SLACK = 900
local MAX_ID = 160
local COLL_MAX, AUTHOR_MAX = 8000, 800
local DAY_NEW, newToday = 300, {}   -- Flut-Bremse fuer die Speicherdatei
Store.FUTURE_SLACK = FUTURE_SLACK
-- Sammlung -> Recht, das der WEITERREICHENDE selbst haben muss (Raidleiter-Daten: ab Schlachtzugs-Assistenz).
-- Damit beim Abgleich die Berechtigten zuerst antworten, warten Mitglieder ohne Rechte laenger (SYNCREQ).
-- 0.5.643: Umfragen nicht mehr - sonst kam eine Umfrage nie an, wenn der Ersteller offline war und nur Mitglieder
-- sie hatten. Der Ersteller wird weiter geprueft (AUTH polls), Aendern/Loeschen fremder Saetze bleibt Offizieren vorbehalten.
local STRICT_RELAY = { guildcfg = "officer", notices = "officer", bans = "officer", points = "officer", sndmute = "officer",
    recruits = "officer", events = "raid.plan.sort", raidplan = "raid.plan.sort", tactics = "raid.plan.sort" }
local function mayRelay(name, feature)
    local A = ns.Admin
    if not (A and A.MayAuthor) then return false end
    local ok, r = pcall(A.MayAuthor, name, feature)
    if not ok then return false end
    return r
end
local OWNED = { posts = true, comments = true, likes = true, follows = true, rep = true, deaths = true,
    profcd = true, trace = true, lfgreq = true, orders = true, dgjoin = true, lvotes = true, lballots = true }
-- Weitergereichte Datensaetze (Abgleich): wer nicht selbst Autor ist, darf nur NEUE, unkritische Saetze
-- weitergeben. Aendern/Loeschen fremder Saetze und alles hier drin nur durch Offiziere (oder den Autor selbst).
-- (nur Bank/Raenge: alles andere MUSS weitergereicht werden duerfen, sonst bekommen Offline-Mitglieder
--  Deathroll-Ergebnisse, Anmeldungen, Stimmen, Beute usw. nie - die Urheber-Pruefung (AUTH) laeuft trotzdem)
local RELAY_SENSITIVE = { bank = true, banklog = true, bankworth = true, rank = true }
Store.STRICT_RELAY, Store.OWNED = STRICT_RELAY, OWNED
Store.future, Store.capped = 0, 0
local curNet, curRelay = false, false   -- Kontext des gerade geprueften Datensatzes (fuer den Verdachts-Monitor)
Store.rejectWhy = {}   -- Sammlung + Grund -> Anzahl (fuer /oa abgleich)
local function reject(why, name, rec, actor)
    Store.rejected = Store.rejected + 1
    local wk = tostring(name) .. ": " .. tostring(why)
    Store.rejectWhy[wk] = (Store.rejectWhy[wk] or 0) + 1
    -- nur direkt gesendete Datensaetze zaehlen: Weitergereichtes (Abgleich) stammt nicht vom Absender selbst
    if curNet and not curRelay and actor and ns.Suspect and ns.Suspect.Note then
        pcall(ns.Suspect.Note, actor, why, name)
    end
    ns.debug("verworfen (" .. why .. ")", name, rec and rec.id, actor)
    return false
end
local function isOfficer(name)
    local A = ns.Admin
    if not (A and A.MayAuthor) then return false end
    local ok, r = pcall(A.MayAuthor, name, "officer")
    if not ok then return false end
    return r
end
-- Zaehler je Sammlung (Gesamt + je Autor), bei Bedarf aufgebaut, bei prune verworfen
local counts = {}
local function countsOf(name)
    local c = counts[name]
    if c then return c end
    c = { total = 0, by = {} }
    for _, r in pairs(coll(name)) do
        c.total = c.total + 1
        local k = whoKey(type(r) == "table" and type(r.by) == "string" and r.by or "")
        c.by[k] = (c.by[k] or 0) + 1
    end
    counts[name] = c
    return c
end
-- zurueckgestellte Datensaetze je Sammlung (fuer /oa abgleich)
function Store.HeldByColl()
    local out = {}
    for _, h in pairs(held) do out[h.name] = (out[h.name] or 0) + 1 end
    return out
end
local function holdRec(name, rec, sender, relay)
    local key = name .. "|" .. tostring(rec.id)
    local h = held[key]
    if not h then heldN = heldN + 1 end
    if not h or RULES.Compare(rec, h.rec) > 0 then
        held[key] = { name = name, rec = rec, sender = sender, relay = relay, t = h and h.t or GetTime() }
    end
    if heldN > 3000 then held, heldN = {}, 0 end
    return false
end

-- lokal uebernehmen, wenn neuer
local function merge(name, rec, fromNet, actor, relay)
    if type(rec) ~= "table" then return false end
    if fromNet and rec.gn and myGuild and myGuild() and rec.gn ~= myGuild() then return false end
    local id = rec.id
    if (type(id) ~= "string" and type(id) ~= "number") or id == "" then return false end
    curNet, curRelay = fromNet and true or false, relay and true or false
    -- Absender, die gerade massenhaft gefaelschte Daten schicken, eine Weile ganz ignorieren
    if fromNet and actor and ns.Suspect and ns.Suspect.Ignored and ns.Suspect.Ignored(actor) then return false end
    if fromNet then
        -- Grundpruefung fremder Daten: Typen, Laengen, Zeitstempel
        if #tostring(id) > MAX_ID then return reject("id zu lang", name, rec, actor) end
        if rec.u ~= nil and not finite(rec.u) then return reject("u kein Zahlwert", name, rec, actor) end
        if (rec.u or 0) > ns.now() + FUTURE_SLACK then
            Store.future = Store.future + 1
            return reject("Zeitstempel in der Zukunft", name, rec, actor)
        end
        if rec.by ~= nil and type(rec.by) ~= "string" then return reject("by", name, rec, actor) end
        if rec.mb ~= nil and type(rec.mb) ~= "string" then return reject("mb", name, rec, actor) end
        if rec.rv ~= nil and (type(rec.rv) ~= "string" or #rec.rv > 160 or rec.rv:find("[%c|]")) then return reject("rv", name, rec, actor) end
        for k, v in pairs(rec) do
            if type(k) ~= "string" then rec[k] = nil
            elseif type(v) == "string" then rec[k] = ns.CleanText(v, REC_MAX_VAL)
            elseif type(v) == "number" and not finite(v) then rec[k] = nil
            elseif type(v) == "table" or type(v) == "function" or type(v) == "userdata" then rec[k] = nil end
        end
    end
    if fromNet and actor ~= nil then
        local sender = actor
        if not relay then
            -- Faelschung: "zuletzt geaendert von" passt nicht zum Absender
            if rec.mb and rec.mb ~= "" and not sameName(rec.mb, actor) then return reject("mb~=Absender", name, rec, actor) end
            -- fehlendes mb (aeltere Clients) mit dem echten Absender fuellen - sonst koennte ein spaeteres
            -- Weiterreichen den Ersteller (by) als Urheber ausgeben
            if not rec.mb or rec.mb == "" then rec.mb = actor end
        else
            actor = (rec.mb ~= nil and rec.mb ~= "") and rec.mb or rec.by
            if name == "avotes" then actor = sender end
        end
        local cur = coll(name)[id]
        if relay then
            -- Gildeneinstellungen gibt nur ihr Besitzer selbst weiter (sonst koennten Offiziere die Gildenleitung faelschen)
            if name == "guildcfg" and not (rec.by and sameName(rec.by, sender)) then
                return reject("guildcfg nur vom Besitzer", name, rec, sender)
            end
            -- angeblicher Autor ist nicht der Weiterreichende: nur Offiziere duerfen fremde Saetze aendern,
            -- loeschen oder kritische Sammlungen weitergeben
            -- vorhandener Satz: Weiterreichen einer neueren Fassung ok, solange der Ersteller (by) gleich bleibt
            local authorSwap = cur and cur.by and rec.by and not sameName(cur.by, rec.by)
            if actor and actor ~= "" and not sameName(actor, sender) and (authorSwap or rec.del or RELAY_SENSITIVE[name]) then
                local off = isOfficer(sender)
                if off == nil then return holdRec(name, rec, sender, relay) end
                if not off then return reject("fremder Satz weitergereicht", name, rec, sender) end
            end
        end
        if cur and (cur.u or 0) > (rec.u or 0) then return false end
        -- Leitungsdaten nur von Offizieren weiterreichen lassen
        if relay and STRICT_RELAY[name] then
            local okR = mayRelay(sender, STRICT_RELAY[name])
            if okR == nil then return holdRec(name, rec, sender, relay) end
            if not okR then return reject("Weiterreichen von Leitungsdaten ohne Rechte", name, rec, sender) end
        end
        -- persoenliche Datensaetze: nur der Autor (oder Offiziere)
        if OWNED[name] then
            local owner = (cur and cur.by) or rec.by
            local mine = actor and actor ~= "" and owner and owner ~= "" and sameName(owner, actor)
            if mine and cur and cur.by and rec.by and not sameName(cur.by, rec.by) then mine = false end
            if not mine then
                local off = isOfficer(actor)
                if off == nil then return holdRec(name, rec, sender, relay) end
                if not off then return reject("fremder Datensatz", name, rec, actor) end
            end
        end
        local ok = authorize(name, rec, actor)
        if ok == nil then return holdRec(name, rec, sender, relay)
        elseif not ok then return reject("keine Rechte", name, rec, actor) end
        -- Mengen-Grenzen nur fuer NEUE Datensaetze
        if not cur then
            local cnt = countsOf(name)
            -- zusaetzlich: je Autor und Sammlung hoechstens DAY_NEW frisch erstellte Datensaetze (letzte 24 h)
            -- (aeltere Saetze aus dem Abgleich zaehlen nicht, sonst bremst der erste Login-Abgleich)
            local fresh = (tonumber(rec.u) or 0) > ns.now() - 86400
            local dk = name .. "|" .. whoKey(rec.by or actor or "")
            if fresh then newToday[dk] = (newToday[dk] or 0) + 1 end
            if fresh and newToday[dk] > DAY_NEW and isOfficer(rec.by or actor) == false then
                Store.capped = Store.capped + 1
                return reject("Tages-Grenze", name, rec, actor)
            end
            if cnt.total >= COLL_MAX or (cnt.by[whoKey(rec.by or actor or "")] or 0) >= AUTHOR_MAX
                or (cnt.by[whoKey(sender or "")] or 0) >= AUTHOR_MAX then
                Store.capped = Store.capped + 1
                return reject("Mengen-Grenze", name, rec, actor)
            end
        end
    end
    local c = coll(name)
    local old = c[id]
    -- Fuer den Vergleich denselben anonymisierten Inhalt verwenden wie im Speicher.
    if name == "avotes" then rec.by, rec.mb = nil, nil end
    if old and old ~= rec and RULES.Compare(rec, old) <= 0 then return false end
    -- geheime Stimmen: nie einen Namen mitspeichern
    if name == "avotes" then rec.by, rec.mb = nil, nil end
    c[id] = rec
    if not old and counts[name] then
        local cnt = counts[name]
        cnt.total = cnt.total + 1
        local k = whoKey(type(rec.by) == "string" and rec.by or "")
        cnt.by[k] = (cnt.by[k] or 0) + 1
    end
    ns.Fire("STORE", name, rec, old)
    return true
end
Store.merge = merge

-- zurueckgestellte Datensaetze erneut pruefen (Gildenliste/Leitungs-Einstellungen geladen)
local recheckDue = false
function Store.Recheck()
    recheckDue = false
    local now = GetTime()
    -- erst einsammeln, dann pruefen (merge darf dabei wieder zurueckstellen)
    local list = {}
    for key, h in pairs(held) do list[#list + 1] = h held[key] = nil end
    heldN = 0
    for _, h in ipairs(list) do
        if now - h.t <= 1800 then
            merge(h.name, h.rec, true, h.sender, h.relay)
            -- weiterhin unbekannt -> urspruengliche Wartezeit behalten
            local k = h.name .. "|" .. tostring(h.rec.id)
            if held[k] then held[k].t = h.t end
        end
    end
end
local function recheckSoon()
    if recheckDue or heldN == 0 then return end
    recheckDue = true
    ns.After(0.5, function() pcall(Store.Recheck) end)
end
ns.Listen("ROSTER", recheckSoon)
ns.Listen("STORE", function(name) if name == "guildcfg" then recheckSoon() end end)

-- anlegen/aendern und an die Gilde senden
function Store.Put(name, rec)
    -- ohne Gilde keine Gilden-Daten (sonst verteilt sie spaeter ein Twink derselben Account-Datei an seine Gilde)
    if not IsInGuild() then return rec end
    if OFFICER_ONLY[name] and not amOfficer() then return rec end
    rec.gn = rec.gn or myGuild()
    local previous = coll(name)[rec.id]
    rec.u = math.max(ns.now(), (rec.u or 0) + 1, ((previous and previous.u) or 0) + 1)
    ns.db.meta.revSeq = (ns.db.meta.revSeq or 0) + 1
    -- Auch anonyme Stimmen erhalten eine Revision ohne Charaktername.
    rec.rv = ("%08x%08x:%d"):format(math.random(0, 2147483646), math.random(0, 2147483646), ns.db.meta.revSeq)
    rec.by = rec.by or ns.me()
    rec.mb = ns.me()   -- zuletzt geaendert von (Urheber-Pruefung beim Empfang)
    if name == "avotes" then rec.by, rec.mb = nil, nil end
    merge(name, rec)
    -- Demo-Daten (/oa demo) bleiben lokal
    if rec.demo or tostring(rec.id):find("demo-", 1, true) then return rec end
    -- Gruppen/Anfragen/Pins sofort senden, nicht hinter Sync-Paketen warten
    -- 0.5.708: auch Tode - sonst warteten sie hinter Sync-Paketen (bis zu Minuten) und der Hinweis kam viel zu spaet
    local fast = name == "lfg" or name == "dgjoin" or name == "lfgreq" or name == "chatpin" or name == "reacts" or name == "deaths" or name == "chronicle"
    if IsInGuild() then Comm.SendEx({ ch = OFFICER_ONLY[name] and "OFFICER" or "GUILD", prio = fast }, "U", name, Comm.encodeRecord(rec)) end
    return rec
end
function Store.Delete(name, id)
    local r = coll(name)[id]
    if not r then return end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.del = true
    Store.Put(name, copy)
end

-- Gilden-Sammlungen nur von Gildenmitgliedern (Gildenkanal oder Absender in der Gildenliste),
-- nie von Fremden per echtem Fluestern/Gruppe/Schlachtzug
Comm.On("U", function(sender, channel, name, recStr)
    if type(name) ~= "string" or not RETENTION[name] or type(recStr) ~= "string" then return end
    if OFFICER_ONLY[name] and not amOfficer() then return end
    if not Comm.FromGuild(sender) then Store.rejected = Store.rejected + 1 return end
    merge(name, Comm.decodeRecord(recStr), true, sender)
end)
-- Sammel-Nachricht beim Sync: UB^coll^rec^rec^...
Comm.On("UB", function(sender, channel, name, ...)
    if type(name) ~= "string" or not RETENTION[name] then return end
    if not Comm.FromGuild(sender) then Store.rejected = Store.rejected + 1 return end
    local skip = OFFICER_ONLY[name] and not amOfficer()
    for i = 1, skip and 0 or select("#", ...) do
        local s = select(i, ...)
        if type(s) == "string" and s ~= "" then merge(name, Comm.decodeRecord(s), true, sender, true) end
    end
    -- nur ein an MICH gerichteter Abgleich zaehlt als "abgeglichen" (Rundsendungen eines Neuankommenden nicht)
    if channel == "WHISPER" then
        if Comm.BusyPeer then Comm.BusyPeer(sender) end
        if Comm.MarkPeer then Comm.MarkPeer(sender, "i") end
        ns.db.meta.lastSync = ns.now()
        ns.db.meta.lastSyncFrom = sender
        Comm.syncing = nil
    end
    ns.Fire("SYNCED")
end)

-- 0.5.617: Nicht-Offiziere loeschen frueher empfangene Leitungsdaten (einmal je Sitzung, wenn die Gildenliste da ist)
local officerPurged = false
ns.Listen("ROSTER", function()
    if officerPurged or not IsInGuild() then return end
    if not (ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0) then return end
    officerPurged = true
    ns.After(10, function()
        if amOfficer() then return end
        for name in pairs(OFFICER_ONLY) do
            if ns.db.store[name] and next(ns.db.store[name]) then ns.db.store[name] = {} end
        end
    end)
end)

local function prune()
    local now = ns.now()
    counts = {}
    for name, keep in pairs(RETENTION) do
        local c = coll(name)
        for id, r in pairs(c) do
            if type(r) ~= "table" then c[id] = nil
            else
                -- Altlasten: Zeitstempel weit in der Zukunft (vor der Haertung angenommen) auf jetzt setzen
                if type(r.u) ~= "number" or not finite(r.u) then r.u = 0 end
                if r.u > now + FUTURE_SLACK then r.u = now end
                local ref = r.u
                -- Terminzeit/Ablauf nur in vernuenftigen Grenzen (sonst lebt ein Datensatz ewig)
                if name == "events" and type(r.ts) == "number" and r.ts < now + 400 * 86400 then ref = math.max(ref, r.ts) end
                if (name == "campfires" or name == "lfg") and type(r.exp) == "number" then ref = math.min(r.exp, r.u + 7 * 86400) end
                if now - ref > keep then c[id] = nil end
            end
        end
    end
end

-- einmalig: vorhandene Texte im Speicher entschaerfen (vor der Haertung empfangene Daten)
local SEC_CLEAN = 1
local function cleanStored()
    if ns.db.meta.secClean == SEC_CLEAN then return end
    for name in pairs(RETENTION) do
        for _, r in pairs(coll(name)) do
            if type(r) == "table" then
                for k, v in pairs(r) do
                    if type(v) == "string" and v:find("|", 1, true) then r[k] = ns.CleanText(v, REC_MAX_VAL) end
                end
            end
        end
    end
    ns.db.meta.secClean = SEC_CLEAN
end

------------------------------------------------------------------------
-- Sync: Neu eingeloggte fragen, ein zufaellig gewaehltes Mitglied antwortet
------------------------------------------------------------------------
local pendingReply = {}

-- broadcast = an ALLE Online-Mitglieder (Gildenkanal) statt nur an den Fragenden:
-- so bekommen auch die, die schon online waren, die Daten eines Neuankommenden
-- kleine, wichtige Sammlungen immer komplett schicken (nicht nur "seit letztem Abgleich"):
-- ein Datensatz, der einmal verpasst wurde, kaeme sonst nie mehr an
local ALWAYS_FULL = { polls = true, votes = true, events = true, signups = true, notices = true, guildcfg = true,
    raidplan = true, chatpin = true, softres = true, sres = true }
local function sendAllTo(target, since, broadcast)
    local since0 = since
    for name in pairs(RETENTION) do
        since = (ALWAYS_FULL[name] and not broadcast) and 0 or since0
        local batch, size = {}, 0
        local off = OFFICER_ONLY[name]
        local function flush()
            if #batch > 0 then
                if broadcast and IsInGuild() then Comm.SendEx({ ch = off and "OFFICER" or "GUILD", bulk = true }, "UB", name, unpack(batch))
                else Comm.WhisperBulk(target, "UB", name, unpack(batch)) end
                batch, size = {}, 0
            end
        end
        -- Leitungsdaten nur von Offizieren an Offiziere
        if off and not (amOfficer() and (broadcast or isOfficerName(target))) then flush = function() batch, size = {}, 0 end end
        for _, r in pairs(coll(name)) do
            if (r.u or 0) > since and not r.demo and not tostring(r.id):find("demo-", 1, true) and ownGuild(r) then
                local s = Comm.encodeRecord(r)
                batch[#batch + 1] = s
                size = size + #s
                if size > 1500 then flush() end
            end
        end
        flush()
    end
end

-- Wer eine Login-Anfrage beantwortet, fragt den Neuankommenden im Gegenzug nach dem,
-- was er selbst verpasst hat (z.B. weil beim eigenen Login niemand online war).
-- "back" = Rueckfrage, darauf wird nicht erneut zurueckgefragt.
local askedBack = {}
-- Gildendaten nur an Gildenmitglieder; je Absender hoechstens alle 2 Minuten ein Komplettabgleich
-- (sonst kann ein manipulierter Client per Dauer-SYNCREQ die Sende-Schlange aller fluten)
local syncServed = {}
local syncWin, syncWinN = 0, 0
Comm.On("SYNCREQ", function(sender, channel, since, back, retry)
    if not Comm.FromGuild(sender) then return end
    -- Wiederholung (erste Anfrage blieb unbeantwortet): nur Berechtigte antworten, Abbruch-Meldungen zaehlen nicht
    retry = retry == "1"
    if retry and not (ns.isOfficer() or (ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.plan.sort"))) then return end
    since = tonumber(since) or 0
    if not finite(since) or since < 0 then since = 0 end
    if pendingReply[sender] then return end
    if syncServed[sender] and GetTime() - syncServed[sender] < 120 then return end
    -- insgesamt hoechstens 6 Komplettabgleiche pro Minute bedienen (viele Absender gleichzeitig = Flut)
    if GetTime() - syncWin > 60 then syncWin, syncWinN = GetTime(), 0 end
    if syncWinN >= 6 then return end
    syncWinN = syncWinN + 1
    local direct = channel == "WHISPER"
    -- Berechtigte (Raid-Assistenz aufwaerts) antworten zuerst: nur deren Weitergabe von Leitungs-/Raiddaten zaehlt
    local priv = ns.isOfficer() or (ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.plan.sort"))
    local delay = direct and 0.3 or (math.random(3, 20) / 10 + (priv and 0 or 2.5))
    pendingReply[sender] = true
    ns.After(delay, function()
        if pendingReply[sender] ~= true and not retry then pendingReply[sender] = nil return end
        pendingReply[sender] = nil
        if not direct then Comm.Guild("SYNCACK", sender) end
        syncServed[sender] = GetTime()
        -- Rueckfrage ("back"): ich bin der Neuankommende und habe evtl. Daten, die ALLE Anwesenden
        -- noch nicht kennen (z.B. offline geaendert) -> an die ganze Gilde, nicht nur an den Fragenden
        Comm.BusyPeer(sender)
        sendAllTo(sender, since, back == "1")
        -- Abschluss immer senden, auch wenn nichts Neues dabei war ("aktuell")
        Comm.Whisper(sender, "SYNCDONE")
        Comm.MarkPeer(sender, "o")
        if back ~= "1" and not askedBack[sender] then
            askedBack[sender] = true
            local mine = math.max(0, (Comm.prevAlive or 0) - 3600)
            ns.After(3, function() Comm.Whisper(sender, "SYNCREQ", mine, "1") end)
        end
    end)
end)
-- Abgleich je Mitglied merken (0.5.515): i = Daten von ihm bekommen, o = ihm Daten geschickt
-- Schluessel = Vorname (Forever: Absender "Vorname-Realm", Gildenliste "Vorname Nachname-Realm")
local function peerKey(name) return ns.NameKey(name) end
function Comm.MarkPeer(sender, dir)
    if not sender or not ns.db then return end
    ns.db.meta.peers = ns.db.meta.peers or {}
    local k = peerKey(sender)
    if k == "" then return end
    local e = ns.db.meta.peers[k] or {}
    e[dir] = ns.now()
    ns.db.meta.peers[k] = e
    Comm.peerFresh = Comm.peerFresh or {}
    Comm.peerFresh[k] = GetTime()
    ns.Debounce("peerRefresh", 0.5, function() if ns.Radar and ns.Radar.RefreshRows then ns.Radar.RefreshRows() else ns.RefreshPage("radar") end end)
end
-- laeuft gerade ein Abgleich mit ihm? (Daten kommen/gehen, bis 3 s nach dem letzten Paket)
Comm.peerBusy = {}
function Comm.BusyPeer(sender)
    local k = peerKey(sender)
    if k ~= "" then Comm.peerBusy[k] = GetTime() end
    ns.Debounce("peerRefresh", 0.3, function() if ns.Radar and ns.Radar.RefreshRows then ns.Radar.RefreshRows() else ns.RefreshPage("radar") end end)
end
function Comm.PeerBusy(name)
    local t = Comm.peerBusy[peerKey(name)]
    return t ~= nil and GetTime() - t < 3
end
-- letzter Abgleich mit einem Mitglied: zeit (max), bekommen, geschickt, gerade eben (Animation)
function Comm.PeerSync(name)
    local e = ns.db and ns.db.meta.peers and ns.db.meta.peers[peerKey(name)]
    if not e then return nil end
    local fr = Comm.peerFresh and Comm.peerFresh[peerKey(name)]
    return math.max(e.i or 0, e.o or 0), e.i, e.o, fr and GetTime() - fr < 4
end
local function synced(sender)
    Comm.MarkPeer(sender, "i")
    ns.db.meta.lastSync = ns.now()
    ns.db.meta.lastSyncFrom = sender
    Comm.syncing = nil
    Comm.noAnswer = nil
    ns.Fire("SYNCED")
end
Comm.On("SYNCDONE", function(sender) if Comm.FromGuild(sender) then synced(sender) end end)
Comm.On("SYNCACK", function(sender, channel, target)
    -- jemand anders antwortet schon (nur ueber den Gildenkanal glaubwuerdig)
    if Comm.rawChannel ~= "GUILD" then return end
    if not Comm.FromGuild(sender) or (target and sameName(sender, target)) then return end
    if target and pendingReply[target] then pendingReply[target] = "cancel" end
end)

function Comm.RequestSync(full)
    if not IsInGuild() then return end
    local since = full and 0 or math.max(0, (ns.db.meta.lastSync or 0) - 3600)
    Comm.Guild("SYNCREQ", since)
    local started = GetTime()
    Comm.syncing, Comm.noAnswer = started, nil
    ns.Fire("SYNCED")
    -- keiner antwortet (niemand mit Oasis online): nicht ewig "gleicht ab" zeigen
    -- gefaelschte SYNCACKs koennen Antworten unterdruecken: nach 8 s ohne Abschluss einmal nachfragen
    ns.After(8, function()
        if Comm.syncing == started then Comm.Guild("SYNCREQ", since, nil, "1") end
    end)
    ns.After(15, function()
        if Comm.syncing == started then
            Comm.syncing, Comm.noAnswer = nil, true
            ns.Fire("SYNCED")
        end
    end)
end


------------------------------------------------------------------------

-- Abgleich-Takt (Sicherheitsnetz): alle ~10 Minuten schickt jeder eine winzige Zusammenfassung

-- je Sammlung ("Anzahl:neuester Zeitpunkt"). Wer sieht, dass ein anderer bei einer Sammlung weiter ist,

-- holt sich gezielt nur diese Sammlung nach. So kommt alles an, was unterwegs verloren ging

-- (Ladebildschirm, Verbindung weg, volle Sende-Schlange, unvollstaendiger Login-Abgleich).

-- Bremsen: nicht im Kampf/in Instanzen, je Sammlung hoechstens alle 5 Min eine Nachfrage,

-- je Fragendem und Sammlung hoechstens alle 2 Min eine Antwort.

------------------------------------------------------------------------

local DIG_EVERY = 600
-- Nach dem Login: wichtige kleine Sammlungen einzeln und KOMPLETT (since 0) anfragen - "DIGREQ" verstehen auch
-- aeltere Oasis-Versionen. So kommt z.B. eine Umfrage an, die auf einem anderen PC entstanden ist.
function Comm.PullImportant(target)
    if not IsInGuild() then return end
    target = target or (ns.db.meta and ns.db.meta.lastSyncFrom)
    if not target or ns.isMe(target) then
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
            if m.online and not ns.isMe(m.name) and ns.Radar.HasAddon and ns.Radar.HasAddon(m.name) then target = m.name break end
        end
    end
    if not target or ns.isMe(target) then return end
    local i = 0
    for _, name in ipairs({ "polls", "votes", "avotes", "events", "signups", "notices", "raidplan", "chatpin", "softres", "sres" }) do
        if RETENTION[name] then
            i = i + 1
            ns.After(i * 1.5, function() Comm.Whisper(target, "DIGREQ", name, 0) end)
        end
    end
    return target
end
ns.Listen("LOGIN", function() ns.After(75, function() pcall(Comm.PullImportant) end) end)

local function digestOf(name)
    local n, top, rows = 0, 0, {}
    for _, r in pairs(coll(name)) do
        if type(r) == "table" and not r.demo and not tostring(r.id):find("demo-", 1, true) and ownGuild(r) then
            n = n + 1
            top = math.max(top, tonumber(r.u) or 0)
            rows[#rows + 1] = tostring(r.id) .. ":" .. ns.hash(Comm.encodeRecord(r))
        end
    end
    table.sort(rows)
    return n, top, ns.hash(table.concat(rows, ","))
end
Comm.DigestOf = digestOf

function Comm.Digest()

    local parts, i = {}, 0

    for name in pairs(RETENTION) do

        local n, top, fingerprint = digestOf(name)

        if n > 0 then

            i = i + 1

            parts[i] = name .. ":" .. n .. ":" .. math.floor(top) .. ":" .. fingerprint

        end

    end

    table.sort(parts)

    return table.concat(parts, ",")

end

local function quietNow()

    if ns.inCombat and ns.inCombat() then return true end

    local inInst, kind = IsInInstance()

    return inInst and (kind == "raid" or kind == "party" or kind == "pvp" or kind == "arena") or false

end

local digAsked = {}     -- Sammlung -> GetTime() der letzten eigenen Nachfrage

local digServed = {}    -- "Name|Sammlung" -> GetTime() der letzten Antwort

Comm.digStats = { sent = 0, asked = 0, served = 0 }

function Comm.SendDigest()

    if not IsInGuild() or quietNow() then return end

    local d = Comm.Digest()

    if d == "" then return end

    Comm.SendEx({ ch = "GUILD", bulk = true }, "DIG", d)

    Comm.digStats.sent = Comm.digStats.sent + 1

end

Comm.On("DIG", function(sender, channel, d)

    if type(d) ~= "string" or #d > 4000 or Comm.rawChannel ~= "GUILD" or not Comm.FromGuild(sender) then return end

    if quietNow() then return end

    for entry in d:gmatch("[^,]+") do
        local name, n, top, fingerprint = entry:match("^([%w_]+):(%d+):(%d+):?(%x*)$")

        n, top = tonumber(n), tonumber(top)

        if RETENTION[name] and finite(n) and finite(top) and top <= ns.now() + 600 then

            local myN, myTop, myFingerprint = digestOf(name)

            -- er ist weiter: neuere Aenderungen, oder gleich neu aber mehr Eintraege (mir fehlen aeltere)

            local newer = top > myTop + 2

            local more = (not newer) and n > myN and top >= myTop

            local different = fingerprint and fingerprint ~= "" and fingerprint ~= myFingerprint and n == myN and top == myTop
            if (newer or more or different) and GetTime() - (digAsked[name] or -999) > 300 then

                digAsked[name] = GetTime()

                local since = newer and math.max(0, myTop - 3600) or 0

                -- kurz zufaellig warten: sieht mehr als einer dieselbe Luecke, fragt nicht jeder gleichzeitig

                ns.After(math.random(2, 12), function()

                    Comm.Whisper(sender, "DIGREQ", name, since)

                    Comm.digStats.asked = Comm.digStats.asked + 1

                end)

            end

        end

    end

end)

Comm.On("DIGREQ", function(sender, channel, name, since)

    if type(name) ~= "string" or not RETENTION[name] or not Comm.FromGuild(sender) then return end

    since = tonumber(since) or 0

    if not finite(since) or since < 0 then since = 0 end

    local key = tostring(sender) .. "|" .. name

    if GetTime() - (digServed[key] or -999) < 120 then return end

    digServed[key] = GetTime()

    local batch, size = {}, 0

    local function flush()

        if #batch > 0 then Comm.WhisperBulk(sender, "UB", name, unpack(batch)) batch, size = {}, 0 end

    end

    for _, r in pairs(coll(name)) do

        if type(r) == "table" and (r.u or 0) > since and not r.demo and not tostring(r.id):find("demo-", 1, true) and ownGuild(r) then

            local str = Comm.encodeRecord(r)

            batch[#batch + 1] = str

            size = size + #str

            if size > 1500 then flush() end

        end

    end

    flush()

    Comm.digStats.served = Comm.digStats.served + 1

end)

ns.Listen("LOGIN", function()

    -- erster Takt nach dem Login-Abgleich, dann alle ~10 Min (mit Zufall, damit nicht alle gleichzeitig senden)

    local function loop()

        pcall(Comm.SendDigest)

        ns.After(DIG_EVERY + math.random(0, 120), loop)

    end

    ns.After(180 + math.random(0, 120), loop)

end)

ns.slash.digest = function()

    local st = Comm.digStats

    ns.print(("Abgleich-Takt: gesendet %d  ·  nachgefragt %d  ·  beantwortet %d"):format(st.sent, st.asked, st.served))

    ns.print("  " .. Comm.Digest():sub(1, 240))

end



ns.slash.sync = function()
    Comm.RequestSync(true)
    ns.print(L["Vollstaendiger Abgleich angefordert."])
end

-- "schon gesehen"-Listen aufraeumen: Eintraege, deren Datensatz es nicht mehr gibt, oder die sehr alt sind
local function exists(id, ...)
    for i = 1, select("#", ...) do
        local c = ns.db.store[select(i, ...)]
        if c and c[id] then return true end
    end
    return false
end
function Comm.PruneSeen()
    local db, now = ns.db, ns.now()
    for id, ts in pairs(db.seenNotices or {}) do
        if not exists(id, "notices") and (tonumber(ts) or 0) < now - 30 * 86400 then db.seenNotices[id] = nil end
    end
    for id in pairs(db.instaSeen or {}) do
        if not exists(id, "posts", "likes", "comments", "follows") then db.instaSeen[id] = nil end
    end
    for id in pairs(db.pollSeen or {}) do
        if not exists(id, "polls") then db.pollSeen[id] = nil end
    end
    for id in pairs(db.helpedSeen or {}) do
        if not exists(id, "wants") then db.helpedSeen[id] = nil end
    end
    -- Rang-Schutz: Stand von Leuten, die ein Jahr nicht mehr aufgetaucht sind
    for key, r in pairs(db.rankSeen or {}) do
        if type(r) == "table" and (r.ts or 0) < now - 365 * 86400 then db.rankSeen[key] = nil end
    end
    -- Mitspieler von ausserhalb: nach 90 Tagen vergessen (ausser Favorit oder mit Notiz)
    for name, a in pairs(db.allies or {}) do
        if type(a) == "table" and not a.fav and (a.note or "") == "" and not a.demo and (a.last or 0) < now - 90 * 86400 then
            db.allies[name] = nil
        end
    end
end

-- Hilfsfelder ("_src", "_makers" ...), die Seiten zur Anzeige an Datensaetze haengen, nicht mitspeichern
ns.On("PLAYER_LOGOUT", function()
    for _, c in pairs(ns.db.store or {}) do
        for _, r in pairs(c) do
            if type(r) == "table" then
                for k in pairs(r) do
                    if type(k) == "string" and k:sub(1, 1) == "_" then r[k] = nil end
                end
            end
        end
    end
end)

ns.Listen("LOGIN", function()
    prune()
    pcall(cleanStored)
    ns.After(120, function() pcall(Comm.PruneSeen) end)
    -- wann war ich zuletzt online? (fuer die Rueckfrage an andere)
    Comm.prevAlive = ns.db.meta.lastAlive or ns.db.meta.lastSync or 0
    ns.db.meta.lastAlive = ns.now()
    ns.Every(60, function() ns.db.meta.lastAlive = ns.now() end)
    ns.After(3, function() Comm.RequestSync(false) end)
    ns.Every(600, prune)
end)

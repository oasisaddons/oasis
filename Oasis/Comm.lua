-- Oasis - communication between the addons (guild / group / whisper)
-- plus replicated collections ("Store") with sync for members who log in later
local ADDON, ns = ...
local L = ns.L

local PREFIX = "OASIS1"
-- several prefixes: WoW throttles per prefix (~1 message/s) -> 3 prefixes = about triple throughput
local PREFIXES = { "OASIS1", "OASIS2", "OASIS3" }
local IS_PREFIX = {}
for _, p in ipairs(PREFIXES) do IS_PREFIX[p] = true end
local Comm = {}
ns.Comm = Comm

------------------------------------------------------------------------
-- Compression with WoW's built-in packer (C_EncodingUtil), if the client has it:
-- "~" + Base64(Deflate(payload)). Only worth it from ~120 characters; if the result isn't shorter, plain text stays.
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
-- Upper limit for unpacked messages (protection against "zip bombs" from manipulated clients)
local UNZIP_MAX = 262144
local ZIP_IN_MAX = 24000   -- limit packed messages before unpacking (zip bomb)
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
-- Encoding: fields separated by ^, special characters as %XX
------------------------------------------------------------------------
local function esc(s)
    s = tostring(s == nil and "" or s)
    return (s:gsub("[%%%^\n|;=,:]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
Comm.esc, Comm.unesc = esc, unesc

-- Uniform limits and atomic records (no silently truncated fields).
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
-- Send queue with throttle (Blizzard allows about 10 messages
-- in a row, then ~1 per second per prefix)
------------------------------------------------------------------------
local queue = {}
local MAXTOK, REGEN = 8, 1.05
local tokens = {}
for _, p in ipairs(PREFIXES) do tokens[p] = MAXTOK end
local lastRegen = GetTime()
-- shared brake for all prefixes: the server limits per player overall
-- ("The number of messages ... is limited") - briefly up to 10 in a row, then about 1.5 per second
local G_MAX, G_REGEN = 10, 0.65
local gTok = G_MAX
local pausedUntil = 0
local msgCounter = 0
Comm.sent, Comm.received = 0, 0

-- Both lock queries raw (for diagnosis). The beta client permanently reports "locked" here,
-- although sending works -> NO longer depend on it, but send and check the return value.
local function lockState()
    local a, b
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        a = ok and tostring(r) or "Bug"
    end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
        local ok, r = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
        b = ok and tostring(r) or "Bug"
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
    if #queue == 0 then return end   -- 0.5.722: nothing to send -> no token accounting (the next one catches up, capped)
    local now = GetTime()
    for p, t in pairs(tokens) do tokens[p] = math.min(MAXTOK, t + (now - lastRegen) / REGEN) end
    gTok = math.min(G_MAX, gTok + (now - lastRegen) / G_REGEN)
    lastRegen = now
    if now < pausedUntil or #queue == 0 then return end
    while #queue > 0 do
        -- take the prefix with the most free tokens
        local pfx, best = nil, 0
        for _, p in ipairs(PREFIXES) do if tokens[p] > best then pfx, best = p, tokens[p] end end
        if not pfx or best < 1 or gTok < 1 then return end
        local m = table.remove(queue, 1)
        if channelOk(m.ch) then
            local ok, r = pcall(C_ChatInfo.SendAddonMessage, pfx, m.text, m.ch, m.target)
            Comm.lastResult = ok and tostring(r) or ("Fehler: " .. tostring(r))
            if not ok or (type(r) == "number" and r ~= 0) or r == false then
                -- throttled or rejected: back to the front, wait briefly
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

-- Upper limit: if many answer sync requests at once, the queue would otherwise grow to thousands.
-- Then the oldest sync packets (UB) are dropped - the receiver fetches them at the next sync.
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
        -- behind the already waiting priority messages (parts stay in order)
        local pos = 1
        while queue[pos] and queue[pos].prio do pos = pos + 1 end
        table.insert(queue, pos, m)
        -- urgent message: send immediately instead of waiting for the next tick (0.25 s)
        if not group then C_Timer.After(0, function() pcall(pump) end) end
    elseif bulk then
        queue[#queue + 1] = m
    else
        -- 0.5.788: normal (live) messages BEFORE the sync packets (bulk) - otherwise e.g. online/level-up/loot messages waited
        -- behind up to 400 sync packets and arrived minutes late. Order: urgent > normal > sync.
        local pos = #queue + 1
        for i = 1, #queue do
            if queue[i].bulk and not queue[i].prio then pos = i break end
        end
        table.insert(queue, pos, m)
    end
    if not group then trimQueue() end
end

-- Comm.Send("GUILD", nil, "TYPE", field1, field2, ...) ; opts: Comm.SendEx
function Comm.SendEx(opts, msgType, ...)
    local ch, target = opts.ch, opts.target
    if not ch then return end
    local n = select("#", ...)
    local fields = { msgType }
    for i = 1, n do fields[#fields + 1] = esc((select(i, ...))) end
    local raw = table.concat(fields, "^")
    if #raw > LIMITS.message then
        ns.err("Comm", L["Message too large; not sent."])
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
-- Whisper target: WoW Forever delivers senders as "First Last-Realm", but whispering goes
-- to the full character, own realm can be omitted
function Comm.WhisperName(name)
    local full = ns.ResolveName(name)
    if not full then return name end
    local base, realm = full:match("^(.-)%-(.+)$")
    local ownRealm = ns.me() and ns.me():match("%-(.+)$")
    if realm and realm ~= ownRealm then return full end
    return base or full
end
-- WoW Forever does not deliver addon whispers ("no player named ..."), but guild messages it does.
-- That's why "whisper" goes over the guild channel with a recipient (full name): W^recipient^type^fields...
-- Only the recipient evaluates it; to the handlers it looks like a normal whisper message.
local function whoKey(name) return ns.NameKey(name) end
Comm.whoKey = whoKey
-- like Whisper, but marked as a droppable sync packet (may be dropped when the queue is full)
function Comm.WhisperBulk(target, msgType, ...)
    if IsInGuild() then
        Comm.SendEx({ ch = "GUILD", bulk = true }, "W", whoKey(target), msgType, ...)
    else
        Comm.SendEx({ ch = "WHISPER", target = Comm.WhisperName(target), bulk = true }, msgType, ...)
    end
end
-- time-critical messages (groups) ahead of everything else in the queue
local URGENT = { JOIN = true, JOINNO = true, MERGE = true, MERGEOK = true, TYP = true, JOINCANCEL = true, GROLE = true,
    DRINV = true, DRACC = true, DRNO = true, DRBUSY = true, DRROLL = true, DRGIVEUP = true, DRCOMMIT = true, DRSEED = true,
    DRJOIN = true, DRFULL = true, DRQ = true, DRQX = true, DRLOOK = true }
Comm.URGENT = URGENT
-- Target in my group, but not reachable via the guild? -> group channel (Forever doesn't deliver addon whispers)
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
    -- 0.6.468: target definitely not in the own guild (e.g. friend from another guild) -> real whisper,
    -- via the guild channel it would never arrive
    local A = ns.Admin
    local outside = A and A.InGuildList and A.InGuildList(target) == false
    if IsInGuild() and not outside then
        Comm.SendEx({ ch = "GUILD", prio = URGENT[msgType] }, "W", whoKey(target), msgType, ...)
    else
        -- 0.6.512: Forever doesn't deliver addon whispers - if there is a shared channel (death roll network),
        -- send there with a recipient; only the recipient evaluates it
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
-- Receiving
------------------------------------------------------------------------
local handlers = {}
function Comm.On(msgType, fn)
    handlers[msgType] = handlers[msgType] or {}
    table.insert(handlers[msgType], fn)
end

local partial = {}
-- Limits for foreign messages
local MAX_FIELDS, MAX_FIELD_LEN = 600, LIMITS.wireField
Comm.badMsg, Comm.flood = 0, 0
-- Comm.rawChannel: real WoW channel of the message currently being evaluated (before the "W" remapping to WHISPER).
-- Handlers can thus check whether something really came via the guild channel.
Comm.rawChannel = nil
local function dispatch(sender, channel, payload)
    payload = unzip(payload)
    if not payload then ns.debug("Nachricht nicht entpackbar", sender) Comm.badMsg = Comm.badMsg + 1 return end
    local fields = {}
    for f in (payload .. "^"):gmatch("([^%^]*)%^") do
        if #fields >= MAX_FIELDS then Comm.badMsg = Comm.badMsg + 1 return end
        -- sanitize foreign texts (item links/colors stay, |K/|A/huge textures don't)
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
-- did the message currently being evaluated come from a guild member? (guild channel = confirmed by the server)
function Comm.FromGuild(sender)
    local raw = Comm.rawChannel
    if raw == "GUILD" or raw == "OFFICER" then return true end
    local A = ns.Admin
    if A and A.InGuildList then return A.InGuildList(sender) == true end
    return false
end

-- Throttle per sender: otherwise manipulated clients could flood with messages
-- (the server throttles too, but not across all channels/prefixes combined)
local RL_MAX, RL_REGEN = 120, 8   -- 120 in a row, then 8 per second
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

-- Incoming counters (diagnosis): where do messages get lost?
Comm.inRaw, Comm.inOasis, Comm.inSecret, Comm.inSelf, Comm.lastFrom = 0, 0, 0, 0, nil
local rawFrame = CreateFrame("Frame")
rawFrame:RegisterEvent("CHAT_MSG_ADDON")
rawFrame:SetScript("OnEvent", function(_, _, prefix, _, _, sender)
    Comm.inRaw = Comm.inRaw + 1
    if IS_PREFIX[ns.safe(prefix) or ""] then
        Comm.inOasis = Comm.inOasis + 1
        Comm.lastFrom = tostring(ns.safe(sender) or "(geheim)")
        -- remember raw sender names (session only): /oa probe wer <Name> shows whether and under which name someone arrives
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
    -- map the sender to the name from the guild list (Forever: the realm suffix differs per client,
    -- otherwise the profile ends up under "...-ClassicBetaPvE2", but the list looks for "...-ClassicBetaPvE")
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
            -- only a few open partial messages per sender at a time (memory)
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
-- clean up orphaned partial messages
C_Timer.NewTicker(60, function()
    local now = GetTime()
    for k, p in pairs(partial) do
        if now - p.t > 120 or now - p.start > 1800 then partial[k] = nil end
    end
    -- full throttle buckets no longer need an entry
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
-- register already while loading (not only at login) so no early messages are lost
registerPrefix()
ns.On("PLAYER_LOGIN", registerPrefix)

-- /oa ping: everyone with Oasis answers via whisper -> shows whether messages go back and forth
-- PING/PONG throttled: otherwise a manipulated client could force chat lines and replies with continuous PINGs
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
-- Store: replicated collections
-- Jeder Datensatz: id, u (geaendert), by (Autor), del (geloescht)
------------------------------------------------------------------------
local Store = {}
ns.Store = Store
local RETENTION = {
    orders = 21 * 86400,
    events = 3 * 86400,     -- from event end
    signups = 30 * 86400,
    chronicle = 45 * 86400,
    loot = 45 * 86400,
    campCatalog = 365 * 86400,
    campfires = 3600,
    wants = 60 * 86400,
    rep = 365 * 86400,
    flights = 365 * 86400,
    mapcal = 365 * 86400,   -- Dungeon map <-> game position calibration (set by players, for everyone)  -- learned flight times (route -> seconds), shared with the guild      -- experiences with other players (good/bad + note), shared with the guild
    lfg = 3 * 3600,
    dgjoin = 4 * 3600,   -- 0.6.304: join list per dungeon (Dungeons > Guild & Group)
    duels = 400 * 86400,   -- Deathroll: seasons need the full previous month
    polls = 30 * 86400,
    votes = 30 * 86400,
    avotes = 30 * 86400,       -- 0.5.617: secret polls - votes without names (only a random tag)
    deaths = 90 * 86400,       -- 0.5.617: death locations 90 days instead of 1 year
    wtrain = 3650 * 86400,
    rpreq = 3650 * 86400,      -- Raid preparation: requirements per raid (set by the raid leadership)     -- Weapon masters: what they really teach in WoW Forever (read on visit)
    bank = 60 * 86400,
    banklog = 60 * 86400,
    prices = 30 * 86400,
    bankworth = 120 * 86400,   -- Guild bank value per day
    posts = 120 * 86400,       -- Oasigram
    likes = 120 * 86400,
    comments = 120 * 86400,
    follows = 3650 * 86400,
    points = 365 * 86400,
    raidplan = 14 * 86400,
    guildcfg = 3650 * 86400,   -- Guild leadership settings
    notices = 14 * 86400,      -- Announcements
    invites = 3650 * 86400,    -- who has already received an Oasis notice via whisper
    reacts = 14 * 86400,       -- Guild chat: reactions
    links = 30 * 86400,        -- Guild chat: recently linked items (shared)
    lfgreq = 3600,             -- Groups: requests (backup for whispering)
    chatpin = 30 * 86400,      -- Guild chat: pinned message
    attend = 120 * 86400,      -- Raid attendance (per raid day and instance)
    formers = 365 * 86400,     -- 0.5.617: former members 1 year instead of 10
    lvotes = 90 * 86400,       -- 0.6.526: leadership votes (officer channel only)
    gpack = 3650 * 86400,      -- 0.6.532: official guild package (version, fingerprint, rank locks)
    lballots = 90 * 86400,
    gpackhave = 60 * 86400,    -- 0.6.533: which guild package someone has installed (everyone reports only themselves)
    sheep = 60 * 86400,        -- 0.6.539: sheep pasture - chosen sheep skin (everyone reports only themselves)
    gfeed = 3 * 86400,         -- 0.6.548: Guildotchi - fed someone else's pet (everyone reports only themselves, once a day per pet)
    rrating = 180 * 86400,     -- 0.6.527: applicant ratings (officers only)
    kader = 3650 * 86400,      -- Raid roster (core/backup)
    absent = 30 * 86400,       -- Raid sign-offs
    wchal = 60 * 86400,        -- Guild weekly task
    wccontrib = 60 * 86400,
    meets = 60 * 86400,        -- Guild meetups (yearbook needs the previous month)
    meetatt = 60 * 86400,
    tactics = 3650 * 86400,
    markers = 8 * 86400,       -- Guild map markers (MapExtras; expire earlier on their own)
    nodes = 365 * 86400,      -- Guild gathering map (GatherMap)    -- Boss tactics (RaidCheck)    -- Former members (GuildHistory)
    audit = 180 * 86400,       -- Guild log: promotions, demotions, kicks, joins
    bans = 3650 * 86400,       -- Guild leadership ban list
    sndmute = 3650 * 86400,    -- Guild leadership sound locks (go to everyone: each client hides sounds of the locked players)
    recruits = 365 * 86400,    -- Applicants and trial period
    sres = 30 * 86400,         -- Soft reserve per raid event
    trace = 365 * 86400,
    raidint = 21 * 86400,      -- Raid interest (roles + days)
    bugs = 90 * 86400,         -- Error reports + bug reports (only the developer sees them)
    ggoals = 3650 * 86400,     -- Guild goals (GuildGoals.lua)
    ggcontrib = 3650 * 86400,  -- Contributions to guild goals
    board = 60 * 86400,        -- Bulletin board (GuildGoals.lua, 0.6.450)
    gcard = 3650 * 86400,      -- Profiles (Community.lua, 0.6.469)
    mentor = 365 * 86400,      -- Mentors for newcomers
    thanks = 60 * 86400,       -- Thanks
    talents = 120 * 86400,     -- Talent export per character (Talents.lua)
    scout = 120 * 86400,       -- Recruiting suggestions (Scout.lua)
    perf = 30 * 86400,         -- Performance measurement per member (PerfShare.lua)
    combat = 365 * 86400,      -- Combat records per player (CombatBoard.lua)
    profcd = 14 * 86400,       -- Profession cooldowns (transmutation, mooncloth ...)       -- self-explored dungeon maps (routes + bosses)
}

-- 0.5.617 privacy: leadership collections (log, former members, ban list, applicants, bank log) go only
-- via the officer channel, are accepted only by officers and deleted for everyone else
local OFFICER_ONLY = { audit = true, formers = true, bans = true, recruits = true, banklog = true, lvotes = true, lballots = true, rrating = true }   -- 0.6.526: leadership votes
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

-- all non-deleted records, optionally filtered
-- Guild name of the current character: Oasis stores per ACCOUNT - alts without/with another guild share
-- the same file. Records therefore carry the guild name (gn); foreign ones are neither shown nor distributed (08.10.).
local function myGuild()
    local g = IsInGuild() and ns.safe((GetGuildInfo("player"))) or nil
    return g
end
Store.MyGuild = myGuild
local function ownGuild(r)
    if not r.gn then return true end      -- old records without tag: as before
    local g = myGuild()
    return RULES.CanReadGuild(r, g)      -- unknown guild: don't show tagged foreign data
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
-- Author check on receive (rules per collection: ns.Admin.AUTH, rights: ns.Admin.MayAuthor)
-- actor = who made the change: for "U" the sender itself, for sync ("UB",
-- relayed) the field mb (last modified by) or by (creator).
-- Unknown (guild list not loaded yet) -> defer and check again on ROSTER.
------------------------------------------------------------------------
local held, heldN = {}, 0
Store.rejected = 0
local function sameName(a, b)
    if ns.Admin and ns.Admin.SameName then return ns.Admin.SameName(a, b) end
    return a == b
end
local function isDemoRec(rec) return rec.demo or tostring(rec.id or ""):find("demo-", 1, true) ~= nil end
-- true | false | nil (defer)
local function authorize(name, rec, actor)
    local A = ns.Admin
    local g = A and A.AUTH and A.AUTH[name]
    if not g then return true end
    if isDemoRec(rec) or rec.sim then return false end   -- Demo/sim data is never sent
    if not actor or actor == "" then return false end
    local ok, r = pcall(g, rec, actor, coll(name)[rec.id])
    if not ok then ns.debug("Urheber-Pruefung", name, r) return false end
    return r
end
Store.Authorize = authorize
function Store.HeldCount() return heldN end

------------------------------------------------------------------------
-- Hardening on receive (threat: manipulated clients in guild/group/whisper)
--  * timestamp u at most FUTURE_SLACK in the future (otherwise "eternal win" over every later change)
--  * Relayed records (UB) carry an unverifiable mb/by. For leadership data (STRICT_RELAY)
--    the RELAYER must therefore be at least an officer too - otherwise any member could
--    inject guild settings/appointments/announcements "in the name of the guild master".
--  * OWNED: personal collections - only the author (or officers) may change/delete others' records,
--    the author (by) of an existing record is immutable.
--  * Amounts: at most COLL_MAX records per collection and AUTHOR_MAX per author (memory/SavedVariables).
------------------------------------------------------------------------
local FUTURE_SLACK = 900
local MAX_ID = 160
local COLL_MAX, AUTHOR_MAX = 8000, 800
local DAY_NEW, newToday = 300, {}   -- Flood brake for the save file
Store.FUTURE_SLACK = FUTURE_SLACK
-- Collection -> right the RELAYER must have itself (raid leader data: raid assistant and up).
-- So that authorized members answer first during sync, members without rights wait longer (SYNCREQ).
-- 0.5.643: polls no longer - otherwise a poll never arrived if the creator was offline and only members
-- had it. The creator is still checked (AUTH polls), changing/deleting others' records stays reserved to officers.
local STRICT_RELAY = { gpack = "officer", wchal = "officer", kader = "raid.plan.sort", guildcfg = "officer", notices = "officer", bans = "officer", points = "officer", sndmute = "officer",
    recruits = "officer", events = "raid.plan.sort", raidplan = "raid.plan.sort", tactics = "raid.plan.sort" }
local function mayRelay(name, feature)
    local A = ns.Admin
    if not (A and A.MayAuthor) then return false end
    local ok, r = pcall(A.MayAuthor, name, feature)
    if not ok then return false end
    return r
end
local OWNED = { posts = true, comments = true, likes = true, follows = true, rep = true, deaths = true,
    profcd = true, trace = true, lfgreq = true, orders = true, dgjoin = true, lvotes = true, lballots = true,
    rrating = true, wccontrib = true, meets = true, meetatt = true, absent = true, gpackhave = true, sheep = true, gfeed = true }   -- 0.6.527
-- Relayed records (sync): whoever is not the author may only pass on NEW, non-critical records.
-- Changing/deleting others' records and everything in here only by officers (or the author).
-- (bank/ranks only: everything else MUST be relayable, otherwise offline members never get
--  Deathroll results, sign-ups, votes, loot etc. - the author check (AUTH) still runs)
local RELAY_SENSITIVE = { bank = true, banklog = true, bankworth = true, rank = true }
Store.STRICT_RELAY, Store.OWNED = STRICT_RELAY, OWNED
Store.future, Store.capped = 0, 0
local curNet, curRelay = false, false   -- Context of the record currently being checked (for the suspicion monitor)
Store.rejectWhy = {}   -- collection + reason -> count (for /oa abgleich)
local function reject(why, name, rec, actor)
    Store.rejected = Store.rejected + 1
    local wk = tostring(name) .. ": " .. tostring(why)
    Store.rejectWhy[wk] = (Store.rejectWhy[wk] or 0) + 1
    -- only count directly sent records: relayed ones (sync) don't come from the sender itself
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
-- counters per collection (total + per author), built on demand, discarded on prune
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
-- deferred records per collection (for /oa abgleich)
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

-- apply locally if newer
local function merge(name, rec, fromNet, actor, relay)
    if type(rec) ~= "table" then return false end
    if fromNet and rec.gn and myGuild and myGuild() and rec.gn ~= myGuild() then return false end
    local id = rec.id
    if (type(id) ~= "string" and type(id) ~= "number") or id == "" then return false end
    curNet, curRelay = fromNet and true or false, relay and true or false
    -- ignore senders sending masses of forged data for a while
    if fromNet and actor and ns.Suspect and ns.Suspect.Ignored and ns.Suspect.Ignored(actor) then return false end
    if fromNet then
        -- Basic check of foreign data: types, lengths, timestamps
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
            -- forgery: "last modified by" doesn't match the sender
            if rec.mb and rec.mb ~= "" and not sameName(rec.mb, actor) then return reject("mb~=Absender", name, rec, actor) end
            -- fill missing mb (older clients) with the real sender - otherwise a later
            -- relay could present the creator (by) as the author
            if not rec.mb or rec.mb == "" then rec.mb = actor end
        else
            actor = (rec.mb ~= nil and rec.mb ~= "") and rec.mb or rec.by
            if name == "avotes" then actor = sender end
        end
        local cur = coll(name)[id]
        if relay then
            -- guild settings are only passed on by their owner (otherwise officers could forge the guild leadership)
            if name == "guildcfg" and not (rec.by and sameName(rec.by, sender)) then
                return reject("guildcfg nur vom Besitzer", name, rec, sender)
            end
            -- claimed author is not the relayer: only officers may change others' records,
            -- delete them or pass on critical collections
            -- existing record: relaying a newer version is ok as long as the creator (by) stays the same
            local authorSwap = cur and cur.by and rec.by and not sameName(cur.by, rec.by)
            if actor and actor ~= "" and not sameName(actor, sender) and (authorSwap or rec.del or RELAY_SENSITIVE[name]) then
                local off = isOfficer(sender)
                if off == nil then return holdRec(name, rec, sender, relay) end
                if not off then return reject("fremder Satz weitergereicht", name, rec, sender) end
            end
        end
        if cur and (cur.u or 0) > (rec.u or 0) then return false end
        -- let only officers relay leadership data
        if relay and STRICT_RELAY[name] then
            local okR = mayRelay(sender, STRICT_RELAY[name])
            if okR == nil then return holdRec(name, rec, sender, relay) end
            if not okR then return reject("Weiterreichen von Leitungsdaten ohne Rechte", name, rec, sender) end
        end
        -- personal records: only the author (or officers)
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
        -- amount limits only for NEW records
        if not cur then
            local cnt = countsOf(name)
            -- additionally: per author and collection at most DAY_NEW freshly created records (last 24 h)
            -- (older records from sync don't count, otherwise the first login sync gets throttled)
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
    -- For comparison use the same anonymized content as in storage.
    if name == "avotes" then rec.by, rec.mb = nil, nil end
    if old and old ~= rec and RULES.Compare(rec, old) <= 0 then return false end
    -- secret votes: never store a name
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

-- recheck deferred records (guild list/leadership settings loaded)
local recheckDue = false
function Store.Recheck()
    recheckDue = false
    local now = GetTime()
    -- collect first, then check (merge may defer again)
    local list = {}
    for key, h in pairs(held) do list[#list + 1] = h held[key] = nil end
    heldN = 0
    for _, h in ipairs(list) do
        if now - h.t <= 1800 then
            merge(h.name, h.rec, true, h.sender, h.relay)
            -- still unknown -> keep the original waiting time
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

-- create/change and send to the guild
function Store.Put(name, rec)
    -- no guild data without a guild (otherwise an alt using the same account file would later distribute it to its guild)
    if not IsInGuild() then return rec end
    if OFFICER_ONLY[name] and not amOfficer() then return rec end
    rec.gn = rec.gn or myGuild()
    local previous = coll(name)[rec.id]
    rec.u = math.max(ns.now(), (rec.u or 0) + 1, ((previous and previous.u) or 0) + 1)
    ns.db.meta.revSeq = (ns.db.meta.revSeq or 0) + 1
    -- Anonymous votes also get a revision without character name.
    rec.rv = ("%08x%08x:%d"):format(math.random(0, 2147483646), math.random(0, 2147483646), ns.db.meta.revSeq)
    rec.by = rec.by or ns.me()
    rec.mb = ns.me()   -- last modified by (author check on receive)
    if name == "avotes" then rec.by, rec.mb = nil, nil end
    merge(name, rec)
    -- demo data (/oa demo) stays local
    if rec.demo or tostring(rec.id):find("demo-", 1, true) then return rec end
    -- send groups/requests/pins immediately, don't wait behind sync packets
    -- 0.5.708: deaths too - otherwise they waited behind sync packets (up to minutes) and the notice came far too late
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

-- guild collections only from guild members (guild channel or sender in the guild list),
-- never from strangers via real whisper/group/raid
Comm.On("U", function(sender, channel, name, recStr)
    if type(name) ~= "string" or not RETENTION[name] or type(recStr) ~= "string" then return end
    if OFFICER_ONLY[name] and not amOfficer() then return end
    if not Comm.FromGuild(sender) then Store.rejected = Store.rejected + 1 return end
    merge(name, Comm.decodeRecord(recStr), true, sender)
end)
-- bulk message on sync: UB^coll^rec^rec^...
Comm.On("UB", function(sender, channel, name, ...)
    if type(name) ~= "string" or not RETENTION[name] then return end
    if not Comm.FromGuild(sender) then Store.rejected = Store.rejected + 1 return end
    local skip = OFFICER_ONLY[name] and not amOfficer()
    for i = 1, skip and 0 or select("#", ...) do
        local s = select(i, ...)
        if type(s) == "string" and s ~= "" then merge(name, Comm.decodeRecord(s), true, sender, true) end
    end
    -- only a sync addressed to ME counts as "synced" (broadcasts of a newcomer don't)
    if channel == "WHISPER" then
        if Comm.BusyPeer then Comm.BusyPeer(sender) end
        if Comm.MarkPeer then Comm.MarkPeer(sender, "i") end
        ns.db.meta.lastSync = ns.now()
        ns.db.meta.lastSyncFrom = sender
        Comm.syncing = nil
    end
    ns.Fire("SYNCED")
end)

-- 0.5.617: non-officers delete previously received leadership data (once per session, when the guild list is there)
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
                -- legacy: set timestamps far in the future (accepted before hardening) to now
                if type(r.u) ~= "number" or not finite(r.u) then r.u = 0 end
                if r.u > now + FUTURE_SLACK then r.u = now end
                local ref = r.u
                -- event time/expiry only within reasonable limits (otherwise a record lives forever)
                if name == "events" and type(r.ts) == "number" and r.ts < now + 400 * 86400 then ref = math.max(ref, r.ts) end
                if (name == "campfires" or name == "lfg") and type(r.exp) == "number" then ref = math.min(r.exp, r.u + 7 * 86400) end
                if now - ref > keep then c[id] = nil end
            end
        end
    end
end

-- once: sanitize existing texts in storage (data received before hardening)
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
-- Sync: newly logged-in members ask, a randomly chosen member answers
------------------------------------------------------------------------
local pendingReply = {}

-- broadcast = to ALL online members (guild channel) instead of only the asker:
-- so those already online also get a newcomer's data
-- always send small, important collections completely (not just "since last sync"):
-- a record that was missed once would otherwise never arrive
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
        -- leadership data only from officers to officers
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

-- Whoever answers a login request asks the newcomer in return for what
-- they missed themselves (e.g. because nobody was online at their own login).
-- "back" = counter-request, it doesn't get counter-requested again.
local askedBack = {}
-- guild data only to guild members; per sender at most one full sync every 2 minutes
-- (otherwise a manipulated client could flood everyone's send queue with continuous SYNCREQs)
local syncServed = {}
local syncWin, syncWinN = 0, 0
Comm.On("SYNCREQ", function(sender, channel, since, back, retry)
    if not Comm.FromGuild(sender) then return end
    -- retry (first request went unanswered): only authorized members answer, abort messages don't count
    retry = retry == "1"
    if retry and not (ns.isOfficer() or (ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.plan.sort"))) then return end
    since = tonumber(since) or 0
    if not finite(since) or since < 0 then since = 0 end
    if pendingReply[sender] then return end
    if syncServed[sender] and GetTime() - syncServed[sender] < 120 then return end
    -- serve at most 6 full syncs per minute in total (many senders at once = flood)
    if GetTime() - syncWin > 60 then syncWin, syncWinN = GetTime(), 0 end
    if syncWinN >= 6 then return end
    syncWinN = syncWinN + 1
    local direct = channel == "WHISPER"
    -- authorized members (raid assistant and up) answer first: only their relaying of leadership/raid data counts
    local priv = ns.isOfficer() or (ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.plan.sort"))
    local delay = direct and 0.3 or (math.random(3, 20) / 10 + (priv and 0 or 2.5))
    pendingReply[sender] = true
    ns.After(delay, function()
        if pendingReply[sender] ~= true and not retry then pendingReply[sender] = nil return end
        pendingReply[sender] = nil
        if not direct then Comm.Guild("SYNCACK", sender) end
        syncServed[sender] = GetTime()
        -- counter-request ("back"): I'm the newcomer and may have data that ALL present members
        -- don't know yet (e.g. changed offline) -> to the whole guild, not only to the asker
        Comm.BusyPeer(sender)
        sendAllTo(sender, since, back == "1")
        -- always send completion, even if nothing new was included ("up to date")
        Comm.Whisper(sender, "SYNCDONE")
        Comm.MarkPeer(sender, "o")
        if back ~= "1" and not askedBack[sender] then
            askedBack[sender] = true
            local mine = math.max(0, (Comm.prevAlive or 0) - 3600)
            ns.After(3, function() Comm.Whisper(sender, "SYNCREQ", mine, "1") end)
        end
    end)
end)
-- remember sync per member (0.5.515): i = got data from them, o = sent data to them
-- key = first name (Forever: sender "First-Realm", guild list "First Last-Realm")
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
-- is a sync with them running right now? (data coming/going, until 3 s after the last packet)
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
-- last sync with a member: time (max), received, sent, just now (animation)
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
    -- someone else is already answering (only credible via the guild channel)
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
    -- nobody answers (nobody with Oasis online): don't show "syncing" forever
    -- forged SYNCACKs can suppress answers: after 8 s without completion ask once more
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

-- Sync tick (safety net): every ~10 minutes everyone sends a tiny summary

-- per collection ("count:latest time"). Whoever sees that someone else is ahead in a collection

-- fetches only that collection. This way everything lost on the way arrives

-- (loading screen, connection lost, full send queue, incomplete login sync).

-- Brakes: not in combat/instances, per collection at most one request every 5 min,

-- per asker and collection at most one answer every 2 min.

------------------------------------------------------------------------

local DIG_EVERY = 600
-- After login: request important small collections individually and COMPLETELY (since 0) - "DIGREQ" is understood by
-- older Oasis versions too. This way e.g. a poll created on another PC arrives.
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

local digAsked = {}     -- collection -> GetTime() of the last own request

local digServed = {}    -- "Name|Collection" -> GetTime() of the last answer

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

            -- they're ahead: newer changes, or equally new but more entries (I'm missing older ones)

            local newer = top > myTop + 2

            local more = (not newer) and n > myN and top >= myTop

            local different = fingerprint and fingerprint ~= "" and fingerprint ~= myFingerprint and n == myN and top == myTop
            if (newer or more or different) and GetTime() - (digAsked[name] or -999) > 300 then

                digAsked[name] = GetTime()

                local since = newer and math.max(0, myTop - 3600) or 0

                -- wait briefly at random: if more than one sees the same gap, not everyone asks at once

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

    -- first tick after the login sync, then every ~10 min (randomized so not everyone sends at once)

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
    ns.print(L["Full sync requested."])
end

-- clean up "already seen" lists: entries whose record no longer exists, or that are very old
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
    -- rank protection: state of people who haven't shown up for a year
    for key, r in pairs(db.rankSeen or {}) do
        if type(r) == "table" and (r.ts or 0) < now - 365 * 86400 then db.rankSeen[key] = nil end
    end
    -- outside players: forget after 90 days (unless favorite or with a note)
    for name, a in pairs(db.allies or {}) do
        if type(a) == "table" and not a.fav and (a.note or "") == "" and not a.demo and (a.last or 0) < now - 90 * 86400 then
            db.allies[name] = nil
        end
    end
end

-- don't store helper fields ("_src", "_makers" ...) that pages attach to records for display
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
    -- when was I last online? (for the counter-request to others)
    Comm.prevAlive = ns.db.meta.lastAlive or ns.db.meta.lastSync or 0
    ns.db.meta.lastAlive = ns.now()
    ns.Every(60, function() ns.db.meta.lastAlive = ns.now() end)
    ns.After(3, function() Comm.RequestSync(false) end)
    ns.Every(600, prune)
end)

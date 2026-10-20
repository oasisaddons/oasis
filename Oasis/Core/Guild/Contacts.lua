-- Oasis - Oasis-Kontakte: Oasis-Nutzer ausserhalb der Gilde merken (ueber den Gruppenkanal)
-- WoW Forever stellt Addon-Fluestern nicht zu; PARTY/RAID funktioniert. Deshalb tauschen Gruppenmitglieder
-- ein kleines "OCHI"-Paket aus: Version, Klasse, Level, Volk, Rollen und (nur solange in der Gruppe) Quest-IDs.
-- Gespeichert in ns.db.oasisContacts[name] = { cls, lvl, race, v, seen, roles, qs }; nach 180 Tagen weg.
local ADDON, ns = ...
local K, C, L = ns.K, ns.K.C, ns.L
local Comm = ns.Comm

local Contacts = {}
ns.Contacts = Contacts

local KEEP_DAYS = 180
local MAX_CONTACTS = 400

local function db()
    if not ns.db then return {} end
    ns.db.oasisContacts = ns.db.oasisContacts or {}
    return ns.db.oasisContacts
end
Contacts.DB = db

function Contacts.Get(name)
    if not name then return nil end
    local t = db()
    local c = t[name]
    if c then return c end
    -- auch ohne Realm-Teil finden ("Fremdi" == "Fremdi-Realm" auf dem eigenen Realm)
    local full = ns.fullName and ns.fullName(name)
    return full and t[full] or nil
end

-- eigene Daten fuer das Paket
local function myRoles()
    local P = ns.Profile
    if P and P.RolesOf then
        local r = P.RolesOf(ns.me())
        if type(r) == "table" then
            local s = ""
            if r.tank then s = s .. "t" end
            if r.heal then s = s .. "h" end
            if r.dps then s = s .. "d" end
            return s
        end
    end
    return ""
end
local function myRace()
    local _, _, id = UnitRace and UnitRace("player")
    return tonumber(ns.safe(id)) or 0
end

-- senden (gedrosselt): beim Gruppenbeitritt / Aenderung und als Antwort auf ein neues Paket
local lastSend = 0
function Contacts.Send(force)
    local ch = ns.groupChannel and ns.groupChannel()
    if not ch then return false end
    local now = GetTime()
    if not force and now - lastSend < 15 then return false end
    lastSend = now
    local _, cls = UnitClass("player")
    local qs = ns.Social and ns.Social.EncodeQuests and ns.Social.EncodeQuests() or ""
    Comm.SendEx({ ch = ch, key = "ochi" }, "OCHI", ns.version or "", ns.safe(cls) or "", ns.safe(UnitLevel("player")) or 0,
        myRace(), myRoles(), qs)
    return true
end
local sendPending = false
local function sendSoon(delay)
    if sendPending then return end
    sendPending = true
    ns.After(delay or (2 + math.random() * 3), function() sendPending = false Contacts.Send() end)
end
Contacts.SendSoon = sendSoon

-- gehoert der Name zu meiner Gruppe?
function Contacts.InGroup(name)
    if not name then return false end
    local s = ns.ChatName and ns.ChatName(name) or ns.short(name)
    return ((UnitInParty and UnitInParty(s)) or (UnitInRaid and UnitInRaid(s))) and true or false
end

-- Empfang: nur ueber den Gruppenkanal, Felder streng pruefen
local GROUP_CH = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local answered = {}
Comm.On("OCHI", function(sender, channel, v, cls, lvl, race, roles, qs)
    local raw = Comm.rawChannel or channel
    if not GROUP_CH[raw] or not sender or ns.isMe(sender) then return end
    v = tostring(v or "")
    if not (v:match("^%d+%.%d+%.?%d*$") and #v <= 16) then v = nil end
    cls = tostring(cls or "")
    if not (cls:match("^%u+$") and #cls <= 16) then cls = nil end
    lvl = tonumber(lvl)
    if lvl then lvl = math.max(1, math.min(200, math.floor(lvl))) end
    race = tonumber(race)
    if race then race = math.max(0, math.min(200, math.floor(race))) end
    roles = tostring(roles or ""):gsub("[^thd]", ""):sub(1, 3)
    -- Quest-IDs: nur Ziffern und Kommas, hoechstens 30 Stueck
    local ids = {}
    for id in tostring(qs or ""):gmatch("%d+") do
        if #ids >= 30 then break end
        if #id <= 7 then ids[#ids + 1] = id end
    end
    local t = db()
    local c = t[sender]
    if not c then
        -- Speicher begrenzen: aeltesten Kontakt verdraengen
        local n, oldest, oldT = 0, nil, math.huge
        for k, x in pairs(t) do
            n = n + 1
            if (x.seen or 0) < oldT then oldest, oldT = k, x.seen or 0 end
        end
        if n >= MAX_CONTACTS and oldest then t[oldest] = nil end
        c = {}
        t[sender] = c
    end
    c.v = v or c.v
    c.cls = cls or c.cls
    c.lvl = lvl or c.lvl
    c.race = race or c.race
    c.roles = roles
    c.qs = table.concat(ids, ",")
    c.seen = ns.now()
    c.guild = (ns.Comm.FromGuild and ns.Comm.FromGuild(sender)) or nil
    -- einmal je Absender und Minute antworten, damit beide Seiten sich kennen
    if not answered[sender] or GetTime() - answered[sender] > 60 then
        answered[sender] = GetTime()
        sendSoon(1 + math.random() * 2)
    end
    ns.Fire("CONTACTS_CHANGED", sender)
    if ns.RefreshPage then ns.RefreshPage("noguild") ns.RefreshPage("social") ns.RefreshPage("deathroll") end
end)

-- Gruppe gewechselt: senden; wer nicht mehr in der Gruppe ist, verliert die Quest-Liste
ns.On("GROUP_ROSTER_UPDATE", function()
    local t = db()
    for name, c in pairs(t) do
        if c.qs and c.qs ~= "" and not Contacts.InGroup(name) then c.qs = nil end
    end
    if ns.groupChannel and ns.groupChannel() then sendSoon() end
end)
-- Quests geaendert: in der Gruppe neu melden (gedrosselt)
for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    ns.On(ev, function() if ns.groupChannel and ns.groupChannel() then sendSoon(4) end end)
end

-- aufraeumen: nach 180 Tagen ohne Kontakt weg; Quest-Listen nie ueber den Login hinaus
ns.Listen("LOGIN", function()
    local t = db()
    local cut = ns.now() - KEEP_DAYS * 86400
    for name, c in pairs(t) do
        if type(c) ~= "table" or (c.seen or 0) < cut then t[name] = nil else c.qs = nil end
    end
    ns.After(6, function() if ns.groupChannel and ns.groupChannel() then Contacts.Send(true) end end)
end)

-- Freundesliste: online?
function Contacts.FriendOnline(name)
    if not (C_FriendList and C_FriendList.GetFriendInfo) then return false, false end
    local ok, info = pcall(C_FriendList.GetFriendInfo, ns.ChatName and ns.ChatName(name) or ns.short(name))
    if not ok or type(info) ~= "table" then return false, false end
    return info.connected and true or false, true
end

-- Liste fuer Anzeigen: zuletzt gesehen zuerst; Gildenmitglieder nur auf Wunsch
function Contacts.List(withGuild)
    local out = {}
    for name, c in pairs(db()) do
        local inGuild = ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, name) ~= nil
        if withGuild or not inGuild then
            local on, friend = Contacts.FriendOnline(name)
            local grp = Contacts.InGroup(name)
            out[#out + 1] = { name = name, c = c, online = on or grp, friend = friend, group = grp }
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.c.seen or 0) > (b.c.seen or 0)
    end)
    return out
end

-- Deathroll-Gegner ohne Gilde: Gruppenmitglieder + Oasis-Kontakte, die Freund und online sind
function Contacts.Candidates()
    local out, seen = {}, {}
    local function addUnit(u)
        if not (UnitExists and UnitExists(u)) or (UnitIsUnit and UnitIsUnit(u, "player")) then return end
        local n, realm = UnitFullName and ns.UnitFullName(u)
        n, realm = ns.safe(n), ns.safe(realm)
        if not n then n = ns.safe(ns.UnitName(u)) end
        if not n then return end
        local full = ns.fullName(realm and realm ~= "" and (n .. "-" .. realm) or n)
        if seen[full] then return end
        seen[full] = true
        local _, cls = UnitClass(u)
        local c = Contacts.Get(full)
        out[#out + 1] = { name = full, class = ns.safe(cls) or (c and c.cls), oasis = c ~= nil, group = true }
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do addUnit("raid" .. i) end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do addUnit("party" .. i) end
    end
    for name, c in pairs(db()) do
        if not seen[name] and not ns.isMe(name) then
            local on = Contacts.FriendOnline(name)
            if on then
                seen[name] = true
                out[#out + 1] = { name = name, class = c.cls, oasis = true, friend = true }
            end
        end
    end
    return out
end

-- kurzer Tooltip-Text
function Contacts.TipLine(c)
    if not c then return nil end
    return (L["uses Oasis (version %s, last seen %s)"]):format(c.v or "?", ns.ago and ns.ago(c.seen or 0) or "?")
end
Contacts.LOGO = "|T" .. ns.MEDIA .. "logo64:12:12|t"

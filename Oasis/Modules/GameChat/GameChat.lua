-- Oasis: Spielchat - Blizzards Chatfenster lesbarer machen
-- Namen kuerzen, Stufe und Klassen-/Volkssymbol vor dem Namen, Symbole an Item- und Zauberlinks, Filter und
-- Stummschaltungen, Suche mit Kopieren, Verlauf ueber Sitzungen und Stichwort-Alarme.
-- Forever ist streng: Blizzards AddMessage wird NIE ersetzt. Oasis schaut per hooksecurefunc nach und aendert oder
-- entfernt die Zeile erst danach ueber die oeffentlichen Methoden des Chatfensters (TransformMessages,
-- RemoveMessagesByPredicate). Geheime Werte (Kampf) werden nie gelesen, verglichen oder veraendert.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Spielchat", function()   -- Modul Spielchat (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L

local GC = {}
ns.GameChat = GC

local DEFAULTS = {
    gcOn = true,   -- 0.6.4: Standard an (vorher aus)
    gcShort = false, gcLevel = true, gcClassIcon = false, gcRaceIcon = false,
    gcLinkIcons = true, gcTokens = true, gcChNum = false, gcQuiet = false, gcHover = false,
    gcFilter = false, gcWhole = false, gcCyr = false, gcHan = false, gcRepeat = false, gcRepeatSec = 60,
    gcHist = false, gcHistLines = 100,   -- 0.6.104: Verlauf nach /reload Standard aus (wirkte grau und doppelt)
    gcAlert = true, gcAlertSound = true,
    gcHideMenu = false, gcHideChannel = false, gcHideSocial = false, gcHideScroll = false,
}
local LISTS = { "gcPhrases", "gcMutes", "gcWords" }
local MAX_LIST, MAX_ENTRY = 50, 100
local BUF_MAX = 500            -- Zeilen je Chatfenster fuer die Suche (nur diese Sitzung)
local HIST_AGE = 7 * 86400     -- gespeicherter Verlauf verfaellt nach 7 Tagen
local LINE_MAX = 4096

local ready = false
local function G()
    local s = ns.db.settings
    if not ready then
        ready = true
        for k, v in pairs(DEFAULTS) do if s[k] == nil then s[k] = v end end
        -- 0.6.4: der alte Standard "aus" stand schon gespeichert -> einmal einschalten; spaeteres Aus bleibt
        if not s.gcOnV2 then s.gcOnV2 = true s.gcOn = true end
        -- 0.6.104: Verlauf nach /reload einmal aus (stand bei allen noch auf dem alten Standard an)
        if not s.gcHistV2 then s.gcHistV2 = true s.gcHist = false end
        for _, k in ipairs(LISTS) do if type(s[k]) ~= "table" then s[k] = {} end end
    end
    return s
end
GC.G = G

------------------------------------------------------------------------
-- Geheime Werte: alles, was nicht lesbar ist, wird zu nil
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function str(v)
    if v == nil or issecret(v) or type(v) ~= "string" then return nil end
    return v
end
local function num(v)
    if v == nil or issecret(v) or type(v) ~= "number" then return nil end
    return v
end
local function tbl(v)
    if v == nil or issecret(v) or type(v) ~= "table" then return nil end
    if canaccesstable and not canaccesstable(v) then return nil end
    return v
end

-- Anzeigetext ohne Farben, Links und Symbole (Suche, Verlauf, Alarme)
function GC.Plain(text)
    -- 0.6.103: Oasis-Emojis werden zu ihrem Kurzcode (sonst fehlten sie im Verlauf nach /reload und beim Kopieren)
    if text:find("oasisemo:", 1, true) and ns.Emoji and ns.Emoji.CodeOf then
        text = text:gsub("|Haddon:oasisemo:([^|]+)|h.-|h", function(k) return ns.Emoji.CodeOf((k:gsub("~", "\\"))) or "" end)
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "?")
    return (text:gsub("||", "|"):gsub("  +", " "))
end
-- fn nur auf die Teile ausserhalb von Links anwenden
local function mapPlain(text, fn)
    local out, pos = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", pos)
        if not s then
            out[#out + 1] = fn(text:sub(pos))
            break
        end
        out[#out + 1] = fn(text:sub(pos, s - 1))
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    return table.concat(out)
end
GC.MapPlain = mapPlain

------------------------------------------------------------------------
-- Stufen: was der Client ohnehin zeigt (Ziel, Maus, Gruppe, Gilde, Freunde, /wer) - nur fuer diese Sitzung
------------------------------------------------------------------------
local levels, levelCount = {}, 0
local function nameKey(name) return (name:gsub("%-[^%-]*$", "")):lower() end
GC.NameKey = nameKey
local function remember(name, lvl)
    name, lvl = str(name), num(lvl)
    if not name or name == "" or not lvl or lvl < 1 or lvl > 255 then return end
    local k = nameKey(name)
    if levels[k] == nil then
        levelCount = levelCount + 1
        if levelCount > 4000 then levels, levelCount = {}, 1 end
    end
    levels[k] = lvl
end
GC.Remember = remember
function GC.LevelOf(name)
    name = str(name)
    return name and levels[nameKey(name)] or nil
end
local function noteUnit(unit)
    pcall(function()
        if not UnitExists(unit) or not ns.safe(UnitIsPlayer(unit)) then return end
        remember(ns.UnitName(unit), UnitLevel(unit))
    end)
end
local guildAt = 0
local function scanGuild()
    if not GetNumGuildMembers or not GetGuildRosterInfo or GetTime() - guildAt < 60 then return end
    guildAt = GetTime()
    pcall(function()
        for i = 1, math.min(num(GetNumGuildMembers()) or 0, 1000) do
            local name, _, _, lvl = GetGuildRosterInfo(i)
            remember(name, lvl)
        end
    end)
end
local function scanFriends()
    local F = C_FriendList
    if not F or not F.GetNumFriends or not F.GetFriendInfoByIndex then return end
    pcall(function()
        for i = 1, math.min(num(F.GetNumFriends()) or 0, 200) do
            local info = tbl(F.GetFriendInfoByIndex(i))
            if info then remember(info.name, info.level) end
        end
    end)
end
local function scanWho()
    local F = C_FriendList
    if not F or not F.GetNumWhoResults or not F.GetWhoInfo then return end
    pcall(function()
        for i = 1, math.min(num(F.GetNumWhoResults()) or 0, 100) do
            local info = tbl(F.GetWhoInfo(i))
            if info then remember(info.fullName, info.level) end
        end
    end)
end
local function scanGroup()
    noteUnit("player")
    for i = 1, 4 do noteUnit("party" .. i) end
    if IsInRaid and IsInRaid() then for i = 1, 40 do noteUnit("raid" .. i) end end
end

------------------------------------------------------------------------
-- Darstellung
------------------------------------------------------------------------
local function atlasOk(name)
    if type(name) ~= "string" or not C_Texture or not C_Texture.GetAtlasInfo then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end
local function atlasMark(name, size)
    if not atlasOk(name) then return "" end
    return "|A:" .. name .. ":" .. size .. ":" .. size .. ":0:" .. (-math.floor(size * 0.2 + 0.5)) .. "|a"
end
local function fontHeight(frame)
    local h = 14
    pcall(function()
        local _, fh = frame:GetFont()
        if num(fh) then h = fh end
    end)
    return math.max(8, math.floor(h + 0.5))
end
-- Volk und Klasse des Absenders (ueber die GUID der Nachricht)
local function senderIcons(args, size, s)
    local guid = str(args[12])
    if not guid or not GetPlayerInfoByGUID then return "" end
    local ok, _, class, _, race, sex = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return "" end
    local out = ""
    class, race, sex = str(class), str(race), num(sex)
    if s.gcRaceIcon and race and GetRaceAtlas and (sex == 2 or sex == 3) then
        local okA, a = pcall(GetRaceAtlas, race:lower(), sex == 2 and "male" or "female")
        if okA then out = atlasMark(a, size) end
    end
    if s.gcClassIcon and class and GetClassAtlas then
        local okA, a = pcall(GetClassAtlas, class:lower())
        local m = okA and atlasMark(a, size) or ""
        if m ~= "" then out = out .. m end
    end
    return out ~= "" and (out .. " ") or ""
end
local function hexByte(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
local function hexColor(r, g, b) return ("|cff%02x%02x%02x"):format(hexByte(r), hexByte(g), hexByte(b)) end
local function levelMark(lvl)
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
    local r, g, b = 0.8, 0.8, 0.8
    if type(c) == "table" and num(c.r) then r, g, b = c.r, c.g, c.b end
    return hexColor(r, g, b) .. "[" .. math.floor(lvl) .. "]|r "
end
-- Kuerzel im Text: :mage: :troll: :trollf: -> Symbol (nur lokal, verschickt wird der Text)
local CLASSES = { warrior = 1, paladin = 1, hunter = 1, rogue = 1, priest = 1, shaman = 1, mage = 1, warlock = 1, druid = 1,
    deathknight = 1, monk = 1, demonhunter = 1, evoker = 1 }
local RACES = { human = "human", orc = "orc", dwarf = "dwarf", nightelf = "nightelf", undead = "scourge", scourge = "scourge",
    tauren = "tauren", gnome = "gnome", troll = "troll", goblin = "goblin", bloodelf = "bloodelf", draenei = "draenei",
    worgen = "worgen", pandaren = "pandaren" }
local function shortcut(key, size)
    key = key:lower()
    local a
    if CLASSES[key] and GetClassAtlas then
        local ok, r = pcall(GetClassAtlas, key)
        a = ok and r or nil
    elseif GetRaceAtlas then
        local race, gender = RACES[key], "male"
        if not race and #key > 2 then
            local tail = key:sub(-1)
            race = (tail == "f" or tail == "m") and RACES[key:sub(1, -2)] or nil
            if tail == "f" then gender = "female" end
        end
        if race then
            local ok, r = pcall(GetRaceAtlas, race, gender)
            a = ok and r or nil
        end
    end
    local m = a and atlasMark(a, size) or ""
    return m ~= "" and m or nil
end
local function itemLink(id)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not get then return nil end
    local ok, _, link = pcall(get, id)
    return ok and str(link) or nil
end
local function spellLink(id)
    local get = C_Spell and C_Spell.GetSpellLink or GetSpellLink
    if not get then return nil end
    local ok, link = pcall(get, id)
    return ok and str(link) or nil
end
local function tokens(seg, size)
    if seg:find("item:%d") then
        seg = seg:gsub("%f[%a]item:(%d+)", function(id) return itemLink(tonumber(id)) end)
    end
    if seg:find("spell:%d") then
        seg = seg:gsub("%f[%a]spell:(%d+)", function(id) return spellLink(tonumber(id)) end)
    end
    if seg:find(":%a+:") then
        seg = seg:gsub(":(%a+):", function(k) return shortcut(k, size) end)
    end
    return seg
end
local function texMark(tex) return tex and ("|T" .. tex .. ":0|t") or nil end
local function linkIcons(text)
    if text:find("|Hitem:", 1, true) then
        local get = C_Item and C_Item.GetItemIconByID or GetItemIcon
        text = text:gsub("|Hitem:(%d+)", function(id)
            local ok, tex = pcall(get, tonumber(id))
            local m = ok and texMark(num(tex) or str(tex))
            return m and (m .. "|Hitem:" .. id) or nil
        end)
    end
    if text:find("|Hspell:", 1, true) then
        local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
        text = text:gsub("|Hspell:(%d+)", function(id)
            local ok, tex = pcall(get, tonumber(id))
            local m = ok and texMark(num(tex) or str(tex))
            return m and (m .. "|Hspell:" .. id) or nil
        end)
    end
    return text
end
-- nur die Beschriftung des Spielerlinks kuerzen (Vorname); das Fluesterziel im Link bleibt vollstaendig
local function shortLabel(label)
    return (label:gsub("([^%s%[%]|%-]+)[%s%-][^%]|]+", "%1", 1))
end
GC.ShortLabel = shortLabel

-- fertige Chatzeile umbauen; liefert die neue Zeile und (fuer "ruhigen Text") das Ende des Kopfes
function GC.Decorate(text, event, args, size, s)
    local out = text
    if s.gcTokens then out = mapPlain(out, function(seg) return tokens(seg, size) end) end
    if s.gcLinkIcons then out = linkIcons(out) end
    local sender = args and str(args[2])
    local ls, le = out:find("|Hplayer:[^|]+|h.-|h")
    local headEnd
    if ls and sender and sender ~= "" then
        local head, label = out:sub(ls, le):match("^(|Hplayer:[^|]+|h)(.-)|h$")
        if head then
            if s.gcShort then label = shortLabel(label) end
            local pre = ""
            if s.gcRaceIcon or s.gcClassIcon then pre = senderIcons(args, size, s) end
            if s.gcLevel then
                local lvl = GC.LevelOf(sender)
                if lvl then pre = pre .. levelMark(lvl) end
            end
            local before = out:sub(1, ls - 1)
            if s.gcChNum and event == "CHAT_MSG_CHANNEL" then before = before:gsub("%[(%d+)%. [^%]]+%]", "[%1]", 1) end
            local link = head .. label .. "|h"
            out = before .. pre .. link .. out:sub(le + 1)
            headEnd = #before + #pre + #link
        end
    end
    return out, headEnd
end
-- "ruhiger Text": Kanal und Name behalten die Kanalfarbe, die Nachricht selbst wird neutral
local QUIET = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true }
function GC.Quiet(text, headEnd, r, g, b)
    local cc = hexColor(r, g, b)
    local head = text:sub(1, headEnd):gsub("|r", "|r" .. cc)
    return cc .. head .. "|r" .. text:sub(headEnd + 1), 0.82, 0.82, 0.82
end

------------------------------------------------------------------------
-- Filter: gesperrte Woerter, Schriftsysteme, Stummschaltung je Kanal, Wiederholungen
------------------------------------------------------------------------
local FILTERED = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true, CHAT_MSG_WHISPER = true }
GC.hidden = 0
local function hasPhrase(body, phrase, whole)
    local from = 1
    while true do
        local s, e = body:find(phrase, from, true)
        if not s then return false end
        if not whole then return true end
        local a, b = body:sub(s - 1, s - 1), body:sub(e + 1, e + 1)
        if not a:find("[%w\128-\255]") and not b:find("[%w\128-\255]") then return true end
        from = e + 1
    end
end
function GC.BlockedText(body, s)
    local low = body:lower()
    for _, p in ipairs(s.gcPhrases) do
        if p ~= "" and hasPhrase(low, p, s.gcWhole) then return true end
    end
    -- Kyrillisch: U+0400-U+052F
    if s.gcCyr and body:find("[\208-\212][\128-\191]") then return true end
    -- chinesische Schriftzeichen (Han): U+4E00-U+9FFF und die Ergaenzungsebene
    if s.gcHan and (body:find("[\228-\233][\128-\191][\128-\191]") or body:find("\240[\160-\174][\128-\191][\128-\191]")) then return true end
    return false
end
function GC.MuteKey(channel, name)
    return channel:lower():gsub("^%s+", ""):gsub("%s+$", "") .. ";" .. name:lower():gsub("^%s+", ""):gsub("%s+$", "")
end
local recent, recentN = {}, 0          -- [Absender|Kanal|Text] = Zeit der letzten gezeigten Nachricht
local decided, decidedN = {}, 0        -- [Zeilen-ID] = versteckt? (dieselbe Nachricht in mehreren Reitern)
local function repeated(sender, channel, body, id, s)
    if decided[id] ~= nil then return decided[id] end
    local now = GetTime()
    local key = sender .. "\1" .. channel .. "\1" .. body
    local last = recent[key]
    local hide = last ~= nil and now - last < (tonumber(s.gcRepeatSec) or 60)
    if not hide then
        if last == nil then
            recentN = recentN + 1
            if recentN > 256 then recent, recentN = {}, 1 end
        end
        recent[key] = now
    end
    decidedN = decidedN + 1
    if decidedN > 256 then decided, decidedN = {}, 1 end
    decided[id] = hide
    return hide
end
function GC.ShouldHide(event, args, s)
    if not s.gcFilter or not FILTERED[event] then return false end
    local body, sender = str(args[1]), str(args[2])
    if not body or not sender or sender == "" or ns.isMe(sender) then return false end
    if GC.BlockedText(body, s) then return true end
    if event ~= "CHAT_MSG_CHANNEL" then return false end
    local channel = str(args[9])
    if not channel or channel == "" then return false end
    -- eingebaute Kanaele tragen das Gebiet im Namen ("Handel - Orgrimmar")
    local zone = num(args[7])
    if zone and zone > 0 then channel = channel:gsub("%s%-%s.*$", "") end
    if #s.gcMutes > 0 then
        local key = GC.MuteKey(channel, sender)
        local keyShort = GC.MuteKey(channel, (sender:gsub("%-[^%-]*$", "")))
        for _, m in ipairs(s.gcMutes) do
            if m == key or m == keyShort then return true end
        end
    end
    local id = num(args[11])
    if s.gcRepeat and id and id > 0 then return repeated(sender:lower(), channel:lower(), body, id, s) end
    return false
end

------------------------------------------------------------------------
-- Zwischenspeicher je Chatfenster (Suche) und Verlauf ueber Sitzungen
------------------------------------------------------------------------
local buffers = setmetatable({}, { __mode = "k" })   -- [Chatfenster] = { Zeilen }
local function push(frame, plain, r, g, b)
    local buf = buffers[frame]
    if not buf then buf = {} buffers[frame] = buf end
    if #plain > 1024 then plain = plain:sub(1, 1024) end
    buf[#buf + 1] = { t = plain, ts = time(), r = r, g = g, b = b }
    if #buf > BUF_MAX + 50 then
        local keep = {}
        for i = #buf - BUF_MAX + 1, #buf do keep[#keep + 1] = buf[i] end
        buffers[frame] = keep
    end
end
function GC.Buffer(frame) return buffers[frame] or {} end
-- Ohne mitgeschriebenen Puffer (Spielchat aus): Zeilen direkt aus dem Chatfenster lesen, geheime ueberspringen
local function frameLines(frame)
    local out, n = {}, 0
    pcall(function() n = num(frame:GetNumMessages()) or 0 end)
    for i = math.max(1, n - BUF_MAX + 1), n do
        local ok, text = pcall(frame.GetMessageInfo, frame, i)
        text = ok and str(text) or nil
        if text then
            local okP, plain = pcall(GC.Plain, text)
            if okP and plain ~= "" then out[#out + 1] = { t = plain } end
        end
    end
    return out
end
function GC.Search(frame, query)
    local out = {}
    query = (query or ""):lower()
    local buf = buffers[frame]
    if not buf or #buf == 0 then buf = frameLines(frame) end
    for _, l in ipairs(buf) do
        if query == "" or l.t:lower():find(query, 1, true) then out[#out + 1] = l end
    end
    return out
end
local function tabName(frame)
    local name
    pcall(function()
        local id = frame:GetID()
        name = str((GetChatWindowInfo(id)))
    end)
    return name or ""
end
GC.TabName = tabName
local function chatFrames()
    local out = {}
    for _, n in ipairs(CHAT_FRAMES or {}) do
        local f = _G[n]
        if f and f ~= ChatFrame2 and f.AddMessage and not (f.IsForbidden and f:IsForbidden()) then out[#out + 1] = f end
    end
    return out
end
GC.Frames = chatFrames
local function saveHistory()
    if not ns.char then return end
    local s = G()
    if not s.gcOn or not s.gcHist then ns.char.gcHist = nil return end
    local keep = math.max(20, math.min(300, tonumber(s.gcHistLines) or 100))
    local frames = {}
    for _, f in ipairs(chatFrames()) do
        local buf, id = buffers[f], f:GetID()
        if buf and #buf > 0 and not f.isTemporary and id then
            local lines = {}
            for i = math.max(1, #buf - keep + 1), #buf do
                local l = buf[i]
                lines[#lines + 1] = { t = l.t, ts = l.ts, r = l.r, g = l.g, b = l.b }
            end
            frames[id] = { n = tabName(f), l = lines }
        end
    end
    ns.char.gcHist = { ts = time(), f = frames }
end
local busy = false   -- eigene Zeilen (Verlauf) nicht wieder einlesen
local function restoreHistory()
    local s = G()
    local h = ns.char and ns.char.gcHist
    if not s.gcOn or not s.gcHist or type(h) ~= "table" or type(h.f) ~= "table" then return end
    if ns.ForeignChat and ns.ForeignChat() then return end   -- 0.6.254
    local age = time() - (tonumber(h.ts) or 0)
    if age > HIST_AGE then ns.char.gcHist = nil return end
    for _, f in ipairs(chatFrames()) do
        local id = f:GetID()
        local saved = id and h.f[id]
        -- nach /reload stellt "Chat nach /reload behalten" das Hauptfenster schon selbst wieder her
        local skip = f == ChatFrame1 and s.cfChatRestore and age < 600
        if saved and not skip and type(saved.l) == "table" and saved.n == tabName(f) then
            busy = true
            pcall(function()
                f:AddMessage("|cff666666- - - " .. (L["Chat vom %s"]):format(date("%d.%m. %H:%M", h.ts)) .. " - - -|r")
                for _, l in ipairs(saved.l) do
                    if type(l.t) == "string" then
                        -- 0.6.103: steht schon eine Uhrzeit vorn (Blizzard-Zeitstempel), keine zweite davor
                        local stamp = (l.ts and not l.t:find("^%[?%d%d?:%d%d")) and date("[%H:%M] ", l.ts) or ""
                        local line = stamp .. l.t:gsub("|", "||")
                        if ns.Emoji and ns.Emoji.Render then
                            local okR, r = pcall(ns.Emoji.Render, line)
                            if okR and r then line = r end
                        end
                        f:AddMessage(line, (l.r or 1) * 0.72, (l.g or 1) * 0.72, (l.b or 1) * 0.72)
                    end
                end
                f:AddMessage("|cff666666- - - - - - - - - - -|r")
            end)
            busy = false
            -- wieder durchsuchbar machen
            for _, l in ipairs(saved.l) do
                if type(l.t) == "string" then push(f, l.t, l.r, l.g, l.b) buffers[f][#buffers[f]].ts = l.ts or time() end
            end
        end
    end
end

------------------------------------------------------------------------
-- Stichwort-Alarme
------------------------------------------------------------------------
GC.hits = {}
local alerted, alertedN = {}, 0
local toastAt = 0
local ALERT_EVENTS = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_WHISPER = true, CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_EMOTE = true, CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true }
function GC.MatchWord(body, s)
    local low = body:lower()
    for _, w in ipairs(s.gcWords) do
        if w ~= "" and low:find(w, 1, true) then return w end
    end
end
local function checkAlert(event, args, plain, s)
    if not s.gcAlert or #s.gcWords == 0 or not ALERT_EVENTS[event] then return end
    local sender = str(args[2])
    if sender and ns.isMe(sender) then return end
    local word = GC.MatchWord(GC.Plain(str(args[1]) or plain), s)
    if not word then return end
    -- dieselbe Nachricht steht oft in mehreren Reitern
    local id = num(args[11]) or plain
    if alerted[id] then return end
    alertedN = alertedN + 1
    if alertedN > 300 then alerted, alertedN = {}, 1 end
    alerted[id] = true
    local hits = GC.hits
    hits[#hits + 1] = { t = plain, ts = time(), w = word }
    if #hits > 100 then table.remove(hits, 1) end
    if GetTime() - toastAt >= 4 and ns.K and ns.K.Toast then
        toastAt = GetTime()
        pcall(ns.K.Toast, (L["Chat-Alarm: %s"]):format(word), plain, nil, function() if GC.OpenViewer then GC.OpenViewer("alerts") end end,
            s.gcAlertSound and "toast" or "none")
    end
    if GC.viewer and GC.viewer:IsShown() and GC.viewer.mode == "alerts" then GC.viewer:Refresh() end
end

------------------------------------------------------------------------
-- Nachsehen, was Blizzard gerade ins Chatfenster geschrieben hat
------------------------------------------------------------------------
local function post(frame, text, r, g, b, _, _, _, event, args)
    if busy or not ns.db then return end
    if ns.ForeignChat and ns.ForeignChat() then return end   -- 0.6.254: fremder Chat zeichnet selbst
    local s = G()
    if not s.gcOn then return end
    text = str(text)
    if not text or text == "" or #text > LINE_MAX then return end
    event, args = str(event), tbl(args)
    local chat = event ~= nil and args ~= nil and event:find("^CHAT_MSG_") ~= nil
    -- Chatzeilen ueber ihre Ereignisdaten wiederfinden, nicht ueber den Text: ein anderes Addon kann die Zeile
    -- auf dem Weg ins Fenster schon umgebaut haben (gekuerzte Kanalnamen, gefaerbte Uhrzeit) - dann stimmte der
    -- Text nie ueberein und der Spielchat aenderte gar nichts.
    local function same(message, ...)
        if issecret(message) then return false end
        if chat then
            local a = select(8, ...)
            return not issecret(a) and a == args
        end
        return message == text
    end
    if chat and frame.RemoveMessagesByPredicate and GC.ShouldHide(event, args, s) then
        GC.hidden = GC.hidden + 1
        frame:RemoveMessagesByPredicate(same)
        return
    end
    local shown = text
    if frame.TransformMessages then
        local size = fontHeight(frame)
        local new, headEnd = GC.Decorate(text, event, chat and args or nil, size, s)
        local quiet = s.gcQuiet and headEnd and QUIET[event]
        if new ~= text or quiet then
            shown = new
            frame:TransformMessages(same, function(message, mr, mg, mb, ...)
                local cur, he = new, headEnd
                -- steht im Fenster ein anderer Text als der uebergebene, dann genau den umbauen (sonst ginge die
                -- Aenderung des anderen Addons verloren)
                if message ~= text then
                    cur, he = GC.Decorate(message, event, chat and args or nil, size, s)
                end
                if s.gcQuiet and he and QUIET[event] and num(mr) and num(mg) and num(mb) then
                    local qt, qr, qg, qb = GC.Quiet(cur, he, mr, mg, mb)
                    return qt, qr, qg, qb, ...
                end
                return cur, mr, mg, mb, ...
            end)
        end
    end
    local plain = GC.Plain(shown)
    push(frame, plain, num(r), num(g), num(b))
    if chat then checkAlert(event, args, plain, s) end
    if GC.viewer and GC.viewer:IsShown() and GC.viewer.mode == "search" and GC.viewer.frame == frame then GC.viewer.dirty = true end
end
local hooked = setmetatable({}, { __mode = "k" })
local function itemTip(self, link)
    if not ns.db or not G().gcOn or not G().gcHover then return end
    link = str(link)
    if not link or #link > LINE_MAX or not (link:find("^item:%d") ) then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
        GC.tipOwner = self
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end
local function itemTipHide(self)
    if GC.tipOwner == self then
        GC.tipOwner = nil
        GameTooltip:Hide()
    end
end
function GC.Attach()
    if ns.ForeignChat and ns.ForeignChat() then return end   -- fremde Chat-Ereigniskette nicht zusaetzlich einhaengen
    for _, f in ipairs(chatFrames()) do
        if not hooked[f] then
            hooked[f] = true
            hooksecurefunc(f, "AddMessage", function(self, ...)
                local ok, err = pcall(post, self, ...)
                if not ok and ns.db and ns.db.settings.debug then ns.print("Spielchat: " .. tostring(err)) end
            end)
            if f.HookScript then
                pcall(f.HookScript, f, "OnHyperlinkEnter", itemTip)
                pcall(f.HookScript, f, "OnHyperlinkLeave", itemTipHide)
            end
        end
    end
end

------------------------------------------------------------------------
-- Knoepfe am Chatfenster ausblenden (nur ausserhalb des Kampfes)
------------------------------------------------------------------------
local watched = setmetatable({}, { __mode = "k" })   -- [Knopf] = { key, hid }
local function hideWanted(key)
    local s = G()
    return s.gcOn and s[key] and true or false
end
local function applyButton(btn)
    local st = watched[btn]
    if not st or (btn.IsForbidden and btn:IsForbidden()) or ns.inCombat() then return end
    if hideWanted(st.key) then
        if btn:IsShown() then st.hid = true btn:Hide() end
    elseif st.hid then
        st.hid = nil
        btn:Show()
    end
end
local function watch(btn, key)
    if not btn or (btn.IsForbidden and btn:IsForbidden()) then return end
    if not watched[btn] then
        if not hideWanted(key) then return end
        watched[btn] = { key = key }
        hooksecurefunc(btn, "Show", function(self) if hideWanted(key) then pcall(applyButton, self) end end)
    end
    pcall(applyButton, btn)
end
function GC.ApplyButtons()
    if ns.ForeignChat and ns.ForeignChat() then return end   -- auch Seitenleisten- und Sozialknoepfe gehoeren dem fremden Chat
    if not ns.db or ns.inCombat() then GC.pending = true return end
    watch(ChatFrameMenuButton, "gcHideMenu")
    watch(ChatFrameChannelButton, "gcHideChannel")
    watch(QuickJoinToastButton, "gcHideSocial")
    watch(FriendsMicroButton, "gcHideSocial")
    for _, n in ipairs((ns.ForeignChat and ns.ForeignChat()) and {} or CHAT_FRAMES or {}) do   -- 0.6.257: EllesmereUI steuert die Knoepfe selbst
        local f = _G[n]
        if f then
            for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton", "BottomButton", "ScrollToBottomButton" }) do
                watch(f[suffix] or _G[n .. suffix], "gcHideScroll")
            end
        end
    end
end

------------------------------------------------------------------------
-- Zeitstempel: Blizzards eigene Einstellung (CVar), Oasis merkt sich den vorherigen Wert
------------------------------------------------------------------------
GC.STAMPS = {
    { key = "none", text = "Aus", fmt = "none" },
    { key = "hm", text = "14:05", fmt = "[%H:%M] " },
    { key = "hms", text = "14:05:09", fmt = "[%H:%M:%S] " },
    { key = "12", text = "02:05 PM", fmt = "[%I:%M %p] " },
    { key = "date", text = "13.10. 14:05", fmt = "[%d.%m. %H:%M] " },
}
local function cvar(name, value)
    if value == nil then
        local get = C_CVar and C_CVar.GetCVar or GetCVar
        local ok, v = pcall(get, name)
        return ok and str(v) or nil
    end
    pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, value)
end
function GC.ApplyStamp()
    local s = G()
    local fmt
    for _, st in ipairs(GC.STAMPS) do if st.key == s.gcStamp then fmt = st.fmt end end
    if s.gcOn and fmt and not (ns.ForeignChat and ns.ForeignChat()) then   -- 0.6.257: EllesmereUI hat eigene Zeitstempel (sonst doppelt)
        if s.gcStampNative == nil then s.gcStampNative = cvar("showTimestamps") or "none" end
        cvar("showTimestamps", fmt)
    elseif s.gcStampNative ~= nil then
        cvar("showTimestamps", s.gcStampNative)
        s.gcStampNative = nil
    end
end

------------------------------------------------------------------------
-- Kopier-Knopf oben rechts im Chatfenster: oeffnet den Chat als markierbaren Text (Strg+C)
-- nesUI hat dafuer einen eigenen Knopf in seiner Chatleiste -> dann keinen zweiten
------------------------------------------------------------------------
local function nesUIChat() return _G.nesUI ~= nil and not (_G.nesUIDB and _G.nesUIDB.chatOff) end

------------------------------------------------------------------------
-- 0.6.3: Markieren direkt im Chatfenster. Blizzards Chat kann selbst nichts markieren - Oasis legt ein
-- Eingabefeld mit demselben Text und derselben Schrift genau ueber das Fenster: mit der Maus markieren, Strg+C
-- kopiert, Esc oder Klick daneben schliesst. Das Chatfenster selbst wird nicht veraendert.
------------------------------------------------------------------------
local sel
local function selLines(frame)
    local buf = buffers[frame]
    if not buf or #buf == 0 then buf = frameLines(frame) end
    local out = {}
    for i, l in ipairs(buf) do out[i] = l.t end
    return table.concat(out, "\n")
end
function GC.SelectInPlace(frame)
    frame = frame or SELECTED_CHAT_FRAME or ChatFrame1
    if not frame or not frame.GetFont then return end
    if not sel then
        sel = CreateFrame("Frame", "OasisChatSelect", UIParent)
        sel:SetFrameStrata("DIALOG")
        sel:EnableMouse(true)
        sel.bg = sel:CreateTexture(nil, "BACKGROUND")
        sel.bg:SetAllPoints()
        sel.bg:SetColorTexture(0.03, 0.03, 0.04, 0.92)
        sel.hint = sel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sel.hint:SetPoint("BOTTOMLEFT", sel, "TOPLEFT", 2, 3)
        sel.hint:SetText(L["Text mit der Maus markieren - Strg+C kopiert, Esc schliesst"])
        sel.sc = CreateFrame("ScrollFrame", nil, sel)
        sel.sc:SetAllPoints()
        sel.eb = CreateFrame("EditBox", nil, sel.sc)
        sel.eb:SetMultiLine(true)
        sel.eb:SetAutoFocus(false)
        sel.eb:SetTextInsets(2, 2, 2, 2)
        sel.sc:SetScrollChild(sel.eb)
        -- nur lesen: Tippen setzt den Text sofort zurueck (Markieren und Strg+C bleiben moeglich)
        sel.eb:SetScript("OnTextChanged", function(self, user) if user and sel.text then self:SetText(sel.text) end end)
        sel.eb:SetScript("OnEscapePressed", function() sel:Hide() end)
        sel.eb:SetScript("OnEditFocusLost", function() sel:Hide() end)
        sel.eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
            -- beim Markieren ueber den Rand hinaus mitrollen
            local top, view = sel.sc:GetVerticalScroll(), sel.sc:GetHeight()
            if -y < top then sel.sc:SetVerticalScroll(-y)
            elseif -y + h > top + view then sel.sc:SetVerticalScroll(-y + h - view) end
        end)
        sel.sc:EnableMouseWheel(true)
        sel.sc:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, sel.eb:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 42)))
        end)
        sel:SetScript("OnMouseDown", function() sel.eb:SetFocus() end)
        sel:Hide()
    end
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    sel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    local font, size, flags = frame:GetFont()
    if font then sel.eb:SetFont(font, size or 14, flags or "") end
    sel.eb:SetWidth(math.max(50, (frame:GetWidth() or 300)))
    sel.text = selLines(frame)
    sel:Show()
    sel.eb:SetText(sel.text)
    sel.eb:SetFocus()
    sel.eb:SetCursorPosition(#sel.text)
    -- ans Ende rollen, wenn die Hoehe feststeht (wie der Chat: neueste Zeile unten)
    C_Timer.After(0, function()
        if not sel:IsShown() then return end
        sel.sc:SetVerticalScroll(math.max(0, sel.eb:GetHeight() - sel.sc:GetHeight()))
    end)
end
------------------------------------------------------------------------
-- 0.6.4: Live markieren - mit gedrueckter Maus ueber Chatzeilen ziehen markiert sie (farbig hinterlegt), beim
-- Loslassen liegt der Text markiert in einem unsichtbaren Eingabefeld: Strg+C kopiert. Ein Klick ohne Ziehen
-- bleibt ein normaler Klick (Namen, Links). Seit 0.6.101 buchstabengenau, Rechtsklick auf die Markierung = Menue.
-- Alt + Klick oeffnet weiter das Markierfeld.
------------------------------------------------------------------------
local live = { hl = {} }
-- 0.6.101: buchstabengenau - jede Zeile wird mit derselben Schrift Zeichen fuer Zeichen ausgemessen (Chatfenster
-- verraten nicht, welcher Buchstabe unter der Maus liegt). Nachrichten ueber mehrere Bildschirmzeilen bleiben ganz.
local function cursorXY()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale() or 1
    return x / s, y / s
end
-- sichtbare, lesbare Zeilen eines Chatfensters, oben zuerst
local function shownLines(cf)
    local out = {}
    for _, fs in ipairs(type(cf.visibleLines) == "table" and cf.visibleLines or {}) do
        if fs.IsShown and fs:IsShown() and fs:GetTop() then
            local t = fs:GetText()
            if t and not issecret(t) and t ~= "" then out[#out + 1] = fs end
        end
    end
    table.sort(out, function(a, b) return a:GetTop() > b:GetTop() end)
    return out
end
local function lineAt(lines, y)
    for i, fs in ipairs(lines) do
        if y <= fs:GetTop() + 1 and y >= fs:GetBottom() - 1 then return i end
    end
    if #lines > 0 then
        if y > lines[1]:GetTop() then return 1 end
        if y < lines[#lines]:GetBottom() then return #lines end
    end
end
-- sichtbare Zeichen einer Zeile: { s = erstes Byte, e = letztes Byte }; Farb-, Link- und Endcodes zaehlen nicht mit,
-- Symbole (|T...|t, |A...|a) zaehlen als ein Zeichen
local function units(raw)
    local out, i, n = {}, 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "|" then
            local nx = raw:sub(i + 1, i + 1)
            if nx == "c" and raw:sub(i + 2, i + 2) == "n" then local e = raw:find(":", i + 3, true) i = (e or n) + 1   -- |cnNAME:
            elseif nx == "c" then i = i + 10
            elseif nx == "r" or nx == "h" then i = i + 2
            elseif nx == "H" then local e = raw:find("|h", i + 2, true) i = (e or n) + 2
            elseif nx == "T" or nx == "A" then
                local e = raw:find(nx == "T" and "|t" or "|a", i + 2, true)
                out[#out + 1] = { s = i, e = (e or n) + 1 }
                i = (e or n) + 2
            elseif nx == "|" then out[#out + 1] = { s = i, e = i + 1 } i = i + 2
            else out[#out + 1] = { s = i, e = i } i = i + 1 end
        else
            local b = c:byte()
            local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
            out[#out + 1] = { s = i, e = i + len - 1 }
            i = i + len
        end
    end
    return out
end
local meas, wrapM
-- 0.6.102: immer buchstabengenau, auch bei umgebrochenen Nachrichten: je Zeichen Bildzeile (row) und rechte Kante (w)
-- innerhalb seiner Bildzeile; Umbrueche ermittelt ein unsichtbares Textfeld mit gleicher Schrift und Breite
local function measureLine(fs, raw)
    live.cache = live.cache or {}
    raw = raw or fs:GetText()
    local c = live.cache[fs]
    if c and c.raw == raw then return c end
    c = { raw = raw, u = units(raw), w = { [0] = 0 }, row = {}, rowStart = { 1 } }
    live.cache[fs] = c
    local font, size, flags = fs:GetFont()
    if not font or #c.u > 600 then c.whole = true return c end
    if not meas then meas = UIParent:CreateFontString(nil, "BACKGROUND") meas:SetWordWrap(false) meas:SetAlpha(0) end
    meas:SetFont(font, size, flags or "")
    local function width(t)
        meas:SetText(t)
        return (meas.GetUnboundedStringWidth and meas:GetUnboundedStringWidth()) or meas:GetStringWidth() or 0
    end
    local rows = math.max(1, (fs.GetNumLines and fs:GetNumLines()) or 1)
    local rowsOf
    if rows > 1 then
        if not wrapM then wrapM = UIParent:CreateFontString(nil, "BACKGROUND") wrapM:SetWordWrap(true) wrapM:SetAlpha(0) end
        wrapM:SetFont(font, size, flags or "")
        wrapM:SetWidth(fs:GetWidth() or 300)
        if fs.GetIndentedWordWrap and wrapM.SetIndentedWordWrap then wrapM:SetIndentedWordWrap(fs:GetIndentedWordWrap()) end
        rowsOf = function(t) wrapM:SetText(t) return (wrapM.GetNumLines and wrapM:GetNumLines()) or 1 end
    end
    c.rows = rows
    c.lh = (fs:GetHeight() or 14) / rows
    local cur, startByte = 1, 1
    for k, u in ipairs(c.u) do
        local r = rowsOf and rowsOf(raw:sub(1, u.e)) or 1
        if r > cur then
            cur = r
            c.rowStart[r] = k
            startByte = u.s
        end
        c.row[k] = cur
        c.w[k] = width(raw:sub(startByte, u.e))
    end
    return c
end
-- linke Kante von Zeichen k (in seiner Bildzeile)
local function leftOf(c, k)
    if k <= 1 or c.row[k - 1] ~= c.row[k] then return 0 end
    return c.w[k - 1]
end
-- Grenze (0 .. Zeichenzahl) an Position x/y
local function boundAt(fs, x, y)
    local c = measureLine(fs)
    if c.whole or #c.u == 0 then return nil end
    local r = 1
    if c.rows > 1 and y then
        r = math.floor(((fs:GetTop() or 0) - y) / c.lh) + 1
        r = math.max(1, math.min(c.rows, r))
    end
    local rx = x - (fs:GetLeft() or 0)
    local first = c.rowStart[r] or 1
    if rx <= 0 then return first - 1 end
    local last = first - 1
    for k = first, #c.u do
        if c.row[k] ~= r then break end
        last = k
        if rx < (leftOf(c, k) + c.w[k]) / 2 then return k - 1 end
    end
    return last
end
-- Auswahl geordnet: Zeile a (ab Grenze ba) bis Zeile b (bis Grenze bb)
-- 0.6.109: Auswahl haengt an Nachrichten im Chatverlauf (Nummer + Zeichen), nicht an Bildschirmzeilen. Scrollt man
-- beim Ziehen, bleibt der Anfang an seiner Nachricht und die Auswahl waechst oder schrumpft mit; der Text kommt aus dem
-- Verlauf (GetMessageInfo), auch wenn Teile gerade nicht sichtbar sind.
local function msgText(cf, m)
    local ok, t = pcall(cf.GetMessageInfo, cf, m)
    if ok and type(t) == "string" and not issecret(t) then return t end
end
-- sichtbare Zeile -> Nachrichtennummer: unterste sichtbare Zeile = neueste (Anzahl - Scrollversatz), nach oben
-- abzaehlen und am Text bestaetigen; passt der Text nicht, im Umkreis suchen
local function visibleMap(cf, lines)
    local map = {}
    if cf.LiveIndexOf then   -- eigene Listen (Oasis-Gildenchat) kennen die Nummer selbst
        for _, fs in ipairs(lines) do map[fs] = cf:LiveIndexOf(fs) end
        return map
    end
    local n = (cf.GetNumMessages and num(cf:GetNumMessages())) or 0
    local off = (cf.GetScrollOffset and num(cf:GetScrollOffset())) or 0
    for k = #lines, 1, -1 do
        local fs = lines[k]
        local t = fs:GetText()
        local guess = n - off - (#lines - k)
        local found
        if t then
            for d = 0, 40 do
                for _, m in ipairs(d == 0 and { guess } or { guess - d, guess + d }) do
                    if m >= 1 and m <= n and msgText(cf, m) == t then found = m break end
                end
                if found then break end
            end
        end
        map[fs] = found or (guess >= 1 and guess or nil)
    end
    return map
end
-- Auswahl geordnet (aeltere Nachricht zuerst): a = { m, b }, z = { m, b }
local function span()
    local a, z = live.A, live.F
    if z.m < a.m or (z.m == a.m and (z.b or 0) < (a.b or 0)) then a, z = z, a end
    return a, z
end
local function liveClear()
    for _, t in ipairs(live.hl) do t:Hide() end
    live.A, live.F, live.lines, live.frame, live.text = nil, nil, nil, nil, nil
    if live.eb then live.eb:ClearFocus() end
    if live.tip then live.tip:Hide() end
end
local function liveDraw()
    if not (live.frame and live.A and live.F) then return end
    local a, z = span()
    local ac = (ns.K and ns.K.C and ns.K.C.accent) or { 0.6, 0.4, 1 }
    local n = 0
    local function bar(fs, x0, y0, x1, y1)
        n = n + 1
        local t = live.hl[n]
        if not t then t = live.layer:CreateTexture(nil, "OVERLAY") live.hl[n] = t end
        t:SetColorTexture(ac[1], ac[2], ac[3], 0.45)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fs, "TOPLEFT", x0, y0)
        if x1 then t:SetPoint("BOTTOMRIGHT", fs, "TOPLEFT", x1, y1) else t:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 2, -1) end
        t:Show()
    end
    live.first = nil
    for fs, m in pairs(live.map or {}) do
        if m and m >= a.m and m <= z.m then
            local c = measureLine(fs, fs:GetText())
            if c.whole or #c.u == 0 then
                bar(fs, -2, 1)
            else
                local s0 = math.max(0, math.min(#c.u, (m == a.m and a.b) or 0))
                local s1 = math.max(0, math.min(#c.u, (m == z.m and z.b) or #c.u))
                local r0, r1 = c.row[s0 + 1], c.row[s1]
                if s1 > s0 and r0 and r1 then
                    for r = r0, r1 do
                        local x0 = (r == r0) and leftOf(c, s0 + 1) or 0
                        local lastK = s1
                        if r < r1 then lastK = (c.rowStart[r + 1] or (#c.u + 1)) - 1 end
                        local x1 = c.w[lastK] or 0
                        if x1 > x0 then bar(fs, x0, -(r - 1) * c.lh, x1, -r * c.lh) end
                    end
                end
            end
            if not live.first or (fs:GetTop() or 0) > (live.first:GetTop() or 0) then live.first = fs end
        end
    end
    for i = n + 1, #live.hl do live.hl[i]:Hide() end
end
local function plainOf(raw)
    local ok, p = pcall(GC.Plain, raw)
    p = ok and p or raw
    return (p:gsub("|[hHrc]%x*", ""))
end
local function selectedText()
    local a, z = span()
    local out = {}
    for m = a.m, z.m do
        local raw = msgText(live.frame, m)
        if raw then
            local u = units(raw)
            local s0 = math.max(0, math.min(#u, (m == a.m and a.b) or 0))
            local s1 = math.max(0, math.min(#u, (m == z.m and z.b) or #u))
            local part
            if #u == 0 then part = raw
            elseif s1 > s0 then part = raw:sub(u[s0 + 1].s, u[s1].e) end
            if part then
                local p = plainOf(part)
                if p ~= "" then out[#out + 1] = p end
            end
        end
    end
    return table.concat(out, "\n")
end
local function liveFinish()
    local text = selectedText()
    if text == "" then liveClear() return end
    if not live.eb then
        -- unsichtbares Eingabefeld: haelt den markierten Text, damit Strg+C ihn kopiert. Ausserhalb des Bildschirms
        -- und ohne Markierungsfarbe (SetAlpha(0) allein liess oben links eine graue Flaeche stehen)
        local eb = CreateFrame("EditBox", nil, live.layer)
        eb:SetSize(10, 10)
        eb:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 200, -200)
        eb:SetAlpha(0)
        if eb.SetHighlightColor then eb:SetHighlightColor(0, 0, 0, 0) end
        eb:SetTextColor(0, 0, 0, 0)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontNormal)
        eb:SetScript("OnTextChanged", function(self, user) if user and live.text then self:SetText(live.text) self:HighlightText() end end)
        eb:SetScript("OnEscapePressed", liveClear)
        eb:SetScript("OnEditFocusLost", function() if not live.menu then for _, t in ipairs(live.hl) do t:Hide() end if live.tip then live.tip:Hide() end end end)
        eb:SetScript("OnKeyUp", function(_, key)
            if key == "C" and IsControlKeyDown() and live.tip then
                live.tip:SetText(L["Kopiert"])
                C_Timer.After(0.8, liveClear)
            end
        end)
        live.eb = eb
        live.tip = live.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    live.text = text
    live.eb:SetText(text)
    live.eb:SetFocus()
    live.eb:HighlightText()
    live.tip:ClearAllPoints()
    if live.first then
        live.tip:SetPoint("BOTTOMLEFT", live.first, "TOPLEFT", 0, 3)
    else
        live.tip:SetPoint("BOTTOMLEFT", live.frame, "TOPLEFT", 0, 3)
    end
    live.tip:SetText(L["Strg+C kopiert - Rechtsklick: mehr - Esc hebt auf"])
    live.tip:Show()
end
local function liveStart(cf)
    if G().gcLiveSelect == false then return end
    liveClear()
    local lines = shownLines(cf)
    local x0, y0 = cursorXY()
    local i = lineAt(lines, y0)
    if not i then return end
    if not live.layer then
        live.layer = CreateFrame("Frame", nil, UIParent)
        live.layer:SetFrameStrata("DIALOG")
        live.layer:SetAllPoints(UIParent)
        live.drv = CreateFrame("Frame")
        -- nach dem Markieren beim Scrollen die Hervorhebung mitfuehren (der Text bleibt derselbe)
        live.follow = CreateFrame("Frame")
        live.follow:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            if self.acc < 0.05 then return end
            self.acc = 0
            if live.frame and live.text and live.A and not (live.drv and live.drv:GetScript("OnUpdate")) and live.eb and live.eb:HasFocus() then
                live.lines = shownLines(live.frame)
                live.map = visibleMap(live.frame, live.lines)
                liveDraw()
            end
        end)
    end
    live.cache = {}
    -- gleicher Massstab wie das Chatfenster (gemessen wird in dessen Einheiten)
    live.layer:SetScale((cf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
    local map = visibleMap(cf, lines)
    local m = map[lines[i]]
    if not m then return end
    live.frame, live.lines, live.map, live.x0, live.y0, live.moved = cf, lines, map, x0, y0, false
    live.A = { m = m, b = boundAt(lines[i], x0, y0) or 0 }
    live.F = { m = m, b = live.A.b }
    live.drv:SetScript("OnUpdate", function(self)
        if not live.frame then self:SetScript("OnUpdate", nil) return end
        local x, y = cursorXY()
        if not live.moved and math.abs(y - live.y0) < 6 and math.abs(x - live.x0) < 5 then
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil) liveClear() end   -- nur ein Klick
            return
        end
        live.moved = true
        -- jede Runde neu: nach dem Mausrad stehen andere Nachrichten in den Zeilen
        live.lines = shownLines(live.frame)
        live.map = visibleMap(live.frame, live.lines)
        local j = lineAt(live.lines, y)
        local fs = j and live.lines[j]
        local mj = fs and live.map[fs]
        if mj then
            local c = measureLine(fs, fs:GetText())
            local b = boundAt(fs, x, y)
            live.F = { m = mj, b = b or ((y < (fs:GetTop() or 0)) and #c.u or 0) }
        end
        liveDraw()
        if not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            liveFinish()
        end
    end)
end
-- Rechtsklick auf eine Markierung: kleines Menue. Die Zwischenablage selbst ist fuer Addons gesperrt -
-- "Kopieren" legt die Markierung wieder bereit, Strg+C kopiert.
local function liveMenu()
    if not live.text or not live.lines then return false end
    local text = live.text
    if not live.anchor then live.anchor = CreateFrame("Frame", nil, UIParent) live.anchor:SetSize(1, 1) end
    local x, y = cursorXY()
    live.anchor:ClearAllPoints()
    live.anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    live.menu = true
    liveDraw()
    local function refocus()
        live.menu = nil
        if live.eb then live.eb:SetFocus() live.eb:HighlightText() end
        liveDraw()
        if live.tip then live.tip:SetText(L["Jetzt Strg+C druecken"]) live.tip:Show() end
    end
    local items = {
        { text = L["Kopieren (Strg+C)"], fn = refocus },
        { text = L["In die Chatzeile einfuegen"], fn = function()
            live.menu = nil
            local one = text:gsub("\n", " ")
            liveClear()
            local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
            if open then open(one) end
        end },
        { text = L["Im Markierfeld oeffnen"], fn = function() live.menu = nil local f = live.frame liveClear() GC.SelectInPlace(f) end },
        { text = L["Markierung aufheben"], fn = function() live.menu = nil liveClear() end },
    }
    if ns.K and ns.K.ShowMenu then ns.K.ShowMenu(live.anchor, items, L["Markierter Text"]) end
    return true
end
GC.LiveStart, GC.LiveClear, GC.LiveMenu = liveStart, liveClear, liveMenu
function GC.LiveText() return live.text end   -- fuer Tests
GC._live = live

-- Ziehen im Chatfenster = live markieren, Alt + Klick = Markierfeld (einzelne Woerter)
local selHooked = setmetatable({}, { __mode = "k" })
function GC.HookSelect()
    if ns.ForeignChat and ns.ForeignChat() then return end   -- 0.6.254: Markieren nur im Blizzard-Chat
    local names = ns.Emoji and ns.Emoji.ChatFrameNames and ns.Emoji.ChatFrameNames()
    if not names then names = {} for i = 1, (NUM_CHAT_WINDOWS or 10) do names[i] = "ChatFrame" .. i end end
    for _, n in ipairs(names) do
        local cf = _G[n]
        if cf and cf.HookScript and not selHooked[cf] then
            selHooked[cf] = true
            cf:HookScript("OnMouseDown", function(self, btn)
                if btn == "RightButton" then pcall(GC.LiveMenu) return end
                if btn ~= "LeftButton" then return end
                if IsAltKeyDown() then
                    if G().gcAltSelect ~= false then GC.SelectInPlace(self) end
                elseif not IsShiftKeyDown() and not IsControlKeyDown() then
                    local ok, e = pcall(liveStart, self)
                    if not ok then ns.err("Spielchat", e) end
                end
            end)
        end
    end
end
if ns.Listen then ns.Listen("LOGIN", function() C_Timer.After(1, function() pcall(GC.HookSelect) end) end) end
if not (ns.ForeignChat and ns.ForeignChat()) and hooksecurefunc and type(FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, function() pcall(GC.HookSelect) end) end)
end
function GC.ApplyCopyButton()
    local want = G().gcCopyBtn ~= false and not nesUIChat() and not (ns.ForeignChat and ns.ForeignChat())   -- 0.6.257
    if not GC.copyBtn then
        if not want or not ChatFrame1 then return end
        local b = CreateFrame("Button", "OasisChatCopyButton", ChatFrame1)
        b:SetSize(18, 18)
        b:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", 0, 0)
        b:SetFrameLevel((ChatFrame1:GetFrameLevel() or 1) + 5)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexture("Interface\\AddOns\\Oasis\\Media\\icons\\checklist")
        b:SetAlpha(0.35)
        b:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            if ns.K and ns.K.ShowTip then ns.K.ShowTip(self, { L["Chat kopieren"], L["Linksklick: direkt im Chat markieren, Strg+C kopiert"], L["Rechtsklick: Suchfenster"], L["Auch Alt + Klick ins Chatfenster startet das Markieren"] }) end
        end)
        b:SetScript("OnLeave", function(self) self:SetAlpha(0.35) GameTooltip:Hide() end)
        -- 0.6.3: Linksklick = direkt im Chat markieren, Rechtsklick = Suchfenster (wie bisher)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                if GC.OpenViewer then GC.OpenViewer("search", SELECTED_CHAT_FRAME) end
            else
                GC.SelectInPlace(SELECTED_CHAT_FRAME)
            end
        end)
        GC.copyBtn = b
    end
    GC.copyBtn:SetShown(want)
end

function GC.ApplyAll()
    if not ns.db then return end
    GC.Attach()
    GC.ApplyButtons()
    GC.ApplyStamp()
    pcall(GC.ApplyCopyButton)
    pcall(GC.HookSelect)
end

------------------------------------------------------------------------
-- Listen pflegen (Einstellungen und Befehle)
------------------------------------------------------------------------
function GC.ListAdd(key, value)
    local list = G()[key]
    value = tostring(value or ""):gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if value == "" or #value > MAX_ENTRY then return false, L["Leer oder zu lang (hoechstens 100 Zeichen)."] end
    for _, v in ipairs(list) do if v == value then return false, L["Steht schon in der Liste."] end end
    if #list >= MAX_LIST then return false, L["Die Liste ist voll (hoechstens 50 Eintraege)."] end
    list[#list + 1] = value
    table.sort(list)
    return true
end
function GC.ListRemove(key, value)
    local list = G()[key]
    for i, v in ipairs(list) do
        if v == value then table.remove(list, i) return true end
    end
    return false
end
-- /oa chatmute Kanal; Name  (nochmal = wieder aufheben)
ns.slash.chatmute = function(rest)
    local channel, name = (rest or ""):match("^%s*(.-)%s*;%s*(.-)%s*$")
    if not channel or channel == "" or name == "" then
        ns.print(L["So geht es: /oa chatmute Kanal; Spielername"])
        return
    end
    local key = GC.MuteKey(channel, name)
    if GC.ListRemove("gcMutes", key) then
        ns.print((L["%s ist in %s nicht mehr stumm."]):format(name, channel))
    else
        local ok, why = GC.ListAdd("gcMutes", key)
        if ok then
            G().gcFilter = true
            ns.print((L["%s ist in %s stummgeschaltet."]):format(name, channel))
        else
            ns.print(why)
        end
    end
end
ns.slash.chatsuche = function() if GC.OpenViewer then GC.OpenViewer("search") end end
ns.slash.chatsearch = ns.slash.chatsuche
ns.slash.chatkopieren = ns.slash.chatsuche
ns.slash.chatcopy = ns.slash.chatsuche
ns.slash.chatmarkieren = function() GC.SelectInPlace() end
ns.slash.chatselect = ns.slash.chatmarkieren
ns.slash.chatalarm = function(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" then
        if GC.OpenViewer then GC.OpenViewer("alerts") end
        return
    end
    local w = rest:lower()
    if GC.ListRemove("gcWords", w) then
        ns.print((L["Alarm entfernt: %s"]):format(rest))
    else
        local ok, why = GC.ListAdd("gcWords", w)
        ns.print(ok and (L["Alarm gesetzt: %s"]):format(rest) or why)
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.On("PLAYER_TARGET_CHANGED", function() noteUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() noteUnit("mouseover") end)
ns.On("GROUP_ROSTER_UPDATE", scanGroup)
ns.On("GUILD_ROSTER_UPDATE", scanGuild)
ns.On("FRIENDLIST_UPDATE", scanFriends)
ns.On("WHO_LIST_UPDATE", scanWho)
ns.On("PLAYER_REGEN_ENABLED", function()
    if GC.pending then
        GC.pending = nil
        GC.ApplyAll()
    end
end)
ns.On("PLAYER_LOGOUT", function() pcall(saveHistory) end)
local entered = false
ns.On("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    GC.ApplyAll()
    scanGroup() scanGuild() scanFriends()
    if not entered then
        entered = true
        ns.After(1.5, function() pcall(restoreHistory) end)
        if hooksecurefunc and not (ns.ForeignChat and ns.ForeignChat()) then
            if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() ns.After(0, GC.ApplyAll) end) end
            if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() ns.After(0, GC.ApplyAll) end) end
        end
    end
end)

end)

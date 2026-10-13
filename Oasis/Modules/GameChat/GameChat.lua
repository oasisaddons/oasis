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
    gcOn = false,
    gcShort = false, gcLevel = true, gcClassIcon = false, gcRaceIcon = false,
    gcLinkIcons = true, gcTokens = true, gcChNum = false, gcQuiet = false, gcHover = false,
    gcFilter = false, gcWhole = false, gcCyr = false, gcHan = false, gcRepeat = false, gcRepeatSec = 60,
    gcHist = true, gcHistLines = 100,
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
function GC.Search(frame, query)
    local out = {}
    query = (query or ""):lower()
    for _, l in ipairs(GC.Buffer(frame)) do
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
                        local stamp = l.ts and date("[%H:%M] ", l.ts) or ""
                        f:AddMessage(stamp .. l.t:gsub("|", "||"), (l.r or 1) * 0.72, (l.g or 1) * 0.72, (l.b or 1) * 0.72)
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
    if not ns.db or ns.inCombat() then GC.pending = true return end
    watch(ChatFrameMenuButton, "gcHideMenu")
    watch(ChatFrameChannelButton, "gcHideChannel")
    watch(QuickJoinToastButton, "gcHideSocial")
    watch(FriendsMicroButton, "gcHideSocial")
    for _, n in ipairs(CHAT_FRAMES or {}) do
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
    if s.gcOn and fmt then
        if s.gcStampNative == nil then s.gcStampNative = cvar("showTimestamps") or "none" end
        cvar("showTimestamps", fmt)
    elseif s.gcStampNative ~= nil then
        cvar("showTimestamps", s.gcStampNative)
        s.gcStampNative = nil
    end
end

function GC.ApplyAll()
    if not ns.db then return end
    GC.Attach()
    GC.ApplyButtons()
    GC.ApplyStamp()
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
        if hooksecurefunc then
            if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", function() ns.After(0, GC.ApplyAll) end) end
            if FCF_OpenNewWindow then hooksecurefunc("FCF_OpenNewWindow", function() ns.After(0, GC.ApplyAll) end) end
        end
    end
end)

end)

-- Oasis - Discord Voice (WoW Forever): nur lesend. Zeigt, ob die Gilde mit einem Discord-Server verknuepft ist, wie Server und Kanal
-- heissen und wer gerade im Sprachkanal ist. Nichts wird verknuepft oder geaendert. Alles pcall-gesichert: fehlt eine Funktion, bleibt es leer.
-- /oa discord gibt den Rohzustand im Chat aus (zum Pruefen, was der Client liefert).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Discord", function()   -- Modul Discord (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L

local D = {}
ns.Discord = D

local issecret = issecretvalue or function() return false end
local function call(tbl, fn, ...)
    local f = tbl and tbl[fn]
    if type(f) ~= "function" then return nil end
    -- in die Spur: wird eine C_Discord-Funktion als geschuetzt geblockt, steht ihr Name im Blockiert-Bericht
    if ns.Trace then ns.Trace("Discord: " .. fn) end
    local ok, a, b = pcall(f, ...)
    if ok and not issecret(a) then return a, b end
    return nil
end
local function txt(v) v = ns.safe(v) return type(v) == "string" and v ~= "" and v or nil end

-- Zustand der Discord-Anbindung. 0.5.775: im Alltag (Dashboard) NUR IsVoiceEnabled - die uebrigen C_Discord-Funktionen sind teils geschuetzt
-- und loesten "Oasis wurde geblockt ... UNKNOWN()" aus. Alles andere nur mit full = true (/oa discord), dort jeweils in der Spur.
-- 0.5.799: im Kampf gar keine Abfrage - dort blockt der Client auch die sonst erlaubten Funktionen ("UNKNOWN()" auf der Startseite
-- im Kampf). Solange gilt der letzte Stand von ausserhalb des Kampfes; nach dem Kampf wird neu gelesen (siehe unten).
local lastState, lastMembers, lastChName, lastChId
function D.State(full)
    local C = C_Discord
    local s = { api = C ~= nil }
    if not C then return s end
    if ns.inCombat() then return lastState or s end
    lastState = s
    s.voice = call(C, "IsVoiceEnabled")
    s.enabled = call(C, "IsEnabled")
    -- Ergebnis von /oa discord test (10.10.2026, Build 70291): NUR IsEnabled und IsVoiceEnabled sind erlaubt. Gesperrt sind IsUserOAuthed,
    -- IsGuildChannelLinked, GetGuildLinkStatus, GetNumDiscordServers, GetNumDiscordChannels, GetDisplayNameType, GetDiscordUserName,
    -- GetDiscordUserID -> nie automatisch aufrufen (loest 'Oasis wurde geblockt' aus).
    return s
end

-- Wer ist gerade im aktiven Sprachkanal: { { name, speaking } }, Kanalname, Kanal-ID
function D.Members()
    local V = C_VoiceChat
    local out = {}
    if not V then return out end
    if ns.inCombat() then return lastMembers or out, lastChName, lastChId end
    lastMembers, lastChName, lastChId = out, nil, nil
    local id = call(V, "GetActiveChannelID")
    if not id then return out end
    lastChId = id
    local ch = call(V, "GetChannel", id)
    if type(ch) ~= "table" then return out, nil, id end
    for _, m in ipairs(ch.members or {}) do
        local mid = type(m) == "table" and m.memberID or m
        local name = mid and txt(call(V, "GetMemberName", mid, id))
        if name then out[#out + 1] = { name = name, speaking = type(m) == "table" and m.isSpeaking and true or false } end
    end
    lastChName = txt(ch.name)
    return out, lastChName, id
end

-- laeuft ein Sprachkanal (fuer die Vorbelegung "Sprachchat" in der Gruppensuche)
function D.VoiceActive()
    local V = C_VoiceChat
    if not V then return false end
    if ns.inCombat() then return lastChId ~= nil end
    return call(V, "GetActiveChannelID") ~= nil
end

-- eine Zeile fuers Dashboard; leer, wenn nichts verknuepft/aktiv ist
function D.Line()
    local s = D.State()
    local members, chName = D.Members()
    local shown = s.voice == true or #members > 0
    if not shown then return "" end
    if #members > 0 then return (L["Discord: %s  -  %d in voice"]):format(chName or "Voice", #members) end
    if chName then return (L["Discord: %s"]):format(chName) end
    return L["Discord voice: on"]
end

function D.Tip()
    local s = D.State()
    local members, chName = D.Members()
    local lines = {}
    lines[#lines + 1] = L["Discord Voice"]
    lines[#lines + 1] = (L["Voice: %s"]):format(s.voice and L["on"] or L["off"])
    if chName then lines[#lines + 1] = (L["Channel: %s"]):format(chName) end
    if #members == 0 then lines[#lines + 1] = L["Nobody is in the voice channel right now."] end
    if #members > 0 then
        local parts = {}
        for _, m in ipairs(members) do parts[#parts + 1] = m.speaking and ("|cff66db9e" .. m.name .. "|r") or m.name end
        lines[#lines + 1] = (L["In voice: %s"]):format(table.concat(parts, ", "))
    end
    return lines
end

-- bei Aenderungen im Sprachkanal: Dashboard u.a. benachrichtigen (gebuendelt)
local EVENTS = { "VOICE_CHAT_CHANNEL_JOINED", "VOICE_CHAT_CHANNEL_REMOVED", "VOICE_CHAT_CHANNEL_ACTIVATED", "VOICE_CHAT_CHANNEL_DEACTIVATED",
    "VOICE_CHAT_CHANNEL_MEMBER_ADDED", "VOICE_CHAT_CHANNEL_MEMBER_REMOVED", "VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED",
    "VOICE_CHAT_LOGIN", "VOICE_CHAT_LOGOUT" }
local ev = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
-- nach dem Kampf den im Kampf eingefrorenen Stand nachziehen
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    ns.Debounce("discordvoice", 0.8, function() ns.Fire("DISCORD_VOICE") end)
end)

-- 0.5.776: /oa discord ist jetzt ungefaehrlich (nur die erlaubten Abfragen). "/oa discord test" prueft die uebrigen Lese-Funktionen
-- einzeln im Abstand von 0,5 s und meldet, welche der Client blockiert (loest dabei absichtlich die Blizzard-Meldung aus).
local blockCount = 0
local blockEv = CreateFrame("Frame")
pcall(blockEv.RegisterEvent, blockEv, "ADDON_ACTION_BLOCKED")
pcall(blockEv.RegisterEvent, blockEv, "ADDON_ACTION_FORBIDDEN")
blockEv:SetScript("OnEvent", function(_, _, addon) if ns.safe(addon) == ADDON then blockCount = blockCount + 1 end end)
local TEST = { "IsEnabled", "IsVoiceEnabled", "IsUserOAuthed", "IsGuildChannelLinked", "GetGuildLinkStatus", "GetNumDiscordServers",
    "GetNumDiscordChannels", "GetDisplayNameType", "GetDiscordUserName", "GetDiscordUserID", "V:GetActiveChannelID", "V:IsLoggedIn" }
local function runTest()
    local C = C_Discord
    if not C then ns.print("Discord: C_Discord fehlt in diesem Client.") return end
    local res, i = {}, 0
    local function step()
        i = i + 1
        local fn = TEST[i]
        if not fn then
            ns.print("Discord-Test fertig: " .. table.concat(res, "  "))
            return
        end
        local before = blockCount
        local tbl = C
        if fn:sub(1, 2) == "V:" then tbl, fn = C_VoiceChat, fn:sub(3) end
        local v = call(tbl, fn)
        C_Timer.After(0.5, function()
            res[#res + 1] = fn .. "=" .. ((blockCount > before) and "|cffff6060GESPERRT|r" or ("|cff66db9e" .. tostring(v) .. "|r"))
            step()
        end)
    end
    ns.print("Discord-Test laeuft (5 Sekunden) - die Blizzard-Meldung dabei bitte mit Ignorieren schliessen.")
    step()
end
ns.slash.discord = function(arg)
    if arg == "test" then runTest() return end
    local s = D.State()
    ns.print(("Discord: Schnittstelle=%s Voice=%s  (weitere Abfragen nur mit /oa discord test)"):format(tostring(s.api), tostring(s.voice)))
    local members, chName, id = D.Members()
    ns.print(("Sprachkanal: id=%s name=%s Mitglieder=%d"):format(tostring(id), tostring(chName), #members))
    for _, m in ipairs(members) do ns.print("  " .. m.name .. (m.speaking and " (spricht)" or "")) end
end
end)

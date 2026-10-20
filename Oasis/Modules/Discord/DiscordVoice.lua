-- Oasis - Discord Voice (WoW Forever): read-only. Shows whether the guild is linked to a Discord server, what server and channel
-- are called and who is currently in the voice channel. Nothing is linked or changed. Everything pcall-protected: if a function is missing, it stays empty.
-- /oa discord prints the raw state in chat (to check what the client delivers).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Discord", function()   -- Discord module (can be disabled, see ModuleLoader.lua)
local L = ns.L

local D = {}
ns.Discord = D

local issecret = issecretvalue or function() return false end
local function call(tbl, fn, ...)
    local f = tbl and tbl[fn]
    if type(f) ~= "function" then return nil end
    -- into the trace: if a C_Discord function gets blocked as protected, its name shows up in the blocked report
    if ns.Trace then ns.Trace("Discord: " .. fn) end
    local ok, a, b = pcall(f, ...)
    if ok and not issecret(a) then return a, b end
    return nil
end
local function txt(v) v = ns.safe(v) return type(v) == "string" and v ~= "" and v or nil end

-- State of the Discord connection. 0.5.775: in everyday use (dashboard) ONLY IsVoiceEnabled - the other C_Discord functions are partly protected
-- and triggered "Oasis has been blocked ... UNKNOWN()". Everything else only with full = true (/oa discord), each in the trace there.
-- 0.5.799: no query at all in combat - there the client also blocks the otherwise allowed functions ("UNKNOWN()" on the start page
-- in combat). Meanwhile the last state from outside combat applies; after combat it is read again (see below).
local lastState, lastMembers, lastChName, lastChId
function D.State(full)
    local C = C_Discord
    local s = { api = C ~= nil }
    if not C then return s end
    if ns.inCombat() then return lastState or s end
    lastState = s
    s.voice = call(C, "IsVoiceEnabled")
    s.enabled = call(C, "IsEnabled")
    -- Result of /oa discord test (10.10.2026, build 70291): ONLY IsEnabled and IsVoiceEnabled are allowed. Blocked are IsUserOAuthed,
    -- IsGuildChannelLinked, GetGuildLinkStatus, GetNumDiscordServers, GetNumDiscordChannels, GetDisplayNameType, GetDiscordUserName,
    -- GetDiscordUserID -> never call automatically (triggers 'Oasis has been blocked').
    return s
end

-- Who is currently in the active voice channel: { { name, speaking } }, channel name, channel ID
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

-- is a voice channel running (for the "Voice chat" preset in the group finder)
function D.VoiceActive()
    local V = C_VoiceChat
    if not V then return false end
    if ns.inCombat() then return lastChId ~= nil end
    return call(V, "GetActiveChannelID") ~= nil
end

-- one line for the dashboard; empty if nothing is linked/active
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

-- on changes in the voice channel: notify dashboard etc. (batched)
local EVENTS = { "VOICE_CHAT_CHANNEL_JOINED", "VOICE_CHAT_CHANNEL_REMOVED", "VOICE_CHAT_CHANNEL_ACTIVATED", "VOICE_CHAT_CHANNEL_DEACTIVATED",
    "VOICE_CHAT_CHANNEL_MEMBER_ADDED", "VOICE_CHAT_CHANNEL_MEMBER_REMOVED", "VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED",
    "VOICE_CHAT_LOGIN", "VOICE_CHAT_LOGOUT" }
local ev = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
-- after combat catch up on the state frozen during combat
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    ns.Debounce("discordvoice", 0.8, function() ns.Fire("DISCORD_VOICE") end)
end)

-- 0.5.776: /oa discord is now harmless (only the allowed queries). "/oa discord test" checks the remaining read functions
-- one by one at 0.5 s intervals and reports which ones the client blocks (deliberately triggers the Blizzard message while doing so).
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

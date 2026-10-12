-- Oasis: Fluestern an einen Charakter, der offline ist -> ANGEBOT, die Nachricht an seinen Twink zu schicken, der gerade online ist.
-- 0.5.912: Standard AUS und nie von selbst senden (Blizzard: Chat nur per Klick) - Oasis bietet es per Hinweis an (ns.OfferChat).
-- Grundlage: Twink-Zuordnung aus Oasis (Alts.lua: Profile + Gildennotizen) und die Online-Anzeige der Gildenliste.
-- Ein/Aus: Einstellungen > Bereiche > Chat oder /oa weiterleiten
local ADDON, ns = ...
local L = ns.L

local WF = {}
ns.WhisperForward = WF
local issecret = issecretvalue or function() return false end
local last   -- { msg, target, t, fwd }

local function on() return (ns.db and ns.db.settings.whisperForward == true) or false end
local function remember(msg, chatType, _, target)
    if chatType ~= "WHISPER" or type(msg) ~= "string" or type(target) ~= "string" then return end
    if issecret(msg) or issecret(target) then return end
    if WF.sending then return end   -- eigene Weiterleitung nicht nochmal merken
    last = { msg = msg, target = target, t = GetTime() }
end
WF._remember = remember   -- fuer Tests
if hooksecurefunc then
    if SendChatMessage then pcall(hooksecurefunc, "SendChatMessage", remember) end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then pcall(hooksecurefunc, C_ChatInfo, "SendChatMessage", remember) end
end

-- Gildenmitglied zu einem Fluester-Namen ("Vorname", "Vorname-Realm", "Vorname Nachname")
local function member(name)
    local R = ns.Radar
    if not (R and R.byName) then return nil end
    if R.byName[name] then return R.byName[name].name end
    local A = ns.Alts
    for _, m in ipairs(R.roster or {}) do
        if m.name and A and A.SameChar(m.name, name) then return m.name end
    end
end
-- Twink desselben Spielers, der gerade online ist
function WF.OnlineAlt(name)
    local A, R = ns.Alts, ns.Radar
    if not (A and R) then return nil end
    local who = member(name) or name
    for _, ch in ipairs(A.CharsOf(A.Main(who)) or {}) do
        if not A.SameChar(ch, who) and R.IsOnline(ch) and not ns.isMe(ch) then return ch end
    end
end

local PAT
local function notFoundName(text)
    if not PAT then
        local f = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
        PAT = "^" .. f:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    end
    return text:match(PAT)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(_, _, text)
    if not on() or not last or type(text) ~= "string" or issecret(text) then return end
    if GetTime() - last.t > 6 or last.fwd then return end
    local who = notFoundName(text)
    if not who or not ns.Alts or not ns.Alts.SameChar(ns.short(who), ns.short(last.target)) then return end
    local alt = WF.OnlineAlt(last.target)
    if not alt then return end
    last.fwd = true
    local to = ns.ChatName(alt)
    if ns.OfferChat then
        ns.OfferChat((L["%s ist offline - an %s senden?"]):format(ns.short(last.target), to), last.msg, "WHISPER", to)
    end
end)

ns.slash.weiterleiten = function()
    ns.db.settings.whisperForward = (not on()) or nil
    ns.print(on() and L["Fluester-Angebot fuer Twinks: an"] or L["Fluester-Angebot fuer Twinks: aus"])
end

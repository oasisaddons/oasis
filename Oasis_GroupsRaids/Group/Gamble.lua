-- Oasis: Wuerfelrunde (0.6.521) - klassisches Gruppenwuerfeln
--  * Wer startet, legt das Maximum fest (z. B. 100); alle in der Gruppe wuerfeln einmal /roll 1-N
--  * Hoechster Wurf gewinnt, niedrigster verliert - die Differenz ist der "Einsatz" (nur Anzeige, kein Gold-Handel)
--  * Mitglieder mit Oasis bekommen einen Hinweis zum Mitwuerfeln (Klick wuerfelt); gezaehlt wird der echte Systemchat
--  * Ansagen gehen nur per Klick in den Chat (ns.OfferChat) - automatische Chatnachrichten sind gesperrt
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Group", function()
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
local P = ns.Party
local G = {}
ns.Gamble = G
G.round = nil    -- { host, max, rolls = { [Name] = Wurf }, ends, done }
local DURATION = 40

local pats
local function patterns()
    if pats then return pats end
    pats = {}
    local seen = {}
    for _, fmt in ipairs({ RANDOM_ROLL_RESULT or "", "%s rolls %d (%d-%d)", "%s würfelt. Ergebnis: %d (%d-%d)" }) do
        if fmt ~= "" and not seen[fmt] then
            seen[fmt] = true
            local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
            pats[#pats + 1] = "^" .. p .. "$"
        end
    end
    return pats
end
local function roll(max)
    local fn = RandomRoll or (C_RandomRoll and C_RandomRoll.RandomRoll)
    if fn then pcall(fn, 1, max) end
end
G.Roll = roll

function G.Result()
    local r = G.round
    if not r then return nil end
    local list = {}
    for n, v in pairs(r.rolls) do list[#list + 1] = { n = n, v = v } end
    table.sort(list, function(a, b) return a.v > b.v end)
    return list
end
local function finish()
    local r = G.round
    if not r or r.done then return end
    r.done = true
    local list = G.Result()
    if #list >= 2 and ns.isMe(r.host) then
        local hi, lo = list[1], list[#list]
        local msg = (L["Wuerfelrunde 1-%d: %s gewinnt mit %d, %s hat %d - Differenz %d"]):format(r.max,
            (hi.n:gsub("%-.*$", "")), hi.v, (lo.n:gsub("%-.*$", "")), lo.v, hi.v - lo.v)
        local ch = ns.groupChannel()
        if ch then ns.OfferChat(L["Ergebnis ansagen"], msg, ch) end
    end
    ns.RefreshPage("party")
end
function G.Start(max)
    max = math.floor(tonumber(max) or 100)
    if max < 2 or max > 1000000 then return end
    local ch = ns.groupChannel()
    if not ch then ns.print(L["Wuerfelrunde geht nur in einer Gruppe."]) return end
    G.round = { host = P.UnitName("player"), max = max, rolls = {}, ends = GetTime() + DURATION }
    Comm.Group("GPG", max)
    ns.OfferChat(L["Wuerfelrunde ansagen"], (L["Wuerfelrunde! Alle /roll %d - %d Sekunden, hoechster gewinnt, niedrigster zahlt die Differenz."]):format(max, DURATION), ch)
    C_Timer.After(DURATION, finish)
    ns.RefreshPage("party")
end
Comm.On("GPG", function(sender, _, max)
    max = tonumber(max)
    if not max or max < 2 or max > 1000000 or ns.isMe(sender) or not P.InMyGroup(sender) then return end
    G.round = { host = sender, max = math.floor(max), rolls = {}, ends = GetTime() + DURATION }
    C_Timer.After(DURATION, finish)
    K.Toast(L["Wuerfelrunde"], (L["%s startet eine Wuerfelrunde 1-%d - klicken zum Wuerfeln"]):format((sender:gsub("%-.*$", "")), max), C.accent, function() roll(max) end)
    ns.RefreshPage("party")
end)
ns.On("CHAT_MSG_SYSTEM", function(msg)
    local r = G.round
    if not r or r.done or GetTime() > r.ends or type(msg) ~= "string" or issecretvalue and issecretvalue(msg) then return end
    for _, p in ipairs(patterns()) do
        local who, v, lo, hi = msg:match(p)
        if who then
            v, lo, hi = tonumber(v), tonumber(lo), tonumber(hi)
            if lo == 1 and hi == r.max and v then
                local full = ns.fullName(who)
                if (P.InMyGroup(full) or ns.isMe(full)) and not r.rolls[full] then
                    r.rolls[full] = v
                    ns.RefreshPage("party")
                end
            end
            return
        end
    end
end)

------------------------------------------------------------------------
-- Reiter "Wuerfelrunde"
------------------------------------------------------------------------
local lines = {}
P.AddTab({
    key = "gamble", text = "Wuerfelrunde",
    build = function(p, a)
        a.info = K.Text(a, 11, C.muted)
        a.info:SetPoint("TOPLEFT", 4, 0)
        a.info:SetPoint("RIGHT", -4, 0)
        a.info:SetJustifyH("LEFT")
        a.info:SetText(L["Alle wuerfeln einmal bis zum Maximum. Hoechster gewinnt, niedrigster verliert - die Differenz ist der Einsatz. Gezaehlt werden die echten Wuerfe."])
        a.max = K.Input(a, 90, "100")
        a.max:SetPoint("TOPLEFT", 4, -30)
        a.max:SetText("100")
        a.start = K.Button(a, L["Runde starten"], 120, 24, nil, function() G.Start(a.max:GetText()) end)
        a.start:SetPoint("LEFT", a.max, "RIGHT", 8, 0)
        a.mine = K.Button(a, L["Selbst wuerfeln"], 120, 24, "ghost", function() if G.round then roll(G.round.max) end end)
        a.mine:SetPoint("LEFT", a.start, "RIGHT", 8, 0)
        a.stat = K.Text(a, 12, C.text)
        a.stat:SetPoint("TOPLEFT", 4, -68)
        a.box = CreateFrame("Frame", nil, a)
        a.box:SetPoint("TOPLEFT", 0, -92)
        a.box:SetSize(420, 300)
    end,
    refresh = function(p, a)
        for _, l in ipairs(lines) do l:Hide() end
        local r = G.round
        a.mine:SetShown(r ~= nil and not r.done)
        if not r then a.stat:SetText(L["Keine Runde - starte eine."]) return end
        local left = math.max(0, math.floor(r.ends - GetTime()))
        a.stat:SetText((L["Runde 1-%d von %s"]):format(r.max, (r.host:gsub("%-.*$", ""))) .. "  -  " .. (r.done and L["beendet"] or ((L["noch %d s"]):format(left))))
        local list = G.Result() or {}
        for i, e in ipairs(list) do
            local l = lines[i]
            if not l then l = K.Text(a.box, 13, C.text) lines[i] = l end
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", 8, -(i - 1) * 20)
            local tag = (i == 1 and #list > 1) and ("  |cff7fd07f" .. L["gewinnt"] .. "|r") or ((i == #list and #list > 1) and ("  |cffff7070" .. L["verliert"] .. "|r") or "")
            l:SetText(("%d.  %s  |cffe8b44a%d|r%s"):format(i, (e.n:gsub("%-.*$", "")), e.v, tag))
            l:Show()
        end
        if not r.done then C_Timer.After(1, function() ns.RefreshPage("party") end) end
    end,
})

end)

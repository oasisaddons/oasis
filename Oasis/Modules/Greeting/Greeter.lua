-- Oasis - Login-Begruessung: zufaelliger, selbst geschriebener Gruss im Gildenchat, wenn jemand online kommt.
-- Abgestimmt: wer zuerst gruesst, sagt es den anderen Oasis-Nutzern - so gruesst nie die halbe Gilde gleichzeitig.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Greeting", function()   -- Modul Begruessung (abschaltbar, siehe ModuleLoader.lua)
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
                if #keep < 8 and (kind == "item" or kind == "spell") and data:match("^[%d:%-]+$")
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

local G = {}
ns.Greeter = G

local DEFAULT = "Hey {name}! o/\nMoin {name}!\nWillkommen zurück, {name}!\n{name} ist da :)\nNa {name}, alles klar?"

local function S() return ns.db.settings end
local function lines()
    local out = {}
    for l in ((S().greetLines or DEFAULT) .. "\n"):gmatch("(.-)\n") do
        l = l:gsub("^%s+", ""):gsub("%s+$", "")
        if l ~= "" then out[#out + 1] = l end
    end
    return out
end
function G.Pick(name)
    local ls = lines()
    if #ls == 0 then return nil end
    local first = ns.displayName(name)
    return (ls[math.random(#ls)]:gsub("{name}", first))
end

-- Online-Meldung im Systemchat erkennen
local pat
local function onlineName(msg)
    if not pat and ERR_FRIEND_ONLINE_SS then
        pat = ns.GlobalPattern(ERR_FRIEND_ONLINE_SS) or false
    end
    if not pat then return nil end
    local ok, n = pcall(string.match, msg, pat)
    return ok and n or nil
end

local loginAt = GetTime()
local lastSent, pending, greeted = 0, {}, {}
local function isGuildie(full)
    return ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, full) ~= nil
end

local function schedule(full)
    local s = S()
    if not s.greetOn or not IsInGuild() or ns.isMe(full) then return end
    if GetTime() - loginAt < 90 then return end                       -- nicht alle begruessen, die beim eigenen Login schon da sind
    local cd = (tonumber(s.greetCooldown) or 60) * 60
    if greeted[full] and ns.now() - greeted[full] < cd then return end
    if pending[full] then return end
    -- zufaellige Verzoegerung: wer zuerst dran ist, gruesst; die anderen brechen ab
    local token = {}
    pending[full] = token
    ns.After(4 + math.random() * 8, function()
        if pending[full] ~= token then return end
        pending[full] = nil
        if GetTime() - lastSent < 45 then return end                   -- hoechstens alle 45 s ein Gruss von dir
        if UnitIsAFK and ns.safe(UnitIsAFK("player")) then return end
        local msg = G.Pick(full)
        if not msg then return end
        lastSent = GetTime()
        greeted[full] = ns.now()
        -- ohne Klick darf Oasis nicht in den Chat schreiben: Gruss als Hinweis anbieten
        ns.OfferChat((L["%s is online"]):format(ns.displayName(full)), msg, "GUILD", nil, ns.K.C.mint)
        Comm.Guild("GRT", full)
    end)
end

ns.On("CHAT_MSG_SYSTEM", function(msg)
    msg = ns.safe(msg)
    if not msg then return end
    local n = onlineName(msg)
    if not n then return end
    local full = ns.fullName(n)
    if isGuildie(full) then schedule(full) end
end)
-- jemand anderes hat schon gegruesst -> eigenen Gruss abbrechen
Comm.On("GRT", function(sender, _, who)
    who = SEC.Name(who)
    if not who or ns.isMe(sender) then return end
    -- nur fuer Namen, die hier wirklich anstehen oder neu sind (Tabelle waechst nicht durch Muell)
    if not pending[who] and not greeted[who] and not (ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, who)) then return end
    pending[who] = nil
    greeted[who] = ns.now()
end)

------------------------------------------------------------------------
-- Einstellungen: eigener Reiter "Begruessung"
------------------------------------------------------------------------
local function build(f)
    local H = ns.SettingsHelpers
    -- 0.5.712: zwei Glas-Karten nebeneinander (links Einstellung + Schutz, rechts die Gruesse)
    local W, HH = 362, 236
    f.noCompact = true
    local left = H.cardH(f, 0, 0, W, HH, "social", L["Login greeting"], L["Random greeting when someone comes online"])
    H.toggle(left, 14, -58, "Greet members in guild chat when they come online", "greetOn",
        "Random greeting from your list. If another Oasis user already greeted, you stay quiet.", nil, W - 28)
    local div = K.Divider(left)
    div:SetPoint("TOPLEFT", 14, -96)
    div:SetPoint("RIGHT", left, "RIGHT", -14, 0)
    H.rowLabel(left, L["Pause per person (minutes)"], 14, -108)
    local cd = K.Input(left, 70, "60", function(t)
        local n = tonumber(t)
        if n then S().greetCooldown = math.max(5, math.min(1440, n)) end
    end)
    cd:SetPoint("TOPRIGHT", left, "TOPRIGHT", -14, -106)
    f.cd = cd
    H.note(left, L["Spam protection: no greeting in the first 90 seconds after your login, at most one every 45 seconds, not while AFK."], 14, -146, W - 28)
    f.greetOn = left

    local right = H.cardH(f, W + 14, 0, W, HH, "chronicle", L["Your greetings"], L["One greeting per line. {name} is replaced with the first name."])
    local box = CreateFrame("Frame", nil, right)
    box:SetPoint("TOPLEFT", 14, -58)
    box:SetPoint("RIGHT", right, "RIGHT", -14, 0)
    box:SetHeight(120)
    K.Fill(box, C.field)
    K.Border(box, C.line)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 13, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetPoint("TOPLEFT", 8, -6)
    eb:SetPoint("BOTTOMRIGHT", -8, 6)
    eb:SetMaxLetters(1200)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(self, user) if user then S().greetLines = self:GetText() end end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.eb = eb
    local test = K.Button(right, L["Preview"], 110, 24, "ghost", function()
        local m = G.Pick(ns.me())
        ns.print(m and ("|cff66db9e" .. L["Preview"] .. ":|r " .. m) or L["No greetings entered."])
    end)
    test:SetPoint("BOTTOMLEFT", 14, 14)
    local reset = K.Button(right, L["Default"], 110, 24, "ghost", function()
        S().greetLines = nil
        eb:SetText(DEFAULT)
    end)
    reset:SetPoint("LEFT", test, "RIGHT", 8, 0)
end
local function refresh(f)
    if f.eb and not f.eb:HasFocus() then f.eb:SetText(S().greetLines or DEFAULT) end
    if f.cd and not f.cd:HasFocus() then f.cd:SetText(tostring(S().greetCooldown or 60)) end
end
if ns.AddSettingsTab then ns.AddSettingsTab("greet", "Greeting", build, refresh) end
end)

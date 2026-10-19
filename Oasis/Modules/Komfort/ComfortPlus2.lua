-- 0.6.524: nur noch Gilden-/Gruppen-Helfer (Berufs-Abklingzeiten der Gilde, Quest-Fortschritt der Gruppe, Rare-Warnung).
-- Instanz-Zaehler, Lehrer, Twink-Gold, Jaeger, Nachkaufen, Ruhestein, Angeln, Sets, Reichweite: Archiv/Komfort/ComfortPlus2_bis_0.6.523.lua
-- Oasis - Helfer, Teil 2: Instanz-Zaehler, neue Zauber beim Lehrer, Berufs-Abklingzeiten der Gilde,
-- Gegenstaende/Gold aller eigenen Charaktere, Quest-Fortschritt der Gruppe, Jaeger-Begleiter,
-- Reagenzien kaufen, Rare-Warnung, Ruhestein/IDs, Angel-Helfer, Ausruestungs-Sets, Reichweite.
-- Einstellungen: Reiter "Helfer"; Uebersicht: /oa chars oder Knopf im Reiter.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Komfort", function()   -- Modul Komfort (abschaltbar, siehe ModuleLoader.lua)
local TIPM = setmetatable({}, { __mode = "k" })   -- Merker je Tooltip (nie Felder auf Blizzard-Frames schreiben)
local L = ns.L
local K, C = ns.K, ns.K.C
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
local Comm, Store = ns.Comm, ns.Store

local CP = ns.ComfortPlus
local H2 = {}
ns.Helpers2 = H2
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function money(c)
    c = math.floor(c or 0)
    return (GetCoinTextureString and GetCoinTextureString(c)) or (math.floor(c / 10000) .. "g")
end
local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 86400 then return ("%d T %d Std"):format(math.floor(sec / 86400), math.floor(sec % 86400 / 3600)) end
    if sec >= 3600 then return ("%d:%02d Std"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%d Min"):format(math.ceil(sec / 60))
end
local function itemCount(id)
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
end
local function char() return ns.db.chars[ns.me()] end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function spellCD(id)
    local s, d
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then s, d = info.startTime, info.duration end
    elseif GetSpellCooldown then
        local ok, a, b = pcall(GetSpellCooldown, id)
        if ok then s, d = a, b end
    end
    if type(s) ~= "number" or type(d) ~= "number" then return nil end
    return s, d
end
local function knows(id)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, id) if ok then return r end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, id) if ok then return r end end
    return false
end

-- neue Helfer einmalig an (Gilden-Meldungen und Kaufen bleiben aus, bis man sie will)
ns.Listen("LOGIN", function()
    local s = S()
    if not s.cp2Init then
        s.cp2Init = true
        -- 0.6.522: nur Gilden-/Gruppen-Helfer an (Raid-IDs, Berufs-Abklingzeiten der Gilde, Quest-Fortschritt der Gruppe, Rare-Warnung)
        for _, k in ipairs({ "cpProfCD", "cpQuestShare", "cpRare" }) do
            if s[k] == nil then s[k] = true end
        end
    end
end)

------------------------------------------------------------------------
-- 3. Berufs-Abklingzeiten (mit der Gilde geteilt)
------------------------------------------------------------------------
-- Schluessel -> Zauber (alle Transmutationen teilen sich eine Abklingzeit)
local PROFCD = {
    { key = "transmute", label = "Transmutation", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 } },
    { key = "mooncloth", label = "Mondstoff", spells = { 18560 } },
    { key = "salt", label = "Salzstreuer", item = 15846 },
}
H2.PROFCD = PROFCD
local function myProfCDs()
    local out = {}
    for _, p in ipairs(PROFCD) do
        if p.spells then
            for _, id in ipairs(p.spells) do
                if knows(id) then
                    local s, d = spellCD(id)
                    local ready = (s and d and d > 2) and math.floor(time() + (s + d - GetTime())) or 0
                    out[p.key] = ready
                    break
                end
            end
        elseif p.item and itemCount(p.item) > 0 then
            local s, d = 0, 0
            if C_Container and C_Container.GetItemCooldown then s, d = C_Container.GetItemCooldown(p.item)
            elseif GetItemCooldown then s, d = GetItemCooldown(p.item) end
            out[p.key] = (d and d > 2) and math.floor(time() + (s + d - GetTime())) or 0
        end
    end
    return out
end
local lastCD
local function shareProfCD()
    if not on("cpProfCD") or ns.inCombat() then return end
    local cds = myProfCDs()
    local parts = {}
    for _, p in ipairs(PROFCD) do if cds[p.key] then parts[#parts + 1] = p.key .. ":" .. cds[p.key] end end
    local s = table.concat(parts, ",")
    if s == "" or s == lastCD then return end
    lastCD = s
    Store.Put("profcd", { id = "pcd-" .. ns.me(), cd = s })
end
local cdPending
ns.On("SPELL_UPDATE_COOLDOWN", function()
    if cdPending then return end
    cdPending = true
    ns.After(3, function() cdPending = nil pcall(shareProfCD) end)
end)
ns.Listen("LOGIN", function() ns.After(8, function() pcall(shareProfCD) end) end)
-- alle Abklingzeiten der Gilde: { { who, key, ready } }
function H2.GuildProfCDs()
    local out = {}
    for _, r in ipairs(Store.List("profcd", function(r) return not r.del end)) do
        for k, ts in (r.cd or ""):gmatch("(%a+):(%d+)") do out[#out + 1] = { who = r.by, key = k, ready = tonumber(ts) } end
    end
    table.sort(out, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.ready < b.ready end)
    return out
end

------------------------------------------------------------------------
-- 5. Quest-Fortschritt der Gruppe (nur Oasis-Mitspieler)
------------------------------------------------------------------------
local partyQ = {}   -- Name -> { [Questtitel] = { "6/10 Kolkar", ... } }
local function myQuests()
    local out = {}
    local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
            local objs = {}
            for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do
                local txt = GetQuestLogLeaderBoard(j, i)
                if txt then objs[#objs + 1] = txt end
            end
            if #objs > 0 then out[title] = objs end
        end
    end
    return out
end
local lastQ = {}
local function sendQuests()
    if not on("cpQuestShare") or not IsInGroup() or ns.inCombat() then return end
    local q = myQuests()
    for title, objs in pairs(q) do
        local s = table.concat(objs, "~")
        if lastQ[title] ~= s then
            lastQ[title] = s
            Comm.Group("QPROG", title, s)
        end
    end
end
local qPending
ns.On("QUEST_LOG_UPDATE", function()
    if qPending then return end
    qPending = true
    ns.After(2, function() qPending = nil pcall(sendQuests) end)
end)
ns.On("GROUP_ROSTER_UPDATE", function() lastQ = {} ns.After(3, function() pcall(sendQuests) end) end)
Comm.On("QPROG", function(sender, _, title, s)
    if not on("cpQuestShare") or not title or ns.isMe(sender) then return end
    -- nur Mitspieler der eigenen Gruppe, Texte entschaerft, Mengen begrenzt
    local sh = ns.short(sender)
    if not ((UnitInParty and UnitInParty(sh)) or (UnitInRaid and UnitInRaid(sh))) then return end
    title = SEC.Text(title, 80)
    local who = ns.fullName(sender)
    partyQ[who] = partyQ[who] or {}
    if not partyQ[who][title] then
        local n = 0
        for _ in pairs(partyQ[who]) do n = n + 1 end
        if n >= 30 then return end
    end
    local old = partyQ[who][title]
    local objs = {}
    for o in tostring(s or ""):sub(1, 600):gmatch("[^~]+") do
        if #objs >= 10 then break end
        objs[#objs + 1] = SEC.Text(o, 80)
    end
    partyQ[who][title] = objs
    -- Ziel gerade fertig geworden? kurz melden, wenn man die Quest selbst hat
    if old and myQuests()[title] then
        for i, o in ipairs(objs) do
            local a, b = o:match("(%d+)/(%d+)")
            local oa = old[i] and old[i]:match("(%d+)/")
            if a and a == b and oa ~= a and SEC.Rate("qprog:" .. who, 3) then
                K.Toast(ns.displayName and ns.displayName(who) or ns.short(who), o, C.mint)
            end
        end
    end
end)
-- Tooltip eines Gruppenmitglieds: gemeinsame Quests
local function questLines(tt, unit)
    if not on("cpQuestShare") or not unit or not (UnitInParty(unit) or UnitInRaid(unit)) or UnitIsUnit(unit, "player") then return end
    local name, realm = ns.UnitName(unit)
    if not name or (issecretvalue and issecretvalue(name)) then return end
    local q = partyQ[ns.fullName(realm and realm ~= "" and (name .. "-" .. realm) or name)]
    if not q then return end
    local mine = myQuests()
    local shown = 0
    for title, objs in pairs(q) do
        if mine[title] and shown < 4 then
            shown = shown + 1
            tt:AddLine("|cffffd24a" .. title .. "|r")
            for _, o in ipairs(objs) do tt:AddLine("  |cffcccccc" .. o .. "|r") end
        end
    end
    if shown > 0 then tt:Show() end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip or ns.inCombat() then return end
        pcall(function() local _, unit = tt:GetUnit() questLines(tt, unit) end)
    end)
elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) if ns.inCombat() then return end pcall(function() local _, unit = tt:GetUnit() questLines(tt, unit) end) end)
end
function H2.PartyQuests() return partyQ end

------------------------------------------------------------------------
-- 8. Rare-Warnung (+ an die Gilde)
------------------------------------------------------------------------
local rareSeen = {}
local function rareCheck(unit)
    if not on("cpRare") or not unit or not UnitExists(unit) then return end
    local cls = UnitClassification(unit)
    if (issecretvalue and issecretvalue(cls)) or (cls ~= "rare" and cls ~= "rareelite") then return end
    if UnitIsDead(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then return end
    local npc = guid:match("%-(%d+)%-%x+$") or guid
    if rareSeen[npc] and GetTime() - rareSeen[npc] < 600 then return end
    rareSeen[npc] = GetTime()
    local name = ns.UnitName(unit)
    local zone = GetZoneText and GetZoneText() or ""
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y = 0, 0
    if pos then x, y = pos:GetXY() end
    K.Toast(L["Seltener Gegner!"], (name or "?") .. "  |cff999999" .. zone .. (" (%.0f, %.0f)"):format(x * 100, y * 100) .. "|r", C.amber or C.accent, nil, "toast")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if on("cpRareShare") and IsInGuild() then Comm.Guild("RARE", name or "?", zone, ("%.1f"):format(x * 100), ("%.1f"):format(y * 100)) end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(u) pcall(rareCheck, u) end)
ns.On("PLAYER_TARGET_CHANGED", function() pcall(rareCheck, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() pcall(rareCheck, "mouseover") end)
Comm.On("RARE", function(sender, _, name, zone, x, y)
    if not on("cpRare") or ns.isMe(sender) then return end
    -- je Absender hoechstens alle 30 s; Texte entschaerft, Koordinaten 0..100
    if not SEC.Rate("rare:" .. sender, 30) then return end
    x, y = SEC.Num(x, 0, 100), SEC.Num(y, 0, 100)
    K.Toast(L["Seltener Gegner (Gilde)"], (L["%s sieht %s - %s (%s, %s)"]):format(ns.displayName and ns.displayName(sender) or ns.short(sender),
        SEC.Text(name or "?", 50), SEC.Text(zone or "", 50), x and ("%.1f"):format(x) or "?", y and ("%.1f"):format(y) or "?"), C.amber or C.accent)
end)

------------------------------------------------------------------------
-- Uebersichtsfenster: Charaktere, Gilden-Abklingzeiten, Sets, Angeln
------------------------------------------------------------------------
local ov
local function clearRows(f)
    for _, r in ipairs(f.rows or {}) do r:Hide() end
    f.nRow = 0
end
local function row(f, y, left, right, color)
    f.nRow = f.nRow + 1
    f.rows = f.rows or {}
    local r = f.rows[f.nRow]
    if not r then
        r = CreateFrame("Frame", nil, f.body)
        r:SetHeight(18)
        r.l = K.Text(r, 11, C.text)
        r.l:SetPoint("LEFT", 0, 0)
        r.r = K.Text(r, 11, C.muted, "RIGHT")
        r.r:SetPoint("RIGHT", 0, 0)
        f.rows[f.nRow] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, y)
    r:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
    r.l:SetText(left or "")
    r.r:SetText(right or "")
    local c = color or C.text
    r.l:SetTextColor(c[1], c[2], c[3])
    r:Show()
    return y - 19
end
local function classColored(name, cls)
    return ns.colorName and ns.colorName(ns.displayName and ns.displayName(name) or name, cls) or name
end
local function fillCDs(f)
    local y = 0
    local list = H2.GuildProfCDs()
    if #list == 0 then return row(f, y, L["Noch keine Abklingzeiten geteilt - wer Transmutation, Mondstoff oder einen Salzstreuer hat, erscheint hier."], "", C.dim) end
    local label = {}
    for _, p in ipairs(PROFCD) do label[p.key] = L[p.label] end
    local lastKey
    for _, e in ipairs(list) do
        if e.key ~= lastKey then
            if lastKey then y = y - 6 end
            y = row(f, y, "|cffffd24a" .. (label[e.key] or e.key) .. "|r", "")
            lastKey = e.key
        end
        local left = e.ready - time()
        y = row(f, y, "   " .. (ns.displayName and ns.displayName(e.who) or ns.short(e.who)),
            left <= 0 and ("|cff66db9e" .. L["bereit"] .. "|r") or ("|cffaaaaaa" .. fmtLeft(left) .. "|r"))
    end
    return y
end
local FILL = { cds = fillCDs }
local function buildOverview()
    local f = CreateFrame("Frame", "OasisHelperOverview", UIParent)
    f:SetSize(460, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true) f:EnableMouse(true) f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, { 0.04, 0.04, 0.05, 0.96 })
    K.Border(f, C.line)
    if K.ApplySkin then K.ApplySkin(f, "panel", { 0.04, 0.04, 0.05, 0.96 }) end
    local title = K.Title(f, 14, C.text)
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Gilden-Abklingzeiten"])
    local x = K.CloseButton(f, function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -6, -6)
    f.seg = K.Segments(f, { { key = "cds", text = L["Abklingzeiten"] } }, function(k) H2.Overview(k) end, nil, { size = 12, pad = 16 })
    f.seg:SetPoint("TOPLEFT", 12, -40)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 16, -76)
    f.body:SetPoint("BOTTOMRIGHT", -16, 14)
    if ns.EscClose then ns.EscClose("OasisHelperOverview") end   -- NICHT UISpecialFrames (sperrt sonst SpellStopCasting/-Targeting)
    f:Hide()
    return f
end
function H2.Overview(tab)
    if not ov then ov = buildOverview() end
    tab = FILL[tab] and tab or "cds"
    ov.tab = tab
    ov.seg:Select(tab)
    clearRows(ov)
    local ok, e = pcall(FILL[tab], ov)
    if not ok then ns.err("Helfer-Uebersicht", e) end
    ov:Show()
    ov:Raise()
end
ns.slash.cds = function() H2.Overview("cds") end

-- fuer die Einstellungen (Reiter "Helfer")
H2.OPTS = {
    { "Gilde & Gruppe", {
        { "cpProfCD", "Berufs-Abklingzeiten mit der Gilde teilen", "Transmutation, Mondstoff, Salzstreuer - wer ist bereit? (Uebersicht)" },
        { "cpQuestShare", "Quest-Fortschritt der Gruppe", "Im Tooltip von Mitspielern mit Oasis, Meldung wenn ein Ziel fertig ist" },
        { "cpRare", "Rare-Warnung", "Ton + Hinweis bei seltenen Gegnern in der Naehe" },
        { "cpRareShare", "Rares an die Gilde melden", "Andere mit Oasis sehen, wo du einen Rare gefunden hast" },
    } },
}
end)

-- Oasis - Helfer: kleine Dinge, fuer die man sonst eigene Addons installiert
-- (EP pro Stunde, Tooltip-Extras, Post "Alles oeffnen", Reagenzien, Flugzeit, Koordinaten,
--  Chat-Links/Klassenfarben/Zeitstempel, Gegenstandsstufe beim Betrachten, Weltkarte aufdecken)
-- Alles einzeln schaltbar (Einstellungen > Komfort > Helfer, Weltkarte: Bereiche > Karte).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Komfort", function()   -- Modul Komfort (abschaltbar, siehe ModuleLoader.lua)
local TIPM = setmetatable({}, { __mode = "k" })   -- Merker je Tooltip (nie Felder auf Blizzard-Frames schreiben)
local L = ns.L
local K, C = ns.K, ns.K.C

local CP = {}
ns.ComfortPlus = CP
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function money(c)
    c = math.floor(c or 0)
    return (GetCoinTextureString and GetCoinTextureString(c)) or (math.floor(c / 10000) .. "g")
end
local function fmtTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then return ("%d:%02d " .. L["Std"]):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return ("%d " .. L["Min"]):format(math.floor(sec / 60 + 0.5)) end
    return ("%d " .. L["Sek"]):format(sec)
end
local function itemInfo(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get or not link then return nil end
    local ok, name, _, quality, ilvl, _, _, _, stack, _, _, sell = pcall(get, link)
    if not ok then return nil end
    return name, quality, ilvl, stack, sell
end
local function itemLevel(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, l = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and type(l) == "number" then return l end
    end
    local _, _, l = itemInfo(link)
    return l
end
-- neue Helfer standardmaessig an (einmalig), Weltkarte aufdecken bleibt aus
ns.Listen("LOGIN", function()
    local s = S()
    -- 0.6.522: Oasis bleibt bei Gilde und Gruppe - persoenliche Helfer (Entzaubern, Questbelohnung, FojjiCore, XP, Post,
    -- Reagenzien, Flugzeit, Haendlerpreis) sind fuer neue Spieler aus; wer sie schon an hatte, behaelt sie
    if not s.cpInit then
        s.cpInit = true
        for _, k in ipairs({ "cpTooltipGuild", "cpChatLinks", "cpInspect" }) do
            if s[k] == nil then s[k] = true end
        end
    end
    -- 0.5.522: Koordinaten kann WoW Forever selbst -> Oasis-Anzeige einmalig aus, Blizzards Weltkarten-Koordinaten an
    if not s.cpCoordsNative then
        s.cpCoordsNative = true
        if s.cpCoords then
            s.cpCoords = false
            if SetCVar and not ns.inCombat() then
                pcall(SetCVar, "worldMapShowPlayerCoords", "1")
                pcall(SetCVar, "worldMapShowCursorCoords", "1")
            end
        end
    end
    ns.After(2, function() pcall(CP.ApplyAll) end)
end)

------------------------------------------------------------------------
-- 2. Tooltip: Gildeninfos und Gegenstandsstufe beim Betrachten (0.6.524: Haendlerpreis/ID/Entzaubern im Archiv)
------------------------------------------------------------------------
local INSPECT = {}   -- Name -> { ilvl, ts }
local function profIcons(profs)
    local out = {}
    for part in (profs or ""):gmatch("[^+]+") do
        local nm, cur, max = part:match("^([^/]+)/(%d+)/(%d+)")
        if nm then out[#out + 1] = L[nm] .. " " .. cur end
    end
    return table.concat(out, ", ")
end
local function unitLines(tt, unit)
    if not unit or ns.inCombat() then return end
    if not UnitIsPlayer(unit) then return end
    local name, realm = ns.UnitName(unit)
    if not name or (issecretvalue and issecretvalue(name)) then return end
    local full = ns.fullName(realm and realm ~= "" and (name .. "-" .. realm) or name)
    if on("cpTooltipGuild") then
        local p = ns.db.members[full]
        if p then
            if ns.Rank and ns.Rank.Verified and ns.Rank.LevelFor then
                local rx = ns.Rank.Verified(full)
                if rx then
                    local rl = ns.Rank.LevelFor(rx)
                    tt:AddDoubleLine(L["Oasis-Rang"], rl .. "  " .. (ns.Rank.Title(rl) or ""), 0.85, 0.85, 0.85, 1, 0.82, 0.29)
                end
            end
            if ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(full) then
                local main = ns.Alts.Main(full)
                tt:AddDoubleLine(L["Twink von"], ns.displayName and ns.displayName(main) or main, 0.85, 0.85, 0.85, 1, 1, 1)
            end
            local pr = profIcons(p.profs)
            if pr ~= "" then tt:AddLine("|cff999999" .. pr .. "|r", nil, nil, nil, true) end
        end
    end
    if on("cpInspect") then
        local e = INSPECT[full]
        if e and ns.now() - e.ts < 3600 then
            local mine = CP.MyItemLevel()
            local diff = mine and (e.ilvl - mine) or 0
            local dc = diff > 0 and "|cff66db9e+" or (diff < 0 and "|cffff6a5a" or "|cff888888±")
            tt:AddDoubleLine(L["Gegenstandsstufe"], ("%.1f  %s%.1f|r"):format(e.ilvl, dc, math.abs(diff)), 0.85, 0.85, 0.85, 1, 1, 1)
        end
    end
    tt:Show()
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        pcall(function() local _, unit = tt:GetUnit() unitLines(tt, unit) end)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    if GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(function() local _, unit = tt:GetUnit() unitLines(tt, unit) end) end)
    end
end
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function(tt) TIPM[tt] = nil end)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", function(tt) TIPM[tt] = nil end) end
end

------------------------------------------------------------------------
-- 7. Chat: Links kopieren, Klassenfarben, Zeitstempel
------------------------------------------------------------------------
local URL_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
-- "addon:"-Links: Blizzard leitet sie selbst weiter, Oasis haengt sich nur per hooksecurefunc an
-- (frueher wurde SetItemRef ersetzt -> verseuchte jeden Link-Klick im Chat)
local function linksOk() return (LinkTypes and LinkTypes.addon ~= nil) or (EventRegistry ~= nil and LinkUtil ~= nil) end
local function linkify(u)
    if not linksOk() then return "|cff6ab0ff" .. u .. "|r" end
    return "|cff6ab0ff|Haddon:Oasis:url:" .. u .. "|h[" .. u .. "]|h|r"
end
local function urlFilter(_, _, msg, ...)
    if not on("cpChatLinks") or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
    if not (msg:find("://", 1, true) or msg:find("www%.") or msg:find("%a%.%a%a")) then return false end
    local out, n = msg:gsub("(%a+://[^%s|]+)", linkify)
    if n == 0 then out, n = msg:gsub("(www%.[%w%-%.]+%.%a%a+[^%s|]*)", linkify) end
    if n == 0 then out, n = msg:gsub("^([%w%-]+%.[%w%-]+%.%a%a+/?[^%s|]*)", linkify) end
    if n == 0 then out, n = msg:gsub("%s([%w%-]+%.%a%a%a?/[^%s|]*)", function(u) return " " .. linkify(u) end) end
    if n == 0 then return false end
    return false, out, ...
end
if ChatFrame_AddMessageEventFilter then
    for _, e in ipairs(URL_EVENTS) do pcall(ChatFrame_AddMessageEventFilter, e, urlFilter) end
end
local function copyBox(text)
    if not CP.copy then
        local f = K.Window and K.Window(UIParent, 420, 90) or CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(420, 90)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        if not K.Window then K.Fill(f, C.bg or { 0.05, 0.05, 0.06, 0.95 }) K.Border(f, C.line) end
        f.title = K.Text(f, 12, C.text)
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.title:SetText(L["Link kopieren (Strg+C)"])
        f.input = K.Input(f, 392, "", function() end)
        f.input:SetPoint("TOPLEFT", 14, -38)
        f.input:SetScript("OnEscapePressed", function() f:Hide() end)
        f.input:SetScript("OnEnterPressed", function() f:Hide() end)
        local x = K.Button(f, L["Schliessen"], 90, 22, "ghost", function() f:Hide() end)
        x:SetPoint("BOTTOMRIGHT", -12, 8)
        CP.copy = f
    end
    CP.copy:Show()
    CP.copy.input:SetText(text)
    CP.copy.input:SetFocus()
    CP.copy.input:HighlightText()
end
if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link)
        local u = type(link) == "string" and link:match("^addon:Oasis:url:(.+)$")
        if u then pcall(copyBox, u) end
    end)
end
local CLASS_CHATS = { "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
    "CHANNEL1", "CHANNEL2", "CHANNEL3", "CHANNEL4", "CHANNEL5", "CHANNEL6", "CHANNEL7", "CHANNEL8", "CHANNEL9", "CHANNEL10" }
function CP.ApplyChat()
    if ns.inCombat() then return end
    local want = on("cpChatLinks")
    -- nur einmal umstellen, danach gehoert die Einstellung wieder dem Spieler
    if want and not S().cpChatApplied then
        S().cpChatApplied = true
        if SetChatColorNameByClass then
            for _, t in ipairs(CLASS_CHATS) do pcall(SetChatColorNameByClass, t, true) end
        end
        -- Zeitstempel: Blizzards eigene Chat-Einstellung (0.5.522: Oasis setzt sie nicht mehr an oder aus)
    elseif not want and S().cpChatApplied then
        S().cpChatApplied = nil
    end
end

------------------------------------------------------------------------
-- 8. Gegenstandsstufe beim Betrachten
------------------------------------------------------------------------
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function avgLevel(unit)
    local sum, n, twoHand = 0, 0, false
    for _, s in ipairs(ILVL_SLOTS) do
        local link = GetInventoryItemLink(unit, s)
        if link then
            local l = itemLevel(link)
            if l then
                sum, n = sum + l, n + 1
                if s == 16 then
                    local equip = select(9, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
                    twoHand = equip == "INVTYPE_2HWEAPON"
                end
            end
        end
    end
    if n == 0 then return nil end
    -- Zweihaender zaehlt doppelt (wie bei Blizzard)
    if twoHand and not GetInventoryItemLink(unit, 17) then sum, n = sum + (sum / n), n + 1 end
    return sum / math.max(n, 16)
end
function CP.MyItemLevel() return avgLevel("player") end
ns.On("INSPECT_READY", function(guid)
    if not on("cpInspect") then return end
    pcall(function()
        local unit
        for _, u in ipairs({ "target", "mouseover", "party1", "party2", "party3", "party4" }) do
            if UnitGUID(u) == guid then unit = u break end
        end
        if not unit then return end
        local l = avgLevel(unit)
        if not l then return end
        local name, realm = ns.UnitName(unit)
        local full = ns.fullName(realm and realm ~= "" and (name .. "-" .. realm) or name)
        INSPECT[full] = { ilvl = l, ts = ns.now() }
        if InspectFrame and InspectFrame:IsShown() then
            if not CP.inspText then
                CP.inspText = InspectFrame:CreateFontString(nil, "OVERLAY")
                if K.SetFontSafe then K.SetFontSafe(CP.inspText, K.FONT, 12, "OUTLINE", K.FONT) else CP.inspText:SetFont(K.FONT, 12, "OUTLINE") end
                CP.inspText:SetPoint("BOTTOMLEFT", InspectFrame, "BOTTOMLEFT", 26, 86)
            end
            local mine = CP.MyItemLevel() or 0
            local d = l - mine
            CP.inspText:SetText(("%s %.1f  |cff%s(%s%.1f)|r"):format(L["Stufe"], l, d >= 0 and "66db9e" or "ff6a5a", d >= 0 and "+" or "-", math.abs(d)))
            CP.inspText:Show()
        end
    end)
end)

------------------------------------------------------------------------
-- 9. Weltkarte aufdecken (Standard aus, Einstellung bei der Karte)
------------------------------------------------------------------------
-- Daten: ns.MapRevealData[uiMapID] = { "w:h:x:y:tex1,tex2,...", ... } (Kern/Karte/MapRevealData.lua)
local revealPool = {}
local function revealRefresh()
    for _, t in ipairs(revealPool) do t:Hide() end
    if not on("mapReveal") or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local data = ns.MapRevealData
    local mapID = WorldMapFrame:GetMapID()
    local list = data and mapID and data[mapID]
    if not list then return end
    -- schon erkundete Flaechen lassen wir Blizzard zeichnen
    local known = {}
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        local ok, ex = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
        if ok and type(ex) == "table" then
            for _, e in ipairs(ex) do known[(e.offsetX or 0) .. ":" .. (e.offsetY or 0)] = true end
            -- 0.6.520: Forever hat manche Karten neu gezeichnet (z. B. Mulgore). Passen die erkundeten Flaechen des
            -- Spiels nicht zu unseren 1.15-Daten, ist die Karte geaendert -> nichts aufdecken (sonst alte Karte drueber)
            if #ex > 0 then
                local mine = {}
                for _, entry in ipairs(list) do
                    local ox, oy = entry:match("^%d+:%d+:(%d+):(%d+):")
                    if ox then mine[ox .. ":" .. oy] = true end
                end
                local miss = 0
                for _, e in ipairs(ex) do if not mine[(e.offsetX or 0) .. ":" .. (e.offsetY or 0)] then miss = miss + 1 end end
                if miss > 0 then return end
            end
        end
    end
    local canvas = WorldMapFrame:GetCanvas()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local lw = layers and layers[1] and layers[1].layerWidth or 1002
    local lh = layers and layers[1] and layers[1].layerHeight or 668
    local sx, sy = cw / lw, ch / lh
    local k = 0
    for _, entry in ipairs(list) do
        local w, h, ox, oy, texs = entry:match("^(%d+):(%d+):(%d+):(%d+):(.+)$")
        w, h, ox, oy = tonumber(w), tonumber(h), tonumber(ox), tonumber(oy)
        if w and not known[ox .. ":" .. oy] then
            local ids = {}
            for id in texs:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
            local cols = math.ceil(w / 256)
            local rows = math.ceil(h / 256)
            for r = 1, rows do
                for c = 1, cols do
                    local id = ids[(r - 1) * cols + c]
                    if id then
                        k = k + 1
                        local t = revealPool[k]
                        if not t then
                            t = canvas:CreateTexture(nil, "ARTWORK", nil, -1)
                            revealPool[k] = t
                        end
                        local tw = (c < cols) and 256 or (w - 256 * (cols - 1))
                        local th = (r < rows) and 256 or (h - 256 * (rows - 1))
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (ox + 256 * (c - 1)) * sx, -(oy + 256 * (r - 1)) * sy)
                        t:SetSize(tw * sx, th * sy)
                        -- Dateigroesse = naechste Zweierpotenz (wie bei Blizzard)
                        local fw, fh = 16, 16
                        while fw < tw do fw = fw * 2 end
                        while fh < th do fh = fh * 2 end
                        t:SetTexCoord(0, tw / fw, 0, th / fh)
                        t:SetTexture(id)
                        -- unerforscht = abgedunkelt
                        t:SetVertexColor(0.55, 0.55, 0.6)
                        t:SetAlpha(0.85)
                        t:Show()
                    end
                end
            end
        end
    end
end
CP.ApplyReveal = function() pcall(revealRefresh) end
local revealHooked
local function hookReveal()
    if revealHooked or not WorldMapFrame then return end
    revealHooked = true
    WorldMapFrame:HookScript("OnShow", function() pcall(revealRefresh) end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() pcall(revealRefresh) end) end
end

function CP.ApplyAll()
    pcall(CP.ApplyChat)
    pcall(hookReveal)
    pcall(revealRefresh)
end

------------------------------------------------------------------------
-- Einstellungen: eigener Reiter "Helfer"
------------------------------------------------------------------------
local OPTS = {
    -- 0.6.524: nur noch Gilden-/Gruppen-Helfer - XP, Munition, Flugzeit, Suche, Haendlerpreis, Entzaubern, Post liegen im Archiv
    { "Tooltip & Chat", {
        { "cpTooltipGuild", "Tooltip: Gildeninfos", "Oasis-Rang, Twink von ... und Berufe bei Gildenmitgliedern" },
        { "cpInspect", "Gegenstandsstufe beim Betrachten", "Im Betrachten-Fenster und danach im Tooltip, mit Vergleich zu dir" },
        { "cpChatLinks", "Chat: Links kopieren, Klassenfarben", "Links anklicken = Kopierfenster. Uhrzeit im Chat: Blizzards Chat-Einstellung (Zeitstempel).", CP.ApplyChat },
        { "fojjiBridge", "Mit FojjiCore zusammenarbeiten", "Ist FojjiCore installiert, oeffnet Oasis dessen Dungeon-Journal und kann dessen Wunschliste in die Gilden-Wunschliste uebernehmen" },
    } },
}
local function build(f)
    local H = ns.SettingsHelpers
    f.noCompact = true
    -- scrollbar (viele Helfer): Mausrad + schmale Leiste
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", 0, 0)
    local body = CreateFrame("Frame", nil, sf)
    body:SetSize(770, 900)
    sf:SetScrollChild(body)
    sf.bar = sf:CreateTexture(nil, "OVERLAY")
    sf.bar:SetWidth(3)
    sf.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    local function updBar()
        local h, ch = sf:GetHeight() or 0, body:GetHeight() or 0
        local max = math.max(0, ch - h)
        sf.bar:SetShown(max > 0 and h > 0)
        if max > 0 and h > 0 then
            local th = math.max(24, h * h / ch)
            sf.bar:ClearAllPoints()
            sf.bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -(h - th) * ((sf:GetVerticalScroll() or 0) / max))
            sf.bar:SetHeight(th)
        end
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (body:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
        updBar()
    end)
    sf:SetScript("OnSizeChanged", function() updBar() end)
    -- Knopf zur Uebersicht
    local ovb = K.Button(body, L["Gilden-Abklingzeiten"], 260, 26, "primary", function()
        if ns.Helpers2 then ns.Helpers2.Overview() end
    end)
    ovb:SetPoint("TOPLEFT", 0, 0)
    if H.note then H.note(body, L["Wer aus der Gilde Transmutation, Mondstoff oder Salzstreuer bereit hat (/oa cds)"], 272, -6, 480) end
    -- Gruppen: links und rechts abwechselnd, jede Spalte stapelt fuer sich
    local groups = {}
    for _, g in ipairs(OPTS) do groups[#groups + 1] = g end
    for _, g in ipairs(ns.Helpers2 and ns.Helpers2.OPTS or {}) do groups[#groups + 1] = g end
    local colY = { -44, -44 }
    for gi, grp in ipairs(groups) do
        local c = (colY[1] >= colY[2]) and 1 or 2
        local x, y = c == 1 and 0 or 376, colY[c]
        -- 0.5.720: je Gruppe eine Glas-Karte (Titel in der Karte, Schalter darin)
        local h = 50 + #grp[2] * 28 + 8
        local card = H.cardH(body, x, y, 362, h, "home", L[grp[1]])
        local cy = -48
        for _, o in ipairs(grp[2]) do
            H.toggle(card, 14, cy, o[2], o[1], o[3], o[4] and function() pcall(o[4]) end or nil, 334)
            cy = cy - 28
        end
        colY[c] = y - h - 12
    end
    local bottom = math.min(colY[1], colY[2])
    if H.note then H.note(body, L["Weltkarte aufdecken findest du unter der Weltkarte und unter Bereiche > Karte."], 0, bottom - 6, 760) end
    body:SetHeight(-bottom + 40)
    ns.After(0.1, updBar)
end
if ns.AddSettingsTab then ns.AddSettingsTab("helpers", "Helfer", build) end
end)

-- Oasis - neue WoW-Forever-Quests erkennen und im Questlog markieren (bläulicher Verlauf + "Neu"),
-- Gruppenquests hervorheben. Forever-Quests haben eigene, hohe Quest-IDs (Classic geht nur bis ca. 10000).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Questmarken", function()   -- Modul Quest-Markierungen (abschaltbar, siehe ModuleLoader.lua)
local DECO = setmetatable({}, { __mode = "k" })   -- eigene Texturen je Questlog-Knopf (keine Felder auf Blizzard-Knoepfen)
local L = ns.L
local K, C = ns.K, ns.K.C

function ns.IsForeverQuest(questID)
    questID = tonumber(questID)
    return questID ~= nil and questID >= 20000
end

local function decorate(btn, questID, isGroup)
    if not btn or not questID then return end
    local new = ns.IsForeverQuest(questID) and not (ns.db and ns.db.settings.questTags == false)
    local grp = isGroup and not (ns.db and ns.db.settings.questTags == false)
    if not DECO[btn] then
        if not (new or grp) then return end
        local g = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        g:SetPoint("TOPLEFT", 0, 0)
        g:SetPoint("BOTTOMRIGHT", 0, 0)
        DECO[btn] = { g = g }
        local t = btn:CreateFontString(nil, "OVERLAY")
        if K.SetFontSafe then K.SetFontSafe(t, K.FONT, 9, "OUTLINE", K.FONT) else t:SetFont(K.FONT, 9, "OUTLINE") end
        -- links neben dem Haken/Fortschritt, nicht darueber
        t:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
        DECO[btn].t = t
    end
    local g, t = DECO[btn].g, DECO[btn].t
    if new then
        if not K.Gradient(g, "HORIZONTAL", { 0.3, 0.55, 1, 0.35 }, { 0.3, 0.55, 1, 0 }) then g:SetColorTexture(0.3, 0.55, 1, 0.15) end
        t:SetText("|cff8fbaff" .. L["NEU"] .. "|r" .. (grp and "  |cffff8a3d" .. L["Gruppe"] .. "|r" or ""))
    elseif grp then
        if not K.Gradient(g, "HORIZONTAL", { 1, 0.55, 0.25, 0.22 }, { 1, 0.55, 0.25, 0 }) then g:SetColorTexture(1, 0.55, 0.25, 0.1) end
        t:SetText("|cffff8a3d" .. L["Gruppe"] .. "|r")
    end
    g:SetShown(new or grp)
    t:SetShown(new or grp)
end

local function groupOf(questID, idx)
    local Q = C_QuestLog
    if Q and Q.GetLogIndexForQuestID and Q.GetInfo then
        local i = idx or Q.GetLogIndexForQuestID(questID)
        local ok, info = pcall(Q.GetInfo, i or 0)
        if ok and type(info) == "table" then return (tonumber(info.suggestedGroup) or 0) > 1 end
    end
    return false
end

-- neues Questlog (Karte & Questlog)
local function updateMapLog()
    local sf = QuestScrollFrame
    local contents = sf and (sf.Contents or sf.contents)
    if not contents then return end
    for _, child in ipairs({ contents:GetChildren() }) do
        local id = child.questID or (child.info and child.info.questID)
        -- nur die Titel-Zeilen (Knoepfe), nicht die Ziel-Zeilen darunter
        local isTitle = child.GetObjectType and child:GetObjectType() == "Button" and child.Text ~= nil
        if id and isTitle then pcall(decorate, child, id, groupOf(id)) elseif DECO[child] then DECO[child].g:Hide() DECO[child].t:Hide() end
    end
end
-- klassisches Questlog (Liste)
local function updateClassicLog()
    local n = QUESTS_DISPLAYED or 0
    for i = 1, n do
        local btn = _G["QuestLogTitle" .. i]
        if btn and btn:IsShown() then
            local idx = btn.GetID and btn:GetID()
            local ok, info = pcall(C_QuestLog.GetInfo, idx or 0)
            if ok and type(info) == "table" and not info.isHeader and info.questID then
                pcall(decorate, btn, info.questID, (tonumber(info.suggestedGroup) or 0) > 1)
            elseif DECO[btn] then
                DECO[btn].g:Hide() DECO[btn].t:Hide()
            end
        end
    end
end
ns.Listen("LOGIN", function()
    if type(QuestLogQuests_Update) == "function" then hooksecurefunc("QuestLogQuests_Update", function() pcall(updateMapLog) end) end
    if type(QuestLog_Update) == "function" then hooksecurefunc("QuestLog_Update", function() pcall(updateClassicLog) end) end
end)

------------------------------------------------------------------------
-- Questfenster (Annehmen / Abgeben): neue Forever-Quests bekommen unten einen leichten blauen Verlauf nach oben
------------------------------------------------------------------------
do
    local holder
    local function paint()
        if not QuestFrame then return end
        local id = GetQuestID and ns.safe(GetQuestID())
        local on = ns.IsForeverQuest(id) and not (ns.db and ns.db.settings.questTags == false)
        if not on then if holder then holder:Hide() end return end
        local sf
        for _, n in ipairs({ "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame" }) do
            local f = _G[n]
            if f and f:IsVisible() then sf = f break end
        end
        if not sf then if holder then holder:Hide() end return end
        if not holder then
            holder = CreateFrame("Frame", nil, QuestFrame)
            holder.g = holder:CreateTexture(nil, "BACKGROUND")
            holder.g:SetPoint("BOTTOMLEFT")
            holder.g:SetPoint("BOTTOMRIGHT")
        end
        holder:ClearAllPoints()
        holder:SetAllPoints(sf)
        holder:SetFrameLevel(sf:GetFrameLevel())
        holder.g:SetHeight(math.max(60, (sf:GetHeight() or 300) * 0.45))
        if not K.Gradient(holder.g, "VERTICAL", { 0.3, 0.55, 1, 0.30 }, { 0.3, 0.55, 1, 0 }) then holder.g:SetColorTexture(0.3, 0.55, 1, 0.10) end
        holder:Show()
    end
    for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
        ns.On(e, function() ns.After(0.05, function() pcall(paint) end) end)
    end
    ns.On("QUEST_FINISHED", function() if holder then holder:Hide() end end)
end

------------------------------------------------------------------------
-- Questbelohnung zur Auswahl: die beste Wahl markieren - ein Upgrade (gruen), sonst der beste Haendlerpreis (gold).
-- Nur Teile, die der Charakter wirklich benutzen kann (WoW meldet das je Belohnung selbst, inkl. fehlender Waffenfertigkeit).
-- Merker in einer Weak-Table, keine eigenen Felder an Blizzards Knoepfen.
------------------------------------------------------------------------
do
    local REW = setmetatable({}, { __mode = "k" })
    local function rewardButton(i)
        local rf = QuestInfoRewardsFrame
        if rf and rf.RewardButtons and rf.RewardButtons[i] then return rf.RewardButtons[i] end
        return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
    end
    -- ohne Text: leichter Verlauf ueber die Belohnung und ein kleines Zeichen auf der Ecke des Symbols
    -- (gruener Pfeil = Verbesserung, Muenze = bester Haendlerpreis)
    local function mark(btn, kind)
        local m = REW[btn]
        if not m then
            if not kind then return end
            m = CreateFrame("Frame", nil, btn)
            m:SetAllPoints()
            m:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
            m.g = m:CreateTexture(nil, "ARTWORK")
            m.g:SetAllPoints()
            m.ic = m:CreateTexture(nil, "OVERLAY")
            m.ic:SetSize(16, 16)
            m.ic:SetPoint("TOPLEFT", -3, 3)
            REW[btn] = m
        end
        m:SetShown(kind ~= nil)
        if not kind then return end
        local c = kind == "better" and { 0.25, 0.90, 0.45 } or { 1, 0.80, 0.25 }
        if not K.Gradient(m.g, "HORIZONTAL", { c[1], c[2], c[3], 0.30 }, { c[1], c[2], c[3], 0 }) then m.g:SetColorTexture(c[1], c[2], c[3], 0.10) end
        m.ic:SetVertexColor(1, 1, 1)
        if kind == "better" then
            if not (m.ic.SetAtlas and pcall(m.ic.SetAtlas, m.ic, "bags-greenarrow") and m.ic:GetAtlas()) then
                m.ic:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
                m.ic:SetVertexColor(0.3, 1, 0.45)
            end
        else
            m.ic:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        end
    end
    local function rate(retry)
        for i = 1, 10 do local b = rewardButton(i) if b and REW[b] then REW[b]:Hide() end end
        if ns.db and ns.db.settings.cpQuestReward == false then return end
        local n = GetNumQuestChoices and ns.safe(GetNumQuestChoices()) or 0
        if type(n) ~= "number" or n <= 1 then return end
        local best, bestPct, rich, richPrice, missing = nil, 0, nil, 0, false
        for i = 1, n do
            local link = GetQuestItemLink and ns.safe(GetQuestItemLink("choice", i))
            if not link then missing = true else
                local _, _, cnt, _, usable = GetQuestItemInfo("choice", i)
                usable, cnt = ns.safe(usable), ns.safe(cnt)
                -- nicht benutzbar (Klasse oder fehlende Waffenfertigkeit): nie als Verbesserung vorschlagen
                local pct = usable ~= false and ns.Upgrade and ns.Upgrade.Compare and ns.Upgrade.Compare(link) or nil
                if pct and pct > bestPct then best, bestPct = i, pct end
                local price = select(11, C_Item.GetItemInfo(link))
                if price == nil then missing = true end
                price = (tonumber(price) or 0) * (tonumber(cnt) or 1)
                if price > richPrice then rich, richPrice = i, price end
            end
        end
        if missing and not retry then ns.After(0.4, function() pcall(rate, true) end) end
        local pick, kind = best or rich, best and "better" or "sell"
        local b = pick and rewardButton(pick)
        if b then mark(b, kind) end
    end
    ns.QuestRewardMarks = true   -- nesUI zeichnet dann nicht selbst
    ns.On("QUEST_COMPLETE", function() ns.After(0.05, function() pcall(rate) end) end)
end
end)

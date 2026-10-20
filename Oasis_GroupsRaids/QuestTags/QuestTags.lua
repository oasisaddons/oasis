-- Oasis - detect new WoW Forever quests and mark them in the quest log (bluish gradient + "New"),
-- Highlight group quests. Forever quests have their own high quest IDs (Classic only goes up to ~10000).
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_QuestTags", function()   -- Module Quest markers (can be disabled, see ModuleLoader.lua)
local DECO = setmetatable({}, { __mode = "k" })   -- own textures per quest log button (no fields on Blizzard buttons)
local L = ns.L
local K, C = ns.K, ns.K.C

function ns.IsForeverQuest(questID)
    questID = tonumber(questID)
    return questID ~= nil and questID >= 20000
end

local function decorate(btn, questID, isGroup)
    if not btn or not questID then return end
    -- 0.6.524: focus on group quests - "NEW" for Forever quests only with its own toggle (default off)
    -- 19.10.2026: always on with the add-on addon "Oasis - Komfort" (Plugins/Oasis_Comfort)
    local new = ns.IsForeverQuest(questID) and ns.db and (ns.db.settings.questTagsNew == true or ns.ComfortPlugin == true)
    local grp = isGroup and not (ns.db and ns.db.settings.questTags == false)
    if not DECO[btn] then
        if not (new or grp) then return end
        local g = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        g:SetPoint("TOPLEFT", 0, 0)
        g:SetPoint("BOTTOMRIGHT", 0, 0)
        DECO[btn] = { g = g }
        local t = btn:CreateFontString(nil, "OVERLAY")
        if K.SetFontSafe then K.SetFontSafe(t, K.FONT, 9, "OUTLINE", K.FONT) else t:SetFont(K.FONT, 9, "OUTLINE") end
        -- left of the checkmark/progress, not above it
        t:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
        DECO[btn].t = t
    end
    local g, t = DECO[btn].g, DECO[btn].t
    if new then
        if not K.Gradient(g, "HORIZONTAL", { 0.3, 0.55, 1, 0.35 }, { 0.3, 0.55, 1, 0 }) then g:SetColorTexture(0.3, 0.55, 1, 0.15) end
        t:SetText("|cff8fbaff" .. L["NEW"] .. "|r" .. (grp and "  |cffff8a3d" .. L["Group"] .. "|r" or ""))
    elseif grp then
        if not K.Gradient(g, "HORIZONTAL", { 1, 0.55, 0.25, 0.22 }, { 1, 0.55, 0.25, 0 }) then g:SetColorTexture(1, 0.55, 0.25, 0.1) end
        t:SetText("|cffff8a3d" .. L["Group"] .. "|r")
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

-- new quest log (map & quest log)
local function updateMapLog()
    local sf = QuestScrollFrame
    local contents = sf and (sf.Contents or sf.contents)
    if not contents then return end
    for _, child in ipairs({ contents:GetChildren() }) do
        local id = child.questID or (child.info and child.info.questID)
        -- only the title rows (buttons), not the objective rows below
        local isTitle = child.GetObjectType and child:GetObjectType() == "Button" and child.Text ~= nil
        if id and isTitle then pcall(decorate, child, id, groupOf(id)) elseif DECO[child] then DECO[child].g:Hide() DECO[child].t:Hide() end
    end
end
-- classic quest log (list)
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
-- Quest window (accept / turn in): new Forever quests get a light blue gradient upward at the bottom
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

-- Marking quest rewards (best choice / most valuable) lives in the add-on addon since 19.10.2026
-- "Oasis - Komfort" (Plugins/Oasis_Comfort/Comfort.lua).
end)

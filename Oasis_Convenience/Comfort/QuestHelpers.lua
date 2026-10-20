-- Oasis - Comfort (formerly a separate add-on addon): personal helpers that are no longer in the
-- main addon since 0.6.524 (focus on guild/group). Whoever wants them installs this addon in addition.
-- Hooks onto the global table Oasis (= ns of the main addon).
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()   -- 0.6.569: formerly plugin Oasis_Comfort, now part of Oasis Convenience
local O = ns
local K = O.K

-- Quest log: new WoW Forever quests with blue gradient + "NEW" (QuestTags.lua queries O.ComfortPlugin)
O.ComfortPlugin = true

local function isForever(id)
    if O.IsForeverQuest then return O.IsForeverQuest(id) end
    id = tonumber(id)
    return id ~= nil and id >= 20000
end

------------------------------------------------------------------------
-- Quest reward choice: mark the best pick - upgrade (green arrow), otherwise the best
-- vendor price (gold coin = most valuable). Only pieces the character can use (WoW reports this per reward,
-- incl. missing weapon skill). Markers in a weak table, no own fields on Blizzard's buttons.
------------------------------------------------------------------------
local REW = setmetatable({}, { __mode = "k" })
local function rewardButton(i)
    local rf = QuestInfoRewardsFrame
    if rf and rf.RewardButtons and rf.RewardButtons[i] then return rf.RewardButtons[i] end
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
end

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
    if not (K.Gradient and K.Gradient(m.g, "HORIZONTAL", { c[1], c[2], c[3], 0.30 }, { c[1], c[2], c[3], 0 })) then
        m.g:SetColorTexture(c[1], c[2], c[3], 0.10)
    end
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

local function safe(v) if O.safe then return O.safe(v) end return v end

local function rate(retry)
    for i = 1, 10 do local b = rewardButton(i) if b and REW[b] then REW[b]:Hide() end end
    local n = GetNumQuestChoices and safe(GetNumQuestChoices()) or 0
    if type(n) ~= "number" or n <= 1 then return end
    local best, bestPct, rich, richPrice, missing = nil, 0, nil, 0, false
    for i = 1, n do
        local link = GetQuestItemLink and safe(GetQuestItemLink("choice", i))
        if not link then missing = true else
            local _, _, cnt, _, usable = GetQuestItemInfo("choice", i)
            usable, cnt = safe(usable), safe(cnt)
            -- not usable (class or missing weapon skill): never suggest as upgrade
            local pct
            if usable ~= false and O.Upgrade and O.Upgrade.Compare then
                local ok, p = pcall(O.Upgrade.Compare, link)
                if ok then pct = p end
            end
            if pct and pct > bestPct then best, bestPct = i, pct end
            local price = select(11, C_Item.GetItemInfo(link))
            if price == nil then missing = true end
            price = (tonumber(price) or 0) * (tonumber(cnt) or 1)
            if price > richPrice then rich, richPrice = i, price end
        end
    end
    if missing and not retry then C_Timer.After(0.4, function() pcall(rate, true) end) end
    local pick, kind = best or rich, best and "better" or "sell"
    local b = pick and rewardButton(pick)
    if b then mark(b, kind) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, e)
    if e == "QUEST_COMPLETE" then
        C_Timer.After(0.05, function() pcall(rate) end)
    elseif e == "PLAYER_LOGIN" then
        -- redraw quest log immediately so the Forever marker appears without detour
        if type(QuestLog_Update) == "function" and QuestLogFrame and QuestLogFrame:IsShown() then pcall(QuestLog_Update) end
    end
end)
local _ = isForever
end)

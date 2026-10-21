-- Oasis - Comfort: more everyday helpers (0.6.606), each off until switched on (Comfort settings > More helpers).
-- Own implementation (ideas as common in tweak addons, no code taken over).
--   flight master: straight to the flight map · battleground: release automatically · Alt+right-click: mark as junk
--   Ctrl+right-click: gear groups, equip a group with one click · quest log: quest levels · trainer: "Train all"
--   fishing: double right-click casts · auction house: item level in the list · camera further out · no screen glow
--   tooltips: class-coloured names, health bar inside · /rl
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()
local L = ns.L
local K, C = ns.K, ns.K.C

local TW = {}
ns.ComfortTweaks = TW
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function combat() return InCombatLockdown and InCombatLockdown() end

------------------------------------------------------------------------
-- flight master: straight to the flight map (Shift = talk normally)
------------------------------------------------------------------------
local TAXI_ICON = 132057
function TW.TaxiOption(options)
    for _, o in ipairs(options or {}) do
        local icon = o.icon
        if icon == TAXI_ICON or o.type == "taxi" or (type(icon) == "string" and icon:lower():find("taxi")) then return o end
    end
end
ns.On("GOSSIP_SHOW", function()
    if not on("twTaxi") or IsShiftKeyDown() or not (C_GossipInfo and C_GossipInfo.GetOptions) then return end
    local ok, opts = pcall(C_GossipInfo.GetOptions)
    local o = ok and TW.TaxiOption(ns.safe(opts))
    if o and o.gossipOptionID then pcall(C_GossipInfo.SelectOption, o.gossipOptionID) end
end)

------------------------------------------------------------------------
-- battleground: release right away (not with a soulstone)
------------------------------------------------------------------------
ns.On("PLAYER_DEAD", function()
    if not on("twBgRelease") then return end
    local _, kind = IsInInstance()
    if kind ~= "pvp" then return end
    if HasSoulstone and HasSoulstone() then return end
    local function go() if UnitIsDead("player") and not UnitIsGhost("player") and RepopMe then pcall(RepopMe) end end
    if C_Timer then C_Timer.After(0.6, go) else go() end
end)

------------------------------------------------------------------------
-- bag items: Alt+right-click = junk mark, Ctrl+right-click = gear group
------------------------------------------------------------------------
TW.GROUPS = { { key = "dps", text = "DPS", color = { 0.95, 0.35, 0.3 } }, { key = "tank", text = "Tank", color = { 0.45, 0.65, 1 } },
    { key = "heal", text = "Heal", color = { 0.4, 0.9, 0.5 } }, { key = "pvp", text = "PvP", color = { 0.95, 0.75, 0.3 } },
    { key = "farm", text = "Farm", color = { 0.75, 0.55, 0.95 } } }
local function itemAt(bag, slot)
    local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
    return info and info.itemID, info
end
function TW.IsJunk(id) return id and S().twJunk and S().twJunk[id] or false end
function TW.ToggleJunk(id)
    if not id then return end
    S().twJunk = S().twJunk or {}
    S().twJunk[id] = (not S().twJunk[id]) or nil
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or tostring(id)
    ns.print((S().twJunk[id] and L["Marked as junk: %s"] or L["No longer junk: %s"]):format(name or "?"))
    TW.UpdateBags()
end
function TW.GroupOf(id)
    for _, g in ipairs(TW.GROUPS) do if S().twGearSets and S().twGearSets[g.key] and S().twGearSets[g.key][id] then return g end end
end
function TW.SetGroup(id, key)
    S().twGearSets = S().twGearSets or {}
    for _, g in ipairs(TW.GROUPS) do if S().twGearSets[g.key] then S().twGearSets[g.key][id] = nil end end
    if key then S().twGearSets[key] = S().twGearSets[key] or {} S().twGearSets[key][id] = true end
    TW.UpdateBags()
end
function TW.GroupMenu(anchor, id)
    local items = {}
    for _, g in ipairs(TW.GROUPS) do
        items[#items + 1] = { text = K.hex(g.color) .. g.text .. "|r", checked = TW.GroupOf(id) == g, fn = function() TW.SetGroup(id, g.key) end }
    end
    items[#items + 1] = { text = L["No group"], fn = function() TW.SetGroup(id, nil) end }
    K.ShowMenu(anchor, items, L["Gear group"])
end
-- equip all items of a group (not in combat)
function TW.EquipGroup(key)
    if combat() then ns.print(L["Not possible in combat - try again shortly."]) return 0 end
    local set = S().twGearSets and S().twGearSets[key]
    local n = 0
    for id in pairs(set or {}) do
        if EquipItemByName and C_Item and C_Item.GetItemCount and (C_Item.GetItemCount(id) or 0) > 0 then
            local equipped = false
            for slot = 1, 19 do if GetInventoryItemID("player", slot) == id then equipped = true end end
            if not equipped then pcall(EquipItemByName, id) n = n + 1 end
        end
    end
    return n
end
local function onBagClick(btn, mouse)
    if mouse ~= "RightButton" or not btn or not btn.GetParent then return end
    local bag = btn.GetBagID and btn:GetBagID() or (btn:GetParent() and btn:GetParent():GetID())
    local slot = btn:GetID()
    local id = bag and itemAt(bag, slot)
    if not id then return end
    if IsAltKeyDown() and on("twJunkMark") then TW.ToggleJunk(id)
    elseif IsControlKeyDown() and on("twGear") then TW.GroupMenu(btn, id) end
end
TW.OnBagClick = onBagClick
-- marks on the bag buttons: grey coin = junk, coloured corner = gear group
local marks = setmetatable({}, { __mode = "k" })
local function markOf(btn)
    local m = marks[btn]
    if m then return m end
    m = {}
    m.junk = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    m.junk:SetTexture("Interface\\MoneyFrame\\UI-CopperIcon")
    m.junk:SetSize(12, 12) m.junk:SetPoint("TOPLEFT", 2, -2)
    m.grp = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    m.grp:SetColorTexture(1, 1, 1, 1)
    m.grp:SetSize(6, 6) m.grp:SetPoint("TOPRIGHT", -2, -2)
    marks[btn] = m
    return m
end
function TW.UpdateBags()
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            local bag = frame:GetID()
            for j = 1, 36 do
                local btn = _G["ContainerFrame" .. i .. "Item" .. j]
                if btn and btn:IsShown() then
                    local id = itemAt(btn.GetBagID and btn:GetBagID() or bag, btn:GetID())
                    local m = markOf(btn)
                    m.junk:SetShown(on("twJunkMark") and TW.IsJunk(id) and true or false)
                    local g = on("twGear") and id and TW.GroupOf(id)
                    if g then m.grp:SetVertexColor(g.color[1], g.color[2], g.color[3]) m.grp:Show() else m.grp:Hide() end
                end
            end
        end
    end
end
local bagHooked
function TW.HookBags()
    if bagHooked then return end
    bagHooked = true
    if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnModifiedClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnModifiedClick", function(self, b) pcall(onBagClick, self, b) end)
    end
    if ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, b) pcall(onBagClick, self, b) end)
    end
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", function() pcall(TW.UpdateBags) end) end
end
pcall(TW.HookBags)
ns.On("BAG_UPDATE_DELAYED", function() pcall(TW.UpdateBags) end)
-- at the vendor: the client lets addons sell only through "sell junk"; marked items are listed for a right-click
ns.On("MERCHANT_SHOW", function()
    if not on("twJunkMark") or not S().twJunk then return end
    local names = {}
    for bag = 0, 4 do
        for slot = 1, (C_Container and C_Container.GetContainerNumSlots(bag) or 0) do
            local id, info = itemAt(bag, slot)
            if id and TW.IsJunk(id) and info.hyperlink then names[#names + 1] = info.hyperlink end
        end
    end
    if #names > 0 then ns.print(L["Marked junk in your bags (right-click to sell):"] .. " " .. table.concat(names, " ")) end
    pcall(TW.UpdateBags)
end)

------------------------------------------------------------------------
-- quest log: levels before the titles
------------------------------------------------------------------------
function TW.QuestTitle(title, level, isHeader)
    if isHeader or not level or level <= 0 then return title end
    return ("[%d] %s"):format(level, title)
end
local function questLog()
    if not on("twQuestLevel") or not GetQuestLogTitle then return end
    local n = QUESTS_DISPLAYED or 6
    local offset = FauxScrollFrame_GetOffset and QuestLogListScrollFrame and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
    for i = 1, n do
        local b = _G["QuestLogTitle" .. i]
        if b and b:IsShown() then
            local idx = i + offset
            local title, level, _, isHeader = GetQuestLogTitle(idx)
            if title and not isHeader then
                b:SetText(TW.QuestTitle(title, level, isHeader))
                if QuestLogTitleButton_Resize then pcall(QuestLogTitleButton_Resize, b) end
            end
        end
    end
end
if QuestLog_Update then hooksecurefunc("QuestLog_Update", function() pcall(questLog) end) end

------------------------------------------------------------------------
-- trainer: "Train all" (everything available you can afford)
------------------------------------------------------------------------
function TW.TrainAll()
    if not (GetNumTrainerServices and BuyTrainerService) or combat() then return 0 end
    local n, money = 0, GetMoney and GetMoney() or 0
    for i = GetNumTrainerServices(), 1, -1 do
        local _, _, category = GetTrainerServiceInfo(i)
        local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
        if category == "available" and cost <= money then
            if pcall(BuyTrainerService, i) then n, money = n + 1, money - cost end
        end
    end
    if n > 0 then ns.print((L["Learned %d skills."]):format(n)) end
    return n
end
local trainBtn
ns.On("TRAINER_SHOW", function()
    if not on("twTrainAll") then if trainBtn then trainBtn:Hide() end return end
    local host = ClassTrainerFrame
    if not host then return end
    if not trainBtn then
        trainBtn = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        trainBtn:SetSize(100, 22)
        trainBtn:SetText(L["Train all"])
        trainBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -44)
        trainBtn:SetScript("OnClick", function() TW.TrainAll() end)
    end
    trainBtn:Show()
end)

------------------------------------------------------------------------
-- fishing: double right-click in the world casts (only with a fishing pole, not in combat)
------------------------------------------------------------------------
local fishBtn, lastRight, owner
local function poleEquipped()
    local id = GetInventoryItemID("player", 16)
    if not id or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID == 2 and subID == 20
end
TW.PoleEquipped = poleEquipped
local function clearFish() if owner and not combat() then ClearOverrideBindings(owner) end end
function TW.FishSetup()
    if fishBtn or not (CreateFrame and WorldFrame) then return end
    owner = CreateFrame("Frame")
    fishBtn = CreateFrame("Button", "OasisFishButton", UIParent, "SecureActionButtonTemplate")
    fishBtn:SetAttribute("type", "spell")
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)) or (GetSpellInfo and GetSpellInfo(7620)) or "Fishing"
    fishBtn:SetAttribute("spell", name)
    fishBtn:RegisterForClicks("AnyUp", "AnyDown")
    fishBtn:HookScript("PostClick", clearFish)
    WorldFrame:HookScript("OnMouseDown", function(_, b)
        if b ~= "RightButton" or not on("twFishing") or combat() or not poleEquipped() then return end
        local now = GetTime()
        if lastRight and now - lastRight < 0.4 then
            -- the next right-click goes to the fishing button
            SetOverrideBindingClick(owner, true, "BUTTON2", "OasisFishButton")
            if C_Timer then C_Timer.After(0.5, clearFish) end
            lastRight = nil
        else
            lastRight = now
        end
    end)
end
pcall(TW.FishSetup)

------------------------------------------------------------------------
-- auction house: item level in the browse list
------------------------------------------------------------------------
local function ahLevels()
    if not on("twAhIlvl") or not GetAuctionItemLink then return end
    local offset = FauxScrollFrame_GetOffset and BrowseScrollFrame and FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    for i = 1, (NUM_BROWSE_TO_DISPLAY or 8) do
        local b = _G["BrowseButton" .. i]
        if b then
            if not b.oaIlvl then
                b.oaIlvl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                b.oaIlvl:SetPoint("LEFT", b, "LEFT", 2, 0)
            end
            local link = GetAuctionItemLink("list", offset + i)
            local lvl = link and C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
            b.oaIlvl:SetText(lvl and lvl > 1 and tostring(lvl) or "")
        end
    end
end
TW.AhLevels = ahLevels
ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_AuctionUI" and AuctionFrameBrowse_Update then hooksecurefunc("AuctionFrameBrowse_Update", function() pcall(ahLevels) end) end
end)
if AuctionFrameBrowse_Update then hooksecurefunc("AuctionFrameBrowse_Update", function() pcall(ahLevels) end) end

------------------------------------------------------------------------
-- camera further out, no screen glow (the game's own settings, old value comes back when switched off)
------------------------------------------------------------------------
local CV = { twCamera = { "cameraDistanceMaxZoomFactor", "2.6" }, twNoGlow = { "ffxGlow", "0" } }
local function getCV(n) return (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(n)) or (GetCVar and GetCVar(n)) end
local function setCV(n, v) if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, n, v) elseif SetCVar then pcall(SetCVar, n, v) end end
function TW.ApplyCVars()
    if combat() then return end
    S().twSaved = S().twSaved or {}
    for key, cv in pairs(CV) do
        local saved = S().twSaved[key]
        if on(key) and saved == nil then
            S().twSaved[key] = getCV(cv[1]) or false
            setCV(cv[1], cv[2])
        elseif not on(key) and saved ~= nil then
            if saved and tostring(getCV(cv[1])) == cv[2] then setCV(cv[1], saved) end
            S().twSaved[key] = nil
        end
    end
end
ns.On("PLAYER_LOGIN", function() pcall(TW.ApplyCVars) end)
if ns.db then pcall(TW.ApplyCVars) end

------------------------------------------------------------------------
-- tooltips: class-coloured player names, health bar inside the tooltip
------------------------------------------------------------------------
local function unitTip(tt)
    if tt ~= GameTooltip then return end
    local _, unit = tt:GetUnit()
    unit = ns.safe(unit)
    if not unit then return end
    if on("twTipClass") and UnitIsPlayer(unit) then
        local _, cls = UnitClass(unit)
        local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if c and GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(c.r, c.g, c.b) end
    end
    if on("twTipBar") and GameTooltipStatusBar then
        tt:AddLine(" ")
        GameTooltipStatusBar:ClearAllPoints()
        GameTooltipStatusBar:SetPoint("BOTTOMLEFT", tt, "BOTTOMLEFT", 10, 8)
        GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", tt, "BOTTOMRIGHT", -10, 8)
        GameTooltipStatusBar:SetHeight(5)
        tt:Show()
    end
end
TW.UnitTip = unitTip
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(unitTip, tt) end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(unitTip, tt) end)
end

------------------------------------------------------------------------
-- /rl
------------------------------------------------------------------------
if not (SlashCmdList and SlashCmdList.RELOAD) and SlashCmdList then
    SLASH_OASISRL1 = "/rl"
    SlashCmdList.OASISRL = function() if ReloadUI then ReloadUI() end end
end

-- gear groups by slash: /oa gear dps
ns.slash.gear = function(rest)
    local key = tostring(rest or ""):lower():match("%a+")
    for _, g in ipairs(TW.GROUPS) do
        if g.key == key then ns.print((L["Equipped %d items of %s."]):format(TW.EquipGroup(g.key), g.text)) return end
    end
    ns.print(L["Gear groups: /oa gear dps | tank | heal | pvp | farm"])
end
ns.slash.ausruestung = ns.slash.gear

function TW.Apply()
    pcall(TW.ApplyCVars)
    pcall(TW.UpdateBags)
end
end)

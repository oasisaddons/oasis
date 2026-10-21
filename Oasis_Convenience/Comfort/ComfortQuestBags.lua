-- Oasis - Comfort: quest helpers on nameplates, quest target key, bag helpers (0.6.621), each off until switched on.
--   * quest progress on enemy nameplates ("3/8") - from the game's own quest lines of that unit
--   * key / button "next quest enemy": targets the enemies your quests still need (kill objectives)
--   * bags full: offer to destroy the cheapest item (never quest, restock or gear-group items)
--   * open button for clams, sacks and boxes (one click each - the game lets addons open nothing by themselves)
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()
local L = ns.L
local K, C = ns.K, ns.K.C

local QB = {}
ns.ComfortQuestBags = QB
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function combat() return InCombatLockdown and InCombatLockdown() end

------------------------------------------------------------------------
-- quest objectives of the quest log
------------------------------------------------------------------------
-- { kind = "monster" | "item", name, have, need, quest }
function QB.Objectives()
    local out = {}
    if not (GetNumQuestLogEntries and GetQuestLogTitle and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return out end
    local n = GetNumQuestLogEntries()
    for i = 1, n or 0 do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if title and not isHeader then
            for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
                local text, kind, done = GetQuestLogLeaderBoard(j, i)
                text = ns.safe(text)
                if type(text) == "string" and not done then
                    local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
                    if name then
                        -- "Defias Thug slain" -> "Defias Thug" (the kill word differs per language)
                        if kind == "monster" then name = name:gsub("%s+%S+$", "") end
                        out[#out + 1] = { kind = kind, name = name, have = tonumber(have), need = tonumber(need), quest = title }
                    end
                end
            end
        end
    end
    return out
end
local objCache, objAt
function QB.Cached()
    local now = GetTime and GetTime() or 0
    if not objCache or now - (objAt or 0) > 2 then objCache, objAt = QB.Objectives(), now end
    return objCache
end
ns.On("QUEST_LOG_UPDATE", function() objCache = nil end)

------------------------------------------------------------------------
-- nameplates: "!" and progress for enemies your quests need
------------------------------------------------------------------------
local marks = setmetatable({}, { __mode = "k" })
-- progress line of a unit: the game's quest lines in the unit tooltip, else kill objectives by name
function QB.UnitProgress(unit)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        local lines = ok and ns.safe(data) and ns.safe(data.lines)
        if type(lines) == "table" then
            local qType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
            for _, l in ipairs(lines) do
                local t = ns.safe(l.leftText)
                if (qType and l.type == qType) and type(t) == "string" and not ns.safe(l.completed) then
                    local have, need = t:match("(%d+)%s*/%s*(%d+)")
                    if have then return have .. "/" .. need end
                end
            end
        end
    end
    local name = ns.safe(UnitName(unit))
    if type(name) ~= "string" then return nil end
    for _, o in ipairs(QB.Cached()) do
        if o.kind == "monster" and o.name == name and o.have < o.need then return o.have .. "/" .. o.need end
    end
end
local function plateFor(unit) return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit) end
function QB.UpdatePlate(unit)
    local plate = plateFor(unit)
    if not plate then return end
    local m = marks[plate]
    local prog = on("cfQuestPlates") and UnitCanAttack("player", unit) and QB.UnitProgress(unit)
    if not prog then if m then m.f:Hide() end return end
    if not m then
        m = {}
        m.f = CreateFrame("Frame", nil, plate)
        m.f:SetSize(40, 16)
        m.f:SetPoint("LEFT", plate, "RIGHT", -6, 0)
        m.icon = m.f:CreateTexture(nil, "OVERLAY")
        m.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        m.icon:SetSize(14, 14) m.icon:SetPoint("LEFT")
        m.t = m.f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        m.t:SetPoint("LEFT", m.icon, "RIGHT", 1, 0)
        marks[plate] = m
    end
    m.t:SetText(prog)
    m.f:Show()
end
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) pcall(QB.UpdatePlate, unit) end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(unit) local p = plateFor(unit) if p and marks[p] then marks[p].f:Hide() end end)
function QB.RefreshPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
        if u then pcall(QB.UpdatePlate, u) end
    end
end
ns.On("QUEST_LOG_UPDATE", function() if on("cfQuestPlates") then pcall(QB.RefreshPlates) end end)

------------------------------------------------------------------------
-- key "next quest enemy": a secure macro button, rewritten out of combat
------------------------------------------------------------------------
local qbtn
function QB.TargetMacro()
    local lines, seen = {}, {}
    for _, o in ipairs(QB.Cached()) do
        if o.kind == "monster" and o.have < o.need and not seen[o.name] and #lines < 8 then
            seen[o.name] = true
            lines[#lines + 1] = "/targetexact " .. o.name
        end
    end
    return table.concat(lines, "\n")
end
function QB.UpdateTargetButton()
    if combat() or not CreateFrame then return end
    if not qbtn then
        qbtn = CreateFrame("Button", "OasisQuestTargetButton", UIParent, "SecureActionButtonTemplate")
        qbtn:SetAttribute("type", "macro")
        qbtn:RegisterForClicks("AnyUp", "AnyDown")
    end
    qbtn:SetAttribute("macrotext", on("cfQuestTarget") and QB.TargetMacro() or "")
end
ns.On("QUEST_LOG_UPDATE", function() objCache = nil pcall(QB.UpdateTargetButton) end)
ns.On("PLAYER_REGEN_ENABLED", function() pcall(QB.UpdateTargetButton) end)
_G["BINDING_NAME_CLICK OasisQuestTargetButton:LeftButton"] = L["Target the next quest enemy"]

------------------------------------------------------------------------
-- bags full: destroy the cheapest item (asked, one click)
------------------------------------------------------------------------
local function protectedItem(id)
    if S().cfRestock and S().cfRestock[id] then return true end
    if ns.ComfortTweaks and ns.ComfortTweaks.GroupOf and ns.ComfortTweaks.GroupOf(id) then return true end
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    for _, o in ipairs(QB.Cached()) do if o.kind == "item" and o.name == name then return true end end
    return false
end
function QB.Cheapest()
    local best
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.hyperlink and not info.isLocked then
                local _, _, quality, _, _, _, _, _, _, _, price, classID = C_Item.GetItemInfo(info.hyperlink)
                -- only things with a vendor price (no quest items, no keys), never protected ones, epic and up never
                if price and price > 0 and classID ~= 12 and (quality or 0) <= 2 and not protectedItem(info.itemID) then
                    local value = price * (info.stackCount or 1)
                    if not best or value < best.value then best = { bag = bag, slot = slot, value = value, link = info.hyperlink, id = info.itemID } end
                end
            end
        end
    end
    return best
end
StaticPopupDialogs["OASIS_DESTROY_CHEAP"] = {
    text = "%s", button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    OnAccept = function(_, d)
        if not d or combat() then return end
        local info = C_Container.GetContainerItemInfo(d.bag, d.slot)
        if not (info and info.itemID == d.id) then return end   -- something moved meanwhile
        C_Container.PickupContainerItem(d.bag, d.slot)
        if DeleteCursorItem then DeleteCursorItem() end
    end,
    timeout = 0, whileDead = false, hideOnEscape = true,
}
local function money(c) return (GetCoinTextureString and GetCoinTextureString(math.floor(c or 0))) or tostring(c) end
function QB.OfferDestroy()
    local b = QB.Cheapest()
    if not b then ns.print(L["Nothing in your bags that may go."]) return end
    StaticPopup_Show("OASIS_DESTROY_CHEAP", (L["Bags full - destroy the cheapest item %s (worth %s)?"]):format(b.link, money(b.value)), nil, b)
end
local fullAt
ns.On("BAG_UPDATE_DELAYED", function()
    if not on("cfDestroyCheap") or combat() then return end
    local free = 0
    for bag = 0, 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then free = free + (n or 0) end
    end
    local now = GetTime and GetTime() or 0
    if free == 0 and (not fullAt or now - fullAt > 120) then fullAt = now QB.OfferDestroy() end
end)
ns.slash.destroycheap = QB.OfferDestroy
ns.slash.billigstes = QB.OfferDestroy

------------------------------------------------------------------------
-- open button for clams, sacks, boxes
------------------------------------------------------------------------
local obtn
function QB.Openables()
    local out = {}
    for bag = 0, 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hasLoot and not info.isLocked then out[#out + 1] = { bag = bag, slot = slot, icon = info.iconFileID } end
        end
    end
    return out
end
function QB.UpdateOpenButton()
    if combat() or not CreateFrame then return end
    local list = on("cfOpenButton") and QB.Openables() or {}
    if not obtn then
        obtn = CreateFrame("Button", "OasisOpenButton", UIParent, "SecureActionButtonTemplate")
        obtn:SetSize(36, 36)
        local p = S().cfOpenPos
        if p then obtn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2]) else obtn:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 160) end
        obtn:SetAttribute("type", "macro")
        obtn:RegisterForClicks("LeftButtonUp")
        obtn:SetMovable(true) obtn:RegisterForDrag("RightButton")
        obtn:SetScript("OnDragStart", function(self) if not combat() then self:StartMoving() end end)
        obtn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() local x, y = self:GetCenter() S().cfOpenPos = { math.floor(x), math.floor(y) } end)
        obtn.icon = obtn:CreateTexture(nil, "ARTWORK") obtn.icon:SetAllPoints()
        obtn.count = obtn:CreateFontString(nil, "OVERLAY", "NumberFontNormal") obtn.count:SetPoint("BOTTOMRIGHT", -2, 2)
        obtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText(L["Click: open"]) GameTooltip:AddLine(L["Right-drag: move"], 0.7, 0.7, 0.7) GameTooltip:Show() end)
        obtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if #list == 0 then obtn:Hide() return end
    local first = list[1]
    obtn:SetAttribute("macrotext", ("/use %d %d"):format(first.bag, first.slot))
    obtn.icon:SetTexture(first.icon)
    obtn.count:SetText(#list > 1 and tostring(#list) or "")
    obtn:Show()
end
ns.On("BAG_UPDATE_DELAYED", function() pcall(QB.UpdateOpenButton) end)
ns.On("PLAYER_REGEN_ENABLED", function() pcall(QB.UpdateOpenButton) end)

function QB.Apply()
    pcall(QB.RefreshPlates)
    pcall(QB.UpdateTargetButton)
    pcall(QB.UpdateOpenButton)
end
ns.On("PLAYER_LOGIN", function() if ns.After then ns.After(3, QB.Apply) end end)
end)

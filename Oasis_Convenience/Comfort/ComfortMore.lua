-- Oasis - Comfort: quests, vendor, tooltip, minimap, chat and sound helpers (0.6.609), each off until switched on
-- (Everyday helpers > "Quests & vendor" and "Tooltip, minimap & chat"). Own implementation, no code taken over.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()
local L = ns.L
local K, C = ns.K, ns.K.C

local MO = {}
ns.ComfortMore = MO
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function combat() return InCombatLockdown and InCombatLockdown() end

------------------------------------------------------------------------
-- quests: Forever's own quests (1 leave to me, 2 turn in only, 3 accept and turn in) and the reward choice
-- (1 let me pick, 2 best upgrade - else highest price, 3 highest price). Used by Comfort.lua's quest automation.
------------------------------------------------------------------------
local function questID() return (GetQuestID and ns.safe(GetQuestID())) or nil end
function MO.IsForever(id)
    id = id or questID()
    if ns.IsForeverQuest then local ok, r = pcall(ns.IsForeverQuest, id) if ok then return r and true or false end end
    return id ~= nil and id >= 20000
end
-- may the automation accept / turn in this quest?
function MO.MayAccept(id) if not MO.IsForever(id) then return true end return (S().cfForeverQuests or 3) >= 3 end
function MO.MayTurnIn(id) if not MO.IsForever(id) then return true end return (S().cfForeverQuests or 3) >= 2 end
-- reward index to take, or nil = the player picks
function MO.RewardChoice()
    local mode = S().cfRewardPick or 1
    local n = GetNumQuestChoices and ns.safe(GetNumQuestChoices()) or 0
    if mode == 1 or type(n) ~= "number" or n <= 1 then return nil end
    local best, bestPct, rich, richPrice, missing = nil, 0, nil, -1, false
    for i = 1, n do
        local link = GetQuestItemLink and ns.safe(GetQuestItemLink("choice", i))
        if not link then missing = true else
            local _, _, cnt, _, usable = GetQuestItemInfo("choice", i)
            if mode == 2 and ns.safe(usable) ~= false and ns.Upgrade and ns.Upgrade.Compare then
                local ok, pct = pcall(ns.Upgrade.Compare, link)
                if ok and pct and pct > bestPct then best, bestPct = i, pct end
            end
            local price = select(11, C_Item.GetItemInfo(link))
            if price == nil then missing = true end
            price = (tonumber(price) or 0) * (tonumber(ns.safe(cnt)) or 1)
            if price > richPrice then rich, richPrice = i, price end
        end
    end
    if missing then return nil end   -- item data not there yet: the player picks rather than a wrong guess
    return best or rich
end
-- quest log full (20 quests)
function MO.LogFull()
    local n = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local _, q = C_QuestLog.GetNumQuestLogEntries() n = q or 0
    elseif GetNumQuestLogEntries then
        local _, q = GetNumQuestLogEntries() n = q or 0
    end
    return n >= (MAX_QUESTS or 20)
end

------------------------------------------------------------------------
-- vendor: restock list and ammo
------------------------------------------------------------------------
-- S().cfRestock = { [itemID] = count }
function MO.RestockNeeds()
    local out, total = {}, 0
    local list = S().cfRestock
    if not (list and GetMerchantNumItems) then return out, 0 end
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local want = id and list[id]
        if want then
            local have = C_Item.GetItemCount(id) or 0
            local _, _, price, qty = GetMerchantItemInfo(i)
            local need = want - have
            if need > 0 and price then
                qty = qty or 1
                out[#out + 1] = { index = i, id = id, need = need, cost = math.ceil(need / qty) * price, qty = qty }
                total = total + math.ceil(need / qty) * price
            end
        end
    end
    return out, total
end
function MO.Restock()
    local list = MO.RestockNeeds()
    for _, e in ipairs(list) do
        local left = e.need
        local stack = select(8, C_Item.GetItemInfo(e.id)) or 20
        while left > 0 do
            local n = math.min(left, stack)
            pcall(BuyMerchantItem, e.index, n)
            left = left - n
        end
    end
end
-- hunters: best usable ammo for the ranged weapon this vendor sells, a stack for each free quiver slot
local AMMO_FOR = { [2] = 2, [18] = 2, [3] = 3 }   -- bow / crossbow -> arrows (2), gun -> bullets (3)
function MO.AmmoOffer()
    local rid = GetInventoryItemID("player", 18)
    if not rid or not GetMerchantNumItems then return nil end
    local _, _, _, _, _, cls, sub = C_Item.GetItemInfoInstant(rid)
    local want = cls == 2 and AMMO_FOR[sub]
    if not want then return nil end
    local best, bestLvl
    local lvl = UnitLevel("player")
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id then
            local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(id)
            local _, _, _, ilvl, minLvl = C_Item.GetItemInfo(id)
            if c == 6 and s == want and (minLvl or 0) <= lvl and (ilvl or 0) > (bestLvl or -1) then best, bestLvl = i, ilvl or 0 end
        end
    end
    if not best then return nil end
    local free = 0
    for bag = 1, 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if family and family > 0 and n then free = free + n end   -- quiver / ammo pouch
    end
    if free == 0 then return nil end
    local id = GetMerchantItemID(best)
    local stack = select(8, C_Item.GetItemInfo(id)) or 200
    local _, _, price, qty = GetMerchantItemInfo(best)
    return { index = best, id = id, stacks = free, amount = free * stack, cost = math.ceil(free * stack / (qty or 1)) * (price or 0) }
end
StaticPopupDialogs["OASIS_RESTOCK"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fn then data.fn() end end,
    timeout = 0, whileDead = false, hideOnEscape = true,
}
local function money(c) return (GetCoinTextureString and GetCoinTextureString(math.floor(c or 0))) or tostring(c) end
ns.On("MERCHANT_SHOW", function()
    if IsShiftKeyDown() then return end
    if on("cfRestockOn") then
        local list, total = MO.RestockNeeds()
        if #list > 0 and total <= (GetMoney() or 0) then
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = e.need .. "x " .. (C_Item.GetItemNameByID(e.id) or "?") end
            StaticPopup_Show("OASIS_RESTOCK", (L["Restock %s for %s?"]):format(table.concat(names, ", "), money(total)), nil, { fn = MO.Restock })
        end
    end
    if on("cfAmmo") then
        local a = MO.AmmoOffer()
        if a and a.cost <= (GetMoney() or 0) then
            StaticPopup_Show("OASIS_RESTOCK", (L["Fill your quiver: %d x %s for %s?"]):format(a.amount, C_Item.GetItemNameByID(a.id) or "?", money(a.cost)), nil,
                { fn = function()
                    local stack = select(8, C_Item.GetItemInfo(a.id)) or 200
                    for _ = 1, a.stacks do pcall(BuyMerchantItem, a.index, stack) end
                end })
        end
    end
end)
-- /oa restock [item link] [count] - add, change (0 removes) or list
ns.slash.restock = function(rest)
    rest = tostring(rest or "")
    local id = tonumber(rest:match("item:(%d+)")) or tonumber(rest:match("^%s*(%d+)%s+%d+"))
    local count = tonumber(rest:match("(%d+)%s*$"))
    S().cfRestock = S().cfRestock or {}
    if id and count and rest:match("item:") or (id and count and id ~= count) then
        S().cfRestock[id] = count > 0 and count or nil
    end
    local any = false
    for i, c in pairs(S().cfRestock) do any = true ns.print(("  %s: %d"):format(C_Item.GetItemNameByID(i) or tostring(i), c)) end
    if not any then ns.print(L["Restock list empty - /oa restock [item link] [count]"]) end
end
ns.slash.nachkaufen = ns.slash.restock
function MO.RestockMenu(anchor)
    local items = {}
    for id, c in pairs(S().cfRestock or {}) do
        items[#items + 1] = { text = (C_Item.GetItemNameByID(id) or tostring(id)) .. "  |cff888888" .. c .. "|r  " .. L["(click removes)"], fn = function() S().cfRestock[id] = nil end }
    end
    if #items == 0 then items[1] = { text = L["Restock list empty - /oa restock [item link] [count]"], disabled = true } end
    K.ShowMenu(anchor, items, L["Restock list"])
end

------------------------------------------------------------------------
-- loot: bind-on-pickup confirmation, delete without typing
------------------------------------------------------------------------
ns.On("LOOT_BIND_CONFIRM", function(slot)
    if not on("cfLootConfirm") then return end
    slot = ns.safe(slot)
    if slot and ConfirmLootSlot then pcall(ConfirmLootSlot, slot) if StaticPopup_Hide then StaticPopup_Hide("LOOT_BIND") end end
end)
local destroyHooked
function MO.HookDestroy()
    if destroyHooked or not StaticPopupDialogs then return end
    local d = StaticPopupDialogs.DELETE_GOOD_ITEM
    if not d then return end
    destroyHooked = true
    hooksecurefunc(d, "OnShow", function(self)
        if not on("cfEasyDestroy") then return end
        local eb = self.editBox or self.EditBox
        if eb and DELETE_ITEM_CONFIRM_STRING then eb:SetText(DELETE_ITEM_CONFIRM_STRING) end
    end)
end
pcall(MO.HookDestroy)

------------------------------------------------------------------------
-- tooltips: guild rank, target of the unit, hidden in combat (Shift shows), faction backdrop
------------------------------------------------------------------------
local function unitTip(tt)
    if tt ~= GameTooltip then return end
    local _, unit = tt:GetUnit()
    unit = ns.safe(unit)
    if not unit then return end
    if on("cfTipRank") and UnitIsPlayer(unit) and GetGuildInfo then
        local g, rank = GetGuildInfo(unit)
        if g and rank then tt:AddLine(("<%s>  %s"):format(g, rank), 0.6, 0.85, 1) end
    end
    if on("cfTipTarget") then
        local tu = unit .. "target"
        if UnitExists(tu) then
            local name = UnitName(tu)
            local _, cls = UnitClass(tu)
            local c = UnitIsPlayer(tu) and cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            tt:AddLine(L["Target:"] .. " " .. (c and ("|c" .. (c.colorStr or "ffffffff")) or "|cffffffff") .. (UnitIsUnit(tu, "player") and ("> " .. L["you"] .. " <") or (name or "?")) .. "|r")
        end
    end
    if on("cfTipFaction") and tt.NineSlice and tt.NineSlice.SetCenterColor then
        local f = UnitFactionGroup(unit)
        if f == "Alliance" then tt.NineSlice:SetCenterColor(0.05, 0.08, 0.2, 0.9)
        elseif f == "Horde" then tt.NineSlice:SetCenterColor(0.2, 0.04, 0.04, 0.9) end
    end
    tt:Show()
end
MO.UnitTip = unitTip
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(unitTip, tt) end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(unitTip, tt) end)
end
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", function(tt)
        if on("cfTipCombat") and combat() and not IsShiftKeyDown() then
            local owner = tt:GetOwner()
            if owner == UIParent or owner == WorldFrame then tt:Hide() end
        end
    end)
    GameTooltip:HookScript("OnHide", function(tt)
        if tt.NineSlice and tt.NineSlice.SetCenterColor and on("cfTipFaction") then tt.NineSlice:SetCenterColor(0, 0, 0, 0.9) end
    end)
end

------------------------------------------------------------------------
-- minimap: square, addon buttons only on mouse-over
------------------------------------------------------------------------
local squareOn
function MO.ApplyMinimap()
    if not Minimap then return end
    local want = on("cfSquareMap")
    if want ~= squareOn then
        squareOn = want
        pcall(Minimap.SetMaskTexture, Minimap, want and "Interface\\ChatFrame\\ChatFrameBackground" or "Textures\\MinimapMask")
        for _, b in ipairs({ _G.MinimapBorder, _G.MinimapBorderTop, _G.MinimapCompassTexture }) do if b then b:SetShown(not want) end end
        GetMinimapShape = want and function() return "SQUARE" end or nil
    end
    MO.ApplyMinimapButtons()
end
local function addonButtons()
    local out = {}
    for _, c in ipairs({ Minimap:GetChildren() }) do
        local n = c.GetName and c:GetName()
        if n and (n:find("^LibDBIcon10_") or n:find("MinimapButton")) and not n:find("^Oasis") then out[#out + 1] = c end
    end
    return out
end
function MO.ApplyMinimapButtons(hover)
    if not Minimap then return end
    local hide = on("cfMapButtons")
    for _, b in ipairs(addonButtons()) do
        if hide then b:SetAlpha(hover and 1 or 0) else b:SetAlpha(1) end
    end
end
if Minimap and Minimap.HookScript then
    Minimap:HookScript("OnEnter", function() if on("cfMapButtons") then MO.ApplyMinimapButtons(true) end end)
    Minimap:HookScript("OnLeave", function()
        if on("cfMapButtons") and C_Timer then C_Timer.After(1, function() if not Minimap:IsMouseOver() then MO.ApplyMinimapButtons(false) end end) end
    end)
end

------------------------------------------------------------------------
-- chat: combat log tab, chat buttons, font size; spam filter
------------------------------------------------------------------------
function MO.ApplyChat()
    if _G.ChatFrame2Tab then
        if on("cfNoCombatTab") then ChatFrame2Tab:SetAlpha(0) ChatFrame2Tab:EnableMouse(false)
        else ChatFrame2Tab:SetAlpha(1) ChatFrame2Tab:EnableMouse(true) end
    end
    for _, n in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
        local b = _G[n]
        if b then b:SetAlpha(on("cfNoChatButtons") and 0 or 1) end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
        if bf then bf:SetAlpha(on("cfNoChatButtons") and 0 or 1) end
        local size = S().cfChatFont
        local cf = _G["ChatFrame" .. i]
        if size and cf and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, cf, size) end
    end
end
-- duel results and drunk messages of other players
local spam
local function spamPatterns()
    if spam then return spam end
    spam = {}
    for _, g in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT", "DRUNK_MESSAGE_OTHER1", "DRUNK_MESSAGE_OTHER2", "DRUNK_MESSAGE_OTHER3", "DRUNK_MESSAGE_OTHER4",
        "DRUNK_MESSAGE_ITEM_OTHER1", "DRUNK_MESSAGE_ITEM_OTHER2", "DRUNK_MESSAGE_ITEM_OTHER3", "DRUNK_MESSAGE_ITEM_OTHER4" }) do
        local s = _G[g]
        if type(s) == "string" then
            -- format tokens (%s, %d, %1$s) -> placeholder, escape the rest, placeholder -> ".+"
            local t = s:gsub("%%%d*%$?[sd]", "")
            t = t:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local p = "^" .. t:gsub("", ".+") .. "$"
            spam[#spam + 1] = p
        end
    end
    return spam
end
function MO.IsSpam(msg)
    if not on("cfSpamFilter") or type(msg) ~= "string" then return false end
    for _, p in ipairs(spamPatterns()) do if msg:find(p) then return true end end
    return false
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg) return MO.IsSpam(ns.safe(msg)) end)
end

------------------------------------------------------------------------
-- mute single game sounds (sound file IDs of the game)
------------------------------------------------------------------------
MO.MUTE = {
    cfMuteChimes = { 566564, 565853, 566558, 566027, 566254, 566064 },
    cfMuteFizzle = { 569773, 569775, 569772, 569774, 569776 },
    cfMuteTrains = { 539802, 539881, 540271, 540275, 540535, 540734, 540870, 540947, 1316209, 1304872, 541157, 541239, 542818, 542896, 543085, 543093, 542526, 542600, 1951457, 1951458 },
    cfMuteYawns = { 562388 },
}
local muted = {}
function MO.ApplyMutes()
    if not (MuteSoundFile and UnmuteSoundFile) then return end
    for key, ids in pairs(MO.MUTE) do
        local want = on(key)
        if want ~= (muted[key] or false) then
            for _, id in ipairs(ids) do pcall(want and MuteSoundFile or UnmuteSoundFile, id) end
            muted[key] = want
        end
    end
end

function MO.Apply()
    pcall(MO.ApplyMinimap)
    pcall(MO.ApplyChat)
    pcall(MO.ApplyMutes)
    pcall(MO.HookDestroy)
end
ns.On("PLAYER_LOGIN", function() if ns.After then ns.After(2, MO.Apply) else MO.Apply() end end)
if ns.db then MO.Apply() end
end)

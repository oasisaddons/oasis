-- Oasis - Comfort: small everyday helpers (each toggleable, off by default).
-- Own implementation in Oasis (ideas as common in comfort addons).
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()   -- module Comfort (can be disabled, see ModuleLoader.lua)
local EBM = setmetatable({}, { __mode = "k" })    -- Marker per chat input/bar (never write fields onto Blizzard frames)
local L = ns.L
local K, C = ns.K, ns.K.C

local CF = {}
ns.Comfort = CF
local function S() return ns.db and ns.db.settings or {} end
local function on(k) return S()[k] and true or false end
local function money(c)
    c = math.floor(c or 0)
    return (GetCoinTextureString and GetCoinTextureString(c)) or (math.floor(c / 10000) .. "g")
end
local function isFriendOrGuild(name, guid)
    if not name then return false end
    local full = ns.fullName(name)
    if ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, full) then return true end
    if guid and C_FriendList and C_FriendList.IsFriend then
        local ok, f = pcall(C_FriendList.IsFriend, guid)
        if ok and f then return true end
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, ns.short(name))
        if ok and info then return true end
    end
    return false
end

------------------------------------------------------------------------
-- vendor: sell junk, repair (hold Shift = skip)
------------------------------------------------------------------------
ns.On("MERCHANT_SHOW", function()
    if IsShiftKeyDown() then return end
    if on("cfRepair") and CanMerchantRepair and CanMerchantRepair() then
        local cost, can = GetRepairAllCost()
        if can and cost and cost > 0 then
            local guild = on("cfRepairGuild") and CanGuildBankRepair and CanGuildBankRepair()
            if guild then RepairAllItems(true) else RepairAllItems() end
            ns.print((L["Repaired for %s%s"]):format(money(cost), guild and (" (" .. L["Guild bank"] .. ")") or ""))
        end
    end
    -- Junk: only via Blizzard's own "Sell junk" (C_MerchantFrame.SellAllJunkItems).
    -- The client blocks UseContainerItem from addon code ("Blocked: UseContainerItem()", 0.5.478).
    if on("cfSellJunk") and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        local total, n = 0, 0
        if C_Container then
            for bag = 0, 4 do
                for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.quality == 0 and not info.hasNoValue and info.hyperlink then
                        local price = select(11, C_Item.GetItemInfo(info.hyperlink)) or 0
                        if price > 0 then total, n = total + price * (info.stackCount or 1), n + 1 end
                    end
                end
            end
        end
        if n > 0 and pcall(C_MerchantFrame.SellAllJunkItems) then
            ns.print((L["Sold %d grey items for %s"]):format(n, money(total)))
        end
    end
end)

------------------------------------------------------------------------
-- quests automatically (hold Shift = skip); decline shared quests
------------------------------------------------------------------------
ns.On("QUEST_DETAIL", function()
    -- shared by a player?
    -- 0.5.739: quests from your own party/raid or guild are never declined, only those from strangers
    local friendly = UnitInParty("npc") or UnitInRaid("npc") or (UnitIsInMyGuild and UnitIsInMyGuild("npc"))
    if on("cfBlockShared") and UnitIsPlayer("npc") and not friendly then
        if DeclineQuest then DeclineQuest() end
        ns.print(L["Shared quest declined."])
        return
    end
    if on("cfQuests") and not IsShiftKeyDown() then
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if CloseQuest then CloseQuest() end
        else
            AcceptQuest()
        end
    end
end)
ns.On("QUEST_PROGRESS", function()
    if on("cfQuests") and not IsShiftKeyDown() and IsQuestCompletable() then CompleteQuest() end
end)
ns.On("QUEST_COMPLETE", function()
    if not on("cfQuests") or IsShiftKeyDown() then return end
    if (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) > 0 then return end
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices <= 1 then GetQuestReward(choices == 1 and 1 or nil) end
end)
local function gossipQuests()
    if not on("cfQuests") or IsShiftKeyDown() or not C_GossipInfo then return end
    local ok, active = pcall(C_GossipInfo.GetActiveQuests)
    if ok and active then
        for _, q in ipairs(active) do
            if q.isComplete and q.questID then pcall(C_GossipInfo.SelectActiveQuest, q.questID) return end
        end
    end
    local ok2, avail = pcall(C_GossipInfo.GetAvailableQuests)
    if ok2 and avail then
        for _, q in ipairs(avail) do
            if q.questID then pcall(C_GossipInfo.SelectAvailableQuest, q.questID) return end
        end
    end
end
ns.On("GOSSIP_SHOW", function() pcall(gossipQuests) end)
ns.On("QUEST_GREETING", function()
    if not on("cfQuests") or IsShiftKeyDown() then return end
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
        local _, done = GetActiveTitle(i)
        if done then SelectActiveQuest(i) return end
    end
    if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end
end)

------------------------------------------------------------------------
-- accept summon / resurrection
------------------------------------------------------------------------
ns.On("CONFIRM_SUMMON", function()
    if not on("cfSummon") or ns.inCombat() then return end
    C_Timer.After(1, function()
        if C_SummonInfo and C_SummonInfo.ConfirmSummon and not ns.inCombat() then
            pcall(C_SummonInfo.ConfirmSummon)
            if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_SUMMON") end
        end
    end)
end)
ns.On("RESURRECT_REQUEST", function()
    if not on("cfSummon") then return end
    if AcceptResurrect then AcceptResurrect() end
    if StaticPopup_Hide then StaticPopup_Hide("RESURRECT") StaticPopup_Hide("RESURRECT_NO_SICKNESS") StaticPopup_Hide("RESURRECT_NO_TIMER") end
end)

------------------------------------------------------------------------
-- Duelle, Einladungen, Einladen per Fluestern
------------------------------------------------------------------------
ns.On("DUEL_REQUESTED", function()
    if not on("cfBlockDuels") then return end
    if CancelDuel then CancelDuel() end
    if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
end)
ns.On("PARTY_INVITE_REQUEST", function(name, ...)
    if not on("cfInvites") then return end
    name = ns.safe(name)
    local guid = select(6, ...)
    if isFriendOrGuild(name, ns.safe(guid)) then
        AcceptGroup()
    else
        DeclineGroup()
        ns.print((L["Invite from %s declined (not guild/friend)."]):format(ns.displayName(name or "?")))
    end
    if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
end)
ns.On("CHAT_MSG_WHISPER", function(msg, sender)
    if not on("cfWhisperInv") then return end
    msg, sender = ns.safe(msg), ns.safe(sender)
    local kw = (S().cfInvKeyword ~= nil and S().cfInvKeyword ~= "") and S().cfInvKeyword or "inv"
    if not msg or not sender or msg:lower():gsub("%s+", "") ~= kw:lower():gsub("%s+", "") then return end
    if not isFriendOrGuild(sender) then return end   -- guild/friends only
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(sender) elseif InviteUnit then InviteUnit(sender) end
end)

------------------------------------------------------------------------
-- Chat: arrow keys, no fading, input on top, history after reload
------------------------------------------------------------------------
local function chatFrames()
    local out = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then out[#out + 1] = { f, _G["ChatFrame" .. i .. "EditBox"] } end
    end
    return out
end
-- recently sent lines (for own history)
CF.sentHistory = {}
-- 0.5.600: history survives /reload and restart (saved account-wide); after loading also hand back to WoW's own
-- input history (chat lines only, no commands like /tar - those would get blocked otherwise)
ns.Listen("DB_READY", function()
    ns.db.chatSent = ns.db.chatSent or {}
    local h = ns.db.chatSent
    for _, t in ipairs(CF.sentHistory) do if h[#h] ~= t then h[#h + 1] = t end end
    while #h > 40 do table.remove(h, 1) end
    CF.sentHistory = h
end)
ns.Listen("LOGIN", function()
    ns.After(2, function()
        local h = CF.sentHistory
        if #h == 0 then return end
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb and eb.AddHistoryLine then
                for _, t in ipairs(h) do if CF.HistoryOk and CF.HistoryOk(t) then pcall(eb.AddHistoryLine, eb, t) end end
            end
        end
    end)
end)
-- 0.5.575: text Oasis puts into the chat input via arrow counts as "from Oasis" for WoW - a /tar, /cast ...
-- from it gets blocked ("TargetUnit() blocked"). Only chat lines and plain channel commands go into own history.
local CHAT_CMD = { g = 1, gu = 1, guild = 1, p = 1, party = 1, w = 1, whisper = 1, t = 1, tell = 1, s = 1, say = 1, y = 1, yell = 1,
    ra = 1, raid = 1, rw = 1, i = 1, instance = 1, bg = 1, o = 1, officer = 1, e = 1, em = 1, me = 1, emote = 1, r = 1, reply = 1 }
local function historyOk(t)
    local cmd = t:match("^%s*/(%S+)")
    if not cmd then return true end
    cmd = cmd:lower()
    return CHAT_CMD[cmd] ~= nil or cmd:match("^%d+$") ~= nil
end
CF.HistoryOk = historyOk
local function remember(eb)
    local t = eb and eb.GetText and eb:GetText()
    if type(t) ~= "string" or t:gsub("%s", "") == "" then return end
    if not historyOk(t) then return end
    local h = CF.sentHistory
    if h[#h] ~= t then h[#h + 1] = t end
    if #h > 40 then table.remove(h, 1) end
end
if ChatEdit_SendText then hooksecurefunc("ChatEdit_SendText", function(eb) pcall(remember, eb) end) end
-- 0.5.599: also fill history from your own sent messages (say, guild, party, raid, whisper,
-- channels) - the hook on ChatEdit_SendText/Enter did not fire reliably in Forever, arrow up stayed empty
local function rememberText(t)
    t = ns.safe(t)
    if type(t) ~= "string" or t:gsub("%s", "") == "" then return end
    local h = CF.sentHistory
    if h[#h] ~= t then h[#h + 1] = t end
    if #h > 40 then table.remove(h, 1) end
end
for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }) do
    ns.On(ev, function(msg, sender) if ns.isMe(ns.safe(sender) or "") then pcall(rememberText, msg) end end)
end
for _, ev in ipairs({ "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM" }) do
    ns.On(ev, function(msg) pcall(rememberText, msg) end)
end
if ChatEdit_ActivateChat and not (ns.ForeignChat and ns.ForeignChat()) then
    hooksecurefunc("ChatEdit_ActivateChat", function(eb)
        if on("cfChatArrows") and eb and eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
    end)
end
function CF.ApplyChat()
    if ns.ForeignChat and ns.ForeignChat() then return end   -- input, arrow keys and mouse clicks are handled by the foreign chat
    for _, c in ipairs(chatFrames()) do
        local f, eb = c[1], c[2]
        if eb and not EBM[eb] and eb.HookScript then
            EBM[eb] = {}
            local function fix(self) if on("cfChatArrows") and self.SetAltArrowKeyMode then self:SetAltArrowKeyMode(false) end end
            eb:HookScript("OnShow", fix)
            eb:HookScript("OnEditFocusGained", function(self) fix(self) ns.After(0, function() fix(self) end) end)
            -- own history as fallback: only kicks in when WoW itself inserts nothing on arrow
            -- OnArrowPressed does not always fire in Forever -> also OnKeyDown (duplicates within 50 ms ignored)
            local function arrow(self, key)
                if not on("cfChatArrows") or (key ~= "UP" and key ~= "DOWN") then return end
                local now = GetTime()
                if EBM[self].arrowAt and now - EBM[self].arrowAt < 0.05 then return end
                EBM[self].arrowAt = now
                local before = self:GetText()
                ns.After(0, function()
                    if self:GetText() ~= before then return end
                    local h = CF.sentHistory
                    if #h == 0 then return end
                    EBM[self].histIdx = EBM[self].histIdx or (#h + 1)
                    if key == "UP" then EBM[self].histIdx = math.max(1, EBM[self].histIdx - 1)
                    else EBM[self].histIdx = math.min(#h + 1, EBM[self].histIdx + 1) end
                    self:SetText(h[EBM[self].histIdx] or "")
                    self:SetCursorPosition(#(self:GetText() or ""))
                end)
            end
            eb:HookScript("OnArrowPressed", arrow)
            eb:HookScript("OnKeyDown", arrow)
            -- also fill history if ChatEdit_SendText is named differently in this client: remember text before sending
            eb:HookScript("OnKeyDown", function(self, key) if key == "ENTER" then pcall(remember, self) end end)
            eb:HookScript("OnEnterPressed", function(self) EBM[self].histIdx = nil end)
            eb:HookScript("OnEscapePressed", function(self) EBM[self].histIdx = nil end)
        end
        if eb and eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(not on("cfChatArrows")) end
        if f.SetFading and not (ns.ForeignChat and ns.ForeignChat()) then f:SetFading(not on("cfChatNoFade")) end   -- 0.6.254
        if (ns.ForeignChat and ns.ForeignChat()) then
            -- 0.6.257: EllesmereUI positions the input itself (text area depends on it) - do not move
        elseif eb and on("cfChatTop") then
            eb:ClearAllPoints()
            eb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -5, 22)
            eb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 5, 22)
            EBM[eb] = EBM[eb] or {}
            EBM[eb].top = true
        elseif eb and EBM[eb] and EBM[eb].top then
            EBM[eb].top = nil
            eb:ClearAllPoints()
            eb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -5, -2)
            eb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 5, -2)
        end
    end
end
-- 0.6.105: only save lines added after restoring - otherwise every /reload carried the old
-- block (and history blocks of other features) along forever
local restoredUpTo = 0
-- nesUI has its own chat history across reloads -> then not additionally from Oasis (would be doubled)
local function nesUIHistory() return _G.nesUI ~= nil and not (_G.nesUIDB and (_G.nesUIDB.chatOff or _G.nesUIDB.chatHistOff)) end
local function saveChat()
    if nesUIHistory() then return end
    if not on("cfChatRestore") or not ChatFrame1 or not ChatFrame1.GetNumMessages then return end
    local lines = {}
    local n = ChatFrame1:GetNumMessages() or 0
    for i = math.max(1, n - 60, math.min(restoredUpTo, n) + 1), n do
        local ok, text, r, g, b = pcall(ChatFrame1.GetMessageInfo, ChatFrame1, i)
        if ok and type(text) == "string" and text ~= "" then lines[#lines + 1] = { t = text, r = r, g = g, b = b } end
    end
    ns.db.chatRestore = { ts = time(), lines = lines }
end
ns.On("PLAYER_LOGOUT", function() pcall(saveChat) end)
ns.On("PLAYER_LEAVING_WORLD", function() pcall(saveChat) end)
local function restoreChat()
    local cr = ns.db.chatRestore
    if nesUIHistory() then ns.db.chatRestore = nil return end
    if not on("cfChatRestore") or not cr or not cr.lines or time() - (cr.ts or 0) > 600 or not ChatFrame1 then return end
    if ns.ForeignChat and ns.ForeignChat() then ns.db.chatRestore = nil return end   -- 0.6.254: foreign chat has its own history
    ns.db.chatRestore = nil
    ChatFrame1:AddMessage("|cff666666- - - " .. L["Chat before reload"] .. " - - -|r")
    -- do not reinsert old history blocks (grey, "- - -") from earlier versions
    local skip = false
    for _, l in ipairs(cr.lines) do
        local t = l.t
        if type(t) == "string" and t:find("^|cff666666%- %- %-") then
            skip = not t:find("^|cff666666%- %- %- %- %-")   -- start line opens, plain dash line closes
        elseif not skip then
            ChatFrame1:AddMessage(t, l.r or 1, l.g or 1, l.b or 1)
        end
    end
    ChatFrame1:AddMessage("|cff666666- - - - - - - - - - -|r")
    restoredUpTo = ChatFrame1.GetNumMessages and ChatFrame1:GetNumMessages() or 0
end

------------------------------------------------------------------------
-- faster looting, error messages, camera, durability
------------------------------------------------------------------------
local lastLoot = 0
ns.On("LOOT_READY", function()
    if not on("cfFastLoot") then return end
    if GetTime() - lastLoot < 0.3 then return end
    lastLoot = GetTime()
    local auto = GetCVarBool and GetCVarBool("autoLootDefault")
    if auto ~= (IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")) then
        for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
    end
end)
function CF.ApplyErrors()
    if not UIErrorsFrame then return end
    if on("cfHideErrors") then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    else UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
end
-- 0.5.522: WoW Forever handles camera distance itself (Settings > Camera: Max camera distance) - Oasis no longer touches it
function CF.ApplyCamera()
    S().cfMaxZoom, S().cfMaxZoomWas = nil, nil
end
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
function CF.Durability()
    local cur, max, low = 0, 0, 1
    for _, s in ipairs(DUR_SLOTS) do
        local c, m = GetInventoryItemDurability(s)
        if c and m and m > 0 then cur, max = cur + c, max + m low = math.min(low, c / m) end
    end
    if max == 0 then return nil end
    return cur / max, low
end
local durWarned = 0
local function durUpdate()
    if not on("cfDurability") then if CF.durText then CF.durText:Hide() end return end
    local avg, low = CF.Durability()
    if not avg then return end
    if CharacterFrame and not CF.durText then
        CF.durText = CharacterFrame:CreateFontString(nil, "OVERLAY")
        if K.SetFontSafe then K.SetFontSafe(CF.durText, K.FONT, 12, "OUTLINE", K.FONT) else CF.durText:SetFont(K.FONT, 12, "OUTLINE") end
        CF.durText:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 26, 86)
    end
    if CF.durText then
        local c = avg >= 0.5 and "|cff66db9e" or (avg >= 0.2 and "|cffe8b44a" or "|cffff5a4a")
        CF.durText:SetText(L["Durability"] .. " " .. c .. math.floor(avg * 100) .. " %|r")
        CF.durText:Show()
    end
    if low < 0.2 and GetTime() - durWarned > 1800 then
        durWarned = GetTime()
        K.Toast(L["Gear almost broken"], (L["Worst item: %d %% - repair soon"]):format(math.floor(low * 100)), C.red)
    end
end
ns.On("UPDATE_INVENTORY_DURABILITY", function() pcall(durUpdate) end)

------------------------------------------------------------------------
-- Blizzard bars: hide menu bar (Character, Spellbook, ...) and bag bar,
-- optionally show again on mouseover. Display only - the keys (C, P, B ...) keep working.
------------------------------------------------------------------------
local function barFrames()
    return {
        micro = _G.MicroMenuContainer or _G.MicroMenu or _G.MicroButtonAndBagsBar,
        bags = _G.BagsBar,
    }
end
local barTick = nil
local function barWanted(key) return on(key == "micro" and "cfHideMicro" or "cfHideBags") end
-- 0.5.504: opacity only. Hide()/Show() on Blizzard's layout bars "touched" their arrangement
-- (edit mode/action bars) -> in combat Blocked UNKNOWN, bars vanished.
local function setBar(fr, key)
    if not fr then return end
    fr:SetAlpha(barWanted(key) and 0 or 1)
end
function CF.ApplyBars()
    local f = barFrames()
    setBar(f.micro, "micro")
    setBar(f.bags, "bags")
    -- Show on mouseover: check every 0.15 s whether the mouse is over it
    local hover = on("cfBarsHover") and (on("cfHideMicro") or on("cfHideBags"))
    if hover and not barTick then
        barTick = CreateFrame("Frame")
        barTick.t = 0
        -- crossfade each frame softly (0.18 s in, 0.35 s out), short trailing time against flicker at the edge
        barTick:SetScript("OnUpdate", function(self, el)
            local fr = barFrames()
            for key, x in pairs(fr) do
                if x and barWanted(key) and on("cfBarsHover") then
                    EBM[x] = EBM[x] or {}
                    if x:IsMouseOver(8, -8, -8, 8) then EBM[x].hold = 0.4 end
                    EBM[x].hold = math.max(0, (EBM[x].hold or 0) - el)
                    local want = EBM[x].hold > 0 and 1 or 0
                    local a = x:GetAlpha()
                    if a ~= want then
                        local step = el / (want > a and 0.18 or 0.35)
                        a = want > a and math.min(want, a + step) or math.max(want, a - step)
                        x:SetAlpha(a)
                    end
                end
            end
        end)
    end
    if barTick then barTick:SetShown(hover and true or false) end
end
ns.On("PLAYER_REGEN_ENABLED", function() if on("cfHideMicro") or on("cfHideBags") then pcall(CF.ApplyBars) end end)

function CF.ApplyAll()
    pcall(CF.ApplyChat)
    pcall(CF.ApplyErrors)
    pcall(CF.ApplyCamera)
    pcall(durUpdate)
    pcall(CF.ApplyBars)
end
ns.Listen("LOGIN", function()
    -- arrow keys without Alt: turn on once for everyone
    local s = ns.db.settings
    if not s.cfChatArrowsInit then
        s.cfChatArrowsInit = true
        if s.cfChatArrows == nil then s.cfChatArrows = true end
    end
    ns.After(2, CF.ApplyAll)
    ns.After(3, function() pcall(restoreChat) end)
end)

------------------------------------------------------------------------
-- settings: tab "Comfort"
------------------------------------------------------------------------
local OPTS = {
    { "Vendors", {
        { "cfSellJunk", "Sell grey items automatically", "At vendors. Hold Shift = skip this time." },
        { "cfRepair", "Repair automatically", "At vendors. Hold Shift = skip this time." },
        { "cfRepairGuild", "Repair from guild bank (if allowed)" },
    } },
    { "Quests & accepting", {
        { "cfQuests", "Accept and turn in quests automatically", "Only without reward choice and costs. Shift = skip." },
        { "cfSummon", "Accept summons and resurrections", "Summons not in combat." },
        { "cfBlockShared", "Decline quests shared by others" },
    } },
    { "Blizzard bars", {
        { "cfHideMicro", "Hide menu bar", "The buttons for character, spellbook, talents etc. Keys (C, P, N ...) still work.", CF.ApplyBars },
        { "cfHideBags", "Hide bag bar", "The B key still opens your bags.", CF.ApplyBars },
        { "cfBarsHover", "Show on mouseover", "Hidden bars appear as soon as the mouse is over them.", CF.ApplyBars },
    } },
    { "Blockers & groups", {
        { "cfBlockDuels", "Decline duels" },
        { "cfInvites", "Invites only from guild and friends", "Others are declined, guild/friends accepted." },
        { "cfWhisperInv", "Invite by whisper (guild/friends only)", "Keyword below, default: inv" },
    } },
    { "Chat", {
        { "cfChatArrows", "Arrow keys in chat without Alt", "Arrow up = recall last message", CF.ApplyChat },
        { "cfChatNoFade", "Don't fade chat", nil, CF.ApplyChat },
        { "cfChatRestore", "Keep chat after /reload" },
        { "cfChatTop", "Edit box above the chat window", "Moves the line you type in above the chat instead of below it - handy when the chat sits at the bottom edge of the screen and the input would be cut off.", CF.ApplyChat },
        { "emojiNoComplete", "No emoji suggestions while typing", "Otherwise: ':' + 2 letters shows matching emojis, Tab inserts." },
    } },
    { "Comfort", {
        { "cfFastLoot", "Faster looting (with auto loot)" },
        { "cfHideErrors", "Hide red error messages", nil, CF.ApplyErrors },
        { "cfDurability", "Show durability and warn", nil, durUpdate },
        { "upgradeTipOff", "No upgrade arrow in the tooltip", "Otherwise: green arrow when an item is better for your class and role." },
        { "upgradeIconOff", "No upgrade arrows on items", "Otherwise: green arrow up = better, red arrow down = worse (bags, loot window).", function() if ns.Upgrade then ns.Upgrade.RefreshBadges() end end },
        { "invTooltipOff", "No alt inventory in the tooltip", "Otherwise: the item tooltip shows which of your characters has it and how many." },
    } },
}
CF.CHAT_OPTS = OPTS[5][2]   -- for the Game chat tab
local function build(f)
    local H = ns.SettingsHelpers
    local x, y = 0, 0
    -- balanced columns: left vendor, quests, comfort - right blockers (+ keyword), bars, chat
    local byName = {}
    for _, grp in ipairs(OPTS) do byName[grp[1]] = grp end
    local LEFT = { "Vendors", "Quests & accepting", "Comfort" }
    local RIGHT = { "Blockers & groups", "Blizzard bars", "Chat" }
    -- 0.6.111: chat toggles live in the Game chat tab - here only when the game chat module is off
    if ns.GameChat then RIGHT[3] = nil end
    -- 0.5.720: one glass card per group (title inside the card, toggles in it) - no auto spacing, otherwise the cards overlap
    f.noCompact = true
    local ICON = { ["Vendors"] = "bank", ["Quests & accepting"] = "chronicle", ["Comfort"] = "home",
        ["Blockers & groups"] = "groups", ["Blizzard bars"] = "map", ["Chat"] = "polls" }
    local ROW = 28
    local function column(list, cx)
        x, y = cx, 0
        for _, nm in ipairs(list) do
            local grp = byName[nm]
            local extra = (nm == "Blockers & groups") and 36 or 0
            local h = 50 + #grp[2] * ROW + extra + 8
            local c = H.cardH(f, x, y, 362, h, ICON[nm] or "home", L[grp[1]])
            local cy = -48
            for _, o in ipairs(grp[2]) do
                H.toggle(c, 14, cy, o[2], o[1], o[3], o[4] and function() pcall(o[4]) end or nil, 334)
                cy = cy - ROW
            end
            if nm == "Blockers & groups" then
                -- keyword for whisper invites directly below the option
                H.rowLabel(c, L["Keyword"], 14, cy - 4)
                f.kw = K.Input(c, 120, "inv", function(t) S().cfInvKeyword = t end)
                f.kw:SetPoint("TOPLEFT", 114, cy - 2)
            end
            y = y - h - 12
        end
    end
    column(LEFT, 0)
    column(RIGHT, 376)
end
local function refresh(f)
    if f.kw and not f.kw:HasFocus() then f.kw:SetText(S().cfInvKeyword or "") end
end
if ns.AddSettingsTab then ns.AddSettingsTab("comfort", "Comfort", build, refresh) end
end)

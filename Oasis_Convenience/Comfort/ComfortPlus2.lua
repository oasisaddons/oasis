-- Oasis - Helpers, part 2: instance counter, new spells at the trainer, guild profession cooldowns,
-- items/gold of all own characters, group quest progress, hunter pet,
-- buy reagents, rare warning, hearthstone/IDs, fishing helper, equipment sets, range.
-- Settings: tab "Helpers"; overview: /oa chars or button in the tab.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Comfort", function()   -- module Comfort (can be disabled, see ModuleLoader.lua)
local TIPM = setmetatable({}, { __mode = "k" })   -- marker per tooltip (never write fields onto Blizzard frames)
local L = ns.L
local K, C = ns.K, ns.K.C
-- Safety on receive (other players' addon messages may be manipulated):
-- sanitize texts, clamp numbers, check names, throttle floods
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- neutralize escape sequences (|c |r |n |H |T |K |A ...) and control chars; links: valid item/spell links stay
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
    return ("%d min"):format(math.ceil(sec / 60))
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

-- new helpers on once (guild announcements and buying stay off until wanted)
ns.Listen("LOGIN", function()
    local s = S()
    if not s.cp2Init then
        s.cp2Init = true
        -- 0.6.522: only guild/group helpers on (raid IDs, guild profession cooldowns, group quest progress, rare warning)
        for _, k in ipairs({ "cpInstances", "cpProfCD", "cpQuestShare", "cpRare" }) do
            if s[k] == nil then s[k] = true end
        end
    end
end)

------------------------------------------------------------------------
-- 1. Instance counter (at most 5 new instances per hour, applies to the whole account)
------------------------------------------------------------------------
local function instList()
    ns.db.instHour = ns.db.instHour or {}
    local cut, out = time() - 3600, {}
    for _, e in ipairs(ns.db.instHour) do if e.ts > cut then out[#out + 1] = e end end
    ns.db.instHour = out
    return out
end
function H2.InstanceStatus()
    local list = instList()
    local n = #list
    local nextFree = n >= 5 and (list[1].ts + 3600 - time()) or nil
    return n, nextFree, list
end
local lastInst
ns.On("PLAYER_ENTERING_WORLD", function()
    if not on("cpInstances") then return end
    local inInst, typ = IsInInstance()
    if not inInst or (typ ~= "party" and typ ~= "raid") then lastInst = nil return end
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    if not mapID then return end
    local list = instList()
    -- the same (not reset) instance does not count again
    for _, e in ipairs(list) do if e.map == mapID and not e.reset then lastInst = mapID return end end
    if lastInst == mapID then return end
    lastInst = mapID
    table.insert(ns.db.instHour, { ts = time(), map = mapID, name = name, who = ns.me() })
    local n, nextFree = H2.InstanceStatus()
    local col = n >= 5 and C.red or (n >= 4 and (C.amber or C.red) or C.accent)
    local txt = (L["%d of 5 instances this hour"]):format(n)
    if n >= 5 then txt = txt .. " - " .. (L["next free in %s"]):format(fmtLeft(nextFree)) end
    K.Toast(L["Instance counter"], txt, col)
end)
ns.On("CHAT_MSG_SYSTEM", function(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    -- "X has been reset": all open entries count as a new instance on next entry
    local pat = INSTANCE_RESET_SUCCESS and INSTANCE_RESET_SUCCESS:gsub("%%s", "(.+)")
    if pat and msg:match(pat) then
        for _, e in ipairs(instList()) do e.reset = true end
        lastInst = nil
    end
end)
-- warning on attempted entry when the hour is full (group, nearby instance portal does not exist as an event)
ns.On("ZONE_CHANGED_NEW_AREA", function()
    if not on("cpInstances") then return end
    local n, nextFree = H2.InstanceStatus()
    if n >= 5 and not IsInInstance() then
        K.Toast(L["Instance counter"], (L["5 of 5 - next instance only in %s"]):format(fmtLeft(nextFree)), C.red)
    end
end)

------------------------------------------------------------------------
-- 2. New spells at the trainer (Oasis learns the list when visiting the trainer)
------------------------------------------------------------------------
local function readTrainer()
    if not GetNumTrainerServices or (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    -- briefly turn all filters on so the not-yet-learnable spells appear too
    local saved = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs({ "available", "unavailable", "used" }) do
            saved[f] = GetTrainerServiceTypeFilter(f)
            SetTrainerServiceTypeFilter(f, 1)
        end
    end
    local list = {}
    for i = 1, GetNumTrainerServices() do
        local name, rank, cat = GetTrainerServiceInfo(i)
        if name and cat ~= "used" and cat ~= "header" then
            local req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            list[#list + 1] = { n = name, r = rank or "", l = req or 0, c = cost or 0 }
        end
    end
    for f, v in pairs(saved) do SetTrainerServiceTypeFilter(f, v and 1 or 0) end
    char().trainer = { ts = time(), list = list }
end
ns.On("TRAINER_SHOW", function() if on("cpTrainer") then pcall(readTrainer) end end)
function H2.TrainerDue(lvl)
    local t = char().trainer
    if not t then return nil end
    local out, cost = {}, 0
    for _, s in ipairs(t.list) do
        if s.l <= lvl then out[#out + 1] = s cost = cost + s.c end
    end
    return out, cost
end
ns.On("PLAYER_LEVEL_UP", function(lvl)
    if not on("cpTrainer") or type(lvl) ~= "number" then return end
    ns.After(2, function()
        local due, cost = H2.TrainerDue(lvl)
        if not due then
            if lvl % 2 == 0 then K.Toast(L["New spells?"], L["Visit your class trainer - Oasis will then remind you exactly."], C.accent) end
            return
        end
        if #due == 0 then return end
        local names = {}
        for i = 1, math.min(4, #due) do names[#names + 1] = due[i].n .. (due[i].r ~= "" and (" (" .. due[i].r .. ")") or "") end
        K.Toast((L["New spells available (%d)"]):format(#due), table.concat(names, ", ") .. (#due > 4 and " ..." or "") .. "  |  " .. money(cost), C.mint)
    end)
end)

------------------------------------------------------------------------
-- 3. Profession cooldowns (shared with the guild)
------------------------------------------------------------------------
-- key -> spell (all transmutations share one cooldown)
local PROFCD = {
    { key = "transmute", label = "Transmute", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 } },
    { key = "mooncloth", label = "Mooncloth", spells = { 18560 } },
    { key = "salt", label = "Salt Shaker", item = 15846 },
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
-- all guild cooldowns: { { who, key, ready } }
function H2.GuildProfCDs()
    local out = {}
    for _, r in ipairs(Store.List("profcd", function(r) return not r.del end)) do
        for k, ts in (r.cd or ""):gmatch("(%a+):(%d+)") do out[#out + 1] = { who = r.by, key = k, ready = tonumber(ts) } end
    end
    table.sort(out, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.ready < b.ready end)
    return out
end

------------------------------------------------------------------------
-- 4. Items and gold of all own characters
------------------------------------------------------------------------
local function scanBags(from, to)
    local t = {}
    if not C_Container then return t end
    for b = from, to do
        for s = 1, (C_Container.GetContainerNumSlots(b) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, b, s)
            if ok and type(info) == "table" and info.itemID then t[info.itemID] = (t[info.itemID] or 0) + (info.stackCount or 1) end
        end
    end
    return t
end
local bagPending
local function saveBags()
    local c = char()
    c.bags = scanBags(0, 4)
    c.money = GetMoney()
    c.class = select(2, UnitClass("player"))
    c.lvl = UnitLevel("player")
    c.seen = time()
end
ns.On("BAG_UPDATE_DELAYED", function()
    if bagPending then return end
    bagPending = true
    ns.After(2, function() bagPending = nil pcall(saveBags) end)
end)
ns.On("PLAYER_MONEY", function() char().money = GetMoney() end)
ns.On("BANKFRAME_OPENED", function()
    pcall(function()
        local bank = scanBags(5, 11)
        local main = scanBags(-1, -1)
        for id, n in pairs(main) do bank[id] = (bank[id] or 0) + n end
        char().bank = bank
    end)
end)
ns.Listen("LOGIN", function() ns.After(5, function() pcall(saveBags) end) end)
-- tooltip lines
local function altLines(tt)
    -- 0.6.621: "Bags & alts" (Oasis base) shows the counts already - this second list only without it
    if not on("cpAltItems") or TIPM[tt] or not (ns.db.settings.invTooltipOff) then return end
    local _, link = tt:GetItem()
    if not link or (issecretvalue and issecretvalue(link)) then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    TIPM[tt] = true
    local total, lines = 0, {}
    for name, c in pairs(ns.db.chars) do
        local b = (c.bags and c.bags[id]) or 0
        local k = (c.bank and c.bank[id]) or 0
        if (b + k) > 0 then
            total = total + b + k
            local parts = {}
            if b > 0 then parts[#parts + 1] = (L["Bags %d"]):format(b) end
            if k > 0 then parts[#parts + 1] = (L["Bank %d"]):format(k) end
            local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
            lines[#lines + 1] = { (ns.displayName and ns.displayName(name) or ns.short(name)), table.concat(parts, ", "), cc }
        end
    end
    if #lines == 0 then return end
    for _, l in ipairs(lines) do
        local cc = l[3]
        tt:AddDoubleLine(l[1], l[2], cc and cc.r or 0.8, cc and cc.g or 0.8, cc and cc.b or 0.8, 0.8, 0.8, 0.8)
    end
    if #lines > 1 then tt:AddDoubleLine(L["Total"], tostring(total), 0.6, 0.6, 0.6, 1, 1, 1) end
    tt:Show()
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) if tt == GameTooltip or tt == ItemRefTooltip then pcall(altLines, tt) end end)
elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt) pcall(altLines, tt) end)
end
if GameTooltip then GameTooltip:HookScript("OnTooltipCleared", function(tt) TIPM[tt] = nil end) end

------------------------------------------------------------------------
-- 5. Group quest progress (Oasis groupmates only)
------------------------------------------------------------------------
local partyQ = {}   -- name -> { [quest title] = { "6/10 Kolkar", ... } }
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
    -- only members of your own group, texts sanitized, amounts clamped
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
    -- objective just completed? briefly report if you have the quest yourself
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
-- tooltip of a group member: shared quests
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
-- 6. Hunter pet: happiness + food
------------------------------------------------------------------------
local lastHappy
local function petCheck()
    if not on("cpPet") or not GetPetHappiness or not UnitExists("pet") then lastHappy = nil return end
    local h = GetPetHappiness()
    if not h then return end
    if h < 3 and h ~= lastHappy then
        K.Toast(L["Pet"], h == 1 and L["Your pet is unhappy - feed it!"] or L["Your pet is hungry."], h == 1 and C.red or (C.amber or C.red))
    end
    lastHappy = h
end
ns.On("UNIT_HAPPINESS", function(u) if u == "pet" then pcall(petCheck) end end)
ns.On("UNIT_PET", function(u) if u == "player" then ns.After(1, function() pcall(petCheck) end) end end)
ns.On("MERCHANT_SHOW", function()
    if not on("cpPet") or select(2, UnitClass("player")) ~= "HUNTER" or not UnitExists("pet") then return end
    pcall(function()
        local foods = GetPetFoodTypes and { GetPetFoodTypes() } or {}
        local h = GetPetHappiness and GetPetHappiness() or 3
        if h < 3 or #foods > 0 then
            K.Toast(L["Pet food?"], (L["Your pet eats: %s"]):format(table.concat(foods, ", ")), C.accent)
        end
    end)
end)

------------------------------------------------------------------------
-- 7. Auto-restock reagents (up to the target amount)
------------------------------------------------------------------------
H2.REAG_TARGET = { [17020] = 20, [17031] = 10, [17032] = 5, [17028] = 20, [17029] = 10, [5140] = 10, [17030] = 5,
    [21177] = 20, [17033] = 5, [17034] = 10, [17026] = 10 }
local AMMO_TARGET = 1000
ns.On("MERCHANT_SHOW", function()
    if not on("cpReagBuy") or not GetMerchantNumItems or IsShiftKeyDown() then return end
    ns.After(0.3, function()
        pcall(function()
            local want = {}
            for id, n in pairs(H2.REAG_TARGET) do
                local have = itemCount(id)
                -- only what you already use (seen in possession once)
                if (S().cpReagSeen or {})[tostring(id)] and have < n then want[id] = n - have end
            end
            -- ammo: same kind as the equipped one
            local ammoSlot = GetInventorySlotInfo and select(1, pcall(GetInventorySlotInfo, "AmmoSlot")) and GetInventorySlotInfo("AmmoSlot")
            local ammoID = ammoSlot and GetInventoryItemID and GetInventoryItemID("player", ammoSlot)
            if ammoID then
                local have = itemCount(ammoID)
                if have < AMMO_TARGET then want[ammoID] = AMMO_TARGET - have end
            end
            local bought = {}
            for i = 1, GetMerchantNumItems() do
                local id = GetMerchantItemID and GetMerchantItemID(i)
                local need = id and want[id]
                if need and need > 0 then
                    local _, _, price, per = GetMerchantItemInfo(i)
                    per = (per and per > 0) and per or 1
                    local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 20
                    local packs = math.ceil(need / per)
                    if price and price * packs <= GetMoney() then
                        local left = packs
                        while left > 0 do
                            local q = math.min(left, math.max(1, math.floor(maxStack / per)))
                            BuyMerchantItem(i, q)
                            left = left - q
                        end
                        bought[#bought + 1] = (GetMerchantItemInfo(i)) .. " x" .. (packs * per)
                    end
                end
            end
            if #bought > 0 then ns.print(L["Restocked: "] .. table.concat(bought, ", ")) end
        end)
    end)
end)

------------------------------------------------------------------------
-- 8. Rare warning (+ to the guild)
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
    K.Toast(L["Rare nearby!"], (name or "?") .. "  |cff999999" .. zone .. (" (%.0f, %.0f)"):format(x * 100, y * 100) .. "|r", C.amber or C.accent, nil, "toast")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if on("cpRareShare") and IsInGuild() then Comm.Guild("RARE", name or "?", zone, ("%.1f"):format(x * 100), ("%.1f"):format(y * 100)) end
end
ns.On("NAME_PLATE_UNIT_ADDED", function(u) pcall(rareCheck, u) end)
ns.On("PLAYER_TARGET_CHANGED", function() pcall(rareCheck, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() pcall(rareCheck, "mouseover") end)
Comm.On("RARE", function(sender, _, name, zone, x, y)
    if not on("cpRare") or ns.isMe(sender) then return end
    -- at most every 30 s per sender; texts sanitized, coordinates 0..100
    if not SEC.Rate("rare:" .. sender, 30) then return end
    x, y = SEC.Num(x, 0, 100), SEC.Num(y, 0, 100)
    K.Toast(L["Rare (guild)"], (L["%s sees %s - %s (%s, %s)"]):format(ns.displayName and ns.displayName(sender) or ns.short(sender),
        SEC.Text(name or "?", 50), SEC.Text(zone or "", 50), x and ("%.1f"):format(x) or "?", y and ("%.1f"):format(y) or "?"), C.amber or C.accent)
end)

------------------------------------------------------------------------
-- 9. Hearthstone + instance IDs of all own characters
------------------------------------------------------------------------
local function saveBind()
    local c = char()
    c.bind = GetBindLocation and GetBindLocation() or c.bind
    local ids = {}
    if GetNumSavedInstances then
        for i = 1, GetNumSavedInstances() do
            local name, id, reset, _, locked = GetSavedInstanceInfo(i)
            if name and locked and reset and reset > 0 then ids[#ids + 1] = { n = name, id = id, until_ = time() + reset } end
        end
    end
    c.ids = ids
end
ns.On("UPDATE_INSTANCE_INFO", function() pcall(saveBind) end)
ns.On("HEARTHSTONE_BOUND", function() pcall(saveBind) end)
ns.Listen("LOGIN", function() if RequestRaidInfo then RequestRaidInfo() end ns.After(6, function() pcall(saveBind) end) end)

------------------------------------------------------------------------
-- 10. Fishing helper: double right-click casts + catch statistics
------------------------------------------------------------------------
local FISHING = 7620   -- Fishing (spell), name comes from the game
local fishBtn
local function poleEquipped()
    local link = GetInventoryItemLink("player", 16)
    if not link then return false end
    local _, _, _, _, _, _, _, _, _, _, _, classID, subID = (C_Item and C_Item.GetItemInfo or GetItemInfo)(link)
    return classID == 2 and subID == 20
end
local function setupFishing()
    if fishBtn or InCombatLockdown() then return end
    fishBtn = CreateFrame("Button", "OasisFishButton", UIParent, "SecureActionButtonTemplate")
    fishBtn:SetAttribute("type", "spell")
    fishBtn:SetAttribute("spell", spellName(FISHING) or "Fishing")
    fishBtn:RegisterForClicks("AnyUp", "AnyDown")
    fishBtn:SetSize(1, 1)
    fishBtn:SetPoint("TOPLEFT", -10, 10)
    fishBtn:HookScript("PostClick", function()
        if not InCombatLockdown() then ClearOverrideBindings(fishBtn) end
    end)
end
local lastRight = 0
if WorldFrame then
    WorldFrame:HookScript("OnMouseDown", function(_, button)
        if button ~= "RightButton" or not on("cpFishing") or InCombatLockdown() then return end
        if GetTime() - lastRight < 0.4 and poleEquipped() then
            setupFishing()
            if fishBtn then SetOverrideBindingClick(fishBtn, true, "BUTTON2", "OasisFishButton") end
            lastRight = 0
        else
            lastRight = GetTime()
        end
    end)
end
ns.On("LOOT_OPENED", function()
    if not on("cpFishing") or not (IsFishingLoot and IsFishingLoot()) then return end
    ns.db.fishing = ns.db.fishing or { casts = 0, items = {} }
    local f = ns.db.fishing
    f.casts = f.casts + 1
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local _, _, qty = GetLootSlotInfo(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then f.items[id] = (f.items[id] or 0) + (qty or 1) end
    end
end)

------------------------------------------------------------------------
-- 11. Equipment sets (own, without Blizzard's manager)
------------------------------------------------------------------------
local SET_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
function H2.SaveSet(name)
    if not name or name == "" then return end
    local set = {}
    for _, s in ipairs(SET_SLOTS) do set[s] = GetInventoryItemLink("player", s) or false end
    char().sets = char().sets or {}
    char().sets[name] = set
    ns.print((L["Set saved: %s"]):format(name))
end
function H2.EquipSet(name)
    if InCombatLockdown() then ns.print(L["Only possible after combat."]) return end
    local set = char().sets and char().sets[name]
    if not set then return end
    local missing = 0
    for _, s in ipairs(SET_SLOTS) do
        local want = set[s]
        local cur = GetInventoryItemLink("player", s)
        if want and want ~= cur then
            local ok = pcall(EquipItemByName, want, s)
            if not ok then missing = missing + 1 end
        end
    end
    ns.print((L["Set equipped: %s"]):format(name) .. (missing > 0 and ((L[" (%d items missing)"]):format(missing)) or ""))
end
function H2.DeleteSet(name) if char().sets then char().sets[name] = nil end end
ns.slash.set = function(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = arg:match("^(%S+)%s*(.*)$")
    if cmd == "save" or cmd == "speichern" then H2.SaveSet(rest)
    elseif cmd == "del" or cmd == "loeschen" then H2.DeleteSet(rest)
    elseif arg ~= "" then H2.EquipSet(arg)
    else H2.Overview("sets") end
end

------------------------------------------------------------------------
-- 12. Range on action bars (button red when the target is too far)
------------------------------------------------------------------------
-- 0.5.504: NO more fields on Blizzard's secure action buttons and no calling their
-- UpdateUsable from Oasis - that "touched" the action bars (Blocked UNKNOWN in combat,
-- bar vanished, casting errors). Markers in own table, compute color ourselves.
local rangeRed = setmetatable({}, { __mode = "k" })
local function secret(v) return issecretvalue and issecretvalue(v) end
local function rangeHook(self, checksRange, inRange)
    if not on("cpRange") then return end
    if secret(checksRange) or secret(inRange) then return end
    local icon = self.icon or self.Icon
    if not icon then return end
    if checksRange and inRange == false then
        icon:SetVertexColor(0.85, 0.22, 0.2)
        rangeRed[self] = true
    elseif rangeRed[self] then
        rangeRed[self] = nil
        local usable, noMana = true, false
        local act = self.action
        local IU = (C_ActionBar and C_ActionBar.IsUsableAction) or IsUsableAction
        if act and not secret(act) and IU then
            local ok, u, m = pcall(IU, act)
            if ok and not secret(u) and not secret(m) then usable, noMana = u, m end
        end
        if usable then icon:SetVertexColor(1, 1, 1)
        elseif noMana then icon:SetVertexColor(0.5, 0.5, 1)
        else icon:SetVertexColor(0.4, 0.4, 0.4) end
    end
end
if ActionButton_UpdateRangeIndicator then hooksecurefunc("ActionButton_UpdateRangeIndicator", rangeHook) end
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateRangeIndicator then
    hooksecurefunc(ActionBarActionButtonMixin, "UpdateRangeIndicator", rangeHook)
end

------------------------------------------------------------------------
-- overview window: characters, guild cooldowns, sets, fishing
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
local function fillChars(f)
    local y = 0
    local n, nextFree = H2.InstanceStatus()
    y = row(f, y, "|cffffd24a" .. L["Instances this hour"] .. "|r", n .. " / 5" .. (nextFree and ("  -  " .. (L["free in %s"]):format(fmtLeft(nextFree))) or ""))
    y = y - 6
    local total = 0
    local names = {}
    for name in pairs(ns.db.chars) do names[#names + 1] = name end
    table.sort(names, function(a, b) return (ns.db.chars[a].money or 0) > (ns.db.chars[b].money or 0) end)
    for _, name in ipairs(names) do
        local c = ns.db.chars[name]
        total = total + (c.money or 0)
        y = row(f, y, classColored(name, c.class) .. (c.lvl and ("  |cff888888" .. c.lvl .. "|r") or ""), money(c.money or 0))
        local sub = {}
        if c.bind then sub[#sub + 1] = "|TInterface\\Icons\\INV_Misc_Rune_01:12:12|t " .. c.bind end
        for _, id in ipairs(c.ids or {}) do
            if id.until_ > time() then sub[#sub + 1] = id.n .. " (" .. fmtLeft(id.until_ - time()) .. ")" end
        end
        if #sub > 0 then y = row(f, y, "   |cff999999" .. table.concat(sub, "   ") .. "|r", "") end
    end
    y = y - 4
    y = row(f, y, "|cffffd24a" .. L["Total gold"] .. "|r", money(total))
    return y
end
local function fillCDs(f)
    local y = 0
    local list = H2.GuildProfCDs()
    if #list == 0 then return row(f, y, L["No cooldowns shared yet - anyone with Transmute, Mooncloth or a Salt Shaker shows up here."], "", C.dim) end
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
            left <= 0 and ("|cff66db9e" .. L["ready"] .. "|r") or ("|cffaaaaaa" .. fmtLeft(left) .. "|r"))
    end
    return y
end
local function fillFish(f)
    local y = 0
    local fs = ns.db.fishing
    y = row(f, y, L["Double right-click casts (fishing pole must be equipped)."], "", C.dim)
    if not fs or fs.casts == 0 then return row(f, y, L["Nothing caught yet."], "", C.dim) end
    y = row(f, y, "|cffffd24a" .. L["Catches"] .. "|r", tostring(fs.casts))
    local items = {}
    for id, n in pairs(fs.items) do items[#items + 1] = { id = id, n = n } end
    table.sort(items, function(a, b) return a.n > b.n end)
    for i = 1, math.min(14, #items) do
        local name = (C_Item and C_Item.GetItemInfo or GetItemInfo)(items[i].id) or ("#" .. items[i].id)
        y = row(f, y, "   " .. name, items[i].n .. "  |cff888888(" .. math.floor(items[i].n / fs.casts * 100 + 0.5) .. " %)|r")
    end
    return y
end
local function fillSets(f)
    local y = 0
    f.setBtns = f.setBtns or {}
    for _, b in ipairs(f.setBtns) do b:Hide() end
    y = row(f, y, L["Save current gear as a set:"], "", C.dim)
    if not f.setName then
        f.setName = K.Input(f.body, 180, L["Name, e.g. Fishing"], function() end)
        f.setSave = K.Button(f.body, L["Save"], 100, 24, "primary", function()
            H2.SaveSet((f.setName:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            f.setName:SetText("")
            H2.Overview("sets")
        end)
        f.setSave:SetPoint("LEFT", f.setName, "RIGHT", 8, 0)
    end
    f.setName:ClearAllPoints()
    f.setName:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, y)
    f.setName:Show() f.setSave:Show()
    y = y - 34
    local names = {}
    for n in pairs(char().sets or {}) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then return row(f, y, L["No sets yet."], "", C.dim) end
    for i, n in ipairs(names) do
        local b = f.setBtns[i]
        if not b then
            b = K.Button(f.body, "", 200, 24, "ghost")
            b.del = K.Button(f.body, L["Put out"], 80, 24, "ghost")
            f.setBtns[i] = b
        end
        b:SetLabel(n)
        b:SetScript("OnClick", function() H2.EquipSet(n) end)
        b.del:SetScript("OnClick", function() H2.DeleteSet(n) H2.Overview("sets") end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, y)
        b.del:ClearAllPoints()
        b.del:SetPoint("LEFT", b, "RIGHT", 6, 0)
        b:Show() b.del:Show()
        y = y - 28
    end
    row(f, y - 4, L["Also via command: /oa set Name"], "", C.dim)
    return y
end
local FILL = { chars = fillChars, cds = fillCDs, sets = fillSets, fish = fillFish }
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
    title:SetText(L["Characters & helpers"])
    local x = K.CloseButton(f, function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -6, -6)
    f.seg = K.Segments(f, { { key = "chars", text = L["Characters"] }, { key = "cds", text = L["Cooldowns"] },
        { key = "sets", text = L["Sets"] }, { key = "fish", text = L["Fishing"] } }, function(k) H2.Overview(k) end, nil, { size = 12, pad = 16 })
    f.seg:SetPoint("TOPLEFT", 12, -40)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", 16, -76)
    f.body:SetPoint("BOTTOMRIGHT", -16, 14)
    if ns.EscClose then ns.EscClose("OasisHelperOverview") end   -- NOT UISpecialFrames (otherwise blocks SpellStopCasting/-Targeting)
    f:Hide()
    return f
end
function H2.Overview(tab)
    if not ov then ov = buildOverview() end
    tab = tab or ov.tab or "chars"
    ov.tab = tab
    ov.seg:Select(tab)
    clearRows(ov)
    if ov.setName then ov.setName:Hide() ov.setSave:Hide() end
    for _, b in ipairs(ov.setBtns or {}) do b:Hide() b.del:Hide() end
    pcall(saveBags) pcall(saveBind)
    local ok, e = pcall(FILL[tab], ov)
    if not ok then ns.err("Helfer-Uebersicht", e) end
    ov:Show()
    ov:Raise()
end
ns.slash.chars = function() H2.Overview("chars") end
ns.slash.cds = function() H2.Overview("cds") end

-- for the settings (tab "Helpers")
H2.OPTS = {
    { "Instances & trainer", {
        { "cpInstances", "Instance counter (5 per hour)", "Tells you on entry how many instances you had in the last hour" },
        { "cpTrainer", "New spells at the trainer", "On level up: what you can learn now and what it costs" },
        { "cpReagBuy", "Restock reagents and ammo", "Auto-refill at vendors (ammo up to 1000). Shift = skip" },
        { "cpPet", "Hunter: pet happiness and food", "Warns when your pet is hungry, food hint at vendors" },
    } },
    { "Guild & group", {
        { "cpProfCD", "Share profession cooldowns with the guild", "Transmute, Mooncloth, Salt Shaker - who is ready? (overview)" },
        { "cpQuestShare", "Group quest progress", "In the tooltip of group members with Oasis, notice when an objective is done" },
        { "cpRare", "Rare alert", "Sound + notice for rare enemies nearby" },
        { "cpRareShare", "Report rares to the guild", "Others with Oasis see where you found a rare" },
    } },
    { "Characters & gear", {
        { "cpFishing", "Fishing helper", "Double right-click casts, catch statistics in the overview" },
        { "cpRange", "Range on action bars", "Button turns red when the target is out of range" },
    } },
}
end)

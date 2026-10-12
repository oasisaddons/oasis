-- Oasis - Helfer: kleine Dinge, fuer die man sonst eigene Addons installiert
-- (EP pro Stunde, Tooltip-Extras, Post "Alles oeffnen", Reagenzien, Flugzeit, Koordinaten,
--  Chat-Links/Klassenfarben/Zeitstempel, Gegenstandsstufe beim Betrachten, Weltkarte aufdecken)
-- Alles einzeln schaltbar (Einstellungen > Komfort > Helfer, Weltkarte: Bereiche > Karte).
local ADDON, ns = ...
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
    if s.cpDisenchant == nil then s.cpDisenchant = true end   -- neu in 0.5.856: auch fuer bestehende Nutzer an
    if s.fojjiBridge == nil then s.fojjiBridge = true end
    if s.cpQuestReward == nil then s.cpQuestReward = true end
    if not s.cpInit then
        s.cpInit = true
        for _, k in ipairs({ "cpXP", "cpTooltip", "cpTooltipGuild", "cpMail", "cpReagents", "cpFlight", "cpChatLinks", "cpInspect" }) do
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
-- 1. Erfahrung pro Stunde, Zeit bis zum Levelaufstieg, Ruhebonus
------------------------------------------------------------------------
local xp = { start = nil, gained = 0, last = nil, shared = {} }
local function xpBox()
    if CP.xpBox then return CP.xpBox end
    local f = CreateFrame("Frame", "OasisXPInfo", UIParent)
    f:SetSize(260, 18)
    f:SetFrameStrata("LOW")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        S().cpXPPos = { p, rp, math.floor(x), math.floor(y) }
    end)
    f.text = f:CreateFontString(nil, "OVERLAY")
    if K.SetFontSafe then K.SetFontSafe(f.text, K.FONT, 11, "OUTLINE", K.FONT) else f.text:SetFont(K.FONT, 11, "OUTLINE") end
    f.text:SetPoint("CENTER")
    f:SetScript("OnEnter", function(self)
        local t = { L["Erfahrung"] }
        local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
        t[#t + 1] = ("%s / %s  (%d %%)"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur, BreakUpLargeNumbers and BreakUpLargeNumbers(max) or max, math.floor(cur / math.max(1, max) * 100))
        local rest = GetXPExhaustion and GetXPExhaustion() or 0
        if rest and rest > 0 then t[#t + 1] = "|cff6aa8ff" .. L["Ruhebonus"] .. ": " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(rest) or rest) .. "|r" end
        if xp.start then t[#t + 1] = (L["Diese Sitzung: %d EP in %s"]):format(xp.gained, fmtTime(GetTime() - xp.start)) end
        t[#t + 1] = "|cff888888" .. L["Shift + Ziehen: verschieben"] .. "|r"
        K.ShowTip(self, t)
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local pos = S().cpXPPos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 118) end
    f:Hide()
    CP.xpBox = f
    return f
end
function CP.XPRate()
    if not xp.start or xp.gained <= 0 then return nil end
    local dt = GetTime() - xp.start
    if dt < 60 then return nil end
    return xp.gained / dt * 3600
end
function CP.UpdateXP()
    local lvl = UnitLevel("player") or 1
    local maxLvl = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if not on("cpXP") or lvl >= maxLvl then if CP.xpBox then CP.xpBox:Hide() end return end
    local f = xpBox()
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    local parts = {}
    local rate = CP.XPRate()
    if rate then
        parts[#parts + 1] = (L["%s EP/Std"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(rate)) or math.floor(rate))
        local eta = (max - cur) / rate * 3600
        parts[#parts + 1] = (L["Level %d in %s"]):format(lvl + 1, fmtTime(eta))
        -- optional: Meilenstein (10, 20, ...) bald erreicht -> einmal an die Gilde
        if on("cpXPShare") and (lvl + 1) % 10 == 0 and eta < 45 * 60 and not xp.shared[lvl + 1] and IsInGuild and IsInGuild() then
            xp.shared[lvl + 1] = true
            ns.OfferChat(L["Im Gildenchat zeigen?"], (L["[Oasis] Noch ~%d Min bis Level %d!"]):format(math.max(1, math.floor(eta / 60 + 0.5)), lvl + 1), "GUILD")
        end
    else
        parts[#parts + 1] = (L["Level %d: %d %%"]):format(lvl, math.floor(cur / math.max(1, max) * 100))
    end
    if rest and rest > 0 then parts[#parts + 1] = "|cff6aa8ff" .. (L["Ruhebonus %d %%"]):format(math.floor(rest / math.max(1, max) * 100)) .. "|r" end
    f.text:SetText(table.concat(parts, "  |cff666666·|r  "))
    f:SetWidth(math.max(120, f.text:GetStringWidth() + 16))
    f:Show()
end
ns.On("PLAYER_XP_UPDATE", function()
    local cur = UnitXP("player") or 0
    if xp.last and cur > xp.last then
        xp.start = xp.start or GetTime()
        xp.gained = xp.gained + (cur - xp.last)
    end
    xp.last = cur
    pcall(CP.UpdateXP)
end)
ns.On("PLAYER_LEVEL_UP", function()
    -- neues Level: der Rest der alten Stufe zaehlt mit
    local max = UnitXPMax("player") or 0
    if xp.last then xp.start = xp.start or GetTime() xp.gained = xp.gained + math.max(0, max - xp.last) end
    xp.last = 0
    ns.After(1, function() xp.last = UnitXP("player") or 0 pcall(CP.UpdateXP) end)
end)
ns.On("UPDATE_EXHAUSTION", function() pcall(CP.UpdateXP) end)

------------------------------------------------------------------------
-- 2. Tooltip-Extras: Haendlerpreis, Gegenstandsstufe, ID; Gildenmitglieder
------------------------------------------------------------------------
local function stackOf(tt)
    local owner = tt.GetOwner and tt:GetOwner()
    if not owner or not owner.GetID or not owner.GetParent then return 1 end
    local slot, parent = owner:GetID(), owner:GetParent()
    local bag = parent and parent.GetID and parent:GetID()
    if bag and slot and C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" and info.stackCount then return info.stackCount end
    end
    if owner.count and type(owner.count) == "number" then return owner.count end
    return 1
end
------------------------------------------------------------------------
-- Entzaubern: was aus einem Teil herauskommen kann (Classic-Tabellen nach Gegenstandsstufe, Seltenheit, Waffe/Ruestung).
-- Namen kommen ueber die Item-ID aus dem Spiel (richtige Sprache); der Text dahinter ist nur der Rueckfall.
------------------------------------------------------------------------
local DE = {}
ns.Disenchant = DE
local DUST = { { 10940, "Seltsamer Staub" }, { 11083, "Seelenstaub" }, { 11137, "Visionenstaub" }, { 11176, "Traumstaub" }, { 16204, "Illusionsstaub" } }
local ESS = { { 10938, "Geringe Magie-Essenz" }, { 10939, "Grosse Magie-Essenz" }, { 10998, "Geringe Astral-Essenz" }, { 11082, "Grosse Astral-Essenz" },
    { 11134, "Geringe Mystiker-Essenz" }, { 11135, "Grosse Mystiker-Essenz" }, { 11174, "Geringe Nether-Essenz" }, { 11175, "Grosse Nether-Essenz" },
    { 16202, "Geringe ewige Essenz" }, { 16203, "Grosse ewige Essenz" } }
local SHARD = { { 10978, "Kleiner gleissender Splitter" }, { 11084, "Grosser gleissender Splitter" }, { 11138, "Kleiner leuchtender Splitter" },
    { 11139, "Grosser leuchtender Splitter" }, { 11177, "Kleiner strahlender Splitter" }, { 11178, "Grosser strahlender Splitter" },
    { 14343, "Kleiner glaenzender Splitter" }, { 14344, "Grosser glaenzender Splitter" } }
local NEXUS = { 20725, "Nexuskristall" }
-- Gruen: bis Stufe -> { Staub, Menge, Essenz, Menge, Splitter }
local GREEN = {
    { 15, DUST[1], "1-2", ESS[1], "1-2", nil },
    { 20, DUST[1], "2-3", ESS[2], "1-2", SHARD[1] },
    { 25, DUST[1], "4-6", ESS[3], "1-2", SHARD[1] },
    { 30, DUST[2], "1-2", ESS[4], "1-2", SHARD[2] },
    { 35, DUST[2], "2-5", ESS[5], "1-2", SHARD[3] },
    { 40, DUST[3], "1-2", ESS[6], "1-2", SHARD[4] },
    { 45, DUST[3], "2-5", ESS[7], "1-2", SHARD[5] },
    { 50, DUST[4], "1-2", ESS[8], "1-2", SHARD[6] },
    { 55, DUST[4], "2-5", ESS[9], "1-2", SHARD[7] },
    { 60, DUST[5], "1-2", ESS[10], "1-2", SHARD[8] },
    { 999, DUST[5], "2-5", ESS[10], "2-3", SHARD[8] },
}
local BLUE = { { 25, SHARD[1] }, { 30, SHARD[2] }, { 35, SHARD[3] }, { 40, SHARD[4] }, { 45, SHARD[5] }, { 50, SHARD[6] }, { 55, SHARD[7] }, { 999, SHARD[8] } }
local PURPLE = { { 45, SHARD[5], "2-4" }, { 50, SHARD[6], "2-4" }, { 55, SHARD[7], "2-4" }, { 60, NEXUS, "1" }, { 999, NEXUS, "1-2" } }
local function row(t, lvl) for _, r in ipairs(t) do if lvl <= r[1] then return r end end end
-- Ergebnis: Liste { id, name, menge, prozent } oder nil (nicht entzauberbar / unbekannt)
function DE.Results(quality, ilvl, isWeapon)
    quality, ilvl = tonumber(quality), tonumber(ilvl)
    if not quality or not ilvl or ilvl < 5 then return nil end
    if quality == 2 then
        local r = row(GREEN, ilvl)
        local dustP, essP = isWeapon and 20 or 75, isWeapon and 75 or 20
        local out = { { r[2][1], r[2][2], r[3], dustP }, { r[4][1], r[4][2], r[5], essP } }
        if r[6] then out[#out + 1] = { r[6][1], r[6][2], "1", 5 } else out[1][4], out[2][4] = isWeapon and 20 or 80, isWeapon and 80 or 20 end
        table.sort(out, function(a, b) return a[4] > b[4] end)
        return out
    elseif quality == 3 then
        local r = row(BLUE, ilvl)
        local out = { { r[2][1], r[2][2], "1", ilvl > 55 and 99 or 100 } }
        if ilvl > 55 then out[2] = { NEXUS[1], NEXUS[2], "1", 1 } end
        return out
    elseif quality == 4 then
        if ilvl < 40 then return nil end
        local r = row(PURPLE, ilvl)
        return { { r[2][1], r[2][2], r[3], 100 } }
    end
    return nil
end
local NO_DE = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true, INVTYPE_BODY = true, INVTYPE_AMMO = true, [""] = true }
local function disenchantLines(tt, link, quality, lvl)
    if S().cpDisenchant == false or not quality or quality < 2 or quality > 4 or not lvl then return end
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not get then return end
    local ok, _, _, _, equipLoc, _, classID = pcall(get, link)
    if not ok or NO_DE[equipLoc or ""] or (classID ~= 2 and classID ~= 4) then return end
    local res = DE.Results(quality, lvl, classID == 2)
    if not res then return end
    -- Abstand, Ueberschrift, dann je Material: Symbol, Name in Seltenheitsfarbe, Menge grau, Chance rechts
    tt:AddLine(" ")
    tt:AddLine(L["Entzaubern ergibt"], 0.62, 0.55, 0.95)
    local QC = { [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.55, 1 }, [4] = { 0.78, 0.35, 1 } }
    for _, r in ipairs(res) do
        local nm, _, q = (C_Item and C_Item.GetItemInfo or GetItemInfo)(r[1])
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r[1])
        local c = QC[type(q) == "number" and q or 1] or QC[1]
        local pc = r[4] >= 50 and { 0.4, 0.86, 0.62 } or (r[4] >= 15 and { 0.9, 0.9, 0.9 } or { 0.6, 0.6, 0.6 })
        tt:AddDoubleLine((icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "  ") .. (nm or r[2]) .. " |cff888888x" .. r[3] .. "|r",
            r[4] .. " %", c[1], c[2], c[3], pc[1], pc[2], pc[3])
    end
end

-- /oa entzaubern: zeigt im Chat, was aus den gerade angelegten Teilen herauskaeme, und oeffnet zur Ansicht den Tooltip
-- des ersten passenden Teils (damit man die Tooltip-Zeilen auch ohne Suchen sieht)
ns.slash = ns.slash or {}
ns.slash.entzaubern = function()
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local n, firstSlot = 0, nil
    ns.print("|cff9d8cf2" .. L["Entzaubern ergibt"] .. "|r  (cpTooltip=" .. tostring(S().cpTooltip) .. ", cpDisenchant=" .. tostring(S().cpDisenchant) .. ")")
    for slot = 1, 19 do
        local link = GetInventoryItemLink and ns.safe(GetInventoryItemLink("player", slot))
        if link then
            local name, quality, ilvl = itemInfo(link)
            local lvl = itemLevel(link) or ilvl
            local ok, _, _, _, equipLoc, _, classID = pcall(get, link)
            local res = ok and not NO_DE[equipLoc or ""] and (classID == 2 or classID == 4) and DE.Results(quality, lvl, classID == 2)
            if res then
                n = n + 1
                firstSlot = firstSlot or slot
                local parts = {}
                for _, r in ipairs(res) do
                    local nm = (C_Item and C_Item.GetItemInfo or GetItemInfo)(r[1])
                    parts[#parts + 1] = (nm or r[2]) .. " x" .. r[3] .. " (" .. r[4] .. " %)"
                end
                ns.print("  " .. link .. " |cff888888" .. L["Stufe"] .. " " .. tostring(lvl) .. "|r: " .. table.concat(parts, ", "))
            end
        end
    end
    if n == 0 then ns.print("  -") return end
    -- Tooltip des ersten Teils zeigen (laeuft durch denselben Weg wie beim Ueberfahren)
    if firstSlot and GameTooltip and not ns.inCombat() then
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", firstSlot)
        GameTooltip:Show()
        ns.After(12, function() if GameTooltip:IsOwned(UIParent) then GameTooltip:Hide() end end)
    end
end

local function itemLines(tt)
    if not on("cpTooltip") or TIPM[tt] then return end
    local _, link = tt:GetItem()
    if not link or (issecretvalue and issecretvalue(link)) then return end
    TIPM[tt] = true
    local name, quality, ilvl, stack, sell = itemInfo(link)
    if not name then return end
    local id = tonumber(link:match("item:(%d+)"))
    local lvl = itemLevel(link) or ilvl
    -- beim Haendler zeigt WoW den Preis selbst
    if sell and sell > 0 and not (MerchantFrame and MerchantFrame:IsShown()) then
        local n = stackOf(tt)
        if n and n > 1 then
            tt:AddDoubleLine(L["Haendlerpreis"], money(sell * n) .. " |cff888888(" .. n .. "x " .. money(sell) .. ")|r", 0.85, 0.85, 0.85, 1, 1, 1)
        else
            tt:AddDoubleLine(L["Haendlerpreis"], money(sell), 0.85, 0.85, 0.85, 1, 1, 1)
        end
    end
    local right = {}
    if lvl and lvl > 1 then right[#right + 1] = L["Stufe"] .. " " .. lvl end
    if id then right[#right + 1] = "ID " .. id end
    if #right > 0 then tt:AddLine("|cff777777" .. table.concat(right, "  ·  ") .. "|r") end
    pcall(disenchantLines, tt, link, quality, lvl)
    tt:Show()
end
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
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt) if tt == GameTooltip or tt == ItemRefTooltip then pcall(itemLines, tt) end end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        pcall(function() local _, unit = tt:GetUnit() unitLines(tt, unit) end)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    if GameTooltip:HasScript("OnTooltipSetItem") then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) pcall(itemLines, tt) end)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) pcall(itemLines, tt) end) end
    end
    if GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(function() local _, unit = tt:GetUnit() unitLines(tt, unit) end) end)
    end
end
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function(tt) TIPM[tt] = nil end)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", function(tt) TIPM[tt] = nil end) end
end

------------------------------------------------------------------------
-- 3. Post: "Alles oeffnen" (Gold + Gegenstaende, keine Nachnahme)
------------------------------------------------------------------------
local mailRun
local function freeSlots()
    local n = 0
    if not C_Container then return 99 end
    for b = 0, 4 do
        local ok, f = pcall(C_Container.GetContainerNumFreeSlots, b)
        if ok and f then n = n + f end
    end
    return n
end
local function mailStep()
    if not mailRun or not (InboxFrame and InboxFrame:IsVisible()) then mailRun = nil return end
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    for i = math.min(n, mailRun.idx), 1, -1 do
        local _, _, _, _, m, cod, _, hasItem = GetInboxHeaderInfo(i)
        if (cod or 0) == 0 then
            if (m or 0) > 0 then
                mailRun.gold = mailRun.gold + m
                TakeInboxMoney(i)
                mailRun.idx = i
                ns.After(0.35, mailStep)
                return
            end
            if hasItem then
                if freeSlots() < 1 then
                    ns.print(L["Taschen voll - Post bleibt im Briefkasten."])
                    break
                end
                for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                    if GetInboxItem(i, a) then
                        TakeInboxItem(i, a)
                        mailRun.items = mailRun.items + 1
                        mailRun.idx = i
                        ns.After(0.45, mailStep)
                        return
                    end
                end
            end
        end
    end
    local r = mailRun
    mailRun = nil
    if CP.mailBtn then CP.mailBtn:SetLabel(L["Alles oeffnen"]) end
    ns.print((L["Post geoeffnet: %s, %d Gegenstaende"]):format(money(r.gold), r.items))
end
local function mailButton()
    if CP.mailBtn or not InboxFrame then return end
    local b = K.Button(InboxFrame, L["Alles oeffnen"], 120, 24, "primary", function(self)
        if mailRun then mailRun = nil self:SetLabel(L["Alles oeffnen"]) return end
        mailRun = { idx = 999, gold = 0, items = 0 }
        self:SetLabel(L["Stopp"])
        mailStep()
    end)
    b:SetPoint("TOP", InboxFrame, "TOP", 0, -40)
    b:SetFrameStrata("HIGH")
    CP.mailBtn = b
end
ns.On("MAIL_SHOW", function()
    -- Blizzard hat in diesem Client schon "Alle oeffnen" (OpenAllMail) -> keinen zweiten Knopf
    local blizz = _G.OpenAllMail ~= nil
    if not on("cpMail") or blizz then if CP.mailBtn then CP.mailBtn:Hide() end return end
    pcall(mailButton)
    if CP.mailBtn then CP.mailBtn:Show() end
end)
ns.On("MAIL_CLOSED", function() mailRun = nil end)

------------------------------------------------------------------------
-- 4. Munition, Reagenzien, Seelensplitter
------------------------------------------------------------------------
-- je Klasse: { Item-ID oder "ammo", Warnschwelle, Name-Schluessel }
local REAG = {
    HUNTER = { { "ammo", 200, "Munition" } },
    WARLOCK = { { 6265, 3, "Seelensplitter" } },
    MAGE = { { 17020, 5, "Arkanes Pulver" }, { 17031, 3, "Rune der Teleportation" }, { 17032, 2, "Rune der Portale" } },
    PRIEST = { { 17028, 5, "Heilige Kerze" }, { 17029, 5, "Geweihte Kerze" } },
    ROGUE = { { 5140, 5, "Blitzstrahlpulver" } },
    SHAMAN = { { 17030, 2, "Ankh" } },
    PALADIN = { { 21177, 5, "Symbol der Koenige" }, { 17033, 2, "Symbol der Goettlichkeit" } },
    DRUID = { { 17034, 3, "Ahornsamenkorn" }, { 17026, 3, "Wilder Dornwurz" } },
}
local reagLow = {}
local function reagCount(r)
    if r == "ammo" then
        local slot = GetInventorySlotInfo and select(1, pcall(GetInventorySlotInfo, "AmmoSlot")) and GetInventorySlotInfo("AmmoSlot") or 0
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if not id then return nil end
        return GetInventoryItemCount("player", slot) or 0, id
    end
    local c = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(r)) or (GetItemCount and GetItemCount(r)) or 0
    return c, r
end
function CP.Reagents()
    local _, cls = UnitClass("player")
    local out = {}
    for _, r in ipairs(REAG[cls] or {}) do
        local n, id = reagCount(r[1])
        -- nur was man benutzt: einmal gesehen (>0) = beobachten
        S().cpReagSeen = S().cpReagSeen or {}
        local key = tostring(r[1])
        if n and n > 0 then S().cpReagSeen[key] = true end
        if n and S().cpReagSeen[key] then out[#out + 1] = { key = key, n = n, min = r[2], name = L[r[3]], id = id } end
    end
    return out
end
local function reagCheck()
    if not on("cpReagents") then return end
    for _, r in ipairs(CP.Reagents()) do
        if r.n < r.min and not reagLow[r.key] then
            reagLow[r.key] = true
            K.Toast(L["Fast leer"], (L["%s: nur noch %d"]):format(r.name, r.n), C.amber or C.red)
        elseif r.n >= r.min then
            reagLow[r.key] = nil
        end
    end
end
local reagPending
ns.On("BAG_UPDATE_DELAYED", function()
    if reagPending then return end
    reagPending = true
    ns.After(1, function() reagPending = nil pcall(reagCheck) end)
end)
ns.On("MERCHANT_SHOW", function()
    if not on("cpReagents") then return end
    pcall(function()
        local low = {}
        for _, r in ipairs(CP.Reagents()) do if r.n < r.min * 3 then low[#low + 1] = r.name .. " " .. r.n end end
        if #low > 0 then K.Toast(L["Nachkaufen?"], table.concat(low, ", "), C.amber or C.accent) end
    end)
end)

------------------------------------------------------------------------
-- 5. Flugzeit (lernt die Strecken selbst)
------------------------------------------------------------------------
local flight = {}
local function nodeName(i) local ok, n = pcall(TaxiNodeName, i) return ok and n or nil end
local function currentNode()
    for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        if TaxiNodeGetType(i) == "CURRENT" then return nodeName(i) end
    end
end
function CP.FlightTime(from, to)
    local key = (from or "?") .. ">" .. (to or "?")
    local t = ns.db.flights and ns.db.flights[key]
    if t then return t end
    -- von der Gilde gelernt
    local r = ns.Store and ns.Store.Get("flights", "fl:" .. key)
    return r and not r.del and r.dur or nil
end
if TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(i)
        if not on("cpFlight") then return end
        flight = { from = currentNode(), to = nodeName(i), armed = GetTime() }
    end)
end
-- Restzeit auf der Flugkarte im Tooltip der Ziele
if TaxiNodeOnButtonEnter then
    hooksecurefunc("TaxiNodeOnButtonEnter", function(btn)
        if not on("cpFlight") or not btn or not btn.GetID then return end
        local t = CP.FlightTime(currentNode(), nodeName(btn:GetID()))
        if t then GameTooltip:AddLine("|cffaaaaaa" .. L["Flugzeit"] .. ": " .. fmtTime(t) .. "|r") GameTooltip:Show() end
    end)
end
local function flightBar()
    if CP.flightBar then return CP.flightBar end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 20)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    K.Fill(f, { 0, 0, 0, 0.55 })
    K.Border(f, { C.line[1], C.line[2], C.line[3], 0.9 })
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT", 1, -1) f.bar:SetPoint("BOTTOMLEFT", 1, 1)
    f.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
    f.text = f:CreateFontString(nil, "OVERLAY")
    if K.SetFontSafe then K.SetFontSafe(f.text, K.FONT, 11, "OUTLINE", K.FONT) else f.text:SetFont(K.FONT, 11, "OUTLINE") end
    f.text:SetPoint("CENTER")
    f:SetScript("OnUpdate", function(self, el)
        self.acc = (self.acc or 0) + el
        if self.acc < 0.25 then return end
        self.acc = 0
        if not flight.start then self:Hide() return end
        -- gelandet? (PLAYER_CONTROL_GAINED kommt manchmal, bevor der Flug offiziell vorbei ist)
        if UnitOnTaxi and not UnitOnTaxi("player") then pcall(CP.TaxiCheck) return end
        local dt = GetTime() - flight.start
        local total = CP.FlightTime(flight.from, flight.to)
        if total then
            self.bar:SetWidth(math.max(1, 218 * math.min(1, dt / total)))
            self.text:SetText((flight.to or "") .. "  " .. fmtTime(math.max(0, total - dt)))
        else
            self.bar:SetWidth(1)
            self.text:SetText((flight.to or "") .. "  |cff999999" .. L["lernt Strecke"] .. " " .. fmtTime(dt) .. "|r")
        end
    end)
    f:Hide()
    CP.flightBar = f
    return f
end
local function taxiCheck()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if onTaxi and flight.armed and not flight.start then
        flight.start = GetTime()
        -- 0.5.731: Flug merken, damit die Anzeige nach /reload weiterlaeuft (Uhrzeit statt GetTime, das nach dem Neuladen neu zaehlt)
        if ns.db then ns.db.flightNow = { from = flight.from, to = flight.to, t = time() } end
        if on("cpFlight") then flightBar():Show() end
    elseif not onTaxi and flight.start then
        local dt = GetTime() - flight.start
        if flight.from and flight.to and dt > 10 then
            ns.db.flights = ns.db.flights or {}
            local key = flight.from .. ">" .. flight.to
            ns.db.flights[key] = math.floor(dt)
            -- mit der Gilde teilen (nur wenn neu oder deutlich anders)
            local old = ns.Store and ns.Store.Get("flights", "fl:" .. key)
            if ns.Store and (not old or old.del or math.abs((old.dur or 0) - dt) > 5) then
                ns.Store.Put("flights", { id = "fl:" .. key, dur = math.floor(dt) })
            end
        end
        flight = {}
        if ns.db then ns.db.flightNow = nil end
        if CP.flightBar then CP.flightBar:Hide() end
    end
end
CP.TaxiCheck = taxiCheck
-- nach /reload mitten im Flug: Restzeit-Anzeige wiederherstellen
local function restoreFlight(final)
    local s = ns.db and ns.db.flightNow
    if flight.start or not s then return end
    if UnitOnTaxi and UnitOnTaxi("player") and time() - (s.t or 0) < 3600 then
        flight = { from = s.from, to = s.to, armed = GetTime(), start = GetTime() - (time() - (s.t or time())) }
        if on("cpFlight") then flightBar():Show() end
    elseif final and not (UnitOnTaxi and UnitOnTaxi("player")) then   -- erst beim zweiten Versuch verwerfen
        ns.db.flightNow = nil
    end
end
ns.On("PLAYER_CONTROL_LOST", function() ns.After(0.5, function() pcall(taxiCheck) end) end)
ns.On("PLAYER_CONTROL_GAINED", function() pcall(taxiCheck) ns.After(1, function() pcall(taxiCheck) end) end)
ns.On("PLAYER_ENTERING_WORLD", function()
    pcall(restoreFlight)
    pcall(taxiCheck)
    ns.After(2, function() pcall(restoreFlight, true) end)   -- UnitOnTaxi kann direkt nach dem Neuladen noch false melden
end)

------------------------------------------------------------------------
-- 6. Koordinaten (Weltkarte: Spieler + Mauszeiger, unter der Minimap)
------------------------------------------------------------------------
local function playerXY()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return x * 100, y * 100
end
local function coordText()
    local x, y = playerXY()
    return x and ("%.1f, %.1f"):format(x, y) or "--"
end
-- 0.5.531: Koordinaten zeigt WoW Forever selbst - Oasis-Anzeige entfernt (blendet nur alte Reste aus)
function CP.ApplyCoords()
    local want = false
    if Minimap and not CP.mmCoords and want then
        local f = CreateFrame("Frame", nil, Minimap)
        f:SetSize(80, 16)
        f:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
        f.text = f:CreateFontString(nil, "OVERLAY")
        if K.SetFontSafe then K.SetFontSafe(f.text, K.FONT, 11, "OUTLINE", K.FONT) else f.text:SetFont(K.FONT, 11, "OUTLINE") end
        f.text:SetPoint("CENTER")
        f:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            if self.acc < 0.2 then return end
            self.acc = 0
            self.text:SetText(coordText())
        end)
        CP.mmCoords = f
    end
    if CP.mmCoords then CP.mmCoords:SetShown(want) end
    -- 0.5.522: Weltkarte zeigt Forever selbst (worldMapShowPlayerCoords / worldMapShowCursorCoords)
    if CP.wmCoords then CP.wmCoords:Hide() end
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
-- Daten: ns.MapRevealData[uiMapID] = { "w:h:x:y:tex1,tex2,...", ... } (Modules/MapRevealData.lua)
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
    pcall(CP.UpdateXP)
    pcall(CP.ApplyCoords)
    pcall(CP.ApplyChat)
    pcall(hookReveal)
    pcall(revealRefresh)
    pcall(reagCheck)
end

------------------------------------------------------------------------
-- 10. Suche (Kraeuter/Erz/Schatz/Wildtiere ...) nach dem Tod wieder an
-- Automatisch zaubern darf ein Addon nicht (geschuetzt + GCD) -> ein Knopf erscheint, ein Klick reicht.
------------------------------------------------------------------------
local TRACK = { [2383] = true, [2580] = true, [2481] = true, [1494] = true, [19883] = true, [19884] = true, [19885] = true,
    [19880] = true, [19878] = true, [19882] = true, [19879] = true, [5225] = true, [5500] = true, [5502] = true }
ns.Listen("LOGIN", function()
    if S().cpTrackInit == nil then
        S().cpTrackInit = true
        if S().cpTracking == nil then S().cpTracking = true end
    end
end)
local function trackingActive()
    if GetTrackingTexture then
        local ok, t = pcall(GetTrackingTexture)
        if ok then return t ~= nil end
    end
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
            if ok and type(info) == "table" and info.active and info.spellID and TRACK[info.spellID] then return true end
        end
        return false
    end
    return false
end
local function trackButton()
    if CP.trackBtn then return CP.trackBtn end
    local b = CreateFrame("Button", "OasisTrackButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(250, 40)
    b:SetPoint("TOP", UIParent, "TOP", 0, -160)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp", "AnyDown")
    K.Fill(b, { 0.04, 0.04, 0.05, 0.92 })
    K.Border(b, C.accent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("LEFT", 5, 0)
    b.text = K.Text(b, 12, C.text)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("LEFT")
    b:HookScript("PostClick", function(self) if not InCombatLockdown() then self:Hide() end end)
    b:Hide()
    CP.trackBtn = b
    return b
end
-- 0.5.661: zuletzt benutzte Suche JE CHARAKTER (vorher accountweit -> Magier ohne Kraeuterkunde bekam den
-- Kraeuter-Knopf eines Twinks) und nur, wenn der Charakter den Zauber auch kennt
local function knows(id)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, id) if ok then return r and true or false end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, id) if ok then return r and true or false end end
    return true
end
local function offerTracking()
    if not on("cpTracking") or InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    local id = ns.char and ns.char.trackSpell
    if not id or not knows(id) or trackingActive() then return end
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then name, icon = info.name, info.iconID end
    elseif C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(id)
        icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    elseif GetSpellInfo then
        local n, _, ic = GetSpellInfo(id)
        name, icon = n, ic
    end
    if not name then return end
    local b = trackButton()
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", name)
    b.icon:SetTexture(icon)
    b.text:SetText((L["Klick: %s wieder an"]):format(name))
    b:Show()
    -- nach einer Minute von selbst weg
    ns.After(60, function() if CP.trackBtn and CP.trackBtn:IsShown() and not InCombatLockdown() then CP.trackBtn:Hide() end end)
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or ns.inCombat() or type(spellID) ~= "number" then return end
    if TRACK[spellID] then
        if ns.char then ns.char.trackSpell = spellID end
        if CP.trackBtn and CP.trackBtn:IsShown() then CP.trackBtn:Hide() end
    end
end)
ns.On("PLAYER_UNGHOST", function() ns.After(1.5, function() pcall(offerTracking) end) end)
ns.On("PLAYER_ALIVE", function() ns.After(1.5, function() pcall(offerTracking) end) end)

------------------------------------------------------------------------
-- Einstellungen: eigener Reiter "Helfer"
------------------------------------------------------------------------
local OPTS = {
    { "Unterwegs", {
        { "cpXP", "Erfahrung pro Stunde und Zeit bis zum Level", "Mit Ruhebonus. Leiste unten, Shift + Ziehen verschiebt sie.", CP.UpdateXP },
        { "cpXPShare", "Bald-Level-10er der Gilde melden", "Einmal \"Noch ~40 Min bis Level 30\" in den Gildenchat" },
        { "cpReagents", "Munition, Reagenzien und Seelensplitter", "Warnt, wenn es knapp wird, und erinnert beim Haendler", reagCheck },
        { "cpFlight", "Flugzeit anzeigen", "Restzeit beim Fliegen - Oasis lernt jede Strecke beim ersten Flug" },
        { "cpTracking", "Suche nach dem Tod wieder an", "Kraeuter-, Erz- oder Wildtiersuche: nach der Wiederbelebung erscheint ein Knopf - ein Klick schaltet sie wieder ein" },
    } },
    { "Tooltip, Post & Chat", {
        { "cpTooltip", "Tooltip: Haendlerpreis, Stufe und ID", "Preis auch fuer den ganzen Stapel" },
        { "fojjiBridge", "Mit FojjiCore zusammenarbeiten", "Ist FojjiCore installiert, oeffnet Oasis dessen Dungeon-Journal und kann dessen Wunschliste uebernehmen" },
        { "cpQuestReward", "Questbelohnung: beste Wahl markieren", "Markiert bei mehreren Belohnungen das Upgrade - sonst das Teil mit dem besten Haendlerpreis" },
        { "cpDisenchant", "Tooltip: Entzaubern ergibt ...", "Zeigt bei gruenen, blauen und epischen Teilen, welche Materialien beim Entzaubern herauskommen koennen" },
        { "cpTooltipGuild", "Tooltip: Gildeninfos", "Oasis-Rang, Twink von ... und Berufe bei Gildenmitgliedern" },
        { "cpInspect", "Gegenstandsstufe beim Betrachten", "Im Betrachten-Fenster und danach im Tooltip, mit Vergleich zu dir" },
        { "cpMail", "Post: Knopf \"Alles oeffnen\"", "Holt Gold und Gegenstaende aus allen Briefen (keine Nachnahme)" },
        { "cpChatLinks", "Chat: Links kopieren, Klassenfarben", "Links anklicken = Kopierfenster. Uhrzeit im Chat: Blizzards Chat-Einstellung (Zeitstempel).", CP.ApplyChat },
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
    local ovb = K.Button(body, L["Charaktere & Helfer - Uebersicht"], 260, 26, "primary", function()
        if ns.Helpers2 then ns.Helpers2.Overview() end
    end)
    ovb:SetPoint("TOPLEFT", 0, 0)
    if H.note then H.note(body, L["Gold, Ruhestein, Instanz-IDs, Gilden-Abklingzeiten, Sets und Angel-Statistik (/oa chars)"], 272, -6, 480) end
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

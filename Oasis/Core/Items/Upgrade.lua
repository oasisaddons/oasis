-- Oasis: upgrade arrow (like Pawn) - is an item better for you than what you are wearing?
-- Score = sum (value x weight) by class and role; compared with the worn item in the
-- same slot (for rings/trinkets/one-hand the weaker of the two). Display only.
-- Role: from your Oasis group roles (healer > tank > damage), changeable under Groups.
local ADDON, ns = ...
local BADGE = setmetatable({}, { __mode = "k" })  -- Arrow texture per bag button (no fields on Blizzard's item buttons)
local L = ns.L
local K, C = ns.K, ns.K.C

local UP = {}
ns.Upgrade = UP

-- Stats in the item -> short name (substring of the Blizzard key)
local STAT = {
    { "STRENGTH", "str" }, { "AGILITY", "agi" }, { "STAMINA", "sta" }, { "INTELLECT", "int" }, { "SPIRIT", "spi" },
    { "RANGED_ATTACK_POWER", "rap" }, { "ATTACK_POWER", "ap" },
    { "SPELL_HEALING", "heal" }, { "HEALING", "heal" }, { "SPELL_DAMAGE", "sp" }, { "SPELL_POWER", "sp" },
    { "SPELL_CRIT", "scrit" }, { "SPELL_HIT", "shit" }, { "CRIT", "crit" }, { "HIT", "hit" },
    { "MANA_REGENERATION", "mp5" }, { "POWER_REGEN0", "mp5" },
    { "DEFENSE", "def" }, { "DODGE", "dodge" }, { "PARRY", "parry" }, { "BLOCK", "block" },
    { "DAMAGE_PER_SECOND", "dps" }, { "RESISTANCE0", "armor" },
}
local W = {
    tank   = { sta = 1.5, str = 1.0, agi = 1.0, def = 1.5, dodge = 12, parry = 12, block = 6, armor = 0.06, hit = 8, ap = 0.3, dps = 2 },
    melee  = { str = 2.0, agi = 1.5, ap = 1.0, crit = 14, hit = 14, sta = 0.3, dps = 7 },
    agile  = { agi = 2.0, str = 1.0, ap = 1.0, crit = 14, hit = 14, sta = 0.3, dps = 7 },
    ranged = { agi = 2.0, rap = 1.0, ap = 0.8, int = 0.3, crit = 14, hit = 14, sta = 0.3, dps = 7 },
    caster = { int = 0.8, spi = 0.2, sp = 1.0, scrit = 12, shit = 12, crit = 6, sta = 0.3 },
    healer = { int = 1.0, spi = 0.6, heal = 1.0, sp = 0.4, mp5 = 2.2, scrit = 8, sta = 0.3 },
}
local CASTER = { MAGE = true, WARLOCK = true }
local AGILE = { ROGUE = true, DRUID = true }

function UP.Role()
    local _, cls = UnitClass("player")
    local r = ns.Groups and ns.Groups.MyRoles and ns.Groups.MyRoles() or {}
    if r.heal and not (r.dps and CASTER[cls]) and cls ~= "WARRIOR" and cls ~= "ROGUE" and cls ~= "HUNTER" and cls ~= "MAGE" and cls ~= "WARLOCK" then return "healer", L["Healer"] end
    if r.tank and (cls == "WARRIOR" or cls == "DRUID" or cls == "PALADIN") and not r.dps then return "tank", L["Tank"] end
    if cls == "HUNTER" then return "ranged", L["Ranged"] end
    if CASTER[cls] or cls == "PRIEST" then return "caster", L["Spells"] end
    if cls == "SHAMAN" and not r.tank then return (r.heal and "healer" or "melee"), (r.heal and L["Healer"] or L["Melee"]) end
    if AGILE[cls] then return "agile", L["Melee"] end
    if cls == "WARRIOR" and r.tank and not r.dps then return "tank", L["Tank"] end
    return "melee", L["Melee"]
end

-- Rating per 1 % (crit/hit/dodge ...): newer clients return "..._RATING" instead of percent.
-- Rule of thumb as in Classic/TBC: 14 rating = 1 % at level 60, linearly less below (min. 1).
-- Previously ratings were weighted like percent: 14 crit rating = 14 x 14 = 196 points -> "+854 %".
function UP.RatingPerPct()
    local lvl = tonumber(ns.safe and ns.safe(UnitLevel("player")) or UnitLevel("player")) or 60
    return math.max(1, 14 * math.max(10, lvl) / 60)
end
local PCT_STAT = { crit = true, hit = true, scrit = true, shit = true, dodge = true, parry = true, block = true }
local function statsOf(link)
    local ok, t = pcall(C_Item.GetItemStats, link)
    if not ok or type(t) ~= "table" then return {} end
    local out = {}
    local rpp
    for k, v in pairs(t) do
        for _, s in ipairs(STAT) do
            if k:find(s[1], 1, true) then
                local n = tonumber(v) or 0
                if PCT_STAT[s[2]] and k:find("_RATING", 1, true) then
                    rpp = rpp or UP.RatingPerPct()
                    n = n / rpp
                elseif s[2] == "def" and k:find("_RATING", 1, true) then
                    n = n / 1.5
                end
                out[s[2]] = (out[s[2]] or 0) + n
                break
            end
        end
    end
    return out
end
-- Average value per occupied equipment slot (without shirt/tabard), cached for 3 s
local avgCache = {}
function UP.AvgSlotScore(role)
    role = role or UP.Role()
    local c = avgCache[role]
    if c and GetTime() - c.t < 3 then return c.v end
    local sum, n = 0, 0
    for s = 1, 18 do
        if s ~= 4 then
            local l = GetInventoryItemLink("player", s)
            if l then sum = sum + (UP.Score(l, role) or 0) n = n + 1 end
        end
    end
    local v = n > 0 and sum / n or 0
    avgCache[role] = { t = GetTime(), v = v }
    return v
end
function UP.Score(link, role)
    if not link then return 0 end
    local w = W[role or UP.Role()] or W.melee
    local s = 0
    for k, v in pairs(statsOf(link)) do s = s + v * (w[k] or 0) end
    return s
end

-- Slots per equip location
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
-- Armor type the class can wear (1 cloth, 2 leather, 3 mail, 4 plate)
local ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, MAGE = 1, WARLOCK = 1, PRIEST = 1 }
-- Weapon types per class (Classic, weapon subclasses)
local WEAP = {
    WARRIOR = { [0] = 1, 1, 2, 3, 4, 5, 6, 7, 8, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PALADIN = { [0] = 1, 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
    HUNTER = { [0] = 1, 1, 2, 3, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    ROGUE = { [0] = 1, [2] = 1, [3] = 1, [4] = 1, [7] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
    PRIEST = { [4] = 1, [10] = 1, [15] = 1, [19] = 1 }, SHAMAN = { [0] = 1, 1, [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
    MAGE = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 }, WARLOCK = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
    DRUID = { [4] = 1, [5] = 1, [6] = 1, [10] = 1, [13] = 1, [15] = 1 },
}
local SHIELD_OK = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- WoW Forever instead of Classic: the game itself says what your own character can wear
-- (weapon/armor skills are spells). The tables above only if the game says nothing.
local PROF_ARMOR = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 }   -- Cloth, leather, mail, plate, shield
local PROF_WEAP = { [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200, [7] = 201, [8] = 202,
    [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011, [19] = 5009 }
local WKEY = { [0] = "axe1", [1] = "axe2", [2] = "bow", [3] = "gun", [4] = "mace1", [5] = "mace2", [6] = "polearm",
    [7] = "sword1", [8] = "sword2", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown", [18] = "xbow" }
-- Fishing (20) and "Miscellaneous" (14, e.g. tools) can be equipped by every class
local ANY_CLASS_WEAP = { [14] = true, [20] = true }
local function knowsSpell(id)
    if not id or not IsPlayerSpell then return nil end
    local ok, r = pcall(IsPlayerSpell, id)
    if not ok then return nil end
    return ns.safe(r) and true or false
end
-- Weapon learnable for a class? First what the guild read at the weapon master, otherwise Classic
local function weaponOk(cls, subID)
    local k = WKEY[subID]
    if k and ns.Weapons and ns.Weapons.ClassCan then
        if ns.Weapons.ClassCan(cls)[k] then return true end
    end
    return WEAP[cls] and WEAP[cls][subID] ~= nil or false
end
UP.WeaponOk = weaponOk
-- 0.5.942: not learned yet? The client colors the slot/type line red in the tooltip ("Two-Hand   Axe") if you
-- can't equip the item (yet) - e.g. two-handed axe as paladin before the weapon master. The class table only says
-- whether you CAN learn it. Result remembered per link for 30 s.
local function isRed(c) return type(c) == "table" and (c.r or 0) > 0.9 and (c.g or 1) < 0.3 and (c.b or 1) < 0.3 end
local unlearnedCache = {}
function UP.Unlearned(link)
    if not link or not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return false end
    local now = GetTime and GetTime() or 0
    local c = unlearnedCache[link]
    if c and now - c.t < 30 then return c.v end
    local res = false
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    local slotName = ok and loc and loc ~= "" and _G[loc]
    local okT, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if slotName and okT and type(data) == "table" and type(data.lines) == "table" then
        for i, line in ipairs(data.lines) do
            if i > 8 then break end
            if not line.leftText and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
            if ns.safe(line.leftText) == slotName then
                res = isRed(line.leftColor) or isRed(line.rightColor) or false
                break
            end
        end
    end
    unlearnedCache[link] = { t = now, v = res }
    return res
end
ns.Listen("LOGIN", function()
    -- newly learned (weapon master, level 40): discard the cache
    for _, ev in ipairs({ "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP" }) do
        pcall(ns.On, ev, function() unlearnedCache = {} end)
    end
end)
local function canWear(link)
    local ok, _, _, _, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return true end
    if UP.Unlearned(link) then return false end
    local _, cls0 = UnitClass("player")
    if classID == 2 and subID then
        if ANY_CLASS_WEAP[subID] then return true end
        if knowsSpell(PROF_WEAP[subID]) then return true end
        return weaponOk(cls0, subID)
    end
    if classID == 4 and PROF_ARMOR[subID] and loc ~= "INVTYPE_CLOAK" then
        local k = knowsSpell(PROF_ARMOR[subID])
        if k ~= nil then return k end
    end
    if classID == 4 and subID == 6 then return SHIELD_OK[cls0] or false end
    if classID ~= 4 or not subID or subID < 1 or subID > 4 then return true end
    if loc == "INVTYPE_CLOAK" then return true end
    local _, cls = UnitClass("player")
    local max = ARMOR[cls] or 4
    local lvl = ns.safe(UnitLevel("player")) or 60
    if lvl < 40 and (cls == "WARRIOR" or cls == "PALADIN" or cls == "HUNTER" or cls == "SHAMAN") then max = max - 1 end
    return subID <= max
end

-- Public (e.g. GearMatch): slots per equip location + wearability for ANOTHER class/level
UP.SLOTS = SLOTS
function UP.CanWearFor(link, cls, lvl)
    local ok, _, _, _, loc, _, classID, subID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok or not cls then return true end
    if classID == 2 and subID and ANY_CLASS_WEAP[subID] then return true end
    if classID == 2 and subID and WEAP[cls] then return weaponOk(cls, subID) end
    if classID == 4 and subID == 6 then return SHIELD_OK[cls] or false end
    if classID ~= 4 or not subID or subID < 1 or subID > 4 then return true end
    if loc == "INVTYPE_CLOAK" then return true end
    local max = ARMOR[cls] or 4
    if (tonumber(lvl) or 60) < 40 and (cls == "WARRIOR" or cls == "PALADIN" or cls == "HUNTER" or cls == "SHAMAN") then max = max - 1 end
    return subID <= max
end

-- Detailed comparison: ONE result for arrow, tooltip line and comparison window (so that band,
-- "instead of ..." line and stat table never contradict each other).
-- Returns nil = not an equipment item, otherwise a table:
--   pct      percent (+ better / - worse), nil = not ratable
--   against  list of worn items being compared against ({} = empty slot)
--   worn     true = exactly this item is being worn
--   useless  true = score for your own role is 0 ("stats do nothing for your role")
--   vs2H     true = off hand/shield against a worn two-handed weapon
--   blocked  true = not wearable for your own class
function UP.CompareInfo(link)
    if not link or not tostring(link):find("item:") then return nil end
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return nil end
    local slots = SLOTS[loc or ""]
    if not slots then return nil end
    local role, roleName = UP.Role()
    local info = { role = role, roleName = roleName, loc = loc, against = {} }
    if not canWear(link) then info.blocked = true end
    local function inv(slot) return GetInventoryItemLink("player", slot) end
    local mhLink, ohLink = inv(16), inv(17)
    if mhLink == link or ohLink == link then info.worn = true info.pct = 0 return info end
    local mhLoc = mhLink and select(4, C_Item.GetItemInfoInstant(mhLink))
    local mh2H = mhLoc == "INVTYPE_2HWEAPON"
    if loc == "INVTYPE_2HWEAPON" then
        -- Two-hand replaces main AND off hand
        info.against = { mhLink, ohLink }
    elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
        -- One-hand against the main hand; when wearing a two-hander, the (empty) off hand does not count
        info.against = { mhLink }
    elseif loc == "INVTYPE_WEAPONOFFHAND" or loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE" then
        -- Off hand while wearing a two-hander: you would have to remove the two-hander -> compare honestly with it
        if mh2H then info.against = { mhLink } info.vs2H = true else info.against = { ohLink } end
    else
        local best, bs
        for _, s in ipairs(slots) do
            local l = inv(s)
            if l == link then info.worn = true info.pct = 0 return info end
            local sc = l and UP.Score(l, role) or -1
            if not bs or sc < bs then best, bs = l, sc end
            if not l then break end
        end
        info.against = { best }
    end
    local old = 0
    for _, l in pairs(info.against) do old = old + (UP.Score(l, role) or 0) end
    local new = UP.Score(link, role)
    info.new, info.old = new, old
    -- (almost) worthless for the role, e.g. shield with only 1 stamina for melee: don't show as -100 %
    if new <= 0 or new < UP.AvgSlotScore(role) * 0.05 then
        info.useless = true
        -- 0.5.880: still rank items without role stats (e.g. pure armor) - sum of all stats against the worn one.
        -- Otherwise every arrow was missing in the bags, although 31 armor on an empty slot is clearly better.
        local function rawSum(l)
            local n = 0
            if l and C_Item and C_Item.GetItemStats then
                local okS, t = pcall(C_Item.GetItemStats, l)
                if okS and type(t) == "table" then for _, v in pairs(t) do v = tonumber(v) if v and v > 0 then n = n + v end end end
            end
            return n
        end
        local sn, sc = rawSum(link), 0
        for _, l in pairs(info.against) do sc = sc + rawSum(l) end
        local base = math.max(sn, sc)
        if base > 0 and old <= 0 then
            -- only if the worn item does nothing for the role either (otherwise an item with role stats would always be better)
            info.rawPct = math.max(-100, math.min(100, math.floor((sn - sc) / base * 100 + (sn >= sc and 0.5 or -0.5))))
        elseif base > 0 then
            info.rawPct = -100
        end
        return info
    end
    if info.blocked then return info end
    -- Realistic percent: don't just compare against the (possibly almost worthless) old item, but at least
    -- against the average value of a slot of the whole equipment (otherwise +900 % for 3 strength)
    -- Base = the larger of the two items (at least the average of a slot) -> always between -100 and +100 %,
    -- never divide by (almost) 0
    local avg = UP.AvgSlotScore(role)
    local base = math.max(old, new, avg, 1)
    info.pct = math.max(-100, math.min(100, math.floor((new - old) / base * 100 + 0.5)))
    return info
end
-- Comparison: percent (+ better, - worse), nil = not comparable (not wearable / worthless for the role)
function UP.Compare(link)
    local i = UP.CompareInfo(link)
    if not i or i.blocked then return nil end
    -- only report real upgrades; worse items without role stats stay without an arrow as before (otherwise red arrows on every piece of junk)
    if i.useless then return (i.rawPct and i.rawPct > 0) and i.rawPct or nil, i.roleName end
    return i.pct, i.roleName
end
function UP.Text(link)
    local pct, role = UP.Compare(link)
    if not pct or pct == 0 then return nil end
    if pct > 0 then return "|TInterface\\Buttons\\Arrow-Up-Up:12:12|t |cff66db9e" .. (L["Improvement +%d%%"]):format(math.min(pct, 999)) .. "|r", role end
    return "|TInterface\\Buttons\\Arrow-Down-Up:12:12|t |cffe06060" .. (L["worse %d%%"]):format(pct) .. "|r", role
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if ns.db and ns.db.settings.upgradeTipOff then return end
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local ok, _, link = pcall(tt.GetItem, tt)
        if not ok or not link then return end
        local t, role = UP.Text(link)
        if t then tt:AddLine(t .. "  |cff777777(" .. (role or "") .. ")|r") end
    end)
end

------------------------------------------------------------------------
-- Arrow directly on the item icon (bags, Oasis loot window):
-- green up = upgrade (top right), red down = worse (bottom right)
-- Turn off: Settings > Convenience > "Keine Verbesserungs-Pfeile auf Items"
------------------------------------------------------------------------
local function iconOn() return not (ns.db and ns.db.settings.upgradeIconOff) end
function UP.Badge(btn, link)
    if not btn then return end
    local pct = iconOn() and link and UP.Compare(link)
    if not BADGE[btn] then
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(14, 14)
        BADGE[btn] = t
    end
    local t = BADGE[btn]
    if not pct or pct == 0 then t:Hide() return end
    t:ClearAllPoints()
    if pct > 0 then
        t:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        t:SetVertexColor(0.3, 1, 0.4)
        t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, 1)
    else
        t:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        t:SetVertexColor(1, 0.3, 0.3)
        t:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    end
    t:Show()
end
local function bagFrames()
    local out = {}
    if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, 13 do local f = _G["ContainerFrame" .. i] if f then out[#out + 1] = f end end
    return out
end
function UP.UpdateBags()
    for _, f in ipairs(bagFrames()) do
        if f:IsShown() and f.EnumerateValidItems then
            for _, btn in f:EnumerateValidItems() do
                local bag = btn.GetBagID and btn:GetBagID()
                local slot = btn.GetID and btn:GetID()
                local link = bag and slot and C_Container.GetContainerItemLink(bag, slot)
                pcall(UP.Badge, btn, link)
            end
        end
    end
end
local pend
local function soon()
    if pend then return end
    pend = true
    C_Timer.After(0.2, function() pend = nil pcall(UP.UpdateBags) end)
end
ns.On("BAG_UPDATE_DELAYED", soon)
ns.On("PLAYER_EQUIPMENT_CHANGED", soon)
ns.On("GET_ITEM_INFO_RECEIVED", soon)
ns.Listen("LOGIN", function()
    for _, f in ipairs(bagFrames()) do f:HookScript("OnShow", soon) end
    if ContainerFrame_UpdateAll then hooksecurefunc("ContainerFrame_UpdateAll", soon) end
end)
UP.RefreshBadges = soon

------------------------------------------------------------------------
-- Public helpers (e.g. dungeon loot): comparison by item ID, compared item, glow frame
------------------------------------------------------------------------
local function asLink(item)
    if type(item) == "number" then
        local ok, _, link = pcall(C_Item.GetItemInfo, item)
        return (ok and link) or ("item:" .. item)
    end
    return item
end
-- Percent (+ better) like UP.Compare, but also with a plain item ID
function UP.ForItem(item)
    if not item then return nil end
    local ok, pct, role = pcall(UP.Compare, asLink(item))
    if ok then return pct, role end
end
-- Which worn item is it compared with? (link or nil) - same logic as UP.Compare
function UP.Against(item)
    local link = asLink(item)
    if not link then return nil end
    local ok, i = pcall(UP.CompareInfo, link)
    if not ok or not i or i.worn then return nil end
    return i.against[1]
end
-- Green pulsing glow frame + arrow around an item icon (pct > 0 = show, otherwise hide)
function UP.Glow(f, pct, still)
    if not f then return end
    local g = f.oasisGlow
    if not pct or pct <= 0 then if g then g:Hide() end return end
    if not g then
        g = CreateFrame("Frame", nil, f)
        f.oasisGlow = g
        g:SetAllPoints()
        g:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
        g.halo = g:CreateTexture(nil, "OVERLAY")
        g.halo:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        g.halo:SetBlendMode("ADD")
        g.halo:SetPoint("CENTER", f, "CENTER", 0, 0)
        g.halo:SetVertexColor(0.3, 1, 0.45)
        g.edge = {}
        for i = 1, 4 do
            local t = g:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(0.35, 1, 0.5, 0.9)
            g.edge[i] = t
        end
        g.edge[1]:SetPoint("TOPLEFT") g.edge[1]:SetPoint("TOPRIGHT") g.edge[1]:SetHeight(1)
        g.edge[2]:SetPoint("BOTTOMLEFT") g.edge[2]:SetPoint("BOTTOMRIGHT") g.edge[2]:SetHeight(1)
        g.edge[3]:SetPoint("TOPLEFT") g.edge[3]:SetPoint("BOTTOMLEFT") g.edge[3]:SetWidth(1)
        g.edge[4]:SetPoint("TOPRIGHT") g.edge[4]:SetPoint("BOTTOMRIGHT") g.edge[4]:SetWidth(1)
        g.arrow = g:CreateTexture(nil, "OVERLAY", nil, 3)
        g.arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        g.arrow:SetSize(12, 12)
        g.arrow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 3, 3)
        g.arrow:SetVertexColor(0.3, 1, 0.4)
        g.t = 0
        g:SetScript("OnUpdate", function(self, el)
            if self.still then return end
            self.t = (self.t or 0) + (el or 0)
            local a = 0.5 + 0.5 * math.sin(self.t * 3.2)
            self.halo:SetAlpha(0.35 + 0.55 * a)
            for _, e in ipairs(self.edge) do e:SetAlpha(0.45 + 0.55 * a) end
        end)
    end
    local w = f:GetWidth() or 30
    g.halo:SetSize(w * 1.9, w * 1.9)
    g.still = still or (ns.db and ns.db.settings and ns.db.settings.noAnim) or false
    if g.still then
        g.halo:SetAlpha(0.7)
        for _, e in ipairs(g.edge) do e:SetAlpha(0.9) end
    end
    g:Show()
end

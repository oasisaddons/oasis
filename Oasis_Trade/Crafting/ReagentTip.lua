-- Oasis: "Wofuer ist das?" - unter Materialien im Item-Tooltip: in welchen Rezepten der Gilde sie stecken
-- Quellen: Rezeptlisten der Gilde (ns.db.recipes, per Abgleich), Material je Rezept (ns.db.reagents:
-- eigene Berufs-Scans, fehlende im Hintergrund ueber C_TradeSkillUI.GetRecipeSchematic nachgeladen).
-- Tooltip-Abfrage ist nur ein Tabellenzugriff; der Index wird im Hintergrund (ausserhalb des Kampfes) gebaut.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Crafting", function()   -- Modul Handwerk (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L

local RT = {}
ns.ReagentTip = RT

local index = {}          -- [reagentItemID] = { { rid, name, crafters = { name, ... } }, ... }
local built = false

local function on() return ns.db and ns.db.settings.tipReagent ~= false end

-- Material eines Rezepts: "itemID:menge,itemID:menge"
local function reagentsOf(rid)
    return ns.db.reagents and ns.db.reagents[rid]
end

function RT.Build()
    local byRecipe = {}
    for who, rec in pairs(ns.db.recipes or {}) do
        for _, list in pairs(type(rec) == "table" and rec.profs or {}) do
            for rid, val in pairs(list) do
                rid = tonumber(rid)
                if rid then
                    local e = byRecipe[rid]
                    if not e then
                        e = { rid = rid, name = tostring(val):match("^(.-)@") or tostring(val), crafters = {} }
                        byRecipe[rid] = e
                    end
                    if #e.crafters < 12 then e.crafters[#e.crafters + 1] = who end
                end
            end
        end
    end
    local idx = {}
    for rid, e in pairs(byRecipe) do
        local r = reagentsOf(rid)
        if r then
            for id in r:gmatch("(%d+):%d+") do
                id = tonumber(id)
                local l = idx[id]
                if not l then l = {} idx[id] = l end
                l[#l + 1] = e
            end
        end
    end
    for _, l in pairs(idx) do table.sort(l, function(a, b) return a.name < b.name end) end
    index, built = idx, true
    return byRecipe
end

-- fehlendes Material im Hintergrund nachladen (gedrosselt, nie im Kampf)
local queue, ticker = {}, nil
local function fill()
    local byRecipe = RT.Build()
    queue = {}
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return end
    for rid in pairs(byRecipe) do if not reagentsOf(rid) then queue[#queue + 1] = rid end end
    if #queue == 0 or ticker then return end
    local i, got = 0, 0
    ticker = C_Timer.NewTicker(1, function()
        if ns.inCombat() then return end
        for _ = 1, 20 do
            i = i + 1
            local rid = queue[i]
            if not rid then
                ticker:Cancel() ticker = nil
                if got > 0 then RT.Build() end
                return
            end
            local ok, sch = pcall(T.GetRecipeSchematic, rid, false)
            if ok and type(sch) == "table" then
                local parts = {}
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    local r = slot.reagents and slot.reagents[1]
                    local need = ns.safe(slot.quantityRequired) or 0
                    if r and r.itemID and need > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
                        parts[#parts + 1] = r.itemID .. ":" .. need
                    end
                end
                if #parts > 0 then
                    ns.db.reagents = ns.db.reagents or {}
                    ns.db.reagents[rid] = table.concat(parts, ",")
                    got = got + 1
                end
            end
        end
    end)
end
ns.Listen("LOGIN", function() ns.After(40, function() pcall(fill) end) end)
-- neue Rezeptlisten aus der Gilde: hoechstens alle 5 Minuten neu einordnen
local lastFill = 0
ns.Listen("SYNCED", function()
    if GetTime() - lastFill < 300 then return end
    lastFill = GetTime()
    ns.After(10, function() pcall(fill) end)
end)
C_Timer.NewTicker(600, function() if not ns.inCombat() and not ticker then pcall(fill) end end)

function RT.For(itemID) return built and index[itemID] or nil end

local function tipLine(tt, id)
    if not (id and on()) then return end
    local l = RT.For(id)
    if not l or #l == 0 then return end
    if IsShiftKeyDown() then
        tt:AddLine("|cffff1200Oasis|r  " .. (L["Reagent for %d guild recipes:"]):format(#l), 0.85, 0.85, 0.85)
        for i = 1, math.min(10, #l) do
            local e = l[i]
            local who = {}
            for j = 1, math.min(3, #e.crafters) do who[#who + 1] = ns.displayName(e.crafters[j]) end
            if #e.crafters > 3 then who[#who + 1] = "+" .. (#e.crafters - 3) end
            tt:AddDoubleLine("  " .. e.name, table.concat(who, ", "), 0.9, 0.9, 0.9, 0.55, 0.55, 0.6)
        end
        if #l > 10 then tt:AddLine("  " .. (L["... and %d more"]):format(#l - 10), 0.55, 0.55, 0.6) end
        return
    end
    local names = {}
    for i = 1, math.min(3, #l) do names[#names + 1] = l[i].name end
    local more = #l > 3 and (" +" .. (#l - 3)) or ""
    tt:AddLine("|cffff1200Oasis|r  " .. (L["Reagent for %d recipes:"]):format(#l) .. " " .. table.concat(names, ", ") .. more
        .. "  |cff777777" .. L["(Shift: all)"] .. "|r", 0.85, 0.85, 0.85, true)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local id = data and ns.safe(data.id)
        pcall(tipLine, tt, id)
    end)
end
RT.TipLine = tipLine
end)

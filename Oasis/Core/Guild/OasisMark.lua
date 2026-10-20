-- Oasis - subtle marker: players Oasis knows to use the addon (guild, group) get a small line
-- in their tooltip. No Oasis mark is inserted into chat anymore.
local ADDON, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local function S() return ns.db and ns.db.settings end
local ICON = "|T" .. ns.MEDIA .. "logo64:11:11:0:0|t"

-- known as Oasis user: own name or an entry from the guild sync (version known, not a demo entry)
local function isUser(name)
    name = ns.safe(name)
    if type(name) ~= "string" or name == "" or issecret(name) then return false end
    if ns.isMe(name) then return true end
    local m = ns.db and ns.db.members
    if not m then return false end
    local p = m[ns.fullName(name)] or m[name]
    return type(p) == "table" and p.v ~= nil and not p.demo
end
ns.IsOasisUser = isUser

-- Tooltip: "Oasis" line below the player
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip or (S() and S().oasisMark == false) or ns.inCombat() then return end
        local ok, _, unit = pcall(tt.GetUnit, tt)
        if not ok or not unit or issecret(unit) then return end
        if not UnitIsPlayer(unit) then return end
        local name, realm = ns.UnitName(unit)
        if issecret(name) or not name then return end
        if isUser((realm and realm ~= "") and (name .. "-" .. realm) or name) then
            tt:AddLine(ICON .. " |cff8f8fb0Oasis|r")
        end
    end)
end


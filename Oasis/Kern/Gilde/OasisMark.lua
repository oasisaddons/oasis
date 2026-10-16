-- Oasis - dezente Markierung: Spieler, von denen Oasis weiss, dass sie das Addon nutzen (Gilde, Gruppe), bekommen im Tooltip
-- eine kleine Zeile. Im Chat wird kein Oasis-Zeichen mehr eingefuegt.
local ADDON, ns = ...
local L = ns.L

local issecret = issecretvalue or function() return false end
local function S() return ns.db and ns.db.settings end
local ICON = "|T" .. ns.MEDIA .. "logo64:11:11:0:0|t"

-- bekannt als Oasis-Nutzer: eigener Name oder ein Eintrag aus dem Gilden-Abgleich (Version bekannt, kein Demo-Eintrag)
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

-- Tooltip: Zeile "Oasis" unter dem Spieler
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


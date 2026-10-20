-- Oasis - Texte: Neu seit letztem Besuch (Core\Guild\NewSince.lua) und Leuchten (UI\Main.lua)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["1 neu seit deinem letzten Besuch"] = "1 new since your last visit",
    ["%d neu seit deinem letzten Besuch"] = "%d new since your last visit",
    ["Neuigkeiten: %s"] = "New: %s",
}
for k, v in pairs(ENC) do if EN[k] == nil then EN[k] = v end end

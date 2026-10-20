-- Oasis: zone and level in chat (0.6.521)
-- Before guild, officer, party and raid lines the speaker's "[23 Barrens]" appears in small text.
-- Source: guild roster (Blizzard) and raid roster; strangers without data stay unchanged. Default off,
-- Toggle: Settings > My Group. With a third-party chat addon (ns.ForeignChat) Oasis does not interfere.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Group", function()
local P = ns.Party
local function S() return ns.db and ns.db.settings or {} end
local issecret = issecretvalue or function() return false end

local roster, rosterAt = {}, 0
local function readRoster()
    if GetTime() - rosterAt < 20 then return end
    rosterAt = GetTime()
    roster = {}
    if IsInGuild() and GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, lvl, _, zone = GetGuildRosterInfo(i)
            name, lvl, zone = ns.safe(name), ns.safe(lvl), ns.safe(zone)
            if name then roster[name:gsub("%-.*$", "")] = { lvl = lvl, zone = zone } end
        end
    end
end
local function infoFor(sender)
    local short = sender:gsub("%-.*$", "")
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            local n, _, _, lvl, _, _, zone = GetRaidRosterInfo(i)
            n = ns.safe(n)
            if n and n:gsub("%-.*$", "") == short then return ns.safe(lvl), ns.safe(zone) end
        end
    end
    readRoster()
    local r = roster[short]
    if r then return r.lvl, r.zone end
    for _, u in ipairs(P.Units()) do
        if UnitExists(u) then
            local n = ns.safe(UnitName(u))
            if n == short then return ns.safe(UnitLevel(u)), nil end
        end
    end
end
local function filter(_, _, msg, sender, ...)
    if not S().chatZones or (ns.ForeignChat and ns.ForeignChat()) then return false end
    if type(msg) ~= "string" or issecret(msg) or type(sender) ~= "string" or issecret(sender) then return false end
    local lvl, zone = infoFor(sender)
    if not lvl and not zone then return false end
    local tag = "|cff8a8a90[" .. (lvl and tostring(lvl) or "") .. ((lvl and zone) and " " or "") .. (zone or "") .. "]|r "
    return false, tag .. msg, sender, ...
end
if ChatFrame_AddMessageEventFilter then
    for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }) do
        ChatFrame_AddMessageEventFilter(ev, filter)
    end
end
ns.On("GUILD_ROSTER_UPDATE", function() rosterAt = 0 end)

end)

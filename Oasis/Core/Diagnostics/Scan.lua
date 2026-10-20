-- Oasis: /oa scan - checks in the running client which Blizzard data is really readable,
-- and stores the result in OasisDB.scan (evaluable after /reload)
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Scan = {}
ns.Scan = Scan

-- Describe a value: type, secret?, keys for tables
local function describe(v, depth)
    depth = depth or 0
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    local t = type(v)
    if t == "table" then
        if depth > 1 then return "table" end
        local keys, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n <= 25 then keys[#keys + 1] = tostring(k) .. "=" .. describe(x, depth + 1) end
        end
        return "{" .. table.concat(keys, ", ") .. (n > 25 and (", +" .. (n - 25)) or "") .. "}"
    elseif t == "string" then
        return '"' .. v:sub(1, 60) .. '"'
    end
    return tostring(v)
end

local function try(out, key, fn, ...)
    local res = { pcall(fn, ...) }
    if not res[1] then
        out[key] = "FEHLER: " .. tostring(res[2])
    else
        local parts = {}
        for i = 2, math.min(#res, 8) do parts[#parts + 1] = describe(res[i]) end
        out[key] = table.concat(parts, " | ")
    end
    return res[1], res[2], res[3]
end

------------------------------------------------------------------------
-- Combat data from Blizzard's damage meter (after combat)
------------------------------------------------------------------------
local function sessionTypes()
    local T = Enum and Enum.DamageMeterSessionType
    if T then return { T.Current, T.Last, T.Overall } end
    return { 0, 1, 2 }
end
function Scan.FightInfo()
    local DM = C_DamageMeter
    if not DM or not DM.GetSessionDurationSeconds then return nil end
    local ok0, avail = pcall(DM.IsDamageMeterAvailable)
    if ok0 and avail == false then return nil end
    local info
    for _, st in ipairs(sessionTypes()) do
        if st ~= nil then
            local ok, dur = pcall(DM.GetSessionDurationSeconds, st)
            dur = ok and ns.safe(dur) or nil
            if type(dur) == "number" and dur > 0 then
                info = { dur = math.floor(dur) }
                local dmgType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
                local ok2, sess = pcall(DM.GetCombatSessionFromType, st, dmgType)
                if ok2 and type(sess) == "table" and not (issecretvalue and issecretvalue(sess)) then
                    local sources = sess.combatSources or sess.sources or sess
                    local best, bestAmt
                    if type(sources) == "table" then
                        for _, s in ipairs(sources) do
                            local amt = ns.safe(s.totalAmount or s.amount)
                            local name = ns.safe(s.name)
                            if type(amt) == "number" and name and (not bestAmt or amt > bestAmt) then best, bestAmt = name, amt end
                        end
                    end
                    if best then info.top = best end
                end
                break
            end
        end
    end
    return info
end

------------------------------------------------------------------------
-- The scan
------------------------------------------------------------------------
function Scan.Run()
    local out = {}
    local v, build, _, iface = GetBuildInfo()
    out.build = ("%s (%s) interface %s, Sprache %s"):format(tostring(v), tostring(build), tostring(iface), tostring(GetLocale()))
    out.time = date("%Y-%m-%d %H:%M")

    -- Game rules
    if C_GameRules then
        try(out, "rules.gameMode", C_GameRules.GetActiveGameMode)
        try(out, "rules.hardcore", C_GameRules.IsHardcoreActive)
        try(out, "rules.selfFound", C_GameRules.IsSelfFoundAllowed)
    end
    -- Guild
    try(out, "guild.info", GetGuildInfo, "player")
    try(out, "guild.motd", function() return C_GuildInfo.GetMOTD() end)
    try(out, "guild.infoText", function() return (C_GuildInfo.GetInfoText() or ""):sub(1, 60) end)
    try(out, "guild.rep", function() return C_Reputation.GetGuildFactionData() end)
    try(out, "guild.lastOnline1", GetGuildRosterLastOnline, 1)
    try(out, "guild.numNews", GetNumGuildNews)
    try(out, "guild.news1", function() return C_GuildInfo.GetGuildNewsInfo(1) end)
    try(out, "guild.tradeskills", GetNumGuildTradeSkill)
    try(out, "guild.tradeskill1", GetGuildTradeSkillInfo, 1)
    try(out, "guild.tradeskill2", GetGuildTradeSkillInfo, 2)
    try(out, "guild.challenges", GetNumGuildChallenges)
    try(out, "guild.isOfficer", C_GuildInfo.IsGuildOfficer)
    -- Guild bank
    try(out, "bank.enabled", function() return C_GuildBank and C_GuildBank.IsGuildBankEnabled and C_GuildBank.IsGuildBankEnabled() end)
    try(out, "bank.tabs", GetNumGuildBankTabs)
    try(out, "bank.tab1", GetGuildBankTabInfo, 1)
    try(out, "bank.money", GetGuildBankMoney)
    try(out, "bank.interactionType", function() return Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker end)
    -- Calendar
    try(out, "calendar.canEditGuild", CanEditGuildEvent)
    try(out, "calendar.guildEvents", function() return C_Calendar.GetNumGuildEvents() end)
    try(out, "calendar.guildEvent1", function() return C_Calendar.GetGuildEventInfo(1) end)
    -- Legacy
    try(out, "legacy.info", function()
        local i = C_PerksActivities.GetPerksActivitiesInfo()
        return i and i.activities and #i.activities, i and i.activities and i.activities[1]
    end)
    -- Loot history, damage meter, death
    try(out, "loot.encounters", function() return C_LootHistory.GetAllEncounterInfos() end)
    try(out, "loot.drops1", function()
        local e = C_LootHistory.GetAllEncounterInfos()
        return e and e[1] and C_LootHistory.GetSortedDropsForEncounter(e[1].encounterID)
    end)
    try(out, "damage.available", function() return C_DamageMeter.IsDamageMeterAvailable() end)
    try(out, "damage.enums", function() return Enum.DamageMeterSessionType, Enum.DamageMeterType end)
    try(out, "damage.sessions", function() return C_DamageMeter.GetAvailableCombatSessions() end)
    try(out, "damage.fightInfo", Scan.FightInfo)
    try(out, "death.corpse", function() return C_DeathInfo.GetCorpseMapPosition(C_Map.GetBestMapForUnit("player") or 0) end)
    -- World
    try(out, "world.vignettes", function() local v2 = C_VignetteInfo.GetVignettes() return v2 and #v2, v2 and v2[1] and C_VignetteInfo.GetVignetteInfo(v2[1]) end)
    try(out, "world.weather", function() return C_Weather.GetCurrentWeather() end)
    try(out, "world.newcomer", function() return C_PlayerMentorship.IsActivePlayerConsideredNewcomer() end)
    try(out, "world.recentAllies", function() return C_RecentAllies.IsSystemEnabled() end)
    -- Oasis state
    out["oasis.version"] = ns.version
    out["oasis.members"] = (function() local n = 0 for _ in pairs(ns.db.members) do n = n + 1 end return n end)()
    out["oasis.restricted"] = tostring(ns.Comm.restricted())

    ns.db.scan = out
    local n, bad = 0, 0
    for _, x in pairs(out) do
        n = n + 1
        if type(x) == "string" and x:find("^FEHLER") then bad = bad + 1 end
    end
    ns.print((L["Scan done: %d checks, %d errors. Now /reload to save the results."]):format(n, bad))
end
ns.slash.scan = function(...) if ns.IsDev and ns.IsDev() then return Scan.Run(...) end end   -- 0.6.524: developer mode only

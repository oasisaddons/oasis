-- Oasis - Guild leadership: hub for guild masters and officers (from a configurable rank)
--  * Turn modules on/off for the whole guild
--  * Permissions: from which rank the hub is visible (guild master only)
--  * Announcements to everyone with Oasis (notice + sound, pinned on the overview)
--  * Overview: who uses Oasis, which version
-- Each leader writes their own record "gcfg-<Name>" into the collection "guildcfg";
-- the newest record of an authorized author wins (rank is checked against the guild roster).
local ADDON, ns = ...
local L = ns.L
local K, C, Store, Comm = ns.K, ns.K.C, ns.Store, ns.Comm

local Admin = {}
ns.Admin = Admin

local DEFAULTS = {
    off = "",          -- disabled pages, comma-separated
    logo = "auto",     -- auto | oasis | text
    ltext = "",        -- custom lettering (empty = guild name)
    lfont = "cinzel",
    lcol = "",         -- text color hex (empty = accent color)
    lsize = 0,         -- 0 = fit automatically
    xp2 = 0,           -- XP weekend: double Oasis XP until this time
    crest = "",        -- Guild crest: icon (name from Media/icons/badges)
    crestc = "",       -- Guild crest: color hex
    xp2s = 0,          -- Double XP scheduled: start (0 = immediately)
    vis = "",          -- Module visible only from rank: "bank:1,raid:3" (rank index, 0 = guild master)
    nob = "",          -- Modules without a news count in the navigation: "chat,insta"
    lup = false,       -- Upper case
    lsub = "",         -- Subtitle (empty = none)
    acc = "",          -- Accent color hex (empty = Oasis red)
    rank = 1,          -- Guild leadership from rank (0 = guild master only)
    inv = false,       -- Whisper members without Oasis once (default: off)
    dlink = "",        -- Discord link for this message
    crown = "all",     -- Crown at the top: "all" = everyone sees it (greyed out without permission) | "lead" = guild leadership only
}
Admin.DEFAULTS = DEFAULTS
function Admin.RegisterOptionDefault(def)
    if def and def.key and DEFAULTS[def.key] == nil then DEFAULTS[def.key] = def.default end
end
for _, def in ipairs(ns.GuildOpts or {}) do Admin.RegisterOptionDefault(def) end
-- these pages cannot be disabled
Admin.LOCKED = { home = true, settings = true, admin = true }

------------------------------------------------------------------------
-- Guild and ranks
------------------------------------------------------------------------
function Admin.GuildName()
    if not IsInGuild() then return nil end
    local g = ns.safe((GetGuildInfo("player")))
    return (g and g ~= "") and g or nil
end
-- Test mode (/oa testleitung): treat as guild master on this PC only.
-- Other clients check the real rank and ignore changes made in test mode.
-- 0.5.997: on by default for developers (adminTest == false = deliberately off)
function Admin.TestMode()
    local s = ns.db and ns.db.settings
    if not s then return false end
    -- 0.5.998: reset an old "off" (from before the default-on era) once
    if not s.adminTestV2 then s.adminTestV2 = true if s.adminTest == false then s.adminTest = nil end end
    return s.adminTest ~= false and ns.IsDev() and true or false
end
local function myRankIndex()
    if not IsInGuild() then return nil end
    if Admin.TestMode() then return 0 end
    local _, _, ri = GetGuildInfo("player")
    return ns.safe(ri)
end
local function rankOf(name)
    if ns.isMe(name) then return myRankIndex() end
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
    return m and m.rankIndex
end
Admin.RankOf = rankOf
local function rosterKnown()
    return ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0
end
function Admin.RankNames()
    local out = {}
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 1, n do out[i - 1] = GuildControlGetRankName(i) or ("#" .. i) end
    if n == 0 then out[0] = L["Guild Master"] out[1] = L["Officer"] end
    return out, math.max(n, 2)
end

------------------------------------------------------------------------
-- Guild settings (apply to everyone)
------------------------------------------------------------------------
-- cached, rebuilt only when the collection changes (performance 0.5.482: ran on every topbar/
-- navigation update once per page: Store.List + sorting)
local grCache, grGuild
ns.Listen("STORE", function(coll) if coll == "guildcfg" then grCache = nil end end)
local function guildRecs()
    local g = Admin.GuildName()
    if not g then return {} end
    if grCache and grGuild == g then return grCache end
    local list = Store.List("guildcfg", function(r) return r.kind == "cfg" and r.g == g end)
    table.sort(list, function(a, b) return (a.u or 0) > (b.u or 0) end)
    grCache, grGuild = list, g
    return list
end

-- Rank limit: whatever the guild master set last applies
function Admin.LeaderRank()
    for _, r in ipairs(guildRecs()) do
        if rankOf(r.by) == 0 and tonumber(r.rank) then return tonumber(r.rank) end
    end
    local g = Admin.GuildName()
    local cache = g and ns.db.gcfgCache and ns.db.gcfgCache[g]
    return cache and tonumber(cache.rank) or DEFAULTS.rank
end

function Admin.Trusted(by)
    if not by then return false end
    local r = rankOf(by)
    if r == nil then return nil end   -- unknown (guild roster not loaded yet)
    return r == 0 or r <= Admin.LeaderRank()
end

local function withDefaults(rec)
    local out = {}
    for k, v in pairs(DEFAULTS) do
        local x = rec and rec[k]
        if x == nil then x = v end
        out[k] = x
    end
    out.by, out.u = rec and rec.by, rec and rec.u
    return out
end

local memo, memoKey
function Admin.Cfg()
    local g = Admin.GuildName()
    if not g then return withDefaults(nil) end
    local recs = guildRecs()
    local key = g .. ":" .. #recs .. ":" .. (recs[1] and recs[1].u or 0) .. ":" .. (ns.Radar and ns.Radar.roster and #ns.Radar.roster or 0) .. ":" .. tostring(myRankIndex())
    if memo and memoKey == key then return memo end
    ns.db.gcfgCache = ns.db.gcfgCache or {}
    local found
    if rosterKnown() then
        for _, r in ipairs(recs) do
            if Admin.Trusted(r.by) then found = r break end
        end
        local cfg = withDefaults(found)
        if found then
            local c = {}
            for k in pairs(DEFAULTS) do c[k] = cfg[k] end
            c.by, c.u = cfg.by, cfg.u
            ns.db.gcfgCache[g] = c
        else
            ns.db.gcfgCache[g] = nil
        end
        memo, memoKey = cfg, key
        return cfg
    end
    -- Guild roster not loaded yet: use the last checked state
    return withDefaults(ns.db.gcfgCache[g])
end

function Admin.CanManage()
    if not IsInGuild() then return false end
    if IsGuildLeader and IsGuildLeader() then return true end
    local r = myRankIndex()
    return r ~= nil and r <= Admin.LeaderRank()
end
-- Show the crown at the top? (guild setting "crown"; leadership always sees it)
function Admin.ShowCrown()
    -- Crown visible to everyone; without permission the page is visibly locked (dimmed with a padlock)
    return true
end
-- Raid roles (assigned in guild leadership): "lead" | "assist" | nil
local function inList(str, name)
    if not name then return false end
    for n in tostring(str or ""):gmatch("[^,]+") do
        n = n:gsub("^%s+", ""):gsub("%s+$", "")
        if ns.SameName(n, name) then return true end
    end
    return false
end
-- Raid roles: "lead" | "assist" | nil
-- a) named in guild leadership (guild options rlead/rassi)
-- b) automatically by guild rank (guild options rleadRank/rassiRank: 0 = off, N = ranks 1..N)
-- Also applies to other names (sender check for transmitted data).
local function rankWithin(name, opt)
    local v = tonumber(ns.GuildOpt and ns.GuildOpt(opt)) or 0
    if v <= 0 then return false end
    local r = rankOf(name)
    return r ~= nil and r + 1 <= v
end
function Admin.RaidRole(name)
    name = name or ns.me()
    if inList(ns.GuildOpt and ns.GuildOpt("rlead"), name) or rankWithin(name, "rleadRank") then return "lead" end
    if inList(ns.GuildOpt and ns.GuildOpt("rassi"), name) or rankWithin(name, "rassiRank") then return "assist" end
end
------------------------------------------------------------------------
-- Permission levels: dev > lead (guild leadership) > officer > raidlead > raidassist > member
-- c) in an active raid: Blizzard raid leader = raidlead, Blizzard assistant = raidassist
------------------------------------------------------------------------
Admin.LEVEL = { member = 0, raidassist = 1, raidlead = 2, officer = 3, lead = 4, dev = 5 }
Admin.FEATURES = {
    ["raid.events"] = "raidlead", ["raid.plan"] = "raidlead", ["raid.tactics.edit"] = "raidlead", ["raid.loot"] = "raidlead",
    ["raid.plan.sort"] = "raidassist", ["raid.board"] = "raidassist", ["raid.readycheck"] = "raidassist", ["raid.announce"] = "raidassist",
    ["loot.config"] = "officer", ["officer"] = "officer", ["admin"] = "lead",
}
local function realOfficer()
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() and true or false
end
function Admin.Role()
    -- Developer rights only in test mode (the developer switch is account-wide - on alts without rank
    -- you should see the real restrictions, 08.10.)
    if Admin.TestMode() then return "dev" end
    if Admin.CanManage() then return "lead" end
    if realOfficer() or (ns.isOfficer and ns.isOfficer()) then return "officer" end
    local rr = Admin.RaidRole(ns.me())
    local inRaid = IsInRaid and IsInRaid()
    if rr == "lead" or (inRaid and UnitIsGroupLeader and UnitIsGroupLeader("player")) then return "raidlead" end
    if rr == "assist" or (inRaid and UnitIsGroupAssistant and UnitIsGroupAssistant("player")) then return "raidassist" end
    return "member"
end
-- required level of a feature ("officer.xyz" -> officer, "admin.xyz" -> lead)
function Admin.Need(feature)
    feature = tostring(feature or "")
    return Admin.FEATURES[feature] or Admin.FEATURES[feature:match("^([^%.]+)%.") or ""] or "lead"
end
function Admin.Can(feature)
    return (Admin.LEVEL[Admin.Role()] or 0) >= (Admin.LEVEL[Admin.Need(feature)] or 99)
end
-- Backward compatible: IsRaidLead = full raid leader rights, CanRaidPlan = sort raid planner (from assistant)
function Admin.IsRaidLead() return Admin.Can("raid.events") end
function Admin.CanRaidPlan() return Admin.Can("raid.plan.sort") end
-- Overview for guild leadership: who has which raid level
function Admin.RaidStaffText()
    local lead, assist = {}, {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local r = Admin.RaidRole(m.name)
        if r == "lead" then lead[#lead + 1] = ns.displayName(m.name) elseif r == "assist" then assist[#assist + 1] = ns.displayName(m.name) end
    end
    table.sort(lead) table.sort(assist)
    local none = "|cff777777" .. L["nobody"] .. "|r"
    return L["Raid leaders"] .. ": " .. (#lead > 0 and table.concat(lead, ", ") or none) .. "\n"
        .. L["Raid assistants"] .. ": " .. (#assist > 0 and table.concat(assist, ", ") or none) .. "\n|cff888888"
        .. L["Guild leadership and officers have all raid leader rights. In a running raid, the raid leader and assistants count for the duration of the raid."] .. "|r"
end
function Admin.IsGM()
    if IsGuildLeader and IsGuildLeader() then return true end
    return myRankIndex() == 0
end

------------------------------------------------------------------------
-- Permissions of OTHER people (receiver's view): may the author of a received record do this?
-- Level from guild roster (rank), rank permissions (officer chat), name lists/rank options (rlead/rassi)
-- and, in an active raid, Blizzard leader/assistant. Developer rights NEVER apply to others.
-- Returns Admin.MayAuthor: true | false | nil (guild roster not loaded yet -> check again later)
------------------------------------------------------------------------
for k, v in pairs({ events = "raidlead", raidplan = "raidassist", tactics = "raidlead", polls = "officer", points = "officer",
    notices = "lead", guildcfg = "lead", formers = "officer", audit = "officer", notes = "officer", bans = "officer", sndmute = "officer", recruits = "officer" }) do
    if Admin.FEATURES[k] == nil then Admin.FEATURES[k] = v end
end
ns.GuildOption({ page = "officer", key = "offRank", default = 2, min = 1, max = 10, step = 1, label = "Officers up to guild rank (fallback)",
    desc = "Only if WoW does not provide the rank permissions: up to which guild rank others count as officers (for checking received data).",
    fmt = function(v) return (ns.L["up to rank %d"]):format(tonumber(v) or 0) end })
-- Compare names: "Firstname Lastname-Realm" (guild roster) == "Firstname-Realm" (messages)
local function nameKey(n) return n and ns.NameKey(n) end
function Admin.SameName(a, b) return ns.SameName(a, b) end
-- Rank permission "officer chat" of a rank (rank index 0 = guild master); nil = not readable
local flagCache, flagAt = {}, 0
local function rankFlagOfficer(ri)
    if GetTime() - flagAt > 60 then flagCache, flagAt = {}, GetTime() end
    local c = flagCache[ri]
    if c ~= nil then if c == "na" then return nil end return c end
    local res = "na"
    if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
        local ok, t = pcall(C_GuildInfo.GuildControlGetRankFlags, ri + 1)
        if ok and type(t) == "table" then
            local v = t[4]   -- 4 = speak in officer chat (3 = listen)
            if v == nil then v = t[3] end
            if v ~= nil then res = ns.safe(v) and true or false end
        end
    end
    flagCache[ri] = res
    if res == "na" then return nil end
    return res
end
Admin.RankFlagOfficer = rankFlagOfficer
local function rankIsOfficer(ri)
    local f = rankFlagOfficer(ri)
    if f ~= nil then return f end
    local v = tonumber(ns.GuildOpt and ns.GuildOpt("offRank")) or 2
    return ri + 1 <= v
end
-- in an active raid: Blizzard leader / assistant?
local function blizzRaidRole(name)
    if not (IsInRaid and IsInRaid()) then return nil end
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local u = "raid" .. i
        local n = ns.safe(ns.UnitName(u))
        if n and Admin.SameName(ns.fullName(n), name) then
            if UnitIsGroupLeader and ns.safe(UnitIsGroupLeader(u)) then return "raidlead" end
            if UnitIsGroupAssistant and ns.safe(UnitIsGroupAssistant(u)) then return "raidassist" end
            return nil
        end
    end
end
-- Leader of your own (non-raid) group? (group leaders may write tactics there)
function Admin.IsMyPartyLeader(name)
    if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return false end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists and UnitExists(u) then
            local n = ns.safe(ns.UnitName(u))
            if n and Admin.SameName(ns.fullName(n), name) then return UnitIsGroupLeader and ns.safe(UnitIsGroupLeader(u)) and true or false end
        end
    end
    return false
end
-- Level of another person: "lead" | "officer" | "raidlead" | "raidassist" | "member" | nil (unknown)
-- why: short reason (for /oa probe rechte)
function Admin.RoleOf(name)
    if not name or name == "" then return "member", "kein Name" end
    if ns.isMe(name) then
        local r = Admin.Role()
        if r == "dev" then r = Admin.CanManage() and "lead" or "officer" end
        return r, "ich selbst"
    end
    if not IsInGuild() then return blizzRaidRole(name) or "member", "no guild" end
    if not rosterKnown() then return nil, "Gildenliste noch nicht geladen" end
    local ri = rankOf(name)
    if ri ~= nil and ri < 99 then
        if ri == 0 or ri <= Admin.LeaderRank() then return "lead", "Gildenrang " .. ri .. " (Leitung bis " .. Admin.LeaderRank() .. ")" end
        local fl = rankFlagOfficer(ri)
        if rankIsOfficer(ri) then return "officer", "Gildenrang " .. ri .. (fl ~= nil and " (Rang-Recht Offizierschat)" or " (Ersatz-Option offRank)") end
        local rr = Admin.RaidRole(name)
        if rr == "lead" then return "raidlead", "Schlachtzugsleiter (Liste/Rang)" end
        local b = blizzRaidRole(name)
        if b then return b, "im Raid (Blizzard)" end
        if rr == "assist" then return "raidassist", "Assistenz (Liste/Rang)" end
        return "member", "Gildenrang " .. ri
    end
    local b = blizzRaidRole(name)
    if b then return b, "nicht in der Gilde, im Raid (Blizzard)" end
    return "member", "not in the guild list"
end
function Admin.MayAuthor(name, feature)
    local role = Admin.RoleOf(name)
    if role == nil then return nil end
    return (Admin.LEVEL[role] or 0) >= (Admin.LEVEL[Admin.Need(feature)] or 99)
end
-- in the guild roster? true | false | nil (unknown)
function Admin.InGuildList(name)
    if ns.isMe(name) then return true end
    if not rosterKnown() then return nil end
    local ri = rankOf(name)
    return ri ~= nil and ri < 99
end

------------------------------------------------------------------------
-- Validation rules per collection (for store receive in Comm.lua)
-- g(rec, actor, old) -> true | false | nil.  actor = who sent/made the change.
------------------------------------------------------------------------
local function rankWithinLimit(name, limit)
    limit = tonumber(limit) or 10
    if limit >= 10 then return false end
    local ri = rankOf(name)
    return ri ~= nil and ri + 1 <= limit
end
local function level(name, feature, extra)
    local ok = Admin.MayAuthor(name, feature)
    if ok then return true end
    if extra then
        local e = extra(name)
        if e then return true end
    end
    return ok
end
local function selfRule(field, allowFeature, viaMain)
    return function(rec, actor)
        local who = rec[field]
        if not who or who == "" then return false end
        if Admin.SameName(who, actor) then return true end
        if viaMain and ns.Alts and ns.Alts.Main then
            local ok, m = pcall(ns.Alts.Main, actor)
            if ok and m and Admin.SameName(m, who) then return true end
        end
        if allowFeature then return level(actor, allowFeature) end
        return false
    end
end
local function memberRule(delFeature)
    return function(rec, actor, old)
        if rec.del and delFeature then return level(actor, delFeature) end
        return Admin.InGuildList(actor)
    end
end
-- Guild roster entry by short name (the log stores short names)
local function rosterEntry(name)
    local full = ns.ResolveName(name)
    return full and ns.Radar and ns.Radar.byName and ns.Radar.byName[full]
end
Admin.RosterEntry = rosterEntry
local function officerOk(actor)
    local role = Admin.RoleOf(actor)
    return role == "lead" or role == "officer"
end
-- does a log entry match the current guild roster?
local function auditPlausible(rec)
    local k = rec.kind
    if k == "join" or k == "rejoin" then return rosterEntry(rec.a) ~= nil end
    if k == "leave" or k == "gone" then return rosterEntry(rec.a) == nil end
    if k == "kick" then return rosterEntry(rec.a) == nil end
    if k == "promote" or k == "demote" then
        local m = rosterEntry(rec.b)
        return m ~= nil and (rec.r == "" or m.rank == rec.r)
    end
    if k == "rankup" or k == "rankdown" then
        local m = rosterEntry(rec.a)
        return m ~= nil and m.rank == rec.r
    end
    if k == "note" then
        local m = rosterEntry(rec.a)
        return m ~= nil and (m.note or "") == (rec.r or "")
    end
    return false
end
-- Someone who is "raid leader" only via a Blizzard raid may not write persistent guild data
-- (otherwise anyone could form a raid and change the guild's events/tactics/plans)
local function blizzOnly(actor)
    local _, why = Admin.RoleOf(actor)
    return type(why) == "string" and why:find("Blizzard", 1, true) ~= nil
end
local function lasting(r, actor)
    if r and blizzOnly(actor) then return false end
    return r
end
Admin.AUTH = {
    events = function(rec, actor)
        return lasting(level(actor, "events", function(n) return rankWithinLimit(n, ns.GuildOpt and ns.GuildOpt("rdEvRank")) end), actor)
    end,
    signups = selfRule("who"),
    raidplan = function(rec, actor) return lasting(level(actor, "raidplan"), actor) end,
    tactics = function(rec, actor) return lasting(level(actor, "tactics", Admin.IsMyPartyLeader), actor) end,
    rpreq = function(rec, actor) return lasting(level(actor, "tactics", Admin.IsMyPartyLeader), actor) end,
    polls = function(rec, actor) return level(actor, "polls") end,
    votes = selfRule("who", nil, true),
    avotes = memberRule(),
    points = function(rec, actor)
        -- the points settings themselves (who may award points) officers only, not delegated points managers
        if rec and rec.id == "points-cfg" then return lasting(level(actor, "points"), actor) end
        return level(actor, "points", function(n)
            local lim = ns.Points and ns.Points.Cfg and tonumber(ns.Points.Cfg().rank)
            local ri = rankOf(n)
            return lim and ri ~= nil and ri <= lim
        end)
    end,
    notices = function(rec, actor) return level(actor, "notices") end,
    guildcfg = function(rec, actor)
        -- each leader writes only their own record gcfg-<Name>
        if rec.by and not Admin.SameName(rec.by, actor) then return false end
        if rec.id and rec.by and rec.id ~= "gcfg-" .. rec.by then return false end
        return level(actor, "guildcfg")
    end,
    -- 0.6.532: official guild pack only from leadership (permission guildcfg), only the fixed record
    gpack = function(rec, actor) if rec.id ~= "gpack-official" then return false end return level(actor, "guildcfg") end,
    bans = function(rec, actor) return level(actor, "bans") end,
    sndmute = function(rec, actor) return level(actor, "sndmute") end,
    recruits = function(rec, actor) return level(actor, "recruits") end,
    -- Log/former members/attendance are created automatically by every member (system messages, guild roster):
    -- any guild member may create, only officers may delete
    -- New entries from non-officers are checked against your OWN guild roster (plausibility),
    -- so a manipulated client cannot inject fake joins/leaves, promotions or former members
    formers = function(rec, actor, old)
        local r = memberRule("formers")(rec, actor, old)
        if not r or rec.del then return r end
        if officerOk(actor) then return true end
        if not rosterKnown() then return nil end
        local here = rosterEntry(rec.full or rec.name) ~= nil
        local back = (tonumber(rec.returned) or 0) > (tonumber(rec.left) or 0)
        return here == back
    end,
    audit = function(rec, actor, old)
        local r = memberRule("audit")(rec, actor, old)
        if not r or rec.del then return r end
        if officerOk(actor) then return true end
        if not rosterKnown() then return nil end
        return auditPlausible(rec)
    end,
    -- Attendance is written by the raid leader: only officers or named raid leaders/assistants (list/rank)
    attend = function(rec, actor, old)
        if not Admin.InGuildList(actor) then return false end
        if rec.del then return level(actor, "officer") end
        if officerOk(actor) then return true end
        local rr = Admin.RaidRole and Admin.RaidRole(actor)
        return rr == "lead" or rr == "assist"
    end,
    sres = selfRule("char", "events"),
    -- Loot: anyone may report their own loot (who = sender); awards to others only raid leadership
    -- (list/rank/Blizzard raid leader) or leader of your own group; deleting others' only raid leadership
    loot = function(rec, actor)
        if rec.who and Admin.SameName(rec.who, actor) and rec.src ~= "Vergabe" then return true end
        return level(actor, "raid.loot", Admin.IsMyPartyLeader)
    end,
    -- Death roll: only the two participants
    duels = function(rec, actor)
        if rec.winner and Admin.SameName(rec.winner, actor) then return true end
        if rec.loser and Admin.SameName(rec.loser, actor) then return true end
        return false
    end,
    -- Chronicle: own entries; any member may report guild events (join etc.)
    chronicle = function(rec, actor)
        if rec.kind == "guild" and not rec.del then return Admin.InGuildList(actor) end
        return selfRule("who", "officer")(rec, actor)
    end,
    wants = selfRule("who", "officer"),
    lfg = selfRule("who", "officer"),
    lfgreq = selfRule("by", "officer"),
    deaths = selfRule("who", "officer"),
    posts = selfRule("by", "officer"),
    -- pinned guild chat message: officer and up (guild option "lead": guild leadership only)
    chatpin = function(rec, actor)
        return level(actor, (ns.GuildOpt and ns.GuildOpt("chPin") == "lead") and "admin" or "officer")
    end,
    -- Reactions: id = <message>#<reactor>
    reacts = function(rec, actor)
        local who = tostring(rec.id or ""):match("#([^#]+)$")
        return who ~= nil and Admin.SameName(who, actor)
    end,
    -- recently linked items: any guild member, only officers may delete
    links = memberRule("officer"),
    raidint = function(rec, actor)
        local who = tostring(rec.id or ""):match("^ri%-(.+)$")
        return who ~= nil and Admin.SameName(who, actor)
    end,
}
-- Diagnostics: /oa probe rechte <Name>
ns.probes = ns.probes or {}
ns.probes.rechte = function(rest)
    local name = rest and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then name = ns.me() or "" end
    local full = name
    if ns.Radar and ns.Radar.byName then
        if not ns.Radar.byName[full] then full = ns.fullName(name) or name end
        if not ns.Radar.byName[full] then
            for _, m in ipairs(ns.Radar.roster or {}) do
                if Admin.SameName(m.name, full) then full = m.name break end
            end
        end
    end
    local role, why = Admin.RoleOf(full)
    ns.print(("|cffe8b44a/oa probe rechte|r %s -> %s  (%s)"):format(ns.displayName and ns.displayName(full) or full, tostring(role or "unbekannt"), tostring(why or "")))
    local ri = rankOf(full)
    ns.print(("  Gildenrang-Index: %s  ·  Leitung bis Rang %s  ·  Offizier-Ersatz bis Rang %s"):format(tostring(ri), tostring(Admin.LeaderRank()), tostring(ns.GuildOpt("offRank"))))
    if ri and ri < 99 then
        local fl = rankFlagOfficer(ri)
        ns.print("  Rang-Recht Offizierschat (C_GuildInfo.GuildControlGetRankFlags): " .. (fl == nil and "nicht lesbar" or tostring(fl)))
    end
    ns.print("  Raid-Rolle (Liste/Rang): " .. tostring(Admin.RaidRole(full) or "-") .. "  ·  Raid (Blizzard): " .. tostring(blizzRaidRole(full) or "-"))
    local feats = { "events", "raidplan", "tactics", "polls", "points", "notices", "guildcfg", "audit" }
    local t = {}
    for _, f in ipairs(feats) do
        local ok = Admin.MayAuthor(full, f)
        t[#t + 1] = f .. "=" .. (ok == nil and "?" or (ok and "ja" or "nein"))
    end
    ns.print("  darf: " .. table.concat(t, "  "))
    if ns.Store and ns.Store.HeldCount then ns.print("  zurueckgestellte Datensaetze: " .. ns.Store.HeldCount() .. "  ·  verworfen: " .. (ns.Store.rejected or 0)) end
end

function Admin.Save(cfg)
    local g = Admin.GuildName()
    if not g or not Admin.CanManage() then return false end
    local rec = { id = "gcfg-" .. ns.me(), kind = "cfg", g = g }
    for k in pairs(DEFAULTS) do rec[k] = cfg[k] end
    if not Admin.IsGM() then rec.rank = Admin.LeaderRank() end
    local old = Store.Get("guildcfg", rec.id)
    rec.u = old and old.u
    Store.Put("guildcfg", rec)
    memo = nil
    return true
end

-- Page enabled for the guild?
local function offSet(cfg)
    local t = {}
    for k in tostring(cfg.off or ""):gmatch("[^,]+") do t[k] = true end
    return t
end
Admin.OffSet = offSet
local function visMap(cfg)
    local t = {}
    for k, r in tostring(cfg.vis or ""):gmatch("([%w_]+):(%d+)") do t[k] = tonumber(r) end
    return t
end
Admin.VisMap = visMap
local function setVis(cfg, key, rank)
    local t = visMap(cfg)
    t[key] = rank
    local parts = {}
    for k, r in pairs(t) do parts[#parts + 1] = k .. ":" .. r end
    table.sort(parts)
    cfg.vis = table.concat(parts, ",")
end
local function nobSet(cfg)
    local t = {}
    for k in tostring(cfg.nob or ""):gmatch("[^,]+") do t[k] = true end
    return t
end
Admin.NoBadge = function(key) return nobSet(Admin.Cfg())[key] and true or false end
function Admin.PageEnabled(key, cfg)
    if Admin.LOCKED[key] then return true end
    cfg = cfg or Admin.Cfg()
    -- visible only from a certain guild rank (leadership always sees everything)
    local need = visMap(cfg)[key]
    if need and not Admin.CanManage() then
        local mine = myRankIndex()
        if mine == nil or mine > need then return false end
    end
    return true
end

------------------------------------------------------------------------
-- Logo and accent color (everyone picks their own; guild color stays as the default)
------------------------------------------------------------------------
local ORIG = {
    accent = { unpack(C.accent) }, accent2 = { unpack(C.accent2) }, violet = { unpack(C.violet) },
}
local appliedAcc
function Admin.ApplyAccent(hex)
    local c = K.FromHex(hex)
    local key = c and hex or ""
    if appliedAcc == key then return end
    appliedAcc = key
    local a = c or ORIG.accent
    local a2 = c and { c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1 } or ORIG.accent2
    for i = 1, 4 do
        C.accent[i] = a[i] or 1
        C.violet[i] = a[i] or 1
        C.accent2[i] = a2[i] or 1
    end
    -- already built toggles, bars and icons keep their color -> rebuild the window
    -- (throttled: dragging in the color wheel sends every small change separately)
    Admin.ScheduleRebuild()
end
-- Rebuild the window throttled (one shared counter: several changes in quick succession = one rebuild)
function Admin.ScheduleRebuild()
    if not (ns.RebuildMain and ns.loggedIn) then return end
    -- Color picker open: recolor live immediately, do the rebuild on close
    if K.pickerOpen then
        if K.LiveRecolor then K.LiveRecolor() end
        Admin.rebuildPending = true
        return
    end
    Admin.rebuildGen = (Admin.rebuildGen or 0) + 1
    local gen = Admin.rebuildGen
    ns.After(0.4, function() if Admin.rebuildGen == gen then ns.RebuildMain() end end)
end

K.onPickerClosed = function()
    if Admin.rebuildPending then Admin.rebuildPending = nil Admin.ScheduleRebuild() end
end

-- personal accent color (Settings > Appearance) before the guild color
function Admin.EffectiveAccent(cfg)
    local mine = ns.db and ns.db.settings.accent or ""
    if K.FromHex(mine) then return mine end
    cfg = cfg or Admin.Cfg()
    return cfg.acc or ""
end
function Admin.GuildAccentColor()
    return K.FromHex(Admin.Cfg().acc) or ORIG.accent
end

-- 0.5.953: sample data shows a long guild name in the logo (to see how Oasis handles long names).
-- DISPLAY only: Admin.GuildName() stays the real name (sync and permissions depend on it).
Admin.DEMO_GUILD = "H\195\188ter der Ewigen Flamme"
function Admin.DemoGuildName()
    if ns.db and ns.db.demo == true then return Admin.DEMO_GUILD end
    return nil
end
function Admin.BrandText(cfg)
    cfg = cfg or Admin.Cfg()
    local t = Admin.DemoGuildName() or ((cfg.ltext or "") ~= "" and cfg.ltext) or Admin.GuildName() or "Oasis"
    t = K.Upper(t)   -- Guild name always in upper case
    return t
end
function Admin.BrandSub(cfg)
    cfg = cfg or Admin.Cfg()
    -- no custom subtitle: none (formerly "Gildenzentrale")
    return cfg.lsub or ""
end
-- 0.5.681: always the guild name as lettering (Oasis is being published - no more Oasis guild wordmark);
-- without a guild, "Oasis" is shown in the same font
function Admin.LogoMode(cfg)
    return "text"
end

-- Logo styles (0.5.916): everyone picks their own by clicking the logo (settings.logoStyle, nil = "soft")
--   soft   = accent color -> same color lighter        fire  = accent color -> warm neighboring color (red -> yellow)
--   lead   = start in accent color, then text color       plain = text color      accent = fully accent color
Admin.LOGO_STYLES = {
    { key = "soft", text = "Soft gradient" }, { key = "fire", text = "Warm gradient" },
    { key = "lead", text = "Only the start in colour" }, { key = "plain", text = "Light, no colour" },
    { key = "accent", text = "All in accent colour" },
}
function Admin.LogoStyle()
    local st = ns.db and ns.db.settings and ns.db.settings.logoStyle
    for _, d in ipairs(Admin.LOGO_STYLES) do if d.key == st then return st end end
    return "soft"
end
-- End color of the gradient: "fire" shifts the hue by ~32 degrees (less saturated, light), otherwise the same color lighter
function Admin.LogoGradientEnd(col, style)
    local r, g, b = col[1], col[2], col[3]
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    if style ~= "fire" or d < 0.08 then
        local k = 0.62
        return { r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k }
    end
    local h
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = (h / 6 + 0.09) % 1
    local s, v = (d / mx) * 0.72, 1
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local pp, q, tt = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return { v, tt, pp } elseif i == 1 then return { q, v, pp } elseif i == 2 then return { pp, v, tt }
    elseif i == 3 then return { pp, q, v } elseif i == 4 then return { tt, pp, v } end
    return { v, pp, q }
end
-- Color of the letter at position q (0..1) in the name
function Admin.LogoLetterColor(style, col, text, q)
    if style == "plain" then return text end
    if style == "accent" then return col end
    local to, k = Admin.LogoGradientEnd(col, style), q
    if style == "lead" then to, k = text, math.min(1, q * 2.2) end
    return { col[1] + (to[1] - col[1]) * k, col[2] + (to[2] - col[2]) * k, col[3] + (to[3] - col[3]) * k }
end

-- Logo widget: shows the Oasis wordmark or the guild name as lettering
local logos = setmetatable({}, { __mode = "k" })
function ns.GuildLogo(parent, w, h, withLine, fixedCfg)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.wm = ns.Wordmark(f, w, h, withLine)
    f.wm:SetPoint("TOPLEFT")
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("BOTTOMLEFT", 0, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.text:SetShadowColor(0, 0, 0, 0.7)
    f.text:SetShadowOffset(1, -1)
    f.text:Hide()   -- never visible, only holds the text; the letter-spaced version is shown (f.track)
    f.track = K.Tracked(f, 20, C.accent)
    f.track:Hide()
    -- Guild name (text logo): monogram tile with initial + name in normal case
    f.badge = CreateFrame("Frame", nil, f)
    f.badge:SetSize(h - 4, h - 4)
    f.badge:SetPoint("LEFT", 0, 0)
    f.badge.bg = f.badge:CreateTexture(nil, "BACKGROUND")
    f.badge.bg:SetAllPoints()
    if not (K.ApplySkin and K.ApplySkin(f.badge, "button", C.accent)) then f.badge.bg:SetColorTexture(1, 1, 1, 1) end
    f.badge.t = f.badge:CreateFontString(nil, "OVERLAY")
    K.SetFontSafe(f.badge.t, K.FONT_HEAD or K.FONT, math.floor((h - 4) * 0.55), "", K.FONT)
    f.badge.t:SetPoint("CENTER", 0, 1)
    f.badge.t:SetTextColor(1, 1, 1)
    f.badge:Hide()
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetPoint("LEFT", 0, 0)   -- without monogram tile
    f.name:SetJustifyH("LEFT")
    f.name:SetJustifyV("MIDDLE")
    f.name:SetWordWrap(false)
    f.name:SetShadowColor(0, 0, 0, 0.6)
    f.name:SetShadowOffset(1, -1)
    f.name:Hide()
    -- 0.5.714: brand line under the name (only large logos without their own line): short bold start, then gradient to the right
    if h >= 30 and not withLine then
        f.rule = f:CreateTexture(nil, "ARTWORK")
        f.rule:SetHeight(2)
        f.rule:SetPoint("BOTTOMLEFT", 0, 1)
        f.rule:SetPoint("BOTTOMRIGHT", 0, 1)
        f.tick = f:CreateTexture(nil, "OVERLAY")
        f.tick:SetSize(30, 2)
        f.tick:SetPoint("BOTTOMLEFT", 0, 1)
        f.rule:Hide()
        f.tick:Hide()
        -- small line under the rule: how many guild members are online right now (updated every 30 s)
        f.sub = f:CreateFontString(nil, "OVERLAY")
        K.SetFontSafe(f.sub, K.FONT, 11, "", K.FONT)
        f.sub:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
        f.sub:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        f.sub:SetJustifyH("LEFT")
        local function upd()
            local n, on = 0, 0
            for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
                n = n + 1
                if m.online then on = on + 1 end
            end
            -- Numbers in text color, words dimmed, middle dot instead of hyphen (applies to every language)
            local s = n > 0 and (L["%d online - %d members"]):format(on, n) or ""
            s = s:gsub(" %- ", "  \194\183  "):gsub("%d+", function(d) return K.hex(C.text) .. d .. "|r" end)
            f.sub:SetText(s)
        end
        upd()
        ns.Every(30, function() if f:IsVisible() then pcall(upd) end end)
    end
    if withLine then
        f.line = f:CreateTexture(nil, "ARTWORK")
        f.line:SetHeight(1)
        f.line:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
        f.line:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
        f.spark = f:CreateTexture(nil, "OVERLAY")
        f.spark:SetTexture(ns.MEDIA .. "shine")
        f.spark:SetBlendMode("ADD")
        f.spark:SetSize(34, 3)
    end
    local t = 0
    f:SetScript("OnUpdate", function(self, el)
        if not self.line or not self.line:IsShown() then return end
        t = t + el
        local anim = not ns.db or ns.db.settings.logoAnim ~= false
        self.spark:SetShown(anim)
        if not anim then self.line:SetAlpha(1) end
        if anim then
            local q = (t % 3.2) / 3.2
            self.spark:ClearAllPoints()
            self.spark:SetPoint("CENTER", self.line, "LEFT", q * w, 0)
            self.spark:SetAlpha(math.sin(q * math.pi))
            self.line:SetAlpha(0.7 + 0.3 * math.sin(t * 1.3))
        end
    end)
    function f:Apply(cfg)
        cfg = cfg or self.fixedCfg or Admin.DisplayCfg()
        local mode = Admin.LogoMode(cfg)
        local isText = mode == "text"
        self.wm:SetShown(not isText)
        self.track:Hide()
        self.badge:Hide()
        self.name:SetShown(isText)
        if self.line then self.line:SetShown(isText) self.spark:SetShown(isText) end
        if self.rule then self.rule:Hide() self.tick:Hide() end   -- 0.5.911: no more line under the name
        if not isText then return end
        local accHex = self.fixedCfg and cfg.acc or Admin.EffectiveAccent(cfg)
        local col = K.FromHex(cfg.lcol) or K.FromHex(accHex) or C.accent
        self.text:SetTextColor(col[1], col[2], col[3], 1)
        if self.line then
            local a = K.FromHex(accHex) or C.accent
            self.line:SetColorTexture(a[1], a[2], a[3], 0.35)
            self.spark:SetVertexColor(a[1], a[2], a[3])
        end
        -- Lettering always exactly as wide as the line below it
        -- 0.5.690: without a choice, narrow + bold (PT Sans Narrow Bold) - looks like a brand lettering
        local path, text = K.FontPath(cfg.lfont or "ptsansbold", K.FONT_HEAD), Admin.BrandText(cfg)
        path = K.FontFor(path, text)   -- Guild name with Cyrillic/Korean/Chinese: matching font
        local fs, tr = self.text, self.track
        tr.color = col
        -- Name in normal case (leadership's own logo text, otherwise guild name)
        local plain = (Admin.DemoGuildName and Admin.DemoGuildName()) or ((cfg.ltext or "") ~= "" and cfg.ltext) or Admin.GuildName() or "Oasis"
        -- Upper case; contract letter-spaced names ("o a s i s")
        local parts = {}
        for w in plain:gmatch("%S+") do parts[#parts + 1] = w end
        local single = #parts > 2
        for _, w in ipairs(parts) do if #w > 1 then single = false end end
        if single then plain = table.concat(parts) end
        plain = K.Upper and K.Upper(plain) or plain:upper()
        local initial = plain:match("[%z\1-\127\194-\244][\128-\191]*") or "?"
        self.badge.t:SetText(K.Upper and K.Upper(initial) or initial:upper())
        K.SkinFill(self.badge, col, 1)
        if not self.badge.skinFill then self.badge.bg:SetColorTexture(col[1], col[2], col[3], 1) end
        -- dark text on very light accent colors
        local lum = 0.299 * col[1] + 0.587 * col[2] + 0.114 * col[3]
        if lum > 0.72 then self.badge.t:SetTextColor(0.08, 0.08, 0.1) else self.badge.t:SetTextColor(1, 1, 1) end
        local nm = self.name
        nm:SetTextColor(C.text[1], C.text[2], C.text[3])
        -- 0.5.911: large logo without line; the name runs letter by letter from the
        -- Accent color into its lighter neighboring color (red -> orange, blue -> violet ...). Small logos stay single-colored.
        local style = Admin.LogoStyle()
        -- set short one-word names letter-spaced ("O A S I S"): looks like a wordmark; long names stay tight
        local shown = self.rule and Admin.LogoSpaced(plain, not (ns.db and ns.db.settings.logoTrack == false)) or plain
        local function tint(t)
            if not self.rule then return t end
            return Admin.LogoMarkup(t, style, col, C.text)
        end
        nm:ClearAllPoints()
        nm:SetPoint("LEFT", 0, self.rule and 2 or 0)
        if self.rule then self.rule:Hide() self.tick:Hide() end
        local avail = w
        local function fit()
            K.SetFontSafe(fs, path, 12, "", K.FONT_HEAD)
            fs:SetText(text)
            local function widthOf(t)
                nm:SetText(t)
                return tonumber(nm:GetStringWidth()) or 0
            end
            -- one line: largest font that fits the width
            nm:SetWordWrap(false)
            if nm.SetMaxLines then nm:SetMaxLines(1) end
            nm:SetWidth(0)
            local one = false
            -- Sizes by height (sidebar 39 px: 26..18, topbar 19 px: 12..8)
            local maxS = math.min(26, math.floor(h * 0.68))
            local minS = math.max(8, math.floor(maxS * 0.69))
            for size = maxS, minS, -1 do
                K.SetFontSafe(nm, path, size, "", K.FONT_HEAD)
                if widthOf(shown) <= avail then one = true break end
            end
            if one or h < 30 then
                nm:SetText(tint(shown))   -- (too low for two lines: smallest size, truncated if needed)
            else
                -- 0.5.690: two balanced lines (break where both lines are about equally long)
                local words = {}
                for w in plain:gmatch("%S+") do words[#words + 1] = w end
                local best
                for size = math.min(19, math.floor((h - (self.rule and 8 or 0)) / 2)), 10, -1 do
                    K.SetFontSafe(nm, path, size, "", K.FONT_HEAD)
                    best = nil
                    for i = 1, #words - 1 do
                        local a, b = table.concat(words, " ", 1, i), table.concat(words, " ", i + 1)
                        local mw = math.max(widthOf(a), widthOf(b))
                        if mw <= avail and (not best or mw < best.w) then best = { w = mw, t = a .. "\n" .. b } end
                    end
                    if best then break end
                end
                if nm.SetMaxLines then nm:SetMaxLines(2) end
                nm:SetWordWrap(true)
                if nm.SetSpacing then nm:SetSpacing(0) end
                nm:SetText(tint(best and best.t or plain))
            end
            nm:SetWidth(avail)
        end
        fit()
        -- WoW loads a new font file only on first use; the first measurement is
        -- often wrong -> measure again shortly after
        self.fitGen = (self.fitGen or 0) + 1
        local gen = self.fitGen
        for _, d in ipairs({ 0.05, 0.3, 1 }) do
            ns.After(d, function() if self.fitGen == gen then fit() end end)
        end
    end
    -- Click: choose font (leadership for the guild, everyone else for themselves)
    function f:MakeClickable()
        self:EnableMouse(true)
        self:SetScript("OnMouseUp", function(s) Admin.ShowLogoStudio(s) end)
        self:SetScript("OnEnter", function(s)
            K.ShowTip(s, { Admin.BrandText(), L["Click: choose style and font"] })
        end)
        self:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    f.fixedCfg = fixedCfg
    logos[f] = true
    f:Apply()
    return f
end

-- What this player sees: guild setting, possibly with their own logo font
function Admin.DisplayCfg()
    local cfg = Admin.Cfg()
    local s = ns.db and ns.db.settings or {}
    local mine = s.logoFont and K.fontByKey[s.logoFont] and s.logoFont
    local c = {}
    for k, v in pairs(cfg) do c[k] = v end
    if mine then c.lfont = mine end
    -- Everyone picks the logo style themselves (Settings / click the logo); without a choice: automatic
    c.logo = (s.logoMode == "oasis" or s.logoMode == "text") and s.logoMode or nil
    return c
end
function Admin.SetLogoMode(mode)
    ns.db.settings.logoMode = mode   -- nil = automatic
    Admin.ApplyBrand(true)
    ns.RefreshPage("settings")
end

function Admin.ShowLogoFontMenu(owner)
    local s = ns.db.settings
    local cur = s.logoFont
    local items = {}
    -- Lettering style (just for you)
    local style = Admin.LogoStyle()
    for _, d in ipairs(Admin.LOGO_STYLES) do
        items[#items + 1] = { text = L[d.text], checked = style == d.key, fn = function()
            s.logoStyle = d.key ~= "soft" and d.key or nil
            Admin.ApplyBrand(true)
        end }
    end
    items[#items + 1] = { text = L["Wide letter spacing"], checked = s.logoTrack ~= false, fn = function()
        if s.logoTrack == false then s.logoTrack = nil else s.logoTrack = false end
        Admin.ApplyBrand(true)
    end }
    items[#items + 1] = { text = L["Font"], header = true }
    items[#items + 1] = { text = L["Default font"], checked = not cur, fn = function()
        s.logoFont = nil
        Admin.SetLogoMode(nil)
    end }
    for _, ft in ipairs(K.PickFonts()) do
        items[#items + 1] = { text = ft.text, font = ft.path, checked = cur == ft.key, fn = function()
            s.logoFont = ft.key
            Admin.SetLogoMode(nil)
        end }
    end
    -- Lettering, subtitle and color are set by the guild leadership for everyone
    items[#items + 1] = { text = "|cff888888" .. L["Logo settings ..."] .. "|r", fn = function()
        if ns.OpenSettingsTab then ns.OpenSettingsTab("look") end
    end }
    K.ShowMenu(owner, items, L["Logo style - only for you"], 200)
end

-- Distribute changes: logos, navigation, accent color
local lastSig
function Admin.ApplyBrand(force)
    local cfg = Admin.Cfg()
    local sig = (cfg.u or 0) .. (cfg.by or "") .. tostring(Admin.GuildName()) .. tostring(Admin.DemoGuildName()) .. tostring(Admin.CanManage()) .. tostring(ns.db.settings.accent) .. tostring(ns.db.settings.logoFont) .. tostring(ns.db.settings.logoMode)
    if not force and sig == lastSig then return end
    lastSig = sig
    if K.ApplyTheme then K.ApplyTheme() end   -- Design palette before the accent color
    Admin.ApplyAccent(Admin.EffectiveAccent(cfg))
    -- force = appearance changed: rebuild even with the same accent color
    -- (previously e.g. "Hoher Kontrast" stayed invisible without /reload because ApplyAccent had nothing to do)
    if force then Admin.ScheduleRebuild() end
    for lg in pairs(logos) do if not lg.fixedCfg then pcall(lg.Apply, lg) end end
    ns.Fire("BRAND", cfg)
end

------------------------------------------------------------------------
-- Announcements
------------------------------------------------------------------------
function Admin.Notices()
    local g = Admin.GuildName()
    local out = {}
    if not g then return out end
    for _, r in ipairs(Store.List("notices", function(r) return r.g == g end)) do
        if Admin.Trusted(r.by) ~= false then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end
-- newest announcement of the last 3 days (for the overview)
function Admin.LatestNotice()
    local n = Admin.Notices()[1]
    if n and ns.now() - (n.ts or 0) < 3 * 86400 and Admin.Trusted(n.by) then return n end
end
function Admin.SendNotice(title, text, important, toChat)
    local g = Admin.GuildName()
    if not g or not Admin.CanManage() then return false end
    title = (title or ""):sub(1, 60)
    text = (text or ""):sub(1, 200)
    if title == "" and text == "" then return false end
    Store.Put("notices", { id = ns.newId("note"), kind = "notice", g = g, title = title, text = text, imp = important and true or false, ts = ns.now() })
    if toChat then
        local msg = "[Oasis] " .. (title ~= "" and (title .. (text ~= "" and ": " or "")) or "") .. text
        ns.SendChat(msg:sub(1, 250), "GUILD")
    end
    return true
end

local pendingNotes = {}
local function announce(rec)
    ns.db.seenNotices = ns.db.seenNotices or {}
    if ns.db.seenNotices[rec.id] then return end
    local trust = Admin.Trusted(rec.by)
    if trust == nil then pendingNotes[rec.id] = rec return end
    pendingNotes[rec.id] = nil
    if not trust then return end
    ns.db.seenNotices[rec.id] = ns.now()
    if ns.isMe(rec.by) or ns.now() - (rec.ts or 0) > 3 * 86400 then return end
    local title = (rec.title or "") ~= "" and rec.title or L["Announcement"]
    K.Toast((rec.imp and "! " or "") .. title, ((rec.text or "") ~= "" and (rec.text .. "  ") or "") .. "|cff888888- " .. ns.displayName(rec.by) .. "|r",
        rec.imp and C.red or C.accent, function() ns.ShowPage("home") end, rec.imp and "alert" or "announce")
end

ns.Listen("STORE", function(name, rec, old)
    if name == "guildcfg" then
        memo = nil
        Admin.ApplyBrand()
        ns.RefreshPage("admin")
    elseif name == "notices" and not old and not rec.del then
        if rec.g == Admin.GuildName() then announce(rec) end
        ns.RefreshPage("admin")
        ns.RefreshPage("home")
    end
end)
ns.Listen("ROSTER", function()
    memo = nil
    Admin.ApplyBrand()
    for _, rec in pairs(pendingNotes) do announce(rec) end
end)
ns.Listen("LOGIN", function()
    Admin.ApplyBrand(true)
    ns.On("PLAYER_GUILD_UPDATE", function() memo = nil Admin.ApplyBrand() end)
end)

------------------------------------------------------------------------
-- Oasis versions
------------------------------------------------------------------------
local function verNum(v)
    local a, b, c = tostring(v or ""):match("(%d+)%.?(%d*)%.?(%d*)")
    if not a then return 0 end
    -- same calculation as Radar.VerNum (0.4.1 > 0.3.347)
    return tonumber(a) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end
Admin.VerNum = verNum
function Admin.Usage()
    local newest = ns.version
    for _, p in pairs(ns.db.members) do
        if p.v and verNum(p.v) > verNum(newest) then newest = p.v end
    end
    local rows, stats = {}, { total = 0, oasis = 0, online = 0, onlineOasis = 0, old = 0 }
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local p = ns.db.members[m.name]
        local recent = p and (ns.isMe(m.name) or ns.now() - (p.seen or 0) < 14 * 86400)
        local v = recent and (ns.isMe(m.name) and ns.version or p.v) or nil
        local row = { m = m, v = v, seen = p and p.seen, old = v and verNum(v) < verNum(newest) }
        rows[#rows + 1] = row
        stats.total = stats.total + 1
        if v then stats.oasis = stats.oasis + 1 end
        if m.online then
            stats.online = stats.online + 1
            if v and (ns.isMe(m.name) or ns.Radar.HasAddon(m.name)) then stats.onlineOasis = stats.onlineOasis + 1 end
        end
        if row.old then stats.old = stats.old + 1 end
    end
    stats.newest = newest
    return rows, stats
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local TABS = {
    -- 0.5.781: re-sorted and in plain language - everyday things first (start, members, announcements, events), then raid/chat, setup last
    { key = "start", text = "Start" },
    { key = "overview", text = "Members" },
    { key = "members", text = "Guild care" },
    { key = "notices", text = "Announcements" },
    { key = "events", text = "Events" },
    { key = "raidtools", text = "Raid" },
    { key = "ochat", text = "Officer chat" },   -- only visible with officer chat permission
    { key = "modules", text = "Sections" },
    { key = "rights", text = "Permissions" },
    { key = "tools", text = "Log" },
}

-- 0.6.537: tabs merged into 6 sections (previously 14 side by side, too much for beginners and too wide).
-- A section with several parts gets a second, small tab row below. Unknown tabs (from modules) stay separate sections.
local GROUPS = {
    { key = "g_today", text = "Today", kids = { "today", "start" } },
    { key = "g_members", text = "Members", kids = { "overview", "members" }, sub = { overview = "List", members = "Guild care" } },
    { key = "g_news", text = "Announce", kids = { "notices", "events", "media" } },
    { key = "g_raid", text = "Raid", kids = { "raidtools" } },
    { key = "g_off", text = "Officers", kids = { "ochat", "decide" }, sub = { decide = "Vote" } },
    { key = "g_set", text = "Settings", kids = { "modules", "rights", "tools" } },
}
local GROUP_OF = {}
for _, g in ipairs(GROUPS) do for _, k in ipairs(g.kids) do GROUP_OF[k] = g end end

local page
local draft
-- 0.6.526: modules can contribute tabs (guild management: "Heute", "Entscheiden"); pos = position in the tab bar
local HELP_EXTRA = {}
function Admin.AddTab(key, text, build, refresh, help, pos)
    for _, t in ipairs(TABS) do if t.key == key then return end end
    -- "Heute" replaces the old start page with the tiles (tab bar too full otherwise)
    if key == "today" then for i, t in ipairs(TABS) do if t.key == "start" then table.remove(TABS, i) break end end end
    table.insert(TABS, math.max(1, math.min(pos or #TABS + 1, #TABS + 1)), { key = key, text = text })
    Admin.EXTRA_BUILD = Admin.EXTRA_BUILD or {}
    Admin.EXTRA_BUILD[key] = { build = build, refresh = refresh }
    HELP_EXTRA[key] = help
end
local function copyCfg(c)
    local t = {}
    for k in pairs(DEFAULTS) do t[k] = c[k] end
    return t
end
local function dirty()
    if not draft then return false end
    local cur = Admin.Cfg()
    for k in pairs(DEFAULTS) do
        if tostring(draft[k]) ~= tostring(cur[k]) then return true end
    end
    return false
end

local function section(p, text, x, y, w)
    local h = K.Header(p, text)
    h:SetPoint("TOPLEFT", x, y)
    h:SetWidth(w or 300)
    return h
end
local function label(p, text, x, y, w)
    local fs = K.Text(p, 12, C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    if w then fs:SetWidth(w) fs:SetWordWrap(true) end
    fs:SetText(text)
    return fs
end

-- shared bar at the bottom: save / discard changes
-- readable names of the guild settings (for "what changed")
local KEYNAMES = { off = "Modules", logo = "Logo", ltext = "Wordmark", lfont = "Logo font", lcol = "Logo colour",
    lsize = "Logo size", xp2 = "XP weekend", crest = "Guild crest", crestc = "Crest colour", xp2s = "XP weekend (start)",
    vis = "Module visibility", nob = "News counters", lup = "Upper case", lsub = "Subtitle",
    acc = "Guild colour", rank = "Leadership from rank", inv = "Message members without Oasis", dlink = "Discord link",
    crown = "Crown for everyone" }
local function changedKeys()
    local out = {}
    if not draft then return out end
    local cur = Admin.Cfg()
    for k in pairs(DEFAULTS) do
        if tostring(draft[k]) ~= tostring(cur[k]) then
            local gd = ns.GuildOptsByKey and ns.GuildOptsByKey[k]
            local pd = gd and ns.PageDef(gd.page)
            out[#out + 1] = gd and ((pd and (L[pd.title] .. ": ") or "") .. L[gd.label]) or L[KEYNAMES[k] or k]
        end
    end
    table.sort(out)
    return out
end
local function buildSaveBar(p)
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("BOTTOMLEFT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetHeight(38)
    bar:SetFrameLevel(p:GetFrameLevel() + 40)
    bar.bg = K.Fill(bar, { 0, 0, 0, 0 })
    bar.edge = bar:CreateTexture(nil, "ARTWORK")
    bar.edge:SetPoint("TOPLEFT") bar.edge:SetPoint("BOTTOMLEFT") bar.edge:SetWidth(3)
    local line = K.Divider(bar)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    bar.dot = bar:CreateTexture(nil, "OVERLAY")
    bar.dot:SetTexture(ns.MEDIA .. "dot")
    bar.dot:SetSize(9, 9)
    bar.dot:SetPoint("LEFT", 12, -2)
    bar.state = K.Text(bar, 12, C.muted)
    bar.state:SetPoint("LEFT", bar.dot, "RIGHT", 8, 0)
    bar.state:SetPoint("RIGHT", bar, "RIGHT", -320, 0)
    bar.state:SetWordWrap(false)
    -- List of changes on hover
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        local ch = changedKeys()
        if #ch == 0 then return end
        local lines = { L["Not yet applied for the guild:"] }
        for _, n in ipairs(ch) do lines[#lines + 1] = "|cffffc24d-|r " .. n end
        K.ShowTip(self, lines, "ANCHOR_TOP")
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- blinking dot while something is unsaved
    bar:SetScript("OnUpdate", function(self)
        if not self.dirtyNow then return end
        self.dot:SetAlpha(0.55 + 0.45 * math.sin(GetTime() * 4))
    end)
    -- Leaving the page with unsaved changes: short reminder
    p:HookScript("OnHide", function()
        if dirty() and not ns.rebuilding then
            K.Toast(L["Guild leadership"], L["Unsaved changes - not yet applied for the guild."], C.amber,
                function() ns.ShowPage("admin") end)
        end
    end)
    bar.save = K.Button(bar, L["Apply for the guild"], 210, 26, "primary", function()
        if Admin.Save(draft) then
            draft = copyCfg(draft)
            if Admin.TestMode() then
                -- others check the real guild rank: the guild takes nothing from test mode
                K.Toast(L["Saved only for you"], L["Test mode: others only accept changes from real officers / the guild master."], C.amber)
            else
                K.Toast(L["Saved"], L["Applies to everyone with Oasis right away."], C.mint)
            end
            Admin.ApplyBrand(true)
        end
        ns.RefreshPage("admin")
    end)
    bar.save:SetPoint("RIGHT", -6, -2)
    bar.reset = K.Button(bar, L["Discard"], 100, 26, "ghost", function()
        draft = copyCfg(Admin.Cfg())
        page.rebuildDraftViews()
        ns.RefreshPage("admin")
    end)
    bar.reset:SetPoint("RIGHT", bar.save, "LEFT", -8, 0)
    function bar:Update()
        local d = dirty()
        self.dirtyNow = d
        self.save:SetEnabledState(d)
        self.reset:SetEnabledState(d)
        local n = #changedKeys()
        self.save:SetLabel(d and (L["Apply for the guild"] .. "  (" .. n .. ")") or L["Apply for the guild"])
        local dc = d and C.amber or (Admin.TestMode() and C.amber or C.mint)
        self.dot:SetVertexColor(dc[1], dc[2], dc[3])
        self.dot:SetAlpha(1)
        self.edge:SetColorTexture(dc[1], dc[2], dc[3], d and 0.9 or 0)
        self.bg:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], d and 0.10 or 0)
        local cur = Admin.Cfg()
        if d then
            self.state:SetText(K.hex(C.amber) .. ((n == 1) and L["1 unsaved change"] or (L["%d unsaved changes"]):format(n)) .. "|r  |cff999999"
                .. L["- the guild only sees them after applying"] .. "|r")
        elseif Admin.TestMode() then
            self.state:SetText(K.hex(C.amber) .. L["Test mode: changes apply only for you, not for the guild."] .. "|r")
        elseif cur.by then
            self.state:SetText((L["Last changed by %s, %s"]):format(ns.displayName(cur.by), ns.ago(cur.u)))
        else
            self.state:SetText(L["Still default settings."])
        end
    end
    return bar
end

------------------------------------------------------------------------
-- Tab: Overview
------------------------------------------------------------------------
-- Member list columns as a fraction of the width: adapts, overlong text is truncated with "..."
local OV_COLS = {
    { key = "rank", text = "Rank", w = 0.13 },
    { key = "name", text = "Name", w = 0.21 },
    { key = "lvl", text = "Lvl", w = 0.05, justify = "CENTER" },
    { key = "note", text = "Note", w = 0.26 },
    { key = "ver", text = "Oasis", w = 0.13 },
    { key = "seen", text = "Last online", w = 0.19 },   -- Rest of the width: map icon
}
local OV_X0 = 44   -- Room for online dot + Oasis rank emblem
local function layoutCols(frame, cols, width)
    local x, avail = OV_X0, math.max(200, (width or 700) - OV_X0 - 8)
    for _, c in ipairs(OV_COLS) do
        local fs = cols[c.key]
        local w = math.floor(avail * c.w)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", frame, "LEFT", x, 0)
        fs:SetWidth(w - 8)
        fs:SetWordWrap(false)
        x = x + w
    end
end

local function buildOverview(f)
    -- Tiles like on the overview: icon, number (counts up), bar
    local TILES = {
        { ns.ICONS.radar, "Members", C.blue },
        { ns.ICONS.home, "With Oasis", C.accent },
        { ns.ICONS.deaths or ns.ICONS.radar, "Inactive", C.amber },
        { ns.ICONS.badges or ns.ICONS.radar, "New", C.mint },
    }
    local CLICK = { [1] = "online", [2] = "without", [3] = "inactive", [4] = "new" }
    f.cards = {}
    for i, d in ipairs(TILES) do
        local t = K.HudTile(f, d[1], L[d[2]], d[3], CLICK[i] and function()
            f.filter = CLICK[i]
            f.seg:Select(CLICK[i])
            ns.RefreshPage("admin")
        end or nil)
        t:SetHeight(66)
        f.cards[i] = t
    end
    local function layoutTiles(w)
        local gap = 10
        local tw = math.floor((w - gap * (#f.cards - 1)) / #f.cards)
        for i, t in ipairs(f.cards) do
            t:ClearAllPoints()
            t:SetWidth(tw)
            t:SetPoint("TOPLEFT", (i - 1) * (tw + gap), 0)
            -- Label must not overflow the tile
            t.label:SetWidth(math.max(40, tw - 50))
            t.label:SetWordWrap(false)
        end
    end

    f.filter = "all"
    f.seg = K.Segments(f, {
        { key = "all", text = L["All"] }, { key = "online", text = L["Online"] }, { key = "inactive", text = L["Inactive"] },
        { key = "new", text = L["New"] }, { key = "without", text = L["Without Oasis"] },
        { key = "old", text = L["Old Oasis"] }, { key = "lead", text = L["Leaders"] },
    }, function(k) f.filter = k ns.RefreshPage("admin") end, nil, { size = 12, pad = 14 })
    f.seg:SetPoint("TOPLEFT", 0, -80)
    -- Search over name and notes
    f.search = K.Input(f, 150, L["Name or note ..."], function(t) f.q = (t or ""):lower() ns.RefreshPage("admin") end)
    f.search:SetPoint("TOPRIGHT", 0, -78)
    -- Hide alts: show mains only (remembered; alts = characters assigned to another main)
    f.altBtn = K.Button(f, "", 110, 22, "ghost", function()
        local st = ns.db.settings
        st.adminHideAlts = not st.adminHideAlts or nil
        ns.RefreshPage("admin")
    end)
    f.altBtn:SetPoint("RIGHT", f.search, "LEFT", -8, 0)
    f.altBtn:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Hide alts"], L["Shows mains only. Alts are characters assigned to another main."] }) end)
    f.altBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- select all in the current view (e.g. set all inactive members to one rank at once)
    f.selAll = K.Button(f, L["Select all"], 110, 22, "ghost", function()
        for _, it in ipairs(f.lastOut or {}) do if not ns.isMe(it.m.name) then f.selected[it.m.name] = true end end
        ns.RefreshPage("admin")
    end)
    f.selAll:SetPoint("TOPLEFT", 0, -108)

    -- running XP weekend as a notice on the right (start it: tab Guild events)
    f.xpTag = K.Text(f, 11, C.amber, "RIGHT")
    f.xpTag:SetPoint("TOPRIGHT", 0, -108)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 0, -138)
    head:SetPoint("TOPRIGHT", 0, -138)
    head:SetHeight(18)
    head.cols = {}
    -- Column headers clickable: sort (click again = reverse)
    f.sortKey, f.sortDesc = nil, false
    local function updateHead()
        for _, c in ipairs(OV_COLS) do
            local fs = head.cols[c.key]
            local on = f.sortKey == c.key
            fs:SetText(K.Upper(L[c.text]) .. (on and (f.sortDesc and "  v" or "  ^") or ""))
            local col = on and C.accent or C.dim
            fs:SetTextColor(col[1], col[2], col[3])
        end
    end
    for _, c in ipairs(OV_COLS) do
        local fs = K.Text(head, 10, C.dim, c.justify)
        head.cols[c.key] = fs
        local b = CreateFrame("Button", nil, head)
        b:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 4)
        b:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -4)
        b:SetScript("OnClick", function()
            if f.sortKey == c.key then f.sortDesc = not f.sortDesc else f.sortKey, f.sortDesc = c.key, false end
            updateHead()
            ns.RefreshPage("admin")
        end)
        b:SetScript("OnEnter", function(self)
            fs:SetTextColor(C.text[1], C.text[2], C.text[3])
            K.ShowTip(self, { L[c.text], "|cff888888" .. L["Click: sort by this"] .. "|r" })
        end)
        b:SetScript("OnLeave", function() updateHead() GameTooltip:Hide() end)
    end
    updateHead()
    f.head = head

    f.list = K.List(f, 26, function(l)
        local r = K.Row(l)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetTexture(ns.MEDIA .. "dot")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("LEFT", 4, 0)
        -- Oasis rank in front: frame per rank (as in the member list) with rank number
        r.remblem = K.RankEmblem(r, 20)
        r.remblem:SetPoint("CENTER", r, "LEFT", 27, 0)
        r.remblem:SetFrameLevel(r:GetFrameLevel() + 2)
        r:Col("rank", 0, 100, 12, C.muted)
        r:Col("name", 0, 100, 12)
        r:Col("lvl", 0, 40, 12, C.muted, "CENTER")
        r:Col("note", 0, 80, 11, C.muted)
        -- everything about the person at a glance (notes, main, join date, pace)
        r:HookScript("OnEnter", function(self)
            local m = self.item and self.item.m
            if not m then return end
            local lines = { ns.colorName(m.name, m.class) .. "  |cff999999" .. (m.rank or "") .. "|r" }
            if (m.note or "") ~= "" then lines[#lines + 1] = "|cffaaaaaa" .. L["Note"] .. ":|r " .. m.note end
            local canO = ns.Members and ns.Members.CanSeeOfficerNote and ns.Members.CanSeeOfficerNote()
            if canO and (m.onote or "") ~= "" then lines[#lines + 1] = "|cffff7a5c" .. L["Officer note"] .. ":|r " .. m.onote end
            local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(m.name)
            if main and main ~= m.name then lines[#lines + 1] = "|cffaaaaaa" .. L["Alt of"] .. "|r " .. ns.displayName(main) end
            local j = ns.Welcome and ns.Welcome.JoinedAt and ns.Welcome.JoinedAt(m.name)
            if j then lines[#lines + 1] = "|cffaaaaaa" .. L["Joined"] .. ":|r " .. date("%d.%m.%Y", j) end
            local g = ns.Members and ns.Members.LevelGain and ns.Members.LevelGain(m.name, 7, m.level)
            if g and g > 0 then lines[#lines + 1] = "|cff66db9e+" .. g .. "|r " .. L["levels in 7 days"] end
            lines[#lines + 1] = "|cff777777" .. L["Click: profile  ·  Right-click: rank  ·  Ctrl-click: select"] .. "|r"
            K.ShowTip(self, lines)
        end)
        r:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r:Col("ver", 0, 90, 12)
        r:Col("seen", 0, 120, 12, C.muted)
        -- Map icon on the right (online only): shows the member on the world map
        -- visible action button: same menu as right-click (change rank, whisper ...) - beginners don't find right-click
        r.act = K.Button(r, "...", 26, 18, "ghost", function()
            local m = r.item and r.item.m
            if m and ns.GuildRanks then ns.GuildRanks.MemberMenu(r.act, m) end
        end)
        r.act:SetPoint("RIGHT", -4, 0)
        r.act:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Actions"], L["Change rank, promote, demote and more"] }) end)
        r.act:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.map = CreateFrame("Button", nil, r)
        r.map:SetSize(18, 18)
        r.map:SetPoint("RIGHT", -36, 0)
        r.map.icon = K.Glyph(r.map, 14, ns.ICONS.map, C.muted)
        r.map.icon:SetPoint("CENTER")
        r.map:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            local m = r.item and r.item.m
            local exact = m and ns.Map and ns.Map.PosOf and ns.Map.PosOf(m.name, m.aname)
            K.ShowTip(self, { L["Show on map"], exact and L["Exact position (shared via Oasis)"] or ((m and m.zone ~= "" and m.zone or "?") .. "  |cff888888(" .. L["zone only"] .. ")|r") })
        end)
        r.map:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
        r.map:SetScript("OnClick", function()
            local m = r.item and r.item.m
            if m and ns.Map and ns.Map.ShowMember then ns.Map.ShowMember(m.name, m.zone, m.aname) end
        end)
        r:SetScript("OnSizeChanged", function(self, w) layoutCols(self, self.cols, w) end)
        layoutCols(r, r.cols, l:GetWidth())
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, btn)
            local it = self.item
            if not it then return end
            if btn == "RightButton" then
                if ns.GuildRanks then ns.GuildRanks.MemberMenu(self, it.m) end
            elseif IsControlKeyDown() or IsShiftKeyDown() then
                -- select for "set several to one rank"
                f.selected[it.m.name] = not f.selected[it.m.name] or nil
                ns.RefreshPage("admin")
            elseif ns.Profile then
                ns.Profile.Show(it.m.name)
            end
        end)
        return r
    end, function(r, it)
        r.sel:SetShown(f.selected[it.m.name] and true or false)
        local m = it.m
        local dc = m.online and C.mint or C.dim
        r.dot:SetVertexColor(dc[1], dc[2], dc[3])
        -- Oasis rank (only those who have Oasis)
        local orl = it.v and ns.Rank and ns.Rank.Of and (ns.Rank.Of(m.name))
        if orl then r.remblem:SetRank(orl) else r.remblem:Hide() end
        -- offline: greyed out (name without class color, whole row paler)
        r.cols.name:SetText(m.online and ns.colorName(m.name, m.class) or ("|cff8a8a8a" .. ns.displayName(m.name) .. "|r"))
        r.cols.rank:SetText(m.rank or "")
        r.cols.lvl:SetText(m.level or "")
        -- Note: alt hint, public note, marker for officer note
        local parts = {}
        local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(m.name)
        if main and main ~= m.name then parts[#parts + 1] = "|cff8fb3ff" .. L["Alt"] .. ":|r " .. ns.displayName(main) end
        if (m.note or "") ~= "" then parts[#parts + 1] = m.note end
        local canO = ns.Members and ns.Members.CanSeeOfficerNote and ns.Members.CanSeeOfficerNote()
        local oTag = (canO and (m.onote or "") ~= "") and "|cffff7a5cO|r  " or ""
        r.cols.note:SetText(oTag .. table.concat(parts, "  ·  "))
        r:SetAlpha(m.online and 1 or 0.55)
        r.map:SetShown(m.online and ns.Map ~= nil and not ns.isMe(m.name))
        if it.v then
            r.cols.ver:SetText((it.old and (K.hex(C.amber) .. it.v .. "  " .. L["old"]) or (K.hex(C.mint) .. it.v)) .. "|r")
        else
            -- no Oasis: red X
            r.cols.ver:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t")
        end
        -- Last seen: online = zone, offline = when last seen (from the guild roster)
        if ns.isMe(m.name) then
            r.cols.seen:SetText(L["that's you"])
        elseif m.online then
            r.cols.seen:SetText("|cff66db9e" .. L["online"] .. "|r" .. ((m.zone or "") ~= "" and ("  ·  " .. m.zone) or ""))
        elseif m.offDays then
            r.cols.seen:SetText(m.offDays < 1 and L["today"] or (L["%d d ago"]):format(m.offDays))
        else
            r.cols.seen:SetText(it.seen and ns.ago(it.seen) or "|cff555555-|r")
        end
    end)
    -- Multi-select: bar appears as soon as someone is selected
    f.selected = {}
    f.bulk = K.Button(f, "", 230, 24, "primary", function(self)
        local GR = ns.GuildRanks
        if not GR then return end
        local names, n = Admin.RankNames()
        local sel = {}
        for name in pairs(f.selected) do sel[#sel + 1] = name end
        local items = { { text = (L["%d selected - set rank"]):format(#sel), header = true } }
        for i = 1, n - 1 do
            items[#items + 1] = { text = (i + 1) .. ".  " .. (names[i] or "?"), fn = function()
                GR.Confirm((L["Set %d members to rank \"%s\"?"]):format(#sel, names[i] or "?"), function()
                    GR.SetRankMany(sel, i, function(cnt)
                        K.Toast(L["Ranks set"], (L["%d members -> %s"]):format(cnt, names[i] or "?"), C.mint)
                    end)
                    f.selected = {}
                    ns.RefreshPage("admin")
                end)
            end }
        end
        items[#items + 1] = { text = L["Clear selection"], fn = function() f.selected = {} ns.RefreshPage("admin") end }
        K.ShowMenu(self, items, nil, 240)
    end)
    f.bulk.isDropdown = true
    f.bulk:SetPoint("TOPLEFT", 0, -108)
    f.bulk:Hide()
    f.selHint = K.Text(f, 10, C.dim, "RIGHT")
    f.selHint:SetPoint("TOPRIGHT", 0, -108)
    f.list:SetPoint("TOPLEFT", 0, -158)
    f.list:SetPoint("BOTTOMRIGHT", 0, 0)
    f.list.empty:SetText(L["No members in this view."])

    local function layout()
        local w = f:GetWidth() or 750
        if w < 10 then w = 750 end
        layoutTiles(w)
        layoutCols(head, head.cols, w)
    end
    f:SetScript("OnSizeChanged", layout)
    layout()
    f.fresh = true
    f:SetScript("OnShow", function(self) self.fresh = true end)
end
local function refreshOverview(f)
    local nsel = 0
    for _ in pairs(f.selected) do nsel = nsel + 1 end
    f.bulk:SetShown(nsel > 0)
    f.bulk:SetLabel((L["%d selected: set rank"]):format(nsel))
    f.selHint:SetShown(nsel == 0)
    f.selHint:SetText(L["Button ... on the right: change rank  ·  Ctrl-click: select several"])
    f.xpTag:SetShown(false)
    local until2 = ns.Rewards and ns.Rewards.DoubleUntil()
    f.xpTag:SetText(until2 and ("2x XP  ·  " .. (L["%d h left"]):format(math.ceil((until2 - ns.now()) / 3600))) or "")
    local rows, st = Admin.Usage()
    local anim = f.fresh
    f.fresh = false
    local share = st.total > 0 and st.oasis / st.total or 0
    f.cards[1]:Set(st.total, (L["%d online"]):format(st.online), nil, anim)
    -- With Oasis: count large, next to it share + how many of them are online right now; outdated ones only as a hint
    local sub = math.floor(share * 100 + 0.5) .. " %"
    if st.old > 0 then sub = sub .. "  ·  " .. K.hex(C.amber) .. (L["%d outdated"]):format(st.old) .. "|r" end
    f.cards[2]:Set(st.oasis, sub, share, anim)
    local tip = { L["With Oasis"], (L["%d of %d members (last 14 days)"]):format(st.oasis, st.total),
        (L["Online now: %d with Oasis of %d"]):format(st.onlineOasis, st.online) }
    if st.old > 0 then
        tip[#tip + 1] = K.hex(C.amber) .. (L["%d on an old version - newest: v%s"]):format(st.old, st.newest or ns.version) .. "|r"
    end
    tip[#tip + 1] = "|cff888888" .. L["Click: show everyone without Oasis"] .. "|r"
    f.cards[2].tip = tip
    local inactDays = ns.db.settings.inactiveDays or 30
    local function isInactive(m) return not m.online and (m.offDays or 0) >= inactDays end
    local function isNew(m) return ns.Welcome and ns.Welcome.IsNew and ns.Welcome.IsNew(m.name) end
    local nIn, nNew = 0, 0
    for _, it in ipairs(rows) do
        if isInactive(it.m) then nIn = nIn + 1 end
        if isNew(it.m) then nNew = nNew + 1 end
    end
    f.cards[3]:Set(nIn, (L["offline %d+ days"]):format(inactDays), st.total > 0 and nIn / st.total or 0, anim)
    f.cards[3].tip = { L["Inactive"], (L["Not online for at least %d days. Set the limit under Settings > Sections > Members."]):format(inactDays),
        "|cff888888" .. L["Click: show only these"] .. "|r" }
    f.cards[4]:Set(nNew, L["new in the guild"], st.total > 0 and nNew / st.total or 0, anim)
    f.cards[4].tip = { L["New"], L["Recently joined - a good moment to say hello."], "|cff888888" .. L["Click: show only these"] .. "|r" }
    local lead = Admin.LeaderRank()
    local q = f.q or ""
    local out = {}
    local hideAlts = ns.db.settings.adminHideAlts and ns.Alts and ns.Alts.IsAlt and true or false
    local nAlts = 0
    for _, it in ipairs(rows) do
        local m = it.m
        local ok = f.filter == "all" or (f.filter == "online" and m.online) or (f.filter == "without" and not it.v) or (f.filter == "old" and it.old)
            or (f.filter == "lead" and (m.rankIndex or 99) <= lead) or (f.filter == "inactive" and isInactive(m)) or (f.filter == "new" and isNew(m))
        if ok and q ~= "" then
            local hay = (ns.displayName(m.name) .. " " .. (m.note or "") .. " " .. (m.onote or "")):lower()
            ok = hay:find(q, 1, true) ~= nil
        end
        if ok and hideAlts then
            local okA, alt = pcall(ns.Alts.IsAlt, m.name)
            if okA and alt then ok = false nAlts = nAlts + 1 end
        end
        if ok then out[#out + 1] = it end
    end
    if f.altBtn then
        f.altBtn:SetLabel(hideAlts and ("|cff66db9e" .. L["Alts: off"] .. "|r" .. (nAlts > 0 and (" |cff888888" .. nAlts .. "|r") or "")) or L["Alts: on"])
    end
    f.lastOut = out
    f.selAll:SetShown(nsel == 0 and f.filter ~= "all" and #out > 0)
    -- Sort value per column (default: online first, then with Oasis, then name)
    local function profCount(m)
        local pr = ns.db.members[m.name]
        local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
        return ns.Radar and #ns.Radar.decodeProfs(raw) or 0
    end
    local KEYS = {
        rank = function(it) return it.m.rankIndex or 99 end,
        name = function(it) return ns.short(it.m.name):lower() end,
        lvl = function(it) return it.m.level or 0 end,
        note = function(it) return (it.m.note or ""):lower() end,
        ver = function(it) return it.v and verNum(it.v) or -1 end,
        seen = function(it) return it.m.online and -1 or (it.m.offDays or 9999) end,
    }
    local key = f.sortKey and KEYS[f.sortKey]
    table.sort(out, function(a, b)
        if key then
            local x, y = key(a), key(b)
            if x ~= y then
                if f.sortDesc then return x > y end
                return x < y
            end
            return a.m.name < b.m.name
        end
        if a.m.online ~= b.m.online then return a.m.online end
        if (a.v ~= nil) ~= (b.v ~= nil) then return a.v ~= nil end
        return a.m.name < b.m.name
    end)
    f.list:SetData(out)
end

------------------------------------------------------------------------
-- Card widget (like overview/profile): color bar on the left, slight glow, icon, title
------------------------------------------------------------------------
local function card(parent, icon, title, color)
    color = color or C.accent
    -- 0.5.784: glass card as in the settings (calm, rounded corners) - without color bar and glow, title in normal case
    local c = CreateFrame("Frame", nil, parent)
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 12)) then
        K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
    end
    c.icon = K.Glyph(c, 18, icon, color)
    c.icon:SetPoint("TOPLEFT", 14, -12)
    c.title = K.Title(c, 14, C.text)
    c.title:SetPoint("LEFT", c.icon, "RIGHT", 9, 0)
    c.title:SetPoint("RIGHT", c, "RIGHT", -34, 0)
    c.title:SetText(title)
    return c
end
-- small label above an input field (beginners immediately see what goes in)
local function fieldLabel(c, text, x, y)
    local t = K.Text(c, 10, C.dim)
    t:SetPoint("TOPLEFT", x, y)
    t:SetText(text)
    return t
end
-- small "?" at the top right of a card: explanation as a tooltip instead of long text
local function helpTip(c, lines)
    local h = CreateFrame("Frame", nil, c)
    h:SetSize(18, 18)
    h:SetPoint("TOPRIGHT", -8, -9)
    h.t = K.Text(h, 12, C.dim, "CENTER")
    h.t:SetPoint("CENTER")
    h.t:SetText("?")
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, lines) end)
    h:SetScript("OnLeave", function(self) self.t:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
    return h
end
-- Description of a button as a tooltip
local function hoverTip(frame, lines)
    frame:HookScript("OnEnter", function(self) K.ShowTip(self, lines) end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"

------------------------------------------------------------------------
-- Tab: Modules
------------------------------------------------------------------------
local function buildModules(f)
    -- compact: one row per module (toggle, icon, name); description as a tooltip
    local intro = label(f, L["Per-module settings for the whole guild - hiding sections is done by everyone in their own settings."], 0, 0)
    intro:SetPoint("RIGHT", f, "RIGHT", -24, 0)
    intro:SetWordWrap(false)
    local info = CreateFrame("Frame", nil, f)
    info:SetSize(16, 16)
    info:SetPoint("TOPRIGHT", 0, 0)
    info.t = K.Text(info, 13, C.dim, "CENTER")
    info.t:SetPoint("CENTER")
    info.t:SetText("?")
    info:EnableMouse(true)
    info:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["Modules"], L["Click a module: who sees it (from rank) and whether news counters appear."],
            L["Every member can hide sections themselves under Settings."], "|cff888888" .. L["Changes only apply after saving below."] .. "|r" })
    end)
    info:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.toggles, f.heads = {}, {}
    -- Modules by navigation groups (like "Bereiche" in the settings);
    -- pages that don't exist on their own (e.g. Oasis rank in the profile) are left out
    local groups, seen = {}, {}
    local function usable(def)
        return def and not Admin.LOCKED[def.key] and not (def.visible and not def.visible())
    end
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        local items = {}
        for _, k in ipairs(g.pages) do
            local def = ns.PageDef(k)
            if usable(def) then items[#items + 1] = def seen[k] = true end
        end
        -- Subpages (reservations under Raid ...)
        for _, def in ipairs(ns.Pages()) do
            if def.parent and not seen[def.key] and usable(def) then
                for _, it in ipairs(items) do
                    if it.key == def.parent then items[#items + 1] = def seen[def.key] = true break end
                end
            end
        end
        if #items > 0 then groups[#groups + 1] = { text = g.text, items = items } end
    end
    local rest = {}
    for _, def in ipairs(ns.Pages()) do
        if not seen[def.key] and usable(def) and not def.topbar then rest[#rest + 1] = def end
    end
    if #rest > 0 then groups[#groups + 1] = { text = "More", items = rest } end
    local ROW = 28
    -- scrollable area: with many modules (Raid has ~13 subpages) the list otherwise ran out of the window
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -24)
    sf:SetPoint("BOTTOMRIGHT", -22, 4)
    local list = CreateFrame("Frame", nil, sf)
    list:SetSize(700, 10)
    sf:SetScrollChild(list)
    f.modScroll, f.modList = sf, list
    for _, gr in ipairs(groups) do
        local h = K.Text(list, 10, C.dim)
        h:SetText(K.Upper(L[gr.text]))
        h.line = K.Divider(list)
        local rows = {}
        for _, def in ipairs(gr.items) do
            local t = CreateFrame("Button", nil, list)
            t:SetHeight(ROW - 4)
            t.bg = K.Fill(t, C.raised)
            t.hl = t:CreateTexture(nil, "HIGHLIGHT")
            t.hl:SetAllPoints()
            t.hl:SetColorTexture(1, 1, 1, 0.05)
            t.icon = K.Glyph(t, 15, ns.ICONS[def.key], C.accent)
            t.icon:SetPoint("LEFT", 10, 0)
            t.lbl = K.Text(t, 13, C.text)
            t.lbl:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
            t.lbl:SetPoint("RIGHT", t, "RIGHT", -96, 0)
            t.lbl:SetWordWrap(false)
            t.lbl:SetText(L[def.title])
            t.def = def
            t:SetScript("OnClick", function() f:OpenModule(def) end)
            function t:Refresh() end
            -- Gear: settings of this module
            t.gear = CreateFrame("Button", nil, t)
            t.gear:SetSize(22, 22)
            t.gear:SetPoint("RIGHT", t, "RIGHT", -2, 0)
            t.gear.icon = K.Glyph(t.gear, 14, ns.ICONS.settings, C.muted)
            t.gear.icon:SetPoint("CENTER")
            t.gear:SetScript("OnEnter", function(self)
                self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                K.ShowTip(self, { L[def.title], L["Click: settings for this module"] })
            end)
            t.gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
            t.gear:SetScript("OnClick", function() f:OpenModule(def) end)
            -- small hint in the row when restricted
            t.tag = K.Text(t, 10, C.amber, "RIGHT")
            t.tag:SetPoint("RIGHT", t.gear, "LEFT", -6, 0)
            -- Description on hover
            t:HookScript("OnEnter", function(self)
                K.ShowTip(self, { L[def.title], def.sub and L[def.sub] or "" })
            end)
            t:HookScript("OnLeave", function() GameTooltip:Hide() end)
            f.toggles[#f.toggles + 1] = t
            rows[#rows + 1] = t
        end
        f.heads[#f.heads + 1] = { h = h, rows = rows }
    end
    -- Distribute group blocks over three columns (each into the shortest)
    local function layout()
        local w = (f:GetWidth() or 750) - 24   -- Room for the scrollbar
        if w < 10 then w = 726 end
        list:SetWidth(w)
        local gap = 18
        local cols = w >= 620 and 3 or 2
        local cw = math.floor((w - gap * (cols - 1)) / cols)
        local colY = {}
        for i = 1, cols do colY[i] = -4 end
        for _, g in ipairs(f.heads) do
            local ci = 1
            for i = 2, cols do if colY[i] > colY[ci] then ci = i end end
            local x, y = (ci - 1) * (cw + gap), colY[ci]
            g.h:ClearAllPoints()
            g.h:SetPoint("TOPLEFT", list, "TOPLEFT", x + 2, y)
            g.h.line:ClearAllPoints()
            g.h.line:SetPoint("TOPLEFT", list, "TOPLEFT", x, y - 14)
            g.h.line:SetWidth(cw)
            y = y - 20
            for _, t in ipairs(g.rows) do
                t:ClearAllPoints()
                t:SetWidth(cw)
                t:SetPoint("TOPLEFT", list, "TOPLEFT", x, y)
                y = y - ROW
            end
            colY[ci] = y - 10
        end
        local low = 0
        for i = 1, cols do low = math.min(low, colY[i]) end
        list:SetHeight(-low + 6)
    end
    f:SetScript("OnSizeChanged", layout)
    layout()

    -- Module settings: card above the list
    local mp = card(f, ns.ICONS.settings, "", C.accent)
    mp:SetPoint("TOPLEFT", 0, -24)
    mp:SetPoint("BOTTOMRIGHT", 0, 0)
    mp:SetFrameLevel(f:GetFrameLevel() + 30)
    mp:EnableMouse(true)
    mp:Hide()
    f.mp = mp
    mp.back = K.Button(mp, "<  " .. L["Back"], 100, 24, "ghost", function() mp:Hide() end)
    mp.back:SetPoint("TOPRIGHT", -12, -8)
    mp.desc = K.Text(mp, 12, C.muted)
    mp.desc:SetPoint("TOPLEFT", 14, -44)
    mp.desc:SetPoint("RIGHT", mp, "RIGHT", -14, 0)
    mp.desc:SetWordWrap(true)
    mp.visLbl = K.Text(mp, 13, C.text)
    mp.visLbl:SetPoint("TOPLEFT", 14, -90)
    mp.visLbl:SetText(L["Visible to"])
    mp.visDesc = K.Text(mp, 11, C.muted)
    mp.visDesc:SetPoint("TOPLEFT", mp.visLbl, "BOTTOMLEFT", 0, -3)
    mp.visDesc:SetText(L["Who sees this section in the navigation (leadership always sees everything)"])
    mp.vis = K.Button(mp, "", 240, 26, "ghost", function(self)
        local names, n = Admin.RankNames()
        local cur = visMap(draft)[mp.def.key]
        local items = { { text = L["All ranks"], checked = cur == nil, fn = function() setVis(draft, mp.def.key, nil) ns.RefreshPage("admin") end } }
        for i = 0, n - 1 do
            items[#items + 1] = { text = (L["up to rank %d: %s"]):format(i + 1, names[i] or "?"), checked = cur == i,
                fn = function() setVis(draft, mp.def.key, i) ns.RefreshPage("admin") end }
        end
        K.ShowMenu(self, items, nil, 240)
    end)
    mp.vis.isDropdown = true
    mp.vis:SetPoint("TOPLEFT", 14, -128)
    mp.badge = K.Toggle(mp, L["News counters in the navigation"], function()
        return mp.def and not nobSet(draft)[mp.def.key]
    end, function(v)
        local t = nobSet(draft)
        t[mp.def.key] = (not v) or nil
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        draft.nob = table.concat(keys, ",")
        ns.RefreshPage("admin")
    end, L["Shows e.g. new messages or orders as a number next to the name"])
    mp.badge:SetWidth(420)
    mp.badge:SetPoint("TOPLEFT", 14, -176)
    -- Guild options of the module (registered by the modules): scrollable below the basic settings
    mp.optHead = K.Text(mp, 11, C.amber)
    mp.optHead:SetPoint("TOPLEFT", 14, -222)
    mp.optHead:SetText(K.Upper(L["For the whole guild"]))
    mp.optLine = K.Divider(mp)
    mp.optLine:SetPoint("TOPLEFT", 14, -238)
    mp.optLine:SetPoint("RIGHT", mp, "RIGHT", -14, 0)
    mp.osf = CreateFrame("ScrollFrame", nil, mp)
    mp.osf:SetPoint("TOPLEFT", 14, -246)
    mp.osf:SetPoint("BOTTOMRIGHT", -14, 34)
    mp.ochild = CreateFrame("Frame", nil, mp.osf)
    mp.ochild:SetSize(600, 10)
    mp.osf:SetScrollChild(mp.ochild)
    mp.osf:SetScript("OnSizeChanged", function(_, w) if w and w > 50 then mp.ochild:SetWidth(w - 8) end end)
    mp.osf:EnableMouseWheel(true)
    mp.osf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (mp.ochild:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
    mp.optWidgets = {}
    function mp:BuildOptions(key)
        for _, w in ipairs(self.optWidgets) do w:Hide() end
        self.optWidgets = {}
        local list = {}
        for _, d in ipairs(ns.GuildOpts or {}) do if d.page == key then list[#list + 1] = d end end
        self.optHead:SetShown(#list > 0)
        self.optLine:SetShown(#list > 0)
        local y = -2
        local canEdit = Admin.CanManage()
        for _, d in ipairs(list) do
            local locked = d.lead and not Admin.IsGM()
            if d.kind == "bool" then
                local t = K.Toggle(self.ochild, L[d.label], function()
                    local v = draft and draft[d.key]
                    if v == nil then v = d.default end
                    return v and true or false
                end, function(v)
                    if not draft or not canEdit or locked then return end
                    draft[d.key] = v
                    ns.RefreshPage("admin")
                end)
                t:SetPoint("TOPLEFT", 0, y)
                t:SetPoint("RIGHT", self.ochild, "RIGHT", 0, 0)
                if d.desc then
                    t:HookScript("OnEnter", function(s) K.ShowTip(s, { L[d.label], L[d.desc], locked and ("|cffffc24d" .. L["Only the guild master can change this."] .. "|r") or nil }) end)
                    t:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
                t:SetAlpha(locked and 0.5 or 1)
                self.optWidgets[#self.optWidgets + 1] = t
                y = y - 30
            elseif d.kind == "info" then
                -- display only (e.g. raid leadership overview)
                local lbl = K.Text(self.ochild, 12, C.text)
                lbl:SetPoint("TOPLEFT", 0, y - 4)
                lbl:SetWidth(230)
                lbl:SetText(L[d.label])
                local tx = K.Text(self.ochild, 11, C.muted)
                tx:SetPoint("TOPLEFT", 240, y - 4)
                tx:SetWidth(380)
                tx:SetWordWrap(true)
                tx:SetText(d.text and d.text() or "")
                self.optWidgets[#self.optWidgets + 1] = lbl
                self.optWidgets[#self.optWidgets + 1] = tx
                y = y - math.max(34, (tx:GetStringHeight() or 30) + 12)
            elseif d.kind == "num" then
                local lbl = K.Text(self.ochild, 12, C.text)
                lbl:SetPoint("TOPLEFT", 0, y - 4)
                lbl:SetWidth(230)
                lbl:SetWordWrap(false)
                lbl:SetText(L[d.label])
                local sl = K.Slider(self.ochild, 200, d.min or 0, d.max or 10, d.step or 1, function()
                    local v = draft and draft[d.key]
                    if v == nil then v = d.default end
                    return tonumber(v) or d.default
                end, function(v)
                    if not draft or not canEdit or locked then return end
                    draft[d.key] = v
                    ns.RefreshPage("admin")
                end, d.fmt or function(v) return tostring(v) end)
                sl:SetPoint("TOPLEFT", 240, y - 2)
                local hit = CreateFrame("Frame", nil, self.ochild)
                hit:SetAllPoints(lbl)
                hit:EnableMouse(true)
                hit:SetScript("OnEnter", function(s) if d.desc then K.ShowTip(s, { L[d.label], L[d.desc] }) end end)
                hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.optWidgets[#self.optWidgets + 1] = lbl
                self.optWidgets[#self.optWidgets + 1] = sl
                self.optWidgets[#self.optWidgets + 1] = hit
                sl.isSlider = true
                y = y - 34
            elseif d.kind == "choice" then
                local lbl = K.Text(self.ochild, 12, C.text)
                lbl:SetPoint("TOPLEFT", 0, y - 4)
                lbl:SetWidth(230)
                lbl:SetWordWrap(false)
                lbl:SetText(L[d.label])
                local items = {}
                for _, ch in ipairs(d.choices or {}) do items[#items + 1] = { key = ch.key, text = L[ch.text] } end
                local seg = K.Segments(self.ochild, items, function(k)
                    if not draft or not canEdit or locked then return end
                    draft[d.key] = k
                    ns.RefreshPage("admin")
                end, nil, { size = 11, pad = 12 })
                seg:SetPoint("TOPLEFT", 240, y)
                seg.def = d
                self.optWidgets[#self.optWidgets + 1] = lbl
                self.optWidgets[#self.optWidgets + 1] = seg
                y = y - 34
            elseif d.kind == "names" then
                -- Name list (e.g. raid leaders): input with suggestions + chips with x to remove
                local lbl = K.Text(self.ochild, 12, C.text)
                lbl:SetPoint("TOPLEFT", 0, y - 4)
                lbl:SetWidth(230)
                lbl:SetWordWrap(false)
                lbl:SetText(L[d.label])
                local hit = CreateFrame("Frame", nil, self.ochild)
                hit:SetAllPoints(lbl)
                hit:EnableMouse(true)
                hit:SetScript("OnEnter", function(s) if d.desc then K.ShowTip(s, { L[d.label], L[d.desc] }) end end)
                hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                local box = CreateFrame("Frame", nil, self.ochild)
                box:SetPoint("TOPLEFT", 240, y)
                box:SetSize(380, 80)
                local function list()
                    local v = draft and draft[d.key]
                    if v == nil then v = d.default end
                    local t = {}
                    for n in tostring(v or ""):gmatch("[^,]+") do t[#t + 1] = n end
                    return t
                end
                local function setList(t)
                    if not draft or not canEdit or locked then return end
                    draft[d.key] = table.concat(t, ",")
                    ns.RefreshPage("admin")
                end
                local inp = K.Input(box, 170, L["Name ..."])
                inp:SetPoint("TOPLEFT", 0, 0)
                if K.AttachNameSuggest then pcall(K.AttachNameSuggest, inp) end
                local function add()
                    local q = ((inp:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()
                    if q == "" then return end
                    -- Find member by display name (double name) or first name; the guild roster name is stored
                    local found
                    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
                        local dn = ns.displayName(m.name):lower()
                        if ns.SameName(m.name, q) then found = m.name break end
                    end
                    if not found then K.Toast(L[d.label], L["No guild member with that name."], C.amber) return end
                    local t = list()
                    for _, n in ipairs(t) do if n == found then inp:SetText("") return end end
                    t[#t + 1] = found
                    inp:SetText("")
                    setList(t)
                end
                inp.onEnter = add
                box.inp = inp
                local plus = K.Button(box, "+", 26, 24, "ghost", add)
                plus:SetPoint("LEFT", inp, "RIGHT", 4, 0)
                box.chips = {}
                function box:UpdateNames()
                    for _, ch in ipairs(self.chips) do ch:Hide() end
                    local x, row = 0, 0
                    for i, n in ipairs(list()) do
                        local ch = self.chips[i]
                        if not ch then
                            ch = K.Button(self, "", 100, 22, "ghost")
                            self.chips[i] = ch
                        end
                        local cls = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(n)
                        ch:SetLabel(ns.colorName(n, cls) .. "  |cffff5a4ax|r")
                        local w = math.min(180, (ch.label:GetStringWidth() or 60) + 22)
                        if x + w > 380 then x, row = 0, row + 1 end
                        ch:SetWidth(w)
                        ch:ClearAllPoints()
                        ch:SetPoint("TOPLEFT", x, -30 - row * 26)
                        x = x + w + 6
                        ch:SetScript("OnClick", function()
                            local t = list()
                            table.remove(t, i)
                            setList(t)
                        end)
                        ch:SetShown(row < 2)
                    end
                end
                box:UpdateNames()
                self.optWidgets[#self.optWidgets + 1] = lbl
                self.optWidgets[#self.optWidgets + 1] = hit
                self.optWidgets[#self.optWidgets + 1] = box
                y = y - 88
            end
        end
        self.ochild:SetHeight(-y + 10)
        self.osf:SetVerticalScroll(0)
    end
    function mp:RefreshOptions()
        for _, w in ipairs(self.optWidgets or {}) do
            if w.Refresh then w:Refresh() end
            if w.UpdateNames then w:UpdateNames() end
            if w.def and w.Select then
                local v = draft and draft[w.def.key]
                if v == nil then v = w.def.default end
                w:Select(v)
            end
        end
    end
    mp.more = K.Text(mp, 11, C.dim)
    mp.more:SetPoint("BOTTOMLEFT", 14, 14)
    mp.more:SetText(L["Changes apply to everyone once you save for the guild below."])
    -- Settings card lies above the (scrollable) list: hide the list meanwhile
    mp:HookScript("OnShow", function() if f.modScroll then f.modScroll:Hide() end end)
    mp:HookScript("OnHide", function() if f.modScroll then f.modScroll:Show() end end)
    function f:OpenModule(def)
        mp.def = def
        mp.title:SetText(K.Upper(L[def.title]) .. "  |cff888888- " .. K.Upper(L["Settings"]) .. "|r")
        mp.icon:SetTexture(ns.ICONS[def.key])
        mp.desc:SetText(def.sub and L[def.sub] or "")
        mp:BuildOptions(def.key)
        mp:Show()
        ns.RefreshPage("admin")
    end
end
local function refreshModules(f)
    local names = Admin.RankNames()
    local vm, nb = visMap(draft), nobSet(draft)
    for _, t in ipairs(f.toggles) do
        t:Refresh()
        local k = t.def.key
        local parts = {}
        if vm[k] then parts[#parts + 1] = (L["from rank %d"]):format(vm[k] + 1) end
        if nb[k] then parts[#parts + 1] = L["no counters"] end
        local nopt = 0
        for _, d in ipairs(ns.GuildOpts or {}) do if d.page == k then nopt = nopt + 1 end end
        t.gear.icon:SetVertexColor((nopt > 0 and C.text or C.muted)[1], (nopt > 0 and C.text or C.muted)[2], (nopt > 0 and C.text or C.muted)[3])
        t.tag:SetText(table.concat(parts, "  ·  "))
    end
    local mp = f.mp
    if mp and mp:IsShown() and mp.def then
        mp.badge:Refresh()
        mp:RefreshOptions()
        local r = vm[mp.def.key]
        mp.vis:SetLabel(r and (L["up to rank %d: %s"]):format(r + 1, names[r] or "?") or L["All ranks"])
    end
end

------------------------------------------------------------------------
-- Tab: Permissions
------------------------------------------------------------------------
local function rankMenu(owner, current, onPick)
    local names, n = Admin.RankNames()
    local items = {}
    for i = 0, n - 1 do
        items[#items + 1] = { text = (L["up to rank %d: %s"]):format(i + 1, names[i] or "?"), checked = current == i, fn = function() onPick(i) end }
    end
    K.ShowMenu(owner, items, nil, 240)
end
local function buildRights(f)
    -- Card 1: who sees guild leadership
    f.cA = card(f, ns.ICONS.admin, L["Access to guild leadership"], C.accent)
    helpTip(f.cA, { L["Access to guild leadership"], L["Everyone from the chosen rank up sees this hub and may change modules, announcements and events for the guild."],
        "|cff888888" .. L["Only the guild master sets the limit. Rank 1 = guild master."] .. "|r" })
    f.cA.desc = K.Text(f.cA, 11, C.muted)
    f.cA.desc:SetPoint("TOPLEFT", 14, -40)
    f.cA.desc:SetPoint("RIGHT", f.cA, "RIGHT", -14, 0)
    f.cA.desc:SetText(L["Modules, announcements, events"])
    f.rank = K.Button(f.cA, "", 210, 26, "ghost", function(self)
        if not Admin.IsGM() then return end
        rankMenu(self, tonumber(draft.rank) or 1, function(i) draft.rank = i ns.RefreshPage("admin") end)
    end)
    f.rank.isDropdown = true
    f.rank:SetPoint("BOTTOMLEFT", 14, 14)
    f.cA.count = K.Text(f.cA, 12, C.text)
    f.cA.count:SetPoint("LEFT", f.rank, "RIGHT", 12, 0)

    -- Card 2: loot points
    f.cB = card(f, ns.ICONS.raid, L["Award loot points"], C.amber)
    helpTip(f.cB, { L["Award loot points"], L["Who may book points (effort/loot) in raid."], "|cff888888" .. L["Saved immediately."] .. "|r" })
    f.cB.desc = K.Text(f.cB, 11, C.muted)
    f.cB.desc:SetPoint("TOPLEFT", 14, -40)
    f.cB.desc:SetPoint("RIGHT", f.cB, "RIGHT", -14, 0)
    f.cB.desc:SetText(L["Book attendance and loot points in raids"])
    f.prank = K.Button(f.cB, "", 210, 26, "ghost", function(self)
        if not (ns.Points and ns.Points.CanManage()) then return end
        rankMenu(self, ns.Points.Cfg().rank, function(i) ns.Points.SetCfg({ rank = i }) ns.RefreshPage("admin") end)
    end)
    f.prank.isDropdown = true
    f.prank:SetPoint("BOTTOMLEFT", 14, 14)
    f.cB.count = K.Text(f.cB, 12, C.text)
    f.cB.count:SetPoint("LEFT", f.prank, "RIGHT", 12, 0)

    -- Card 3: crown & test mode (preparation: later access by rank only)
    f.cC = card(f, ns.ICONS.admin, L["Crown & test mode"], C.blue)
    helpTip(f.cC, { L["Crown & test mode"], L["Who sees the crown at the top. Without rights it is grey and only opens a preview."],
        "|cff888888" .. L["Takes effect after 'Apply for the guild'."] .. "|r" })
    f.crown = K.Toggle(f.cC, L["Show the crown only to guild leadership"], function() return draft and draft.crown == "lead" end,
        function(v) if draft then draft.crown = v and "lead" or "all" end ns.RefreshPage("admin") end)
    f.crown:SetPoint("TOPLEFT", 14, -40)
    f.crown:SetPoint("RIGHT", f.cC, "RIGHT", -14, 0)
    f.cC.test = K.Text(f.cC, 11, C.muted)
    f.cC.test:SetPoint("BOTTOMLEFT", 14, 14)
    f.cC.test:SetPoint("RIGHT", f.cC, "RIGHT", -14, 0)
    f.cC.test:SetWordWrap(true)
    -- Card dropped: crown toggle/test mode hint no longer needed
    f.cC:Hide()
    f.cC.Show = function() end

    -- right: rank ladder (click sets the limit, guild master only)
    f.ladderHead = K.GameHead(f, L["Rank ladder"], C.accent)
    f.ladder = {}
    for i = 1, 10 do
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(26)
        r.bg = K.Fill(r, C.raised)
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT")
        r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetWidth(2)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.05)
        r.mark = K.Text(r, 12, C.text)
        r.mark:SetPoint("LEFT", 10, 0)
        r.num = K.Title(r, 11, C.dim)
        r.num:SetPoint("LEFT", 34, 0)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 60, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -90, 0)
        r.count = K.Text(r, 11, C.muted, "RIGHT")
        r.count:SetPoint("RIGHT", -34, 0)
        -- Gear: rename rank / permissions / delete (guild master only, goes directly to Blizzard)
        r.gear = CreateFrame("Button", nil, r)
        r.gear:SetSize(22, 22)
        r.gear:SetPoint("RIGHT", -6, 0)
        r.gear.icon = K.Glyph(r.gear, 13, ns.ICONS.settings, C.muted)
        r.gear.icon:SetPoint("CENTER")
        r.gear:SetScript("OnEnter", function(self)
            self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            K.ShowTip(self, { L["Edit rank"], L["Rename, permissions, delete - applies in WoW immediately"] })
        end)
        r.gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
        r.gear:SetScript("OnClick", function(self)
            local GR, ri = ns.GuildRanks, r.rank
            if not (GR and ri) then return end
            local names, n = Admin.RankNames()
            local cnt = GR.CountIn(ri)
            local items = {
                { text = (L["Rank %d: %s"]):format(ri + 1, names[ri] or "?"), header = true },
                { text = L["Rename ..."], fn = function()
                    GR.AskName((L["New name for rank %d:"]):format(ri + 1), names[ri], function(t) GR.Rename(ri, t) end)
                end },
                { text = L["Permissions"], header = true },
            }
            for _, fl in ipairs(GR.RankFlags(ri)) do
                items[#items + 1] = { text = fl.label, checked = fl.on, disabled = ri == 0,
                    fn = function() GR.SetRankFlag(ri, fl.i, not fl.on) end }
            end
            items[#items + 1] = { text = "|cffe64040" .. L["Delete rank"] .. "|r",
                disabled = ri == 0 or ri ~= n - 1 or cnt > 0 or n <= 2,
                fn = function()
                    GR.Confirm((L["Really delete rank \"%s\"?"]):format(names[ri] or "?"), function() GR.DeleteRank(ri) end)
                end }
            if ri ~= n - 1 or cnt > 0 then
                items[#items + 1] = { text = "|cff888888" .. L["Only the lowest, empty rank can be deleted (WoW rule)."] .. "|r", disabled = true }
            end
            K.ShowMenu(self, items, nil, 260)
        end)
        r:SetScript("OnClick", function(self)
            if Admin.IsGM() and self.rank then draft.rank = self.rank ns.RefreshPage("admin") end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.rank then return end
            K.ShowTip(self, { (L["Rank %d: %s"]):format(self.rank + 1, self.rname or "?"),
                self.inside and (K.hex(C.mint) .. L["sees guild leadership"] .. "|r") or (K.hex(C.dim) .. L["no access"] .. "|r"),
                Admin.IsGM() and ("|cff888888" .. L["Click: set the limit here"] .. "|r") or nil })
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.ladder[i] = r
    end

    f.addRank = K.Button(f, "+  " .. L["New rank"], 140, 22, "ghost", function()
        local GR = ns.GuildRanks
        if not GR then return end
        GR.AskName(L["Name for the new rank:"], "", function(t) GR.AddRank(t) end)
    end)
    f.addRank:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["New rank"], L["Added at the bottom - applies in WoW immediately."], "|cff888888" .. L["Guild master only, at most 10 ranks."] .. "|r" })
    end)
    f.addRank:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.whoHead = K.GameHead(f, L["Have access"], C.mint)
    f.who = K.List(f, 24, function(l)
        local r = K.Row(l)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetTexture(ns.MEDIA .. "dot")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("LEFT", 4, 0)
        r:Col("name", 18, 170, 12)
        r:Col("rank", 190, 140, 12, C.muted)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, btn)
            if not self.item then return end
            if btn == "RightButton" and ns.GuildRanks then ns.GuildRanks.MemberMenu(self, self.item)
            elseif ns.Profile then ns.Profile.Show(self.item.name) end
        end)
        return r
    end, function(r, m)
        local dc = m.online and C.mint or C.dim
        r.dot:SetVertexColor(dc[1], dc[2], dc[3])
        r.cols.name:SetText(m.online and ns.colorName(m.name, m.class) or ("|cff8a8a8a" .. ns.displayName(m.name) .. "|r"))
        r.cols.rank:SetText(m.rank or "")
        r:SetAlpha(m.online and 1 or 0.6)
    end)
    f.who.empty:SetText(L["Guild roster not loaded yet."])

    function f:Layout(nRanks)
        local w = self:GetWidth() or 750
        if w < 10 then w = 750 end
        local gap = 24
        local half = math.floor((w - gap) / 2)
        self.cA:ClearAllPoints()
        self.cA:SetPoint("TOPLEFT", 0, 0)
        self.cA:SetSize(half, 110)
        self.cB:ClearAllPoints()
        self.cB:SetPoint("TOPLEFT", 0, -122)
        self.cB:SetSize(half, 110)
        self.cC:ClearAllPoints()
        self.cC:SetPoint("TOPLEFT", 0, -244)
        self.cC:SetSize(half, 110)
        local x = half + gap
        self.ladderHead:ClearAllPoints()
        self.ladderHead:SetPoint("TOPLEFT", x, -2)
        self.ladderHead:SetWidth(half)
        local n = nRanks or 0
        for i, r in ipairs(self.ladder) do
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", x, -26 - (i - 1) * 28)
            r:SetWidth(half)
        end
        local canAdd = ns.GuildRanks and ns.GuildRanks.CanEditRanks() and n < 10
        self.addRank:ClearAllPoints()
        self.addRank:SetPoint("TOPLEFT", x, -26 - n * 28 - 4)
        self.addRank:SetShown(canAdd and true or false)
        local yWho = -26 - n * 28 - 14 - (canAdd and 26 or 0)
        self.whoHead:ClearAllPoints()
        self.whoHead:SetPoint("TOPLEFT", x, yWho)
        self.whoHead:SetWidth(half)
        self.who:ClearAllPoints()
        self.who:SetPoint("TOPLEFT", x, yWho - 24)
        self.who:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout(self.nRanks) end)
end
local function refreshRights(f)
    local names, n = Admin.RankNames()
    if f.crown then
        f.crown:Refresh()
        f.crown:SetAlpha(Admin.IsGM() and 1 or 0.5)
        f.cC.test:SetText(Admin.TestMode() and (K.hex(C.amber) .. L["Test mode is on for you: you see leadership like a guild master. Only on your PC - turn off with /oa testleitung."] .. "|r")
            or L["Test mode off. To try it without the rank: /oa testleitung"])
    end
    f.nRanks = math.min(n, #f.ladder)
    f:Layout(f.nRanks)
    local r = tonumber(draft.rank) or 1
    local pr = ns.Points and ns.Points.Cfg().rank or 1
    local counts, total, inA, inB = {}, 0, 0, 0
    local out = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local ri = m.rankIndex or 99
        counts[ri] = (counts[ri] or 0) + 1
        total = total + 1
        if ri <= r then inA = inA + 1 out[#out + 1] = m end
        if ri <= pr then inB = inB + 1 end
    end
    f.rank:SetLabel((L["up to rank %d: %s"]):format(r + 1, names[r] or "?"))
    f.rank:SetEnabledState(Admin.IsGM())
    f.cA.count:SetText(K.hex(C.accent) .. inA .. "|r " .. L["Members"])
    if ns.Points then
        f.prank:SetLabel((L["up to rank %d: %s"]):format(pr + 1, names[pr] or "?"))
        f.prank:SetEnabledState(ns.Points.CanManage())
        f.cB.count:SetText(K.hex(C.amber) .. inB .. "|r " .. L["Members"])
    end
    for i, row in ipairs(f.ladder) do
        local ri = i - 1
        if i <= f.nRanks then
            local inside = ri <= r
            row.rank, row.rname, row.inside = ri, names[ri], inside
            row.mark:SetText(inside and CHECK or CROSS)
            row.num:SetText(ri + 1)
            row.name:SetText(names[ri] or "?")
            row.name:SetTextColor((inside and C.text or C.muted)[1], (inside and C.text or C.muted)[2], (inside and C.text or C.muted)[3])
            row.count:SetText((L["%d mem."]):format(counts[ri] or 0))
            row.gear:SetShown(ns.GuildRanks and ns.GuildRanks.CanEditRanks() or false)
            local c = inside and C.accent or C.line
            row.bar:SetColorTexture(c[1], c[2], c[3], 1)
            row.bg:SetColorTexture(inside and C.accent[1] * 0.12 or C.raised[1], inside and C.accent[2] * 0.12 or C.raised[2], inside and C.accent[3] * 0.12 or C.raised[3], 1)
            row:Show()
        else
            row.rank = nil
            row:Hide()
        end
    end
    f.whoHead:SetCount(#out)
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        return a.name < b.name
    end)
    f.who:SetData(out)
end

------------------------------------------------------------------------
-- Tab: Announcements
------------------------------------------------------------------------
local function buildNotices(f)
    -- Card: new announcement
    local c1 = card(f, ns.MEDIA .. "icons\\announce", L["New announcement"], C.accent)
    helpTip(c1, { L["New announcement"], L["Everyone with Oasis gets a notice with sound."], L["The latest announcement stays on top of the overview for 3 days."] })
    f.c1 = c1
    fieldLabel(c1, L["1. Headline"], 14, -40)
    f.title = K.Input(c1, 300, L["Headline - e.g. raid postponed today"])
    f.title:SetPoint("TOPLEFT", 14, -54)
    f.title:SetPoint("RIGHT", c1, "RIGHT", -14, 0)
    f.title:SetMaxLetters(60)
    fieldLabel(c1, L["2. Message"], 14, -88)
    f.count = K.Text(c1, 10, C.dim, "RIGHT")
    f.count:SetPoint("TOPRIGHT", -14, -88)
    f.text = K.Input(c1, 300, L["What's it about? (max. 200 characters)"])
    f.text:SetPoint("TOPLEFT", 14, -102)
    f.text:SetPoint("RIGHT", c1, "RIGHT", -14, 0)
    f.text:SetMaxLetters(200)
    local function updCount()
        local n = #(f.text:GetText() or "")
        f.count:SetText(n .. " / 200")
        local col = n >= 190 and C.amber or C.dim
        f.count:SetTextColor(col[1], col[2], col[3])
    end
    f.text:HookScript("OnTextChanged", updCount)
    updCount()
    f.imp, f.chat = false, false
    f.impT = K.Toggle(c1, L["Important"], function() return f.imp end, function(v) f.imp = v end)
    f.impT:SetSize(140, 22)
    f.impT:SetPoint("TOPLEFT", 14, -138)
    hoverTip(f.impT, { L["Important"], L["Alarm sound, stays twice as long"] })
    f.chatT = K.Toggle(c1, L["Also in guild chat"], function() return f.chat end, function(v) f.chat = v end)
    f.chatT:SetSize(180, 22)
    f.chatT:SetPoint("LEFT", f.impT, "RIGHT", 16, 0)
    hoverTip(f.chatT, { L["Also in guild chat"], L["Also reaches members without Oasis"] })
    f.send = K.Button(c1, L["Send announcement"], 160, 26, "primary", function()
        if Admin.SendNotice(f.title:GetText(), f.text:GetText(), f.imp, f.chat) then
            f.title:SetText("")
            f.text:SetText("")
            f.imp = false
            f.impT:Refresh()
            K.Toast(L["Announcement sent"], L["Everyone with Oasis gets it now or at their next login."], C.mint)
            ns.RefreshPage("admin")
        end
    end)
    f.send:SetPoint("BOTTOMLEFT", 14, 14)
    f.test = K.Button(c1, L["Preview"], 90, 26, "ghost", function()
        local t = f.title:GetText()
        K.Toast((f.imp and "! " or "") .. (t ~= "" and t or L["Announcement"]), f.text:GetText() .. "  |cff888888- " .. ns.displayName(ns.me()) .. "|r",
            f.imp and C.red or C.accent, nil, f.imp and "alert" or "announce")
    end)
    f.test:SetPoint("LEFT", f.send, "RIGHT", 8, 0)

    -- Card: promote Oasis
    local c2 = card(f, ns.ICONS.social, L["Spread the word"], C.mint)
    helpTip(c2, { L["Spread the word"], L["Notice in guild chat or a one-time whisper to everyone without Oasis."],
        "|cff888888" .. L["For whispers only one leader sends, each member gets it only once."] .. "|r" })
    f.c2 = c2
    f.hint = K.Button(c2, L["Mention in guild chat"], 180, 26, "ghost", function()
        ns.SendChat(Admin.InviteText(true), "GUILD")
        K.Toast(L["Sent"], L["Notice posted in guild chat."], C.mint)
    end)
    f.hint:SetPoint("TOPLEFT", 14, -42)
    f.invT = K.Toggle(c2, L["Whisper those without Oasis"], function() return Admin.Cfg().inv and true or false end, function(v)
        local cfg = copyCfg(Admin.Cfg())
        cfg.inv = v and true or false
        if Admin.Save(cfg) then draft.inv = cfg.inv end
        ns.RefreshPage("admin")
    end)
    f.invT:SetSize(200, 22)
    f.invT:SetPoint("LEFT", f.hint, "RIGHT", 16, 0)
    hoverTip(f.invT, { L["Whisper members without Oasis"], L["Once per member after 3 min online - only one officer sends it"] })
    f.link = K.Input(c2, 300, L["Discord link - e.g. discord.gg/yourguild (Enter saves)"])
    f.link:SetPoint("TOPLEFT", 14, -78)
    f.link:SetPoint("RIGHT", c2, "RIGHT", -14, 0)
    f.link:SetMaxLetters(80)
    f.link:SetScript("OnEnterPressed", function(self)
        local cfg = copyCfg(Admin.Cfg())
        cfg.dlink = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if Admin.Save(cfg) then draft.dlink = cfg.dlink end
        self:ClearFocus()
        K.Toast(L["Saved"], L["The link applies to all officers."], C.mint)
    end)
    f.invInfo = K.Text(c2, 11, C.muted)
    f.invInfo:SetPoint("BOTTOMLEFT", 14, 12)

    -- right: previous announcements
    f.listHead = K.GameHead(f, L["Previous announcements"], C.accent)
    f.list = K.List(f, 50, function(l)
        local r = K.Row(l)
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT", 0, -5)
        r.bar:SetPoint("BOTTOMLEFT", 0, 5)
        r.bar:SetWidth(2)
        r.title = K.Title(r, 12, C.text)
        r.title:SetPoint("TOPLEFT", 10, -6)
        r.title:SetPoint("RIGHT", r, "RIGHT", -30, 0)
        r.body = K.Text(r, 11, C.muted)
        r.body:SetPoint("TOPLEFT", 10, -22)
        r.body:SetPoint("RIGHT", r, "RIGHT", -30, 0)
        r.meta = K.Text(r, 10, C.dim)
        r.meta:SetPoint("BOTTOMLEFT", 10, 4)
        r.del = K.IconButton(r, "x", 16, function(self)
            local it = self:GetParent().item
            if it then Store.Delete("notices", it.id) ns.RefreshPage("admin") ns.RefreshPage("home") end
        end, L["Delete announcement"])
        r.del:SetPoint("TOPRIGHT", -6, -6)
        return r
    end, function(r, n)
        local c = n.imp and C.red or C.accent
        r.bar:SetColorTexture(c[1], c[2], c[3], 1)
        r.title:SetText((n.imp and (K.hex(C.red) .. "! |r") or "") .. ((n.title or "") ~= "" and n.title or L["Announcement"]))
        r.body:SetText(n.text or "")
        r.meta:SetText(ns.displayName(n.by) .. "  ·  " .. ns.ago(n.ts))
        r.del:SetShown(ns.isMe(n.by) or Admin.IsGM())
    end)
    f.list.empty:SetText(L["No announcements yet. Write the first one on the left - headline, message, send."])

    local function layout()
        local w = f:GetWidth() or 750
        if w < 10 then w = 750 end
        local gap = 24
        local half = math.floor((w - gap) / 2)
        c1:ClearAllPoints()
        c1:SetPoint("TOPLEFT", 0, 0)
        c1:SetSize(half, 214)
        c2:ClearAllPoints()
        c2:SetPoint("TOPLEFT", 0, -226)
        c2:SetSize(half, 140)
        f.listHead:ClearAllPoints()
        f.listHead:SetPoint("TOPLEFT", half + gap, -2)
        f.listHead:SetWidth(half)
        f.list:ClearAllPoints()
        f.list:SetPoint("TOPLEFT", half + gap, -26)
        f.list:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    f:SetScript("OnSizeChanged", layout)
    layout()
end
local function refreshNotices(f)
    local notes = Admin.Notices()
    f.list:SetData(notes)
    f.listHead:SetCount(#notes > 0 and #notes or nil)
    f.invT:Refresh()
    if not f.link:HasFocus() then f.link:SetText(Admin.Cfg().dlink or "") end
    local n = 0
    for _ in pairs(Store.coll("invites")) do n = n + 1 end
    local on = Admin.Cfg().inv
    f.invInfo:SetText((on and (K.hex(C.mint) .. L["Whisper on"] .. "|r") or (K.hex(C.dim) .. L["Whisper off"] .. "|r"))
        .. "  ·  " .. (L["Whispered so far: %d"]):format(n))
end

------------------------------------------------------------------------
-- Tab: Guild events - create events (also in the WoW calendar), Double XP (immediate or scheduled),
-- upcoming events with sign-ups
------------------------------------------------------------------------
local function buildEvents(f)
    local R = ns.Raid
    if not R then return end   -- 0.6.275: raid module off -> no event card
    -- Card: new event
    local c1 = card(f, ns.ICONS.raid, L["New event"], C.accent)
    helpTip(c1, { L["New event"], L["Shared with the whole guild - everyone with Oasis can sign up."],
        L["With the calendar switch it also goes into the WoW guild calendar (visible to everyone, even without Oasis)."] })
    f.c1 = c1
    f.kind = "raid"
    local kinds = {}
    for _, k in ipairs(R.KINDS) do kinds[#kinds + 1] = { key = k.key, text = L[k.text] } end
    f.kindSeg = K.Segments(c1, kinds, function(k) f.kind = k end)
    f.kindSeg:SetPoint("TOPLEFT", 10, -36)
    f.kindSeg:Select("raid")
    fieldLabel(c1, L["What?"], 14, -66)
    f.evTitle = K.Input(c1, 200, L["Title - e.g. Molten Core"])
    f.evTitle:SetPoint("TOPLEFT", 14, -80)
    f.evTitle:SetPoint("RIGHT", c1, "RIGHT", -14, 0)
    fieldLabel(c1, L["Day"], 14, -112)
    fieldLabel(c1, L["Time"], 90, -112)
    fieldLabel(c1, L["Slots"], 156, -112)
    f.evDate = K.Input(c1, 70, L["MM/DD"])
    f.evDate:SetPoint("TOPLEFT", 14, -126)
    f.evTime = K.Input(c1, 60, L["HH:MM"])
    f.evTime:SetPoint("LEFT", f.evDate, "RIGHT", 6, 0)
    f.evMax = K.Input(c1, 44, L["Max"])
    f.evMax:SetPoint("LEFT", f.evTime, "RIGHT", 6, 0)
    f.evMax:SetNumeric(true)
    f.evMax:SetMaxLetters(2)
    hoverTip(f.evMax, { L["Max"], L["Slots (5 = dungeon, 10/20/40 = raid)"] })
    f.weekly = false
    f.weekT = K.Toggle(c1, L["4 weeks"], function() return f.weekly end, function(v) f.weekly = v end)
    f.weekT:SetSize(110, 22)
    f.weekT:SetPoint("LEFT", f.evMax, "RIGHT", 12, 0)
    hoverTip(f.weekT, { L["Repeat weekly"], L["Creates the event every week at the same time for 4 weeks."] })
    f.calT = K.Toggle(c1, L["In WoW calendar"], function() return R.toCalendar end, function(v) R.toCalendar = v end)
    f.calT:SetSize(160, 22)
    f.calT:SetPoint("TOPLEFT", 14, -162)
    hoverTip(f.calT, { L["In WoW calendar"], L["Adds the event as a guild event to the WoW calendar (needs calendar rights in the guild)."] })
    f.create = K.Button(c1, L["Create event"], 130, 26, "primary", function()
        local ts = R.ParseWhen(f.evDate:GetText(), f.evTime:GetText())
        local title = (f.evTitle:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if not ts or title == "" then ns.print(L["Enter a title, date (MM/DD) and time (HH:MM)."]) return end
        local kind = f.kind
        local mx = tonumber(f.evMax:GetText()) or (kind == "raid" and 40 or kind == "dungeon" and 5 or 0)
        local made = R.CreateEvent({ title = title, ts = ts, max = mx, kind = kind }, R.toCalendar, f.weekly and 4 or 1)
        f.evTitle:SetText("") f.evDate:SetText("") f.evTime:SetText("") f.evMax:SetText("")
        K.Toast(L["Event created"], title .. "  ·  " .. ns.fmtWhen(ts) .. (#made > 1 and ("  ·  " .. (L["%d events"]):format(#made)) or ""), C.mint)
        ns.RefreshPage("admin")
    end)
    f.create:SetPoint("BOTTOMRIGHT", -14, 14)

    -- Card: Double XP (immediate or scheduled)
    local c2 = card(f, ns.ICONS.rank, L["XP weekend"], C.amber)
    helpTip(c2, { L["XP weekend"], L["Double Oasis XP for the whole guild - start any time. Everyone with Oasis gets an announcement."],
        L["Without a date it starts right away, with date + time it gets scheduled."] })
    f.c2 = c2
    f.x2state = K.Title(c2, 13, C.dim)
    f.x2state:SetPoint("TOPLEFT", 14, -40)
    f.x2state:SetPoint("RIGHT", c2, "RIGHT", -14, 0)
    f.x2hours = 48
    f.x2slider = K.Slider(c2, 200, 6, 96, 6, function() return f.x2hours end, function(v) f.x2hours = v end,
        function(v) return (L["%d h"]):format(v) end)
    f.x2slider:SetPoint("TOPLEFT", 14, -72)
    f.x2slider:SetPoint("RIGHT", c2, "RIGHT", -14, 0)
    fieldLabel(c2, L["Start (empty = now)"], 14, -104)
    f.x2date = K.Input(c2, 70, L["MM/DD"])
    f.x2date:SetPoint("TOPLEFT", 14, -118)
    f.x2time = K.Input(c2, 60, L["HH:MM"])
    f.x2time:SetPoint("LEFT", f.x2date, "RIGHT", 6, 0)
    hoverTip(f.x2date, { L["Schedule"], L["Leave empty = start now"] })
    f.x2go = K.Button(c2, L["Start"], 130, 26, "primary", function()
        local at
        if (f.x2date:GetText() or "") ~= "" then
            at = R.ParseWhen(f.x2date:GetText(), f.x2time:GetText() ~= "" and f.x2time:GetText() or "18:00")
            if not at then ns.print(L["Enter the date as DD.MM. and the time as HH:MM."]) return end
        end
        ns.Rewards.StartDouble(f.x2hours, at)
        f.x2date:SetText("") f.x2time:SetText("")
        ns.RefreshPage("admin")
    end)
    f.x2go:SetPoint("BOTTOMRIGHT", -14, 14)
    f.x2stop = K.Button(c2, L["Close"], 110, 26, "danger", function()
        ns.Rewards.StartDouble(0)
        ns.RefreshPage("admin")
    end)
    f.x2stop:SetPoint("RIGHT", f.x2go, "LEFT", -8, 0)

    -- upcoming events
    f.listHead = K.GameHead(f, L["Upcoming events"], C.mint)
    f.list = K.List(f, 44, function(l)
        local r = K.Row(l)
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT", 0, -4)
        r.bar:SetPoint("BOTTOMLEFT", 0, 4)
        r.bar:SetWidth(3)
        r.day = K.Title(r, 18, C.text, "CENTER")
        r.day:SetPoint("LEFT", 8, 5)
        r.day:SetWidth(40)
        r.mon = K.Text(r, 9, C.muted, "CENTER")
        r.mon:SetPoint("TOP", r.day, "BOTTOM", 0, -1)
        r.mon:SetWidth(40)
        r.icon = K.Glyph(r, 16, nil)
        r.icon:SetPoint("LEFT", 56, 0)
        r.title = K.Text(r, 13, C.text)
        r.title:SetPoint("TOPLEFT", 82, -7)
        r.title:SetPoint("RIGHT", r, "RIGHT", -190, 0)
        r.meta = K.Text(r, 11, C.muted)
        r.meta:SetPoint("BOTTOMLEFT", 82, 7)
        r.meta:SetPoint("RIGHT", r, "RIGHT", -190, 0)
        r.cnt = K.Text(r, 12, C.text, "RIGHT")
        r.cnt:SetPoint("RIGHT", -36, 0)
        r.del = K.IconButton(r, "x", 16, function(self)
            local it = self:GetParent().item
            if it and not it.cal then Store.Delete("events", it.id) ns.RefreshPage("admin") ns.RefreshPage("raid") end
        end, L["Delete event"])
        r.del:SetPoint("RIGHT", -8, 0)
        r:SetScript("OnClick", function() ns.ShowPage("raid") end)
        return r
    end, function(r, ev)
        local k = R.KIND[ev.kind or ((ev.max or 5) > 5 and "raid" or "dungeon")] or R.KIND.other
        local c = ev.cal and C.dim or k.color
        r.bar:SetColorTexture(c[1], c[2], c[3], 1)
        r.icon:SetTexture(ns.ICONS[k.icon])
        r.icon:SetVertexColor(c[1], c[2], c[3])
        r.day:SetText(date("%d", ev.ts))
        r.mon:SetText(K.Upper(ns.weekday(ev.ts, true)) .. " " .. date("%m.", ev.ts))
        r.title:SetText(ev.title or "?")
        local meta = date("%H:%M", ev.ts) .. "  ·  " .. (ev.cal and L["WoW calendar only"] or L[k.text])
        if (ev.inst or "") ~= "" then meta = meta .. "  ·  " .. ev.inst end
        r.meta:SetText(meta)
        if ev.cal then
            r.cnt:SetText("")
        else
            local t, h, d, n = 0, 0, 0, 0
            for _, sgn in ipairs(R.Signups(ev.id)) do
                if sgn.status == "yes" then
                    n = n + 1
                    if sgn.role == "tank" then t = t + 1 elseif sgn.role == "heal" then h = h + 1 else d = d + 1 end
                end
            end
            r.cnt:SetText(K.hex(C.text) .. n .. ((ev.max or 0) > 0 and ("|cff777777/" .. ev.max .. "|r") or "") .. "|r   "
                .. K.hex(C.blue) .. t .. "T|r " .. K.hex(C.mint) .. h .. "H|r " .. K.hex(C.pink) .. d .. "D|r")
        end
        r.del:SetShown(not ev.cal and (ns.isMe(ev.by) or Admin.IsGM()))
    end)
    f.list.empty:SetText(L["No event planned yet. Top left: what, day, time - then 'Create event'."])

    local function layout()
        local w = f:GetWidth() or 750
        if w < 10 then w = 750 end
        local gap = 24
        local wl = math.floor((w - gap) * 0.56)
        local wr = w - gap - wl
        c1:ClearAllPoints()
        c1:SetPoint("TOPLEFT", 0, 0)
        c1:SetSize(wl, 204)
        c2:ClearAllPoints()
        c2:SetPoint("TOPLEFT", wl + gap, 0)
        c2:SetSize(wr, 204)
        f.listHead:ClearAllPoints()
        f.listHead:SetPoint("TOPLEFT", 0, -222)
        f.listHead:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.list:ClearAllPoints()
        f.list:SetPoint("TOPLEFT", 0, -246)
        f.list:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    f:SetScript("OnSizeChanged", layout)
    layout()
end
local function refreshEvents(f)
    local R, RW = ns.Raid, ns.Rewards
    f.calT:Refresh()
    f.weekT:Refresh()
    f.calT:SetAlpha(R.CanCalendar() and 1 or 0.45)
    -- Double XP: running / scheduled / off
    local until2 = RW and RW.DoubleUntil()
    local ps, pe = RW and RW.DoublePlanned()
    if until2 then
        f.x2state:SetText(K.hex(C.amber) .. L["Running"] .. "|r  ·  " .. (L["%d h left"]):format(math.ceil((until2 - ns.now()) / 3600)) .. "  ·  " .. (L["until %s"]):format(ns.fmtDate(until2)))
    elseif ps then
        f.x2state:SetText(K.hex(C.blue) .. L["Scheduled"] .. "|r  ·  " .. ns.fmtWhen(ps) .. "  ·  " .. math.floor((pe - ps) / 3600 + 0.5) .. " h")
    else
        f.x2state:SetText(K.hex(C.dim) .. L["No Double XP right now."] .. "|r")
    end
    f.x2stop:SetShown(until2 ~= nil or ps ~= nil)
    f.x2go:SetLabel(ps and L["Reschedule"] or L["Start"])
    f.x2slider:Refresh()
    -- List: Oasis events + plain calendar entries
    local list = {}
    for _, e in ipairs(R.Events()) do list[#list + 1] = e end
    for _, e in ipairs(R.CalendarOnly()) do list[#list + 1] = e end
    table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    f.listHead:SetCount(#list > 0 and #list or nil)
    f.list:SetData(list)
end

------------------------------------------------------------------------
local BUILD = { overview = buildOverview, modules = buildModules, rights = buildRights, notices = buildNotices, events = buildEvents }
local REFRESH = { overview = refreshOverview, modules = refreshModules, rights = refreshRights, notices = refreshNotices, events = refreshEvents }
local DRAFT_TABS = { modules = true, rights = true }

-- Guild management as groups with sub-tabs (Modules/GuildManagement/Officer.lua)
------------------------------------------------------------------------
-- Tab: Officer chat - WoW's officer channel (/o). Blizzard only sends it to ranks with
-- officer chat permission; history comes from the guild chat log (ns.db.gchat, entries k="off").
-- Never exported and never passed on via Oasis.
------------------------------------------------------------------------
local ochatUnread = 0
local function canOfficerChat()
    -- real permission, not the guild leadership test mode
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer then return C_GuildInfo.IsGuildOfficer() and true or false end
    return false
end
Admin.CanOfficerChat = canOfficerChat
local function officerLines()
    local out = {}
    for _, e in ipairs(ns.db.gchat or {}) do if e.k == "off" then out[#out + 1] = e end end
    return out
end
local function ochatLine(e)
    local who = e.s or "?"
    local cc = e.c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.c]
    local name = ns.displayName(who)
    if cc then name = ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) .. name .. "|r" end
    local msg = e.m or ""
    if ns.Emoji and ns.Emoji.Render then
        local ok, r = pcall(ns.Emoji.Render, msg)
        if ok and r then msg = r end
    end
    return "|cff666666" .. date("%H:%M", e.ts or 0) .. "|r  |Hplayer:" .. ns.short(who) .. "|h" .. name .. "|h|cff888888:|r  " .. msg
end

local function buildOfficerChat(f)
    f.head = K.GameHead(f, L["Officer chat"], C.accent)
    f.head:SetPoint("TOPLEFT", 0, -8)
    f.head:SetWidth(240)
    f.hint = K.Text(f, 11, C.dim, "RIGHT")
    f.hint:SetPoint("TOPRIGHT", 0, -14)
    f.hint:SetText(L["Only officers and guild management see this channel (/o)."])

    f.box = K.Panel(f, C.panel)
    f.box:SetPoint("TOPLEFT", 0, -40)
    f.box:SetPoint("BOTTOMRIGHT", 0, 40)
    f.smf = CreateFrame("ScrollingMessageFrame", nil, f.box)
    f.smf:SetPoint("TOPLEFT", 12, -10)
    f.smf:SetPoint("BOTTOMRIGHT", -12, 10)
    f.smf:SetFont(K.FONT, 13, "")
    f.smf:SetJustifyH("LEFT")
    f.smf:SetFading(false)
    f.smf:SetMaxLines(1000)
    f.smf:SetIndentedWordWrap(true)
    f.smf:SetHyperlinksEnabled(true)
    f.smf:SetScript("OnHyperlinkClick", function(_, link, text, btn) SetItemRef(link, text, btn) end)
    f.smf:EnableMouseWheel(true)
    f.smf:SetScript("OnMouseWheel", function(self, d)
        if d > 0 then self:ScrollUp() self:ScrollUp() else self:ScrollDown() self:ScrollDown() end
    end)
    f.empty = K.Text(f.box, 13, C.dim, "CENTER")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(460)
    f.empty:SetWordWrap(true)

    local function send()
        local t = (f.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then return end
        if ns.SendChat(t:sub(1, 255), "OFFICER") then f.input:SetText("") end
    end
    f.input = K.Input(f, 400, L["Message to the officers ..."])
    f.input:SetPoint("BOTTOMLEFT", 0, 6)
    f.input:SetPoint("RIGHT", f, "RIGHT", -110, 0)
    f.input:SetMaxLetters(255)
    f.input.onEnter = send
    f.sendBtn = K.Button(f, L["Send"], 100, 24, "primary", send)
    f.sendBtn:SetPoint("BOTTOMRIGHT", 0, 6)
end
local function refreshOfficerChat(f)
    ochatUnread = 0
    Admin.UpdateOchatTab()
    local ok = canOfficerChat()
    local lines = officerLines()
    f.smf:Clear()
    if ok then
        for _, e in ipairs(lines) do f.smf:AddMessage(ochatLine(e)) end
    end
    f.empty:SetShown(not ok or #lines == 0)
    f.empty:SetText(not ok and L["Your rank can't read officer chat. The guild master grants this in the Blizzard guild window."]
        or L["No messages in officer chat yet. Everything written in /o from now on shows up here."])
    f.input:SetShown(ok)
    f.sendBtn:SetShown(ok)
end
BUILD.ochat = buildOfficerChat
REFRESH.ochat = refreshOfficerChat

-- new message: open -> append, otherwise counter on the tab
ns.On("CHAT_MSG_OFFICER", function()
    ns.After(0.1, function()
        local fr = page and page.tabs and page.tabs.ochat
        if fr and fr:IsVisible() then
            local l = officerLines()
            if l[#l] then fr.smf:AddMessage(ochatLine(l[#l])) fr.empty:Hide() end
        else
            ochatUnread = ochatUnread + 1
            Admin.UpdateOchatTab()
        end
    end)
end)
function Admin.UpdateOchatTab()
    if not (page and page.seg and page.seg.buttons) then return end
    local badge = ochatUnread > 0 and (" |cffff1200" .. ochatUnread .. "|r") or ""
    for _, s in pairs(page.subs or {}) do
        for _, b in ipairs(s.buttons) do
            if b.key == "ochat" then
                b.label:SetText(L["Officer chat"] .. badge)
                b:SetShown(canOfficerChat() or Admin.TestMode())
                if s.Fit then s:Fit(page:GetWidth()) end
            end
        end
    end
    for _, b in ipairs(page.seg.buttons) do
        if b.key == "g_off" then b.label:SetText(L["Officers"] .. badge) end
    end
    if page.seg.Fit then page.seg:Fit(page:GetWidth()) end
end

local OFFICER_GROUPS = {
    members = { "inactive", "promo", "history", "formers", "recruits", "ads", "bans", "sndmute" },
    raidtools = { "attend", "gear" },
    tools = { "audit", "suspect", "export" },   -- Crest tab removed
}
for g, keys in pairs(OFFICER_GROUPS) do
    BUILD[g] = function(fr) if ns.Officer and ns.Officer.BuildGroup then ns.Officer.BuildGroup(fr, keys) end end
    REFRESH[g] = function(fr) if ns.Officer and ns.Officer.RefreshGroup and fr.seg then ns.Officer.RefreshGroup(fr) end end
end
-- jump directly to a sub-tab (e.g. from a reminder)
function Admin.OpenOfficer(group, sub)
    if sub then ns.db.settings.officerTab = sub end
    ns.ShowPage("admin")
    Admin.SetTab(group)
    local fr = page and page.tabs and page.tabs[group]
    if fr and sub then fr.cur = sub ns.RefreshPage("admin") end
end
-- 0.5.781: guild leadership start page for beginners - "What would you like to do?" with large task cards (click jumps to the
-- matching tab). Plus a line of plain text under the tabs explaining what you can do in the selected tab.
local HELP = {
    start = "Pick below what you want to do - Oasis takes you to the right place.",
    overview = "All members with rank, level and Oasis version. Right-click a row: change rank.",
    members = "Guild care: find inactive members, promotions, history, former members, applicants, ban list and sound mutes.",
    notices = "Write an announcement: everyone with Oasis gets a notice with sound.",
    events = "Create dates and guild events - they show up on everyone's dashboard.",
    raidtools = "Raid: who attended and how good the guild's gear is.",
    ochat = "The officer channel (/o) with history - only for ranks with officer chat permission.",
    modules = "Decide which Oasis areas the guild sees and from which rank. Then save below.",
    rights = "Decide which rank may do what (announcements, events, bank ...). Then save below.",
    tools = "Leadership log, anomalies and export of guild data.",
}
local START_CARDS = {
    { tab = "notices", icon = "announce", title = "Write an announcement", desc = "A message to everyone with Oasis - with notice and sound." },
    { tab = "events", icon = "polls", title = "Create event", desc = "Add a raid, guild night or event, visible to everyone." },
    { tab = "overview", icon = "radar", title = "View members", desc = "Who is in the guild, which rank, who has an old Oasis." },
    { tab = "members", sub = "inactive", icon = "deaths", title = "Find inactive members", desc = "Who has been offline for long - clean up with one click." },
    { tab = "members", sub = "promo", icon = "badges", title = "Promote", desc = "Suggestions for who has earned a higher rank." },
    { tab = "raidtools", icon = "raid", title = "Review raids", desc = "Keep an eye on attendance and guild gear." },
    { tab = "modules", icon = "modules", title = "Enable areas", desc = "Which pages the guild sees - and from which rank." },
    { tab = "rights", icon = "rights", title = "Assign permissions", desc = "Which rank may use announcements, events, bank and more." },
    { tab = "tools", icon = "stats", title = "Log & export", desc = "What leadership changed, anomalies, back up data." },
}
local function buildStart(f)
    f.cards = {}
    f.hello = K.Title(f, 18, C.text)
    f.hello:SetPoint("TOPLEFT", 4, -6)
    f.hello:SetText(L["What would you like to do?"])
    f.sum = K.Text(f, 12, C.muted)
    f.sum:SetPoint("TOPLEFT", f.hello, "BOTTOMLEFT", 0, -6)
    local G = ns.Insta and ns.Insta.Glass
    local anim = K.Tween and not (ns.db and ns.db.settings.noAnim)
    for i, def in ipairs(START_CARDS) do
        local c = CreateFrame("Button", nil, f)
        c.def = def
        if not (G and pcall(G, c, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.10 }, 12)) then
            K.Fill(c, { 1, 1, 1, 0.03 })
            K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
        end
        c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 3)
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
        c.hl:SetAlpha(0)
        c.ic = K.Glyph(c, 24, ns.MEDIA .. "icons\\" .. def.icon, C.accent)
        c.ic:SetPoint("TOPLEFT", 16, -16)
        c.t = K.Title(c, 14, C.text)
        c.t:SetPoint("TOPLEFT", c.ic, "TOPRIGHT", 12, 1)
        c.t:SetPoint("RIGHT", -34, 0)
        c.t:SetJustifyH("LEFT")
        c.t:SetWordWrap(false)
        c.t:SetText(L[def.title])
        c.d = K.Text(c, 11, C.muted)
        c.d:SetPoint("TOPLEFT", c.t, "BOTTOMLEFT", 0, -5)
        c.d:SetPoint("RIGHT", -16, 0)
        c.d:SetJustifyH("LEFT")
        c.d:SetJustifyV("TOP")
        c.d:SetWordWrap(true)
        c.d:SetText(L[def.desc])
        c.go = K.Text(c, 16, C.dim, "RIGHT")
        c.go:SetPoint("TOPRIGHT", -14, -15)
        c.go:SetText(">")
        c:SetScript("OnEnter", function(self)
            if anim then
                K.Tween(self.hl, 0.16, function(q) self.hl:SetAlpha(q) end)
                K.Tween(self.ic, 0.30, function(q) local z = 24 + 4 * math.sin(q * math.pi) self.ic:SetSize(z, z) end, function() self.ic:SetSize(24, 24) end)
                K.Tween(self.go, 0.16, function(q) self.go:SetPoint("TOPRIGHT", -14 + 4 * q, -15) end)
            else
                self.hl:SetAlpha(1)
            end
            self.go:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        end)
        c:SetScript("OnLeave", function(self)
            if anim then
                K.Tween(self.hl, 0.2, function(q) self.hl:SetAlpha(1 - q) end)
                K.Tween(self.go, 0.16, function(q) self.go:SetPoint("TOPRIGHT", -10 - 4 * q, -15) end)
            else
                self.hl:SetAlpha(0)
            end
            self.go:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end)
        c:SetScript("OnClick", function(self)
            local d = self.def
            if d.sub and Admin.OpenOfficer then Admin.OpenOfficer(d.tab, d.sub) else Admin.SetTab(d.tab) end
        end)
        f.cards[i] = c
    end
    -- three columns, width from the page; cards appear one after another
    function f:Layout()
        local w = self:GetWidth() or 990
        if w < 300 then w = 990 end
        local cols, gap = 3, 14
        local cw = math.floor((w - (cols - 1) * gap) / cols)
        for i, c in ipairs(self.cards) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self, "TOPLEFT", col * (cw + gap), -64 - row * (92 + gap))
            c:SetSize(cw, 92)
        end
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    f:Layout()
    if anim then
        for i, c in ipairs(f.cards) do
            c:SetAlpha(0)
            K.Tween(c, 0.28, function(q) c:SetAlpha(q) end, function() c:SetAlpha(1) end, 0.04 * (i - 1))
        end
    end
end
local function refreshStart(f)
    local n, on, old = 0, 0, 0
    local mine = ns.Radar and ns.Radar.VerNum and ns.Radar.VerNum(ns.version) or 0
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        n = n + 1
        if m.online then on = on + 1 end
        local p = ns.db.members[m.name]
        if type(p) == "table" and p.v and ns.Radar.VerNum(p.v) < mine then old = old + 1 end
    end
    f.sum:SetText((L["%d members  -  %d online  -  %d with older Oasis"]):format(n, on, old))
end
BUILD.start = buildStart
REFRESH.start = refreshStart
for k, e in pairs(Admin.EXTRA_BUILD or {}) do BUILD[k], REFRESH[k] = e.build, e.refresh end
for k, h in pairs(HELP_EXTRA) do HELP[k] = h end

function Admin.SetTab(key)
    if not page or not BUILD[key] then return end
    page.tab = key
    local g = GROUP_OF[key]
    if g then
        page.lastKid[g.key] = key
        page.seg:Select(g.key)
        for gk, s in pairs(page.subs) do s:SetShown(gk == g.key) end
        if page.subs[g.key] then page.subs[g.key]:Select(key) end
    end
    for k, fr in pairs(page.tabs) do fr:SetShown(k == key) end
    if not page.tabs[key] then
        local fr = CreateFrame("Frame", nil, page)
        fr:SetPoint("TOPLEFT", 0, -86)   -- Room for section, sub-tab and explanation line
        fr:SetPoint("BOTTOMRIGHT", 0, DRAFT_TABS[key] and 40 or 0)
        page.tabs[key] = fr
        local ok, e = pcall(BUILD[key], fr)
        if not ok then ns.err(L["Setup"] .. " admin/" .. key, e) end
    end
    -- Explanation line in plain language + soft fade-in of the tab
    if page.help then page.help:SetText(HELP[key] and L[HELP[key]] or "") end
    local shown = page.tabs[key]
    if shown and K.Tween and not (ns.db and ns.db.settings.noAnim) then
        shown:SetAlpha(0)
        K.Tween(shown, 0.22, function(q) shown:SetAlpha(q) end, function() shown:SetAlpha(1) end)
    end
    page.saveBar:SetShown(DRAFT_TABS[key] == true)
    ns.RefreshPage("admin")
end

ns.RegisterPage({
    key = "admin", title = "Guild leadership", order = 9, topbar = true,
    sub = "Hub for the Guild Master and officers – applies to the whole guild",
    visible = function() return true end,   -- visible to everyone, locked without permission (see lockPage)
    build = function(p)
        page = p
        draft = copyCfg(Admin.Cfg())
        p.tabs = {}
        -- Sections from the existing tabs (order as GROUPS, remaining tabs at the end as separate sections)
        for k, e in pairs(Admin.EXTRA_BUILD or {}) do BUILD[k], REFRESH[k] = e.build, e.refresh end
        local present, textOf = {}, {}
        for _, t in ipairs(TABS) do present[t.key] = true textOf[t.key] = t.text end
        p.groups, p.subs, p.lastKid = {}, {}, {}
        for _, g in ipairs(GROUPS) do
            local kids = {}
            for _, k in ipairs(g.kids) do if present[k] and BUILD[k] then kids[#kids + 1] = k end end
            if #kids > 0 then p.groups[#p.groups + 1] = { key = g.key, text = g.text, kids = kids, sub = g.sub } end
        end
        for _, t in ipairs(TABS) do
            if not GROUP_OF[t.key] and BUILD[t.key] then
                local g = { key = "g_" .. t.key, text = t.text, kids = { t.key } }
                GROUP_OF[t.key] = g
                p.groups[#p.groups + 1] = g
            end
        end
        local items = {}
        for _, g in ipairs(p.groups) do items[#items + 1] = { key = g.key, text = L[g.text] } end
        p.seg = K.Segments(p, items, function(gk)
            for _, g in ipairs(p.groups) do
                if g.key == gk then
                    local want = p.lastKid[gk]
                    if not want or (want == "ochat" and not (canOfficerChat() or Admin.TestMode())) then
                        want = nil
                        for _, k in ipairs(g.kids) do if k ~= "ochat" or canOfficerChat() or Admin.TestMode() then want = k break end end
                    end
                    if want then Admin.SetTab(want) end
                end
            end
        end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        for _, g in ipairs(p.groups) do
            if #g.kids > 1 then
                local si = {}
                for _, k in ipairs(g.kids) do si[#si + 1] = { key = k, text = L[(g.sub and g.sub[k]) or textOf[k] or k] } end
                local s = K.Segments(p, si, function(k) Admin.SetTab(k) end, nil, { size = 12, pad = 18 })
                s:SetPoint("TOPLEFT", 0, -34)
                s:Hide()
                p.subs[g.key] = s
            end
        end
        p:HookScript("OnSizeChanged", function(self, w) if self.seg and self.seg.Fit then self.seg:Fit(w) end end)
        C_Timer.After(0, function() if p.seg and p.seg.Fit then p.seg:Fit(p:GetWidth()) end end)
        local line = K.Divider(p)
        line:SetPoint("TOPLEFT", 0, -28)
        line:SetPoint("TOPRIGHT", 0, -28)
        p.help = K.Text(p, 11, C.muted)
        p.help:SetPoint("TOPLEFT", 2, -64)
        p.help:SetPoint("RIGHT", p, "RIGHT", -4, 0)
        p.help:SetJustifyH("LEFT")
        p.help:SetWordWrap(false)
        p.saveBar = buildSaveBar(p)
        p.testTag = K.Button(p, "", 200, 22, "ghost", function() ns.slash.testleitung() end)
        p.testTag:SetPoint("TOPRIGHT", 0, 0)
        p.testTag:Hide()   -- empty button otherwise lay over the tabs (tools/officer chat)

        p.testTag.label:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
        p.rebuildDraftViews = function() end
        -- 0.6.526: modules (guild management) register their tabs only after this file
        for k, e in pairs(Admin.EXTRA_BUILD or {}) do BUILD[k], REFRESH[k] = e.build, e.refresh end
        for k, h in pairs(HELP_EXTRA) do HELP[k] = h end
        Admin.SetTab(BUILD.today and "today" or "start")
    end,
    refresh = function(p)
        if not Admin.CanManage() then
            -- without permission: page stays open, frosted-glass lock (lockPage) lies on top
            if p.rightsLock then p.rightsLock:Update() end
            return
        end
        -- Refresh the draft when someone else saved and nothing is pending here
        local cur = Admin.Cfg()
        local u = (cur.u or 0) .. (cur.by or "")
        if p.lastU ~= u then
            if p.lastU == nil or not dirty() then draft = copyCfg(cur) end
            p.lastU = u
        end
        local fr = p.tabs[p.tab]
        if fr and REFRESH[p.tab] then
            local ok, e = pcall(REFRESH[p.tab], fr)
            if not ok then ns.err(L["Page"] .. " admin/" .. p.tab, e) end
        end
        if p.saveBar:IsShown() then p.saveBar:Update() end
        Admin.UpdateOchatTab()
        p.testTag:SetShown(false)   -- Test mode is under Permissions > Crown & test mode
        p.testTag:SetLabel(L["TEST MODE – only you (off)"])
    end,
})

ns.slash.leitung = function()
    if Admin.CanManage() then
        ns.ShowPage("admin")
    elseif not IsInGuild() then
        ns.print(L["You are not in a guild."])
    else
        local names = Admin.RankNames()
        local lr = Admin.LeaderRank()
        ns.print((L["Guild Leadership is visible to ranks up to %d (%s). Your rank: %d."]):format(lr + 1, names[lr] or "?", (myRankIndex() or 98) + 1))
    end
end
ns.slash.admin = ns.slash.leitung
ns.slash.testleitung = function()
    if not ns.IsDev() then ns.print(L["Only for the Guild Master and officers."]) return end
    ns.db.settings.adminTest = not Admin.TestMode()
    memo = nil
    Admin.ApplyBrand(true)
    if Admin.TestMode() then
        ns.print(K.hex(C.amber) .. L["Test mode ON: only on your PC you are treated as Guild Master. Others do NOT see changes you save for the guild. Turn off: /oa testleitung"] .. "|r")
        ns.ShowPage("admin")
    else
        ns.print(L["Test mode OFF – back to your real guild rank."])
    end
end

------------------------------------------------------------------------
-- Whisper members without Oasis once (toggle in guild leadership, default off)
-- Only leaders write. Whoever writes adds the member to "invites" (goes to the guild),
-- all other leaders then skip them -> everyone gets the message only once.
------------------------------------------------------------------------
function Admin.InviteText(forGuild)
    local link = Admin.Cfg().dlink or ""
    local base = forGuild and L["[Oasis] We use the guild addon Oasis (groups, crafting, events, guild bank ...)."]
        or L["Hi! Our guild uses the addon Oasis (groups, crafting, events, guild bank ...)."]
    if link ~= "" then return base .. " " .. (L["Download: %s"]):format(link) end
    return base .. " " .. L["You can find the download in the guild's Discord."]
end
local onlineSince = {}
local function hasOasis(name)
    local p = ns.db.members[name]
    return p and (ns.now() - (p.seen or 0) < 14 * 86400)
end
local function checkInvites()
    local cfg = Admin.Cfg()
    if not cfg.inv or not Admin.CanManage() or ns.inCombat() then return end
    local now = GetTime()
    local seen = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        if m.online and not ns.isMe(m.name) then
            seen[m.name] = true
            onlineSince[m.name] = onlineSince[m.name] or now
            local id = "inv-" .. m.name
            -- 3 min online and still no sign of Oasis -> message once
            if now - onlineSince[m.name] > 180 and not hasOasis(m.name) and not Store.Get("invites", id) then
                Store.Put("invites", { id = id, who = m.name })
                -- 0.5.650: no longer whisper automatically (was a real chat message: ended AFK and went nowhere
                -- if the player had gone offline in the meantime) -> notice, one click sends
                if ns.OfferChat then
                    ns.OfferChat((L["Oasis tip for %s"]):format(ns.short(m.name)), Admin.InviteText(false), "WHISPER", Comm.WhisperName(m.name))
                end
                ns.debug("Oasis-Hinweis angeboten:", m.name)
                return   -- at most one per pass
            end
        end
    end
    for name in pairs(onlineSince) do if not seen[name] then onlineSince[name] = nil end end
end
-- random interval per leader so not everyone checks at the same time
ns.Listen("LOGIN", function()
    ns.After(20 + math.random(0, 20), function() ns.Every(45 + math.random(0, 15), checkInvites) end)
end)

------------------------------------------------------------------------
-- Manage guild ranks (talks directly to Blizzard) - formerly GuildRanks.lua
-- Promote / demote members / set rank, create, rename, delete ranks, set permissions.
-- WoW checks the real permissions itself. Everything by click only (with confirmation) and never in combat.
------------------------------------------------------------------------
do
local GR = {}
ns.GuildRanks = GR

------------------------------------------------------------------------
-- Permissions (what WoW allows me - never from the Oasis test mode)
------------------------------------------------------------------------
function GR.IsLeader() return IsGuildLeader and IsGuildLeader() and true or false end
function GR.CanEditRanks() return GR.IsLeader() end
function GR.CanPromote()
    if C_GuildInfo and C_GuildInfo.CanPromote then local ok, r = pcall(C_GuildInfo.CanPromote) if ok then return r and true or false end end
    return CanGuildPromote and CanGuildPromote() and true or false
end
function GR.CanDemote()
    if C_GuildInfo and C_GuildInfo.CanDemote then local ok, r = pcall(C_GuildInfo.CanDemote) if ok then return r and true or false end end
    return CanGuildDemote and CanGuildDemote() and true or false
end
local function myRank()
    local _, _, ri = GetGuildInfo("player")
    return ns.safe(ri)
end
GR.MyRank = myRank

local function blocked()
    if ns.inCombat() then ns.print(L["Not possible in combat - try again shortly."]) return true end
    if not IsInGuild() then return true end
    return false
end
local function refresh()
    ns.RequestGuildRoster()
    ns.After(0.6, function() ns.RefreshPage("admin") ns.RefreshPage("radar") end)
end

------------------------------------------------------------------------
-- Confirmation
------------------------------------------------------------------------
StaticPopupDialogs.OASIS_CONFIRM = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    OnAccept = function(self, data) if data and data.fn then data.fn() end end,
}
function GR.Confirm(text, fn)
    StaticPopup_Show("OASIS_CONFIRM", text, nil, { fn = fn })
end
StaticPopupDialogs.OASIS_RANKNAME = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
    hasEditBox = true, maxLetters = 15, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetText(data and data.name or "") eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        local t = eb and (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
        if t ~= "" and data and data.fn then data.fn(t) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        if p.button1 then p.button1:Click() end
    end,
}
function GR.AskName(text, current, fn)
    StaticPopup_Show("OASIS_RANKNAME", text, nil, { name = current, fn = fn })
end

------------------------------------------------------------------------
-- Members: set rank (via the index in the guild roster - robust for names with spaces)
------------------------------------------------------------------------
local function indexOf(name)
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, n do
        local nm, _, ri = GetGuildRosterInfo(i)
        nm = ns.safe(nm)
        if nm and (ns.fullName(nm) == name or nm == name or ns.short(ns.fullName(nm)) == ns.short(name)) then return i, ns.safe(ri) end
    end
end
GR.IndexOf = indexOf
-- rankIndex: 0 = guild master, 1 = next ...
function GR.SetRank(name, rankIndex)
    if blocked() then return false end
    local i, cur = indexOf(name)
    if not i then ns.print(L["Member not found in the guild roster."]) return false end
    local mine = myRank()
    if rankIndex <= (mine or 0) and not GR.IsLeader() then
        ns.print(L["You can't set anyone to your own or a higher rank."])
        return false
    end
    ns.Trace("SetGuildMemberRank " .. rankIndex)
    local ok, e
    if SetGuildMemberRank then
        ok, e = pcall(SetGuildMemberRank, i, rankIndex + 1)
    elseif cur and rankIndex < cur and (C_GuildInfo and C_GuildInfo.Promote or GuildPromote) then
        ok, e = pcall(C_GuildInfo and C_GuildInfo.Promote or GuildPromote, ns.short(name))
    elseif cur and rankIndex > cur and (C_GuildInfo and C_GuildInfo.Demote or GuildDemote) then
        ok, e = pcall(C_GuildInfo and C_GuildInfo.Demote or GuildDemote, ns.short(name))
    end
    if ok == false then ns.err(L["Set rank"], e) end
    refresh()
    return ok ~= false
end
function GR.Promote(name)
    local _, cur = indexOf(name)
    if cur and cur > 0 then return GR.SetRank(name, cur - 1) end
end
function GR.Demote(name)
    local _, cur = indexOf(name)
    local _, n = ns.Admin.RankNames()
    if cur and cur < n - 1 then return GR.SetRank(name, cur + 1) end
end
-- several one after another (WoW doesn't like floods)
function GR.SetRankMany(names, rankIndex, done)
    local list = {}
    for _, n in ipairs(names) do list[#list + 1] = n end
    local function step(i)
        if i > #list then if done then done(#list) end refresh() return end
        GR.SetRank(list[i], rankIndex)
        ns.After(0.4, function() step(i + 1) end)
    end
    step(1)
end

-- Right-click menu for a member
function GR.MemberMenu(owner, m)
    if not m then return end
    local names, n = ns.Admin.RankNames()
    local cur = m.rankIndex or 99
    local short = ns.displayName(m.name)
    local canP, canD = GR.CanPromote(), GR.CanDemote()
    local mine = myRank() or 99
    local items = { { text = short .. "  |cff888888" .. (names[cur] or "?") .. "|r", header = true } }
    if ns.Leadership and ns.isOfficer() then
        items[#items + 1] = { text = L["Open file"], fn = function() ns.Leadership.ShowDossier(m.name) end }   -- 0.6.526
    end
    items[#items + 1] = { text = "▲  " .. L["Promote"], disabled = not canP or cur <= 0 or (cur - 1 <= mine and not GR.IsLeader()),
        fn = function() GR.Confirm((L["Promote %s to \"%s\"?"]):format(short, names[cur - 1] or "?"), function() GR.Promote(m.name) end) end }
    items[#items + 1] = { text = "▼  " .. L["Demote"], disabled = not canD or cur >= n - 1 or (cur <= mine and not GR.IsLeader()),
        fn = function() GR.Confirm((L["Demote %s to \"%s\"?"]):format(short, names[cur + 1] or "?"), function() GR.Demote(m.name) end) end }
    items[#items + 1] = { text = L["Set rank"], header = true }
    for i = 1, n - 1 do
        local allowed = (i > mine or GR.IsLeader()) and ((i < cur and canP) or (i > cur and canD))
        items[#items + 1] = { text = (i + 1) .. ".  " .. (names[i] or "?"), checked = i == cur, disabled = not allowed or i == cur,
            fn = function() GR.Confirm((L["Set %s to rank \"%s\"?"]):format(short, names[i] or "?"), function() GR.SetRank(m.name, i) end) end }
    end
    if not canP and not canD then
        items[#items + 1] = { text = "|cff888888" .. L["Your guild rank may not change ranks."] .. "|r", disabled = true }
    end
    K.ShowMenu(owner, items, nil, 220)
end

------------------------------------------------------------------------
-- Ranks: create, rename, delete, permissions (guild master only)
------------------------------------------------------------------------
local function rankCount() return GuildControlGetNumRanks and GuildControlGetNumRanks() or 0 end
function GR.RankFlags(rankIndex)
    local out = {}
    if not (GuildControlSetRank and GuildControlGetRankFlags) then return out end
    pcall(GuildControlSetRank, rankIndex + 1)
    local flags = { GuildControlGetRankFlags() }
    for i, v in ipairs(flags) do
        local label = _G["GUILDCONTROL_OPTION" .. i]
        if label and label ~= "" then out[#out + 1] = { i = i, label = label, on = v and true or false } end
    end
    return out
end
function GR.SetRankFlag(rankIndex, flag, on)
    if blocked() or not GR.CanEditRanks() then return end
    local names = ns.Admin.RankNames()
    local ok, e = pcall(function()
        GuildControlSetRank(rankIndex + 1)
        GuildControlSetRankFlag(flag, on and true or false)
        if GuildControlSaveRank then GuildControlSaveRank(names[rankIndex] or GuildControlGetRankName(rankIndex + 1)) end
    end)
    if not ok then ns.err(L["Rank permissions"], e) end
    refresh()
end
function GR.Rename(rankIndex, newName)
    if blocked() or not GR.CanEditRanks() then return end
    local ok, e = pcall(function()
        GuildControlSetRank(rankIndex + 1)
        GuildControlSaveRank(newName)
    end)
    if not ok then ns.err(L["Rename rank"], e) end
    refresh()
end
function GR.AddRank(name)
    if blocked() or not GR.CanEditRanks() then return end
    if rankCount() >= 10 then ns.print(L["WoW allows at most 10 ranks."]) return end
    local ok, e = pcall(GuildControlAddRank, name)
    if not ok then ns.err(L["Create rank"], e) end
    refresh()
end
function GR.DeleteRank(rankIndex)
    if blocked() or not GR.CanEditRanks() then return end
    local ok, e = pcall(GuildControlDelRank, rankIndex + 1)
    if not ok then ns.err(L["Delete rank"], e) end
    refresh()
end
-- Members per rank (from the guild roster)
function GR.CountIn(rankIndex)
    local n = 0
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do if m.rankIndex == rankIndex then n = n + 1 end end
    return n
end

ns.On("GUILD_RANKS_UPDATE", function() ns.RefreshPage("admin") end)
end

-- Diagnostics: /oa wappen - state of the rank crests in the guild leadership overview
ns.slash.wappen = function()
    local f = page and page.tabs and page.tabs.overview
    local list = f and f.list
    if not list then ns.print("Gildenleitung > Uebersicht einmal oeffnen, dann nochmal.") return end
    local n = 0
    for _, r in ipairs(list.rows or {}) do
        if r:IsShown() and r.item and r.remblem then
            n = n + 1
            local e, m = r.remblem, r.item.m
            local lvl, ok = ns.Rank.Of(m.name)
            ns.print(("%s  v=%s  rang=%s (%s)  shown=%s tex=%s texShown=%s alpha=%.2f lvl=%d/%d  %dx%d"):format(
                ns.short(m.name), tostring(r.item.v), tostring(lvl), tostring(ok), tostring(e:IsShown()),
                tostring(e.tex:GetTexture()), tostring(e.tex:IsShown()), e.tex:GetAlpha(),
                e:GetFrameLevel(), r:GetFrameLevel(), e:GetWidth() or 0, e:GetHeight() or 0))
            if n >= 4 then break end
        end
    end
    if n == 0 then ns.print("Keine Zeilen gefunden.") end
end

-- Guild leadership/guild management: visible to everyone, dimmed + padlock without permission (nothing usable)
local function lockPage(key)
    local def = ns.PageDef and ns.PageDef(key)
    if not def or def.oasisLockWrapped then return end
    def.oasisLockWrapped = true
    local build = def.build
    def.build = function(p)
        build(p)
        if K.Lock then
            -- Tab bar (p.seg, line at -28) stays sharp and visible, only the content below is locked/blurred
            p.rightsLock = K.Lock(p, { check = function() return Admin.CanManage() end, who = "lead",
                top = p.seg and 58 or nil, keep = { p.seg, unpack((function() local t = {} for _, s in pairs(p.subs or {}) do t[#t + 1] = s end return t end)()) } })
            p.rightsLock:Update(true)
            p:HookScript("OnShow", function(self) self.rightsLock:Update() end)
        end
    end
    local refresh = def.refresh
    def.refresh = function(p, ...)
        if refresh then refresh(p, ...) end
        if p.rightsLock then p.rightsLock:Update() end
    end
end
ns.Listen("LOGIN", function() lockPage("admin") lockPage("officer") end)

------------------------------------------------------------------------
-- Logo studio (0.5.917): clicking the logo opens a small window with live preview instead of a long list.
-- Hovering shows style/font immediately in the preview, click applies. Everything only for the user themselves
-- (settings.logoStyle / logoTrack / logoFont). No rebuild of the main window: only the logos redraw.
------------------------------------------------------------------------
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
-- Color the name letter by letter (spaces/line breaks stay uncolored)
function Admin.LogoMarkup(text, style, col, textCol)
    if not text or text == "" then return text end
    local chars, n = {}, 0
    for ch in text:gmatch(CHAR) do
        chars[#chars + 1] = ch
        if ch ~= " " and ch ~= "\n" then n = n + 1 end
    end
    local out, i = {}, 0
    for _, ch in ipairs(chars) do
        if ch == " " or ch == "\n" then
            out[#out + 1] = ch
        else
            local lc = Admin.LogoLetterColor(style, col, textCol, n > 1 and i / (n - 1) or 0)
            out[#out + 1] = ("|cff%02x%02x%02x%s"):format(
                math.floor(lc[1] * 255 + 0.5), math.floor(lc[2] * 255 + 0.5), math.floor(lc[3] * 255 + 0.5), ch)
            i = i + 1
        end
    end
    return table.concat(out) .. "|r"
end
-- short one-word names letter-spaced ("O A S I S"), otherwise unchanged
function Admin.LogoSpaced(plain, track)
    if not track or plain:find("%s") then return plain end
    local letters = {}
    for ch in plain:gmatch(CHAR) do letters[#letters + 1] = ch end
    if #letters >= 2 and #letters <= 10 then return table.concat(letters, " ") end
    return plain
end
function Admin.RefreshLogos()
    for lg in pairs(logos) do if not lg.fixedCfg then pcall(lg.Apply, lg) end end
end
-- Name as in the logo: leadership's own lettering or guild name, large, "o a s i s" contracted
local function studioName()
    local cfg = Admin.DisplayCfg()
    local plain = (Admin.DemoGuildName and Admin.DemoGuildName()) or ((cfg.ltext or "") ~= "" and cfg.ltext) or Admin.GuildName() or "Oasis"
    local parts = {}
    for w in plain:gmatch("%S+") do parts[#parts + 1] = w end
    local single = #parts > 2
    for _, w in ipairs(parts) do if #w > 1 then single = false end end
    if single then plain = table.concat(parts) end
    plain = K.Upper and K.Upper(plain) or plain:upper()
    local col = K.FromHex(cfg.lcol) or K.FromHex(Admin.EffectiveAccent(cfg)) or C.accent
    return plain, col
end
local function firstLetters(text, max)
    local out = {}
    for ch in text:gmatch(CHAR) do
        if ch ~= " " then out[#out + 1] = ch end
        if #out >= max then break end
    end
    return table.concat(out)
end

local studio
function Admin.ShowLogoStudio(owner)
    local s = ns.db.settings
    if studio and studio:IsShown() and not owner then studio:Hide() return end
    if studio and studio:IsShown() and studio.owner == owner then studio:Hide() return end
    if not studio then
        local W, PAD = 468, 20
        local f = CreateFrame("Frame", "OasisLogoStudio", UIParent)
        studio = f
        f:SetSize(W, 548)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        K.Fill(f, C.bg)
        K.Border(f, C.line)
        if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
        if ns.EscClose then ns.EscClose(f) end
        local title = K.Title(f, 15, C.text)
        title:SetPoint("TOPLEFT", PAD, -16)
        title:SetText(L["Design your logo"])
        local hint = K.Text(f, 11, C.dim)
        hint:SetPoint("TOPLEFT", PAD, -37)
        hint:SetText(L["Only applies to you - others see their own logo."])
        local close = K.CloseButton(f, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)

        -- Preview: large, shows the selection immediately on hover
        local pv = CreateFrame("Frame", nil, f)
        pv:SetPoint("TOPLEFT", PAD, -62)
        pv:SetPoint("TOPRIGHT", -PAD, -62)
        pv:SetHeight(104)
        K.Fill(pv, C.side)
        K.Border(pv, C.line)
        pv.name = pv:CreateFontString(nil, "OVERLAY")
        pv.name:SetPoint("CENTER", 0, 8)
        pv.name:SetWordWrap(false)
        pv.name:SetShadowColor(0, 0, 0, 0.6)
        pv.name:SetShadowOffset(1, -1)
        pv.cap = K.Text(pv, 10, C.dim, "CENTER")
        pv.cap:SetPoint("BOTTOM", 0, 9)
        f.pv = pv

        -- Style: five tiles, each shows the start of the name in its style
        local head1 = K.Header(f, L["Style"])
        head1:SetPoint("TOPLEFT", PAD, -180)
        head1:SetWidth(W - PAD * 2)
        f.tiles = {}
        local GAPX = 8
        local TW = math.floor((W - PAD * 2 - GAPX * (#Admin.LOGO_STYLES - 1)) / #Admin.LOGO_STYLES)
        for i, d in ipairs(Admin.LOGO_STYLES) do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(TW, 62)
            b:SetPoint("TOPLEFT", PAD + (i - 1) * (TW + GAPX), -204)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0.04)
            b.sample = b:CreateFontString(nil, "OVERLAY")
            b.sample:SetPoint("TOP", 0, -10)
            b.sample:SetWordWrap(false)
            b.label = K.Text(b, 10, C.muted, "CENTER")
            b.label:SetPoint("BOTTOM", 0, 9)
            b.label:SetWidth(TW - 6)
            b.label:SetWordWrap(true)
            if b.label.SetMaxLines then b.label:SetMaxLines(2) end
            b.label:SetText(L[d.text])
            b.under = b:CreateTexture(nil, "OVERLAY")
            b.under:SetHeight(2)
            b.under:SetPoint("BOTTOMLEFT", 6, 0)
            b.under:SetPoint("BOTTOMRIGHT", -6, 0)
            b.key = d.key
            b:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.09)
                f.hoverStyle = self.key
                f:Paint(true)
            end)
            b:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.04)
                f.hoverStyle = nil
                f:Paint(true)
            end)
            b:SetScript("OnClick", function(self)
                s.logoStyle = self.key ~= "soft" and self.key or nil
                if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
                Admin.RefreshLogos()
                f:Paint(true)
            end)
            f.tiles[i] = b
        end
        f.track = K.Toggle(f, L["Wide letter spacing"], function() return s.logoTrack ~= false end, function(v)
            if v then s.logoTrack = nil else s.logoTrack = false end
            Admin.RefreshLogos()
            f:Paint(true)
        end)
        f.track:SetPoint("TOPLEFT", PAD, -278)
        f.track:SetWidth(300)

        -- Font: two columns, each row shows the name in its font
        local head2 = K.Header(f, L["Font"])
        head2:SetPoint("TOPLEFT", PAD, -316)
        head2:SetWidth(W - PAD * 2)
        local sc = CreateFrame("ScrollFrame", nil, f)
        sc:SetPoint("TOPLEFT", PAD, -340)
        sc:SetPoint("BOTTOMRIGHT", -PAD, 54)
        local inner = CreateFrame("Frame", nil, sc)
        sc:SetScrollChild(inner)
        local CW, RH = math.floor((W - PAD * 2 - 8) / 2), 30
        local list = { { key = "default", text = L["Default font"] } }
        for _, ft in ipairs(K.PickFonts()) do list[#list + 1] = { key = ft.key, text = ft.text } end
        inner:SetSize(W - PAD * 2, math.ceil(#list / 2) * RH)
        sc:EnableMouseWheel(true)
        sc:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, inner:GetHeight() - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * RH * 2)))
        end)
        f.fonts = {}
        for i, ft in ipairs(list) do
            local b = CreateFrame("Button", nil, inner)
            b:SetSize(CW, RH - 2)
            b:SetPoint("TOPLEFT", ((i - 1) % 2) * (CW + 8), -math.floor((i - 1) / 2) * RH)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0)
            b.sample = b:CreateFontString(nil, "OVERLAY")
            b.sample:SetPoint("LEFT", 8, 0)
            b.sample:SetWidth(CW - 96)
            b.sample:SetJustifyH("LEFT")
            b.sample:SetWordWrap(false)
            b.name = K.Text(b, 10, C.dim, "RIGHT")
            b.name:SetPoint("RIGHT", -8, 0)
            b.name:SetWidth(84)
            b.name:SetWordWrap(false)
            b.name:SetText(ft.text)
            b.key = ft.key
            b:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.07)
                f.hoverFont = self.key
                f:Paint(true)
            end)
            b:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0)
                f.hoverFont = nil
                f:Paint(true)
            end)
            b:SetScript("OnClick", function(self)
                s.logoFont = self.key ~= "default" and self.key or nil
                if ns.Sound and ns.Sound.Next then pcall(ns.Sound.Next, "click") end
                Admin.RefreshLogos()
                f:Paint(true)
            end)
            f.fonts[i] = b
        end

        local reset = K.Button(f, L["Reset"], 130, 24, "ghost", function()
            s.logoStyle, s.logoTrack, s.logoFont = nil, nil, nil
            Admin.RefreshLogos()
            if f.track.Refresh then pcall(f.track.Refresh, f.track) end
            f:Paint(true)
        end)
        reset:SetPoint("BOTTOMLEFT", PAD, 16)
        local more = K.Button(f, L["Logo settings ..."], 180, 24, "ghost", function()
            f:Hide()
            if ns.OpenSettingsTab then ns.OpenSettingsTab("look") end
        end)
        more:SetPoint("BOTTOMRIGHT", -PAD, 16)

        local function pathOf(key)
            local guild = Admin.Cfg().lfont or "ptsansbold"
            return K.FontPath((key and key ~= "default") and key or guild, K.FONT_HEAD)
        end
        -- redraw everything; anim = briefly fade in the preview
        function f:Paint(anim)
            local plain, col = studioName()
            local style = self.hoverStyle or Admin.LogoStyle()
            local fontKey = self.hoverFont or s.logoFont or "default"
            local shown = Admin.LogoSpaced(plain, s.logoTrack ~= false)
            local path = K.FontFor and K.FontFor(pathOf(fontKey), plain) or pathOf(fontKey)
            local maxW = (pv:GetWidth() or (W - PAD * 2)) - 36
            for size = 36, 14, -2 do
                K.SetFontSafe(pv.name, path, size, "", K.FONT_HEAD)
                pv.name:SetText(shown)
                if (tonumber(pv.name:GetStringWidth()) or 0) <= maxW then break end
            end
            pv.name:SetText(Admin.LogoMarkup(shown, style, col, C.text))
            local styleText, fontText = "", ""
            for _, d in ipairs(Admin.LOGO_STYLES) do if d.key == style then styleText = L[d.text] end end
            for _, b in ipairs(self.fonts) do if b.key == fontKey then fontText = b.name:GetText() or "" end end
            pv.cap:SetText(styleText .. "  \194\183  " .. fontText)
            if anim and K.Tween and not s.noAnim then
                pv.name:SetAlpha(0.35)
                K.Tween(pv.name, 0.18, function(q) pv.name:SetAlpha(0.35 + 0.65 * q) end, function() pv.name:SetAlpha(1) end)
            else
                pv.name:SetAlpha(1)
            end
            local short = firstLetters(plain, 5)
            local curStyle, curFont = Admin.LogoStyle(), s.logoFont or "default"
            local samplePath = K.FontFor and K.FontFor(pathOf(s.logoFont), plain) or pathOf(s.logoFont)
            for _, b in ipairs(self.tiles) do
                K.SetFontSafe(b.sample, samplePath, 17, "", K.FONT_HEAD)
                b.sample:SetText(Admin.LogoMarkup(short, b.key, col, C.text))
                local on = b.key == curStyle
                b.under:SetColorTexture(col[1], col[2], col[3], 1)
                b.under:SetShown(on)
                local lc = on and C.text or C.muted
                b.label:SetTextColor(lc[1], lc[2], lc[3])
            end
            local row = firstLetters(plain, 12)
            for _, b in ipairs(self.fonts) do
                local p2 = K.FontFor and K.FontFor(pathOf(b.key), plain) or pathOf(b.key)
                K.SetFontSafe(b.sample, p2, 15, "", K.FONT_HEAD)
                b.sample:SetText(row)
                local on = b.key == curFont
                local tc = on and col or C.text
                b.sample:SetTextColor(tc[1], tc[2], tc[3])
                local nc = on and C.text or C.dim
                b.name:SetTextColor(nc[1], nc[2], nc[3])
            end
        end
    end
    studio.owner = owner
    studio.hoverStyle, studio.hoverFont = nil, nil
    studio:ClearAllPoints()
    if owner and owner.GetRight then
        studio:SetPoint("TOPLEFT", owner, "TOPRIGHT", 46, 6)
    else
        studio:SetPoint("CENTER")
    end
    studio:Show()
    if studio.track.Refresh then pcall(studio.track.Refresh, studio.track) end
    studio:Paint()
    if K.FadeIn then studio.oasisFadedAt = nil K.FadeIn(studio) end
    -- WoW loads font files only on first use: measure and draw again shortly after
    ns.After(0.3, function() if studio:IsShown() then studio:Paint() end end)
end
-- End of logo studio

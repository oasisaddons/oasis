-- Oasis module 4: Legacy tracker
-- The 65 Legacy challenges of WoW Forever (as of beta 28.09.2026, sources: classicwowforever.com/legacy,
-- endgametools.com). Points belong to the account -> Oasis counts per player (main + alts).
-- Oasis detects class and profession challenges itself (guild roster, alts, profession data),
-- Exalted/PvP rank for your own characters, the rest is ticked off and shared with the guild.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Legacy", function()   -- Legacy module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
-- Safety on receive (other players' addon messages may be tampered with):
-- sanitize texts, cap numbers, check names, throttle floods
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- escape sequences (|c |r |n |H |T |K |A ...) and control characters neutralized; links: valid item/spell links are kept
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

local Legacy = {}
ns.Legacy = Legacy
Legacy.list = {}        -- all challenges (static)
Legacy.byId = {}
Legacy.searches = {}    -- active group searches [name] = { name, id, activity, note, t }

local MAX_SPEND = 16
-- 0.5.699: beta gift - with the update of 8.10.2026 (build 70291) all beta players got the Legacy challenge
-- as a gift = 16 Legacy points. Oasis doesn't know the real points (only ticked challenges) -> count at least
-- that many. Turn off (e.g. when it goes live): ns.db.settings.legacyGrant = false
local GRANT_BUILD = 70291
function ns.LegacyGrant()
    if ns.db and ns.db.settings and ns.db.settings.legacyGrant == false then return 0 end
    local ok, _, build = pcall(GetBuildInfo)
    return (ok and (tonumber(build) or 0) >= GRANT_BUILD) and MAX_SPEND or 0
end
local REWARDS = { 15, 25, 40, 55 }

------------------------------------------------------------------------
-- Challenge catalog
------------------------------------------------------------------------
local CATS = {
    { key = "class", name = "Classes", icon = "Interface\\Icons\\Achievement_Level_60" },
    { key = "prof", name = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { key = "dungeon", name = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Lantern_01" },
    { key = "raid", name = "Raids", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { key = "pvp", name = "PvP", icon = "Interface\\Icons\\INV_BannerPVP_02" },
    { key = "adv", name = "Adventure", icon = "Interface\\Icons\\INV_Misc_Map_01" },
}
Legacy.CATS = CATS
local CAT_BY = {}
for _, c in ipairs(CATS) do CAT_BY[c.key] = c end

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_DE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local CLASS_TIERS = { { 25, "Novice" }, { 45, "Experienced" }, { 60, "Master" } }
local PROFS = { { 171, "Alchemy" }, { 164, "Blacksmithing" }, { 333, "Enchanting" }, { 202, "Engineering" },
    { 165, "Leatherworking" }, { 197, "Tailoring" } }
local PROF_TIERS = { { 150, "Journeyman" }, { 225, "Expert" }, { 300, "Artisan" } }
-- Exalted: Horde and Alliance faction per battleground
local REPS = { av = { 729, 730 }, ab = { 510, 509 }, wsg = { 889, 890 } }

local function className(cf)
    local t = LOCALIZED_CLASS_NAMES_MALE
    if ns.lang ~= "de" and t and t[cf] then return t[cf] end
    return L[CLASS_DE[cf] or cf]
end
local function profName(id, fallback)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
        if ok and ns.safe(n) and n ~= "" then return n end
    end
    return L[fallback]
end

local function add(e)
    Legacy.list[#Legacy.list + 1] = e
    Legacy.byId[e.id] = e
end
local function build()
    for _, cf in ipairs(CLASSES) do
        for _, t in ipairs(CLASS_TIERS) do
            add({ id = "c:" .. cf .. ":" .. t[1], cat = "class", auto = true, class = cf, lvl = t[1], tier = t[2],
                icon = "Interface\\Icons\\ClassIcon_" .. cf:sub(1, 1) .. cf:sub(2):lower() })
        end
    end
    for _, pf in ipairs(PROFS) do
        for _, t in ipairs(PROF_TIERS) do
            add({ id = "p:" .. pf[1] .. ":" .. t[1], cat = "prof", auto = true, prof = pf[1], profName = pf[2], skill = t[1], tier = t[2] })
        end
    end
    add({ id = "d:1", cat = "dungeon", name = "Novice Spelunker", req = "Complete all level 15–25 dungeons", lo = 15, hi = 25 })
    add({ id = "d:2", cat = "dungeon", name = "Experienced Spelunker", req = "Complete all level 26–45 dungeons", lo = 26, hi = 45 })
    add({ id = "d:3", cat = "dungeon", name = "Master Spelunker", req = "Complete all level 46–60 dungeons", lo = 46, hi = 60 })
    add({ id = "r:ony", cat = "raid", name = "Conqueror of the Lair", req = "Defeat Onyxia" })
    add({ id = "r:deeps", cat = "raid", name = "Conqueror of the Deeps", req = "Defeat all 8 bosses of the Barrow Deeps" })
    add({ id = "r:hyjal", cat = "raid", name = "Conqueror of the Wilds", req = "Defeat all 13 bosses of Hyjal Summit" })
    for _, r in ipairs({ 3, 7, 10, 13, 14 }) do
        add({ id = "pr:" .. r, cat = "pvp", name = (L["PvP Rank %d"]):format(r), req = (L["Reach honor rank %d"]):format(r), rank = r })
    end
    add({ id = "pe:av", cat = "pvp", name = "Exalted: Alterac Valley", req = "Exalted with the Alterac Valley faction (Frostwolf / Stormpike)", rep = "av" })
    add({ id = "pe:ab", cat = "pvp", name = "Exalted: Arathi Basin", req = "Exalted with the Arathi Basin faction (Defilers / League of Arathor)", rep = "ab" })
    add({ id = "pe:wsg", cat = "pvp", name = "Exalted: Warsong Gulch", req = "Exalted with the Warsong faction (Outriders / Silverwing)", rep = "wsg" })
    add({ id = "pe:dsi", cat = "pvp", name = "Exalted: Darkspear Islands", req = "Exalted with the Darkspear Islands battleground faction" })
    for _, w in ipairs({ 4, 7, 10 }) do
        add({ id = "pf:" .. w, cat = "pvp", name = (L["Field of Honor: Week %d"]):format(w), req = (L["Complete week %d of the Field of Honor season"]):format(w) })
    end
    add({ id = "a:explorer", cat = "adv", name = "Explorer", req = "Explore the entire world map on one character" })
    add({ id = "a:valthalak", cat = "adv", name = "Lord Valthalak Laid to Rest", req = "Quest chain from \"An Earnest Proposition\" to \"Saving the Best for Last\"" })
end
build()

function Legacy.Name(e)
    if e.cat == "class" then return className(e.class) .. ": " .. L[e.tier] .. " (" .. e.lvl .. ")" end
    if e.cat == "prof" then return profName(e.prof, e.profName) .. ": " .. L[e.tier] .. " (" .. e.skill .. ")" end
    return L[e.name]
end
function Legacy.Req(e)
    if e.cat == "class" then return (L["Get a %s to level %d"]):format(className(e.class), e.lvl) end
    if e.cat == "prof" then return (L["Raise %s to %d"]):format(profName(e.prof, e.profName), e.skill) end
    return L[e.req]
end
function Legacy.Icon(e)
    if e.icon then return e.icon end
    return CAT_BY[e.cat].icon
end

------------------------------------------------------------------------
-- players (main + alts) and their characters
------------------------------------------------------------------------
local function profsOf(name)
    local c = ns.db.chars[name]
    if c and c.profs then return c.profs end
    local p = ns.db.members[name]
    if p and p.profs and p.profs ~= "" then return p.profs end
    return ns.db.guildProfs and ns.db.guildProfs[name]
end
local function charInfo(name)
    local c = ns.db.chars[name]
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
    local p = ns.db.members[name]
    local lvl = math.max(c and c.level or 0, m and m.level or 0, p and p.lvl or 0)
    local cls = (c and c.class) or (m and m.class) or (p and p.class)
    return lvl, cls
end

-- all known players: [main] = { chars = {...} }
function Legacy.Players()
    local players = {}
    local function put(name)
        if not name then return end
        local main = ns.Alts and ns.Alts.Main(name) or name
        local p = players[main]
        if not p then p = { main = main, chars = {}, set = {} } players[main] = p end
        if not p.set[name] then p.set[name] = true p.chars[#p.chars + 1] = name end
    end
    if ns.Radar and ns.Radar.roster then for _, m in ipairs(ns.Radar.roster) do put(m.name) end end
    for name in pairs(ns.db.legacy) do put(name) end
    for name in pairs(ns.db.chars) do put(name) end
    return players
end

-- a player's state: done[id] = character name/true, best[id] = progress (0..1) + text
function Legacy.StateOf(chars)
    local done, prog = {}, {}
    for _, name in ipairs(chars) do
        local lvl, cls = charInfo(name)
        if cls then
            for _, t in ipairs(CLASS_TIERS) do
                local id = "c:" .. cls .. ":" .. t[1]
                if lvl >= t[1] then done[id] = done[id] or name
                else
                    local f = lvl / t[1]
                    if lvl > 0 and (not prog[id] or f > prog[id].f) then prog[id] = { f = f, text = ns.displayName(name) .. " " .. lvl .. "/" .. t[1], who = name, cur = lvl, max = t[1] } end
                    break
                end
            end
        end
        if ns.Radar and ns.Radar.decodeProfs then
            for _, pf in ipairs(ns.Radar.decodeProfs(profsOf(name))) do
                local pid = ns.Radar.ProfId and ns.Radar.ProfId(pf)
                if pid then
                    for _, t in ipairs(PROF_TIERS) do
                        local id = "p:" .. pid .. ":" .. t[1]
                        if Legacy.byId[id] then
                            if (pf.rank or 0) >= t[1] then done[id] = done[id] or name
                            else
                                local f = (pf.rank or 0) / t[1]
                                if not prog[id] or f > prog[id].f then prog[id] = { f = f, text = ns.displayName(name) .. " " .. (pf.rank or 0) .. "/" .. t[1], who = name, cur = pf.rank or 0, max = t[1] } end
                                break
                            end
                        end
                    end
                end
            end
        end
        local shared = ns.db.legacy[name]
        if shared and shared.done then
            for id in pairs(shared.done) do if Legacy.byId[id] then done[id] = done[id] or true end end
        end
    end
    return done, prog
end

local function count(done)
    local n = 0
    for id in pairs(done) do if Legacy.byId[id] then n = n + 1 end end
    return n
end
Legacy.Count = count

-- own account
local myCache, realCache
-- real = true: without demo state (for everything that is saved or sent to the guild)
function Legacy.Mine(real)
    local useDemo = Legacy.demoMine and not real
    local cache = useDemo and myCache or realCache
    if cache and GetTime() - cache.t < 2 then return cache.done, cache.prog end
    local chars = ns.Alts and ns.Alts.CharsOf(ns.Alts.MyMain()) or { ns.me() }
    local done, prog = Legacy.StateOf(chars)
    for id in pairs(ns.db.legacyManual or {}) do if Legacy.byId[id] then done[id] = done[id] or true end end
    for name in pairs(ns.db.chars) do
        for id in pairs(ns.db.chars[name].legacyAuto or {}) do if Legacy.byId[id] then done[id] = done[id] or name end end
    end
    -- demo mode: own sample state (local only, never saved or sent)
    if useDemo then
        for id in pairs(Legacy.demoMine.done) do if Legacy.byId[id] then done[id] = done[id] or true end end
        for id, x in pairs(Legacy.demoMine.prog) do if not done[id] and not prog[id] then prog[id] = x end end
        myCache = { t = GetTime(), done = done, prog = prog }
    else
        realCache = { t = GetTime(), done = done, prog = prog }
    end
    return done, prog
end
local allCache
local function dirty() myCache, realCache, allCache = nil, nil, nil end

-- all players with state, briefly cached (a list with 65 rows would otherwise query the whole guild 65x)
function Legacy.AllStates()
    if allCache and GetTime() - allCache.t < 3 then return allCache.list end
    local myMain = ns.Alts and ns.Alts.MyMain() or ns.me()
    local list = {}
    for main, p in pairs(Legacy.Players()) do
        local done
        if main == myMain then done = Legacy.Mine() else done = Legacy.StateOf(p.chars) end
        list[#list + 1] = { main = main, chars = p.chars, done = done, me = main == myMain }
    end
    allCache = { t = GetTime(), list = list }
    return list
end
Legacy.Dirty = dirty

function Legacy.myHash()
    local done = Legacy.Mine(true)
    local ids = {}
    for id in pairs(done) do ids[#ids + 1] = id end
    if #ids == 0 then return "" end
    table.sort(ids)
    return ns.hash(table.concat(ids, ","))
end
function Legacy.myDoneCount() return count((Legacy.Mine(true))) end

-- Who has it / who needs it (per player)
function Legacy.WhoDone(id)
    local done, need = {}, {}
    for _, x in ipairs(Legacy.AllStates()) do
        if x.done[id] then done[#done + 1] = x.main elseif x.me or count(x.done) > 0 or ns.db.members[x.main] then need[#need + 1] = x.main end
    end
    table.sort(done) table.sort(need)
    return done, need
end

------------------------------------------------------------------------
-- Own characters: remember class, professions, reputation, PvP rank (account-wide in OasisDB)
------------------------------------------------------------------------
local function repExalted(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
        if ok and type(d) == "table" then return (ns.safe(d.reaction) or 0) >= 8 end
    end
    if GetFactionInfoByID then
        local ok, _, _, standing = pcall(GetFactionInfoByID, id)
        if ok then return (ns.safe(standing) or 0) >= 8 end
    end
    return false
end
local function pvpRank()
    local best = 0
    if GetPVPLifetimeStats then
        local ok, _, _, highest = pcall(GetPVPLifetimeStats)
        highest = ok and ns.safe(highest)
        if type(highest) == "number" and highest > 4 then best = highest - 4 end
    end
    if UnitPVPRank then
        local ok, r = pcall(UnitPVPRank, "player")
        r = ok and ns.safe(r)
        if type(r) == "number" and r > 4 then best = math.max(best, r - 4) end
    end
    return best
end

local firstCheck = true
-- open Blizzard's Legacy window: the name differs per client, hence several ways
function Legacy.OpenBlizzard()
    -- load a loadable Blizzard addon with "Legacy" in its name first
    local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local GetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local Load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if GetNum and GetInfo and Load then
        for i = 1, GetNum() do
            local name = GetInfo(i)
            if type(name) == "string" and name:find("^Blizzard_") and name:lower():find("legacy") then pcall(Load, name) end
        end
    end
    for _, fn in ipairs({ "ToggleLegacySystemUI", "ToggleLegacyUI", "ToggleLegacyFrame", "LegacyFrame_Toggle", "ToggleLegacy" }) do
        if type(_G[fn]) == "function" and pcall(_G[fn]) then return true end
    end
    for _, fr in ipairs({ "LegacySystemFrame", "LegacyFrame", "LegacyUIFrame", "LegacyChallengeFrame" }) do
        local f = _G[fr]
        if type(f) == "table" and f.SetShown then f:SetShown(not f:IsShown()) return true end
    end
    -- last attempt: top-level Blizzard frame with "Legacy" in its name
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("Legacy") and not k:find("^Oasis") and type(v) == "table" and v.GetObjectType then
            local ok, typ = pcall(v.GetObjectType, v)
            if ok and typ == "Frame" and v.GetParent and v:GetParent() == UIParent then v:SetShown(not v:IsShown()) return true end
        end
    end
    -- other functions with "Legacy" in their name (Toggle/Show/Open)
    local tried = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" and k:find("[Ll]egacy") and (k:find("Toggle") or k:find("Show") or k:find("Open")) and not k:find("^Oasis") then
            tried[#tried + 1] = k
        end
    end
    table.sort(tried)
    for _, k in ipairs(tried) do
        if pcall(_G[k]) then return true end
    end
    -- the game's chat command (e.g. /legacy)
    for key, fn in pairs(SlashCmdList or {}) do
        if type(key) == "string" and key:upper():find("LEGACY") and type(fn) == "function" then
            if pcall(fn, "") then return true end
        end
    end
    Legacy.lastTried = tried
    return false
end

function Legacy.Scan()
    if not ns.char or ns.inCombat() then return end
    local c = ns.char
    local _, cf = UnitClass("player")
    c.class = ns.safe(cf) or c.class
    c.level = ns.safe(UnitLevel("player")) or c.level
    if ns.Radar and ns.Radar.myProfessions then
        local ok, list = pcall(ns.Radar.myProfessions)
        if ok and type(list) == "table" then
            local p = {}
            for _, x in ipairs(list) do p[#p + 1] = x.name .. "/" .. x.rank .. "/" .. x.max .. "/" .. (x.id or 0) end
            c.profs = table.concat(p, "+")
        end
    end
    c.legacyAuto = c.legacyAuto or {}
    for key, ids in pairs(REPS) do
        for _, id in ipairs(ids) do if repExalted(id) then c.legacyAuto["pe:" .. key] = true end end
    end
    local rank = pvpRank()
    for _, r in ipairs({ 3, 7, 10, 13, 14 }) do if rank >= r then c.legacyAuto["pr:" .. r] = true end end
    dirty()
    -- newly completed? (chronicle + guild chat)
    local done = Legacy.Mine(true)
    if not ns.db.legacyKnown then
        ns.db.legacyKnown = {}
        for id in pairs(done) do ns.db.legacyKnown[id] = true end
    else
        for id in pairs(done) do
            if not ns.db.legacyKnown[id] then
                ns.db.legacyKnown[id] = true
                -- only report what this character just completed (not reloaded alt/guild data)
                if not firstCheck and (done[id] == ns.me() or Legacy.IsManual(id)) then
                    ns.Fire("LEGACY_DONE", { id = id, name = Legacy.Name(Legacy.byId[id]) })
                end
            end
        end
    end
    firstCheck = false
    local hash = Legacy.myHash()
    if hash ~= Legacy.lastHash then
        Legacy.lastHash = hash
        if ns.Radar and ns.loggedIn then ns.Radar.SendHello() end
    end
    ns.RefreshPage("legacy")
end

function Legacy.SetManual(id, on)
    ns.db.legacyManual = ns.db.legacyManual or {}
    ns.db.legacyManual[id] = on and ns.now() or nil
    if not on and ns.db.legacyKnown then ns.db.legacyKnown[id] = nil end
    Legacy.Scan()
end
function Legacy.IsManual(id) return ns.db.legacyManual and ns.db.legacyManual[id] ~= nil end

ns.On("PLAYER_LEVEL_UP", function() ns.After(2, Legacy.Scan) end)
ns.On("SKILL_LINES_CHANGED", function() ns.After(3, Legacy.Scan) end)
ns.On("UPDATE_FACTION", function() ns.After(3, Legacy.Scan) end)
ns.On("PLAYER_PVP_RANK_CHANGED", function() ns.After(3, Legacy.Scan) end)
ns.Listen("PROFILE", function() dirty() end)

------------------------------------------------------------------------
-- Exchange: keys of completed challenges (whole account)
------------------------------------------------------------------------
local requested = {}
ns.Listen("PROFILE", function(name, p)
    if ns.isMe(name) or not p.lh or p.lh == "" then return end
    local have = ns.db.legacy[name]
    if have and have.hash == p.lh then return end
    if requested[name] and GetTime() - requested[name] < 180 then return end
    requested[name] = GetTime()
    ns.After(math.random(10, 80) / 10, function() Comm.Whisper(name, "LREQ") end)
end)
Comm.On("LREQ", function(sender)
    -- answer each sender at most once per minute (otherwise the whole guild answers in rapid fire)
    if not SEC.Rate("lreq:" .. tostring(sender), 60) then return end
    local done = Legacy.Mine(true)
    local ids = {}
    for id in pairs(done) do ids[#ids + 1] = id end
    table.sort(ids)
    Comm.Whisper(sender, "LDATA", Legacy.myHash(), table.concat(ids, "+"))
end)
Comm.On("LDATA", function(sender, _, hash, ids)
    -- only after own request (otherwise anyone fills the saved data)
    if not requested[sender] or GetTime() - requested[sender] > 300 then return end
    local done = {}
    for id in tostring(ids or ""):sub(1, 4000):gmatch("[^+]+") do if Legacy.byId[id] then done[id] = true end end
    ns.db.legacy[sender] = { hash = tostring(hash or ""):sub(1, 40), u = ns.now(), done = done }
    ns.RefreshPage("legacy")
end)

------------------------------------------------------------------------
-- Find companions
------------------------------------------------------------------------
-- Guild options (guild leadership): allow companion search to the guild, minimum interval against spam
ns.GuildOption({ page = "legacy", key = "lgLfg", default = true,
    label = "Partner search to the guild", desc = "Players may look for partners in the guild for a Legacy challenge (notice for everyone)." })
ns.GuildOption({ page = "legacy", key = "lgCd", default = 0, min = 0, max = 30, step = 1,
    label = "Minimum gap between searches", desc = "Minutes a player must wait before sending the next search (0 = no limit).",
    fmt = function(v) return v == 0 and L["off"] or (v .. " min") end })
local lastSearch = 0
function Legacy.Search(e, note)
    if ns.GuildOpt("lgLfg") == false then ns.print(L["The guild leadership has disabled the partner search."]) return end
    local cd = (tonumber(ns.GuildOpt("lgCd")) or 0) * 60
    if cd > 0 and GetTime() - lastSearch < cd then
        ns.print((L["Next search possible in %d min."]):format(math.ceil((cd - (GetTime() - lastSearch)) / 60)))
        return
    end
    lastSearch = GetTime()
    Comm.Guild("LFG", e.id, Legacy.Name(e), note or "")
    Legacy.searches[ns.me()] = { name = ns.me(), id = e.id, activity = Legacy.Name(e), note = note or "", t = ns.now() }
    K.Toast(L["Search sent"], Legacy.Name(e), C.violet)
    ns.RefreshPage("legacy")
end
Comm.On("LFG", function(sender, _, id, name, note)
    if ns.GuildOpt("lgLfg") == false then return end
    local e = Legacy.byId[id]
    if not e then return end   -- only known challenges (no free text as title)
    name = Legacy.Name(e)
    note = SEC.Text(note, 80)
    -- per sender at most once a minute (notice + sound)
    if not SEC.Rate("lfg:" .. sender, 60) then return end
    Legacy.searches[sender] = { name = sender, id = id, activity = name, note = note, t = ns.now() }
    if not ((Legacy.Mine())[id]) or ns.db.settings.legacyLfgDone then
        ns.Sound.Next("group")
        K.Toast(ns.displayName(sender) .. L[" is looking for help"], (name or "?") .. ((note or "") ~= "" and (" - " .. note) or ""), C.violet,
            function() ns.Whisper(sender) end)
    end
    ns.RefreshPage("legacy")
end)
function Legacy.ActiveSearches()
    local out, now = {}, ns.now()
    for name, s in pairs(Legacy.searches) do
        if now - s.t < 1800 then out[#out + 1] = s else Legacy.searches[name] = nil end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

------------------------------------------------------------------------
-- Perk planner (21 perks in 3 trees, max. 16 points per character)
------------------------------------------------------------------------
local TREES = {
    { key = "adv", name = "Adventure", perks = {
        { "wellrested", "Well Rested", 5, 0, nil, "Rested XP builds up 20% faster, cap +20%." },
        { "thrill", "Thrill of Adventure", 5, 0, nil, "Non-trivial kills restore 1–5% max health/mana over 10 s (not in dungeons, raids, PvP)." },
        { "quickdead", "The Quick and the Dead", 2, 0, nil, "10% faster while dead; free casts for 2 min after resurrection." },
        { "alert", "High Alert", 2, 5, nil, "Detect stealthed targets 1–2 levels higher (not in battlegrounds)." },
        { "talented", "Talented", 5, 5, "wellrested", "Gain talent points from level 5–9 instead of 10 (max 51)." },
        { "fieldguide", "Field Guide", 3, 5, nil, "Camping cooldown 8–25% shorter." },
        { "fieldmed", "Field Medicine", 2, 5, nil, "Recently Bandaged 5–10 s shorter (not in dungeons, raids, PvP)." },
        { "flier", "Frequent Flier", 1, 10, "fieldguide", "Flight paths 50% cheaper, flights 20% faster." },
    } },
    { key = "prof", name = "Professions", perks = {
        { "overtime", "Working Overtime", 5, 0, nil, "Skill-up chance +4–20%." },
        { "harvest", "Bountiful Harvest", 5, 0, nil, "20–100% more scarce materials when gathering." },
        { "chef", "Master Chef", 5, 5, nil, "Cooking: 10–50% chance for an extra result." },
        { "barter", "Bartering", 2, 5, nil, "All vendor items 5–10% cheaper." },
        { "bonus", "Performance Bonus", 3, 5, "harvest", "Supply crates: 15% chance for double Merchant's Favor." },
        { "lure", "Luremaster", 2, 5, nil, "With a lure active, 25–50% chance for an extra fish." },
        { "study", "Dedicated Study", 1, 10, "barter", "Lowest tradeskill +1 – or 2–4 Elemental Essences if all are maxed." },
    } },
    { key = "res", name = "Resourcefulness", perks = {
        { "gourmand", "Gourmand", 3, 0, nil, "Food buffs last 33–100% longer." },
        { "reinforce", "Reinforce", 5, 0, nil, "8–40% less durability loss on death." },
        { "honor", "For Great Honor", 5, 5, nil, "2–10% more honor points." },
        { "permanence", "Permanence", 2, 5, "gourmand", "Party/raid buffs and camp benefits last 50–100% longer." },
        { "diplomat", "Diplomat", 5, 5, nil, "Reputation gains +2–10%." },
        { "reagent", "Reagent Economy", 1, 10, "quickdead", "Class abilities need no vendor reagents; camping tier 1 free." },
    } },
}
Legacy.TREES = TREES
-- 0.5.680: icon per perk (Blizzard icons from the game)
local PERK_ICON = {
    wellrested = "Spell_Nature_Sleep", thrill = "Spell_Shadow_LifeDrain02", quickdead = "Ability_Rogue_Sprint",
    alert = "Spell_Shadow_DetectInvisibility", talented = "INV_Misc_Book_11", fieldguide = "INV_Misc_Map_01",
    fieldmed = "INV_Misc_Bandage_15", flier = "Ability_Hunter_EagleEye",
    overtime = "INV_Misc_PocketWatch_01", harvest = "INV_Misc_Herb_08", chef = "INV_Misc_Food_15",
    barter = "INV_Misc_Coin_02", bonus = "INV_Crate_01", lure = "Trade_Fishing", study = "INV_Misc_Book_07",
    gourmand = "INV_Misc_Food_14", reinforce = "Trade_BlackSmithing", honor = "INV_BannerPVP_02",
    permanence = "Spell_Holy_WordFortitude", diplomat = "INV_Scroll_03", reagent = "INV_Misc_Dust_02",
}
Legacy.PERK_ICON = PERK_ICON
local PERK = {}
for _, t in ipairs(TREES) do
    for _, pk in ipairs(t.perks) do PERK[pk[1]] = { key = pk[1], name = pk[2], max = pk[3], gate = pk[4], req = pk[5], desc = pk[6], tree = t.key } end
end

local function plan()
    ns.db.settings.legacyPlan = ns.db.settings.legacyPlan or {}
    return ns.db.settings.legacyPlan
end
function Legacy.PlanSpent(tree)
    local n = 0
    for k, r in pairs(plan()) do
        local pk = PERK[k]
        if pk and (not tree or pk.tree == tree) then n = n + r end
    end
    return n
end
function Legacy.PerkAvailable(key)
    local pk = PERK[key]
    if Legacy.PlanSpent(pk.tree) - (plan()[key] or 0) < pk.gate then return false, (L["needs %d points in tree"]):format(pk.gate) end
    if pk.req and (plan()[pk.req] or 0) < 1 then return false, (L["needs %s"]):format(L[PERK[pk.req].name]) end
    return true
end
function Legacy.PerkChange(key, delta)
    local p, pk = plan(), PERK[key]
    local r = (p[key] or 0) + delta
    if r < 0 or r > pk.max then return end
    if delta > 0 and (Legacy.PlanSpent() >= MAX_SPEND or not Legacy.PerkAvailable(key)) then return end
    p[key] = r > 0 and r or nil
    -- reset dependent perks whose condition no longer holds
    if delta < 0 then
        for k in pairs(p) do if k ~= key and not Legacy.PerkAvailable(k) then p[k] = nil end end
    end
    ns.RefreshPage("legacy")
end

------------------------------------------------------------------------
-- Demo (local only): Legacy state of the demo people + own sample state
------------------------------------------------------------------------
local DEMO = {
    Grukthar = "d:1+d:2+r:ony+pr:3+pr:7+pe:wsg+pf:4+a:explorer",
    ["Zul'mira"] = "d:1+pe:ab+pf:4+pf:7",
    Tavira = "d:1+d:2+r:ony+a:explorer",
    Mokrash = "d:1+pr:3",
    Hoknar = "d:1",
    ["Vex'ra"] = "d:1+d:2+r:ony+pr:3+pr:7+pr:10+pe:av+pe:wsg+pf:4+pf:7+pf:10+a:explorer+a:valthalak",
    Nakira = "d:1+pf:4",
    Yenzi = "d:1+d:2+pe:ab",
    Drogbar = "d:1+pr:3+pe:wsg",
}
-- own demo state: 12 points (3 before the collection reward), plus progress for "Next steps"
local DEMO_ME = "c:WARRIOR:25+c:WARRIOR:45+c:PRIEST:25+p:164:150+p:164:225+d:1+d:2+r:ony+pr:3+pe:wsg+pf:4+a:explorer"
local DEMO_PROG = { { "c:WARRIOR:60", 52 }, { "p:164:300", 262 }, { "c:PRIEST:45", 38 }, { "p:171:150", 118 }, { "c:MAGE:25", 14 } }
function Legacy.SeedDemo()
    for who, ids in pairs(DEMO) do
        local done = {}
        for id in ids:gmatch("[^+]+") do done[id] = true end
        ns.db.legacy[ns.fullName(who)] = { hash = "demo", u = ns.now(), done = done, demo = true }
    end
    local mine = { done = {}, prog = {} }
    for id in DEMO_ME:gmatch("[^+]+") do mine.done[id] = true end
    for _, x in ipairs(DEMO_PROG) do
        local e = Legacy.byId[x[1]]
        if e then
            local max = e.lvl or e.skill or 1
            mine.prog[x[1]] = { f = x[2] / max, text = ns.displayName(ns.me()) .. " " .. x[2] .. "/" .. max, who = ns.me(), cur = x[2], max = max }
        end
    end
    Legacy.demoMine = mine
    local function s(who, id, note, ago)
        local n = ns.fullName(who)
        Legacy.searches[n] = { name = n, id = id, activity = Legacy.Name(Legacy.byId[id]), note = note, t = ns.now() - ago, demo = true }
    end
    s("Tavira", "r:deeps", L["Tonight 8 pm, meet in Orgrimmar"], 300)
    s("Mokrash", "d:2", L["I still need Uldaman and Zul'Farrak"], 900)
    s("Nakira", "pe:ab", L["Farming Arathi Basin rep, who's in?"], 1500)
    dirty()
    ns.RefreshPage("legacy")
end
function Legacy.RemoveDemo()
    for name, d in pairs(ns.db.legacy) do if d.demo then ns.db.legacy[name] = nil end end
    for name, s in pairs(Legacy.searches) do if s.demo then Legacy.searches[name] = nil end end
    Legacy.demoMine = nil
    dirty()
    ns.RefreshPage("legacy")
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local view, catFilter, stateFilter, search, selected, forMe = "home", "all", "open", "", nil, false
local TOP = -54                       -- content below the tabs
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local ICON = ns.MEDIA .. "icons\\"
local CAT_COLOR = { class = C.amber, prof = C.mint, dungeon = C.blue, raid = C.accent, pvp = C.red, adv = C.pink }
local TREE_COLOR = { adv = C.mint, prof = C.amber, res = C.blue }
local MEDAL = { { 1, 0.80, 0.25 }, { 0.80, 0.82, 0.88 }, { 0.85, 0.54, 0.30 } }
-- where a button in the details leads (only if the page exists and is visible)
local GOTO = { dungeon = { "groups", "Find a group" }, raid = { "raid", "Raid dates" }, pvp = { "groups", "Find a group" },
    adv = { "map", "To the map" } }

local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function catColor(key) return CAT_COLOR[key] or C.accent end
local function grad(tex, dir, c, a1, a2)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2)
    end
end
local function pageOk(key) return ns.PageDef(key) ~= nil and ns.PageVisible(key) end

-- 2026: glass look like Profile/Collections/Badges (helpers from ns.Insta; if missing, the old surface stays)
local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
local function glass(f, fill, line, r) if hasGlass() then ns.Insta.Glass(f, fill, line, r) end end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
-- calm glass button: primary = subtly tinted in accent color, otherwise neutral
local function calmBtn(b, primary)
    if not (b and hasGlass()) then return b end
    local ac = C.accent
    local fill = primary and { ac[1], ac[2], ac[3], 0.16 } or { 1, 1, 1, 0.05 }
    local line = primary and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.10 }
    if b.sheen then b.sheen:Hide() end
    glass(b, fill, line, 8)
    b:SetScript("OnEnter", function(self) glass(self, { fill[1], fill[2], fill[3], fill[4] + 0.05 }, { line[1], line[2], line[3], line[4] + 0.12 }) end)
    b:SetScript("OnLeave", function(self) glass(self, fill, line) end)
    return b
end
-- segments as glass pills (function and Select interface stay)
local function pillSegs(seg)
    if not (seg and seg.buttons and hasGlass()) then return seg end
    local x = 0
    for _, b in ipairs(seg.buttons) do
        if b.under then b.under:Hide() b.under:SetAlpha(0) end
        b:SetHeight(26)
        b:ClearAllPoints()
        b:SetPoint("LEFT", seg, "LEFT", x, 0)
        x = x + (b:GetWidth() or 48) + 5
        glass(b, nil, nil, 9)
    end
    seg:SetHeight(26)
    seg:SetWidth(math.max(10, x - 5))
    local orig = seg.Select
    function seg:Select(key, user)
        orig(self, key, user)
        local ac = C.accent
        for _, b in ipairs(self.buttons) do
            if b.under then b.under:Hide() end
            local on = b.key == key
            glass(b, on and { ac[1], ac[2], ac[3], 0.15 } or { 1, 1, 1, 0.035 }, on and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.08 })
        end
    end
    seg:Select(seg.value)
    return seg
end
-- section header in normal case, without pulsing dot
local function gameHead(parent, text, color)
    local h = K.GameHead(parent, text, color)
    h.text:SetText(text)
    if h.mark then h.mark:SetSize(3, 12) end
    h.Live = function() end
    return h
end

local function catCounts(done)
    local have, total = {}, {}
    for _, e in ipairs(Legacy.list) do
        total[e.cat] = (total[e.cat] or 0) + 1
        if done[e.id] then have[e.cat] = (have[e.cat] or 0) + 1 end
    end
    return have, total
end

local function nextReward(n)
    for _, r in ipairs(REWARDS) do if n < r then return r end end
end
local function prevReward(n)
    local p = 0
    for _, r in ipairs(REWARDS) do if n >= r then p = r end end
    return p
end

local function names(list, max)
    local t = {}
    for i = 1, math.min(max or 12, #list) do
        local n = list[i]
        t[#t + 1] = (ns.Radar.IsOnline(n) and ns.Radar.Colored(n)) or ("|cff777777" .. ns.displayName(n) .. "|r")
    end
    if #list > (max or 12) then t[#t + 1] = "|cff888888+" .. (#list - (max or 12)) .. "|r" end
    return #t > 0 and table.concat(t, ", ") or L["|cff666666nobody|r"]
end

local function guildRanking()
    local out = {}
    for _, x in ipairs(Legacy.AllStates()) do
        local n = count(x.done)
        if n > 0 or x.me then
            out[#out + 1] = { main = x.main, n = n, have = (catCounts(x.done)), chars = x.chars, me = x.me, done = x.done }
        end
    end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.main < b.main end)
    for i, r in ipairs(out) do r.rank = i end
    return out
end

local function dungeonList(e)
    local t = {}
    if not (e.lo and ns.DungeonData) then return t end
    for _, d in ipairs(ns.DungeonData) do
        if d.lo and d.status ~= "client" and d.lo >= e.lo and d.lo <= e.hi then
            t[#t + 1] = (ns.lang == "de" and d.de or d.name) or d.name
        end
    end
    return t
end

local function classIcon(cf)
    if not cf then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return "Interface\\Icons\\ClassIcon_" .. cf:sub(1, 1) .. cf:sub(2):lower()
end
local function classOf(name)
    local _, cls = charInfo(name)
    if not cls and ns.Radar and ns.Radar.ClassOf then
        local ok, c = pcall(ns.Radar.ClassOf, name)
        if ok then cls = c end
    end
    return cls
end
local function openProfile(name)
    if ns.Profile and ns.Profile.Show then pcall(ns.Profile.Show, name) end
end

-- Relevant to me: classes/professions one of my characters has (or has started), everything else always
local function relevantSets(done, prog)
    local cls, prof = {}, {}
    local function mark(id)
        local e = Legacy.byId[id]
        if e and e.class then cls[e.class] = true end
        if e and e.prof then prof[e.prof] = true end
    end
    for id in pairs(done) do mark(id) end
    for id in pairs(prog) do mark(id) end
    local chars = ns.Alts and ns.Alts.CharsOf and ns.Alts.CharsOf(ns.Alts.MyMain()) or { ns.me() }
    for _, n in ipairs(chars or {}) do
        local _, c = charInfo(n)
        if c then cls[c] = true end
    end
    return cls, prof
end
local function isRelevant(e, done, cls, prof)
    if done[e.id] then return false end
    if e.cat == "class" then return cls[e.class] == true end
    if e.cat == "prof" then return prof[e.prof] == true end
    return true
end

-- concrete next step for a challenge
local function stepText(e, x)
    if x and x.cur and x.max then
        local left = math.max(0, x.max - x.cur)
        if e.cat == "class" then return (L["%s: %d more levels to %d"]):format(ns.displayName(x.who or ns.me()), left, x.max) end
        if e.cat == "prof" then return (L["%s: %d more points to %d"]):format(ns.displayName(x.who or ns.me()), left, x.max) end
    end
    if x and x.text then return L["Progress: "] .. x.text end
    return Legacy.Req(e)
end

-- Next steps: others' running searches, started challenges, then shared guild goals
local function nextSteps(done, prog)
    local out, seen = {}, {}
    for _, s in ipairs(Legacy.ActiveSearches()) do
        local e = Legacy.byId[s.id]
        if e and not done[e.id] and not ns.isMe(s.name) and not seen[e.id] then
            seen[e.id] = true
            out[#out + 1] = { e = e, kind = "search", s = s }
        end
    end
    local tmp = {}
    for id, x in pairs(prog) do
        local e = Legacy.byId[id]
        if e and not done[id] and not seen[id] then tmp[#tmp + 1] = { e = e, kind = "prog", f = x.f, x = x } end
    end
    table.sort(tmp, function(a, b) if a.f ~= b.f then return a.f > b.f end return a.e.id < b.e.id end)
    for _, t in ipairs(tmp) do seen[t.e.id] = true out[#out + 1] = t end
    local grp = {}
    for _, e in ipairs(Legacy.list) do
        if not e.auto and not done[e.id] and not seen[e.id] then
            local _, need = Legacy.WhoDone(e.id)
            grp[#grp + 1] = { e = e, kind = "group", need = math.max(0, #need - 1) }
        end
    end
    table.sort(grp, function(a, b) if a.need ~= b.need then return a.need > b.need end return a.e.id < b.e.id end)
    for i = 1, math.min(4, #grp) do out[#out + 1] = grp[i] end
    return out
end

-- tackle together: challenges to tick off by need in the guild (I need it -> search, I have it -> help)
local function together(done)
    local out = {}
    for _, e in ipairs(Legacy.list) do
        if not e.auto then
            local h, n = Legacy.WhoDone(e.id)
            local need = #n - (done[e.id] and 0 or 1)
            if need > 0 or not done[e.id] then
                out[#out + 1] = { e = e, have = #h, need = math.max(0, need), mine = done[e.id] and true or false }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return not a.mine end
        if a.need ~= b.need then return a.need > b.need end
        return a.e.id < b.e.id
    end)
    return out
end

------------------------------------------------------------------------
-- Building blocks: dot ring, box, tile finish, empty state
------------------------------------------------------------------------
-- progress ring made of dots (runs on every client, no cooldown trick needed)
local function Ring(parent, size, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.dots = {}
    f.color = color or C.accent
    -- 2026: densely placed small dots form a calm continuous line
    local n = math.max(28, math.floor(size * 1.5))
    local r = size / 2 - 3
    for i = 1, n do
        local d = f:CreateTexture(nil, "OVERLAY")
        d:SetTexture(CIRCLE)
        d:SetSize(3, 3)
        local a = math.pi / 2 - (i - 1) / n * math.pi * 2
        d:SetPoint("CENTER", f, "CENTER", math.cos(a) * r, math.sin(a) * r)
        f.dots[i] = d
    end
    function f:Paint(p)
        local k = math.floor(p * #self.dots + 0.5)
        local c = self.color
        for i, d in ipairs(self.dots) do
            if i <= k then d:SetVertexColor(c[1], c[2], c[3], 0.95) else d:SetVertexColor(1, 1, 1, 0.07) end
        end
    end
    function f:SetProgress(p, animate, delay)
        p = math.max(0, math.min(1, p or 0))
        self.p = p
        if animate and animOn() and p > 0 then
            self:Paint(0)
            K.Tween(self, 0.9, function(q) self:Paint(p * q) end, function() self:Paint(p) end, delay)
        else
            self:Paint(p)
        end
    end
    f:Paint(0)
    return f
end

local function box(parent, title, color)
    local f = K.Panel(parent, C.panel)
    f.color = color or C.accent
    f.glow = f:CreateTexture(nil, "BORDER", nil, 1)
    f.glow:SetPoint("TOPLEFT") f.glow:SetPoint("TOPRIGHT")
    f.glow:SetHeight(44)
    if hasGlass() then
        f.glow:Hide()
        glass(f, nil, nil, 12)
    else
        grad(f.glow, "VERTICAL", f.color, 0, 0.07)
    end
    f.head = gameHead(f, title, f.color)
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.head:SetPoint("RIGHT", -12, 0)
    return f
end

-- gradient, icon glow, hover glow with slight lift, shine sweep (like dashboard tiles)
local function dress(t, c)
    t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
    t.grad:SetAllPoints()
    grad(t.grad, "HORIZONTAL", c, 0.16, 0.02)
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 2)
    t.iconGlow:SetTexture(EMBER)
    t.iconGlow:SetBlendMode("ADD")
    t.iconGlow:SetSize(64, 64)
    t.iconGlow:SetPoint("CENTER", t.icon)
    t.iconGlow:SetVertexColor(c[1], c[2], c[3])
    t.iconGlow:SetAlpha(0.35)
    t.hov = t:CreateTexture(nil, "BORDER", nil, 3)
    t.hov:SetAllPoints()
    grad(t.hov, "VERTICAL", c, 0, 0.22)
    t.hov:SetAlpha(0)
    if hasGlass() then
        -- 2026: glass card instead of gradient/glow; hover only slightly brighter
        t.grad:Hide()
        t.iconGlow:SetTexture(nil)
        t.iconGlow:Hide()
        t.hov:SetColorTexture(1, 1, 1, 0.035)
        round(t.hov, t, 12)
        glass(t, nil, { c[1], c[2], c[3], 0.22 }, 12)
        t.noSweep = true
    end
    t.sweep = t:CreateTexture(nil, "OVERLAY", nil, 5)
    t.sweep:SetTexture(ns.MEDIA .. "shine")
    t.sweep:SetBlendMode("ADD")
    t.sweep:SetSize(46, 64)
    t.sweep:SetAlpha(0)
    t.lift = 0
    function t:Place()
        if not self.host then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self.host, "TOPLEFT", self.x or 0, (self.y or 0) + (self.lift or 0))
        self:SetSize(math.max(10, self.w or 100), self.h or 66)
    end
    local function hover(on)
        local from, to = t.lift or 0, on and (t.noSweep and 2 or 3) or 0
        local g0, g1 = t.hov:GetAlpha() or 0, on and 1 or 0
        local function step(q)
            t.lift = from + (to - from) * q
            t.hov:SetAlpha(g0 + (g1 - g0) * q)
            if not t.noSweep then t.iconGlow:SetAlpha(0.35 + 0.35 * (t.hov:GetAlpha() or 0)) end
            t:Place()
        end
        if animOn() then K.Tween(t.hov, 0.18, step) else step(1) end
    end
    t:HookScript("OnEnter", function() hover(true) end)
    t:HookScript("OnLeave", function() hover(false) end)
end
local function sweep(t, delay)
    if not animOn() or not t.sweep or t.noSweep then return end
    local w = t:GetWidth() or 140
    if w < 40 then w = 140 end
    K.Tween(t.sweep, 0.7, function(q)
        t.sweep:ClearAllPoints()
        t.sweep:SetPoint("CENTER", t, "LEFT", 20 + (w - 40) * q, 0)
        t.sweep:SetAlpha(0.55 * math.sin(q * math.pi))
    end, function() t.sweep:SetAlpha(0) end, delay)
end
-- fade content in softly from below (staggered)
local function rise(f, delay)
    if not animOn() then f:SetAlpha(1) return end
    f:SetAlpha(0)
    K.Tween(f, 0.3, function(q) f:SetAlpha(q) end, function() f:SetAlpha(1) end, delay)
    ns.After((delay or 0) + 1, function() if (f:GetAlpha() or 1) < 1 then f:SetAlpha(1) end end)
end
-- fill bar smoothly
local function fillBar(bar, v, animate, delay)
    if animate and animOn() and (v or 0) > 0 then
        bar:Set(0)
        K.Tween(bar, 0.7, function(q) bar:Set(v * q) end, function() bar:Set(v) end, delay)
    else
        bar:Set(v)
    end
end
local function barColor(bar, c, a) bar.fill:SetColorTexture(c[1], c[2], c[3], a or 1) end
local function roundBar(bar, r) round(bar.fill, bar, r or 2) return bar end

-- stat tile 2026: glass card, big number, normally written label with color mark, round bar
local function hudTile(parent, icon, label, color, onClick)
    local t = K.HudTile(parent, icon, label, color, onClick)
    if not hasGlass() then return t end
    t.label:SetText(label)
    t.glow:Hide()
    t.top:Hide()
    t.top:SetAlpha(0)
    t.hl:SetColorTexture(1, 1, 1, 0)
    t.mark = t:CreateTexture(nil, "ARTWORK")
    t.mark:SetColorTexture(color[1], color[2], color[3], 0.9)
    t.mark:SetSize(3, 11)
    round(t.mark, t.mark, 1)
    t.label:ClearAllPoints()
    t.label:SetPoint("BOTTOMLEFT", 22, 18)
    t.label:SetPoint("RIGHT", t, "RIGHT", -46, 0)
    t.label:SetWordWrap(false)
    if K.SetFontSafe then K.SetFontSafe(t.label, K.FONT, 11, "") end
    t.mark:SetPoint("RIGHT", t.label, "LEFT", -6, 0)
    t.pbar = K.Bar(t, 100, 4)
    t.pbar:SetPoint("BOTTOMLEFT", 14, 9)
    t.pbar:SetPoint("BOTTOMRIGHT", -14, 9)
    barColor(t.pbar, color, 0.9)
    roundBar(t.pbar)
    t.pbar:Hide()
    local orig = t.Set
    function t:Set(value, sub, progress, animate)
        orig(self, value, sub, nil, animate)
        self.bar:Hide()
        if progress then
            self.pbar:Show()
            fillBar(self.pbar, progress, animate, 0.1)
        else
            self.pbar:Hide()
        end
    end
    return t
end

-- challenge icon: classes via the class atlas (the ClassIcon_ files are missing in the client -> "?")
local function setIcon(tex, e)
    local GI = ns.GuildInfo
    if e and e.cat == "class" and e.class and GI and GI.SetClassIcon and GI.SetClassIcon(tex, e.class) then return end
    local path = e and ((e.cat == "class" and CAT_BY.class.icon) or Legacy.Icon(e)) or (ICON .. "groups")
    tex:SetTexture(path)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
-- player icon in rankings: round class icon, otherwise initial on a calm disc
local function portCell(r, size, x)
    r.portDisc = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.portDisc:SetTexture(CIRCLE)
    r.portDisc:SetSize(size, size)
    r.portDisc:SetPoint("LEFT", x, 0)
    r.port = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.port:SetSize(size, size)
    r.port:SetPoint("CENTER", r.portDisc)
    if r.port.SetMask then pcall(r.port.SetMask, r.port, CIRCLE) end K.MaskSafe(r.port)
    r.ini = K.Text(r, math.max(9, math.floor(size * 0.5)), C.text, "CENTER")
    r.ini:SetPoint("CENTER", r.portDisc, "CENTER", 0, 0)
    r.ini:SetWidth(size)
end
local function setPort(r, name)
    local cls = classOf(name)
    local GI = ns.GuildInfo
    local cc = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    local ok = cls and GI and GI.SetClassIcon and GI.SetClassIcon(r.port, cls)
    r.port:SetShown(ok and true or false)
    if ok then
        r.portDisc:SetVertexColor(0, 0, 0, 0.35)
        r.ini:Hide()
    else
        r.portDisc:SetVertexColor(cc and cc.r * 0.35 or 0.16, cc and cc.g * 0.35 or 0.16, cc and cc.b * 0.35 or 0.18, 1)
        local n = ns.displayName(name or "?") or "?"
        r.ini:SetText((n:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper())
        r.ini:Show()
    end
end

-- empty state: icon + sentence + action buttons
local function emptyState(parent, icon, color, text, acts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(64)
    f:SetPoint("TOPLEFT", 14, -40)
    f:SetPoint("RIGHT", -14, 0)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(52, 52)
    f.halo:SetPoint("CENTER", f, "TOPLEFT", 17, -17)
    f.halo:SetVertexColor(color[1], color[2], color[3])
    f.halo:SetAlpha(hasGlass() and 0 or 0.4)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(34, 34)
    f.disc:SetPoint("TOPLEFT", 0, 0)
    f.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
    f.icon = K.Glyph(f, 18, icon, color)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 12, C.muted)
    f.text:SetPoint("TOPLEFT", 46, -1)
    f.text:SetPoint("RIGHT", 0, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(true)
    f.text:SetText(text)
    f.btns = {}
    local prev
    for i, a in ipairs(acts or {}) do
        local b = calmBtn(K.Button(f, L[a[1]], 10, 22, i == 1 and "primary" or "ghost"), i == 1)
        b.label:SetFont(K.FONT, 11, "")
        local tw = b.label and b.label.GetStringWidth and b.label:GetStringWidth() or 0
        b:SetWidth(math.max(80, math.min(150, (tonumber(tw) or 0) + 24)))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 46, -36) end
        b:SetScript("OnClick", function() a[2]() end)
        f.btns[i] = b
        prev = b
    end
    f:Hide()
    return f
end

-- rank medal (1-3 gold/silver/bronze, otherwise a plain number)
local function medal(r, x)
    r.medal = r:CreateTexture(nil, "ARTWORK")
    r.medal:SetTexture(CIRCLE)
    r.medal:SetSize(20, 20)
    r.medal:SetPoint("LEFT", x, 0)
    r.medalRing = r:CreateTexture(nil, "BORDER")
    r.medalRing:SetTexture(CIRCLE)
    r.medalRing:SetSize(24, 24)
    r.medalRing:SetPoint("CENTER", r.medal)
    r.num = K.Text(r, 11, C.text, "CENTER")
    r.num:SetWidth(22)
    K.CenterNum(r.num, r.medal, "CENTER", 0, 0)
    function r:SetMedal(rank)
        local m = MEDAL[rank]
        self.medal:SetShown(m ~= nil)
        self.medalRing:SetShown(m ~= nil and not hasGlass())
        if m then
            self.medal:SetVertexColor(m[1], m[2], m[3], hasGlass() and 0.85 or 1)
            self.medalRing:SetVertexColor(m[1] * 0.45, m[2] * 0.45, m[3] * 0.45)
            self.num:SetTextColor(0.08, 0.07, 0.05)
        else
            self.num:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end
        self.num:SetText(rank)
    end
end

------------------------------------------------------------------------
-- switch tab + content
------------------------------------------------------------------------
local function makeTabs(p, items, onChange)
    if ns.Insta and ns.Insta.ProfileTabs then
        local ok, t = pcall(ns.Insta.ProfileTabs, p, items, onChange)
        if ok and t then return t end
    end
    return K.Segments(p, items, onChange)
end
local function goView(p, k)
    if p.tabs.value == k then
        if view ~= k then view = k p.fresh = true end
        ns.RefreshPage("legacy")
    else
        p.tabs:Select(k, true)   -- animates the bar and calls onChange
    end
end
local function openChallenge(p, id)
    selected = id
    local e = Legacy.byId[id]
    if e and catFilter ~= "all" and catFilter ~= e.cat then catFilter = "all" p.catSeg:Select("all") end
    if e and stateFilter ~= "all" then stateFilter = "all" p.stateSeg:Select("all") end
    goView(p, "list")
end
local function openCategory(p, key, complete)
    catFilter = key
    p.catSeg:Select(key)
    if complete then stateFilter = "all" p.stateSeg:Select("all") end
    selected = nil
    goView(p, "list")
end

ns.RegisterPage({
    key = "legacy", title = "Legacy", order = 4,
    sub = "The guild's Legacy challenges: who has what, who still needs what – and do them together",
    build = function(p)
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.tabs = makeTabs(p, {
            { key = "home", text = L["Overview"], icon = "legacy" },
            { key = "list", text = L["Challenges"], icon = "checklist" },
            { key = "perks", text = L["Perk planner"], icon = "stats" },
            { key = "guild", text = L["Guild"], icon = "groups" },
        }, function(k)
            if view ~= k then view = k p.fresh = true end
            ns.RefreshPage("legacy")
        end)
        p.tabs:SetPoint("TOPLEFT", 0, 0)
        p.tabs:SetPoint("RIGHT", p, "RIGHT", -140, 0)
        local open = K.Button(p, L["Legacy window"], 130, hasGlass() and 34 or 44, "ghost", function()
            if not Legacy.OpenBlizzard() then
                ns.print(L["Blizzard's legacy window was not found in this client - please open it from the game menu."])
                if Legacy.lastTried and #Legacy.lastTried > 0 then ns.print("  |cff888888" .. table.concat(Legacy.lastTried, ", ", 1, math.min(8, #Legacy.lastTried)) .. "|r") end
            end
            ns.After(1, Legacy.Scan)
        end)
        open:SetPoint("TOPRIGHT", 0, 0)
        calmBtn(open)
        open.label:SetFont(K.FONT, 12, "")
        open:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Legacy window"], L["Opens Blizzard's own Legacy window and re-reads your progress afterwards."] }) end)
        open:HookScript("OnLeave", function() GameTooltip:Hide() end)

        local function content()
            local f = CreateFrame("Frame", nil, p)
            f:SetPoint("TOPLEFT", 0, TOP)
            f:SetPoint("BOTTOMRIGHT")
            f:Hide()
            return f
        end

        ----------------------------------------------------------------
        -- Overview
        ----------------------------------------------------------------
        local home = content()
        p.home = home
        p.tiles = {}
        local tdefs = {
            { ICON .. "legacy", "Your Legacy points", C.accent, function() goView(p, "list") end },
            { ICON .. "stats", "Spendable per character", C.amber, function() goView(p, "perks") end },
            { ICON .. "badges", "Next collection reward", C.mint, function() goView(p, "list") end },
            { ICON .. "groups", "Guild total", C.blue, function() goView(p, "guild") end },
        }
        for i, d in ipairs(tdefs) do
            local t = hudTile(home, d[1], L[d[2]], d[3], d[4])
            t.host = home
            dress(t, d[3])
            if i == 1 or i == 3 then
                t.ring = Ring(t, 48, d[3])
                t.ring:SetPoint("CENTER", t.icon)
                t.icon:SetSize(22, 22)
            end
            p.tiles[i] = t
        end

        p.catHead = gameHead(home, L["Your categories"], C.amber)
        p.catHint = K.Text(home, 11, C.dim, "RIGHT")
        p.catHint:SetText(L["Click shows the challenges"])
        p.catCards = {}
        for i, c in ipairs(CATS) do
            local col = catColor(c.key)
            local b = CreateFrame("Button", nil, home)
            b.host = home
            b.bg = K.Fill(b, C.raised)
            K.Border(b, C.line)
            b.top = b:CreateTexture(nil, "ARTWORK")
            b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT")
            b.top:SetHeight(2)
            b.top:SetColorTexture(col[1], col[2], col[3], 0.8)
            if hasGlass() then b.top:Hide() end
            b.ring = Ring(b, 56, col)
            b.ring:SetPoint("TOP", 0, -8)
            b.icon = K.Icon(b, 30, c.icon)
            b.icon:SetPoint("CENTER", b.ring)
            dress(b, col)
            b.grad:Hide()
            glass(b, nil, nil, 12)
            if hasGlass() then round(b.icon, b.icon, 15) end
            b.name = K.Text(b, 12, C.text, "CENTER")
            b.name:SetPoint("TOP", b.ring, "BOTTOM", 0, -3)
            b.name:SetPoint("LEFT", 4, 0) b.name:SetPoint("RIGHT", -4, 0)
            b.name:SetText(L[c.name])
            b.cnt = K.Text(b, 11, C.muted, "CENTER")
            b.cnt:SetPoint("TOP", b.name, "BOTTOM", 0, -2)
            b.cnt:SetPoint("LEFT", 4, 0) b.cnt:SetPoint("RIGHT", -4, 0)
            b.key = c.key
            b:SetScript("OnClick", function(self) openCategory(p, self.key, self.complete) end)
            b:HookScript("OnEnter", function(self)
                if hasGlass() then glass(self, nil, { col[1], col[2], col[3], 0.40 }) else K.SetBorderColor(self, col) end
                local lines = { K.hex(col) .. L[c.name] .. "|r", (L["%d of %d done"]):format(self.nHave or 0, self.nTot or 0) }
                if self.open and #self.open > 0 then
                    lines[#lines + 1] = " "
                    lines[#lines + 1] = "|cff888888" .. L["Open next:"] .. "|r"
                    for j = 1, math.min(4, #self.open) do lines[#lines + 1] = "· " .. self.open[j] end
                end
                lines[#lines + 1] = " "
                lines[#lines + 1] = "|cff666666" .. L["Click: challenges in this category"] .. "|r"
                K.ShowTip(self, lines)
            end)
            b:HookScript("OnLeave", function(self) if hasGlass() then glass(self, nil, nil) else K.SetBorderColor(self, C.line) end GameTooltip:Hide() end)
            p.catCards[i] = b
        end

        -- Next steps
        local np = box(home, L["Next steps"], C.amber)
        p.nextBox = np
        p.nextList = K.List(np, 46, function(l)
            local r = K.Row(l)
            r.cstripe = r:CreateTexture(nil, "ARTWORK")
            r.cstripe:SetPoint("TOPLEFT") r.cstripe:SetPoint("BOTTOMLEFT")
            r.cstripe:SetWidth(2)
            if hasGlass() then r.cstripe:ClearAllPoints() r.cstripe:SetPoint("LEFT", 2, 0) r.cstripe:SetSize(3, 22) round(r.cstripe, r.cstripe, 1) end
            r.icon = K.Icon(r, 30, nil)
            r.icon:SetPoint("LEFT", 10, 0)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 48, -6)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -104, 0)
            r.cols.step = K.Text(r, 11, C.muted)
            r.cols.step:SetPoint("TOPLEFT", 48, -21)
            r.cols.step:SetPoint("RIGHT", r, "RIGHT", -104, 0)
            r.bar = roundBar(K.Bar(r, 100, 3))
            r.bar:SetPoint("BOTTOMLEFT", 48, 5)
            r.bar:SetPoint("RIGHT", r, "RIGHT", -104, 0)
            barColor(r.bar, C.amber)
            r.reward = K.Text(r, 10, C.amber, "RIGHT")
            r.reward:SetPoint("TOPRIGHT", -8, -6)
            r.reward:SetWidth(96)
            r.btn = calmBtn(K.Button(r, "", 90, 20, "ghost"))
            r.btn:SetPoint("BOTTOMRIGHT", -8, 5)
            r.btn.label:SetFont(K.FONT, 11, "")
            r:SetScript("OnClick", function(self) if self.item then openChallenge(p, self.item.e.id) end end)
            r:SetScript("OnEnter", function(self)
                local x = self.item
                if not x then return end
                K.ShowTip(self, { Legacy.Name(x.e), "|cffc8c8c8" .. Legacy.Req(x.e) .. "|r", " ", "|cff666666" .. L["Click: details"] .. "|r" })
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, x, idx)
            local e = x.e
            local c = catColor(e.cat)
            r.cstripe:SetColorTexture(c[1], c[2], c[3], 0.9)
            setIcon(r.icon, e)
            r.cols.name:SetText(Legacy.Name(e))
            if x.kind == "search" then
                r.cols.step:SetText(K.hex(C.violet) .. (L["%s is looking for companions"]):format(ns.displayName(x.s.name)) .. "|r"
                    .. ((x.s.note or "") ~= "" and ("  |cff999999" .. x.s.note .. "|r") or ""))
            elseif x.kind == "prog" then
                r.cols.step:SetText(stepText(e, x.x))
            else
                r.cols.step:SetText(x.need > 0 and (L["%d guildies need it too"]):format(x.need) or Legacy.Req(e))
            end
            r.bar:SetShown(x.f ~= nil)
            if x.f then fillBar(r.bar, x.f, p.animRows, 0.15 + idx * 0.05) end
            r.reward:SetText(p.rewardNext and ("+1 · " .. L["Reward!"]) or L["+1 point"])
            r.reward:SetTextColor(unpack(p.rewardNext and C.amber or C.dim))
            if x.kind == "search" then
                r.btn:SetLabel(L["Whisper"])
                r.btn:SetScript("OnClick", function() ns.Whisper(x.s.name) end)
            elseif e.auto then
                r.btn:SetLabel(L["View"])
                r.btn:SetScript("OnClick", function() openChallenge(p, e.id) end)
            else
                r.btn:SetLabel(L["Companions"])
                r.btn:SetScript("OnClick", function() Legacy.Search(e) end)
            end
        end)
        p.nextList:SetPoint("TOPLEFT", 4, -34)
        p.nextList:SetPoint("BOTTOMRIGHT", -4, 6)
        p.nextList.empty:SetText("")
        p.nextEmpty = emptyState(np, ICON .. "legacy", C.mint, L["All done – great! Now help others in the guild."],
            { { "View guild", function() goView(p, "guild") end } })

        -- Ranking
        local rp = box(home, L["Guild ranking"], C.blue)
        p.rankBox = rp
        p.rankList = K.List(rp, 30, function(l)
            local r = K.Row(l)
            medal(r, 8)
            portCell(r, 20, 36)
            r.cols.who = K.Text(r, 12, C.text)
            r.cols.who:SetPoint("LEFT", 62, 0)
            r.cols.who:SetWidth(118)
            r.bar = roundBar(K.Bar(r, 100, 5), 3)
            r.bar:SetPoint("LEFT", 186, 0)
            r.bar:SetPoint("RIGHT", r, "RIGHT", -40, 0)
            r.cols.n = K.Title(r, 13, C.text, "RIGHT")
            r.cols.n:SetPoint("RIGHT", -8, 0)
            r.cols.n:SetWidth(30)
            r:SetScript("OnClick", function(self) if self.item then openProfile(self.item.main) end end)
            r:SetScript("OnEnter", function(self)
                local x = self.item
                if not x then return end
                local _, total = catCounts({})
                local lines = { ns.Radar.Colored(x.main) .. "  |cff888888#" .. x.rank .. "|r", (L["%d of %d Legacy points"]):format(x.n, #Legacy.list), " " }
                for _, c in ipairs(CATS) do
                    local h, t = x.have[c.key] or 0, total[c.key] or 0
                    lines[#lines + 1] = K.hex(catColor(c.key)) .. L[c.name] .. "|r  " .. h .. "/" .. t
                end
                if not x.me then
                    local mine = Legacy.Mine()
                    local ahead = 0
                    for id in pairs(x.done) do if Legacy.byId[id] and not mine[id] then ahead = ahead + 1 end end
                    lines[#lines + 1] = " "
                    lines[#lines + 1] = ahead > 0 and (K.hex(C.mint) .. (L["Can help you with %d challenges"]):format(ahead) .. "|r") or "|cff888888" .. L["Has nothing you are missing"] .. "|r"
                end
                lines[#lines + 1] = (L["%d characters"]):format(#x.chars)
                lines[#lines + 1] = "|cff666666" .. L["Click: profile"] .. "|r"
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, x, idx)
            r:SetMedal(x.rank)
            setPort(r, x.main)
            r.cols.who:SetText(ns.Radar.Colored(x.main) .. (x.me and (" |cff888888(" .. L["you"] .. ")|r") or ""))
            local top = p.rankTop or 1
            barColor(r.bar, x.me and C.mint or (MEDAL[x.rank] or C.accent2))
            fillBar(r.bar, x.n / math.max(1, top), p.animRows, 0.1 + idx * 0.06)
            r.cols.n:SetText(x.n)
            r.sel:SetShown(x.me)
        end)
        p.rankList:SetPoint("TOPLEFT", 4, -34)
        p.rankList:SetPoint("BOTTOMRIGHT", -4, 6)
        p.rankList.empty:SetText(L["No guild data yet."])

        -- Companions wanted
        local sp = box(home, L["Looking for companions"], C.violet)
        p.searchBox = sp
        p.searchList = K.List(sp, 36, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 24, nil)
            r.icon:SetPoint("LEFT", 8, 0)
            r.cols.what = K.Text(r, 12, C.text)
            r.cols.what:SetPoint("TOPLEFT", 42, -4)
            r.cols.what:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            r.cols.meta = K.Text(r, 11, C.muted)
            r.cols.meta:SetPoint("BOTTOMLEFT", 42, 4)
            r.cols.meta:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            r.wh = calmBtn(K.Button(r, L["Whisper"], 84, 22, "ghost"))
            r.wh:SetPoint("RIGHT", -6, 0)
            r.wh.label:SetFont(K.FONT, 11, "")
            r:SetScript("OnClick", function(self) if self.item and Legacy.byId[self.item.id] then openChallenge(p, self.item.id) end end)
            return r
        end, function(r, s)
            local e = Legacy.byId[s.id]
            setIcon(r.icon, e)
            r.cols.what:SetText(s.activity or "?")
            r.cols.meta:SetText(ns.Radar.Colored(s.name) .. "  |cff777777" .. ns.ago(s.t) .. "|r" .. ((s.note or "") ~= "" and ("  |cff999999" .. s.note .. "|r") or ""))
            local me = ns.isMe(s.name)
            r.wh:SetLabel(me and L["Your search"] or L["Whisper"])
            r.wh:SetEnabledState(not me)
            r.wh:SetScript("OnClick", function() ns.Whisper(s.name) end)
        end)
        p.searchList:SetPoint("TOPLEFT", 4, -34)
        p.searchList:SetPoint("BOTTOMRIGHT", -4, 6)
        p.searchList.empty:SetText("")
        p.searchEmpty = emptyState(sp, ICON .. "groups", C.violet, L["Nobody is looking for companions right now. Start a search yourself!"],
            { { "Pick a challenge", function()
                stateFilter = "open" p.stateSeg:Select("open")
                forMe = true if p.meChip then p.meChip:Refresh() end
                goView(p, "list")
            end }, { "Tackle together", function() goView(p, "guild") end } })

        function home:Layout()
            local w, h = self:GetWidth() or 0, self:GetHeight() or 0
            if w < 100 then return end
            local tw = math.floor((w - 30) / 4)
            for i, t in ipairs(p.tiles) do
                t.x, t.y, t.w, t.h = (i - 1) * (tw + 10), 0, tw, 74
                t:Place()
            end
            p.catHead:ClearAllPoints()
            p.catHead:SetPoint("TOPLEFT", 2, -88)
            p.catHead:SetPoint("RIGHT", self, "RIGHT", -160, 0)
            p.catHint:ClearAllPoints()
            p.catHint:SetPoint("TOPRIGHT", -2, -90)
            local cw = math.floor((w - 5 * 8) / 6)
            for i, b in ipairs(p.catCards) do
                b.x, b.y, b.w, b.h = (i - 1) * (cw + 8), -110, cw, 104
                b:Place()
            end
            local y = -226
            local rest = math.max(120, h + y)
            local lw = math.floor((w - 10) * 0.52)
            np:ClearAllPoints()
            np:SetPoint("TOPLEFT", 0, y)
            np:SetSize(lw, rest)
            local rh = math.floor(rest * 0.52)
            rp:ClearAllPoints()
            rp:SetPoint("TOPLEFT", lw + 10, y)
            rp:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            rp:SetHeight(rh)
            sp:ClearAllPoints()
            sp:SetPoint("TOPLEFT", lw + 10, y - rh - 10)
            sp:SetPoint("BOTTOMRIGHT")
        end
        home:SetScript("OnSizeChanged", function(self) self:Layout() end)

        ----------------------------------------------------------------
        -- Challenges
        ----------------------------------------------------------------
        local list = content()
        p.list = list
        local citems = { { key = "all", text = L["All"] } }
        for _, c in ipairs(CATS) do citems[#citems + 1] = { key = c.key, text = L[c.name] } end
        p.catSeg = K.Segments(list, citems, function(k) catFilter = k selected = nil ns.RefreshPage("legacy") end)
        p.catSeg:SetPoint("TOPLEFT", 0, 0)
        pillSegs(p.catSeg)
        p.catSeg:Select(catFilter)
        p.stateSeg = K.Segments(list, { { key = "open", text = L["Open"] }, { key = "done", text = L["Done"] }, { key = "all", text = L["All"] } }, function(k)
            stateFilter = k
            ns.RefreshPage("legacy")
        end)
        p.stateSeg:SetPoint("TOPLEFT", 0, -32)
        pillSegs(p.stateSeg)
        p.stateSeg:Select(stateFilter)
        p.meChip = K.Chip(list, L["For me"], C.mint, function() return forMe end, function(v) forMe = v ns.RefreshPage("legacy") end, 92)
        p.meChip:SetPoint("LEFT", p.stateSeg, "RIGHT", 10, 0)
        p.meChip:HookScript("OnEnter", function(self) K.ShowTip(self, { L["For me"], L["Only open challenges that fit your characters (classes, professions) – plus all dungeons, raids, PvP and adventure."] }) end)
        p.meChip:HookScript("OnLeave", function() GameTooltip:Hide() end)
        p.searchBoxIn = K.Input(list, 150, L["Search ..."], function(t) search = (t or ""):lower() ns.RefreshPage("legacy") end)
        p.searchBoxIn:SetPoint("LEFT", p.meChip, "RIGHT", 10, 0)
        p.hits = K.Text(list, 11, C.dim)
        p.hits:SetPoint("LEFT", p.searchBoxIn, "RIGHT", 10, 0)

        p.cl = K.List(list, 40, function(l)
            local r = K.Row(l)
            r.check = r:CreateTexture(nil, "ARTWORK")
            r.check:SetSize(14, 14)
            r.check:SetPoint("LEFT", 9, 0)
            r.icon = K.Icon(r, 26, nil)
            r.icon:SetPoint("LEFT", 30, 0)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 64, -6)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -80, 0)
            r.cols.sub = K.Text(r, 11, C.dim)
            r.cols.sub:SetPoint("BOTTOMLEFT", 64, 6)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -80, 0)
            r.bar = roundBar(K.Bar(r, 56, 3))
            r.bar:SetPoint("BOTTOMRIGHT", -10, 9)
            barColor(r.bar, C.mint, 0.85)
            r.cols.cnt = K.Text(r, 11, C.muted, "RIGHT")
            r.cols.cnt:SetPoint("TOPRIGHT", -10, -7)
            r.cols.cnt:SetWidth(66)
            r.lfg = r:CreateTexture(nil, "OVERLAY")
            r.lfg:SetTexture(CIRCLE)
            r.lfg:SetSize(7, 7)
            r.lfg:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", -4, 2)
            r.lfg:SetVertexColor(C.violet[1], C.violet[2], C.violet[3])
            r:SetScript("OnClick", function(self) if self.item then selected = self.item.e.id ns.RefreshPage("legacy") end end)
            r:SetScript("OnEnter", function(self)
                local x = self.item
                if not x then return end
                local lines = { Legacy.Name(x.e), "|cffc8c8c8" .. Legacy.Req(x.e) .. "|r", " ",
                    (L["%d in the guild have it, %d need it"]):format(x.have, x.total - x.have) }
                if x.lfg then lines[#lines + 1] = K.hex(C.violet) .. (L["%s is looking for companions"]):format(ns.displayName(x.lfg.name)) .. "|r" end
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, x)
            local e = x.e
            r.check:SetTexture(ns.MEDIA .. (x.done and "dot" or "ring"))
            local c = x.done and C.mint or (x.prog and C.amber or C.dim)
            r.check:SetVertexColor(c[1], c[2], c[3])
            setIcon(r.icon, e)
            r.icon:SetDesaturated(not x.done)
            r.icon:SetAlpha(x.done and 1 or 0.8)
            local label = Legacy.Name(e)
            r.cols.name:SetText(x.done and ("|cffb8b8b8" .. label .. "|r") or label)
            if x.done then
                r.cols.sub:SetText(K.hex(C.mint) .. L["Done"] .. "|r" .. (type(x.done) == "string" and ("  |cff777777" .. (L["with %s"]):format(ns.displayName(x.done)) .. "|r") or ""))
            elseif x.prog then
                r.cols.sub:SetText(K.hex(C.amber) .. stepText(e, x.prog) .. "|r")
            else
                r.cols.sub:SetText(Legacy.Req(e))
            end
            r.bar:Set(x.total > 0 and x.have / x.total or 0)
            r.cols.cnt:SetText((L["%d/%d guild"]):format(x.have, x.total))
            r.lfg:SetShown(x.lfg ~= nil)
            r.sel:SetShown(selected == e.id)
        end)
        p.cl:SetPoint("TOPLEFT", 0, -66)
        p.cl:SetPoint("BOTTOMLEFT")
        p.cl.empty:SetText(L["No challenge matches the filter."])

        -- Details
        local d = K.Panel(list, C.panel)
        p.detail = d
        d.band = d:CreateTexture(nil, "BORDER", nil, 1)
        d.band:SetPoint("TOPLEFT") d.band:SetPoint("TOPRIGHT")
        d.band:SetHeight(72)
        glass(d, nil, nil, 12)
        d.dc = CreateFrame("Frame", nil, d)
        d.dc:SetAllPoints()
        local dc = d.dc
        p.dGlow = dc:CreateTexture(nil, "BACKGROUND")
        p.dGlow:SetTexture(EMBER)
        p.dGlow:SetBlendMode("ADD")
        p.dGlow:SetSize(84, 84)
        p.dGlow:SetAlpha(hasGlass() and 0 or 0.45)
        p.dIcon = K.Icon(dc, 42, nil)
        p.dIcon:SetPoint("TOPLEFT", 14, -14)
        if hasGlass() then round(p.dIcon, p.dIcon, 8) end
        p.dGlow:SetPoint("CENTER", p.dIcon)
        p.dName = K.Title(dc, 15, C.text)
        p.dName:SetPoint("TOPLEFT", 66, -16)
        p.dName:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dCat = K.Text(dc, 11, C.muted)
        p.dCat:SetPoint("TOPLEFT", p.dName, "BOTTOMLEFT", 0, -4)
        p.dCat:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dReq = K.Text(dc, 12, C.text)
        p.dReq:SetPoint("TOPLEFT", 14, -82)
        p.dReq:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dReq:SetWordWrap(true)
        p.dStatus = K.Text(dc, 12, C.text)
        p.dStatus:SetPoint("TOPLEFT", p.dReq, "BOTTOMLEFT", 0, -8)
        p.dStatus:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dBar = roundBar(K.Bar(dc, 100, 5), 3)
        p.dBar:SetPoint("TOPLEFT", p.dStatus, "BOTTOMLEFT", 0, -6)
        p.dBar:SetPoint("RIGHT", d, "RIGHT", -14, 0)
        barColor(p.dBar, C.amber)
        p.dMark = K.Button(dc, L["Mark as done"], 160, 22, "ghost", function()
            if selected then
                local on = not Legacy.IsManual(selected)
                Legacy.SetManual(selected, on)
                if on then K.Toast(L["Checked off"], Legacy.Name(Legacy.byId[selected]), C.mint) end
            end
        end)
        p.dMark:SetPoint("TOPLEFT", p.dBar, "BOTTOMLEFT", 0, -10)
        calmBtn(p.dMark)
        p.dMark.label:SetFont(K.FONT, 11, "")
        p.dGo = calmBtn(K.Button(dc, "", 120, 22, "ghost"))
        p.dGo.label:SetFont(K.FONT, 11, "")
        p.dBody = K.Text(dc, 12, C.text)
        p.dBody:SetPoint("TOPLEFT", p.dMark, "BOTTOMLEFT", 0, -12)
        p.dBody:SetPoint("RIGHT", d, "RIGHT", -12, 0)
        p.dBody:SetPoint("BOTTOM", d, "BOTTOM", 0, 84)
        p.dBody:SetWordWrap(true)
        p.dBody:SetJustifyV("TOP")
        p.dNote = K.Input(dc, 240, L["Note for the search (time, meeting point) ..."])
        p.dNote:SetPoint("BOTTOMLEFT", 14, 46)
        p.dNote:SetPoint("RIGHT", d, "RIGHT", -14, 0)
        p.dBtn = K.Button(dc, L["Find partners"], 240, 26, "primary", function()
            local e = selected and Legacy.byId[selected]
            if e then
                Legacy.Search(e, p.dNote:GetText())
                p.dNote:SetText("")
            end
        end)
        p.dBtn:SetPoint("BOTTOMLEFT", 14, 12)
        calmBtn(p.dBtn, true)
        p.dBtn:SetPoint("RIGHT", d, "RIGHT", -14, 0)
        p.dEmpty = emptyState(d, ICON .. "checklist", C.amber, L["No challenge selected – loosen the filters or click a row."],
            { { "Reset filters", function()
                catFilter, stateFilter, search, forMe = "all", "all", "", false
                p.catSeg:Select("all") p.stateSeg:Select("all") p.searchBoxIn:SetText("") p.meChip:Refresh()
                ns.RefreshPage("legacy")
            end } })

        function list:Layout()
            local w = self:GetWidth() or 0
            if w < 100 then return end
            local lw = math.floor(w * 0.55)
            p.cl:SetWidth(lw)
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", lw + 12, -66)
            d:SetPoint("BOTTOMRIGHT")
            p.hits:SetShown(w > 640)
        end
        list:SetScript("OnSizeChanged", function(self) self:Layout() end)

        ----------------------------------------------------------------
        -- Perk planner
        ----------------------------------------------------------------
        local perks = content()
        p.perks = perks
        local bud = K.Panel(perks, C.panel)
        p.budget = bud
        bud:SetPoint("TOPLEFT") bud:SetPoint("TOPRIGHT")
        bud:SetHeight(58)
        bud.glow = bud:CreateTexture(nil, "BORDER", nil, 1)
        bud.glow:SetAllPoints()
        grad(bud.glow, "HORIZONTAL", C.accent, 0.12, 0.0)
        if hasGlass() then bud.glow:Hide() glass(bud, nil, nil, 12) end
        bud.flash = bud:CreateTexture(nil, "OVERLAY")
        bud.flash:SetAllPoints()
        bud.flash:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.25)
        bud.flash:SetAlpha(0)
        p.pVal = K.Title(bud, 22, C.text)
        p.pVal:SetPoint("TOPLEFT", 14, -9)
        p.pLab = K.Text(bud, 11, C.muted)
        p.pLab:SetPoint("BOTTOMLEFT", 14, 9)
        p.pLab:SetText(L["Points planned"])
        p.segs = {}
        for i = 1, MAX_SPEND do
            local s = bud:CreateTexture(nil, "ARTWORK")
            s:SetHeight(12)
            if hasGlass() then round(s, s, 3) end
            p.segs[i] = s
        end
        p.pLegend = K.Text(bud, 10, C.dim)
        p.pWarn = K.Text(bud, 11, C.amber, "RIGHT")
        p.pReset = K.Button(bud, L["Clear plan"], 96, 22, "ghost", function()
            ns.db.settings.legacyPlan = {}
            ns.RefreshPage("legacy")
        end)
        p.pReset:SetPoint("TOPRIGHT", -12, -8)
        calmBtn(p.pReset)
        p.pReset.label:SetFont(K.FONT, 11, "")
        function p:FlashBudget()
            if not animOn() then return end
            K.Tween(bud.flash, 0.6, function(q) bud.flash:SetAlpha(math.sin(q * math.pi)) end, function() bud.flash:SetAlpha(0) end)
        end
        bud:SetScript("OnSizeChanged", function(self, w)
            w = w or self:GetWidth() or 0
            local x0, x1 = 120, w - 124
            local sw = (x1 - x0 - (MAX_SPEND - 1) * 3) / MAX_SPEND
            for i, s in ipairs(p.segs) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + (i - 1) * (sw + 3), -14)
                s:SetWidth(math.max(2, sw))
            end
            p.pLegend:ClearAllPoints()
            p.pLegend:SetPoint("BOTTOMLEFT", x0, 9)
            p.pWarn:ClearAllPoints()
            p.pWarn:SetPoint("BOTTOMRIGHT", -12, 9)
            p.pWarn:SetPoint("LEFT", self, "LEFT", x0 + 250, 0)
        end)
        p.pLegend:SetText(K.hex(C.accent) .. L["planned"] .. "|r   |cff555555·|r   " .. K.hex(C.amber) .. L["missing"] .. "|r   |cff555555·|r   |cff4c8a68" .. L["open"] .. "|r")

        local function perkClick(key, delta, tile)
            local pk = PERK[key]
            local rk = plan()[key] or 0
            if delta > 0 then
                if Legacy.PlanSpent() >= MAX_SPEND then p:FlashBudget() return end
                local ok = Legacy.PerkAvailable(key)
                if not ok or rk >= pk.max then
                    if tile and animOn() then
                        tile.flash:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.3)
                        K.Tween(tile.flash, 0.5, function(q) tile.flash:SetAlpha(math.sin(q * math.pi)) end, function() tile.flash:SetAlpha(0) end)
                    end
                    return
                end
            end
            Legacy.PerkChange(key, delta)
        end

        p.trees = {}
        for ti, t in ipairs(TREES) do
            local tc = TREE_COLOR[t.key] or C.accent
            local tp = box(perks, L[t.name], tc)
            tp.spentBar = roundBar(K.Bar(tp, 60, 3))
            tp.spentBar:SetPoint("TOPRIGHT", -12, -16)
            barColor(tp.spentBar, tc)
            tp.head.count:SetTextColor(tc[1], tc[2], tc[3])
            tp.rows = {}
            for i, pk in ipairs(t.perks) do
                local r = CreateFrame("Button", nil, tp)
                r:SetHeight(38)
                r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 42)
                r:SetPoint("RIGHT", tp, "RIGHT", -8, 0)
                r.bg = K.Fill(r, C.raised)
                r.hl = r:CreateTexture(nil, "HIGHLIGHT")
                r.hl:SetAllPoints()
                r.hl:SetColorTexture(tc[1], tc[2], tc[3], 0.10)
                if hasGlass() then
                    glass(r, nil, nil, 9)
                    r.hl:SetColorTexture(1, 1, 1, 0.035)
                    round(r.hl, r, 9)
                end
                r.stripe = r:CreateTexture(nil, "ARTWORK")
                r.stripe:SetPoint("TOPLEFT") r.stripe:SetPoint("BOTTOMLEFT")
                r.stripe:SetWidth(3)
                r.stripe:SetColorTexture(tc[1], tc[2], tc[3], 1)
                if hasGlass() then r.stripe:ClearAllPoints() r.stripe:SetPoint("LEFT", 3, 0) r.stripe:SetSize(3, 18) round(r.stripe, r.stripe, 1) end
                r.flash = r:CreateTexture(nil, "OVERLAY")
                r.flash:SetAllPoints()
                r.flash:SetAlpha(0)
                r.key = pk[1]
                -- icon on the left (edge slightly cropped)
                r.ic = r:CreateTexture(nil, "ARTWORK", nil, 1)
                r.ic:SetSize(26, 26)
                r.ic:SetPoint("LEFT", 10, 0)
                r.ic:SetTexture("Interface\\Icons\\" .. (PERK_ICON[pk[1]] or "INV_Misc_QuestionMark"))
                r.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.name = K.Text(r, 12, C.text)
                r.name:SetPoint("TOPLEFT", 44, -5)
                r.name:SetPoint("RIGHT", r, "RIGHT", -(32 + pk[3] * 9 + 20), 0)
                r.name:SetText(L[pk[2]])
                r.info = K.Text(r, 10, C.dim)
                r.info:SetPoint("BOTTOMLEFT", 44, 5)
                r.info:SetPoint("RIGHT", r, "RIGHT", -(32 + pk[3] * 9 + 20), 0)
                r.pips = {}
                for j = 1, pk[3] do
                    local pip = r:CreateTexture(nil, "OVERLAY")
                    pip:SetColorTexture(1, 1, 1, 1)
                    pip:SetSize(7, 7)
                    if hasGlass() then round(pip, pip, 3) end
                    pip:SetPoint("CENTER", r, "RIGHT", -26 - (pk[3] - j) * 9 - 4, 0)
                    r.pips[j] = pip
                end
                r.plus = K.IconButton(r, "+", 18, function() perkClick(pk[1], 1, r) end)
                r.plus:SetPoint("RIGHT", -4, 0)
                r.minus = K.IconButton(r, "-", 18, function() perkClick(pk[1], -1, r) end)
                r.minus:SetPoint("RIGHT", -(28 + pk[3] * 9), 0)
                r:SetScript("OnEnter", function(self)
                    local x = PERK[self.key]
                    local lines = { K.hex(tc) .. L[x.name] .. "|r", (L["Ranks: %d"]):format(x.max), " ", "|cffc8c8c8" .. L[x.desc] .. "|r" }
                    if x.gate > 0 then lines[#lines + 1] = " " lines[#lines + 1] = (L["needs %d points in tree"]):format(x.gate) end
                    if x.req then lines[#lines + 1] = (L["needs %s"]):format(L[PERK[x.req].name]) end
                    lines[#lines + 1] = " "
                    lines[#lines + 1] = "|cff666666" .. L["Click: +1  ·  Shift-click: -1"] .. "|r"
                    K.ShowTip(self, lines)
                end)
                r:SetScript("OnLeave", function() GameTooltip:Hide() end)
                r:SetScript("OnClick", function(self) perkClick(self.key, IsShiftKeyDown() and -1 or 1, self) end)
                tp.rows[i] = r
            end
            p.trees[ti] = tp
        end
        perks:SetScript("OnSizeChanged", function(self, w)
            w = w or self:GetWidth() or 0
            local cw = (w - 20) / 3
            for i, tp in ipairs(p.trees) do
                tp:ClearAllPoints()
                tp:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (cw + 10), -70)
                tp:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
                tp:SetWidth(math.max(10, cw))
            end
        end)

        ----------------------------------------------------------------
        -- Guild
        ----------------------------------------------------------------
        local guild = content()
        p.guild = guild
        p.gTiles = {}
        local gdefs = {
            { ICON .. "groups", "Players with Legacy", C.blue },
            { ICON .. "stats", "Guild average", C.amber },
            { ICON .. "legacy", "Your rank", C.accent },
        }
        for i, dd in ipairs(gdefs) do
            local t = hudTile(guild, dd[1], L[dd[2]], dd[3])
            t.host = guild
            dress(t, dd[3])
            p.gTiles[i] = t
        end
        local gt = box(guild, L["Who is how far"], C.blue)
        p.gTable = gt
        p.gHead = {}
        for i, c in ipairs(CATS) do
            -- header as category icon (names don't fit in narrow columns), name in the tooltip
            local h = CreateFrame("Frame", nil, gt)
            h:SetSize(20, 20)
            h.icon = K.Icon(h, 18, c.icon)
            h.icon:SetPoint("CENTER")
            h.line = h:CreateTexture(nil, "ARTWORK")
            h.line:SetHeight(2)
            h.line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 1, -1)
            h.line:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", -1, -1)
            local hc = catColor(c.key)
            h.line:SetColorTexture(hc[1], hc[2], hc[3], 0.9)
            h:EnableMouse(true)
            h:SetScript("OnEnter", function(self) K.ShowTip(self, L[c.name]) end)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.gHead[i] = h
        end
        p.gl = K.List(gt, 32, function(l)
            local r = K.Row(l)
            medal(r, 8)
            portCell(r, 20, 36)
            r.cols.who = K.Text(r, 12, C.text)
            r.cols.who:SetPoint("LEFT", 62, 0)
            r.cols.who:SetWidth(108)
            r.cells, r.cbars = {}, {}
            for i = 1, #CATS do
                r.cells[i] = K.Text(r, 11, C.muted, "CENTER")
                r.cells[i]:SetWidth(52)
                r.cbars[i] = roundBar(K.Bar(r, 40, 3))
                barColor(r.cbars[i], catColor(CATS[i].key))
            end
            r.cols.n = K.Title(r, 14, C.text, "RIGHT")
            r.cols.n:SetPoint("RIGHT", -10, 0)
            r.cols.n:SetWidth(36)
            r:SetScript("OnEnter", function(self)
                local x = self.item
                if not x then return end
                local t = {}
                for _, c in ipairs(x.chars) do
                    local lvl = charInfo(c)
                    t[#t + 1] = ns.Radar.Colored(c) .. (lvl > 0 and ("  |cff888888" .. lvl .. "|r") or "")
                end
                local lines = { ns.displayName(x.main) .. " - " .. (L["%d Legacy points"]):format(x.n) }
                if not x.me then
                    local mine = Legacy.Mine()
                    local give, take = {}, 0
                    for id in pairs(x.done) do if Legacy.byId[id] and not mine[id] then give[#give + 1] = Legacy.Name(Legacy.byId[id]) end end
                    for id in pairs(mine) do if Legacy.byId[id] and not x.done[id] then take = take + 1 end end
                    table.sort(give)
                    lines[#lines + 1] = " "
                    if #give > 0 then
                        lines[#lines + 1] = K.hex(C.mint) .. L["Has what you are missing:"] .. "|r"
                        for j = 1, math.min(5, #give) do lines[#lines + 1] = "· " .. give[j] end
                        if #give > 5 then lines[#lines + 1] = "|cff888888+" .. (#give - 5) .. "|r" end
                    end
                    if take > 0 then lines[#lines + 1] = K.hex(C.amber) .. (L["You have %d they are missing"]):format(take) .. "|r" end
                end
                lines[#lines + 1] = " "
                lines[#lines + 1] = L["Characters:"]
                lines[#lines + 1] = table.concat(t, "\n")
                lines[#lines + 1] = "|cff666666" .. L["Click: profile"] .. "|r"
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.item then openProfile(self.item.main) end end)
            return r
        end, function(r, x, idx)
            r:SetMedal(x.rank)
            setPort(r, x.main)
            r.cols.who:SetText(ns.Radar.Colored(x.main) .. (#x.chars > 1 and (" |cff777777+" .. (#x.chars - 1) .. "|r") or ""))
            local _, total = catCounts({})
            local step, x0 = p.gStep or 50, p.gX0 or 176
            for i, c in ipairs(CATS) do
                local h, tt = x.have[c.key] or 0, total[c.key] or 0
                local cell, bar = r.cells[i], r.cbars[i]
                cell:ClearAllPoints()
                cell:SetPoint("CENTER", r, "LEFT", x0 + (i - 0.5) * step, 5)
                bar:ClearAllPoints()
                bar:SetPoint("CENTER", r, "LEFT", x0 + (i - 0.5) * step, -8)
                bar:SetWidth(math.max(10, math.min(46, step - 10)))
                cell:SetText((h == tt and "|cff66db9e" or (h > 0 and "|cffe8e8e8" or "|cff555555")) .. h .. "|r|cff666666/" .. tt .. "|r")
                fillBar(bar, tt > 0 and h / tt or 0, p.animRows, 0.1 + idx * 0.04 + i * 0.02)
            end
            r.cols.n:SetText(x.n)
            r.sel:SetShown(x.me)
        end)
        p.gl:SetPoint("TOPLEFT", 4, -50)
        p.gl:SetPoint("BOTTOMRIGHT", -4, 6)
        p.gl.empty:SetText(L["No guild data yet."])

        local gs = box(guild, L["Tackle together"], C.mint)
        p.gSug = gs
        p.sugList = K.List(gs, 48, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 28, nil)
            r.icon:SetPoint("TOPLEFT", 8, -9)
            if hasGlass() then round(r.icon, r.icon, 6) end
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 44, -7)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.cols.meta = K.Text(r, 11, C.muted)
            r.cols.meta:SetPoint("BOTTOMLEFT", 44, 8)
            r.cols.meta:SetPoint("RIGHT", r, "RIGHT", -82, 0)
            r.btn = calmBtn(K.Button(r, "", 70, 20, "ghost"))
            r.btn:SetPoint("BOTTOMRIGHT", -8, 5)
            r.btn.label:SetFont(K.FONT, 11, "")
            r:SetScript("OnClick", function(self) if self.item then openChallenge(p, self.item.e.id) end end)
            return r
        end, function(r, x)
            local e = x.e
            setIcon(r.icon, e)
            r.cols.name:SetText(Legacy.Name(e))
            r.cols.meta:SetText(K.hex(C.amber) .. (L["%d need it"]):format(x.need) .. "|r  |cff777777·|r  " .. K.hex(C.mint) .. (L["%d have it"]):format(x.have) .. "|r")
            if x.mine then
                r.btn:SetLabel(L["Help"])
                r.btn:SetScript("OnClick", function() Legacy.Search(e, L["I'll help – who still needs it?"]) end)
            else
                r.btn:SetLabel(L["Search"])
                r.btn:SetScript("OnClick", function() Legacy.Search(e) end)
            end
        end)
        p.sugList:SetPoint("TOPLEFT", 4, -34)
        p.sugList:SetPoint("BOTTOMRIGHT", -4, 6)
        p.sugList.empty:SetText(L["Nothing to tackle together right now."])

        function guild:Layout()
            local w, h = self:GetWidth() or 0, self:GetHeight() or 0
            if w < 100 then return end
            local tw = math.floor((w - 20) / 3)
            for i, t in ipairs(p.gTiles) do
                t.x, t.y, t.w, t.h = (i - 1) * (tw + 10), 0, tw, 70
                t:Place()
            end
            local sw = math.max(220, math.floor(w * 0.35))
            gt:ClearAllPoints()
            gt:SetPoint("TOPLEFT", 0, -80)
            gt:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -(sw + 10), 0)
            gs:ClearAllPoints()
            gs:SetPoint("TOPLEFT", self, "TOPRIGHT", -sw, -80)
            gs:SetPoint("BOTTOMRIGHT")
            local tableW = w - sw - 10 - 8 - 8
            local x0 = 176
            local step = math.max(30, (tableW - x0 - 46) / #CATS)
            p.gX0, p.gStep = x0, step
            for i, hh in ipairs(p.gHead) do
                hh:ClearAllPoints()
                hh:SetPoint("CENTER", gt, "TOPLEFT", 4 + x0 + (i - 0.5) * step, -40)
            end
        end
        guild:SetScript("OnSizeChanged", function(self) self:Layout() ns.RefreshPage("legacy") end)
    end,

    refresh = function(p)
        if p.tabs.value ~= view then p.tabs:Select(view) end
        -- only the content changes (smoothly), tabs and header stay put
        local frames = { home = p.home, list = p.list, perks = p.perks, guild = p.guild }
        if p.shownView ~= view then
            for k, f in pairs(frames) do f:SetShown(k == view) end
            local f = frames[view]
            if f.Layout then f:Layout() end
            if p.shownView and animOn() then
                f:SetAlpha(0)
                K.Tween(f, 0.28, function(q)
                    f:SetAlpha(q)
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", 0, TOP - 10 * (1 - q))
                    f:SetPoint("BOTTOMRIGHT", 0, -10 * (1 - q))
                end, function()
                    f:SetAlpha(1)
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", 0, TOP)
                    f:SetPoint("BOTTOMRIGHT")
                end)
                ns.After(1, function() if (f:GetAlpha() or 1) < 1 then f:SetAlpha(1) end end)
            end
            p.shownView = view
        end
        local fresh = p.fresh and true or false
        p.fresh = false
        p.animRows = fresh and animOn()
        local done, prog = Legacy.Mine()
        local mine = count(done)
        local nl = #Legacy.list

        if view == "home" then
            local nr = nextReward(mine)
            local pr = prevReward(mine)
            local rank = guildRanking()
            local sum, myRank = 0, nil
            for _, x in ipairs(rank) do sum = sum + x.n if x.me then myRank = x.rank end end
            local anim = fresh and animOn()
            local t = p.tiles
            t[1]:Set(mine, "/ " .. nl, mine / nl, anim)
            t[1].ring:SetProgress(mine / nl, anim, 0.1)
            t[1].tip = { L["Your Legacy points"], (L["%d of %d challenges done (whole account)"]):format(mine, nl), "|cff666666" .. L["Click: all challenges"] .. "|r" }
            local have0 = math.max(mine, ns.LegacyGrant())
            t[2]:Set(math.min(have0, MAX_SPEND), "/ " .. MAX_SPEND, math.min(have0, MAX_SPEND) / MAX_SPEND, anim)
            t[2].tip = { L["Spendable per character"], (L["Each character can spend up to %d points on perks."]):format(MAX_SPEND), "|cff666666" .. L["Click: perk planner"] .. "|r" }
            if nr then
                t[3]:Set(nr - mine, (L["left until %d"]):format(nr), (mine - pr) / math.max(1, nr - pr), anim)
                t[3].ring:SetProgress((mine - pr) / math.max(1, nr - pr), anim, 0.2)
                t[3].tip = { L["Next collection reward"], (L["The next reward comes at %d points – you need %d more."]):format(nr, nr - mine) }
            else
                t[3]:Set(L["everyone"], L["earned"], 1, anim)
                t[3].ring:SetProgress(1, anim, 0.2)
                t[3].tip = { L["Next collection reward"], L["All collection rewards earned."] }
            end
            t[4]:Set(sum, (L["%d players"]):format(#rank), nil, anim)
            t[4].tip = { L["Guild total"], (L["%d Legacy points across %d players"]):format(sum, #rank) }
            if myRank then t[4].tip[#t[4].tip + 1] = (L["You are rank %d"]):format(myRank) end
            t[4].tip[#t[4].tip + 1] = "|cff666666" .. L["Click: guild"] .. "|r"
            if fresh then
                for i, tile in ipairs(t) do rise(tile, (i - 1) * 0.06) sweep(tile, 0.5 + i * 0.12) end
            end
            -- Categories
            local have, total = catCounts(done)
            for i, c in ipairs(CATS) do
                local b = p.catCards[i]
                local h, tt = have[c.key] or 0, total[c.key] or 0
                b.nHave, b.nTot, b.complete = h, tt, h == tt
                b.cnt:SetText((h == tt and "|cff66db9e" or "|cffe8e8e8") .. h .. "|r |cff777777/ " .. tt .. "|r  |cff888888" .. math.floor(tt > 0 and h / tt * 100 or 0) .. "%|r")
                b.ring:SetProgress(tt > 0 and h / tt or 0, anim, 0.15 + i * 0.07)
                b.icon:SetDesaturated(h == 0)
                local open = {}
                for _, e in ipairs(Legacy.list) do if e.cat == c.key and not done[e.id] then open[#open + 1] = Legacy.Name(e) end end
                b.open = open
                if fresh then rise(b, 0.15 + i * 0.05) end
            end
            -- Next steps
            p.rewardNext = nr and (nr - mine == 1) or false
            local steps = nextSteps(done, prog)
            p.nextBox.head:SetCount(#steps > 0 and #steps or nil)
            p.nextList:SetData(steps)
            p.nextEmpty:SetShown(#steps == 0)
            -- Ranking
            p.rankTop = rank[1] and rank[1].n or 1
            p.rankBox.head:SetCount(#rank)
            p.rankList:SetData(rank)
            -- Searches
            local ss = Legacy.ActiveSearches()
            p.searchBox.head:SetCount(#ss > 0 and #ss or nil)
            p.searchBox.head:Live(#ss > 0)
            p.searchList:SetData(ss)
            p.searchEmpty:SetShown(#ss == 0)
            if fresh then
                rise(p.nextBox, 0.25) rise(p.rankBox, 0.32) rise(p.searchBox, 0.39)
            end
            return
        end

        if view == "perks" then
            local spent = Legacy.PlanSpent()
            local granted = ns.LegacyGrant()
            local have = math.max(mine, granted)
            local avail = math.min(have, MAX_SPEND)
            p.pVal:SetText(spent .. " |cff888888/ " .. MAX_SPEND .. "|r")
            for i, s in ipairs(p.segs) do
                local c, a
                if i <= spent then
                    if i <= avail then c, a = C.accent, 1 else c, a = C.amber, 1 end
                elseif i <= avail then c, a = C.mint, 0.3
                else c, a = { 1, 1, 1 }, 0.07 end
                s:SetColorTexture(c[1], c[2], c[3], a)
                if p.lastSpent and i > p.lastSpent and i <= spent and animOn() then
                    s:SetAlpha(0)
                    K.Tween(s, 0.3, function(q) s:SetAlpha(q) end, function() s:SetAlpha(1) end, (i - p.lastSpent - 1) * 0.04)
                else
                    s:SetAlpha(1)
                end
            end
            p.lastSpent = spent
            if spent > have then
                p.pWarn:SetText(K.hex(C.amber) .. (L["Plan over budget: collect %d more points"]):format(spent - have) .. "|r")
            elseif spent >= MAX_SPEND then
                p.pWarn:SetText(K.hex(C.mint) .. L["All 16 points planned"] .. "|r")
            else
                p.pWarn:SetText("|cff888888" .. (L["You have %d Legacy points"]):format(have) .. (granted > mine and (" (" .. L["beta gift"] .. ")") or "")
                    .. "  ·  " .. (L["%d still free"]):format(MAX_SPEND - spent) .. "  ·  " .. L["respec from 1 point, 1 cheaper every hour"] .. "|r")
            end
            local pl = plan()
            for ti, t in ipairs(TREES) do
                local tp = p.trees[ti]
                local ts = Legacy.PlanSpent(t.key)
                local tmax = 0
                for _, pk in ipairs(t.perks) do tmax = tmax + pk[3] end
                tp.head:SetCount((L["%d points"]):format(ts))
                tp.spentBar:Set(ts / math.max(1, MAX_SPEND))
                local tc = TREE_COLOR[t.key] or C.accent
                for ri, r in ipairs(tp.rows) do
                    local pk = PERK[r.key]
                    local rk = pl[r.key] or 0
                    local ok, why = Legacy.PerkAvailable(r.key)
                    for j, pip in ipairs(r.pips) do
                        if j <= rk then pip:SetColorTexture(tc[1], tc[2], tc[3], 1) else pip:SetColorTexture(1, 1, 1, 0.12) end
                    end
                    r.name:SetTextColor(unpack((ok or rk > 0) and C.text or C.dim))
                    if r.ic then r.ic:SetDesaturated(not (ok or rk > 0)) end
                    r.info:SetText(ok and (pk.gate > 0 and ("|cff666666" .. (L["from %d points"]):format(pk.gate) .. "|r") or ("|cff666666" .. (L["Ranks: %d"]):format(pk.max) .. "|r")) or ("|cffa05050" .. why .. "|r"))
                    if hasGlass() then
                        glass(r, rk > 0 and { tc[1], tc[2], tc[3], 0.10 } or { 1, 1, 1, 0.03 }, rk > 0 and { tc[1], tc[2], tc[3], 0.35 } or { 1, 1, 1, 0.07 })
                    else
                        r.bg:SetColorTexture(rk > 0 and tc[1] * 0.16 + 0.06 or C.raised[1], rk > 0 and tc[2] * 0.16 + 0.06 or C.raised[2], rk > 0 and tc[3] * 0.16 + 0.06 or C.raised[3], 1)
                    end
                    r.stripe:SetShown(rk > 0)
                    r:SetAlpha((ok or rk > 0) and 1 or 0.55)
                    r.plus:SetShown(ok and rk < pk.max and spent < MAX_SPEND)
                    r.minus:SetShown(rk > 0)
                    if r.lastRk and r.lastRk ~= rk and animOn() then
                        r.flash:SetColorTexture(tc[1], tc[2], tc[3], 0.35)
                        K.Tween(r.flash, 0.45, function(q) r.flash:SetAlpha(1 - q) end, function() r.flash:SetAlpha(0) end)
                        local pip = r.pips[math.max(1, rk)]
                        if pip and rk > r.lastRk then
                            K.Tween(pip, 0.35, function(q) pip:SetSize(7 + 5 * (1 - q), 7 + 5 * (1 - q)) end, function() pip:SetSize(7, 7) end)
                        end
                    end
                    r.lastRk = rk
                end
                if fresh then rise(tp, 0.05 + ti * 0.07) end
            end
            if fresh then rise(p.budget, 0) end
            return
        end

        if view == "guild" then
            local rank = guildRanking()
            local sum, myRank = 0, nil
            local active = 0
            for _, x in ipairs(rank) do sum = sum + x.n if x.me then myRank = x.rank end if x.n > 0 then active = active + 1 end end
            local anim = fresh and animOn()
            local g = p.gTiles
            g[1]:Set(active, (L["of %d"]):format(#rank), #rank > 0 and active / #rank or 0, anim)
            local avg = #rank > 0 and math.floor(sum / #rank * 10 + 0.5) / 10 or 0
            g[2]:Set(avg, L["points per player"], avg / nl, false)
            g[3]:Set(myRank or "–", myRank and (L["of %d"]):format(#rank) or "", myRank and (#rank - myRank + 1) / math.max(1, #rank) or nil, anim and myRank ~= nil)
            if fresh then for i, tile in ipairs(g) do rise(tile, (i - 1) * 0.06) sweep(tile, 0.4 + i * 0.12) end end
            p.gTable.head:SetCount(#rank)
            p.gl:SetData(rank)
            local sug = together(done)
            p.gSug.head:SetCount(#sug > 0 and #sug or nil)
            p.sugList:SetData(sug)
            if fresh then rise(p.gTable, 0.15) rise(p.gSug, 0.22) end
            return
        end

        -- Challenges
        local cls, prof = relevantSets(done, prog)
        local searching = {}
        for _, s in ipairs(Legacy.ActiveSearches()) do if not searching[s.id] then searching[s.id] = s end end
        local rows = {}
        for _, e in ipairs(Legacy.list) do
            local ok = (catFilter == "all" or e.cat == catFilter)
                and (stateFilter == "all" or e.id == selected or (stateFilter == "open" and not done[e.id]) or (stateFilter == "done" and done[e.id]))
            if ok and forMe then ok = isRelevant(e, done, cls, prof) or e.id == selected end
            if ok and search ~= "" then
                ok = Legacy.Name(e):lower():find(search, 1, true) or Legacy.Req(e):lower():find(search, 1, true)
            end
            if ok then
                local h, n = Legacy.WhoDone(e.id)
                rows[#rows + 1] = { e = e, done = done[e.id], prog = prog[e.id], have = #h, total = #h + #n, lfg = searching[e.id] }
            end
        end
        p.cl:SetData(rows)
        p.hits:SetText((L["%d matches"]):format(#rows))
        if fresh then rise(p.cl, 0.05) rise(p.detail, 0.12) end
        local e
        for _, x in ipairs(rows) do if x.e.id == selected then e = x.e end end
        if not e and rows[1] then e = rows[1].e selected = e.id p.cl:Refresh() end
        local show = e ~= nil
        p.detail.dc:SetShown(show)
        p.dEmpty:SetShown(not show)
        p.detail.band:SetShown(show)
        if not e then return end
        if p.lastSel ~= e.id then
            p.lastSel = e.id
            if not fresh then rise(p.detail.dc, 0) end
        end
        local cc = catColor(e.cat)
        if hasGlass() then
            p.detail.band:SetColorTexture(0, 0, 0, 0)
            glass(p.detail, nil, { cc[1], cc[2], cc[3], 0.25 })
        else
            grad(p.detail.band, "VERTICAL", cc, 0, 0.16)
        end
        p.dGlow:SetVertexColor(cc[1], cc[2], cc[3])
        setIcon(p.dIcon, e)
        p.dName:SetText(Legacy.Name(e))
        p.dCat:SetText(K.hex(cc) .. L[CAT_BY[e.cat].name] .. "|r  ·  " .. L["1 Legacy point"] .. "  ·  " .. (e.auto and L["detected automatically"] or L["check off yourself"]))
        p.dReq:SetText(Legacy.Req(e))
        local who = done[e.id]
        local x = prog[e.id]
        if who then
            local manual = Legacy.IsManual(e.id)
            p.dStatus:SetText(K.hex(C.mint) .. L["Done"] .. "|r" .. (type(who) == "string" and ("  |cff888888" .. (L["with %s"]):format(ns.displayName(who)) .. "|r") or "")
                .. (manual and ("  |cff888888(" .. L["checked off"] .. ")|r") or ""))
            barColor(p.dBar, C.mint)
            p.dBar:Set(1)
            p.dMark:SetShown(manual)
            p.dMark:SetLabel(L["Remove check"])
        else
            p.dStatus:SetText(x and (K.hex(C.amber) .. stepText(e, x) .. "|r") or ("|cff888888" .. L["Still open"] .. "|r"))
            barColor(p.dBar, C.amber)
            fillBar(p.dBar, x and x.f or 0, p.lastBarSel ~= e.id, 0.05)
            p.dMark:SetShown(not e.auto)
            p.dMark:SetLabel(L["Mark as done"])
        end
        p.lastBarSel = e.id
        local go = GOTO[e.cat]
        if e.id == "a:valthalak" then go = nil end
        if go and pageOk(go[1]) then
            p.dGo:SetLabel(L[go[2]])
            p.dGo:SetScript("OnClick", function() ns.ShowPage(go[1]) end)
            p.dGo:ClearAllPoints()
            if p.dMark:IsShown() then p.dGo:SetPoint("LEFT", p.dMark, "RIGHT", 8, 0) else p.dGo:SetPoint("TOPLEFT", p.dBar, "BOTTOMLEFT", 0, -10) end
            p.dGo:Show()
        else
            p.dGo:Hide()
        end
        local lines = {}
        local dl = dungeonList(e)
        if #dl > 0 then
            lines[#lines + 1] = "|cff888888" .. L["Dungeons in this level range:"] .. "|r"
            lines[#lines + 1] = table.concat(dl, ", ")
            lines[#lines + 1] = " "
        end
        local h, n = Legacy.WhoDone(e.id)
        lines[#lines + 1] = K.hex(C.mint) .. L["Done ("] .. #h .. ")|r"
        lines[#lines + 1] = names(h)
        lines[#lines + 1] = " "
        lines[#lines + 1] = K.hex(C.amber) .. L["Still needs ("] .. #n .. ")|r"
        lines[#lines + 1] = names(n)
        local s = searching[e.id]
        if s then
            lines[#lines + 1] = " "
            lines[#lines + 1] = K.hex(C.violet) .. (L["%s is looking for companions"]):format(ns.displayName(s.name)) .. "|r" .. ((s.note or "") ~= "" and ("  |cff999999" .. s.note .. "|r") or "")
        end
        p.dBody:SetText(table.concat(lines, "\n"))
        p.dBtn:SetEnabledState(not who)
        p.dBtn:SetLabel(who and L["Already done"] or L["Find partners"])
    end,
})

ns.Listen("LOGIN", function()
    ns.After(8, Legacy.Scan)
    ns.Every(120, function() if not ns.inCombat() then Legacy.Scan() end end)
    local D = ns.Demo
    if D and not D.legacyHooked then
        D.legacyHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) Legacy.SeedDemo() end
        D.Remove = function(...) remove(...) Legacy.RemoveDemo() end
        if D.IsActive() then ns.After(3, Legacy.SeedDemo) end
    end
end)
end)

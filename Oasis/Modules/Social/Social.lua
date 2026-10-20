-- Oasis: companions (quest partners in the guild, recent players from outside, newcomer tag)
local ADDON, ns = ...
ns.ModuleFile("Oasis_Social", function()   -- Companions module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
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
local refreshSocial   -- assigned further below

local Social = {}
ns.Social = Social

------------------------------------------------------------------------
-- own quests (ID, title, zone) -> shared via profile
------------------------------------------------------------------------
-- open quest in the quest log (or map & quest log)
function Social.OpenQuest(id, q)
    id = tonumber(id)
    if not id then return end
    local Q = C_QuestLog
    local idx = Q and Q.GetLogIndexForQuestID and select(2, pcall(Q.GetLogIndexForQuestID, id))
    if type(idx) ~= "number" then idx = nil end
    -- fallback: search by title in your own quest log (IDs may differ in Forever)
    if not idx and q and q.title and Q and Q.GetNumQuestLogEntries and Q.GetInfo then
        for i = 1, (Q.GetNumQuestLogEntries() or 0) do
            local ok, info = pcall(Q.GetInfo, i)
            if ok and type(info) == "table" and not info.isHeader and ns.safe(info.title) == q.title then
                idx = i
                id = ns.safe(info.questID) or id
                break
            end
        end
    end
    if not idx then
        -- not mine: demo quest or a fellow player's quest -> say who has it and show the location
        if q and q.demo then ns.print(L["This is a demo quest - it is not in your quest log."]) return end
        local who = q and q.owners and q.owners[1]
        ns.print(who and (L["%s has this quest, not you."]):format(ns.displayName(who)) or L["This quest is not in your quest log."])
        if q and ns.QuestLocations and ns.QuestLocations.Show then pcall(ns.QuestLocations.Show, id, q) end
        return
    end
    if QuestMapFrame_OpenToQuestDetails then
        pcall(QuestMapFrame_OpenToQuestDetails, id)
    elseif QuestLogFrame then
        if not QuestLogFrame:IsShown() and ToggleQuestLog then ToggleQuestLog() end
        if QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx) end
        if QuestLog_Update then pcall(QuestLog_Update) end
    elseif ToggleQuestLog then
        ToggleQuestLog()
    end
end
function Social.MyQuests()
    local out = {}
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then return out end
    local header = ""
    for i = 1, (Q.GetNumQuestLogEntries() or 0) do
        local ok, info = pcall(Q.GetInfo, i)
        if ok and type(info) == "table" then
            if info.isHeader then
                header = ns.safe(info.title) or ""
            elseif not info.isHidden and info.questID then
                local done = Q.IsComplete and Q.IsComplete(info.questID) or false
                out[#out + 1] = { id = info.questID, title = ns.safe(info.title) or ("#" .. info.questID), zone = header, done = done,
                    lvl = tonumber(info.level) or nil, group = (tonumber(info.suggestedGroup) or 0) > 1, new = ns.IsForeverQuest and ns.IsForeverQuest(info.questID) or false }
                out[#out].dungeon = Social.DungeonOf(out[#out])
            end
        end
    end
    if ns.Demo and ns.Demo.IsActive() and ns.Demo.Quests then
        for _, q in ipairs(ns.Demo.Quests()) do q.dungeon = Social.DungeonOf(q) out[#out + 1] = q end
    end
    return out
end
-- dungeon quest? quest log header = dungeon name or Blizzard tag (Dungeon/Raid)
function Social.DungeonOf(q)
    if not q then return nil end
    local key = ns.Dungeons and ns.Dungeons.KeyByZone and ns.Dungeons.KeyByZone(q.zone)
    if key then return key end
    local Q = C_QuestLog
    if Q and Q.GetQuestTagInfo and q.id then
        local ok, tag = pcall(Q.GetQuestTagInfo, q.id)
        if ok and type(tag) == "table" and (tag.tagID == 81 or tag.tagID == 62) then return true end
    end
    return nil
end
local DUNGEON_C = { 0.64, 0.42, 1 }   -- purple like epic items
function Social.EncodeQuests()
    local t = {}
    for _, q in ipairs(Social.MyQuests()) do
        if #t >= 30 then break end
        if not q.demo then t[#t + 1] = tostring(q.id) end
    end
    return table.concat(t, ",")
end
local function questSet(s)
    local set = {}
    for id in (s or ""):gmatch("%d+") do set[tonumber(id)] = true end
    return set
end
-- quest color as in the quest log (red/orange/yellow/green/gray depending on distance to your level)
function Social.QuestColor(q)
    local lvl = q and q.lvl
    if not lvl or lvl <= 0 then return "|cffe8b44a" end
    local c
    if GetQuestDifficultyColor then
        local ok, res = pcall(GetQuestDifficultyColor, lvl)
        if ok and type(res) == "table" and res.r then c = res end
    end
    if not c then
        local me = ns.safe(UnitLevel("player")) or 1
        local d = lvl - me
        local green = (GetQuestGreenRange and GetQuestGreenRange()) or 8
        if d >= 5 then c = { r = 1, g = 0.1, b = 0.1 }
        elseif d >= 3 then c = { r = 1, g = 0.5, b = 0.25 }
        elseif d >= -2 then c = { r = 1, g = 0.82, b = 0 }
        elseif -d <= green then c = { r = 0.25, g = 0.75, b = 0.25 }
        else c = { r = 0.5, g = 0.5, b = 0.5 } end
    end
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end
function Social.InMyGroup(name)
    if ns.isMe(name) then return true end
    local s = ns.ChatName and ns.ChatName(name) or ns.short(name)
    return (UnitInParty and UnitInParty(s)) or (UnitInRaid and UnitInRaid(s)) or false
end

-- quest partners: for each of your quests the members who have it too
function Social.Partners()
    local out = {}
    local others = {}
    for name, p in pairs(ns.db.members) do
        if not ns.isMe(name) and p.qs and p.qs ~= "" then others[name] = questSet(p.qs) end
    end
    -- Oasis contacts (also without guild): quests come via the group channel, only while in the group
    for name, c in pairs((ns.db and ns.db.oasisContacts) or {}) do
        if not others[name] and not ns.isMe(name) and c.qs and c.qs ~= "" and Social.InMyGroup(name) then others[name] = questSet(c.qs) end
    end
    local showDone = ns.db and ns.db.settings.socialShowDone
    local groupOnly = ns.db and ns.db.settings.socialGroupOnly
    for _, q in ipairs(Social.MyQuests()) do
      if (showDone or not q.done) and (not groupOnly or q.group) then
        local on, off = {}, {}
        for name, set in pairs(others) do
            if set[q.id] then
                if ns.Radar.IsOnline(name) or Social.InMyGroup(name) then on[#on + 1] = name else off[#off + 1] = name end
            end
        end
        if #on + #off > 0 then
            table.sort(on) table.sort(off)
            out[#out + 1] = { q = q, online = on, offline = off }
        end
      end
    end
    table.sort(out, function(a, b)
        if #a.online ~= #b.online then return #a.online > #b.online end
        if (a.q.group or false) ~= (b.q.group or false) then return a.q.group end
        return a.q.title < b.q.title
    end)
    return out
end

-- per person: which of my quests do they have too? (one row per player, name forms merged)
function Social.PartnersByName(partners)
    local by, order = {}, {}
    local function add(n, q, online)
        local key = (ns.Alts and ns.Alts.Canon) and ns.Alts.Canon(n) or n
        local e = by[key]
        if not e then e = { name = key, online = false, quests = {} } by[key] = e order[#order + 1] = e end
        e.online = e.online or online
        e.quests[#e.quests + 1] = q
    end
    for _, x in ipairs(partners or Social.Partners()) do
        for _, n in ipairs(x.online) do add(n, x.q, true) end
        for _, n in ipairs(x.offline) do add(n, x.q, false) end
    end
    for _, e in ipairs(order) do table.sort(e.quests, function(a, b) return (a.title or "") < (b.title or "") end) end
    table.sort(order, function(a, b)
        if a.online ~= b.online then return a.online end
        if #a.quests ~= #b.quests then return #a.quests > #b.quests end
        return a.name < b.name
    end)
    return order
end

-- notice when a member just accepted the same quest
local lastQS = {}
local told = {}
ns.Listen("PROFILE", function(name, p)
    if ns.isMe(name) or not p.qs then return end
    local before = lastQS[name]
    lastQS[name] = questSet(p.qs)
    if not before or not ns.Radar.IsOnline(name) then return end
    if ns.db.settings.socialQuestHint == false then return end
    for _, q in ipairs(Social.MyQuests()) do
        if lastQS[name][q.id] and not before[q.id] and not q.done and (not ns.db.settings.socialGroupOnly or q.group) then
            local key = name .. q.id
            if not told[key] then
                told[key] = true
                ns.Sound.Next("group")
                K.Toast((L["%s also has: %s"]):format(ns.displayName(name), q.title), L["Click: quest together (invite)"], C.mint, function()
                    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName(name)) end
                end)
            end
        end
    end
end)

-- resend profile on quest changes (batched)
local pending
local function questsChanged()
    if pending then return end
    pending = true
    ns.After(6, function()
        pending = nil
        if ns.Radar then ns.Radar.SendHello() end
        refreshSocial()
    end)
end
ns.On("QUEST_ACCEPTED", questsChanged)
ns.On("QUEST_REMOVED", questsChanged)
ns.On("QUEST_TURNED_IN", questsChanged)

------------------------------------------------------------------------
-- recent companions (not in the guild): own tracking + Blizzard's list
------------------------------------------------------------------------
-- own entry (creates it if I only know the person from guild experiences)
function Social.Entry(name)
    local e = ns.db.allies[name]
    if not e then
        e = { count = 0, note = "", last = 0 }
        -- 0.6.302: take time, class and level from guild experiences - with last = 0 the row slid
        -- to the end of the list when rating (newest on top) and it looked as if the rating was gone
        for _, r in ipairs(ns.Store.List("rep")) do
            if r.target == name then
                if r.class then e.class = r.class end
                if r.lvl then e.lvl = r.lvl end
                e.last = math.max(e.last, tonumber(r.u) or 0)
            end
        end
        if e.last == 0 then e.last = ns.now() end
        e.via = e.via or "guild"
        ns.db.allies[name] = e
    end
    return e
end
local function remember(unit)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    local n, realm = ns.UnitFullName(unit)
    n, realm = ns.safe(n), ns.safe(realm)
    if not n or not ns.validName(n) then return end
    local full = ns.fullName(realm and realm ~= "" and (n .. "-" .. realm) or n)
    if ns.Radar.byName[full] then return end
    local _, classFile = UnitClass(unit)
    local a = ns.db.allies[full] or { count = 0, note = "" }
    if (ns.now() - (a.last or 0)) > 1800 then a.count = (a.count or 0) + 1 end
    a.class = ns.safe(classFile) or a.class
    a.lvl = ns.safe(UnitLevel(unit)) or a.lvl
    a.last = ns.now()
    a.zone = ns.safe(GetRealZoneText()) or a.zone
    -- guild (for "Recruiting"): "" = visible without guild
    local g = ns.safe(GetGuildInfo(unit))
    if g ~= nil then a.guild = g elseif ns.safe(UnitIsVisible(unit)) then a.guild = a.guild or "" end
    -- remember role in this group: Blizzard role (group finder) or spot in the Oasis group
    local seen
    local r = UnitGroupRolesAssigned and ns.safe(UnitGroupRolesAssigned(unit))
    if r == "TANK" then seen = "t" elseif r == "HEALER" then seen = "h" elseif r == "DAMAGER" then seen = "d" end
    if not seen and ns.Groups and ns.Groups.Active and ns.Groups.Slots then
        pcall(function()
            local sh = ns.short(full)
            for _, g in ipairs(ns.Groups.Active()) do
                for _, s in ipairs(ns.Groups.Slots(g)) do
                    if s.who and ns.short(s.who) == sh then
                        seen = (s.role == "tank" and "t") or (s.role == "heal" and "h") or "d"
                    end
                end
            end
        end)
    end
    if seen then a.seen = seen end
    a.via = a.via or "group"
    if unit:find("^party") or unit:find("^raid") then a.via = "group" end
    ns.db.allies[full] = a
end
-- 0.6.301: into the player book even without a group - whispered (both directions), traded, duel, added by hand.
-- Not guild members and Battle.net contacts (|K). via = where the last contact came from (second line in the list).
function Social.Touch(name, via)
    if not ns.db then return end
    name = ns.safe(name)
    if type(name) ~= "string" or name == "" or name:find("|K", 1, true) then return end
    local full = ns.fullName(name)
    if not full or ns.isMe(full) or (ns.Radar and ns.Radar.byName and ns.Radar.byName[full]) then return end
    if via ~= "manual" and ns.db.settings.allyRemember == false then return end
    if via ~= "manual" and not ns.validName(ns.short(full)) then return end
    local a = ns.db.allies[full] or { count = 0, note = "" }
    if (ns.now() - (a.last or 0)) > 1800 then a.count = (a.count or 0) + 1 end
    a.last, a.via = ns.now(), via
    a.zone = ns.safe(GetRealZoneText()) or a.zone
    ns.db.allies[full] = a
    refreshSocial()
    return full
end
ns.On("CHAT_MSG_WHISPER", function(_, sender) Social.Touch(sender, "whisper") end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(_, target) Social.Touch(target, "whisper") end)
ns.On("DUEL_REQUESTED", function(name) Social.Touch(name, "duel") end)
ns.On("TRADE_SHOW", function()
    -- trade partner is the unit "NPC": remember() picks up class and level right away
    if UnitExists and UnitExists("NPC") and UnitIsPlayer and UnitIsPlayer("NPC") then
        remember("NPC")
        local n = ns.UnitFullName and ns.safe((ns.UnitFullName("NPC")))
        local full = n and ns.fullName(n)
        if full and ns.db.allies[full] then ns.db.allies[full].via = "trade" end
        refreshSocial()
    end
end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if not ns.db then return end
    if ns.db.settings.allyRemember == false then refreshSocial() return end
    local n = GetNumGroupMembers() or 0
    if IsInRaid() then
        for i = 1, n do remember("raid" .. i) end
    else
        for i = 1, math.max(0, n - 1) do remember("party" .. i) end
    end
    refreshSocial()
end)

-- add Blizzard's "recent allies" if that system is active
local function importBlizzard()
    local R = C_RecentAllies
    if not (R and R.IsSystemEnabled and R.GetRecentAllies) then return end
    local ok, on = pcall(R.IsSystemEnabled)
    if not ok or not on then return end
    local ok2, list = pcall(R.GetRecentAllies)
    if not ok2 or type(list) ~= "table" then return end
    for _, ally in ipairs(list) do
        local cd = ally.characterData or ally
        local name = ns.safe(cd.fullName or cd.name)
        if name and ns.validName(ns.short(name)) then
            local full = ns.fullName(name)
            if not ns.Radar.byName[full] then
                local a = ns.db.allies[full] or { count = 1, note = "" }
                a.lvl = ns.safe(cd.level) or a.lvl
                a.last = math.max(a.last or 0, ns.now() - 86400)
                a.blizz = true
                -- class from the class ID
                local cid = ns.safe(cd.classID)
                if cid and not a.class and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                    local okc, ci = pcall(C_CreatureInfo.GetClassInfo, cid)
                    if okc and ci then a.class = ci.classFile end
                end
                -- online status (stateData.isOnline), valid only briefly
                local sd = ally.stateData
                if type(sd) == "table" and sd.isOnline ~= nil then
                    a.online, a.onlineAt = ns.safe(sd.isOnline) and true or false, ns.now()
                    local loc = ns.safe(sd.currentLocation)
                    if a.online and loc and loc ~= "" then a.zone = loc end
                end
                ns.db.allies[full] = a
            end
        end
    end
end

-- true = online, false = offline, nil = unknown (then grayed out)
function Social.AllyOnline(name, a)
    local short = ns.short(name)
    -- in my group?
    if (UnitInParty and UnitInParty(short)) or (UnitInRaid and UnitInRaid(short)) then
        return UnitIsConnected and UnitIsConnected(short) and true or false
    end
    -- in the friends list?
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, short)
        if ok and type(info) == "table" then return info.connected and true or false end
    end
    -- Blizzard's recent allies (fresh, at most 3 minutes old)
    if a and a.online ~= nil and ns.now() - (a.onlineAt or 0) < 180 then return a.online end
    -- Demo
    if a and a.demo then return a.demoOnline and true or false end
    return nil
end

local CLASS_ROLES = {
    WARRIOR = "td", PALADIN = "thd", DRUID = "thd", PRIEST = "hd", SHAMAN = "hd",
    HUNTER = "d", ROGUE = "d", MAGE = "d", WARLOCK = "d",
}
function Social.AllyRoles(a)
    -- entered yourself > seen in the group > estimated from the class
    local s = a.roles or a.seen or CLASS_ROLES[a.class or ""] or "d"
    return { tank = s:find("t") ~= nil, heal = s:find("h") ~= nil, dps = s:find("d") ~= nil }, (a.roles or a.seen) ~= nil, a.roles == nil and a.seen ~= nil
end

function Social.InviteGroup(name, demo)
    if demo then ns.print(L["(Demo) Invite sent to "] .. ns.displayName(name)) return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName(name)) elseif InviteUnit then pcall(InviteUnit, ns.ChatName(name)) end
end
function Social.InviteGuild(name, demo)
    if demo then ns.print(L["(Demo) Guild invite to "] .. ns.displayName(name)) return end
    if C_GuildInfo and C_GuildInfo.Invite then pcall(C_GuildInfo.Invite, name) elseif GuildInvite then pcall(GuildInvite, name) end
end
function Social.AddFriend(name, demo)
    if demo then ns.print(L["(Demo) Friend added: "] .. ns.displayName(name)) return end
    if C_FriendList and C_FriendList.AddFriend then pcall(C_FriendList.AddFriend, name) elseif AddFriend then pcall(AddFriend, name) end
end
function Social.IsFriend(name)
    if not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
    local ok, info = pcall(C_FriendList.GetFriendInfo, ns.short(name))
    return ok and type(info) == "table"
end

function Social.Allies()
    local out = {}
    for name, a in pairs(ns.db.allies) do
        if not ns.Radar.byName[name] then
            local row = { name = name }
            for k, v in pairs(a) do row[k] = v end
            out[#out + 1] = row
        end
    end
    local have = {}
    for _, a in ipairs(out) do have[ns.short(a.name)] = true end
    for _, r in ipairs(ns.Store.List("rep")) do
        local t = r.target
        if t and not ns.isMe(r.who) and not have[ns.short(t)] and not ns.Radar.byName[t] and not ns.isMe(t) then
            have[ns.short(t)] = true
            out[#out + 1] = { name = t, class = r.class, lvl = r.lvl, last = r.u or 0, note = "", fromGuild = true }
        end
    end
    for _, a in ipairs(out) do a.isOnline = Social.AllyOnline(a.name, ns.db.allies[a.name] or {}) == true end
    -- 0.6.301: newest contact on top (before online/favorite/note first - new ones never moved up)
    table.sort(out, function(a, b)
        if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

------------------------------------------------------------------------
-- Blizzard's newcomer tag (new to WoW)
------------------------------------------------------------------------
function Social.IAmNewcomer()
    local M = C_PlayerMentorship
    if not (M and M.IsActivePlayerConsideredNewcomer) then return false end
    local ok, v = pcall(M.IsActivePlayerConsideredNewcomer)
    return ok and v == true
end

------------------------------------------------------------------------
-- Near you: guild members in the same zone or at a matching level
------------------------------------------------------------------------
function Social.Near()
    local out = {}
    local myZone = ns.safe(GetRealZoneText()) or ""
    local myLvl = ns.safe(UnitLevel("player")) or 0
    local mine = {}
    for _, q in ipairs(Social.MyQuests()) do mine[q.id] = true end
    for _, m in ipairs(ns.Radar.roster) do
        if m.online and not ns.isMe(m.name) then
            local sameZone = myZone ~= "" and m.zone == myZone
            local close = math.abs((m.level or 0) - myLvl) <= 5
            -- "Near you" really means the same zone (matching level alone isn't enough)
            if sameZone then
                local shared = 0
                local pr = ns.db.members[m.name]
                for id in pairs(questSet(pr and pr.qs)) do if mine[id] then shared = shared + 1 end end
                out[#out + 1] = { m = m, sameZone = sameZone, close = close, shared = shared }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.shared ~= b.shared then return a.shared > b.shared end
        if a.sameZone ~= b.sameZone then return a.sameZone end
        return math.abs((a.m.level or 0) - myLvl) < math.abs((b.m.level or 0) - myLvl)
    end)
    return out
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local view, selected = "quests", nil
-- "Recent companions" is its own page (same layout, fixed to this view)
refreshSocial = function()
    ns.RefreshPage("social")
    ns.RefreshPage("allies")
end

------------------------------------------------------------------------
-- 0.6.137: add players to the player book by hand - right-click a name (chat, group, raid, target, friends)
-- or /oa buch for the current target. Creates the entry, opens the player book and puts the cursor in the note.
------------------------------------------------------------------------
function Social.AddToBook(name, unit)
    if type(name) ~= "string" or name == "" then return end
    local full = ns.fullName(name)
    if not full or ns.isMe(full) then return end
    local e = Social.Entry(full)
    if unit and UnitExists(unit) then
        local _, classFile = UnitClass(unit)
        e.class = ns.safe(classFile) or e.class
        e.lvl = ns.safe(UnitLevel(unit)) or e.lvl
        local g = ns.safe(GetGuildInfo(unit))
        if g ~= nil then e.guild = g end
    end
    if (e.last or 0) == 0 then e.last = ns.now() end
    e.manual = true
    selected = full
    view = "allies"
    ns.ShowPage("allies")
    refreshSocial()
    ns.After(0.15, function()
        local pg = Social._page
        if pg and pg.detailNote then pg.detailNote:SetFocus() end
    end)
    K.Toast(L["Player book"], (L["%s is now in your player book - add a note."]):format(ns.displayName(full)), C.accent)
end
-- entry in Blizzard's right-click menus (official way: Menu.ModifyMenu, Blizzard menus stay unchanged)
local MENU_TAGS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FRIEND",
    "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FOCUS", "MENU_UNIT_CHAT_ROSTER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER" }
local function bookMenu(owner, root, ctx)
    if not ctx then return end
    local unit = ctx.unit
    local name = ctx.name
    if unit and UnitExists(unit) then
        if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
        local n, realm = ns.UnitFullName(unit)
        n, realm = ns.safe(n), ns.safe(realm)
        if n then name = (realm and realm ~= "") and (n .. "-" .. realm) or n end
    elseif name and ctx.server and ctx.server ~= "" and not name:find("-", 1, true) then
        name = name .. "-" .. ctx.server
    end
    name = ns.safe(name)
    if not name or name == "" or ns.isMe(name) then return end
    root:CreateDivider()
    root:CreateTitle("Oasis")
    root:CreateButton(L["Add to player book"], function() Social.AddToBook(name, unit) end)
end
if ns.Listen then ns.Listen("LOGIN", function()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs(MENU_TAGS) do pcall(Menu.ModifyMenu, tag, function(owner, root, ctx) pcall(bookMenu, owner, root, ctx) end) end
end) end
ns.slash = ns.slash or {}
ns.slash.buch = function()
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
        local n, realm = ns.UnitFullName("target")
        n, realm = ns.safe(n), ns.safe(realm)
        if n then Social.AddToBook((realm and realm ~= "") and (n .. "-" .. realm) or n, "target") return end
    end
    ns.print(L["Target a player first, then /oa book."])
end
ns.slash.book = ns.slash.buch
local allyFilter, roleFilter = "all", nil
local rateFilter   -- 0.6.300: "good" | "bad" | nil, applies in every tab
local allySearch = ""
local bookLoaded = false
local function bookState()
    ns.char.bookUI = ns.char.bookUI or {}
    return ns.char.bookUI
end
local function saveBook(p)
    local st = bookState()
    st.filter, st.role, st.search, st.selected, st.rate = allyFilter, roleFilter, allySearch, selected, rateFilter
    if p and p.allies then st.scroll = p.allies.target or p.allies.pos or 0 end
end
local function loadBook()
    if bookLoaded then return end
    bookLoaded = true
    local st = bookState()
    allyFilter = ({ all=true, fav=true, online=true, guild=true })[st.filter] and st.filter or "all"
    roleFilter = ({ tank=true, heal=true, dps=true })[st.role] and st.role or nil
    rateFilter = ({ good=true, bad=true })[st.rate] and st.rate or nil
    allySearch = type(st.search) == "string" and st.search or ""
    selected = type(st.selected) == "string" and st.selected or nil
end
local function bookGlass(frame, fill, line)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(frame, fill, line, 8) end
end
local function bookButton(button, primary)
    local c = primary and C.accent or C.text
    local fill = { c[1], c[2], c[3], primary and 0.12 or 0.035 }
    bookGlass(button, fill, nil)
    if button.sheen then button.sheen:Hide() end
    button:HookScript("OnEnter", function(self) bookGlass(self, { c[1], c[2], c[3], fill[4] + 0.05 }, { 1, 1, 1, 0.16 }) end)
    button:HookScript("OnLeave", function(self) bookGlass(self, fill, nil) end)
    return button
end
local function bookHover(row, on)
    local from, target = row.bookHover or 0, on and 1 or 0
    local function step(q)
        row.bookHover = from + (target - from) * q
        bookGlass(row, { 1, 1, 1, 0.025 + 0.035 * row.bookHover }, { 1, 1, 1, 0.055 + 0.045 * row.bookHover })
    end
    if K.Tween and not ns.db.settings.noAnim then K.Tween(row, 0.14, step) else step(1) end
end
local function bookMatches(a)
    if allySearch == "" then return true end
    local text = table.concat({ ns.displayName(a.name), a.name or "", a.note or "", a.zone or "" }, " "):lower()
    return text:find(allySearch, 1, true) ~= nil
end

local function inviteName(n)
    if not ns.Radar.IsOnline(n) then
        ns.print((L["%s is offline right now."]):format(ns.displayName(n)))
        return
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName(n)) end
end
local DOT = ns.MEDIA .. "dot"
local function dot(online)
    return "|T" .. DOT .. ":8:8:0:0:64:64:0:64:0:64:" .. (online and "102:219:158" or "85:85:85") .. "|t "
end

local socialPage = {
    key = "social", title = "Quest together", order = 2.8,
    sub = "Who can you play with right now? Same quests, same area",
    build = function(p)
        p.seg = K.Segments(p, {
            { key = "quests", text = L["Quest partners"] }, { key = "near", text = L["Near you"] },
        }, function(k)
            view = k
            Social.animNext = true
            refreshSocial()
        end, 120)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        if p.fixed then p.seg:Hide() end
        p.segBase = { quests = L["Quest partners"], near = L["Near you"], allies = L["Recent players"] }
        p.hint = K.Text(p, 11, C.dim, "RIGHT")
        p.hint:SetPoint("TOPRIGHT", 0, -6)
        -- quest partners: group by quest (default) or by person
        p.group = K.Segments(p, { { key = "quest", text = L["By quest"] }, { key = "person", text = L["By person"] } }, function(k)
            ns.db.settings.socialGroup = k
            Social.animNext = true
            refreshSocial()
        end, 100)
        p:HookScript("OnShow", function() Social.animNext = true end)
        p.group:SetPoint("TOPRIGHT", 0, 0)
        p.doneBtn = K.Button(p, "", 130, 22, "ghost", function()
            ns.db.settings.socialShowDone = not ns.db.settings.socialShowDone
            refreshSocial()
        end)
        p.doneBtn:SetPoint("RIGHT", p.group, "LEFT", -14, 0)

        ----------------------------------------------------------------
        -- quest partners: on top "Online now" (one card per companion),
        -- below it the quests by zone, one row per quest
        ----------------------------------------------------------------
        p.sum = K.Panel(p, C.panel)
        p.sum:SetPoint("TOPLEFT", 0, -36)
        p.sum:SetPoint("TOPRIGHT", 0, -36)
        p.sum:SetHeight(58)
        p.sumText = K.Text(p.sum, 12, C.muted)
        p.sumText:SetPoint("LEFT", 14, 0)
        p.sumText:SetPoint("RIGHT", p.sum, "RIGHT", -160, 0)
        p.inviteAll = K.Button(p.sum, "", 140, 22, "primary")
        p.inviteAll:SetPoint("RIGHT", -10, 0)
        p.chips = {}
        local function chip(i)
            local c = p.chips[i]
            if c then return c end
            c = CreateFrame("Button", nil, p.sum)
            c:SetSize(230, 44)
            c:SetPoint("LEFT", 8 + (i - 1) * 238, 0)
            c.bg = K.Fill(c, C.raised)
            c.stripe = c:CreateTexture(nil, "ARTWORK")
            c.stripe:SetPoint("BOTTOMLEFT") c.stripe:SetPoint("BOTTOMRIGHT") c.stripe:SetHeight(2)
            c.ring = c:CreateTexture(nil, "ARTWORK")
            c.ring:SetTexture(DOT)
            c.ring:SetSize(30, 30)
            c.ring:SetPoint("LEFT", 8, 1)
            c.av = c:CreateTexture(nil, "OVERLAY")
            c.av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            c.av:SetSize(26, 26)
            c.av:SetPoint("CENTER", c.ring, "CENTER")
            c.hov = c:CreateTexture(nil, "HIGHLIGHT")
            c.hov:SetAllPoints()
            c.hov:SetColorTexture(1, 1, 1, 0.05)
            c.name = K.Text(c, 13, C.text)
            c.name:SetPoint("TOPLEFT", 46, -7)
            c.name:SetPoint("RIGHT", c, "RIGHT", -84, 0)
            c.name:SetWordWrap(false)
            c.info = K.Text(c, 11, C.muted)
            c.info:SetPoint("BOTTOMLEFT", 46, 8)
            c.info:SetPoint("RIGHT", c, "RIGHT", -84, 0)
            c.info:SetWordWrap(false)
            c.inv = K.Button(c, L["Invite"], 72, 22, "primary")
            c.inv:SetPoint("RIGHT", -8, 0)
            c.state = K.Text(c, 11, C.mint, "CENTER")
            c.state:SetPoint("CENTER", c.inv, "CENTER")
            c:SetScript("OnClick", function(self) if self.who and ns.Profile then ns.Profile.Show(self.who) end end)
            p.chips[i] = c
            return c
        end
        p.chip = chip

        p.quests = K.List(p, 34, function(l)
            local r = K.Row(l)
            r.lvl = K.Text(r, 12, C.text, "CENTER")
            r.lvl:SetWidth(26)
            r.lvl:SetPoint("LEFT", 8, 0)
            -- person row: class icon in a ring, below it a bar for the share of shared quests
            r.avRing = r:CreateTexture(nil, "ARTWORK")
            r.avRing:SetTexture(DOT)
            r.avRing:SetSize(26, 26)
            r.avRing:SetPoint("LEFT", 36, 0)
            r.av = r:CreateTexture(nil, "OVERLAY")
            r.av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.av:SetSize(22, 22)
            r.av:SetPoint("CENTER", r.avRing, "CENTER")
            r.onl = r:CreateTexture(nil, "OVERLAY", nil, 2)
            r.onl:SetTexture(DOT)
            r.onl:SetSize(8, 8)
            r.onl:SetPoint("BOTTOMRIGHT", r.avRing, "BOTTOMRIGHT", 1, -1)
            r.share = r:CreateTexture(nil, "ARTWORK")
            r.share:SetHeight(2)
            r.share:SetPoint("BOTTOMLEFT", 70, 4)
            r.shareBg = r:CreateTexture(nil, "BORDER")
            r.shareBg:SetHeight(2)
            r.shareBg:SetPoint("BOTTOMLEFT", 70, 4)
            r.shareBg:SetWidth(180)
            r.shareBg:SetColorTexture(1, 1, 1, 0.06)
            -- quests of an expanded person: guide line on the left
            r.guide = r:CreateTexture(nil, "ARTWORK")
            r.guide:SetWidth(1)
            r.guide:SetPoint("TOPLEFT", 49, 0)
            r.guide:SetPoint("BOTTOMLEFT", 49, 0)
            r.guide:SetColorTexture(1, 1, 1, 0.10)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("LEFT", 38, 0)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -280, 0)
            -- dungeon icon before the title (purple)
            r.dicon = K.Glyph(r, 15, ns.MEDIA .. "icons\\dungeons")
            r.dicon:SetPoint("LEFT", 37, 0)
            r.dicon:SetVertexColor(DUNGEON_C[1], DUNGEON_C[2], DUNGEON_C[3])
            r.dicon:Hide()
            r.hicon = K.Glyph(r, 13, ns.MEDIA .. "icons\\dungeons")
            r.hicon:SetVertexColor(DUNGEON_C[1], DUNGEON_C[2], DUNGEON_C[3])
            r.hicon:Hide()
            r.cols.qs = K.Text(r, 12, C.muted, "RIGHT")
            r.cols.qs:SetPoint("RIGHT", r, "RIGHT", -92, 0)
            r.cols.qs:SetWidth(230)
            r.inv = K.Button(r, L["Invite"], 80, 20, "ghost")
            r.inv:SetPoint("RIGHT", -6, 0)
            r.state = K.Text(r, 11, C.mint, "CENTER")
            r.state:SetPoint("CENTER", r.inv, "CENTER")
            r.head = K.Text(r, 11, C.dim)
            r.head:SetPoint("BOTTOMLEFT", 10, 5)
            r.headR = K.Text(r, 11, C.dim, "RIGHT")
            r.headR:SetPoint("BOTTOMRIGHT", -10, 5)
            r.headLine = r:CreateTexture(nil, "ARTWORK")
            r.headLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
            r.headLine:SetHeight(1)
            r.headLine:SetPoint("BOTTOMLEFT", 0, 1)
            r.headLine:SetPoint("BOTTOMRIGHT", 0, 1)
            r.newGlow = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.newGlow:SetAllPoints()
            if not K.Gradient(r.newGlow, "HORIZONTAL", { 0.3, 0.55, 1, 0.16 }, { 0.3, 0.55, 1, 0 }) then r.newGlow:SetColorTexture(0.3, 0.55, 1, 0.08) end
            r.newGlow:Hide()
            r:SetScript("OnEnter", function(self)
                local e = self.item
                if not e or e.zrow then return end
                if e.qrow or e.sub then
                    local q = e.q
                    local lines = { Social.QuestColor(q) .. q.title .. "|r", (q.lvl and ((L["Level %d"]):format(q.lvl) .. "  ·  ") or "") .. (q.zone or "") }
                    for _, n in ipairs(e.online or {}) do lines[#lines + 1] = dot(true) .. ns.Radar.Colored(n) end
                    for _, n in ipairs(e.offline or {}) do lines[#lines + 1] = dot(false) .. "|cff888888" .. ns.displayName(n) .. "|r" end
                    K.ShowTip(self, lines)
                    return
                end
                local lines = { ns.Radar.Colored(e.name), (L["%d shared quests"]):format(#e.quests), "|cff888888" .. L["Click: expand or collapse"] .. "|r" }
                for _, q in ipairs(e.quests) do
                    lines[#lines + 1] = Social.QuestColor(q) .. "[" .. (q.lvl or "?") .. "] " .. q.title .. "|r" .. (q.done and ("  |cff66db9e" .. L["done"] .. "|r") or "") .. "  |cff666666" .. (q.zone or "") .. "|r"
                end
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                local e = self.item
                -- quest row: open quest in the quest log
                if e and e.qrow and e.q and e.q.id then
                    local q = e.q
                    if not q.owners then q = setmetatable({ owners = (#(e.online or {}) > 0 and e.online) or e.offline }, { __index = e.q }) end
                    Social.OpenQuest(e.q.id, q)
                    return
                end
                if not e or e.sub or e.qrow or e.zrow then return end
                Social.open = Social.open or {}
                Social.open[e.name] = not Social.open[e.name]
                Social.animOpen = Social.open[e.name] or nil
                refreshSocial()
            end)
            return r
        end, function(r, e)
            local isHead = e.zrow and true or false
            r.head:SetShown(isHead) r.headR:SetShown(isHead) r.headLine:SetShown(isHead)
            r.lvl:SetShown(not isHead) r.cols.name:SetShown(not isHead) r.cols.qs:SetShown(not isHead)
            r.stripe:SetShown(not isHead and (r.index or 0) % 2 == 0)
            -- gradient as in the quest log: blue = new in Forever, purple = dungeon, orange = group quest
            local q0 = not isHead and e.q
            local gc = q0 and ((q0.new and { 0.3, 0.55, 1, 0.35 }) or (q0.dungeon and { DUNGEON_C[1], DUNGEON_C[2], DUNGEON_C[3], 0.28 })
                or (q0.group and { 1, 0.55, 0.25, 0.22 }))
            if gc and not K.Gradient(r.newGlow, "HORIZONTAL", gc, { gc[1], gc[2], gc[3], 0 }) then r.newGlow:SetColorTexture(gc[1], gc[2], gc[3], gc[4] * 0.45) end
            r.newGlow:SetShown(gc and true or false)
            local dun = q0 and q0.dungeon
            r.dicon:SetShown(dun and true or false)
            r.cols.name:ClearAllPoints()
            r.cols.name:SetPoint("LEFT", dun and 56 or 38, 0)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -280, 0)
            r.inv:Hide() r.state:SetText("")
            r.hicon:Hide()
            local person = not isHead and not e.qrow and not e.sub
            r.avRing:SetShown(person) r.av:SetShown(person) r.onl:SetShown(person)
            r.share:SetShown(person) r.shareBg:SetShown(person)
            r.guide:SetShown(e.sub and true or false)
            r:SetAlpha((person and not e.online) and 0.6 or 1)
            if isHead then
                -- zone header (dungeon: purple with icon)
                local dz = e.dungeon or (not e.solo and ns.Dungeons and ns.Dungeons.KeyByZone and ns.Dungeons.KeyByZone(e.zone))
                r.head:ClearAllPoints()
                r.head:SetPoint("BOTTOMLEFT", dz and 28 or 10, 5)
                if dz then r.hicon:ClearAllPoints() r.hicon:SetPoint("BOTTOMLEFT", 10, 4) r.hicon:Show() end
                r.head:SetText((dz and "|cffa36bff" or "") .. K.Upper(e.zone ~= "" and e.zone or L["Other"]) .. (dz and ("|r  |cff777777" .. L["Dungeon"] .. "|r") or "")
                    .. (e.here and ("  |cff66db9e" .. L["you are here"] .. "|r") or ""))
                r.headR:SetText((L["%d quests"]):format(e.n) .. (e.on > 0 and ("  ·  |cff66db9e" .. (L["%d online"]):format(e.on) .. "|r") or ""))
                return
            end
            local function inviteBtn(names)
                -- only those online and not yet in my group
                local todo, inGrp = {}, 0
                for _, n in ipairs(names) do
                    if Social.InMyGroup(n) then inGrp = inGrp + 1 else todo[#todo + 1] = n end
                end
                if #todo > 0 then
                    r.inv:Show()
                    r.inv:SetLabel(#todo > 1 and (L["Invite"] .. " (" .. #todo .. ")") or L["Invite"])
                    r.inv:SetScript("OnClick", function() for _, n in ipairs(todo) do inviteName(n) end end)
                elseif inGrp > 0 then
                    r.state:SetText(L["in group"])
                end
            end
            if e.qrow or e.sub then
                local q = e.q
                r.lvl:SetText(Social.QuestColor(q) .. (q.lvl or "?") .. "|r")
                local tags = ""
                if q.group then tags = tags .. "  |cffff8a3d[" .. L["Group"] .. "]|r" end
                if q.done then tags = tags .. "  |cff66db9e" .. L["done"] .. "|r" end
                if q.new then tags = tags .. "  |cff8fbaff" .. L["NEW"] .. "|r" end
                if q.dungeon then tags = tags .. "  |cffa36bff" .. L["Dungeon"] .. "|r" end
                r.cols.name:SetText((e.sub and "      " or "") .. Social.QuestColor(q) .. q.title .. "|r" .. tags)
                if e.sub then
                    r.cols.qs:SetText("|cff666666" .. (q.zone or "") .. "|r")
                    return
                end
                local names = {}
                for _, n in ipairs(e.online) do names[#names + 1] = dot(true) .. ns.Radar.Colored(n) end
                for i, n in ipairs(e.offline) do
                    if #names >= 3 then names[#names + 1] = "|cff666666+" .. (#e.offline - i + 1) .. "|r" break end
                    names[#names + 1] = "|cff555555" .. ns.displayName(n) .. "|r"
                end
                r.cols.qs:SetText(e.solo and ("|cff555555" .. (e.q.zone or "") .. "|r") or table.concat(names, "  "))
                inviteBtn(e.online)
                return
            end
            -- per person
            local m = ns.Radar.byName[e.name]
            local opened = Social.open and Social.open[e.name]
            r.lvl:SetText(opened and "|cffaaaaaav|r" or "|cff777777>|r")
            local cls = (m and m.class) or (ns.Radar.ClassOf and ns.Radar.ClassOf(e.name))
            local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
            if tc then r.av:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) r.av:SetAlpha(1) else r.av:SetAlpha(0) end
            local cr, cg, cb = ns.classColor(cls)
            cr, cg, cb = cr or 0.6, cg or 0.6, cb or 0.6
            r.avRing:SetVertexColor(cr, cg, cb, 0.9)
            if e.online then r.onl:SetVertexColor(0.4, 0.86, 0.62, 1) else r.onl:SetVertexColor(0.33, 0.33, 0.33, 1) end
            r.share:SetColorTexture(cr, cg, cb, 0.85)
            local sw = math.max(2, 180 * math.min(1, #e.quests / math.max(1, Social.maxShared or 1)))
            if Social.animNext and not (ns.db.settings.noAnim) then
                r.share:SetWidth(1)
                K.Tween(r.share, 0.5, function(q) r.share:SetWidth(math.max(1, sw * (1 - (1 - q) ^ 3))) end, function() r.share:SetWidth(sw) end, 0.15)
            else
                r.share:SetWidth(sw)
            end
            r.cols.name:ClearAllPoints()
            r.cols.name:SetPoint("LEFT", 70, 2)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -280, 0)
            r.cols.name:SetText(ns.Radar.Colored(e.name) .. (m and m.level and ("  |cff777777" .. m.level .. "|r") or "")
                .. "   |cffe8b44a" .. (L["%d shared quests"]):format(#e.quests) .. "|r")
            r.cols.qs:SetText(e.online and m and m.zone and ("|cff888888" .. m.zone .. "|r") or ("|cff555555" .. L["offline"] .. "|r"))
            if e.online then inviteBtn({ e.name }) end
        end)
        p.quests:SetPoint("TOPLEFT", 0, -102)
        p.quests:SetPoint("BOTTOMRIGHT")
        p.quests.empty:SetText(L["Nobody in the guild has the same quests right now.\nAs soon as members with Oasis pick up the same quests, they show up here."])

        ----------------------------------------------------------------
        -- Near you
        ----------------------------------------------------------------
        p.near = K.List(p, 38, function(l)
            local r = K.Row(l)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("TOPLEFT", 12, -4)
            r.cols.name:SetWidth(240)
            r.cols.meta = K.Text(r, 11, C.muted)
            r.cols.meta:SetPoint("BOTTOMLEFT", 12, 4)
            r.cols.meta:SetWidth(300)
            r.cols.tags = K.Text(r, 11, C.text)
            r.cols.tags:SetPoint("LEFT", 330, 0)
            r.cols.tags:SetWidth(240)
            r.inv = K.Button(r, L["Invite"], 84, 22, "primary")
            r.inv:SetPoint("RIGHT", -36, 0)
            r.w = CreateFrame("Button", nil, r)
            r.w:SetSize(18, 18)
            r.w:SetPoint("RIGHT", -10, 0)
            r.w.icon = K.Glyph(r.w, 16, ns.MEDIA .. "icons\\badges\\chat")
            r.w.icon:SetPoint("CENTER")
            r.w:SetScript("OnEnter", function(self) K.ShowTip(self, L["Whisper"]) end)
            r.w:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnEnter", function(self) if self.item then ns.Radar.ShowMemberTip(self, self.item.m) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.item and ns.Profile then ns.Profile.Show(self.item.m.name) end end)
            return r
        end, function(r, e)
            local m = e.m
            r.cols.name:SetText(dot(true) .. ns.Radar.Label(m.name) .. " |cff888888" .. m.level .. "|r  " .. (ns.Profile and ns.Profile.RoleIcons(m.name, 13) or ""))
            r.cols.meta:SetText((e.sameZone and ("|cff66db9e" .. m.zone .. "|r") or m.zone) .. "  ·  " .. (e.close and L["matching level"] or L["same zone"]))
            local t = {}
            if e.shared > 0 then t[#t + 1] = "|cffe8b44a" .. (L["%d shared quests"]):format(e.shared) .. "|r" end
            if e.sameZone then t[#t + 1] = "|cff66db9e" .. L["in the same zone"] .. "|r" end
            r.cols.tags:SetText(table.concat(t, "   "))
            r.inv:SetScript("OnClick", function() inviteName(m.name) end)
            r.w:SetScript("OnClick", function() ns.Whisper(m.name) end)
        end)
        p.near:SetPoint("TOPLEFT", 0, -36)
        p.near:SetPoint("BOTTOMRIGHT")
        p.near.empty:SetText(L["Nobody from the guild is online in your area or level right now."])

        ----------------------------------------------------------------
        -- recent companions (from outside the guild)
        ----------------------------------------------------------------
        loadBook()
        p.allies = K.List(p, 36, function(l)   -- 0.6.291: two lines, compact (name | note/when/where)
            local r = K.Row(l)
            r.noBoxFrame = true   -- 0.6.291: rows without image frame
            -- rating: check = good (favorite), X = bad (warning)
            r.fav = CreateFrame("Button", nil, r)
            r.fav:SetSize(18, 18)
            r.fav:SetPoint("LEFT", 6, 0)
            r.fav.icon = r.fav:CreateTexture(nil, "ARTWORK")
            r.fav.icon:SetAllPoints()
            r.fav.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            r.bad = CreateFrame("Button", nil, r)
            r.bad:SetSize(18, 18)
            r.bad:SetPoint("LEFT", r.fav, "RIGHT", 2, 0)
            r.bad.icon = r.bad:CreateTexture(nil, "ARTWORK")
            r.bad.icon:SetAllPoints()
            r.bad.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            r.warnBg = r:CreateTexture(nil, "BACKGROUND", nil, 2)
            r.warnBg:SetAllPoints()
            r.warnBg:SetColorTexture(0.85, 0.15, 0.15, 0.12)
            -- faint blue: guild experiences exist
            r.guildBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.guildBg:SetAllPoints()
            r.guildBg:SetColorTexture(0.35, 0.55, 1, 0.08)
            r.warnBar = r:CreateTexture(nil, "ARTWORK")
            r.warnBar:SetPoint("TOPLEFT")
            r.warnBar:SetPoint("BOTTOMLEFT")
            r.warnBar:SetWidth(3)
            r.warnBar:SetColorTexture(0.95, 0.2, 0.2, 1)
            r.cols.name = K.Text(r, 13, C.text)
            -- Oasis contact: tooltip "uses Oasis (version, last seen)"
            r:HookScript("OnEnter", function(self) if self.oasisTip and self.item then K.ShowTip(self, { ns.Radar.Colored(self.item.name), "|cff66db9e" .. self.oasisTip .. "|r" }) end end)
            r:HookScript("OnLeave", function(self) if self.oasisTip then GameTooltip:Hide() end end)
            -- single line: name + level | when/where | roles | note | buttons
            r.cav = r:CreateTexture(nil, "ARTWORK")
            r.cav:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.cav:SetSize(24, 24)
            r.cav:SetPoint("LEFT", 50, 0)
            r.conl = r:CreateTexture(nil, "OVERLAY")
            r.conl:SetTexture(DOT)
            r.conl:SetSize(7, 7)
            r.conl:SetPoint("BOTTOMRIGHT", r.cav, "BOTTOMRIGHT", 2, -2)
            r.cols.name:SetPoint("TOPLEFT", 84, -4)
            r.cols.name:SetWidth(186)
            r.cols.name:SetWordWrap(false)
            r.cols.meta = K.Text(r, 11, C.muted)
            r.cols.meta:SetPoint("TOPLEFT", 84, -20)
            r.cols.meta:SetWidth(180)
            r.cols.meta:SetWordWrap(false)
            r.cols.note = K.Text(r, 11, C.amber)
            r.cols.note:SetPoint("LEFT", 500, 0)
            r.cols.note:SetWordWrap(false)
            r.roles = {}
            for i, k in ipairs({ "tank", "heal", "dps" }) do
                local b = CreateFrame("Button", nil, r)
                b:SetSize(16, 16)
                b:SetPoint("LEFT", 428 + (i - 1) * 20, 0)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetTexture(ns.Profile.RoleTexture(k))
                b.icon:SetAllPoints()
                b.key = k
                b:SetScript("OnClick", function(self)
                    local a = r.item and ns.db.allies[r.item.name]
                    if not a then return end
                    local cur = Social.AllyRoles(a)
                    cur[k] = not cur[k]
                    a.roles = (cur.tank and "t" or "") .. (cur.heal and "h" or "") .. (cur.dps and "d" or "")
                    refreshSocial()
                end)
                b:SetScript("OnEnter", function(self)
                    local a = r.item and ns.db.allies[r.item.name]
                    local _, set, seen = Social.AllyRoles(a or {})
                    K.ShowTip(self, { L[({ tank = "Tank", heal = "Healer", dps = "Damage" })[k]], seen and L["played this role in your group - click: on/off"] or set and L["set by you – click: on/off"] or L["guessed from class – click: on/off"] })
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                r.roles[k] = b
            end
            r.cols.note:SetWidth(120)
            r.cols.note:Hide()
            -- type the note right after the name (Enter or clicking away saves)
            r.noteEdit = CreateFrame("EditBox", nil, r)
            r.noteEdit:SetPoint("LEFT", 496, 0)
            r.noteEdit:SetHeight(20)
            r.noteEdit:SetAutoFocus(false)
            r.noteEdit:SetFont(K.FONT, 11, "")
            r.noteEdit:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
            r.noteEdit:SetTextInsets(6, 6, 0, 0)
            r.noteEdit:SetMaxLetters(120)
            r.noteEdit.bg = r.noteEdit:CreateTexture(nil, "BACKGROUND")
            r.noteEdit.bg:SetAllPoints()
            r.noteEdit.bg:SetColorTexture(1, 1, 1, 0.03)
            r.noteEdit.ph = K.Text(r.noteEdit, 11, C.dim)
            r.noteEdit.ph:SetPoint("LEFT", 6, 0)
            r.noteEdit.ph:SetText(L["Note ..."])
            local function saveNote(self)
                if not r.item then return end
                if (self:GetText() or "") == "" and not ns.db.allies[r.item.name] then return end
                local owner = self.noteOwner or r.item.name
                local a = Social.Entry(owner)
                if a then
                    a.note = self:GetText() or ""
                    Social.ShareRep(owner)
                end
            end
            r.noteEdit:SetScript("OnTextChanged", function(self) self.ph:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end)
            r.noteEdit:SetScript("OnEditFocusGained", function(self)
                self.noteOwner = r.item and r.item.name
                self.originalNote = self:GetText() or ""
                self.ph:Hide()
                bookGlass(self, { 1, 1, 1, 0.08 }, { 1, 1, 1, 0.18 })
            end)
            r.noteEdit:SetScript("OnEditFocusLost", function(self)
                saveNote(self)
                self.noteOwner = nil
                bookGlass(self, { 1, 1, 1, 0.025 }, nil)
                self.ph:SetShown((self:GetText() or "") == "")
            end)
            r.noteEdit:SetScript("OnEnterPressed", function(self) saveNote(self) self:ClearFocus() end)
            r.noteEdit:SetScript("OnEscapePressed", function(self) self:SetText(self.originalNote or "") self:ClearFocus() end)
            r.guild = K.Button(r, L["Guild"], 50, 20, "ghost")
            r.guild:SetPoint("RIGHT", -30, 0)
            r.party = K.Button(r, L["Group"], 58, 20, "primary")
            r.party:SetPoint("RIGHT", r.guild, "LEFT", -6, 0)
            -- note ends before the buttons (before a fixed 300 px -> lay under "Group"/"Guild")
            r.noteEdit:SetPoint("RIGHT", r.party, "LEFT", -8, 0)
            r:RegisterForClicks("AnyUp")
            r.bx = K.IconButton(r, "x", 18, nil, L["Remove from list"])
            r.bx:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnClick", function(self, btn)
                if not self.item then return end
                if btn == "RightButton" then
                    local a = self.item
                    local e = ns.db.allies[a.name]
                    local canGuild = (CanGuildInvite and CanGuildInvite()) or a.demo
                    K.ShowMenu(self, {
                        { text = L["Whisper"], disabled = not a.isOnline, fn = function() ns.Whisper(a.name) end },
                        { text = L["Invite to group"], disabled = not a.isOnline, fn = function() Social.InviteGroup(a.name, a.demo) end },
                        { text = L["Invite to guild"], disabled = not canGuild, fn = function() Social.InviteGuild(a.name, a.demo) end },
                        { text = L["Add as friend"], disabled = Social.IsFriend(a.name), fn = function() Social.AddFriend(a.name, a.demo) end },
                        { text = (e and e.fav) and L["Remove favorite"] or L["Mark as favourite"], fn = function()
                            if e then e.fav = not e.fav or nil end
                            refreshSocial()
                        end },
                        { text = (e and e.ninja) and L["Remove ninja mark"] or L["Report as ninja looter"], fn = function()
                            local x = Social.Entry(a.name)
                            if not x then return end
                            x.ninja = not x.ninja or nil
                            if x.ninja then x.bad = true x.fav = nil end
                            Social.ShareRep(a.name)
                            refreshSocial()
                        end },
                        { text = L["View gear"], disabled = not ns.Scout, fn = function() if ns.Scout then ns.Scout.ShowGear(a.name) end end },
                        { text = L["View talents"], fn = function() if ns.Talents then ns.Talents.Show(a.name) end end },
                        { text = L["Suggest for recruiting"], disabled = not ns.Scout or (ns.Scout.Suggested and ns.Scout.Suggested(a.name) ~= nil),
                          fn = function() ns.Scout.Suggest(a.name) end },
                        { text = L["Edit note"], fn = function()
                            selected = a.name
                            refreshSocial()
                            if p.detailNote then p.detailNote:SetFocus() end
                        end },
                        { text = L["Remove from list"], fn = function()
                            ns.db.allies[a.name] = nil
                            refreshSocial()
                        end },
                    }, ns.colorName(a.name, a.class))
                    return
                end
                selected = selected ~= self.item.name and self.item.name or nil
                p.noteBox:SetText(ns.db.allies[selected] and ns.db.allies[selected].note or "")
                refreshSocial()
            end)
            bookGlass(r, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.055 })
            bookGlass(r.noteEdit, { 1, 1, 1, 0.025 }, nil)
            bookButton(r.party, true) bookButton(r.guild)
            r:HookScript("OnEnter", function(self) bookHover(self, true) if self.showControls then self.showControls(true) end end)
            r:HookScript("OnLeave", function(self)
                bookHover(self, false)
                if self.showControls and not (self.IsMouseOver and self:IsMouseOver()) then self.showControls(false) end
            end)
            return r
        end, function(r, a)
            r.fav.icon:SetDesaturated(not a.fav)
            r.fav.icon:SetAlpha(1)   -- opacity is controlled by the button (showControls)
            r.bad.icon:SetDesaturated(not a.bad)
            r.bad.icon:SetAlpha(1)
            r.warnBg:SetShown(a.bad and true or false)
            r.warnBg:SetColorTexture(0.85, 0.15, 0.15, a.ninja and 0.24 or 0.12)
            r.warnBar:SetShown(a.bad and true or false)
            r.fav:SetScript("OnClick", function()
                local e = Social.Entry(a.name)
                if e then e.fav = not e.fav or nil if e.fav then e.bad = nil end end
                Social.ShareRep(a.name)
                refreshSocial()
            end)
            r.bad:SetScript("OnClick", function()
                local e = Social.Entry(a.name)
                if e then e.bad = not e.bad or nil if e.bad then e.fav = nil end end
                Social.ShareRep(a.name)
                refreshSocial()
            end)
            r.fav:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Good - happy to play again"], a.fav and L["Click: undo"] or L["Click: mark as good (favourite)"] }) end)
            r.fav:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.bad:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Bad - rather not"], L["Oasis warns you when they whisper you or are in your group."], a.bad and L["Click: undo"] or L["Click: mark as bad"] }) end)
            r.bad:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- note takes the room up to the buttons (offline without buttons: up to the X)
            local rw = r:GetWidth() or 0
            local canGuild = ((CanGuildInvite and CanGuildInvite()) or a.demo) and a.isOnline
            local reserve = a.isOnline and (canGuild and 160 or 100) or 34
            local nameWidth = math.max(130, math.min(280, rw * 0.32))
            r.cols.name:SetWidth(nameWidth)
            r.cols.meta:SetWidth(nameWidth)
            for i, key in ipairs({ "tank", "heal", "dps" }) do
                r.roles[key]:ClearAllPoints()
                r.roles[key]:SetPoint("RIGHT", r, "RIGHT", -34 - (3 - i) * 22, 0)
            end
            r.party:ClearAllPoints()
            r.party:SetPoint("RIGHT", r, "RIGHT", canGuild and -86 or -30, 0)
            r.noteEdit:ClearAllPoints()
            r.noteEdit:SetPoint("LEFT", nameWidth + 132, 0)
            r.noteEdit:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
            if r.noteEdit:HasFocus() and r.noteEdit.noteOwner ~= a.name then r.noteEdit:ClearFocus() end
            r.noteEdit:SetMaxLetters(250)
            if not r.noteEdit:HasFocus() then r.noteEdit:SetText(a.note or "") end
            r.noteEdit.ph:SetShown((a.note or "") == "" and not r.noteEdit:HasFocus())
            -- don't show realm (all on the same server); WoW Forever: "First-Last" as "First Last"
            local on = a.isOnline
            local base, realm = a.name:match("^(.-)%-(.+)$")
            local myRealm = (ns.me() or ""):match("%-(.+)$")
            local shown = a.name
            if realm and realm == myRealm then shown = base
            elseif base then shown = base end
            local cr, cg, cb = ns.classColor(a.class)
            local oc = ns.Contacts and ns.Contacts.Get(a.name)
            local atc = a.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[a.class]
            if atc then r.cav:SetTexCoord(atc[1], atc[2], atc[3], atc[4]) r.cav:SetVertexColor(1, 1, 1, on and 1 or 0.6)
            else r.cav:SetTexCoord(0, 0.01, 0, 0.01) r.cav:SetVertexColor(1, 1, 1, 0) end
            if on then r.conl:SetVertexColor(0.4, 0.86, 0.62, 1) else r.conl:SetVertexColor(0.3, 0.3, 0.3, atc and 1 or 0.6) end
            r.cols.name:SetText(("|cff%02x%02x%02x"):format((cr or 0.8) * 255, (cg or 0.8) * 255, (cb or 0.8) * 255) .. shown .. "|r |cff888888" .. (a.lvl or "?") .. "|r"
                .. (oc and ("  " .. ns.Contacts.LOGO) or ""))
            r.oasisTip = oc and ns.Contacts.TipLine(oc) or nil
            r:SetAlpha((on or a.bad) and 1 or 0.85)
            local roles, set = Social.AllyRoles(a)
            for k, b in pairs(r.roles) do
                local c = ns.Profile.ROLE_COLORS[k]
                local f = roles[k] and (set and 1 or 0.7) or 0.18
                b.icon:SetVertexColor(c[1] * f + (roles[k] and 0 or 0.12), c[2] * f + (roles[k] and 0 or 0.12), c[3] * f + (roles[k] and 0 or 0.12))
            end
            local times = (a.count or 1) > 1 and ((L["%dx together"]):format(a.count) .. "  ·  ") or ""
            if a.fromGuild then times = "|cff9b8cff" .. L["known only via the guild"] .. "|r  ·  " end
            local gu, gd, glist = Social.GuildRep(a.name)
            local gtxt = ""
            if gd > 0 then gtxt = "|cffff5a5a" .. (L["Guild: %d bad"]):format(gd) .. "|r  ·  " elseif gu > 0 then gtxt = "|cff66db9e" .. (L["Guild: %d good"]):format(gu) .. "|r  ·  " end
            -- 0.6.290: no "01.01.70" without a timestamp
            local when = ((tonumber(a.last) or 0) > 86400) and ns.ago(a.last) or ""
            local VIA = { whisper = L["whispered"], trade = L["traded"], duel = L["Duel"], manual = L["added"], group = L["Group"], guild = L["from the guild"] }
            local via = a.via and VIA[a.via]
            if via then times = "|cff9a9aa0" .. via .. "|r  ·  " .. times end
            local metaText = gtxt .. times .. when .. ((a.zone or "") ~= "" and ((when ~= "" and "  ·  " or "") .. a.zone) or "")
            metaText = metaText:gsub("  ·  $", "")
            r.cols.meta:SetText(metaText)
            r.glist = glist
            r.guildBg:SetShown(false)   -- 0.6.290: no blue area anymore, "Guild: x good" is shown as text
            r.cols.note:SetText(a.note or "")
            r.sel:SetShown(selected == a.name)
            local canInvite = (CanGuildInvite and CanGuildInvite()) or a.demo
            r.guild:SetShown((canInvite and a.isOnline) and true or false)
            r.guild:SetScript("OnClick", function() Social.InviteGuild(a.name, a.demo) end)
            r.guild:SetScript("OnEnter", function(self) K.ShowTip(self, L["Invite to guild"]) end)
            r.guild:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.party:SetShown(a.isOnline and true or false)
            r.party:SetScript("OnClick", function() Social.InviteGroup(a.name, a.demo) end)
            r.party:SetScript("OnEnter", function(self) K.ShowTip(self, L["Invite to group"]) end)
            r.party:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnEnter", function(self)
                if not self.glist or #self.glist == 0 then return end
                local t = { L["Experiences from the guild"] }
                for _, g in ipairs(self.glist) do
                    t[#t + 1] = (g.v == "up" and "|cff66db9e+|r " or g.v == "down" and "|cffff5a5a-|r " or "  ") .. ns.displayName(g.who) .. ((g.note or "") ~= "" and (": " .. g.note) or "")
                end
                K.ShowTip(self, t)
            end)
            r:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if not (self.IsMouseOver and self:IsMouseOver()) then self.bx:SetAlpha(0.25) end
            end)
            r:HookScript("OnEnter", function(self) self.bx:SetAlpha(1) end)
            r.bx:SetAlpha(0.25)
            -- 0.6.290: two lines - name on top, below it note (amber) and when/where (quiet); details in the card
            r.noteEdit:Hide()
            r.cols.note:Hide()
            r.cols.name:SetWidth(math.max(120, rw - 86 - 110))
            r.cols.meta:SetWidth(math.max(120, rw - 86 - 110))
            local note = (a.note or "") ~= "" and ("|cffe8b44a" .. a.note .. "|r") or ""
            r.cols.meta:SetText(note .. ((note ~= "" and metaText ~= "") and "   " or "") .. (metaText ~= "" and ("|cff777777" .. metaText .. "|r") or ""))
            r.cols.meta:Show()
            r.party:Hide() r.guild:Hide()
            -- rating and roles: show only what's set, on hover everything clickable
            local function showControls(hover)
                -- good/bad always visible (unset dimmed) so you can see that you can rate
                r.fav:SetAlpha(a.fav and 1 or (hover and 0.5 or 0.22))
                r.bad:SetAlpha(a.bad and 1 or (hover and 0.5 or 0.22))
                for k, b in pairs(r.roles) do b:SetAlpha(roles[k] and 1 or (hover and 0.5 or 0)) end
            end
            r.showControls = showControls
            showControls(false)
            r.bx:SetScript("OnClick", function()
                if selected == a.name then selected = nil end
                ns.db.allies[a.name] = nil
                refreshSocial()
            end)
        end)
        p.bookSearch = K.Input(p, 260, L["Search player, note or zone"], function(text)
            allySearch = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            p.allies.offset, p.allies.pos, p.allies.target = 0, 0, 0
            refreshSocial()
        end)
        p.bookSearch:SetPoint("TOPLEFT", 0, 0)
        p.bookSearch:SetText(allySearch)
        -- 0.6.301: add a player by hand (name; same realm works without realm)
        p.bookAdd = K.Button(p, "+ " .. L["Add"], 100, 24, "ghost", function()
            local function add(t)
                t = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if t == "" then return end
                local full = Social.Touch(t, "manual")
                if full then selected = full ns.print((L["Added to the player book: %s"]):format(ns.displayName(full)))
                else ns.print(L["Not added – guild member, yourself or invalid name."]) end
            end
            if ns.WhisperLog and ns.WhisperLog.Prompt then
                ns.WhisperLog.Prompt(L["Add player"], L["Player name (same realm: without realm)"], "", add, L["Add"])
            else
                add(p.bookSearch:GetText())   -- without the whisper module: name from the search field
            end
        end)
        p.bookAdd:SetPoint("LEFT", p.bookSearch, "RIGHT", 8, 0)
        p:HookScript("OnHide", function(self) saveBook(self) end)
        p.allies:HookScript("OnMouseWheel", function() saveBook(p) end)
        p.details = K.Panel(p, C.panel)
        p.details:SetPoint("BOTTOMLEFT", 0, 0)
        p.details:SetPoint("BOTTOMRIGHT", 0, 0)
        p.details:SetHeight(94)
        bookGlass(p.details, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.08 })
        p.detailTitle = K.Text(p.details, 12, C.text)
        p.detailTitle:SetPoint("TOPLEFT", 12, -10)
        p.detailTitle:SetPoint("RIGHT", -38, 0)
        p.detailMeta = K.Text(p.details, 11, C.muted)
        p.detailMeta:SetPoint("TOPLEFT", 12, -30)
        p.detailMeta:SetPoint("RIGHT", -12, 0)
        p.detailNote = K.Input(p.details, 300, L["Note ..."])
        Social._page = p
        p.detailNote:SetPoint("BOTTOMLEFT", 12, 10)
        p.detailNote:SetPoint("RIGHT", p.details, "RIGHT", -190, 0)
        p.detailNote:SetMaxLetters(250)
        p.detailNote.onEnter = function(text)
            local owner = p.noteOwner
            if owner then local e = Social.Entry(owner) if e then e.note = text Social.ShareRep(owner) end end
            p.detailNote:ClearFocus()
            refreshSocial()
        end
        p.detailNote:HookScript("OnEditFocusGained", function(self) p.noteOwner = selected p.originalNote = self:GetText() end)
        p.detailNote:HookScript("OnEditFocusLost", function(self)
            local owner = p.noteOwner
            if owner then local e = Social.Entry(owner) if e then e.note = self:GetText() Social.ShareRep(owner) end end
            p.noteOwner = nil
        end)
        p.detailNote:SetScript("OnEscapePressed", function(self) self:SetText(p.originalNote or "") self:ClearFocus() end)
        p.detailParty = bookButton(K.Button(p.details, L["Group"], 72, 22, "primary", function() if selected then Social.InviteGroup(selected) end end), true)
        p.detailParty:SetPoint("BOTTOMRIGHT", -100, 10)
        p.detailGuild = bookButton(K.Button(p.details, L["Guild"], 72, 22, "ghost", function() if selected then Social.InviteGuild(selected) end end))
        p.detailGuild:SetPoint("BOTTOMRIGHT", -16, 10)
        p.detailClose = K.IconButton(p.details, "x", 18, function() p.detailNote:ClearFocus() selected = nil refreshSocial() end, L["Close details"])
        p.detailClose:SetPoint("TOPRIGHT", -10, -8)
        p.details:Hide()
        p.bookCount = K.Text(p, 11, C.muted, "RIGHT")
        p.bookCount:SetPoint("TOPRIGHT", -8, -6)
        p.allies:SetPoint("TOPLEFT", 0, -70)
        p.allies:SetPoint("BOTTOMRIGHT")
        p.allies.empty:SetText(L["No players from outside the guild yet.\nAnyone you group with shows up here automatically."])

        p.allySeg = K.Segments(p, { { key = "all", text = L["All"] }, { key = "fav", text = L["Favourites"] }, { key = "online", text = L["Online"] }, { key = "guild", text = L["From guild"] } },
            function(k) allyFilter = k refreshSocial() end, 80)
        p.allySeg:SetPoint("TOPLEFT", 0, -36)
        bookGlass(p.allySeg, nil, nil)
        p.roleFilter = {}
        local rl = K.Text(p, 11, C.muted)
        rl:SetPoint("LEFT", p.allySeg, "RIGHT", 18, 0)
        rl:SetText(L["Role:"])
        p.roleLabel = rl
        local rx = nil
        for i, k in ipairs({ "tank", "heal", "dps" }) do
            local b = CreateFrame("Button", nil, p)
            b:SetSize(26, 24)
            b.bg = K.Fill(b, C.raised)
            K.Border(b, C.line)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetTexture(ns.Profile.RoleTexture(k))
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("CENTER")
            if i == 1 then b:SetPoint("LEFT", rl, "RIGHT", 8, 0) else b:SetPoint("LEFT", rx, "RIGHT", 4, 0) end
            rx = b
            function b:Refresh()
                local on = roleFilter == k
                local c = ns.Profile.ROLE_COLORS[k]
                self.icon:SetVertexColor(on and c[1] or c[1] * 0.5, on and c[2] or c[2] * 0.5, on and c[3] or c[3] * 0.5)
                K.SetBorderColor(self, on and c or C.line)
                bookGlass(self, { 1, 1, 1, on and 0.08 or 0.025 }, on and { c[1], c[2], c[3], 0.4 } or nil)
            end
            b:SetScript("OnClick", function() roleFilter = (roleFilter ~= k) and k or nil refreshSocial() end)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { (L["Show only %s"]):format(L[({ tank = "Tank", heal = "Healer", dps = "Damage" })[k]]), L["Click again: show all"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Refresh()
            p.roleFilter[k] = b
        end
        -- 0.6.300: filter by rating (good / bad), in addition to tab and role
        p.rateLabel = K.Text(p, 11, C.muted)
        p.rateLabel:SetPoint("LEFT", rx, "RIGHT", 18, 0)
        p.rateLabel:SetText(L["Rating:"])
        p.rateFilter = {}
        local qx
        for i, it in ipairs({ { "good", "Interface\\RaidFrame\\ReadyCheck-Ready", { 0.40, 0.86, 0.62 }, L["Only rated good"] },
                              { "bad", "Interface\\RaidFrame\\ReadyCheck-NotReady", { 0.95, 0.35, 0.35 }, L["Only rated bad"] } }) do
            local k, tex, c, tip = it[1], it[2], it[3], it[4]
            local b = CreateFrame("Button", nil, p)
            b:SetSize(26, 24)
            b.bg = K.Fill(b, C.raised)
            K.Border(b, C.line)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetTexture(tex)
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("CENTER")
            if i == 1 then b:SetPoint("LEFT", p.rateLabel, "RIGHT", 8, 0) else b:SetPoint("LEFT", qx, "RIGHT", 4, 0) end
            qx = b
            function b:Refresh()
                local on = rateFilter == k
                self.icon:SetDesaturated(not on)
                self.icon:SetAlpha(on and 1 or 0.55)
                K.SetBorderColor(self, on and c or C.line)
                bookGlass(self, { 1, 1, 1, on and 0.08 or 0.025 }, on and { c[1], c[2], c[3], 0.4 } or nil)
            end
            b:SetScript("OnClick", function() rateFilter = (rateFilter ~= k) and k or nil refreshSocial() end)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { tip, L["Click again: show all"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Refresh()
            p.rateFilter[k] = b
        end
        p.noteBox = K.Input(p, 420, L["Note for the selected player, e.g. \"great healer, nice person\""])
        p.noteBox:SetPoint("TOPLEFT", 0, -68)
        p.noteBox.onEnter = function(t)
            if selected and ns.db.allies[selected] then
                ns.db.allies[selected].note = t
                refreshSocial()
            end
        end
        p.whisper = K.Button(p, L["Whisper"], 110, 24, "ghost", function()
            if selected then ns.Whisper(selected) end
        end)
        p.whisper:SetPoint("LEFT", p.noteBox, "RIGHT", 8, 0)
    end,
    refresh = function(p)
        local view = p.fixed or ((view == "allies") and "quests" or view)
        local partners = Social.Partners()
        local near = Social.Near()
        importBlizzard()
        local allies = Social.Allies()
        local counts = { quests = #Social.PartnersByName(partners), near = #near, allies = #allies }
        for _, b in ipairs(p.seg.buttons) do
            local n = counts[b.key] or 0
            b.label:SetText(p.segBase[b.key] .. (n > 0 and (" |cffff1200" .. n .. "|r") or ""))
        end
        p.quests:SetShown(view == "quests")
        p.sum:SetShown(view == "quests")
        p.near:SetShown(view == "near")
        p.allies:SetShown(view == "allies")
        p.bookSearch:SetShown(view == "allies")
        if p.bookAdd then p.bookAdd:SetShown(view == "allies") end
        p.bookCount:SetShown(view == "allies")
        p.noteBox:SetShown(false)
        if view ~= "allies" and p.detailNote:HasFocus() then p.detailNote:ClearFocus() end
        p.details:SetShown(view == "allies" and selected ~= nil)
        p.allySeg:SetShown(view == "allies")
        p.roleLabel:SetShown(view == "allies")
        for _, b in pairs(p.roleFilter) do b:SetShown(view == "allies") end
        p.rateLabel:SetShown(view == "allies")
        for _, b in pairs(p.rateFilter) do b:SetShown(view == "allies") end
        p.whisper:SetShown(false)
        p.group:SetShown(view == "quests")
        p.doneBtn:SetShown(view == "quests")
        p.doneBtn:SetLabel(ns.db.settings.socialShowDone and ("|cff66db9e" .. L["Finished: on"] .. "|r") or L["Finished: off"])
        p.hint:SetShown(view ~= "quests")
        if view == "quests" then
            local mode = ns.db.settings.socialGroup or "quest"
            p.group:Select(mode)
            local rows = {}
            if mode == "quest" then
                -- by zone: where I am first, then where most are online
                local here = ns.safe(GetRealZoneText()) or ""
                local zones, zorder = {}, {}
                for _, x in ipairs(partners) do
                    local z = x.q.zone or ""
                    local g = zones[z]
                    if not g then g = { zone = z, list = {}, on = 0 } zones[z] = g zorder[#zorder + 1] = g end
                    g.list[#g.list + 1] = x
                    g.on = g.on + #x.online
                end
                table.sort(zorder, function(a, b)
                    if (a.zone == here) ~= (b.zone == here) then return a.zone == here end
                    if a.on ~= b.on then return a.on > b.on end
                    if #a.list ~= #b.list then return #a.list > #b.list end
                    return a.zone < b.zone
                end)
                for _, g in ipairs(zorder) do
                    local dun = false
                    for _, x in ipairs(g.list) do if x.q.dungeon then dun = true end end
                    rows[#rows + 1] = { zrow = true, zone = g.zone, n = #g.list, on = g.on, here = g.zone == here and here ~= "", dungeon = dun }
                    for _, x in ipairs(g.list) do rows[#rows + 1] = { qrow = true, q = x.q, online = x.online, offline = x.offline } end
                end
                -- all other own quests (e.g. crafting) that nobody else has right now - dimmed at the end
                local shared = {}
                for _, x in ipairs(partners) do shared[x.q.id] = true end
                local showDone = ns.db.settings.socialShowDone
                local solo = {}
                for _, q in ipairs(Social.MyQuests()) do
                    if not shared[q.id] and (showDone or not q.done) then solo[#solo + 1] = q end
                end
                table.sort(solo, function(a, b)
                    if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
                    return (a.title or "") < (b.title or "")
                end)
                if #solo > 0 then
                    rows[#rows + 1] = { zrow = true, solo = true, zone = L["Only for you"], n = #solo, on = 0 }
                    for _, q in ipairs(solo) do rows[#rows + 1] = { qrow = true, solo = true, q = q, online = {}, offline = {} } end
                end
            else
                -- one row per person, their quests expanded below
                Social.maxShared = 1
                for _, e in ipairs(Social.PartnersByName(partners)) do
                    if #e.quests > Social.maxShared then Social.maxShared = #e.quests end
                    rows[#rows + 1] = e
                    if Social.open and Social.open[e.name] then
                        for _, q in ipairs(e.quests) do rows[#rows + 1] = { sub = true, q = q, name = e.name } end
                    end
                end
            end
            p.quests:SetData(rows)
            -- view changed / person expanded: rows fade in one after another
            if (Social.animNext or Social.animOpen) and not ns.db.settings.noAnim then
                local k = 0
                for _, row in ipairs(p.quests.rows) do
                    local it = row.item
                    if it and row:IsShown() and (Social.animNext or it.sub) then
                        local a = row:GetAlpha()
                        row:SetAlpha(0)
                        K.Tween(row, 0.25, function(q) row:SetAlpha(a * q) end, function() row:SetAlpha(a) end, k * 0.025)
                        k = k + 1
                    end
                end
            end
            Social.animOpen = nil
            -- top: one card per companion who is online right now
            local byName = Social.PartnersByName(partners)
            local onList, offCount = {}, 0
            for _, e in ipairs(byName) do
                if e.online then onList[#onList + 1] = e else offCount = offCount + 1 end
            end
            local maxChips = math.max(1, math.floor(((p.sum:GetWidth() or 700) - 160) / 238))
            for i, c in ipairs(p.chips) do c:Hide() end
            for i, e in ipairs(onList) do
                if i > maxChips then break end
                local c = p.chip(i)
                local m = ns.Radar.byName[e.name]
                local cr, cg, cb = ns.classColor(m and m.class)
                c.stripe:SetColorTexture(cr or 0.5, cg or 0.5, cb or 0.5, 0.8)
                c.ring:SetVertexColor(cr or 0.5, cg or 0.5, cb or 0.5, 0.9)
                local ctc = m and m.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
                if ctc then c.av:SetTexCoord(ctc[1], ctc[2], ctc[3], ctc[4]) c.av:SetAlpha(1) else c.av:SetAlpha(0) end
                c.who = e.name
                c.name:SetText(ns.Radar.Colored(e.name) .. (m and m.level and ("  |cff888888" .. m.level .. "|r") or ""))
                if Social.animNext and not ns.db.settings.noAnim then
                    c:SetAlpha(0)
                    K.Tween(c, 0.3, function(q) c:SetAlpha(q) end, function() c:SetAlpha(1) end, (i - 1) * 0.06)
                end
                c.info:SetText("|cffe8b44a" .. (L["%d shared quests"]):format(#e.quests) .. "|r" .. (m and m.zone and ("  ·  " .. m.zone) or ""))
                local inGrp = Social.InMyGroup(e.name)
                c.inv:SetShown(not inGrp)
                c.state:SetText(inGrp and L["in group"] or "")
                c.inv:SetScript("OnClick", function() inviteName(e.name) end)
                c:Show()
            end
            Social.animNext = nil
            local more = #onList - maxChips
            if #onList == 0 then
                p.sumText:SetText(#partners > 0
                    and ((L["None of your quest partners are online right now."]) .. "   |cff666666" .. (L["%d shared quests with %d people"]):format(#partners, offCount) .. "|r")
                    or ("|cff777777" .. ((ns.InGuild and not ns.InGuild()) and L["Group up with other Oasis users - Oasis then shows who has the same quests."]
                        or L["Pick up quests – Oasis shows you who in the guild has the same ones."]) .. "|r"))
            else
                p.sumText:SetText("")
            end
            local todo = {}
            for _, e in ipairs(onList) do if not Social.InMyGroup(e.name) then todo[#todo + 1] = e.name end end
            p.inviteAll:SetShown(#todo > 1)
            p.inviteAll:SetLabel((L["Invite all (%d)"]):format(#todo) .. (more > 0 and ("  +" .. more) or ""))
            p.inviteAll:SetScript("OnClick", function() for _, n in ipairs(todo) do inviteName(n) end end)
        elseif view == "near" then
            p.hint:SetText((L["Level %d  ·  %s"]):format(ns.safe(UnitLevel("player")) or 0, ns.safe(GetRealZoneText()) or ""))
            p.near:SetData(near)
        else
            p.hint:SetText("")
            local shown = {}
            for _, a in ipairs(allies) do
                local ok = allyFilter == "all" or (allyFilter == "fav" and a.fav) or (allyFilter == "online" and a.isOnline)
                    or (allyFilter == "guild" and (select(3, Social.GuildRep(a.name)))[1] ~= nil)
                if ok and roleFilter then ok = Social.AllyRoles(a)[roleFilter] end
                if ok and rateFilter then ok = (rateFilter == "good" and a.fav) or (rateFilter == "bad" and a.bad) or false end
                if ok and bookMatches(a) then shown[#shown + 1] = a end
            end
            p.bookCount:SetText((L["%d of %d players"]):format(#shown, #allies))
            p.allies.empty:SetText(#allies > 0 and L["No players match this search or filters."] or L["No players from outside the guild yet.\nAnyone you group with shows up here automatically."])
            local picked
            for _, a in ipairs(shown) do if a.name == selected then picked = a break end end
            if p.detailNote:HasFocus() and (not picked or p.noteOwner ~= selected) then p.detailNote:ClearFocus() end
            p.details:SetShown(picked ~= nil)
            p.allies:ClearAllPoints()
            p.allies:SetPoint("TOPLEFT", 0, -70)
            if picked then
                p.allies:SetPoint("BOTTOMRIGHT", p.details, "TOPRIGHT", 0, 8)
                p.detailTitle:SetText(ns.colorName(picked.name, picked.class) .. "  " .. (L["Level %d"]):format(picked.lvl or 0))
                p.detailMeta:SetText((L["%dx together"]):format(picked.count or 1) .. "  ·  " .. ns.ago(picked.last) .. ((picked.zone or "") ~= "" and ("  ·  " .. picked.zone) or ""))
                if not p.detailNote:HasFocus() then p.detailNote:SetText(picked.note or "") end
                p.detailParty:SetEnabledState(picked.isOnline and true or false)
                p.detailGuild:SetEnabledState(picked.isOnline and CanGuildInvite and CanGuildInvite() and true or false)
            else p.allies:SetPoint("BOTTOMRIGHT") end
            local restored = p.bookRestored
            p.allies:SetData(shown)
            if Social.animNext and not ns.db.settings.noAnim then
                local k = 0
                for _, row in ipairs(p.allies.rows) do
                    if row.item and row:IsShown() then
                        local al = row:GetAlpha()
                        row:SetAlpha(0)
                        K.Tween(row, 0.25, function(q) row:SetAlpha(al * q) end, function() row:SetAlpha(al) end, k * 0.02)
                        k = k + 1
                    end
                end
                Social.animNext = nil
            end
            if not restored then
                p.bookRestored = true
                local saved = bookState().scroll
                if type(saved) == "number" then p.allies.offset, p.allies.pos, p.allies.target = saved, saved, saved p.allies:Refresh() end
            end
            saveBook(p)
            for k, b in pairs(p.roleFilter) do b:Refresh() end
            for _, b in pairs(p.rateFilter) do b:Refresh() end
            p.whisper:SetEnabledState(selected ~= nil)
        end
    end,
}
ns.RegisterPage(socialPage)
ns.RegisterPage({
    key = "allies", title = "Player book", order = 2.85,
    sub = "Who you played with - rate, take notes, share with the guild",
    build = function(p) p.fixed = "allies" socialPage.build(p) end,
    refresh = function(p) p.fixed = "allies" socialPage.refresh(p) end,
})

ns.Listen("DB_READY", function() ns.db.allies = ns.db.allies or {} end)
ns.Listen("LOGIN", function()
    ns.db.allies = ns.db.allies or {}
    -- Blizzard's newcomer tag: show the greeting then too
    ns.After(30, function()
        if Social.IAmNewcomer() and ns.Welcome and IsInGuild() then
            local g = GetGuildInfo("player")
            ns.char.welcomed = ns.char.welcomed or {}
            if g and not ns.char.welcomed[g] then
                ns.char.welcomed[g] = ns.now()
                ns.Welcome.Show()
            end
        end
    end)
end)

-- online status comes from the guild roster: redraw on every update
ns.Listen("ROSTER", function() refreshSocial() end)

------------------------------------------------------------------------
-- warning for badly rated companions (X in "Recent companions")
------------------------------------------------------------------------
-- share with the guild: one record per player and rater
ns.GuildOption({ page = "allies", key = "soRepShr", default = true,
    label = "Share ratings with the guild", desc = "Good/bad marks on players are shared with the guild (off = everyone keeps them private)." })
ns.GuildOption({ page = "allies", key = "soWarnN", default = 1, min = 1, max = 5, step = 1,
    label = "Guild warning from votes", desc = "This many bad ratings from the guild are needed before a warning about a player is shown.",
    fmt = function(v) return v .. "x" end })
-- 0.6.302: ONE rating per rater and player - target without realm in the key ("Woodox" and "Woodox-Realm"
-- were two records and counted twice); a new rating replaces the old one
local function repId(target) return "rep:" .. ns.me() .. ":" .. ns.short(target) end
function Social.ShareRep(target)
    if not ns.db or ns.db.settings.shareRep == false then return end
    if ns.GuildOpt("soRepShr") == false then return end
    local e = ns.db.allies[target]
    if not e then return end
    -- remove own old entries under a different spelling of the name (otherwise the old rating keeps counting)
    local sh, id = ns.short(target), repId(target)
    for _, r in ipairs(ns.Store.List("rep")) do
        if r.id ~= id and not r.del and r.target and ns.short(r.target) == sh and ns.isMe(r.who) then ns.Store.Delete("rep", r.id) end
    end
    local old = ns.Store.Get("rep", id)
    local v = e.fav and "up" or e.bad and "down" or nil
    local note = e.note or ""
    local nj = e.ninja and 1 or nil
    if old and not old.del and old.v == v and (old.note or "") == note and old.ninja == nj then return end
    if not v and note == "" then
        if old and not old.del then ns.Store.Delete("rep", old.id) end
        return
    end
    ns.Store.Put("rep", { id = repId(target), who = ns.me(), target = target, v = v, note = note, class = e.class, lvl = e.lvl, ninja = nj })
end
-- What does the guild say (without me)? -> up, down, { {who, v, note}, ... }
function Social.GuildRep(target)
    local up, down, list, ninja = 0, 0, {}, 0
    local sh = ns.short(target)
    -- 0.6.302: per rater only the newest rating (rated again = overwrites the old one)
    local newest = {}
    for _, r in ipairs(ns.Store.List("rep")) do
        if r.target and ns.short(r.target) == sh and not ns.isMe(r.who) then
            local w = ns.short(r.who or "?")
            local cur = newest[w]
            if not cur or (tonumber(r.u) or 0) > (tonumber(cur.u) or 0) then newest[w] = r end
        end
    end
    for _, r in pairs(newest) do
        if r.v == "up" then up = up + 1 elseif r.v == "down" then down = down + 1 end
        if r.ninja == 1 then ninja = ninja + 1 end
        list[#list + 1] = r
    end
    return up, down, list, ninja
end
local function badEntry(name)
    name = ns.safe(name)
    if not name or not ns.db or not ns.db.allies then return end
    local e = ns.db.allies[name] or ns.db.allies[ns.fullName(name)]
    if e and e.fav then return end   -- marked as good yourself: no warning
    if e and e.ninja then return { note = L["reported by you as a ninja looter"] .. ((e.note or "") ~= "" and (" - " .. e.note) or ""), ninja = true }, name end
    if e and e.bad then return e, name end
    local sh = ns.short(name)
    for k, v in pairs(ns.db.allies) do
        if v.bad and ns.short(k) == sh then return v, k end
    end
    -- Guild: a ninja looter report counts immediately, otherwise more bad than good experiences
    local up, down, list, ninja = Social.GuildRep(name)
    if ninja > 0 then
        local by = {}
        for _, r in ipairs(list) do if r.ninja == 1 then by[#by + 1] = ns.displayName(r.who) end end
        return { note = (L["reported as a ninja looter by %s"]):format(table.concat(by, ", ")), guild = true, ninja = true }, name
    end
    if down > 0 and down >= (tonumber(ns.GuildOpt("soWarnN")) or 1) and down > up then
        local notes = {}
        for _, r in ipairs(list) do if r.v == "down" and (r.note or "") ~= "" then notes[#notes + 1] = ns.displayName(r.who) .. ": " .. r.note end end
        return { note = (L["%d from the guild: bad"]):format(down) .. (#notes > 0 and (" - " .. table.concat(notes, "; ")) or ""), guild = true }, name
    end
end
Social.BadEntry = badEntry
local function warn(name, e, why)
    -- notes come from members (shared): without escape sequences, shortened
    e = { note = SEC.Text(e.note, 120) }
    why = SEC.Text(why, 200)
    local note = (e.note or "") ~= "" and ("  |cffffc24d\"" .. e.note .. "\"|r") or ""
    ns.print("|cffff4d4d" .. L["Warning:"] .. "|r " .. ns.displayName(name) .. " " .. why .. note)
    if K.Toast then pcall(K.Toast, L["Warning"] .. ": " .. ns.displayName(name), why .. ((e.note or "") ~= "" and (" - " .. e.note) or ""), { 0.95, 0.25, 0.25 }) end
    if ns.Sound then pcall(ns.Sound.Play, "toast") end
end
local whisperWarned = {}
ns.On("CHAT_MSG_WHISPER", function(_, sender)
    if ns.db and ns.db.settings.allyWarnWhisper == false then return end
    local e, n = badEntry(sender)
    if not e then return end
    if e.guild and ns.db.settings.allyWarnGuild == false then return end
    if whisperWarned[n] and GetTime() - whisperWarned[n] < 600 then return end
    whisperWarned[n] = GetTime()
    warn(n, e, e.guild and L["is whispering you - the guild had bad experiences."] or L["is whispering you - you marked them as bad."])
end)
local groupWarned = {}
ns.On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then wipe(groupWarned) return end
    if ns.db and ns.db.settings.allyWarnGroup == false then return end
    local raid = IsInRaid()
    for i = 1, (GetNumGroupMembers() or 0) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local n, realm = ns.UnitFullName(u)
            n, realm = ns.safe(n), ns.safe(realm)
            if n then
                local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
                local e, key = badEntry(full)
                if e and not groupWarned[key] and not (e.guild and ns.db.settings.allyWarnGuild == false) then
                    groupWarned[key] = true
                    warn(key, e, e.guild and L["is in your group - the guild had bad experiences."] or L["is in your group - you marked them as bad."])
                end
            end
        end
    end
end)

-- tooltip over players (world, group, nameplates): own rating and guild experiences
local function repLine(tt, unit)
    if not ns.db or ns.db.settings.allyTooltip == false then return end
    if not unit or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
    local n, realm = ns.UnitFullName(unit)
    n, realm = ns.safe(n), ns.safe(realm)
    if not n then return end
    local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
    if ns.Radar.byName[ns.fullName(full)] then return end
    local mine = ns.db.allies[ns.fullName(full)] or ns.db.allies[full]
    local up, down, list, ninja = Social.GuildRep(full)
    if not (mine and (mine.fav or mine.bad or (mine.note or "") ~= "")) and #list == 0 then return end
    tt:AddLine(" ")
    tt:AddLine("|cffe8b44a" .. L["Player book"] .. "|r")
    if (ninja or 0) > 0 or (mine and mine.ninja) then tt:AddLine("|cffff3b3b" .. L["NINJA LOOTER"] .. "|r  |cffaaaaaa" .. (L["%d report(s) from the guild"]):format((ninja or 0) + ((mine and mine.ninja) and 1 or 0)) .. "|r") end
    if mine and (mine.fav or mine.bad) then
        tt:AddLine(mine.bad and ("|cffff5a5a" .. L["You: bad"] .. "|r") or ("|cff66db9e" .. L["You: good"] .. "|r"))
    end
    if mine and (mine.note or "") ~= "" then tt:AddLine("\"" .. mine.note .. "\"", 1, 0.76, 0.3, true) end
    if up + down > 0 then
        tt:AddLine((L["Guild: %d good, %d bad"]):format(up, down), down > up and 1 or 0.4, down > up and 0.35 or 0.86, down > up and 0.35 or 0.62)
    end
    for i, r in ipairs(list) do
        if i > 3 then break end
        if (r.note or "") ~= "" then tt:AddLine(ns.displayName(r.who) .. ": " .. r.note, 0.75, 0.75, 0.75, true) end
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        pcall(function() local _, unit = tt:GetUnit() repLine(tt, unit) end)
    end)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(function() local _, unit = tt:GetUnit() repLine(tt, unit) end) end)
end
end)

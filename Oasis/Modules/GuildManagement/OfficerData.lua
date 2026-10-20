-- Oasis - data for guild care: gear, attendance, guild log, ban list, applicants, export.
-- Everything runs over the normal Oasis sync (Store). Nothing is whispered or posted automatically.
local ADDON, ns = ...
ns.ModuleFile("Oasis_GuildManagement", function()   -- Guild care module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
local Store = ns.Store

local O = {}
ns.Officer = O

local function mainOf(n) return ns.Alts and ns.Alts.Main(n) or n end

------------------------------------------------------------------------
-- Gear: everyone reports their own items (no inspect needed)
-- format: "slot=itemID:enchantID,..." only for enchantable slots
------------------------------------------------------------------------
O.ENCH_SLOTS = {
    { 5, "Chest" }, { 9, "Wrists" }, { 10, "Hands" }, { 8, "Feet" }, { 15, "Back" },
    { 16, "Main hand" }, { 17, "Off hand" }, { 1, "Head", optional = true }, { 7, "Legs", optional = true },
}
function O.GearString()
    local parts = {}
    for _, s in ipairs(O.ENCH_SLOTS) do
        local link = ns.safe(GetInventoryItemLink("player", s[1]))
        if link then
            local id, ench = link:match("item:(%d+):(%-?%d*)")
            parts[#parts + 1] = s[1] .. "=" .. (id or 0) .. ":" .. ((ench ~= "" and ench) or 0)
        end
    end
    return table.concat(parts, ",")
end
-- a member's missing enchants (from their profile)
function O.MissingEnchants(name)
    local pr = ns.db.members[name]
    local gr = ns.isMe(name) and O.GearString() or (pr and pr.gr)
    if not gr or gr == "" then return nil end
    local have, miss, opt = {}, {}, {}
    for slot, id, ench in gr:gmatch("(%d+)=(%d+):(%-?%d+)") do have[tonumber(slot)] = { id = tonumber(id), ench = tonumber(ench) } end
    for _, s in ipairs(O.ENCH_SLOTS) do
        local h = have[s[1]]
        if h and h.id > 0 and (h.ench or 0) == 0 then
            local ok = true
            if s[1] == 17 then
                -- off-hand: only shields and weapons are enchantable
                local gi = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
                local _, _, _, loc = gi(h.id)
                ok = loc == "INVTYPE_SHIELD" or loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND"
            end
            if ok then table.insert(s.optional and opt or miss, L[s[2]]) end
        end
    end
    return miss, opt
end

------------------------------------------------------------------------
-- Raid attendance: the raid leader records the raid day on every boss kill (mains)
------------------------------------------------------------------------
local function raidNames()
    local out, seen = {}, {}
    for i = 1, (GetNumGroupMembers() or 0) do
        local n = ns.safe(GetRaidRosterInfo(i))
        if n then
            local m = mainOf(ns.fullName(n))
            if not seen[m] then seen[m] = true out[#out + 1] = m end
        end
    end
    return out
end
ns.On("ENCOUNTER_END", function(_, encName, _, _, success)
    if ns.safe(success) ~= 1 then return end
    local inInst, kind = IsInInstance()
    if not (inInst and kind == "raid" and IsInRaid() and UnitIsGroupLeader("player")) then return end
    local inst = ns.safe(GetInstanceInfo()) or "?"
    local day = date("%Y-%m-%d")
    local id = day .. "@" .. inst
    local old = Store.Get("attend", id)
    local names = raidNames()
    -- whoever was already recorded stays in (someone leaves before the last boss)
    local set = {}
    if old and old.n then for n in old.n:gmatch("[^,]+") do set[n] = true end end
    for _, n in ipairs(names) do set[n] = true end
    local list = {}
    for n in pairs(set) do list[#list + 1] = n end
    table.sort(list)
    Store.Put("attend", { id = id, d = day, inst = inst, n = table.concat(list, ","), b = ((old and old.b) or 0) + 1,
        last = ns.safe(encName) or "", ts = ns.now() })
end)
-- attendance of the last days: rate 0..1, attended, total
function O.Attendance(name, days)
    local since = ns.now() - (days or 28) * 86400
    local m = mainOf(name)
    local total, here = 0, 0
    for _, r in ipairs(Store.List("attend")) do
        if (r.ts or 0) >= since then
            total = total + 1
            if ("," .. (r.n or "") .. ","):find("," .. m .. ",", 1, true) then here = here + 1 end
        end
    end
    return total > 0 and here / total or nil, here, total
end

------------------------------------------------------------------------
-- guild log from system messages (everyone sees them, same message = one entry)
------------------------------------------------------------------------
local PATTERNS
local function patterns()
    if PATTERNS then return PATTERNS end
    PATTERNS = {}
    local function add(kind, gs)
        if type(gs) ~= "string" then return end
        local p = ns.GlobalPattern(gs, true)
        if p then PATTERNS[#PATTERNS + 1] = { kind = kind, pat = p } end
    end
    add("promote", ERR_GUILD_PROMOTE_SSS)
    add("demote", ERR_GUILD_DEMOTE_SSS)
    add("kick", ERR_GUILD_REMOVE_SS)
    add("join", ERR_GUILD_JOIN_S)
    add("leave", ERR_GUILD_LEAVE_S)
    return PATTERNS
end
ns.On("CHAT_MSG_SYSTEM", function(msg)
    msg = ns.safe(msg)
    if not msg or not IsInGuild() then return end
    for _, p in ipairs(patterns()) do
        local ok, a, b, c = pcall(string.match, msg, p.pat)
        if not ok then a = nil end
        if a then
            local t = ns.now()
            local id = p.kind .. ":" .. a .. ":" .. (b or "") .. ":" .. math.floor(t / 300)
            if not Store.Get("audit", id) then
                Store.Put("audit", { id = id, kind = p.kind, a = a, b = b or "", r = c or "", ts = t })
            end
            return
        end
    end
end)
function O.Audit()
    local list = Store.List("audit")
    table.sort(list, function(x, y) return (x.ts or 0) > (y.ts or 0) end)
    return list
end
function O.AuditText(r)
    if r.kind == "promote" then return (L["%s promoted %s to %s"]):format(r.a, r.b, r.r)
    elseif r.kind == "demote" then return (L["%s demoted %s to %s"]):format(r.a, r.b, r.r)
    elseif r.kind == "kick" then return (L["%s was removed by %s"]):format(r.a, r.b)
    elseif r.kind == "join" then return (L["%s joined"]):format(r.a)
    elseif r.kind == "leave" then return (L["%s left the guild"]):format(r.a)
    end
    return r.kind or "?"
end

------------------------------------------------------------------------
-- Ban list: leadership maintains it, everyone gets warnings
------------------------------------------------------------------------
local function banKey(n) return ns.NameKey(n) end
function O.BanOf(name)
    if not name then return nil end
    local r = Store.Get("bans", "ban-" .. banKey(name))
    if r and not r.del then return r end
    for _, old in ipairs(Store.List("bans")) do
        if not old.del and ns.SameName(old.name, name) then return old end
    end
end
function O.Ban(name, reason)
    Store.Put("bans", { id = "ban-" .. banKey(name), name = ns.short(name), reason = reason or "", ts = ns.now() })
end
function O.Unban(name)
    for _, r in ipairs(Store.List("bans")) do
        if ns.SameName(r.name, name) then Store.Delete("bans", r.id) end
    end
end
------------------------------------------------------------------------
-- Sound block: leadership blocks a member from sound effects. The blocked player can no longer send sounds,
-- and all other clients don't play/show their sounds (in case they use an old or modified version).
-- Applies to the whole player: main and alts.
------------------------------------------------------------------------
function O.SoundMuteOf(name)
    if not name or name == "" then return nil end
    local r = Store.Get("sndmute", "sm-" .. banKey(name))
    if r and not r.del then return r end
    local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(name)
    for _, old in ipairs(Store.List("sndmute")) do
        if not old.del and old.name then
            if ns.SameName(old.name, name) then return old end
            if main and (ns.SameName(old.name, main) or (ns.Alts.Main(old.full or old.name) == main)) then return old end
        end
    end
end
function ns.SoundMuted(name) return O.SoundMuteOf(name) ~= nil end
function O.SoundMute(name, reason)
    Store.Put("sndmute", { id = "sm-" .. banKey(name), name = ns.short(name), full = name, reason = reason or "", ts = ns.now() })
end
function O.SoundUnmute(name)
    for _, r in ipairs(Store.List("sndmute")) do
        if ns.SameName(r.name, name) then Store.Delete("sndmute", r.id) end
    end
end
local warned = {}
local function warn(name, where)
    local b = O.BanOf(name)
    if not b or warned[banKey(name) .. where] then return end
    warned[banKey(name) .. where] = true
    if ns.Sound then ns.Sound.Play("toast") end
    K.Toast((L["Warning: %s is on the ban list"]):format(ns.displayName(name)), (b.reason ~= "" and b.reason or L["no reason given"]) .. "  ·  " .. where, C.red)
end
ns.On("GROUP_ROSTER_UPDATE", function()
    local raid = IsInRaid()
    for i = 1, (GetNumGroupMembers() or 0) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local n = ns.safe(ns.UnitName(u))
            if n then warn(n, L["in your group"]) end
        end
    end
end)
ns.On("PARTY_INVITE_REQUEST", function(name) name = ns.safe(name) if name then warn(name, L["invites you"]) end end)
ns.On("TRADE_SHOW", function() local n = ns.safe(ns.UnitName("NPC")) if n then warn(n, L["Trade"]) end end)
local function banLine(tt, unit)
    if not unit or not UnitIsPlayer(unit) then return end
    local b = O.BanOf(ns.safe(ns.UnitName(unit)))
    if b then tt:AddLine("|cffff5a4a" .. L["Oasis ban list"] .. ":|r " .. (b.reason ~= "" and b.reason or L["no reason given"]), 1, 0.35, 0.3, true) end
end
-- new clients: TooltipDataProcessor; old: OnTooltipSetUnit (only if the script exists)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip then return end
        local ok, e = pcall(function() local _, unit = tt:GetUnit() banLine(tt, unit) end)
        if not ok then ns.debug("Bann-Tooltip", e) end
    end)
elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(function() local _, unit = tt:GetUnit() banLine(tt, unit) end) end)
end

------------------------------------------------------------------------
-- Applicants and trial
------------------------------------------------------------------------
O.STATUS = { { "app", "Applicants", C.blue }, { "trial", "Trial", C.amber }, { "member", "Accepted", C.mint }, { "no", "Declined", C.red } }
function O.Recruits()
    local list = Store.List("recruits")
    local order = { app = 1, trial = 2, member = 3, no = 4 }
    table.sort(list, function(a, b)
        if order[a.st or "app"] ~= order[b.st or "app"] then return order[a.st or "app"] < order[b.st or "app"] end
        return (a.ts or 0) > (b.ts or 0)
    end)
    return list
end
function O.SaveRecruit(rec)
    rec.id = rec.id or ("rec-" .. banKey(rec.name))
    rec.ts = rec.ts or ns.now()
    Store.Put("recruits", rec)
end
function O.TrialLeft(r)
    if r.st ~= "trial" or not r.trial then return nil end
    local days = (ns.db.settings.trialDays or 14)
    return math.max(0, r.trial + days * 86400 - ns.now())
end

------------------------------------------------------------------------
-- Export: snapshot in OasisDB.export (WoW writes it to disk on logout / /reload).
-- Tools/oasis_export.py reads the file and turns it into JSON / sends it to a web interface.
------------------------------------------------------------------------
-- Export only when wanted: explicitly enabled, otherwise default = on for guild leadership/developers,
-- off for everyone else (performance 0.5.482: was on for everyone - 145 KB of duplicate data in every saved file)
function O.ExportWanted()
    -- 0.5.926: export for everyone. Whoever set the toggle gets exactly that. Without own choice: in the public
    -- version OFF (don't store duplicates nobody uses), with guild module on for leadership/developers as before.
    local s = ns.db and ns.db.settings and ns.db.settings.webExport
    if s ~= nil then return s ~= false end
    if not ns.GuildPack then return false end
    if ns.IsDev and ns.IsDev() then return true end
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end
function O.Snapshot()
    if not ns.db then return end
    if not O.ExportWanted() then ns.db.export = nil return end
    local roster = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        local pr = ns.db.members[m.name]
        local rate = O.Attendance(m.name)
        roster[#roster + 1] = {
            name = m.name, level = m.level, class = m.class, rank = m.rank, online = m.online and true or false,
            offDays = m.offDays and math.floor(m.offDays * 10) / 10 or nil, zone = m.zone,
            ilvl = pr and tonumber(pr.ilvl) or nil, xp = pr and tonumber(pr.xp) or nil, profs = pr and pr.profs or nil,
            main = mainOf(m.name), oasis = pr ~= nil, attendance = rate and math.floor(rate * 100) or nil,
        }
    end
    local function list(coll, fields)
        local out = {}
        for _, r in ipairs(Store.List(coll)) do
            local e = {}
            for _, f in ipairs(fields) do e[f] = r[f] end
            out[#out + 1] = e
        end
        return out
    end
    -- real officer rank (not test mode /oa testleitung)
    local realOfficer = C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
    ns.db.export = {
        v = 1, ts = ns.now(), by = ns.me(), guild = ns.Admin and ns.Admin.GuildName() or (GetGuildInfo("player")),
        roster = roster,
        attendance = list("attend", { "d", "inst", "n", "b", "last" }),
        loot = list("loot", { "item", "who", "ts", "boss", "inst", "link" }),
        -- guild leadership data only when an officer exports
        -- 0.5.617 privacy: log, ban list and applicants never go to the website
        events = list("events", { "id", "title", "ts", "kind" }),
        signups = list("signups", { "id", "status", "role", "who" }),
    }
    if ns.Export then ns.Export.Merge(ns.db.export) end
    return ns.db.export
end
-- WoW only writes the saved file on logout / /reload -> the snapshot is enough then (before every 10 min)
ns.Listen("LOGIN", function()
    ns.After(30, function() if not O.ExportWanted() then ns.db.export = nil end end)
end)
ns.On("PLAYER_LOGOUT", function() pcall(O.Snapshot) end)


------------------------------------------------------------------------
-- Trial reminder: 2 days before and when it has expired (guild leadership only, once per day per person)
------------------------------------------------------------------------
local function trialCheck()
    if not (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) then return end
    ns.db.trialReminded = ns.db.trialReminded or {}
    local day = date("%Y-%m-%d")
    for _, r in ipairs(O.Recruits()) do
        local left = O.TrialLeft(r)
        if left then
            local key = r.id .. "@" .. day
            if not ns.db.trialReminded[key] and (left <= 0 or left <= 2 * 86400) then
                ns.db.trialReminded[key] = true
                local title = left <= 0 and (L["Trial over: %s"]):format(r.name or "?") or (L["Trial ends soon: %s"]):format(r.name or "?")
                local sub = left <= 0 and L["Decide now: accept or not"] or (L["%d days left"]):format(math.ceil(left / 86400))
                K.Toast(title, sub .. ((r.pate and r.pate ~= "") and ("  ·  " .. L["Mentor"] .. ": " .. ns.displayName(r.pate)) or ""), C.amber, function()
                    ns.db.settings.officerTab = "recruits"
                    if ns.Admin and ns.Admin.OpenOfficer then ns.Admin.OpenOfficer("members", "recruits") else ns.ShowPage("admin") end
                end)
            end
        end
    end
    -- clean up old markers
    for k in pairs(ns.db.trialReminded) do if not k:find(day, 1, true) then ns.db.trialReminded[k] = nil end end
end
ns.Listen("LOGIN", function()
    ns.After(25, function() pcall(trialCheck) end)
    ns.Every(1800, function() pcall(trialCheck) end)
end)
end)

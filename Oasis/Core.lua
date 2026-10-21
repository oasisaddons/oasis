-- Oasis guild hub - core: database, events, helper functions
local ADDON, ns = ...
local L = ns.L
Oasis = ns
ns.version = "0.6.627"
ns.versionDate = "21.10.2026"
ns.SUPPORT_URL = ""   -- Link for "Copy report" (e.g. Discord invite); empty = text only
ns.WAGO_ID = ""       -- Wago project ID for Wago Analytics (empty = off)   -- Version date: update with EVERY new version (update notice in guild chat)
ns.MEDIA = "Interface\\AddOns\\Oasis\\Media\\"

------------------------------------------------------------------------
-- Secret values (Midnight lockdown): anything secret becomes nil
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
function ns.safe(v)
    if v == nil then return nil end
    if issecret(v) then return nil end
    return v
end
-- defuse several return values at once
function ns.safeAll(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = ns.safe((select(i, ...))) end
    return unpack(t, 1, n)
end

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------
-- Color gradient over a short ASCII text (one color code per letter); from/to = { r, g, b } in 0..255
function ns.GradientText(text, from, to)
    local n, out = #text, {}
    for i = 1, n do
        local t = n > 1 and (i - 1) / (n - 1) or 0
        out[i] = ("|cff%02x%02x%02x%s"):format(
            math.floor(from[1] + (to[1] - from[1]) * t + 0.5), math.floor(from[2] + (to[2] - from[2]) * t + 0.5),
            math.floor(from[3] + (to[3] - from[3]) * t + 0.5), text:sub(i, i))
    end
    return table.concat(out) .. "|r"
end
-- Name in chat: Oasis red to warm orange, preceded by a thin bar instead of square brackets
ns.BRAND = ns.GradientText("Oasis", { 255, 40, 20 }, { 255, 170, 70 })
local PREFIX = "|cffff2814|||r " .. ns.BRAND   -- "||" = one visible bar, then |r (previously a bar was missing: chat showed "|r")
function ns.print(...)
    print(PREFIX, ...)
end
function ns.debug(...)
    if ns.db and ns.db.settings.debug then
        print(L["|cffff3fbf[Oasis-Debug]|r"], ...)
    end
end
local errSeen = {}
-- Record the error location (0.5.505): pcall loses the call stack, xpcall with this handler keeps it
-- -> error reports show the real code line instead of just "Core.lua (Timer)".
local function errTrace(e)
    ns.lastErrStack = debugstack and debugstack(2, 10, 0) or nil
    ns.lastErrAt = GetTime and GetTime() or 0
    return e
end
ns.errTrace = errTrace
function ns.err(where, msg)
    local key = tostring(where) .. tostring(msg)
    if errSeen[key] then return end
    errSeen[key] = true
    print(L["|cffff5060[Oasis error]|r "] .. tostring(where) .. ": " .. tostring(msg))
end

------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------
-- While loading, WoW sometimes returns "Unbekannt"/"Unknown" instead of the real name -> never store it
local function validName(n)
    return type(n) == "string" and n ~= "" and n ~= UNKNOWNOBJECT and n ~= UNKNOWN and n ~= "Unknown" and n ~= "Unknown"
end
ns.validName = validName

local realmCache
local function myRealm()
    if realmCache then return realmCache end
    local r = ns.safe(GetNormalizedRealmName and GetNormalizedRealmName())
    if not r or r == "" then
        r = ns.safe(GetRealmName())
        r = r and r:gsub("[%s%-]", "") or nil
    end
    if r and r ~= "" then realmCache = r end
    return r or "Realm"
end
function ns.fullName(name)
    name = ns.safe(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. myRealm()
end
-- Forever: UnitName returns first name AND last name, not name and realm.
-- Addon's own adapter: do not replace Blizzard globals.
function ns.UnitName(unit)
    local name, second = UnitName(unit)
    name, second = ns.safe(name), ns.safe(second)
    if not name then return nil end
    local regional = RegionalUniqueNamesEnabled and ns.safe(RegionalUniqueNamesEnabled())
    if regional then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        if second and second ~= "" and not name:find(sep, 1, true) then name = name .. sep .. second end
        return name
    end
    return name, second
end
function ns.UnitFullName(unit)
    local name, realm = ns.UnitName(unit)
    if not name then return nil end
    return name, realm or myRealm()
end
-- Only for FontString:SetText: the client may display secret names directly.
function ns.UnitDisplayName(unit)
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local ok, name = pcall(NameUtil.FormatUnitNameForDisplay, unit, true)
        if ok then return name end
    end
    local name = ns.UnitName(unit)
    if name then return name end
    return UnitName(unit)
end
-- Resolve old first-name keys only via unambiguously linked roster entries.
function ns.ResolveName(name, fromGuild)
    local full = ns.fullName(name)
    if not full then return nil end
    local R = ns.Radar
    local member = R and R.byName and R.byName[full]
    if not member and R and R.byNameLower then member = R.byNameLower[full:lower()] end
    -- Forever (regionally unique names): "First Last" is unique across the whole region, the realm suffix is not.
    -- Every client appends ITS realm to realmless names - the same character arrives as "...-ClassicBetaPvE" and
    -- "...-ClassicBetaPvE2" (group messages, profiles, senders). If the realm doesn't match, resolve by name alone
    -- - but only if exactly ONE guild member has that name.
    if not member and R and R.roster and RegionalUniqueNamesEnabled and ns.safe(RegionalUniqueNamesEnabled()) then
        local idx = ns._baseIdx
        if not idx or idx.src ~= R.roster or idx.n ~= #R.roster then
            idx = { src = R.roster, n = #R.roster, map = {}, first = {} }
            for _, m in ipairs(R.roster) do
                local base = type(m.name) == "string" and (m.name:match("^(.*)%-[^%-]+$") or m.name):lower()
                if base and base ~= "" then
                    if idx.map[base] == nil then idx.map[base] = m else idx.map[base] = false end   -- false = ambiguous
                    local first = base:match("^(%S+)%s")
                    if first then
                        if idx.first[first] == nil then idx.first[first] = m else idx.first[first] = false end
                    end
                end
            end
            ns._baseIdx = idx
        end
        local base = (full:match("^(.*)%-[^%-]+$") or full):lower()
        local hit = idx.map[base]
        -- Addon messages sometimes carry only the FIRST NAME ("Mira-ClassicBetaPvE2"). That is not regionally unique,
        -- so only for senders from the guild channel (definitely a guild member) and only with exactly one match.
        if not hit and fromGuild and not base:find("%s") then hit = idx.first[base] end
        if hit then member = hit end
    end
    return member and member.name or full
end
function ns.NameKey(name)
    return (ns.ResolveName(name) or ""):lower()
end
function ns.SameName(a, b)
    a, b = ns.safe(a), ns.safe(b)
    return type(a) == "string" and type(b) == "string" and a ~= "" and b ~= ""
        and ns.NameKey(a) == ns.NameKey(b)
end

-- 0.5.774: C_GuildInfo.GuildRoster() is protected in the Forever client ("Oasis has been blocked ... UNKNOWN()", trace: GuildRoster right before).
-- The guild list arrives from the server via GUILD_ROSTER_UPDATE anyway; the call now only runs with settings.rosterCall = true.
function ns.RequestGuildRoster()
    local s = ns.db and ns.db.settings
    -- 0.5.788: ON by default again - the block demonstrably came from the Discord queries, not from here. Without the call
    -- the guild list stalls (people coming online are noticed late). Turn off only for testing: rosterCall = false
    if s and s.rosterCall == false then return end
    -- 0.6.537: not in combat (Blocked UNKNOWN() for Daito 0.6.518 came right after GuildRoster, UNIT_AURA before) - after combat GUILD_ROSTER_UPDATE is enough
    if InCombatLockdown and InCombatLockdown() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        if ns.Trace then ns.Trace("C_GuildInfo.GuildRoster") end
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end
function ns.me()
    if not ns._me then
        local n = ns.UnitName("player")
        if validName(n) and myRealm() ~= "Realm" then ns._me = ns.fullName(n) end
    end
    return ns._me
end
function ns.short(name)
    name = ns.safe(name)
    if type(name) ~= "string" then return "?" end
    return (name:gsub("%-.*$", ""))
end
-- Full character name for whispering and inviting (realm only internally).
function ns.ChatName(name)
    if not name then return "?" end
    return ns.short(ns.ResolveName(name))
end
-- Whispering: WoW does not understand "/w First Last" (takes only the first word) ->
-- WoW's own function sets the full name as target
function ns.Whisper(name, text)
    if not name then return end
    if ns.inCombat() then ns.print(L["Not possible in combat - try again shortly."]) return end
    local n = ns.ChatName(name)
    if ChatFrame_SendTell then
        ns.Trace("ChatFrame_SendTell")
        ChatFrame_SendTell(n)
        if text and text ~= "" then
            local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
            if eb then eb:Insert(text) end
        end
    else
        ns.OpenChat("/w " .. n .. " " .. (text or ""))
    end
end
-- ns._meRoster: own name as the guild list has it (Forever: "First Last-Realm")
function ns.isMe(name)
    return ns.SameName(name, ns.me()) or ns.SameName(name, ns._meRoster)
end

------------------------------------------------------------------------
-- Time
------------------------------------------------------------------------
function ns.now()
    return GetServerTime and GetServerTime() or time()
end
function ns.ago(ts)
    if not ts then return "-" end
    local d = ns.now() - ts
    if d < 0 then d = 0 end
    if d < 60 then return L["just now"] end
    if d < 3600 then return (L["%d min ago"]):format(d / 60) end
    if d < 86400 then return (L["%dh ago"]):format(d / 3600) end
    if d < 86400 * 14 then return (L["%d d ago"]):format(d / 86400) end
    return date(ns.L["%m/%d/%y"], ts)
end
function ns.fmtDate(ts) return ts and date(ns.L["%m/%d %H:%M"], ts) or "-" end
-- date() always returns weekdays in English -> translate ourselves
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
function ns.weekday(ts, short)
    local w = ns.L[WEEKDAYS[tonumber(date("%w", ts)) + 1]]
    if not short then return w end
    -- short: the first 2 characters (UTF-8 safe); Chinese "星期二" -> "周二", Korean "화요일" -> "화"
    local chars = {}
    for ch in w:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    if chars[1] and #chars[1] >= 3 then
        if chars[1] == "星" and #chars >= 3 then return "周" .. chars[#chars] end
        return chars[1]
    end
    return table.concat(chars, "", 1, math.min(2, #chars))
end
function ns.fmtWhen(ts) return ns.weekday(ts) .. ", " .. date(ns.L["%m/%d at %H:%M"], ts) end
-- Zone name in the own language (from the map ID), otherwise the stored text
function ns.zoneName(mapID, fallback)
    if mapID and mapID ~= 0 and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    return fallback or ""
end
function ns.newId(tag)
    return (tag or "x") .. "-" .. ns.short(ns.me() or "?") .. "-" .. ns.now() .. "-" .. math.random(1000, 9999)
end

------------------------------------------------------------------------
-- Class colors
------------------------------------------------------------------------
function ns.classColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.85, 0.82, 0.95
end
function ns.classHex(classFile)
    local r, g, b = ns.classColor(classFile)
    return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end
-- Role/group log for tracing (in SavedVariables after /reload: OasisDB.roleLog)
function ns.RoleLog(...)
    if not ns.db then return end
    ns.db.roleLog = ns.db.roleLog or {}
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local l = ns.db.roleLog
    l[#l + 1] = ("%s %.2f %s"):format(date("%H:%M:%S"), GetTime() % 1000, table.concat(parts, " "))
    while #l > 300 do table.remove(l, 1) end
end
-- Display name: WoW Forever uses double names ("Mira Stern"). Always use this for DISPLAY,
-- for comparisons/keys/whispering/inviting keep using ns.short or ns.isMe/Radar.byName.
function ns.displayName(name)
    if not name or name == "" then return name or "?" end
    local full = ns.ResolveName(name)
    return ns.short(full)
end
------------------------------------------------------------------------
-- Guild options: settings the guild leadership sets for the whole guild.
-- Modules register them (when the file loads), the guild leadership shows them in the module's gear menu.
-- def = { page = "chat", key = "chPin", default = true, kind = "bool"|"num"|"choice", label = "Text", desc = "Text",
--         min =, max =, step =, fmt = function(v) end, choices = { { key = ..., text = "..." }, ... }, lead = true (guild master only) }
-- Read: ns.GuildOpt("chPin") -> stored guild value or default (= previous behavior)
------------------------------------------------------------------------
ns.GuildOpts, ns.GuildOptsByKey = {}, {}
function ns.GuildOption(def)
    if not def or not def.key or ns.GuildOptsByKey[def.key] then return end
    def.kind = def.kind or (type(def.default) == "boolean" and "bool") or (type(def.default) == "number" and "num") or "choice"
    ns.GuildOpts[#ns.GuildOpts + 1] = def
    ns.GuildOptsByKey[def.key] = def
    if ns.Admin and ns.Admin.RegisterOptionDefault then ns.Admin.RegisterOptionDefault(def) end
end
function ns.GuildOpt(key)
    local def = ns.GuildOptsByKey[key]
    local v
    if ns.Admin and ns.Admin.Cfg then
        local ok, cfg = pcall(ns.Admin.Cfg)
        if ok and cfg then v = cfg[key] end
    end
    if v == nil and def then v = def.default end
    return v
end
function ns.colorName(name, classFile)
    -- WoW Forever: always show the full name ("Mira Stern" instead of "Mira")
    local full = ns.ResolveName(name)
    return L["|c"] .. ns.classHex(classFile) .. ns.short(full) .. "|r"
end

------------------------------------------------------------------------
-- Combat / instance
------------------------------------------------------------------------
function ns.inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (ns.safe(UnitAffectingCombat("player")) == true)
end
function ns.inInstance()
    local inInst = IsInInstance()
    return inInst and true or false
end
-- Developer mode: off by default; Core/Diagnostics/Dev.lua replaces ns.IsDev and registers /oa entwickler <code>
-- (only a hash of the code is in the source). Always call as ns.IsDev(), never cache it.
function ns.IsDev() return false end
-- 0.6.627: the artwork (backgrounds, deathroll, Guildotchi, start tiles) ships with Oasis (Media\art). Former guild
-- module checks for pictures ask ns.ART; ns.GuildPack stays nil (behaviour of the public version).
ns.ART = true
-- 0.6.275: own position on the map (mapID, x, y 0..1) - formerly Camp.MyPosition, used by map, camp, etc.
function ns.MyMapPosition()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = ns.safe(x), ns.safe(y)
    if not x or not y then return nil end
    return mapID, x, y
end
-- 0.6.272: optional modules register here (previously in ModuleLoader.lua - module files had to come after it
-- in the toc). ModuleLoader.LoadAll runs only the enabled ones at startup; after that ns.ModuleFile accepts nothing.
ns.moduleFiles = {}
ns.moduleOrder = {}   -- 0.6.285: toc order (modules that build on others load afterwards)
-- chronicle entry "joined the guild" (German template from Oasis before 0.6.627 or English)
function ns.IsJoinTk(tk) return type(tk) == "string" and (tk:find("^tritt") or tk:find("^joined the guild")) and true or false end
function ns.ModuleFile(key, fn)
    local files = ns.moduleFiles
    if not files then return end
    if not files[key] then files[key] = {} table.insert(ns.moduleOrder, key) end
    table.insert(files[key], fn)
end
-- 0.6.254: does another addon draw the chat itself (EllesmereUI chat: Blizzard frames run invisibly alongside and
-- are mirrored)? Then Oasis does not modify the Blizzard chat frames - rewriting/removing lines,
-- hiding, inserted history and highlighting messed up its frames (only 2-3 lines, chat
-- drifted away upwards).
function ns.ForeignChat()
    local E = rawget(_G, "EllesmereUI")
    if type(E) == "table" and type(E._chatCFD) == "function" then return true end
    -- Detect already while loading, before the foreign frame mapping is ready.
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    -- 0.6.537: Chattynator and Prat also draw the chat themselves
    if not loaded then return false end
    for _, n in ipairs({ "EllesmereUIChat", "Chattynator", "Prat-3.0" }) do if loaded(n) then return true end end
    return false
end
-- Oasis minimap icons (0.5.960): the center stays free so the own arrow is visible, and the icons sit in the
-- minimap's own layer (previously one layer higher - then they covered the border and compass).
-- px/py = distance from the minimap center in screen pixels.
function ns.MiniPinVisible(px, py)
    local s = ns.db and ns.db.settings
    if s and s.miniCenterClear == false then return true end
    return (px or 0) * (px or 0) + (py or 0) * (py or 0) >= 20 * 20   -- 0.6.410: larger, player arrow stays free
end
function ns.MiniPinLayer(p, add)
    if not (p and Minimap) then return end
    pcall(p.SetFrameStrata, p, Minimap:GetFrameStrata() or "LOW")
    -- 0.6.144: one layer lower (at most +1) - border, compass needle and player arrow stay on top
    pcall(p.SetFrameLevel, p, (Minimap:GetFrameLevel() or 1) + math.min(add or 1, 1))
end
-- External programs (OasisSync, export scripts, import scripts) are not distributed with the public version for now
--. Settings and hints that only make sense with them therefore exist only with the guild module.
-- Oasis-Tools (templates for custom sounds/emojis, export programs) is a separate file in the Oasis Discord,
-- never on CurseForge/Wago/GitHub. That's why Oasis shows the related hints and settings to everyone.
ns.TOOLS_RELEASED = true
function ns.ExternTools() return (ns.GuildPack or ns.TOOLS_RELEASED) and true or false end
-- all sounds/emojis without rank lock (only for me): developer mode or /oa freischalten
function ns.UnlockAll()
    -- 0.5.562: without the guild's rank lock (default) everything is free for everyone - emojis AND sounds
    -- 0.6.435: rank lock always applies (old guild setting "free" is no longer honored)
    -- 0.6.421: developer mode no longer unlocks automatically (to test the lock) - only the own switch
    return (ns.db and ns.db.settings and ns.db.settings.unlockAll == true) or false
end
function ns.isOfficer()
    if ns.db and ns.db.settings.adminTest ~= false and ns.IsDev() then return true end   -- Guild leadership test mode (developers only)
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end
function ns.groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end
function ns.isGroupLead()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
end

------------------------------------------------------------------------
-- Trace: the last Oasis actions (for the error recorder "blocked from an action")
------------------------------------------------------------------------
ns.trail = {}
function ns.Trace(what)
    local t = ns.trail
    t[#t + 1] = { t = GetTime(), w = tostring(what), c = ns.inCombat() }
    if #t > 25 then table.remove(t, 1) end
end

------------------------------------------------------------------------
-- Using chat safely
-- SendChatMessage is protected during chat lockdowns (boss, Mythic+, PvP, "secret" combat phases):
-- a call then triggers "Oasis has been blocked" - pcall doesn't help. So check beforehand.
------------------------------------------------------------------------
function ns.ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        -- Beta sometimes reports this permanently -> only take it seriously when we really are in an instance + combat
        if ok and r == true and ns.inInstance() and ns.inCombat() then return true end
    end
    return false
end
function ns.SendChat(msg, channel, target)
    if type(msg) ~= "string" or msg == "" then return false end
    channel = channel or "GUILD"
    if ns.ChatLocked() then
        ns.debug("Chat gesperrt, nicht gesendet:", channel)
        return false
    end
    ns.Trace("SendChatMessage " .. channel)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return pcall(send, msg, channel, nil, target)
end
-- WoW Forever blocks automatic chat messages (without a click) ("Blocked: UNKNOWN()", 08.10.):
-- instead a notice with the message - clicking it sends (click = input, allowed).
function ns.OfferChat(title, msg, channel, target, color)
    if type(msg) ~= "string" or msg == "" then return end
    local K = ns.K
    local preview = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    -- 0.6.236: truncate at a character boundary (previously in the middle of UTF-8 characters like "–" -> broken characters),
    -- "Click: send" on its own line (otherwise it overlapped the text)
    if #preview > 160 then preview = ns.Utf8Cut(preview, 157) .. "..." end
    -- 0.6.410: message dimmed in quotes, "Click: send" as its own hint at the bottom right
    K.toastHint = "|cffe8b44a" .. L["Click: send"] .. "|r"
    K.Toast(title, "|cffa8a8ae\226\128\158" .. preview .. "\226\128\156|r", color or K.C.accent,
        function() ns.SendChat(msg, channel, target) end)
    K.toastHint = nil   -- in case the notice was muted and not shown
end
-- Open chat input ("/w Name ") - not in combat: that touches the Blizzard edit box
function ns.OpenChat(text)
    if ns.inCombat() then
        ns.print(L["Not possible in combat - try again shortly."])
        return
    end
    ns.Trace("ChatFrame_OpenChat")
    ChatFrame_OpenChat(text)
end

------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------
local QHEX = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff" }
function ns.fixColors(s)
    if type(s) ~= "string" or not s:find("|cn", 1, true) then return s end
    s = s:gsub("|cnIQ(%d):", function(q) return "|c" .. (QHEX[tonumber(q)] or "ffffffff") end)
    return (s:gsub("|cn[%w_]+:", "|cffffffff"))
end
function ns.itemID(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end
-- calls cb(link, name, quality, icon, ilvl, equipLoc) once the item is in the cache
function ns.withItem(idOrLink, cb)
    local id = ns.itemID(idOrLink)
    if not id then return end
    local function done()
        local name, link, quality, ilvl, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(idOrLink)
        if name then cb(link, name, quality, icon, ilvl, equipLoc) return true end
    end
    if done() then return end
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(id)
        item:ContinueOnItemLoad(function() done() end)
    else
        C_Timer.After(1, done)
    end
end

------------------------------------------------------------------------
-- Simple hash (for "did something change?")
------------------------------------------------------------------------
function ns.hash(str)
    local h = 5381
    for i = 1, #str do
        -- stay below 2^31 so %x formats safely even with 32-bit long
        h = (h * 33 + str:byte(i)) % 2147483647
    end
    return ("%08x"):format(h)
end

------------------------------------------------------------------------
-- Sanitize foreign texts (addon messages from other players):
--  * allowed: colors |cAARRGGBB ... |r, links to items/spells/quests/achievements/players (well-formed),
--    icons |T...|t only up to 64 pixels (huge textures covering the screen are shrunk)
--  * everything else (|K, |A, |n, other |H kinds, broken sequences) becomes "||" = visible "|", without effect
--  * length limited (cut UTF-8 safely). Idempotent: sanitizing twice = sanitizing once.
------------------------------------------------------------------------
function ns.Utf8Cut(s, maxLen)
    if type(s) ~= "string" or not maxLen or #s <= maxLen then return s end
    local cut = maxLen
    -- don't cut in the middle of a multibyte character
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end
local LINK_OK = { item = true, spell = true, enchant = true, quest = true, achievement = true, currency = true,
    talent = true, player = true, addon = true }
local function texOk(rest)
    if rest == "" then return true end
    if not rest:match("^[%d:%-%.]*$") then return false end
    local n = 0
    for v in rest:gmatch("[^:]+") do
        n = n + 1
        local x = tonumber(v)
        if not x or (n <= 4 and (x > 64 or x < -64)) then return false end
    end
    return true
end
-- Item links: take the displayed name and color from the real item
-- (otherwise a manipulated client could write "[Thunderfury]" on a gray item)
local itemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function ns.FixItemLinks(t)
    if type(t) ~= "string" or not t:find("|Hitem:", 1, true) then return t end
    return (t:gsub("|c([^|]-)|Hitem:(%d+)([^|]*)|h%[([^|%]]*)%]|h|r", function(col, id, rest, text)
        local name, link = itemInfo(tonumber(id))
        if name and link then
            local realCol = link:match("^|c([^|]-)|H")
            return "|c" .. (realCol or col) .. "|Hitem:" .. id .. rest .. "|h[" .. name .. "]|h|r"
        end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, tonumber(id)) end
        -- not in the cache yet: neutral gray with number instead of an unverified name
        return "|cff9d9d9d|Hitem:" .. id .. rest .. "|h[#" .. id .. "]|h|r"
    end))
end
function ns.CleanText(s, maxLen)
    if type(s) ~= "string" then return s end
    if maxLen then s = ns.Utf8Cut(s, maxLen) end
    if not s:find("|", 1, true) then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local p = s:find("|", i, true)
        if not p then out[#out + 1] = s:sub(i) break end
        if p > i then out[#out + 1] = s:sub(i, p - 1) end
        local c = s:sub(p + 1, p + 1)
        if c == "|" then
            out[#out + 1] = "||"
            i = p + 2
        elseif c == "c" and s:find("^%x%x%x%x%x%x%x%x", p + 2) then
            out[#out + 1] = s:sub(p, p + 9)
            i = p + 10
        elseif c == "r" then
            out[#out + 1] = "|r"
            i = p + 2
        elseif c == "H" then
            local data, text, e = s:match("^|H([^|]*)|h(%[[^|%]]*%])|h()", p)
            local typ = data and data:match("^(%a+):")
            if data and LINK_OK[typ] and #data <= 200 and not data:find("[^%w:%-%._]")
                and (typ ~= "addon" or data:find("^addon:Oasis:")) then
                out[#out + 1] = "|H" .. data .. "|h" .. text .. "|h"
                i = e
            else
                out[#out + 1] = "||"
                i = p + 1
            end
        elseif c == "T" then
            local path, rest, e = s:match("^|T([^:|]+)([^|]*)|t()", p)
            if path and #path <= 200 then
                if not texOk(rest) then rest = ":0" end
                out[#out + 1] = "|T" .. path .. rest .. "|t"
                i = e
            else
                out[#out + 1] = "||"
                i = p + 1
            end
        else
            out[#out + 1] = "||"
            i = p + 1
        end
    end
    -- close open color codes (otherwise a text colors the following display too)
    local open = 0
    for _, part in ipairs(out) do
        if part:sub(1, 2) == "|c" then open = open + 1 elseif part == "|r" and open > 0 then open = open - 1 end
    end
    if open > 0 then out[#out + 1] = string.rep("|r", open) end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Events (WoW) and internal messages
------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
local evHandlers = {}
-- Register unit events only for the units Oasis really needs (otherwise hundreds per second in a raid)
local PLAYER_UNIT_EVENTS = { UNIT_SPELLCAST_SENT = "player", UNIT_SPELLCAST_SUCCEEDED = "player", UNIT_HEALTH = "target" }
function ns.On(event, fn)
    local list = evHandlers[event]
    if not list then
        list = {}
        evHandlers[event] = list
        -- unknown events throw errors in the beta -> catch them
        -- Register spell events only for the own character (all Oasis handlers check unit == "player" anyway;
-- otherwise they fire in a raid for every unit, hundreds of times per second) - performance 0.5.482
        local ok
        if PLAYER_UNIT_EVENTS[event] and evFrame.RegisterUnitEvent then ok = pcall(evFrame.RegisterUnitEvent, evFrame, event, PLAYER_UNIT_EVENTS[event])
        else ok = pcall(evFrame.RegisterEvent, evFrame, event) end
        if not ok then ns.debug(L["Event not available: "] .. event) end
    end
    list[#list + 1] = fn
    if not ns.handlerSrc then ns.handlerSrc = setmetatable({}, { __mode = "k" }) end
    ns.handlerSrc[fn] = ns.Caller and ns.Caller() or nil
end
-- Error diagnosis (0.5.504): the last events Oasis processed (ring buffer, almost free).
-- If WoW blocks Oasis, the error report automatically shows which event ran just before.
local EV_N, evRingE, evRingT, evRingI = 24, {}, {}, 0
function ns.LastEvents(maxAge)
    local now, out, seen = GetTime(), {}, {}
    for k = 0, EV_N - 1 do
        local i = (evRingI - k - 1) % EV_N + 1
        local e, t = evRingE[i], evRingT[i]
        if not e or now - t > (maxAge or 3) then break end
        if not seen[e] and not e:find("^ADDON_ACTION") then
            seen[e] = true
            out[#out + 1] = ("%s (vor %.1fs)"):format(e, now - t)
            if #out >= 8 then break end
        end
    end
    return table.concat(out, ", ")
end
evFrame:SetScript("OnEvent", function(_, event, ...)
    -- before startup (player name still unknown) only process loading/login
    if not ns.loggedIn and event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then return end
    local list = evHandlers[event]
    if not list then return end
    evRingI = evRingI % EV_N + 1
    evRingE[evRingI], evRingT[evRingI] = event, GetTime()
    if ns.prof then
        for i = 1, #list do
            local t0 = debugprofilestop()
            local ok, e = xpcall(list[i], errTrace, ...)
            ns.prof.add(list[i], event, debugprofilestop() - t0)
            if not ok then ns.err(event, e) end
        end
        return
    end
    for i = 1, #list do
        local ok, e = xpcall(list[i], errTrace, ...)
        if not ok then ns.err(event, e) end
    end
end)

local listeners = {}
function ns.Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do
        local ok, e = xpcall(list[i], errTrace, ...)
        if not ok then ns.err(msg, e) end
    end
end

-- Timer with error protection
-- Caller line for performance measurement (WoW doesn't give addons the source line of a function)
local function caller()
    local st = debugstack and debugstack(3, 1, 0) or ""
    local f, l = st:match("([%w_]+[/\\][%w_]+%.lua)[\"%]]*:(%d+)")
    if not f then f, l = st:match("([%w_]+%.lua)[\"%]]*:(%d+)") end
    return f and (f:gsub("\\", "/") .. ":" .. l) or nil
end
ns.Caller = caller
local function timed(fn, what)
    if not ns.prof then return xpcall(fn, errTrace) end
    local t0 = debugprofilestop()
    local ok, e = xpcall(fn, errTrace)
    ns.prof.add(fn, what, debugprofilestop() - t0)
    return ok, e
end
function ns.After(sec, fn)
    local lbl = ns.prof and caller() or nil
    sec = tonumber(sec) or 0
    if sec ~= sec or sec < 0 then sec = 0 end   -- 0.5.660: C_Timer.After lehnt negative Zeiten ab (Fehlerbericht Comm GCREQ)
    C_Timer.After(sec, function()
        local ok, e = timed(fn, lbl and ("Timer " .. lbl) or "Timer")
        if not ok then ns.err("Timer", e) end
    end)
end
function ns.Every(sec, fn)
    local lbl = "Ticker " .. (caller() or "?")
    return C_Timer.NewTicker(sec, function()
        local ok, e = timed(fn, lbl)
        if not ok then ns.err("Ticker", e) end
    end)
end
-- Performance measurement (0.5.528): /oa leistung -> 60 s of CPU time per Oasis function (events, timers)
do
    local src = setmetatable({}, { __mode = "k" })
    local function where(fn)
        if not fn then return "?" end
        local w = src[fn]
        if w then return w end
        local info = debug and debug.getinfo and debug.getinfo(fn, "S")
        w = info and ((info.short_src or "?"):gsub("^.-AddOns[/\\]Oasis[/\\]", ""):gsub("^%[string \"", ""):gsub("\"%]$", "") .. ":" .. (info.linedefined or 0)) or "?"
        src[fn] = w
        return w
    end
    function ns.PerfStart(sec)
        sec = sec or 60
        local P = { t0 = debugprofilestop(), rows = {} }
        function P.add(fn, what, ms)
            local w = where(fn)
            if w == "?" and ns.handlerSrc and ns.handlerSrc[fn] then w = ns.handlerSrc[fn] end
            local k = (w ~= "?" and (w .. "  ") or "") .. tostring(what)
            local r = P.rows[k]
            if not r then r = { k = k, ms = 0, n = 0, max = 0 } P.rows[k] = r end
            r.ms, r.n = r.ms + ms, r.n + 1
            if ms > r.max then r.max = ms end
        end
        ns.prof = P
        -- 0.5.625: count frame times (stutter = frame takes longer than 33 or 50 ms)
        P.frames, P.h33, P.h50, P.maxEl, P.sumEl = 0, 0, 0, 0, 0
        P.fr = P.fr or CreateFrame("Frame")
        P.fr:SetScript("OnUpdate", function(_, el)
            if ns.prof ~= P then return end
            P.frames, P.sumEl = P.frames + 1, P.sumEl + el
            if el > 0.033 then P.h33 = P.h33 + 1 end
            if el > 0.05 then P.h50 = P.h50 + 1 end
            if el > P.maxEl then P.maxEl = el end
        end)
        local m0
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
            pcall(function() m0 = C_AddOnProfiler.GetAddOnMetric(ADDON, Enum.AddOnProfilerMetric.SessionAverageTime) end)
        end
        ns.print(("Leistung: messe %d Sekunden ... (einfach normal weiterspielen)"):format(sec))
        C_Timer.After(sec, function() ns.PerfStop(m0) end)
    end
    function ns.PerfStop()
        local P = ns.prof
        if not P then return end
        ns.prof = nil
        local dur = (debugprofilestop() - P.t0) / 1000
        local list, total = {}, 0
        for _, r in pairs(P.rows) do list[#list + 1] = r total = total + r.ms end
        table.sort(list, function(a, b) return a.ms > b.ms end)
        local out = { ("Oasis-Leistung: %.0f s gemessen, %.1f ms Rechenzeit in Ereignissen/Timern/Listen (%.2f ms pro Sekunde)"):format(dur, total, total / math.max(1, dur)) }
        if P.fr then P.fr:SetScript("OnUpdate", nil) end
        if (P.frames or 0) > 0 then
            out[#out + 1] = ("Bilder: %.0f FPS im Schnitt, Ruckler: %d Bilder ueber 33 ms, %d ueber 50 ms, laengstes %.0f ms"):format(
                P.frames / math.max(0.001, P.sumEl), P.h33, P.h50, P.maxEl * 1000)
        end
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
            local M = Enum.AddOnProfilerMetric
            local function m(k) local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON, M[k]) return ok and v or nil end
            local ra, pk = m("RecentAverageTime"), m("PeakTime")
            if ra or pk then out[#out + 1] = ("Blizzard-Messung (alles inkl. Fenster): zuletzt %.3f ms je Bild, Spitze %.1f ms"):format(ra or 0, pk or 0) end
        end
        for i = 1, math.min(15, #list) do
            local r = list[i]
            out[#out + 1] = ("%2d. %6.1f ms  %5dx  max %5.1f  %s"):format(i, r.ms, r.n, r.max, r.k)
        end
        ns.db.perfReport = { ts = ns.now(), v = ns.version, lines = out }
        for i = 1, math.min(8, #out) do ns.print(out[i]) end
        if ns.Bugs and ns.Bugs.ShowCopy then pcall(ns.Bugs.ShowCopy, table.concat(out, "\n")) end
    end
end
-- Bundle repeated calls: fn runs once, "sec" after the first call (performance 0.5.482:
-- during login sync hundreds of records arrive, counters/pages were previously recalculated for each)
local debounced = {}
function ns.Debounce(key, sec, fn)
    if debounced[key] then return end
    -- 0.5.876: catch negative/invalid times. Otherwise C_Timer.After throws an error - and because the flag
    -- was already set, this bundle never ran again until the next /reload.
    sec = tonumber(sec) or 0
    if sec ~= sec or sec < 0 then sec = 0 end
    debounced[key] = true
    C_Timer.After(sec, function()
        debounced[key] = nil
        local ok, e = timed(fn, "Buendel " .. tostring(key))
        if not ok then ns.err(key, e) end
    end)
end

------------------------------------------------------------------------
-- Database
------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    shareMap = false,       -- 0.5.617 privacy: off by default
    shareRep = false,
    wantAlarm = true,       -- Wish list alert (market)
    xpFloat = true,         -- Oasis XP as +XP on screen
    priceAnswer = true,     -- answer 'pc [Item]' in guild chat
    shareTrade = false,     -- share trade balance for the leaderboard (optional)
    mapNames = true,
    minimapDots = true,
    inactiveDays = 30,
    deathToasts = true,
    deathPins = true,
    mapInterval = 8,
    toasts = true,
    announceMilestones = false,
    minimap = true,
    minimapAngle = 215,
    scale = 1.0,
    lootMinQuality = 3,
    radarRange = 300,
    debug = false,
    -- Notices & sound
    toastDur = 7,
    toastHoldCombat = false,
    sound = true,
    soundVol = 14,   -- 0.5.976: twice as loud as before (70 %)
    soundQuietCombat = true,
    soundEvents = {},
    music = "off",
    musicTrack = "orc",
    -- Appearance
    uiFont = "inter",     -- Default font (0.5.379 user decision)
    accent = "",          -- own accent color (empty = same as the guild)
    headFont = "friz",
    logoAnim = true,
    chatEmoji = true,     -- show shortcodes in chat as emoji
    drSilent = true,      -- roll Deathroll quietly among Oasis users (no /roll in chat)
    emojiButton = true,   -- emoji button in the chat edit box
    emojiHotkey = true,   -- Alt+Space in chat opens the emoji picker
    hiddenPages = {},
    lang = "auto",
}

-- 0.5.727: beginner settings - calm, few pages, nothing blinks. Applies to NEW installs (empty settings)
-- and via /oa einsteiger to existing ones. Everything stays changeable in the settings; hidden pages under Sections.
local BEGINNER = {
    soundVol = 10, toastDur = 6, toastHoldCombat = true,
    dashStill = true, dashTicker = false, dashHero = false, hideMidasAd = true, calmStart = true,
    xpFloat = false, priceAnswer = false, announceMilestones = false, lfgAuto = false, greetOn = false,
}
local BEGINNER_HIDDEN = { "raidlead", "loot", "lootrules", "softres", "wipes", "tactics", "raidboard", "raidcheck", "lockouts",
    "buffs", "repplan", "gearmatch", "scout", "fight", "rares", "sammlung", "goals" }
function ns.ApplyBeginner(st)
    for k, v in pairs(BEGINNER) do st[k] = v end
    st.hiddenPages = st.hiddenPages or {}
    for _, k in ipairs(BEGINNER_HIDDEN) do st.hiddenPages[k] = true end
end

local function applyDefaults(t, d)
    for k, v in pairs(d) do
        if t[k] == nil then
            if type(v) == "table" then
                t[k] = {}
                applyDefaults(t[k], v)
            else
                t[k] = v
            end
        end
    end
end

local function initDB()
    OasisDB = OasisDB or {}
    local db = OasisDB
    db.settings = db.settings or {}
    local fresh = next(db.settings) == nil
    ns.DEFAULT_SETTINGS = DEFAULT_SETTINGS   -- for "Reset page" in the settings
    applyDefaults(db.settings, DEFAULT_SETTINGS)
    -- 0.5.740: sharing quests should just work - turn off declining shared quests once (default was never on; whoever deliberately
    -- turns it back on keeps it). Group, raid and guild are never declined anyway.
    if db.settings.shareQuest740 == nil then
        db.settings.shareQuest740 = true
        db.settings.cfBlockShared = nil
    end
    -- 0.5.976: Oasis sounds twice as loud overall. Existing installs: double the stored volume (and that of the
    -- online sound) once, at most up to 200 % (level 40). New installs already have the new default.
    if db.settings.soundVolDoubled == nil then
        db.settings.soundVolDoubled = true
        if not fresh then
            for _, k in ipairs({ "soundVol", "soundEntranceVol" }) do
                local v = tonumber(db.settings[k])
                if v and v > 0 then db.settings[k] = math.min(40, math.floor(v * 2)) end
            end
        end
    end
    if db.settings.beginner727 == nil then
        db.settings.beginner727 = true
        if fresh then ns.ApplyBeginner(db.settings) end   -- only new installs; existing ones keep their choice
    end
    -- 0.5.346: new default design "Glas 2026" + font Inter (once; whoever deliberately chose something else keeps it)
    local st = db.settings
    if not st.glass26 then
        st.glass26 = true
        if st.theme == nil or st.theme == "standard" or st.theme == "modern" or st.theme == "classic" then st.theme = "glass" end   -- 0.6.265: Classic, Modern, WoW Classic removed
        if st.uiFont == nil or st.uiFont == "arialn" then st.uiFont = "inter" end
    end
    -- 0.5.379: default font Inter; revert the Arial Narrow reset from 0.5.378
    if not st.inter379 then
        st.inter379 = true
        if st.uiFont == nil or st.uiFont == "arialn" then st.uiFont = "inter" end
    end
    db.members = db.members or {}      -- Member profiles (shared via addon)
    db.recipes = db.recipes or {}      -- [name] = { hash, u, profs = { [prof] = { [id] = name } } }
    db.legacy = db.legacy or {}        -- [name] = { hash, u, done = { [id] = true } }
    db.store = db.store or {}          -- replicated collections (orders, events, chronicle ...)
    db.chars = db.chars or {}
    db.meta = db.meta or { lastSync = 0 }
    ns.db = db
    local me = ns.me()
    if me then
        db.chars[me] = db.chars[me] or {}
        local c = db.chars[me]
        c.milestones = c.milestones or {}
        c.recipes = c.recipes or {}
        ns.char = c
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    initDB()
    -- personal language and fonts before building the UI
    local s = ns.db.settings
    if s.lang and ns.langByKey[s.lang] then ns.lang = s.lang end
    if ns.PrepareLang then pcall(ns.PrepareLang) end
    -- 0.5.568: load enabled modules (add-on addons) - before DB_READY/LOGIN so they catch everything
    if ns.ModuleLoader then pcall(ns.ModuleLoader.LoadAll) end
    if ns.K then ns.K.ApplyUserFonts() end
    ns.Fire("DB_READY")
end)
-- after the first loading screen: reassign Oasis texts with their font (see K.RefreshFonts in Kit.lua)
do
    local done = false
    ns.On("PLAYER_ENTERING_WORLD", function()
        if done or not (ns.K and ns.K.RefreshFonts) then return end
        done = true
        ns.After(1, function() pcall(ns.K.RefreshFonts) end)
        -- second pass in case a font was ready late; then remove the preload texts
        ns.After(5, function()
            pcall(ns.K.RefreshFonts)
            if ns.K.preloadFrame then ns.K.preloadFrame:Hide() end
        end)
        -- 0.5.770: on the first login of the day (cold font cache) WoW often loads font files only after seconds -> two late passes
        for _, d in ipairs({ 12, 30 }) do
            ns.After(d, function() pcall(ns.K.RefreshFonts) end)
        end
    end)
end

-- Start only once WoW knows the player name (otherwise entries like "Unbekannt" would appear)
local function start()
    if ns.loggedIn then return true end
    if not ns.me() then return false end
    if not ns.char then initDB() end
    if not ns.char then return false end
    for _, t in ipairs({ ns.db.chars, ns.db.recipes, ns.db.members, ns.db.legacy }) do
        for name in pairs(t) do
            if not validName(ns.short(name)) then t[name] = nil end
        end
    end
    ns.loggedIn = true
    ns.Fire("LOGIN")
    ns.print((L["v%s loaded – |cffffffff/oasis|r opens the hub."]):format("|cffffc98a" .. ns.version .. "|r"))
    return true
end
ns.On("PLAYER_LOGIN", function()
    if start() then return end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        tries = tries + 1
        if start() or tries > 120 then ticker:Cancel() end
    end)
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
ns.slash = {}
ns.slash.einsteiger = function()
    if not ns.db then return end
    ns.ApplyBeginner(ns.db.settings)
    ns.print(ns.L["Beginner settings applied: calmer notices, fewer pages. Show pages again under Settings > Areas. Please /reload."])
end
ns.slash.leistung = function(a) if ns.prof then ns.PerfStop() else ns.PerfStart(tonumber(a) or 60) end end
ns.slash.perf = ns.slash.leistung
ns.slash.freischalten = function(arg)
    arg = tostring(arg or ""):lower()
    local on = ns.db.settings.unlockAll == true
    if arg == "an" or arg == "on" then on = true elseif arg == "aus" or arg == "off" then on = false else on = not on end
    ns.db.settings.unlockAll = on or nil
    ns.print(on and "Alle Sounds und Emojis sind bei dir freigeschaltet (nur lokal)." or "Rang-Sperren wieder aktiv.")
    ns.RefreshPage("settings")
end
SLASH_OASIS1 = "/oasis"
SLASH_OASIS2 = "/oa"
SlashCmdList.OASIS = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if not ns.loggedIn then
        ns.print(L["Oasis is still loading – try again in a moment."])
        return
    end
    if cmd == "" then
        ns.Fire("TOGGLE_MAIN")
        return
    end
    local fn = ns.slash[cmd]
    ns.Trace("/oa " .. cmd)
    if fn then
        fn(rest)
    else
        ns.print(L["Commands: /oa, /oa award <item link>, /oa campfire [note], /oa deathroll <name> [start], /oa sync"])
    end
end
ns.slash.debug = function()
    ns.db.settings.debug = not ns.db.settings.debug
    ns.print(L["Debug: "] .. (ns.db.settings.debug and "an" or "aus"))
end


-- WoW system text ("%s ist jetzt online.", also "%1$s") -> Lua pattern with a capture per placeholder
function ns.GlobalPattern(gs, anchor)
    if type(gs) ~= "string" then return nil end
    gs = gs:gsub("%%(%d)%$", "%%")                                   -- remove numbered placeholders
    local p = gs:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")         -- escape special characters (including %)
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    if anchor then p = "^" .. p .. "$" end
    local ok = pcall(string.match, "", p)
    return ok and p or nil
end

-- Esc closes Oasis frames WITHOUT Blizzard's UISpecialFrames list (it otherwise "taints" the Esc path
-- and WoW then blocks spell cancel and camera turning). Own key catcher only while something is open.
do
    local list, stack = {}, {}
    -- 0.5.413: no key catcher anymore (passing keys through from addon code locked SpellStopCasting/SpellStopTargeting).
    -- Instead: while an Oasis frame is open (and not in combat), ESC is bound via override to an
    -- own button -> Blizzard's ESC action doesn't run at all, nothing gets "tainted".
    local escBtn = CreateFrame("Button", "OasisEscCloseButton", UIParent)
    local bound = false
    local focusOf = setmetatable({}, { __mode = "k" })
    local closeOf = setmetatable({}, { __mode = "k" })
    local function topmost()
        for i = #stack, 1, -1 do
            local f = stack[i]
            if f and f:IsVisible() then
                -- open, but without focus (main window, click went into the world): Esc belongs to the game, stays in the stack
                if not (focusOf[f] and not focusOf[f]()) then return f end
            else
                table.remove(stack, i)
            end
        end
    end
    -- is Esc really bound to our button? (0.5.598: don't trust only the flag - after the first close
    -- Esc was no longer bound on the second open, although the flag believed it was)
    local ACTION = "CLICK OasisEscCloseButton:LeftButton"
    local function reallyBound()
        if not GetBindingAction then return bound end
        local ok, a = pcall(GetBindingAction, "ESCAPE", true)
        if not ok then return bound end
        return a == ACTION
    end
    local function update()
        if InCombatLockdown() or not SetOverrideBindingClick then return end
        local want = topmost() ~= nil
        if want and (not bound or not reallyBound()) then
            ClearOverrideBindings(escBtn)
            SetOverrideBindingClick(escBtn, true, "ESCAPE", "OasisEscCloseButton")
            bound = true
        elseif not want and bound then
            ClearOverrideBindings(escBtn)
            bound = false
        end
    end
    -- Self-healing: while something is open, check every 0.3 s (very cheap: only active with an open frame)
    local guard = CreateFrame("Frame")
    guard:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t < 0.3 then return end
        self.t = 0
        if #stack == 0 and not bound then return end
        update()
    end)
    -- 0.5.596: react ONLY on key release. 0.5.594 reacted on press -> Oasis closed, binding freed,
    -- and releasing the same key then opened Blizzard's game menu.
    escBtn:RegisterForClicks("AnyUp")
    local lastEsc = 0
    escBtn:SetScript("OnClick", function()
        local now = GetTime()
        if now - lastEsc < 0.25 then return end
        lastEsc = now
        local f = topmost()
        -- 0.5.605: own close path (e.g. main window: like the X button, with fly animation)
        if f then
            if closeOf[f] then
                local ok = pcall(closeOf[f])
                if not ok then f:Hide() end
            else
                f:Hide()
            end
        end
        update()
    end)
    -- release before combat (in combat the binding can no longer be changed), set again afterwards
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then
            if bound and ClearOverrideBindings then ClearOverrideBindings(escBtn) bound = false end
        else
            update()
        end
    end)
    ns.EscUpdate = function() update() end
    -- Diagnosis: /oa esc -> which frames are in the Esc stack, is Esc currently bound?
    function ns.EscDebug()
        local out = {}
        for i, f in ipairs(stack) do
            out[#out + 1] = i .. ": " .. tostring(f.GetName and f:GetName() or "?") .. (f:IsShown() and " shown" or "") .. (f:IsVisible() and " visible" or "")
                .. (" alpha=%.2f"):format(f:GetEffectiveAlpha() or 1) .. ((focusOf[f] and not focusOf[f]()) and " (ohne Fokus)" or "")
        end
        local top = topmost()
        return out, bound, top and (top:GetName() or tostring(top)) or nil
    end
    ns.slash.esc = function()
        local out, b, top = ns.EscDebug()
        ns.print("Esc belegt: " .. tostring(b) .. "  oberstes: " .. tostring(top))
        for _, l in ipairs(out) do ns.print("  " .. l) end
    end
    function ns.EscClose(name, focusFn, closeFn)
        local f = type(name) == "string" and _G[name] or name
        if not f or list[f] then return end
        list[f] = true
        focusOf[f] = focusFn
        closeOf[f] = closeFn
        f:HookScript("OnShow", function(self)
            for i = #stack, 1, -1 do if stack[i] == self then table.remove(stack, i) end end
            stack[#stack + 1] = self
            update()
        end)
        f:HookScript("OnHide", function() update() end)
        -- Click sounds: only own Oasis frames (name with "Oasis" or no name)
        local fname = f.GetName and f:GetName()
        if not fname or fname:find("^Oasis") then
            f:HookScript("OnShow", function(self)
                if C_Timer and ns.K and ns.K.SoundifyTree then C_Timer.After(0.4, function() ns.K.SoundifyTree(self) end) end
            end)
        end
        if f:IsShown() then stack[#stack + 1] = f update() end
    end
end

-- Invite player to the group (with feedback; full group -> raid)
function ns.InviteName(name)
    if not name then return false end
    local n = ns.ChatName(name)
    if GetNumGroupMembers and GetNumGroupMembers() >= 5 and not IsInRaid() and C_PartyInfo and C_PartyInfo.ConvertToRaid then
        pcall(C_PartyInfo.ConvertToRaid)
    end
    local ok
    if C_PartyInfo and C_PartyInfo.InviteUnit then ok = pcall(C_PartyInfo.InviteUnit, n) end
    if not ok and InviteUnit then ok = pcall(InviteUnit, n) end
    if not ok and n ~= ns.short(name) and C_PartyInfo and C_PartyInfo.InviteUnit then ok = pcall(C_PartyInfo.InviteUnit, ns.short(name)) end
    ns.print(ok and (L["Invite sent to %s."]):format(ns.short(name)) or (L["Inviting %s failed."]):format(ns.short(name)))
    return ok
end

-- Oasis: Discord bridge (game side)
-- The actual bridge is OasisSync.exe (Tools\OasisSync.cs, docs Tools\OasisSync-Format.md, section Discord):
--   * Game -> Discord: OasisSync reads Logs\WoWChatLog.txt (WoW only writes it with /chatlog active) and posts
--     guild lines via webhook. This file can turn on the chat log automatically at login (setting).
--   * Discord -> game: OasisSync puts Discord messages into Oasis\Import.lua as OasisImport.collections.discord.
--     WoW only reads the file at login / /reload -> Discord messages only appear in Oasis guild chat afterwards.
-- Discord messages are ONLY displayed: not sent to the real WoW chat and not passed on to other Oasis users
-- (GuildChat doesn't include entries with src="discord" when reloading missed messages).
-- Reason: whoever runs the bridge delivers the messages themselves anyway; passing them on would duplicate with several
-- operators, and foreign Discord names shouldn't travel to the whole guild as "guild chat".
--
-- Toggle in the chat section of the settings: ns.AppendPageSettings (Settings.lua), load order doesn't matter.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Discord", function()   -- Discord module (can be disabled, see ModuleLoader.lua)
local L = ns.L

local DB = {}
ns.DiscordBridge = DB

local KEEP_DAYS = 30
local function S() return (ns.db and ns.db.settings) or {} end

------------------------------------------------------------------------
-- turn on chat log automatically (default: off)
------------------------------------------------------------------------
function DB.ChatlogAvailable() return type(LoggingChat) == "function" end

function DB.EnableChatlog(force)
    if not force and S().dcChatlog ~= true then return false end
    if not DB.ChatlogAvailable() then return false end
    local ok, on = pcall(LoggingChat)
    if ok and on then return true end
    local ok2 = pcall(LoggingChat, true)
    if ok2 then ns.print(L["Chat log enabled - OasisSync can pass guild chat on to Discord."]) end
    return ok2
end

------------------------------------------------------------------------
-- show Discord messages from Import.lua in Oasis guild chat
------------------------------------------------------------------------
local function prune(seen)
    local cut = (ns.now() - KEEP_DAYS * 86400)
    for id, ts in pairs(seen) do if (tonumber(ts) or 0) < cut then seen[id] = nil end end
end

local function sanitize(s, max)
    s = tostring(s or "")
    s = s:gsub("[%z\1-\9\11-\31]", ""):gsub("|", "||")   -- no WoW control codes (colors, links, textures) from Discord
    if #s > max then s = s:sub(1, max) end
    return s
end

function DB.ShowImported()
    if S().dcShow == false or not ns.db then return 0 end
    local GC = ns.GuildChat
    local data = _G.OasisImport
    local list = type(data) == "table" and type(data.collections) == "table" and data.collections.discord
    if not GC or not GC.Add or type(list) ~= "table" then return 0 end
    ns.db.dcSeen = ns.db.dcSeen or {}
    local seen = ns.db.dcSeen
    prune(seen)
    local cut, n = ns.now() - KEEP_DAYS * 86400, 0
    GC.bulk = true
    for _, r in ipairs(list) do
        local id = type(r) == "table" and r.id
        local ts = type(r) == "table" and tonumber(r.ts)
        if type(id) == "string" and id ~= "" and not seen[id] and ts and ts > cut and type(r.text) == "string" and r.text ~= "" then
            seen[id] = ts
            local author = sanitize(r.author, 40):gsub("^%s+", ""):gsub("%s+$", "")
            if author == "" then author = "Discord" end
            local ok, added = pcall(GC.Add, { ts = ts, s = author, m = sanitize(r.text, 1000), dc = true, src = "discord", cid = "dc" .. id }, true)
            if ok and added then n = n + 1 end
        end
    end
    GC.bulk = nil
    if n > 0 then
        ns.RefreshPage("chat")
        ns.debug("Discord-Nachrichten uebernommen:", n)
    end
    return n
end

ns.Listen("LOGIN", function()
    ns.After(3, function() pcall(DB.EnableChatlog) end)
    -- after GuildChat (prune/cleanLog at login) and Import.Run (8 s)
    ns.After(10, function() pcall(DB.ShowImported) end)
end)
ns.slash.discord = function()
    local n = DB.ShowImported()
    ns.print((L["Discord messages imported: %d (new ones only appear after /reload)"]):format(n or 0))
end

------------------------------------------------------------------------
-- settings in the "Chat" section
------------------------------------------------------------------------
function DB.BuildSettings(det, y)
    local K = ns.K
    if not K or not K.Toggle then return y end
    if not (ns.ExternTools and ns.ExternTools()) then return y end   -- needs OasisSync: not offered publicly for now
    y = y - 6
    local t1 = K.Toggle(det, L["Show Discord messages in guild chat (via OasisSync, after /reload)"],
        function() return S().dcShow ~= false end,
        function(v) S().dcShow = v and true or false if v then pcall(DB.ShowImported) end end)
    t1:SetPoint("TOPLEFT", 14, y)
    t1:SetWidth(600)
    det.t[#det.t + 1] = t1
    y = y - 32
    if DB.ChatlogAvailable() then
        local t2 = K.Toggle(det, L["Enable chat log on login (guild chat -> Discord via OasisSync)"],
            function() return S().dcChatlog == true end,
            function(v) S().dcChatlog = v and true or nil if v then pcall(DB.EnableChatlog, true) end end)
        t2:SetPoint("TOPLEFT", 14, y)
        t2:SetWidth(600)
        det.t[#det.t + 1] = t2
        y = y - 32
    end
    return y
end

-- 0.6.289: append Discord toggles to the chat section of the settings (module runs after Settings.lua)
if ns.AppendPageSettings then ns.AppendPageSettings("chat", function(det, y) return DB.BuildSettings(det, y) end) end
end)

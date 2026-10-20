-- Oasis: toggleable modules (0.5.568 as add-on addons, since 0.5.580 everything in ONE Oasis folder again)
-- Large sections live in Modules\<Name>\. Each file there wraps its content in ns.ModuleFile("<key>", function() ... end).
-- On startup (ADDON_LOADED) only enabled modules are run; disabled functions are discarded
-- and use no memory after the next /reload. Settings > Sections > Modules.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local M = {}
ns.ModuleLoader = M
-- ns.ModuleFile lives in Core.lua since 0.6.272 (module files may be anywhere in the toc), collected in ns.moduleFiles
-- 0.6.272: ordered by category (cat); the settings page shows a heading per category
M.CATS = { "Game content", "Guild and group", "Chat", "Comfort and map" }
M.LIST = {
    { cat = "Game content", addon = "Oasis_Dungeons", title = "Dungeons", icon = "dungeons", desc = "Dungeon database, bosses, maps, quest locations and the dungeon page" },
    { cat = "Game content", addon = "Oasis_RaidTools", title = "Raids and events", icon = "raid", desc = "Events and sign-ups, raid planner, raid check, buffs, master looter and loot points, tactics map, raid IDs, combat reports" },
    { cat = "Game content", addon = "Oasis_Legacy", title = "Legacy", icon = "legacy", desc = "Legacy achievements and collectibles" },
    { cat = "Game content", addon = "Oasis_QuestItems", title = "Quest items", icon = "checklist", desc = "Find and offer quest items in the guild" },
    { cat = "Game content", addon = "Oasis_Rares", title = "Rare Enemies", icon = "star_on", desc = "Rare and world boss sightings shared with the guild, with respawn estimate" },
    { cat = "Game content", addon = "Oasis_Reputation", title = "Reputation Planner", icon = "badges", desc = "Your reputation and the guild's standing per faction" },
    { cat = "Guild and group", addon = "Oasis_Group", title = "My group", icon = "groups", desc = "Group overview, quest sharing, group XP, blessing plan, threat and pull warning, roll game, zone in chat" },
    { cat = "Guild and group", addon = "Oasis_Deathroll", title = "Deathroll", icon = "deathroll", desc = "Deathroll duels with leaderboard" },
    { cat = "Guild and group", addon = "Oasis_Polls", title = "Polls", icon = "polls", desc = "Votes in the guild" },
    { cat = "Guild and group", addon = "Oasis_Community", title = "Community", icon = "heart", desc = "Profiles, birthdays, mentors for newcomers, thanks and helper of the week, guild achievements" },
    { cat = "Guild and group", addon = "Oasis_Combat", title = "Combat ranking", icon = "stats", desc = "Guild damage and healing after every fight, real crits" },
    { cat = "Guild and group", addon = "Oasis_Upgrades", title = "Upgrade finder", icon = "wants", desc = "Tradeable guild gear that would be an upgrade for you" },
    { cat = "Guild and group", addon = "Oasis_Talents", title = "Talents", icon = "profile", desc = "View talents of guild members and inspected players" },
    { cat = "Guild and group", addon = "Oasis_Discord", title = "Discord", icon = "speaker", desc = "Discord bridge and the guild's voice channel" },
    { cat = "Guild and group", addon = "Oasis_Crafting", title = "Crafting", icon = "crafting", desc = "Who can craft what, crafting orders to the guild, materials in the tooltip" },
    { cat = "Guild and group", addon = "Oasis_GuildBank", title = "Guild bank", icon = "bank", desc = "Guild bank contents and history" },
    { cat = "Guild and group", addon = "Oasis_Market", title = "Trade", icon = "bank", desc = "Buy and sell within the guild, market values" },
    { cat = "Guild and group", addon = "Oasis_Wishlist", title = "Wish list", icon = "wants", desc = "Items the guild is looking for, who-needs-what in tooltips, hints in dungeons" },
    { cat = "Guild and group", addon = "Oasis_Chronicle", title = "Chronicle", icon = "chronicle", desc = "What happened in the guild: levels, badges, achievements" },
    { cat = "Guild and group", addon = "Oasis_Campfire", title = "Campfire", icon = "camp", desc = "Announce campfires to the guild and show them on the map" },
    { cat = "Guild and group", addon = "Oasis_Deaths", title = "Deaths", icon = "deaths", desc = "Deaths in the guild, death locations on the map" },
    { cat = "Guild and group", addon = "Oasis_Social", title = "Players", icon = "groups", desc = "Quest partners in the guild, recent players from outside, newcomers" },
    { cat = "Guild and group", addon = "Oasis_Collections", title = "Collections", icon = "star_on", desc = "Mounts, pets and toys of the guild" },
    { cat = "Guild and group", addon = "Oasis_GuildGoals", title = "Guild goals", icon = "checklist", desc = "Shared projects with steps and progress" },
    { cat = "Guild and group", addon = "Oasis_Greeting", title = "Greeting", icon = "smile", desc = "Coordinated greeting in guild chat when someone logs in" },
    { cat = "Guild and group", addon = "Oasis_GuildManagement", title = "Guild care", icon = "admin", desc = "Guild leaders only: inactives, applicants, recruiting, attendance, log with guild history, ban list, suspicion monitor" },
    { cat = "Chat", addon = "Oasis_Whispers", title = "Whisper history", icon = "social", desc = "Whisper conversations, private tab in guild chat, forwarding to alts" },
    { cat = "Chat", addon = "Oasis_GameChat", title = "Game chat", icon = "social", desc = "Makes Blizzard's chat windows easier to read: names, levels and icons, filters, search, history and keyword alerts" },
    { cat = "Chat", addon = "Oasis_EmojiSuggest", title = "Emoji suggestions", icon = "smile", desc = "Suggest matching emojis while typing" },
    { cat = "Comfort and map", addon = "Oasis_Comfort", title = "Comfort", icon = "home", desc = "Auto repair and sell, quests, invites, bars, tooltips" },
    { cat = "Comfort and map", addon = "Oasis_MapExtras", title = "Map extras", icon = "pin", desc = "Guild gathering spots, markers, trails, danger zones, target arrow" },
    { cat = "Comfort and map", addon = "Oasis_MyJourney", title = "My Journey", icon = "chronicle", desc = "Timeline and records of your character" },
    { cat = "Comfort and map", addon = "Oasis_QuestTags", title = "Quest markers", icon = "checklist", desc = "Mark group quests in the quest log" },
    { cat = "Game content", addon = "Oasis_WeaponTrainers", title = "Weapon masters", icon = "map", desc = "Which weapon you learn in which capital" },
    { cat = "Guild and group", addon = "Oasis_Encounters", title = "Encounters", icon = "groups", desc = "Players outside the guild: remember gear when inspecting" },
    { cat = "Comfort and map", addon = "Oasis_ItemCompare", title = "Item comparison", icon = "wants", desc = "Comparison window next to the item tooltip" },
    { cat = "Comfort and map", addon = "Oasis_BankSlots", title = "Bank slots", icon = "bank", desc = "Remember fixed slots in your bank" },
    { cat = "Comfort and map", addon = "Oasis_Performance", dev = true, title = "Performance", icon = "stats", desc = "Live CPU time display and guild measurements" },
}
M.state = {}   -- [addon] = "loaded" | "off" | "missing" | "disabled" | error text

-- 0.6.571: module keys in English - take over disabled modules under the old name once
M.RENAMED = { Oasis_Bankplaetze = "Oasis_BankSlots", Oasis_Begegnungen = "Oasis_Encounters", Oasis_Begruessung = "Oasis_Greeting", Oasis_Chronik = "Oasis_Chronicle", Oasis_EmojiVorschlaege = "Oasis_EmojiSuggest", Oasis_Fluestern = "Oasis_Whispers", Oasis_Gemeinschaft = "Oasis_Community", Oasis_Gildenbank = "Oasis_GuildBank", Oasis_Gildenpflege = "Oasis_GuildManagement", Oasis_Gildenziele = "Oasis_GuildGoals", Oasis_Gruppe = "Oasis_Group", Oasis_Handel = "Oasis_Market", Oasis_Handwerk = "Oasis_Crafting", Oasis_Itemvergleich = "Oasis_ItemCompare", Oasis_Kampf = "Oasis_Combat", Oasis_Kartenextras = "Oasis_MapExtras", Oasis_Komfort = "Oasis_Comfort", Oasis_Lager = "Oasis_Campfire", Oasis_Leistung = "Oasis_Performance", Oasis_MeinWeg = "Oasis_MyJourney", Oasis_Mitspieler = "Oasis_Social", Oasis_Questitems = "Oasis_QuestItems", Oasis_Questmarken = "Oasis_QuestTags", Oasis_Raidwerkzeuge = "Oasis_RaidTools", Oasis_Ruf = "Oasis_Reputation", Oasis_Sammlungen = "Oasis_Collections", Oasis_Spielchat = "Oasis_GameChat", Oasis_Talente = "Oasis_Talents", Oasis_Tode = "Oasis_Deaths", Oasis_Umfragen = "Oasis_Polls", Oasis_Waffenlehrer = "Oasis_WeaponTrainers", Oasis_Wunschliste = "Oasis_Wishlist" }
local migrated
local function off()
    local mo = ns.db and ns.db.settings.modOff
    if mo and not migrated then
        migrated = true
        for old, new in pairs(M.RENAMED) do
            if mo[old] then mo[new] = true mo[old] = nil end
        end
    end
    return mo or {}
end
function M.IsOn(addon) return not off()[addon] end
function M.Loaded(addon) return M.state[addon] == "loaded" end
-- Folders from 0.5.564-0.5.579 (separate add-on addons): no longer needed
M.OLD_FOLDERS = { "Oasis_Dungeons", "Oasis_Raidwerkzeuge", "Oasis_Deathroll", "Oasis_Brachland", "Oasis_Legacy", "Oasis_Questitems", "Oasis_Sprachen",
    "Oasis_Locale_FR", "Oasis_Locale_ES", "Oasis_Locale_IT", "Oasis_Locale_PT", "Oasis_Locale_RU", "Oasis_Locale_ZH", "Oasis_Locale_KO" }
-- on startup (ADDON_LOADED, before DB_READY/LOGIN): run enabled modules, discard the rest
-- 0.6.566: Oasis is split into sub-addons (folder Addons\<Teil>\, own toc with LoadOnDemand).
-- Oasis loads them itself here, BEFORE the modules run - so they hook into ns.ModuleFile as before and run before DB_READY.
-- If a part is not installed or disabled in the AddOn list, its modules are missing (state "missing").
M.PARTS = {
    { addon = "Oasis_GroupsRaids", title = "Oasis - Groups & Raids", modules = { "Oasis_Group", "Oasis_Dungeons", "Oasis_QuestTags", "Oasis_RaidTools", "Oasis_Combat", "Oasis_Talents", "Oasis_Rares" } },
    { addon = "Oasis_Trade", title = "Oasis - Trade", modules = { "Oasis_Crafting", "Oasis_Market", "Oasis_Wishlist" } },
    { addon = "Oasis_Convenience", title = "Oasis - Convenience", modules = { "Oasis_Comfort", "Oasis_MapExtras", "Oasis_GameChat", "Oasis_Whispers", "Oasis_Upgrades", "Oasis_ItemCompare", "Oasis_WeaponTrainers", "Oasis_BankSlots" } },
}
M.partOf = {}
for _, p in ipairs(M.PARTS) do for _, k in ipairs(p.modules) do M.partOf[k] = p end end
M.partState = {}   -- [part] = "loaded" | reason from LoadAddOn ("MISSING", "DISABLED" ...)
local function loadParts()
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    for _, p in ipairs(M.PARTS) do
        if not load then M.partState[p.addon] = "MISSING" else
            local ok, loaded, reason = pcall(load, p.addon)
            M.partState[p.addon] = (ok and loaded) and "loaded" or tostring(reason or (not ok and loaded) or "MISSING")
        end
    end
end
function M.PartLoaded(addon) return M.partState[addon] == "loaded" end
function M.LoadAll()
    pcall(loadParts)
    local files = ns.moduleFiles or {}
    ns.moduleFiles = nil
    -- 0.6.285: run in toc order (not the display list) - e.g. one module extends another
    local byKey, ordered = {}, {}
    for _, m in ipairs(M.LIST) do byKey[m.addon] = m end
    for _, k in ipairs(ns.moduleOrder or {}) do if byKey[k] then ordered[#ordered + 1] = byKey[k] byKey[k] = nil end end
    for _, m in ipairs(M.LIST) do if byKey[m.addon] then ordered[#ordered + 1] = m end end
    ns.moduleOrder = nil
    for _, m in ipairs(ordered) do
        local fns = files[m.addon]
        if not M.IsOn(m.addon) then
            M.state[m.addon] = "off"
        elseif not fns then
            M.state[m.addon] = "missing"
        else
            M.state[m.addon] = "loaded"
            for _, fn in ipairs(fns) do
                local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "") end)
                if not ok then
                    M.state[m.addon] = tostring(err):match("^[^\n]*")
                    if ns.err then pcall(ns.err, "Modul " .. m.addon, err) end
                end
            end
        end
    end
    -- old add-on folders still present? Then a notice (toast + Settings > Modules)
    -- 0.5.583: GetAddOnInfo also returns a name for MISSING addons (reason "MISSING") -> check DoesAddOnExist or the reason
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    M.stale = {}
    for _, n in ipairs(M.OLD_FOLDERS) do
        local found = false
        if exists then
            local ok, r = pcall(exists, n)
            found = ok and r == true
        elseif info then
            local ok, name, _, _, _, reason = pcall(info, n)
            found = ok and name ~= nil and reason ~= "MISSING"
        end
        if found then M.stale[#M.stale + 1] = n end
    end
end
-- Guild module (addon Oasis_Guild): present / enabled / toggle via the game's AddOn manager
local GUILD = "Oasis_Guild"
function M.GuildInstalled()
    local ex = C_AddOns and C_AddOns.DoesAddOnExist
    if ex then local ok, r = pcall(ex, GUILD) return ok and r == true end
    return ns.GuildPack and true or false
end
function M.GuildEnabled()
    local f = C_AddOns and C_AddOns.GetAddOnEnableState
    if f then
        local ok, r = pcall(f, GUILD, ns.UnitName("player"))
        if not (ok and type(r) == "number") then ok, r = pcall(f, ns.UnitName("player"), GUILD) end
        if ok and type(r) == "number" then return r > 0 end
    end
    return ns.GuildPack and true or false
end
function M.SetGuildEnabled(on)
    local f = C_AddOns and (on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn) or (on and EnableAddOn or DisableAddOn)
    if f then
        local ok = pcall(f, GUILD, ns.UnitName("player"))
        if not ok then pcall(f, GUILD) end
    end
    M.dirty = true
end
function M.Set(addon, on)
    ns.db.settings.modOff = ns.db.settings.modOff or {}
    ns.db.settings.modOff[addon] = (not on) and true or nil
    M.dirty = true
end
-- Memory of the whole addon (modules count toward Oasis since 0.5.580)
function M.MemKB(addon)
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not get then return nil end
    local ok, v = pcall(get, addon)
    return ok and v or nil
end
function M.UpdateMem()
    if ns.inCombat() then return end
    local up = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    if up then pcall(up) end
end
-- all Oasis parts for performance measurement (since 0.5.580 just one addon)
function M.Addons() return { ADDON } end

-- Settings > Sections > Modules -------------------------------------------------------
local STATE_TXT = {
    loaded = { "geladen", "66db9e" }, off = { "aus", "888888" },
    missing = { "fehlt", "e8b44a" },
}
local function fmtMB(kb) if not kb then return "" end return ("%.1f MB"):format(kb / 1024) end
local function build(f)
    local H = ns.SettingsHelpers
    -- 0.6.480: plain category rows instead of section() - the automatic box border otherwise wrapped around the cards
    local function cathead(text, yy)
        local t = K.Text(f, 11, C.dim)
        t:SetPoint("TOPLEFT", 2, yy)
        t:SetText(K.Upper(text))
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1)
        d:SetPoint("LEFT", t, "RIGHT", 10, 0)
        d:SetPoint("RIGHT", f, "LEFT", 738, 0)
        d:SetColorTexture(1, 1, 1, 0.08)
    end
    local intro = K.Text(f, 11, C.muted)
    intro:SetPoint("TOPLEFT", 2, -4)
    intro:SetWidth(730)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(L["Large areas can be switched off. Whatever you switch off is not loaded at all after the next /reload and uses no memory."])
    -- 0.5.713: one glass card per module (icon + name, toggle on the right, description, state bottom right)
    f.noCompact = true
    f.rows = {}
    local W, TH, GAP = 362, 96, 12
    local y = -40
    -- per category a heading + cards in two columns

    for _, cat in ipairs(M.CATS) do
      local list = {}
      -- 0.6.523: developer modules (performance measurement) only in developer mode
      for _, m in ipairs(M.LIST) do if m.cat == cat and (not m.dev or (ns.IsDev and ns.IsDev())) then list[#list + 1] = m end end
      if #list > 0 then
        cathead(L[cat], y)
        y = y - 26
      end
      for i, m in ipairs(list) do
        local col = (i - 1) % 2
        if col == 0 and i > 1 then y = y - (TH + GAP) end

        local c = H.cardH(f, col * (W + 14), y, W, TH, m.icon, L[m.title], L[m.desc])
        if c.s then c.s:SetWordWrap(true) c.s:SetPoint("RIGHT", -70, 0) end
        local tg = K.Toggle(c, "", function() return M.IsOn(m.addon) end, function(v)
            M.Set(m.addon, v)
            if f.reload then f.reload:Show() f.hint:Show() end
        end)
        tg:SetWidth(46)
        tg:SetPoint("TOPRIGHT", -14, -12)
        local st = K.Text(c, 10, C.dim, "RIGHT")
        st:SetPoint("BOTTOMRIGHT", -14, 10)
        f.rows[#f.rows + 1] = { m = m, tg = tg, st = st }
      end
      if #list > 0 then y = y - (TH + GAP) - 8 end
    end
    -- 0.5.728: guild module = separate addon "Oasis_Guild" (meme sounds, music, guild emojis, bug reports); toggleable
    -- individually here and in the game's AddOn list. In the public version the folder is not included at all.
    local gm = H.cardH(f, 0, y, 2 * W + 14, 72, "home", L["Guild module"],
        L["Meme sounds, music, guild emojis and bug reports - a separate add-on for the guild only."])
    gm.s:SetWordWrap(true)
    gm.s:SetPoint("RIGHT", -70, 0)
    f.gmState = K.Text(gm, 10, C.dim, "RIGHT")
    f.gmState:SetPoint("BOTTOMRIGHT", -14, 10)
    f.gmT = K.Toggle(gm, "", function() return M.GuildEnabled() end, function(v)
        M.SetGuildEnabled(v)
        if f.reload then f.reload:Show() f.hint:Show() end
        f.gmState:SetText("|cffe8b44a" .. L[v and "on after /reload" or "off after /reload"] .. "|r")
    end)
    f.gmT:SetWidth(46)
    f.gmT:SetPoint("TOPRIGHT", -14, -12)
    f.gmT:SetShown(M.GuildInstalled())
    y = y - 72 - GAP - 8
    f.total = K.Text(f, 11, C.muted)
    f.total:SetPoint("TOPLEFT", 0, y)
    f.hint = K.Text(f, 11, C.amber or C.accent)
    f.hint:SetPoint("TOPLEFT", 0, y - 30)
    f.hint:SetText(L["Changes apply after reloading."])
    f.hint:SetShown(M.dirty and true or false)
    f.reload = K.Button(f, L["Reload now"], 150, 24, "primary", function() ReloadUI() end)
    f.reload:SetPoint("LEFT", f.hint, "RIGHT", 14, 0)
    f.reload:SetShown(M.dirty and true or false)
    f.stale = K.Text(f, 11, C.amber or C.accent)
    f.stale:SetPoint("TOPLEFT", 0, y - 64)
    f.stale:SetWidth(730)
    f.stale:SetJustifyH("LEFT")
    f.stale:SetWordWrap(true)
end
local function staleText()
    return (L["Old Oasis add-on folders are still in your AddOns folder and are no longer needed (everything now lives in the Oasis folder). You can delete them: %s"]):format(table.concat(M.stale, ", "))
end
local function refresh(f)
    M.UpdateMem()
    if f.gmT then
        f.gmT:SetShown(M.GuildInstalled())
        f.gmT:Refresh()
        if not M.GuildInstalled() then f.gmState:SetText("|cff888888" .. L["not installed (public version)"] .. "|r")
        elseif ns.GuildPack then f.gmState:SetText("|cff66db9e" .. L["loaded"] .. "|r")
        else f.gmState:SetText("|cff888888" .. L["off"] .. "|r") end
    end
    local sum = M.MemKB(ADDON) or 0
    for _, r in ipairs(f.rows or {}) do
        r.tg:Refresh()
        local s = M.state[r.m.addon]
        local sd = STATE_TXT[s]
        local txt = sd and ("|cff" .. sd[2] .. L[sd[1]] .. "|r") or ("|cffff6060" .. tostring(s or "?") .. "|r")
        if not M.IsOn(r.m.addon) and s == "loaded" then txt = "|cffe8b44a" .. L["off after /reload"] .. "|r" end
        if M.IsOn(r.m.addon) and s == "off" then txt = "|cffe8b44a" .. L["on after /reload"] .. "|r" end
        -- 0.6.566: module lives in a sub-addon that is missing or disabled
        local part = M.partOf[r.m.addon]
        if part and s == "missing" and not M.PartLoaded(part.addon) then
            txt = "|cffe8b44a" .. (L["%s missing"]):format(part.title) .. "|r"
        end
        r.st:SetText(txt)
    end
    f.total:SetText((L["Oasis is currently using %s."]):format(fmtMB(sum)))
    local has = M.stale and #M.stale > 0
    f.stale:SetText(has and staleText() or "")
    f.stale:SetShown(has and true or false)
end
-- notify once per version after login
ns.Listen("LOGIN", function()
    if not (M.stale and #M.stale > 0) or not ns.db then return end
    if ns.db.staleDirHint == ns.version then return end
    ns.db.staleDirHint = ns.version
    C_Timer.After(12, function()
        K.Toast(L["Old Oasis folders"], staleText(), nil, function() ns.slash.module() end)
    end)
end)
if ns.AddSettingsTab then ns.AddSettingsTab("modules", "Modules", build, refresh) end
ns.slash.module = function() if ns.Settings then ns.Settings.SetTab("modules") end end

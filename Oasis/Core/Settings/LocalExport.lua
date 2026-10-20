-- Oasis - Guild module: local full export (0.5.921) - for now ONLY for developers (ns.IsDev) and only when enabled.
-- On login, every 15 minutes and on logout stores a complete snapshot of the guild data in
-- OasisDB.localExport. An addon cannot write files itself: WoW writes the saved data on
-- logout or /reload to WTF\...\SavedVariables\Oasis.lua - from there Tools\oasis_export.py --full
-- turns it into JSON files (one per collection, with timestamp).
-- Included: guild roster (with notes), all Oasis profiles, ALL shared collections (incl. those of guild leadership,
-- as far as this character has them), recipes, guild settings. NOT included: guild chat, whispers,
-- personal settings, personal histories ("My path"), sample data.
local ns = Oasis
if not ns then return end
local L = ns.L

local LX = {}
ns.LocalExport = LX
LX.SCHEMA = 1
LX.EVERY = 15 * 60

function LX.Wanted()
    return (ns.IsDev and ns.IsDev() and ns.db and ns.db.settings and ns.db.settings.localExport == true) and true or false
end
local function isDemo(r)
    return type(r) == "table" and (r.demo or tostring(r.id or ""):find("demo-", 1, true)) and true or false
end
-- deep copy only with numbers/texts/booleans/tables (no functions, no frames)
local function clean(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth > 10 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            local c = clean(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

function LX.Build(reason)
    local db = ns.db
    if not db then return nil end
    local ex = {
        schema = LX.SCHEMA, kind = "full", reason = reason or "manual",
        addon = ns.version, at = ns.now(), by = ns.me(), byDisplay = ns.displayName and ns.displayName(ns.me()) or ns.me(),
        guild = (IsInGuild and IsInGuild() and GetGuildInfo and GetGuildInfo("player")) or "",
        realm = GetRealmName and GetRealmName() or "", locale = GetLocale and GetLocale() or "",
        members = {}, profiles = {}, collections = {}, recipes = {}, counts = {},
    }
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        if not m.demo then ex.members[#ex.members + 1] = clean(m, 1) end
    end
    for name, p in pairs(db.members or {}) do
        if type(p) == "table" and not p.demo and not p.stub then ex.profiles[name] = clean(p, 1) end
    end
    for name, r in pairs(db.recipes or {}) do
        if type(r) == "table" and not r.demo then ex.recipes[name] = clean(r, 1) end
    end
    local total = 0
    for cname, coll in pairs(db.store or {}) do
        if type(coll) == "table" then
            local list = {}
            for _, r in pairs(coll) do
                if type(r) == "table" and not r.del and not isDemo(r) then list[#list + 1] = clean(r, 1) end
            end
            ex.collections[cname] = list
            ex.counts[cname] = #list
            total = total + #list
        end
    end
    ex.guildcfg = clean(db.gcfgCache, 1)
    ex.counts._members, ex.counts._profiles, ex.counts._records = #ex.members, 0, total
    for _ in pairs(ex.profiles) do ex.counts._profiles = ex.counts._profiles + 1 end
    return ex
end

-- store snapshot; turned off or not a developer: remove old snapshot (no data leftovers)
function LX.Run(reason)
    if not ns.db then return nil end
    if not LX.Wanted() then
        ns.db.localExport = nil
        return nil
    end
    local ok, ex = pcall(LX.Build, reason)
    if not ok or not ex then
        if ns.debug then ns.debug("LocalExport:", tostring(ex)) end
        return nil
    end
    ns.db.localExport = ex
    LX.last = ex.at
    return ex
end
function LX.Status()
    local ex = ns.db and ns.db.localExport
    if not ex then return L["No export in this session yet."] end
    return (L["Last export: %s - %d members, %d profiles, %d records"]):format(
        date and date("%H:%M:%S", ex.at) or tostring(ex.at), ex.counts._members or 0, ex.counts._profiles or 0, ex.counts._records or 0)
end

-- timing: login (shortly after, once guild roster and sync are there), every 15 minutes, logout
ns.Listen("LOGIN", function()
    ns.After(15, function() pcall(LX.Run, "login") end)
end)
ns.Every(60, function()
    if LX.Wanted() and ns.now() - (LX.last or 0) >= LX.EVERY then pcall(LX.Run, "timer") end
end)
ns.On("PLAYER_LOGOUT", function() pcall(LX.Run, "logout") end)

-- Settings > Profile & Data > Local export: tab only exists for developers (registered at login)
local function build(f)
    local H = ns.SettingsHelpers
    local K, C = ns.K, ns.K.C
    local S = function() return ns.db.settings end
    H.section(f, L["Local data export (developer)"], 14, -12, 700)
    f.t = H.toggle(f, 14, -46, "Alle Gildendaten lokal exportieren", "localExport",
        "Beim Einloggen, alle 15 Minuten und beim Ausloggen", function()
            pcall(LX.Run, "manual")
            if f.status then f.status:SetText(LX.Status()) end
        end, 600)
    H.note(f, L["Oasis saves a full snapshot: guild roster, profiles, all shared collections, recipes and guild settings. Not included: guild chat, whispers and personal settings."], 14, -84, 660)
    H.note(f, L["WoW only writes the data to disk on logout or /reload (SavedVariables\\Oasis.lua). The tool turns it into files: python Tools\\oasis_export.py --full"], 14, -124, 660)
    f.run = K.Button(f, L["Export now"], 160, 24, "primary", function()
        if not LX.Wanted() then
            ns.print(L["Turn the switch on first."])
        else
            pcall(LX.Run, "manual")
        end
        f.status:SetText(LX.Status())
    end)
    f.run:SetPoint("TOPLEFT", 14, -172)
    f.status = K.Text(f, 12, C.muted)
    f.status:SetPoint("LEFT", f.run, "RIGHT", 14, 0)
    f.status:SetText(LX.Status())
end
local function refresh(f)
    if f.t and f.t.Refresh then pcall(f.t.Refresh, f.t) end
    if f.status then f.status:SetText(LX.Status()) end
end
ns.Listen("LOGIN", function()
    if ns.IsDev and ns.IsDev() and ns.AddSettingsTab then ns.AddSettingsTab("lexport", "Lokaler Export", build, refresh) end
end)

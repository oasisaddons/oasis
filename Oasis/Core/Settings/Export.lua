-- Oasis: export for websites/companion program (Tools\OasisSync.exe)
-- Extends the snapshot OasisDB.export (Officer.Snapshot) with members, profiles, crafters and collections.
-- The companion program reads it from WTF\...\SavedVariables\Oasis.lua and turns it into JSON.
-- NOT exported: officer notes, guild chat, whispers, ratings, ban list, applicants,
-- guild leadership settings, personal settings, demo data.
-- Format: Tools\OasisSync-Format.md (bump SCHEMA on changes and document it there)
-- 0.5.926: part of public Oasis again - every guild may export its data and use it for its own
-- website / Discord bot. There is no service from us; tools and format are in the Oasis-Tools package.
local ADDON, ns = ...
local Store = ns.Store

local Export = {}
ns.Export = Export
Export.SCHEMA = 1

-- these collections are exported (the rest stays in the game)
Export.COLLECTIONS = {
    "events", "signups", "raidplan", "sres", "attend", "points", "loot",
    "bank", "bankworth", "wants", "orders", "chronicle",
    "polls", "notices", "duels",   -- 0.5.617: without bank log, votes with names, death locations, campfires
}
-- Profile fields that are not exported
local PROFILE_SKIP = { hh = true, hh_want = true, stub = true, demo = true, gb = true, bio = true, zone = true, ao = true }   -- 0.5.617: without birthday/bio/zone

local function isDemo(r)
    return type(r) == "table" and (r.demo or tostring(r.id or ""):find("demo-", 1, true))
end

-- deep copy with only numbers/strings/booleans/tables
local function clean(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth > 8 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            local c = clean(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

function Export.Build()
    local db = ns.db
    if not db then return nil end
    local guild, _, _, realm = nil, nil, nil, nil
    if IsInGuild() then guild = GetGuildInfo("player") end
    realm = GetRealmName and GetRealmName() or ""
    local ex = {
        schema = Export.SCHEMA,
        addon = ns.version,
        at = ns.now(),
        by = ns.me(),
        byDisplay = ns.displayName(ns.me()),
        guild = guild or "",
        realm = realm,
        locale = GetLocale and GetLocale() or "",
        members = {}, profiles = {}, collections = {}, crafters = {},
    }
    -- Guild roster (without officer note)
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        if not m.demo then
            ex.members[#ex.members + 1] = {
                name = m.name, short = m.aname, display = ns.displayName(m.name),
                rank = m.rank, rankIndex = m.rankIndex, level = m.level, class = m.class,
                -- 0.5.617: no zone; note only from Oasis users
                note = (ns.Radar.UsesOasis and ns.Radar.UsesOasis(m.name)) and m.note or nil, online = m.online, lastOnlineDays = m.offDays,
                main = ns.Alts and ns.Alts.Canon and ns.Alts.Canon(m.name) or nil,
            }
        end
    end
    -- Oasis profiles (what everyone shares via HELLO)
    for name, p in pairs(db.members or {}) do
        if type(p) == "table" and not p.demo and not p.stub then
            local c = {}
            for k, v in pairs(p) do if not PROFILE_SKIP[k] then c[k] = clean(v, 1) end end
            ex.profiles[name] = c
        end
    end
    -- Crafters: who knows which recipes
    for name, r in pairs(db.recipes or {}) do
        if type(r) == "table" and not r.demo then ex.crafters[name] = clean(r.profs, 1) end
    end
    -- shared collections
    for _, cname in ipairs(Export.COLLECTIONS) do
        local list = {}
        for _, r in pairs(Store.coll(cname)) do
            if type(r) == "table" and not r.del and not isDemo(r) then list[#list + 1] = clean(r, 1) end
        end
        ex.collections[cname] = list
    end
    return ex
end

-- merged into OasisDB.export by Officer.Snapshot (OfficerData.lua); the interval is there too (10 min + logout)
function Export.Merge(snap)
    if ns.db.settings and ns.db.settings.webExport == false then return snap end
    local ok, ex = pcall(Export.Build)
    if not ok or not ex then return snap end
    for k, v in pairs(ex) do if snap[k] == nil then snap[k] = v end end
    return snap
end

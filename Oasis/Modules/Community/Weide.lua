-- Oasis: Sheep pasture (0.6.539) - every guild member with Oasis walks across the meadow as a sheep.
-- From certain Oasis ranks there are other animals and colors (skins). Size only by depth (0.6.548).
-- Everyone reports their own skin (collection "sheep", OWNED); on display the owner's rank is
-- checked - whoever picks a skin above their rank still appears white to the others.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Community", function()
local K, C, L = ns.K, ns.K.C, ns.L
local Store = ns.Store
local Weide = {}
ns.Weide = Weide

local SHEEP_NPC = 1933        -- sheep (like in Deathroll)
local SHEEP_DISPLAY = 856     -- sheep model (polymorph), works even without the creature in the cache
local MAX_SHEEP = 40          -- more models cost too much performance
local ART = "Interface\\AddOns\\Oasis\\Media\\art\\weide_bg"   -- image only in the guild module
-- walking area (feet), fraction of the meadow height from the top. 0.6.579: the grass in the picture starts at ~41 %;
-- before, the animals walked up to 34 % (tiny, at the tree line, names floating without a visible animal)
local MEADOW_TOP, MEADOW_BOTTOM = 0.52, 0.88   -- 0.6.582: the back row stood at the tree line
local SHADOW = "Interface\\AddOns\\Oasis\\Media\\art\\shadow"   -- 0.6.582: own soft shadow (radial gradient) - the Blizzard mask had a hard edge

-- Skins: light color on the sheep model. lvl = from Oasis rank
Weide.SKINS = {
    { key = "white", text = "White", lvl = 1, amb = { 1, 1, 1 }, ai = 0.8, dif = { 1, 0.95, 0.9 }, di = 0.9 },
    { key = "cream", text = "Cream", lvl = 10, amb = { 1, 0.9, 0.7 }, ai = 0.8, dif = { 1, 0.85, 0.6 }, di = 0.9 },
    { key = "grey", text = "Grey", lvl = 20, amb = { 0.55, 0.55, 0.58 }, ai = 0.7, dif = { 0.6, 0.6, 0.62 }, di = 0.7 },
    { key = "pink", text = "Pink", lvl = 30, amb = { 1, 0.6, 0.78 }, ai = 0.85, dif = { 1, 0.55, 0.75 }, di = 0.9 },
    { key = "blue", text = "Sky blue", lvl = 40, amb = { 0.5, 0.72, 1 }, ai = 0.85, dif = { 0.5, 0.7, 1 }, di = 0.9 },
    { key = "black", text = "Black sheep", lvl = 50, amb = { 0.12, 0.11, 0.13 }, ai = 0.6, dif = { 0.22, 0.2, 0.24 }, di = 0.5 },
    { key = "green", text = "Moss green", lvl = 60, amb = { 0.5, 0.95, 0.45 }, ai = 0.85, dif = { 0.45, 0.9, 0.4 }, di = 0.9 },
    { key = "gold", text = "Gold", lvl = 70, amb = { 1, 0.8, 0.3 }, ai = 0.9, dif = { 1, 0.75, 0.25 }, di = 1 },
    { key = "violet", text = "Purple", lvl = 80, amb = { 0.7, 0.45, 1 }, ai = 0.85, dif = { 0.65, 0.4, 1 }, di = 0.9 },
    { key = "rainbow", text = "Rainbow", lvl = 100, rainbow = true },
}
local BY = {}
for _, s in ipairs(Weide.SKINS) do BY[s.key] = s end
-- 0.6.540: disguises - other animals from higher ranks (creature IDs from the game world; if one doesn't load, it stays a sheep)
Weide.FORMS = {
    { key = "sheep", text = "Sheep", lvl = 1 },
    { key = "rabbit", text = "Rabbit", lvl = 15, npc = 721 },
    { key = "chicken", text = "Chicken", lvl = 25, npc = 620 },
    { key = "toad", text = "Toad", lvl = 35, npc = 1420 },
    { key = "squirrel", text = "Squirrel", lvl = 45, npc = 1412 },
    { key = "prairie", text = "Prairie dog", lvl = 55, npc = 2620 },
    { key = "fawn", text = "Fawn", lvl = 65, npc = 890 },
    { key = "cow", text = "Cow", lvl = 75, npc = 2442 },
    { key = "deer", text = "Stag", lvl = 90, npc = 883 },
}
local FBY = {}
for _, f in ipairs(Weide.FORMS) do FBY[f.key] = f end

local function myRank() return ns.Rank and ns.Rank.Mine and ns.Rank.Mine().level or 1 end
-- 0.6.583: simulation for big guilds (/oa schafsim [n], /oa schafsim aus) - fake animals only on this PC, nothing is sent
Weide.sim = nil
local simRec = {}
local function simIdx(name) return Weide.sim and type(name) == "string" and tonumber(name:match("^Sim(%d+)%-Sim$")) end
function Weide.IsSim(name) return simIdx(name) ~= nil end
local function simLvl(i) return 1 + (i * 37) % 100 end
local function simCare(i)
    local r = simRec[i]
    if r then return r end
    local now = ns.now()
    local roll = (i * 7919) % 100   -- deterministic mix: most happy, some hungry, a few neglected
    local age = roll < 70 and (i * 977) % 30000 or (roll < 92 and 40000 + (i * 331) % 40000 or 200000 + (i * 113) % 300000)
    r = { f = now - age, j = now - age * 0.6, c = now - age * 1.2, sd = date("%Y-%m-%d", now - (roll < 80 and 0 or 86400)),
        sn = (i * 13) % 40, tc = (i * 29) % 400, skin = Weide.SKINS[1 + i % #Weide.SKINS].key, form = (i % 4 == 0) and "sheep" or nil }
    if not r.form then
        local f = Weide.FORMS[1 + (i * 7) % #Weide.FORMS]
        r.form = (simLvl(i) >= f.lvl) and f.key or "sheep"
    end
    simRec[i] = r
    return r
end
function Weide.Simulate(n)
    simRec = {}
    Weide.sim = (n and n > 0) and math.min(100, n) or nil
    if ns.RefreshPage then ns.RefreshPage("pasture", true) end
    if Weide.sim and ns.ShowPage then ns.ShowPage("pasture") end
end
local function rankOf(name)
    local si = simIdx(name)
    if si then return simLvl(si) end
    if ns.isMe(name) then return myRank() end
    return (ns.Rank and ns.Rank.Of and ns.Rank.Of(name)) or 1
end
-- a member's skin - only if their rank allows it (otherwise white)
function Weide.SkinOf(name, lvl)
    local key
    local si = simIdx(name)
    if si then key = simCare(si).skin
    elseif ns.isMe(name) then key = ns.db.settings.sheepSkin
    else local r = Store.Get("sheep", "shp-" .. ns.NameKey(name)) key = r and r.skin end
    local s = BY[key or ""]
    if not s or (lvl or 1) < s.lvl then return BY.white end
    return s
end
function Weide.FormOf(name, lvl)
    local key
    local si = simIdx(name)
    if si then key = simCare(si).form
    elseif ns.isMe(name) then key = ns.db.settings.sheepForm
    else local r = Store.Get("sheep", "shp-" .. ns.NameKey(name)) key = r and r.form end
    local f = FBY[key or ""]
    if not f or (lvl or 1) < f.lvl then return FBY.sheep end
    return f
end
function Weide.SetMyForm(key)
    local f = FBY[key]
    if not f or myRank() < f.lvl then return false end
    ns.db.settings.sheepForm = key
    Weide.Report()
    return true
end
function Weide.SetMySkin(key)
    local s = BY[key]
    if not s or myRank() < s.lvl then return false end
    ns.db.settings.sheepSkin = key
    Weide.Report()
    return true
end

-- 0.6.540 Gildotchi: three needs, each drops from 100 to 0 in "span" seconds after the last care
Weide.NEEDS = {
    { key = "f", text = "Fed", act = "Feed", span = 24 * 3600, cd = 3 * 3600, say = "Hungry!" },
    { key = "j", text = "Happy", act = "Pet", span = 12 * 3600, cd = 1 * 3600, say = "Pet me!" },
    { key = "c", text = "Groomed", act = "Brush", span = 48 * 3600, cd = 8 * 3600, say = "I am all scruffy!" },
}
local function careRec(name)
    local si = simIdx(name)
    if si then return simCare(si) end
    if ns.isMe(name) then ns.db.settings.gildotchi = ns.db.settings.gildotchi or {} return ns.db.settings.gildotchi end
    local r = Store.Get("sheep", "shp-" .. ns.NameKey(name))
    return r or {}
end
-- values 0-100 per need + mood (average); without any care a sheep starts half content
-- 0.6.548: guild helps - most recent feeding by others (collection "gfeed", everyone reports only themselves)
function Weide.GuildFed(name)
    local key, best, by = ns.NameKey(name), nil, nil
    for _, g in ipairs(Store.List("gfeed")) do
        if g.target == key and not g.kind and (tonumber(g.ts) or 0) > (best or 0) then best, by = tonumber(g.ts), g.by end
    end
    return best, by
end
-- 0.6.580: friends - members who fed each other's animals lately; their animals like to graze side by side
function Weide.Friends()
    local fed, out = {}, {}
    for _, g in ipairs(Store.List("gfeed")) do
        if not g.kind and g.by and g.target then
            local a = ns.NameKey(g.by)
            fed[a] = fed[a] or {}
            fed[a][g.target] = (fed[a][g.target] or 0) + 1
        end
    end
    for a, list in pairs(fed) do
        local best, score
        for b, n in pairs(list) do
            local sc = n + ((fed[b] and fed[b][a]) and 10 or 0)   -- mutual counts much more
            if not score or sc > score then best, score = b, sc end
        end
        out[a] = best
        if best and not out[best] then out[best] = a end   -- the one fed walks to the feeder as well
    end
    return out
end
-- 0.6.580: small reactions to someone else's animal (no free text): heart, wave, cheer - shown to everyone on the pasture
Weide.REACTS = {
    { text = "Send a heart", say = "%s sends a heart!", icon = "heart" },
    { text = "Wave", say = "%s waves!", icon = "smile" },
    { text = "Cheer", say = "%s cheers!", icon = "star_on" },
}
local lastReact = {}
function Weide.React(name, idx)
    local r = Weide.REACTS[idx]
    if not r or not name or ns.isMe(name) or not IsInGuild() or Weide.IsSim(name) then return false end
    local key = ns.NameKey(name)
    if (lastReact[key] or 0) > ns.now() - 600 then return false end   -- at most every 10 minutes per animal
    lastReact[key] = ns.now()
    Store.Put("gfeed", { id = "gr-" .. ns.NameKey(ns.me()) .. "-" .. key .. "-" .. ns.now(), kind = "r", e = idx, target = key, by = ns.me(), ts = ns.now() })
    return true
end
-- reactions for an animal not yet seen on this PC (newest first, at most a day old)
function Weide.NewReacts(name)
    local key, out = ns.NameKey(name), {}
    ns.db.settings.gotchiSeen = ns.db.settings.gotchiSeen or {}
    local seen = ns.db.settings.gotchiSeen
    for _, g in ipairs(Store.List("gfeed")) do
        if g.kind == "r" and g.target == key and not seen[g.id] and (tonumber(g.ts) or 0) > ns.now() - 86400 and Weide.REACTS[tonumber(g.e) or 0] then
            out[#out + 1] = g
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
    return out
end
local function today(off) return date("%Y-%m-%d", (ns.now() + (off or 0) * 86400)) end
-- last care at all (own or by the guild); nil = never cared for
function Weide.LastCare(name)
    local r, last = careRec(name), nil
    for _, n in ipairs(Weide.NEEDS) do local t = tonumber(r[n.key]) if t and t > (last or 0) then last = t end end
    local gf = Weide.GuildFed(name)
    if gf and gf > (last or 0) then last = gf end
    return last
end
-- 0.6.548: after 7 days without care the animal is away (not on the pasture, "Bring back" returns it immediately).
-- 0.6.579: told as "visiting grandma's farm" - no punishment, it comes back any time
Weide.AWAY = 7 * 86400
function Weide.IsAway(name)
    local last = Weide.LastCare(name)
    return last ~= nil and ns.now() - last > Weide.AWAY
end
function Weide.Recall()
    local g = careRec(ns.me())
    for _, n in ipairs(Weide.NEEDS) do g[n.key] = ns.now() - n.span * 0.5 end   -- back to half content
    Weide.welcome = true
    Weide.Report()
end
-- 0.6.548: care streak - consecutive days with at least one care; only counts if cared for today or yesterday
-- 0.6.579: one missed day per week is forgiven (like a streak freeze) - a long streak does not drop to zero at once
local function week(off) return date("%Y-%W", ns.now() + (off or 0) * 86400) end
function Weide.Streak(name)
    local r = careRec(name)
    if r.sd == today() or r.sd == today(-1) then return tonumber(r.sn) or 0 end
    if r.sd == today(-2) and r.fz ~= week() then return tonumber(r.sn) or 0 end
    return 0
end
-- 0.6.581: care book - small memories with the date they happened (only on this PC, nothing is sent)
Weide.BOOK = {
    { key = "first", text = "First care" },
    { key = "st3", text = "3 days in a row" }, { key = "st7", text = "A whole week" }, { key = "st14", text = "Two weeks of care" }, { key = "st30", text = "A month together" },
    { key = "helper", text = "Fed someone else's animal" },
    { key = "gift", text = "First gift at the fence" },
    { key = "friend", text = "Found a friend" },
    { key = "react", text = "Got a hello from the guild" },
    { key = "brush", text = "Brushed out all the burrs" },
    { key = "fest", text = "Celebrated a flock festival" },
    { key = "t1", text = "Became a Shepherd" }, { key = "t2", text = "Became a Herder" },
    { key = "t3", text = "Became a Flock master" }, { key = "t4", text = "Became a Legendary shepherd" },
}
function Weide.Note(key)
    local g = ns.db.settings.gildotchi
    if not g then ns.db.settings.gildotchi = {} g = ns.db.settings.gildotchi end
    g.ms = g.ms or {}
    if g.ms[key] then return false end
    g.ms[key] = date("%d.%m.%Y")
    local def
    for _, b in ipairs(Weide.BOOK) do if b.key == key then def = b end end
    if def and K.Toast then K.Toast(L["Care book"], L[def.text], C.accent2 or C.mint) end
    return true
end
-- 0.6.579: lifetime care count -> shepherd titles (only grow, never lost)
Weide.TITLES = {
    { n = 10, text = "Shepherd" }, { n = 50, text = "Herder" }, { n = 150, text = "Flock master" }, { n = 365, text = "Legendary shepherd" },
}
function Weide.Title(name)
    local tc, best = tonumber(careRec(name).tc) or 0, nil
    for _, t in ipairs(Weide.TITLES) do if tc >= t.n then best = t end end
    return best, tc
end
-- 0.6.579: weekly flock festival - all cares of the guild this week fill one shared bar (everyone reports only their own count)
function Weide.WeekCares(name)
    local r = careRec(name)
    return (r.wk == week()) and (tonumber(r.wn) or 0) or 0
end
function Weide.Festival(flockSize)
    local sum = Weide.WeekCares(ns.me())
    for _, r in ipairs(Store.List("sheep")) do
        if r.by and not ns.isMe(r.by) and r.wk == week() then sum = sum + (tonumber(r.wn) or 0) end
    end
    -- goal grows with the flock, but stays reachable: ~6 cares per active member and week
    local goal = math.max(20, math.min(300, 6 * math.max(3, flockSize or 3)))
    return sum, goal, sum >= goal
end
Weide.EXTRAS = {
    { n = 3, text = "Sparkle" },
    { n = 7, text = "Star by the name" },
    { n = 14, text = "Golden name" },
    { n = 30, text = "Crown" },
}
function Weide.Needs(name)
    local r, out, sum = careRec(name), {}, 0
    local gf = Weide.GuildFed(name)
    for _, n in ipairs(Weide.NEEDS) do
        local ts = tonumber(r[n.key])
        if n.key == "f" and gf and gf > (ts or 0) then ts = gf end
        local v = ts and math.max(0, math.min(100, 100 - (ns.now() - ts) / n.span * 100)) or 50
        out[n.key] = v
        sum = sum + v
    end
    out.mood = sum / #Weide.NEEDS
    return out
end
function Weide.MoodText(m)
    if m >= 75 then return "Happy", C.mint elseif m >= 45 then return "Content", C.text
    elseif m >= 20 then return "Grumpy", C.amber or C.accent else return "Sad", C.accent end
end
function Weide.Report()
    if not IsInGuild() then return end
    local g = ns.db.settings.gildotchi or {}
    Store.Put("sheep", { id = "shp-" .. ns.NameKey(ns.me()), skin = ns.db.settings.sheepSkin, form = ns.db.settings.sheepForm,
        f = g.f, j = g.j, c = g.c, sd = g.sd, sn = g.sn, fz = g.fz, tc = g.tc, wk = g.wk, wn = g.wn, by = ns.me(), ts = ns.now() })
end
local report = function() Weide.Report() end
local function fmtLeft(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return ("%d Std. %d Min."):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%d min"):format(math.max(1, math.ceil(sec / 60)))
end
-- Care: true or false + remaining time in seconds
function Weide.Care(key)
    local g = careRec(ns.me())
    for _, n in ipairs(Weide.NEEDS) do
        if n.key == key then
            local left = (tonumber(g[key]) or 0) + n.cd - ns.now()
            if left > 0 then return false, left end
            local before = Weide.LastCare(ns.me())
            g[key] = ns.now()
            -- Streak: already counted today? else yesterday -> +1, a day missed once this week -> +1 (freeze used),
            -- longer ago -> restart at 1
            if g.sd ~= today() then
                if g.sd == today(-1) then g.sn = (tonumber(g.sn) or 0) + 1
                elseif g.sd == today(-2) and g.fz ~= week() then g.sn = (tonumber(g.sn) or 0) + 1 g.fz = week()
                else g.sn = 1 end
                g.sd = today()
            end
            g.tc = (tonumber(g.tc) or 0) + 1
            Weide.Note("first")
            for _, n2 in ipairs({ 3, 7, 14, 30 }) do if (tonumber(g.sn) or 0) >= n2 then Weide.Note("st" .. n2) end end
            for i, t in ipairs(Weide.TITLES) do if g.tc >= t.n then Weide.Note("t" .. i) end end
            if g.wk ~= week() then g.wk, g.wn = week(), 0 end
            g.wn = (tonumber(g.wn) or 0) + 1
            report()
            -- 0.6.579: welcome back after a longer break - joy instead of reproach
            Weide.welcome = before and (ns.now() - before) > 3 * 86400 or nil
            return true
        end
    end
    return false, 0
end

-- 0.6.579: whoever feeds someone else's animal leaves a small gift at the fence (fixed icons, no free text)
Weide.GIFTS = {
    { text = "Apple", icon = "Interface\\Icons\\INV_Misc_Food_19" },
    { text = "Flower", icon = "Interface\\Icons\\INV_Misc_Flower_02" },
    { text = "Bread", icon = "Interface\\Icons\\INV_Misc_Food_11" },
    { text = "Clover", icon = "Interface\\Icons\\INV_Misc_Herb_11" },
}
-- gifts / feedings for an animal in the last days (newest first): { by, gift, ts }
function Weide.Gifts(name)
    local key, out = ns.NameKey(name), {}
    for _, g in ipairs(Store.List("gfeed")) do
        if g.target == key and g.by and not g.kind then out[#out + 1] = { by = g.by, gift = Weide.GIFTS[tonumber(g.gift) or 0], ts = tonumber(g.ts) or 0 } end
    end
    table.sort(out, function(a, b) return a.ts > b.ts end)
    return out
end
-- feed someone else's animal: once a day per animal
function Weide.FeedOther(name)
    if not name or ns.isMe(name) or not IsInGuild() or Weide.IsSim(name) then return false end
    local id = "gf-" .. ns.NameKey(ns.me()) .. "-" .. ns.NameKey(name) .. "-" .. today()
    if Store.Get("gfeed", id) then return false, "today" end
    Store.Put("gfeed", { id = id, target = ns.NameKey(name), by = ns.me(), ts = ns.now(), gift = math.random(#Weide.GIFTS) })
    Weide.Note("helper")
    -- helping counts toward the weekly flock festival too
    local g = careRec(ns.me())
    if g.wk ~= week() then g.wk, g.wn = week(), 0 end
    g.wn = (tonumber(g.wn) or 0) + 1
    report()
    local f = Weide.FormOf(name, (ns.Rank and ns.Rank.Of and ns.Rank.Of(name)) or 1)
    if ns.Chronicle and ns.Chronicle.Add then
        pcall(ns.Chronicle.Add, "guild", "gfc-" .. id, "fed %s", { (L["%s's %s"]):format(ns.short(name), L[f.text]) })
    end
    return true
end

-- Who is on the pasture? Mains with Oasis, seen in the last 14 days
function Weide.Flock()
    local out = {}
    Weide.away = {}
    if Weide.sim then
        out[1] = { name = ns.me(), lvl = myRank(), online = true }
        for i = 1, Weide.sim - 1 do
            local nm = "Sim" .. i .. "-Sim"
            out[#out + 1] = { name = nm, lvl = simLvl(i), online = i % 3 ~= 0, away = Weide.IsAway(nm) }
        end
        table.sort(out, function(a, b) if a.lvl ~= b.lvl then return a.lvl > b.lvl end return a.name < b.name end)
        return out
    end
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local p = ns.db.members and ns.db.members[m.name]
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        local uses = ns.isMe(m.name) or (type(p) == "table" and p.v and ns.now() - (p.seen or 0) < 14 * 86400)
        if uses and not isAlt then
            local lvl = rankOf(m.name)
            local row = { name = m.name, lvl = lvl, online = m.online or ns.isMe(m.name), away = Weide.IsAway(m.name) }
            out[#out + 1] = row
        end
    end
    if not IsInGuild() or #out == 0 then out[#out + 1] = { name = ns.me(), lvl = myRank(), online = true } end
    table.sort(out, function(a, b) if a.lvl ~= b.lvl then return a.lvl > b.lvl end return a.name < b.name end)
    return out
end

local function light(m, s, r, g, b)
    if not (m.SetLight and CreateVector3D and CreateColor) then return end
    local amb, dif, ai, di = s.amb, s.dif, s.ai, s.di
    if s.rainbow then amb, dif, ai, di = { r, g, b }, { r, g, b }, 0.85, 0.9 end
    -- 0.6.548: neglected -> color toward gray, a bit darker
    local sad = m.sad or 0
    if sad > 0 then
        local function mix(c) return { c[1] + (0.5 - c[1]) * sad * 0.7, c[2] + (0.5 - c[2]) * sad * 0.7, c[3] + (0.5 - c[3]) * sad * 0.7 } end
        amb, dif, ai, di = mix(amb), mix(dif), ai * (1 - 0.3 * sad), di * (1 - 0.3 * sad)
    end
    pcall(m.SetLight, m, true, {
        omnidirectional = false, point = CreateVector3D(-0.6, 1, -0.6),
        ambientIntensity = ai, ambientColor = CreateColor(amb[1], amb[2], amb[3]),
        diffuseIntensity = di, diffuseColor = CreateColor(dif[1], dif[2], dif[3]),
    })
end

------------------------------------------------------------------------
-- One sheep: own model, walks to random targets, sometimes stops and grazes
------------------------------------------------------------------------
-- load animal into a model; if it doesn't load (not in cache), it becomes a sheep
function Weide.LoadForm(m, f)
    pcall(m.ClearModel, m)
    if f and f.npc then
        pcall(m.SetCreature, m, f.npc)
    else
        local ok = m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, SHEEP_DISPLAY)
        if not ok then pcall(m.SetCreature, m, SHEEP_NPC) end
    end
    C_Timer.After(0.5, function()
        local okm, id = pcall(m.GetModelFileID, m)
        if not okm or not id or id == 0 then
            local ok2 = m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, SHEEP_DISPLAY)
            if not ok2 then pcall(m.SetCreature, m, SHEEP_NPC) end
        end
    end)
end
local function newSheep(field)
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, field)
    if not ok or not m then return nil end
    m:EnableMouse(true)
    function m:LoadSheep() Weide.LoadForm(self, self.form) end
    m:LoadSheep()
    m:SetScript("OnShow", function(self)
        local okm, id = pcall(self.GetModelFileID, self)
        if not okm or not id or id == 0 then self:LoadSheep() end
    end)
    -- name (subtle) and above it the speech bubble - own frame directly above this animal (0.6.546)
    m.lab = CreateFrame("Frame", nil, field)
    m.lab:SetAllPoints(m)
    m.name = K.Text(m.lab, 12, C.text, "CENTER")
    m.name:SetPoint("BOTTOM", m, "TOP", 0, -14)
    do local fnt, sz = m.name:GetFont() if fnt then m.name:SetFont(fnt, sz or 12, "OUTLINE") end end
    m.name:SetDrawLayer("OVERLAY", 6)
    m.name:SetShadowOffset(1, -1)
    m.name:SetShadowColor(0, 0, 0, 0.9)
    m.name:SetAlpha(0.95)
    m.say = K.Text(m.lab, 11, C.text, "CENTER")
    m.say:SetPoint("BOTTOM", m.name, "TOP", 0, 5)
    m.say:SetDrawLayer("OVERLAY", 7)
    m.sayBg = m.lab:CreateTexture(nil, "OVERLAY")
    m.sayBg:SetColorTexture(0, 0, 0, 0.55)
    m.sayBg:SetPoint("TOPLEFT", m.say, "TOPLEFT", -6, 3)
    m.sayBg:SetPoint("BOTTOMRIGHT", m.say, "BOTTOMRIGHT", 6, -3)
    m.say:Hide() m.sayBg:Hide()
    m.sayIn = 3 + math.random() * 20
    m:SetScript("OnModelLoaded", function(self)
        pcall(self.SetPortraitZoom, self, 0)
        pcall(self.SetCamDistanceScale, self, 0.85)   -- closer: animal fills the frame
        pcall(self.SetPosition, self, 0, 0, 0)
        if self.skin then light(self, self.skin, 1, 1, 1) end
        self.anim = nil
        if self.sleeping then pcall(self.SetRoll, self, math.pi) pcall(self.SetPaused, self, true) end   -- 0.6.582: stays on its back after reloading
    end)
    m:SetScript("OnEnter", function(self)
        if not self.who then return end
        self.hover = true
        self.nameHidden = nil self.name:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.short(self.who.name), 1, 1, 1)
        GameTooltip:AddLine((L["Oasis rank %d"]):format(self.who.lvl), C.accent2[1], C.accent2[2], C.accent2[3])
        GameTooltip:AddLine(L[self.form and self.form.text or "Sheep"] .. " - " .. L[self.skin and self.skin.text or "White"], 0.8, 0.8, 0.8)
        local nd = Weide.Needs(self.who.name)
        local mt, mc = Weide.MoodText(nd.mood)
        GameTooltip:AddLine(L["Mood"] .. ": " .. L[mt], mc[1], mc[2], mc[3])
        local st = Weide.Streak(self.who.name)
        if st >= 2 then GameTooltip:AddLine((L["Cared for %d days in a row"]):format(st), 1, 0.82, 0.3) end
        local tt, tc = Weide.Title(self.who.name)
        if tt then GameTooltip:AddLine(L[tt.text] .. "  |cff9a9a9a" .. (L["%d cares in total"]):format(tc) .. "|r", 0.55, 0.85, 1) end
        if not self.who.online then GameTooltip:AddLine(L["Dozing - the owner is offline"], 0.6, 0.6, 0.7) end
        if not ns.isMe(self.who.name) then GameTooltip:AddLine(L["Click: feed or say hello"], 0.6, 0.8, 1) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function(self) self.hover = nil GameTooltip:Hide() end)
    -- 0.6.580: click on someone else's animal: feed (once a day) or send a small reaction
    m:SetScript("OnMouseUp", function(self)
        if not self.who then return end
        -- 0.6.581: your own animal: a click pets it (counts as "Pet" when it is due, otherwise just a happy reaction)
        if ns.isMe(self.who.name) then
            local ok = Weide.Care("j")
            self:Hearts()
            self.say:SetText(ok and L["Baa! Thanks!"] or L["Baa!"]) self.say:Show() self.sayBg:Show() self.sayLeft = 2.5
            if ok then ns.RefreshPage("pasture", true) end
            return
        end
        local who = self.who.name
        local items = { { text = L["Feed (once a day)"], fn = function()
            local ok = Weide.FeedOther(who)
            if ok then
                K.Toast(L["Guildotchi"], (L["You fed %s and left a little gift at the fence."]):format(ns.short(who)), C.mint)
                self.say:SetText(L["Baa! Thanks!"]) self.say:Show() self.sayBg:Show() self.sayLeft = 3
                self:Hearts()
                ns.RefreshPage("pasture", true)
            else
                K.Toast(L["Guildotchi"], L["Already fed today - again tomorrow."], C.amber or C.accent)
            end
        end } }
        for i, r in ipairs(Weide.REACTS) do
            items[#items + 1] = { text = "|T" .. ns.MEDIA .. "icons\\" .. r.icon .. ":14|t " .. L[r.text], fn = function()
                if Weide.React(who, i) then
                    self.say:SetText((L[r.say]):format(ns.short(ns.me()))) self.say:Show() self.sayBg:Show() self.sayLeft = 3
                    if i == 1 then self:Hearts() end
                else
                    K.Toast(L["Guildotchi"], L["One reaction per animal every 10 minutes."], C.amber or C.accent)
                end
            end }
        end
        K.ShowMenu(self, items, ns.short(who))
    end)
    -- sparkle (care streak of 3+ days)
    m.spark = {}
    for i = 1, 3 do
        local t = m.lab:CreateTexture(nil, "OVERLAY")
        t:SetTexture(ns.MEDIA .. "icons\\star_on")
        t:SetVertexColor(1, 0.9, 0.5)
        t:SetSize(10, 10)
        t:Hide()
        m.spark[i] = t
    end
    -- 0.6.579: soft ground shadow (on the meadow, below every model) - the animals stand on the grass instead of floating
    m.shadow = field:CreateTexture(nil, "ARTWORK")
    m.shadow:SetTexture(SHADOW)
    m.shadow:SetVertexColor(1, 1, 1, 1)
    m.shadow:Hide()
    -- 0.6.579: little hearts rise when the animal is cared for or fed
    m.hearts = {}
    for i = 1, 4 do
        local t = m.lab:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(ns.MEDIA .. "icons\\heart")
        t:SetVertexColor(1, 0.45, 0.6)
        t:SetSize(14, 14)
        t:Hide()
        m.hearts[i] = t
    end
    function m:Hearts() self.heartT = 0 end
    return m
end
-- 0.6.547: baa sound (CC0, "Sheep Baa" by AntumDeluge after mikewest, opengameart.org/node/132779) - only with guild module,
-- follows the Oasis volume slider, only while the meadow is visible
-- 0.6.557: every baa of a sheep can be heard (sounds may overlap), randomly from five voices;
-- four of them CC0 by Joseph Sardin / BigSoundBank (sheep 3, 4, 5, 7)
local SND = "Interface\\AddOns\\Oasis\\Media\\sounds\\"
local VOICES = { "maeh", "maeh03", "maeh04", "maeh05", "maeh07" }
function Weide.Maeh()
    if not ns.ART or ns.db.settings.gotchiSound == false then return end
    local vol = math.floor(tonumber(ns.db.settings.soundVol or 14) or 14)
    if vol <= 0 then return end
    local dir = SND .. VOICES[math.random(#VOICES)] .. "\\"
    vol = math.min(vol, 20)
    while vol > 0 do
        local lv = math.min(10, vol)
        vol = vol - lv
        pcall(PlaySoundFile, dir .. lv .. ".ogg", "Master")
    end
end
-- 0.6.582: sleeping = lying on its back as a still picture (rolled over, animation paused) - works for every model,
-- the creature sleep animation did not exist for all of them
local function setSleep(m, on)
    if (m.sleeping or false) == (on or false) then return end
    m.sleeping = on or nil
    if on then
        if m.anim ~= 0 then m.anim = 0 pcall(m.SetAnimation, m, 0) end
        pcall(m.SetRoll, m, math.pi)
        pcall(m.SetPaused, m, true)
    else
        pcall(m.SetRoll, m, 0)
        pcall(m.SetPaused, m, false)
    end
end
local function setAnim(m, id)
    if m.anim ~= id then m.anim = id pcall(m.SetAnimation, m, id) end
end
-- too close to another animal? (x across in fractions of width, y = depth)
local GAP_X, GAP_Y = 0.13, 0.12   -- 0.6.548: clearly more distance
-- 0.6.558: distance by actual size (like when drawing: 0.35 + 1.25 * y^1.8) - at the front the animals were
-- three times as wide as the fixed distance and walked into each other
-- 0.6.579: gentler perspective - at the back still clearly visible (0.42), at the front 1.42 (before 0.16 .. 1.60)
-- 0.6.584: big flocks - all animals shrink with the number on the meadow (100 animals at full size were one big heap);
-- distances and walking room use the same factor
local crowdScale = 1
local function bodyW(y) return (0.42 + 1.0 * (y or 0) ^ 1.35) * crowdScale end
local function crowded(s, x, y, flock)
    for _, o in ipairs(flock or {}) do
        if o ~= s and o:IsShown() and o.who then
            local need = 0.17 * (bodyW(y) + bodyW(o.y))   -- 0.6.559: from the side a sheep is almost twice as long as wide
            local needY = GAP_Y * (0.9 + 0.9 * math.max(y, o.y)) * crowdScale
            if math.abs(o.x - x) < need and math.abs(o.y - y) < needY then return o end
        end
    end
end
-- 0.6.549: target with as much room as possible - of 10 candidates (half nearby, half anywhere on the meadow)
-- the one with the largest distance to the nearest animal wins -> the herd spreads over the whole area
local function room(s, x, y, flock)
    local best = 9
    for _, o in ipairs(flock or {}) do
        if o ~= s and o:IsShown() and o.who then
            local ox, oy = o.tx or o.x, o.ty or o.y   -- also where the others are currently heading
            local d = math.sqrt((ox - x) ^ 2 + ((oy - y) * 1.3) ^ 2)
            -- 0.6.555: at the front animals are up to three times as big - the same distance looks much tighter there
            d = d / ((0.45 + 0.9 * math.max(y, oy)) * crowdScale)
            if d < best then best = d end
        end
    end
    return best
end
-- 0.6.562: too close -> slowly push apart without turning around (before: run away, block, turn -> jitter)
local function push(s, o, dt)
    local dx, dy = s.x - o.x, s.y - o.y
    if math.abs(dx) + math.abs(dy) < 0.001 then dx = (math.random() - 0.5) end
    local len = math.sqrt(dx * dx + dy * dy)
    s.x = math.max(0.02, math.min(0.98, s.x + dx / len * 0.05 * dt))
    s.y = math.max(0, math.min(1, s.y + dy / len * 0.05 * dt))
end
local function pickTarget(s, flock)
    -- 0.6.580: friends graze side by side - now and then walk next to the friend's animal
    if s.friend and math.random() < 0.45 then
        for _, o in ipairs(flock or {}) do
            if o ~= s and o:IsShown() and o.who and ns.NameKey(o.who.name) == s.friend then
                local side = (o.x > 0.5) and -1 or 1
                s.tx = math.max(0.03, math.min(0.97, o.x + side * (0.07 + 0.06 * o.y)))
                s.ty = math.max(0, math.min(1, o.y + (math.random() - 0.5) * 0.08))
                s.wait = nil
                return
            end
        end
    end
    local bx, by, bs = s.x, s.y, -1
    for i = 1, 10 do
        local x, y
        if i % 2 == 0 then
            x, y = 0.03 + math.random() * 0.94, math.random() ^ 1.8   -- 0.6.562: clearly more likely at the back (more room there)
        else
            x = math.max(0.02, math.min(0.98, s.x + (math.random() - 0.5) * 0.5))
            y = math.max(0, math.min(1, s.y + (math.random() - 0.5) * 0.6))   -- y: 0 = back (small), 1 = front (big)
        end
        local sc = room(s, x, y, flock)
        if sc > bs then bx, by, bs = x, y, sc end
    end
    s.tx, s.ty = bx, by
    s.wait = nil
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local LIST_W = 190   -- 0.6.546: narrower, more room for the meadow
ns.RegisterPage({
    key = "pasture", title = "Guildotchi", order = 7.64,
    sub = "Every guild member with Oasis has an animal on the pasture - feed, pet and brush it. Higher ranks unlock new animals and colours.",
    build = function(p)
        -- Meadow
        local field = CreateFrame("Frame", nil, p)
        field:SetPoint("TOPLEFT", 4, -4)   -- room for the frame
        field:SetPoint("BOTTOMRIGHT", -(LIST_W + 24), 76)   -- 0.6.582: two rows below the meadow
        -- no SetClipsChildren: 3D models are not drawn in clipped frames (0.6.540)
        p.field = field
        field.bg = field:CreateTexture(nil, "BACKGROUND")
        field.bg:SetAllPoints()
        field.bg:SetColorTexture(0.32, 0.55, 0.22, 1)   -- without guild module: plain green meadow
        if ns.ART then   -- flag: guild module loaded
            field.bg:SetTexture(ART)
            field.bg:SetTexCoord(0, 1, 0, 0.75)
        end
        K.Border(field, C.line)
        -- 0.6.543: frame in the style of the logo (gold, petrol inner edge, gems), 9-slice so the corners stay sharp
        if ns.ART then
            local fr = CreateFrame("Frame", nil, p)
            fr:SetPoint("TOPLEFT", field, "TOPLEFT", -6, 6)
            fr:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 7, -12)   -- 0.6.555: meadow stuck out at the bottom   -- at the bottom the band sits higher in the image (edge 53 instead of 43 px)
            fr:SetFrameLevel(field:GetFrameLevel() + 55)
            -- 0.6.552: frame from the template (1448x1086, as 1024x768 in 1024x1024): corners and center ornament undistorted, edges stretched
            local TEX = "Interface\\AddOns\\Oasis\\Media\\art\\gildotchi_frame"
            local SW, SH, KK = 1448, 1086, 0.3
            local function piece(x1, y1, x2, y2)
                local x = fr:CreateTexture(nil, "OVERLAY")
                x:SetTexture(TEX)
                x:SetTexCoord(x1 / SW, x2 / SW, y1 / SH * 0.75, y2 / SH * 0.75)
                x:SetSize((x2 - x1) * KK, (y2 - y1) * KK)
                return x
            end
            local CO, EW = 115, 60          -- corner size, edge thickness (template)
            local tl, tr = piece(0, 0, CO, CO), piece(SW - CO, 0, SW, CO)
            local bl, br = piece(0, SH - CO, CO, SH), piece(SW - CO, SH - CO, SW, SH)
            tl:SetPoint("TOPLEFT") tr:SetPoint("TOPRIGHT") bl:SetPoint("BOTTOMLEFT") br:SetPoint("BOTTOMRIGHT")
            local tm, bm = piece(600, 0, 848, 80), piece(600, SH - 80, 848, SH)
            tm:SetPoint("TOP") bm:SetPoint("BOTTOM")
            local lm, rm = piece(0, 505, EW, 585), piece(SW - EW, 505, SW, 585)
            lm:SetPoint("LEFT") rm:SetPoint("RIGHT")
            local function hseg(a, b, y1, y2, top)
                local x = piece(300, y1, 500, y2)
                if top then x:SetPoint("TOPLEFT", a, "TOPRIGHT") x:SetPoint("TOPRIGHT", b, "TOPLEFT")
                else x:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT") x:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT") end
            end
            hseg(tl, tm, 0, EW, true) hseg(tm, tr, 0, EW, true)
            hseg(bl, bm, SH - EW, SH, false) hseg(bm, br, SH - EW, SH, false)
            local function vseg(a, b, x1, x2, left)
                local x = piece(x1, 250, x2, 450)
                if left then x:SetPoint("TOPLEFT", a, "BOTTOMLEFT") x:SetPoint("BOTTOMLEFT", b, "TOPLEFT")
                else x:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT") x:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT") end
            end
            vseg(tl, lm, 0, EW, true) vseg(lm, bl, 0, EW, true)
            vseg(tr, rm, SW - EW, SW, false) vseg(rm, br, SW - EW, SW, false)
            p.frameArt = fr
        end
        -- 0.6.542: logo top center, sticks out over the meadow (only with guild module)
        if ns.ART then
            local logo = CreateFrame("Frame", nil, p)
            logo:SetSize(210, 77)   -- 0.6.547: smaller
            logo:SetPoint("TOP", field, "TOP", 0, 24)
            logo:SetFrameLevel(field:GetFrameLevel() + 70)
            logo.t = logo:CreateTexture(nil, "OVERLAY")
            logo.t:SetAllPoints()
            logo.t:SetTexture("Interface\\AddOns\\Oasis\\Media\\art\\gildotchi_logo")
            logo.t:SetTexCoord(0, 1, 0, 187 / 256)
            p.logo = logo
        end
        field.sheep = {}
        field.empty = K.Text(field, 13, C.text, "CENTER")
        field.empty:SetPoint("CENTER")

        -- Movement: one OnUpdate for all sheep
        local tick, hue, sortT = 0, 0, 0
        local order = {}
        field:SetScript("OnUpdate", function(self, dt)
            dt = math.min(dt or 0, 0.1)
            local W, H = self:GetWidth(), self:GetHeight()
            if not W or W < 50 then return end
            tick, hue = tick + dt, (hue + dt * 0.15) % 1
            local rb = tick > 0.12
            if rb then tick = 0 end
            -- 0.6.546: draw order by depth - an animal further front is always in front of those behind (own layer per animal)
            sortT = sortT + dt
            if sortT > 0.1 then
                sortT = 0
                wipe(order)
                for _, s in ipairs(self.sheep) do if s:IsShown() then order[#order + 1] = s end end
                table.sort(order, function(a, b) return a.y < b.y end)
                local base = self:GetFrameLevel() + 2
                for i, s in ipairs(order) do
                    local lv = base + i * 3
                    if s.lvlSet ~= lv then
                        s.lvlSet = lv
                        s:SetFrameLevel(lv)
                        s.lab:SetFrameLevel(lv + 1)
                    end
                end
            end
            -- 0.6.548: Deathroll - rarely two animals walk together and roll until one gets the 1 (visual only, everyone sees their own)
            self.duelIn = (self.duelIn or (90 + math.random() * 120)) - dt
            if self.duelIn <= 0 and not self.duel then
                self.duelIn = 180 + math.random() * 180
                local cand = {}
                for _, s in ipairs(self.sheep) do if s:IsShown() and s.who and not s.lying then cand[#cand + 1] = s end end
                if #cand >= 2 then
                    local a = table.remove(cand, math.random(#cand))
                    local b = table.remove(cand, math.random(#cand))
                    local mx, my = (a.x + b.x) / 2, math.max(0.15, math.min(0.9, (a.y + b.y) / 2))
                    self.duel = { a = a, b = b, phase = "walk", t = 0, max = 100, turn = a }
                    a.duel, b.duel = self.duel, self.duel
                    a.tx, a.ty, a.wait = math.max(0.03, mx - 0.05), my, nil
                    b.tx, b.ty, b.wait = math.min(0.97, mx + 0.05), my, nil
                end
            end
            local du = self.duel
            if du then
                du.t = du.t + dt
                local function say(sh, txt, sec) sh.say:SetText(txt) sh.say:Show() sh.sayBg:Show() sh.sayLeft = sec or 1.5 end
                if du.phase == "walk" then
                    local da = math.abs(du.a.x - du.a.tx) + math.abs(du.a.y - du.a.ty)
                    local db = math.abs(du.b.x - du.b.tx) + math.abs(du.b.y - du.b.ty)
                    if (da < 0.02 and db < 0.02) or du.t > 25 then
                        du.phase, du.t = "roll", 0
                        pcall(du.a.SetFacing, du.a, -1.5708) du.a.face = -1.5708   -- look at each other
                        pcall(du.b.SetFacing, du.b, 1.5708) du.b.face = 1.5708
                        say(du.a, L["Death roll?"], 1.6)
                    end
                elseif du.phase == "roll" and du.t > 1.8 then
                    du.t = 0
                    local roll = math.random(1, du.max)
                    say(du.turn, ("%d (1-%d)"):format(roll, du.max), 1.7)
                    if roll == 1 then
                        local other = du.turn == du.a and du.b or du.a
                        du.phase, du.loser, du.winner = "end", du.turn, other
                    else
                        du.max = roll
                        du.turn = du.turn == du.a and du.b or du.a
                    end
                elseif du.phase == "end" and du.t > 1.8 then
                    say(du.loser, L["Lost!"], 2.5)
                    say(du.winner, L["Won!"], 2.5)
                    du.phase, du.t = "done", 0
                elseif du.phase == "done" and du.t > 2.5 then
                    du.a.duel, du.b.duel = nil, nil
                    du.a.wait, du.b.wait = 1 + math.random() * 2, 1 + math.random() * 2
                    self.duel = nil
                end
            end
            for _, s in ipairs(self.sheep) do
                if s:IsShown() and s.who then
                    if s.lying then
                        -- 0.6.548: totally neglected - lies in the grass; 0.6.579: asleep instead of the death pose
                        setSleep(s, true)
                        s.sayIn = (s.sayIn or 10) - dt
                    elseif s.sleeping and setSleep(s, false) then
                    elseif s.duel and s.duel.phase ~= "walk" then
                        setAnim(s, 0)
                    elseif s.wait then
                        s.wait = s.wait - dt
                        setAnim(s, 0)
                        if s.wait <= 0 then pickTarget(s, self.sheep) end
                        -- standing too close to another (e.g. after start)? gently apart
                        if not s.duel then
                            s.cw = ((s.cw or math.random(0, 5)) + 1) % 6   -- 0.6.584: standing animals check only every sixth frame
                            local o = s.cw == 0 and crowded(s, s.x, s.y, self.sheep) or nil
                            if o then push(s, o, dt) end
                        end
                        s.sayIn = (s.sayIn or 10) - dt
                    else
                        local dx, dy = s.tx - s.x, s.ty - s.y
                        local d = math.sqrt(dx * dx + dy * dy)
                        s.sayIn = (s.sayIn or 10) - dt
                        if d < 0.01 then
                            -- 0.6.579: animals of offline owners doze - long breaks, rarely on the move
                            s.wait = (1.5 + math.random() * 4) * (s.mood and s.mood < 30 and 2.5 or 1) * (s.who.online and 1 or 4)
                        else
                            local v = 0.045 * (0.6 + 0.6 * s.y) * (s.mood and (0.45 + s.mood / 120) or 1)   -- faster at the front, sad sheep trudge
                            local step = math.min(d, v * dt)
                            local nx, ny = s.x + dx / d * step, s.y + dy / d * step
                            -- 0.6.584: the O(n^2) check only every third frame per animal (100 animals = 10,000 pairs)
                            s.cc = ((s.cc or math.random(0, 2)) + 1) % 3
                            local o
                            if s.cc == 0 then o = crowded(s, nx, ny, self.sheep) s.lastCrowd = o else o = s.lastCrowd end
                            if o and not o:IsShown() then o = nil end
                            if o and s.duel and (o == s.duel.a or o == s.duel.b) then o = nil end   -- for a duel you may get close
                            -- 0.6.546: don't walk into each other - whoever stands in front of another animal stops briefly and picks a new target
                            local away = o and (math.abs(nx - o.x) + math.abs(ny - o.y)) > (math.abs(s.x - o.x) + math.abs(s.y - o.y))
                            if o and not away then
                                -- 0.6.562: in the way -> gently aside, after 1 s a new target with room (no turning on the spot)
                                push(s, o, dt)
                                setAnim(s, 0)
                                s.blocked = (s.blocked or 0) + dt
                                if s.blocked > 1 then s.blocked = 0 pickTarget(s, self.sheep) end
                            else
                                s.blocked = 0
                                s.x, s.y = nx, ny
                                setAnim(s, 4)
                                -- Facing: 0 = toward camera, right = -pi/2, away = pi; only while walking and only after a noticeable change
                                local face = math.atan2 and math.atan2(-dx, dy) or 0
                                if not s.face or math.abs(face - s.face) > 0.25 then s.face = face pcall(s.SetFacing, s, face) end
                            end
                        end
                    end
                    -- speech bubble: every 15-40 s briefly "Baa!" or whatever is lacking
                    if s.sayLeft then
                        s.sayLeft = s.sayLeft - dt
                        if s.sayLeft <= 0 then s.sayLeft = nil s.say:Hide() s.sayBg:Hide() self.talking = math.max(0, (self.talking or 1) - 1) end
                    elseif (s.sayIn or 10) <= 0 and not s.duel and (self.talking or 0) >= 3 then
                        s.sayIn = 3 + math.random() * 6   -- 0.6.584: enough bubbles right now - try again later
                    elseif (s.sayIn or 10) <= 0 and not s.duel then
                        self.talking = (self.talking or 0) + 1
                        s.sayIn = (15 + math.random() * 25) * math.max(1, (self.crowd or 1) / 15)
                        s.say:SetText(s.wish or L["Baa!"])
                        s.say:Show() s.sayBg:Show() s.sayLeft = 3
                        if self:IsVisible() and s.who.online and (not s.form or s.form.key == "sheep") then Weide.Maeh() end
                    end
                    -- size: only by depth
                    local size = 140 * bodyW(s.y) * math.max(0.6, H / 520)   -- 0.6.548: size only by depth, not by rank
                    size = size * (1 - 0.15 * (s.sad or 0))   -- 0.6.548: neglected a bit smaller
                    local feet = H * (MEADOW_TOP + s.y * (MEADOW_BOTTOM - MEADOW_TOP))
                    -- 0.6.547: names smaller at the back, bigger at the front (9-14 pt)
                    local fs = 9 + math.floor(s.y * 5 + 0.5)
                    if s.fs ~= fs then
                        s.fs = fs
                        local face, _, flags = s.name:GetFont()
                        if face then s.name:SetFont(face, fs, flags or "OUTLINE") end
                    end
                    s:SetSize(size, size)
                    s:ClearAllPoints()
                    s:SetPoint("BOTTOMLEFT", self, "TOPLEFT", s.x * (W - size), -feet - size * 0.08)   -- bottom edge = feet (small margin in the model)
                    -- 0.6.579: ground shadow under the feet, name right above the head (the model fills only the lower part of its square)
                    s.shadow:ClearAllPoints()
                    -- 0.6.582: the feet sit a bit above the bottom edge of the model square - shadow higher, smaller, softer
                    s.shadow:SetPoint("CENTER", self, "TOPLEFT", s.x * (W - size) + size * 0.5, -feet + size * 0.1)
                    s.shadow:SetSize(size * (s.lying and 0.6 or 0.5), size * 0.14)
                    s.shadow:SetAlpha(0.35 + 0.2 * s.y)
                    s.shadow:Show()
                    if math.abs((s.nameOff or 0) - size) > 2 then
                        s.nameOff = size
                        s.name:ClearAllPoints()
                        s.name:SetPoint("BOTTOM", s, "TOP", 0, -size * (s.lying and 0.55 or 0.36))
                    end
                    -- names further back fade a little; offline owners dimmer
                    s.nameA = (s.who.online and 0.95 or 0.6) * (0.55 + 0.45 * s.y)
                    if not s.nameHidden then s.name:SetAlpha(s.nameA) end
                    -- hearts: rise and fade for 1.6 s
                    if s.heartT then
                        s.heartT = s.heartT + dt
                        local hs = math.max(10, size * 0.14)
                        for i, t in ipairs(s.hearts) do
                            local ph = s.heartT - (i - 1) * 0.18
                            if ph > 0 and ph < 1.4 then
                                t:ClearAllPoints()
                                t:SetPoint("CENTER", s, "TOP", (i - 2.5) * hs * 0.9 + math.sin(ph * 6 + i) * 4, -size * 0.35 + ph * size * 0.35)
                                t:SetSize(hs, hs)
                                t:SetAlpha(math.min(1, (1.4 - ph) * 1.5))
                                t:Show()
                            else
                                t:Hide()
                            end
                        end
                        if s.heartT > 2.2 then s.heartT = nil for _, t in ipairs(s.hearts) do t:Hide() end end
                    end

                    -- sparkle (streak of 3+ days): three little stars briefly circle the head
                    if (s.streak or 0) >= 3 then
                        s.sparkT = (s.sparkT or math.random() * 6) + dt
                        local ph = s.sparkT % 6
                        for i, t in ipairs(s.spark) do
                            if ph < 2 then
                                local a = ph * 3 + i * 2.09
                                t:ClearAllPoints()
                                t:SetPoint("CENTER", s, "TOP", math.cos(a) * size * 0.3, -size * 0.2 + math.sin(a) * size * 0.08)
                                t:SetAlpha(math.sin(ph / 2 * math.pi))
                                t:Show()
                            else
                                t:Hide()
                            end
                        end
                    else
                        for _, t in ipairs(s.spark) do t:Hide() end
                    end
                    if rb and s.skin and s.skin.rainbow then
                        local r, g, b = 0.5 + 0.5 * math.sin(hue * 6.283), 0.5 + 0.5 * math.sin(hue * 6.283 + 2.09), 0.5 + 0.5 * math.sin(hue * 6.283 + 4.19)
                        light(s, s.skin, r, g, b)
                    end
                end
            end
            -- 0.6.581: brushing mini game - burrs stick to the own animal until swept off (20 s)
            local br = self.brush
            if br then
                br.t = br.t + dt
                local s = br.s
                local size = s:GetWidth() or 60
                for _, b in ipairs(self.burrs) do
                    if not b.done then
                        b:ClearAllPoints()
                        b:SetPoint("CENTER", s, "TOPLEFT", size * b.ox, -size * b.oy)
                        local bs = math.max(12, size * 0.11)
                        b:SetSize(bs, bs)
                    end
                end
                if br.left <= 0 then
                    self.brush = nil
                    s.wait = 1
                    local ok = Weide.Care("c")
                    if ok then Weide.cared = true Weide.Note("brush") end
                    s:Hearts()
                    s.say:SetText(L["So fluffy! Thanks!"]) s.say:Show() s.sayBg:Show() s.sayLeft = 3
                    ns.RefreshPage("pasture", true)
                elseif br.t > 20 or not s:IsShown() then
                    self.brush = nil
                    s.wait = 1
                    for _, b in ipairs(self.burrs) do b:Hide() end
                end
            end
            -- 0.6.580: now and then a few animals follow the one with the longest care streak (little herds)
            self.herdIn = (self.herdIn or (40 + math.random() * 60)) - dt
            if self.herdIn <= 0 then
                self.herdIn = 70 + math.random() * 90
                local lead, cand = nil, {}
                for _, s in ipairs(self.sheep) do
                    if s:IsShown() and s.who and not s.lying and not s.duel then
                        if s.who.online and (s.streak or 0) >= 2 and (not lead or s.streak > lead.streak) then lead = s end
                        cand[#cand + 1] = s
                    end
                end
                if lead then
                    local n = 0
                    for i = #cand, 2, -1 do local j = math.random(i) cand[i], cand[j] = cand[j], cand[i] end
                    for _, s in ipairs(cand) do
                        if s ~= lead and n < 3 then
                            n = n + 1
                            local back = (lead.tx and lead.tx < lead.x) and 1 or -1
                            s.tx = math.max(0.03, math.min(0.97, (lead.tx or lead.x) + back * (0.06 + 0.05 * n)))
                            s.ty = math.max(0, math.min(1, (lead.ty or lead.y) + (n - 2) * 0.07))
                            s.wait = nil
                        end
                    end
                end
            end
            -- 0.6.579: names must not cover each other - nearer animals (and your own) win, hovering shows all again
            self.labT = (self.labT or 0) + dt
            if self.labT > 0.25 then
                self.labT = 0
                local list = {}
                for _, s in ipairs(self.sheep) do if s:IsShown() and s.who then list[#list + 1] = s end end
                table.sort(list, function(a, b)
                    local am, bm = ns.isMe(a.who.name), ns.isMe(b.who.name)
                    if am ~= bm then return am end
                    return a.y > b.y
                end)
                local taken = {}
                local big = (self.crowd or 0) > 25
                for _, s in ipairs(list) do
                    local l, r, t, b = s.name:GetLeft(), s.name:GetRight(), s.name:GetTop(), s.name:GetBottom()
                    local hide = false
                    local keep = s.keepName or s.hover
                    if big and not keep then hide = true l = nil end
                    if l and r and t and b and not self.showAll and not s.hover then
                        for _, q in ipairs(taken) do
                            if l < q[2] + 2 and r > q[1] - 2 and b < q[3] + 1 and t > q[4] - 1 then hide = true break end
                        end
                    end
                    s.nameHidden = hide
                    s.name:SetAlpha(hide and 0 or (s.nameA or 0.9))
                    if not hide and l then taken[#taken + 1] = { l, r, t, b } end
                end
            end
            -- 0.6.579: time of day (local clock): dawn, day, dusk, night with fireflies
            if self.sky then
                self.skyT = (self.skyT or 99) + dt
                if self.skyT > 20 then
                    self.skyT = 0
                    local tm = date("*t")
                    local hr = tm.hour + tm.min / 60
                    local col, a
                    if hr < 5 or hr >= 22 then col, a = { 0.04, 0.07, 0.22 }, 0.5
                    elseif hr < 7 then col, a = { 1, 0.6, 0.35 }, 0.18 * (7 - hr) / 2 + 0.05
                    elseif hr >= 19 then col, a = { 0.9, 0.45, 0.35 }, 0.1 + 0.25 * (hr - 19) / 3
                    else col, a = { 1, 1, 1 }, 0 end
                    if ns.db.settings.gotchiDayNight == false then a = 0 end
                    self.sky.t:SetColorTexture(col[1], col[2], col[3], 1)
                    self.sky.t:SetAlpha(a)
                    self.night = a >= 0.4
                end
                local bugs = self.sky.bugs
                for i, f in ipairs(bugs) do
                    if self.night then
                        f.ph = (f.ph or math.random() * 10) + dt * f.sp
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", self, "TOPLEFT", W * (f.x + 0.04 * math.sin(f.ph * 0.7)), -H * (f.y + 0.03 * math.cos(f.ph)))
                        f:SetAlpha(0.35 + 0.65 * math.max(0, math.sin(f.ph * 2.3)))
                        f:Show()
                    else
                        f:Hide()
                    end
                end
            end
            -- 0.6.580: seasons by the calendar: snow (Dec-Feb), blossoms (Mar-May), butterflies (Jun-Aug), leaves (Sep-Nov)
            if self.season and self.seasonKind and ns.db.settings.gotchiDayNight ~= false then
                local kind = self.seasonKind
                for i, f in ipairs(self.season) do
                    f.ph = (f.ph or math.random() * 20) + dt * f.sp
                    local x, y
                    if kind == "fly" then
                        x = f.x + 0.06 * math.sin(f.ph * 0.9 + i)
                        y = f.y + 0.04 * math.sin(f.ph * 1.7)
                        f:SetAlpha(0.85)
                        local w = 6 + 4 * math.abs(math.sin(f.ph * 9))   -- wings flap
                        f:SetSize(w, 7)
                    else
                        local fall = (f.ph * 0.05) % 1.1
                        x = f.x + 0.03 * math.sin(f.ph * 1.3 + i)
                        y = fall - 0.05
                        f:SetAlpha(math.min(1, (1.05 - fall) * 3) * 0.85)
                    end
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", self, "TOPLEFT", W * x, -H * y)
                    f:Show()
                end
            elseif self.season then
                for _, f in ipairs(self.season) do f:Hide() end
            end
            -- 0.6.579: flock festival reached this week - colourful sparks float up across the meadow
            if self.party and self.fest then
                for i, f in ipairs(self.party) do
                    f.ph = (f.ph or math.random() * 6) + dt * f.sp
                    local ph = f.ph % 6
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", self, "TOPLEFT", W * f.x + 10 * math.sin(ph * 2 + i), -H * (0.95 - ph / 6 * 0.6))
                    f:SetAlpha(math.min(1, ph) * math.min(1, (6 - ph) / 2) * 0.9)
                    f:Show()
                end
            elseif self.party then
                for _, f in ipairs(self.party) do f:Hide() end
            end
        end)
        -- 0.6.579: sky tint + fireflies above the animals (no mouse - clicks go through to the animals)
        local sky = CreateFrame("Frame", nil, field)
        sky:SetAllPoints()
        sky:SetFrameLevel(field:GetFrameLevel() + 50)
        sky.t = sky:CreateTexture(nil, "OVERLAY")
        sky.t:SetAllPoints()
        sky.t:SetBlendMode("BLEND")
        sky.t:SetAlpha(0)
        sky.bugs = {}
        for i = 1, 14 do
            local f = sky:CreateTexture(nil, "OVERLAY", nil, 7)
            f:SetTexture(ns.MEDIA .. "icons\\star_on")
            f:SetBlendMode("ADD")
            f:SetVertexColor(0.85, 1, 0.45)
            f:SetSize(9, 9)
            f.x, f.y, f.sp = 0.05 + math.random() * 0.9, 0.42 + math.random() * 0.45, 0.4 + math.random() * 0.6
            f:Hide()
            sky.bugs[i] = f
        end
        field.sky = sky
        -- 0.6.581: burrs for the brushing mini game (buttons above the animals, removed by moving the mouse over them)
        field.burrs = {}
        for i = 1, 6 do
            local b = CreateFrame("Frame", nil, field)
            b:SetSize(18, 18)
            b:SetFrameLevel(field:GetFrameLevel() + 48)
            b:EnableMouse(true)
            b.t = b:CreateTexture(nil, "OVERLAY")
            b.t:SetAllPoints()
            b.t:SetTexture(ns.MEDIA .. "dot")
            b.t:SetVertexColor(0.45, 0.3, 0.12)
            b.spike = b:CreateTexture(nil, "OVERLAY", nil, 1)
            b.spike:SetPoint("CENTER")
            b.spike:SetSize(22, 22)
            b.spike:SetTexture(ns.MEDIA .. "icons\\star_on")
            b.spike:SetVertexColor(0.55, 0.38, 0.15)
            b:SetScript("OnEnter", function(self)
                if not field.brush then return end
                self:Hide()
                self.done = true
                field.brush.left = field.brush.left - 1
                if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
            end)
            b:Hide()
            field.burrs[i] = b
        end
        function field:StartBrush()
            local mine
            for _, s in ipairs(self.sheep) do if s:IsShown() and s.who and ns.isMe(s.who.name) and not s.lying then mine = s end end
            if not mine then return false end
            local g = ns.db.settings.gildotchi or {}
            local left = (tonumber(g.c) or 0) + Weide.NEEDS[3].cd - ns.now()
            if left > 0 then
                K.Toast(L["Gildotchi"], (L["Again in %s."]):format(fmtLeft(left)), C.amber or C.accent)
                return true
            end
            self.brush = { s = mine, left = #self.burrs, t = 0 }
            mine.wait, mine.tx, mine.ty = 30, mine.x, mine.y   -- stand still while being brushed
            for _, b in ipairs(self.burrs) do
                b.ox, b.oy, b.done = 0.28 + math.random() * 0.44, 0.45 + math.random() * 0.3, nil
                b:Show()
            end
            mine.say:SetText(L["Sweep the burrs off with your mouse!"]) mine.say:Show() mine.sayBg:Show() mine.sayLeft = 4
            return true
        end
        -- 0.6.580: season particles (below the sky tint, above the animals)
        field.season = {}
        local mon = tonumber(date("%m")) or 6
        local SK = (mon == 12 or mon <= 2) and "snow" or (mon <= 5 and "bloom") or (mon <= 8 and "fly") or "leaf"
        local SCOL = { snow = { { 1, 1, 1 } }, bloom = { { 1, 0.75, 0.85 }, { 1, 0.9, 0.95 } },
            fly = { { 1, 0.9, 0.35 }, { 1, 1, 1 }, { 0.6, 0.8, 1 } }, leaf = { { 0.95, 0.55, 0.15 }, { 0.8, 0.3, 0.1 }, { 0.95, 0.8, 0.25 } } }
        for i = 1, (SK == "fly" and 7 or 22) do
            local f = sky:CreateTexture(nil, "OVERLAY", nil, 5)
            f:SetTexture(ns.MEDIA .. "dot")
            local c = SCOL[SK][i % #SCOL[SK] + 1]
            f:SetVertexColor(c[1], c[2], c[3])
            local sz = SK == "snow" and (3 + math.random() * 3) or (4 + math.random() * 3)
            f:SetSize(sz, sz * (SK == "leaf" and 0.6 or 1))
            f.x, f.y, f.sp = math.random(), 0.5 + math.random() * 0.4, 0.5 + math.random() * 0.8
            f:Hide()
            field.season[i] = f
        end
        field.seasonKind = SK
        field.party = {}
        local PCOL = { { 1, 0.45, 0.6 }, { 1, 0.85, 0.3 }, { 0.5, 0.85, 1 }, { 0.6, 1, 0.55 } }
        for i = 1, 16 do
            local f = sky:CreateTexture(nil, "OVERLAY", nil, 6)
            f:SetTexture(ns.MEDIA .. "icons\\" .. (i % 3 == 0 and "heart" or "star_on"))
            local c = PCOL[i % #PCOL + 1]
            f:SetVertexColor(c[1], c[2], c[3])
            f:SetSize(12, 12)
            f.x, f.sp = 0.04 + math.random() * 0.92, 0.6 + math.random() * 0.8
            f:Hide()
            field.party[i] = f
        end

        -- 0.6.545: choose look - button below the meadow opens a picker with model preview
        local bar = CreateFrame("Frame", nil, p)
        bar:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -12)
        bar:SetPoint("RIGHT", field, "RIGHT", 0, 0)
        bar:SetHeight(26)
        p.bar = bar
        bar.btn = K.Button(bar, L["Change look"], 150, 24, "primary", function()
            p.pick:SetShown(not p.pick:IsShown())
            if p.pick:IsShown() then p.pick:Update() end
        end)
        bar.btn:SetPoint("LEFT", 0, 0)
        -- 0.6.581: care book
        bar.book = K.Button(bar, L["Care book"], 110, 24, "ghost", function()
            p.book:SetShown(not p.book:IsShown())
            if p.book:IsShown() then p.pick:Hide() p.book:Update() end
        end)
        bar.book:SetPoint("LEFT", bar.btn, "RIGHT", 8, 0)
        bar.cur = K.Text(bar, 11, C.muted)
        bar.cur:SetPoint("LEFT", bar.book, "RIGHT", 12, 0)
        -- 0.6.545: as AFK screen (fullscreen as soon as you are AFK)
        bar.afk = K.Toggle(bar, L["As AFK screen"], function() return ns.db.settings.gotchiAfk == true end,
            function(v) ns.db.settings.gotchiAfk = v and true or nil end)
        bar.afk:SetWidth(190)
        bar.snd = K.Toggle(bar, L["Baa sounds"], function() return ns.db.settings.gotchiSound ~= false end,
            function(v) if v then ns.db.settings.gotchiSound = nil else ns.db.settings.gotchiSound = false end end)
        bar.snd:SetWidth(170)
        -- 0.6.579: time of day on the meadow (local clock)
        bar.day = K.Toggle(bar, L["Day, night & seasons"], function() return ns.db.settings.gotchiDayNight ~= false end,
            function(v) if v then ns.db.settings.gotchiDayNight = nil else ns.db.settings.gotchiDayNight = false end field.skyT = 99 end)
        bar.day:SetWidth(230)
        -- 0.6.582: second row below the buttons (in one row they covered the buttons)
        bar.day:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
        bar.snd:SetPoint("LEFT", bar.day, "RIGHT", 16, 0)
        bar.afk:SetPoint("LEFT", bar.snd, "RIGHT", 16, 0)
        -- 0.6.556: text "Look" ends before the toggles (was underneath)
        bar.cur:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        bar.cur:SetJustifyH("LEFT") bar.cur:SetWordWrap(false)

        local pick = CreateFrame("Frame", nil, p)
        pick:SetPoint("TOPLEFT", field, "TOPLEFT", 16, -60)
        pick:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -16, 16)
        pick:SetFrameLevel(field:GetFrameLevel() + 80)
        pick:EnableMouse(true)
        pick:Hide()
        K.Fill(pick, { 0.03, 0.04, 0.06, 0.92 })
        K.Border(pick, C.line)
        p.pick = pick
        pick.close = K.Button(pick, L["Done"], 80, 22, "ghost", function() pick:Hide() end)
        pick.close:SetPoint("TOPRIGHT", -10, -8)
        pick.h1 = K.Text(pick, 12, C.text)
        pick.h1:SetPoint("TOPLEFT", 14, -12)
        pick.h1:SetText(L["Your animal"])
        pick.h2 = K.Text(pick, 12, C.text)
        pick.h2:SetText(L["Colour"])
        local TILE = 74
        local function tile(kind, def)
            local t = CreateFrame("Button", nil, pick)
            t:SetSize(TILE, TILE + 18)
            t.bg = K.Fill(t, { 1, 1, 1, 0.04 })
            t.sel = t:CreateTexture(nil, "BORDER")
            t.sel:SetPoint("TOPLEFT", -2, 2) t.sel:SetPoint("BOTTOMRIGHT", 2, -2)
            t.sel:SetColorTexture(C.accent2[1], C.accent2[2], C.accent2[3], 0.7)
            t.sel:Hide()
            local ok, m = pcall(CreateFrame, "PlayerModel", nil, t)
            if ok and m then
                m:SetPoint("TOPLEFT", 2, -2)
                m:SetSize(TILE - 4, TILE - 4)
                m:SetScript("OnModelLoaded", function(self)
                    pcall(self.SetPortraitZoom, self, 0)
                    pcall(self.SetCamDistanceScale, self, 0.95)
                    pcall(self.SetFacing, self, -0.5)
                    if self.skin then light(self, self.skin, 1, 0.6, 0.9) end
                end)
                t.m = m
            end
            t.label = K.Text(t, 10, C.text, "CENTER")
            t.label:SetPoint("BOTTOM", 0, 3)
            t.label:SetWidth(TILE)
            t.label:SetWordWrap(false)
            t.lock = K.Text(t, 11, C.amber or C.accent, "CENTER")
            t.lock:SetPoint("CENTER", 0, 8)
            t.kind, t.def = kind, def
            t:SetScript("OnClick", function(self)
                local d = self.def
                local ok2 = (self.kind == "form") and Weide.SetMyForm(d.key) or (self.kind == "skin" and Weide.SetMySkin(d.key))
                if not ok2 then
                    K.Toast(L["Guildotchi"], (L["%s unlocks at Oasis rank %d."]):format(L[d.text], d.lvl), C.amber or C.accent)
                end
                ns.RefreshPage("pasture", true)
                pick:Update()
            end)
            return t
        end
        pick.ft, pick.st = {}, {}
        for i, f in ipairs(Weide.FORMS) do pick.ft[i] = tile("form", f) end
        for i, sk in ipairs(Weide.SKINS) do pick.st[i] = tile("skin", sk) end
        function pick:Update()
            local w = math.max(200, (self:GetWidth() or 600) - 28)
            local per = math.max(1, math.floor((w + 6) / (TILE + 6)))
            local mine = myRank()
            local curF, curS = Weide.FormOf(ns.me(), mine), Weide.SkinOf(ns.me(), mine)
            local function place(list, y0)
                for i, t in ipairs(list) do
                    local c, r = (i - 1) % per, math.floor((i - 1) / per)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", 14 + c * (TILE + 6), y0 - r * (TILE + 24))
                    local d = t.def
                    local open = mine >= d.lvl
                    local form = t.kind == "form" and d or curF
                    local skin = t.kind == "skin" and d or curS
                    if t.m then
                        if t.m.form ~= form or not t.m.loaded then t.m.form = form t.m.loaded = true Weide.LoadForm(t.m, form) end
                        t.m.skin = skin
                        if skin.rainbow then light(t.m, skin, 1, 0.6, 0.9) else light(t.m, skin, 1, 1, 1) end
                        t.m:SetAlpha(open and 1 or 0.35)
                    end
                    t.label:SetText(L[d.text])
                    t.lock:SetText(open and "" or ((L["from %d"]):format(d.lvl)))
                    t.sel:SetShown((t.kind == "form" and d == curF) or (t.kind == "skin" and d == curS))
                end
                return y0 - math.ceil(#list / per) * (TILE + 24)
            end
            local y = place(self.ft, -34)
            self.h2:ClearAllPoints()
            self.h2:SetPoint("TOPLEFT", 14, y - 6)
            place(self.st, y - 26)
        end
        pick:SetScript("OnSizeChanged", function(self) if self:IsShown() then self:Update() end end)

        local book = CreateFrame("Frame", nil, p)
        book:SetPoint("TOPLEFT", field, "TOPLEFT", 16, -60)
        book:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -16, 16)
        book:SetFrameLevel(field:GetFrameLevel() + 80)
        book:EnableMouse(true)
        book:Hide()
        K.Fill(book, { 0.03, 0.04, 0.06, 0.93 })
        K.Border(book, C.line)
        p.book = book
        book.close = K.Button(book, L["Done"], 80, 22, "ghost", function() book:Hide() end)
        book.close:SetPoint("TOPRIGHT", -10, -8)
        book.h = K.Text(book, 13, C.text)
        book.h:SetPoint("TOPLEFT", 14, -12)
        book.rows = {}
        for i, b in ipairs(Weide.BOOK) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local r = K.Text(book, 12, C.text)
            r:SetPoint("TOPLEFT", 16 + col * 300, -44 - row * 24)
            r:SetWidth(290) r:SetJustifyH("LEFT") r:SetWordWrap(false)
            r.def = b
            book.rows[i] = r
        end
        function book:Update()
            local ms = (ns.db.settings.gildotchi or {}).ms or {}
            local n = 0
            for _, r in ipairs(self.rows) do
                local d = ms[r.def.key]
                if d then n = n + 1 end
                r:SetText(d and ("|T" .. ns.MEDIA .. "icons\\star_on:14|t " .. L[r.def.text] .. "  |cff8a8a8a" .. d .. "|r")
                    or ("|cff5a5a5a|T" .. ns.MEDIA .. "icons\\star_off:14|t " .. L[r.def.text] .. "|r"))
            end
            self.h:SetText((L["Care book - %d of %d memories"]):format(n, #self.rows))
        end
        -- ranking on the right
        local side = CreateFrame("Frame", nil, p)
        side:SetPoint("TOPLEFT", field, "TOPRIGHT", 24, 10)
        side:SetPoint("BOTTOMRIGHT", 0, 0)
        p.side = side
        side.bg = K.Fill(side, C.panel or { 0, 0, 0, 0.4 })
        K.Border(side, C.line)
        -- My Gildotchi: mood, three bars, three buttons
        side.me = K.Text(side, 13, C.text)
        side.me:SetPoint("TOPLEFT", 12, -10)
        side.me:SetText(L["My Guildotchi"])
        side.mood = K.Text(side, 11, C.muted)
        side.mood:SetPoint("TOPLEFT", side.me, "BOTTOMLEFT", 0, -3)
        side.mood:SetPoint("RIGHT", side, "RIGHT", -8, 0)
        side.mood:SetJustifyH("LEFT")
        side.mood:SetWordWrap(false)
        -- 0.6.548: ran away -> bring back
        side.recall = K.Button(side, L["Bring back"], 100, 20, "primary", function()
            Weide.Recall()
            K.Toast(L["Guildotchi"], L["Your animal is back from grandma's farm and happy to see you."], C.mint)
            ns.RefreshPage("pasture", true)
        end)
        side.recall:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -8)
        side.recall:Hide()
        side.need = {}
        for i, n in ipairs(Weide.NEEDS) do
            local y = -48 - (i - 1) * 40
            local r = {}
            r.t = K.Text(side, 11, C.text)
            r.t:SetPoint("TOPLEFT", 12, y)
            r.bar = K.Bar(side, LIST_W - 24, 6)
            r.bar:SetPoint("TOPLEFT", 12, y - 20)
            r.btn = K.Button(side, L[n.act], 76, 20, "ghost", function()
                -- 0.6.581: brushing is a small mini game: sweep the burrs off your animal with the mouse
                if n.key == "c" and p.field.StartBrush and p.field:StartBrush() then return end
                local ok, left = Weide.Care(n.key)
                if ok then
                    Weide.cared = true
                    K.Toast(L["Gildotchi"], L["Baa! Thanks!"], C.mint)
                else
                    K.Toast(L["Gildotchi"], (L["Again in %s."]):format(fmtLeft(left)), C.amber or C.accent)
                end
                ns.RefreshPage("pasture", true)
            end)
            r.btn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, y + 3)
            r.need = n
            side.need[i] = r
        end
        -- 0.6.579: weekly flock festival (shared bar of the whole guild)
        side.fest = K.Text(side, 11, C.text)
        side.fest:SetPoint("TOPLEFT", 12, -172)
        side.fest:SetPoint("RIGHT", side, "RIGHT", -8, 0)
        side.fest:SetJustifyH("LEFT")
        side.fest:SetWordWrap(false)
        side.festBar = K.Bar(side, LIST_W - 24, 6)
        side.festBar:SetPoint("TOPLEFT", 12, -190)
        -- 0.6.579: gifts at the fence - who fed your animal recently (feed them back by clicking their animal)
        side.gifts = K.Text(side, 11, C.muted)
        side.gifts:SetPoint("TOPLEFT", 12, -204)
        side.gifts:SetPoint("RIGHT", side, "RIGHT", -8, 0)
        side.gifts:SetJustifyH("LEFT")
        side.gifts:SetWordWrap(true)
        side.gifts:SetMaxLines(2)
        side.h = K.Text(side, 13, C.text)
        side.h:SetPoint("TOPLEFT", 12, -244)
        side.h:SetText(L["Flock leaderboard"])
        side.sum = K.Text(side, 11, C.muted)
        side.sum:SetPoint("TOPLEFT", side.h, "BOTTOMLEFT", 0, -3)
        side.rows = {}
        for i = 1, 16 do
            local r = CreateFrame("Frame", nil, side)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 10, -280 - (i - 1) * 21)
            r:SetPoint("RIGHT", side, "RIGHT", -10, 0)
            r.pos = K.Text(r, 11, C.dim, "RIGHT")
            r.pos:SetPoint("LEFT", 0, 0) r.pos:SetWidth(22)
            r.dot = r:CreateTexture(nil, "ARTWORK")
            r.dot:SetSize(8, 8) r.dot:SetPoint("LEFT", 28, 0)
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("LEFT", 42, 0) r.n:SetPoint("RIGHT", -40, 0)
            r.n:SetWordWrap(false) r.n:SetJustifyH("LEFT")
            r.l = K.Text(r, 12, C.accent2, "RIGHT")
            r.l:SetPoint("RIGHT", 0, 0)
            side.rows[i] = r
        end
    end,
    refresh = function(p)
        local all = Weide.Flock()
        local flock = {}
        for _, f in ipairs(all) do if not f.away then flock[#flock + 1] = f end end   -- runaway animals are not on the pasture
        local field = p.field
        local friends = Weide.Friends()
        -- seen reactions older than two days are forgotten again (keeps the saved list small)
        if ns.db.settings.gotchiSeen and next(ns.db.settings.gotchiSeen) then
            local live = {}
            for _, g in ipairs(Store.List("gfeed")) do if g.kind == "r" then live[g.id] = true end end
            for id in pairs(ns.db.settings.gotchiSeen) do if not live[id] then ns.db.settings.gotchiSeen[id] = nil end end
        end
        -- assign sheep (known ones keep their spot)
        local n = math.min(#flock, Weide.sim and 100 or MAX_SHEEP)   -- 0.6.583: the simulation may show up to 100
        for i = 1, n do
            local s = field.sheep[i]
            if not s then
                s = newSheep(field)
                if not s then break end
                field.sheep[i] = s
                s.x, s.y = math.random() * 0.9 + 0.05, math.random()
                -- starting spot: the freest of 12 spots
                local bs = -1
                for _ = 1, 12 do
                    local x, y = math.random() * 0.9 + 0.05, math.random()
                    local sc = room(s, x, y, field.sheep)
                    if sc > bs then s.x, s.y, bs = x, y, sc end
                end
                pickTarget(s, field.sheep)
                s.wait = math.random() * 3
            end
            local who = flock[i]
            s.who = who
            local skin = Weide.SkinOf(who.name, who.lvl)
            if s.skin ~= skin then s.skin = skin light(s, skin, 1, 1, 1) end
            local form = Weide.FormOf(who.name, who.lvl)
            if s.form ~= form then s.form = form s:LoadSheep() end
            local nd = Weide.Needs(who.name)
            s.mood, s.wish = nd.mood, nil
            for _, n in ipairs(Weide.NEEDS) do if nd[n.key] < 25 then s.wish = L[n.say] break end end
            -- 0.6.548: neglected (mood below 20) grayer/smaller, below 8 it lies down
            local sad = nd.mood < 20 and (20 - nd.mood) / 20 or 0
            if math.abs((s.sad or 0) - sad) > 0.05 then s.sad = sad light(s, s.skin, 1, 1, 1) end
            s.lying = nd.mood < 8 and not s.duel
            if s.lying then s.wish = L["Zzz ..."] s.wait = nil end
            if not who.online and not s.wish then s.wish = L["Zzz ..."] end
            s.streak = Weide.Streak(who.name)
            local nk = ns.NameKey(who.name)
            s.friend = friends[nk]
            s.keepName = ns.isMe(who.name) or (friends[ns.NameKey(ns.me())] == nk) or nil
            -- 0.6.580: new reactions from guildmates: the animal shows them once (heart, wave, cheer)
            if p:IsVisible() then
                local nr = Weide.NewReacts(who.name)
                if #nr > 0 then
                    for _, g in ipairs(nr) do ns.db.settings.gotchiSeen[g.id] = true end
                    if ns.isMe(who.name) then Weide.Note("react") end
                    local g, r = nr[1], Weide.REACTS[tonumber(nr[1].e)]
                    s.say:SetText((L[r.say]):format(ns.short(g.by)) .. (#nr > 1 and ("  |cff9a9a9a+" .. (#nr - 1) .. "|r") or ""))
                    s.say:Show() s.sayBg:Show() s.sayLeft = 5
                    if tonumber(g.e) == 1 then s:Hearts() end
                end
            end
            s:SetAlpha(who.online and 1 or 0.75)
            local st, nm = s.streak or 0, ns.short(who.name)
            if st >= 30 then nm = (ns.ART and "|TInterface\\AddOns\\Oasis\\Media\\art\\dr_crown:0|t " or "|T" .. ns.MEDIA .. "icons\\star_on:0|t ") .. "|cffffd24a" .. nm .. "|r"
            elseif st >= 14 then nm = "|T" .. ns.MEDIA .. "icons\\star_on:0|t |cffffd24a" .. nm .. "|r"
            elseif st >= 7 then nm = "|T" .. ns.MEDIA .. "icons\\star_on:0|t " .. nm end
            s.name:SetText(nm)
            s.name:SetAlpha(who.online and 0.95 or 0.6)
            s.name:Show()
            s:Show()
        end
        for i = n + 1, #field.sheep do
            local s = field.sheep[i]
            s:Hide() s.who = nil s.name:Hide() s.say:Hide() s.sayBg:Hide() s.shadow:Hide()
        end
        field.empty:SetText(#flock == 0 and L["No sheep on the pasture yet."] or "")
        -- 0.6.584: crowd: up to ~18 animals at full size, then smaller (40 -> 0.67, 100 -> 0.42)
        field.crowd = n
        crowdScale = math.min(1, math.sqrt(18 / math.max(18, n)))
        field.myFriend = friends[ns.NameKey(ns.me())]
        field.talking = 0
        for i = 1, n do local s = field.sheep[i] if s and s.sayLeft then field.talking = field.talking + 1 end end

        -- current look
        local mine = myRank()
        p.bar.cur:SetText(L[Weide.FormOf(ns.me(), mine).text] .. " - " .. L[Weide.SkinOf(ns.me(), mine).text])
        if p.pick:IsShown() then p.pick:Update() end

        -- My Gildotchi
        local side = p.side
        local nd = Weide.Needs(ns.me())
        local mt, mc = Weide.MoodText(nd.mood)
        local st = Weide.Streak(ns.me())
        local nextX
        for _, x in ipairs(Weide.EXTRAS) do if st < x.n then nextX = x break end end
        local tt = Weide.Title(ns.me())
        side.me:SetText(L["My Guildotchi"] .. (tt and ("  |cff8ad4ff" .. L[tt.text] .. "|r") or ""))
        side.mood:SetText(L["Mood"] .. ": " .. K.hex(mc) .. L[mt] .. "|r   " .. (L["Streak: %d days"]):format(st)
            .. (nextX and ("  |cff8a8a8a(" .. (L["%s from %d"]):format(L[nextX.text], nextX.n) .. ")|r") or ""))
        side.recall:SetShown(Weide.IsAway(ns.me()))
        local g = ns.db.settings.gildotchi or {}
        for _, r in ipairs(side.need) do
            local v = nd[r.need.key]
            r.t:SetText(L[r.need.text] .. "  |cff9a9a9a" .. math.floor(v + 0.5) .. "%|r")
            r.bar:Set(v / 100)
            local left = (tonumber(g[r.need.key]) or 0) + r.need.cd - ns.now()
            r.btn:SetAlpha(left > 0 and 0.5 or 1)
        end
        -- 0.6.579: flock festival of the week
        local fs, fg, fdone = Weide.Festival(#flock)
        field.fest = fdone
        side.fest:SetText(fdone and ("|cffffd24a" .. L["Flock festival! The meadow celebrates."] .. "|r")
            or ((L["Flock festival: %d / %d cares this week"]):format(fs, fg)))
        side.festBar:Set(math.min(1, fs / fg))
        if fdone then Weide.Note("fest") end
        if friends[ns.NameKey(ns.me())] then Weide.Note("friend") end
        -- gifts at the fence
        local gifts = Weide.Gifts(ns.me())
        if #gifts > 0 then Weide.Note("gift") end
        if #gifts == 0 then
            side.gifts:SetText(L["No gifts at the fence yet - feed others' animals, they may return the favour."])
        else
            local icons, names, seen = "", {}, {}
            for i, g in ipairs(gifts) do
                if i <= 5 and g.gift then icons = icons .. "|T" .. g.gift.icon .. ":14|t " end
                local nm = ns.short(g.by)
                if not seen[nm] and #names < 3 then seen[nm] = true names[#names + 1] = nm end
            end
            side.gifts:SetText(icons .. "|cffc8c8c8" .. (L["from %s"]):format(table.concat(names, ", ")) .. (#gifts > 3 and " ..." or "") .. "|r")
        end
        -- welcome back / hearts on my own animal after caring
        if Weide.welcome or Weide.cared then
            for _, s in ipairs(field.sheep) do if s:IsShown() and s.who and ns.isMe(s.who.name) then s:Hearts() end end
            if Weide.welcome then K.Toast(L["Guildotchi"], L["Your animal is overjoyed to see you again!"], C.mint) end
            Weide.welcome, Weide.cared = nil, nil
        end
        -- Ranking
        local on = 0
        for _, f in ipairs(flock) do if f.online then on = on + 1 end end
        side.sum:SetText((L["%d sheep, %d online now"]):format(#flock, on))
        local maxRows = math.max(3, math.floor(((side:GetHeight() or 600) - 290) / 21))
        for i, r in ipairs(side.rows) do
            local f = i <= maxRows and all[i] or nil
            r:SetShown(f ~= nil)
            if f then
                r.pos:SetText(i .. ".")
                r.n:SetText(ns.short(f.name) .. (ns.isMe(f.name) and ("  |cff9a9a9a" .. L["(you)"] .. "|r") or "")
                    .. (f.away and ("  |cffe8a040" .. L["visiting grandma's farm"] .. "|r") or ""))
                r.l:SetText(f.lvl)
                local sk = Weide.SkinOf(f.name, f.lvl)
                local c = sk.amb or { 1, 0.4, 0.4 }
                r.dot:SetColorTexture(c[1], c[2], c[3], f.online and 1 or 0.4)
            end
        end
    end,
})
ns.Listen("STORE", function(name) if name == "sheep" then ns.RefreshPage("pasture") end end)
ns.slash.weide = function() ns.ShowPage("pasture") end
-- 0.6.583: /oa schafsim [n] - fake flock of n animals (default 100) to see a big guild; /oa schafsim aus - back to the real one
ns.slash.schafsim = function(arg)
    arg = (arg or ""):lower()
    if arg == "aus" or arg == "off" or arg == "0" then
        Weide.Simulate(nil)
        ns.print(L["Guildotchi: simulation off."])
    else
        Weide.Simulate(tonumber(arg) or 100)
        ns.print((L["Guildotchi: simulating %d animals (only on this PC). Off: /oa schafsim off"]):format(Weide.sim))
    end
end
ns.slash.gildotchi = ns.slash.weide

-- 0.6.545: AFK screen - own meadow in fullscreen while you are AFK (never in combat).
-- Click, key or "no longer AFK" closes it.
local saver
function Weide.ShowSaver(force)
    if not force and ns.db.settings.gotchiAfk ~= true then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local def = ns.PageDef and ns.PageDef("pasture")
    if not def then return end
    if not saver then
        saver = CreateFrame("Frame", nil, UIParent)
        saver:SetFrameStrata("FULLSCREEN_DIALOG")
        saver:SetAllPoints(UIParent)
        saver:EnableMouse(true)
        K.Fill(saver, { 0, 0, 0, 1 })
        local inner = CreateFrame("Frame", nil, saver)
        inner:SetAllPoints()
        local ok, e = pcall(def.build, inner)
        if not ok then ns.err(L["Setup"] .. " Guildotchi AFK", e) saver:Hide() saver = nil return end
        inner.field:ClearAllPoints()
        inner.field:SetAllPoints(saver)
        for _, k in ipairs({ "bar", "side", "pick", "frameArt" }) do if inner[k] then inner[k]:Hide() end end
        if inner.logo then
            inner.logo:ClearAllPoints()
            inner.logo:SetPoint("TOP", saver, "TOP", 0, -24)
            inner.logo:SetSize(480, 176)
        end
        saver.inner = inner
        saver.hint = K.Text(saver, 13, C.text, "CENTER")
        saver.hint:SetPoint("BOTTOM", 0, 24)
        saver.hint:SetAlpha(0.7)
        saver.hint:SetText(L["You are AFK - click or press a key to close this screen."])
        saver:SetScript("OnMouseDown", function(self) self:Hide() end)
        saver:SetScript("OnKeyDown", function(self)
            if self.SetPropagateKeyboardInput and not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, true) end
            self:Hide()
        end)
        local t = 0
        saver:HookScript("OnUpdate", function(self, dt)
            t = t + (dt or 0)
            if t > 30 then t = 0 pcall(def.refresh, self.inner) end
        end)
    end
    pcall(saver.EnableKeyboard, saver, true)
    pcall(def.refresh, saver.inner)
    saver:Show()
end
function Weide.HideSaver() if saver then saver:Hide() end end
ns.On("PLAYER_FLAGS_CHANGED", function(unit)
    if unit ~= "player" then return end
    if UnitIsAFK and UnitIsAFK("player") then Weide.ShowSaver() else Weide.HideSaver() end
end)
ns.On("PLAYER_REGEN_DISABLED", function() Weide.HideSaver() end)
ns.slash.afkschafe = function() Weide.ShowSaver(true) end
-- Diagnostics: do the sheep models load?
ns.slash.schaftest = function()
    local def = ns.PageDef and ns.PageDef("pasture")
    local f = def and def.frame and def.frame.field
    if not f then ns.print("Gildotchi: Seite erst einmal oeffnen.") return end
    ns.print(("Gildotchi: %d Schafe, Wiese %dx%d sichtbar=%s"):format(#f.sheep, f:GetWidth() or 0, f:GetHeight() or 0, tostring(f:IsVisible())))
    for i, m in ipairs(f.sheep) do
        local ok, id = pcall(m.GetModelFileID, m)
        ns.print(("Schaf %d: %s  Modell=%s  sichtbar=%s  Groesse=%dx%d"):format(i, m.who and ns.short(m.who.name) or "-", tostring(ok and id),
            tostring(m:IsVisible()), m:GetWidth() or 0, m:GetHeight() or 0))
    end
end
end)

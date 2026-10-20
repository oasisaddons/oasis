-- Oasis: demo data for raid and trade (only /oa demo)
-- Complements Core\Start\Demo.lua: Molten Core event with signups, lineups (raid leadership),
-- soft reserves, guild tactics, raid loot in the loot log and raid-related wishes.
-- Everything only via ctx.put (Store.merge with demo=true) - Comm sends none of it to the guild.
-- Market (Trade.lua), buff monitor (BuffMonitor.lua) and crafting bring their own demo data.
local ADDON, ns = ...

-- raid loot as link (name in English as in Demo.lua, the game shows the local name)
local function link(id, name, q)
    local col = q == 5 and "ff8000" or (q == 4 and "a335ee" or "0070dd")
    return "|cff" .. col .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r"
end

-- the guild's tactics (own version, overrides the library for these bosses)
local TACTICS = {
    { "Lucifron", "Geschmolzener Kern", "Alle: Fluch des Lucifron sofort entfernen - Magier und Druiden sind eingeteilt.\nAlle: Drohende Verdammnis bannen, Priester links, Schamanen rechts.\nTank: Grukthar nimmt Lucifron, Drogbar und Ragna je eine Wache - Abstand halten (Gedankenkontrolle).\nHeiler: Gedankenkontrollierte Spieler sofort bannen, nicht wegheilen.\nDD: Erst Wache links, dann Wache rechts, zuletzt Lucifron." },
    { "Magmadar", "Geschmolzener Kern", "Alle: Panik alle 30 Sek - Furchtschutz auf die Tanks, Erdungs- und Tremortotem in jeder Nahkampfgruppe.\nAlle: Lavabombe am Boden: sofort raus.\nTank: Magmadar mit dem Ruecken zum Raid, Kopf zur Wand.\nHeiler: In der Panikphase Tank vorheilen.\nDD: Jaeger: Einlullender Schuss im Wechsel (Vol'tar, Thrallia, Mokrash)." },
    { "Baron Geddon", "Geschmolzener Kern", "Alle: Lebende Bombe = SOFORT nach hinten links laufen, Ansage im Sprachchat.\nAlle: Inferno: Nahkampf raus, Mana-Ausloeschung sofort bannen.\nTank: Geddon in der Mitte halten, bei Inferno kurz zuruecktreten.\nHeiler: Bombe-Ziel vor der Explosion volltoppen.\nDD: Fernkampf im Halbkreis, mindestens 25 Meter Abstand." },
    { "Ragnaros", "Geschmolzener Kern", "Alle: Feuerschutztrank vor dem Pull, Feuerwiderstand ab 120.\nAlle: Nach 3 Min taucht Raggi ab - 8 Soehne der Flamme: Magier fesseln nicht, alle Schaden drauf.\nTank: Grukthar Haupttank, Drogbar steht bereit - Zorn des Ragnaros wirft weg.\nHeiler: Gruppe 1 heilt Tanks, Rest Raid. Nicht zu nah (Lavaplatscher).\nDD: Nahkampf bei Zorn zurueck, Fernkampf nie in einer Linie stehen." },
    { "Onyxia", "Onyxias Hort", "Alle: Nie vor oder hinter Onyxia - Atem und Schwanzfeger.\nAlle: Phase 2 (65%): verteilt unter ihr, Feuerbaellen ausweichen, Welpen sofort umhauen.\nAlle: Phase 3 (40%): Furcht - Tremortotem und Furchtschutz bereit, Lavarisse meiden.\nTank: Grukthar zieht sie an die Nordwand, Kopf weg vom Raid.\nHeiler: Tank hat Vorrang, Fernheiler hinten links.\nDD: 3 Sunder abwarten. Jaeger und Hexer: Welpen an den Hoehlen." },
}

-- soft reserves: person, item ID
local SRES_ONY = { { 1, 17068 }, { 9, 17075 }, { 4, 18205 }, { 16, 18205 }, { 2, 17064 }, { 14, 18813 }, { 10, 17064 }, { 20, 17078 } }
local SRES_MC = { { 1, 17076 }, { 9, 18832 }, { 4, 18820 }, { 16, 17103 }, { 18, 18820 }, { 14, 18815 }, { 2, 18815 },
    { 20, 17069 }, { 3, 18842 }, { 6, 18822 }, { 12, 17072 }, { 22, 18822 }, { 10, 17105 }, { 13, 17063 }, { 17, 16800 } }

-- raid awards of the last weeks: person, link, choice, days ago, zone
local DROPS = {
    { 1, link(17068, "Deathbringer", 4), "ms", 5, "Onyxias Hort" },
    { 16, link(18205, "Eskhandar's Collar", 4), "ms", 5, "Onyxias Hort" },
    { 14, link(18813, "Ring of Binding", 4), "ms", 5, "Onyxias Hort" },
    { 9, link(17078, "Sapphiron Drape", 4), "os", 5, "Onyxias Hort" },
    { 20, link(17069, "Striker's Mark", 4), "ms", 12, "Geschmolzener Kern" },
    { 4, link(18820, "Talisman of Ephemeral Power", 4), "ms", 12, "Geschmolzener Kern" },
    { 2, link(16812, "Gloves of Prophecy", 4), "ms", 12, "Geschmolzener Kern" },
    { 10, link(18203, "Eskhandar's Right Claw", 4), "os", 12, "Geschmolzener Kern" },
    { 6, link(18822, "Obsidian Edged Blade", 4), "ms", 19, "Geschmolzener Kern" },
    { 18, link(16808, "Felheart Horns", 4), "ms", 19, "Geschmolzener Kern" },
    { 12, link(16846, "Giantstalker's Helmet", 4), "ms", 19, "Geschmolzener Kern" },
    { 13, link(18823, "Aged Core Leather Gloves", 4), "tm", 19, "Geschmolzener Kern" },
}

-- raid wishes (Wanted page): person, item ID, name, quantity, note, price (gold) or nil
local WANTS = {
    { 9, 13457, "Grosser Feuerschutztrank", 10, "fuer Ragnaros", 4 },
    { 1, 12360, "Arkanitbarren", 4, "Arkanitschnitter", 3 },
    { 14, 14048, "Runenstoffballen", 20, "Taschen fuer den Raid", nil },
    { 4, 13468, "Schwarzer Lotus", 2, "Flaeschchen", 45 },
    { 20, 13452, "Elixier des Mungos", 15, "", 2 },
}

-- lineup: person, group, role
local function plan(ctx, evId, size, slots)
    local t = {}
    for _, s in ipairs(slots) do t[#t + 1] = ctx.nm(s[1]) .. ":" .. s[2] .. ":" .. s[3] end
    table.sort(t)
    -- ID like Planner.PlanId ("plan-<event>"); contains "demo-" -> stays local, Demo.Remove cleans up via demo=true
    ctx.put("raidplan", { id = "plan-" .. evId, ev = evId, size = size, g = table.concat(t, ",") })
end

local function seed(ctx)
    local nm, now, P = ctx.nm, ctx.now, ctx.people
    local function signup(ev, i, role, status, k)
        local p = P[i]
        ctx.put("signups", { id = ev .. "@" .. nm(i), ev = ev, who = nm(i), role = role, status = status or "yes",
            class = p[2], lvl = p[3], ilvl = 20 + p[3], u = now - k * 1300 })
    end

    -- Event: Molten Core (40-man) with many signups
    ctx.put("events", { id = "demo-mc1", title = "Geschmolzener Kern - Gildenraid", inst = "Geschmolzener Kern", ts = now + 6 * 86400 + 5400,
        max = 40, kind = "raid", desc = "Feuerwiderstand ab 120, Wasserkerne und Feuerschutztraenke mitbringen. Invite 19:30, Pull 20:00.", who = nm(1) })
    local mc = {
        { 1, "tank" }, { 9, "tank" }, { 21, "tank" }, { 2, "heal" }, { 14, "heal" }, { 10, "heal" }, { 17, "heal" }, { 23, "heal", "maybe" },
        { 5, "heal" }, { 4, "dps" }, { 16, "dps" }, { 18, "dps" }, { 20, "dps" }, { 6, "dps" }, { 12, "dps" }, { 13, "dps" },
        { 3, "dps" }, { 22, "dps" }, { 24, "dps", "maybe" }, { 8, "dps" }, { 7, "dps", "maybe" }, { 15, "dps", "no" },
    }
    for k, r in ipairs(mc) do signup("demo-mc1", r[1], r[2], r[3], k) end

    -- Lineups (raid leadership > lineup)
    plan(ctx, "demo-raid1", 20, {
        { 1, 1, "tank" }, { 2, 1, "heal" }, { 4, 1, "dps" }, { 16, 1, "dps" }, { 6, 1, "dps" },
        { 9, 2, "tank" }, { 10, 2, "heal" }, { 12, 2, "dps" }, { 18, 2, "dps" }, { 13, 2, "dps" },
        { 14, 3, "heal" }, { 3, 3, "dps" }, { 20, 3, "dps" }, { 17, 3, "heal" },
    })
    plan(ctx, "demo-raid3", 40, {
        { 1, 1, "tank" }, { 2, 1, "heal" }, { 4, 1, "dps" },
        { 9, 2, "tank" }, { 14, 2, "heal" }, { 16, 2, "dps" },
        { 10, 3, "heal" }, { 20, 3, "dps" }, { 18, 3, "dps" },
    })
    plan(ctx, "demo-mc1", 40, {
        { 1, 1, "tank" }, { 2, 1, "heal" }, { 6, 1, "dps" }, { 13, 1, "dps" }, { 3, 1, "dps" },
        { 9, 2, "tank" }, { 14, 2, "heal" }, { 20, 2, "dps" }, { 12, 2, "dps" }, { 22, 2, "dps" },
        { 21, 3, "tank" }, { 10, 3, "heal" }, { 4, 3, "dps" }, { 16, 3, "dps" }, { 18, 3, "dps" },
        { 17, 4, "heal" }, { 5, 4, "heal" }, { 8, 4, "dps" },
    })

    -- soft reserves (ID like SoftRes: <event>@<main>), own reservation is set by Raid.SeedLootDemo
    local me = ctx.me
    for _, r in ipairs(SRES_ONY) do
        if nm(r[1]) ~= me then ctx.put("sres", { id = "demo-raid3@" .. nm(r[1]), ev = "demo-raid3", item = r[2], who = nm(r[1]), char = nm(r[1]), ts = now - r[1] * 2700 }) end
    end
    for _, r in ipairs(SRES_MC) do
        if nm(r[1]) ~= me then ctx.put("sres", { id = "demo-mc1@" .. nm(r[1]), ev = "demo-mc1", item = r[2], who = nm(r[1]), char = nm(r[1]), ts = now - r[1] * 1900 }) end
    end

    -- guild tactics (Boss tactics page); the library fills in the remaining bosses
    for k, t in ipairs(TACTICS) do
        local key = t[1]:lower():gsub("[^%w]", "")
        ctx.put("tactics", { id = "demo-tac-" .. key, boss = t[1], inst = t[2], text = t[3], ts = now - k * 86400, who = nm(1) })
    end

    -- Loot log: raid awards
    for k, d in ipairs(DROPS) do
        ctx.put("loot", { id = "demo-rhloot" .. k, item = d[2], who = nm(d[1]), src = "Vergabe", choice = d[3], roll = 30 + (k * 17) % 70,
            zone = d[5], mapID = 0, ts = now - d[4] * 86400 + k * 600, quality = 4 })
    end

    -- Wanted: raid preparation
    for k, w in ipairs(WANTS) do
        ctx.put("wants", { id = "demo-rhwant" .. k, itemID = w[2], name = w[3], qty = w[4], note = w[5], who = nm(w[1]), created = now - k * 3100, price = w[6] })
    end
end

local function clean()
    -- nothing written outside the store
end

if ns.Demo and ns.Demo.AddSeed then ns.Demo.AddSeed("RaidHandel", seed, clean) end

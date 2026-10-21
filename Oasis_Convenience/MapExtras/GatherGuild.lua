-- Oasis: gathering with the guild (0.6.598) - what a single-player addon cannot do
--   * live finds: valuable herbs/ore someone in the guild sees on the minimap right now -> notice with pin
--   * wishlist: nodes whose herb/ore someone in the guild wants are highlighted, the arrow prefers them
--   * no double work: guild members farming nearby - the arrow leaves their side to them
--   * farm statistics per zone (nodes/hour, skill-ups, value) and zone tips for your skill
-- Respawn times and the skill-up route live in GatherMap.lua.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local GM = ns.Gather
if not GM then return end

local GG = {}
ns.GatherGuild = GG
local function S() return ns.db.settings end
local LIVE = "nodelive"

------------------------------------------------------------------------
-- items of the nodes (for the wishlist): node English name -> item ID
------------------------------------------------------------------------
local ITEM = {
    ["peacebloom"] = 2447, ["silverleaf"] = 765, ["earthroot"] = 2449, ["mageroyal"] = 785, ["briarthorn"] = 2450,
    ["stranglekelp"] = 3820, ["bruiseweed"] = 2453, ["wild steelbloom"] = 3355, ["grave moss"] = 3369, ["kingsblood"] = 3356,
    ["liferoot"] = 3357, ["fadeleaf"] = 3818, ["goldthorn"] = 3821, ["khadgar's whisker"] = 3358, ["wintersbite"] = 3819,
    ["firebloom"] = 4625, ["purple lotus"] = 8831, ["arthas' tears"] = 8836, ["sungrass"] = 8838, ["blindweed"] = 8839,
    ["ghost mushroom"] = 8845, ["gromsblood"] = 8846, ["golden sansam"] = 13464, ["dreamfoil"] = 13463,
    ["mountain silversage"] = 13465, ["plaguebloom"] = 13466, ["icecap"] = 13467, ["black lotus"] = 13468,
    ["copper vein"] = 2770, ["tin vein"] = 2771, ["iron deposit"] = 2772, ["silver vein"] = 2775, ["gold vein"] = 2776,
    ["mithril deposit"] = 3858, ["truesilver deposit"] = 7911, ["small thorium vein"] = 10620, ["rich thorium vein"] = 10620,
    ["dark iron deposit"] = 11370, ["incendicite mineral vein"] = 3340, ["lesser bloodstone deposit"] = 4278,
}
local function itemOf(name)
    local info = GM.NodeInfo(name)
    if not info then return nil end
    local en = info.en:lower():gsub("^ooze covered ", "")
    return ITEM[en]
end
GG.ItemOf = itemOf

-- who in the guild wants the item of this node (Trade wishlist), cached for 10 s
local wantCache, wantAt = {}, -100
function GG.WantedBy(name)
    if S().gatherWanted == false or not (ns.Wants and ns.Wants.All) then return nil end
    local now = GetTime and GetTime() or 0
    if now - wantAt > 10 then wantCache, wantAt = {}, now end
    local key = tostring(name)
    if wantCache[key] ~= nil then return wantCache[key] or nil end
    local id = itemOf(name)
    local itemName = id and C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
    local who
    local ok, list = pcall(ns.Wants.All)
    if ok and type(list) == "table" then
        for _, w in ipairs(list) do
            if not w.del and not w.done and ((id and w.itemID == id) or (itemName and w.name == itemName)) then
                who = w.who or w.by
                break
            end
        end
    end
    wantCache[key] = who or false
    return who
end

------------------------------------------------------------------------
-- live finds of the guild
------------------------------------------------------------------------
-- worth a notice: herbs/ore from skill 230 on, and every Black Lotus
local function valuable(name)
    local info = GM.NodeInfo(name)
    return info and info.skill >= 230
end
GG.Valuable = valuable
local sentAt = {}
function GG.ShareLive(d)
    if S().shareNodes == false or S().gatherAlertsShare == false or not valuable(d.name) then return end
    local id = ("nl-%d-%d-%d"):format(d.map, math.floor(d.x * 1000), math.floor(d.y * 1000))
    local now = ns.now()
    if sentAt[id] and now - sentAt[id] < 600 then return end
    sentAt[id] = now
    Store.Put(LIVE, { id = id, kind = d.kind, name = d.name, map = d.map,
        x = math.floor(d.x * 10000) / 10000, y = math.floor(d.y * 10000) / 10000, ts = now, by = ns.me() })
end
-- watched names (lowercase English): default the Black Lotus
local function watched(name)
    local info = GM.NodeInfo(name)
    if not info then return false end
    local w = S().gatherWatch
    if not w then return info.en == "Black Lotus" end
    return w[info.en] == true
end
GG.Watched = watched
local function setPin(map, x, y, name)
    -- 0.6.607: as Oasis target - with Shortest Path Forever installed it plans the whole journey
    if ns.Map and ns.Map.SetTarget then ns.Map.SetTarget({ mapID = map, x = x, y = y, label = name or "?" }) return end
    if not (C_Map.SetUserWaypoint and UiMapPoint) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x, y)) and C_SuperTrack then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end
GG.alerts = 0
ns.Listen("STORE", function(coll, rec)
    if coll ~= LIVE or type(rec) ~= "table" or S().gatherAlerts == false then return end
    if rec.by == ns.me() or ns.now() - (tonumber(rec.ts) or 0) > 300 then return end
    if not watched(rec.name) then return end
    GG.alerts = GG.alerts + 1
    local zone = ns.zoneName and ns.zoneName(rec.map) or tostring(rec.map)
    local text = (L["%s sees it in %s - click: set map pin"]):format(ns.displayName(rec.by or "?"), zone)
    if K.Toast then K.Toast((L["Guild find: %s"]):format(rec.name or "?"), text, C.amber or C.accent, function() setPin(rec.map, rec.x, rec.y, rec.name) end, true) end
    ns.print((L["Guild find: %s"]):format(rec.name or "?") .. " - " .. text)
end)

------------------------------------------------------------------------
-- no double work: guild members farming close by
------------------------------------------------------------------------
-- members on your map within 400 m who stored a node in the last 10 minutes
-- 0.6.600: cached for 2 seconds (it walks the zone's nodes and the guild positions)
local farmCache, farmAt = {}, -100
function GG.Farmers()
    local now = GetTime and GetTime() or 0
    if now - farmAt < 2 then return farmCache end
    farmAt = now
    farmCache = GG.FarmersNow()
    return farmCache
end
function GG.FarmersNow()
    local out = {}
    if S().gatherShareArea == false or not (ns.Map and ns.Map.Active) then return out end
    local c = GM.MiniCtx()
    if not c then return out end
    local recent = {}
    local t = ns.now()
    for _, r in ipairs(GM.Nodes(c.map)) do if r.by and t - (r.ts or 0) < 600 then recent[r.by] = true end end
    local ok, list = pcall(ns.Map.Active)
    if not ok then return out end
    for _, e in ipairs(list) do
        local p = e.p
        if p and p.mapID == c.map and not ns.SameName(e.name, ns.me()) and (recent[e.name] or recent[ns.displayName(e.name)]) then
            local dx, dy = (p.x - c.mx) * c.w, (p.y - c.my) * c.h
            if dx * dx + dy * dy < 400 * 400 then out[#out + 1] = { name = e.name, x = p.x, y = p.y } end
        end
    end
    return out
end
-- a node closer to a farming guild member than to you is theirs
function GG.Theirs(r, farmers, mx, my)
    if not farmers[1] then return false end
    local mine = (r.x - mx) ^ 2 + (r.y - my) ^ 2
    for _, f in ipairs(farmers) do
        if (r.x - f.x) ^ 2 + (r.y - f.y) ^ 2 < mine * 0.8 then return f.name end
    end
    return false
end
local toldAt = {}
function GG.TellFarmers(farmers)
    local now = GetTime and GetTime() or 0
    for _, f in ipairs(farmers) do
        if now - (toldAt[f.name] or -1000) > 900 then
            toldAt[f.name] = now
            ns.print((L["%s is gathering nearby too - the arrow leaves their side to them."]):format(ns.displayName(f.name)))
        end
    end
end

------------------------------------------------------------------------
-- farm statistics per zone + zone tips
------------------------------------------------------------------------
local lastHarvest, pendingLoot = nil, nil
local function stats(map)
    S().gatherStats = S().gatherStats or {}
    local st = S().gatherStats[map]
    if not st then st = { t = 0, n = 0, s = 0, v = 0, i = 0 } S().gatherStats[map] = st end
    return st
end
-- called by GM.Record on a real harvest
function GG.OnHarvest(map, kind)
    local now = GetTime and GetTime() or 0
    local st = stats(map)
    st.n = st.n + 1
    if lastHarvest and lastHarvest.map == map and now - lastHarvest.t < 300 then st.t = st.t + (now - lastHarvest.t) end
    lastHarvest = { map = map, t = now }
    pendingLoot = { map = map, t = now, kind = kind }
end
-- skill-ups: herbalism/mining rank went up
local lastRank = {}
function GG.CheckSkill()
    for _, kind in ipairs({ "herb", "ore" }) do
        local sk = GM.Skill(kind)
        if sk and sk.rank then
            if lastRank[kind] and sk.rank > lastRank[kind] and lastHarvest then
                local st = stats(lastHarvest.map)
                st.s = st.s + (sk.rank - lastRank[kind])
            end
            lastRank[kind] = sk.rank
        end
    end
end
ns.On("SKILL_LINES_CHANGED", function() if ns.After then ns.After(2.5, function() pcall(GG.CheckSkill) end) else pcall(GG.CheckSkill) end end)
ns.On("CHAT_MSG_SKILL", function() if ns.After then ns.After(2.5, function() pcall(GG.CheckSkill) end) end end)
-- loot right after a harvest: item count and vendor value
function GG.OnLoot(msg)
    if not pendingLoot then return end
    local now = GetTime and GetTime() or 0
    if now - pendingLoot.t > 6 then pendingLoot = nil return end
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local link = msg:match("|Hitem:[^|]+|h%[[^%]]+%]|h")
    if not link then return end
    local n = tonumber(msg:match("x(%d+)") or "1") or 1
    local id = tonumber(link:match("item:(%d+)"))
    local price = 0
    if id and C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, id)
        if ok and type(sell) == "number" then price = sell end
    elseif id and GetItemInfo then
        local sell = select(11, GetItemInfo(id))
        if type(sell) == "number" then price = sell end
    end
    -- guild price list (Trade) beats the vendor price
    if ns.Prices and ns.Prices.Get then local ok, p = pcall(ns.Prices.Get, id) if ok and type(p) == "number" and p > 0 then price = p end end
    local st = stats(pendingLoot.map)
    st.i = st.i + n
    st.v = st.v + price * n
end
ns.On("CHAT_MSG_LOOT", function(msg, who)
    who = ns.safe(who)
    if type(who) == "string" and who ~= "" and not ns.SameName(who, ns.me()) then return end   -- group members' loot
    pcall(GG.OnLoot, msg)
end)
local function money(c)
    c = math.floor(c or 0)
    local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
    if g > 0 then return ("%dg %ds"):format(g, s) end
    return ("%ds %dc"):format(s, c % 100)
end
GG.Money = money
function GG.StatLines()
    local rows = {}
    for map, st in pairs(S().gatherStats or {}) do if st.n > 0 then rows[#rows + 1] = { map = map, st = st } end end
    table.sort(rows, function(a, b) return a.st.n > b.st.n end)
    local out = {}
    for i = 1, math.min(8, #rows) do
        local r, st = rows[i], rows[i].st
        local hours = math.max(st.t, 60) / 3600
        out[#out + 1] = (L["%s: %d nodes (%d/h), +%d skill, %s (%s/h)"]):format(ns.zoneName and ns.zoneName(r.map) or tostring(r.map),
            st.n, math.floor(st.n / hours + 0.5), st.s, money(st.v), money(st.v / hours))
    end
    return out
end
-- zones where the guild knows the most nodes that still give you skill-ups (score: orange 3, yellow 2, green 1)
function GG.Recommend(limit)
    local per = {}
    for _, r in ipairs(GM.Nodes()) do
        local info = (r.kind == "herb" or r.kind == "ore") and GM.NodeInfo(r.name)
        local own = info and GM.Skill(info.kind)
        if own and own.rank then
            local over = own.rank - info.skill
            local score = over < 0 and 0 or over < 25 and 3 or over < 50 and 2 or over < 100 and 1 or 0
            if score > 0 then
                local z = per[r.map]
                if not z then z = { map = r.map, score = 0, n = 0, names = {} } per[r.map] = z end
                z.score, z.n = z.score + score, z.n + 1
                z.names[r.name] = (z.names[r.name] or 0) + 1
            end
        end
    end
    local list = {}
    for _, z in pairs(per) do list[#list + 1] = z end
    table.sort(list, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(limit or 5, #list) do
        local z = list[i]
        local names = {}
        for n, c in pairs(z.names) do names[#names + 1] = { n = n, c = c } end
        table.sort(names, function(a, b) return a.c > b.c end)
        local top = {}
        for j = 1, math.min(3, #names) do top[#top + 1] = names[j].n end
        local text = (L["%s: %d nodes for you (%s)"]):format(ns.zoneName and ns.zoneName(z.map) or tostring(z.map), z.n, table.concat(top, ", "))
        -- 0.6.607: travel time when Shortest Path Forever is installed
        local sec = ns.Compat and ns.Compat.SPFEstimate and ns.Compat.SPFEstimate(z.map, 0.5, 0.5)
        if sec then text = text .. "  |cff888888" .. (L["~%d min away"]):format(math.max(1, math.floor(sec / 60 + 0.5))) .. "|r" end
        out[#out + 1] = { map = z.map, n = z.n, score = z.score, text = text }
    end
    return out
end

-- panel: statistics + zone tips (/oa gatherstats or the button in the settings)
local panel
function GG.ShowPanel()
    if not panel then
        panel = CreateFrame("Frame", "OasisGatherStats", UIParent)
        panel:SetSize(520, 360)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true) panel:SetMovable(true) panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving) panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        K.Fill(panel, { 0.035, 0.035, 0.045, 0.97 })
        K.Border(panel, C.line)
        if K.ApplySkin then K.ApplySkin(panel, "panel", { 0.035, 0.035, 0.045, 0.97 }) end
        panel.h = K.Title(panel, 16, C.text)
        panel.h:SetPoint("TOPLEFT", 22, -20)
        panel.h:SetText(L["Farm statistics"])
        panel.a = K.Text(panel, 12, C.text)
        panel.a:SetPoint("TOPLEFT", 22, -50) panel.a:SetPoint("RIGHT", panel, "RIGHT", -22, 0)
        panel.a:SetJustifyH("LEFT") panel.a:SetSpacing(4)
        panel.h2 = K.Title(panel, 14, C.text)
        panel.h2:SetPoint("TOPLEFT", 22, -200)
        panel.h2:SetText(L["Where it pays off for your skill"])
        panel.b = K.Text(panel, 12, C.text)
        panel.b:SetPoint("TOPLEFT", 22, -226) panel.b:SetPoint("RIGHT", panel, "RIGHT", -22, 0)
        panel.b:SetJustifyH("LEFT") panel.b:SetSpacing(4)
        panel.close = K.Button(panel, L["Close"], 100, 26, "ghost", function() panel:Hide() end)
        panel.close:SetPoint("BOTTOMRIGHT", -18, 14)
        panel.reset = K.Button(panel, L["Reset statistics"], 150, 26, "ghost", function() S().gatherStats = nil GG.ShowPanel() end)
        panel.reset:SetPoint("BOTTOMLEFT", 18, 14)
    end
    local a = GG.StatLines()
    panel.a:SetText(#a > 0 and table.concat(a, "\n") or ("|cff888888" .. L["Nothing gathered yet - the statistics fill up as you gather."] .. "|r"))
    local b = {}
    for _, z in ipairs(GG.Recommend(5)) do b[#b + 1] = z.text end
    panel.b:SetText(#b > 0 and table.concat(b, "\n") or ("|cff888888" .. L["The guild knows no nodes for your skill yet."] .. "|r"))
    panel:Show()
end
ns.slash.gatherstats = GG.ShowPanel
ns.slash.sammelstatistik = GG.ShowPanel

-- watch list menu (settings button)
function GG.WatchMenu(anchor)
    local items = {}
    for _, e in ipairs(GM.NodeList()) do
        items[#items + 1] = { text = e.name .. "  |cff888888" .. e.skill .. "|r", checked = watched(e.name), fn = function()
            local w = S().gatherWatch
            if not w then w = { ["Black Lotus"] = true } S().gatherWatch = w end
            w[e.en] = (not w[e.en]) or nil
        end }
    end
    K.ShowMenu(anchor, items, L["Guild finds: notify me for"])
end
end)

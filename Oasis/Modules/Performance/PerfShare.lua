-- Oasis: record performance for all members + developer tab (0.5.562)
--  * every client measures silently: Oasis CPU time per frame (Blizzard's AddOn profiler), peak, frame rate, memory
--  * every 15 min (and on developer request) a summary into the shared store "perf"
--  * Developer page in the sidebar (only in developer mode): unlocks, tools, performance table
local ADDON, ns = ...
ns.ModuleFile("Oasis_Performance", function()   -- Performance measurement module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local P = {}
ns.PerfShare = P
local COLL = "perf"

------------------------------------------------------------------------
-- Measure
------------------------------------------------------------------------
local acc = { n = 0, sum = 0, peak = 0, fps = 0, cn = 0, csum = 0, start = 0 }
-- 0.5.568: core + loaded modules (extra addons) together
local function parts() return ns.ModuleLoader and ns.ModuleLoader.Addons() or { ADDON } end
local function metric(k)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[k]) then return nil end
    local sum, any = 0, false
    for _, a in ipairs(parts()) do
        local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, a, Enum.AddOnProfilerMetric[k])
        if ok and type(v) == "number" then
            any = true
            if k == "PeakTime" then sum = math.max(sum, v) else sum = sum + v end
        end
    end
    return any and sum or nil
end
local function sample()
    local ra = metric("RecentAverageTime")
    local pk = metric("PeakTime")
    local fps = GetFramerate and GetFramerate() or 0
    if acc.start == 0 then acc.start = ns.now() end
    if ra then
        acc.n, acc.sum = acc.n + 1, acc.sum + ra
        if ns.inCombat() then acc.cn, acc.csum = acc.cn + 1, acc.csum + ra end
    end
    if pk and pk > acc.peak then acc.peak = pk end
    acc.fps = acc.fps + fps
    acc.fn = (acc.fn or 0) + 1
end
local function memKB()
    if ns.inCombat() then return P.lastMem end
    local up = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (up and get) then return nil end
    pcall(up)
    local sum = 0
    for _, a in ipairs(parts()) do
        local ok, v = pcall(get, a)
        if ok and v then sum = sum + v end
    end
    if sum > 0 then P.lastMem = math.floor(sum) end
    return P.lastMem
end
function P.Share(force)
    if not (ns.me and ns.me()) or not IsInGuild() or ns.db.settings.sharePerf == false then return end
    if (acc.fn or 0) == 0 then sample() end
    local rec = {
        id = "perf-" .. ns.me(), who = ns.me(), v = ns.version, t = ns.now(),
        avg = acc.n > 0 and math.floor(acc.sum / acc.n * 1000 + 0.5) / 1000 or nil,       -- ms per frame (average)
        cav = acc.cn > 0 and math.floor(acc.csum / acc.cn * 1000 + 0.5) / 1000 or nil,    -- ms per frame in combat
        peak = math.floor((acc.peak or 0) * 10 + 0.5) / 10,                              -- ms peak
        fps = math.floor(acc.fps / math.max(1, acc.fn or 1) + 0.5),
        mem = memKB(), n = acc.n, sess = math.floor((ns.now() - (acc.start or ns.now())) / 60),
        ses = metric("SessionAverageTime"),
        addons = P.AddonCount and P.AddonCount() or nil,
        mods = #parts() - 1,   -- loaded Oasis modules
    }
    if rec.ses then rec.ses = math.floor(rec.ses * 1000 + 0.5) / 1000 end
    Store.Put(COLL, rec)
    P.lastShare = GetTime()
    if force then ns.print(L["Performance sent."]) end
end
function P.AddonCount()
    local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local Loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not (GetNum and Loaded) then return nil end
    local n = 0
    for i = 1, GetNum() do local ok, l = pcall(Loaded, i) if ok and l then n = n + 1 end end
    return n
end
ns.Listen("LOGIN", function()
    ns.Every(30, function() pcall(sample) end)
    ns.Every(900, function() if not ns.inCombat() then pcall(P.Share) end end)
    ns.After(300, function() if not ns.inCombat() then pcall(P.Share) end end)
end)
-- developer asks everyone: measure 60 s, then send
if ns.Comm then
    ns.Comm.On("PERFREQ", function(sender)
        if ns.Comm.FromGuild and not ns.Comm.FromGuild(sender) then return end
        -- 0.5.617: measurement only on request of officers/guild leadership
        local role = ns.Admin and ns.Admin.RoleOf and ns.Admin.RoleOf(sender)
        if role ~= "officer" and role ~= "lead" then return end
        if P.reqAt and GetTime() - P.reqAt < 120 then return end
        P.reqAt = GetTime()
        acc.peak = 0
        ns.After(60, function() pcall(P.Share) end)
    end)
end
function P.RequestAll()
    if ns.Comm and ns.Comm.Guild then ns.Comm.Guild("PERFREQ") end
    P.reqAt = nil
    ns.After(60, function() pcall(P.Share) end)
    K.Toast(L["Performance"], L["All Oasis users now measure for 60 seconds and send the result."], C.accent)
end
-- permissions: only your own record
local function installAuth()
    local A = ns.Admin
    if not (A and A.AUTH) then return end
    A.AUTH[COLL] = function(rec, actor) return rec.who ~= nil and A.SameName(rec.who, actor) end
end
installAuth()
ns.Listen("LOGIN", installAuth)
ns.Listen("STORE", function(coll) if coll == COLL then ns.Debounce("perfTab", 1, function() ns.RefreshPage("dev") end) end end)

-- 0.5.568: don't keep diagnostic data (meant only for the developer) in memory for everyone else
ns.Listen("LOGIN", function()
    if ns.IsDev and ns.IsDev() then return end
    ns.db.blizzProbe, ns.db.talentProbe = nil, nil
    local h = ns.db.talHarvest
    if type(h) == "table" then ns.db.talHarvest = { ts = h.ts, v = h.v, learned = h.learned } end
end)

------------------------------------------------------------------------
-- emojis and sounds free for all (rank lock off): once in the guild setting by the developer
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    ns.After(20, function()
        -- 0.6.417: the other way round - turn on the rank lock for the guild once
        if not (ns.IsDev and ns.IsDev()) or ns.db.emLockOn then return end
        local A = ns.Admin
        if not (A and A.Cfg and A.Save and A.CanManage and A.CanManage()) then return end
        local ok, cfg = pcall(A.Cfg)
        if not ok or type(cfg) ~= "table" then return end
        ns.db.emLockOn = true
        if cfg.emLock ~= true then
            local c = {}
            for k, v in pairs(cfg) do c[k] = v end
            c.emLock = true
            pcall(A.Save, c)
            ns.print(L["Emojis and sounds now unlock with the matching Oasis rank."])
        end
    end)
end)

------------------------------------------------------------------------
-- "Developer" page (sidebar, only in developer mode) - 0.5.570
------------------------------------------------------------------------
local function devCard(p, icon, title, sub)
    local c = CreateFrame("Frame", nil, p)
    c:SetFrameLevel(math.max(1, p:GetFrameLevel()))
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 12)) then
        K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, { C.line[1], C.line[2], C.line[3], 0.6 })
    end
    c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. icon, C.accent)
    c.ic:SetPoint("TOPLEFT", 14, -14)
    c.t = K.Title(c, 14, C.text)
    c.t:SetPoint("LEFT", c.ic, "RIGHT", 8, 0)
    c.t:SetText(title)
    if sub then
        c.s = K.Text(c, 10, C.dim)
        c.s:SetPoint("TOPLEFT", c.ic, "BOTTOMLEFT", 0, -6)
        c.s:SetPoint("RIGHT", -14, 0)
        c.s:SetJustifyH("LEFT")
        c.s:SetText(sub)
    end
    return c
end
local function guildCfg()
    local ok, cfg = pcall(ns.Admin.Cfg)
    return ok and type(cfg) == "table" and cfg or nil
end
-- performance table columns: key, header, x, width, right-aligned
local COLS = {
    { k = "name", t = "Name", x = 14, w = 170 },
    { k = "avg", t = "ms/frame", x = 190, w = 62, r = true },
    { k = "cav", t = "in a fight", x = 256, w = 66, r = true },
    { k = "peak", t = "Peak", x = 326, w = 58, r = true },
    { k = "fps", t = "FPS", x = 388, w = 44, r = true },
    { k = "mem", t = "Memory", x = 436, w = 70, r = true },
    -- 0.5.671: column "Modules" removed (since 0.5.580 a single folder, always 0)
    { k = "v", t = "Version", x = 524, w = 70 },
    { k = "t", t = "gemessen", x = 608, w = 90 },
}
local ROWS = 16
ns.RegisterPage({
    key = "dev", title = "Developer", order = 98.5,
    sub = "Unlocks, tools and member performance",
    visible = function() return ns.IsDev and ns.IsDev() or false end,
    build = function(p)
        p.sortKey, p.sortDesc = "avg", true
        -- Unlocks (top left)
        local a = devCard(p, "star_on", L["Unlocks"], L["Emojis and sounds for the guild or just for you"])
        a:SetPoint("TOPLEFT", 0, 0)
        a:SetPoint("RIGHT", p, "CENTER", -7, 0)
        a:SetHeight(160)
        p.lock = K.Toggle(a, L["Emojis & sounds only from Oasis rank (guild)"], function() local c = guildCfg() return c and c.emLock == true or false end, function(v)
            local cfg = guildCfg()
            if not cfg then return end
            local c = {}
            for k, x in pairs(cfg) do c[k] = x end
            c.emLock = v and true or false
            if not ns.Admin.Save(c) then K.Toast(L["Unlocks"], L["Only the guild leadership can change this."], C.amber or C.accent) end
        end)
        p.lock:SetPoint("TOPLEFT", 14, -58)
        p.lock:SetWidth(320)
        p.mine = K.Toggle(a, L["Unlock everything for me"], function() return ns.db.settings.unlockAll == true end, function(v) ns.db.settings.unlockAll = v and true or nil end)
        p.mine:SetPoint("TOPLEFT", 14, -88)
        p.mine:SetWidth(320)
        -- Tools (top right)
        local w = devCard(p, "settings", L["Tools"], L["Diagnostics and sync"])
        w:SetPoint("TOPRIGHT", 0, 0)
        w:SetPoint("LEFT", p, "CENTER", 7, 0)
        w:SetHeight(160)
        local tools = {
            -- 0.6.534: error reports directly reachable (before only by right-clicking the bug icon or tab)
            { L["Bug reports"], function() ns.ShowPage("bugs") end, true },
            { L["Report a bug"], function() if ns.slash.bug then ns.slash.bug() end end },
            { L["Blocked log"], function() if ns.slash.fehler then ns.slash.fehler() end end },
            { L["Measure performance (60 s)"], function() if ns.slash.leistung then ns.slash.leistung("60") end end },
            { L["Blizzard check"], function() if ns.probes and ns.probes.blizz then ns.probes.blizz() end end },
            { L["Learn talent icons"], function() if ns.slash.talentsymbole then ns.slash.talentsymbole() end end },
            { L["Sync now"], function() if ns.Comm and ns.Comm.RequestSync then ns.Comm.RequestSync(true) end end },
        }
        p.tools = {}
        for i, t in ipairs(tools) do
            local b = K.Button(w, t[1], 150, 24, t[3] and "primary" or "ghost", t[2])
            p.tools[i] = b
            if t[3] then p.bugsBtn = b end
        end
        local function layoutTools()
            local cw = (w:GetWidth() or 360) - 28
            local bw = math.floor((cw - 3 * 8) / 3)
            for i, b in ipairs(p.tools) do
                b:SetWidth(bw)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 14 + ((i - 1) % 3) * (bw + 8), -56 - math.floor((i - 1) / 3) * 32)
            end
        end
        w:SetScript("OnSizeChanged", layoutTools)
        layoutTools()
        -- members' performance (full width)
        local t = devCard(p, "stats", L["Member performance"], L["Oasis CPU time per frame for each member - green good, yellow medium, red high"])
        t:SetPoint("TOPLEFT", 0, -174)
        t:SetPoint("BOTTOMRIGHT", 0, 0)
        p.req = K.Button(t, L["Measure everyone now"], 150, 24, "primary", function() P.RequestAll() end)
        p.req:SetPoint("TOPRIGHT", -14, -12)
        p.heads = {}
        for _, c in ipairs(COLS) do
            local h = CreateFrame("Button", nil, t)
            h:SetSize(c.w, 18)
            h:SetPoint("TOPLEFT", c.x, -54)
            h.t = K.Text(h, 10, C.dim, c.r and "RIGHT" or "LEFT")
            h.t:SetAllPoints()
            h.t:SetText(K.Upper and K.Upper(L[c.t]) or L[c.t])
            h:SetScript("OnClick", function()
                if p.sortKey == c.k then p.sortDesc = not p.sortDesc else p.sortKey, p.sortDesc = c.k, c.k ~= "name" end
                ns.RefreshPage("dev")
            end)
            h:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
            h:SetScript("OnLeave", function(self) local d = C.dim self.t:SetTextColor(d[1], d[2], d[3]) end)
            p.heads[c.k] = h
        end
        local line = t:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 14, -74)
        line:SetPoint("TOPRIGHT", -14, -74)
        p.rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Frame", nil, t)
            r:SetHeight(20)
            r:SetPoint("TOPLEFT", 0, -78 - (i - 1) * 21)
            r:SetPoint("RIGHT", t, "RIGHT", 0, 0)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetPoint("TOPLEFT", 8, 0) r.bg:SetPoint("BOTTOMRIGHT", -8, 0)
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
            -- small bar below ms/frame: how heavy Oasis is for this member
            r.bar = r:CreateTexture(nil, "BORDER")
            r.bar:SetHeight(14)
            r.bar:SetPoint("RIGHT", r, "LEFT", COLS[2].x + COLS[2].w, 0)
            r.cells = {}
            for _, c in ipairs(COLS) do
                local fs = K.Text(r, 12, C.text, c.r and "RIGHT" or "LEFT")
                fs:SetPoint("LEFT", c.x, 0)
                fs:SetWidth(c.w)
                fs:SetWordWrap(false)
                r.cells[c.k] = fs
            end
            p.rows[i] = r
        end
        p.empty = K.Text(t, 12, C.dim)
        p.empty:SetPoint("TOPLEFT", 14, -84)
        p.empty:SetText(L["No data yet - members send their measurement every 15 min (from this version)."])
        p.more = K.Text(t, 10, C.dim)
        p.more:SetPoint("BOTTOMLEFT", 14, 10)
    end,
    refresh = function(p)
        -- 0.6.534: number of new error reports on the button
        if p.bugsBtn then
            local n = ns.Bugs and ns.Bugs.NewCount and ns.Bugs.NewCount() or 0
            p.bugsBtn:SetLabel(L["Bug reports"] .. (n > 0 and ("  (" .. n .. ")") or ""))
        end
        if p.lock then p.lock:Refresh() p.mine:Refresh() end
        local list = Store.List(COLL)
        -- 0.5.663: one entry per player (alts merged, e.g. Anna + Tomas) - the newest measurement counts
        local A, best = ns.Alts, {}
        -- 0.5.671: only measurements of the last 3 hours (old alt/old version rows drop out)
        local cutoff = ns.now() - 3 * 3600
        for _, r in ipairs(list) do
            if (r.t or 0) >= cutoff then
                local who = tostring(r.by or r.who or "")   -- full name (with realm) for the alt mapping
                local key = who:lower()
                if A and A.Main then
                    local ok, m = pcall(A.Main, who)
                    if ok and m then key = tostring(m):lower() end
                end
                if not best[key] or (r.t or 0) > (best[key].t or 0) then best[key] = r end
            end
        end
        list = {}
        for _, r in pairs(best) do list[#list + 1] = r end
        local k, desc = p.sortKey, p.sortDesc
        table.sort(list, function(a, b)
            local x, y
            if k == "name" then x, y = tostring(a.who or ""):lower(), tostring(b.who or ""):lower()
            elseif k == "v" then x, y = tostring(a.v or ""), tostring(b.v or "")
            elseif k == "t" then x, y = a.t or 0, b.t or 0
            else x, y = tonumber(a[k]) or -1, tonumber(b[k]) or -1 end
            if x == y then return tostring(a.who) < tostring(b.who) end
            if desc then return x > y end
            return x < y
        end)
        for ck, h in pairs(p.heads) do
            local arrow = (ck == k) and (desc and "  v" or "  ^") or ""
            local c
            for _, cc in ipairs(COLS) do if cc.k == ck then c = cc end end
            h.t:SetText((K.Upper and K.Upper(L[c.t]) or L[c.t]) .. arrow)
        end
        p.empty:SetShown(#list == 0)
        local maxAvg = 0.01
        for _, e in ipairs(list) do if (e.avg or 0) > maxAvg then maxAvg = e.avg end end
        for i, r in ipairs(p.rows) do
            local e = list[i]
            r:SetShown(e ~= nil)
            if e then
                local avg = e.avg or 0
                local col = avg >= 1.5 and { 1, 0.38, 0.38 } or (avg >= 0.6 and { 0.91, 0.71, 0.29 } or { 0.4, 0.86, 0.62 })
                local who = tostring(e.who or "?")
                r.cells.name:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(who:match("^[^-]+") or who) or who)
                r.cells.avg:SetText(("%.2f"):format(avg))
                r.cells.avg:SetTextColor(col[1], col[2], col[3])
                r.cells.cav:SetText(e.cav and ("%.2f"):format(e.cav) or "|cff555555-|r")
                r.cells.peak:SetText(e.peak and ("%.0f"):format(e.peak) or "-")
                r.cells.fps:SetText(e.fps or "-")
                r.cells.mem:SetText(e.mem and ("%.1f MB"):format(e.mem / 1024) or "-")
                r.cells.v:SetText("|cff9a9aa5" .. tostring(e.v or "?") .. "|r")
                r.cells.t:SetText("|cff777777" .. ns.ago(e.t or 0) .. "|r")
                r.bar:SetColorTexture(col[1], col[2], col[3], 0.14)
                r.bar:SetWidth(math.max(1, COLS[2].w * math.min(1, avg / maxAvg)))
            end
        end
        p.more:SetText(#list > ROWS and (L["+%d more"]):format(#list - ROWS) or "")
    end,
})
end)

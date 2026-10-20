-- Oasis - live performance meter (Settings > Profile & Data > Performance)
-- Shows in real time how much CPU time Oasis is using: big number, curve over the last minutes, peak, session average, memory.
-- Data source: Blizzard's addon profiler (C_AddOnProfiler) - measures the whole addon (windows, events, timers), not just the Oasis functions.
-- Measured only while the tab is open (one call per second, practically free).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Performance", function()   -- Performance measurement module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local PERF = {}
ns.PerfLive = PERF

local MAXN = 300                       -- seconds of history
local hist = {}                        -- ms per frame (RecentAverageTime), one value per second
local histMem = {}                     -- MB
local paused, windowSec = false, 120
local ADDONS = { ADDON, "Oasis_Guild" }

local function metric(name)
    local P = C_AddOnProfiler
    if not (P and P.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then return nil end
    local e = Enum.AddOnProfilerMetric[name]
    if e == nil then return nil end
    local sum, any = 0, false
    for _, a in ipairs(ADDONS) do
        local ok, v = pcall(P.GetAddOnMetric, a, e)
        if ok and type(v) == "number" and not (issecretvalue and issecretvalue(v)) then sum = sum + v any = true end
    end
    return any and sum or nil
end
local function memMB()
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not get then return nil end
    local sum = 0
    for _, a in ipairs(ADDONS) do
        local ok, v = pcall(get, a)
        if ok and type(v) == "number" then sum = sum + v end
    end
    return sum / 1024
end

-- color by CPU time per frame: up to 0.5 ms calm, up to 1.5 ms noticeable, above that a lot
local function level(ms)
    if ms < 0.5 then return C.mint, L["calm"] end
    if ms < 1.5 then return C.amber, L["noticeable"] end
    return C.red, L["high"]
end

local function build(f)
    local H = ns.SettingsHelpers
    f.noCompact = true
    local W = 738
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric) then
        local t = K.Text(f, 12, C.muted)
        t:SetPoint("TOPLEFT", 4, -8)
        t:SetText(L["This client provides no add-on metrics (C_AddOnProfiler missing)."])
        return
    end

    -- Header: big number + rating ------------------------------------------------------
    local top = H.cardH(f, 0, 0, W, 124, "stats", L["Compute time now"], L["Live, updated every second - Oasis and guild module combined"])
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
    f.big = K.Title(top, 34, C.text)
    f.big:SetPoint("TOPLEFT", 16, -56)
    f.unit = K.Text(top, 12, C.muted)
    f.unit:SetPoint("BOTTOMLEFT", f.big, "BOTTOMRIGHT", 6, 5)
    f.unit:SetText(L["ms per frame"])
    f.state = K.Text(top, 12, C.text)
    f.state:SetPoint("TOPLEFT", f.big, "BOTTOMLEFT", 2, -4)
    -- right in the header: four stats
    f.tiles = {}
    local TILES = { { "peak", L["Peak"] }, { "avg", L["Session avg"] }, { "mem", L["Memory"] }, { "fps", L["Frames / sec"] } }
    for i, t in ipairs(TILES) do
        local x = 330 + (i - 1) * 100
        local v = K.Title(top, 18, C.text)
        v:SetPoint("TOPLEFT", x, -52)
        local l = K.Text(top, 10, C.dim)
        l:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -3)
        l:SetText(t[2])
        f.tiles[t[1]] = v
    end

    -- Graph --------------------------------------------------------------------------------
    local gc = H.cardH(f, 0, -136, W, 288, "stats", L["Gradient"], L["Hover for individual values"])
    gc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -136)
    f.seg = K.Segments(gc, { { key = 60, text = L["1 min"] }, { key = 120, text = L["2 min"] }, { key = 300, text = L["5 min"] } },
        function(k) windowSec = k PERF.Draw(f) end)
    f.seg:SetPoint("TOPRIGHT", gc, "TOPRIGHT", -112, -10)
    f.seg:Select(windowSec)
    f.pauseBtn = K.Button(gc, L["Pause"], 90, 22, "ghost", function(self)
        paused = not paused
        self:SetLabel(paused and L["Resume"] or L["Pause"])
    end)
    f.pauseBtn:SetPoint("TOPRIGHT", gc, "TOPRIGHT", -14, -10)

    local g = CreateFrame("Frame", nil, gc)
    g:SetPoint("TOPLEFT", 16, -58)
    g:SetPoint("BOTTOMRIGHT", gc, "BOTTOMRIGHT", -16, 34)
    f.g = g
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0, 0, 0, 0.18)
    g.bars, g.lines, g.grid, g.gridTx = {}, {}, {}, {}
    for i = 1, 3 do
        local ln = g:CreateTexture(nil, "BORDER")
        ln:SetHeight(1)
        ln:SetColorTexture(1, 1, 1, 0.07)
        g.grid[i] = ln
        local tx = K.Text(g, 9, C.dim, "RIGHT")
        g.gridTx[i] = tx
    end
    g.cross = g:CreateTexture(nil, "OVERLAY")
    g.cross:SetWidth(1)
    g.cross:SetColorTexture(1, 1, 1, 0.35)
    g.cross:Hide()
    g.dot = g:CreateTexture(nil, "OVERLAY")
    g.dot:SetSize(7, 7)
    g.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    g.dot:Hide()
    g.read = K.Text(g, 11, C.text)
    g.read:Hide()
    g.empty = K.Text(g, 12, C.dim, "CENTER")
    g.empty:SetPoint("CENTER")
    g.empty:SetText(L["Measuring ... the curve builds up shortly."])
    g:EnableMouse(true)
    g:SetScript("OnLeave", function(self)
        self.cross:Hide() self.dot:Hide() self.read:Hide()
        self:SetScript("OnUpdate", nil)
    end)
    g:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", function() PERF.Hover(f) end)
    end)
    -- below the graph: legend / action
    f.legend = K.Text(gc, 11, C.muted)
    f.legend:SetPoint("BOTTOMLEFT", gc, "BOTTOMLEFT", 16, 12)
    f.report = K.Button(gc, L["Report (60 s)"], 150, 22, "ghost", function() if ns.PerfStart then ns.PerfStart(60) end end)
    f.report:SetPoint("BOTTOMRIGHT", gc, "BOTTOMRIGHT", -14, 8)

    f:HookScript("OnShow", function() PERF.Sample(f) end)
    PERF.Draw(f)
end

-- one measurement ----------------------------------------------------------------------------
function PERF.Sample(f)
    if paused then return end
    local ms = metric("RecentAverageTime")
    if ms == nil then return end
    hist[#hist + 1] = ms
    histMem[#histMem + 1] = memMB() or 0
    while #hist > MAXN do table.remove(hist, 1) table.remove(histMem, 1) end
    PERF.Draw(f)
end

-- 0.5.779: fixed time axis (right = now, left = window start) and smoothed curve. Before, a few points were stretched across the whole
-- width and the area consisted of wide columns - that looked steppy.
local STEP = 3   -- pixels per column of the area; the line takes every second point

-- x position of sample i (1..n) in the fixed time window
local function xOf(g, i, n)
    local w = g:GetWidth()
    local slot = windowSec - n + i
    return (slot - 1) / math.max(1, windowSec - 1) * w
end
local function yOf(g, v, vmax)
    return math.max(1, v / vmax * (g:GetHeight() - 6))
end
-- smoothed value at the fractional position t (1..n): Catmull-Rom through the samples, never below 0
local function valAt(first, n, t)
    local i = math.floor(t)
    if i >= n then return hist[first + n - 1] end
    if i < 1 then return hist[first] end
    local u = t - i
    local p1, p2 = hist[first + i - 1], hist[first + i]
    local p0 = hist[first + math.max(1, i - 1) - 1]
    local p3 = hist[first + math.min(n, i + 2) - 1]
    local v = 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)
    -- limit overshoot: never outside the two neighbor values by more than their distance
    local lo, hi = math.min(p1, p2), math.max(p1, p2)
    local pad = (hi - lo) * 0.15
    if v < lo - pad then v = lo - pad elseif v > hi + pad then v = hi + pad end
    return math.max(0, v)
end

function PERF.Draw(f)
    local g = f and f.g
    if not g or not f.big then return end
    local n = math.min(#hist, windowSec)
    local cur = hist[#hist]
    -- Numbers
    if cur then
        local col, word = level(cur)
        f.big:SetText(("%.2f"):format(cur))
        f.big:SetTextColor(col[1], col[2], col[3])
        local fps = GetFramerate and GetFramerate() or 0
        local pct = cur / 16.67 * 100
        f.state:SetText(K.hex(col) .. word .. "|r  -  " .. (L["%.1f %% of a frame at 60 frames per second"]):format(pct))
        f.tiles.peak:SetText(("%.1f ms"):format(metric("PeakTime") or 0))
        f.tiles.avg:SetText(("%.2f ms"):format(metric("SessionAverageTime") or 0))
        f.tiles.mem:SetText(("%.1f MB"):format(histMem[#histMem] or 0))
        f.tiles.fps:SetText(("%.0f"):format(fps))
    end
    g.empty:SetShown(n < 2)
    local over1 = metric("CountTimeOver1Ms")
    f.legend:SetText(over1 and (L["Frames over 1 ms (this session): %d"]):format(math.floor(over1 + 0.5)) or "")
    if n < 2 then
        for _, b in ipairs(g.bars) do b:Hide() end
        for _, l in ipairs(g.lines) do l:Hide() end
        for i = 1, 3 do g.grid[i]:Hide() g.gridTx[i]:Hide() end
        g.n = nil
        return
    end
    local first = #hist - n + 1
    local vmax = 0.2
    for i = first, #hist do if hist[i] > vmax then vmax = hist[i] end end
    vmax = vmax * 1.25
    -- Guide lines
    for i = 1, 3 do
        local v = vmax * i / 3
        local y = v / vmax * (g:GetHeight() - 6)
        g.grid[i]:ClearAllPoints()
        g.grid[i]:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, y)
        g.grid[i]:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, y)
        g.grid[i]:Show()
        g.gridTx[i]:ClearAllPoints()
        g.gridTx[i]:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -4, y + 2)
        g.gridTx[i]:SetText(("%.2f ms"):format(v))
        g.gridTx[i]:Show()
    end
    -- area (narrow columns) and curve (short line segments), both from the smoothed curve
    local col = level(cur or 0)
    local w = g:GetWidth()
    local x1 = xOf(g, 1, n)
    local span = math.max(1, w - x1)
    local hasLine = g.CreateLine ~= nil
    local nb, nl2 = 0, 0
    local px, py
    local k = 0
    local x = x1
    while x <= w + 0.01 do
        local t = 1 + (x - x1) / span * (n - 1)
        local y = yOf(g, valAt(first, n, t), vmax)
        nb = nb + 1
        local b = g.bars[nb]
        if not b then
            b = g:CreateTexture(nil, "ARTWORK")
            g.bars[nb] = b
        end
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x, 0)
        b:SetSize(math.min(STEP, math.max(1, w - x)), y)
        b:SetColorTexture(col[1], col[2], col[3], 0.14)
        b:Show()
        if hasLine and k % 2 == 0 then
            if px then
                nl2 = nl2 + 1
                local ln = g.lines[nl2]
                if not ln then
                    ln = g:CreateLine(nil, "OVERLAY")
                    ln:SetThickness(2)
                    g.lines[nl2] = ln
                end
                ln:SetStartPoint("BOTTOMLEFT", g, px, py)
                ln:SetEndPoint("BOTTOMLEFT", g, x, y)
                ln:SetColorTexture(col[1], col[2], col[3], 0.95)
                ln:Show()
            end
            px, py = x, y
        end
        k = k + 1
        x = x + STEP
    end
    for i = nb + 1, #g.bars do g.bars[i]:Hide() end
    for i = nl2 + 1, #g.lines do if g.lines[i] then g.lines[i]:Hide() end end
    g.n, g.first, g.vmax = n, first, vmax
end

-- mouse over the graph: crosshair, dot and single value
function PERF.Hover(f)
    local g = f.g
    if not g or not g.n or g.n < 2 then return end
    local cx = GetCursorPosition() / g:GetEffectiveScale()
    local l = g:GetLeft()
    if not l then return end
    local n = g.n
    local x1 = xOf(g, 1, n)
    local frac = math.max(0, math.min(1, ((cx - l) - x1) / math.max(1, g:GetWidth() - x1)))
    local i = math.floor(frac * (n - 1) + 0.5) + 1
    local v = hist[g.first + i - 1]
    if not v then return end
    local x, y = xOf(g, i, n), yOf(g, v, g.vmax)
    g.cross:ClearAllPoints()
    g.cross:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x, 0)
    g.cross:SetHeight(g:GetHeight())
    g.cross:Show()
    local col = level(v)
    g.dot:ClearAllPoints()
    g.dot:SetPoint("CENTER", g, "BOTTOMLEFT", x, y)
    g.dot:SetVertexColor(col[1], col[2], col[3], 1)
    g.dot:Show()
    local ago = n - i
    g.read:SetText(("%.2f ms  -  %s  -  %.1f MB"):format(v, ago == 0 and L["now"] or (L["%d s ago"]):format(ago), histMem[g.first + i - 1] or 0))
    g.read:ClearAllPoints()
    if x > g:GetWidth() * 0.6 then g.read:SetPoint("TOPRIGHT", g, "TOPLEFT", x - 8, -6) else g.read:SetPoint("TOPLEFT", g, "TOPLEFT", x + 8, -6) end
    g.read:Show()
end

-- one sample per second, only while the tab is visible
local tabFrame
ns.Every(1, function()
    if tabFrame and tabFrame:IsVisible() then PERF.Sample(tabFrame) end
end)

if ns.AddSettingsTab then
    ns.AddSettingsTab("perf", "Performance", function(f) tabFrame = f build(f) end, function(f) tabFrame = f PERF.Draw(f) end)
end
end)

-- Oasis: settings tab "Sidebar" (0.6.614) - every entry of the sidebar with a switch, grouped like the sidebar.
-- Built fresh each time it opens from what is installed: an add-on that is missing has no entries here, a new one
-- shows up by itself. Switching off = hidden (and, once all pages of a module are off, the module is not loaded
-- any more - see ModuleLoader.PageToggled). Switched-off modules stay listed so they can be switched on again.
-- 0.6.656: like the comfort pages - left a live copy of the sidebar, right tiles (icon, explanation, switch, cog
-- for the settings of the area). Hovering a tile frames its entry in the copy.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local SB = {}
ns.SidebarTab = SB

-- groups like the sidebar; entries of no group go to "More", stubs of switched-off modules to "Switched off"
function SB.Groups()
    local D = ns.Discover
    if not D then return {} end
    local toggleable = {}
    for _, d in ipairs(D.Pages()) do toggleable[d.key] = d end
    local used, out = {}, {}
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        local list = {}
        for _, k in ipairs(g.pages or {}) do
            local d = toggleable[k]
            if d and not d.stub and not used[k] then list[#list + 1] = d used[k] = true end
        end
        if #list > 0 then out[#out + 1] = { g = g, list = list } end
    end
    local more, off = {}, {}
    for _, d in ipairs(D.Pages()) do
        if not used[d.key] then
            if d.stub then off[#off + 1] = d else more[#more + 1] = d end
        end
    end
    if #more > 0 then out[#out + 1] = { g = { key = "more", text = "More" }, list = more } end
    if #off > 0 then out[#out + 1] = { g = { key = "off", text = "Switched off" }, list = off } end
    return out
end

local PVW, GAP = 214, 18
local function subOf(d)
    local s = d.subFn and d.subFn() or d.sub
    return s and L[s] or nil
end

------------------------------------------------------------------------
-- preview: the sidebar as it will look - only the entries that are on, in their group colours
------------------------------------------------------------------------
local function buildPreview(f)
    local pv = CreateFrame("Frame", nil, f)
    pv:SetSize(PVW, 300)
    pv:SetPoint("TOPLEFT", 0, -44)
    local G = ns.Insta and ns.Insta.Glass
    if not (G and pcall(G, pv, { 0, 0, 0, 0.35 }, { 1, 1, 1, 0.08 }, 10)) then K.Fill(pv, { 0, 0, 0, 0.35 }) K.Border(pv, C.line) end
    pv.head = K.Text(pv, 10, C.dim)
    pv.head:SetPoint("TOPLEFT", 12, -10)
    pv.head:SetText(K.Upper(L["Your sidebar"]))
    pv.inner = CreateFrame("Frame", nil, pv)
    pv.inner:SetPoint("TOPLEFT", 10, -28)
    pv.inner:SetSize(PVW - 20, 100)
    pv.cap = K.Text(pv, 10, C.dim)
    pv.cap:SetPoint("BOTTOMLEFT", 12, 10) pv.cap:SetPoint("RIGHT", pv, "RIGHT", -10, 0)
    pv.cap:SetJustifyH("LEFT") pv.cap:SetWordWrap(true)
    pv.capText = L["Move the mouse over an entry - it is framed here"]
    pv.cap:SetText(pv.capText)
    pv.hi = CreateFrame("Frame", nil, pv.inner)
    pv.hi:SetFrameLevel(pv.inner:GetFrameLevel() + 10)
    pv.hi.l = {}
    for i = 1, 4 do pv.hi.l[i] = pv.hi:CreateTexture(nil, "OVERLAY") pv.hi.l[i]:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.95) end
    pv.hi.l[1]:SetPoint("TOPLEFT") pv.hi.l[1]:SetPoint("TOPRIGHT") pv.hi.l[1]:SetHeight(2)
    pv.hi.l[2]:SetPoint("BOTTOMLEFT") pv.hi.l[2]:SetPoint("BOTTOMRIGHT") pv.hi.l[2]:SetHeight(2)
    pv.hi.l[3]:SetPoint("TOPLEFT") pv.hi.l[3]:SetPoint("BOTTOMLEFT") pv.hi.l[3]:SetWidth(2)
    pv.hi.l[4]:SetPoint("TOPRIGHT") pv.hi.l[4]:SetPoint("BOTTOMRIGHT") pv.hi.l[4]:SetWidth(2)
    pv.hi:Hide()
    pv.rows, pv.heads, pv.byKey = {}, {}, {}
    return pv
end
local function updatePreview(f)
    local pv = f.pv
    if not pv then return end
    local D = ns.Discover
    for _, r in ipairs(pv.rows) do r:Hide() end
    for _, h in ipairs(pv.heads) do h:Hide() end
    wipe(pv.byKey)
    local y, nr, nh = 0, 0, 0
    for _, grp in ipairs(SB.Groups()) do
        if grp.g.key ~= "off" then
            local col = grp.g.color or C.dim
            local any = false
            for _, d in ipairs(grp.list) do if D.IsOn(d.key) then any = true break end end
            nh = nh + 1
            local h = pv.heads[nh]
            if not h then h = K.Text(pv.inner, 9, C.dim) pv.heads[nh] = h end
            h:ClearAllPoints() h:SetPoint("TOPLEFT", 2, y - 4)
            h:SetText(K.Upper(L[grp.g.text ~= "" and grp.g.text or "Start"]) .. (any and "" or ("  |cff777777" .. L["not loaded"] .. "|r")))
            h:SetTextColor(col[1], col[2], col[3], any and 1 or 0.45)
            h:Show()
            y = y - 18
            for _, d in ipairs(grp.list) do
                if D.IsOn(d.key) then
                    nr = nr + 1
                    local r = pv.rows[nr]
                    if not r then
                        r = CreateFrame("Frame", nil, pv.inner)
                        r:SetSize(PVW - 24, 16)
                        r.ic = r:CreateTexture(nil, "ARTWORK") r.ic:SetSize(12, 12) r.ic:SetPoint("LEFT", 4, 0)
                        r.t = K.Text(r, 10, C.text) r.t:SetPoint("LEFT", r.ic, "RIGHT", 6, 0) r.t:SetPoint("RIGHT", -2, 0)
                        r.t:SetJustifyH("LEFT") r.t:SetWordWrap(false)
                        pv.rows[nr] = r
                    end
                    local ic = ns.ICONS and ns.ICONS[d.key]
                    r.ic:SetTexture(ic) r.ic:SetShown(ic ~= nil)
                    r.ic:SetVertexColor(col[1], col[2], col[3])
                    r.t:SetText(L[d.title])
                    r.t:SetTextColor(col[1], col[2], col[3])
                    r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, y)
                    r:Show()
                    pv.byKey[d.key] = r
                    y = y - 17
                end
            end
            y = y - 4
        end
    end
    -- fit: the copy is scaled down until it fits the height of the visible area
    pv.inner:SetHeight(-y + 2)
    local avail = (f.GetHeight and f:GetHeight() or 0) - 44 - 4
    if avail < 200 then avail = 420 end
    local need = -y + 28 + 44
    local sc = math.max(0.55, math.min(1, (avail - 72) / math.max(1, -y)))
    pv.inner:SetScale(sc)
    pv:SetHeight(math.min(avail, (-y) * sc + 72))
    if pv.focusKey then SB.Focus(f, pv.focusKey) end
    return need
end
function SB.Focus(f, key, d)
    local pv = f and f.pv
    if not pv then return end
    pv.focusKey = key
    if not key then
        pv.hi:Hide()
        pv.cap:SetText(pv.capText) pv.cap:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        return
    end
    local r = pv.byKey[key]
    if r then
        pv.hi:ClearAllPoints()
        pv.hi:SetPoint("TOPLEFT", r, "TOPLEFT", -2, 2) pv.hi:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 2, -2)
        pv.hi:Show()
    else
        pv.hi:Hide()
    end
    if d then
        local txt = L[d.title] .. ": " .. (r and L["shown in the sidebar"] or L["hidden - switch it on to show it"])
        pv.cap:SetText(txt)
        local c = r and C.accent or C.dim
        pv.cap:SetTextColor(c[1], c[2], c[3])
    end
end

------------------------------------------------------------------------
-- tab
------------------------------------------------------------------------
local function build(f)
    f.note = K.Text(f, 11, C.muted)
    f.note:SetPoint("TOPLEFT", 0, -8)
    f.note:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.note:SetJustifyH("LEFT") f.note:SetWordWrap(true)
    f.note:SetText(L["Switch an entry off and it disappears from the sidebar. When all entries of an area are off, the area is not loaded any more (after a reload) - that saves memory. The cog opens the settings of the area."])
    f.pv = buildPreview(f)
    f.sf = CreateFrame("ScrollFrame", nil, f)
    f.sf:SetPoint("TOPLEFT", PVW + GAP, -44)
    f.sf:SetPoint("BOTTOMRIGHT", -10, 0)
    f.child = CreateFrame("Frame", nil, f.sf)
    f.child:SetSize(500, 10)
    f.sf:SetScrollChild(f.child)
    f.sf:EnableMouseWheel(true)
    f.sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, f.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
    end)
    f.tiles, f.heads = {}, {}
end
local function refresh(f)
    for _, t in ipairs(f.tiles) do t:Hide() end
    for _, h in ipairs(f.heads) do h:Hide() end
    wipe(f.tiles)
    local D = ns.Discover
    local W = (f.sf.GetWidth and f.sf:GetWidth()) or 0
    if W < 200 then W = 500 end
    f.child:SetWidth(W)
    local cw = math.floor((W - 10) / 2)
    local y, nh = 0, 0
    for _, grp in ipairs(SB.Groups()) do
        nh = nh + 1
        local h = f.heads[nh]
        if not h then
            h = CreateFrame("Frame", nil, f.child)
            h:SetHeight(22)
            h.t = K.Text(h, 11, C.dim) h.t:SetPoint("LEFT", 0, 0)
            h.tag = K.Text(h, 8, C.dim) h.tag:SetPoint("LEFT", h.t, "RIGHT", 6, 0)
            h.line = h:CreateTexture(nil, "ARTWORK")
            h.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6) h.line:SetHeight(1)
            h.line:SetPoint("LEFT", h.tag, "RIGHT", 8, 0) h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
            f.heads[nh] = h
        end
        local g = grp.g
        local col = g.color or C.dim
        h:SetWidth(W)
        h.t:SetText(K.Upper(L[g.text ~= "" and g.text or "Start"]))
        h.t:SetTextColor(col[1], col[2], col[3])
        h.tag:SetText(g.addon and K.Upper(L["Add-on"]) or "")
        h:ClearAllPoints() h:SetPoint("TOPLEFT", 0, y) h:Show()
        y = y - 28
        local rowH = 0
        for i, d in ipairs(grp.list) do
            local key = d.key
            local hasSet = not d.stub and ns.AreaHasSettings and ns.AreaHasSettings(key)
            local t = K.Tile(f.child, cw, {
                title = L[d.title], desc = subOf(d) or (d.stub and L["Switched off - switch on and reload to load it again"]) or nil,
                icon = (ns.ICONS and ns.ICONS[key]) or (ns.MEDIA .. "icons\\home"), glyph = true, tint = g.color,
                get = function() return D.IsOn(key) end,
                set = function(v)
                    D.Set(key, v)
                    if ns.LayoutNav then pcall(ns.LayoutNav) end
                    updatePreview(f)
                    SB.Focus(f, key, d)
                end,
                gear = hasSet and function() if ns.OpenAreaSettings then ns.OpenAreaSettings(key) end end or nil,
                onEnter = function() SB.Focus(f, key, d) end,
                onLeave = function() SB.Focus(f, nil) end,
            })
            t.pageKey = key
            f.tiles[#f.tiles + 1] = t
            local column = (i - 1) % 2
            t:ClearAllPoints() t:SetPoint("TOPLEFT", column * (cw + 10), y)
            rowH = math.max(rowH, t:GetHeight())
            if column == 1 or i == #grp.list then y = y - rowH - 8 rowH = 0 end
        end
        y = y - 10
    end
    f.child:SetHeight(-y + 20)
    updatePreview(f)
end
SB.Build, SB.Refresh, SB.UpdatePreview = build, refresh, updatePreview
if ns.AddSettingsTab then ns.AddSettingsTab("sidebar", "Sidebar", build, refresh) end

-- Oasis: settings tab "Sidebar" (0.6.614) - every entry of the sidebar with a switch, grouped like the sidebar.
-- Built fresh each time it opens from what is installed: an add-on that is missing has no entries here, a new one
-- shows up by itself. Switching off = hidden (and, once all pages of a module are off, the module is not loaded
-- any more - see ModuleLoader.PageToggled). Switched-off modules stay listed so they can be switched on again.
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

local ROW, COLW = 30, 330
local function build(f)
    f.sf = CreateFrame("ScrollFrame", nil, f)
    f.sf:SetPoint("TOPLEFT", 0, -10)
    f.sf:SetPoint("BOTTOMRIGHT", -10, 0)
    f.child = CreateFrame("Frame", nil, f.sf)
    f.child:SetSize(700, 10)
    f.sf:SetScrollChild(f.child)
    f.sf:EnableMouseWheel(true)
    f.sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, f.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
    end)
    f.note = K.Text(f.child, 11, C.muted)
    f.note:SetPoint("TOPLEFT", 0, 0)
    f.note:SetPoint("RIGHT", f.child, "RIGHT", -10, 0)
    f.note:SetJustifyH("LEFT") f.note:SetWordWrap(true)
    f.note:SetText(L["Every entry of the sidebar. Off = hidden; when all pages of an area are off, the area is not loaded any more (after a reload). Entries of add-ons that are not installed are not listed."])
    f.rows, f.heads = {}, {}
end
local function refresh(f)
    for _, r in ipairs(f.rows) do r:Hide() end
    for _, h in ipairs(f.heads) do h:Hide() end
    local D = ns.Discover
    local y, nr, nh = -40, 0, 0
    for _, grp in ipairs(SB.Groups()) do
        nh = nh + 1
        local h = f.heads[nh]
        if not h then
            h = CreateFrame("Frame", nil, f.child)
            h:SetSize(660, 22)
            h.t = K.Text(h, 11, C.dim) h.t:SetPoint("LEFT", 0, 0)
            h.tag = K.Text(h, 8, C.dim) h.tag:SetPoint("LEFT", h.t, "RIGHT", 6, 0)
            h.line = h:CreateTexture(nil, "ARTWORK")
            h.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6) h.line:SetHeight(1)
            h.line:SetPoint("LEFT", h.tag, "RIGHT", 8, 0) h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
            f.heads[nh] = h
        end
        local g = grp.g
        local col = g.color or C.dim
        h.t:SetText(K.Upper(L[g.text ~= "" and g.text or "Start"]))
        h.t:SetTextColor(col[1], col[2], col[3])
        h.tag:SetText(g.addon and K.Upper(L["Add-on"]) or "")
        h:ClearAllPoints() h:SetPoint("TOPLEFT", 0, y) h:Show()
        y = y - 28
        for i, d in ipairs(grp.list) do
            nr = nr + 1
            local r = f.rows[nr]
            if not r then
                r = CreateFrame("Frame", nil, f.child)
                r:SetSize(COLW - 10, ROW - 4)
                r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 0, 0)
                r.sw = K.Toggle(r, "", function() return r.d and D.IsOn(r.d.key) or false end, function(v)
                    if r.d then D.Set(r.d.key, v) end
                    if ns.LayoutNav then pcall(ns.LayoutNav) end
                end)
                r.sw:SetPoint("LEFT", 24, 0)
                r.sw:SetWidth(COLW - 40)
                f.rows[nr] = r
            end
            r.d = d
            local ic = ns.ICONS and ns.ICONS[d.key]
            r.icon:SetTexture(ic) r.icon:SetShown(ic ~= nil)
            r.icon:SetVertexColor(col[1], col[2], col[3])
            if r.sw.lbl then r.sw.lbl:SetText(L[d.title]) end
            if r.sw.Refresh then pcall(r.sw.Refresh, r.sw) end
            local column = (i - 1) % 2
            r:ClearAllPoints() r:SetPoint("TOPLEFT", column * COLW, y)
            r:Show()
            if column == 1 or i == #grp.list then y = y - ROW end
        end
        y = y - 8
    end
    f.child:SetHeight(-y + 20)
end
SB.Build, SB.Refresh = build, refresh
if ns.AddSettingsTab then ns.AddSettingsTab("sidebar", "Sidebar", build, refresh) end

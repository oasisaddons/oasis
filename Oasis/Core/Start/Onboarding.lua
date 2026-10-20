-- Oasis: onboarding for new users - short tour on first start + "Einfache Ansicht"
-- Simple = only the most important sections in the navigation; everything else stays reachable any time via
-- Settings > Sections (or "Alles zeigen"). Uses hiddenPages,
-- but remembers what it hid itself (settings.simpleHidden) so "Alles zeigen"
-- only shows those again and the user's own decisions stay.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local OB = {}
ns.Onboarding = OB

OB.CORE = { home = true, chat = true, radar = true, groups = true, social = true, raid = true, raidcheck = true, crafting = true, settings = true }

local function S() return ns.db.settings end
local function navPages()
    local out = {}
    for _, d in ipairs(ns.Pages()) do if d.nav ~= nil or d.title then out[#out + 1] = d.key end end
    return out
end
function OB.IsSimple() return S().simpleMode and true or false end
function OB.Simple()
    local s = S()
    s.hiddenPages = s.hiddenPages or {}
    s.simpleHidden = s.simpleHidden or {}
    for _, k in ipairs(navPages()) do
        local d = ns.PageDef(k)
        if not OB.CORE[k] and d and not d.topbar and not s.hiddenPages[k] then
            s.hiddenPages[k] = true
            s.simpleHidden[k] = true
        end
    end
    s.simpleMode = true
    if ns.LayoutNav then ns.LayoutNav() end
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
end
function OB.ShowAll()
    local s = S()
    for k in pairs(s.simpleHidden or {}) do if s.hiddenPages then s.hiddenPages[k] = nil end end
    s.simpleHidden, s.simpleMode = nil, nil
    if ns.LayoutNav then ns.LayoutNav() end
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
end

------------------------------------------------------------------------
-- Tour with spotlight: dim everything, highlight one element, briefly explain next to it
------------------------------------------------------------------------
local function mainF() return ns.MainFrame and ns.MainFrame() end
local function navOf(key)
    local d = ns.PageDef and ns.PageDef(key)
    return d and d.nav and d.nav:IsVisible() and d.nav or nil
end
local STEPS = {
    { title = "Welcome to Oasis", text = "Your guild's hub. In 30 seconds you will know your way around - here is what matters.",
      target = function() return mainF() end },
    { title = "The navigation", text = "All areas, grouped by topic: guild, playing together, raid, trade, fun. Click a heading to collapse its group.",
      target = function() local m = mainF() return m and m.side end },
    { title = "Quest together", text = "Shows at a glance who in the guild has the same quests and is online right now - one click invites them.",
      target = function() return navOf("social") or navOf("groups") or (mainF() and mainF().side) end, page = "social" },
    { title = "This is where it happens", text = "The content of the selected area. The overview shows who is online, what is coming up and what is new.",
      target = function() local m = mainF() return m and m.content end, page = "home" },
    { title = "Settings and language", text = "Gear = settings (look, sounds, notifications). Next to it the language and - for guild leadership - the crown.",
      target = function() local m = mainF() return m and m.gear end, pad = 40 },
    { title = "Always at hand", text = "The minimap button or /oa opens Oasis. The dash at the top right turns the window into a slim bar.",
      target = function() return _G.OasisMinimapButton end, pad = 6 },
    { title = "Have fun with Oasis!", text = "That's it. You can find the tour again any time under Settings > Status or with /oa rundgang.",
      choice = true },
}
OB.STEPS = STEPS

local ov
local function shade(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0, 0, 0, 0.72)
    return t
end
local function build()
    ov = CreateFrame("Frame", "OasisTour", UIParent)
    ov:SetAllPoints(UIParent)
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:EnableMouse(true)          -- nothing underneath is clickable while the tour is running
    -- Esc ends the tour - via ns.EscClose, NO key catcher with SetPropagateKeyboardInput
    -- (it passes every key through addon code and then blocks SpellStopCasting/-Targeting)
    ov:SetScript("OnHide", function() if not (S().onboarded) then S().onboarded = ns.now() end end)
    if ns.EscClose then ns.EscClose(ov) end
    ov.top, ov.bottom, ov.left, ov.right = shade(ov), shade(ov), shade(ov), shade(ov)
    -- Frame around the highlighted element
    ov.ring = CreateFrame("Frame", nil, ov)
    K.Border(ov.ring, C.accent, 2)
    ov.glow = ov.ring:CreateTexture(nil, "BACKGROUND")
    ov.glow:SetPoint("TOPLEFT", -6, 6) ov.glow:SetPoint("BOTTOMRIGHT", 6, -6)
    ov.glow:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
    ov.ring:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        ov.glow:SetAlpha(0.5 + 0.5 * math.sin(self.t * 3))
    end)
    -- Explanation bubble
    local b = CreateFrame("Frame", nil, ov)
    b:SetSize(320, 150)
    K.Fill(b, { 0.05, 0.05, 0.06, 0.98 })
    K.Border(b, C.line)
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 1, -1) bar:SetPoint("TOPRIGHT", -1, -1) bar:SetHeight(2)
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    b.step = K.Text(b, 10, C.dim, "RIGHT")
    b.step:SetPoint("TOPRIGHT", -12, -12)
    b.title = K.Title(b, 15, C.text)
    b.title:SetPoint("TOPLEFT", 14, -12)
    b.title:SetPoint("RIGHT", b.step, "LEFT", -8, 0)
    b.text = K.Text(b, 12, C.muted)
    b.text:SetPoint("TOPLEFT", 14, -38)
    b.text:SetWidth(292)
    b.text:SetWordWrap(true)
    b.text:SetJustifyV("TOP")
    b.skip = K.Button(b, L["Skip"], 100, 24, "ghost", function() OB.Finish(nil) end)
    b.skip:SetPoint("BOTTOMLEFT", 12, 12)
    b.back = K.Button(b, L["Back"], 74, 24, "ghost", function() OB.Step(ov.i - 1) end)
    b.back:SetPoint("BOTTOMRIGHT", -94, 12)
    b.next = K.Button(b, L["Resume"], 76, 24, "primary", function() OB.Step(ov.i + 1) end)
    b.next:SetPoint("BOTTOMRIGHT", -12, 12)
    b.simple = K.Button(b, L["Let's go"], 140, 28, "primary", function() OB.Finish("all") end)
    b.simple:SetPoint("BOTTOMRIGHT", -12, 12)
    b.all = b.simple
    b.dots = {}
    for i = 1, #STEPS do
        local d = b:CreateTexture(nil, "ARTWORK")
        d:SetSize(6, 6)
        d:SetTexture(ns.MEDIA .. "dot")
        d:SetPoint("BOTTOM", b, "BOTTOM", (i - (#STEPS + 1) / 2) * 11, 44)
        b.dots[i] = d
    end
    ov.bubble = b
end

-- Put the hole where the target is (coordinates in UIParent units)
local function place(target, pad)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local l, r, t, bt
    if target and target:IsVisible() and target:GetLeft() then
        local s = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
        pad = pad or 8
        l, r = target:GetLeft() * s - pad, target:GetRight() * s + pad
        bt, t = target:GetBottom() * s - pad, target:GetTop() * s + pad
        l, r, bt, t = math.max(0, l), math.min(W, r), math.max(0, bt), math.min(H, t)
    end
    local function rect(tex, x1, y1, x2, y2)
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x1, y1)
        tex:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", math.max(x1 + 0.1, x2), math.max(y1 + 0.1, y2))
    end
    local b = ov.bubble
    b:ClearAllPoints()
    if not l then
        -- no target: everything dark, bubble in the middle
        rect(ov.top, 0, 0, W, H)
        ov.bottom:Hide() ov.left:Hide() ov.right:Hide() ov.ring:Hide()
        b:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        return
    end
    ov.bottom:Show() ov.left:Show() ov.right:Show() ov.ring:Show()
    rect(ov.top, 0, t, W, H)
    rect(ov.bottom, 0, 0, W, bt)
    rect(ov.left, 0, bt, l, t)
    rect(ov.right, r, bt, W, t)
    ov.ring:ClearAllPoints()
    ov.ring:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, bt)
    ov.ring:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r, t)
    -- Bubble where there is room: right, left, below, above - otherwise into the target
    local bw, bh = b:GetWidth(), b:GetHeight()
    local cy = math.max(bh / 2 + 10, math.min(H - bh / 2 - 10, (t + bt) / 2))
    if W - r > bw + 24 then b:SetPoint("LEFT", UIParent, "BOTTOMLEFT", r + 16, cy)
    elseif l > bw + 24 then b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", l - 16, cy)
    elseif bt > bh + 24 then b:SetPoint("TOP", UIParent, "BOTTOMLEFT", (l + r) / 2, bt - 16)
    elseif H - t > bh + 24 then b:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", (l + r) / 2, t + 16)
    else b:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r - 20, bt + 20) end
end

function OB.Step(i)
    if not ov then build() end
    i = math.max(1, math.min(#STEPS, i))
    ov.i = i
    local s = STEPS[i]
    if not (ns.MainShown and ns.MainShown()) and ns.OpenMain then ns.OpenMain() end
    if s.page and ns.ShowPage then pcall(ns.ShowPage, s.page) end
    local b = ov.bubble
    b.title:SetText(L[s.title])
    b.text:SetText(L[s.text])
    b.step:SetText(i .. " / " .. #STEPS)
    for k, d in ipairs(b.dots) do
        local c = k == i and C.accent or C.line
        d:SetVertexColor(c[1], c[2], c[3])
    end
    b.back:SetShown(i > 1 and not s.choice)
    b.next:SetShown(not s.choice)
    b.skip:SetShown(not s.choice)
    b.simple:SetShown(s.choice and true or false)
    b.all:SetShown(s.choice and true or false)
    b:SetHeight(math.max(130, (b.text:GetStringHeight() or 0) + 100))
    ov:Show()
    -- Window/navigation need a moment until sizes are correct
    place(nil)
    C_Timer.After(0.15, function()
        if ov.i ~= i or not ov:IsShown() then return end
        local ok, tgt = pcall(s.target or function() end)
        place(ok and tgt or nil, s.pad)
    end)
end
function OB.Show() OB.Step(1) end
function OB.Finish(choice)
    S().onboarded = ns.now()
    if choice == "simple" then OB.Simple() elseif choice == "all" then OB.ShowAll() end
    if ov then ov:Hide() end
    if choice and ns.ShowPage then pcall(ns.ShowPage, "home") end
end
ns.slash.rundgang = function() OB.Show() end

-- first start: wait briefly after login, then show once
ns.Listen("LOGIN", function()
    -- the simple view no longer exists: whoever had chosen it sees everything again
    if S().simpleMode then OB.ShowAll() end
    -- The tour no longer comes automatically - the first window is the interest picker (Discover.lua);
    -- the tour remains reachable via /oa rundgang
    S().onboarded = S().onboarded or ns.now()
end)
-- Combat starts: tour gone immediately (comes back at the next login as long as not finished)
ns.On("PLAYER_REGEN_DISABLED", function() if ov and ov:IsShown() then ov:Hide() end end)

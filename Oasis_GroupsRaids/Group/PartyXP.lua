-- Oasis: Gruppen-XP (0.6.521) - kleine, verschiebbare Leiste mit einem Erfahrungsbalken je Gruppenmitglied
-- (nur 5er-Gruppe, Daten aus "GPI" von Mitgliedern mit Oasis). Schalter: Einstellungen > Meine Gruppe.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Group", function()
local L = ns.L
local K, C = ns.K, ns.K.C
local P = ns.Party
local function S() return ns.db.settings end
local function on() return S().partyXP ~= false end

local f
local rows = {}
local W, RH = 190, 18
local function build()
    f = CreateFrame("Frame", "OasisPartyXP", UIParent)
    f:SetSize(W, 20)
    f:SetFrameStrata("LOW")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        if x and y then S().partyXPPos = { x = math.floor(x), y = math.floor(y) } end
    end)
    local pos = S().partyXPPos
    if pos then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y) else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220) end
    P.glass(f, { 0.03, 0.03, 0.04, 0.82 }, { 1, 1, 1, 0.08 }, 8)
    f.title = K.Text(f, 10, C.dim)
    f.title:SetPoint("TOPLEFT", 8, -5)
    f.title:SetText(K.Upper(L["Group XP"]))
    f:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Group XP"], L["Drag to move"], L["Off: Settings > My group"] }) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 16, RH)
    r.name = K.Text(r, 11, C.text)
    r.name:SetPoint("LEFT", 0, 0)
    r.name:SetWidth(70)
    r.name:SetWordWrap(false)
    r.bar = K.Bar(r, W - 16 - 74 - 30, 6)
    r.bar:SetPoint("LEFT", 74, 0)
    r.pct = K.Text(r, 10, C.dim, "RIGHT")
    r.pct:SetPoint("RIGHT", 0, 0)
    rows[i] = r
    return r
end
local function update()
    if not on() or not IsInGroup() or IsInRaid() or not ns.loggedIn then if f then f:Hide() end return end
    if not f then build() end
    local list = {}
    local maxL = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    for _, m in ipairs(P.Members()) do
        local inf = m.info
        if inf and inf.xp and inf.xpMax and (m.lvl or 0) < maxL then list[#list + 1] = m end
    end
    for _, r in ipairs(rows) do r:Hide() end
    if #list == 0 then f:Hide() return end
    for i, m in ipairs(list) do
        local r = row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 8, -18 - (i - 1) * RH)
        local cr, cg, cb = ns.classColor(m.class)
        r.name:SetText(m.short .. " |cff888888" .. (m.lvl or "") .. "|r")
        r.name:SetTextColor(cr or 1, cg or 1, cb or 1)
        local p = m.info.xp / math.max(1, m.info.xpMax)
        r.bar:Set(p)
        r.pct:SetText(math.floor(p * 100) .. "%")
        r:Show()
    end
    f:SetHeight(24 + #list * RH)
    f:Show()
end
P.UpdateXP = update
ns.Listen("PARTY_INFO", function() ns.Debounce("partyXP", 0.3, update) end)
ns.On("GROUP_ROSTER_UPDATE", function() ns.Debounce("partyXP", 0.5, update) end)
ns.Listen("LOGIN", function() C_Timer.After(6, update) end)

end)

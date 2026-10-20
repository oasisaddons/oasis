-- Oasis: Bedrohung und Pull-Warnung (0.6.521)
--  * kleine Leiste: deine Bedrohung auf dem Ziel in % (nur solange das Spiel den Wert liefert - Forever macht
--    Kampfwerte teils "secret", dann bleibt die Leiste einfach weg; nie mit geheimen Werten rechnen)
--  * Pull-Warnung: du (kein Tank) kommst in den Kampf, waehrend der Tank deiner Gruppe noch nicht kaempft
--  * Warnung, wenn du als Nicht-Tank die Aggro hast (nur wenn lesbar)
-- Schalter: Einstellungen > Meine Gruppe
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Group", function()
local L = ns.L
local K, C = ns.K, ns.K.C
local P = ns.Party
local function S() return ns.db.settings end
local issecret = issecretvalue or function() return false end
local function clean(v) if v == nil or issecret(v) then return nil end return v end

local function myRole()
    local r = ns.safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player"))
    if r and r ~= "NONE" then return r end
    local inf = P.MyInfo and P.MyInfo()
    return inf and inf.role or "DAMAGER"
end
local function tankUnits()
    local out = {}
    for _, m in ipairs(P.Members()) do if m.role == "TANK" and not m.me and m.unit then out[#out + 1] = m.unit end end
    return out
end

-- Pull-Warnung
ns.On("PLAYER_REGEN_DISABLED", function()
    if S().pullWarn == false or not IsInGroup() or myRole() == "TANK" then return end
    local tanks = tankUnits()
    if #tanks == 0 then return end
    C_Timer.After(0.3, function()
        for _, u in ipairs(tanks) do
            local c = clean(UnitAffectingCombat(u))
            if c == nil or c == true then return end
        end
        K.Toast(L["Pulled before the tank"], L["You are in combat, the tank is not - back to the tank!"], C.amber or C.accent)
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    end)
end)

-- Bedrohungsleiste
local f, warned
local function build()
    f = CreateFrame("Frame", "OasisThreatBar", UIParent)
    f:SetSize(160, 26)
    local pos = S().threatPos
    if pos then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -170) end
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() local x, y = self:GetLeft(), self:GetTop() if x and y then S().threatPos = { x = math.floor(x), y = math.floor(y) } end end)
    P.glass(f, { 0.03, 0.03, 0.04, 0.8 }, { 1, 1, 1, 0.08 }, 6)
    f.t = K.Text(f, 10, C.dim)
    f.t:SetPoint("TOPLEFT", 6, -3)
    f.t:SetText(K.Upper(L["Threat"]))
    f.v = K.Text(f, 11, C.text, "RIGHT")
    f.v:SetPoint("TOPRIGHT", -6, -3)
    f.bar = K.Bar(f, 148, 5)
    f.bar:SetPoint("BOTTOMLEFT", 6, 5)
    f:Hide()
end
local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.25 then return end
    acc = 0
    if S().threatBar ~= true or not IsInGroup() or not UnitExists("target") or not UnitCanAttack("player", "target") then
        if f then f:Hide() end
        return
    end
    if not UnitDetailedThreatSituation then return end
    local ok, tanking, status, pct = pcall(UnitDetailedThreatSituation, "player", "target")
    pct, tanking = ok and clean(pct), ok and clean(tanking)
    if type(pct) ~= "number" then if f then f:Hide() end return end
    if not f then build() end
    f.bar:Set(pct / 100)
    f.v:SetText(math.floor(pct + 0.5) .. "%")
    local hot = pct >= 90 and myRole() ~= "TANK"
    f.v:SetTextColor((hot and C.amber or C.text)[1], (hot and C.amber or C.text)[2], (hot and C.amber or C.text)[3])
    f:Show()
    if tanking == true and myRole() ~= "TANK" and S().pullWarn ~= false then
        if not warned or GetTime() - warned > 8 then
            warned = GetTime()
            K.Toast(L["You have aggro"], L["Ease off until the tank has it back."], C.amber or C.accent)
        end
    end
end)

end)

-- Oasis: Bank-Platzhalter - feste Plaetze in der eigenen Bank
-- "Belegung merken" speichert, welches Item auf welchem Bankplatz liegt (ns.char.bankPlan).
-- Ist so ein Platz spaeter leer, zeigt Oasis dort ein blasses Symbol des Items, damit die Ordnung bleibt.
-- NUR Anzeige: Oasis verschiebt keine Items (Verschieben/Benutzen aus Addon-Code sperrt der Client).
-- Die Overlays sind eigene Frames an UIParent, nur an Blizzards Knoepfen ausgerichtet (nichts an deren Frames setzen).
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local BS = {}
ns.BankSlots = BS

local function S() return ns.db.settings end
local function plan()
    ns.char.bankPlan = ns.char.bankPlan or {}
    return ns.char.bankPlan
end

-- Bank-Behaelter: klassisch (-1 + Taschen 5..11) und Retail-Reiter (Enum.BagIndex.CharacterBankTab_*)
local function bankBags()
    local out, seen = {}, {}
    local function add(b) if b and not seen[b] then seen[b] = true out[#out + 1] = b end end
    add(BANK_CONTAINER or -1)
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
    if Enum and Enum.BagIndex then
        for i = 1, 8 do add(Enum.BagIndex["CharacterBankTab_" .. i]) end
    end
    local list = {}
    for _, b in ipairs(out) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, b)
        if ok and (ns.safe(n) or 0) > 0 then list[#list + 1] = b end
    end
    return list
end

function BS.Remember()
    if not (C_Container and C_Container.GetContainerItemInfo) then return 0 end
    local p, n = {}, 0
    for _, b in ipairs(bankBags()) do
        for s = 1, (C_Container.GetContainerNumSlots(b) or 0) do
            local info = C_Container.GetContainerItemInfo(b, s)
            local id = info and ns.safe(info.itemID)
            if id then p[b .. ":" .. s] = id n = n + 1 end
        end
    end
    ns.char.bankPlan = p
    BS.Refresh()
    return n
end
function BS.Clear()
    ns.char.bankPlan = {}
    BS.Refresh()
end
function BS.Count()
    local n = 0
    for _ in pairs(plan()) do n = n + 1 end
    return n
end

------------------------------------------------------------------------
-- Blizzards Bank-Knoepfe finden (ohne sie zu veraendern)
------------------------------------------------------------------------
local function slotOf(btn)
    if btn.GetBankTabID and btn.GetContainerSlotID then
        local ok1, tab = pcall(btn.GetBankTabID, btn)
        local ok2, slot = pcall(btn.GetContainerSlotID, btn)
        if ok1 and ok2 and tab and slot then return tab, slot end
    end
    if btn.GetBagID and btn.GetID then
        local ok, bag = pcall(btn.GetBagID, btn)
        if ok and bag then return bag, btn:GetID() end
    end
    -- klassische Bank: BankFrameItemN, Behaelter-ID am Elternrahmen
    local name = btn.GetName and btn:GetName()
    if name and name:find("^BankFrameItem%d+$") then return BANK_CONTAINER or -1, btn:GetID() end
    return nil
end
local function collect(frame, out, depth)
    if not frame or depth > 6 then return end
    if frame.IsVisible and frame:IsVisible() and frame.GetObjectType and frame:GetObjectType() == "Button" then
        local b, s = slotOf(frame)
        if b and s and s > 0 then out[b .. ":" .. s] = frame end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do collect(c, out, depth + 1) end
    end
end
local function bankButtons()
    local out = {}
    collect(_G.BankFrame, out, 0)
    collect(_G.BankPanel, out, 0)
    for i = 1, 13 do collect(_G["ContainerFrame" .. i], out, 0) end
    collect(_G.ContainerFrameCombinedBags, out, 0)
    return out
end

------------------------------------------------------------------------
-- Overlays
------------------------------------------------------------------------
local pool, used = {}, {}
local function ghost()
    local g = table.remove(pool)
    if g then return g end
    g = CreateFrame("Frame", nil, UIParent)
    g:EnableMouse(false)
    g.icon = g:CreateTexture(nil, "OVERLAY")
    g.icon:SetPoint("TOPLEFT", 3, -3)
    g.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    g.icon:SetDesaturated(true)
    g.icon:SetAlpha(0.35)
    return g
end
local function releaseAll()
    for _, g in ipairs(used) do g:Hide() g:ClearAllPoints() pool[#pool + 1] = g end
    used = {}
end
local bankOpen = false
function BS.Refresh()
    releaseAll()
    if not bankOpen or S().bankGhosts == false or ns.inCombat() then return end
    local p = plan()
    if not next(p) then return end
    local btns = bankButtons()
    for key, id in pairs(p) do
        local btn = btns[key]
        if btn then
            local b, s = key:match("^(%-?%d+):(%d+)$")
            local info = C_Container.GetContainerItemInfo(tonumber(b), tonumber(s))
            if not info then
                local g = ghost()
                g:SetFrameStrata(btn:GetFrameStrata() or "HIGH")
                g:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
                g:SetPoint("TOPLEFT", btn, "TOPLEFT")
                g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")
                g.icon:SetTexture((C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
                g:Show()
                used[#used + 1] = g
            end
        end
    end
end

-- kleine Oasis-Leiste ueber der Bank: merken / vergessen / an-aus
local bar
local function buildBar()
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(330, 28)
    bar:SetFrameStrata("HIGH")
    K.Fill(bar, { 0.05, 0.05, 0.06, 0.92 })
    K.Border(bar, C.line)
    bar.t = K.Text(bar, 11, C.muted)
    bar.t:SetPoint("LEFT", 8, 0)
    bar.save = K.Button(bar, L["Belegung merken"], 110, 20, "ghost", function()
        local n = BS.Remember()
        K.Toast(L["Bank-Platzhalter"], (L["%d Plaetze gemerkt - leere Plaetze zeigen jetzt ein blasses Symbol."]):format(n), C.mint)
        BS.UpdateBar()
    end)
    bar.save:SetPoint("RIGHT", -64, 0)
    bar.clr = K.Button(bar, L["Leeren"], 54, 20, "ghost", function() BS.Clear() BS.UpdateBar() end)
    bar.clr:SetPoint("RIGHT", -6, 0)
    bar:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["Bank-Platzhalter (Oasis)"], L["Merkt, welches Item auf welchem Platz liegt. Leere Plaetze zeigen dann ein blasses Symbol - Oasis verschiebt nichts."] })
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
function BS.UpdateBar()
    if not bar then return end
    local n = BS.Count()
    bar.t:SetText(n > 0 and (L["Platzhalter: %d"]):format(n) or L["Platzhalter: keine"])
    bar.clr:SetShown(n > 0)
end
local function showBar()
    if S().bankGhosts == false then if bar then bar:Hide() end return end
    local host = (_G.BankFrame and _G.BankFrame:IsVisible() and _G.BankFrame) or (_G.BankPanel and _G.BankPanel:IsVisible() and _G.BankPanel)
    if not host then return end
    if not bar then buildBar() end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    BS.UpdateBar()
    bar:Show()
end

ns.On("BANKFRAME_OPENED", function()
    bankOpen = true
    ns.After(0.3, function() pcall(showBar) pcall(BS.Refresh) end)
end)
ns.On("BANKFRAME_CLOSED", function()
    bankOpen = false
    releaseAll()
    if bar then bar:Hide() end
end)
local pending
local function soon()
    if not bankOpen or pending then return end
    pending = true
    ns.After(0.3, function() pending = nil pcall(BS.Refresh) end)
end
ns.On("PLAYERBANKSLOTS_CHANGED", soon)
ns.On("BAG_UPDATE_DELAYED", soon)
ns.slash.bankplatz = function() if bankOpen then local n = BS.Remember() ns.print((L["%d Plaetze gemerkt"]):format(n)) else ns.print(L["Erst die Bank oeffnen."]) end end

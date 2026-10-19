-- Oasis: Segen-Plan (0.6.521) - welcher Paladin segnet welche Klasse mit welchem Segen
--  * Reiter "Segen" auf der Seite Meine Gruppe: Zeile je Paladin, Spalte je Klasse in der Gruppe, Klick wechselt den Segen
--  * "Vorschlag" verteilt automatisch (Koenige > Macht/Weisheit > Rettung > Licht > Refugium)
--  * Plan wird im Gruppenkanal geteilt ("GPB"); aendern duerfen Gruppenleitung und die Paladine selbst
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gruppe", function()
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
local P = ns.Party
local B = {}
ns.Blessings = B

-- Segen (Classic-Zauber-IDs Rang 1; Name und Symbol kommen vom Spiel)
B.LIST = {
    { key = "k", spell = 20217, short = "Koenige" },
    { key = "m", spell = 19740, short = "Macht" },
    { key = "w", spell = 19742, short = "Weisheit" },
    { key = "s", spell = 1038, short = "Rettung" },
    { key = "l", spell = 19977, short = "Licht" },
    { key = "r", spell = 20911, short = "Refugium" },
}
local BY = {}
for _, b in ipairs(B.LIST) do BY[b.key] = b end
local CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }
-- was jede Klasse am liebsten bekommt (Reihenfolge)
local WANT = {
    WARRIOR = { "k", "m", "l", "r" }, ROGUE = { "k", "m", "s", "l" }, HUNTER = { "k", "m", "s", "w" },
    MAGE = { "k", "w", "s", "l" }, WARLOCK = { "k", "w", "s", "l" }, PRIEST = { "k", "w", "s", "l" },
    DRUID = { "k", "w", "s", "m" }, SHAMAN = { "k", "w", "s", "m" }, PALADIN = { "k", "w", "s", "m" },
}
B.plan = {}     -- [Paladin] = { [Klasse] = Schluessel }

local function spellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return ns.safe(n)
end
local function spellIcon(id)
    local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return ns.safe(t) or 134400
end
function B.Name(key) local b = BY[key] return b and (spellName(b.spell) or L[b.short]) or "-" end

function B.Paladins()
    local out = {}
    for _, m in ipairs(P.Members()) do if m.class == "PALADIN" then out[#out + 1] = m end end
    return out
end
function B.Classes()
    local have, out = {}, {}
    for _, m in ipairs(P.Members()) do if m.class then have[m.class] = true end end
    for _, c in ipairs(CLASSES) do if have[c] then out[#out + 1] = c end end
    return out
end
local function canEdit()
    if ns.isGroupLead() then return true end
    local _, cls = UnitClass("player")
    return cls == "PALADIN"
end
B.CanEdit = canEdit

-- Vorschlag: jeder Paladin uebernimmt einen Segen fuer alle Klassen, in der Reihenfolge der Wuensche
function B.Suggest()
    local pals = B.Paladins()
    B.plan = {}
    for _, cls in ipairs(B.Classes()) do
        local used = {}
        for i, pm in ipairs(pals) do
            local pick
            for _, k in ipairs(WANT[cls] or { "k" }) do if not used[k] then pick = k break end end
            if pick then
                used[pick] = true
                B.plan[pm.name] = B.plan[pm.name] or {}
                B.plan[pm.name][cls] = pick
            end
        end
    end
    B.Share()
end
function B.Encode()
    local parts = {}
    for name, row in pairs(B.plan) do
        local cs = {}
        for cls, k in pairs(row) do cs[#cs + 1] = cls .. ":" .. k end
        parts[#parts + 1] = name .. "=" .. table.concat(cs, ",")
    end
    return table.concat(parts, ";")
end
function B.Share()
    if ns.groupChannel() then Comm.Group("GPB", B.Encode()) end
    ns.RefreshPage("party")
end
local function mine()
    local me = P.UnitName("player")
    for n, row in pairs(B.plan) do if ns.SameName(n, me) then return row end end
end
B.Mine = mine
local function announceMine()
    local row = mine()
    if not row then return end
    local by = {}
    for cls, k in pairs(row) do by[k] = by[k] or {} table.insert(by[k], (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls) end
    local lines = {}
    for k, list in pairs(by) do lines[#lines + 1] = B.Name(k) .. ": " .. table.concat(list, ", ") end
    if #lines > 0 then K.Toast(L["Dein Segen-Plan"], table.concat(lines, "\n"), C.accent) end
end
Comm.On("GPB", function(sender, _, s)
    if type(s) ~= "string" or #s > 1500 or not P.InMyGroup(sender) then return end
    -- nur Gruppenleitung oder Paladine duerfen den Plan setzen
    local ok = false
    for _, m in ipairs(P.Members()) do
        if ns.SameName(m.name, sender) and (m.class == "PALADIN" or (m.unit and UnitIsGroupLeader(m.unit)) or (m.unit and UnitIsGroupAssistant and UnitIsGroupAssistant(m.unit))) then ok = true end
    end
    if not ok then return end
    local before = B.Encode()
    local plan = {}
    for name, rest in s:gmatch("([^=;]+)=([^;]*)") do
        if #name <= 64 and not name:find("[|%c]") then
            local row = {}
            for cls, k in rest:gmatch("(%u+):(%l)") do if BY[k] then row[cls] = k end end
            plan[name] = row
        end
    end
    B.plan = plan
    if B.Encode() ~= before then announceMine() end
    ns.RefreshPage("party")
end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then B.plan = {} return end
    for n in pairs(B.plan) do if not P.InMyGroup(n) then B.plan[n] = nil end end
end)

------------------------------------------------------------------------
-- Reiter "Segen"
------------------------------------------------------------------------
local cells = {}
P.AddTab({
    key = "bless", text = "Segen",
    build = function(p, a)
        a.info = K.Text(a, 11, C.muted)
        a.info:SetPoint("TOPLEFT", 4, 0)
        a.info:SetPoint("RIGHT", -240, 0)
        a.info:SetJustifyH("LEFT")
        a.info:SetText(L["Klick auf ein Feld wechselt den Segen. Aendern duerfen die Gruppenleitung und die Paladine; alle mit Oasis sehen den Plan."])
        a.sug = K.Button(a, L["Vorschlag"], 100, 22, "ghost", function() if canEdit() then B.Suggest() end end)
        a.sug:SetPoint("TOPRIGHT", -114, 2)
        a.send = K.Button(a, L["In den Chat"], 104, 22, "ghost", function()
            local parts = {}
            for name, row in pairs(B.plan) do
                local by = {}
                for cls, k in pairs(row) do by[k] = by[k] or {} table.insert(by[k], (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls) end
                local seg = {}
                for k, l in pairs(by) do seg[#seg + 1] = B.Name(k) .. " > " .. table.concat(l, "/") end
                parts[#parts + 1] = name:gsub("%-.*$", "") .. ": " .. table.concat(seg, ", ")
            end
            if #parts > 0 and ns.groupChannel() then ns.OfferChat(L["Segen-Plan"], table.concat(parts, " | "), ns.groupChannel()) end
        end)
        a.send:SetPoint("TOPRIGHT", -4, 2)
        a.grid = CreateFrame("Frame", nil, a)
        a.grid:SetPoint("TOPLEFT", 0, -40)
        a.grid:SetPoint("BOTTOMRIGHT", 0, 0)
        a.empty = K.Text(a, 13, C.dim, "CENTER")
        a.empty:SetPoint("TOP", 0, -100)
    end,
    refresh = function(p, a)
        for _, c in ipairs(cells) do c:Hide() end
        local pals, classes = B.Paladins(), B.Classes()
        a.empty:SetShown(#pals == 0)
        a.empty:SetText(L["Kein Paladin in der Gruppe."])
        a.sug:SetShown(#pals > 0 and canEdit())
        a.send:SetShown(#pals > 0)
        if #pals == 0 then return end
        local n, CW, RH = 0, 64, 44
        local function cell()
            n = n + 1
            local c = cells[n]
            if not c then
                c = CreateFrame("Button", nil, a.grid)
                c.t = K.Text(c, 11, C.text, "CENTER")
                c.t:SetPoint("CENTER")
                c.ic = c:CreateTexture(nil, "ARTWORK")
                c.ic:SetSize(26, 26)
                c.ic:SetPoint("CENTER")
                cells[n] = c
            end
            c:SetScript("OnClick", nil) c:SetScript("OnEnter", nil)
            c.ic:Hide() c.t:SetText("")
            c:Show()
            return c
        end
        -- Kopf: Klassen
        for j, cls in ipairs(classes) do
            local c = cell()
            c:SetSize(CW, 24)
            c:SetPoint("TOPLEFT", 150 + (j - 1) * CW, 0)
            local cr, cg, cb = ns.classColor(cls)
            c.t:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls)
            c.t:SetTextColor(cr or 1, cg or 1, cb or 1)
        end
        for i, pm in ipairs(pals) do
            local y = -28 - (i - 1) * RH
            local nm = cell()
            nm:SetSize(140, RH)
            nm:SetPoint("TOPLEFT", 0, y)
            nm.t:SetText(pm.short)
            local cr, cg, cb = ns.classColor("PALADIN")
            nm.t:SetTextColor(cr or 1, cg or 1, cb or 1)
            for j, cls in ipairs(classes) do
                local c = cell()
                c:SetSize(CW - 6, RH - 6)
                c:SetPoint("TOPLEFT", 150 + (j - 1) * CW + 3, y - 3)
                if not c.bg then c.bg = true P.glass(c, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.07 }, 6) end
                local key = B.plan[pm.name] and B.plan[pm.name][cls]
                local b = key and BY[key]
                if b then c.ic:SetTexture(spellIcon(b.spell)) c.ic:Show() else c.t:SetText("|cff555555-|r") end
                c:SetScript("OnEnter", function(self) K.ShowTip(self, { pm.short .. " > " .. ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls), b and B.Name(b.key) or L["kein Segen"], canEdit() and L["Klick: naechster Segen, Rechtsklick: keiner"] or nil }) end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
                c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                c:SetScript("OnClick", function(_, btn)
                    if not canEdit() then return end
                    B.plan[pm.name] = B.plan[pm.name] or {}
                    if btn == "RightButton" then B.plan[pm.name][cls] = nil
                    else
                        local idx = 0
                        for x, bb in ipairs(B.LIST) do if bb.key == key then idx = x end end
                        B.plan[pm.name][cls] = B.LIST[idx % #B.LIST + 1].key
                    end
                    B.Share()
                end)
            end
        end
    end,
})

end)

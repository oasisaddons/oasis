-- Oasis: Raid-Kader (0.6.527) - feste Raid-Teams mit Stamm und Ersatz
--  * Team = Name + Raidtag (Store "kader", aendern: Raidleitung - Recht raid.plan.sort)
--  * je Person: Anwesenheit der letzten 28 Tage (Gildenpflege) und ob sie sich abgemeldet hat
--  * "Ersatz an der Reihe": wer aus dem Ersatz zuletzt am wenigsten dabei war - faire Rotation
--  * jeder kann sich abmelden ("Ich fehle am ..." -> Store "absent"); die Raidleitung bekommt einen Hinweis
-- Ergaenzt Gargul/RCLootCouncil (Beute) und MRT (Notizen) - die kennen keinen festen Kader.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local KD = {}
ns.Kader = KD
local DAY = 86400

local function canEdit() return ns.Admin and ns.Admin.CanRaidPlan and ns.Admin.CanRaidPlan() or false end
local function split(s) local t = {} for n in tostring(s or ""):gmatch("[^,]+") do t[#t + 1] = n end return t end
local function short(n) return ns.displayName and ns.displayName(n) or ns.short(n) end
local function att(n)
    if not (ns.Officer and ns.Officer.Attendance) then return nil end
    local q = ns.Officer.Attendance(n, 28)
    return q
end

function KD.Teams()
    local l = Store.List("kader")
    table.sort(l, function(a, b) return (a.name or "") < (b.name or "") end)
    return l
end
local function save(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    c.by, c.u2 = c.by or ns.me(), ns.now()
    Store.Put("kader", c)
end
function KD.NewTeam(name, day)
    if not canEdit() then return end
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    save({ id = ns.newId("kd"), name = name:sub(1, 40), day = (day or ""):sub(1, 40), stamm = "", ersatz = "", by = ns.me() })
end
function KD.Set(team, who, where)   -- where = "stamm" | "ersatz" | nil (entfernen)
    if not canEdit() or not team then return end
    who = ns.fullName(who)
    local st, er = {}, {}
    for _, n in ipairs(split(team.stamm)) do if not ns.SameName(n, who) then st[#st + 1] = n end end
    for _, n in ipairs(split(team.ersatz)) do if not ns.SameName(n, who) then er[#er + 1] = n end end
    if where == "stamm" then st[#st + 1] = who elseif where == "ersatz" then er[#er + 1] = who end
    team.stamm, team.ersatz = table.concat(st, ","), table.concat(er, ",")
    save(team)
end
function KD.Delete(team) if canEdit() and team then Store.Delete("kader", team.id) end end

-- Abmeldungen
function KD.Absences(who)
    local today = date("%Y-%m-%d")
    return Store.List("absent", function(a) return (a.d or "") >= today and (not who or ns.SameName(a.who, who)) end)
end
function KD.Absent(dayText, why)
    local d, m = tostring(dayText or ""):match("^(%d+)%.(%d+)")
    if not d then ns.print(L["Enter the date as DD.MM, e.g. 24.10"]) return end
    local y = tonumber(date("%Y"))
    if tonumber(m) < tonumber(date("%m")) then y = y + 1 end
    local iso = ("%04d-%02d-%02d"):format(y, tonumber(m), tonumber(d))
    Store.Put("absent", { id = "ab-" .. ns.NameKey(ns.me()) .. "-" .. iso, who = ns.me(), d = iso, why = tostring(why or ""):sub(1, 60), by = ns.me(), ts = ns.now() })
    K.Toast(L["Signed off"], (L["For %s - raid leaders see it in the roster."]):format(d .. "." .. m), C.mint)
end
-- Hinweis an die Raidleitung, wenn sich jemand aus einem Stamm abmeldet
do
    ns.Listen("STORE", function(name, rec, old)
        if name ~= "absent" or old or not rec or ns.isMe(rec.who) or not canEdit() then return end
        for _, t in ipairs(KD.Teams()) do
            for _, n in ipairs(split(t.stamm)) do
                if ns.SameName(n, rec.who) then
                    K.Toast(L["Roster absence"], (L["%s is absent on %s (%s)"]):format(short(rec.who), rec.d or "?", t.name or ""), C.amber)
                    return
                end
            end
        end
    end)
end
-- Ersatz an der Reihe: am wenigsten dabei, nicht abgemeldet
function KD.NextBench(team)
    local best, bq
    for _, n in ipairs(split(team.ersatz)) do
        if #KD.Absences(n) == 0 then
            local q = att(n) or 0
            if not bq or q < bq then best, bq = n, q end
        end
    end
    return best
end

------------------------------------------------------------------------
-- Seite "Kader"
------------------------------------------------------------------------
local cards = {}
local function glass(f, a) local G = ns.Insta and ns.Insta.Glass if not (G and pcall(G, f, { 1, 1, 1, a or 0.035 }, { 1, 1, 1, 0.09 }, 10)) then K.Fill(f, { 1, 1, 1, 0.03 }) end end
local function memberMenu(owner, team, who)
    if not canEdit() then return end
    K.ShowMenu(owner, {
        { text = L["To the core"], fn = function() KD.Set(team, who, "stamm") ns.RefreshPage("kader") end },
        { text = L["To the bench"], fn = function() KD.Set(team, who, "ersatz") ns.RefreshPage("kader") end },
        { text = L["Remove from team"], fn = function() KD.Set(team, who, nil) ns.RefreshPage("kader") end },
        { text = L["Open file"], disabled = not ns.Leadership, fn = function() if ns.Leadership then ns.Leadership.ShowDossier(who) end end },
    }, short(who))
end
local function personLine(parent, i)
    parent.lines = parent.lines or {}
    local b = parent.lines[i]
    if not b then
        b = CreateFrame("Button", nil, parent)
        b:SetHeight(18)
        b.t = K.Text(b, 12, C.text) b.t:SetPoint("LEFT", 0, 0)
        b.r = K.Text(b, 11, C.dim, "RIGHT") b.r:SetPoint("RIGHT", 0, 0)
        b:RegisterForClicks("RightButtonUp", "LeftButtonUp")
        parent.lines[i] = b
    end
    return b
end
local function fillCard(c, team)
    c.team = team
    c.title:SetText(team.name or "?")
    c.day:SetText(team.day or "")
    for _, b in ipairs(c.lines or {}) do b:Hide() end
    local y, i = -52, 0
    local function section(label, list, bench)
        i = i + 1
        local h = personLine(c, i)
        h:ClearAllPoints() h:SetPoint("TOPLEFT", 14, y) h:SetPoint("RIGHT", c, "RIGHT", -14, 0)
        h.t:SetText("|cff999999" .. K.Upper(label) .. "  (" .. #list .. ")|r") h.r:SetText("")
        h:SetScript("OnClick", nil) h:Show()
        y = y - 20
        local nextB = bench and KD.NextBench(team)
        for _, n in ipairs(list) do
            i = i + 1
            local b = personLine(c, i)
            b:ClearAllPoints() b:SetPoint("TOPLEFT", 14, y) b:SetPoint("RIGHT", c, "RIGHT", -14, 0)
            local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[ns.fullName(n)]
            local cr, cg, cb = ns.classColor(m and m.class)
            local ab = KD.Absences(n)[1]
            b.t:SetText(short(n) .. (ab and ("  |cffff6a5a" .. (L["absent %s"]):format(ab.d:sub(9, 10) .. "." .. ab.d:sub(6, 7)) .. "|r") or "")
                .. ((nextB and ns.SameName(nextB, n)) and ("  |cff66db9e" .. L["next up"] .. "|r") or ""))
            b.t:SetTextColor(cr or 1, cg or 1, cb or 1)
            local q = att(n)
            b.r:SetText(q and (math.floor(q * 100 + 0.5) .. "%") or "-")
            b:SetScript("OnClick", function(self, btn) if btn == "RightButton" then memberMenu(self, team, n) end end)
            b:Show()
            y = y - 18
        end
        y = y - 8
    end
    section(L["Core"], split(team.stamm))
    section(L["Bench"], split(team.ersatz), true)
    c.add:SetShown(canEdit())
    c.del:SetShown(canEdit())
    c:SetHeight(math.max(140, -y + 44))
end
local function card(p, idx)
    local c = cards[idx]
    if c then return c end
    c = CreateFrame("Frame", nil, p.body)
    glass(c, 0.035)
    c.title = K.Title(c, 15, C.text) c.title:SetPoint("TOPLEFT", 14, -12)
    c.day = K.Text(c, 11, C.muted) c.day:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
    c.add = K.Input(c, 150, L["Add name"])
    c.add:SetPoint("BOTTOMLEFT", 14, 10)
    c.add:SetScript("OnEnterPressed", function(self)
        local n = self:GetText()
        if n ~= "" and c.team then KD.Set(c.team, n, "ersatz") self:SetText("") ns.RefreshPage("kader") end
        self:ClearFocus()
    end)
    if K.AttachNameSuggest then pcall(K.AttachNameSuggest, c.add) end
    c.del = K.Button(c, L["Delete team"], 100, 20, "ghost", function() if c.team then KD.Delete(c.team) ns.RefreshPage("kader") end end)
    c.del:SetPoint("BOTTOMRIGHT", -10, 10)
    cards[idx] = c
    return c
end
StaticPopupDialogs["OASIS_KADER_NEW"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 60,
    OnAccept = function(self) local eb = self.editBox or self.EditBox local t = eb and eb:GetText() or ""
        local name, day = t:match("^(.-)%s*%-%s*(.+)$")
        KD.NewTeam(name or t, day or "") ns.RefreshPage("kader") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["OASIS_KADER_ABSENT"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 70,
    OnAccept = function(self) local eb = self.editBox or self.EditBox local t = eb and eb:GetText() or ""
        local d, why = t:match("^%s*(%d+%.%d+)%.?%s*(.*)$")
        KD.Absent(d or t, why) ns.RefreshPage("kader") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
ns.RegisterPage({
    key = "kader", title = "Raid roster", order = 2.78,
    sub = "Fixed raid teams: core, bench, attendance and who is next up",
    build = function(p)
        p.new = K.Button(p, L["New team"], 130, 24, nil, function() StaticPopup_Show("OASIS_KADER_NEW", L["Name and raid day, e.g. 'Team Middle - Wed + Sun 8 pm'"]) end)
        p.new:SetPoint("TOPLEFT", 0, 0)
        p.abs = K.Button(p, L["I'm absent on ..."], 140, 24, "ghost", function() StaticPopup_Show("OASIS_KADER_ABSENT", L["Date (DD.MM) and reason, e.g. '24.10 late shift'"]) end)
        p.abs:SetPoint("LEFT", p.new, "RIGHT", 8, 0)
        p.mine = K.Text(p, 11, C.muted) p.mine:SetPoint("LEFT", p.abs, "RIGHT", 12, 0) p.mine:SetPoint("RIGHT", p, "RIGHT", -4, 0) p.mine:SetWordWrap(false)
        p.body = CreateFrame("Frame", nil, p)
        p.body:SetPoint("TOPLEFT", 0, -36)
        p.body:SetPoint("BOTTOMRIGHT", 0, 0)
        p.empty = K.Text(p.body, 13, C.dim, "CENTER") p.empty:SetPoint("TOP", 0, -80)
        p.empty:SetText(L["No teams yet. Raid leaders create them with 'New team'."])
    end,
    refresh = function(p)
        p.new:SetShown(canEdit())
        local mine = KD.Absences(ns.me())
        local md = {}
        for _, a in ipairs(mine) do md[#md + 1] = a.d:sub(9, 10) .. "." .. a.d:sub(6, 7) end
        p.mine:SetText(#md > 0 and ((L["You signed off: %s"]):format(table.concat(md, ", "))) or "")
        for _, c in ipairs(cards) do c:Hide() end
        local teams = KD.Teams()
        p.empty:SetShown(#teams == 0)
        local w = p.body:GetWidth() or 760
        if w < 300 then w = 760 end
        local cw = math.floor((w - 14) / 2)
        local colY = { 0, 0 }
        for i, t in ipairs(teams) do
            local c = card(p, i)
            fillCard(c, t)
            local col = (colY[1] <= colY[2]) and 1 or 2
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", p.body, "TOPLEFT", (col - 1) * (cw + 14), -colY[col])
            c:SetWidth(cw)
            c:Show()
            colY[col] = colY[col] + c:GetHeight() + 12
        end
    end,
})
ns.ICONS.kader = ns.MEDIA .. "icons\\raid"
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "raid" then
        local has = false
        for _, k in ipairs(g.pages) do if k == "kader" then has = true end end
        if not has then table.insert(g.pages, 2, "kader") end
    end
end
ns.slash.kader = function() if ns.Expand then ns.Expand("kader") else ns.ShowPage("kader") end end
ns.slash.fehle = function(arg) local d, why = tostring(arg or ""):match("^%s*(%d+%.%d+)%.?%s*(.*)$") if d then KD.Absent(d, why) else StaticPopup_Show("OASIS_KADER_ABSENT", L["Date (DD.MM) and reason, e.g. '24.10 late shift'"]) end end

end)

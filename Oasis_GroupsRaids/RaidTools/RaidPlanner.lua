-- Oasis: Raid-Planer - Aufstellung per Klick vorbauen, dann alle einladen und in ihre Gruppen sortieren
-- Plan = { id = "plan-<Termin>", ev, size, g = "Name:Gruppe:Rolle,..." }  (wird mit der Gilde geteilt)
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Kern\Diagnose\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Planner = {}
ns.RaidPlanner = Planner

local ROLE_NAMES = { tank = "Tank", heal = "Heiler", dps = "Schaden" }
local function roleColor(k) return ns.Profile and ns.Profile.ROLE_COLORS[k] or C.muted end

------------------------------------------------------------------------
-- Plan lesen/schreiben
------------------------------------------------------------------------
-- Glas 2026: Flaeche + Kante (Kante zeigt Auswahl/Ziel beim Ziehen)
local function glass(f, line, fill, r)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, fill or { 1, 1, 1, 0.035 }, line or { 1, 1, 1, 0.08 }, r or 6) return true end
end
local function sline(s, c)
    if s.glassFill then glass(s, c and { c[1], c[2], c[3], 0.8 } or nil) else K.SetBorderColor(s, c or C.line) end
end
local function simOn() return ns.Sim and ns.Sim.Active() or false end
-- Raid-Simulator: eigener, nur lokaler Plan (demo-sim-ID -> wird nie geteilt, beim Stopp entfernt)
function Planner.PlanId(evId) return (simOn() and (ns.Sim.PREFIX or "demo-sim-") or "") .. "plan-" .. (evId or "frei") end
function Planner.Get(evId)
    local rec = Store.Get("raidplan", Planner.PlanId(evId))
    local plan = { ev = evId, size = rec and rec.size or 20, slots = {} }
    for name, g, role in ((rec and rec.g) or ""):gmatch("([^:,]+):(%d+):?(%a*)") do
        plan.slots[name] = { group = tonumber(g), role = role ~= "" and role or nil }
    end
    return plan
end
function Planner.CanEdit() return simOn() or not ns.Admin or not ns.Admin.CanRaidPlan or ns.Admin.CanRaidPlan() end
function Planner.Save(plan)
    if not Planner.CanEdit() then
        ns.print(L["Den Raidplan bearbeiten duerfen Gildenleitung, Schlachtzugsleiter und Raid-Assistenten."])
        ns.RefreshPage("raid")
        return
    end
    local t = {}
    for name, s in pairs(plan.slots) do t[#t + 1] = name .. ":" .. s.group .. ":" .. (s.role or "") end
    table.sort(t)
    Store.Put("raidplan", { id = Planner.PlanId(plan.ev), ev = plan.ev, size = plan.size, g = table.concat(t, ",") })
end
function Planner.Members(plan, group)
    local out = {}
    for name, s in pairs(plan.slots) do if s.group == group then out[#out + 1] = name end end
    table.sort(out)
    return out
end
function Planner.Groups(plan) return math.max(1, math.ceil((plan.size or 20) / 5)) end

-- Rolle eines Kandidaten: Anmeldung > Profil > Schaden
local SIM_ROLE = { TANK = "tank", HEALER = "heal", DAMAGER = "dps" }
function Planner.RoleOf(name, evId)
    local sm = simOn() and ns.Group.Member(name)
    if sm and SIM_ROLE[sm.role or ""] then return SIM_ROLE[sm.role] end
    if evId then
        local s = Store.Get("signups", evId .. "@" .. name)
        if s and s.status == "yes" and s.role then return s.role end
    end
    if ns.Profile then
        local r = ns.Profile.RolesOf(name)
        for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then return k end end
    end
    return "dps"
end

-- Kandidaten: Angemeldete / Online / Alle
function Planner.Candidates(plan, mode)
    local out, seen = {}, {}
    local function add(name, extra)
        if seen[name] or plan.slots[name] then return end
        seen[name] = true
        local m = ns.Radar.byName[name]
        local sm = simOn() and ns.Group.Member(name)
        if sm then
            out[#out + 1] = { name = name, role = Planner.RoleOf(name, plan.ev), online = sm.online and true or false, level = sm.level or 60, class = sm.class, status = extra, sim = true }
            return
        end
        out[#out + 1] = { name = name, role = Planner.RoleOf(name, plan.ev), online = ns.isMe(name) or (m and m.online) or false,
            level = m and m.level or 0, class = m and m.class, status = extra }
    end
    -- Raid-Simulator: der simulierte Raid steht oben im Pool (zum Ziehen)
    if simOn() then for _, sm in ipairs(ns.Group.Members()) do add(sm.name, "yes") end end
    if plan.ev and mode ~= "all" and mode ~= "online" then
        for _, s in ipairs(ns.Raid.Signups(plan.ev)) do if s.status ~= "no" then add(s.who, s.status) end end
    end
    if mode == "online" or mode == "all" then
        for _, m in ipairs(ns.Radar.roster) do
            if mode == "all" or m.online then add(m.name) end
        end
        if not seen[ns.me()] then add(ns.me()) end
    end
    local order = { tank = 1, heal = 2, dps = 3 }
    table.sort(out, function(a, b)
        if (a.status == "yes") ~= (b.status == "yes") then return a.status == "yes" end
        if order[a.role] ~= order[b.role] then return order[a.role] < order[b.role] end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

-- Automatisch fuellen: Tanks und Heiler gleichmaessig auf die Gruppen, Rest Schaden
function Planner.AutoFill(plan, mode)
    local groups = Planner.Groups(plan)
    local free = {}
    for g = 1, groups do free[g] = 5 - #Planner.Members(plan, g) end
    local cands = Planner.Candidates(plan, mode)
    local placedHere = 0
    local function place(c, prefer)
        for step = 0, groups - 1 do
            local g = ((prefer - 1 + step) % groups) + 1
            if free[g] > 0 then
                plan.slots[c.name] = { group = g, role = c.role }
                free[g] = free[g] - 1
                placedHere = placedHere + 1
                return true
            end
        end
        return false
    end
    local rr = 1
    for _, role in ipairs({ "tank", "heal", "dps" }) do
        for _, c in ipairs(cands) do
            if c.role == role and not plan.slots[c.name] then
                place(c, rr)
                rr = rr % groups + 1
            end
        end
    end
    return placedHere
end

------------------------------------------------------------------------
-- Im Spiel umsetzen: einladen, Schlachtzug, Gruppen sortieren
------------------------------------------------------------------------
Planner.running = nil
local function rosterIndex()
    local idx, count = {}, {}
    for g = 1, 8 do count[g] = 0 end
    if simOn() then
        for i, m in ipairs(ns.Group.Members()) do
            idx[m.name] = { i = i, group = m.group, sim = true }
            count[m.group] = (count[m.group] or 0) + 1
        end
        return idx, count
    end
    if not IsInRaid() then return idx, count end
    for i = 1, (GetNumGroupMembers() or 0) do
        local name, _, sub = GetRaidRosterInfo(i)
        name = ns.safe(name)
        if name then
            idx[ns.fullName(name)] = { i = i, group = sub }
            count[sub] = (count[sub] or 0) + 1
        end
    end
    return idx, count
end
local function canLead() return ns.Group.IsLeader() or (IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player")) end

-- einen Schritt sortieren (Server mag keine Flut): true = es gab noch etwas zu tun
local function sortStep(plan)
    if not ns.Group.IsInRaid() or not canLead() or ns.inCombat() then return false end
    ns.Trace("Raid sortieren")
    local idx, count = rosterIndex()
    if simOn() then
        -- simuliert: Gruppen direkt umsetzen (eine Aenderung je Schritt, wie im Spiel)
        for name, s in pairs(plan.slots) do
            local cur = idx[name]
            if cur and cur.group ~= s.group then
                if (count[s.group] or 0) < 5 then ns.Sim.SetGroup(name, s.group) return true end
                for other, o in pairs(idx) do
                    local want = plan.slots[other]
                    if o.group == s.group and (not want or want.group ~= s.group) then
                        local m1, m2 = ns.Group.Member(name), ns.Group.Member(other)
                        if m1 and m2 then m1.group, m2.group = m2.group, m1.group end
                        return true
                    end
                end
            end
        end
        return false
    end
    for name, s in pairs(plan.slots) do
        local cur = idx[name]
        if cur and cur.group ~= s.group then
            if (count[s.group] or 0) < 5 then
                pcall(SetRaidSubgroup, cur.i, s.group)
            else
                -- Platz tauschen mit jemandem, der nicht in diese Gruppe gehoert
                for other, o in pairs(idx) do
                    local want = plan.slots[other]
                    if o.group == s.group and (not want or want.group ~= s.group) then
                        pcall(SwapRaidSubgroup, cur.i, o.i)
                        break
                    end
                end
            end
            return true
        end
    end
    return false
end

function Planner.Status(plan)
    local idx = rosterIndex()
    local inGroup, placed, total, online = 0, 0, 0, 0
    for name, s in pairs(plan.slots) do
        total = total + 1
        local m = ns.Radar.byName[name]
        if ns.isMe(name) or (m and m.online) then online = online + 1 end
        local cur = idx[name] or ((not ns.Group.IsInRaid() and (ns.isMe(name) or (UnitInParty and UnitInParty(ns.short(name))))) and { group = 1 })
        if cur then
            inGroup = inGroup + 1
            if cur.group == s.group then placed = placed + 1 end
        end
    end
    return { total = total, online = online, inGroup = inGroup, placed = placed }
end

local ticker
local function tick()
    local r = Planner.running
    if not r then return end
    local plan = Planner.Get(r.ev)
    -- Gruppe groesser als 5 geplant -> Schlachtzug
    local n = ns.Group.Num()
    local want = 0
    for _ in pairs(plan.slots) do want = want + 1 end
    if n > 1 and not ns.Group.IsInRaid() and want > 5 and C_PartyInfo and C_PartyInfo.ConvertToRaid and UnitIsGroupLeader("player") then
        pcall(C_PartyInfo.ConvertToRaid)
        return
    end
    -- noch nicht Eingeladene einladen (online, einmal pro 60 s)
    local idx = rosterIndex()
    -- offene Einladungen zaehlen: ohne Schlachtzug passen nur 5 (inkl. Einladungen) in die Gruppe
    local pending = 0
    for name, t in pairs(r.invited) do
        local inGrp = idx[name] or (UnitInParty and UnitInParty(ns.short(name)))
        if not inGrp and GetTime() - t < 60 then pending = pending + 1 end
    end
    for name in pairs(plan.slots) do
        local inGrp = idx[name] or ns.isMe(name) or (UnitInParty and UnitInParty(ns.short(name)))
        local m = ns.Radar.byName[name]
        local online = m and m.online
        if not inGrp and online and (not r.invited[name] or GetTime() - r.invited[name] > 60) then
            -- ohne Schlachtzug passen nur 5 in die Gruppe
            if ns.Group.IsInRaid() or (math.max(n, 1) + pending) < 5 then
                r.invited[name] = GetTime()
                if simOn() then ns.print(L["(Raid-Sim) Einladung an "] .. ns.displayName(name))
                elseif m and m.demo then ns.print(L["(Demo) Einladung an "] .. ns.displayName(name))
                elseif C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName(name)) end
                return
            end
        end
    end
    if sortStep(plan) then return end
    ns.RefreshPage("raid")
end

function Planner.Start(evId)
    Planner.running = { ev = evId, invited = {}, t = GetTime(), sim = simOn() or nil }
    if not ticker then ticker = C_Timer.NewTicker(0.4, function() pcall(tick) end) end
    K.Toast(L["Raid wird aufgebaut"], L["Einladen und Gruppen sortieren laeuft - Oasis kuemmert sich."], C.accent)
    ns.RefreshPage("raid")
end
function Planner.Stop()
    Planner.running = nil
    if ticker then ticker:Cancel() ticker = nil end
    ns.RefreshPage("raid")
end
-- Live: laeuft ein Raid und ich leite ihn, werden Aenderungen sofort umgesetzt
function Planner.LiveApply(plan)
    if ns.Group.IsInRaid() and canLead() then
        Planner.running = Planner.running or { ev = plan.ev, invited = {}, t = GetTime(), sim = simOn() or nil }
        if not ticker then ticker = C_Timer.NewTicker(0.4, function() pcall(tick) end) end
    end
end
ns.On("GROUP_ROSTER_UPDATE", function() ns.RefreshPage("raid") end)

------------------------------------------------------------------------
-- Reiter "Aufstellung" (wird von der Raid-Seite eingebunden)
------------------------------------------------------------------------
local selEv, poolMode, picked, pickedSlot = nil, "signed", nil, nil
local drag, ghost, pageF

function Planner.Build(f)
    pageF = f
    -- Termin waehlen, Groesse, Aktionen
    f.evDrop = K.Dropdown(f, 190, L["Termin"], function()
        local items = { { key = "frei", text = L["Ohne Termin"] } }
        for _, e in ipairs(ns.Raid.Events()) do
            items[#items + 1] = { key = e.id, text = ns.weekday(e.ts, true) .. " " .. date("%d.%m.", e.ts) .. "  " .. (e.title or "?") }
        end
        return items
    end, function() return selEv or "frei" end, function(v)
        selEv = (v ~= "frei") and v or nil
        picked, pickedSlot = nil, nil
        ns.RefreshPage("raid")
    end)
    f.evDrop:SetPoint("TOPLEFT", 0, 0)
    f.size = K.Segments(f, { { key = 10, text = "10" }, { key = 20, text = "20" }, { key = 40, text = "40" } }, function(k)
        local plan = Planner.Get(selEv)
        plan.size = k
        -- Leute aus wegfallenden Gruppen zurueck in den Pool
        for name, s in pairs(plan.slots) do if s.group > Planner.Groups(plan) then plan.slots[name] = nil end end
        Planner.Save(plan)
    end, 44)
    f.size:SetPoint("LEFT", f.evDrop, "RIGHT", 12, 0)
    f.auto = K.Button(f, L["Auto-Fuellen"], 104, 24, "ghost", function()
        local plan = Planner.Get(selEv)
        local n = Planner.AutoFill(plan, poolMode)
        Planner.Save(plan)
        if n == 0 then ns.print(L["Keine passenden Kandidaten mehr - wechsle links auf 'Online' oder 'Alle'."]) end
    end)
    f.auto:SetPoint("LEFT", f.size, "RIGHT", 12, 0)
    f.clear = K.Button(f, L["Leeren"], 64, 24, "ghost", function()
        local plan = Planner.Get(selEv)
        plan.slots = {}
        Planner.Save(plan)
    end)
    f.clear:SetPoint("LEFT", f.auto, "RIGHT", 6, 0)
    -- ein Klick: alle Zusagen auf die Gruppen verteilen und sofort einladen/sortieren
    f.oneClick = K.Button(f, L["Einteilen & starten"], 150, 24, "ghost", function()
        if not selEv then ns.print(L["Erst oben einen Termin waehlen."]) return end
        local plan = Planner.Get(selEv)
        Planner.AutoFill(plan, "signed")
        Planner.Save(plan)
        if not Planner.running then Planner.Start(selEv) end
    end)
    f.oneClick:SetPoint("LEFT", f.clear, "RIGHT", 6, 0)
    f.oneClick:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Zusagen einteilen & starten"], L["Alle Zusagen auf die Gruppen verteilen und sofort einladen und sortieren."] }) end)
    f.oneClick:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- schmales Fenster: Knoepfe enger bzw. "Einteilen & starten" in die zweite Zeile rechts
    f:HookScript("OnSizeChanged", function(self, w)
        w = w or 0
        local need = 190 + 12 + (self.size:GetWidth() or 130) + 12 + 104 + 6 + 64 + 6 + 150
        self.oneClick:ClearAllPoints()
        if w > 0 and w < need then self.oneClick:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -34)
        else self.oneClick:SetPoint("LEFT", self.clear, "RIGHT", 6, 0) end
    end)
    f.lockHint = K.Text(f, 11, C.amber, "RIGHT")
    f.lockHint:SetPoint("TOPRIGHT", 0, -6)
    f.lockHint:SetText(L["Nur ansehen - bearbeiten: Leitung, Schlachtzugsleiter, Raid-Assistenten"])
    f.lockHint:Hide()

    -- links: Kandidaten
    f.pool = K.Segments(f, { { key = "signed", text = L["Angemeldet"] }, { key = "online", text = L["Online"] }, { key = "all", text = L["Alle"] } }, function(k)
        poolMode = k
        ns.RefreshPage("raid")
    end, 72)
    f.pool:SetPoint("TOPLEFT", 0, -34)
    f.cands = K.List(f, 24, function(l)
        local r = K.Row(l)
        r.role = r:CreateTexture(nil, "ARTWORK")
        r.role:SetSize(14, 14)
        r.role:SetPoint("LEFT", 6, 0)
        r:Col("name", 26, 150, 12)
        r:Col("st", 0, 40, 10, C.dim, "RIGHT")
        r.cols.st:ClearAllPoints()
        r.cols.st:SetPoint("RIGHT", -6, 0)
        r:SetScript("OnClick", function(self)
            if not self.item then return end
            picked = (picked ~= self.item.name) and self.item.name or nil
            pickedSlot = nil
            ns.RefreshPage("raid")
        end)
        r:SetScript("OnEnter", function(self) if not drag and self.item and ns.Radar.byName[self.item.name] then ns.Radar.ShowMemberTip(self, ns.Radar.byName[self.item.name]) end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function(self) if self.item then Planner.BeginDrag(self.item.name) end end)
        r:SetScript("OnDragStop", function() Planner.EndDrag() end)
        return r
    end, function(r, c)
        r.role:SetTexture(ns.Profile and ns.Profile.RoleTexture(c.role))
        local rc = roleColor(c.role)
        r.role:SetVertexColor(rc[1], rc[2], rc[3])
        r.cols.name:SetText((c.online and "" or "|cff777777") .. ns.colorName(c.name, c.class) .. " |cff888888" .. (c.level > 0 and c.level or "") .. "|r")
        r.cols.st:SetText(c.status == "maybe" and "|cffe8b44a?|r" or (c.online and "" or L["offline"]))
        r.sel:SetShown(picked == c.name)
        r:SetAlpha(c.online and 1 or 0.55)
    end)
    f.cands:SetPoint("TOPLEFT", 0, -62)
    f.cands:SetPoint("BOTTOMLEFT", 0, 50)
    f.cands:SetWidth(200)
    f.candsBg = CreateFrame("Frame", nil, f)
    f.candsBg:SetPoint("TOPLEFT", f.cands, "TOPLEFT", -4, 4)
    f.candsBg:SetPoint("BOTTOMRIGHT", f.cands, "BOTTOMRIGHT", 4, -4)
    f.candsBg:SetFrameLevel(math.max(0, f.cands:GetFrameLevel() - 1))
    glass(f.candsBg, { 1, 1, 1, 0.08 }, { 1, 1, 1, 0.025 }, 12)
    f.cands.empty:SetText(L["Keine Kandidaten.\nOben 'Online' oder 'Alle' waehlen."])

    -- rechts: Gruppen
    f.groups = {}
    for g = 1, 8 do
        local box = CreateFrame("Frame", nil, f)
        box:SetSize(124, 132)
        box.panel = CreateFrame("Frame", nil, box)
        box.panel:SetPoint("TOPLEFT", -6, 4)
        box.panel:SetPoint("BOTTOMRIGHT", 6, -6)
        box.panel:SetFrameLevel(math.max(0, box:GetFrameLevel() - 1))
        glass(box.panel, { 1, 1, 1, 0.07 }, { 1, 1, 1, 0.02 }, 10)
        box:SetPoint("TOPLEFT", 214 + ((g - 1) % 4) * 132, -40 - math.floor((g - 1) / 4) * 142)
        box.head = K.Text(box, 11, C.muted)
        box.head:SetPoint("TOPLEFT", 2, 0)
        box.slots = {}
        for i = 1, 5 do
            local s = CreateFrame("Button", nil, box)
            s:SetSize(124, 22)
            s:SetPoint("TOPLEFT", 0, -18 - (i - 1) * 23)
            s.bg = K.Fill(s, C.field)
            K.Border(s, C.line)
            glass(s)
            s.role = s:CreateTexture(nil, "ARTWORK")
            s.role:SetSize(13, 13)
            s.role:SetPoint("LEFT", 5, 0)
            s.text = K.Text(s, 11, C.text)
            s.text:SetPoint("LEFT", 22, 0)
            s.text:SetPoint("RIGHT", -14, 0)
            s.state = s:CreateTexture(nil, "OVERLAY")
            s.state:SetTexture(ns.MEDIA .. "dot")
            s.state:SetSize(7, 7)
            s.state:SetPoint("RIGHT", -4, 0)
            s:RegisterForClicks("AnyUp")
            s.group = g
            s:SetScript("OnClick", function(self, btn) Planner.ClickSlot(self, btn) end)
            s:RegisterForDrag("LeftButton")
            s:SetScript("OnDragStart", function(self) if self.who then Planner.BeginDrag(self.who, self) end end)
            s:SetScript("OnDragStop", function() Planner.EndDrag() end)
            s:SetScript("OnEnter", function(self)
                if drag then return end
                if self.who and ns.Radar.byName[self.who] then ns.Radar.ShowMemberTip(self, ns.Radar.byName[self.who])
                elseif picked then K.ShowTip(self, (L["Klick: %s hierher"]):format(ns.displayName(picked))) end
            end)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
            box.slots[i] = s
        end
        f.groups[g] = box
    end

    -- unten: Zusammenfassung + Umsetzen
    f.sum = K.Text(f, 12, C.text)
    f.sum:SetPoint("BOTTOMLEFT", 0, 22)
    f.sum:SetWidth(330)
    f.status = K.Text(f, 10, C.muted)
    f.status:SetPoint("BOTTOMLEFT", 0, 6)
    f.status:SetWidth(470)
    f.go = K.Button(f, "", 230, 30, "primary", function()
        if Planner.running then Planner.Stop() else Planner.Start(selEv) end
    end)
    f.go:SetPoint("BOTTOMRIGHT", 0, 6)
    f.hint = K.Text(f, 10, C.dim, "RIGHT")
    f.hint:SetPoint("BOTTOMRIGHT", f.go, "TOPRIGHT", 0, 4)
    f.hint:SetText(L["Ziehen oder anklicken  ·  Rechtsklick: entfernen"])
    f.legend = K.Text(f, 10, C.dim)
    f.legend:SetPoint("BOTTOMLEFT", 214, 22)
end

local function slotUnderMouse()
    if not pageF then return nil end
    for _, box in ipairs(pageF.groups) do
        if box:IsShown() then
            for _, s in ipairs(box.slots) do if s:IsMouseOver() then return s end end
        end
    end
end
local function buildGhost()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(150, 26)
    ghost.bg = K.Fill(ghost, C.raised)
    K.Border(ghost, C.accent)
    ghost.role = ghost:CreateTexture(nil, "ARTWORK")
    ghost.role:SetSize(16, 16)
    ghost.role:SetPoint("LEFT", 6, 0)
    ghost.text = K.Text(ghost, 12, C.text)
    ghost.text:SetPoint("LEFT", 28, 0)
    ghost.text:SetPoint("RIGHT", -6, 0)
    ghost:SetScript("OnUpdate", function(self, el)
        if not drag then self:Hide() return end
        self.t = (self.t or 0) + el
        -- weich einblenden + leicht schweben
        local a = math.min(1, self.t * 6)
        self:SetAlpha(0.35 + 0.6 * a)
        self:SetScale(0.85 + 0.15 * a)
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale() * self:GetScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 14, y / sc - 2 + math.sin(self.t * 6) * 2)
        -- Platz unter der Maus hervorheben
        local over = slotUnderMouse()
        if over ~= self.over then
            if self.over then sline(self.over, nil) end
            if over then sline(over, C.accent) end
            self.over = over
        end
    end)
end
function Planner.BeginDrag(name, fromSlot)
    if not name then return end
    drag = { name = name, from = fromSlot }
    if not ghost then buildGhost() end
    local role = (fromSlot and Planner.Get(selEv).slots[name] and Planner.Get(selEv).slots[name].role) or Planner.RoleOf(name, selEv)
    ghost.role:SetTexture(ns.Profile and ns.Profile.RoleTexture(role))
    local rc = roleColor(role)
    ghost.role:SetVertexColor(rc[1], rc[2], rc[3])
    local m = ns.Radar.byName[name]
    ghost.text:SetText(ns.colorName(name, m and m.class))
    ghost.t, ghost.over = 0, nil
    ghost:Show()
    GameTooltip:Hide()
end
-- kurzes Aufleuchten nach dem Ablegen
local function flash(slot)
    if not slot then return end
    slot.flash = slot.flash or slot:CreateTexture(nil, "OVERLAY")
    slot.flash:SetAllPoints()
    slot.flash:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
    slot.flash:Show()
    local t = 0
    slot:SetScript("OnUpdate", function(self, el)
        t = t + el
        self.flash:SetAlpha(math.max(0, 0.5 - t))
        if t > 0.5 then self.flash:Hide() self:SetScript("OnUpdate", nil) end
    end)
end
function Planner.EndDrag()
    if not drag then return end
    local d = drag
    drag = nil
    if ghost then
        if ghost.over then sline(ghost.over, nil) end
        ghost:Hide()
    end
    local target = slotUnderMouse()
    local plan = Planner.Get(selEv)
    if target then
        if d.from and d.from == target then return end
        local occupant = target.who
        if d.from then
            -- Platz -> Platz: verschieben bzw. tauschen
            local ga = plan.slots[d.name] and plan.slots[d.name].group
            if not ga then return end
            plan.slots[d.name].group = target.group
            if occupant then plan.slots[occupant].group = ga end
        else
            -- Kandidat -> Platz: wer dort sass, geht zurueck in den Pool
            if occupant then plan.slots[occupant] = nil end
            if not occupant and #Planner.Members(plan, target.group) >= 5 then return end
            plan.slots[d.name] = { group = target.group, role = Planner.RoleOf(d.name, selEv) }
        end
        picked, pickedSlot = nil, nil
        Planner.Save(plan)
        Planner.LiveApply(plan)
        ns.After(0.05, function() flash(slotUnderMouse() or target) end)
    elseif d.from and pageF and pageF.cands:IsMouseOver() then
        -- zurueck in die Kandidatenliste = entfernen
        plan.slots[d.name] = nil
        Planner.Save(plan)
        Planner.LiveApply(plan)
    end
end

function Planner.ClickSlot(s, btn)
    local plan = Planner.Get(selEv)
    if btn == "RightButton" then
        if s.who then plan.slots[s.who] = nil Planner.Save(plan) Planner.LiveApply(plan) end
        return
    end
    if picked then
        -- Kandidat auf den Platz; wer dort war, geht zurueck in den Pool
        if s.who then plan.slots[s.who] = nil end
        if #Planner.Members(plan, s.group) >= 5 and not s.who then return end
        plan.slots[picked] = { group = s.group, role = Planner.RoleOf(picked, selEv) }
        picked = nil
        Planner.Save(plan)
        Planner.LiveApply(plan)
        return
    end
    if pickedSlot and pickedSlot ~= s then
        -- zwei Plaetze tauschen / verschieben
        local a = pickedSlot.who
        if a then
            local b = s.who
            local ga = plan.slots[a].group
            plan.slots[a].group = s.group
            if b then plan.slots[b].group = ga end
            Planner.Save(plan)
            Planner.LiveApply(plan)
        end
        pickedSlot = nil
        ns.RefreshPage("raid")
        return
    end
    pickedSlot = s.who and s or nil
    ns.RefreshPage("raid")
end

function Planner.Refresh(f)
    if f.lockHint then
        local ok = Planner.CanEdit()
        f.lockHint:SetShown(not ok)
        for _, b in ipairs({ f.auto, f.clear, f.oneClick }) do if b and b.SetEnabledState then b:SetEnabledState(ok) end end
    end
    if selEv and not Store.Get("events", selEv) then selEv = nil end
    if not selEv then
        local evs = ns.Raid.Events()
        if evs[1] then selEv = evs[1].id end
    end
    f.evDrop:Update()
    local plan = Planner.Get(selEv)
    if f.size.value ~= plan.size then f.size:Select(plan.size) end
    f.cands:SetData(Planner.Candidates(plan, (poolMode == "signed" and not selEv) and "online" or poolMode))
    local groups = Planner.Groups(plan)
    local idx = rosterIndex()
    local counts = { tank = 0, heal = 0, dps = 0 }
    for g, box in ipairs(f.groups) do
        box:SetShown(g <= groups)
        if g <= groups then
            local mem = Planner.Members(plan, g)
            box.head:SetText((L["Gruppe %d"]):format(g) .. "  |cff666666" .. #mem .. "/5|r")
            for i, s in ipairs(box.slots) do
                local name = mem[i]
                s.who = name
                if name then
                    local role = plan.slots[name].role or Planner.RoleOf(name, selEv)
                    counts[role] = (counts[role] or 0) + 1
                    s.role:SetTexture(ns.Profile and ns.Profile.RoleTexture(role))
                    local rc = roleColor(role)
                    s.role:SetVertexColor(rc[1], rc[2], rc[3])
                    s.role:Show()
                    local m = ns.Radar.byName[name]
                    s.text:SetText(ns.colorName(name, m and m.class))
                    -- Status: gruen = im Raid richtig, gelb = im Raid falsche Gruppe, grau = noch nicht da
                    local cur = idx[name]
                    local c = (cur and cur.group == g) and C.mint or (cur and C.amber) or ((m and m.online or ns.isMe(name)) and C.dim or C.red)
                    s.state:SetVertexColor(c[1], c[2], c[3])
                    s.state:Show()
                    sline(s, (pickedSlot == s) and C.accent or nil)
                else
                    s.role:Hide()
                    s.state:Hide()
                    s.text:SetText(picked and ("|cff666666" .. L["+ hier"] .. "|r") or "")
                    sline(s, picked and C.accent2 or nil)
                end
            end
        end
    end
    local st = Planner.Status(plan)
    local function part(k) return (ns.Profile and ns.Profile.RoleIcon(k, 13) or "") .. " " .. counts[k] end
    f.sum:SetText(part("tank") .. "   " .. part("heal") .. "   " .. part("dps") .. "     |cffe6e6e6" .. st.total .. "/" .. plan.size .. "|r")
    f.status:SetText((L["%d online  ·  %d in der Gruppe  ·  %d richtig einsortiert"]):format(st.online, st.inGroup, st.placed))
    f.legend:SetText("|cff66db9e●|r " .. L["richtig"] .. "   |cffe8b44a●|r " .. L["falsche Gruppe"] .. "   |cff555555●|r " .. L["noch nicht da"])
    if Planner.running then
        f.go:SetLabel(L["Aufbau stoppen"])
    else
        f.go:SetLabel(ns.Group.IsInRaid() and L["Raid jetzt anordnen"] or L["Alle einladen & anordnen"])
    end
    f.go:SetEnabledState(st.total > 0)
end

ns.Listen("STORE", function(coll) if coll == "raidplan" then ns.RefreshPage("raid") end end)
end)

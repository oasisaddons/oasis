-- Oasis: loot rules (like PackMule) - the master looter decides where certain loot
-- goes automatically, e.g. "trade goods to bank char", "grays to me". Applies on opening
-- of a corpse, only as master looter. Whatever a rule matches is not distributed.
-- Tab "Loot rules" on the raid check page (building blocks from ns.RCUI, RaidCheck.lua).
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_RaidTools", function()   -- Module Raid tools (can be disabled, see ModuleLoader.lua)
local L = ns.L
local function refreshAll() if ns.RCRefresh then ns.RCRefresh() else ns.RefreshPage("lootrules") end end
local K, C = ns.K, ns.K.C

local LR = {}
ns.LootRules = LR

LR.KINDS = {
    { key = "q0", text = "Grey items" },
    { key = "q1", text = "White items" },
    { key = "q2", text = "Green items" },
    { key = "q3", text = "Blue items" },
    { key = "trade", text = "Trade goods" },
    { key = "recipe", text = "Recipes" },
    { key = "quest", text = "Quest items" },
    { key = "name", text = "Name contains ..." },
}
local KIND = {}
for _, k in ipairs(LR.KINDS) do KIND[k.key] = k end

local function S() return ns.db.settings end
function LR.Rules() S().lootRules = S().lootRules or {} return S().lootRules end
function LR.On() return S().lootRulesOn ~= false end

-- does a rule match this loot slot? -> target (name) or nil
function LR.Match(slot)
    if not LR.On() then return nil end
    local link = GetLootSlotLink(slot)
    if not link then return nil end
    local _, name, _, _, quality = GetLootSlotInfo(slot)
    local id = tonumber(link:match("item:(%d+)"))
    local classID = id and select(6, C_Item.GetItemInfoInstant(id))
    for _, r in ipairs(LR.Rules()) do
        local hit
        local q = r.kind and r.kind:match("^q(%d)$")
        if q then hit = tonumber(quality) == tonumber(q)
        elseif r.kind == "trade" then hit = classID == 7
        elseif r.kind == "recipe" then hit = classID == 9
        elseif r.kind == "quest" then hit = classID == 12
        elseif r.kind == "name" then hit = r.value and r.value ~= "" and name and name:lower():find(r.value:lower(), 1, true) ~= nil
        end
        if hit then return r.to, r end
    end
    return nil
end
local function target(to)
    if not to or to == "" or to:lower() == "ich" or to:lower() == "me" then return ns.me() end
    return to
end
-- Give item to player (search master loot candidates)
local function give(slot, name)
    if not (GetMasterLootCandidate and GiveMasterLoot) then return false end
    local want = ns.short(name):lower()
    for ci = 1, 40 do
        local cand = GetMasterLootCandidate(slot, ci)
        if cand then
            local c = ns.short(ns.fullName(cand)):lower()
            if c == want or (ns.isMe(name) and UnitIsUnit(cand, "player")) then
                return pcall(GiveMasterLoot, slot, ci)
            end
        end
    end
    return false
end
LR.log = {}
function LR.Apply()
    if not (IsInGroup() and ns.LootMaster and ns.LootMaster.IsMasterLooter and ns.LootMaster.IsMasterLooter()) then return end
    if not LR.On() or #LR.Rules() == 0 then return end
    for slot = (GetNumLootItems() or 0), 1, -1 do
        local to = LR.Match(slot)
        if to then
            local who = target(to)
            local link = GetLootSlotLink(slot)
            if give(slot, who) then
                table.insert(LR.log, 1, { link = link, who = who, ts = ns.now() })
                if #LR.log > 30 then table.remove(LR.log) end
            else
                ns.print((L["Loot rule: %s could not go to %s (not in group / too far away?)."]):format(link or "?", ns.short(who)))
            end
        end
    end
    refreshAll()
end
ns.On("LOOT_OPENED", function() ns.After(0.05, function() pcall(LR.Apply) end) end)

------------------------------------------------------------------------
-- UI (embedded in raid check) - plain: sentence to create, list, small history
------------------------------------------------------------------------
local QCOL = { q0 = { 0.62, 0.62, 0.62 }, q1 = { 0.92, 0.92, 0.92 }, q2 = { 0.12, 1, 0 }, q3 = { 0.1, 0.5, 0.95 } }
local KIND_GLYPH = { q0 = "wants", q1 = "wants", q2 = "wants", q3 = "wants", trade = "crafting", recipe = "chronicle", quest = "checklist", name = "pin" }
local KIND_DESC = {
    q0 = "all grey items (junk)", q1 = "all white items", q2 = "all green items", q3 = "all blue items",
    trade = "Cloth, ore, herbs, leather ...", recipe = "Recipes, plans, formulas", quest = "Items for quests", name = "every item whose name contains this",
}
local TEMPLATES = {
    { kind = "trade", to = nil, text = "Trade goods -> bank alt", bank = true },
    { kind = "q0", to = "", text = "Grey items -> me" },
    { kind = "recipe", to = "", text = "Recipes -> me" },
    { kind = "quest", to = "", text = "Quest items -> me" },
}
local DEMO_RULES = {
    { kind = "trade", to = "Bankfach", demo = true },
    { kind = "q0", to = "", demo = true },
    { kind = "name", value = "Leinen", to = "Nadelfee", demo = true },
}
local DEMO_LOG = {
    { link = "|cff9d9d9d|Hitem:4865::::::::60:::::|h[Zerbrochener Fangzahn]|h|r", who = "", ago = 95 },
    { link = "|cffffffff|Hitem:2589::::::::60:::::|h[Leinenstoff]|h|r", who = "Bankfach", ago = 420 },
    { link = "|cffffffff|Hitem:14047::::::::60:::::|h[Runenstoff]|h|r", who = "Bankfach", ago = 1260 },
    { link = "|cff9d9d9d|Hitem:4878::::::::60:::::|h[Zerbrochene Kette]|h|r", who = "", ago = 2400 },
}
local ROW_H, LOG_ROWS, LOG_ROW_H = 30, 5, 18
local function U() return ns.RCUI end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() or false end
local function shownRules()
    local r = LR.Rules()
    if #r == 0 and demoOn() then return DEMO_RULES, true end
    return r, false
end
local function isMeTo(to) return not to or to == "" or to:lower() == "ich" or to:lower() == "me" end
local function targetText(to)
    if isMeTo(to) then return "|cff66db9e" .. L["me"] .. "|r" end
    if ns.Radar and ns.Radar.Colored and ns.Radar.byName and ns.Radar.byName[ns.fullName(to)] then return ns.Radar.Colored(ns.fullName(to)) end
    return ns.displayName(to)
end
local function whatText(e)
    local t = L[(KIND[e.kind] or {}).text or "?"]
    if e.kind == "name" then t = L["Name contains"] .. " |cffe8b44a\"" .. (e.value or "") .. "\"|r" end
    return t
end
local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function addRule(f, kind, value, to)
    local rules = LR.Rules()
    for _, r in ipairs(rules) do
        if r.kind == kind and (r.value or "") == (value or "") then
            K.Toast(L["Loot rules"], L["This rule already exists."], C.amber)
            return false
        end
    end
    rules[#rules + 1] = { kind = kind, value = kind == "name" and (value or "") or nil, to = trim(to) }
    f.flashIdx = #rules
    refreshAll()
    return true
end
-- Name suggestions from group/raid and guild
local function candidates()
    local out, seen = {}, {}
    local function add(n, cls, src)
        if not n or n == "" then return end
        local s = ns.short(n)
        if seen[s:lower()] or ns.isMe(n) then return end
        seen[s:lower()] = true
        out[#out + 1] = { name = n, short = s, class = cls, src = src }
    end
    if IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and 40 or 4 do
            local u = raid and ("raid" .. i) or ("party" .. i)
            if UnitExists(u) then
                local n = ns.safe(ns.UnitName(u))
                local _, cls = UnitClass(u)
                if n then add(ns.fullName(n), cls, "grp") end
            end
        end
    end
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do add(m.name, m.class, m.online and "on" or "off") end
    return out
end
local function attachSuggest(eb)
    local box = CreateFrame("Frame", nil, eb)
    box:SetFrameStrata("DIALOG")
    box:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -2)
    box:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", 40, -2)
    box:SetHeight(10)
    K.Fill(box, { 0.05, 0.05, 0.06, 0.98 })
    K.Border(box, C.accent2)
    box:Hide()
    box.rows = {}
    local function pick(name)
        eb:SetText(name)
        eb:SetCursorPosition(#name)
        box:Hide()
    end
    for i = 1, 7 do
        local r = CreateFrame("Button", nil, box)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 20)
        r:SetPoint("RIGHT", -3, 0)
        r.t = K.Text(r, 12, C.text)
        r.t:SetPoint("LEFT", 6, 0)
        r.s = K.Text(r, 10, C.dim, "RIGHT")
        r.s:SetPoint("RIGHT", -6, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        r:SetScript("OnClick", function(self) pick(self.name) end)
        box.rows[i] = r
    end
    local function update(self)
        local q = (self:GetText() or ""):lower()
        local list = {}
        if q == "" or (L["me"]):lower():find(q, 1, true) == 1 then list[1] = { short = L["me"], me = true } end
        local src = { grp = 1, on = 2, off = 3 }
        local cand = candidates()
        table.sort(cand, function(a, b)
            if src[a.src] ~= src[b.src] then return src[a.src] < src[b.src] end
            return a.short < b.short
        end)
        for _, c in ipairs(cand) do
            if q == "" and c.src == "off" then break end
            if c.short:lower():find(q, 1, true) == 1 then list[#list + 1] = c end
        end
        if #list == 0 then box:Hide() return end
        for i, r in ipairs(box.rows) do
            local c = list[i]
            r:SetShown(c ~= nil)
            if c then
                r.name = c.me and "" or c.short
                r.t:SetText(c.me and ("|cff66db9e" .. L["me"] .. "|r") or (c.class and ns.colorName(c.name, c.class) or c.short))
                r.s:SetText(c.me and L["yourself"] or c.src == "grp" and L["Group"] or c.src == "on" and L["Guild online"] or L["Guild"])
            end
        end
        box.first = list[1].me and "" or list[1].short
        box:SetHeight(6 + math.min(#list, #box.rows) * 20)
        box:Show()
    end
    eb:HookScript("OnTextChanged", function(self, user) if user then update(self) end end)
    eb:HookScript("OnEditFocusGained", function(self) update(self) end)
    eb:HookScript("OnTabPressed", function() if box:IsShown() and box.first then pick(box.first) end end)
    eb:HookScript("OnEditFocusLost", function() ns.After(0.2, function() box:Hide() end) end)
    return box
end

-- single-line font that truncates with "..." when space is short
local function line(parent, size, color, justify)
    local t = K.Text(parent, size, color, justify)
    t:SetWordWrap(false)
    if t.SetMaxLines then t:SetMaxLines(1) end
    return t
end

function LR.Build(f)
    local UI = U()
    -- Header: one line of explanation, below it toggles + status
    f.intro = line(f, 11, C.muted)
    f.intro:SetPoint("TOPLEFT", 0, -2)
    f.intro:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.intro:SetText(L["Matching loot goes to the chosen player automatically when you loot - the topmost matching rule wins."])
    f.on = K.Toggle(f, L["Rules active"], function() return LR.On() end, function(v) S().lootRulesOn = v refreshAll() end)
    f.on:SetPoint("TOPLEFT", 0, -22)
    f.on:SetWidth(140)
    f.ml = line(f, 11, C.muted)
    f.ml:SetPoint("LEFT", f.on, "LEFT", 150, 0)
    f.ml:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    -- Create rule as a sentence: [What v] [Extra] goes to [Name] [Add]          [Templates v]
    f.kind = "trade"
    f.kindBtn = K.Button(f, "", 170, 24, "ghost")
    f.kindBtn.isDropdown = true
    f.kindBtn.label:ClearAllPoints()
    f.kindBtn.label:SetPoint("LEFT", 10, 0)
    f.kindBtn.label:SetPoint("RIGHT", -20, 0)
    f.kindBtn.label:SetJustifyH("LEFT")
    f.kindBtn.label:SetWordWrap(false)
    f.kindBtn.arrow = K.Text(f.kindBtn, 10, C.dim, "RIGHT")
    f.kindBtn.arrow:SetPoint("RIGHT", -8, 0)
    f.kindBtn.arrow:SetText("v")
    f.kindBtn:SetPoint("TOPLEFT", 0, -60)
    local function setKind(k)
        f.kind = k or "trade"
        f.kindBtn.label:SetText(L[(KIND[f.kind] or LR.KINDS[1]).text])
        local nameOn = f.kind == "name"
        if f.val:IsShown() ~= nameOn then f.val:SetShown(nameOn) f:LayoutAdd() end
        if nameOn then f.val:SetFocus() end
    end
    f.kindBtn:SetScript("OnClick", function(self)
        local list = {}
        for _, k in ipairs(LR.KINDS) do
            list[#list + 1] = { text = L[k.text], checked = k.key == f.kind, fn = function() setKind(k.key) end }
        end
        K.ShowMenu(self, list, nil, 170)
    end)
    f.val = K.Input(f, 100, L["e.g. Linen"])
    f.val:SetPoint("LEFT", f.kindBtn, "RIGHT", 6, 0)
    f.val:Hide()
    f.goes = K.Text(f, 12, C.muted)
    f.goes:SetText(L["goes to"])
    f.to = K.Input(f, 150, L["Name (empty = me)"])
    f.toSuggest = attachSuggest(f.to)
    f.add = K.Button(f, L["Add"], 100, 24, "ghost", function()
        if f.kind == "name" and trim(f.val:GetText()) == "" then
            K.Toast(L["Loot rules"], L["Please enter part of a name, e.g. Linen."], C.amber)
            f.val:SetFocus()
            return
        end
        if addRule(f, f.kind, trim(f.val:GetText()), f.to:GetText()) then
            f.val:SetText("") f.to:SetText("")
            f.to.ph:SetText(L["Name (empty = me)"])
        end
    end)
    f.to.onEnter = function() f.add:Click() end
    f.val.onEnter = function() f.to:SetFocus() end
    function f:LayoutAdd()
        self.goes:ClearAllPoints()
        self.goes:SetPoint("LEFT", self.val:IsShown() and self.val or self.kindBtn, "RIGHT", 8, 0)
        self.to:ClearAllPoints()
        self.to:SetPoint("LEFT", self.goes, "RIGHT", 8, 0)
        self.add:ClearAllPoints()
        self.add:SetPoint("LEFT", self.to, "RIGHT", 6, 0)
    end
    f:LayoutAdd()
    setKind("trade")
    -- Templates as a small menu
    local function applyTemplate(t)
        if t.bank then
            setKind(t.kind)
            f.to:SetText("")
            f.to.ph:SetText(L["Name of the bank alt"])
            f.to:SetFocus()
        else
            addRule(f, t.kind, nil, t.to)
        end
    end
    f.ApplyTemplate = function(i) if TEMPLATES[i] then applyTemplate(TEMPLATES[i]) end end
    local function tplMenu(owner)
        local list = {}
        for _, t in ipairs(TEMPLATES) do list[#list + 1] = { text = L[t.text], fn = function() applyTemplate(t) end } end
        K.ShowMenu(owner, list, nil, 190)
    end
    f.tpl = K.Button(f, L["Templates"] .. "  v", 96, 24, "ghost", function(self) tplMenu(self) end)
    f.tpl.isDropdown = true
    f.tpl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -60)

    -- List of rules (full width)
    f.listHead = line(f, 10, C.dim)
    f.listHead:SetPoint("TOPLEFT", 0, -98)
    f.listHead:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    -- shared field for changing the target (click on the name)
    f.edit = K.Input(f, 170, L["Name (empty = me)"])
    f.edit:SetFrameStrata("DIALOG")
    f.edit:Hide()
    f.editSuggest = attachSuggest(f.edit)
    local function commitEdit()
        local idx = f.editIdx
        f.editIdx = nil
        f.edit:Hide()
        if not idx or f.editCancel then f.editCancel = nil return end
        local r = LR.Rules()[idx]
        if r then r.to = trim(f.edit:GetText()) end
        refreshAll()
    end
    f.edit.onEnter = function() commitEdit() end
    f.edit:HookScript("OnEscapePressed", function() f.editCancel = true commitEdit() end)
    f.edit:HookScript("OnEditFocusLost", function() ns.After(0.25, function() if f.editIdx then commitEdit() end end) end)
    local function startEdit(row, idx, e)
        f.editIdx, f.editCancel = idx, nil
        f.edit:ClearAllPoints()
        f.edit:SetPoint("LEFT", row.to, "LEFT", -4, 0)
        f.edit:SetText(isMeTo(e.to) and "" or e.to)
        f.edit:Show()
        f.edit:SetFocus()
    end

    f.list = K.List(f, ROW_H, function(l)
        local r = K.Row(l)
        r.num = line(r, 11, C.dim, "RIGHT")
        r.num:SetPoint("LEFT", 2, 0)
        r.num:SetWidth(18)
        r.ic = K.Glyph(r, 16, ns.MEDIA .. "icons\\wants", C.muted)
        r.ic:SetPoint("LEFT", 28, 0)
        r.what = line(r, 13, C.text)
        r.what:SetPoint("LEFT", 52, 0)
        r.what:SetPoint("RIGHT", r, "RIGHT", -310, 0)
        r.arr = K.Text(r, 13, C.blue, "CENTER")
        r.arr:SetPoint("RIGHT", -280, 0)
        r.arr:SetWidth(24)
        r.arr:SetText("->")
        r.to = CreateFrame("Button", nil, r)
        r.to:SetHeight(22)
        r.to:SetPoint("LEFT", r, "RIGHT", -270, 0)
        r.to:SetPoint("RIGHT", r, "RIGHT", -92, 0)
        r.to.t = line(r.to, 13, C.text)
        r.to.t:SetPoint("LEFT", 0, 0)
        r.to.t:SetPoint("RIGHT", 0, 0)
        r.to.hl = r.to:CreateTexture(nil, "HIGHLIGHT")
        r.to.hl:SetPoint("BOTTOMLEFT", 0, 1) r.to.hl:SetPoint("BOTTOMRIGHT", 0, 1)
        r.to.hl:SetHeight(1)
        r.to.hl:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.8)
        r.up = K.IconButton(r, "^", 18, nil, L["move up"])
        r.up:SetPoint("RIGHT", -62, 0)
        r.down = K.IconButton(r, "v", 18, nil, L["move down"])
        r.down:SetPoint("RIGHT", -40, 0)
        r.del = K.IconButton(r, "x", 16, nil, L["Put out"])
        r.del:SetPoint("RIGHT", -12, 0)
        r.demo = K.Text(r, 10, C.amber, "RIGHT")
        r.demo:SetPoint("RIGHT", -12, 0)
        r.demo:SetText(L["Demo"])
        local function tip(self)
            local e = r.item
            if not e then return end
            K.ShowTip(self, { whatText(e) .. "  ->  " .. targetText(e.to), L[KIND_DESC[e.kind] or ""],
                e.demo and ("|cfffac257" .. L["Example rule (demo) - add your own and the examples disappear."] .. "|r")
                or ("|cff888888" .. L["Click the name to change it."] .. "|r") })
        end
        r:SetScript("OnEnter", tip)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.to:SetScript("OnEnter", tip)
        r.to:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e, idx)
        r.item = e
        local c = QCOL[e.kind] or C.blue
        r.num:SetText(idx .. ".")
        r.ic:SetTexture(ns.MEDIA .. "icons\\" .. (KIND_GLYPH[e.kind] or "wants"))
        r.ic:SetVertexColor(c[1], c[2], c[3])
        r.what:SetText(whatText(e))
        r.to.t:SetText(targetText(e.to))
        local n = #(shownRules())
        r.up:SetShown(not e.demo and idx > 1)
        r.down:SetShown(not e.demo and idx < n)
        r.del:SetShown(not e.demo)
        r.demo:SetShown(e.demo == true)
        r.to:EnableMouse(not e.demo)
        r.to:SetScript("OnClick", function() if not e.demo then startEdit(r, idx, e) end end)
        r.up:SetScript("OnClick", function()
            local rl = LR.Rules()
            if idx > 1 then rl[idx], rl[idx - 1] = rl[idx - 1], rl[idx] f.flashIdx = idx - 1 end
            refreshAll()
        end)
        r.down:SetScript("OnClick", function()
            local rl = LR.Rules()
            if idx < #rl then rl[idx], rl[idx + 1] = rl[idx + 1], rl[idx] f.flashIdx = idx + 1 end
            refreshAll()
        end)
        r.del:SetScript("OnClick", function()
            if f.editIdx then f.editCancel = true commitEdit() end
            table.remove(LR.Rules(), idx)
            refreshAll()
        end)
        if f.flashIdx == idx and not e.demo then
            f.flashIdx = nil
            if UI.animOn() then
                r.what:SetAlpha(0.2)
                K.Tween(r.what, 0.3, function(p) r.what:SetAlpha(0.2 + 0.8 * p) end, function() r.what:SetAlpha(1) end)
            end
        end
    end)
    f.list:SetPoint("TOPLEFT", 0, -114)
    f.list.empty:SetText("")
    f.empty = UI.Empty(f, "wants", C.blue)
    f.empty:SetPoint("TOP", f.list, "TOP", 0, -20)
    f.empty.btn.isDropdown = true

    -- History: compact at the bottom, collapsible
    f.logOpen = true
    f.log = CreateFrame("Frame", nil, f)
    f.log:SetPoint("BOTTOMLEFT", 0, 0)
    f.log:SetPoint("BOTTOMRIGHT", 0, 0)
    f.log.sep = f.log:CreateTexture(nil, "ARTWORK")
    f.log.sep:SetPoint("TOPLEFT") f.log.sep:SetPoint("TOPRIGHT")
    f.log.sep:SetHeight(1)
    f.log.sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.log.head = CreateFrame("Button", nil, f.log)
    f.log.head:SetHeight(22)
    f.log.head:SetPoint("TOPLEFT", 0, -2) f.log.head:SetPoint("TOPRIGHT", 0, -2)
    f.log.head.t = line(f.log.head, 10, C.dim)
    f.log.head.t:SetPoint("LEFT", 0, 0) f.log.head.t:SetPoint("RIGHT", 0, 0)
    f.log.head:SetScript("OnClick", function()
        f.logOpen = not f.logOpen
        f.logLayout = nil
        refreshAll()
    end)
    f.log.rows = {}
    for i = 1, LOG_ROWS do
        local e = CreateFrame("Button", nil, f.log)
        e:SetHeight(LOG_ROW_H)
        e:SetPoint("TOPLEFT", 0, -24 - (i - 1) * LOG_ROW_H)
        e:SetPoint("RIGHT", f.log, "RIGHT", 0, 0)
        e.time = line(e, 10, C.dim)
        e.time:SetPoint("LEFT", 4, 0)
        e.time:SetWidth(96)
        e.link = line(e, 12, C.text)
        e.link:SetPoint("LEFT", 104, 0)
        e.link:SetPoint("RIGHT", e, "RIGHT", -4, 0)
        e:SetScript("OnEnter", function(self) if self.ilink and K.ItemTip then pcall(K.ItemTip, self, self.ilink) end end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.log.rows[i] = e
    end
    f.log.none = line(f.log, 11, C.dim)
    f.log.none:SetPoint("TOPLEFT", 4, -26)
    f.log.none:SetPoint("RIGHT", f.log, "RIGHT", 0, 0)
    f.log.none:SetText(L["Nothing handed out yet. As soon as a rule matches it shows up here."])
end

function LR.Refresh(f)
    f.on:Refresh()
    local isML = IsInGroup() and ns.LootMaster and ns.LootMaster.IsMasterLooter and ns.LootMaster.IsMasterLooter()
    if not LR.On() then
        f.ml:SetText("|cff888888" .. L["Off - nothing is handed out automatically."] .. "|r")
    elseif isML then
        f.ml:SetText("|cff66db9e" .. L["Active - you are master looter"] .. "|r")
    else
        f.ml:SetText("|cfffac257" .. L["Only works while you are master looter"] .. "|r")
    end
    -- History (computed above, because it determines the list height)
    local log = LR.log
    local demoLog = #log == 0 and demoOn()
    if demoLog then
        log = {}
        for _, d in ipairs(DEMO_LOG) do log[#log + 1] = { link = d.link, who = d.who ~= "" and d.who or ns.me(), ts = ns.now() - d.ago } end
    end
    local n = math.min(#log, LOG_ROWS)
    local lines = f.logOpen and math.max(1, n) or 0
    local logH = 26 + lines * LOG_ROW_H
    if f.logLayout ~= logH then
        f.logLayout = logH
        f.log:SetHeight(logH)
        f.list:ClearAllPoints()
        f.list:SetPoint("TOPLEFT", 0, -114)
        f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, logH + 6)
    end
    f.log.head.t:SetText(L["Recently handed out"] .. "  |cff666666" .. #log .. (f.logOpen and "  ^" or "  v") .. "|r" ..
        (demoLog and ("   |cfffac257" .. L["Demo"] .. "|r") or ""))
    for i, e in ipairs(f.log.rows) do
        local d = f.logOpen and log[i]
        e:SetShown(d and true or false)
        if d then
            e.ilink = d.link
            e.time:SetText(date("%H:%M", d.ts) .. "  " .. ns.ago(d.ts))
            e.link:SetText((d.link or "?") .. "  |cff6699ff->|r  " .. targetText(ns.isMe(d.who or "") and "" or d.who))
        end
    end
    f.log.none:SetShown(f.logOpen and n == 0)

    local rules = shownRules()
    f.list:SetData(rules)
    f.listHead:SetText(L["Your rules"] .. "  |cff888888" .. #LR.Rules() .. "|r" ..
        (#rules > 1 and ("   |cff666666" .. L["top wins"] .. "|r") or ""))
    f.list:SetAlpha(LR.On() and 1 or 0.55)
    if #rules == 0 then
        f.empty:Set(L["No rules yet"], L["Templates"], function(self)
            local list = {}
            for i, t in ipairs(TEMPLATES) do list[#list + 1] = { text = L[t.text], fn = function() f.ApplyTemplate(i) end } end
            K.ShowMenu(self, list, nil, 190)
        end)
        f.empty:Show()
    else
        f.empty:Hide()
    end
end
end)

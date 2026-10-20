-- Oasis: Guild life (0.6.527) - page with four tabs
--  * Weekly task: a shared goal for the week (leadership picks), Oasis counts progress itself from chronicle,
--    thanks and meetups - or contributions (materials for the bank). Store "wchal" (leadership) + "wccontrib" (per member)
--  * Meetups: guild meetup at a place and time (store "meets"), notice with target arrow 10 min before,
--    whoever is there is automatically marked as present (store "meetatt")
--  * Thanks & contribution: who contributed in the last 30 days (got thanks, finished orders, materials,
--    mentoring, meetups) - alphabetical, no ranking: appreciation instead of competition
--  * Yearbook: monthly page of the guild (new members, level milestones, bosses, meetups, helpers, Deathroll, graveyard)
--    to view and as text for Discord (copy window)
local ADDON, ns = ...
ns.ModuleFile("Oasis_Community", function()
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local GL = {}
ns.GuildLife = GL
local DAY, WEEK = 86400, 7 * 86400
local function short(n) return ns.displayName and ns.displayName(n) or ns.short(n) end
local function lead() return ns.isOfficer() and true or false end
local function weekStart(t)   -- Monday 00:00 (local time) of the week of t
    t = t or ns.now()
    local d = date("*t", t)
    local wd = (d.wday + 5) % 7   -- Monday = 0
    return time({ year = d.year, month = d.month, day = d.day - wd, hour = 0 })
end
GL.WeekStart = weekStart

------------------------------------------------------------------------
-- Weekly task
------------------------------------------------------------------------
GL.PRESETS = {
    { key = "levels", title = "Collect level milestones", goal = 15, desc = "Every level milestone in the chronicle counts" },
    { key = "bosses", title = "Defeat bosses together", goal = 20, desc = "Every boss in the chronicle counts" },
    { key = "thanks", title = "Help each other", goal = 25, desc = "Every thanks in the guild counts" },
    { key = "meet", title = "Join guild meetups", goal = 15, desc = "Every guild meetup attendance counts" },
    { key = "item", title = "Materials for the guild bank", goal = 200, desc = "Log donations: item and amount you put into the bank" },
}
local PBY = {}
for _, p in ipairs(GL.PRESETS) do PBY[p.key] = p end
function GL.Challenge()
    local ws = weekStart()
    local best
    for _, r in ipairs(Store.List("wchal")) do if (r.ws or 0) == ws and (not best or (r.u or 0) > (best.u or 0)) then best = r end end
    return best
end
function GL.SetChallenge(kind, goal, itemID)
    if not lead() or not PBY[kind] then return end
    local ws = weekStart()
    Store.Put("wchal", { id = "wc-" .. ws, ws = ws, kind = kind, goal = math.max(1, math.floor(tonumber(goal) or PBY[kind].goal)),
        item = tonumber(itemID) or nil, by = ns.me(), ts = ns.now() })
end
function GL.Contribute(n)
    local ch = GL.Challenge()
    if not ch or ch.kind ~= "item" then return end
    n = math.floor(tonumber(n) or 0)
    if n <= 0 or n > 1000 then return end
    local id = "wcc-" .. ch.ws .. "@" .. ns.NameKey(ns.me())
    local old = Store.Get("wccontrib", id)
    Store.Put("wccontrib", { id = id, ws = ch.ws, n = ((old and old.n) or 0) + n, by = ns.me(), ts = ns.now() })
end
-- Progress: number + who contributed ({ name = count })
function GL.Progress(ch)
    ch = ch or GL.Challenge()
    if not ch then return 0, {} end
    local from, n, who = ch.ws, 0, {}
    local function add(name, k) if name then who[name] = (who[name] or 0) + (k or 1) end n = n + (k or 1) end
    if ch.kind == "levels" or ch.kind == "bosses" then
        local kind = ch.kind == "levels" and "level" or "boss"
        for _, r in ipairs(Store.List("chronicle", function(r) return r.kind == kind and (r.ts or 0) >= from end)) do add(r.who) end
    elseif ch.kind == "thanks" then
        for _, r in ipairs(ns.Community and ns.Community.Thanks and ns.Community.Thanks(from) or {}) do add(r.by) end
    elseif ch.kind == "meet" then
        for _, r in ipairs(Store.List("meetatt", function(r) return (r.ts or 0) >= from end)) do add(r.by) end
    elseif ch.kind == "item" then
        for _, r in ipairs(Store.List("wccontrib", function(r) return r.ws == ch.ws end)) do add(r.by, tonumber(r.n) or 0) end
    end
    return n, who
end

------------------------------------------------------------------------
-- Meetups
------------------------------------------------------------------------
local function myPos()
    local map = C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player"))
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = ns.safe(x), ns.safe(y)
    if not x or x == 0 then return nil end
    return map, x, y
end
function GL.Meets(upcomingOnly)
    local now = ns.now()
    local l = Store.List("meets", function(m) return not upcomingOnly or (m.ts or 0) > now - 3600 end)
    table.sort(l, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return l
end
-- time "HH:MM" (today/tomorrow) or "DD.MM HH:MM"
local function parseTime(s)
    s = tostring(s or "")
    local d, mo, h, mi = s:match("(%d+)%.(%d+)%.?%s+(%d+):(%d+)")
    local now = date("*t")
    if d then return time({ year = now.year, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) }) end
    h, mi = s:match("(%d+):(%d+)")
    if not h then return nil end
    local t = time({ year = now.year, month = now.month, day = now.day, hour = tonumber(h), min = tonumber(mi) })
    if t < ns.now() then t = t + DAY end
    return t
end
function GL.NewMeet(title, when)
    local t = parseTime(when)
    local map, x, y = myPos()
    if not t then ns.print(L["Enter the time as HH:MM or DD.MM HH:MM"]) return end
    if not map then ns.print(L["Your position is unknown here (instance?) - go to the meeting point."]) return end
    local zone = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    Store.Put("meets", { id = ns.newId("meet"), title = tostring(title or ""):sub(1, 60), ts = t, mapID = map,
        x = math.floor(x * 10000), y = math.floor(y * 10000), zone = zone and ns.safe(zone.name) or "", by = ns.me() })
    K.Toast(L["Guild meetup created"], (title or "") .. "  ·  " .. date("%d.%m. %H:%M", t), C.mint)
end
function GL.Attendees(meetId)
    return Store.List("meetatt", function(r) return r.m == meetId end)
end
function GL.Goto(m)
    if ns.Map and ns.Map.SetTarget then ns.Map.SetTarget({ mapID = m.mapID, x = (m.x or 0) / 10000, y = (m.y or 0) / 10000, label = m.title, sub = L["Guild meetup"] }) end
end
-- notice 10 minutes before, attendance automatic (up to 40 m, -15 to +60 minutes)
local reminded = {}
local function tick()
    if not ns.loggedIn or ns.inCombat() then return end
    local now = ns.now()
    local map, x, y
    for _, m in ipairs(GL.Meets(true)) do
        local dt = (m.ts or 0) - now
        if dt > 0 and dt <= 600 and not reminded[m.id] then
            reminded[m.id] = true
            K.Toast(L["Guild meetup soon"], (m.title or "") .. "  ·  " .. (m.zone or "") .. "  ·  " .. date("%H:%M", m.ts), C.accent, function() GL.Goto(m) end)
        end
        if dt <= 900 and dt >= -3600 and not Store.Get("meetatt", m.id .. "@" .. ns.NameKey(ns.me())) then
            if not map then map, x, y = myPos() end
            if map and map == m.mapID and C_Map.GetMapWorldSize then
                local w, h = C_Map.GetMapWorldSize(map)
                local dx, dy = (x - (m.x or 0) / 10000) * (w or 0), (y - (m.y or 0) / 10000) * (h or 0)
                if (w or 0) > 0 and math.sqrt(dx * dx + dy * dy) <= 40 then
                    Store.Put("meetatt", { id = m.id .. "@" .. ns.NameKey(ns.me()), m = m.id, by = ns.me(), ts = now })
                    K.Toast(L["You're in!"], (L["You're checked in at the guild meetup %s."]):format(m.title or ""), C.mint)
                end
            end
        end
    end
end
C_Timer.NewTicker(20, function() pcall(tick) end)

------------------------------------------------------------------------
-- Thanks & contribution (30 days, no ranking)
------------------------------------------------------------------------
function GL.Contributions(days)
    local from = ns.now() - (days or 30) * DAY
    local t = {}
    local function add(name, field, k)
        if not name or name == "" then return end
        local key = ns.fullName(name)
        t[key] = t[key] or { name = key }
        t[key][field] = (t[key][field] or 0) + (k or 1)
    end
    for _, r in ipairs(ns.Community and ns.Community.Thanks and ns.Community.Thanks(from) or {}) do add(r.to, "thanks") end
    for _, o in ipairs(Store.List("orders", function(o) return o.status == "done" and o.worker and (o.u or o.created or 0) >= from end)) do
        if not ns.SameName(o.worker, o.from) then add(o.worker, "orders") end
    end
    for _, c in ipairs(Store.List("ggcontrib", function(c) return (c.u or c.ts or 0) >= from end)) do add(c.by or c.who, "mats", tonumber(c.n) or 1) end
    for _, c in ipairs(Store.List("wccontrib", function(c) return (c.ts or 0) >= from end)) do add(c.by, "mats", tonumber(c.n) or 1) end
    for _, r in ipairs(Store.List("meetatt", function(r) return (r.ts or 0) >= from end)) do add(r.by, "meets") end
    for _, r in ipairs(Store.List("mentor") or {}) do if (r.ts or r.u or 0) >= from then add(r.by, "mentor") end end
    local out = {}
    for _, e in pairs(t) do out[#out + 1] = e end
    table.sort(out, function(a, b) return ns.short(a.name):lower() < ns.short(b.name):lower() end)
    return out
end

------------------------------------------------------------------------
-- Yearbook (month)
------------------------------------------------------------------------
function GL.Month(offset)
    local d = date("*t")
    local m, y = d.month - (offset or 0), d.year
    while m < 1 do m, y = m + 12, y - 1 end
    local from = time({ year = y, month = m, day = 1, hour = 0 })
    local nm, ny = m + 1, y
    if nm > 12 then nm, ny = 1, y + 1 end
    local to = time({ year = ny, month = nm, day = 1, hour = 0 })
    local function inM(ts) return (ts or 0) >= from and (ts or 0) < to end
    local r = { y = y, m = m, joins = {}, lvl60 = {}, levels = 0, bosses = {}, nBoss = 0, meets = 0, meetPeople = 0, duels = 0, deaths = 0 }
    for _, a in ipairs(Store.List("audit")) do if inM(a.ts) and (a.kind == "join" or a.kind == "rejoin") then r.joins[#r.joins + 1] = a.a end end
    local bossSeen = {}
    for _, e in ipairs(Store.List("chronicle", function(e) return inM(e.ts) end)) do
        if e.kind == "level" then
            r.levels = r.levels + 1
            if tonumber(e.lvl or e.a1) == (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then r.lvl60[#r.lvl60 + 1] = e.who end
        elseif e.kind == "boss" then
            r.nBoss = r.nBoss + 1
            local b = e.a1 or "?"
            if not bossSeen[b] then bossSeen[b] = true r.bosses[#r.bosses + 1] = L[b] end
        end
    end
    for _, mt in ipairs(Store.List("meets", function(x) return inM(x.ts) end)) do r.meets = r.meets + 1 r.meetPeople = r.meetPeople + #GL.Attendees(mt.id) end
    r.duels = #Store.List("duels", function(x) return inM(x.ts) end)
    r.deaths = #Store.List("deaths", function(x) return inM(x.ts) end)
    local th = {}
    for _, t in ipairs(ns.Community and ns.Community.Thanks and ns.Community.Thanks(from) or {}) do if inM(t.ts) then th[t.to] = (th[t.to] or 0) + 1 end end
    local helpers = {}
    for n, c in pairs(th) do helpers[#helpers + 1] = { n = n, c = c } end
    table.sort(helpers, function(a, b) return a.c > b.c end)
    r.helpers = {}
    for i = 1, math.min(3, #helpers) do r.helpers[i] = helpers[i].n end
    return r
end
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local function names(list, max)
    local o = {}
    for i, n in ipairs(list) do if i > (max or 8) then o[#o + 1] = "+" .. (#list - (max or 8)) break end o[#o + 1] = ns.short(n) end
    return table.concat(o, ", ")
end
function GL.MonthText(r, md)
    local g = (GetGuildInfo and ns.safe(GetGuildInfo("player"))) or "Guild"
    local b = md and "**" or ""
    local lines = { (md and "## " or "") .. g .. " - " .. L[MONTHS[r.m]] .. " " .. r.y }
    local function add(k, v) if v and v ~= "" then lines[#lines + 1] = (md and "- " or "") .. b .. L[k] .. b .. ": " .. v end end
    add("New in the guild", #r.joins > 0 and (#r.joins .. "  (" .. names(r.joins) .. ")") or nil)
    add("Reached max level", #r.lvl60 > 0 and names(r.lvl60) or nil)
    add("Level milestones", r.levels > 0 and tostring(r.levels) or nil)
    add("Bosses", r.nBoss > 0 and (r.nBoss .. "  (" .. table.concat(r.bosses, ", ", 1, math.min(#r.bosses, 6)) .. ")") or nil)
    add("Guild meetup", r.meets > 0 and ((L["%d meetups, %d attended"]):format(r.meets, r.meetPeople)) or nil)
    add("Helpers of the month", #r.helpers > 0 and names(r.helpers) or nil)
    add("Deathroll", r.duels > 0 and tostring(r.duels) or nil)
    add("Graveyard", r.deaths > 0 and tostring(r.deaths) or nil)
    if #lines == 1 then lines[#lines + 1] = L["Oasis hasn't recorded anything this month yet."] end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function glass(f, a) local G = ns.Insta and ns.Insta.Glass if not (G and pcall(G, f, { 1, 1, 1, a or 0.035 }, { 1, 1, 1, 0.09 }, 10)) then K.Fill(f, { 1, 1, 1, 0.03 }) end end
local tab, monthOff = "week", 0
local copyBox
local function showCopy(text)
    if not copyBox then
        local f = CreateFrame("Frame", "OasisYearbookCopy", UIParent)
        f:SetSize(520, 320) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG")
        glass(f, 0.97)
        K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
        local t = K.Title(f, 14, C.text) t:SetPoint("TOPLEFT", 16, -14) t:SetText(L["Text for Discord - Ctrl+C to copy"])
        local x = K.CloseButton(f, function() f:Hide() end) x:SetPoint("TOPRIGHT", -6, -6)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -42) sf:SetPoint("BOTTOMRIGHT", -34, 16)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true) eb:SetAutoFocus(true) eb:SetFontObject(ChatFontNormal) eb:SetWidth(460)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        if ns.EscClose then ns.EscClose("OasisYearbookCopy") end
        copyBox = f
    end
    copyBox.eb:SetText(text)
    copyBox.eb:HighlightText()
    copyBox:Show()
end
StaticPopupDialogs["OASIS_MEET_NEW"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 80,
    OnAccept = function(self) local eb = self.editBox or self.EditBox local t = eb and eb:GetText() or ""
        local when, title = t:match("^%s*([%d%.]*%s*%d+:%d+)%s*(.*)$")
        GL.NewMeet((title and title ~= "") and title or L["Guild meetup"], when) ns.RefreshPage("guildlife") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["OASIS_WC_GIVE"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 5,
    OnAccept = function(self) local eb = self.editBox or self.EditBox GL.Contribute(eb and eb:GetText()) ns.RefreshPage("guildlife") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["OASIS_WC_ITEM"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 120,
    OnAccept = function(self) local eb = self.editBox or self.EditBox local t = eb and eb:GetText() or ""
        local id = ns.itemID and ns.itemID(t)
        local goal = tonumber(t:match("(%d+)%s*$"))
        GL.SetChallenge("item", goal or 200, id) ns.RefreshPage("guildlife") end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function buildWeek(a)
    a.title = K.Title(a, 18, C.text) a.title:SetPoint("TOPLEFT", 4, -6) a.title:SetPoint("RIGHT", -4, 0)
    a.desc = K.Text(a, 12, C.muted) a.desc:SetPoint("TOPLEFT", a.title, "BOTTOMLEFT", 0, -6) a.desc:SetPoint("RIGHT", -4, 0) a.desc:SetJustifyH("LEFT")
    a.bar = K.Bar(a, 500, 10) a.bar:SetPoint("TOPLEFT", 4, -70) a.bar:SetPoint("RIGHT", -120, 0)
    a.num = K.Title(a, 16, C.text, "RIGHT") a.num:SetPoint("LEFT", a.bar, "RIGHT", 10, 0) a.num:SetPoint("RIGHT", -4, 0)
    a.who = K.Text(a, 12, C.text) a.who:SetPoint("TOPLEFT", 4, -96) a.who:SetPoint("RIGHT", -4, 0) a.who:SetJustifyH("LEFT") a.who:SetWordWrap(true)
    a.give = K.Button(a, L["Log a donation"], 150, 24, nil, function() StaticPopup_Show("OASIS_WC_GIVE", L["How many did you put into the guild bank?"]) end)
    a.give:SetPoint("TOPLEFT", 4, -150)
    a.pick = K.Button(a, L["Choose this week's goal"], 210, 24, "ghost", function(self)
        local items = {}
        for _, p in ipairs(GL.PRESETS) do
            items[#items + 1] = { text = L[p.title] .. "  |cff888888(" .. p.goal .. ")|r", fn = function()
                if p.key == "item" then StaticPopup_Show("OASIS_WC_ITEM", L["Item (link or name) and target amount, e.g. '[Copper Ore] 200'"])
                else GL.SetChallenge(p.key, p.goal) ns.RefreshPage("guildlife") end
            end }
        end
        K.ShowMenu(self, items, L["Goal of the week"])
    end)
    a.pick:SetPoint("BOTTOMLEFT", 4, 4)
end
local function refreshWeek(a)
    local ch = GL.Challenge()
    a.pick:SetShown(lead())
    if not ch then
        a.title:SetText(L["No weekly goal yet"])
        a.desc:SetText(lead() and L["Pick a goal below - the whole guild sees the progress."] or L["The leadership picks a shared goal every week."])
        a.bar:Hide() a.num:SetText("") a.who:SetText("") a.give:Hide()
        return
    end
    local p = PBY[ch.kind] or {}
    local title = L[p.title or "?"]
    if ch.kind == "item" and ch.item then
        local nm = C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(ch.item))
        if nm then title = title .. ": " .. nm end
    end
    a.title:SetText(title)
    a.desc:SetText(L[p.desc or ""] .. "  ·  " .. (L["until Sunday, target %d"]):format(ch.goal))
    local n, who = GL.Progress(ch)
    a.bar:Show() a.bar:Set(n / math.max(1, ch.goal))
    a.num:SetText(n .. " / " .. ch.goal .. (n >= ch.goal and ("  |cff66db9e" .. L["done!"] .. "|r") or ""))
    local list = {}
    for name, k in pairs(who) do list[#list + 1] = short(name) .. " |cff888888" .. k .. "|r" end
    table.sort(list)
    a.who:SetText(#list > 0 and (L["Taking part: "] .. table.concat(list, ", ")) or L["Nobody has contributed yet - be the first!"])
    a.give:SetShown(ch.kind == "item")
end

local function buildMeets(a)
    a.new = K.Button(a, L["Create meetup here"], 170, 24, nil, function() StaticPopup_Show("OASIS_MEET_NEW", L["Time and title, e.g. '20:30 Campfire at the Crossroads' - the place is your position"]) end)
    a.new:SetPoint("TOPLEFT", 0, 0)
    a.info = K.Text(a, 11, C.muted) a.info:SetPoint("LEFT", a.new, "RIGHT", 12, 0) a.info:SetPoint("RIGHT", -4, 0) a.info:SetWordWrap(false)
    a.info:SetText(L["10 minutes before, a reminder with a waypoint arrow appears. Whoever is there is checked in automatically."])
    a.list = K.List(a, 52, function(l)
        local r = K.Row(l)
        r.t = K.Text(r, 13, C.text) r.t:SetPoint("TOPLEFT", 12, -8) r.t:SetPoint("RIGHT", -150, 0) r.t:SetWordWrap(false)
        r.s = K.Text(r, 11, C.muted) r.s:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -4) r.s:SetPoint("RIGHT", -150, 0) r.s:SetWordWrap(false)
        r.go = K.Button(r, L["Set waypoint"], 110, 22, "ghost", function() if r.item then GL.Goto(r.item) end end)
        r.go:SetPoint("RIGHT", -8, 0)
        return r
    end, function(r, m)
        local att = GL.Attendees(m.id)
        local ppl = {}
        for i, x in ipairs(att) do if i <= 10 then ppl[#ppl + 1] = short(x.by) end end
        r.t:SetText((m.title or "") .. "  |cff888888" .. date("%a %d.%m. %H:%M", m.ts or 0) .. "|r")
        r.s:SetText((m.zone or "") .. "  ·  " .. L["from"] .. " " .. short(m.by or "?") .. (#att > 0 and ("  ·  " .. #att .. " " .. L["attended"] .. ": " .. table.concat(ppl, ", ")) or ""))
    end)
    a.list:SetPoint("TOPLEFT", 0, -34) a.list:SetPoint("BOTTOMRIGHT", 0, 0)
    glass(a.list, 0.025)
end
local function refreshMeets(a)
    local now = ns.now()
    local l = {}
    for _, m in ipairs(GL.Meets(false)) do if (m.ts or 0) > now - 14 * DAY then l[#l + 1] = m end end
    table.sort(l, function(x, y) return (x.ts or 0) > (y.ts or 0) end)
    a.list:SetData(l)
    a.list.empty:SetText(#l == 0 and L["No guild meetups yet. A campfire, a duel night, a group photo - just create one!"] or "")
end

local function buildThanks(a)
    a.info = K.Text(a, 12, C.muted) a.info:SetPoint("TOPLEFT", 4, -2) a.info:SetPoint("RIGHT", -4, 0) a.info:SetJustifyH("LEFT") a.info:SetWordWrap(true)
    a.info:SetText(L["Who did something for others in the last 30 days - alphabetical, no ranking. Thank you!"])
    a.list = K.List(a, 30, function(l)
        local r = K.Row(l)
        r.n = K.Text(r, 13, C.text) r.n:SetPoint("LEFT", 12, 0) r.n:SetWidth(180)
        r.d = K.Text(r, 11, C.muted) r.d:SetPoint("LEFT", 200, 0) r.d:SetPoint("RIGHT", -12, 0) r.d:SetWordWrap(false)
        return r
    end, function(r, e)
        local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[e.name]
        local cr, cg, cb = ns.classColor(m and m.class)
        r.n:SetText(short(e.name)) r.n:SetTextColor(cr or 1, cg or 1, cb or 1)
        local p = {}
        if (e.thanks or 0) > 0 then p[#p + 1] = (L["%d x thanks"]):format(e.thanks) end
        if (e.orders or 0) > 0 then p[#p + 1] = (L["%d orders crafted"]):format(e.orders) end
        if (e.mats or 0) > 0 then p[#p + 1] = (L["%d materials donated"]):format(e.mats) end
        if (e.meets or 0) > 0 then p[#p + 1] = (L["%d x at meetups"]):format(e.meets) end
        if (e.mentor or 0) > 0 then p[#p + 1] = L["Mentor"] end
        r.d:SetText(table.concat(p, "  ·  "))
    end)
    a.list:SetPoint("TOPLEFT", 0, -40) a.list:SetPoint("BOTTOMRIGHT", 0, 0)
    glass(a.list, 0.025)
end
local function refreshThanks(a)
    local l = GL.Contributions(30)
    a.list:SetData(l)
    a.list.empty:SetText(#l == 0 and L["Nothing yet - say thanks in the members' right-click menu."] or "")
end

local function buildBook(a)
    a.prev = K.Button(a, "<", 30, 24, "ghost", function() monthOff = math.min(11, monthOff + 1) ns.RefreshPage("guildlife") end)
    a.prev:SetPoint("TOPLEFT", 0, 0)
    a.next = K.Button(a, ">", 30, 24, "ghost", function() monthOff = math.max(0, monthOff - 1) ns.RefreshPage("guildlife") end)
    a.next:SetPoint("LEFT", a.prev, "RIGHT", 4, 0)
    a.copy = K.Button(a, L["Copy for Discord"], 170, 24, "ghost", function() showCopy(GL.MonthText(GL.Month(monthOff), true)) end)
    a.copy:SetPoint("TOPRIGHT", 0, 0)
    a.post = K.Button(a, L["Short note to guild chat"], 170, 24, "ghost", function()
        local r = GL.Month(monthOff)
        local msg = (L["Oasis yearbook %s: %d new members, %d bosses, %d guild meetups"]):format(L[MONTHS[r.m]], #r.joins, r.nBoss, r.meets)
        if #r.helpers > 0 then msg = msg .. " - " .. L["Helpers of the month"] .. ": " .. names(r.helpers) end
        ns.OfferChat(L["Yearbook"], msg, "GUILD")
    end)
    a.post:SetPoint("RIGHT", a.copy, "LEFT", -6, 0)
    a.page = CreateFrame("Frame", nil, a)
    a.page:SetPoint("TOPLEFT", 0, -34) a.page:SetPoint("BOTTOMRIGHT", 0, 0)
    glass(a.page, 0.035)
    a.text = K.Text(a.page, 13, C.text) a.text:SetPoint("TOPLEFT", 20, -18) a.text:SetPoint("RIGHT", -20, 0)
    a.text:SetJustifyH("LEFT") a.text:SetSpacing(7) a.text:SetWordWrap(true)
end
local function refreshBook(a)
    local r = GL.Month(monthOff)
    local t = GL.MonthText(r, false)
    t = t:gsub("^([^\n]+)", "|cffe8b44a%1|r")
    a.text:SetText(t)
    a.next:SetEnabled(monthOff > 0)
end

local TABS = {
    { key = "week", text = "Weekly goal", build = buildWeek, refresh = refreshWeek },
    { key = "meets", text = "Meetups", build = buildMeets, refresh = refreshMeets },
    { key = "thanks", text = "Thanks & contribution", build = buildThanks, refresh = refreshThanks },
    { key = "book", text = "Yearbook", build = buildBook, refresh = refreshBook },
}
ns.ICONS.guildlife = ns.MEDIA .. "icons\\heart"
ns.RegisterPage({
    key = "guildlife", title = "Guild life", order = 3.45,
    sub = "Weekly goal, guild meetups, thanks and the guild yearbook",
    build = function(p)
        local items = {}
        for _, t in ipairs(TABS) do items[#items + 1] = { key = t.key, text = L[t.text] } end
        p.seg = K.Segments(p, items, function(k) tab = k for _, t in ipairs(TABS) do t.area:SetShown(t.key == k) end ns.RefreshPage("guildlife", true) end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        for _, t in ipairs(TABS) do
            t.area = CreateFrame("Frame", nil, p)
            t.area:SetPoint("TOPLEFT", 0, -36) t.area:SetPoint("BOTTOMRIGHT", 0, 0)
            local ok, e = pcall(t.build, t.area)
            if not ok then ns.err("Gildenleben " .. t.key, e) end
            t.area:SetShown(t.key == tab)
        end
        p.seg:Select(tab)
    end,
    refresh = function(p)
        for _, t in ipairs(TABS) do
            if t.key == tab then local ok, e = pcall(t.refresh, t.area) if not ok then ns.err("Gildenleben " .. t.key, e) end end
        end
    end,
})
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "guild" then
        local has = false
        for _, k in ipairs(g.pages) do if k == "guildlife" then has = true end end
        if not has then table.insert(g.pages, 3, "guildlife") end
    end
end
ns.slash.treffen = function(arg) if arg and arg ~= "" then local when, title = arg:match("^%s*([%d%.]*%s*%d+:%d+)%s*(.*)$") GL.NewMeet((title and title ~= "") and title or L["Guild meetup"], when) else StaticPopup_Show("OASIS_MEET_NEW", L["Time and title, e.g. '20:30 Campfire at the Crossroads' - the place is your position"]) end end
ns.slash.jahrbuch = function() tab = "book" if ns.Expand then ns.Expand("guildlife") else ns.ShowPage("guildlife") end end

end)

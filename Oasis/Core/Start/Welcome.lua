-- Oasis: accompanying newcomers
-- Guild: notice "Neu in der Gilde - Willkommen sagen". Newcomer: welcome window with contact persons.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
-- Security on receive (other players' addon messages may be manipulated):
-- Sanitize strings, limit numbers, check names, throttle floods
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape sequences (|c |r |n |H |T |K |A ...) and control characters neutralized; links: valid item/spell links stay
    function SEC.Text(s, max, links)
        if s == nil then return "" end
        s = tostring(s):gsub("[%z\1-\31\127]", " ")
        local keep
        if links then
            keep = {}
            s = s:gsub("(|c([^|]-)|H(%a+):([^|]*)|h(%[[^|%]]*%])|h|r)", function(all, col, kind, data)
                if #keep < 8 and (kind == "item" or kind == "spell") and data:match("^[%d:%-]+$")
                    and (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then
                    keep[#keep + 1] = all
                    return "\1" .. #keep .. "\2"
                end
            end)
        end
        s = cut((s:gsub("|", "/")), max)
        if keep then s = s:gsub("\1%d*$", ""):gsub("\1(%d+)\2", function(i) return keep[tonumber(i)] or "" end) end
        return s
    end
    function SEC.Link(s)
        if type(s) ~= "string" or #s > 300 then return nil end
        local col = s:match("^|c([^|]-)|Hitem:[%d:%-]+|h%[[^|%]]*%]|h|r$")
        if not col or not (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then return nil end
        return s
    end
    function SEC.Num(v, lo, hi, int)
        v = tonumber(v)
        if not v or v ~= v or v < lo or v > hi then return nil end
        if int then v = math.floor(v) end
        return v
    end
    function SEC.Name(s)
        if type(s) ~= "string" or s == "" or #s > 64 or s:find("[|%c]") then return nil end
        return s
    end
    local last, lastN = {}, 0
    function SEC.Rate(key, sec)
        local now = GetTime()
        local t = last[key]
        if t and now - t < sec then return false end
        if not t then lastN = lastN + 1 if lastN > 500 then last, lastN = {}, 0 end end
        last[key] = now
        return true
    end
end

local Welcome = {}
ns.Welcome = Welcome
local NEW_DAYS = 14

------------------------------------------------------------------------
-- Who is new? (join in the chronicle within the last 14 days)
------------------------------------------------------------------------
function Welcome.JoinedAt(name)
    local best
    for _, e in ipairs(Store.List("chronicle", function(e) return e.kind == "guild" and e.who == name end)) do
        if ns.IsJoinTk(e.tk) then best = math.max(best or 0, e.ts or 0) end
    end
    return best
end
function Welcome.IsNew(name)
    -- only the guild join counts; Blizzard's newcomer flag (p.nc) stays for weeks -> not as NEW
    local t = Welcome.JoinedAt(name)
    return t and (ns.now() - t) < ((ns.db and ns.db.settings.newDays) or NEW_DAYS) * 86400
end

-- Notice to the guild when someone joins
local greeted = {}
ns.GuildOption({ page = "radar", key = "wlToast", default = true, label = "Announce new members",
    desc = "Notice with click-to-welcome when someone joins the guild" })
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "chronicle" or old or rec.del or rec.kind ~= "guild" then return end
    if not ns.IsJoinTk(rec.tk) or (ns.now() - (rec.ts or 0)) > 600 or ns.isMe(rec.who) then return end
    if greeted[rec.who] or ns.GuildOpt("wlToast") == false then return end
    -- Any member can write chronicle entries: only greet real names from the guild roster
    if not SEC.Name(rec.who) then return end
    if ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(rec.who) ~= true then return end
    greeted[rec.who] = true
    ns.Sound.Next("welcome")
    K.Toast((L["New in the guild: %s"]):format(ns.displayName(rec.who)), L["Click: say welcome in guild chat"], C.mint, function()
        ns.SendChat((L["Welcome to the guild, %s!"]):format(ns.displayName(rec.who)), "GUILD")
        if ns.Badges then ns.Badges.Add("gz", 1) end
        if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("gz", rec.who) end
    end)
end)

------------------------------------------------------------------------
-- Welcome window for the newcomer
-- Layout: header (logo, title) | 3 numbers | contact cards | level range | what's happening | first steps
-- Preview with sample data: /oa willkommen test  (nothing is sent)
------------------------------------------------------------------------
local W, H = 560, 610
local PAD = 20
local win

-- Sample data for the preview
local DUMMY = {
    guild = "Oasis", total = 87, preview = true,
    online = {
        { name = "Durotan", level = 60, class = "WARRIOR", rank = "Guild Master", rankIndex = 0 },
        { name = "Lyssandra", level = 60, class = "PRIEST", rank = "Officer", rankIndex = 1 },
        { name = "Brummbart", level = 58, class = "HUNTER", rank = "Officer", rankIndex = 1 },
        { name = "Zul'kira", level = 22, class = "MAGE", rank = "Member", rankIndex = 3 },
        { name = "Feuerfaust", level = 19, class = "SHAMAN", rank = "Member", rankIndex = 3 },
        { name = "Nachtschatten", level = 24, class = "ROGUE", rank = "Member", rankIndex = 3 },
        { name = "Eichenherz", level = 41, class = "DRUID", rank = "Veteran", rankIndex = 2 },
        { name = "Morgana", level = 35, class = "WARLOCK", rank = "Member", rankIndex = 3 },
        { name = "Silberhand", level = 60, class = "PALADIN", rank = "Veteran", rankIndex = 2 },
    },
    myLevel = 21,
    next = { "Next event: Molten Core, Friday, 20:00", "3 open group searches", "1 running poll" },
    events = 2, oasis = 23,
    motd = "Raids Mi + So 20 Uhr. Fragen? Einfach einen Offizier anfluestern!",
}

-- real data from guild roster, events, groups, polls
local function collect()
    local R = ns.Radar
    local d = { guild = IsInGuild() and (GetGuildInfo("player")) or "Oasis", online = {}, total = 0, next = {}, events = 0 }
    d.myLevel = ns.safe(UnitLevel("player")) or 1
    for _, m in ipairs(R and R.roster or {}) do
        d.total = d.total + 1
        if m.online and not ns.isMe(m.name) then d.online[#d.online + 1] = m end
    end
    local evs = ns.Raid and ns.Raid.Events() or {}
    local week = ns.now() + 7 * 86400
    for _, ev in ipairs(evs) do if (ev.ts or 0) < week then d.events = d.events + 1 end end
    if evs[1] then d.next[#d.next + 1] = (L["Next event: %s"]):format((evs[1].title or "?") .. ", " .. ns.fmtWhen(evs[1].ts)) end
    local lfg = ns.Groups and #ns.Groups.Active() or 0
    if lfg > 0 then d.next[#d.next + 1] = (L["%d open group searches"]):format(lfg) end
    local polls = 0
    if ns.Polls then for _, p in ipairs(ns.Polls.All()) do if ns.Polls.IsOpen(p) then polls = polls + 1 end end end
    if polls > 0 then d.next[#d.next + 1] = (L["%d open polls"]):format(polls) end
    d.oasis = R and R.withAddon or 0
    d.motd = ns.GuildInfo and ns.GuildInfo.MOTD and ns.GuildInfo.MOTD() or ""
    return d
end

-- Contact persons (officers, otherwise highest rank) and fellow players in your own level range
local function split(d)
    local online, contacts, peers = {}, {}, {}
    for _, m in ipairs(d.online) do online[#online + 1] = m end
    table.sort(online, function(a, b) return (a.rankIndex or 99) < (b.rankIndex or 99) end)
    for _, m in ipairs(online) do
        if #contacts < 3 and (m.rankIndex or 99) <= 1 then contacts[#contacts + 1] = m end
    end
    for _, m in ipairs(online) do if #contacts < 3 and not tContains(contacts, m) then contacts[#contacts + 1] = m end end
    for _, m in ipairs(online) do
        if math.abs((m.level or 0) - d.myLevel) <= 4 then peers[#peers + 1] = m end
    end
    table.sort(peers, function(a, b) return math.abs(a.level - d.myLevel) < math.abs(b.level - d.myLevel) end)
    return contacts, peers
end

local function colored(m) return ns.colorName(m.name, m.class) end
local function whisper(m)
    if win and win.data and win.data.preview then ns.print(L["Preview: "] .. "/w " .. ns.short(m.name)) return end
    ns.Whisper(m.name)
end

-- Number tile
local function statTile(parent, color, label)
    local t = K.Panel(parent, C.panel)
    t:SetHeight(58)
    t.edge = t:CreateTexture(nil, "ARTWORK")
    t.edge:SetPoint("TOPLEFT")
    t.edge:SetPoint("TOPRIGHT")
    t.edge:SetHeight(2)
    t.edge:SetColorTexture(color[1], color[2], color[3], 1)
    t.value = K.Title(t, 22, C.text)
    t.value:SetPoint("TOPLEFT", 12, -12)
    t.label = K.Text(t, 11, C.muted)
    t.label:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -3)
    t.label:SetText(label)
    return t
end

-- Card for a contact person: class color on the left, name, rank + level, click = whisper
local function contactCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(60)
    c.bg = K.Fill(c, C.raised)
    K.Border(c, C.line)
    c.bar = c:CreateTexture(nil, "ARTWORK")
    c.bar:SetPoint("TOPLEFT")
    c.bar:SetPoint("BOTTOMLEFT")
    c.bar:SetWidth(3)
    c.name = K.Text(c, 13, C.text)
    c.name:SetPoint("TOPLEFT", 12, -10)
    c.name:SetPoint("RIGHT", -8, 0)
    c.rank = K.Text(c, 11, C.muted)
    c.rank:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.act = K.Text(c, 10, C.dim)
    c.act:SetPoint("BOTTOMLEFT", 12, 8)
    c.act:SetText(L["Click: whisper"])
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:SetScript("OnEnter", function(self)
        K.SetBorderColor(self, C.accent2)
        self.act:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    c:SetScript("OnLeave", function(self)
        K.SetBorderColor(self, C.line)
        self.act:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end)
    c:SetScript("OnClick", function(self, btn)
        if not self.m then return end
        if btn == "RightButton" and ns.Profile and not (win.data and win.data.preview) then ns.Profile.Show(self.m.name) return end
        whisper(self.m)
    end)
    function c:Set(m)
        self.m = m
        if not m then self:Hide() return end
        local r, g, b = ns.classColor(m.class)
        self.bar:SetColorTexture(r, g, b, 1)
        self.name:SetText(colored(m))
        self.rank:SetText((m.rank ~= "" and m.rank or "?") .. "  ·  " .. (L["Level %d"]):format(m.level or 0))
        self:Show()
    end
    return c
end

-- Step tile: number in a circle, text, check mark when done
local STEPS = {
    { key = "hello", text = "Say hello", sub = "Say hi in guild chat" },
    { key = "profile", text = "Create profile", sub = "Class, role, what you're looking for", page = "insta" },
    { key = "group", text = "Find a group", sub = "Partners for quests & dungeons", page = "groups" },
}
local function stepTile(parent, i, step, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(54)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    b.circle = b:CreateTexture(nil, "ARTWORK")
    b.circle:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    b.circle:SetSize(24, 24)
    b.circle:SetPoint("LEFT", 10, 0)
    b.num = K.Title(b, 12, C.text, "CENTER")
    K.CenterNum(b.num, b.circle, "CENTER", 0, 0)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.check:SetSize(22, 22)
    b.check:SetPoint("CENTER", b.circle, "CENTER", 1, 0)
    b.text = K.Text(b, 12, C.text)
    b.text:SetPoint("TOPLEFT", b.circle, "TOPRIGHT", 9, 1)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetText(L[step.text])
    b.sub = K.Text(b, 10, C.muted)
    b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -3)
    b.sub:SetPoint("RIGHT", -6, 0)
    b.sub:SetText(L[step.sub])
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.04)
    function b:SetDone(done)
        local c = done and C.mint or C.accent2
        self.circle:SetVertexColor(c[1], c[2], c[3])
        self.num:SetText(done and "" or tostring(i))
        self.check:SetShown(done)
        self.text:SetTextColor((done and C.muted or C.text)[1], (done and C.muted or C.text)[2], (done and C.muted or C.text)[3])
    end
    b:SetScript("OnClick", function(self) onClick(self, step) end)
    return b
end

local function build()
    local f = CreateFrame("Frame", "OasisWelcome", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    ns.EscClose("OasisWelcome")

    -- Header: accent gradient, logo, small badge, title, subtitle
    local head = f:CreateTexture(nil, "BORDER")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(104)
    if not K.Gradient(head, "VERTICAL", { 0, 0, 0, 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.16 }) then head:Hide() end
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.MEDIA .. "logo256")
    logo:SetSize(68, 68)
    logo:SetPoint("TOPLEFT", PAD, -20)
    f.logo = logo
    f.tag = K.Text(f, 10, C.accent)
    f.tag:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -4)
    f.tag:SetText(K.Upper(L["New in the guild"]))
    f.title = K.Title(f, 22, C.text)
    f.title:SetPoint("TOPLEFT", f.tag, "BOTTOMLEFT", 0, -5)
    f.title:SetPoint("RIGHT", -44, 0)
    f.subtitle = K.Text(f, 12, C.muted)
    f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.subtitle:SetPoint("RIGHT", -44, 0)
    f.subtitle:SetWordWrap(true)
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    -- Preview marker
    f.preview = K.Panel(f, { C.amber[1] * 0.22, C.amber[2] * 0.22, C.amber[3] * 0.22, 1 })
    K.SetBorderColor(f.preview, C.amber)
    f.preview:SetSize(76, 18)
    f.preview:SetPoint("RIGHT", close, "LEFT", -8, 0)
    f.preview.t = K.Text(f.preview, 10, C.amber, "CENTER")
    f.preview.t:SetPoint("CENTER")
    f.preview.t:SetText(K.Upper(L["Preview"]))
    local d = K.Divider(f)
    d:SetPoint("TOPLEFT", PAD, -104)
    d:SetPoint("TOPRIGHT", -PAD, -104)

    -- three numbers
    local tw = (W - 2 * PAD - 2 * 10) / 3
    f.stOnline = statTile(f, C.mint, L["online now"])
    f.stTotal = statTile(f, C.accent, L["Members"])
    f.stEvents = statTile(f, C.amber, L["Events this week"])
    for i, t in ipairs({ f.stOnline, f.stTotal, f.stEvents }) do
        t:SetWidth(tw)
        t:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + 10), -118)
    end

    -- Contact persons
    local h1 = K.GameHead(f, L["Who to ask"], C.accent)
    h1:SetPoint("TOPLEFT", PAD, -192)
    h1:SetPoint("RIGHT", -PAD, 0)
    f.h1 = h1
    f.cards = {}
    for i = 1, 3 do
        local c = contactCard(f)
        c:SetWidth(tw)
        c:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + 10), -216)
        f.cards[i] = c
    end
    f.noContacts = K.Text(f, 12, C.dim)
    f.noContacts:SetPoint("TOPLEFT", PAD + 2, -222)
    f.noContacts:SetText(L["Nobody is online right now - check back later."])

    -- Guild message (MOTD) - for newcomers usually the most important (rules, Discord, raid times)
    f.hm = K.GameHead(f, L["Guild message"], C.blue)
    f.hm:SetPoint("RIGHT", -PAD, 0)
    f.motd = K.Text(f, 12, C.text)
    f.motd:SetPoint("RIGHT", -PAD, 0)
    f.motd:SetWordWrap(true)
    f.motd:SetJustifyV("TOP")
    f.motd:SetSpacing(3)

    -- Level range
    local h2 = K.GameHead(f, L["Around your level"], C.mint)
    h2:SetPoint("TOPLEFT", PAD, -294)
    h2:SetPoint("RIGHT", -PAD, 0)
    f.h2 = h2
    f.peers = K.Text(f, 12, C.text)
    f.peers:SetPoint("TOPLEFT", PAD + 2, -318)
    f.peers:SetPoint("RIGHT", -PAD, 0)
    f.peers:SetWordWrap(true)
    f.peers:SetJustifyV("TOP")

    -- What's happening right now
    local h3 = K.GameHead(f, L["Going on right now"], C.amber)
    f.h3 = h3
    h3:SetPoint("TOPLEFT", PAD, -356)
    h3:SetPoint("RIGHT", -PAD, 0)
    f.next = K.Text(f, 12, C.text)
    f.next:SetPoint("TOPLEFT", PAD + 2, -380)
    f.next:SetPoint("RIGHT", -PAD, 0)
    f.next:SetWordWrap(true)
    f.next:SetJustifyV("TOP")
    f.next:SetSpacing(4)

    -- First steps
    local h4 = K.GameHead(f, L["First steps"], C.pink)
    h4:SetPoint("TOPLEFT", PAD, -448)
    h4:SetPoint("RIGHT", -PAD, 0)
    f.h4 = h4
    f.steps = {}
    for i, st in ipairs(STEPS) do
        local b = stepTile(f, i, st, function(self, step) Welcome.DoStep(step) end)
        b:SetWidth(tw)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (tw + 10), -472)
        f.steps[i] = b
    end

    -- Footer
    local fd = K.Divider(f)
    fd:SetPoint("BOTTOMLEFT", PAD, 58)
    fd:SetPoint("BOTTOMRIGHT", -PAD, 58)
    f.open = K.Button(f, L["Open Oasis"], 140, 28, "primary", function()
        f:Hide()
        ns.ShowPage("home")
    end)
    f.open:SetPoint("BOTTOMLEFT", PAD, 18)
    f.later = K.Button(f, L["Later"], 100, 28, "ghost", function() f:Hide() end)
    f.later:SetPoint("LEFT", f.open, "RIGHT", 8, 0)
    -- old button name stays as reference (DoStep/Refresh use it)
    f.hello = { SetEnabledState = function() end }
    f.hint = K.Text(f, 10, C.dim, "RIGHT")
    f.hint:SetPoint("BOTTOMRIGHT", -PAD, 26)
    f.hint:SetText(L["Reopen: /oa welcome"])
    win = f
    return f
end

local function stepsDone()
    ns.char.welcomeSteps = ns.char.welcomeSteps or {}
    return ns.char.welcomeSteps
end
function Welcome.DoStep(step)
    local f = win
    local preview = f and f.data and f.data.preview
    if step.key == "hello" then
        if preview then
            ns.print(L["Preview: "] .. L["Hi everyone! I am new to the guild."])
        else
            ns.SendChat(L["Hi everyone! I am new to the guild."], "GUILD")
        end
        f.hello:SetEnabledState(false)
    elseif step.page then
        f:Hide()
        ns.ShowPage(step.page)
    end
    if not preview then stepsDone()[step.key] = true end
    if f.done then f.done[step.key] = true end
    Welcome.Refresh()
end

function Welcome.Refresh()
    local f, dd = win, win and win.data
    if not dd then return end
    local contacts, peers = split(dd)
    f.title:SetText((L["Welcome to %s!"]):format(dd.guild or "Oasis"))
    f.subtitle:SetText(L["Great to have you. Here is who can help you out."])
    f.preview:SetShown(dd.preview and true or false)
    f.stOnline.value:SetText(#dd.online)
    f.stTotal.value:SetText(dd.total > 0 and dd.total or "-")
    -- "0 events this week" is off-putting -> then rather show how many use Oasis
    if (dd.events or 0) > 0 then
        f.stEvents.value:SetText(dd.events)
        f.stEvents.label:SetText(L["Events this week"])
    else
        f.stEvents.value:SetText(dd.oasis or 0)
        f.stEvents.label:SetText(L["use Oasis"])
    end
    for i, c in ipairs(f.cards) do c:Set(contacts[i]) end
    f.noContacts:SetShown(#contacts == 0)
    local t = {}
    for i = 1, math.min(8, #peers) do t[#t + 1] = colored(peers[i]) .. " |cff777777" .. peers[i].level .. "|r" end
    if #peers > 8 then t[#t + 1] = "|cff777777+" .. (#peers - 8) .. "|r" end
    f.peers:SetText(table.concat(t, "   "))
    f.h2:SetCount(#peers > 0 and #peers or nil)
    local nx = {}
    for _, line in ipairs(dd.next) do nx[#nx + 1] = "|cffffd24a•|r  " .. L[line] end
    f.next:SetText(table.concat(nx, "\n"))
    local motd = tostring(dd.motd or ""):gsub("^%s+", ""):gsub("%s+$", "")
    f.motd:SetText(motd)
    -- Sections stacked; empty ones ("nobody right now", "nothing planned") are dropped, the window gets shorter
    local y = -294
    local function section(head, body, show, bodyH)
        head:SetShown(show) body:SetShown(show)
        if not show then return end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", PAD, y)
        head:SetPoint("RIGHT", -PAD, 0)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", PAD + 2, y - 24)
        body:SetPoint("RIGHT", -PAD, 0)
        y = y - 24 - bodyH - 14
    end
    local function textH(fs, min) local h = fs:GetStringHeight() or 0 return math.max(min or 16, h) end
    section(f.hm, f.motd, motd ~= "", textH(f.motd, 16))
    section(f.h2, f.peers, #peers > 0, textH(f.peers, 16))
    section(f.h3, f.next, #nx > 0, textH(f.next, 16))
    f.h4:ClearAllPoints()
    f.h4:SetPoint("TOPLEFT", PAD, y)
    f.h4:SetPoint("RIGHT", -PAD, 0)
    for i, b in ipairs(f.steps) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (b:GetWidth() + 10), y - 24)
    end
    f:SetHeight(-(y - 24 - 54) + 78)
    local n = 0
    for i, st in ipairs(STEPS) do
        local done = f.done[st.key] and true or false
        if done then n = n + 1 end
        f.steps[i]:SetDone(done)
    end
    f.h4:SetCount(n .. "/" .. #STEPS)
    f.hello:SetEnabledState(not f.done.hello and (dd.preview or IsInGuild()))
end

-- preview = true: sample data, nothing is sent or saved
function Welcome.Show(preview)
    local f = win or build()
    f.data = preview and DUMMY or collect()
    f.done = {}
    if not preview then for k, v in pairs(stepsDone()) do f.done[k] = v end end
    Welcome.Refresh()
    f:Show()
    K.FadeIn(f, 0)
end
local function slash(arg)
    arg = (arg or ""):lower()
    Welcome.Show(arg == "test" or arg == "demo" or arg == "vorschau")
end
ns.slash.willkommen = slash
ns.slash.welcome = slash
------------------------------------------------------------------------
-- When to show: freshly joined (in this session) or new according to the chronicle,
-- and not yet shown for this guild
------------------------------------------------------------------------
local wasInGuild
local function maybeShow(force)
    if not IsInGuild() then return end
    local gname = GetGuildInfo("player")
    if not gname then return end
    ns.char.welcomed = ns.char.welcomed or {}
    if ns.char.welcomed[gname] then return end
    if force or Welcome.IsNew(ns.me()) then
        ns.char.welcomed[gname] = ns.now()
        ns.After(2, Welcome.Show)
    end
end
ns.On("PLAYER_GUILD_UPDATE", function()
    local now = IsInGuild()
    if wasInGuild == false and now then
        ns.After(8, function() maybeShow(true) end)
    end
    wasInGuild = now
end)
ns.Listen("LOGIN", function()
    wasInGuild = IsInGuild()
    ns.After(25, function() maybeShow(false) end)
end)
-- "Say hello" also counts as done if you write anything in guild chat yourself
ns.On("CHAT_MSG_GUILD", function(_, sender)
    sender = ns.safe(sender)
    if not sender or not ns.isMe(ns.fullName and ns.fullName(sender) or sender) and ns.short(sender) ~= ns.short(ns.me()) then return end
    if not ns.char then return end
    local d = stepsDone()
    if d.hello then return end
    d.hello = true
    if win and win:IsShown() and win.done then win.done.hello = true Welcome.Refresh() end
end)

-- Oasis - Guild care (guild leadership only): inactive, applicants, recruiting, gear, attendance,
-- log, ban list, export, emblem. Everything with cooldowns - nothing goes out automatically.
local ADDON, ns = ...
ns.ModuleFile("Oasis_GuildManagement", function()   -- Guild care module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C
local O = ns.Officer

if ns.ICONS then ns.ICONS.officer = ns.MEDIA .. "icons\\rights" end

local TABS = {
    { key = "inactive", text = "Inactive" }, { key = "recruits", text = "Applicants" }, { key = "ads", text = "Recruiting" },
    { key = "gear", text = "Gear" }, { key = "attend", text = "Attendance" }, { key = "audit", text = "Log" },
    { key = "bans", text = "Ban list" }, { key = "sndmute", text = "Sound mute" }, { key = "export", text = "Export" }, { key = "crest", text = "Crest" },
}
local page
local function S() return ns.db.settings end
O.frames = {}
-- guild care lives in guild leadership: always redraw the currently open page
function O.Refresh() ns.RefreshPage(ns.CurrentPage and ns.CurrentPage() or "admin") end
local function cname(name, class)
    if ns.Radar and ns.Radar.Colored then return ns.Radar.Colored(name) end
    return ns.colorName(name, class)
end
local function fmtAgo(sec)
    local d = math.floor(sec / 86400)
    if d >= 1 then return (L["%d days ago"]):format(d) end
    local h = math.floor(sec / 3600)
    if h >= 1 then return (L["%dh ago"]):format(h) end
    return L["just now"]
end
-- prefill chat line with a command (pressing Enter = you decide)
local function prefill(text)
    if ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end
local function smallBtn(parent, text, w, fn, color)
    local b = K.Button(parent, text, w or 80, 20, "ghost", fn)
    if color then b.label:SetTextColor(color[1], color[2], color[3]) end
    return b
end
local function input(parent, w, ph, fn)
    local e = K.Input(parent, w, ph, fn)
    return e
end
-- simple list with columns
local function makeList(parent, top, rowH, cols, fill, extra)
    local list = K.List(parent, rowH or 28, function(l)
        local r = K.Row(l)
        for _, c in ipairs(cols) do r:Col(c[1], c[2], c[3], c[4] or 12, c[5] or C.text, c[6]) end
        if extra then extra(r) end
        return r
    end, fill)
    list:SetPoint("TOPLEFT", 0, top)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    return list
end
local function heads(parent, y, defs)
    for _, d in ipairs(defs) do
        local t = K.Text(parent, 10, C.dim)
        t:SetPoint("TOPLEFT", d[2], y)
        t:SetText(K.Upper(L[d[1]]))
    end
end

------------------------------------------------------------------------
-- Inactive
------------------------------------------------------------------------
local BUILD, REFRESH = {}, {}
BUILD.inactive = function(f)
    local hint = K.Text(f, 11, C.muted)
    hint:SetPoint("TOPLEFT", 0, 0)
    hint:SetText(L["Offline for at least"])
    f.days = input(f, 50, "30", function(t) local n = tonumber(t) if n then S().inactiveDays = math.max(1, n) O.Refresh() end end)
    f.days:SetPoint("LEFT", hint, "RIGHT", 8, 0)
    local t2 = K.Text(f, 11, C.muted)
    t2:SetPoint("LEFT", f.days, "RIGHT", 8, 0)
    t2:SetText(L["days"])
    f.sum = K.Text(f, 11, C.dim, "RIGHT")
    f.sum:SetPoint("TOPRIGHT", 0, -2)
    -- remove several at once: tick them, then one per click (WoW only allows removing by click)
    f.sel = {}
    f.kickSel = smallBtn(f, "", 230, function(self)
        local q = {}
        for _, e in ipairs(f.rows or {}) do if f.sel[e.name] then q[#q + 1] = e.name end end
        if #q == 0 then return end
        if not self.armed or GetTime() - self.armed > 8 then
            self.armed = GetTime()
            self:SetLabel("|cffff5a4a" .. (L["Really remove %d? Click again"]):format(#q) .. "|r")
            return
        end
        self.armed = GetTime()
        local name = q[1]
        local ok = pcall(GuildUninvite, ns.ChatName(name))
        if ok then f.sel[name] = nil ns.print((L["%s removed from the guild."]):format(ns.displayName(name)))
        else ns.print(L["Removal failed - missing permission?"]) end
        ns.After(1, function() if ns.Radar.RequestRoster then ns.Radar.RequestRoster() end O.Refresh() end)
        O.Refresh()
    end, C.red)
    f.kickSel:SetPoint("RIGHT", f.sum, "LEFT", -12, 0)
    f.allSel = smallBtn(f, L["Select all"], 110, function()
        local any = false
        for _ in pairs(f.sel) do any = true break end
        f.sel = {}
        if not any then for _, e in ipairs(f.rows or {}) do f.sel[e.name] = true end end
        O.Refresh()
    end)
    f.allSel:SetPoint("RIGHT", f.kickSel, "LEFT", -8, 0)
    heads(f, -34, { { "Name", 34 }, { "Rank", 200 }, { "Lvl", 320 }, { "Offline", 360 }, { "Suggestion", 500 } })
    f.list = makeList(f, -50, 28, {
        { "name", 34, 160 }, { "rank", 200, 110, 12, C.muted }, { "lvl", 320, 30, 12, C.muted }, { "off", 360, 130, 12, C.red }, { "tip", 500, 200, 11, C.amber },
    }, function(r, m)
        r.cols.name:SetText(cname(m.name, m.class))
        r.cols.rank:SetText(m.rank or "")
        r.cols.lvl:SetText(m.level or "")
        r.cols.off:SetText((L["%d days"]):format(math.floor(m.offDays or 0)))
        r.cols.tip:SetText(m.tip or "")
        r.dem.name, r.kick.name = m.name, m.name
        r.chk.name = m.name
        r.chk.mark:SetShown(f.sel[m.name] and true or false)
    end, function(r)
        r.chk = CreateFrame("Button", nil, r)
        r.chk:SetSize(16, 16)
        r.chk:SetPoint("LEFT", 10, 0)
        K.Fill(r.chk, C.field)
        K.Border(r.chk, C.line)
        r.chk.mark = r.chk:CreateTexture(nil, "OVERLAY")
        r.chk.mark:SetPoint("TOPLEFT", 3, -3) r.chk.mark:SetPoint("BOTTOMRIGHT", -3, 3)
        r.chk.mark:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
        r.chk:SetScript("OnClick", function(self)
            local fr = O.frames.inactive
            if fr then fr.sel[self.name] = (not fr.sel[self.name]) or nil end
            O.Refresh()
        end)
        r.dem = smallBtn(r, L["Demote"], 90, function(self) prefill("/gdemote " .. ns.ChatName(self.name)) end)
        r.dem:SetPoint("RIGHT", -100, 0)
        r.kick = smallBtn(r, L["Remove"], 84, function(self) prefill("/gremove " .. ns.ChatName(self.name)) end, C.red)
        r.kick:SetPoint("RIGHT", -10, 0)
    end)
    f.list.empty:SetText(L["Nobody has been offline that long."])
    local foot = K.Text(f, 10, C.dim)
    foot:SetPoint("BOTTOMLEFT", 0, -16)
    foot:SetText(L["The buttons put the command into the chat line - it only runs when you press Enter."])
end
REFRESH.inactive = function(f)
    local thr = S().inactiveDays or 30
    if not f.days:HasFocus() then f.days:SetText(tostring(thr)) end
    local out = {}
    -- last activity per main: if one of the player's alts is active, don't suggest
    local mainActive = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        local mn = ns.Alts and ns.Alts.Main(m.name) or m.name
        local d = m.online and 0 or (m.offDays or 999)
        if not mainActive[mn] or d < mainActive[mn] then mainActive[mn] = d end
    end
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        if not m.online and (m.offDays or 0) >= thr then
            local mn = ns.Alts and ns.Alts.Main(m.name) or m.name
            local e = { name = m.name, class = m.class, rank = m.rank, level = m.level, offDays = m.offDays }
            if (mainActive[mn] or 999) < thr then e.tip = L["Alt - player is active"]
            elseif m.offDays >= thr * 4 then e.tip = L["gone long: remove?"]
            elseif m.offDays >= thr * 2 then e.tip = L["demote?"]
            else e.tip = L["watch"] end
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b) return (a.offDays or 0) > (b.offDays or 0) end)
    f.sum:SetText((L["%d inactive"]):format(#out))
    f.rows = out
    local n = 0
    local still = {}
    for _, e in ipairs(out) do if f.sel[e.name] then n = n + 1 still[e.name] = true end end
    f.sel = still
    if not (f.kickSel.armed and GetTime() - f.kickSel.armed < 8) or n == 0 then
        f.kickSel.armed = nil
        f.kickSel:SetLabel(n > 0 and ((L["Remove marked (%d)"]):format(n)) or L["Remove marked"])
    else
        f.kickSel:SetLabel("|cffff5a4a" .. (L["Remove next (%d left)"]):format(n) .. "|r")
    end
    f.kickSel:SetEnabledState(n > 0)
    f.list:SetData(out)
end

------------------------------------------------------------------------
-- Applicants + trial
------------------------------------------------------------------------
BUILD.recruits = function(f)
    f.name = input(f, 180, L["Name"], nil)
    f.name:SetPoint("TOPLEFT", 0, 0)
    if K.AttachNameSuggest then pcall(K.AttachNameSuggest, f.name) end
    f.note = input(f, 300, L["Note (class, contact, impression ...)"], nil)
    f.note:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
    local add = K.Button(f, L["Add"], 110, 24, "primary", function()
        local n = f.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        O.SaveRecruit({ name = n, note = f.note:GetText(), st = "app" })
        f.name:SetText("") f.note:SetText("")
        O.Refresh()
    end)
    add:SetPoint("LEFT", f.note, "RIGHT", 8, 0)
    local tl = K.Text(f, 11, C.muted)
    tl:SetPoint("LEFT", add, "RIGHT", 18, 0)
    tl:SetText(L["Trial (days)"])
    f.trial = input(f, 44, "14", function(t) local n = tonumber(t) if n then S().trialDays = math.max(1, n) end end)
    f.trial:SetPoint("LEFT", tl, "RIGHT", 6, 0)
    heads(f, -36, { { "Name", 10 }, { "Status", 170 }, { "Mentor", 290 }, { "Trial", 420 }, { "Note", 540 } })
    f.list = makeList(f, -52, 30, {
        { "name", 10, 150 }, { "pate", 290, 120, 12, C.muted }, { "trial", 420, 110, 12 }, { "note", 540, 260, 11, C.muted },
    }, function(r, rec)
        r.rec = rec
        r.cols.name:SetText(rec.name or "?")
        local st = O.STATUS[1]
        for _, s in ipairs(O.STATUS) do if s[1] == (rec.st or "app") then st = s end end
        r.st.label:SetText(L[st[2]])
        r.st.label:SetTextColor(st[3][1], st[3][2], st[3][3])
        K.SetBorderColor(r.st, st[3])
        r.cols.pate:SetText(rec.pate and ns.displayName(rec.pate) or "|cff555555-|r")
        local left = O.TrialLeft(rec)
        if left then
            r.cols.trial:SetText(left > 0 and ("|cffe8b44a" .. (L["%d days left"]):format(math.ceil(left / 86400)) .. "|r") or ("|cffff5a4a" .. L["over - decide!"] .. "|r"))
        else
            r.cols.trial:SetText("")
        end
        r.cols.note:SetText(rec.note or "")
    end, function(r)
        r.st = K.Button(r, "", 100, 20, "ghost", function(self)
            local rec = self:GetParent().rec
            if not rec then return end
            local order = { app = "trial", trial = "member", member = "no", no = "app" }
            local c = {}
            for k, v in pairs(rec) do c[k] = v end
            c.st = order[rec.st or "app"]
            if c.st == "trial" then c.trial = ns.now() end
            O.SaveRecruit(c)
            O.Refresh()
        end)
        r.st:SetPoint("LEFT", 170, 0)
        r.pateBtn = smallBtn(r, L["I'm the mentor"], 96, function(self)
            local rec = self:GetParent().rec
            if not rec then return end
            local c = {}
            for k, v in pairs(rec) do c[k] = v end
            c.pate = ns.me()
            O.SaveRecruit(c)
            O.Refresh()
        end)
        r.pateBtn:SetPoint("RIGHT", -40, 0)
        r.del = K.CloseButton(r, function(self)
            local rec = r.rec
            if rec then ns.Store.Delete("recruits", rec.id) O.Refresh() end
        end, L["Put out"])
        r.del:SetPoint("RIGHT", -6, 0)
    end)
    f.list.empty:SetText(L["No applicants yet. Enter a name above - click the status to advance it."])
end
REFRESH.recruits = function(f)
    if not f.trial:HasFocus() then f.trial:SetText(tostring(S().trialDays or 14)) end
    f.list:SetData(O.Recruits())
end

------------------------------------------------------------------------
-- Recruiting: post text (15 min pause), player search (/who, 20 s pause), messaging (30 s, max. 10/h)
------------------------------------------------------------------------
local AD_CD, WHO_CD, WHISPER_CD, WHISPER_MAX = 900, 20, 30, 10
local lastAd, lastWho, whispers = 0, 0, {}
local function whispersLastHour()
    local n, now = 0, GetTime()
    for i = #whispers, 1, -1 do if now - whispers[i] < 3600 then n = n + 1 else table.remove(whispers, i) end end
    return n
end
local function multiBox(parent, w, h, getter, setter)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    K.Fill(box, C.field)
    K.Border(box, C.line)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetPoint("TOPLEFT", 6, -5)
    eb:SetPoint("BOTTOMRIGHT", -6, 5)
    eb:SetMaxLetters(255)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(self, user) if user and setter then setter(self:GetText()) end end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    box.eb = eb
    box.Load = function() if not eb:HasFocus() then eb:SetText(getter() or "") end end
    return box
end
-- templates for recruiting/messages name your OWN guild: "<Oasis>" in the text is only the placeholder (0.5.912)
local function ownGuild(s)
    local g = (ns.Admin and ns.Admin.GuildName and ns.Admin.GuildName()) or (GetGuildInfo and GetGuildInfo("player")) or "Oasis"
    return (s:gsub("<Oasis>", function() return "<" .. tostring(g) .. ">" end))
end
BUILD.ads = function(f)
    local h1 = K.GameHead(f, L["Post guild ad"], C.amber)
    h1:SetPoint("TOPLEFT", 0, 0)
    h1:SetWidth(300)
    f.ad = multiBox(f, 420, 56, function() return S().recruitAd or ownGuild(L["<Oasis> is looking for nice people to level, quest and run dungeons with! With our own guild hub. /w me if interested :)"]) end,
        function(t) S().recruitAd = t end)
    f.ad:SetPoint("TOPLEFT", 0, -26)
    f.chanBtns = {}
    f.post = K.Button(f, L["Mail"], 150, 24, "primary", function()
        if GetTime() - lastAd < AD_CD then return end
        local ch = S().recruitChan
        local id = ch and GetChannelName(ch)
        if not id or id == 0 then ns.print(L["Pick a channel (above) - you must have joined it."]) return end
        local msg = (f.ad.eb:GetText() or ""):gsub("\n", " ")
        if msg == "" then return end
        SendChatMessage(msg, "CHANNEL", nil, id)
        lastAd = GetTime()
    end)
    f.post:SetPoint("TOPLEFT", 430, -26)
    f.chanLbl = K.Text(f, 10, C.dim)
    f.chanLbl:SetPoint("TOPLEFT", 0, -88)
    f.chanLbl:SetText(K.Upper(L["Channel"]))

    local h2 = K.GameHead(f, L["Find players without a guild"], C.blue)
    h2:SetPoint("TOPLEFT", 0, -130)
    h2:SetWidth(300)
    local lv = K.Text(f, 11, C.muted)
    lv:SetPoint("TOPLEFT", 0, -160)
    lv:SetText(L["Level"])
    f.lo = input(f, 40, "10", nil)
    f.lo:SetPoint("LEFT", lv, "RIGHT", 8, 0)
    f.hi = input(f, 40, "60", nil)
    f.hi:SetPoint("LEFT", f.lo, "RIGHT", 6, 0)
    f.who = K.Button(f, L["Search"], 130, 24, "primary", function()
        if GetTime() - lastWho < WHO_CD then return end
        local lo, hi = tonumber(f.lo:GetText()) or 10, tonumber(f.hi:GetText()) or 60
        lastWho = GetTime()
        f.whoWasShown = FriendsFrame and FriendsFrame:IsShown()
        if C_FriendList and C_FriendList.SendWho then
            if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
            C_FriendList.SendWho(("%d-%d"):format(lo, hi))
        end
    end)
    f.who:SetPoint("LEFT", f.hi, "RIGHT", 10, 0)
    f.wtl = K.Text(f, 11, C.muted)
    f.wtl:SetPoint("LEFT", f.who, "RIGHT", 18, 0)
    f.wtl:SetText(L["Whisper text"])
    f.wmsg = input(f, 300, ownGuild(L["Hi! We're <Oasis> - fancy a guild? :)"]), function(t) S().recruitWhisper = t end)
    f.wmsg:SetPoint("LEFT", f.wtl, "RIGHT", 8, 0)
    heads(f, -192, { { "Name", 10 }, { "Lvl", 200 }, { "Class", 240 }, { "Zone", 360 } })
    f.list = makeList(f, -208, 28, {
        { "name", 10, 180 }, { "lvl", 200, 34, 12, C.muted }, { "cls", 240, 110, 12, C.muted }, { "zone", 360, 200, 12, C.muted },
    }, function(r, w)
        r.w = w
        r.cols.name:SetText(w.name)
        r.cols.lvl:SetText(w.level or "")
        r.cols.cls:SetText(w.cls or "")
        r.cols.zone:SetText(w.zone or "")
        local done = ns.db.recruitContacted and ns.db.recruitContacted[w.name]
        r.msg.label:SetText(done and L["contacted"] or L["Whisper"])
        r.msg:SetEnabled(not done)
    end, function(r)
        r.msg = smallBtn(r, L["Whisper"], 110, function(self)
            local w = self:GetParent().w
            if not w then return end
            local now = GetTime()
            if now - (f.lastWhisper or 0) < WHISPER_CD then ns.print((L["Please wait %d s (spam protection)."]):format(math.ceil(WHISPER_CD - (now - (f.lastWhisper or 0))))) return end
            if whispersLastHour() >= WHISPER_MAX then ns.print(L["At most 10 messages per hour (spam protection)."]) return end
            local msg = (S().recruitWhisper and S().recruitWhisper ~= "") and S().recruitWhisper or ownGuild(L["Hi! We're <Oasis> - fancy a guild? :)"])
            SendChatMessage(msg, "WHISPER", nil, w.name)
            f.lastWhisper = now
            whispers[#whispers + 1] = now
            ns.db.recruitContacted = ns.db.recruitContacted or {}
            ns.db.recruitContacted[w.name] = ns.now()
            O.Refresh()
        end)
        r.msg:SetPoint("RIGHT", -10, 0)
    end)
    f.list.empty:SetText(L["No search yet. Enter levels and click \"Search\" - players with a guild are hidden."])
    f.results = {}
    f:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t < 0.5 then return end
        self.t = 0
        local adLeft = AD_CD - (GetTime() - lastAd)
        self.post.label:SetText(adLeft > 0 and (L["Mail"] .. "  " .. ("%d:%02d"):format(math.floor(adLeft / 60), adLeft % 60)) or L["Mail"])
        self.post:SetEnabled(adLeft <= 0)
        local whoLeft = WHO_CD - (GetTime() - lastWho)
        self.who.label:SetText(whoLeft > 0 and (L["Search"] .. "  " .. math.ceil(whoLeft) .. " s") or L["Search"])
        self.who:SetEnabled(whoLeft <= 0)
    end)
end
REFRESH.ads = function(f)
    f.ad.Load()
    if not f.wmsg:HasFocus() then f.wmsg:SetText(S().recruitWhisper or "") end
    -- channels you are in
    for _, b in ipairs(f.chanBtns) do b:Hide() end
    local x, i = 60, 0
    local list = { GetChannelList() }
    for j = 1, #list, 3 do
        local name = list[j + 1]
        if type(name) == "string" then
            i = i + 1
            local b = f.chanBtns[i]
            if not b then
                b = K.Button(f, "", 0, 20, "ghost", function(self) S().recruitChan = self.chan O.Refresh() end)
                f.chanBtns[i] = b
            end
            b.chan = name
            b.label:SetText(name)
            b:SetWidth(b.label:GetStringWidth() + 20)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -84)
            K.SetBorderColor(b, S().recruitChan == name and C.accent or C.line)
            b:Show()
            x = x + b:GetWidth() + 6
        end
    end
    f.list:SetData(f.results)
end
ns.On("WHO_LIST_UPDATE", function()
    local f = O.frames and O.frames.ads
    if not f then return end
    if GetTime() - lastWho > 15 then return end
    local out = {}
    local n = C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults() or 0
    for i = 1, n do
        local w = C_FriendList.GetWhoInfo(i)
        if w and (w.fullGuildName or "") == "" and w.fullName then
            out[#out + 1] = { name = w.fullName, level = w.level, cls = w.classStr, zone = w.area }
        end
    end
    f.results = out
    -- no HideUIPanel from within Oasis: that "touches" Blizzard's window management and later blocks Esc
    O.Refresh()
end)
-- keyword in a whisper -> notice with invite button (click = you decide)
ns.On("CHAT_MSG_WHISPER", function(msg, sender)
    msg, sender = ns.safe(msg), ns.safe(sender)
    local kw = S() and S().recruitKeyword
    if not msg or not sender or not kw or kw == "" then return end
    if not msg:lower():find(kw:lower(), 1, true) then return end
    if not (CanGuildInvite and CanGuildInvite()) then return end
    if ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, ns.fullName(sender)) then return end
    K.Toast((L["%s wants to join the guild"]):format(ns.displayName(sender)), L["Click: invite to the guild"], C.mint, function()
        if C_GuildInfo and C_GuildInfo.Invite then C_GuildInfo.Invite(sender) elseif GuildInvite then GuildInvite(sender) end
    end)
end)

------------------------------------------------------------------------
-- Gear: missing enchants (from the profiles)
------------------------------------------------------------------------
BUILD.gear = function(f)
    local t = K.Text(f, 11, C.muted)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(L["From level"])
    f.min = input(f, 40, "60", function(v) local n = tonumber(v) if n then S().gearMinLvl = n O.Refresh() end end)
    f.min:SetPoint("LEFT", t, "RIGHT", 8, 0)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("LEFT", f.min, "RIGHT", 12, 0)
    n:SetText(L["Every Oasis user reports their own gear - no inspecting needed."])
    heads(f, -34, { { "Name", 10 }, { "Lvl", 190 }, { "Item level", 230 }, { "Missing", 290 }, { "Optional", 620 } })
    f.list = makeList(f, -50, 28, {
        { "name", 10, 170 }, { "lvl", 190, 34, 12, C.muted }, { "ilvl", 230, 50, 12, C.muted }, { "miss", 290, 320, 11, C.red }, { "opt", 620, 200, 11, C.dim },
    }, function(r, e)
        r.cols.name:SetText(cname(e.name, e.class))
        r.cols.lvl:SetText(e.level or "")
        r.cols.ilvl:SetText(e.ilvl or "")
        r.cols.miss:SetText(#e.miss > 0 and table.concat(e.miss, ", ") or "|cff66db9e" .. L["all enchanted"] .. "|r")
        r.cols.opt:SetText(table.concat(e.opt, ", "))
    end)
    f.list.empty:SetText(L["No data yet - gear arrives with the next Oasis sync."])
end
REFRESH.gear = function(f)
    local minL = S().gearMinLvl or 60
    if not f.min:HasFocus() then f.min:SetText(tostring(minL)) end
    local out = {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        if (m.level or 0) >= minL then
            local miss, opt = O.MissingEnchants(m.name)
            if miss then
                local pr = ns.db.members[m.name]
                out[#out + 1] = { name = m.name, class = m.class, level = m.level, ilvl = pr and pr.ilvl, miss = miss, opt = opt }
            end
        end
    end
    table.sort(out, function(a, b) if #a.miss ~= #b.miss then return #a.miss > #b.miss end return a.name < b.name end)
    f.list:SetData(out)
end

------------------------------------------------------------------------
-- Attendance
------------------------------------------------------------------------
BUILD.attend = function(f)
    f.info = K.Text(f, 11, C.muted)
    f.info:SetPoint("TOPLEFT", 0, 0)
    f.info:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    heads(f, -30, { { "Player", 10 }, { "Rate", 220 }, { "Raid days", 420 } })
    f.list = makeList(f, -46, 28, {
        { "name", 10, 200 }, { "pct", 380, 40, 12, C.text, "RIGHT" }, { "days", 420, 120, 12, C.muted },
    }, function(r, e)
        r.cols.name:SetText(cname(e.name))
        r.cols.pct:SetText(math.floor(e.rate * 100) .. " %")
        r.cols.days:SetText(e.here .. " / " .. e.total)
        local col = e.rate >= 0.75 and C.mint or (e.rate >= 0.5 and C.amber or C.red)
        r.bar:SetColorTexture(col[1], col[2], col[3], 0.85)
        r.bar:SetWidth(math.max(1, 150 * e.rate))
    end, function(r)
        r.track = r:CreateTexture(nil, "ARTWORK")
        r.track:SetColorTexture(1, 1, 1, 0.06)
        r.track:SetSize(150, 6)
        r.track:SetPoint("LEFT", 220, 0)
        r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.bar:SetHeight(6)
        r.bar:SetPoint("LEFT", r.track, "LEFT")
    end)
    f.list.empty:SetText(L["No raid days recorded yet. The raid leader (with Oasis) records them automatically on every boss kill."])
end
REFRESH.attend = function(f)

    local recs = ns.Store.List("attend", function(r) return (r.ts or 0) >= ns.now() - 28 * 86400 end)
    f.info:SetText((L["Last 4 weeks: %d raid days recorded. Counted per main (alts count too)."]):format(#recs))
    local seen, out = {}, {}
    for _, r in ipairs(recs) do
        for n in (r.n or ""):gmatch("[^,]+") do
            if not seen[n] then
                seen[n] = true
                local rate, here, total = O.Attendance(n, 28)
                if rate then out[#out + 1] = { name = n, rate = rate, here = here, total = total } end
            end
        end
    end
    table.sort(out, function(a, b) if a.rate ~= b.rate then return a.rate > b.rate end return a.name < b.name end)
    f.list:SetData(out)
end

------------------------------------------------------------------------
-- Log
------------------------------------------------------------------------
local KIND_COL = { promote = C.mint, demote = C.amber, kick = C.red, join = C.blue, leave = C.dim }
BUILD.audit = function(f)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("TOPLEFT", 0, 0)
    n:SetText(L["Promotions, demotions, kicks, joins and leaves - collected by all Oasis users (180 days)."])
    f.list = makeList(f, -24, 26, { { "when", 10, 150, 11, C.dim }, { "text", 170, 600, 12 } }, function(r, e)
        r.cols.when:SetText(date(L["%m/%d %H:%M"], e.ts or 0))
        local c = KIND_COL[e.kind] or C.text
        r.cols.text:SetText(K.hex(c) .. O.AuditText(e) .. "|r")
    end)
    f.list.empty:SetText(L["No entries yet."])
end
REFRESH.audit = function(f) f.list:SetData(O.Audit()) end

------------------------------------------------------------------------
-- Ban list
------------------------------------------------------------------------
BUILD.bans = function(f)
    f.name = input(f, 180, L["Name"], nil)
    f.name:SetPoint("TOPLEFT", 0, 0)
    f.reason = input(f, 340, L["Reason"], nil)
    f.reason:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
    local b = K.Button(f, L["Add to ban list"], 150, 24, "danger", function()
        local n = f.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        O.Ban(n, f.reason:GetText())
        f.name:SetText("") f.reason:SetText("")
        O.Refresh()
    end)
    b:SetPoint("LEFT", f.reason, "RIGHT", 8, 0)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("TOPLEFT", 0, -32)
    n:SetText(L["All Oasis users get a warning when a banned player is in their group, invites them or wants to trade - and see it in the tooltip."])
    f.list = makeList(f, -56, 28, { { "name", 10, 180 }, { "reason", 200, 400, 12, C.muted }, { "by", 610, 160, 11, C.dim } }, function(r, e)
        r.e = e
        r.cols.name:SetText("|cffff5a4a" .. (e.name or "?") .. "|r")
        r.cols.reason:SetText(e.reason or "")
        r.cols.by:SetText((e.by and ns.displayName(e.by) or "") .. "  " .. date(L["%m/%d"], e.ts or 0))
    end, function(r)
        r.un = smallBtn(r, L["Remove"], 90, function(self) local e = self:GetParent().e if e then O.Unban(e.name) O.Refresh() end end)
        r.un:SetPoint("RIGHT", -10, 0)
    end)
    f.list.empty:SetText(L["The ban list is empty."])
end
REFRESH.bans = function(f)
    local l = ns.Store.List("bans")
    table.sort(l, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    f.list:SetData(l)
end

------------------------------------------------------------------------
-- Sound block: block members from sound effects
------------------------------------------------------------------------
BUILD.sndmute = function(f)
    f.name = input(f, 180, L["Name"], nil)
    f.name:SetPoint("TOPLEFT", 0, 0)
    f.reason = input(f, 340, L["Reason"], nil)
    f.reason:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
    local function add(n)
        n = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then return end
        -- resolve names from the guild roster (first name is enough), otherwise take as typed
        local full = n
        for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
            if ns.SameName(m.name, n) or ns.short(m.name):lower() == n:lower() or ns.displayName(m.name):lower() == n:lower() then full = m.name break end
        end
        O.SoundMute(full, f.reason:GetText())
        f.name:SetText("") f.reason:SetText("")
        O.Refresh()
    end
    local b = K.Button(f, L["Mute sounds"], 130, 24, "danger", function() add(f.name:GetText()) end)
    b:SetPoint("LEFT", f.reason, "RIGHT", 8, 0)
    -- pick from the guild roster (who is online right now)
    local pick = K.Button(f, L["Pick member"], 130, 24, "ghost", function(self)
        local items = {}
        for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
            if m.online and not ns.isMe(m.name) and not O.SoundMuteOf(m.name) then
                local full = m.name
                items[#items + 1] = { text = ns.displayName(full), fn = function() f.name:SetText(ns.displayName(full)) end }
            end
        end
        table.sort(items, function(a, c) return a.text < c.text end)
        if #items == 0 then items[1] = { text = L["Nobody online"], disabled = true } end
        K.ShowMenu(self, items)
    end)
    pick:SetPoint("LEFT", b, "RIGHT", 6, 0)
    local n = K.Text(f, 10, C.dim)
    n:SetPoint("TOPLEFT", 0, -32)
    n:SetPoint("RIGHT", 0, 0)
    n:SetJustifyH("LEFT")
    n:SetText(L["Muted members can no longer send sound effects, and their sounds stay silent for everyone else. Also applies to their alts."])
    f.list = makeList(f, -56, 28, { { "name", 10, 180 }, { "reason", 200, 400, 12, C.muted }, { "by", 610, 160, 11, C.dim } }, function(r, e)
        r.e = e
        r.cols.name:SetText("|cffe8b44a" .. (e.name or "?") .. "|r")
        r.cols.reason:SetText(e.reason or "")
        r.cols.by:SetText((e.by and ns.displayName(e.by) or "") .. "  " .. date(L["%m/%d"], e.ts or 0))
    end, function(r)
        r.un = smallBtn(r, L["Remove"], 90, function(self) local e = self:GetParent().e if e then O.SoundUnmute(e.name) O.Refresh() end end)
        r.un:SetPoint("RIGHT", -10, 0)
    end)
    f.list.empty:SetText(L["Nobody is muted for sound effects."])
end
REFRESH.sndmute = function(f)
    local l = ns.Store.List("sndmute")
    table.sort(l, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    f.list:SetData(l)
end

------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------
local function json(v, ind)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return tostring(v) end
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
            return ""
        end) .. '"'
    end
    if t == "table" then
        local parts = {}
        if #v > 0 or next(v) == nil then
            for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = json(k) .. ":" .. json(v[k]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
O.JSON = json
local function discordText(snap)
    local on, total = 0, #snap.roster
    for _, m in ipairs(snap.roster) do if m.online then on = on + 1 end end
    local lines = { ("**%s** – %s"):format(snap.guild or "Guild", date("%d.%m.%Y %H:%M", snap.ts)), ("Mitglieder: %d  ·  online: %d"):format(total, on), "" }
    local top = {}
    for _, m in ipairs(snap.roster) do top[#top + 1] = m end
    table.sort(top, function(a, b) return (a.level or 0) > (b.level or 0) end)
    lines[#lines + 1] = "**Top-Level**"
    for i = 1, math.min(10, #top) do lines[#lines + 1] = ("%d. %s – %s"):format(i, ns.short(top[i].name), top[i].level or "?") end
    if #snap.attendance > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("**Raidtage erfasst:** %d"):format(#snap.attendance)
    end
    return table.concat(lines, "\n")
end
BUILD.export = function(f)
    local info = K.Text(f, 11, C.muted)
    info:SetPoint("TOPLEFT", 0, 0)
    info:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    info:SetWordWrap(true)
    info:SetText(L["Automatic: every 10 minutes and on logout Oasis stores a snapshot in the saved variables (WTF/Account/<account>/SavedVariables/Oasis.lua). The program Tools/oasis_export.py reads the file, turns it into JSON and can send it to your web page. Addons have no internet access - this is the safe way."])
    f.mode = "json"
    f.seg = K.Segments(f, { { key = "json", text = "JSON" }, { key = "discord", text = "Discord" } }, function(k) f.mode = k O.Refresh() end)
    f.seg:SetPoint("TOPLEFT", 0, -50)
    local snap = K.Button(f, L["Snapshot now"], 170, 24, "primary", function() O.Snapshot() f.dirty = true O.Refresh() end)
    snap:SetPoint("TOPLEFT", 200, -50)
    local rl = K.Button(f, L["Save (/reload)"], 170, 24, "ghost", function() O.Snapshot() ReloadUI() end)
    rl:SetPoint("LEFT", snap, "RIGHT", 8, 0)
    f.stamp = K.Text(f, 10, C.dim)
    f.stamp:SetPoint("LEFT", rl, "RIGHT", 12, 0)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -84)
    sf:SetPoint("BOTTOMRIGHT", -26, 0)
    K.Fill(sf, C.field)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 11, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetWidth(700)
    -- width follows the visible area (no fixed size)
    sf:HookScript("OnSizeChanged", function(_, w) if w and w > 50 then eb:SetWidth(w - 8) end end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnTextChanged", function(self, user) if user and f.text then self:SetText(f.text) self:HighlightText() end end)
    sf:SetScrollChild(eb)
    sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(math.max(100, (w or 800) - 10)) end)
    f.eb = eb
    local hint = K.Text(f, 10, C.dim)
    hint:SetPoint("BOTTOMLEFT", 0, -16)
    hint:SetText(L["Click into the field, Ctrl+C to copy."])
end
REFRESH.export = function(f)
    f.seg:Select(f.mode)
    local snap = ns.db.export or O.Snapshot()
    if not snap then return end
    f.stamp:SetText((L["As of: %s"]):format(date("%d.%m. %H:%M", snap.ts or 0)))
    f.text = f.mode == "discord" and discordText(snap) or json(snap)
    if not f.eb:HasFocus() then f.eb:SetText(f.text) end
end

------------------------------------------------------------------------
-- Emblem
------------------------------------------------------------------------
local CRESTS = { "leader", "loyal", "veteran", "fire", "heart", "owl", "reaper", "saint", "dice", "pack", "family", "innkeeper",
    "globetrotter", "duelist", "master", "angel", "fishking", "nightking", "platzhirsch", "survivor" }
local CRESTCOL = { "e8b44a", "e0453a", "66db9e", "4a9ee8", "a66be8", "f08ac8", "d9d9d9", "ff8a3d" }
function O.Crest()
    local cfg = ns.Admin and ns.Admin.Cfg() or {}
    local icon = cfg.crest ~= "" and cfg.crest or nil
    if not icon then return nil end
    local hex = (cfg.crestc ~= "" and cfg.crestc) or "e8b44a"
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    return ns.MEDIA .. "icons\\badges\\" .. icon, { r, g, b }
end
BUILD.crest = function(f)
    local n = K.Text(f, 11, C.muted)
    n:SetPoint("TOPLEFT", 0, 0)
    n:SetText(L["Guild crest - shown in the Oasis window and on every member's profile bar."])
    f.prev = CreateFrame("Frame", nil, f)
    f.prev:SetSize(96, 96)
    f.prev:SetPoint("TOPLEFT", 0, -30)
    f.prev.bg = f.prev:CreateTexture(nil, "BACKGROUND")
    f.prev.bg:SetTexture(ns.MEDIA .. "dot")
    f.prev.bg:SetAllPoints()
    f.prev.bg:SetVertexColor(0.08, 0.08, 0.09)
    f.prev.icon = f.prev:CreateTexture(nil, "ARTWORK")
    f.prev.icon:SetPoint("CENTER")
    f.prev.icon:SetSize(60, 60)
    f.icons = {}
    for i, key in ipairs(CRESTS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(36, 36)
        b:SetPoint("TOPLEFT", 120 + ((i - 1) % 10) * 42, -30 - math.floor((i - 1) / 10) * 42)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.t = b:CreateTexture(nil, "ARTWORK")
        b.t:SetPoint("TOPLEFT", 5, -5) b.t:SetPoint("BOTTOMRIGHT", -5, 5)
        b.t:SetTexture(ns.MEDIA .. "icons\\badges\\" .. key)
        b.key = key
        b:SetScript("OnClick", function(self) f.selIcon = self.key O.Refresh() end)
        f.icons[i] = b
    end
    f.cols = {}
    for i, hex in ipairs(CRESTCOL) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(28, 28)
        b:SetPoint("TOPLEFT", 120 + (i - 1) * 34, -128)
        b.t = b:CreateTexture(nil, "ARTWORK")
        b.t:SetAllPoints()
        b.t:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1)
        K.Border(b, C.line)
        b.hex = hex
        b:SetScript("OnClick", function(self) f.selCol = self.hex O.Refresh() end)
        f.cols[i] = b
    end
    local save = K.Button(f, L["Save crest"], 160, 24, "primary", function()
        if not ns.Admin then return end
        local cfg = {}
        for k, v in pairs(ns.Admin.Cfg()) do cfg[k] = v end
        cfg.crest, cfg.crestc = f.selIcon or "", f.selCol or ""
        if ns.Admin.Save(cfg) then ns.print(L["Crest saved - the guild sees it after the next sync."]) end
        if ns.Rewards and ns.Rewards.UpdateCrest then ns.Rewards.UpdateCrest() end
    end)
    save:SetPoint("TOPLEFT", 120, -170)
    local clear = K.Button(f, L["No crest"], 120, 24, "ghost", function() f.selIcon = "" O.Refresh() end)
    clear:SetPoint("LEFT", save, "RIGHT", 8, 0)
end
REFRESH.crest = function(f)
    local cfg = ns.Admin and ns.Admin.Cfg() or {}
    if f.selIcon == nil then f.selIcon = cfg.crest or "" end
    if f.selCol == nil then f.selCol = (cfg.crestc ~= "" and cfg.crestc) or "e8b44a" end
    local hex = f.selCol
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    if f.selIcon ~= "" then f.prev.icon:SetTexture(ns.MEDIA .. "icons\\badges\\" .. f.selIcon) f.prev.icon:Show() else f.prev.icon:Hide() end
    f.prev.icon:SetVertexColor(r, g, b)
    for _, ib in ipairs(f.icons) do
        ib.t:SetVertexColor(r, g, b)
        K.SetBorderColor(ib, ib.key == f.selIcon and C.accent or C.line)
    end
    for _, cb in ipairs(f.cols) do K.SetBorderColor(cb, cb.hex == f.selCol and C.text or C.line) end
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function setTab(key)
    page.tab = key
    page.seg:Select(key)
    for k, fr in pairs(page.tabs) do fr:SetShown(k == key) end
    if not page.tabs[key] then
        local fr = CreateFrame("Frame", nil, page)
        fr:SetPoint("TOPLEFT", 0, -40)
        fr:SetPoint("BOTTOMRIGHT", 0, 18)
        page.tabs[key] = fr
        local ok, e = pcall(BUILD[key], fr)
        if not ok then ns.err("officer/" .. key, e) end
    end
    S().officerTab = key
    O.Refresh()
end

ns.RegisterPage({
    key = "officer", title = "Guild care", order = 9.1, topbar = true, parent = "admin",
    sub = "Inactive, applicants, recruiting, gear, attendance, log, ban list, export and crest",
    visible = function() return true end,   -- visible to everyone, locked without permissions (Admin.lua lockPage)
    build = function(p)
        page = p
        p.tabs = {}
        local items = {}
        for _, t in ipairs(TABS) do items[#items + 1] = { key = t.key, text = L[t.text] } end
        p.seg = K.Segments(p, items, setTab)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        local line = K.Divider(p)
        line:SetPoint("TOPLEFT", 0, -28)
        line:SetPoint("TOPRIGHT", 0, -28)
        local back = K.Button(p, "< " .. L["Guild leadership"], 150, 22, "ghost", function() ns.ShowPage("admin") end)
        back:SetPoint("TOPRIGHT", 0, 0)
        local tab = S().officerTab
        setTab(BUILD[tab or ""] and tab or "inactive")
    end,
    refresh = function(p)
        local fr = p.tabs[p.tab]
        if fr and REFRESH[p.tab] then
            local ok, e = pcall(REFRESH[p.tab], fr)
            if not ok then ns.err("officer/" .. p.tab, e) end
        end
    end,
})


------------------------------------------------------------------------
-- embedding in guild leadership: group with sub-tabs
------------------------------------------------------------------------
local TEXT = {}
for _, t in ipairs(TABS) do TEXT[t.key] = t.text end
TEXT.lootlog = "Loot log"
-- for extensions (GuildHistory.lua)
O.BUILD, O.REFRESH, O.TEXT, O.KIND_COL = BUILD, REFRESH, TEXT, KIND_COL
O.makeList = makeList
function O.BuildGroup(fr, keys)
    fr.keys, fr.subs = keys, {}
    local items = {}
    for _, k in ipairs(keys) do items[#items + 1] = { key = k, text = L[TEXT[k] or k] } end
    fr.seg = K.Segments(fr, items, function(k) fr.cur = k S().officerTab = k O.Refresh() end)
    fr.seg:SetPoint("TOPLEFT", 0, 0)
    local want = S().officerTab
    fr.cur = keys[1]
    for _, k in ipairs(keys) do if k == want then fr.cur = k end end
end
function O.RefreshGroup(fr)
    local k = fr.cur
    if not fr.subs[k] then
        local sub = CreateFrame("Frame", nil, fr)
        sub:SetPoint("TOPLEFT", 0, -36)
        sub:SetPoint("BOTTOMRIGHT", 0, 18)
        fr.subs[k] = sub
        O.frames[k] = sub
        local ok, e = pcall(BUILD[k], sub)
        if not ok then ns.err("officer/" .. k, e) end
    end
    for key, sub in pairs(fr.subs) do sub:SetShown(key == k) end
    fr.seg:Select(k)
    if REFRESH[k] then
        local ok, e = pcall(REFRESH[k], fr.subs[k])
        if not ok then ns.err("officer/" .. k, e) end
    end
end
end)

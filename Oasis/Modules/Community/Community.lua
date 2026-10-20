-- Oasis: Community (0.6.469) - profile card, birthdays, mentors, thanks and helper of the week, guild achievements
local ADDON, ns = ...
ns.ModuleFile("Oasis_Community", function()   -- Community module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local CO = {}
ns.Community = CO
local CARD, MENTOR, THANKS = "gcard", "mentor", "thanks"
local WEEK = 7 * 86400

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function cut(s, n) s = trim(s) if #s > n then s = s:sub(1, n):gsub("[\192-\255][\128-\191]*$", "") end return s end
local function glass(f, a)
    if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, f, { 0.055, 0.055, 0.065, a or 0.85 }, { 1, 1, 1, 0.08 }, 10)
    else K.Fill(f, C.panel) K.Border(f, C.line) end
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
-- profile card per character: usually online when, time zone, "currently looking for", birthday (DD.MM, optional)
function CO.Card(name) return Store.Get(CARD, "c-" .. tostring(name or "")) end
function CO.SaveCard(t)
    local me = ns.me()
    if not me then return end
    local rec = { id = "c-" .. me, on = cut(t.on, 40), tz = cut(t.tz, 12), seek = cut(t.seek, 80), bday = cut(t.bday, 5) }
    if rec.bday ~= "" and not rec.bday:match("^%d%d?%.%d%d?$") then rec.bday = "" end
    Store.Put(CARD, rec)
end
function CO.Cards()
    local out = Store.List(CARD, function(r) return r.by end)
    table.sort(out, function(a, b) return (a.u or 0) > (b.u or 0) end)
    return out
end

-- Mentors: one record per newcomer (id = m-<newcomer>), created by the mentor
function CO.MentorOf(name) local r = Store.Get(MENTOR, "m-" .. tostring(name or "")) return r and r.by end
function CO.MenteesOf(name)
    local out = {}
    for _, r in ipairs(Store.List(MENTOR)) do if r.by and ns.SameName(r.by, name) and r.newbie then out[#out + 1] = r.newbie end end
    return out
end
function CO.BecomeMentor(newbie)
    if not newbie or CO.MentorOf(newbie) or ns.isMe(newbie) then return end
    Store.Put(MENTOR, { id = "m-" .. newbie, newbie = newbie, ts = ns.now() })
    K.Toast(L["Mentor"], (L["You are now mentor of %s."]):format(ns.displayName(newbie)), C.mint)
    if ns.OfferChat then ns.OfferChat(L["Mentor"], (L["Hi %s, I am your mentor in the guild - feel free to ask me anything!"]):format(ns.short(newbie)), "WHISPER", newbie) end
end
-- short addition for the member list
function CO.Tag(name)
    local me = ns.me()
    if CO.MentorOf(name) and ns.SameName(CO.MentorOf(name), me) then return "|cff66db9e" .. L["Mentee"] .. "|r" end
    if CO.MentorOf(me) and ns.SameName(CO.MentorOf(me), name) then return "|cff66db9e" .. L["your mentor"] .. "|r" end
    return nil
end
-- leveling together: mentor/mentee in the group -> Oasis XP
ns.On("PLAYER_LEVEL_UP", function()
    local me = ns.me()
    local partners = CO.MenteesOf(me)
    local m = CO.MentorOf(me)
    if m then partners[#partners + 1] = m end
    for _, p in ipairs(partners) do
        local s = ns.short(p)
        if (UnitInParty and UnitInParty(s)) or (UnitInRaid and UnitInRaid(s)) then
            if ns.Rewards and ns.Rewards.GiveXP then ns.Rewards.GiveXP(15, L["Levelled together with your mentor"]) end
            return
        end
    end
end)

-- Thanks: one record per thank-you (id = t-<from>-<time>)
function CO.Thank(to, why)
    if not to or ns.isMe(to) then return end
    Store.Put(THANKS, { id = ("t-%s-%d"):format(ns.short(ns.me()), math.floor(ns.now())), to = to, why = cut(why, 60), ts = ns.now() })
    K.Toast(L["Thanks given"], ns.displayName(to) .. ((why or "") ~= "" and ("  ·  " .. cut(why, 60)) or ""), C.mint)
end
function CO.Thanks(since)
    local out = Store.List(THANKS, function(r) return r.to and (r.ts or 0) > (since or 0) end)
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end
-- Helper of the week: who got thanked most often in the last 7 days
function CO.Helper()
    local n, best, bn = {}, nil, 0
    for _, r in ipairs(CO.Thanks(ns.now() - WEEK)) do
        n[r.to] = (n[r.to] or 0) + 1
        if n[r.to] > bn then best, bn = r.to, n[r.to] end
    end
    return best, bn
end

-- guild achievements of the week from the chronicle
local GOALS = {
    { kind = "boss", text = "Bosses defeated", goal = 25, color = { 0.98, 0.58, 0.22 } },
    { kind = "level", text = "Level milestones", goal = 30, color = { 0.45, 0.6, 1 } },
    { kind = "badge", text = "Badge", goal = 50, color = { 0.93, 0.3, 0.32 } },
    { kind = "duel", text = "Dice games", goal = 10, color = { 0.85, 0.55, 1 } },
    { kind = "thanks", text = "Thanks given", goal = 15, color = { 0.4, 0.86, 0.55 } },
}
function CO.WeekGoals()
    local cut0 = ns.now() - WEEK
    local cnt = {}
    for _, r in ipairs(Store.List("chronicle", function(r) return (r.ts or 0) > cut0 end)) do cnt[r.kind or ""] = (cnt[r.kind or ""] or 0) + 1 end
    cnt.thanks = #CO.Thanks(cut0)
    local out = {}
    for _, g in ipairs(GOALS) do out[#out + 1] = { text = g.text, n = cnt[g.kind] or 0, goal = g.goal, color = g.color } end
    return out
end

-- Birthdays: on login once a day a notice with click-to-congratulate
ns.Listen("LOGIN", function()
    ns.After(25, function()
        local today = date("%d.%m")
        local t2 = today:gsub("^0", ""):gsub("%.0", ".")
        ns.db.bdayShown = ns.db.bdayShown or {}
        for _, r in ipairs(CO.Cards()) do
            local b = r.bday or ""
            if b ~= "" and r.by and (b == today or b == t2) and not ns.isMe(r.by) then
                local key = date("%Y%m%d") .. r.by
                if not ns.db.bdayShown[key] and ns.OfferChat then
                    ns.db.bdayShown[key] = true
                    ns.OfferChat(L["Birthday"], (L["Happy birthday, %s!"]):format(ns.short(r.by)), "GUILD")
                end
            end
        end
    end)
end)

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
if ns.ICONS then ns.ICONS.community = ns.MEDIA .. "icons\\heart" end
local function box(p, title)
    local b = CreateFrame("Frame", nil, p)
    glass(b)
    b.head = K.GameHead(b, title, C.accent)
    b.head:SetPoint("TOPLEFT", 14, -12)
    b.head:SetPoint("RIGHT", b, "RIGHT", -14, 0)
    return b
end
local function field(parent, label, w, ph)
    local l = K.Text(parent, 10, C.dim)
    l:SetText(label)
    local e = K.Input(parent, w, ph or "")
    e:SetHeight(26)
    return l, e
end

ns.RegisterPage({
    key = "community", title = "Community", order = 7.63,
    sub = "Profiles, mentors, thanks and shared guild goals",
    build = function(p)
        -- My profile card
        local sb = box(p, L["My profile card"])
        p.sb = sb
        sb.lOn, sb.on = field(sb, L["Usually online"], 200, L["e.g. evenings from 7 pm"])
        sb.lTz, sb.tz = field(sb, L["Time zone"], 90, "MEZ")
        sb.lSeek, sb.seek = field(sb, L["I am looking for ..."], 300, L["e.g. group for Monastery"])
        sb.lBd, sb.bd = field(sb, L["Birthday (DD.MM, optional)"], 90, "24.12")
        sb.save = K.Button(sb, L["Save"], 110, 26, "primary", function()
            CO.SaveCard({ on = sb.on:GetText(), tz = sb.tz:GetText(), seek = sb.seek:GetText(), bday = sb.bd:GetText() })
            K.Toast(L["Profile card"], L["Saved - the guild can see it now."], C.mint)
            ns.RefreshPage("community", true)
        end)
        -- Mentors
        local pb = box(p, L["Mentors for newcomers"])
        p.pb = pb
        pb.mine = K.Text(pb, 11, C.text)
        pb.mine:SetWordWrap(true)
        pb.rows = {}
        for i = 1, 4 do
            local r = CreateFrame("Frame", nil, pb)
            r:SetHeight(28)
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("LEFT", 0, 0)
            r.b = K.Button(r, L["Become mentor"], 110, 24, "ghost", function() if r.who then CO.BecomeMentor(r.who) ns.RefreshPage("community", true) end end)
            r.b:SetPoint("RIGHT", 0, 0)
            pb.rows[i] = r
        end
        pb.none = K.Text(pb, 11, C.dim)
        pb.none:SetText(L["No new members without a mentor right now."])
        -- Guild achievements
        local gb = box(p, L["Guild achievements this week"])
        p.gb = gb
        gb.rows = {}
        for i = 1, #GOALS do
            local r = {}
            r.l = K.Text(gb, 11, C.text)
            r.v = K.Text(gb, 11, C.muted, "RIGHT")
            r.track = gb:CreateTexture(nil, "ARTWORK")
            r.track:SetHeight(6)
            r.track:SetColorTexture(1, 1, 1, 0.06)
            r.fill = gb:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(6)
            gb.rows[i] = r
        end
        -- Thanks
        local db = box(p, L["Say thanks"])
        p.db = db
        db.helper = K.Text(db, 12, C.text)
        db.lTo, db.to = field(db, L["To whom?"], 150, L["Name"])
        db.lWhy, db.why = field(db, L["What for? (optional)"], 220, L["e.g. help in Monastery"])
        db.send = K.Button(db, L["Thanks"], 90, 26, "primary", function()
            local n = trim(db.to:GetText())
            if n == "" then return end
            local full = ns.Radar and ns.Radar.byName and (function()
                for nm in pairs(ns.Radar.byName) do if ns.SameName(nm, n) or ns.short(nm):lower() == n:lower() then return nm end end
            end)()
            if not full then K.Toast(L["Say thanks"], L["That is not a guild member."], C.amber) return end
            CO.Thank(full, db.why:GetText())
            db.to:SetText("") db.why:SetText("")
            ns.RefreshPage("community", true)
        end)
        db.list = K.Text(db, 11, C.muted)
        db.list:SetJustifyV("TOP")
        db.list:SetWordWrap(true)
        -- the guild's profile cards
        local cb = box(p, L["Guild profile cards"])
        p.cb = cb
        cb.list = K.List(cb, 30, function(l)
            local r = K.Row(l)
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("LEFT", 6, 0)
            r.n:SetWidth(150)
            r.n:SetWordWrap(false)
            r.on = K.Text(r, 11, C.muted)
            r.on:SetPoint("LEFT", 162, 0)
            r.on:SetWidth(170)
            r.on:SetWordWrap(false)
            r.seek = K.Text(r, 11, C.text)
            r.seek:SetPoint("LEFT", 340, 0)
            r.seek:SetPoint("RIGHT", -6, 0)
            r.seek:SetWordWrap(false)
            return r
        end, function(r, c)
            r.n:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(c.by) or c.by)
            r.on:SetText((c.on or "") .. ((c.tz or "") ~= "" and ("  |cff666666" .. c.tz .. "|r") or ""))
            r.seek:SetText((c.seek or "") ~= "" and ("|cffe8b44a" .. L["needs:"] .. "|r " .. c.seek) or "")
        end)
        cb.empty = K.Text(cb, 11, C.dim, "CENTER")
        cb.empty:SetText(L["No profile cards yet - fill in yours above."])

        function p:Layout()
            local W, H = self:GetWidth() or 760, self:GetHeight() or 520
            if W < 100 then return end
            local half = math.floor((W - 12) / 2)
            local rx = half + 12
            -- top left: profile card
            sb:ClearAllPoints() sb:SetPoint("TOPLEFT", 0, 0) sb:SetSize(half, 196)
            sb.lOn:ClearAllPoints() sb.lOn:SetPoint("TOPLEFT", 14, -42)
            sb.on:ClearAllPoints() sb.on:SetPoint("TOPLEFT", 14, -56) sb.on:SetWidth(half - 28 - 100)
            sb.lTz:ClearAllPoints() sb.lTz:SetPoint("TOPLEFT", half - 14 - 90, -42)
            sb.tz:ClearAllPoints() sb.tz:SetPoint("TOPLEFT", half - 14 - 90, -56) sb.tz:SetWidth(90)
            sb.lSeek:ClearAllPoints() sb.lSeek:SetPoint("TOPLEFT", 14, -90)
            sb.seek:ClearAllPoints() sb.seek:SetPoint("TOPLEFT", 14, -104) sb.seek:SetWidth(half - 28)
            sb.lBd:ClearAllPoints() sb.lBd:SetPoint("TOPLEFT", 14, -138)
            sb.bd:ClearAllPoints() sb.bd:SetPoint("TOPLEFT", 14, -152) sb.bd:SetWidth(90)
            sb.save:ClearAllPoints() sb.save:SetPoint("BOTTOMRIGHT", -14, 14)
            -- top right: guild achievements
            gb:ClearAllPoints() gb:SetPoint("TOPLEFT", rx, 0) gb:SetSize(W - rx, 196)
            for i, r in ipairs(gb.rows) do
                local y = -44 - (i - 1) * 29
                r.l:ClearAllPoints() r.l:SetPoint("TOPLEFT", gb, "TOPLEFT", 14, y)
                r.v:ClearAllPoints() r.v:SetPoint("TOPRIGHT", gb, "TOPRIGHT", -14, y)
                r.track:ClearAllPoints() r.track:SetPoint("TOPLEFT", gb, "TOPLEFT", 14, y - 15) r.track:SetPoint("RIGHT", gb, "RIGHT", -14, 0)
                r.fill:ClearAllPoints() r.fill:SetPoint("LEFT", r.track, "LEFT")
            end
            -- middle left: mentors
            pb:ClearAllPoints() pb:SetPoint("TOPLEFT", 0, -208) pb:SetSize(half, 176)
            pb.mine:ClearAllPoints() pb.mine:SetPoint("TOPLEFT", 14, -40) pb.mine:SetPoint("RIGHT", pb, "RIGHT", -14, 0)
            for i, r in ipairs(pb.rows) do
                r:ClearAllPoints() r:SetPoint("TOPLEFT", pb, "TOPLEFT", 14, -62 - (i - 1) * 28) r:SetPoint("RIGHT", pb, "RIGHT", -14, 0)
            end
            pb.none:ClearAllPoints() pb.none:SetPoint("TOPLEFT", 14, -70)
            -- middle right: thanks
            db:ClearAllPoints() db:SetPoint("TOPLEFT", rx, -208) db:SetSize(W - rx, 176)
            db.helper:ClearAllPoints() db.helper:SetPoint("TOPLEFT", 14, -40) db.helper:SetPoint("RIGHT", db, "RIGHT", -14, 0)
            db.lTo:ClearAllPoints() db.lTo:SetPoint("TOPLEFT", 14, -62)
            db.to:ClearAllPoints() db.to:SetPoint("TOPLEFT", 14, -76) db.to:SetWidth(130)
            db.lWhy:ClearAllPoints() db.lWhy:SetPoint("TOPLEFT", 152, -62)
            db.why:ClearAllPoints() db.why:SetPoint("TOPLEFT", 152, -76) db.why:SetPoint("RIGHT", db, "RIGHT", -112, 0)
            db.send:ClearAllPoints() db.send:SetPoint("TOPRIGHT", -14, -76)
            db.list:ClearAllPoints() db.list:SetPoint("TOPLEFT", 14, -112) db.list:SetPoint("BOTTOMRIGHT", -14, 10)
            -- bottom: profile cards
            cb:ClearAllPoints() cb:SetPoint("TOPLEFT", 0, -396) cb:SetPoint("BOTTOMRIGHT", 0, 0)
            cb.list:ClearAllPoints() cb.list:SetPoint("TOPLEFT", 8, -38) cb.list:SetPoint("BOTTOMRIGHT", -8, 8)
            cb.empty:ClearAllPoints() cb.empty:SetPoint("TOP", 0, -50)
        end
        p:HookScript("OnSizeChanged", function(self) self:Layout() end)
        p:Layout()
    end,
    refresh = function(p)
        p:Layout()
        local me = ns.me()
        -- fill profile card only while nobody is typing
        local c = CO.Card(me)
        local sb = p.sb
        if c and not (sb.on:HasFocus() or sb.tz:HasFocus() or sb.seek:HasFocus() or sb.bd:HasFocus()) then
            sb.on:SetText(c.on or "") sb.tz:SetText(c.tz or "") sb.seek:SetText(c.seek or "") sb.bd:SetText(c.bday or "")
        end
        -- Mentors
        local pb = p.pb
        local mine = {}
        local m = CO.MentorOf(me)
        if m then mine[#mine + 1] = L["Your mentor:"] .. " " .. (ns.Radar and ns.Radar.Colored(m) or m) end
        local kids = CO.MenteesOf(me)
        if #kids > 0 then
            local t = {}
            for _, k in ipairs(kids) do t[#t + 1] = ns.Radar and ns.Radar.Colored(k) or k end
            mine[#mine + 1] = L["Your mentees:"] .. " " .. table.concat(t, ", ")
        end
        pb.mine:SetText(#mine > 0 and table.concat(mine, "   ") or ("|cff888888" .. L["Become a mentor for a new member - levelling together gives Oasis XP."] .. "|r"))
        local cand = {}
        for _, mm in ipairs(ns.Radar and ns.Radar.roster or {}) do
            if ns.Welcome and ns.Welcome.IsNew and ns.Welcome.IsNew(mm.name) and not CO.MentorOf(mm.name) and not ns.isMe(mm.name) then cand[#cand + 1] = mm.name end
        end
        for i, r in ipairs(pb.rows) do
            r.who = cand[i]
            r:SetShown(cand[i] ~= nil)
            if cand[i] then r.n:SetText((ns.Radar and ns.Radar.Colored(cand[i]) or cand[i]) .. "  |cff66db9e" .. L["NEW"] .. "|r") end
        end
        pb.none:SetShown(#cand == 0)
        -- Guild achievements
        for i, g in ipairs(CO.WeekGoals()) do
            local r = p.gb.rows[i]
            r.l:SetText(L[g.text])
            r.v:SetText(g.n .. " / " .. g.goal .. (g.n >= g.goal and "  |cff66db9e" .. L["done"] .. "|r" or ""))
            local w = (r.track:GetWidth() or 200)
            r.fill:SetWidth(math.max(1, w * math.min(1, g.n / g.goal)))
            r.fill:SetColorTexture(g.color[1], g.color[2], g.color[3], 0.9)
        end
        -- Thanks + helper of the week
        local h, hn = CO.Helper()
        p.db.helper:SetText(h and (L["Helper of the week:"] .. "  " .. (ns.Radar and ns.Radar.Colored(h) or h) .. "  |cff888888" .. (L["thanked %d times"]):format(hn) .. "|r")
            or ("|cff888888" .. L["No helper of the week yet - say thanks when someone helps you."] .. "|r"))
        local lines = {}
        for i, t in ipairs(CO.Thanks(ns.now() - WEEK)) do
            if i > 3 then break end
            lines[#lines + 1] = (ns.Radar and ns.Radar.Colored(t.by or "?") or "?") .. " |cff888888>|r " .. (ns.Radar and ns.Radar.Colored(t.to) or t.to)
                .. ((t.why or "") ~= "" and ("  |cff888888" .. t.why .. "|r") or "")
        end
        p.db.list:SetText(table.concat(lines, "\n"))
        -- Profile cards
        local cards = CO.Cards()
        p.cb.list:SetData(cards)
        p.cb.empty:SetShown(#cards == 0)
    end,
})
ns.slash.gemeinschaft = function() ns.ShowPage("community") end
end)

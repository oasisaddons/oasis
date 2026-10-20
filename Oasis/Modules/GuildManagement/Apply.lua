-- Oasis: Rekrutierungs-Mappe (0.6.527)
--  * Bewerben: Spieler (auch ohne Gilde, mit Oasis) schicken einem Offizier eine Bewerbung per Addon-Fluestern:
--    Klasse/Stufe (automatisch), Rolle, Spielzeiten, Ziele, ein paar Worte. /oa bewerben Name oder "Gilde finden".
--  * Offizier: landet bei Gildenpflege > Bewerber (Store "recruits", nur Offiziere) + Hinweis; antwortet "angekommen".
--  * Mappe: Bewerbung ansehen, mit 1-5 Sternen + Satz bewerten (Store "rrating", nur Offiziere), Schnitt aller
--    Bewertungen, Einladen / Probezeit / Ablehnen mit einem Klick.
-- Nichts geht automatisch in den Chat; Bewerbungen kommen nur ueber Oasis-Addon-Nachrichten.
local ADDON, ns = ...
ns.ModuleFile("Oasis_GuildManagement", function()
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
local AP = {}
ns.Apply = AP
local ROLES = { { "tank", "Tank" }, { "heal", "Healer" }, { "dps", "Damage" } }
local function cut(s, n) s = tostring(s or ""):gsub("[%c|]", " ") if #s > n then s = s:sub(1, n) end return s end

local function canRecruit() return (CanGuildInvite and ns.safe(CanGuildInvite())) or ns.isOfficer() end

------------------------------------------------------------------------
-- Senden (Bewerber)
------------------------------------------------------------------------
function AP.Send(target, role, times, goals, msg)
    target = (target or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if target == "" then return end
    local _, cls = UnitClass("player")
    Comm.Send("WHISPER", target, "APPLY", cls or "", UnitLevel("player") or 0, role or "", cut(times, 60), cut(goals, 80), cut(msg, 200), ns.version or "")
    K.Toast(L["Application sent"], (L["To %s - you'll get a reply once it has arrived."]):format(target), C.accent)
end
Comm.On("APPLYOK", function(sender, _, guild)
    K.Toast(L["Application received"], (L["%s received your application for %s."]):format(ns.short(sender), cut(guild, 40)), C.mint)
end)
Comm.On("APPLYNO", function(sender)
    K.Toast(L["Application"], (L["%s can't accept applications - ask for an officer."]):format(ns.short(sender)), C.amber)
end)

------------------------------------------------------------------------
-- Empfangen (Offizier)
------------------------------------------------------------------------
local lastFrom = {}
Comm.On("APPLY", function(sender, channel, cls, lvl, role, times, goals, msg, ver)
    if not sender or (lastFrom[sender] and GetTime() - lastFrom[sender] < 60) then return end
    lastFrom[sender] = GetTime()
    if not (IsInGuild() and canRecruit()) then Comm.Send("WHISPER", sender, "APPLYNO") return end
    local O = ns.Officer
    if not (O and O.SaveRecruit) then return end
    local rec = { name = ns.fullName(sender), st = "app", ts = ns.now(), cls = cut(cls, 20), lvl = tonumber(lvl) or 0,
        role = (role == "tank" or role == "heal" or role == "dps") and role or "", times = cut(times, 60), goals = cut(goals, 80),
        msg = cut(msg, 200), via = "oasis", by = ns.me() }
    O.SaveRecruit(rec)
    Comm.Send("WHISPER", sender, "APPLYOK", (GetGuildInfo and ns.safe(GetGuildInfo("player"))) or "")
    K.Toast(L["New application"], ns.short(sender) .. "  ·  " .. (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rec.cls] or rec.cls) .. " " .. rec.lvl,
        C.accent, function() AP.ShowFile(rec.name) end)
end)

------------------------------------------------------------------------
-- Bewertungen der Offiziere
------------------------------------------------------------------------
function AP.Rate(name, stars, text)
    if not ns.isOfficer() then return end
    stars = math.max(1, math.min(5, math.floor(tonumber(stars) or 3)))
    Store.Put("rrating", { id = "rr-" .. ns.NameKey(name) .. "@" .. ns.me(), who = ns.fullName(name), s = stars, t = cut(text, 120), by = ns.me(), ts = ns.now() })
end
function AP.Ratings(name)
    local k = ns.NameKey(name)
    local list = Store.List("rrating", function(r) return r.who and ns.NameKey(r.who) == k end)
    local sum = 0
    for _, r in ipairs(list) do sum = sum + (r.s or 0) end
    return list, #list > 0 and sum / #list or nil
end
function AP.RecruitOf(name)
    for _, r in ipairs(ns.Officer and ns.Officer.Recruits() or {}) do if ns.SameName(r.name, name) then return r end end
end

------------------------------------------------------------------------
-- Formular (Bewerber)
------------------------------------------------------------------------
local form
function AP.ShowForm(target)
    if not form then
        local f = CreateFrame("Frame", "OasisApplyForm", UIParent)
        f:SetSize(440, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.04, 0.04, 0.05, 0.97 }, { 1, 1, 1, 0.10 }, 12)) then K.Fill(f, { 0.04, 0.04, 0.05, 0.97 }) K.Border(f, C.line) end
        local t = K.Title(f, 16, C.text) t:SetPoint("TOPLEFT", 18, -16) t:SetText(L["Apply to a guild"])
        local x = K.CloseButton(f, function() f:Hide() end) x:SetPoint("TOPRIGHT", -6, -6)
        local function lab(text, y) local l = K.Text(f, 11, C.muted) l:SetPoint("TOPLEFT", 18, y) l:SetText(text) return l end
        lab(L["To (officer or guild master, with Oasis)"], -52)
        f.to = K.Input(f, 260, L["Name"]) f.to:SetPoint("TOPLEFT", 18, -68)
        lab(L["Your role"], -104)
        f.role = K.Segments(f, { { key = "dps", text = L["Damage"] }, { key = "tank", text = L["Tank"] }, { key = "heal", text = L["Healer"] } }, nil, nil, { size = 12 })
        f.role:SetPoint("TOPLEFT", 14, -120)
        lab(L["When do you play? (e.g. Mon-Fri evenings)"], -156)
        f.times = K.Input(f, 400, "") f.times:SetPoint("TOPLEFT", 18, -172)
        lab(L["What are you looking for? (raids, leveling, professions, community ...)"], -208)
        f.goals = K.Input(f, 400, "") f.goals:SetPoint("TOPLEFT", 18, -224)
        lab(L["A few words about you"], -260)
        f.msg = K.Input(f, 400, "") f.msg:SetPoint("TOPLEFT", 18, -276)
        f.send = K.Button(f, L["Send application"], 170, 26, nil, function()
            AP.Send(f.to:GetText(), f.role.value, f.times:GetText(), f.goals:GetText(), f.msg:GetText())
            f:Hide()
        end)
        f.send:SetPoint("BOTTOMRIGHT", -18, 16)
        local hint = K.Text(f, 10, C.dim) hint:SetPoint("BOTTOMLEFT", 18, 22) hint:SetPoint("RIGHT", f.send, "LEFT", -10, 0)
        hint:SetWordWrap(true) hint:SetText(L["Oasis sends your class and level automatically."])
        if ns.EscClose then ns.EscClose("OasisApplyForm") end
        form = f
    end
    if target and target ~= "" then form.to:SetText(target) end
    form:Show()
    form:Raise()
end
ns.slash.bewerben = function(arg) AP.ShowForm(arg) end
ns.slash.apply = ns.slash.bewerben

------------------------------------------------------------------------
-- Mappe (Offiziere)
------------------------------------------------------------------------
local file
local STATUS = { app = "Applicants", trial = "Trial", member = "Accepted", no = "Declined" }
function AP.ShowFile(name)
    if not ns.isOfficer() then return end
    local r = AP.RecruitOf(name)
    if not r then return end
    if not file then
        local f = CreateFrame("Frame", "OasisRecruitFile", UIParent)
        f:SetSize(480, 460)
        f:SetPoint("CENTER", 80, 0)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.04, 0.04, 0.05, 0.97 }, { 1, 1, 1, 0.10 }, 12)) then K.Fill(f, { 0.04, 0.04, 0.05, 0.97 }) K.Border(f, C.line) end
        f.title = K.Title(f, 16, C.text) f.title:SetPoint("TOPLEFT", 18, -16)
        f.sub = K.Text(f, 11, C.muted) f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
        local x = K.CloseButton(f, function() f:Hide() end) x:SetPoint("TOPRIGHT", -6, -6)
        f.body = K.Text(f, 12, C.text) f.body:SetPoint("TOPLEFT", 18, -64) f.body:SetPoint("RIGHT", -18, 0)
        f.body:SetJustifyH("LEFT") f.body:SetWordWrap(true) f.body:SetSpacing(4)
        f.rh = K.Text(f, 11, C.muted) f.rh:SetPoint("TOPLEFT", 18, -230) f.rh:SetText(L["Your rating"])
        f.stars = {}
        for i = 1, 5 do
            local b = K.Button(f, tostring(i), 30, 24, "ghost", function() f.myStars = i f:Paint() end)
            b:SetPoint("TOPLEFT", 18 + (i - 1) * 34, -246)
            f.stars[i] = b
        end
        f.note = K.Input(f, 260, L["short sentence (optional)"]) f.note:SetPoint("TOPLEFT", 196, -246)
        f.save = K.Button(f, L["Rate"], 90, 24, nil, function() AP.Rate(f.who, f.myStars or 3, f.note:GetText()) AP.ShowFile(f.who) end)
        f.save:SetPoint("TOPRIGHT", -18, -280)
        f.others = K.Text(f, 11, C.muted) f.others:SetPoint("TOPLEFT", 18, -314) f.others:SetPoint("RIGHT", -18, 0)
        f.others:SetJustifyH("LEFT") f.others:SetWordWrap(true)
        f.inv = K.Button(f, L["Invite to guild"], 160, 26, nil, function() if ns.GuildTools then ns.GuildTools.Invite(f.who) end end)
        f.inv:SetPoint("BOTTOMLEFT", 18, 16)
        f.trial = K.Button(f, L["Trial"], 100, 26, "ghost", function() local r2 = AP.RecruitOf(f.who) if r2 then r2.st, r2.trial = "trial", ns.now() ns.Officer.SaveRecruit(r2) AP.ShowFile(f.who) end end)
        f.trial:SetPoint("LEFT", f.inv, "RIGHT", 8, 0)
        f.no = K.Button(f, L["Decline"], 100, 26, "ghost", function() local r2 = AP.RecruitOf(f.who) if r2 then r2.st = "no" ns.Officer.SaveRecruit(r2) AP.ShowFile(f.who) end end)
        f.no:SetPoint("LEFT", f.trial, "RIGHT", 8, 0)
        function f:Paint() for i, b in ipairs(self.stars) do if K.SetBorderColor then K.SetBorderColor(b, (self.myStars or 0) >= i and C.amber or C.line) end end end
        if ns.EscClose then ns.EscClose("OasisRecruitFile") end
        file = f
    end
    local f = file
    f.who = r.name
    local roleT = ""
    for _, x in ipairs(ROLES) do if x[1] == r.role then roleT = L[x[2]] end end
    local cls = r.cls and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[r.cls]) or r.cls) or ""
    f.title:SetText(ns.colorName and ns.colorName(ns.short(r.name), r.cls) or ns.short(r.name))
    f.sub:SetText(L[STATUS[r.st or "app"] or "Applicants"] .. "  ·  " .. date("%d.%m.%Y", r.ts or 0) .. ((r.via == "oasis") and ("  ·  " .. L["via Oasis"]) or ""))
    local lines = {}
    if cls ~= "" or (r.lvl or 0) > 0 then lines[#lines + 1] = "|cff999999" .. L["Class"] .. ":|r " .. cls .. " " .. (r.lvl or "") .. (roleT ~= "" and ("  ·  " .. roleT) or "") end
    if (r.times or "") ~= "" then lines[#lines + 1] = "|cff999999" .. L["Play times"] .. ":|r " .. r.times end
    if (r.goals or "") ~= "" then lines[#lines + 1] = "|cff999999" .. L["Looking for"] .. ":|r " .. r.goals end
    if (r.msg or "") ~= "" then lines[#lines + 1] = "\"" .. r.msg .. "\"" end
    if (r.note or "") ~= "" then lines[#lines + 1] = "|cff999999" .. L["Note"] .. ":|r " .. r.note end
    f.body:SetText(#lines > 0 and table.concat(lines, "\n") or L["No details - added by hand."])
    local list, avg = AP.Ratings(r.name)
    local o = {}
    f.myStars = nil
    for _, x in ipairs(list) do
        if ns.isMe(x.by) then f.myStars = x.s f.note:SetText(x.t or "") end
        o[#o + 1] = ns.short(x.by) .. ": " .. string.rep("*", x.s or 0) .. ((x.t or "") ~= "" and ("  " .. x.t) or "")
    end
    f.others:SetText(avg and ((L["Ratings (average %.1f of 5):"]):format(avg) .. "\n" .. table.concat(o, "\n")) or L["No ratings yet."])
    f:Paint()
    f.inv:SetShown(canRecruit() and r.st ~= "member" and r.st ~= "no")
    f.trial:SetShown(r.st == "app")
    f.no:SetShown(r.st == "app" or r.st == "trial")
    f:Show()
    f:Raise()
end
ns.slash.mappe = function(arg) if arg and arg ~= "" then AP.ShowFile(ns.fullName(arg)) end end

end)

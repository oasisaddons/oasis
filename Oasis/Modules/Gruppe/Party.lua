-- Oasis: Meine Gruppe (0.6.521)
--  * Gruppenuebersicht: alle in Gruppe/Raid mit Klasse, Stufe, Erfahrung, Itemlevel, Rolle und ob Oasis laeuft
--  * Quests: wer hat welche Quest - "Bitte teilen" fragt ein Gruppenmitglied mit Oasis, ob es die Quest teilt
--  * Datenaustausch nur im Gruppenkanal (PARTY/RAID), gedrosselt; ohne Oasis sieht man Klasse/Stufe von Blizzard
-- Weitere Teile in diesem Ordner: PartyXP.lua (XP-Leiste), Blessings.lua (Segen), Threat.lua, Gamble.lua
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gruppe", function()
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm

local P = {}
ns.Party = P
P.info = {}      -- [voller Name] = { lvl, xp, xpMax, ilvl, role, ver, t, quests = { [qid] = { t = Titel, p = teilbar } } }

local function S() return ns.db.settings end
local function api(t, f) return t and type(t[f]) == "function" end
local function num(v, lo, hi) v = tonumber(v) if not v or v ~= v or v < lo or v > hi then return nil end return v end

------------------------------------------------------------------------
-- Gruppenmitglieder (Blizzard)
------------------------------------------------------------------------
function P.Units()
    local out = {}
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do out[#out + 1] = "party" .. i end
    end
    return out
end
local function unitName(u)
    local n, r = UnitName(u)
    n, r = ns.safe(n), ns.safe(r)
    if not n then return nil end
    if r and r ~= "" then return n .. "-" .. r end
    return ns.fullName(n)
end
P.UnitName = unitName
function P.InfoFor(name)
    for n, v in pairs(P.info) do if ns.SameName(n, name) then return v end end
    return nil
end
function P.Members()
    local out = {}
    for _, u in ipairs(P.Units()) do
        if UnitExists(u) then
            local name = unitName(u)
            if name then
                local _, cls = UnitClass(u)
                local inf = ns.isMe(name) and P.MyInfo() or P.InfoFor(name)
                out[#out + 1] = { unit = u, name = name, short = (name:gsub("%-.*$", "")), class = cls,
                    lvl = (inf and inf.lvl) or ns.safe(UnitLevel(u)) or 0, online = UnitIsConnected(u) and true or false,
                    role = (inf and inf.role) or ns.safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)) or "NONE",
                    info = inf, me = ns.isMe(name) }
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Eigene Daten
------------------------------------------------------------------------
local function myQuests()
    local out, Q = {}, C_QuestLog
    if not (api(Q, "GetNumQuestLogEntries") and api(Q, "GetInfo")) then return out end
    local okN, n = pcall(Q.GetNumQuestLogEntries)
    for i = 1, (okN and tonumber(n) or 0) do
        local ok, info = pcall(Q.GetInfo, i)
        local qid = ok and type(info) == "table" and not info.isHeader and not info.isHidden and tonumber(ns.safe(info.questID))
        if qid then
            local push = false
            if api(Q, "IsPushableQuest") then local okP, p = pcall(Q.IsPushableQuest, qid) push = okP and p == true end
            out[qid] = { t = ns.safe(info.title) or ("#" .. qid), p = push }
        end
    end
    return out
end
P.MyQuests = myQuests
function P.MyInfo()
    local avg, eq
    if GetAverageItemLevel then avg, eq = GetAverageItemLevel() end
    local role = ns.Upgrade and ns.Upgrade.Role and select(2, pcall(ns.Upgrade.Role)) or nil
    local rmap = { tank = "TANK", healer = "HEALER", ranged = "DAMAGER", caster = "DAMAGER", melee = "DAMAGER", agile = "DAMAGER" }
    return { lvl = UnitLevel("player") or 0, xp = ns.safe(UnitXP("player")) or 0, xpMax = ns.safe(UnitXPMax("player")) or 1,
        ilvl = math.floor((ns.safe(eq) or ns.safe(avg) or 0) + 0.5), role = (type(role) == "string" and rmap[role:lower()]) or nil,
        ver = ns.version, quests = myQuests() }
end

-- senden: "GPI" Stufe, XP, XP max, Itemlevel, Rolle, Version ; "GPQ" Quest-IDs (teilbar mit +)
local lastSent, pendingSend = 0, false
function P.Send(force)
    if not ns.groupChannel() or not ns.loggedIn then return end
    if ns.inCombat() and not force then pendingSend = true return end
    local now = GetTime()
    if not force and now - lastSent < 4 then
        if not pendingSend then pendingSend = true C_Timer.After(4.2 - (now - lastSent), function() pendingSend = false P.Send(true) end) end
        return
    end
    lastSent, pendingSend = now, false
    local m = P.MyInfo()
    Comm.Group("GPI", m.lvl, m.xp, m.xpMax, m.ilvl, m.role or "", m.ver or "")
    local ids = {}
    for qid, q in pairs(m.quests) do ids[#ids + 1] = qid .. (q.p and "+" or "") if #ids >= 35 then break end end
    Comm.Group("GPQ", table.concat(ids, ","))
end

local function inMyGroup(sender)
    for _, u in ipairs(P.Units()) do
        local n = UnitExists(u) and unitName(u)
        if n and ns.SameName(n, sender) then return true end
    end
    return false
end
P.InMyGroup = inMyGroup
local function rec(sender)
    local r = P.info[sender]
    if not r then r = { quests = {} } P.info[sender] = r end
    r.t = GetTime()
    return r
end
local function changed() ns.Fire("PARTY_INFO") ns.RefreshPage("party") end
Comm.On("GPI", function(sender, _, lvl, xp, xpMax, ilvl, role, ver)
    if ns.isMe(sender) or not inMyGroup(sender) then return end
    local r = rec(sender)
    r.lvl, r.xp, r.xpMax, r.ilvl = num(lvl, 1, 200), num(xp, 0, 1e8), num(xpMax, 1, 1e8), num(ilvl, 0, 1000)
    r.role = ({ TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" })[role or ""]
    r.ver = type(ver) == "string" and ver:match("^[%d%.]+$") and ver or nil
    r.oasis = true
    changed()
end)
-- Quest-Titel kommen nicht mit (Platz) - aus dem eigenen Questlog oder per Blizzard-Abfrage
local function questTitle(qid)
    local mine = myQuests()[qid]
    if mine then return mine.t end
    if api(C_QuestLog, "GetTitleForQuestID") then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
        if ok and ns.safe(t) then return t end
    end
    return "#" .. qid
end
P.QuestTitle = questTitle
Comm.On("GPQ", function(sender, _, list)
    if ns.isMe(sender) or not inMyGroup(sender) or type(list) ~= "string" then return end
    local r = rec(sender)
    r.quests, r.oasis = {}, true
    local n = 0
    for id, plus in list:gmatch("(%d+)(%+?)") do
        n = n + 1
        if n > 40 then break end
        local qid = num(id, 1, 1e7)
        if qid then r.quests[qid] = { p = plus == "+" } end
    end
    changed()
end)
-- Teilen-Bitte: an die Gruppe, Empfaenger prueft, ob er gemeint ist (Fluestern geht nur in der Gilde ueber Oasis)
function P.AskShare(target, qid)
    if not ns.groupChannel() then return end
    Comm.Group("GPQR", target, qid)
    K.Toast(L["Quest teilen"], (L["%s wurde gefragt, ob er/sie %s teilt."]):format((target:gsub("%-.*$", "")), questTitle(qid)), C.accent)
end
local askAt = {}
Comm.On("GPQR", function(sender, _, target, qid)
    qid = num(qid, 1, 1e7)
    if not qid or not target or not ns.isMe(target) or not inMyGroup(sender) then return end
    if askAt[sender] and GetTime() - askAt[sender] < 10 then return end
    askAt[sender] = GetTime()
    local q = myQuests()[qid]
    if not q then return end
    local who = sender:gsub("%-.*$", "")
    K.Toast(L["Quest teilen?"], (L["%s bittet dich: %s teilen - klicken zum Teilen"]):format(who, q.t), C.accent, function() P.Push(qid) end)
end)
function P.Push(qid)
    if ns.inCombat() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
    if not (QuestLogPushQuest and api(C_QuestLog, "SetSelectedQuest")) then ns.print(L["Quest teilen geht hier nicht - im Questlog auf Teilen klicken."]) return end
    local prev = api(C_QuestLog, "GetSelectedQuest") and select(2, pcall(C_QuestLog.GetSelectedQuest)) or nil
    pcall(C_QuestLog.SetSelectedQuest, qid)
    pcall(QuestLogPushQuest)
    if prev then pcall(C_QuestLog.SetSelectedQuest, prev) end
end

-- Ereignisse: bei Gruppenwechsel, Stufe, XP, Ausruestung und Questlog neu senden; Fremde aufraeumen
local function prune()
    for n in pairs(P.info) do if not inMyGroup(n) then P.info[n] = nil end end
end
ns.On("GROUP_ROSTER_UPDATE", function() prune() P.Send() changed() end)
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    ns.On(ev, function() P.Send() if ev == "PLAYER_XP_UPDATE" or ev == "PLAYER_LEVEL_UP" then ns.Fire("PARTY_INFO") end end)
end
ns.On("PLAYER_REGEN_ENABLED", function() if pendingSend then pendingSend = false C_Timer.After(1, function() P.Send(true) end) end end)
ns.Listen("LOGIN", function() C_Timer.After(5, function() P.Send(true) end) end)

------------------------------------------------------------------------
-- Seite "Meine Gruppe"
------------------------------------------------------------------------
local function glass(f, fill, line, r)
    local G = ns.Insta and ns.Insta.Glass
    if G and pcall(G, f, fill or { 1, 1, 1, 0.035 }, line or { 1, 1, 1, 0.09 }, r or 10) then return true end
    if not f.oasisFlat then f.oasisFlat = K.Fill(f, { 1, 1, 1, 0.03 }) K.Border(f, C.line) end
    return false
end
P.glass = glass
local ROLE_TEX = { TANK = "role_tank", HEALER = "role_heal", DAMAGER = "role_dps" }
local tab = "members"
P.tabs = {}      -- weitere Reiter aus den anderen Dateien: { key, text, build(p, area), refresh(p, area) }
function P.AddTab(def) P.tabs[#P.tabs + 1] = def end

local function memberRow(l)
    local r = K.Row(l)
    r.role = r:CreateTexture(nil, "ARTWORK")
    r.role:SetSize(16, 16)
    r.role:SetPoint("LEFT", 8, 0)
    r:Col("name", 30, 170, 13)
    r:Col("lvl", 205, 50, 13, C.muted, "CENTER")
    r.xp = K.Bar(r, 130, 6)
    r.xp:SetPoint("LEFT", 262, 0)
    r:Col("xpt", 398, 60, 10, C.dim)
    r:Col("ilvl", 460, 60, 13, C.text, "CENTER")
    r:Col("quests", 525, 70, 12, C.muted, "CENTER")
    r:Col("oasis", 600, 140, 11, C.dim)
    r.talents = K.Button(r, L["Talente"], 70, 20, "ghost", function(self)
        if ns.Talents and ns.Talents.Show and self.who then pcall(ns.Talents.Show, self.who) end
    end)
    r.talents:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and self.item then
            K.ShowMenu(self, {
                { text = L["Anfluestern"], fn = function() ChatFrame_OpenChat("/w " .. self.item.name .. " ") end },
                { text = L["Talente"], fn = function() if ns.Talents and ns.Talents.Show then pcall(ns.Talents.Show, self.item.name) end end },
            }, self.item.short)
        end
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return r
end
local function memberUpdate(r, m)
    local cr, cg, cb = ns.classColor(m.class)
    r.cols.name:SetText(m.short .. (m.online and "" or (" |cff666666(" .. L["offline"] .. ")|r")))
    r.cols.name:SetTextColor(cr or 1, cg or 1, cb or 1)
    r.cols.lvl:SetText(m.lvl > 0 and m.lvl or "?")
    local tex = ROLE_TEX[m.role]
    r.role:SetShown(tex ~= nil)
    if tex then r.role:SetTexture(ns.MEDIA .. "icons\\" .. tex) end
    local inf = m.info
    if inf and inf.xp and inf.xpMax and inf.xpMax > 0 and (m.lvl or 0) < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then
        r.xp:Show() r.xp:Set(inf.xp / inf.xpMax)
        r.cols.xpt:SetText(("%d%%"):format(math.floor(inf.xp / inf.xpMax * 100)))
    else
        r.xp:Hide() r.cols.xpt:SetText("")
    end
    r.cols.ilvl:SetText(inf and inf.ilvl and inf.ilvl > 0 and inf.ilvl or "|cff555555-|r")
    local nq = 0
    for _ in pairs(inf and inf.quests or {}) do nq = nq + 1 end
    r.cols.quests:SetText(inf and nq or "|cff555555-|r")
    r.cols.oasis:SetText(m.me and L["du"] or (inf and inf.oasis and ("|cff7fd07fOasis|r " .. (inf.ver or ""))) or ("|cff666666" .. L["ohne Oasis"] .. "|r"))
    r.talents.who = m.name
    r.talents:SetShown(ns.Talents ~= nil and not m.me)
end

-- Quests: alle Quests der Gruppe, wer sie hat, wer sie fehlt
local function questRows()
    local mine = myQuests()
    local all = {}
    for _, m in ipairs(P.Members()) do
        local qs = m.me and mine or (m.info and m.info.quests) or {}
        for qid, q in pairs(qs) do
            local e = all[qid]
            if not e then e = { id = qid, have = {}, push = {} } all[qid] = e end
            e.have[#e.have + 1] = m.short
            if q.p and not m.me then e.push[#e.push + 1] = m.name end
        end
    end
    local out = {}
    for qid, e in pairs(all) do
        e.title = questTitle(qid)
        e.mine = mine[qid] ~= nil
        out[#out + 1] = e
    end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return not a.mine end      -- erst die, die mir fehlen
        if #a.have ~= #b.have then return #a.have > #b.have end
        return a.title < b.title
    end)
    return out
end
local function questRow(l)
    local r = K.Row(l)
    r:Col("title", 12, 300, 13)
    r:Col("have", 320, 330, 11, C.muted)
    r.btn = K.Button(r, L["Bitte teilen"], 110, 20, "ghost", function(self)
        if self.target and self.qid then P.AskShare(self.target, self.qid) end
    end)
    r.btn:SetPoint("RIGHT", -8, 0)
    return r
end
local function questUpdate(r, e)
    r.cols.title:SetText(e.title)
    r.cols.title:SetTextColor((e.mine and C.muted or C.text)[1], (e.mine and C.muted or C.text)[2], (e.mine and C.muted or C.text)[3])
    r.cols.have:SetText((e.mine and (L["Du hast sie"] .. " - ") or "") .. table.concat(e.have, ", "))
    r.btn.qid, r.btn.target = e.id, e.push[1]
    r.btn:SetShown(not e.mine and e.push[1] ~= nil)
end

local function switch(p, key)
    tab = key
    p.members:SetShown(key == "members")
    p.quests:SetShown(key == "quests")
    for _, d in ipairs(P.tabs) do if d.area then d.area:SetShown(key == d.key) end end
    ns.RefreshPage("party", true)
end

ns.ICONS.party = ns.MEDIA .. "icons\\groups"
ns.RegisterPage({
    key = "party", title = "Meine Gruppe", order = 2.72,
    sub = "Wer ist dabei, wer braucht welche Quest, Segen, Bedrohung und Wuerfelrunde",
    build = function(p)
        local items = { { key = "members", text = L["Mitglieder"] }, { key = "quests", text = L["Quests"] } }
        for _, d in ipairs(P.tabs) do items[#items + 1] = { key = d.key, text = L[d.text] } end
        p.seg = K.Segments(p, items, function(k) switch(p, k) end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.empty = K.Text(p, 13, C.dim, "CENTER")
        p.empty:SetPoint("TOP", 0, -120)
        p.empty:SetText(L["Du bist in keiner Gruppe. Sobald du einer Gruppe beitrittst, siehst du hier alle Mitglieder."])
        -- Mitglieder
        p.members = CreateFrame("Frame", nil, p)
        p.members:SetPoint("TOPLEFT", 0, -36)
        p.members:SetPoint("BOTTOMRIGHT", 0, 0)
        local hd = K.Text(p.members, 10, C.dim)
        hd:SetPoint("TOPLEFT", 30, 0)
        hd:SetText(K.Upper(L["Name"]))
        for _, h in ipairs({ { 205, "Stufe" }, { 262, "Erfahrung" }, { 460, "Itemlevel" }, { 525, "Quests" }, { 600, "Addon" } }) do
            local t = K.Text(p.members, 10, C.dim) t:SetPoint("TOPLEFT", h[1], 0) t:SetText(K.Upper(L[h[2]]))
        end
        p.mlist = K.List(p.members, 34, memberRow, memberUpdate)
        p.mlist:SetPoint("TOPLEFT", 0, -18)
        p.mlist:SetPoint("BOTTOMRIGHT", 0, 30)
        glass(p.mlist, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.07 }, 10)
        p.sum = K.Text(p.members, 11, C.muted)
        p.sum:SetPoint("BOTTOMLEFT", 4, 8)
        -- Quests
        p.quests = CreateFrame("Frame", nil, p)
        p.quests:SetPoint("TOPLEFT", 0, -36)
        p.quests:SetPoint("BOTTOMRIGHT", 0, 0)
        local qh = K.Text(p.quests, 11, C.muted)
        qh:SetPoint("TOPLEFT", 4, 0)
        qh:SetText(L["Oben die Quests, die dir fehlen. 'Bitte teilen' fragt ein Gruppenmitglied mit Oasis - es muss nur noch klicken."])
        p.qlist = K.List(p.quests, 30, questRow, questUpdate)
        p.qlist:SetPoint("TOPLEFT", 0, -22)
        p.qlist:SetPoint("BOTTOMRIGHT", 0, 0)
        glass(p.qlist, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.07 }, 10)
        -- weitere Reiter
        for _, d in ipairs(P.tabs) do
            d.area = CreateFrame("Frame", nil, p)
            d.area:SetPoint("TOPLEFT", 0, -36)
            d.area:SetPoint("BOTTOMRIGHT", 0, 0)
            local ok, e = pcall(d.build, p, d.area)
            if not ok then ns.err("Gruppe " .. d.key, e) end
        end
        p.seg:Select(tab)
        switch(p, tab)
        P.Send()
    end,
    refresh = function(p)
        local grouped = IsInGroup()
        local m = P.Members()
        local own = (tab == "members" or tab == "quests")
        p.empty:SetShown(own and not grouped)
        p.members:SetShown(tab == "members" and grouped)
        p.quests:SetShown(tab == "quests" and grouped)
        if tab == "members" and grouped then
            p.mlist:SetData(m)
            local oasis, sum, cnt = 0, 0, 0
            for _, x in ipairs(m) do
                if x.me or (x.info and x.info.oasis) then oasis = oasis + 1 end
                if x.info and x.info.ilvl and x.info.ilvl > 0 then sum, cnt = sum + x.info.ilvl, cnt + 1 end
            end
            p.sum:SetText((L["%d Mitglieder, %d mit Oasis"]):format(#m, oasis) .. (cnt > 0 and ("  -  " .. (L["Itemlevel im Schnitt %d"]):format(math.floor(sum / cnt + 0.5))) or ""))
        elseif tab == "quests" and grouped then
            local rows = questRows()
            p.qlist:SetData(rows)
            p.qlist.empty:SetText(#rows == 0 and L["Noch keine Quests bekannt - die anderen brauchen Oasis."] or "")
        end
        for _, d in ipairs(P.tabs) do
            if d.key == tab and d.refresh then local ok, e = pcall(d.refresh, p, d.area) if not ok then ns.err("Gruppe " .. d.key, e) end end
        end
    end,
})
-- in die Navigation unter "Zusammen spielen"
for _, g in ipairs(ns.NAV_GROUPS or {}) do
    if g.key == "play" then
        local has = false
        for _, k in ipairs(g.pages) do if k == "party" then has = true end end
        if not has then table.insert(g.pages, 2, "party") end
    end
end
ns.slash.gruppe = function() if ns.Expand then ns.Expand("party") else ns.ShowPage("party") end end
ns.slash.party = ns.slash.gruppe

end)

-- Einstellungen der Seite "Meine Gruppe"
ns.ModuleFile("Oasis_Gruppe", function()
local L, K = ns.L, ns.K
if not ns.AddPageSettings then return end
ns.AddPageSettings("party", function(det, y)
    local S = ns.db.settings
    local defs = {
        { "Gruppen-XP-Leiste", "partyXP", "Kleine Leiste mit dem Erfahrungsbalken jedes Gruppenmitglieds mit Oasis (5er-Gruppe)", true, function() if ns.Party.UpdateXP then ns.Party.UpdateXP() end end },
        { "Pull-Warnung", "pullWarn", "Hinweis, wenn du vor dem Tank in den Kampf kommst oder als Nicht-Tank die Aggro hast", true },
        { "Bedrohungsleiste", "threatBar", "Deine Bedrohung auf dem Ziel in Prozent (nur wenn das Spiel den Wert liefert)", true },
        { "Gebiet und Stufe im Chat", "chatZones", "Vor Gilden-, Gruppen- und Raidzeilen steht klein Stufe und Gebiet der Person", false },
    }
    for _, d in ipairs(defs) do
        local t = K.Toggle(det, L[d[1]], function() if d[4] then return S[d[2]] ~= false end return S[d[2]] == true end, function(v)
            if d[4] then S[d[2]] = (not v) and false or nil else S[d[2]] = v and true or nil end
            if d[5] then d[5]() end
        end, L[d[3]])
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        if det.t then det.t[#det.t + 1] = t end
        y = y - 44
    end
    return y - 10
end)
end)

-- Oasis: Beute verteilen (Master-Loot) - ersetzt Gargul / RCLootCouncil fuer die Gilde
--  * Plundermeister/Anfuehrer startet eine Runde mit ALLEN Items einer Leiche (oder per /oa beute [Link])
--  * Jeder im Raid bekommt ein kompaktes Wahlfenster: Bedarf / Zweitspec / Transmog / Passen (+ Notiz),
--    Klick wuerfelt dabei echt (/roll 100), Zeitbalken laeuft ab -> wer nichts waehlt, passt
--  * Reihenfolge: Soft-Reserve > Bedarf > Zweitspec > Transmog, dann Punkte (Prioritaet) bzw. Plus-Eins, dann Wurf
--  * Beuterat (Gilden-Option): Offiziere stimmen je Item ab, der Plundermeister vergibt
--  * Vergeben gibt das Item direkt per Master-Loot weiter (sonst: Merkliste zum Handeln)
--  * Alles landet im Beute-Verlauf (Store "loot") und bucht Punkte (LootPoints), Plus-Eins zaehlt je Raidabend
-- Aufbau angelehnt an das, was sich bewaehrt hat: links Item-Reiter, rechts Bewerbertabelle mit Spalten
-- (Name, Rang, Wahl, Wurf, +1/Punkte, getragene Items, Stimmen, Notiz); fuer Mitglieder ein schmales Wurf-Fenster.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
-- ns.Group kommt aus Kern\Diagnose\RaidSim.lua; fehlt die Datei, gelten die echten Blizzard-Abfragen
if not ns.Group then ns.Group = { IsSim = function() return false end, IsInGroup = function() return (IsInGroup and IsInGroup()) and true or false end, IsInRaid = function() return (IsInRaid and IsInRaid()) and true or false end, Num = function() return (GetNumGroupMembers and GetNumGroupMembers()) or 0 end, InInstance = function() if IsInInstance then return IsInInstance() end return false, "none" end, Instance = function() return nil end, Members = function() return {} end, Member = function() return nil end, IsLeader = function() return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false end, IsAssist = function() return false end } end
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store

local LM = {}
ns.LootMaster = LM
local function simOn() return ns.Sim and ns.Sim.Active() or false end

------------------------------------------------------------------------
-- Sicherheit beim Empfang: Addon-Nachrichten anderer koennen manipuliert sein
-- (Texte entschaerfen, Zahlen begrenzen, Absender pruefen, Flut drosseln)
------------------------------------------------------------------------
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape-Sequenzen (|c |r |n |H |T |K |A ...) und Steuerzeichen unschaedlich machen; links: gueltige Item-/Zauberlinks bleiben
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
    -- genau ein gueltiger Itemlink (sonst nil)
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
LM.SEC = SEC
local GROUP_CH = { RAID = true, PARTY = true, INSTANCE_CHAT = true, RAID_WARNING = true }
-- Absender in meiner Gruppe? (Simulator: Sim-Mitglieder; ohne RaidSim.lua: Blizzard-Abfrage)
local function inMyGroup(name)
    if not name then return false end
    if simOn() then return ns.Group.Member(name) ~= nil end
    if ns.Group.Member(name) then return true end
    local s = ns.short(name)
    if (UnitInRaid and UnitInRaid(s)) or (UnitInParty and UnitInParty(s)) then return true end
    return false
end
-- darf der Absender eine Beute-Runde starten? (Anfuehrer/Assistent/Plundermeister der eigenen Gruppe)
local function mayLead(name)
    if simOn() then return ns.Group.IsAssist(name) end
    if ns.Group.IsAssist and ns.Group.IsAssist(name) then return true end
    if ns.Group.IsLeader and ns.Group.IsLeader(name) then return true end
    local ok, method, partyID, raidID = pcall(function()
        if C_PartyInfo and C_PartyInfo.GetLootMethod then return C_PartyInfo.GetLootMethod() end
        if GetLootMethod then return GetLootMethod() end
    end)
    if ok and (method == "master" or method == 2) then
        local u = raidID and ("raid" .. raidID) or (partyID and partyID > 0 and ("party" .. partyID)) or nil
        local n = u and UnitName and ns.safe(ns.UnitName(u))
        if n and ns.short(n) == ns.short(name) then return true end
    end
    return false
end
LM.InMyGroup, LM.MayLead = inMyGroup, mayLead
local MODES = { roll = true, points = true, council = true, gdkp = true }

ns.GuildOption({ page = "raid", key = "lmMode", default = "roll", kind = "choice",
    label = "Beute-Verteilung", desc = "Wuerfeln: Reihenfolge Bedarf > Zweitspec > Transmog, dann Wurf. Punkte: Prioritaet aus den Beutepunkten entscheidet. Beuterat: Offiziere stimmen ab, der Plundermeister vergibt.",
    choices = { { key = "roll", text = "Wuerfeln" }, { key = "points", text = "Punkte" }, { key = "council", text = "Beuterat" }, { key = "gdkp", text = "GDKP (Gold-Gebote)" } } })
ns.GuildOption({ page = "raid", key = "lmGMin", default = 10, min = 1, max = 1000, step = 1,
    label = "GDKP: Mindestgebot", desc = "Erstes Gebot je Item in Gold.", fmt = function(v) return v .. " g" end })
ns.GuildOption({ page = "raid", key = "lmGInc", default = 5, min = 1, max = 500, step = 1,
    label = "GDKP: Erhoehung", desc = "Um so viel Gold muss jedes neue Gebot hoeher sein.", fmt = function(v) return v .. " g" end })
ns.GuildOption({ page = "raid", key = "lmGCut", default = 0, min = 0, max = 50, step = 1,
    label = "GDKP: Anteil Gildenbank", desc = "So viel Prozent vom Topf gehen vor dem Aufteilen an die Gildenbank.", fmt = function(v) return v .. " %" end })
ns.GuildOption({ page = "raid", key = "lmTimer", default = 60, min = 20, max = 180, step = 10,
    label = "Bedenkzeit", desc = "So lange hat jeder Zeit zu waehlen. Wer nichts waehlt, passt.",
    fmt = function(v) return v .. " s" end })
ns.GuildOption({ page = "raid", key = "lmPlus", default = true,
    label = "Plus-Eins", desc = "Wer an einem Abend schon ein Item mit Bedarf bekommen hat, rutscht bei Bedarf hinter alle ohne Item (gleicher Wurf-Rang)." })
ns.GuildOption({ page = "raid", key = "lmSR", default = true,
    label = "Soft-Reserve zuerst", desc = "Wer ein Item fuer den Termin reserviert hat, kommt bei Bedarf vor allen anderen." })
ns.GuildOption({ page = "raid", key = "lmCouncil", default = 1, min = 0, max = 9, step = 1,
    label = "Beuterat ab Rang", desc = "Diese Gildenraenge (0 = Gildenmeister) duerfen im Beuterat abstimmen.",
    fmt = function(v) return (ns.L["bis Rang %d"]):format(v) end })
ns.GuildOption({ page = "raid", key = "lmMinQ", default = "3", kind = "choice",
    label = "Ab Qualitaet", desc = "Items ab dieser Qualitaet kommen in die Verteilung.",
    choices = { { key = "2", text = "Selten (gruen)" }, { key = "3", text = "Rar (blau)" }, { key = "4", text = "Episch" } } })

local CHOICES = {
    { key = "ms", text = "Bedarf", short = "Bedarf", color = C.mint, order = 1 },
    { key = "os", text = "Zweitspec", short = "Zweit", color = C.blue, order = 2 },
    { key = "tm", text = "Transmog", short = "Mog", color = C.amber, order = 3 },
    { key = "pass", text = "Passen", short = "Passen", color = C.dim, order = 9 },
}
local CH = {}
for _, c in ipairs(CHOICES) do CH[c.key] = c end

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local function equippedFor(link)
    local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return "", "" end
    local out = {}
    for _, s in ipairs(SLOTS[loc or ""] or {}) do
        local l = GetInventoryItemLink("player", s)
        if l then out[#out + 1] = l:match("item:(%d+)") end
    end
    return out[1] or "", out[2] or ""
end
local function itemID(link) return tonumber(tostring(link or ""):match("item:(%d+)")) end
local function mainOf(n) return ns.Alts and ns.Alts.Main and ns.Alts.Main(n) or n end
local function today() return date("%Y-%m-%d") end

------------------------------------------------------------------------
-- Wer darf was
------------------------------------------------------------------------
function LM.Mode() return tostring(ns.GuildOpt("lmMode") or "roll") end
function LM.IsCouncil(name)
    name = name or ns.me()
    if LM.session and ns.isMe(LM.session.leader) and ns.isMe(name) then return true end
    local ri = ns.Admin and ns.Admin.RankOf and ns.Admin.RankOf(name)
    return ri ~= nil and ri <= (tonumber(ns.GuildOpt("lmCouncil")) or 1)
end
local function isLeader() local s = LM.session return s and ns.isMe(s.leader) end

------------------------------------------------------------------------
-- Plus-Eins: Bedarf-Gewinne je Main und Abend (alle Clients zaehlen mit, ueber LMAWARD)
------------------------------------------------------------------------
local function plusTable()
    ns.db.lmPlus = ns.db.lmPlus or {}
    local d = today()
    if ns.db.lmPlus.day ~= d then ns.db.lmPlus = { day = d, n = {} } end
    return ns.db.lmPlus.n
end
function LM.Plus(name) return plusTable()[mainOf(name)] or 0 end

------------------------------------------------------------------------
-- Rangfolge eines Items
------------------------------------------------------------------------
function LM.Ranked(it)
    local list = {}
    local mode = (LM.session and LM.session.mode) or LM.Mode()
    if mode == "gdkp" then
        for name, bid in pairs(it.bids or {}) do
            list[#list + 1] = { name = name, r = it.resp[name] or {}, choice = "ms", roll = 0, bid = bid, plus = 0, pr = 0, votes = 0 }
        end
        table.sort(list, function(a, b) if a.bid ~= b.bid then return a.bid > b.bid end return a.name < b.name end)
        return list
    end
    local srOn = ns.GuildOpt("lmSR") ~= false
    local plusOn = ns.GuildOpt("lmPlus") ~= false
    local srSet = {}
    if srOn and ns.SoftRes and ns.SoftRes.ForItem then
        for _, who in ipairs(ns.SoftRes and ns.SoftRes.ForItem(itemID(it.link)) or {}) do srSet[who] = true end
    end
    for name, r in pairs(it.resp) do
        local e = { name = name, r = r, choice = r.c, roll = r.roll or 0 }
        e.sr = srSet[mainOf(name)] and r.c == "ms"
        e.plus = LM.Plus(name)
        e.pr = ns.Points and ns.Points.Of and ns.Points.Of(name).pr or 0
        local votes = 0
        for _ in pairs(it.votes[name] or {}) do votes = votes + 1 end
        e.votes = votes
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        local oa, ob = (CH[a.choice] or CH.pass).order, (CH[b.choice] or CH.pass).order
        if (a.sr and 1 or 0) ~= (b.sr and 1 or 0) then return a.sr end
        if oa ~= ob then return oa < ob end
        if mode == "council" and a.votes ~= b.votes then return a.votes > b.votes end
        if mode == "points" and a.choice == "ms" and math.abs(a.pr - b.pr) > 0.0001 then return a.pr > b.pr end
        if plusOn and a.choice == "ms" and a.plus ~= b.plus then return a.plus < b.plus end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.name < b.name
    end)
    return list
end

------------------------------------------------------------------------
-- Beute-Statistik je Spieler (aus dem Beute-Verlauf, Main + Twinks zusammen)
------------------------------------------------------------------------
function LM.Stats(name)
    local main = mainOf(name)
    local st = { total = 0, ms = 0, os = 0, tm = 0, d30 = 0, last = nil, lastTs = 0, items = {} }
    local cut = ns.now() - 30 * 86400
    for _, r in ipairs(Store.List("loot")) do
        if r.who and mainOf(r.who) == main and (r.src == "Vergabe" or r.choice) then
            st.total = st.total + 1
            local c = r.choice or "ms"
            if st[c] then st[c] = st[c] + 1 end
            if (r.ts or 0) > cut then st.d30 = st.d30 + 1 end
            if (r.ts or 0) > st.lastTs then st.last, st.lastTs = r.item, r.ts or 0 end
            st.items[#st.items + 1] = r
        end
    end
    table.sort(st.items, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return st
end
function LM.StatsTip(lines, name)
    local st = LM.Stats(name)
    lines[#lines + 1] = (L["Beute: %d gesamt  ·  %d in 30 Tagen"]):format(st.total, st.d30)
    lines[#lines + 1] = "|cff66db9e" .. (L["Bedarf %d"]):format(st.ms) .. "|r  |cff6199ff" .. (L["Zweitspec %d"]):format(st.os) .. "|r  |cffe8b44a" .. (L["Transmog %d"]):format(st.tm) .. "|r"
    for k, r in ipairs(st.items) do
        if k > 4 then break end
        lines[#lines + 1] = "|cff888888" .. date(L["%d.%m."], r.ts or 0) .. "|r  " .. (r.item or "?")
    end
    return lines
end

------------------------------------------------------------------------
-- GDKP: Gebote in Gold, Topf, Auszahlung
------------------------------------------------------------------------
local function gdkpPot()
    ns.db.gdkp = ns.db.gdkp or {}
    local d = date("%Y-%m-%d")
    if ns.db.gdkp.day ~= d then ns.db.gdkp = { day = d, sales = {} } end
    return ns.db.gdkp
end
function LM.Pot()
    local pot, sum = gdkpPot(), 0
    for _, s in ipairs(pot.sales) do sum = sum + (s.gold or 0) end
    local cut = math.floor(sum * (tonumber(ns.GuildOpt("lmGCut")) or 0) / 100)
    local n = math.max(1, ns.Group.IsInGroup() and ns.Group.Num() or 1)
    return sum, cut, n, math.floor((sum - cut) / n)
end
function LM.MinBid(it)
    local hi = 0
    for _, b in pairs(it.bids or {}) do if b > hi then hi = b end end
    if hi == 0 then return tonumber(ns.GuildOpt("lmGMin")) or 10, 0 end
    return hi + (tonumber(ns.GuildOpt("lmGInc")) or 5), hi
end
local function gotBid(name, i, amount)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner or s.closed then return end
    amount = SEC.Num(amount, 1, 10000000, true)
    if not amount then return end
    it.bids[name] = math.max(it.bids[name] or 0, amount)
    -- spaete Gebote verlaengern die Runde (wie bei Auktionen)
    if s.ends - GetTime() < 10 then s.ends = GetTime() + 10 end
    LM.Refresh()
end
function LM.Bid(i, amount)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner or s.closed then return end
    local min = LM.MinBid(it)
    amount = math.floor(tonumber(amount) or min)
    if amount < min then ns.print((L["Mindestens %d Gold."]):format(min)) return end
    gotBid(ns.me(), i, amount)
    it.mine = "bid"
    Comm.Group("LMBID", s.sid, i, amount)
end
Comm.On("LMBID", function(sender, _, sid, i, amount)
    local s = LM.session
    if not s or s.sid ~= sid or ns.isMe(sender) or s.mode ~= "gdkp" then return end
    if not s.sim and not inMyGroup(sender) then return end   -- nur Mitspieler der eigenen Gruppe bieten
    gotBid(sender, SEC.Num(i, 1, 40, true), amount)
end)
function LM.PostPayout()
    local ch = ns.groupChannel()
    if not ch then return end
    local sum, cut, n, each = LM.Pot()
    ns.SendChat((L["[Oasis] GDKP-Topf: %d g, Gildenbank %d g, %d Spieler - je %d g"]):format(sum, cut, n, each), ch)
end

------------------------------------------------------------------------
-- Runde starten / beenden
------------------------------------------------------------------------
local function newSession(sid, leader, mode, timer)
    LM.session = { sid = sid, leader = leader, mode = mode, items = {}, ends = GetTime() + timer, timer = timer, started = ns.now() }
    LM.pendingRolls = {}
    return LM.session
end
local function addItem(s, i, link, slot)
    s.items[i] = { link = link, slot = slot, resp = {}, votes = {}, bids = {}, mine = nil }
end

-- items = { {link=, slot=}, ... }
function LM.Start(items)
    if not items or #items == 0 then return end
    if not ns.Group.IsInGroup() then ns.print(L["Du bist in keiner Gruppe."]) return end
    if not ns.isGroupLead() and not LM.IsMasterLooter() then ns.print(L["Nur Plundermeister, Anfuehrer oder Assistenten koennen verteilen."]) return end
    if LM.session and not LM.session.closed then LM.End() end
    local timer = tonumber(ns.GuildOpt("lmTimer")) or 60
    local s = newSession(tostring(math.random(100000, 999999)), ns.me(), LM.Mode(), timer)
    s.sim = simOn() or nil
    Comm.Group("LMSTART", s.sid, s.mode, timer, #items)
    for i, it in ipairs(items) do
        addItem(s, i, it.link, it.slot)
        Comm.Group("LMITEM", s.sid, i, it.link)
    end
    local ch = ns.groupChannel()
    if ch then
        local links = {}
        for _, it in ipairs(items) do links[#links + 1] = it.link end
        ns.SendChat((L["[Oasis] Verteilung (%d s): "]):format(timer) .. table.concat(links, " "):sub(1, 200), ns.Group.IsInRaid() and "RAID_WARNING" or ch)
    end
    LM.ShowRoll()
    LM.ShowMaster()
end
ns.slash.beute = function(rest)
    local items = {}
    for link in tostring(rest or ""):gmatch("|c%x+|Hitem:.-|h.-|h|r") do items[#items + 1] = { link = link } end
    if #items == 0 then LM.ShowMaster() return end
    LM.Start(items)
end

function LM.End()
    local s = LM.session
    if not s then return end
    s.closed = true
    if isLeader() then Comm.Group("LMEND", s.sid) end
    if LM.rollWin then LM.rollWin:Hide() end
    LM.Refresh()
end

Comm.On("LMSTART", function(sender, channel, sid, mode, timer, n)
    if ns.isMe(sender) then return end
    -- nur ueber den Gruppenkanal, nur Anfuehrer/Assistent/Plundermeister der eigenen Gruppe
    if not GROUP_CH[channel or ""] or not inMyGroup(sender) or not mayLead(sender) then return end
    sid = tostring(sid or "")
    if not sid:match("^%d+$") or #sid > 12 then return end
    -- laufende Runde eines anderen Verteilers nicht kapern
    local cur = LM.session
    if cur and not cur.closed and cur.leader ~= sender and GetTime() < (cur.ends or 0) and mayLead(cur.leader) then return end
    newSession(sid, sender, MODES[mode] and mode or "roll", SEC.Num(timer, 10, 300) or 60)
end)
Comm.On("LMITEM", function(sender, _, sid, i, link)
    local s = LM.session
    if not s or s.sid ~= sid or ns.isMe(sender) then return end
    if not (ns.Admin and ns.Admin.SameName and ns.Admin.SameName(sender, s.leader) or sender == s.leader) then return end   -- nur der Verteiler selbst
    i, link = SEC.Num(i, 1, 40, true), SEC.Link(link)
    if not i or not link then return end
    addItem(s, i, link)
    -- kurz sammeln, dann Fenster zeigen
    if LM.showTimer then LM.showTimer:Cancel() end
    LM.showTimer = C_Timer.NewTimer(0.4, function()
        LM.ShowRoll()
        if LM.IsCouncil() and s.mode == "council" then LM.ShowMaster() end
    end)
end)
Comm.On("LMEND", function(sender, _, sid)
    local s = LM.session
    if s and s.sid == sid and (ns.Admin and ns.Admin.SameName and ns.Admin.SameName(sender, s.leader) or sender == s.leader) then s.closed = true if LM.rollWin then LM.rollWin:Hide() end LM.Refresh() end
end)

------------------------------------------------------------------------
-- Antworten, Wuerfe, Stimmen
------------------------------------------------------------------------
local function takeRoll(name, it)
    local q = LM.pendingRolls[name]
    if q and #q > 0 then it.resp[name].roll = table.remove(q, 1) return true end
end
local function gotResp(name, i, choice, e1, e2, note)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner then return end
    it.resp[name] = { c = choice, e1 = e1 or "", e2 = e2 or "", note = note or "", t = GetTime() }
    if choice ~= "pass" then takeRoll(name, it) end
    LM.Refresh()
end
function LM.Choose(i, choice)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner or s.closed then return end
    it.mine = choice
    local e1, e2 = equippedFor(it.link)
    local note = LM.rollWin and LM.rollWin.note and LM.rollWin.note:GetText() or ""
    note = note:gsub("[|%c]", " ")
    -- echter Wurf (Klick = Tastendruck, darum erlaubt)
    local simRoll
    if choice ~= "pass" then
        if s.sim then
            -- Raid-Simulator: nur lokal wuerfeln, kein /roll im Chat
            simRoll = math.random(1, 100)
            ns.print((L["Raid-Sim: du wuerfelst %d"]):format(simRoll))
        else
            local roll = RandomRoll or (C_RandomRoll and C_RandomRoll.RandomRoll)
            if roll then pcall(roll, 1, 100) end
        end
    end
    gotResp(ns.me(), i, choice, e1, e2, note)
    if simRoll and it.resp[ns.me()] then it.resp[ns.me()].roll = simRoll LM.Refresh() end
    Comm.Group("LMRESP", s.sid, i, choice, e1, e2, note:sub(1, 60))
    LM.RefreshRoll()
end
Comm.On("LMRESP", function(sender, _, sid, i, choice, e1, e2, note)
    local s = LM.session
    if not s or s.sid ~= sid or ns.isMe(sender) or s.closed then return end
    if not s.sim and not inMyGroup(sender) then return end   -- nur Mitspieler, niemand "im Namen" anderer
    if not CH[choice or ""] then return end
    local function iid(v) v = tostring(v or "") return v:match("^%d+$") and #v <= 9 and v or "" end
    gotResp(sender, SEC.Num(i, 1, 40, true), choice, iid(e1), iid(e2), SEC.Text(note, 60))
end)

-- Wuerfe aus dem Systemchat (nur 1-100) dem naechsten offenen Wunsch des Spielers zuordnen
local rollPats
local function buildPats()
    rollPats = {}
    for _, fmt in ipairs({ RANDOM_ROLL_RESULT or "", "%s rolls %d (%d-%d)", "%s würfelt. Ergebnis: %d (%d-%d)" }) do
        if fmt ~= "" then
            local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
            rollPats[#rollPats + 1] = "^" .. p .. "$"
        end
    end
end
ns.On("CHAT_MSG_SYSTEM", function(text)
    local s = LM.session
    if not s or s.closed then return end
    text = ns.safe(text)
    if not text then return end
    if not rollPats then buildPats() end
    local who, roll, lo, hi
    for _, p in ipairs(rollPats) do who, roll, lo, hi = text:match(p) if who then break end end
    if not who or tonumber(lo) ~= 1 or tonumber(hi) ~= 100 then return end
    local name = ns.fullName(who)
    roll = SEC.Num(roll, 1, 100, true)
    if not name or not roll then return end
    -- an das erste Item mit Wunsch, aber ohne Wurf
    for _, it in ipairs(s.items) do
        local r = it.resp[name]
        if not r then
            for n, rr in pairs(it.resp) do if ns.isMe(n) and ns.isMe(name) then r = rr name = n break end end
        end
        if r and r.c ~= "pass" and not r.roll and not it.winner then r.roll = roll LM.Refresh() return end
    end
    -- nur Mitspieler; je Spieler hoechstens so viele Wuerfe vormerken, wie Items in der Runde sind
    if not s.sim and not inMyGroup(name) then return end
    LM.pendingRolls[name] = LM.pendingRolls[name] or {}
    if #LM.pendingRolls[name] >= math.max(1, #s.items) then return end
    table.insert(LM.pendingRolls[name], roll)
end)

function LM.Vote(i, cand)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner or not LM.IsCouncil() then return end
    it.votes[cand] = it.votes[cand] or {}
    local on = not it.votes[cand][ns.me()]
    it.votes[cand][ns.me()] = on or nil
    Comm.Group("LMVOTE", s.sid, i, cand, on and "1" or "0")
    LM.Refresh()
end
Comm.On("LMVOTE", function(sender, _, sid, i, cand, on)
    local s = LM.session
    local it = s and s.sid == sid and s.items[tonumber(i)]
    if not it or ns.isMe(sender) or not LM.IsCouncil(sender) then return end
    if not it.resp[cand or ""] then return end   -- nur fuer echte Bewerber
    it.votes[cand] = it.votes[cand] or {}
    it.votes[cand][sender] = (on == "1") or nil
    LM.Refresh()
end)

------------------------------------------------------------------------
-- Raid-Simulator: Beute-Runde mit simulierten Antworten, Wuerfen und Stimmen (alles lokal)
------------------------------------------------------------------------
function LM.SimRound(items)
    if not simOn() or not items or #items == 0 then return end
    LM.Start(items)
    local s = LM.session
    if not s or not s.sim then return end
    local officers = {}
    for _, m in ipairs(ns.Group.Members()) do if m.isAssist and not m.isMe then officers[#officers + 1] = m.name end end
    local span = math.min(20, (s.timer or 60) * 0.5)
    for i, it in ipairs(s.items) do
        for _, m in ipairs(ns.Group.Members()) do
            if not m.isMe and m.online and not m.afk then
                ns.After(1 + math.random() * span, function()
                    if LM.session ~= s or s.closed or it.winner then return end
                    local x = math.random()
                    local choice = x < 0.3 and "ms" or (x < 0.45 and "os" or (x < 0.55 and "tm" or "pass"))
                    if s.mode == "gdkp" then
                        if choice ~= "pass" and math.random() < 0.5 then gotBid(m.name, i, LM.MinBid(it)) end
                        return
                    end
                    gotResp(m.name, i, choice, "", "", "")
                    if choice ~= "pass" and it.resp[m.name] then it.resp[m.name].roll = math.random(1, 100) end
                    if s.mode == "council" and choice == "ms" and math.random() < 0.5 then
                        it.votes[m.name] = it.votes[m.name] or {}
                        for _, o in ipairs(officers) do if math.random() < 0.6 then it.votes[m.name][o] = true end end
                    end
                    LM.Refresh()
                end)
            end
        end
    end
end

------------------------------------------------------------------------
-- Vergeben
------------------------------------------------------------------------
function LM.IsMasterLooter()
    local ok, method, partyID, raidID = pcall(function()
        if C_PartyInfo and C_PartyInfo.GetLootMethod then return C_PartyInfo.GetLootMethod() end
        return GetLootMethod()
    end)
    if not ok then return false end
    if method ~= "master" and method ~= 2 then return false end
    if partyID == 0 then return true end
    if raidID and UnitIsUnit and UnitIsUnit("raid" .. raidID, "player") then return true end
    return false
end
-- Item per Master-Loot uebergeben, wenn das Beutefenster noch offen ist
local function giveLoot(link, name)
    if not (GetNumLootItems and GiveMasterLoot and GetMasterLootCandidate) then return false end
    for slot = 1, (GetNumLootItems() or 0) do
        if GetLootSlotLink(slot) == link then
            for ci = 1, 40 do
                local cand = GetMasterLootCandidate(slot, ci)
                if cand and (ns.isMe(name) and UnitIsUnit(cand, "player") or ns.short(ns.fullName(cand)) == ns.short(name)) then
                    local ok = pcall(GiveMasterLoot, slot, ci)
                    return ok
                end
            end
        end
    end
    return false
end
LM.toTrade = {}
function LM.Award(i, name, why)
    local s = LM.session
    local it = s and s.items[i]
    if not it or it.winner or not isLeader() then return end
    local r = it.resp[name]
    local choice = r and r.c or "ms"
    it.winner, it.wchoice = name, choice
    local gold = s.mode == "gdkp" and it.bids and it.bids[name] or nil
    if s.sim then
        -- Raid-Simulator: nichts uebergeben, keine Punkte/Plus-Eins buchen, Beute-Eintrag nur lokal (demo-sim-ID)
        Store.merge("loot", { id = "demo-sim-lm-" .. s.sid .. "-" .. i, sim = true, item = it.link, who = name, src = "Vergabe", choice = choice,
            roll = r and r.roll or nil, gold = gold, why = why, zone = L["Raid-Sim"], mapID = 0, ts = ns.now(), u = ns.now(), by = ns.me(), quality = 4 })
        ns.SendChat(L["[Oasis] "] .. it.link .. " > " .. ns.short(name) .. " (" .. (gold and (gold .. " g") or L[(CH[choice] or CH.ms).text]) .. ")", "RAID")
        local open = false
        for _, x in ipairs(s.items) do if not x.winner then open = true end end
        if not open then ns.After(2, LM.End) end
        LM.Refresh()
        return
    end
    if gold then
        local pot = gdkpPot()
        pot.sales[#pot.sales + 1] = { item = it.link, who = name, gold = gold, ts = ns.now() }
    end
    local given = giveLoot(it.link, name)
    if not given and not ns.isMe(name) then LM.toTrade[#LM.toTrade + 1] = { link = it.link, who = name, t = ns.now() } end
    if not gold and ns.Points and ns.Points.CanManage and ns.Points.CanManage() and choice ~= "pass" then
        -- Wahl auf die Punkte-Begriffe abbilden (Zweitspec = "greed" -> Viertelpreis, Transmog = "mog" -> gratis)
        local pc = ({ ms = "need", os = "greed", tm = "mog" })[choice] or "need"
        local cost = ns.Points.ItemCost(it.link, pc)
        if cost and cost > 0 then ns.Points.Charge(name, cost, it.link, pc) end
    end
    Store.Put("loot", {
        id = "lm-" .. s.sid .. "-" .. i, item = it.link, who = name, src = "Vergabe", choice = choice,
        roll = r and r.roll or nil, gold = gold, why = why, zone = ns.safe(GetRealZoneText()) or "",
        mapID = C_Map.GetBestMapForUnit("player") or 0, ts = ns.now(),
        quality = select(3, C_Item.GetItemInfo(it.link)) or 0,
    })
    if choice == "ms" then plusTable()[mainOf(name)] = LM.Plus(name) + 1 end
    Comm.Group("LMAWARD", s.sid, i, name, choice)
    local ch = ns.groupChannel()
    if ch then ns.SendChat(L["[Oasis] "] .. it.link .. " > " .. ns.short(name) .. " (" .. (gold and (gold .. " g") or L[(CH[choice] or CH.ms).text]) .. ")", ch) end
    -- alles vergeben -> Runde zu
    local open = false
    for _, x in ipairs(s.items) do if not x.winner then open = true end end
    if not open then ns.After(2, LM.End) end
    LM.Refresh()
end
Comm.On("LMAWARD", function(sender, _, sid, i, name, choice)
    local s = LM.session
    local it = s and s.sid == sid and s.items[tonumber(i)]
    if not it or ns.isMe(sender) then return end
    if not (ns.Admin and ns.Admin.SameName and ns.Admin.SameName(sender, s.leader) or sender == s.leader) then return end   -- nur der Verteiler selbst
    name = SEC.Name(name)
    if not name or not CH[choice or ""] then return end
    it.winner, it.wchoice = name, choice
    if choice == "ms" then plusTable()[mainOf(name)] = LM.Plus(name) + 1 end
    if ns.isMe(name) then K.Toast(L["Du bekommst das Item!"], it.link, C.mint) end
    LM.Refresh()
end)
-- alle offenen Items nach Rangfolge vergeben (Wuerfeln/Punkte)
function LM.AwardAll()
    local s = LM.session
    if not s or not isLeader() then return end
    for i, it in ipairs(s.items) do
        if not it.winner then
            local top = LM.Ranked(it)[1]
            if top and top.choice ~= "pass" then LM.Award(i, top.name, "auto") end
        end
    end
end
-- Handel-Erinnerung (wenn Master-Loot nicht direkt ging)
ns.On("TRADE_SHOW", function()
    local who = ns.safe(ns.UnitName("NPC"))
    if not who then return end
    for k = #LM.toTrade, 1, -1 do
        local t = LM.toTrade[k]
        if ns.short(t.who) == ns.short(ns.fullName(who)) then
            K.Toast(L["Noch zu uebergeben"], t.link, C.amber)
            table.remove(LM.toTrade, k)
        end
    end
end)

------------------------------------------------------------------------
-- Darstellung: gemeinsame Helfer (auch fuer Raid.lua: Meine Beute, Beute-Log, Verteilung)
------------------------------------------------------------------------
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local QHEX = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6 }
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.92, 0.92, 0.92 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
-- Qualitaet eines Items (Zahl 0..6): angegeben, aus der Item-Info oder aus der Farbe im Link
function LM.Quality(link, q)
    q = tonumber(q)
    if not q and link then
        local ok, _, _, qq = pcall(C_Item.GetItemInfo, link)
        if ok and qq ~= nil then
            if ns.safe then qq = ns.safe(qq) end
            q = tonumber(qq)
        end
    end
    if not q and type(link) == "string" then
        local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
        q = hex and QHEX[hex:lower()] or tonumber(link:match("|cnIQ(%d)") or "")
    end
    return q or 1
end
function LM.QColor(q) return QCOL[tonumber(q) or 1] or QCOL[1] end
function LM.ItemName(link) return tostring(link or ""):match("%[(.-)%]") or tostring(link or "?") end
-- Item-Knopf: Symbol mit Rahmen in Qualitaetsfarbe und weichem Schein, Tooltip, Shift-Klick = Link in den Chat
function LM.ItemButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("TOPLEFT", -3, 3)
    b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetColorTexture(1, 1, 1, 0)
    b.bg = K.Fill(b, C.field)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.edges = {}
    local E = { { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2 }, { "TOPRIGHT", "BOTTOMRIGHT", 2 } }
    for i, e in ipairs(E) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(e[1]) t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        t:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        b.edges[i] = t
    end
    b:SetScript("OnEnter", function(self) if self.link then K.ItemTip(self, self.link) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, btn)
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) return end
        if self.onClick then self.onClick(self, btn) end
    end)
    function b:SetItem(link, q)
        self.link = link
        local id = itemID(link)
        local tex = id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        self.icon:SetTexture(tex or 134400)
        local c = LM.QColor(LM.Quality(link, q))
        self.qc = c
        for _, t in ipairs(self.edges) do t:SetColorTexture(c[1], c[2], c[3], 1) end
        self.glow:SetColorTexture(c[1], c[2], c[3], 0.22)
    end
    return b
end
-- an x/y (oben links) setzen und als Rechteck merken (fuer den Ueberlappungs-Test)
local function put(rects, grp, key, o, x, y, w, h)
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", x, -y)
    if w then o:SetWidth(w) end
    if h then o:SetHeight(h) end
    if rects then rects[#rects + 1] = { grp = grp, key = key, x = x, y = y, w = w or 0, h = h or 0 } end
end
LM.Put = put
-- kleine Pille (Fuellung in Farbe, Text hell)
local function pill(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(60, 18)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.edge = p:CreateTexture(nil, "BORDER")
    p.edge:SetPoint("TOPLEFT") p.edge:SetPoint("BOTTOMLEFT") p.edge:SetWidth(2)
    p.t = K.Text(p, size or 11, C.text, "CENTER")
    p.t:SetPoint("LEFT", 6, 0) p.t:SetPoint("RIGHT", -4, 0)
    p.t:SetWordWrap(false)
    function p:Set(text, c)
        c = c or C.dim
        self.t:SetText(text or "")
        self.bg:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.9)
        self.edge:SetColorTexture(c[1], c[2], c[3], 1)
        self.t:SetTextColor(c[1] * 0.4 + 0.6, c[2] * 0.4 + 0.6, c[3] * 0.4 + 0.6)
    end
    return p
end
LM.Pill = pill
-- Farbe des Zeitbalkens: gruen -> gelb -> rot
local function timeColor(p)
    local a, b, t
    if p > 0.5 then a, b, t = C.amber, C.mint, (p - 0.5) * 2 else a, b, t = C.red, C.amber, p * 2 end
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end
LM.TimeColor = timeColor
local MODE_COL = { roll = C.blue, points = C.mint, council = C.amber, gdkp = C.amber }
local function modeText(m)
    local t = { roll = L["Wuerfeln"], points = L["Punkte"], council = L["Beuterat"], gdkp = L["GDKP"] }
    return t[m] or tostring(m or "")
end
-- mein Platz in der Rangfolge eines Items (nur wer nicht gepasst hat), sonst nil
function LM.MyPlace(it)
    if not it then return nil end
    local list = LM.Ranked(it)
    local n, mine = 0, nil
    for _, e in ipairs(list) do
        if e.choice ~= "pass" then
            n = n + 1
            if ns.isMe(e.name) then mine = n end
        end
    end
    return mine, n
end

------------------------------------------------------------------------
-- Fenster fuer alle: Wurf-Fenster mit Item-Karten und animiertem Zeitbalken
------------------------------------------------------------------------
local function window(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
    K.Border(f, C.line)
    f.topLine = f:CreateTexture(nil, "ARTWORK")
    f.topLine:SetPoint("TOPLEFT") f.topLine:SetPoint("TOPRIGHT") f.topLine:SetHeight(2)
    f.topLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    f.title = K.Title(f, 13, C.text)
    f.title:SetPoint("TOPLEFT", 12, -11)
    f.title:SetText(title)
    f.close = K.CloseButton(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    return f
end

local ROLL_W, CARD_H, CARD_GAP, ROLL_TOP = 460, 84, 6, 52
local function buildRollCard(f, i)
    local cw = ROLL_W - 24
    local r = K.Panel(f, C.panel)
    r:SetSize(cw, CARD_H)
    r.rects = {}
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetPoint("TOPLEFT") r.edge:SetPoint("BOTTOMLEFT") r.edge:SetWidth(3)
    r.shine = r:CreateTexture(nil, "BORDER")
    r.shine:SetAllPoints()
    r.shine:SetColorTexture(1, 1, 1, 0)
    r.icon = LM.ItemButton(r, 52)
    put(r.rects, "card", "icon", r.icon, 12, 14, 52, 52)
    local x0 = 76
    local tw = cw - x0 - 12
    r.name = K.Text(r, 13, C.text)
    r.name:SetWordWrap(false)
    put(r.rects, "card", "name", r.name, x0, 10, tw, 16)
    r.info = K.Text(r, 10, C.muted)
    r.info:SetWordWrap(false)
    put(r.rects, "card", "info", r.info, x0, 28, tw, 14)
    -- Wahl-Knoepfe: gleiche Breite, farbige Unterkante je Wahl
    r.btn = {}
    local bw = math.floor((tw - 3 * 4) / 4)
    for k, c in ipairs(CHOICES) do
        local b = K.Button(r, L[c.text], bw, 26, c.key == "ms" and "primary" or "ghost")
        put(r.rects, "card", "btn" .. k, b, x0 + (k - 1) * (bw + 4), 50, bw, 26)
        b.cl = b:CreateTexture(nil, "OVERLAY")
        b.cl:SetPoint("BOTTOMLEFT", 1, 1) b.cl:SetPoint("BOTTOMRIGHT", -1, 1) b.cl:SetHeight(2)
        b.cl:SetColorTexture(c.color[1], c.color[2], c.color[3], 0.9)
        b.key = c.key
        b:HookScript("OnEnter", function(self)
            local tips = { ms = L["Fuer deine Hauptspezialisierung"], os = L["Fuer die Zweitspezialisierung"], tm = L["Nur fuers Aussehen"], pass = L["Kein Interesse"] }
            K.ShowTip(self, { L[c.text], tips[c.key] or "" })
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.btn[c.key] = b
    end
    -- Ergebnis nach der Wahl: Pille mit Wahl, Wurf und Platz
    r.state = pill(r, 12)
    put(nil, "card", "state", r.state, x0, 50, tw, 26)
    -- GDKP: Hoechstgebot, Eingabe, Bieten
    r.high = K.Text(r, 11, C.amber)
    r.high:SetWordWrap(false)
    put(r.rects, "gdkp", "high", r.high, x0, 56, tw - 172, 16)
    r.bidIn = K.Input(r, 80, "")
    r.bidIn:SetNumeric(true)
    put(r.rects, "gdkp", "bidIn", r.bidIn, x0 + tw - 168, 50, 80, 26)
    r.bidBtn = K.Button(r, L["Bieten"], 84, 26, "primary")
    put(r.rects, "gdkp", "bidBtn", r.bidBtn, x0 + tw - 84, 50, 84, 26)
    f.rows[i] = r
    return r
end

function LM.ShowRoll()
    local s = LM.session
    if not s or s.closed then return end
    local f = LM.rollWin
    local fresh = false
    if not f then
        f = window("OasisLootRoll", ROLL_W, 200, L["Oasis-Beute"])
        f:SetPoint("CENTER", 0, 180)
        f.modeChip = pill(f, 10)
        f.modeChip:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
        f.modeChip:SetSize(76, 16)
        f.by = K.Text(f, 10, C.dim)
        f.by:SetPoint("LEFT", f.modeChip, "RIGHT", 8, 0)
        f.by:SetWidth(170)
        f.by:SetWordWrap(false)
        f.left = K.Title(f, 15, C.text, "RIGHT")
        f.left:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
        f.left:SetWidth(60)
        -- Zeitbalken: Spur, Fuellung (Farbe laeuft gruen -> rot), Funke an der Spitze
        local track = CreateFrame("Frame", nil, f)
        track:SetPoint("TOPLEFT", 12, -36)
        track:SetSize(ROLL_W - 24, 6)
        K.Fill(track, C.field)
        track.fill = track:CreateTexture(nil, "ARTWORK")
        track.fill:SetPoint("TOPLEFT") track.fill:SetPoint("BOTTOMLEFT")
        track.fill:SetWidth(ROLL_W - 24)
        track.fill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 1)
        track.spark = track:CreateTexture(nil, "OVERLAY")
        track.spark:SetSize(12, 16)
        track.spark:SetPoint("CENTER", track.fill, "RIGHT", 0, 0)
        track.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        pcall(track.spark.SetBlendMode, track.spark, "ADD")
        function track:Set(p)
            p = math.max(0, math.min(1, p or 0))
            self.fill:SetWidth(math.max(0.01, (ROLL_W - 24) * p))
            self.fill:SetShown(p > 0)
            local r, g, b = timeColor(p)
            self.fill:SetColorTexture(r, g, b, 1)
            self.spark:SetShown(p > 0 and p < 1 and animOn())
        end
        f.bar = track
        f.rows = {}
        f.note = K.Input(f, ROLL_W - 24, L["Notiz an den Plundermeister (optional)"])
        f:SetScript("OnUpdate", function(self, el)
            local ss = LM.session
            if not ss then return end
            local left = math.max(0, ss.ends - GetTime())
            self.bar:Set(left / math.max(1, ss.timer or 60))
            self.left:SetText(("%d s"):format(math.ceil(left)))
            -- letzte 10 Sekunden: Balken pulsiert (nur mit Animationen)
            if left > 0 and left < 10 and animOn() then
                self.pt = ((self.pt or 0) + (el or 0)) % 0.8
                self.bar.fill:SetAlpha(0.55 + 0.45 * (0.5 + 0.5 * math.cos(self.pt / 0.8 * math.pi * 2)))
                self.left:SetTextColor(C.red[1], C.red[2], C.red[3])
            else
                self.bar.fill:SetAlpha(1)
                self.left:SetTextColor(C.text[1], C.text[2], C.text[3])
            end
            if left <= 0 and not self.autoPassed then
                self.autoPassed = true
                if ss.mode ~= "gdkp" then for i, it in ipairs(ss.items) do if not it.mine and not it.winner then LM.Choose(i, "pass") end end end
            end
        end)
        LM.rollWin = f
    end
    if f.sid ~= s.sid then fresh = true f.sid = s.sid end
    f.autoPassed = false
    for _, r in ipairs(f.rows) do r:Hide() end
    f.rects = {}
    for i, it in ipairs(s.items) do
        local r = f.rows[i] or buildRollCard(f, i)
        put(f.rects, "win", "card" .. i, r, 12, ROLL_TOP + (i - 1) * (CARD_H + CARD_GAP), ROLL_W - 24, CARD_H)
        r.icon:SetItem(it.link)
        local qc = r.icon.qc or C.line
        r.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
        if ns.Upgrade and ns.Upgrade.Badge and not ns.Upgrade.Glow then pcall(ns.Upgrade.Badge, r.icon, it.link) end
        r.name:SetText(it.link)
        for key, b in pairs(r.btn) do b:SetScript("OnClick", function() LM.Choose(i, key) end) end
        r.bidBtn:SetScript("OnClick", function() LM.Bid(i, r.bidIn:GetText()) r.bidIn:ClearFocus() end)
        r.bidIn.onEnter = function() LM.Bid(i, r.bidIn:GetText()) end
        r:Show()
        if fresh then K.FadeIn(r, (i - 1) * 0.07) end
    end
    local yN = ROLL_TOP + #s.items * (CARD_H + CARD_GAP) + 2
    put(f.rects, "win", "note", f.note, 12, yN, ROLL_W - 24, 24)
    f.note:SetText("")
    f:SetHeight(yN + 24 + 12)
    f.modeChip:Set(modeText(s.mode), MODE_COL[s.mode] or C.blue)
    f.by:SetText((L["von %s"]):format(ns.displayName(s.leader or "")))
    LM.RefreshRoll()
    f:Show()
    if fresh then K.FadeIn(f, 0, 0) end
    if SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
end
function LM.RefreshRoll()
    local f, s = LM.rollWin, LM.session
    if not f or not s then return end
    local mine = ns.me()
    for i, it in ipairs(s.items) do
        local r = f.rows[i]
        if r then
            local gd = s.mode == "gdkp"
            local done = (it.mine and not gd) or it.winner
            for _, b in pairs(r.btn) do b:SetShown(not done and not gd) end
            r.bidIn:SetShown(gd and not it.winner) r.bidBtn:SetShown(gd and not it.winner) r.high:SetShown(gd and not it.winner)
            if gd and not it.winner then
                local min, hi = LM.MinBid(it)
                local hiBy
                for n, b in pairs(it.bids) do if b == hi then hiBy = n end end
                r.high:SetText(hi > 0 and (L["Hoechstgebot"] .. ": " .. (ns.isMe(hiBy) and "|cff66db9e" or "|cffe8b44a") .. hi .. " g|r  " .. ns.displayName(hiBy or ""))
                    or ("|cff888888" .. (L["ab %d g"]):format(min) .. "|r"))
                if not r.bidIn:HasFocus() then r.bidIn:SetText(tostring(min)) end
            end
            local id = itemID(it.link)
            local sr = ns.SoftRes and ns.SoftRes.ForItem and id and ns.SoftRes.ForItem(id) or {}
            local info = {}
            local up, pct
            if ns.Upgrade and ns.Upgrade.Text then
                local ok, t = pcall(ns.Upgrade.Text, it.link)
                if ok then up = t end
                if ns.Upgrade.Compare then local ok2, p = pcall(ns.Upgrade.Compare, it.link) if ok2 then pct = p end end
            end
            if up then info[#info + 1] = up end
            if ns.Upgrade and ns.Upgrade.Glow then pcall(ns.Upgrade.Glow, r.icon, (pct and pct > 0 and not it.winner) and pct or nil, not animOn()) end
            if #sr > 0 then info[#info + 1] = "|cffe8b44a" .. (L["%d reserviert"]):format(#sr) .. "|r" end
            local e1 = equippedFor(it.link)
            if e1 ~= "" then
                local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(tonumber(e1))
                info[#info + 1] = "|cff888888" .. L["du traegst"] .. "|r " .. (n or ("#" .. e1))
            end
            r.info:SetText(#info > 0 and table.concat(info, "  ·  ") or ("|cff666666" .. L["Kein Vergleich moeglich"] .. "|r"))
            local was = r.lastState
            if it.winner then
                local me = ns.isMe(it.winner)
                r.state:Set(me and (L["Gewonnen!"] .. "  " .. ns.displayName(it.winner)) or ((L["Vergeben an %s"]):format(ns.displayName(it.winner))), me and C.mint or C.dim)
                r.state:Show()
                r.lastState = "win" .. tostring(it.winner)
            elseif it.mine and not gd then
                local c = CH[it.mine] or CH.pass
                local rr = it.resp[mine]
                local parts = { L[c.text] }
                if rr and rr.roll then parts[#parts + 1] = (L["Wurf %d"]):format(rr.roll) end
                if it.mine ~= "pass" then
                    local place, n = LM.MyPlace(it)
                    if place then parts[#parts + 1] = (L["Platz %d von %d"]):format(place, n) end
                end
                r.state:Set(table.concat(parts, "  ·  "), c.color)
                r.state:Show()
                r.lastState = "mine" .. it.mine
            else
                r.state:Hide()
                r.lastState = nil
            end
            -- kurzes Aufleuchten, wenn sich das Ergebnis aendert
            if r.lastState and r.lastState ~= was and animOn() then
                local c = (it.winner and ns.isMe(it.winner)) and C.mint or (r.icon.qc or C.text)
                K.Tween(r.shine, 0.6, function(p) r.shine:SetColorTexture(c[1], c[2], c[3], 0.16 * (1 - p)) end, function() r.shine:SetColorTexture(1, 1, 1, 0) end)
            end
        end
    end
end

------------------------------------------------------------------------
-- Fenster Plundermeister / Beuterat: links Item-Leiste, oben das gewaehlte Item gross,
-- darunter Rangfolge der Bewerber (Spalten passen sich der Fensterbreite an; Fenster ziehbar/groessenveraenderbar)
------------------------------------------------------------------------
-- prio: wer zuerst wegfaellt, wenn es eng wird (hoeher = frueher weg)
local COLS = {
    { key = "pos", text = "#", w = 26, j = "CENTER", prio = 0 },
    { key = "name", text = "Name", w = 150, prio = 0 },
    { key = "choice", text = "Wahl", w = 84, prio = 0 },
    { key = "roll", text = "Wurf", w = 42, j = "CENTER", prio = 0 },
    { key = "prio", text = "+1 / Prio", w = 64, j = "CENTER", prio = 1 },
    { key = "votes", text = "Stimmen", w = 80, j = "CENTER", prio = 1, council = true },
    { key = "loot", text = "Beute 30T", w = 62, j = "CENTER", prio = 2 },
    { key = "gear", text = "Getragen", w = 64, prio = 3 },
    { key = "rank", text = "Rang", w = 84, prio = 4 },
    { key = "note", text = "Notiz", w = 110, prio = 5, flex = true },
}
local GIVE_W, RAIL_W, MIN_W, MIN_H = 64, 64, 620, 380
-- sichtbare Spalten fuer eine Listenbreite: { {key, x, w, j}, ... }
function LM.Columns(listW, council)
    local use = {}
    for _, c in ipairs(COLS) do if not c.council or council then use[#use + 1] = c end end
    local avail = listW - GIVE_W - 10
    local function sum() local s = 0 for _, c in ipairs(use) do s = s + c.w + 4 end return s end
    while sum() > avail do
        local worst, wi = -1, nil
        for i, c in ipairs(use) do if c.prio > 0 and c.prio >= worst then worst, wi = c.prio, i end end
        if not wi then break end
        table.remove(use, wi)
    end
    local out, x = {}, 0
    local extra = math.max(0, avail - sum())
    for _, c in ipairs(use) do
        local w = c.w + ((c.flex or (c.key == "name" and not use[#use].flex)) and extra or 0)
        out[#out + 1] = { key = c.key, x = x, w = w, j = c.j, text = c.text }
        x = x + w + 4
    end
    return out
end

local function buildMaster()
    local f = window("OasisLootMaster", 900, 460, L["Beute verteilen"])
    f:SetPoint("CENTER", 0, -40)
    f:SetResizable(true)
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, MIN_W, MIN_H, 1400, 900) elseif f.SetMinResize then pcall(f.SetMinResize, f, MIN_W, MIN_H) end
    f.modeChip = pill(f, 10)
    f.modeChip:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
    f.modeChip:SetSize(84, 16)
    f.mode = f.modeChip.t
    f.timer = pill(f, 11)
    f.timer:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    f.timer:SetSize(64, 18)
    f.tbar = CreateFrame("Frame", nil, f)
    f.tbar:SetHeight(2)
    f.tbar.fill = f.tbar:CreateTexture(nil, "ARTWORK")
    f.tbar.fill:SetPoint("TOPLEFT") f.tbar.fill:SetPoint("BOTTOMLEFT")
    f.tabs = {}
    -- Kopf: gewaehltes Item
    f.headCard = K.Panel(f, C.panel)
    f.headCard.edge = f.headCard:CreateTexture(nil, "ARTWORK")
    f.headCard.edge:SetPoint("TOPLEFT") f.headCard.edge:SetPoint("BOTTOMLEFT") f.headCard.edge:SetWidth(3)
    f.headCard.glow = f.headCard:CreateTexture(nil, "BORDER")
    f.headCard.glow:SetAllPoints()
    f.head = LM.ItemButton(f.headCard, 52)
    f.head:SetPoint("TOPLEFT", 12, -10)
    f.hname = K.Text(f.headCard, 15, C.text)
    f.hname:SetWordWrap(false)
    f.hinfo = K.Text(f.headCard, 11, C.muted)
    f.hinfo:SetWordWrap(false)
    f.hup = K.Text(f.headCard, 11, C.muted)
    f.hup:SetWordWrap(false)
    -- Zusammenfassung der Wahlen
    f.sum = K.Text(f, 11, C.muted)
    f.sum:SetWordWrap(false)
    -- Fussleiste
    f.awardAll = K.Button(f, L["Alle nach Regel vergeben"], 180, 24, "primary", function() LM.AwardAll() end)
    f.toMe = K.Button(f, L["An mich"], 84, 24, "ghost", function() if f.sel then LM.Award(f.sel, ns.me(), "manual") end end)
    f.endBtn = K.Button(f, L["Runde beenden"], 120, 24, "ghost", function() LM.End() end)
    f.awardAll.fw, f.toMe.fw, f.endBtn.fw = 180, 84, 120
    f.newBtn = K.Button(f, L["Items aus Beutefenster"], 170, 24, "ghost", function() LM.StartFromLoot() end)
    f.hint = K.Text(f, 10, C.dim)
    f.hint:SetWordWrap(false)
    -- GDKP-Topf: vier Kennzahlen + Auszahlung
    f.potBox = K.Panel(f, C.panel)
    f.potBox.edge = f.potBox:CreateTexture(nil, "ARTWORK")
    f.potBox.edge:SetPoint("TOPLEFT") f.potBox.edge:SetPoint("BOTTOMLEFT") f.potBox.edge:SetWidth(3)
    f.potBox.edge:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
    f.potStats = {}
    for i, lab in ipairs({ "Topf", "Gildenbank", "Spieler", "je Spieler" }) do
        local v = K.Title(f.potBox, 15, i == 4 and C.amber or C.text)
        local l = K.Text(f.potBox, 9, C.dim)
        l:SetText(K.Upper(L[lab]))
        f.potStats[i] = { v = v, l = l }
    end
    f.pot = f.potStats[1].v
    f.payout = K.Button(f.potBox, L["Auszahlung posten"], 140, 24, "ghost", function() LM.PostPayout() end)
    f.potHit = CreateFrame("Frame", nil, f.potBox)
    f.potHit:SetPoint("TOPLEFT") f.potHit:SetPoint("BOTTOMRIGHT", -150, 0)
    f.potHit:EnableMouse(true)
    f.potHit:SetScript("OnEnter", function(self)
        local lines = { L["GDKP-Topf (heute)"] }
        for k, sl in ipairs(gdkpPot().sales) do
            if k > 12 then break end
            lines[#lines + 1] = "|cffe8b44a" .. (sl.gold or 0) .. " g|r  " .. (sl.item or "?") .. "  " .. ns.displayName(sl.who or "")
        end
        if #lines == 1 then lines[2] = "|cff888888" .. L["Noch nichts verkauft."] .. "|r" end
        K.ShowTip(self, lines)
    end)
    f.potHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Spaltenkoepfe
    f.colHead = {}
    for _, c in ipairs(COLS) do
        local t = K.Text(f, 10, C.dim, c.j or "LEFT")
        t:SetText(K.Upper(L[c.text]))
        t:SetWordWrap(false)
        f.colHead[c.key] = t
    end
    f.colVer = 0
    f.list = K.List(f, 30, function(l)
        local r = K.Row(l)
        for _, c in ipairs(COLS) do
            local t = K.Text(r, 12, C.text, c.j or "LEFT")
            t:SetWordWrap(false)
            r.cols[c.key] = t
        end
        r.cols.pos:SetFont(K.FONT, 13, "OUTLINE")
        r.chip = r:CreateTexture(nil, "BORDER")
        r.chip:SetHeight(20)
        r.chipEdge = r:CreateTexture(nil, "ARTWORK")
        r.chipEdge:SetSize(2, 20)
        r.vbar = r:CreateTexture(nil, "ARTWORK")
        r.vbar:SetHeight(3)
        r.vbar:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.8)
        r.vote = K.Button(r, "+", 24, 20, "ghost")
        r.give = K.Button(r, L["Geben"], GIVE_W - 6, 22, "primary")
        r.give:SetPoint("RIGHT", -4, 0)
        -- Beute-Statistik beim Drueberfahren
        r:SetScript("OnEnter", function(self)
            local e = self.item
            if not e then return end
            K.ShowTip(self, LM.StatsTip({ ns.Radar.Colored(e.name) }, e.name))
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.gearHit = CreateFrame("Frame", nil, r)
        r.gearHit:EnableMouse(true)
        r.gearHit:SetScript("OnEnter", function(self)
            local e = r.item
            local id = e and e.r and tonumber(e.r.e1)
            if id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetItemByID(id) GameTooltip:Show() end
        end)
        r.gearHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e, idx)
        local f2 = LM.master
        local s = LM.session
        local it = s and s.items[f2.sel]
        local mode = s and s.mode
        -- Spalten an die aktuelle Breite anpassen
        if r.colVer ~= f2.colVer then
            r.colVer = f2.colVer
            for _, t in pairs(r.cols) do t:Hide() end
            for _, c in ipairs(f2.cols or {}) do
                local t = r.cols[c.key]
                t:ClearAllPoints()
                t:SetPoint("LEFT", c.x + 6, 0)
                t:SetWidth(c.w)
                t:Show()
                if c.key == "choice" then
                    r.chip:ClearAllPoints() r.chip:SetPoint("LEFT", c.x + 2, 0) r.chip:SetWidth(c.w - 4)
                    r.chipEdge:ClearAllPoints() r.chipEdge:SetPoint("LEFT", c.x + 2, 0)
                    t:ClearAllPoints() t:SetPoint("LEFT", c.x + 10, 0) t:SetWidth(c.w - 12)
                elseif c.key == "votes" then
                    r.vote:ClearAllPoints() r.vote:SetPoint("RIGHT", r, "LEFT", c.x + c.w + 4, 0)
                    r.vbar:ClearAllPoints() r.vbar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", c.x + 6, 3)
                    t:SetWidth(c.w - 28)
                elseif c.key == "gear" then
                    r.gearHit:ClearAllPoints() r.gearHit:SetPoint("LEFT", c.x + 6, 0) r.gearHit:SetSize(c.w, 22)
                end
            end
            r.hasVotes, r.hasGear = false, false
            for _, c in ipairs(f2.cols or {}) do
                if c.key == "votes" then r.hasVotes = c.w end
                if c.key == "gear" then r.hasGear = true end
            end
        end
        -- Platz: 1-3 in Gold/Silber/Bronze, Gepasste ohne Platz
        local pos = e.choice ~= "pass" and idx or nil
        local PC = { { 1, 0.82, 0.3 }, { 0.8, 0.82, 0.86 }, { 0.85, 0.55, 0.3 } }
        r.cols.pos:SetText(pos and tostring(pos) or "-")
        local pc = pos and PC[pos] or C.dim
        r.cols.pos:SetTextColor(pc[1], pc[2], pc[3])
        r.cols.name:SetText(ns.Radar.Colored(e.name) .. (e.sr and "  |cffe8b44a" .. L["SR"] .. "|r" or "") .. (ns.isMe(e.name) and "  |cff888888" .. L["(du)"] .. "|r" or ""))
        local m = ns.Radar.byName[e.name]
        r.cols.rank:SetText("|cff999999" .. (m and m.rank or "") .. "|r")
        local c = CH[e.choice] or CH.pass
        r.cols.choice:SetText(L[c.text])
        r.cols.choice:SetTextColor(c.color[1] * 0.4 + 0.6, c.color[2] * 0.4 + 0.6, c.color[3] * 0.4 + 0.6)
        r.chip:SetColorTexture(c.color[1] * 0.25, c.color[2] * 0.25, c.color[3] * 0.25, 0.9)
        r.chipEdge:SetColorTexture(c.color[1], c.color[2], c.color[3], 1)
        r.cols.roll:SetText(e.choice == "pass" and "" or (e.r.roll and tostring(e.r.roll) or "|cff666666...|r"))
        r.cols.prio:SetText(mode == "points" and ns.Points and ns.Points.FmtPR(e.pr) or ((e.plus > 0) and ("|cffff8a3d+" .. e.plus .. "|r") or "|cff6666660|r"))
        local g = {}
        for _, id in ipairs({ e.r.e1, e.r.e2 }) do
            id = tonumber(id)
            if id then
                local q = select(3, C_Item.GetItemInfo(id))
                local _, _, _, hex = GetItemQualityColor and GetItemQualityColor(q or 1)
                local lvl = select(4, C_Item.GetItemInfo(id))
                g[#g + 1] = (hex and ("|c" .. hex) or "") .. (lvl or "?") .. "|r"
            end
        end
        r.cols.gear:SetText(#g > 0 and table.concat(g, " ") or "|cff555555-|r")
        r.cols.votes:SetText(e.votes > 0 and ("|cff66db9e" .. e.votes .. "|r") or "")
        local st = LM.Stats(e.name)
        r.cols.loot:SetText(st.d30 > 0 and ("|cffe8b44a" .. st.d30 .. "|r") or "|cff5555550|r")
        if mode == "gdkp" then
            r.cols.choice:SetText((e.bid or 0) .. " g")
            r.cols.choice:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
            r.chip:SetColorTexture(C.amber[1] * 0.25, C.amber[2] * 0.25, C.amber[3] * 0.25, 0.9)
            r.chipEdge:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
            r.cols.roll:SetText("")
        end
        r.cols.note:SetText("|cff999999" .. (e.r.note or "") .. "|r")
        local voted = it and it.votes[e.name] and it.votes[e.name][ns.me()]
        local council = mode == "council"
        r.vote:SetShown(council and r.hasVotes and LM.IsCouncil() and not (it and it.winner) and e.choice ~= "pass" and true or false)
        r.vote:SetLabel(voted and "|cff66db9e" .. L["Ja"] .. "|r" or "+")
        r.vote:SetWidth(voted and 30 or 24)
        r.vote:SetScript("OnClick", function() LM.Vote(f2.sel, e.name) end)
        -- Stimmen-Balken (Anteil an der hoechsten Stimmenzahl)
        local maxV = f2.maxVotes or 0
        r.vbar:SetShown(council and r.hasVotes and e.votes > 0 and maxV > 0 and true or false)
        if r.hasVotes then r.vbar:SetWidth(math.max(2, (r.hasVotes - 34) * (e.votes / math.max(1, maxV)))) end
        r.give:SetShown(isLeader() and it and not it.winner and true or false)
        r.give:SetScript("OnClick", function() LM.Award(f2.sel, e.name, "manual") end)
        if r.sel then r.sel:SetShown(it and it.winner == e.name or false) end
        if r.stripe and it and it.winner == e.name then r.stripe:Show() end
    end)
    f.list.empty:SetText(L["Noch keine Antworten."])
    -- Ziehgriff unten rechts
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip.t = f.grip:CreateTexture(nil, "OVERLAY")
    f.grip.t:SetAllPoints()
    f.grip.t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() f:Layout() end)
    f:SetScript("OnSizeChanged", function(self) if self.Layout then self:Layout() end end)
    f:SetScript("OnUpdate", function(self, el)
        local s = LM.session
        if s and not s.closed then
            local left = math.max(0, s.ends - GetTime())
            local p = left / math.max(1, s.timer or 60)
            local rr, gg, bb = timeColor(p)
            self.tbar.fill:SetWidth(math.max(0.01, (self.tbarW or 100) * p))
            self.tbar.fill:SetColorTexture(rr, gg, bb, 1)
            self.tbar:Show()
            self.acc = (self.acc or 0) + (el or 0)
            if self.acc < 0.25 then return end
            self.acc = 0
            self.timer:Set(("%d s"):format(math.ceil(left)), left < 10 and C.red or C.dim)
            self.timer:Show()
        else
            self.timer:Hide()
            self.tbar:Hide()
        end
    end)

    -- Aufbau nach Breite/Hoehe; merkt Rechtecke in f.rects (Test)
    function f:Layout(W, H)
        W = W or self:GetWidth() or 900
        H = H or self:GetHeight() or 460
        W, H = math.max(MIN_W, W), math.max(MIN_H, H)
        local R = {}
        self.rects = R
        local s = LM.session
        local mx = 12 + RAIL_W - 4
        local mw = W - mx - 12
        self.tbarW = W - 24
        put(nil, "win", "tbar", self.tbar, 12, 34, W - 24, 2)
        -- Item-Leiste links (bei vielen Items kleiner)
        local n = s and #s.items or 0
        local size = (n * 54 <= H - 90) and 48 or 38
        for i, t in ipairs(self.tabs) do
            if i <= n then put(R, "rail", "tab" .. i, t, 12, 44 + (i - 1) * (size + 6), size, size) end
        end
        -- Kopf-Karte
        put(R, "main", "head", self.headCard, mx, 44, mw, 72)
        local hx = 76
        put(R, "head", "hname", self.hname, hx, 12, mw - hx - 12, 18)
        put(R, "head", "hinfo", self.hinfo, hx, 32, mw - hx - 12, 14)
        put(R, "head", "hup", self.hup, hx, 50, mw - hx - 12, 14)
        put(R, "main", "sum", self.sum, mx, 124, mw, 16)
        -- Fussleiste + GDKP-Topf
        local fy = H - 36
        local gd = (s and s.mode or LM.Mode()) == "gdkp"
        local sum = LM.Pot()
        local potOn = gd or sum > 0
        self.potBox:SetShown(potOn)
        local listBottom = fy - 8
        if potOn then
            local py = fy - 52
            put(R, "main", "pot", self.potBox, mx, py, mw, 44)
            local sw = math.floor((mw - 160) / 4)
            for i, ps in ipairs(self.potStats) do
                put(R, "pot", "pv" .. i, ps.v, 12 + (i - 1) * sw, 6, sw - 8, 18)
                put(nil, "pot", "pl" .. i, ps.l, 12 + (i - 1) * sw, 27, sw - 8, 12)
            end
            put(R, "pot", "payout", self.payout, mw - 150, 10, 140, 24)
            listBottom = py - 8
        end
        -- rechts in der Fussleiste von rechts nach links: Runde beenden, Alle vergeben, An mich
        local x = W - 12
        local fb = {}
        for _, b in ipairs({ self.endBtn, self.awardAll, self.toMe }) do
            if b:IsShown() then
                local bw = b.fw or b:GetWidth() or 100
                x = x - bw
                put(R, "foot", "b" .. #fb, b, x, fy, bw, 24)
                fb[#fb + 1] = b
                x = x - 6
            end
        end
        if self.newBtn:IsShown() then put(R, "foot", "new", self.newBtn, mx, fy, 170, 24) end
        local hx0 = self.newBtn:IsShown() and (mx + 180) or mx
        put(R, "foot", "hint", self.hint, hx0, fy + 5, math.max(10, x - hx0 - 4), 14)
        -- Liste
        local council = s and s.mode == "council"
        self.cols = LM.Columns(mw - 8, council)
        self.colVer = self.colVer + 1
        for _, t in pairs(self.colHead) do t:Hide() end
        for _, c in ipairs(self.cols) do
            local t = self.colHead[c.key]
            put(R, "cols", c.key, t, mx + c.x + 6, 148, c.w, 12)
            t:Show()
        end
        self.list:ClearAllPoints()
        self.list:SetPoint("TOPLEFT", mx, -164)
        self.list:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", mx + mw, -listBottom)
        R[#R + 1] = { grp = "main", key = "list", x = mx, y = 164, w = mw, h = math.max(0, listBottom - 164) }
        self.list:Refresh()
    end
    return f
end

function LM.ShowMaster()
    local f = LM.master
    local fresh = not f
    if not f then
        f = buildMaster()
        LM.master = f
    end
    f.sel = f.sel or 1
    f:Show()
    LM.Refresh()
    if fresh then K.FadeIn(f, 0, 0) end
end

function LM.Refresh()
    LM.RefreshRoll()
    local f = LM.master
    if not f or not f:IsShown() then return end
    local s = LM.session
    f.modeChip:Set(s and modeText(s.mode) or L["Keine laufende Runde"], s and (MODE_COL[s.mode] or C.blue) or C.dim)
    f.modeChip:SetWidth(s and 84 or 140)
    local items = s and s.items or {}
    if f.sel > #items then f.sel = 1 end
    for _, t in ipairs(f.tabs) do t:Hide() end
    for i, it in ipairs(items) do
        local t = f.tabs[i]
        if not t then
            t = LM.ItemButton(f, 48)
            t.done = t:CreateTexture(nil, "OVERLAY", nil, 2)
            t.done:SetPoint("TOPLEFT", 2, -2) t.done:SetPoint("BOTTOMRIGHT", -2, 2)
            t.done:SetColorTexture(0, 0, 0, 0.62)
            t.check = t:CreateTexture(nil, "OVERLAY", nil, 3)
            t.check:SetSize(18, 18)
            t.check:SetPoint("CENTER")
            t.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            t.mark = t:CreateTexture(nil, "OVERLAY", nil, 3)
            t.mark:SetPoint("TOPLEFT", -8, 0) t.mark:SetPoint("BOTTOMLEFT", -8, 0)
            t.mark:SetWidth(3)
            t.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            t.nbg = t:CreateTexture(nil, "OVERLAY", nil, 4)
            t.nbg:SetSize(18, 14)
            t.nbg:SetPoint("BOTTOMRIGHT", 3, -3)
            t.nbg:SetColorTexture(C.accent2[1], C.accent2[2], C.accent2[3], 1)
            t.n = K.Text(t, 10, C.text, "CENTER")
            t.n:SetPoint("CENTER", t.nbg, "CENTER", 0, 0)
            t.n:SetDrawLayer("OVERLAY", 5)
            f.tabs[i] = t
        end
        t:SetItem(it.link)
        t.done:SetShown(it.winner ~= nil)
        t.check:SetShown(it.winner ~= nil)
        t.mark:SetShown(i == f.sel)
        t:SetAlpha((i == f.sel or it.winner) and 1 or 0.8)
        local n = 0
        for _, r in pairs(it.resp) do if r.c ~= "pass" then n = n + 1 end end
        if s.mode == "gdkp" then n = 0 for _ in pairs(it.bids or {}) do n = n + 1 end end
        t.n:SetText(n > 0 and n or "")
        t.nbg:SetShown(n > 0 and not it.winner)
        t.onClick = function() f.sel = i LM.Refresh() end
        t:Show()
    end
    local it = items[f.sel]
    f.head:SetShown(it ~= nil)
    local list = {}
    if it then
        f.head:SetItem(it.link)
        local qc = f.head.qc or C.line
        f.headCard.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
        if not K.Gradient(f.headCard.glow, "HORIZONTAL", { qc[1], qc[2], qc[3], 0.14 }, { 0, 0, 0, 0 }) then f.headCard.glow:SetColorTexture(qc[1], qc[2], qc[3], 0.05) end
        f.hname:SetText(it.link)
        local sr = ns.SoftRes and ns.SoftRes.ForItem and ns.SoftRes.ForItem(itemID(it.link)) or {}
        local cnt = 0
        for _ in pairs(it.resp) do cnt = cnt + 1 end
        local info = (L["%d Antworten"]):format(cnt)
        if #sr > 0 then
            local names = {}
            for _, w in ipairs(sr) do names[#names + 1] = ns.displayName(w) end
            info = info .. "  ·  |cffe8b44a" .. L["reserviert"] .. ": " .. table.concat(names, ", ") .. "|r"
        end
        if it.winner then info = info .. "  ·  |cff66db9e" .. L["vergeben an"] .. " " .. ns.displayName(it.winner) .. "|r" end
        f.hinfo:SetText(info)
        local up
        if ns.Upgrade and ns.Upgrade.Text then local ok, t = pcall(ns.Upgrade.Text, it.link) if ok then up = t end end
        f.hup:SetText(type(up) == "string" and (L["Fuer dich"] .. ": " .. up) or ("|cff666666" .. L["Fuer dich: kein Vergleich"] .. "|r"))
        if ns.Upgrade and ns.Upgrade.Badge then pcall(ns.Upgrade.Badge, f.head, it.link) end
        list = LM.Ranked(it)
        -- Zusammenfassung: wie viele je Wahl, wer fehlt noch
        local cn = { ms = 0, os = 0, tm = 0, pass = 0 }
        local maxV = 0
        for _, e in ipairs(list) do
            cn[e.choice] = (cn[e.choice] or 0) + 1
            if (e.votes or 0) > maxV then maxV = e.votes end
        end
        f.maxVotes = maxV
        local parts = {}
        if s.mode == "gdkp" then
            local min, hi = LM.MinBid(it)
            parts[#parts + 1] = "|cffe8b44a" .. (L["%d Gebote"]):format(#list) .. "|r"
            parts[#parts + 1] = hi > 0 and ((L["Hoechstgebot"] .. ": %d g"):format(hi)) or (L["ab %d g"]):format(min)
        else
            for _, c in ipairs(CHOICES) do parts[#parts + 1] = K.hex(c.color) .. L[c.text] .. " " .. (cn[c.key] or 0) .. "|r" end
            local grp = ns.Group.Num and ns.Group.Num() or 0
            if grp > cnt then parts[#parts + 1] = "|cff888888" .. (L["%d offen"]):format(grp - cnt) .. "|r" end
        end
        f.sum:SetText(table.concat(parts, "   "))
    else
        f.hname:SetText(L["Keine laufende Runde"])
        f.hinfo:SetText(L["Beutefenster einer Leiche oeffnen und hier 'Items aus Beutefenster' klicken - oder /oa beute [Itemlink]."])
        f.hup:SetText("")
        f.sum:SetText("")
        f.headCard.edge:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        f.headCard.glow:SetColorTexture(0, 0, 0, 0)
    end
    local lead = isLeader() and s and not s.closed
    f.awardAll:SetShown(lead and s.mode ~= "council" or false)
    f.toMe:SetShown(lead and it and not it.winner or false)
    f.endBtn:SetShown(lead or false)
    f.newBtn:SetShown(not s or s.closed or false)
    if s and not s.closed and s.mode == "council" and LM.IsCouncil() and not isLeader() then
        f.hint:SetText(L["Du stimmst ab - der Plundermeister vergibt."])
    elseif s and not s.closed and not isLeader() then
        f.hint:SetText((L["Verteilt von %s"]):format(ns.displayName(s.leader or "")))
    elseif s and s.closed then
        f.hint:SetText(L["Runde beendet."])
    else
        f.hint:SetText("")
    end
    local sum, cut, n, each = LM.Pot()
    local vals = { sum .. " g", cut .. " g", tostring(n), each .. " g" }
    for i, ps in ipairs(f.potStats) do ps.v:SetText(vals[i]) end
    f.payout:SetShown(isLeader() or false)
    f:SetHeight(math.max(f:GetHeight() or 0, MIN_H, 52 + #items * 54 + 40))
    f:Layout()
    f.list:SetData(list)
end

------------------------------------------------------------------------
-- Beutefenster: Knopf "Mit Oasis verteilen" fuer Plundermeister
------------------------------------------------------------------------
local function lootItems()
    local out = {}
    local minQ = tonumber(ns.GuildOpt("lmMinQ")) or 3
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local _, _, _, _, q = GetLootSlotInfo(slot)
        if link and (tonumber(q) or 0) >= minQ then out[#out + 1] = { link = link, slot = slot } end
    end
    return out
end
function LM.StartFromLoot()
    local items = lootItems()
    if #items == 0 then ns.print(L["Kein passendes Item im Beutefenster."]) return end
    LM.Start(items)
end
local lootBtn
ns.On("LOOT_OPENED", function()
    ns.After(0.1, function()
        if ns.db and ns.db.settings.lootHelper == false then return end
        if not (IsInGroup() and (LM.IsMasterLooter() or ns.isGroupLead())) then return end
        local items = lootItems()
        if #items == 0 then return end
        if not lootBtn then
            lootBtn = K.Button(UIParent, "", 200, 26, "primary", function() LM.StartFromLoot() lootBtn:Hide() end)
            lootBtn:SetFrameStrata("DIALOG")
        end
        lootBtn:SetLabel((L["Mit Oasis verteilen (%d)"]):format(#items))
        lootBtn:ClearAllPoints()
        if LootFrame and LootFrame:IsShown() then lootBtn:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 6, 0) else lootBtn:SetPoint("CENTER", 220, 120) end
        lootBtn:Show()
    end)
end)
ns.On("LOOT_CLOSED", function() if lootBtn then lootBtn:Hide() end end)
ns.slash.verteilen = function() LM.ShowMaster() end
end)
